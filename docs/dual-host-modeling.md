# Dual-host modeling and validation

Project workflow, revision 1, 2026-10-07. This extends the existing
`ec2-claude-orca` dispatch skill for this project only. It does not change that
global skill, agent settings, permissions, subscription, or engine installation.

## Ownership

| Owner | Work |
|---|---|
| Existing EC2 Claude Opus session, reached through Orca | Design, modeling skill improvements, builders, geometry/material choices, gameplay integration, interpreting actual images, and repairs. It owns the production files. |
| Codex on this Mac | Freeze/transfer coordination, exact-input checks, sequential local Godot imports, geometry tests, renders and regression tests; return original logs, metrics and images to the same Opus session. |
| User | Subjective art approval and target-device acceptance. |

All messages to Claude are in English.
Source, comments, paths and project documentation remain English. The game's UI
scope stays exactly **en, zh-CN, ja, es, fr, de**; do not add zh-TW or zh-HK.
Keep the existing Claude subscription, Opus model/effort, sandbox wrapper and
permission mode. Never substitute local Codex design decisions for an Opus repair
without an explicit handoff. Existing scale and asset rules still apply:
[scale and surfaces](../design/object-scale-and-surfaces.md),
[contribution rules](../CONTRIBUTING.md), and each candidate's modeling skill.

## Control and artifact transport

Task messages, feedback and goal changes use **Orca -> the existing remote
terminal -> tmux -> the sandboxed Claude wrapper**. Discover the environment and
runtime and read the terminal first; do not persist terminal handles as permanent
identities. Use the version-matched Orca CLI skill. Confirm actual acknowledgment
or work after a send: `accepted: true` alone is not proof. If input is queued,
inspect it and the current goal; do not repeatedly paste or blindly press Enter.
A goal is replaced only when the native condition and the working agent agree.

For this user-authorized project workflow, **SCP/SFTP may carry curated candidate
files and validation evidence between the two project directories**. This is an
artifact transport extension, not an SSH agent-dispatch route. SSH may inspect
files/hashes/processes. Do not launch another agent or render worker via SSH.
Never transfer credentials, signing settings, saved games, `.git`, `.godot`,
sessions, runtimes, dependency caches or the complete reference collection.
Reference images remain reference material, not shipping textures. Transfer a
specific permitted reference only when necessary and separately from a release.

## One candidate at a time

1. **PREPARING (Opus):** finish a bounded asset batch or integrated release. Stop
   starting EC2 render/import jobs for this candidate. Declare the exact file list,
   base commit, changed/untracked inputs, asset IDs, expected test commands and
   thresholds. Include builders, helpers, the current modeling skill, geometry
   validators and their self-tests, manifests and required game dependencies.
   Do not send only GLBs without their reproducible inputs.
2. **READY_FOR_LOCAL_VALIDATION (Opus):** hold the selected files still while
   sealing. Provide the manifest SHA-256 in the Orca message. A base commit is
   context; the manifest identifies uncommitted changes too. A changed validator
   is a new candidate and requires self-test/calibration evidence.
3. **RECEIVED (Mac):** transfer to a new `build/dual-host/<batch>/<revision>/`
   directory, never into the live checkout. Verify every file, the manifest hash
   from Orca, dependencies, disk space, engine version and the declared test plan.
   Missing dependencies mean blocked, never silently skipped checks.
4. **VALIDATING (Mac):** use a disposable work copy, one Godot job at a time.
   Keep the candidate immutable. Import with the exact engine build, run geometry
   and validator self-tests, render multiview/game-camera/lineup/placement images,
   then run the applicable integrated game tests. Preserve raw outputs and exit
   codes. Use new output directories so old images cannot satisfy a rerun.
5. **FEEDBACK_READY (Mac):** return `report.json`, metrics, full logs, hashes and
   actual PNGs, with candidate ID and per-asset findings. Transfer images to a new
   project-local evidence folder on EC2; a Mac absolute path alone is not usable by
   remote Claude. Send the evidence paths through Orca in English. Opus must open
   the images and name the views inspected, not rely only on a contact-sheet
   caption or Codex's summary. If remote image inspection is unavailable, visual
   review is blocked.
