## Headless tests for the city camera maths (world/city_orbit.gd).
##   godot --headless --path game -s res://tests/city_orbit_tests.gd
extends SceneTree

const O := preload("res://scripts/world/city_orbit.gd")
const CityMap := preload("res://scripts/core/city_map.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for t in ["test_overview", "test_orbit_zoom", "test_steps", "test_follow", "test_motion", "test_gestures", "test_look_pick", "test_look_state", "test_glide", "test_pan"]:
		call(t)
	print("CITY ORBIT TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _all_in_view(pts: Array, xf: Transform3D, view: Vector2, shrink := 1.0) -> bool:
	for p: Vector3 in pts:
		var s: Variant = O.project(xf, view, p)
		if s == null:
			return false
		var q: Vector2 = s
		if q.x < 0.0 or q.y < 0.0 or q.x > view.x * shrink or q.y > view.y * shrink:
			return false
	return true


func test_overview() -> void:
	for view in [Vector2(1920, 1080), Vector2(2388, 1668), Vector2(2532, 1170), Vector2(1080, 1920), Vector2(1024, 768)]:
		var aspect: float = view.x / view.y
		var s := O.overview(aspect)
		_ok(is_equal_approx(float(s["pitch"]), deg_to_rad(45.0)) and float(s["yaw"]) == 0.0 and bool(s["out"]), "overview looks north from 45 degrees")
		var pose := O.pose(s, aspect, Vector3(0, 0, 0))
		_ok(_all_in_view(O.overview_points(), pose["xform"], view), "the whole map fits the %s view" % str(view))
		# the map's four corners (plus MARGIN) are inside, and the fit is tight: a smaller distance would not fit
		var tighter := O.pose_xform(pose["focus"], 0.0, float(s["pitch"]), float(s["distance"]) * 0.95)
		_ok(not _all_in_view(O.overview_points(), tighter, view), "...and the fit is tight for %s" % str(view))
		var h := CityMap.HALF + Vector2(2.0, 2.0)
		var corners: Array = [Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, -h.y), Vector3(h.x, 0, h.y), Vector3(-h.x, 0, h.y)]
		_ok(_all_in_view(corners, pose["xform"], view), "HALF + 2 m corners in view for %s" % str(view))
		# at any orbit angle the limit keeps the block in view
		for yaw in [0.5, 1.0, PI * 0.25, PI * 0.5, 2.5, -1.2]:
			var s2 := s.duplicate()
			s2["yaw"] = yaw
			var s3 := O.orbit(s2, Vector2.ZERO, view.y, aspect)
			var p2 := O.pose(s3, aspect, Vector3.ZERO)
			_ok(_all_in_view(O.overview_points(), p2["xform"], view), "zoomed out at yaw %.2f still fits %s" % [yaw, str(view)])
	_ok(O.max_distance(16.0 / 9.0) > O.max_distance(4.0 / 3.0) * 0.5 and O.max_distance(1080.0 / 1920.0) > O.max_distance(16.0 / 9.0), "a portrait view is farther out")


func test_orbit_zoom() -> void:
	var aspect := 16.0 / 9.0
	var s := O.overview(aspect)
	# drag: yaw is free, pitch bounded
	var s1 := O.orbit(s, Vector2(100, 0), 1080.0, aspect)
	_ok(not is_equal_approx(float(s1["yaw"]), 0.0) and is_equal_approx(float(s1["pitch"]), float(s["pitch"])), "a horizontal drag turns the yaw only")
	var s2 := O.orbit(s, Vector2(-100, 0), 1080.0, aspect)
	_ok(is_equal_approx(float(s1["yaw"]), -float(s2["yaw"])), "drag left and right are symmetric")
	var turn := s
	for i in 40:
		turn = O.orbit(turn, Vector2(47, 0), 1080.0, aspect)
	_ok(float(turn["yaw"]) >= -PI and float(turn["yaw"]) <= PI, "yaw is kept in one turn but continuous (no snap to 45 degrees)")
	var steep := s
	for i in 100:
		steep = O.orbit(steep, Vector2(0, 80), 1080.0, aspect)
	_ok(is_equal_approx(float(steep["pitch"]), deg_to_rad(70.0)), "pitch stops at 70 degrees")
	var flat := s
	for i in 100:
		flat = O.orbit(flat, Vector2(0, -80), 1080.0, aspect)
	_ok(is_equal_approx(float(flat["pitch"]), deg_to_rad(25.0)), "pitch stops at 25 degrees")
	_ok(absf(float(O.orbit(s, Vector2(100, 0), 2160.0, aspect)["yaw"]) * 2.0 - float(s1["yaw"])) < 1e-6, "sensitivity follows the screen height")
	# zoom: bounds
	var z := s
	for i in 40:
		z = O.zoom(z, 1.3, aspect)
	_ok(is_equal_approx(float(z["distance"]), 8.0) and not bool(z["out"]), "zoom in stops at 8 m")
	var zo := z
	for i in 40:
		zo = O.zoom(zo, 1.0 / 1.3, aspect)
	_ok(bool(zo["out"]) and absf(float(zo["distance"]) - float(s["distance"])) < 0.01, "zoom out stops at the overview distance")
	_ok(float(O.zoom(s, 1.0, aspect)["distance"]) == float(s["distance"]), "factor 1 changes nothing")
	_ok(O.pinch_factor(100.0, 150.0) > 1.0 and O.pinch_factor(100.0, 60.0) < 1.0 and O.pinch_factor(100.0, 900.0) == 2.0 and O.pinch_factor(0.0, 5.0) == 1.0, "pinch factors")
	_ok(O.wheel_factor(1.0) > 1.0 and O.wheel_factor(-1.0) < 1.0 and is_equal_approx(O.wheel_factor(2.0), O.wheel_factor(1.0) * O.wheel_factor(1.0)), "wheel factors")
	# reset
	var moved := O.zoom(O.orbit(s, Vector2(300, 90), 1080.0, aspect), 3.0, aspect)
	var back := O.reset(aspect)
	_ok(back == s and float(moved["distance"]) < float(s["distance"]), "reset returns to the overview")
	var clamped := O.clamp_state({"yaw": 9.0, "pitch": 3.0, "distance": 1.0, "out": false}, aspect)
	_ok(float(clamped["pitch"]) == deg_to_rad(70.0) and float(clamped["distance"]) == 8.0 and absf(float(clamped["yaw"])) <= PI, "clamp_state")


func test_steps() -> void:
	var aspect := 16.0 / 9.0
	var s := O.overview(aspect)
	var r := O.step_yaw(s, 1)
	_ok(is_equal_approx(float(r["yaw"]), deg_to_rad(22.5)), "R turns 22.5 degrees")
	var l := O.step_yaw(O.step_yaw(s, -1), -1)
	_ok(is_equal_approx(float(l["yaw"]), deg_to_rad(-45.0)), "L twice turns -45")
	var free := s.duplicate()
	free["yaw"] = deg_to_rad(30.0)
	_ok(is_equal_approx(float(O.step_yaw(free, 1)["yaw"]), deg_to_rad(45.0)) and is_equal_approx(float(O.step_yaw(free, -1)["yaw"]), deg_to_rad(22.5)), "a free yaw goes to the next grid line")
	var full := s
	for i in 16:
		full = O.step_yaw(full, 1)
	_ok(absf(angle_difference(float(full["yaw"]), 0.0)) < 1e-6, "sixteen steps is a full turn")
	# zoom steps: levels from 8 m to the limit
	var levels := O.zoom_levels(aspect, 0.0, float(s["pitch"]))
	_ok(levels.size() == 5 and is_equal_approx(float(levels[0]), 8.0) and absf(float(levels[4]) - float(s["distance"])) < 0.01, "five zoom levels from 8 m to the overview")
	var z := s
	var seen: Array = []
	for i in 7:
		z = O.step_zoom(z, 1, aspect)
		seen.append(snappedf(float(z["distance"]), 0.01))
	_ok(float(seen[3]) == 8.0 and float(seen[6]) == 8.0 and float(seen[0]) > float(seen[1]), "a step closer each time, then 8 m stays (%s)" % str(seen))
	var back := z
	for i in 7:
		back = O.step_zoom(back, -1, aspect)
	_ok(bool(back["out"]), "steps back out reach the overview")


func test_follow() -> void:
	var aspect := 16.0 / 9.0
	var view := Vector2(1920, 1080)
	var s := O.overview(aspect)
	var child := Vector3(-22.0, 0.0, 5.0)
	var far := O.pose(s, aspect, child)
	_ok((far["focus"] as Vector3).distance_to(O.overview_focus()) < 1e-4, "zoomed out: looking at the middle of the block")
	var near_s := O.zoom(s, 100.0, aspect)
	var near := O.pose(near_s, aspect, child)
	_ok(is_equal_approx(float(near["distance"]), 8.0) and (near["focus"] as Vector3).distance_to(child + Vector3(0, O.FOCUS_LIFT, 0)) < 1e-4, "zoomed in: centred on the child at 8 m")
	var mid := O.zoom(s, 1.5, aspect)
	var mp := O.pose(mid, aspect, child)
	_ok((mp["focus"] as Vector3).distance_to(O.overview_focus()) > 0.0 and (mp["focus"] as Vector3).distance_to(child) < O.overview_focus().distance_to(child), "in between: the focus has slid toward the child")
	var fp := O.follow_pose(mid, child)
	_ok((fp["focus"] as Vector3).is_equal_approx(child + Vector3(0, O.FOCUS_LIFT, 0)) and is_equal_approx(float(fp["distance"]), float(mid["distance"])), "follow pose: centred at the chosen distance")
	# the child is on screen at every zoom, everywhere on the map
	var all_ok := true
	for cx in [-34.0, 0.0, 34.0]:
		for cz in [-26.0, 0.0, 26.0]:
			var c := Vector3(cx, 0.0, cz)
			for k in 5:
				var st := s
				for j in k:
					st = O.step_zoom(st, 1, aspect)
				var p := O.pose(st, aspect, c)
				var sp: Variant = O.project(p["xform"], view, c)
				if sp == null or (sp as Vector2).x < 0.0 or (sp as Vector2).x > view.x or (sp as Vector2).y < 0.0 or (sp as Vector2).y > view.y:
					all_ok = false
	_ok(all_ok, "the child stays on screen at every zoom level and corner of the map")
	# rays: the centre of the screen looks at the focus
	var p2 := O.pose(near_s, aspect, child)
	var rr := O.ray(p2["xform"], view, view * 0.5)
	var hit_t := (O.FOCUS_LIFT - (rr["origin"] as Vector3).y) / (rr["dir"] as Vector3).y
	var ground := (rr["origin"] as Vector3) + (rr["dir"] as Vector3) * hit_t
	_ok(Vector2(ground.x, ground.z).distance_to(Vector2(child.x, child.z)) < 1e-3, "the middle of the screen is the child")
	# dest-fix r1: the strolling view (arrival, Reset view, Look off) follows the child, large and centred, on
	# every screen shape; it is a zoom level, so the zoom buttons leave it and return to it
	for asp in [4.0 / 3.0, 16.0 / 9.0, 2208.0 / 1024.0]:
		var vw := Vector2(1024.0 * asp, 1024.0)
		var st := O.stroll(asp)
		var levels: Array = O.zoom_levels(asp, 0.0, O.PITCH_OVERVIEW)
		_ok(not bool(st["out"]) and is_equal_approx(float(st["distance"]), float(levels[O.STROLL_LEVEL])), "stroll is zoom level %d (%.1f m) at aspect %.2f" % [O.STROLL_LEVEL, float(st["distance"]), asp])
		var sp := O.pose(st, asp, child)
		_ok((sp["focus"] as Vector3).distance_to(child + Vector3(0, O.FOCUS_LIFT, 0)) < 1e-4, "stroll follows the child fully at aspect %.2f" % asp)
		var feet: Variant = O.project(sp["xform"], vw, child)
		var head: Variant = O.project(sp["xform"], vw, child + Vector3(0, 1.3, 0))
		_ok(feet != null and head != null and (feet as Vector2).distance_to(head) > 60.0, "the child stands over 60 px tall in a 1024 px high view at aspect %.2f (%.0f px)" % [asp, (feet as Vector2).distance_to(head) if feet != null and head != null else -1.0])
		var back := O.step_zoom(O.step_zoom(st, -1, asp), 1, asp)
		_ok(is_equal_approx(float(back["distance"]), float(st["distance"])), "one zoom out and in returns to the strolling view")


func test_motion() -> void:
	var aspect := 16.0 / 9.0
	var a := O.pose(O.overview(aspect), aspect, Vector3.ZERO)
	var b := O.pose(O.zoom(O.orbit(O.overview(aspect), Vector2(200, 50), 1080.0, aspect), 4.0, aspect), aspect, Vector3(-20, 0, 4))
	var snap := O.smooth(a, b, 0.016, true)
	_ok(snap["yaw"] == b["yaw"] and snap["distance"] == b["distance"] and snap["focus"] == b["focus"], "reduce motion snaps")
	var g := O.smooth(a, b, 0.016, false)
	_ok(float(g["distance"]) < float(a["distance"]) and float(g["distance"]) > float(b["distance"]), "otherwise it glides")
	var cur := a
	for i in 300:
		cur = O.smooth(cur, b, 0.016, false)
	_ok(absf(float(cur["distance"]) - float(b["distance"])) < 0.01 and absf(angle_difference(float(cur["yaw"]), float(b["yaw"]))) < 0.01, "and arrives")
	# a turn across the +-pi seam takes the short way
	var c1 := {"yaw": 3.0, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}
	var c2 := {"yaw": -3.0, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}
	var m := O.smooth(c1, c2, 0.05, false)
	_ok(absf(angle_difference(float(m["yaw"]), 3.0)) < 0.5 and absf(float(m["yaw"])) > 2.8, "yaw glides the short way round")


func test_gestures() -> void:
	var sc := 1.0
	# a tap: short and still
	var g := O.gesture_new("touch", "ground", Vector2(100, 100), 0.0)
	g = O.gesture_move(g, Vector2(103, 102), 0.05)
	_ok(g["mode"] == "pending" and O.gesture_end(g, 0.2) == "tap", "a short, small touch is a tap")
	_ok(O.gesture_end(g, 0.9) == "hold", "a long still press is a hold, not a walk")
	# a drag on empty ground orbits and never taps
	var d := O.gesture_new("touch", "ground", Vector2(100, 100), 0.0)
	d = O.gesture_move(d, Vector2(104, 100), 0.05)
	_ok(d["mode"] == "pending", "under the threshold nothing happens yet")
	d = O.gesture_move(d, Vector2(125, 100), 0.1)
	_ok(d["mode"] == "orbit" and (d["delta"] as Vector2).x == 21.0, "past 10 px: orbit with the delta")
	d = O.gesture_move(d, Vector2(101, 100), 0.2)
	_ok(d["mode"] == "orbit" and O.gesture_end(d, 0.25) == "none", "a drag that comes back is still a drag, never a tap")
	# a drag on a thing or the UI never orbits or walks
	for on in ["thing", "ui"]:
		var t := O.gesture_new("touch", on, Vector2(0, 0), 0.0)
		t = O.gesture_move(t, Vector2(80, 0), 0.1)
		_ok(t["mode"] == "none" and O.gesture_end(t, 0.2) == "none", "a drag starting on a %s does not orbit or walk" % on)
	# the mouse behaves like touch
	var m := O.gesture_new("mouse", "ground", Vector2(0, 0), 0.0)
	_ok(O.gesture_move(m, Vector2(30, 0), 0.1)["mode"] == "orbit", "a mouse drag orbits")
	# the TV pointer never orbits, and always taps
	var p := O.gesture_new("pointer", "ground", Vector2(0, 0), 0.0)
	p = O.gesture_move(p, Vector2(900, 400), 0.1)
	_ok(p["mode"] == "pending" and O.gesture_end(p, 0.2) == "tap", "the pointer never orbits; a press taps")
	# a second finger makes a pinch; what is left afterwards never taps or orbits
	var q := O.gesture_new("touch", "ground", Vector2(0, 0), 0.0)
	q = O.gesture_move(q, Vector2(1, 0), 0.05, 2)
	_ok(q["mode"] == "pinch", "two fingers pinch")
	q = O.gesture_move(q, Vector2(60, 0), 0.1, 1)
	_ok(q["mode"] == "none" and O.gesture_end(q, 0.15) == "none", "after a pinch the remaining finger does nothing")
	# device density scales the threshold
	var hi := O.gesture_new("touch", "ground", Vector2(0, 0), 0.0, 2.0)
	_ok(O.gesture_move(hi, Vector2(15, 0), 0.1)["mode"] == "pending" and O.gesture_move(hi, Vector2(25, 0), 0.1)["mode"] == "orbit", "the threshold follows the scale")
	_ok(O.gesture_end(O.gesture_move(hi, Vector2(15, 0), 0.1), 0.2) == "tap", "...and so does the tap radius")


# ------------------------------------------------------------------ Look (r2)

func _centre(lp: Dictionary) -> Vector3:
	var y: Vector2 = lp["y"]
	if lp.has("rect"):
		var r: Rect2 = lp["rect"]
		return Vector3(r.get_center().x, (y.x + y.y) * 0.5, r.get_center().y)
	if lp.get("disc", false):
		return (CityMap.FERRIS as Dictionary)["hub"]
	var f: Vector3 = lp["focus"]
	return Vector3(f.x, (y.x + y.y) * 0.5, f.z)


## An independent check: does the segment from a to b pass through the wheel's disc?
func _through_wheel(a: Vector3, b: Vector3) -> bool:
	var hub: Vector3 = (CityMap.FERRIS as Dictionary)["hub"]
	var rad := float((CityMap.FERRIS as Dictionary)["radius"]) + 0.8
	for i in 2001:
		var p := a.lerp(b, float(i) / 2000.0)
		if absf(p.z - hub.z) <= 0.8 and Vector2(p.x - hub.x, p.y - hub.y).length() <= rad:
			return true
	return false


func test_look_pick() -> void:
	var aspect := 16.0 / 9.0
	var s := O.overview(aspect)
	var hit_own := 0
	var total := 0
	for key: String in CityMap.LOOK_PLACES:
		var c := _centre(CityMap.LOOK_PLACES[key])
		for k in 8:
			var st := s.duplicate()
			st["yaw"] = O.clamp_state({"yaw": float(k) * PI / 4.0, "pitch": s["pitch"], "distance": s["distance"], "out": true}, aspect)["yaw"]
			var xf: Transform3D = O.pose(st, aspect, Vector3.ZERO)["xform"]
			var got := O.pick_place(xf.origin, (c - xf.origin).normalized())
			total += 1
			if got == key:
				hit_own += 1
			else:
				# the only legitimate misses: the tower's own centre lies under the restaurant box, and the carousel
				# can stand behind the wheel's disc
				var excused := (key == "tower" and got == "restaurant") or (key == "carousel" and got == "ferris" and _through_wheel(xf.origin, c))
				_ok(excused, "%s at yaw %d degrees from the overview picks %s" % [key, k * 45, got])
	_ok(hit_own >= total - 8 - 3, "nearly every place is picked at its own centre from every 45 degrees (%d of %d)" % [hit_own, total])
	_ok(O.pick_place(Vector3(0, 60, 40), (Vector3(-34.0, 0, -26.0) - Vector3(0, 60, 40)).normalized()) == "", "a ray at empty ground picks nothing")
	_ok(O.pick_place(Vector3(0, 30, 30), Vector3(0, -1, 0.0001).normalized()) == "", "straight down at the road picks nothing")
	# the tower and the restaurant above it
	var down := Vector3(0.0, -1.0, 0.0)
	_ok(O.pick_place(Vector3(13.0, 30.0, -8.0), down) == "restaurant", "from above the tower's box above 6.2 m is the restaurant")
	var front := (Vector3(9.5, 3.0, -3.0) - Vector3(9.5, 8.0, 20.0)).normalized()
	_ok(O.pick_place(Vector3(9.5, 8.0, 20.0), front) == "tower", "a ray into the tower's front face below 6.2 m is the tower")
	var high := (Vector3(8.5, 7.5, -3.0) - Vector3(8.5, 9.0, 20.0)).normalized()
	_ok(O.pick_place(Vector3(8.5, 9.0, 20.0), high) == "restaurant", "...and above 6.2 m the restaurant")
	# the wheel is a disc: through its plane near the rim, but not a ray beside it
	var hub: Vector3 = (CityMap.FERRIS as Dictionary)["hub"]
	_ok(O.pick_place(hub + Vector3(0, 0, 30), Vector3(0, 0, -1)) == "ferris", "a ray along the wheel's axis hits the disc")
	_ok(O.pick_place(hub + Vector3(6.5, 0, 30), Vector3(0, 0, -1)) == "ferris", "6.5 m from the hub is still the wheel (radius + 0.8)")
	_ok(O.pick_place(hub + Vector3(7.0, 0, 30), Vector3(0, 0, -1)) == "", "7 m out is beside the wheel")
	var edge := hub + Vector3(0, 0, -0.5)
	_ok(O.pick_place(edge + Vector3(0, 40, 0), Vector3(0, -1, 0)) == "ferris", "from above: the disc is thick 1.6 m, so a ray down its plane hits it")
	_ok(O.pick_place(hub + Vector3(0, 40, -2.0), Vector3(0, -1, 0)) == "", "a ray down 2 m behind the plane misses it")
	# the carousel cylinder
	var car := (CityMap.LOOK_PLACES["carousel"] as Dictionary)
	var cf: Vector3 = car["focus"]
	_ok(O.pick_place(Vector3(cf.x, 30.0, cf.z), down) == "carousel", "down onto the carousel")
	_ok(O.pick_place(Vector3(cf.x + float(car["circle"]) - 0.1, 30.0, cf.z), down) == "carousel", "inside its radius")
	_ok(O.pick_place(Vector3(cf.x + float(car["circle"]) + 0.1, 30.0, cf.z), down) == "", "just outside its radius")
	_ok(O.pick_place(Vector3(cf.x + 20.0, 5.0, cf.z), Vector3(-1, 0, 0)) == "", "sideways at 5 m passes above the cylinder's y range")
	_ok(O.pick_place(Vector3(cf.x + 20.0, 2.0, cf.z), Vector3(-1, 0, 0)) == "carousel", "sideways at 2 m hits it")
	# every box place is hit through each of its faces
	for key: String in CityMap.LOOK_PLACES:
		var lp: Dictionary = CityMap.LOOK_PLACES[key]
		if not lp.has("rect"):
			continue
		var r: Rect2 = lp["rect"]
		var y: Vector2 = lp["y"]
		var ym := (y.x + y.y) * 0.5
		var cx := r.get_center().x
		var cz := r.get_center().y
		var faces := {"+z": [Vector3(cx, ym, r.end.y + 12.0), Vector3(0, 0, -1)], "-z": [Vector3(cx, ym, r.position.y - 12.0), Vector3(0, 0, 1)],
			"+x": [Vector3(r.end.x + 12.0, ym, cz), Vector3(-1, 0, 0)], "-x": [Vector3(r.position.x - 12.0, ym, cz), Vector3(1, 0, 0)]}
		for f: String in faces:
			var got2 := O.pick_place(faces[f][0], faces[f][1])
			# a neighbouring place may stand in front (the gym beside the cafe, the shops in a row)
			var neighbour := got2 != "" and got2 != key
			_ok(got2 == key or neighbour, "%s: a ray in through its %s face picks a place (%s)" % [key, f, got2])


func test_look_state() -> void:
	for aspect in [16.0 / 9.0, 4.0 / 3.0, 9.0 / 16.0]:
		for key: String in CityMap.LOOK_PLACES:
			var lp: Dictionary = CityMap.LOOK_PLACES[key]
			var st := O.look_state(key, aspect)
			_ok(is_equal_approx(float(st["pitch"]), deg_to_rad(float(lp["pitch"]))) and is_equal_approx(float(st["yaw"]), float(lp["yaw"])) and (st["focus"] as Vector3) == (lp["focus"] as Vector3) and st["out"] == false, "%s: look_state carries the map's view" % key)
			_ok(float(st["distance"]) >= float(lp["distance"]) - 1e-6 and float(st["distance"]) <= O.max_distance(aspect, float(st["yaw"]), float(st["pitch"])) + 1e-6, "%s: distance within limits (%.1f at aspect %.2f)" % [key, st["distance"], aspect])
	_ok(float(O.look_state("office", 16.0 / 9.0)["distance"]) == float((CityMap.LOOK_PLACES["office"] as Dictionary)["distance"]), "at 16:9 the map's distance as is")
	# the look pose is centred on its own focus, whoever the child is
	var st2 := O.look_state("cafe", 16.0 / 9.0)
	var pa := O.pose(st2, 16.0 / 9.0, Vector3(-30, 0, 20))
	var pb := O.pose(st2, 16.0 / 9.0, Vector3(30, 0, -20))
	_ok((pa["focus"] as Vector3) == (st2["focus"] as Vector3) and (pb["focus"] as Vector3) == (st2["focus"] as Vector3), "pose() of a Look state ignores where the child is")
	# and the place is on screen
	var view := Vector2(1920, 1080)
	for key: String in CityMap.LOOK_PLACES:
		var st3 := O.look_state(key, 16.0 / 9.0)
		var sp: Variant = O.project(O.pose(st3, 16.0 / 9.0, Vector3.ZERO)["xform"], view, st3["focus"])
		_ok(sp != null and (sp as Vector2).distance_to(view * 0.5) < 2.0, "%s: its focus is the middle of the screen" % key)
	# every key of LOOK_ORDER is a place
	for key: String in CityMap.LOOK_ORDER:
		_ok(CityMap.LOOK_PLACES.has(key), "LOOK_ORDER names a real place: %s" % key)


func test_glide() -> void:
	var aspect := 16.0 / 9.0
	var a := O.pose(O.overview(aspect), aspect, Vector3.ZERO)
	var b := O.pose(O.look_state("cafe", aspect), aspect, Vector3.ZERO)
	var g0 := O.glide(a, b, 0.0)
	var g1 := O.glide(a, b, 1.0)
	_ok(g0["yaw"] == a["yaw"] and g0["pitch"] == a["pitch"] and g0["distance"] == a["distance"] and g0["focus"] == a["focus"], "glide at 0 is the first pose")
	_ok(g1["yaw"] == b["yaw"] and g1["pitch"] == b["pitch"] and g1["distance"] == b["distance"] and g1["focus"] == b["focus"], "glide at 1 is the second pose")
	_ok(g0.has("xform") and g1.has("xform") and O.glide(a, b, 0.5).has("xform"), "every glide carries an xform")
	_ok(O.glide(a, b, -3.0)["distance"] == a["distance"] and O.glide(a, b, 7.0)["distance"] == b["distance"], "u is clamped to 0..1")
	var last := float(a["distance"])
	var mono := true
	var last_focus := (a["focus"] as Vector3).distance_to(b["focus"])
	var focus_mono := true
	for i in range(1, 101):
		var g := O.glide(a, b, float(i) / 100.0)
		if float(g["distance"]) > last + 1e-9:
			mono = false
		last = float(g["distance"])
		var fd := (g["focus"] as Vector3).distance_to(b["focus"])
		if fd > last_focus + 1e-9:
			focus_mono = false
		last_focus = fd
	_ok(mono and float(a["distance"]) > float(b["distance"]), "distance goes down monotonically toward a closer view")
	_ok(focus_mono, "the focus approaches steadily")
	var back := true
	last = float(b["distance"])
	for i in range(1, 101):
		var g := O.glide(b, a, float(i) / 100.0)
		if float(g["distance"]) < last - 1e-9:
			back = false
		last = float(g["distance"])
	_ok(back, "and out again monotonically")
	# eased: slow at the ends, fastest in the middle
	var d1 := absf(float(O.glide(a, b, 0.1)["distance"]) - float(a["distance"]))
	var d2 := absf(float(O.glide(a, b, 0.5)["distance"]) - float(O.glide(a, b, 0.4)["distance"]))
	_ok(d1 < d2, "smoothstep: the first tenth moves less than the 0.4 to 0.5 step")
	_ok(is_equal_approx(float(O.glide(a, b, 0.5)["distance"]), (float(a["distance"]) + float(b["distance"])) * 0.5), "halfway is halfway (smoothstep(0.5) = 0.5)")
	# the shortest way round in yaw
	var p1 := {"yaw": 3.0, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}
	var p2 := {"yaw": -3.0, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}
	var m := O.glide(p1, p2, 0.5)
	_ok(absf(absf(float(m["yaw"])) - PI) < 0.01, "3.0 to -3.0 goes through pi, not through 0 (%.3f)" % float(m["yaw"]))
	var q1 := O.glide(p1, p2, 0.25)
	_ok(float(q1["yaw"]) > 3.0 or float(q1["yaw"]) < -3.0, "and stays on that side (%.3f)" % float(q1["yaw"]))
	var p3 := {"yaw": -2.9, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}
	var m2 := O.glide(p3, {"yaw": 2.9, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}, 0.5)
	_ok(absf(absf(float(m2["yaw"])) - PI) < 0.01, "-2.9 to 2.9 also goes through pi")
	var m3 := O.glide({"yaw": 0.1, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}, {"yaw": 1.1, "pitch": 0.8, "distance": 20.0, "focus": Vector3.ZERO}, 0.5)
	_ok(absf(float(m3["yaw"]) - 0.6) < 1e-6, "a short turn is a plain interpolation")


# ------------------------------------------------------------------ pan (r3)

func test_pan() -> void:
	var aspect := 16.0 / 9.0
	var view := Vector2(1920, 1080)
	var s := O.overview(aspect)
	# zoom in so the focus is not pinned by the bounds, then pan at several yaws: the ground follows the cursor
	var base := O.zoom(s, 2.0, aspect)
	var child := Vector3(0.0, 0.0, 0.0)
	for yaw in [0.0, 0.7, -1.3, PI * 0.5, 2.6, -PI * 0.75]:
		var st := base.duplicate()
		st["yaw"] = yaw
		for drag in [Vector2(80, 0), Vector2(-60, 0), Vector2(0, 50), Vector2(0, -70), Vector2(40, 30)]:
			var p0 := O.pose(st, aspect, child)
			var st2 := O.pan(st, drag, view.y, aspect)
			var p1 := O.pose(st2, aspect, child)
			# a ground point at the middle of the screen before: where is it after?
			var ground := p0["focus"] as Vector3
			ground.y = 0.0
			var a: Variant = O.project(p0["xform"], view, ground)
			var b: Variant = O.project(p1["xform"], view, ground)
			var moved := (b as Vector2) - (a as Vector2)
			_ok(moved.dot(drag) > 0.0 and absf(moved.x - drag.x) < 0.12 * drag.length() + 2.0 and absf(moved.y - drag.y) < 0.12 * drag.length() + 2.0, "yaw %.2f drag %s: the ground moved %s on screen" % [yaw, str(drag), str(moved)])
	# pan is a ground offset
	var pp := O.pan(base, Vector2(100, 40), view.y, aspect)
	_ok((pp["pan"] as Vector3).y == 0.0 and (pp["pan"] as Vector3) != Vector3.ZERO, "pan is a ground offset (y 0)")
	_ok(not s.has("pan") and not O.look_state("cafe", aspect).has("pan") and not O.reset(aspect).has("pan"), "overview, look_state and reset carry no pan")
	_ok(not O.reset(aspect).has("pan"), "reset clears it")
	# accumulates, and the other operations keep it
	var p2 := O.pan(pp, Vector2(100, 0), view.y, aspect)
	_ok(absf((p2["pan"] as Vector3).x) > absf((pp["pan"] as Vector3).x), "drags add up")
	_ok(O.orbit(p2, Vector2(30, 0), view.y, aspect)["pan"] == p2["pan"] and O.zoom(p2, 1.2, aspect)["pan"] == p2["pan"] and O.step_yaw(p2, 1)["pan"] == p2["pan"], "orbit, zoom and steps keep the pan")
	# bounds: dragging for ever stops at the lot grown by 4 m
	var bounds := O.pan_bounds()
	_ok(bounds == (CityMap.LOT as Rect2).grow(4.0), "the bounds are the lot grown by 4 m")
	for dir in [Vector2(500, 0), Vector2(-500, 0), Vector2(0, 500), Vector2(0, -500), Vector2(300, 300)]:
		for yaw2 in [0.0, 1.0, -2.0]:
			var st3 := base.duplicate()
			st3["yaw"] = yaw2
			for i in 60:
				st3 = O.pan(st3, dir, view.y, aspect)
			var f := (O.pose(st3, aspect, child)["focus"] as Vector3)
			_ok(f.x >= bounds.position.x - 1e-6 and f.x <= bounds.end.x + 1e-6 and f.z >= bounds.position.y - 1e-6 and f.z <= bounds.end.y + 1e-6, "the focus stays within the bounds (%s)" % str(f))
	# it also holds for a Look state and for the overview
	var lk := O.look_state("ferris", aspect)
	var far := lk
	for i in 80:
		far = O.pan(far, Vector2(400, 0), view.y, aspect)
	var lf := (O.pose(far, aspect, child)["focus"] as Vector3)
	_ok(lf.x >= bounds.position.x - 1e-6 and lf.x <= bounds.end.x + 1e-6, "a Look view panned far is bounded too")
	_ok((O.pose(O.pan(lk, Vector2(50, 0), view.y, aspect), aspect, child)["focus"] as Vector3) != (lk["focus"] as Vector3), "a Look state's focus plus the pan")
	var ov := O.overview(aspect)
	var ovp := O.pan(ov, Vector2(100, 0), view.y, aspect)
	_ok((O.pose(ovp, aspect, child)["focus"] as Vector3) != (O.pose(ov, aspect, child)["focus"] as Vector3), "the overview pans too")
	# a child outside the bounds is not pulled back by a zero pan
	var outer := Vector3(32.0, 0.0, 0.0)
	var near := O.zoom(base, 100.0, aspect)
	_ok(absf((O.pose(near, aspect, outer)["focus"] as Vector3).x - 32.0) < 1e-6, "following a child on the outer pavement still works")
	# gestures: a right drag pans and is never a tap
	var g := O.gesture_new("mouse", "ground", Vector2(100, 100), 0.0, 1.0, "right")
	_ok(g["mode"] == "pending", "right press: pending")
	_ok(O.gesture_end(g, 0.1) == "none", "a right press without moving is not a tap")
	g = O.gesture_move(g, Vector2(103, 100), 0.05)
	_ok(g["mode"] == "pending", "under the threshold nothing yet")
	g = O.gesture_move(g, Vector2(130, 100), 0.1)
	_ok(g["mode"] == "pan" and (g["delta"] as Vector2).x == 27.0, "a right drag pans with its delta")
	g = O.gesture_move(g, Vector2(101, 101), 0.2)
	_ok(g["mode"] == "pan" and O.gesture_end(g, 0.25) == "none", "and coming back is still not a tap")
	for on in ["thing", "ui"]:
		var t := O.gesture_new("mouse", on, Vector2(0, 0), 0.0, 1.0, "right")
		t = O.gesture_move(t, Vector2(60, 0), 0.1)
		_ok(t["mode"] == "pan", "a right drag on a %s pans as well" % on)
	var l := O.gesture_new("mouse", "ground", Vector2(0, 0), 0.0)
	l = O.gesture_move(l, Vector2(60, 0), 0.1)
	_ok(l["mode"] == "orbit" and O.gesture_end(O.gesture_new("mouse", "ground", Vector2(0, 0), 0.0), 0.1) == "tap", "the left button still orbits and taps")
