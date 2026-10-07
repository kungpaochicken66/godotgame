---
name: cozy-game-modeling
description: Produce rounded, toy-like, matte props/furniture and rig-fitted wearables as validated GLB batches for a Godot 4 mobile game from reference data and a concept direction — archetype builders, a rounded geometry kit, deterministic contract validation (geometry, scale class, anchors, markers, rotation-aware support fit), multiview + game-camera renders, and frozen hash-listed batch handoffs.
---

# Cozy game modeling — v3 (project-local)

Tags: **[tested]** exercised and verified in this production run or the pilot;
**[rec]** recommendation not yet proven. Corrections to the pilot are in
`docs/LESSONS_FROM_PILOT.md` (final pot height 0.573; desk lamp fits a 0.56 slot only at
0/90/180/270°, not 45°; pilot material counts span 2–6).

## 1. Before modeling
- Read the game's scale contract (`design/object-scale-and-surfaces.md`) and map to its
  fields; it overrides this skill. Measure anchors from source (avatar H = 1.30). [tested]
- References (icons + catalog rows) give function, category, footprint ratio and
  interaction only. Never copy designs, textures, lettering, logos or artworks. Block,
  with a written reason, references that ARE third-party IP (a character item or a branded
  console); never substitute a generic object and call it that reference. [tested]
- Variants that the lab design would make identical (e.g. a genuine painting and its
  fake) map to ONE asset as `shared_variant`; never count them as separate work. [tested]

## 2. Scale classes (validator G4, contract §3)
small h 0.26–0.585 · medium h 0.78–1.56 · large long side ≥ 0.78 · flat h < 0.1;
wall/ceiling (lab rule): small ≤ 0.6, medium ≤ 1.2, large > 1.2 longest side. [tested]
- The contract has a gap (h 0.585–0.78 with a short footprint): raise or widen the piece
  deliberately (pedestal table raised to 0.80) and note it. [tested]
- Plated food is too low for "small": serve it on a standard pedestal tray (house rule). [tested]
- Low seats (stools, child chairs) are "small" by height only; say so, keep them not eligible. [tested]
- Footprint radius ≤ 0.75 × longest side + 0.15 (G5). [tested]

## 3. Build (kit: `scripts/cozy_geo.gd`, `scripts/cozy_parts.gd`)
- One builder per archetype in `project/builders/<archetype>.gd`, `static func build(G, p)`;
  per-asset parameters live in the batch `spec.json`. Type every kit result explicitly
  (`var x: PackedVector2Array = G.f(...)`): an inference error inside SceneTree `_init`
  hangs Godot; `run_batch.sh` parse-checks builders with `--check-only` first. [tested]
- Shapes [tested]: `rounded_box`, `lathe` (+`smooth_path` Catmull-Rom profiles), `rod`,
  `rod_between`, `puck`, `egg`, `pillow`, `bevel_slab` with `rounded_rect`, `scallop_top`,
  `lobed_circle`, `blob_outline` (smooth union of circles), `annular_sector`,
  `rounded_polygon`; `profile_x` (side profile extruded across x), `plan_slab` (plan outline
  extruded up), `tube` (swept tube, domed ends or closed loop). Parts: `bun_foot`, `knob`,
  `panel`, `bamboo`, `screen`, `balloon`, `slats`.
- Pitfalls [tested]: fillet radius must exceed bevel inset (else concave fillets collapse
  and cap triangulation fails); chained rods with fillets look beaded — use `tube`;
  superellipsoid exponents < ~0.35 on small/thin pillows leave sub-weld seams; lathe
  profiles with few points look faceted — `smooth_path`; tilted rods dip below the floor
  — the runner calls `b.snap(anchor)` and records the offset.
- Overlap joined parts 1–3 cm. The validator walks the overlap graph from the anchor plane
  and reports where unsupported pieces are (`unsupported_at`). [tested]
- ≤ 6 materials, ≤ 6000 tris per asset (G7). Muted matte palette in `PALETTE`; emissive
  only `bulb` and `screen`. [tested]
- Markers: `Seat0`/`Seat1` (seating), `Sleep0` (beds big enough for the child), `Light0`
  (lighting), `Support0` = support local_position. [tested]

## 4. Validate (deterministic — NOT art approval)
`scripts/validate_assets.gd -- spec.json models out.json res://imported/<batch> registry.json`
G1 runtime load + editor-import match · G2 0 flipped / 0 degenerate / 0 open / 0
unsupported · G3 anchor plane & origin · G4 size class · G5 footprint rule · G6 markers
by interaction · G7 budget · G8 support: 11×11 downward rays all hit the declared flat top
(±2 mm, up-facing), Support0 matches, max_items 1, AND the host accepts every known
eligible item at ≥ 1 of 8 rotations · G9 eligible: small, ground, fits every known host at
≥ 1 rotation (turned box |w cos a| + |d sin a|). Registry: `progress/support_registry.json`.
Self-test: `tools/validator_selftest.py` (clean spec passes; seeded faults fail exactly
the expected gates). [tested]

