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
- **Shutdown leak (pre-existing since revision 2, also on `b0f1fb7`).** *Fixed in the uncommitted A-H goal candidate, see the next section.* At process exit the music autoload's looping `AudioStreamPlaybackWAV` is still owned by the audio server, so `res://assets/audio/meadow_lanterns.wav` (`AudioStreamWAV`) and the bus name StringName `Music` are reported. Reproduced on EC2 with a headless probe; stopping both music players, dropping their streams and allowing about 0.1 s (one audio mix) before `quit()` gives a clean exit. Planned fix for the next candidate: `Music.stop_for_exit()` plus a shared test exit helper at the nine test `quit()` sites. It does not affect play (one long-lived stream by design).
- **Activity square labels overlap and crop.** *Fixed in the uncommitted A-H goal candidate (HUD name tags), see the next section.* The floating landmark labels "Change the weather", "Hide and seek", "Photo ideas", "Evening" and "Party!" overlap each other and are partly cropped under the top HUD (status chip): observed in `act_01_activity_square.png` and, in Chinese, `24_decorate_zh-CN.png` (Mac evidence of `ipad-r1`).
- **Release r1 models are not in any rendered tour.** The tours furnish pilot items only; the 130 production models are covered in-game by the unit tests (each is built and its bounds, anchor and footprint checked), not by screenshots.


Issues found and fixed during this revision:
- Eight wall models put their origin 5-13 cm off the vertical center; they ship as version 2 with a transform-only wrapper (a first attempt translated a sole glTF root, which Godot discards on import; the offset now sits on the original root under a transform-free wrapper).
- The game stores bounds as float32, so a 0.260 m wall item (breaker box) falls just below 0.2 H; it was excluded rather than relabeled, together with three other wall items outside the small-class height band.
- The dock tour's stale button index (above).

## A-H goal candidate (uncommitted, based on `f26f9c8`) — 2026-10-07

EC2, Godot 4.7.2, software OpenGL under Xvfb. None of this is iPad or iPhone testing. Raw logs are kept in `tools/goal-logs/` on EC2, and every log was scanned for `ERROR`, `leaked` and `still in use`, not only for assertion results. The A-H checklist is in [HANDOFF.md](../HANDOFF.md).

| Check | Result |
|---|---|
| `scripts/check.py` (venv) | PASS: 401 messages in 6 languages; fonts cover 922 characters, now including non-ASCII characters written directly in scripts |
| `tests/run_tests.gd` | **8074 checks, 0 failures**, exit 0 (new: `test_landmark_tag_layout` for the name-tag layout). The only engine line is `Parse JSON failed` from the intentional corrupt-save test |
| `scripts/net_test.py` | **NET TEST PASS**, exit 0. Server, five bots, restart check: no engine errors and no exit leak |
| `scripts/net_test.py --activities` | **ACTIVITIES TEST PASS**, exit 0, no engine errors and no exit leak |
| Rendered activities tour, capture tour (six languages), dock tour (iPad 4:3, iPad Air 5, iPhone) | all **PASS, 0 failures**, exit 0, no engine errors besides EC2's missing audio device and V-Sync, on the bytes just before the final server-only fix (guarding broadcasts to friends who are leaving). Not rerun on EC2 for the sealed bytes: the duplicate rerun was stopped once the Mac import passed |
| Frozen candidate `ipad-r2` (manifest `8ed0ab85531601fb3783a73e6a7dc4c945f32a3cce0c92e9f7a5115410ab196a`, 383 files) | Mac: archive downloaded, manifest verified, isolated import **PASS** (exit 0, no errors). Mac (macOS 26.3.1 arm64, Godot 4.7.2, GPU, Compatibility renderer, dummy audio driver), report status `automated_render_checks_passed`: unit **8074 checks, 0 failures**, exit 0 (only the deliberate corrupt-save `Parse JSON failed` and its warning, no leak); six-language tour **TOUR PASS, 0 failures**; dock tour iPad, iPad Air 5 and iPhone **PASS, 0 failures**; activities tour **ACTIVITY TOUR PASS, 0 failures**. Every stage exit 0 with **no engine errors and no shutdown leak** (the r1 strict-report blocker is gone). 66 PNGs; the coordinator and the EC2 session inspected `act_01`, `act_03`, `24_decorate_zh-CN`, `dock_iphone_low_center` and `22_scrapbook`. iPhone build, install, launch, touch and audio: **pending** |

Found and fixed while testing this candidate:
- The first activities tour run failed honestly: only 1 name tag fit, because from 8.5 m south four landmarks stand right under the top bar and the layout refused to overlap it. Tags now fall back below the landmark's foot.
- `get_meta("new", null)` still raises an error in Godot 4 (a null default counts as no default); it logged errors in every client during the network test while the assertions passed.
- The music leak survived one 0.12 s mix wait for a client that quit soon after the music started (net bot `check`, 3 of 3 runs). Three mix waits fixed it (verified with `--verbose`: the leaked objects were the music `AudioStreamWAV` and its playback).
- Pre-existing server errors when friends leave together (`disconnect_peer` on a peer that already left, sending to a closing WebSocket) are guarded.
- At the drum, its "Party!" tag repeated the action button and covered the child's name tag; the landmark offered by the action button no longer gets a tag.

Screenshots (Mac GPU, candidate `ipad-r2`): [activity_square_tags.png](screenshots/godot/activity_square_tags.png) (three name tags, compare the r1 image with overlapping labels) and [dance_party_lanterns.png](screenshots/godot/dance_party_lanterns.png) (all lanterns out during a party, no duplicate tag at the drum).

Repeated network checks on the sealed `ipad-r2` bytes: unit tests 8074 checks, 0 failures; `net_test.py` and `net_test.py --activities` run three times, all PASS, exit 0. Server and bot logs were scanned in every run: runs 1 and 2 have no engine errors or leaks; run 3's server log has **one** `ERROR: Condition "ready_state != STATE_OPEN"` from `_reply` (`_srv_stand`): a bot asked to stand up and closed its connection before the reply arrived. No client saw an error and nothing was lost, but it is an open engine-log race (the reply path is not yet guarded like the broadcasts). Not fixed because the source is frozen for the Mac candidate; proposed fix for the next candidate: skip `_reply` to a peer whose WebSocket is no longer open.

Not covered: the engine's `--quit-after N` debug flag skips the game's quit path and still reports the music leak. EC2 has no audio device (`ERR_CANT_OPEN` from ALSA in rendered runs).

## Toy box browser and crowded-room picking (uncommitted, candidate `ipad-r3`) — 2026-10-07

Design and acceptance examples: [design/item-browser-ux.md](../design/item-browser-ux.md). Candidate `ipad-r3`: 389 files under `game/`, manifest SHA-256 `c1a99e6f87d363897be1421761993514dffdee9b2baa62a57ba4d0ec595de196`, based on `4fe1552`. Catalog entries, models and the network/save code are unchanged.

EC2 development runs (Linux, software OpenGL; not device testing):

| Check | Result |
|---|---|
| `scripts/check.py` | PASS: 423 messages in 6 languages, fonts 948 characters (CJK subsets regenerated with `scripts/build_fonts.py`) |
| `tests/run_tests.gd` | **8354 checks, 0 failures**, exit 0. New: `test_item_query` (tabs equal the catalog, ranked localized search with English fallback, accents, full-width letters, Chinese substring, derived placement filters, Recent), `test_item_query_large_fixture` (a deterministic 2,000-entry **test-only** fixture, never in the game: 8.5 ms per query on EC2), `test_tap_choices` |
| `scripts/net_test.py` | NET TEST PASS (network code unchanged) |
| `tests/browser_tour.gd`, iPad, English | `BROWSER ipad PASS: 0 failures` (37 checks), no engine errors; on the bytes before the final dock-margin and style fixes |
| `tests/browser_tour.gd`, iPhone insets, six languages | 101 checks passed, none failed, then stopped by the EC2 time limit (exit 124) before the last section: **not a pass** |

Defects found in those screenshots and fixed before sealing: the hint and placement tools overlapped the taller toy box by about 10 px (the tools now follow its real height); the search placeholder was too faint; the chip row showed a heavy scrollbar. The Mac GPU run of the sealed candidate (unit, browser tour on iPad and iPhone in six languages, dock x3, capture tour, activities tour) is **pending**; device acceptance is not requested (no install authorized).

## r4: activity guide, PT-AH-001, private deployment and invites (uncommitted, candidate `ipad-r4`) — 2026-10-07

Candidate `ipad-r4`: 405 files, manifest SHA-256 `2786a051986694bf0448c66c6632315b7d02991d049f9a47255dcf4fa7f50926`. EC2 (Linux; no GPU tours by agreement):

| Check | Result |
|---|---|
| `scripts/check.py` | PASS: 513 messages in 6 languages, fonts 1036 characters |
| `tests/parse_all.gd` (new) | `PARSE PASS: 46 scripts`, twice. Added after a typed-variable parse error in `net_bot.gd` stalled an invite run (found by an independent diagnostic); an earlier version that recompiled running scripts crashed the engine and was replaced |
| `tests/run_tests.gd` | **9547 checks, 0 failures**. One run under heavy parallel load failed the fixture timing check (32 ms over a 30 ms limit); the check now takes the best of three passes (7.5 ms) |
| `net_test.py`, `--activities` | PASS, exit 0, process logs without engine errors (closing peers are dropped before broadcasts) |
| `net_test.py --invites` (new) | PASS: right, wrong, missing invite, reconnect, missing invite file exit 2, loose-permission warning, no secret in logs, `remote_check.py` live and mark/restart/verify |
| `scripts/check_packaging.py` (new) | PASS: injected private config packed, public copy packs none |

