# Thousand Town data

Thousand Town is adapted from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY
(https://github.com/YiHuiShiBY/thousand-town, commit `1332ef29d6208a4192bf7400e0085033fd773a3c`), CC BY 4.0.
Lantern Lane's changes are listed in `design/thousand-town.md` section 12 and, for this folder, below.

This folder holds two generated layers. Never edit them by hand.

| Layer | Written by | Documented in |
|---|---|---|
| `town.json` and the six module GLBs (`district`, `housing`, `amusement`, `civic`, `hospital_room`, `landscape`) | `scripts/thousand_town/extract.mjs` (W-DATA) | `scripts/thousand_town/README.md` |
| The world layer: `world_*.glb`, `world.json`, `lights.json`, `solids.json` | `scripts/thousand_town/build_world.mjs` | this file |

## The world layer (route C)

Upstream builds part of its town only inside its Three.js scene code, so W-DATA could not extract it (CHECKPOINT.md, "Not extractable"):
- the ground layer: kerbs, lamps, benches, shelters, canal walls and the rest of the street furniture;
- the facility bodies;
- the housing floor detail;
- the station building;
- the fences;
- the ferris wheel;
- the stall bodies.

`build_world.mjs` ports each of those builders to Node (`scripts/thousand_town/world_*.mjs`; the provenance table is below and in `world.json`). It runs them on the city that upstream's own pure planners build, in the same bare, hash-checked vm as `extract.mjs`. It writes the result here in metres.

**What is not executed:** upstream's Three.js builders and page code. They were read, never run. Three.js is used only as a geometry library: Lantern Lane's vendored `game/web_city/vendor/three.core.js` r186, hash-checked.

### Running and checking

```
node scripts/thousand_town/build_world.mjs              # write the 17 files here (about 9 s, one core)
node scripts/thousand_town/build_world.mjs --out DIR    # write elsewhere (the two-run byte comparison)
node scripts/thousand_town/build_world.mjs --check      # rebuild in memory, compare every byte with this folder,
                                                        # re-hash upstream and the local inputs, run the checks
node scripts/thousand_town/build_world.test.mjs         # build twice in memory, compare, run the checks
```

**Requirements:** Node 22 or later, with no packages and no network.
- It finds the pinned copy at `build/dual-host/thousand-town/upstream/thousand-town-1332ef2/`, or beside the dual-host work copy.
- `THOUSAND_UPSTREAM` overrides that path.

**Determinism:** two runs give byte-identical files.
- There are no clocks.
- The only randomness is upstream's own seeded generators, the same mulberry32 seeds as the page.
- JSON keys are sorted and numbers are rounded to 1e-4.
- Vertex positions are rounded to 1e-6 m, then to float32.

**`--check` verifies:**
- the pinned commit;
- the SHA-256 of every input: 19 executed upstream files, 9 ported or cited upstream files, `three.core.js` and `town.json`. The table is in `world.json` `source.files`.
- the files on disk against a fresh build, byte for byte;
- the checks below.

**The checks** (`build_world.test.mjs`):
- **GLB structure:** accessors, unit normals, RGBA16 colours, index bounds, vertices inside the board, the CC BY credit, the keep import.
- **Scale, against the 1.30 m child:**
  - doors 2.1 m;
  - every facility and housing body is 0.7 m + floors x 3.0 m;
  - street lamp heads 3.25-5 m and slim posts;
  - bench backrests below the child's head, and seats 0.4-0.6 m;
  - market stools 0.4-0.6 m;
  - a kerb step of 0.065 m;
  - canopy and shelter headroom over 2.2 m;
  - bridge rails 0.8-1.2 m;
  - the wheel 10 m / 13 m;
  - bus 6.3 m, taxi 3.45 m.
- **Budgets.**
- **Every listed element present,** with its named nodes.
- **The provenance table:** each line range lies inside its hash-checked file and contains the named function, and each minified anchor occurs exactly once.
- **Solids:** well formed, and the arrival point is clear.
- **Signs:** all placed, plate sizes, and a contrast of at least 4.5:1.

### Format: GLB, read at run time with GLTFDocument

The world layer uses the same path as W-DATA's six GLBs:
- each `.glb` has a `.glb.import` with `importer="keep"`;
- the game loads it with `GLTFDocument.append_from_file` + `generate_scene` (`ThousandMap.glb_scene()`), never `load()`.

**Why GLB rather than the mesh-pack format:**
- `scripts/web/mesh_pack.gd` is a Godot-to-browser format: Godot writes it and only the page reads it. Godot would need a new reader.
- GLB needs no new code on the Godot side.
- It keeps node names, so moving parts and per-building groups can be found by name.
- It keeps per-surface materials, so the emissive groups can be swapped by name.
- It decodes with no per-vertex scripting.

**Layout:**
- Every node uses core glTF 2.0 only: `POSITION` and `NORMAL` (float32), `COLOR_0` (normalized unsigned short RGBA, the layout Blender exports), uint16 or uint32 indices.
- The window panes also carry `TEXCOORD_0`.
- **Colour is in the vertices, and linear.** Every material is white, and the material only says how the surface responds.
- `asset.copyright` carries the CC BY credit.

### What the Godot world builder must do

1. **Load the seven GLBs** with GLTFDocument. Add `thousand_town/data/*` to the export `include_filter`, which W-DATA already noted. Then:
   - **Materials:** replace each glTF material by its name (the table below) with a StandardMaterial3D or a small shader, with `vertex_color_use_as_albedo = true` and `vertex_color_is_srgb = false`.
   - **Merge per chunk.** Static chunk nodes end in `_c<ix>_<iz>`, in all files: `Ground_`, `Facilities_`, `Housing_`, `Market_`, `Market_Goods_`, `Market_Lights_`, `Signs_`, `Station_`, `Amusement_`, `Plaza_`, `BalloonCarts_`, `StreetOffice_`.
     - Nodes with the same chunk suffix may be merged into one mesh per material at load (append the surface arrays).
     - That is what the merged draw-call figures below assume. The cells are 16: x cuts at -48, 0 and 48 m; z cuts at -64.5, 0 and 64.5 m.
     - Keep `Market_Goods_c*` and `Market_Lights_c*` apart if the market's open and lit states are toggled per node.
   - **Visibility ranges** (`world.json` `godot.visibility_ranges_m`):
     - doors 45 m, awnings 80 m, market goods 60 m, signs 90 m, balloon carts 80 m, the canal fountain 150 m;
     - the vehicle templates are never drawn in place.
2. **Light it** from `lights.json`:
   - drive the emissive groups by the town clock (the schedule there);
   - put real OmniLight3Ds on the four `omni_candidate` lamps nearest the camera (design section 8);
   - draw the `pools` as additive decals or quads if wanted.
3. **Windows:**
   - Each `Windows_<building>` node is one building's lit panes. A pane is lit when its `TEXCOORD_0.x` (rank) is below the building's light level, from the thousand_sim occupancy, as upstream's town-view `lightLevel`. `TEXCOORD_0.y` is floor / floors.
   - Use a shader that discards unlit panes. Upstream hides them.
4. **Animate** (`world.json` `animate`):
   - **`FerrisWheel`:** rotate `FerrisRotor` about its local Z by `angle = (t mod 180 s) / 180 x 2 pi`. Move each `FerrisCabin_kk` to `(cos(angle + k pi / 6) x 10, 13 + sin(angle + k pi / 6) x 10, 0)` in `FerrisWheel` space without rotating it.
     - Cabins k and k + 3 share a mesh, so three MultiMeshes are an option: 6 draw calls instead of 24.
   - **`Door_<building>_<k>`:** the origin is the hinge (swing about +Y by `angle x open`) or the leaf centre (slide by `offset_m x open`). `open` is the building's `doorOpen` from the town view.
   - **`Stall_<id>_Awning`:** one node per stall, to sway or fold.
   - **`BalloonCarts_Balloons`:** bob per balloon. Per-balloon data is given for a MultiMesh.
   - **`CanalFountain`:** the 116 droplets are given as `p0`, `v`, period and phase, with g = 4.75 m/s². The pump is off 22:00-05:30.
   - **Vehicles:** `Station_BusTemplate` and `Station_TaxiTemplate` are one bus and one taxi at the origin, front toward -z, wheels on y 0.125 m. Instance them along `town.json` `transit.station_loop`.
5. **Collide and walk** with `solids.json`:
   - `solids`: rects or turned quads, in metres;
   - `walkable`: surfaces with their height or height profile (bridges, viaducts, tunnels, the station platforms, yards, the plaza and park paving, the market promenade, the housing entry steps).
6. **Do not draw `town.json` `facility_parts` again.** `world_facilities.glb` already contains every `architectureParts` piece.
   - Place `civic.glb` and `hospital_room.glb` as W-DATA describes.
   - The boxes upstream skips when those modules are present are skipped here too.

### Materials

| Material | Roughness / metallic | Holds | Emission (`lights.json` schedule) |
|---|---|---|---|
| `tt_matte` | 0.92 / 0 | Paving, roads, kerbs, stone, grass, trees, timber; the ground and market street furniture (merged in) | none |
| `tt_paint` | 0.66 / 0.06 | Facility walls, frames and trims; the station; landmarks and cabins | none |
| `tt_metal` | 0.46 / 0.5 | Not used after the merges | none |
| `tt_glass` | 0.22 / 0.14 | Facility and housing glazing (opaque, tinted) | none |
| `tt_lamp` | 0.5 / 0 | Every night light: lamp heads, light strips and coloured lanterns, canopy strips, park and plaza lamp heads, wheel rim bulbs and cabin glazing, market festoons and lanterns | COLOR_0 x the lamps factor, x 2.6 for a busy market |
| `tt_window` | 0.72 / 0 | Window panes (`Windows_*`, `StreetOffice_Windows`) | COLOR_0 where rank < light level, else discarded |
| `tt_sign` | 0.6 / 0 | Pictogram signs: plates, rims, posts | COLOR_0 x 0.35 x lamps |
| `tt_fixture` | — | Defined, not used (merged into `tt_lamp`) | — |

### Files

Sizes and counts are at this builder revision. `world.json` `files` has the SHA-256 of each file and every node, with its triangles, materials and world AABB.

| File | Size | Nodes | Surfaces | Triangles | Contents |
|---|---|---|---|---|---|
| `world_ground.glb` | 18.84 MB | 17 | 33 | 229,424 | See below |
| `world_facilities.glb` | 2.28 MB | 54 | 57 | 31,652 | See below |
| `world_housing.glb` | 16.31 MB | 18 | 22 | 216,382 | See below |
| `world_station.glb` | 0.17 MB | 3 | 6 | 2,538 | See below |
| `world_landmarks.glb` | 0.90 MB | 20 | 34 | 16,548 | See below |
| `world_market.glb` | 4.60 MB | 58 | 66 | 71,680 | See below |
| `world_signs.glb` | 1.28 MB | 16 | 16 | 12,813 | See below |
| `world.json` | 0.10 MB | | | | The manifest: see below |
| `lights.json` | 0.19 MB | | | | See below |
| `solids.json` | 0.20 MB | | | | See below |

**`world_ground.glb`:**
- `Ground_c<ix>_<iz>` (16 chunks):
  - ground slabs and roads; 1,555 kerb stones; joints, centre dashes, 88 zebras and 48 stop lines;
  - the river-walk pavements and 210 canal-wall coping segments (the landscape Coping module);
  - parks with paths and 16 lawn lamps; the sports ground (track, pitch, goals, bleachers);
  - block walks; 2 road bridges and 2 footbridges with ramps, rails and rail light strips; the viaducts and piers; the tunnels;
  - 340 street lamps (10 of them high masts); 22 benches; 3 bus shelters and 5 bus signs; the taxi rank; 2 bike racks with 6 bicycles; 8 vending machines; 3 mailboxes; 40 bins;
  - the pedestrian street's gates, festoons, lanterns, bollards, planters, chess table, cart, menu boards and kiosk;
  - river benches and bank festoons;
  - 30 shrubs, 80 grass tufts, 230 flowers;
  - 194 trees (102 from the plan, 92 street trees).
- `CanalFountain`: the canal fountain's stones.

**`world_facilities.glb`:** 10 facilities and 6 annexes.
- `Facilities_c*`: the bodies, merged per chunk, including every architecture part.
- `Windows_<id>`: 14 window groups, 494 panes.
- `Door_<id>_<k>`: 28 door leaves, 20 of them raised to 2.1 m.

**`world_housing.glb`:** 4 blocks.
- `Housing_c*`: plinths, gardens, and every floor and roof module, with upstream's Blender modules baked in.
- `Windows_<id>`: 914 panes.
- `Door_<id>_<k>`: 10 entrance leaves at 2.1 m.

**`world_station.glb`:**
- `Station_c0_2`: the pad, platforms, bay paint, canopy, columns, light strips, booth, 3 benches and the name board.
- `Station_BusTemplate` and `Station_TaxiTemplate`.

**`world_landmarks.glb`:**
- `Amusement_c3_2`: the paving rings, gate, ticket booth, perimeter fences (5 runs), bench, planters, path lamps and ride trim lights.
- `FerrisWheel` (yawed): `FerrisSupports`, `FerrisAxle`, `FerrisRotor` (with the rim bulbs), and `FerrisCabin_00..11`.
- `Plaza_c2_2`: paving, rings, joints and 6 lamps.
- `BalloonCarts_c3_2` and `BalloonCarts_Balloons`.

**`world_market.glb`:**
- `Market_c*`: the promenade and 32 stall bodies.
- `Stall_<id>_Awning`: 32 nodes.
- `Market_Goods_c*` and `Market_Lights_c*`: 64 lanterns plus the festoons.
- `StreetOffice_c1_0` and `StreetOffice_Windows`.

**`world_signs.glb`:** `Signs_c*`, 83 pictogram signs:
- 27 totems;
- plates on the station board, the bus stops, the taxi rank, 32 stalls, the street office, the park gate and the plaza plaque;
- 7 bay paintings.

**`world.json`, the manifest:**
- files and nodes, per-node AABBs, materials;
- what Godot must do;
- animation data, doors, windows, buildings, vehicles, signs and the fountain droplets;
- counts, budgets, provenance, elements not ported, and the hash table.

**`lights.json`:**
- 413 lamps: positions, colour, range, `omni_candidate`, and spot data for the street lamps and high masts;
- 58 spot anchors (river, fountain, tunnel walls);
- 440 light pools;
- 172 lanterns;
- the window groups;
- the emission schedule.

**`solids.json`:**
- 1,279 footprints of everything that blocks walking between 0.25 m and 1.8 m above its own ground;
- 61 walkable surfaces;
- the datums.

### Budgets

Draw calls count each surface (node x material). The view metric is a 100-degree, 200 m wedge on the ground plane: the follow camera's 16:9 view at a 60° vertical field. It honours the visibility ranges and is taken at the arrival framing and at 2,320 street views (a 12 m grid x 8 headings).

| | Value | Limit |
|---|---|---|
| Draw calls if everything were drawn | 234 | 300 |
| Draw calls, arrival view, as authored | 133 | — |
| Draw calls, worst view, as authored | 152 | 200 |
| **Draw calls, arrival view, merged per chunk** | **83** | 100 |
| **Draw calls, worst view, merged per chunk** | **96** | 110 (about 0.55 of the iPad's 180) |
| Triangles, all files | 581,037 | 700,000 |
| Triangles, arrival view / worst view | 434,088 / 540,462 | — |
| Largest node | `Housing_c0_1`, 60,694 | 70,000 |
| Bytes, all seven GLBs | 44.4 MB | 48 MB |
| Real lights | 4 nearest candidates | 4 (design section 8) |

**Bytes are the open trade-off.** The GLBs use core glTF only (float32 positions and normals), and the housing modules and the trees are baked rather than instanced: baking costs bytes but saves draw calls.
- **If GLTFDocument's handling of `KHR_mesh_quantization` is confirmed on the Mac,** quantized positions and normals would roughly halve the files.
- **Instancing the housing Window/Balcony modules** (W-DATA's `housing.glb`) would remove about 12 MB, at about 9 more draw calls per visible block.

### Scale (design section 1)

**Everything is upstream x 0.5,** with one exception.
- **Doors are 2.1 m (4.2 units), raised from their sills.** Every leaf below that height grows, and the frame and mullion of the same doorway grow with it:
  - the facility portals (upstream 2.0 m) and the architecture doorways (1.83-2.08 m);
  - the housing entrances (1.8 m).
  The checks then hold for the 1.30 m child:
  - Upstream's furniture already sits plausibly: bench seat 0.55 m and backrest 1.09 m above the pavement, market stools 0.53 m, lamp heads about 4.2 m, rails 0.94 m above the bridge deck.
  - Headroom: 3.7 m under the station canopy and 3.5 m under the shelters.

### Pictogram signs

Upstream's Chinese-only sign atlases are not used (design section 0). Each sign is a pictogram:
- **No text.** It is built from filled shapes with thick strokes: at least 0.08 of the icon, about 0.1 m on a 1.3 m plate.
- **High contrast:** a coloured plate with a light or dark rim. Every plate and ink pair is at least 4.5:1.
- **Geometry, not a texture,** so it stays crisp at 10-15 m.

**Categories and icons:**
- **transit,** green: bus, taxi;
- **health,** white with a red ink: cross;
- **education,** blue: a schoolhouse with a clock tower, a mortarboard, a book;
- **shopping,** magenta: bag;
- **food,** orange: apple, and on the stalls skewer, hotpot, pan, dessert, cup, bowl;
- **civic,** navy: shield, bank columns, flag;
- **leisure,** teal: tree, ball, ferris wheel, fountain;
- **housing,** brown: house;
- **work,** slate: briefcase, wrench, truck;
- **recycling,** green: bin.

**Totems:** a post with a double-sided 1.3 m plate centred at 2.6 m, the follow camera's height.
- One stands beside every building's and annex's street door (`town.json` `doors[0]`), placed clear of every solid and off the roads.
- The bank, where no clear spot exists, gets a wall plate over its door.
- The station, the parks and the sports ground also have one.

### Provenance

The upstream file names below are relative to the pinned copy. Line ranges are 1-based and inclusive. The ground bundle is a generated, minified file of 77 physical lines, so its anchors are unique snippets with the minified function names. The checks verify every range and anchor.

| Element | Upstream file | Functions | Lines / anchor | Port |
|---|---|---|---|---|
| Kerbs | `assets/city-ground.runtime.min.js` | `CityGround.create` (`Jt`): the road loop, kerb stones, joints | `x.curbSegments+=1` | `world_ground.mjs` |
| Lamps | same | `Je` (lamp pairs), `ba` / `hn` (lamp), the high masts, `planHighMasts` (`Ja`) | `[[0,.62,.62,.48,.22],[0,.2,.2,8.35,8.09]` | `world_ground.mjs` |
| Benches | same | `bt` (bench), the walk-street benches, the river benches (landscape Bench) | `kind:"bench",alongX:a,top:2.42` | `world_ground.mjs` |
| Shelters | same | `mn` (bus shelter), `xn` (bus sign), the taxi rank | `kind:"bus-shelter",top:7.6` | `world_ground.mjs` |
| Canal walls | same | `refinedBankSegments` + `blender-bank-coping`, the waterline stain, the river-walk pavements | `Ie.name="blender-bank-coping"` | `world_ground.mjs` |
| Ground surfaces | same | `la`, the roads, crossings, parks, block walks, bridges (`cn`), viaducts, tunnels, `Ce` / `en` / `rn` | `la(-ye,ye,-2,3.2)` | `world_ground.mjs` |
| Street furniture | same | `wn`, `gn`, `Ba`, `zn`, the `Tr` walk street, the festoons, `dn` planting, `Bn` trees | `kind:"bike-rack",top:2.9,bicycles:3` | `world_ground.mjs` |
| Canal fountain | same | the fountain stones (`vr`), the droplets (`wa`) | `Lr.name="canal-fountain-water"` | `world_ground.mjs` |
| Sports ground | `city-playground.js` | `create` | 4-93 | `world_ground.mjs` |
| Facility bodies | `city-facilities.js` | `create`: `box`, `lightPane`, `markDoor`, `windowRows`, `parapet`, `frontPorch`, `storey`, `shutters`, `buildTeachingBlock`, `buildHall`, `buildSmallCentre`, `buildClinic`, `buildPrecinct`, `buildWaste`, `buildPodium`, `buildArchitecture` | 773-1592 | `world_facilities.mjs` |
| Facility architecture | `city-facilities.js` | `architectureParts` (pure, run in the vm) | 428-677 | `world_facilities.mjs` |
| Housing floor detail | `city-housing.js` | `create`: `facade`, `floorModule`, `roofModule`, `garden`, `planter`, `windowRank`, `paletteFor`, `detailsFor`; `load` | 14-410 | `world_housing.mjs` |
| Station building | `city-transit.js` | `create`: pad, platforms, bays, canopy, booth, benches, board; `vehicle` | 11-300 | `world_station.mjs` |
| Fences | `city-landmarks.js` | `amusementPark`: the gate, perimeter fences, booth, bench, planters, `parkLights` | 394-433 | `world_landmarks.mjs` |
| Ferris wheel | `city-landmarks.js` | `amusementPark`: the supports, axle, rotor, `ferrisLights`, the cabins; `update` | 338-536 | `world_landmarks.mjs` |
| Plaza paving | `city-landmarks.js` | `monumentPlaza` | 561-628 | `world_landmarks.mjs` |
| Balloon carts | `city-landmarks.js` | `balloonCarts`, `bobBalloons` | 630-711 | `world_landmarks.mjs` |
| Stall bodies | `city-waterfront.js` | `create`: the promenade, `lampTrain`, `lantern`, `stool`, the stalls, the street office | 181-444 | `world_market.mjs` |
| Street lamp lights | `city-scene.js` | `createStreetLighting` | 283 | `world_ground.mjs` |
| Kit colours | `city-materials.js` | `kit` | 752-772 | `world_ground.mjs` |

### Differences from upstream, for the CC BY change list

- **Doors** are 2.1 m (design section 1).
- **Tree crowns** use icosahedron detail 1 (80 triangles) with upstream's displacement, instead of detail 2 (320). This is a budget choice.
- **Fewer, merged materials.** The street furniture is merged into the matte surface, and the light strips and coloured lanterns into the night-lamp group; upstream gives the strips a faint daytime glow. This is a budget choice.
- **The wheel's cabin doors are drawn shut.** Upstream slides them open for about six seconds at the boarding point.
- **The station's parked fleet** is replaced by one bus and one taxi template, for the transit system to instance. Upstream's seated passengers, wheel fares and balloon vendor are left to Lantern Lane's people.
- **Signs** are pictograms (above), not upstream's Chinese text.

**Not drawn** (also listed in `world.json` `not_ported`):
- the Reflector canal water and the waterfall shader quads: Godot draws its own water;
- the festival flags and colours (National Day dressing);
- the ward window glass at 13% opacity;
- the plaza monument, benches and planters, the carousel and the teacups: they are W-DATA's `landscape.glb` and `amusement.glb`.

**Light pools, spot lights, the viaduct flow-strip colours and the fountain droplets** are written as data, not geometry.
