## World parity fixture for the Three.js city (design/city-threejs.md §6.1): runs Godot's own city
## (world/city_world.gd, built headless) and the city's light (world/town_world.gd _city_light) and writes
## what they produce to scripts/web_city/fixtures/world.json. scripts/web_city/world.test.mjs runs the
## page's port (js/world_logic.js, js/rules.js) on the same inputs and compares.
##   scripts/godot.sh --headless --path game --script res://tests/web_city/parity_world.gd [-- --out=/abs/file.json]
##
## The city's _process is never left to the engine (set_process(false)); every frame is a direct
## _process(dt) call with a scripted clock (CityWorld.clock), so the run is deterministic. Recorded:
##   ferris      wheel transform and gondola transforms after _process at chosen clock times
##   riders      rider_transform samples;  seats: seat_transform of every INTERACTIONS key
##   carousel    Turn rotation and the horses' MultiMesh transforms after _pose_carousel, horse world and seat
##               transforms; horse_colors: the MultiMesh instance colours
##   vehicles    a scripted run of the real rules (CityRules, ticked with no child) delivered as client-form
##               states with latency, uneven frame times, a pause and a resume; the drawn pose of every vehicle
##               each frame
##   weights     _compute_weights for weather states at view times
##   looks       for weight mixes: weather_look, the applied material/node/light values and TownWorld's
##               environment and sun after _city_light
##   rain_focus  rain_focus for camera transforms;  hidden: storey visibility after apply_hidden
## The City autoload and town_world.gd are used at run time (script mode cannot preload them).
extends SceneTree

const CityWorld := preload("res://scripts/world/city_world.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const WebJson := preload("res://scripts/web/web_json.gd")

const FERRIS_TIMES := [0.0, 7.3, 33.125, 79.9, 123.4, 640.25, 1000.0 / 3.0]
const CAROUSEL_TIMES := [0.0, 1.3, 5.5, 11.0, 21.99, 22.0, 640.25, 1234.567]
## The vehicles run: uneven frame times (s), cycled.
const FRAME_DTS := [1.0 / 60.0, 1.0 / 60.0, 1.0 / 30.0, 1.0 / 60.0, 0.05, 1.0 / 120.0, 1.0 / 60.0]
const LATENCY := 0.09
const WARMUP := 30.0
const FRAMES := 420
const PAUSE_AT := 150
const RESUME_AT := 230

var cw
var city: Node
var _clock_now := 0.0              # the vehicles run's clock (a member: a lambda would capture a local by value)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../scripts/web_city/fixtures/world.json").simplify_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	city = root.get_node_or_null("City")
	if city == null or not city.has_method("decode"):
		push_error("the City autoload is missing")
		quit(1)
		return
	cw = CityWorld.new()
	cw.name = "City"
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(cw)
	cw.setup(holder)
	cw.build()
	cw.set_process(false)
	var fx := {
		"about": "Godot world parity fixture (tests/web_city/parity_world.gd); regenerate, never edit",
		"godot": Engine.get_version_info()["string"],
		"ferris": _ferris(),
		"riders": _riders(),
		"seats": _seats(),
		"carousel": _carousel(),
		"horse_colors": _horse_colors(),
		"vehicles": _vehicles(),
		"weights": _weights(),
		"looks": _looks(),
		"rain_focus": _rain_focus(),
		"hidden": _hidden(),
	}
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(WebJson.value(fx), "", false, true))
	f.close()
	print("WORLD PARITY FIXTURE OK: %d ferris, %d riders, %d seats, %d carousel, %d vehicle frames, %d weights, %d looks, %d focus, %d hidden -> %s" % [
		(fx["ferris"] as Array).size(), (fx["riders"] as Array).size(), (fx["seats"] as Dictionary).size(), (fx["carousel"] as Array).size(),
		(fx["vehicles"]["frames"] as Array).size(), (fx["weights"] as Array).size(), (fx["looks"] as Array).size(),
		(fx["rain_focus"] as Array).size(), (fx["hidden"] as Array).size(), out])
	holder.queue_free()
	quit(0)


## One frame of the city at a fresh view (the view time is the clock exactly).
func _frame_at(t: float) -> void:
	cw.clock = func() -> float: return t
	cw.set("_view_ok", false)
	cw._process(0.0)


func _ferris() -> Array:
	var out: Array = []
	for t: float in FERRIS_TIMES:
		_frame_at(t)
		var gs: Array = []
		for g: Node3D in cw.gondolas:
			gs.append(g.transform)
		out.append({"t": t, "angle": CityWorld.ferris_angle_at(t), "angle_now": cw.ferris_angle_now(), "wheel": cw.wheel.transform, "gondolas": gs,
			"static": [CityWorld.gondola_transform(0, CityWorld.ferris_angle_at(t)), CityWorld.gondola_transform(5, CityWorld.ferris_angle_at(t))]})
	return out


func _riders() -> Array:
	var out: Array = []
	for g in int(CityMap.FERRIS["gondolas"]):
		for slot in [0, 1, 2, 3]:
			var angle := 0.37 * float(g) + 0.11 * float(slot) - 1.0
			out.append({"g": g, "angle": angle, "slot": slot, "xf": CityWorld.rider_transform(g, angle, slot)})
	return out


