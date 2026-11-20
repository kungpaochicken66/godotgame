## Camera parity fixture for the Three.js city (design/city-threejs.md §6.1): runs Godot's own camera rig
## (world/camera_rig.gd, city mode) and its maths (world/city_orbit.gd) headless through scripted sequences
## and writes what they produce to scripts/web_city/fixtures/camera.json. scripts/web_city/camera.test.mjs
## replays the same sequences on the page's port (js/orbit.js, js/camera.js CityRig) and compares.
##   scripts/godot.sh --headless --path game --script res://tests/web_city/parity_camera.gd [-- --out=/abs/file.json]
##
## The rig lives in a SubViewport of each tested size (its view_size() is that viewport's size). Its _process
## is never left to the engine: every frame is rig._process(dt) at a fixed dt, so the run is deterministic.
## Recorded per step: the camera node's global transform, the rig's city_state, Look place, glide state, and,
## where asked, Camera3D.project_ray_origin / project_ray_normal and CityOrbit.pick_place for screen points.
extends SceneTree

const O := preload("res://scripts/world/city_orbit.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")

const VIEWS := [Vector2i(1280, 720), Vector2i(2732, 2048), Vector2i(2556, 1179)]
const DT := 1.0 / 60.0
## Screen points (fractions of the view) whose rays are recorded.
const RAY_POINTS := [Vector2(0.5, 0.5), Vector2(0.1, 0.2), Vector2(0.9, 0.85), Vector2(0.3, 0.7), Vector2(0.72, 0.38)]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../scripts/web_city/fixtures/camera.json").simplify_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var fx := {
		"about": "Godot camera parity fixture (tests/web_city/parity_camera.gd); regenerate, never edit",
		"godot": Engine.get_version_info()["string"],
		"calls": _pure_calls(),
		"pick": _pick_samples(),
		"gestures": _gesture_samples(),
		"rig": [],
	}
	for v in VIEWS:
		fx["rig"].append(_rig_run(v, _rig_script(v)))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(fx, "", false, true))
	f.close()
	var frames := 0
	for r in fx["rig"]:
		frames += (r["records"] as Array).size()
	print("CAMERA PARITY FIXTURE OK: %d calls, %d pick rays, %d gestures, %d rig records -> %s" % [
		(fx["calls"] as Array).size(), (fx["pick"] as Array).size(), (fx["gestures"] as Array).size(), frames, out])
	quit(0)


# ------------------------------------------------------------------ encoding (the port's conventions)

