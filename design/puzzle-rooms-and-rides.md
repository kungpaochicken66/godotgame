# Design: puzzle rooms and rideable carts

Status: written and implemented 2026-11-13 as candidate `puzzle-rides` r1, on top of the frozen `contraptions-life` r3 (manifest `48c4f1b3…6c47`). Not released, not rendered on a GPU, not run on an iPhone, iPad or Apple TV. Owner: GameCode lane (EC2). Art is code-built in the existing primitive style; no new model, texture, sound or font source was added.

Two directions chosen by the user from the six-direction brainstorm (handoff `build/mac-handoff/puzzle-rides-20261113/FABLE_HANDOFF.md`):

1. **Puzzle rooms:** a child makes a small puzzle that a friend can solve and play again.
2. **Ride a creation:** a child lays a ring of rails, gets into a cart and rides round it.

Both keep the pillars of [game-design.md](../docs/game-design.md): everything is free, nothing is scored or timed, nothing can be lost, no text is typed, and every action works by touch and by one controller.

## 1. Puzzle rooms

### The loop

**Make:** hide a key and a clue card, set up a picture dial and a treasure chest. **Solve:** find the key, read the clue, turn the dial, open the chest. **Again:** anyone taps Start again.

### The parts

All are in the toy box tab **Puzzles** (and in **Play**), indoors and outdoors.

| Part | What it is | In play |
|---|---|---|
| **Treasure chest** | The goal. A row of small lights on its front shows what it still needs: one gold light per key, one light in each dial's color | **Treasure chest** opens its card |
| **Puzzle key** | A golden key on a small cushion. It fits on tables and shelves, so it can be hidden | **Pick up the key**: it hops to the chest and its light goes on. Nobody carries it |
| **Picture dial** | A post with a picture board and a knob | **Turn the dial**: the next of four pictures |
| **Clue card** (four kinds: circle, square, triangle, flower) | A small card on an easel showing one picture. It fits on tables and shelves | Only looked at |

### The one rule

**A dial must show the picture of the clue card that has its color.** Paint a dial and a clue card the same color and they belong together. The chest opens when every key is found and every such dial shows its card's picture.

- Color is doubled by a count: a card and a dial carry a row of small dots, one for the first paint color up to eight for the last, so the pair can be matched without telling colors apart. The four pictures differ by shape only.
- A dial with no clue card of its color is decoration. With two clue cards of one color, the older one decides.
- A chest with no keys and no dials is a plain treasure chest: it opens at once.
- A puzzle counts at most six keys and six dials.
- A dial never starts on its answer. What it starts on comes from its id, so every device shows the same without a message.

### One puzzle per place

Every puzzle part in a space (one room, or the town outdoors) belongs to that space's puzzle. There is no wiring step and no general scripting. While **decorating**, dotted purple lines of small squares join each key and each counted dial to the chest, and each clue card to its dial. (Contraption links are orange round dots with an arrow head.)

### Shared progress

- Progress belongs to the place and to everyone in the town: whoever is there helps the same puzzle along. A key one child finds is found for all; a dial one child turns is turned for all.
- The authority (the solo device, the host or the town server) checks every action: the child must be in the same space and within 2.2 m of the part.
- **Who may start it again:** anyone standing in that place, at any time, from the chest's card (**Start again**). Keys go back, dials turn away from their answers, the chest shuts.
- **Who may edit:** the ordinary rules, unchanged. Anyone may decorate, except in a place another child put **On display**; there the usual question is asked first. Using a puzzle is play, not decoration, so it works in a place on display. No new permission or account idea was added.
- **Editing a part starts the puzzle again.** Placing, moving, painting, wrapping or putting away any puzzle part in a space resets that space's progress as the town is now. Turning a part on its spot does not.
- **Leaving:** a child who leaves or loses the connection takes nothing away; found keys stay found. When an opened chest has nobody left in its place, the puzzle starts again by itself, so the next visitor finds it ready. A half-solved puzzle is left as it is.
- **Nothing is locked.** There is no gate. No door, stair or path depends on a puzzle; a chest, a dial and a key are ordinary things under the ordinary door-clearance rules.

### Crossover with contraptions

An opened chest is a contraption **trigger**: lamps, a music box, a pinwheel or a bubble machine within two steps answer, and pass the spark on. A puzzle can end with the lights coming on.

### How it reads

