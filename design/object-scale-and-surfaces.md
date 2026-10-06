# Object Scale and Support Surfaces — Canonical Contract

Status: version 1, 2026-10-06. Owner: the game-code lane. Code is the source of truth: `game/scripts/core/catalog.gd`, with automated checks in `game/tests/run_tests.gd`. Other lanes (for example the modeling pilot) report against this contract. They do not redefine it.

The town uses a **stylized, compressed scale**, inspired by the readability of cozy life-sim games such as Animal Crossing ([official site](https://animalcrossing.nintendo.com/new-horizons/explore/)). That game is a visual reference only. No sizes here are taken from it, and the numbers below are tuning targets refined with renders, not facts about any other game.

## 1. Units and grid

| Convention | Value |
|---|---|
| Game unit | 1 unit = 1 m. Y is up and the ground is y = 0. Item origin is the center of its footprint on its anchor surface. Front faces +z at rotation 0. |
| Placement grid | The ghost snaps to 0.25 units; stored positions round to 0.05 units. Rotation uses 8 steps of 45°. |
| Neutral avatar height **H** | **1.30 units**: the head top of the default child (hair included; the name tag and emote heart are excluded). Measured from the built model. The full child box including the emote heart is 1.68. |
| Room | 8 × 6 units of floor; walls 2.8 units high. Three floors × two rooms per cottage. |
| Town | 52 × 44 units. |

## 2. Three different sizes per object (keep them distinct but coherent)

1. **Visual bounds** (`bounds`): the axis-aligned box of the built model at rotation 0, in units. Used for camera framing, thumbnails, screen-space checks (for example placement tools avoiding the item) and support-fit checks.
2. **Footprint** (`radius` + `layer`): the circle used for placement overlap and walking collision. Trees have footprints **smaller** than their canopies (the trunk blocks, the canopy overhangs), so children and animals can get close. Small decorations keep a footprint slightly larger than their bodies so they stay spaced out and easy to tap. Furniture you use (chairs, benches, swings) may have a footprint a little wider than the model, to keep space to sit or swing. The rule is radius ≤ 0.75 × the longest side + 0.15. `solid` blocks walking and other solids; `flat` (rugs, paths, blankets) only collides with other flat items.
3. **Touch target**: picking uses the projected visual bounds, never smaller than 44 px across on screen (`TownWorld.pick_item`). Small decorations stay tappable because of that minimum, not by inflating the model.

Scale is applied **once**, in the model builder (`game/scripts/art/props.gd`). Neither the catalog nor the world multiplies it again. A test builds every model and fails if its measured bounds drift more than 0.12 units from `bounds`. The decorative woods outside the town vary in size (0.9–1.2) as scenery; they are not catalog items.

## 3. Size classes and targets

Ratios are relative to H = 1.30 or to the chair (0.52 × 0.52 footprint, seat at 0.5).

| size_class | Meaning | Target |
|---|---|---|
| `landmark` | Defines the town, deliberately big | Wishing Tree about 5.5 units; cottage 3 stories, 7.5 units high |
| `tree` | Ordinary trees | Height **1.6–2.0 H** (2.1–2.6 units), canopy no wider than about 2 units, trunk footprint 0.5–0.55 |
| `large` | Major furniture and play equipment | Clearly more footprint and mass than a chair: about 1.5–3 chair widths along the long side. Beds are sized to fit a lying child, not stretched taller. |
| `medium` | Chairs, lamps, bushes, fences | Around 0.6–1.2 H high |
| `small` | Handheld and tabletop decorations | Height **0.2–0.45 H** (0.26–0.6 units); enlarged from real life so they read and can be tapped |
| `flat` | Rugs, stepping stones, picnic blankets | Height under 0.1 except blanket props |

Measured result after this change (built models, units):

| asset_id | size_class | bounds w × h × d | footprint r | notes |
|---|---|---|---|---|
| tree | tree | about 1.85 × 2.42 × 1.85 (width varies ±0.1 with the random canopy) | 0.55 | was 2.78 × 3.75 × 2.70 (2.9 H), footprint 0.8 |
| pine | tree | 1.50 × 2.18 × 1.50 | 0.50 | was 2.10 × 3.05 × 2.10, footprint 0.7 |
| chair | medium | 0.52 × 1.00 × 0.52 | 0.40 | reference prop |
| table | large | 1.20 × 0.70 × 1.20 | 0.65 | 2.3 chair widths; the built-in tea set was removed so the top is a real support surface |
| bed | large | 1.28 × 0.96 × 1.98 | 0.95 | 3.8 chair widths long: fits a lying child |
| sofa | large | 1.80 × 0.86 × 0.82 | 0.90 | 3.5 chair widths |
| bookshelf | large | 1.10 × 1.60 × 0.44 | 0.60 | |
| plant (flower pot) | small | 0.38 × 0.52 × 0.36 | 0.25 | 0.40 H; was 0.53 × 0.80 × 0.48 (0.62 H) |
| teddy | small | 0.35 × 0.45 × 0.27 | 0.22 | 0.35 H; was 0.46 × 0.60 × 0.35 |

The numbers for every item live in `Catalog.ITEMS[...]["bounds"]`.

### Modeled items (pilot-10 v1, integrated 2026-10-06)

The reviewed models in `art/pilot-10-v1` use this contract directly. Their bounds are measured from the GLBs, and the scale is baked in (no runtime scaling). The built-model test checks them like every other item.

| Game id | size_class | bounds | footprint r | Support / markers |
|---|---|---|---|---|
| scallop_chair | medium | 0.533 × 1.068 × 0.501 | 0.38 | `Seat0` |
| cozy_round_table | large | 1.000 × 0.660 × 1.000 | 0.52 | support `(0, 0.66, 0)`, 0.56 × 0.56, max 1 (inside the flat top, radius 0.465) |
| scallop_bed | large | 1.072 × 1.018 × 1.792 | 0.85 | `Sleep0` |
| writing_bureau | large | 0.780 × 0.950 × 0.516 | 0.38 | — |
| open_shelf | large | 1.001 × 1.362 × 0.401 | 0.45 | — (shelves are not slots) |
| curved_counter | large | 1.510 × 0.800 × 0.578 | 0.62 | — (no surface: its curved top fits neither eligible prop) |
| desk_lamp | small, eligible | 0.317 × 0.538 × 0.482 | 0.18 | `Light0`. On the 0.56 surface it fits straight, but its 45° turned box (about 0.565) is refused. |
| flower_pot_bloom | small, eligible | 0.351 × 0.573 × 0.351 | 0.18 | fits at every rotation |
| wall_clock | small (wall) | 0.44 × 0.44 × 0.141 | — | **not placeable**: wall anchor not implemented |
| bird_mobile | medium (ceiling) | 0.817 × 0.78 × 0.78 | — | **not placeable**: ceiling anchor not implemented |

The lab used anchor values `floor` and `surface`; both map to `ground`. `surface` items are the `tabletop_eligible` ones. Chairs and beds interact through their model markers (`Seat0`, `Sleep0`), not through hard-coded offsets.

## 4. Support surfaces (tabletop placement)

Only items that explicitly declare `support_surface` can hold another item, and only items with `tabletop_eligible: true` can be placed on one. There are no name-based heuristics.

```text
support_surface = {
  "local_position": Vector3,   # center of the usable top, in the host's local frame (y = top height)
  "usable_size_xz": Vector2,   # width x depth of the usable area in the host's local frame
  "max_items": 1               # fixed at one in this version
}
```

Current hosts: `table` with `local_position (0, 0.70, 0)`, `usable_size_xz (0.84, 0.84)`, `max_items 1`. The round top has radius 0.6; 0.84 is the conservative square inscribed in it (side 0.6 × √2 = 0.848). Round or irregular surfaces must declare an inscribed rectangle, never the outer bounding box. A test checks that the usable diagonal stays within the top. Current eligible items: `plant` and `teddy`.

Rules (enforced by `TownModel`, so the authority, saves and the network all share them):

1. **Fit:** the item's bounds, **turned by its rotation relative to the host** (in 45° steps), must fit inside `usable_size_xz`. For angle a, the turned width is |w cos a| + |d sin a| and the turned depth is |w sin a| + |d cos a|. Any overhang is rejected. Items are never resized to fit; anything else is rejected with "That does not fit on top." or placed on the floor instead.
2. **One per host:** a second item is rejected with "There is already something on top."
3. **No nesting:** a host can't be placed on a host, an attached item can't host anything, and nothing attaches to itself, so cycles are impossible.
4. **Same space:** host and item are in the same town or room space.
5. **Placement on the surface:** an attached item stores `"host": <host id>`. Its position is always the host's surface center: it sits exactly on the top, with no floating or sinking. Its rotation is kept relative to the host. Attached items don't take part in floor overlap or walking collision.
6. **Follow:** moving or turning a host moves and turns its attached item, so the relative rotation and the fit never change. Putting a host away packs the attached item with it, and undo restores both together.
7. **Restore order:** `TownModel.restore` rebuilds cottages first, then floor items (tables included), then attached items, whatever order its input is in. A decoration may be older than its table, so insertion order is not enough. IDs are kept when free and remapped otherwise. If a table cannot come back, its decoration goes to the floor at the same spot if there is room. Anything that cannot come back at all is listed in `skipped` and the player is told ("Some things could not go back."). Nothing is dropped silently.
8. **Saves:** `host` is optional. Saves without it (all older saves) load unchanged. If a saved host is missing, invalid or already occupied, the item stays where it was as a floor item: it is never deleted.
9. **Network:** the authority decides. Two simultaneous attempts on the same table are serialized: the first wins, the second gets "There is already something on top."

## 5. Exchange schema for new assets (mapping to the catalog)

New models (for example from the modeling pilot) should be described with these fields. The right-hand column shows where each one lives in the catalog.

| Contract field | Type | Catalog mapping |
|---|---|---|
| `asset_id` | snake_case string, stable forever (stored in saves) | the `Catalog.ITEMS` key |
| `bounds` | `[w, h, d]` units at rotation 0, origin at the bottom center of the anchor face | `"bounds": Vector3` |
| `anchor` | `ground` \| `wall` \| `ceiling` | `"anchor"`. Only `ground` is placeable today. Wall and ceiling assets (for example the pilot's wall decor and hanging decor) are recorded but **not placeable** until wall and ceiling anchoring is implemented and tested. They are never put on the floor and called integrated. |
| `footprint` | collision radius recommendation, plus `solid` or `flat` | `"radius"`, `"layer"` |
| `size_class` | `landmark`, `tree`, `large`, `medium`, `small`, `flat` | `"size_class"` |
| `tabletop_eligible` | bool | `"tabletop_eligible"` |
| `support_surface` | optional object (section 4) | `"support_surface"` |

The catalog also has gameplay fields not covered by this contract: `name`, `category`, `space`, `color`, `seats`, `action`.

## 6. Checks

- `run_tests.gd → test_scale_contract`: every catalog item has the contract fields with valid values; every built model's bounds match `bounds` within 0.12 units; size-class ranges hold (trees 1.6–2.0 H, small items 0.2–0.45 H); footprints stay close to the model size, and tree footprints are narrower than their canopies; eligible items fit every host they are allowed on.
- `run_tests.gd → test_tabletop_restore_order`: a decoration older than its table, in a cottage put away and restored, with the input as removed, reversed and shuffled. Also a blocked table (decoration to the floor, table reported) and a blocked cottage (everything reported).
- `run_tests.gd → test_tabletop_rotated_fit`: a 0.84 × 0.5 item fits straight but is refused at 45°; a 0.9 square overhangs the round top; current decorations fit at all 8 rotations; rotation is relative to the host.
- `run_tests.gd → test_tabletop_*`: placing, the second-item rejection, fit and eligibility, nesting, following moves and turns, removal and undo, save round trip, legacy saves, and broken host data.
- `scripts/net_test.py`: two real clients try to put something on the same table at the same moment; exactly one succeeds.
- Lineup renders (`tests/scale_lineup.gd`): child, tree, large furniture, chair and a decoration on a table, before and after this change, from the game camera.
