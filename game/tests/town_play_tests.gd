## Headless tests for the follow-on slices (design/town-evenings-and-more.md): the evening
## lamplighter walk, signal rails, weather toys, the picture board, friend echoes and animal
## passengers: their pure rules, saves, and the authority running them for real (solo).
##   godot --headless --path game -s res://tests/town_play_tests.gd
## It reuses the helpers of puzzle_ride_tests.gd. Real clients: scripts/net_test.py --townplay.
extends "res://tests/puzzle_ride_tests.gd"

const Lamplight := preload("res://scripts/core/lamplight.gd")
const PictureBoard := preload("res://scripts/core/picture_board.gd")
const Echoes := preload("res://scripts/core/echoes.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	for t in ["test_lamplight_rules", "test_signal_rules", "test_weather_rules", "test_board_rules", "test_echo_rules", "test_passenger_rules"]:
		_current = t
		call(t)
	for t in ["test_lamplight_session", "test_signal_session", "test_weather_session", "test_board_session", "test_echo_session", "test_passenger_session"]:
		_current = t
		await call(t)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nTOWN PLAY TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------- the lamplighter walk

func test_lamplight_rules() -> void:
	var m = TownModel.new()
	eq(Lamplight.posts(m), [], "a town without lamp posts")
	ok(not Lamplight.all_lit(m), "is never 'all lit': there is nothing to light")
	var a := _put(m, "lamp_post", "town", 4.0, 4.0)
	var b := _put(m, "lamp_post", "town", 8.0, 4.0)
	var c := _put(m, "lamp_post", "town", 12.0, 4.0)
	_put(m, "floor_lamp", "town", 6.0, 8.0) if Catalog.allowed_in("floor_lamp", "town") else ""
	eq(Lamplight.posts(m), [a, b, c], "the lamp posts outdoors, oldest first")
	eq(Lamplight.count(m), [0, 3], "none lit yet")
	eq(Lamplight.check(m, a, "town", Vector2(4.0, 5.5)), "", "next to a lamp")
	eq(Lamplight.check(m, a, "town", Vector2(4.0, 9.0)), Lamplight.ERR_WALK, "too far to reach it")
	eq(Lamplight.check(m, a, "i1:0:0", Vector2(4.0, 5.5)), Lamplight.ERR_WALK, "not from indoors")
	eq(Lamplight.check(m, "i999", "town", Vector2.ZERO), Lamplight.ERR_NOT_HERE, "a lamp that is gone")
	var bench := _put(m, "bench", "town", 4.0, 12.0)
	eq(Lamplight.check(m, bench, "town", Vector2(4.0, 12.5)), Lamplight.ERR_NOT_HERE, "only lamp posts are lit by hand")
	m.set_lamp_on(a, true)
	m.set_lamp_on(b, true)
	eq(Lamplight.count(m), [2, 3], "two lit")
	ok(not Lamplight.all_lit(m), "not all yet")
	m.set_lamp_on(c, true)
	ok(Lamplight.all_lit(m), "all three lit")
	m.wrap(c, "a", "Sky", "", 1)
	eq(Lamplight.posts(m), [a, b], "a wrapped lamp post is a present, not a lamp to light")
	eq(Lamplight.check(m, c, "town", Vector2(12.0, 5.0)), Lamplight.ERR_NOT_HERE, "and cannot be lit")
	m.unwrap(c, "a")
	m.set_lamp_on(b, false)
	ok(not Lamplight.all_lit(m), "one put out again")
	# A lamp lit by hand is saved like one a contraption switched on, and a town without one saves as before.
	var back = TownModel.new()
	back.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	eq(Lamplight.count(back), [2, 3], "lit lamps are lit again after loading")
	eq(m.to_dict()["schema"], TownModel.SCHEMA, "the save format is the current schema (3 since the zoo; this feature added none)")


func test_lamplight_session() -> void:
	await process_frame
	eq(Session.PROTOCOL, 20, "protocol 20")
	await _fresh_town("user://test_lamplight.json")
	var me: int = Session.my_id
	var fired := []
	var on_light := func(by): fired.append(by)
	Session.lamplight.connect(on_light)
	# Two lamp posts of our own, added to whatever the default town has.
	var spot = Session.model.find_free_spot("lamp_post", "town", Vector2(-12, 12))
	var a := await _place("lamp_post", spot)
	var b := await _place("lamp_post", Session.model.find_free_spot("lamp_post", "town", spot + Vector2(4, 0)))
	var all: Array = Lamplight.posts(Session.model)
	ok(all.has(a) and all.has(b), "the town has %d lamp posts" % all.size())
	ok(not Session.model.evening, "it is day")
	_go("town", spot + Vector2(0, 8))
	eq((await _result(Session.toggle_lamp(a))).get("error"), Lamplight.ERR_WALK, "a lamp is lit from next to it")
	var some_bench: Array = Session.model.items.values().filter(func(i): return i["kind"] == "bench")
	if not some_bench.is_empty():
		_go("town", Vector2(some_bench[0]["x"], some_bench[0]["z"]))
		eq((await _result(Session.toggle_lamp(some_bench[0]["id"]))).get("error"), Lamplight.ERR_NOT_HERE, "a bench is not a lamp")
	eq((await _result(Session._ask("lamp", ["i99999"]))).get("error"), Lamplight.ERR_NOT_HERE, "an id that does not exist is refused kindly")
	# Light every lamp post by day: lamps shine, nothing gathers.
	for id in all:
		var it: Dictionary = Session.model.items[id]
		_go("town", Vector2(it["x"], it["z"]) + Vector2(0, 1.0))
		var r := await _result(Session.toggle_lamp(id))
		ok(r.get("ok", false) and r.get("on", false), "lamp %s is lit by hand (%s)" % [id, str(r.get("error", "ok"))])
	eq(Lamplight.count(Session.model), [all.size(), all.size()], "every lamp post is lit")
	eq(fired, [], "by day the fireflies do not gather")
	# The evening bell with every lamp already lit: they gather at once, one time.
	ok((await _result(Session.ring_bell())).get("ok", false) and Session.model.evening, "the evening bell rings")
	eq(fired.size(), 1, "every lamp is lit this evening: the fireflies gather")
	eq(fired[0], [Session.nick_of(me)], "for everyone in town, by name")
	var ia: Dictionary = Session.model.items[a]
	_go("town", Vector2(ia["x"], ia["z"]) + Vector2(0, 1.0))
	var off := await _result(Session.toggle_lamp(a))
	ok(off.get("ok", false) and not off.get("on", true) and off.get("lit") == [all.size() - 1, all.size()], "a lamp is put out again (%s)" % str(off))
	ok((await _result(Session.toggle_lamp(a))).get("on", false), "and lit again")
	eq(fired.size(), 1, "once per evening: lighting it again does not repeat the moment")
	# Morning, one lamp out, evening: nothing yet. A contraption lights the last lamp: they gather.
	await _result(Session.ring_bell())
	ok(not Session.model.evening, "morning")
	await _result(Session.toggle_lamp(a))
	ok(not Session.model.items[a].get("on", false), "one lamp is put out by day")
	await _result(Session.ring_bell())
	eq(fired.size(), 1, "evening with a lamp still dark: nothing gathers")
	var button := await _place("push_button", Session.model.find_free_spot("push_button", "town", Vector2(ia["x"], ia["z"]) + Vector2(0, 1.4)))
	ok(Contraptions.linked(Session.model, button).has(a), "a Big button next to the dark lamp")
	_go("town", Vector2(Session.model.items[button]["x"], Session.model.items[button]["z"]) + Vector2(0, 0.8))
	# Other lamp posts in reach of the button would be switched off by it; this one stands apart.
	eq(Contraptions.plan(Session.model, button).filter(func(s): return s["effect"] == "light").map(func(s): return s["id"]), [a], "only that lamp is in the button's chain")
	ok((await _result(Session.press(button))).get("fired", false), "the button is pressed")
	await create_timer(0.9).timeout
	ok(Session.model.items[a].get("on", false), "the contraption lights the lamp")
	eq(fired.size(), 2, "the last lamp lit by a contraption counts too: the fireflies gather this evening")
	# Saved and loaded: lamps stay lit; the moment itself is not saved.
	ok(Session.save_now(), "saved")
	Session.lamplight.disconnect(on_light)
	Session.leave()
	Session.start_solo("user://test_lamplight.json", Avatar.PRESETS[0])
	await process_frame
	ok(Lamplight.all_lit(Session.model) and Session.model.evening, "after loading it is still evening and every lamp is lit")
	Session.leave()


# ------------------------------------------------------------- signal rails

## A 3 x 2 ring whose straight piece (opposite the station) is a signal rail.
func _signal_ring(cx: int, cz: int) -> Array:
	var pieces := _ring(cx, cz, 3, 2)
	pieces[3][0] = RideRules.SIGNAL
	return pieces


func test_signal_rules() -> void:
	ok(RideRules.is_rail(RideRules.SIGNAL) and Contraptions.is_trigger(RideRules.SIGNAL) and not Contraptions.is_reactor(RideRules.SIGNAL), "a signal rail is a rail and a contraption trigger")
	eq([Catalog.grid(RideRules.SIGNAL), Catalog.ITEMS[RideRules.SIGNAL]["layer"], Catalog.ITEMS[RideRules.SIGNAL]["space"]], [RideRules.CELL, "flat", "town"], "it lies flat outdoors on 2 m cells like the other rails")
	var m = TownModel.new()
	var ids := _lay(m, _signal_ring(2, 2))
	var r: Dictionary = RideRules.route(m, ids[0])
	eq([r["end"], r["legs"].size()], ["loop", 6], "a ring with a signal rail in it is still a circuit")
	eq(r["signals"], [[3, ids[3]]], "the route knows its signal rail and where it is")
	var lap: float = RideRules.total_length(r)
	var at := 1.0 + PI + 1.0   # half the station, two curves, half the signal rail
	eq(RideRules.signals_between(r, 0.0, at - 0.01), [], "before the cart reaches its middle: nothing")
	eq(RideRules.signals_between(r, at - 0.01, at + 0.01), [ids[3]], "passing the middle: the signal")
	eq(RideRules.signals_between(r, at, at + 1.0), [], "a passing counts once: not again from exactly there")
	eq(RideRules.signals_between(r, at + 0.01, lap), [], "after it: nothing for the rest of the lap")
	eq(RideRules.signals_between(r, 0.0, lap * 3.0), [ids[3], ids[3], ids[3]], "three laps: three times")
	eq(RideRules.signals_between(r, lap + at - 0.2, lap + at + 0.2), [ids[3]], "the second lap's passing")
	eq(RideRules.signals_between(r, 5.0, 5.0), [], "no movement, no signal")
	# The lamp beside the signal rail is linked to it; one standing on the rails would block them.
	var sig: Dictionary = m.items[ids[3]]
	var lamp := _put(m, "lamp_post", "town", sig["x"], sig["z"] + 1.6)
	eq(Contraptions.linked(m, ids[3]), [lamp], "a lamp 1.6 m beside a signal rail is linked to it")
	eq(RideRules.route(m, ids[0])["end"], "loop", "and does not stand in the cart's way")
	# Two signals on an open track, in riding order.
	var open = TownModel.new()
	var st := _put(open, "ride_station", "town", 4.0, 4.0, 2)
	var s1 := _put(open, "ride_signal", "town", 6.0, 4.0, 2)
	var s2 := _put(open, "ride_signal", "town", 8.0, 4.0, 2)
	var ro: Dictionary = RideRules.route(open, st)
	eq(ro["signals"], [[1, s1], [2, s2]], "two signal rails in a row")
	eq(RideRules.signals_between(ro, 0.0, 10.0), [s1, s2], "passed in riding order")
	eq(RideRules.signals_between(ro, 0.0, RideRules.end_distance(ro)), [s1, s2], "the cart stops 0.7 m before the end, past the last signal's middle")
	open.wrap(s1, "a", "Sky", "", 1)
	eq(RideRules.route(open, st)["end"], "end", "a wrapped signal rail is a present: the rails end before it")


func test_signal_session() -> void:
	await process_frame
	await _fresh_town("user://test_signals.json")
	var origin := Vector2i(99, 99)
	for cx in range(-10, 8):
		for cz in range(2, 8):
			var pieces := _signal_ring(cx, cz)
			if origin.x == 99 and pieces.all(func(p): return Session.model.check(p[0], "town", p[1].x * 2.0, p[1].y * 2.0, p[2]) == "") \
					and RideRules._solids(Session.model).all(func(s): return s[0].distance_to(Vector2(cx * 2.0 + 2.0, cz * 2.0 + 1.0)) > 5.5 + s[1]) \
					and Session.model.items_in("town").all(func(i): return not Contraptions.takes_part(i["kind"]) or Vector2(i["x"], i["z"]).distance_to(Vector2(cx * 2.0 + 2.0, cz * 2.0 + 1.0)) > 7.0):
				origin = Vector2i(cx, cz)
	ok(origin.x != 99, "found room for a ring with a signal rail")
	var pieces := _signal_ring(origin.x, origin.y)
	var ids := []
	for p in pieces:
		ids.append(await _place(p[0], Vector2(p[1]) * 2.0, p[2]))
	var station: String = ids[0]
	var sig_at := Vector2(pieces[3][1]) * 2.0
	var wheel := await _place("pinwheel", sig_at + Vector2(0, 1.6))
	eq(Contraptions.linked(Session.model, ids[3]), [wheel], "a pinwheel beside the signal rail")
	eq(RideRules.route(Session.model, station)["end"], "loop", "the ring is whole with the pinwheel beside it")
	var log := []
	var on_trig := func(id): log.append(["trigger", id])
	var on_react := func(id, from, effect, _on): log.append([effect, id, from])
	Session.contraption_triggered.connect(on_trig)
	Session.contraption_reacted.connect(on_react)
	_go("town", Vector2(pieces[0][1]) * 2.0 + Vector2(0, 1.6))
	ok((await _result(Session.ride(station, "board"))).get("ok", false), "in the cart")
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "Go!")
	await create_timer(0.3).timeout
	eq(log, [], "the cart has not reached the signal rail yet")
	var middle := 1.0 + PI + 1.0
	var skip := func(to: float):   # as if time had passed until the cart is `to` meters along
		Session.rides[station]["t"] -= int((to - Session.ride_distance(station)) / RideRules.SPEED * 1000.0)
	skip.call(middle + 0.3)
	await process_frame
	await process_frame
	eq(log, [["trigger", ids[3]]], "riding over the signal rail sets it off")
	await create_timer(0.7).timeout
	eq(log, [["trigger", ids[3]], ["spin", wheel, ids[3]]], "and the pinwheel beside it spins")
	# Stopped past the signal: nothing more. The next lap: again.
	ok((await _result(Session.ride(station, "stop"))).get("ok", false), "Stop")
	await create_timer(0.3).timeout
	eq(log.size(), 2, "a cart standing still sets nothing off")
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "Go! again")
	await create_timer(1.3).timeout   # the trigger rests 1.2 s
	skip.call(RideRules.total_length(Session.rides[station]["route"]) + middle + 0.3)
	await process_frame
	await process_frame
	eq(log.filter(func(e): return e[0] == "trigger").size(), 2, "the second time round sets it off again")
	# The signal rail put away ahead of the cart: the cart rides to the new end, and nothing is set off.
	await create_timer(1.3).timeout
	var lap_len: float = RideRules.total_length(Session.rides[station]["route"])
	skip.call(2.0 * lap_len + 0.6)   # early in the third lap, before the signal rail
	await process_frame
	await process_frame
	log.clear()
	ok(RideRules.locate(Session.rides[station]["route"], Session.ride_distance(station))["leg"] < 3, "the cart is before the signal rail again")
	ok((await _result(Session.remove(ids[3]))).get("ok", false), "the signal rail is put away ahead of the cart")
	eq([Session.rides[station]["route"]["signals"], Session.rides[station]["route"]["end"], Session.rides[station]["phase"]], [[], "end", "moving"], "the cart's route has no signal any more and ends before the gap")
	Session.rides[station]["t"] -= 60000
	await process_frame
	await process_frame
	eq(log.filter(func(e): return e[0] == "trigger"), [], "no signal, nothing set off")
	eq([Session.rides[station]["phase"], Session.rides[station]["why"]], ["stopped", "end"], "the ride ended safely at the end of the rails")
	# Put back behind a cart that stands past it: the cart is on rails again, and a standing cart sets nothing off.
	ids[3] = await _place(RideRules.SIGNAL, sig_at, pieces[3][2])
	await create_timer(0.3).timeout
	eq(log.filter(func(e): return e[0] == "trigger"), [], "a signal rail placed while the cart stands sets nothing off")
	await _result(Session.stand())
	Session.contraption_triggered.disconnect(on_trig)
	Session.contraption_reacted.disconnect(on_react)
	Session.leave()