6. **REVISING (Opus):** repair the production source, seal a new revision and
   repeat affected tests. Never modify a frozen candidate or reuse the old pass
   for changed bytes. Do not resume the 639-item backlog during a release task.
7. **ACCEPTED_FOR_INTEGRATION:** deterministic gates pass and image review has
   evidence. Preserve distinctions between model-complete, wearable/rig-complete,
   placeable/integrated, reference-only, blocked and unattempted assets.
8. **RELEASE_CANDIDATE:** run game regressions against the integrated candidate.
   Before committing, compare the tested production inputs against the current
   working tree; changed inputs invalidate affected results. Retain Linux-specific
   checks where required. A Mac render is not proof of iPad performance or touch.
   Commit/push require user authorization for that release; they are not standing
   permissions granted by this document. Record the pushed SHA and verify the
   remote ref. Do not merge, deploy or install on a device implicitly.

There is no unattended scheduler or automatic cloud/local daemon in this version.
Closing this chat does not create monitoring. If the Mac is asleep/unavailable,
mark local validation pending and keep the candidate; do not fall back to parallel
EC2 software rendering or claim completion. EC2 may perform bounded independent
design work without changing a sealed candidate. Do not leave a `/goal` spinning
on a blocked local result: the coordinator records the state and adjusts it through
Orca when necessary, preserving the condition for resumption.

## Quality gates stay the same

- Same Godot release/build on both hosts; current baseline is
  `4.7.2.stable.official.ed1daf0bf`. OS binaries have different checksums, so record
  the binary and platform separately; do not demand identical executable hashes.
- Canonical 1 unit = 1 m, H = 1.30, class bounds, footprint, anchor, normals,
  winding, degeneracy, open edges, connectivity, materials and triangle budgets.
- Fixed camera, light, background, viewport and render method per test. Six asset
  views plus real game-camera and scale-lineup views. **Six views are not the six
  UI languages**. Both are required where applicable.
- Tabletop fit uses the real support region and rotation. Wall/ceiling models
  require implemented anchors. Clothing requires real rig/attachment checks and
  passing validator self-tests; pretty renders cannot override a failed gate.
- Opus examines original images and repairs visible defects. Subjective approval
  remains distinct from geometry and automated rendering checks.
- Record platform differences; exact Linux/Mac pixels are not required. A broken
  silhouette, clipping, unreadable UI or failed deterministic assertion is still
  a failure. Real iPad checks remain a separate release condition where required.

## Tools included in this revision

`scripts/model_handoff.py` uses Python 3.9+ standard library only. It does not
connect to EC2, send prompts, install tools, modify Git, generate models, or turn a
render pass into art approval.

### Seal a reviewed file list on the producer

Place one relative **file** path per line in `files.txt`. Review it before use;
do not list the whole home directory or recursively include `tools/`. For an
integrated game rendering candidate, start from `git ls-files game` and explicitly
add new untracked game assets. For a model candidate add only the required builder,
skill, validator and spec files from its lab. Include every dependency and record
the chosen test commands in an English `LOCAL_VALIDATION_REQUEST.md` in that list.
The tool rejects traversal, symlinks and common private paths but is **not** a
general secret scanner: a human/agent must review the allowlist.

```sh
python3 scripts/model_handoff.py seal --root . \
  --files-from /absolute/path/files.txt --base-commit "$(git rev-parse HEAD)" \
  --output /absolute/project/path/build/dual-host/batch-r1/candidate
```

The printed SHA-256 identifies `manifest.json`. Send that value through Orca.
Sealing detects edits during copying but is not an atomic filesystem snapshot;
producer acknowledgment that the selected inputs are held still is required.
An interrupted seal is not ready for transfer. Use a new revision directory.

### Receive and verify on the Mac

Transfer the candidate directory with SCP/SFTP into a fresh local project output
directory. Do not overwrite the checkout, use `rsync --delete`, fetch private
runtime trees, or transfer Linux import caches. Then:

```sh
python3 scripts/model_handoff.py verify \
  --candidate /absolute/path/candidate --expected MANIFEST_SHA256_FROM_ORCA
```

### Run the integrated game render checks on the Mac

```sh
python3 scripts/model_handoff.py render \
  --candidate /absolute/path/candidate --expected MANIFEST_SHA256_FROM_ORCA \
  --output /absolute/path/new-local-result \
  --godot /Users/xiaoyi/Applications/Godot-4.7.2.app/Contents/MacOS/Godot
```

The runner imports, runs the existing six-language `capture_tour.gd`, then the
three `dock_tour.gd` viewport cases sequentially with desktop OpenGL. It preserves
full logs, exit codes, elapsed times, screenshots and evidence hashes; it requires
success markers and fails on script errors, missing screenshots or changed input
files. Each stage has a timeout. A host-local lock refuses simultaneous calls.
If interrupted abnormally, check for live processes before manually removing a
stale lock; never blindly remove it to launch another renderer.

The disposable work copy gets an `override.cfg` solely to put `user://` in a
unique `LanternLane-validation/<run-id>` application-data directory. This avoids
using the player's saves. Record that test-only override. The desktop sandbox
must allow this isolated application-data location and window/GPU access. Never
disable the sandbox or alter the real game settings to work around denial.

Keep the Mac logged in, unlocked and the validation window visible. In the first
real run, an obscured window waited at `frame_post_draw`; raising the existing
validation window allowed screenshots to continue. The coordinator may use the
computer-use tool to select the exact Godot app path and raise that window. Do not
launch another copy by an ambiguous app name, minimize the active render, change
OS security settings, or call a stalled run passed. The timeout remains in force.

This runner covers **integrated game rendering**, not all model acceptance.
For model-only batches, run the candidate's existing geometry/self-test/multiview
scripts from a disposable copy using the reviewed commands in its request. Reuse
the pilot's tested scripts; do not invent a second modeling engine. Return their
raw evidence with the same candidate ID. Unit, repository, audio and real-client
network checks still need their existing runners and result records; preserve
remote results only if they tested the same inputs. Font checks that were skipped
for missing dependencies do not count as passing.

## English messages for the existing Orca session

Producer request (fill every placeholder before sending):

```text
Use the project-local dual-host modeling workflow. Keep creative/modeling and
repair ownership in this existing session. Prepare candidate <batch/revision>
for the current authorized scope only; do not expand the backlog. Freeze a
reviewed, complete input file list and report READY_FOR_LOCAL_VALIDATION with
the manifest hash, engine build, base commit, asset IDs and exact checks.
The Mac will run heavy Godot imports/renders and return raw logs and actual
images. Do not run a duplicate EC2 render for this candidate. Keep the six UI
locales en, zh-CN, ja, es, fr, de and every existing quality/authorization gate.
Do not claim local/device/visual acceptance before receiving that evidence.
```

Feedback (success and failure both use this shape):

```text
Candidate <manifest hash>; local result <result hash>; evidence is available at
<absolute EC2 project evidence directory>. Automated result: <pass/fail/blocked>,
with <exact counts and failing asset IDs>. Open <explicit PNG paths> and inspect
the multiview and game-camera results yourself. Record the inspected views and
remaining issues. Fix <specific defects> in source and seal a new revision if
needed. Do not treat these Mac results as iPad validation. Keep the current
release scope and authorization; report the next handoff state.
```

## Adoption and verification record

The first implementation is local tooling plus this contract. It does not
interrupt or replace the already-running EC2 release test. Adopt at the next
explicit candidate boundary; if transferring an in-flight render, first verify
the Mac copy starts successfully, then stop only the matching remote test job.
Do not restart Claude, resume the paused code lane, or erase pending outputs.

Local engine discovery verified Godot 4.7.2 with the build string above. The local
checkout at implementation start was revision 2 (`b0f1fb7`); it is not the newer
EC2 130-model release. Validation of this workflow against that baseline must not
be presented as acceptance of the newer release. See
[the workflow validation record](dual-host-validation.md) for actual results.