Not run on EC2: the rendered guide tour (iPad, iPhone, six languages), the PT-AH-001 pose at 1100x800, and the r3/r2 rendered regressions on r4 bytes; requested on the Mac. HK WSS checks are the operator's. No device acceptance.

Mac acceptance of `ipad-r5` (test-only correction of r4; 371 runtime files identical to r4), 2026-10-07: unit 9547 checks, 0 failures (only the deliberate corrupt-save JSON line); parse PASS; all ten rendered jobs PASS, each exit 0 with no other engine error or leak line: guide tour iPad and iPhone (six languages; r4 runs bound to identical runtime hashes), PT-AH-001 at 1100x800 (zh-CN, en), browser tour iPad and iPhone (six languages), dock tour iPad, iPad Air 5, iPhone, capture tour (six languages), activities tour. 206 PNGs. The EC2 session re-scanned every log in the evidence archive and inspected the PT-AH-001 photo and the German guide overview. The r4 PT-AH-001 failure was a test defect (UI-coordinate taps at a scaled window). Private packaging and the prefilled join address were verified locally by the operator; a signed iOS build was not installed. Hosted WSS checks and device acceptance are pending.

## r6: invite refusal feedback (candidate `ipad-r6`) — 2026-10-07

Operator report on r5 over the hosted WSS server: two-client place/move/remove, reconnect, wrong invite and restart persistence PASS; the missing-invite client was refused and closed without receiving the friendly reason (repeated). Reproduced locally with a relay that holds server bytes and delivers them with the close (`scripts/delay_proxy.py`, 800 ms): on r5 code both missing and wrong invites ended with an empty reason. Fixed in `session.gd` (client closes after reading the reason; server fallback close after 5 s). EC2: parse PASS; unit 9547 checks, 0 failures; `net_test.py` and `--activities` PASS; `--invites` PASS including the holding relay and a lingering client closed by the server; process logs clean. Hosted retest, Mac checks and device installs pending.

## r7: pets, themed rooms, cooking, Photos (uncommitted) — 2026-10-07

EC2, Linux, headless only (no rendered tours by request):

| Check | Result |
|---|---|
| `scripts/check.py` | PASS: 621 messages in 6 languages, fonts 1122 characters |
| `tests/parse_all.gd` | PARSE PASS, 53 scripts |
| `tests/run_tests.gd` | **11486 checks, 0 failures**. New: themed tabs offer every promised supply; set-up adds only missing pieces, once, keeping what was there; pet rules (families, variants, names, four at most, follow/home, care, saved-data cleanup); cooking rules (ingredients, reach, busy stove, serving, eating); r6 saves load unchanged; all ten modeled pets load with their joint hooks and the joints animate; scale contract for the new items; the Photos wrapper never claims a Photos save off iOS and the plugin asks for add-only access |
| `net_test.py --pets` (new, real clients) | PASS: adopt (a lizard is refused), the other client draws the pet behind its owner with the right model, set-up, cooking with a busy-stove refusal, serving, eating, shared cooking count, the pet leaves with its owner, restart persistence |
| `net_test.py`, `--activities`, `--invites` | PASS; all process logs without engine errors or leaks |
| `check_packaging.py` | PASS |
| `ios_photo_purpose.py` on a sample project | writes the six purpose strings, keeps existing entries |

Model integration: all 23 p001 GLBs matched their manifest digests before being copied. Not covered here: rendered views of the new items and pets, the iOS plugin build and Photos on a device, touch feel.

## r8: modeled kitchen and game room, bird repairs, Photos fixes (uncommitted) — 2026-10-07

EC2 headless only. Models: p002-game-kitchen (21) and p003-pets-r2 (2 birds) copied after their manifest digests matched; r7's p001 bird bytes replaced.

| Check | Result |
|---|---|
| `scripts/check.py`, `tests/parse_all.gd` | PASS (622 messages in 6 languages; 53 scripts) |
| `tests/run_tests.gd` | **11549 checks, 0 failures** (modeled count 174; r7 save kinds load as the modeled ones; after set-up every recipe can be cooked, pot on the counter, pan on the stove turned to fit) |
| `net_test.py --pets`, main, `--activities`, `--invites` | all PASS; process logs without engine errors or leaks |
| `tests/pets_tour.gd --no-shots` (headless logic only, de and ja) | **61 checks, 0 failures**, twice. Found and fixed: the pet layer missed an owner's room change made after the view switched; the kitchen starter blocked the way to the stove. Driver fixes: a tap that opened a resting pet's card, a lambda capture, taps before a dialog's layout settled |
| `scripts/test_ios_photo_purpose.py` (real exported project fixture) | PASS, 23 checks, idempotent |

Not covered on EC2: the rendered `pets_tour.gd` (Mac), the plugin build, Xcode links, simulator and device Photos checks.

r8b (test-only revision of r8): the Mac's strict scan found a SCRIPT ERROR in `test_pets_cooking_saves` (a float `%` in a fixture) that stopped the test before its r7-migration assertions, while the run still reported 0 failures. Fixed, and `run_tests.gd` now installs a `Logger` that attributes every engine and script error to its test and fails on any error not declared in `EXPECTED_ERRORS` (only the deliberate damaged-save `Parse JSON failed` in `test_session_solo`, which must also happen). Result: **11555 checks, 0 failures**; a run with the old expression restored fails with `unexpected engine error (SCRIPT ERROR)` and exit 1.

r8c (test-only revision of r8b): the Mac's rendered `pets_tour.gd` (iPhone, de/ja) passed everything except the Japanese recipe card: the driver tapped the stove in the same frame it closed the Pets dialog, while the closing full-screen shade (freed at the end of the frame) still stopped input (German first changed rooms and waited). Fixed in the driver: `close_dialogs()` waits until the overlay is empty (bounded, asserted) before the next tap. The game is unchanged (a player cannot tap within the frame of pressing Close). EC2 headless logic smoke: 74 checks, 0 failures.

## r9: play ideas batch 1 (uncommitted) — 2026-10-07

EC2 headless only; nothing rendered. Candidate `ipad-r9` (manifest `98a53c3d93ee0a7435d4477915a21ec39b47da403dbab1573fc8952327f2b41e`).

| Check | Result |
|---|---|
| `scripts/check.py`, `tests/parse_all.gd` | PASS (668 messages in 6 languages, fonts 1153 characters after `scripts/build_fonts.py`; 56 scripts) |
| `tests/run_tests.gd` | **12295 checks, 0 failures** (new: `test_play_rules`, `test_fetch_brain`, `test_play_session`; new props within 0.12 m of their catalog bounds; pet rename aliases) |
| `net_test.py --play` (new) | PASS: two real clients share a snack (both cheer), display refuses a friend's edit until taken off, snowman face, fetch (thrower sees Biscuit carry the ball back to 0.9 m, the friend sees the throw), restart keeps the face and display mark and not the eaten snack |
| `net_test.py` main, `--activities`, `--invites`, `--pets` | all PASS |
| `tests/play_tour.gd --no-shots` (new driver, de and ja) | **34 checks, 0 failures**, twice: real taps on Biscuit, Play fetch, a ground throw, toolkit tabs and cards, the snack card, Share, Change face, a rain puddle, Put on display, the ask-first dialog, cards inside the safe area |
| `tests/pets_tour.gd --no-shots` | PASS (regression) |

Found and fixed during the run: the toolkit tabs sit beyond the edge of the sideways tab row (the driver now scrolls a row like a finger before tapping). Not covered on EC2: rendering of the code-built snack and snowman props, the splash and ball effects, touch on devices, Photos on a device.

## r10: play ideas batch 2 (uncommitted) — 2026-10-07

EC2 headless only; nothing rendered. Candidate `ipad-r10` (manifest `05fb2db3ea827c262b56c2c667fa327c4a02e4827678b3df2e71ae9980c3fbfe`, archive `bba5cd85…b232a`).

| Check | Result |
|---|---|
| `scripts/check.py`, `tests/parse_all.gd` | PASS (738 messages in 6 languages, fonts 1196 characters after `scripts/build_fonts.py`; 60 scripts) |
| `tests/run_tests.gd` | **13337 checks, 0 failures** (new: `test_dress_and_poses` with the rig contract, `test_track_rules` incl. a closed loop, `test_trail_rules`, `test_music_box_rules`, `test_story_rules`, `test_batch2_session` with a restart, and a town-wide fetch sweep) |
| `net_test.py --batch2` (new) | PASS: two real clients; crown drawn on the friend's `Body/Head/Hat` with exact rig names after the rebuild; trail walked with clues (a wrong clue does not count); keepsake shared; the friend's tune heard nearby, and the local mute silences it for that device only; ball to the finish; story poses seen; restart keeps sign numbers, keepsake, tune and track |
| `net_test.py` main, `--activities`, `--invites`, `--pets`, `--play` | all PASS; no SCRIPT ERROR, engine ERROR or leak in any process log of the final run |
| `tests/play2_tour.gd --no-shots` (new driver, de and ja) | **57 checks, 0 failures**, twice before the final run and once in it: Dress up card, hat and color; Story card, a pose, three panels (blank images: no renderer), reorder (verified in the kept strip) and Keep; two signs from the toy box, the sign card, Follow, the arrow, waves at each sign, keepsake; music card, a square, Play, notes heard, Mute and unmute; track roll to the finish, gap arrow and hint, switch flip by tap, side finish; cards inside the safe area |
| `tests/play_tour.gd`, `tests/pets_tour.gd` `--no-shots` | PASS (34 and 74 checks) |

