## Headless tests for the zoo's network side (docs/zoo-engineering-standard.md sections 3, 4 and 8):
## the Zoo autoload, the journey, the stale-state rule, stations, offers and the discovery log, run
## against the authority for real (a solo session). Real clients: scripts/net_test.py --zoo.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_net_tests.gd
## It reuses the helpers of puzzle_ride_tests.gd. Nothing here renders.
extends "res://tests/puzzle_ride_tests.gd"

const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")
const Places := preload("res://scripts/core/places.gd")
const Invites := preload("res://scripts/core/invites.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")

var Zoo: Node
var Animals: Node


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	Zoo = root.get_node("Zoo")
	Animals = root.get_node("Animals")
	for t in ["test_rules"]:
		_current = t
		call(t)
	Zoo.set_physics_process(false)   # the tests step the zoo themselves
	for t in ["test_travel", "test_stale_state", "test_stations", "test_offers", "test_found", "test_sleep", "test_kid_inputs",
			"test_toys", "test_arrival_slots", "test_visit_ends", "test_invite", "test_disconnect"]:
		_current = t
		await call(t)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nZOO NET TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


## The zoo steps `n` brain steps (0.1 s each); `each` is called before each one with the step number.
func _zsteps(n: int, each := Callable()) -> void:
	for i in n:
		if each.is_valid():
			each.call(i)
		Zoo.advance(ZooBrain.STEP + 0.0001)


func _state(peer := 0) -> Dictionary:
	return Session.players[peer if peer != 0 else Session.my_id]["state"]


func _travel(to: String) -> Dictionary:
	return await _result(Session.travel(to))


func _friend(peer: int, space: String, p: Vector2) -> void:
	Session.players[peer] = {"avatar": Avatar.sanitize(Avatar.PRESETS[(peer + 1) % 4]), "pid": ("%032x" % peer),
		"state": {"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"}}


func _no_rest() -> void:
	Session._last_journey.clear()
	Session._station_rest.clear()


# ------------------------------------------------------------- pure rules

func test_rules() -> void:
	eq(Session.PROTOCOL, 20, "protocol 20")
	ok(Invites.KINDS.has("zoo") and Invites.KINDS["zoo"] == "Come to the zoo with me", "the zoo invitation is on the list")
	eq(Invites.check("zoo", "town", 1, -99, 1000, "", "a"), "Take the tram to the zoo first, then invite your friends.", "invite to the zoo from town: refused")
	eq(Invites.check("zoo", "zoo", 1, -99, 1000, "", "a"), "", "invite to the zoo from the zoo")
	eq(Invites.check("fetch", "town", 1, -99, 1000, "", "a"), "", "the other invitations are unchanged")
	# Who hears about the zoo: only peers whose recorded space is the zoo.
	var players := {1: {"state": {"space": "zoo"}}, 2: {"state": {"space": "town"}}, 3: {"state": {"space": "zoo"}},
		4: {"state": {"space": "i1:0:0"}}, 5: {"state": {}}}
	eq(Zoo.in_zoo(players), [1, 3], "players in the zoo")
	eq(Zoo.recipients(players, [2, 3, 4, 5]), [3], "states go only to open peers in the zoo (not to the town, a cottage room or the unknown)")
	eq(Zoo.recipients(players, []), [], "and to nobody when no connection is open")
	eq(Zoo.recipients(players, [1, 2, 3]), [1, 3], "every open zoo peer")
	# The station rules the authority applies.
	eq(Session.STATION_REST, 1.2, "a station rests 1.2 s")
	eq(Session.JOURNEY_REST, 1.0, "a journey rests 1 s")
	eq(Session.OFFER_REACH, 3.5, "an offer reaches 3.5 m")
	eq(Session.STATION_SLACK, 0.4, "a station is believed 0.4 m beyond its reach")
	# est_time never runs backwards, and restarts with a new zoo.
	Zoo._reset()
	eq(Zoo.est_time(), 0.0, "no estimate before a state arrives")
	var b := ZooBrain.new(3)
	b.spawn()
	for i in 50:
		b.tick([])
	Zoo._apply(b.pack())
	ok(absf(Zoo.est_time() - b.time) < 0.2, "the estimate starts at the packet's time (%.2f vs %.2f)" % [Zoo.est_time(), b.time])
	var t1: float = Zoo.est_time()
	var older := ZooBrain.new(3)
	older.spawn()
	for i in 49:
		older.tick([])
	Zoo._apply(older.pack())
	ok(Zoo.est_time() >= t1, "a late packet does not set the clock back")
	var fresh := ZooBrain.new(4)
	fresh.spawn()
	Zoo._apply(fresh.pack())
	ok(Zoo.est_time() < 1.0, "a freshly woken zoo restarts the clock (%.2f)" % Zoo.est_time())
	eq(Zoo.states["animals"].size(), ZooMap.ORDER.size(), "the states have every resident")
	Zoo._apply(PackedFloat32Array([1.0, 2.0]))
	eq(Zoo.states["animals"].size(), ZooMap.ORDER.size(), "a malformed packet is ignored")
	# Hints and the log read from the model.
	var found_before: Dictionary = Zoo.found("giraffe")
	ok(typeof(found_before) == TYPE_DICTIONARY, "found() is a dictionary")
	_current = "test_rules"


