#!/usr/bin/env python3
"""Freeze reviewed file lists and render a sealed game candidate on macOS.

No network, agent dispatch, package installation or Git mutation is performed.
See docs/dual-host-modeling.md for the human/agent handoff contract.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import subprocess
import time
import uuid

LOCALES = ["en", "zh-CN", "ja", "es", "fr", "de"]
ENGINE = "4.7.2.stable.official.ed1daf0bf"
DENIED = {".git", ".godot", ".aws", ".ssh", ".codex", ".cc-runtime",
          "__pycache__", "node_modules", "pre_integration_backup"}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def relative(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or ".." in path.parts
            or str(path) != name or DENIED.intersection(path.parts)
            or any(p.startswith(".env") for p in path.parts)
            or path.suffix in {".pem", ".key"}):
        raise ValueError(f"Unsafe or private candidate path: {name!r}")
    return path


def file_at(root, name):
    path = root / relative(name)
    current = root
    for part in relative(name).parts:
        current /= part
        if current.is_symlink():
            raise ValueError(f"Symlinks are not accepted: {name}")
    if not path.is_file():
        raise ValueError(f"Missing regular file: {name}")
    return path


def verify(candidate, expected=None):
    manifest_path = candidate / "manifest.json"
    candidate_id = digest(manifest_path)
    if expected and candidate_id != expected:
        raise ValueError("Manifest hash differs from the Orca handoff")
    manifest = json.loads(manifest_path.read_text())
    if manifest["schema"] != 1 or manifest["locales"] != LOCALES:
        raise ValueError("Unsupported schema or language scope")
    source = candidate / "source"
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Candidate source must be a real directory")
    actual = {p.relative_to(source).as_posix() for p in source.rglob("*") if p.is_file() or p.is_symlink()}
    if actual != set(manifest["files"]):
        raise ValueError("Missing or extra candidate files")
    for name, record in manifest["files"].items():
        path = file_at(source, name)
        if (path.stat().st_size != record["bytes"] or digest(path) != record["sha256"]
                or path.stat().st_mode & 0o111 != record["executable"]):
            raise ValueError(f"Candidate content changed: {name}")
    return manifest, candidate_id


def seal(root, output, file_list, base):
    names = sorted(set(file_list.read_text().splitlines()))
    if not names:
        raise ValueError("An explicit, reviewed file list is required")
    records = {}
    for name in names:
        path = file_at(root, name)
        records[name] = {"bytes": path.stat().st_size, "sha256": digest(path),
                         "executable": path.stat().st_mode & 0o111}
    output.mkdir(parents=True, exist_ok=False)
    for name in names:
        dest = output / "source" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_at(root, name), dest)
    # Detect edits during copying. The producer must also hold these inputs still.
    for name, record in records.items():
        if digest(file_at(root, name)) != record["sha256"]:
            raise ValueError(f"Producer changed input during sealing: {name}")
    manifest = {"schema": 1, "base_commit": base, "engine": ENGINE,
                "locales": LOCALES, "files": records}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    _, candidate_id = verify(output)
    print(candidate_id)


def run_stage(argv, log, timeout):
    started = time.monotonic()
    with log.open("w") as stream:
        process = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    return {"argv": argv, "exit_code": code, "seconds": round(time.monotonic() - started, 2)}


def stage_passed(code, content, marker):
    return (code == 0 and (marker is None or marker in content)
            and not re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|FAIL\b)", content))


def render(candidate, output, godot, expected, timeout):
    if platform.system() != "Darwin":
        raise ValueError("This runner is for a logged-in Mac desktop, not EC2/Xvfb")
    manifest, candidate_id = verify(candidate, expected)
    version = subprocess.check_output([str(godot), "--version"], text=True, timeout=20).strip()
    if version != manifest["engine"]:
        raise ValueError(f"Godot mismatch: {version!r} != {manifest['engine']!r}")
    for name in ("game/project.godot", "game/tests/capture_tour.gd", "game/tests/dock_tour.gd"):
        file_at(candidate / "source", name)
    if "game/override.cfg" in manifest["files"]:
        raise ValueError("Candidate already has override.cfg; review isolation before running")
    output.mkdir(parents=True, exist_ok=False)
    # A host-local lock prevents two calls from rendering at the same time.
    lock = Path(__file__).resolve().parents[1] / "build/dual-host/.render.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.mkdir(exist_ok=False)
    report = {"candidate_id": candidate_id, "base_commit": manifest["base_commit"],
              "engine": version, "engine_sha256": digest(godot),
              "platform": platform.platform(), "locales": LOCALES,
              "status": "failed", "visual_review": "pending", "device_validation": "not_run", "stages": []}
    try:
        work = output / "work"
        shutil.copytree(candidate / "source", work)
        # Only the disposable work copy gets an isolated user-data directory.
        user_dir = "LanternLane-validation/" + uuid.uuid4().hex
        override = work / "game/override.cfg"
        override.write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir + '"\n')
        report["user_data_directory_name"] = user_dir
        shots = output / "screenshots"
        shots.mkdir()
        common = [str(godot), "--path", str(work / "game"), "--audio-driver", "Dummy"]
        graphics = ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]
        stages = [("import", common + ["--headless", "--import"], None),
                  ("tour", common + graphics + ["--", "--driver=res://tests/capture_tour.gd",
                   "--shots=" + str(shots / "tour"), "--locales=" + ",".join(LOCALES)], "TOUR PASS: 0 failures")]
        for tag, resolution, insets in (("ipad", "1366x1024", "0,0,0,0"),
                ("ipadair", "1475x1024", "0,0,0,32"), ("iphone", "2208x1024", "154,0,154,55")):
            stages.append(("dock-" + tag, common + graphics + ["--resolution", resolution, "--",
                           "--driver=res://tests/dock_tour.gd", "--shots=" + str(shots / tag),
                           "--tag=" + tag, "--safe-insets=" + insets], f"DOCK {tag} PASS: 0 failures"))
        failed = []
        for name, argv, marker in stages:
            log = output / (name + ".log")
            result = run_stage(argv, log, timeout)
            result["name"] = name
            report["stages"].append(result)
            content = log.read_text(errors="replace")
            result["passed"] = bool(stage_passed(result["exit_code"], content, marker))
            if not result["passed"]:
                failed.append(name)
                if name == "import":
                    raise ValueError(f"Import failed; see {log}")
            print(f"{'PASS' if result['passed'] else 'FAIL'} {name}", flush=True)
        for folder in ("tour", "ipad", "ipadair", "iphone"):
            if not list((shots / folder).glob("*.png")):
                raise ValueError(f"No screenshots produced: {folder}")
        # Tests may create imports/user data, but may not alter sealed source files.
        for name, record in manifest["files"].items():
            if digest(file_at(work, name)) != record["sha256"]:
                raise ValueError(f"Test changed an input: {name}")
        verify(candidate, expected)
        if failed:
            raise ValueError("Failed stages (all logs retained): " + ", ".join(failed))
        report["status"] = "automated_render_checks_passed"
    except BaseException as exc:
        report["error"] = str(exc)
        raise
    finally:
        report["evidence"] = {p.relative_to(output).as_posix(): digest(p)
                              for p in output.rglob("*") if p.is_file() and "work" not in p.relative_to(output).parts}
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("seal")
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--files-from", type=Path, required=True)
    p.add_argument("--base-commit", required=True)
    p = sub.add_parser("verify")
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--expected", required=True)
    p = sub.add_parser("render")
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--expected", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--godot", type=Path, required=True)
    p.add_argument("--timeout", type=int, default=1800, help="Maximum seconds per stage")
    args = parser.parse_args()
    if args.command == "seal":
        seal(args.root.resolve(), args.output.resolve(), args.files_from, args.base_commit)
    elif args.command == "verify":
        print(verify(args.candidate.resolve(), args.expected)[1])
    else:
        render(args.candidate.resolve(), args.output.resolve(), args.godot.resolve(), args.expected, args.timeout)


if __name__ == "__main__":
    main()
