# Pets and themed-room assets: interface for the Modeling lane

Shared coordination file (GameCode writes the interface; Modeling may append a "Handoff" section). Status: 2026-10-07, interface v1.

The game ships **code-built versions of every ID below now** (procedural meshes in `game/scripts/art/props.gd` and `game/scripts/art/pet.gd`, same style as the town animals), so r7 is playable without new files. A modeled GLB may replace any of them later through the normal frozen handoff; GameCode then sets the catalog `model` path. Nothing here asks Modeling to edit game code, and GameCode does not edit `tools/nookipedia-model-production/`.

## Common rules (same as [object-scale-and-surfaces.md](object-scale-and-surfaces.md))

- 1 unit = 1 m, Y up, the item faces **+Z** (front toward the viewer at rotation 0). Ground items: origin at the floor center of the footprint. Wall items: origin at the center of the back face, on the wall plane.
- Built bounds within 0.12 m of the numbers below; small items 0.26-0.585 m tall; table-top items fit a 0.84 m square.
- Original geometry only; reference images are not shipped.

## Furniture and supplies (catalog IDs are stable)

| ID | Theme | Anchor | Bounds x, y, z (m) | Notes |
|---|---|---|---|---|
| kitchen_stove | kitchen | ground | 0.80, 0.95, 0.65 | cooking station; node `CookTop` at the hob center (for steam) |
| kitchen_sink | kitchen | ground | 0.90, 0.95, 0.60 | counter with basin and tap |
| kitchen_fridge | kitchen | ground | 0.70, 1.75, 0.68 | |
| kitchen_counter | kitchen | ground | 1.00, 0.92, 0.60 | worktop; support surface 0.90 x 0.50 at 0.92 |
| cooking_pot | kitchen | ground, table-top | 0.42, 0.30, 0.32 | |
| frying_pan | kitchen | ground, table-top | 0.50, 0.27, 0.30 | |
| utensil_crock | kitchen | ground, table-top | 0.22, 0.42, 0.22 | |
| plate_stack | kitchen | ground, table-top | 0.30, 0.27, 0.30 | |
| rice_sack | kitchen | ground, table-top | 0.34, 0.40, 0.28 | ingredient |
| egg_basket | kitchen | ground, table-top | 0.34, 0.28, 0.28 | ingredient |
| veggie_basket | kitchen | ground, table-top | 0.40, 0.32, 0.30 | ingredient |
| dish_rice, dish_soup, dish_egg, dish_omelette | kitchen | ground, table-top | about 0.30, 0.27, 0.30 | cooked dishes (also placeable) |
| game_tv | games | ground | 1.10, 1.05, 0.45 | screen on a low stand |
| game_console | games | ground, table-top | 0.46, 0.27, 0.34 | console with a controller |
| game_tablet | games | ground, table-top | 0.36, 0.27, 0.28 | handheld tablet on a little stand |
| gaming_desk | games | ground | 1.20, 0.76, 0.62 | support surface |
| bean_bag | games | ground | 0.80, 0.70, 0.80 | seat (`Seat0`) |
| game_shelf | games | ground | 0.90, 1.20, 0.38 | storage with game boxes |
| pet_bed | pets | ground | 0.80, 0.30, 0.65 | node `Rest` where a pet lies |
| dog_house | pets | ground | 0.90, 1.00, 0.90 | node `Rest` at the door |
| food_bowl | pets | ground | 0.30, 0.27, 0.30 | feeding spot |
| water_bowl | pets | ground | 0.30, 0.27, 0.30 | |
| cat_tree | pets | ground | 0.80, 1.60, 0.80 | climbing and scratching; node `Perch` at the top |
| scratching_post | pets | ground | 0.45, 0.80, 0.45 | |
| pet_toy_ball | pets | ground | 0.30, 0.27, 0.30 | toy |
| bird_perch | pets | ground | 0.60, 1.30, 0.50 | stand with a perch bar; node `Perch` |
| butterfly_garden | pets | ground | 0.90, 0.75, 0.50 | flower planter for butterflies; node `Perch` above the flowers |

Existing r1 items the game files under these themes (unchanged models): prepared foods and drinks, the fish skillet and kitchen scale (kitchen); the three arcade cabinets (games); the butterfly and fish models (pets).

## Pets (IDs stable; not catalog items)

| ID | Size (x, y, z) | Moves by | Hooks for animation |
|---|---|---|---|
| pet_cat | 0.30, 0.38, 0.55 | walking | `Body`, `Head`, `Tail`, `Leg0`-`Leg3` |
| pet_dog | 0.32, 0.45, 0.60 | walking | `Body`, `Head`, `Tail`, `Leg0`-`Leg3`, `EarL`, `EarR` |
| pet_bird | 0.20, 0.24, 0.26 | flying at about 1.3 m, perching | `Body`, `Head`, `WingL`, `WingR` |
| pet_butterfly | 0.26, 0.06, 0.18 (wings open) | fluttering at about 1.0 m | `Body`, `WingL`, `WingR` |

