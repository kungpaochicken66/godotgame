## Headless tests for Thousand Town as a destination (design/thousand-town.md sections 3-7): the places registry,
## the Thousand authority's clock, time modes and bus seats (solo), the placeholder world's API, the follow
## camera and its occlusion pull-in, and the journey there and back with the HUD's time buttons, Look and the
## inspect panel (fed with fake data), and the TV focus order. Protocol 20 and the refusal of 19.
##   scripts/godot.sh --headless --path game -s res://tests/thousand_tests.gd
## Two real clients: scripts/net_test.py --thousand (tests/thousand_bot.gd).
extends "res://tests/puzzle_ride_tests.gd"

const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const ThousandWorld := preload("res://scripts/world/thousand_world.gd")
const ThousandPanel := preload("res://scripts/ui/thousand_panel.gd")
const Rig := preload("res://scripts/world/camera_rig.gd")
const PadInput := preload("res://scripts/ui/pad_input.gd")
const ThousandMap := preload("res://scripts/core/thousand_map.gd")
var TownWorld: GDScript

var Thousand: Node
var _tv_before := -1
var _effects: Array = []
var _hints: Array = []
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control


## Stands in for main.gd for the controller layer (pad_input.gd reads these).
class FakeMain extends Node:
	var menus: Control = null
	var hud: Control
	var controller: Node
	var rig: Node3D


## A world that only answers the camera's questions.
class BoxWorld extends Node3D:
	var boxes: Array = []
	var told: Array = []
	var calls := 0

	func occluders() -> Array:
		return boxes

	func set_occluded(ids: Array) -> void:
		told = ids.duplicate()
		calls += 1


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	Thousand = root.get_node("Thousand")
	_tv_before = TvMode.forced
	TownWorld = load("res://scripts/world/town_world.gd")
	await process_frame
	for t in ["test_places", "test_clock", "test_world", "test_fonts"]:
		_current = t
		call(t)
	for t in ["test_camera", "test_authority", "test_controller"]:
		_current = t
		await call(t)
	TvMode.forced = _tv_before
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nTHOUSAND TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


## Software GL on the EC2 host draws the real Thousand Town (about 600k triangles) at about 2 s a frame, so
## a wait measured in wall-clock seconds would see well under a second of game time. Waits stretch by SLOW
## (they still end as soon as the condition holds); the game's own timings are unchanged.
const SLOW := 8.0


