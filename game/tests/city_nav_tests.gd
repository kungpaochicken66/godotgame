## Headless tests for the city's navigation (core/city_nav.gd): reachability, walls and railings,
## stairs, floor-aware picking, and the city camera maths' floors (world/city_orbit.gd has its own file).
##   godot --headless --path game -s res://tests/city_nav_tests.gd
extends SceneTree

const N := preload("res://scripts/core/city_nav.gd")
const CityMap := preload("res://scripts/core/city_map.gd")

var _checks := 0
var _failures := 0
var _printed := 0


func _initialize() -> void:
	for t in ["test_places", "test_reachability", "test_interactions", "test_stairs", "test_edges", "test_walls",
			"test_step_determinism", "test_pick_cutaways", "test_pick_blockers", "test_hidden_storeys", "test_pick_random", "test_carousel_and_people"]:
		var t0 := Time.get_ticks_msec()
		call(t)
		print("  ", t, " ", Time.get_ticks_msec() - t0, " ms, ", _checks, " checks so far")
	print("CITY NAV TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		if _printed < 60:
			_printed += 1
			print("FAIL: ", msg)


# ------------------------------------------------------------------ helpers

## Walk a route with step(): returns {"ok", "region", "pos", "max_dy"}.
func _walk(region: String, pos: Vector2, wps: Array, stride := 0.25) -> Dictionary:
	var reg := region
	var p := pos
	var max_dy := 0.0
	for w: Dictionary in wps:
		var target: Vector2 = w["pos"]
		var guard := 0
		while guard < 1200:
			guard += 1
			if reg == String(w["region"]) and p.distance_to(target) < 0.005:
				break
			var to := p + (target - p).limit_length(stride)
			var h0 := N.height(reg, p)
			var r := N.step(reg, p, to)
			var np: Vector2 = r["pos"]
			if String(r["region"]) == reg and np.distance_to(p) < 1e-9:
				return {"ok": false, "region": reg, "pos": p, "max_dy": max_dy}
			reg = r["region"]
			p = np
			max_dy = maxf(max_dy, absf(N.height(reg, p) - h0))
		if guard >= 1200:
			return {"ok": false, "region": reg, "pos": p, "max_dy": max_dy}
	return {"ok": true, "region": reg, "pos": p, "max_dy": max_dy}


func _allowed_points(region: String, spacing: float) -> Array:
	var out: Array = []
	var r := N.place_rect(region)
	var x := r.position.x + 0.2
	while x < r.end.x:
		var z := r.position.y + 0.2
		while z < r.end.y:
			if N.allowed(region, Vector2(x, z)):
				out.append(Vector2(x, z))
			z += spacing
		x += spacing
	return out


# ------------------------------------------------------------------ tests

func test_places() -> void:
	var ids := N.place_ids()
	_ok(ids.size() == 1 + CityMap.REGIONS.size() + CityMap.STAIRS.size(), "places: ground + regions + stairs")
	_ok(N.has_place("ground") and N.has_place(""), "ground is both '' and 'ground'")
	for id: String in ids:
		var pr := N.probe(id)
		_ok(N.allowed(id, pr), "probe of '%s' is standable" % id)
	# every stair has two connected ends, every door two, every region at least one portal
	for id: String in CityMap.STAIRS:
		_ok(N.portals(id).size() == 2, "stair %s has exactly two portals (ends), got %d" % [id, N.portals(id).size()])
	for id: String in CityMap.REGIONS:
		var n := N.portals(id).size()
		_ok(n >= 1, "region %s has a portal" % id)
		if String((CityMap.REGIONS[id] as Dictionary)["kind"]) == "door":
			_ok(n == 2, "door %s bridges: two portals, got %d" % [id, n])
	# arrivals are standable and distinct
	for i in CityMap.ARRIVALS.size():
		var a := N.arrival(i)
		_ok(N.allowed("", a["pos"]) and a["pos"].distance_to(CityMap.ARRIVALS[i]) < 0.01, "arrival %d standable and unmoved" % i)
	_ok(N.arrival(CityMap.ARRIVALS.size())["pos"] == N.arrival(0)["pos"], "arrival slots wrap")
	# heights
	_ok(is_equal_approx(N.height("", Vector2(0, 0)), 0.0), "ground height 0")
	_ok(is_equal_approx(N.height("office_l1", Vector2(-17, -7)), 3.2), "region height")
	for id: String in CityMap.STAIRS:
		var s: Dictionary = CityMap.STAIRS[id]
		var up: String = s["up"]
		var r: Rect2 = s["rect"]
		var hi_pt := Vector2(r.get_center().x, r.position.y) if up == "-z" else Vector2(r.get_center().x, r.end.y)
		var lo_pt := Vector2(r.get_center().x, r.end.y) if up == "-z" else Vector2(r.get_center().x, r.position.y)
		_ok(is_equal_approx(N.height(id, hi_pt), float(s["y1"])) and is_equal_approx(N.height(id, lo_pt), float(s["y0"])), "stair %s end heights" % id)
		_ok(is_equal_approx(N.height(id, r.get_center()), (float(s["y0"]) + float(s["y1"])) * 0.5), "stair %s midpoint" % id)


func test_reachability() -> void:
	var from_arrival := N.reachable("", Vector2.ZERO)
	for id: String in N.place_ids():
		_ok(from_arrival.has(id), "graph: '%s' reachable from the ground" % id)
		var from_there := N.reachable(id)
		_ok(from_there.has(""), "graph: ground reachable from '%s'" % id)
	for slot in CityMap.ARRIVALS.size():
		var a := N.arrival(slot)
		for id: String in N.place_ids():
			var target := N.probe(id)
			var there := N.route("", a["pos"], id, target)
			_ok(not there.is_empty(), "route arrival %d -> %s exists" % [slot, id])
			if there.is_empty():
				continue
			var w := _walk("", a["pos"], there)
			_ok(bool(w["ok"]) and String(w["region"]) == id and (w["pos"] as Vector2).distance_to(target) < 0.02, "walking arrival %d -> %s arrives (%s %s)" % [slot, id, w["region"], w["pos"]])
			_ok(float(w["max_dy"]) < 0.2, "walking arrival %d -> %s has no height jump (%.2f)" % [slot, id, w["max_dy"]])
			var back := N.route(id, target, "", a["pos"])
			_ok(not back.is_empty(), "route %s -> arrival %d exists" % [id, slot])
			if back.is_empty():
				continue
			var w2 := _walk(id, target, back)
			_ok(bool(w2["ok"]) and String(w2["region"]) == "" and (w2["pos"] as Vector2).distance_to(a["pos"]) < 0.02, "walking %s -> arrival %d arrives" % [id, slot])
	# a tap inside an obstacle snaps to a standable place, a tap on a wall too
	var r := N.route("", N.arrival(0)["pos"], "", Vector2(-20.0, 0.5))
	_ok(not r.is_empty() and N.allowed("", (r[-1] as Dictionary)["pos"]), "a tap on a tree walks to the nearest free spot")
	_ok(N.route("nowhere", Vector2.ZERO, "", Vector2.ZERO).is_empty(), "unknown region: no route")
	_ok(N.route("", N.arrival(0)["pos"], "", N.arrival(0)["pos"]).size() == 1, "already there: just the goal")


func test_interactions() -> void:
	var a := N.arrival(0)
	for key: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[key]
		var reg: String = it["region"]
		var pos: Vector2 = it["pos"]
		var s := N.snap(reg, pos)
		_ok(not s.is_empty(), "interaction %s has a standing place" % key)
		if s.is_empty():
			continue
		# the action button must be offered when standing at the snapped place
		_ok((s["pos"] as Vector2).distance_to(pos) <= CityMap.REACH - 0.2, "interaction %s: nearest standing place is %.2f m away (REACH %.1f)" % [key, (s["pos"] as Vector2).distance_to(pos), CityMap.REACH])
		var rt := N.route("", a["pos"], reg, pos)
		_ok(not rt.is_empty(), "interaction %s reachable" % key)
		if rt.is_empty():
			continue
		var w := _walk("", a["pos"], rt)
		_ok(bool(w["ok"]) and (w["pos"] as Vector2).distance_to(pos) <= CityMap.REACH - 0.2 and String(w["region"]) == N._rn(reg), "walking to interaction %s arrives within REACH" % key)
	# somebody sitting inside a footprint is let out toward the nearest free spot
	var out := N.step("", Vector2(9.5, -12.3), Vector2(9.5, -12.3) + Vector2(0.0, 1.0))
	_ok(N.allowed("", out["pos"]) or (out["pos"] as Vector2).distance_to(Vector2(9.5, -12.3)) > 0.5, "a child inside a treadmill moves out")


func test_stairs() -> void:
	for id: String in CityMap.STAIRS:
		var s: Dictionary = CityMap.STAIRS[id]
		var r: Rect2 = s["rect"]
		var up: String = s["up"]
		var portals := N.portals(id)
		var lo_to := ""
		var hi_to := ""
		for p: Dictionary in portals:
			# side points toward the neighbour; the high end is on the "up" side
			var high := (int(p["side"]) < 0) if up == "-z" else (int(p["side"]) > 0)
			if high:
				hi_to = p["to"]
			else:
				lo_to = p["to"]
		var lo_region := lo_to
		var hi_region := hi_to
		_ok(N.has_place(lo_region) and N.has_place(hi_region), "stair %s ends lead somewhere (%s, %s)" % [id, lo_to, hi_to])
		_ok(absf(N.height(lo_region, N.probe(lo_region)) - float(s["y0"])) < 0.01 and absf(N.height(hi_region, N.probe(hi_region)) - float(s["y1"])) < 0.01, "stair %s joins the heights of its ends" % id)
		# climb: start 1.2 m below the low end on its centre line, walk to 1.2 m beyond the high end
		var cx := r.get_center().x
		var dir_z := -1.0 if up == "-z" else 1.0
		var start_z := (r.end.y + 0.6) if up == "-z" else (r.position.y - 0.6)
		var start := Vector2(cx, start_z)
		var reg := lo_region
		_ok(N.allowed(reg, start), "stair %s: start point below the foot is standable" % id)
		var p := start
		var last_h := N.height(reg, p)
		var seq: Array = [reg]
		var monotone := true
		for i in 120:
			var r2 := N.step(reg, p, p + Vector2(0.0, dir_z * 0.1))
			if String(r2["region"]) != reg:
				seq.append(String(r2["region"]))
			reg = r2["region"]
			p = r2["pos"]
			var h := N.height(reg, p)
			if h < last_h - 1e-6:
				monotone = false
			last_h = h
		_ok(monotone, "stair %s climbs monotonically" % id)
		_ok(seq.size() == 3 and seq[1] == id and seq[2] == hi_region, "stair %s: low end, stair, high end (%s)" % [id, str(seq)])
		_ok(absf(last_h - float(s["y1"])) < 0.01, "stair %s ends at the upper height (%.2f)" % [id, last_h])
		# and back down
		var seq2: Array = [reg]
		var mono2 := true
		last_h = N.height(reg, p)
		for i in 120:
			var r3 := N.step(reg, p, p + Vector2(0.0, -dir_z * 0.1))
			if String(r3["region"]) != reg:
				seq2.append(String(r3["region"]))
			reg = r3["region"]
			p = r3["pos"]
			var h2 := N.height(reg, p)
			if h2 > last_h + 1e-6:
				mono2 = false
			last_h = h2
		# (the walk goes on past the foot: only the first three places matter)
		_ok(mono2 and seq2.size() >= 3 and seq2[1] == id and seq2[2] == lo_region, "stair %s descends back to the foot (%s)" % [id, str(seq2)])
		# the long sides are railings: walking sideways from the middle stops R inside
		for sx in [-1.0, 1.0]:
			var mid := r.get_center()
			var r4 := N.step(id, mid, mid + Vector2(sx * 3.0, 0.0))
			var lim := N.R
			_ok(String(r4["region"]) == id and absf((r4["pos"] as Vector2).x - (r.position.x + lim if sx < 0.0 else r.end.x - lim)) < 0.02, "stair %s railing stops at R (x %.2f)" % [id, (r4["pos"] as Vector2).x])
		# the foot on the ground is solid: nobody walks under the stair
		if lo_region == "":
			_ok(not N.allowed("", r.get_center()), "stair %s: its footprint is solid on the ground" % id)


func test_edges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	for id: String in N.place_ids():
		var rect := N.place_rect(id)
		var pl := N.portals(id)
		var is_ground := id == ""
		var pts := _allowed_points(id, 8.0 if is_ground else 2.6)
		var bad := 0
		var walks := 0
		for p0: Vector2 in pts:
			for k in (12 if is_ground else 12):
				var ang := TAU * float(k) / float(12 if is_ground else 12) + rng.randf() * 0.2
				var dir := Vector2(cos(ang), sin(ang))
				var reg := id
				var p := p0
				for i in 70:
					var r := N.step(reg, p, p + dir * 0.25)
					var prev_reg := reg
					var prev_p := p
					reg = r["region"]
					p = r["pos"]
					var cur_rect := N.place_rect(reg)
					if not cur_rect.grow(0.001).has_point(p) and not (p.x <= cur_rect.end.x + 0.001 and p.y <= cur_rect.end.y + 0.001 and p.x >= cur_rect.position.x - 0.001 and p.y >= cur_rect.position.y - 0.001):
						bad += 1
					if not N.allowed(reg, p):
						bad += 1
						print("  not allowed ", reg, p, " from ", prev_reg, prev_p, " start ", p0, " dir ", dir)
					if reg != prev_reg:
						# only through a portal: its edge, within its range
						var legit := false
						for q: Dictionary in N.portals(prev_reg):
							if q["to"] == reg:
								var axis: int = q["axis"]
								var along: float = p[1 - axis]
								if along >= float(q["lo"]) - 1e-3 and along <= float(q["hi"]) + 1e-3 and absf(p[axis] - float(q["e"])) < 0.45 and absf(prev_p[axis] - float(q["e"])) < 0.45:
									legit = true
						if not legit:
							bad += 1
							print("  bad crossing ", prev_reg, prev_p, " -> ", reg, p)
					# raw obstacles: never inside a ground wall or solid, never inside a hole
					if reg == "":
						for w: Rect2 in CityMap.GROUND_WALLS:
							if p.x > w.position.x + 0.001 and p.x < w.end.x - 0.001 and p.y > w.position.y + 0.001 and p.y < w.end.y - 0.001:
								bad += 1
						for sd: Dictionary in CityMap.GROUND_SOLIDS:
							if sd.has("rect"):
								var rr: Rect2 = sd["rect"]
								if p.x > rr.position.x + 0.001 and p.x < rr.end.x - 0.001 and p.y > rr.position.y + 0.001 and p.y < rr.end.y - 0.001:
									bad += 1
							elif p.distance_to(sd["at"]) < float(sd["r"]) - 0.001:
								bad += 1
					elif CityMap.REGIONS.has(reg):
						for h: Rect2 in (CityMap.REGIONS[reg] as Dictionary)["holes"]:
							if p.x > h.position.x + 0.001 and p.x < h.end.x - 0.001 and p.y > h.position.y + 0.001 and p.y < h.end.y - 0.001:
								bad += 1
				walks += 1
		_ok(bad == 0, "free walks on '%s': %d walks, %d violations (pass-through, off an edge, or a bad crossing)" % [id, walks, bad])
	# straight at every non-portal edge of every upper place: stops R short, same region
	for id: String in N.place_ids():
		if id == "" or String((CityMap.REGIONS.get(id, {"kind": ""}) as Dictionary)["kind"]) == "door":
			continue
		var rect := N.place_rect(id)
		var pl := N.portals(id)
		var stopped := 0
		var wrong := 0
		for side in 4:
			var axis := 0 if side < 2 else 1
			var sign_out := 1.0 if side % 2 == 1 else -1.0
			var edge := (rect.end[axis] if sign_out > 0.0 else rect.position[axis])
			var lat0: float = rect.position[1 - axis]
			var lat1: float = rect.end[1 - axis]
			var u := lat0 + 0.4
			while u < lat1 - 0.3:
				var in_portal := false
				for q: Dictionary in pl:
					if int(q["axis"]) == axis and absf(float(q["e"]) - edge) < 0.02 and u > float(q["lo"]) - 0.35 and u < float(q["hi"]) + 0.35:
						in_portal = true
				if not in_portal:
					var start := Vector2(edge - sign_out * 0.8, u) if axis == 0 else Vector2(u, edge - sign_out * 0.8)
					if N.allowed(id, start):
						var tgt := start + (Vector2(sign_out, 0.0) if axis == 0 else Vector2(0.0, sign_out)) * 3.0
						var r := N.step(id, start, tgt)
						var d := absf(edge - float((r["pos"] as Vector2)[axis]))
						if String(r["region"]) == id and d >= N.R - 0.02:
							stopped += 1
						else:
							wrong += 1
				u += 0.5
		_ok(wrong == 0, "place %s: %d straight walks at its edges stopped, %d did not" % [id, stopped, wrong])


func test_walls() -> void:
	var stopped := 0
	var wrong := 0
	for w: Rect2 in CityMap.GROUND_WALLS:
		var along_z := w.size.y > w.size.x
		var lo := w.position.y if along_z else w.position.x
		var hi := w.end.y if along_z else w.end.x
		var u := lo + 0.5
		while u < hi - 0.4:
			for side in [-1.0, 1.0]:
				var base := (w.get_center().x if along_z else w.get_center().y)
				var start := Vector2(base + side * 1.5, u) if along_z else Vector2(u, base + side * 1.5)
				if not N.allowed("", start):
					continue
				var dirv := Vector2(-side, 0.0) if along_z else Vector2(0.0, -side)
				var cur := start
				var reg := ""
				for i in 20:
					var r := N.step(reg, cur, cur + dirv * 0.3)
					cur = r["pos"]
				var d := absf(cur.x - w.get_center().x) if along_z else absf(cur.y - w.get_center().y)
				var inside := cur.x > w.position.x + 0.001 and cur.x < w.end.x - 0.001 and cur.y > w.position.y + 0.001 and cur.y < w.end.y - 0.001
				if inside or d < w.size[0 if along_z else 1] * 0.5 + N.R - 0.02:
					wrong += 1
				else:
					stopped += 1
			u += 0.7
	_ok(wrong == 0 and stopped > 40, "walls: %d walks stopped R from the wall, %d passed or stuck inside" % [stopped, wrong])
	# solids and furniture on the ground block as well
	var bad := 0
	var n := 0
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		var c := Vector2.ZERO
		var rr := Rect2()
		if sd.has("rect"):
			rr = sd["rect"]
			c = rr.get_center()
		else:
			c = sd["at"]
			rr = Rect2(c - Vector2(float(sd["r"]), float(sd["r"])), Vector2(float(sd["r"]), float(sd["r"])) * 2.0)
		var start := Vector2(c.x, rr.end.y + 1.0)
		if sd["kind"] == "stair_base" or not N.allowed("", start):
			continue
		var cur := start
		for i in 20:
			cur = N.step("", cur, cur + Vector2(0.0, -0.3))["pos"]
		n += 1
		if cur.y < rr.end.y + N.R - 0.02 and absf(cur.x - c.x) < rr.size.x * 0.5 + 0.01:
			bad += 1
	_ok(bad == 0 and n > 10, "solids stop a straight walk (%d walks, %d passed)" % [n, bad])


func test_step_determinism() -> void:
	var a := N.step("", Vector2(-20, 0), Vector2(-12, 6))
	var b := N.step("", Vector2(-20, 0), Vector2(-12, 6))
	_ok(a["pos"] == b["pos"] and a["region"] == b["region"], "step is deterministic")
	var r1 := N.route("", N.arrival(1)["pos"], "gym_roof", Vector2(13, -8.5))
	var r2 := N.route("", N.arrival(1)["pos"], "gym_roof", Vector2(13, -8.5))
	_ok(r1 == r2 and not r1.is_empty(), "route is deterministic")
	# a long step equals the same distance in many small ones
	var p := Vector2(-20.0, 5.0)
	var one := N.step("", p, p + Vector2(8.0, 0.0))["pos"] as Vector2
	var q := p
	for i in 16:
		q = N.step("", q, q + Vector2(0.5, 0.0))["pos"]
	_ok(one.distance_to(q) < 0.01, "one long step equals many short ones")


## A camera ray at a target: from `yaw` / `pitch`, aimed at `target`.
func _ray(target: Vector3, yaw: float, pitch: float) -> Array:
	var dir := -Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return [target - dir * 60.0, dir]


func test_pick_cutaways() -> void:
	var pitch := deg_to_rad(50.0)
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		var rect: Rect2 = b["rect"]
		var floors: Array = b["floors"]
		# the region at each floor height of this building
		for fy: float in floors:
			var reg := ""
			if fy > 0.0:
				for id: String in CityMap.REGIONS:
					var rd: Dictionary = CityMap.REGIONS[id]
					if rd["building"] == bid and absf(float(rd["y"]) - fy) < 0.01 and rd["kind"] == "floor":
						reg = id
				if reg == "":
					_ok(false, "building %s floor %.1f has a region" % [bid, fy])
					continue
			var depth := 0.8
			var x := rect.get_center().x
			var z := rect.end.y - depth
			# shallow: the floor above does not cover the ray (nothing hidden); deeper: needs the child inside
			var ry := _ray(Vector3(x, fy, z), 0.0, pitch)
			var hit := N.pick(ry[0], ry[1])
			_ok(not hit.is_empty() and hit["region"] == reg and (hit["pos"] as Vector2).distance_to(Vector2(x, z)) < 0.05, "%s: a pick through the open face lands on floor %.1f (%s)" % [bid, fy, str(hit)])
			# deep, with a child on that floor (the storeys above hidden)
			var zd := rect.end.y - 4.5
			var hide := N.storeys_hidden(reg, Vector2(x, zd))
			var ry2 := _ray(Vector3(x, fy, zd), 0.0, pitch)
			var hit2 := N.pick(ry2[0], ry2[1], hide)
			_ok(not hit2.is_empty() and hit2["region"] == reg and (hit2["pos"] as Vector2).distance_to(Vector2(x, zd)) < 0.05, "%s: with the storeys above hidden, a deep pick lands on floor %.1f (%s)" % [bid, fy, str(hit2)])
			if fy > 0.0 or floors.size() > 1:
				# without hiding, the same deep pick must not return a floor BELOW the visible one or a hole in the stack
				var hit3 := N.pick(ry2[0], ry2[1])
				var not_below := hit3.is_empty() or N.height(hit3["region"], hit3["pos"]) >= fy - 0.01
				_ok(not_below, "%s: an unhidden deep pick is blocked or lands on a floor at or above (never below) %.1f (%s)" % [bid, fy, str(hit3)])
		# the roof terrace: a pick from above returns the terrace
		if b.has("roof_terrace"):
			var tid: String = b["roof_terrace"]
			var tr: Rect2 = (CityMap.REGIONS[tid] as Dictionary)["rect"]
			var ty: float = (CityMap.REGIONS[tid] as Dictionary)["y"]
			var tp := Vector3(tr.get_center().x, ty, tr.get_center().y + 1.0)
			var rt := _ray(tp, 0.0, pitch)
			var th := N.pick(rt[0], rt[1])
			_ok(not th.is_empty() and th["region"] == tid, "%s: a pick on the roof terrace lands on it (%s)" % [bid, str(th)])


func test_pick_blockers() -> void:
	var pitch := deg_to_rad(50.0)
	# roofs: nothing walkable behind them
	for oc: Dictionary in CityMap.OCCLUDERS:
		var r: Rect2 = oc["rect"]
		var y: float = oc["y"]
		for k in 5:
			var p := Vector3(r.position.x + r.size.x * (0.15 + 0.17 * k), y, r.position.y + r.size.y * 0.5)
			for yaw in [0.0, 0.5, -0.7]:
				var rr := _ray(p, yaw, pitch)
				var hit := N.pick(rr[0], rr[1])
				_ok(hit.is_empty(), "roof %s at %s from yaw %.1f: nothing behind it (%s)" % [oc["name"], str(p), yaw, str(hit)])
	# the underside of a floor: a ray going up from below
	var up_hit := N.pick(Vector3(-17.0, 1.0, -7.0), Vector3(0.0, 1.0, 0.0))
	_ok(up_hit.is_empty(), "a ray from the ground floor up into a floor's underside picks nothing")
	var up2 := N.pick(Vector3(-17.0, 1.0, -7.0), Vector3(0.0, 0.7, -0.7).normalized())
	_ok(up2.is_empty() or up2["region"] == "", "a ray going up never returns an upper floor")
	# skywalks: a pick where the skywalk covers the ray returns the skywalk; beside it, the ground
	var cover := _ray(Vector3(-9.0, 0.0, -13.0), 0.0, deg_to_rad(45.0))
	var h1 := N.pick(cover[0], cover[1])
	_ok(not h1.is_empty() and h1["region"] == "skywalk_a", "ground under the skywalk's shadow: the skywalk is hit, never the ground (%s)" % str(h1))
	var clear := _ray(Vector3(-9.0, 0.0, -5.0), 0.0, deg_to_rad(45.0))
	var h2 := N.pick(clear[0], clear[1])
	_ok(not h2.is_empty() and h2["region"] == "" and (h2["pos"] as Vector2).distance_to(Vector2(-9.0, -5.0)) < 0.05, "ground where the skywalk does not cover the ray still picks (%s)" % str(h2))
	var ground_far := _ray(Vector3(12.0, 0.0, 12.0), 0.3, pitch)
	var h3 := N.pick(ground_far[0], ground_far[1])
	_ok(not h3.is_empty() and h3["region"] == "" and (h3["pos"] as Vector2).distance_to(Vector2(12.0, 12.0)) < 0.05, "open ground picks")
	# a stair
	var sp := Vector3(-10.0, N.height("st_office", Vector2(-10.0, -6.0)), -6.0)
	var sr := _ray(sp, 0.0, pitch)
	var sh := N.pick(sr[0], sr[1])
	_ok(not sh.is_empty() and sh["region"] == "st_office" and (sh["pos"] as Vector2).distance_to(Vector2(-10.0, -6.0)) < 0.05, "a stair's slope picks (%s)" % str(sh))
	# outside the map: nothing
	var off := N.pick(Vector3(100.0, 50.0, 0.0), Vector3(0.0, -1.0, 0.0))
	_ok(off.is_empty(), "a ray that lands outside the map picks nothing")
	# walls hide the interior from a camera on the far side; the open face and the child inside do not
	var wr := _ray(Vector3(-2.0, 0.0, -8.0), PI, deg_to_rad(30.0))
	_ok(N.pick(wr[0], wr[1]).is_empty(), "the cafe's back wall blocks a tap on its floor from the north")
	var hide := N.storeys_hidden("", Vector2(-2.0, -8.0))
	_ok(hide.has("cafe"), "a child on the cafe floor hides the cafe's storeys")
	var wh := N.pick(wr[0], wr[1], hide)
	_ok(wh.is_empty(), "with the child inside, the cafe's own wall still blocks a tap from the north (drawn as the art draws it)")
	var open := _ray(Vector3(-2.0, 0.0, -8.0), 0.0, deg_to_rad(40.0))
	var oh := N.pick(open[0], open[1], hide)
	_ok(not oh.is_empty() and oh["region"] == "", "...while the open face still lets the same tap through (%s)" % str(oh))
	# the doorway lets a tap through to the door's floor
	var dr := _ray(Vector3(-11.15, 3.2, -10.0), PI * 0.5, deg_to_rad(25.0))
	var dh := N.pick(dr[0], dr[1])
	_ok(not dh.is_empty() and dh["region"] == "office_door_l1", "a tap through the office doorway lands on the door's floor (%s)" % str(dh))
	# hidden floors do not block: a child on the office ground floor sees the ground through the cutaway
	var tall := _ray(Vector3(-17.0, 0.0, -9.0), 0.0, deg_to_rad(65.0))
	var seen := N.pick(tall[0], tall[1], N.storeys_hidden("", Vector2(-17.0, -9.0)))
	_ok(not seen.is_empty() and seen["region"] == "", "office ground floor taps with the storeys above hidden (%s)" % str(seen))
	var unseen := N.pick(tall[0], tall[1])
	_ok(unseen.is_empty() or unseen["region"] != "", "the same tap without hiding does not click through the roof/floors (%s)" % str(unseen))


# A reference picker: marches the ray in small steps over the raw map data.
func _ref_pick(o: Vector3, d: Vector3, hide: Dictionary) -> Dictionary:
	var step := 0.05
	var t_start := maxf(0.0, (o.y - 14.0) / -d.y) if d.y < 0.0 else 0.0
	var prev := o + d * t_start
	var n := int(120.0 / step)
	for i in range(1, n):
		var p := o + d * (t_start + step * float(i))
		var hit := _ref_event(prev, p, hide)
		if hit.has("kind"):
			return hit.get("result", {})
		prev = p
	return {}


func _ref_event(a: Vector3, b: Vector3, hide: Dictionary) -> Dictionary:
	# ground
	if a.y > 0.0 and b.y <= 0.0:
		var t := a.y / (a.y - b.y)
		var p := a.lerp(b, t)
		if absf(p.x) <= CityMap.HALF.x and absf(p.z) <= CityMap.HALF.y:
			return {"kind": "ground", "result": {"region": "", "pos": Vector2(p.x, p.z)}}
		return {"kind": "void", "result": {}}
	for id: String in CityMap.REGIONS:
		var rd: Dictionary = CityMap.REGIONS[id]
		var bid: String = rd["building"]
		if bid != "" and hide.has(bid) and float(rd["y"]) > float(hide[bid]) + 0.05:
			continue
		var r: Rect2 = rd["rect"]
		var y: float = rd["y"]
		var ina := _in_box(r, rd["holes"], y - 0.2, y, a)
		var inb := _in_box(r, rd["holes"], y - 0.2, y, b)
		if inb and not ina and not _in_holes_zone(r, rd["holes"], y - 0.2, y, a):
			if a.y > y and b.y <= y:
				var t2 := (a.y - y) / (a.y - b.y)
				var p2 := a.lerp(b, t2)
				return {"kind": "top", "result": {"region": id, "pos": Vector2(p2.x, p2.z)}}
			return {"kind": "block", "result": {}}
	for id: String in CityMap.STAIRS:
		var sd: Dictionary = CityMap.STAIRS[id]
		var sb: String = sd["building"]
		if sb != "" and hide.has(sb) and float(sd["y0"]) > float(hide[sb]) + 0.05:
			continue
		var r: Rect2 = sd["rect"]
		var ina := _in_stair(sd, a)
		var inb := _in_stair(sd, b)
		if inb and not ina:
			var above := a.y > _stair_y(sd, a) and b.y <= _stair_y(sd, b)
			if above:
				var ya := a.y - _stair_y(sd, a)
				var yb := b.y - _stair_y(sd, b)
				var p3 := a.lerp(b, ya / (ya - yb))
				return {"kind": "top", "result": {"region": id, "pos": Vector2(p3.x, p3.z)}}
			return {"kind": "block", "result": {}}
	for oc: Dictionary in CityMap.OCCLUDERS:
		var skip := false
		for bid2: String in CityMap.BUILDINGS:
			var bb: Dictionary = CityMap.BUILDINGS[bid2]
			if hide.has(bid2) and float(oc["y"]) > float(hide[bid2]) + 0.05 and (oc["rect"] as Rect2).intersects(bb["rect"]) and absf(float(bb["roof"]) - float(oc["y"])) < 0.3:
				skip = true
		if skip:
			continue
		var y2: float = oc["y"]
		if _in_box(oc["rect"], [], y2 - 0.2, y2, b) and not _in_box(oc["rect"], [], y2 - 0.2, y2, a):
			return {"kind": "block", "result": {}}
	for w: Rect2 in CityMap.GROUND_WALLS:
		var owners: Array = []
		for bid3: String in CityMap.BUILDINGS:
			if ((CityMap.BUILDINGS[bid3] as Dictionary)["rect"] as Rect2).grow(0.2).encloses(w):
				owners.append(bid3)
		var spans: Array = []
		if owners.is_empty():
			spans.append([0.0, 3.2, ""])
		else:
			var bd: Dictionary = CityMap.BUILDINGS[owners[0]]
			var fl: Array = bd["floors"]
			for k in fl.size():
				var shown := false
				for ob: String in owners:
					if not (hide.has(ob) and float(fl[k]) > float(hide[ob]) + 0.05):
						shown = true
				if shown:
					spans.append([float(fl[k]), float(fl[k + 1]) if k + 1 < fl.size() else float(bd["roof"]), String(owners[0])])
		for sp: Array in spans:
			if _in_wall(w, float(sp[0]), float(sp[1]), String(sp[2]), b) and not _in_wall(w, float(sp[0]), float(sp[1]), String(sp[2]), a):
				return {"kind": "block", "result": {}}
	return {}


func _in_box(r: Rect2, holes: Array, y0: float, y1: float, p: Vector3) -> bool:
	if p.y < y0 or p.y > y1:
		return false
	if p.x < r.position.x or p.x > r.end.x or p.z < r.position.y or p.z > r.end.y:
		return false
	for h: Rect2 in holes:
		if p.x > h.position.x and p.x < h.end.x and p.z > h.position.y and p.z < h.end.y:
			return false
	return true


func _in_holes_zone(r: Rect2, holes: Array, y0: float, y1: float, p: Vector3) -> bool:
	if p.y < y0 or p.y > y1:
		return false
	for h: Rect2 in holes:
		if p.x > h.position.x and p.x < h.end.x and p.z > h.position.y and p.z < h.end.y:
			return true
	return false


func _in_wall(w: Rect2, base: float, top: float, building: String, p: Vector3) -> bool:
	if p.y < base or p.y > top or p.x < w.position.x or p.x > w.end.x or p.z < w.position.y or p.z > w.end.y:
		return false
	for id: String in CityMap.REGIONS:
		var rd: Dictionary = CityMap.REGIONS[id]
		if rd["kind"] == "door" and rd["building"] == building:
			var y: float = rd["y"]
			if (rd["rect"] as Rect2).grow(0.02).has_point(Vector2(p.x, p.z)) and p.y >= y - 0.02 and p.y <= y + 2.4:
				return false
	return true


func _stair_y(sd: Dictionary, p: Vector3) -> float:
	var r: Rect2 = sd["rect"]
	var t := 0.0
	match String(sd["up"]):
		"-z":
			t = (r.end.y - p.z) / r.size.y
		"+z":
			t = (p.z - r.position.y) / r.size.y
		"-x":
			t = (r.end.x - p.x) / r.size.x
		_:
			t = (p.x - r.position.x) / r.size.x
	return lerpf(float(sd["y0"]), float(sd["y1"]), clampf(t, 0.0, 1.0))


func _in_stair(sd: Dictionary, p: Vector3) -> bool:
	var r: Rect2 = sd["rect"]
	if p.x < r.position.x or p.x > r.end.x or p.z < r.position.y or p.z > r.end.y:
		return false
	var y := _stair_y(sd, p)
	return p.y <= y and p.y >= y - 0.2


func test_pick_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 97531
	var mism := 0
	var total := 0
	var kinds := {"": 0, "empty": 0, "upper": 0}
	for i in 160:
		var yaw := rng.randf_range(-PI, PI)
		var pitch := rng.randf_range(deg_to_rad(25.0), deg_to_rad(70.0))
		var target := Vector3(rng.randf_range(-34.0, 34.0), rng.randf_range(0.0, 7.0), rng.randf_range(-26.0, 26.0))
		var rr := _ray(target, yaw, pitch)
		var hide: Dictionary = {}
		if i % 3 == 0:
			hide = N.storeys_hidden("", Vector2(target.x, target.z))
		elif i % 3 == 1:
			hide = {"office": 3.2, "gym": 3.2} if i % 2 == 0 else {"office": 6.4, "gym": 0.0, "cafe": 3.2}
		var got := N.pick(rr[0], rr[1], hide)
		var want := _ref_pick(rr[0], rr[1], hide)
		total += 1
		var same := false
		if got.is_empty() and want.is_empty():
			same = true
			kinds["empty"] = int(kinds["empty"]) + 1
		elif not got.is_empty() and not want.is_empty() and got["region"] == want["region"] and (got["pos"] as Vector2).distance_to(want["pos"]) < 0.06:
			same = true
			kinds["upper" if got["region"] != "" else ""] = int(kinds["upper" if got["region"] != "" else ""]) + 1
		if not same:
			mism += 1
			if mism <= 5:
				print("  pick mismatch: ray ", rr[0], " ", rr[1], " hide ", hide, " nav ", got, " ref ", want)
	_ok(mism == 0, "random rays: nav.pick equals the marched reference (%d of %d differ)" % [mism, total])
	_ok(int(kinds["upper"]) > 8 and int(kinds[""]) > 30 and int(kinds["empty"]) > 10, "random rays cover ground, upper floors and blocked picks (%s)" % str(kinds))



## (a) interior stairs belong to the storey they start from; (b) only the walls of hidden storeys vanish.
func test_hidden_storeys() -> void:
	# storeys_hidden for the stairs
	_ok(N.storeys_hidden("st_office", Vector2(-10.0, -6.0)).is_empty(), "an exterior stair hides nothing")
	_ok(N.storeys_hidden("st_gym", Vector2(6.0, -6.0)).is_empty(), "the gym's exterior stair hides nothing")
	var h2 := N.storeys_hidden("st_office2", Vector2(-12.3, -6.5))
	_ok(h2.has("office") and is_equal_approx(float(h2["office"]), 6.4), "on the interior office stair the upper end stays drawn (%s)" % str(h2))
	_ok(N.storeys_hidden("st_gym2", Vector2(17.9, -7.0)).has("gym"), "on the interior gym stair the gym is in the map")
	var pitch := deg_to_rad(55.0)
	# a stair of storey 3.2 (st_office2: y 3.2 to 6.4) is picked when visible, ignored when hidden
	var mid := Vector2(-12.3, -6.5)
	var sy := N.height("st_office2", mid)
	var sray := _ray(Vector3(mid.x, sy, mid.y), 0.0, pitch)
	var seen := N.pick(sray[0], sray[1], {"office": 6.4})
	_ok(not seen.is_empty() and seen["region"] == "st_office2", "storey 3.2 visible: its stair picks (%s)" % str(seen))
	var hidden_pick := N.pick(sray[0], sray[1], {"office": 0.0})
	_ok(hidden_pick.is_empty() or hidden_pick["region"] != "st_office2", "storey 3.2 hidden (child on the ground floor): the stair is not picked (%s)" % str(hidden_pick))
	# ...and does not block: a ray from the front through the stair's place to the ground floor behind it
	var base := Vector2(-12.3, -7.5)
	var gray := _ray(Vector3(base.x, 0.0, base.y), 0.0, deg_to_rad(65.0))
	var g1 := N.pick(gray[0], gray[1], {"office": 0.0})
	_ok(not g1.is_empty() and g1["region"] == "" and (g1["pos"] as Vector2).distance_to(base) < 0.05, "with the stair's storey hidden the ground floor under it can be tapped (%s)" % str(g1))
	var g2 := N.pick(gray[0], gray[1])
	_ok(g2.is_empty() or g2["region"] != "", "without hiding, the same tap lands on a floor above, never through it (%s)" % str(g2))
	# the gym's interior stair, same rule
	var gm := Vector2(17.9, -7.0)
	var gy := N.height("st_gym2", gm)
	var gr := _ray(Vector3(gm.x, gy, gm.y), 0.0, pitch)
	var gv := N.pick(gr[0], gr[1], {"gym": 6.4})
	_ok(not gv.is_empty() and gv["region"] == "st_gym2", "gym storey 3.2 visible: its stair picks (%s)" % str(gv))
	var gh := N.pick(gr[0], gr[1], {"gym": 0.0})
	_ok(gh.is_empty() or gh["region"] != "st_gym2", "gym storey 3.2 hidden: not picked (%s)" % str(gh))
	# (b) walls: the child on the ground floor of the office hides L1 and L2: their walls do not block,
	# the ground floor's own do. Camera from the west at a steep pitch, over the ground walls (3.2 high).
	var hide0 := {"office": 0.0}
	# the west wall of storey 0 (x -23..-22.7): a low ray from the west into the lobby is blocked
	var low := _ray(Vector3(-20.0, 0.0, -8.0), -PI * 0.5, deg_to_rad(25.0))
	_ok(N.pick(low[0], low[1], hide0).is_empty(), "the child's own storey's wall still blocks a low tap from the west")
	# a ray that crosses the west wall only at the height of storey 1 (3.2..6.4): target on the lobby
	# ground, steep angle: the ray passes x = -22.7 at y between 3.2 and 6.4
	var steep := _ray(Vector3(-20.0, 0.0, -8.0), -PI * 0.5, deg_to_rad(60.0))
	var crossing_y := 2.3 * tan(deg_to_rad(60.0))
	_ok(crossing_y > 3.2 and crossing_y < 6.4, "(test geometry: the ray crosses the west wall at y %.2f in storey 1)" % crossing_y)
	var through := N.pick(steep[0], steep[1], hide0)
	_ok(not through.is_empty() and through["region"] == "" and (through["pos"] as Vector2).distance_to(Vector2(-20.0, -8.0)) < 0.05, "with storey 1 hidden its wall does not block (%s)" % str(through))
	var shown := N.pick(steep[0], steep[1], {"office": 3.2})
	_ok(shown.is_empty() or shown["region"] != "", "with storey 1 drawn, its wall (or its floor) blocks: nothing behind it is picked (%s)" % str(shown))
	# the child on L1 sees L1's walls but not L2's
	var low1 := _ray(Vector3(-20.0, 3.2, -8.0), -PI * 0.5, deg_to_rad(25.0))
	_ok(N.pick(low1[0], low1[1], {"office": 3.2}).is_empty(), "on storey 1 its own west wall blocks a low tap")
	# the roof of a hidden storey is not there either: a steep tap onto the office roof area reaches the floor
	var roof := _ray(Vector3(-20.0, 0.0, -8.0), 0.0, deg_to_rad(70.0))
	var rp := N.pick(roof[0], roof[1], hide0)
	_ok(not rp.is_empty() and rp["region"] == "", "with the storeys above hidden the roof does not stop a tap on the lobby (%s)" % str(rp))


## r2: the carousel is a solid circle; standing people (CityPeopleData.solids(), when it exists) are solid too.
func test_carousel_and_people() -> void:
	var found := false
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		if sd["kind"] != "carousel":
			continue
		found = true
		var c: Vector2 = sd["at"]
		var rad: float = sd["r"]
		_ok(not N.allowed("", c) and not N.allowed("", c + Vector2(rad - 0.05, 0.0)) and not N.allowed("", c + Vector2(0.0, rad + N.R - 0.05)), "the carousel's disc and its fence are solid")
		_ok(N.allowed("", c + Vector2(rad + N.R + 0.05, 0.0)), "just beyond the fence a child can stand")
		var stopped := 0
		for k in 24:
			var ang := TAU * float(k) / 24.0
			var dirv := Vector2(cos(ang), sin(ang))
			var cur := c + dirv * (rad + 2.0)
			if not N.allowed("", cur):
				continue
			for i in 40:
				cur = N.step("", cur, cur - dirv * 0.2)["pos"]
			if cur.distance_to(c) >= rad + N.R - 0.02:
				stopped += 1
			else:
				_ok(false, "walking at the carousel from %d degrees got to %.2f m from its centre" % [k * 15, cur.distance_to(c)])
		_ok(stopped >= 12, "walks at the carousel stop at its fence (%d)" % stopped)
		# a route around it exists
		var rt := N.route("", c + Vector2(-rad - 2.0, 0.0), "", c + Vector2(rad + 2.0, 0.0))
		_ok(not rt.is_empty(), "a route goes round the carousel")
	_ok(found, "the carousel is in GROUND_SOLIDS")
	var people := N.people_solids()
	var checked := 0
	for ps: Dictionary in people:
		var reg := N._rn(String(ps.get("region", "")))
		if not N.has_place(reg):
			_ok(false, "a person stands on an unknown region '%s'" % reg)
			continue
		var at: Vector2 = ps["at"]
		_ok(not N.allowed(reg, at) and not N.allowed(reg, at + Vector2(float(ps["r"]) + N.R - 0.05, 0.0)) or reg != "" and not N.allowed(reg, at), "a standing person at %s on '%s' is solid" % [str(at), reg])
		checked += 1
	print("  people solids read: ", checked)
