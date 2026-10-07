# b001-housewares-1 (frozen 2026-10-06T15:30:29Z)

Assets: 15. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| celebratory_arch_gold | 2021 celebratory arch | 1.94 × 1.746 × 0.356 | 1.343 | ground | large | 5400 | 3 | 0.4 | False | – | – |
| celebratory_arch_teal | 2022 celebratory arch | 1.94 × 1.746 × 0.356 | 1.343 | ground | large | 5400 | 3 | 0.4 | False | – | – |
| cash_machine | ABD | 0.64 × 1.2 × 0.62 | 0.923 | ground | medium | 3120 | 6 | 0.38 | False | – | – |
| acoustic_guitar_stand | Acoustic guitar | 0.327 × 0.932 × 0.365 | 0.717 | ground | medium | 3008 | 5 | 0.25 | False | – | – |
| practice_amp | Amp | 0.52 × 0.52 × 0.327 | 0.4 | ground | small | 2772 | 4 | 0.3 | False | – | – |
| tall_case_clock | Antique clock | 0.48 × 1.47 × 0.341 | 1.131 | ground | medium | 2956 | 4 | 0.3 | False | – | – |
| antique_console_table | Antique console table | 1.0 × 0.73 × 0.428 | 0.562 | ground | large | 2256 | 3 | 0.5 | False | [0, 0.73, 0] [0.84, 0.36] | Support0 |
| pedestal_side_table | Antique mini table | 0.75 × 0.801 × 0.75 | 0.616 | ground | medium | 2000 | 1 | 0.4 | False | [0, 0.8, 0] [0.49, 0.49] | Support0 |
| antique_vanity | Antique vanity | 1.0 × 1.27 × 0.467 | 0.977 | ground | large | 5156 | 4 | 0.5 | False | – | – |
| antique_wardrobe | Antique wardrobe | 1.08 × 1.575 × 0.638 | 1.212 | ground | large | 4044 | 3 | 0.55 | False | – | – |
| apple_chair | Apple chair | 0.57 × 1.001 × 0.553 | 0.77 | ground | medium | 2608 | 5 | 0.38 | False | – | Seat0 |
| handled_urn | Aquarius urn | 0.482 × 0.515 × 0.335 | 0.396 | ground | small | 2400 | 3 | 0.22 | True | – | – |
| arcade_cabinet_blue | Arcade combat game | 0.632 × 1.46 × 0.75 | 1.123 | ground | medium | 1984 | 5 | 0.4 | False | – | – |
| arcade_cabinet_red | Arcade fighting game | 0.632 × 1.46 × 0.75 | 1.123 | ground | medium | 1984 | 5 | 0.4 | False | – | – |
| arcade_cabinet_keys | Arcade mahjong game | 0.632 × 1.46 × 0.75 | 1.123 | ground | medium | 3100 | 5 | 0.4 | False | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- urn: first pass had a faceted belly and beaded handles -> smooth_path profile + swept tube handles (fixed)
- tall_case_clock and arcade cabinets: first pass failed G2 (cap triangulation) -> fixed outline/fillet radii
- lineup labels overlap for long ids (cosmetic, render-only)
- arches: year digits intentionally omitted (no lettering)
