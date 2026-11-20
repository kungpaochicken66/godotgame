# Design: contraptions and a living town

Status: written and implemented 2026-11-11 as candidate `contraptions-life` r1 (see "As implemented"). Not released, not rendered on a GPU, not run on an iPhone, iPad or Apple TV. Owner: GameCode lane (EC2). Art is code-built in the existing primitive style; no new model, texture, sound or font source was added.

Two directions from the 2026-11-11 gameplay brainstorm, chosen by the user:

1. **Contraptions:** things that set off other things. Until now every placed thing answered only the child who used it.
2. **A living town:** the animal friends notice and use what children place outdoors. Until now they followed fixed hobbies and visited a child only when asked.

Both keep the existing pillars ([game-design.md](../docs/game-design.md)): everything is free, nothing is scored or timed, nothing can be lost, there is no typed text, and every action works by touch and by one controller.

## What was already there (and is not claimed as new)

- Toy tracks roll a ball along connected pieces; bell and light pieces ring and light up as it passes ([playability-8-12.md](playability-8-12.md) F02). They answered the ball only.
- A music box plays for everyone nearby and lamp posts close to it glow on the beat (F08).
- Each animal already walks to kinds of things it likes: Wooly to lamp posts, benches and swings; Bramble to plants and garden beds; Pip to ponds ([animals.md](../docs/animals.md)). It stood near them and did its hobby. It did not react to a thing being placed, switched on or set off, and nothing on screen said why it was there.
- Animal wishes ask for one arrangement and reward it once.

## 1. Contraptions

### The loop

Place a **trigger** near a **reactor**, set it off, watch the chain, then move things to make it longer or different.

| Triggers | How they are set off |
|---|---|
| **Big button** (new) | The context action **Press**, standing next to it; or a tap on the button, which walks over and presses it |
| **Step pad** (new, flat) | A child walks onto it. Outdoors, an animal walking onto it sets it off too, while a child is outdoors |
| Bell track, Light track, Track finish | A rolling toy-track ball passes or arrives |

| Reactors | What they do |
|---|---|
| Every thing with a lamp of its own (37 kinds: lamp post, floor and desk lamps, wall lamps, ceiling lights) | Switches on, or off if it was on. A lamp switched on shines by day too. Saved with the town |
| Music box | Starts, or stops if it was playing. Saved (as before) |
| Track start | Rolls its ball. Its bell, light and finish pieces are triggers again |
| **Pinwheel** (new) | Spins for 5 s |
| **Bubble machine** (new) | Blows bubbles for 5 s |

### Rules

- **Linking is nearness.** Two things are linked when they are in the same space and their centres are at most 2.0 m apart on the floor plan. A ceiling light is linked to the button under it.
- **A spark hops.** A trigger sends a spark to every reactor linked to it. 450 ms later each of those reacts and sends a spark to every reactor linked to *it*. So a row of things 1.5 m apart answers one after another.
- **Each thing once.** A chain touches a thing at most once, and at most 24 reactors. A ring of things cannot run forever.
- **A trigger rests** for 1.2 s after it is set off. Pressing again in that time does nothing and breaks nothing.
- **The town as it is now.** Each hop looks at the town when its spark lands. A thing put away mid-chain is skipped; a thing moved closer joins.
- **Play, not decoration.** Setting things off works in a place that is "On display", like starting a music box.
- **Wrapped presents** take no part.
- **Standing on a step pad** sets it off once. Stepping off and on sets it off again.
- A lamp's switch has no button of its own in this version: lamps are switched by contraptions only.

### How it reads

- While **decorating**, a dotted orange line with an arrow head joins every linked pair in the space on screen. Lines disappear in play.
- After placing a trigger with something in reach, the message is "Placed! Linked things: N".
- Pressing a button with nothing in reach says what to do: "Nothing is close enough yet. Put a lamp, a music box or a pinwheel within two steps."
- A button's dome and a step pad's top dip when set off. A small glowing spark arcs from each thing to the next.
- The toy box has a **Contraptions** tab with the four new things, lamps, the music box and the track pieces, and the idea line: "Idea: put a Big button next to a lamp, a music box or a pinwheel. Things within two steps pass the spark on."

### Reduce motion

With **Reduce motion** on (the existing setting), no spark flies, the pinwheel does not turn and no bubbles are drawn. Each thing still answers in order with a short swell, and lamps and music switch as usual.

## 2. A living town

### The loop

Place or switch on something outdoors, see who comes and what they do with it, and arrange the town for them.

### What the animals do

