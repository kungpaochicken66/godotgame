# Pets, themed rooms, cooking and Photos (r7 plan)

Status: 2026-10-07, implemented in candidate r7 (uncommitted) on top of the r6 tree (multiplayer invites, private deployment, activity guide and toy box browser are kept). Owner: GameCode lane. Asset interface for the Modeling lane: [pets-rooms-assets.md](pets-rooms-assets.md).

## Audit (before r7)

| Room | Promised by its name | In the toy box before r7 | Missing |
|---|---|---|---|
| Kitchen (floor 1) | counter, stove, sink, fridge, pots and pans, utensils, plates, ingredients, food | curved counter, fish skillet, kitchen scale, many prepared foods (all under "Cozy things") | stove, sink, fridge, pot, pan, utensils, plates, raw ingredients; no way to cook |
| Playroom (floor 2), shown as **Game room** from r7 | tablet or handheld, console and controller, TV, desk, seats, storage | three arcade cabinets | everything else |
| Attic (floor 3), shown as **Pet room** from r7 | pet beds and houses, bowls, scratching and climbing furniture, toys, bird and butterfly spots | none | everything; there were no pets |

Room names are labels keyed by floor and room number, so renaming them keeps every save.

## Implementation order (bounded)

1. Room themes: new procedural items (code-built in the existing style) for kitchen, games and pets; a theme table that also lists suitable existing items (r1 food, skillet, arcade cabinets, fish and butterfly models); theme tabs **Kitchen**, **Games**, **Pets** in the toy box, opened first in the matching room; the Attic and Playroom are renamed Pet room and Game room.
2. Starter set (changed while implementing): a Kitchen, Game room or Pet room that lacks its key item (stove; TV, console or tablet; pet bed or house) offers **Set up the kitchen / game room / pet room** on the action button. One tap adds only the missing starter pieces into free spots (nothing is moved or removed) and is offered once per room. It is a choice, not automatic, so existing rooms and saves never change by themselves.
3. Pets: cat, dog, bird and butterfly, as the ten modeled, rigged pets of batch p001 (three cats, three dogs, two birds, two butterflies). Adopt and name one in the **Pets** dialog (button under Activities), choose which one follows you, send it home to the Pet room, pet it, feed it at a bowl. The authority owns adoption and selection; pets follow their owner through town and rooms (drawn by every client from the owner's position), never block walking or taps, and rest in their owner's Pet room when sent home. Saved in the town under the owner's device player id.
4. Cooking: stand at a stove, tap **Cook**, choose a recipe whose ingredients are in this room (rice sack, egg basket, vegetable basket; a pot or pan for soup and eggs). The authority checks and cooks for 3 seconds (steam and a progress ring), then puts the dish on a free spot next to the stove as a real item. Tap it and **Eat**: a happy cheer and the dish is gone; cook again any time. Dishes are saved; cooking counts per player are saved.
5. Photos: on iOS a native plugin (`ios/plugins/photo_library/`) asks for add-only Photos access and saves the picture; the game says "Saved to Photos" only after the system reports success, and offers **Try again** and **Open Settings** after a denial or error. Other platforms keep saving to the game's own folder. Built and verified on the Mac.
6. Tests and a frozen candidate.

## Acceptance examples

| # | Given | When | Then |
|---|---|---|---|
| 1 | New town, any locale | Pets → Adopt → cat, orange, name | a cat follows the child, also through doors and stairs, and never blocks a tap or the path |
| 2 | Two players online | B adopts a dog | A sees B's dog behind B (not behind A); B leaves: the dog leaves with B; B rejoins: the same dog |
| 3 | Pet following | Send home | the pet walks in its owner's Pet room near a pet bed; visitors see it there |
| 4 | Pet near a food bowl | tap the pet → Feed | happy hearts; without a bowl in reach the pet card says to bring it to a bowl |
| 5 | Kitchen of a new town | open Decorate | the Kitchen tab is first and lists stove, sink, fridge, counter, pot, pan, utensils, plates, ingredients and dishes; search "stove" finds it |
| 6 | Kitchen with stove and rice sack | tap the stove → Rice bowl | 3 s of steam, a rice bowl appears next to the stove for everyone; tap it to eat: it goes with a cheer (recipes: rice bowl, vegetable soup, fried egg, rice and stew) |
| 7 | Kitchen without eggs | Cook | the egg recipe is shown greyed with "Needs: egg basket"; a request for it is refused by the authority |
| 8 | Two players at one stove | both tap Cook | one cooks, the other is told the stove is busy |
| 9 | Game room | Decorate | Games tab first: TV, console with controller, handheld tablet, gaming desk, bean bag, game shelf, arcade cabinets |
| 10 | iPad, Photos access allowed | take a photo | "Saved to Photos" after the system confirms; the picture is in Photos |
| 11 | iPad, access denied | take a photo | a message with Try again and Open Settings; the picture stays in the game scrapbook |
| 12 | Old save (r6 or earlier) | load | everything loads unchanged; empty themed rooms get their starter set once; no pets until adopted |
