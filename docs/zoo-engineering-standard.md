# Zoo engineering standard (contract v1, 2026-11-16)

This is the binding engineering contract for the zoo's first release. It covers [the zoo design](../design/zoo-and-world-journeys.md), sections 1 to 22, and [the camera note](../design/zoo-camera-rotation-assessment.md). Every worker builds against this version.
- **Owner:** the EC2 Opus production-owner session. It owns this file, integration and review.
- **Changes:** workers propose interface changes to the owner and do not implement them before the owner updates this file (section 9).

## 1. Scope and invariants

- **Full first release** (Phases 1A to 1D plus 22.4 to 22.7):
  - 7 species, 14 animals, exactly `ZooMap.ORDER`: lion Rory, lioness Honey, tiger Tango, monkeys Mango, Coco, Peanut, Momo and Bibi, giraffe Topper, zebras Zig and Zag, hippo Bubbles, otters Skip and Ripple;
  - 5 habitats;
  - the tram journey;
  - the zoo toy box;
  - Look;
  - the discovery log;
  - zoo-only turning (the existing 45° steps) and zoom (8, 9.5 and 15 m).
- **Outside the zoo nothing changes.** The town, the rooms, the town animals, the town camera (two zooms) and every existing test and assertion stay as they are.
- **Units and axes:**
  - 1 unit = 1 m; the child H = 1.30 m.
  - World axes as in the town: +x east, +z toward the default camera, y up.
  - Ground positions are `Vector2(x, z)`; 3D points are `Vector3(x, y, z)`.
  - Rotation `ry` is `atan2(dx, dz)`, as `TownModel`/`kid.gd` use it.
- **Style:**
  - code-built rounded primitives from `art/mesh_kit.gd`, `Kit.mat` matte colours from `core/palette.gd` or literal `Color`;
  - no textures (except `Kit.blob_shadow`), no metallic, roughness at least 0.85;
  - transparency only for shadows and water;
  - one model of the world: no new lights or environment.
- **No rendering on EC2.** Headless parse, unit, session and real-client tests only. Look and feel are deferred and never reported as passed.

## 2. Modules, ownership, dependency direction

Dependencies point downward only: core <- net <- world/art <- ui. Core never loads a scene or a node.

| Module | File(s) | Owner | Role |
|---|---|---|---|
| Map data | `core/zoo_map.gd` | Opus | **The single source** of every zoo id, rectangle, height, spot, anchor, link, station, resident and the arrival points |
| Life data | `core/zoo_life.gd` | Opus | Routines, treats, emote answers, toy answers, discovery answers and hints, the lines over animals |
| Simulation | `core/zoo_brain.gd` | Opus | A pure, seeded, fixed-step (`STEP` 0.1 s) simulation; `pack`/`unpack`; `path_point` (shared with drawing) |
| Places | `core/places.gd` | Opus | `is_map`, `map_of`, `half`, `arrival`, `can_decorate`, `music`. The only place that knows which spaces are maps |
| Rig maths | `art/zoo_rig.gd` | Opus | Pure two-bone reach, easing, pendulum, arcs |
| Animal models and poses | `art/zoo_animal.gd` | Opus | Builders for the 7 species; `apply(state, t, reduce_motion)` |
| Props and scenery | `art/props_zoo.gd` | **Worker W3** | Static builders (section 6) |
| Zoo world | `world/zoo_world.gd` | Opus | Builds the map from `ZooMap` plus `PropsZoo`; draws the animals from `Zoo.states`; one-shot effects; hides far animals |
| Town world hook | `world/town_world.gd` | Opus | `set_view("zoo")`, `resolve_walk`, `pick_animal` for the zoo |
| Player and journey | `world/play_controller.gd` | Opus, except the pinch and wheel lines | Contexts, journey, Look, taps |
| Camera | `world/camera_rig.gd` and the pinch and wheel lines in `play_controller.gd` | **Worker W2** | Zoo-only zoom levels and reset (section 5) |
| HUD | `ui/hud.gd`, `ui/look_strip.gd`, journey card | Opus | |
| Model and persistence | `core/town_model.gd`, `core/catalog.gd`, `art/props.gd` (dispatch only), `core/blueprints.gd`, `core/durable.gd`, and `net/session.gd` functions `_load_town`, `save_now`, `_srv_remove`, `_srv_wrap` and the blueprint guard | **Worker W1** | Schema 3, the tram stop rules, zoo items (section 7) |
| Network | `net/zoo.gd` (new autoload `Zoo`); in `net/session.gd`: `PROTOCOL`, the `rq_action` whitelist and `expected`, `travel`, `_srv_travel`, `_srv_state`, `zoo_use`/`zoo_offer` plumbing, disconnect clean-up; `core/invites.gd`; `net/animals.gd` (visit end); `project.godot` `[autoload]` | **Worker W4** | Section 8 |
| Strings | `game/locale/*.json`, then `scripts/extract_strings.py`, `scripts/build_fonts.py` | Opus, or a later worker after the string list is frozen | |
| Tests | Each owner writes the tests of their module: `tests/zoo_tests.gd` (Opus), `tests/zoo_save_tests.gd` (W1), `tests/zoo_camera_tests.gd` (W2), `tests/zoo_props_tests.gd` (W3), `tests/zoo_net_tests.gd` and `scripts/net_test.py --zoo` (W4) | | |

