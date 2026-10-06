# Lantern Lane — Game Design

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
| Animal friends | Pip the pig, Bramble the rabbit, Wooly the sheep, Biscuit the dog and Tumble the elephant roam outdoors and play their hobbies; tap one to see what it loves ([animals.md](animals.md)) | Yes |
| Music | A gentle original loop outdoors, softer on menus and indoors; music on/off and volume, sounds on/off ([assets.md](assets.md)) | Yes |
| Explore | A 52 × 44 m town: the original center plus a west grove, an east meadow with a second pond, a north orchard and trails | Yes |
| Play | Swing (sway), seesaw (two riders), bench and sofa (two seats), chair, bed (rest) | Yes |
| Cozy Spots | 8 recognized arrangements, a celebration, a lantern on the Wishing Tree, credit to everyone present | Yes |
| Evening | The bell at the Wishing Tree switches the shared time of day; lamps, windows, lanterns and fireflies glow | Yes |
| Emotes | Wave, cheer, dance, heart, seen by everyone | Yes |
| Scrapbook & photo | Lanterns lit, hints for unfound spots, photos taken this session | Yes (photos are saved on the device; the in-game album lists only this session's photos) |

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

### Toy box (30 items)

Nature: round tree (leaf color can be painted, for example blossom pink), pine, berry bush, flower patch. Paths & water: stepping stone, pond, lamp post, fence. Play: swing, seesaw, bench, picnic blanket. Homes: cottage. Furniture (indoors, and chairs and tables outdoors too): bed, chair, round table, sofa, bookshelf. Cozy things: rug, flower pot, floor lamp, teddy bear. Modeled furniture (from the reviewed pilot-10 set): scallop chair, cozy round table, scallop bed, writing desk, open shelf, curved counter, desk lamp, blooming flower pot. A wall clock and a bird mobile have been modeled but are not placeable until wall and ceiling placement exists.

## Rules that settle earlier open questions

- **Joining:** one town per server. Up to four children; a fifth is told kindly that the town is full. Solo play uses a separate town on the device.
- **Shared edits:** picking up an item locks it for others, who see "<name> is decorating here". Occupied seats and houses with someone inside cannot be moved or put away. Locks and seats free up when a player leaves.
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

Placement tools: normally the Turn / Paint / Put away / Cancel / Place buttons sit above the toy box. When the item being placed or moved would be hidden behind them (judged from its projected screen footprint), the tools move under the top bar and the toy box tucks away. They come back once the item is clearly clear of that area again. A dwell time and a hysteresis margin prevent jumping back and forth, and the camera holds still while a finger drags an item. Positions respect the device safe area. Main controls are 68–96 px and tabs and swatches 56–60 px at the 1366×1024 base resolution (about 44–70 pt on a 12.9" iPad; not measured on a device). Pinch zoom uses magnify gestures (not verified on device).

## Art direction

Sizes follow the canonical scale contract in [design/object-scale-and-surfaces.md](../design/object-scale-and-surfaces.md): 1 unit = 1 m and child height H = 1.30. Ordinary trees are about 1.85 H. Large furniture is clearly bigger than a chair. Small decorations are about 0.35–0.4 H, so they read well and fit on a table. The Wishing Tree and the cottages stay landmark-sized.

Everything is generated from code (`game/scripts/art/`): rounded boxes with exact normals, spheres, capsules and cylinders with soft matte materials. There are no textures, so silhouettes and color carry the look. Real-time shadows are off: soft blob shadows ground every object (see the environment report for why). The camera is close and tilted at 40° (direction A from the preview), with 45° turns and two zoom levels. Interiors use a dollhouse cut-away with the front and right walls removed, and each room has its own gentle wall tint. Cottages are three stories tall outside (trim bands, windows on every floor, a balcony, a round attic window) on the original footprint. The palette follows `docs/design-spec.md`.

## Localization

All UI text is English source passed through Godot's `TranslationServer`. The game uses the same JSON key format as the preview, in `game/locale/`, for en, zh-CN, ja, es, fr and de, with English as the default. Language can be switched from the title or in game at any time without losing the town or a placement draft. Bundled OFL fonts: Nunito (Latin), M PLUS Rounded 1c (Japanese) and Noto Sans SC (Chinese), with CJK subset to the catalog characters. The fallback order depends on the locale, so Chinese uses Chinese glyph forms. The app name is localized for the home screen. Translations have not been reviewed by native speakers; see the handoff for specific choices to review.

## Next content ideas (not implemented)

Creator-designed items (drawings turned into new builders), more spots (garden party, music corner), weather, a mailbox for leaving emoji notes, seasonal lantern colors, and a shared town photo wall.
