# Mac tvOS packaging helpers

These files preserve the coordinator's actual packaging repairs for the accepted
Apple TV build. They contain no signing configuration, deployment configuration,
player data or built engine. They are not an automatic installer or publisher.

Engine: `stuartcarnie/godot` branch `tvos_platform`, exact revision
`791c358acacd05022e3e8ffc3553e7125dd5fd36` (experimental 4.8-dev).
Apply `engine-791c358.patch` to a clean disposable checkout of that revision.
The scoped Git whitespace attribute preserves unified-diff context prefixes;
the patch itself is verified by applying it to the original engine files.
It links the compiled Swift entry point and uses `Library/Caches/GodotApp` for
writable tvOS staging. This is not durable storage; the game's tvOS-only
LanternDefaults module provides bounded copies of important progress.

The pinned distribution also lacks a debug XCFramework skeleton. Copy
`DebugFramework-Info.plist` to
`misc/dist/apple_embedded_xcode/libgodot.tvos.debug.xcframework/Info.plist`
and create its `tvos-arm64/` directory before building. Only the arm64 device
debug slice was built and verified; release and simulator slices are not claimed.
Build with the accepted candidate's `tv/native` directory as `custom_modules`.

After exporting the Apple TV preset to a disposable `ios/` directory:

```sh
python3 scripts/tvos/fix_storyboard.py /absolute/export/ios
python3 scripts/tvos/install_brand.py /absolute/candidate/source/tv/brand/png /absolute/export/ios
```

The first helper repairs the shared iOS storyboard and unresolved plist
placeholders. The second verifies all 13 source image hashes and dimensions,
then copies the original TV layered icon/top-shelf art and uses it for launch.
Both helpers are byte-identical copies of those used for the accepted r5 build.
The engine patch reproduces the three modified engine files byte-for-byte.

Use the private inventory named by `docs/release-workflow.md` for signing and
device identifiers; never put credentials or export presets in Git. TV packaging
uses Mobile/Metal and excludes the iOS photo plugin; it must not change the iOS
project's renderer. Verify code signature, profile expiry/device coverage,
AppleTVOS/family3, CA92.1 and LanternDefaults linkage, exact PCK identity, and
absence of validation overrides before installation.

Evidence and tested limitations are in `docs/release-status.md`. The Siri Remote
Home-navigation follow-up is separate from this baseline packaging repair.