- The chest's lights: unlit grey, lit gold (keys) or the dial's color.
- The chest's card says "Keys found: 1 of 2", "Pictures right: 0 of 1" and the rule in one sentence. **Open the chest** appears when everything is right.
- When the last part is right, the child who did it reads "The chest is unlocked! Go and open it."
- Opening: the lid swings up, gold shows inside, sparkles rise, and everyone in the place reads "Sky, Mo opened the treasure chest!".
- The toy box tab's idea line: "Idea: hide a key and a clue card. Friends turn the dial to the clue's picture and open the chest." (shortened in candidate `first-steps` r1: the first wording ran to five lines and covered the child; the steps are in the Activities guide now)
- With **Reduce motion** on, the key does not fly, the knob does not turn and no sparkles rise; lights, pictures and the lid still change.

## 2. Rideable carts

### The loop

Lay rails in a ring from the front of a cart station round to its back, get in, **Go!**, ride, **Get off**.

### Why not the toy tracks

The handoff asked to build on the toy-track pieces only if their geometry and connections really fit. They do not, and `test_ride_geometry` checks the facts instead of assuming them:

- A toy-track piece is a 0.94 m board for a 9 cm ball. Its bell, light, switch and start pieces stand 0.42 to 0.49 m high over the groove; a seated child's head is about 1.2 m up.
- A toy-track start has one opening, so it cannot be part of a ring; a finish only catches.

So rides have their own three pieces, sized for the cart, in the toy box tab **Rides** (outdoors):

| Piece | Size | Connects |
|---|---|---|
| **Cart station** | one 2 m cell; rails, a small platform, a flag in the paint color, and the cart | front and back |
| **Straight cart rail** | one 2 m cell | front and back |
| **Curved cart rail** | one 2 m cell, a quarter circle of 1 m radius | back and one side |

### Scale and clearance

1 unit = 1 m, avatar height 1.30 ([object-scale-and-surfaces.md](object-scale-and-surfaces.md)).

- Rails snap to 2 m cells and quarter turns. They lie flat: children walk over them.
- The cart is 0.8 m wide and 1.1 m long, its sides 0.52 m high, its seat 0.42 m up: a seated child is seen from the waist up.
- Two tracks side by side leave 1.2 m between carts.
- A curve stays inside its own cell.
- **Nothing is driven through.** A route stops before any solid thing whose footprint comes within 0.4 m (half a cart) of the middle of the rails. Trees, benches and houses beside the track are fine; one standing on it ends the route there.
- Rails and toy-track pieces cannot share a cell.

### The ride

- **Get in the cart** (within 3 m of the station): the child sits in the cart; it waits.
- **Go!**: the cart sets off at 2.4 m/s (walking is 3.4).
- **Stop**: it stands still where it is. **Go!** again continues.
- **Get off**, beside the main button at all times: the child steps onto free ground beside the cart, and the cart is back at its station, empty.
- **A ring:** three laps, then the cart stops at its station with the child still in it. **Go!** rides again.
- **An open track:** the cart stops 0.7 m before the end of the last rail, with "The rails end here. Get off, or add a rail." and an arrow over the place.
- **A rail that does not join, or something on the rails:** the same, with its own sentence.
- One cart per station, one child per cart. A second station on the same rails ends the first cart's route before it.

### When things change during a ride

| What happens | Result |
|---|---|
| A rail ahead is put away or turned | The cart rides to the new end of the rails and stops there |
| A rail is added ahead | It is ridden |
| The rail under the cart is put away or turned | The cart stops where it is ("The rails changed under the cart. Get off to send it home."). Putting the rail back mends it |
| Someone tries to move or put away the station | Refused while a child is in the cart ("Someone is playing on it."), as for any seat |
| A second child asks for the cart | "Someone is riding this cart." |
| The rider sits somewhere else | One seat per child: the cart goes home |
| The rider's connection drops | The seat is freed, the cart goes home; no rider is left on screen. Coming back is a new arrival at the town's entrance |
| The town is saved and loaded | Rails are saved like any thing; no ride is saved; every cart is at home |

The rider is never drawn twice: the seat is an ordinary seat (the same `seats` record as benches and swings), and the child follows the cart through its seat marker.

### Camera

Assessed: **fixed** (stays where the ride began) against **gentle follow** (the existing glide after the child).

