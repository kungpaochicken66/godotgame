# EC2 production workflow

How a title is taken from a short idea to a frozen, playable candidate on the EC2 host: who does what, how each
collaborator is started and checked, the limits of the host, and what the work so far has taught. Source: the owner's
handoff `msg_a373288c73d9` (2026-11-24). This page is the standing brief; a new assignment can be short because the
rules are here.

The division of work between this host and the Mac, and the trials in progress, are recorded once, in
[../dual-host-modeling.md](../dual-host-modeling.md), "Division of work between EC2 and the Mac".

## Who does what

Fable owns the workflow and is the single contact for requirements, decisions and candidate handoffs. It starts from
the owner's one or two sentences, decides what makes the episode distinctive and what the child gets to do, and
carries it to a locally committed, playable candidate with the coding and the EC2 checks substantially complete.

| Collaborator | Standing setting | Given |
|---|---|---|
| Fable | high effort | Original design; hard creative or technical decisions; judging the key playable moment; the handoff-or-repair decision; the review points |
| AGY Orchestrator (Neon), the principal builder | Orchestrator profile, high effort | Most implementation, scene and asset work, render iteration, targeted tests, routine documentation, repairs. Before a handoff it plays the normal route, fixes evident defects, and prepares a short representative capture, the candidate revision, and a list of known issues and checks that need the target hardware |
| Opus | high effort on every assignment, resumed ones included | Used selectively: a bounded problem where it adds clear value |
| Haiku | default effort | The recurring read-only host check below |

Fable spends its own quota on decisions that change the player's experience. When a material flaw remains after the
builder's pass, Fable names the single most important change and the builder repairs it; another Fable look is asked
for only where creative judgment is still needed. Once the experience meets the bar, Fable freezes and hands off
(`rotation.md`, "Standing direction").

## Starting the builder, and proving which model started

The builder runs as an Antigravity CLI (`agy`) terminal in Orca. Start it with the Orchestrator selector and **no
effort flag**:

```sh
orca agent launch --agent antigravity --worktree path:/home/yy834/projects/godotgame --surface terminal \
  --model gemini-pro-orchestrator-neon --prompt "Read the brief at /abs/path/BRIEF.md and carry it out exactly. ..." --json
```

Then prove the start from the session itself, and record all five facts with the task:

1. **Handle**: `result.outcome.handle` of the launch.
2. **Selector and profile**: the newest `~/.gemini/antigravity-cli/log/cli-*.log` must say
   `Resolving model gemini-pro-orchestrator-neon` followed by
   `Propagating selected model override to backend: label="Orchestrator (Neon)"`.
3. **Effort**: the terminal's status line (`orca terminal read --terminal <handle> --screen`) must read
   `auto · Orchestrator · Gemini 4 Neon · high`. High is the profile's own effort.
4. **First tool action**: the first `Monitor agy_tool_safety FINISHED` line in that log gives its time.
5. **Task**: the brief's path.

What does not prove an Orchestrator start (each of these happened on 2026-11-24):

- **A tab title.** The tab named "agy · Orchestrator (Neon)" ran plain `gemini-4-neon-high`.
- **A banner or status line reading "Gemini 4 Neon (High)" or `auto · Gemini 4 Neon · high`.** That is plain Neon.
  The Orchestrator line has the word `Orchestrator` in it.
- **Passing `--effort high` with the Orchestrator selector.** `agy` answers `--effort is not supported for model
  "gemini-pro-orchestrator-neon"`, drops the whole model override, and starts plain Gemini 4 Neon (High) without
  stopping. `orca agent launch --effort` passes the flag through, so leave it out.
- **The builder's own sentence about its model.** Under the Orchestrator profile it says "Gemini 4 Neon, reasoning
  effort: High", the same words plain Neon uses.

The `agy` sign-in is not available inside Fable's own sandbox (`agy models` fails there by design); the session's log
and screen are the evidence.

## Briefing and review

- One bounded slice per brief, written as a file beside the evidence it will produce
  (`build/dual-host/world-classics-odyssey/evidence/<title>/builder-NN/BRIEF.md`). It names the goal and what done
  looks like, the one checkout to work in, the files that may be edited, the host limits below, and the report.
