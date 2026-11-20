# Assessment: turning and zooming the camera in the zoo

**Status: APPROVED by the user on 2026-11-16 and part of the zoo's first release.** The user explicitly authorised turning plus a moderate zoom in the zoo, through the coordinator. The owner chose the recommended option below:
- the existing 45° turns;
- three fixed zoom levels (8, 9.5 and 15 m);
- the zoo's default view on each arrival, and the town's view restored on return;
- snaps under Reduce Motion.

The assessment that led to it follows. It was written by the production owner from the code as it stands. Any change it proposes is for the standalone zoo map only; the town, the rooms and every other place keep their camera. It does not replace or narrow the zoo's first release ([zoo-and-world-journeys.md](zoo-and-world-journeys.md), section 22).

**The user's wish:** both turning and a moderate zoom in and out.
- Turning at any angle is welcome if practical; a fixed 90° per press is explicitly acceptable.
- Continuous zoom is optional; a few fixed zoom levels are acceptable.

## What exists today (read from the code)

| | Code | Today |
|---|---|---|
| Turning (yaw) | `CameraRig.rotate_step(dir)`, `goal_pose()`, `yaw_step`, `game/scripts/world/camera_rig.gd` | Eight 45° steps, outdoors only (`if not in_room`). The camera glides to each step (`_update`, rate 4/s, about 0.25 s to settle) |
| Zoom | `ZOOMS := [9.5, 15.0]`, `zoom` (0 or 1), `toggle_zoom()` | Two fixed levels |
| Pitch, field of view | `PITCH` 40°, `FOV` 42° | Fixed |
| iPad controls | `Hud._cam_tools`: *Rotate view left*, *Rotate view right* and *Zoom* (toggle). A pinch (`InputEventMagnifyGesture`) and the mouse wheel in `PlayController._unhandled_input` | Shown only when `space == "town"` (`Hud.bind`) |
| Apple TV and controller | `PadInput`: **L / R** call `rotate_step`. **ZL / ZR** scroll a list or else zoom. The left stick walks, the right stick moves the pointer, the D-pad jumps between buttons | Blocked while a dialog is open |
| Things that follow the camera | Walking (`flat_forward`, `flat_right`); taps (`ground_point`, `pick_item`, `pick_animal` use the live camera); placing (`frame_fit`, `room_fit` take the yaw and distance and never come closer than the zoom chosen) | Correct for any yaw and distance |
| State | `yaw_step`, `zoom` in the rig | Local to the device; not saved, not sent |

The zoo uses the outdoor camera (`set_room(false)`), so **L / R and ZL / ZR already work there.** Only the on-screen buttons are hidden. The zoo design's section 11.3 already asks for them on every outdoor map.

## Turning

