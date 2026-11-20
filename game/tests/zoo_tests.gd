## Headless tests for the zoo (design/zoo-and-world-journeys.md, Phase 1A onward): the camera's
## real footprint, habitat sizes against one gameplay screen, the layout rules H1 and H3, and
## the rig's pure helpers. Nothing here renders; how anything looks is the Mac's gate.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_tests.gd
extends SceneTree

const CameraRig := preload("res://scripts/world/camera_rig.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooRig := preload("res://scripts/art/zoo_rig.gd")
const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")
const ZooAnimal := preload("res://scripts/art/zoo_animal.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")

## The four layouts the tours use: logical height 1024, widths from the project's stretch.
const LAYOUTS := {"ipad": Vector2(1366, 1024), "ipad_air": Vector2(1475, 1024), "tv": Vector2(1820, 1024), "iphone": Vector2(2208, 1024)}
const TOP_BAR := 104.0
const FOCUS_UP := 0.6   # CameraRig.goal_pose: the focus is 0.6 m above the child outdoors

var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	for t in ["test_camera_footprint", "test_hill_larger_than_screen", "test_zoo_map_data", "test_layout_h3",
			"test_show_spots_visible", "test_two_bone_reach", "test_pendulum_and_arc",
			"test_zoo_routes", "test_monkey_repertoire", "test_monkey_reduce_motion", "test_monkey_seeds",
			"test_lion_answers", "test_lion_pace", "test_stations", "test_monkey_copycat", "test_pack_roundtrip",
			"test_roster", "test_all_stay_home", "test_tiger", "test_savanna", "test_splash_bay", "test_station_answers",
			"test_treats_full", "test_toys", "test_keep_clear", "test_found_events",
			"test_models", "test_readability_in_place", "test_tram_stop_in_first_view", "test_lions_den_in_rain", "test_town_literal_audit", "test_bell_always_rings"]:
		_current = t
		call(t)
	print("\nZOO TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


# ---------------------------------------------------------------- camera helpers

## Where the screen point lands on the ground plane y = 0, or null.
static func ground_hit(xf: Transform3D, view: Vector2, screen: Vector2) -> Variant:
	var half := tan(deg_to_rad(CameraRig.FOV) * 0.5)
	var dir_cam := Vector3((screen.x - view.x * 0.5) / (view.y * 0.5) * half, (view.y * 0.5 - screen.y) / (view.y * 0.5) * half, -1.0)
	var dir := (xf.basis * dir_cam).normalized()
	if dir.y >= -0.0001:
		return null
	var t := -xf.origin.y / dir.y
	return xf.origin + dir * t


static func pose(child: Vector2, yaw: float, zoom: int) -> Transform3D:
	return CameraRig.pose_xform(Vector3(child.x, FOCUS_UP, child.y), yaw, CameraRig.ZOOMS[zoom])


## The visible ground for a child at the origin, yaw 0: depth (near to far along -z) and widths.
static func footprint(view: Vector2, zoom: int) -> Dictionary:
	var xf := pose(Vector2.ZERO, 0.0, zoom)
	var near: Vector3 = ground_hit(xf, view, Vector2(view.x * 0.5, view.y))
	var far: Vector3 = ground_hit(xf, view, Vector2(view.x * 0.5, 0.0))
	var near_l: Vector3 = ground_hit(xf, view, Vector2(0.0, view.y))
	var far_l: Vector3 = ground_hit(xf, view, Vector2(0.0, 0.0))
	# width at the child's depth: the horizontal span of the screen line through the child
	var child_scr: Vector2 = CameraRig.project(xf, view, Vector3.ZERO)
	var left: Vector3 = ground_hit(xf, view, Vector2(0.0, child_scr.y))
	return {"depth": near.z - far.z, "toward": near.z, "beyond": -far.z,
			"near_w": 2.0 * absf(near_l.x), "far_w": 2.0 * absf(far_l.x), "child_w": 2.0 * absf(left.x)}


# ---------------------------------------------------------------- tests

func test_camera_footprint() -> void:
	# Pins the planner's computed table (section 5.1) to the real camera code.
	var f: Dictionary = footprint(LAYOUTS["ipad"], 0)
	print("footprint near zoom: depth %.2f (toward %.2f, beyond %.2f) widths near/child/far ipad %.1f/%.1f/%.1f" % [f["depth"], f["toward"], f["beyond"], f["near_w"], f["child_w"], f["far_w"]])
	ok(absf(f["depth"] - 15.8) < 0.3, "visible depth at the near zoom is about 15.8 m (%.2f)" % f["depth"])
	ok(absf(f["toward"] - 3.6) < 0.3 and absf(f["beyond"] - 12.2) < 0.3, "3.6 m toward the camera, 12.2 m beyond the child")
	for k in LAYOUTS:
		var g: Dictionary = footprint(LAYOUTS[k], 0)
		print("  %s: width at the child %.1f m, near %.1f m, far %.1f m" % [k, g["child_w"], g["near_w"], g["far_w"]])
		ok(absf(g["depth"] - f["depth"]) < 0.01, "%s: the depth does not depend on the device" % k)
	var tv: Dictionary = footprint(LAYOUTS["tv"], 0)
	ok(absf(tv["child_w"] - 13.5) < 0.4, "TV width at the child is about 13.5 m (%.1f)" % tv["child_w"])
	var wide: Dictionary = footprint(LAYOUTS["ipad"], 1)
	ok(absf(wide["depth"] - 24.1) < 0.4, "wide zoom depth is about 24.1 m (%.2f)" % wide["depth"])


func test_hill_larger_than_screen() -> void:
	# Section 5.4: a habitat is larger than one screen when it cannot lie inside the visible
	# trapezoid at the default zoom on any layout at any quarter turn: both sides longer than the
	# visible depth, and the long side longer than the widest layout's mean width.
	var depth: float = footprint(LAYOUTS["ipad"], 0)["depth"]
	var widest: Dictionary = footprint(LAYOUTS["iphone"], 0)
	var mean_w: float = (widest["near_w"] + widest["far_w"]) * 0.5
	for hill in ZooMap.HABITATS:
		var r: Rect2 = ZooMap.HABITATS[hill]
		var short_side := minf(r.size.x, r.size.y)
		var long_side := maxf(r.size.x, r.size.y)
		ok(short_side > depth, "%s: both sides (%.1f) exceed the visible depth %.1f" % [hill, short_side, depth])
		ok(long_side > mean_w, "%s: the long side (%.1f) exceeds the iPhone's mean width %.1f" % [hill, long_side, mean_w])
	ok(ZooMap.HABITATS["lion_hill"].size == Vector2(24, 18), "Lion Hill is 24 x 18 m")


func test_zoo_map_data() -> void:
	for k in ZooMap.AREAS:
		var a: Dictionary = ZooMap.AREAS[k]
		var r: Rect2 = a["rect"]
		ok(absf(r.position.x) <= ZooMap.HALF.x and absf(r.end.x) <= ZooMap.HALF.x and absf(r.position.y) <= ZooMap.HALF.y and absf(r.end.y) <= ZooMap.HALF.y, "%s lies on the map" % k)
		if a["hill"] != "":
			ok(ZooMap.HABITATS[a["hill"]].encloses(r), "%s lies inside %s" % [k, a["hill"]])
	for k in ZooMap.SPOTS:
		var s: Dictionary = ZooMap.SPOTS[k]
		ok((ZooMap.AREAS[s["area"]]["rect"] as Rect2).has_point(s["pos"]), "spot %s is on its area" % k)
		if ZooMap.AREAS[s["area"]]["kind"] == "water":
			ok(s["height"] <= 0.0, "spot %s is in the water (%.2f)" % [k, s["height"]])
		else:
			ok(is_equal_approx(ZooMap.surface_height(s["pos"]), s["height"]), "spot %s's height matches the surface under it (%.2f)" % [k, ZooMap.surface_height(s["pos"])])
		ok(ZooMap.AREAS.has(s["bay"]) and ZooMap.AREAS[s["bay"]]["kind"] in ["bay", "path"], "spot %s has a viewing bay or path" % k)
	for k in ZooMap.child_stands("lion_hill"):
		var c: Vector2 = (ZooMap.AREAS[k]["rect"] as Rect2).get_center()
		ok(not ZooMap.blocked_for_child(c), "a child can stand in %s" % k)
	ok(ZooMap.blocked_for_child(ZooMap.SPOTS["lion_sun_rock"]["pos"]), "a child cannot walk onto the Sun Rock")
	ok(not ZooMap.blocked_for_child(ZooMap.ARRIVAL), "the arrival point is free")
	for res in ZooMap.RESIDENTS:
		var home: String = ZooMap.RESIDENTS[res]["home"]
		ok(ZooMap.SPOTS.has(home) or ZooMap.ANCHORS.has(home), "%s has a home (%s)" % [res, home])


## Rule H3: rock within 1.5 m of a path is at most 0.9 m high, so a 1.3 m child stays visible
## from every camera turn. Backdrops must be 1.5 m or more away from every path.
func test_layout_h3() -> void:
	for k in ZooMap.AREAS:
		var a: Dictionary = ZooMap.AREAS[k]
		if a["kind"] != "terrace" and a["kind"] != "backdrop":
			continue
		if a["height"] <= 0.9:
			continue
		var r: Rect2 = a["rect"]
		for p in ZooMap.AREAS:
			var b: Dictionary = ZooMap.AREAS[p]
			if not b["kind"] in ["path", "bay"]:
				continue
			var gap := _rect_gap(r, b["rect"])
			ok(gap >= 1.5, "H3: %s (%.1f m high) is %.2f m from %s; needs 1.5 m" % [k, a["height"], gap, p])


static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dz).length()


## Rule H1: from the front of its bay, with the camera at its default turn and zoom, the top of a
## standing or roaring lion at each lion spot shows below the top bar, and its feet above the
## bottom edge, on every layout. Lion head-top heights are the slice's targets (section 6.3):
## 1.55 m standing, 2.35 m above the ground when roaring on the 0.7 m Sun Rock (1.65 m pose).
func test_show_spots_visible() -> void:
	for k in ZooMap.SPOTS:
		var s: Dictionary = ZooMap.SPOTS[k]
		if not str(k).begins_with("lion_"):
			continue
		var bay: Rect2 = ZooMap.AREAS[s["bay"]]["rect"]
		var child := Vector2(clampf(s["pos"].x, bay.position.x + 0.3, bay.end.x - 0.3), clampf(s["pos"].y, bay.position.y + 0.3, bay.end.y - 0.3))
		var top: float = s["height"] + (1.65 if "roar" in s["use"] else 1.55)
		var feet := Vector3(s["pos"].x, s["height"], s["pos"].y)
		var head := Vector3(s["pos"].x, top, s["pos"].y)
		for lay in LAYOUTS:
			var view: Vector2 = LAYOUTS[lay]
			var xf := pose(child, 0.0, 0)
			var hp = CameraRig.project(xf, view, head)
			var fp = CameraRig.project(xf, view, feet)
			ok(hp != null and fp != null, "%s seen from %s on %s is in front of the camera" % [k, s["bay"], lay])
			if hp == null or fp == null:
				continue
			ok(hp.y >= TOP_BAR, "H1: %s's head top (%.2f m) shows below the top bar from %s on %s (y %.0f)" % [k, top, s["bay"], lay, hp.y])
			ok(fp.y <= view.y, "%s's feet are on screen from %s on %s (y %.0f)" % [k, s["bay"], lay, fp.y])
			ok(hp.x >= 0.0 and hp.x <= view.x, "%s is on screen sideways from %s on %s (x %.0f)" % [k, s["bay"], lay, hp.x])


func test_two_bone_reach() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var worst := 0.0
	for i in 400:
		var l1 := rng.randf_range(0.25, 0.6)
		var l2 := rng.randf_range(0.25, 0.6)
		var root := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var d := rng.randf_range(absf(l1 - l2) + 0.02, l1 + l2 - 0.02)
		var target := root + Vector2.from_angle(rng.randf_range(-PI, PI)) * d
		var r: Dictionary = ZooRig.two_bone(root, target, l1, l2)
		ok(r["reach"], "target %d is within reach" % i) if not r["reach"] else null
		worst = maxf(worst, (r["end"] as Vector2).distance_to(target))
		ok(is_equal_approx((r["joint"] as Vector2).distance_to(root), l1), "segment 1 keeps its length") if i < 5 else null
	ok(worst < 0.02, "a hand or paw lands within 2 cm of its target (worst %.4f m)" % worst)
	var far: Dictionary = ZooRig.two_bone(Vector2.ZERO, Vector2(5, 0), 0.5, 0.5)
	ok(not far["reach"], "out of reach is reported")
	ok((far["end"] as Vector2).distance_to(Vector2(1, 0)) < 0.01, "out of reach the limb points straight at the target")


func test_pendulum_and_arc() -> void:
	var amp := deg_to_rad(50.0)
	var peak := 0.0
	var peak_rm := 0.0
	for i in 200:
		var t := i * 0.01
		peak = maxf(peak, absf(ZooRig.pendulum(t, amp, 2.0)))
		peak_rm = maxf(peak_rm, absf(ZooRig.pendulum(t, amp, 2.0, 0.0, true)))
	ok(absf(peak - amp) < 0.01, "a vine swings 50 degrees each way")
	ok(absf(peak_rm - amp * 0.5) < 0.01, "with Reduce Motion it swings 25 degrees: smaller, not off")
	var a := Vector3(0, 1.2, 0)
	var b := Vector3(2.5, 2.0, 0)
	ok(ZooRig.arc(a, b, 0.6, 0.0).distance_to(a) < 0.001 and ZooRig.arc(a, b, 0.6, 1.0).distance_to(b) < 0.001, "a leap starts and ends on its anchors")
	ok(ZooRig.arc(a, b, 0.6, 0.5).y > 2.0, "a leap rises above the higher anchor")
	var lo := 1.0
	var hi := 1.0
	for i in 101:
		var s := ZooRig.arc_squash(i / 100.0)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	ok(lo >= 0.92 - 0.0001 and hi <= 1.08 + 0.0001, "squash and stretch stay within 8 %")


# ---------------------------------------------------------------- the brain

## Every route joins two anchors; every anchor can be left; the route graph is connected.
func test_zoo_routes() -> void:
	for l in ZooMap.LINKS:
		ok(ZooMap.ANCHORS.has(l[0]) and ZooMap.ANCHORS.has(l[1]), "route %s -> %s joins two anchors" % [l[0], l[1]])
	for k in ZooMap.ANCHORS:
		ok(not ZooMap.links_from(k).is_empty(), "%s can be left" % k)
		ok(not ZooBrain.route("m_court_s", k).is_empty(), "%s can be reached from the court" % k)
		ok(not ZooBrain.route(k, "m_court_s").is_empty(), "the court can be reached from %s" % k)
	# 22.5 item 3: no route's path passes over ground where a child can walk.
	for l in ZooMap.LINKS:
		var a := ZooMap.anchor_pos(l[0])
		var b := ZooMap.anchor_pos(l[1])
		if l[2] in ["run", "hop", "climb", "descend", "drop"]:
			continue   # on the ground, a short step beside a structure, or landing from the rings
		for i in 21:
			var p := ZooBrain.path_point(l[2], a, b, i / 20.0)
			var low := p.y   # anchors and paths are the monkey's feet
			if low < 1.4:
				ok(ZooMap.blocked_for_child(Vector2(p.x, p.z)), "%s %s->%s at %.2f passes over blocked ground, not a child's (%.1f, %.1f, body %.2f m up)" % [l[2], l[0], l[1], i / 20.0, p.x, p.z, low])
	for k in ZooMap.STATIONS:
		ok(not ZooMap.blocked_for_child(ZooMap.STATIONS[k]["pos"]), "station %s can be reached by a child" % k)


func _run_monkeys(seed: int, seconds: float, reduce: bool, child: Vector2) -> Dictionary:
	var b = ZooBrain.new(seed)
	b.reduce_motion = reduce
	b.history_on = true
	b.spawn()
	var kids := [{"id": 1, "pos": child, "emote": "", "emote_t": 0.0}]
	var res := {"max_big": 0, "all_rest_max": 0.0, "jumps": 0, "overlap": 0, "brain": b, "big_starts": [], "never_off_anchor": true}
	var all_rest := 0.0
	var last_pos := {}
	var steps := int(seconds / ZooBrain.STEP)
	for i in steps:
		var before := {}
		for a in b.animals:
			before[a["id"]] = [a["action"], a["t0"]]
		b.tick(kids)
		res["max_big"] = maxi(res["max_big"], b.big_count())
		var any_moving := false
		var anchors := {}
		for a in b.animals:
			if a["species"] != "monkey":
				continue
			if not (a["action"] in ZooBrain.RESTS or a["action"] == "idle"):
				any_moving = true
			if before[a["id"]][1] != a["t0"] and a["action"] in ZooBrain.BIG:
				res["big_starts"].append([b.time, a["id"], a["action"], ZooBrain.path_point(a["action"], a["from"], a["to"], 0.0)])
			var p: Vector3 = b.pos_of(a)
			if last_pos.has(a["id"]) and p.distance_to(last_pos[a["id"]]) > 1.0:
				res["jumps"] += 1
				print("  jump: %s %s %.2f m at %.1f s" % [a["id"], a["action"], p.distance_to(last_pos[a["id"]]), b.time])
			last_pos[a["id"]] = p
			if anchors.has(a["anchor"]):
				res["overlap"] += 1
			anchors[a["anchor"]] = true
			if b._occupied.get(a["anchor"], "") != a["id"]:
				res["never_off_anchor"] = false
		all_rest = 0.0 if any_moving else all_rest + ZooBrain.STEP
		res["all_rest_max"] = maxf(res["all_rest_max"], all_rest)
	return res


## Section 22.4's acceptance, on a deterministic seed: variety, spontaneous starts, ambient life
## with real pauses, coherence, social play and no moving in step.
func test_monkey_repertoire() -> void:
	var child := Vector2(29.0, -19.0)   # in the Monkey Court, doing nothing
	var r := _run_monkeys(11, 240.0, false, child)
	var b = r["brain"]
	var chosen := {}
	var social := 0
	var last_by := {}
	var repeats := 0
	var same_start := 0
	var starts: Array = []
	for e in b.history:
		var act: String = e[2]
		if ZooMap.RESIDENTS[e[1]]["species"] != "monkey":
			continue
		if act.begins_with("social_"):
			social += 1
			chosen[act] = true
			continue
		if e[3] or act in ZooBrain.RESTS or act == "idle":
			continue
		chosen[act] = true
		if last_by.get(e[1], "") == act:
			repeats += 1
		last_by[e[1]] = act
		starts.append(e)
	for i in starts.size():
		for j in range(i + 1, starts.size()):
			if starts[j][0] - starts[i][0] >= ZooBrain.TROOP_GAP:
				break
			if starts[j][2] == starts[i][2] and not starts[i][2] in ZooBrain.SHARED + ["run"]:
				same_start += 1
	var family := {}
	for e in b.history:
		if ZooMap.RESIDENTS[e[1]]["species"] == "monkey" and not e[2] in ZooBrain.RESTS and e[2] != "idle":
			family[e[2]] = true
	print("monkeys 240 s: chosen %s; all actions seen %s; social %d; max big %d; longest troop rest %.1f s" % [chosen.keys(), family.keys(), social, r["max_big"], r["all_rest_max"]])
	ok(family.size() >= 12, "at least 12 distinct actions in 240 s with no input (%d)" % family.size())
	ok(chosen.size() >= 10, "at least 10 distinct self-chosen actions (%d)" % chosen.size())
	ok(repeats == 0, "no monkey repeats a chosen action back to back (%d repeats)" % repeats)
	ok(same_start == 0, "no two monkeys start the same move within 3 s (%d)" % same_start)
	ok(social >= 2, "at least two social plays in 240 s (%d)" % social)
	ok(r["max_big"] <= ZooBrain.MAX_BIG, "at most %d in a big move at once (%d)" % [ZooBrain.MAX_BIG, r["max_big"]])
	ok(r["all_rest_max"] <= 8.0, "the troop is never all at rest for more than 8 s (%.1f)" % r["all_rest_max"])
	ok(r["jumps"] == 0, "no monkey jumps position between two steps (%d)" % r["jumps"])
	ok(r["overlap"] == 0, "no anchor ever holds two monkeys (%d)" % r["overlap"])
	ok(r["never_off_anchor"], "every monkey always holds its anchor")
	# Spontaneous: a big move starts within 8 s of arrival near the child, and every 10 s after.
	var bs: Array = r["big_starts"]
	var near: Array = bs.filter(func(x): return Vector2(x[3].x, x[3].z).distance_to(child) < 12.0)
	ok(not near.is_empty() and near[0][0] <= 8.0, "a big move starts near the child within 8 s (%s)" % (str(near[0][0]) if not near.is_empty() else "none"))
	var windows := 0
	var hit := 0
	var t := 0.0
	while t < 240.0:
		windows += 1
		if near.any(func(x): return x[0] >= t and x[0] < t + 10.0):
			hit += 1
		t += 10.0
	ok(hit >= int(ceil(windows * 0.8)), "a big move starts near the child in at least 80 %% of 10 s windows (%d of %d)" % [hit, windows])
	# Each one's arrivals land on anchors: the end of every move is an anchor's position.
	var bad := 0
	for a in b.animals:
		if a["species"] == "monkey" and b.progress(a) >= 1.0 and b.pos_of(a).distance_to(ZooMap.anchor_pos(a["anchor"])) > 0.05:
			bad += 1
	ok(bad == 0, "a finished move rests on its anchor")


func test_monkey_reduce_motion() -> void:
	var r := _run_monkeys(11, 240.0, true, Vector2(29.0, -19.0))
	var family := {}
	for e in r["brain"].history:
		if ZooMap.RESIDENTS[e[1]]["species"] == "monkey" and not e[2] in ZooBrain.RESTS and e[2] != "idle":
			family[e[2]] = true
	ok(r["max_big"] <= ZooBrain.MAX_BIG_REDUCED, "Reduce Motion: at most two big moves at once (%d)" % r["max_big"])
	ok(family.size() >= 10, "Reduce Motion: the monkeys still play: %d action families" % family.size())
	ok(r["jumps"] == 0 and r["overlap"] == 0, "Reduce Motion: still coherent")
	ok(is_equal_approx(ZooRig.pendulum(0.5, 1.0, 2.0, 0.0, true) * 2.0, ZooRig.pendulum(0.5, 1.0, 2.0)), "Reduce Motion halves a swing's arc when drawn")


## Different seeds: still lively, never stuck, never overlapping.
func test_monkey_seeds() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var r := _run_monkeys(seed, 180.0, false, Vector2(28.0, -13.0))
		ok(r["overlap"] == 0 and r["jumps"] == 0, "seed %d: coherent" % seed)
		ok(r["all_rest_max"] <= 8.0, "seed %d: never all resting over 8 s (%.1f)" % [seed, r["all_rest_max"]])
		ok(r["max_big"] <= ZooBrain.MAX_BIG, "seed %d: at most three big moves at once" % seed)


func _lion_brain() -> Variant:
	var b = ZooBrain.new(7)
	b.spawn()
	for i in 30:
		b.tick([])
	return b


func test_lion_answers() -> void:
	var b = _lion_brain()
	var at := Vector2(0.0, -11.2)   # the Pride Overlook
	b.tick([{"id": 1, "pos": at, "emote": "cheer", "emote_t": 5.0}])
	ok(b.animal("rory")["action"] == "roar", "a cheer at the overlook: Rory roars (%s)" % b.animal("rory")["action"])
	ok(b.events.any(func(e): return e["kind"] == "roar"), "the roar is an event for every device")
	b.events.clear()
	b.tick([{"id": 1, "pos": at, "emote": "cheer", "emote_t": 6.0}])
	ok(b.animal("honey")["action"] == "roar", "a second cheer right after: Honey roars in turn (%s)" % b.animal("honey")["action"])
	b.tick([{"id": 1, "pos": at, "emote": "cheer", "emote_t": 6.0}])
	ok(b.events.filter(func(e): return e["kind"] == "roar").size() == 1, "the same emote is answered once")
	for i in 40:
		b.tick([])
	b.tick([{"id": 2, "pos": Vector2(6.0, -12.0), "emote": "wave", "emote_t": 9.0}])
	var nodder: Array = b.animals.filter(func(x): return x["action"] == "nod")
	ok(nodder.size() == 1, "a wave: the nearest lion nods")
	b.tick([{"id": 2, "pos": Vector2(6.0, -12.0), "emote": "dance", "emote_t": 10.0}])
	ok(b.animal("honey")["action"] == "roll", "a dance: Honey rolls on her back")
	b.tick([{"id": 2, "pos": Vector2(6.0, -12.0), "emote": "heart", "emote_t": 11.0}])
	ok(b.animals.any(func(x): return x["action"] == "blink"), "a heart: a slow blink")
	b.tick([{"id": 3, "pos": Vector2(30.0, -19.0), "emote": "cheer", "emote_t": 12.0}])
	ok(not b.animals.any(func(x): return x["species"] != "monkey" and x["action"] == "roar" and x["t0"] > b.time - 0.15), "a cheer on Monkey Hill does not make a lion roar")


func test_lion_pace() -> void:
	var b = _lion_brain()
	var zs: Array = []
	var kz := -13.0
	var paced := 0
	for i in 200:
		kz = lerpf(-13.0, -20.0, i / 200.0)
		b.tick([{"id": 1, "pos": Vector2(-10.5, kz), "emote": "", "emote_t": 0.0}])
		var rory: Dictionary = b.animal("rory")
		if rory["action"] == "patrol" and rory["follow"] == "pace":
			paced += 1
			zs.append([kz, b.pos_of(rory).z])
	ok(paced > 100, "a child walking Lion's Pass: Rory paces the Ridge (%d of 200 steps)" % paced)
	if not zs.is_empty():
		var last: Array = zs[-1]
		ok(absf(last[1] - clampf(last[0], -19.4, -14.1)) < 2.0, "and keeps level with the child (child z %.1f, lion z %.1f)" % [last[0], last[1]])
		var rory: Dictionary = b.animal("rory")
		ok(absf(b.pos_of(rory).x - (-7.0)) < 1.6, "on the Ridge, beside the pass")
	for i in 60:
		b.tick([{"id": 1, "pos": Vector2(0.0, 20.0), "emote": "", "emote_t": 0.0}])
	ok(b.animal("rory")["follow"] != "pace", "when the child leaves the pass, the pacing stops")


func test_stations() -> void:
	var b = _lion_brain()
	ok(b.use_station("lion_treats", Vector2(1.8, -10.6)) == "", "Offer a treat: a lion comes")
	var eater := ""
	for i in 200:
		b.tick([])
		for a in b.animals:
			if a["species"] != "monkey" and a["action"] == "eat":
				eater = a["id"]
	ok(eater != "", "and eats it on the rock's edge (%s)" % eater)
	var b2 = ZooBrain.new(3)
	b2.spawn()
	for i in 20:
		b2.tick([])
	ok(b2.use_station("monkey_bananas", Vector2(31.6, -12.0)) == "", "Offer a banana: a monkey comes")
	var caught := false
	var ate := false
	for i in 300:
		b2.tick([])
		for a in b2.animals:
			if a["action"] == "catch":
				caught = true
			if a["species"] == "monkey" and a["action"] == "eat":
				ate = true
	ok(caught and ate, "it catches the banana in the air and eats it (%s, %s)" % [caught, ate])
	var b3 = ZooBrain.new(4)
	b3.spawn()
	for i in 20:
		b3.tick([])
	ok(b3.use_station("monkey_bell", Vector2(29.0, -22.4)) == "", "Ring the bell: a monkey races up the Spire")
	var rang := false
	var top := false
	for i in 400:
		b3.tick([])
		for e in b3.events:
			if e["kind"] == "bell":
				rang = true
				top = Vector3(e["at"]).distance_to(ZooMap.anchor_pos("m_spire_3")) < 0.05
		b3.events.clear()
	ok(rang and top, "and rings it again at the top (%s, %s)" % [rang, top])


func test_monkey_copycat() -> void:
	var b = ZooBrain.new(9)
	b.spawn()
	for i in 50:
		b.tick([])
	var kid := {"id": 1, "pos": Vector2(29.0, -18.0), "emote": "dance", "emote_t": 3.0}
	var copied := {}
	for i in 30:
		b.tick([kid])
		for a in b.animals:
			if a["action"] == "copy":
				copied[a["id"]] = b.time
	ok(copied.size() >= 2, "a dance on Monkey Hill: the troop copies it (%d monkeys)" % copied.size())
	var times: Array = copied.values()
	times.sort()
	ok(times.size() < 2 or times[-1] - times[0] >= 0.2, "in a ripple, not all at once")


func test_pack_roundtrip() -> void:
	var b = ZooBrain.new(5)
	b.spawn()
	for i in 37:
		b.tick([])
	var d: Dictionary = ZooBrain.unpack(b.pack())
	ok(d["animals"].size() == ZooMap.ORDER.size(), "every resident is in the packed state")
	ok(absf(d["time"] - b.time) < 0.01, "with the authority's time")
	for i in b.animals.size():
		var a: Dictionary = b.animals[i]
		var u: Dictionary = d["animals"][i]
		ok(u["action"] == a["action"] and u["to"].distance_to(a["to"]) < 0.01 and absf(u["t0"] - a["t0"]) < 0.01, "%s survives packing" % a["id"])
	ok(ZooBrain.unpack(PackedFloat32Array([1.0, 2.0])).get("animals", []).is_empty(), "a damaged packet draws nothing")
	var t := ZooBrain.unpack_target(ZooBrain._target_param(Vector3(31.6, 0, -19.0)))
	ok(t.distance_to(Vector2(31.6, -19.0)) < 0.06, "a pass target survives packing")


# ---------------------------------------------------------------- the whole roster

func _brain(seed := 21) -> Variant:
	var b = ZooBrain.new(seed)
	b.spawn()
	for i in 30:
		b.tick([])
	return b


func _kid(id: int, pos: Vector2, extra := {}) -> Dictionary:
	var k := {"id": id, "pos": pos, "emote": "", "emote_t": 0.0, "still": 0.0, "speed": 0.0, "run": 0.0, "vel": Vector2.ZERO}
	k.merge(extra, true)
	return k


func test_roster() -> void:
	var count := {}
	for id in ZooMap.ORDER:
		var sp: String = ZooMap.RESIDENTS[id]["species"]
		count[sp] = count.get(sp, 0) + 1
	ok(ZooMap.ORDER.size() == 18, "eighteen animals: r1's fourteen and Bao, Mabel, Pebble, Flip (%d)" % ZooMap.ORDER.size())
	ok(count.size() == 10 + 1, "ten species, the lion pair counted as lion and lioness (%s)" % str(count))
	ok(count.get("monkey", 0) == 5 and count.get("zebra", 0) == 2 and count.get("otter", 0) == 2, "five monkeys, two zebras, two otters")
	for sp in ZooBrain.HOME_OF:
		ok(ZooMap.HABITATS.has(ZooBrain.HOME_OF[sp]), "%s has a habitat" % sp)
		if sp != "monkey":
			ok(ZooLife.LIFE.has(sp) and ZooLife.LIFE[sp]["routine"].size() >= 3, "%s does three or more things by itself" % sp)
			ok(ZooLife.LIFE[sp].has("treat") and ZooLife.LIFE[sp]["emotes"].size() == 4, "%s has a treat and answers all four emotes" % sp)
			for o in ZooLife.LIFE[sp]["routine"]:
				for spot in o[1]:
					ok(spot == "" or ZooMap.SPOTS.has(spot), "%s's spot %s exists" % [sp, spot])
		ok(ZooLife.ANSWERS.has(sp if sp != "lioness" else "lioness"), "%s has answers for the discovery log" % sp)
	for a in ZooBrain.ACTIONS:
		ok(ZooBrain.ACTIONS.count(a) == 1, "action %s is listed once" % a)


## A long run with children wandering: every animal stays in its habitat, water animals stay
## in water or on their beach, nothing jumps.
func test_all_stay_home() -> void:
	var b = ZooBrain.new(31)
	b.spawn()
	var last := {}
	var jumps := 0
	var outside := 0
	var acts := {}
	for i in 3000:
		var t := i * 0.1
		var kids := [_kid(1, Vector2(-30 + 6.0 * sin(t * 0.05), -15.0)), _kid(2, Vector2(0, 11.0)), _kid(3, Vector2(-30.0, 8.0), {"still": 3.0})]
		b.tick(kids)
		for a in b.animals:
			var p: Vector3 = b.pos_of(a)
			var home: Rect2 = (ZooMap.HABITATS[ZooBrain.HOME_OF[a["species"]]] as Rect2).grow(0.3)
			if not home.has_point(Vector2(p.x, p.z)):
				outside += 1
				if outside < 4:
					print("  outside: %s %s at (%.1f, %.1f)" % [a["id"], a["action"], p.x, p.z])
			if last.has(a["id"]) and p.distance_to(last[a["id"]]) > 0.9:
				jumps += 1
				if jumps < 4:
					print("  jump: %s %s %.2f m at %.1f" % [a["id"], a["action"], p.distance_to(last[a["id"]]), b.time])
			last[a["id"]] = p
			acts[a["species"] + ":" + a["action"]] = true
	ok(outside == 0, "every animal stays in its habitat (%d outside)" % outside)
	ok(jumps == 0, "nothing jumps between two steps (%d)" % jumps)
	for sp in ["tiger", "giraffe", "zebra", "hippo", "otter", "lion", "lioness"]:
		var mine: Array = acts.keys().filter(func(k): return k.begins_with(sp + ":"))
		ok(mine.size() >= 4, "%s did 4 or more different things in 300 s (%s)" % [sp, mine])


func test_tiger() -> void:
	var b = _brain()
	var bay := Vector2(-37.5, -15.2)
	var peek := false
	for i in 200:
		b.tick([_kid(1, bay, {"still": 2.0})])
		if b.animal("tango")["action"] == "peekaboo":
			peek = true
	ok(peek, "standing still at Thicket Bay: Tango plays peekaboo")
	var b2 = _brain()
	b2.tick([_kid(1, Vector2(-30.0, -15.2), {"emote": "cheer", "emote_t": 4.0})])
	var walked := false
	for i in 300:
		b2.tick([])
		if b2.animal("tango")["action"] == "show_walk":
			walked = true
	ok(walked, "a cheer on Tiger Hill: a show walk along the log")


func test_savanna() -> void:
	var b = _brain()
	var g: Dictionary = b.animal("topper")
	var gp: Vector3 = b.pos_of(g)
	var bowed := false
	for i in 150:
		b.tick([_kid(1, Vector2(gp.x + 1.8, gp.z + 1.0), {"still": 2.0})])
		if b.animal("topper")["action"] == "bow":
			bowed = true
	ok(bowed, "standing still within 3 m of Topper: the bow")
	var b2 = _brain()
	var galloped := 0
	var kz := 0.0
	for i in 80:
		var kx := -10.0 + i * 0.25
		b2.tick([_kid(1, Vector2(kx, kz), {"speed": 2.6, "run": 7.0, "vel": Vector2(2.6, 0)})])
		if b2.animal("zig")["action"] == "gallop" and b2.animal("zag")["action"] == "gallop":
			galloped += 1
	ok(galloped > 20, "running across the meadow: both zebras gallop alongside (%d steps)" % galloped)
	ok(b2.animal("topper")["action"] in ["look", "bow", "browse", "walk", "drink", "blink"], "and Topper's head follows")


func test_splash_bay() -> void:
	var b = _brain()
	var surfaced := false
	for i in 200:
		b.tick([_kid(1, Vector2(-29.8, 5.0), {"still": 2.0})])
		if b.animal("bubbles")["action"] == "surface":
			surfaced = true
	ok(surfaced, "standing still on the jetty: Bubbles surfaces beside it")
	var b2 = _brain()
	var escorted := 0
	for i in 120:
		b2.tick([_kid(1, Vector2(-38.0, -3.0 + i * 0.06), {"speed": 1.5})])
		if b2.animal("skip")["follow"] == "escort":
			escorted += 1
	ok(escorted > 40, "walking the bank: the otters swim alongside (%d steps)" % escorted)


func test_station_answers() -> void:
	var cases := {"tiger_ball": ["tango", "pool_leap"], "savanna_pump": ["topper", "drink"], "splash_shower": ["bubbles", "shower"],
		"monkey_tyre": ["", "tyre"], "monkey_bongos": ["", "drum"]}
	for st in cases:
		var b = _brain(5)
		ok(b.use_station(st, ZooMap.STATIONS[st]["pos"]) == "", "%s is answered" % st)
		var seen := false
		for i in 300:
			b.tick([])
			for a in b.animals:
				if (cases[st][0] == "" or a["id"] == cases[st][0]) and a["action"] == cases[st][1]:
					seen = true
		ok(seen, "%s: %s" % [st, cases[st][1]])
	var b = _brain(6)
	b.use_station("monkey_tyre", ZooMap.STATIONS["monkey_tyre"]["pos"])
	for i in 120:
		b.tick([])
	var on := false
	for a in b.animals:
		if a["anchor"] == "m_tyre":
			on = true
	ok(on, "a monkey climbs onto the tyre")
	b.use_station("monkey_tyre", Vector2.ZERO)
	b.use_station("monkey_tyre", Vector2.ZERO)
	var off := false
	for i in 120:
		b.tick([])
		for a in b.animals:
			if a["species"] == "monkey" and a["action"] == "leap" and a["to"].distance_to(ZooMap.anchor_pos("m_court_e")) < 0.05:
				off = true
	ok(off, "the third push sends it off the tyre with a leap")


func test_treats_full() -> void:
	var b = _brain()
	var actions := []
	for n in 4:
		ok(b.offer_to("tango", Vector2(-28.0, -15.2)) == "", "treat %d is taken" % (n + 1))
		actions.append(b.animal("tango")["action"])
		for i in 30:
			b.tick([])
	ok(b.animal("tango")["action"] == "full" or actions.has("full"), "the fourth treat in a minute: full and happy (%s)" % str(actions))
	var b2 = _brain()
	ok(b2.use_station("splash_treats", Vector2(-33.0, 8.6)) == "", "Splash Bay's treat table")
	# zoo r2: the table feeds the least-fed animal, so a penguin may come first now.
	ok(b2.events.any(func(e): return e["kind"] == "splash") or b2.animal("skip")["action"] == "beg" or b2.animal("ripple")["action"] == "beg" \
		or ["pebble", "flip"].any(func(id): return b2.animal(id)["action"] in ["eat", "waddle", "swim"]), "Bubbles chomps (a splash), an otter begs or a penguin comes")


func test_toys() -> void:
	var b = _brain(8)
	b.toys = [{"kind": "zoo_ball", "pos": Vector2(2.0, -18.5)}, {"kind": "leaf_feeder", "pos": Vector2(0.0, 4.0)}, {"kind": "zoo_box", "pos": Vector2(-36.0, -26.0)}]
	var seen := {}
	for i in 1500:
		b.tick([])
		for a in b.animals:
			if a["action"] in ["pounce", "browse", "graze", "hide"]:
				var p: Vector3 = b.pos_of(a)
				for t in b.toys:
					if Vector2(p.x, p.z).distance_to(t["pos"]) < 1.4:
						seen[a["species"] + ":" + t["kind"]] = true
	ok(seen.has("lion:zoo_ball") or seen.has("lioness:zoo_ball"), "a ball on Lion Hill: a lion pounces on it (%s)" % str(seen.keys()))
	ok(seen.has("giraffe:leaf_feeder") or seen.has("zebra:leaf_feeder"), "a leaf feeder in the meadow: browsed")
	ok(seen.has("tiger:zoo_box"), "a big box on Tiger Hill: Tango hides in it")


func test_keep_clear() -> void:
	var b = _brain()
	var z: Dictionary = b.animal("zig")
	for i in 200:
		b.tick([])
		if b.animal("zig")["action"] == "graze":
			break
	var p: Vector3 = b.pos_of(b.animal("zig"))
	var stepped := false
	for i in 120:
		b.tick([_kid(1, Vector2(p.x + 0.3, p.z))])
		if b.animal("zig")["action"] == "step_back":
			stepped = true
	ok(stepped, "a child walking into a resting zebra: it steps back")


func test_found_events() -> void:
	var b = _brain()
	b.tick([_kid(1, Vector2(0.0, -11.2), {"emote": "cheer", "emote_t": 3.0})])
	ok(b.events.any(func(e): return e["kind"] == "found" and e["species"] == "lion" and e["answer"] == "roar"), "a roar is reported once for the discovery log")
	for sp in ZooLife.ANSWERS:
		for key in ZooLife.ANSWERS[sp]:
			ok(str(ZooLife.ANSWERS[sp][key]).length() > 5, "%s/%s has a hint" % [sp, key])


# ---------------------------------------------------------------- models (section 4, 6.3, 14.1)

static func _visible_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible:
			continue
		var mat := m.material_override as BaseMaterial3D
		if mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var p: Node = m
		var hidden := false
		while p != n:
			if p.name == "prop":
				hidden = true
			p = p.get_parent()
		if hidden:
			continue
		var xf := Transform3D()
		var q: Node = m
		while q != n:
			xf = (q as Node3D).transform * xf
			q = q.get_parent()
		var b: AABB = xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _make(sp: String, young := false) -> Node3D:
	var a: Node3D = ZooAnimal.new()
	root.add_child(a)
	a.setup(sp, "t_" + sp, 0, young)
	return a


func test_models() -> void:
	for sp in ["lion", "lioness", "tiger", "monkey", "giraffe", "zebra", "hippo", "otter", "panda", "elephant", "penguin"]:
		var a := _make(sp)
		var b := _visible_aabb(a)
		b = AABB(b.position * a.scale.y, b.size * a.scale.y)   # as drawn (zoo r2 scales the penguin and panda)
		var want: float = ZooBrain.SPECIES[sp]["height"]
		var meshes := a.find_children("*", "MeshInstance3D", true, false).size()
		var tris := 0
		var bad_mat := 0
		for mi in a.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null and not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat = m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh.get_surface_count() > 0 else null)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				var bm := mat as BaseMaterial3D
				if bm.albedo_texture != null or bm.metallic > 0.0 or bm.roughness < 0.85:
					bad_mat += 1
		print("  model %s: built %.2f x %.2f x %.2f (height wanted %.2f), %d mesh nodes, %d triangles" % [sp, b.size.x, b.size.y, b.size.z, want, meshes, tris])
		var top := b.end.y
		if sp == "monkey":
			ok(top >= 1.0, "the monkey stands at least 1.0 m tall in its rest pose (%.2f)" % top)
		else:
			ok(absf(top - want) <= want * 0.12, "%s is %.2f m tall in its usual pose (wanted %.2f within 12 %%)" % [sp, top, want])
		ok(b.position.y > -0.2, "%s stands on the ground (bottom %.2f)" % [sp, b.position.y])
		var calls: int = {"giraffe": 20, "monkey": 16, "otter": 16}.get(sp, 18)
		ok(meshes <= calls, "%s draws in %d calls or fewer, design 14.1 (%d)" % [sp, calls, meshes])
		var budget: int = {"giraffe": 11000, "monkey": 9000, "otter": 9000}.get(sp, 10000)
		ok(tris <= budget, "%s has %d triangles (design 14.1 budget %d)" % [sp, tris, budget])
		ok(bad_mat == 0, "%s: no texture, no metal, matte (%d bad materials)" % [sp, bad_mat])
		a.free()
	var young := _make("monkey", true)
	ok(young.scale.x < 0.9 and young.scale.x > 0.6, "Bibi, the young one, is drawn smaller (%.2f)" % young.scale.x)
	young.free()


