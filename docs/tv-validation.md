# Validation record: Apple TV controller lane (atv-r20-controller)

The Apple TV lane's own record, kept as it was sealed (r1 to r13). The production history is in [validation.md](validation.md). Every result here is from EC2, Godot 4.7.2.stable.official `ed1daf0bf`, headless. These are **logic checks, not TV rendering, device or controller-feel evidence**. The TV engine (4.8.0-dev, tvOS) is validated on the Mac.

User data for every run here is isolated: `XDG_DATA_HOME=build/atv-r20-controller/userdata`. Logs are copied to `build/atv-r20-controller/logs/`.

## Results (2026-10-25)

| Check | Result |
|---|---|
| `scripts/test_all.sh --quick` (inherited, unchanged) | **PASS** (`test_all_quick_final.log`): `check.py` with links, music, import, units 21881/0. The first run, before the inherited reference documents were added, failed on 23 Markdown links into files missing from this partial tree; it is kept (`test_all_quick.log`, `check_links_missing.txt`). |
| `scripts/test_all.sh` (full) | Network steps **PASS**: `net_test.py` NET TEST PASS and `--activities` ACTIVITIES TEST PASS (`test_all_full.log`). Stopped on purpose before its software-OpenGL render steps (capture tour, dock tours): **pending on the Mac**, not PASS (dual-host ownership). |
| `scripts/tv_check.py` (every `check.py` check except links) | PASS: 1359 game messages, six languages, fonts 1499 characters |
| `scripts/check_audio.py` | PASS |
| Import | PASS (exit 0) |
| Parse | PASS, 80 scripts |
| Units (`run_tests.gd`) | 21881 checks, 0 failures; `test_tv_controller` and `test_tv_durable` included |
| Mutations | **Poll by time and size:** fails the same-length, same-second check. **No restore-failed guard:** fails 2 checks (a fresh town overwrote the kept copy). |
| `tv_tour.gd`, main | 135 checks, 0 failures, twice in a row, and again on the final source (`final_tv_tour_main.log`) |
| `tv_tour.gd`, reopen | 6 checks, 0 failures (`final_tv_tour_reopen.log`) |
| `tv_tour.gd --phase=defaults` / `defaults_restart` with `--fake-defaults` | 14 / 8 checks, 0 failures. **Dry run with the stand-in, not the native module.** Without the module the phase fails at its first check, as intended. |
| `tv_brand_rasterize.gd` | PASS: 13 images, exact sizes, opaque back layers, transparent upper layers |
| Native module `LanternDefaults` | The Mac's Apple SDK preflight of the first draft failed with 14 errors (ClassDB incomplete, D_METHOD undeclared: a missing `core/object/class_db.h` include in `lantern_defaults.mm`; `mac-native-preflight-fail.log`). Fixed in source; **not compiled since** (no Apple SDK on EC2): a Mac gate. |

**Kept as evidence, not counted as passes:**
- `tv1`: run before the import;
- `tv2` to `tv10`, `tv12`, `tv13_*`: controller flow failures, each found and fixed;
- `back1` to `back3`: the B probe;
- `smoke_nomod`: no module.

**Fixed from those runs:**
- B could not reach a button scrolled out of view;
- the Scrapbook's Close was off-screen at TV size;
- the tour's camera step;
- a freed toy box card;
- fail-fast on unfinished cases.

## Not covered here

- The rendered steps of `test_all.sh` (capture and dock tours) and the network tests are the r20 production checks. The network and rendered regressions are listed in the candidate's `LOCAL_VALIDATION_REQUEST.md`.
- Physical controller, Apple TV rendering (Metal), real camera photos, purge survival and the real WSS join are Mac and device gates.

## r2 (2026-10-25): repairs after the Mac r1 review

**Mac r1 (Godot 4.8-dev, Metal mobile renderer, real GPU):**
- import, parse 80/0, units 21881/0;
- TV tour headless 135/0 and reopen 6/0;
- **GPU** TV tour 135/0 and reopen 6/0.

