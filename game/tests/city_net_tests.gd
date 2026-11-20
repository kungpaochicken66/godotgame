## Headless tests for the city's network side (design/city-district.md "Playable rules"): the City
## autoload against the authority for real (a solo session), other children as recorded players.
## Real clients: scripts/net_test.py --city.
##   scripts/godot.sh --headless --path game -s res://tests/city_net_tests.gd
extends "res://tests/puzzle_ride_tests.gd"

const CityRules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const Places := preload("res://scripts/core/places.gd")

var City: Node
var _effects: Array = []


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	City = root.get_node("City")
	for t in ["test_rules"]:
		_current = t
		call(t)
	City.set_physics_process(false)   # the tests step the city themselves
	root.get_node("Zoo").set_physics_process(false)
	for t in ["test_wake_sleep", "test_places", "test_wheel", "test_traffic", "test_weather", "test_late_and_leave"]:
		_current = t
		await call(t)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nCITY NET TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _steps(n: int, dt := 0.1) -> void:
	for i in n:
		City.advance(dt)


func _friend(peer: int, space: String, p: Vector2, level := "") -> void:
	var st := {"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"}
	if level != "":
		st["level"] = level
	Session.players[peer] = {"avatar": Avatar.sanitize(Avatar.PRESETS[(peer + 1) % 4]), "pid": ("%032x" % peer), "state": st}


func _at(peer: int, p: Vector2, level := "") -> void:
	var st: Dictionary = Session.players[peer]["state"]
	st["x"] = p.x
	st["z"] = p.y
	if level == "":
		st.erase("level")
	else:
		st["level"] = level


func _use(peer: int, key: String) -> Dictionary:
	var st: Dictionary = Session.players[peer]["state"]
	return City.srv_use(peer, str(st.get("level", "")), Vector2(float(st["x"]), float(st["z"])), key)


func _no_rest() -> void:
	Session._last_journey.clear()


func _on_effect(kind: String, data: Dictionary) -> void:
	_effects.append([kind, data])


# ------------------------------------------------------------- pure rules