**Shared files.** `net/session.gd` and `world/play_controller.gd` have several owners. Each owner edits only its own functions, re-reads the file before every edit, and never reverts or reformats code it does not own.

## 3. Authority, timing, replication

- The authority is the solo device, the host or the dedicated server. It runs `ZooBrain` **only while at least one player is in the zoo**. When the first player arrives it creates `ZooBrain.new(seed)` and calls `spawn()`. When the last one leaves it drops it.
- **Brain input, each tick:** `kids` is an `Array` of dictionaries, one per player in the zoo:
  - `id: int`, the peer;
  - `pos: Vector2`;
  - `emote: String` and `emote_t: float` (the last emote and its time, as in `Animals.kid_inputs`);
  - `still: float`, seconds without moving more than 0.05 m;
  - `speed: float`, m/s, smoothed over 0.5 s;
  - `vel: Vector2`;
  - `run: float`, metres covered in the last 2 s at a speed of 2 m/s or more.

  Also `brain.toys`: an `Array` of `{"kind": String, "pos": Vector2}`, built from the model's items with `space == "zoo"`. And `brain.reduce_motion`: the authority device's own setting.
- **Output:**
  - `pack()` gives a `PackedFloat32Array`: `[time]` plus 14 floats per resident in `ZooMap.ORDER` (see `zoo_brain.gd`, `FIELDS`), sent at 4 Hz, unreliable and ordered, **only to the peers whose recorded space is `"zoo"`** (and drawn locally on a solo or host device);
  - `brain.events` is an `Array` of `{"kind", "who", "at"}` (plus `species` and `answer` for `"found"`), sent reliably to the zoo peers, then cleared;
  - kinds: `roar`, `bell`, `banana`, `treat`, `splash`, `slide`, `pump`, `shower`, `drums`, `found`.
- **Clients never roll random choices.** They draw a state at `u = (est_time - t0) / dur`, where `est_time = packet.time + seconds since that packet arrived`, using `ZooBrain.path_point`. They never simulate.
- **Late join and arrival:** the authority sends the newest `pack()` to a player at once when their space becomes `"zoo"`. Reconnecting always starts in town (`_spawn_state`).
- **Determinism:** the brain's behaviour depends only on the seed, the steps and its inputs. Tests run fixed seeds; the network seed is `int(Time.get_unix_time_from_system())` at wake.

## 4. Journey and places

- **Spaces:** `"town"`, `"zoo"`, or a cottage room `"<id>:<floor>:<room>"`. `Places.map_of(space)` is `"town"` or `"zoo"`.
- **The request:** `Session.travel(to: String) -> int`. It sends `rq_action("travel", req, [to])`.
- **The authority,** `_srv_travel(peer, req, to)`:
  - checks that `to` is in `Places.DESTINATIONS[map_of(current)]` and that at least 1.0 s has passed since that peer's last journey;
  - sets `players[peer].state` to the arrival: the zoo uses `ZooMap.ARRIVALS[slot]`, with the slot the first one not taken by another player in the zoo; the town uses the stop's boarding point, else `TOWN_SPAWN`, through `TownModel.tram_stop_boarding(model)` (W1);
  - broadcasts `ev_player_state`;
  - replies `{"ok": true, "space", "x", "z", "ry"}` (plus `"waits": <animal's English name>` when a house visit ended at boarding; see section 10), or `{"ok": false, "error": <English message>}`.