## Section 22.5 item 2: each species measured where it really stands (its routine and answer
## spots, at the spot's height), from the nearest point of the spot's viewing bay, with the
## camera at its default turn and zoom: the projected height of its usual pose at the four
## layouts. The worst case is reported; T1 (115 px) must hold where a species signs its
## signature, and the honest numbers are printed for all spots.
func test_readability_in_place() -> void:
	var heights := {}
	for sp in ZooBrain.SPECIES:
		var a := _make(sp)
		heights[sp] = _visible_aabb(a).end.y * a.scale.y if sp != "monkey" else 1.1   # as drawn (zoo r2 scales the penguin and panda)
		a.free()
	var rows: Array = []
	var fails := 0
	for spot in ZooMap.SPOTS:
		var s: Dictionary = ZooMap.SPOTS[spot]
		var sp := ""
		for x in ZooLife.LIFE:
			for o in ZooLife.LIFE[x]["routine"]:
				if spot in o[1]:
					sp = x
			if ZooLife.LIFE[x]["treat"][1] == spot:
				sp = x
		if sp == "":
			for r in ZooMap.RESIDENTS:
				if ZooMap.RESIDENTS[r]["home"] == spot:
					sp = ZooMap.RESIDENTS[r]["species"]
		if sp == "":
			sp = {"lion_": "lion", "tiger_": "tiger", "giraffe_": "giraffe", "savanna_": "zebra", "zebra_": "zebra", "hippo_": "hippo", "otter_": "otter", "splash_": "hippo"}.get(str(spot).split("_")[0] + "_", "lion")
		var bay: Rect2 = ZooMap.AREAS[s["bay"]]["rect"]
		var child := Vector2(clampf(s["pos"].x, bay.position.x + 0.3, bay.end.x - 0.3), clampf(s["pos"].y, bay.position.y + 0.3, bay.end.y - 0.3))
		var h: float = heights[sp]
		var worst := INF
		for lay in LAYOUTS:
			var view: Vector2 = LAYOUTS[lay]
			var xf := pose(child, 0.0, 0)
			var foot = CameraRig.project(xf, view, Vector3(s["pos"].x, s["height"], s["pos"].y))
			var head = CameraRig.project(xf, view, Vector3(s["pos"].x, s["height"] + h, s["pos"].y))
			if foot == null or head == null:
				worst = 0.0
				continue
			worst = minf(worst, (foot as Vector2).y - (head as Vector2).y)
		rows.append([spot, sp, worst])
		if worst < 115.0:
			fails += 1
	rows.sort_custom(func(x, y): return x[2] < y[2])
	for r in rows:
		print("  readability %-20s %-8s %4.0f px" % [r[0], r[1], r[2]])
	ok(fails == 0, "every show spot shows its animal at least 115 px tall from its bay (%d below)" % fails)