- The builder leaves its changes uncommitted, writes `REPORT.md` beside the brief, and tells Fable by Orca mail.
  Fable reads the frames and the diff, decides, and commits. Messages between agents go by `orca orchestration send`
  and `reply`, never by typing into another agent's terminal.
- An agent started by Orca reads its mail with `orca orchestration check --terminal <its handle>`. Fable's own
  environment still carries the handle of an earlier Orca runtime, so a bare `check` shows nothing and no mail wakes
  the session: on 2026-11-24 three messages, one of them the owner's decision lifting two holds, sat unread for
  about six hours. Since 2026-11-25 the coordinator's mailbox watcher
  (`build/dual-host/world-classics-odyssey/operations/fable-mail/mailbox.py watch`, read-only) runs as one
  background task of Fable's session; it ends when mail appears, and Fable starts it again after handling the mail.
- A session Fable started and no longer needs is closed with `orca terminal close --terminal <handle>`. Sessions
  started by anyone else are left alone.

## Limits of the host

- 3.7 GB of memory, with swap often above 80% used. One Godot process at a time, always through
  `flock ../godot.lock`; look at `free -m` before a rendered run.
- **Two clients do not fit beside the other sessions on this host.** Measured on 2026-11-25 with
  `scripts/memwatch.py` during The Snow Queen's solo tour: one headless client peaks at 495 MB, and the host's
  available memory fell from about 1,080 MB to 583 MB while it ran. A second client would leave under 100 MB. The
  first two-client run of that title was stopped by the host for low memory. The owner's decision of 2026-11-25
  (`msg_45d31acc7ab6`) covers this case: hand off the exact candidate and name the two-client run as the validation
  still pending on the Mac. To try again, measure first: `python3 scripts/memwatch.py --log /abs/log.jsonl --
  <command>` samples Godot and the host every two seconds, and with `--floor-mib` it stops the command before the
  host runs short.
- Idle agent sessions cost 300–400 MB each. Close finished helpers; do not leave probes open.
- Disk: 77 GiB, 6.2 GiB free on 2026-11-24. A frozen candidate with its bundle is about 0.4 GiB, a packaging export
  0.23 GiB, and a title's evidence 0.1–0.3 GiB.

## The recurring host check (Haiku)

An Orca automation, `EC2 disk and Orca health (Haiku)` (id `03e8e7ad-76d5-4993-a9aa-01a79b2da292`), starts a fresh
Claude Haiku session at 00:17, 06:17, 12:17 and 18:17 UTC in this worktree. It runs `scripts/ec2_health.py` once and
reports three things separately:

| Section | What is read | Needs attention when |
|---|---|---|
| Disk | The root filesystem's free space | Under 4 GiB (warn: clear space before the next freeze) or under 2 GiB (critical: a freeze cannot complete) |
| Orca runtime | `orca status` (service, version, runtime id, ready, reachable), the runtime descriptor that matches the running runtime, a connection to its listener, saved paired environments | The service is down, the runtime is not ready or reachable, or its listener refuses a connection |
| Agent mail | The newest stored message, its time, and the unread count | The mailbox cannot be read |

The runtime, listener and paired environments are discovered on every run. A managed activation replaces the
runtime and leaves the old descriptor behind: on 2026-11-24 the running runtime was described in
`~/.orca/orca-runtime.json` (`ws://127.0.0.1:6800`) while `~/.config/orca/orca-runtime.json` still named a retired
runtime on port 6768. The script reports the retired one and does not use it.

Haiku sends Fable one Orca message when a section changes state (a failure or a recovery) and, while something stays
wrong, one reminder a day. A healthy run sends nothing. The check never restarts, upgrades, re-pairs or sends a test
message. Its only effects are one line appended to `build/dual-host/ec2-health/history.jsonl` (how the next run knows
what changed) and closing its own terminal three minutes after the run, so that four runs a day do not leave four
idle sessions.

```sh
orca automations runs --id 03e8e7ad-76d5-4993-a9aa-01a79b2da292        # history
python3 scripts/ec2_health.py                                          # the same report by hand, nothing written
```

