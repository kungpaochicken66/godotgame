# Dual-host workflow validation

Scope: the project-local handoff tooling, Mac render runner, and the subsequent
frozen EC2 candidate round-trip and USB iPad installation. Work started on
2026-10-07 from local `b0f1fb7`.

## Tool checks

- `python3 scripts/test_model_handoff.py`: 10 tests passed. Covers corrupted,
  missing/extra and wrong-manifest inputs, source/copy independence, private and
  traversal paths, symlinks, executable bits, overwrite refusal, and refusal to
  accept success text when an engine error or nonzero exit is present.
- `python3 scripts/check.py`: passed; baseline game 193 messages, preview 133,
  six locales, font coverage of 624 characters, English sources/paths and links.
- `git diff --check`: passed.
- EC2 reports Python 3.10. SHA-256 uses standard-library block reads rather than
  the Python 3.11-only `file_digest`; candidate verification and the 10 tool tests
  pass after that compatibility correction. No Python installation was requested.

## Real Mac run

Candidate manifest SHA-256:
`1ea3e2a89fb42be01324ee879133581da3e747b91ac5d646c3c55ef10e7a8970`.
It contains the tracked `game/` files from baseline `b0f1fb7`, not the newer EC2
130-model candidate. Engine: `4.7.2.stable.official.ed1daf0bf`; renderer log:
OpenGL 4.1 / Apple M1 Pro. Runs used isolated work copies and user-data names.

The final tool run is in the ignored project directory
`build/dual-host/workflow-check-20261007/mac-result-2/`. It produced 52 PNGs,
complete logs, stage timings, candidate/engine/evidence hashes, and `report.json`.

| Stage | Engine exit | Assertions | Strict workflow result |
|---|---|---|---|
| Import | 0 | Import completed | PASS |
| Six-language tour | 0 | `TOUR PASS: 0 failures` | FAIL: engine resource error at exit |
| iPad layout | 0 | `DOCK ipad PASS: 0 failures` | FAIL: same error |
| iPad Air layout | 0 | `DOCK ipadair PASS: 0 failures` | FAIL: same error |
| iPhone layout | 0 | `DOCK iphone PASS: 0 failures` | FAIL: same error |

All four rendered stages logged `ERROR: 1 resources still in use at exit` and a
warning about two leaked ObjectDB instances. The runner returned nonzero and
recorded `status: failed`. This is an observed baseline finding for Opus to assess
against the current candidate, not evidence that the newer release has the same
defect. No model/game code was changed locally to hide or bypass it.

An obscured window stalled screenshot progress in the first run. Raising the
existing validation window resumed it. In the second run the tour took 56.64 s;
the iPad Air layout also needed the window raised (199.41 s), while the other
layout runs took about 27 s each. These are workflow observations, not device
benchmarks or a claim of guaranteed acceleration for every candidate.

Codex inspected the generated modeled-furniture scene image to confirm actual
geometry and UI rendered. Full Opus visual review, model-only geometry/rig batch
validation, two-host candidate round-trip and actual iPad acceptance are not
established by this baseline run. No global skill/settings were changed and no
workflow commit or push was performed here.

## Frozen EC2 candidate and iPad installation

EC2 sealed 381 game files (tracked and required untracked inputs), excluding
imports and private signing settings. Mac verified the immutable manifest
`955dcc5c0f380d96591fb5eb6c95e9551b67d1629b0b4d53ce4db9464565a03f`.
This candidate includes the 130 production furniture models and eight activities.
The producer also verified the same archive using Python 3.10 and the r2 tool.

Evidence: `build/dual-host/ipad-r1/mac-result/` and `mac-evidence.tar.gz`.
The archive was transferred back to the same EC2 project for producer review.

- Import passed in 4.53 seconds.
- Six-language tour: zero assertion failures, 62.42 seconds.
- iPad / iPad Air / iPhone layouts: zero assertion failures, about 32 seconds each.
- Full logic suite: 8,057 checks, zero assertion failures, exit 0.
- Eight-activity rendered tour: zero assertion failures, exit 0.
- 66 actual screenshots were produced; the modeled room image was inspected locally.
- All gameplay test processes reported the same pre-existing shutdown resource
  error, so the strict report remains **failed**. Verbose output identifies
  `AudioStreamWAV`, `AudioStreamPlaybackWAV`, and
  `res://assets/audio/meadow_lanterns.wav`. No gate was relaxed.

