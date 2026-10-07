# Model release r1: coverage and next-run guide

Release r1 integrates the modeling lane's frozen, validated furniture batches into the game.
Every one of the 639 Nookipedia reference entries has exactly one status below; the per-entry
table (reference index, bundle file, item, category, status, asset id, batch, evidence or
reason) is [model-release-r1-coverage.csv](model-release-r1-coverage.csv).

References were used for function, garment type, silhouette, footprint and dominant colors
only. All geometry is original procedural modeling; display names are original generic names.

| status | furniture | clothing | total |
|---|---|---|---|
| shipped_production | 135 | 0 | 135 |
| shipped_pilot | 9 | 0 | 9 |
| built_not_accepted | 42 | 434 | 476 |
| blocked | 3 | 16 | 19 |
| remaining | 0 | 0 | 0 |
| total | 189 | 450 | 639 |

## What shipped

- 130 production models (`game/assets/models/<asset_id>.glb`, catalog block
  "production models r1" in `game/scripts/core/catalog.gd`, names in all six locales). They
  come from frozen batches b001-b008, each of which passed the lab validator (Godot import,
  closed geometry, scale class against avatar H = 1.30, anchors, Seat0/Sleep0/Light0/Support0
  markers, rotation-aware tabletop fit, material and triangle budgets) plus a model visual check
  of multiview and game-camera renders. In the game they also pass the game's own contract
  tests (`game/tests/run_tests.gd`). Visual checks are by the model, not human art approval.
- 8 wall items ship as version 2: the frozen v1 GLB put the origin off the vertical
  center by 5-13 cm; v2 adds one wrapper node that moves the model so its origin is the center
  on the wall plane (geometry unchanged). Frozen batches were not modified.
- The two-seat bamboo bench seats one child (the game reads only Seat0 for modeled items).
- Reference indices shipped as production models: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 53, 54, 55, 56, 58, 59, 60, 61, 62, 63, 64, 65, 66, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 114, 116, 117, 118, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 140, 141, 142, 144, 145, 146, 147, 148, 149.
- Reference indices covered by pilot-10 models: 10, 11, 12, 16, 25, 67, 91, 139, 150.

## Built but not accepted for this release

- Furniture excluded by the game's scale contract (small items must be 0.2-0.45 H tall; not
  relabelled): bone_doorplate (wall item is 0.237 m = 0.183 H as a float32 bound), breaker_box (wall item is 0.260 m = 0.200 H as a float32 bound), insect_chart_poster (wall item is 0.600 m = 0.462 H as a float32 bound), antler_wall_mount (wall item is 0.587 m = 0.451 H as a float32 bound).
  Reference indices: 113, 115, 119, 143.
- Ceiling batches b009-ceiling-1 and b010-ceiling-2 (38 references): built; their first run had
  gate failures (size class of pendants, floating cords/links, material budgets). The builders
  were fixed but the rerun was stopped for this release, so they are not frozen or shipped.
  Reference indices: 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188.
- Wearables (all 434 non-blocked clothing references): built as rig-fitted garments for the
  child replica of `game/scripts/art/kid.gd` (per-pivot GLBs, gates W1-W7). Batches c001 tops,
  c002 bottoms, c005 shoes, c008 bags and c009 umbrellas (240 references) are frozen with all
  gates passing; c003 dress-up, c004 headwear, c006 socks and c007 accessories have builder
  fixes whose reruns did not finish. None are accepted: the wearable validator self-test has
  not passed, and the game has no system to equip clothing. Reference indices:
  189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 368, 369, 370, 371, 372, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 418, 419, 420, 423, 424, 425, 427, 429, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 465, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 583, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638.

## Blocked (not modeled on purpose)

Franchise characters and trademarked designs (Nintendo, Sanrio and other licensed
collaborations). Reference indices: 50, 52, 57, 238, 367, 373, 400, 417, 421, 422, 426, 428, 430, 464, 466, 532, 533, 582, 584. Each reason is in the CSV.

## Remaining

Entries with no model built: none.

## Next run

The modeling workspace is `tools/nookipedia-model-production/` (git-ignored, local to the
modeling machine; see its README.md). One Godot job at a time on this host.
Follow the project dual-host workflow (`tools/dual-host-workflow/20261007-r2/`, with
`dual-host-modeling.md` and `model_handoff.py`): finish a bounded candidate here, seal an
explicit file list (builders, skill, validators and their self-tests, specs, manifests, GLBs),
send the manifest SHA-256, let the Mac import, test and render it, and review the returned
original images here before accepting anything. Heavy renders run on the Mac.

1. Ceiling furniture: `tools/run_queue.sh batches/b009-ceiling-1 batches/b010-ceiling-2`,
   inspect `renders/sheet_*.png`, write `inspection.json` (`tools/write_inspection.py`), then
   `python3 tools/freeze_batch.py batches/<b>`. Before integrating, decide with GameCode how
   ceiling pendants taller than 0.585 m are classed (the game test only bounds "small").
2. Wearables: run `python3 tools/wear_validator_selftest.py` until it prints PASS; rerun c003,
   c004, c006, c007 (`tools/run_queue.sh ...`), inspect, `tools/freeze_wear_batch.py`. Shipping
   them needs a game feature (equip per pivot node, hide the baked parts named in each
   manifest `hides`, a hold pose for `held` items) owned by GameCode.
3. The three excluded wall items need a new version with a height inside 0.26-0.585 m.
4. Integrate new frozen furniture with `python3 tools/integrate_release.py` (add names to
   `release/names.tsv`), then `tools/venv/bin/python scripts/build_fonts.py` and
   `scripts/test_all.sh`, and raise the model count in `test_modeled_assets`.