First real run: 2026-11-24 15:54:24 UTC, Haiku 5.5, about eight seconds. Disk `/dev/root` 6.2 GiB free of 77.3 GiB
(92% used): OK. Orca 1.4.273, runtime `d6fd994b` ready and reachable, listener `ws://127.0.0.1:6800` accepting: OK.
Mail: newest `msg_604e35a5dbfe` (15:44:48 UTC), none unread: OK. No message sent. A second run by hand at 16:18:32
UTC (all OK) proved the cleanup: its terminal closed itself at 16:21:34. Next scheduled run 18:17 UTC.

## Model ledger

One row per meaningful milestone: the task, who did it, what came back, what rework could have been avoided, and
usage where the tool reports it. Change the workflow when the rows support it.

| Date | Task | Owner | Result | Avoidable rework | Usage |
|---|---|---|---|---|---|
| 2026-11-23/24 | The Snow Queen: five worlds, figures, journal data (five parallel assignments) | Opus, high | All five delivered and merged; scenery verifiers pass | Camera under stair treads and floating blob shadows found only in Fable's picture-book review: ask each scenery author for player-camera frames along the walking route, not only beauty shots | Three assignments hit the weekly limit and were resumed |
| 2026-11-24 | The Snow Queen: rules, stage, visit, tests, 281 strings into five languages, polish from 53 frames | Fable, high | Plays tram to tram in six languages; single-process checks pass | Translating and render iteration are builder work; Fable did them because dispatches were paused | Not reported |
| 2026-11-24 | Flowing Sand River M1 discovery feedback, source only | AGY, plain Gemini 4 Neon (High), selector `gemini-4-neon-high` | Finished, uncommitted: 3 new and 9 modified files, six-locale and font checks pass; no Godot run in its sparse checkout | Started under a tab titled "Orchestrator" without the Orchestrator profile | Not reported |
| 2026-11-24 | Builder start for Snow Queen slice 01 with `--effort high` | AGY | Fell back to plain Neon; closed after 26 seconds, nothing written | One relaunch; rule added above | Negligible |
| 2026-11-24 | Snow Queen builder slice 01: eleven unseen frames in English, Chinese and German, plain repairs; then one follow-up named by Fable (summer clothes at home) | AGY Orchestrator (Neon), high | 56 minutes for both parts. Precise frame verdicts; found a pigeon floating behind the cage's rail (Fable had passed that frame) and Gerda's winter boots in the summer ending (Fable had missed it in 53 frames); repairs of 2 and 17 lines, each re-rendered; rules 204/0; nothing outside its permitted files | None. It reports a flaw outside its brief and leaves it alone, which is the behaviour to keep asking for | Not reported by the tool |
| 2026-11-24 | Crusoe r2 wreck camera (Mac finding): reproduce at the recorded poses, find the cause, repair, add tour checks | Fable, high (the Mac packet reserves it for the title's original owner) | Two causes found from the Mac's stage readbacks before any render; one fix each; 352 tour checks pass | The raft regression shipped in r2 because the hold's camera rule was added after the raft frames had been reviewed and they were not rendered again: after any camera change, re-render every set piece of that zone | Not reported |
| 2026-11-24 | Host check, first run | Haiku 5.5 | Correct three-part report in eight seconds | None | About $0.01 API-equivalent |

## Checkpoints kept for other work

- **Flowing Sand River M1 discovery** (not a World Classics title; recorded here because this workflow owns the
  builder). Isolated checkout `/home/yy834/projects/lantern-agy-flowing-sand-m1-discovery`, branch
  `agy/flowing-sand-m1-discovery`, baseline `443ebad2a1953a81b4468ce7444e630dfd5ce07c`, tree
  `c6dfa4746b06e95a9a007a01bbcda39a4bfedf29`. No candidate commit. On 2026-11-24 at 15:50 UTC all twelve working-tree
  files matched the SHA-256 manifest in the session's own report (read-only comparison). Its session
  (`agy --conversation=6dacfcd2-e2f3-4b93-a255-cb54d28079a8`) ended at 15:49:11 UTC: Orca's daemon log records an
  operator close of it and of three other idle terminals of the main checkout within fourteen seconds. Fable sent no
  close command before 15:51. The files were unaffected (same hashes at 15:56 UTC). It is plain-Neon work and does not count as an Orchestrator start. Nothing in
  that checkout is to be changed, tested again or given a second writer until its next slice is assigned through
  the procedure above.