# ------------------------------------------------------------- travel

func test_travel() -> void:
	await process_frame
	await _fresh_town("user://test_zoo_net.json")
	var me: int = Session.my_id
	eq(_state()["space"], "town", "the child starts in town")
	ok(Zoo.brain == null, "the zoo sleeps with nobody in it")
	# A bad destination, and one that is where the child already is.
	var r := await _travel("moon")
	eq(r.get("ok"), false, "a place that is not on the line is refused")
	eq(r.get("error"), "The tram does not go there from here.", "with a message")
	r = await _travel("town")
	eq(r.get("ok"), false, "town from town is refused")
	eq(_state()["space"], "town", "the child stays")
	# There.
	var got := []
	var cb := func(states): got.append(states)
	Zoo.updated.connect(cb)
	r = await _travel("zoo")
	Zoo.updated.disconnect(cb)
	ok(r.get("ok", false), "the tram goes to the zoo (%s)" % str(r))
	eq([r.get("space"), r.get("x"), r.get("z")], ["zoo", snappedf(ZooMap.ARRIVALS[0].x, 0.01), snappedf(ZooMap.ARRIVALS[0].y, 0.01)], "arrives on the platform, first place")
	ok(absf(float(r.get("ry", 0.0)) - snappedf(ZooMap.ARRIVAL_RY, 0.01)) < 0.001, "facing the zoo")
	eq(_state()["space"], "zoo", "the recorded space is the zoo")
	ok(Zoo.brain != null, "the first arrival wakes the zoo")
	ok(got.size() >= 1 and got[0]["animals"].size() == 18, "and the child gets the whole picture at once (%d updates)" % got.size())
	eq(Zoo.states["animals"].size(), 18, "18 residents in the states (zoo r2)")
	ok(Zoo.brain.time == 0.0, "the zoo wakes fresh")
	# Not again within a second, whatever the place.
	r = await _travel("town")
	eq(r.get("ok"), false, "a second journey within 1 s is refused")
	eq(_state()["space"], "zoo", "the child stays in the zoo")
	await create_timer(1.1).timeout
	r = await _travel("town")
	ok(r.get("ok", false), "after a second the tram goes back (%s)" % str(r))
	eq(_state()["space"], "town", "back in town")
	var board = TownModel.tram_stop_boarding(Session.model)
	ok(board is Vector2 and Vector2(r["x"], r["z"]).distance_to(board) < 0.02, "at the tram stop's boarding point (%s)" % str(board))
	ok(Zoo.brain == null, "the zoo sleeps again when the last child leaves")
	_current = "test_travel"
	# Journey bookkeeping goes with a disconnect.
	_friend(77, "town", Vector2(3, 3))
	Session._srv_travel(77, 0, "zoo")
	ok(Session._last_journey.has(77), "a journey is remembered")
	Session._on_peer_disconnected(77)
	ok(not Session._last_journey.has(77) and not Session.players.has(77), "and forgotten when the child leaves")
	# The seat and the locks are left on the way.
	var chair := await _place("chair", Vector2(6, 12))
	Session._last_journey.clear()
	ok((await _result(Session.lock(chair))).get("ok", false), "a lock is taken")
	eq(Session.lock_holder(chair), me, "held")
	r = await _travel("zoo")
	ok(r.get("ok", false), "off to the zoo")
	eq(Session.lock_holder(chair), 0, "the lock was given back on the way")
	_no_rest()
	await _travel("town")


# ------------------------------------------------------------- the stale-state rule

