# Contributing to Lantern Lane

Guidance for everyone changing this repository, people and coding agents alike.

## Standing rule: update the docs with every change

Every change to code, assets, tests or behavior must update the affected documentation **in the same change**. The user requested this on 2026-10-06 as a standing rule for this project. A change is not finished until these are accurate:

- [README.md](README.md): what the game is, how to run it, the test commands.
- [HANDOFF.md](HANDOFF.md): current status, changed paths, exact tests run with their results, and remaining issues. Remove stale claims (for example old commit or push status) instead of leaving them.
- Gameplay and controls: [docs/game-design.md](docs/game-design.md), [docs/animals.md](docs/animals.md), [docs/multiplayer.md](docs/multiplayer.md).
- Assets: [docs/assets.md](docs/assets.md) records provenance, license and attribution for every font, sound and other asset. No asset goes in without an entry.
- Verification: [docs/validation.md](docs/validation.md) and [docs/requirements.md](docs/requirements.md).

Record the exact tests and their real results, and state what was **not** tested. Never present automated, headless, simulated or software-rendered checks as testing on an actual iPhone or iPad.

## Object scale and surfaces

All object sizes, footprints, touch targets and tabletop support follow the canonical contract in [design/object-scale-and-surfaces.md](design/object-scale-and-surfaces.md): 1 unit = 1 m, neutral avatar height H = 1.30, size classes, and the `support_surface` / `tabletop_eligible` schema. New or changed assets must state these fields, and `run_tests.gd` checks built models against them.

## Modeled assets

Reviewed models are versioned in `art/<batch>/` with their builders, manifests and skill. Only the placeable ones are copied into `game/assets/models/`. Record exactly what was copied and excluded in that folder's `INTEGRATION.md`. Never ship reference imagery, private runtimes, caches or session logs. Wall and ceiling assets stay out of the catalog until those anchors are implemented and tested.

## Other project rules

- Code, comments, file names and docs are in English. UI text is English source; translations go in `game/locale/` for exactly six locales (en, zh-CN, ja, es, fr, de). Run `scripts/extract_strings.py` and `scripts/build_fonts.py` after changing UI text.
- Assets must be original or explicitly licensed for redistribution, and their license must be checked. "Royalty-free" alone is not enough.
- Keep saves backwards compatible: bump `TownModel.SCHEMA`, write a migration, and test it. Bump `Session.PROTOCOL` when the network rules change.
- The modeling lab under `tools/opus-model-lab-20261006/` belongs to a separate lane. Don't edit it or import its output without a reviewed handoff.
- Committing, pushing, publishing and deploying each need explicit authorization from the user.
- Run `scripts/test_all.sh` before handing off.
