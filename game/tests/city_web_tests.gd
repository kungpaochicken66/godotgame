## Headless tests for the web city's Godot side (design/city-threejs.md section 6): the map "city_web" with
## the same CityMap, rules, navigation and interactions as the Godot city, its own shared state (the CityWeb
## autoload), and the controller API the page bridge calls (web_tap, web_act, web_weather, web_home, web_ctx).
## Nothing of the Godot city is built for it: a logic-only CityWorld answers the seat and gondola poses.
##   scripts/godot.sh --headless --path game -s res://tests/city_web_tests.gd
##   scripts/godot.sh --headless --path game -s res://tests/city_web_tests.gd -- --web-city   (the desktop flag)
## Two real clients in the two city maps: scripts/net_test.py --city-web.
extends "res://tests/puzzle_ride_tests.gd"

const CityRules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")
# The world, the controller and the HUD name autoloads, so they are loaded at run time (as run_tests.gd does).
var TownWorld: GDScript

var City: Node
var CityWeb: Node
var _flag := false
var _env_before := ""
var _tv_before := -1
var _effects: Array = []
var _hints: Array = []
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	City = root.get_node("City")
	CityWeb = root.get_node("CityWeb")
	_flag = OS.get_cmdline_user_args().has("--web-city")
	_env_before = OS.get_environment(Places.WEB_CITY_ENV)
	_tv_before = TvMode.forced
	TownWorld = load("res://scripts/world/town_world.gd")
	await process_frame   # the autoloads are in the tree (CityWeb knows its map) and nodes have global transforms
	for t in ["test_places", "test_instances", "test_logic_world"]:
		_current = t
		call(t)
	for t in ["test_authority", "test_controller"]:
		_current = t
		await call(t)
	TvMode.forced = _tv_before
	if _env_before == "":
		OS.unset_environment(Places.WEB_CITY_ENV)
	else:
		OS.set_environment(Places.WEB_CITY_ENV, _env_before)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nCITY WEB TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _env(on: bool) -> void:
	OS.set_environment(Places.WEB_CITY_ENV, "1" if on else "0")


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


func _no_rest() -> void:
	Session._last_journey.clear()