func test_stale_state() -> void:
	await process_frame
	_no_rest()
	var me: int = Session.my_id
	var r := await _travel("zoo")
	ok(r.get("ok", false), "to the zoo")
	var arrival := Vector2(_state()["x"], _state()["z"])
	# A late town packet cannot pull the child back.
	_go("town", Vector2(-3, 9))
	eq([_state()["space"], _state()["x"], _state()["z"]], ["zoo", arrival.x, arrival.y], "a town state after a journey to the zoo is dropped")
	_go("i1:0:0", Vector2(0, 0))
	eq(_state()["space"], "zoo", "so is a cottage room's (a room belongs to the town)")
	_go("nowhere", Vector2(0, 0))
	eq(_state()["space"], "zoo", "and an unknown space (it would read as town)")
	_go("zoo", Vector2(2.0, 20.0))
	eq([_state()["space"], _state()["x"], _state()["z"]], ["zoo", 2.0, 20.0], "a zoo state moves the child")
	_no_rest()
	r = await _travel("town")
	ok(r.get("ok", false), "back to town")
	_go("zoo", Vector2(2.0, 20.0))
	eq(_state()["space"], "town", "a zoo state after a journey to town is dropped")
	# Between a map and its rooms stays allowed.
	var house := ""
	for id in Session.model.items:
		if Session.model.items[id]["kind"] == "cottage":
			house = id
			break
	ok(house != "", "the town has a cottage")
	if house != "":
		var room: String = TownModel.room_space(house, 0, 0)
		_go(room, Vector2(0, 0))
		eq(_state()["space"], room, "walking into a cottage room is allowed")
		_go("town", Vector2(0, 9))
		eq(_state()["space"], "town", "and out again")
		# From a cottage room the tram is still reachable.
		_go(room, Vector2(0, 0))
		_no_rest()
		r = await _travel("zoo")
		ok(r.get("ok", false), "the tram can be asked for from a room")
		eq(_state()["space"], "zoo", "and takes the child to the zoo")
		_no_rest()
		await _travel("town")
	_current = "test_stale_state"
	eq(me, Session.my_id, "still me")


# ------------------------------------------------------------- stations

func test_stations() -> void:
	await process_frame
	_no_rest()
	await _travel("zoo")
	var st: Dictionary = ZooMap.STATIONS["savanna_pump"]
	var spot: Vector2 = st["pos"]
	# From the platform it is far.
	var r := await _result(Zoo.use("savanna_pump"))
	eq(r.get("ok"), false, "a station out of reach is refused")
	eq(r.get("error"), "Walk closer first.", "with a message")
	r = await _result(Zoo.use("no_such_station"))
	eq(r.get("ok"), false, "an unknown station is refused")
	# Just beyond reach plus the slack, and just within it.
	_go("zoo", spot + Vector2(ZooMap.STATION_REACH + 0.5, 0))
	r = await _result(Zoo.use("savanna_pump"))
	eq(r.get("ok"), false, "1.8 + 0.5 m is out of reach")
	_go("zoo", spot + Vector2(ZooMap.STATION_REACH + 0.3, 0))
	var seen := []
	var fx := func(kind, at, who): seen.append([kind, at, who])
	Zoo.effect.connect(fx)
	r = await _result(Zoo.use("savanna_pump"))
	ok(r.get("ok", false), "1.8 + 0.3 m is in reach (%s)" % str(r))
	eq(r.get("station"), "savanna_pump", "the reply names the station")
	Zoo.advance(ZooBrain.STEP + 0.0001)
	ok(seen.any(func(e): return e[0] == "pump"), "the pump's effect reached this screen (%s)" % str(seen))
	# It rests for 1.2 s.
	r = await _result(Zoo.use("savanna_pump"))
	eq(r.get("ok"), false, "a second use at once is refused: the station rests")
	await create_timer(0.6).timeout
	r = await _result(Zoo.use("savanna_pump"))
	eq(r.get("ok"), false, "still resting after 0.6 s")
	await create_timer(0.7).timeout
	r = await _result(Zoo.use("savanna_pump"))
	ok(r.get("ok", false), "after 1.3 s it answers again (%s)" % str(r))
	# Another station does not share the rest.
	_go("zoo", ZooMap.STATIONS["splash_shower"]["pos"] + Vector2(1.0, 0))
	r = await _result(Zoo.use("splash_shower"))
	ok(r.get("ok", false), "a different station is not resting (%s)" % str(r))
	Zoo.effect.disconnect(fx)
	# Not from town.
	_no_rest()
	await _travel("town")
	r = await _result(Zoo.use("savanna_pump"))
	eq(r.get("ok"), false, "stations are for the zoo")
	eq(r.get("error"), "Take the tram to the zoo first.", "with a message")
	_current = "test_stations"


