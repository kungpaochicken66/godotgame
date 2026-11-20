## tv-diag (design/tv-city-diagnostics.md): the controller counters and the benchmark's diagnostic fields.
##   scripts/godot.sh --headless --path game -s res://tests/tv_diag_tests.gd
extends SceneTree

var PadInput   # loaded once the autoloads exist (city_bench.gd refers to Session)
var CityBench
var _checks := 0
var _failures := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL ", what)


func _initialize() -> void:
	await process_frame
	PadInput = load("res://scripts/ui/pad_input.gd")
	CityBench = load("res://scripts/web/city_bench.gd")
	var pad: Node = PadInput.new()
	root.add_child(pad)
	await process_frame
	# no controller: said so, not invented
	var info: Dictionary = pad.controller_info()
	ok(info.get("connected") == false and info.has("count"), "no controller: connected false, with the count (%s)" % info)
	# counters: a tagged synthetic press and an untagged one (hardware or an untagged source)
	pad.counts = {}
	var e := InputEventJoypadButton.new()
	e.set_meta("synthetic", true)
	e.button_index = JOY_BUTTON_Y
	e.pressed = true
	pad._count(e, pad.role_of(e.button_index))
	var u := InputEventJoypadButton.new()
	u.button_index = JOY_BUTTON_Y
	u.pressed = true
	pad._count(u, pad.role_of(u.button_index))
	var got: Dictionary = pad.take_counts()
	ok(int(got.get("context", 0)) == 2, "Y counts as the context action twice (%s)" % got)
	ok(int(got.get("origin_synthetic", 0)) == 1 and int(got.get("origin_untagged", 0)) == 1, "one synthetic (tagged at its source), one untagged (origin unproven)")
	ok(pad.take_counts().is_empty(), "take_counts clears")
	# the layout's printed letters
	pad.layout = "nintendo"
	ok(pad.label_of(pad.confirm_button()) == "A" and pad.label_of(pad.back_button()) == "B", "Nintendo: A confirms and B goes back, by the printed letters")
	pad.layout = "standard"
	ok(pad.label_of(pad.confirm_button()) == "A" and pad.label_of(pad.back_button()) == "B", "standard: A confirms, B goes back")
	# the bench's statistics and fields
	var s: Dictionary = CityBench.stats_of(PackedFloat32Array([10, 10, 10, 10, 10, 10, 10, 10, 10, 50]))
	ok(s.has("p99") and is_equal_approx(float(s["p99"]), 50.0) and is_equal_approx(float(s["p50"]), 10.0), "p50 and p99 (%s)" % s)
	ok(CityBench.stats_of(PackedFloat32Array()) == {"frames": 0}, "no frames: frames 0 and nothing else")
	var b: Node = CityBench.new()
	var t: Dictionary = b.timing()
	for k in ["engine_delta", "wall", "displayed_cadence", "delta_smoothing", "max_fps", "physics_ticks_per_second", "time_scale", "vsync_mode", "screen_refresh_hz"]:
		ok(t.has(k), "timing names %s" % k)
	ok(str(t["displayed_cadence"]).begins_with("unavailable"), "the displayed cadence is said to be unavailable here")
	var un: Dictionary = b.unavailable()
	for k in ["process_cpu_pct", "process_rss_mb", "thermal", "page_processes"]:
		ok(un.has(k) and typeof(un[k]) == TYPE_STRING and str(un[k]) != "" and str(un[k]) != "0", "%s is explained, not a number (%s)" % [k, un.get(k)])
	# r2: the app's focus and pause notifications are recorded with their time (a launch that leaves the TV's Home
	# screen in front); controller hotplug is a signal the bench logs
	b._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	b._notification(NOTIFICATION_APPLICATION_PAUSED)
	ok(b._app_events.size() == 2 and b._app_events[0]["event"] == "focus_in" and b._app_events[1]["event"] == "paused" and b._app_events[1].has("ms"),
		"focus and pause notifications are recorded with their time (%s)" % [b._app_events])
	ok(pad.has_signal("controller_changed"), "the controller layer signals hotplug")
	var heard: Array = []
	pad.connect("controller_changed", func(connected: bool, info: Dictionary): heard.append([connected, info]))
	pad._on_joy(0, true)
	ok(heard.size() == 1 and heard[0][0] == true and heard[0][1].has("connected"), "a connect is signalled with the controller's info (%s)" % [heard])
	b.free()
	pad.queue_free()
	print("TV DIAG TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
