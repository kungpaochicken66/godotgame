# Toy box browser and picking things in a crowded room

Status: 2026-10-07, being implemented (UI task after release A-H, `4fe1552`). Owner: GameCode lane (UI code, item browsing/query logic, UI tests and UI strings). The catalog entries, models and production records belong to the Modeling lane and are not edited; every filter below is derived from existing catalog metadata.

## Problem

- Inside a house the toy box offers 149 items in two tabs (Cozy things 96, Furniture 53) as one sideways row. Finding a particular item means swiping through dozens of cards; there is no search, count, recent list or filter, and the row loses its place.
- In a furnished room, a tap picks the item whose projected center is nearest, so a cup on a table, a lamp beside a bed or a clock above a shelf is easy to grab by mistake, and there is no other way to reach a hidden item.

## Chosen design (touch-first, same visual style, same height as today)

The toy box stays a bottom sheet of about the same height, so the scene and the placement-tool docking keep working.

1. **Header**: title, a search field ("Find a toy"), the result count ("24 things") and a "Things here" button.
2. **One chip row** that scrolls sideways: categories as tabs (**Recent** when there is one, **Wish** when an animal is wishing, **All**, then the existing categories), followed by placement filters derived from metadata. The filters show only when they would split the current results:
   - **Floor**: ground anchor, not small
   - **Small things**: small items, including everything that fits on a table (`tabletop_eligible`)
   - **On the wall**: `anchor == "wall"`
   - **Ceiling**: `anchor == "ceiling"`
   - **Seats**: `seats > 0`
   - **Tables**: has a `support_surface`
3. **Cards**: thumbnail plus a localized name of at most two lines (ellipsis), sorted by localized name. The last item taken is outlined.
4. **Search** looks at every category of the current space. It matches the localized name and also the English name, ignores case and Latin accents ("cafe" finds "Café"), and works with Chinese and Japanese substrings. Results are ranked: whole name, start of the name, start of a word, then anywhere. Typing waits 0.15 s before refreshing; Enter or tapping a card closes the keyboard.
5. **Empty states**: no match shows "Nothing matches “…”." with **Clear search**. A filter with no items shows **Show all**. A clear (X) button sits in the search field.
6. **Recent**: the last 10 kinds this device placed (saved in `user://settings.cfg`, never in the town save). Placing an item keeps the tab, filter, search and scroll position, so placing the same thing again is one tap.
7. **On-screen keyboard**: while the search field has focus, the sheet rises above the keyboard (`DisplayServer.virtual_keyboard_get_height`) and the chip row stays visible.
8. **Feedback**: the placement tools show the item's name; Cancel on a new item says "Back in the toy box."; a placed item updates Recent.

### Crowded scenes

- **Which one?** In decorate mode, when a tap lands on more than one item and none is clearly closest, a small chooser near the finger lists up to four of them (thumbnail and name; "on a table" for table-top items). Nothing is picked up until the child chooses. A clear hit still picks directly.
- **Things here**: a list of every item in the current room or the town, nearest first, with thumbnails and names. Tapping a row picks that item up for moving, turning, painting or putting away, just like tapping it in the scene. Items another friend is moving are shown as busy.
- No labels float over items, so nothing new can overlap.

Unchanged: save ids and layouts, undo, the authoritative placement rules (walls, table tops, overlaps), locks and every network message.

## Acceptance examples

| # | Given | When | Then |
|---|---|---|---|
| 1 | Living room, English | open Decorate | "All" shows the count of every indoor item; the chips show Furniture, Cozy things and the placement filters |
| 2 | Any locale | type the localized name of the wall clock (part of it) | the wall clock is among the first results; the count matches the cards |
| 3 | Spanish | type "cafe" or "CAFÉ" | items whose Spanish name contains "café" appear |
| 4 | Any | type "zzqx" | "Nothing matches" and **Clear search**; Clear brings back the previous tab and its scroll position |
| 5 | Cozy things | tap **On the wall** | every card is a wall item; the count drops; **All** resets |
| 6 | Any | place a chair, then tap its card again | a second chair is placed; Recent lists the chair first; the toy box did not jump |
| 7 | Crowded table (cup on a table next to a lamp) | tap between them | the chooser lists the candidates; choosing the cup lifts only the cup |
| 8 | Any furnished room | open **Things here**, tap a row | that item is lifted for editing; Cancel puts it back unchanged |
| 9 | iPhone landscape with insets, iPad 4:3 | all of the above | the sheet, chips and chooser stay inside the safe area; touch targets at least 56 px; the sheet clears a simulated keyboard |
| 10 | Large-catalog test fixture (2,000 generated entries, test only) | search and filter | each query finishes well under one frame; fixture entries never appear in the game |
