# Handoff — Lantern Lane

Date: 2026-10-07, revision 3 (release r1). Workflow: EC2 code → GitHub → local Mac pull and build; heavy renders and the iPad build run on the Mac (dual-host workflow).

**Git status:**
- Revision 1 is commit `e677e8c` (built and played on a real device by the user).
- Revision 2 is commit `b0f1fb7`.
- Revision 3 is committed and pushed on `main` after its checks; the pushed SHA is reported in the session. The game bytes equal the sealed Mac candidate `ipad-r1` (manifest SHA-256 `955dcc5c0f380d96591fb5eb6c95e9551b67d1629b0b4d53ce4db9464565a03f`, 381 files under `game/`).

## Current goal: finish A-H and fix the r1 acceptance blockers (uncommitted, 2026-10-07)

Goal: finish all eight activities A-H under the corrected specs in [design/playfulness-proposals.md](design/playfulness-proposals.md), fix the r1 acceptance blockers (music shutdown error, overlapping landmark labels), keep six languages, free play, network and save contracts, and retain raw evidence. **Not committed or pushed** (no authorization for this goal). Working tree is based on `f26f9c8`; model assets and the modeling workspaces are untouched.

**Status: code complete; EC2 logic, multiplayer and persistence checks and the Mac GPU rendered suites PASS on the frozen candidate `ipad-r2` with no engine errors or shutdown leaks. iPhone device acceptance pending** (see "Pending external acceptance" below). Committed and pushed on user authorization for this A-H delivery.

### A-H checklist (corrected specs)

