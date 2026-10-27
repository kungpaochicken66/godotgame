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
- The rendered tour (`tests/capture_tour.gd`) shows them in town (`docs/screenshots/godot/animals.png`).

None of this has been seen on an iPhone or iPad yet.
