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


def start_server(port, save, log, extra=()):
    proc = subprocess.Popen(GODOT + ['--', '--server', f'--port={port}', '--bind=127.0.0.1', f'--save={save}', *extra],
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


def bot(role, port, logdir, invite_file=None):
    log = open(logdir / f'bot_{role}.log', 'w')
    extra = [f'--invite-file={invite_file}'] if invite_file is not None else []
    return subprocess.Popen(GODOT + ['--', '--driver=res://tests/net_bot.gd', f'--url=ws://127.0.0.1:{port}', f'--role={role}', *extra],
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


def invites(work):
    """Optional town invite: right, wrong, missing, reconnect; start-up errors; no secret in logs."""
    secret = 'test-invite-7f3c9a'
    invite_file = work / 'invite'
    invite_file.write_text(secret + '\n')
    os.chmod(invite_file, 0o600)
    ok = True
    # A named but missing invite file stops the server (exit code 2).
    missing = subprocess.run(GODOT + ['--', '--server', f'--port={free_port()}', '--bind=127.0.0.1', f'--save={work / "x.json"}',
                                      f'--invite-file={work / "no_such_invite"}'], capture_output=True, text=True, timeout=60)
    print(f'missing invite file: exit {missing.returncode}')
    if missing.returncode != 2 or 'invite configuration error' not in missing.stdout + missing.stderr:
        print('FAIL: a missing invite file must stop the server with exit code 2')
        ok = False
    port = free_port()
    save = work / 'invite_town.json'
    server = start_server(port, save, open(work / 'server_invite.log', 'w'), [f'--invite-file={invite_file}'])
    procs = {}
    try:
        procs['inv_ok'] = bot('inv_ok', port, work, invite_file)
        deadline = time.time() + 60
        while time.time() < deadline and not any('INVITE in' in l for l in results(work, 'inv_ok')):
            time.sleep(0.5)
        procs['inv_wrong'] = bot('inv_wrong', port, work)
        procs['inv_none'] = bot('inv_none', port, work)
        procs['inv_reconnect'] = bot('inv_reconnect', port, work, invite_file)
        for role, p in procs.items():
            try:
                p.wait(timeout=120)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
    finally:
        server.terminate()
        server.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    log = (work / 'server_invite.log').read_text(errors='replace')
    every_log = log + ''.join((work / f'bot_{r}.log').read_text(errors='replace') for r in procs)
    refused = log.count('a connection was refused (wrong or missing invite)')
    print(f'server: invite required {"invite: required" in log}, refused connections {refused}')
    if 'invite: required' not in log or refused != 2:
        print('FAIL: the server must require the invite and refuse exactly two connections')
        ok = False
    if secret in every_log:
        print('FAIL: the invite appears in a log')
        ok = False
    # Refusals through a relay that holds server bytes and delivers them together
    # with the close, like a buffering TLS proxy (the production failure of r5).
    port = free_port()
    relay_port = free_port()
    server = start_server(port, work / 'held_town.json', open(work / 'server_held.log', 'w'), [f'--invite-file={invite_file}'])
    relay = subprocess.Popen([sys.executable, str(ROOT / 'scripts/delay_proxy.py'), str(relay_port), str(port), '40', '800'])
    held = {}
    try:
        time.sleep(1)
        for role in ('inv_none', 'inv_wrong', 'inv_linger'):
            held[role] = bot(role, relay_port, work, invite_file)
        held['inv_reconnect'] = bot('inv_reconnect', relay_port, work, invite_file)
        for role, p in held.items():
            try:
                p.wait(timeout=120)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out (held relay)')
                ok = False
    finally:
        relay.terminate()
        server.terminate()
        server.wait(timeout=20)
    print('through a holding relay (800 ms, delivered with the close):')
    for role, p in held.items():
        for line in results(work, role):
            print('  ' + line)
        if p.returncode != 0:
            ok = False
    # The operator tool against a local invite-only server: live, then a kept
    # marker that must survive a real server restart.
    port = free_port()
    save2 = work / 'remote_town.json'
    url = f'ws://127.0.0.1:{port}'
    tool = [sys.executable, str(ROOT / 'scripts/remote_check.py'), '--url', url, '--invite-file', str(invite_file)]
    server = start_server(port, save2, open(work / 'server_remote.log', 'w'), [f'--invite-file={invite_file}'])
    try:
        live = subprocess.run(tool, capture_output=True, text=True, timeout=400)
        mark = subprocess.run(tool + ['--phase', 'mark', '--state-file', str(work / 'marker')], capture_output=True, text=True, timeout=200)
        time.sleep(3)  # let the debounced autosave land
    finally:
        server.terminate()
        server.wait(timeout=20)
    server = start_server(port, save2, open(work / 'server_remote2.log', 'w'), [f'--invite-file={invite_file}'])
    try:
        verify = subprocess.run(tool + ['--phase', 'verify', '--state-file', str(work / 'marker')], capture_output=True, text=True, timeout=200)
    finally:
        server.terminate()
        server.wait(timeout=20)
    for name, r in (('live', live), ('mark', mark), ('verify', verify)):
        print(f'remote_check {name}: exit {r.returncode}')
        print('\n'.join('  ' + l for l in r.stdout.splitlines() if 'NETBOT' in l or 'REMOTE' in l or 'FAIL' in l))
        if r.returncode != 0:
            ok = False
        if secret in r.stdout + r.stderr or url in r.stdout + r.stderr:
            print(f'FAIL: remote_check {name} printed the invite or the address')
            ok = False
    # A loosely readable invite file starts with a warning.
    os.chmod(invite_file, 0o644)
    port = free_port()
    loose = start_server(port, save, open(work / 'server_loose.log', 'w'), [f'--invite-file={invite_file}'])
    time.sleep(1)
    loose.terminate()
    loose.wait(timeout=20)
    if 'readable by other users' not in (work / 'server_loose.log').read_text(errors='replace'):
        print('FAIL: a world-readable invite file must print a warning')
        ok = False
    return ok


def pets(work):
    """Pets and cooking with two real clients; owner leaves; restart persistence."""
    save = work / 'pets.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_pets.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'pets_a': bot('pets_a', port, work), 'pets_b': bot('pets_b', port, work)}
        for role, p in procs.items():
            try:
                p.wait(timeout=180)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
        time.sleep(3)
    finally:
        server.terminate()
        server.wait(timeout=20)
    server2 = start_server(port, save, open(work / 'server_pets2.log', 'w'))
    try:
        procs['pets_check'] = bot('pets_check', port, work)
        procs['pets_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def play(work):
    """Play ideas (snacks, display, snowman, fetch) with two real clients; restart persistence."""
    save = work / 'play.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_play.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'play_a': bot('play_a', port, work), 'play_b': bot('play_b', port, work)}
        for role, p in procs.items():
            try:
                p.wait(timeout=180)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
        time.sleep(3)
    finally:
        server.terminate()
        server.wait(timeout=20)
    server2 = start_server(port, save, open(work / 'server_play2.log', 'w'))
    try:
        procs['play_check'] = bot('play_check', port, work)
        procs['play_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def batch2(work):
    """Play ideas batch 2 (dress-up, trails, music box, tracks, poses) with two real clients; restart persistence."""
    save = work / 'b2.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_b2.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'b2_a': bot('b2_a', port, work), 'b2_b': bot('b2_b', port, work)}
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
    server2 = start_server(port, save, open(work / 'server_b2b.log', 'w'))
    try:
        procs['b2_check'] = bot('b2_check', port, work)
        procs['b2_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def r11(work):
    """r11: invitations, help-edit, music parts, animal games, leaf piles, blueprints; restart."""
    save = work / 'r11.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_r11.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'r11_a': bot('r11_a', port, work), 'r11_b': bot('r11_b', port, work)}
        for role, p in procs.items():
            try:
                p.wait(timeout=300)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'bot {role} timed out')
                ok = False
        time.sleep(3)
    finally:
        server.terminate()
        server.wait(timeout=20)
    server2 = start_server(port, save, open(work / 'server_r11b.log', 'w'))
    try:
        procs['r11_check'] = bot('r11_check', port, work)
        procs['r11_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def wear(work):
    """r12 wardrobe: two real clients see each other's outfit, seated variant and held item;
    gated and wrong-slot requests are refused; a reconnect keeps the outfit; restart."""
    save = work / 'wear.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_wear.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'wear_a': bot('wear_a', port, work), 'wear_b': bot('wear_b', port, work)}
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
    server2 = start_server(port, save, open(work / 'server_wear2.log', 'w'))
    try:
        procs['wear_check'] = bot('wear_check', port, work)
        procs['wear_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def furniture(work):
    """r2 wall and ceiling models: two real clients hang, move and remove them; the server refuses
    a pavilion under a chandelier; a reconnect and a restart keep everything."""
    save = work / 'furn.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_furn.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'furn_a': bot('furn_a', port, work), 'furn_b': bot('furn_b', port, work)}
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
    server2 = start_server(port, save, open(work / 'server_furn2.log', 'w'))
    try:
        procs['furn_check'] = bot('furn_check', port, work)
        procs['furn_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def seats(work):
    """r17 two-seat benches: three real clients. Two sit on one bamboo bench at the same moment and get
    different seats; the third is refused, then takes the seat that frees when one stands; a seat held by a
    client that disconnects is freed; after a restart the bench is kept and every seat is free."""
    save = work / 'seats.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_seats.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {r: bot(r, port, work) for r in ('seat_a', 'seat_b', 'seat_c')}
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
    server2 = start_server(port, save, open(work / 'server_seats2.log', 'w'))
    try:
        procs['seat_check'] = bot('seat_check', port, work)
        procs['seat_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def visits(work):
    """r18 animals visit houses: Sunny takes Pip home; Sky in the living room sees Pip beside her, answering
    her dance, then upstairs; Peach joins late outdoors and learns the visit; Sunny disconnects inside and
    Pip is back at the front door for everyone; after a restart nobody is visiting."""
    save = work / 'visits.json'
    port = free_port()
    server = start_server(port, save, open(work / 'server_visits.log', 'w'))
    ok = True
    procs = {}
    try:
        procs = {'visit_a': bot('visit_a', port, work), 'visit_b': bot('visit_b', port, work)}
        deadline = time.time() + 120
        while time.time() < deadline and not any('VISIT inside' in l for l in results(work, 'visit_a')):
            time.sleep(0.5)
        procs['visit_c'] = bot('visit_c', port, work)   # the late joiner
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
    server2 = start_server(port, save, open(work / 'server_visits2.log', 'w'))
    try:
        procs['visit_check'] = bot('visit_check', port, work)
        procs['visit_check'].wait(timeout=120)
    finally:
        server2.terminate()
        server2.wait(timeout=20)
    for role in procs:
        for line in results(work, role):
            print(line)
        if procs[role].returncode != 0:
            ok = False
    return ok


def silent_ws_server(port, stop):
    """A WebSocket endpoint that completes the handshake and then never sends anything (no peer id, no
    town): the shape of a server that cannot send the welcome. Standard library only."""
    import base64, hashlib, threading
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', port))
    srv.listen(4)
    srv.settimeout(0.5)
    held = []
    def run():
        while not stop.is_set():
            try:
                c, _ = srv.accept()
            except socket.timeout:
                continue
            data = b''
            while b'\r\n\r\n' not in data:
                chunk = c.recv(4096)
                if not chunk:
                    break
                data += chunk
            key = next((l.split(b':', 1)[1].strip() for l in data.split(b'\r\n') if l.lower().startswith(b'sec-websocket-key')), b'')
            accept = base64.b64encode(hashlib.sha1(key + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
            c.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
            held.append(c)   # keep it open and silent
        for c in held:
            c.close()
        srv.close()
    t = threading.Thread(target=run, daemon=True)
    t.start()
    return t


def connect(work):
    """r19-connect: joining a town bigger than Godot's 64 KiB WebSocket buffers (incident 2026-10-11 Asia/Shanghai).
    A synthetic 420-item town (about 79 KB welcome, like the real 364-item town) is joined:
      1 current server and client: the whole town arrives, every item unchanged (digest), and the save
        still holds every item afterwards (nothing truncated or deleted);
      2 server with Godot's default buffers (as shipped): the old send failure is reproduced in the server
        log, and the child is told the town is too big instead of staying on Connecting;
      3 client with Godot's default buffers (as shipped): it cannot receive the town and gives up after
        the welcome timeout;
      4 current server with a lowered welcome limit: the defined boundary refuses clearly."""
    ok = True
    fixture = work / 'town_fixture.json'
    out = subprocess.run(GODOT + ['-s', 'res://tests/town_fixture.gd', '--', f'--out={fixture}', '--items=420'],
                         capture_output=True, text=True, timeout=300)
    line = next((l for l in out.stdout.splitlines() if l.startswith('FIXTURE')), '')
    print(line)
    if not line or int(line.split()[3]) <= 65535:
        print('FAIL: the fixture must be above 64 KiB')
        return False
    cases = [
        ('current', [], 'connect_big', []),
        ('legacy_server', ['--net-buffer=-1'], 'connect_refused', []),
        ('legacy_client', [], 'connect_stuck', ['--net-buffer=-1']),
        ('limit', ['--welcome-limit=60000'], 'connect_refused', []),
    ]
    for name, server_extra, role, bot_extra in cases:
        save = work / f'{name}.json'
        save.write_bytes(fixture.read_bytes())
        port = free_port()
        log = work / f'server_{name}.log'
        server = start_server(port, save, open(log, 'w'), server_extra)
        try:
            log_b = open(work / f'bot_{role}_{name}.log', 'w')
            p = subprocess.Popen(GODOT + ['--', '--driver=res://tests/net_bot.gd', f'--url=ws://127.0.0.1:{port}', f'--role={role}',
                                          f'--fixture={fixture}', *bot_extra], stdout=log_b, stderr=subprocess.STDOUT)
            try:
                p.wait(timeout=120)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f'{name}: bot timed out')
                ok = False
            time.sleep(1.5)
        finally:
            server.terminate()
            server.wait(timeout=20)
        lines = [l for l in (work / f'bot_{role}_{name}.log').read_text(errors='replace').splitlines() if l.startswith('NETBOT ')]
        for l in lines:
            print(f'[{name}] {l}')
        if p.returncode != 0:
            ok = False
        slog = log.read_text(errors='replace')
        if name == 'legacy_server':
            seen = 'could not send the town' in slog and 'limit 61439' in slog
            print(f'[{name}] {"PASS" if seen else "FAIL"} the server refused the town because it exceeds Godot\'s default 64 KiB buffer')
            ok = ok and seen
        by_id = lambda items: {i['id']: i for i in items} if isinstance(items, list) else dict(items)
        kept = by_id(json.loads(save.read_text()).get('items', []))
        want = by_id(json.loads(fixture.read_text()).get('items', []))
        same = all(kept.get(k) == v for k, v in want.items())
        print(f'[{name}] {"PASS" if same else "FAIL"} the save still holds every fixture item unchanged ({len(kept)} items, fixture {len(want)})')
        ok = ok and same
    # 5 a server that accepts the connection but never sends the town: the client gives up at the timeout.
    import threading
    stop = threading.Event()
    port = free_port()
    t = silent_ws_server(port, stop)
    log_b = open(work / 'bot_connect_silent.log', 'w')
    p = subprocess.Popen(GODOT + ['--', '--driver=res://tests/net_bot.gd', f'--url=ws://127.0.0.1:{port}', '--role=connect_silent',
                                  f'--fixture={fixture}'], stdout=log_b, stderr=subprocess.STDOUT)
    try:
        p.wait(timeout=90)
    except subprocess.TimeoutExpired:
        p.kill()
        print('silent: bot timed out')
        ok = False
    stop.set()
    t.join(timeout=5)
    for l in (work / 'bot_connect_silent.log').read_text(errors='replace').splitlines():
        if l.startswith('NETBOT '):
            print(f'[silent] {l}')
    if p.returncode != 0:
        ok = False
    return ok


def main():
    if '--connect' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-connect-'))
        ok = connect(work)
        print(f'work dir {work}')
        print('CONNECT TEST PASS' if ok else 'CONNECT TEST FAIL')
        return 0 if ok else 1
    if '--visits' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-visits-'))
        ok = visits(work)
        print(f'work dir {work}')
        print('VISITS TEST PASS' if ok else 'VISITS TEST FAIL')
        return 0 if ok else 1
    if '--seats' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-seats-'))
        ok = seats(work)
        print(f'work dir {work}')
        print('SEATS TEST PASS' if ok else 'SEATS TEST FAIL')
        return 0 if ok else 1
    if '--furniture' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-furn-'))
        ok = furniture(work)
        print(f'work dir {work}')
        print('FURNITURE TEST PASS' if ok else 'FURNITURE TEST FAIL')
        return 0 if ok else 1
    if '--wear' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-wear-'))
        ok = wear(work)
        print(f'work dir {work}')
        print('WEAR TEST PASS' if ok else 'WEAR TEST FAIL')
        return 0 if ok else 1
    if '--r11' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-r11-'))
        ok = r11(work)
        print(f'work dir {work}')
        print('R11 TEST PASS' if ok else 'R11 TEST FAIL')
        return 0 if ok else 1
    if '--batch2' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-b2-'))
        ok = batch2(work)
        print(f'work dir {work}')
        print('BATCH2 TEST PASS' if ok else 'BATCH2 TEST FAIL')
        return 0 if ok else 1
    if '--play' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-play-'))
        ok = play(work)
        print(f'work dir {work}')
        print('PLAY TEST PASS' if ok else 'PLAY TEST FAIL')
        return 0 if ok else 1
    if '--pets' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-pets-'))
        ok = pets(work)
        print(f'work dir {work}')
        print('PETS TEST PASS' if ok else 'PETS TEST FAIL')
        return 0 if ok else 1
    if '--invites' in sys.argv:
        work = Path(tempfile.mkdtemp(prefix='lantern-inv-'))
        ok = invites(work)
        print(f'work dir {work}')
        print('INVITE TEST PASS' if ok else 'INVITE TEST FAIL')
        return 0 if ok else 1
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
