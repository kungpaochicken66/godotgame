# Lantern Lane

A cozy 3D iPad and iPhone game built with **Godot 4.7.2**, in which two to four children decorate a shared town from their own homes. They place three-story cottages, gardens, ponds, swings and furniture (with a decoration on a table top), form **Cozy Spots** that light lanterns on the Wishing Tree, explore a 52 × 44 m countryside with five animal friends, and play in what they build, to a gentle original soundtrack. Eight optional activities invite play without quests or currency: animal wishes, hide-and-seek with a golden acorn, gift bundles, little gardens, a dance party, open-house hearts and guest books, photo ideas and weather. The toy box holds 163 items, 140 of them modeled furniture and decorations (including wall and ceiling items), all free from the start.

- Game design: [docs/game-design.md](docs/game-design.md) · Animal friends: [docs/animals.md](docs/animals.md)
- Object scale and table-top contract: [design/object-scale-and-surfaces.md](design/object-scale-and-surfaces.md)
- Activities A-H: [design/playfulness-proposals.md](design/playfulness-proposals.md) · Model release r1 coverage and next-run guide: [design/model-release-r1.md](design/model-release-r1.md)
- Asset provenance and licenses: [docs/assets.md](docs/assets.md) · Contributing (keep docs current with every change): [CONTRIBUTING.md](CONTRIBUTING.md)
- Apple TV with a game controller (Nintendo Switch Pro; Siri Remote Menu returns to the Home screen at the title): [design/tv-controller.md](design/tv-controller.md) · device results [docs/tv-validation.md](docs/tv-validation.md) · required engine patch [tv/engine/README.md](tv/engine/README.md)
- Handoff (status, tests, remaining issues): [HANDOFF.md](HANDOFF.md)
- Multiplayer approach: [docs/multiplayer.md](docs/multiplayer.md)
- Development environment report: [docs/environment-report.md](docs/environment-report.md)
- Requirements and history: [docs/requirements.md](docs/requirements.md) · Validation record: [docs/validation.md](docs/validation.md)

![Town](docs/screenshots/godot/lantern_celebration.png)

## Repository layout

```text
game/                 Godot project (open game/project.godot)
  scripts/core/       Pure game rules: catalog (scale contract), town model (rooms, table tops,
                      wall/ceiling mounts), Cozy Spots, animal brain, wishes, hide-and-seek,
                      photo ideas, avatars, palette
  scripts/net/        Session (solo, host, client, dedicated server), Animals and Activities autoloads
  scripts/world/      3D town, activity visuals, camera, local player and decorating controller
  scripts/art/        Procedural toy-like models for props and children
  scripts/ui/         HUD, menus, theme/icons, catalog thumbnails
  scripts/autoload/   Localization (six languages), music and settings, synthesized sounds
  assets/audio/       Original music loop (see docs/assets.md)
  assets/models/      140 modeled GLBs: 10 from art/pilot-10-v1, 130 from art/production-r1 (scale baked in)
  locale/             UI catalogs: en, zh-CN, ja, es, fr, de (English is the source)
  assets/fonts/       OFL fonts (Nunito; M PLUS Rounded 1c and Noto Sans SC subsets)
  tests/              Unit/session tests, rendered tour, network bots, probes
  export_presets.cfg  Generic iOS export preset "iPad" for iPhone and iPad (placeholder bundle ID, no Team ID)
art/pilot-10-v1/      Reviewed modeled furniture: GLBs, builders, manifests, modeling skill (rebuild.sh)
art/production-r1/    Release r1 models: release manifest, frozen batch records, builders, skill
design/               Earlier browser design preview, concept art and the object scale contract
docs/                 Design, requirements, validation, environment and multiplayer notes
scripts/              Tool setup, Godot wrapper, test runners, string, font and music tools
```

## Open and run

On a Mac or PC with Godot 4.7.2: open `game/project.godot` and press Play. On this Linux host, use the project-local tools:

```sh
scripts/setup_tools.sh                     # Godot 4.7.2 + Python venv + fonts into tools/ (git-ignored)
scripts/godot.sh --path game               # run the game (needs a display; on EC2 prefix: xvfb-run -a)
scripts/godot.sh --headless --path game -- --server --port=9080   # dedicated town server
```

Touch: tap the ground to walk; tap a door, stairs, swing, bench or animal to use it or say hello; Decorate opens the toy box, and dragging an item onto a table sets it on top. The placement tools jump to the top of the screen when they would cover the item. Desktop controls for testing: click the ground to walk; WASD/arrows to walk; Q/E rotate the view; Z zoom; Space for the context action; R turn, Enter place, Esc cancel, Ctrl+Z undo; keys 1–4 for emotes.

## Tests

```sh
scripts/test_all.sh            # everything (rendered tour needs xvfb-run)
scripts/test_all.sh --quick    # repository checks + headless unit/session tests
```

