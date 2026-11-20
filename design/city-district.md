# The miniature city district (candidate `city` r1)

**Status:** authorized by the user, 2026-11-16. It is built on zoo r2, which continues alongside it. The source of every layout number is `game/scripts/core/city_map.gd`.

## What it is

A third map, `city`, which a child reaches by tram from town, like the zoo. It is a complete miniature city block in a refined voxel look on a white world:
- **Centre:**
  - a blue three-storey office: open front, desks on two floors, a balcony;
  - a yellow cafe with a roof terrace;
  - a coral two-storey gym with a **rooftop restaurant**.
- **Front:** a row of five small shops: a bakery, a little cafe, a bookstore, a flower shop and an ice cream shop.
- **Circulation:**
  - two exterior staircases from the street;
  - two interior staircases;
  - two **skywalks**: office to cafe terrace, and cafe terrace to gym.
- **East side:** a retro **Ferris wheel** in berry-red and cream.
- **Around:** perimeter roads with a slow bus and two cars, pavements, crossings and a **bus stop**.

The scale is real (1 unit = 1 m, child H = 1.30). "Miniature" is the composition, the white world and the overview camera, not smaller navigation.

## Playable rules

- **Getting there and back:**
  - the town's tram stop offers **Ride to the city** next to Ride to the zoo;
  - the city's bus stop and the **Ride home** button go back to town;
  - the journey is the zoo's (`Session.travel`, the journey card, refusals, timeouts);
  - the city keeps no saved state of its own, so the save schema is unchanged.
- **Levels:**
  - the ground (y = 0) is one plane with walls and solids;
  - upper floors, terraces, the balcony and the skywalks are rectangles at a height;
  - stairs are straight ramps of 16 steps.
  
  A child walks off an upper surface only where it meets another surface or a stair's end; everywhere else is a railing or a wall. A tap picks the nearest walkable surface along the ray, and a floor or roof above stops it. So nothing is clicked through a floor, nobody walks through a wall or falls off a balcony, and every stair arrives somewhere.
- **The player's height** is part of the shared state (`level`: the region id, or "" for the ground). This changes the protocol (16).
- **Interactions** (`CityMap.INTERACTIONS`; the action button within 1.4 m on the same level):
  - **seats:** the cafe, the terrace and the rooftop restaurant, one child each, shared like benches;
  - **ordering:** a hot chocolate at the cafe counter, dinner at the rooftop;
  - **exercise:** treadmills and weights in the gym, bikes in the studio upstairs, one child per machine;
  - **office desks:** two;
  - **the five shops:** a line and a small thing;
  - **the Ferris wheel:** a real ride. Board from the platform only when a gondola is at the bottom; two children per gondola. Riding takes no other input. The child gets off at the bottom after one turn, or at the bottom on request.
  - **the bus stop:** the way home.
- **Ambient life (bounded):**
  - one bus and two cars on the ring road, stopping while a child is in front of them;
  - four walkers on the block pavement;
  - three seated townsfolk;
  - the wheel turning (80 s per turn).
  
  Everything is a function of the authority's clock and the shared states, so late joiners see the same thing.
- **Camera:**
  - **Arrival:** the city opens on the **strolling view**: the camera follows the player's own child at the second-closest zoom level, about 15 m on an iPad, where the child stands about 80 px tall and centred.
    - **Changed in dest-fix r1** (2026-11-18), from the user's feedback on the installed r3: "Ride to the city is for strolling with my own character".
    - **Before,** the city opened on the overview of the whole block. There the child was a 13 px figure among fifty townsfolk, with an unreadable name tag.
    - **Now,** the overview is one zoom-out away, and the player's own name grows there so it stays readable.
  - **Orbit and zoom:** a one-finger drag on empty ground orbits; pinch or the mouse wheel zooms, from 8 m (beside the child) to the overview.
    - **Reset view** returns to the strolling view (dest-fix r1; before, the overview).
  - **Decorating:** the city is visited, not decorated (`Places.decoratable`, dest-fix r1).
    - There is no Decorate button; no path enters decorate mode; the toy box offers nothing.
    - Before, Decorate showed in the city and offered indoor furniture, which the authority then refused.
  - **Controller (Apple TV):** L/R turn, ZL/ZR zoom, and the pointer taps as everywhere else.
  - **Avoiding conflicts:** a tap still walks or uses a thing; a drag never moves the child; the pointer never orbits.
  - **Inside a building**, the storeys above the child's level are hidden, so the child stays readable.

## Budgets (mobile and Apple TV)

| What | Budget |
|---|---|
| Static scene | at most 160 draw calls after merging, at most 160 000 triangles |
| A vehicle | at most 3 draw calls |
| A walker | at most 3 draw calls |
| The wheel | 1 + 8 draw calls |
| Moving agents | at most 7 |
| Textures | none: code-built voxel geometry with matte vertex colours, like the zoo's props |

## Ownership (city r1)