func test_rules() -> void:
	eq(Session.PROTOCOL, 20, "protocol 20")
	var players := {1: {"state": {"space": "city"}}, 2: {"state": {"space": "town"}}, 3: {"state": {"space": "city", "level": "gym_roof"}},
		4: {"state": {"space": "zoo"}}, 5: {"state": {"space": "i1:0:0"}}, 6: {"state": {}}}
	eq(City.in_city(players), [1, 3], "players in the city")
	eq(City.recipients(players, [2, 3, 4, 5, 6]), [3], "states go only to open peers in the city (not the town, the zoo, a cottage room or the unknown)")
	eq(City.recipients(players, []), [], "and to nobody when no connection is open")
	# The packed state round-trips into the client form.
	var r := CityRules.new()
	r.tick(12.0)
	r.use(5, "cafe_seat_a", "", CityMap.INTERACTIONS["cafe_seat_a"]["pos"])
	r.board(6, 10.0, "", CityMap.FERRIS["board_at"])
	var s: Dictionary = City.decode(r.pack())
	ok(not s.is_empty(), "a packed state decodes")
	ok(absf(float(s["time"]) - r.time) < 1e-9, "time kept")
	ok(absf(float(s["ferris_angle"]) - CityRules.gondola_angle(0, r.time)) < 1e-9, "the wheel's angle is gondola 0's")
	eq(s["vehicles"].size(), 5, "five vehicles in the decoded state")
	eq(CityMap.VEHICLES.size(), 5, "(the map has five)")
	for i in 5:
		eq(s["vehicles"][i]["kind"], CityMap.VEHICLES[i]["kind"], "vehicle %d kind" % i)
		eq(s["vehicles"][i]["color"], CityMap.VEHICLES[i]["color"], "vehicle %d colour" % i)
		ok(s["vehicles"][i].has("dwell") and float(s["vehicles"][i]["dwell"]) >= 0.0, "vehicle %d carries its dwell" % i)
	eq(s["vehicles"].map(func(v): return v["kind"]), ["bus", "car", "bus", "car", "bus"], "three buses and two cars")
	eq(s["vehicles"].map(func(v): return v["stop"] == -1), [false, true, false, true, false], "buses have a next stop, cars -1")
	eq(CityRules.VERSION, 3.0, "pack version 3")
	eq(s["weather"], 0, "the weather in the state: sunny by default")
	var rw := CityRules.new()
	rw.tick(7.0)
	rw.set_weather(2)
	var sw: Dictionary = City.decode(rw.pack())
	eq([sw["weather"], sw["since"], sw["prev"]], [2, rw.weather_since, rw.weather_prev], "the decoded weather, since and previous mix")
	for t in [7.0, 8.5, 10.0, 12.0, 20.0]:
		var d: Dictionary = CityRules.weather_weights(sw, t)
		var e: Dictionary = CityRules.weather_weights(rw, t)
		ok(absf(d["night"] - e["night"]) < 1e-9 and absf(d["sunny"] - e["sunny"]) < 1e-9, "the client's weights match the rules' at t=%.1f" % t)
	var bytes := r.pack().size() * 8
	print("PACKET BYTES (rules.pack, Float64): %d" % bytes)
	ok(bytes <= 600, "the packed state stays small (%d bytes)" % bytes)
	var old := r.pack()
	old[0] = 1.0 if old[0] != 1.0 else 2.0   # another version
	ok(City.decode(old).is_empty(), "a pack of another version is refused with an empty state")
	City._apply(old)
	eq(s["vehicles"][0]["pos"], r.vehicle_poses()[0]["pos"], "a vehicle's pose is the rules' own")
	eq(s["occupancy"], {"cafe_seat_a": 5}, "occupancy")
	eq(s["riders"], {CityRules.bottom_gondola(10.0): [6]}, "riders by gondola")
	ok(City.decode(PackedFloat64Array([1.0, 2.0])).is_empty(), "a malformed packet is ignored")
	# est_time never runs backwards and restarts with a new city.
	City._reset()
	eq(City.est_time(), 0.0, "no estimate before a state arrives")
	City._apply(r.pack())
	var t1: float = City.est_time()
	ok(absf(t1 - r.time) < 0.2, "the estimate starts at the packet's time")
	var older := CityRules.new()
	older.tick(11.7)
	City._apply(older.pack())
	ok(City.est_time() >= t1, "a late packet does not set the clock back")
	City._apply(CityRules.new().pack())
	ok(City.est_time() < 1.0, "a freshly woken city restarts the clock")
	City._reset()
	eq(City.states, City.empty_state(), "reset is the empty shape")
	eq(City.occupant("cafe_seat_a"), -1, "nobody in the empty state")
	eq(City.riding(6), -1, "nobody riding in the empty state")
	for reason in ["busy", "far", "level", "riding", "wait", "full", "not_riding", "?"]:
		ok(City.refusal(reason, "cafe_seat_a").ends_with("."), "a sentence for " + reason)
	_current = "test_rules"


# ------------------------------------------------------------- wake and sleep

