# b006-misc-3 (frozen 2026-10-06T21:44:01Z)

Assets: 17. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| bagworm_model | Bagworm model | 0.34 × 0.41 × 0.22 | 0.316 | ground | small | 1268 | 4 | 0.22 | True | – | – |
| baked_potatoes_plate | Baked potatoes | 0.36 × 0.31 × 0.36 | 0.238 | ground | small | 2916 | 3 | 0.22 | True | – | – |
| basketball | Ball | 0.35 × 0.352 × 0.352 | 0.271 | ground | small | 1152 | 2 | 0.2 | True | – | – |
| bamboo_candle_cup | Bamboo candleholder | 0.278 × 0.388 × 0.246 | 0.298 | ground | small | 1988 | 6 | 0.18 | True | – | Light0 |
| bamboo_slit_drum | Bamboo drum | 0.46 × 0.295 × 0.36 | 0.227 | ground | small | 2596 | 5 | 0.3 | True | – | – |
| bamboo_lunch_basket | Bamboo lunch box | 0.47 × 0.29 × 0.252 | 0.223 | ground | small | 2112 | 6 | 0.24 | True | – | – |
| bamboo_shoot_lamp | Bamboo-shoot lamp | 0.26 × 0.48 × 0.264 | 0.369 | ground | small | 1392 | 4 | 0.2 | True | – | Light0 |
| bamboo_shoot_soup | Bamboo-shoot soup | 0.36 × 0.283 × 0.36 | 0.218 | ground | small | 2048 | 5 | 0.22 | True | – | – |
| woven_bamboo_sphere | Bamboo sphere | 0.338 × 0.369 × 0.338 | 0.284 | ground | small | 2272 | 4 | 0.22 | True | – | – |
| fish_carpaccio_plate | Barred-knifejaw carpaccio | 0.36 × 0.265 × 0.36 | 0.204 | ground | small | 3820 | 6 | 0.22 | True | – | – |
| striped_fish_model | Barred knifejaw model | 0.411 × 0.419 × 0.22 | 0.322 | ground | small | 3044 | 4 | 0.22 | True | – | – |
| deep_sea_fish_model | Barreleye model | 0.383 × 0.374 × 0.22 | 0.288 | ground | small | 1764 | 4 | 0.22 | True | – | – |
| baseball_set | Baseball set | 0.554 × 0.349 × 0.281 | 0.268 | ground | small | 1562 | 3 | 0.24 | False | – | – |
| bath_bucket | Bath bucket | 0.413 × 0.298 × 0.38 | 0.229 | ground | small | 608 | 2 | 0.22 | False | – | – |
| beach_ball | Beach ball | 0.34 × 0.345 × 0.34 | 0.265 | ground | small | 784 | 5 | 0.2 | True | – | – |
| cricket_model | Bell cricket model | 0.34 × 0.344 × 0.372 | 0.265 | ground | small | 1648 | 3 | 0.22 | True | – | – |
| berliner_plate | Berliner | 0.36 × 0.305 × 0.36 | 0.235 | ground | small | 3168 | 3 | 0.22 | True | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- striped_fish_model rebuilt (stripe bands sized to the body cross-section) and re-inspected on the regenerated sheet_2.
- bath_bucket and baseball_set are not tabletop-eligible (removed); woven_bamboo_sphere shrunk to fit every registered host.