| | Feature | Spec items | Implemented | Evidence (EC2) |
|---|---|---|---|---|
| A | Animal wishes | 20 templates (4 per animal), one active wish, wish card, "Wish" tab first in the toy box, sticker crediting everyone present, occasional present, authority checks once | yes (r1) | unit tests (wishes), activities tour (wish card, wish came true), activities network test |
| B | Hide-and-seek | golden acorn, hider hides where they stand (any room), 0-4 warmth from the server, acorn visible within 2 m, glow hint after 3 min, solo: an animal hides it, spot never sent early | yes (r1) | unit tests (warmth), activities tour (tap the stump's name tag, seek, find), network test (roles hider and seeker, conflicting starts, late joiner) |
| C | Gift bundles | wrap any placed item for a roster player or "anyone", only they unwrap, at most 3 waiting per recipient, saved on the item | yes (r1) | unit tests, activities tour (gift picker, present waiting, opening), network test (presents, opened present survives restart) |
| D | Little gardens | garden bed, sprout/bud/bloom, Water action, slow growth tick with someone outdoors, never wilts, saved | yes (r1) | unit tests, activities tour (three waterings bloom) |
| E | Dance party | 30 s party, music speeds up with a beat, animals parade around the tree, **lanterns twinkle** (added in this goal: all eight lanterns hang out and twinkle in a wave, then only lit ones stay), children dance; session only | yes | activities tour (party starts, music joins, lanterns twinkle and reset), network test (party joined/started) |
| F | Open-house visits | heart per player per room, guest book in the living room, no counts or rankings, saved | yes (r1) | unit tests, activities tour (heart, guest book), network test (guest book survives restart) |
| G | Photo ideas | 8 ideas from deterministic scene facts at the shutter, recorded by the authority, in the scrapbook | yes (r1); scrapbook rows now use icons instead of missing glyphs | unit tests (photo idea rules), activities tour |
| H | Weather | vane cycles sunny, rain, autumn, snow; sky, ground, particles, puddles; Pip splashes in rain puddles; saved; decoration only | yes (r1) | unit tests, activities tour (rain, autumn, snow, sunny) |

Entry mechanisms (addendum): untried landmarks twinkle; nearby landmarks now carry tappable name tags (walk there and start); solo and multiplayer starts; late joiners get the running game; conflicting starts join the running game. All optional; nothing is gated.

### Fixed in this goal

| Blocker | Fix | Evidence |
|---|---|---|
| Shutdown error `1 resources still in use` / `2 ObjectDB instances were leaked` (music loop) | `Music.stop_for_exit()` stops both music players and every sound player, drops their streams and lets the audio server mix three times (0.36 s); `Music.quit_game(code)` is the one quit path for the game (window close with `auto_accept_quit = false`, server error) and all test drivers; `run_tests.gd` awaits it. One mix (0.12 s) was not enough for a client that quit soon after the music started (net bot `check`: 3 of 3 runs leaked; clean after) | `tools/goal-logs/net-procs/`, `act-procs/`, `lineup_exit.log`, `unit.log` |
| Landmark labels overlapped and were cropped under the top bar | The 3D labels are gone. A HUD layer shows at most three tappable name tags, nearest first, laid out in screen space by `game/scripts/ui/tag_layout.gd`: never overlapping, clear of the top bar, bottom controls, activity chip and action button, inside the safe area; a tag falls back below its landmark when the landmark stands under the top bar; the landmark the action button already offers gets no tag | unit test `test_landmark_tag_layout`; activities tour; `tools/goal-logs/shots/act_01_activity_square.png` vs. the r1 Mac image |
| Missing glyphs (✨ ★ ✓ ○ ♥ were not in the bundled fonts) | Replaced with SVG icons and styles; `scripts/check.py` now also checks non-ASCII characters written directly in scripts | `check.py` PASS |
| Server engine errors when friends leave together (pre-existing) | `_kick` skips a peer that already left; "player left" is sent only to peers whose WebSocket is still open | server logs in `tools/goal-logs/net-procs/` have no `ERROR` lines |
| Particles started before entering the tree (5 startup errors) | the sparkle is added to the tree before `emitting` is set | clean startup logs |

### Evidence (EC2, Linux, Godot 4.7.2, software OpenGL under Xvfb; not iPad or iPhone testing)

Raw logs: `tools/goal-logs/` (git-ignored scratch, kept on EC2). Every log was scanned for `ERROR`, `leaked` and `still in use`, not only for assertions.

| Check | Result |
|---|---|
| `tools/venv/bin/python scripts/check.py` | PASS (401 messages x 6 languages, fonts 922 characters) |
| `run_tests.gd` (`unit.log`) | **8074 checks, 0 failures**, exit 0. One engine line, `Parse JSON failed`, is the intentional corrupt-save test |
| `net_test.py` (`net_test.log`, `net-procs/`) | **NET TEST PASS**, exit 0; server, five bots and the restart check: no `ERROR`, no leak |
| `net_test.py --activities` (`net_activities.log`, `act-procs/`) | **ACTIVITIES TEST PASS**, exit 0; no `ERROR`, no leak |
| Rendered: activities tour, six-locale capture tour (87 checks), dock tour x3 (58 checks each) | all **PASS, 0 failures**, exit 0, no engine errors besides EC2's missing audio device and V-Sync, on the bytes just before the final server-only broadcast fix; for the sealed bytes these run on the Mac (EC2 duplicate stopped, partial log kept) |

Repeated network checks on the sealed bytes (3 runs of both suites): all PASS, exit 0. **Open:** run 3's server log has one `ready_state != STATE_OPEN` error from `_reply` when a bot closed right after asking to stand up (no functional effect). The reply path is not guarded yet; deferred because the candidate source is frozen.

Known, not a defect of the game: on EC2 every rendered run prints `ERR_CANT_OPEN` from the ALSA driver (no audio device; Godot falls back to the dummy driver). The engine's own `--quit-after N` debug flag bypasses `Music.quit_game` and still reports the music leak; the game and all drivers do not use it.

### Pending external acceptance

- iPhone 14 Pro (iOS 18.7.7): build after pull, install, launch, touch play, safe areas, name tags and audio on quit. Not yet done.
- The `_reply` send race above (one server log line in 1 of 3 network runs). Frozen candidate `ipad-r2`: 383 files under `game/`, manifest SHA-256 `8ed0ab85531601fb3783a73e6a7dc4c945f32a3cce0c92e9f7a5115410ab196a`, archive `tools/dual-host-workflow/ipad-r2/candidate.tar.gz`; request `tools/dual-host-workflow/ipad-r2/LOCAL_VALIDATION_REQUEST.md`. All five rendered suites move to the Mac GPU for these bytes. Mac (GPU): manifest verified; import, unit (8074 checks, 0 failures), six-language tour, dock tour iPad / iPad Air 5 / iPhone and activities tour all exit 0, PASS, **no engine errors and no shutdown leak** (only the deliberate corrupt-save message in the unit run); 66 PNGs inspected in part by the coordinator and this session.
- Music and sounds heard on a device; native-speaker review; art approval.

## What changed in revision 3

| Area | Change | Main paths |
|---|---|---|
| Eight activities (GameCode lane) | A animal wishes, B hide-and-seek with a golden acorn, C gift bundles, D little gardens, E dance party, F open-house hearts and guest books, G photo ideas, H weather. All optional, nothing gated, the authority runs every rule. Device player ids and a roster; network protocol 4. | `game/scripts/core/wishes.gd`, `hide_seek.gd`, `photo_ideas.gd`, `game/scripts/net/activities.gd`, `game/scripts/world/activity_world.gd`, `session.gd`, `hud.gd`, [design/playfulness-proposals.md](design/playfulness-proposals.md) |
| Wall and ceiling placement | Wall items snap onto room walls at a mount height and face into the room; ceiling items hang at 2.8 m; both are "mounted" and never block walking. The pilot wall clock and bird mobile are now placeable. | `town_model.gd`, `catalog.gd` |
| 130 production models (release r1) | Furniture, small decorations, table-top food and toys and 41 wall items from the modeling lane's frozen batches b001-b008, with original names in six languages. Eight wall items ship as version 2 (origin recentered). Four built models were excluded by the game's small-size rule. Wearables (clothing) are built but **not** shipped. The toy box now holds 163 items. | `game/assets/models/`, `catalog.gd` (block "production models r1"), `game/locale/`, [art/production-r1](art/production-r1/README.md), [design/model-release-r1.md](design/model-release-r1.md) |
| Fonts | CJK subsets rebuilt for the new names (921 characters). | `game/assets/fonts/` |
| Tests | Model count 10 + 130; the dock tour finds Cancel by its label (the new hidden Gift button shifted the index). | `game/tests/run_tests.gd`, `game/tests/dock_tour.gd` |

## Tests for revision 3

EC2 (Linux, Godot 4.7.2, software OpenGL under Xvfb), on the same bytes as candidate `ipad-r1`:

| Command | Result |
|---|---|
| `tools/venv/bin/python scripts/check.py` | PASS: 401 game messages × 6 languages, placeholders, extracted strings, fonts cover 921 characters, English sources, links |
| `python3 scripts/check_audio.py` | PASS |
| `scripts/godot.sh --headless --path game -s res://tests/run_tests.gd` | **8057 checks, 0 failures** (scale contract and bounds of every one of the 163 kinds including all 140 GLBs, mounted items, activity rules) |
| `python3 scripts/net_test.py` | **NET TEST PASS** |
| `python3 scripts/net_test.py --activities` | **ACTIVITIES TEST PASS** (conflicting starts, late joiner, presents, hearts, restart) |
| `tests/capture_tour.gd`, six languages | **TOUR PASS, 0 failures** |
| `tests/dock_tour.gd` | first run: iPad 8 failures, all "'Gift' reachable" (a stale button index in the test). After the test-only fix: iPad **PASS, 0 failures**; the EC2 iPad Air 5 run was stopped as a duplicate of the Mac run and iPhone was not run on EC2 |

Mac (candidate `ipad-r1`, macOS arm64, Godot 4.7.2 GPU): manifest verified, import exit 0; unit tests 8057 checks, 0 failures; capture tour (six languages), dock tour (iPad, iPad Air 5, iPhone) and activities tour all 0 failures. The strict report is **FAILED** only because every rendered run prints a shutdown resource error (known issue 1 below). Signed iPad build and codesign passed (PCK SHA-256 `576a6238…6ffc`) and installation on the USB iPad succeeded; launch and on-device play are not yet verified. Details: [docs/validation.md](docs/validation.md).

## What changed in revision 2

| Area | Change | Main paths |
|---|---|---|
| Background music | An original 45.7 s loop, "Meadow Lanterns", rendered from synthesized instruments. It plays quietly outdoors, softer indoors and on menus, and pauses with the app. The sound dialog has music on/off, music volume and sounds on/off, saved on the device. | `game/scripts/autoload/music.gd`, `game/assets/audio/`, `scripts/compose_music.py`, `scripts/check_audio.py`, [docs/assets.md](docs/assets.md) |
| Animal friends | Pip the pig, Bramble the rabbit, Wooly the sheep, Biscuit the dog and Tumble the elephant roam outdoors and play their hobbies. They greet children, chat with each other, and react when tapped. The authority simulates them and broadcasts them to everyone; they are not saved. | `game/scripts/core/animal_brain.gd`, `game/scripts/net/animals.gd`, `game/scripts/art/animal.gd`, [docs/animals.md](docs/animals.md) |
| Placement tools (device bug) | The Turn / Paint / Cancel / Place bar moves under the top bar (and the toy box tucks away) when it would cover the item being placed. This uses the item's screen footprint, with hysteresis, a dwell time and the safe area. The camera now holds still while a finger drags an item, which was also the cause of earlier jitter. | `game/scripts/ui/placement_dock.gd`, `hud.gd`, `camera_rig.gd`, `play_controller.gd` |
| Larger town | 52 × 44 m (was 32 × 28) with a west grove, an east meadow and second pond, a north orchard and trails. Every old position still fits. | `town_model.gd`, `town_world.gd` |
| Three-story houses | Cottages are three stories outside. Inside there are 3 floors × 2 rooms (living room/kitchen, bedroom/playroom, attic/art studio) connected by doors and stairs, with signs and a floor and room chip. Furniture, presence and isolation are per room. Old saves migrate (schema 1 → 2) without loss, and the original file is kept as `.v1`. | `town_model.gd`, `town_world.gd`, `play_controller.gd`, `props.gd`, [docs/game-design.md](docs/game-design.md) |
| Scale contract | [design/object-scale-and-surfaces.md](design/object-scale-and-surfaces.md): 1 unit = 1 m, H = 1.30, size classes, and bounds, footprint and touch-target rules checked against the built models. Trees went from about 2.9 H to about 1.85 H. Small decorations are resized and the decorative woods toned down. | `catalog.gd`, `props.gd`, `town_world.gd` |
| Table tops | A table holds exactly one small decoration. The second one is refused. Fit is checked for the item turned relative to the table, inside an inscribed rectangle. Nothing stacks. The decoration follows the table and is put away and undone with it. Restore works in dependency order. Saves, the network, and two simultaneous attempts are handled. | `town_model.gd`, `session.gd`, `play_controller.gd`, `town_world.gd` |
| Modeled furniture | Eight reviewed pilot-10 models are placeable: scallop chair, cozy round table, scallop bed, writing desk, open shelf, curved counter, desk lamp, blooming flower pot. The wall clock and bird mobile are versioned but **not placeable** (wall and ceiling anchors are not implemented). | `game/assets/models/`, `art/pilot-10-v1/` ([INTEGRATION.md](art/pilot-10-v1/INTEGRATION.md)) |
| Other fixes | Leaving a house placed the child up to 3.5 m from the door, because the room's walking limits were applied outdoors. The export preset is now universal (iPhone and iPad). Network protocol is 3. | `play_controller.gd`, `game/export_presets.cfg`, `session.gd` |
| Docs rule | Docs are updated with every change, see [CONTRIBUTING.md](CONTRIBUTING.md). | |

## Run (Mac)

```sh
git pull
/Applications/Godot.app/Contents/MacOS/Godot --path game              # play
/Applications/Godot.app/Contents/MacOS/Godot --editor --path game     # editor
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://tests/run_tests.gd
```

iOS export: preset "iPad" (now targeting iPhone and iPad). Set the bundle ID and Team ID locally only.

## Tests run on EC2 for revision 2 (final code)

| Command | Result |
|---|---|
| `tools/venv/bin/python scripts/check.py` | PASS: 193 game messages × 6 languages, placeholders, extracted strings, fonts cover 624 characters, links |
| `python3 scripts/check_audio.py` | PASS: 45.71 s loop, peak −6.0 dBFS, RMS −19.9 dBFS, seam step 384 ≤ 1362 |
| `scripts/godot.sh --headless --path game -s res://tests/run_tests.gd` | **3189 checks, 0 failures**. Includes the scale contract on every built model, the eight GLBs, table tops (restore order as removed/reversed/shuffled, rotated fit, broken save data), rooms and stairs, v1 migration, animals, placement-tool logic and music settings |
| `python3 scripts/net_test.py` | **NET TEST PASS**: server + 5 real client processes. Covers animals, room presence and isolation, kitchen furniture, the table-top race (one client won, one was refused) and persistence across a restart |
| Rendered tour, six languages (`tests/capture_tour.gd`) | **TOUR PASS, 0 failures**. Covers walking through all six rooms and back out, furnishing every room, kitchen table tops through the real ghost, modeled furniture (pot on the cozy table, lamp refused at 45°, sitting at `Seat0`), the countryside, animals, music state, and furniture surviving a reload |
| `tests/dock_tour.gd` at iPad 4:3, iPad Air 5 and iPhone landscape with simulated insets | final run: see [docs/validation.md](docs/validation.md) |
| `art/pilot-10-v1/rebuild.sh` | all ten GLBs rebuilt **byte-identical** |

Evidence: `docs/screenshots/godot/` (including `scale/lineup_before.png`, `lineup_after.png` and `lineup_modeled.png`, the six rooms, the three-story house, table tops, animals, countryside, the sound dialog and the placement-tool layouts).

## Not verified (needs the Mac or devices)

- Everything on the iPad Air 5 and iPhone 14 Pro: frame rate with the larger map, animals and modeled furniture, memory, touch feel, safe areas, and the docked placement tools under real fingers.
- Music and sounds were never heard (there is no audio device on EC2).
- Real-time shadows are still off (blob shadows only).
- Software rendering here runs at about 8 fps and says nothing about Apple GPUs.
- Cross-home play: no hosted server.
- Art approval of the procedural and modeled assets (the 130 release r1 models were checked visually by the modeling model only); native-speaker review of the translations, including the 130 new item names.
- Frame rate and memory on devices with the 163-item toy box (thumbnails for all items render at startup) and the eight activities.

## Remaining product issues

0. Release r1 known issues: (a) a shutdown-only resource leak from the looping music playback and (b) overlapping, cropped landmark labels are **fixed in the uncommitted A-H goal candidate** (see the top section; Mac acceptance pending); (c) the 130 release r1 models are checked by unit tests but appear in no rendered tour yet.
1. Wearables: 434 clothing references are built as rig-fitted garments, but none ship. The wearable validator self-test has not passed, and the game has no system to equip clothing ([design/model-release-r1.md](design/model-release-r1.md)).
2. Ceiling furniture batches (38 references) and four excluded wall items still need repair and a new release.
3. The desk lamp fits the cozy table only at 0°, 90°, 180° and 270°. At 45° it is refused truthfully, because its turned box is about 0.565 against a 0.56 slot.
4. Footprints are circles, so long items (beds, counters, sofas) can sit closer to walls than their shape suggests.
5. Modeled seats use only `Seat0`: the two-seat bamboo bench seats one child.
6. Animals are recreated each session, and they don't enter houses.
7. The town server still needs hosting, TLS and an invite code before cross-home play ([docs/multiplayer.md](docs/multiplayer.md)).
8. The scrapbook lists only this session's photos.
