# Design: Lantern Lane on Apple TV with a game controller (atv-r20-controller)

Status: TV adaptation of the accepted r20-motion source, developed 2026-10-25 to 2026-10-27 as the frozen lane `atv-r20-controller` and integrated into production at r13 (manifest `f4c33b423791bafe11f90c45c8934855584a9576f87847e6349d13b53bdeeff1`; `game/`, `tv/` and `scripts/` byte-identical). The user authorized installing Lantern Lane on their Apple TV and playing with a Nintendo Switch Pro Controller.

- **Installed on the user's Apple TV** (the lane's r11 device build, with the engine Menu patch); not an App Store release. Device results: [docs/tv-validation.md](../docs/tv-validation.md).
- **Unchanged:** iPhone, iPad and the HK server. The network protocol (10) and save schema (2) are r20's.
- **Separate from R21.** The paused r21 photo-wall work is not part of this lane: no photo wall, no protocol 11, no schema 3.

## Engine baseline (different from r20)

- r20 was built and validated with **Godot 4.7.2.stable.official `ed1daf0bf`**.
- Apple TV needs an engine that has a tvOS platform. The official 4.7.2 templates have only iOS and macOS. The Mac builds an isolated engine from the draft upstream tvOS work:
  - `stuartcarnie/godot` branch `tvos_platform`, commit `791c358acacd05022e3e8ffc3553e7125dd5fd36`, which reports **4.8.0-dev**;
  - the Metal mobile renderer, SDL game controllers, and Xcode with the tvOS 26.5 SDK.
- **The Mac's tvOS fix:** `OS_TVOS::get_user_data_dir` returns `Library/Caches/GodotApp`. Documents and Application Support are not writable on tvOS. iOS is unchanged.
- **What the EC2 checks in this candidate cover:**
  - they ran on 4.7.2 headless, so they are evidence of the game logic only, not of the TV engine, its renderer or the device;
  - the project still says `GL Compatibility`; how the 4.8-dev tvOS template renders it is a Mac validation gate.

## Contract

- **No touch screen or mouse needed.** Everything from launch to play is reachable with one controller, through the real buttons and the real world taps of the game. No action is reimplemented.
- **One press, one action.** Joypad events are consumed by the controller layer only. The built-in `ui_*` actions lose their joypad bindings, so a press never also walks, moves GUI focus or presses a focused button.
- **Dialogs hold the world still.** While a dialog or the menus are open, the sticks move the pointer, never the child.
- **B never chooses an unknown option.** B presses only a dialog button known to be safe: Close, Cancel, Back, Not now, Keep it or Done. Otherwise it closes the dialog without choosing anything.
- **Nothing stays stuck.**
  - **Disconnect:** walking stops, the pending tap is released and the game says the controller disconnected.
  - **App leaves the foreground:** the same reset happens.
  - **Late controller:** one that appears after launch is picked up (the Apple TV reported the paired Switch Pro Controller about 3 s after start).

## Controls

Godot's SDL game controllers are positional: `JOY_BUTTON_A` is the bottom face button and `JOY_BUTTON_B` the right one. On a Nintendo controller, the button **labelled A is on the right** and the one labelled B at the bottom. Confirm and back therefore follow the label:

| Nintendo label | Godot button | Action |
|---|---|---|
| A (right) | `JOY_BUTTON_B` | Confirm: tap where the pointer is |
| B (bottom) | `JOY_BUTTON_A` | Back (see the contract) |
| X (top) | `JOY_BUTTON_Y` | The context action (Sit, Go in, ...) |
| Y (left) | `JOY_BUTTON_X` | Turn the thing being placed |
| + | `JOY_BUTTON_START` | Place here |
| L / R | shoulders | Turn the camera |
| ZL / ZR | trigger axes | Scroll a list, or zoom, where the pointer is (like a mouse wheel) |
| D-pad | | Jump the pointer to the nearest button that way (scrolling its list) |
| Left stick | | Walk; move the thing being placed; the pointer in a dialog |
| Right stick | | The pointer |

