# Lantern Lane — Game Design

Controller hints must follow tab and scrolling layout changes without waiting for a periodic timer. They avoid the visible portions of toy-box cards, scrollbar and readable disabled buttons such as Undo; disabled buttons remain excluded from controller navigation.

Status, 2026-10-06: implemented as a playable Godot 4.7 prototype in `game/`. Revision 2 (same day) adds background music, animal friends, a larger town, three-story houses and placement tools that move out of the way. This design replaces the earlier static "Our Little Town" preview flow. The preview remains in `design/` as reference. The working title, cast names and content are proposals for the creator to change.

## Pitch

A cozy shared town where two to four friends, each at home on their own iPad, decorate together. Certain arrangements form **Cozy Spots**, such as a tea party, a reading nook or a pond picnic. Each new spot lights a lantern on the **Wishing Tree** in the town square, and the town scrapbook records which friends made it together. In the evening, anyone can ring the bell, and the whole town glows with what the friends have built.

## Design pillars

1. **Everything is free, right away.** The toy box holds every item with unlimited copies. There is no currency, collecting, unlocking or task to finish first.
2. **Make it, then play in it.** Swings swing, seesaws rock, chairs and sofas seat friends, beds are for resting, and houses can be entered. Building creates places to play together.
3. **Discovery without pressure.** Cozy Spots reward thoughtful arrangement with a celebration and a lantern. They never gate anything. Unfound spots show gentle hints in the scrapbook.
4. **Together, kindly.** Players choose preset nicknames and play with emotes (wave, cheer, dance, love). There is no free-text chat or typed name. Anyone can edit anything, but only one child holds an item at a time, and you can only undo your own actions.
5. **Readable toy look.** Soft, rounded primitive shapes, simple colors, big-headed children, uncluttered lawns and soft contact shadows. The direction is inspired by the clarity of Animal Crossing; all content is original.

## Core loop

```text
Wander the town ──► open the Toy box ──► place / move / turn / paint
      ▲                                              │
      │                                              ▼
 ring the evening bell ◄── play in it (sit, swing, ride) ◄── a Cozy Spot forms:
 & look at the glowing tree                                 lantern lights, scrapbook entry
```

A session is short and open-ended (about 10–30 minutes). Players arrive, see what their friends changed, try to find a new Cozy Spot or redecorate a house, play on what they built, and leave. The town saves itself.

## Activities

