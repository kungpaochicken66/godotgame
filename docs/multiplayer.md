# Cross-Home Multiplayer

Goal: two to four children, each at home on a different internet connection, play in one persistent town. The town must keep existing when everyone leaves.

## Options evaluated

| Approach | Works across home NATs | Town survives everyone leaving | Operations | Verdict |
|---|---|---|---|---|
| One iPad hosts (ENet/WebSocket listen) | No, unless a parent forwards a port; carrier-grade NAT often blocks it entirely | No: the town lives on the host iPad | None | LAN and testing only |
| WebRTC peer-to-peer | Usually, with STUN; needs TURN for strict NATs | No, unless a server also stores it | Signaling server + TURN relay | More moving parts than a server, still needs one |
| Hosted relay/backend services (e.g. Photon, Nakama Cloud, Epic Online Services) | Yes | Depends on the service | Third-party accounts, terms, child-privacy review, often fees | Possible later; external accounts not authorized here |
| **Small authoritative town server** (headless Godot, WebSocket over TLS) | **Yes**: every iPad makes an outbound connection | **Yes**: the server saves the town to disk | One small VM or container, a domain name and a TLS certificate | **Recommended** |

**Recommendation:** run the same Godot project headless as a dedicated server (`--server`), behind a TLS reverse proxy (`wss://`). The town is tiny (tens of KB, four players), so the smallest cloud instance is enough. The server is authoritative: it validates every edit with the same `TownModel` rules the clients use, then saves and broadcasts. Clients never trust each other.

## Implemented

- `game/scripts/net/session.gd` (autoload) holds all networking, using Godot's high-level multiplayer API over `WebSocketMultiplayerPeer`. The same code runs:
  - **solo**: `OfflineMultiplayerPeer`, this device is the authority, saved to `user://town_solo.json`;
  - **host**: a listening WebSocket server plus a local player (LAN/testing);
  - **client**: joins a URL (`ws://` or `wss://`);
  - **server**: headless dedicated, no local player.
- Protocol: clients send `rq_join(avatar, protocol)`, a validated `rq_action(method, req, args)` with an argument-count whitelist, unreliable `rq_state` at 10 Hz for movement, and `rq_emote`. The server replies `ev_result` and broadcasts `ev_item`, `ev_removed`, `ev_lock`, `ev_seats`, `ev_lantern`, `ev_evening`, `ev_emote`, `ev_saved` and player join/leave events. A late joiner receives a full snapshot (`ev_welcome`).
- Rules enforced on the server: four-player limit, protocol version check, 10 s join timeout, item locks, seat occupancy, no moving occupied items or houses with someone inside, and avatar sanitizing (preset nicknames only).
- Persistence: debounced atomic save (`.tmp`, then rename) with a `.bak`, loaded tolerantly (malformed entries are dropped, not fatal). Clients show "Town saved" and connection state. Disconnects pause editing and offer Reconnect.
- Privacy by design: no accounts, no free text, no chat, no location. Nicknames come from a fixed list.

## Run a server

```sh
scripts/godot.sh --headless --path game -- --server --port=9080 --bind=127.0.0.1 --save=user://town_server.json
```

`--bind=*` (the default) listens on all interfaces. Clients use "Play with friends", then enter the server address (for example `ws://192.168.1.20:9080` on a LAN, or `wss://town.example.org` in production).

## Tested here

`python3 scripts/net_test.py` starts a real dedicated server process and five separate client processes connecting over loopback WebSockets on this host. It then restarts the server from its save file and connects another client. See [validation.md](validation.md) for the latest results. These clients are real network peers, but they are scripted, headless and on one machine. This does **not** test home-NAT traversal, TLS, real internet latency, iPad networking or app suspension.

`python3 scripts/net_test.py --capture tools/shots` connects one rendered client with two scripted friends and saves a screenshot.

## Production blockers (need an owner decision)

1. **Hosting**: choose and pay for a small VM/container, or a game backend. Not provisioned: no infrastructure purchase or network rule change was authorized.
2. **TLS + domain**: iPadOS App Transport Security expects `wss://`. Put a reverse proxy (e.g. Caddy or nginx) in front of the server, or configure Godot `TLSOptions` with a certificate.
3. **Access control**: currently anyone with the address can join. Before a public address exists, add a per-town secret invite code that the server checks in `rq_join` (a small change). Consider a parental gate around "Play with friends".
4. **Child privacy**: review COPPA/GDPR-K obligations before collecting anything. The current design collects nothing beyond a preset nickname in memory, plus the shared town layout.
5. **Operations**: a process supervisor (systemd), backups of the save file, and monitoring.
6. **Real-world test**: two to four iPads on different home networks, including one on mobile data.