Found and fixed while testing batch 2:

- **Kid rig rebuild names** (`kid.gd`): a dress-up change rebuilt the child with `queue_free` before detaching, so the new `Body` was auto-renamed for that frame and the documented `Body/Head/Hat` path broke. Children are now detached first; unit and network checks assert the exact names after a rebuild.
- **Fetch could be abandoned** (`animal_brain.gd`, batch 1 code, found by the regression `net_test.py --play`): animals steer in straight lines, so a throw behind a bench or tree left Biscuit stuck; he gave up and wandered (9 of 238 throws in a town-wide sweep). The ball now stops or glances aside (up to 80°) at the farthest point the dog can run to and back from, and the hand-over counts within 1.3 m of the child. Sweep: 0 lost of 238; 8 throws by a child hemmed in on every side drop at their feet. The unit sweep fails on the old code (verified) and passes now.
- **Server SCRIPT ERROR on leaving peers** (`session.gd` `_drop_closing_peers`, older code): a peer it had just closed was still listed for a frame and `get_peer()` returned null. Dropped peers are now remembered and skipped.
- **Intermittent engine send error when friends leave together** (older code; also seen on the frozen r9 code, 1 of 3 runs): the engine's own peer relaying announced a leaving peer to a socket that was already closing. All messages go through the authority, so relaying is now off (`server_relay = false`) and Session processes first each frame. After the change 0 of 6 main runs logged it (before: about 1 in 4 to 6). Intermittent, so this is evidence, not proof.

## r11: deferred play ideas and follow-ups (uncommitted) — 2026-10-07

EC2 headless only; nothing rendered. Frozen candidate `ipad-r11` after the final run: manifest `f22891d4c1059d55635d6b6f6dd3651681da0fa887d6fb2ff0acaee0c45e19b1` (540 files), archive `c75d42309af0e76ac6cc40292b65c54bccfa9737f463f7462ca723ab204ddcb8`. The first full regression attempt was stopped by the host for low memory (not a test result); the final run went one suite at a time.

| Check (final code) | Result |
|---|---|
| `tests/parse_all.gd`, `scripts/check.py` | PASS: 63 scripts; 825 messages in 6 languages, fonts 1220 characters |
| `tests/run_tests.gd` | **14501 checks, 0 failures** (new: `test_invite_rules`, `test_animal_games`, `test_blueprint_rules`, `test_r11_props_and_rig`, `test_r11_session` including the back-to-back invitation regression, verified to fail when broken) |
| `net_test.py --r11` (new; twice) | PASS: two different invitations back to back both sent and the newer card replaces the older on the server; the same one again held back; help-edit refused before Join, allowed as helper, refused again after Leave; music invitation joined, a claimed part refused to the friend, a free part played; the friend joins Wooly's running game; a together leaf jump; a blueprint placed and seen by the friend; after a restart the display mark stays and helpers are gone |
| `net_test.py` main, `--activities`, `--invites`, `--pets`, `--play`, `--batch2` | all PASS |
| All of the above | 0 SCRIPT ERROR, engine ERROR or leak lines in every bot and server log |
| `play3_tour.gd --no-shots` (new, de and ja) | **62 checks, 0 failures**: clothes style and umbrella prop at `Body/ArmR/Hand`; Wooly's card and an answered dance; Tumble's star fountain; boat sails and returns; leaf jump; blueprint save, list, preview move and turn, Place here, Undo; Suggest a trail; no Invite buttons when alone; two invitation cards (one per friend), Not now, Join walks over; a music part taken and released; cards inside the safe area |
| `play2_tour.gd`, `play_tour.gd`, `pets_tour.gd --no-shots` | 57, 34 and 74 checks, 0 failures |

Found and fixed during r11 testing:

- **Different invitations back to back** (product): see design/playability-8-12.md. The first failing `--r11` run did not record the reply; reproduced with a focused script (help then music: second refused), fixed, and covered by unit and network checks.
- **Invitation card expiry** (product): its timer captured the card, logging an engine error if the card had been answered.
- **Animal games abandoned** (product): an animal stuck near its play spot gave up silently; it now plays there.
- **Wooly's hop** (product): the movement code reset a "hop" answer; answers are standing moves.
- **`--invites` harness race** (test): one run failed because the friend who must be seen joined late (the host was short on memory) and was in its planned leave/rejoin gap at the single 14 s check; the server log shows the invited friend's two joins and no uninvited joins. The check now watches the whole time: the invited friend must arrive and nobody without the invite may ever appear (stricter than before). With the old check the suite passed 3 of 4 runs; with the new check it passed the 1 run made in the final regression.
- **Tap tour harness** (test): after Join the child was still walking; the tours' teleport helper now stops a walk first.

Not covered on EC2: every rendered image (props, prop on the rig, fountains, boats, previews, cards), the story caption band and real camera panels (blank fixtures only), touch on devices, Photos on a device.

## r11 Mac evidence review and r11b fixes (uncommitted) — 2026-10-07

