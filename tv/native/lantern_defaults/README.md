# LanternDefaults (tvOS only)

A small custom engine module that gives Lantern Lane on Apple TV a bounded, persistent store for its progress. The design is in [design/tv-controller.md](../../../design/tv-controller.md), "Saving on a TV".

This module also holds **`LanternRemote`** (`lantern_remote.h/.mm`): the Siri Remote's Menu button. It counts Menu presses of the Siri Remote only, through the Game Controller framework (`take_menu_presses()`). It switches the root `GCEventViewController`'s `controllerUserInteractionEnabled` (`set_system_back(on)`, `arm_system_back(seconds)`: at most 10 s, ended natively by any other UIKit press; `is_system_back()`), so that at the game's title the next Menu press returns to the Apple TV Home screen. See [design/tv-controller.md](../../../design/tv-controller.md), "The Siri Remote's Menu".

## Why it exists

- **Apple TV Programming Guide:** an app gets only 500 KB of persistent local storage (NSUserDefaults). Every other file, including `user://` (`Library/Caches/GodotApp` on tvOS), may be deleted when the TV needs space and the app is not running.
- **UserDefaults:** warns at 512 KiB and terminates the app at 1 MiB or more.

## What it does

The Engine singleton `LanternDefaults` offers:

| Method | Result |
|---|---|
| `put_blob(name, data) -> int` | `OK`, `ERR_INVALID_PARAMETER` (name), `ERR_INVALID_DATA` (empty or over 192 KiB), `ERR_OUT_OF_MEMORY` (the whole domain would pass 384 KiB: **nothing is written**), `FAILED` (not stored, or the read-back differs) |
| `get_blob(name) -> PackedByteArray` | Empty if missing |
| `erase_blob(name) -> bool` | Removes one name |
| `domain_bytes() -> int` | Exact size of the app's whole persistent domain as a binary property list |
| `candidate_bytes(name, data) -> int` | That size if the value were written |
| `keys(prefix) -> PackedStringArray` | Names starting with `prefix` (the `lantern.` part removed) |
| `budget() -> int` | 393216 |

**Names:** stored as `lantern.` + the name, and limited to `[a-z0-9_.]` with at most 48 characters.

**Budget check:** before every write, the whole candidate domain (every key and value the app has, plus the new value) is serialized exactly as a binary property list, and its length is compared with the budget. This is not an estimate.

**What it stores:** small byte blobs only. The game (`game/scripts/core/durable.gd`) stores checked copies of four progress files, never images.

## Build (Mac, with the pinned tvOS engine source)

The module stays in this candidate; nothing is copied into the engine tree:

```sh
scons platform=tvos target=template_debug arch=arm64 custom_modules=<candidate>/source/tv/native
# (and template_release the same way when needed)
```

`config.py` builds it only for `platform == "tvos"`. iOS and other platforms are unchanged and never contain it. Without the module, the game on a TV says that it cannot keep the town safely.

## Privacy manifest

UserDefaults is a required-reason API. `PrivacyInfo.xcprivacy` here holds the entry: `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1` (the app's own data). Merge it into the exported app's privacy manifest if it is not already there.

## Device check

```sh
--driver=res://tests/tv_tour.gd --tv --phase=defaults            # first launch
--driver=res://tests/tv_tour.gd --tv --phase=defaults_restart    # after relaunching the app
```

The smoke test uses synthetic files under `user://tv_smoke/` and only `lantern.test.*` names. It checks:

- put and get, and the exact budget refusal (the domain is unchanged after it);
- a corrupt copy is never used;
- recovery after the staging file is deleted (as a purge would), and after the file holds invalid content;
- after the relaunch, the copies are still there;
- cleanup: it removes exactly its own names and files.

## Licence

Original code written for Lantern Lane, under the project's licence. It uses Godot Engine headers (MIT) and Apple Foundation.

r11: on arming, `LanternRemote` prints one `[tvOS Menu] armed:` line (the responder chain above the engine controller and the focused item, class names only). The Menu press itself reaches the Home screen only with the engine patch in `tv/engine/`.
