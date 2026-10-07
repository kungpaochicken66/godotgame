# b007-wall-1 (frozen 2026-10-06T21:44:31Z)

Assets: 22. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| framed_painting_ring | Academic painting, Academic painting (fake) | 0.5 × 0.62 × 0.067 | 0.477 | wall | medium | 1580 | 5 | None | False | – | – |
| wall_air_conditioner | Air conditioner | 0.9 × 0.28 × 0.21 | 0.215 | wall | medium | 996 | 3 | None | False | – | – |
| framed_painting_night | Amazing painting, Amazing painting (fake) | 1.0 × 0.8 × 0.067 | 0.615 | wall | medium | 1960 | 5 | None | False | – | – |
| wall_crank_phone | Antique phone | 0.354 × 0.34 × 0.18 | 0.262 | wall | small | 1112 | 3 | None | False | – | – |
| bust_relief_plaque | Art plaque | 0.36 × 0.435 × 0.148 | 0.335 | wall | small | 2724 | 2 | None | False | – | – |
| signed_card_frames | Autograph cards | 0.68 × 0.46 × 0.038 | 0.354 | wall | medium | 1680 | 4 | None | False | – | – |
| bamboo_wall_spray | Bamboo wall decoration | 0.209 × 0.33 × 0.12 | 0.254 | wall | small | 1676 | 5 | None | False | – | – |
| framed_painting_portrait | Basic painting, Basic painting (fake) | 0.5 × 0.85 × 0.067 | 0.654 | wall | medium | 1388 | 4 | None | False | – | – |
| towel_rack | Bathroom towel rack | 0.48 × 0.35 × 0.175 | 0.269 | wall | small | 1272 | 3 | None | False | – | – |
| blue_rose_wreath | Blue rose wreath | 0.452 × 0.481 × 0.083 | 0.37 | wall | small | 2592 | 4 | None | False | – | – |
| bone_doorplate | Bone doorplate | 0.551 × 0.237 × 0.04 | 0.183 | wall | small | 892 | 1 | None | False | – | – |
| wall_boomerang | Boomerang | 0.395 × 0.395 × 0.06 | 0.304 | wall | small | 988 | 3 | None | False | – | – |
| breaker_box | Breaker | 0.4 × 0.26 × 0.1 | 0.2 | wall | small | 1272 | 2 | None | False | – | – |
| round_award_plaque | Bronze HHA plaque | 0.4 × 0.4 × 0.062 | 0.308 | wall | small | 1816 | 2 | None | False | – | – |
| broom_and_dustpan | Broom and dustpan | 0.346 × 0.699 × 0.092 | 0.538 | wall | medium | 800 | 4 | None | False | – | – |
| butterfly_plaque | Bug plaque | 0.36 × 0.435 × 0.078 | 0.335 | wall | small | 3140 | 2 | None | False | – | – |
| insect_chart_poster | Bug poster | 0.42 × 0.6 × 0.044 | 0.462 | wall | small | 1496 | 6 | None | False | – | – |
| green_bulletin_board | Bulletin board | 0.8 × 0.5 × 0.066 | 0.385 | wall | medium | 1268 | 5 | None | False | – | – |
| egg_light_garland | Bunny Day glowy garland | 0.93 × 0.22 × 0.069 | 0.169 | wall | medium | 1226 | 6 | None | False | – | Light0 |
| egg_wall_clock | Bunny Day wall clock | 0.382 × 0.5 × 0.095 | 0.385 | wall | small | 2564 | 6 | None | False | – | – |
| egg_bow_wreath | Bunny Day wreath | 0.486 × 0.537 × 0.097 | 0.413 | wall | small | 2520 | 6 | None | False | – | – |
| fish_trophy_wall | Butterfly-fish model | 0.462 × 0.33 × 0.065 | 0.254 | wall | small | 2304 | 3 | None | False | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- Wall items: origin at back-plane center (z = 0); clock faces re-seated (were 3-5 mm off) before this inspection.
