# Handoff — Lantern Lane

Date: 2026-10-06, revision 2. Workflow: EC2 code → GitHub → local Mac pull and build.

**Git status:**
- Revision 1 is commit `e677e8c` (pushed; built and played on a real device by the user).
- Revision 2 is committed and pushed on `main` after its final checks. The pushed SHA is reported in the session.

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

## Tests run on EC2 for this revision (final code)

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
- Art approval of the procedural and modeled assets; native-speaker review of the translations (including the new room, animal and furniture names).

## Remaining product issues

1. Wall and ceiling placement do not exist, so the wall clock and bird mobile are pending.
2. The desk lamp fits the cozy table only at 0°, 90°, 180° and 270°. At 45° it is refused truthfully, because its turned box is about 0.565 against a 0.56 slot.
3. Footprints are circles, so long items (beds, counters, sofas) can sit closer to walls than their shape suggests.
4. Animals are recreated each session, and they don't enter houses.
5. The town server still needs hosting, TLS and an invite code before cross-home play ([docs/multiplayer.md](docs/multiplayer.md)).
6. The scrapbook lists only this session's photos.
