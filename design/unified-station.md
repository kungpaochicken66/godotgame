# The unified tram stop: Thousand Town, the Roller Coaster Workshop and the Lantern Reef

Candidate `unified` r1 (freeze ID `unified-r1`), EC2 source owner, 2026-11-19.

## What is combined

| Part | Source | How it is reached | Kind |
|---|---|---|---|
| Thousand Town | frozen `thousand-town` r1 (`design/thousand-town.md`), unchanged | "Ride to Thousand Town" | a shared map (the tram, the authority, protocol 20) |
| Roller Coaster Workshop | Workshop r4 from the Mac (`tools/coaster/README.md`, `VERIFICATION.md`): six coasters, `game/coasters/` runtime data, `tools/coaster/presets/` editable saves | "Roller Coaster Workshop" | local to the player (`scripts/world/coaster_park.gd`) |
| Lantern Reef | the Mac's native reef (`scripts/reef/`, `assets/reef/`), informed by "Abyssal Garden" by Maksymilian Dendura (MIT, github.com/Noniv/abyssal-garden at a596354; `game/assets/reef/ABYSSAL-GARDEN-LICENSE.txt`) | "Explore the lantern reef" | local to the player (`scripts/reef/reef_dive.gd`, opened by `main._open_reef`) |

The Workshop and the reef are local excursions: the town session keeps running, the child's town position is kept, and
nothing new crosses the network. So the protocol stays **20** (Thousand Town's); the HK server note of Thousand Town
still applies.

## The stop's entries (`scripts/ui/hud.gd`)

At the town's tram stop the action buttons offer the journeys: Ride to the zoo, Ride to the city, Ride to the city
(web) where offered, and Ride to Thousand Town. The two local destinations, Roller Coaster Workshop and Explore the
lantern reef, sit on a row above them. When the journeys overflow one row (Thousand Town's rule, `_fit_context_row`),
the local destinations join the overflow row: on a separate third row the D-pad (PadInput's cone rule) could never
reach "Ride to Thousand Town" between them (found by the station tour at 1920 x 1080; fixed in the HUD, not the test).

## Controls and returns

| | Touch | TV controller |
|---|---|---|
| Open the Workshop | tap its button | Start (+) (Workshop r4's binding), or D-pad and A |
| In the Workshop | cards, walking, Switch view, Get off; **Ride home** at every platform after getting off (r4) and at the central tram | D-pad and A on the cards; L / R views while riding; A gets off; **B or + / Start rides home** whenever the child is off the train (r4), as the park's hint says |
| Open the reef | tap its button | D-pad and A |
| In the reef | drag on the left half swims, drag on the right half looks, hold Ascend / Descend, the view button, Back | left stick swims, right stick looks, ZR / ZL (RT / LT) rise and sink, the context button changes the view (X on a Nintendo pad, Y otherwise), **B, + / Start or - / Select returns**; the Siri Remote's Menu returns. A hint panel in the controller's own labels shows while a controller is in use (r4), laid out inside the TV safe area in every language (r5) |
| Thousand Town | as in thousand-town r1; the wheel's view turns with a drag and zooms with a pinch (r4) | as in thousand-town r1, plus (r4): concise hints in the controller's labels; **- / Select steps the time** Day, Dusk, Night, Auto; on the ferris wheel the right stick looks around and ZL / ZR zoom |

Every return comes back to the stop: the Workshop's and the reef's restore the town's world, HUD, camera, walking and
the controller layer with the child where it left; Thousand Town's Ride home arrives in front of the stop.

## unified r6: living-room feedback on the installed r5 (2026-11-20)

**Thousand Town's actions (`core/places.gd` `offers`, `ui/hud.gd` `_offer_world_actions`).** Each HUD action was
tried in Thousand Town, with this outcome:

| Action | In Thousand Town on r5 | r6 |
|---|---|---|
| Hello (friend echoes) | the authority refuses it: echoes exist only in the town, the zoo and rooms (`TownModel.is_space`) | hidden |
| Pets | adopts into, and sends home to, the town's Pet room | hidden (a pet already following still follows) |
| Story | story cards for the town's story board, with invitations | hidden |
| Lantern scrapbook (0 / 8) | the town's lantern spots and the zoo's stickers | hidden |
| Decorate | already hidden (not decoratable) | hidden |
| Ctrl+Z (desktop) | undid the last placement *in the town* | does nothing outside decoratable places |
| Activities, Dress up, the emotes, photo, sound, language, leave, the camera | work as anywhere | kept |
| Time, Look, the show buttons, Ride home, the action button | Thousand Town's own | kept |

A hidden action is neither a D-pad stop (`PadInput.targets` takes only visible controls) nor tappable. Everything
comes back on the return (`space_changed`). The city is unchanged (Hello there fails the same way; it is outside this
feedback).

**Focus on return (`ui/pad_input.gd` `_track_focus`).** A press with A remembers the control for its map. Arriving
back in the town after a journey puts the pointer on the control that left (for example "Ride to Thousand Town"), once
the stop's buttons show. Arriving elsewhere puts it on the action button, if one shows. Any pointer move by the player
cancels this. After the Workshop or the reef (the HUD and the controller layer were paused), one motion where the
pointer rests gives the control under it its focused look again; before this, the pointer sat on the button without
the button showing focus.

**unified r7 (the Mac's real-window 1080p run on r6, Nintendo).** After the zoo, the city and Thousand Town the pointer
was back on the button that left, but the button showed no ring: the focused look came from the GUI's mouse hover.
In a real window that hover is taken by the fading travel card and by the window's own mouse. On EC2 headless it
survived, so the r6 tour passed. Now the pad keeps its own selection, the enabled control under the pointer, worked
out every frame (`PadInput.selected` / `selection()`). The pad layer draws that control's focus ring itself (the
`PadFocusRing` node, the theme's ring on the control's own corners), whatever the hover or an overlay says. Nothing is
selected while a journey's card is up, or with the pointer hidden. The mouse and a finger keep the theme's hover ring
as before. After every return, the station tour also sends a window mouse motion elsewhere, which takes the GUI hover
away, and requires the selection and the ring to stay on the button that left.

**Destination buttons (`ui/ui_kit.gd` `style_destination`).** The stop's six destinations were in three styles:
green primary (zoo, Workshop, reef), cream (city, web city, Thousand Town), and two text sizes. They are now one
button in the game's theme: normal (the panel with its soft border), **focused** (the theme's focus ring, yellow,
4 px, over the soft fill; this is what the controller's pointer and the mouse show), pressed (the soft fill with the
accent border), disabled. All have the tram icon, 88 px and 26 px text. The context buttons return to their own looks
away from the stop. Ride home (the zoo, the city, Thousand Town) and the Workshop's platform Ride home use the same
states.

**Action UI in the four worlds (the town, Thousand Town, the Workshop, the reef).**

| Finding (r5) | r6 |
|---|---|
| Focus looked different in each world: theme hover (a pale accent border), green primary nearly unchanged, the Workshop's selected card a thick brown border, Thousand Town's glass time buttons only more opaque | one focused state for every action button: `UI.focus_box`, the yellow focus ring (theme hover, primary buttons, icon buttons, the Workshop's selected card, the time buttons) |
| Hint panels: the town's white panel with 20 px dark text; the Workshop's dark green panel, 26 px white; the reef's dark blue, 22 px white; separators of four spaces or "·"; alternatives as "LB RB" or "B / +" | one form, `UI.hint_panel` / `hint_label` / `hint_part` / `glyphs`: the town's panel and text, "glyph  action" parts four spaces apart, alternatives "B / +" (the town's turn hint now reads "LB / RB") |
| Hint placement | the town's (and Thousand Town's) bar is placed by PadInput clear of buttons and text, as before; the excursions put theirs at the safe area's top right, grown leftward by containers (the reef's r5 layout, now also the Workshop's, whose hint was top left under its title) |
| The Workshop drew in the TV's overscan margin: title at x 46, action row 26 px from the bottom | the Workshop's UI is inside the TV title-safe area (`UI.fit_safe_area`), as the HUD and the reef |
| The Workshop's action row: 76 px buttons, 24 px text, 18 px spacing | the town's action row: 88 px, 28 px text (primary), 14 px spacing |

Kept on purpose: each world's local actions and states (the Workshop's cards, Switch view, Get off; the reef's Back,
view, Ascend and Descend; Thousand Town's chosen-time lighting, Look's tint, the show buttons' countdowns).

**Coaster clearance (`tests/coaster_clearance.gd`, `world/coaster_line.gd`, `world/coaster_park.gd`).** The audit
checks the park the game actually builds, at every frame of all six laps (0.5 m apart). It tests the track, all three
cars and the seated child against terrain, scenery, platforms and other track. r5 had 135 conflict intervals:

- **Hills.** Mainly the 24 distant backdrop hills (r ≈ 380–430 m), which Comet, Crystal Mine, Neon Wings and Phantom
  Castle ran through, up to 38 m deep. This covers all eight points the Mac rendered: Comet 344 and 520 m, Crystal
  460 m, Neon 14, 275 and 1160 m, Phantom 400 and 700 m.
- **Supports.** Columns of upper sections passed through the trains and the child.
- **Phantom Castle.** Arch plinths, piers and the canopy trim.

r6 lowers 16 of the 24 hills just enough to clear every ride by 0.3 m; all 24 remain, but the backdrop is flatter
behind those four rides. It leaves out 44 supports that would pass through a train, the child or scenery. Column tops
end under the ties. The Phantom hanger arms move to the free side or a shorter reach, with the mount raised to 0.6 m,
and the canopy's track-side edge is 0.45 m narrower. The ride data (`game/coasters/*.json`) is unchanged.

After the repairs the audit passes with 0 intervals. The intentional tunnels keep open portals, with minimum
clearance from the car and rider envelope of 1.71 m (Crystal Mine), 1.01 m (Neon Wings) and at least 2.0 m (Phantom
Castle). The audit requires at least 0.25 m. Records: `docs/local-validation/unified-r6/coaster-clearance-r5.*`
(before) and `coaster-clearance-r6.*` (after). `tests/coaster_frames.gd` renders matching rider-eye and chase frames
(`<ride>_f<frame>_v<view>.png`) in r6 and, copied in, in r5 (`tools/coaster/README.md`).

**Tap on a building in Thousand Town (`world/thousand_world.gd` `building_on_ray`, `world/play_controller.gd`
`thousand_tap_target`).** On the Mac's 1080p touch run, the tap on Courtyard Housing's front walked the child into the
wall instead of opening "Who's here?". This reproduced on EC2. The finger's ray met the ground behind the facade.
Re-aimed at the ground's height there (meant for the footbridges), the point fell just outside the footprint. A tap
now asks the building whose volume (footprint × storeys) the ray meets before the ground, else the site under the
ground point as before. The tour aims with the same function.

## Merge record

- Workshop r4's base is exactly frozen tv-diag r1 (all 2,006 files). Its changes were merged three ways onto
  thousand-town r1: `pad_input.gd` and `play_controller.gd` cleanly, `hud.gd` with one conflict (the context row's
  container), resolved by hand as above. Its 16 strings joined the six catalogs. Its `export_presets.cfg` change was
  not in the delta; the include filter now carries `coasters/*.json`, `coasters/*.jpg` and the reef's licence.
- The reef's shared hooks were merged selectively: `main.gd` (`_open_reef`, `_close_reef`, `--reef-preview`),
  `tv_remote.gd` (Menu closes the reef), the HUD's `reef_requested` signal and the 8 strings. Not merged: the guide's
  "Explore the lantern reef" button (the entry is the stop), and 14 translation edits in the reef's locale files that
  were outside its hook patch (spacing around `%s` in zh-CN, "Hier platzieren" in de); they can come as their own
  change. `reef_dive_tour.gd` now enters from the stop.
- The fonts were regenerated from the merged catalogs.

## Tours

- `game/tests/station_tour.gd`: the stop, every destination (the Workshop, the reef, the zoo, the city, Thousand
  Town) and every return, touch and TV (header). r6 added: the return HUD and pointer focus, the destinations' one
  look, safe-area checks in every world, and the main world's actions absent in Thousand Town. Run at 1920x1080
  (touch, Nintendo, standard) and 1366x1024 (touch).
- `game/tests/coaster_clearance.gd` (r6: every lap sample against terrain and scenery; headless, exits 1 on a
  conflict), `game/tests/coaster_frames.gd` (r6: rider-eye / chase frames for before / after, rendered on the Mac).
- `game/tests/coaster_tour.gd` (Workshop r4), `game/tests/reef_dive_tour.gd` (the reef, rendered),
  `game/tests/thousand_loop_tour.gd` (Thousand Town's whole loop, rendered frames including Night).
