# Mac and EC2 production roles

Use these defaults for Lantern Lane and as the starting point for future projects on the same Mac and EC2. Resolve model selectors on the actual host when opening or resuming a session. A scheduling decision belongs to one owner at a time.

| Host and role | Model | Responsibility |
| --- | --- | --- |
| Mac production dispatcher | AGY Gemini 4 Neon (High) | Read the existing queue, choose the next eligible action, respect resource and review dependencies, and record the result. Keep the current run and pending worker handoffs across wakes. |
| Mac implementation and native verification | AGY Orchestrator (Neon), high effort | Build or repair local work and inspect the actual player camera, audio, input and devices. Verify another builder’s frozen candidate for independent acceptance. Qualify the operator on a real two-client route before relying on it for that check. |
| Mac disk monitoring | AGY Gemini 4 Hydrogen (XHigh) | Periodically measure available space on the data volume. Return timestamped readings to local operations. The monitoring job is read-only. |
| EC2 creative and delivery lead | Fable, high effort | Turn a short seed into an original playable episode. Own difficult decisions, assign work locally, critique the signature moment and decide when the episode is polished for its scope with no obvious weakness. |
| EC2 primary builder | AGY Orchestrator (Neon), high effort | Own a whole playable milestone, including implementation, assets, repairs, targeted checks and routine English documentation. |
| EC2 specialist and disk monitor | Opus, high effort; Haiku for disk checks | Give Opus a small share where its contribution warrants it. Haiku periodically checks EC2 disk space and reports to Fable. Fable chooses the cadence and may add a local coordinator. |

Fable has final say on the division of responsibilities across EC2 and Mac for Journey and World Classics. Fable leads EC2 workflow and skill improvements. The Mac workflow owner (Codex) leads Mac improvements and implements Fable's cross-host decisions with the local dispatcher. When capacity or device access affects a handoff, the Mac owner gives Fable the measured constraint and feasible options. Fable records the resulting allocation in the existing workflow or rotation record. Existing owner decisions on models, quotas and release authorization continue to apply.

## Recording improvements

Record an agreed change at its point of use before the next affected handoff. Fable maintains the English record of cross-host decisions and EC2 practices; the Mac workflow owner maintains the Mac procedure. Update the existing playbook, skill or automated check that the operator actually uses. Keep one authoritative entry and link to it from dispatch or rotation records.

Each entry names the owner, the event that calls for action, the action itself and the evidence that shows it worked. Mark a new idea as a trial, use the next ordinary production run to measure it, then record whether to adopt, adjust or retire it. For example, use the next normal Fable handoff to verify unattended receipt, and the next repaired camera turn to check whether it survives Mac review. Commit the record with the related change or as a small documentation milestone, and hand off its path and revision.

### Review and follow-up

1. Before a trial, record the observed failure, the baseline, the proposed change, a measurable pass condition, its owner and an independent reviewer. Specify the next production event that can supply evidence. If there is no usable baseline, record the first observation and defer comparative claims.
2. At that event, the reviewer checks the frozen revision or original message ID using player-visible results or recipient acknowledgment. Record the host, evidence link and result. For quality, count first-pass acceptances over comparable candidates reviewed and note any blocking defect. For turnaround, distinguish active repair time from machine or mailbox waits. Record revision count and Fable usage when available; keep missing values explicit. Use only measures relevant to the trial.
3. The decision owner records the verdict and reason. Adopt a passing change in the playbook, skill or test used for the next handoff. For a failed trial, name the repair owner and next review event, or retire the change and restore the prior practice. Insufficient evidence keeps the trial open. Codex decides Mac-local changes; Fable decides EC2 and cross-host changes.
4. At the next comparable use, verify that the adopted practice was actually used and the benefit held. Link that observation and the versioned rule before closing the entry. A recurrence reopens the same entry. Reuse the scheduled review and evidence where they still apply.

| Initial trial | Baseline and pass condition | Follow-up |
| --- | --- | --- |
| Fable mailbox wakeup | Fable reported roughly 5.5 hours idle; three messages were read after a manual wake. Pass on a subsequent ordinary message when the original lead reads and acknowledges it without a reminder. Record send, read and reply times and whether the watcher rearms. | The Mac dispatcher verifies receipts; Fable owns the cross-host verdict. Confirm on the next ordinary handoff. |
| Camera turns while carrying an object | Crusoe r3 passed the solo route, but a normal turn hid the player and cask, and the hands did not support it. For the next frozen revision, require a clear view throughout the reported and adjacent turns and a credible grip in the matched frames. | An independent Mac reviewer checks normal gameplay and reports defects per set piece and revisions to acceptance. Fable decides whether to extend the trial after a comparable Snow Queen scene. |

