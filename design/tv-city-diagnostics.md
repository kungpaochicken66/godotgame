# The Apple TV: what the two city modes can be compared on, and the diagnostic logs

**Status:** tv-diag r1, 2026-11-18. EC2 source owner. Work log: `build/dual-host/tv-diag/CHECKPOINT.md`.

## 1. The tvOS boundary

- **The iPad's web city cannot run on Apple TV,** because tvOS has no WKWebView. The TV build leaves out `web_view.gdip`, and `Places.available("city_web")` is false on a TV.
  - **That rules out hosting the page in a browser view only, not every Three.js route.** A native tvOS port, NativeScript Canvas with Three.js (`prototypes/tvos-canvas-three/`), is a different route. The user has authorized building and testing it on the Apple TV (`design/city-threejs.md` §7).
  - It is a separate app with its own runtime: NativeScript, Canvas and three 0.184.
  - Its numbers are its own. They are **not** the iPad's web mode, and **not** a city comparison until it shows the same city.
- **AirPlay is not TV rendering.**
- **What is measured honestly, each labelled by device and runtime:**
  - both city modes on the **same iPad**;
  - the **Godot city on the Apple TV**;
  - later, the **NativeScript prototype on the same Apple TV**, but only rows with equivalent content count as comparable.

## 2. The decision contract (the user's)

- **No route is chosen or retired now.** Both routes are kept.
- **At the end, two costs are evaluated:**
  - **Development cost:** actual setup, porting, debugging and packaging, recorded **separately** from the estimated future cost of scenes, interactions, controllers and cross-platform maintenance, with the assumptions and the uncertainty.
  - **Runtime cost:** on the **same Apple TV**, at the same resolution, with equivalent content (the city, people, weather, camera, path), from measured sources (frames, CPU, GPU, memory, load).
- **Any mismatch makes a row non-comparable.**
- **Subjective experience is kept separate,** for the user's decision. The owner's earlier leaning toward native Godot is a hypothesis, not a decision (`design/engine-route-evaluation.md`).

## 3. The logs (opt-in launch arguments; no user or save data)

**`--city-bench=godot|web [--city-bench-scale=1.0] [--city-bench-quit]`** writes `user://city_bench.jsonl`. On tvOS, `user://` is under `Library/Caches/GodotApp/`. The benchmark plays on its own town save, `city_bench_town.json`.

**The run line:**
- the build, engine, runtime, rendering method, adapter and API, TV mode and tvOS, the window;
- **the controller:** name, GUID (a mapping id), layout, the printed confirm and back letters, vendor and product ids;
- **`timing`:** what shapes the frame numbers. Delta smoothing, `max_fps`, physics ticks, time scale, vsync mode, the screen's refresh rate;
- **`unavailable`:** each field Godot cannot give, with the reason and where to measure it.

**The `load` line:** ride → arrival, and ride → the first drawn city frame. On the web, also ride → page ready. Headless says the first frame is unavailable.
- **It is ride-scoped.** The time before the ride is not in it.
- **Since r2 it also records:**
  - the engine clock at the run header and at the ride;
  - the app's focus and pause events before the ride;
  - `valid_for_startup`, false (with the reason) only if such an event happens **during** the ride;
  - the longest gap between its 200 ms polls, as information only: it includes the city's synchronous build.
- **Process-launch (cold) startup is not measured** by Godot's clock. Use Instruments' App Launch.

**`app` lines (r2):** focus in and out, pause and resume, with the phase.

**`controller_change` lines (r2):** a controller connected or disconnected, with its info.

**`second` lines, once a second:**
- the engine-delta statistics: fps, p50, p95, **p99**, max. These may be smoothed. On the r3 Apple TV they read 20.0 ms throughout, which is 1/50 Hz.
- **`wall`:** the monotonic main-loop interval, with the same statistics;
- Godot's process and physics time (`_ms`), objects, nodes, objects in the frame, draw calls, primitives;
- `static_mb` and `video_mb`, each with a scope note: **Godot's own figures, not the process's or the GPU's totals**;
- on the iPad, the WebView plugin's `stats` (the app's footprint, thermal state).

**The `summary` line per phase:** both timing sources.