**The author opened all 8 originals.**

**Visual failures:**
- **`05_scrapbook_photo`:** the saved photo's thumbnail had the controller hint bar burned in. `_take_photo` hid only the HUD, not the controller's layer.
- **`04_inside`:** the hint bar covered the town status at the top, because only buttons were avoided.

**OK:** `01_title`, `02_friends_tv`, `03_walk`, `06_placing`, `07_ja_scrapbook` and `08_de_scrapbook`.
- **Noted, unchanged:** the placing panel's text is touch wording ("Drag it, turn it, then tap Place here."); the hint bar beside it gives the controller buttons.
- **Noted, unchanged:** in German the hint bar ends about 8 px from "Schließen" without overlapping it.

**Repairs:**
- **Capture:** `main.capture_world` hides the HUD and the controller layer for the captured frame and restores each as it was, for photos and story pictures alike. It does not read a frame when there is no renderer.
- **Hint placement:** the bar avoids readable text as well as buttons, tries every row of the safe area, and is placed again five times a second.
- **Defaults smoke:** every filler and the refused value use distinct bytes, because a binary property list may keep identical data once. The Mac's device diagnostic used distinct values and passed.

**Regressions:**
- **Tour, photo and story:** the camera is pressed through the controller in both flows. An observer must see the HUD and controller layer hidden when the picture is read, and both restored after.
- **Tour, inside a house** (the Mac r1 state): the hints leave the town status readable.
- **Tour, text by itself:** a test label where the hints are must send them elsewhere, still covering no button.
- **`hints_ok`:** now also fails on covered readable text, using a test-side scan independent of `pad_input.gd`.
- **Mutations:** a capture that leaves the controller layer visible fails the photo and story checks. Placement that ignores text fails the text check (`logs-r2/mut_*.log`).

**r2 results (EC2, 4.7.2 headless):**

| Check | Result |
|---|---|
| Tour main | 167/0 |
| Tour reopen | 6/0 |
| Defaults dry runs | 14/0 and 8/0 (stand-in, distinct fillers) |
| `test_all.sh --quick` | PASS, units 21881/0 |

**Render steps** of the full `test_all.sh` stay with the Mac.

## r3 (2026-10-25): Mac r2 GPU and full-regression findings

**Mac r2 (4.8-dev):**
- import, parse 80/0, units 21881/0;
- headless 167/0 and reopen 6/0.

**Three findings:**
1. **Metal GPU TV tour:** failed at `_join_screen`, where B, B did not return to the title (36 checks, 2 originals; both open and normal: title, friends screen).
2. **capture_tour:** 2 failures.
3. **dock iPad Air:** 1 failure.

**1. Second B on the character screen (GPU only):**
- **Path:** the character screen is rebuilt from the friends screen's Back about 3 frames before B. Its Back button sits in a scroll list below the visible part. The controller scrolled the list once and tapped on the next frame.
- **Likely root cause:** with real frame timing the list had not settled, so the tap hit clipped space. Headless always settled within one frame.
- **Fix:** tap only once the button's centre is inside the list's visible rect, re-scrolling for up to 10 frames; ignore buttons of a screen queued for deletion; `--pad-trace` diagnostics.
- **Regression:** `--phase=menus_back` runs the exact path 5 times, plus a slow-list case that holds the list for 3 frames. With the old one-shot tap the slow case fails (`logs-r3/mut_tap.log`); fixed, 51/0.
- **The GPU run must confirm it:** headless alone cannot.

**2. capture_tour location strings:**
- **Cause:** the expectations "Floor 2 · Playroom" and "Floor 3 · Attic" predate the accepted room rename. The canonical `TownModel.ROOM_NAMES` has Game room and Pet room.
- **Fix:** only those two expected strings were updated; the location assertion stays. No product room was renamed.

