# Saving photos to the iPhone/iPad Photos library

The in-game camera keeps every picture in the scrapbook. On iPhone and iPad it also asks the system to add the picture to Photos, with **add-only** access (`PHAccessLevelAddOnly`, purpose key `NSPhotoLibraryAddUsageDescription`). The game never reads the library. The message "Saved to Photos and the scrapbook." appears only after the system's completion handler reports success. After a denial the child sees **Open Settings** and **Try again**; after a failure, **Try again**. Desktop and other platforms keep saving to the game's own folder only.

| Part | Path |
|---|---|
| Native plugin (Objective-C++, Godot iOS plugin format) | `game/ios/plugins/photo_library/` (`photo_library.gdip`, `src/photo_library.h`, `src/photo_library.mm`, `build.sh`) |
| Game wrapper (answers `saved`, `denied`, `failed`, or `local` without the plugin) | `game/scripts/ui/photo_library.gd` |
| Camera flow and messages | `game/scripts/main.gd` (`_take_photo`, `_save_to_photos`), `game/scripts/ui/hud.gd` (`photo_result`) |
| Localized purpose string (six languages, from `game/locale/*.json`) | `scripts/ios_photo_purpose.py` |
| Export | `game/export_presets.cfg`: `plugins/PhotoLibrary=true`; `privacy/photolibrary_usage_description` stays empty (it would request full library access) |

## Mac steps (EC2 cannot build, sign or run this)

1. Engine source at the exact tag (commit `ed1daf0bf001b61586d9930840f2f1394092c079`):
   `git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git godot-4.7.2`
2. Build the plugin: `game/ios/plugins/photo_library/build.sh /path/to/godot-4.7.2`. It asks SCons only for the generated headers (exactly `core/version_generated.gen.h`, `core/disabled_classes.gen.h`, `core/object/gdvirtual.gen.h`, `core/extension/gdextension_interface.gen.h`, the minimum confirmed on a clean 4.7.2 source; override with `GODOT_GEN_TARGETS`) and fails on any SCons or compile error. It produces **`photo_library.debug.xcframework`** (compiled with `DEBUG_ENABLED`, matching the debug export template's `ClassDB` binder) and **`photo_library.release.xcframework`**, each for device arm64 and simulator arm64 (iOS 15.0+), checks the binder symbol in each (`nm` output saved to `build/<variant>/symbols.txt`, then searched; the release library must not reference the debug binder), and removes any plain `photo_library.xcframework`. Godot's exporter uses `<binary>.debug.xcframework` for `--export-debug` and `<binary>.release.xcframework` for `--export-release` only when both exist and the plain `binary` named in the `.gdip` does not.
3. Export the iOS project (preset "iPad", `export_project_only=true`), debug and release.
4. Run `python3 scripts/ios_photo_purpose.py <exported project folder>` on each export. It removes the empty `NSPhotoLibraryUsageDescription` that Godot always writes, keeps `NSPhotoLibraryAddUsageDescription`, fails unless only the add-only key remains, writes the purpose string into `en`, `zh-Hans`, `ja`, `es`, `fr`, `de` `.lproj/InfoPlist.strings`, and registers all six in `project.pbxproj` (file references, the `InfoPlist.strings` variant group, `knownRegions`). Running it again changes nothing. Its test, `python3 scripts/test_ios_photo_purpose.py`, runs it on an unmodified real export (`scripts/fixtures/ios_export/`).
5. Build in Xcode (debug and release) and confirm: the app bundle has the six `*.lproj/InfoPlist.strings`, the Info.plist has only `NSPhotoLibraryAddUsageDescription`, and `Photos.framework` is linked. Sign with the personal team as usual.
6. Install on a device only when the user authorizes it.

## Device acceptance checklist (pending; never claimed from EC2)

| # | Step | Expected |
|---|---|---|
| 1 | First photo on a fresh install | The system asks for permission to add photos, showing the purpose string in the device language |
| 2 | Allow | "Saved to Photos and the scrapbook." only after the prompt is answered; the picture is in Photos (Recents) |
| 3 | Don't Allow, take a photo | "Photos access is off" with Not now / Open Settings / Try again; the picture is still in the scrapbook |
| 4 | Open Settings, allow, return, Try again | Saved; the message appears once |
| 5 | Desktop build | "Photo saved to the scrapbook" as before; no Photos message |
