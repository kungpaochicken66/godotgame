# World Classics — rotation ledger

Entry point: [README.md](README.md). This page is the single source of truth for **which work is current, which are
frozen or delivered, and which candidates remain**. Read it before starting anything; update it in the same commit as the
event it records. Owner direction of 2026-11-22 (standing rotation) is summarized under "Rules".

## Rules

1. **One current work.** The steward keeps producing, integrating and polishing it, and alone judges when it is polished
   and of high quality for a child actually playing it.
2. **Ready.** When the current work is judged ready, add a row to "Frozen and delivered" with the decision in a sentence,
   the playable scope, the strongest evidence, and the frozen local Git commit; make the usual immutable candidate handoff
   (`scripts/model_handoff.py`, `docs/dual-host-modeling.md`) including the whole `docs/world-classics/` folder.
3. **Next.** At that point choose one eligible candidate below, by creative judgment (the source documents' own
   recommendations are noted beside the entries). **First** change its state to `active` in this file and commit that
   change with the date; only then begin work. Do not wait for another owner prompt or for Mac acceptance of the previous
   work: Mac verification of a frozen candidate and production of the next work run in parallel, and Mac defects on a
   frozen work are repaired alongside.
4. **Never twice.** A candidate whose state is anything other than `candidate` must not be started again. Each has a
   stable id; use that id in branch names, folders, commits and handoffs. If a session resumes and finds an `active` entry,
   it continues that work from its record instead of selecting.
5. **Exhaustion.** When no `candidate` remains, record that here and tell the Mac desk.
6. **Boundaries unchanged.** Local commits on the isolated feature repository only; no push, no merge to production main,
   no signing, no deployment. Journey scheduling and the EC2 resource limits (one Godot process at a time) continue.
   The Mac desk plays each frozen candidate from Lantern Lane's World Classics entrance through completion and the return
   to town and reports issues with reproduction steps.

States: `candidate` → `active` → `frozen` (handed off, awaiting or under Mac play) → `delivered` (Mac play passed; device
acceptance and release remain separate) . A work may also be `set aside` with a reason; that needs an owner decision.

## History

- 2026-11-25 — Owner decision ROLE-1125 (`msg_c8337077fdc4`, `msg_7d6d51fd8914`): the steward has the final say on
  how work is divided between EC2 and the Mac for Journey and World Classics. The split, what each side hands
  over, and five marked trials are recorded in [../dual-host-modeling.md](../dual-host-modeling.md), "Division of
  work between EC2 and the Mac".