func test_wake_sleep() -> void:
	await process_frame
	await _fresh_town("user://test_city_net.json")
	City.effect.connect(_on_effect)
	var me: int = Session.my_id
	ok(City.rules == null, "the city sleeps with nobody in it")
	_friend(70, "town", Vector2(3, 3))
	City.advance(0.1)
	ok(City.rules == null, "a child in town does not wake it")
	var got := []
	var cb := func(states): got.append(states)
	City.updated.connect(cb)
	var r := await _result(Session.travel("city"))
	City.updated.disconnect(cb)
	ok(r.get("ok", false), "the tram goes to the city (%s)" % str(r))
	ok(City.rules != null, "the first arrival wakes the city")
	ok(got.size() >= 1 and got[0]["vehicles"].size() == CityMap.VEHICLES.size(), "and the child gets the picture at once")
	ok(City.rules.time < 0.1, "the city wakes fresh (%s)" % City.rules.time)
	# Nothing reaches a child who is in town.
	_no_rest()
	await create_timer(1.1).timeout
	r = await _result(Session.travel("town"))
	ok(r.get("ok", false), "back to town")
	ok(City.rules == null, "the city sleeps again with its last child gone")
	eq(City.states, City.empty_state(), "and its state is the empty shape")
	_friend(71, "city", CityMap.ARRIVALS[0])
	City.on_space_changed(71)
	ok(City.rules != null, "another child's arrival wakes it")
	var n_before := got.size()
	got.clear()
	City.updated.connect(cb)
	_steps(30)
	City.updated.disconnect(cb)
	eq(got.size(), 0, "the child in town hears nothing of 3 s of the city")
	eq(City.states, City.empty_state(), "and holds an empty state")
	ok(n_before >= 1, "(sanity)")
	_no_rest()
	Session._on_peer_disconnected(71)
	ok(City.rules == null, "the last child leaving the server sleeps it")
	Session.players.erase(70)


# ------------------------------------------------------------- seats, machines, orders and shops

func test_places() -> void:
	await process_frame
	_no_rest()
	var me: int = Session.my_id
	var r := await _result(Session.travel("city"))
	ok(r.get("ok", false), "to the city")
	_friend(72, "city", Vector2(-5.0, -6.0))
	City.on_space_changed(72)
	var sa: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	_at(me, sa)
	_at(72, sa + Vector2(0.5, 0))
	var a: Dictionary = _use(me, "cafe_seat_a")
	ok(a.get("ok", false) and a.get("hold", false) and a.get("pose") == "sit", "the first child sits (%s)" % str(a))
	eq(City.occupant("cafe_seat_a"), me, "the state shows who")
	var b: Dictionary = _use(72, "cafe_seat_a")
	eq(b.get("ok"), false, "the second child is refused the same seat")
	eq(b.get("error"), "Someone is sitting there.", "kindly")
	# The state is on the way to the one who asked through the real request path, too.
	var q := await _result(Session.city_use("cafe_seat_a"))
	ok(q.get("ok", false), "asking again as the holder is fine (%s)" % str(q))
	var rel: Dictionary = City.srv_release(me, "", sa)
	eq(rel.get("key"), "cafe_seat_a", "release frees it")
	eq(City.occupant("cafe_seat_a"), -1, "and the state says so")
	ok(_use(72, "cafe_seat_a").get("ok", false), "now the other child sits there")
	City.srv_release(72, "", sa)
	# A far child, a wrong level.
	_at(72, Vector2(0, 0))
	var far: Dictionary = _use(72, "cafe_seat_b")
	eq(far.get("error"), "Walk closer first.", "too far is refused kindly")
	var lvl: Dictionary = City.srv_use(72, "gym_roof", CityMap.INTERACTIONS["cafe_seat_b"]["pos"], "cafe_seat_b")
	eq(lvl.get("ok"), false, "the wrong level is refused")
	# Walking away stands the child up.
	_at(me, sa)
	_use(me, "cafe_seat_a")
	_at(me, sa + Vector2(6, 0))
	City.advance(0.1)
	eq(City.occupant("cafe_seat_a"), -1, "a child who walks off stands up")
	# One machine each; two treadmills and the weights.
	var ta: Vector2 = CityMap.INTERACTIONS["gym_treadmill_a"]["pos"]
	var tb: Vector2 = CityMap.INTERACTIONS["gym_treadmill_b"]["pos"]
	_at(me, ta)
	_at(72, ta + Vector2(0.4, 0))
	ok(_use(me, "gym_treadmill_a").get("pose") == "run", "the treadmill runs")
	var busy: Dictionary = _use(72, "gym_treadmill_a")
	eq(busy.get("error"), "Someone is using that.", "one child per machine")
	_at(72, tb)
	ok(_use(72, "gym_treadmill_b").get("ok", false), "the next machine is free")
	# One holder holds one thing: a second use moves them.
	_at(me, tb)
	eq(_use(me, "gym_treadmill_b").get("ok"), false, "a taken machine stays taken")
	City.srv_release(me, "", ta)
	City.srv_release(72, "", tb)
	# Upstairs: a bike and a desk.
	var bike: Dictionary = City.srv_use(me, "gym_l1", CityMap.INTERACTIONS["studio_bike_a"]["pos"], "studio_bike_a")
	ok(bike.get("ok", false) and bike.get("pose") == "cycle", "the bike upstairs works on its own level")
	City.srv_release(me, "", Vector2.ZERO)
	# Orders and shops reach the city's children as events.
	_effects.clear()
	_at(me, CityMap.INTERACTIONS["cafe_counter"]["pos"])
	var o: Dictionary = _use(me, "cafe_counter")
	ok(o.get("ok", false) and o.get("line") == "hot_chocolate" and o.get("prop") == "cup", "the counter answers (%s)" % str(o))
	eq(City.occupant("cafe_counter"), -1, "an order holds nothing")
	_at(me, CityMap.INTERACTIONS["shop_bakery"]["pos"])
	var sh: Dictionary = _use(me, "shop_bakery")
	ok(sh.get("ok", false) and sh.get("line") == "bun", "the bakery answers")
	_at(me, CityMap.INTERACTIONS["restaurant_order"]["pos"])
	City.srv_use(me, "gym_roof", CityMap.INTERACTIONS["restaurant_order"]["pos"], "restaurant_order")
	eq(_effects.map(func(e): return e[0]), ["order", "shop", "order"], "an event for each")
	eq(_effects[0][1], {"peer": me, "key": "cafe_counter", "line": "hot_chocolate", "prop": "cup"}, "with who, what and the prop")
	eq(_effects[1][1]["prop"], "bun", "the bun")
	# The bus is a journey, not a state.
	var bus: Dictionary = City.srv_use(me, "", CityMap.BUS_STOP, "bus_stop")
	ok(bus.get("ok", false) and bus.get("travel", false), "the bus stop says travel")
	# A request from outside the city is refused kindly by the session.
	Session.players.erase(72)
	City.advance(0.1)