- **Layouts:** a Nintendo layout is detected from the controller's name or Nintendo's vendor id. Other controllers use the standard positions (A at the bottom).
- **Swap A and B:** a setting in Sound and music, saved on the device, for a controller that reports its buttons the other way round.
- **Deadzone:** radial 0.22, rescaled so motion starts smoothly.
- **Hints:** a small bar names the buttons for the current state (dialog, play, placing) in the six languages. It sits inside the TV safe area and never covers a button or readable text (the town status, toasts, dialog and panel labels, cut to their scroll lists). It tries every row, centred, then left and right, and is placed again five times a second (r2: on the Mac r1 originals it covered the town status inside a house).
- **Hint font (r5):** the controller layer takes the game's shared UI theme, whose font follows the language and carries the bundled Chinese and Japanese fonts. Without it the hints used Godot's own Latin font, and on the Apple TV the Japanese hint showed boxes for the kanji of its D-pad word. The tour checks that the hint font has every character of the hints in all six languages, and takes zh-CN, ja and de screenshots.
- **Photos never show the controller:** the camera hides every overlay above the world (the HUD, and the controller's pointer and hints) for the captured frame, then restores each as it was. Photos and story pictures use the same capture (`main.capture_world`). r2: the Mac r1 photo had the hint bar burned in.

## The Siri Remote's Menu (r7)

**Root cause:** the pinned tvOS port (`stuartcarnie/godot` `791c358`) never let the Menu button reach UIKit.
- Its view controller is a `GCEventViewController`, and the line that would set `controllerUserInteractionEnabled` is commented out. The property keeps its default, so controller and remote input goes to the Game Controller framework, not to UIKit.
- The port's own Menu handling (`pressesEnded`, `UIPressTypeMenu`: hand the press to UIKit for Home when `SceneTree.quit_on_go_back`, else a go-back request) is therefore never reached. The Menu button never returned to the Apple TV Home screen.

**Apple's pattern** (the DemoBots sample): set `controllerUserInteractionEnabled` to true only on the game's top screen, so that Menu goes to UIKit there and tvOS returns Home.

**The fix** has two parts, with no engine change:

1. **Native:** `LanternRemote`, in the candidate's tvOS-only module `tv/native/lantern_defaults`.
   - It counts Menu presses of the Siri Remote only: a controller with a micro gamepad and no extended gamepad, through `buttonMenu`. A game controller's buttons are never taken for it.
   - It switches the root view controller's `controllerUserInteractionEnabled`.
2. **Game:** `game/scripts/ui/tv_remote.gd`, on a TV only.
   - **Back one step:** Menu acts like the controller's B. It closes a dialog, cancels placing, leaves Decorate, or presses Back in the start menus.
   - **In town with nothing open:** it leaves to the title, like the Leave town button.
   - **At the title:** the first Menu press "arms" Home. The view controller hands the next press to UIKit, and `quit_on_go_back` lets UIKit take it, so tvOS returns Home. A note says "Press Menu again for the Home screen."
   - **Disarming:** leaving the title, controller input that the game sees (`pad_input.controller_used`), or the native side ending the armed state (below). While armed, controller presses go through UIKit only, so the game does not see them: the native side has to end it (see "Bounded arming").
   - **Elsewhere:** `quit_on_go_back` is false. A Menu press that reaches UIKit anyway becomes a go-back request, which is handled the same way.

**The controller's B is unchanged when Home is not armed:** it never arms Home and never goes Home. While armed (at most 5 s after a Siri Remote Menu press at the title), see the remaining limit below.

**Bounded arming (r9).** Apple's `GCEventViewController` delivers controller input to one path at a time. While Menu is handed to UIKit, controller presses reach only UIKit, and the game cannot see them, so disarming on game-side controller input alone is not enough. The native side therefore:
- arms for at most 5 seconds (`arm_system_back`), then takes Menu back by itself on a native timer;
- while armed, ends the armed state at once on any other UIKit press (select, play/pause, arrows) through a press gesture recognizer on the engine's view. A controller's A, if UIKit reports it as select, ends the armed state instead of reaching Home. That A press itself probably does nothing else (the game does not see it), so a second A press acts: device check f records which.

The game follows the native state every frame.

**Remaining limit:** UIKit does not say which device a press came from. A controller press that UIKit reports as Menu (on game controllers normally their B, which means Back) still goes Home while armed. This is a mandatory device check (g2); until the device shows otherwise, take it that the Switch Pro's B goes Home while armed. Not used: a programmatic quit or any private suspend API.

**Build note (r10):** `lantern_remote.mm` imports Apple's UIKit and GameController before any Godot header, as the engine's own files do. Otherwise the tvOS 26.5 SDK's `GCPhysicalInputElementCollection<Key, …>` is ambiguous with Godot's `enum class Key` (the r9 native build failed on this).

**Device result r10 (check e failed):** at the title the note appeared, but the second Menu press did not reach the Apple TV Home screen. The self-test "hands Menu to tvOS" only checks `controllerUserInteractionEnabled`, not what tvOS does with the press.

**Likely cause (r11, not yet proven):** the pinned engine's `GDTViewController.pressesBegan` never forwards a press to `super`. `pressesEnded` forwards only the end of a Menu press. Apple's `UIResponder` documentation says to forward unhandled presses to `super`, so UIKit never sees the beginning of the Menu press.

**r11 fix:** a narrow engine patch, `tv/engine/0001-tvos-menu-presses-to-uikit.patch` (see its README). While `quit_on_go_back` is set (Home armed), the whole Menu press goes to UIKit: began, ended and cancelled.

**r11 diagnostics:** `LanternRemote` logs one line when Home is armed, with the responder chain above the engine's controller and the focused item (class names only). With `[tvOS Menu] began/ended` from the patch, the device log shows whether the press reaches the engine's controller at all.

**Device result r11 (check e PASS):** at the title, Menu then Menu returned to the Apple TV Home screen; the user confirmed it. The physical log showed:
- `armed`: interaction YES, the SwiftUI responder chain, focused item none;
- `began: forwarded to UIKit`;
- `ended: forwarded to UIKit (began forwarded)`.

So the cause was the engine's `pressesBegan` keeping the Menu press from UIKit. The SwiftUI host passes the whole press on.



- The HUD and the menus keep to the TV title-safe area (Apple's tvOS layout guide: 60 pt at the top and bottom and 80 pt at the sides of 1920 x 1080), or the system's safe area if larger.
- **Tapping a button in a scrolled list (r3):** the controller scrolls the list, then taps only once the button's centre is inside the visible part, re-checking for up to 10 frames. A tap before the list settles would hit clipped space; the Mac r2 GPU run failed B on the character screen this way. Buttons of a screen being replaced (queued for deletion) are never chosen. `--pad-trace` prints every action, chosen button, tap and release.
- **Two r20 layout problems the controller tour found, fixed in this lane:**
  - **Character screen:** its Back and Let's go! row sits in a scroll list. A controller tap now scrolls a button into view first, as a finger would.
  - **Scrapbook:** at TV size its body ran off the screen, so Close was unreachable. The body now scrolls between the heading and the buttons. This was written for this lane; the r21 lane met the same problem on a phone.

## No keyboard on a TV

The upstream tvOS display server has no virtual keyboard, and keyboard input is unsupported. So the TV build offers no text field:

- **Toy box search** is hidden. The category tabs still browse every item.
- **Join (Play with friends)** uses only the town the app was prepared with: address and invite are injected on the Mac from the private deployment config.
  - The screen says "Your town is ready to join." and never shows the address, so it never ends up in screenshots.
  - Without a prepared town, Join is off and the screen says why.
  - Playing alone and hosting still work.
- **iPhone and iPad keep every text field.** `TvMode.can_type()` is false only on a TV.

## Photos

- The iOS Photos plugin does not exist on tvOS. `photo_library.gd` already answers "local" off iOS, so a camera photo stays in the game's scrapbook and the Photos dialogs never show.
- The game's camera and the scrapbook are unchanged.

## Saving on a TV

**What Apple guarantees** (Apple TV Programming Guide):

- "Your app can only access 500 KB of persistent storage that is local to the device (using the NSUserDefaults class). Outside of this limited local storage, all other data must be purgeable by the operating system when space is low."
- Cache data "may be deleted" when space is low and the app is not running.
- UserDefaults warns at 512 KiB and terminates the app at 1 MiB or more.

`user://` on tvOS (`Library/Caches/GodotApp`) is therefore writable **staging**. It survives a restart, but a purge may delete it.

### The design (`game/scripts/core/durable.gd`, `tv/native/lantern_defaults`)

1. **Files as everywhere else.** The game keeps writing its files to `user://`. No game path changed, and iPhone, iPad, desktop and the server do none of what follows.
2. **Checked copies.** On a TV, four small progress files also get a checked copy in UserDefaults through the tvOS-only engine module `LanternDefaults`:

   | File | Name | Largest copy |
   |---|---|---|
   | `settings.cfg` | `settings` | 16 KiB |
   | `blueprints.json` | `blueprints` | 48 KiB |
   | `town_solo.json` | `town_solo` | 176 KiB |
   | `town_hosted.json` | `town_hosted` | 176 KiB |

   A copy is `lld1`, the raw size (u32), the SHA-256 of the raw bytes, then the deflated bytes.
3. **A whole-store budget.** Before every write, the module serializes the whole candidate domain exactly, with every key and value plus the new value, as a binary property list. It refuses above **384 KiB**, leaving the domain as it was.
4. **Only valid content is copied.** A town must load in the town model, every blueprint must pass the blueprint rules (`Blueprints.usable`), and settings must parse with a valid device id. An invalid file is never copied over a good copy.
5. **When copies are made:**
   - after every successful town save (`Session.save_now`, which covers every Session save);
   - when settings or blueprints change, noticed by their SHA-256 within a second;
   - when the app pauses, loses focus or closes.
6. **At launch,** before anything reads them (`I18n._ready`), a missing or invalid file comes back from a copy that unpacks to exactly its recorded size and SHA-256 and holds valid content. A valid file always wins, because a copy can only lag behind it. Inflating is bounded: the recorded size must be between 1 byte and 8 MiB.
7. **Failures are said, never silent:**

   | Status | Meaning |
   |---|---|
   | `too_big`, `no_room`, `failed`, `unavailable` (no module) | The last good copy stays. The child is told "This TV cannot keep this town safely. It may be lost when the TV needs space." |
   | `damaged` (the copy cannot be used and there is no valid file) | "This TV's safe copy of your town was damaged, so it could not be brought back." |
   | `restore_failed` (a good copy could not be written back) | The copy is kept and never overwritten that session, so a fresh town cannot replace it. "Your town's safe copy could not be brought back right now. It is kept for next time." |
   | `restored` | "Your town was brought back from this TV's safe copy." |

8. **Photos and stories** are media, too big for this store. They stay in the purgeable cache, and the TV scrapbook says: "Photos and stories on this TV may be removed when the TV needs space."
9. **Online towns** are kept by the server, as before.

## Brand art

`tv/brand/make_brand.py` draws the Apple TV layered app icon and the Top Shelf images from the shapes and palette of `game/icon.svg`: the green field, the round hill and the golden lantern. They are original. `game/tests/tv_brand_rasterize.gd` renders the 13 PNGs at Apple's sizes and checks their alpha:

- app icon at 400 x 240 and 800 x 480; App Store icon at 1280 x 768;
- Top Shelf at 1920 x 720 and 3840 x 1440; Top Shelf Wide at 2320 x 720 and 4640 x 1440.

## Checks

- **Unit:**
  - `test_tv_controller`: deadzone, the Nintendo and standard mappings, Swap A and B, labels, B safety, the TV switch;
  - `test_tv_durable`: with the stand-in module `tests/fake_defaults.gd`, covering round trip, a purge, invalid-but-readable files, eight kinds of damaged copy, too big, the exact whole-store refusal leaving the store unchanged, settings and blueprint rules, malformed blueprint entries, a same-length edit in the same second, a failed restore keeping the copy, and the notices.
- **`tests/tv_tour.gd`:** every step through simulated controller events, failing fast at the first broken case.
  - **main phase:** menus, the TV join screen, walking and the deadzone, the camera, a dialog that holds the world still, the context action, the camera photo and the scrapbook, Decorate, B safety, Swap A and B, six languages, disconnect and reconnect, and a storage write;
  - **`reopen`:** after a relaunch;
  - **`defaults` / `defaults_restart`:** on the TV only, the native module with synthetic files and `lantern.test.*` names only, then exact cleanup. `--fake-defaults` is an EC2 dry run with the stand-in.
- **Results:** a small `user://tv_tour_result.json`, and screenshots to `--shots=user://tv_shots` on the device.
