# Lantern Lane project instructions

Read `CONTRIBUTING.md` for project rules. Keep documentation in English.

## Release and session recovery

For publishing, installation, server upgrades, release status, or resuming a release, read in order:
1. `docs/release-status.md` — latest recorded release, exact candidate and evidence, pending acceptance.
2. `docs/release-workflow.md` — the standard iPhone + iPad + HK release procedure and private inventory location.
3. The private operational README referenced there — destinations, deployment configuration and rollback facts; refresh changing facts live.

These release records supersede older release/install/server claims in `HANDOFF.md`, but do not supersede its unrelated development tasks. Do not infer the shipped version from the checkout, newest directory, or conversation memory. Do not ask the user to repeat information available in these files.

A user request to publish an accepted version invokes the documented three-target release scope unless narrowed by the user. An explicit publication request authorizes that release; do not request the same approval again. This is a workflow definition, not permission to publish unsolicited future versions. Commit/push remain separately authorized.

Use the existing remote production owner and frozen-candidate process in `docs/dual-host-modeling.md` for source changes. Do not replace the owner or deploy an unverified local checkout. Update the release status and private operational record after every attempted release, including partial failures, so a new session can resume safely.
