# A Three.js city beside the Godot city: investigation and plan

**Status:** investigation 2026-11-17, then implementation the same day (§6), as candidate `city-web` r1. The user queued this after city r3. Its purpose is to evaluate how Three.js content runs on the hardware that runs Lantern Lane. The player chooses, inside the game, which city to enter: the Godot city (unchanged but for one fix, §6.1) or a separate Three.js city. In both, the Lantern Lane child is present and playable. The Apple TV route without a web view is studied in §7.

**Not authorized by this task:** publish, deploy, commit or push.

## 1. What each target can run

| Target | Can it run a Three.js city inside the game? | How | Confidence |
|---|---|---|---|
| **iPad, iPhone** (iOS / iPadOS, Godot 4.7.2, Compatibility renderer) | **Yes, by an in-app web view.** WKWebView renders WebGL 2, so Three.js runs in it. | A small native iOS plugin (`.gdip` plus an xcframework, the same pattern as the existing `game/ios/plugins/photo_library`) puts a WKWebView over Godot's view. The city's page is bundled in the app, and a message bridge carries state and input between Godot and the page. | Sound in principle. **Unproven here:** nothing is built or run yet. |
| **Apple TV** (tvOS, the project's custom engine fork) | **Not by a web view**: WebKit, and so WKWebView, is not available on tvOS. **A candidate route without a web view is under study (§7):** NativeScript with @nativescript/canvas 3.x, a native WebGL/WebGPU canvas for tvOS, plus a Three.js adapter. | Its packages and binaries are verified (§7.2). Nothing is built or run here, and nothing shows that our city runs, or how fast it runs, on an Apple TV. | WebKit absent: high (Apple). The Canvas route: **unverified on hardware**. |
| **Mac** (development) | Yes, in a desktop browser or a macOS web view. | Useful for development and desktop timing. **It is not target hardware.** | High. |
| **EC2** (this machine) | Logic only. | Playwright's headless Chromium with software WebGL (SwiftShader) can load the page and run its logic tests. **Its frame rates say nothing about devices**, and nothing it renders is art evidence. | High. |

**Consequence:** until the Canvas route of §7 is proven on a physical Apple TV, the choice of city on Apple TV shows only the Godot city. The Three.js city is offered only where it was built and tested; an untested platform is never called supported. The route is not rejected because tvOS lacks WKWebView.

## 2. How it fits the game (owner's proposal)

**Godot stays the game.** The session, the network, the child's movement and navigation, the shared rules, the HUD and saves all stay in Godot. The Three.js page is a **renderer and input surface** for the city.
- **Godot → page, about 30 to 60 times a second:**
  - the camera pose, the child's and friends' positions, levels and poses;
  - the shared City state (vehicles, riders, seats, weather and its time);
  - the view clock.
- **Page → Godot:** a tap's floor-aware hit (the page casts the ray against its own floors and walls), drags and zooms (or the page owns the camera and reports it), and the HUD actions it shows.
- **Why:** the comparison is then like for like. The same rules, people timetable, traffic and weather run the same way, and only the drawing differs. It is also the only way the child's movement and multiplayer stay exactly the game's.

**Two separate cities, as asked.**
- **Maps:** a new map id, `city_web`, beside `city`. Children in one city do not see the other.
- **The tram stop** offers the choice: "Ride to the city" (Godot) and "Ride to the city (web)".
- **Authority:** the City authority holds one shared state per city map. The protocol rises once more for the second map and its travel.

**HUD.** Godot's HUD draws in Godot's view, which the web view would cover. So the page draws a small matching HUD (Ride home, Reset view, Look, Pause, weather) and sends each press to Godot as the same request the Godot HUD makes.

**Content.** The same city from the same data. `city_map.gd` and the people's data are exported to JSON by a Godot script, so the two cities cannot drift. The Three.js code rebuilds them:
- buildings, interiors and furniture;
- the 52 people;
- rain and night;
- the wheel, the carousel and the buses;
- Look with its glides.

It is like for like, not pixel for pixel.

**Three.js itself.** One vendored, version-pinned file (MIT licence, recorded in `docs/assets.md`), bundled in the app. Nothing is loaded from the network at runtime.

## 3. How results will be told apart

Every result names where it came from:
- **EC2 headless:** logic only, software WebGL. No timing claims.
- **Mac desktop browser:** frame time on a Mac. Not a device.
- **iOS Simulator:** it runs; its performance means nothing.
- **Real iPad and iPhone:** the only performance evidence. It needs a signed build installed on the devices.
- **Apple TV:** no web view (§1); the Canvas route is under study (§7). Its results are labelled "Apple TV, NativeScript Canvas prototype" and are never mixed with the iPad and iPhone results.

Both cities are measured in the same scenes by a scripted camera path: overview, Look into each building, rain and night. The measures are frame time (median and 95th percentile), memory, launch-to-first-frame of the city, and thermal state after 10 minutes. The Three.js city records these with the page's own timers; the Godot city with its performance monitors.

## 4. Phases

1. **EC2:**
   - the data export;
   - the Three.js city page (content, people, rain and night, rides, buses, Look, HUD);
   - the bridge protocol and a desktop harness that plays Godot's side from recorded states;
   - logic tests in headless Chromium.
2. **EC2:** the Godot side.
   - the `city_web` map and travel;
   - the authority's second city;
   - the bridge calls (no-ops where no web view exists);
   - the choice at the tram stop on iOS only, plus a desktop fallback for testing on the Mac.
3. **EC2 (source), Mac (build):** the iOS WebKit plugin (Objective-C++), built with the plugin's `build.sh` on the Mac, then tried in the Simulator.
4. **Mac and devices:**
   - signed builds on the iPad and iPhone;
   - the measured comparison;
   - the tvOS SDK check that confirms §1.

**Needs the user's explicit authorization:** installing on devices in step 4. This task authorizes no publication, deployment, commit or push, and installation has always been authorized separately.

## 5. Risks

- **Memory and performance:** a WKWebView runs its own process and WebGL context beside Godot's renderer, so memory and battery use rise. Godot should stop drawing its 3D world while the web city is shown.
- **Bridge timing:** state crosses a process boundary. 30 to 60 messages a second is usual for WKWebView, but it must be measured on devices.
- **Input:** the web view takes touch; the page forwards what Godot needs. On Apple TV (§7) input would come from the Siri Remote and game controllers instead.
- **Review:** Apple accepts in-app WKWebView content that is bundled with the app.

## Sources

- Apple TV and WebKit: Daniel Pasco, "Apple TV: A World Without Webviews" (Black Pixel, Medium, 2015); Apple developer forums threads 698287 (WebKit only on iOS, iPadOS, macOS) and 849373 (tvOS has no WebKit); the FakeWebKit project (a UIWebView wrapper that relies on a private API).
- Godot iOS plugins: Godot documentation, "Creating iOS plugins" (`.gdip` plus `.xcframework`); this project's `game/ios/plugins/photo_library`. Experimental WebView embedding: the Godot Kirie project (WKWebView with bidirectional IPC).

## 6. Implementation (from 2026-11-17)

The user authorized the implementation (`build/dual-host/city-r2/CHECKPOINT.md`). For this build the user then authorized, after validation and the seal, the bounded three-target release: **iPad** (both cities), **Apple TV** (the main game with the Godot city only; no Three.js and no prototype on tvOS) and the **existing HK server**, with iPhone excluded (`build/dual-host/city-web/CHECKPOINT.md`). Commit and push stay unauthorized. Work state: `build/dual-host/city-web/CHECKPOINT.md`.

### 6.1 The same city, exported, not retyped

- **Geometry:** `game/tests/web_city/export.gd` runs Godot's own city builder (`CityWorld.build()` plus the people's part meshes) headless and writes it as a mesh pack (`scripts/web/mesh_pack.gd`): `game/web_city/data/city.json` and `city.bin`, 319,444 vertices, 7.3 MB. The export is deterministic (two runs are byte-identical), and the battery checks that the checked-in files equal a fresh export.
- **Data:** every constant of the city's scripts goes to `data/consts.json` (`scripts/web/web_json.gd` convention). The page's ports read numbers from there, never retype them.
- **Behaviour:** the functions that move things are ported to JavaScript function by function (wheel, carousel, vehicles, weather, people, camera). Godot dumps their results at chosen times (`tests/web_city/parity_<area>.gd`), and Node tests (`scripts/web_city/*.test.mjs`) compare the ports with them.
- **A Godot city fix found by the export:** `city_world._ceiling_lights` wrote into a glow accumulator whose frame a sign had left set, so the top-floor ceiling panels of the office, gym and cafe were displaced (two sets floated in the sky). The frame is reset now; both cities get the fix.
- **Shading as Godot draws it:** the project renders with Godot's Compatibility renderer everywhere.
  - Light energies become Three.js intensities of π·E, with Godot's lambert-wrap diffuse and specular.
  - **Emission is not scaled the same way.** Godot multiplies the sRGB emission colour by its energy and only then converts it to linear (`world_logic.godotEmission`, checked against the engine's shader text).
  - r1 and r2 scaled it like a light. The Mac's real-GPU frames showed the night cabins about 2.5 times too bright and washed peach; r3 corrects this.
  - The bulbs and signs (energy 1.6) clip either way.
- **Three.js:** 0.186.1, vendored as `game/web_city/vendor/three.core.js` and `three.module.js` (MIT, `THREE_LICENSE.txt`), npm integrity `sha512-blFeqb49…CCb8jA==` checked at download. Nothing loads from the network at run time.

### 6.2 Who does what at run time

- **Godot (the game):** the session and network, the City authority (a second instance, `CityWeb`, for the map `city_web`), the child's movement, routes and actions, friends, saves, sounds.
- **The page:** drawing, the camera (orbit, zoom, pan, Look and its glides, all ported), the people, the wheel, carousel and buses, the weather's look, Pause, and the page's HUD.
- **Picking** stays Godot's: the page sends a tap as a ray, and Godot runs the same floor-aware `CityNav.pick` as the Godot city.

### 6.3 Bridge protocol v1

One JSON object per message, with its type in `t`.
- **iOS:** the page posts text with `window.webkit.messageHandlers.godot.postMessage`, and Godot calls `window.LL.recv(object)`.
- **Desktop (Mac, EC2):** Godot serves the page over HTTP and the messages over a WebSocket, both on 127.0.0.1 only.

**Godot to page:**

| t | When | Fields |
|---|---|---|
| `hello` | the page is ready, or the city is entered again | `v` (1), `me` (peer id), `map`, `platform` (`ios`, `desktop`), `locale`, `strings` (English text to translated text, for the page's words) |
| `frame` | every Godot frame | `clock` (City est_time), `me` {`id`, `level`, `pos` [x, z], `riding` (gondola or -1), `hold` (key or ""), `ctx` ({`type`, `label`, `icon`}: the action button, translated) or null}, `kids` [{`id`, `me`, `rev` (rig revision), `xf` (12 floats, world), `anim`, `ride` ({`g`, `slot`}) or null, `pose` (the rig's pose, defined by the kids code)}] |
| `states` | each City update (4 a second) | `s`: the City states, client form (net/city.gd header) in the web_json convention |
| `effect` | a City effect | `kind`, `data` |
| `cutaway` | when the hidden storeys change | `hidden` (what CityWorld.apply_hidden takes), `regions` (what the people's set_hidden_regions takes) |
| `kid_model` | a child appears or changes looks | `id`, `rev`, `pack` (a mesh pack header), `bin` (base64) |
| `kid_gone` | a child leaves the city | `id` |
| `toast`, `hint` | as the Godot HUD would show them | `text` (translated) |
| `bye` | the child leaves the web city | nothing |

**Page to Godot:**

| t | When | Fields |
|---|---|---|
| `ready` | the city is loaded | `v`, `w`, `h`, `dpr`, `load_ms`, `failed` (modules that did not start), `ua` |
| `first_frame` | the first frame is drawn | `ms` since the page started |
| `tap` | a play tap (not in Look) | `o` [x, y, z], `d` [x, y, z]: the camera ray |
| `act` | the action button | nothing: Godot does its current context |
| `weather` | a weather button | `w` (index into CityMap.WEATHERS) |
| `home` | the Town button | nothing: the child rides home |
| `look`, `pause` | Look or Pause changed | `on` (information for Godot's records) |
| `cam` | 10 times a second | `pos`, `target` (Godot's sound listener) |
| `perf` | once a second | `fps`, `p50`, `p95`, `max` (frame ms), `calls`, `triangles`, `geometries`, `textures`, `heap` |
| `log` | page errors and warnings | `level`, `text` |

### 6.4 Page modules and their owners

`js/main.js`, `meshpack.js`, `consts.js`, `clock.js`, `bridge.js`, `harness.js` and the core of `rules.js` are the owner's. The others are workers':
- `world.js`: the moving city, the weather and night, the lights and sky;
- `people.js`: the people;
- `camera.js` and `hud.js`: the camera, the input and the page's HUD;
- `kids.js`: the children, from Godot's rigs.

Each exports `init(app)` and publishes its API on `app`: `app.world`, `app.people`, `app.cameraRig`, `app.hud`, `app.kids`.

## 7. Apple TV without a web view: the NativeScript Canvas lead (2026-11-17)

**Source:** user-supplied research, relayed on 2026-11-17. It proposes NativeScript with `@nativescript/canvas` 3.x and `@nativescript/canvas-three` to render Three.js locally on Apple TV, with no WKWebView, no AirPlay and no streaming.
- Its claims were treated as unverified and checked by the owner against primary sources: the npm registry, package tarballs and their binaries, GitHub releases and the projects' own pages.
- **What this is not:** a benchmark of our city. Nothing here was built or run on an Apple TV. Nothing shows that our city runs there, outperforms Godot there, or can share one app with the Godot game.

### 7.1 What changes in the assessment

- The earlier verdict "Apple TV: no" rested on WebKit's absence. That still holds for WKWebView, but it is no longer the end of the question.
- A native WebGL2/WebGPU canvas for tvOS exists as a maintained package with tvOS binaries.
- Apple TV is therefore **an open question to answer on hardware**, neither rejected nor supported.

### 7.2 Claims checked (owner, 2026-11-17)

| Claim in the report | Finding | Status |
|---|---|---|
| Canvas documents tvOS 13+ | The installation page's platform table: "tvOS 13.0, New in 3.0". `CanvasNativeBinary/Package.swift` in 3.0.10 declares `.tvOS(.v13)`. | **Verified** (documentation and manifest) |
| WebGL2 and WebGPU/Metal on tvOS | Contexts table: webgl and webgl2 "Yes" and webgpu "Yes (Metal)" under "iOS / tvOS". The Metal-only, no-WebGL note is for visionOS. The 3.0.10 release's `CanvasNative.xcframework.zip` (140,357,966 bytes; its SHA-256 `238897bb…a081a` equals the checksum in the package manifest) has `tvos-arm64` and `tvos-arm64-simulator` slices. The tvOS binary references EAGL/OpenGL ES, the system Metal device and wgpu. | **Verified** that the binaries exist. That they render correctly on hardware is **unverified**. |
| WebGL on tvOS rests on OpenGL ES | The tvOS binary links EAGL and OpenGL ES. Apple deprecated OpenGL ES (a long-term risk); the WebGPU path uses Metal through wgpu. | **Inferred from the binary**; to be confirmed on the device |
| A Three.js adapter wrapping 0.184 | The adapters page says "@nativescript/canvas-three bundles three 0.184". The registry shows both `canvas-three@3.0.10` and `@3.0.0-alpha.10` depend on `three` **0.184.0** exactly. Our page vendors **0.186.1**: the prototype must test our code on 0.184.0 or show that 0.186.1 works through the polyfill. | **Verified** (version); compatibility with our code **unverified** |
| SolidTV ran its own WebGL2 renderer at 60 FPS on a physical Apple TV HD, with remote input and suspend/resume | solidtv.dev says "60 fps on real hardware. Measured on a physical Apple TV HD with the WebGL2 renderer" and "Siri Remote presses, the Menu button and suspend and resume are wired up". This is the vendor's own statement about its own 2D UI renderer (`@solidtv/renderer`), not Three.js. | **Verified that the claim is published.** The measurement itself is **unverified**; it is not a Three.js benchmark. |
| The example pins `@nativescript/tvos` 9.1.0, CLI/core 9.2.0-tvos.0, canvas 3.0.0-alpha.10, and uses `link:` workspace dependencies | `solid-demo-app/nativescript/package.json` (main): `@nativescript/canvas` and `canvas-polyfill` 3.0.0-alpha.10, `@nativescript/core` 9.2.0-tvos.0, `nativescript` (CLI) 9.2.0-tvos.0, `@nativescript/tvos` 9.1.0, `@nativescript/ios` 9.1.0, `@nativescript/webpack` 5.0.39-tvos.0, `typescript` ~6.0.0, `pnpm` 10.33.4. `@solidtv/nativescript`, `renderer` and `solid` are `link:../../…` paths outside that repository, so the folder does not build alone. `github.com/solid-tv/nativescript` answers 404, though npm has `@solidtv/nativescript` 0.2.0 with its source. | **Verified** |
| Current versions | At check time: `@nativescript/canvas`, `canvas-three`, `canvas-polyfill` and `canvas-gamepad` latest **3.0.10** (published 2026-11-16; eight 3.0.x releases from 11-09 to 11-16, so fast-moving); `@nativescript/tvos` **9.1.0** (2026-09-13); `@nativescript/core` latest 9.1.4, tag `tvos` = 9.2.0-tvos.0; CLI `nativescript` latest 9.1.2, tag `tvos` = 9.2.0-tvos.0. Canvas is Apache-2.0. | **Verified** |
| Commands `npx ns build tvos`, `npx ns run tvos --emulator --no-hmr` | The demo's `package.json` scripts are `ns build tvos` and `ns run tvos --emulator --no-hmr`. | **Verified that they are written**; **not run** by the report or by us |
| Apple V8 has no JIT | `@nativescript/tvos` 9.1.0 embeds V8 **14.9.207.39** (from its tvOS binary). Its headers mention code paths that "only fire on JIT-enabled embeds". Apple does not let third-party tvOS apps make memory executable, so V8 must run without JIT there. | **Consistent with platform rules**; the runtime's flags are to be confirmed on the device |
| `EXT_disjoint_timer_query_webgl2` unavailable | Canvas 3.0.10 implements wrappers for `EXT_disjoint_timer_query` and `_webgl2`. Whether the extension is offered depends on Apple's OpenGL ES driver. | **Unverified**: check `getSupportedExtensions()` on the device. GPU timing must come from Instruments in any case. |
| Synchronous graphics queries can stall | General WebGL behaviour (`readPixels`, `getError` and others). Not specific evidence. | Plausible; measure |
| `canvas-gamepad` uses Apple GameController; the Siri Remote is not a Gamepad API controller | `canvas-gamepad` 3.0.10's native source uses `GCController` and `GCExtendedGamepad` only (no `GCMicroGamepad`). SolidTV handles the remote with `pressesBegan` and `UIPressType`. | **Verified**: the remote needs its own press handling |
| Other routes: JSContext gives no WebGL/Canvas; Chromium for tvOS is experimental and single-process; Three Native targets iPhone | Chromium's iOS build instructions: "Blink for tvOS is an experimental project … runs in a single-process mode only". The three-native README covers iPhone only, through React Native WebGPU, Dawn and Metal ("Early alpha", Three.js 0.186.0); it says nothing about tvOS. | **Verified** as stated |
| A Godot tvOS build must first be obtained | Generic. This project already has an Apple TV lane: the `stuartcarnie/godot` `tvos_platform` fork at `791c358`, with the Mobile/Metal renderer, the LanternDefaults custom module and an accepted device build (`scripts/tvos/README.md`). | **Superseded** by the project's own lane |
| Personal Team signing limits, Developer Mode, TestFlight | Not checked for tvOS here; generic iOS rules are not assumed. The project's Apple TV lane already signs and installs through the private inventory (`docs/release-workflow.md`). TestFlight and App Store review are separate from local tests and are not in scope. | **Unverified for tvOS**; not needed while the existing lane's signing is used |

### 7.3 Same-process integration

**What it needs.** The user asked for one game with an in-game choice of two playable cities. Two apps joined by URL schemes are two processes. They would not give a seamless switch, a shared session, or the same child, so they do not meet the requirement. A standalone NativeScript app is only a feasibility step.

**What exists.** The NativeScript tvOS runtime's public header has `initWithConfig:`, `runScriptString:runLoop:`, `restartWithConfig:` and `shutdownRuntime`, besides `runMainApplication`, which takes over `UIApplicationMain`. That suggests the runtime could start inside another app, the Godot tvOS host. That host already links a custom native module, in the same way as the iOS WebView plugin.

**What is not verified.**
- The NativeScript build step: its Objective-C metadata section and its webpack bundle.
- Whether that step can be folded into Godot's exported Xcode project.
- Whether a Canvas view can sit over Godot's Metal view with both renderers alive.
- Godot's own Metal rendering must stop while the city shows.
- Focus and Siri Remote presses must be shared between UIKit, NativeScript and Godot's tvOS patches.
- State restoration, for example after a suspend.

Nothing is claimed until a device build shows it.

### 7.4 Plan (bounded, in order)

1. **Cube** (feasibility only): a separate NativeScript tvOS app.
   - Content: Canvas plus canvas-three; `WebGLRenderer({canvas})`, pixel ratio 1, `setAnimationLoop`.
   - Input: the arrows rotate, Select (Enter) pauses. Siri Remote presses through UIKit presses, a Bluetooth controller through GameController.
   - Lifecycle: suspend stops the loop and resume restarts its timing; cleanup on exit.
   - Measured on a physical Apple TV:
     - frame rate: average FPS, P95 frame time, displayed frame cadence from Instruments rather than the JS loop's own count;
     - time to the first frame;
     - memory: peak process memory in bytes from Instruments (`renderer.info.memory` counts resources, not bytes);
     - CPU and GPU;
     - endurance: 30 minutes of stability and 10 suspend/resume cycles;
     - scaling: 100, 1,000 and 5,000 Meshes against one InstancedMesh.
2. **A small street section of our city:**
   - our exported mesh pack (one street, a building, the people's instanced parts), loaded with our `meshpack.js` on Three.js 0.184.0;
   - our shaders (the rain, the Godot shading patch), transparency and the colour pass, each checked on its own;
   - fonts and paths.
3. **Only then** the city modules, and same-process integration into the Godot tvOS host (§7.3).
4. **Comparison with Godot:** the same Apple TV model, resolution, camera path, content and quality settings in both.

**Authorizations this needs, not yet given:**
- **Install the prototype on the user's Apple TV:** this build's Apple TV release is the main game with the Godot city only; it does not cover the prototype.
- **Install the toolchain on the Mac:** the NativeScript tvOS CLI (`nativescript@9.2.0-tvos.0`), the project's npm dependencies, and the 140 MB CanvasNative framework that SwiftPM fetches. The research does not authorize new system toolchains.

**EC2 can:** write the prototype's source and its measurement and test plan. That is done without installing anything.

### 6.5 Measuring both cities

- **Running it:** `--city-bench=godot|web` (a launch argument; `--city-bench-scale`, `--city-bench-quit`) runs `scripts/web/city_bench.gd`. It starts a solo game, rides to the chosen city and plays the same path through it: the overview, Look into every place, back out, rain, night, sunny.
- **What each side records:**
  - **Godot city:** the engine's frame times.
  - **Web city:** the page's JS-loop frame times, tagged by phase in `web_city_perf.jsonl`.
  - **Both:** once a second, memory and, with the WebView plugin, the thermal state and the app's footprint (`city_bench.jsonl`).
- **Reporting:** `scripts/web_city/bench_report.py --source "<device, real or simulated>"` prints the two side by side. The source label is required.
- **What these numbers are not:**
  - neither is the displayed frame cadence;
  - the app footprint leaves out WebKit's own processes.
  - Instruments supplies the displayed cadence and the processes' memory.
- **Checked on EC2:** `scripts/web_city/bench_check.mjs` shows the path runs end to end. Its numbers are not evidence.