| Owner | Files |
|---|---|
| The production owner (Opus 5.5, high) | `city_map.gd`, this design, `places.gd`, `session.gd` (travel, protocol, shared interactions), `play_controller.gd`, `town_world.gd`, `camera_rig.gd`, the HUD and `pad_input.gd` wiring, the docs, the seal |
| Art (Opus worker) | `art/props_city.gd`, `world/city_world.gd`, `tests/city_art_tests.gd` |
| Navigation, rules and camera (Sonnet worker) | `core/city_nav.gd`, `core/city_rules.gd`, `world/city_orbit.gd`, `tests/city_nav_tests.gd`, `tests/city_rules_tests.gd` |
| Inventory, then strings and checks (Haiku workers) | reports under `build/dual-host/city/`, later `game/locale/*.json` and a focused regression run |

**Order of work:**
1. The art and navigation workers build their own new files in parallel with zoo r2.
2. The owner integrates the shared files only after zoo r2 is sealed.

## Acceptance path (headless on EC2, then images and devices on the Mac)

1. **Navigation tests:** every region and stair is reachable from the bus stop; every railing edge and wall blocks; floor-aware picks, including through the cutaways; no stair dead-ends.
2. **Rules tests:** seats, machines and the wheel shared between two children; the wheel's boarding window and safe exit; vehicles yield.
3. **Art tests:** budgets; every walkable region has a visible floor and every railing edge a railing; stairs drawn where the navigation has them.
4. **Real clients:** two children in the city on different levels; a late joiner sees the same wheel, seats and riders.
5. **The city tour** (touch and controller): ride from town, walk to every named place and use it, climb, cross both skywalks, ride the wheel, orbit, zoom and reset, ride home.
6. **Mac GPU capture:** the full scene, cutaways, stairs and skywalks, the wheel, avatar-level views, interactions. Art and device acceptance stay the user's.

## Refinement pass (user feedback, 2026-11-16)

The user saw the basic layout and asked for more refinement and detail, keeping every building's position and height, the Ferris wheel and the roads. Character activities and weather were deferred to a later pass. What changed:
- **Coral tower (the central main building):**
  - a furnished first-floor terrace, `gym_terrace`, along its open front: bistro tables and chairs, planters, a striped canopy;
  - a rooftop restaurant pavilion on four posts with a slatted roof, so its interior shows from above: the kitchen bar with stools, dining tables, pendant lamps, string lights and planters.
- **Yellow cafe:** parasols over the terrace tables; a coffee bar inside (espresso machine, grinder, cups, a pastry case, stools, a menu board) and a dining table with four chairs.
- **Blue office:** desks with computers, keyboards and office chairs on both upper floors; bookshelves on each floor and in the lobby.
- **Shops:**
  - a bakery, a little cafe, a bookstore, a flower shop and an ice cream shop, each with an English sign (BAKERY, CAFE, BOOKS, FLOWERS, ICE CREAM) in voxel letters;
  - each front has two display windows with goods behind the glass, either side of a framed door; inside, the counter;
  - outdoor bistro seating in front of the bakery, the cafe and the bookstore.
- **Ground:** paved paths and raised flower beds.
- **Stairs and skywalks, made physically sensible:**
  - a landing at each stair's foot and top;
  - stringers that meet the ground and a header beam under the top landing;
  - columns under the landings and the outdoor flights;
  - handrails that meet the skywalk railings;
  - skywalk decks with visible thickness, resting on corbels at the walls.
- **Colour and light:** a fresher blue (`#5aaef5`), yellow (`#ffd75e`) and coral (`#ff8f7a`); in the city, a brighter fill light. *(Correction, 2026-11-17: this line first said the shadows were made softer with opacity 0.45 and blur 2. Real-time shadows are off in the whole game, so those settings had no effect; the soft look comes from the blob shadows, the materials and the fill light.)*

The Mac capture's showcase frames show each of these areas (`city_tour.gd`, `SHOWCASE`).


## City r2: colour, everyday life and Look (user request, 2026-11-17)

Building positions, floor heights, the roads and the wheel stay where r1 put them. The playable child stays in the city with everything it can do; Look is added beside play, never instead of it.

- **Colour:** brighter and cleaner, never grey (`CityMap.COLORS`).
  - the office: a fresh blue;
  - roofs: coral orange;
  - the central tower: warm white with light peach accents;
  - the cafe: soft cream yellow;
  - the shop row: mint, with an accent per shop;
  - the wheel: berry red, with pastel cabins;
  - the ground: light cool grey;
  - plants: natural greens.

  Shadows are softer. Buildings stand apart by trim, base bands and light, and interiors stay easy to see.
- **About 50 people** (`CityMap.PEOPLE_BUDGET`; places, looks and actions in `core/city_people_data.gd`):
  - **Where:** office workers at computers; diners and talkers in the rooftop restaurant and on the terraces; staff and customers in the shops; people exercising; walkers; passengers in the wheel's cabins; riders on the carousel.
  - **Looks:** men and women with varied hair, skin, clothes and poses.
  - **Motion:** walkers swing their arms; seated people now and then turn their heads or lift a cup; staff and athletes have their own actions; every person's timing is staggered.
  - **Shared and fair:** they are a pure function of the city's shared clock, so every player sees the same city. None of them ever takes a child's place. Standing people are solid to children. Cabin passengers ride only in cabins with no child aboard, getting on and off at the bottom.
