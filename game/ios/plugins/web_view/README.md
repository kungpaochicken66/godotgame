# WebView: the web view of the Three.js city (iPad and iPhone)

A Godot 4.7.2 iOS plugin that shows one bundled web page in a full-screen `WKWebView` above Godot's view, and carries messages between Godot and the page. It exists for the Three.js city (`design/city-threejs.md`, sections 1, 5 and 6).

- **iPad and iPhone only.** tvOS has no WebKit, so the Apple TV build never contains this plugin (see "Apple TV" below).
- **The page is local.** It is served from a folder of the app through the custom scheme `lantern://city/`, and every navigation to another address is cancelled. The plugin does not block a request the page itself makes to the network (`fetch("https://...")`, an image); the page makes none, and a Content-Security-Policy in `index.html` (for example `default-src lantern: 'unsafe-inline' data: blob:`) would enforce that.
- **Status:** source only. It has never been compiled: this was written on Linux, where there is no Xcode. Build and try it on the Mac (steps below).

| File | What |
|---|---|
| `web_view.gdip` | The plugin descriptor: name `WebView`, binary `web_view.xcframework`, `web_view_init` / `web_view_deinit`, `WebKit.framework` |
| `src/web_view.h`, `src/web_view.mm` | The source (Objective-C++) |
| `build.sh` | Builds `web_view.debug.xcframework` and `web_view.release.xcframework` on the Mac |
| `../../../export_presets.cfg` | The iPad preset: `plugins/WebView=true`, ships `web_city/*`, leaves out `web_city/dev/*` |
| `../../../../scripts/check_web_view_plugin.py` and `test_check_web_view_plugin.py` | The checks that run on Linux |

## How Godot uses it

```gdscript
if OS.get_name() == "iOS" and Engine.has_singleton("WebView"):
	var web: Object = Engine.get_singleton("WebView")
	if web.open(page_folder, "platform=ios"):   # an absolute path of real files
		...
# every frame, while it is open:
for text in web.poll():          # the page's messages, oldest first
	handle(JSON.parse_string(text))
web.post(JSON.stringify(message))   # Godot to page
# when the child leaves the web city:
web.close()
```

The Engine singleton is named `WebView`. (Its C++ class is `LanternWebView`, because WebKit already has an Objective-C class called `WebView`.)

| Method | What it does |
|---|---|
| `open(root_dir: String, query: String) -> bool` | Creates the web view (once) in Godot's window, above Godot's view, and loads `lantern://city/index.html?<query>` from `root_dir`. Returns false, and shows nothing, when `root_dir` is not a folder with an `index.html`, the query cannot be put in a URL, or there is no window. Calling it while open loads the page again. |
| `close()` | Hides and frees the web view (and its web process), removes the message handler, and discards unread messages. A later `open` starts fresh. |
| `post(json: String) -> bool` | Runs `window.LL&&window.LL.recv(<json>)` on the page. It never waits. It returns false and counts the message as dropped when no page is loaded yet, or when 64 calls are still unanswered. `json` must be JSON text (the output of `JSON.stringify`): it is placed in the script as it is. |
| `poll() -> PackedStringArray` | The texts the page sent with `window.webkit.messageHandlers.godot.postMessage(text)` since the last poll. At most 512 wait; the oldest is dropped (and counted) when it is full. |
| `is_open() -> bool` | True from `open` until `close`. |
| `stats() -> Dictionary` | `thermal` (0 nominal, 1 fair, 2 serious, 3 critical), `footprint_mb` (the physical footprint of **the app's process**, in MB), `dropped` (messages `post` did not deliver), `web_process_terminated` (times the web process ended). Also: `poll_dropped`, `js_errors` (calls the page answered with an error), `in_flight`, `loaded`. The counts run from the app's start. |

Things to know on the Godot side:

- **`root_dir` must be real files.** The export puts `web_city/*` inside the `.pck`, where WebKit cannot read. Godot has to copy `res://web_city` to a folder (for example below `user://`) and pass that folder's absolute path (`ProjectSettings.globalize_path`), and copy again when the app's version changes.
- **The page is "loaded"** when its load event has come or when it has sent its first message, whichever is first. So a `hello` answered to the page's `ready` is never dropped.
- **A new document starts fresh.** When a load commits (a second `open`, a reload after the web process ended, the page reloading itself), calls still on their way to the document before it are forgotten, and it is "not loaded" again until the new page speaks or finishes loading.
- **Messages of the plugin itself** arrive through `poll()` in the protocol's `log` form, with a text that begins with `native:`: a page that did not load, and the end of the web process.
- **When the web process ends** (iOS ends it when memory is short), the plugin counts it and loads the page again. The page then sends `ready` again and Godot answers with `hello`, as at the start. This also happens after a long time in the background. If the process ends a fourth time within 60 seconds, the page is not loaded again: it stays blank and a `log` error says so. Godot should then close the web city.
- **`footprint_mb` is not the page's memory.** The page lives in WebKit's own processes, which an app cannot measure. Use Xcode's memory report or Instruments for those.
- **Godot keeps drawing under the web view.** Stopping the 3D world while the web city is shown is Godot's side (`design/city-threejs.md`, section 5).

## What the web view is

- A child of Godot's window (found from Godot's view controller, else the key window), resized with it (a turn between the two landscape directions, split view, Stage Manager). The game is landscape only (`display/window/handheld/orientation=4`, sensor landscape). With the iPad held upright, iPadOS shows the landscape app letterboxed, and the web view shares that letterbox; it never goes portrait. Godot's view is not in its responder chain, so a touch on the page never reaches the game.
- White and opaque. No scrolling, bouncing or zooming; no back and forward swipes; no link previews; no pop-up windows; mobile content mode on iPad as on iPhone.
- Nothing of the page is kept on disk (a non-persistent data store).
- Safari's Web Inspector can attach in **debug** builds on iOS 16.4 and later; never in release builds. `build.sh` checks all four libraries for this (debug and release, device and simulator) through `check_inspectable.sh`.

