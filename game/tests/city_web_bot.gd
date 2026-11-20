## A scripted player for scripts/net_test.py --city-web: a real network client of the dedicated server that runs
## as a plain script (no scene, no world, no rendering). Two children in the two city maps never see each
## other's City state (design/city-threejs.md section 6: the CityWeb autoload). Roles:
##   web_a    Sunny: rides to the web city, takes the cafe seat, chooses rain; sees only the web city's states
##   web_b    Sky: rides to the Godot city, takes the same cafe seat there, chooses night; sees only the city's
##   web_old  a hello of an older protocol (19, the web city's own, since Thousand Town's 20) is refused ("update"); one of 20 is accepted ("ok")
##   scripts/godot.sh --headless --path game -s res://tests/city_web_bot.gd -- --url=ws://127.0.0.1:9080 --role=web_a
extends SceneTree

const Avatar := preload("res://scripts/core/avatar.gd")
const CityMap := preload("res://scripts/core/city_map.gd")

const PRESETS := {"web_a": 0, "web_b": 1, "web_old": 2}

var Session: Node
var City: Node
var CityWeb: Node
var args := {}
var role := ""
var url := ""
var avatar := {}
var failures := 0
var _city_states := 0       # whole states drawn from City (the Godot city)
var _web_states := 0        # whole states drawn from CityWeb (the web city)
var _city_effects := []
var _web_effects := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = str(args.get("role", "web_a"))
	url = str(args.get("url", "ws://127.0.0.1:9080"))
	Session = root.get_node("Session")
	City = root.get_node("City")
	CityWeb = root.get_node("CityWeb")
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


func state_of(peer: int) -> Dictionary:
	return Session.players.get(peer, {}).get("state", {})


func finish() -> void:
	say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
	Session.leave()
	await root.get_node("Music").stop_for_exit()
	quit(1 if failures else 0)


func _run() -> void:
	if role == "web_old":
		await _role_old()
		say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
		await root.get_node("Music").stop_for_exit()
		quit(1 if failures else 0)
		return
	Session.join(url, avatar, "")
	var online := await wait_until(func(): return Session.is_online(), 20.0)
	check(online, "joined the town server")
	if not online:
		await finish()
		return
	check(Session.PROTOCOL == 20, "protocol 20")
	City.updated.connect(func(s: Dictionary):
		if not (s["vehicles"] as Array).is_empty():
			_city_states += 1)
	CityWeb.updated.connect(func(s: Dictionary):
		if not (s["vehicles"] as Array).is_empty():
			_web_states += 1)
	City.effect.connect(func(kind, data): _city_effects.append([kind, data]))
	CityWeb.effect.connect(func(kind, data): _web_effects.append([kind, data]))
	match role:
		"web_a": await _role_a()
		"web_b": await _role_b()
	await finish()


func _sit_here(space: String) -> void:
	var seat: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"] + Vector2(0.3, 0.0)
	Session.send_state({"space": space, "x": seat.x, "z": seat.y, "ry": 0.0, "anim": "idle"})
	await wait(0.6)


## Sunny: the web city. Sits at the cafe and chooses rain; never sees Sky's city.
func _role_a() -> void:
	check(await wait_until(func(): return peer_of("Sky") != 0, 30.0), "sees Sky arrive")
	var r := await ask(Session.travel("city_web"))
	check(r.get("ok", false) and r.get("space") == "city_web", "the tram goes to the web city (%s)" % str(r))
	check(await wait_until(func(): return (CityWeb.states["vehicles"] as Array).size() == 5, 5.0), "the web city's state is mine within 5 s")
	await _sit_here("city_web")
	r = await ask(CityWeb.use("cafe_seat_a"))
	check(r.get("ok", false) and r.get("pose") == "sit", "I get the web city's cafe seat (%s)" % str(r))
	check(await wait_until(func(): return CityWeb.occupant("cafe_seat_a") == Session.my_id, 5.0), "my web city states say I hold it")
	r = await ask(CityWeb.set_weather(1))
	check(r.get("ok", false), "I choose rain (%s)" % str(r))
	check(await wait_until(func(): return int(CityWeb.states["weather"]) == 1, 5.0), "the web city rains in my states")
	var seat: Vector2 = CityMap.INTERACTIONS["cafe_seat_a"]["pos"] + Vector2(0.3, 0.0)
	Session.send_state({"space": "city_web", "x": seat.x, "z": seat.y, "ry": 0.0, "anim": "sit"})   # the sign for Sky: seated
	say("WEB a_seated")
	var sky := peer_of("Sky")
	check(await wait_until(func(): return str(state_of(sky).get("space", "")) == "city", 60.0), "Sky is in the city (another map)")
	check(await wait_until(func(): return str(state_of(sky).get("space", "")) == "town", 90.0), "Sky goes home at the end")
	check(_city_states == 0, "not one state of the city reached me (%d)" % _city_states)
	check(_city_effects.is_empty(), "nor any of its effects (%s)" % str(_city_effects))
	check(City.states == City.empty_state(), "my City state is the empty shape")
	check(_web_states >= 8, "the web city's states keep coming (%d)" % _web_states)
	check(CityWeb.occupant("cafe_seat_a") == Session.my_id, "my seat is still mine")
	check(int(CityWeb.states["weather"]) == 1, "and the web city still rains (Sky's night stayed in the city)")
	check(not (CityWeb.states["occupancy"] as Dictionary).values().map(func(v): return int(v)).has(sky), "Sky never shows in the web city")
	r = await ask(CityWeb.release())
	check(r.get("ok", false), "I stand up")
	r = await ask(Session.travel("town"))
	check(r.get("ok", false), "home again")