## Design 9.1: a new town's tram stop stands 4 to 6 m from the arrival point and inside the first view, on
## every device at the town's arrival view (yaw 0, 9.5 m): its middle at least 15 % in from each screen edge
## and at least 80 % of its box on screen. It keeps off the stepping stones and the animals' start points,
## and its boarding point faces the arriving child.
func test_tram_stop_in_first_view() -> void:
	var m = TownModel.make_default()
	var id: String = m.tram_stop_id()
	ok(id != "", "a new town has its tram stop")
	if id == "":
		return
	var it: Dictionary = m.items[id]
	var p := Vector2(it["x"], it["z"])
	var spawn: Vector2 = TownModel.TOWN_SPAWN
	ok(p.distance_to(TownModel.TRAM_STOP_SPOT) < 0.01, "it stands at the designed spot (%s)" % p)
	var d := p.distance_to(spawn)
	ok(d >= 4.0 and d <= 6.0, "4 to 6 m from the arrival point (%.2f m)" % d)
	var r: float = Catalog.ITEMS["tram_stop"]["radius"]
	for v in LAYOUTS:
		var view: Vector2 = LAYOUTS[v]
		var xf := pose(spawn, 0.0, 0)
		var c = CameraRig.project(xf, view, Vector3(p.x, 1.0, p.y))
		ok(c != null, "%s: the stop is in front of the camera" % v)
		if c == null:
			continue
		var edge := minf(minf(c.x / view.x, 1.0 - c.x / view.x), minf(c.y / view.y, 1.0 - c.y / view.y))
		ok(edge >= 0.15, "%s: its middle is at least 15 %% in from the screen edges (%.3f)" % [v, edge])
		var box: Rect2 = CameraRig.box_rect(xf, view, Vector3(p.x, 0, p.y), r, 2.0)
		var frac := Rect2(Vector2.ZERO, view).intersection(box).get_area() / maxf(box.get_area(), 0.001)
		ok(frac >= 0.8, "%s: at least 80 %% of it is on screen (%.2f)" % [v, frac])
	for st in m.items.values():
		if st["space"] == "town" and st["kind"] == "path_stone":
			ok(Vector2(st["x"], st["z"]).distance_to(p) >= r + 0.5, "it keeps off the stepping stone at (%.1f, %.1f)" % [st["x"], st["z"]])
	for s in AnimalBrain.SPAWNS:
		ok(s.distance_to(p) >= r + 1.5, "it keeps clear of an animal's start at %s" % s)
	var board: Vector2 = TownModel.door_point(it)
	ok((board - p).normalized().dot((spawn - p).normalized()) >= 0.3, "its boarding point faces the arriving child")
	ok(m.validate_door("tram_stop", "town", p.x, p.y, it["rot"], id) == "", "its boarding point is on open ground")


