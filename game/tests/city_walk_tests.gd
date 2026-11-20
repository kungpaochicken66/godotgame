## The controller's loop against route() and step(): every route between spots walked with fixed strides, as
## play_controller does (aim at the next waypoint, advance within 0.08 m), arriving and never stuck.
## Data-driven: the spots are ARRIVALS, a standing point in every place, and every INTERACTIONS spot.
##   godot --headless --path game -s res://tests/city_walk_tests.gd
extends SceneTree

const N := preload("res://scripts/core/city_nav.gd")
const CityMap := preload("res://scripts/core/city_map.gd")

var _checks := 0
var _failures := 0
var _printed := 0


func _initialize() -> void:
	var spots := _spots()
	print("  ", spots.size(), " spots")
	var t0 := Time.get_ticks_msec()
	_all_pairs(spots, 0.15, 2, 0)
	print("  stride 0.15 ", Time.get_ticks_msec() - t0, " ms")
	_all_pairs(spots, 0.10, 5, 0)
	print("  stride 0.10 ", Time.get_ticks_msec() - t0, " ms")
	_all_pairs(spots, 0.04, 11, 1)
	print("  stride 0.04 ", Time.get_ticks_msec() - t0, " ms")
	_stair_ends()
	_cover_routes()
	print("CITY WALK TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		if _printed < 40:
			_printed += 1
			print("FAIL: ", msg)


func _spots() -> Array:
	var out: Array = []
	for i in CityMap.ARRIVALS.size():
		var a := N.arrival(i)
		out.append({"name": "arrival%d" % i, "region": "", "pos": a["pos"]})
	for id: String in N.place_ids():
		out.append({"name": "place '%s'" % id, "region": id, "pos": N.probe(id)})
	for key: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[key]
		out.append({"name": key, "region": N._rn(String(it["region"])), "pos": it["pos"]})
	return out


## The controller: returns "" when it arrives, else why not.
func _walk(from: Dictionary, to: Dictionary, stride: float) -> String:
	var wps := N.route(from["region"], from["pos"], to["region"], to["pos"])
	if wps.is_empty():
		return "no route"
	var reg: String = from["region"]
	var p: Vector2 = from["pos"]
	var idx := 0
	var stuck := 0
	var steps := 0
	while idx < wps.size():
		var wp: Dictionary = wps[idx]
		var target: Vector2 = wp["pos"]
		var last := idx == wps.size() - 1
		var tol := 0.08
		if p.distance_to(target) <= tol and (not last or String(wp["region"]) == reg):
			idx += 1
			stuck = 0
			continue
		steps += 1
		if steps > 6000:
			return "too long at waypoint %d %s from %s" % [idx, str(wp), str(p)]
		var r := N.step(reg, p, p + (target - p).normalized() * stride)
		var np: Vector2 = r["pos"]
		if String(r["region"]) == reg and np.distance_to(p) < stride * 0.05:
			stuck += 1
			if stuck >= 4:
				return "stuck at %s '%s' going to waypoint %d %s of %d" % [str(p), reg, idx, str(wp), wps.size()]
		else:
			stuck = 0
		reg = r["region"]
		p = np
	var goal: Vector2 = (wps[-1] as Dictionary)["pos"]
	if reg != String(to["region"]) or p.distance_to(goal) > 0.1:
		return "ended at %s '%s', not %s" % [str(p), reg, str(goal)]
	return ""


func _all_pairs(spots: Array, stride: float, every: int, offset: int) -> void:
	var n := 0
	var bad := 0
	for i in spots.size():
		for j in spots.size():
			if i == j:
				continue
			# every route from or to an arrival is walked (the way into every shop and upstairs); the others are sampled
			if i >= CityMap.ARRIVALS.size() and j >= CityMap.ARRIVALS.size() and (i + j) % every != offset % every:
				continue
			n += 1
			var why := _walk(spots[i], spots[j], stride)
			if why != "":
				bad += 1
				_ok(false, "stride %.2f: %s -> %s: %s" % [stride, spots[i]["name"], spots[j]["name"], why])
	_ok(bad == 0 and n > 0, "stride %.2f: %d routes walked, %d failed" % [stride, n, bad])


## Every end of every stair, entered and left from both sides at every stride 0.02 to 0.15.
func _stair_ends() -> void:
	for sid: String in CityMap.STAIRS:
		var ports := N.portals(sid)
		for pt: Dictionary in ports:
			var nb: String = pt["to"]
			var axis: int = pt["axis"]
			var e: float = pt["e"]
			var side: int = pt["side"]
			var lat := (float(pt["lo"]) + float(pt["hi"])) * 0.5
			# the way from the neighbour: a route from 3 m out on the neighbour to the middle of the stair
			var out_c := e + side * 3.0
			var out_p := Vector2(out_c, lat) if axis == 0 else Vector2(lat, out_c)
			var from_pos := N.snap(nb, out_p)
			if from_pos.is_empty():
				continue
			for stride in [0.02, 0.04, 0.1, 0.15]:
				var in_why := _walk({"region": nb, "pos": from_pos["pos"]}, {"region": sid, "pos": N.probe(sid)}, stride)
				_ok(in_why == "", "stair %s end via %s, stride %.2f, in: %s" % [sid, nb, stride, in_why])
				var out_why := _walk({"region": sid, "pos": N.probe(sid)}, {"region": nb, "pos": from_pos["pos"]}, stride)
				_ok(out_why == "", "stair %s end via %s, stride %.2f, out: %s" % [sid, nb, stride, out_why])


## r3: people hurrying to shelter. route() from every walker position and every standing person on the ground
## (who stand inside their own solid) to every cover spot (awnings, bus shelters, the carousel's rim).
func _cover_routes() -> void:
	var covers := N.cover_spots()
	_ok(covers.size() >= 20, "cover spots exist: %d" % covers.size())
	var kinds: Dictionary = {}
	for c: Dictionary in covers:
		kinds[c["kind"]] = true
		_ok(N.allowed(String(c["region"]), c["pos"]), "cover spot %s is standable" % c["id"])
	_ok(kinds.has("awning") and kinds.has("shelter") and kinds.has("canopy"), "awnings, shelters and the canopy all have spots (%s)" % str(kinds.keys()))
	var sources: Array = []
	for i in CityMap.ARRIVALS.size():
		sources.append({"name": "arrival%d" % i, "region": "", "pos": N.arrival(i)["pos"]})
	var Rules := preload("res://scripts/core/city_rules.gd")
	for t in [0.0, 17.3, 53.7, 211.9]:
		for w: Dictionary in Rules.walkers(t):
			sources.append({"name": "walker %d at %.0f s" % [int(w["index"]), t], "region": "", "pos": w["pos"]})
	for ps: Dictionary in N.people_solids():
		if N._rn(String(ps.get("region", ""))) == "":
			sources.append({"name": "person %s" % str(ps.get("id", ps["at"])), "region": "", "pos": ps["at"]})
	var routed := 0
	var walked := 0
	var k := 0
	for src: Dictionary in sources:
		for c: Dictionary in covers:
			var rt := N.route("", src["pos"], "", c["pos"])
			_ok(not rt.is_empty(), "%s can run to %s" % [src["name"], c["id"]])
			routed += 1
			k += 1
			if k % 9 == 0:
				var why := _walk(src, {"name": c["id"], "region": "", "pos": c["pos"]}, 0.1 if k % 2 == 0 else 0.15)
				_ok(why == "", "%s -> %s walked: %s" % [src["name"], c["id"], why])
				walked += 1
	print("  cover routes: %d sources x %d spots, %d walked" % [sources.size(), covers.size(), walked])
