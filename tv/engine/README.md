# Engine patch for the Apple TV build (Siri Remote Menu to the Home screen)

`0001-tvos-menu-presses-to-uikit.patch`: one engine file, `drivers/apple_embedded/godot_view_controller.mm`, tvOS only (`#ifdef TVOS_ENABLED`).

**Engine:** `stuartcarnie/godot` branch `tvos_platform`, revision `791c358acacd05022e3e8ffc3553e7125dd5fd36`. The patch does not overlap the coordinator's `engine-791c358.patch` (that one changes only `platform/tvos/`), so the two can be applied in either order.

## Why

The pinned `GDTViewController.pressesBegan` never passes a press to `super`. Its `pressesEnded` passes only the end of a Menu press to `super`, and only when `SceneTree.quit_on_go_back` is set. Apple's `UIResponder.pressesBegan` documentation says to forward unhandled presses to `super`. UIKit therefore may never see a whole Menu press, and the Apple TV did not return to the Home screen (r10, device check e).

This is the likely cause, **not a proven one**. A press might also never reach this view controller (the window's root is a SwiftUI hosting controller). The log lines below tell the two cases apart.

## What it changes (tvOS only)

- **`pressesBegan`:** a Menu press goes to `super` when `quit_on_go_back` is set (the game sets it only while Home is armed at its title). Every other press is unchanged.
- **`pressesEnded`:** a Menu press goes to `super` when its beginning did, or (as before) when `quit_on_go_back` is set. Otherwise it is unchanged: the game gets a go-back request.
- **`pressesCancelled`:** new override with the same forwarding as UIKit's default, clearing the flag only.
- **Logging:** a line `[tvOS Menu] began: forwarded to UIKit` and a line `[tvOS Menu] ended: forwarded to UIKit (…)`, only for forwarded Menu presses.

No private API, no programmatic quit: UIKit decides what a Menu press does.

## Apply

Expected hashes of `drivers/apple_embedded/godot_view_controller.mm`:
- before: SHA-256 `37571027e7c6a30d2ddd8163df5ce68f87898ced88f51ad94e93f70ca3678e1c` (git blob `985b22851184b099af182540cf7cfc7da67996be` in `791c358`);
- after: `6ef55d73bec5571c67e616ad561b6782d36bb384ecb2dd19662f7410ca0b5731`.

**The after-hash is the only proof that the patch was applied.** Check it in every case, and never rely on an exit status alone.

**Engine as its own Git checkout of 791c358** (its top-level directory is the engine root):

```sh
cd <engine>
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"   # must be the engine's own repository
git apply --check -v <candidate>/source/tv/engine/0001-tvos-menu-presses-to-uikit.patch
git apply -v <candidate>/source/tv/engine/0001-tvos-menu-presses-to-uikit.patch
shasum -a 256 drivers/apple_embedded/godot_view_controller.mm   # must be 6ef55d73...5731
```

**Engine extracted from a tar** (no `.git` of its own; possibly inside another repository):

Do **not** use `git apply` here. Inside an enclosing repository it takes paths relative to that repository's root. It skips a file outside the current directory, prints "Skipped patch", and still exits 0. Use `patch` instead:

```sh
cd <engine>
shasum -a 256 drivers/apple_embedded/godot_view_controller.mm   # must be 37571027...8e1c
patch -p1 --forward --batch --dry-run < <candidate>/source/tv/engine/0001-tvos-menu-presses-to-uikit.patch
patch -p1 --forward --batch < <candidate>/source/tv/engine/0001-tvos-menu-presses-to-uikit.patch
shasum -a 256 drivers/apple_embedded/godot_view_controller.mm   # must be 6ef55d73...5731
```

The dry run must report the one file as patched, with no rejected or offset hunks.

**Either way:** the binary built afterwards must contain the strings `[tvOS Menu] began: forwarded to UIKit` (engine) and `[tvOS Menu] armed:` (native module). Otherwise the build used stale objects.

Then apply the coordinator's `engine-791c358.patch` as before, and build with `custom_modules=<candidate>/source/tv/native`. This needs a rebuilt engine template, not only a new module.
