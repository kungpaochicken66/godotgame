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
- **Protocol 11 (candidate `contraptions-life`, not released):** request `press` (a contraption's big button); events `ev_trigger(id)`, `ev_react(id, from, effect, on)` and `Animals.ev_focus({species: {id, why}})`; a 15th animal action (`sniff`) appended to the broadcast list. The authority runs each chain one hop every 450 ms and decides what each animal is busy with ([design](../design/contraptions-and-town-life.md)).
  - **Release:** apps and the town server must be updated together (10 → 11). Saves stay schema 2: a lamp carries the optional `"on": true` only while switched on.
  - The paused R21 branch also claimed protocol 11 and schema 3 for different changes. It must take the next free numbers when it resumes.
- **Protocol 12 (candidate `puzzle-rides`, not released):** requests `puzzle` (a key, dial or chest by id), `puzzle_reset` (a space) and `ride` (a cart station's id and `board`, `go` or `stop`; getting off is the existing `stand`); events `ev_puzzle(space, progress)` and `ev_ride(station, ride)` ([design](../design/puzzle-rooms-and-rides.md)).
  - **Puzzle progress is shared and authoritative:** one record per space on the solo device, host or server (`found` keys, what each dial shows, `open`, up to four helpers' names). Every use is checked for the child's space and distance. A fresh puzzle is computed the same on every device from the town alone, so only changes travel. Anyone standing in the space may start it again; ordinary edit rules (including On display) decide who may change its parts, and any change to a part starts it again. An opened puzzle with nobody left in its space starts again by itself.
  - **A ride is authoritative:** the server holds who is in the cart (the ordinary `seats` record), the route computed from the town as it is now, the distance along it and where the ride ends; each device draws the cart from the same route and distance with its own clock. Getting up, sitting elsewhere or a dropped connection frees the seat and sends the cart home. The station cannot be moved or put away under a rider. Rails changed under way re-route the cart, or stop it where it stands.
  - **Late joiners** get puzzles under way and carts that are out right after the town.
  - **Saves stay schema 2.** Neither puzzle progress nor rides are saved. The ten new kinds are ordinary items; a build without them drops them on load.
  - **Release:** apps and the town server must be updated together (11 → 12). The paused R21 branch must take the next free numbers.
- **Protocol 13 (candidate `town-play`, not released):** requests `lamp`, `pixel`, `echo_leave`, `echo_delete`, `echo_answer`, `echo_seen`, `animal_ride`; events `ev_lamplight(names)` and `Animals.ev_riders({kind: station})`; hellos travel as the shared `echoes` data ([design](../design/town-evenings-and-more.md)).
  - **Checked by the authority:** a lamp post is lit from within 2.2 m; a square is painted from within 2.6 m, one square per request, not in a place on display by someone else, squares 0 to 63 and colors 0 to 8 only; a hello is exactly three emotes from the fixed list, left where the authority knows the child to be; an answer is one emote from the list, from within 2.8 m, never to one's own hello; only its maker's request removes a hello; an animal gets into a trailer only for a child seated in that cart at its station.
  - **Friend echoes are bounded:** one per player per town, at most 12 per town and 8 answers each, seven days (cleared when a town loads, when someone joins, after edits and every ten minutes), names and looks from the game's fixed lists only. Whatever a client sends is rebuilt from those lists before it is stored or shown.
  - **Saves stay schema 2** with optional data (a board's `pix`, the town's `echoes`). The evening moment and passengers are not saved.
  - **Release:** apps and the town server must be updated together (12 → 13).
- **Protocol 14 (candidate `zoo`, not released):** the zoo ([contract](zoo-engineering-standard.md), [design](../design/zoo-and-world-journeys.md)). Requests `travel` (1 argument: `"town"` or `"zoo"`), `zoo_use` (1: a station id) and `zoo_offer` (1: a resident id); a new autoload `Zoo` with `ev_zoo_state` (the packed animals, 4 Hz, unreliable) and `ev_zoo_events` (reliable); `ev_town_data` learns the key `maps` (the discovery log).
  - **Protocol 15 (zoo r2):** four residents are appended to `ZooMap.ORDER` (Bao, Mabel, Pebble, Flip), so the packed zoo state is longer. Protocol 14 clients cannot join.
  - **Protocol 16 (city r1):** the city district ([design](../design/city-district.md)).
    - **Travel:** `travel` accepts `"city"` from town. The arrival is the first free place at the bus stop (`CityMap.ARRIVALS`).
    - **Player state:** it carries `level` (the floor, terrace, skywalk or stair a child is on; absent on the ground). The authority accepts only a level that exists at that point (`CityNav.has_place`).
    - **Requests:** `city_use` (1: an interaction key), `city_board`, `city_off` and `city_release` (0). The authority checks the map, the level, reach (1.4 m) and whether the place is taken.
    - **Autoload `City`:** `ev_city_state` (the packed state at 4 Hz, unreliable, sent at once on every change and to every arrival) and `ev_city_effect` (reliable: `ride_off`, `order`, `shop`).
    - **The wheel:** boarding only at the bottom within the boarding window, two seats per gondola. Getting off happens at the bottom; the authority places the child back on the platform.
    - **Holding a place:** a child who walks away from a seat or machine, or changes level, is stood up. A dropped child's places are freed.
    - **Shared clock:** the city's clock runs only while someone is there. The walkers are a pure function of it; the vehicles (which stop for a child ahead of them) are in the packed state. So every client draws the same street.
    - **Saves:** schema 3 unchanged; nothing of the city is saved.
    - **Versions:** protocol 15 clients cannot join.
  - **Protocol 17 (city r2):** the packed city state is version 2. Each vehicle carries `(s, v, dwell, stop)`: three buses and two cars in one lane that never pass, keep 3 m apart and stop for children; buses dwell at four stops, longer when bunched. A state is 256 bytes at 4 Hz.
    - **People:** the city's 52 people, walkers included, are a pure function of the shared clock and are never sent. Wheel passengers ride only in cabins with no child aboard.
    - **Look and Pause** are on one screen only and never sent.
    - **Versions:** protocol 16 clients cannot join.
  - **Protocol 18 (city r3):** the city's weather is shared.
    - **Request:** `city_weather` (1: an index into `CityMap.WEATHERS`: sunny, rain, night). Any child in the city may change it; an unknown index is refused kindly.
    - **State:** the packed city state (version 3) ends with the weather, when it changed and the mix at that moment. Every client blends the same way over `WEATHER_BLEND` from the shared clock, and a change during a blend starts from the current mix.
    - **People:** taking cover in the rain is computed on each client from the shared weather. A device that joins during a change shows them its own way until that change finishes, then matches.
    - **Cost:** a state is 296 bytes at 4 Hz.
  - **Protocol 19 (city-web r1):** a second city map, `city_web`.
    - **Two authorities' states:** the `City` autoload runs twice, as `City` (map `city`) and `CityWeb` (map `city_web`), each taking its map from its node name. Each runs its rules only while a child is on its map and sends its packed state only to that map's peers. RPCs are node-path based, so the two never mix.
    - **Requests:** the city requests (`city_use`, `city_board`, `city_off`, `city_release`, `city_weather`) go to the instance for the asker's recorded space.
    - **Travel:** the authority accepts a journey to `city_web` from any client. Whether a device offers it is the device's own choice (`Places.available`), never an authority rule.
    - **The page:** what the Three.js page shows comes from the client's own Godot over a local bridge (design/city-threejs.md §6.3), never from the network.
    - **Versions:** protocol 18 clients cannot join.
  - **Protocol 20 (thousand-town, development candidate):** the map `thousand`, Thousand Town (design/thousand-town.md section 3), offered on every device, the TV included. Its world is a placeholder until the world builder lands.
    - **Autoload `Thousand`** (`net/thousand.gd`): the shared town clock `{day, minute, mode, speed}`. The first arrival starts it at day 1, 08:00; after that it runs only while a child is in the town and keeps its place while the town is empty. It is forgotten on a new session.
    - **Requests:** `thousand_time` (2: a mode `auto`, `day`, `dusk` or `night`, and a speed 1, 2, 4, or 0 to keep it). Any child in the town may choose. Day, Dusk and Night jump to 12:00, 18:40 and 21:30 and hold; Auto runs 1 sim minute per second times the speed, from the held time. `thousand_board` (1: a bus index) and `thousand_off` (0) reserve a seat (4 per bus, 3 buses) and free it; leaving the town frees it too. The buses' motion comes later.
    - **State:** `ev_thousand_state` (packed Float64: wire version, started, day, minute, mode, speed, riders) about once a second, at once on every change and to every arrival, only to the peers in the town. `ev_thousand_effect` (reliable: `time`, `bus`). Clients estimate the clock between packets and never run it backwards.
    - **Saves:** schema unchanged; nothing of Thousand Town is saved.
    - **Versions:** protocol 19 clients cannot join. Tests: `thousand_tests.gd` (solo authority) and `python3 scripts/net_test.py --thousand` (real clients, nothing rendered).
  - **A player's map changes only through `travel`.** The authority answers `{"ok", "space", "x", "z", "ry"}` (plus `"waits": <the animal's English name>` when a house visit ended because the animal cannot ride; the client says "%s will wait for you in town." in its own language) or `{"ok": false, "error"}`. The destination must be on the line from the child's current map, at least 1 s after their last journey. The zoo arrival is the first free place on the platform (`ZooMap.ARRIVALS`); the town arrival is in front of the tram stop, else the usual place. A child's seat and locks are left behind, and the others learn of the move through `ev_player_state`.
  - **A stale position is dropped.** `rq_state` may move a child between a map and its own rooms, never to another map, so a late packet from before a journey cannot pull a child back. A reconnecting child always starts in town.
  - **The zoo sleeps when empty.** The authority runs `ZooBrain` only while a player's recorded space is the zoo (a fresh `spawn()` for the first arrival, dropped with the last child). States and events go only to the peers in the zoo, and an arriving peer is sent the newest state at once. Clients never simulate; they draw at the clock they estimate from the newest state.
  - **Checked by the authority:** a station from within `ZooMap.STATION_REACH` + 0.4 m and rested 1.2 s after each use (per station); a treat from within 3.5 m of the animal; an invitation to the zoo only from the zoo. A `found` answer is written once per species and answer, with the nicks of the players within 8 m, then saved and sent as `ev_town_data("maps", ...)`.
  - **Saves:** discoveries and zoo items are saved with the town (schema 3, see the contract); animals, stations and journeys are not.
  - **Release:** apps and the town server must be updated together (13 -> 14). Tests: `zoo_net_tests.gd` (solo authority) and `python3 scripts/net_test.py --zoo` (real clients, nothing rendered).
- Release r1 models need no protocol change: modeled items are ordinary catalog kinds, and wall and ceiling items carry their mount height in the item data.
- Table tops: the authority applies requests in order, so when two children drop a decoration on the same table at once, exactly one succeeds and the other gets "There is already something on top." (tested with two real client processes).
- Rules enforced on the server: four-player limit, protocol version check, 10 s join timeout, item locks, seat occupancy (the first free seat of an item; a child already on it keeps their seat; r17), no moving occupied items or houses with someone in any of their rooms, and avatar sanitizing (preset nicknames only; only accepted wearables in their own slot).
- Persistence: debounced atomic save (`.tmp`, then rename), loaded tolerantly (malformed entries are dropped, not fatal). Clients show "Town saved" and connection state. Disconnects pause editing and offer Reconnect.
  - **Schema 3 (zoo) writes three files** (`Session.save_now`): the main file (schema 3); `<save>.bak`, a **schema-2 projection** of the same town (no zoo things, no tram stop, no `maps`), so an older app that refuses schema 3 still finds the whole town; and `<save>.maps`, a sidecar `{"schema": 3, "items": [zoo things], "maps": {...}}`. It is always written, empty when the zoo is.
  - **Loading** a schema-1 or schema-2 file migrates it and adds the tram stop if the town has none; the untouched original is kept once as `<save>.v1` or `<save>.v2`. When the file loaded is schema 2 (a downgrade and an upgrade, or the `.bak` after a damaged main file) and the sidecar exists, its zoo things (new ids where the old id is taken) and `maps` are merged back and logged. A damaged `maps` key or sidecar is dropped, never fatal.
  - **Apple TV:** `Durable` also keeps a checked copy of each town's sidecar (`town_solo_maps`, `town_hosted_maps`, at most 24 KiB each; 80 zoo things and a full found log pack to a few KB).
- Privacy by design: no accounts, no free text, no chat, no location. Nicknames come from a fixed list.

## Run a server

```sh
scripts/godot.sh --headless --path game -- --server --port=9080 --bind=127.0.0.1 --save=user://town_server.json
```

`--bind=*` (the default) listens on all interfaces. Clients use "Play with friends", then enter the server address (for example `ws://192.168.1.20:9080` on a LAN, or `wss://town.example.org` in production).

## Tested here

`python3 scripts/net_test.py` starts a real dedicated server process and five separate client processes connecting over loopback WebSockets on this host. It then restarts the server from its save file and connects another client. See [validation.md](validation.md) for the latest results. These clients are real network peers, but they are scripted, headless and on one machine. This does **not** test home-NAT traversal, TLS, real internet latency, iPad networking or app suspension.

`python3 scripts/net_test.py --zoo` runs the zoo with real client processes: two clients on different maps, an invitation and Join, a late joiner, a drop mid-journey and a server restart.

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

