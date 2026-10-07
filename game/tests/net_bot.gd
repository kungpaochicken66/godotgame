## A scripted player that joins a real town server over WebSocket. Several bot
## processes run at once against one dedicated server (see scripts/net_test.py).
## They are real network peers on this machine, not simulated in-process players.
##   godot --headless --path game -- --driver=res://tests/net_bot.gd --url=ws://127.0.0.1:9080 --role=a
extends Node

const Avatar := preload("res://scripts/core/avatar.gd")
const TownModel := preload("res://scripts/core/town_model.gd")

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
	var presets := {"a": 0, "b": 1, "c": 2, "d": 3, "e": 0, "check": 1, "show1": 1, "show2": 2,
		"act_a": 0, "act_b": 1, "act_c": 2, "act_check": 3}
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
		"act_a", "act_b": await _role_activities()
		"act_c": await _role_late_joiner()
		"act_check": await _role_activities_check()
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
	r = await ask(Session.place("table", "town", Vector2(-11, 10), 0, -2))
	check(r.get("ok", false), "placed a table for the tabletop race")
	await _race_for_table()
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
	check(await wait_until(func(): return Animals.states.size() == 5), "five animal friends arrive from the server")
	var first: Array = Animals.states.map(func(a): return a["pos"])
	await wait(4.0)
	var moved := 0
	for i in Animals.states.size():
		if Animals.states[i]["pos"].distance_to(first[i]) > 0.3:
			moved += 1
	check(moved >= 3, "animals roam for every player (%d moved)" % moved)
	var swing: Dictionary = items_of("swing")[0]
	r = await ask(Session.sit(swing["id"]))
	check(r.get("ok", false), "sat on the swing")
	await _race_for_table()
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
	var home: String = items_of("cottage")[0]["id"]
	var kitchen := TownModel.room_space(home, 0, 1)
	Session.send_state({"space": kitchen, "x": 2.5, "z": -1.4, "ry": 0.0, "anim": "idle"})
	r = await ask(Session.place("chair", kitchen, Vector2(-2.0, 1.5), 0, 4))
	check(r.get("ok", false) and r.get("item", {}).get("space") == kitchen, "furnished the kitchen of a cottage")
	r = await ask(Session.ring_bell())
	check(r.get("ok", false), "rang the evening bell")
	check(await wait_until(func(): return Session.model.evening), "evening reached this player")
	check(await wait_until(func(): return Session.players.values().any(func(p): return TownModel.parse_room(p["state"].get("space", "")).get("floor", -1) == 1)),
		"sees a friend upstairs, in a different room")
	await wait(HOLD)


## Two real clients put a flower pot on the same table at the same moment.
func _race_for_table() -> void:
	var tables := func(): return items_of("table").filter(func(t): return absf(t["x"] + 11.0) < 0.01 and absf(t["z"] - 10.0) < 0.01)
	check(await wait_until(func(): return not tables.call().is_empty()), "sees the race table")
	if tables.call().is_empty():
		return
	var table: String = tables.call()[0]["id"]
	# Both bots fire at the next 4-second mark of the shared clock.
	var start := Time.get_unix_time_from_system()
	var mark := (floorf(start / 4.0) + 2.0) * 4.0
	while Time.get_unix_time_from_system() < mark:
		await get_tree().process_frame
	var r := await ask(Session.place("plant", "town", Vector2(-11, 10), 0, 3, table))
	if r.get("ok", false):
		say("RACE won")
	else:
		check(r.get("error") == "There is already something on top.", "lost the race politely (%s)" % r.get("error"))
		say("RACE lost")
	await wait(1.0)
	check(Session.model.attachments_of(table).size() == 1, "exactly one pot on the table for everyone")


## Leaf: fills the fourth spot, then a house removal is shared.
func _role_d() -> void:
	check(await wait_until(func(): return Session.players.size() >= 4), "four friends in town")
	var r := await ask(Session.place("cottage", "town", Vector2(-4, 16), 0, 6))
	check(r.get("ok", false), "placed a lilac cottage")
	var house: String = r.get("item", {}).get("id", "")
	r = await ask(Session.place("bed", TownModel.room_space(house, 1, 0), Vector2(0, 0.5), 0, 3))
	check(r.get("ok", false), "furnished the new cottage")
	await wait(1.0)
	r = await ask(Session.remove(house))
	check(r.get("ok", false) and r.get("removed", []).size() == 2, "putting the house away packs its furniture too")
	r = await ask(Session.restore(r.get("removed", [])))
	check(r.get("ok", false) and Session.model.items_in_house(house).size() == 1, "undo brings back the house with its bed")
	var home: String = items_of("cottage")[0]["id"]
	Session.send_state({"space": TownModel.room_space(home, 1, 0), "x": 0.0, "z": 0.0, "ry": 0.0, "anim": "idle"})
	check(await wait_until(func(): return Session.model.items_in(TownModel.room_space(home, 0, 1)).any(func(i): return i["kind"] == "chair")), "sees a friend's new kitchen chair")
	check(Session.model.items_in(TownModel.room_space(home, 1, 0)).all(func(i): return i["kind"] != "chair"), "the chair is not in the bedroom")
	await wait(0.6)
	r = await ask(Session.remove(home))
	check(not r.get("ok", true) and r.get("error") == "Someone is inside this house.", "cannot put away a house while a friend is in its kitchen")
	await wait(HOLD)


