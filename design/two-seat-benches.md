# Design: two seats on modeled benches (implemented in candidate r17)

Status: written 2026-10-09 as a plan (r16 batch, item 4); **implemented in candidate r17** (2026-10-09, after the user authorized it), with the reasoned adjustments in "As implemented (r17)" below. Not released.

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

## As implemented (r17)

Option 1 was followed. Protocol 9 and schema 2 are unchanged, and seats are still never saved.

**Capacity.**
- `Catalog.SEATS_OVERRIDE = {"bamboo_bench": 2}` and `Catalog.seats(kind)` live outside the generated blocks. `ITEMS` is a constant, and the release r1 block stays exactly as generated: it still says `seats: 1`.
- The authority (`Session._srv_sit`) and the play controller ask `seats()`.
- The toy box's "Seats" filter reads the entry, which is unchanged, because the override only raises an existing seat count.

**Markers.**
- `Props._modeled` copies `Seat0` to `Seat3`.
- `Props.seat_marker(node, i)` returns the prop root's own marker first (else the first one inside, or `Sleep0` for a one-place bed). The world, the controller and the tests all use it.
- A unit test checks every seated kind: one marker per seat, none beyond the capacity, all inside the bounds, and seats at least 0.5 m apart.

**Seat spacing (adjustment).**
- The plan checked only shoulder width (0.43 m). The rendered child's head is about **0.70 m** wide (the chibi rig), and a wide hat brim reaches further.
- On the frozen markers, 0.54 m apart, two children's heads would be 0.155 m inside each other, and 0.236 m with an alpinist hat. These were measured in `test_two_seat_geometry`.
- `Props.MIN_SEAT_PITCH = 0.80` m now applies to every side-by-side pair:
  - the procedural bench (was 0.76 m) and sofa (was 0.70 m) build their seats 0.80 m apart;
  - a frozen model with closer markers has its **copied** markers moved apart evenly (`Props._spread_seats`). The bamboo bench now seats at ±0.40 m, still on its 1.2 m seat with hips inside the width.
- The GLB is not changed, and a test confirms its own markers are still 0.54 m apart.
- **Modeling note (not requested now):** re-exporting `bamboo_bench` with `Seat0`/`Seat1` at x = ±0.40 (same height 0.47 m and depth) would make the game's correction a no-op. No mesh change is needed.

**Choosing a seat.**
- The authority gives the first free seat, and a child who taps Sit again on their own bench keeps their seat; previously they would have moved to the other one.
- Two simultaneous requests get seats 0 and 1; a third child is refused with "Someone is playing on it.".

**Feedback (addition).**
- A refused Sit now shows the authority's reason as a message. Before, a full bench did nothing.
- Get up places the child in front of their **own** seat, so two children leaving one bench do not stand on each other.

**Remote children stay on their seat (fix found by the new network check).**
- A friend's child eased toward the friend's last walking position every frame, which pulled it off the seat between the world's placements.
- `kid.gd` now does not ease while seated; the world places the child on the seat each frame.

**Hardening.**
- The authority relays a player's position only to connected peers, the same guard `activities.gd` already uses for its messages.

**Acceptance, EC2 (headless; not Mac, device or visual acceptance):**
- `test_seat_markers`: all 17 seated kinds.
- `test_two_seat_geometry`, which checks every two-seat kind (bench, sofa, bamboo bench, seesaw):
  - turned 0°, 135° and 270°;
  - with a seated-variant coat, an alpinist hat and a backpack; a robe with a held umbrella; and plain presets;
  - no part of one child is inside a part of the other (closest parts 0.024 m with the hat, 0.105 m plain);
  - both sit on their own seats, above the floor;
  - the same look in every direction.
- `test_two_seat_authority`: seats 0 and 1, a third child refused, tapping again keeps the seat, standing and disconnecting free only that seat, occupied benches cannot be moved or put away, the chair still seats one, nothing is saved.
- `net_test.py --seats`: three real clients and a server restart.
- `bench_tour.gd`: through the real UI. It also runs headless with `--no-shots`.
- **Mutations:**
  - no override: 10 failing checks;
  - no spreading: 11;
  - seat choice reverted: 1;
  - the remote-child easing put back: 5 failing tour checks.

