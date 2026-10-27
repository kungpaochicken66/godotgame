# Handoff — Lantern Lane

> Current release checkpoint (2026-10-27): [release status](docs/release-status.md).
> Installed targets: iPhone/iPad R20, HK R19-connect (protocol 10, schema 2), Apple TV signed r11 (atv-r20-controller; this tree holds r13, whose PCK is byte-identical to the installed one). Siri Remote Menu to the Home screen is accepted on the device. Not verified there: Switch Pro B while armed, B after the timeout, Siri Remote select while armed. R21 remains paused.
> Standard iPhone + iPad + HK publication: [release workflow](docs/release-workflow.md).
> These supersede historical release/install/server claims below; do not infer the shipped version from this older development narrative.

Date: 2026-10-27. Revision 3 was release r1. Workflow: EC2 code → GitHub → local Mac pull and build; heavy renders and device builds run on the Mac (dual-host workflow).

Local workflow addition (2026-10-07): [dual-host modeling](docs/dual-host-modeling.md)
keeps Opus as the remote creative/repair owner and moves heavy validation to the
Mac at explicit candidate boundaries. See [tool validation](docs/dual-host-validation.md).
This local addition does not update the game revision below or certify the newer
EC2 release. No global skill, agent settings or release permissions were changed.

**Git status:**
- Revision 1 is commit `e677e8c` (built and played on a real device by the user).
- Revision 2 is commit `b0f1fb7`.
- Revision 3 (release r1) is commit `57dbe1f`; its game bytes equal the sealed Mac candidate `ipad-r1` (manifest SHA-256 `955dcc5c0f380d96591fb5eb6c95e9551b67d1629b0b4d53ce4db9464565a03f`).
- The A-H goal is commit `4fe1552`.
- The r16c checkpoint is commit `32c4830`. It was local only until 2026-10-25.
- **Production integration (this commit, authorized 2026-10-25):**
  - the accepted r17-r20 work;
  - the Apple TV controller lane, from the frozen candidate `atv-r20-controller` r13 (manifest `f4c33b423791bafe11f90c45c8934855584a9576f87847e6349d13b53bdeeff1`; `game/`, `tv/` and `scripts/` byte-identical to it);
  - the Mac coordinator branch `codex/mac-release-coordination` (merged).

## Status (2026-10-27)

**Released on iPhone and iPad:** r20-motion (manifest `3c83a810a435e8e24c8dae3c534e91d8ba797fa30fa9001f532ee5457fca0fbf`). It was signed, installed and launched on both on 2026-10-25, with content PCK SHA-256 `0d91c554a70ad74dd9b24cd6b3a2b80ad6bdcb3d75fd37b063aca7ae7b6d9cf7`.

**HK server:** r19-connect, protocol 10, schema 2, unchanged.

**Apple TV:** installed on the user's Apple TV 4K (3rd generation), on an experimental 4.8.0-dev tvOS engine built on the Mac, with the Menu patch [tv/engine/0001-tvos-menu-presses-to-uikit.patch](tv/engine/README.md). See [design/tv-controller.md](design/tv-controller.md) and [docs/tv-validation.md](docs/tv-validation.md).
- **Installed:** the lane's r11 device build (manifest `faf82b338940de188742d34bee0e020800d9744541ec8433d4ec78fc5de31b8a`; content PCK SHA-256 `f6f27c79984a32a78f67cdc19cc6d47483c2e9905e6a95915bb32ec442e008e0`; **app bundle** 135005632 bytes). r13 (this tree) differs only by comment lines in `tv_remote.gd`, with the same line count. The Mac confirmed that its controlled PCK is byte-identical to the installed r11 PCK (all 1515 entries), so no reinstall was needed.
  - The earlier r5 build's **app bundle** was 134975620 bytes. Some earlier notes called that the "PCK" size; it is the app bundle.
- **Device results (r11):** tour main 218/0, reopen 6/0, 10 screenshots reviewed.
- **Siri Remote, user-confirmed:**
  - Menu goes back one step; at the title, Menu then Menu returns to the Apple TV Home screen;
  - while armed, Switch Pro A does not go Home;
  - not armed, B does nothing.