- **`_srv_state` stale-packet rule:** a state whose `map_of(space)` differs from the recorded map is dropped. Moving between the town and its rooms stays allowed.
- **The client** (`PlayController`, Opus):
  - shows the journey card;
  - waits for the reply, at most 8 s;
  - on `ok`, calls `world.set_view(to)`, places the child, and calls `rig.enter_zoo()` or `rig.leave_zoo()`;
  - keeps the card at least 1.2 s;
  - on a refusal or the timeout, stays at its origin, shows the message, and offers the action again.

## 5. Camera (W2)

`CameraRig` keeps `ZOOMS := [9.5, 15.0]` and the town behaviour. It adds:
- `const ZOO_ZOOMS := [8.0, 9.5, 15.0]`, `const ZOO_DEFAULT := 1`;
- `var on_zoo := false`;
- `func enter_zoo()`: remembers the town's `yaw_step` and `zoom`, sets `on_zoo`, `yaw_step = 0`, `zoom = ZOO_DEFAULT`, and snaps;
- `func leave_zoo()`: restores them and snaps;
- `func distance() -> float`: the current zoom's distance; **every** former `ZOOMS[zoom]` read goes through it;
- `func zoom_in()` and `func zoom_out()`: one level, clamped;
- `toggle_zoom()` in the zoo steps 9.5 -> 15 -> 8 -> 9.5; in town it is unchanged;
- `var reduce_motion := false`: when it and `on_zoo` are both true, yaw and zoom changes snap instead of gliding.

The pinch and the wheel in `PlayController._unhandled_input` call `zoom_in()` / `zoom_out()` in the zoo and keep their town behaviour elsewhere. ZL / ZR already arrive as wheel events (`PadInput._wheel`), so `pad_input.gd` is unchanged.

The camera is local state: never saved, never sent.

## 6. Props and scenery (W3): `art/props_zoo.gd`

- **Catalog kinds:** `const KINDS := ["tram_stop", "zoo_ball", "zoo_box", "scratching_log", "leaf_feeder", "hay_bale", "play_mirror"]`.
- **`static func build(kind: String, color: int) -> Node3D`.** Origin at ground centre; the front is +z; merged with `Kit.merge_parts`.
- **Bounds** (w x h x d, m, within 0.12 of the built model, as `test_scale_contract` checks):

  | Kind | Bounds |
  |---|---|
  | `tram_stop` | 3.2 x 2.4 x 2.0 |
  | `zoo_ball` | 0.5 x 0.5 x 0.5 |
  | `zoo_box` | 0.9 x 0.8 x 0.9 |
  | `scratching_log` | 1.8 x 0.8 x 0.8 |
  | `leaf_feeder` | 0.9 x 2.4 x 0.9 |
  | `hay_bale` | 1.1 x 0.8 x 0.8 |
  | `play_mirror` | 1.0 x 1.3 x 0.4 |