- Fixed loses the rider on any ring larger than the screen (about 15 m at the near zoom) and would need a zoom of its own.
- The existing camera already follows the child with a soft glide and never turns by itself; its direction changes only when the child taps a turn button. The cart is slower than walking, so the view moves less than on foot.

**Chosen: the existing gentle follow, unchanged.** The view never rotates with the cart, never shakes and never zooms by itself. Bounded: speed 2.4 m/s, at most three laps per **Go!**.

Not done, and not claimed: a comfort check by a person on a real screen. That is a Mac and device gate.

## Controls

| | Touch | Controller (Apple TV) |
|---|---|---|
| Pick up a key, turn a dial | The action button next to it, or tap it | **X** next to it |
| The chest's card | The action button **Treasure chest**, or tap the chest | **X**; pointer and **A** on its buttons; **B** closes |
| Get in the cart | **Get in the cart**, or tap the station | **X** |
| Go, Stop | The action button | **X** |
| Get off | The smaller button beside it | **Y** (the hints show it), or pointer and **A** |
| Lay rails, build a puzzle | Decorate, the **Rides** and **Puzzles** tabs | As for every thing: pointer and A, left stick, **+** to place |

One control was added: a second, smaller action button beside the main one, shown only in a cart.

## Network and saves

- **Protocol 12** (was 11). New requests `puzzle` (a part's id), `puzzle_reset` (a space) and `ride` (a station's id; `board`, `go` or `stop`). New events `ev_puzzle(space, progress)` and `ev_ride(station, ride)`. Getting off is the existing `stand`.
  - Every app and the town server must be updated together. The paused R21 branch must take the next free numbers when it resumes.
- **Authority.** The solo device, host or server decides every key, dial, chest, boarding, start, stop and the cart's route and distance. Clients ask and draw. A cart's position is drawn on every device from the same route and distance with that device's clock.
- **Saves stay schema 2.** The ten new kinds are ordinary items. A build without them drops them on load, as it does any unknown kind. A town without them saves byte for byte as before.
- **Not saved:** puzzle progress, rides. A loaded town has every puzzle ready and every cart at home.
- **Late joiners** get the puzzles that are under way and the carts that are out right after the town.

## Accessibility and audience

- Clue to dial matching never relies on color alone (dots) and pictures never on color at all (shapes).
- Every puzzle step leaves a state that stays: a light on, a picture shown, a lid open.
- Nothing flashes; nothing is timed.
- Not measured: whether an 8-year-old understands the one rule from the chest's card and the idea line, and whether a ride is comfortable to watch. Both need a person.

## As implemented (candidate `puzzle-rides` r1)

- **Rules:** `game/scripts/core/puzzles.gd`, `game/scripts/core/ride_rules.gd`; the chest as a trigger in `core/contraptions.gd`.
- **Things:** ten catalog entries (`core/catalog.gd`), built in `game/scripts/art/props_puzzle.gd`.
- **Authority:** `net/session.gd` `_srv_puzzle`, `_srv_puzzle_reset`, `_sync_puzzles`, `_puzzle_left`, `_srv_ride`, `_tick_rides`, `_reroute_rides`; the cart's seat freed in `_free_seats_of`.
- **Drawing:** `world/puzzle_world.gd`, `world/ride_world.gd`; hooks in `world/town_world.gd`.
- **Controls and UI:** `world/play_controller.gd` (contexts, Get off, the rider's position), `ui/hud.gd` (the second action button, the chest's card, the toast), `ui/pad_input.gd` (**Y** for the second action, its hint), `core/room_themes.gd` (the two tabs).
- **Text:** 46 new strings in six languages; the two CJK font subsets regenerated with `scripts/build_fonts.py`.
- **Tests:** `game/tests/puzzle_ride_tests.gd`, `game/tests/puzzle_ride_tour.gd`, `scripts/net_test.py --puzzles`.

## Known limits

- One puzzle per place. Two separate puzzles in one room are one puzzle.
- A clue card can be put away by anyone who may decorate there; a maker who wants it safe puts the room on display.
- The cart does not push or wait for children or animals standing on the rails; it passes through them.
- One child per cart; no trains of carts, slopes, switches or crossings.
- A ride that was mended after the rail under the cart changed ends at the station the next time round, whatever laps were left.
- The dots on cards and dials are small (1.3 cm in the model); their readability at play distance needs the Mac's rendered images and a device.