## Design 10.7: in the rain the lions go to their den and rest there, side by side; in sun they do not
## stay there; they still answer a child's cheer in the rain.
func test_lions_den_in_rain() -> void:
	var b = ZooBrain.new(5)
	b.spawn()
	b.weather = "rain"
	for i in 600:
		b.tick([], ZooBrain.STEP)
	for id in ["rory", "honey"]:
		var a: Dictionary = b.animal(id)
		var p: Vector3 = b.pos_of(a)
		ok(p.distance_to(ZooBrain.DEN_SPOTS[id]) < 0.4 and a["action"] == "nap", "%s rests in the den in the rain (%s at %s)" % [id, a["action"], p])
	ok(ZooBrain.DEN_SPOTS["rory"].distance_to(ZooBrain.DEN_SPOTS["honey"]) >= 1.6, "the two lions lie apart, not in one another")
	# A cheer at the overlook in the rain: Rory still answers with a roar.
	var cheer := {"id": 1, "pos": Vector2(1.8, -10.6), "emote": "cheer", "emote_t": 0.0, "still": 0.0, "speed": 0.0, "vel": Vector2.ZERO, "run": false}
	var seen := false
	for i in 120:
		b.tick([cheer], ZooBrain.STEP)
		if b.animal("rory")["action"] == "roar":
			seen = true
	ok(seen, "Rory still roars for a cheer in the rain")
	b.weather = "sunny"
	var left := false
	for i in 900:
		b.tick([], ZooBrain.STEP)
		if b.pos_of(b.animal("rory")).distance_to(ZooBrain.DEN_SPOTS["rory"]) > 2.0:
			left = true
	ok(left, "in the sun Rory leaves the den again")


