# Design: the zoo and world journeys

Status: written 2026-11-15, before implementation, by the design planner for the production owner's review. Nothing here is implemented, rendered, tested or accepted. No Godot ran for this document. Every number marked "computed" was derived by re-implementing `CameraRig.pose_xform` and `CameraRig.project` from the constants in `game/scripts/world/camera_rig.gd`; the owner should pin them with a unit test before relying on them.

Scope authorized by the user: a separate zoo map reached from the town, with more and larger animals, plus the reusable map-connection and map-state capabilities that later destinations can use. The other eight destinations of the idea pool are not implemented by this work.

Engineering contract for the implementation: [zoo engineering standard](../docs/zoo-engineering-standard.md).

Related documents: [game design](../docs/game-design.md), [animals](../docs/animals.md), [multiplayer](../docs/multiplayer.md), [scale contract](object-scale-and-surfaces.md), [child rig](../docs/kid-rig.md), [controller](tv-controller.md), [dual-host workflow](../docs/dual-host-modeling.md), [experience plan](experience-plan.md).

## 1. Decisions in brief

| Topic | Decision |
|---|---|
| Art style and camera | Unchanged. Code-built rounded primitives, flat matte colors, no textures, the existing oblique camera (40° pitch, 42° field of view, 9.5 m and 15 m). Readability comes from scale, silhouette, proportion, color blocking and where things stand in the frame. |
| First milestone | A Lion Hill slice in the real game, at the real camera, before anything else. Its rendered evidence calibrates the sizes and the rig for every later habitat. It is a milestone, not an approval stop. |
| Roster | Phase 1: seven species, fourteen individuals (lion and lioness, tiger, five monkeys, giraffe, two zebras, hippo, two otters). Phase 2: four more species (giant panda, red panda, penguins, sea lion). |
| Scale | Zoo animals are 1.1 m to 2.8 m tall (today's town animals: 0.73 m to 0.86 m, the elephant 1.6 m). On screen at the default camera: 115 px to 300 px tall instead of 76 px to 91 px; eyes 16 px to 19 px wide instead of about 9 px. |
| Habitats | Lion Hill 24 × 18 m, Tiger Hill and Monkey Hill 22 × 18 m each: every one larger than one gameplay screen (15.8 m deep) on every device. Plus Savanna Meadow and Splash Bay. |
| Monkeys | A troop of five on climbable and swingable structures, with two-segment limbs, hands that really hold, pendulum swings and arc jumps. At least two are always in motion while a child is there. |
| Entrance | A "Zoo tram stop" in town, added to every town near the arrival point, movable like a cottage and never removable. A fixed Zoo Station in the zoo. A "Ride home" button as an always-available way back. |
| Travel | An authoritative `travel` request, a short journey card, the origin kept until the destination is ready, and a retry. Players travel alone; friends can be on different maps. |
| State | One town save holds every map. Zoo things are ordinary items with space `"zoo"`; a small optional `maps` key holds the discovery log. Save schema stays 2. Network protocol 13 → 14. |
| Main-world animals | Not resized in Phase 1. Assessed in section 4.3, with an explicit proposal and its consequences for a later decision. |

## 2. Goals and non-goals

### Goals

1. A zoo map that is a place to play, not a gallery: every species answers the child with something only it does.
2. More species than the reference's three, and larger ones whose shapes, faces and markings read at the normal gameplay view on an iPhone, an iPad and a TV.
3. Three landmark habitats (Lion Hill, Tiger Hill, Monkey Hill) that are substantial, walkable and built around spots the animals really use.
4. A journey between town and zoo that is easy to find, feels like going somewhere, cannot strand a child and always has a way back.
5. Reusable capabilities: a map registry, travel, per-map saved state, and player places across maps.
6. Solo play is complete. Friends add fun and are never required.
7. No hunger, no chores, no timers, no scores, no daily check-ins, nothing locked. The pillars of [game-design.md](../docs/game-design.md) hold.

### Non-goals

- A new rendering style, textures, fur, glossy materials, cinematic shots or another camera. The user rejected a glossy, richly textured lion concept; it is not a target.
- A seamless open world, streaming, terrain editing, an ecosystem simulation or continuous transport between maps.
- The other eight destinations. They get only an adopted or deferred decision here (section 17).
- Resizing the main-world animals in Phase 1.
- Any commit, push, release, install or server change. Those need the user's own authorization.

## 3. What exists today (read from the code)

### 3.1 Spaces are two kinds, not a map framework

- **Model.** `game/scripts/core/town_model.gd` keeps one flat `items` dictionary. Each item has a `space` string: `"town"` or a cottage room `"<cottage id>:<floor>:<room>"`. `is_space()` accepts only those two forms. `validate()` picks `TOWN_HALF` or `ROOM_HALF` by `space == "town"` and the caps `MAX_TOWN_ITEMS` (300) or `MAX_ROOM_ITEMS` (40) the same way. The Wishing Tree is a special case inside `validate()`.
- **Session.** `game/scripts/net/session.gd` has one model, one save file (`save_now`, `_load_town`) and one welcome message with the whole town (`_srv_join`, `ev_welcome`). Every device mirrors every item of every space. A player's place is `players[peer]["state"]["space"]`, sent by the client ten times a second in `rq_state`; `_srv_state` only checks `model.is_space(space)`. There is no request for changing space and no interest filtering: every state goes to every peer.
- **World.** `game/scripts/world/town_world.gd` is one node. It builds the town ground once in `_ready`. `set_view(space)` shows `_town` or `_room`, rebuilds the room procedurally (`_build_room`) and rebuilds the item nodes of that space, all in one frame. `resolve_walk()` clamps to `TOWN_HALF` or `ROOM_HALF`.
- **Player.** `game/scripts/world/play_controller.gd` switches space instantly in `go_to_room`, `exit_house` and `travel_to`. `_on_joined` always starts in `"town"`. There is no loading step and no transition picture.
- **Camera.** `game/scripts/world/camera_rig.gd` has two modes by the boolean `in_room`.
- **Everything else.** The literal `"town"` appears 214 times in 28 script files. Many uses of `space != "town"` mean "indoors": `Catalog.allowed_in`, `Hud.catalog_tabs`, `Hud._refresh_heart`, `PlayController._on_view_changed` (`rig.set_room(view != "town")`), and the music context in `main.gd`. A third kind of space would be taken for a room in all of those.

**Conclusion.** The space handling is a town-plus-rooms switch. It is not a multi-map or streaming framework. This design adds a small registry on top of it and keeps the single model and single save.

### 3.2 Animals: two pipelines

- **Town animals** (`game/scripts/art/animal.gd`): five species built from primitives. A `_body` node carries pivots: `_head`, four `_legs` (one capsule each, turning at the hip), `_ears`, `_tail`, and for the elephant a `_trunk` chain of four nested pivots. `_pose()` sets angles from sine curves per `action`. The brain (`game/scripts/core/animal_brain.gd`) is a pure, seeded simulation bound to `"town"`, `TownModel.TOWN_HALF` and five fixed species. `game/scripts/net/animals.gd` runs it on the authority and broadcasts six floats per animal four times a second. `game/scripts/core/town_life.gd` is a data table of what the animals do with placed things.
- **Pets** (`game/scripts/art/pet.gd`): ten modeled GLB actors with named joints (`Head`, `Tail`, `LegFL`…, `WingL/WingR`) turned in code. They follow their owner by the owner's `space` (`game/scripts/world/pet_world.gd` `wanted()`), so they already follow into any space.
- **The child** (`game/scripts/art/kid.gd`, [kid-rig.md](../docs/kid-rig.md)): `Body` with `LegL/LegR`, `ArmL/ArmR`, `Head`, `Hand`; one capsule per limb; angles written every frame; a blink by scaling the eyes. A seated child follows a seat marker on a swinging `Pivot` (`TownWorld.seat_transform`, `_animate_play_items`).
- No skeleton, skinning or `AnimationPlayer` is used by any of the three in the code read.

### 3.3 The rules the HUD already keeps

From [HANDOFF.md](../HANDOFF.md) (`first-steps` r8 to r11): while a thing is held, the tools have two places (`Hud.zones`, `PlacementDock.choose_place`), the camera rests the thing between them (`CameraRig.frame_fit`, `room_fit`), and a side menu or the top bar's right part that would stand on the held thing or on the player's own child steps aside (`Hud._keep_menus_clear`, `side_menus`). The controller's hints keep off the same boxes (`game/scripts/ui/pad_input.gd`). This design reuses those mechanisms and does not change them.

## 4. Art style, camera and readability

### 4.1 Binding constraints

1. **Same builders and materials.** Zoo animals, props and scenery are built from `game/scripts/art/mesh_kit.gd` primitives (`rounded_box`, `sphere`, `capsule`, `cylinder`, `torus`) with `Kit.mat` matte colors, merged by `Kit.merge_parts`, grounded by `Kit.blob_shadow`.
2. **No new look.** No albedo, normal or roughness textures, no fur, no gloss, no rim light, no post effects, no new lights. The zoo uses the same `WorldEnvironment` and sun as the town (`TownWorld._build_environment`).
3. **Same camera.** `PITCH` 40°, `FOV` 42°, `ZOOMS` 9.5 m and 15 m, the eight 45° turns. No closer zoom step, no lower angle, no cut scenes.
4. **Sparse surfaces.** At most ten marking shapes per animal. No detail smaller than 0.06 m.
5. **A style check in code.** A unit test walks every zoo model and fails on a texture (other than the blob shadow), a metallic value above 0, a roughness below 0.85, or transparency outside shadows and water.

Optional concept images from the user are unapproved references. The owner may use or ignore them. They are never shipped, never a gate and never the place where a species' look is accepted. A species' look is accepted from in-game renders at the real gameplay camera on the Mac's GPU, and later by the user's own review of those renders. This document was written without opening them.

### 4.2 Readability within the style

| Lever | Rule |
|---|---|
| Body scale | Zoo scale classes (section 6.1). The smallest adult is 1.1 m in its usual pose. |
| Proportion | Head height at least 32 % of standing height (cats at least 36 % with mane or ruff). |
| Eyes | A dark oval at least 0.12 m wide with a white highlight of at least 0.04 m. Blink, slow blink and sleepy eyes by scaling the eye, as `kid.gd` does. |
| Seen from above | The camera looks down 40°. Identifying features go on the upper half: ears, mane crown, back bands, a tail carried up or in a curve. A face turned to a child tilts up 15° to 25°. |
| Color blocking | Two or three flat colors and one accent per species. Neighbouring blocks differ in lightness clearly (a luminance ratio of at least 1.5, checked from the palette constants). |
| Ground contrast | Body color against its habitat's ground: luminance ratio at least 1.4. Lion Hill's rock is a cool grey so a golden lion stands out. |
| Markings | Separate rounded shapes on the body, each at least 0.10 m across. |
| Limbs | At least 0.10 m thick, so an arm is 13 px wide at the near zoom and 9 px at the wide zoom. |
| Motion | Every action's key pose changes the silhouette: a yawn opens the jaw at least 45°, a pounce stretches the body, a swing shows a fully raised arm. |

### 4.3 Today's main-world animals, assessed

Measured from the builders in `animal.gd` and computed at the default camera (9.5 m, the animal at the child's position, 1024-high view):

| Animal | Height in the model | On screen, near zoom | On screen, wide zoom |
|---|---|---|---|
| Pig | about 0.80 m | 84 px (8.2 % of the height) | 54 px |
| Rabbit | 0.73 m (1.03 m with ears) | 76 px (110 px with ears) | 49 px |
| Sheep | 0.86 m | 91 px | 58 px |
| Dog | 0.77 m | 81 px | 52 px |
| Elephant | 1.61 m | 179 px (17.4 %) | 112 px |
| Child, for comparison | 1.30 m | 141 px (13.8 %) | 89 px |

Eyes are 0.063 m wide (`_eyes`, radius 0.035): about 9 px at the near zoom and 6 px at the wide zoom. On a 6.1-inch iPhone (an assumption: 64.6 mm of screen height for the 1024 logical pixels) a pig is about 5.3 mm tall and its eye about 0.55 mm. The user's complaint is confirmed by the numbers.

Options for the town, with consequences:

| Option | Gain | Consequences |
|---|---|---|
| A. Leave as they are (Phase 1) | None | None. Every tested behaviour stays valid. |
| B. Larger features only (eyes 0.10 m, bigger ears and snouts, blink) | Faces read about 1.6 times better | Art only. The animal images in older Mac evidence no longer match; the visit, contraption and town tours need new renders. |
| C. Bodies 1.25 times larger | 95 px to 113 px tall | `AnimalBrain.SPECIES` radii grow, so animals fit fewer gaps and the 240 s roaming tests may shift; the cart trailer (sized after a Mac finding) must be re-checked; house visits clip more furniture (`guest_world.gd` does not collide); label, ball, wish bubble and pick heights move; every animal render is invalid. |

**Recommendation.** A in Phase 1. Decide B and C after the user has seen zoo animals on devices; B is the safer first step. Nothing in this design changes a town animal without that decision.

## 5. What the camera shows (computed)

Constants: `PITCH` 40°, `FOV` 42° vertical, `ZOOMS` `[9.5, 15.0]`, focus 0.6 m above the child (`CameraRig.goal_pose`). The project stretches a 1366 × 1024 base with `canvas_items` and `expand`, so the logical height is 1024 on every layout and only the width differs: 1366 (iPad 4:3), 1475 (iPad Air), 1820 (Apple TV 16:9), 2208 (iPhone landscape, the layouts the tours use).

### 5.1 One gameplay screen on the ground

The visible ground is a trapezoid. Its depth does not depend on the device.

| Default zoom, 9.5 m | iPad 4:3 | iPad Air | Apple TV | iPhone |
|---|---|---|---|---|
| Depth, whole screen | 15.8 m | 15.8 m | 15.8 m | 15.8 m |
| of which toward the camera / beyond the child | 3.6 m / 12.2 m | same | same | same |
| Depth clear of the top bar (104 px) and the bottom controls | 11.4 m | 11.4 m | 11.4 m | 11.4 m |
| Width at the near edge | 7.3 m | 7.9 m | 9.8 m | 11.9 m |
| Width at the child | 10.1 m | 10.9 m | 13.5 m | 16.4 m |
| Width at the far edge | 19.7 m | 21.3 m | 26.2 m | 31.8 m |
| Ground area | 213 m² | 230 m² | 284 m² | 344 m² |

At the wide zoom (15 m): depth 24.1 m; width at the child 15.8, 17.0, 21.0 and 25.5 m; area 497 to 803 m².

Pixel scale at the child's position: 1 m of height is 106 px, 1 m of width is 135 px, 1 m of ground depth is 92 px (near zoom); 68, 87 and 58 px (wide zoom).

### 5.2 The height budget

Because the camera looks down, a tall thing beyond the child leaves the top of the screen. The table gives how far beyond the child (away from the camera) a point at a given height can be and still show below the top bar.

| Height of the point | Near zoom | Wide zoom |
|---|---|---|
| 0 m (ground) | 8.1 m | 12.1 m |
| 1.0 m | 5.8 m | 9.8 m |
| 1.5 m | 4.7 m | 8.6 m |
| 2.0 m | 3.5 m | 7.4 m |
| 2.5 m | 2.4 m | 6.3 m |
| 3.0 m | 1.2 m | 5.1 m |
| 3.5 m | 0.1 m | 4.0 m |

A point beside the child, or between the child and the camera, shows at any height up to 3.5 m.

### 5.3 Layout rules that follow

1. **H1, show spots.** Every spot where an animal does its signature thing has a viewing bay from which the top of the animal's head is inside the budget at the near zoom. Either the head top is at most 2.0 m high within 3.5 m beyond the bay (2.5 m within 2.4 m), or the spot is beside the bay.
2. **H2, action beside the path.** Tall play (monkeys on rings, a lion on a ridge) runs alongside a path, not beyond it.
3. **H3, low near paths.** Rock within 1.5 m of a path is at most 0.9 m high, so a 1.3 m child stays visible from every camera turn.
4. **H4, backdrop only at the back.** Crags up to 3.2 m carry no animals and stand at the far side or at least 6 m from a path. They show whole at the wide zoom.
5. **H5, flat ground for children.** In Phase 1 children stay on the ground plane. `PlayController._place_kid` sets the child's height to 0, `TownWorld.ground_point` intersects the plane y = 0 and `resolve_walk` is two-dimensional. "Hill" therefore means low terraces that animals climb, with ground-level paths and bays through and around them. Raised lookouts for children are a Phase 2 option (section 20).

### 5.4 Sizing a habitat "slightly larger than one screen"

Method: a habitat is larger than one gameplay screen when it cannot lie inside the visible trapezoid at the default zoom, on any target layout, at any camera turn.

- Both sides longer than the visible depth of 15.8 m guarantee that at every quarter turn. Minimum: 17 m (8 % more).
- The long side also exceeds the widest layout's mean width (iPhone: (11.9 + 31.8) / 2 = 21.9 m). Minimum: 22 m.

| Habitat | Size | Area | Against one screen (iPad 4:3 / iPad Air / TV / iPhone) |
|---|---|---|---|
| Lion Hill | 24 × 18 m | 432 m² | 2.0 / 1.9 / 1.5 / 1.26 screens |
| Tiger Hill | 22 × 18 m | 396 m² | 1.9 / 1.7 / 1.4 / 1.15 screens |
| Monkey Hill | 22 × 18 m | 396 m² | 1.9 / 1.7 / 1.4 / 1.15 screens |

"Slightly larger" is therefore true on the widest device and "about two screens" on an iPad. At the wide zoom Lion Hill fits one screen on the TV and the iPhone, which gives an overview by zooming out.

## 6. Scale and the roster

### 6.1 Zoo scale classes

The [scale contract](object-scale-and-surfaces.md) stays: 1 unit = 1 m, child height H = 1.30, a stylized and compressed scale. Animals are not catalog items, so the contract has no class for them. This design adds animal classes for the zoo; the owner records them in the contract when implementing.

| Class | Height in the usual pose | Against the child | Species |
|---|---|---|---|
| zoo small | 1.05 m to 1.25 m | 0.8 to 0.95 H | monkey, otter; later red panda, penguin |
| zoo medium | 1.30 m to 1.50 m | 1.0 to 1.15 H | lioness, tiger, hippo; later giant panda, sea lion |
| zoo large | 1.55 m to 2.0 m | 1.2 to 1.5 H | lion, zebra |
| zoo giant | 2.6 m to 2.8 m | 2.0 to 2.15 H | giraffe |

Real-ish or toy: large animals are compressed (the giraffe is about 0.6 of a real one, as the town's trees are compressed), medium ones are near real size, small ones are enlarged about 1.7 times (as the contract enlarges small decorations so they read). The order of sizes stays true: giraffe, then zebra and lion, then tiger and hippo, then monkey and otter.

### 6.2 Targets on screen at the default camera

Binding, measured from the built models through `CameraRig.project`, the animal at the child's position, near zoom:

| Target | Threshold | Today |
|---|---|---|
| T1 height of every adult in its usual pose | at least 115 px (11.2 % of the screen height) | 76 px to 91 px |
| T2 long side of a four-legged animal | at least 250 px | about 135 px |
| T3 eye width | at least 16 px | about 9 px |
| T4 smallest marking | at least 13 px | not applicable |
| T5 limb thickness | at least 13 px | 9 px to 13 px |
| T6 height at the wide zoom | at least 72 px | 49 px to 58 px |

The same numbers in millimetres, under stated assumptions (iPhone 6.1 inch: 0.063 mm per logical pixel; iPad Air 10.9 inch: 0.154 mm; 55-inch TV: 0.669 mm; the user's iPhone model is not recorded in the documents read):

| | iPhone | iPad Air | TV |
|---|---|---|---|
| T1, 115 px | 7.3 mm | 17.7 mm | 77 mm |
| Lion, 165 × 283 px | 10.4 × 17.9 mm | 25 × 44 mm | 110 × 189 mm |
| Eye, 16 px to 19 px | 1.0 mm to 1.2 mm | 2.5 mm to 2.9 mm | 11 mm to 13 mm |
| Pig today, 84 px | 5.3 mm | 12.9 mm | 56 mm |

An honest limit: on a phone a lion's eye is about 1.2 mm. With the camera fixed, detail below 0.10 m is not a target on a phone; silhouette and color blocks carry the species there. If the Lion Hill slice shows that this is still too small, the first lever is the scale class (up to 15 % more), not the camera.

### 6.3 Phase 1 roster

Names are proposals for the creator, checked against the player nicknames, pet names and town animals.

| Species, names | Habitat | Real size | Zoo size (m) | On screen, near zoom | Silhouette and the details that must read |
|---|---|---|---|---|---|
| **Lion** Rory | Lion Hill | 1.2 m at the shoulder, 2.5 m long | 1.55 tall at the mane, 2.1 long, mane 1.05 across, eyes 0.14 | 165 × 283 px | Round dark-crowned mane ruff seen from above, golden body, pale muzzle, tufted tail carried in a curve, round ears on the mane |
| **Lioness** Honey | Lion Hill | 1.1 m, 2.3 m | 1.35 tall, 1.95 long | 143 × 263 px | No mane, sleek head with round ears, white chin, same tail tuft |
| **Tiger** Tango | Tiger Hill | 1.0 m, 2.8 m | 1.40 tall, 2.2 long, tail 1.1 | 149 × 297 px | Six broad black back bands on orange, three tail rings, white cheek ruffs and belly, white spot on each ear back |
| **Monkey** Mango, Coco, Peanut, Momo, Bibi | Monkey Hill | 0.5 m sitting | 1.10 sitting, 1.9 hanging, arm span 1.8, tail 1.0, limbs 0.11 thick | 117 px sitting, 202 px hanging, 243 px span | Long arms and tail, pale face disc 0.34 m, round ears, five flat color variants, one smaller youngster (0.85 m) |
| **Giraffe** Topper | Savanna Meadow | 4.8 m | 2.8 tall, shoulder 1.75, 2.0 long | 297 px (29 %) | Long neck, two dark-tipped horns, eight to ten large patches, dark lashes, tufted tail |
| **Zebra** Zig, Zag | Savanna Meadow | 1.6 m at the ears | 1.65 tall, 1.9 long | 175 × 256 px | Five black body bands and two neck bands on white, upright mane crest, dark muzzle |
| **Hippo** Bubbles | Splash Bay | 1.5 m, 3.5 m | 1.35 tall, 2.3 long, 1.2 wide, gape 0.75 | 143 × 310 px | Barrel body, wide square muzzle, small ears that twirl, four peg teeth, pink mouth |
| **Otter** Skip, Ripple | Splash Bay | 0.6 m standing | 1.10 standing, 0.6 on all fours, 1.3 long | 117 px standing | Cream face and throat, big nose, thick tapered tail, paws held together |

Excluded on purpose: reptiles, insects and anything frightening. [pets-rooms-assets.md](pets-rooms-assets.md) records that rule for pets; it is carried over to the zoo as the default (section 20).

### 6.4 Natural behaviour and what each answers

Every species has three or more things it does by itself and at least three answers to a child: a treat, a signature only it has, and an answer to an emote. Toys, stations and other animals add more (section 10).

| Species | By itself | Treat | Signature (only this species) | Emote answers |
|---|---|---|---|---|
| Lion | Basks on the Sun Rock, patrols the Ridge, surveys the savanna, big yawn, naps in the shade | Bats a snack box open and eats | **Roar and ridge walk.** A cheer makes Rory stand and roar a soft "rawr". Walking Lion's Pass makes him pace the Ridge beside the child | Wave: nod and tail thump. Heart: slow blink. Dance: Honey rolls on her back |
| Tiger | Prowls low, walks the Log Bridge, soaks in the pool, stretches on the Scratching Tree | Holds a fish ice pop between its paws and licks | **Peekaboo and pool leap.** Standing still by the thicket brings up the ears, then the eyes. A floated ball makes Tango leap in from the Falls Ledge, swim it back and shake dry | Wave: chuff and cheek rub on the bay post. Cheer: a show walk along the log. Dance: rolls and bats the air |
| Monkey | Swings the Ring Run, rides the vines, climbs towers and the Spire, leaps between platforms, grooms, tags | Leaps and catches a banana in mid-air, peels it, eats with legs dangling | **Copycat.** Every emote is copied by the whole troop in a ripple, with long arms | The four emotes themselves, exaggerated |
| Giraffe | Browses the acacia tops, ambles, splays its legs to drink | Curls a long tongue round a leaf bundle | **Bow.** A child standing still within 3 m brings the head down to the child's height | Wave: two slow neck nods. Cheer: a short funny canter |
| Zebra | Graze, stand head to tail swishing, dust roll, trot | Eat hay from the hand | **Run with me.** A child running a line through the meadow gets both zebras galloping alongside | Cheer: buck and bray. Dance: prance in a circle |
| Hippo | Floats with only eyes, ears and nose out, twirls its ears, basks on the beach, yawns | Opens wide and chomps a melon with a splash | **Surface beside you.** A child standing still on the jetty brings Bubbles gliding over to rise next to it | Wave: ear twirl. Cheer: a fountain of bubbles |
| Otter | Float on their backs holding paws, dive and pop up, slide down the mud slide, juggle a pebble | Beg upright, eat on the belly | **Bring it back.** A ball on the beach is pushed back to the child's side; a child walking the bank is escorted | Wave: both paws. Dance: barrel rolls |

### 6.5 Phase 2 roster (planned, less detail)

| Species | Habitat | Zoo size | Signature |
|---|---|---|---|
| Giant panda | Bamboo Grove | 1.4 m sitting | Somersault on a dance; scoots over to sit beside a still child |
| Red panda (two) | Bamboo Grove | 0.8 m, 1.15 m standing | Stands up with arms spread when surprised, then hides and peeks |
| Penguins (four) | Snowy Cove | 1.05 m | Line up and waddle after the child |
| Sea lion | Snowy Cove | 1.3 m upright | Balances a ball on its nose and bumps it back |

Lion cubs and a tiger cub also come in Phase 2. A pool for later: flamingo, peacock, kangaroo, capybara, koala, polar bear, meerkat.

### 6.6 Why seven now and eleven later

1. **The three hills are binding.** Lion, tiger and monkey are in the first delivery.
2. **Each other zone needs two species.** Two give reactions between animals inside a zone, and together the four show the range the user asked for: the giant (giraffe), a herd (zebra), water (hippo) and a small one sized up (otter).
3. **The supply of distinct play.** Counting verbs that are really different (roar and patrol, peekaboo and swim, copy and acrobatics, bow, run alongside, chomp, bring back, tumble, hide and peek, follow in a line, balance a ball) gives about eleven to fourteen before they repeat. That is the ceiling worth building.
4. **Production cost in this codebase.** A species costs a builder of 60 to 110 lines, a row of proportions for the rig, six to nine poses, eight to ten strings in six languages, rows in the behaviour table and tests that are mostly table-driven. That part is cheap. The costly part is review: each species needs rendered views from the Mac that the owner opens, and usually a repair round. The `first-steps` candidate needed twelve rounds for layout alone.
5. **Why code-built, not modeled.** The pet GLBs expose single joints only, so climbing and swinging would need a new rig contract with the modeling lane and an import on the Mac for every change. Code-built animals keep rig and shape in one place and can be measured headless. A species can still be swapped for a modeled actor later if it keeps the pivot names.
6. **Device load.** Fourteen individuals, of which one habitat's worth is on screen, stays inside the budgets of section 15. Eleven species means about twenty-four individuals; that is the reason Phase 2 is separate and measured first.

Fallback cut: if the first delivery must be smaller, it ends after the three hills (three species, eight individuals). That would meet the hills and the scale but not "more species"; it is not recommended.

## 7. Rig and animation

### 7.1 Approach

Keep today's technique: a tree of named pivots, angles written in code every frame, parts merged per pivot. Add what large cats and monkeys need. A new `game/scripts/art/zoo_rig.gd` holds it; `game/scripts/art/zoo_animal.gd` holds the builders and poses.

| Need | Today | Added |
|---|---|---|
| Limbs | One capsule turning at the hip or shoulder | Two segments: `ArmL/ArmR` → `ForeL/ForeR` → `HandL/HandR`; `LegL/LegR` → `ShinL/ShinR` → `FootL/FootR` |
| Spine and jaw | `_body` and `_head` | `Chest` (spine bend), `Neck`, `Head`, `Jaw` |
| Tail | One pivot | A chain `Tail0`…, turned like the elephant's `_trunk`, each segment lagging its parent |
| Changing action | Some angles set at once | A pose is a set of target angles; one step eases every pivot toward its target, so actions blend |
| Holding on | None | A two-bone reach (law of cosines) puts a hand or foot on a world point. A pure function, unit-tested |
| Hanging and swinging | A seated child follows a marker on a swinging pivot | The body hangs from its grip as a pendulum; the swing's own pivot turns with it |
| Jumps | The thrown ball's arc (`animal.gd` `show_throw`) | A leap, pounce or dive is an arc over the straight move the brain reports, with crouch, stretch, tuck and landing |
| Life | Ear and tail sway | Blink and slow blink, breathing, squash and stretch within 8 % |

### 7.2 Monkeys: climbing, swinging, jumping

- **Routes.** The map data declares the structures as typed elements: `pole`, `ledge`, `rings` (a line of grips), `vine` (a pendulum from an anchor), `net`, `bridge`, and `leap` links between perches up to 3 m apart. The brain moves each monkey along this graph. A monkey is always on an element or on the ground; its height is the element's own height at that point.
- **Rings.** Hand over hand: the body swings as a pendulum from the holding hand, the free arm reaches for the next ring at the forward peak, then they change. The phase comes from the distance along the line, so every device draws the same swing from the same position.
- **Vines.** An arc of up to 50° each way. At the forward peak a monkey may let go, fly and land on a platform or catch the next vine.
- **Poles, nets and the Spire.** Arms and legs reach in turn for grips 0.3 m apart; the body stays close to the surface.
- **Leaps.** Crouch, push off with arms forward, tuck, land with a small squash.
- **Never idle blobs.** While a child is on Monkey Hill at least two of the five are in a moving action, and no monkey within 8 m of a child sits still longer than 6 s unless it is the one napping.

### 7.3 Lions and tigers

Four two-segment legs allow a real crouch (the cat's wiggle before a pounce), a sit, a sphinx rest, a roll onto the back, a paw that bats, and a stretch up a tree with the paws placed by the reach function. The jaw opens for the yawn and the roar. The mane shakes with the head. The two cats share the rig and differ in proportions, markings, places and answers (section 8).

### 7.4 What travels over the network

Six floats per animal, as today: position x and z, facing, action index, and two more that depend on the action: a target point (ball, leap landing) or a height and a route element. Sent four times a second like `Animals.ev_animals`; swings and arcs are drawn locally between updates. If the Mac's renders show stutter on Monkey Hill, that hill alone may send eight times a second.

## 8. The zoo map

### 8.1 Overall

84 × 64 m (half extents 42 × 32), about 2.3 times the town. East is +x, toward the default camera is +z, as in the town. Children arrive at the south and look north, so open ground is in front and the hills are behind.

| Area | Rectangle (x, z) | Size | Phase |
|---|---|---|---|
| Tiger Hill | x −40…−18, z −28…−10 | 22 × 18 m | 1 |
| Lion Hill | x −12…12, z −28…−10 | 24 × 18 m | 1 (slice first) |
| Monkey Hill | x 18…40, z −28…−10 | 22 × 18 m | 1 |
| Hill Road | z −10…−5.5, the whole width | 4.5 m wide | 1 |
| Splash Bay | x −40…−18, z −5.5…10.5 | 22 × 16 m | 1 |
| Savanna Meadow | x −12…12, z −5.5…12.5 | 24 × 18 m | 1 |
| Picnic Green, later Bamboo Grove | x 18…40, z −5.5…10.5 | 22 × 16 m | lawn in 1, habitat in 2 |
| Two avenues | x −18…−12 and x 12…18 | 6 m wide | 1 |
| Entry plaza | circle at (0, 20), radius 6 | | 1 |
| Zoo Station | platform x −4…4, z 27…31; arrival (0, 26) facing north | | 1 |
| South-west lawn, later Snowy Cove | x −40…−18, z 15…29 | 22 × 14 m | lawn in 1, habitat in 2 |
| South-east lawn | x 18…40, z 15…29 | 22 × 14 m | later |

Why this order: the lions look out over the savanna from their rock, the stream from Tiger Falls runs under the Hill Road into Splash Bay, and the monkeys' woods will border the Bamboo Grove. The first animals a child meets, 11 m from the plaza, are the zebras.

Walking at 3.4 m/s (`PlayController.WALK_SPEED`): station to the savanna 5 s, to Lion Hill's overlook 12 s, to Tiger Hill or Monkey Hill 14 s.

Habitats have no fences that block children. The game has no path finding (`PlayController._walk_to` goes straight and stops when blocked), so a fence would stop every tap across it. Low edging and signs mark each habitat; the animals stay inside by their own rule. Blocked for children: terraces, pools, tree trunks and structure posts, as circles and boxes that `resolve_walk` slides around like the town's ponds and trees.

The map can grow later without touching saves, as the town did (32 × 28 m to 52 × 44 m): positions stay valid.

### 8.2 Lion Hill (24 × 18 m)

A low rock island with a loop path around it and a pocket in front. Positions are a proposal to tune on the slice.

| Feature | Where | Height | Who uses it, and how it is seen |
|---|---|---|---|
| **Pride Overlook** (viewing bay) | South edge, 6 × 2.5 m, open to the Hill Road | ground | Children. The treat table stands here |
| **Sun Rock** | 2 m beyond the overlook, 7 × 4.5 m, tilted to the south | 0.7 m | Rory basks, sits and roars here, facing south. Head top 1.75 m (lying) to 2.35 m (roaring), 2.2 m beyond the bay: inside the budget (rule H1) |
| **Lion's Pass** (path) | West side, 3 m wide, 12 m long, north to south | ground | Children walk beside the Ridge |
| **The Ridge** | Along the pass, 3 × 6.5 m | 1.0 m to 1.2 m | The patrol route. A lion here is beside the child, so its whole body shows (rule H2) |
| **Ridge View** (bay) | Half way along the pass | ground | Children |
| **Back Trail** (path) | North side, 2 m wide | ground | Joins the two side paths |
| **The Crag and the Den** | North end; the den mouth faces the east path | 3.0 m backdrop; den at ground | Lions shelter here in the rain and peek out |
| **Shady Ledge and the Shade Tree** | East of the Ridge, 4.5 × 4 m | 0.4 m | Honey naps and grooms; Rory comes to bump heads. Seen from Cub Walk beside it |
| **Cub Walk** (path) | East side, 3 m wide | ground | Children |
| **Den Corner** (bay) | North end of Cub Walk | ground | Children, facing the den mouth |
| **Tall Grass** | Between the overlook and the Shady Ledge, about 4 × 4 m | ground | Stalking and pouncing on toys. Children may stand in it |

The loop is about 38 m (11 s). From the overlook at the near zoom a child sees the Sun Rock, the Tall Grass and the nearer half of the Ridge. The Crag, the Den and the Back Trail are beyond the frame, so the hill has to be walked.

### 8.3 Tiger Hill (22 × 18 m)

Water, cover and a balance beam for one tiger that likes to hide and swim.

| Feature | Height | Use and view |
|---|---|---|
| **Tiger Falls** | 2.6 m backdrop at the north | A ledge of rock with falling water (white drops, no texture) |
| **Falls Ledge** | 1.0 m, beside the falls | Tango lies with paws hanging and leaps into the pool from here. Seen from Falls Bay beside it |
| **Tiger Pool** | water at ground level, about 7 × 5 m | Soaking and swimming. Seen from Pool Bay on its south shore: a swimming tiger is at most 0.5 m high and shows 7 m away |
| **Log Bridge** | 0.6 m, 5 m long, across the stream | The balance walk. 2 m beyond Bridge Bay; head top 2.0 m: inside the budget |
| **Bamboo Thicket** | ground, about 8 × 5 m, stalks 1.6 m and sparse | Hiding with ears, eyes and tail tip showing. Seen from Thicket Bay |
| **Scratching Tree** | trunk beside Bridge Bay | Tango stretches up to 2.2 m, beside the child |
| **Sunning Slab** | 0.4 m by the pool | Naps |
| **Stripe Trail** (path) | ground, 3 m wide, about 30 m | Hill Road → Bridge Bay (stepping stones over the stream) → Pool Bay → Falls Bay → Thicket Bay → Hill Road |

### 8.4 Monkey Hill (22 × 18 m)

Everything the monkeys climb stands beside the children's path and round a clearing (rule H2).

| Structure | Height | What happens on it |
|---|---|---|
| **Canopy Lane** (path) | ground, 3 m wide, north from the Hill Road | Children. The Ring Run runs beside it |
| **Ring Run** | a beam at 2.9 m with seven rings (hands at 2.6 m), 7 m long, 2 m west of the lane | Hand-over-hand swinging alongside a walking child. Feet clear a child's head |
| **West Tower, East Tower** | platforms at 1.2 m and 2.0 m, a pole each, a net ramp outside | Climbing, sitting with legs dangling, leaping across |
| **Monkey Court** (clearing) | ground, 7 m across | Children stand here; monkeys land here |
| **Vine Swings** | two ropes of 2.0 m from an arch at 3.0 m, west of the court | Big arcs; a let-go flight over the court to the East Tower |
| **Tyre Swing** | hangs from a 2.6 m frame, east of the court | A child pushes; the monkey swings higher and jumps off |
| **The Spire** | 3.2 m rock at the north with ledges at 0.8, 1.4 and 2.0 m and a bell | The climbing race. The two lower ledges show at the near zoom from the court's edge; the bell ledge shows whole at the wide zoom |
| **Net Bridge** | 4 m span at 1.2 m to the Banana Tree | Running across; it sags and bounces |
| **Banana Tree** | fruit at 1.8 m | Jump and grab |
| **Bongo Logs** | ground, by the court | A child drums; monkeys drum and dance |
| **Hammock** | 0.8 m, behind the West Tower | The one napping monkey; a pair grooming |
| **Tower Walks** (paths) | ground | Two side loops back to the Hill Road |

### 8.5 Savanna Meadow and Splash Bay

- **Savanna Meadow** (24 × 18 m): open grass, three acacias with tops at 2.8 m to 3.2 m, a waterhole of 3 m radius with a hand pump, tufts of tall grass, a treat table at the south gate. Children walk straight through it. The giraffe is 2.8 m: beyond the child its head leaves the frame at the near zoom (section 5.2), so it holds its head at about 2.0 m when a child is within 6 m, and its signature is to bow lower still.
- **Splash Bay** (22 × 16 m): a pool of two overlapping circles (about 12 × 8 m), a beach on the south, a jetty spot at the pool's edge, a mud slide of 0.8 m on the east shore, a shower arch, a treat table. The stream from Tiger Falls enters at the north.

### 8.6 Plaza and station

The plaza has a map board with the habitats as pictures, benches and lamp posts. The Zoo Station has a platform, a shelter and the same toy tram as the town's stop.

## 9. Entrance, arrival, return, companions

### 9.1 The entrance in town

**A Zoo tram stop**: a catalog thing of the landmark class (about 3.2 × 2.4 × 2.0 m: a platform, a short piece of rail, a toy tram car and a sign with a paw).

- **Where.** Added by the game to every town. In a new town it stands at a designed free spot 4 m to 6 m from the arrival point and inside the first view. In an existing town `TownModel.find_free_spot` finds the nearest free place to the same spot, so nothing a child made is moved. If none is free within reach, other anchors are tried; the journey can also start from the guide (below).
- **Why not at the town's edge.** The nearest edge is 13 m from the arrival point. The camera shows 2.8 m of clear ground toward itself and about 8 m beyond the child (section 5.1), so an edge station is on screen only for a child already walking to it. A stop near the arrival point is seen in the first seconds of every session.
- **Rules.** Exactly one per town; not in the toy box; it can be moved like a cottage and never put away ("The tram stop stays in town. You can move it."); it does not count toward the 300 things; its boarding point must face open ground, by the same rule as a cottage door (`TownModel.validate_door`); it cannot be wrapped or saved in a blueprint. If a town loads without one, one is added.
- **How it is found.** It is on screen on arrival. A new child and a returning child each get one line, once, at the top: "A tram to the zoo is waiting." The Activities guide gets a card "The zoo" with **Go there**. A name tag "Zoo tram" shows from 13 m like the landmarks' tags.

The alternative, a fixed station beyond the north edge, is described in section 20 with its consequences.

### 9.2 The ride

| | Touch | Controller |
|---|---|---|
| Board | The action button **Ride to the zoo** at the stop, or tap the tram | **X** |
| Come back | **Ride home** at the Zoo Station, or the small **Ride home** button beside the place name at the top | **X** at the station; pointer and **A** on the button |

- Arrival at the zoo: on the station platform, facing north, the plaza ahead. Four arrival places side by side, so friends never stand in each other.
- Arrival in town: at the stop's boarding point. If the stop is being moved by a friend, at the town's usual arrival point.
- The guide's card and an invitation's **Join** start the same journey from anywhere ("the tram picks you up"), because a walk to the stop can be blocked and the game has no path finding.
- A new session always starts in town. The place is not remembered between sessions.

### 9.3 Companions

| Companion | Rule |
|---|---|
| Pets in follow mode (cat, dog, bird, butterfly) | Come along and follow everywhere in the zoo. `pet_world.gd` already draws a following pet in its owner's space. Zoo animals ignore them in Phase 1 |
| A town animal walking with a child (house visits) | Stays in town. The visit ends at boarding (`Animals.end_visit`), with "%s will wait for you in town." |
| An animal passenger in a cart | Not affected: a child gets off the cart before boarding |

## 10. Play

### 10.1 Position

Interactive observation first: the child is a friend, a watcher and a maker. A little care, as one free verb (offer a treat) with no need behind it. A little building, as a small zoo toy box. No hunger, no cleaning, no tidying, no tasks.

### 10.2 What a child can do

1. **Walk, stand still, run.** Several signatures answer movement alone, so the first answers need no button.
2. **Emotes** (wave, cheer, dance, love): the existing four buttons.
3. **Offer a treat**: at a habitat's treat table (the nearest free animal comes), or on the strip of an animal being looked at (that animal answers). Nothing is carried and nothing runs out. After three treats in a minute the animal shows that it is full and happy with a different move.
4. **Use a station**: a fixed thing with one action.
5. **Place a toy** from the zoo toy box. Toys stay where they are put, also after everyone leaves.
6. **Look**: tap an animal to frame it (section 11).
7. **Photo and story**: the existing camera and story strip.

### 10.3 Stations (Phase 1)

| Station | Habitat | Action | What it does |
|---|---|---|---|
| Treat table (five) | each | **Offer a treat** | Section 6.4 |
| Ball basket | Tiger Hill, Pool Bay | **Float a ball** | The pool leap |
| Bell rope | Monkey Hill, the court | **Ring the bell** | The climbing race |
| Tyre swing | Monkey Hill | **Push the swing** (up to three pushes) | Higher each push, then the jump |
| Bongo logs | Monkey Hill | **Play the drums** | Eight seconds of drumming and dancing |
| Water pump | Savanna Meadow | **Pump water** | The waterhole fills for a minute; giraffe and zebras drink |
| Shower arch | Splash Bay | **Turn on the shower** | The hippo stands under it; the otters take the slide |

A station rests 1.2 s after use, like a contraption trigger.

### 10.4 The zoo toy box (Phase 1)

In the zoo, Decorate opens two tabs: **Zoo** and **Picnic**. Up to 80 things in the zoo. Proposed sizes; the owner fits them to the scale contract's classes.

| Thing | Size (w × h × d, m) | Who answers |
|---|---|---|
| Play ball | 0.5 × 0.5 × 0.5 | Lion: stalk, pounce, flop. Tiger: hug and kick. Monkeys: catch between the towers. Otters: bring it back |
| Big box | 0.9 × 0.8 × 0.9 | Lion sits on it. Tiger hides in it with its tail out. A monkey pops out of it |
| Scratching log | 1.8 × 0.8 × 0.8 | Tiger and lion scratch; otters slide over it |
| Leaf feeder | 0.9 × 2.4 × 0.9 | The giraffe browses wherever it stands; zebras nibble under it |
| Hay bale | 1.1 × 0.8 × 0.8 | Zebras eat; a monkey sits on top |
| Play mirror | 1.0 × 1.3 × 0.4 | A monkey makes faces; the lion looks puzzled; the tiger pats it |
| Picnic tab: bench, picnic blanket, flowers, fence, garden umbrella, picture board | existing | A garden umbrella by the Sun Rock gives shade the lion moves into ("%s likes the shade." exists) |

An animal that plays with a ball moves a drawn ball only; the placed ball returns to its place afterward. Zoo animals never change saved things, as in town.

Not offered in the zoo in Phase 1: cottages, ponds, toy tracks, cart rails, contraptions, puzzles, presents, blueprints, "On display".

### 10.5 Interaction table

| Where | The child does (touch / controller) | The animal answers | The world answers | With a friend |
|---|---|---|---|---|
| Pride Overlook | Wave (emote button / pointer and A) | Rory lifts his head, nods, thumps his tail | A puff of dust; the line "Rory says hello." | Two waves: Honey joins |
| Lion Hill, within 8 m | Cheer | Rory stands and roars a soft "rawr" | Birds rise from the Shade Tree; the zebras in the savanna look up | Two cheers: Rory and Honey roar in turn |
| Lion's Pass | Walk along it (tap ahead / left stick) | Rory rises and paces the Ridge beside the child, stops when the child stops | — | Each child gets a lion |
| Lion treat table | **Offer a treat** (action button / X) | The nearest lion comes to the rock's edge, bats the box open, eats | The open box lies there for a while | Each child's box goes to a different lion |
| Lion Hill island | Place a Play ball (Decorate, Zoo tab, Place here / pointer and A, +) | Crouch, wiggle, pounce, bat, chase, flop | The ball rolls and comes home | A friend restarts it with **Roll the ball** |
| Sun Rock | Place a garden umbrella beside it | The basking lion moves into the shade | — | — |
| Any, in the rain | Wave at the den | A head comes out of the Den | — | — |
| Thicket Bay | Stand still 1.5 s | Tango's ears, then eyes, rise; a slow blink | Stalks part | — |
| Thicket Bay | Wave | A chuff; Tango bounds out and rubs a cheek on the bay's post | — | — |
| Pool Bay | **Float a ball** | The leap from the Falls Ledge, the swim back, the shake | Rings on the water, drops on the bay, wet paw prints | One floats the ball, the other watches from Falls Bay or takes the photo |
| Tiger Hill | Cheer | A show walk along the Log Bridge with a pause in the middle | — | — |
| Tiger Hill | Place a Big box | Tango hides in it; pops up when a child comes within 2 m | — | — |
| Monkey Hill, within 8 m | Any emote | The troop copies it in a ripple | — | The troop splits to copy each child |
| Canopy Lane | Walk along it | Monkeys drop onto the Ring Run and swing alongside, then leap to a vine | Rings sway | Two children: a monkey each |
| Monkey Court | **Ring the bell** | A race up the Spire; the first rings the bell again and poses | The bell rings | — |
| Tyre swing | **Push the swing**, up to three times | Higher each time, then a jump with a turn in the air and arms up | — | One pushes, one stands where it lands |
| Monkey treat table | **Offer a treat** | A leap and a catch in mid-air; the peel; eating with legs dangling | The peel drops | The next banana goes to another monkey |
| Bongo logs | **Play the drums** | Monkeys drum on the platforms; two dance | A beat for eight seconds | — |
| Savanna | Stand still within 3 m of Topper | The head bows to the child's height; a blink | — | One stands, one takes the photo |
| Savanna | Run a line of 6 m near the zebras | Zig and Zag gallop alongside for up to 12 s, then toss their heads | Dust puffs; Topper's head follows them | Children at opposite ends: the zebras run between them |
| Savanna | **Pump water** | Topper splays to drink; the zebras drink side by side | The waterhole fills | — |
| Savanna | Place a Leaf feeder | Topper walks to it and browses | Leaves thin and grow back | — |
| Splash Bay jetty | Stand still | Bubbles glides over and rises beside the jetty | Bubbles on the water | — |
| Splash Bay | **Offer a treat** | Bubbles opens wide and chomps the melon | A splash; the wave rocks the otters | Two melons at once: a bigger splash |
| Splash Bay beach | Place a Play ball | The otters push it back to the child's side | — | The otters send it to each child in turn |
| Splash Bay bank | Walk along it | The otters swim alongside and pop up ahead | Ripples | — |
| Splash Bay | **Turn on the shower** | Bubbles stands under it with an open mouth; the otters take the mud slide | Water arc, a puddle | — |

Reactions between animals (data-driven): a roar makes the lioness chuff and the zebras look up; a gallop makes the giraffe's head follow; the hippo's splash rocks the otters; an otter's slide makes the hippo's ears twirl; the bell brings every monkey.

### 10.6 The line over an animal and the discovery log

As in town (`Animals.ev_focus`), an animal busy with a child says so over its head and on its strip ("Tango is playing peekaboo."). The first time a town sees an answer, it goes into the scrapbook's new page **Zoo friends**, with the names of the children close by. Answers not yet seen show a gentle hint ("Try standing very still near Topper."), like the hints for Cozy Spots. No counts, no rewards, nothing unlocks.

### 10.7 Town features in the zoo

| Works in the zoo | Not in the zoo (Phase 1) |
|---|---|
| Walking, emotes, story poses, camera, story strip, scrapbook, pets, dress up, wardrobe, language, sound, hellos for friends, Undo, Things here, invitations | The Wishing Tree and its landmarks, the dance party, hide-and-seek, wishes, fetch and the animals' own games, house visits, Cozy Spots, lamplighter walk, trails, toy tracks, cart rides, contraptions, puzzles |

Evening and weather are the town's and show in the zoo too (sky, lamps, rain, snow), so the two maps never disagree. In Phase 1 the only behaviour tied to them is the lions' den in the rain.

## 11. Looking at an animal, and the HUD

### 11.1 Look framing

Tapping an animal (or pointer and **A**) walks the child to within 3.5 m and starts **Look**. It is the same camera: the same angle, field of view, zoom and turn.

- The focus glides from the child to a point between the child and the animal's head, along the ground, by at most 2.5 m. This brings a tall or raised head into the frame.
- If head and child still do not both fit between the top bar and the bottom controls, the camera steps back, never beyond the wide zoom's 15 m. It never comes closer than the zoom the player chose.
- A small strip shows the name, what the animal is doing, **Offer a treat** and **Done**. It is not a dialog and has no shade, because the town's animal card (`Hud._open_animal`, `_dialog`) covers the animal it describes.
- Look ends on **Done**, **B**, walking away, opening Decorate, a dialog, or the animal moving more than 9 m off.
- With Reduce motion the focus changes without a glide.

No request is needed: an animal already turns to a still child within 4 m.

### 11.2 Rules with the existing HUD

1. The strip takes one of the two places the placement tools use (`Hud.zones`), chosen by `PlacementDock.choose_place` with the animal's head box as the "thing" and the child's box as the child.
2. Side menus and the top bar's right part step aside for the head box and the child exactly as for a held thing (`Hud._keep_menus_clear`).
3. The controller's hints keep off both boxes (`pad_input.gd`).
4. Look and holding a thing never happen together: picking a thing ends Look, and the placement rules then apply unchanged.
5. In the zoo while walking, nothing changes: the top bar, the corner column and the emotes stay where they are.

Targets: with Look on, for every show spot and its bay, the animal's head box and the child's box are whole inside the safe area and under no shown control, in six languages at the four layouts.

### 11.3 Other HUD changes

- The place name at the top left shows "Zoo · Lion Hill" by where the child stands, with **Ride home** beside it.
- A friend's chip gets a small paw while that friend is in the zoo, and a small house while you are in the zoo and they are in town.
- The rotate and zoom buttons show on every outdoor map (today: `s == "town"` in `Hud.bind`).
- The room's heart button, "Put on display", blueprints and the trail button do not show in the zoo.

## 12. Travel architecture

### 12.1 A registry of places

New `game/scripts/core/places.gd`, pure data and helpers, the one place that knows the maps.

| Helper | Purpose |
|---|---|
| `is_map(space)`, `kind(space)` | `"map"`, `"room"` or nothing. Replaces `space == "town"` where "outdoors" is meant |
| `map_of(space)` | The map a space belongs to (a cottage room belongs to the town) |
| `half(space)`, `max_items(space)` | Extents and caps; `TownModel.validate` and `TownWorld.resolve_walk` ask here |
| `solids(space)`, `keep_clear(space)` | Fixed blockers and places no thing may stand; the Wishing Tree becomes the town's entry instead of a special case |
| `allows(kind, space)` | What the toy box offers there; `Catalog.allowed_in` asks here |
| `arrival(map)`, `destinations(from)` | Where a traveller arrives; where a stop can go. One destination today; with two, the stop shows a board of cards |
| `music(space)` | The music context; `main.gd` asks here |

`TownModel.is_space` accepts a map from the registry or a room of an existing cottage.

### 12.2 The audit this needs

Every `"town"` literal is read and sorted into "the town itself" (stays), "outdoors" (asks the registry) or "not a room" (asks the registry). Found while reading, all wrong for a zoo today:

| Place | Today | Effect on a zoo if left |
|---|---|---|
| `TownModel.validate` | `TOWN_HALF if space == "town" else ROOM_HALF`; room cap otherwise | Things refused beyond a room's size; 40 things only |
| `TownWorld.set_view`, `_build_room` | Anything but town is built as a room | `parse_room("zoo")` is empty: an error |
| `TownWorld.resolve_walk` | Room bounds otherwise | The child held in an 8 × 6 m box |
| `PlayController._on_view_changed` | `rig.set_room(view != "town")` | The room camera |
| `Catalog.allowed_in`, `Hud.catalog_tabs` | "home" kinds otherwise | The indoor toy box |
| `Hud._refresh_heart` | Shown when not town | A room's heart button |
| `main.gd` music context | "home" otherwise | Quiet indoor music |

A unit test lists the remaining literals against an allowed list, so a new one cannot slip in.

### 12.3 The journey, step by step

1. **Board.** Control pauses; a held thing is cancelled, a seat is left, a lock is given back, fetch and Look end. The child steps to the tram's door (up to 0.8 s).
2. **Ask.** `Session.travel(to)` reaches the authority. It answers with the place and the arrival point, records the traveller's new space at once and tells the others, so friends see the child leave.
3. **Journey card.** A full-screen card in the guide's drawing style fades in (0.3 s): a tram, the name of the place, a dotted line from a town picture to a zoo picture with the tram moving along it. A tram bell sounds; the music changes level. With Reduce motion the card is still.
4. **Under the card.** The world switches to the zoo (built the first time, kept afterward). The zoo's animals and stations arrive from the authority.
5. **Arrive.** After at least 1.2 s and once the zoo is ready, the card fades out (0.35 s). The child stands on the platform; control returns. "Welcome to the zoo!" the first time.

Typical length 2 s. The card is there for the journey's sake; nothing is streamed. The origin stays as it was until the answer is yes.

### 12.4 When something goes wrong

| Case | What the child sees | What happens |
|---|---|---|
| The authority says no | The child steps back; a short message | Nothing changed |
| No answer, or the zoo is not ready, within 8 s | "The tram could not leave right now. You are still in town." | The client asks to travel back to the origin (the request names a place, so repeating it is harmless), shows the origin and offers the same action again |
| The connection drops on the way | The card goes; the usual Reconnect | After reconnecting, the child is in town, as after every join |
| The app is put in the background | The journey waits and continues | Solo towns save as usual |
| The stop was moved or is held by a friend on the way home | Arrival at the town's usual arrival point | |

A child can never be left between maps: the client always shows the map the authority last confirmed.

### 12.5 Authority and players' places

- **Only `travel` changes a player's map.** `_srv_state` keeps accepting a move between a map and the rooms that belong to it (walking into a cottage), and drops a state that names another map. Late movement packets from before a journey therefore cannot pull a child back.
- The authority does not require the child to stand at the stop. Positions are already the client's word, and invitations and **Ride home** start from anywhere. It does enforce a rest of one second between journeys.
- Friends are told through the existing `ev_player_state`. `TownWorld._update_kid_visibility` already hides a child in another space.
- **The zoo sleeps when empty.** The authority simulates the zoo only while a child is there. When the first arrives, the animals start fresh at their home spots. The dedicated server pays nothing for an empty zoo.
- **Only those in the zoo hear about it.** Animal states go to the peers whose place is the zoo; an arriving peer gets the whole picture first.
- **Invitations.** `Invites.KINDS` gets "Come to the zoo with me". The card already carries a space and a spot (`Invites.card`); **Join** rides the tram and then walks toward the friend (`PlayController.travel_to` learns the journey).
- The four-player limit, preset names and the rest of [multiplayer.md](../docs/multiplayer.md) are unchanged.

### 12.6 What is saved

| Saved with the town | Not saved |
|---|---|
| Things placed in the zoo: ordinary items with `"space": "zoo"` | The animals, where they are, what they were doing |
| The tram stop: an ordinary town item | Where each player is |
| `maps`: `{"zoo": {"found": {species: {answer: {"by": [names], "t": time}}}}}`, written only when not empty | Balls in play, station timers, the full-and-happy counter |

One file, one welcome. A full zoo adds about 16 kB to the welcome (80 things at about 200 bytes), far inside the 3 MiB limit that `test_welcome_bound` guards. On Apple TV the solo town's checked copy has 176 KiB (`game/scripts/core/durable.gd` `FILES`); a full zoo adds a few kilobytes when deflated.

If later maps make one welcome too big, the registry is where per-map snapshots would attach. Not needed now.

### 12.7 Save schema and network protocol

- **Save schema stays 2.** The additions are optional and loaded tolerantly, like `echoes` and a board's `pix`. A town without a zoo saves exactly as before, apart from the tram stop.
- **Old saves in the new build:** load unchanged; the tram stop is added at a free spot; nothing moves.
- **New saves in an old build:** zoo things, the stop and `maps` are dropped on load and gone after its next save; the town is intact. That is how every earlier optional addition behaves.
- **Why not schema 3.** `Session._load_town` falls back to the backup and then to a new default town when `from_dict` refuses a schema, and marks it for saving. An older app given a schema-3 file would replace that town after two saves. Until that is hardened (section 20), a bump is a risk with no benefit here. The paused R21 branch also claims schema 3.
- **Protocol 13 → 14.** New requests in `rq_action`: `travel` (1 argument), `zoo_offer` (1: an animal or a treat table), `zoo_use` (1: a station). A new autoload `Zoo` with its own events: animal states (unreliable, to those in the zoo), a snapshot on arrival, the lines over animals, one-shot effects. `ev_town_data` learns the key `maps`. Apps and the town server update together, as for 11, 12 and 13, which are also unreleased; the installed apps and the HK server are on 10.
- Phase 2 appends species, which changes the packed states: protocol 15.

## 13. Solo, friends, authority, persistence

| Rule | How |
|---|---|
| Solo is complete | Every signature, treat, station and toy works with one child |
| Friends add, never gate | The "with a friend" column of section 10.5 is extra |
| No forced group travel | Each child rides alone; friends can be in town and zoo at once |
| Come to me | An invitation brings a friend to the inviter's map |
| One authority | The solo device, the host or the server runs the zoo's brain and decides every answer: a treat needs the child within 3.5 m on that map; a station within 2.2 m and rested; toys follow the model's placement rules |
| Fair turns | Two treats at once are served in order; group species share; the nearest free animal answers a station |
| Never trapped | Animals keep clear of children; a large animal at rest steps back when a child walks into it; the way home is always on screen |
| What stays | Toys and the discovery log. Animals start fresh when the zoo wakes |
| Kind by design | No animal is ever hungry, sad, angry or hunting. A startle is a cute step back and a peek |

## 14. Assets

### 14.1 Animals and things

Everything is original code, under the project's own terms like every code-built thing ([assets.md](../docs/assets.md)). No asset file is added in Phase 1 except rebuilt font subsets.

| Asset | Built in | Triangles | Draw calls |
|---|---|---|---|
| Lion, lioness, tiger, zebra, hippo | `zoo_animal.gd` on `zoo_rig.gd` | at most 10 000 each | at most 18 each |
| Giraffe | same, with a neck chain | at most 11 000 | at most 20 |
| Monkey, otter | same, climber plan | at most 9 000 each | at most 16 each |
| Zoo toys (six) | `props_zoo.gd` | at most 1 500 each | 1 to 3 |
| Stations (eleven) | `props_zoo.gd` | at most 3 000 each | 1 to 4 |
| A hill's rock, a zone's scenery | `zoo_world.gd`, merged | at most 30 000 per zone | at most 12 per zone |
| Tram stop | `props_zoo.gd` | at most 4 000 | 2 |
| Textures | none | | |

Small parts use spheres with fewer rings (`Kit.sphere(radius, rings)`); a default sphere is 576 triangles, which is why today's animals are about 7 000 each.

Sounds are synthesized tones in `game/scripts/autoload/sfx.gd`, as now: a tram bell, a soft "rawr", a hoot, a chomp, a whoosh. No recordings. The music is the existing loop at the town's level; a zoo tune of its own (from `scripts/compose_music.py`) is a later option.

### 14.2 What the Mac validates (dual-host)

By [dual-host-modeling.md](../docs/dual-host-modeling.md), each sealed candidate:

1. Import with the pinned 4.7.2 build, and with the 4.8-dev tvOS engine for the TV.
2. A **zoo gallery** scene: six views of every species and thing, and a **lineup** at the game camera with the child and a town animal beside each species.
3. **Game-camera captures** at the four layouts, near and wide zoom, from every viewing bay, with each signature under way.
4. The zoo tour rendered in six languages by touch, and by controller at the TV layout with the outside-pointer guard; Metal twice for the TV.
5. The performance probe on a real GPU.
6. The existing regressions (unit suite, real-client suites, the other tours).

The owner opens the originals and names the views inspected. A species' look is accepted from these renders, within the existing style; the user's own review follows. Device builds and a child come after.

## 15. Performance budgets

No frame rate has been measured on a device for this game; the portable numbers are draw calls and triangles (`game/tests/perf_probe.gd`). The default town measures 72 to 89 draw calls and 0.30 to 0.36 million triangles ([validation.md](../docs/validation.md)).

| Budget | Limit | Where measured |
|---|---|---|
| Draw calls, worst zoo view (Monkey Court, wide zoom, four children with pets) | 240 | Headless counts and the Mac's GPU |
| Triangles per frame, worst zoo view | 0.50 million | same |
| Animals drawn | Only those within 30 m of a child on this device; the others are hidden and their rigs not updated | Unit test |
| Particles alive in the zoo | 300 | Unit count |
| Zoo brain | 0.5 ms per 0.1 s step for 24 animals and four children | Headless timing on EC2 |
| Network, per child in the zoo | 2 kB/s | Real-client test |
| Journey | 2.5 s at the 95th percentile; first build of the zoo under 1.5 s | Mac and devices |
| Frame rate | 60 on iPad Air 5 and Apple TV 4K; never under 30 on the user's iPhone | Devices only |

The weakest target is not known: the export allows iOS 15, and the user's iPhone model is not in the documents read. If the articulated rigs cost too many draw calls, the fallback is to merge both segments of the limbs of animals beyond 12 m, or to give them single-segment limbs at that distance.

## 16. Controls, accessibility, languages

### 16.1 Controls

| Action | Touch | Controller |
|---|---|---|
| Walk | Tap the ground | Left stick |
| Ride, use a station, offer at a table | The action button, or tap the thing | **X** |
| Look at an animal | Tap it | Pointer (right stick) and **A** |
| On the Look strip | Its buttons | **X** for Offer a treat; D-pad or pointer and **A** for the others; **B** for Done |
| Emotes | The four buttons | Pointer and **A**, or D-pad to them |
| Camera | Rotate and zoom buttons, pinch | **L** / **R**, **ZL** / **ZR** |
| Place a toy | Decorate, drag, **Place here** | Pointer and **A**, left stick, **Y** turns, **+** places, **B** cancels |
| Ride home | At the station, or the button at the top | **X**; pointer and **A** |

No new button and no new mapping. During the journey card the controller acts on nothing. The hints name **X** for the action in reach, as now. The Siri Remote's Menu keeps its meaning: back one step, and from the zoo with nothing open, to the title.

### 16.2 Accessibility

- **Reduce motion** (the existing setting, `DecoMotion.load_reduce`): a still journey card, no glide into Look, smaller splashes, the tram's sway off. The animals keep moving; they are the content.
- Never by color alone: species differ by shape; an answer is always a move, a line of text and a sound.
- Nothing is timed, nothing flashes, nothing can be failed. Sounds are soft; the roar is a friendly "rawr".
- Every core action works with taps alone, and with one controller alone.
- Tapping an animal uses its projected box, never less than 44 px (today `TownWorld.pick_animal` uses a fixed 60 px circle at 0.4 m, too low for a 1.5 m lion).

### 16.3 Languages

About 150 new English strings in Phase 1 (places, the journey, fourteen names, lines over animals, stations, toys, the strip, messages, the guide card, the scrapbook page), each in exactly en, zh-CN, ja, es, fr and de. `scripts/extract_strings.py` and `scripts/build_fonts.py` run; `scripts/check.py` checks completeness and glyphs. Names follow the rule from `first-steps` r5 (no space between a name and Chinese words). The strip and the action button are checked for fit in six languages at four layouts; German and French are the long ones.

## 17. The first ten minutes, and coming back

### 17.1 Ten minutes

| Minute | What happens |
|---|---|
| 0 to 1 | In town the tram stop is on screen, with its tag and one line of text. Tap it, **Ride to the zoo**, the journey card, the platform |
| 1 to 3 | Through the plaza into the savanna. Running makes the zebras gallop alongside. Standing still by Topper brings the head down |
| 3 to 5 | Lion Hill. A wave at the overlook, a cheer for the roar, a walk up Lion's Pass with Rory pacing beside |
| 5 to 7 | Monkey Hill. The troop copies a dance. A walk up Canopy Lane with monkeys swinging alongside. **Ring the bell** |
| 7 to 8 | Tiger Hill. Stand still at the thicket for the peek. **Float a ball** for the leap |
| 8 to 9 | A Play ball placed on Lion Hill: the first creation, and the pounce |
| 9 to 10 | A photo, then **Ride home**. The ball stays for next time |

Six or more different answers, one creation, one photo, a safe return. Nothing asks for any of it and nothing is timed.

### 17.2 Reasons to come back, without rewards

- Answers not yet seen, hinted in the scrapbook.
- Toys change where animals go and what they do: move the leaf feeder and the giraffe follows.
- Friends: the "with a friend" answers, photos of each other, stories with large animals.
- What the children left is still there.
- Later: weather and evening answers, cubs, four more species.

## 18. Reused, new, deferred

### 18.1 Reused as it is

Placement, move, turn, paint, Undo, locks and the toy box; emotes and story poses; the camera, photos and story strips; the scrapbook; pets following; invitations; the line over an animal and its ring; the behaviour-table pattern of `town_life.gd`; the brain pattern of `animal_brain.gd` (pure, seeded, fixed step, packed states); the placement tools' places and the step-aside rule; landmark name tags; the guide's cards; the first-steps line; evening and weather; synthesized sounds; the controller layer.

### 18.2 New shared systems

| System | Reusable for |
|---|---|
| `Places` registry | Every later map |
| Journey (request, card, failure handling) | Every later map |
| Per-map saved state (`maps`) | Every later map |
| Players' places across maps (the travel rule, chips, invitations) | Every later map |
| The stop's destination board | The second destination onward |
| Zoo rig (two-segment limbs, reach, pendulum, arcs) | Any later creature; a later pass on town animals |
| Routes that animals follow on structures | The treehouse forest idea |
| Stations and the zoo behaviour table | Any map with responsive animals |
| Look framing | The town's animals, as a later option |

### 18.3 The reference's ideas

| Idea | Decision |
|---|---|
| Observation first, a little care and building | Adopted |
| A tram stop and a shared plaza | Adopted; the stop stands near the arrival point, not at the edge (section 9.1) |
| Three zones, three species | Superseded by the user: five zones, seven species in Phase 1 |
| Alpaca, otter, red panda examples | Otter in Phase 1, red panda in Phase 2, alpaca in the later pool |
| Toys bring animals; move toys to change behaviour | Adopted |
| Splash makes a neighbour step back; a bell makes an animal peek | Adopted as reactions between animals and as the monkeys' bell |
| Food without hunger | Adopted as treats |
| Water bowls, cleaning, tidying toys | Rejected: chores |
| One friend places, another photographs | Adopted |
| Hide-and-seek and role play in the zoo | Deferred; the story strip and poses work now |
| Benches, signs, small toys left behind | Adopted |
| Photo walls | Deferred; the paused R21 photo wall owns that ground |
| Links to home (photo displays, animal toys at home) | Deferred to Phase 3 |
| Weather changes answers | Phase 2, apart from the lions' den |
| No check-ins, task lists or numbers | Adopted as rules |
| Independent maps, invitations, pets follow or wait, failed loading keeps the origin | Adopted |
| Seamless world, ecosystems, terrain editing, continuous transport | Rejected |

### 18.4 The nine destinations

| Destination | Now | What it would reuse |
|---|---|---|
| 1. Zoo | This design | — |
| 2. Tidal bay (channels, flowing water) | Deferred; the farthest, it needs terrain and water | Places, journey |
| 3. Treehouse forest (bridges, squirrels use routes) | Deferred; a strong second | Routes, the zoo rig, placement |
| 4. Toy railway valley | Deferred; likely the cheapest next | Cart rails and track rules, places, journey |
| 5. Stargazing observatory | Deferred | Evening, places |
| 6. Fairytale theater | Deferred | The Little Theater kit, story poses |
| 7. Kite plateau (wind) | Deferred | Places; new wind play |
| 8. Curious toy workshop (chain reactions) | Deferred | Contraptions |
| 9. Raincloud garden (local rain opens flowers) | Deferred | Weather, garden growth |

A rule for all of them, adopted from the reference: each map has its own verb. None becomes a hunt for items.

## 19. Phases and acceptance

Three kinds of evidence are kept apart, as in the [experience plan](experience-plan.md): function (EC2 can test headless), look (only the Mac's renders) and feel (only a device and a person).

### 19.1 Phase 1A: the Lion Hill slice (first)

Recommended by the coordinator and adopted: it tests the one thing EC2 cannot, how large code-built animals read at the real camera in the existing style, before seven species are built on a guess.

**Contains:** a minimal registry and a `zoo` space; the zoo's ground with Lion Hill at 24 × 18 m; the rig; Rory and Honey with bask, ridge patrol, survey, yawn, roar on a cheer, nod on a wave, pacing beside a child on Lion's Pass, and stalk, pounce and flop on a Play ball; the Play ball and the garden umbrella placeable there. Solo only, entered by a developer start argument; not offered to players and not released by itself.

| Acceptance | How | Where |
|---|---|---|
| The footprint and height tables of section 5 hold | `test_camera_footprint`, `test_height_budget` | EC2 |
| Lion Hill cannot lie inside one screen at any turn on any layout | `test_hill_larger_than_screen` | EC2 |
| Every show spot is inside the height budget from its bay | `test_show_spots_visible` | EC2 |
| Rory is at least 150 px tall and 260 px long, eyes at least 16 px, at the near zoom | `test_species_readability` | EC2 |
| Style check passes: no textures, matte only | `test_zoo_style_lint` | EC2 |
| Hands and paws land within 2 cm of their targets | `test_zoo_rig_reach` | EC2 |
| The lions never leave the island, never stand in a thing, and each answer fires from its trigger | `test_zoo_brain_lion` | EC2 |
| The slice works by touch and by controller | `zoo_slice_tour.gd`, headless | EC2 |
| Captures at four layouts, near and wide, from the three bays; the lineup with child, pig and elephant | The same tour, rendered | Mac |
| The lion reads as a lion, in the game's own style | The owner on the originals; later the user | Mac, then user |

**Outcome recorded in this document by the owner:** the scale classes confirmed or changed (up to 15 %), eye and marking sizes, colors, whether two-segment legs earn their draw calls, and any change to rules H1 to H4. Work on 1B continues meanwhile.

### 19.2 Phase 1B: journeys

**Contains:** the full registry and the audit; the tram stop in every town; `travel`, the journey card and its failures; **Ride home**; protocol 14; `maps`; chips and invitations; the companions' rules; the whole zoo ground with the plaza, the station and Lion Hill live.

| Acceptance | How | Where |
|---|---|---|
| No stray `"town"` literal; a zoo is never taken for a room | `test_space_kinds` | EC2 |
| An old save loads unchanged, gains one tram stop and moves nothing; a town saves as before apart from the stop | `test_old_save_gets_stop` | EC2 |
| The stop cannot be put away, wrapped or doubled; it returns if missing | `test_stop_rules` | EC2 |
| Zoo things and the discovery log survive a save and a restart; a damaged `maps` is dropped, not fatal | `test_zoo_save_roundtrip` | EC2 |
| A stale movement packet cannot change a player's map | `test_travel_authority` | EC2 |
| Every failure of section 12.4 leaves the child at the origin with a retry | `test_journey_failures` | EC2 |
| Two real clients on different maps; an invitation and Join; a late joiner; a connection dropped mid-journey; a server restart keeps the toys | `net_test.py --zoo` | EC2 |
| The welcome and the TV's checked copy stay inside their limits with a full zoo | `test_welcome_bound`, `test_tv_durable` | EC2 |
| There and back by touch and by controller, six languages | `zoo_tour.gd`, headless | EC2 |
| The card, the stop in town, the station | Rendered | Mac |
| The journey takes under 2.5 s; it feels like a ride | | Device, a person |

### 19.3 Phase 1C: Tiger Hill and Monkey Hill

**Contains:** the tiger; five monkeys with routes, rings, vines, poles, leaps and the copycat; their stations and treat tables; Look framing and its strip.

| Acceptance | How | Where |
|---|---|---|
| Both hills pass the screen and height tests | as 1A | EC2 |
| A monkey is always on a route element or the ground, at that element's height | `test_zoo_routes` | EC2 |
| With a child on the hill, at least two monkeys are in a moving action in every second of a 240 s run; none within 8 m sits still over 6 s | `test_monkeys_lively` | EC2 |
| Every emote is copied within a second; the Ring Run race starts from walking the lane; the bell starts the climb | `test_zoo_brain_monkey` | EC2 |
| Lion and tiger differ: each of the five paired triggers (cheer, ball, box, treat, standing still) gives a different action | `test_cats_differ` | EC2 |
| With Look on, head and child are whole and under no control, six languages, four layouts | `zoo_look_tour.gd`, headless | EC2 |
| Climbing, swinging and jumping read; hands look as if they hold | Rendered sequences | Mac, then user |
| The worst view stays inside the draw-call and triangle budgets | `perf_probe.gd` for the zoo | EC2 counts, Mac GPU |

### 19.4 Phase 1D: Savanna, Splash Bay, making and finish

**Contains:** giraffe, zebras, hippo, otters; the six toys and the Picnic tab; the scrapbook page; four zoo photo ideas; the guide card and the one-time line; evening and weather in the zoo; the performance pass. This ends the first delivery to the user.

| Acceptance | How | Where |
|---|---|---|
| Every species has its treat, signature and emote answers; every zone has a reaction between animals | `test_zoo_roster_contract` | EC2 |
| Every toy brings the listed answers; a moved toy moves the answer | `test_zoo_toys` | EC2 |
| The zoo brain never edits a saved thing | `test_zoo_brain_readonly` | EC2 |
| An answer is logged once with the names nearby; hints show for the rest | `test_zoo_found_log` | EC2 |
| The ten-minute path by touch and by controller, six languages, no text cut | `zoo_tour.gd` | EC2 headless, Mac rendered |
| All budgets of section 15 that are not device-only | | EC2, Mac |
| Frame rate, touch, sound, a child's ten minutes | | Devices, the user |

### 19.5 Later phases

- **Phase 2:** Bamboo Grove and Snowy Cove with four species; cubs; answers to weather and evening; toys for two; contraptions that set stations off; raised lookouts if accepted; the town animals' decision (section 4.3). Protocol 15.
- **Phase 3:** children shaping habitats; species from the pool; links to home; a second destination on the same registry and journey.

### 19.6 What EC2 cannot verify

How anything looks; whether a species reads; z-fighting and transparency; Metal and the 4.8-dev tvOS engine; frame rates; touch; the controller on a real Apple TV; sound; the comfort of Look; whether a child finds the tram and understands the answers. None of these may be reported as passed from a headless run.

## 20. Implementation map

### New files

| File | Holds |
|---|---|
| `game/scripts/core/places.gd` | The registry (section 12.1) |
| `game/scripts/core/zoo_map.gd` | Zones, terraces with heights, blockers, bays, show spots, stations, routes, arrival points |
| `game/scripts/core/zoo_life.gd` | Species data, triggers and answers, toy attractions, reactions between animals, the lines |
| `game/scripts/core/zoo_brain.gd` | The pure, seeded simulation |
| `game/scripts/net/zoo.gd` | Autoload `Zoo`: runs the brain on the authority, sends to those in the zoo, handles offers and stations |
| `game/scripts/art/zoo_rig.gd` | Pivot plans, pose easing, two-bone reach, pendulum, arcs |
| `game/scripts/art/zoo_animal.gd` | Builders and poses per species |
| `game/scripts/art/props_zoo.gd` | The tram stop, toys, stations, structures |
| `game/scripts/world/zoo_world.gd` | Ground, hills, water, animals, effects, hiding what is far |
| `game/scripts/world/journey.gd`, `game/scripts/ui/journey_card.gd` | The journey's steps and its card |
| `game/scripts/ui/look_strip.gd` | The strip of an animal being looked at |
| `game/tests/zoo_tests.gd`, `zoo_slice_tour.gd`, `zoo_tour.gd`, `zoo_look_tour.gd`, `zoo_gallery.gd` with its scene | Tests and the Mac's render drivers |

### Changed files

| File | Change |
|---|---|
| `game/scripts/core/town_model.gd` | `is_space`, `validate`, caps and blockers through the registry; `maps` in `to_dict`, `from_dict`, `_load_activities`; the stop's rules and `ensure` on load |
| `game/scripts/core/catalog.gd`, `room_themes.gd` | Zoo kinds; `allowed_in` through the registry; the Zoo and Picnic tabs with an idea line |
| `game/scripts/net/session.gd` | `PROTOCOL` 14; `travel`, `zoo_offer`, `zoo_use` in the whitelist; `_srv_travel`; the map rule in `_srv_state`; leaving and disconnect clean-up; `maps` in `ev_town_data`; the stop in `_srv_remove` and `_srv_wrap` |
| `game/scripts/net/animals.gd` | A visit ends at boarding |
| `game/scripts/core/invites.gd`, `photo_ideas.gd`, `blueprints.gd` | The zoo invitation; zoo photo ideas; the stop kept out of blueprints |
| `game/scripts/world/town_world.gd` | `set_view` for maps; `resolve_walk`, `pick_animal` and `photo_facts` for the zoo; evening and weather there |
| `game/scripts/world/activity_world.gd` | Weather drawn for the map on screen |
| `game/scripts/world/play_controller.gd` | Stop, station and Look contexts; `travel_to` and the journey; `_on_view_changed`; taps on zoo animals |
| `game/scripts/world/camera_rig.gd` | The Look focus as a new goal; nothing else. `PITCH`, `FOV` and `ZOOMS` are not touched |
| `game/scripts/ui/hud.gd` | Place name and Ride home; chips; zoo tabs; what hides in the zoo; the strip's place; the guide card's action; the scrapbook page; the one-time line |
| `game/scripts/ui/pad_input.gd` | The strip among its targets; nothing acts under the journey card |
| `game/scripts/ui/activity_guide.gd`, `guide_art.gd` | The card "The zoo" and its picture |
| `game/scripts/main.gd`, `autoload/music.gd`, `autoload/sfx.gd` | Music context from the registry; new tones; the slice's start argument |
| `game/project.godot` | The `Zoo` autoload |
| `game/locale/*.json`, the two CJK font subsets | New strings |
| `game/tests/run_tests.gd`, `net_bot.gd`, `perf_probe.gd`, `scripts/net_test.py`, `scripts/test_all.sh` | New and extended checks |
| Documents, by the standing rule of [CONTRIBUTING.md](../CONTRIBUTING.md) | README, HANDOFF, game-design, animals, multiplayer, requirements, validation, assets, the scale contract (animal classes), tv-controller |

## 21. Open questions and risks

Each has a recommended default. None blocks the work.

| # | Question or risk | Default |
|---|---|---|
| 1 | The entrance: a movable stop near the arrival point, or a fixed station beyond the north edge? The fixed one needs walkable ground outside `TOWN_HALF`, trees removed from the scenery ring there, and things standing in its mouth moved on load; and it is on screen only when walked to | The movable stop |
| 2 | The size of the lion (and with it every class) is a guess until rendered | 1.55 m; the slice may change it by up to 15 % |
| 3 | On a phone, eyes are about 1 mm even at the new scale | Accept; raise the scale class before ever touching the camera |
| 4 | Resizing the town's animals | Not in Phase 1; decide after devices (section 4.3) |
| 5 | The giraffe's head leaves the frame beyond the child at the near zoom | 2.8 m, a lowered head near children, the bow; if the slice's evidence argues for it, 2.6 m |
| 6 | Children on raised lookouts would need a height for the child, for taps and for friends | Ground-level bays in Phase 1; a small height function in Phase 2 if wanted |
| 7 | Look framing moves the focus by itself after a tap | Keep, focus only; if the user sees it as a camera change, drop it and keep the strip |
| 8 | Does the rule against reptiles, insects and frightening animals cover the zoo? | Yes |
| 9 | Lions and tigers next to children | Friendly, never hunting, never chasing a child; the tiger's stalk is a game it plays with a ball, a box or beside a child |
| 10 | Save schema | Stay at 2. Separately, harden `_load_town` so a save from a newer app is set aside and reported, never replaced |
| 11 | Protocol numbers and the paused R21 branch | The zoo takes 14; R21 takes the next free ones when it resumes |
| 12 | The zoo sleeps when empty, so animals start fresh | Accept; it keeps the server idle and the simulation simple |
| 13 | A player's place is not remembered between sessions | Accept; every session starts in town |
| 14 | Journeys from the guide and from an invitation start anywhere, so the stop is the main way but not the only one | Accept, for reliability without path finding |
| 15 | Articulated rigs raise draw calls (up to 18 per animal) | Budget 240; fall back to merged limbs for far animals |
| 16 | Four updates a second may look late on the Ring Run | Draw swings locally; eight a second for that hill only if renders show it |
| 17 | Sounds are tones; a zoo may want more | Tones in Phase 1; nobody has heard any of the game's audio on EC2 |
| 18 | Names, and whether each individual needs one | Fourteen names as proposed, for the creator to change |
| 19 | "On display", presents, blueprints and contraptions are off in the zoo | Off in Phase 1; contraptions with stations in Phase 2 |
| 20 | The user's iPhone model and every real frame rate are unknown | Measure on the first device build; the portable budgets stand until then |
| 21 | Behaviour on the 4.8-dev tvOS engine | The Mac's gate, as for every TV candidate |

Not verified while reading; the owner should confirm:

- that `game/scripts/world/echo_world.gd`, `game/scripts/core/echoes.gd` (`near`, `sanitize`) and `game/scripts/core/contraptions.gd` treat a space as an opaque string, so hellos work in the zoo and contraptions can follow in Phase 2;
- that `game/scripts/ui/thumbnails.gd` renders pictures for new catalog kinds by itself;
- that a catalog kind can be kept out of every toy box tab, including All (`Catalog.kinds_for`, `Hud.current_kinds`);
- that `PlacementDock.choose_place` and `CameraRig.frame_fit` can be given an animal's box without change;
- that hiding far animals by `visible` is enough on the Compatibility renderer, or whether visibility ranges are wanted;
- that `HideSeek.warmth_level` and `Activities` need no change once hide-and-seek cannot start in the zoo;
- the proposed catalog sizes against the size-class ranges of `test_scale_contract`.

## 22. Owner review and amendments (2026-11-15)

By the production owner (the EC2 Opus session), after reading sections 1 to 21 against the code. Where this section and an earlier one differ, this section wins.

### 22.1 Provenance

- **Who wrote it:** the design planner, launched by the owner through the Agent tool with model `fable` and effort `xhigh`, as the user asked.
- **How the run ended:** the planner wrote sections 1 to 21, then stopped on a Fable usage limit (HTTP 429, request `req_011Ch4vzaLYiVxwizA6JSoMB`) before it could send its final report. That error names the model sent to the API: `claude-fable-5-2`. The effort setting comes from the launch request; the planner never echoed it back.
- **What arrived late:** the user's Monkey Hill priority was sent after the planner had stopped receiving messages, so it is not in sections 1 to 21. It is added in 22.4.

### 22.2 Facts checked against the code

| Claim | Result |
|---|---|
| `Session.PROTOCOL` is 13 and `TownModel.SCHEMA` is 2 | Confirmed (`session.gd:42`, `town_model.gd:17`) |
| `TOWN_HALF` is 26 × 22; the caps are 300 things in town and 40 in a room | Confirmed |
| Spaces are a town-plus-rooms switch, not a map framework | Confirmed: `is_space`, `validate`, `set_view`, `resolve_walk` |
| `pick_animal` works in town only, aims at a fixed point 0.4 m up and reaches 60 px | Confirmed (`town_world.gd:875`) |
| The `"town"` literal: 214 uses in 28 files | **Corrected:** 207 uses in 28 files on the current tree. The audit method (section 12.2) is unchanged |
| "The installed apps and the HK server are on 10" (section 12.7) | **Possibly out of date.** The Mac coordinator reports that first-steps r12 was published on iPad, Apple TV and HK on 2026-11-15. `docs/release-status.md` in this tree does not record that yet, so the owner does not rely on either number. What stands: the zoo needs a new protocol number, and apps and server must update together |
| The camera numbers in section 5 | Not yet pinned. A unit test re-derives them from `CameraRig` before any habitat size is final (Phase 1A) |

### 22.3 Decisions adopted as written

These are adopted:
- the art and camera constraints (4.1);
- the zoo scale classes and on-screen targets (6.1, 6.2) as starting values, to be calibrated on the Lion Hill slice;
- the code-built rig (7.1);
- the hill sizes (5.4, 8.2 to 8.4);
- the movable tram stop near the arrival point (9.1);
- the registry, travel and failure rules (12);
- schema 2 with optional keys, and a new protocol (12.7);
- the phase order 1A → 1B → 1C → 1D.

The open-question defaults in section 21 are accepted, except where 22.4 or 22.5 changes them.

### 22.4 Amendment: Monkey Hill is a priority (user, 2026-11-15)

**Phase.** The monkeys move up. In the build order they come right after the Lion Hill slice, before the tiger, so that Monkey Hill gets the most iteration. Section 7.2 and the rows for Monkey Hill stay; this section adds to them.

**Repertoire.** Every action is a whole-body action with a readable key pose; no gesture is smaller than the limits of section 4.2. The first build has at least twelve distinct autonomous actions, each built from anchors on Monkey Hill:

| Action | From → to | Key read |
|---|---|---|
| Climb a pole | ground → platform | Arms and legs alternate reaching up |
| Climb down head first, then flip | platform → ground | The body inverted, the tail up |
| Swing along the rings | ring → ring | A pendulum, one arm raised |
| Vine swing with a release | vine → a safe perch | A full arc, the release at the peak, a tucked flight, a squash landing |
| Leap between platforms | platform → platform | Crouch, stretch, tuck, land |
| Hop across rocks | rock → rock → rock | A chain of short hops |
| Balance walk | along the Net Bridge or a beam | Arms out, the tail as counterweight, a wobble |
| Hang by the tail | a branch | Upside down, arms swinging |
| Peek | from behind a post or ledge | The head appears, the ears perk, the head hides again |
| Sit and dangle the legs | a platform edge | Legs swing, the head turns to look around |
| Play with an object | a ball or banana at an anchor | Toss and catch, roll, hold up to show |
| Spin or somersault | ground or platform | A full turn of the body |

**Play between monkeys.** These are sequences for two or three monkeys:
- chase and tag across the court and up a tower;
- follow-the-leader along the same route, a beat behind;
- grooming on the hammock or a platform;
- passing a ball or banana from hand to hand, or tossing it to a monkey on the next platform;
- a youngster riding on an adult's back.

**Choosing actions (in `zoo_brain.gd`, on the authority).**
- Each monkey picks its next action from a weighted table, keyed by where it is (ground, pole, platform, ring, vine, rock) and by what is near it (a child, another monkey, a toy).
- Cooldowns:
  - each action has its own cooldown per monkey, 20 to 60 s;
  - the same action cannot be picked twice in a row by one monkey;
  - a troop-wide cooldown stops the same action starting on two monkeys within 3 s, except in follow-the-leader and copycat, which are meant to match.
- A sequence may only start at a valid anchor and end at a valid anchor (a perch, ring, vine seat, rock top, ledge or ground spot), and an anchor holds one monkey at a time. Motion therefore stays spatially coherent: no landing in the air, no two monkeys on one perch, no sliding.
- Rests are short (2 to 6 s), with small motions (looking around, scratching, swinging the tail), so the troop is lively without being constant chaos. At most three of the five are in a big move at once.
- Each monkey's timing is offset by its own random phase, so no two run the same loop in step.
- Player answers (the copycat, walking the lane, the bell, the treat, the tyre swing) interrupt the table. They do not replace it.

**Multiplayer.** The authority chooses every action and sends it with its anchors (start anchor, end anchor, start time) in the zoo's state events. Clients draw the arcs and swings from that, so every device shows the same monkey on the same vine at the same moment. Clients never roll their own random choices.

**Reduce Motion.** The monkeys keep playing, because they are the content, but:
- the vine arc drops from 50° to 25°;
- releases and somersaults become a hop to the next perch;
- leaps are slower (0.75 times as fast);
- the troop limit for big moves drops to two;
- the copycat ripple happens in place.

**Acceptance (EC2, headless, deterministic seeds).**

| Check | Threshold | Test |
|---|---|---|
| Variety | A 240 s run with a child on the hill and no input shows at least 10 distinct autonomous actions; no monkey repeats an action back to back | `test_monkey_repertoire` |
| Spontaneous start | With no input, a monkey within 10 m of the child starts a big move within 8 s of the child arriving, and at least every 10 s after | `test_monkey_spontaneous` |
| Ambient life, with real pauses | In at least 80 % of the 10 s windows a big move starts within the child's default view. Any single monkey may rest for up to 12 s; the whole troop is never at rest for more than 8 s. At most three monkeys are in a big move at once (two with Reduce Motion) | `test_monkeys_lively`. This **replaces** section 7.2's rule ("two always moving, no stillness over 6 s"), which would have forced constant motion and synchronized fidgeting |
| Coherence | Every action starts and ends on a valid anchor; no anchor holds two monkeys; no position jumps more than an action's own path allows | `test_zoo_routes` |
| Social play | At least two social sequences (chase, follow, groom, pass) in the 240 s run | `test_monkey_social` |
| Not in step | No two monkeys start the same action within 3 s outside follow-the-leader and copycat | `test_monkey_desync` |
| Readable | Every big move displaces the body by at least 0.8 m or turns it by at least 90°, and every key pose changes the silhouette box by at least 20 %, both measured on the built rig | `test_monkey_legible` |
| Reduce Motion | The same run shows the same set of action families, with the reduced amplitudes above | `test_monkey_reduce_motion` |
| Same on every client | Two real clients log the same action, anchor and start time for each monkey | `net_test.py --zoo` |
| Looks lively and reads at the normal camera | Rendered sequences at the four layouts | Mac, then the user |

### 22.5 Coordinator review findings, resolved (2026-11-15)

1. **Monkey liveliness rule.** Section 7.2's "at least two always moving, none still over 6 s" is withdrawn. The repertoire, weighted choice, cooldowns, real pauses, desynchronisation and the ambient-life test of 22.4 replace it. Monkey Hill stays the top priority after the slice.

2. **Readability where animals actually stand, not at the child's position.**
   - Section 6.2 projects an animal standing at the child's position. That is an ideal case. The binding check, `test_readability_in_place`, measures each species instead:
     - at each of its real show spots and resting spots, at the terrain height of that spot;
     - from each viewing bay and from the nearest point on the walking path;
     - at all eight camera turns, both zooms and the four layouts;
     - in normal walking view, without Look.
   - It reports the projected height, length and eye width per pose. The worst case counts, not the best.
   - **Visibility depends on the pose, honestly.** Each species declares its poses and the share of time it holds each one while a child is within 10 m. T1 to T6 must hold for every pose held for 20 % or more of that time. A lower pose may show smaller, and the test reports it as such.
   - **The otter is resized.** On all fours it was 0.6 m, which fails T1 (about 64 px). It is enlarged so that on all fours it reaches at least 0.85 m with its head up, and it is 1.30 m standing upright. Near children its weights favour standing upright, floating with the head up, or holding a pebble up. If the slice's renders show it still reads too small, it moves to the zoo medium class.
   - **Raised and far spots.** An animal on a 1.0 m terrace, 6 m beyond a bay, is measured where it stands. If a spot fails its targets, the spot moves closer or lower; the camera does not change.

3. **Ring Run geometry.**
   - The section 8.4 figures contradict each other. With hands at 2.6 m and a hanging monkey 1.9 m tall, the feet hang at about 0.7 m, so they could not clear a 1.3 m child.
   - Resolved by keeping the route to one side, not by raising it:
     - the Ring Run's beam runs parallel to Canopy Lane, its centre line 2.5 m from the lane's edge;
     - the strip under it, 1.6 m wide, is a blocked low planting (a `resolve_walk` box), so a child can never walk beneath it;
     - the claim "feet clear a child's head" is withdrawn.
   - The hanging pose is tightened: hands at 2.7 m, a hang length of 1.55 m with the knees tucked, so the feet are at about 1.15 m. The monkey reads as hanging above the ground beside the child.
   - The same rule covers the vines, the tyre swing and the Net Bridge: no route runs over a walkable cell.
   - `test_routes_clear_of_paths` checks that no route segment's swept volume overlaps a cell where a child can walk.

4. **Save schema and rollback.** Section 12.7's plan (stay at schema 2 and let older apps drop zoo data on load) is **withdrawn**. CONTRIBUTING requires a schema bump, a migration and a test. The resolution:
   - **Bump `TownModel.SCHEMA` to 3**, with the migration 2 → 3. Zoo items, the tram stop and the `maps` key are first-class. The migration leaves the town's contents unchanged and adds the stop. It is tested by `test_schema3_migration`, using real schema-1 and schema-2 fixtures.
   - **Keep the untouched original.** The existing `.v1` rule (`Session._load_town`) is extended: on the first migration, the original schema-2 file is copied to `town.json.v2` and never written again.
   - **Make a rollback safe for the town.** An older installed app reads only the main file and `.bak`. When a newer schema refuses both, it starts a new default town and would save it over the old one (the path in `_load_town`). From schema 3 on, `save_now` therefore writes `.bak` as a **schema-2 projection** of the town: everything except zoo items and `maps`. An older app then falls back to an intact town.
   - **Get the zoo back after a downgrade and re-upgrade.** Each save also writes a sidecar, `town.json.maps`, holding the zoo items and `maps`. When the new app loads a main file that is schema 2 and finds this sidecar, it merges the zoo back, remapping any ids already in use, and logs it.
   - Tested by `test_rollback_old_reader` (a reader frozen at schema-2 rules accepts `.bak` and keeps every town item) and `test_downgrade_roundtrip` (no zoo item lost on the way down and back).
   - **The Apple TV checked copy** (`Durable.mirror`) follows the same files.
   - **The server.** The HK server keeps its own save. A server running schema 3 is never paired with older apps, because the protocol bump stops them joining. A server rollback uses the same `.bak` projection.
   - **The paused R21 branch** also claims schema 3. The zoo now takes 3, and R21 must rebase onto 4 when it resumes. This is recorded in HANDOFF.

5. **What the tree says versus what is live.**
   - **Production source** (this tree): `PROTOCOL` 13, `SCHEMA` 2. The zoo moves them to 14 and 3. These are facts about the code.
   - **Live release** (outside this tree): the Mac coordinator reports that r12 was published on iPad, Apple TV and the existing HK on 2026-11-15. Which protocol and schema those targets now run is the Mac's release record to state. `docs/release-status.md` here still describes the earlier state (protocol 10), so it is not quoted as live fact.
   - In any case the zoo's protocol differs from every published build, so apps and server must update together when it is released.

### 22.6 Other amendments

1. **Lion Hill slice (1A).** It runs at the real default camera, with a Lion Hill footprint that pins section 5 by test. Concept images (`build/dual-host/zoo-concepts/20261115/`) are optional and unapproved. The owner opened both. It may borrow from them only shapes that fit the current style: rock terraces with a cave, a mane of a few lobes, pale muzzle and paws, a tail tuft, flat colour bands for stripes, a play ball, a low viewing rail. It does not take their closer framing or their animal sizes.
2. **Reduce Motion for the other animals.** The same rule as the monkeys: the behaviour stays, and the amplitude and speed are reduced (the pounce becomes a bat, the roar a softer pose, the pool leap a wade-in).
3. **Candidate boundary.** Each sealed candidate is bounded and comes with a Mac request. The first is the Lion Hill slice together with the monkeys' rig and brain, entered by a developer start argument. Nothing in it is offered to players until Phase 1B's journey exists.

### 22.7 Camera in the zoo: turning and zoom (user approval, 2026-11-16)

Approved by the user and added to the first release. It is assessed in [zoo-camera-rotation-assessment.md](zoo-camera-rotation-assessment.md). In the zoo only:
- the existing eight 45° turns, through the on-screen buttons and L / R;
- three fixed zoom levels, 8 m (closer), 9.5 m (default) and 15 m (wide), through the Zoom button, a pinch, the wheel and ZL / ZR;
- each arrival starts at the default view, and the town's own view comes back on return;
- turns and zooms snap under Reduce Motion.

This supersedes section 4.1, item 3, "no closer zoom step", **for the zoo**. Pitch, field of view and style are unchanged. The town, the rooms and every other place keep the two zooms and their behaviour.