func _until(cond: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await physics_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout:
			return false
	return true


func _xf_near(a: Transform3D, b: Transform3D, tol := 0.02) -> bool:
	return a.origin.distance_to(b.origin) < tol and (a.basis.x - b.basis.x).length() < tol and (a.basis.z - b.basis.z).length() < tol


# ------------------------------------------------------------- the places registry (pure)

func test_places() -> void:
	ok(Places.MAPS.has(Places.CITY_WEB) and Places.is_map("city_web"), "city_web is a map")
	ok(Places.is_city("city") and Places.is_city("city_web") and not Places.is_city("town") and not Places.is_city("zoo") and not Places.is_city("i1:0:0"),
		"is_city: the two city maps and nothing else")
	eq(Places.map_of("city_web"), "city_web", "its own map")
	eq(Places.DESTINATIONS[Places.TOWN], ["zoo", "city", "city_web", "thousand"], "the town's tram goes to the zoo, the city, the web city and Thousand Town")
	eq(Places.DESTINATIONS[Places.CITY_WEB], ["town"], "the web city goes home only")
	eq(Places.DESTINATIONS[Places.CITY], ["town"], "the city is unchanged")
	eq(Places.NAMES[Places.CITY_WEB], "City (web)", "its name")
	eq(Places.half("city_web"), CityMap.HALF, "the city's ground")
	eq(Places.arrival("city_web", 1), CityMap.ARRIVALS[1], "the city's arrival places")
	ok(not Places.can_decorate("city_web") and not Places.can_decorate("city") and Places.can_decorate("town"), "no toy box in either city")
	eq(Places.music("city_web"), Places.music("city"), "the city's music")
	# availability: a client-side offer
	TvMode.forced = 0
	OS.unset_environment(Places.WEB_CITY_ENV)
	eq(Places.available(Places.CITY_WEB), _flag, "a desktop without LANTERN_WEB_CITY offers the web city only with --web-city (flag given: %s)" % _flag)
	_env(true)
	ok(Places.available(Places.CITY_WEB), "LANTERN_WEB_CITY=1 offers it on a desktop")
	eq(Places.offered(Places.TOWN), ["zoo", "city", "city_web", "thousand"], "and the town's tram stop lists it")
	_env(false)
	eq(Places.available(Places.CITY_WEB), _flag, "LANTERN_WEB_CITY=0 does not")
	_env(true)
	TvMode.forced = 1
	ok(not Places.available(Places.CITY_WEB), "never on a TV (--tv), even with the switch and the flag")
	eq(Places.offered(Places.TOWN), ["zoo", "city", "thousand"], "a TV's tram stop lists the zoo, the city and Thousand Town")
	ok(Places.available("town") and Places.available("zoo") and Places.available("city"), "the other maps are offered everywhere")
	TvMode.forced = 0
	ok(not Places.available("nowhere") and not Places.available("i1:0:0"), "not a map: never offered")
	eq(Places.offered(Places.CITY_WEB), ["town"], "from the web city: home")
	# dest-fix r1: where things can be placed. The cities are visited, not decorated (the user's acceptance on the
	# installed r3); the town, the zoo and cottage rooms are.
	ok(Places.decoratable("town") and Places.decoratable("zoo") and Places.decoratable("i1:0:0"), "the town, the zoo and a cottage room can be decorated")
	ok(not Places.decoratable(Places.CITY) and not Places.decoratable(Places.CITY_WEB), "neither city can")
	var Catalog = load("res://scripts/core/catalog.gd")
	var offered_in_cities := 0
	for kind in Catalog.ITEMS:
		if Catalog.allowed_in(kind, Places.CITY) or Catalog.allowed_in(kind, Places.CITY_WEB):
			offered_in_cities += 1
	eq(offered_in_cities, 0, "the toy box offers nothing in either city (it offered the indoor furniture)")


# ------------------------------------------------------------- two City instances (pure)

func test_instances() -> void:
	eq(City.map, "city", "City serves the city")
	eq(CityWeb.map, "city_web", "CityWeb serves the web city")
	eq(City.map_for_name("CityWeb"), "city_web", "the map comes from the node name")
	eq(City.map_for_name("City"), "city", "(City)")
	ok(City.get_path() != CityWeb.get_path() and City.get_script() == CityWeb.get_script(), "one script, two node paths (separate RPCs)")
	var players := {1: {"state": {"space": "city"}}, 2: {"state": {"space": "city_web"}}, 3: {"state": {"space": "town"}},
		4: {"state": {"space": "city_web", "level": "gym_roof"}}, 5: {"state": {"space": "zoo"}}, 6: {"state": {"space": "i1:0:0"}}, 7: {"state": {}}}
	eq(City.in_city(players), [1], "the city's children")
	eq(CityWeb.in_city(players), [2, 4], "the web city's children")
	eq(City.recipients(players, [1, 2, 3, 4, 5]), [1], "the city's states go only to the city's open peers")
	eq(CityWeb.recipients(players, [1, 2, 3, 5]), [2], "the web city's only to its own")
	eq(Session.city_of("city"), City, "a city request from the city goes to City")
	eq(Session.city_of("city_web"), CityWeb, "from the web city to CityWeb")
	eq(Session.city_of("town"), null, "from town to none")
	eq(Session.city_nodes(), [City, CityWeb], "both instances run")
	eq(Session.PROTOCOL, 20, "protocol 20")


# ------------------------------------------------------------- the logic-only CityWorld (pure plus one build)

func test_logic_world() -> void:
	var fake := [37.25]
	var logic: Node3D = CityWorld.new()
	logic.clock = func() -> float: return float(fake[0])
	ok(not logic._built and logic.get_child_count() == 0, "the logic world is not built")
	ok(is_equal_approx(logic.ferris_angle_now(), CityWorld.ferris_angle_at(37.25)), "its wheel angle runs on its clock, unbuilt")
	var built: Node3D = CityWorld.new()
	root.add_child(built)
	built.build()
	built.clock = func() -> float: return float(fake[0])
	built._process(0.016)
	var angle: float = logic.ferris_angle_now()
	ok(is_equal_approx(built.ferris_angle_now(), angle), "the same wheel angle as the drawn wheel")
	var bad := []
	for g in int(CityMap.FERRIS["gondolas"]):
		if not built.gondolas[g].transform.is_equal_approx(logic.gondola_transform(g, angle)):
			bad.append("gondola %d" % g)
		for slot in 2:
			var a: Transform3D = logic.rider_transform(g, angle, slot)
			var b: Transform3D = built.rider_transform(g, built.ferris_angle_now(), slot)
			if not a.is_equal_approx(b):
				bad.append("rider %d/%d" % [g, slot])
			# the rider sits in the drawn gondola: its pivot less the hang, half a metre to the side
			var pivot: Vector3 = built.gondolas[g].global_transform.origin
			if a.origin.distance_to(pivot + Vector3(-0.5 if slot == 0 else 0.5, -float(CityMap.FERRIS["hang"]), 0.0)) > 0.001:
				bad.append("rider %d/%d off the drawn gondola" % [g, slot])
	for key in CityMap.INTERACTIONS:
		if not (logic.seat_transform(key) as Transform3D).is_equal_approx(built.seat_transform(key)):
			bad.append("seat " + key)
	eq(bad, [], "the logic world's rider and seat transforms equal the built city's")
	for i in 30:
		fake[0] += 0.016   # the clock runs at the frame rate: the drawn wheel keeps up with it
		built._process(0.016)
	ok(built.gondolas[3].transform.is_equal_approx(logic.gondola_transform(3, logic.ferris_angle_now())), "and stay equal as the clock runs")
	built.free()
	logic.free()


# ------------------------------------------------------------- the authority (solo), stepped by hand

func test_authority() -> void:
	await process_frame
	await _fresh_town("user://test_city_web_net.json")
	City.set_physics_process(false)
	CityWeb.set_physics_process(false)
	var me: int = Session.my_id
	CityWeb.effect.connect(func(kind, data): _effects.append(["web", kind, data]))
	City.effect.connect(func(kind, data): _effects.append(["city", kind, data]))
	ok(City.rules == null and CityWeb.rules == null, "both cities sleep")
	# The authority accepts the journey whatever this device offers (availability is a client-side offer).
	TvMode.forced = 1
	_env(false)
	var web_got := []
	var city_got := []
	var web_cb := func(states): web_got.append(states)
	var city_cb := func(states): city_got.append(states)
	CityWeb.updated.connect(web_cb)
	City.updated.connect(city_cb)
	var r := await _result(Session.travel("city_web"))
	TvMode.forced = 0
	ok(r.get("ok", false) and r.get("space") == "city_web", "the tram goes to the web city (%s)" % str(r))
	eq(Vector2(float(r.get("x", 0)), float(r.get("z", 0))), CityMap.ARRIVALS[0], "at the city's first arrival place")
	ok(CityWeb.rules != null and City.rules == null, "the first arrival wakes the web city only")
	ok(web_got.size() >= 1 and (web_got[0]["vehicles"] as Array).size() == CityMap.VEHICLES.size(), "and the child gets the web city's picture at once")
	eq(city_got.size(), 0, "nothing of the city")
	# a friend in the Godot city
	_friend(90, "city", CityMap.INTERACTIONS["cafe_seat_a"]["pos"])
	City.on_space_changed(90)
	ok(City.rules != null, "a friend wakes the city")
	_friend(91, "city_web", CityMap.ARRIVALS[1])
	CityWeb.on_space_changed(91)
	eq(City.recipients(Session.players, [90, 91]), [90], "the city's states go to the friend in the city")
	eq(CityWeb.recipients(Session.players, [90, 91]), [91], "the web city's to the friend in the web city")
	# The same seat: taken in the city, free in the web city.
	var sa: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	var a: Dictionary = City.srv_use(90, "", sa, "cafe_seat_a")
	ok(a.get("ok", false) and a.get("hold", false), "the friend sits at the city's cafe (%s)" % str(a))
	_at(me, sa + Vector2(0.3, 0.0))
	var mine := await _result(Session.city_use("cafe_seat_a"))
	ok(mine.get("ok", false) and mine.get("hold", false), "the same seat is free in the web city: my request goes to CityWeb (%s)" % str(mine))
	eq(CityWeb.occupant("cafe_seat_a"), me, "the web city's state shows me")
	eq(City.decode(City.rules.pack())["occupancy"], {"cafe_seat_a": 90}, "the city's shows the friend")
	eq(CityWeb.decode(CityWeb.rules.pack())["occupancy"], {"cafe_seat_a": me}, "two separate states")
	var fr: Dictionary = CityWeb.srv_use(91, "", sa + Vector2(0.4, 0.0), "cafe_seat_a")
	eq(fr.get("error"), "Someone is sitting there.", "a friend in the web city is refused my seat")
	# Weather in one does not change the other.
	_effects.clear()
	var w := await _result(Session.city_weather(2))
	ok(w.get("ok", false) and w.get("weather") == 2, "I choose night in the web city (%s)" % str(w))
	eq(CityWeb.rules.weather, 2, "the web city is at night")
	eq(City.rules.weather, 0, "the city stays sunny")
	eq(CityWeb.states["weather"], 2, "and my state shows it")
	ok(_effects.any(func(e): return e[0] == "web" and e[1] == "weather") and not _effects.any(func(e): return e[0] == "city"), "the weather event comes from the web city only")
	ok(City.srv_weather(90, "", sa, 1).get("ok", false), "the friend chooses rain in the city")
	eq(CityWeb.rules.weather, 2, "the web city stays at night")
	# States go only to that map's peers: stepping the city does not reach me, stepping the web city does.
	city_got.clear()
	web_got.clear()
	for i in 12:
		City.advance(0.1)
		CityWeb.advance(0.1)
	eq(city_got.size(), 0, "1.2 s of the city: nothing reaches the child in the web city")
	ok(web_got.size() >= 4, "and the web city's states do (%d)" % web_got.size())
	eq(City.states, City.empty_state(), "my City state is still the empty shape")
	# Routing: a request from town reaches no city; a level is kept in the web city.
	Session.send_state({"space": "city_web", "x": 10.0, "z": -12.2, "ry": 0.0, "anim": "idle", "level": "gym_roof"})
	await process_frame
	eq(str(Session.players[me]["state"].get("level", "")), "gym_roof", "the web city keeps the level a child stands on")
	Session.send_state({"space": "city_web", "x": sa.x + 0.3, "z": sa.y, "ry": 0.0, "anim": "sit"})
	await process_frame
	# the web city cannot go to the city directly
	_no_rest()
	var cross := await _result(Session.travel("city"))
	eq(cross.get("error"), "The tram does not go there from here.", "no journey from the web city to the city")
	# Home: the seat is freed and the web city sleeps when its last child leaves.
	Session.players.erase(91)
	_no_rest()
	r = await _result(Session.travel("town"))
	ok(r.get("ok", false), "back to town")
	ok(CityWeb.rules == null, "the web city sleeps again")
	ok(City.rules != null, "the city keeps its friend")
	var nope := await _result(Session.city_use("cafe_seat_b"))
	eq(nope.get("error"), "Take the tram to the city first.", "a request from town reaches no city")
	Session._on_peer_disconnected(90)
	ok(City.rules == null, "the city sleeps when its friend leaves")
	CityWeb.updated.disconnect(web_cb)
	City.updated.disconnect(city_cb)
	City.set_physics_process(true)
	CityWeb.set_physics_process(true)


# ------------------------------------------------------------- the controller and the HUD (a world without rendering)

func _build_game() -> void:
	holder = Node.new()
	holder.name = "Main"
	root.add_child(holder)
	var thumbs: Node = load("res://scripts/ui/thumbnails.gd").new()
	holder.add_child(thumbs)
	world = TownWorld.new()
	world.name = "World"
	holder.add_child(world)
	rig = load("res://scripts/world/camera_rig.gd").new()
	holder.add_child(rig)
	c = load("res://scripts/world/play_controller.gd").new()
	holder.add_child(c)
	c.setup(world, rig)
	var ui := CanvasLayer.new()
	holder.add_child(ui)
	hud = load("res://scripts/ui/hud.gd").new()
	ui.add_child(hud)
	hud.bind(c, thumbs)
	c.hint.connect(func(t): _hints.append(t))


func _ground_target(from: Vector2) -> Dictionary:
	# A plain ground spot a few metres away with no action near it (a tap there only walks).
	for dx in [3.0, -3.0, 0.0, 2.0]:
		for dz in [3.0, -3.0, 0.0, 2.0]:
			var p := from + Vector2(dx, dz)
			if p.distance_to(from) < 1.5:
				continue
			var o := Vector3(p.x, 25.0, p.y + 6.0)
			var d := (Vector3(p.x, 0.0, p.y) - o).normalized()
			var hit := CityNav.pick(o, d, CityNav.storeys_hidden("", from))
			if hit.is_empty() or str(hit["region"]) != "" or (hit["pos"] as Vector2).distance_to(p) > 0.05:
				continue
			if CityNav.route("", from, "", p).is_empty():
				continue
			var near := false
			for key in CityMap.INTERACTIONS:
				var it: Dictionary = CityMap.INTERACTIONS[key]
				if str(it["region"]) == "ground" and (it["pos"] as Vector2).distance_to(p) < 2.5:
					near = true
			if not near:
				return {"o": o, "d": d, "p": p}
	return {}


func test_controller() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://test_city_web_ui.json")
	await process_frame
	var me: int = Session.my_id
	ok(c.space == "town" and world.local_kid() != null, "a solo game in town")
	# ---- the tram stop: the third journey only where the web city is available
	var stop: String = Session.model.tram_stop_id()
	_env(false)
	if not _flag:
		ok(not c._context_for_item(stop).has("alt2"), "without the switch the tram stop offers the zoo and the city only")
		_hints.clear()
		c.travel_to("city_web", CityMap.ARRIVALS[0])
		ok(c.space == "town" and c.journey_to == "" and _hints.has("That place can't be reached from here."),
			"an invitation into the web city on a device without it stays in town, kindly (%s)" % str(_hints))
	_env(true)
	var ctx: Dictionary = c._context_for_item(stop)
	eq(ctx.get("alt", {}).get("type", ""), "tram_city", "the stop still offers the city beside the zoo")
	eq(ctx.get("alt2", {}).get("type", ""), "tram_city_web", "and the web city third")
	eq(ctx.get("alt2", {}).get("label", ""), "Ride to the city (web)", "named")
	var board: Variant = TownModel.tram_stop_boarding(Session.model)
	c.pos = board
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt2"), 3.0), "standing at the stop offers it (%s)" % str(c._ctx))
	ok(hud._context_alt2_btn.visible and hud._context_alt2_btn.text == "Ride to the city (web)", "the HUD shows a third button")
	hud._context_alt2_btn.pressed.emit()
	ok(await _until(func(): return c.space == "city_web" and c.journey_to == "", 6.0), "the child arrives in the web city (%s)" % c.space)
	# ---- nothing of the Godot city
	eq(world.view_space, "city_web", "the world's view is the web city")
	ok(world.city_world == null, "the Godot city is neither built nor shown")
	ok(world.city_logic != null and not world.city_logic._built and not world.city_logic.visible and world.city_logic.get_child_count() == 0,
		"a logic-only CityWorld answers the poses")
	ok(world.active_city() == world.city_logic, "and serves the web city")
	ok(c.pos.distance_to(CityMap.ARRIVALS[0]) < 0.05 and c.level == "", "at the bus stop (%s)" % c.pos)
	ok(CityWeb.rules != null and City.rules == null, "the web city is awake, the city sleeps")
	ok(rig.on_city, "Godot's own camera frames the block (desktop window)")
	# ---- the HUD: the page draws the city's own controls
	ok(not hud._city_look.visible and not hud._city_pause.visible and not hud._city_weather.visible and not hud._city_reset.visible,
		"Look, Pause, weather and Reset are hidden in the web city")
	ok(hud._ride_home.visible, "Ride home stays")
	ok(hud._location.visible and hud._location.text.begins_with("City (web)"), "the place is named (%s)" % hud._location.text)
	# ---- Godot's own window does not walk the child
	var at0: Vector2 = c.pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = Vector2(400, 300)
		c._unhandled_input(e)
	await physics_frame
	ok(c._walk_target == null and c.pos == at0, "a tap in Godot's window does nothing in the web city")
	# ---- web_ctx at the bus stop
	await physics_frame
	var wc: Dictionary = c.web_ctx()
	if c._ctx.is_empty():
		eq(wc, {}, "no action: an empty context")
	else:
		eq(wc, {"type": str(c._ctx["type"]), "label": tr(str(c._ctx["label"])), "icon": str(c._ctx["icon"])}, "web_ctx is the action button")
	# ---- web_tap: a ground tap walks the child there
	var tgt := _ground_target(c.pos)
	ok(not tgt.is_empty(), "a plain ground spot near the bus stop")
	if not tgt.is_empty():
		c.web_tap(tgt["o"], tgt["d"])
		ok(c._walk_target != null and c._pending_ctx.is_empty(), "a ground tap walks (to %s)" % str(tgt["p"]))
		ok(await _until(func(): return c.pos.distance_to(tgt["p"]) < 0.15, 8.0), "and the child gets there (%s)" % c.pos)
		eq(c.level, "", "on the ground")
	# ---- web_tap on an upper floor: a route by stairs, with the thing tapped done on arrival
	var seat_r: Vector2 = CityMap.INTERACTIONS["restaurant_seat_a"]["pos"]
	var ro := Vector3(seat_r.x, 40.0, seat_r.y)
	var hit := CityNav.pick(ro, Vector3.DOWN, CityNav.storeys_hidden(c.level, c.pos))
	eq(str(hit.get("region", "")), "gym_roof", "(the ray from above lands on the rooftop restaurant)")
	var want: Array = CityNav.route(c.level, c.pos, "gym_roof", seat_r)
	c.web_tap(ro, Vector3(0, -3, 0))   # not normalized: the bridge may send any length
	ok(want.size() >= 2 and str((want[-1] as Dictionary)["region"]) == "gym_roof", "(a route up exists: %d waypoints)" % want.size())
	eq(c._pending_ctx.get("key", ""), "restaurant_seat_a", "a tap on the restaurant seat walks there to sit")
	ok(not c._city_route.is_empty() and str((c._city_route[-1] as Dictionary)["region"]) == "gym_roof", "by a route that ends on the roof")
	eq(c._city_route, want.slice(1), "the same route as CityNav.route")
	c._walk_target = null
	c._city_route = []
	c._pending_ctx = {}
	c.web_tap(Vector3.ZERO, Vector3.ZERO)
	ok(c._walk_target == null, "a ray without a direction does nothing")
	# ---- web_act: sit down, stand up
	var sa: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	c.pos = sa + Vector2(0.3, 0.0)
	c.level = ""
	ok(await _until(func(): return c._ctx.get("key", "") == "cafe_seat_a", 2.0), "beside the cafe seat")
	eq(c.web_ctx(), {"type": "city_use", "label": tr("Sit down"), "icon": "sit"}, "web_ctx: Sit down")
	# a friend in the Godot city holds the same seat there
	_friend(92, "city", sa)
	City.on_space_changed(92)
	ok(City.srv_use(92, "", sa, "cafe_seat_a").get("ok", false), "(a friend sits there in the city)")
	c.web_act()
	ok(await _until(func(): return c.city_hold.get("key", "") == "cafe_seat_a", 3.0), "web_act sits the child down (%s)" % str(_hints))
	ok(await _until(func(): return CityWeb.occupant("cafe_seat_a") == me, 3.0), "the web city's state shows me")
	eq(City.occupant("cafe_seat_a"), -1, "my City state knows nothing of the city's seat")
	await physics_frame
	var seat_xf: Transform3D = CityWorld.seat_transform("cafe_seat_a")
	seat_xf.origin.y += 0.44
	ok(_xf_near(world.local_kid().global_transform, seat_xf), "the child sits on the seat's pose (logic world)")
	eq(c.web_ctx(), {"type": "city_release", "label": tr("Stand up"), "icon": "stand"}, "web_ctx: Stand up")
	eq(c.web_me()["hold"], "cafe_seat_a", "web_me says what is held")
	# ---- weather in the web city
	c.web_weather(1)
	ok(await _until(func(): return int(CityWeb.states["weather"]) == 1, 3.0), "web_weather: rain in the web city")
	ok(City.rules != null and City.rules.weather == 0, "the city stays sunny")
	eq(int(City.states["weather"]), 0, "and nothing of it reaches me")
	var city_got := []
	var city_cb := func(states): city_got.append(states)
	City.updated.connect(city_cb)
	await create_timer(0.8).timeout
	City.updated.disconnect(city_cb)
	eq(city_got.size(), 0, "the city's states go to its own children only")
	c.web_act()
	ok(await _until(func(): return c.city_hold.is_empty() and CityWeb.occupant("cafe_seat_a") == -1, 3.0), "web_act stands the child up")
	# ---- riding and friends: the poses come from the logic world
	CityWeb.set_physics_process(false)
	var s: Dictionary = CityWeb.states.duplicate(true)
	s["riders"] = {2: [me]}
	CityWeb.states = s
	await physics_frame
	await physics_frame
	var lw: Node3D = world.city_logic
	var kid: Node3D = world.local_kid()
	ok(c._city_busy() and c.web_me()["riding"] == 2, "riding gondola 2")
	ok(_xf_near(kid.global_transform, CityWorld.rider_transform(2, lw.ferris_angle_now(), 0), 0.05), "the child sits in its gondola at the clock's angle")
	_friend(93, "city_web", sa)
	world._sync_players()
	var s2: Dictionary = CityWeb.states.duplicate(true)
	s2["riders"] = {2: [me], 5: [93]}
	CityWeb.states = s2
	world.place_city_friends(CityWeb.states)
	ok(world.kids.has(93) and _xf_near(world.kids[93].global_transform, CityWorld.rider_transform(5, lw.ferris_angle_now(), 0), 0.05), "a friend rides gondola 5 where the logic world says")
	var s3: Dictionary = CityWeb.states.duplicate(true)
	s3["riders"] = {}
	s3["occupancy"] = {"cafe_seat_b": 93}
	CityWeb.states = s3
	world.place_city_friends(CityWeb.states)
	var sb: Transform3D = CityWorld.seat_transform("cafe_seat_b")
	sb.origin.y += 0.44
	ok(_xf_near(world.kids[93].global_transform, sb), "a friend holding a seat sits on its pose")
	CityWeb.effect.emit("ride_off", {"peer": me, "pos": CityMap.FERRIS["board_at"], "region": "", "gondola": 2})
	ok(c.pos == CityMap.FERRIS["board_at"], "the web city's ride_off brings the child back to the platform")
	Session.players.erase(93)
	world._sync_players()
	CityWeb.set_physics_process(true)
	await create_timer(0.4).timeout
	ok(not c._city_busy(), "the shared state takes over again")
	# ---- the cutaway the page receives
	var desk: Vector2 = CityMap.INTERACTIONS["office_desk_a"]["pos"]
	c.level = "office_l1"
	c.pos = desk
	await physics_frame
	await physics_frame
	var rev0: int = world.web_cutaway()["rev"]
	var cut: Dictionary = world.web_cutaway()
	var hidden: Dictionary = CityNav.storeys_hidden("office_l1", desk)
	ok(not hidden.is_empty(), "(on the office's first floor something is hidden above)")
	eq(cut["hidden"], hidden, "web_cutaway: what CityWorld.apply_hidden would get")
	eq(cut["regions"], TownWorld.hidden_regions(hidden), "and what the people's set_hidden_regions would get")
	ok((cut["regions"] as Array).size() > 0, "(some regions go with it: %s)" % str(cut["regions"]))
	await physics_frame
	eq(world.web_cutaway()["rev"], rev0, "the revision stays while nothing changes")
	c.level = ""
	c.pos = CityMap.ARRIVALS[0]
	await physics_frame
	await physics_frame
	ok(int(world.web_cutaway()["rev"]) > rev0 and (world.web_cutaway()["hidden"] as Dictionary).is_empty(), "and changes when the cutaway changes")
	ok(world.city_world == null, "still nothing of the Godot city")
	# ---- home
	Session.players.erase(92)
	City.advance(0.1)
	_no_rest()
	c.web_home()
	ok(await _until(func(): return c.space == "town" and c.journey_to == "", 6.0), "web_home rides the child home")
	ok(CityWeb.rules == null, "the web city sleeps")
	eq(world.view_space, "town", "the town is in view")
	ok(not rig.on_city, "and its camera")
	holder.queue_free()
	await process_frame
