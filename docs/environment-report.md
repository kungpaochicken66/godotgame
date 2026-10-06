# Development Environment Report

Assessed on 2026-10-06 on the project EC2 host. These are facts observed here, not assumptions.

## Host

| Item | Observed |
|---|---|
| OS / kernel | Ubuntu 22.04.5 LTS, Linux 6.8.0-1063-aws, x86_64 |
| CPU | 2 vCPU Intel Xeon Platinum 8259CL @ 2.50 GHz |
| Memory | 1.9 GiB RAM (about 0.6 GiB free while working) + 4 GiB swap |
| Disk | 58 GB root, about 40 GB free |
| GPU | None usable: an emulated "Amazon.com Device 1111" VGA adapter, no `/dev/dri` render node, no Vulkan |
| Display | No physical display. Xvfb and `xvfb-run` are installed; Mesa 23.2 software OpenGL (llvmpipe, LLVM 15) is available |
| Audio | No sound card (ALSA fails); Godot falls back to a dummy audio driver, so sound was never heard |
| Tools | git, Python 3.10, Node 24, curl; outbound HTTPS works. No Godot was installed system-wide |
| Sandbox | Normal user without root. Nothing was installed system-wide and no sandbox restriction was bypassed |

## What was installed (project-local, git-ignored)

- `tools/godot/`: official Godot **4.7.2-stable** Linux x86_64 editor binary (latest stable on 2026-10-06), verified against the release SHA-512 sums.
- `tools/godot-home/`: Godot editor data/config/cache, redirected through XDG variables by `scripts/godot.sh`, so nothing is written to `~/.local` or `~/.config`. It also holds the iOS export template (`ios.zip`) extracted from the SHA-512-verified 4.7.2 template archive.
- `tools/venv/`: Python venv with fontTools, used only to subset fonts.
- `tools/fonts-src/`: original OFL fonts from the Google Fonts repository.

`scripts/setup_tools.sh` reproduces all of this.

## Capability matrix

| Work | Possible here? | Evidence |
|---|---|---|
| Write and organize the Godot project, GDScript and data | Yes | `game/` |
| Headless import, script compilation, unit tests | Yes | `godot --headless` |
| Headless dedicated multiplayer server | Yes | `--server` mode |
| Multiplayer with several real client processes over loopback | Yes | `scripts/net_test.py` |
| Rendered 3D game with automated screenshots | **Yes, slowly**, with the Compatibility (OpenGL 3) renderer on llvmpipe under Xvfb | `game/tests/capture_tour.gd`; images in `docs/screenshots/` |
| Forward+ / Mobile renderers (Vulkan/Metal) | No (no Vulkan driver); Godot falls back to Compatibility | startup log |
| Interactive editor GUI used by a person | Not practical: no display or remote desktop, and software rendering of the editor would be very slow | — |
| Real touch input, multitouch, pinch | No; only emulated mouse events from scripts | — |
| Performance / frame-rate measurement relevant to iPad | No; llvmpipe timing says nothing about Apple GPUs | — |
| iOS export (Xcode project / .ipa) | **No.** Official Godot 4.7 docs: "You must export for iOS from a computer running macOS with Xcode installed." See below for what a Linux export attempt showed | [Exporting for iOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html) |
| Code signing, provisioning, TestFlight, installing on an iPad | No: needs a Mac, Xcode, an Apple Developer membership (Team ID) and a device | — |
| Public multiplayer server across home networks | Not without provisioning hosting, DNS, TLS and opening ports, none of which was authorized | [multiplayer.md](multiplayer.md) |

## Rendering finding

With Mesa llvmpipe and Godot's Compatibility renderer, a **shadow-casting** DirectionalLight combined with any ambient light produced a strongly over-bright image (grass `#a9d27f` rendered as about `#d9ffa5`). The same light without shadows, and the ambient light alone, added up as expected. Measured with a probe scene during development:

| Sun energy | Ambient | Shadows | Lit grass pixel |
|---|---|---|---|
| 0.9 | 0.2 | off | `#9fc67a` (expected) |
| 0.9 | 0.2 | on | `#d9ffa5` (blown out) |

This may be specific to llvmpipe, so it is **not** evidence about iPad behavior. The game uses soft blob shadows instead of real-time shadows, which also suits the simple toy look and is cheaper on mobile GPUs. Re-test real-time shadows on an iPad before deciding to enable them.

## Renderer choice

The project uses the **Compatibility** renderer on all platforms (`project.godot`). This keeps what was inspected here identical to what ships, and the art uses no features that need Forward+ or Mobile. Godot recommends the Mobile renderer (Metal) for mobile platforms; switching is a one-line project setting change once someone can compare both on a real iPad.

## What needs a Mac, Xcode, signing or a real iPad

1. Install Godot 4.7.2 and its export templates on a Mac with current Xcode.
2. Set a real bundle identifier and the App Store Team ID in `game/export_presets.cfg` (currently placeholders: `org.example.lanternlane`, empty Team ID).
3. Export the Xcode project, build, sign and run on an iPad. Then check touch targets, pinch zoom, performance with about 300 items, memory, suspend/resume saving, and CJK font rendering.
4. Distribution (TestFlight) requires an Apple Developer Program membership; this was not purchased.
