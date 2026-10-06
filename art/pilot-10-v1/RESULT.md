# RESULT: cozy pilot-10 v1 (modeling lane)

**Status: first version complete and frozen. 10 of 10 assets were delivered, validated and are ready for GameCode review. 0 are blocked.**

- **Timebox:** the art-direction update arrived and the timebox started at 2026-10-06T13:18:01Z. The deadline was about 14:18:01Z.
- **Actual end:** 13:47:18Z, so **29.3 minutes elapsed** within the 60-minute budget.
- **Pilot span:** the pilot started at 13:13:02Z, so the whole pilot took 34.3 minutes.
- **Phase times:** shared preparation 2.2 min, skill/template 8.2 min, the ten asset windows 11.6 min in total, shared verification and reporting 12.1 min.
- **Commits:** none from this lane. GameCode owns integration, commit and push.

## Per item

| id | status | tris | surfaces | bounds w×h×d | anchor (placeable v1) | revisions | notes |
|---|---|---|---|---|---|---|---|
| 01-chair | complete | 2744 | 3 | 0.533×1.068×0.501 | ground (yes) | 0 | REUSED from the lab baseline B chair (same triangle count); only a Seat0 marker was added |
| 02-round-table | complete | 2048 | 2 | 1.000×0.660×1.000 | ground (yes) | 1 | one support slot: (0, 0.66, 0), 0.56×0.56, max 1 |
| 03-bed | complete | 4412 | 3 | 1.072×1.018×1.792 | ground (yes) | 1 | open-edge seams fixed during verification |
| 04-writing-bureau | complete | 2496 | 2 | 0.780×0.950×0.516 | ground (yes) | 1 | knob that was buried in the slope fixed |
| 05-open-shelf | complete | 3556 | 5 | 1.001×1.362×0.401 | ground (yes) | 0 | books are baked decoration; no slots |
| 06-desk-lamp | complete | 1664 | 4 | 0.317×0.538×0.482 | ground (yes), tabletop_eligible | 2 | scaled ×1.3; bounds recentered so it cannot overhang the table |
| 07-wall-clock | complete as an asset | 1976 | 4 | 0.440×0.440×0.141 | wall (**no**, contract v1 is ground-only) | 0 | recorded, not placeable |
| 08-curved-counter | complete | 3924 | 2 | 1.510×0.800×0.578 | ground (yes) | 2 | slot removed: too narrow for either eligible prop |
| 09-flower-pot | complete | 2848 | 6 | 0.351×0.573×0.351 | ground (yes), tabletop_eligible | 3 | final scale ×1.08 → 0.44 H (≤ 0.45 H) |
| 10-bird-mobile | complete as an asset | 3996 | 6 | 0.817×0.780×0.780 | ceiling (**no**) | 0 | recorded, not placeable |

## Exact checks (final run)

- **Geometry and import** (`metrics/verify_report.json`), all 10 assets:
  - glTF export error 0; runtime load error 0;
  - editor import counts match the runtime load;
  - 0 triangles wound against their normals, 0 degenerate triangles, 0 open edges, 0 floating parts;
  - anchor plane OK.
- **Support fit** (`renders/fit_lineup/support_fit_report.json`):
  - table + pot and table + lamp: the size rule holds, there is no overhang with the prop's origin at the support center, the prop bottom sits exactly at y = 0.66, and the marker matches the manifest;
  - the counter declares no support surface.
- **Reference bundle** (`metrics/reference_bundle_verification.json`): 639/639/639 records, 13 categories, `ok: true`.
- **Kit smoke test** (`metrics/smoke/`): every helper builds and exports, with 0 open edges.
- **Renders inspected:**
  - all 10 per-item check sheets;
  - the full gallery;
  - both lineups;
  - the fit demos.
- **Commands:**
  - `tools/item.sh <id>`
  - `project`: `bin/godot --headless --path . --import`
  - `res://kit/verify_glb.gd -- ../models ../metrics/verify_report.json ../metadata/anchors.json`
  - `xvfb-run … res://fit_lineup.gd -- ../models ../renders/fit_lineup ../renders/reference/game_chair.glb`

## Metering

- **Ledger:** serial, in `metrics/ledger.jsonl`. Phase and asset windows, revisions, generator and render times, file sizes and acceptance are in `metrics/work_metrics.json` and `metrics/asset_metrics.csv`. Per-asset build and export takes 0.4–0.9 s; rendering 6 views plus a check sheet takes 3.8–5.9 s.
- **Token attribution:**
  - **Source:** this session's own transcript only; streamed duplicates are removed by message id, and messages from before the pilot are excluded.
  - **Per-asset rows:** `exact_by_serial_time_window`. A row includes kit helper edits made inside that asset's window. Fixes found later during shared verification stay in `shared_verification_reporting`.
  - **Not done:** nothing is divided by 10, and no price is implied (this runs on a subscription).
  - **Thinking tokens:** already included in the output column.

Usage per phase. The shared verification and reporting rows keep growing until the session ends, so read them from `metrics/token_attribution.json`:

| phase | messages | uncached input | cache creation | cache read | output (incl. thinking) | thinking |
|---|---|---|---|---|---|---|
| shared_preparation | 14 | 28 | 31845 | 2933894 | 11933 | 6862 |
| skill_template | 21 | 42 | 45148 | 5293274 | 32402 | 6810 |
| asset:01-chair | 7 | 14 | 8495 | 1922968 | 3208 | 828 |
| asset:02-round-table | 5 | 10 | 4550 | 1403054 | 2213 | 655 |
| asset:03-bed | 2 | 4 | 6148 | 569862 | 2605 | 1099 |
| asset:04-writing-bureau | 5 | 10 | 6882 | 1463699 | 4962 | 2507 |
| asset:05-open-shelf | 2 | 4 | 2220 | 592963 | 1682 | 252 |
| asset:06-desk-lamp | 4 | 8 | 5662 | 1202346 | 4226 | 2139 |
| asset:07-wall-clock | 2 | 4 | 2148 | 608630 | 1699 | 356 |
| asset:08-curved-counter | 4 | 8 | 7218 | 1234681 | 4348 | 2369 |
| asset:09-flower-pot | 4 | 8 | 5083 | 1262272 | 3516 | 1388 |
| asset:10-bird-mobile | 2 | 4 | 3394 | 637624 | 2857 | 1142 |

## Limitations

- Modeling acceptance only. The following were not tested:
  - in-game placement, collision, saves or network behavior;
  - iPad or iPhone frame rate and memory;
  - human art approval.
- Wall and ceiling assets are not placeable under contract v1.
- Production ids are proposals only.
- Renders use software GL.
- See `README.md`, "Known limitations".
