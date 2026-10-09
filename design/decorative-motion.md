# Design: decorative motion for the fan, mirror ball and screens (plan only, not implemented)

Status: read-only design, written 2026-10-09 (r16 batch, item 5). No GLB or Modeling-owned builder was changed.
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
