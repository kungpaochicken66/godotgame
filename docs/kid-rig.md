# Child rig and attachment contract

The child avatar is code-built in `game/scripts/art/kid.gd` from soft primitives. This page describes the node names, pivots and attachment rules that other lanes (for example the Modeling lane's wearables) can rely on. Status: GameCode r12 (uncommitted, 2026-10-08; `Hand` added in r11, kept upright since r11b; wearables mounted since r12, see [wearables.md](wearables.md)).

Units: 1 unit = 1 m; the neutral avatar's head top is H = 1.30 (`tests/run_tests.gd` `test_scale_contract`). The kid faces local +z.

## Node tree (names are stable)

| Node | Parent | Local position | Moves in animation |
|---|---|---|---|
| `Body` | kid root | (0, 0, 0) | `position.y` bob; `rotation.y` (dance); `rotation.x` (sneak pose) |
| `LegL`, `LegR` | `Body` | (∓0.095, 0.36, 0): hip pivots | `rotation.x` (walk, sit) |
| `ArmL`, `ArmR` | `Body` | (∓0.215, 0.66, 0): shoulder pivots | `rotation.x`, `rotation.z` (emotes, poses) |
| `Head` | `Body` | (0, 0.72, 0): neck pivot; head ball center at (0, 0.29, 0) in `Head` | `rotation.x` (rest, poses), `rotation.z` (thinking pose) |
| `Hat` | `Head` | (0, 0, 0) | follows `Head` only |
| `Hand` | `ArmR` | (0.04, -0.29, 0): the right hand | its position follows `ArmR`; its rotation is the inverse of `ArmR`'s, so a prop stays upright (r11b) |

Rules:

- **Hats attach under `Body/Head/Hat`**, in `Head` coordinates. The current hats (`chef`, `explorer`, `crown`, `rain`; `Avatar.HATS`) sit on the hair between y ≈ 0.46 and 0.91 in `Head` space. A modeled hat should have its origin at the `Head` origin and stay above y ≈ 0.45 so it clears the eyes (y 0.30) and cheeks.
- **Handheld props attach under `Body/ArmR/Hand`** (r11: magnifying glass, conductor's baton, umbrella, little flag; `Avatar.PROPS`). `Hand` is turned against the arm every frame (`hand.basis = ArmR.basis.inverse()`), so a prop's local +y always points up in body space, even with arms out in a pose (unit-checked: under 25 degrees of tilt in every emote and pose; the r11 Mac story strip showed the umbrella swinging sideways before this). The umbrella's canopy rim sits above the tallest hat (unit-checked). The left arm has no attachment node yet.
- **Hair** is never hidden by a procedural hat; every hat is shaped to read over all five hairstyles. Non-band wearable headwear hides the hair by avatar data: `kid._build` leaves the hair (and other baked parts a worn slot replaces, `Wearables.HIDES`) out of the build, since merged parts have no stable names.
- **Rebuilds:** `kid.setup(avatar)` frees and rebuilds the whole tree (hat or clothes color changed in town, F07). Anything attached from outside must be re-attached after `setup` and must not keep references across it.
- **Merging:** within each node, static opaque mesh parts are merged into one mesh (`mesh_kit.gd` `merge_parts`); emissive or transparent parts and parts with children stay separate. Pivots (`Body`, legs, arms, `Head`, `Hat`, `Hand`) are never merged away.
- **Seated (r17):** while a child sits, swings or rides, the world places it on its seat marker every frame (`TownWorld.seat_transform`); a friend's child does not ease toward their last walking position meanwhile, so it stays on the seat.
- **Wearables (r12):** after every `setup`, each worn GLB's `<id>_<Pivot>[_sit]` meshes are re-parented under `Body`, `Head`, `ArmL`/`ArmR` or `LegL`/`LegR` with an identity transform (`kid._mount_wear`); `Wearables.pose_state(anim, wear)` picks standing or seated meshes, the held item's visibility, the seated hands (arms x -1.1) and the right-arm hold envelope (emotes then play on the left arm). Rules and the accepted ids: [wearables.md](wearables.md).
- **Network:** a player's look is `Avatar.sanitize(...)` data (`nick`, `skin`, `hair`, `hair_color`, `outfit`, `outfit_color`, `hat`, `prop`, `wear`); changes go through the authority (`Session.dress(hat, color, outfit, prop)`, `Session.wear(slot, id)`, event `ev_avatar`). Unknown values fall back safely (an unknown hat becomes no hat), so older saves and settings load unchanged.
- **Poses** (story poses `surprised`, `think`, `proud`, `sneak`; `Avatar.POSES`) only rotate the pivots above; they never move `Hat` relative to `Head`.
