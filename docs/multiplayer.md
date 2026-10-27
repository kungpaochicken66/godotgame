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
- Spaces: `town`, or a cottage room `<cottage id>:<floor>:<room>`. Player state carries the exact room, so friends in other rooms (or other houses) are not drawn. Furniture edits go to the room's space.
- Animal friends: the authority simulates them and broadcasts `Animals.ev_animals` (6 floats per animal, 4 Hz, unreliable). They are not saved and never touch shared town data ([animals.md](animals.md)).
- Protocol version 4 (2: three-story houses and the larger town; 3: table-top decorations, where `place` and `move` carry a host id; 4: device player ids sent with `rq_join`, and the activities: wishes, presents, gardens, hearts and visits, weather, photo ideas, hide-and-seek and the dance party, carried by the `Activities` autoload). An older app gets "Please update the app to play together."
- Activities: the authority runs every activity rule (one wish completion even with simultaneous edits; it alone wraps and unwraps presents; it holds the hidden acorn and sends each seeker only a warmth level; it grows gardens, records hearts, visits and photo ideas, and sets the weather). Wishes, presents, gardens, hearts, visits, photo ideas and weather are saved with the town; hide-and-seek and the party are session-only ([proposals](../design/playfulness-proposals.md)).
- Protocol 5 adds the invite handshake ([deployment.md](deployment.md)); 6 the r9 play actions (snacks, snowman faces, "On display", fetch); 7 the r10 play actions (`dress`, `trail`, `music`, `music_play`, `track`; events `ev_avatar`, `ev_trail`, `ev_track`; poses ride on `rq_emote`); 8 the r11 actions (`invite`, `invite_reply`, `animal_play`, `boat`, `leaves`, `blueprint`, `music_part`, `starter_trail`, `dress` with 4 arguments; events `ev_invite` and `ev_invite_joined` go only to the one player concerned, `ev_boat`, `ev_leaves`, `ev_music_parts`, `Animals.ev_fountain`). Invitation cards, help-edit helpers and music parts live on the authority only and are never saved. 9 adds the r12 `wear` action (2 arguments: slot, wearable id; the look travels in `ev_avatar` and join snapshots, no new event). Apps and server must be updated together; a different number is refused kindly. **10 (r18)** adds `animal_visit` (2 arguments: animal, on) and the reliable `Animals.ev_guests` event (who is visiting with whom; also sent to every joining player); the animals' compact state is unchanged. The released r13b apps and the HK server are protocol 9; protocol 10 must be released to the apps and the server together (not done; [design/animal-visits.md](../design/animal-visits.md)).
- The engine's own peer relaying (`SceneMultiplayer.server_relay`) is off since r10: clients only ever talk to the authority, and with relaying off a friend who leaves is never announced to a connection that is already closing.
- **Joining a big town (r19-connect, incident 2026-10-11 Asia/Shanghai).**
  - **The incident:** the whole town is sent to a joining player in one welcome message. The shipped r13b used Godot's default 64 KiB WebSocket buffers. The real town reached 364 items (a 75.6 KB welcome), so the server could not send it (`ERR_OUT_OF_MEMORY` in the log) and both apps stayed on Connecting. Raising only the server's buffer does not help shipped apps: their 64 KiB inbound buffer cannot receive the town.
  - **The fix:**
    - every peer (client, hosted town, dedicated server) is made by `Session._new_peer()` with `NET_BUFFER_BYTES` = 4 MiB inbound and outbound, set before `create_*`;
    - the authority measures the welcome and refuses it clearly ("This town is too big to join right now.") above `WELCOME_LIMIT` = 3 MiB, or above its peer's real outbound buffer. Godot's `rpc_id` still returns OK when a send is too big, so the check comes first;
    - nothing is truncated or deleted;
    - a client that loses the connection before the town arrives, or gets no town within `WELCOME_TIMEOUT` = 20 s, ends in "failed", so the menu says it could not reach the town instead of staying on Connecting.
  - **Bounds:** a welcome costs about 190-210 bytes per item. The densest town the unit test builds within today's caps (52 houses, every room at 40 items, 300 outdoor items: 12786 items) is 2.38 MB, under the 3 MiB limit.
  - **Decision: chunked snapshots are not needed under the current caps.** If the caps grow so that `test_welcome_bound` fails, the welcome must be chunked rather than the buffer raised again.
  - **Memory:** up to 8 MiB of buffers per connection (the server holds at most 4 players plus pending joins).
  - **Release:** the wire format is unchanged (protocol 10, as in r18b). Apps and server still need the coordinated protocol 9 → 10 release; shipped r13b apps are refused kindly with "Please update the app to play together." Tests: `python3 scripts/net_test.py --connect`.
