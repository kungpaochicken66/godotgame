# Asset Provenance and Licenses

Every asset that ships in `game/` is listed here. Most models, the icons and the sound effects are generated from code in this repository. The stored asset files are the fonts, the music loop, and 140 modeled GLBs (10 pilot-10 and 130 release r1), whose builders and manifests are versioned in `art/`.

| Asset | Path | Source | License | Attribution |
|---|---|---|---|---|
| Background music "Meadow Lanterns" | `game/assets/audio/meadow_lanterns.wav` | Original composition written for this project and rendered by `scripts/compose_music.py` from synthesized sine and triangle tones. No samples, recordings, loops or existing songs were used. | Original work created for this project. It contains no third-party material, so the project owner may redistribute and relicense it. Suggested: CC0 1.0 | None required |
| Sound effects (place, pop, tap, bell, lantern, photo) | generated at runtime in `game/scripts/autoload/sfx.gd` | Original synthesized tones | Same as the project source | None required |
| 3D models, characters, animals, icons | generated in `game/scripts/art/` and `game/scripts/ui/ui_kit.gd` | Original procedural code | Same as the project source | None required |
| Modeled furniture, pilot-10 v1 (scallop chair, cozy round table, scallop bed, writing desk, open shelf, curved counter, desk lamp, blooming flower pot, wall clock, bird mobile) | `game/assets/models/*.glb` (all ten placeable); all ten with builders, manifests and the modeling skill in `art/pilot-10-v1/` | Original procedural geometry by the project's modeling lane, built with `art/pilot-10-v1/rebuild.sh` (rebuild verified byte-identical). Nookipedia item icons and metadata were used only as function and footprint references and are **not** shipped. | Original work created for this project | None required |
| Modeled furniture and decorations, release r1 (130 items: furniture, small decorations and table-top food, models and toys, wall clocks, paintings, wreaths and other wall items) | `game/assets/models/<asset_id>.glb` (listed in `art/production-r1/RELEASE_MANIFEST.json`); frozen batch records, builders and the modeling skill in `art/production-r1/` | Original procedural geometry by the project's modeling lane (Godot 4.7.2 builders, frozen hash-listed batches). Nookipedia item icons and metadata were used only as references for function, footprint and dominant colors and are **not** shipped; display names are original generic names, and in-game brand marks and franchise items were not reproduced. Eight wall items ship as version 2 (origin recentered, geometry unchanged). | Original work created for this project | None required |
| Wearables (434 GLBs) | `game/assets/wearables/*.glb`, catalog `game/data/wearables.json` | The modeling lane's frozen, hash-verified batches listed in [wearables.md](wearables.md) (accepted in r16c) | As recorded for those batches; unchanged by the TV lane | None required |
| Apple TV brand art: layered app icon (back, middle, front) and Top Shelf images (TV candidate) | `tv/brand/src/*.svg` (sources), `tv/brand/png/*.png` (13 renders), `tv/brand/png/manifest.json` (SHA-256) | Original, drawn from basic shapes in `tv/brand/make_brand.py` after the game's own `game/icon.svg` (palette and lantern), rendered by `game/tests/tv_brand_rasterize.gd` | Same as the project source | None required |
| Three.js 0.186.1 (the web city's renderer) | `game/web_city/vendor/three.core.js`, `game/web_city/vendor/three.module.js` | The `three` package 0.186.1 from the npm registry (`build/` files, unmodified); the tarball's npm integrity value `sha512-blFeqb49wRCSGUGj7gtpfnSGHy2lwDk94RhUmS1c/hTby70kvChbWpkJ4Pm1390LqzzvTmzgXKHPEafJwCb8jA==` was checked at download | MIT (`game/web_city/vendor/THREE_LICENSE.txt`) | Copyright © 2010-2026 three.js authors |
| The web city's page and data | `game/web_city/` (except `vendor/`) | Original code for this project; `data/` is exported from the project's own city builder by `game/tests/web_city/export.gd` | Same as the project source | None required |
| LanternDefaults native module (TV candidate) | `tv/native/lantern_defaults/` | Original Objective-C++ written for this project; uses Godot Engine headers (MIT) and Apple Foundation | Same as the project source | None required |
| Nunito (Latin UI font) | `game/assets/fonts/Nunito-Variable.ttf` | Google Fonts repository, `ofl/nunito` | SIL Open Font License 1.1 (`NUNITO-OFL.txt`) | Copyright 2014 The Nunito Project Authors |
| M PLUS Rounded 1c Bold, subset (Japanese; the TV candidate's subset adds the characters of its new strings, rebuilt with `scripts/build_fonts.py`) | `game/assets/fonts/MPLUSRounded1c-Bold-subset.ttf` | Google Fonts, `ofl/mplusrounded1c`, subset by `scripts/build_fonts.py` | SIL OFL 1.1 (`MPLUSROUNDED1C-OFL.txt`) | Copyright 2016 The Rounded M+ Project Authors |
| Noto Sans SC, subset (Simplified Chinese; rebuilt the same way in the TV candidate) | `game/assets/fonts/NotoSansSC-subset.ttf` | Google Fonts, `ofl/notosanssc`, fixed at weight 700 and subset by `scripts/build_fonts.py` | SIL OFL 1.1 (`NOTOSANSSC-OFL.txt`) | Copyright 2014-2021 Adobe, with Reserved Font Name "Source" |

## Music details

- **Composition:** 16 bars in F major at 84 BPM, 45.71 s per loop. Melody, chords (F, Dm, B♭, C, Am, Gm, Csus) and arrangement are written out in `scripts/compose_music.py`.
- **Instruments:** a kalimba-like lead (sine with soft partials), a harp arpeggio, a slow pad and a soft bass, plus a quiet bell every four bars. The mix uses a gentle convolution reverb and a low-pass.
- **Seamless loop:** notes, reverb and filtering are computed circularly, so the end of the file flows into its start. The game loops the whole file sample-exactly (`AudioStreamWAV` forward loop).
- **Format:** 24 kHz stereo 16-bit PCM WAV, peaking at −6 dBFS. WAV was chosen deliberately: a Vorbis encode added 503 samples of padding at the end, which would click at every loop. Godot compresses the WAV when it imports it.
- **Validation:** `python3 scripts/check_audio.py` checks format, exact loop length, headroom, loudness (about −20 dBFS RMS), DC offset, gaps, and that the jump across the seam is no larger than an ordinary step in the music. These checks are objective, but nobody has listened to the music in this environment (there is no audio device here). Listen on a device before release.
- **Reproduce:** `tools/venv/bin/python scripts/compose_music.py` (needs numpy in the project-local venv).

## Not used

The Nookipedia and Animal Crossing reference images (including the modeling lane's 639-image reference bundle), any Peppa Pig material, and any third-party models are **not** shipped. The concept images in `design/` are generated design references for the browser preview, not game assets. The modeling lab under `tools/` is git-ignored and owned by a separate lane. Only its reviewed, curated output is versioned, in `art/pilot-10-v1/` (see `INTEGRATION.md` there for exactly what was copied and what was excluded) and `art/production-r1/` (see its `README.md`). Built clothing (wearables) is not shipped in release r1.

## Candidate `puzzle-rides` (2026-11-13)

No asset file was added. The ten new things (treasure chest, puzzle key, picture dial, four clue cards, cart station and cart, straight and curved cart rail) are original procedural code in `game/scripts/art/props_puzzle.gd`, under the project's own terms like every other code-built thing. They reuse existing sounds (`pop`, `tap`, `lantern`). The two CJK font subsets were rebuilt with `scripts/build_fonts.py` from the same sources and licenses for the 46 new strings (the repository check now counts 1513 covered characters, 8 more than before); nothing else about the fonts changed.

## Candidate `town-play` (2026-11-13)

No asset file was added. The Signal rail, Weather bell, Picture board and the cart's trailer are original procedural code in `game/scripts/art/props_puzzle.gd`; a hello's figure is the existing child model made see-through. Existing sounds are reused (`lantern`, `mb_bell`, `tap`, `pop`). The two CJK font subsets were rebuilt with `scripts/build_fonts.py` for 46 more strings (the repository check counts 1523 covered characters).

## Candidate `first-steps` (2026-11-13)

No asset file was added. The six new guide pictures are original SVG drawn in code in `game/scripts/ui/guide_art.gd`, like the eight existing ones. The two CJK font subsets were rebuilt with `scripts/build_fonts.py` for 59 more strings (the repository check counts 1529 covered characters).

## Candidate `zoo` (2026-11-16)

No asset file was added. The fourteen zoo animals (`game/scripts/art/zoo_animal.gd`), the zoo's structures, stations, toys and tram stop (`game/scripts/art/props_zoo.gd`) and the new icons (`tram`, `paw` in `game/scripts/ui/ui_kit.gd`, the guide picture in `guide_art.gd`) are original procedural code. The five new sounds (`tram`, `rawr`, `hoot`, `chomp`, `whoosh`) are tones synthesized in `game/scripts/autoload/sfx.gd`. The optional concept images under `build/dual-host/zoo-concepts/` were never approved and are not shipped. The two CJK font subsets were rebuilt with `scripts/build_fonts.py` for the new strings (1609 and 1582 characters).

## Candidate `zoo` r2 (2026-11-16): six Everything Library animals

Six animal models are added under `game/assets/models/zoo_everything/`: `everything_panda.glb`, `everything_lion.glb`, `everything_elephant.glb`, `everything_giraffe.glb`, `everything_zebra.glb` and `everything_penguin.glb`, with the license notice in `game/assets/models/zoo_everything/LICENSE-NOTICE.md`. Their SHA-256 values are recorded in `art/everything-zoo-r1/godot-pack/manifests/`.

- **Source:** "Everything Library – Animals 0.2" © David OReilly, licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0) licence, https://creativecommons.org/licenses/by/4.0/.
- **How they were made:** exported from the Everything Library animals with Blender 5.2.2 by `scripts/blender/everything_export.py` (handoff `script-h3`), following `art/everything-zoo-r1/spec.json`. Each animal was extracted to its own file, scaled, re-oriented, given vertex colours in `colorSet1` only, one matte material, UVs removed, and triangulated.
- **Runtime use:** the game skins these models at runtime in `game/scripts/art/zoo_skin.gd` without changing their vertices or colours.
- **Credit:** the in-game credit is on the scrapbook's "Zoo friends" page.
- **Attribution notice:** `game/assets/models/zoo_everything/LICENSE-NOTICE.md` (copied byte-identical from `art/everything-zoo-r1/LICENSE-NOTICE.md`).

## Candidate `city` r1 (2026-11-16): the miniature city district

No asset file was added. The city's buildings, interiors, signs (a 5 x 5 voxel alphabet), the Ferris wheel, vehicles and walkers are original procedural code in `game/scripts/art/props_city.gd` and `game/scripts/world/city_world.gd`, with materials that use vertex colours only. The asset inventory is `build/dual-host/city/asset-inventory.md`; no third-party model, texture, font or sound is used, so nothing new needs attribution. The two CJK font subsets were rebuilt with `scripts/build_fonts.py` for the new strings (1629 and 1602 characters).

## Candidate `city` r2 (2026-11-17): colour, people, carousel, buses

No asset file was added. The city's 52 people (`game/scripts/art/city_people.gd`, data in `game/scripts/core/city_people_data.gd`), the carousel, the buses, the new furniture and signs (`props_city.gd`, `city_world.gd`) and the new HUD icons (`look`, `pause` in `ui_kit.gd`) are original procedural code. No third-party model, texture, font or sound is used. The font subsets were rebuilt for the new strings.

## Candidate `city` r3 (2026-11-17): weather

No asset file was added. The rain, wet ground, puddles, night glow, street lamps and light pools (`props_city.gd`, `city_world.gd`), the umbrellas (`city_people.gd`) and the HUD icons `sun`, `rain` and `moon` (`ui_kit.gd`) are original procedural code. The font subsets were rebuilt for the new strings.

