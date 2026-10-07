# b004-misc-1 (frozen 2026-10-06T21:43:02Z)

Assets: 13. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| accessory_rack | Accessories stand | 0.58 × 0.842 × 0.332 | 0.647 | ground | medium | 2200 | 6 | 0.3 | False | – | – |
| tiered_tea_stand | Afternoon-tea set | 0.32 × 0.572 × 0.32 | 0.44 | ground | small | 3128 | 6 | 0.2 | True | – | – |
| butterfly_model | Agrias butterfly model | 0.34 × 0.332 × 0.244 | 0.255 | ground | small | 1840 | 4 | 0.22 | True | – | – |
| circulator_fan | Air circulator | 0.375 × 0.46 × 0.22 | 0.354 | ground | small | 2700 | 2 | 0.22 | True | – | – |
| fried_fish_plate | Aji fry | 0.36 × 0.267 × 0.36 | 0.205 | ground | small | 2784 | 6 | 0.22 | True | – | – |
| aluminum_briefcase | Aluminum briefcase | 0.5 × 0.419 × 0.154 | 0.322 | ground | small | 1816 | 3 | 0.3 | True | – | – |
| kitchen_scale | Analog kitchen scale | 0.33 × 0.302 × 0.33 | 0.232 | ground | small | 2684 | 4 | 0.2 | True | – | – |
| garlic_fish_skillet | Anchoas al ajillo | 0.422 × 0.27 × 0.36 | 0.208 | ground | small | 3600 | 6 | 0.24 | True | – | – |
| anchovy_model | Anchovy model | 0.4 × 0.341 × 0.22 | 0.262 | ground | small | 1764 | 4 | 0.22 | True | – | – |
| clay_figurine | Ancient statue, Ancient statue (fake) | 0.445 × 0.558 × 0.241 | 0.429 | ground | small | 2176 | 3 | 0.22 | True | – | – |
| angelfish_model | Angelfish model | 0.389 × 0.486 × 0.22 | 0.374 | ground | small | 2532 | 4 | 0.22 | True | – | – |
| ant_farm | Ant farm | 0.37 × 0.5 × 0.14 | 0.385 | ground | small | 2064 | 3 | 0.22 | True | – | – |
| ant_model | Ant model | 0.34 × 0.335 × 0.319 | 0.258 | ground | small | 2056 | 3 | 0.22 | True | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- angelfish_model rebuilt (stripe bands sized to the body cross-section; fins scale with body height) and re-inspected on the regenerated sheet_2.
- Earlier fixes: clay figurine arms shortened, skillet deepened, tea stand/anatomy materials reduced to <= 6, fish fins scaled.