## Sky: the Godot city. Waits for Sunny to sit in the web city, then takes the same seat and chooses night.
func _role_b() -> void:
	check(await wait_until(func(): return peer_of("Sunny") != 0, 30.0), "sees Sunny")
	var sunny := peer_of("Sunny")
	check(await wait_until(func(): return str(state_of(sunny).get("space", "")) == "city_web" and str(state_of(sunny).get("anim", "")) == "sit", 60.0),
		"Sunny sits in the web city")
	var r := await ask(Session.travel("city"))
	check(r.get("ok", false) and r.get("space") == "city", "the tram goes to the city (%s)" % str(r))
	check(await wait_until(func(): return (City.states["vehicles"] as Array).size() == 5, 5.0), "the city's state is mine within 5 s")
	check(City.occupant("cafe_seat_a") == -1, "the cafe seat is free in the city")
	check(int(City.states["weather"]) == 0, "and the city is sunny (Sunny's rain is the web city's)")
	await _sit_here("city")
	r = await ask(City.use("cafe_seat_a"))
	check(r.get("ok", false) and r.get("pose") == "sit", "I get the same seat in the city (%s)" % str(r))
	check(await wait_until(func(): return City.occupant("cafe_seat_a") == Session.my_id, 5.0), "my city states say I hold it")
	r = await ask(City.set_weather(2))
	check(r.get("ok", false), "I choose night (%s)" % str(r))
	check(await wait_until(func(): return int(City.states["weather"]) == 2, 5.0), "the city is at night in my states")
	await wait(3.0)
	check(_web_states == 0, "not one state of the web city reached me (%d)" % _web_states)
	check(_web_effects.is_empty(), "nor any of its effects (%s)" % str(_web_effects))
	check(CityWeb.states == CityWeb.empty_state(), "my CityWeb state is the empty shape")
	check(not (City.states["occupancy"] as Dictionary).values().map(func(v): return int(v)).has(sunny), "Sunny never shows in the city")
	r = await ask(City.release())
	check(r.get("ok", false), "I stand up")
	await wait(1.1)
	r = await ask(Session.travel("town"))
	check(r.get("ok", false), "home again")
	await wait(3.0)   # Sunny checks while I am in town


## A hello of another protocol is refused with "update"; the current one is accepted ("ok").
func _role_old() -> void:
	check(Session.PROTOCOL == 20, "protocol 20")
	var old := await _hello(19)
	check(old == "update", "a protocol 19 app is told to update (%s)" % old)
	var cur := await _hello(20)
	check(cur == "ok", "a protocol 20 app is let in (%s)" % cur)


func _hello(v: int) -> String:
	var holder := Node.new()
	holder.name = "Hello%d" % v
	root.add_child(holder)
	var mp := SceneMultiplayer.new()
	var answer := [""]
	mp.auth_callback = func(_id: int, data: PackedByteArray): answer[0] = data.get_string_from_utf8()
	mp.peer_authenticating.connect(func(id: int): mp.send_auth(id, JSON.stringify({"v": v, "invite": ""}).to_utf8_buffer()))
	set_multiplayer(mp, holder.get_path())
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return "connect error %d" % err
	mp.multiplayer_peer = peer
	await wait_until(func(): return answer[0] != "", 15.0)
	peer.close()
	await wait(0.3)
	set_multiplayer(null, holder.get_path())
	holder.queue_free()
	return answer[0]
