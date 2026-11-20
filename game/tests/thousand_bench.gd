## Thousand Town frame-time bench (physical Apple TV feedback on unified-r3: "profile town frame times, especially
## Night; repeatable identical day/night viewpoints, settings, warmup and measured timing/draw counters for the Mac
## baseline vs the candidate, with matching screenshots").
## The real Main (world, controller, camera rig, HUD, menus, PadInput) runs a solo town on this bench's own save
## with the capture's avatar (Avatar.PRESETS[0]); the child walks onto the town's tram stop (as
## tests/thousand_world_capture.gd places it) and the stop's "Ride to Thousand Town" button rides the real journey.
## Then, for each of the EIGHT viewpoints of tests/thousand_world_capture.gd (same child spot and facing, the same
## follow camera behind it held with _t_manual, the same Day / Dusk / Night held by the HUD's time buttons, Look for
## the overview), --reps times in order: stand, settle, WARMUP frames, then FRAMES measured frames. Per frame:
## the wall time between two frames, Godot's process and physics time, draw calls / primitives / objects of the
## whole frame (and the HUD's canvas share where the renderer reports it), the viewport's measured render CPU / GPU
## time. After the measured reps it saves one screenshot per viewpoint (rendered runs only, same file names on every
## run) and, with --systems, times each Thousand Town per-frame entry point in isolation at every viewpoint.
## The run writes one JSON (--bench-out) and prints a summary table; "THOUSAND BENCH: done" ends a good run, exit 0.
## Uses only APIs present in the frozen unified-r3 bytes (optional ones by has_method / `in`), so the same file runs
## unchanged on the r3 baseline and on a candidate: copy it into the other tree's game/tests/.
##
## Mac (rendered; the numbers that matter), the same flags for the baseline and the candidate:
##   scripts/godot.sh --path game --resolution 1920x1080 --disable-vsync -- --driver=res://tests/thousand_bench.gd \
##       --tv --reps=3 --bench-out=/abs/r4-tv-1920.json --shots=/abs/r4-tv-1920
##   scripts/godot.sh --path game --resolution 1366x1024 --disable-vsync -- --driver=res://tests/thousand_bench.gd \
##       --reps=3 --bench-out=/abs/r4-1366.json --shots=/abs/r4-1366
##   (the r3 baseline: the same lines in the r3 tree, with r3- file names). V-Sync: --disable-vsync on the command
##   line, and the bench itself sets DisplayServer.window_set_vsync_mode(VSYNC_DISABLED) and Engine.max_fps = 0;
##   the JSON records the mode in effect.
## EC2 headless (script / CPU time only; no renderer, no screenshots, render timings absent):
##   timeout 900 scripts/godot.sh --headless --fixed-fps 60 --path game -- --driver=res://tests/thousand_bench.gd \
##       --window=1920x1080 --tv --reps=3 --systems --bench-out=/abs/ec2-headless.json
##   (--fixed-fps 60: one physics step a frame, delta 1/60, no real-time waits, so a frame's wall time is its CPU work)
## EC2 software GL (draw counts and screenshots; Mesa llvmpipe frame times are not representative):
##   timeout 3000 xvfb-run -a -s "-screen 0 1960x1200x24" scripts/godot.sh --path game --resolution 1920x1080 \
##       -- --driver=res://tests/thousand_bench.gd --tv --warmup=5 --frames=5 --reps=1 --bench-out=/abs/x.json \
##       --shots=/abs/dir
## Options (after --): --warmup=N (90) --frames=N (300) --reps=N (1) --only=01,06 (viewpoint name prefixes)
##   --show=pinned|natural (pinned: the fireworks' show second runs SHOW_START + k / 60 over the k-th frame of every
##   viewpoint, so the spark load is the same on every run; natural: the game's own event clock) --systems
##   --systems-calls=N (60) --window=WxH (headless layout) --timeout=SECONDS (2400) --tv.
## JSON: {"bench", "version", "settings": {engine, os, model, cpu, display, renderer, renderer_driver, adapter, window,
##   viewport, vsync_mode, max_fps, physics_ticks, tv_mode, warmup_frames, measured_frames, reps, show, resident_budget,
##   spark_cap, ...}, "viewpoints": [{name, what, mode, pos, ry, look}],
##   "results": [{name, rep, frames, wall_ms (the time between two frames), process_ms (the frame's process span: the
##   first node's _process to the last one's), physics_ms (the physics steps' spans), monitor_time_process_ms (Godot's
##   TIME_PROCESS: the max over the last second), people_update_ms, transit_update_ms, render_cpu_ms, render_gpu_ms
##   (the viewport's measured render time), draws (the whole frame), draws_canvas (the 2D canvas, the HUD), primitives,
##   objects: each {mean, p50, p95, p99, max, min}; spikes / process_spikes (frames over 1.5 x the median: count,
##   commonest gap, first frames), clock, drawn (residents), sparks, windows_lit, memory_static_mb, video_mem_mb,
##   objects_alive}], "summary": [{name, reps, wall_p50_of_reps, wall_p95_of_reps, draws_p50_of_reps}],
##   "systems": [{name, calls, us: {entry point: {mean, p50, max} microseconds a call}}], "shots": [{name, file, draws,
##   draws_canvas}]}. Render times and canvas draws are empty headless; GPU time is 0 where the driver has no timer
##   queries. Runs on Compatibility and on Mobile / Metal (no renderer-specific call without a guard).
extends Node

