# b008-wall-2 (frozen 2026-10-06T21:44:56Z)

Assets: 23. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| framed_painting_park | Calm painting | 1.0 × 0.72 × 0.067 | 0.554 | wall | medium | 1768 | 6 | None | False | – | – |
| blossom_wall_clock | Cherry-blossom clock | 0.456 × 0.468 × 0.093 | 0.36 | wall | small | 2292 | 4 | None | False | – | – |
| cherry_wall_lamp | Cherry lamp | 0.377 × 0.456 × 0.2 | 0.35 | wall | small | 1232 | 4 | None | False | – | Light0 |
| chic_cosmos_wreath | Chic cosmos wreath | 0.453 × 0.462 × 0.081 | 0.356 | wall | small | 3264 | 5 | None | False | – | – |
| chic_windflower_wreath | Chic windflower wreath | 0.476 × 0.453 × 0.083 | 0.348 | wall | small | 2432 | 5 | None | False | – | – |
| coconut_wall_planter | Coconut wall planter | 0.252 × 0.471 × 0.286 | 0.362 | wall | small | 1180 | 4 | None | False | – | – |
| framed_painting_field | Common painting | 0.62 × 0.5 × 0.067 | 0.385 | wall | medium | 1768 | 6 | None | False | – | – |
| cool_hyacinth_wreath | Cool hyacinth wreath | 0.461 × 0.46 × 0.079 | 0.353 | wall | small | 3744 | 6 | None | False | – | – |
| cool_pansy_wreath | Cool pansy wreath | 0.479 × 0.47 × 0.082 | 0.362 | wall | small | 2688 | 5 | None | False | – | – |
| cool_windflower_wreath | Cool windflower wreath | 0.471 × 0.453 × 0.083 | 0.348 | wall | small | 2176 | 6 | None | False | – | – |
| cork_board | Corkboard | 0.8 × 0.5 × 0.066 | 0.385 | wall | medium | 1268 | 5 | None | False | – | – |
| cosmos_wreath | Cosmos wreath | 0.47 × 0.461 × 0.081 | 0.354 | wall | small | 3264 | 6 | None | False | – | – |
| crest_doorplate | Crest doorplate | 0.419 × 0.397 × 0.055 | 0.305 | wall | small | 1144 | 2 | None | False | – | – |
| cuckoo_wall_clock | Cuckoo clock | 0.371 × 0.713 × 0.215 | 0.548 | wall | medium | 2508 | 6 | None | False | – | – |
| dark_lily_wreath | Dark lily wreath | 0.452 × 0.486 × 0.084 | 0.374 | wall | small | 2304 | 5 | None | False | – | – |
| dark_rose_wreath | Dark rose wreath | 0.479 × 0.47 × 0.082 | 0.361 | wall | small | 2880 | 5 | None | False | – | – |
| dark_tulip_wreath | Dark tulip wreath | 0.475 × 0.467 × 0.082 | 0.36 | wall | small | 2112 | 5 | None | False | – | – |
| antler_wall_mount | Deer decoration | 0.386 × 0.587 × 0.274 | 0.451 | wall | small | 1588 | 4 | None | False | – | – |
| framed_painting_scroll | Detailed painting, Detailed painting (fake) | 0.4 × 0.85 × 0.067 | 0.654 | wall | medium | 1580 | 5 | None | False | – | – |
| neon_ring_clock | Diner neon clock | 0.44 × 0.44 × 0.105 | 0.338 | wall | small | 2392 | 4 | None | False | – | – |
| station_wall_clock | Double-sided wall clock | 0.15 × 0.338 × 0.46 | 0.26 | wall | small | 3900 | 4 | None | False | – | – |
| plush_wall_shelf | Dreamy wall rack | 0.5 × 0.408 × 0.16 | 0.314 | wall | small | 1272 | 3 | None | False | – | – |
| dried_flower_garland | Dried-flower garland | 0.93 × 0.287 × 0.071 | 0.221 | wall | medium | 2570 | 6 | None | False | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- cuckoo clock materials reduced to <= 6 and re-inspected; wreaths/garland tri+material budgets fixed.
