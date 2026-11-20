## A scripted player for scripts/net_test.py --zoo: a real network client of the dedicated server
## that runs as a plain script (no scene, no world, no rendering). Roles:
##   zoo_a  Sunny: rides to the zoo, invites Sky, pumps water (a discovery), puts two toys down
##   zoo_b  Sky: stays in town and hears nothing of the zoo, then answers the invitation
##   zoo_c  Peach: joins late, rides to the zoo, drops the connection mid-journey and reconnects
##   zoo_check  Leaf: after a server restart, checks what stayed and that the zoo starts fresh
##   scripts/godot.sh --headless --path game -s res://tests/zoo_bot.gd -- --url=ws://127.0.0.1:9080 --role=zoo_a
extends SceneTree

const Avatar := preload("res://scripts/core/avatar.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")

const PRESETS := {"zoo_a": 0, "zoo_b": 1, "zoo_c": 2, "zoo_check": 3}
const NICKS := {"zoo_a": "Sunny", "zoo_b": "Sky", "zoo_c": "Peach", "zoo_check": "Leaf"}
const PUMP := Vector2(5.5, 6.9)

var Session: Node
var Zoo: Node
var args := {}
var role := ""
var url := ""
var avatar := {}
var failures := 0
var _zlog := {}
var _effects := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = str(args.get("role", "zoo_a"))
	url = str(args.get("url", "ws://127.0.0.1:9080"))
	Session = root.get_node("Session")
	Zoo = root.get_node("Zoo")
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


func at_of(peer: int) -> Vector2:
	var s: Dictionary = Session.players.get(peer, {}).get("state", {})
	return Vector2(float(s.get("x", 0.0)), float(s.get("z", 0.0)))


func stand(space: String, p: Vector2) -> void:
	Session.send_state({"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"})
	await wait(0.5)


func finish() -> void:
	say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
	Session.leave()
	await root.get_node("Music").stop_for_exit()
	quit(1 if failures else 0)


## Every state this client draws is logged with a digest, so the runner can compare two clients.
func _log_states(states: Dictionary) -> void:
	var parts := []
	for a in states["animals"]:
		parts.append("%s|%s|%s|%s|%s|%s|%s" % [a["id"], a["action"], a["from"], a["to"], a["t0"], a["dur"], a["line"]])
	_zlog[str(states["time"])] = "|".join(parts).hash()


func _run() -> void:
	Session.join(url, avatar, "")
	var online := await wait_until(func(): return Session.is_online(), 20.0)
	check(online, "joined the town server")
	if not online:
		await finish()
		return
	check(Session.PROTOCOL == 20, "protocol 20")
	Zoo.updated.connect(_log_states)
	Zoo.effect.connect(func(kind, _at, _who): _effects.append(kind))
	match role:
		"zoo_a": await _role_a()
		"zoo_b": await _role_b()
		"zoo_c": await _role_c()
		"zoo_check": await _role_check()
	for t in _zlog:
		print("ZLOG %s %s %s" % [role, t, _zlog[t]])
	await finish()


func _nick_in(names: Array, nick: String) -> bool:
	return names.has(nick)