const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Avatar := preload("res://scripts/core/avatar.gd")

const BENCH := "thousand_bench"
const VERSION := 1
const SAVE := "user://thousand_bench_town.json"
const SHOW_START := 30.0
## tests/thousand_world_capture.gd's eight frames, in its order: [name, what, time mode, child spot (null: the
## world's arrival()), facing ry, Look (overview)].
const VIEWPOINTS := [
	["01_arrival_day", "arrival, the forecourt corner, looking east along the z = 0 street", "day", null, PI / 2.0, false],
	["02_street_day", "the avenue pavement looking north to the towers and the hospital", "day", Vector2(-44.6, -27.0), PI, false],
	["03_bridge_day", "the canal footbridge at z = -20, on the deck, looking east", "day", Vector2(-4.0, -20.0), PI / 2.0, false],
	["04_market_night", "the night market on the west promenade, looking north", "night", Vector2(-11.0, -44.0), PI, false],
	["05_wheel_dusk", "the ferris wheel from inside the amusement park, looking south", "dusk", Vector2(66.0, 48.0), 0.0, false],
	["06_arrival_night", "arrival again at night, paired with 01", "night", null, PI / 2.0, false],
	["07_occluded_day", "against the mall's north face looking north (camera inside the dithered mall box)", "day", Vector2(30.0, 7.3), PI, false],
	["08_overview_day", "Look: the overview of the whole town", "day", null, PI / 2.0, true],
]

var main: Node
var c: Node
var hud: Control
var warmup := 90
var frames_n := 300
var reps := 1
var show_mode := "pinned"
var shots_dir := ""
var out_path := ""
var headless := false
var _vp_rid: RID
var _last_us := -1
var _rec := false
var _rec_skip := 0
var _wall := PackedFloat64Array()
var _proc := PackedFloat64Array()
var _phys := PackedFloat64Array()
var _rcpu := PackedFloat64Array()
var _rgpu := PackedFloat64Array()
var _draws := PackedFloat64Array()
var _draws_canvas := PackedFloat64Array()
var _prims := PackedFloat64Array()
var _objs := PackedFloat64Array()
var _proc_max := PackedFloat64Array()
var _people_ms := PackedFloat64Array()
var _transit_ms := PackedFloat64Array()
var _starter: Starter
var _ender: Ender


## The first node to process each frame (and each physics step): where the frame's process span starts. Its
## physics_ms sums the physics spans of the steps since the last drawn frame (ended by the Ender).
class Starter extends Node:
	var process_us := 0
	var physics_us := 0
	var physics_ms := 0.0
	var _acc := 0.0

	func _process(_dt: float) -> void:
		process_us = Time.get_ticks_usec()
		physics_ms = _acc
		_acc = 0.0

	func _physics_process(_dt: float) -> void:
		physics_us = Time.get_ticks_usec()

	func physics_end() -> void:
		_acc += (Time.get_ticks_usec() - physics_us) / 1000.0


