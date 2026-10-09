# Private deployment contract (generic)

This public repository never contains a real server address, domain or invite. An operator keeps those privately and injects them into an isolated packaging copy. This page is the stable contract between the game and that private tooling. Version: contract 1, network protocol 8 (2026-10-07; protocols 6-8 keep the protocol 5 handshake and add the r9, r10 and r11 play actions). The deployed r8c server and apps are protocol 5: the next synchronized update must move server and apps together.

## 1. Packaged client config: `res://private/deployment.json`

- Repository path: `game/private/deployment.json`. The folder `game/private/` is git-ignored, so a public checkout has no such file and a default export carries no endpoint. The example lives outside the game folder: [docs/private-deployment.example.json](private-deployment.example.json).
- Export: the iOS preset's include filter lists `private/deployment.json`. When the operator copies the file into an isolated packaging copy before exporting, it is packed into the app; when it is absent, nothing is packed. Mobile builds cannot read shell variables, so this file is the only client channel.
- Schema (UTF-8 JSON object; unknown keys are ignored):

| Key | Required | Rule |
|---|---|---|
| `schema` | yes | the integer `1` |
| `multiplayer_url` | yes | at most 512 characters; `wss://<host>[:port][/path]` for real servers. `ws://` is accepted **only** for a loopback host (`localhost`, `127.0.0.1`, `[::1]`) for local testing. No other scheme. There is no option to skip TLS checks |
| `invite_code` | no | 1-256 printable ASCII characters (`!` to `~`), no spaces |

- A missing file is normal (public build). A malformed file (bad JSON, wrong schema, bad URL or invite) is ignored as a whole: the game logs one line naming only the reason category, never the values, and the join screen works by hand as before.
- Anyone who has the app package can extract this file. A packaged invite is a convenience for a personal build, not a secret from people who hold that build.

## 2. Which address the join screen shows

Deterministic, in this order:

1. **Valid private config present** (default `D`): the address field shows `D`, unless the player edited the address by hand **while this same `D` was the default**; then the edit is shown. An edit made against an older or no default is discarded, so a stale test server never overrides a newly injected default. **Use the town's address** restores `D` and clears the edit.
2. **No private config:** the last address the player used (as before), else `ws://127.0.0.1:9080`.

Invite sent with a join: the private `invite_code` when the address equals `D`; otherwise whatever the player typed in the optional **Invite code** field (empty if none). A typed invite is stored on the device (`user://settings.cfg`), never in the town save, and is never logged.

## 3. Server startup

```
godot --headless --path <game dir> --import                       # once per release
godot --headless --path <game dir> -- --server --bind=127.0.0.1 --port=9080 \
      --save=/var/lib/<service>/town.json [--invite-file=/etc/<service>/invite]
```

- `--bind=127.0.0.1` keeps the plain WebSocket on loopback behind a TLS (WSS) reverse proxy. `--save` may be any absolute path; its folder must exist and be writable (a `.bak` is kept beside it).
- Invite (optional): `--invite-file=PATH`, or the environment variable `LANTERN_LANE_INVITE_FILE=PATH` when the flag is absent. The file's first line, trimmed, is the invite (same character rule as above). If an invite file is named but is missing, unreadable, empty or invalid, the server **refuses to start** (exit code 2). If the file is readable by group or others, the server prints a warning (no contents). Without an invite file the server is open, as before (manual and LAN play).
- Log lines say `invite: required` or `invite: off`; they never contain the invite, the URL host or tokens.
- Exit codes: 0 normal, 1 port or bind failure, 2 invite configuration error.

## 4. Join handshake (protocol 5 and later)

1. The client connects and sends one authentication message, `{"v": <protocol>, "invite": "<code or empty>"}` (currently `"v": 8`), using Godot's `SceneMultiplayer` authentication step.
2. Until the server accepts it, the connection is **not** a peer: it receives no town snapshot, no player list and no broadcast, and it occupies no player slot. The server compares invites in constant time (SHA-256 digests compared byte by byte). On a wrong or missing invite it answers `invite` and closes the connection; an unanswered handshake is dropped after 10 s.
3. After acceptance the existing `rq_join` flow runs unchanged (protocol check, four players at most, device player id).
4. The client shows "This town needs the right invite code." for a refused invite, and the usual messages otherwise. Reconnecting repeats the handshake.

A different protocol number is answered `update` and the app shows "Please update the app to play together." (so a protocol 5, 6 or 7 app is refused kindly by a protocol 8 server, and the reverse). Protocol 4 apps cannot join a protocol 5 server (they never complete the handshake and are dropped after the timeout); protocol 5 apps reaching a protocol 4 server time out the same way. Both sides must be updated together.

## 5. Checks an operator can run (placeholders only; nothing here holds real values)

| Tool | What it proves |
|---|---|
| `python3 scripts/remote_check.py --url wss://<host>/<path> --invite-file <file> [--godot <godot 4.7.2 binary>]` | Against the live server: two invited clients join, one places a marker and moves it, the other sees both changes, reconnects and still sees it; a wrong and a missing invite are refused before any town data; the marker is removed afterwards. Prints neither the address nor the invite |
| `... --phase mark --state-file <file>`, restart the service, `... --phase verify --state-file <file>` | The marker survives a service restart (saved to the server's `--save` path), then is removed |
| `... --use-private-config --game <injected copy>/game` | Same, taking address and invite from an injected `res://private/deployment.json` |
| `python3 scripts/net_test.py --invites` | The same checks locally (loopback), plus: missing invite file exits 2, a world-readable invite file warns, the invite never appears in any log |
| `python3 scripts/check_packaging.py` | An injected private config is packed by the iOS preset; a public copy packs none; git ignores `game/private/` |
| `scripts/godot.sh --headless --path game -s res://tests/parse_all.gd` | Every game and test script compiles inside the project |

The clients read the invite from the file themselves; it is never passed as a plain command-line argument.