# ------------------------------------------------------------- offers

func test_offers() -> void:
	await process_frame
	_no_rest()
	await _travel("zoo")
	var r := await _result(Zoo.offer("rory"))
	eq(r.get("ok"), false, "a treat for an animal across the zoo is refused")
	eq(r.get("error"), "Walk closer to offer a treat.", "with a message")
	r = await _result(Zoo.offer("nobody"))
	eq(r.get("ok"), false, "an offer to nobody is refused")
	var a: Dictionary = Zoo.brain.animal("rory")
	var p: Vector3 = Zoo.brain.pos_of(a)
	_go("zoo", Vector2(p.x, p.z) + Vector2(3.2, 0))
	r = await _result(Zoo.offer("rory"))
	ok(r.get("ok", false), "within 3.5 m a treat is taken (%s)" % str(r))
	eq(r.get("animal"), "rory", "the reply names the animal")
	var here := Vector2(p.x, p.z) + Vector2(3.8, 0)
	_go("zoo", here)
	r = await _result(Zoo.offer("honey"))
	var hp: Vector3 = Zoo.brain.pos_of(Zoo.brain.animal("honey"))
	if Vector2(hp.x, hp.z).distance_to(here) > Session.OFFER_REACH:
		eq([r.get("ok"), r.get("error")], [false, "Walk closer to offer a treat."], "a treat for a different animal is judged by that animal's distance")
	else:
		ok(r.get("ok", false), "honey happens to be within reach too")
	_no_rest()
	await _travel("town")
	r = await _result(Zoo.offer("rory"))
	eq(r.get("ok"), false, "a treat needs the zoo")
	_current = "test_offers"


# ------------------------------------------------------------- the discovery log