- Origin: ground center for cat and dog; the body center for bird and butterfly (the game sets the flying height). Front +Z.
- Colors: the game passes one of three body colors per family (cat: orange, grey, cream; dog: brown, white, black; bird: blue, yellow, green; butterfly: blue, orange, pink). A GLB should keep the body material named `Body` so the game can tint it.
- The game animates the hooks procedurally (walk cycle, tail wag, wing flap). An optional `AnimationPlayer` with `idle`, `walk`, `fly`, `happy` would be used if present.
- Not allowed: reptiles, lizards, geckos, insects other than the butterfly, anything frightening.

## Handoff (Modeling appends here)

### p001-pets-room: integrated in r7 (2026-10-07)

Frozen batch `tools/nookipedia-model-production/batches/p001-pets-room/` (`BATCH_MANIFEST.json` sha256 `9e14df29…0900`; Mac-validated candidate `pets-r7` rev1, manifest `11ab177a…1f31`). GameCode verified all 23 GLBs against their manifest digests and copied them byte-identical to `game/assets/models/`. **The modeled IDs below supersede the pet and pet-room rows above**; the code-built pet-room items and the code-built pets were removed, not shipped.

- Pets (rigged actors, not catalog items): `pet_cat_tabby`, `pet_cat_tuxedo`, `pet_kitten_cream`, `pet_dog_ginger`, `pet_dog_spotted`, `pet_puppy_brown`, `pet_bird_blue`, `pet_bird_yellow`, `pet_butterfly_blue`, `pet_butterfly_orange`. The game drives the joints `Head`, `Tail`, `LegFL/FR/BL/BR`, `WingL/WingR` within the handoff ranges (`game/scripts/art/pet.gd`); hover heights 0.4 (bird) and 0.6 (butterfly) at rest, +0.5 while following.
- Pet room (catalog, category Pets): `petroom_bed_round`, `petroom_dog_house`, `petroom_food_bowl`, `petroom_water_bowl`, `petroom_cat_tree`, `petroom_scratch_post`, `petroom_toy_yarn`, `petroom_toy_bone`, `petroom_toy_mouse`, `petroom_feather_wand`, `petroom_bird_cage`, `petroom_perch_stand`, `petroom_butterfly_house`; bounds, footprints, layers and size classes as in their manifests; markers `Sleep0`, `Feed0`, `Rest0`, `Perch0` are used for resting pets and feeding.
- Not proven by the handoff and checked by GameCode instead: runtime follow, joint motion (unit test: every joint hook turns) and multiplayer (real-client test). Art approval and device behavior remain open.

### Kitchen and game room

Still code-built (`game/scripts/art/props_rooms.gd`) under the IDs in the first table. Modeling's next batch (p002) may replace them through the catalog `model` path.

### rooms-r8 integration plan (prepared 2026-10-07; waiting for the Mac-tested frozen handoffs)

Nothing below is copied until Modeling posts accepted, frozen batches. Every GLB is checked against its manifest digest before it is copied byte-identical.

**p003-pets-r2 (bird repairs).** `pet_bird_blue`, `pet_bird_yellow` replace the p001 bytes in `game/assets/models/` (same IDs, same rig). The p001 bird bytes in candidate r7 had inside-out tail pieces (validator v2.4) and are **not accepted**.

**p002-game-kitchen.** Code-built r7 kinds are replaced by the modeled ones. Saves keep working through a kind alias applied when a town loads (`TownModel.KIND_ALIASES`; r7 was never released, the alias only protects test and dev saves):

| r7 code-built kind | r8 modeled kind | Notes |
|---|---|---|
| `kitchen_counter`, `kitchen_stove`, `kitchen_sink`, `kitchen_fridge` | same IDs | catalog gains `model`; stove support surface (0, 0.9, 0.03) 0.5 x 0.4 from the handoff; steam at `Cook0` |
| `cooking_pot` | `kitchen_pot` | |
| `frying_pan` | `kitchen_pan_set` | |
| `utensil_crock` | `kitchen_utensil_crock` | |
| `plate_stack` | `kitchen_plate_rack` | |
| `rice_sack`, `egg_basket`, `veggie_basket` | `kitchen_rice_sack`, `kitchen_egg_basket`, `kitchen_veg_basket` | recipe ingredients |
| `dish_rice`, `dish_soup`, `dish_egg` | `dish_rice_bowl`, `dish_veg_soup`, `dish_fried_egg` | recipe dishes |
| `dish_omelette` | `dish_rice_meal` | recipe "Rice and stew" (rice sack, vegetable basket, pot) replaces the omelette |
| `game_tv` | `game_tv_stand` | |
| `game_console` | `game_console_set` | plus new `game_controller` (flat) |
| `game_tablet` | `game_handheld_dock` | |
| `bean_bag` | `game_bean_bag` | seat `Seat0` |
| `game_shelf` | `game_storage_cubby` | |
| `gaming_desk` | `table` (existing round table, which has a support surface) | the game room console starts on the table |

Markers brought to the prop root in addition to Seat0/Sleep0/Support0/Light0/Feed0/Rest0/Perch0: `Cook0`, `Wash0`, `Open0`, `Screen0`. `game/scripts/art/props_rooms.gd` (the code-built kitchen and game items) is removed when p002 lands.

**b012-furn-r3** (repairs of the b011 ceiling backlog): not part of this feature. b011/b012 ceiling furniture stays outside the game until it is separately scheduled; no b011 asset is integrated today.
