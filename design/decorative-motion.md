# Design: decorative motion (first batch implemented in candidate r20-motion)

Status: written 2026-10-09 as a plan (r16 batch, item 5). The first batch was **implemented in candidate r20-motion on 2026-10-14**, at the user's request; see "As implemented (r20-motion)" below. No GLB or Modeling-owned builder was changed.
Facts below come from the frozen GLBs in `game/assets/models/` (byte copies of `b011-furn-r2`), read as glTF JSON.

## What the frozen models allow

Every one of these models is a **single merged mesh** (one node) whose parts are separated only by material surfaces. No blade, wing or screen is a node of its own.

| Model | Surfaces (material: extent) | Can it move honestly without new geometry? |
|---|---|---|
| `disco_ball` (mirror ball) | charcoal rod x/z ±0.04; steel ball ±0.2, y -0.7 to -0.3; white band ±0.2 | **Yes: turn the whole model about its vertical axis.** Every part is centred on that axis, so it looks like the ball turning on its rod. |
| `ceiling_fan_light` | white (canopy, rod and blades together) ±0.54 x ±0.63; bulb **off-centre** x -0.205 to -0.088; `Light0` at (-0.146, -0.36, 0) | **No.** Spinning the whole model would make the off-centre bulb and its evening light orbit, which a real fan does not do. Blade motion needs **Modeling**: blades as their own node (or a centred light kit). |
| `hanging_screen`, `dual_hanging_screens` | charcoal frame; a "screen" surface; **no texture coordinates** | **Partly:** the screen surface can glow and slowly change tint (material colour or emission on that surface only). **Pictures or video cannot** be shown without UVs; that needs **Modeling** (UV-mapped screen faces). |
| `paper_ornithopter` (related) | cream rod; paper body and wings together; wood | Wings cannot flap (fused). A gentle whole-model sway about the hook, like a hanging mobile, is possible. |

## Proposed animation-only slice (Game Code, no Modeling)

- **Mirror ball:** turn the `Model` node about Y at about 0.3 rev/s while the room is visible. A soft sparkle could be added later with the existing evening light. This is purely visual.
- **Screens:** on the "screen" surface only, cycle the emission colour slowly through two or three calm tints (period about 4 s). The frame stays still.
- **Ornithopter (optional):** sway ±6 degrees about the hook (period about 3 s).
- **Fan:** stays still until Modeling delivers separable blades. It must not be faked by spinning the whole model.

## Constraints

- **Cost:** one transform or one material parameter per visible item per frame. Animate only items in the space the local child is viewing (`TownWorld.set_view`); rooms that are not shown have no nodes. Cap at, say, 20 animated items per view. Expected cost is negligible against rendering; to be measured on the Mac (frame time with 10 mirror balls and 10 screens in one room vs none).
- **Lifecycle:** animation state lives on the item's node, which is rebuilt when the item is edited or the view changes. No timers outlive the node; use the world's existing `_process` pass, like the swings and seesaws in `_animate_play_items`.
- **Shared state:** none. Motion is cosmetic, driven by local time. Nothing is sent over the network or saved; two devices may show different phases, which is acceptable for decoration. No protocol or schema change.
- **Placement ghost:** the ghost stays still, so placement remains readable.
- **Photos and thumbnails:** catalog thumbnails stay static renders.

## Modeling handoff needed (not requested here)

- `ceiling_fan_light`: blades as a separate node centred on the rotation axis, or a light kit centred on that axis.
- Screens: UV-mapped screen faces, if picture content is ever wanted.

These would be new frozen versions under the Modeling lane's process. This plan does not ask for them.

## Future Mac visual checks (when implemented)

- A short rendered capture of the living room with a mirror ball (two frames 0.5 s apart showing different facets) and a screen (two tints). The fan must be shown still, as a negative control.
- The frame-time comparison above, and the evening-light regression (the lamps still light up).

## As implemented (r20-motion, 2026-10-14)

The user asked for slow fan-blade rotation, a gentle sway of suspended decorations, and a slow, gentle brightness change for a few lights, with a local, persistent **Reduce motion** setting. The plan above was updated as follows.

**The batch (exact catalog ids, `DecoMotion.MOTION` in `game/scripts/world/deco_motion.gd`):**

| Item | Motion |
|---|---|
| `ceiling_fan_light` | **spin**: the three blades turn a quarter turn per second about the motor's vertical axis (x -0.146, z 0) |
| `bird_mobile` | **sway**: from the hook (the item origin), ±3.5° and ±2.5° with periods of 3.4 s and 4.7 s |
| `red_paper_lantern` | **sway**: as the mobile |
| `candle_ring_chandelier` | **glow**: its lamp breathes between 85 % and 100 % of its evening brightness over 6 s; off by day |
| `bamboo_floor_lantern` | **glow**: as the chandelier |

**Corrections to the plan, from the frozen geometry (connected pieces of the merged mesh):**
- **`ceiling_fan_light`** has three separate blade pieces (108 triangles each, thin flat plates), and the motor, canopy, rod and light kit are centered on an axis at x -0.146, not at the hook origin. The bulb is centered under that motor, so it is not "off-centre" relative to the fan as the plan said.
- The game copies the blade pieces into a turning part and the rest into a static copy, **per instance, at runtime**. The GLB file, its shared mesh and its materials are unchanged, and thumbnails and ghosts use the plain model.
- **`circulator_fan`** (standing fan) has **no blades**: it is a closed drum (body) behind a fixed front guard (three rings and eight spokes) with a small hub. Turning the guard or the hub would misrepresent it, so it stays still. **Modeling dependency (not requested here): blades behind the guard as their own node or piece.**
- The mirror ball and screens are not in this batch.

**Rules kept:**
- Every pose is computed from the time alone, on top of the part's transform recorded once, so nothing drifts or accumulates.
- The item's root transform, rotation, anchors, markers (Light0, seats, supports), collision, selection and placement rules are untouched.
- Only items of the space on screen are animated. Rooms not shown have no nodes, and a removed or rebuilt node drops out of `TownWorld.deco`.
- Glow scales the lamp energy the world sets (1.6 × evening) on each item's own light, so no shared material is modulated. The fan's blades use that instance's own material copy.
- Nothing is sent, saved or changed in the town (protocol 10, schema 2 unchanged). The headless server has no world and no motion.
- **Reduce motion** (the Sound and music settings dialog, six languages) is saved locally in `user://settings.cfg` (`display/reduce_motion`). It puts every part back to its recorded pose, and lamps to their steady brightness, at once and after restarts.

**Known limit, not changed:** the catalog's `radius` for `ceiling_fan_light` (0.63 m, used for ceiling spacing) is smaller than the still model's reach (0.785 m from the hook). The turning tips reach 0.838 m. This is catalog data owned with the model release; the motion adds at most 5.3 cm.

**Tests:**
- `test_deco_motion`: the split (3 × 108 triangles, axis, exact coverage, shared mesh unchanged); poses from time only; pure turns; bounds (sway within 7 cm of the still shape, blade tips within 6 cm of the still reach); root and markers untouched; material isolation and independent phases; plain thumbnails; glow range and step (no flashing); still pose; persistence; no network or save access.
- `motion_tour.gd` (rendered on the Mac): time-separated originals; pixel change of each moving item; Reduce motion by real taps; frozen-after-toggle originals and pixels; stairs, removal, re-placing, reload; turned back on; a 17-decoration workload with the motion pass timed. Desktop timings are not iPhone or iPad performance or battery measurements.

