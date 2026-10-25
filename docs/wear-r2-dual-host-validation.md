# Wear-r2 dual-host model validation

Date: 2026-10-08. Workflow: [dual-host modeling](dual-host-modeling.md).
EC2 Modeling owns production geometry, the reference rig and visual review. Mac Codex runs
immutable-input checks, sequential Godot verification and returns original evidence through
the same project evidence directory. Engine: `4.7.2.stable.official.ed1daf0bf`, Mac Apple M1 Pro,
OpenGL. This record concerns model and rig contracts, not an integrated game release.

## Scope and current result

- 61 seated garments: 43 skirted dress-ups and 18 skirts. Full Mac verification passed;
  Modeling reviewed all 27 full-batch pages plus seam closeups and froze c016/c017.
- 60 held items: 50 umbrellas and 10 hand-held bags. Four pilot assets passed in rev2/rev3;
  the remaining 48 umbrellas and 8 bags passed Mac rev5. Producer reviewed all 21 pages plus 2 original closeups and froze c018/c019. All 60 held items are now model-contract validated.
- The 61 garments supersede matching IDs in the existing 434-model wearable baseline.
  Held-item geometry is unchanged. These batches do not add 121 new catalog items.
- No game integration, target-device validation or subjective art approval is claimed.

## Evidence

All paths below are relative to `build/dual-host/wear-r2/`. Immutable candidate manifests,
original logs, validation metrics, GLBs and PNGs are retained there. Evidence copies are also
under the EC2 project's `tools/nookipedia-model-production/evidence/wear-r2/`.

| revision | coverage | result |
|---|---|---|
| rev2 + rev3 | 11-asset pilot; rev3 repairs evidence/self-test harness only | 22 self-test assets pass; 310 unchanged files hash-bound to rev2; 6 pages and a missing-frame negative test reviewed |
| rev4 | c016-dressup-sit 43 + c017-skirts-sit 18 | 61/61 gates, 1,037 views, 27 pages, zero process errors; independent serialized GLB active-set check over 14 animations x 3 held states |
| rev5 | c018-umbrellas-hold 48 + c019-bags-hold 8 | 56/56 gates, 1,176 views, 21 pages and 21 clean page logs; all 5 stages exit 0; rebuilt GLBs match frozen originals 48/48 + 8/8 |

Rev4 candidate manifest SHA-256:
`c4d8d3eb7ff74c7ba8c2fc0c2bbf7959fcec6e96ee037d66662f1f5dd7f9cfdf`.
Rev4 evidence archive SHA-256:
`c356fbb625870cfa8f036c83bb1e98e5dcb875a51e9dbc05c91e4520166b7ad9`.
Rev4 report SHA-256:
`e6c7bf5f9be9b87fe96a635cca8a13bca5fa26bd69bb8536d965f8fcf9f95881`.

Rev5 candidate manifest SHA-256:
`c717621f8fda19a2a2bf80faaedb8fe6b01df32db01aad4495baa60a3bedb107`.
Rev5 evidence archive SHA-256:
`03238cafdb108a1bacb1f0f8c999a97df7919a5deffa59afd8e9e3a8934cd8af`.
Rev5 report SHA-256:
`64efc16b20270bd95d2b233b61c312fc3a659385501bb0cd8be00e26d4606600`.
The archive contains 1,470 hashed evidence files and is 71,428,088 bytes. Remote SHA-256
matched after upload. The four pilot held GLBs also match the original frozen manifests.

Additional rev5 checks compare all 56 state tables against the documented 14-animation
hold/hide contract. Hidden frames are compared to previously reviewed, same-engine pilot
frames without held items. PNG bytes are not identical: small edge differences affected at
most 66 of 262,144 pixels, with maximum channel mean error 0.00538 on a 0-255 scale.
The supplemental comparison requires changed-pixel fraction <= 0.001 AND channel mean
error <= 0.01; all 224 raw-visible diagnostic frames fail that same similarity criterion.
This evidence supplements the producer's original-image review; it does not alter the W gates.
Exact measurements and comparison code are included in rev5 evidence.

Producer rev5 review resolved the close-looking seated umbrella shaft using the original
`bat_umbrella_sit.png` and `bat_umbrella_sitside.png`, plus an analytic hairstyle-clearance
check (producer-reported minimum shaft clearance +21 mm, canopy +184 mm). This is additional
review evidence, not a new W9 hairstyle gate. Codex also opened both original images.
The remote frozen c018/c019 GLBs were independently compared against Mac evidence: 56/56
exact matches; see `rev5/remote-freeze-check.json`.

## Final producer records

Retrieved copies:
- [Final acceptance](../build/dual-host/wear-r2/final-handoff/WEAR_R2_ACCEPTANCE.md)
- [GameCode equipment handoff](../build/dual-host/wear-r2/final-handoff/EQUIP_HANDOFF.md)
- [Held-item page review](../build/dual-host/wear-r2/final-handoff/REVIEW.md)

The producer completed this round and is idle. Seated-batch metadata still contains the old
W1-W7 wording; the producer preserves frozen files and records the correction in
`requests/wear-r2/ERRATA_freeze_c016_c017.md`. The actual rev4 validation contains the seated
gates. Revalidate affected behavior if the r11 game rig pivots or poses change.

## Integration contract and limits

- Seated garments carry `Body_sit`, `LegL_sit`, `LegR_sit`. Activate the complete seated set
  and hide standing Body in sit/rest/swing/ride; restore standing meshes otherwise. Shared
  sleeves remain. Never show both variants or only part of the seated set.
- Each active state stays within 3,000 triangles; total stored geometry stays within 6,000.
  W8 tests seated clearance, W10 hand interaction, W11 thigh/hip coverage. W11 detects larger
  bare bands (about 3.3 cm); smaller seam issues require image review.
- Held ArmR stays within x [-0.6, 0.6], z [0, 0.05] radians. Hide the held mesh outside this
  envelope, or implement an independently validated held-arm override.
- Bags hide in seated states. Standalone umbrellas may remain in sit/rest with the hold pose.
  A seated garment takes precedence: in sit/rest use its arm contract (x -1.1) and hide all
  held items. Swing/ride hide held items in the tested contract.
- Original game sit arms and raw held poses remain diagnostic and can clip. Their renders
  are labelled separately. Baseline sleeve/raised-arm limitations remain optional polish.
- Game Code still owns equip/unequip, animation transitions, save/network state, UI,
  gameplay integration, and device tests. No implementation or release is implied here.

The local source checkout and unrelated work were preserved. No Git commit, push, deployment,
installation or global-memory update was performed for this validation round.