func _seats() -> Dictionary:
	var out := {}
	for key: String in CityMap.INTERACTIONS:
		out[key] = CityWorld.seat_transform(key)
	return out


func _carousel() -> Array:
	var out: Array = []
	for t: float in CAROUSEL_TIMES:
		cw._pose_carousel(t)
		# What _pose_carousel hands to the MultiMesh (horse_xf): the headless dummy renderer keeps no
		# MultiMesh instance data to read back.
		var horses: Array = (cw.horse_xf as Array).duplicate()
		var mm: MultiMesh = cw.get("_horses").multimesh
		assert(horses.size() == mm.instance_count)
		var world: Array = []
		var seats: Array = []
		var bobs: Array = []
		for i in int(CityMap.CAROUSEL["horses"]):
			world.append(CityWorld.carousel_horse_transform(i, t))
			seats.append(CityWorld.carousel_seat_transform(i, t))
			bobs.append(CityWorld.carousel_bob(i, t))
		out.append({"t": t, "angle": CityWorld.carousel_angle_at(t), "turn": cw.carousel_turn.transform, "horses": horses, "world": world,
			"seats": seats, "bobs": bobs})
	return out


## The horses' instance colours. The headless dummy renderer keeps no MultiMesh instance data (its
## get_instance_color answers black), so this records what city_world.gd _carousel hands to
## set_instance_color: CABIN_COLORS[i % size] for each of the MultiMesh's instances, with use_colors checked.
func _horse_colors() -> Dictionary:
	var out: Array = []
	var mm: MultiMesh = cw.get("_horses").multimesh
	for i in mm.instance_count:
		out.append(CityMap.CABIN_COLORS[i % CityMap.CABIN_COLORS.size()])
	return {"use_colors": mm.use_colors, "count": mm.instance_count, "colors": out,
		"material_is_base": (cw.get("_horses") as GeometryInstance3D).material_override == load("res://scripts/art/props_city.gd").material()}


## The real rules ticked by uneven frames; a packet every 0.25 s of rules time reaches the city LATENCY
## seconds later; the clock is City.est_time's (the newest packet's time plus the time since it arrived).
func _vehicles() -> Dictionary:
	var rules = CityRules.new()
	rules.tick(WARMUP, [])
	var real := 0.0
	var pending: Array = []      # [arrive_at, client states]
	var send := 0.0
	var pkt_time := -1.0
	var pkt_at := 0.0
	var est_floor := 0.0
	var states_list: Array = []
	var frames: Array = []
	cw.set("_view_ok", false)
	cw.set("_shown", {})
	cw.set("_frozen", {})
	cw.set("_glide", 0.0)
	cw.set_states({})
	_clock_now = 0.0
	cw.clock = func() -> float: return _clock_now
	for k in FRAMES:
		var dt: float = FRAME_DTS[k % FRAME_DTS.size()]
		real += dt
		rules.tick(dt, [])
		send -= dt
		if send <= 0.0:
			send += 0.25
			pending.append([real + LATENCY, city.decode(rules.pack())])
		var got := -1
		while not pending.is_empty() and float(pending[0][0]) <= real + 1e-9:
			var s: Dictionary = pending.pop_front()[1]
			states_list.append(s)
			got = states_list.size() - 1
			cw.set_states(s)
			pkt_time = float(s["time"])
			pkt_at = real
		if pkt_time >= 0.0:
			est_floor = maxf(est_floor, pkt_time + (real - pkt_at))
		_clock_now = est_floor
		if k == PAUSE_AT:
			cw.set_paused(true)
		elif k == RESUME_AT:
			cw.set_paused(false)
		cw._process(dt)
		var drawn: Array = []
		for v: Node3D in cw.vehicles:
			drawn.append([v.position.x, v.position.y, v.position.z, v.rotation.y, v.visible])
		frames.append({"dt": dt, "clock": _clock_now, "states": got, "paused": cw.is_paused(), "drawn": drawn})
	cw.set_paused(false)
	var enc: Array = []
	for s: Dictionary in states_list:
		enc.append(s)
	return {"states": enc, "frames": frames}


func _weights() -> Array:
	var out: Array = []
	cw.set_weather_override({})
	var cases := [
		[0, -4.0, Vector3(1, 0, 0), 10.0], [1, 100.0, Vector3(1, 0, 0), 101.0], [1, 100.0, Vector3(1, 0, 0), 102.7],
		[2, 50.0, Vector3(0.2, 0.7, 0.1), 51.5], [2, 50.0, Vector3(0.2, 0.7, 0.1), 60.0], [0, 12.0, Vector3(0, 0.5, 0.5), 13.0],
		[1, 300.0, Vector3(0, 0, 1), 299.0], [7, 10.0, Vector3(1, 0, 0), 11.0], [-1, 10.0, Vector3(0, 0, 1), 12.0]]
	for c: Array in cases:
		var s: Dictionary = city.empty_state()
		s["weather"] = c[0]
		s["since"] = c[1]
		s["prev"] = c[2]
		s["weather_since"] = c[1]
		s["weather_prev"] = c[2]
		cw.set_states(s)
		cw.set("_view", c[3])
		cw.set("_view_ok", true)
		out.append({"states": {"weather": c[0], "since": c[1], "prev": c[2]}, "t": c[3], "weights": cw._compute_weights()})
	cw.set_states({})
	return out