| Check | Command |
|---|---|
| Repository: locales, placeholders, extracted UI strings, font coverage, English sources, links | `tools/venv/bin/python scripts/check.py` |
| Music loop: format, length, headroom, loudness, seam | `python3 scripts/check_audio.py` |
| Placement tools never cover the item (three screen shapes, real drags) | see `scripts/test_all.sh` (`tests/dock_tour.gd`) |
| Rules, saves and migration, rooms and stairs, table tops, wall/ceiling mounts, scale contract and every modeled GLB, Cozy Spots, animals, activity rules (wishes, gifts, gardens, hearts and visits, photo ideas, hide-and-seek warmth), placement-tool logic, toy box search and filters (with a 2,000-entry test-only fixture), tap disambiguation, music settings, locales, solo session | `scripts/godot.sh --headless --path game -s res://tests/run_tests.gd` |
| Multiplayer with real WebSocket client processes, persistence across server restart | `python3 scripts/net_test.py` |
| Activities with real clients (conflicting starts, late joiner, presents, hearts, restart) | `python3 scripts/net_test.py --activities` |
| Apple TV controller tour (every step by simulated controller events: menus, TV join screen, walk and deadzone, camera, dialogs hold the world, context action, camera photo and scrapbook, Decorate, B safety, Swap A and B, six languages, disconnect, storage; `--phase=reopen` after a relaunch; `--phase=defaults` then `defaults_restart` on the TV for the native save module; result in `user://tv_tour_result.json`) | `scripts/godot.sh --headless --path game -- --driver=res://tests/tv_tour.gd --tv --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv` (device: `--tv --shots=user://tv_shots --tag=atv`) |
| Apple TV brand art (13 PNGs at Apple's sizes from `tv/brand/src`) | `python3 tv/brand/make_brand.py && scripts/godot.sh --headless --path game -s res://tests/tv_brand_rasterize.gd` |
| TV repository checks (all of `check.py` except Markdown links) | `tools/venv/bin/python scripts/tv_check.py` |
| Decorative motion (fan blades, sway, glow; Reduce motion by real taps; frozen-after-toggle pixels; stairs, removal, reload; a timed 17-decoration workload) | `scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/motion_tour.gd --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja` (logic only: `--headless`, `--no-shots --window=2208x1024`) |
| Joining a town above 64 KiB (synthetic 420-item town: whole town arrives unchanged; old 64 KiB server or client buffers fail clearly; the welcome limit refuses clearly; a silent server times out after 20 s; saves keep every item) | `python3 scripts/net_test.py --connect` |
| Animals visiting houses with real clients (invite, same-room view, emote answer, stairs, a late joiner, a disconnect inside, restart) | `python3 scripts/net_test.py --visits` |
| Animals visiting houses through the real UI (card, follow to the door, living room, dance answer, stairs, Say goodbye, back outside) | `scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/visit_tour.gd --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja` (logic only: `--headless`, `--no-shots --window=2208x1024`) |
| Two-seat benches with three real clients (two sit at once on different seats, a third is refused and then takes a freed seat, a disconnect frees a seat, restart) | `python3 scripts/net_test.py --seats` |
| Two-seat benches through the real UI (tap to sit, a friend beside you, full-bench message, Get up, turned sofa and town bench, outfits) | `scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/bench_tour.gd --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja` (logic only: `--headless`, `--no-shots --window=2208x1024`) |
| Pets and cooking with real clients (adopt, follow the right owner, busy stove, serve and eat, owner leaves, restart) | `python3 scripts/net_test.py --pets` |
| Optional town invite and the operator tool (right, wrong, missing invite; reconnect; a holding relay; restart) | `python3 scripts/net_test.py --invites` |
| Rendered tour of the eight activities | `xvfb-run -a -s "-screen 0 1366x1024x24" scripts/godot.sh --path game -- --driver=res://tests/activities_tour.gd --shots=/abs/dir` |
| Rendered end-to-end tour with screenshots in six languages | see `scripts/test_all.sh` |
| Toy box browser (search, no results and reset, placement filters, keyboard, repeated placement, Which one? in a crowded room, Things here), any locales and screen shape | `xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 -- --driver=res://tests/browser_tour.gd --shots=/abs/dir --tag=ipad --locales=en,zh-CN,ja,es,fr,de` (iPhone: `--resolution 2208x1024 --tag=iphone --safe-insets=154,0,154,55`) |

Screenshots from the rendered tests are in `docs/screenshots/godot/`. They come from a software renderer on a headless server. They are not iPad verification or final visual acceptance.

## Languages

English (default), Simplified Chinese, Japanese, Spanish, French and German. Change language from the globe button on the title screen or in game. After changing UI text, run `tools/venv/bin/python scripts/extract_strings.py` to find untranslated strings, and run `scripts/build_fonts.py` to refresh the CJK font subsets.

## Design preview

The earlier browser preview is still available: run `python3 -m http.server 8769 --bind 127.0.0.1` and open `design/index.html`. It is reference material only.