## Sunny: the first in the zoo; Sky is in town and must hear nothing; the invitation; the pump.
func _role_a() -> void:
	check(await wait_until(func(): return peer_of("Sky") != 0, 30.0), "sees Sky arrive")
	check(Zoo.states["animals"].is_empty() and Zoo.est_time() == 0.0, "in town no zoo state has reached me")
	var r := await ask(Session.travel("zoo"))
	check(r.get("ok", false) and r.get("space") == "zoo", "the tram goes to the zoo (%s)" % str(r))
	var first := Vector2(float(r.get("x", 0.0)), float(r.get("z", 0.0)))
	check(first.is_equal_approx(ZooMap.ARRIVALS[0]), "the first child arrives at place 0 (%s)" % str(first))
	check(await wait_until(func(): return Zoo.states["animals"].size() == 18, 5.0), "all 18 residents are in my states within 5 s of arriving")
	check(Zoo.est_time() < 5.0, "the zoo woke fresh (%.1f s)" % Zoo.est_time())
	say("ZOO a_in_zoo")
	check(space_of(peer_of("Sky")) == "town", "Sky is in town: two clients on different maps")
	await wait(4.0)   # Sky watches in town: no zoo packets may reach her
	# Sky's arrival place is the state the authority broadcasts with her journey (Session._srv_travel), taken
	# from that message itself. Reading her newest state once the space has changed was a race: Sky walks to
	# the pump at once (role b), and when both states reached this client within one of its frames (a loaded
	# host), the pump spot (7.5, 7.9) was read as her arrival place (city-web r1 battery, net_zoo).
	var sky_arrival: Array = []
	Session.player_state.connect(func(peer: int, st: Dictionary):
		if sky_arrival.is_empty() and peer == peer_of("Sky") and str(st.get("space", "")) == "zoo":
			sky_arrival.append(Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0)))))
	r = await ask(Session.send_invite("zoo", ""))
	check(r.get("ok", false) and r.get("sent") == 1, "the zoo invitation reached Sky (%s)" % str(r))
	check(await wait_until(func(): return space_of(peer_of("Sky")) == "zoo", 30.0), "Sky rode the tram to join me")
	check(not sky_arrival.is_empty(), "her arrival state reached me")
	var sky_at: Vector2 = sky_arrival[0] if not sky_arrival.is_empty() else Vector2.ZERO
	check(sky_at.distance_to(first) > 0.4 and sky_at.y > 24.0, "she arrived at another place on the platform (%s)" % str(sky_at))
	# The pump: Sky comes to stand near it too.
	await stand("zoo", PUMP + Vector2(1.0, 0.0))
	check(await wait_until(func(): return at_of(peer_of("Sky")).distance_to(PUMP) < 6.0, 30.0), "Sky walks over to the pump")
	r = await ask(Zoo.use("savanna_pump"))
	check(r.get("ok", false), "the pump answers (%s)" % str(r))
	var r2 := await ask(Zoo.use("savanna_pump"))
	check(not r2.get("ok", true), "and rests: a second use at once is refused (%s)" % str(r2.get("error")))
	check(await wait_until(func(): return Zoo.found("giraffe").has("drink"), 10.0), "the drink is in the discovery log")
	var by: Array = Zoo.found("giraffe").get("drink", {}).get("by", [])
	check(by.has("Sunny") and by.has("Sky"), "with both names (%s)" % str(by))
	check(_effects.has("pump"), "the pump's splash arrived (%s)" % str(_effects))
	say("ZOO found")
	# Two toys on the lawn.
	var placed := 0
	for kind in ["zoo_ball", "zoo_box"]:
		for c in [Vector2(24.0, 0.0), Vector2(28.0, 3.0), Vector2(32.0, -2.0), Vector2(26.0, 6.0), Vector2(34.0, 5.0)]:
			var pr := await ask(Session.place(kind, "zoo", c, 0, -2))
			if pr.get("ok", false):
				placed += 1
				break
	check(placed == 2, "two toys placed in the zoo (%d)" % placed)
	say("ZOO placed %d" % placed)
	# Peach arrives late, rides over, drops mid-journey and comes back to town.
	check(await wait_until(func(): return space_of(peer_of("Peach")) == "zoo", 90.0), "Peach joined the zoo late")
	var peach := peer_of("Peach")
	var at_c := at_of(peach)
	check(at_c.y > 24.0 and at_c.distance_to(sky_at) > 0.4, "on the platform at a free place (Sunny and Sky have moved on, so place 0 is free again) (%s)" % str(at_c))
	check(await wait_until(func(): return not Session.players.has(peach), 30.0), "Peach's drop is seen")
	check(Zoo.states["animals"].size() == 18, "the zoo goes on for the two of us")
	var t1: float = Zoo.est_time()
	await wait(1.0)
	check(Zoo.est_time() > t1 + 0.5, "its clock keeps running (%.1f s)" % Zoo.est_time())
	check(await wait_until(func(): return peer_of("Peach") != 0 and space_of(peer_of("Peach")) == "town", 30.0), "Peach reconnected in town, not in the zoo")
	say("ZOO c_back")
	await wait(1.0)