The Mac dispatcher or workflow owner communicates with Fable as the sole EC2 contact. Keep Mac staffing instructions on the Mac. Use Codex selectively for difficult integration or independent review. Terra-driven GLM production is parked.

## English correspondence with Fable

Every Mac session contacting Fable writes in English. This covers initial briefs, clarifications, corrections, evidence requests, playtest feedback and handoffs. For each item, the workflow owner or dispatcher designates one sender. Use Fable’s existing project conversation and carry the same item identifier on follow-up. Fable coordinates the EC2 agents.

For a new title, translate the user’s short seed and purpose faithfully. Give the audience, the relevant series constraints and the intended deliverable. Leave story, map and mechanics decisions to Fable. Preserve exact in-game labels, quotations, identifiers and paths when needed inside an English message. The outgoing-language rule imposes no language requirement on Fable’s replies or on player-facing content. Omit report-language instructions.

For a playtest finding, give the candidate revision, entry route, action, observed result and the player-visible outcome needed. Supply a short clip or matched frames accessible on EC2. For a handoff, state what is ready, what remains open and the decision or deliverable requested. Keep local staffing, private operational details and unrelated logs in the Mac record.

Use project-approved Orca mail. Record local queue receipt, verified EC2 file availability, Fable’s acknowledgment and a resulting action as separate facts. If the delivery channel fails, keep the English brief for the same recipient and record the blocker. Check the existing receipt before sending again.

For the World Classics lead, a tmux reattachment can leave Claude bound to an older terminal handle. Match the connected lead by project and title and inspect its mailbox with the runtime-matched CLI. The project-local Claude hooks on EC2 check for pending mail at session start, user input and the end of a turn. While unattended, the lead runs one background `python3 ../operations/fable-mail/mailbox.py watch` from its World Classics worktree, reads the original mail itself when notified, and rearms the watcher. The watcher uses a read-only peek. A sender-side check never consumes mail.

When a delivery is held, the dispatcher retains the original message ID and checks its read state on the next existing health cycle. If still unread, verify the lead's actual terminal binding and recipient-owned watcher. Record a single actionable alert if the idle lead needs a person to wake it. Close the incident on a real read and acknowledgment; verify the next ordinary delivery while the lead is unattended before declaring automatic wakeup proven.

Use Orca’s recurring jobs for local wakeups and its run history for receipts. Keep the lightweight dispatcher separate from the production model. On each wake, recover the last recorded action before dispatching. If an existing run is bound to its original coordinator, keep that identity for queue transport while Neon owns scheduling decisions. An accepted wake is distinct from a verified model response or completed task.

Include read-only Orca health checks in each host's existing disk check. Record the time, free space, runtime readiness and version, and the most recent evidence of actual agent-mail delivery. Record pending acknowledgments separately. The Mac monitor checks the paired runtime and its advertised peer-mail capability; EC2 Haiku checks its local service and listener. Use existing message receipts to avoid generating periodic test traffic. Report failures and recoveries to the local owner. Restarts, upgrades and pairing changes are separate maintenance decisions. When Orca itself cannot schedule a check, its owner can verify the last receipt through the independent supervisory channel or SSH.

AGY supplies playable evidence and fixes obvious defects before asking Fable for a focused review. At an accepted milestone, freeze the revision, record known issues and pass the candidate to the Mac for target-specific acceptance. Compare time to playable milestones and accepted outcomes; attribute host and transport waits separately. Use observed results to refine assignments.

At the next scheduled Mac review of a camera or carry repair, use the normal player entrance. Record the host, frozen revision, player action, camera bearing and the frames around the failure. Recheck the reported pose and the adjacent turn in the same run. Link the resulting evidence from the existing record so the builder can reproduce the issue without another full tour. Keep host-specific check counts with their host names.

For a new repository, create its own queue, evidence locations, schedules and acceptance criteria after checking its workload and hardware. The Lantern Lane disk trial uses a 10 GiB alert threshold and checks every 30 minutes. Repository permissions, release authority, device access and Git authorization are project-specific.
