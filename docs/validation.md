# Validation Record

All checks below concern the browser design preview. They do not establish Godot implementation, iPad touch behavior, GPU performance, real 3D collisions, shared-world synchronization or server-side persistence.

## Earlier design checks — 2026-10-06

- Chrome at a 1024px-wide viewport: both 1448 by 1086 scene images loaded and were visually inspected.
- A/B switching, catalog selection and hiding/restoring the catalog worked without horizontal page overflow.
- Direction A was subsequently selected. The complete interaction design still awaits user acceptance.
- Character selection, outdoor placement, turning, color changes, removal confirmation, undo and indoor arrangement were exercised.
- Preview objects survived a reload in local browser storage.
- Swing sitting, animated swaying and leaving were checked. Full-room, editing-lock, offline and save-failure simulations displayed their corresponding states and retry controls.
- Five flow states had no horizontal page overflow. Main scene controls met the 48 by 48 CSS pixel target in that run.

## Tree placement and furniture revision — 2026-10-06

Before the fix, a tree at scene coordinates (24%, 78%) could not be confirmed. After the fix, the same location allowed placement and the object remained in the scene. Catalog selection found a free initial spot automatically.

Beds, tables, chairs and flower pots now use different relative sizes with ground-contact anchors and no white icon-card background. The interior was visually inspected. Turning is sprite mirroring only, not verified 3D rotation.

## English repository and six-language UI — 2026-10-06

This section is updated with the final checks for the localization and source upload task. Prior Chinese-only screenshots were superseded by the current English and multilingual preview evidence. No game-development completion is implied.

- `python3 scripts/check.py`: PASS, 133 nonempty messages with identical keys across six catalogs; English filenames and source/document text; valid local HTML references.
- `node --check`: PASS for `flow.js`, `i18n.js`, `directions.js` and `scripts/browser-check.js`.
- `scripts/browser-check.js` executed in an isolated Chrome context at 1024px viewport width: PASS in all six languages. It exercises actual control clicks for character selection, tree placement at (24%, 78%), interior bed placement, turning, removal, undo, simulated save failure and retry, swing animation and exit.
- Language switching retained the chosen character, placed objects and active placement draft. Object accessibility labels and scenario options translated correctly.
- All five main views and the removal, reset, disconnected, full-room, occupied and failed-save states were checked for message coverage and panel bounds. No horizontal page overflow was detected in this run.
- Both concept directions, category selection, catalog hide/show and page titles passed checks in all six languages.
- Reload restored three saved test objects and the selected German locale. The comparison page also read the saved locale.
- English and German interiors were visually inspected. A missed scenario-option translation found in that inspection was fixed and all six language checks rerun. Final screenshots: [English](screenshots/interior-en.png), [German](screenshots/interior-de.png).
- Git initialized locally on `main`; no commit or push was performed.

Limits: translations have not had native-speaker review; browser checks are not physical iPad testing. No public service, Godot build or multiplayer server was deployed.

## Source transfer verification — 2026-10-06

The authorized SSH destination was inspected and was empty before transfer. The complete source tree, including initialized Git metadata, was uploaded without deletion flags. SHA-256 comparison verified 51 files with zero mismatches and zero extra remote files. The repository checker also passed on the remote host. Remote Git reported `main` with no commits, matching the local repository. No server was started.

## Godot prototype "Lantern Lane" — 2026-10-06

All runs were on the EC2 host with Godot 4.7.2-stable (project-local). Rendering used Mesa llvmpipe software OpenGL under Xvfb. None of this is iPad, touch-hardware, performance or cross-home verification.

| Check | Result |
|---|---|
| `scripts/check.py` (venv): six game catalogs with 155 identical keys and matching `%d`/`%s` placeholders; every user-facing literal in the scripts is in `en.json`; every catalog character is covered by the bundled fonts (Chinese by Noto Sans SC); English sources; doc links | PASS |
| `tests/run_tests.gd` (headless): catalog integrity, default town validity, placement rules (edges, overlap, flat/solid layers, door clearance, Wishing Tree, indoor/outdoor, capacity), move/paint, house removal with contents and undo, JSON round trip, tolerant loading, all 8 Cozy Spots, avatar sanitizing, locale completeness, and the real Session autoload in solo mode (locks, seats, bell, save/reload, recovery from a damaged save via `.bak`) | PASS, 2144 checks |
| `scripts/net_test.py`: dedicated server + 5 separate client processes over loopback WebSockets — sync, shared lantern credit, lock contention, swing occupancy, late-join snapshot, shared evening, house put away and restored with its furniture, fifth player turned away, then server restart from its save with persistence verified by a new client | PASS |
| `tests/capture_tour.gd` (rendered): title, creator, solo town, real tap-to-walk input, placement and lantern celebration, invalid placement, edit/paint/undo with lock release, cottage interior, swing sway, evening bell, scrapbook, autosave on disk, language switching in all six locales keeping the placement draft and the town | PASS, 25 assertions |
| iPad Air 5 aspect (1475×1024) rendered tour in French and German | PASS after widening the Undo/Done column |
| Rendering cost of the default town (`tests/perf_probe.gd`) | 72–89 draw calls and about 0.3–0.36 M triangles per frame after merging meshes (previously well over 1000 draw calls) |
| iOS export from Linux (one-off feasibility check, placeholder Team ID in a temporary copy, since restored and the output deleted) | Unsigned Xcode project and `.pck` produced; `.ipa` requires macOS; the pack booted on the Linux runtime |

