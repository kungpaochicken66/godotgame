# Cozy pilot-10 v1 — modeling lane (first version, frozen)

Ten original rounded toy-style furniture GLBs, built with a project-local modeling skill
distilled from the earlier three-object lab, then validated and refined through this
pilot. Standalone lab work: nothing here is integrated into the game; GameCode owns
integration, commit and push.

## What is here

| Path | Content |
|---|---|
| `models/<id>.glb` | the 10 deliverables (ids `01-chair` … `10-bird-mobile`) |
| `metadata/<id>.manifest.json`, `metadata/manifests.json` | per-asset neutral manifest mapped to the canonical contract (bounds, anchor, footprint, size_class, tabletop_eligible, support_surface, markers, mesh stats, SHA-256, provenance) |
| `project/items/<id>.gd` | one source builder + config (MANIFEST) per item |
| `project/build_items.gd`, `project/fit_lineup.gd` | item runner; support-fit checks + fit demo + scale lineup |
| `skills/cozy-game-modeling/` | `SKILL.md` + kit (`cozy_geo.gd`, `verify_glb.gd`, `render_views.gd`, `contact_sheet.gd`, `smoke_test.gd`, `godot_run.sh`) |
| `renders/gallery_pilot10.png` | all 10: front, side, rear, three-quarter (shared 2.0 m ortho frame), close-up, game camera |
| `renders/fit_lineup/` | lineup (isolated + game camera) with avatar proxy H = 1.30 and the game's current chair; table + one pot / one lamp fit demos; `support_fit_report.json` |
| `metrics/` | `ledger.jsonl` (serial work ledger), `work_metrics.json`, `asset_metrics.csv`, `token_attribution.json`, `verify_report.json`, `render_times.json`, `reference_bundle_verification.json` |
| `HANDOFF_MANIFEST.json`, `READY_FOR_INTEGRATION.md`, `RESULT.md` | handoff |
| `tools/` | `verify_references.py`, `ledger.sh`, `item.sh`, `render_timing.sh`, `finalize.py`, `handoff.py` |

Reproduce: `tools/item.sh <id>...` (build + render one item), then the verify / fit
commands in `RESULT.md`, then `python3 tools/finalize.py --transcript <this session's jsonl>`
and `python3 tools/handoff.py`. Needs `xvfb-run`; uses `bin/godot` (a hardlink to the lab's
verified Godot 4.7.2 binary in self-contained mode, so its editor data stays inside `bin/`).

## Inputs and how they were used

- `input/pilot-style-board.png` (shared generated concept sheet): palette, proportions,
  signature details (scalloped backs, ball finials, bun feet, rolled pot rim). Wood grain
  ignored; hidden structure resolved physically (four table legs fully under the top).
- `input/selected-references.json` + icons: function, category, interaction and footprint
  ratio only. Catalog grid units were **not** used as meters. Designs are original.
- 639-record Nookipedia bundle, extracted to `input/references/nookipedia/` and verified by
  `tools/verify_references.py`: 639 JSON rows = 639 CSV rows = 639 PNGs (signature-checked,
  SHA-256 recorded), 13 categories, all 189 furniture rows have a size, no manifest
  failures, archive SHA-256 `eaaf1299…87caac2`. Used as reference only: furniture size
  statistics (1×1 dominates; 2×1 / 2×2 for large pieces) and category/interaction context.
  Icon licenses are not established; nothing from it ships.
- Game facts measured from source: avatar head top H = 1.30 (`kid.gd`), current chair
  0.52 × 1.00 × 0.52, room walls 2.8, room camera pitch 40°, yaw 28°, FOV 42°, distance 11.
- Canonical contract `design/object-scale-and-surfaces.md` (GameCode): read and mapped below.

## Contract mapping (pilot id → proposed production id; GameCode decides the final key)