func test_found() -> void:
	await process_frame
	if not ("maps" in Session.model):
		print("SKIP test_found: the town model has no `maps` yet (worker W1)")
		return
	_no_rest()
	Session.model.maps = {}
	var me: int = Session.my_id
	var nick: String = Session.nick_of(me)
	await _travel("zoo")
	_friend(77, "zoo", ZooMap.STATIONS["savanna_pump"]["pos"] + Vector2(4.0, 0.0))   # 4 m away
	_friend(78, "zoo", ZooMap.STATIONS["savanna_pump"]["pos"] + Vector2(20.0, 0.0))  # 20 m away
	_friend(79, "town", ZooMap.STATIONS["savanna_pump"]["pos"])                      # in town: not there at all
	_go("zoo", ZooMap.STATIONS["savanna_pump"]["pos"] + Vector2(1.0, 0))
	var changes := [0]
	var cb := func(): changes[0] += 1
	Zoo.found_changed.connect(cb)
	var datas := []
	var dcb := func(key): datas.append(key)
	Session.town_data_changed.connect(dcb)
	Session.dirty = false
	eq(Zoo.found("giraffe"), {}, "nothing found yet")
	eq(Zoo.hint("giraffe"), ZooLife.ANSWERS["giraffe"]["bow"], "the first hint is the first answer")
	var r := await _result(Zoo.use("savanna_pump"))
	ok(r.get("ok", false), "the pump works (%s)" % str(r))
	Zoo.advance(ZooBrain.STEP + 0.0001)
	await process_frame
	var fg: Dictionary = Zoo.found("giraffe")
	ok(fg.has("drink"), "the answer is recorded (%s)" % str(Session.model.maps))
	var names: Array = fg.get("drink", {}).get("by", [])
	names.sort()
	var want := [nick, Session.nick_of(77)]
	want.sort()
	eq(names, want, "with the names of the children within 8 m (not 20 m, not in town)")
	ok(int(fg.get("drink", {}).get("t", 0)) > 1700000000, "and the time")
	ok(Session.dirty, "the town is marked to be saved")
	# zoo r2: the pump also sends Mabel to spray, which is a discovery of its own; each recorded answer is
	# announced exactly once.
	var recorded := 0
	for sp in Session.model.maps.get("zoo", {}).get("found", {}):
		recorded += (Session.model.maps["zoo"]["found"][sp] as Dictionary).size()
	ok(datas.has("maps") and changes[0] == recorded and recorded >= 1, "everyone is told once per answer (%s, %d told, %d recorded)" % [str(datas), changes[0], recorded])
	var base: int = changes[0]
	eq(Zoo.hint("giraffe"), ZooLife.ANSWERS["giraffe"]["bow"], "the hint for 'bow' still comes first")
	# Once per species and answer: the same answer again changes nothing.
	await create_timer(1.3).timeout
	var t0: int = int(fg["drink"]["t"])
	r = await _result(Zoo.use("savanna_pump"))
	Zoo.advance(ZooBrain.STEP + 0.0001)
	await process_frame
	eq(Zoo.found("giraffe")["drink"]["by"].size(), names.size(), "a second drink is not written again")
	eq([int(Zoo.found("giraffe")["drink"]["t"]), changes[0]], [t0, base], "nor announced again")
	# Another answer is recorded as its own.
	Zoo.brain.events.append({"kind": "found", "species": "giraffe", "answer": "bow", "at": Vector3(0, 0, 0)})
	Zoo.advance(ZooBrain.STEP + 0.0001)
	eq(Zoo.found("giraffe").keys().size(), 2, "a new answer is added")
	eq(Zoo.hint("giraffe"), ZooLife.ANSWERS["giraffe"]["treat"], "and the hint moves on to the next")
	eq(changes[0], base + 1, "announced")
	Zoo.brain.events.append({"kind": "found", "species": "giraffe", "answer": "treat", "at": Vector3(0, 0, 0)})
	Zoo.advance(ZooBrain.STEP + 0.0001)
	eq(Zoo.hint("giraffe"), "", "nothing left to hint when all are found")
	eq(Zoo.hint("unicorn"), "", "no hint for an unknown species")
	# No children near at all: still recorded, with nobody's name.
	Zoo.brain.events.append({"kind": "found", "species": "lion", "answer": "roar", "at": Vector3(-30.0, 0, -30.0)})
	Zoo.advance(ZooBrain.STEP + 0.0001)
	eq(Zoo.found("lion").get("roar", {}).get("by"), [], "far from everyone: recorded with no names")
	Zoo.found_changed.disconnect(cb)
	Session.town_data_changed.disconnect(dcb)
	Session.model.maps = {}
	Session.players.erase(77)
	Session.players.erase(78)
	Session.players.erase(79)
	_no_rest()
	await _travel("town")
	_current = "test_found"


# ------------------------------------------------------------- the zoo sleeps when empty

func test_sleep() -> void:
	await process_frame
	_no_rest()
	Session.players[Session.my_id]["state"]["space"] = "town"
	Zoo.advance(0.2)
	ok(Zoo.brain == null, "nobody in the zoo: no brain")
	await _travel("zoo")
	var first = Zoo.brain
	ok(first != null, "woken by the first arrival")
	_zsteps(120)
	ok(first.time > 11.0, "it runs while someone is there (%.1f s)" % first.time)
	var pack_time: float = Zoo.states["time"]
	ok(pack_time > 5.0, "and the child's states follow along (%.1f)" % pack_time)
	_no_rest()
	await _travel("town")
	ok(Zoo.brain == null, "dropped when the last child leaves")
	var events_before: int = Zoo.states["animals"].size()
	Zoo.advance(5.0)
	ok(Zoo.brain == null, "an empty zoo costs nothing: it stays asleep")
	eq(events_before, ZooMap.ORDER.size(), "(the last picture is kept for the screen)")
	await create_timer(1.1).timeout
	await _travel("zoo")
	var second = Zoo.brain
	ok(second != null and second != first and second.time == 0.0, "woken afresh, with a new brain at time 0")
	ok(Zoo.est_time() < 1.0, "the clock restarted (%.2f)" % Zoo.est_time())
	_no_rest()
	await _travel("town")
	_current = "test_sleep"


# ------------------------------------------------------------- what the brain is told about the children