## After a server restart: everything made together is still there.
func _role_check() -> void:
	check(Session.model.lanterns.has("tea_party"), "lantern survived the server restart")
	check(items_of("chair").size() >= 2, "chairs survived the server restart")
	check(Session.model.evening, "evening survived the server restart")
	var cottages := items_of("cottage")
	check(cottages.size() >= 3, "the friend's cottage survived")
	var furnished := cottages.filter(func(c): return Session.model.items_in(TownModel.room_space(c["id"], 1, 0)).any(func(i): return i["kind"] == "bed" and i["color"] == 3))
	check(furnished.size() == 1, "its upstairs bedroom furniture survived")
	var kitchen := TownModel.room_space(cottages[0]["id"], 0, 1)
	check(Session.model.items_in(kitchen).any(func(i): return i["kind"] == "chair" and i["color"] == 4), "the kitchen chair survived in its room")
	check(await wait_until(func(): return Animals.states.size() == 5), "animals are back after the restart")
	var race := items_of("table").filter(func(t): return absf(t["x"] + 11.0) < 0.01)
	check(race.size() == 1 and Session.model.attachments_of(race[0]["id"]).size() == 1, "the pot is still on the race table after the restart")


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



# ------------------------------------------------------------- activities scenario

## Waits for the next shared-clock mark so two bots act at the same moment.
func _mark(every := 4.0) -> void:
	var mark := (floorf(Time.get_unix_time_from_system() / every) + 2.0) * every
	while Time.get_unix_time_from_system() < mark:
		await get_tree().process_frame


