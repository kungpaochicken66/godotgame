## A scripted player that joins a real town server over WebSocket. Several bot
## processes run at once against one dedicated server (see scripts/net_test.py).
## They are real network peers on this machine, not simulated in-process players.
##   godot --headless --path game -- --driver=res://tests/net_bot.gd --url=ws://127.0.0.1:9080 --role=a
extends Node

const Avatar := preload("res://scripts/core/avatar.gd")

## Seconds the four players stay after meeting, so the fifth can try to join.
const HOLD := 14.0

var main: Node
var role := ""
var failures := 0
var _log := []


func _ready() -> void:
	role = main.args.get("role", "a")
	_run.call_deferred()


func say(text: String) -> void:
	print("NETBOT %s %s" % [role, text])


func check(cond: bool, what: String) -> void:
	say(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func wait_until(cond: Callable, timeout := 20.0) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > timeout:
			return false
	return true


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


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


func items_of(kind: String) -> Array:
	return Session.model.items.values().filter(func(i): return i["kind"] == kind and i["space"] == "town")


func finish() -> void:
	say("DONE %s" % ("PASS" if failures == 0 else "FAIL"))
	Session.leave()
	get_tree().quit(1 if failures else 0)


func _run() -> void:
	var presets := {"a": 0, "b": 1, "c": 2, "d": 3, "e": 0, "check": 1, "show1": 1, "show2": 2}
	var avatar: Dictionary = Avatar.PRESETS[presets.get(role, 0)].duplicate()
	if role == "e":
		avatar["nick"] = "Berry"
	var rejected := [""]
	Session.rejected.connect(func(r): rejected[0] = r)
	Session.join(main.args.get("url", "ws://127.0.0.1:9080"), avatar)
	var joined := await wait_until(func(): return Session.is_online() or rejected[0] != "", 15.0)
	if role == "e":
		check(rejected[0] == "The town is full right now", "a fifth player is turned away kindly (%s)" % rejected[0])
		finish()
		return
	check(joined and Session.is_online(), "joined the town server")
	if not Session.is_online():
		finish()
		return
	check(Session.model.items.size() > 20, "received the shared town (%d items)" % Session.model.items.size())
	match role:
		"a": await _role_a()
		"b": await _role_b()
		"c": await _role_c()
		"d": await _role_d()
		"check": await _role_check()
		"show1", "show2": await _role_show()
	finish()


## Sunny: hosts nothing, just starts a tea party and holds the bench.
func _role_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees a second friend arrive")
	var r := await ask(Session.place("table", "town", Vector2(-6, 5), 0, -2))
	check(r.get("ok", false), "placed a round table")
	var bench: Dictionary = items_of("bench")[0]
	r = await ask(Session.lock(bench["id"]))
	check(r.get("ok", false), "picked up the bench to move it")
	Session.send_state({"space": "town", "x": -4.0, "z": 6.0, "ry": 0.0, "anim": "walk"})
	check(await wait_until(func(): return Session.model.lanterns.has("tea_party")), "saw the tea party lantern light up")
	Session.send_emote("cheer")
	await wait(3.0)
	r = await ask(Session.move(bench["id"], Vector2(bench["x"] - 1.0, bench["z"]), bench["rot"]))
	check(r.get("ok", false), "moved the bench while holding it")
	Session.unlock(bench["id"])
	await wait_until(func(): return Session.players.size() >= 4, 15.0)
	await wait(HOLD)


## Sky: completes the tea party, is blocked from the held bench, rides the swing.
func _role_b() -> void:
	check(await wait_until(func(): return not items_of("table").is_empty()), "saw the table placed by a friend")
	var t: Dictionary = items_of("table")[0]
	for dx in [-1.25, 1.25]:
		var r := await ask(Session.place("chair", "town", Vector2(t["x"] + dx, t["z"]), 2 if dx < 0 else 6, 0))
		check(r.get("ok", false), "placed a chair")
	check(await wait_until(func(): return Session.model.lanterns.has("tea_party")), "tea party lantern lit for everyone")
	check(Session.model.lanterns.get("tea_party", {}).get("by", []).size() >= 2, "lantern credits everyone present")
	var bench: Dictionary = items_of("bench")[0]
	await wait_until(func(): return Session.lock_holder(bench["id"]) != 0)
	var r := await ask(Session.lock(bench["id"]))
	check(not r.get("ok", true) and r.get("error") == "Someone else is using that.", "cannot grab the bench a friend is moving")
	check(await wait_until(func(): return Session.players.values().any(func(pl): return pl["state"].get("anim") == "walk")), "sees a friend walking")
	var swing: Dictionary = items_of("swing")[0]
	r = await ask(Session.sit(swing["id"]))
	check(r.get("ok", false), "sat on the swing")
	await wait_until(func(): return Session.players.size() >= 4, 15.0)
	await wait(HOLD)
	Session.stand()


## Peach: joins late and must receive everything already made.
func _role_c() -> void:
	check(await wait_until(func(): return Session.model.lanterns.has("tea_party"), 30.0), "late joiner sees the existing lantern")
	check(items_of("chair").size() >= 2 and items_of("table").size() >= 1, "late joiner receives the tea party furniture")
	var swing: Dictionary = items_of("swing")[0]
	check(await wait_until(func(): return not Session.seat_holders(swing["id"]).is_empty()), "sees a friend on the swing")
	var r := await ask(Session.sit(swing["id"]))
	check(not r.get("ok", true), "the one-seat swing is already taken")
	r = await ask(Session.ring_bell())
	check(r.get("ok", false), "rang the evening bell")
	check(await wait_until(func(): return Session.model.evening), "evening reached this player")
	await wait(HOLD)


## Leaf: fills the fourth spot, then a house removal is shared.
func _role_d() -> void:
	check(await wait_until(func(): return Session.players.size() >= 4), "four friends in town")
	var r := await ask(Session.place("cottage", "town", Vector2(-10, 9.5), 0, 6))
	check(r.get("ok", false), "placed a lilac cottage")
	var house: String = r.get("item", {}).get("id", "")
	r = await ask(Session.place("bed", house, Vector2(0, 0), 0, 3))
	check(r.get("ok", false), "furnished the new cottage")
	await wait(1.0)
	r = await ask(Session.remove(house))
	check(r.get("ok", false) and r.get("removed", []).size() == 2, "putting the house away packs its furniture too")
	r = await ask(Session.restore(r.get("removed", [])))
	check(r.get("ok", false) and Session.model.items_in(house).size() == 1, "undo brings back the house with its bed")
	await wait(HOLD)


## After a server restart: everything made together is still there.
func _role_check() -> void:
	check(Session.model.lanterns.has("tea_party"), "lantern survived the server restart")
	check(items_of("chair").size() >= 2, "chairs survived the server restart")
	check(Session.model.evening, "evening survived the server restart")
	var cottages := items_of("cottage")
	check(cottages.size() >= 3, "the friend's cottage survived")
	var furnished := cottages.filter(func(c): return Session.model.items_in(c["id"]).any(func(i): return i["kind"] == "bed" and i["color"] == 3))
	check(furnished.size() == 1, "its furniture survived")


## Friends for the rendered multiplayer screenshot: walk over and play near the viewer.
func _role_show() -> void:
	var first := role == "show1"
	if first:
		await ask(Session.place("blanket", "town", Vector2(5.2, 5.6), 0, 4))
	var spot := Vector2(-1.4, 10.2) if first else Vector2(1.6, 10.6)
	var pos := Vector2(Session.players[Session.my_id]["state"]["x"], Session.players[Session.my_id]["state"]["z"])
	for i in 30:
		pos = pos.move_toward(spot, 0.25)
		Session.send_state({"space": "town", "x": pos.x, "z": pos.y, "ry": 0.4 if first else -0.4, "anim": "walk"})
		await wait(0.1)
	Session.send_state({"space": "town", "x": pos.x, "z": pos.y, "ry": 0.4 if first else -0.4, "anim": "idle"})
	# Stay until the rendered viewer (Leaf) has joined, then keep playing a while.
	await wait_until(func(): return Session.players.values().any(func(p): return p["avatar"]["nick"] == "Leaf"), 240.0)
	var t := 0.0
	while t < float(main.args.get("hold", "45")):
		Session.send_emote("wave" if first else "dance")
		await wait(2.0)
		t += 2.0
