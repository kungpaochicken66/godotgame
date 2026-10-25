# Standard three-target release

## Meaning and entry point

For this project, “publish the accepted version” means install the same signed universal app on the user's iPhone and iPad, and synchronize the existing HK town server with that accepted candidate. The user may narrow this scope. A publication request is authorization for this bounded release; it does not authorize Git commit/push, unrelated services, new infrastructure, a host reboot, or future releases without a request. Preparing a candidate or accepting a visual review alone is not a publication request.

Read [release status](release-status.md) first. Use its candidate and evidence, not whichever source directory looks newest. If more than one accepted candidate exists and the intended version is unclear, resolve that version before side effects. A disconnected device is a resumable installation gate, not permission to claim installation or silently drop a target.

## Private operational source

On the current Mac, the private operations directory is:
`/Users/xiaoyi/ai-agent-kit/services/lantern-lane-hk/`

Read its `README.md` for inventory, deployment contract, active release and rollback. Read `release-targets.json` for device identifiers, host alias, bundle ID and local tool locations. Verify devices with `xcrun devicectl list devices`, the server's current symlink/service state, installed tool versions and available disk space. Inventory is a discovery hint, not proof of current connectivity.

Private deployment settings are in `private/deployment.json` there. Copy this file directly into an ignored disposable export copy; never print its contents or put endpoint/invite values into public docs, command arguments, logs, source or Git. Do not move the server invite into the public server pack. Missing inventory/configuration should be reported accurately, not reconstructed from guesses.

## Candidate and packaging

1. Follow [dual-host validation](dual-host-modeling.md): immutable manifest-verified candidate, relevant regression evidence and author image review. Reuse evidence only for byte-identical inputs; record exactly what was reused. Do not rerun broad rendered suites merely because the session changed.
2. Create a new `build/dual-host/<candidate>/<revision>/device-install/` directory. Preserve the sealed source; use a disposable `work/` copy. Remove validation-only `game/override.cfg` so the installed app retains its normal save location.
3. Reuse the existing private export preset's bundle/signing configuration. Keep universal device families `[1, 2]`. Copy both validated native frameworks from the previous accepted build into `game/ios/plugins/photo_library/`: `photo_library.debug.xcframework` and `photo_library.release.xcframework`. Their directory is nested; a glob directly under `ios/plugins/` misses them. Reuse only after confirming native source/ABI compatibility.
4. Inject existing private deployment settings into `work/game/private/deployment.json` (0600). Export the `iPad` preset with the pinned Godot engine to an absolute `ios/LanternLane.xcodeproj` path. Treat `Invalid plugin config` as a release failure, even if export exits zero.
5. Run `scripts/ios_photo_purpose.py <ios-directory>`. Build Debug for generic iOS using the existing signing identity and a dedicated derived-data directory. Do not print signing secrets or invent a team.
6. Verify strict codesigning, expected bundle ID, `[1, 2]`, linked PhotoLibrary native symbols, add-only Photos permission and six localized permission files. Verify the bundled PCK matches the exported PCK and includes the private settings without printing them.
7. Build the server PCK from a separate public export copy without private settings or test drivers. Verify its digest and absence of actual private endpoint/invite bytes. Smoke-test locally. Never run editor import or compile on HK: a prior resource import exhausted that host's memory.

## Install and synchronized server update

1. Check both devices are connected and unlocked. Install the exact same signed app over the existing bundle ID, preserving app data. Save per-device installation and launch JSON and check actual outcomes. If Apple reports a tunnel error, retry once; if it persists, ask for replug/unlock and continue unaffected work. Resume only incomplete steps after reconnection.
2. Compare network protocol and save schema to the active server. Protocol changes require a coordinated client/server update. Check rollback/save compatibility before changing the active release. Do not launch incompatible clients against the old protocol and call that a functional failure.
3. Upload only the digest-verified public server pack into the existing staging directory. Reuse the existing bounded release deployment procedure: create an immutable release, stop only the game service, validate and fsync a timestamped town backup, record previous release and saved item IDs, atomically switch the current symlink, then start the service. Preserve proxy, firewall, credentials and other services. Keep the prior release and backup.
4. Save deployment outcomes. If a post-cutover gate fails, report the failure and use the recorded compatible rollback; never overwrite new player progress by blindly restoring an old save. Preserve the current state first if recovery needs a restore. Do not repeat a completed cutover merely because a device installation failed.
5. Launch both successfully installed apps. Run `scripts/remote_check.py --use-private-config --game <private-work/game> --godot <pinned-engine>` for real WSS dual-client synchronization, movement, reconnect, and wrong/missing invite rejection.
6. Run its `--phase mark --state-file <task-marker>` flow, restart only the game service, then `--phase verify` with the same marker path. Confirm persistence and cleanup. Inspect final service state, retain all pre-update item IDs, and ensure test markers are gone. A health URL alone is not multiplayer acceptance.

## Completion and next-session handoff

Write per-target outcomes, exact manifest/PCK hashes, evidence paths, active server release, backup and rollback pointers, and remaining gates. Keep private operational details in the private directory. Update [release status](release-status.md) after partial as well as successful releases; never overwrite an incomplete target with an overall PASS. Record approval as applying to that specific release, not future releases.

Install/launch success and native plugin linkage do not prove real touch, audio or writing to Photos. Ask the user to verify those on-device and record their actual answer. Do not mark them passed from Mac screenshots or a build result.

No autonomous scheduler is created by this procedure. A new chat opened in this project reads `AGENTS.md`; a chat outside this project needs the project path or this document attached before it can discover the workflow.
