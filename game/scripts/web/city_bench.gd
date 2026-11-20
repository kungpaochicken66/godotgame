## The two cities' benchmark (design/city-threejs.md §3): the same scripted path through the Godot city
## ("godot") or the Three.js city ("web"), on the device it runs on.
##   launch argument --city-bench=godot|web   [--city-bench-scale=1.0] [--city-bench-quit]
## It starts a solo game with its own save, rides to the city map, and plays PHASES: the overview, Look into
## every place of CityMap.LOOK_ORDER, back out, rain, night and sunny again. Weather goes through the shared
## city (Session.city_weather), as a child's button press would.
##   godot: every frame's engine delta is recorded here; once a second a line goes to user://city_bench.jsonl
##          with fps, p50, p95, max (ms), draw calls, primitives, static and video memory, and the WebView
##          plugin's stats() where the plugin exists (thermal state, app footprint).
##   web:   the page records its own frames (js/main.js perf samples, tagged with the phase this sends) and the
##          bridge appends them to user://web_city_perf.jsonl; this file gets the phase marks and the same
##          once-a-second process lines (without Godot's frame numbers, which say nothing about the page).
## Each run starts with a "run" line naming the kind, device model, OS, scale and the start time, and ends
## with a "summary" line per phase. These are the run's own numbers: JS-loop and engine frame times, not the
## displayed cadence, and process memory as the engine or plugin reports it. Instruments gives the rest.
## tv-diag (for the Apple TV and iPad comparison; design/tv-city-diagnostics.md): the run line also names the build,
## runtime, renderer and adapter, whether TV mode is on, and the controller; a "load" line times ride -> arrival ->
## first drawn city frame (-> the page ready, web); the second lines add p99, Godot's process and physics time, object
## counts; each phase summary adds the controller counters (pad_input.take_counts: actions by role, with how many
## were tagged synthetic by a test driver and how many were untagged). What a platform does not give is written as
## "unavailable" with the reason, never as 0: process CPU %, the whole process's memory (resident size), the thermal
## state, and the page's processes. Units are in the field names (_ms, _mb, _pct).
extends Node

const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const CityMap := preload("res://scripts/core/city_map.gd")

const LOG := "user://city_bench.jsonl"
const SAVE := "user://city_bench_town.json"
const WARMUP := 5.0

var main: Node
var kind := "godot"
var scale := 1.0
var quit_after := false
var phase := ""
var _phases: Array = []
var _deltas: PackedFloat32Array = PackedFloat32Array()
var _phase_deltas := {}
var _phase_walls := {}
var _walls: PackedFloat32Array = PackedFloat32Array()
var _last_usec := -1
var _app_events: Array = []
var _header_ms := 0
var _window := 0.0
var _running := false
var _run_id := ""


static func phases() -> Array:
	var out: Array = [{"phase": "overview", "dur": 15.0, "weather": 0, "look": ""}]
	for key in CityMap.LOOK_ORDER:
		out.append({"phase": "look_%s" % key, "dur": 4.0, "look": str(key)})
	out.append({"phase": "overview_again", "dur": 5.0, "look": "-"})
	out.append({"phase": "rain", "dur": 20.0, "weather": 1})
	out.append({"phase": "night", "dur": 20.0, "weather": 2})
	out.append({"phase": "sunny", "dur": 10.0, "weather": 0})
	return out


## The bench's launch arguments, from the user arguments or (as a device launch may pass them) the plain ones.
static func requested() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--city-bench"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func setup(m: Node, args: Dictionary) -> void:
	main = m
	kind = "web" if str(args.get("city-bench", "godot")) == "web" else "godot"
	scale = clampf(float(args.get("city-bench-scale", "1.0")), 0.01, 10.0)
	quit_after = args.has("city-bench-quit")


func _ready() -> void:
	var pad: Node = main.get("pad") if main else null
	if pad and pad.has_signal("controller_changed"):
		pad.connect("controller_changed", func(connected: bool, info: Dictionary):
			if _run_id != "":
				_line({"t": "controller_change", "connected": connected, "phase": phase, "controller": info}))
	_run.call_deferred()