# ------------------------------------------------------------- the wheel

func test_wheel() -> void:
	await process_frame
	var me: int = Session.my_id
	var board: Vector2 = CityMap.FERRIS["board_at"]
	_friend(73, "city", board + Vector2(0.3, 0))
	_friend(74, "city", board + Vector2(-0.3, 0))
	_at(me, board)
	City.on_space_changed(73)
	City.on_space_changed(74)
	# Away from the platform.
	City.rules.time = 10.0
	var far: Dictionary = City.srv_board(me, "", board + Vector2(5, 0))
	eq(far.get("error"), "Walk closer first.", "boarding away from the platform is refused")
	var up: Dictionary = City.srv_board(me, "gym_roof", board)
	eq(up.get("ok"), false, "and from another level")
	# Outside the window: gondolas pass the bottom every 10 s for 6 s.
	City.rules.time = 15.0
	var wait: Dictionary = City.srv_board(me, "", board)
	eq(wait.get("error"), "Wait for a gondola at the bottom.", "outside the bottom window: wait")
	# Inside it: two to a gondola.
	City.rules.time = 20.0
	var g := CityRules.bottom_gondola(20.0)
	var r1: Dictionary = City.srv_board(me, "", board)
	ok(r1.get("ok", false) and r1.get("gondola") == g, "boarding in the window is accepted (%s)" % str(r1))
	var r2: Dictionary = City.srv_board(73, "", board)
	ok(r2.get("ok", false) and r2.get("gondola") == g and r2.get("seat") != r1.get("seat"), "a second child takes the other seat")
	var r3: Dictionary = City.srv_board(74, "", board)
	eq(r3.get("ok"), false, "the third is refused")
	eq(r3.get("error"), "That gondola is full.", "kindly")
	eq(City.riding(me), g, "the state shows me riding in gondola %d" % g)
	eq(City.states["riders"][g], [me, 73] if me < 73 else [73, me], "both riders")
	eq(City.states["occupancy"].size(), 0, "no seat is held")
	# Riding blocks the rest.
	var sa: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	_at(me, sa)
	eq(_use(me, "cafe_seat_a").get("error"), "Finish your ride first.", "a rider cannot sit down")
	_at(me, board)
	eq(City.srv_board(me, "", board).get("error"), "Finish your ride first.", "or board twice")
	# Off only at the bottom, after at least a turn.
	var t0: float = City.rules.time
	var off: Dictionary = City.srv_off(me, "", board)
	ok(off.get("ok", false), "asking to get off is accepted")
	var exit_at: float = off["exit_at"]
	ok(CityRules.at_bottom(g, exit_at), "the exit is at the bottom pass")
	ok(exit_at >= t0 + CityRules.ferris_period() - 1e-6, "after one full turn")
	eq(City.srv_off(74, "", board).get("error"), "You are not on the wheel.", "a child who does not ride cannot ask")
	_effects.clear()
	City.rules.time = exit_at - 1.0
	City.advance(0.1)
	eq(City.riding(me), g, "still riding a second before")
	eq(_effects.size(), 0, "no event yet")
	_steps(12)
	eq(City.riding(me), -1, "off at the bottom")
	var offs := _effects.filter(func(e): return e[0] == "ride_off")
	ok(offs.size() >= 1, "a ride_off event")
	var ev: Dictionary = offs[0][1]
	eq(ev["peer"], me, "for the rider who asked")
	eq(ev["pos"], board, "puts the child back at the platform")
	eq(ev["region"], "", "on the ground")
	# 73 had no request: she rides on until her own full turn (the same time here).
	_effects.clear()
	City.rules.time = float(City.rules.riders.get(73, {"exit_at": 0.0})["exit_at"]) - 0.05 if City.rules.riders.has(73) else City.rules.time
	City.advance(0.2)
	eq(City.riding(73), -1, "the other rider is let off at her turn's end")
	# Disconnect mid-ride frees the place at once.
	City.rules.time = fposmod(City.rules.time, 80.0) + 800.0
	City.rules.time = floorf(City.rules.time / 10.0) * 10.0
	_at(74, board)
	var rb: Dictionary = City.srv_board(74, "", board)
	ok(rb.get("ok", false), "board again (%s)" % str(rb))
	eq(City.riding(74), int(rb["gondola"]), "riding")
	_no_rest()
	Session._on_peer_disconnected(74)
	eq(City.riding(74), -1, "a disconnect mid-ride frees the place at once")
	eq(City.rules.riders.has(74), false, "in the rules")
	Session.players.erase(73)
	City.advance(0.1)


