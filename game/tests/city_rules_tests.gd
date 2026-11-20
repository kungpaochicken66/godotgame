## Headless tests for the city's shared rules (core/city_rules.gd): occupancy, the Ferris wheel, traffic,
## walkers and the packed state.
##   godot --headless --path game -s res://tests/city_rules_tests.gd
extends SceneTree

const Rules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for t in ["test_occupancy", "test_momentary", "test_wheel_geometry", "test_boarding", "test_riding", "test_disconnect",
			"test_vehicles", "test_traffic_invariants", "test_bus_stops", "test_headways", "test_vehicle_yield", "test_walkers", "test_pack", "test_pack_layout", "test_weather", "test_determinism"]:
		call(t)
	print("CITY RULES TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _at(key: String) -> Vector2:
	return (CityMap.INTERACTIONS[key] as Dictionary)["pos"]


func _reg(key: String) -> String:
	return (CityMap.INTERACTIONS[key] as Dictionary)["region"]


func test_occupancy() -> void:
	var r := Rules.new()
	var k := "cafe_seat_a"
	var a := r.use(1, k, _reg(k), _at(k))
	_ok(a["ok"] and a["hold"] and a["pose"] == "sit", "peer 1 sits (%s)" % str(a))
	_ok(r.occupant(k) == 1 and r.held(1) == k, "occupant recorded")
	var b := r.use(2, k, _reg(k), _at(k))
	_ok(not b["ok"] and b["reason"] == "busy", "peer 2 finds the seat busy")
	_ok(r.use(1, k, _reg(k), _at(k))["ok"], "peer 1 may use its own seat again")
	_ok(r.offer(2, "ground", _at(k)) != k, "the action button does not offer a busy seat to another child")
	_ok(r.offer(1, "ground", _at(k)) == k, "it offers the held one to its holder")
	_ok(r.use(2, "cafe_seat_b", "ground", _at("cafe_seat_b"))["ok"], "the next seat is free")
	var far := r.use(3, "cafe_seat_c", "ground", _at("cafe_seat_c") + Vector2(CityMap.REACH + 0.1, 0.0))
	_ok(not far["ok"] and far["reason"] == "far", "too far to sit")
	var lvl := r.use(3, "terrace_seat_a", "ground", _at("terrace_seat_a"))
	_ok(not lvl["ok"] and lvl["reason"] == "level", "wrong level refused")
	_ok(not r.use(3, "nope", "ground", Vector2.ZERO)["ok"], "unknown key refused")
	# moving to another seat frees the first
	_ok(r.use(1, "cafe_seat_d", "ground", _at("cafe_seat_d"))["ok"] and r.occupant(k) == -1 and r.occupant("cafe_seat_d") == 1, "taking another seat frees the old one")
	# every holding kind holds exactly one
	for key: String in CityMap.INTERACTIONS:
		var kind: String = (CityMap.INTERACTIONS[key] as Dictionary)["kind"]
		if kind in ["seat", "exercise", "desk"]:
			var rr := Rules.new()
			_ok(rr.use(10, key, _reg(key), _at(key))["ok"], "%s can be taken" % key)
			var second := rr.use(11, key, _reg(key), _at(key))
			_ok(not second["ok"] and second["reason"] == "busy", "%s holds one child" % key)
			_ok(rr.use(10, key, _reg(key), _at(key))["pose"] != "", "%s gives a pose" % key)
			rr.leave(10)
			_ok(rr.use(11, key, _reg(key), _at(key))["ok"], "%s is free after the holder leaves" % key)


func test_momentary() -> void:
	var r := Rules.new()
	for key: String in CityMap.INTERACTIONS:
		var kind: String = (CityMap.INTERACTIONS[key] as Dictionary)["kind"]
		if kind in ["order", "shop"]:
			var a := r.use(1, key, _reg(key), _at(key))
			var b := r.use(2, key, _reg(key), _at(key))
			_ok(a["ok"] and b["ok"] and a["line"] != "" and a["prop"] != "", "%s: two children, each gets a result (%s)" % [key, str(a)])
			_ok(r.occupant(key) == -1, "%s holds nobody" % key)
	_ok(r.use(1, "cafe_counter", "ground", _at("cafe_counter"))["prop"] == "cup", "a hot chocolate is a cup")
	_ok(r.use(1, "bus_stop", "ground", _at("bus_stop"))["travel"] == true, "the bus stop travels")
	_ok(Rules.nearest("ground", _at("shop_cafe") + Vector2(0.5, 0.2)) == "shop_cafe", "nearest finds the corner cafe")
	for key: String in CityMap.INTERACTIONS:
		if (CityMap.INTERACTIONS[key] as Dictionary)["kind"] in ["order", "shop"]:
			_ok(Rules.RESULTS.has(key) and CityMap.LINES.has(String((Rules.RESULTS[key] as Dictionary)["line"])), "%s has a result whose line text exists" % key)
	_ok(Rules.nearest("", Vector2(30.0, 20.0)) == "", "nothing near, nothing offered")
	for key: String in Rules.RESULTS:
		_ok(CityMap.INTERACTIONS.has(key), "result %s belongs to a real interaction" % key)


func test_wheel_geometry() -> void:
	var f: Dictionary = CityMap.FERRIS
	var p0 := Rules.gondola_pos(0, 0.0)
	_ok(absf(p0.y - float(f["board_y"])) < 1e-4 and absf(p0.x - 16.0) < 1e-4 and absf(p0.z - 4.0) < 1e-4, "gondola 0 at the bottom at t = 0 (%s)" % str(p0))
	_ok(Rules.bottom_gondola(0.0) == 0, "gondola 0 boardable at 0")
	_ok(Rules.bottom_gondola(10.0) == 7, "gondola 7 comes 10 s later")
	_ok(Rules.bottom_gondola(5.0) == -1, "between two gondolas nothing is at the bottom (offsets 5 and -5 are outside the window)")
	var half := Rules.window_half()
	_ok(Rules.bottom_gondola(half - 0.01) == 0 and Rules.bottom_gondola(-half + 0.01 + 80.0) == 0, "window edges are inclusive of +-%.1f s" % half)
	_ok(Rules.bottom_gondola(half + 0.05) == -1, "just outside the window")
	# the top is 12 m higher than the bottom
	var top := Rules.gondola_pos(0, 40.0)
	_ok(absf(top.y - (float(f["board_y"]) + 2.0 * float(f["radius"]))) < 1e-3, "gondola 0 at the top after half a turn")
	# a full turn returns
	_ok(Rules.gondola_pos(3, 17.0).distance_to(Rules.gondola_pos(3, 97.0)) < 1e-3, "one turn is 80 s")
	# seconds since bottom is continuous and signed
	_ok(absf(Rules.bottom_offset(0, 1.5) - 1.5) < 1e-6 and absf(Rules.bottom_offset(0, 78.5) + 1.5) < 1e-6, "bottom offset is signed seconds")
	_ok(absf(Rules.next_bottom(0, 1.0) - 80.0) < 1e-6 and absf(Rules.next_bottom(7, 1.0) - 10.0) < 1e-6, "next bottom pass of a gondola")


func test_boarding() -> void:
	var f: Dictionary = CityMap.FERRIS
	var at: Vector2 = f["board_at"]
	var r := Rules.new()
	_ok(r.board(1, 5.0, "", at)["reason"] == "wait", "no boarding between gondolas")
	_ok(r.board(1, 0.0, "", at + Vector2(CityMap.REACH + 0.2, 0.0))["reason"] == "far", "no boarding away from the platform")
	_ok(r.board(1, 0.0, "office_l1", at)["reason"] == "level", "no boarding from another level")
	var a := r.board(1, 0.0, "ground", at)
	var b := r.board(2, 1.0, "", at + Vector2(0.5, 0.0))
	var c := r.board(3, 2.0, "", at)
	_ok(a["ok"] and b["ok"] and a["gondola"] == 0 and b["gondola"] == 0 and a["seat"] != b["seat"], "two children share gondola 0 (%s %s)" % [str(a), str(b)])
	_ok(not c["ok"] and c["reason"] == "full", "a third child cannot board the same gondola")
	_ok(r.board(1, 2.0, "", at)["reason"] == "riding", "a rider cannot board twice")
	# the next gondola, ten seconds on, takes the third
	var d := r.board(3, 10.0, "", at)
	_ok(d["ok"] and d["gondola"] == 7, "the next gondola is free (%s)" % str(d))
	# through the interaction route
	var r2 := Rules.new()
	r2.tick(0.0)
	_ok(r2.use(9, "ferris_board", "ground", at)["ok"], "boarding through use() at t = 0")
	var r3 := Rules.new()
	r3.tick(5.0)
	_ok(r3.use(9, "ferris_board", "ground", at)["reason"] == "wait", "use() waits for a gondola")
	# in the window edge only
	var r4 := Rules.new()
	_ok(r4.board(1, Rules.window_half() + 0.2, "", at)["reason"] == "wait", "just after the window: wait")


func test_riding() -> void:
	var f: Dictionary = CityMap.FERRIS
	var at: Vector2 = f["board_at"]
	var period := Rules.ferris_period()
	# automatic exit after one turn, at the bottom
	var r := Rules.new()
	r.tick(2.0)
	var a := r.board(1, r.time, "", at)
	_ok(a["ok"], "board at 2 s")
	var left_early := false
	var exited_at := -1.0
	var ev: Array = []
	while r.time < 2.0 + period + 5.0:
		ev = r.tick(0.25)
		if not r.is_riding(1) and exited_at < 0.0:
			exited_at = r.time
			_ok(ev.size() == 1 and ev[0]["peer"] == 1 and (ev[0]["pos"] as Vector2).distance_to(at) < 0.01, "exit event at the platform")
			_ok(Rules.at_bottom(int(a["gondola"]), r.time), "the rider gets off with the gondola at the bottom")
		if exited_at < 0.0 and r.time < 2.0 + period - 0.3 and not r.is_riding(1):
			left_early = true
	_ok(not left_early and exited_at >= 2.0 + period - 1e-6 and exited_at < 2.0 + period + 0.5, "one full turn, then off (at %.2f)" % exited_at)
	# a request cannot shorten the first turn; it leaves at the next bottom pass
	var r2 := Rules.new()
	var b := r2.board(1, 0.0, "", at)
	r2.tick(20.0)
	var req := r2.request_off(1, r2.time)
	_ok(req["ok"] and req["exit_at"] >= period - 1e-6, "a request at 20 s still means a full turn (%s)" % str(req))
	for i in 600:
		r2.tick(0.25)
		if r2.time < period - 0.3:
			_ok(r2.is_riding(1), "still riding at %.1f s" % r2.time) if i % 50 == 0 else null
	_ok(not r2.is_riding(1), "off by the first return")
	# several laps: stays until a request, then leaves only at a bottom pass
	var r3 := Rules.new()
	r3.board(1, 0.0, "", at, 3)
	r3.tick(100.0)
	_ok(r3.is_riding(1), "three laps requested: still riding after one turn")
	var q := r3.request_off(1, r3.time)
	var exit_t := float(q["exit_at"])
	_ok(exit_t >= period and exit_t <= 160.0 + 1e-6 and Rules.at_bottom(0, exit_t), "request at 100 s leaves at a bottom pass (%.2f)" % exit_t)
	r3.tick(exit_t - r3.time - 0.01)
	_ok(r3.is_riding(1), "not before that")
	r3.tick(0.02)
	_ok(not r3.is_riding(1), "and then off")
	# the gondola is free again after the exit
	_ok(r3.board(2, exit_t, "", at)["ok"], "the seat is boardable again after exit")
	# nobody ever gets off while their gondola is away from the bottom
	var r5 := Rules.new()
	var seq := [[0.0, 1], [10.0, 2], [20.0, 3], [30.0, 4]]
	var ok_all := true
	var t := 0.0
	var boarded: Dictionary = {}
	while t < 400.0:
		for s: Array in seq:
			if absf(t - float(s[0])) < 1e-9:
				var bb := r5.board(int(s[1]), t, "", at)
				boarded[int(s[1])] = bb["ok"]
		var evs := r5.tick(0.25)
		t += 0.25
		for e: Dictionary in evs:
			if not Rules.at_bottom(int(e["gondola"]), r5.time):
				ok_all = false
	_ok(ok_all and boarded.size() == 4, "every exit happens with its gondola at the bottom")


func test_disconnect() -> void:
	var at: Vector2 = (CityMap.FERRIS as Dictionary)["board_at"]
	var r := Rules.new()
	r.board(1, 0.0, "", at)
	r.board(2, 0.0, "", at)
	_ok(r.board(3, 0.0, "", at)["reason"] == "full", "full")
	r.leave(1)
	_ok(not r.is_riding(1) and r.gondola_riders(0) == [2], "disconnect frees the seat at once")
	_ok(r.board(3, 1.0, "", at)["ok"], "and another child takes it")
	r.use(5, "cafe_seat_a", "ground", _at("cafe_seat_a"))
	r.leave(5)
	_ok(r.occupant("cafe_seat_a") == -1, "disconnect frees a seat as well")
	r.use(6, "gym_weights", "ground", _at("gym_weights"))
	_ok(r.use(6, "ferris_board", "ground", at)["reason"] != "ok", "(a child at the weights is not on the wheel)")
	var rd := Rules.new()
	rd.board(7, 0.0, "", at)
	_ok(not rd.use(7, "cafe_seat_a", "ground", _at("cafe_seat_a"))["ok"], "a rider cannot take a seat")


func _bumper_gap(r: Rules, i: int, j: int) -> float:
	var total := Rules.loop_length()
	var li: float = (CityMap.VEHICLES[i] as Dictionary)["length"]
	var lj: float = (CityMap.VEHICLES[j] as Dictionary)["length"]
	return fposmod((float((r.vehicles[j] as Dictionary)["s"]) - lj * 0.5) - (float((r.vehicles[i] as Dictionary)["s"]) + li * 0.5), total)


## The vehicle each one follows (the nearest ahead), at the start.
func _leaders(r: Rules) -> Array:
	var out: Array = []
	for i in r.vehicles.size():
		var best := -1
		var best_g := INF
		for j in r.vehicles.size():
			if j != i and _bumper_gap(r, i, j) < best_g:
				best_g = _bumper_gap(r, i, j)
				best = j
		out.append(best)
	return out


func test_vehicles() -> void:
	var r := Rules.new()
	var total := Rules.loop_length()
	_ok(absf(total - 192.0) < 1e-6, "the ring road is 192 m (%.1f)" % total)
	_ok(CityMap.VEHICLES.size() == 5 and r.vehicles.size() == 5, "three buses and two cars")
	var colours: Array = []
	for v: Dictionary in CityMap.VEHICLES:
		if v["kind"] == "bus" and not colours.has(v["color"]):
			colours.append(v["color"])
	_ok(colours.size() == 3, "the three buses have different colours")
	var poses := r.vehicle_poses()
	_ok(poses[0].has("color") and poses[0].has("dwell") and poses[0].has("kind") and poses[0].has("stopped"), "vehicle_poses keeps its shape plus color and dwell")
	_ok(Rules.stop_arcs().size() == CityMap.BUS_STOPS.size(), "every stop has an arc position")
	var asc := true
	for i in range(1, Rules.stop_arcs().size()):
		if float(Rules.stop_arcs()[i]) < float(Rules.stop_arcs()[i - 1]):
			asc = false
	_ok(asc, "stop arcs ascend")
	_ok(not CityMap.BUS_STOPS.is_empty() and float(CityMap.VEHICLE_GAP) > 0.0, "the map has stops and a gap")
	# the start already respects the gap
	for i in r.vehicles.size():
		_ok(_bumper_gap(r, i, _leaders(r)[i]) >= float(CityMap.VEHICLE_GAP), "vehicle %d starts a gap behind its leader" % i)


## One long simulation: returns {"min_gap", "order_ok", "max_jump", "dwells": {bus: [stop indices]}, "stopped_for_child", ...}.
func _simulate(dt: float, seconds: float, child_windows: bool) -> Dictionary:
	var r := Rules.new()
	var total := Rules.loop_length()
	var leaders := _leaders(r)
	var min_gap := INF
	var order_ok := true
	var max_jump := 0.0
	var dwells: Dictionary = {}
	var dwell_len: Dictionary = {}
	var prev: Array = []
	for st: Dictionary in r.vehicles:
		prev.append({"s": float(st["s"]), "dwell": 0.0})
	var steps := int(seconds / dt)
	for n in steps:
		var kids: Array = []
		if child_windows:
			var cycle := fmod(r.time, 150.0)
			# a child stands in the road (south leg, mid-lane) for 40 s out of every 150
			if cycle > 50.0 and cycle < 90.0:
				kids.append({"id": 1, "pos": Vector2(-12.0, 20.0), "region": ""})
			if cycle > 100.0 and cycle < 120.0:
				kids.append({"id": 2, "pos": Vector2(28.0, -10.0), "region": ""})
		r.tick(dt, kids)
		for i in r.vehicles.size():
			var st: Dictionary = r.vehicles[i]
			var d := fposmod(float(st["s"]) - float((prev[i] as Dictionary)["s"]), total)
			if d > total * 0.5:
				d = 0.0
			max_jump = maxf(max_jump, d - float((CityMap.VEHICLES[i] as Dictionary)["speed"]) * dt)
			if float(st["v"]) < -1e-9:
				order_ok = false
			if float(st["dwell"]) > 0.0 and float((prev[i] as Dictionary)["dwell"]) <= 0.0:
				if not dwells.has(i):
					dwells[i] = []
					dwell_len[i] = []
				(dwells[i] as Array).append(int(st["stop"]))
				(dwell_len[i] as Array).append(float(st["dwell"]))
				var arc := float(Rules.stop_arcs()[int(st["stop"])])
				if absf(float(st["s"]) - arc) > 1e-6:
					order_ok = false
			prev[i] = {"s": float(st["s"]), "dwell": float(st["dwell"])}
			min_gap = minf(min_gap, _bumper_gap(r, i, int(leaders[i])))
		# the order never changes: every vehicle's nearest vehicle ahead is still the same one
		if n % 20 == 0 and _leaders(r) != leaders:
			order_ok = false
	return {"min_gap": min_gap, "order_ok": order_ok, "max_jump": max_jump, "dwells": dwells, "dwell_len": dwell_len, "r": r}


func test_traffic_invariants() -> void:
	for dt in [0.1, 0.25]:
		for child in [false, true]:
			var res := _simulate(dt, 600.0, child)
			var tag := "dt %.2f%s" % [dt, " with a child in the road" if child else ""]
			_ok(float(res["min_gap"]) >= float(CityMap.VEHICLE_GAP) - 1e-3, "%s: nobody closes under the gap (closest %.3f m)" % [tag, res["min_gap"]])
			_ok(bool(res["order_ok"]), "%s: the order on the loop never changes (nobody passes), stops are exact" % tag)
			_ok(float(res["max_jump"]) <= 0.05, "%s: nobody ever jumps (largest excess %.3f m)" % [tag, res["max_jump"]])


func test_bus_stops() -> void:
	var res := _simulate(0.1, 600.0, false)
	var dwells: Dictionary = res["dwells"]
	var nstops := Rules.stop_arcs().size()
	for i in CityMap.VEHICLES.size():
		var kind: String = (CityMap.VEHICLES[i] as Dictionary)["kind"]
		if kind == "bus":
			_ok(dwells.has(i), "bus %d stops somewhere" % i)
			if not dwells.has(i):
				continue
			var seen: Array = []
			var cyc := true
			var list: Array = dwells[i]
			for k in list.size():
				if not seen.has(list[k]):
					seen.append(list[k])
				if k > 0 and int(list[k]) != (int(list[k - 1]) + 1) % nstops:
					cyc = false
			_ok(seen.size() == nstops, "bus %d dwells at every stop (%s)" % [i, str(seen)])
			_ok(cyc, "bus %d takes the stops in order round the loop (%s)" % [i, str(list)])
			var shortest := 1e9
			for d: float in res["dwell_len"][i]:
				shortest = minf(shortest, d)
			_ok(shortest >= float(CityMap.BUS_DWELL) - 1e-6 and shortest <= float(CityMap.BUS_DWELL) + Rules.DWELL_EXTRA_MAX + 1e-6, "bus %d dwells BUS_DWELL (+ at most %.0f s): %.2f" % [i, Rules.DWELL_EXTRA_MAX, shortest])
		else:
			_ok(not dwells.has(i), "car %d never stops at a stop" % i)


func test_headways() -> void:
	var r := Rules.new()
	var total := Rules.loop_length()
	var buses: Array = []
	for i in CityMap.VEHICLES.size():
		if (CityMap.VEHICLES[i] as Dictionary)["kind"] == "bus":
			buses.append(i)
	var even := total / float(buses.size())
	var worst := 0.0
	var t_end := 900.0
	var n := int(t_end / 0.25)
	for k in n:
		r.tick(0.25)
		if r.time >= 300.0 and k % 40 == 0:
			var arcs: Array = []
			for b: int in buses:
				arcs.append(float((r.vehicles[b] as Dictionary)["s"]))
			arcs.sort()
			for g in arcs.size():
				var gap := fposmod(float(arcs[(g + 1) % arcs.size()]) - float(arcs[g]), total)
				worst = maxf(worst, absf(gap - even) / even)
	_ok(worst <= 0.25, "after 5 minutes the bus gaps stay within 25%% of even (worst %.0f%%)" % (worst * 100.0))
	# bunched buses spread out again: start two buses close and let them run
	var rb := Rules.new()
	var s0 := float((rb.vehicles[0] as Dictionary)["s"])
	# put bus 2 (index 2) 20 m behind bus 0's far side... the buses closest by headway
	var b2: Dictionary = rb.vehicles[2]
	b2["s"] = fposmod(s0 - 25.0, total)
	var b4: Dictionary = rb.vehicles[4]
	b4["s"] = fposmod(s0 - 70.0, total)
	var nstop := Rules._next_stop(float(b2["s"]))
	b2["stop"] = nstop
	b4["stop"] = Rules._next_stop(float(b4["s"]))
	for k in int(900.0 / 0.25):
		rb.tick(0.25)
	var arcs2: Array = []
	for b: int in buses:
		arcs2.append(float((rb.vehicles[b] as Dictionary)["s"]))
	arcs2.sort()
	var worst2 := 0.0
	for g in arcs2.size():
		worst2 = maxf(worst2, absf(fposmod(float(arcs2[(g + 1) % arcs2.size()]) - float(arcs2[g]), total) - even) / even)
	_ok(worst2 <= 0.4, "buses started bunched spread out again (worst %.0f%% from even after 15 min)" % (worst2 * 100.0))
	# the extra dwell is bounded and only when bunched
	_ok(Rules.DWELL_EXTRA_MAX <= 3.0 and Rules.BUNCH_FRACTION == 0.6, "bunching wait is bounded by 3 s at 0.6 of the headway")


func _kid_ahead(r: Rules, i: int, dist: float, lateral := 0.0) -> Dictionary:
	var length: float = (CityMap.VEHICLES[i] as Dictionary)["length"]
	var front := float((r.vehicles[i] as Dictionary)["s"]) + length * 0.5
	var pt := Rules.poly_point(CityMap.ROAD_LOOP, front + dist)
	var normal := Vector2(-(pt["dir"] as Vector2).y, (pt["dir"] as Vector2).x)
	return {"id": 1, "pos": (pt["pos"] as Vector2) + normal * lateral, "region": ""}


## Tick until vehicle i is rolling at speed.
func _roll(r: Rules, i: int) -> void:
	for n in 4000:
		r.tick(0.1)
		if float((r.vehicles[i] as Dictionary)["v"]) > 2.0 and float((r.vehicles[i] as Dictionary)["dwell"]) <= 0.0:
			return


func test_vehicle_yield() -> void:
	var total := Rules.loop_length()
	for i in [1, 3]:
		var r := Rules.new()
		_roll(r, i)
		var kid := _kid_ahead(r, i, 7.0)
		for n in 120:
			r.tick(0.1, [kid])
		var st: Dictionary = r.vehicles[i]
		var length: float = (CityMap.VEHICLES[i] as Dictionary)["length"]
		var front := float(st["s"]) + length * 0.5
		var kid_s := Rules.poly_project(CityMap.ROAD_LOOP, kid["pos"]).x
		_ok(float(st["v"]) < 0.01, "vehicle %d stopped for the child in front (v %.2f)" % [i, float(st["v"])])
		_ok(kid_s - front > 0.8 and kid_s - front <= Rules.STOP_AHEAD + 0.01, "vehicle %d stopped short of the child (%.2f m left)" % [i, kid_s - front])
		for n in 400:
			r.tick(0.25, [kid])
		_ok(float((r.vehicles[i] as Dictionary)["v"]) < 0.01, "vehicle %d keeps waiting" % i)
		# the others queue behind it with the gap and nobody passes
		var leaders_ok := true
		for a in r.vehicles.size():
			for b in r.vehicles.size():
				if a != b and _bumper_gap(r, a, b) < float(CityMap.VEHICLE_GAP) - 1e-3 and _bumper_gap(r, a, b) < total * 0.5:
					leaders_ok = false
		_ok(leaders_ok, "a queue behind the child keeps the gap")
		var s_before := float((r.vehicles[i] as Dictionary)["s"])
		for n in 60:
			r.tick(0.1, [])
		_ok(float((r.vehicles[i] as Dictionary)["s"]) - s_before > 3.0 or fposmod(float((r.vehicles[i] as Dictionary)["s"]) - s_before, total) > 3.0, "after the child steps away vehicle %d goes on" % i)
	# children who do not block: beside the lane, on another level, behind the vehicle
	for case in [["on the pavement", 4.0, "", 6.0], ["upstairs", 0.0, "office_l1", 6.0], ["behind", 0.0, "", -12.0]]:
		var rr := Rules.new()
		_roll(rr, 1)
		var k2 := _kid_ahead(rr, 1, float(case[3]), float(case[1]))
		k2["region"] = case[2]
		rr.tick(0.5, [k2])
		_ok(float((rr.vehicles[1] as Dictionary)["v"]) > 1.5, "a child %s does not stop the car" % case[0])
	var r3 := Rules.new()
	_roll(r3, 1)
	r3.tick(0.1, [_kid_ahead(r3, 1, 12.0)])
	_ok(float((r3.vehicles[1] as Dictionary)["v"]) > 2.0, "a child 12 m ahead: still rolling")


func _people_extra_clear(p: Vector2, extra: float) -> bool:
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		if sd.has("rect"):
			if (sd["rect"] as Rect2).grow(0.25 - extra).has_point(p):
				return false
		elif p.distance_to(sd["at"]) < float(sd["r"]) + 0.25 - extra:
			return false
	for f: Dictionary in CityMap.FURNITURE:
		if String(f["region"]) == "ground" and (f["rect"] as Rect2).grow(0.25 - extra).has_point(p):
			return false
	for ps: Dictionary in CityNav.people_solids():
		if String(ps.get("region", "")) in ["ground", ""] and p.distance_to(ps["at"]) < float(ps["r"]) + 0.25 - extra:
			return false
	return true


func test_walkers() -> void:
	var inner: Rect2 = CityMap.ROAD_INNER
	var lot: Rect2 = CityMap.LOT
	var n := int(CityMap.PEDESTRIANS)
	_ok(n == 10 and Rules.walkers(0.0).size() == 10, "ten walkers")
	var w0: Array = Rules.walkers(12.5)
	var keys_ok := true
	for i in w0.size():
		var w: Dictionary = w0[i]
		if not (w.has("pos") and w.has("ry") and w.has("phase") and w.has("index")) or int(w["index"]) != i or float(w["phase"]) < 0.0 or float(w["phase"]) >= 1.0:
			keys_ok = false
	_ok(keys_ok, "each walker has pos, ry, phase 0..1 and a stable index")
	_ok(Rules.walkers(12.5) == w0 and Rules.walker_pose(3, 12.5) == w0[3], "walkers are a pure function of time")
	var worst_speed := 0.0
	var best_speed := INF
	var on_ground := true
	var clear := true
	var min_gap := INF
	var phase_moves := true
	var prev: Array = Rules.walkers(0.0)
	var dt := 0.25
	for step in range(1, 2400):
		var t := float(step) * dt
		var now: Array = Rules.walkers(t)
		for i in now.size():
			var p: Vector2 = (now[i] as Dictionary)["pos"]
			var in_band := inner.grow(0.001).has_point(p) and not (p.x > lot.position.x + 0.001 and p.x < lot.end.x - 0.001 and p.y > lot.position.y + 0.001 and p.y < lot.end.y - 0.001)
			var on_path := false
			for pr: Rect2 in CityMap.PATHS:
				if pr.grow(0.6).has_point(p):
					on_path = true
			var outer: Rect2 = CityMap.OUTER_PAVEMENT
			var in_outer := outer.grow(0.001).has_point(p) and not (CityMap.ROAD_OUTER as Rect2).grow(-0.001).has_point(p)
			if not in_band and not on_path and not in_outer:
				on_ground = false
			if not _people_extra_clear(p, 0.001):
				clear = false
			var sp := p.distance_to((prev[i] as Dictionary)["pos"]) / dt
			worst_speed = maxf(worst_speed, sp)
			if step > 1:
				best_speed = minf(best_speed, sp)
			for j in range(i + 1, now.size()):
				min_gap = minf(min_gap, p.distance_to((now[j] as Dictionary)["pos"]))
		prev = now
	_ok(on_ground, "every walker is on the block pavement, the outer pavement or a path")
	_ok(clear, "walkers never touch a solid, furniture, the carousel or a standing person")
	_ok(worst_speed <= 1.4 + 0.02, "no walker faster than 1.4 m/s (%.2f)" % worst_speed)
	var speeds: Array = []
	for l: Dictionary in Rules.walk_loops():
		speeds.append(float(l["speed"]))
	_ok(speeds.size() >= 2 and speeds.min() >= 1.0 and speeds.max() <= 1.4 and speeds.min() < speeds.max(), "speeds are staggered within 1.0 to 1.4 m/s (%s)" % str(speeds))
	_ok(min_gap >= 0.7, "no two walkers closer than 0.7 m over 10 minutes (closest %.2f)" % min_gap)
	_ok(Rules.walk_loops().size() == 3, "three loops: the block pavement, the outer pavement the other way, the path loop")
	# the walk cycle advances with the distance
	var a: Dictionary = Rules.walker_pose(0, 10.0)
	var b: Dictionary = Rules.walker_pose(0, 10.2)
	_ok(absf(float(a["phase"]) - float(b["phase"])) > 0.01, "the phase moves while walking")
	# both directions: loop 0 clockwise, loop 1 the other way round
	var ws: Array = Rules.walkers(0.0)
	var w1: Array = Rules.walkers(1.0)
	var l0: Dictionary = Rules.walk_loops()[0]
	var l1: Dictionary = Rules.walk_loops()[1]
	var i1 := int(l1["first"])
	var cw := ((w1[0] as Dictionary)["pos"] - (ws[0] as Dictionary)["pos"]) as Vector2
	var ccw := ((w1[i1] as Dictionary)["pos"] - (ws[i1] as Dictionary)["pos"]) as Vector2
	_ok(cw.length() > 0.5 and ccw.length() > 0.5 and l0 != l1, "both loops move")


func _busy_state() -> Rules:
	var r := Rules.new()
	var at: Vector2 = (CityMap.FERRIS as Dictionary)["board_at"]
	r.tick(7.0, [])
	r.use(11, "cafe_seat_a", "ground", _at("cafe_seat_a"))
	r.use(12, "gym_weights", "ground", _at("gym_weights"))
	r.use(13, "office_desk_a", "office_l1", _at("office_desk_a"))
	r.tick(3.0, [])
	r.board(2147483000, r.time, "", at)
	r.board(5, r.time, "", at)
	r.tick(31.0, [{"id": 1, "pos": Vector2(0.0, 20.0), "region": ""}])
	return r


func test_pack() -> void:
	var r := _busy_state()
	var data := r.pack()
	var u := Rules.unpack(data)
	_ok(u["ok"] and absf(float(u["time"]) - r.time) < 1e-9, "unpack reads the time")
	_ok((u["occupancy"] as Dictionary).size() == 3 and u["occupancy"]["cafe_seat_a"] == 11, "occupancy in the pack")
	_ok((u["riders"] as Dictionary).size() == 2 and (u["riders"] as Dictionary).has(2147483000), "riders in the pack (large peer id exact)")
	var r2 := Rules.new()
	_ok(r2.restore(data), "restore")
	_ok(r2.pack() == data, "pack -> restore -> pack round-trips exactly")
	_ok(r2.occupant("gym_weights") == 12 and r2.is_riding(5) and absf(r2.time - r.time) < 1e-12, "restored fields")
	# a late joiner continues like the authority
	var kids := [{"id": 1, "pos": Vector2(28.0, 0.0), "region": ""}]
	for i in 200:
		r.tick(0.25, kids)
		r2.tick(0.25, kids)
	_ok(r.pack() == r2.pack(), "a restored state evolves identically")
	# malformed data is refused and changes nothing
	var before := r2.pack()
	var bad := data.duplicate()
	bad.resize(bad.size() - 3)
	_ok(not r2.restore(bad) and not r2.restore(PackedFloat64Array([1.0])) and not Rules.unpack(PackedFloat64Array())["ok"], "malformed packs are refused")
	_ok(r2.pack() == before, "and leave the state alone")
	var wrong := data.duplicate()
	wrong[0] = 99.0
	_ok(not Rules.unpack(wrong)["ok"], "another version is refused")
	# an empty state round-trips too
	var e := Rules.new()
	var e2 := Rules.new()
	_ok(e2.restore(e.pack()) and e2.pack() == e.pack(), "the empty state round-trips")


func test_pack_layout() -> void:
	var r := Rules.new()
	var n := r.vehicles.size()
	var data := r.pack()
	_ok(data[0] == 3.0 and Rules.VERSION == 3.0, "the pack's version is 3")
	_ok(int(data[2]) == n and data.size() == 3 + 4 * n + 1 + 1 + 5, "the empty pack is [3, time, n, 4 floats per vehicle, 0 occupied, 0 riders, 5 weather floats]")
	var wt := data.size() - 5
	_ok(data[wt] == 0.0 and data[wt + 1] == -float(CityMap.WEATHER_BLEND) and data[wt + 2] == 1.0 and data[wt + 3] == 0.0 and data[wt + 4] == 0.0, "the weather tail: sunny, since -BLEND, prev (1, 0, 0)")
	for i in n:
		var base := 3 + 4 * i
		_ok(data[base] == float((r.vehicles[i] as Dictionary)["s"]) and data[base + 1] == 0.0 and data[base + 2] == 0.0 and data[base + 3] == float((r.vehicles[i] as Dictionary)["stop"]), "vehicle %d: s, v, dwell, stop" % i)
	# mid-dwell state round-trips and continues identically
	var live := Rules.new()
	var found := false
	for k in 4000:
		live.tick(0.1)
		for st: Dictionary in live.vehicles:
			if float(st["dwell"]) > 1.0:
				found = true
		if found:
			break
	_ok(found, "a bus is standing at a stop")
	var copy := Rules.new()
	_ok(copy.restore(live.pack()) and copy.pack() == live.pack(), "a mid-dwell state round-trips")
	for k in 600:
		live.tick(0.1)
		copy.tick(0.1)
	_ok(copy.pack() == live.pack(), "and runs on identically")
	var u := Rules.unpack(live.pack())
	_ok(u["vehicles"][0].has("dwell") and u["vehicles"][0].has("stop"), "unpack returns dwell and stop")
	# versions 1 and 2 are refused
	var v2 := live.pack()
	v2[0] = 2.0
	_ok(not Rules.unpack(v2)["ok"] and not Rules.new().restore(v2), "version 2 is refused")
	# version 1 data is refused
	var old := live.pack()
	old[0] = 1.0
	_ok(not Rules.unpack(old)["ok"], "the old version is refused")


func _sum_ok(w: Dictionary) -> bool:
	return absf(float(w["sunny"]) + float(w["rain"]) + float(w["night"]) - 1.0) < 1e-9 and float(w["sunny"]) >= -1e-12 and float(w["rain"]) >= -1e-12 and float(w["night"]) >= -1e-12


func _vec(w: Dictionary) -> Vector3:
	return Vector3(float(w["sunny"]), float(w["rain"]), float(w["night"]))


func test_weather() -> void:
	var r := Rules.new()
	var blend := float(CityMap.WEATHER_BLEND)
	_ok(r.weather == 0 and CityMap.WEATHERS[0] == "sunny", "a city wakes up sunny")
	var w0 := r.weights()
	_ok(w0["sunny"] == 1.0 and w0["rain"] == 0.0 and w0["night"] == 0.0, "sunny at wake: exactly (1, 0, 0)")
	_ok(r.set_weather(0)["ok"] and r.weather_since == -blend, "setting the current weather is a no-op success")
	_ok(not r.set_weather(7)["ok"] and r.set_weather(7)["reason"] == "unknown" and not r.set_weather(-1)["ok"], "an unknown weather is refused")
	_ok(r.weather == 0, "...and changes nothing")
	r.tick(10.0)
	_ok(r.set_weather(1)["ok"] and r.weather == 1 and r.weather_since == r.time, "set rain at t = 10")
	# endpoints
	var st := r.weather_state()
	var t0 := r.time
	var a := Rules.weather_weights(st, t0)
	var b := Rules.weather_weights(st, t0 + blend)
	_ok(a["sunny"] == 1.0 and a["rain"] == 0.0, "at the change: still the old mix")
	_ok(absf(float(b["rain"]) - 1.0) < 1e-12 and absf(float(b["sunny"])) < 1e-12, "BLEND seconds later: exactly the new weather")
	var mid := Rules.weather_weights(st, t0 + blend * 0.5)
	_ok(absf(float(mid["rain"]) - 0.5) < 1e-9 and absf(float(mid["sunny"]) - 0.5) < 1e-9, "halfway: smoothstep(0.5) = 0.5")
	_ok(Rules.weather_weights(st, 1000.0)["rain"] == 1.0 and Rules.weather_weights(st, -1000.0)["sunny"] == 1.0, "clamped before and after")
	_ok(Rules.rain_amount(st, t0 + blend * 0.25) == Rules.weather_weights(st, t0 + blend * 0.25)["rain"] and Rules.rain_amount(st, t0 + blend) == 1.0 and Rules.rain_amount(st, t0) == 0.0, "rain_amount is the rain weight")
	# the rules instance can be passed as well
	_ok(Rules.weather_weights(r, t0 + 2.0) == Rules.weather_weights(st, t0 + 2.0), "weather_weights takes the rules or its state")
	# monotone on a simple change, sum 1 everywhere
	var last := -1.0
	var mono := true
	var sum_ok := true
	for i in 201:
		var w := Rules.weather_weights(st, t0 - 1.0 + float(i) * 0.03)
		sum_ok = sum_ok and _sum_ok(w)
		if float(w["rain"]) < last - 1e-12:
			mono = false
		last = float(w["rain"])
	_ok(mono and sum_ok, "rain rises monotonically, the weights always sum to 1")
	# continuity across every change, including a change in the middle of a blend
	var seq := [[1.0, 2], [1.5, 0], [0.3, 1], [2.0, 2], [0.0, 0], [5.0, 1], [1.0, 1], [0.4, 2], [0.2, 1], [0.1, 0], [6.0, 2]]
	var rr := Rules.new()
	var worst := 0.0
	var all_sum := true
	for step: Array in seq:
		var steps := int(float(step[0]) / 0.05)
		for k in steps:
			rr.tick(0.05)
			all_sum = all_sum and _sum_ok(rr.weights())
		var before := _vec(rr.weights())
		var res := rr.set_weather(int(step[1]))
		var after := _vec(rr.weights())
		worst = maxf(worst, before.distance_to(after))
		_ok(res["ok"], "set_weather(%d) accepted" % int(step[1]))
	_ok(worst < 1e-9, "weights are continuous across every change, mid-blend included (jump %f)" % worst)
	_ok(all_sum, "the weights sum to 1 throughout")
	# per-tick movement is bounded by the smoothstep slope
	var ra := Rules.new()
	ra.set_weather(2)
	var prev := _vec(ra.weights())
	var max_step := 0.0
	for k in 400:
		ra.tick(0.05)
		var cur := _vec(ra.weights())
		max_step = maxf(max_step, prev.distance_to(cur))
		prev = cur
	_ok(max_step < 0.05 * 1.5 / blend * 1.5, "no jump while blending (largest step %.4f)" % max_step)
	# a change mid-blend: the new blend starts from the current mix, which is a mix of all three
	var rm := Rules.new()
	rm.set_weather(1)
	rm.tick(blend * 0.5)
	var mixed := rm.weights()
	rm.set_weather(2)
	_ok(absf(float(mixed["sunny"]) - 0.5) < 1e-9 and absf(float(rm.weather_prev[0]) - 0.5) < 1e-9 and absf(float(rm.weather_prev[1]) - 0.5) < 1e-9, "the previous mix is stored: (0.5, 0.5, 0)")
	var then := Rules.weather_weights(rm, rm.time + blend * 0.5)
	_ok(absf(float(then["night"]) - 0.5) < 1e-9 and absf(float(then["rain"]) - 0.25) < 1e-9 and absf(float(then["sunny"]) - 0.25) < 1e-9, "and the next blend goes from that mix to night")
	# pack round trip, with a blend in progress
	var rp := Rules.new()
	rp.tick(7.0)
	rp.set_weather(1)
	rp.tick(1.3)
	rp.set_weather(2)
	rp.tick(0.7)
	var data := rp.pack()
	var late := Rules.new()
	_ok(late.restore(data) and late.pack() == data, "the weather round-trips through pack()/restore()")
	_ok(late.weather == 2 and late.weather_since == rp.weather_since and late.weather_prev == rp.weather_prev, "all three fields restored")
	for t in [0.0, 1.0, 3.0, 9.0]:
		_ok(Rules.weather_weights(late, rp.time + t) == Rules.weather_weights(rp, rp.time + t), "a late joiner blends identically at +%.0f s" % t)
	var u := Rules.unpack(data)
	_ok(u["weather"]["weather"] == 2 and u["weather"]["prev"] == rp.weather_prev, "unpack carries the weather")
	_ok(Rules.weather_weights(u["weather"], rp.time + 2.0) == Rules.weather_weights(rp, rp.time + 2.0), "...and weather_weights takes it")
	# a bad weather index is refused
	var bad := data.duplicate()
	bad[bad.size() - 5] = 9.0
	_ok(not Rules.unpack(bad)["ok"], "an unknown weather index in a pack is refused")
	var short := data.duplicate()
	short.resize(short.size() - 1)
	_ok(not Rules.unpack(short)["ok"], "a pack without the whole weather tail is refused")
	# determinism
	var d1 := Rules.new()
	var d2 := Rules.new()
	for rr2: Rules in [d1, d2]:
		rr2.tick(3.0)
		rr2.set_weather(1)
		rr2.tick(2.0)
		rr2.set_weather(2)
		rr2.tick(9.0)
	_ok(d1.pack() == d2.pack(), "the same changes give the same state")


func test_determinism() -> void:
	var a := _busy_state()
	var b := _busy_state()
	_ok(a.pack() == b.pack(), "the same inputs give the same state")
	# chunking does not matter
	var c := Rules.new()
	var d := Rules.new()
	for i in 100:
		c.tick(0.5)
	d.tick(50.0)
	_ok(c.pack() == d.pack() or absf(c.time - d.time) < 1e-9, "time adds up")
	var same := true
	for i in c.vehicles.size():
		if absf(float((c.vehicles[i] as Dictionary)["s"]) - float((d.vehicles[i] as Dictionary)["s"])) > 1e-6:
			same = false
	_ok(same, "tick(0.5) x 100 equals tick(50) for the traffic")