func _walk(to: Vector2, space := "town") -> void:
	var st: Dictionary = Session.players[Session.my_id]["state"]
	var p := Vector2(st.get("x", 0.0), st.get("z", 0.0))
	while p.distance_to(to) > 0.05:
		p = p.move_toward(to, 0.6)
		Session.send_state({"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "walk"})
		await wait(0.1)
	Session.send_state({"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"})
	await wait(0.3)


const HIDE_SPOT := Vector2(8.0, 15.0)


## Sunny and Sky: conflicting starts, a full hide-and-seek round, a party, a present.
func _role_activities() -> void:
	var messages := []
	Activities.message.connect(func(t): messages.append(t))
	check(await wait_until(func(): return Session.players.size() >= 2), "two friends in town")
	await _mark()
	Activities.start_hide_and_seek()   # both press the stump at the same moment
	check(await wait_until(func(): return Activities.hs.get("phase") == "hiding"), "hide-and-seek started")
	await wait(1.0)
	var i_hide: bool = Activities.hs.get("hider") == Session.my_id
	say("HS " + ("hider" if i_hide else "seeker"))
	check(i_hide or messages.has("A game of hide-and-seek is already going. Join in!"), "a conflicting start just joins the game")
	if i_hide:
		await _walk(HIDE_SPOT)
		Activities.hide_here()
		check(await wait_until(func(): return Activities.hs.get("phase") == "seeking"), "the acorn is hidden")
		var found := [""]
		Activities.hs_found.connect(func(n): found[0] = n)
		check(await wait_until(func(): return found[0] != "", 40.0), "a friend found my acorn (%s)" % found[0])
	else:
		check(await wait_until(func(): return Activities.hs.get("phase") == "seeking", 30.0), "the hider has hidden the acorn")
		await wait(1.0)
		check(Activities.near_acorn.is_empty() and not Activities.hs.has("acorn"), "the hidden spot is secret while I am far away")
		var far: int = Activities.warmth
		await _walk(HIDE_SPOT + Vector2(4.0, 0))
		await wait(1.0)
		check(Activities.warmth > far, "warmer when closer (%d -> %d)" % [far, Activities.warmth])
		check(Activities.near_acorn.is_empty(), "still hidden at 4 m")
		await _walk(HIDE_SPOT + Vector2(1.0, 0))
		check(await wait_until(func(): return not Activities.near_acorn.is_empty()), "the acorn appears when I am right there")
		var found := [""]
		Activities.hs_found.connect(func(n): found[0] = n)
		Activities.find_acorn()
		check(await wait_until(func(): return found[0] == Session.nick_of(Session.my_id)), "I found the golden acorn")
	check(await wait_until(func(): return Activities.hs.get("phase") == "none"), "the round is over for everyone")
	# Party: both press the drum together; one starts it, the other joins in.
	messages.clear()
	await _mark()
	Activities.start_party()
	check(await wait_until(func(): return Activities.is_party()), "the dance party is on")
	await wait(1.0)
	say("PARTY " + ("joined" if messages.has("The party is on. Dance along!") else "started"))
	# Sunny changes the weather, starts a new round for the late joiner, and wraps a present for Sky.
	if role == "act_a":
		await ask(Session.change_weather())
		check(Session.model.weather == "rain", "the weather vane turned to rain")
		Activities.start_hide_and_seek()
		check(await wait_until(func(): return Activities.hs.get("phase") == "hiding"), "a second round waits for the hider")
		var sky := ""
		for pid in Session.model.roster:
			if Session.model.roster[pid]["nick"] == "Sky":
				sky = pid
		var bench := await ask(Session.place("bench", "town", Vector2(-8, 16), 0, 4))
		var r := await ask(Session.wrap(bench.get("item", {}).get("id", ""), sky, 3))
		check(r.get("ok", false) and r["item"]["gift"]["to"] == sky, "wrapped a bench for Sky's player id")
		check(await wait_until(func(): return Session.players.size() >= 3, 40.0), "a late friend arrived")
		await wait(12.0)
		Activities.stop_hide_and_seek()
		check(await wait_until(func(): return Activities.hs.get("phase") == "none"), "Stop ends the round for everyone")
	else:
		check(await wait_until(func(): return Session.model.items.values().any(func(i): return i.get("gift", {}).get("to", "") == Session.my_pid), 40.0), "a present for me appeared")
		await wait_until(func(): return Session.players.size() >= 3, 40.0)
		await wait(6.0)   # the late friend tries to open it first
		var gift_id: String = Session.model.items.values().filter(func(i): return i.get("gift", {}).get("to", "") == Session.my_pid)[0]["id"]
		var r := await ask(Session.unwrap(gift_id))
		check(r.get("ok", false), "I opened my present")
		var attic := TownModel.room_space(items_of("cottage")[0]["id"], 2, 0)
		Session.send_state({"space": attic, "x": 0.0, "z": 0.0, "ry": 0.0, "anim": "idle"})
		await ask(Session.toggle_heart(attic))
	await wait(HOLD)


## Peach joins late: gets the running party, the weather and the waiting round,
## cannot open someone else's present, and leaves a heart.
func _role_late_joiner() -> void:
	check(Activities.is_party() or Session.model.weather == "rain", "joined while things are going on")
	check(await wait_until(func(): return Activities.hs.get("phase") == "hiding", 20.0), "the running hide-and-seek round reached me")
	check(Session.model.weather == "rain", "the weather reached me")
	check(Activities.is_party(), "the party reached me as a late joiner")
	check(await wait_until(func(): return Session.model.items.values().any(func(i): return i.has("gift"))), "I can see a present")
	var gift: Dictionary = Session.model.items.values().filter(func(i): return i.has("gift"))[0]
	var r := await ask(Session.unwrap(gift["id"]))
	check(not r.get("ok", true) and r.get("error") == "That present is for someone else.", "I cannot open a present meant for Sky")
	check(await wait_until(func(): return Activities.hs.get("phase") == "none", 30.0), "the round was stopped")
	var attic := TownModel.room_space(items_of("cottage")[0]["id"], 2, 0)
	Session.send_state({"space": attic, "x": 1.0, "z": 0.0, "ry": 0.0, "anim": "idle"})
	await ask(Session.toggle_heart(attic))
	check(await wait_until(func(): return Session.model.hearts.get(attic, {}).size() >= 2, 20.0), "two friends left hearts in the attic")
	await wait(4.0)


func _role_activities_check() -> void:
	var attic := TownModel.room_space(items_of("cottage")[0]["id"], 2, 0)
	check(Session.model.weather == "rain", "the weather survived the restart")
	check(Session.model.hearts.get(attic, {}).size() >= 2, "hearts survived the restart")
	check(Session.model.visits.get(items_of("cottage")[0]["id"], {}).size() >= 2, "the guest book survived the restart")
	check(Session.model.roster.size() >= 3, "the roster remembers the friends by id")
	check(items_of("bench").all(func(b): return not b.has("gift")), "the opened present stayed opened")
	check(Activities.hs.get("phase") == "none" and not Activities.is_party(), "games in progress do not survive a restart (by design)")
