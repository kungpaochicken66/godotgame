## A scripted player for scripts/net_test.py --city: a real network client of the dedicated server that runs
## as a plain script (no scene, no world, no rendering). Roles:
##   city_a  Sunny: rides the tram to the city, takes a cafe seat, watches Sky ride the wheel, sees her leave
##   city_b  Sky: rides to the city, is refused Sunny's seat, boards the wheel in its window, drops mid-ride
##   city_c  Peach: joins late, sees the same seat and rider within 5 s, sees the place freed after Sky drops
##   scripts/godot.sh --headless --path game -s res://tests/city_bot.gd -- --url=ws://127.0.0.1:9080 --role=city_a
extends SceneTree

const Avatar := preload("res://scripts/core/avatar.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")

const PRESETS := {"city_a": 0, "city_b": 1, "city_c": 2}

var Session: Node
var City: Node
var args := {}
var role := ""
var url := ""
var avatar := {}
var failures := 0
var _effects := []
var _saw_rain := false
var _saw_night := false
var _dwelling := 0   # states drawn in which some bus was waiting at a stop


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = str(args.get("role", "city_a"))
	url = str(args.get("url", "ws://127.0.0.1:9080"))
	Session = root.get_node("Session")
	City = root.get_node("City")
	avatar = Avatar.PRESETS[PRESETS.get(role, 0)].duplicate()
	_run.call_deferred()


func say(text: String) -> void:
	print("NETBOT %s %s" % [role, text])