**The `controller` line per phase:**
- since r2, the **current** `controller_info` (the run header samples it once, possibly before the app is in front and the controller is enumerated);
- actions by role, trigger pulls, stick pushes;
- **`origin_synthetic`:** events a test driver tagged where it made them (meta `synthetic`);
- **`origin_untagged`:** all others. That is real hardware **or any untagged source**; an event alone cannot prove its origin.

**Neither timing source is the displayed cadence.** The process's CPU, memory and GPU totals, and the displayed frame rate, come from **Instruments** on the Mac: Game Performance, Game Memory, Metal System Trace, Time Profiler, Activity Monitor. They are recorded beside the log, labelled with their tool.

**`--pad-trace`:** prints the controller identity (`PADINFO`) when one is chosen, and one line per action (`PADTRACE`). For diagnosis only.

## 4. The controller-only route audit and the r2 fixes

**The audit driver:** `game/tests/tv_route_audit.gd`. It walks the Apple TV route with one Nintendo-layout controller:
- title → town → tram → city (walk, camera, zoom, Look, Reset view, a seat, weather) → home → Decorate;
- it uses only synthetic joypad events, tagged at their source;
- each step records the hints, the pointer, the focus targets, the TV title-safe area, what B does, and any accidental action.
- **It never fails on a finding,** only on a step it cannot carry out.

**Run it:** `scripts/godot.sh --headless --path game -- --driver=res://tests/tv_route_audit.gd --tv --pad-layout=nintendo --window=1920x1080 --no-shots [--pad-trace]`.

**Headless shows:** logic, states, hint texts, rectangles, the D-pad map and B's effect.

**It cannot show:**
- feel and timing;
- the rendered picture;
- the letters printed on a controller, and how tvOS maps it;
- the Siri Remote;
- a controller that connects late.

| Audit finding (r1 behaviour) | r2 change (`pad_input.gd` unless noted) |
|---|---|
| A D-pad press could land on a moving town name tag ("Zoo tram"): one A rode to the zoo | The world's name tags are not D-pad stops. The pointer still reaches them. |
| A on Leave town ended the session at once | With the controller, A on Leave town asks first (`hud.gd` `confirm_leave`: "Not now" / "Leave town"; B is Not now). Touch is unchanged. |
| After A on Look around the button moved and a second A missed | After A, the pointer follows the pressed control if it moves within 20 frames, unless something else moved the pointer. (A fixed two-frame wait passed in one run and missed in the next.) |
| After X Sit down the pointer stayed on the action button, so the next A stood up | The X and Y shortcuts put the pointer back where it was, unless the shortcut opened a card or dialog, or the pointer moved meanwhile. (The first r2 attempt restored it inside the puzzle chest's card, and `puzzle_ride_tour` failed.) |
| — | The page's camera (`web_city/js/camera.js` `toggleZoom`) gets the same Zoom direction fix, for parity. |
| The left stick walked the child out of view while looking | The left stick is ignored while looking. |
| The Look hints showed the walking hints | While looking: A Select, D-pad Look around, B Stop looking, L R Turn camera. |
| The HUD Zoom button in the city only zoomed out (`camera_rig.gd` `toggle_zoom`, step −1) | It steps closer (+1), and from the closest level goes back out to the overview. |
| ZR took 19 pulls from the strolling view to the overview | In the city, ZL and ZR step one zoom level per pull. |
| D-pad jumps almost sideways | **Partly:** targets within 60° of the pressed direction are preferred. Where none exists, the nearest target is still taken, to keep buttons reachable, so some sideways jumps remain. |

**Text:** no new text. Every hint and dialog reuses existing catalog strings, present in all six locales.

**Remaining findings (r2 run, 9; none a blocker):**
- **Awkward:**
  - sideways D-pad fallbacks;
  - A over open world walks the child (as designed);
  - no analog orbit on the right stick;
  - while looking, five buttons are reached only with the right stick;
  - in the city, the D-pad reaches "Leave town" (now asked first).
- **Cosmetic:**
  - "B Back" at the title;
  - the hint bar over the journey card;
  - the play hints don't name the stick or ZL/ZR;
  - the stick does nothing while seated.

**The evidence:**
- r1 behaviour: `build/dual-host/tv-diag/audit/AUDIT-r2.md`, run 4 and run 5;
- after the fixes: run 7 (`run7-after-fixes.log`).