## Design 12.2: every "town" literal in the game's scripts was read and sorted into "the town itself"
## (stays), "outdoors" or "not a room" (ask core/places.gd). What stays is listed here per file, so a
## new one cannot slip in unread. A new literal fails this test: read it, use Places where it means
## "outdoors", "a map" or "a room", and only then raise its file's count with a reason.
const TOWN_LITERALS := {
	"scripts/autoload/music.gd": 3,
	"scripts/core/animal_brain.gd": 7,
	"scripts/core/blueprints.gd": 1,
	"scripts/core/catalog.gd": 35,
	"scripts/core/cozy_spots.gd": 1,
	"scripts/core/durable.gd": 3,
	"scripts/core/echoes.gd": 1,
	"scripts/core/hide_seek.gd": 2,
	"scripts/core/lamplight.gd": 1,
	"scripts/core/photo_ideas.gd": 5,
	"scripts/core/places.gd": 5,
	"scripts/core/play_rules.gd": 2,
	"scripts/core/ride_rules.gd": 4,
	"scripts/core/town_life.gd": 2,
	"scripts/core/town_model.gd": 43,
	"scripts/core/track_rules.gd": 2,
	"scripts/core/wishes.gd": 1,
	"scripts/net/activities.gd": 9,
	"scripts/net/animals.gd": 7,
	"scripts/net/session.gd": 22,
	"scripts/net/zoo.gd": 1,
	"scripts/ui/hud.gd": 9,
	"scripts/world/activity_world.gd": 4,
	"scripts/world/contraption_world.gd": 3,
	"scripts/world/guest_world.gd": 1,
	"scripts/world/play_controller.gd": 19,
	"scripts/world/play_world.gd": 4,
	"scripts/world/ride_world.gd": 2,
	"scripts/world/town_world.gd": 17,   # city r1: _rebuild_items asks Places.is_map instead (two fewer)
}