- Release r1 models need no protocol change: modeled items are ordinary catalog kinds, and wall and ceiling items carry their mount height in the item data.
- Table tops: the authority applies requests in order, so when two children drop a decoration on the same table at once, exactly one succeeds and the other gets "There is already something on top." (tested with two real client processes).
- Rules enforced on the server: four-player limit, protocol version check, 10 s join timeout, item locks, seat occupancy (the first free seat of an item; a child already on it keeps their seat; r17), no moving occupied items or houses with someone in any of their rooms, and avatar sanitizing (preset nicknames only; only accepted wearables in their own slot).
- Persistence: debounced atomic save (`.tmp`, then rename) with a `.bak`, loaded tolerantly (malformed entries are dropped, not fatal). Clients show "Town saved" and connection state. Disconnects pause editing and offer Reconnect.
- Privacy by design: no accounts, no free text, no chat, no location. Nicknames come from a fixed list.

## Run a server

```sh
scripts/godot.sh --headless --path game -- --server --port=9080 --bind=127.0.0.1 --save=user://town_server.json
```

`--bind=*` (the default) listens on all interfaces. Clients use "Play with friends", then enter the server address (for example `ws://192.168.1.20:9080` on a LAN, or `wss://town.example.org` in production).

## Tested here

`python3 scripts/net_test.py` starts a real dedicated server process and five separate client processes connecting over loopback WebSockets on this host. It then restarts the server from its save file and connects another client. See [validation.md](validation.md) for the latest results. These clients are real network peers, but they are scripted, headless and on one machine. This does **not** test home-NAT traversal, TLS, real internet latency, iPad networking or app suspension.

`python3 scripts/net_test.py --activities` runs the activities with real client processes: conflicting starts, a late joiner, presents, hearts and a server restart.

`python3 scripts/net_test.py --capture tools/shots` connects one rendered client with two scripted friends and saves a screenshot.

## Production blockers (need an owner decision)

1. **Hosting**: choose and pay for a small VM/container, or a game backend. Not provisioned: no infrastructure purchase or network rule change was authorized.
2. **TLS + domain**: iPadOS App Transport Security expects `wss://`. Put a reverse proxy (e.g. Caddy or nginx) in front of the server, or configure Godot `TLSOptions` with a certificate.
3. **Access control**: an optional per-town invite exists since protocol 5 (`--invite-file`, checked in a join handshake before any town data or player slot; see [deployment.md](deployment.md)). Without an invite file anyone with the address can join, which suits LAN play only. Consider a parental gate around "Play with friends".
4. **Child privacy**: review COPPA/GDPR-K obligations before collecting anything. The current design collects nothing beyond a preset nickname in memory, plus the shared town layout.
5. **Operations**: a process supervisor (systemd), backups of the save file, and monitoring.
6. **Real-world test**: two to four iPads on different home networks, including one on mobile data.

## Apple TV candidate (atv-r20-controller)

- **Unchanged:** the wire protocol (10), the save schema (2) and the HK server. The TV app joins the same server as iPhone and iPad.
- **No typing on a TV:** the address and invite come only from the private deployment config the Mac injects, and the join screen never shows the address. Without one, Join is off.
- **Real WSS compatibility** with the current HK server must be tested on the device before any acceptance ([tv-controller.md](../design/tv-controller.md)).