| Reason | Things | When | The animal | Who cares most |
|---|---|---|---|---|
| music | Music box | It is playing | dances beside it | Wooly, then everyone |
| snack | Snack tray, cookie, sandwich, juice | always | sniffs at it (new pose) | Pip, then Biscuit and Tumble |
| picnic | Picnic blanket | not raining | rests on it | Biscuit, Wooly, Pip, Bramble |
| shade | Garden umbrella | not raining | rests beside it | Bramble, Wooly, Biscuit |
| rain | Garden umbrella | raining | waits under it | Bramble and Wooly, Biscuit, Tumble. Never Pip, who prefers puddles |
| lamp | Lamp post | evening, or switched on by a contraption | rests in its light | Tumble, Wooly, the others |
| bubbles | Bubble machine | just set off | bounces happily | Tumble, Biscuit, Pip, the others |
| pinwheel | Pinwheel | just set off | watches | Bramble, Tumble, Biscuit |
| new | Anything placed outdoors | just placed | walks up and looks | the nearest free animal |
| ball | A toy-track ball | it rolls | Biscuit runs to where it ends and waits, wagging | Biscuit |

### Rules

- **Using.** When an animal chooses what to do next and something it cares about is in town, half the time it goes to use it (weighted by how much it cares) instead of its own routine. It stays 4 to 10 s and moves on. It never goes straight back to the thing it just used.
- **Noticing.** When a child places something outdoors, the nearest free animal within 14 m comes to look. Each animal rests 12 s between such looks, so placing ten things does not make a parade.
- **Lively things.** When a music box starts or a bubble machine or pinwheel is set off, the free animals within 14 m that love it (fondness 2 or more) come at once. A set-off thing stays lively for 12 s.
- **No crowds.** At most two animals use one thing at a time.
- **Honest.** If the thing is put away, wrapped, or stops being worth it on the way (the music stops), the animal gives up at once. If a child moves it, the animal follows it.
- **Never in the way.** As before, animals never change the town, never block placement, are never saved and never stand inside things. A visiting animal stays with its child. The dance party outranks everything.
- **Crossover.** An animal that walks onto a step pad sets it off. A lamp switched on by a contraption counts as lit for the animals. A bubble machine set off by a contraption draws Tumble.

### How it reads

- While an animal is busy with something a child made, the name over its head becomes a line in a warmer color, visible from any distance outdoors: "Wooly loves this music!", "Pip wonders what this is."
- A soft pink ring lies under the thing it is busy with.
- Its card (a tap on the animal) begins with the same line.
- With Reduce motion on, the ring does not pulse.

## Network and saves