# ------------------------------------------------------------- weather toys

func test_weather_rules() -> void:
	ok(Contraptions.is_trigger("weather_bell") and not Contraptions.is_reactor("weather_bell"), "a weather bell sets things off")
	ok(Catalog.allowed_in("weather_bell", "town") and not Catalog.allowed_in("weather_bell", "i1:0:0"), "it belongs outdoors, where the weather is")
	var m = TownModel.new()
	var bell := _put(m, "weather_bell", "town", 4.0, 4.0)
	var wheel := _put(m, "pinwheel", "town", 5.5, 4.0)
	var box := _put(m, "music_box", "town", 7.0, 4.0)
	eq(Contraptions.plan(m, bell).map(func(s): return [s["id"], s["hop"]]), [[wheel, 1], [box, 2]], "a weather bell starts a chain like any trigger")


func test_weather_session() -> void:
	await process_frame
	await _fresh_town("user://test_weather.json")
	var base := Vector2(99, 99)
	for x in range(-22, 16):
		for z in range(8, 16):
			var c := Vector2(x, z)
			if base.x == 99 and [["weather_bell", 0.0], ["pinwheel", 1.5]].all(func(e): return Session.model.check(e[0], "town", c.x + e[1], c.y, 0) == "") \
					and Session.model.items_in("town").all(func(i): return not Contraptions.takes_part(i["kind"]) or Vector2(i["x"], i["z"]).distance_to(c) > 6.0):
				base = c
	ok(base.x != 99, "found room for a weather bell")
	var before: String = Session.model.weather
	var none := await _result(Session.change_weather())
	ok(none.get("ok", false) and none.get("bells") == 0 and Session.model.weather != before, "the weather changes; with no weather bell nothing rings (%s)" % str(none))
	var bell := await _place("weather_bell", base)
	var wheel := await _place("pinwheel", base + Vector2(1.5, 0))
	var log := []
	var on_trig := func(id): log.append(["trigger", id])
	var on_react := func(id, from, effect, _on): log.append([effect, id, from])
	Session.contraption_triggered.connect(on_trig)
	Session.contraption_reacted.connect(on_react)
	_go("town", Vector2(20, -18))   # far from the bell: the weather is everywhere
	var r := await _result(Session.change_weather())
	ok(r.get("ok", false) and r.get("bells") == 1, "the weather changes and the bell rings, wherever the child is (%s)" % str(r))
	eq(log, [["trigger", bell]], "the bell is set off")
	await create_timer(0.7).timeout
	eq(log, [["trigger", bell], ["spin", wheel, bell]], "and the pinwheel beside it answers")
	await create_timer(1.3).timeout
	log.clear()
	await _result(Session.wrap(bell, "", 2))
	r = await _result(Session.change_weather())
	eq([r.get("bells"), log], [0, []], "a wrapped bell is a present: it does not ring")
	eq(TownModel.WEATHERS.has(Session.model.weather), true, "the weather is always one of the four")
	Session.contraption_triggered.disconnect(on_trig)
	Session.contraption_reacted.disconnect(on_react)
	Session.leave()