- **Not verified:** B while armed (may go Home: UIKit reports a controller's B as Menu), B after the timeout, Siri Remote select while armed.
- **Earlier, user-confirmed:** the Switch Pro controls and the real TV join to the HK town.
- **Not exercised:** the two-controller fallback path.
- **Durable saves:** the native UserDefaults store (r4 inputs, unchanged) passed 14/0 and 8/0 on the device.

**R21 (photo wall, protocol 11, schema 3): paused and not accepted.** It is not in this tree. Its work is preserved on the local branch `r21-photo-wall-paused` (commit `3bfc49f`).

## Candidate r20-motion: ACCEPTED (scoped) — decorative motion, first batch (uncommitted, not released, 2026-10-14)

READY_FOR_LOCAL_VALIDATION: manifest `3c83a810a435e8e24c8dae3c534e91d8ba797fa30fa9001f532ee5457fca0fbf` (1530 files), archive `314d20aa…2870`, based on the released r19-connect. Protocol 10 and schema 2 are unchanged.

**What it adds:**
- `ceiling_fan_light` blades turn;
- `bird_mobile` and `red_paper_lantern` sway;
- `candle_ring_chandelier` and `bamboo_floor_lantern` glow gently at evening;
- a local, persistent **Reduce motion** setting (six languages).

`circulator_fan` has no blades in its model and needs Modeling.

**EC2 results:**
- units 21476/0; `test_all.sh --quick` PASS; parse 74;
- network: main, activities, connect, furniture, visits PASS;
- headless tours: motion 48, furn 122, bench 40, visit 37, play 43 PASS;
- mutations caught (drift; no still pose).

**Mac (2026-10-14):** all 1530 inputs unchanged; import 9.24 s; parse 74; units 21476/0. Real-GPU `motion_tour` 57/0, 4 cases, 7 originals.
- Pixel change while moving: fan 4.60, mobile 0.86, lantern 0.59. After Reduce motion: 0.00 for all five.
- Motion pass 63.7 µs per frame for 17 decorations; frame 8.87 ms moving vs 8.71 ms reduced (desktop only).
- Evidence `8b8ac67d…d23b`. **The author reviewed all 7 originals: accepted (scoped)**, in `ipad-r20-motion/MAC_RESULT_REVIEW.md`.

### Earlier status (kept for history)

Release states in this block and in the candidate sections below are as of their dates. **Everything accepted from r14b through r18b shipped with r19-connect on 2026-10-11.**

**Released (coordinator-reported; the evidence is coordinator-local and was not read here):** r13b, manifest `f33dc3826431c2de52ce5e234d67f0655857159f47a74221d3fca6cd80a54ec9`. (superseded by r19-connect on 2026-10-11)
- Installed and launched on the iPhone and the iPad (the same signed universal app) and deployed to the existing HK server. Public pack SHA-256 `ebb723ee5604cea176ff6c54bd605a64315514edfe1b537316dd92e1b5e5fc20`, protocol 9, schema 2.
- Live WSS sync, movement, reconnect and invite refusals PASS; service restart persistence PASS; all 181 previous item ids retained; test markers i206/i207 removed.
- Service active, 0 automatic restarts, backup timer enabled; r12b kept with a verified backup.

**Accepted, not released at the time (2026-10-09): r17** (shipped with r19-connect on 2026-10-11), manifest `0fdf382e4c7ead09b85f40dba685fe2551c2fd0ae16047ea29cc223524f6a0ed` (1517 files). Mac and author original-image accepted 2026-10-09 (`tools/dual-host-workflow/ipad-r17/MAC_RESULT_REVIEW.md`).
- It contains everything in the accepted **r16c** (`d81d8da7…9bfb`, committed locally as `32c4830`: r14b Wardrobe pictures, r15 turning ceiling items, r16c wall clearance and the scrapbook kept on the device), plus r17 two-seat benches.
- Protocol 9 and schema 2 are unchanged.
- The wall-clearance and seat rules run on the authority, so a release must update the app and the HK server together.
- **Physical-device acceptance is deferred by the user** and does not block the accepted state.
- r17's changes are **uncommitted**: `main` holds r16c. The working tree has moved on to the r18 candidate (see below).

**Git:**
- The accepted r16c (r4 through r16c) is committed locally on `main` as the authorized checkpoint (parent `4fe1552`). **It has not been pushed**; a push needs a separate request.
- The external reference zip `Lantern_Lane_Playability_8-12_EN.zip` stays untracked by design.
- Frozen candidates live under the git-ignored `tools/dual-host-workflow/ipad-*`.

**INCIDENT 2026-10-11 Asia/Shanghai: the shipped apps are stuck at Connecting.** The repair candidate **r19-connect** is **Mac-validated and accepted (scoped)**; review in `tools/dual-host-workflow/ipad-r19-connect/MAC_RESULT_REVIEW.md`.
- Mac results: units 21348/0; `--connect`, main and `--invites` PASS. The private 364-item town joined and reconnected with complete content (36 and 35 ms).
- Evidence `08ff0380…5764`: 37 indexed hashes OK.
- The user authorized releasing it to iPhone, iPad and HK; **the Mac released it on 2026-10-11** (see the latest release above). EC2 performed no publication.
- manifest `c2faf8e3c147eddae5c02e9eca208c183f62c9223a0d96eb3a0251d95eb55553` (1524 files), archive `6c8621f0…224b`;
- request: `tools/dual-host-workflow/ipad-r19-connect/LOCAL_VALIDATION_REQUEST.md`.
- **Cause:** the 364-item town's welcome (75.6 KB) exceeded Godot's default 64 KiB WebSocket buffers on both ends.
- **Fix:** 4 MiB buffers on every peer; a clear refusal above 3 MiB (no truncation); a client that loses the connection before the town, or waits 20 s for it, ends in `failed`, never Connecting.
- Based on the accepted r18b. Protocol 10 (unchanged from r18b); schema 2.
- The confirmed targets are iPhone, iPad and HK, released together. The Mac packages, installs and deploys (user-authorized); EC2 does none of it. No commit or push.
- Decorative motion (r19 draft) is deferred until after this incident.

**Development order authorized by the user:**
1. Two-seat benches: **r17, accepted**.
2. Animals visiting houses: **r18 Mac FAIL** (the visit tour's invite press never fired; a test-input defect). Repaired as **r18b: ACCEPTED under controlled input** (Mac clean2 38/0 and author review of all 13 originals, 2026-10-10; review in `tools/dual-host-workflow/ipad-r18b/MAC_RESULT_REVIEW.md`). r18b's first Mac attempt FAILed 9 checks after an unexpected Sound and music dialog from input outside the tour (cause unproven); it is kept on record.
   - manifest `958ee9e4a1a8455fb1e261eda0e75ff95883eb70c972299ebb81bddad834d227` (1523 files), archive `4d647746…4943`;
   - request: `tools/dual-host-workflow/ipad-r18b/LOCAL_VALIDATION_REQUEST.md`; review: `ipad-r18/MAC_RESULT_REVIEW.md`.
   - **Protocol 10**: a future release must update the apps and HK together.
3. Decorative motion: next (authorized), not started.

Publication, commit and push are not authorized for this work.

**Working tree:** it now holds r19-connect (it equals that manifest). The accepted r17 stays frozen in `ipad-r17` and still verifies. `main` holds r16c.

**Next step (recommended):**
1. Git checkpoint of r16c: done locally, not pushed.
2. A release plan for r16c, covering the app and the HK server together.
3. A release, only on the user's authorization.
4. r17 two-seat benches: accepted (Mac and author), not committed or released.
5. r18b animals visiting houses: accepted under controlled input (Mac and author), not committed or released. **Protocol 10**: a release must update the apps and HK together. Next: decorative motion (authorized, not started).

**Reference backlog (639 Nookipedia references; lab `progress/backlog_inventory.csv`; game state verified here):**

| state | furniture | clothing | total |
|---|---|---|---|
| released in the installed game | 186 (144 release r1 + 42 r13b) | 434 (r12b) | 620 |
| model complete, not in the game | 0 | 0 | 0 |
| blocked on purpose (third-party IP, never unlocked) | 3 | 16 | 19 |
| unattempted | 0 | 0 | 0 |

The lab's generated `progress/BACKLOG.md` still shows the HEAD `4fe1552` view: 476 "model_complete" and "no clothing is game-usable". It is Modeling-owned and was not edited here. GameCode release receipts are in `tools/nookipedia-model-production/INTEGRATION_QUEUE.md`.

In the game:
- 259 catalog kinds, of which 216 use frozen models (10 pilot, 130 release r1, 13 pet room, 21 kitchen and game room, 42 r2);
- 434 wearables.

**Remaining blockers:**
- **Model blockers:** none open. The 19 IP-blocked references stay excluded by design. Known model limits are recorded with the accepted batches (rigid garments, sleeve steps, simplified seated fronts) and are optional polish, not blockers.
- **Functional gaps (Game Code)**, kept separate from the reference inventory (620 released, 19 IP-blocked). Current as of 2026-10-14 (everything marked r14b-r18b below shipped with r19-connect on 2026-10-11):
  1. Ceiling items could not be turned: solved in **r15**; released with r19-connect.
  2. Decorations are static: first batch in candidate **r20-motion** (ceiling fan blades, mobile and lantern sway, two lamps glow; Reduce motion). The mirror ball and screens are not in this batch, and the standing `circulator_fan` has no blades in its model, which needs Modeling ([design/decorative-motion.md](design/decorative-motion.md)).
  3. Wall items could overlap tall standing furniture against the wall: solved in **r16c**; released with r19-connect.
  4. Footprints are circles.
  5. Modeled two-seat benches seat one child: solved in **r17**; released with r19-connect ( [design/two-seat-benches.md](design/two-seat-benches.md)).
  6. Animals do not enter houses: solved in **r18b**; released with r19-connect ( [design/animal-visits.md](design/animal-visits.md)).
  7. The scrapbook kept only this session's photos: solved in **r16c**; released with r19-connect. Photos cannot yet be deleted in the game.
  8. The Wardrobe has no pictures in the released r13b: solved in **r14b**; released with r19-connect. Its pale white-frame glasses pictures are faint.

  None blocks play.

**Remaining limits (recorded, not blocking):**
- The two-line German overview taglines touch their card edge (also in r5).
- The camera can hide the child behind the stairs.
- The lantern string overlaps the antler mount from one camera.
- `guide_tour.shot()` has no internal timeout.
- The Mac window sometimes does not draw at startup (minimize and restore recovers it).

**User-only device checks (cannot be done from EC2 or the Mac):**
- Real finger touch on iPhone and iPad: the Wardrobe (tabs, tiles, Take it off), placing wall and ceiling items, the headroom refusal, sitting, swings and seesaws while dressed.
- Audio on device: music, effects, muting.
- A real save to Photos (add-only permission prompt and the saved picture).
- Performance with four children in full outfits in one room with several evening lamps.
- Two-device play over the real HK server with real invites.

## Candidate r18b: ACCEPTED under controlled input — animals visit houses (not released at the time, 2026-10-10; shipped with r19-connect on 2026-10-11)

Attempt 1 on the Mac: FAIL, 9 checks, after an unexpected Sound and music dialog (cause unproven; kept). Attempt clean2, same inputs, no window operations: 38/0, 8 originals. The author reviewed all 13 originals: `tools/dual-host-workflow/ipad-r18b/MAC_RESULT_REVIEW.md`.


**r18 Mac result: FAIL.**
- Import, parse 71 and units 21332/0 passed.
- `visit_tour` failed 13 checks: the press on Come home with me never fired, and the card stayed open over shots 01-04.
- A probe with one stray pointer motion between the press and the lift reproduces the Mac sequence line for line. The inherited tap sent no pointer motion; the finger-like tap passes.

**r18b** changes only `visit_tour.gd` and the design note; product bytes are identical. It is READY_FOR_LOCAL_VALIDATION (`958ee9e4…d227`).

## Candidate r18: animals visit houses (uncommitted, 2026-10-10; Mac FAIL, see r18b)

READY_FOR_LOCAL_VALIDATION: `ipad-r18`, manifest `caaea4b8…d27e`. The changed paths, commands and acceptance checks are in its request.

**What it adds:**
- Pip, Bramble, Wooly or Biscuit can **Come home with me** (Tumble is too big for the door);
- the visitor follows through the door, rooms and stairs, is drawn beside its child on every device in that room, and answers emotes;
- **Say goodbye**, or its child leaving or disconnecting, puts it at the house's front door outdoors.

**Rules and wire:**
- one visitor per child; no invitations during the party; busy animals refuse;
- protocol 10 (`animal_visit`, `Animals.ev_guests`); the animal state is unchanged; nothing is saved.

**EC2 results:**
- units 21332/0; parse 71; `check.py` PASS (11 new strings in six languages; fonts rebuilt);
- `net_test.py --visits` PASS (32 checks: same room, stairs, late joiner, disconnect inside, restart);
- regression: main, `--play`, `--seats`, `--furniture` PASS. `--activities` failed once on a pre-existing seeker race in unchanged code, then PASSed; both logs are kept.
- `visit_tour` headless 37/0, twice;
- mutations: 4, 8, and outdoor hiding caught by the net test.

**Mac:** import, parse, units, and `visit_tour` rendered (8 originals) are requested. Physical devices are deferred.

## Candidate r17: Mac acceptance PASS — two-seat benches (not released at the time, 2026-10-09; shipped with r19-connect on 2026-10-11)

**ACCEPTED (Mac + author original-image review)**, recorded in `tools/dual-host-workflow/ipad-r17/MAC_RESULT_REVIEW.md`.
- Mac: import 9.90 s, parse 69, units 21161/0, `bench_tour` 41 PASS, 0 failures, 0 errors, 4 completed cases.
- Evidence `a08e0f97…2e68`: 12 indexed hashes OK. The author opened all 5 originals and found no defect.
- Recorded limits: rigid garments; a standing child can hide a seated one from the camera; a leftover message in shot 03 (a tour timing note).
- Devices deferred; not released.

Sealed as `ipad-r17`, manifest `0fdf382e…a0ed`. The changed paths, commands and acceptance checks are in its request.

**What it adds:**
- the bamboo bench seats two (a catalog override outside the generated block);
- seats are given first-free by the authority, and a re-tap keeps your seat;
- side-by-side seats are 0.80 m apart: the frozen bamboo markers are spread game-side from 0.54 m, and the GLB is unchanged (Modeling note);
- a full bench shows a message;
- Get up puts you in front of your own seat;
- a friend's seated child no longer drifts off the seat;
- positions are relayed only to connected peers.

Protocol, schema and UI text are unchanged.

**EC2 results:**
- units 21161/0; parse 69; `check.py` PASS;
- `net_test.py --seats` (3 clients plus a restart), main, `--play`, `--activities`, `--furniture`: all PASS;
- `bench_tour` headless 40/0;
- mutations: 10, 11, 1 and 5 failing checks.

**Mac:** done; see the acceptance above. Physical devices are deferred.

## Candidate r16c: Mac acceptance PASS — wall clearance, scrapbook kept on the device (committed locally as the r16c checkpoint; not released at the time, 2026-10-09; shipped with r19-connect on 2026-10-11)

**ACCEPTED (Mac + author visual review)**, recorded in `tools/dual-host-workflow/ipad-r16c/MAC_RESULT_REVIEW.md`.
- Mac results: furniture tour 124/0 with 0 script errors, 8 completed cases and 10 images. Reused from byte-identical inputs: units 20903/0, guide 174/0 with 19 images, photo 16/0 and fresh-process restore 7/0.
- Evidence archive `81ffb358…ae02`: 44 indexed hashes OK. The author opened all 29 originals; no real defect.
- r16c was accepted, not released at the time (r13b was then the released build; r16c shipped with r19-connect on 2026-10-11). Physical devices are deferred.

### r16c candidate details (Mac result above)

**READY_FOR_LOCAL_VALIDATION:** `ipad-r16c`
- manifest `d81d8da7ba112977a123f8ab7f6a73d28ba921fc185b9715fbc9044eb4979bfb`, 1508 files;
- archive `4920760f23fc57422cded0b7f6807dd51cee099cb6fa6a5322ff6f07ba3ce964`;
- request: `tools/dual-host-workflow/ipad-r16c/LOCAL_VALIDATION_REQUEST.md`.

It is based on r16b; only `game/tests/furn_tour.gd` changed.

**r16b Mac result: NOT ACCEPTED.**
- Passed: hashes and the 4 changes, import, parse 68, units 20903/0, and `guide_tour` iphone 174/0 with every German body correct. Finding (B) is closed.
- Furniture attempt 1: the renderer did not draw at startup (environmental; minimize and restore recovers it; kept).
- Furniture attempt 2 exited 0 but logged a `SCRIPT ERROR` in `_headroom`: a toy-box card freed while the child walked was passed to `scrolled_to`. The case aborted silently, and only 9 images were made.
- The r16 control retry timed out at 630.04 s at shot 19 (160 PASS); it is not a complete pass.

**r16c repair (test driver only):**
- the pavilion card is pressed through the live, verified `press_card` after the walk;
- the chandelier lookup is a checked precondition;
- every case must reach its last line ("the … case ran to its end"), so a script error or a missing precondition fails the tour.

**EC2 results:**
- `furn_tour` 122/0, twice;
- the forced freed-card mutation reproduces the Mac `SCRIPT ERROR` and now ends in FAIL;
- parse 68.

**Mac request:** `furn_tour` only, with 10 originals.

## Candidate r16b: Mac result NOT ACCEPTED (furniture tour script error), repaired in r16c — r16 acceptance repair (uncommitted, 2026-10-09)

**READY_FOR_LOCAL_VALIDATION:** `ipad-r16b`
- manifest `4b194842260e7bd2642a4604b97869b9da81cd8f29736c643b0e536e151f318a`, 1508 files;
- archive `e49e34484c33c2b5dd01463657a10cf164275465086030566ae6e4349738eb13`;
- request: `tools/dual-host-workflow/ipad-r16b/LOCAL_VALIDATION_REQUEST.md`.

It is based on r16. Four files changed; protocol and schema are unchanged.

**r16 Mac result: FAIL, repair requested.** The review is in `tools/dual-host-workflow/ipad-r16/MAC_RESULT_REVIEW.md`.
- Evidence: archive `ed6dfdf2…c9d9`, 34 indexed hashes OK, 21 original PNGs opened by the author.
- The first import crashed natively in font import (log kept); the unchanged retry passed.
- Passed: parse 68, units 20883/0, `furn_tour` 115 PASS lines with 10 images, the real-camera `guide_tour --tag=pt001` 16/0, and a fresh-process scrapbook restore 7/0 with four real photos.
- **(A)** Wall clearance used the wall item's bottom **plus** 5 cm, allowing up to 5 cm of real overlap. Fixed to bottom **minus** 5 cm. `test_wall_clearance_heights` uses real catalog pairs below, at and above the boundary, in both placement orders; the r16-sign mutation fails 4 checks.
- **(B)** `guide_tour --tag=iphone` failed 20 assertions: the en Back tap was ignored, and everything after it cascaded.
  - Neither the live UI nor a stale lookup was at fault: the guide code and driver are identical to the passing r5 run.
  - EC2 reproduction: a pointer motion away from the button between the driver's press and release gives a PASS/FAIL sequence identical to the Mac log. A Mac control rerun of the unchanged driver passed Back, so the failure is intermittent.
  - Classified as consistent with desktop-cursor interference; not proven as the OS cause.
  - Repair: finger-like taps in the driver (pointer moved to the point before the press and before the lift). No assertion changed.
- The English body text in the German guide shot is a cascade artefact (the en-built page stayed open). It is not a missing translation and not a regression.
- r16 visuals look good but are **not accepted**, because r16 failed.

**EC2 (headless):**
- units 20903/0;
- parse 68;
- `check.py` with fonts PASS;
- `net_test.py --furniture` PASS;
- `furn_tour` 113, `play_tour` 43, `pets_tour` 92, `play3_tour` 72 PASS;
- the guide flow through the diagnosis probe PASS, with and without the injected stray motion.

**Known gap:** `guide_tour.shot()` waits for a drawn frame without a timeout. The r16 Mac control rerun hung at `go_there_stump`. It is recorded, not changed.

## Candidate r16: Mac result FAIL, repaired in r16b — wall clearance, scrapbook kept on the device (uncommitted, 2026-10-09)

**READY_FOR_LOCAL_VALIDATION:** `ipad-r16`
- manifest `b480736e70e910dc86aa2048a48923f8ee65127be904958b25ec4fdcb81baf16`, 1508 files;
- archive `3865c50c3e59d07178751004e4675481a8b690f15f081db04b85bfb9806dfc58`;
- request: `tools/dual-host-workflow/ipad-r16/LOCAL_VALIDATION_REQUEST.md`.

It is based on the Mac-accepted r15. Prepared while the Mac was off; nothing has been run on the Mac.

| Queue item | State |
|---|---|
| 1. Wall clearance (wall items vs tall standing items, box-based, both orders, moves, table tops; older overlaps load untouched and stay correctable) | **Implemented, EC2-verified**; Mac pending |
| 2. Scrapbook photos kept across restarts (game's own folder, local index, safe writes, missing or damaged tolerated, no network or other folders; Photos export unchanged) | **Implemented, EC2-verified** (logic and store path); real camera path Mac pending (`guide_tour`, `furn_tour`) |
| 3. Furniture-tour fade wait before the turned shot, plus rendered wall-clearance and scrapbook-restart cases | **Implemented, EC2 headless PASS**; Mac rendering pending |
| 4. Two-seat modeled benches | **Planned**: [design/two-seat-benches.md](design/two-seat-benches.md) (only `bamboo_bench` has `Seat1`; add the marker and a catalog override; no protocol change) |
| 5. Decorative motion | **Planned**: [design/decorative-motion.md](design/decorative-motion.md) (mirror ball can spin as a whole and screens can glow, animation only; the fan needs a Modeling blade split; no UVs for screen pictures) |

**EC2 results:**
- units 20883/0 (mutations: wall rule off fails 14 checks; photo store forgetting fails 6);
- `net_test.py --furniture`, `--wear` and main PASS;
- `furn_tour` 113 (twice), `wear_tour` 231, `play_tour` 43, `pets_tour` 92, `play3_tour` 72 PASS;
- `guide_tour` is rendered-only and requested on the Mac.

**Blocked:** none. No migration was needed: older overlaps load unchanged.

## Candidate r15: Mac acceptance PASS — turn ceiling items (not released at the time, 2026-10-09; shipped with r19-connect on 2026-10-11)

**Closed:** Mac acceptance of `ipad-r15`.
- Evidence `ipad-r15/mac-evidence.tar.gz` `1c2e97a6…a2aac`, 15 hashes verified.
- Units 20826/0; `furn_tour` 94 PASS, 0 failures, 8 originals.
- Author review of all 8: PASS. The quarter turn in 03 is partly under the placement message, but is substantiated by its uncovered part, the numeric drawn-turn check, and the unobstructed 04 and 06. No supplemental capture needed.
- Follow-up for the tour: wait for messages to fade before the turn shot.
- Limits: the lantern string overlaps the antler mount from this camera; static moving parts.

Details: [docs/validation.md](docs/validation.md#r15-mac-acceptance--pass-2026-10-09).

Released: still r13b. Physical devices are deferred by the user.

Candidate record:
- manifest `c99ea758ac7a4de88ffc5da5a1d119242e2aa862da9656d95fa9c094860a104d`, 1506 files;
- archive `89adf4b3795687a0f9338f10472f5c863cefcda7dc17bac74b2f37bb3a8e601b`;
- request: `tools/dual-host-workflow/ipad-r15/LOCAL_VALIDATION_REQUEST.md`.

It is based on the Mac-accepted r14b; seven files differ (`town_model.gd`, `play_controller.gd`, three test files, two design docs).

**What it does:**
- Ceiling items turn in 45-degree steps with Turn, while hanging and when editing; Done keeps the turn and Cancel discards it.
- Wall items still face into the room; floor items are unchanged.
- No protocol or schema change: it reuses `rot`, which is saved, synchronized and kept across reconnect and late join.
- It fixed a load path that would have reset turned ceiling items to 0.

**EC2:**
- units 20826/0 (planted failure: 7 checks fail);
- `net_test.py --furniture` PASS (turn replicated, reconnect, late join after restart);
- `furn_tour` 93 (placement, edit with Done, edit with Cancel, wall unaffected, touch-safe tools); `play_tour` 43, `pets_tour` 92, `wear_tour` 231; 0 error lines.

**Not done here:** the Mac rendered run (requested). Physical devices are deferred by the user. Nothing was released.

## Candidate r14b: Mac acceptance PASS — Wardrobe pictures (not released at the time, 2026-10-08; shipped with r19-connect on 2026-10-11)

**Closed:** Mac acceptance of `ipad-r14b`.
- Evidence `ipad-r14b/mac-evidence.tar.gz` `43a10f55…91ce49`, 16 hashes verified.
- Real M1 Pro run: 232 PASS lines, 0 failures, 9 originals.
- End to end from the tap: cold 0.157 s, 0.193 s and 0.165 s (6, 8 and 7 new renders); warm 0.058 s and 0.063 s against the original 0.25 s, with 0 renders and the same rows.
- Author review of all nine originals: visual acceptance PASS.
- Limits: the white-frame glasses are faint; existing animal overlap and rigid garments.

Details: [docs/validation.md](docs/validation.md#r14b-mac-acceptance--pass-final-review-of-the-wardrobe-pictures-2026-10-08).

**Released:** still r13b. Shipping r14b (app update; protocol unchanged) and device checks are not authorized here.

Candidate record:
- manifest `3fa9b8aa8f8b8be4af6ee2163143b8b0d4a301ec479ecfaa6d86f584e10e870f`;
- archive `2fa47c7b3a02077e9859f0fa15f6c1908ab86a0b79128c416b4524982adb2af5`;
- request with the diagnosis: `tools/dual-host-workflow/ipad-r14b/LOCAL_VALIDATION_REQUEST.md`.

**The r14 Mac run (evidence `08fe5ac4…9341a6`, kept):**
- clean run 2 PASS;
- first run FAIL: the warm reopen came back at scroll 0, a one-frame scroll restore racing layout;
- retry 1 FAIL: the same restore moved the list under a tap, and the tour read the dying card by name;
- cold timing was not truly cold.

**r14b:**
- the scroll restore is re-applied until stable (bounded), and the card is marked settled;
- the tour waits for it, finds the live card, and times cold and warm end to end from the request tap with phases;
- the original 0.25 s warm criterion is kept;
- warm requires the same rows and 0 renders.

**EC2:** warm 0.094 s and 0.149 s; cold 0.199-0.300 s (stub pictures); `wear_tour` 231 PASS twice in the same user folder; units 20812/0.

**Mac result pending:** a warm total over 0.25 s is to be reported unmet.

## Candidate r14: Wardrobe pictures (uncommitted, 2026-10-08)

**READY_FOR_LOCAL_VALIDATION:** `ipad-r14`
- manifest `6c6ebf20829aa8f703894f1d13b3bca2399a89710ae99781dcff12491e3fbcc6`, 1506 files;
- archive `a55054885e13d818f1b2890f96132c1d36a9fc409bdf0659b34444d3ed5034c5`;
- request: `tools/dual-host-workflow/ipad-r14/LOCAL_VALIDATION_REQUEST.md`.

It is based on the released r13b. Only `wear_thumbs.gd` (added), `hud.gd`, `run_tests.gd`, `wear_tour.gd` and `docs/wearables.md` differ.

**What it does:**
- Wardrobe tiles show each item's picture above its whole name, rendered on demand from the frozen GLBs for the rows on screen.
- Memory is bounded: 120 pictures and one viewport, freed when idle.
- Nothing happens at startup.
- Thresholds: 3.0 s cold, 0.25 s warm with 0 renders.

**EC2 (headless):** units 20812/0; `wear_tour` 196, `play2` 66, `play3` 72, `furn` 69; `net_test.py --wear` PASS; 0 error lines. Software-GL sample renders were inspected.

**Not done here:**
- the Mac rendered run (requested);
- shipping and device checks (not authorized).

## Released r13b: Mac acceptance PASS, then released — 42 wall and ceiling models (uncommitted, 2026-10-08)

**Closed:** Mac acceptance of `ipad-r13b`.
- Evidence `ipad-r13b/mac-evidence.tar.gz` `9f90d807…bc4943`, all hashes verified.
- Units 20796/0; the rendered `furn_tour` PASS on foreground retry 2 (69 checks). The two stalled attempts and the r13 control are kept; their cause is unknown.
- r13 network evidence reused.
- Author review of all 6 originals: visual acceptance PASS. Names are whole and distinct, messages stay clear of the tools, the wall mounts hang on the wall, and the lamps are lit.
- Limits: small 13 px German names, a lone kana on some Japanese lines, the antler partly behind the lantern string from this camera, static fan.

Details: [docs/validation.md](docs/validation.md#r13b-mac-acceptance--pass-final-visual-acceptance-of-the-wall-and-ceiling-models-2026-10-08).

**Released afterwards (coordinator-reported):** installed on the iPhone and the iPad and deployed to HK; see the status section at the top.

**Still pending:** device touch, audio, Photos and performance (user-only checks).

Candidate record:
- manifest `f33dc3826431c2de52ce5e234d67f0655857159f47a74221d3fca6cd80a54ec9`, 1505 files;
- archive `33d56a3af8be15bc3ca48c0ca5f948f345e7c1b515d8ddad96be02ee5611896a`;
- request: `tools/dual-host-workflow/ipad-r13b/LOCAL_VALIDATION_REQUEST.md`.

**The r13 Mac run (evidence `50b5347f…dabfa64d`, kept):**
- Automated checks passed: units, the rendered `furn_tour` and `--furniture`.
- Visual review: REPAIR_REQUIRED.
  - Two German cards read "Hängelampe mit..."; words broke mid-word; names were ellipsised.
  - The "Placed!" toast covered the wall items and the placement tools.

**r13b (seven files: `hud.gd`, `ui_kit.gd`, ja/es locales, `run_tests.gd`, `furn_tour.gd`, the r2 design doc):**
- Cards show whole names, broken between words, in up to 3 lines at 13-16 px.
- Names are unique per tab in six languages; three older duplicates were fixed.
- A new placement clears the stale message, and messages never cover the placement tools.
- The new tour fails on r13's HUD exactly as the Mac saw and passes on r13b.
- EC2: units 20796/0; tours furn 69, play 43, pets 92, play3 72, all PASS.

## Candidate r13: 42 wall and ceiling models, headroom rule (uncommitted, 2026-10-08)

**Release context (recorded, not repeated):** r12b (protocol 9, all 434 wearables) is installed and launched on the iPhone and the iPad and deployed to HK; the Mac coordinator recorded:
- WSS sync, movement, reconnect, refusal and restart persistence passed;
- all 181 pre-update town item ids were retained;
- test markers were removed.

Physical touch, audio, Photos and four-child performance still await humans.

**READY_FOR_LOCAL_VALIDATION:** `ipad-r13`
- manifest `f8a92ee5cb1bc1ede90e3033cfbed1c7d718323005755abcfd4bdc8d9fc21db9`, 1505 files;
- archive `991ff366661a1859d0257a75f545b6a1baadc72453eff818124ff1de0ce2a037`;
- request: `tools/dual-host-workflow/ipad-r13/LOCAL_VALIDATION_REQUEST.md`.

**What it adds:** the 42 `model_complete` furniture references (42 unique models: 38 ceiling, 4 wall v2).
- Sources: `b011-furn-r2` (31) and `b012-furn-r3` (the 11 repaired ceiling items), copied byte-for-byte by `scripts/build_furniture_r2.py`. Inventory and hashes: [design/model-release-r2.md](design/model-release-r2.md).
- Placeable indoors through the toy box under the existing wall and ceiling gates, plus a new **headroom** rule enforced by the authority (hanging and standing items may not meet).
- 25 lamps light up in the evening.
- The antler mount is centred by a catalog `model_offset` instead of rewriting its frozen GLB.
- Six languages; no protocol change.

**EC2 (headless, not Mac or device acceptance):** all PASS, with 0 error lines.
- Units 20778/0; `net_test.py --furniture` (two clients, reconnect, restart), `--wear` and main.
- Tours at Mac geometry: furn 56, pets 92, play 43, wear 150.

**Remaining:**
- the Mac rendered `furn_tour` (requested);
- an app + HK update to ship it (protocol unchanged);
- real touch, device performance and human art review.

Limits: ceiling items cannot be turned; the fan, mirror ball and screens are static.

## Candidate r12b: Mac acceptance PASS — wearables in the game (uncommitted, 2026-10-08)

**Closed:** Mac acceptance of the in-game wearables on `ipad-r12b`.
- Evidence `ipad-r12b/mac-evidence.tar.gz`, SHA-256 `c504f38b…ed6299`.
- Units 19554/0 and the rendered `wear_tour` PASS. Every Wardrobe fit holds on 20 frames, including live language switches.
- Network, rig and native evidence reused from r12 (unchanged bytes).
- Author review of all 9 originals: visual acceptance PASS.
- Limitations: a long German word beside the check mark can break mid-word; a Japanese line can start with a small kana; the left-arm wave and swing views are small at the game's closest camera distance.

Details: [docs/validation.md](docs/validation.md#r12b-mac-acceptance--pass-final-visual-acceptance-of-the-in-game-wardrobe-2026-10-08).

**Remaining gates (device; not done here):**
- signed packaging (being prepared separately);
- an authorized, synchronized protocol 9 HK + app update;
- real touch, device performance and a real Photos write.

Candidate record:
- manifest `165bea09c43bc50c5bdefe6546767b853ff0bc15135bc1f9ace7210d37a3601a`, 1416 files;
- archive `071eaebbd0a229167179fd7d9209bd5f1f0062267c2235edf4a450f48272d486`;
- request: `tools/dual-host-workflow/ipad-r12b/LOCAL_VALIDATION_REQUEST.md`.

**The r12 Mac run (evidence `f3100f52…0c00c0a`, kept):**
- Import, parse, units and the targeted `--wear` network check passed.
- The rendered `wear_tour` FAILED: the German Wardrobe after rejoin was 985 px on a 969 px safe height.
- Two character shots were covered by the card, and long names were clipped into identical-looking tiles.

**r12b changes only:** `hud.gd`, `wear_tour.gd`, `run_tests.gd` and `docs/wearables.md`.
- The list refits whenever the card's layout changes.
- Tiles show whole names (wrapped, unique per tab, sorted in the player's language).
- The tour now checks the fit on every frame, including language switches, plus whole names, and its character shots have the card closed.

The new tour fails on r12's `hud.gd` just as on the Mac and passes on r12b. EC2: units 19554/0, wear_tour 150, play2 66, play3 72, all PASS. The rig, network, model and native bytes equal r12, so that Mac evidence is reused.

## Candidate r12: wearables in the game, protocol 9 (uncommitted, 2026-10-08)

**READY_FOR_LOCAL_VALIDATION:** `ipad-r12`
- manifest `d74944cc47a11033cbb6c0422093ef28366d2d167979be2f97615349ece8c180`, 1416 files;
- archive `8a0172ea1aedb5e7b1d0696bb60dba7789b89cccb95bc5aa7d1fafb504dbad9f`;
- request and Mac commands: `tools/dual-host-workflow/ipad-r12/LOCAL_VALIDATION_REQUEST.md`.

r11d and its evidence are unchanged.

- **What:** all 434 frozen wearables are in Dress up -> Wardrobe:
  - nine tabs, free, in six languages;
  - kept per device; validated by the authority (`wear`, protocol 9); shared with friends;
  - the per-pose rig contract (seated variants, seated hands, held-item hide/restore and hold envelope) and hides, rebuilt after `kid.setup()`.

  Wear-r2 rev5 reached final acceptance during this work (c018/c019 FROZEN). The 56 held items therefore use those hold records: their GLB bytes are checked equal to c014/c013. Nothing is gated, nothing blocked is unlocked, and nothing in the lab was edited. Report and id lists: [docs/wearables.md](docs/wearables.md).
- **Also fixed:**
  - Reconnect rejoined with the look from the first join; outfits and hats changed in town were lost. It now uses the current look.
  - The Wardrobe card was taller than the iPhone safe area; its list now shrinks.
- **EC2 (headless, not device tests):** all PASS, with 0 error lines.
  - Units 19548/0.
  - `net_test.py --wear`: 41 checks.
  - At Mac geometry: `wear_tour` 130, and the regressions play2 66, play3 72, pets 92, play 43.
- **Gates:** model acceptance (lab), in-game acceptance (Mac run of r12, requested) and device acceptance are separate. Device acceptance means:
  - real touch on iPhone/iPad and performance with four dressed children, NOT TESTED;
  - the Photos write, still unverified.

  A synchronized, authorized HK + app update to protocol 9 is needed (HK and the installed r11d apps are protocol 8).

## Candidate r11d: Mac acceptance PASS (uncommitted, 2026-10-08)

**Closed:** the r11 Mac acceptance is complete on `ipad-r11d` (manifest `457c9faa…8d0c0`, archive `ae37d661…09d2e`, evidence `ipad-r11d/mac-evidence.tar.gz` `ededbde3…e49c3`, reviewed): rendered play3 and play_tour PASS with every tap guarded on screen (all inside the safe area, drift at most 0.6 px); author image review passes; product evidence reused from identical r11b/r11c bytes (units 14528, play2 with the real story strip, music translations, unsigned iOS build with add-only Photos in six languages, network). Details: [docs/validation.md](docs/validation.md#r11d-mac-acceptance--pass-final-guarded-input-result-2026-10-08).

**Release (done by Codex, 2026-10-08 08:18 CST, with explicit owner authorization; recorded here, not repeated):** r11d is installed and launched on both the iPad and the iPhone, and HK runs the matching protocol 8 server. Live WSS, wrong/missing invites, reconnect and restart persistence passed, and all 130 town item ids were retained. **Still unverified:** actual human touch and a real Photos write. Not committed or pushed.

### How r11d came about

- r11c's Mac play3 passed, but its boat tap was aimed off screen (2096, 1437 on 2208 x 1024), so it does not count as tap usability; r11c and its evidence stay unchanged and recorded as such.
- r11d (`ipad-r11d`, manifest `457c9faa…8d0c0`, archive `ae37d661…09d2e`; only three tour files differ from r11c): every world tap and drag must be on screen, in the safe area and not under the HUD, or the check fails and nothing is sent; boat and leaf pile are framed before the real tap; framing peeks end before the next step; play_tour's fetch throw now goes up the screen (its old throw was also off screen); a red ghost is moved by a real drag. EC2 headless at the Mac's geometry (`--window=2208x1024`): play3, play, play2, pets PASS with every aim inside the safe area.
- **READY_FOR_LOCAL_VALIDATION:** one rendered `play3_tour` on the Mac (`ipad-r11d/LOCAL_VALIDATION_REQUEST.md`). Product, unit, story, native and network evidence from r11b/r11c is reused (product bytes identical).

## Candidate r11c: Mac-accepted except boat-tap fidelity (uncommitted, 2026-10-07)

**Still open (outside Mac acceptance):** device install, real touch and a real Photos write on iPhone/iPad (NOT TESTED; the devices were disconnected at the last check), and the synchronized app + HK server update to protocol 8 (HK is r8c, protocol 5). An unsigned Debug iphoneos build/link and a local public server pack loopback start passed on the Mac; neither was installed or uploaded.

### How r11c came about

- Mac on r11b: play2 rendered PASS (real story strip, upright umbrella, translated Japanese bell row, stop icon confirmed); play3 rendered FAIL (Tumble's real tap missed).
- Cause measured on EC2 (play3 at `--max-fps 60`): the driver aimed taps while the camera was still easing after a jump; the target drifted 160 px during the tap. Fixed in the tour harness (`settle_camera()`, drift logging, detailed miss report); no check loosened; product bytes identical to r11b.
- `ipad-r11c`: manifest `81a12c11…eae7a`, archive `959b732d…97db3`. **Mac acceptance PASS** (evidence `ipad-r11c/mac-evidence.tar.gz` `20c828a4…a006c`, reviewed): rendered play3 PASS with tap drift under 0.5 px; author image review of the fountain, boat, invite cards, real story strip and German/Japanese music cards passes. The boat tap was aimed off screen, so boat tap usability was not shown by r11c (resolved in r11d above). The first Mac import crashed in Godot font reimport even single-threaded; retry passed (engine-side, intermittent). Details: [docs/validation.md](docs/validation.md#r11b-mac-acceptance-and-r11c-test-only--2026-10-07). r11b and r11 unchanged. Not committed or pushed; no install or deployment.

## Revision r11b: fixes from the r11 Mac image review (uncommitted, 2026-10-07)

- **r11 Mac evidence reviewed** (`ipad-r11/mac-evidence.tar.gz` `5374b1eb…7af47`, verified, extracted to `ipad-r11/mac-evidence/`): all r11 checks passed on the Mac, including a real 1504 x 464 story strip with the German caption. The images showed five defects: the music box "Bell" row untranslated in every language, a paper boat lap crossing the pond's rim, a fountain shape that could face edge-on, an umbrella swinging sideways in poses, and a Play icon kept while showing Stop. Two shots also had framing problems (fountain behind a tree, boat distant).
- **Fixed in r11b** (`ipad-r11b`, manifest `13330641…23fe1`, archive `ccbadb8a…51baa`, 540 files, 12 differ from r11): all five, plus clearer tour framing and a real preset nickname in a fixture; the string extractor no longer hides "Bell". No network, save, model or native change (protocol 8).
- **Checks (EC2, headless):** units 14528/0 (new checks shown to fail on the old defects); check.py; tours play3 63, play2 57, play 34, pets 74; `--r11` and `--batch2` PASS with clean logs. Details: [docs/validation.md](docs/validation.md#r11-mac-evidence-review-and-r11b-fixes-uncommitted--2026-10-07).
- **READY_FOR_LOCAL_VALIDATION:** bounded Mac request in `tools/dual-host-workflow/ipad-r11b/LOCAL_VALIDATION_REQUEST.md` (two rendered tours and one real story strip). `ipad-r11` and its evidence are unchanged.
- **Still open:** rendered acceptance of r11b; Photos on a real device NOT TESTED; installed apps and HK are r8c (protocol 5). Not committed or pushed.

## Revision r11: the deferred play ideas and batch-2 follow-ups (uncommitted, 2026-10-07)

Scope (user-authorized extension): F09 blueprint cards, F04 paper boats and leaf piles, F03 games for Wooly, Bramble, Pip and Tumble, F10 invitations with Join / Not now and "Please help me edit", plus natural completions of the batch-2 omissions. Decisions, reasons and what is still deferred: [design/playability-8-12.md](design/playability-8-12.md) ("r11" and "Not done and why"). The reference package is **not** claimed complete.

- **Implemented:** invitation cards (one per inviter, Join walks there, Not now closes, 2-minute life) from fetch, animal, trail, music and story cards and the hide-and-seek/party chip; help-edit for a place on display (temporary, never saved, Leave); animal games (Wooly answers emotes, Bramble tends a bed which grows through the authority, Pip splashes at water, Tumble sprays heart/star/round fountains; friends join a running game); paper boats that sail a pond lap; leaf piles with a together-jump; garden umbrella; blueprints (save a picked group on the device, preview with fit rings, move, turn, place piece by piece, undo); clothes style and handheld props (`Body/ArmR/Hand`, docs/kid-rig.md); story caption band (renderer only); cardboard moon, mountains and curtain; Suggest a trail; light track piece; music parts.
- **Fixes found while testing:** an invitation card's expiry timer captured a card that may already be freed (engine error after 2 minutes); an animal stuck near its play spot silently abandoned the game (it now plays right there); Wooly's "hop" answer was reset by the movement code (answers are standing moves now).
- **Network protocol 7 → 8.** Installed apps and the HK server are r8c (protocol 5); r9 (6), r10 (7) and r11 (8) cannot mix with each other. No install or deployment of r9-r11 is authorized.
- **Closeout fix:** a different invitation sent right after another was refused by a per-inviter cooldown (reproduced, fixed, unit and network covered); an `--invites` harness race was replaced by a stricter whole-time check.
- **Checks (EC2, headless only, final code, one suite at a time):** units 14501/0; parse 63; check.py; network main, activities, invites, pets, play, batch2 and r11 (x2) PASS with 0 error lines in every log; tap tours play3 62, play2 57, play 34, pets 74, 0 failures. Details: [docs/validation.md](docs/validation.md#r11-deferred-play-ideas-and-follow-ups-uncommitted--2026-10-07).
- **Frozen candidates:** `ipad-r11` (manifest `f22891d4…e19b1`, 540 files, archive `c75d4230…ddcb8`; Mac-validated, review fixes in r11b above); `ipad-r10`, `ipad-r9`, `ipad-r8`, `r8b`, `r8c`, `photos-native-r8`, `rev2` unchanged. Not committed or pushed.
- **Still open:** rendered, touch and device acceptance of r9, r10 and r11 (Mac); the story caption needs a renderer; Photos on a real device NOT TESTED; no r9/r10 Mac evidence exists (none was uploaded).

## Revision r10: play ideas for ages 8-12, batch 2 (uncommitted, 2026-10-07)

All ten ideas from the reference package now have a playable slice; decisions per idea, scope cuts and what is deferred: [design/playability-8-12.md](design/playability-8-12.md).

- **Batch 2 implemented (F07, F08, F06, F05, F02):** Dress up (four hats and clothes color in town, seen by friends, kept on the device); a placeable music box (4 sounds x 8 steps, Play/Stop, per-device mute, lamps swell gently on notes); trail signs 1-5 with clue emotes, Follow the trail with an arrow, shared trail keepsakes; Story mode (five inspiration cards, four network poses, three pictures, reorder, kept in `user://stories` and Photos where available); toy tracks (six pieces on a 1 m grid, roll the ball, bells, switch, finish, gap arrow, loops).
- **Network protocol 6 → 7.** r8c (installed on both devices and deployed on the HK server, protocol 5) and the frozen r9 (protocol 6) cannot join an r10 server or the reverse; the next synchronized update must move apps and server together. No install or deployment of r9/r10 is authorized.
- **Fixes found while testing** (details in [docs/validation.md](docs/validation.md#r10-play-ideas-batch-2-uncommitted--2026-10-07)): the kid rig's rebuild naming; Biscuit abandoning throws behind obstacles (batch 1); a server SCRIPT ERROR and an intermittent engine send error when several friends leave at once (older code).
- **Kid rig contract for the Modeling lane:** [docs/kid-rig.md](docs/kid-rig.md) (`Body`, `LegL/R`, `ArmL/R`, `Body/Head`, `Body/Head/Hat`; pivots, coordinates, hair is not hidden, rebuild and merge rules). Full wearable equip integration is not part of r10 and needs its own evidenced handoff.
- **Checks (EC2, headless only):** units 13337/0; parse 60; check.py; network main, activities, invites, pets, play and new `--batch2` PASS with clean process logs; tap tours `play2_tour` 57, `play_tour` 34, `pets_tour` 74 checks, 0 failures.
- **Frozen candidates:** `ipad-r10` (manifest `05fb2db3…c3fbfe`, 534 files, archive `bba5cd85…b232a`; see its `LOCAL_VALIDATION_REQUEST.md`); `ipad-r9`, `ipad-r8`, `r8b`, `r8c`, `photos-native-r8` and `rev2` unchanged. Not committed or pushed.
- **Still open:** rendered, touch and device acceptance of r9 and r10 (Mac); Photos on a real device NOT TESTED.

## Revision r9: play ideas for ages 8-12, batch 1 (uncommitted, 2026-10-07)

Source: the reference package `Lantern_Lane_Playability_8-12_EN.zip` (SHA-256 `4cc62502…e225cf`), treated as reference data; the real game wins. Decisions and status for all ten ideas: [design/playability-8-12.md](design/playability-8-12.md).

- **Batch 1 implemented (F01, F03, F04, F09, F10):** snack tray with a 3 x 3 snack card and Share; fetch with Biscuit (authority brain plans `chase`/`bring`, action `carry`); rain-puddle splashes and a snowman with three faces; four toolkit tabs; "On display" with ask-first and server-side refusal. Network protocol 5 → 6. Saves stay compatible (optional `display` key and `variant` item field).
- **r8c findings fixed:** adoptable dog/bird names no longer reuse town animal names (Noodle, Poppy; old saves load renamed); the following pet walks beside the child.
- **Batch 2 (F02, F05, F06, F07, F08)** followed in r10 (above). Deferred with reasons: blueprints, paper boats and leaf piles, other animals' games, collaborative edit invitations.
- **Checks (EC2, headless only):** see [docs/validation.md](docs/validation.md#r9-play-ideas-batch-1-uncommitted--2026-10-07). Frozen candidate `tools/dual-host-workflow/ipad-r9` (manifest `98a53c3d…2b41e`, archive `a461aa35…5135c`) with `LOCAL_VALIDATION_REQUEST.md`; the rendered `play_tour.gd`, touch and device checks are the Mac's. Not committed or pushed; no deployment or device installation.
- **Still open:** Photos on a real device NOT TESTED (external gate); r8/r9 device installation not authorized.

## Revision r8: modeled kitchen and game room, bird repairs, Photos fixes (uncommitted, 2026-10-07)

**Closed out (2026-10-07).** Evidence archive `tools/dual-host-workflow/ipad-r8c/mac-evidence.tar.gz` (SHA-256 `9d15ee48…6bb2a`, uploaded with the user's approval) was verified and reviewed on EC2: `report.json`, all logs (pass markers present; no SCRIPT ERROR, leak or unexpected ERROR; the unit log's only error is the classified damaged-save JSON line; both Xcode builds `BUILD SUCCEEDED`; the purpose tool left only the add-only key and registered six languages in Debug and Release), the 11 rendered screenshots and `manual-desktop-photo.png`. Findings for r9: the pet name lists reuse town animal names (dog "Biscuit", bird "Pip"); in the manual photo the following cat is mostly hidden behind the child. Results: frozen `ipad-r8c` (manifest `af334fc4…db07`; product bytes identical across r8, r8b and r8c) passed the rendered `pets_tour.gd` with 0 failures and 11 inspected screenshots; r8b unit tests 11555 checks, 0 failures; real two-client `--pets` network test with restart PASS; manual play, adopting a cat and a desktop photo save PASS; Photos native rev2 clean default build and unsigned iOS Debug and Release device links PASS, with six localized add-only Photos descriptions in the app bundles.
**Still open (external gate):** saving to Photos on a real device is **NOT TESTED** (the official Godot simulator engine archive lacks arm64, so no simulator run either). Device installation and touch/audio acceptance of r8 are not done. Not committed or pushed.

r8 builds on r7 (r7 was never Mac-tested; its p001 birds had inside-out tail pieces and are replaced).

- **Models:** p002-game-kitchen (21 Mac-validated assets) replaces the code-built kitchen and game items; `game/scripts/art/props_rooms.gd` is gone. p003-pets-r2 replaces the two bird GLBs. All 23 GLBs matched their manifest digests before copying. Older kinds load through `TownModel.KIND_ALIASES`. Mapping: [design/pets-rooms-assets.md](design/pets-rooms-assets.md).
- **Cooking:** recipes on the modeled items; the omelette became **Rice and stew** (p002 has no omelette). The kitchen set-up keeps the way to the stove clear (ingredients along the left wall, pot on the counter, pan on the stove top turned to fit).
- **Pets:** the pet layer now notices when an owner moves to another room (it used to miss the change when the view switched first).
- **Photos (Mac findings):** debug and release plugin libraries with the matching `DEBUG_ENABLED` ABI; header-only SCons targets; the post-export tool removes the full-access key and registers all six localized `InfoPlist.strings` in the Xcode project. Frozen early as `photos-native-r8` (manifest `5e8ab0ec…4e0f`).
- **Unit runner (r8b):** engine and script errors now fail the test that raised them unless declared expected; fixes a fixture whose SCRIPT ERROR had hidden its own assertions.
- **New Mac driver:** `game/tests/pets_tour.gd` (12 screenshots at most), using the real UI and taps; its logic passes headless on EC2 (`--no-shots`), the rendered run is the Mac's.

## Revision r7: pets, themed rooms, cooking, Photos (uncommitted, 2026-10-07)

Plan and acceptance examples: [design/pets-kitchen-photos.md](design/pets-kitchen-photos.md); asset interface and integrated handoff: [design/pets-rooms-assets.md](design/pets-rooms-assets.md); Photos: [docs/ios-photos.md](docs/ios-photos.md). Builds on r6 (invites, private deployment, activity guide, toy box browser), which is unchanged in behavior.

- **Pets:** ten modeled, rigged pets from the Modeling lane's frozen batch p001 (3 cats, 3 dogs, 2 birds, 2 butterflies; no reptiles or other insects). **Pets** button (under Activities): adopt (family, variant, a name from a friendly list), choose who follows, send home; tap a pet to Pat or Feed (feeding needs a food bowl in reach). The authority owns adoption, selection and care; every client draws each pet behind its real owner; pets leave with their owner and are saved under the owner's device id.
- **Themed rooms:** Playroom and Attic are now shown as **Game room** and **Pet room** (labels only; saves unchanged). New toy box tabs **Kitchen**, **Games**, **Pets**, opened first in the matching room, listing new items plus suitable existing ones. Pet room: 13 modeled items (p001). Kitchen (stove, sink, fridge, counter, pot, pan, spoons, plates, rice sack, egg basket, vegetable basket, four dishes) and game room (TV, console with controller, game tablet, gaming desk, bean bag, game shelf) are **code-built** in the procedural prop style until Modeling's p002 replaces them. A themed room without its key item offers a one-tap **Set up** that adds only missing pieces.
- **Cooking:** stove → **Cook** → recipe card (rice bowl, vegetable soup, fried egg, omelette; greyed with missing ingredients) → 3 s of steam (authority timer, one dish per stove) → the dish is served as a saved item → **Eat** with a cheer → repeat. Per-player cooking counts are saved.
- **Photos:** native add-only iOS plugin source, export settings, localized purpose strings and exact Mac steps; desktop unchanged. **Not built or tested on EC2; device acceptance pending.**

Status: EC2 headless checks PASS (see [docs/validation.md](docs/validation.md)). Pending: Mac import and focused UI checks, the plugin build, the Photos device checklist, art approval of the code-built kitchen and game items. Not committed or pushed.

## Revision r6: invite refusal feedback over real WSS (uncommitted, 2026-10-07)

Hosted WSS checks of r5 passed except one assertion: a missing (sometimes wrong) invite was refused and closed without the friendly reason. Cause: the server closed 0.5 s after sending the reason, and a TLS hop can deliver both together, so the client dropped the unread reason. r6: the client closes after reading the reason; the server closes only after a 5 s fallback; still fail-closed (no data, no slot). Changed: `game/scripts/net/session.gd` (runtime), `game/tests/net_bot.gd`, `scripts/net_test.py`, new `scripts/delay_proxy.py` (holding relay used to reproduce and regression-test). Candidate `ipad-r6`, manifest SHA-256 `5fa8f34692c95c98197b4f5701e7d6e86f2b673c22b0f9cc0da5e7510fa25797`. EC2 headless checks PASS.

Operator acceptance of r6 (2026-10-07, generic; no private values recorded here):
- Archive and all 406 manifest hashes verified; the source and runtime diff matches the four changed files. Mac: parse 46 scripts PASS; unit 9547 checks, 0 failures.
- Public source, server PCK and the tracked checkout contain no private endpoint or invite.
- r6 is deployed on the hosted server, with autostart and backups. Real trusted-WSS `remote_check.py` live PASS: two clients shared a placed, moved and cleaned marker; reconnect kept it; wrong and missing invites both received the friendly reason, closed offline, with no town data before or after. The existing town survived the release switch.
- Signed universal iOS app built with the private pack (digest verified).
- Device install and launch: after the owner unlocked and replugged the devices, the signed personal build (the same private pack on both) installed with exit 0 and launched with exit 0 on the USB iPad Air 5 and iPhone 14 Pro. Native touch, audio and visual acceptance are **not** done; the owner is trying the game.

## Revision r4/r5: activity guide, PT-AH-001, private deployment and invites (uncommitted, 2026-10-07)

Frozen candidate `ipad-r4` (405 files: `game/` plus the deployment tools and contract), manifest SHA-256 `2786a051986694bf0448c66c6632315b7d02991d049f9a47255dcf4fa7f50926`, archive `tools/dual-host-workflow/ipad-r4/candidate.tar.gz` (SHA-256 `d39e7c9b0cc8ea7c546e6eaafaecb6bf51a14c81e6b89fc9a784c81b292ac190`), request `tools/dual-host-workflow/ipad-r4/LOCAL_VALIDATION_REQUEST.md`. Builds on the r3 browser work (r3 stays frozen; its evidence does not cover r4).

- **Activity guide** (user requirement): an Activities button opens How to play with eight illustrated cards (A-H), each with where to start, steps naming the real labels in all six languages, how you know it worked, Alone / With friends, and a safe next step. Data: `scripts/ui/activity_guide.gd`; illustrations: `scripts/ui/guide_art.gd` (code-drawn SVG, no image files).
- **PT-AH-001** (playtest, P3): tags drew over the photo message. Fixed by layering (tags under every HUD part) and by reserving the space of a showing message. Unit test reproduces the overlap without the reservation; `tests/guide_tour.gd --tag=pt001` repeats the recorded pose at 1100x800.
- **Private deployment** (Codex owns infrastructure; contract here, no real values): `docs/deployment.md`, protocol 5 invite handshake, `res://private/deployment.json` (git-ignored, packed only when injected), `scripts/remote_check.py`, `scripts/check_packaging.py`, `net_test.py --invites`, `tests/parse_all.gd`.

**Accepted candidate: `ipad-r5`** (manifest SHA-256 `52d4b22b5efebebf98f28eee913c68bdc0f82b85186d43f2fe70d781b8c03480`, archive SHA-256 `57b159d25debf5a6f685b1fe1a0c530ea18e49db0313d08f4d8fed7d0fdacb0b`). r5 differs from r4 only in two test helpers (`tests/guide_tour.gd`, `tests/browser_tour.gd`: taps are mapped from UI to window coordinates, which mattered at the scaled 1100x800 window); all 371 runtime game files are identical to r4. The r4 PT-AH-001 run had failed for that test reason (taps missed and walked the child indoors), not because of the game.

Status (2026-10-07):
- EC2: static, parse, unit, network, invite, operator-tool and packaging checks PASS.
- Mac (GPU, automated): unit 9547 checks, 0 failures; parse PASS; all ten rendered jobs PASS with no engine errors or leaks (guide iPad and iPhone in six languages, PT-AH-001 at 1100x800, browser iPad and iPhone in six languages, dock x3, six-language capture tour, activities tour); 206 PNGs, evidence `tools/dual-host-workflow/ipad-r5/mac-evidence.tar.gz` (SHA-256 `5f02f8c7…35ca`). Reviewed images include the PT-AH-001 photo message (readable, tags beside it) and the German guide overview.
- Mac (operator, local): private packaging and the prefilled join address verified with a private config; a signed iOS build passes but is **not installed**.
- **Pending:** real WSS checks on the hosted server (not done; host recovery pending), device install and touch/audio acceptance, native-speaker review.
- Not committed or pushed (no authorization for this revision).
- Follow-up nit: two-line guide card taglines sit close to the card's bottom edge.

## Earlier task r3: toy box browser and crowded-room picking (UI, uncommitted, 2026-10-07)

User-authorized UI task after `4fe1552`: finding, categorizing and placing items with a large catalog, and selecting existing objects in a crowded scene. Design and acceptance examples: [design/item-browser-ux.md](design/item-browser-ux.md). **Not committed or pushed; no device install authorized for this task.** The coordinator installed and launched `4fe1552` on the iPhone 14 Pro; touch and audio acceptance of that build are still unverified.

Ownership: this lane owns UI code (`hud.gd`, `ui_kit.gd`, new `item_query.gd`), browsing and query logic, UI tests (`tests/browser_tour.gd`, `run_tests.gd`, the test-only fixture `tests/fixtures/large_catalog.gd`) and UI strings in the six locale files plus the regenerated CJK font subsets. Catalog entries, models, builders and production records belong to the Modeling lane and were not edited; every filter is derived from existing metadata (`anchor`, `size_class`, `tabletop_eligible`, `seats`, `support_surface`, `space`). Coordination notes: the Modeling lane's integration script may also rewrite `game/locale/*.json` and the font subsets; my locale edits are additive (23 keys per language) and `scripts/build_fonts.py` must be re-run after either lane changes locale text. No shared schema or equip-system change was needed.

Status and evidence: see "Toy box browser" in [docs/validation.md](docs/validation.md). Mac GPU and device acceptance: pending.

## A-H goal: finish A-H and fix the r1 acceptance blockers (committed and pushed as `4fe1552`, 2026-10-07)

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

Updated 2026-10-08 after the r13b release. Resolved since the earlier list:
- the shutdown leak and landmark labels (A-H);
- wearables (r12b, released);
- the ceiling and excluded wall items (r13b, released);
- hosting with TLS and invites (HK, protocol 9).

Still open:

1. The Wardrobe shows names only, with no pictures, in the released r13b. Addressed by r14b (Mac-accepted 2026-10-08, not released); its white-frame glasses pictures are faint.
2. The ceiling fan, mirror ball and hanging screens are static. (Ceiling items can be turned since candidate r15, which is not released.)
3. Wall items can overlap tall standing furniture against the wall (only hanging items have the headroom rule).
4. The desk lamp fits the cozy table only at 0°, 90°, 180° and 270°. At 45° it is refused truthfully, because its turned box is about 0.565 against a 0.56 slot.
5. Footprints are circles, so long items (beds, counters, sofas) can sit closer to walls than their shape suggests.
6. Modeled seats use only `Seat0`: the two-seat bamboo bench seats one child.
7. Animals are recreated each session, and they don't enter houses.
8. The scrapbook lists only this session's photos.
9. Device-only checks are pending with the user (touch, audio, Photos, four-child performance).