| Option | Reuse | Effort | Risk |
|---|---|---|---|
| **Keep 45° steps (existing)** | Everything above. The zoo's layout rules (H1 to H4) and the planned readability test (`test_readability_in_place`) already cover all 8 steps | Show the buttons in the zoo (already a first-release item) | Low |
| 90° per press (the user's fallback) | The same code: a press adds 2 steps. Four views to check instead of eight | One line, if the user prefers fewer, bigger turns | Low. A turn moves the view further at once, so it may be harder to keep one's bearings |
| Any angle (drag to turn) | Movement and picking already follow any yaw | New: an iPad two-finger twist (one finger already walks, drags a held thing and scrolls lists); a TV control for continuous turning. The right stick is the pointer and the left stick walks, so it needs a new mapping, against design 16.1 "no new mapping"; layout rules sampled, not proved, between steps | Medium. Gesture clashes, a new TV control, disorientation for an 8-year-old |

**Recommended:** keep the existing 45° steps. They already exist, are already reachable by L / R on the TV, and are already covered by the layout rules. They are a finer version of the user's acceptable 90° fallback, at no extra cost. If the user prefers 90°, it is a one-line change, not a new system.

## Zoom

Measured with the real projection (`CameraRig.pose_xform` and `project`, TV layout 1820 x 1024, pitch 40°, focus 0.6 m above the child):

| Distance | Ground visible (deep) | Lion 1.55 m on screen | Lion eye (0.14 m) | A 2 m head stays in view up to | iPad: width at the child |
|---|---|---|---|---|---|
| 7.0 m | 12.0 m | 235 px | 30 px | 1.9 m beyond the child | 7.6 m |
| 8.0 m | 13.5 m | 204 px | 26 px | 2.7 m | 8.6 m |
| **9.5 m (default today)** | 15.8 m | 171 px | 21 px | 3.8 m | 10.1 m |
| 12.0 m | 19.5 m | 135 px | 17 px | 5.7 m | 12.7 m |
| **15.0 m (wide today)** | 24.1 m | 107 px | 13 px | 7.9 m | 15.8 m |

What the numbers mean:

- **Closer helps the user's main wish** (larger, readable animals). At 8 m a lion is 19 % larger than at the default; at 7 m, 37 % larger. A monkey's face disc (0.34 m) reaches about 56 px at 8 m.
- **Closer shrinks the height budget.**
  - At 8 m, a 2 m head stays in view only 2.7 m beyond the child (3.8 m at the default).
  - Animals on far terraces or crags then leave the top of the frame, which is why rule H1 is defined at the default zoom.
  - A player who zooms in looks closely at what is near; zooming out shows the rest.
  - Look framing (design 11.1) already steps the camera back when a head and the child do not both fit.
- **Wider** is already there (15 m). Beyond 15 m, eyes drop under 13 px and the TV's view reaches 31 m wide at the far edge. Not needed.
- **Map edge.** The zoo is 84 x 64 m. At 15 m the far edge of the view can pass the map's border near the edges and at the station. The zoo world draws a ring of hedges and trees outside its walkable border for this in any case (the existing eight turns already reach those views). Closer zooms show less, so they add nothing here.
- **Safe areas and HUD.** The HUD's two tool places (`Hud.zones`), the step-aside rules and `frame_fit` work at any distance. They measure with the live pose. A closer view puts more of a large animal under the top bar and the side menus. That is the existing step-aside rule's job for a held thing, but not for animals, which the HUD does not avoid outside Look.
- **Occlusion.** Nearer views lower the camera (at 8 m it is 5.1 m up, against 6.1 m), so crags and tall rocks hide a little more behind them. Rule H3 keeps the child visible at the default; at 8 m it holds for rocks of 0.9 m or lower beside a path, which is the rule.

| Option | Effort | Risk |
|---|---|---|
| **Three fixed levels in the zoo: 8 m (closer), 9.5 m (default), 15 m (wide)** | `CameraRig` gets a level list per map (the zoo's three; everything else keeps its two). `toggle_zoom()` becomes zoom in / zoom out by one level. The pinch and the wheel already know the direction. ZL / ZR already zoom. The HUD's Zoom button steps through the levels, or splits into + and −. Tests | Low to medium. Every code path that reads `ZOOMS[zoom]` must read the map's list |
| Continuous zoom between 8 and 15 m | The same, plus a continuous value. The iPad pinch gives it naturally; the TV needs held ZL / ZR | Medium. More states to test, and a TV hold behaviour |

**Recommended:** three fixed levels in the zoo only (8, 9.5, 15 m). Eight metres rather than seven keeps a 2 m head in view 2.7 m beyond the child, so animals at the show spots near a bay stay whole. Seven metres loses most of them.

## Turning and zooming together

- **24 views:** 8 turns x 3 zooms. Movement, picking, labels (billboards) and placing work in all of them, because they read the live camera.
- **What the tests can check for each view** (headless, by projection):
  - every show spot from its bay;
  - the child on every path cell against the top bar and the safe area;
  - the station, the stop and the stations in view when the child stands at them;
  - a tap on an animal's projected box hits that animal.
- **Defaults and reset.** On arriving in the zoo, the turn and the zoom start at the designed view (yaw step 0, looking north from the station; zoom 9.5 m). On returning to town, the town's own turn and zoom come back. Nothing is saved or sent: the camera stays local to each device, and friends' views are independent.
- **Transitions.** Turns and zoom changes glide as they do today (about 0.25 s). **Reduce Motion:** in the zoo they snap instead of gliding, which is a few lines in `_update`. Elsewhere they are unchanged.
- **Controls, with no clashes:**
  - iPad: Rotate left and right; Zoom in and out (or the one Zoom button stepping through the levels); a pinch for zoom. No new one-finger gesture.
  - Apple TV and controller: L / R turn, ZL / ZR zoom (both existing). No new mapping. While a list scrolls, ZL / ZR keep scrolling it (existing rule).
  - Siri Remote alone: the existing remote mapping (`design/tv-controller.md`) has no free turn or zoom. A remote-only player keeps the default view. This is a limit to state, not to solve now.
- **The seven species and the monkeys.**
  - Animals are code-built rounded shapes and read from every side.
  - Monkey actions are tied to anchors, so they play the same in every view. Ring Run and vine swings read best across the view (east and west turns), and as up-and-down from along it.
  - At the close level, the Ring Run's top (2.7 m) leaves the frame when the monkey is more than about 2 m beyond the child; it stands beside the lane (rule H2), so it stays in view while walking the lane.
- **Performance.** No new cost: the same draw calls per view. The wide level exists today. The edge ring has its own budget.

## Files a decision would touch (zoo only)

| File | Change |
|---|---|
| `game/scripts/world/camera_rig.gd` | Zoom levels per map: the zoo's 8 / 9.5 / 15, the others' 9.5 / 15. `zoom_in()` and `zoom_out()`; the zoo's snap under Reduce Motion; keep and restore the town's view across a journey |
| `game/scripts/world/play_controller.gd` | The pinch and the wheel step one level; the journey sets the zoo's defaults and brings back the town's view |
| `game/scripts/ui/pad_input.gd` | ZL / ZR step one level (already wired to zoom) |
| `game/scripts/ui/hud.gd` | Camera buttons shown on every outdoor map (already a first-release item); Zoom steps through the levels |
| `game/tests/zoo_tests.gd` | The 24-view projection checks, the reset and restore, and the controls headless |
| `design/tv-controller.md`, the zoo design | Record the decision |

## Verified without rendering, and deferred

**Without rendering:**
- every projection check above;
- camera-relative stick movement in each view;
- picking;
- the reset and restore;
- the controls (touch events and controller actions driven headless);
- the snap under Reduce Motion.

**Deferred to rendering, devices and the user:**
- how habitats and backdrops look from the north and the sides, and up close;
- whether the closer level makes animals easier to enjoy;
- whether turning helps or confuses a child;
- the feel of the glides;
- the remote and controller ergonomics on a real Apple TV.

## Recommendation, effort, decision

**The simple option:**
- turning stays the existing 45° steps (90° if preferred);
- zoom gets three fixed levels in the zoo only (8 m closer, 9.5 m default, 15 m wide);
- the zoo's default view on every arrival, and the town's own view back on return;
- snaps under Reduce Motion in the zoo.

No free orbit, no continuous zoom, no pitch change, no new controller mapping.

**Effort:** small to medium, about a day of the owner's work with its tests. The turning part is nearly free.

**Risk:** low. The main one is a closer view hiding tall animals at far spots, which zooming out solves.

**Decisions (2026-11-16):**
1. The user approved the closer zoom. It supersedes the zoo design's section 4.1, item 3 ("no closer zoom step") **in the zoo only**. The angle, field of view and style stay the same.
2. Turns stay **45°**: the existing facility, which is finer than the user's acceptable 90° fallback.
