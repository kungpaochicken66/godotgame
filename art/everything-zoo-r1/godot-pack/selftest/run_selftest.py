#!/usr/bin/env python3
"""Self-test of check.gd: the right fixture must pass every check, and each wrong one must fail the
check it was made to fail (and only for its own reason). Python 3 standard library only.

  python3 art/everything-zoo-r1/godot-check/selftest/run_selftest.py --godot <godot binary> --work <empty dir>

It copies the pack's project, post-import and checker into --work, writes the fixtures in plain
Python (make_fixtures.py, shaped like the Blender export), imports them with this project's
post-import, runs check.gd and compares the report with the expected failures. Exit 0 when the checker
behaves; prints SELFTEST PASS or SELFTEST FAIL.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.dirname(HERE)

# Fixture -> words that must appear in a failed check of that fixture (lower case).
EXPECTED = {
    "fx_good": None,
    "fx_no_colour": ["every vertex has a colour"],
    "fx_one_colour": ["the colours vary"],
    "fx_wrong_height": ["height"],
    "fx_floating": ["stands on the ground"],
    "fx_textured": ["no texture"],
    "fx_metal": ["matte"],
    "fx_two_meshes": ["exactly one mesh"],
    "fx_double_sided": ["culls back faces"],
    "fx_wrong_sha": ["sha-256"],
}


def run(cmd, log):
    with open(log, "w") as f:
        p = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
    return p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--work", required=True)
    a = ap.parse_args()
    work = os.path.abspath(a.work)
    if os.path.exists(work) and os.listdir(work):
        print("SELFTEST FAIL: --work must be empty")
        return 1
    os.makedirs(work, exist_ok=True)
    for f in ["project.godot", "check.gd"]:
        shutil.copy(os.path.join(CHECK, f), work)
    shutil.copytree(os.path.join(CHECK, "import"), os.path.join(work, "import"))
    logs = os.path.join(work, "logs")
    os.makedirs(logs)
    g = a.godot
    codes = {
        "fixtures": run([sys.executable, "-I", os.path.join(HERE, "make_fixtures.py"), work], os.path.join(logs, "fixtures.log")),
        "import": run([g, "--headless", "--path", work, "--import"], os.path.join(logs, "import.log")),
        "check": run([g, "--headless", "--path", work, "-s", "res://check.gd"], os.path.join(logs, "check.log")),
    }
    report = json.load(open(os.path.join(work, "check_report.json")))
    problems = []
    if codes["fixtures"] != 0:
        problems.append("making the fixtures exited %d" % codes["fixtures"])
    if codes["check"] == 0:
        problems.append("the checker passed a set with wrong fixtures (exit 0)")
    for aid, words in EXPECTED.items():
        rows = report["assets"].get(aid, [])
        failed = [r["check"].lower() for r in rows if not r["ok"]]
        if not rows:
            problems.append("%s: not checked at all" % aid)
        elif words is None and failed:
            problems.append("%s: the right fixture failed: %s" % (aid, failed))
        elif words is not None:
            if not any(w in f for w in words for f in failed):
                problems.append("%s: did not fail its check %s (failed: %s)" % (aid, words, failed))
            if aid != "fx_good" and len(failed) > 2:
                problems.append("%s: failed more than its own reason: %s" % (aid, failed))
    summary = {"exit_codes": codes, "problems": problems, "checks": report.get("checks"),
               "failures_seen": report.get("failures"), "engine": report.get("engine")}
    json.dump(summary, open(os.path.join(work, "selftest_result.json"), "w"), indent=2)
    for p in problems:
        print("PROBLEM " + p)
    print("SELFTEST %s: %d fixtures, %d problems" % ("PASS" if not problems else "FAIL", len(EXPECTED), len(problems)))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