**3. dock iPad Air `bottom_edge`:**
- **Cause:** a latent R20 touch bug. While dragging the item down, the finger passes over the placement tools and the toy box, and those menus took the drag's motion. The item stopped under the tools at y ≈ 293, the dock never switched, and the tools covered it.
- **Reproduced headless** at 1475 x 1024 with the same numbers (item at 648.6, 293.0; dock bottom).
- **Fix** (`play_controller.gd`): a drag that started on the item keeps its motion and release over the menus. Afterwards the dock switches at step 7 and the item follows the finger to y 748, as in the accepted r1/r2 dock runs. (r5's dock log is not a valid baseline: its item never moved.)
- **`dock_tour.gd --no-shots`** now runs headless (skips screenshots and the thumbnail wait; checks unchanged): iPad, iPad Air and iPhone all PASS. Without the fix the iPad Air run fails exactly as on the Mac (`logs-r3/mut_drag_ipadair.log`).

**r3 results (EC2, 4.7.2 headless):**

| Check | Result |
|---|---|
| TV tour main | 167/0 |
| TV tour reopen | 6/0 |
| `menus_back` | 51/0 |
| furn_tour | 122/0 |
| play_tour | 43/0 |
| dock headless ×3 | PASS |
| `test_all.sh --quick` | PASS, units 21881/0 |

The rendered capture and dock tours and the GPU TV tour stay with the Mac.

## r4 (2026-10-25): test fixture only

**Mac r3 (4.8-dev):**
- headless: all PASS;
- GPU `menus_back`: 51/0 (trace kept). The full GPU tour now passes B, B.

**First full GPU failure: a race in the test's precondition, not the game.**
- In `_walk` the test put its test label where the hints were, waited 2 frames, then required the label to overlap the hints' current place.
- The hints are placed again 5 times a second, and had already moved off the label (y 899 -> 827). The real checks ("move off readable text", "still cover no button") passed.
- Originals `01_title`, `02_friends_tv` and `03_walk` were opened; all normal.

**Fix:** only `tv_tour.gd`.
- The test places the hints explicitly, snapshots their rect, puts the label on that snapshot, and requires the label to overlap the snapshot.
- Then it places again and checks the real rules.
- Product code is unchanged from r3.

**Results (EC2):**
- tour main 167/0;
- ignoring readable text still fails "the hints move off readable text" (`logs-r4/mut_text.log`).

## r5 (2026-10-25): CJK glyphs in the controller hints

**Device acceptance of r4 on the Apple TV:**
- main 175/0, reopen 6/0, native `defaults` 14/0, `defaults_restart` 8/0;
- **user-confirmed:** the Switch Pro controls and the real TV join to the HK town are normal.

**Defect in the device original `07_ja_scrapbook`:** the Japanese hint for the D-pad showed boxes for its kanji.
- **Cause:** the controller layer had no theme, so its hint label used Godot's built-in Open Sans. That font lacks every Chinese and Japanese hint character (confirmed headless).
- **Fix:** `pad_input.gd` sets `_hint_panel.theme = UI.theme()`. That is the shared theme whose font follows the language, with the bundled CJK fonts as fallbacks.

**Regression** in `tv_tour.gd`, in the six-language case:
- every character of each translated hint must exist in the font the hint label actually resolves;
- a zh-CN screenshot is added next to ja and de.

**Without the theme line,** zh-CN and ja fail with the missing glyphs (`logs-r5/mut_theme.log`).

**r5 results (EC2):**

| Check | Result |
|---|---|
| Tour main | 173/0 |
| Tour reopen | 6/0 |
| `test_all.sh --quick` | PASS, units 21881/0 |

Native storage and network behaviour are unchanged (their inputs are byte-identical to r4).

## r6 (2026-10-25): test only, after the r5 device run

**r5 on the Apple TV:**
- the font fix passed: hint glyph checks in all six languages, 9 new originals;
- main stopped at 177 checks with 2 failures. The first was "and that it is back" in the disconnect case, so the storage step and reopen did not run.

**Cause: a test assumption, not the game.**
- The real Switch Pro Controller was connected beside the simulated controller (device 0).
- When device 0 "disconnected", the game correctly took over the other connected controller. So the simulated reconnect correctly showed no "Controller connected" toast, because a controller was already in use.
- The earlier check "the pointer hides with no controller left" had only passed through its "another controller is connected" escape.
- Every safety check passed: walking stopped, nothing stayed pressed, the controller worked again.

**Fix:** `tv_tour.gd` only.
- **Diagnostic:** the case prints the connected controller ids, their names and the one in use. It makes sure the simulated controller is in use first.
- **Both cases:** walking stops, "Controller disconnected" is shown, nothing stays pressed, and the controller works again.
- **No other controller:** the pointer hides, and on return "Controller connected" is shown and the controller is used.
- **Another controller connected:** it takes over at once and the pointer stays. The returning one does not take over by itself; a button press on it does.
- **Product code is unchanged.**

**The tour's own leftovers:**
- **After a stop:** a main run that stops before its storage step removes only the photos created during that run (the list taken at its start; its own names are noted in `user://tv_tour_artifacts.json`), plus its tour town. It also prunes only those names from the scrapbook index. After its result is written it sends no more input and stores nothing.
- **`--phase=cleanup_photo --photo=<exact name> --sha256=<hash>`** removes one earlier leftover, only when both the name and the SHA-256 of its bytes match. It then removes only that name from the index.
- **The r5 leftover:** it was identified by the coordinator from device metadata (13:47:50Z, inside the failed run).

**EC2 results (isolated folders):**

| Check | Result |
|---|---|
| main | 174/0 |
| reopen | 6/0 |
| cleanup, wrong hash | Refused, nothing removed |
| cleanup, right hash | Only the target removed |
| Runs stopped at 14 s and 18 s | Each removed exactly its own photo and town |

User stand-in photos stayed byte-identical throughout.

## r7 (2026-10-25): the Siri Remote's Menu returns to the Home screen

**Requirement (user):** the Siri Remote's Menu goes back one step, and at the title another press returns to the Apple TV Home screen. The Switch Pro's B is unchanged.

**Root cause** (port source at `791c358`): the view controller never set `controllerUserInteractionEnabled`. So Menu never reached UIKit, and the port's own Menu handling was unreachable.

**Fix:**
- the native `LanternRemote` (Siri-Remote-only Menu presses, and the view-controller switch);
- `game/scripts/ui/tv_remote.gd` (the step-back hierarchy; at the title, arm Home, and disarm on any controller input or on leaving);
- `pad_input.gd` emits `controller_used`;
- `main.gd` creates the handler on a TV;
- one new string in six languages.

**Checks (EC2, headless; a stand-in remote queues the presses):**

| Check | Result |
|---|---|
| Tour main | 204/0 |
| Tour reopen | 6/0 |
| Without the disarm on controller input | "controller input disarms Home at once" fails (`logs-r7/mut_disarm.log`) |

**The new tour case checks:**
- Menu closes a dialog, cancels placing, leaves Decorate, and leaves the town to the title; the engine's go-back request does the same;
- the controller's B at the title does not arm Home;
- Menu at the title arms Home, with a note inside the safe area, covering no button, in a font with every one of its characters;
- controller input and leaving the title disarm it.

**On the TV** the tour also checks that the real module turns the view-controller setting on and back off.

**Not covered headless:** the actual return to the Home screen, a real Siri Remote press, and the Switch Pro A at the armed title. These are device checks.

## r8 (2026-10-25): native fix before the r7 build (Mac pre-build review)

**Finding:** in the pinned port the window's root view controller is a SwiftUI hosting controller (`GodotWindowScene`, a `UIViewControllerRepresentable` returning `GDTViewController`). So r7's `root_controller()`, which accepted only the root itself, would never find the engine's `GCEventViewController`, and the Home switch would have failed on the device.

**Fix** (`lantern_remote.mm`/`.h` only):
- use the engine's own published controller, `GDTAppDelegateService.viewController` (set in `makeUIViewController`);
- fall back to a search of each window's view controller tree, at most 4 levels (children and presented controllers).

No game script changed; the r7 EC2 results apply. The tour's device check "the native module hands Menu to tvOS when asked" is the gate for this.

## r9 (2026-10-25): bounded arming (review before the build)

**Finding:**
- Apple's `GCEventViewController` delivers controller input either to UIKit or to the Game Controller framework, not both. While Home is armed, Switch Pro presses reach only UIKit, so the game's disarm on controller input never fires.
- A controller press that UIKit reports as Menu would reach the port's `pressesEnded`, and with `quit_on_go_back` it would go Home.

**Fix:**
- **Native:** `arm_system_back(seconds)` arms for at most 5 s, then a native timer takes Menu back. While armed, a press gesture recognizer on the engine's view (select, play/pause, arrows) ends it at once.
- **Game:** follows the native state every frame (the note hides and `quit_on_go_back` resets).
- **Test:** `tv_tour.gd` starts with no stale storage record, so a reopen never reads an earlier run's record.

**Remaining limit:** a controller press that UIKit itself reports as Menu cannot be told apart from the Siri Remote's. Device checks f and g, and a press within the armed window, are mandatory. Injected joypad events prove nothing about physical A/B.

**EC2 results:**

| Check | Result |
|---|---|
| Tour main | 206/0 (new: "when the native side ends the armed state, the game follows at once") |
| Tour reopen | 6/0 |
| Without following the native state | Fails that check (`logs-r9/mut_follow.log`) |


## r10 (2026-10-27): native build fix (header order); armed-state limits stated

**Mac r9 results:**
- parse 82, headless main 206/0, reopen 6/0, GPU main 216/0, reopen 6/0 (with the `home_armed` screenshot);
- the native build **failed**: in the tvOS 26.5 SDK, GameController's `GCPhysicalInputElementCollection<Key, …>` is ambiguous with Godot's `enum class Key` (`core/variant/variant_caster.h`), two errors in `lantern_remote.mm` (`mac-r9-native-build.log`).

**Fix:** `lantern_remote.mm` imports UIKit and GameController before any Godot header, as the engine's own files do. There is no other code change.

**Docs:** `design/tv-controller.md` no longer says that any controller input disarms Home. While armed:
- a controller's A probably only ends the armed state, so a second press acts;
- its B probably goes Home (the known limit).

The device decides both (checks f and g2).

**Game files are byte-identical to r9:** the Mac's r9 parse, headless and GPU results carry over. The comment at the top of `game/scripts/ui/tv_remote.gd` still says a controller button can never send the game Home. That comment is wrong and will be corrected after the device result, so the game files tested on the Mac are not changed here.

**Not verified yet:** the native compile, and the Siri Remote's Home and A/B behaviour on the device.

## r11 (2026-10-27): the second Menu press does not reach Home (device check e failed on r10)

**Device result r10:**
- tour main 218/0 and reopen 6/0 (both automated);
- **the user's physical check e failed:** at the title the note appeared, but pressing Menu again within 5 s did not return to the Apple TV Home screen.

The automated "hands Menu to tvOS" check only reads `controllerUserInteractionEnabled`. It proves nothing about what tvOS does with the press.

**Investigation (pinned engine `791c358`, `drivers/apple_embedded/godot_view_controller.mm`):**
- `pressesBegan` passes no press to `super`; for a Menu press it does nothing at all;
- `pressesEnded` passes only the end of a Menu press to `super`, and only with `quit_on_go_back`;
- Apple's `UIResponder.pressesBegan` documentation says to forward unhandled presses to `super`.

This is the likely cause, but **not proven**: a press might also not reach this controller, because the window's root is a SwiftUI hosting controller.

**Fix and diagnostics:**
- **Engine patch** `tv/engine/0001-tvos-menu-presses-to-uikit.patch` (SHA-256 `9c38ed15…6201`, tvOS only): while `quit_on_go_back` is set, the whole Menu press goes to UIKit. It also logs `[tvOS Menu] began/ended: forwarded to UIKit`.
- **`LanternRemote`** logs, on arming, the responder chain above the engine's controller and the focused item (class names only).

**EC2:** the patch applies cleanly (`git apply --check`) to a clean checkout of `791c358`. It does not overlap the coordinator's `engine-791c358.patch`. `game/` is byte-identical to r9 and r10. Neither the native code nor the engine was compiled here (there is no tvOS SDK).

## r12 (2026-10-27): r11 result; comment correction

**r10 physical observation:** the note stayed about 5 s and then disappeared; a second Menu press within the window neither reached Home nor ended the armed state; Menu after the timeout showed the note again. So the timeout and re-arming worked, but this did not show where the press was lost.

**r11 on the Apple TV:**
- **Build:** the engine patch was applied with `patch -p1 --batch`. `godot_view_controller.mm` went from `37571027…` to `6ef55d73…`. Both diagnostic strings are in the signed binary.
  - A first build was rejected: `git apply` in a tar tree nested inside another repository skipped the patch and still exited 0. `tv/engine/README.md` now gives the tar-safe command and requires the hash checks.
- **Device tour:** main 218/0 with 10 screenshots, reopen 6/0.
- **Physical check e PASS:** at the title, Menu then Menu returned to the Apple TV Home screen (confirmed by the user). Log lines:
  - `[tvOS Menu] armed: interaction YES; chain` through the SwiftUI host`; focused none`;
  - `[tvOS Menu] began: forwarded to UIKit`;
  - `[tvOS Menu] ended: forwarded to UIKit (began forwarded)`.
- The cause was the engine's `pressesBegan`, which never forwarded the Menu press.

**r12 change:**
- The comment at the top of `game/scripts/ui/tv_remote.gd` now states the armed-state limits (A may only disarm; B may go Home while armed) and the engine patch. Only `##` comment lines changed; every code line is identical to r11.
- Parse check on EC2: Godot 4.7.2, `--check-only`, exit 0.

**Physical checks f, g, g2, g3, g4, a–d and h:** pending (being run by the user).

## r13 (2026-10-27): same comment, same line count as r11

**Mac result for r12:**
- 1605 files verified; parse 82 PASS.
- A controlled export (the whole r11 device work and import state, with only `tv_remote.gd` replaced) gives 1515 PCK entries. Exactly one differs: `scripts/ui/tv_remote.gdc`.
- The cause: the r12 header had 3 more comment lines, which moved the debug line numbers of the code. r12 controlled PCK `69b51a13…94ce`, installed r11 PCK `f6f27c79…`.
- An earlier export from re-created import metadata re-imported 660 scene binaries. That attempt is kept and counted as non-equivalent.

**r13:** the same corrected header, reflowed into r11's 9 comment lines before `extends Node`. Only lines 4–7 differ from r11, and every code line keeps its line number. The compiled `tv_remote.gdc`, and so the PCK, are expected to equal the installed r11's. Parse check `--check-only` on EC2: exit 0.

## Physical results on the r11 device build (user, 2026-10-27; recorded at integration)

**PASS:**
- **e (the requirement):** at the title, Siri Remote Menu then Menu returns to the Apple TV Home screen.
- **f:** armed with Siri Remote Menu and the pointer on Play, Switch Pro A does not go Home, and play continues into Play.
- **g:** at the title, not armed, Switch Pro B does nothing (no note).
- **Pointer semantics:** A selects only when the pointer is on the button.

**Not verified (no claim):**
- g2: Switch Pro B while armed. UIKit reports a controller's B as Menu and cannot say which device sent it, so B may go Home while armed.
- g3: B after the 5 s timeout.
- g4: Siri Remote select while armed.

**Not separately re-run on r11:** a–d and h; the user scoped this as a bounded Home fix.

r12 and r13 add no executable change to r11: only the `##` header comment of `tv_remote.gd` changed. In r13 it keeps r11's line count, so the compiled script is unchanged. **Mac result:** the controlled r13 PCK is byte-identical to the installed r11's `f6f27c79…` (1515 of 1515 entries); no reinstall.
