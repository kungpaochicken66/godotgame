#!/usr/bin/env python3
"""Packaging check for the private deployment config (docs/deployment.md).

Exports the iOS preset's .pck from two isolated copies of game/: one with a
placeholder private config injected, one without. The injected file must be
packed; a public copy must contain no private file. Also checks that git
ignores game/private/. Uses only placeholder values.

  python3 scripts/check_packaging.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = '{"schema": 1, "multiplayer_url": "wss://placeholder.example.org/x", "invite_code": "placeholder-invite"}\n'


def export(game, out):
    r = subprocess.run([str(ROOT / 'scripts/godot.sh'), '--headless', '--path', str(game), '--export-pack', 'iPad', str(out)],
                       capture_output=True, text=True, timeout=900)
    return r.returncode, out.read_bytes() if out.exists() else b''


def main():
    ok = True
    ignored = subprocess.run(['git', 'check-ignore', '-q', 'game/private/deployment.json'], cwd=ROOT).returncode == 0
    tracked = subprocess.run(['git', 'ls-files', 'game/private'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    print(f'git ignores game/private/: {ignored}; tracked private files: {tracked or "none"}')
    ok &= ignored and not tracked
    work = Path(tempfile.mkdtemp(prefix='lantern-pack-'))
    try:
        for name, inject in (('public', False), ('private', True)):
            copy = work / name
            shutil.copytree(ROOT / 'game', copy, ignore=shutil.ignore_patterns('private'))
            if inject:
                (copy / 'private').mkdir()
                (copy / 'private/deployment.json').write_text(PLACEHOLDER)
            code, pck = export(copy, work / f'{name}.pck')
            has_path = b'private/deployment.json' in pck
            has_value = b'placeholder.example.org' in pck
            print(f'{name}: export exit {code}, {len(pck)} bytes, packs private config: {has_path and has_value}')
            ok &= code == 0 and len(pck) > 0 and (has_path and has_value) == inject and (has_path or has_value) == inject
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print('PACKAGING CHECK PASS' if ok else 'PACKAGING CHECK FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
