# Design: animal friends visit a child's house (r18)

Status: written 2026-10-10 before implementation; implemented in candidate r18 (see "As implemented"). Not released. Owner: GameCode lane. It uses the existing five town animals, their procedural art (`game/scripts/art/animal.gd`) and the existing rooms. No new art, currency or system; no Modeling dependency.

## The visit loop

1. **Invite (outdoors).** Tapping Pip, Bramble, Wooly or Biscuit opens its existing card (its game card, or Biscuit's fetch card). The card now also offers **Come home with me**.
2. **Follow.** The animal walks after the child through town, about 1.3 m behind. While it follows, it answers that child's emotes with a move of its own: wave → greet, cheer → sing, dance → dance, heart → chat. This is the existing call-and-response game (`AnimalBrain.COPY`), here for every visitor.
3. **Inside.** When the child goes through any house door, the animal comes in too. Every device that shows the child's room draws the visitor near the child. It follows the child through doors and up and down the stairs, like a following pet.
   - Indoors it still answers emotes from children in the same room.
   - Tapping it makes it hop and shows its card: its hobby, the emote tip and **Say goodbye**.
4. **Leave.** **Say goodbye** (indoors or outdoors) ends the visit.
   - If the animal is inside, it appears at that house's front door outdoors and goes back to roaming.
   - If the child walks back outside with it, it keeps following until they say goodbye.

## Rules (authority)

- Only the authority (solo device, host or server) starts and ends visits, and it decides between requests that arrive together.
- **Limits:**
  - one visitor per child, and one child per visitor (a second invitation for the same animal is refused kindly);
  - Tumble the elephant (body radius 0.8 m) does not visit: "Tumble is too big for the door, but loves to play outside.";
  - invitations happen outdoors, within 6 m of the animal;
  - an animal in another child's game, or bringing back someone else's fetch ball, is busy;
  - while the dance party runs, nobody can be invited;
  - inviting an animal that is in your own game ends that game.
- **Leaving and disconnects:** a visit ends when its child leaves or disconnects. An animal that was inside appears at that house's front door and roams again. Nothing is stranded indoors, duplicated or hidden.
- **The dance party:** animals following outdoors join the parade as usual and keep following afterwards. Visitors inside stay inside.
- **Saves:** visits are session state, like animals and seats; they are never saved. Old saves load unchanged (schema 2).

## Network

- The authority keeps `Animals.guests` ({animal: peer}) and sends it reliably whenever it changes, and to every player who joins (late join).
- The animals' compact state (6 floats each, 4 times a second) is unchanged.
- A device hides the outdoor animal while its child is in a room, and draws it in that room instead (the pet pattern: shared data plus the child's position). Every device in the room sees the same visitor following the same child.
- A new request `animal_visit [kind, on]` is added. **Protocol 9 → 10**: a new request and a new event, so old apps and servers refuse each other kindly.
- **A release must update the app and the HK server together.** The live server is not touched by this candidate.

## Words (six locales)

- Buttons: "Come home with me", "Say goodbye".
- Messages:
  - "%s is coming home with you!"
  - "%s went back outside."
  - "Do an emote and %s answers with a move!"
  - "Invite animal friends outdoors."
  - "Walk closer to invite them."
  - "They are already visiting a friend."
  - "One animal friend at a time can come home with you."
  - "Tumble is too big for the door, but loves to play outside."
  - "They are busy playing. Try again in a moment."
- Existing: "Everyone is at the party!".

## Acceptance

**Unit tests (brain):**
- following;
- away while the child is indoors, with the animal kept out of other animals' steering and the parade;
- back at the child's side or at the door;
- busy rules, the parade, ending a game, determinism.

**Session tests:** every refusal, one visitor per child, a leave or disconnect releasing the visitor at the door, a reload with no visitors.

**Network (`net_test.py --visits`, real clients):**
- A invites Pip and walks into the house; B in the same room draws Pip next to A.
- A late joiner learns the visit.
- A disconnects inside, and everyone sees Pip back outdoors at the front door.

**Rendered tour (`visit_tour.gd`):**
- the invitation card;
- Pip following in town;
- Pip in the living room, answering an emote;
- after the stairs, in the room above;
- Say goodbye, and Pip back outside.

## As implemented (r18)

**Code:**
- `AnimalBrain`: `start_visit`, `end_visit`, `guest_of`, the "visit" plan and `away` state, and guards in fetch, games, wish celebrations, chats and the end of the parade.
- `Animals` autoload: `guests`, `request_visit`, `end_visit`, release on departure, `ev_guests`.
- `Session`: `animal_visit` and `PROTOCOL` 10.
- World and UI: `guest_world.gd` (indoor drawing and tapping), `TownWorld.visiting_indoors` / `space_of`, and the HUD buttons and visitor card.

**Addition to the plan:** the invitation is also on an animal's **wish card**. A wishing animal's tap shows that card first, so without it a wishing animal could not be invited.

**A client's own position:** a client's own entry in `Session.players` is not updated by its own moves, so a device places its own child's visitor by the room it is viewing.

**Modeling:** no dependency. The procedural animal art is drawn indoors as it is.

**EC2 results:**
- units 21332/0, including `test_animal_visits_brain` and `test_animal_visits_session`;
- `net_test.py --visits` PASS (32 checks);
- `visit_tour.gd` headless 37/0, twice.

**Mutations:**
- departure release plus the wish guard off: 4 failing checks;
- away-while-indoors off: 8;
- outdoor hiding off: caught by `--visits` (the late joiner outdoors).

**r18b (Mac r18 result: FAIL, repaired in the test only).**
- On the Mac, the visit tour's press on **Come home with me** never fired: no message, and the card stayed open over shots 01-04, blocking the rest of the tour.
- The inherited `pets_tour.tap` sends only a press and a release. A disposable probe that injects one pointer motion away from the button between them reproduces the Mac PASS/FAIL sequence line for line (0 `pressed` signals).
- `visit_tour.gd` now moves the pointer to the point before the press and again before the lift, as `guide_tour` did in r16b. With the same stray motion it passes.
- Classified as consistent with desktop-cursor interference, reproduced synthetically; the OS cause is not proven. Product code is unchanged, and no assertion changed.

