# Design: town evenings and more (six small slices)

Status: written and implemented 2026-11-13 as candidate `town-play` r1, on top of the sealed `puzzle-rides` r1. Authorized by the user on 2026-11-13 (all six). Not released, not rendered on a GPU, not run on any device. Art is code-built; no asset file is added. See "As implemented" for what exists and what was tested.

Six small things that make the town's existing systems answer each other, each a minimal playable version. All keep the pillars of [game-design.md](../docs/game-design.md): free, unscored, untimed, nothing lost, no typed text, touch and one controller.

**Protocol 13** for all six together (was 12). Saves stay schema 2: every new field is optional.

## 1. The evening lamplighter walk

- **What a child does:** next to a lamp post, **Light the lamp** (or **Put out the lamp**). Until now a lamp could be switched by contraptions only.
- **The evening moment:** when the evening bell has rung and every lamp post in town is lit, fireflies rise around every lamp, a chime plays and everyone reads "Every lamp is lit. The fireflies have come!". Once per evening; the bell starts a new one.
- **Rules:** outdoors, within 2.2 m, lamp posts only (indoor lamps stay as they are). A lamp lit by hand is the same as one lit by a contraption: it shines by day too and is saved. A lamp lit by a contraption counts toward the moment. Lighting is play, not decoration: it works in a place on display.
- **What is honest about the look:** in the evening every lamp already glows. A lamp lit by hand also has its halo. Whether that difference is visible enough is a question for rendered pictures.
- **Not a chore:** nothing counts what is missing or reminds anyone. The lamps can be lit in any order, by any child, or by a contraption chain.
- **Reduce motion:** the chime and the sentence stay; nothing flies.

## 2. Signal rails

- **What a child does:** puts a **Signal rail** in a ring of cart rails and lamps, pinwheels, a music box or a bubble machine within two steps of it, then rides. Each time the cart passes the middle of the signal rail, those things are set off, and pass the spark on as contraptions do.
- **Rules:** a signal rail is a straight rail and a contraption trigger. The authority works out which signals the cart passed between two looks from the route and the distance alone, so the result does not depend on frame timing. A standing cart sets nothing off. A trigger still rests 1.2 s.
- **Reads as:** the post's arm swings and a bell sounds; in Decorate the usual dotted link joins the rail to what it will set off.

## 3. Weather toys

- **What a child does:** puts a **Weather bell** outdoors with things near it, then changes the weather at the weather vane. Every weather bell rings and sets off what stands near it. In windy autumn weather every pinwheel outdoors turns by itself.
- **Cause and effect:** the child who changes the weather reads "The weather bells are ringing!" when there is at least one. The bell's chimes swing and sound for everyone near.
- **Rules:** one ring per change of weather; a wrapped bell does not ring.

## 4. The picture board

- **What a child does:** next to a **Picture board**, **Paint a picture**: a card with the eight paint colors, a rubber, and 8 x 8 squares. A tap paints one square. Friends add to the same picture, and see each other's squares appear while the card is open.
- **Rules:** one square per request, so two children painting at once never lose each other's work. Painting changes what a child made, so, like a music box's notes, it is refused in a place someone else put on display. The picture is saved in the board (64 digits) and comes back with Undo.
- **Uses:** a sign for a snack stand, a decoration, a hand-made clue for a puzzle room.

## 5. Friend echoes

A way to play with friends who are not online at the same time.

- **What a child does:** **Hello** in the menu column: pick three emotes, **Leave it here**. A pale, see-through figure in the child's shape stands at that spot, with the tag "A hello from <name>" in its own color and a ring on the ground under it, so it cannot be taken for a child who is there. (Repaired in candidate `first-steps` r1: in `town-play` r1 the figure was drawn as an exact, opaque double with the child's own name tag; the Mac's rendered picture showed it.) When anyone comes near, it plays the three emotes. A friend standing by it can **Answer the hello** with one emote. The first child finds the answers on their own hello's card next time.
- **Bounded defaults** (implementation defaults chosen by the coordinator within its delegated routine decisions and relayed on 2026-11-13; the user has not reviewed or accepted them personally)**:** one hello per player per town; a new one replaces the old; exactly three emotes from the fixed list of four; one answer per friend, one emote, a second answer replacing that friend's first; the creator can take it away; it disappears by itself after seven days; at most 12 hellos in a town and 8 answers on one (the oldest make room).
- **What is kept:** the child's name and look as the game's fixed lists allow them, the place in the town, the three emotes, the time it was left (to count the seven days), and for each answer a name, one emote and a time. **Not kept:** any sound, any typed text, anything about the real world. The card shows only "It stays for N more days".
- **Expiry and deletion:** old hellos are dropped when a town is loaded, when someone joins, and every ten minutes while a town runs. A hello in a house that is put away goes with it.
- **Saves:** under the optional key `echoes`, written only when there is at least one, so a town without hellos saves exactly as before. A damaged entry is dropped; the rest of the town loads.
- **Unknown until rendered again:** whether the repaired figure reads as "a message from a friend". The tour now checks the picture itself when a renderer draws (the figure's colors against the child's, and the ground showing through), not only properties.

## 6. Animal passengers