# ------------------------------------------------------------- the picture board

func test_board_rules() -> void:
	eq(PictureBoard.blank(), "0".repeat(64), "an empty picture is 64 empty squares")
	eq(PictureBoard.sanitize("12345678".repeat(8)), "12345678".repeat(8), "a whole picture stays as it is")
	eq(PictureBoard.sanitize("123"), PictureBoard.blank(), "a picture of the wrong length becomes empty")
	eq(PictureBoard.sanitize(77), PictureBoard.blank(), "something that is not a picture becomes empty")
	eq(PictureBoard.sanitize("9x-" + "1".repeat(61)), "000" + "1".repeat(61), "squares that are no color become empty")
	eq(PictureBoard.cell(PictureBoard.with_cell(PictureBoard.blank(), 9, 4), 9), 4, "one square painted")
	ok(PictureBoard.valid(0, 0) and PictureBoard.valid(63, 8) and not PictureBoard.valid(64, 1) and not PictureBoard.valid(-1, 1) and not PictureBoard.valid(3, 9) and not PictureBoard.valid(3, -1),
		"squares 0 to 63, colors 0 (rub out) to 8")
	var m = TownModel.new()
	var board := _put(m, "picture_board", "town", 4.0, 4.0)
	eq(m.items[board]["pix"], PictureBoard.blank(), "a new board is empty")
	ok(m.set_pixel(board, 0, 3)["ok"] and m.set_pixel(board, 63, 8)["ok"], "two squares are painted")
	eq([PictureBoard.cell(m.items[board]["pix"], 0), PictureBoard.cell(m.items[board]["pix"], 63), PictureBoard.cell(m.items[board]["pix"], 1)], [3, 8, 0], "and only those")
	eq(m.set_pixel(board, 64, 1).get("error"), PictureBoard.ERR_SQUARE, "a square off the board is refused")
	eq(m.set_pixel(board, 5, 12).get("error"), PictureBoard.ERR_SQUARE, "a color that does not exist is refused")
	var bench := _put(m, "bench", "town", 8.0, 8.0)
	eq(m.set_pixel(bench, 0, 1).get("error"), TownModel.ERR_GONE, "a bench has no picture")
	eq(PictureBoard.check(m, board, "town", Vector2(4.0, 5.5)), "", "next to the board")
	eq(PictureBoard.check(m, board, "town", Vector2(4.0, 9.0)), PictureBoard.ERR_WALK, "too far to paint")
	eq(PictureBoard.check(m, bench, "town", Vector2(8.0, 8.5)), PictureBoard.ERR_NOT_HERE, "not a board")
	# Saved, loaded, damaged, undone.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	var back = TownModel.new()
	ok(back.from_dict(saved), "a town with a painted board loads")
	eq(back.items[board]["pix"], m.items[board]["pix"], "with its picture")
	for it in saved["items"]:
		if it["id"] == board:
			it["pix"] = [1, 2, 3]
	var hurt = TownModel.new()
	ok(hurt.from_dict(saved) and hurt.items[board]["pix"] == PictureBoard.blank(), "a damaged picture becomes an empty board; the town still loads")
	var removed: Dictionary = m.remove(board)
	var again: Dictionary = m.restore(removed["removed"])
	ok(again["ok"] and m.items[again["items"][0]["id"]]["pix"] == removed["removed"][0]["pix"], "Undo brings the board back with its picture")
	m.wrap(again["items"][0]["id"], "a", "Sky", "", 1)
	eq(m.set_pixel(again["items"][0]["id"], 0, 1).get("error"), TownModel.ERR_GONE, "a wrapped board is a present")
	# The built board shows its painted squares.
	var Props = load("res://scripts/art/props.gd")
	var empty: Node3D = Props.build("picture_board", 7, 1, 3, 0, {"pix": PictureBoard.blank()})
	var painted: Node3D = Props.build("picture_board", 7, 1, 3, 0, {"pix": "123" + "0".repeat(61)})
	eq([empty.get_node("Face/Cells").get_child_count(), painted.get_node("Face/Cells").get_child_count() > 0], [0, true], "an empty board has no tiles, a painted one has")
	empty.free()
	painted.free()