| Activity | What the child does | Implemented |
|---|---|---|
| Character | Pick a nickname, skin tone, hairstyle, hair color, outfit and color; the child preview cheers | Yes |
| Walk | Tap the ground (or WASD on desktop); tap a door, swing or bench to walk there and use it | Yes |
| Decorate | Toy box by category; a ghost item with a green or red ring; drag, Turn (45° steps), Paint (8 colors), Place, Cancel | Yes |
| Table tops | Drag a small decoration (flower pot, teddy bear) onto a round table and it snaps onto the top. Each table holds exactly one; a second one is refused. The decoration moves and turns with its table and is packed away with it ([scale contract](../design/object-scale-and-surfaces.md)) | Yes |
| Edit | In Decorate mode, tap an item to pick it up (locks it for others), then move, turn, paint or put it away; Undo | Yes |
| Houses | Place whole three-story cottages in any of 8 roof colors. Walk in through the front door, then through doors and stairs between six rooms (two per floor), and furnish each room | Yes |
| Animal friends | Pip the pig, Bramble the rabbit, Wooly the sheep, Biscuit the dog and Tumble the elephant roam outdoors and play their hobbies; tap one to see what it loves ([animals.md](animals.md)). **House visits (r18):** Pip, Bramble, Wooly or Biscuit can **Come home with me**: it follows the child through the door, the rooms and the stairs, answers emotes, and goes back outside after **Say goodbye** or when the child leaves ([animal-visits.md](../design/animal-visits.md)) | Yes |
| Apple TV with a controller (TV candidate) | On Apple TV the whole game is played with one controller: the left stick walks, a pointer taps the real buttons, A confirms and B goes back (by the labels on a Nintendo controller), X does the nearby action, Y and + turn and place in Decorate, L and R turn the camera. Text fields are not offered on a TV (no keyboard): the toy box is browsed by its tabs, and Play with friends joins the town the app was prepared with. Progress is kept safely within the TV's small persistent storage; photos and stories may be removed when the TV needs space ([tv-controller.md](../design/tv-controller.md)) | TV candidate |
| Decorations that move (r20) | A ceiling fan's blades turn slowly, a bird mobile and a red paper lantern sway from their hooks, and a candle chandelier and a bamboo floor lantern glow gently in the evening. **Reduce motion** in the Sound and music settings keeps them still, also after a restart ([decorative-motion.md](../design/decorative-motion.md)) | Yes |
| Music | A gentle original loop outdoors, softer on menus and indoors; music on/off and volume, sounds on/off ([assets.md](assets.md)) | Yes |
| Explore | A 52 × 44 m town: the original center plus a west grove, an east meadow with a second pond, a north orchard and trails | Yes |
| Play | Swing (sway), seesaw (two riders), bench, sofa and bamboo bench (two seats, 0.80 m apart; r17), chair, bed (rest) | Yes |
| Cozy Spots | 8 recognized arrangements, a celebration, a lantern on the Wishing Tree, credit to everyone present | Yes |
| Evening | The bell at the Wishing Tree switches the shared time of day; lamps, windows, lanterns and fireflies glow | Yes |
| Emotes | Wave, cheer, dance, heart, seen by everyone | Yes |
| Scrapbook & photo | Lanterns lit, hints for unfound spots, photos taken this session | Yes (photos are saved on the device; the in-game album lists only this session's photos) |
| A. Animal wishes | An animal shows a wish card for an outdoor arrangement; a "Wish" tab is pinned first in the toy box; fulfilling it earns a scrapbook sticker for everyone present and sometimes a present ([proposals](../design/playfulness-proposals.md)) | Yes |
| B. Hide-and-seek | One child hides a golden acorn where they stand (town or any room); seekers get warmer/colder hints from the server and the acorn appears within 2 m; solo, an animal hides it | Yes |
| C. Gift bundles | Wrap a placed item for a friend on the roster (or anyone); only they can unwrap it; at most 3 unopened presents per recipient | Yes |
| D. Little gardens | A garden bed grows from seeds to sprouts, buds and blooms while children play, faster when watered; it never wilts | Yes |
| E. Dance party | A drum starts a 30 s party: the music speeds up, animals parade, all eight Wishing Tree lanterns hang out and twinkle, and children can dance | Yes |
| F. Open-house hearts | One heart sticker per player per room; the living room keeps a guest book of visitors; no counts or rankings | Yes |
| G. Photo ideas | 8 photo ideas checked from what is actually on screen when the shutter is pressed; completed ideas go in the scrapbook | Yes |
| H. Weather | A weather vane by the bell cycles sunny, rain, autumn and snow for everyone; decoration only | Yes |
| Pets (r7) | Adopt a cat, dog, bird or butterfly (ten modeled variants, friendly names to choose from) in **Pets**; the chosen one follows you through town and rooms, others rest in the Pet room by the beds, cat tree, perches and butterfly garden; pat a pet, or feed it at a food bowl | Yes |
| Cooking (r7) | At a stove, **Cook** a rice bowl, vegetable soup, fried egg or rice and stew when its ingredients are in the room; three seconds of steam, then the dish is served next to the stove; **Eat** it | Yes |
| Snack stand (r9, F01) | Place a **snack tray** anywhere; **Make a snack** from a picture card (cookie, sandwich or juice; berry, honey or mint topping); the snack is a real item; **Share** it and everyone close by cheers (outdoors the nearest animal dances). No prices, orders or scores ([playability-8-12.md](../design/playability-8-12.md)) | Yes |
| Fetch with Biscuit (r9, F03) | Tap Biscuit → **Play fetch** → tap the ground: the ball flies, Biscuit runs, picks it up and brings it back to the thrower; friends take turns; **Stop fetch** ends it | Yes |
| Weather play (r9, F04) | In the rain every child splashes when stepping into a puddle (seen by everyone); a placeable **snowman** with three faces (**Change face**) and a paintable scarf that never melts | Yes |
| Toolkits (r9, F09) | Toy box tabs **Snack Stand, Little Theater, Rainy Day, Music Corner** gather existing things for one kind of play, each with a one-line idea; nothing is locked | Yes |
| On display (r9, F10) | **Put on display** (while decorating) protects a room or the town square: a friend who starts decorating there is asked first and may take it off display; the server refuses edits there until then | Yes |
| Dress up (r10, F07) | **Dress up**: a chef hat, explorer hat, paper crown or rain hat and the clothes color, changed in town any time; friends see it | Yes |
| Music box (r10, F08) | A placeable **music box** with a 4 x 8 tune grid (bell, drum, chime, bass), Play/Stop for everyone nearby, lamps glow gently on the beat, **Mute music boxes** on your own device | Yes |
| Trails (r10, F06) | Up to five numbered **trail signs** with clues (wave, cheer, dance, love); **Follow the trail**, do each clue at its sign, and finish with a shared keepsake sticker | Yes |
| Story (r10, F05) | **Story**: pick an inspiration card, pose (surprised, thinking, proud, sneaking), take three pictures, reorder them and keep the strip in the scrapbook (and Photos) | Yes |
| Toy tracks (r10, F02) | Start, straight, curve, switch, bell and finish pieces snap together outdoors; **Roll the ball**, ring bells, flip switches; a gap shows an arrow and the ball waits | Yes |
| Invitations (r11, F10) | **Invite friends** from an activity card; each friend gets one card per inviter with **Join** (go there) or **Not now**; **Ask friends to help** lets friends who join edit a place on display until they **Leave** | Yes |
| Animal games (r11, F03) | **Sing with Wooly** (it answers your emotes), **Garden with Bramble** (a bed grows), **Splash with Pip**, **Fountain with Tumble** (heart, star, round); friends join a running game | Yes |
| Boats and leaves (r11, F04) | A **paper boat** by a pond sails a lap; **Jump in!** a leaf pile (a big burst when two jump together); a garden umbrella | Yes |
| Contraptions (candidate `contraptions-life`, not released) | A **Big button** (context action **Press**) or a **Step pad** (walk onto it) sets off the things within two steps: lamps switch on by day, a music box starts, a **Pinwheel** spins, a **Bubble machine** blows bubbles, a track start rolls its ball. Each thing passes the spark on to its own neighbours one hop at a time, so a row becomes a chain; toy-track bells, lights and finishes set things off as the ball passes. While decorating, dotted lines show what is linked. No scores or timers ([contraptions-and-town-life.md](../design/contraptions-and-town-life.md)) | Candidate |
| A living town (candidate `contraptions-life`, not released) | The animal friends notice and use what children place outdoors: the nearest one comes to look at a new thing; Wooly dances by a playing music box; Pip sniffs at snacks; they rest on a picnic blanket, in an umbrella's shade or under it in the rain, and by a lit lamp; Tumble comes for bubbles; Biscuit watches a rolling ball. The line over the animal says what it is doing ("Wooly loves this music!"), a ring marks the thing, and its card begins with the same line | Candidate |
| Puzzle rooms (candidate `puzzle-rides`, not released) | A child hides **Puzzle keys** and **clue cards** and sets up **Picture dials** and a **Treasure chest**. Friends pick up each key (it hops to the chest), turn each dial to the picture on the clue card of the same color and dots, and open the chest; lamps and other contraption things beside it answer. One puzzle per place; progress is shared by everyone there; **Start again** on the chest's card is for anyone, at any time; editing a part starts the puzzle again. Nothing is locked, scored or timed ([design](../design/puzzle-rooms-and-rides.md)) | Yes |
| Rideable carts (candidate `puzzle-rides`, not released) | Outdoors, **cart rails** snap to 2 m cells. From a **Cart station**: **Get in the cart**, **Go!**, **Stop**, and **Get off** on a second button beside the main one. A ring is ridden three laps; an open track ends with the cart stopping before the last rail's end. The cart stops before anything solid on the rails. One child per cart; the camera follows as gently as on foot and never turns by itself | Yes |
| Lamplighter walk (candidate `town-play`, not released) | **Light the lamp** / **Put out the lamp** on any lamp post. When the evening bell has rung and every lamp post is lit, fireflies rise around the lamps for everyone, once that evening. Nothing counts what is missing ([design](../design/town-evenings-and-more.md)) | Yes |
| Signal rails and weather bells (candidate `town-play`) | A **Signal rail** sets off the contraption things beside it each time a ridden cart passes; a **Weather bell** does so whenever the weather changes; pinwheels turn by themselves in autumn | Yes |
| Picture board (candidate `town-play`) | **Paint a picture**: eight colors, a rubber and 8 x 8 squares on a card; everyone can add to the same picture; saved with the town | Yes |
| Friend echoes (candidate `town-play`) | **Hello** in the menu column leaves three emotes as a see-through figure for friends who are not online; a friend answers with one emote; one per child, replaced by a new one, taken away by its maker or gone after seven days | Yes |
| Animal passengers (candidate `town-play`) | From a cart at its station, an animal's card offers **Come for a ride**: it rides in the trailer and hops out at the station | Yes |
| First steps (candidate `first-steps`, not released) | A child who is new on a device reads one short line at a time at the top: how to walk, then that Decorate builds, then that Activities has ideas. Each line goes when it is done; **Hide** puts it away; it never comes back. A child who already plays sees none of it ([design](../design/first-steps.md)) | Yes |
| The guide's second section (candidate `first-steps`) | **Activities** has two sections: **Things to do** (the eight activities) and **Things to build** (contraptions, puzzle rooms, cart rides, evening lamps, the picture board, a hello for friends), each card with steps and a button that leads into the game | Yes |
| Blueprints (r11, F09) | Save a picked group as a named blueprint on this device; preview, move, turn and place it elsewhere; Undo removes it | Yes |

### Cozy Spots

| Spot | Arrangement |
|---|---|
| Tea party | A round table with two chairs within 1.7 m |
| Reading nook | A bookshelf with a seat and a floor lamp nearby (indoors) |
| Flower ring | A round tree with three flower patches around it |
| Pond picnic | A picnic blanket beside a pond |
| Sleepover | Two beds and a rug in the same room |
| Lantern path | A lamp post with four stepping stones nearby |
| Playground | A swing and a seesaw close together |
| Front porch | A bench and a flower pot or flowers by a cottage door |

The default town contains no spots, so the first lanterns are the players' own discoveries. New spots are easy to add in `game/scripts/core/cozy_spots.gd`. This is a natural way for the creator to contribute ideas.

### Toy box (163 items)

Nature: round tree (leaf color can be painted, for example blossom pink), pine, berry bush, flower patch, garden bed. Paths & water: stepping stone, pond, lamp post, fence. Play: swing, seesaw, bench, picnic blanket. Homes: cottage. Furniture (indoors, and chairs and tables outdoors too): bed, chair, round table, sofa, bookshelf. Cozy things: rug, flower pot, floor lamp, teddy bear.

Modeled items (not paintable, colors baked in): the ten pilot-10 models (scallop chair, cozy round table, scallop bed, writing desk, open shelf, curved counter, desk lamp, blooming flower pot, wall clock, bird mobile) and 130 release r1 models for rooms: large and medium furniture in the Furniture tab (tables with a support surface, chairs and stools to sit on, a bed to rest on, shelves, cabinets, arcade games, statues, a gazebo), and small decorations, table-top food and toys and 41 wall items (clocks, paintings, wreaths, plaques, lamps) in the Cozy things tab. Wall items snap onto a room wall at a set height; the bird mobile hangs from the ceiling. Small items marked table-top eligible fit on every table at some rotation. The list, sources and versions are in [art/production-r1](../art/production-r1/README.md); coverage of all 639 reference entries is in [design/model-release-r1.md](../design/model-release-r1.md).

### Weather in the city (candidate `city` r3, not released)

- **Choosing it:** three small glass buttons on the right of the screen (sun, rain, moon) choose the city's weather for everyone there. The change blends over four seconds.
- **Rain:** rain falls around the view, the ground turns darker and glossy, and puddles appear.
  - People outdoors either open an umbrella (about a third) or hurry, in small staggered groups, to awnings, shelters, the carousel's canopy and the open ground floors. They wait there and go back when it stops.
- **Night:** a deep-blue sky.
  - **Steady warm light:** windows, signs, terrace and rooftop strings, lamps along every pavement with soft pools under them, and the wheel's rim and cabins.
  - **No flicker:** nothing flickers or pops while the view moves.
- **Palette:** a blue main building, a coral-orange tower, a warm-yellow cafe, mint shops, dark-green roofs and a berry-red wheel.
- **On a computer:** a right drag pans the view.

### The web city (candidate `city-web` r1, not released)

- **What it is:** a second city map, `city_web`, reached from the town's tram stop by "Ride to the city (web)", beside the Godot city. Its purpose is to evaluate Three.js on the hardware that runs the game ([design/city-threejs.md](../design/city-threejs.md)).
- **Same city:** Godot exports its own built city, the constants of every city script and each child's rig; the page draws them with Three.js 0.186.1. The moving things, the people, the weather and the camera are ported function by function and checked against Godot's own numbers.
- **Same play:** the child walks, rides the wheel, sits and uses things exactly as in the Godot city, because Godot still runs all of it; the page sends taps as rays and Godot picks the floor. The page's buttons are the city's: Look, Pause, the weather, Reset view, the action button and Ride home.
- **Separate:** each city map has its own shared state (seats, the wheel, the weather); friends in one city do not see the other.
- **Where:** iPad and iPhone, and desktops started with `--web-city`. Not Apple TV (no web view); a native Canvas route for Apple TV is being studied, not offered.

### The city alive (candidate `city` r2, not released)

- **People:** 52 people live in the city, each with a look of its own: office workers at computers, diners and talkers, shop staff and customers, people exercising, walkers swinging their arms, passengers in the wheel's cabins and riders on the carousel.
  - Seated people now and then turn their heads or lift a cup, and everyone's timing is staggered.
  - They never take a child's place, and the standing ones are solid.
- **Traffic:** three buses (blue, yellow and berry) and two cars share one lane; the buses pause at four stops and keep their spacing.
- **Look:** a button beside Reset view.
  - While looking, a tap on a building, a shop, the rooftop restaurant, the wheel or the carousel glides the camera in; a tap on empty space glides back out.
  - Pause freezes the city on this screen only.
  - Esc, B or the button ends Look, and taps walk again.
  - The child stays where it is, visible, with its action button.

### The city district (candidate `city` r1, not released)

A third map, 72 x 56 m on a white world, reached by tram from town ([design/city-district.md](../design/city-district.md); the layout data is `game/scripts/core/city_map.gd`).
- **Getting there and back.** The town's tram stop offers **Ride to the city** beside Ride to the zoo. The child arrives at the bus stop; **Ride home** is always on screen, and the bus stop's action rides home too.
- **The block.**
  - **Office:** a blue three-storey office with desks, computers and bookshelves.
  - **Cafe:** a yellow cafe with a coffee bar, a dining area and a roof terrace.
  - **Coral tower:** a furnished first-floor terrace and a rooftop restaurant.
  - **Shops:** five shops with English signs (bakery, cafe, bookstore, flowers, ice cream).
  - **Ferris wheel:** berry-red and cream.
  - **Around:** paths, flower beds, roads with a bus and two cars, and four walkers.
- **Walking on every level.** Two outdoor and two indoor stairs and two skywalks join the floors and terraces. Walls, railings and furniture block the way. A tap walks to the floor that shows under the finger; floors above the child are cut away near it.
- **Things to do.**
  - **Places that hold the child:** cafe and terrace seats (sit), the gym's treadmills, bikes and weights (run, pedal, lift), and office desks.
  - **Short treats:** a hot chocolate, dinner on the roof, a bun, a cupcake, a book, a flower, an ice cream.
  - **The wheel:** board a gondola at the bottom, ride round, and get off at the bottom.
  - **Sharing:** places are shared, so a taken seat says so kindly.
- **Camera.** The overview fits the whole block on every device. A drag orbits; pinch, the wheel or ZL / ZR zoom from the overview down to 8 m; L / R turn in 22.5 degree steps; **Reset view** returns to the overview. A short tap still walks.

### The zoo (candidate `zoo`, not released)

A second map, 84 x 64 m, reached by tram ([design/zoo-and-world-journeys.md](../design/zoo-and-world-journeys.md); the binding interfaces are in [docs/zoo-engineering-standard.md](zoo-engineering-standard.md)).

- **Getting there and back.** Every town has one **Zoo tram stop** near the arrival point, inside the first view on every device. A new town has it 4.5 m ahead and to the left of the child. An old town gets the free spot nearest that, and nothing a child made moves. It is not in the toy box, it can be moved like a cottage and never put away, and it has a "Zoo tram" name tag. Tapping it, its tag, or the action button (X on a controller) starts the ride. A journey card shows for at least 1.2 s and takes no input. In the zoo, **Ride home** is always beside the place name ("Zoo · Lion Hill"). A refused or timed-out ride leaves the child where it was, with one line saying so. Pets in follow mode come along. A town animal visiting a child's house stays in town, and the child is told it will wait there.
- **Zoo r2 (in development).**
  - **Imported meshes:** Rory, Topper, Zig and Zag use the Everything Library's lion, giraffe and zebra (CC BY 4.0, credited on the "Zoo friends" page). The meshes are skinned and moved by the same rigs, so every action stays.
  - **Bao the panda,** in **Bamboo Grove** (east of the savanna): munches bamboo, sits up on the rock, and rolls on the lawn. A child standing still at the gate brings Bao to the front.
  - **Mabel the elephant,** in Savanna Meadow: dusts, flaps her ears, drinks and sprays at the waterhole (the pump sends her there), and trumpets for a cheer at the gate.
  - **Pebble and Flip the penguins,** in Splash Bay: preen and flap on the shore, swim and dive, belly-slide into the pool, and waddle alongside a child running on the beach.
  - **Avoidance:** every land and water animal keeps its footprint clear of the others and stays in its habitat.
- **Who lives there.** Lion Hill: Rory and Honey. Tiger Hill: Tango. Monkey Hill: Mango, Coco, Peanut, Momo and young Bibi. Savanna Meadow: Topper, Zig and Zag. Splash Bay: Bubbles, Skip and Ripple. Every animal has its own routine, its answers to wave, cheer, heart and dance, and a signature moment: Rory paces beside a child on Lion's Pass, Tango plays peekaboo in the bamboo and leaps into his pool, the zebras gallop beside a running child, Topper bows to a still child, Bubbles surfaces, the otters escort a swimmer-watcher. In the rain the lions rest in their den.
- **Monkey Hill.** At least twelve whole-body moves (climb, ring swings, vine, leaps, balancing on the ridge, tail hangs, somersaults, drumming, the tyre swing, and more), play between monkeys (chase, follow, pass, groom), and a copycat answer to a dance. Choices are weighted, with cooldowns, staggered starts, real pauses and at most three big moves at once (two under Reduce motion).
- **Things to do.** Treat tables, the monkeys' banana basket and bell rope, the tyre swing, bongo logs, the savanna pump, the hippo's shower and the tiger's ball. Nothing runs out; an animal is "full and happy" after three treats in a minute. **Look**: tap an animal and the camera frames it with the child, and a small strip shows its name, what it is doing, **Offer a treat** and **Done** (B on a controller). Look also ends on walking away, Decorate or a dialog.
- **The zoo's toy box.** Two tabs: **Zoo** (play ball, big box, scratching log, leaf feeder, hay bale, play mirror, which the animals play with) and **Picnic** (bench, blanket, flowers, fence, garden umbrella, picture board). At most 80 things. No blueprints, displays or help requests in the zoo.
- **Remembering.** The scrapbook's "Zoo friends" page lists each species with the answers a child has found and who found them, and a hint for the next one. Four photo ideas belong to the zoo.
- **Camera.** In the zoo only: turns in 45 degree steps and three zoom levels, 8, 9.5 and 15 m. Every arrival starts at the designed view, and the town's own view comes back on the way home. Reduce motion snaps instead of gliding.
- **Shared.** The solo device, host or server runs the animals while someone is in the zoo, and only zoo players receive their states. Evening and weather are the town's and show in the zoo (sky, lamps, rain, snow, leaves).

## Rules that settle earlier open questions

- **Joining:** one town per server. Up to four children; a fifth is told kindly that the town is full. Solo play uses a separate town on the device.
- **Shared edits:** picking up an item locks it for others, who see "<name> is decorating here". Occupied seats and houses with someone inside cannot be moved or put away. Locks and seats free up when a player leaves. On a two-seat bench or sofa the first child to sit gets one seat and the next child the other; tapping Sit on a full one says "Someone is playing on it.", and Get up puts each child in front of their own seat (r17, [design/two-seat-benches.md](../design/two-seat-benches.md)).
- **Undo:** each child can undo their own last 30 actions. Undo is applied as a new shared edit and fails gracefully if a friend has since changed that spot.
- **Houses:** every cottage has three floors with two rooms each:

  | Floor | Room 1 (stairs here) | Room 2 (through the side door) |
  |---|---|---|
  | 1 | Living room (front door) | Kitchen |
  | 2 | Bedroom | Playroom |
  | 3 | Attic | Art studio |

  - The first room of each floor holds the stairs: up on the back wall, and down where the front door is on the ground floor. Every doorway and staircase has a sign and a mat. Walking onto it (or tapping it) takes the child through, arriving just inside the matching opening so the way back is right behind them.
  - Only the room you are in is drawn, and children in other rooms are hidden. The top-left chip says, for example, "Floor 2 · Bedroom".
  - Furniture belongs to one room. Doorways and stairs must stay clear.
  - Putting a cottage away packs all six rooms (after a confirmation) and can be undone as one action. It isn't possible while a friend is inside any of its rooms.
- **Placement:** footprints are circles; solid items cannot overlap; flat items (rugs, paths, blankets) lie under solid ones. Door fronts, the Wishing Tree plaza and the edges stay clear. The town holds up to 300 items and each room up to 40, pending iPad measurement.
- **Persistence:** the authority (server or solo device) autosaves 1.5 s after changes with an atomic write and a `.bak` copy. Solo play also saves when iPadOS pauses the app.
- **Save migration (schema 1 → 2):** older saves load unchanged outdoors, because every old position still fits the larger town. Each cottage's old single room becomes its ground-floor living room. Furniture standing in the new stair or side-door openings is moved to the nearest free spot in the same room. The untouched original save is kept once as `<save>.v1`.

## Controls (landscape iPad)

Top bar: friend chips (with the floor and room inside houses), save and connection status, lantern counter (opens the scrapbook), photo, sound and music, language, leave. Right edge: rotate view and zoom. Bottom left: emotes. Bottom center: a context action ("Go inside", "Go upstairs", "Kitchen", "Swing", "Evening"…). Bottom right: Decorate/Done and Undo.

Landmark name tags: on the town square, the nearest landmarks (weather vane, bell, drum, acorn stump, photo board) show tappable name tags, at most three at once. Untried ones show from about 13 m, tried ones only up close (4.5 m), and new ones are yellow. Tapping a tag walks there and starts it. A screen-space layout keeps the tags apart and clear of the top bar, the bottom controls and the safe area (`game/scripts/ui/tag_layout.gd`).

Toy box (decorate mode, [design/item-browser-ux.md](../design/item-browser-ux.md)): a bottom sheet with a search field, the result count and **Things here**; one sideways row of tabs (**Recent** with this device's last 10 placed kinds, **Wish**, the categories, **All**) followed by placement filters derived from the catalog (Floor, Small things, On the wall, Ceiling, Seats, Tables; shown only when they split the results); then item cards with a thumbnail and a two-line localized name, sorted by name. Search covers every category of the current space, matches the shown language and English, ignores case and accents and ranks whole name, start, word start, then anywhere. The tab, filter, search and scroll position survive placing, so the same item can be placed again with one tap; the last card taken is outlined. While the on-screen keyboard is up the sheet rises above it. A tap that lands on several items in decorate mode opens **Which one?** next to the finger instead of guessing; **Things here** lists everything in the room or town, nearest first, and a row picks that item up.

Placement tools (since `first-steps` r8, not yet validated on the Mac): while a thing is held the toy box tucks away and the tools (its name, the instruction or the reason it cannot go there, and Turn / Paint / Put away / Cancel / Place here) have two places of the same size, at the bottom edge and under the top bar. Outdoors the camera rests the held thing in the room between the two places, stepping back when the thing is tall or when the child would not fit between the places (two rows of buttons); the tools then leave the place where the player's own child stands, and return to the bottom edge when nothing is near it. While a finger drags the thing the camera holds still and the thing decides (the child cannot move the tools then), with a margin for the way back. The chips at the top centre (first-steps line, activity, story or trail) step aside while a thing is held. Indoors (since `first-steps` r9) the room camera keeps its dollhouse view and steps straight back only when the held thing and the child leave neither place free, so the room is drawn smaller then; the thing keeps 24 px from the tools there as outdoors. Since `first-steps` r10, indoors the camera also steps back just enough to keep the held thing whole inside the safe area, and while a thing is held, anywhere, a side menu or the top bar's right part (the left menu; the saved status, lanterns and corner buttons; the camera buttons; the bottom right column; poses and emotes) that would stand on the held thing or on the player's own child steps aside: it is hidden, takes no press and the controller skips it. It comes back as soon as it would no longer stand on them, and always when the thing is placed, cancelled or put away. Since `first-steps` r11 the menus, and the controller's hints, judge the held thing by its catalog ring and its own meshes' boxes together (a round table's top reaches past the ring). For the few frames after a pick in which the tools take their place unseen they take no press. A dwell time and margins prevent jumping back and forth. The toy box comes back when the thing is placed or put back. Positions respect the device safe area. Main controls are 68–96 px and tabs and swatches 56–60 px at the 1366×1024 base resolution (about 44–70 pt on a 12.9" iPad; not measured on a device). Pinch zoom uses magnify gestures (not verified on device).

## Art direction

Sizes follow the canonical scale contract in [design/object-scale-and-surfaces.md](../design/object-scale-and-surfaces.md): 1 unit = 1 m and child height H = 1.30. Ordinary trees are about 1.85 H. Large furniture is clearly bigger than a chair. Small decorations are about 0.35–0.4 H, so they read well and fit on a table. The Wishing Tree and the cottages stay landmark-sized.

Everything is generated from code (`game/scripts/art/`): rounded boxes with exact normals, spheres, capsules and cylinders with soft matte materials. There are no textures, so silhouettes and color carry the look. Real-time shadows are off: soft blob shadows ground every object (see the environment report for why). The camera is close and tilted at 40° (direction A from the preview), with 45° turns and two zoom levels. Interiors use a dollhouse cut-away with the front and right walls removed, and each room has its own gentle wall tint. Cottages are three stories tall outside (trim bands, windows on every floor, a balcony, a round attic window) on the original footprint. The palette follows `docs/design-spec.md`.

## Localization

All UI text is English source passed through Godot's `TranslationServer`. The game uses the same JSON key format as the preview, in `game/locale/`, for en, zh-CN, ja, es, fr and de, with English as the default. Language can be switched from the title or in game at any time without losing the town or a placement draft. Bundled OFL fonts: Nunito (Latin), M PLUS Rounded 1c (Japanese) and Noto Sans SC (Chinese), with CJK subset to the catalog characters. The fallback order depends on the locale, so Chinese uses Chinese glyph forms. The app name is localized for the home screen. Translations have not been reviewed by native speakers; see the handoff for specific choices to review.

## Next content ideas (not implemented)

From the 2026-11-11 brainstorm: puzzle rooms and riding what you build are implemented in candidate `puzzle-rides` (not released; see the table above). An evening lamplighter walk, signal rails, weather toys, a shared 8 x 8 picture board, friend echoes and animal passengers were authorized by the user on 2026-11-13 and are implemented in candidate `town-play` (not released; see the table above and the [experience plan](../design/experience-plan.md)). The remaining deferred play-idea details listed in [playability-8-12.md](../design/playability-8-12.md); creator-designed items (drawings turned into new builders), more spots (garden party), a mailbox for leaving emoji notes, seasonal lantern colors, and a shared town photo wall.