## Sky: in town she hears nothing of the zoo; then the invitation, Join, and the tram.
func _role_b() -> void:
	var cards := []
	Session.invited.connect(func(c): cards.append(c))
	check(await wait_until(func(): return space_of(peer_of("Sunny")) == "zoo", 60.0), "sees Sunny go to the zoo")
	await wait(3.0)
	check(Zoo.states["animals"].is_empty() and Zoo.est_time() == 0.0, "3 s of the zoo running and not one state reached me in town")
	check(await wait_until(func(): return not cards.is_empty(), 30.0), "the zoo invitation card arrives")
	var card: Dictionary = cards[0]
	check(card.get("kind") == "zoo" and card.get("space") == "zoo" and card.get("nick") == "Sunny", "it says who and where (%s)" % str(card))
	var r := await ask(Session.answer_invite(str(card["from"]), "join"))
	check(r.get("ok", false) and r.get("joined", false), "Join accepted (%s)" % str(r.get("error", "ok")))
	r = await ask(Session.travel("zoo"))
	check(r.get("ok", false) and r.get("space") == "zoo", "the tram goes to the zoo (%s)" % str(r))
	var mine := Vector2(float(r.get("x", 0.0)), float(r.get("z", 0.0)))
	check(not mine.is_equal_approx(ZooMap.ARRIVALS[0]), "not on Sunny's place (%s)" % str(mine))
	var t0 := Time.get_ticks_msec()
	check(await wait_until(func(): return Zoo.states["animals"].size() == 18, 5.0), "the zoo's states arrive at once (%d ms)" % (Time.get_ticks_msec() - t0))
	check(Zoo.est_time() > 3.0, "and it is the running zoo, not a fresh one (%.1f s)" % Zoo.est_time())
	await stand("zoo", PUMP + Vector2(2.0, 1.0))
	check(await wait_until(func(): return Zoo.found("giraffe").has("drink"), 30.0), "I see the discovery Sunny made")
	check(_effects.has("pump"), "and the pump's splash on my screen")
	check(await wait_until(func(): return not Session.players.has(peer_of("Sunny")) and peer_of("Sunny") == 0, 120.0), "Sunny leaves at the end")


## Peach: a late joiner. The log and the toys are in her welcome; the tram's first state is at once.
func _role_c() -> void:
	check(Zoo.found("giraffe").has("drink"), "the discovery is already in my welcome")
	var toys: Array = Session.model.items.values().filter(func(i): return i["space"] == "zoo")
	check(toys.size() == 2, "so are the two toys in the zoo (%d)" % toys.size())
	check(space_of(peer_of("Sunny")) == "zoo" and space_of(peer_of("Sky")) == "zoo", "I know Sunny and Sky are in the zoo")
	check(Zoo.states["animals"].is_empty(), "no zoo state has reached me in town")
	var r := await ask(Session.travel("zoo"))
	check(r.get("ok", false), "the tram goes to the zoo (%s)" % str(r))
	var t0 := Time.get_ticks_msec()
	check(await wait_until(func(): return Zoo.states["animals"].size() == 18, 5.0), "a late arrival gets the picture at once (%d ms)" % (Time.get_ticks_msec() - t0))
	# Not a fresh zoo: one woken by my arrival would read about my own wait. 8 s assumed the others'
	# pace (6.1 s seen on a run where all else passed); this is the same rule as Sky's check.
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	check(Zoo.est_time() > 3.0 + waited, "of the running zoo, not a fresh one (%.1f s, waited %.1f s)" % [Zoo.est_time(), waited])
	await wait(1.5)
	# On the way home, the connection drops before the answer.
	Session.travel("town")
	Session.leave()
	await wait(1.5)
	check(not Session.is_online() and Zoo.states["animals"].is_empty(), "disconnected: nothing of the zoo is kept")
	Session.join(url, avatar, "")
	check(await wait_until(func(): return Session.is_online(), 20.0), "reconnected")
	var mine: int = Session.my_id
	check(space_of(mine) == "town", "the child is back in town after reconnecting (%s)" % space_of(mine))
	check(Zoo.states["animals"].is_empty(), "with no zoo state")
	check(Zoo.found("giraffe").has("drink"), "and the discovery log came back with the welcome")
	await wait(3.0)


## After a server restart: the toys and the log are still there; the zoo starts fresh.
func _role_check() -> void:
	check(space_of(Session.my_id) == "town", "a new visit begins in town")
	var toys: Array = Session.model.items.values().filter(func(i): return i["space"] == "zoo")
	check(toys.size() == 2, "the two toys survived the restart (%d)" % toys.size())
	check(Zoo.found("giraffe").has("drink"), "so did the discovery")
	var by: Array = Zoo.found("giraffe").get("drink", {}).get("by", [])
	check(by.has("Sunny") and by.has("Sky"), "with both names (%s)" % str(by))
	check(Session.model.items.values().any(func(i): return i["kind"] == "tram_stop" and i["space"] == "town"), "the town has its tram stop")
	var r := await ask(Session.travel("zoo"))
	check(r.get("ok", false), "the tram goes to the restarted town's zoo (%s)" % str(r))
	check(await wait_until(func(): return Zoo.states["animals"].size() == 18, 5.0), "the zoo wakes")
	check(Zoo.est_time() < 5.0, "fresh: the animals are at home (%.1f s)" % Zoo.est_time())
	await wait(1.5)