func test_town_literal_audit() -> void:
	var found := {}
	var dirs := ["res://scripts"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			dirs.append(d + "/" + sub)
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var path := d + "/" + f
			var n := FileAccess.get_file_as_string(path).count("\"town\"")
			if n > 0:
				found[path.trim_prefix("res://")] = n
	for path in found:
		ok(TOWN_LITERALS.has(path) and found[path] <= TOWN_LITERALS[path], "%s has %d \"town\" literals, %d read and allowed" % [path, found[path], TOWN_LITERALS.get(path, 0)])
	for path in TOWN_LITERALS:
		ok(found.get(path, 0) == TOWN_LITERALS[path], "the allowed list is current for %s (%d now, %d listed)" % [path, found.get(path, 0), TOWN_LITERALS[path]])


## Ring the bell (design 10.3): a ring that is accepted always ends with a monkey ringing it, within 25 s,
## and a ring is seldom refused. Found by the zoo tour (r1 integration): a resting monkey blocked the
## climber's path, two monkeys met head-on, and a troop-mate climbed ahead; see the decisions log.
func test_bell_always_rings() -> void:
	var busy := 0
	var late := []
	var slowest := 0.0
	for seed in range(1, 121):
		var b = ZooBrain.new(seed)
		b.spawn()
		for i in int(30.0 / ZooBrain.STEP):
			b.tick([], ZooBrain.STEP)
		var kid := {"id": 1, "pos": ZooMap.STATIONS["monkey_bell"]["pos"] + Vector2(0, 0.8), "emote": "", "emote_t": 0.0, "still": 1.0, "speed": 0.0, "vel": Vector2.ZERO, "run": false}
		if b.use_station("monkey_bell", kid["pos"]) != "":
			busy += 1
			continue
		var rang := -1.0
		for i in int(25.0 / ZooBrain.STEP):
			b.tick([kid], ZooBrain.STEP)
			if b.animals.any(func(a): return a["action"] == "bell"):
				rang = i * ZooBrain.STEP
				break
		if rang < 0.0:
			late.append(seed)
		slowest = maxf(slowest, rang)
	ok(late.is_empty(), "every accepted ring is rung within 25 s (late seeds %s; slowest %.1f s)" % [str(late), slowest])
	ok(busy <= 6, "a ring is seldom refused as busy (%d of 120)" % busy)
	# After a dance at the Court the troop is busy copying, grooming and following (the zoo tour's
	# order; seed 3 once kept the climber behind a grooming monkey on a one-monkey path).
	var late2 := []
	var busy2 := 0
	for seed in range(1, 61):
		var b = ZooBrain.new(seed)
		b.spawn()
		for i in int(20.0 / ZooBrain.STEP):
			b.tick([], ZooBrain.STEP)
		var kid := {"id": 1, "pos": Vector2(29.0, -18.0), "emote": "dance", "emote_t": 0.0, "still": 0.0, "speed": 0.0, "vel": Vector2.ZERO, "run": false}
		for i in int(12.0 / ZooBrain.STEP):
			kid["emote_t"] += ZooBrain.STEP
			if kid["emote_t"] > 3.0:
				kid["emote"] = ""
			b.tick([kid], ZooBrain.STEP)
		kid["pos"] = ZooMap.STATIONS["monkey_bell"]["pos"] + Vector2(0, 1.5)
		for i in int(3.0 / ZooBrain.STEP):
			b.tick([kid], ZooBrain.STEP)
		if b.use_station("monkey_bell", kid["pos"]) != "":
			busy2 += 1
			continue
		var rang := false
		for i in int(25.0 / ZooBrain.STEP):
			b.tick([kid], ZooBrain.STEP)
			if b.animals.any(func(a): return a["action"] == "bell"):
				rang = true
				break
		if not rang:
			late2.append(seed)
	ok(late2.is_empty() and busy2 <= 3, "after a dance, every accepted ring is rung within 25 s (late %s, busy %d of 60)" % [str(late2), busy2])