class Ender extends Node:
	var starter: Starter

	func _physics_process(_dt: float) -> void:
		starter.physics_end()
var _pin_k := -1
var _done := false
var _limit_ms := 0


func _ready() -> void:
	process_priority = 1000000   # after the game's nodes: a frame's numbers are read once its work is done
	_starter = Starter.new()
	_starter.name = "BenchStarter"
	_starter.process_priority = -1000000
	_starter.process_physics_priority = -1000000
	add_child(_starter)
	_ender = Ender.new()
	_ender.name = "BenchEnder"
	_ender.starter = _starter
	_ender.process_physics_priority = 1000000
	add_child(_ender)
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	return str(main.args.get(k, d))


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if not _done and _limit_ms > 0 and Time.get_ticks_msec() > _limit_ms:
		_fail("the wall-clock limit (%s s, real time)" % _arg("timeout", "2400"))
		return
	var ev: Node = _events()
	if _pin_k >= 0 and ev != null and "pin_show_seconds" in ev:
		# the show second for the NEXT frame's update (the events' _process runs before this node)
		_pin_k += 1
		ev.set("pin_show_seconds", SHOW_START + float(_pin_k) / 60.0)
	if _rec:
		if _rec_skip > 0:
			_rec_skip -= 1   # the first sample's "previous frame" is the one before measuring started
		else:
			_wall.append((now - _last_us) / 1000.0)
			# the process span: from the first node's _process (the Starter) to this, the last one
			_proc.append((now - _starter.process_us) / 1000.0)
			_phys.append(_starter.physics_ms)
			_proc_max.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			var pp := _people()
			var tr := _transit()
			_people_ms.append(float(pp.get("update_ms")) if pp else 0.0)
			_transit_ms.append(float(tr.get("update_ms")) if tr else 0.0)
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			if not headless:
				_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid))
				_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
				_draws_canvas.append(RenderingServer.viewport_get_render_info(_vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	_last_us = now


# ------------------------------------------------------------- the world

func _tw() -> Node3D:
	return main.world.thousand_world if main.world.get("thousand_world") != null else null


func _events() -> Node:
	return main.world.get("thousand_events") if main and main.world else null


func _people() -> Node:
	return main.world.get("thousand_people")


func _transit() -> Node:
	return main.world.get("thousand_transit")


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func until(cond: Callable, sec := 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > sec:
			return cond.call()
	return true


func _fail(why: String) -> void:
	printerr("THOUSAND BENCH: FAIL %s" % why)
	_done = true
	get_tree().quit(1)


## The HUD's time button (Day, Dusk, Night hold 12:00, 18:40, 21:30), as the capture presses it.
func _mode(mode: String) -> bool:
	var th := get_node_or_null("/root/Thousand")
	if th == null:
		return false
	if str(th.states.get("mode", "")) != mode:
		(hud._thousand_time_btns[mode] as Button).pressed.emit()
		if not await until(func(): return str(th.states.get("mode", "")) == mode, 8.0):
			return false
	return true


## Stands the child at p facing ry with the follow camera behind it, held (tests/thousand_world_capture.gd _stand).
func _stand(p: Vector2, ry: float) -> void:
	c.pos = p
	c.ry = ry
	c._place_kid()
	var kid: Node3D = main.world.local_kid()
	if kid and kid.has_method("set_target"):
		kid.set_target(kid.position, ry, true)
	main.rig.t_yaw = ry + PI
	main.rig._t_manual = 999.0
	main.rig.snap()


func _place(vp: Array) -> bool:
	var tw := _tw()
	var arr: Transform3D = tw.arrival()
	var spot: Vector2 = vp[3] if vp[3] is Vector2 else Vector2(arr.origin.x, arr.origin.z)
	if c.thousand_looking and not vp[5]:
		c.set_thousand_look(false)
		await until(func(): return not main.rig.thousand_gliding(), 6.0)
	if not await _mode(str(vp[2])):
		return false
	_stand(spot, float(vp[4]))
	if vp[5] and not c.thousand_looking:
		c.set_thousand_look(true)
		await until(func(): return not main.rig.thousand_gliding(), 6.0)
	return true


# ------------------------------------------------------------- statistics

static func stats(a: PackedFloat64Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var q := func(p: float) -> float:
		return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]
	return {"mean": snappedf(sum / s.size(), 0.0001), "p50": snappedf(q.call(0.5), 0.0001), "p95": snappedf(q.call(0.95), 0.0001),
		"p99": snappedf(q.call(0.99), 0.0001), "max": snappedf(s[-1], 0.0001), "min": snappedf(s[0], 0.0001)}


## Frames over 1.5 x the median: how many, and the commonest gap between them (a periodic task shows as one gap).
static func spikes(a: PackedFloat64Array) -> Dictionary:
	var st := stats(a)
	if st.is_empty():
		return {}
	var lim := float(st.p50) * 1.5
	var at := PackedInt32Array()
	for i in a.size():
		if a[i] > lim:
			at.append(i)
	var gaps := {}
	for k in range(1, at.size()):
		var g := at[k] - at[k - 1]
		gaps[g] = int(gaps.get(g, 0)) + 1
	var best := -1
	for g in gaps:
		if best < 0 or int(gaps[g]) > int(gaps[best]):
			best = g
	var first: Array = []
	for k in mini(at.size(), 12):
		first.append(at[k])
	return {"over_ms": snappedf(lim, 0.001), "count": at.size(), "commonest_gap": best, "gap_count": int(gaps.get(best, 0)), "first_frames": first}


# ------------------------------------------------------------- the run

func _settings() -> Dictionary:
	var vi := Engine.get_version_info()
	var vs := get_viewport().get_visible_rect().size
	var win := get_window().size
	var vsync := -1
	if not headless:
		vsync = DisplayServer.window_get_vsync_mode()
	var tree_root := ProjectSettings.globalize_path("res://").simplify_path()
	return {
		"engine": "%s (%s)" % [str(vi.get("string", "")), str(vi.get("hash", "")).left(9)],
		"os": OS.get_name(), "model": OS.get_model_name(), "cpu": OS.get_processor_name(), "cpu_count": OS.get_processor_count(),
		"display": DisplayServer.get_name(), "headless": headless,
		"renderer": str(RenderingServer.call("get_current_rendering_method")) if RenderingServer.has_method("get_current_rendering_method") \
			else str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"renderer_driver": str(RenderingServer.call("get_current_rendering_driver_name")) if RenderingServer.has_method("get_current_rendering_driver_name") else "",
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_api": RenderingServer.get_video_adapter_api_version(),
		"window": [win.x, win.y], "viewport": [int(vs.x), int(vs.y)], "vsync_mode": vsync, "max_fps": Engine.max_fps,
		"fixed_fps_cmdline": OS.get_cmdline_args().has("--fixed-fps"),
		"physics_ticks": Engine.physics_ticks_per_second, "max_physics_steps": Engine.max_physics_steps_per_frame,
		"tv_mode": TvMode.active(), "warmup_frames": warmup, "measured_frames": frames_n, "reps": reps, "show": show_mode,
		"show_start_s": SHOW_START, "game_tree": tree_root, "args": OS.get_cmdline_user_args(),
		"resident_budget": (_people().get("max_figures") if _people() else -1),
		"spark_cap": (_events().get("spark_cap") if _events() else -1),
		"started": Time.get_datetime_string_from_system(true),
	}


func _run() -> void:
	c = main.controller
	hud = main.hud
	headless = DisplayServer.get_name() == "headless"
	warmup = maxi(0, int(_arg("warmup", "90")))
	frames_n = maxi(1, int(_arg("frames", "300")))
	reps = maxi(1, int(_arg("reps", "1")))
	show_mode = "natural" if _arg("show", "pinned") == "natural" else "pinned"
	out_path = _arg("bench-out", ProjectSettings.globalize_path("user://thousand_bench.json"))
	shots_dir = _arg("shots", "")
	var only := _arg("only", "")
	_limit_ms = Time.get_ticks_msec() + int(float(_arg("timeout", "2400")) * 1000.0)
	if main.args.has("window"):
		var wh: PackedStringArray = _arg("window", "").split("x")
		if wh.size() == 2:
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_vp_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	Engine.max_fps = 0
	if shots_dir != "" and not headless:
		DirAccess.make_dir_recursive_absolute(shots_dir)
	# the solo town on the bench's own save, with the capture's avatar
	await frames(5)
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2", SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("THOUSAND BENCH: the solo town")
	Session.start_solo(SAVE, Avatar.PRESETS[0])
	if not await until(func(): return hud.visible and not main.menus.visible and main.world.local_kid() != null, 30.0):
		_fail("the solo town did not start")
		return
	await frames(10)
	# the town's tram stop and its "Ride to Thousand Town" (the real journey: card, prepare_thousand, arrival)
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	if not await until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 10.0):
		_fail("the tram stop did not offer Thousand Town")
		return
	print("THOUSAND BENCH: riding to Thousand Town")
	hud._context_alt3_btn.pressed.emit()
	if not await until(func(): return c.space == Places.THOUSAND and c.journey_to == "" and _tw() != null, 300.0):
		_fail("did not arrive in Thousand Town")
		return
	# the same HUD on every run: no card or dialog, the arrival's messages gone
	await until(func(): return hud._overlay.get_children().filter(func(n): return not n.is_queued_for_deletion()).is_empty(), 10.0)
	var t0 := Time.get_ticks_msec()
	await until(func(): return (Time.get_ticks_msec() - t0) > 6000, 8.0)
	print("THOUSAND BENCH: arrived")
	var list: Array = []
	for vp: Array in VIEWPOINTS:
		if only == "" or Array(only.split(",")).any(func(p): return str(vp[0]).begins_with(p)):
			list.append(vp)
	var settings := _settings()
	print("THOUSAND BENCH settings: %s" % JSON.stringify(settings))
	var results: Array = []
	for rep in reps:
		for vp: Array in list:
			if not await _place(vp):
				_fail("could not set %s" % vp[0])
				return
			results.append(await _measure(vp, rep))
	var shots: Array = []
	if shots_dir != "" and not headless:
		for vp: Array in list:
			await _place(vp)
			shots.append(await _shot(vp))
	var systems: Array = []
	if main.args.has("systems"):
		for vp: Array in list:
			await _place(vp)
			await frames(30)
			systems.append(_systems(vp, maxi(1, int(_arg("systems-calls", "60")))))
	var vps: Array = []
	for vp: Array in list:
		vps.append({"name": vp[0], "what": vp[1], "mode": vp[2], "pos": ([vp[3].x, vp[3].y] if vp[3] is Vector2 else "arrival()"),
			"ry": vp[4], "look": vp[5]})
	var doc := {"bench": BENCH, "version": VERSION, "settings": settings, "viewpoints": vps, "results": results,
		"summary": _summary(list, results), "systems": systems, "shots": shots}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % out_path)
		return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	_print_table(doc)
	print("THOUSAND BENCH: done; JSON %s" % out_path)
	_done = true
	if Music.has_method("stop_for_exit"):
		await Music.stop_for_exit()
	get_tree().quit(0)


func _measure(vp: Array, rep: int) -> Dictionary:
	_pin_k = 0 if show_mode == "pinned" else -1
	var ev: Node = _events()
	if _pin_k == 0 and ev != null and "pin_show_seconds" in ev:
		ev.set("pin_show_seconds", SHOW_START)
	await frames(warmup)
	_wall.clear()   # (packed arrays are values: each is cleared by name)
	_proc.clear()
	_phys.clear()
	_rcpu.clear()
	_rgpu.clear()
	_draws.clear()
	_draws_canvas.clear()
	_prims.clear()
	_objs.clear()
	_proc_max.clear()
	_people_ms.clear()
	_transit_ms.clear()
	_rec_skip = 1
	_rec = true
	await until(func(): return _wall.size() >= frames_n, 3600.0)
	_rec = false
	var pp := _people()
	var tw := _tw()
	var vt: Dictionary = tw.view_time()
	var out := {
		"name": vp[0], "rep": rep, "frames": _wall.size(),
		"wall_ms": stats(_wall), "process_ms": stats(_proc), "physics_ms": stats(_phys),
		"monitor_time_process_ms": stats(_proc_max), "people_update_ms": stats(_people_ms), "transit_update_ms": stats(_transit_ms),
		"render_cpu_ms": stats(_rcpu), "render_gpu_ms": stats(_rgpu),
		"draws": stats(_draws), "draws_canvas": stats(_draws_canvas), "primitives": stats(_prims), "objects": stats(_objs),
		"spikes": spikes(_wall), "process_spikes": spikes(_proc),
		"clock": {"day": vt.get("day"), "minute": vt.get("minute"), "mode": vt.get("mode")},
		"drawn": int(pp.counts().get("drawn", 0)) if pp and pp.has_method("counts") else -1,
		"sparks": int(ev.status().get("sparks", 0)) if ev and ev.has_method("status") else -1,
		"windows_lit": int(tw.light.get("windows_lit", -1)),
		"memory_static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.01),
		"objects_alive": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
	}
	_pin_k = -1
	if ev != null and "pin_show_seconds" in ev:
		ev.set("pin_show_seconds", -1.0)
	print("BENCH %s rep %d: wall p50 %.2f p95 %.2f p99 %.2f max %.2f ms | process p50 %.2f p95 %.2f | draws %s | residents %d sparks %d" % [
		vp[0], rep, out.wall_ms.p50, out.wall_ms.p95, out.wall_ms.p99, out.wall_ms.max, out.process_ms.p50, out.process_ms.p95,
		str(out.draws.get("p50", "-")), out.drawn, out.sparks])
	return out


## One screenshot per viewpoint, the moving parts held at fixed moments: the fireworks' show second (SHOW_START),
## the wheel and rides (the world's animation clock), the fountain's event clock and the residents' idle clock.
## What is left is sub-frame (the town's own and the child's idle animation).
func _shot(vp: Array) -> Dictionary:
	await frames(30)
	var ev: Node = _events()
	var tw := _tw()
	var pp := _people()
	for i in 3:
		if ev != null and "pin_show_seconds" in ev:
			ev.set("pin_show_seconds", SHOW_START)
		if ev != null and "_last_abs" in ev:
			ev.set("_last_abs", -1.0)   # the fountain's event clock restarts at the held minute (offset 0)
		if "anim_offset" in tw:
			tw.anim_offset = 100.0 - Time.get_ticks_msec() / 1000.0
		if pp != null and "_idle_clock" in pp:
			pp.set("_idle_clock", 0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var canvas := RenderingServer.viewport_get_render_info(_vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var img := get_viewport().get_texture().get_image()
	var file := "%s.png" % vp[0]
	var err := img.save_png(shots_dir.path_join(file))
	if ev != null and "pin_show_seconds" in ev:
		ev.set("pin_show_seconds", -1.0)
	if "anim_offset" in tw:
		tw.anim_offset = 0.0
	print("SHOT %s: %d draw calls (canvas %d)%s" % [file, draws, canvas, "" if err == OK else " NOT SAVED"])
	return {"name": vp[0], "file": file, "saved": err == OK, "draws": draws, "draws_canvas": canvas}


## Each Thousand Town per-frame entry point called `n` times in a row at this viewpoint (after the measured reps,
## so they do not disturb the frames): microseconds a call (mean and max).
func _systems(vp: Array, n: int) -> Dictionary:
	var w: Node3D = main.world
	var tw := _tw()
	var ev: Node = _events()
	var pp := _people()
	var tr := _transit()
	var vt: Dictionary = tw.view_time()
	var day := int(vt.get("day", 1))
	var minute := float(vt.get("minute", 480.0))
	var eye: Vector3 = main.rig.camera.global_position
	var kid: Node3D = w.local_kid()
	var focus: Vector3 = kid.global_position + Vector3(0, 0.9, 0) if kid else Vector3.ZERO
	var reset := func():
		if "_thousand_frame_no" in w:
			w.set("_thousand_frame_no", -1)   # its once-a-frame guard
	var tw_frame := func():
		reset.call()
		w._thousand_frame()
	var w_process := func():
		reset.call()
		w._process(1.0 / 60.0)
	var sky: Node = tw.get("_sky")
	var jobs := [
		["world.set_time (the light: sky, uniforms, occupancy, lit count)", func(): tw.set_time(day, minute)],
		["world._process (animate, x-ray line, lights every 0.25 s)", func(): tw._process(1.0 / 60.0)],
		["world.animate (wheel, rides, balloons, fountain droplets)", func(): tw.animate(Time.get_ticks_msec() / 1000.0)],
		["world.set_view_line (x-ray uniforms)", func(): tw.set_view_line(eye, focus)],
		["world.place_lights (nearest omni lamps)", func(): tw.place_lights(eye)],
		["sky.apply (dome, sun, moon, environment)", func(): sky.apply(minute + 1440.0 * float(maxi(day - 1, 0)), w.get("_env"), w.get("_sun")) if sky else null],
		["people.set_time (residents)", func(): pp.set_time(day, minute)],
		["transit.set_time (buses, taxis, cars)", func(): tr.set_time(day, minute)],
		["events.update (fireworks, fountain)", func(): ev.update(day, minute, 1.0 / 60.0, eye)],
		["town_world._thousand_frame (people + transit + focus)", tw_frame],
		["town_world._process (town light, Thousand light and frame, town bits)", w_process],
		["rig._process (follow camera, sphere cast, occluders)", func(): main.rig._process(1.0 / 60.0)],
	]
	# outside Thousand Town's own code, for the whole picture (each only where it has a _process)
	for extra: Array in [["hud._process", hud], ["pad_input._process", main.get("pad")],
			["kid._process", w.local_kid()]]:
		var node: Node = extra[1]
		if node != null and node.has_method("_process"):
			jobs.append([extra[0], func(): node._process(1.0 / 60.0)])
	var out := {"name": vp[0], "calls": n, "us": {}}
	for job: Array in jobs:
		var key: String = job[0]
		var fn: Callable = job[1]
		var times := PackedFloat64Array()
		for i in n:
			var t0 := Time.get_ticks_usec()
			fn.call()
			times.append(float(Time.get_ticks_usec() - t0))
		var st := stats(times)
		out.us[key] = {"mean": st.mean, "p50": st.p50, "max": st.max}
	print("SYSTEMS %s: %s" % [vp[0], JSON.stringify(out.us)])
	return out


func _summary(list: Array, results: Array) -> Array:
	var out: Array = []
	for vp: Array in list:
		var wall := PackedFloat64Array()
		var proc := PackedFloat64Array()
		var p50s := PackedFloat64Array()
		var p95s := PackedFloat64Array()
		var draws := PackedFloat64Array()
		for r: Dictionary in results:
			if r.name != vp[0]:
				continue
			p50s.append(float(r.wall_ms.p50))
			p95s.append(float(r.wall_ms.p95))
			draws.append(float(r.draws.get("p50", 0.0)))
		# pooled stats need the frames: recompute from the per-rep stats is not exact, so keep both views
		out.append({"name": vp[0], "reps": p50s.size(), "wall_p50_of_reps": stats(p50s), "wall_p95_of_reps": stats(p95s),
			"draws_p50_of_reps": stats(draws)})
	return out


func _print_table(doc: Dictionary) -> void:
	print("\nviewpoint | reps | wall p50 (median of reps) | wall p95 (median of reps) | draw calls")
	for s: Dictionary in doc.summary:
		print("%s | %d | %.2f ms | %.2f ms | %s" % [s.name, s.reps, s.wall_p50_of_reps.get("p50", 0.0), s.wall_p95_of_reps.get("p50", 0.0),
			str(s.draws_p50_of_reps.get("p50", "-"))])