Bounds are measured from the exported GLBs (w × h × d, units, rotation 0). Anchors: the
lab helper values `floor`/`surface` both map to contract `ground`; `surface` items are
the `tabletop_eligible: true` ones. Wall/ceiling items are recorded but **not placeable**
under contract v1 (ground-only).

| pilot id | production id (proposal) | bounds | h / H | anchor | placeable v1 | radius, layer | size_class | tabletop_eligible | support_surface |
|---|---|---|---|---|---|---|---|---|---|
| 01-chair | scallop_chair | 0.533 × 1.068 × 0.501 | 0.82 | ground | yes | 0.38, solid | medium | false | – |
| 02-round-table | cozy_round_table | 1.000 × 0.660 × 1.000 | 0.51 | ground | yes | 0.52, solid | large | false | (0, 0.66, 0), 0.56 × 0.56, max 1 |
| 03-bed | scallop_bed | 1.072 × 1.018 × 1.792 | 0.78 | ground | yes | 0.85, solid | large | false | – |
| 04-writing-bureau | writing_bureau | 0.780 × 0.950 × 0.516 | 0.73 | ground | yes | 0.38, solid | large | false | – |
| 05-open-shelf | open_shelf | 1.001 × 1.362 × 0.401 | 1.05 | ground | yes | 0.45, solid | large | false | – (shelves are not slots) |
| 06-desk-lamp | desk_lamp | 0.317 × 0.538 × 0.482 | 0.41 | ground | yes | 0.18, solid | small | true | – |
| 07-wall-clock | wall_clock | 0.440 × 0.440 × 0.141 | 0.34 | wall | **no** | –, – | small | false | – |
| 08-curved-counter | curved_counter | 1.510 × 0.800 × 0.578 | 0.62 | ground | yes | 0.62, solid | large | false | – (see below) |
| 09-flower-pot | flower_pot_bloom | 0.351 × 0.573 × 0.351 | 0.44 | ground | yes | 0.18, solid | small | true | – |
| 10-bird-mobile | bird_mobile | 0.817 × 0.780 × 0.780 | 0.60 | ceiling | **no** | –, – | medium | false | – |

Markers (empty nodes, survive export/reimport, positions in the manifests): `Seat0`
(chair), `Support0` (table, equals `support_surface.local_position`), `Sleep0` (bed),
`Light0` (lamp bulb). Scale is final in the GLB (applied once in the builder; no runtime
multiplier). Origins: ground items at the footprint center on y = 0; xz bounds center is
within 0.01 of the origin except the bureau (z +0.033, drawers/knobs) and counter (z −0.089,
arc bulges forward); the lamp's xz bounds were deliberately centered on its origin.
Wall clock: back plane z = 0, recommended center height 1.5. Mobile: attachment point
y = 0, hangs 0.78 under a 2.8 ceiling.

**Scale decisions.** Large furniture reads as 1.5–2.9 chair widths along the long side (table 1.9, bureau 1.5, shelf 1.9,
counter 2.9, bed length 3.4 because the mattress must fit a lying child). Small props are
enlarged once in the builder and capped by the exported height: lamp ×1.3 → 0.41 H; pot
first ×1.2 = 0.637 (0.49 H, over the 0.45 H small-class cap) → reduced to ×1.08 = 0.573
(0.44 H), still readable and still fits the table.

**Support surface.** The table top is a flat lathe disc (flat radius 0.465); the declared
0.56 × 0.56 slot is inside its inscribed square (side 0.66), and its corners sit 0.40 from
center. Placing each eligible prop's origin at `Support0`: pot 0.351 × 0.351 and lamp
0.317 × 0.482 both fit the size rule AND the origin-centered no-overhang check, and their
bottoms sit exactly at y = 0.66 (`renders/fit_lineup/support_fit_report.json`). The counter
initially declared a slot, but its curved flat band only allows about 0.32 × 0.32 inside both arcs,
which fits neither eligible prop, so the slot was removed instead of declared uselessly.
Nothing auto-shrinks; no stacking; no runtime parenting in the lab.

