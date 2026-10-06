# Handoff — Lantern Lane Godot prototype

Date: 2026-10-06. Nothing has been committed or pushed. All changes are in the working tree, ready for review. Workflow: EC2 code → GitHub → local Mac pull/build.

## What changed

- **New Godot 4.7.2 project in `game/`**. It reimagines the earlier static "Our Little Town" preview as *Lantern Lane* ([design](docs/game-design.md)): the creator decorates a shared town with friends, Cozy Spot arrangements light lanterns on a Wishing Tree, and every built thing can be played on. Highlights:
  - character creator with six appearance options and preset nicknames (no free text);
  - tap-to-walk third-person town with a close, tilted camera that turns and zooms;
  - toy box of 22 free items with ghost placement (green/red ring), drag, turn, 8 paint colors and undo;
  - enterable cottages with dollhouse interiors whose furniture belongs to each house;
  - swing, seesaw, benches, sofa and bed with seats; emotes; a shared evening bell with glowing lamps and fireflies;
  - scrapbook with hints and photos; synthesized sounds; procedural toy-like art;
  - six-language UI with bundled OFL fonts.
- **Multiplayer**: authoritative `Session` autoload (solo / LAN host / client / headless dedicated server) over WebSockets, with locks, seats, a four-player limit, protocol version checks and atomic autosave. Recommended production setup: [docs/multiplayer.md](docs/multiplayer.md).
- **Tooling**: `scripts/setup_tools.sh` (project-local Godot in self-contained mode, venv, fonts), `scripts/godot.sh`, `scripts/test_all.sh`, `scripts/net_test.py`, `scripts/extract_strings.py`, `scripts/build_fonts.py`, and an extended `scripts/check.py`.
- **Docs**: README rewritten; new design, multiplayer and environment documents; requirements register and validation record updated. The browser preview in `design/` is unchanged.
- `game/export_presets.cfg`: generic "iPad" preset with placeholder bundle ID `org.example.lanternlane`, empty Team ID, `export_project_only=true`, targeted device family iPad, minimum iOS 15. The one-off fake Team ID used for the Linux export check was reverted, and its generated output was deleted.

## Run

```sh
scripts/setup_tools.sh                         # once, on Linux (tools/ is git-ignored)
xvfb-run -a scripts/godot.sh --path game       # play on EC2 (software rendering, about 8 fps)
scripts/godot.sh --headless --path game -- --server --port=9080 --bind=127.0.0.1 --save=user://town_server.json
```

On the Mac, open `game/project.godot` in Godot 4.7.2, press Play, or export with the "iPad" preset after setting the bundle ID and Team ID locally.

## Tests (latest results on EC2)

| Command | Result |
|---|---|
| `tools/venv/bin/python scripts/check.py` | PASS: 155 game messages × 6 languages, placeholders, extracted strings, font coverage, English sources, links |
| `scripts/godot.sh --headless --path game -s res://tests/run_tests.gd` | PASS: 2144 checks, 0 failures |
| `python3 scripts/net_test.py` | NET TEST PASS: server + 5 real client processes on loopback, then a restart and persistence check |
| Rendered tour (`scripts/test_all.sh` last step) | TOUR PASS: 25 assertions, screenshots in six languages |
| `scripts/test_all.sh` | Runs all of the above |

Artifacts: curated screenshots in `docs/screenshots/godot/` (including `net_friends.png`, taken from a real three-process networked session). Temporary outputs go to `tools/shots*` and the system temp directory (`lantern-net-*`, `lantern-cap-*` logs).

## Not verified here (and why)

- **Anything on an iPad**: touch feel, pinch zoom (the code handles magnify gestures), real performance, memory, suspend/resume saving, Metal/GLES rendering differences. The EC2 host has no GPU and uses software OpenGL.
- **Cross-home play**: no hosted server, TLS or domain. Network tests ran over loopback on one machine.
- **Visual quality acceptance**: screenshots come from a software renderer; final art needs the creator's review on the device.
- **Sound**: no audio device here, so the synthesized sounds were never heard.

## Remaining product issues

1. Run on the iPad Air 5: check the Compatibility renderer vs the Mobile renderer, the safe-area handling (`UI.fit_safe_area`, active only on mobile and untested), and touch target comfort.
2. Town server hosting, `wss://` TLS, a per-town invite code, and a parental gate before any public address exists ([multiplayer.md](docs/multiplayer.md)).
3. Translations need native-speaker review. Specific choices to review: the Chinese "Sunny" nickname, inherited from the preview, means "little grain" and reads oddly as a color name, the es/fr/de nicknames are literal nouns, "Swing" is a noun-style button label, and "Host on this device" is technical wording.
4. Photos are saved to the app's user folder, but the scrapbook lists only this session's photos. No export to the Photos app.
5. Real-time shadows are off (blob shadows only) because of a software-renderer artifact. Re-test on device.
6. Placement uses circular footprints. Long items (bed, bench, sofa) can sit slightly closer to walls than their shape suggests.
7. Thumbnails render at startup (about 22 frames). On slow devices the toy box may briefly show text-only cards.
8. Art is placeholder-quality procedural geometry: no animation clips, and simple faces. The creator's own designs could be added as new builders in `game/scripts/art/props.gd` and new spots in `game/scripts/core/cozy_spots.gd`.
9. Accessibility: no screen-reader labels on 3D items yet; tooltips only on icon buttons.