func test_kid_inputs() -> void:
	await process_frame
	_no_rest()
	await _travel("zoo")
	_zsteps(1)
	eq(Zoo.kid_inputs().size(), 1, "one child in the zoo")
	_go("zoo", Vector2(0.0, 24.0))
	_zsteps(25)
	var k: Dictionary = Zoo.kid_inputs()[0]
	eq(k["id"], Session.my_id, "the peer")
	ok(k["still"] >= 2.0 and k["speed"] < 0.1 and k["run"] == 0.0, "standing: still %.1f, speed %.2f, run %.1f" % [k["still"], k["speed"], k["run"]])
	ok(k["pos"] == Vector2(0.0, 24.0), "at its place")
	# Walk at 1 m/s, then run at 4 m/s.
	var x := [0.0]
	var walk := func(_i):
		x[0] += 0.1
		_go("zoo", Vector2(x[0], 24.0))
	_zsteps(30, walk)
	k = Zoo.kid_inputs()[0]
	ok(k["still"] < 0.2, "walking: not still (%.2f)" % k["still"])
	ok(absf(k["speed"] - 1.0) < 0.1, "speed smoothed to about 1 m/s (%.2f)" % k["speed"])
	ok(absf((k["vel"] as Vector2).x - 1.0) < 0.1 and absf((k["vel"] as Vector2).y) < 0.05, "velocity points east (%s)" % str(k["vel"]))
	eq(k["run"], 0.0, "no running metres at a walk")
	var run := func(_i):
		x[0] += 0.4
		_go("zoo", Vector2(fmod(x[0], 8.0) + 0.0, 24.0))
	_zsteps(25, run)   # 2.5 s at 4 m/s (the wrap back is a jump and is not counted)
	k = Zoo.kid_inputs()[0]
	ok(k["speed"] > 2.5, "speed smoothed up (%.2f)" % k["speed"])
	ok(k["run"] > 3.0 and k["run"] < 9.0, "the last 2 s covered about 8 m at a run (%.2f)" % k["run"])
	_go("zoo", Vector2(fmod(x[0], 8.0), 24.0))
	_zsteps(30)
	k = Zoo.kid_inputs()[0]
	ok(k["run"] == 0.0 and k["still"] > 2.0, "stopped: the run count empties after 2 s (run %.2f, still %.2f)" % [k["run"], k["still"]])
	# A small shuffle (under 5 cm) is still standing.
	var base: Vector2 = Vector2(fmod(x[0], 8.0), 24.0)
	_go("zoo", base + Vector2(0.03, 0.0))
	_zsteps(3)
	ok(Zoo.kid_inputs()[0]["still"] > 0.3, "3 cm is not moving")
	_go("zoo", base + Vector2(0.5, 0.0))
	_zsteps(1)
	ok(Zoo.kid_inputs()[0]["still"] == 0.0, "50 cm is")
	# Emotes come from the session's signal.
	Session.send_emote("cheer")
	k = Zoo.kid_inputs()[0]
	eq(k["emote"], "cheer", "the last emote")
	ok(float(k["emote_t"]) > 0.0, "and when it was")
	Zoo._emotes[Session.my_id] = ["wave", Time.get_ticks_msec() / 1000.0 - 5.0]
	eq(Zoo.kid_inputs()[0]["emote"], "", "an emote older than 3 s is not offered again")
	# A child in town is not an input.
	_friend(77, "town", Vector2(1, 1))
	eq(Zoo.kid_inputs().size(), 1, "children in town are not the brain's business")
	Session.players.erase(77)
	_no_rest()
	await _travel("town")
	_current = "test_kid_inputs"


# ------------------------------------------------------------- toys

func test_toys() -> void:
	await process_frame
	_no_rest()
	var m: Variant = Session.model
	m.items["zt1"] = {"id": "zt1", "kind": "zoo_ball", "space": "zoo", "x": 10.0, "z": 2.0, "rot": 0, "color": -2}
	m.items["zt2"] = {"id": "zt2", "kind": "zoo_box", "space": "zoo", "x": -4.0, "z": 5.5, "rot": 0, "color": -2}
	eq(Zoo.toys_from_model(), [{"kind": "zoo_ball", "pos": Vector2(10.0, 2.0)}, {"kind": "zoo_box", "pos": Vector2(-4.0, 5.5)}], "the zoo's toys are the model's zoo items")
	await _travel("zoo")
	eq(Zoo.brain.toys.size(), 2, "the woken brain has them")
	m.items["zt3"] = {"id": "zt3", "kind": "hay_bale", "space": "zoo", "x": 3.0, "z": 3.0, "rot": 0, "color": -2}
	Session.town_changed.emit()
	eq(Zoo.brain.toys.size(), 3, "an edit refreshes them")
	for id in ["zt1", "zt2", "zt3"]:
		m.items.erase(id)
	Session.town_changed.emit()
	eq(Zoo.brain.toys, [], "and putting them away empties the list")
	_no_rest()
	await _travel("town")
	_current = "test_toys"