func test_board_session() -> void:
	await process_frame
	await _fresh_town("user://test_board.json")
	var at = Session.model.find_free_spot("picture_board", "town", Vector2(-10, 12))
	var board := await _place("picture_board", at)
	var seen := []
	var on_item := func(item): seen.append(item.get("pix", ""))
	Session.item_changed.connect(on_item)
	_go("town", at + Vector2(0, 8))
	eq((await _result(Session.set_pixel(board, 0, 3))).get("error"), PictureBoard.ERR_WALK, "a board is painted from next to it")
	_go("town", at + Vector2(0, 1.2))
	ok((await _result(Session.set_pixel(board, 0, 3))).get("ok", false), "one square painted")
	eq([PictureBoard.cell(Session.model.items[board]["pix"], 0), seen.size()], [3, 1], "the town has it, and every device is told once")
	eq((await _result(Session.set_pixel(board, 99, 1))).get("error"), PictureBoard.ERR_SQUARE, "a square off the board is refused by the authority")
	eq((await _result(Session.set_pixel(board, 1, 40))).get("error"), PictureBoard.ERR_SQUARE, "so is a color that does not exist")
	eq((await _result(Session.set_pixel("i99999", 1, 1))).get("error"), PictureBoard.ERR_NOT_HERE, "and a board that does not exist")
	# A friend paints another square at the same time: both stay.
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": at.x, "z": at.y + 1.2, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_pixel(77, 0, board, 5, 2)
	ok((await _result(Session.set_pixel(board, 6, 1))).get("ok", false), "my next square")
	eq([PictureBoard.cell(Session.model.items[board]["pix"], 0), PictureBoard.cell(Session.model.items[board]["pix"], 5), PictureBoard.cell(Session.model.items[board]["pix"], 6)], [3, 2, 1], "the friend's square and mine are all there")
	ok((await _result(Session.set_pixel(board, 0, 0))).get("ok", false) and PictureBoard.cell(Session.model.items[board]["pix"], 0) == 0, "color 0 rubs a square out")
	# On display by someone else: painting is refused, like editing a music box's tune.
	Session.model.set_display("town", true, "someone-else", "Sky")
	eq((await _result(Session.set_pixel(board, 7, 1))).get("error"), "This place is on display.", "a board in a place on display is not painted by others")
	Session.model.set_display("town", false, "someone-else", "Sky")
	Session.players.erase(77)
	ok(Session.save_now(), "saved")
	var pix: String = Session.model.items[board]["pix"]
	Session.item_changed.disconnect(on_item)
	Session.leave()
	Session.start_solo("user://test_board.json", Avatar.PRESETS[0])
	await process_frame
	eq(Session.model.items[board]["pix"], pix, "the picture is there after loading")
	Session.leave()