**Files (`lantern://city/<path>` is `<root_dir>/<path>`):**

- A path with a `.` or `..` part, a control character or a backslash is refused with 403. So is a file whose real path (links resolved with `realpath`) is not below the real `root_dir`.
- A missing file, or a folder, gets 404.
- A file gets 200 with `Content-Length` and a `Content-Type` by extension: `html` text/html, `js` and `mjs` text/javascript (WebKit runs a module script only with a JavaScript type), `json` application/json, `bin` application/octet-stream, `png` image/png, `css` text/css; also `txt`, `svg`, `jpg`, `webp`, `wasm`; anything else application/octet-stream.
- Every file is read off the main thread. A request that WebKit stopped meanwhile is never answered.

**Threads:** UIKit and WebKit are used on the main thread only. The six methods may be called from any thread and never wait for the main thread or the page.

## Build on the Mac

As for `photo_library` (`docs/ios-photos.md`), with the same engine source:

```sh
# once: the engine source at the exact tag (commit ed1daf0bf001b61586d9930840f2f1394092c079)
git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git godot-4.7.2

game/ios/plugins/web_view/build.sh /path/to/godot-4.7.2
```

It asks SCons only for the generated headers, compiles `src/web_view.mm` for the device and the simulator (arm64, iOS 15.0), and fails on any error. It leaves `web_view.debug.xcframework` and `web_view.release.xcframework` beside the `.gdip`, and no plain `web_view.xcframework`. It then checks each library:

- the `ClassDB` binder of its own mode, and not the other mode's (as for `photo_library`);
- the entry points `web_view_init()` and `web_view_deinit()`;
- `setInspectable:` in the debug libraries only, device and simulator (`check_inspectable.sh`).
  - Xcode's clang sends it through a selector stub by default, so a debug object shows the undefined symbol `_objc_msgSend$setInspectable:` in `nm -C`, and no selector string. Without stubs, the selector string `setInspectable:` shows in `strings -a`. Either form counts, by its exact name.
  - A release library must show no `setInspectable` in either listing.
  - r1's check looked for the selector string only, so it failed the Mac's correct debug build (`build/dual-host/city-web/CHECKPOINT.md`, "Mac Step 1 on r1").

Then, on any machine: `python3 scripts/check_web_view_plugin.py` (it also checks that both frameworks are there and the plain one is not).

**This is the first compile of this source.** If the compiler reports an error, it is in `src/web_view.mm` or `src/web_view.h`; nothing else has to change.

## Export, Simulator, devices (the owner's steps on the Mac)

