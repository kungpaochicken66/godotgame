# Animal Friends

Five animal friends live outdoors in the town. They wander, play their favorite games, greet the children and chat with each other. The cast was inspired by the species variety and everyday social play of popular preschool animal casts. Their names, looks and personalities are original to Lantern Lane, and no existing characters, designs or names are copied.

| Animal | Name | Hobby | What it does |
|---|---|---|---|
| Pig | **Pip** | Muddy puddles | Goes to the edge of a pond and jumps up and down (*splash*) with muddy drops flying. With no pond in town, Pip just wanders. |
| Rabbit | **Bramble** | Hopping and gardening | Hops (it never walks) to flower patches, bushes, flower pots and trees, then tends them with its head down while little leaves fly (*garden*). |
| Sheep | **Wooly** | Music and dancing | Visits lamp posts, benches, swings and seesaws and sways while singing, with music notes (*sing*). If a child uses the **Dance** emote within about 10 m, Wooly comes over and spins along (*dance*). |
| Dog | **Biscuit** | Ball games | Plays with a red ball near a child when one is outdoors, otherwise on open lawn. Biscuit kicks it 3–5 m, runs after it and repeats, tail wagging (*ball*, *run*). **Fetch (r9):** tap Biscuit → Play fetch, then tap the ground; the ball flies up to 8 m, Biscuit runs for it and carries it back to that child (*carry*); one child at a time, never during the dance parade. |
| Elephant | **Tumble** | Exploring | Keeps a memory of a 7 × 7 grid over the whole town, walks to the least-visited areas and looks around with its trunk raised (*look*). Near a pond, Tumble sprays water (*spray*). |

Behaviors shared by all of them:
- **Greet:** an animal stops to greet a child who comes within about 2.4 m, at most once every 20 s per child.
- **Chat:** two animals walk over to each other and nod.
- **Rest:** an animal lies down for a moment.
- **Tapped:** tapping an animal makes it hop happily, and a bubble says its hobby, for example "Pip loves splashing in muddy puddles!", in the current language.
- **Name tag:** each animal's name appears when your child is within 4 m.

## House visits (r18)

Pip, Bramble, Wooly and Biscuit can come home with a child. Tumble is too big for the door. The full design and its rules are in [design/animal-visits.md](../design/animal-visits.md).

1. **Invite.** Tap the animal outdoors; its card (game, fetch or wish) offers **Come home with me**. The child must be within 6 m.
2. **Follow.** The animal follows about 1.3 m behind and answers that child's emotes with a move of its own (wave → greet, cheer → sing, dance → dance, heart → chat).
3. **Inside.** It goes through any house door with the child and follows through doors and stairs. Every device showing that room draws it beside the child (`game/scripts/world/guest_world.gd`). It answers emotes made in the room, and tapping it shows its card with **Say goodbye**.
4. **Leave.** After Say goodbye, or when its child leaves or disconnects, an animal that was inside appears at that house's front door and roams again.

**Limits:**
- one visitor per child, and one child per visitor;
- no invitations during the dance party, and none to an animal in another child's game or fetch;
- fetch, other games and wish celebrations never take a visitor away;
- visitors inside stay out of the parade.

**Network and saves:**
- Visits are session state on the authority (`Animals.guests`), sent reliably on every change and to joining players.
- They are never saved.
- The animals' compact state is unchanged. The request `animal_visit` makes this protocol 10.

## A living town (candidate `contraptions-life`, not released)

The animals also notice and use what children place outdoors ([design](../design/contraptions-and-town-life.md)).

| Reason | Things | When | What the animal does | Line over its head |
|---|---|---|---|---|
| music | Music box | playing | dances beside it | "%s loves this music!" |
| snack | Snack tray and snacks | always | sniffs at it | "%s smells a snack!" |
| picnic | Picnic blanket | not raining | rests on it | "%s is having a picnic." |
| shade | Garden umbrella | not raining | rests beside it | "%s likes the shade." |
| rain | Garden umbrella | raining | waits under it | "%s is keeping dry." |
| lamp | Lamp post | evening, or switched on by a contraption | rests in its light | "%s likes the cozy light." |
| bubbles | Bubble machine | just set off | bounces happily | "%s loves the bubbles!" |
| pinwheel | Pinwheel | just set off | watches | "%s is watching it spin." |
| new | Anything | just placed | the nearest free animal walks up and looks | "%s wonders what this is." |
| ball | A toy-track ball | rolling | Biscuit runs to where it ends | "%s is watching the ball roll." |

- Who cares how much is in `game/scripts/core/town_life.gd` (for example Wooly loves music most; Pip never shelters from rain).
- At most two animals use one thing at a time. An animal never goes straight back to the thing it just used.
- A ring marks the thing an animal is busy with, and the animal's card begins with the same line.
- An animal that walks onto a step pad sets it off, while a child is outdoors.
- What each animal is busy with is decided by the authority and shared with every device (`Animals.ev_focus`); it is never saved.
- As before, animals never change the town, never block placement and never stand inside things.

