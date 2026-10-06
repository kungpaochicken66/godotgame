# Pilot-10 v1 — Game Integration Record

This folder versions the reviewed modeling pilot "cozy pilot-10 v1". It was produced by the modeling lane in a separate lab and frozen there (the lab folder itself is git-ignored and untouched). The coordinator reviewed `HANDOFF_MANIFEST.json` (SHA-256 `7b63e06d21db1cd68738e479139edb8778495ac2894f51ceeb4adb3a8ada76c9`). The game-code lane verified all 68 listed files against their hashes before copying.

## What is here (copied from the curated shipped-file list)

- `models/`: all ten GLBs (final scale baked in) and their build reports.
- `metadata/`: per-asset neutral manifests and the anchor table.
- `project/`: the original builders (`items/*.gd`, `build_items.gd`, `fit_lineup.gd`) and a minimal `project.godot`.
- `skills/cozy-game-modeling/`: the project-local modeling skill and its scripts (`cozy_geo.gd` kit, verification, rendering).
- `renders/`: the gallery and table-fit images. `metrics/`: verification, render and work metrics. `tools/`: the lab's helper scripts.
- `README.md`, `RESULT.md`, `READY_FOR_INTEGRATION.md`, `HANDOFF_MANIFEST.json`: the modeling lane's own records.

**Not included:**
- the private Godot runtime (`bin/`) and the import caches (`project/.godot/`, `project/imported_check/`);
- the 639-image reference bundle and the other reference images (`input/`);
- session and usage logs (`metrics/ledger.jsonl`, `metrics/token_attribution.json`) and the reference-bundle file listing (`metrics/reference_bundle_verification.json`).

`HANDOFF_MANIFEST.json` still lists those files as part of the lab's frozen record. They are intentionally absent here.

**Edits relative to the frozen lab:** two accuracy fixes in `skills/cozy-game-modeling/SKILL.md`, requested in review:
1. Only the flower pot's 1.2× pass exceeded the small-class height; the lamp's final 1.3× (0.538) fits.
2. Material counts measured 2–6, so "2–5" is a preference with measured exceptions.

Also added: this file, `rebuild.sh` and `.gitignore`.

## Reproduce

```sh
art/pilot-10-v1/rebuild.sh            # rebuilds all ten GLBs with scripts/godot.sh and compares them
```

`rebuild.sh` recreates the `project/kit` link to the skill scripts (the lab used a symlink, which is git-ignored here). On 2026-10-06 the rebuild was **byte-identical** to all ten reviewed GLBs.

## In the game

| Pilot id | Game item id | Placeable | Notes |
|---|---|---|---|
| 01-chair | `scallop_chair` | yes | sits a child at its `Seat0` marker |
| 02-round-table | `cozy_round_table` | yes | support surface `(0, 0.66, 0)`, usable 0.56 × 0.56, one item (matches `Support0`) |
| 03-bed | `scallop_bed` | yes, indoors | rests a child at its `Sleep0` marker |
| 04-writing-bureau | `writing_bureau` ("Writing desk") | yes, indoors | |
| 05-open-shelf | `open_shelf` | yes, indoors | shelves are not support slots |
| 06-desk-lamp | `desk_lamp` | yes, indoors; tabletop-eligible | light at `Light0` in the evening. On the cozy table it fits at 0°, 90°, 180° and 270°; at 45° steps its turned box (about 0.565) exceeds 0.56, so it is refused there (the lamp is never shrunk and the area is not enlarged) |
| 08-curved-counter | `curved_counter` | yes, indoors | no support surface, by design |
| 09-flower-pot | `flower_pot_bloom` ("Blooming flower pot") | yes, indoors and outdoors; tabletop-eligible | fits the cozy table at every rotation |
| 07-wall-clock | — | **no** | wall anchor not implemented; kept here only, not in the game folder or catalog |
| 10-bird-mobile | — | **no** | ceiling anchor not implemented; kept here only |

- **Game files:** the eight placeable GLBs are copied byte-for-byte to `game/assets/models/<game id>.glb`.
- **Catalog:** entries live in `game/scripts/core/catalog.gd` with the manifests' bounds, footprints and size classes. The models are not rescaled at runtime.
- **Pending models:** `Catalog.PENDING_MODELS` records `wall_clock` and `bird_mobile`.
- **Old items:** existing items (`chair`, `table`, `bed`, `plant`, …) remain, so older saves are unchanged.

## Not verified

- Art approval.
- Device performance: the models are 1.7k–4.4k triangles each.
- Real touch use on iPhone or iPad.
