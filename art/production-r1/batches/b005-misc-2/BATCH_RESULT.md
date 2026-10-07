# b005-misc-2 (frozen 2026-10-06T21:43:35Z)

Assets: 14. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| brass_cash_register | Antique cash register | 0.481 × 0.36 × 0.338 | 0.277 | ground | small | 2664 | 4 | 0.26 | True | – | – |
| map_on_easel | Antique map | 0.372 × 0.343 × 0.197 | 0.264 | ground | small | 1384 | 5 | 0.22 | True | – | – |
| arched_table_radio | Antique radio | 0.34 × 0.419 × 0.226 | 0.323 | ground | small | 2228 | 4 | 0.22 | True | – | – |
| apple_jam_jars | Apple jam | 0.29 × 0.286 × 0.18 | 0.22 | ground | small | 2904 | 3 | 0.2 | True | – | – |
| apple_jelly_plate | Apple jelly | 0.36 × 0.324 × 0.36 | 0.249 | ground | small | 2300 | 5 | 0.22 | True | – | – |
| apple_pie_plate | Apple pie | 0.36 × 0.288 × 0.36 | 0.222 | ground | small | 2904 | 4 | 0.22 | True | – | – |
| apple_smoothie | Apple smoothie | 0.251 × 0.331 × 0.18 | 0.255 | ground | small | 692 | 3 | 0.18 | True | – | – |
| apple_tart_slice | Apple tart | 0.36 × 0.275 × 0.36 | 0.212 | ground | small | 2088 | 5 | 0.22 | True | – | – |
| arapaima_model | Arapaima model | 0.921 × 0.379 × 0.24 | 0.292 | ground | large | 1764 | 4 | 0.45 | False | – | – |
| aroma_burner | Aroma pot | 0.28 × 0.278 × 0.28 | 0.214 | ground | small | 1676 | 4 | 0.2 | True | – | Light0 |
| arowana_model | Arowana model | 0.409 × 0.363 × 0.22 | 0.279 | ground | small | 1764 | 5 | 0.24 | True | – | – |
| plush_bear | Baby bear | 0.361 × 0.44 × 0.242 | 0.338 | ground | small | 1576 | 4 | 0.2 | True | – | – |
| plush_panda | Baby panda | 0.361 × 0.44 × 0.242 | 0.338 | ground | small | 1676 | 3 | 0.2 | True | – | – |
| backlit_box_sign | Backlit sign | 0.42 × 0.3 × 0.167 | 0.231 | ground | small | 1092 | 3 | 0.24 | True | – | Light0 |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- Inspected sheets after the material/tri budget and class fixes listed in the run notes.