- **Scenery builders** (static, returning an unmerged-or-merged `Node3D`; sizes in metres; the y origin at the ground):
  - `tram_car()`, `station(size: Vector2)`;
  - `rock(size: Vector3, seed: int)`: a flat-topped rounded rock block, top at `size.y`; `crag(size: Vector3, seed: int)`;
  - `acacia()` (crown about 2.8 m), `bamboo(size: Vector2)`, `hedge(length: float)`, `shade_tree()`;
  - `water(size: Vector2, depth: float)`, `falls(width: float, height: float)`;
  - `log_bridge(length: float)`, `scratch_tree()`;
  - `ring_run(length: float, height: float, rings: int)`, `tower(height: float)`, `beam(length: float)`, `vine_arch(height: float)`;
  - `spire(heights: Array)`, `hammock()`, `tyre_frame()` and `tyre()` (separate, so the tyre can swing);
  - `bell_rope()`, `bongo_logs()`, `water_pump()`, `shower_arch()`, `treat_table()`, `ball_basket()`;
  - `sign_post(text: String)` (a `Label3D` with the town's sign style), `map_board()`, `lamp()`.

## 7. Model, persistence, compatibility (W1)

- **`TownModel.SCHEMA = 3`.**
  - `from_dict` accepts schemas 1, 2 and 3; 1 -> 3 and 2 -> 3 are migrations reported in `last_migration` (`{"from": n}`).
  - The migration adds a tram stop if there is none.
  - Town contents are otherwise untouched.
- **`var maps := {}`**, saved under `"maps"` only when not empty. Shape: `{"zoo": {"found": {species: {answer: {"by": [nick, ...], "t": int unix}}}}}`. Each part is validated on load: unknown species and answers are kept only as strings, and malformed parts are dropped, never fatal.
- **`is_space("zoo")` is true.** For the zoo, `validate` uses `ZooMap.HALF`, `MAX_ZOO_ITEMS := 80`, no Wishing Tree check, and refuses any position where `ZooMap.blocked_for_child` is true.
- **`Catalog.allowed_in(kind, "zoo")`:** true for `PropsZoo.KINDS` except the tram stop, plus the Picnic list `["bench", "blanket", "flowers", "fence", "garden_umbrella", "picture_board"]`. **Zoo toy kinds are not allowed in the town or the rooms.**
- **The tram stop:**
  - kind `tram_stop`, `space` `"town"`, `category` `""` (it is in no toy box tab), landmark;
  - exactly one per town;
  - `TownModel.ensure_tram_stop()` adds one at the free spot nearest `TRAM_STOP_SPOT` (W1 picks a designed spot 4 to 6 m from `TOWN_SPAWN`, inside the first view) when it is missing; it runs on load and in `make_default`;
  - movable (Decorate);
  - `_srv_remove` and `_srv_wrap` refuse it with "The tram stop stays in town. You can move it.";
  - blueprints skip it;
  - it does not count toward `MAX_TOWN_ITEMS`;
  - `TownModel.tram_stop_boarding(model) -> Variant` returns the boarding point `Vector2` in front of it, or null;
  - its door rule is the cottage door rule (`validate_door`).
- **Files** (`Session.save_now`):
  - the main file is schema 3, as now (tmp, then rename);
  - `<path>.bak` is a **schema-2 projection**: `to_dict()` with `"schema": 2`, without zoo items, the tram stop or `maps`, so an older app falls back to an intact town;
  - `<path>.maps` is a sidecar `{"schema": 3, "items": [zoo items], "maps": maps}`.
  - On the first migration, `<path>.v2` keeps the untouched original, as `.v1` does today.
  - On load, if the main file is schema 2 and a sidecar exists, zoo items (ids remapped if taken) and `maps` are merged back and logged.
  - `Durable` (Apple TV) mirrors the sidecar too, within a stated byte budget.
- **Tests,** `tests/zoo_save_tests.gd`:
  - migrations 1 -> 3 and 2 -> 3 with real fixtures;
  - a frozen schema-2 reader rule (accepts `schema == 2` only, drops unknown kinds and spaces) loads `.bak` with every town item;
  - downgrade and re-upgrade loses no zoo item;
  - damaged `maps` and a damaged sidecar are dropped, not fatal;
  - the tram stop rules;
  - the cap and blocked zoo placements.

## 8. Network (W4): `net/zoo.gd`, autoload `Zoo`

- **`Session.PROTOCOL = 14`.**
- **`rq_action` whitelist adds:** `"travel": 1`, `"zoo_use": 1` (a station id from `ZooMap.STATIONS`), `"zoo_offer": 1` (a resident id).
- **`Zoo` (autoload, after `Animals`) public API:**
  - `signal updated(states: Dictionary)` (the `ZooBrain.unpack` shape, with `time` replaced by the local estimate);
  - `signal effect(kind: String, at: Vector3, who: String)`;
  - `signal found_changed()`;
  - `var states: Dictionary`, the latest unpacked states;
  - `func est_time() -> float`;
  - `func use(station: String) -> int` and `func offer(animal_id: String) -> int` (requests; replies `{"ok"}` or `{"ok": false, "error"}`);
  - `func found(species: String) -> Dictionary`, from `Session.model.maps`;
  - `func hint(species: String) -> String`, the first answer not yet found, from `ZooLife.ANSWERS`.
- **Authority rules:**
  - a station needs the player in the zoo within `ZooMap.STATION_REACH + 0.4` m, and rests 1.2 s;
  - an offer needs the player within 3.5 m of the animal;
  - a `found` event is recorded once per `species/answer`, with the nicks of the players within 8 m, then saved and sent as `ev_town_data("maps", model.maps)`;
  - `Invites.KINDS` gains the zoo invitation ("Come to the zoo with me"), whose Join starts the journey;
  - `Animals` ends a house visit when its child boards (with "%s will wait for you in town.").
- **Tests:** `tests/zoo_net_tests.gd` (solo session: travel, a refusal, stale-state drop, the rest, stations, offers, found recording, the sleeping zoo); and `scripts/net_test.py --zoo` (two real clients on different maps; travel, invite and Join; a late joiner gets states; a drop mid-journey; a restart keeps zoo items).

## 9. Change control and records

- Interfaces in sections 3 to 8 are **frozen at v1**. A worker that needs a change asks the owner. The owner updates this file (with the version and a line in section 10) and tells the affected workers.
- Workers preserve each other's edits, never revert or reformat code they do not own, and re-read a shared file before editing it.
- **No assertion is weakened to pass.** A failing existing test is reported with its output, not edited, unless the owner agrees the test itself was wrong.
- Evidence is raw command output with exit codes and counts.

## 10. Decisions and deviations

| Date | Decision |
|---|---|
| 2026-11-16 | Ridge 0.9 m and Spire moved north (rule H3, `zoo_tests`) |
| 2026-11-16 | Ring and vine anchors are feet positions; hands 1.55 m above (coherence) |
| 2026-11-16 | Social pairs (pass, groom) are exempt from the 3 s same-start rule, as copy and follow are (design 22.4) |
| 2026-11-16 | Camera approval: 45° turns kept; zoom 8, 9.5 and 15 m in the zoo only (design 22.7) |
| 2026-11-16 | Schema 3 with a `.bak` projection and a `.maps` sidecar (design 22.5.4) |
| 2026-11-16 | Tram stop spot moved from (5.5, 8.5) to (−2.0, 5.0): the first spot was just off the iPad's first view (design 9.1 needs both 4 to 6 m and in view); pinned by `zoo_tests` `test_tram_stop_in_first_view` |
| 2026-11-16 | Travel reply: a house visit that ends on boarding is reported as `"waits": <the animal's English name>` instead of an English sentence `note`; the client says "%s will wait for you in town." in its language |
| 2026-11-16 | The toy box asks `Catalog.offered(kind, space)` (W1), so the tram stop is in no tab, All and Recent included; `test_catalog` pins it |
| 2026-11-16 | `test_activity_guide` (W5) extended to nine entries with "zoo" last; existing checks unchanged otherwise |
| 2026-11-16 | Zoo photo ideas live in `PhotoIdeas.ZOO_IDEAS` and are judged only in the zoo; the town board keeps its eight (W5) |
| 2026-11-16 | The audit of "town" literals (design 12.2) fixed music in the zoo (`Places.music`), room labels rebuilt for the zoo on a language change, and the guide's and placement's messages in the zoo; `zoo_tests` `test_town_literal_audit` pins the 218 remaining literals per file |
| 2026-11-16 | Journey: timed by game frames (a background pause waits, 12.4); on the 8 s timeout the client asks to travel back to its origin; a dropped connection closes the card; "Welcome to the zoo!" once per device |
| 2026-11-16 | Monkeys answering a child: a resting monkey, or one busy in place with something of its own, steps aside (`_make_way`, a response, not a self-chosen move); on a one-monkey path with nowhere to step, the two pass each other; the climber's route avoids occupied anchors when one exists; anchors ahead of such a monkey are reserved from the others' own choices; head-on meetings: the one not answering a child turns back; any planned step waits at most 8 s (`PLAN_WAIT_MAX`), then the plan is dropped. The bell: a monkey already climbing to the top rings it; else the highest monkey on the Spire (after its current action); else the nearest free one; others' Spire plans are cut; a ring already under way answers a second ring. Pinned by `test_bell_always_rings` (120 quiet seeds: every accepted ring within 25 s, at most 6 refused; 60 seeds after a dance at the Court: every accepted ring within 25 s, at most 3 refused). 400-seed probe on the final code: 0 refused, 0 missed, worst 18.1 s (first rule: 7 refused of 40, 1 never rang) |
| 2026-11-16 | The scrapbook's "Zoo friends" is its own page (a button in the scrapbook, Back returns), as design 10.6 says "page": inline, it pushed the photos beyond ZR's reach in `tv_tour` |
| 2026-11-16 | Plaza benches are `ZooMap.SOLIDS` of kind `bench` (the town's bench model); the lion's mane shake follows basking; the zoo invitation button sits beside Ride home while a friend is elsewhere |
| 2026-11-16 | Test expectations amended to the new rules, each with its intent kept: schema 3 in `town_play_tests` and `puzzle_ride_tests`; nine guide entries in `first_steps_tests`; the late joiner's "running zoo" check in `zoo_bot` uses the same rule as Sky's (more than 3 s plus its own wait), not a fixed 8 s that assumed the other bots' pace |

## 11. Imported animals: the Everything Library six (candidate `zoo` r2, contract v2)

**Scope.** The user selected the six Everything Library models (CC BY 4.0, David OReilly) for the real zoo. The verified source is `art/everything-zoo-r1/godot-pack` (pack-p1, manifest `39ecae3d…b4c1`), its run3 GLBs and the h3 exporter. Frozen handoffs, zoo r1 and the `.blend` are never edited.
- **Lion, giraffe and zebra:** the imported meshes replace only the **look** of Rory, Topper, Zig and Zag. Ids, names, brain, actions, answers, discovery, stations and network are unchanged.
- **Lioness, tiger, monkeys, hippo and otters** stay procedural. The town's Tumble is untouched.
- **New residents:**
  - Bao the panda, in the new Bamboo Grove (`picnic_green`, x 18 to 40, z −5.5 to 10.5);
  - Mabel the elephant, in Savanna Meadow;
  - Pebble and Flip the penguins, in Splash Bay.

### 11.1 Technique: a skinned imported mesh driven by the existing pivots (W6)

- **Pivots:** `ZooSkin.build(animal, body, species)` (`art/zoo_skin.gd`) builds the same named pivot `Node3D`s the procedural rigs have, at joints measured on the imported mesh (`art/zoo_skin_rigs.gd`, one table per species, metres, model space: +Y up, +Z front, origin at the feet).
- **Skeleton:** it builds a `Skeleton3D` whose bones mirror the pivot tree (bone rest = pivot rest), and one `MeshInstance3D` whose `ArrayMesh` is the GLB's own surface. The positions, normals and `COLOR_0` are unchanged, with deterministic `ARRAY_BONES` and `ARRAY_WEIGHTS` added.
- **Weights** are a pure function of a vertex's position and the rig table, so split vertices at the same place get the same weights and nothing cracks.
  - Each bone influences only vertices on its own side and region: a left leg never moves right-leg vertices, and legs never take head vertices.
  - Weights blend linearly across a band at each joint. At most 4 influences; they sum to 1.
- **The material:** made in code. Vertex colour as albedo (linear), Lambert wrap, roughness 1, metallic 0, back faces culled, no texture.
- **Each frame:** `ZooAnimal._pose` eases the pivots exactly as before. Then `ZooSkin.sync()` copies every pivot's local transform into its bone pose.
  - For lion, giraffe and zebra, every existing pose and action drives the imported mesh unchanged.
  - The jaw has no vertices of its own on the imported meshes, so roar and yawn show as a head lift. That is a documented limitation.
- **Pivot names per species.** Each must exist; a test checks every name `_pose_animal` sets for the species:
  - **lion, panda:** `leg_fl`, `leg_fl_low`, `leg_fr`, `leg_fr_low`, `leg_bl`, `leg_bl_low`, `leg_br`, `leg_br_low`, `neck`, `head` (child of `neck`), `jaw` (child of `head`), `ear_l`, `ear_r` (children of `head`), `tail0`…`tail3`.
    - lion `tail0`…`tail3`, panda `tail0` only;
    - the lion has no ear pivots.
  - **giraffe:** the four legs (+`_low`), `neck`, `neck1`, `head`, `ear_l`, `ear_r`, `jaw`, `tail0`…`tail2`.
  - **zebra:** the four legs (+`_low`), `neck`, `head`, `jaw`, `tail0`…`tail2`.
  - **elephant:** the four legs (+`_low`), `neck`, `head`, `ear_l`, `ear_r`, `trunk0`, `trunk1`, `trunk2` (a chain under `head`), `tail0`, `tail1`.
  - **penguin:** `leg_l`, `leg_r`, `flipper_l`, `flipper_r`, `head`, `tail0`.
  - **All six:** `prop`, a non-bone `Node3D` at the mouth, under `self`, as today.
- **`ZooSkin.build` returns** `{"pivots": {name: Node3D}, "rest": {name: Vector3}, "size": Vector3, "skeleton": Skeleton3D, "mesh": MeshInstance3D}`. `ZooAnimal` (the owner) stores them in `_pivots`, `_rest` and `size`, and calls `ZooSkin.sync(skeleton, pivots)` after `_pose`.
- **New species' poses:** `art/zoo_pose_extra.gd` provides `static func pose(species, action, target: Dictionary, t, amp, u, param, reduce_motion) -> void`. It fills `target` (and `"_off"`, `"_rot"`) for panda, elephant and penguin. The owner calls it from `_pose_animal`.
- **Visible limb motion is required:**
  - four-legged walks swing the upper and lower leg in diagonal pairs, with a phase per animal;
  - penguins waddle: roll and alternate feet;
  - idle shows breathing.
  
  No rigid sliding is presented as a walk.
- **Budgets:** one draw call per imported animal; triangles as in the GLB (776 to 1576).

### 11.2 Actions, footprints, avoidance (W7)

- **`ZooBrain.ACTIONS` stays append-only.** New names are appended at its end: `munch`, `sit_up`, `spray`, `dust`, `ear_flap`, `trumpet`, `waddle`, `flap`, `preen`. Existing names are reused where they fit: `walk`, `nap`, `roll`, `look`, `nod`, `blink`, `eat`, `drink`, `graze`, `swim`, `dive`, `surface`, `slide`, `hop`, `play_ball`.
- **`ZooBrain.SPECIES` gains:**
  - `panda` (height 1.27, length 2.2, radius 0.92);
  - `elephant` (2.40, 3.45, 1.5);
  - `penguin` (1.20, 0.54, 0.42).
  
  The panda's and penguin's GLBs are drawn at 1.15× and 1.2× (`ZooAnimal.SPECIES_SCALE`), so they read at 115 px from their bays like every other resident (decision log, 2026-11-16).
- **Footprint, distinct from the hit shape:**
  - **footprint** = `SPECIES.radius`: a circle on the ground used for avoidance, for keeping animals apart, and against children (existing `_keep_clear`);
  - **hit shape** (`ZooWorld.pick`) = the projected box of the animal's size, at least 44 px.
- **Avoidance (authoritative, deterministic):**
  - no two ground animals target spots closer than the sum of their radii;
  - a walk whose straight path passes within the sum of radii of another animal's position (or its target) goes by one side-step waypoint, or waits and chooses again;
  - every destination lies inside the animal's habitat on a valid surface (`ZooMap.habitat_at`, the spot's area).
- **Physics:** there are **no physics bodies or layers for zoo animals** (collision layer 0, mask 0). All collision is this 2D footprint arithmetic on the authority, so nothing can be launched or trap a child. Children stay outside enclosures by the existing `ZooMap.blocked_for_child`. No triangle-mesh collision anywhere.

- **Events:** `trumpet` (`{"kind","who","at"}`) is emitted when Mabel starts trumpeting. It is the tenth `Zoo.EFFECT_KINDS` entry, and has its own synthesized tone.

### 11.3 Network and saves

- New residents are appended to `ZooMap.ORDER`, which changes the packed state: **protocol 15**.
- Discovery keys are species and answer strings, so they need no schema change (schema stays 3).

### 11.4 Attribution

The GLBs ship in `game/assets/models/zoo_everything/`, with the notice next to them. The credit appears:
- in-game, on the "Zoo friends" page;
- in `docs/assets.md`;
- in the r2 request.
| 2026-11-16 | zoo r2: the six Everything Library models are skinned (`ZooSkin`). They are driven by the procedural rigs' pivot names, so Rory, Topper, Zig and Zag keep every action. The jaw has no vertices of its own, so roar and yawn show as a head lift; blink is a small head dip |
| 2026-11-16 | zoo r2, readability: panda and penguin scaled 1.15× and 1.2× (1.27 m, 1.20 m). The panda's spots moved toward the grove gate and the penguins' swim spots toward the beach. The penguins got their own shore belly-slide; the otters' slide stays theirs. `zoo_tests` measures heights as drawn (root scale included) |
| 2026-11-16 | zoo r2, avoidance (W7): footprint circles on the authority for every ground and water animal (spot reservation, a side-step waypoint or a wait, water detours). Ground animals draw from their own random stream (`grng`), so the monkeys' seeded runs are unchanged. No physics bodies or layers |
| 2026-11-16 | zoo r2, protocol 15: Bao, Mabel, Pebble and Flip appended to `ZooMap.ORDER`. Schema stays 3 |