None of this was done from Linux. The latest authorization (`design/city-threejs.md`, section 6) is the bounded three-target release after validation: the iPad, the Apple TV (without this plugin) and the existing HK server. iPhone is excluded.

1. **Build both plugins' frameworks** in the copy that is exported: `web_view` as above, and `photo_library` as before (`docs/release-workflow.md`, "Candidate and packaging", step 3). The iPad preset now enables both, and a missing framework gives `Invalid plugin config`.
2. **Export** the iPad preset with the pinned Godot 4.7.2, as in `docs/release-workflow.md` step 4, and keep the log:
   ```sh
   "$GODOT" --headless --path game --export-debug "iPad" /absolute/out/ios/LanternLane.xcodeproj 2>&1 | tee /absolute/out/export.log
   grep -n "Invalid plugin config" /absolute/out/export.log     # must print nothing
   python3 scripts/ios_photo_purpose.py /absolute/out/ios
   ```
3. **Check the export:**
   - `grep -c "web_view" /absolute/out/ios/LanternLane.xcodeproj/project.pbxproj` and the same for `WebKit.framework`: both above 0;
   - the `.pck` has the page and not the dev folder: `grep -a -c "web_city/index.html" <the .pck>` above 0, `grep -a -c "web_city/dev/" <the .pck>` is 0 (`python3 scripts/check_web_view_plugin.py --export` does the same from a copy, on Linux too).
4. **Simulator** (Apple silicon; a debug build):
   ```sh
   xcodebuild -project /absolute/out/ios/LanternLane.xcodeproj -scheme LanternLane -configuration Debug \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /absolute/out/dd-sim \
     ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
   xcrun simctl install booted /absolute/out/dd-sim/Build/Products/Debug-iphonesimulator/LanternLane.app
   xcrun simctl launch --console-pty booted <bundle id>
   ```
   Enter the web city, then check:
   - the city appears, white behind it, and covers the whole window; rotate the simulator: it still does;
   - Godot receives `ready` and `first_frame`, and the page receives `hello` and `frame` (`stats()`: `loaded` true, `dropped` not growing after `ready`, `js_errors` 0);
   - Safari, Develop menu, the simulator, the page: the Web Inspector attaches. In its console:
     `fetch('lantern://city/nothing.js').then(r => r.status)` gives 404;
     `fetch('lantern://city/..%2F..%2Fetc%2Fhosts').then(r => r.status)` gives 403;
     `fetch('data/city.bin').then(r => r.headers.get('content-length'))` gives the file's size;
   - a tap on the page moves the child once (the game does not also get the touch);
   - leave the web city and enter it again, several times: it opens each time, and the app's memory does not grow each time;
   - end the simulator's web process (`pkill -f com.apple.WebKit.WebContent` on the Mac ends every simulator's): the page comes back, `web_process_terminated` is 1, and a `native:` log arrives.
   The Simulator's frame rates mean nothing.
5. **Devices:** build, sign and install the same export as in `docs/release-workflow.md` (the existing private preset and signing), on the iPad. Repeat the checks of step 4 that need no inspector, in both landscape directions (held upright, the app stays landscape, letterboxed), and then measure (`design/city-threejs.md`, section 3): frame time, memory in Xcode, `stats().thermal` after 10 minutes.
6. **A release build** once: the Web Inspector must not be able to attach.

## Checks on Linux

```sh
python3 scripts/check_web_view_plugin.py            # the descriptor, the preset, the Apple TV files, the source, build.sh
python3 scripts/test_check_web_view_plugin.py       # each fault the check guards against is caught
python3 scripts/check_web_view_plugin.py --export   # also exports the iPad .pck from a copy and reads it (slow)
```

They read the source; they do not compile it. Linux has no Objective-C++ compiler with the iOS SDK.

## Apple TV

- The plugin's source refuses to compile for tvOS, and no file below `tv/` or `scripts/tvos/` refers to it (checked).
- The Apple TV packaging reads the same `game/ios/plugins/` folder. `scripts/tvos/README.md` already says to leave `photo_library.gdip` out of the disposable TV copy, because a descriptor without its framework gives `Invalid plugin config`. **`web_view/web_view.gdip` must be left out of that copy in the same way.**
- The Apple TV export preset is private (not in Git). It must not set `plugins/WebView=true` and does not need `web_city/*`.
