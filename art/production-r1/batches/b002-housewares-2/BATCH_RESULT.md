# b002-housewares-2 (frozen 2026-10-06T17:28:01Z)

Assets: 15. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| saxophone_stand | Alto saxophone | 0.438 × 0.868 × 0.338 | 0.667 | ground | medium | 3172 | 4 | 0.25 | False | – | – |
| lab_machine | Amazing machine | 1.1 × 1.165 × 0.536 | 0.896 | ground | large | 5180 | 6 | 0.6 | False | – | – |
| anatomy_model | Anatomical model | 0.445 × 1.11 × 0.4 | 0.854 | ground | medium | 2576 | 5 | 0.25 | False | – | – |
| anchor_statue | Anchor statue | 0.552 × 0.936 × 0.54 | 0.72 | ground | medium | 2608 | 2 | 0.3 | False | – | – |
| wooden_signpost | Angled signpost | 0.507 × 1.2 × 0.309 | 0.923 | ground | medium | 1384 | 5 | 0.25 | False | – | – |
| cushion_stool | Arcade seat | 0.468 × 0.546 × 0.468 | 0.42 | ground | small | 1564 | 2 | 0.3 | False | – | Seat0 |
| ram_rocker | Aries rocking chair | 0.476 × 0.759 × 1.069 | 0.584 | ground | large | 4868 | 5 | 0.4 | False | – | Seat0 |
| low_platform_bed | Artful bed | 1.08 × 0.94 × 1.86 | 0.723 | ground | large | 3380 | 4 | 0.85 | False | – | Sleep0 |
| slat_armchair | Artful chair | 0.58 × 0.923 × 0.582 | 0.71 | ground | medium | 2812 | 2 | 0.38 | False | – | Seat0 |
| paper_floor_lamp | Artful lamp | 0.3 × 1.36 × 0.297 | 1.046 | ground | medium | 1684 | 4 | 0.2 | False | – | Light0 |
| folding_screen | Artful screen | 1.123 × 1.2 × 0.21 | 0.923 | ground | large | 2256 | 2 | 0.55 | False | – | – |
| lattice_cabinet | Artful shelves | 1.0 × 0.86 × 0.448 | 0.662 | ground | large | 4352 | 3 | 0.5 | False | – | – |
| insect_house | Artisanal bug cage | 1.0 × 0.79 × 0.56 | 0.608 | ground | large | 5036 | 3 | 0.5 | False | – | – |
| egg_lounge_chair | Artsy chair | 0.62 × 1.05 × 0.691 | 0.808 | ground | medium | 1776 | 3 | 0.38 | False | – | Seat0 |
| oval_arch_table | Artsy table | 1.12 × 0.66 × 0.58 | 0.508 | ground | large | 2260 | 2 | 0.55 | False | [0, 0.66, 0] [0.74, 0.36] | Support0 |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- First run: 6 gate failures found and fixed (materials > 6 on lab_machine/anatomy_model; floating anchor shank 3-4 mm gap; ram eyes/wool bumps floating; ram class large not medium; mattress pole sliver triangle).
- Import of this batch was slowed for ~30 min by host memory pressure; the import cache was regenerated (lab-local .godot only).
- egg_lounge_chair cushion reads as a large red panel at close range (acceptable stylization).
