# Design: first steps and a way into the newer play

Status: written and implemented 2026-11-13 as candidate `first-steps` r1, on top of the sealed `town-play` r1. Not released, not rendered on a GPU, not on any device. It comes from the [experience plan](experience-plan.md), issues 1 and 10, both found by reading the game as a new child would meet it. No protocol change (13), no save change, no asset file.

## The two player problems

1. **A new child was told nothing on arrival.** After the menus the town appeared with its buttons and no first instruction.
2. **The Activities guide did not know the newer play.** Contraptions, puzzle rooms, cart rides, lighting lamps, the picture board and hellos could be found only by opening the right toy box tab.

## 1. First steps

One short line at a time, top center, with a small icon and a button to hide it:

| Step | Line | Done when |
|---|---|---|
| walk | "Tap the ground to walk there." With a controller in use: "Move with the left stick." | the child has walked 2.5 m |
| build | "Open Decorate to build something." With the toy box open: "Pick a thing, then choose Place here." | a first thing is placed |
| guide | "Open Activities for ideas to play." | the guide is opened |

- After the last step: "You know the basics. Have fun building!", once. Then nothing, ever again on this device.
- Steps can be done in any order; the first one still open is shown.
- **Hide** puts the line away for good.
- The line is never shown over the menus, over a dialog, or while an activity's own chip (hide-and-seek, dance party) is there; landmark name tags keep clear of it. While a thing is held it steps aside (`first-steps` r8): the placement tools may stand under the top bar, and their own line then says what to do.
- Remembered in the device's settings (section `first_steps`), not in the town and not on the server: it is about this child on this device.
- **A child who already plays is not a beginner:** a device with nothing stored for first steps whose toy box already remembers recently placed things starts with every step done.
- The lines name the buttons as each language shows them.

## 2. The guide's second section

The guide (**Activities**) now has two sections, chosen by two buttons at its top: **Things to do** (the eight activities, unchanged, shown first every time) and **Things to build**, with six cards in the same form as the eight: a picture drawn in code, where to start, two or three steps in the buttons' own words, how to tell it worked, alone, with friends, and one button that leads into the game.

| Card | Its button |
|---|---|
| Contraptions | **Open the toy box**: Decorate, on the Contraptions tab, with its idea line |
| Puzzle rooms | the same, on the Puzzles tab |
| Cart rides | the same, on the Rides tab (indoors: "Those things go outdoors. Go outside first.") |
| Evening lamps | **Go there**: walks to the evening bell |
| Picture board | **Open the toy box**, on the Puzzles tab |
| A hello for friends | **Leave a hello** |

In a place on display by someone else, **Open the toy box** brings up the usual question instead, as Decorate always does.

## Also in this candidate: repairs after the Mac's first look at `town-play` r1

The Mac ran `town-play` r1 (which stays sealed and unchanged) and returned original pictures and logs. This candidate carries the repairs:

| Finding on the Mac | Kind | Repair here |
|---|---|---|
| A hello's figure was an exact, opaque double of the child, same name tag (`town_play_ipad_09_hello_figure.png`) | blocking, visual | One pale, see-through material on every part (ordinary alpha blending, which every renderer draws), the tag "A hello from <name>" in another color, a ring under it. The tour now checks the picture itself when rendered |
| The puzzle tour failed at the iPhone layout: after a wish arrived, the card under the same place was another thing | deterministic, function | The toy box row jumped to a remembered place that differed from the screen. A rebuild of the same view now keeps the row where it is; a return to a tab's remembered place is repeated until it holds; memory and screen are kept equal. The tour sets up the Mac's state on purpose and fails on the old code |
| The sheep stood in and through a small trailer tight against the cart | review | A flatbed trailer with a low rim, further back; the animal aboard sits with its legs tucked away |
| The idea panel hid the child; the right-hand column lay over the turn and zoom buttons | review (known issues) | The Puzzles and Rides idea lines are at most three lines in every language; when the column would reach the camera buttons, they move up at the right edge and end just above it (a first repair stepped them left of the column; at the TV layout that put them on the toy box's corner) |
| The three-line idea panel still hid the child (Mac, `first-steps` r1, iPhone and Metal TV) | blocking | r2: the panel steps to the side of the child that has room, or up under the top bar, whenever it would cover the child; checked by rectangles against the child's own meshes on every tab with an idea line |
| The docs said the user set the echo defaults | correction | They are implementation defaults chosen by the coordinator within its delegated routine decisions; the user has not reviewed them personally. The docs say so now |

## What is not known

- How the line and the six new pictures look: they were drawn without ever being rendered. This is the first thing to look at on the Mac.
- Whether a child reads the line, and whether three lines are the right three. Only a child can say.
- The first step by controller says "left stick"; the Siri Remote has none. A child with only the remote sees the touch wording until a controller is used. Not addressed here.

## As implemented (candidate `first-steps` r1)

- `game/scripts/core/first_steps.gd` (new, pure state); `game/scripts/ui/hud.gd` (the line, its hooks, the guide's sections and Go actions; the line's container is centered whatever its length); `game/scripts/main.gd` (the HUD is given the controller layer; test drivers run without the line unless they ask for it with `--first-steps`); `game/scripts/ui/activity_guide.gd` (`MAKE`); `game/scripts/ui/guide_art.gd` (`MAKE_SCENES`).
- 59 new strings in six languages; the two CJK font subsets rebuilt.
- Tests: `game/tests/first_steps_tests.gd`, `game/tests/first_steps_tour.gd`.
