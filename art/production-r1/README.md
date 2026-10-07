# Production models, release r1

Curated, versioned record of the 130 modeled items integrated into the game in release r1.
The GLBs themselves ship once, in `game/assets/models/<asset_id>.glb`; their catalog entries are
the block "production models r1" in `game/scripts/core/catalog.gd`. Coverage of all 639
reference entries and the next-run guide are in
[design/model-release-r1.md](../../design/model-release-r1.md).

## Contents

| Path | What it is |
|---|---|
| `RELEASE_MANIFEST.json` | Every shipped asset: source batch, version, source and shipped SHA-256, references, the generated catalog fields; plus the four excluded assets and why |
| `names.tsv` | Original display names in en, zh-CN, ja, es, fr, de |
| `batches/b00N-*/` | The eight frozen lab batches the models come from, without their GLBs and renders: `BATCH_MANIFEST.json` (SHA-256 of every file in the frozen batch, including the GLBs), `BATCH_RESULT.md`, `spec.json`, `validation.json` (validator gates per asset), `inspection.json` (visual check record), `metadata/<asset_id>.manifest.json` (contract fields and evidence), `source/` (the exact builders, kit and `build_batch.gd` used) |
| `skill/` | The project-local modeling skill and kit (`cozy_geo.gd`, validators, renderers) at release time |
| `tools/` | `integrate_release.py` (copies GLBs, writes the catalog block and locale names), `release_coverage.py` (coverage CSV and guide), `freeze_batch.py`, `run_batch.sh` |

## Versions

122 GLBs are byte-identical to their frozen batch (`shipped_sha256` equals `source_sha256`).
Eight wall items ship as **version 2**: version 1 placed the origin 5-13 cm off the vertical
center, and the game requires a wall item's origin at its center on the wall plane. Version 2
adds a transform-free wrapper root and moves the original root by `recenter_dy`; geometry,
materials and markers are unchanged. The frozen batches were not modified.

## What "validated" means here

Each asset passed the lab validator (Godot load and editor import, closed and correctly wound
geometry, no floating pieces, scale class against the avatar height H = 1.30, anchors, Seat0 /
Sleep0 / Light0 / Support0 markers, rotation-aware tabletop fit against every registered table,
1-6 materials, at most 6000 triangles) and a visual check of multiview and game-camera
renders by the modeling model. In the game it also passes `game/tests/run_tests.gd` (scale
contract, bounds within 0.12 m of the built model, anchors, footprint, model count). This is
not human art approval and not device testing.

## Rebuild

The builders were run inside the git-ignored modeling lab (`tools/nookipedia-model-production/`,
Godot 4.7.2): a Godot project whose `builders/` holds `source/builders/*.gd` and whose `kit/`
holds `source/kit/`, then
`godot --headless --path <project> --script res://build_batch.gd -- <spec.json> <out_dir>`.
Batch hashes were recorded at freeze time; a byte-identical rebuild from this copy has not been
re-run inside the repository.