static func enc(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [float(v.x), float(v.y)]
		TYPE_VECTOR3:
			return [v.x, v.y, v.z]
		TYPE_TRANSFORM3D:
			var t: Transform3D = v
			return {"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z], "origin": [t.origin.x, t.origin.y, t.origin.z]}
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[str(k)] = enc(v[k])
			return o
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(enc(e))
			return a
		_:
			return v


var _calls: Array = []


func _rec(fn: String, args: Array, ret: Variant) -> void:
	_calls.append({"fn": fn, "args": enc(args), "ret": enc(ret)})


# ------------------------------------------------------------------ pure CityOrbit samples

func _pure_calls() -> Array:
	_calls = []
	var aspects := [1280.0 / 720.0, 2732.0 / 2048.0, 2556.0 / 1179.0, 720.0 / 1280.0, 16.0 / 9.0]
	var pitches := [O.PITCH_MIN, O.PITCH_OVERVIEW, O.PITCH_MAX, deg_to_rad(10.0)]
	for a: float in aspects:
		for yaw: float in [0.0, 0.5, 1.3, -2.0, PI]:
			for p: float in pitches:
				_rec("max_distance", [a, yaw, p], O.max_distance(a, yaw, p))
		_rec("overview", [a], O.overview(a))
		_rec("reset", [a], O.reset(a))
		_rec("stroll", [a], O.stroll(a))   # dest-fix r1
		_rec("zoom_levels", [a, 0.4, O.PITCH_OVERVIEW], O.zoom_levels(a, 0.4, O.PITCH_OVERVIEW))
		for key: String in CityMap.LOOK_PLACES:
			_rec("look_state", [key, a], O.look_state(key, a))
	var a0: float = 1280.0 / 720.0
	var s := O.overview(a0)
	var child := Vector3(-10.0, 0.0, 5.0)
	_rec("pose", [s, a0, child], O.pose(s, a0, child))
	_rec("pose_xform", [Vector3(1, 2, 3), 0.7, 0.6, 30.0], O.pose_xform(Vector3(1, 2, 3), 0.7, 0.6, 30.0))
	# orbit, zoom, pan, steps from the overview and from close states
	var st := s
	for d: Vector2 in [Vector2(120, 0), Vector2(-40, 35), Vector2(300, -500), Vector2(0, 900), Vector2(-2000, 10)]:
		_rec("orbit", [st, d, 720.0, a0], O.orbit(st, d, 720.0, a0))
		st = O.orbit(st, d, 720.0, a0)
	for f: float in [1.1, 1.3, 2.0, 0.5, 4.0, 0.9]:
		_rec("zoom", [st, f, a0], O.zoom(st, f, a0))
		st = O.zoom(st, f, a0)
	var close := {"yaw": 0.3, "pitch": 0.6, "distance": 14.0, "out": false}
	_rec("pose", [close, a0, child], O.pose(close, a0, child))
	_rec("follow_pose", [close, child], O.follow_pose(close, child))
	_rec("orbit", [close, Vector2(55, -20), 1179.0, 2556.0 / 1179.0], O.orbit(close, Vector2(55, -20), 1179.0, 2556.0 / 1179.0))
	var pn := close
	for d2: Vector2 in [Vector2(80, 0), Vector2(0, 120), Vector2(-500, 300), Vector2(3000, 0), Vector2(0, -4000)]:
		_rec("pan", [pn, d2, 720.0, a0], O.pan(pn, d2, 720.0, a0))
		pn = O.pan(pn, d2, 720.0, a0)
	_rec("pose", [pn, a0, child], O.pose(pn, a0, child))
	var pout := s.duplicate()
	_rec("pan", [pout, Vector2(200, 100), 720.0, a0], O.pan(pout, Vector2(200, 100), 720.0, a0))
	for base: Vector3 in [Vector3(0, 1, 0), Vector3(30, 0.6, 0), Vector3(-40, 0.6, 22)]:
		for p3: Vector3 in [Vector3.ZERO, Vector3(10, 0, -5), Vector3(-50, 0, 50)]:
			_rec("apply_pan", [base, p3], O.apply_pan(base, p3))
	for sy: Dictionary in [s, close, {"yaw": O.YAW_STEP * 3.0, "pitch": 0.8, "distance": 20.0, "out": false}, {"yaw": -3.0, "pitch": 0.8, "distance": 20.0, "out": true}]:
		for dir: int in [1, -1]:
			_rec("step_yaw", [sy, dir], O.step_yaw(sy, dir))
			_rec("step_zoom", [sy, dir, a0], O.step_zoom(sy, dir, a0))
	for cs: Dictionary in [{"yaw": 4.0, "pitch": 0.1, "distance": 2.0, "out": false}, {"yaw": -7.0, "pitch": 2.0, "distance": 900.0, "out": false}, close]:
		_rec("clamp_state", [cs, a0], O.clamp_state(cs, a0))
	for n: float in [1.0, -1.0, 2.5, 0.0]:
		_rec("wheel_factor", [n], O.wheel_factor(n))
	for pc: Vector2 in [Vector2(200, 260), Vector2(260, 900), Vector2(300, 100), Vector2(0.0, 50), Vector2(120, 120)]:
		_rec("pinch_factor", [pc.x, pc.y], O.pinch_factor(pc.x, pc.y))
	# smooth and glide between poses
	var p_from := O.pose(s, a0, child)
	var p_to := O.pose(O.look_state("carousel", a0), a0, child)
	var p_wrap := O.pose({"yaw": 3.0, "pitch": 0.5, "distance": 20.0, "out": false}, a0, child)
	var p_wrap2 := O.pose({"yaw": -3.0, "pitch": 0.9, "distance": 12.0, "out": false}, a0, child)
	for u: float in [-0.5, 0.0, 0.1, 0.37, 0.5, 0.9, 1.0, 1.4]:
		_rec("glide", [p_from, p_to, u], O.glide(p_from, p_to, u))
		_rec("glide", [p_wrap, p_wrap2, u], O.glide(p_wrap, p_wrap2, u))
	for dt: float in [0.0, DT, 0.05, 0.3]:
		_rec("smooth", [p_from, p_to, dt, false], O.smooth(p_from, p_to, dt, false))
		_rec("smooth", [p_wrap, p_wrap2, dt, false], O.smooth(p_wrap, p_wrap2, dt, false))
	_rec("smooth", [p_from, p_to, DT, true], O.smooth(p_from, p_to, DT, true))
	# project and ray for a pose
	var xf: Transform3D = p_from["xform"]
	for view: Vector2 in [Vector2(1280, 720), Vector2(2732, 2048)]:
		for q: Vector3 in [Vector3(0, 0, 0), Vector3(16, 7.6, 4), Vector3(-30, 0, 25), Vector3(0, 0, 200)]:
			_rec("project", [xf, view, q], O.project(xf, view, q))
		for sp: Vector2 in [Vector2(0, 0), view * 0.5, Vector2(view.x, view.y), Vector2(view.x * 0.3, view.y * 0.8)]:
			_rec("ray", [xf, view, sp], O.ray(xf, view, sp))
	return _calls


## Rays from each test view's overview and from every Look view over a grid of screen points, plus rays that
## run along the axes (the slab tests' zero-direction branches); each with the place pick_place gives.
func _pick_samples() -> Array:
	var out: Array = []
	var child := Vector3(-26.0, 0.0, 6.0)
	for v in VIEWS:
		var view := Vector2(v)
		var a := view.x / view.y
		var poses: Array = [O.pose(O.overview(a), a, child)]
		for key: String in CityMap.LOOK_PLACES:
			poses.append(O.pose(O.look_state(key, a), a, child))
		for pi in poses.size():
			var xf: Transform3D = poses[pi]["xform"]
			var nx := 16 if pi == 0 else 5
			var ny := 10 if pi == 0 else 4
			for ix in nx:
				for iy in ny:
					var sp := Vector2((ix + 0.5) / nx * view.x, (iy + 0.5) / ny * view.y)
					var r := O.ray(xf, view, sp)
					out.append({"o": enc(r["origin"]), "d": enc(r["dir"]), "key": O.pick_place(r["origin"], r["dir"])})
	for x in range(-24, 25, 3):
		for z in range(-16, 17, 4):
			var o := Vector3(x + 0.25, 30.0, z + 0.25)
			out.append({"o": enc(o), "d": [0.0, -1.0, 0.0], "key": O.pick_place(o, Vector3(0, -1, 0))})
	for y: float in [0.5, 2.0, 5.0, 8.0, 12.0]:
		for z2 in range(-16, 17, 2):
			var o2 := Vector3(-60.0, y, z2 + 0.1)
			out.append({"o": enc(o2), "d": [1.0, 0.0, 0.0], "key": O.pick_place(o2, Vector3(1, 0, 0))})
			var o3 := Vector3(z2 + 0.1, y, 60.0)
			out.append({"o": enc(o3), "d": [0.0, 0.0, -1.0], "key": O.pick_place(o3, Vector3(0, 0, -1))})
	return out


## Scripted gestures: each starts with gesture_new and feeds moves ([x, y, t, fingers]); the gesture after each
## move and gesture_end at the given times are recorded.
func _gesture_samples() -> Array:
	var specs := [
		[["mouse", "ground", Vector2(400, 300), 1.0, 1.0, "left"], [[402, 301, 1.05, 1], [405, 303, 1.1, 1]], [1.2, 1.6]],
		[["mouse", "ground", Vector2(400, 300), 1.0, 1.0, "left"], [[405, 300, 1.05, 1], [430, 310, 1.1, 1], [480, 330, 1.2, 1]], [1.25]],
		[["touch", "ground", Vector2(100, 100), 0.0, 2.0, "left"], [[115, 100, 0.05, 1], [118, 104, 0.1, 1]], [0.2]],
		[["touch", "ground", Vector2(100, 100), 0.0, 2.0, "left"], [[125, 100, 0.05, 1], [130, 104, 0.1, 1]], [0.2]],
		[["touch", "thing", Vector2(100, 100), 0.0, 1.0, "left"], [[150, 100, 0.05, 1]], [0.1]],
		[["touch", "ui", Vector2(10, 10), 0.0, 1.0, "left"], [[12, 11, 0.05, 1]], [0.1, 0.6]],
		[["touch", "ground", Vector2(300, 300), 0.0, 1.0, "left"], [[301, 300, 0.02, 2], [305, 300, 0.05, 2], [306, 301, 0.1, 1], [340, 301, 0.15, 1]], [0.2]],
		[["mouse", "ground", Vector2(300, 300), 0.0, 0.667, "right"], [[303, 300, 0.02, 1], [312, 300, 0.05, 1], [312, 300, 0.06, 1], [200, 250, 0.1, 1]], [0.2]],
		[["mouse", "ground", Vector2(300, 300), 0.0, 1.0, "right"], [[302, 300, 0.02, 1]], [0.1]],
		[["pointer", "ground", Vector2(300, 300), 0.0, 1.0, "left"], [[700, 300, 0.2, 1]], [0.5, 0.99, 1.1]],
		[["mouse", "ground", Vector2(0, 0), 0.0, 1.0, "left"], [], [0.5, 0.5000001]],
		# just past and just inside DRAG_PX (10 px at scale 1, 6.67 px at 720 / 1080)
		[["touch", "ground", Vector2(100, 100), 0.0, 1.0, "left"], [[110.4, 100, 0.1, 1]], [0.2]],
		[["touch", "ground", Vector2(100, 100), 0.0, 1.0, "left"], [[109.6, 100, 0.1, 1], [100, 100, 0.2, 1]], [0.3]],
		[["mouse", "ground", Vector2(100, 100), 0.0, 720.0 / 1080.0, "left"], [[105.5, 103.0, 0.1, 1]], [0.2]],
		[["mouse", "ground", Vector2(100, 100), 0.0, 720.0 / 1080.0, "left"], [[106.0, 103.0, 0.1, 1]], [0.2]],
	]
	var out: Array = []
	for spec in specs:
		var na: Array = spec[0]
		var g := O.gesture_new(na[0], na[1], na[2], na[3], na[4], na[5])
		var rec := {"new": enc(na), "start": enc(g), "moves": [], "after": [], "end": []}
		for m: Array in spec[1]:
			g = O.gesture_move(g, Vector2(m[0], m[1]), m[2], m[3])
			rec["moves"].append(m)
			rec["after"].append(enc(g))
		for t: float in spec[2]:
			rec["end"].append([t, O.gesture_end(g, t)])
		out.append(rec)
	return out


# ------------------------------------------------------------------ the rig

func _rig_script(v: Vector2i) -> Array:
	var ops: Array = [
		["enter"], ["rays"],
		["frames", 5, DT],
		["orbit", 120.0, 0.0], ["frames", 10, DT],
		["orbit", -40.0, 35.0], ["orbit", 300.0, -500.0], ["frames", 30, DT],
		["wheel", 1.0], ["wheel", 1.0], ["wheel", 1.0], ["frames", 20, DT],
		["pinch", 200.0, 260.0], ["pinch", 260.0, 900.0], ["frames", 20, DT],
		["child", -10.0, 0.0, 5.0], ["frames", 30, DT], ["rays"],
		["child", -12.0, 3.4, 6.0], ["frames", 12, 0.033],
		["step_zoom", 1], ["step_zoom", 1], ["frames", 10, DT], ["step_zoom", -1], ["frames", 5, DT],
		["rotate", 1], ["rotate", -1], ["rotate", -1], ["frames", 10, DT],
		["toggle_zoom"], ["toggle_zoom"], ["toggle_zoom"], ["toggle_zoom"], ["toggle_zoom"], ["toggle_zoom"], ["frames", 20, DT],
		["wheel", -1.0], ["wheel", 2.0], ["frames", 5, DT],
	]
	for i in 10:
		ops.append(["pan", 400.0, 0.0])
	for i in 10:
		ops.append(["pan", 0.0, -600.0])
	ops += [["frames", 30, DT], ["rays"],
		["reset"], ["frames", 60, DT], ["rays"],
		["look_at", "office"], ["frames", 30, DT], ["orbit", 80.0, 20.0], ["wheel", 2.0], ["pan", 100.0, 50.0],
		["frames", 30, DT], ["rays"],
		["look_at", "ferris"], ["frames", 20, DT], ["look_at", "carousel"], ["frames", 60, DT], ["rays"],
		["look_at", "restaurant"], ["frames", 60, DT], ["step_zoom", 1], ["frames", 10, DT], ["pinch", 300.0, 200.0],
		["frames", 10, DT],
		["look_out"], ["frames", 60, DT],
		["look_at", "bakery"], ["frames", 25, DT], ["reset"], ["frames", 60, DT],
		["reduce", true], ["orbit", 50.0, 0.0], ["frames", 2, DT], ["look_at", "cafe"], ["frames", 20, DT], ["reset"],
		["frames", 20, DT], ["wheel", 1.0], ["frames", 2, DT], ["reduce", false],
		["orbit", -15.0, 4.0], ["snap"], ["rays"]]
	if v == Vector2i(1280, 720):
		# the screen turns: the rig reads the new view size from then on
		ops += [["view", 720, 1280], ["frames", 10, DT], ["look_at", "icecream"], ["frames", 60, DT], ["rays"],
			["view", 1280, 720], ["look_out"], ["frames", 60, DT]]
	return ops


func _rig_run(size: Vector2i, ops: Array) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = false
	root.add_child(vp)
	var child := Node3D.new()
	child.name = "Child"
	vp.add_child(child)
	child.global_position = Vector3(-26.0, 0.0, 6.0)
	var rig = CameraRig.new()
	vp.add_child(rig)
	rig.set_process(false)
	rig.target = child
	var records: Array = []
	for i in ops.size():
		var op: Array = ops[i]
		match str(op[0]):
			"enter":
				rig.enter_city()
			"frames":
				for f in int(op[1]):
					rig._process(float(op[2]))
					records.append(_snapshot(rig, i, f, false))
				continue
			"orbit":
				rig.city_orbit(Vector2(op[1], op[2]))
			"pan":
				rig.city_pan(Vector2(op[1], op[2]))
			"zoom":
				rig.city_zoom(float(op[1]))
			"wheel":
				rig.city_zoom(O.wheel_factor(float(op[1])))
			"pinch":
				rig.city_zoom(O.pinch_factor(float(op[1]), float(op[2])))
			"step_zoom":
				rig.city_step_zoom(int(op[1]))
			"rotate":
				rig.rotate_step(int(op[1]))
			"toggle_zoom":
				rig.toggle_zoom()
			"reset":
				rig.city_reset()
			"look_at":
				rig.city_look_at(str(op[1]))
			"look_out":
				rig.city_look_out()
			"child":
				child.global_position = Vector3(op[1], op[2], op[3])
			"snap":
				rig.snap()
			"reduce":
				rig.reduce_motion = bool(op[1])
			"view":
				vp.size = Vector2i(int(op[1]), int(op[2]))
			"rays":
				records.append(_snapshot(rig, i, -1, true))
				continue
		records.append(_snapshot(rig, i, -1, false))
	vp.queue_free()
	return {"view": [size.x, size.y], "start_child": [-26.0, 0.0, 6.0], "ops": ops, "records": records}


func _snapshot(rig: Node, op: int, frame: int, rays: bool) -> Dictionary:
	var cam: Camera3D = rig.camera
	var r := {"op": op, "frame": frame, "xf": enc(cam.global_transform), "state": enc(rig.city_state),
		"look": rig.city_look, "look_view": enc(rig.city_look_view), "gliding": rig.city_gliding(),
		"glide_t": rig._glide_t}
	if not (rig._city_cur as Dictionary).is_empty():
		var c: Dictionary = rig._city_cur
		r["cur"] = {"yaw": c["yaw"], "pitch": c["pitch"], "distance": c["distance"], "focus": enc(c["focus"])}
	if rays:
		var view: Vector2 = rig.view_size()
		var rs: Array = []
		for fp: Vector2 in RAY_POINTS:
			var sp := fp * view
			var o := cam.project_ray_origin(sp)
			var d := cam.project_ray_normal(sp)
			rs.append({"screen": enc(sp), "o": enc(o), "d": enc(d), "key": O.pick_place(o, d)})
		r["rays"] = rs
	return r