func _looks() -> Array:
	var ts := load("res://scripts/world/town_world.gd") as GDScript
	var tw: Node3D = ts.new()
	tw.call("_build_environment")
	var env: Environment = tw.get("_env")
	var sun: DirectionalLight3D = tw.get("_sun")
	var out: Array = []
	var mixes := [{"sunny": 1.0}, {"rain": 1.0}, {"night": 1.0}, {"sunny": 0.5, "rain": 0.5}, {"rain": 0.3, "night": 0.7},
		{"sunny": 0.2, "rain": 0.3, "night": 0.5}, {"sunny": 0.999, "rain": 0.001}, {"sunny": 0.0, "rain": 0.0, "night": 0.0}]
	for m: Dictionary in mixes:
		cw.set_weather_override(m)
		var weights: Dictionary = cw.weather_weights()
		tw.call("_city_light", weights)
		var gm: StandardMaterial3D = cw.get("_ground_mat")
		var rain: GPUParticles3D = cw.get("_rain")
		var lights: Array = []
		for l: OmniLight3D in cw.get("_lights"):
			lights.append({"name": String(l.name), "energy": l.light_energy, "range": l.omni_range, "color": l.light_color, "at": l.position,
				"shadow": l.shadow_enabled, "fade": l.distance_fade_enabled, "attenuation": l.omni_attenuation})
		out.append({
			"override": m,
			"weights": weights,
			"look": cw.weather_look(),
			"applied": {
				"ground": {"albedo": gm.albedo_color, "roughness": gm.roughness, "specular": gm.metallic_specular},
				"puddle": {"alpha": (cw.get("_puddle_mat") as StandardMaterial3D).albedo_color.a, "visible": (cw.get("_puddles") as Node3D).visible},
				"glow": {"energy": (cw.get("_glow_mat") as StandardMaterial3D).emission_energy_multiplier},
				"cabin": {"energy": (cw.get("_cabin_mat") as StandardMaterial3D).emission_energy_multiplier},
				"pool": {"alpha": (cw.get("_pool_mat") as StandardMaterial3D).albedo_color.a, "visible": (cw.get("_pools") as Node3D).visible},
				"rain": {"alpha": (cw.get("_rain_mat") as StandardMaterial3D).albedo_color.a, "ratio": rain.amount_ratio, "emitting": rain.emitting,
					"visible": rain.visible},
				"lights": lights,
			},
			"town": {
				"sky": env.background_color, "ambient": env.ambient_light_color, "ambient_energy": env.ambient_light_energy,
				"adjustment": env.adjustment_enabled, "saturation": env.adjustment_saturation, "contrast": env.adjustment_contrast,
				"brightness": env.adjustment_brightness, "fog": env.fog_enabled, "sun": sun.light_color, "sun_energy": sun.light_energy,
				"sun_dir": -sun.transform.basis.z, "tonemap": env.tonemap_mode,
			},
		})
	cw.set_weather_override({})
	tw.free()
	return out


func _rain_focus() -> Array:
	var out: Array = []
	var cam := Camera3D.new()
	var poses := [[Vector3(0, 60, 70), Vector3.ZERO], [Vector3(-50, 20, -40), Vector3(-60, 0, -45)], [Vector3(10, 5, 10), Vector3(14, 6, 2)],
		[Vector3(30, 40, 10), Vector3(31, 0, 9)], [Vector3(2, 8, -3), Vector3(5, 7.8, -6)], [Vector3(-5, 30, 50), Vector3(80, 0, 90)]]
	for p: Array in poses:
		cam.transform = Transform3D.IDENTITY.looking_at(p[1] - p[0]).translated(p[0])
		var o: Vector3 = cam.transform.origin
		out.append({"origin": o, "forward": -cam.transform.basis.z, "focus": cw.rain_focus(cam)})
	cam.free()
	return out


func _hidden() -> Array:
	var cases: Array = [{}, {"office": 0.0}, {"office": 3.2, "gym": 0.0}, {"cafe": 0.0, "bakery": 0.0}, {"gym": 3.2}]
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		if String(reg["building"]) != "" and (cases.size() < 9):
			var r: Rect2 = reg["rect"]
			cases.append(CityNav.storeys_hidden(rid, r.get_center()))
	cases.append(CityNav.storeys_hidden("", Vector2(-15.0, -8.0)))
	var out: Array = []
	for h: Dictionary in cases:
		cw.apply_hidden(h)
		var vis := {}
		for bid: String in cw.levels:
			for n: Node3D in cw.levels[bid]:
				vis["Buildings/%s/%s" % [bid, n.name]] = n.visible
		out.append({"hidden": h, "visible": vis})
	cw.apply_hidden({})
	return out