# ------------------------------------------------------------- traffic

func test_traffic() -> void:
	await process_frame
	var me: int = Session.my_id
	_at(me, Vector2(0, 0))
	City.advance(0.1)
	_steps(60)
	var moving := 0
	for v: Dictionary in City.states["vehicles"]:
		if float(v["v"]) > 0.5:
			moving += 1
	ok(moving >= 1, "the traffic moves with the road clear (%d moving)" % moving)
	# Stand a child in the bus's lane just ahead of it.
	var bus: Dictionary = City.states["vehicles"][0]
	var dir: Vector2 = bus["dir"]
	var length: float = CityMap.VEHICLES[0]["length"]
	var ahead: Vector2 = (bus["pos"] as Vector2) + dir * (length * 0.5 + 2.0)
	_friend(75, "city", ahead)
	City.on_space_changed(75)
	_steps(40)
	var stopped := false
	for i in 40:
		_at(75, (City.states["vehicles"][0]["pos"] as Vector2) + dir * (length * 0.5 + 2.0))   # the child keeps standing just ahead
		City.advance(0.1)
		stopped = bool(City.states["vehicles"][0]["stopped"])
	ok(stopped, "the vehicle stops for a child standing in its lane")
	var s_stop: float = City.states["vehicles"][0]["s"]
	_steps(10)
	ok(absf(float(City.states["vehicles"][0]["s"]) - s_stop) < 0.05, "and stays put")
	_at(75, Vector2(0, 0))
	# It goes on: at once, or (a bus that has meanwhile reached a stop) after its stop, BUS_DWELL plus at most 3 s.
	var went := false
	for i in int((CityMap.BUS_DWELL + 3.0 + 3.0) / 0.1):
		_steps(1)
		if not bool(City.states["vehicles"][0]["stopped"]) and absf(float(City.states["vehicles"][0]["s"]) - s_stop) > 0.05:
			went = true
			break
	ok(went, "it goes on when the child steps away (dwell %.1f s)" % float(City.states["vehicles"][0].get("dwell", 0.0)))
	Session.players.erase(75)
	City.advance(0.1)


