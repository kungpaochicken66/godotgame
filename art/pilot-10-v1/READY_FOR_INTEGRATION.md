# READY FOR INTEGRATION: cozy pilot-10 v1 (modeling lane → GameCode)

**Ready for review.** This lane does not commit or push. GameCode owns integration, commit and push.

**What to ship:** the files listed in `HANDOFF_MANIFEST.json` under `assets` and `shipped_files`, with their SHA-256 hashes.

**Do not ship:** `bin/`, `project/.godot/`, `project/imported_check/`, `input/references/` (the 639-image reference bundle) and the other input reference images.

**Per asset:**
- GLB: `models/<id>.glb`
- Neutral manifest: `metadata/<id>.manifest.json`
- Builder: `project/items/<id>.gd`

**Contract mapping:** `README.md`, section "Contract mapping".
- Proposed production ids: scallop_chair, cozy_round_table, scallop_bed, writing_bureau, open_shelf, desk_lamp, wall_clock, curved_counter, flower_pot_bloom, bird_mobile.
- Helper anchor values `floor` and `surface` both map to contract `ground`. The `surface` items are the ones marked `tabletop_eligible: true` (desk_lamp, flower_pot_bloom).
- wall_clock (anchor `wall`) and bird_mobile (anchor `ceiling`) are **not placeable** under contract v1.
- Bounds are measured from the exported GLBs and are final size. No runtime scale is needed: scale is applied once, in the builders.

**Support surface:** only `02-round-table` declares one: `local_position (0, 0.66, 0)`, `usable_size_xz (0.56, 0.56)`, `max_items 1`, matching its `Support0` marker. Both eligible props fit it with no overhang.

**Checks:** all clean (see `RESULT.md`). Untested:
- device performance;
- in-game behavior;
- art approval.