**Mac evidence for ipad-r11** (`tools/dual-host-workflow/ipad-r11/mac-evidence.tar.gz`, SHA-256 `5374b1ebed0bdb412c6e03f45d9e25ad09d2ecd8fc3a86ebf4ae980e57e3af47`, uploaded with the user's approval; verified and extracted to `ipad-r11/mac-evidence/`; macOS arm64 OpenGL, candidate `f22891d4…e19b1`): parse 63 PASS; units 14501/0 (only the damaged-save line); `--r11` and `--batch2` PASS with clean bot and server logs; rendered play3/play2/play/pets tours PASS with 8/9/9/11 screenshots; real story strip 1504 x 464 with the German title over three real camera panels. The first editor import crashed in Godot's threaded font reimport (an engine thread calling `propagate_notification`, signal 11); the retry with `--single-threaded-scene` passed (both logs kept). Reported outside the archive: an unsigned Debug iphoneos build and link PASS. No install, real Photos write or HK update.

**Review of the images** (15 of the 37 tour screenshots opened, plus the story strip; all 37 checked against the logs): the music box "Bell" row was English in German and Japanese (a real localization defect: the key was missing from every catalog because the extractor treated "Bell" as an identifier word); the paper boat sailed a circle that crossed the pond's rim stones (a real defect; the pond is an ellipse) and was shot distant and early; Tumble's fountain was shot behind a tree on its first frame, and its shape could face edge-on; the umbrella swung sideways during story poses; the music Play button kept the play icon while saying Stop. Framing only (no change): trees can hide the child.

**r11b** (`ipad-r11b`, manifest `13330641b8c195a5e78b8cffea55e8d8a9515d20b3b014ae774dd2bf79723fe1`, archive `ccbadb8a9f3c66a297e0ec21278aa572e4e9d7936a49355535262e9079251baa`, 540 files, 12 differ from r11) fixes all five; details in its `LOCAL_VALIDATION_REQUEST.md`.

| Check (r11b, EC2 headless) | Result |
|---|---|
| `parse_all.gd`, `scripts/check.py` | PASS: 63 scripts; 826 messages in 6 languages, fonts unchanged (characters already covered) |
| `run_tests.gd` | **14528 checks, 0 failures**; new `test_r11b_review_fixes` (all player-facing name lists in six catalogs, the boat lap inside the water for 8 pond turns, a prop upright in every emote and pose); with ja "Bell" removed and the upright-hand line disabled, 4 checks fail as intended |
| `--no-shots` tours | play3 63 (asserts the boat is on the water mid-lap), play2 57, play 34, pets 74; 0 failures, 0 error lines |
| `net_test.py --r11`, `--batch2` | PASS, 0 error lines in every log |

Not covered on EC2: every rendered image (the fixed boat lap, fountain, upright umbrella and translated labels need the Mac's rendered `play3_tour` and `play2_tour` and a new real story strip).

## r11b Mac acceptance and r11c (test-only) — 2026-10-07

Mac on `ipad-r11b` (reported by the coordinator; logs stay on the Mac): single-threaded import, parse 63 and units 14528 PASS; rendered `play2_tour` PASS (9 PNGs, 0 errors; real story strip 1504 x 464 with the German title and the umbrella upright in all three panels; the Japanese music card shows the translated bell row and a stop mark); rendered `play3_tour` **FAIL, 3 failures** (Tumble's card did not open on the real tap, so no fountain).

**Cause, measured on EC2:** the tour aimed real taps while the camera was still easing after a jump. Running play3 headless at `--max-fps 60` reproduced a failure: the camera moved 0.505 m during the boat tap and the target drifted 160 px (pick radius 60 px). Uncapped headless taps finish in about 2 ms, which hid this. **Fix (r11c, test harness only):** `settle_camera()` before aiming, drift logging, and a detailed report on a missed animal tap; nothing loosened. After the fix: play3 at 60 fps 3 of 3 PASS (taps drift under 0.5 px), uncapped PASS; play2, play and pets at 60 fps PASS; 0 error lines.

`ipad-r11c`: manifest `81a12c111729f0366e8a615082f026a9a80574f628746d036bd1b83c1d7eae7a`, archive `959b732dd6d3cd01af2bbba33dccb344c9bb63fba340b9951a495703ce597db3`; only `game/tests/pets_tour.gd` and `game/tests/play3_tour.gd` differ from r11b. Mac result below.

Product note (not changed): while the camera eases after a jump (about one second), a tap on a moving thing is handled one frame after it was seen, so a fast-sliding view can shift a real child's tap slightly; the 60 px pick radius covers normal easing, and the tour's 160 px came from aiming two frames early at the start of a long slide.

### r11c Mac acceptance — PASS (2026-10-07)

Evidence `tools/dual-host-workflow/ipad-r11c/mac-evidence.tar.gz` (SHA-256 `20c828a4b9d50e7e5d127345eb8464ff2965b8ced0e566c06853044cd87a006c`, uploaded with the user's approval; verified; 28 regular files, no unsafe paths; extracted to `ipad-r11c/mac-evidence/`). Candidate `81a12c11…eae7a`; the Mac confirmed only `pets_tour.gd` and `play3_tour.gd` differ from r11b and no sealed input changed during the tests.

- **Mac automated:** parse 63 PASS; rendered `play3_tour` (iPhone 2208 x 1024, safe insets, de/ja) **PASS**, 43.66 s, 8 PNGs, no failure, error or leak lines; tap drift sheep 0.4 px, elephant 0.3 px, items 0.0-0.4 px. Reused from source-identical r11b (product bytes equal): units 14528/0, rendered `play2_tour` PASS (9 PNGs), the real story strip, and `--r11`/`--batch2` from r11.
- **Import caveat:** the first r11c import crashed in Godot's font reimport (exit -11) even with `--single-threaded-scene`; the same command succeeded on retry. The flag is **not** shown to prevent this engine crash; it is an intermittent engine-side import issue, not game code.
- **Author image review (originals opened):** `play3_iphone_03_tumble_fountain` (a clear star of droplets over Tumble on open lawn, nothing in front), `play3_iphone_04_boat_sailing` (the white paper boat on the water inside the stone rim; small at gameplay distance, which is the normal camera), `play3_iphone_07_invite_cards` (two German cards, one per friend, Join and Not now, preset nicknames translated), `real-story.png` (1504 x 464, German title, three real camera panels, umbrella upright above the child in all three), `play2_tour-r11b/play2_iphone_08_de_music_card` (Glocke, stop mark) and `..._09_ja_music_card` (the Japanese bell label, stop mark). **Visual acceptance: PASS.**
- **Test-fidelity finding (recorded as it happened in r11c; resolved in r11d below):** in the Mac log the boat tap was aimed at (2096, 1437), below the 1024 px bottom edge: the boat placed from the toy box sat off screen toward the camera, and the game's screen-distance pick still matched it, so "tapping the boat sails it" passed on a tap a finger could not make. r11c's play3 pass therefore does not count as tap usability for the boat.
- **Outside Mac acceptance (kept separate):** unsigned Debug iphoneos build and link PASS on product-identical r11b (device families iPhone and iPad, add-only Photos purpose in 6 localizations, not installed); a public `server.pck` exported locally and started on loopback (SHA-256 `75af3e40…a4738`, no private deployment file, not uploaded). **Not performed:** device install, real touch, a real Photos write, any HK update. HK read-only check: still r8c, protocol 5. The paired iPhone and iPad were disconnected at the last check.

## r11d: no impossible synthetic taps (test-only) — 2026-10-08

`ipad-r11d`: manifest `457c9faa0b4e76529cdeaf2d5217f0e43d75a4acf7d411f857e45aed5888d0c0`, archive `ae37d661388296b874d913c6e24928a1cb8324b0767547baa66dd90d32b09d2e`; only `game/tests/{pets_tour,play_tour,play3_tour}.gd` differ from r11c (product bytes identical). Details and the Mac command: its `LOCAL_VALIDATION_REQUEST.md`.

- **Reachability assertion:** every world tap and drag in the tours is sent only if it is in front of the camera, inside the visible view and the safe area, and not under an input-taking HUD control; otherwise the check fails and no event is sent.
- **Mac geometry on EC2:** headless ignores `--resolution`; the tours' `--window=2208x1024` reproduces the iPhone layout. With it the old boat approach fails the new check (aim 2171, 1591), and a second impossible tap was found and fixed in play_tour (the fetch throw aimed at y 1209, toward the camera; it now throws up the screen). Earlier play_tour passes, on EC2 and on the Mac, included that off-screen throw tap.
- **Framing fixes:** the child stands beside the boat and the leaf pile before tapping; framing peeks end after their screenshot and never count as a settled camera (a pinned camera had hidden an off-screen aim on fast runs); a red placement ghost is moved by a real drag.
- **Results (EC2 headless):** play3 72 checks PASS at Mac geometry (twice, 60 fps) and at the default geometry; play_tour 43, play2 66, pets 92 PASS at Mac geometry (60 fps); every aim inside the safe area; 0 error lines; parse 63 PASS. Mac result below.

### r11d Mac acceptance — PASS, final guarded-input result (2026-10-08)

Evidence `tools/dual-host-workflow/ipad-r11d/mac-evidence.tar.gz` (SHA-256 `ededbde3c6cc47c4a93d546577f103530f7457878d16b0191c913adceb9e49c3`, uploaded with the user's approval; verified; 22 regular files, no unsafe paths; extracted to `ipad-r11d/mac-evidence/`). Candidate `457c9faa…8d0c0`; the Mac confirmed all 540 sealed inputs unchanged after the tests and exactly the three tour files differing from r11c. Import reused the Mac's same-engine cache for byte-identical assets (exit 0); parse 63 PASS.

- **Rendered (iPhone 2208 x 1024, safe insets, de/ja):** `play3_tour` **PASS** (43.63 s, 8 PNGs) and `play_tour` **PASS** (21.69 s, 9 PNGs); no failure, error or leak lines. Every guarded "tap is on screen" check passed; I re-parsed all 12 aimed taps from the logs: all inside the safe area x 162-2046, y 8-961 (boat 897, 627; leaf pile 900, 629; Tumble 947, 476; fetch throw 1104, 269), drift at most 0.6 px; the snack ghost was moved by a real drag (start guard PASS) and fit.
- **Author image review (originals opened):** `play3_iphone_03_tumble_fountain` (clear star of droplets over Tumble on open lawn), `play3_iphone_04_boat_sailing` (the paper boat on the water inside the stone rim, its stand by the child), `play_iphone_02_fetch_carry`, `play_iphone_04_snack_made`, `play_iphone_06_puddle_splash`. **Visual acceptance: PASS.** Observations only (batch-1 screenshot framing, no failure, nothing changed): in the fetch and snack shots the dog and the snack partly sit behind the child, the umbrella or the hint bubble, and the splash is a small burst at the child's feet; their checks assert the behavior directly.
- **Reused (product bytes identical to r11b and r11c):** units 14528/0 (only the damaged-save line); rendered `play2_tour` PASS with the real 1504 x 464 story strip (German caption, real camera panels, upright umbrella); German/Japanese music cards (translated bell row, stop mark); unsigned Debug iphoneos build/link (iPhone and iPad) with the add-only Photos purpose in six localizations; `--r11`/`--batch2` network and pets evidence.
- **Superseded results kept as recorded:** r11b play3 FAIL (camera-easing tap race); r11c play3 PASS whose boat tap was aimed off screen (2096, 1437), not counted as tap usability. r11d is the first result with every synthetic input guarded as reachable.
- **Not part of this acceptance (external gates):** the paired iPhone and iPad are disconnected; real touch and a real Photos write are NOT TESTED; no device install. The public `server.pck` and the unsigned universal iOS app (built from product-identical r11b) are ready for final packaging but not installed or uploaded. HK remains r8c, protocol 5; the protocol 8 client and server need one synchronized, authorized update.

## r12: wearables in the game, protocol 9 (uncommitted) — 2026-10-08

`ipad-r12`: manifest `d74944cc47a11033cbb6c0422093ef28366d2d167979be2f97615349ece8c180`, archive `8a0172ea1aedb5e7b1d0696bb60dba7789b89cccb95bc5aa7d1fafb504dbad9f`, 1416 files. Details, inventory and the Mac command: its `LOCAL_VALIDATION_REQUEST.md`; report: [wearables.md](wearables.md).

- **Release context (recorded, not repeated):** r11d is installed on the iPad and the iPhone, and HK runs protocol 8 (Codex, 2026-10-08 08:18 CST, owner-authorized). Live WSS, invites, reconnect and restart passed, and all 130 town ids were retained. Human touch and a Photos write are still unverified.
- **Model inputs:** 13 frozen batches, digests and every GLB hash checked (`scripts/build_wear_catalog.py --check` PASS). 434 accepted, 0 gated: the rev5 hold records c018/c019 were frozen and finally accepted on 2026-10-08, and they cover the same GLB bytes as c014/c013.
- **EC2 results (headless Linux; not device tests):**
  - units 19548 checks, 0 failures;
  - parse 65 PASS; `check.py` PASS;
  - `net_test.py --wear` PASS (41 checks, two real WebSocket clients plus a restart);
  - at Mac geometry (`--window=2208x1024`, safe insets, 60 fps, de/ja): `wear_tour` 130, play2 66, play3 72, pets 92, play 43, all PASS, every aim inside the safe area, 0 error lines.
- **Found and fixed by the new tests:**
  - the Wardrobe card was 985 px on a 969 px safe height;
  - Reconnect lost changes made to the look in town.
- **Not tested:** Mac rendered run (requested); device touch, performance and Photos; the protocol 9 HK update (needs authorization).

### r12 Mac result — FAIL (rendered wear_tour), recorded as it happened (2026-10-08)

Evidence: `ipad-r12/mac-evidence.tar.gz` (SHA-256 `f3100f529940bd0969e10c8a7121b837b4ccf89b90d08f221fd5bcb265d00c0a`, 3125220 bytes; report, logs and 9 original PNGs; extracted to `ipad-r12/mac-evidence-r12/`). Engine: official Godot 4.7.2, OpenGL, M1 Pro.

- **Passed:**
  - import (9.93 s); parse 65 (1.62 s);
  - units 19548/0, with only the deliberate bad-JSON line (21.87 s);
  - targeted `net_test.py --wear`, logs clean;
  - the PhotoLibrary source equal to r11d.
- **Failed:** the rendered `wear_tour` (exit 1, 83.01 s). `[de] the Wardrobe fits the safe area` after rejoin: P(804, 0) S(600, 985), on a 969 px safe height. The first German card (953 px) and the Japanese card (923 px) had passed.
- **Image review (originals opened):**
  - The rig integration reads correctly at the game's closest camera distance: the umbrella upright in the right hand while waving; the seated skirt with hands over the knees on the bench, the umbrella put away; seated on the swing, the umbrella hidden.
  - Two problems: `top_and_bottom` and `seven_slots` were covered by the card; and in de/ja long names were clipped, so tiles with the same visible start ("Antikes Gewand mit", "Paradise Planning…") could not be told apart.

## r12b: Wardrobe layout and readable names — 2026-10-08

`ipad-r12b`: manifest `165bea09c43bc50c5bdefe6546767b853ff0bc15135bc1f9ace7210d37a3601a`, archive `071eaebbd0a229167179fd7d9209bd5f1f0062267c2235edf4a450f48272d486`. Only `hud.gd`, `wear_tour.gd`, `run_tests.gd` and `docs/wearables.md` differ from r12.

- **Cause of the failure:** the card height was measured once, a frame after opening; on the Mac the German tabs wrapped later. The list now refits whenever the card's minimum size or the safe area changes.
- **Name fix:** tiles wrap whole names; names are unique per tab in six languages (unit-checked).
- **Tour:**
  - the fit must hold on 20 consecutive frames after the card opens, and again after a language switch with the card open;
  - character shots have the card closed; the wave shot is taken mid-wave.
- **Proof:** the new tour run against r12's `hud.gd` on EC2 reproduces the Mac failure (`[ja -> de, card open]` 985 px). With r12b, at Mac geometry: wear_tour 150, play2 66, play3 72, units 19554/0, all PASS, 0 error lines.
- **Not tested:** the Mac rendered run of r12b (requested); devices; the protocol 9 HK update.

### r12b Mac acceptance — PASS, final visual acceptance of the in-game wardrobe (2026-10-08)

**Evidence:** `ipad-r12b/mac-evidence.tar.gz`, SHA-256 `c504f38b41a5c9bd290f8d1a06f9708e3823d7173879223273164943f9ed6299`, 3143023 bytes.
- Verified; 15 regular files, no unsafe paths or links; extracted to `ipad-r12b/mac-evidence-r12b/`.
- Contents: report, 4 logs, the reused network result and 9 original PNGs.

**Mac runs** (official Godot 4.7.2, OpenGL, M1 Pro; candidate `165bea09…3601a`):
- import 4.67 s (identical-asset cache reused); parse 65 PASS (1.53 s);
- units 19554/0 PASS (21.41 s), with only the deliberate bad-JSON line;
- **rendered `wear_tour` PASS** (65.53 s, 9 PNGs), with no FAIL, error or leak lines.

The Mac confirmed that the tested work files all match the frozen manifest, and that exactly the four declared files changed from r12.

**What the log shows:**
- Every "fits the safe area on each of 20 frames" check passed, including both live language switches with the card open: German 953 px, Japanese 923 px.
- Wrapped tiles: Tops 14 of 49; German Dress-up 22 of 50 (tallest 122 px); Japanese Dress-up 26 of 50.
- Tap aims drift at most 0.5 px.

**Reused from r12** (those bytes are unchanged): the targeted `net_test.py --wear` PASS, the rig views, and the PhotoLibrary source equal to r11d.

**Author image review** (all 9 originals opened). **Visual acceptance: PASS** for in-game integration.

| Shot | What it shows |
|---|---|
| `01_top_and_bottom` | The child in the tee and jeans, card closed |
| `02_seven_slots` | Beret (hair hidden), goggles, bag, socks and shoes on the unobscured child |
| `04_wave_with_umbrella` | The ladybug umbrella upright in the right hand over the standing skirt |
| `05_bench_seated` | The seated skirt, hands over the knees, umbrella put away |
| `06_swing_seated` | Seated on the swing, umbrella hidden |
| `07_taken_off` | Dress-up and umbrella gone; the other items remain |
| `08_de_wardrobe` | Whole names wrap at word boundaries ("Kuscheliger Paradise Planning-Mantel" on three lines; "Paradise Planning-Kleid" and "...-Maxikleid" now distinct); card inside the safe area |
| `09_ja_wardrobe` | Whole names wrap; card inside the safe area |

Rows cut at the edge of the list's scroll view are partial rows, not clipped names.

**Limitations** (confirmed in the images; recorded, not changed):
- A long single German word next to the worn check mark breaks mid-word ("Marienkäferschi / rm" in `03_wardrobe_umbrellas`).
- Japanese wrapping can start a line with a small kana (the "cheerleading uniform" tile).
- At the game's closest camera distance the child is small. The left-arm wave is not clearly visible in the wave shot; it is asserted numerically (left arm up to 2.95 rad, right arm 0.000 rad outside the hold envelope).
- The swing shot is taken from behind and above, so the seated garment is barely visible.
- From the model acceptance: rigid parts, sleeve steps, simplified seated fronts.

**Not part of this acceptance:**
- real touch on iPhone and iPad, device performance and a real Photos write: NOT TESTED;
- the protocol 9 HK and app update, which needs authorization (HK and the installed r11d apps are protocol 8);
- art approval of the garments.

Signed device packaging is being prepared separately. Nothing was committed, pushed, deployed or installed.

## r13: 42 wall and ceiling models, headroom rule — 2026-10-08

`ipad-r13`: manifest `f8a92ee5cb1bc1ede90e3033cfbed1c7d718323005755abcfd4bdc8d9fc21db9`, archive `991ff366661a1859d0257a75f545b6a1baadc72453eff818124ff1de0ce2a037`, 1505 files, based on the installed r12b. Inventory and hashes: [design/model-release-r2.md](../design/model-release-r2.md). Mac command: its `LOCAL_VALIDATION_REQUEST.md`.

- **Inputs:**
  - the 42 `model_complete` furniture references map to 42 unique models, none already present;
  - frozen `b011-furn-r2` (`1b10021d…c86abe`) supplies 31 and `b012-furn-r3` (`cd8e0084…eafda5`) the 11 defect-notice repairs;
  - every digest and GLB hash is checked (`scripts/build_furniture_r2.py --check` PASS);
  - the 19 blocked references stay excluded.
- **Contract:**
  - the existing anchor gates are unchanged;
  - new headroom rule on place and move, enforced by the authority;
  - `model_offset` centres the antler mount (7.1 cm) without rewriting the frozen GLB.
- **EC2 results (headless Linux; not Mac or device tests):**
  - units 20778/0, with only the deliberate bad-JSON line; the planted headroom failure fails 6 checks;
  - parse 66; `check.py` PASS;
  - `net_test.py --furniture` PASS (create, move, remove, server refusal, reconnect, restart), `--wear` PASS, main PASS, all logs clean;
  - tours at Mac geometry, de/ja: furn 56, pets 92, play 43, wear 150 PASS, every aim in the safe area, 0 error lines.
- **Not tested:**
  - the Mac rendered `furn_tour` (requested);
  - the app + HK update;
  - device touch and performance with many evening lamps;
  - human art review.

### r13 Mac result — automated PASS, visual REPAIR_REQUIRED, recorded as it happened (2026-10-08)

**Evidence:** `ipad-r13/mac-evidence.tar.gz` (SHA-256 `50b5347f33ac42a656f8dbe75fe22fe0a526a980ba48cce01aa3ef58dabfa64d`, 2551194 bytes). Verified, with no unsafe paths or links, and extracted to `ipad-r13/mac-evidence-r13/`. It holds the report, logs, network logs and 6 original PNGs. The frozen manifest `f8a92ee5…21db9` was verified, all 1505 files, unchanged after the tests.

**Automated (Apple M1 Pro, gl_compatibility, 2208 x 1024, safe insets):**
- import 10.15 s; parse 66 PASS;
- units 20778/0, with only the expected bad-JSON line;
- rendered `furn_tour` PASS (0 failures, 6 screenshots, 56.42 s);
- targeted `net_test.py --furniture` PASS with clean raw logs.

**Visual review (all 6 originals opened).** Confirmed problems:
- `05_de_toybox_ceiling`: two adjacent cards both read "Hängelampe mit..."; long German words break mid-word ("Deckenventilat / or mit Licht", "Bühnenlichtleis / te"); other names end in an ellipsis.
- `06_ja_toybox_ceiling`: names are cut at two lines.
- `02_room_day`: the lingering "Placed!" toast covers the back wall, so the wall items cannot be inspected.
- `03_headroom_red`: the same toast lies over the Turn, Cancel and Place here tools; the red footprint and the refusal text are visible.

Seen working: `04_room_evening` shows the three lamps lit. The fan and other static items remain documented limits.

## r13b: readable toy box names, messages clear of placement tools — 2026-10-08

`ipad-r13b`: manifest `f33dc3826431c2de52ce5e234d67f0655857159f47a74221d3fca6cd80a54ec9`, archive `33d56a3af8be15bc3ca48c0ca5f948f345e7c1b515d8ddad96be02ee5611896a`. Only `hud.gd`, `ui_kit.gd`, `ja.json`, `es.json`, `run_tests.gd`, `furn_tour.gd` and `design/model-release-r2.md` differ from r13.

- **Names:** the toy box card name is fitted by measurement (`UI.fit_text`). It breaks between words only, uses up to 3 lines at 13-16 px and is never ellipsised; a card widens only for a single over-wide word (9 German names, up to 148 px).
  - A unit test covers every catalog name in six languages, including the seven long German names the Mac flagged.
  - It also found and fixed three older duplicate names in one tab (ja Plush bear and Garden bed, es Plush bear).
- **Messages:** a new placement clears the stale placement message, and messages move clear of the placement tools before they fade in. The tour asserts no overlap on 20 frames, and takes the room and headroom pictures after messages fade.
- **Proof:** the new tour run against r13's HUD fails on the Mac's findings and passes with r13b.
- **EC2 (headless, Mac geometry):** units 20796/0; `furn_tour` 69, `play_tour` 43, `pets_tour` 92, `play3_tour` 72, all PASS, 0 error lines.
- **Not tested:** the Mac rendered run of r13b (requested); devices; the app + HK update.

### r13b Mac acceptance — PASS, final visual acceptance of the wall and ceiling models (2026-10-08)

*Pre-release snapshot: recorded before r13b was shipped. The release that followed is recorded in the next section, "r13b release".*

**Evidence:** `ipad-r13b/mac-evidence.tar.gz` (SHA-256 `9f90d807c42e072ad5587a17458d74a571fe13732264d22e51955cec42bc4943`, 2586712 bytes; uploaded with the user's approval).
- Extracted to `ipad-r13b/mac-evidence-r13b/`: no unsafe paths or links, and all 16 entries of `evidence-hashes.json` match.
- Candidate `f33dc3826431c2de52ce5e234d67f0655857159f47a74221d3fca6cd80a54ec9`; all 1505 inputs unchanged.

**Mac results:**
- import, parse 66 and units 20796/0 PASS (only the deliberate bad-JSON line);
- rendered `furn_tour` (Apple M1 Pro, OpenGL, 2208 x 1024, safe insets) PASS on foreground retry 2: 69 assertions, 0 failures, 6 PNGs, exit 0.

**Preserved failures:** two earlier r13b attempts and an r13 control run stalled at "item thumbnails are ready" (the control also hit its 100 s timeout). The same frozen candidate passed once the window was in the foreground. The exact host cause is not established.

**Network:** the r13 Mac `--furniture` PASS is reused (network, save, placement and model bytes are identical).

**Author image review (all six originals in `furn_tour-retry2/` opened). Visual acceptance: PASS.**

| Shot | What it shows |
|---|---|
| `01_toybox_ceiling` (German UI) | Whole names, broken between words only ("Deckenventilator mit Licht", "Doppelte Hängebildschirme", "Bühnenlichtleiste", "Dunstabzugshaube"); no ellipsis, no mid-word break. |
| `02_room_day` | No message over the room. Chandelier, paper-lantern string and ceiling fan hang from the ceiling. The insect chart hangs on the back wall left of the stairs; the antler mount on the back wall right of the stairs, partly behind the hanging lanterns from this camera. |
| `03_headroom_red` | The red pavilion footprint; the tools Drehen, Abbrechen and the disabled Hier platzieren fully visible, with the reason "Dort ist unter der Decke nicht genug Platz." below them; no message covers anything. |
| `04_room_evening` | The chandelier and the lantern string glow; the wall items have no lamp. |
| `05_de_toybox_ceiling` | "Hängelampe mit Kegelschirm" and "Hängelampe mit Trommelschirm" side by side, each in full on three lines; the other names are whole. |
| `06_ja_toybox_ceiling` | Whole Japanese names, wrapped and distinguishable. |

**Limitations (confirmed in the images; recorded, not changed):**
- Long German names use the smallest card font (13 px) and are small at this distance.
- Japanese wrapping may leave a single kana on the last line (the string of paper lanterns card).
- From the game's camera the antler mount is partly hidden behind the paper-lantern string placed in front of it.
- The fan's own lamp is faint compared with the chandelier.
- Ceiling items cannot be turned, and the fan, mirror ball and screens are static.

**Not part of this acceptance:** device touch, audio, Photos and performance; human art review; the app + HK update that would ship r13b. That update was not authorized at the time of this acceptance; it was completed afterwards (next section).

### r13b release (coordinator-reported, 2026-10-08)

*Completed after the pre-release acceptance above: this supersedes its "not authorized" note about shipping.*

Recorded as reported by the Mac coordinator. The evidence (`build/dual-host/ipad-r13b/rev1/release-result.json`, `hk-release/final-state.json`) is local to the coordinator and was not read from EC2.
- **Release:** r13b (`f33dc382…3601a`) is installed and launched on the iPhone and the iPad (the same signed universal app) and deployed to the existing HK server. Public pack `ebb723ee5604cea176ff6c54bd605a64315514edfe1b537316dd92e1b5e5fc20`, protocol 9, schema 2.
- **Live checks:** WSS sync, movement, reconnect and invite refusals PASS; restart persistence PASS; 181 previous item ids retained; markers i206/i207 removed.
- **Service:** active, 0 automatic restarts, backup timer enabled; r12b retained with a verified backup.
- **Not done:** physical touch, audio, Photos and four-child performance.

## r14: Wardrobe pictures — 2026-10-08

`ipad-r14`: manifest `6c6ebf20829aa8f703894f1d13b3bca2399a89710ae99781dcff12491e3fbcc6`, archive `a55054885e13d818f1b2890f96132c1d36a9fc409bdf0659b34444d3ed5034c5`, 1506 files. Based on the released r13b; only `game/scripts/ui/wear_thumbs.gd` (added), `hud.gd`, `run_tests.gd`, `wear_tour.gd` and `docs/wearables.md` differ.

- **Design:** on-demand pictures for the visible rows plus one row ahead.
  - Bounded: an LRU cache of 120 and one 128 px viewport, freed after 2 s idle.
  - Lazy: created on the first Wardrobe open; nothing at startup.
  - A wanted list replaced on every scroll, resize and tab change; failures are not retried.
  - The open card is rebuilt on a language change.
- **Thresholds (wear_tour):**
  - startup: no picture maker and no wearable model loaded beyond the saved look;
  - cold: visible pictures within 3.0 s, each the item's own and all distinct;
  - warm: within 0.25 s with 0 renders;
  - fast tab changes and real wheel scrolling: no stale queue, renders bounded by the tab;
  - memory: cache at most 120, viewports at most 1, then 0 after closing.
- **EC2 results (headless Linux, stub pictures; timings are not real render costs):**
  - units 20812/0, with only the bad-JSON line;
  - parse 67; `check.py` PASS;
  - `wear_tour` 196 PASS at Mac geometry;
  - `net_test.py --wear` PASS; `play2_tour` 66, `play3_tour` 72, `furn_tour` 69 PASS; 0 error lines.
- **Found and fixed:** building the card had requested pictures for the top rows before the scroll position was restored.
- **Software-GL sanity check (Xvfb; not acceptance):** 9 sample pictures in 18 frames, inspected: right item, centred, distinct.
- **Not tested:** the Mac rendered run (requested); devices; shipping (not authorized).

### r14 Mac result — not accepted; recorded as it happened (2026-10-08)

**Evidence:** `ipad-r14/mac-evidence.tar.gz` (SHA-256 `08fe5ac472857410cc045d36c70eafa1962ba9e58f71edca25877edb179341a6`). All 27 hashes verified; extracted to `ipad-r14/mac-evidence-r14/`. All 1506 inputs unchanged.

**Headless stages:** import 11.05 s, parse 67 PASS, units 20812/0.

**Three M1 Pro runs:**
- **First run (fresh user folder):** FAIL. Catalog thumbnails timed out before the window was in the foreground. The Japanese Accessories warm reopen rendered 6 new pictures: it came back at scroll 0 instead of 2550.
- **Retry 1 (reused user folder):** 10 dress and pose failures after a missed maxi tap.
- **Clean run 2:** PASS, 196 checks, 9 originals.

**Author review** (the nine clean-run originals and the first run's 09):
- The pictures match the whole names and are distinct; the cards stay inside the safe area.
- The thin, pale glasses have low contrast on the light tile.
- The partial top row is cut by the scroll view (intended).
- The character views are unchanged from r12b.

**Diagnosis and repair:** see the r14b section and its request. In short: a one-frame scroll restore raced layout (product); the tour read a card being freed by name and tapped before the card settled (test); and cold was measured after the tab's pictures were already made (test).

## r14b: scroll-restore repair, end-to-end timing — 2026-10-08

`ipad-r14b`: manifest `3fa9b8aa8f8b8be4af6ee2163143b8b0d4a301ec479ecfaa6d86f584e10e870f`, archive `2fa47c7b3a02077e9859f0fa15f6c1908ab86a0b79128c416b4524982adb2af5`. Only `hud.gd`, `wear_thumbs.gd`, `wear_tour.gd` and `docs/wearables.md` differ from r14.

- **Repair:** the scroll position is re-applied until stable (bounded), and then the card is marked settled.
- **Tour:** waits for that mark, finds the live card by its build metadata, and times cold (pictures forgotten first, at least 6 made in the window) and warm (0.25 s, the original criterion; same scroll and rows; 0 renders) from the request tap in four phases.
- **EC2 (headless, stub pictures):**
  - warm 0.094 s and 0.149 s;
  - cold 0.199 s, 0.300 s and 0.235 s;
  - `wear_tour` 231 PASS twice in the same user folder;
  - units 20812/0; play2 66, play3 72 PASS.
- **Mac rendered run requested.** A warm total over 0.25 s is to be reported unmet, not re-budgeted.

### r14b Mac acceptance — PASS, final review of the Wardrobe pictures (2026-10-08)

**Evidence:** `ipad-r14b/mac-evidence.tar.gz` (SHA-256 `43a10f55caa7dbcf08030f05d6717b2181acefa4c6eb1cbd8ee10948d791ce49`; upload approved by the user).
- Extracted to `ipad-r14b/mac-evidence-r14b/`: no unsafe paths or links, and all 16 entries of `evidence-sha256.json` match.
- Candidate `3fa9b8aa…e870f`; all 1506 inputs unchanged.

**Mac results** (Apple M1 Pro GPU, gl_compatibility, foreground, fresh user folder): import PASS, parse 67 PASS, units 20812/0 (only the bad-JSON line), `wear_tour` exit 0 with 232 PASS lines, 0 failures, 9 original PNGs. All `DIAG pictures` lines say "rendered".

**End-to-end timing from the request tap (original criteria kept):**

| Case | Request → built | Built → settled | Settled → pictures | Total | New renders |
|---|---|---|---|---|---|
| [de] Dress-up cold | 0.015 | 0.037 | 0.105 | **0.157 s** (≤ 3.0) | 6 |
| [ja] Accessories cold | 0.016 | 0.041 | 0.136 | **0.193 s** (≤ 3.0) | 8 |
| Bottoms after quick taps, cold | 0.020 | 0.039 | 0.106 | **0.165 s** (≤ 3.0) | 7 |
| [de] Dress-up warm | 0.017 | 0.033 | 0.008 | **0.058 s** (≤ 0.25) | 0 |
| [ja] Accessories warm | 0.018 | 0.037 | 0.008 | **0.063 s** (≤ 0.25) | 0 |

Warm reopens came back with the same scroll position and rows. Scrolling to the end of Bottoms showed the new rows' pictures 0.42 s after the scroll; at most 120 pictures were held.

**Author image review (all nine originals in `mac-evidence/wear_tour/` opened). Visual acceptance: PASS** for the in-game Wardrobe pictures.

| Shot | What it shows |
|---|---|
| `wear_iphone_01_top_and_bottom` | The child in the tee and jeans, card closed |
| `wear_iphone_02_seven_slots` | Beret (hair hidden), goggles, bag, socks and shoes |
| `wear_iphone_03_wardrobe_umbrellas` | Each umbrella tile shows its own umbrella above its whole name (Kirschschirm, Kiwischirm, Logo-Schirm, Marienkäferschirm); the worn ladybug umbrella is marked with the check badge |
| `wear_iphone_04_wave_with_umbrella` | The ladybug umbrella upright in the hand over the dress |
| `wear_iphone_05_bench_seated` | Seated skirt, hands over the knees, umbrella put away |
| `wear_iphone_06_swing_seated` | Seated on the swing from behind, umbrella hidden |
| `wear_iphone_07_taken_off` | The remaining items after taking things off |
| `wear_iphone_08_de_wardrobe` | German Dress-up: Küken-Kostüm, Lässig-schickes Kleid, Paradise Planning-Kleid and Paradise Planning-Maxikleid, each with its own picture and whole name |
| `wear_iphone_09_ja_wardrobe` | Japanese Accessories: distinct glasses pictures with whole names; the worn goggles tile is highlighted |

**Remaining issues (confirmed in the pixels; recorded, not changed):**
- The thin white-frame glasses (straw glasses, double-bridge glasses) are pale and low in contrast on the light tile.
- In `04` the pig and the sheep overlap the child; this is the existing animal-proximity behaviour, unrelated to this slice.
- Garments are rigid parts, as recorded in the model acceptance.
- The swing view from behind shows little of the outfit.
- The top row of the list is partly cut by the scroll view (intended).

**Preserved:** the r14 failed attempts (first run and retry 1) and their evidence (`ipad-r14/mac-evidence-r14/`) stay recorded as they happened.

**Not part of this acceptance:** this is a Mac acceptance, not device acceptance. Physical touch, audio, Photos, device timing and four-child performance are not tested. r14b is not released: r13b remains the released build, and no install or deployment was authorized.

## r15: turn ceiling items — 2026-10-08

`ipad-r15`: manifest `c99ea758ac7a4de88ffc5da5a1d119242e2aa862da9656d95fa9c094860a104d`, archive `89adf4b3795687a0f9338f10472f5c863cefcda7dc17bac74b2f37bb3a8e601b`, 1506 files. Based on r14b. Only `town_model.gd`, `play_controller.gd`, `run_tests.gd`, `net_bot.gd`, `furn_tour.gd` and two design docs differ.

- **Behaviour:** ceiling items turn in eight 45-degree steps (the item's existing `rot`) with Turn, while hanging and when editing; Done keeps the turn and Cancel discards it. Wall items keep facing into the room, and floor items are unchanged.
- **Data:** no protocol or schema change. Save loading now keeps a ceiling item's turn; it used to recompute mounted slots with rot 0.
- **Validity:** every ceiling rule is a circle, so results are identical at all 8 turns (unit-checked).
- **EC2 results (headless Linux, Mac geometry; not Mac or device acceptance):**
  - units 20826/0, with only the bad-JSON line; a planted rot-0 fails 7 checks;
  - parse 67; `check.py` and `build_furniture_r2.py --check` PASS;
  - `net_test.py --furniture` PASS: rot 2 hung by A, turned to 5 by B, kept on A's reconnect and seen by a client joining after a restart; logs clean;
  - `furn_tour` 93 PASS (real Turn, Done and Cancel; a wall item unaffected; tools touch-safe); `play_tour` 43, `pets_tour` 92, `wear_tour` 231 PASS; 0 error lines.
- **Not tested:** the Mac rendered run (requested); physical devices (deferred by the user).

### r15 Mac acceptance — PASS (2026-10-09)

**Evidence:** `ipad-r15/mac-evidence.tar.gz` (SHA-256 `1c2e97a60af44d26ebc2b474816cf3369dc58070fa2458f5b23b1439f89a2aac`; upload approved by the user).
- Extracted to `ipad-r15/mac-evidence-r15/`: no unsafe paths or links, and all 15 entries of `evidence-sha256.json` match.
- Candidate `c99ea758…a104d`; all 1506 files unchanged after the Mac tests, with exactly the seven declared changes versus r14b.

**Mac results** (M1 Pro GPU, Godot 4.7.2):
- import PASS (11.97 s); parse 67 PASS (1.81 s);
- units 20826/0 (32.62 s), with only the deliberate bad-JSON line;
- `furn_tour` exit 0: 94 PASS lines, 0 failures, 8 original PNGs (33.8 s); the GPU log has no errors or leaks.

**Author image review (all eight originals in `mac-evidence/furn_tour/` opened):**

| Shot | What it shows |
|---|---|
| `furn_iphone_01_toybox_ceiling` | German toy box, ceiling filter, whole names |
| `furn_iphone_02_room_day` | Chandelier, lantern string and fan as accepted in r13b; insect chart and antler mount on the back wall |
| `furn_iphone_03_ceiling_turned` | The new drapery, left of the insect chart. Its visible part runs front to back, not parallel to the back wall as an unturned drapery would. The placement message ("Platziert! …") still covers its lower part. |
| `furn_iphone_04_ceiling_edit_turn` | Editing the drapery after one more Turn: the drapery at its next turn (still not parallel to the back wall); Drehen, Wegräumen, Schenken, Abbrechen and Fertig fully visible and unobstructed, with the hint above them |
| `furn_iphone_05_headroom_red` | The red pavilion footprint, the reason ("Dort ist unter der Decke nicht genug Platz."), and Hier platzieren disabled |
| `furn_iphone_06_room_evening` | The lamps lit; the drapery unobstructed at its kept turn after the cancelled edit |
| `furn_iphone_07_de_toybox_ceiling` | Whole German names, including both "Hängelampe mit …" lamps |
| `furn_iphone_08_ja_toybox_ceiling` | Whole Japanese names |

**Judgment on 03 (the overlaid quarter turn):** no supplemental capture is required.
- The quarter turn is substantiated by three sources: the uncovered part of the drapery in 03 already runs front to back; the tour's numeric check that the hung drapery is drawn turned a quarter passed on the Mac; and 04 and 06 show the same drapery unobstructed at its later turn.
- The overlap is a tour-evidence flaw: unlike the room-day shot, the turn shot does not wait for the placement message to fade first. No placement controls were on screen at that moment, so this is not a repeat of the r13 message-over-controls defect.
- Recorded as a follow-up for the next tour revision; the frozen r15 inputs are not changed.

**Visual acceptance: PASS** for turning ceiling items (placement, edit and Done, edit and Cancel, wall items unaffected, controls visible).

**Remaining limits (recorded):**
- the lantern string overlaps the antler mount from this camera;
- the fan, mirror ball and screens are static;
- r15 is not released (r13b remains the released build);
- physical devices are deferred by the user.

## r16: wall clearance, scrapbook kept on the device, tour timing — 2026-10-09 (EC2 only; Mac pending)

`ipad-r16`: manifest `b480736e70e910dc86aa2048a48923f8ee65127be904958b25ec4fdcb81baf16`, archive `3865c50c3e59d07178751004e4675481a8b690f15f081db04b85bfb9806dfc58`, 1508 files, based on r15. Two files are added (`photo_store.gd`, `docs/photos.md`) and 14 changed; the inventory is in the request. It was prepared while the Mac was off.

- **Implemented, EC2-verified:**
  - wall clearance: box-based, both orders, moves, table-top effective height, unchanged state on refusal, older overlaps load untouched;
  - local scrapbook persistence: own folder only, local index of bare names, temporary-file-then-rename writes, missing or damaged tolerated, legacy adoption, no network;
  - tour fade wait plus the new rendered cases.
- **EC2 results:**
  - units 20883/0. Error lines: the deliberate bad-JSON save and the deliberately damaged test PNG. Mutations: 14 and 6 failing checks.
  - parse 68; `check.py` PASS;
  - `net_test.py --furniture` PASS (server refuses the lamp in front of the poster; control accepted and saved); `--wear` and main PASS; logs clean;
  - `furn_tour` 113 (twice), `wear_tour` 231, `play_tour` 43, `pets_tour` 92, `play3_tour` 72 PASS; 0 error lines.
- **Recorded failures:**
  - one `--furniture` run failed on a parse error in my own test edit (raw logs kept), fixed before the passing run;
  - `guide_tour` timed out headless (exit 124, 0 checks) because it is rendered-only; it is requested on the Mac.
- **Planned, not implemented:** `design/two-seat-benches.md` and `design/decorative-motion.md`.
- **Not tested:** the Mac rendered runs (requested); devices (deferred); release (r13b stays live).

### r16 Mac result — 2026-10-09: FAIL, repair requested

- Evidence archive `ed6dfdf2d83035eaee773d62c86ef5481ba4331b28a76cc9ae6e8100a37dc9d9`: all 34 indexed hashes match. The author opened all 21 original PNGs (findings in `tools/dual-host-workflow/ipad-r16/MAC_RESULT_REVIEW.md`).
- The import crashed natively on the first attempt (log kept); the unchanged retry passed.
- Passed:
  - parse 68 and units 20883/0;
  - `furn_tour` exit 0 with 10 images;
  - real-camera `guide_tour --tag=pt001` 16/0;
  - a fresh-process scrapbook restore 7/0 (four real photos unchanged).
- **(A)** Wall-gap sign: the code added the 5 cm gap instead of subtracting it.
- **(B)** `guide_tour --tag=iphone` failed 20 assertions after one ignored Back tap. A control rerun of the unchanged driver passed Back but hung at a later screenshot.
- The German guide shot showing English body text is a cascade artefact, not a regression.

## r16b: r16 acceptance repair — 2026-10-09 (EC2 only; Mac pending)

`ipad-r16b`: manifest `4b194842260e7bd2642a4604b97869b9da81cd8f29736c643b0e536e151f318a`, archive `e49e34484c33c2b5dd01463657a10cf164275465086030566ae6e4349738eb13`, 1508 files, based on r16. It changes `town_model.gd`, `run_tests.gd`, `guide_tour.gd` and `design/object-scale-and-surfaces.md`.

- **(A)** A standing item now conflicts when its top is higher than the wall item's bottom minus 5 cm; exactly 5 cm below fits.
  - New boundary checks on real catalog pairs (3.5 cm above, 0.7 mm below, exactly 5 cm below, 5.5 cm below), in both orders.
  - Mutation back to r16's sign: 4 failures.
- **(B)** Taps in `guide_tour` move the pointer to the point before the press and before the lift.
  - A disposable probe (`tools/dual-host-workflow/ipad-r16b/diagnostics/`) reproduced the Mac PASS/FAIL sequence exactly with the old tap plus one stray pointer motion, and passes with the new tap.
  - This classifies the Mac failure as consistent with desktop-cursor interference, reproduced synthetically and not proven as the OS cause. No assertion changed.
- **EC2 results:** units 20903/0; parse 68; `check.py` with fonts PASS; `net_test.py --furniture` PASS; `furn_tour` 113, `play_tour` 43, `pets_tour` 92, `play3_tour` 72 PASS at iPhone geometry.
- **Recorded failures:**
  - a first tour batch run with the wrong geometry flag failed (logs kept);
  - an xvfb guide attempt was stopped during thumbnail generation (log kept).
- **Not tested:** Mac rendering (requested); devices (deferred); release (r13b stays live).

### r16b Mac result — 2026-10-09: NOT ACCEPTED

- **Passed:**
  - all 1508 hashes with exactly the 4 declared changes; import 10.24 s; parse 68; units 20903/0;
  - `guide_tour` iphone 174/0 on a real M1 GPU, 19 originals inspected locally, every German body correct.
- **Furniture attempt 1:** the renderer did not draw at startup. The thumbnail-ready check failed, followed by cascades. Minimize and restore recovered drawing; the run was stopped at 549.79 s and kept.
- **Furniture attempt 2:** exit 0 and `FURN PASS`, but `SCRIPT ERROR` at `furn_tour.gd:234` (a freed card passed to `scrolled_to` after the 0.6 s walk). Only 9 images (no `headroom_red`). FAIL.
- The r16 control retry timed out at 630.04 s at shot 19 (160 PASS, no FAIL); it is not a complete pass.

## r16c: furniture tour lifetime fix — 2026-10-09 (EC2 only; Mac pending)

`ipad-r16c`: manifest `d81d8da7ba112977a123f8ab7f6a73d28ba921fc185b9715fbc9044eb4979bfb`, archive `4920760f23fc57422cded0b7f6807dd51cee099cb6fa6a5322ff6f07ba3ce964`, 1508 files, based on r16b. Only `game/tests/furn_tour.gd` changed.

- **Changes:**
  - the headroom case presses the pavilion through the live, verified `press_card` after the walk;
  - the chandelier lookup is a checked precondition;
  - each case must reach its last line, checked by the runner, so script errors and missing preconditions fail the tour.
  - No assertion was removed.
- **EC2 results:**
  - `furn_tour` 122/0, twice, 0 error lines;
  - a forced freed-card mutation gives the Mac's `SCRIPT ERROR` text and `FURN FAIL` on "the headroom case ran to its end";
  - parse 68.
  - Other evidence is reused from r16b; the bytes are identical outside `furn_tour.gd`.
- **Not tested:** the Mac `furn_tour` with 10 originals (requested); devices (deferred).

### r16c Mac result and author review — 2026-10-09: ACCEPTED

- **Evidence:** archive `81ffb358eedfef4acffb0b724f4d412940774e80d7e614de5b631c5d2babae02` (7860437 bytes, 45 files); all 44 indexed hashes match. Manifest `d81d8da7…9bfb` re-verified unchanged.
- **Mac:**
  - import 10.99 s; parse 68;
  - `furn_tour` 124 PASS, 0 failures, 0 script errors, 8 completed cases, 10 images, 51.79 s.
- **Reused from byte-identical inputs:** units 20903/0, `guide_tour` iphone 174/0 (19 images), photo pt001 16/0, and the fresh-process restore 7/0.
- **Author review of all 29 originals:** PASS.
  - The headroom refusal (05) is present: red footprint, Place off, reason readable.
  - The wall refusal (06) is correct.
  - The evening room (07) has all lamps lit.
  - The restored scrapbook (08) shows the real photo.
  - Every German guide body is German.
- **Pre-existing limits only:**
  - the two-line de overview taglines touch the card edge (as in r5);
  - camera occlusion of the child behind the stairs;
  - the `shot()` wait has no internal timeout.
- **Earlier failed runs (r16, r16b) are kept.** Not released (r13b stays live); devices deferred.

