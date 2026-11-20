# Thousand Town data tools

Thousand Town is adapted from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY
(https://github.com/YiHuiShiBY/thousand-town), CC BY 4.0. Lantern Lane's changes are listed in
`design/thousand-town.md` section 12. This folder holds the Node scripts that read the pinned upstream copy
and write data the Godot game uses natively:

| Script | Writes | Checked by |
|---|---|---|
| `extract.mjs` | `game/thousand_town/data/` (map, meshes) | `game/tests/thousand_map_tests.gd`, `extract.mjs --check` |
| `sim_fixtures.mjs` | `game/tests/thousand/fixtures/` (simulation parity) | `game/tests/thousand_sim_tests.gd` |

This README documents `extract.mjs`.

## Running it

```
node scripts/thousand_town/extract.mjs            # write game/thousand_town/data/
node scripts/thousand_town/extract.mjs --check    # regenerate in memory, compare every byte with the files
node scripts/thousand_town/extract.mjs --out DIR  # write elsewhere (for a two-run byte comparison)
```

- **Requirements:** Node 22 and no npm packages. It uses only `crypto`, `fs`, `path`, `vm`, `zlib` and `url`.
- **No network.** It reads the pinned copy only.
- **Determinism:** two runs give byte-identical files.
  - Object keys are sorted.
  - Integers are written as integers. Every other number is rounded to 4 decimals (0.1 mm), with trailing zeros removed.
  - There are no timestamps.
  - The GLB writer emits fixed layouts.
  - `--check` proves it against the files on disk.
- **Godot check:**
  - The command: `scripts/godot.sh --headless --path game -s res://tests/thousand_map_tests.gd`.
  - It ends `THOUSAND MAP TESTS: N checks, M failures` and exits non-zero on a failure.
  - It is not in `scripts/test_all.sh` yet; the lead integrates it.

## Safety: the upstream copy is untrusted data

- **The copy:** `build/dual-host/thousand-town/upstream/thousand-town-1332ef2/`, read-only. Nothing runs from inside that folder.
- **Pinned commit:** the script reads `.git/HEAD` (following a ref through the loose or packed refs) and refuses anything but `1332ef29d6208a4192bf7400e0085033fd773a3c`.
- **Hash check:** every upstream file the script reads must match the SHA-256 in its `EXEC` or `CITED` table, or it stops with an error naming the file.
  - The `CITED` files are read only for constants, which this script quotes with file and line.
  - They are hashed too, so a changed copy cannot drift silently.
- **The vm context:** the `EXEC` files run there, in `index.html`'s script order.
  - The context has no `require`, `module`, `process` or `Buffer`, and only a silent `console` and `atob`.
  - Upstream's UMD wrappers therefore register their APIs on the context's global, as the page's `<script>` tags do.
  - `Math.random` and `Date` throw inside it, so nothing non-deterministic can leak in.

### Hashes (SHA-256 at the pinned commit)

**Executed (`EXEC`), in load order:**

| File | SHA-256 |
|---|---|
| `city-random.js` | `441e8419826de45ee183127ef41108c944114d5aa477988ca85b05f69d393aeb` |
| `city-model.js` | `98a9b5f0c591ef375c54ebd8ee9a32759251994038ffe7847529f1047990e3a9` |
| `assets/resident-town-runtime.min.js` (CityLife: walking, lane, traffic and rider routes) | `880af8b610729e46392b5eedbda92702d50fdf1a2a01f1dac0966cf796e758f4` |
| `assets/blender-landscape.js` | `c9e57c7fb992c8d0bb220daabf688b6df5d799f011757183a5c7bed4b4438766` |
| `assets/blender-amusement.js` | `6f87a2bef9ed209c2e17c0aed75891a1e67f0f86b70e1eaf9c260d68e25416a3` |
| `city-fountain.js` | `57704231d5f2cbdad33c9199d3fcdadf6b71df548bec6055dbcb324be23baa7a` |
| `assets/blender-district.js` | `20689f5ed14d1a4cdf55c15590eb77803d902fae8d04b29dd1e9941d3cafaa47` |
| `city-district.js` | `ea7509710467ad4671ccb7ccbea640f5716d5328ea0b2710f8fb51228ed5cfed` |
| `assets/blender-civic.js` | `3b018ed9737b1426d441e1cb2c10fccc51d183a8bedc18ed90928a0e1d73ce30` |
| `assets/blender-hospital-room.js` | `51140b0e1eb289ab03ca4c0b76bdb79fd63a81edba1740b5d43ab9f1ae5f5bc0` |
| `city-facilities.js` | `07e55c0fb704a7c874a703cf0d8b12d94caf88244d75e86a1a30c0c3cb2a42e0` |
| `city-places.js` | `84fe8a2a308b92326071656a138e89f387964b6380e0bd287d73dc19faadd03f` |
| `city-housing-plan.js` | `b91f11b91ffcdd50adefb1667dd71b1e0543b3b1cf2eb560bf041de9a42e0572` |
| `city-frontage.js` | `208cc492911bf4be12d51e8488757ccd67d987894894dbbc9562ada53753a761` |
| `city-layout.js` | `f11e213ee0208079fe864d8d7f75131f83181b45ec0647bb0952e85a917914b7` |
| `assets/blender-housing.js` | `0b66a60a97d56774c13b71b0e547b33ca7d1698e58a7518df11b6cbc9abfa7b8` |
| `city-waterfront.js` | `6238fdb8612ab1f55a5d28e327a506cbf1f6b45b673724b809558f0495d88480` |
| `city-transit-motion.js` | `32ea84d03640a3ced96d7e92caf15ae23e2acbdda16e2d7cdc3827ac3ba214ab` |
| `city-helipad.js` | `bc887166dc31eceadad4f5f9ca1fc10d6afcec869aeee7c094588e98ef701dfc` |

**Cited for constants (`CITED`), not executed:**

| File | SHA-256 |
|---|---|
| `sketch.js` (defaults, build order) | `d5162cedf2c12870b2d4e1a2566f72ffc2cdf169556cc1cc1712ccd1127bc423` |
| `city-housing.js` (wing entrances) | `26dedc2b44c916befb44ade2a3ad4a60eff8027a332725e7d9a0250d35e66d4e` |
| `city-transit.js` (station pad, platforms, canopy) | `70cf912a7651b0614745d53e16e110fb2e1f1da1d53279535a78f7dcbdeaacbe` |
| `city-landmarks.js` (wheel, rides, plaza furniture) | `bda5217fcb35742e0ca991b4eb95665e390c2b9ff0f320bda7af7381dce450ad` |
| `city-materials.js` (kit colours) | `09a4e885687ae9d4bde7147eb3c4bc8440b72debef4ae6d5d58ca2e34048151d` |
| `assets/city-ground.runtime.min.js` (zebras, station gates) | `108bf59d06c69590d9f3d36999f550348472982e747f093210452ae3bece3f9a` |
| `LICENSE` | `9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411` |

`town.json` repeats this table under `source.files`.

## What it builds

This is the page's own `createCity` (`sketch.js:133-144`), with the page's defaults (`sketch.js:10`):
- seed 20260818, density 0.8, skyline 1;
- playground and housing on;
- the identity layout (no `?layout=`).

The build order:
1. `CityModel.createCity`
2. `CityFacilities.decorate`
3. `CityPlaces.decorate`
4. `CityHousingPlan.decorate`
5. `CityLayout.apply(identity)`
6. `CityWaterfront.plan` and `civicSite`
7. `CityPlaces.balloonStands`
8. `CityFrontage.plan`

**The construction is frozen at its end state.** No `sampleBuilding` time is used, every building has all its floors, and the per-part appearance times (`t`) are dropped.

**Derived data also comes from upstream code:**
- the routes come from `CityLife.create(city)`;
- the station loop from `CityTransitMotion.create`;
- the helipad from `CityHelipad.plan`;
- the facility and annex boxes from `CityFacilities.architectureParts` and `annexSites`;
- the tower boxes from `CityDistrict.officeParts`.

## Units and every scale conversion

**1 upstream unit = 0.5 m.** Every length, position, height and radius is multiplied by 0.5:
- `x y z w h d r`;
- roof and axle heights;
- widths, ring depths and band depths;
- route lengths and polylines;
- mesh vertex positions.

**Not scaled:**
- counts, floors and ids;
- angles in radians: `yaw`, `tilt`, `facing` vectors, and the helipad circuit's unit vectors `u` and `v`;
- colours;
- times and periods in seconds;
- the tower module scale ratios (`w / 36`, `d / 32`, `0.8`, `0.86`), which are unitless.

**Speeds** are scaled, since they are lengths per second: the station loop runs at 5 m/s of upstream time (10 units/s).

| Quantity | Upstream | Metres |
|---|---|---|
| Board | x +-190, z +-258 | x +-95, z +-129 |
| Lot centres | x -132/-60/60/132, z -200/-120/-40/40/120/200 | x -66/-30/30/66, z -100/-60/-20/20/60/100 |
| Storey / plinth | 6 / 1.4 | 3.0 / 0.7 |
| Pavement datum / water level | 0.25 / -0.55 | 0.125 / -0.275 |
| Cross street / avenue / ring road width | 12 / 10 / 10 | 6 / 5 / 5 |
| Canal half-width | 15 | 7.5 |
| Avenues / ring roads | x +-96 / +-175 | x +-48 / +-87.5 |
| Road bridge / footbridge | 46 x 15 / 44 x 5 | 23 x 7.5 / 22 x 2.5 |
| Station | (-132, 40), 52 x 58 | (-66, 20), 26 x 29 |
| Ferris wheel radius / axle | 20 / 26 | 10 / 13 |
| Housing door (upstream) | 3.6 | 1.8; Lantern Lane uses 2.1 (`constants.door_height`, design section 1) |

## `game/thousand_town/data/town.json`

| Key | Content | Copied or derived |
|---|---|---|
| `source` | Title, repository, commit, licence "CC BY 4.0", author "Yihuishi / YiHuiShiBY", units, the hash table | Lantern Lane |
| `params`, `constants`, `board`, `palette` | Seed and settings; storey, plinth, datums and widths; the board extent and lot axes; the kit colours (`city-materials.js:753-772`) | Copied, scaled |
| `lots` (24) | `index`, `row`, `col`, `cell` (A1-D6), centre, `kind`, `programme`, upstream `name_zh`, our `name_en`, the building ids | `CityLayout.cells`; tower lots marked `tower`; English names ours |
| `buildings` (18) | See below | Copied; doors derived as described |
| `annexes` (6) | 3 clinics, the police post, the waste station, the bank podium: resolved centre and size, `footprint` (reserved ground, including the bank's forecourt), host, floors, height, palette, `doors`, `facade_doors` | `annexSites` |
| `places` | `station`; `amusement` (its south gate); `plaza`; `parks` (3, one `use: "sports"`); `sports` (track and pitch); `block_walks` | See the station notes below |
| `roads` (18) | `role` (`cross_street`, `avenue`, `ring_road`, `expressway_stub`), `axis`, rect, `through`, `closed`, `walk_only_to` (the z = 0 street is pedestrian for \|x\| <= 45.5 m) | Copied |
| `crossings` (24 junctions, 88 zebras) | Junction centre, the two road ids, each zebra's rect, walking axis and stripe count | Replicated from the ground bundle's crosswalk loop |
| `bridges`, `viaducts`, `tunnels` | 2 road bridges and 2 footbridges; 2 viaducts (deck height, flat and ramp lengths); 2 tunnels (portal, cover, drop) | Copied |
| `canal`, `promenade`, `river_walk`, `walking_routes` (9) | The water rect and level; the promenade bands (bank to \|x\| 13.95 m, `city-waterfront.js:44-46`); the ids of the walking routes along \|x\| = 11.5 m; every walking route as a polyline with its 1.4 m paved width | `CityLife.walkingRoutes` |
| `transit` | `bus_stops` (6), `taxi_rank`, `station_loop` (7 vehicles, see below), `street_loops` (4), `rider_loop`, `lane_routes` (16), and the 40 street `vehicles` (loop, offset, speed, kind, colour) | `CityPlaces.transitStops`, `CityTransitMotion`, `CityLife` |
| `trees` (102) | `x`, `z`, crown radius `r`, height `h` | Copied |
| `waterfront` | 32 night-market `stalls` (side, plot, type, colour, seats); `street_office` (with a derived door facing the river walk) | Copied |
| `landmarks` | See below | Mixed |
| `frontage` | `role_colors`, and 17 `sites`, each with type, ring, band, gate or entry side, the lobby opening, its reserved rects and its box `parts` | `CityFrontage.plan` |
| `facility_parts` (14 groups, 550 parts: 418 on eight facilities, 132 on six annexes) | Each facility's and annex's architecture boxes in world metres: `role` (material), `feature`, `color`, `floor`, an optional `tilt` (radians), `door: true` on door leaves; plus `signs` (anchor, size, yaw, upstream `text_zh` for reference only; design section 0 replaces them) | `architectureParts` |
| `office_parts` (4 groups, 1014 parts) | The towers' fins, bands, ribs, terraces and crowns, world metres | `officeParts` |
| `meshes` | One entry per GLB: file, source, triangles, sha256 of our file, upstream hash, module names and bounds (metres) | See below |
| `counts` | The totals above, and the GLB triangle counts | |

**Box parts** are `{role, x, y, z, w, h, d, yaw}` in world metres. `x y z` is the box centre (`y` above the ground datum) and `w h d` its full size along x, y and z. They are axis-aligned. They batch per role, which is merge-friendly.
- **Frontage parts:** `yaw` is the outward normal of the side the part belongs to. Only the `sign`, `plaque` and `board` roles use it: they are flat sheets turned to face their side (`city-frontage.js:733-741`). The sheet is `d` wide when `|sin yaw| > 0.5`, else `w`. Their `tile` is the cell in upstream's Chinese name atlases.
- **Facility and office parts:** the world position is already resolved, `floor * 3 + 0.7` included.

### Buildings

Each building has:
- `id` (upstream's `b-<lot>-<unit>`);
- `kind` (`tower`, `housing`, `facility`), `material_kind`, `programme`, `name_en` and `name_zh`;
- `lot` and `cell`;
- the centre and the record size `w`, `d`;
- `rect`, the solid footprint:
  - the record for the towers and the three V2 landmarks;
  - the pushed-back mass for the seven W1.5b facilities (`city-facilities.js:38-42`);
  - the 46 x 50 envelope for housing;
- `floors`, `storey` 3.0, `plinth` 0.7, `height` = 0.7 + 3 x floors;
- `roof`, `palette`, `frontage`;
- for **towers**: `office_profile` (t-one to t-four) and `modules`, which give the district GLB floor and roof module, the setback floor, and the module scales (`city-district.js:443-467`);
- for **housing**: `housing_type`, the wing `volumes` and the `courtyard`;
- for **facilities**: `gate_side` and `mass`.

**Doors.** Every door has `x`, `z`, a unit `facing` (out of the building), `kind`, `width` (or null), and `source`, which says which rule produced it. Two lists:

- **`doors`: where people come and go from the street.** Each stands 0.5 m outside its wall or opening.
  - **Walled compounds** (all housing and nine facilities): the compound gate, `kind: "gate"`, 4 m wide, centred on the gate side at the ring line.
    - The gate side comes from upstream's `CityFrontage.gateSide`:
      - the facility's recorded entrance;
      - else the housing courtyard;
      - else the nearest carriageway.
    - So every gate already faces a street.
  - **Towers:** the lobby opening through the shop ring, `kind: "lobby"` (`city-frontage.js` entry).
  - **The mall,** which has no frontage: upstream's recorded entrance (`entranceOf`), `kind: "entrance"`.
  - **The fallback,** "the frontage side facing the nearest street", is implemented but unused by the default town. No door is purely derived.
- **`facade_doors`: the building's own door leaves.**
  - **Facilities:** the leaves `architectureParts` marks with `door`, or else the recorded entrance.
  - **Housing:** each wing's ground-floor entrance on its north face, unless another wing stands in front. The formula is `city-housing.js:253-275`, replicated.
  - **Towers:** the lobby door behind the opening.
  - Inside a compound, these doors are reached through the gate.
- **Annex doors** stand outside the annex's gate face. The clinics and the waste station sit inside their host's compound, as upstream draws them.

### Station, arrival, transit

- **The station:**
  - the pad, the bus `platform`, `canopy` (with `y`), `taxi_platform` and `west_strip` (`city-transit.js:149-168`);
  - the bus and taxi bays (`city-transit-motion.js:8`);
  - the two vehicle `gates` on the avenue side (the ground bundle's formula: `gateX = x + side*w/2`, `gateWidth = 8*d/58`, `gateZ = z +- 13*d/58*side`).
- **The forecourt and the arrival are Lantern Lane's** (design section 3); upstream has no forecourt.
  - **`forecourt`** is the pad's south-east corner, clear of the bus lanes (local x 15..26, z -29..-15), plus the pavement out to the z = 0 street kerb (z = 3 m) and the avenue kerb (x = -50.5 m). In metres: x -58.5..-50.5, z 3..12.5.
  - **`arrival`** is (-52.0, 0.125, 3.6), facing +x.
    - It is on that forecourt's south-east corner, at the north kerb of the z = 0 street.
    - It is just west of the avenue and of the street's pedestrian stretch, so the view east runs along the street to the canal with no building or compound in the line.
    - `thousand_map.gd` carries the same numbers as `ARRIVAL_POS` and `ARRIVAL`.
- **`station_loop`:** 3 buses and 4 taxis, each with:
  - `departure` (s), its bay and the rounded route polyline in world metres;
  - `speed` 5 m/s and `period` 360 s of upstream time;
  - `bridge_rise` 0.85 m.
  - Upstream's daily bus timetable (from 06:00) is the clock's business (`sim_fixtures.mjs`).
- **`street_loops`:** upstream's four traffic rings. They run the z = +-40 m streets and the avenue flanks; the z = +-80 m streets with the ring roads and the tunnels; and the expressway loop over the viaducts. Each carries its half extents.
- **Upstream quirk, kept:** the stops do not move with `CityLayout.apply`. With the identity layout this changes nothing.

### Landmarks

| Landmark | Data | Source |
|---|---|---|
| `ferris_wheel` | Centre on the amusement lot, yaw -0.66, radius 10, axle 13 m, 12 cabins, period 180 s | Copied constants, `city-landmarks.js:11` and `:451-520` |
| `carousel`, `teacups` | Ride centres, base height, radius, height, period, their `amusement.glb` modules | `city-landmarks.js:42-44`, `:281-283` |
| `fountain` | The ring basin around the monument: inner 5.9 m, outer 7.3 m, surface 0.23 m, the 16 + 12 jet rings | `CityFountain.BASIN` / `RINGS` |
| `monument` | The plaza centre, its `landscape.glb` module, the four planters and four benches | `city-landmarks.js:578-583` |
| `helipad` | On the tallest tower, `b-3-0` (21 floors); roof level, pad radius, deck, the helicopter circuit ellipse | `CityHelipad.plan` |
| `balloon_stands` | The two stands | `CityPlaces.balloonStands` |

## The GLBs

All six are in metres, Y up, and keep upstream's module-local frames:

| Frame | Modules |
|---|---|
| Ride-local | the amusement rides |
| Building-local, floor-relative | the civic modules and the hospital ward |
| Host-local | landscape |
| Module-local | the district and housing modules |

Each has its `.glb.import` with `importer="keep"`:
- Godot exports the file as it is and never needs an editor import.
- The game reads it at run time with `GLTFDocument` (`ThousandMap.glb_scene()` / `glb_state()`), never with `load()`.
- `ResourceLoader.exists()` reports true for any file with a `.import` beside it, but `load()` fails for a kept file.

| File | Triangles | Built from | SHA-256 of our file |
|---|---|---|---|
| `district.glb` | 14376 | `assets/blender-district.js`: gunzip of the embedded base64 GLB (decoded sha256 `2230a5046b924591c7027cf7e26a3c43522a9fbdfb484b79d27b5ac3baaaf6d9`; upstream records none) | `f46098bee5b01e6dfef3f311d417d2f7746ec85992032f3b771009d85c2a413d` |
| `housing.glb` | 2568 | `assets/blender-housing.js`: gunzip, checked against the GLB's own recorded sha256 `1d5c107ab5f58c1e1f3bab949251854d2dd30fad4d28c99ac50a01a41da71c67` and size | `760691b67e7e323870aa7569fbd3ff7a93df4527587e784b5ac819ad144661d0` |
| `amusement.glb` | 896 | Packed arrays: CarouselBase/Rotor, TeacupsBase/Rotor | `c5cf115bf98ca5625baa2ad926e78a2df041e09b62a530ef7b2fb7f996be8b3e` |
| `civic.glb` | 3544 | Packed arrays: MallEntry, MallSkylightFrame, HospitalEntry, HospitalServiceScreen, SchoolEntry, SchoolClerestoryFrame | `ff09b193b9960234fd2ab5b299ec56585bbfefbc8bdf79c3106a36b457d5a568` |
| `hospital_room.glb` | 1232 | Packed arrays: one ward, split into its six features (Shell, BedLeft, BedRight, CabinetLeft, CabinetRight, Curtain), each a node and mesh over shared vertex arrays | `b539c5508f9a69fa78a60a4b96ab0737d96301639311c965ae58d47467be150b` |
| `landscape.glb` | 2320 | Plain arrays: Monument, Bench, Planter, Coping, CanopyStripe (non-indexed) | `69c997250ba1809b47f1e57bee018261118fb2f81ba254d7c773b27c1624fcb4` |

`town.json` records the same hashes under `meshes.<name>.sha256`, with the upstream GLB hash each pack was generated from (`upstream_sha256` / `upstream_glb_sha256`). The source `.js` files themselves are covered by the hash table above. `town.json` is `2efddfbf4061d90902d5d7dcda1423a7a27891f16fc6b821ab41059348bd849b` (985,778 bytes) at this extractor revision.

**District and housing** are upstream's own Blender GLBs, rescaled to metres:
- every POSITION accessor is multiplied by 0.5 in the binary chunk (exact in float32), with its min and max;
- every node translation is multiplied by 0.5;
- normals, UVs, the two embedded PNGs, materials and node names are untouched;
- `asset.copyright` and `asset.extras.units` are added;
- the scene `extras` (`city_module_stats`) are upstream's text, still in upstream units. Use `town.json` `meshes.district` for metre bounds.

**The four packed assets** are written by a minimal glTF 2.0 writer in `extract.mjs`. Each has:
- one node and one mesh per module (or per feature);
- `POSITION` (metres), `NORMAL`, `COLOR_0` (float RGB) and uint16 indices where upstream has them;
- one material with base colour white, metallic 0, and roughness 0.72 (rides, civic, ward) or 0.9 (landscape).

The triangle count written must equal upstream's meta, or the script fails.

**Vertex colours are linear,** as upstream stores them, and are written as linear `COLOR_0` as glTF specifies. Godot 4.7's GLTFDocument keeps the values (it reads them back as 0.6654 for 0.6654). However, it does **not** turn on `vertex_color_use_as_albedo` on the explicit material. The world builder must set it true, and leave `vertex_color_is_srgb` false.

**Export:** the export preset's `include_filter` does not cover this folder yet. Add `thousand_town/data/*` (town.json and the .glb files) when integrating. A kept file is exported as is, but only if the preset includes it.

## Not extracted, and why

- **The ground layer** (`assets/city-ground.runtime.min.js`) is a generated bundle that builds THREE meshes and has no pure plan. Not extracted:
  - kerbs and paving strips;
  - lamps, benches, bins, bike racks, mailboxes and bus shelters;
  - lawn lamps and planting tufts;
  - the canal walls and the waterfalls.
  
  Only two pieces were replicated from its source, the zebra crossings and the station gates. The rest is for `thousand_world.gd` to rebuild from roads, places and walks.
- **Facility bodies:** the floors, window rows and parapets of every facility, and the whole of the mall and the hospital, are built inside `CityFacilities.create` with THREE, not as data. `town.json` gives each facility's mass, floors, palette, architecture feature parts, and the civic GLB modules (`civic.glb`, placed at the building centre on floor 0 or the roof). The world rebuilds the plain massing.
- **Housing wing detail:** the windows, balconies, stair cores, entries and roof services per floor come from `CityHousing.create` (THREE). `town.json` gives the wings, palette and entrance positions; `housing.glb` holds the modules. The per-floor placement rules are in `city-housing.js` (cited, not run).
- **Procedural geometry built only in `create()`:** the station building (canopy columns, booth, signs), the amusement park's fences and booth, the ferris wheel, and the market stalls' bodies. Their sites and parameters are exported, not their meshes.
- **Not used (design section 0):**
  - the Chinese sign atlases and the canvas noise textures;
  - the Reflector water and the HDR sky;
  - the Milky Way image;
  - the guestbook bottles;
  - the airship advert;
  - the drone show.

  Sign anchors are exported. Their upstream text is kept only as `text_zh`, for reference.