- **Protocol 11** (was 10). New request `press` (one argument: the button's id). New events `ev_trigger(id)`, `ev_react(id, from, effect, on)` and `Animals.ev_focus({species: {id, why}})`. Animal states gained a 15th action, `sniff`, appended so older indices keep their meaning.
  - A protocol change means every app and the town server must be updated together. The paused R21 branch (`r21-photo-wall-paused`) also uses protocol 11 and schema 3 for different changes; it must take the next free numbers when it resumes.
- **Authority.** The solo device, host or server decides everything: who may press, the order and timing of a chain, each toggle, what each animal is busy with. Clients ask and draw.
- **Saves stay schema 2.** A lamp gains the optional field `"on": true` only while it is switched on, so a town without contraptions saves byte for byte as before. Loading drops `on` from anything that is not a lamp or a music box. The four new kinds are ordinary items. A build without them drops them on load, as it does any unknown kind.
- **Not saved:** sparks in flight, a trigger's rest, lively things, what animals are busy with.
- **Late joiners** get lamp and music state with the town, and what the animals are busy with right after.
- **An empty town stays quiet.** Animals set off step pads only while a child is outdoors, so a server with nobody on it does not switch lamps and save itself.

## Controls

| | Touch | Controller (Apple TV) |
|---|---|---|
| Press a button | The action button **Press** next to it, or tap the button | **X** next to it (the hints show Press) |
| Step pad | Tap the ground to walk onto it | Left stick |
| See links | **Decorate** | Pointer and **A** on Decorate; **B** leaves |
| Place the new things | Toy box, **Contraptions** tab | Pointer and A on the tab and card, left stick to move, **+** to place |
| An animal's card | Tap the animal | Pointer on the animal and **A** |

No new control was added. No text is typed.

## Accessibility and audience

- Every reaction has a visible state change that stays (a lamp on, a music box's beat lights), not only a motion or a sound.
- Sparks and links are orange on grass or floor and are doubled by shape (dots and an arrow head), so they do not rely on color alone.
- Lines over animals are short sentences in the six languages; Japanese uses kana, as elsewhere.
- Nothing flashes. Lamps switch once per chain.
- Not measured: whether an 8-year-old discovers linking without help. The brainstorm's playtest (give a child the pieces with no explanation and see whether a two-step chain appears within five minutes) is still to be done by the user.

## Implementation and acceptance plan

| # | Step | Evidence |
|---|---|---|
| 1 | Pure rules: `core/contraptions.gd`, `core/town_life.gd`; lamp state in `core/town_model.gd`; lamp list in `core/catalog.gd` | `run_tests.gd`: `test_contraption_rules`, `test_town_life_rules` |
| 2 | Animal brain: use, notice, lively things, the rolling ball, focus | `test_living_brain` (deterministic, seeded) |
| 3 | Authority: `press`, sparks one hop at a time, step pads, ball triggers, hooks to the animals; protocol 11 | `test_contraptions_session` |
| 4 | Four code-built things and their catalog entries (scale contract) | `test_scale_contract`, `test_catalog`, `test_contraption_rules` |
| 5 | Drawing: `world/contraption_world.gd`, lamps on by day, animal lines and rings; Press; links in Decorate; the toy box tab | `tests/contraption_tour.gd`, touch |
| 6 | Controller and TV path | `tests/contraption_tour.gd --tv` |
| 7 | Six locales and fonts | `scripts/check.py`, `tv_check.py`, the tour's per-language case |
| 8 | Real clients: same chain on every device, a far press refused, a step, a late joiner, restart | `scripts/net_test.py --contraptions` |
| 9 | Regression: every existing unit, network and logic tour still passes | `scripts/test_all.sh --quick`, the other `net_test.py` modes, the headless tours |
| 10 | Seal a complete candidate; request Mac import, GPU renders and tvOS validation | `scripts/model_handoff.py seal`, `LOCAL_VALIDATION_REQUEST.md` |

**READY_FOR_LOCAL_VALIDATION** when 1 to 10 are done on EC2. **Not part of this state:** GPU rendering, reading of the returned images by the author, tvOS on the Apple TV, and any iPhone or iPad run. Those stay pending and are requested from the Mac.

## As implemented (candidate `contraptions-life` r1)

- **Rules:** `game/scripts/core/contraptions.gd`, `game/scripts/core/town_life.gd`.
- **Model:** `TownModel.set_lamp_on`, optional `on` on lamps; `Catalog.LAMPS` (checked against the built items by a test, so a new lamp cannot be forgotten).
- **Brain:** `animal_brain.gd` plans `use` and `notice`; `notice()`, `enliven()`, `watch_ball()`, `focus_map()`; action `sniff`.
- **Authority:** `session.gd` `_srv_press`, `fire_trigger`, `_spread`, `_tick_contraptions`, `_react`, `_roll`, `step_on_pads`; `animals.gd` `item_placed`, `enliven`, `watch_ball`, `ev_focus`.
- **Drawing:** `world/contraption_world.gd`; `town_world.gd` `lamp_on`, `lamp_level`, `_apply_switched_lamps`; `art/animal.gd` `set_line`; `art/props_contraption.gd`.
- **Controls and UI:** `play_controller.gd` (Press, links with the mode, the placement message), `hud.gd` (the busy line on animal cards), `room_themes.gd` (the Contraptions tab).
- **Text:** 21 new strings in six languages; the two CJK font subsets were regenerated with `scripts/build_fonts.py` (6 new Chinese characters).

Differences from the brainstorm's prototype sketch:

- The prototype proposed three triggers (doormat, bell, track finish) and three reactors linked within 1.5 m. Implemented: five triggers, five reactor effects (37 lamp kinds), 2.0 m, so things with a 0.45 m footprint can stand side by side and still link.
- The prototype proposed two animals reacting to three kinds. Implemented: all five animals and ten reasons.
- Benches and other seats are not attractions: a seat taken by an animal would take it from a child.
- Animals do not eat snacks: they never change the town.

## Known limits

- Linking by nearness means everything within 2 m joins the chain; there is no way to keep two close things apart except moving them.
- A lamp cannot be switched by tapping it.
- Chain timing is the authority's; a client with a slow connection sees hops late but in order.
- The line over an animal can be long in German and French (up to about 40 characters). Its size and overlap with other labels need the Mac's rendered images.
- Daylight readability of a switched-on lamp (the halo), the spark, the links and the ring are untested on a GPU.
