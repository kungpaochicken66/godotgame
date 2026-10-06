---
name: cozy-game-modeling
description: Build small rounded, toy-like, matte furniture/props as real GLB meshes for a Godot 4 mobile game from a concept sheet plus reference data, with reuse-vs-rebuild rules, a procedural rounded-geometry kit, scale/anchor/support metadata and export/reimport/render checks.
---

# Cozy game modeling (project-local draft)

Use when an asset must look like the game's warm rounded toy style and ship as an
opaque GLB with predictable scale, anchor and markers. Tags: **[tested]** = exercised
and verified in a lab run; **[rec]** = recommendation, not yet proven here.

## 1. Inputs and scale (decide before modeling)
- Reference icons/catalog rows give *function, category and footprint ratio only*; never
  copy a design, never treat catalog grid units as meters. Concept sheets give palette,
  proportions and signature details, not exact geometry; resolve hidden/ambiguous
  structure physically (e.g. a table needs legs you cannot see). [tested]
- Measure the scale anchors from source, not from docs: avatar height **H**, current
  chair, wall height, camera. Record them with the asset. [tested]
- Read the project's scale contract first if one exists (here
  `design/object-scale-and-surfaces.md`) and map to its fields; it beats this skill. [tested]
- Stylized compression, not real meters: big furniture reads bigger in footprint/mass
  (bed > counter > table > chair), tiny props are *enlarged* to stay readable, usable
  space (seat height, bed length >= avatar) beats any ratio rule. Do not scale
  everything uniformly or into one normalized box. [tested on 10 items]
- Enlarge small props with `b.scale_all(f)` ONCE in the builder, then check the class
  limit on the *exported* height. In pilot 10 only the pot's 1.2x pass overshot 0.45 H
  (0.637 = 0.49 H) and was reduced to 1.08 (0.573 = 0.44 H); the lamp's final 1.3x is
  0.538 (0.41 H) and fits. [tested]

## 2. Reuse or rebuild
- Reuse an existing mesh only when its silhouette and construction already fit;
  restyling sharp low-poly bases mostly yields new parts plus repairs. [tested]
- Reusing a previous accepted asset: record that it is reused (source path + hash),
  do not present it as regenerated. [tested]
- When cutting a welded base: select triangles by centroid region, then expect
  *missing hidden faces* (bases omit faces covered by parts you removed) — run the
  open-edge check and patch or cover real holes. Keep boxy retained parts flat-shaded;
  smoothing normals across 90-degree edges makes diagonal creases. [tested]

## 3. Build with the kit (`scripts/cozy_geo.gd`)
- `Builder` collects triangles per named material and re-winds every triangle to its
  normals (Godot front faces are clockwise), so any parameterization is safe. [tested]
- Shapes: `rounded_box` (seg 2 small parts, 3 large bodies), `lathe` / `rod` / `puck`
  (legs, feet, pots, shades), `rod_between`, `egg` (leaves, petals, bird bodies),
  `pillow` (cushions, mattresses), `bevel_slab(outline)` for any custom silhouette
  (`scallop_top`, `lobed_circle`, `rounded_rect`, `annular_sector`). [tested: rounded_box,
  lathe, rod, egg, pillow, bevel_slab+scallop_top; others: rec until a pilot uses them]
- One outline per decorative silhouette (smooth-max lobes), never overlapping blobs:
  no scallop seams. Bands of one profile (pot wall / rim / soil) share end vertices:
  no floating rims. Overlap joined parts 1–3 cm; bury stems/leaf bases. [tested]
- Materials: flat matte (roughness 0.9, metallic 0), named, few per asset. Prefer 2–5
  surfaces; the pilot measured 2–6 (open shelf 5, flower pot 6, bird mobile 6), so this is
  a preference with measured exceptions, not universally met. Lambert-wrap diffuse is
  not stored in glTF; re-apply on import/render. No alpha, no billboards. [tested]
- Budget [tested]: 1.7k–4.4k tris per piece (pillows, books, bevel outlines dominate);
  leaves 8x12–14 segs; outlines for small slabs ~6 points per lobe.
- Superellipsoid `pillow` exponents below ~0.35 on small/thin parts cluster vertices
  under the 0.1 mm weld tolerance -> open-edge seams; use e >= 0.35 there. [tested]
- Builders: type results of kit calls explicitly when the kit is passed as an untyped
  arg (`var o: PackedVector2Array = G.f(...)`), or GDScript fails to parse. [tested]
- Anchors: ground origin = footprint center at y=0, front +Z; wall = back plane z=0,
  model in +Z; ceiling = attachment point y=0, model hangs into -Y. Markers (Seat0,
  Sleep0, Light0, Support0) are empty nodes via `b.marker()`; they survive GLB
  export/reimport. Mark wall/ceiling items "not placeable" if the game is ground-only. [tested]
- Support surfaces: declare one only on a genuinely flat, level top with no baked
  clutter; usable_size_xz must lie INSIDE the flat region (round top: inscribed square
  minus bevel; curved band: check corners against both arcs). Check eligible props by
  origin placement, not just size: an asymmetric prop (tilted lamp shade) can pass the
  size rule yet overhang -> `b.offset_all()` to center its xz bounds on the origin. A
  slot no eligible prop fits is not "sensible": do not declare it. [tested]

## 4. Export and verify (always)
1. `cozy_geo.export_glb()` (GLTFDocument) -> check err 0.
2. Copy GLBs into the project's `imported_check/`, run `godot --headless --path . --import`,
   then `scripts/verify_glb.gd -- <dir> <out.json> [anchors.json]`: runtime load ==
   editor import counts; 0 triangles wound against normals; 0 degenerate; open edges
   (0 expected for procedural); floating pieces (graph from the anchor plane); anchor
   plane check; markers listed. [tested]
3. `scripts/render_views.gd`: front/side/rear/three-quarter (one shared ortho size =
   relative scale), auto close-up, and a game-camera shot (pitch 40, yaw 28, fov 42,
   distance 11) with a 1.2 m scale post. Look at them; fix detached parts, holes,
   seams, silhouettes. Add a lineup with an avatar-height proxy and the current chair,
   and a host+prop fit demo. [tested] At 512 px the true-distance game view is small:
   it shows read size, not detail (device check still needed). [tested]
4. Pitfalls [tested]: elevated ortho makes far parts look higher (not a gap); in a
   SceneTree `_init`, set camera transforms directly and `await process_frame` before
   `unproject_position`; run Godot from a private binary copy in self-contained mode
   (`._sc_`) inside your scope so shared editor data is untouched; `xvfb-run` for GL.
   A script/parse error inside `SceneTree._init` leaves Godot running forever: always
   wrap runs in `timeout`. Never `pkill -f` a pattern that also appears in your own
   shell command line (it kills the shell); kill by exact process name instead.

## 5. Metering (if asked)
Keep a serial ledger (`phase start/end/revision`), build one asset at a time, and
attribute usage records by message timestamp; the message that issues a phase's
start call authors that phase's work, so windows start at that message. Keep fixes
found in shared verification as shared. Never divide totals per asset. [tested]

## 6. Report
Per asset: source/provenance, reused vs new, tris/surfaces/materials, bounds, anchor,
markers, checks, and which renders you actually inspected. Never claim device FPS or
in-game acceptance without testing on device/in game.