# ------------------------------------------------------------- friend echoes

func test_echo_rules() -> void:
	var m = TownModel.new()
	var av: Dictionary = Avatar.PRESETS[0]
	var now := 1000000
	eq(Echoes.leave(m, "p1", av, "town", Vector2(3, 4), 0.5, ["wave", "dance"], now).get("error"), Echoes.ERR_EMOTES, "a hello is exactly three emotes")
	eq(Echoes.leave(m, "p1", av, "town", Vector2(3, 4), 0.5, ["wave", "dance", "shout"], now).get("error"), Echoes.ERR_EMOTES, "from the list")
	eq(Echoes.leave(m, "p1", av, "town", Vector2(3, 4), 0.5, "wave", now).get("error"), Echoes.ERR_EMOTES, "and nothing else is taken")
	eq(Echoes.leave(m, "p1", av, "i99:0:0", Vector2(3, 4), 0.5, ["wave", "dance", "heart"], now).get("error"), Echoes.ERR_PLACE, "in a place that exists")
	var r: Dictionary = Echoes.leave(m, "p1", av, "town", Vector2(3.02, 4.0), 0.5, ["wave", "dance", "heart"], now)
	ok(r["ok"] and m.echoes.size() == 1, "a hello is left")
	var e: Dictionary = m.echoes["p1"]
	eq([e["nick"], e["space"], e["x"], e["emotes"], e["t"], e["answers"]], [Avatar.sanitize(av)["nick"], "town", 3.0, ["wave", "dance", "heart"], now, {}], "with a name from the list, its place, three emotes and the time")
	eq(e.keys().filter(func(k): return not k in ["nick", "avatar", "space", "x", "z", "ry", "emotes", "t", "answers"]), [], "and nothing else is kept")
	# Answers.
	eq(Echoes.check_answer(m, "p1", "p1", "town", Vector2(3, 4), now), Echoes.ERR_OWN, "nobody answers their own hello")
	eq(Echoes.check_answer(m, "p1", "p2", "town", Vector2(9, 9), now), Echoes.ERR_WALK, "an answer is given from next to it")
	eq(Echoes.check_answer(m, "p1", "p2", "i1:0:0", Vector2(3, 4), now), Echoes.ERR_WALK, "in the same place")
	eq(Echoes.check_answer(m, "nobody", "p2", "town", Vector2(3, 4), now), Echoes.ERR_GONE, "to a hello that exists")
	eq(Echoes.check_answer(m, "p1", "p2", "town", Vector2(3, 5), now), "", "next to it")
	eq(Echoes.answer(m, "p1", "p2", "Sky", "shout", now).get("error"), Echoes.ERR_EMOTE, "an answer is one emote from the list")
	ok(Echoes.answer(m, "p1", "p2", "Sky", "cheer", now + 10)["ok"], "a friend answers")
	ok(Echoes.answer(m, "p1", "p2", "Sky", "heart", now + 20)["ok"] and m.echoes["p1"]["answers"].size() == 1 and m.echoes["p1"]["answers"]["p2"]["emote"] == "heart", "a second answer from the same friend replaces the first")
	eq(Echoes.new_answers(m, "p1"), ["Sky"], "the creator has one new answer")
	ok(Echoes.mark_seen(m, "p1") and Echoes.new_answers(m, "p1") == [] and not Echoes.mark_seen(m, "p1"), "seen once, no longer new")
	for i in 12:
		Echoes.answer(m, "p1", "f%d" % i, "Mo", "wave", now + 100 + i)
	ok(m.echoes["p1"]["answers"].size() == Echoes.MAX_ANSWERS and m.echoes["p1"]["answers"].has("f11") and not m.echoes["p1"]["answers"].has("p2"), "at most eight answers: the oldest make room, the newest stays")
	# Replace, and the town's limit.
	Echoes.leave(m, "p1", av, "town", Vector2(6, 6), 0.0, ["heart", "heart", "wave"], now + 500)
	eq([m.echoes.size(), m.echoes["p1"]["emotes"], m.echoes["p1"]["answers"]], [1, ["heart", "heart", "wave"], {}], "a new hello replaces the old one, answers and all")
	for i in 15:
		Echoes.leave(m, "q%d" % i, av, "town", Vector2(i, 10), 0.0, ["wave", "wave", "wave"], now + 600 + i)
	ok(m.echoes.size() == Echoes.MAX_ECHOES and m.echoes.has("q14") and not m.echoes.has("p1"), "at most twelve hellos in a town: the oldest make room")
	# Seven days.
	var fresh: Dictionary = m.echoes["q14"]
	eq([Echoes.days_left(fresh, int(fresh["t"])), Echoes.days_left(fresh, int(fresh["t"]) + 6 * 86400 + 5), Echoes.expired(fresh, int(fresh["t"]) + Echoes.LIFETIME - 1), Echoes.expired(fresh, int(fresh["t"]) + Echoes.LIFETIME)],
		[7, 1, false, true], "seven days at first, one on the last day, gone at seven days exactly")
	eq(Echoes.check_answer(m, "q14", "p2", "town", Vector2(14, 10), int(fresh["t"]) + Echoes.LIFETIME), Echoes.ERR_GONE, "an expired hello cannot be answered even before it is cleared away")
	ok(not Echoes.prune(m, now + 700), "nothing to clear away yet")
	ok(Echoes.prune(m, now + 600 + 7 + Echoes.LIFETIME) and m.echoes.size() == 7, "after seven days the older ones are cleared away, the newer ones stay (%d left)" % m.echoes.size())
	# A hello in a house goes with the house.
	var house := _put(m, "cottage", "town", -10.0, -10.0)
	var later := now + 600 + 7 + Echoes.LIFETIME + 5   # the remaining hellos are still within their seven days
	Echoes.leave(m, "inside", av, TownModel.room_space(house, 1, 0), Vector2(0, 0), 0.0, ["wave", "wave", "wave"], later)
	m.remove(house)
	ok(Echoes.prune(m, later) and not m.echoes.has("inside") and m.echoes.has("q14"), "a hello in a house that was put away is cleared away; the others stay")
	eq(Echoes.near(m, "town", Vector2(14, 10.5)), "q14", "the hello next to a point")
	eq(Echoes.near(m, "town", Vector2(-20, -20)), "", "none near there")
	# Saves: only when there is one; damaged entries are dropped; an old save has none.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	ok(saved.has("echoes") and saved["schema"] == TownModel.SCHEMA, "hellos are in the save, in the current schema")
	var back = TownModel.new()
	back.from_dict(saved)
	eq(JSON.stringify(back.echoes), JSON.stringify(m.echoes), "and come back the same")
	saved["echoes"]["bad1"] = {"emotes": ["wave", "wave"], "avatar": av}
	saved["echoes"]["bad2"] = "nonsense"
	saved["echoes"]["bad3"] = {"emotes": ["wave", "wave", "wave"], "avatar": av, "nick": "x".repeat(99), "answers": {"a": {"emote": "shout"}, "b": {"emote": "wave", "nick": "y".repeat(99)}}}
	var hurt = TownModel.new()
	ok(hurt.from_dict(saved), "a save with damaged hellos loads")
	ok(not hurt.echoes.has("bad1") and not hurt.echoes.has("bad2") and hurt.echoes.has("bad3"), "the damaged ones are dropped")
	eq([hurt.echoes["bad3"]["nick"].length() <= 16, hurt.echoes["bad3"]["answers"].keys(), hurt.echoes["bad3"]["answers"]["b"]["nick"].length()], [true, ["b"], 16], "names are cut and come from the list; an answer that is no emote is dropped")
	ok(not TownModel.make_default().to_dict().has("echoes"), "a town without hellos saves without the key, exactly as before")
	var old = TownModel.new()
	old.from_dict(JSON.parse_string(JSON.stringify(TownModel.make_default().to_dict())))
	eq(old.echoes, {}, "an older save has no hellos")
	eq(Echoes.sanitize([1, 2]), {}, "nonsense is no hellos")