- **What a child does:** sitting in a cart at its station, taps an animal friend and chooses **Come for a ride**. It walks over and hops into the little trailer behind the cart. **Go!** takes both round. **Hop out** on its card, or the child getting off, lets it out.
- **Rules:** one animal per cart; the four that fit through a door (not Tumble, who is told kindly). The animal gets in and out at the station only: if the child gets off anywhere, the cart is home at once and the animal hops out beside the platform. A dance party, the child leaving the town or a dropped connection ends the ride the same way.
- **Repaired in candidate `first-steps` r1 after the Mac's pictures of `town-play` r1** (the sheep stood in and through a trailer smaller than itself, tight against the cart): the trailer is a flatbed with a low rim, 0.84 m by 0.95 m, 1.4 m behind the cart's middle (0.37 m clear of the cart), and an animal aboard is drawn sitting, its legs tucked away and its body on the floor. **Unknown until rendered again:** how that looks, on the straight and round a curve.

## How the slices connect

- A ring of rails with a signal rail, a row of lamp posts beside it and the evening bell: riding lights the lamps, and the last lamp brings the fireflies.
- A weather bell next to a puzzle's chest row; a picture board as a hand-made clue.
- An animal riding past a music box set off by a signal rail.

## Controls

| | Touch | Controller (Apple TV) |
|---|---|---|
| Light or put out a lamp post, paint, a hello's card | The action button next to it, or tap it | **X** next to it; pointer and **A** on a card's buttons and squares; **B** closes |
| Leave a hello | **Hello** in the menu column | Pointer and **A** on **Hello** |
| Change the weather | The weather vane, as before | As before |
| An animal for a ride | In the cart at its station, tap the animal, **Come for a ride** | Pointer on the animal and **A** |

No new control was added.

## Network and saves

- **Protocol 13.** New requests: `lamp` (id), `pixel` (id, square, color), `echo_leave` (three emotes), `echo_delete`, `echo_answer` (owner, emote), `echo_seen`, `animal_ride` (kind, on). New events: `ev_lamplight(names)`, `Animals.ev_riders({kind: station})`. Hellos travel with the existing shared-data event (`echoes`). The weather reply gained `bells`.
- **Authority.** The solo device, host or server decides every lamp, square, hello, answer, signal and passenger; clients ask and draw. Signals are worked out from the route and the distance, not from frames.
- **Saves stay schema 2.** New optional data: a board's `pix` (64 digits) in its item; the town's `echoes` (written only when there is one). A lamp's `on` was already saved. Not saved: the evening moment, passengers.
- **Late joiners** get boards, lit lamps and hellos with the town, and passengers right after. The evening moment is not replayed for someone who arrives later.
- A build without the three new kinds drops them on load, as it does any unknown kind; an older build ignores `echoes`.

## As implemented (candidate `town-play` r1)

- **Rules:** `game/scripts/core/lamplight.gd`, `core/picture_board.gd`, `core/echoes.gd` (new); `core/ride_rules.gd` (`SIGNAL`, `signals_between`); `core/contraptions.gd` (triggers "cart" and "weather"); `core/animal_brain.gd` (`start_ride`, `end_ride`, `carry`).
- **Model:** `core/town_model.gd` (`set_pixel`, a board's `pix`, the town's `echoes`); `core/catalog.gd` (Signal rail, Weather bell, Picture board; the station's bounds with its trailer).
- **Authority:** `net/session.gd` (`_srv_lamp`, `_check_lamplight`, `_srv_pixel`, the four echo requests, `prune_echoes`, signals in `_tick_rides`, bells in `_srv_weather`, `_srv_animal_ride`); `net/animals.gd` (`riders`, `request_ride`, `_carry_riders`, `trailer_pose`).
- **Drawing:** `world/echo_world.gd` (new); `world/town_world.gd` (`_on_lamplight`, a board rebuilt when its picture changes); `world/contraption_world.gd` (swinging arm and chimes, pinwheels in the autumn wind); `world/ride_world.gd` (trailer and passenger); `art/props_puzzle.gd` (signal rail, weather bell, picture board, trailer).
- **Controls and UI:** `world/play_controller.gd` (four new actions); `ui/hud.gd` (the board's card, Hello and its cards, the ride row on an animal's card; a closing dialog gives up its name at once so a card can reopen itself).
- **Text:** 46 new strings in six languages; the two CJK font subsets rebuilt.
- **Tests:** `game/tests/town_play_tests.gd`, `game/tests/town_play_tour.gd`, `scripts/net_test.py --townplay`.

## Known limits

- Only lamp posts are lit by hand; indoor lamps are still switched by contraptions only.
- In the evening every lamp already glows, so a lamp lit by hand differs only by its halo.
- Sparks hop every 450 ms while the cart covers about a meter, so effects trail a little behind a moving cart.
- The weather vane and a weather bell can be far apart; only the child who changed the weather is told that bells rang.
- The picture board has 64 small squares; comfort with the TV pointer is unknown.
- A hello's figure is the child's shape in one pale see-through color with its own tag and a ring; whether it reads as a message needs a rendered picture and a child.
- An animal sits in the trailer with its legs hidden; no modeled sitting pose was made. Passengers were tested with the solo authority and through the UI, not with separate client processes (an animal cannot be placed near a cart from a client).
- Tumble cannot ride.