An independent export work copy excludes the test-only `override.cfg`, preserving
the installed application's normal save location. Xcode build, strict code-sign
verification, and USB installation to the paired iPad Air 5 succeeded. Exported
and bundled PCK hashes match:
`576a62384f5d5dab60a7d35eddd59a2b55dae49d7abce8f5c5892cc476e72ffc`.
The first launch attempt was denied because the iPad was locked; user unlock is
pending. Physical touch, frame rate, and visual acceptance remain unverified.
Build/install/launch logs are `build/ios/revision3-*.log`.

Producer screenshot review completed. Activity landmark labels overlap one
another and crop beneath the top HUD, including the Chinese view; this remains
a known visual limitation. The producer's bounded probe reproduced the exact
music shutdown error and eliminated it by stopping playback, releasing streams,
and allowing one audio mix cycle before quitting; no such patch was applied to
this immutable candidate.

EC2 created commit `57dbe1f7f957b35059241c1f5701f1c46b315b06` before receiving
the coordinator's hold notice. A read-only hash comparison confirms all 381
candidate inputs match that commit. The producer reported push failure due to
missing credentials; a live `git ls-remote` confirms GitHub main remains
`b0f1fb7964bd529ac7c8ebfd431c9c93aab0d648`. Further commit/push actions are
paused after automatic approval review rejected the finalization message.
EC2 has two subsequent documentation-only edits, in `HANDOFF.md` and
`docs/validation.md`. Local workflow changes remain uncommitted.

Follow-up: the user explicitly re-authorized commit/push. The two documentation
edits became `f26f9c88476aa3980445d842dd8e2af5e4b11ce6`; all 381 game inputs
still match the sealed candidate. EC2's existing `gh` login has owner access;
using its credential helper for one command resolved the earlier plain-Git
authentication failure. The push succeeded, and an independent live
`git ls-remote` confirmed GitHub main at `f26f9c8`. The original GameCode session
resumed, read the current handoff and clean EC2 tree, and is ready for the next
development instruction. The Mac working tree's workflow additions remain
uncommitted and were not included in this release.

## Wearable baseline validation, 2026-10-07: wear-r1a

The original EC2 Modeling session and this Mac completed the 194-item batch
using the project dual-host contract. Production modeling/repairs and original
image review stayed with EC2; the Mac ran immutable disposable candidates,
validator self-tests, geometry checks, GPU views and contact sheets sequentially.

- rev1 manifest: `608dcbd6d9def03ec6db3136643dfbb5031fcab733cc62e3ce0246ad0d3b3136`.
  Self-test passed. c003 dress-up 50/50, c004 headwear 35/48, c006 socks 48/48,
  c007 accessories 48/48. All 2,134 views and 50 sheets were produced. Twelve
  crowns failed penetration/hair-cap gates; cat-cap ears failed attachment.
- rev2 manifest: `ec83535ab456816a31015893a0adb69816d3c5ccbff1f8b1521d2f78b863e8e8`.
  Self-test passed; headwear 47/48. The original failures were repaired, but the
  shared hood-ear change introduced a bear-cap penetration regression. Initial
  sandboxed GUI starts aborted; their logs remain intact. A desktop-authorized
  render-only retry produced all 528 views and 12 sheets with clean process exits.
- rev3 manifest: `3bf2e493cd49355480a08c5850b83c99a923f4004be338720c63685ad282cddc`.
  Self-test and all 48 headwear assets passed. All 528 views and 12 sheets exist;
  every process exited zero with no script errors. Repairs also corrected crown
  spike orientation and protruding helmet decoration found in actual images.

The producer verified the returned evidence hashes, opened all final c004 sheets
and pose pages plus repair closeups, and froze 194 models: c003/c006/c007 from
byte-identical rev1 inputs and c004 from rev3. No threshold was loosened. Local
raw evidence is in `build/dual-host/wear-r1a/rev{1,2,3}/evidence/`; the matching
archives were transferred to the same EC2 project's
`tools/nookipedia-model-production/evidence/wear-r1a/rev{1,2,3}/`.