func test_echo_session() -> void:
	await process_frame
	var path := "user://test_echoes.json"
	await _fresh_town(path)
	var me: int = Session.my_id
	var pid: String = Session.my_pid
	var told := []
	var on_data := func(key): told.append(key)
	Session.town_data_changed.connect(on_data)
	_go("town", Vector2(3, 12))
	eq((await _result(Session.leave_echo(["wave"]))).get("error"), Echoes.ERR_EMOTES, "the authority wants three emotes")
	eq((await _result(Session._ask("echo_leave", ["not a list"]))).get("error"), Echoes.ERR_EMOTES, "and refuses something that is not a list, kindly")
	eq((await _result(Session._ask("echo_leave", [[1, 2, 3]]))).get("error"), Echoes.ERR_EMOTES, "or a list of something else")
	ok((await _result(Session.leave_echo(["wave", "dance", "heart"]))).get("ok", false), "a hello is left where the child stands")
	eq([Session.model.echoes[pid]["x"], Session.model.echoes[pid]["z"], Session.model.echoes[pid]["space"], told.has("echoes")], [3.0, 12.0, "town", true], "there, and every device is told")
	eq((await _result(Session.answer_echo(pid, "cheer"))).get("error"), Echoes.ERR_OWN, "nobody answers their own hello")
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": 20.0, "z": -15.0, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_echo_answer(77, 0, pid, "cheer")
	eq(Session.model.echoes[pid]["answers"], {}, "a friend far away cannot answer")
	_go("town", Vector2(3.5, 12.8), 77)
	Session._srv_echo_answer(77, 0, pid, "shout")
	eq(Session.model.echoes[pid]["answers"], {}, "nor with something that is no emote")
	Session._srv_echo_answer(77, 0, pid, "cheer")
	eq(Session.model.echoes[pid]["answers"].keys(), ["b".repeat(32)], "next to it, the friend answers")
	eq(Echoes.new_answers(Session.model, pid), [Session.nick_of(77)], "the creator has a new answer")
	Session._srv_echo_delete(77, 0)
	ok(Session.model.echoes.has(pid), "a friend cannot take someone else's hello away (their request is about their own)")
	ok((await _result(Session.seen_echo())).get("ok", false) and Echoes.new_answers(Session.model, pid) == [], "looked at: no longer new")
	# Save and load keeps the hello and its answer.
	ok(Session.save_now(), "saved")
	Session.players.erase(77)
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	pid = Session.my_pid
	ok(Session.model.echoes.has(pid) and Session.model.echoes[pid]["answers"].size() == 1 and Session.model.echoes[pid]["emotes"] == ["wave", "dance", "heart"], "after loading the hello and its answer are there")
	# A new one replaces it; the creator takes it away.
	_go("town", Vector2(5, 12))
	ok((await _result(Session.leave_echo(["heart", "heart", "heart"]))).get("ok", false), "a new hello")
	eq([Session.model.echoes.size(), Session.model.echoes[pid]["x"], Session.model.echoes[pid]["answers"]], [1, 5.0, {}], "replaces the old one")
	var gone := await _result(Session.delete_echo())
	ok(gone.get("ok", false) and gone.get("had", false) and Session.model.echoes.is_empty(), "the creator takes it away")
	ok(not (await _result(Session.delete_echo())).get("had", true), "taking away nothing is fine")
	# Seven days pass (the test moves the clock).
	ok((await _result(Session.leave_echo(["wave", "wave", "wave"]))).get("ok", false), "another hello")
	Session.echo_clock_offset = Echoes.LIFETIME - 60
	Session.prune_echoes()
	ok(Session.model.echoes.has(pid), "a minute before seven days it is still there")
	Session.echo_clock_offset = Echoes.LIFETIME + 60
	told.clear()
	Session.prune_echoes()
	ok(Session.model.echoes.is_empty() and told.has("echoes"), "after seven days it is gone, and every device is told")
	Session.echo_clock_offset = 0
	# One left in a house goes with the house.
	var house: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]
	_go(TownModel.room_space(house["id"], 0, 0), TownModel.ROOM_SPAWN)
	ok((await _result(Session.leave_echo(["dance", "dance", "dance"]))).get("ok", false), "a hello left indoors")
	eq(Session.model.echoes[pid]["space"], TownModel.room_space(house["id"], 0, 0), "in that room")
	_go("town", Vector2(3, 12))
	ok((await _result(Session.remove(house["id"]))).get("ok", false), "the house is put away")
	ok(Session.model.echoes.is_empty(), "and the hello with it")
	# Loaded after its time: gone when the town opens.
	ok((await _result(Session.leave_echo(["wave", "wave", "wave"]))).get("ok", false), "one more")
	ok(Session.save_now(), "saved")
	Session.town_data_changed.disconnect(on_data)
	Session.leave()
	Session.echo_clock_offset = Echoes.LIFETIME + 3600
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	ok(Session.model.echoes.is_empty(), "a town opened eight days later has no old hello")
	Session.echo_clock_offset = 0
	Session.leave()


