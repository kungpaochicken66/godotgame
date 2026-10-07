#!/usr/bin/env python3
"""Multiplayer integration test over real WebSockets on this machine.

Starts a headless dedicated town server, then separate Godot client processes
("bots") that join, build a Cozy Spot together, contend for the same item, ride
the swing, ring the evening bell and put a house away and back. A fifth client
must be turned away. The server is then restarted from its save file and a new
client checks that everything persisted.

All peers are real network clients of the server, but they run on one host over
the loopback interface. This does not verify NAT traversal, the public internet,
TLS, iPad hardware or latency between different homes.

  python3 scripts/net_test.py
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = [str(ROOT / 'scripts/godot.sh'), '--headless', '--path', str(ROOT / 'game')]


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def start_server(port, save, log):
    proc = subprocess.Popen(GODOT + ['--', '--server', f'--port={port}', '--bind=127.0.0.1', f'--save={save}'],
                            stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 60
    while time.time() < deadline:
        with socket.socket() as s:
            if s.connect_ex(('127.0.0.1', port)) == 0:
                return proc
        if proc.poll() is not None:
            raise RuntimeError('server exited early')
        time.sleep(0.3)
    raise RuntimeError('server did not start listening')


def bot(role, port, logdir):
    log = open(logdir / f'bot_{role}.log', 'w')
    return subprocess.Popen(GODOT + ['--', '--driver=res://tests/net_bot.gd', f'--url=ws://127.0.0.1:{port}', f'--role={role}'],
                            stdout=log, stderr=subprocess.STDOUT)


def results(logdir, role):
    lines = (logdir / f'bot_{role}.log').read_text(errors='replace').splitlines()
    return [l for l in lines if l.startswith('NETBOT ')]


def capture(shots):
    """Rendered client plus two bot friends, for a real multiplayer screenshot (needs Xvfb)."""
    work = Path(tempfile.mkdtemp(prefix='lantern-cap-'))
    port = free_port()
    server = start_server(port, work / 'town.json', open(work / 'server.log', 'w'))
    try:
        bots = [bot('show1', port, work), bot('show2', port, work)]
        cmd = ['xvfb-run', '-a', '-s', '-screen 0 1366x1024x24', str(ROOT / 'scripts/godot.sh'), '--path', str(ROOT / 'game'),
               '--', '--driver=res://tests/net_capture.gd', f'--url=ws://127.0.0.1:{port}', f'--shots={shots}']
        log = work / 'client.log'
        with open(log, 'w') as f:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=400)
        print('\n'.join(l for l in log.read_text(errors='replace').splitlines() if l.startswith(('NETCAPTURE', 'CAP'))))
        print(f'client log: {log}')
        for b in bots:
            b.kill()
    finally:
        server.terminate()
        server.wait(timeout=20)
    return 0


def activities(work):
    """Three real clients play the activities; then a restart check."""
    save = work / 'activities.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_activities.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'act_a': bot('act_a', port, work), 'act_b': bot('act_b', port, work)}
        # Peach joins late, after the party and the second round have started.
        deadline = time.time() + 120
        while time.time() < deadline and not any('PARTY' in l for l in results(work, 'act_a')):
            time.sleep(0.5)
        time.sleep(2)
        procs['act_c'] = bot('act_c', port, work)
        for role, p in procs.items():
            try:
                p.wait(timeout=240)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
        time.sleep(3)
    finally:
        server.terminate()
        server.wait(timeout=20)
    server2 = start_server(port, save, open(work / 'server_activities2.log', 'w'))
    try:
        procs['act_check'] = bot('act_check', port, work)
        procs['act_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    hs = sorted(l.split()[-1] for role in ('act_a', 'act_b') for l in results(work, role) if ' HS ' in l)
    party = sorted(l.split()[-1] for role in ('act_a', 'act_b') for l in results(work, role) if ' PARTY ' in l)
    print('hide-and-seek roles:', hs, 'party:', party)
    if hs != ['hider', 'seeker'] or party != ['joined', 'started']:
        print('FAIL: conflicting starts must give exactly one hider and one party')
        ok = False
    return ok


def main():
    if '--activities' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-act-'))
        ok = activities(work)
        print('ACTIVITIES TEST PASS' if ok else 'ACTIVITIES TEST FAIL')
        return 0 if ok else 1
    if '--capture' in sys.argv:
        return capture(Path(sys.argv[sys.argv.index('--capture') + 1]).resolve())
    work = Path(tempfile.mkdtemp(prefix='lantern-net-'))
    save = work / 'town.json'
    port = free_port()
    print(f'work dir {work}, port {port}')
    server_log = open(work / 'server.log', 'w')
    server = start_server(port, save, server_log)
    ok = True
    try:
        procs = {'a': bot('a', port, work), 'b': bot('b', port, work)}
        time.sleep(6)
        procs['c'] = bot('c', port, work)
        time.sleep(3)
        procs['d'] = bot('d', port, work)
        # The fifth child must be turned away while four are playing.
        deadline = time.time() + 40
        while time.time() < deadline and 'joined the town server' not in ''.join(results(work, 'd')):
            time.sleep(0.5)
        procs['e'] = bot('e', port, work)
        for role, p in procs.items():
            try:
                p.wait(timeout=180)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
        time.sleep(3)  # let the debounced autosave land
    finally:
        server.terminate()
        server.wait(timeout=20)
    data = json.loads(save.read_text()) if save.exists() else {}
    print(f'save file: {len(data.get("items", []))} items, lanterns {sorted(data.get("lanterns", {}))}, evening {data.get("evening")}')
    server2 = start_server(port, save, open(work / 'server2.log', 'w'))
    try:
        check = bot('check', port, work)
        check.wait(timeout=120)
        procs['check'] = check
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    races = [l for role in ('a', 'b') for l in results(work, role) if 'RACE' in l]
    print('tabletop race:', races)
    if sorted(l.split()[-1] for l in races) != ['lost', 'won']:
        print('FAIL: expected exactly one client to win the tabletop race')
        ok = False
    print(f'server log: {work / "server.log"}')
    print('NET TEST PASS' if ok else 'NET TEST FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