## 5. Render, inspect, freeze
- `tools/run_batch.sh <batch>`: build → editor import → validate → views (front, side,
  rear, three-quarter, close-up, game camera 11 m, game camera 4.5 m) → contact sheets →
  lineups with avatar H = 1.30 + chair → tabletop fit demos at 0° and 45°. [tested]
- Inspect the sheets yourself and write `inspection.json` (what was and was not opened).
  Fix, re-run the WHOLE batch with the final kit (reproducibility), then
  `tools/freeze_batch.py` (refuses on any failed gate or missing verdict): source snapshot,
  per-asset contract manifests, BATCH_MANIFEST.json hashes, read-only directory, tracker,
  registry, append-only INTEGRATION_QUEUE.md. [tested]
- Never mutate a frozen batch; repairs go into a new batch version. [rec until a receipt arrives]

## 6. Operations
- Private Godot copy in self-contained mode inside your scope; never touch shared editor
  data. Kill only your own processes by exact name (`pkill -x godot`), never `pkill -f`
  with a pattern from your own command line. [tested]
- Under memory pressure (shared 2-core / 2 GB host) the editor import can take many
  minutes: run Godot jobs one at a time, in the background, with long timeouts; clear only
  your own regenerable `project/.godot` cache if an import was killed midway. [tested]
- Meter with a serial ledger; attribute usage by message timestamp windows; keep fixes
  found in shared verification as shared; never divide totals. [tested in pilot]
- One Godot launch costs ~20 s of disk IO on a swapping host: gate all builders in ONE
  process (`project/check_scripts.gd`), never one launch per script. [tested]
- An editor `--import` that idles at ~2 % CPU after a killed import is the stale-cache hang:
  stop it, delete `project/.godot` and the `.import` files under `project/imported/`, rerun. [tested]

## 7. Wearables (clothing on the game child, H = 1.30)
- Rig contract: transcribe the game's child (`game/scripts/art/kid.gd`) into
  `project/wearables/kid_rig.gd` (pivots Body/Head/LegL/LegR/ArmL/ArmR, skin, baked outfit,
  shoes, hair cap, hair styles as SDF primitives; idle/walk/sit poses). Re-transcribe and
  re-validate whenever kid.gd changes. [tested]
- GLB layout: `<id>/<Pivot>/<id>_<Pivot>`; pivot node at the rest offset, mesh identity, so
  integration is "parent each pivot child under the matching child node". Rigid parts per
  pivot — no skinning. [tested]
- Never put a closed cap across a limb away from an opening: sleeves, pant legs, socks, cuffs
  and boot shafts are annular shells (`wear_common.gd` `shell`) whose ends are rings. W4
  exempts only vertices within 3 cm of the garment's ends along the limb (a cap exactly at an
  opening is hidden inside the limb and passes, like the child's own shoe tops); a cap or a too
  tight wall anywhere else fails. [tested: sample sleeves with caps 3.5 cm in failed W4; self-test
  tight sleeve fails W4; the self-test showed an end-cap-only sleeve is (correctly) accepted]
- Patterns on a torso: bands are plan-slabs of the torso's own rounded-rect section
  (`band`); a thin `rounded_box` clamps its corner radius and sticks out ~3 cm at corners
  and, having vertices only at corners, cannot be shown to touch the torso. Dots as
  flattened low-ring spheres, flowers as 10-point slabs keep tops under 3000 tris. [tested]
- Share ONE material instance per palette name across all pivot meshes of an asset, or the
  glTF exporter renames duplicates (`red2`, `red3`) and the material count inflates. [tested]
- Head items: crowns sit ON the hair cap (solve the shell/cap clearance numerically, e.g.
  cone hat inner line y = 0.663 - 0.5 r); band items (crown, flowers, clip, ears, bopper) keep
  the hair visible and report per-style hair clipping; crown-covering hats hide hair. [tested]
- Worn bags stay outside the torso envelope and below the head: straps cross the shoulder at
  x = +-0.15, y = 0.725 (6 cm gap between torso top and head). Held items (umbrella, tote,
  basket) are ArmR parts gripped at the fist (0.04, -0.29); manifest `held: true` exempts
  only the grip inside the closed hand. [tested]
- Validator `validate_wearables.gd` v2 gates W1 load/import, W2 closed geometry, W3 pivot
  structure, W4 no vertex > 4 mm inside skin/hair cap (+ torso envelope for worn bags) in
  idle and walk poses (limb-opening and hand-grip exemptions only), W5 contact-graph
  attachment (piece within 3 cm of its pivot's body, or within 1.2 cm of an attached piece,
  checked both ways), W6 <= 3000 tris and <= 4 materials, W7 hair cap. Self-test:
  `tools/wear_validator_selftest.py` (good garments pass; tight sleeve, floating button,
  wrong pivot, 5 materials, hat inside hair, held item without the grip flag each fail
  exactly the expected gate). Sit pose is reported, not gated. [tested]
- Pipeline: `tools/clothing_specs.py` (per-item table from the icon review: garment type,
  silhouette, dominant colors; brand marks/lettering dropped) → `tools/run_wear_batch.sh` →
  inspect sheets → `tools/freeze_wear_batch.py`. [tested]