# ------------------------------------------------------------- the weather

func test_weather() -> void:
	await process_frame
	var me: int = Session.my_id
	_at(me, Vector2(0, 0))
	_friend(80, "city", Vector2(1, 1))
	_friend(81, "town", Vector2(3, 3))
	City.on_space_changed(80)
	_effects.clear()
	eq(City.states["weather"], 0, "the city starts sunny")
	var r: Dictionary = City.srv_weather(80, "", Vector2(1, 1), 1)
	ok(r.get("ok", false), "a child in the city chooses rain")
	eq(City.rules.weather, 1, "the rules keep it")
	eq(City.states["weather"], 1, "and the state shows it at once")
	ok(_effects.any(func(e): return e[0] == "weather" and e[1] == {"peer": 80, "weather": 1}), "a weather event goes to the city")
	_steps(20)   # 2 s into the blend
	var w: Dictionary = City.weights()
	ok(w["rain"] > 0.05 and w["rain"] < 1.0 and absf(w["sunny"] + w["rain"] + w["night"] - 1.0) < 1e-6, "mid-blend: a mix of sunny and rain (%s)" % str(w))
	_steps(30)
	ok(City.weights()["rain"] > 0.99, "after the blend it is rain")
	var bad: Dictionary = City.srv_weather(80, "", Vector2.ZERO, 7)
	eq(bad.get("ok"), false, "an index out of range is refused")
	eq(bad.get("error"), "The city does not have that weather.", "kindly")
	eq(City.srv_weather(80, "", Vector2.ZERO, -1).get("ok"), false, "so is a negative one")
	eq(City.rules.weather, 1, "the weather stays")
	var town: Dictionary = City.srv_weather(81, "", Vector2.ZERO, 2)
	eq(town.get("ok"), false, "a child in town cannot change the city's weather")
	eq(town.get("error"), "Take the tram to the city first.", "kindly")
	ok(City.srv_weather(80, "", Vector2.ZERO, 2).get("ok", false), "now night")
	_steps(10)   # 1 s into the change
	var t_now: float = City.rules.time
	var live: Dictionary = CityRules.weather_weights(City.rules, t_now)
	# A late arriver: I go to town and come back; the first state matches at the same time.
	_no_rest()
	await create_timer(1.1).timeout
	await _result(Session.travel("town"))
	ok(City.rules != null, "(the other child keeps the city awake)")
	var tt: float = City.rules.time
	var want: Dictionary = CityRules.weather_weights(City.rules, tt)
	_no_rest()
	await create_timer(1.1).timeout
	var got := []
	var cb := func(states): got.append(states)
	City.updated.connect(cb)
	await _result(Session.travel("city"))
	City.updated.disconnect(cb)
	ok(got.size() >= 1, "the late arriver gets a state at once")
	var st: Dictionary = got[0] if got.size() > 0 else City.states
	eq(st["weather"], 2, "the same weather")
	var have: Dictionary = CityRules.weather_weights(st, City.rules.time)
	var rules_now: Dictionary = CityRules.weather_weights(City.rules, City.rules.time)
	for k in ["sunny", "rain", "night"]:
		ok(absf(float(have[k]) - float(rules_now[k])) < 0.02, "the same %s weight (%.3f vs %.3f)" % [k, have[k], rules_now[k]])
	ok(live["night"] > 0.0 and want["night"] >= live["night"], "(the blend runs on)")
	Session.players.erase(80)
	Session.players.erase(81)
	City.advance(0.1)


