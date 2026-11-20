## A scripted player for scripts/net_test.py --thousand: a real network client of the dedicated server that runs
## as a plain script (no scene, no world, no rendering). Two children in Thousand Town agree on its clock
## (design/thousand-town.md section 4: the Thousand autoload) and share a bus. Roles:
##   th_a     Sunny: rides to Thousand Town, waits for Sky there, chooses Night, takes a seat on bus 0, then
##            Auto at 2x; sees Sky's seat, and sees it freed when Sky goes home
##   th_b     Sky: rides to Thousand Town; sees Sunny's Night (21:30, held) and seat; takes the next seat on
##            bus 0; sees Auto at 2x run on; goes home
##   th_old   a hello of protocol 19 is refused ("update"); one of 20 is accepted ("ok")
##   scripts/godot.sh --headless --path game -s res://tests/thousand_bot.gd -- --url=ws://127.0.0.1:9080 --role=th_a
extends SceneTree

const Avatar := preload("res://scripts/core/avatar.gd")

const PRESETS := {"th_a": 0, "th_b": 1, "th_old": 2}

var Session: Node
var Thousand: Node
var args := {}
var role := ""
var url := ""
var avatar := {}
var failures := 0
var _states := 0
var _effects := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = str(args.get("role", "th_a"))
	url = str(args.get("url", "ws://127.0.0.1:9080"))
	Session = root.get_node("Session")
	Thousand = root.get_node("Thousand")
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
	return str(Session.players.get(peer, {}).get("state", {}).get("space", ""))


func finish() -> void:
	say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
	Session.leave()
	await root.get_node("Music").stop_for_exit()
	quit(1 if failures else 0)


func _run() -> void:
	if role == "th_old":
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
	Thousand.updated.connect(func(s: Dictionary):
		if s["started"]:
			_states += 1)
	Thousand.effect.connect(func(kind, data): _effects.append([kind, data]))
	match role:
		"th_a": await _role_a()
		"th_b": await _role_b()
	await finish()


## Sunny: chooses Night once Sky is in the town, takes a bus seat, then Auto at 2x.
func _role_a() -> void:
	check(await wait_until(func(): return peer_of("Sky") != 0, 30.0), "sees Sky arrive")
	var sky := peer_of("Sky")
	var r := await ask(Session.travel("thousand"))
	check(r.get("ok", false) and r.get("space") == "thousand", "the tram goes to Thousand Town (%s)" % str(r))
	check(await wait_until(func(): return bool(Thousand.states["started"]), 5.0), "the town's clock reaches me within 5 s")
	check(await wait_until(func(): return space_of(sky) == "thousand", 60.0), "Sky is in Thousand Town too")
	r = await ask(Thousand.set_time_mode("night"))
	check(r.get("ok", false) and float(r.get("minute", 0)) == 1290.0, "I choose Night (%s)" % str(r))
	check(await wait_until(func(): return Thousand.states["mode"] == "night", 5.0), "my state says night")
	r = await ask(Thousand.board_bus(0))
	check(r.get("ok", false) and int(r.get("seat", -1)) == 0, "I take the first seat on bus 0 (%s)" % str(r))
	check(await wait_until(func(): return Thousand.riding(sky) == 0, 60.0), "Sky takes a seat on my bus")
	check(int((Thousand.states["riders"] as Dictionary)[sky]["seat"]) == 1, "the next seat")
	r = await ask(Thousand.set_time_mode("auto", 2))
	check(r.get("ok", false) and int(r.get("speed", 0)) == 2, "I choose Auto at 2x (%s)" % str(r))
	say("TH a_auto2")
	check(await wait_until(func(): return space_of(sky) == "town", 90.0), "Sky goes home")
	check(await wait_until(func(): return not (Thousand.states["riders"] as Dictionary).has(sky), 5.0), "and Sky's seat is free again")
	check(Thousand.riding(Session.my_id) == 0, "mine is still mine")
	var m0 := float(Thousand.est_clock()["minute"])
	await wait(2.0)
	var m1 := float(Thousand.est_clock()["minute"])
	check(m1 > m0 + 3.0 and m1 < m0 + 5.0, "the clock runs on at 2x with me there (%.2f -> %.2f)" % [m0, m1])
	check(_states >= 5, "the town's states keep coming (%d)" % _states)
	r = await ask(Thousand.off_bus())
	check(r.get("ok", false), "I get off")
	r = await ask(Session.travel("town"))
	check(r.get("ok", false), "home again")


## Sky: rides there, sees Sunny's Night and seat, takes the next seat, sees Auto at 2x.
func _role_b() -> void:
	check(await wait_until(func(): return peer_of("Sunny") != 0, 30.0), "sees Sunny")
	var sunny := peer_of("Sunny")
	await wait(1.0)
	var r := await ask(Session.travel("thousand"))
	check(r.get("ok", false) and r.get("space") == "thousand", "the tram goes to Thousand Town (%s)" % str(r))
	check(await wait_until(func(): return bool(Thousand.states["started"]), 5.0), "the town's clock reaches me within 5 s")
	check(await wait_until(func(): return Thousand.states["mode"] == "night", 60.0), "Sunny's Night reaches me")
	check(float(Thousand.states["minute"]) == 1290.0 and int(Thousand.states["day"]) == 1, "21:30 on day 1, as Sunny has it")
	check(_effects.any(func(e): return e[0] == "time" and int(e[1]["peer"]) == sunny and e[1]["mode"] == "night"), "the time effect names Sunny")
	await wait(1.5)
	check(float(Thousand.est_clock()["minute"]) == 1290.0, "Night holds")
	check(await wait_until(func(): return Thousand.riding(sunny) == 0, 30.0), "Sunny sits on bus 0")
	r = await ask(Thousand.board_bus(0))
	check(r.get("ok", false) and int(r.get("seat", -1)) == 1, "I take the next seat on bus 0 (%s)" % str(r))
	check(await wait_until(func(): return Thousand.states["mode"] == "auto" and int(Thousand.states["speed"]) == 2, 30.0), "Sunny's Auto at 2x reaches me")
	var m0 := float(Thousand.est_clock()["minute"])
	await wait(2.0)
	var m1 := float(Thousand.est_clock()["minute"])
	check(m1 > m0 + 3.0 and m1 < m0 + 5.0, "the clock runs at 2x here too (%.2f -> %.2f)" % [m0, m1])
	r = await ask(Session.travel("town"))
	check(r.get("ok", false), "home (the seat is left behind)")
	await wait(3.0)


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