## tv-diag r2: the app's focus and pause notifications (a launch that leaves the TV's Home screen in front runs the
## app in the background until the user opens it: the Mac's first r1 run). Each is logged with its time.
func _notification(what: int) -> void:
	var names := {NOTIFICATION_APPLICATION_FOCUS_IN: "focus_in", NOTIFICATION_APPLICATION_FOCUS_OUT: "focus_out",
		NOTIFICATION_APPLICATION_PAUSED: "paused", NOTIFICATION_APPLICATION_RESUMED: "resumed"}
	if names.has(what):
		_app_events.append({"event": names[what], "ms": Time.get_ticks_msec()})
		if _run_id != "":
			_line({"t": "app", "event": names[what], "phase": phase})


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _line(rec: Dictionary) -> void:
	rec["run"] = _run_id
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(LOG) else FileAccess.open(LOG, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(rec))
		f.close()


## tv-diag: what this device and build are, for the run line (no user or save data).
func identity() -> Dictionary:
	var pad: Node = main.get("pad") if main else null
	return {"build_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": Engine.get_version_info().get("string", ""), "runtime": "godot" if kind == "godot" else "web (WKWebView page; Godot runs the game)",
		"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_api": RenderingServer.get_video_adapter_api_version(), "tv_mode": TvMode.active(), "tvos": OS.has_feature("tvos"),
		"controller": pad.call("controller_info") if pad and pad.has_method("controller_info") else "unavailable (no pad layer)"}