## The zoo's animals (candidate `zoo`, not released)

Fourteen residents of seven species live on the zoo map; see [the game design](game-design.md#the-zoo-candidate-zoo-not-released) and [design/zoo-and-world-journeys.md](../design/zoo-and-world-journeys.md). They are separate from the town's animal friends: they never leave the zoo, never visit houses, and are not adopted.

- **Brain.** `game/scripts/core/zoo_brain.gd`, pure and seeded, steps every 0.1 s on the authority while a player is in the zoo. Ground and water animals follow tables in `zoo_life.gd` (routines with weights, durations and cooldowns, answers to emotes, treats, toys). Monkeys move along `ZooMap.LINKS` between anchors (rocks, the ridge, the Spire, the Ring Run, the vine, the tyre). Clients only draw: they place each animal with `ZooBrain.path_point` from four packed states a second and never roll a choice.
- **Models.** `game/scripts/art/zoo_animal.gd`: rounded, matte, code-built like the town's animals, with two-segment legs, a tail chain, neck, head and jaw pivots. Budgets per animal: at most 20 draw calls and 11 000 triangles (giraffe), 9 000 for a monkey or otter. Bibi is a young monkey at 0.78 scale.
- **Imported meshes (zoo r2).**
  - **What:** the lion, giraffe, zebra, panda, elephant and penguin are the Everything Library's models (CC BY 4.0, `game/assets/models/zoo_everything/`).
  - **How:** `art/zoo_skin.gd` adds a skeleton whose bones mirror the procedural rigs' pivots, at joints measured on each mesh (`art/zoo_skin_rigs.gd`). Weights are deterministic and region-limited, at most 4 per vertex. The same pose code drives them; the new species' poses are in `art/zoo_pose_extra.gd`.
  - **Limits:**
    - no separate jaw (roar and yawn show as a head lift);
    - no eyelids (blink is a small head dip);
    - very large poses stretch a few short edges.
  - **Sizes:** the panda and penguin are drawn at 1.15× and 1.2× for readability.
- **Avoidance (zoo r2).** Every ground and water animal has a footprint circle (`ZooBrain.SPECIES.radius`). A walk that would pass too close to another animal takes a side-step waypoint or waits. Dry-land animals walk around water. No physics bodies are involved.
- **Readability.** Every spot an animal uses is at least 115 px tall on screen from where a child can stand in front of it, at the default view, on the iPad layout.

## How it works

- `game/scripts/core/animal_brain.gd` is a pure simulation with a fixed 0.1 s step and a seeded random generator. It chooses activities (hobby 55 %, chat 15 %, rest 10 %, wander 20 %), steers around other animals and children, and pushes the animals out of solid items, the Wishing Tree and the edges. It never moves an animal into a gap narrower than its body. If an animal stops making progress for 1.5 s it picks a new goal, which also covers an item being placed in its way.
- `game/scripts/net/animals.gd` (autoload) runs the brain only on the authority: the solo device, the hosting device or the dedicated server. Four times a second it broadcasts 6 floats per animal (120 bytes), and every device draws the same animals with smoothing.
- `game/scripts/art/animal.gd` draws each animal from soft primitives, merged into a few meshes, with procedural animation per action and tiny particle effects. Animals only appear outdoors.

## Rules that keep play safe

- Animals are **not** part of the town save, and they never change items, lanterns or anything else that is shared. Each session starts them fresh near the middle of town.
- Animals never block placement: validation ignores them, and an animal steps aside if an item is placed on top of it.
- Children do not collide with animals. Animals keep a little distance from children and from each other.
- Old app versions cannot join a server with animals (`Session.PROTOCOL` 2), and since r18 a protocol 9 app cannot join a protocol 10 server (house visits).

## Tests

- `tests/run_tests.gd` (headless):
  - 240 simulated seconds of roaming in which no animal ever stands inside an item, the tree or off the edge;
  - each animal travels more than 15 m and performs its hobby;
  - greeting a nearby child, the sheep joining a dancing child, the dog playing near a child;
  - stepping aside when an item lands on it; behavior in a bare town;
  - determinism for the same seed, and network packing;
  - checks that the town save is unchanged.
- `scripts/net_test.py`: all five animals arrive at a real client from the server and move; they return after a server restart.
- r18 house visits:
  - `test_animal_visits_brain` and `test_animal_visits_session`;
  - `net_test.py --visits`: real clients, a late joiner, and a disconnect inside;
  - `tests/visit_tour.gd`: the rendered invite, door, room, emote, stairs and goodbye.
- A living town: `test_town_life_rules`, `test_living_brain`, `test_contraptions_session`; `net_test.py --contraptions` (a real client learns what an animal is busy with, and so does a late joiner); `tests/contraption_tour.gd` (the line, the ring and the card, by touch and by controller; logic only on EC2, rendering requested from the Mac).
- The rendered tour (`tests/capture_tour.gd`) shows them in town (`docs/screenshots/godot/animals.png`).

None of this has been seen on an iPhone or iPad yet.
