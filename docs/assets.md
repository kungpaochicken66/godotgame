# Asset Provenance and Licenses

Every asset that ships in `game/` is listed here. Most models, the icons and the sound effects are generated from code in this repository. The stored asset files are the fonts, the music loop, and 140 modeled GLBs (10 pilot-10 and 130 release r1), whose builders and manifests are versioned in `art/`.

| Asset | Path | Source | License | Attribution |
|---|---|---|---|---|
| Background music "Meadow Lanterns" | `game/assets/audio/meadow_lanterns.wav` | Original composition written for this project and rendered by `scripts/compose_music.py` from synthesized sine and triangle tones. No samples, recordings, loops or existing songs were used. | Original work created for this project. It contains no third-party material, so the project owner may redistribute and relicense it. Suggested: CC0 1.0 | None required |
| Sound effects (place, pop, tap, bell, lantern, photo) | generated at runtime in `game/scripts/autoload/sfx.gd` | Original synthesized tones | Same as the project source | None required |
| 3D models, characters, animals, icons | generated in `game/scripts/art/` and `game/scripts/ui/ui_kit.gd` | Original procedural code | Same as the project source | None required |
| Modeled furniture, pilot-10 v1 (scallop chair, cozy round table, scallop bed, writing desk, open shelf, curved counter, desk lamp, blooming flower pot, wall clock, bird mobile) | `game/assets/models/*.glb` (all ten placeable); all ten with builders, manifests and the modeling skill in `art/pilot-10-v1/` | Original procedural geometry by the project's modeling lane, built with `art/pilot-10-v1/rebuild.sh` (rebuild verified byte-identical). Nookipedia item icons and metadata were used only as function and footprint references and are **not** shipped. | Original work created for this project | None required |
| Modeled furniture and decorations, release r1 (130 items: furniture, small decorations and table-top food, models and toys, wall clocks, paintings, wreaths and other wall items) | `game/assets/models/<asset_id>.glb` (listed in `art/production-r1/RELEASE_MANIFEST.json`); frozen batch records, builders and the modeling skill in `art/production-r1/` | Original procedural geometry by the project's modeling lane (Godot 4.7.2 builders, frozen hash-listed batches). Nookipedia item icons and metadata were used only as references for function, footprint and dominant colors and are **not** shipped; display names are original generic names, and in-game brand marks and franchise items were not reproduced. Eight wall items ship as version 2 (origin recentered, geometry unchanged). | Original work created for this project | None required |
| Nunito (Latin UI font) | `game/assets/fonts/Nunito-Variable.ttf` | Google Fonts repository, `ofl/nunito` | SIL Open Font License 1.1 (`NUNITO-OFL.txt`) | Copyright 2014 The Nunito Project Authors |
| M PLUS Rounded 1c Bold, subset (Japanese) | `game/assets/fonts/MPLUSRounded1c-Bold-subset.ttf` | Google Fonts, `ofl/mplusrounded1c`, subset by `scripts/build_fonts.py` | SIL OFL 1.1 (`MPLUSROUNDED1C-OFL.txt`) | Copyright 2016 The Rounded M+ Project Authors |
| Noto Sans SC, subset (Simplified Chinese) | `game/assets/fonts/NotoSansSC-subset.ttf` | Google Fonts, `ofl/notosanssc`, fixed at weight 700 and subset by `scripts/build_fonts.py` | SIL OFL 1.1 (`NOTOSANSSC-OFL.txt`) | Copyright 2014-2021 Adobe, with Reserved Font Name "Source" |

## Music details

- **Composition:** 16 bars in F major at 84 BPM, 45.71 s per loop. Melody, chords (F, Dm, B♭, C, Am, Gm, Csus) and arrangement are written out in `scripts/compose_music.py`.
- **Instruments:** a kalimba-like lead (sine with soft partials), a harp arpeggio, a slow pad and a soft bass, plus a quiet bell every four bars. The mix uses a gentle convolution reverb and a low-pass.
- **Seamless loop:** notes, reverb and filtering are computed circularly, so the end of the file flows into its start. The game loops the whole file sample-exactly (`AudioStreamWAV` forward loop).
- **Format:** 24 kHz stereo 16-bit PCM WAV, peaking at −6 dBFS. WAV was chosen deliberately: a Vorbis encode added 503 samples of padding at the end, which would click at every loop. Godot compresses the WAV when it imports it.
- **Validation:** `python3 scripts/check_audio.py` checks format, exact loop length, headroom, loudness (about −20 dBFS RMS), DC offset, gaps, and that the jump across the seam is no larger than an ordinary step in the music. These checks are objective, but nobody has listened to the music in this environment (there is no audio device here). Listen on a device before release.
- **Reproduce:** `tools/venv/bin/python scripts/compose_music.py` (needs numpy in the project-local venv).

## Not used

The Nookipedia and Animal Crossing reference images (including the modeling lane's 639-image reference bundle), any Peppa Pig material, and any third-party models are **not** shipped. The concept images in `design/` are generated design references for the browser preview, not game assets. The modeling lab under `tools/` is git-ignored and owned by a separate lane. Only its reviewed, curated output is versioned, in `art/pilot-10-v1/` (see `INTEGRATION.md` there for exactly what was copied and what was excluded) and `art/production-r1/` (see its `README.md`). Built clothing (wearables) is not shipped in release r1.