## tv-diag: what shapes the frame numbers. "fps", "p50" ... in the second and summary lines are the ENGINE DELTA,
## which delta smoothing snaps to the refresh interval; "wall" is the monotonic main-loop interval. Neither is the
## displayed cadence (Instruments).
func timing() -> Dictionary:
	return {"engine_delta": "Engine _process delta (ms); smoothed when delta_smoothing is on",
		"wall": "monotonic Time.get_ticks_usec() between this node's process calls (ms)",
		"displayed_cadence": "unavailable here (use Instruments: Core Animation FPS, Metal System Trace)",
		"delta_smoothing": bool(ProjectSettings.get_setting("application/run/delta_smoothing", true)),
		"max_fps": Engine.max_fps, "physics_ticks_per_second": Engine.physics_ticks_per_second,
		"time_scale": Engine.time_scale, "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "low_processor_mode": OS.low_processor_usage_mode}


## tv-diag: the fields a platform does not report, said so (never 0).
func unavailable() -> Dictionary:
	var plugin := Engine.has_singleton("WebView")
	return {"process_cpu_pct": "unavailable (no per-process CPU reading in Godot; use Instruments)",
		"process_rss_mb": "see stats.footprint_mb (the app process only, WebKit excluded)" if plugin else "unavailable (no process memory reading in Godot on this platform; use Instruments)",
		"thermal": "see stats.thermal" if plugin else "unavailable (no thermal reading without the iOS WebView plugin; use Instruments)",
		"page_processes": "unavailable (WebKit runs in other processes)" if kind == "web" else "not applicable (no page)"}


func _run() -> void:
	_run_id = "%s-%d" % [kind, int(Time.get_unix_time_from_system())]
	var map := Places.CITY_WEB if kind == "web" else Places.CITY
	var head := {"t": "run", "kind": kind, "map": map, "model": OS.get_model_name(), "os": OS.get_name(),
		"os_version": OS.get_version(), "scale": scale, "unix": Time.get_unix_time_from_system(),
		"available": Places.available(map), "window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]}
	_header_ms = Time.get_ticks_msec()
	head["engine_ms_at_header"] = _header_ms
	head.merge(identity())
	head["timing"] = timing()
	head["unavailable"] = unavailable()
	_line(head)
	if not Places.available(map):
		print("CITY BENCH %s: the map %s is not available on this device" % [kind, map])
		_line({"t": "error", "text": "map not available"})
		return
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(SAVE, main.menus.avatar)
	await _wait(1.0)
	var c: Node = main.controller
	var ride_ms := Time.get_ticks_msec()
	var events_before := _app_events.size()
	var max_gap := 0
	var last_poll := ride_ms
	c.ride(map)
	var t := 0.0
	while not (c.space == map and c.journey_to == "") and t < 30.0:
		await _wait(0.2)
		t += 0.2
		var now_ms := Time.get_ticks_msec()
		max_gap = maxi(max_gap, now_ms - last_poll)
		last_poll = now_ms
	if c.space != map:
		print("CITY BENCH %s: the child did not arrive" % kind)
		_line({"t": "error", "text": "did not arrive"})
		return
	var arrived_ms := Time.get_ticks_msec()
	var first_frame: Variant = "unavailable (headless: nothing is drawn)"
	if DisplayServer.get_name() != "headless":   # the dummy renderer never emits frame_post_draw
		await RenderingServer.frame_post_draw
		first_frame = Time.get_ticks_msec() - ride_ms
	# valid only if the app stayed in the foreground: no focus or pause notification during the load (a launch that
	# leaves the TV's Home screen in front gets one when the user opens the app). The longest gap between the 200 ms
	# polls is reported, not judged: it includes the city's synchronous build (about 1.6 s headless on EC2).
	var during: Array = _app_events.slice(events_before)
	var reasons: Array = []
	if not during.is_empty():
		reasons.append("app events during the load: %s" % ", ".join(during.map(func(e): return str(e["event"]))))
	_line({"t": "load", "ride_to_arrival_ms": arrived_ms - ride_ms, "ride_to_first_frame_ms": first_frame,
		"max_poll_gap_ms": max_gap, "max_poll_gap_note": "includes the city's synchronous build; not a validity test",
		"valid_for_startup": reasons.is_empty(), "invalid_because": reasons,
		"scope": "ride-scoped: from the ride request to arrival and the first frame; the time before the ride is not in it",
		"engine_ms_at_ride": ride_ms, "engine_ms_at_run_header": _header_ms,
		"app_events_before_ride": _app_events.slice(0, events_before).map(func(e): return "%s@%dms" % [e["event"], e["ms"]]),
		"process_launch_startup": "not measured (Godot's clock starts at engine start, not at process launch; use Instruments App Launch)",
		"note": "arrival is polled every 200 ms; the first frame is the first drawn after arrival (Godot's frame, also under the web view)"})
	if kind == "web":
		# the page loads its 7 MB city first: the path starts when it has drawn (or after 60 s, noted)
		var bridge := main.get("web_city") as Node
		t = 0.0
		while bridge and not bool(bridge.get("page_ready")) and t < 60.0:
			await _wait(0.2)
			t += 0.2
		_line({"t": "page", "ready": bridge != null and bool(bridge.get("page_ready")), "waited": t, "ride_to_page_ready_ms": Time.get_ticks_msec() - ride_ms})
	_running = true
	_set_phase("warmup")
	await _wait(WARMUP * scale)
	for ph: Dictionary in phases():
		_set_phase(str(ph["phase"]))
		if ph.has("weather"):
			Session.city_weather(int(ph["weather"]))
		if ph.has("look"):
			_look(c, str(ph["look"]))
		await _wait(float(ph["dur"]) * scale)
	_set_phase("")
	_running = false
	_summaries()
	print("CITY BENCH %s DONE: %s (%s)" % [kind, ProjectSettings.globalize_path(LOG), _run_id])
	c.ride(Places.TOWN)
	if quit_after:
		await _wait(2.0)
		Music.quit_game(0)


## "" leaves Look for the overview at the start; "-" glides back out; a key glides into that place.
func _look(c: Node, key: String) -> void:
	if kind == "web":
		_send({"t": "bench", "phase": phase, "look": null if key == "" or key == "-" else key})
		return
	if key == "" or key == "-":
		c.set_city_look(false)
		c.rig.city_overview()   # dest-fix r1: the overview phases measure the whole block, as in r1-r3
	else:
		c.set_city_look(true)
		c.rig.city_look_at(key)


func _set_phase(p: String) -> void:
	var pad: Node = main.get("pad") if main else null
	if pad and pad.has_method("take_counts") and (phase != "" or p == "warmup"):
		var got: Dictionary = pad.call("take_counts")
		if phase != "":
			_line({"t": "controller", "phase": phase, "counts": got, "controller": pad.call("controller_info")})
	phase = p
	if p != "":
		_phase_deltas[p] = []   # an Array: a packed array in a Dictionary would be appended to as a copy
		_phase_walls[p] = []
		_line({"t": "phase", "phase": p, "unix": Time.get_unix_time_from_system()})
	if kind == "web":
		_send({"t": "bench", "phase": p})
	var bridge := main.get("web_city") as Node if main else null
	if bridge:
		bridge.set("bench_phase", p)
		bridge.set("bench_run", _run_id)


func _send(msg: Dictionary) -> void:
	var bridge := main.get("web_city") as Node if main else null
	if bridge and bridge.has_method("send"):
		bridge.call("send", msg)


func _process(delta: float) -> void:
	if not _running:
		_last_usec = -1
		return
	# tv-diag: two timing sources. The engine delta can be smoothed to the display's refresh interval
	# (application/run/delta_smoothing), so every frame reads exactly 1/refresh (the r3 Apple TV baseline: all 20.0 ms)
	# whatever happened. The wall interval is the monotonic time between this node's process calls: how fast the main
	# loop actually produced frames. Neither is the displayed cadence; Instruments (Core Animation, Metal) gives that.
	var now := Time.get_ticks_usec()
	var wall_ms := float(now - _last_usec) / 1000.0 if _last_usec >= 0 else -1.0
	_last_usec = now
	if kind == "godot":
		_deltas.append(delta * 1000.0)
		if wall_ms >= 0.0:
			_walls.append(wall_ms)
		if _phase_deltas.has(phase):
			(_phase_deltas[phase] as Array).append(delta * 1000.0)
			if wall_ms >= 0.0:
				(_phase_walls[phase] as Array).append(wall_ms)
	_window += delta
	if _window >= 1.0:
		_window = 0.0
		var rec := {"t": "second", "phase": phase, "unix": Time.get_unix_time_from_system(),
			"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"static_mb_scope": "Godot's static allocations only (not the process's memory)"}
		if kind == "godot":
			rec.merge(stats_of(_deltas))   # engine delta (fps, p50, p95, p99, max): may be smoothed, see "timing"
			rec["wall"] = stats_of(_walls)  # main-loop wall interval, monotonic
			_walls = PackedFloat32Array()
			rec["calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			rec["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			rec["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
			rec["video_mb_scope"] = "Godot's estimate of its own video memory (not the GPU's total footprint)"
			rec["objects_in_frame"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		# Godot's own time for the last frame's scripts and physics (ms), and its object and node counts
		rec["godot_process_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		rec["godot_physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		rec["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
		rec["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		if Engine.has_singleton("WebView"):
			rec["stats"] = Engine.get_singleton("WebView").call("stats")
		_deltas = PackedFloat32Array()
		_line(rec)


## fps, p50, p95 and max (ms) of a list of frame times in ms.
static func stats_of(ms: PackedFloat32Array) -> Dictionary:
	if ms.is_empty():
		return {"frames": 0}
	var s := ms.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	var q := func(f: float) -> float: return s[mini(s.size() - 1, int(f * s.size()))]
	return {"frames": s.size(), "fps": s.size() / maxf(total / 1000.0, 1e-6), "p50": q.call(0.5), "p95": q.call(0.95), "p99": q.call(0.99), "max": s[s.size() - 1]}


func _summaries() -> void:
	for p in _phase_deltas:
		var rec := {"t": "summary", "phase": p}
		if kind == "godot":
			rec.merge(stats_of(PackedFloat32Array(_phase_deltas[p])))
			rec["wall"] = stats_of(PackedFloat32Array(_phase_walls.get(p, [])))
		else:
			rec["note"] = "the page's frames are in web_city_perf.jsonl, tagged with this phase and run"
		_line(rec)
