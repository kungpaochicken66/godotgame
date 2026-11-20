# Thousand Town: a separate destination adapted from "Qianren Xiaozhen (Thousand Town)"

**Status:** design and implementation started 2026-11-18 by the EC2 source owner (Opus). This is a separate development candidate on top of the sealed `city-web` r3 (`build/dual-host/city-web/SEAL-r3.md`).

**Not authorized for this feature:** commit, push, install or deployment. The work log is `build/dual-host/thousand-town/CHECKPOINT.md`.

## 0. Source and attribution

**Upstream:** https://github.com/YiHuiShiBY/thousand-town, commit `1332ef29d6208a4192bf7400e0085033fd773a3c`, by Yihuishi / YiHuiShiBY.
- **Names in this English document are romanized** (`scripts/check.py` keeps CJK text out of source files). The original title and the author's name in Chinese are carried exactly in `game/thousand_town/data/town.json` (`source`), and the in-game credit fills them in, in every locale.
- It is licensed **CC BY 4.0**. We credit the author with the link, list our changes (section 12), and imply no endorsement.
- The pinned copy is `build/dual-host/thousand-town/upstream/thousand-town-1332ef2/`.
- The studies are `build/dual-host/thousand-town/study-{layout,residents,scene}.md`.

**Credit line,** shown in the game's destination info and in `docs/assets.md`, translated in the six locales:

> Thousand Town is adapted from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY (github.com/YiHuiShiBY/thousand-town), CC BY 4.0. Changed for Lantern Lane: units, characters, controls, lighting, and the additions listed in design/thousand-town.md.

**Not used:**
- p5.js (LGPL-2.1).
- Three.js. Its code is not used; Godot draws the town.
- The guestbook bottles: a live network feed of third-party content.
- The author's branding and the "like, coin, favourite" call-to-action texts and icons.
- The airship advert.
- The National Day dressing.
- The ESO Milky Way JPEG: the shipped file does not match its own credit file.
- The Chinese-only sign atlases. They are replaced by translated signs.

## 1. Units and scale (one metre per unit)

- **Upstream uses 1 unit = 0.5 m.** Every upstream position and size is multiplied by **0.5**.
  - The town board is x ±95 m and z ±129 m.
  - A storey is 3.0 m and the plinth 0.7 m. Cross streets are 6 m wide; avenues and ring roads 5 m.
  - The canal is |x| < 7.5 m.
  - The ferris wheel has radius 10 m, with its axle at 13 m.
- **The child is the yardstick:** H = 1.30 m to the top of the head (`design/object-scale-and-surfaces.md`), walking at 3.4 m/s.
- **Residents use Lantern Lane's people rig** (`art/city_people.gd`; at scale 1 that is about 1.8 m to the top of the head).
  - **Adults are scale 0.94, about 1.70 m.** Women are ×0.97, as upstream.
  - **Children follow upstream's height curve** relative to the adult: age 5 ×0.55, age 12 ×0.76, with the curve between. That puts a 7-year-old near the player's 1.30.
  - **Upstream's adults are 2.06 m at 0.5 m per unit,** taller than its own 1.8 m doors. That is changed here: Lantern Lane's adults are 1.70 m.
  - **Doors are 2.1 m high** (upstream 3.6 units = 1.8 m). The doors are the one architectural size changed, so adults fit through them.
- **Vehicles:** cars are about 4 m long (upstream 8 units). Buses are scaled to match the city's buses.
- **Checks:** a scale test asserts storey, door, street, child, adult and car sizes against these numbers.

## 2. Architecture

**Pattern:** city-web in reverse. Upstream's pure planners run in Node, the pinned and hash-checked copy, and write data and fixtures. Godot builds and runs everything natively, so it works on iPad, iPhone and Apple TV alike.