# ------------------------------------------------------------- animal passengers

func test_passenger_rules() -> void:
	var m = TownModel.new()
	var brain = AnimalBrain.new(7)
	brain.spawn(m)
	var at := Vector2(6, 6)
	for a in brain.animals:
		a["pos"] = Vector2(-20, -18)
		a["plan"] = "rest"
		a["timer"] = 999.0
		a["goal"] = null
	eq(brain.start_ride("elephant", "s1", at), "too_big", "Tumble does not fit in the trailer")
	eq(brain.start_ride("sheep", "s1", at), "far", "an animal far away is not called")
	brain.animal("sheep")["pos"] = at + Vector2(3.0, 0.5)
	eq(brain.start_ride("sheep", "s1", at), "", "Wooly is called for a ride")
	eq([brain.animal("sheep")["plan"], brain.animal("sheep")["ride"], brain.animal("sheep")["aboard"]], ["ride", "s1", false], "and walks to the trailer")
	eq(brain.start_ride("sheep", "s2", at), "taken", "it cannot be called to a second cart")
	for i in 80:
		brain.tick(m, [])
	ok(brain.animal("sheep")["aboard"], "it reaches the trailer and hops in")
	brain.carry("sheep", Vector2(9, 9), 1.0)
	for i in 20:
		brain.tick(m, [])
	eq([brain.animal("sheep")["pos"], brain.animal("sheep")["action"]], [Vector2(9, 9), "rest"], "aboard, it goes where the trailer goes and nowhere else")
	brain.carry("pig", Vector2(1, 1), 0.0)
	ok(brain.animal("pig")["pos"] != Vector2(1, 1), "an animal that is not aboard is not carried")
	brain.end_ride(m, "sheep", at)
	var out: Dictionary = brain.animal("sheep")
	ok(out["ride"] == "" and not out["aboard"] and out["pos"].distance_to(at) < 2.5 and out["plan"] != "ride", "it hops out next to the station and roams again (%.1f m away)" % out["pos"].distance_to(at))
	brain.animal("pig")["pos"] = at + Vector2(2, 0)
	brain.animal("pig")["guest"] = 5
	eq(brain.start_ride("pig", "s1", at), "taken", "an animal visiting a child's house is not called")
	brain.animal("pig")["guest"] = 0
	brain.start_parade(10.0)
	eq(brain.start_ride("pig", "s1", at), "party", "nobody rides during the dance party")