func _until(cond: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await physics_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout * SLOW:
			return false
	return true


func _friend(peer: int, space: String, p: Vector2) -> void:
	Session.players[peer] = {"avatar": Avatar.sanitize(Avatar.PRESETS[(peer + 1) % 4]), "pid": ("%032x" % peer),
		"state": {"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"}}


# ------------------------------------------------------------- the places registry (pure)

func test_places() -> void:
	ok(Places.MAPS.has(Places.THOUSAND) and Places.is_map("thousand"), "thousand is a map")
	eq(Places.THOUSAND, "thousand", "its id")
	eq(Places.map_of("thousand"), "thousand", "its own map")
	ok(not Places.is_city("thousand") and not Places.is_room("thousand"), "neither a city map nor a room")
	ok((Places.DESTINATIONS[Places.TOWN] as Array).has("thousand"), "the town's tram goes to Thousand Town")
	eq(Places.DESTINATIONS[Places.THOUSAND], ["town"], "Thousand Town goes home only")
	eq(Places.NAMES[Places.THOUSAND], "Thousand Town", "its name")
	eq(Places.half("thousand"), Vector2(95.0, 129.0), "its board (+-95, +-129 m)")
	eq(Places.arrival("thousand", 0), Vector2(-52.0, 3.6), "the station forecourt's corner")
	ok(is_equal_approx(Places.THOUSAND_ARRIVAL_RY, PI / 2.0), "arriving facing east (+x)")
	ok(not Places.can_decorate("thousand"), "no toy box there")
	eq(Places.music("thousand"), "town", "outdoor music")
	TvMode.forced = 0
	ok(Places.available("thousand") and (Places.offered("town") as Array).has("thousand"), "offered on a phone or tablet")
	TvMode.forced = 1
	ok(Places.available("thousand") and (Places.offered("town") as Array).has("thousand"), "and on a TV")
	TvMode.forced = 0
	eq(Places.offered("thousand"), ["town"], "from Thousand Town: home")


# ------------------------------------------------------------- the clock (pure)

func test_clock() -> void:
	var t := Thousand   # its pure functions, through the autoload (the script names Session, an autoload)
	var c0: Dictionary = t.fresh_clock()
	eq(c0, {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}, "the first arrival starts at day 1, 08:00, auto 1x")
	eq(t.step_clock(c0, 60.0)["minute"], 540.0, "auto 1x: one minute per second")
	var c2: Dictionary = t.apply_mode(c0, "auto", 2)
	eq(t.step_clock(c2, 30.0)["minute"], 540.0, "auto 2x: two minutes per second")
	var c4: Dictionary = t.apply_mode(c0, "auto", 4)
	eq(t.step_clock(c4, 15.0)["minute"], 540.0, "auto 4x")
	var late: Dictionary = {"day": 1, "minute": 1430.0, "mode": "auto", "speed": 1}
	var next: Dictionary = t.step_clock(late, 20.0)
	ok(next["day"] == 2 and is_equal_approx(float(next["minute"]), 10.0), "midnight starts day 2 (%s)" % str(next))
	for spec in [["day", 720.0], ["dusk", 1120.0], ["night", 1290.0]]:
		var held: Dictionary = t.apply_mode(c0, spec[0])
		eq(held["minute"], spec[1], "%s jumps to %s" % [spec[0], t.clock_text(spec[1])])
		eq(t.step_clock(held, 120.0)["minute"], spec[1], "%s holds" % spec[0])
	var resumed: Dictionary = t.apply_mode(t.apply_mode(c4, "dusk"), "auto", 0)
	ok(resumed["mode"] == "auto" and resumed["speed"] == 4 and resumed["minute"] == 1120.0, "Auto resumes from the held time at its speed (%s)" % str(resumed))
	eq([t.next_speed(1), t.next_speed(2), t.next_speed(4)], [2, 4, 1], "a second press on Auto: 1x, 2x, 4x, 1x")
	eq(t.clock_text(1290.0), "21:30", "clock text")
	var seats := {7: {"v": 1, "seat": 2}, 3: {"v": 0, "seat": 0}}
	var packed: PackedFloat64Array = t.pack_state({"day": 6, "minute": 1120.0, "mode": "dusk", "speed": 2}, seats)
	eq(t.decode(packed), {"started": true, "day": 6, "minute": 1120.0, "mode": "dusk", "speed": 2, "riders": {3: {"v": 0, "seat": 0}, 7: {"v": 1, "seat": 2}}},
		"the wire round trip")
	eq(t.decode(t.pack_state({}, {}))["started"], false, "an unstarted clock says so")
	eq(t.decode(PackedFloat64Array([2.0, 1, 1, 480, 0, 1, 0])), {}, "another wire version is refused")
	eq(t.decode(PackedFloat64Array([1.0, 1, 1, 480, 9, 1, 0])), {}, "an unknown mode is refused")
	eq(t.decode(PackedFloat64Array([1.0, 1, 1, 480, 0, 3, 0])), {}, "an unknown speed is refused")
	eq(t.decode(PackedFloat64Array([1.0, 1, 1, 480, 0, 1, 2, 5, 0])), {}, "a truncated rider list is refused")


# ------------------------------------------------------------- the placeholder world

func test_world() -> void:
	var w: Node3D = ThousandWorld.new()
	root.add_child(w)
	w.build()
	w.build()   # idempotent
	eq(ThousandWorld.BUILDINGS.size(), 18, "18 buildings")
	ok(w.occluders().size() >= 31, "an occluder per building, tower and roof (%d)" % w.occluders().size())
	ok(w.get_child_count() > 40, "the placeholder is built (%d nodes)" % w.get_child_count())
	# walking
	eq(w.resolve_walk(Vector2(-20.0, 0.0)), Vector2(-20.0, 0.0), "the pedestrian street is walkable")
	var wet: Vector2 = w.resolve_walk(Vector2(-6.0, 0.0), Vector2(-8.0, 0.0))
	ok(wet.x <= -7.5, "a step into the canal stays on the bank (%s)" % wet)
	ok(absf(w.resolve_walk(Vector2(1.0, 3.0)).x) >= 7.5, "a point in the canal is pushed onto a bank")
	for z in [-40.0, -20.0, 20.0, 40.0]:
		eq(w.resolve_walk(Vector2(0.0, z)), Vector2(0.0, z), "the bridge at z %d crosses the canal" % int(z))
	var mall: Rect2 = ThousandWorld._rect(ThousandWorld.BUILDINGS["mall"])
	var outside := Vector2(mall.position.x - 0.5, mall.get_center().y)
	var into: Vector2 = w.resolve_walk(Vector2(mall.position.x + 0.5, mall.get_center().y + 0.2), outside)
	ok(not mall.grow(0.27).has_point(into), "a step into a building is blocked (%s)" % into)
	var edge: Vector2 = w.resolve_walk(Vector2(200.0, -300.0))
	ok(absf(edge.x) <= 95.0 and absf(edge.y) <= 129.0, "the board's edge holds (%s)" % edge)
	ok(is_equal_approx(w.height_at(Vector2(-30, -40)), 0.125), "the street level (%.3f)" % w.height_at(Vector2(-30, -40)))
	var arr: Transform3D = w.arrival()
	ok(arr.origin.is_equal_approx(ThousandMap.ARRIVAL_POS), "arrival at the station forecourt's corner (%s)" % arr.origin)
	for k in 4:
		var ak: Vector3 = w.arrival(k).origin
		eq(Vector2(ak.x, ak.z), Places.THOUSAND_ARRIVALS[k], "the session's arrival slot %d is the world's" % k)
	ok((arr.basis.z - Vector3(1, 0, 0)).length() < 0.001, "facing east, +x (%s)" % arr.basis.z)
	eq(w.resolve_walk(Vector2(-66.0, 20.0)), Vector2(-66.0, 20.0), "the station is walkable")
	# inspection
	eq(str(w.building_at(mall.get_center()).get("id", "")), "c-mall", "building_at: the mall")
	eq(str(w.building_at(mall.get_center()).get("name", "")), "Mall", "its English name")
	eq(str(w.building_at(Vector2(-66.0, 20.0)).get("kind", "")), "place", "the station is a place")
	var door: Vector2 = ThousandWorld.door_point("mall")
	ok(not ThousandWorld._blocked(door), "the mall's door point is walkable (%s)" % door)
	eq(str(w.door_near(door + Vector2(0.5, 0.0), 2.0).get("id", "")), "c-mall", "door_near finds the mall's door")
	eq(w.door_near(Vector2(-20.0, 0.0), 2.0), {}, "no door in the middle of the street")
	var bad := []
	for id in ThousandWorld.BUILDINGS:
		if ThousandWorld._blocked(ThousandWorld.door_point(id)):
			bad.append(id)
	eq(bad, [], "every door point is walkable")
	# light
	w.set_time(1, 720.0)
	ok(is_equal_approx(float(w.light["daylight"]), 1.0), "noon is full day")
	w.set_time(1, 1290.0)
	ok(is_equal_approx(float(w.light["daylight"]), 0.0), "21:30 is night")
	w.set_time(1, 1120.0)
	ok(float(w.light["daylight"]) > 0.0 and float(w.light["daylight"]) < 1.0, "18:40 is dusk (%.2f)" % float(w.light["daylight"]))
	# dithering hook
	w.set_occluded([3])
	eq(w.occluded(), [3], "set_occluded keeps the ids")
	w.set_occluded([])
	w.clock = func() -> Dictionary: return {"day": 4, "minute": 100.0}
	eq(w.view_time()["day"], 4, "a test clock replaces the shared one")
	w.free()


## The credit's upstream title and author (code escapes, outside the catalogs) are in the bundled fonts.
func test_fonts() -> void:
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	var credit: String = hud_script.thousand_credit()
	ok(credit.contains(String.chr(0x5343)) and credit.contains("YiHuiShiBY") and credit.contains("CC BY 4.0"), "the credit names the title, author and licence")
	var fonts := []
	for f in ["NotoSansSC-subset.ttf", "MPLUSRounded1c-Bold-subset.ttf"]:
		var ff := FontFile.new()
		ff.load_dynamic_font(ProjectSettings.globalize_path("res://assets/fonts/" + f))
		fonts.append(ff)
	var missing := []
	for ch in hud_script.THOUSAND_TITLE + hud_script.THOUSAND_AUTHOR:
		if ch.unicode_at(0) > 127 and not (fonts[0] as FontFile).has_char(ch.unicode_at(0)):
			missing.append(ch)
	eq(missing, [], "every character of the credit's title and author is in the Chinese font (the fallback in every language)")


# ------------------------------------------------------------- the follow camera

func test_camera() -> void:
	# the pose (pure)
	var xf: Transform3D = Rig.follow_xform(Vector3.ZERO, -PI / 2.0, 7.0)   # yaw -pi/2: the camera west of the child
	ok(xf.origin.is_equal_approx(Vector3(-7.0, 2.6, 0.0)), "7 m behind, 2.6 m up (%s)" % xf.origin)
	var fwd := -xf.basis.z
	ok(fwd.x > 0.98 and fwd.y < 0.0 and fwd.y > -0.2, "looking east, slightly down (%s)" % fwd)
	var view := Vector2(1920, 1080)
	var chest = Rig.project(xf, view, Vector3(0, 0.9, 0))
	ok(chest != null and absf((chest as Vector2).y / view.y - 2.0 / 3.0) < 0.01, "the child's chest on the lower third (%s)" % str(chest))
	var far: Transform3D = Rig.follow_xform(Vector3.ZERO, 0.0, 14.0)
	ok(is_equal_approx(far.origin.y, 0.9 + 1.7 * 2.0), "the height scales with the distance (the look-down stays)")
	# the sphere cast (pure)
	var c0 := Vector3(0, 0.9, 0)
	var eye := Vector3(-7, 2.6, 0)
	var wall := AABB(Vector3(-6, 0, -5), Vector3(1, 10, 10))   # x -6 .. -5
	var d: float = Rig.pull_in(c0, eye, [wall])
	ok(d > 4.5 and d < 5.0, "pulled in before the wall (%.2f m)" % d)
	var close := AABB(Vector3(-3.2, 0, -5), Vector3(0.3, 10, 10))   # nearer than 4 m
	eq(Rig.pull_in(c0, eye, [close]), Rig.T_PULL_MIN, "never nearer than the closest zoom (4 m)")
	ok(is_equal_approx(Rig.pull_in(c0, eye, [AABB(Vector3(10, 0, 10), Vector3(2, 2, 2))]), c0.distance_to(eye)), "a box elsewhere does not pull")
	eq(Rig.blocking(c0, eye, [AABB(Vector3(10, 0, 10), Vector3(2, 2, 2)), close]), [1], "the box between is reported by id")
	# the rig in a tree, with a world of boxes
	var bw := BoxWorld.new()
	root.add_child(bw)
	var r: Node3D = Rig.new()
	root.add_child(r)
	var kid := Node3D.new()
	root.add_child(kid)
	kid.position = Vector3(0, 0, 0)
	kid.rotation = Vector3(0, PI / 2.0, 0)
	r.target = kid
	await process_frame
	r.enter_thousand(bw, PI / 2.0)
	ok(r.camera.global_position.is_equal_approx(Vector3(-7.0, 2.6, 0.0)), "entering: behind the child (%s)" % r.camera.global_position)
	ok((-r.camera.global_basis.z).x > 0.98, "looking +x")
	ok(is_equal_approx(r.camera.far, 600.0) and is_equal_approx(r.camera.near, 0.1), "near 0.1, far 600 m")
	ok(r.flat_forward().distance_to(Vector2(1, 0)) < 0.001, "the stick walks away from the camera")
	bw.boxes = [wall]
	r.snap()
	ok(r.camera.global_position.x > -4.9 and r.camera.global_position.x < -4.5, "pulled in by the wall (%s)" % r.camera.global_position)
	eq(bw.told, [], "nothing between the camera and the child")
	bw.boxes = [close]
	r.snap()
	ok(absf(r.camera.global_position.distance_to(c0) - Rig.T_PULL_MIN) < 0.01, "held at 4 m by a nearer box")
	eq(bw.told, [0], "the box still between is handed to set_occluded")
	bw.boxes = []
	r.snap()
	eq(bw.told, [], "and taken back when it is not")
	# zoom and orbit
	r.thousand_zoom(10.0)
	eq(r.t_dist, 4.0, "a pinch stops at 4 m")
	r.thousand_zoom(0.01)
	eq(r.t_dist, 18.0, "and at 18 m")
	var y0: float = r.t_yaw
	r.thousand_orbit(Vector2(100, 0))
	ok(not is_equal_approx(r.t_yaw, y0), "a drag orbits")
	var y1: float = r.t_yaw
	r.thousand_orbit_stick(Vector2(1, 0), 0.5)
	ok(is_equal_approx(r.t_yaw, y1 - Rig.T_STICK_RATE * 0.5), "the right stick orbits")
	r.thousand_set_overview(true)
	r.snap()
	ok(r.camera.global_position.is_equal_approx(Rig.T_OVERVIEW_EYE), "Look: the overview of the whole town")
	r.thousand_set_overview(false)
	r.snap()
	ok(r.camera.global_position.distance_to(kid.position) < 20.0, "and back to the child")
	r.leave_thousand()
	ok(not r.on_thousand and is_equal_approx(r.camera.far, 220.0), "leaving restores the town's camera")
	r.queue_free()
	kid.queue_free()
	bw.queue_free()
	await process_frame


# ------------------------------------------------------------- the authority (solo), stepped by hand

func test_authority() -> void:
	await _fresh_town("user://test_thousand_net.json")
	Thousand.set_physics_process(false)
	var me: int = Session.my_id
	_effects.clear()
	Thousand.effect.connect(func(kind, data): _effects.append([kind, data]))
	eq(Session.PROTOCOL, 20, "protocol 20")
	var refused := []
	var cb := func(reason): refused.append(reason)
	Session.rejected.connect(cb)
	Session._srv_join(1, Avatar.sanitize(Avatar.PRESETS[1]), 19, "")
	Session.rejected.disconnect(cb)
	eq(refused, ["Please update the app to play together."], "a protocol 19 app is told to update")
	ok(Thousand.clock.is_empty() and not Thousand.states["started"], "the clock waits for the first arrival")
	var r := await _result(Session.thousand_time("night", 0))
	eq(r.get("error", ""), "Take the tram to Thousand Town first.", "nobody in town chooses its time from home")
	Session._last_journey.clear()
	r = await _result(Session.travel("thousand"))
	ok(r.get("ok", false) and r.get("space") == "thousand", "the tram goes to Thousand Town (%s)" % str(r))
	eq(Vector2(float(r.get("x", 0)), float(r.get("z", 0))), Places.THOUSAND_ARRIVALS[0], "to the station forecourt's corner")
	ok(is_equal_approx(float(r.get("ry", 0)), snappedf(PI / 2.0, 0.01)), "facing east")
	eq(Thousand.clock, {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}, "the first arrival starts the clock at 08:00")
	ok(Thousand.states["started"] and Thousand.states["minute"] == 480.0, "and this device has the state at once")
	Thousand.advance(0.2)
	for i in 50:
		Thousand.advance(0.2)
	ok(absf(float(Thousand.clock["minute"]) - 490.2) < 0.01, "auto 1x runs a minute a second (%s)" % str(Thousand.clock))
	r = await _result(Session.thousand_time("night", 0))
	ok(r.get("ok", false) and r.get("minute") == 1290.0, "Night: 21:30 (%s)" % str(r))
	ok(_effects.any(func(e): return e[0] == "time" and e[1]["mode"] == "night" and e[1]["peer"] == me), "a time effect for everyone in town")
	for i in 20:
		Thousand.advance(0.25)
	eq(Thousand.clock["minute"], 1290.0, "Night holds")
	eq(Thousand.states["mode"], "night", "the state says night")
	eq(Thousand.est_clock()["minute"], 1290.0, "and the estimate holds too")
	r = await _result(Session.thousand_time("day", 0))
	eq(Thousand.clock["minute"], 720.0, "Day: 12:00")
	r = await _result(Session.thousand_time("dusk", 0))
	eq(Thousand.clock["minute"], 1120.0, "Dusk: 18:40")
	r = await _result(Session.thousand_time("auto", 0))
	ok(r.get("ok", false) and r.get("mode") == "auto" and r.get("speed") == 1, "Auto resumes (%s)" % str(r))
	for i in 20:
		Thousand.advance(0.25)
	ok(absf(float(Thousand.clock["minute"]) - 1125.0) < 0.01, "from the held time (%s)" % str(Thousand.clock))
	r = await _result(Session.thousand_time("auto", 4))
	eq(Thousand.clock["speed"], 4, "4x")
	for i in 4:
		Thousand.advance(0.25)
	ok(absf(float(Thousand.clock["minute"]) - 1129.0) < 0.01, "four minutes a second (%s)" % str(Thousand.clock))
	var est: Dictionary = Thousand.est_clock()
	ok(float(est["minute"]) >= float(Thousand.states["minute"]) - 0.001, "the estimate never runs behind the state")
	r = await _result(Session.thousand_time("noon", 0))
	eq(r.get("error", ""), "That does not work right now.", "an unknown mode is refused")
	r = await _result(Session.thousand_time("auto", 3))
	eq(r.get("error", ""), "That does not work right now.", "an unknown speed is refused")
	# bus seats (stub)
	r = await _result(Session.thousand_board(0))
	ok(r.get("ok", false) and r.get("v") == 0 and r.get("seat") == 0, "a seat on bus 0 (%s)" % str(r))
	eq(Thousand.riding(me), 0, "my state says I ride bus 0")
	r = await _result(Session.thousand_board(0))
	ok(r.get("ok", false) and r.get("seat") == 0, "asking again keeps the seat")
	r = await _result(Session.thousand_board(1))
	eq(r.get("error", ""), "Get off the bus first.", "one bus at a time")
	r = await _result(Session.thousand_board(9))
	eq(r.get("error", ""), "That does not work right now.", "no bus 9")
	for p in [81, 82, 83]:
		_friend(p, "thousand", Vector2(-60, 0))
		ok(Thousand.srv_board_bus(p, 0).get("ok", false), "friend %d boards bus 0" % p)
	_friend(84, "thousand", Vector2(-60, 0))
	eq(Thousand.srv_board_bus(84, 0).get("error", ""), "That bus is full.", "a fifth rider waits for the next bus")
	ok(Thousand.srv_board_bus(84, 1).get("ok", false), "and takes bus 1")
	Session.players[81]["state"]["space"] = "town"
	Thousand.on_space_changed(81)
	ok(not Thousand.seats.has(81), "a friend who went home gives up the seat")
	r = await _result(Session.thousand_off())
	ok(r.get("ok", false), "I get off")
	r = await _result(Session.thousand_off())
	eq(r.get("error", ""), "You are not on a bus.", "and cannot get off twice")
	for p in [81, 82, 83, 84]:
		Session.players.erase(p)
		Thousand.peer_left(p)
	ok(Thousand.seats.is_empty(), "every seat is free again")
	# the clock runs only while someone is there
	Session._last_journey.clear()
	r = await _result(Session.travel("town"))
	ok(r.get("ok", false), "home again")
	var held: float = Thousand.clock["minute"]
	for i in 20:
		Thousand.advance(0.25)
	eq(Thousand.clock["minute"], held, "an empty town's clock stands still")
	Session._last_journey.clear()
	r = await _result(Session.travel("thousand"))
	eq(Thousand.clock["minute"], held, "and goes on from there on the next visit (not 08:00 again)")
	Session._last_journey.clear()
	r = await _result(Session.travel("town"))
	# nothing of Thousand Town is saved
	var saved: Dictionary = Session.model.to_dict()
	ok(not JSON.stringify(saved).contains("thousand"), "the save holds nothing of Thousand Town")
	Thousand.set_physics_process(true)


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


func _fake_provider(id: String) -> Dictionary:
	return {"id": id, "name": "Terrace Housing", "open": false, "count": 2, "counts": {"home": 1, "asleep": 1},
		"here": [{"id": "r12", "name": "Mia Chen", "role": "teacher", "age": 34, "state": "home", "where": "Terrace Housing",
			"plan": [{"from": 0, "to": 420, "state": "asleep", "where": "Terrace Housing", "now": false},
				{"from": 420, "to": 1020, "state": "work", "where": "Primary School", "now": true}]},
			{"id": "r40", "name": "Leo Park", "role": "preschooler", "age": 5, "state": "asleep", "where": "Terrace Housing", "plan": []}],
		"lives": [{"id": "r12", "name": "Mia Chen", "role": "teacher", "age": 34, "state": "home", "where": "Terrace Housing", "plan": []}]}


func test_controller() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://test_thousand_ui.json")
	await process_frame
	var me: int = Session.my_id
	ok(c.space == "town" and world.local_kid() != null, "a solo game in town")
	# ---- the tram stop offers the journey, on a TV too
	var stop: String = Session.model.tram_stop_id()
	TvMode.forced = 1
	eq(c._context_for_item(stop).get("alt3", {}).get("type", ""), "tram_thousand", "a TV's tram stop offers Thousand Town")
	TvMode.forced = 0
	var ctx: Dictionary = c._context_for_item(stop)
	eq(ctx.get("alt3", {}).get("type", ""), "tram_thousand", "a tablet's too")
	eq(ctx.get("alt3", {}).get("label", ""), "Ride to Thousand Town", "named")
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 3.0), "standing at the stop offers it")
	ok(hud._context_alt3_btn.visible and hud._context_alt3_btn.text == "Ride to Thousand Town", "the HUD shows its button")
	hud._context_alt3_btn.pressed.emit()
	ok(c.journey_to == "thousand", "the journey starts")
	await process_frame
	var title: Label = hud._journey_card.get_node("Box/V/Title")
	eq(title.text, "To Thousand Town", "the journey card names it")
	var credit: Label = hud._journey_card.get_node("Box/V/Credit")
	ok(credit.visible and credit.text.contains("YiHuiShiBY") and credit.text.contains("CC BY 4.0"), "and carries the credit")
	ok(await _until(func(): return c.space == "thousand" and c.journey_to == "", 6.0), "the child arrives (%s, journey_to %s, arrived %s, %.2f s)" % [c.space, c.journey_to, c._journey_arrived, c._journey_elapsed])
	# ---- arrival
	eq(world.view_space, "thousand", "the world shows Thousand Town")
	ok(world.thousand_world != null and world.thousand_world.visible and not world._town.visible, "its world is built and shown, the town hidden")
	ok(c.pos.distance_to(Places.THOUSAND_ARRIVALS[0]) < 0.05 and is_equal_approx(c.ry, snappedf(PI / 2.0, 0.01)), "at the station forecourt facing east (%s, %.2f)" % [c.pos, c.ry])
	ok(rig.on_thousand, "the follow camera")
	await process_frame
	var kid: Node3D = world.local_kid()
	var cam: Camera3D = rig.camera
	ok(cam.global_position.x < kid.global_position.x - 6.5 and absf(cam.global_position.z - kid.global_position.z) < 0.05,
		"the camera stands behind the child (%s)" % cam.global_position)
	ok(absf(cam.global_position.y - kid.global_position.y - 2.6) < 0.05, "2.6 m above the child's feet (%.2f)" % (cam.global_position.y - kid.global_position.y))
	ok((-cam.global_basis.z).x > 0.97, "looking east (+x) (%s)" % (-cam.global_basis.z))
	var at = cam.unproject_position(kid.global_position + Vector3(0, 0.9, 0))
	ok((at as Vector2).y > cam.get_viewport().get_visible_rect().size.y * 0.55, "the child in the lower part of the picture (%s)" % str(at))
	ok(Thousand.states["started"] and Thousand.states["day"] == 1, "the town's clock is running for this device")
	# ---- the HUD
	ok(hud._ride_home.visible, "Ride home")
	ok(hud._location.visible and hud._location.text.begins_with("Thousand Town"), "the place is named (%s)" % hud._location.text)
	ok(hud._thousand_time.visible and hud._thousand_look.visible, "the time buttons and Look")
	ok(not hud._city_weather.visible and not hud._city_look.visible, "not the city's")
	eq(hud._thousand_time_btns.keys(), ["day", "dusk", "night", "auto"], "sun, sunset, moon, auto")
	# ---- time modes through the authority
	(hud._thousand_time_btns["night"] as Button).pressed.emit()
	ok(await _until(func(): return Thousand.states["mode"] == "night", 3.0), "Night through the button")
	eq(Thousand.clock["minute"], 1290.0, "21:30")
	ok(is_equal_approx((hud._thousand_time_btns["night"] as Button).modulate.a, 1.0) and (hud._thousand_time_btns["day"] as Button).modulate.a < 1.0, "the Night button is lit")
	await create_timer(0.3).timeout
	eq(Thousand.clock["minute"], 1290.0, "and holds")
	ok(float(world.thousand_world.light.get("daylight", 1.0)) < 0.05, "the world draws night")
	(hud._thousand_time_btns["auto"] as Button).pressed.emit()
	ok(await _until(func(): return Thousand.states["mode"] == "auto", 3.0), "Auto resumes")
	eq(hud.thousand_speed_badge(), "1×", "badge 1x")
	(hud._thousand_time_btns["auto"] as Button).pressed.emit()
	ok(await _until(func(): return int(Thousand.states["speed"]) == 2, 3.0), "a second press: 2x")
	eq(hud.thousand_speed_badge(), "2×", "badge 2x")
	(hud._thousand_time_btns["auto"] as Button).pressed.emit()
	ok(await _until(func(): return int(Thousand.states["speed"]) == 4, 3.0), "4x")
	(hud._thousand_time_btns["auto"] as Button).pressed.emit()
	ok(await _until(func(): return int(Thousand.states["speed"]) == 1, 3.0), "and back to 1x")
	var m0: float = Thousand.clock["minute"]
	await create_timer(1.0).timeout
	ok(float(Thousand.clock["minute"]) > m0 + 0.5, "auto advances in play (%.2f -> %.2f)" % [m0, float(Thousand.clock["minute"])])
	(hud._thousand_time_btns["day"] as Button).pressed.emit()
	ok(await _until(func(): return Thousand.states["mode"] == "day", 3.0), "Day")
	# ---- walking in the town: the canal holds
	c.pos = Vector2(-9.0, 0.0)
	rig.t_yaw = PI / 2.0 + PI    # the camera west of the child: the stick's forward is east (+x)
	rig._t_manual = 99.0
	rig.snap()
	c.pad_move = Vector2(0, -1)   # forward
	for i in 30:
		await physics_frame
	c.pad_move = Vector2.ZERO
	ok(c.pos.x <= -7.7 and c.pos.x > -9.0, "walking east stops at the canal (%s)" % c.pos)
	rig._t_manual = 0.0
	# ---- a late friend in the town shows; one in town does not
	_friend(95, "thousand", Vector2(-62.0, 20.0))
	_friend(96, "town", Vector2(0.0, 5.0))
	world._sync_players()
	ok(world.kids[95].visible and not world.kids[96].visible, "friends in Thousand Town show, friends at home do not")
	Session.players.erase(95)
	Session.players.erase(96)
	world._sync_players()
	# ---- Who's here? at a door, with fake data
	hud.inspect_provider = _fake_provider
	var door: Vector2 = ThousandWorld.door_point("terrace_housing")
	c.pos = door
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "thousand_inspect", 2.0), "near a door: Who's here? (%s)" % str(c._ctx))
	eq(c._ctx.get("id", ""), "h-terrace", "for that building")
	ok(hud._context_btn.visible and hud._context_btn.text == "Who's here?", "the action button offers it")
	ok(await _until(func(): return hud._location.text.contains("Terrace Housing"), 2.0), "the place line names the building (%s; door %s)" % [hud._location.text, str(world.thousand_world.door_near(c.pos, 2.0).get("id", ""))])
	hud._context_btn.pressed.emit()
	await process_frame
	var panel: Node = hud.thousand_inspect_panel()
	ok(panel != null, "the inspect panel opens")
	if panel != null:
		var status: Label = panel.get_node("Status")
		ok(status.text.contains("Closed") and status.text.contains("2"), "closed, two here now (%s)" % status.text)
		var list: Node = panel.find_child("List", true, false)
		eq(list.get_child_count(), 2, "two residents here now")
		(list.get_child(0) as Button).pressed.emit()
		await process_frame
		eq(panel.picked, "r12", "picking a resident")
		var detail: Node = panel.find_child("Detail", true, false)
		eq((detail.get_node("Name") as Label).text, "Mia Chen", "shows the name")
		ok((detail.get_node("Who") as Label).text.contains("Teacher") and (detail.get_node("Who") as Label).text.contains("34"), "role and age")
		var now_rows := detail.get_children().filter(func(n): return n.has_meta("now"))
		eq(now_rows.size(), 1, "today's plan with the current part highlighted")
		(panel.find_child("Tab_lives", true, false) as Button).pressed.emit()
		await process_frame
		eq(panel.tab, "lives", "Lives here")
		eq(list.get_child_count(), 1, "one lives here")
		# B closes it (the controller layer, as on a TV)
		var pad: Node = PadInput.new()
		var fm := FakeMain.new()
		fm.hud = hud
		fm.controller = c
		fm.rig = rig
		holder.add_child(fm)
		holder.add_child(pad)
		pad.bind(fm)
		ok(pad.is_modal(), "the panel is a dialog for the controller")
		pad._back()
		ok(await _until(func(): return hud.thousand_inspect_panel() == null, 2.0), "B closes the panel")
		# ---- the TV's focus order: every new button is a target
		TvMode.forced = 1
		await process_frame
		var targets: Array = pad.targets()
		var missing := []
		for m in hud._thousand_time_btns:
			if not targets.has(hud._thousand_time_btns[m]):
				missing.append(m)
		if not targets.has(hud._thousand_look):
			missing.append("look")
		eq(missing, [], "the time buttons and Look are in the TV's focus order")
		# the right stick orbits instead of moving the pointer
		var y0: float = rig.t_yaw
		var cur0: Vector2 = pad.cursor
		pad.device = 0
		pad._axes = {JOY_AXIS_RIGHT_X: 1.0, JOY_AXIS_RIGHT_Y: 0.0}
		pad._process(0.1)
		pad._axes = {}
		ok(not is_equal_approx(rig.t_yaw, y0) and pad.cursor == cur0, "the right stick orbits the camera, not the pointer")
		pad.device = -1
		TvMode.forced = 0
		pad.queue_free()
		fm.queue_free()
	# ---- Look: the overview and back
	hud._thousand_look.pressed.emit()
	ok(c.thousand_looking and rig.t_overview, "Look flies to the overview")
	rig.snap()
	ok(cam.global_position.is_equal_approx(rig.T_OVERVIEW_EYE), "(there)")
	c.set_thousand_look(false)
	ok(not rig.t_overview, "and back")
	# ---- home
	_hints.clear()
	hud._ride_home.pressed.emit()
	ok(await _until(func(): return c.space == "town" and c.journey_to == "", 6.0), "Ride home")
	eq(world.view_space, "town", "the town is in view")
	ok(not world.thousand_world.visible and world._town.visible, "Thousand Town hidden")
	ok(not rig.on_thousand and is_equal_approx(cam.far, 220.0), "the town's camera again")
	ok(not hud._thousand_time.visible and not hud._thousand_look.visible, "no time buttons at home")
	var held: float = Thousand.clock["minute"]
	await create_timer(0.5).timeout
	eq(Thousand.clock["minute"], held, "the clock stands still with nobody there")
	# ---- an invitation into Thousand Town: the tram, then a walk to the friend
	Session._last_journey.clear()
	c.travel_to("thousand", Vector2(-50.0, 0.0))
	ok(await _until(func(): return c.space == "thousand" and c.journey_to == "", 6.0), "an invitation takes the tram there")
	ok(await _until(func(): return c.pos.distance_to(Vector2(-50.0, 0.0)) < 2.0, 8.0), "and walks to the friend (%s)" % c.pos)
	Session._last_journey.clear()
	c.ride("town")
	ok(await _until(func(): return c.space == "town" and c.journey_to == "", 6.0), "home")
	holder.queue_free()
	await process_frame
