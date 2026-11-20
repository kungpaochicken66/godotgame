# Roller Coaster Workshop

Take the main-town tram to Roller Coaster Workshop. Tap or click any of the six illustrated cards at the entrance to immediately board that stopped train. On a controller, use the D-pad and confirm (up/down changes rows). The same cards are available after disembarking. Walking to a signed platform and using Board train also works. Switch view cycles rider-eye, chase and trackside. Get off appears at the end of one circuit. After getting off, Ride home appears beside Board train at every platform (unified r4); the central tram's Ride home works too.

## Editable layouts and reproduction

The six JSON files in presets/ are normal v1 Workshop saves. Import any one using the reference application's file importer to open its control points, segment types, banking, train settings and environment. The rendering assets for that application belong in its own authoring directory.

The reference is *Three-dimensional Roller Coaster Workshop*, published by 量子书架 on Bilibili Toy, updated 2026-11-13. [Original workshop](https://www.bilibili.com/toy/nAdXZ2wF3W9DPBTm/index.html). The supplied frontend ZIP SHA-256 is c5b77c4709f101d0bade1305f581c730e21ddad463b2f21b3936e3f01a8979e4. In the supplied ZIP the Three.js r160 header identifies the MIT license and credits the Three.js Authors, 2010–2023. No permission to redistribute the workshop program, texture collection or GLBs was identified in the ZIP or the public work details. Those inputs stay outside the candidate. The Godot rails, cars, platforms, tram, landscaping and controls are original procedural game geometry. The player's child uses the existing Lantern Lane Kid rig, avatar configuration, clothing and seated animation.

Serve the supplied frontend with its matching assets on loopback. Copy author.mjs and themes.mjs beside its index.html. Enter construction mode and run the following in the application's own module context:

```js
const original = await (await import('./author.mjs')).author(window.app);
const expansion = await (await import('./themes.mjs')).buildThemes(window.app);
```

Each result contains the native editable save and the corresponding sampled runtime. Write save to tools/coaster/presets/ID.json and runtime to game/coasters/ID.json. Stable filenames retain the r1 IDs. For the original three rides, the authoring module defines normalized height knots and horizontal paths, inserts 144 points in each closed circuit with the Workshop construction Track.addNode method, then serializes and reloads through App. The baked frames use the Workshop's calculated tangent and banked up vector. TrainSim dispatches three seated cars and records the speed and track position through docking. Run python3 tools/coaster/check_tracks.py to verify loop distance, frame continuity, winding, station and shallow-track proportion.

The Mac authoring run used a headless JavaScript adapter for pro construction mode, including the original Editor.setMode, App.serialize, App.applyData and train model with parts.glb. Its preview renderer, scenery and audio were inactive. The in-app entry point above works with a normal Workshop instance. The first three ride posters are original OpenAI GPT Image concepts generated for Lantern Lane. Their reduced JPEG versions are the in-game boarding cards. The Godot trains use original procedural silhouettes, including bee antennae and wings, a silver rocket nose and fins, and a dragon head with horns and scales.

The six paths share one park scene. This candidate branches independently from the frozen tv-diag r1 main-town game. Thousand Town's separate, in-progress production tree was not imported. The park excursion is local to the player, retaining the existing main-world session and returning to its stop. Shared park multiplayer, authoring inside the shipped game and target-device acceptance are outside this candidate.

## Workshop theme expansion

The original Workshop defines six seat arrangements and eight vehicle themes. Its theme presets also choose train finishes, track styles, environment and compatible scenery. The three new lines select native combinations from the mine, neon and castle presets. The construction recipe calls generateTrack, applies autoScenes to the resulting circuit, serializes it and reloads it through the Workshop. The native TrainSim timetable, half-gauge, car pitch, lead-car eye and scene tags are retained in the Godot data. Editable files retain per-segment scene and banking fields. The Mac adapter used a level authoring surface. Loading the editable files preserves the authored geometry in the desktop editor.

| Ride | Workshop choices | Passenger position | Trackside scenery |
| --- | --- | --- | --- |
| Crystal Mine | Mine train, wooden track, minetrain generator | Inside a timber ore cart | Timber portals, lanterns and crystal outcrops |
| Neon Wings | Cyber train, truss track, launch generator | Left outboard wing seat | Luminous hoops, a covered light corridor and ground pools |
| Phantom Castle | Ghost train, box track, thrill generator | Suspended beneath the rails | Stone arches, torchlight, stained glass and castle towers |

The park rebuilds these features with original Godot geometry. Its three new card images are renders of the actual cars in their own track scenery. A fountain, striped tent and tethered balloon mark the spaces between the entrance paths.

## Workshop gamepad trial on Apple TV

At the town tram, press Start (+ on Switch Pro) to travel to the workshop. The D-pad moves between six ride cards in two rows. Confirm boards or disembarks after docking. The shoulders switch cameras in both directions while moving. Whenever the child is off the train, Back (B) or Start (+) rides home, from a platform or the entrance (unified r4); the park's hint names them. The on-screen guide uses the active layout and confirm/back preference.

## Clearance audit (unified r6)

Physical TV feedback showed track, trains and the seated child passing through hills and scenery. `game/tests/coaster_clearance.gd` audits the park the game actually builds. It loads main.tscn, starts a solo session and opens the Workshop through the Hud's own path (`stop_for_workshop()`, then `coaster_park.gd` `setup(main)`). It then reads back every visible mesh. Merged meshes are split back into their convex parts. It also reads the rail, tie, column and hanger-arm poses (by rerunning the line's own `_build_track()` on a capturing copy, because a headless renderer does not keep MultiMesh transforms), the platform signs and the parked trains. For every frame index of all six laps the ride's train is placed with `CoasterLine.place()`. Each check reports the object and the ride it belongs to.