| Piece | Path | Role |
|---|---|---|
| Extractor | `scripts/thousand_town/extract.mjs` | Checks the pinned commit and file hashes, then loads upstream's UMD planners from the pinned copy (no browser, no network). Writes `game/thousand_town/data/`: `town.json` (lots, buildings, roads, bridges, stops, waterfront, frontage parts, trees, landmarks, already in metres), the decoded district and housing GLBs, and the packed-array assets as `.glb`. Deterministic, and byte-identical across two runs. |
| Sim fixtures | `scripts/thousand_town/sim_fixtures.mjs` | Writes `tests/thousand/fixtures/*.json`: the roster, `buildDay` for days 1, 6, 7 and 42, `stateAt` and occupancy at chosen minutes, mulberry32 and hash32 sequences, lighting factors, transit motion. |
| Map data | `scripts/core/thousand_map.gd` | Loads `town.json`. Constants: lots, buildings, doors, stops, the station, the arrival point, `HALF`. |
| Simulation | `scripts/core/thousand_sim.gd` (+ `thousand_sim_data.gd`) | **The port:** the census (1000), names, schedules, `buildDay`, `stateAt`, occupancy. Pure GDScript with packed arrays, no nodes. Parity with the fixtures, exact where upstream is exact. |
| Clock and lighting | `scripts/core/thousand_clock.gd` | The town clock (day, minute), daylight, lighting factors, sun and moon formulas, event schedules (fireworks, fountain, helicopter, airship, searchlights). Pure functions; parity with the fixtures. |
| Navigation | `scripts/core/thousand_nav.gd` | **Built.** Where a child may stand and how high the ground is, from `solids.json` (1,279 footprints, 61 walkable surfaces with heights or profiles) plus what the world layer leaves to `town.json`: the 4 towers, the frontage (compound walls, railings, hedges, shop rings), the plaza monument, benches and planters, the carousel and teacups, the plaza fountain's ring of water, the park lawns. 6,235 solids in a 4 m spatial hash. A solid blocks where it reaches into 0.25..1.8 m above the local ground. The canal is open only on a bridge deck; tunnels' sunk roadways and viaduct ramps are closed (a child walks under the high viaduct deck); a step may not climb or drop more than 0.6 m. `resolve()` walks a step in 0.2 m pieces and slides along x or z. Deterministic; about 7 µs a query on EC2. Roads are walkable (the residents' pavement graph is `art/thousand_people.gd`'s own). |
| World | `scripts/world/thousand_world.gd` | **Built.** Loads the 7 world GLBs with GLTFDocument and swaps every `tt_*` material for one small shader (linear vertex colour as albedo). Chunk nodes are merged per cell (16), layer and material: 99 meshes. Kept apart: the doors (38, animated by the building's door-open), the ferris wheel (rotor plus 3 cabin MultiMeshes), the canal fountain and its 116 droplets, the balloons, the vehicle templates (hidden, for transit). From W-DATA: the towers (district.glb modules as MultiMeshes, tinted per tower, floors glowing by occupancy), frontage and office parts (box MultiMeshes per cell), civic entries, plaza monument, benches and planters, ride bases and rotors, the helipad. All window panes are one mesh; a per-building level array lights them. Water (canal and plaza ring), light pools, 4 real lights. Builds in about 1.1 s headless on EC2, 0.65 s of it the GLB parse. |
| Residents | `scripts/art/thousand_people.gd` | **Built and integrated** (town_world.gd creates them under the world, on its sim and plans, behind the journey card). The figures: `city_people`-style part MultiMeshes with role looks. Who is drawn: residents on the street (a real resident each, routed door to door), at outdoor venues, and at the stops, nearest first, within the budget (section 8). |
| Transit | `scripts/world/thousand_transit.gd` (+ `thousand_clock.gd`) | **Built and integrated.** Upstream's station loop with 3 buses and 4 taxis, the timetable, and the street-traffic loops. **Lantern Lane addition:** buses stop at upstream's bus stops beside the loop (bus-stop-1, 3, 4) and the bays, and the player's child can board, ride and get off (section 13, I4; local to the device). |
| Sky and events | `scripts/world/thousand_sky.gd` | **Sky built:** a dome that follows the camera (gradient, twilight glow, sun and moon discs, turning stars), its own sun and moon lights on upstream's daily circle, and the environment's background, ambient and fog, from `thousand_clock.gd` `sky_state` and `factors` (section 9). **Not yet:** fireworks, the plaza fountain's jets, helicopter, airship, searchlights. |
| Authority | `scripts/net/thousand.gd` (autoload `Thousand`) | The shared town clock and time mode: auto, day, dusk, night; speed. Bus boarding seats. Like `City`'s weather, any child may press, and the authority decides. |
| Integration | `places.gd`, `session.gd`, `play_controller.gd`, `town_world.gd`, `hud.gd`, `camera_rig.gd`, locales | The map `thousand`: the journey from the town and back; the HUD's time buttons and inspect panel; camera follow and occlusion; touch and TV controls. |

## 3. The map and journeys

- **Place:** `Places.THOUSAND = "thousand"`, listed in `MAPS` and `DESTINATIONS`. It is reachable from the town, with return to the town, and **offered on every device, the TV included**.
- **Arrival:** the tram arrives at **the station** (upstream lot 12, A4). The child steps onto the station forecourt.
- **Arrival framing:** the camera stands behind the child, looking east along the 0 m pedestrian street toward the canal and the towers. The child sits in the lower third; the first view shows the plaza direction and a tower. The tour checks it.
- **Return:** "Ride home" at any time, as in the city, or walk back into the station.
- **Protocol 20:** the new map and authority messages. The save schema is unchanged: nothing in Thousand Town is saved.

## 4. Time and lighting under player control

**The town clock** is (day, minute), shared through `Thousand`.
- The first arrival starts at 08:00 on day 1, a Monday. **Not the real local time,** unlike upstream.
- After that the clock runs only while someone is in the town.

**Modes:**
- **Auto:** the cycle runs at 1 sim minute per real second (a 24-minute day), or **2× / 4×**.
- **Day, Dusk, Night:** jump to 12:00, 18:40 and 21:30 and **hold** there. The residents keep the plan of that held time.

**Buttons:** four glass buttons on the right, like the city's weather buttons: sun, sunset, moon, and a circular arrow for Auto. A long press, or a second press on Auto, changes the speed.

**Lighting:** upstream's formulas through Godot lights (section 9). The sun and moon paths, golden hour, dusk, lamps and windows follow upstream's factors.

## 5. Residents

- **The roster** is upstream's: 1000 residents, 20 roles, seed 20260818, ported exactly with parity tests.
- **Plans** are upstream's `buildDay`, a pure function of (seed, resident, day). `stateAt(minute)` says where each resident is.
  - Building occupancy is a count per building.
  - Lit windows follow occupancy and upstream's window rules.
- **Movement, a Lantern Lane addition.** Upstream shows anonymous proxies; here a resident on a street segment is **that resident**.
  - **Route:** along the pavement graph, from the previous building's door to the next one's.
  - **Natural pace:** 0.9–2.2 m/s for a walk, up to 3.2 m/s for joggers.
  - **Arriving early:** they linger at the destination door, then go in.
  - **A trip longer than the pace allows:** they join their route partway and fade in over 0.8 s, as upstream's figures do at its gates.
  - **Some trips go by bus:** a long trip whose two ends each have a bus stop nearby waits at a stop and is drawn in the bus while it rides.
- **Inspecting, as in upstream's "walk up to a building and see who is here":**
  - Near a door, the action button offers "Who's here?". A tap on a building does the same. On TV it is the focused action.
  - **The panel:** the building's name, open or closed, how many are here now, counts by activity, and a list (here now, lives here).
  - Picking a resident shows name, role, age, what they are doing and where, and **today's plan**, with the current part highlighted.
  - A resident walking near the child can also be inspected.
- **Names:** generated per locale from small pools of our own, stable by resident id. zh-CN uses upstream's Chinese name generator (CC BY).

## 6. Camera, following and occlusion

- **Follow camera at player height:** behind the child, about 7 m away, 2.6 m up, looking slightly down at the child's chest. It eases after the child's turns.
- **Touch:** drag orbits around the child; pinch zooms, 4–18 m.
- **TV:** the right stick orbits; the triggers zoom.
- **Overview:** the Look button flies to upstream's "home" view of the whole town, and back.
- **Occlusion:** the camera is pulled in by a sphere cast against the world's occluder boxes, never closer than 2.5 m. The boxes (31): each facility and annex body (its largest footprint in `solids.json`, up to `world.json` `top_m`), each housing wing (to its roof plus 1.5 m), each tower, and the station canopy.
- **Dithering:** a box still between the camera and the child is drawn as a screen door (one pixel in four kept) inside that box only, up to 4 boxes at once, through the building materials' shader uniforms. The ground is never dithered.
- **X-ray (thin things):** a lamp post, a tree, a sign or a fence on the line from the camera to the child's chest is drawn the same way, in a vertical slab over that line, from the child's knees to 4 m above the eye; anything within 1.5 m of the camera is not drawn at all, and to 2.2 m it is a ghost (a one-in-four ghost right at the eye veiled the whole picture when the camera backed against a frontage wall at bus stop 3, loop-touch frame 11). It is off beyond 22 m (the overview).
- **Near and far:** near plane 0.1, far plane 600 m. Fog in the distance only at night.

## 7. Controls

- **Touch, the existing Lantern Lane scheme:** tap to walk, the on-screen stick, the action button, the HUD.
- **TV:** the left stick walks, the right stick orbits, A acts, B goes back, Menu goes Home. The HUD's buttons are focusable, with the new time buttons in the focus order.
- **Responsiveness:** input to motion within one frame. The tour measures time-to-move.

## 8. Budgets

| | iPad | Apple TV |
|---|---|---|
| Draw calls in the town | ≤ 180 | ≤ 140 |
| Visible resident figures | ≤ 160 | ≤ 96 |
| Fireworks sparks | ≤ 600 | ≤ 400 |
| Real lights | sun + moon + 4 omni near the camera | the same |
| Shadows | the sun only, 2048, the near part | none |

Static geometry is merged per lot chunk and per material, with visibility ranges for the frontage detail. The construction is frozen at its end state.

### Measured (world builder, 2026-11-18, EC2)

**Evidence label:** EC2. The counts are real; the frame times are Mesa llvmpipe software GL, not device numbers. The Mac and the devices still have to measure frame time.

**Build** (`thousand_world.gd` `build()`, headless): 1.07-1.6 s, of which:
- the GLB parse (GLTFDocument, 7 world GLBs plus 4 of W-DATA's) 0.64-1.0 s;
- the merge 0.22-0.28 s;
- the navigation 0.08 s.

The first `set_time` adds today's 1000 plans, 46 ms (the roster, 23 ms, is in the build). After that, the occupancy sample runs at most every 0.5 sim minute, at about 2 ms. A new day's plans are built 120 residents a frame.

**The scene:**
- 186 geometry nodes and 99 merged meshes;
- 841,215 triangles: the world layer's 581,037, plus the towers' district modules, the frontage and office box parts, and W-DATA's rides, monument and civic entries.

**Draw calls, rendered.** The renderer's own count at the follow camera, iPad layout; the town's share is the frame minus the frame with the town hidden:

| View | The town | The whole frame (with the HUD and the child) |
|---|---|---|
| Arrival, day / night | 76 / 80 | 152 / 157 |
| Street (avenue, looking north) | 28 | 104 |
| Canal footbridge | 32 | 112 |
| Night market, night | 37 | 116 |
| Ferris wheel, dusk | 33 | 111 |
| Pulled in against the mall | 50 | 129 |
| Overview (Look) | 113 | 191 |

**Draw calls, counted** (`tests/thousand_world_tests.gd`; surfaces in the 42° 16:9 frustum within their visibility ranges):

| View | Draw calls |
|---|---|
| Arrival | 90 |
| `world.json`'s worst view, (-54, 102) heading 315 | 108 |
| The worst of 1,184 street views (a 16 m grid, 8 headings), at (24, 120) heading 270 | 116 |
| Overview | 114 |

These counts run a little over the renderer's: the renderer culls more finely. At the worst street view they break down as:
- the ground and market chunks 34;
- the buildings 19;
- the frontage 18;
- the market lanterns 8;
- the wheel 10, with its 12 cabins as 3 MultiMeshes.

**Triangles in one view:** at most 775,573 counted; 613,280 rendered primitives at the arrival and 815,278 in the overview.

**Lights:** sun, moon and 4 omni on the nearest candidates (`lights.json`). No shadows: Lantern Lane has none.

**Against the budget:**
- **The town alone stays under the Apple TV's 140** in every view measured.
- **The HUD and the child add about 76 draw calls on EC2.** That is mostly canvas items: only 13 3D instances are visible outside the town. So the whole frame is 152-157 at the arrival and 191 in the overview, over the Apple TV's 140 and, in the overview, over the iPad's 180.
- **Decide on the device count** whether the budget is the town's or the frame's.

### Gaps (world builder)

**Not built yet:**
- the events: fireworks, the plaza fountain's jets, the helicopter, the airship, the searchlights;
- the 58 spot anchors (river, fountain, tunnel walls) and the viaduct flow strips;
- the hospital ward interior (`hospital_room.glb`; behind opaque glass here);
- the balloons bob as one node, not each balloon.

**Not fitted:** the parity table of reference colours against upstream's frames (section 9) waits for the Mac GPU.

**Walking:**
- Roads are walkable. The residents' pavement graph is `thousand_people.gd`'s.
- The viaduct deck and the tunnels' sunk roadways are closed to the child.
- The world offers no `walk_route` to the residents yet.

**Occlusion:**
- Dithering covers at most 4 occluder boxes at once.
- The x-ray slab is per material uniform, set every frame on about 40 materials. A global shader uniform would make it 3 calls.

**Size:** the GLBs are 44.4 MB. COLOR_0 as normalized bytes instead of shorts would save 4.9 MB (see the data note in the report).

## 9. Lighting values (upstream's light table, through Godot)

- **Sun:** a DirectionalLight3D, colour #ffe4c4 warming to #ffb27a, energy (4.2−s)·d·(1−0.48·dusk) with s = 0.7, mapped to Lantern Lane's exposure.
- **Moon:** #8fa7cc at 0.20·(1−d)·visible.
- **Ambient:** the hemisphere sky #5f739a→#c4dbf5 and ground #1b2431→#b6a38a, as the ambient colour.
- **Background:** #131c2b → #e9f0f5, with the twilight #c98a5e.
- **Windows:** #ffe6b2 and #ffd096.
- **Lamps:** #ffe5bc, 18:30–06:00.
- **Fitting to the renderer:** the absolute values are fitted so Lantern Lane's Compatibility renderer gives the same look as upstream's frames at noon, 18:40 and 21:30. The fit is recorded in a parity table of reference colours.

**As built** (`world/thousand_sky.gd`, `world/thousand_world.gd`; the factors are `thousand_clock.gd`'s, so they are upstream's):
- **Sun:** the world's own DirectionalLight3D, aimed down `sky_state(minute).sun_direction` (upstream's circle: up 05:30 for 810 minutes, 0.78 rad high). Energy (4.2 − 0.7)·d·(1 − 0.48·dusk) / 4.2, faded as the sun nears the horizon: 0.83 at noon, the town's own sun being 0.8. Colour #ffe4c4 → #ffb27a by max(dusk, golden hour). The TownWorld's sun is set dark while Thousand Town is shown; leaving puts it back (`_apply_white_world(false)`).
- **Moon:** a second DirectionalLight3D down `moon_direction`, #8fa7cc, 0.20·(1 − d)·moon visibility × 1.25.
- **Ambient:** sky #5f739a → #c4dbf5 and ground #1b2431 → #b6a38a by d, mixed 70 / 30 as the ambient colour; energy 0.42 → 0.62.
- **Background and fog:** #131c2b → #e9f0f5 by d, toward #c98a5e by the twilight. Fog (the town's density) only while d < 0.25, coloured as the background.
- **Sky dome:** horizon the background colour, zenith #0a1222 → #8fbbe6, the twilight glow round the low sun, the sun disc (upstream's radius × 1.6), the moon disc, stars by night turning with `space_angle`.
- **Lamps** (`tt_lamp`): emission = vertex colour × lamps × 1.6. **Signs** (`tt_sign`): × 0.56. **Market lanterns:** × 1.95 while the night market has people and is open, else × 0.12. **Shop light panels** of the frontage glow as lamps.
- **Windows** (`tt_window`): a pane is drawn when its rank (UV.x) is below its building's level, the sample's `light` (upstream's lightLevel, 0..0.82, already faded by the window factor); one pane when the building is shut with somebody on duty. Lit panes glow × 1.25. **Towers:** the glass of a whole floor glows #ffd69a × window factor × 0.9 when the floor's stable rank is below the tower's level.
- **Real lights:** 4 OmniLight3Ds on the `omni_candidate` lamps nearest the camera, re-chosen every 0.25 s, energy 1.4 × lamps, range and colour from `lights.json`. **Light pools:** 440 additive ground quads, strength 0.55 × lamps, hidden by day.
- **Water:** the canal and the plaza ring, a small ripple shader with a Fresnel mix toward the sky colour, darkened by night.
- **Not fitted yet:** the parity table against upstream's frames (Mac GPU), exposure on the devices.

### Events: the fireworks and the plaza fountain (`world/thousand_events.gd`)

**Built 2026-11-18, not integrated yet.** A Node3D for the Thousand world: `setup(world)`, `update(day, minute, dt, eye)` every frame (or `drive = true`), `status()`, `watch_point("fireworks" | "fountain")` and the static `watch_camera()`. Tests: `tests/thousand_events_tests.gd`; frames: `tests/thousand_events_capture.gd`.

**Schedules** are `thousand_clock.gd`'s: the show 19:00-22:00 on a 96 s loop (`fireworks_schedule()`, 128 lifts), the pump `fountain_level_smooth()` and `fountain_program()`.

**Show time.** In Auto at 1x the show second is exactly `fireworks_state(day, minute)`. While the clock holds (Day, Dusk, Night) or runs at 2x or 4x, the show and the fountain keep their real pace: an offset collects the difference between real time and the clock. A preset jump clears it, and so does the night once the show and the pump are both off. Two devices that see the same clock therefore play the same second.

**Launch sites.** Upstream's `SITE_LAYOUT`: a host centre from `town.json` plus upstream's offset × 0.5.
- The hosts: buildings b-0-0, b-2-0, b-20-0 and b-22-0; `places.parks` 0 and 1; `places.sports`; `places.amusement`.
- The test matches all eight against upstream's own sites in `tests/thousand/fixtures/events.json`. None is missing.

**Sparks.** Upstream's closed-form flight (drag, gravity 9.81 units/s², wind) in upstream units, then × 0.5.
- **Shapes:** all 12 game shapes have their own bloom: peony, chrysanthemum, willow, palm, salute, ring, crown, and upstream's contour heart, star, saturn, spiral and fan.
- **Facing:** contours and rings face the watcher, as upstream's `glyphBasis` does. Nothing else depends on the eye.
- **Size:** fewer, bolder sparks. Each is 2.2 m × its shape's size, with a floor of 0.63° so a far bloom reads. Colours are upstream's `TOWN_COLORS` core and outer layers.
- **Flash:** a 12 m additive flash quad for 0.45 s at each burst replaces real lights. In Compatibility, an omni light adds passes to every mesh it touches.
- **Determinism:** the look is a pure function of (day, minute, show second, eye), from seeded tables.

**Cap.** 600 sparks (`spark_cap`; 400 on the TV), counting the comets, embers and flashes. Over a show sampled every 0.1 s, about a quarter of the frames reach the cap. The sparks are then thinned evenly across the shells, and the trails are dropped first.

**Fountain.** The 28 jets of `landmarks.fountain` (16 main and 12 low) with upstream's `buildRings` draws, `wave()` and droplets. The jet height is base × level × wave.
- **Show (19:00-21:10):** three 24 s figures, cross-faded: a chase round the ring, the whole ring pulsing, and the two rings answering. At night, five colours chase round the ring.
- **Other night programmes:** lamp-white light.
- **Day:** plain water.
- **Off:** 22:00-05:30.

**Draws.** Three CPU-filled MultiMeshes with `use_colors`: the sparks, the jets' columns, and their spray and foam. Measured on EC2, the events added 3-4 draw calls to the frame. Nothing of the fireworks is visible, or computed, outside 19:00-22:00. At 03:00 nothing at all is visible.

**Watching.** The follow camera of section 6 looks down, so bursts 50-61 m up fall above its frame. `watch_point("fireworks")` therefore searches the canal promenades and the bridges for the spot and heading that see the most sites, 75-170 m away and 12-22° up, past the occluder boxes. `watch_camera()` then tilts the view so the child stays low in the frame and the bursts high. The fountain's spot is 11.5 m west of its centre.

**Evidence** (`build/dual-host/thousand-town/shots/events/`) is EC2 llvmpipe. The counts and the look are real; the frame times and the GDScript cost (about 2 ms a frame for the fireworks, about 1 ms for the fountain, headless) are not device numbers.

## 10. Locales

All new UI strings are in the six catalogs:
- the time buttons and the panel;
- building names: the 18 buildings and the places;
- the 20 roles and 8 states;
- the destination name and the credit;
- the signs.

`scripts/check.py` keeps them complete.
- The interactions' strings (section 13): 63 in all six catalogs. "Waste Station" (the waste station annex) and "Plaza" (shown in the place line and the panel) are translated; "Plaza" is no longer an identifier word in `scripts/extract_strings.py`.

## 11. Verification

**Parity (EC2, Node against GDScript):**
- the roster and plans for days 1, 6, 7 and 42;
- occupancy at 03:00, 07:30, 12:00 and 17:00;
- the lighting factors, the sun and moon, the event schedules;
- transit motion;
- the data pack's byte identity.

**Unit tests:**
- the scale (section 1);
- navigation: walkable, blocked, routes exist from every door;
- the authority's time modes and protocol 20.

**Tours, on the iPad, iPhone and TV layouts:**
- arrival;
- the walk to a building and the inspect panel;
- Day, Dusk and Night at player height, as paired screenshots;
- boarding a bus, riding, getting off;
- the return home;
- time-to-move.

**Network:** `net_test.py --thousand`: two clients agree on the clock mode, and boarding works.

**Evidence labels:** EC2's frames are software-rendered and logic only. The paired screenshots on the Mac GPU and the devices are the Mac's.

**The battery:** the city-web r3 battery plus the Thousand Town steps.

## 12. Differences from upstream (the CC BY change list)

- **Engine:** Godot instead of Three.js.
- **Units:** metres (×0.5).
- **Characters:** Lantern Lane's own characters, with adults at 1.70 m, instead of the 20 upstream character models.
- **Movement:**
  - residents walk real door-to-door routes, and buses stop and carry riders, where upstream has proxy loops and buses without passengers;
  - the player's own child walks the town and can ride the bus.
- **Clock:**
  - it starts at 08:00, not the real time;
  - Auto runs at 1 minute per second, with Day, Dusk and Night presets that hold;
  - upstream's 1×, 2× and 4× at 0.625 s per minute become 1×, 2× and 4× at 1 s per minute.
- **Text:** six locales and locale names; Chinese-only signs are replaced by translated signs.
- **Removed:**
  - the guestbook bottles;
  - the branding and call-to-action screens;
  - the airship advert;
  - the National Day dressing;
  - the Milky Way photo;
  - the drone show, which upstream offers only through its URL;
  - the layout editor and the random town.
- **Cheaper look-alikes:**
  - water with ripples and Fresnel instead of the Reflector;
  - lamps as emissive heads and light pools;
  - beams as cones;
  - fireworks capped at 600 sparks.
- **Doors** are 2.1 m.

## 13. Interactions

**Code:** `scripts/world/thousand_play.gd` (a child of the play controller, `controller.thousand_play`), with hooks in `play_controller.gd` (`_thousand_tap`, `_thousand_context`, `do_context`, `_physics_process`, `ride`, `_arrive`), `hud.gd` (the chip and the resident card at the top right, the two show buttons at the bottom right, Follow in "Who's here?"), `pad_input.gd` (B), `camera_rig.gd` (`t_watch`, a held view the camera glides to) and `town_world.gd` (`prepare_thousand`, `_thousand_frame`).

**Integration (town_world.gd):**
- `prepare_thousand()` builds the world, the events node (fireworks and fountain, `drive = true`, 600 sparks; 400 on the TV), the transit and the residents once, under the world, on the world's `sim` and today's plans, and warms the residents (every route searched) for the current time. The tram to Thousand Town calls it behind the journey card once the card is fully shown (0.35 s after it starts); the way home never waits for it.
- `_thousand_frame()`, once a frame while the town is shown: the transit and the residents at the same `view_time()` the light uses; the residents get the world's plans when they change (`set_plans`) and hold their last frame while a new day's plans are still being built; `focus()` on the child; `budget_profile("tv")` while `TvMode` is active, else `"ipad"` (re-applied when it changes).
- The world's bus and taxi templates stay hidden: the transit draws them.

**Everything is local to the device:** boarding, the wheel, a snack and following change nothing on the network (no protocol change). Friends see the child where it is (its state: on the bus, its position moves with the bus).

| Interaction | What the player does | What changes | Grounding in the source | Touch | TV controller | Test | Status |
|---|---|---|---|---|---|---|---|
| I1 Meet a resident | Taps a drawn figure, or "Say hello" within 3 m | The child turns and waves; the resident card (name in the reader's language, role, age, what they do now and where, where they head and when they arrive); a marker floats over them | `ThousandPeople.pick_screen`, `nearest`, `info` (the sim's plan segment: state, place, ETA), `sim.name_of(i, locale)` | Tap the figure, or the action button | Action button (Y, or A on it with the D-pad); B closes the card; Close and Follow are D-pad stops | `test_meet` | Implemented |
| I2 Follow a commute | Follow on the card, or on a resident picked in "Who's here?" who is out on the street | The child walks after them along the pavements (re-routed every second, 2.6 m behind); the rest of their trip is drawn on the ground (yellow dashes); the chip "Following NAME · to PLACE · about N min" with Stop; into a building: "NAME went into PLACE." with that building's "Who's here?"; aboard a bus or out of sight for 4 s: a toast, and it ends | `route_of`, `info` (to, eta, mode inside / aboard), `position_of`; the child's route is `ThousandPeople.ground().route` | Follow, Stop, Who's here? buttons | The same buttons are D-pad stops; B stops following | `test_follow` | Implemented |
| I3 Visit a building | "Who's here?" at any door (or a tap on the building) | The panel: open or closed and the counts from the last sample; picking a resident inside says where they are and puts the marker over the building's door | `thousand_inspect.gd` from `town_sample()` (open, count, present) and the plans | Action button, list | Action button; B closes | `test_inspect` (every door walkable and offering its own building; four buildings at four times against the sample) | Implemented |
| I4 Board a scheduled bus | At bus-stop-1, 3 or 4, or the station's bays: "Wait for the bus", then "Get on the bus" | Waiting: the child stands at the stop, the chip counts down (`next_departures`); the bus stands there with a free seat: "The bus is here!"; riding: seated in the bus (`seat_transform`), the camera stands back to 11 m behind it, the chip names the next stop; "Get off" at a stop (at `door_point`); at the end of the lap everybody gets off at the bays; after 22:30 the chip says when the first bus comes; with the clock held it says to press Auto | `ThousandTransit` timetable, `can_board`, `board`, `alight`, `next_stop`, `bay_point` (the bus runs on the town clock: upstream's loop with Lantern Lane's stops) | Action button and chip buttons | The same; B stops waiting (not riding: Get off is at a stop) | `test_bus` | Implemented |
| I5 Ferris wheel | At the wheel (amusement park), "Ride the wheel" | Open: the child waits for the next cabin at the bottom, rides one whole turn (180 s) standing in it, the camera at the cabin's open front looking out over the town along the wheel's axle (the child is in the cabin behind the camera; the chip says so); "Get off" only near the bottom; after a whole turn it gets off by itself. Closed: "It opens at HH:MM" | `town_sample()` row `c-amusement` (open while somebody there is awake or on the way, `_public_open`); the opening time is the first plan segment there after now; `cabin_position(k)` | Action button | Action button | `test_wheel` | Implemented |
| I6 Night market | At a stall's counter on the promenade, "Buy a snack" | Open: a snack (by the stall's type: skewer, cup or bun) in the child's right hand for 45 s, a cheer, and a toast naming a shopkeeper who is at the market now. Closed: "The night market opens at 18:00." | The sample's `c-night-market` row (open from 18:00, `_public_open`) and its present list filtered by role `shopkeeper`; the stalls of `town.json` | Action button | Action button | `test_market` | Implemented |
| I7 Shows | The bottom-right buttons "Watch the fireworks" / "Watch the fountain show" | On: the child walks (along the pavements) to the events node's watch point, faces the show, and the camera glides to that point's watch camera and holds; the chip says so, with Stop; the show's end ends it. Off: the button says when it is next on ("Fireworks at 19:00"), pressing it says how to get there (the moon jumps to 21:30) | `thousand_events.gd` `status()` and `watch_point()` (`fireworks_schedule`, `fountain_program`) | The two buttons | Both are D-pad stops; B stops watching | `test_shows` | Implemented |
| Time-dependent town | Day, Dusk, Night or Auto | The night market's lanterns brighten while it is open and busy (from 18:00); the buses stop after 22:30 and stand closed at the bays; the amusement park opens in the afternoon (weekdays) | The sample (`open`, `count`), `Clock.dispatch` | Time buttons | Time buttons | `test_market`, `test_bus`, `test_wheel` | Implemented |

**Return home from any state:** the tram home (Ride home, or the station's back) and leaving the town end every interaction (`thousand_end_all`): off the bus (the seat is freed), off the wheel, the snack gone, the camera behind the child, no card, no marker, no chip, no show buttons. `test_return_home` rides home from following, waiting, riding the bus, riding the wheel with a snack, and watching, and compares the town HUD's visible buttons with the ones before the first journey.

**TV:** `test_tv` (TvMode forced, the real PadInput): the residents' budget switches to 96 and the fireworks' to 400; the action button says hello; the card's buttons, the chip's Stop and the show buttons are D-pad targets; A on Follow follows; B ends following, closes the card and stops waiting; the controller hint names B.

**Decisions:**
- **unified r6:** the HUD in Thousand Town offers only what works here (`Places.offers`): Pets, Story, Hello and the
  lantern scrapbook (the main world's own records) are hidden, as Decorate already was, and come back on the return
  (`design/unified-station.md`, r6). A tap on a building asks the one whose volume the finger's ray meets first
  (`ThousandWorld.building_on_ray`, `PlayController.thousand_tap_target`).
- The card and the chip sit at the top right under the top bar, clear of the toasts (top centre), the menus (left), the time buttons (right middle) and the action button (bottom centre); the show buttons take the bottom-right corner, where Decorate is elsewhere (Thousand Town has no toy box).
- Following re-routes along the residents' own pavement graph; the child keeps 2.6 m behind. A resident on a bus is not followed onto it ("Ride" commuters are hidden while aboard; the follow ends with a toast).
- The bus ride keeps the seat local (`board(id, "peer:<id>")`); the authority's own bus seats (`Thousand.srv_board_bus`, protocol 20) are not used by this interaction.
- One turn of the wheel takes upstream's 180 s, on real time (the wheel turns whatever the town clock does). Get off is allowed within 0.22 rad of the bottom.
- The wheel's view looks along the axle, not toward the middle of the town: the town's middle lies in the wheel's own plane, where the rim, the spokes and the next cabins filled the picture (an EC2 frame showed only the next cabin's red wall).
- The fountain's watch point (events node) now keeps its camera off the market promenade (`_camera_room`): from the first west spot the camera stood 1.9 m from a promenade lamp head (a blue `tt_lamp` cube, which filled the right of the frame as a flat blue box) and a market lantern (the red blob at the left edge). Both are real parts of the town, not placeholders; the camera was simply too close to them.
- The shows use only the events node's watch points: its fireworks camera looks up at the bursts (50-61 m up, about 150 m away), which the follow camera does not show.

**Tests and evidence (EC2, 2026-11-18):** `tests/thousand_play_tests.gd` (headless) 242 checks, 0 failures; `thousand_tests` 203/0, `thousand_world_tests` 190/0, `thousand_people_tests` 1230/0, `thousand_transit_tests` 9905/0, `thousand_map_tests` 335/0, `thousand_events_tests` 159/0, `thousand_sim_tests` 8192/0, `run_tests` 29058/0, `parse_all` 191/0, `tv_tour` 215/0, `tv_route_audit` 18 steps, 9 findings (as before), 0 errors, `check.py` PASS. Player-camera frames of each interaction: `tests/thousand_play_capture.gd`, saved to `build/dual-host/thousand-town/shots/play/` with a README (Mesa llvmpipe software GL; frame times are not device numbers). Nothing here was tested on an iPad, iPhone or Apple TV.

**The whole loop by player input (`tests/thousand_loop_tour.gd`, EC2, 2026-11-18).** One session in the real Main scene (world, controller, camera rig, HUD, menus, PadInput): the town and its HUD; the walk to the tram stop; "Ride to Thousand Town" and its journey card; the arrival (the follow camera behind the child, the Thousand Town HUD, Decorate hidden); exploring (the pedestrian street, the canal bank stops the child on both sides, orbit, zoom, the camera pulled in at Courtyard Housing, the streets south to bus stop 3); I1 and I2 with a resident met where one happens to walk by; I3 at Courtyard Housing; I4 from bus stop 3 to bus stop 4 with Auto at 4x; Day, Dusk and Night by the time buttons (daylight, the sun, the lamps and the lit windows checked); I6 at a juice stall; I7 the fireworks; and Ride home while watching, the town HUD exactly as at the stop before the journey. Touch: taps and drags as the mouse events the game takes from a finger, a pinch as a magnify gesture. TV (`--tv --pad`): only joypad events through PadInput (the left stick, the D-pad and A, X and Y, B, the right stick, ZL / ZR). Watchers over the whole stay: the child never inside a solid, the camera never inside an occluder box that is not dithered, every occluder between the camera and the child dithered, the child visible. The town's time is changed only with the time buttons; the only call that is not input is `Session.start_solo` for the tour's own save. Headless (`scripts/test_all.sh`) and rendered frames with READMEs in `build/dual-host/thousand-town/shots/loop-touch/` and `loop-tv/` (EC2 Mesa llvmpipe at 0.4-2.5 s a frame; the rendered runs allow 24 physics steps a frame instead of Godot's 8, and 150 while the child follows a resident (`--physics-steps=150`), because the town's shown clock, its residents and its buses follow wall time through `Thousand.est_clock` while the child walks on game time).

Results (EC2, 2026-11-18, the final revision, headless): `THOUSAND LOOP TOUR touch: 124 checks, 0 failures`, `THOUSAND LOOP TOUR tv: 133 checks, 0 failures`. Rendered: a touch run of an earlier revision (20 frames, 136 checks, 1 failure: the tap on a walking resident missed at 2 s a frame) is in `shots/loop-touch/`; the TV run of a near-final revision reached the canal bank (9 frames, 63 checks, 3 failures, two of them tour checks corrected afterwards) before the host's CPU throttling (about 80 % steal, 8-25 s a frame) ran out its wall-clock limit; see the READMEs. The loop depends on who happens to walk by, so a run meets a walker or, failing that, a resident standing still.

**Fixed by the loop tour:**
- The residents' venue spots keep 1.6 m off the four arrival slots (`thousand_people.gd` `ARRIVAL_CLEAR`): a resident standing on the forecourt corner overlapped the arriving child and took every tap on the street ahead.
- A walk in Thousand Town ends only after 0.5 s without progress (`play_controller.gd` `THOUSAND_STALL`): grazing an edge stalled single steps, and a tap on Courtyard Housing or a walk to a market counter stopped dead.
- Following: a follow that makes no headway toward the resident for 4 s ends with "You lost sight of NAME." (`thousand_play.gd` `STUCK_AFTER`): the child had stayed pressed against the market's stall row for good (the residents' pavements pass where the child's own walking does not; not solved, now ended).
- The tram stop's journeys wrap onto a second row when one row would run under the corner columns (`hud.gd` `_fit_context_row`): on the iPad "Ride to Thousand Town" ran under Decorate.
- The controller's D-pad repeat counts at most 0.1 s a frame (`pad_input.gd`): one long frame turned a single press into two jumps.
- A tap in Thousand Town meets the finger's ray at the ground's own height (`play_controller.gd` `_thousand_tap`), not at y = 0: on a footbridge deck (up to about 1 m) the child walked to a point well beyond the one tapped.

**Seen in the loop's frames:** the child is about 236 px tall at the iPad arrival (about a quarter of the picture's height at the 7 m follow distance; kept as the framing, the lead's guide of 80-200 px was a guess). At bus stop 3 the follow camera stood just behind the Tower Two forecourt's 3 m frontage walls (not occluder boxes) and the one-in-four ghost of the near-eye x-ray greyed the whole frame: fixed by the lead (section 6: nothing within 1.5 m of the eye is drawn). At 2 s a frame a walking resident moves 2-3 m between a finger's press and release (and a controller press reaches the game frames later), so the rendered tours meet a resident standing still when a walker cannot be met.

**Pending:**
- Device feel (frame times on the iPad and the Apple TV), and the readability of the card and chip at TV distance: EC2 frames are software-rendered.
- Following a resident onto a bus (riding with them) is not offered.
- Friends do not see each other's snack or card; nothing of these interactions is shared.