# ------------------------------------------------------------- a late arriver, a leaver

func test_late_and_leave() -> void:
	await process_frame
	var me: int = Session.my_id
	_friend(76, "city", Vector2(-5.0, -6.0))
	City.on_space_changed(76)
	_friend(77, "city", CityMap.FERRIS["board_at"])
	City.on_space_changed(77)
	_at(76, CityMap.INTERACTIONS["cafe_seat_b"]["pos"])
	ok(_use(76, "cafe_seat_b").get("ok", false), "a child sits before the late one comes")
	City.rules.time = 30.0
	_at(77, CityMap.FERRIS["board_at"])
	var bg: Dictionary = City.srv_board(77, "", CityMap.FERRIS["board_at"])
	ok(bg.get("ok", false), "a rider before the late child comes")
	# I go to town; they stay; I come back.
	_no_rest()
	await create_timer(1.1).timeout
	var r := await _result(Session.travel("town"))
	ok(r.get("ok", false), "I leave for town")
	ok(City.rules != null, "the city goes on for the others")
	City.advance(0.5)
	var held_before: Dictionary = City.rules.occupancy.duplicate()
	var packed: PackedFloat64Array = City.rules.pack()
	_no_rest()
	await create_timer(1.1).timeout
	var got := []
	var cb := func(states): got.append(states)
	City.updated.connect(cb)
	City.set_physics_process(false)   # something in a journey turns the loop back on
	r = await _result(Session.travel("city"))
	City.set_physics_process(false)
	City.updated.disconnect(cb)
	ok(r.get("ok", false), "and come back")
	ok(got.size() >= 1, "the newest state reaches me at once")
	var s: Dictionary = got[0] if got.size() > 0 else {}
	eq(s.get("occupancy"), {"cafe_seat_b": 76}, "the same seat holder")
	eq(s.get("riders"), {int(bg["gondola"]): [77]}, "the same rider")
	ok(absf(float(s.get("time", 0.0)) - City.rules.time) < 0.5 and float(s.get("time", 0.0)) >= City.decode(packed)["time"], "the same clock, not a fresh one")
	ok(City.est_time() > 30.0, "est_time is the running city's")
	var want: Dictionary = City.decode(City.rules.pack())
	var same: bool = s.get("vehicles", []).size() == want["vehicles"].size()
	for i in mini(s.get("vehicles", []).size(), want["vehicles"].size()):
		var a: Dictionary = s["vehicles"][i]
		var b: Dictionary = want["vehicles"][i]
		same = same and a["dwell"] == b["dwell"] and (a["pos"] as Vector2).distance_to(b["pos"]) < 0.5
	ok(same, "the late child sees the same dwell and bus positions (state t=%.3f, now t=%.3f, %s)" % [s.get("time", 0.0), City.rules.time, str(City.is_physics_processing())])
	print("PACKET BYTES (a live state with a seat and a rider): %d" % (City.rules.pack().size() * 8))
	eq(held_before.size(), 1, "(sanity)")
	# A disconnect frees a seat at once and the sleeping stays right.
	Session._on_peer_disconnected(76)
	eq(City.occupant("cafe_seat_b"), -1, "a leaver's seat is free at once")
	Session._on_peer_disconnected(77)
	eq(City.riding(77), -1, "and a leaver's gondola place")
	_no_rest()
	await create_timer(1.1).timeout
	await _result(Session.travel("town"))
	ok(City.rules == null, "with everyone gone the city sleeps (%s)" % str(City.in_city(Session.players)))