func check(cond: bool, what: String) -> void:
	say(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func wait_until(cond: Callable, timeout := 20.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout:
			return false
	return true


func ask(req: int) -> Dictionary:
	var result := {}
	var got := [false]
	var cb := func(r_id: int, r: Dictionary):
		if r_id == req:
			result.merge(r)
			got[0] = true
	Session.request_done.connect(cb)
	await wait_until(func(): return got[0], 10.0)
	Session.request_done.disconnect(cb)
	return result


func peer_of(nick: String) -> int:
	for p in Session.players:
		if Session.players[p]["avatar"]["nick"] == nick:
			return p
	return 0


func space_of(peer: int) -> String:
	return str(Session.players.get(peer, {}).get("state", {}).get("space", "?"))


func stand(p: Vector2) -> void:
	Session.send_state({"space": "city", "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"})
	await wait(0.6)


func finish() -> void:
	say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
	Session.leave()
	await root.get_node("Music").stop_for_exit()
	quit(1 if failures else 0)


func _run() -> void:
	Session.join(url, avatar, "")
	var online := await wait_until(func(): return Session.is_online(), 20.0)
	check(online, "joined the town server")
	if not online:
		await finish()
		return
	check(Session.PROTOCOL == 20, "protocol 20")
	City.updated.connect(_log_state)
	City.effect.connect(func(kind, data): _effects.append([kind, data]))
	match role:
		"city_a": await _role_a()
		"city_b": await _role_b()
		"city_c": await _role_c()
	await finish()


## Every state this client draws is logged, so the runner can compare two clients (positions and dwell).
func _log_state(states: Dictionary) -> void:
	var parts := []
	var waiting := false
	for v: Dictionary in states["vehicles"]:
		waiting = waiting or float(v.get("dwell", 0.0)) > 0.0
		var p: Vector2 = v["pos"]
		parts.append("%.2f,%.2f,%.2f" % [p.x, p.y, float(v.get("dwell", 0.0))])
	if waiting:
		_dwelling += 1
	_saw_rain = _saw_rain or int(states["weather"]) == 1
	_saw_night = _saw_night or int(states["weather"]) == 2
	var w: Dictionary = CityRules.weather_weights(states, float(states["time"]))
	if not parts.is_empty():
		print("CLOG %s %s %s %.4f,%.4f,%.4f" % [role, states["time"], ";".join(parts), w["sunny"], w["rain"], w["night"]])


func _to_city() -> void:
	var r := await ask(Session.travel("city"))
	check(r.get("ok", false) and r.get("space") == "city", "the tram goes to the city (%s)" % str(r))


## Sunny: the first in the city; takes the cafe seat; sees Sky ride; sees her leave.
func _role_a() -> void:
	check(await wait_until(func(): return peer_of("Sky") != 0, 30.0), "sees Sky arrive")
	check(City.states["vehicles"].is_empty() and City.est_time() == 0.0, "in town no city state has reached me")
	await _to_city()
	check(await wait_until(func(): return City.states["vehicles"].size() == 5, 5.0), "the city's state is mine within 5 s of arriving")
	check(City.est_time() < 5.0, "the city woke fresh (%.1f s)" % City.est_time())
	var seat: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	await stand(seat)
	var r := await ask(City.use("cafe_seat_a"))
	check(r.get("ok", false) and r.get("pose") == "sit", "I get the cafe seat (%s)" % str(r))
	check(await wait_until(func(): return City.occupant("cafe_seat_a") == Session.my_id, 5.0), "my states say I hold it")
	say("CITY a_seated")
	check(await wait_until(func(): return space_of(peer_of("Sky")) == "city", 30.0), "Sky is in the city with me")
	var sky := peer_of("Sky")
	check(await wait_until(func(): return City.riding(sky) >= 0, 60.0), "my states show Sky riding the wheel (gondola %d)" % City.riding(sky))
	check(await wait_until(func(): return peer_of("Peach") != 0 and space_of(peer_of("Peach")) == "city", 60.0), "Peach joined the city late")
	check(await wait_until(func(): return peer_of("Sky") == 0, 90.0), "Sky's drop is seen")
	check(City.riding(sky) == -1, "and the place on the wheel is free in my states")
	check(City.occupant("cafe_seat_a") == Session.my_id, "my seat is still mine")
	check(await wait_until(func(): return _saw_rain, 60.0), "I saw the weather turn to rain")
	check(await wait_until(func(): return _saw_night, 60.0), "and then to night")
	check(City.states["weather"] == 2, "the city is at night in my states")
	check(await wait_until(func(): return peer_of("Peach") == 0, 60.0), "Peach leaves at the end")
	r = await ask(City.release())
	check(r.get("ok", false), "I stand up")
	check(await wait_until(func(): return City.occupant("cafe_seat_a") == -1, 5.0), "the seat is free")


## Sky: refused the taken seat, then the wheel: refused far and outside the window, accepted in it.
func _role_b() -> void:
	check(await wait_until(func(): return peer_of("Sunny") != 0, 30.0), "sees Sunny")
	await _to_city()
	check(await wait_until(func(): return space_of(peer_of("Sunny")) == "city", 30.0), "Sunny is in the city")
	check(await wait_until(func(): return City.occupant("cafe_seat_a") == peer_of("Sunny"), 30.0), "I see Sunny sitting at the cafe")
	var seat: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"]
	await stand(seat + Vector2(0.5, 0.0))
	var r := await ask(City.use("cafe_seat_a"))
	check(not r.get("ok", true) and r.get("error") == "Someone is sitting there.", "the taken seat is refused (%s)" % str(r.get("error")))
	r = await ask(City.board())
	check(not r.get("ok", true) and r.get("error") == "Walk closer first.", "boarding far from the platform is refused (%s)" % str(r.get("error")))
	var board: Vector2 = CityMap.FERRIS["board_at"]
	await stand(board)
	var refused_wait := false
	var boarded := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		r = await ask(City.board())
		if r.get("ok", false):
			boarded = r
			break
		if r.get("error") == "Wait for a gondola at the bottom.":
			refused_wait = true
		await wait(0.3)
	check(boarded.get("ok", false), "I board in the window (%s)" % str(boarded))
	check(refused_wait or Time.get_ticks_msec() - t0 < 1500, "outside the window I was told to wait (or the window was open at once)")
	check(await wait_until(func(): return City.riding(Session.my_id) == int(boarded.get("gondola", -2)), 5.0), "my own states show me in gondola %d" % int(boarded.get("gondola", -1)))
	r = await ask(City.use("cafe_seat_a"))
	check(not r.get("ok", true), "riding blocks other things (%s)" % str(r.get("error")))
	say("CITY b_riding")
	check(await wait_until(func(): return peer_of("Peach") != 0 and space_of(peer_of("Peach")) == "city", 60.0), "Peach arrives while I ride")
	await wait(4.0)   # she checks what she sees
	say("CITY b_dropping")
	Session.leave()
	await wait(1.0)


## Peach: a late joiner. Seat and rider are in her first state.
func _role_c() -> void:
	check(await wait_until(func(): return space_of(peer_of("Sky")) == "city" and space_of(peer_of("Sunny")) == "city", 90.0), "Sunny and Sky are in the city")
	var sunny := peer_of("Sunny")
	var sky := peer_of("Sky")
	check(City.states["vehicles"].is_empty(), "in town no city state has reached me")
	await _to_city()
	var t0 := Time.get_ticks_msec()
	check(await wait_until(func(): return City.occupant("cafe_seat_a") == sunny and City.riding(sky) >= 0, 5.0), "the same seat holder and rider within 5 s (%d ms)" % (Time.get_ticks_msec() - t0))
	check(City.est_time() > 3.0, "of the running city, not a fresh one (%.1f s)" % City.est_time())
	check(City.states["riders"].size() == 1, "one gondola in use (%s)" % str(City.states["riders"]))
	check(await wait_until(func(): return City.riding(sky) == -1 and peer_of("Sky") == 0, 40.0), "Sky's drop mid-ride frees her place (%s)" % str(City.states["riders"]))
	check(City.occupant("cafe_seat_a") == sunny, "and Sunny still sits")
	# The weather: rain, then night; shared by everyone in the city.
	var wr := await ask(City.set_weather(1))
	check(wr.get("ok", false), "I make it rain (%s)" % str(wr))
	check(await wait_until(func(): return City.states["weather"] == 1, 5.0), "my states say rain")
	await wait(5.0)
	check(City.weights()["rain"] > 0.99, "the blend has finished (%s)" % str(City.weights()))
	var wn := await ask(City.set_weather(2))
	check(wn.get("ok", false), "and night (%s)" % str(wn))
	var bad := await ask(City.set_weather(9))
	check(not bad.get("ok", true) and bad.get("error") == "The city does not have that weather.", "a weather that does not exist is refused (%s)" % str(bad.get("error")))
	await wait(5.0)
	check(City.states["weather"] == 2 and City.weights()["night"] > 0.99, "night has settled (%s)" % str(City.weights()))
	# Stay until buses have been seen waiting at a stop, so the runner can compare their dwell with Sunny's.
	check(await wait_until(func(): return _dwelling >= 8, 60.0), "I saw buses waiting at a stop (%d states)" % _dwelling)
	await wait(1.0)