## Verification actually performed

- **Export and reimport.** All 10 exported via GLTFDocument (err 0). Each was reloaded twice: by the glTF runtime loader and by the Godot
  editor import (`--headless --import` in this lab project). Triangle, surface and bounds counts match between the two loads.
- **Geometry checks** (`verify_glb.gd`):
  - 0 triangles wound against their normals, and 0 degenerate triangles, on all 10;
  - 0 open boundary edges on all 10 (the bed had 32 at first; fixed);
  - 0 floating parts: connectivity is traced from the anchor plane through bounds overlaps;
  - every model sits on its anchor plane (ground y = 0, wall z = 0, ceiling top y = 0);
  - the markers are listed.
- **Fit checks:** as above, plus the visual fit demos `fit_table_*`.
- **Renders I inspected myself:**
  - each item's 5-view check sheet;
  - close-ups of the bureau, flower pot and table;
  - the full gallery;
  - both lineups;
  - the table + lamp three-quarter view.

  Not every individual 512 px file was opened.
- **Render limits:** Compatibility renderer on Mesa llvmpipe under xvfb (software GL, not iPad/iPhone Metal).
  Lambert-wrap diffuse is re-applied at render time, because glTF cannot store it.

## Skill: exercised vs untested, and did it help?

**Exercised and confirmed:**
- **Reuse and kit pieces:**
  - the reuse-vs-rebuild rule: the chair was reused, and reuse was recorded;
  - Builder auto-winding;
  - `rounded_box`, `lathe`, `rod`, `rod_between`, `puck`, `egg`, `pillow`, `bevel_slab`, `scallop_top`, `lobed_circle`, `rounded_rect`, `annular_sector`;
  - `rounded_polygon`, `scale_all` and `offset_all` were added during the pilot.
- **Construction rules:** single-outline silhouettes, profile bands sharing vertices, and the 1–3 cm overlap rule. These produced 0 open edges and 0 floating parts on the first build, except the bed.
- **Export and checks:** marker export; anchor checks; the verify / import / render / game-camera loop; the timeout and process-kill pitfalls.

**Pilot failures that changed the skill:**
- superellipsoid exponents below about 0.35 leave weld seams;
- untyped kit results cause parse errors;
- a support-fit by origin can overhang even when the size rule passes;
- small props need a class-height cap after enlarging;
- message-window token attribution was off by one message per phase.

**Untested:**
- the reuse/retain path for cutting welded base meshes (no base mesh was cut in this pilot);
- real wall or ceiling placement in-game;
- device performance.

**Did it reduce repeated work?** Partly, with caveats. The nine new assets (02–10) took
25–180 s of serial window time each (median 46 s), with 0–2 revisions inside the window. The reused chair took 174 s,
including porting it to the kit. By comparison, the first lab took about 17 minutes for three objects, but that
included building the helpers, so the comparison is indicative rather than controlled. Per-asset wall time can
shift by roughly one message's generation time between neighbours, because message timestamps mark completion.
Skill and kit work cost about 8.4 min up front. Shared verification still found 4 real issues the per-item loop
missed (bed seams, lamp overhang, counter slot, pot height above the class cap). So the scripted checks, more
than the prose, carried much of the value.

## Known limitations

- Not integrated; no gameplay, collision, save or network testing; no iPad/iPhone FPS or memory data; no human art approval.
- Wall clock and bird mobile cannot be placed under contract v1.
- Production ids are proposals.
- Triangle counts are 1.7k–4.4k per asset. The bed, counter, mobile and shelf are the heaviest; no LODs.
- Materials are 2–6 flat-color surfaces per asset with no textures; the game's `merge_parts` could reduce draw calls.
- Birds, leaves and flower outlines show mild faceting in close-up. Strings are 4 mm rods, by design.
- In the 512 px game-camera renders small props are only a few pixels across: this shows in-game read size, not readability on a device. The contract's 44 px tap minimum is GameCode's concern.
