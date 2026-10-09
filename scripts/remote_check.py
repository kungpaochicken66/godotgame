#!/usr/bin/env python3
"""Check a deployed town server with real game clients (operator tool).

Runs headless game clients (tests/net_bot.gd) against a live server, for example
behind a TLS proxy. The address and the invite are never printed: the invite is
read from a file by the clients themselves, not passed on the command line.

  # two invited clients see each other's change, wrong and missing invites are
  # refused, and a client reconnects; the marker is removed afterwards
  python3 scripts/remote_check.py --url wss://town.example.org/path --invite-file /path/to/invite

  # restart check: keep a marker, restart the service, then verify and clean up
  python3 scripts/remote_check.py --url ... --invite-file ... --phase mark --state-file /tmp/marker
  (restart the server)
  python3 scripts/remote_check.py --url ... --invite-file ... --phase verify --state-file /tmp/marker

  # or take address and invite from the packaged private config of an injected copy:
  python3 scripts/remote_check.py --use-private-config --game /path/to/injected/game

Exit code 0 only if every check passed. Contract: docs/deployment.md.
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_bots(godot, game, roles, common, logdir, stagger=0.0):
    import time
    procs = {}
    for role in roles:
        log = open(logdir / f'remote_{role}.log', 'w')
        procs[role] = subprocess.Popen([godot, '--headless', '--path', str(game), '--',
                                        '--driver=res://tests/net_bot.gd', f'--role={role}', *common],
                                       stdout=log, stderr=subprocess.STDOUT)
        time.sleep(stagger)
    for role, p in procs.items():
        try:
            p.wait(timeout=180)
        except subprocess.TimeoutExpired:
            p.kill()
            print(f'FAIL client {role} timed out')
    out = {}
    for role, p in procs.items():
        lines = [l for l in (logdir / f'remote_{role}.log').read_text(errors='replace').splitlines() if l.startswith('NETBOT ')]
        out[role] = (p.returncode, lines)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', help='wss:// address (or ws:// to loopback for local testing); never printed')
    ap.add_argument('--invite-file', help='file whose first line is the town invite; never printed')
    ap.add_argument('--use-private-config', action='store_true', help='read address and invite from res://private/deployment.json')
    ap.add_argument('--game', default=str(ROOT / 'game'), help='game folder (an injected packaging copy for --use-private-config)')
    ap.add_argument('--godot', default=str(ROOT / 'scripts/godot.sh'), help='Godot 4.7.2 binary (default: the project wrapper)')
    ap.add_argument('--phase', choices=['live', 'mark', 'verify'], default='live')
    ap.add_argument('--state-file', help='marker id file for --phase mark/verify')
    a = ap.parse_args()
    if not a.url and not a.use_private_config:
        ap.error('give --url or --use-private-config')
    if a.url and not (a.url.startswith('wss://') or a.url.startswith('ws://127.0.0.1') or a.url.startswith('ws://localhost')):
        ap.error('the address must start with wss:// (ws:// only to localhost)')
    if a.phase != 'live' and not a.state_file:
        ap.error('--phase mark/verify needs --state-file')
    common = []
    if a.url:
        common.append(f'--url={a.url}')
    if a.use_private_config:
        common.append('--use-private-config')
    if a.invite_file:
        common.append(f'--invite-file={Path(a.invite_file).resolve()}')
    if a.state_file:
        common.append(f'--state-file={Path(a.state_file).resolve()}')
    logdir = Path(tempfile.mkdtemp(prefix='lantern-remote-'))
    print(f'phase {a.phase}; target and invite are not shown; logs in {logdir}')
    if a.phase == 'live':
        res = run_bots(a.godot, a.game, ['remote_a', 'remote_b'], common, logdir, stagger=3.0)
        res.update(run_bots(a.godot, a.game, ['inv_wrong', 'inv_none'], common, logdir))
    elif a.phase == 'mark':
        res = run_bots(a.godot, a.game, ['remote_mark'], common, logdir)
    else:
        res = run_bots(a.godot, a.game, ['remote_verify'], common, logdir)
    ok = True
    for role, (code, lines) in res.items():
        for l in lines:
            print(l)
        if code != 0 or not any(l.endswith('DONE PASS') for l in lines):
            ok = False
    if a.phase == 'live':
        mark = [l.split()[-1] for l in res['remote_a'][1] if ' MARK ' in l]
        for tag in ('SAW', 'SAW_MOVE', 'RECONNECT_SAW'):
            seen = [l.split()[-1] for l in res['remote_b'][1] if f' {tag} ' in l]
            if not mark or seen != mark:
                print(f'FAIL the second client did not report {tag} for the first client\'s marker')
                ok = False
        if not any(' CLEANED ' in l for l in res['remote_a'][1]):
            print('FAIL the marker was not removed')
            ok = False
    if a.phase == 'mark' and ok:
        print('Marker kept. Restart the server, then run this again with --phase verify and the same --state-file.')
    print('REMOTE CHECK PASS' if ok else 'REMOTE CHECK FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
