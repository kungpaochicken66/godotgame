# b003-housewares-3 (frozen 2026-10-06T18:15:13Z)

Assets: 15. All passed validator `validate_assets.gd v2.1` gates G1–G9 (as applicable) and a model visual check of every render set.
This is geometry/scale/anchor evidence plus a visual check by the model, not human art approval or device performance testing.

| asset_id | references | bounds w×h×d | H | anchor | size | tris | mats | footprint r | eligible | support | markers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| space_rock | Asteroid | 0.918 × 0.728 × 0.837 | 0.56 | ground | large | 1088 | 1 | 0.42 | False | – | – |
| space_suit_display | Astronaut suit | 0.608 × 1.27 × 0.52 | 0.977 | ground | medium | 3880 | 5 | 0.28 | False | – | – |
| top_load_washer | Automatic washer | 0.6 × 1.005 × 0.61 | 0.773 | ground | medium | 2392 | 5 | 0.36 | False | – | – |
| garden_pavilion | Azumaya gazebo | 2.8 × 2.81 × 2.8 | 2.162 | ground | large | 3180 | 5 | 1.3 | False | – | – |
| baby_crib | Baby bed | 0.688 × 0.895 × 0.968 | 0.688 | ground | medium | 5636 | 3 | 0.45 | False | – | – |
| child_tube_chair | Baby chair | 0.384 × 0.555 × 0.391 | 0.427 | ground | small | 2016 | 2 | 0.26 | False | – | Seat0 |
| ball_cart | Ball catcher | 1.0 × 0.74 × 0.637 | 0.569 | ground | large | 5696 | 3 | 0.5 | False | – | – |
| bamboo_basket | Bamboo basket | 0.338 × 0.409 × 0.338 | 0.314 | ground | small | 2512 | 3 | 0.2 | True | – | – |
| bamboo_bench | Bamboo bench | 1.2 × 0.465 × 0.426 | 0.358 | ground | large | 4320 | 2 | 0.55 | False | – | Seat0, Seat1 |
| glowing_bamboo | Bamboo doll | 0.491 × 0.8 × 0.435 | 0.615 | ground | medium | 1732 | 5 | 0.24 | False | – | Light0 |
| bamboo_floor_lantern | Bamboo floor lamp | 0.44 × 1.03 × 0.44 | 0.792 | ground | medium | 3604 | 4 | 0.26 | False | – | Light0 |
| wish_bamboo | Bamboo grass | 0.757 × 1.439 × 0.798 | 1.107 | ground | medium | 3440 | 6 | 0.3 | False | – | – |
| bamboo_noodle_slide | Bamboo noodle slide | 2.219 × 0.866 × 0.4 | 0.666 | ground | large | 3948 | 3 | 0.9 | False | – | – |
| bamboo_partition | Bamboo partition | 1.0 × 1.35 × 0.24 | 1.038 | ground | large | 5676 | 3 | 0.55 | False | – | – |
| bamboo_ring_shelf | Bamboo shelf | 1.176 × 1.229 × 0.42 | 0.945 | ground | large | 5288 | 2 | 0.6 | False | – | – |

Renders: `renders/sheet_*.png` (front, side, rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m), `renders/lineup/` (avatar H=1.30 + chair lineups; tabletop fit demos at 0° and 45°).
Inspection record: `inspection.json`. Sources: `source/` (builders + kit snapshot, rebuild with `build_batch.gd`). Hashes: `BATCH_MANIFEST.json`.

Visual check notes:

- First run: 5 gate failures fixed (tri budgets on bamboo_bench/bamboo_ring_shelf; open bottom ring on cut bamboo; wish_bamboo height/materials/2 flipped thin-leaf triangles; noodle slide origin off-center; ring shelf middle poles really floating -> cross members added).
- garden_pavilion and bamboo_noodle_slide exceed the fixed 2.0 m ortho frame: front/side/rear views are cropped; close-up and game-camera views show the whole object.
- bamboo_ring_shelf supersedes the pilot open_shelf mapping for the Bamboo shelf reference.
