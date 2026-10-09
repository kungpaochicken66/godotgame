# Design: two seats on modeled benches (plan only, not implemented)

Status: read-only design, written 2026-10-09 (r16 batch, item 4). Nothing here is in production code yet.

## What exists today (verified in source)

- **Multi-seat already works for procedural items.**
  - The catalog field `seats` sets the capacity: `seesaw` 2, `bench` 2, `sofa` 2.
  - The authority's `Session._srv_sit` gives a sitting child the first free seat index below that capacity (`seats[item_id][index] = peer`). It refuses when all are taken ("Someone is playing on it."), and frees a child's old seat first (`_free_seats_of`).
  - Seat maps go to everyone with `ev_seats` and are part of the join snapshot (`_seats_snapshot`). They are session state and are never saved.
  - `TownWorld._animate_play_items` places each holder at the item's `Seat<index>` marker, facing the marker's +z, with the pose from the catalog action (sit, swing, ride, rest).
  - The procedural builders already add `Seat0` and `Seat1` (`props.gd`: bench, sofa, seesaw).
- **Modeled items expose only `Seat0` today.** `Props._modeled` copies a fixed list of marker names from the GLB to the prop root: `Seat0`, `Sleep0`, `Support0`, `Light0` and a few others, but not `Seat1`.
- **Of the 8 frozen models with seat markers, one has two:** `bamboo_bench` (batch `b003-housewares-3`; markers `Seat0 (-0.27, 0.47, 0)` and `Seat1 (0.27, 0.47, 0)`; bounds 1.2 x 0.465 x 0.426). Its catalog entry (release r1 block, generated) says `seats: 1`. This is the known limit "the two-seat bamboo bench seats one child".

## Options

1. **Copy `Seat1` and give the bamboo bench two seats (recommended).**
   - Add `Seat1` to the marker list in `Props._modeled` (any later model with `Seat1` gains it automatically).
   - Set `bamboo_bench` to `seats: 2` through a small Game Code override applied after the generated block. The release r1 block stays exactly as generated, and the frozen GLB is unchanged.
   - Server, network, world placement and poses are reused unchanged.
2. **Derive the seat count from the markers at load time** (count `SeatN` nodes in the GLB). This is more general, but the authority would then depend on loading a scene; the server runs headless with the catalog only. Rejected for the authority; it could be a unit-test cross-check instead.
3. **Ask the Modeling lane for more two-seat models.** Out of scope; nothing blocks option 1.

## Recommendation: option 1

**Affected files:**
- `game/scripts/art/props.gd`: the marker list.
- `game/scripts/core/catalog.gd`: a seats override for `bamboo_bench`, outside the generated block.
- `game/tests/run_tests.gd`, `game/tests/net_bot.gd`, `scripts/net_test.py`, one tour.
- Docs: `design/object-scale-and-surfaces.md` and this file.

**Selection and claims:**
- Tapping a two-seat item offers Sit while a seat is free. The authority picks the first free seat, so two children tapping at the same moment get seats 0 and 1; a third is refused.
- Standing up frees only that child's seat. Leaving or disconnecting frees it too (existing `_free_seats_of` on leave).

**Poses:** the existing sit pose, at each marker's transform. Two children sit 0.54 m apart (centre to centre). With the child's shoulder width (about 0.43 m) they do not touch. A rendered check confirms this.

**Save and network:**
- Protocol 9 and schema 2 are unchanged: `seats` capacity is catalog data, and seat maps are session-only.
- Older saves are unaffected. Old clients (`seats: 1`) would show a second child sitting on Seat0's spot if the server allowed two, so this ships with the usual app and server update together. No mixed versions are supported anyway, because the protocol check refuses them.

## Acceptance (future candidate)

- **Deterministic:**
  - `Props.build("bamboo_bench")` has `Seat0` and `Seat1` 0.54 m apart at seat height 0.47.
  - `Catalog.get_def("bamboo_bench")["seats"] == 2`.
  - The generated release r1 block is byte-unchanged (only the override differs).
  - All other modeled seats keep their counts.
- **Network (two real clients plus a third):**
  - A and B sit on one bamboo bench and get seats 0 and 1.
  - C is refused with "Someone is playing on it."
  - A stands, and C gets seat 0.
  - A leaves while seated, and the seat is freed for B's view.
  - Seats are not in the save after a restart.
- **Rendered (Mac):** two children seated side by side on the bamboo bench in the living room, not overlapping each other or the arm rests, plus the sit-pose regression on a chair.
- **Not in scope:** seat choice by tap position. The authority picks the first free seat, as on procedural benches today.