# ------------------------------------------------------------- arrival places

func test_arrival_slots() -> void:
	await process_frame
	_no_rest()
	await _travel("zoo")
	var me: int = Session.my_id
	eq(Vector2(_state()["x"], _state()["z"]), Vector2(snappedf(ZooMap.ARRIVALS[0].x, 0.01), snappedf(ZooMap.ARRIVALS[0].y, 0.01)), "the first child takes place 0")
	_friend(77, "town", Vector2(0, 9))
	_friend(78, "town", Vector2(1, 9))
	_friend(79, "town", Vector2(2, 9))
	Session._srv_travel(77, 0, "zoo")
	Session._srv_travel(78, 0, "zoo")
	Session._srv_travel(79, 0, "zoo")
	var xs := []
	for p in [me, 77, 78, 79]:
		xs.append(_state(p)["x"])
	xs.sort()
	eq(xs, [-1.5, -0.5, 0.5, 1.5], "four children take the four places")
	var here: Array = Zoo.in_zoo(Session.players)
	var all4 := [me, 77, 78, 79]
	all4.sort()
	eq(here, all4, "all four are in the zoo")
	# One leaves, the next arrival takes the freed place.
	Session._last_journey.erase(78)
	var freed: float = _state(78)["x"]
	Session._srv_travel(78, 0, "town")
	_friend(80, "town", Vector2(0, 9))
	Session._srv_travel(80, 0, "zoo")
	eq(_state(80)["x"], freed, "a freed place is used first")
	eq(_state(78)["space"], "town", "the child who left is in town")
	for p in [77, 78, 79, 80]:
		Session._on_peer_disconnected(p)
	_no_rest()
	await _travel("town")
	_current = "test_arrival_slots"


# ------------------------------------------------------------- a house visit ends at the tram

func test_visit_ends() -> void:
	await process_frame
	_no_rest()
	var me: int = Session.my_id
	Animals.guests = {"dog": me}
	Animals._guest_space = {"dog": "town"}
	var r := await _travel("zoo")
	ok(r.get("ok", false), "to the zoo with a visitor")
	eq(r.get("waits"), "Biscuit", "the reply names the visitor who waits in town (the client says it in its language)")
	ok(Animals.guests.is_empty(), "the visit is over")
	_no_rest()
	r = await _travel("town")
	ok(not r.has("waits"), "no visitor named when nobody was visiting")
	_current = "test_visit_ends"


# ------------------------------------------------------------- invitations

func test_invite() -> void:
	await process_frame
	_no_rest()
	var me: int = Session.my_id
	_friend(77, "town", Vector2(0, 9))
	var r := await _result(Session.send_invite("zoo", ""))
	eq(r.get("ok"), false, "from town nobody is invited to the zoo")
	await _travel("zoo")
	Session._last_invite.clear()
	r = await _result(Session.send_invite("zoo", ""))
	ok(r.get("ok", false) and r.get("sent") == 1, "from the zoo the friend gets a card (%s)" % str(r))
	var card: Dictionary = Session.inbox.get(77, {}).get(Session.pid_of(me), {})
	ok(card.get("kind") == "zoo" and card.get("space") == "zoo", "the card says the zoo and where (%s)" % str(card))
	Session.players.erase(77)
	_no_rest()
	await _travel("town")
	_current = "test_invite"


# ------------------------------------------------------------- a drop

func test_disconnect() -> void:
	await process_frame
	_no_rest()
	_friend(77, "zoo", Vector2(0.0, 26.0))
	Zoo.advance(0.2)
	ok(Zoo.brain != null, "a friend in the zoo wakes it, even when the local child is in town")
	ok(not Zoo.in_zoo(Session.players).has(Session.my_id), "(and I am in town)")
	Session._on_peer_disconnected(77)
	ok(Zoo.brain == null, "the friend's drop sends the zoo to sleep")
	_friend(78, "zoo", Vector2(0.0, 26.0))
	Session._srv_state(78, {"space": "town", "x": 0.0, "z": 9.0, "ry": 0.0, "anim": "idle"})
	eq(Session.players[78]["state"]["space"], "zoo", "a late town packet cannot take a child out of the zoo")
	Session.players.erase(78)
	Zoo.advance(0.2)
	_current = "test_disconnect"