- **Furnishing:** more tables, chairs, computers, tableware, shelves, flowerpots and canopies inside the buildings and on the block. The outer areas stay simple, nothing hides the roads or the people inside, and signs use simple English words.
- **Rides:**
  - the wheel turns slowly with its cabins always upright;
  - a new **carousel** (`CityMap.CAROUSEL`) turns the way its horses face, while they bob.
- **Traffic:** three buses in different colours and the two cars (`CityMap.VEHICLES`).
  - Buses pause at four stops (`BUS_STOPS`) and keep their spacing.
  - Nobody passes or bunches up, and everything still stops for a child.
- **Camera and Look:**
  - **Kept from r1:** drag to orbit, the wheel or a pinch to zoom, and Reset view, which now glides.
  - **Look,** a HUD button beside Reset view, switches to inspecting.
    - **Touch and mouse:** a tap on a building, a shop, the rooftop restaurant, the wheel or the carousel glides the camera in to that place (`LOOK_PLACES`). A tap on empty space glides back to the overview.
    - **Leaving:** Esc, the controller's B or the Look button again glides back to the strolling view, the child again (dest-fix r1; before, the overview), and gives taps back to walking.
    - **Controller:** D-pad left and right step through the places (`LOOK_ORDER`).
  - **Pause** shows only while looking. It freezes the people, rides and traffic on this screen only; the shared city keeps running for friends, and Resume catches up smoothly. The child stays where it is and stays visible.
  - **Every move is an eased glide** (`LOOK_GLIDE`); Reduce motion shortens it.
- **On arrival:** the city is already running, with nothing to start.
- **Versions:** the vehicles' new state (the bus dwell) changes the packed city state, so protocol 17.

## City r3: weather, palette, panning, stability (user request, 2026-11-17)

The layout, model count, camera framing, proportions and composition stay as in r2, and the child stays playable.

- **Palette** (`CityMap.COLORS`, superseding r2 where they differ):
  - a blue main building;
  - a coral-orange central tower (light peach accents);
  - a warm-yellow restaurant building (the cafe);
  - mint shops;
  - **dark-green roofs**;
  - a berry-red wheel.

  Bright, clean and differentiated, never grey. The background stays pure white except at night. No title or explanatory text is added over the scene; the HUD's place label beside Ride home is the game's own and stays.
- **Weather** (`WEATHERS`, `WEATHER_LOOK`): sunny (the default), rain and night.
  - **Shared:** the weather is shared by everyone in the city, like the town's weather. The authority keeps the weather, the one before it and when it changed (protocol 18). Every client blends over `WEATHER_BLEND` seconds from the shared clock.
  - **Smooth:** a change never cuts and never reloads; nothing is destroyed or recreated.
  - **Buttons:** three small, semi-transparent glass buttons on the right of the screen (sun, rain, moon), reachable with the D-pad on TV. There is no refresh control.
- **Rain:**
  - **Look:** continuous rain particles (bounded, around the view), wet darker ground with subtle sheen and puddles.
  - **People outdoors without an umbrella** hurry, in staggered groups over `RAIN_COVER_SPREAD` seconds, along real routes to cover: awnings, the bus shelters, the carousel canopy, open ground floors and shops. Nobody vanishes.
  - **Umbrellas:** about a third (`UMBRELLA_SHARE`) open umbrellas and carry on.
  - **When it stops:** people drift back to their places and activities over `RAIN_RETURN_SPREAD` seconds.
- **Night:** a deep-blue sky with the building colours still clear.
  - **Steady warm lights:** office, restaurant, gym and shop windows; the rooftop and terraces; the signs; street lamps along every pavement with no large dark area; the wheel's rim and its cabins.
  - **Built for stability:** mostly glowing materials and soft light pools, at most a few real lights, none casting shadows, none fading with distance. So nothing flickers, pops on or dims while the view is dragged, zoomed or glides.
- **Controls:**
  - left drag orbits; **right drag pans** (new; bounded to the block; Reset view and Look clear it);
  - the wheel zooms;
  - a click on a place glides in while looking;
  - empty space or Esc glides back.

  Play and Look stay as in r2.
- **Stability:** no flicker of light, shadows, the wheel or building edges during glides, drags, zooms or weather changes.
  - **Shadows:** real-time shadows stay off in the whole game; blob shadows and the fill light give the soft look, so no shadow can flicker while the view moves. (r1's and r2's shadow-softening settings had no effect and were removed.)
  - **Detail:** distance-based detail never pops; it either stays or fades.
- **Seated people:** they now also adjust their posture now and then, besides turning their heads and lifting cups.