func test_passenger_session() -> void:
	await process_frame
	await _fresh_town("user://test_passengers.json")
	var anim = root.get_node("Animals")
	var me: int = Session.my_id
	var origin := Vector2i(99, 99)
	for cx in range(-10, 8):
		for cz in range(2, 8):
			var pcs := _ring(cx, cz, 4, 2)
			if origin.x == 99 and pcs.all(func(p): return Session.model.check(p[0], "town", p[1].x * 2.0, p[1].y * 2.0, p[2]) == "") \
					and RideRules._solids(Session.model).all(func(s): return s[0].distance_to(Vector2(cx * 2.0 + 3.0, cz * 2.0 + 1.0)) > 6.0 + s[1]):
				origin = Vector2i(cx, cz)
	ok(origin.x != 99, "found room for a ring")
	var pieces := _ring(origin.x, origin.y, 4, 2)
	var ids := []
	for p in pieces:
		ids.append(await _place(p[0], Vector2(p[1]) * 2.0, p[2]))
	var station: String = ids[0]
	var st_at := Vector2(pieces[0][1]) * 2.0
	var sheep: Dictionary = anim.brain.animal("sheep")
	var trailer: Vector2 = anim.trailer_pose(station)["pos"]
	ok(trailer.distance_to(st_at - Vector2(anim.TRAILER_GAP, 0)) < 0.01, "the trailer stands behind the cart at the station")
	var built: Node3D = load("res://scripts/art/props.gd").build(RideRules.STATION, 2, 1)
	ok(absf(built.get_node("Trailer").position.z + anim.TRAILER_GAP) < 0.001, "the built station has its trailer where the rules say (%.2f m behind the cart)" % anim.TRAILER_GAP)
	# Room for the animal: the trailer is wider than the biggest rider and does not reach into the cart.
	var widest := 0.0
	for kind in AnimalBrain.VISITORS:
		widest = maxf(widest, float(AnimalBrain.SPECIES[kind]["radius"]) * 2.0)
	ok(anim.TRAILER_GAP - 0.475 - 0.55 >= 0.3, "there is at least 0.3 m between the cart's back and the trailer's front (%.2f m)" % (anim.TRAILER_GAP - 0.475 - 0.55))
	print("DIAG the widest animal that rides is %.2f m across by its footprint; the trailer is 0.84 m wide inside its sides" % widest)
	built.free()
	sheep["pos"] = trailer + Vector2(0.4, 2.2)
	sheep["plan"] = ""
	sheep["timer"] = 30.0
	sheep["goal"] = null
	_go("town", st_at + Vector2(0, 1.6))
	eq((await _result(Session.ride_with_animal("sheep", true))).get("error"), "Get into the cart first.", "an animal is called from the cart")
	ok((await _result(Session.ride(station, "board"))).get("ok", false), "in the cart")
	eq((await _result(Session.ride_with_animal("elephant", true))).get("error"), anim.RIDE_ERRORS["too_big"], "Tumble is told kindly")
	eq((await _result(Session.ride_with_animal("nobody", true))).get("error"), anim.RIDE_ERRORS["too_big"], "an animal that does not exist is refused the same way")
	var asked := await _result(Session.ride_with_animal("sheep", true))
	ok(asked.get("ok", false), "Wooly is asked for a ride (%s)" % str(asked.get("error", "ok")))
	eq(anim.riders, {"sheep": station}, "every device learns who rides with which cart")
	anim.brain.animal("pig")["pos"] = trailer + Vector2(0.4, 2.6)
	eq((await _result(Session.ride_with_animal("pig", true))).get("error"), "One animal friend at a time rides in the trailer.", "one animal per cart")
	var t := 0.0
	while not sheep["aboard"] and t < 6.0:
		await create_timer(0.2).timeout
		t += 0.2
	ok(sheep["aboard"], "Wooly walks over and hops into the trailer (%.1f s)" % t)
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "Go!")
	await create_timer(0.8).timeout
	var tp: Vector2 = anim.trailer_pose(station)["pos"]
	ok(sheep["pos"].distance_to(tp) < 0.45 and tp.distance_to(trailer) > 1.0, "Wooly rides in the trailer behind the moving cart (%.2f m from it)" % sheep["pos"].distance_to(tp))
	var behind: float = tp.distance_to(RideRules.pose(Session.rides[station]["route"], Session.ride_distance(station))["pos"])
	ok(behind > 0.9 and behind < anim.TRAILER_GAP + 0.1, "the trailer follows %.2f m behind the cart's middle (the gap along the rails is %.2f m)" % [behind, anim.TRAILER_GAP])
	eq((await _result(Session.ride_with_animal("pig", true))).get("error"), "Animals get in at the station. Ride back there first.", "nobody gets in out on the rails")
	# The child gets off out on the rails: the cart is home, and Wooly hops out by the station.
	ok((await _result(Session.ride(station, "stop"))).get("ok", false), "Stop, out on the rails")
	await _result(Session.stand())
	await create_timer(0.3).timeout
	ok(anim.riders.is_empty() and sheep["ride"] == "" and not sheep["aboard"], "the child gets off: Wooly is no passenger any more")
	ok(sheep["pos"].distance_to(st_at) < 3.0 and AnimalBrain.is_clear(Session.model, sheep["pos"], AnimalBrain.SPECIES["sheep"]["radius"]), "and stands on free ground by the station (%.1f m from it)" % sheep["pos"].distance_to(st_at))
	# Hop out on request at the station; the dance party; a dropped connection.
	sheep["pos"] = trailer + Vector2(0.3, 1.8)
	sheep["plan"] = ""
	sheep["timer"] = 30.0
	await _result(Session.ride(station, "board"))
	ok((await _result(Session.ride_with_animal("sheep", true))).get("ok", false), "asked again")
	ok((await _result(Session.ride_with_animal("sheep", false))).get("ok", false) and anim.riders.is_empty(), "Hop out lets it out")
	sheep["pos"] = trailer + Vector2(0.3, 1.8)
	sheep["plan"] = ""
	ok((await _result(Session.ride_with_animal("sheep", true))).get("ok", false), "and once more")
	anim.brain.start_parade(5.0)
	await create_timer(0.3).timeout
	ok(anim.riders.is_empty() and not sheep["aboard"], "a dance party lets every passenger out")
	anim.brain.stop_parade()
	await _result(Session.stand())
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": st_at.x, "z": st_at.y + 1.6, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_ride(77, 0, station, "board")
	sheep["pos"] = trailer + Vector2(0.3, 1.8)
	sheep["plan"] = ""
	sheep["timer"] = 30.0
	Session._srv_animal_ride(77, 0, "sheep", true)
	eq(anim.riders, {"sheep": station}, "a friend takes Wooly for a ride")
	Session._on_peer_disconnected(77)
	await create_timer(0.3).timeout
	ok(anim.riders.is_empty() and sheep["ride"] == "" and not Session.rides.has(station), "the friend's connection drops: the cart is home and Wooly is out")
	ok(Session.save_now() and not FileAccess.get_file_as_string("user://test_passengers.json").contains("riders"), "nothing about passengers is saved")
	Session.leave()