Screenshots: [docs/screenshots/godot/](screenshots/godot/). These were visually reviewed during development. Issues found and fixed during review include zero-size UI anchors, over-bright lighting with shadowed lights (see the [environment report](environment-report.md)), lanterns hidden in the canopy, items hidden behind panels, and selected-option styling.

## Revision 2 — music, animals, placement tools, larger town, three-story houses, scale contract, table tops, modeled furniture — 2026-10-06

Final run of `scripts/test_all.sh` on the final code, on EC2 with Godot 4.7.2 and software OpenGL (Xvfb + llvmpipe): **EXIT 0**. None of this is iPad or iPhone testing, and nothing was heard (no audio device).

| Check | Result |
|---|---|
| `scripts/check.py` (venv) | PASS: 193 game messages in 6 languages with matching placeholders; every user-facing literal extracted; fonts cover 624 characters; English sources; doc links |
| `scripts/check_audio.py` | PASS: the shipped WAV is 24 kHz stereo, a 45.71 s loop, peak −6.0 dBFS, RMS −19.9 dBFS, DC +0.0000, no silence, seam step 384 ≤ ordinary 1362 |
| `tests/run_tests.gd` (headless) | **3189 checks, 0 failures**. New coverage: animals (240 simulated seconds clear of items and edges, hobbies, greeting, sheep dancing, dog near children, stepping aside, determinism and packing, unchanged save); placement-tool logic across 4:3, iPad Air 5 and iPhone with insets, including hysteresis; music settings and the loop asset; six rooms per cottage, portal graph and arrivals, doorway clearance; v1 → v2 migration of a real v1 save (furniture to the living room, one bookshelf nudged out of the new stairs, second load unchanged); larger town; scale contract on every built model (avatar H measured 1.30, bounds within 0.12, ground contact, footprints, tree and small-item size ranges); table tops (one item, fit, no nesting, follow on move and turn, removal and undo, saves including broken host data, restore order as removed/reversed/shuffled for a decoration older than its table, rotated fit, solo-session race); the eight pilot models (markers, support, lamp refused at 45°, pending wall and ceiling models absent) |
| `scripts/net_test.py` | **NET TEST PASS**: dedicated server + 5 separate client processes over loopback WebSockets. Covers animals from the server for every client, room presence on another floor, a kitchen chair visible in its room only, "cannot put away a house while a friend is in its kitchen", the table-top race (two clients at the same moment: one `RACE won`, one `RACE lost` with "There is already something on top."), a fifth player turned away, and persistence of the upstairs bed, kitchen chair, pot on table and lantern across a restart |
| `tests/capture_tour.gd`, six languages | **TOUR PASS, 0 failures**. Covers the three-story house; walking through all six rooms by doors and stairs and back out to the front door; per-room furnishing; kitchen table tops through the real ghost (snap, 0.70 surface, second item refused, table moved and turned with the pot following, undo); modeled furniture (lamp refused at 45°, pot at 0.66, child at the chair's `Seat0`); walking into the new meadow; five animals; music playing outdoors and softened indoors; every room's furniture surviving a reload; language switching that keeps the placement draft |
| `tests/dock_tour.gd`, real mouse drags | **PASS** at iPad 4:3 (1366 × 1024), iPad Air 5 (1475 × 1024, 32 px bottom inset) and iPhone landscape (2208 × 1024, 154/154/55 px simulated insets). For 8 targets each (both halves, edges): tools and toy box never cover the item, confirm/cancel/turn stay inside the safe area, no flip-flopping while dragging or holding, back to the usual place after letting go |
| `art/pilot-10-v1/rebuild.sh` | all ten pilot GLBs rebuilt byte-identical from the versioned builders and skill |

Issues found and fixed during this revision:
- The camera glided back to the child while a finger dragged an item, so the item moved under the finger and the menus flipped. The camera now holds still.
- Leaving a house clamped the child into the room's 8 × 6 m area outdoors, up to 3.5 m from the door. The view now switches first.
- Animals could squeeze into gaps narrower than their bodies. They now stay put and re-plan.
- `restore` could put a decoration older than its table onto the floor during undo. It now restores in dependency order (from review).
- Support fit ignored rotation, and the old table's 0.9 square overhung its round top. Fit is now rotation-aware, inside an inscribed 0.84 square (from review).
- A Vorbis encode of the music padded 503 samples, which would click at the loop. The game uses a sample-exact WAV instead.

Screenshots: [docs/screenshots/godot/](screenshots/godot/) and [scale lineups](screenshots/godot/scale/). `net_friends.png` is revision-1 evidence (three real client processes) and shows the old tree scale.

## Revision 3 (release r1) — activities A-H, wall and ceiling placement, 130 production models — 2026-10-07

EC2 runs used Godot 4.7.2 with software OpenGL (Xvfb + llvmpipe), on exactly the `game/` bytes sealed as the Mac candidate `ipad-r1` (381 files, manifest SHA-256 `955dcc5c0f380d96591fb5eb6c95e9551b67d1629b0b4d53ce4db9464565a03f`). None of this is iPad or iPhone testing.

| Check | Result |
|---|---|
| `scripts/check.py` (venv) | PASS: 401 game messages in 6 languages; extracted strings; fonts cover 921 characters; English sources; doc links |
| `scripts/check_audio.py` | PASS |
| `tests/run_tests.gd` (headless) | **8057 checks, 0 failures**. Includes the scale contract on all 163 kinds (built bounds within 0.12 m of the catalog, ground/wall/ceiling origins, footprints, small-class heights), 140 modeled GLBs present and unpaintable, mounted items, and the activity rules (wishes, gifts, gardens, hearts and visits, photo ideas, activity saves, hide-and-seek warmth) |
| `scripts/net_test.py` | **NET TEST PASS** |
| `scripts/net_test.py --activities` | **ACTIVITIES TEST PASS**: conflicting starts, late joiner, presents, hearts, server restart (roles `hider`, `seeker`) |
| `tests/capture_tour.gd`, six languages | **TOUR PASS, 0 failures** |
| `tests/dock_tour.gd` | First run on the release tree: iPad 8 failures, all "'Gift' reachable": the test checked the fourth tools-row button by index, which became the new Gift button (correctly hidden while placing a new item). Fixed in the test only (Cancel is found by its label). Rerun: iPad 4:3 **PASS, 0 failures**. The EC2 iPad Air 5 rerun was stopped as a duplicate once the Mac took over; iPhone was not rerun on EC2 |
| Mac (macOS 26.3.1 arm64, Godot 4.7.2 GPU), candidate `ipad-r1` | Manifest verified; isolated import exit 0. Unit tests **8057 checks, 0 failures**; capture tour, six languages **TOUR PASS, 0 failures**; dock tour **PASS, 0 failures** at iPad 4:3, iPad Air 5 and iPhone landscape; activities tour **ACTIVITY TOUR PASS, 0 failures**. **Strict report: FAILED** for one reason only: every rendered run ends with `WARNING: 2 ObjectDB instances were leaked at exit` and `ERROR: 1 resources still in use at exit` (exit code 0), see Known issues |
| iPad build (Mac lane, user-authorized) | Signed Xcode build and codesign verification passed; PCK SHA-256 `576a62384f5d5dab60a7d35eddd59a2b55dae49d7abce8f5c5892cc476e72ffc`; installation on the USB iPad succeeded. Launch and on-device play were not yet verified (the device was locked) |
| Visual review of Mac PNGs (EC2 session) | 66 actual PNGs returned. Opened: activities `act_01` square, `act_03` dance party, `act_04` rain, `act_08` wish card, `act_11` gift picker, `act_13` garden bloom, `act_14` room with wall clock, ceiling mobile and guest book; tour `15_room_modeled_furniture`, `24_decorate_zh-CN`; dock `dock_iphone_low_center`. Activities, mounted pilot items, Chinese text and the iPhone tool bar render correctly. Defects noted under Known issues. This is not art approval or device acceptance |

Known issues recorded for this release:
- **Shutdown leak (pre-existing since revision 2, also on `b0f1fb7`).** At process exit the music autoload's looping `AudioStreamPlaybackWAV` is still owned by the audio server, so `res://assets/audio/meadow_lanterns.wav` (`AudioStreamWAV`) and the bus name StringName `Music` are reported. Reproduced on EC2 with a headless probe; stopping both music players, dropping their streams and allowing about 0.1 s (one audio mix) before `quit()` gives a clean exit. Planned fix for the next candidate: `Music.stop_for_exit()` plus a shared test exit helper at the nine test `quit()` sites. It does not affect play (one long-lived stream by design).
- **Activity square labels overlap.** The floating labels "Change the weather", "Hide and seek", "Photo ideas", "Evening" and "Party!" overlap each other, and the top ones are partly hidden by the status chip in some views (also in Chinese).
- **Release r1 models are not in any rendered tour.** The tours furnish pilot items only; the 130 production models are covered in-game by the unit tests (each is built and its bounds, anchor and footprint checked), not by screenshots.


Issues found and fixed during this revision:
- Eight wall models put their origin 5-13 cm off the vertical center; they ship as version 2 with a transform-only wrapper (a first attempt translated a sole glTF root, which Godot discards on import; the offset now sits on the original root under a transform-free wrapper).
- The game stores bounds as float32, so a 0.260 m wall item (breaker box) falls just below 0.2 H; it was excluded rather than relabeled, together with three other wall items outside the small-class height band.
- The dock tour's stale button index (above).