Acceptance is limited to the declared idle/walk baseline. Rigid skirts still
intersect bent legs in sit/swing; some raised-hand poses overlap hats and masks.
These limitations remain recorded for subsequent model/integration work. This
is not game integration, all-pose clearance, subjective user art approval, or a
target-device acceptance. The remaining 240 older wearable models still require
v3 revalidation. No commit, push, deployment or installation was performed in
this continuation.

## Wearable baseline validation, 2026-10-08: wear-r1b closure

All 240 older wearable references were revalidated under the same v3 gates.
Together with wear-r1a, all 434 eligible clothing references now have frozen
model/rig evidence for idle and walk. This does not make them game-usable.

- rev1 manifest: `ac059f2f1b5677d58f51ae2ee20d4164f0c9280a2abbb7cb846494cac9e91aab`.
  Self-test passed. Tops 49/49, bottoms 50/50, bags 48/48; shoes 24/43 and
  umbrellas 49/50. All 2,640 views and 66 sheets were produced without process
  or script errors. The 19 shoe failures were heel tabs and sandal straps cutting
  through ankle skin; the ladybug umbrella exceeded the 3,000-triangle budget.
- rev2 manifest: `a772fe806f317d76afe855ce72626a5577d79c69bdf81aaccae7035765228e90`.
  The producer changed only the shoe and umbrella builders plus equipment
  handoff among common inputs. Self-test, all 43 shoes and all 50 umbrellas
  passed. All 1,023 views and 26 sheets exist; completed-run processes exited
  zero without script errors. An earlier Mac harness startup failed because its
  log directory was absent; that failure was retained, and acceptance uses a
  complete fresh-work-copy rerun. Frozen candidate bytes did not change.

The producer verified every returned evidence file, inspected all 66 rev1 pages
and three closeups, then all 26 rev2 pages and five closeups. Empty image-load
responses were excluded and reopened; a durable page checklist records actual
successful inspections. c010/c011/c013 were frozen from rev1, and c012/c014 from
rev2. An independent read-only check compared all 434 frozen GLBs and nine
validation files on EC2 with their Mac evidence: **443 matches, zero drift**.
The check is `build/dual-host/wear-r1b/final-freeze-verification.json`.

Evidence archives are retained locally and in the corresponding EC2 project
evidence folders. rev2 archive SHA-256 is
`9b58ab895bdc784841aed3824cc0539c691d04a005c9178dd0052eee5404827a`;
report SHA-256 is `b9cdbc1cc3319c33ed79c29dca851f9b10c6245a2357288d7b53cc0ff5a5b864`.
The final equipment handoff and producer review are copied under
`build/dual-host/wear-r1b/final-handoff/`. Retired v2-only batches remain immutable
and must not be used for integration. BACKLOG and COVERAGE generator prose was
corrected so stale pending counts cannot reappear on regeneration.

Remaining usability work is explicit: skirts/dresses need Body_sit variants
before unrestricted seated activities; umbrellas need a right-arm hold pose or
temporary hiding during raised-arm actions; ten hand-held bags need equivalent
pose handling. Sleeved tops have a reviewed shoulder step in raised-arm poses.
Wear-r2 is the proposed model-only sitting-variant candidate. Game equipment,
the 42 pending furniture records, device validation and human art approval
remain separate. Nineteen references remain blocked under existing project
rules. No commit, push, deployment or device installation occurred in this run.

## Source preservation (2026-10-25)

The Mac coordinator helpers are now prepared for Git alongside the workflow and release records. `python3 scripts/test_model_handoff.py`:10/10 PASS. `scripts/tvos/` preserves the two byte-identical export helpers used in the accepted Apple TV r5 package, the device-debug XCFramework skeleton, and an engine patch reproduced against the three original files with exact byte equality to the tested engine. Both Python helpers parse successfully. No signing presets, private configuration, reference collection or build products are included. The Siri Remote follow-up and final integrated repository checks are tracked separately in the release record.