- **Track**: every rail segment, tie, column and arm against everything, including other sections and other rides. A support standing in terrain, a path, the plaza or a pool counts as its footing.
- **Cars**: each car's own convex parts and its wheel cylinders, for all three cars. A car buried more than 0.5 m in terrain is recorded with its whole-car box.
- **Rider**: the child in the lead car. The envelope is boxes around the kid rig's own meshes in the "ride" pose (upper body and legs, +0.05 m) plus the rider-eye camera (eye ±0.15 m).

The only exclusions are a car's contact with its own rails and ties under it and a track element's contact with its own track within ±8 frames. Any penetration above 0.01 m is a conflict. The portal arches of Crystal Mine, Neon Wings and Phantom Castle, and the castle, are intentional tunnels, but they do not pass by name. Each must stay at least 0.25 m from the car and rider envelopes over the whole lap. The cross-section at each portal frame must also be empty: all envelopes + 0.25 m, 0.6 m deep.

The audit of the sealed r5 bytes found 135 conflict intervals and 3 failed tunnel checks (`docs/local-validation/unified-r6/coaster-clearance-r5.json` and `.txt`):

- **Distant hills**: Comet Express, Crystal Mine, Neon Wings and Phantom Castle run up to 38 m deep through the 24 backdrop hills (r ≈ 380–430 m, semi-axes 92 × 39–60 × 78 m). Track, cars and child are inside a hill for long stretches, such as Comet 319–377 m and 484–637 m, Neon 0–43 m and 1024–1308 m, and Phantom 228–834 m. Those hills also blocked 42 Crystal Mine portals, 1 Neon Wings portal and all 52 Phantom Castle portals.
- **Supports through the train**: a support of another section passing through the cars or the child, mainly in the Jade Dragon helix (up to 0.43 m), Neon Wings 737–754 m and Crystal Mine 215–232 m. The Comet rocket nose also clipped column stubs between the rails in sags (≤ 0.07 m).
- **Phantom Castle supports**: hanger arms and columns crossed 53 arch plinths, piers, caps, glass and torches and 6 stone piers (up to 1.41 m). A hanger arm clipped a wheel (0.02 m at a sample; up to 0.08 m between samples). The hanging car clipped the platform canopy trim at departure (0.08 m).
- **Crystal Mine**: two columns stood in rock outcrops (1.03 m and 0.03 m).

Repairs (no ride data changed):

- **Hills** (`coaster_park.gd`): each distant hill is lowered until it stays 0.3 m below every ride's clearance box (`CoasterLine.hill_room()`). All 24 hills remain; 16 are lower, their peaks now 4.8–33.6 m above the ground instead of 31–52 m.
- **Supports** (`coaster_line.gd` `_build_track`): column tops end under the ties, not between the rails. A support is left out where its column or arm would pass through the train or child at any frame (`clearance_box`, `_clear_of_train`) or through a scenery part (`_keep_clear` / `_clear_of_scenery`). For that, the scenery is now built before the track. A Phantom Castle hanger arm first tries the other side and a 3.6 m reach. Its mount is raised from 0.45 m to 0.6 m above the rails, clear of the wheels. Removed supports per ride:
  - Comet Express: 4 of 92
  - Jade Dragon: 16 of 62
  - Crystal Mine: 7 of 91
  - Neon Wings: 2 of 147
  - Phantom Castle: 15 of 108 (arm and column pairs)
- **Platform**: under the suspended ride, the canopy's track-side edge is 0.45 m narrower.

After the repairs the audit passes with 0 intervals (`coaster-clearance-r6.json` and `.txt`). Every portal is open. The smallest tunnel clearances are 1.71 m for Crystal Mine, 1.01 m for Neon Wings and at least 2.0 m (the probe) for Phantom Castle. `tests/coaster_contact.gd` still holds wheel contact at 0.003 m.

```sh
# audit (EC2 or Mac, headless, about 2 min on r5 bytes and 20 s after the repairs): prints the intervals, writes JSON + .txt, exits 1 on any conflict
scripts/godot.sh --headless --path game -s res://tests/coaster_clearance.gd -- --out=/abs/coaster-clearance.json [--label=r6] [--rides=comet-run,neon-wings] [--dump]
# matching rider-eye (view 0) and chase (view 1) frames at 1920x1080 (Mac, rendered); identical names in r5 and r6 runs
scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/coaster_frames.gd \
    --plan=/abs/docs/local-validation/unified-r6/coaster-clearance-r5.json --frames-out=/abs/frames-r6 \
    "--at=comet-run:344,520;crystal-mine:460;neon-wings:14,275,1160;phantom-castle:400,700"
```

For the matching r5 frames, copy `game/tests/coaster_frames.gd` into an extracted r5 tree's `game/tests/` (it uses only r5 APIs) and run the same command there with `--frames-out=/abs/frames-r5`. Add `--headless` and `--dry` for a check without pictures, which prints every camera transform. `manifest.json` in the output directory lists every shot with its camera, lead-car transform and the reason it was taken.
