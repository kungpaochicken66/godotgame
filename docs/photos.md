# Scrapbook photos on the device (r16)

The camera button saves a picture in the game's own user folder and shows it in the scrapbook.

**Where and what is stored**
- Files live in `user://photos/`, the game's own app data folder (on iPhone and iPad, inside the app sandbox).
- Each picture is a PNG named `photo_<unix milliseconds>.png`. Pictures from before r16 are named `photo_<unix seconds>.png`.
- `scrapbook.json` in the same folder lists the file names in the order the photos were taken. It holds bare file names only: no absolute paths, nothing about other apps.
- Code: `game/scripts/core/photo_store.gd`.

**After a restart:** the scrapbook reads that list and shows the newest four photos. Each photo is loaded only when the scrapbook opens, and shown at a third of its size.

**Older photos and errors**
- Photos taken before r16 (no list yet) are found by their file names in the same folder and shown in time order.
- A missing photo is left out.
- A damaged photo shows no picture and does not stop the scrapbook.
- A damaged list falls back to the photo files; the next photo rebuilds it.
- Nothing is ever deleted by the game.

**Safe writes:** each photo and the list are written to a temporary file first and then renamed into place, so an interrupted write never leaves a half-written file under the real name.

**Privacy**
- Only this folder is read.
- The game never lists or imports the Photos library or any other app's files.
- Pictures never go over the network: they are not part of multiplayer and are not in the shared town save.

**Photos (iPhone and iPad):** unchanged. With permission, a copy is also added to Photos (add-only, the r8 behaviour), and the scrapbook keeps its own copy either way.

**Limits**
- Photos stay on the device that took them.
- There is no way to delete photos in the game yet; they can be removed by deleting the app's data.
- The scrapbook shows only the newest four.
