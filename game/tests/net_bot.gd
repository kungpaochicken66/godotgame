## A scripted player that joins a real town server over WebSocket. Several bot
## processes run at once against one dedicated server (see scripts/net_test.py).
## They are real network peers on this machine, not simulated in-process players.
##   godot --headless --path game -- --driver=res://tests/net_bot.gd --url=ws://127.0.0.1:9080 --role=a
extends Node

const Avatar := preload("res://scripts/core/avatar.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Deployment := preload("res://scripts/net/deployment.gd")
const Wearables := preload("res://scripts/core/wearables.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Props := preload("res://scripts/art/props.gd")

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
	Music.quit_game(1 if failures else 0)


func _run() -> void:
	var presets := {"a": 0, "b": 1, "c": 2, "d": 3, "e": 0, "check": 1, "show1": 1, "show2": 2,
		"act_a": 0, "act_b": 1, "act_c": 2, "act_check": 3, "inv_ok": 0, "inv_wrong": 1, "inv_none": 2, "inv_reconnect": 3,
		"remote_a": 0, "remote_b": 1, "remote_mark": 2, "remote_verify": 3, "inv_linger": 1, "pets_a": 0, "pets_b": 1, "pets_check": 2,
		"play_a": 0, "play_b": 1, "play_check": 2, "b2_a": 0, "b2_b": 1, "b2_check": 2,
		"r11_a": 0, "r11_b": 1, "r11_check": 2, "wear_a": 0, "wear_b": 1, "wear_check": 2,
		"furn_a": 0, "furn_b": 1, "furn_check": 2, "seat_a": 0, "seat_b": 1, "seat_c": 2, "seat_check": 3,
		"visit_a": 0, "visit_b": 1, "visit_c": 2, "visit_check": 3}
	var avatar: Dictionary = Avatar.PRESETS[presets.get(role, 0)].duplicate()
	if role == "e":
		avatar["nick"] = "Berry"
	var rejected := [""]
	Session.rejected.connect(func(r): rejected[0] = r)
	# Address and invite: --url, then the packaged private config (--use-private-config).
	# The invite comes from --invite-file (operator checks), the private config, or
	# --invite (local tests only). Neither is ever printed.
	var cfg: Dictionary = Deployment.load_config() if main.args.has("use-private-config") else {}
	var url: String = main.args.get("url", cfg.get("url", "ws://127.0.0.1:9080"))
	var invite: String = main.args.get("invite", "")
	if main.args.has("invite-file"):
		var r: Dictionary = Deployment.read_invite_file(main.args["invite-file"])
		check(r["ok"], "read the invite file (%s)" % ("ok" if r["ok"] else r["reason"]))
		invite = r.get("invite", "")
	elif not cfg.is_empty():
		invite = Deployment.invite_for(cfg, url, invite)
	if role in ["inv_wrong", "inv_linger"]:
		invite = "wrong-%d" % randi()   # never the real invite
	elif role == "inv_none":
		invite = ""
	if role == "inv_linger":
		# A client that reads the refusal but keeps the connection open: the server
		# must still close it (fail-closed), without ever sending town data.
		Session.rejected.connect(func(_r): Session._join_refused = false)
	if role.begins_with("connect_"):
		await _role_connect(url, avatar, invite, rejected)
		finish()
		return
	Session.join(url, avatar, invite)
	var joined := await wait_until(func(): return Session.is_online() or rejected[0] != "", 15.0)
	if role in ["inv_wrong", "inv_none", "inv_linger"]:
		check(rejected[0] == "This town needs the right invite code.", "a %s invite is refused kindly (%s)" % ["missing" if role == "inv_none" else "wrong", rejected[0]])
		check(not Session.is_online() and Session.model.items.is_empty() and Session.players.is_empty(), "nothing of the town was received before the invite was checked")
		var t0 := Time.get_ticks_msec()
		check(await wait_until(func(): return Session.state in ["failed", "disconnected", "offline"], 12.0), "the refused connection was closed (%s)" % Session.state)
		if role == "inv_linger":
			var secs := (Time.get_ticks_msec() - t0) / 1000.0
			check(secs <= Session.REFUSE_GRACE + 3.0, "the server closed a lingering refused connection itself (%.1f s)" % secs)
		check(Session.model.items.is_empty(), "still no town data after the close")
		finish()
		return
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
		"inv_ok": await _role_invite_ok()
		"inv_reconnect": await _role_invite_reconnect(url, avatar, invite)
		"remote_a", "remote_mark": await _role_remote_a(role == "remote_mark")
		"remote_b": await _role_remote_b(url, avatar, invite)
		"remote_verify": await _role_remote_verify()
		"pets_a": await _role_pets_a()
		"pets_b": await _role_pets_b()
		"pets_check": await _role_pets_check()
		"play_a": await _role_play_a()
		"play_b": await _role_play_b()
		"play_check": await _role_play_check()
		"b2_a": await _role_b2_a()
		"b2_b": await _role_b2_b()
		"b2_check": await _role_b2_check()
		"r11_a": await _role_r11_a()
		"r11_b": await _role_r11_b()
		"r11_check": await _role_r11_check()
		"wear_a": await _role_wear_a(url, invite)
		"wear_b": await _role_wear_b()
		"wear_check": await _role_wear_check(url, avatar, invite)
		"furn_a": await _role_furn_a(url, avatar, invite)
		"furn_b": await _role_furn_b()
		"furn_check": await _role_furn_check()
		"seat_a": await _role_seat_a()
		"seat_b": await _role_seat_b()
		"seat_c": await _role_seat_c()
		"seat_check": await _role_seat_check()
		"visit_a": await _role_visit_a()
		"visit_b": await _role_visit_b()
		"visit_c": await _role_visit_c()
		"visit_check": await _role_visit_check()
	finish()


# ------------------------------------------------------------- pets and cooking

func _kitchen() -> String:
	var homes := items_of("cottage")
	homes.sort_custom(func(a, b): return int(a["id"].substr(1)) < int(b["id"].substr(1)))
	return TownModel.room_space(homes[0]["id"], 0, 1)


func _go(space: String, at: Vector2) -> void:
	Session.send_state({"space": space, "x": at.x, "z": at.y, "ry": 0.0, "anim": "idle"})
	await wait(0.6)


## Sunny: adopts a dog that follows her, sets up the kitchen and cooks rice.
func _role_pets_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var r := await ask(Session.adopt_pet("dog", 1, 2))
	check(r.get("ok", false) and r["pet"]["name"] == "Waffle", "adopted a spotted dog called Waffle")
	var mine: Dictionary = Session.model.pets.get(Session.my_pid, {})
	check(mine.get("active", "") == r.get("pet", {}).get("id", "-") and mine.get("mode") == "follow", "the dog follows me")
	r = await ask(Session.adopt_pet("lizard", 0, 0))
	check(not r.get("ok", true), "a lizard cannot be adopted")
	say("PET adopted")
	var kitchen := _kitchen()
	await _go(kitchen, Vector2(0, 0.5))
	r = await ask(Session.furnish_room(kitchen))
	check(r.get("ok", false) and items_in(kitchen, "kitchen_stove").size() == 1, "set up the kitchen (%d things%s)" % [r.get("count", 0), (", " + str(r.get("error", ""))) if not r.get("ok", false) else ""])
	var stove: Dictionary = items_in(kitchen, "kitchen_stove")[0]
	await _go(kitchen, Vector2(stove["x"], stove["z"] + 0.9))
	say("KITCHEN ready")
	r = await ask(Session.cook(stove["id"], "rice"))
	check(r.get("ok", false), "started cooking a rice bowl")
	say("COOKING")
	check(await wait_until(func(): return not items_in(kitchen, "dish_rice_bowl").is_empty(), 15.0), "the rice bowl was served")
	await wait(8.0)   # the friend eats, then I go home and come back
	Session.leave()
	await wait(4.0)


## Sky: sees Sunny's dog behind Sunny, is refused a busy stove, eats the rice.
func _role_pets_b() -> void:
	var a_pid := [""]
	check(await wait_until(func():
		for pid in Session.model.pets:
			if pid != Session.my_pid:
				a_pid[0] = pid
				return true
		return false, 30.0), "sees the friend's new pet")
	var a_peer := Session.peer_of_pid(a_pid[0])
	var layer: Node = main.world.pet_layer
	var key: String = a_pid[0] + "/" + Session.model.pets[a_pid[0]]["active"]
	check(await wait_until(func(): return layer.pets.has(key), 10.0), "the dog is drawn here too")
	check(layer.pets.has(key) and int(layer.pets[key].get_meta("follow_peer", 0)) == a_peer and a_peer != 0, "it follows its owner, not me")
	check(layer.pets.has(key) and layer.pets[key].model_id == "pet_dog_spotted", "it is the spotted dog model")
	var kitchen := _kitchen()
	check(await wait_until(func(): return not Session.cooking.is_empty(), 30.0), "sees the stove start cooking")
	var stove: Dictionary = items_in(kitchen, "kitchen_stove")[0]
	await _go(kitchen, Vector2(stove["x"] + 0.6, stove["z"] + 0.9))
	var r := await ask(Session.cook(stove["id"], "rice"))
	check(not r.get("ok", true) and r.get("error", "") == "Someone is cooking on this stove. Try again in a moment.", "a busy stove is refused")
	check(await wait_until(func(): return not items_in(kitchen, "dish_rice_bowl").is_empty(), 15.0), "sees the rice bowl served")
	var dish: Dictionary = items_in(kitchen, "dish_rice_bowl")[0]
	r = await ask(Session.eat(dish["id"]))
	check(r.get("ok", false) and not Session.model.items.has(dish["id"]), "ate the rice bowl")
	check(int(Session.model.cooked.get(a_pid[0], 0)) == 1, "the cook's count is shared")
	check(await wait_until(func(): return not layer.pets.has(key), 20.0), "the dog leaves with its owner")


## After a server restart: the pet, its owner and the kitchen are still there.
func _role_pets_check() -> void:
	var owners: Array = Session.model.pets.keys()
	check(owners.size() == 1, "one player's pets were saved")
	if owners.is_empty():
		return
	var e: Dictionary = Session.model.pets[owners[0]]
	check(e["pets"].size() == 1 and e["pets"][0]["family"] == "dog" and e["pets"][0]["name"] == "Waffle", "Waffle the dog survived the restart")
	check(not items_in(_kitchen(), "kitchen_stove").is_empty() and items_in(_kitchen(), "dish_rice_bowl").is_empty(), "the kitchen is set up and the eaten dish is gone")
	check(Session.model.cooked.values() == [1], "the cooking count survived")


# ------------------------------------------------------------- play ideas (design/playability-8-12.md)

func _dog_state() -> Dictionary:
	for st in Animals.states:
		if st["kind"] == "dog":
			return st
	return {}


func _where_peer(peer: int) -> Vector2:
	var st: Dictionary = Session.players.get(peer, {}).get("state", {})
	return Vector2(float(st.get("x", 999.0)), float(st.get("z", 999.0)))


## Sunny: sets up a snack tray, makes a snack and shares it with Sky, puts the
## square on display, then plays fetch with Biscuit.
func _role_play_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var spot: Vector2 = Session.model.find_free_spot("snack_tray", "town", Vector2(8, -10))
	var r := await ask(Session.place("snack_tray", "town", spot, 0, -2))
	check(r.get("ok", false), "placed a snack tray")
	var tray: Dictionary = r.get("item", {})
	await _go("town", Vector2(tray["x"], tray["z"] + 1.0))
	r = await ask(Session.make_snack(tray["id"], "snack_cookie", "honey"))
	check(r.get("ok", false) and Session.model.items.get(r.get("id", ""), {}).get("color") == 1, "made a honey cookie (%s)" % r.get("error", "ok"))
	var snack: Dictionary = Session.model.items.get(r.get("id", ""), {})
	var b_peer: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	check(await wait_until(func(): return _where_peer(b_peer).distance_to(Vector2(snack["x"], snack["z"])) < 3.0, 20.0), "the friend came over for the snack")
	await _go("town", Vector2(snack["x"], snack["z"] + 0.6))
	r = await ask(Session.share_snack(snack["id"]))
	check(r.get("ok", false) and r.get("cheered", 0) == 2, "shared the snack: both of us cheered (%s)" % r.get("cheered", r.get("error")))
	r = await ask(Session.set_display("town", true))
	check(r.get("ok", false) and r.get("on", false), "put the town square on display")
	say("DISPLAY on")
	# Fetch: stand near Biscuit and throw.
	check(await wait_until(func(): return not _dog_state().is_empty(), 10.0), "sees Biscuit")
	var dog: Dictionary = _dog_state()
	await _go("town", dog["pos"] + Vector2(1.2, 0))
	var me_at: Vector2 = dog["pos"] + Vector2(1.2, 0)
	r = await ask(Session.throw_ball(me_at + Vector2(0, 5)))
	check(r.get("ok", false), "threw the ball for Biscuit (%s)" % r.get("error", "ok"))
	var seen := {"carry": false}
	check(await wait_until(func():
		if _dog_state().get("action") == "carry":
			seen["carry"] = true
		return seen["carry"] and _dog_state().get("action") != "carry", 25.0), "Biscuit carried the ball back")
	check(_dog_state().get("pos", Vector2(99, 99)).distance_to(me_at) < 2.5, "Biscuit brought it to me (%.1f m)" % _dog_state().get("pos", Vector2(99, 99)).distance_to(me_at))
	# Keep the square on display for the restart check, after the friend is done.
	check(await wait_until(func(): return not items_of("snowman").is_empty() and items_of("snowman")[0].get("variant") == 1, 30.0), "sees the friend's snowman with its new face")
	r = await ask(Session.set_display("town", true))
	check(r.get("on", false), "put the square back on display")
	await wait(2.0)


## Sky: comes for the snack and cheers, is asked about the display, takes it off,
## builds a snowman, and watches the fetch game.
func _role_play_b() -> void:
	var cheers := [0]
	var thrown := [0]
	Session.emote.connect(func(peer, kind):
		if peer == Session.my_id and kind == "cheer":
			cheers[0] += 1)
	Animals.thrown.connect(func(_f, _t): thrown[0] += 1)
	check(await wait_until(func(): return not Session.model.items.values().filter(func(i): return i["kind"] == "snack_cookie").is_empty(), 30.0), "sees the friend's snack")
	var snack: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "snack_cookie")[0]
	await _go("town", Vector2(snack["x"] + 0.8, snack["z"]))
	check(await wait_until(func(): return not Session.model.items.has(snack["id"]), 20.0), "the snack was shared")
	check(await wait_until(func(): return cheers[0] >= 1, 5.0), "I cheered too")
	check(await wait_until(func(): return not Session.model.display_by("town").is_empty(), 20.0), "sees the square on display")
	check(Session.display_by_other("town").get("nick") == "Sunny", "it was Sunny who put it on display")
	var spot: Vector2 = Session.model.find_free_spot("snowman", "town", Vector2(-8, -12))
	var r := await ask(Session.place("snowman", "town", spot, 0, 3))
	check(r.get("error", "") == "This place is on display.", "a change on display is refused until I take it off")
	r = await ask(Session.set_display("town", false))
	check(r.get("ok", false) and not r.get("on", true), "took it off display after being asked")
	r = await ask(Session.place("snowman", "town", spot, 0, 3))
	check(r.get("ok", false), "built a snowman")
	var sm: String = r.get("item", {}).get("id", "")
	r = await ask(Session.change_face(sm))
	check(r.get("ok", false) and Session.model.items[sm].get("variant") == 1, "changed its face")
	check(await wait_until(func(): return thrown[0] >= 1, 30.0), "sees the ball fly")
	var seen := [false]
	check(await wait_until(func():
		seen[0] = seen[0] or _dog_state().get("action") == "carry"
		return seen[0], 20.0), "sees Biscuit carry the ball")
	await wait(6.0)


## After a restart: the snowman's face and the display mark were saved; the shared snack is gone.
func _role_play_check() -> void:
	var sm := items_of("snowman")
	check(sm.size() == 1 and sm[0].get("variant") == 1, "the snowman kept its face")
	check(Session.model.display_by("town").get("nick") == "Sunny", "the square is still on display")
	check(items_of("snack_tray").size() == 1 and items_of("snack_cookie").is_empty(), "the tray stayed; the shared snack is gone")


# ------------------------------------------------------------- play ideas batch 2

## A spot where `kinds` fit one meter apart along +z, starting at whole meters.
func _track_spot(n: int) -> Vector2:
	for x in range(6, 22):
		for z in range(-18, 16):
			var ok_all := true
			for i in n:
				if Session.model.check("track_straight", "town", x, z + i, 0) != "":
					ok_all = false
			if ok_all:
				return Vector2(x, z)
	return Vector2(99, 99)


## Sunny: dresses up, lays a trail, composes a tune and builds a track.
func _role_b2_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var b_peer: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	var r := await ask(Session.dress("crown", 2))
	check(r.get("ok", false), "put on the paper crown")
	var poses := []
	Session.emote.connect(func(peer, kind):
		if peer == b_peer and kind in ["surprised", "proud"]:
			poses.append(kind))
	# A trail of two signs.
	for p in [Vector2(-12, -16), Vector2(-6, -16)]:
		r = await ask(Session.place("trail_sign", "town", Session.model.find_free_spot("trail_sign", "town", p), 0, -2))
		check(r.get("ok", false), "placed trail sign %d" % r.get("item", {}).get("num", 0))
	say("TRAIL ready")
	var done := []
	Session.trail_changed.connect(func(peer, _f, _t, d, nick):
		if peer == b_peer and d:
			done.append(nick))
	check(await wait_until(func(): return not done.is_empty(), 40.0), "the friend walked my trail (%s)" % [done])
	# A music box tune.
	r = await ask(Session.place("music_box", "town", Session.model.find_free_spot("music_box", "town", Vector2(10, -16)), 0, -2))
	var mb: Dictionary = r.get("item", {})
	await _go("town", Vector2(mb["x"], mb["z"] + 1.0))
	check((await ask(Session.toggle_note(mb["id"], 2, 5))).get("ok", false), "added a chime")
	check((await ask(Session.play_music(mb["id"], true))).get("ok", false), "started the music box")
	say("MUSIC on")
	# A toy track: start, straight, finish.
	var base := _track_spot(3)
	for spec in [["track_start", 0], ["track_straight", 1], ["track_finish", 2]]:
		r = await ask(Session.place(spec[0], "town", base + Vector2(0, spec[1]), 0, -2))
		check(r.get("ok", false), "placed %s" % spec[0])
	await _go("town", base + Vector2(1.2, 0))
	var start: Dictionary = items_of("track_start")[0]
	r = await ask(Session.roll_track(start["id"]))
	check(r.get("ok", false) and r.get("end") == "finish" and r.get("cells") == 3, "the ball rolled to the finish (%s)" % [r])
	say("TRACK rolled")
	check(await wait_until(func(): return poses.size() >= 2, 30.0), "saw the friend's story poses (%s)" % [poses])
	await wait(3.0)


## Sky: sees the crown, walks the trail with its clues, hears the tune, sees the ball, poses.
func _role_b2_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var a_peer: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	check(await wait_until(func(): return Session.players[a_peer]["avatar"].get("hat") == "crown", 20.0), "sees the friend's paper crown")
	var kid: Node3D = main.world.kids.get(a_peer)
	check(kid != null and await wait_until(func(): return kid.get_node_or_null("Body/Head/Hat") != null and kid.get_node("Body/Head/Hat").get_child_count() > 0, 5.0), "the crown is drawn on the friend's head (Body/Head/Hat)")
	check(kid != null and kid.get_children().filter(func(c): return c.name == "Body").size() == 1, "the rebuilt rig keeps its exact node names")
	var rolled := []
	Session.track_rolled.connect(func(_id, cells, end, _at, _bells): rolled.append([cells.size(), end]))
	check(await wait_until(func(): return Session.model.trail_signs().size() == 2, 30.0), "sees the trail")
	await _go("town", Vector2(0, -12))
	check((await ask(Session.follow_trail(true))).get("ok", false), "started following the trail")
	var found := [0]
	Session.trail_changed.connect(func(peer, f, _t, _d, _n):
		if peer == Session.my_id:
			found[0] = f)
	for i in 2:
		var sign: Dictionary = Session.model.trail_signs()[i]
		await _go("town", Vector2(sign["x"], sign["z"] + 1.0))
		Session.send_emote("dance")   # not this sign's clue
		await wait(0.5)
		check(found[0] == i, "a wrong clue does not count")
		Session.send_emote("wave")
		check(await wait_until(func(): return found[0] == i + 1, 5.0), "found sign %d with its clue" % (i + 1))
	check(await wait_until(func(): return Session.model.keepsakes.size() == 1, 5.0), "a keepsake sticker is shared")
	# The tune: stand next to the box and hear it.
	check(await wait_until(func(): return not items_of("music_box").is_empty() and items_of("music_box")[0].get("on", false), 30.0), "sees the music box playing")
	var mb: Dictionary = items_of("music_box")[0]
	check(int(mb["song"][2]) & (1 << 5) != 0, "with the friend's chime in the tune")
	main.controller.pos = Vector2(mb["x"] + 1.0, mb["z"] + 1.0)   # the local child walks over too
	main.controller._place_kid()
	await _go("town", Vector2(mb["x"] + 1.0, mb["z"] + 1.0))
	var fx: Node = main.world.play_fx
	var before: int = fx.notes_played
	Sfx.music_boxes_muted = false
	check(await wait_until(func(): return fx.notes_played > before, 8.0), "hears the tune nearby (%d notes)" % (fx.notes_played - before))
	Sfx.music_boxes_muted = true
	await wait(1.0)
	var muted_at: int = fx.notes_played
	await wait(3.0)
	check(fx.notes_played == muted_at, "muting music boxes on my device silences them for me only")
	Sfx.music_boxes_muted = false
	check(await wait_until(func(): return not rolled.is_empty(), 30.0) and rolled[0] == [3, "finish"], "sees the ball roll to the finish (%s)" % [rolled])
	for pose in ["surprised", "proud"]:
		Session.send_emote(pose)
		await wait(0.5)
	await wait(4.0)


## After a restart: the trail, keepsake, tune and track are still there.
func _role_b2_check() -> void:
	check(Session.model.trail_signs().map(func(s): return s["num"]) == [1, 2], "the trail signs kept their numbers")
	check(Session.model.keepsakes.size() == 1 and Session.model.keepsakes[0]["by"] == ["Sky"], "the keepsake was saved")
	var mb := items_of("music_box")
	check(mb.size() == 1 and mb[0]["on"] and int(mb[0]["song"][2]) & (1 << 5) != 0, "the music box kept its tune and plays")
	check(items_of("track_start").size() == 1 and items_of("track_finish").size() == 1, "the track is still there")


# ------------------------------------------------------------- r11

func _animal_state(kind: String) -> Dictionary:
	for st in Animals.states:
		if st["kind"] == kind:
			return st
	return {}


## Sunny: asks for help on a place on display, invites to music with a part of
## her own, plays with Wooly, jumps in the leaves with Sky, builds a blueprint.
func _role_r11_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var joined := []
	Session.invite_joined.connect(func(nick, kind): joined.append([nick, kind]))
	await _go("town", Vector2(0, 6))
	check((await ask(Session.set_display("town", true))).get("on", false), "put the square on display")
	# Two different invitations back to back must both go out (r11 closeout: a
	# per-inviter cooldown refused the second one; the newer card replaces the older).
	var r := await ask(Session.send_invite("story", ""))
	check(r.get("ok", false) and r.get("sent") == 1, "invited Sky to my story (%s)" % [r])
	r = await ask(Session.send_invite("help", "town"))
	check(r.get("ok", false) and r.get("sent") == 1, "asked my friend to help edit right after (%s)" % [r])
	r = await ask(Session.send_invite("help", "town"))
	check(r.get("error", "") == "Your friends have your invitation.", "the same invitation again is held back")
	check(await wait_until(func(): return joined.has(["Sky", "help"]), 20.0), "Sky joined to help (%s)" % [joined])
	var benches := func(): return items_of("bench").size()
	var before: int = benches.call()
	check(await wait_until(func(): return benches.call() == before + 1, 20.0), "Sky's change while helping arrived")
	check(await wait_until(func(): return not Session.model.display_by("town").get("helpers", []).has(Session.model.roster.keys().filter(func(p): return p != Session.my_pid)[0]), 20.0), "Sky left helping")
	await wait(4.0)   # Sky checks the place is protected again before it comes off display
	check((await ask(Session.set_display("town", false))).get("ok", false), "took the square off display")
	# Music with parts.
	r = await ask(Session.place("music_box", "town", Session.model.find_free_spot("music_box", "town", Vector2(10, -16)), 0, -2))
	var mb: Dictionary = r.get("item", {})
	await _go("town", Vector2(mb["x"], mb["z"] + 1.0))
	check((await ask(Session.claim_music_part(mb["id"], 0))).get("mine", false), "took the bell part")
	r = await ask(Session.send_invite("music", mb["id"]))
	check(r.get("ok", false), "invited Sky to make music (%s)" % [r])
	check(await wait_until(func(): return joined.has(["Sky", "music"]), 20.0), "Sky joined the music")
	var song0: Array = mb["song"].duplicate()
	check(await wait_until(func(): return int(Session.model.items[mb["id"]]["song"][2]) != int(song0[2]), 20.0), "Sky played the chime part")
	check(int(Session.model.items[mb["id"]]["song"][0]) == int(song0[0]), "my bell part stayed mine")
	# Wooly's game, then the leaf pile.
	var sheep := _animal_state("sheep")
	await _go("town", sheep["pos"] + Vector2(1.5, 0))
	r = await ask(Session.play_with_animal("sheep", 0))
	check(r.get("ok", false) and r.get("result") == "started", "Wooly comes to sing with me (%s)" % [r])
	say("WOOLY started")
	var spot: Vector2 = Session.model.find_free_spot("leaf_pile", "town", Vector2(12, 10))
	r = await ask(Session.place("leaf_pile", "town", spot, 0, -2))
	var pile: Dictionary = r.get("item", {})
	await _go("town", Vector2(pile["x"], pile["z"] + 1.0))
	var jumps := []
	Session.leaves_jumped.connect(func(_id, peer, together): jumps.append([peer, together]))
	check(await wait_until(func(): return jumps.any(func(j): return j[0] != Session.my_id), 30.0), "saw Sky jump in")
	r = await ask(Session.jump_in_leaves(pile["id"]))
	check(r.get("ok", false) and r.get("together", false), "jumped in together with Sky")
	# A blueprint of the leaf corner, placed somewhere else; Sky sees it.
	var B = load("res://scripts/core/blueprints.gd")
	var bp: Dictionary = B.capture(Session.model, pile["id"])
	var target: Vector2 = Session.model.find_free_spot("leaf_pile", "town", Vector2(-14, 16))
	await _go("town", target + Vector2(0, 2))
	r = await ask(Session.place_blueprint("town", B.plan(bp, target, 2)))
	check(r.get("ok", false) and r.get("ids", []).size() >= 1, "placed my leaf corner blueprint (%s)" % [r])
	say("BLUEPRINT placed")
	# For the restart check: on display with Sky helping right now.
	await _go("town", Vector2(0, 6))
	await ask(Session.set_display("town", true))
	await wait(1.5)
	check((await ask(Session.send_invite("help", "town"))).get("ok", false), "asked for help again")
	check(await wait_until(func(): return joined.count(["Sky", "help"]) >= 2, 20.0), "Sky helps again")
	await wait(3.0)


## Sky: joins to help, edits, leaves; joins the music on a free part; joins
## Wooly's game; jumps in the leaves; sees the blueprint arrive.
func _role_r11_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var cards := []
	Session.invited.connect(func(c): cards.append(c))
	check(await wait_until(func(): return cards.any(func(c): return c["kind"] == "help"), 30.0), "got a Please help me edit card")
	check(cards.size() >= 2 and cards[0]["kind"] == "story", "the story card came first and the help card replaced it (%s)" % [cards.map(func(c): return c["kind"])])
	var help: Dictionary = cards.filter(func(c): return c["kind"] == "help")[0]
	check(help["nick"] == "Sunny" and help["space"] == "town", "from Sunny, for the town square")
	await _go("town", Vector2(help["x"] + 1.0, help["z"]))
	var spot: Vector2 = Session.model.find_free_spot("bench", "town", Vector2(-6, 10))
	var r := await ask(Session.place("bench", "town", spot, 0, -2))
	check(r.get("error", "") == "This place is on display.", "before joining, the place on display is protected")
	r = await ask(Session.answer_invite(help["from"], "join"))
	check(r.get("ok", false) and r.get("joined", false), "joined to help")
	check(r.get("card", {}).get("kind", "") == "help", "the newer help card replaced the story card on the server")
	check(await wait_until(func(): return Session.model.display_by("town").get("helpers", []).has(Session.my_pid), 5.0), "I am a helper now")
	r = await ask(Session.place("bench", "town", spot, 0, -2))
	check(r.get("ok", false), "as a helper I can decorate the place on display")
	await wait(1.0)
	check((await ask(Session.answer_invite(help["from"], "leave"))).get("ok", false), "left helping")
	await wait(0.5)
	r = await ask(Session.place("bench", "town", Session.model.find_free_spot("bench", "town", Vector2(-10, 12)), 0, -2))
	check(r.get("error", "") == "This place is on display.", "after Leave the place is protected again")
	# Music.
	check(await wait_until(func(): return cards.any(func(c): return c["kind"] == "music"), 40.0), "got a music invitation")
	if not cards.any(func(c): return c["kind"] == "music"):
		return
	var music: Dictionary = cards.filter(func(c): return c["kind"] == "music")[0]
	var mb: Dictionary = Session.model.items.get(music["target"], {})
	check(not mb.is_empty(), "it names the music box")
	check((await ask(Session.answer_invite(music["from"], "join"))).get("joined", false), "joined the music")
	await _go("town", Vector2(mb["x"] + 1.0, mb["z"] + 1.0))
	check(Session.music_part_names(mb["id"]).get(0, "") == "Sunny", "I can see Sunny plays the bell part")
	check((await ask(Session.toggle_note(mb["id"], 0, 1))).get("error", "") == "A friend is playing this part.", "her part is hers while she plays it")
	check((await ask(Session.toggle_note(mb["id"], 2, 3))).get("ok", false), "I play the chime part")
	# Wooly: Sunny started the game; I join it.
	check(await wait_until(func(): return items_of("leaf_pile").size() == 1, 40.0), "Sunny made a leaf pile (Wooly is playing)")
	var sheep := _animal_state("sheep")
	await _go("town", sheep["pos"] + Vector2(-1.5, 0))
	var rs := await ask(Session.play_with_animal("sheep", 0))
	check(rs.get("ok", false) and rs.get("result") == "joined", "I joined Wooly's game instead of taking Wooly away (%s)" % [rs])
	var pile: Dictionary = items_of("leaf_pile")[0]
	await _go("town", Vector2(pile["x"] + 0.8, pile["z"] + 0.8))
	check((await ask(Session.jump_in_leaves(pile["id"]))).get("ok", false), "jumped in the leaves")
	check(await wait_until(func(): return items_of("leaf_pile").size() >= 2, 30.0), "Sunny's blueprint arrived here too")
	check(await wait_until(func(): return cards.filter(func(c): return c["kind"] == "help").size() >= 2, 30.0), "a second help card")
	var help2: Dictionary = cards.filter(func(c): return c["kind"] == "help")[-1]
	check((await ask(Session.answer_invite(help2["from"], "join"))).get("joined", false), "helping again")
	await wait(4.0)


## After a restart: the display mark stayed; helping was temporary; the blueprint's pieces stayed.
func _role_r11_check() -> void:
	var d: Dictionary = Session.model.display_by("town")
	check(d.get("nick", "") == "Sunny", "the square is still on display")
	check(not d.has("helpers"), "helping was not saved: friends are asked again after a restart")
	check(items_of("leaf_pile").size() >= 2, "the blueprint's leaf pile is still there")
	check(items_of("music_box").size() == 1, "the music box is still there")


# ------------------------------------------------------------- r12 wardrobe

const WEAR_DRESS := "paradise_planning_maxi"   # has a frozen seated variant (c016)
const WEAR_HELD := "bat_umbrella"               # held, W9 hold record c018 (GLB bytes of c014)
const WEAR_BAG := "furoshiki_bag"               # held bag, W9 hold record c019 (GLB bytes of c013)


## Sunny: wears a dress-up and an umbrella, sits on a bench, swings, waves, leaves and
## comes back in the same outfit (the game reconnects with the device's current look).
func _role_wear_a(url: String, invite: String) -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var r := await ask(Session.wear("dress", WEAR_DRESS))
	check(r.get("ok", false), "put on the %s" % WEAR_DRESS)
	r = await ask(Session.wear("hand", WEAR_HELD))
	check(r.get("ok", false) and r.get("avatar", {}).get("wear", {}) == {"dress": WEAR_DRESS, "hand": WEAR_HELD}, "and holds the %s (%s)" % [WEAR_HELD, r.get("avatar", {}).get("wear")])
	say("WORN")
	var b_peer: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	check(await wait_until(func(): return Session.players[b_peer]["avatar"].get("wear", {}).get("hand") == WEAR_BAG, 20.0), "sees the friend's %s" % WEAR_BAG)
	var bkid: Node3D = main.world.kids.get(b_peer)
	check(bkid != null and await wait_until(func(): return bkid.find_children(WEAR_BAG + "_ArmR", "MeshInstance3D", true, false).size() == 1, 5.0), "the bag is drawn in the friend's right hand")
	await wait(3.0)
	var bench: Dictionary = items_of("bench")[0]
	check((await ask(Session.sit(bench["id"]))).get("ok", false), "sat on the bench")
	Session.send_state({"space": "town", "x": bench["x"], "z": bench["z"], "ry": 0.0, "anim": "sit"})
	say("SITTING")
	await wait(4.0)
	var swing: Dictionary = items_of("swing")[0]
	check((await ask(Session.sit(swing["id"]))).get("ok", false), "moved to the swing")
	Session.send_state({"space": "town", "x": swing["x"], "z": swing["z"], "ry": 0.0, "anim": "swing"})
	say("SWINGING")
	await wait(4.0)
	Session.stand()
	Session.send_state({"space": "town", "x": swing["x"] + 2.0, "z": swing["z"], "ry": 0.0, "anim": "idle"})
	Session.send_emote("wave")
	say("WAVING")
	await wait(4.0)
	var keep: Dictionary = Session.players[Session.my_id]["avatar"].duplicate(true)
	Session.leave()
	await wait(1.0)
	Session.join(url, keep, invite)
	check(await wait_until(func(): return Session.is_online(), 15.0), "joined again")
	check(Session.players.get(Session.my_id, {}).get("avatar", {}).get("wear") == {"dress": WEAR_DRESS, "hand": WEAR_HELD}, "the outfit came back with me")
	say("BACK")
	await wait(8.0)


## Sky: sees the outfit on the friend's child, the seated variant on the bench and the swing,
## the umbrella in hand while waving; her own gated request is refused; sees the outfit after
## the friend reconnects.
func _role_wear_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var a_peer: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	var r := await ask(Session.wear("hand", "not_an_umbrella"))
	check(not r.get("ok", true) and r.get("error") == "That is not in the wardrobe.", "an unknown item is refused by the server (%s)" % r.get("error"))
	r = await ask(Session.wear("dress", "a_tee"))
	check(not r.get("ok", true) and r.get("error") == "That is not in the wardrobe.", "a top is refused as a dress-up")
	check(Session.players[Session.my_id]["avatar"].get("wear", {}).is_empty(), "my avatar is unchanged after refusals")
	r = await ask(Session.wear("hand", WEAR_BAG))
	check(r.get("ok", false), "I hold the %s (rev5 hold contract)" % WEAR_BAG)
	check(await wait_until(func(): return Session.players[a_peer]["avatar"].get("wear", {}) == {"dress": WEAR_DRESS, "hand": WEAR_HELD}, 20.0), "sees the friend's outfit")
	var kid: Node3D = main.world.kids.get(a_peer)
	var meshes := func(id: String) -> Array:
		return kid.find_children(id + "_*", "MeshInstance3D", true, false) if is_instance_valid(kid) else []
	check(await wait_until(func(): return meshes.call(WEAR_DRESS).size() == 6 and meshes.call(WEAR_HELD).size() == 1, 5.0), "the dress-up (6 parts) and umbrella are drawn on the friend's child")
	var vis := func(name: String) -> bool:
		var m: Array = kid.find_children(name, "MeshInstance3D", true, false)
		return m.size() == 1 and m[0].visible
	check(vis.call(WEAR_DRESS + "_Body") and not vis.call(WEAR_DRESS + "_Body_sit") and vis.call(WEAR_HELD + "_ArmR"), "standing: standing skirt shown, umbrella in hand")
	check(await wait_until(func(): return kid.anim == "sit" and kid.wear_state.get("seated", false), 20.0), "sees the friend sit down")
	check(not vis.call(WEAR_DRESS + "_Body") and vis.call(WEAR_DRESS + "_Body_sit") and vis.call(WEAR_DRESS + "_LegL_sit") and not vis.call(WEAR_HELD + "_ArmR"), "on the bench: seated variant only, umbrella put away")
	check(await wait_until(func(): return kid.anim == "swing", 20.0), "sees the friend swing")
	check(not vis.call(WEAR_DRESS + "_Body") and vis.call(WEAR_DRESS + "_Body_sit") and not vis.call(WEAR_HELD + "_ArmR"), "on the swing: seated variant, umbrella hidden (hands on the ropes)")
	check(await wait_until(func(): return kid.anim == "idle" and kid.emote_kind == "wave", 20.0), "sees the friend stand and wave")
	await wait(0.3)
	check(vis.call(WEAR_DRESS + "_Body") and not vis.call(WEAR_DRESS + "_Body_sit") and vis.call(WEAR_HELD + "_ArmR"), "standing again: standing skirt and umbrella back")
	var arm_r: Node3D = meshes.call(WEAR_HELD)[0].get_parent()
	var arm_l: Node3D = kid._arms[0]
	check(arm_r == kid._arms[1], "the umbrella is mounted on the right arm")
	var worst_r := 0.0
	var most_l := 0.0
	for i in 60:   # about a second of the wave, sampled every frame
		worst_r = maxf(worst_r, maxf(arm_r.rotation.x - Wearables.HOLD_X.y, Wearables.HOLD_X.x - arm_r.rotation.x))
		worst_r = maxf(worst_r, maxf(arm_r.rotation.z - Wearables.HOLD_Z.y, Wearables.HOLD_Z.x - arm_r.rotation.z))
		if arm_l:
			most_l = maxf(most_l, absf(arm_l.rotation.x) + absf(arm_l.rotation.z))
		await get_tree().process_frame
	check(worst_r <= 0.001, "the umbrella arm stays in the hold envelope while waving (worst %.3f rad outside)" % worst_r)
	check(most_l > 0.5, "the wave plays on the other arm (%s, up to %.2f rad)" % [arm_l.name if arm_l else "?", most_l])
	var gone := [false]
	check(await wait_until(func():
		if not Session.players.has(a_peer):
			gone[0] = true
		return gone[0] and Session.players.size() >= 2, 30.0), "the friend left and came back")
	var a2: int = Session.players.keys().filter(func(p): return p != Session.my_id)[0]
	check(Session.players[a2]["avatar"].get("wear") == {"dress": WEAR_DRESS, "hand": WEAR_HELD}, "the friend came back in the same outfit")
	var kid2: Node3D = main.world.kids.get(a2)
	check(kid2 != null and await wait_until(func(): return kid2.find_children(WEAR_DRESS + "_*", "MeshInstance3D", true, false).size() == 6, 5.0), "and it is drawn again (no duplicates)")
	await wait(3.0)


## After a server restart: a saved outfit is accepted when joining; unknown ids and ids in
## the wrong slot in a saved look are dropped by the server.
func _role_wear_check(url: String, avatar: Dictionary, invite: String) -> void:
	Session.leave()
	await wait(1.0)
	var av := avatar.duplicate(true)
	av["wear"] = {"top": "a_tee", "head": "not_an_item", "hand": "a_tee", "shoes": "boots"}
	Session.join(url, av, invite)
	check(await wait_until(func(): return Session.is_online(), 15.0), "joined the restarted server")
	check(Session.players[Session.my_id]["avatar"].get("wear") == {"top": "a_tee", "shoes": "boots"}, "the server kept the valid saved items and dropped the rest (%s)" % [Session.players[Session.my_id]["avatar"].get("wear")])


# ------------------------------------------------------------- r2 wall and ceiling models

func _living() -> String:
	var houses := items_of("cottage")
	houses.sort_custom(func(p, q): return p["id"] < q["id"])
	return TownModel.room_space(houses[0]["id"], 0, 0)


## Sunny: hangs a chandelier and a ceiling fan and puts a poster on the wall of the first house's
## living room; leaves and joins again and finds the friend's changes kept by the server.
func _role_furn_a(url: String, avatar: Dictionary, invite: String) -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var room := _living()
	var r := await ask(Session.place("spiral_crystal_chandelier", room, Vector2(2.0, 1.0), 0, -1))
	check(r.get("ok", false) and is_equal_approx(r.get("item", {}).get("y", 0.0), TownModel.CEILING_Y), "hung a chandelier from the ceiling (%s)" % r.get("error", "ok"))
	r = await ask(Session.place("ceiling_fan_light", room, Vector2(-2.0, -1.0), 0, -1))
	check(r.get("ok", false), "hung a ceiling fan (%s)" % r.get("error", "ok"))
	var poster := {}
	for step in 25:
		r = await ask(Session.place("insect_chart_poster", room, Vector2(-3.0 + step * 0.25, -2.9), 0, -1))
		if r.get("ok", false):
			poster = r["item"]
			break
	check(not poster.is_empty() and poster["z"] == -TownModel.ROOM_HALF.y, "put an insect chart on the back wall")
	r = await ask(Session.place("swag_drapery", room, Vector2(2.4, -1.6), 2, -1))
	check(r.get("ok", false) and r.get("item", {}).get("rot") == 2, "hung a drapery turned a quarter (r15) (%s)" % r.get("error", "ok"))
	say("FURN ready")
	check(await wait_until(func(): return items_in(room, "ceiling_fan_light").is_empty() and items_in(room, "garden_pavilion").size() == 1, 40.0), "sees the friend take the fan down and build a pavilion")
	var moved_x: float = items_in(room, "insect_chart_poster")[0]["x"] if not items_in(room, "insect_chart_poster").is_empty() else 99.0
	check(absf(moved_x - poster.get("x", 0.0)) > 0.1, "sees the poster moved along the wall")
	Session.leave()
	await wait(1.0)
	Session.join(url, avatar, invite)
	check(await wait_until(func(): return Session.is_online(), 15.0), "joined again")
	var ch := items_in(room, "spiral_crystal_chandelier")
	check(ch.size() == 1 and ch[0]["x"] == 2.0 and is_equal_approx(ch[0]["y"], TownModel.CEILING_Y), "after reconnecting: the chandelier still hangs where it was")
	check(items_in(room, "ceiling_fan_light").is_empty() and items_in(room, "insect_chart_poster").size() == 1 and items_in(room, "insect_chart_poster")[0]["x"] == moved_x, "the fan stays gone and the poster stays moved")
	var dr := items_in(room, "swag_drapery")
	check(dr.size() == 1 and dr[0]["rot"] == 5 and is_equal_approx(dr[0]["y"], TownModel.CEILING_Y), "after reconnecting: the drapery keeps the friend's turn (rot %s)" % (dr[0]["rot"] if dr.size() else "?"))
	say("FURN back")
	await wait(4.0)


## Sky: the server refuses a pavilion under the chandelier and moving one there; she moves the
## poster, takes the fan down and builds the pavilion in free space.
func _role_furn_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees the friend arrive")
	var room := _living()
	check(await wait_until(func(): return items_in(room, "insect_chart_poster").size() == 1 and items_in(room, "spiral_crystal_chandelier").size() == 1 and items_in(room, "ceiling_fan_light").size() == 1, 30.0), "sees the chandelier, the fan and the poster")
	var ch: Dictionary = items_in(room, "spiral_crystal_chandelier")[0]
	check(is_equal_approx(ch["y"], TownModel.CEILING_Y) and ch["rot"] == 0, "the chandelier arrives hanging from the ceiling")
	var r := await ask(Session.place("garden_pavilion", room, Vector2(ch["x"], ch["z"]), 0, -1))
	check(not r.get("ok", true) and r.get("error") == TownModel.ERR_HEADROOM, "the server refuses a pavilion under the chandelier (%s)" % r.get("error"))
	r = await ask(Session.place("garden_pavilion", room, Vector2(-1.6, 1.4), 0, -1))
	check(r.get("ok", false), "builds the pavilion where the ceiling is free (%s)" % r.get("error", "ok"))
	var pav: Dictionary = r.get("item", {})
	r = await ask(Session.move(pav.get("id", ""), Vector2(1.0, 0.8), 0))
	check(not r.get("ok", true) and r.get("error") == TownModel.ERR_HEADROOM, "and refuses moving it under the chandelier (%s)" % r.get("error"))
	r = await ask(Session.place("bird_mobile", "town", Vector2(0, 6), 0, -1))
	check(not r.get("ok", true) and r.get("error") == TownModel.ERR_INDOORS, "ceiling items stay indoors")
	var poster: Dictionary = items_in(room, "insect_chart_poster")[0]
	r = await ask(Session.move(poster["id"], Vector2(poster["x"] + 0.5, -2.9), 0))
	check(r.get("ok", false) and r["item"]["z"] == -TownModel.ROOM_HALF.y and r["item"]["rot"] == 0, "moved the poster along the wall (%s)" % r.get("error", "ok"))
	# r16: the server keeps tall standing things out of the space in front of a wall item.
	var px: float = r.get("item", {}).get("x", poster["x"])
	var before_n: int = Session.model.items.size()
	r = await ask(Session.place("floor_lamp", room, Vector2(px, -2.7), 0, -1))
	check(not r.get("ok", true) and r.get("error") == TownModel.ERR_WALL_CLEARANCE and Session.model.items.size() == before_n, "the server refuses a floor lamp in front of the poster, and nothing is added (%s)" % r.get("error"))
	r = await ask(Session.place("floor_lamp", room, Vector2(px, -2.4), 0, -1))
	check(r.get("ok", false), "a floor lamp clear of the poster is fine (%s)" % r.get("error", "ok"))
	check(await wait_until(func(): return items_in(room, "swag_drapery").size() == 1, 10.0) and items_in(room, "swag_drapery")[0]["rot"] == 2, "sees the drapery turned as the friend hung it")
	var dr: Dictionary = items_in(room, "swag_drapery")[0]
	check((await ask(Session.lock(dr["id"]))).get("ok", false), "picked up the drapery to turn it")
	r = await ask(Session.move(dr["id"], Vector2(dr["x"], dr["z"]), 5))
	check(r.get("ok", false) and r["item"]["rot"] == 5 and r["item"]["x"] == dr["x"], "turned it in place to rot 5 (%s)" % r.get("error", "ok"))
	Session.unlock(dr["id"])
	var fan: Dictionary = items_in(room, "ceiling_fan_light")[0]
	r = await ask(Session.remove(fan["id"]))
	check(r.get("ok", false), "took the ceiling fan down")
	var gone := [false]
	check(await wait_until(func():
		if Session.players.size() < 2:
			gone[0] = true
		return gone[0] and Session.players.size() >= 2, 40.0), "the friend left and came back")
	await wait(3.0)


## After a server restart: the hanging and wall items are saved with their heights.
func _role_furn_check() -> void:
	var room := _living()
	var ch := items_in(room, "spiral_crystal_chandelier")
	check(ch.size() == 1 and is_equal_approx(ch[0]["y"], TownModel.CEILING_Y), "the chandelier was saved hanging from the ceiling")
	var po := items_in(room, "insect_chart_poster")
	check(po.size() == 1 and is_equal_approx(po[0]["y"], Catalog.get_def("insect_chart_poster")["mount_height"]) and po[0]["z"] == -TownModel.ROOM_HALF.y, "the poster was saved on the wall at its mount height")
	check(items_in(room, "ceiling_fan_light").is_empty() and items_in(room, "garden_pavilion").size() == 1, "the removed fan stays gone; the pavilion stays")
	var lamps := items_in(room, "floor_lamp")
	check(lamps.size() == 1 and is_equal_approx(lamps[0]["z"], -2.4), "only the floor lamp clear of the poster was saved")
	var dr := items_in(room, "swag_drapery")
	check(dr.size() == 1 and dr[0]["rot"] == 5, "a client joining after the restart sees the drapery's turn (rot %s)" % (dr[0]["rot"] if dr.size() else "?"))


func items_in(space: String, kind: String) -> Array:
	return Session.model.items_in(space).filter(func(i): return i["kind"] == kind)


# ------------------------------------------------------------- operator checks
# Run by scripts/remote_check.py against a deployed town. The marker is one
# flower patch placed outdoors; it is removed again unless kept for a restart check.

func _state_path() -> String:
	return main.args.get("state-file", "")


## Waits for a second friend, places a marker, moves it, then cleans up (or keeps it).
func _role_remote_a(keep: bool) -> void:
	var before := Session.players.size()
	if not keep:
		check(await wait_until(func(): return Session.players.size() > before, 60.0), "a second invited client arrived")
	var spot = Session.model.find_free_spot("flowers", "town", TownModel.TOWN_SPAWN + Vector2(6.0, 6.0))
	check(spot != null, "found a free spot for the marker")
	if spot == null:
		return
	var r := await ask(Session.place("flowers", "town", spot, 0, 3))
	check(r.get("ok", false), "placed the marker")
	if not r.get("ok", false):
		return
	var id: String = r["item"]["id"]
	say("MARK %s" % id)
	if keep:
		var f := FileAccess.open(_state_path(), FileAccess.WRITE)
		check(f != null, "wrote the marker id for the restart check")
		if f:
			f.store_line(id)
		return
	await wait(4.0)
	var spot2 = Session.model.find_free_spot("flowers", "town", spot + Vector2(1.5, 0))
	r = await ask(Session.lock(id))
	r = await ask(Session.move(id, spot2 if spot2 != null else spot, 2))
	check(r.get("ok", false), "moved the marker")
	Session.unlock(id)
	say("MOVED %s" % id)
	await wait(14.0)   # the other client checks the move and reconnects
	r = await ask(Session.remove(id))
	check(r.get("ok", false) and not Session.model.items.has(id), "removed the marker again")
	say("CLEANED %s" % id)


## Sees the other client's marker appear and move, then reconnects and still sees it.
func _role_remote_b(url: String, avatar: Dictionary, invite: String) -> void:
	var known: Array = Session.model.items.keys()
	var mark := [""]
	check(await wait_until(func():
		for id in Session.model.items:
			if not known.has(id) and Session.model.items[id]["kind"] == "flowers":
				mark[0] = id
				return true
		return false, 60.0), "saw the other client's marker appear")
	if mark[0] == "":
		return
	say("SAW %s" % mark[0])
	var first: Dictionary = Session.model.items[mark[0]].duplicate()
	check(await wait_until(func():
		var it: Dictionary = Session.model.items.get(mark[0], {})
		return not it.is_empty() and (it["x"] != first["x"] or it["rot"] != first["rot"]), 30.0), "saw the marker move")
	say("SAW_MOVE %s" % mark[0])
	Session.leave()
	await wait(1.0)
	Session.join(url, avatar, invite)
	check(await wait_until(func(): return Session.is_online(), 20.0), "reconnected with the same invite")
	check(Session.model.items.has(mark[0]), "the marker is still there after reconnecting")
	say("RECONNECT_SAW %s" % mark[0])
	await wait(2.0)


## After the operator restarted the service: the kept marker survived; remove it.
func _role_remote_verify() -> void:
	var id := FileAccess.get_file_as_string(_state_path()).strip_edges()
	check(id != "", "read the marker id")
	check(Session.model.items.has(id), "the marker survived the server restart")
	say("PERSISTED %s" % id)
	if Session.model.items.has(id):
		var r := await ask(Session.remove(id))
		check(r.get("ok", false), "removed the marker (cleanup)")


## With the right invite: the town arrives, and refused visitors never take a slot.
func _role_invite_ok() -> void:
	say("INVITE in")
	# Watch the whole time (not one fixed moment: the other bots start at their own
	# pace): the invited friend must arrive, and nobody without the invite ever does.
	var seen := {}
	var most := [0]
	var watch := func():
		most[0] = maxi(most[0], Session.players.size())
		for p in Session.players.values():
			seen[p["avatar"]["nick"]] = true
	var arrived := await wait_until(func():
		watch.call()
		return Session.players.size() == 2, 45.0)
	check(arrived, "the invited friend arrived")
	var t := 0.0
	while t < 12.0:
		watch.call()
		await wait(0.25)
		t += 0.25
	check(Session.is_online() and most[0] == 2 and seen.keys().all(func(n): return n in ["Sunny", "Leaf"]),
		"only invited friends were ever in town (%s; at most %d)" % [", ".join(seen.keys()), most[0]])


## Leaves and joins again with the same invite.
func _role_invite_reconnect(url: String, avatar: Dictionary, invite: String) -> void:
	await wait(2.0)
	Session.leave()
	await wait(1.0)
	check(not Session.is_online(), "left the town")
	Session.join(url, avatar, invite)
	check(await wait_until(func(): return Session.is_online(), 15.0), "joined again with the same invite")
	check(Session.model.items.size() > 20, "received the town again (%d items)" % Session.model.items.size())
	await wait(8.0)


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


# ------------------------------------------------------------- r17: two-seat benches (net_test.py --seats)

func _peer_named(nick: String) -> int:
	for p in Session.players:
		if Session.nick_of(p) == nick:
			return p
	return 0


func _bench() -> Dictionary:
	var b := items_in(_living(), "bamboo_bench")
	return b[0] if b.size() == 1 else {}


## Holders of the bench as {seat: nick}, as this client sees them.
func _bench_nicks() -> Dictionary:
	var out := {}
	var h: Dictionary = Session.seat_holders(_bench().get("id", ""))
	for s in h:
		out[s] = Session.nick_of(h[s])
	return out


## This client's view of a seated friend: their child is drawn sitting on that seat of the bench.
func _drawn_on_seat(nick: String, seat: int) -> bool:
	var kid: Node3D = main.world.kids.get(_peer_named(nick))
	var node: Node3D = main.world.item_nodes.get(_bench().get("id", ""))
	if kid == null or node == null:
		return false
	var mk: Node3D = Props.seat_marker(node, seat)
	return kid.anim == "sit" and mk != null and kid.global_transform.origin.distance_to(main.world.seat_transform(mk).origin) < 0.01


## Sunny builds a bamboo bench in the living room and sits down at the same moment as Sky; later she
## stands so Peach can sit, and watches Sky's seat free when Sky disconnects.
func _role_seat_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 3), "sees both friends arrive")
	main.controller.go_to_room(_living())
	var r := await ask(Session.place("bamboo_bench", _living(), Vector2(1.0, 1.0), 0, -1))
	check(r.get("ok", false), "built a bamboo bench (%s)" % r.get("error", "ok"))
	var id: String = r.get("item", {}).get("id", "")
	await wait(0.5)
	r = await ask(Session.sit(id))
	check(r.get("ok", false), "sat down (%s)" % r.get("error", "ok"))
	var mine: int = r.get("seat", -1)
	check(await wait_until(func(): return Session.seat_holders(id).size() == 2, 10.0), "both seats are taken")
	check(_bench_nicks().values().has("Sunny") and _bench_nicks().values().has("Sky") and _bench_nicks().get(mine) == "Sunny", "Sky and I have different seats (%s)" % _bench_nicks())
	check(await wait_until(func(): return _drawn_on_seat("Sky", 1 - mine) and _drawn_on_seat("Sunny", mine), 10.0), "both children are drawn sitting on their own seats")
	r = await ask(Session.remove(id))
	check(r.get("error", "") == "Someone is playing on it.", "the bench cannot be put away while children sit on it (%s)" % r.get("error"))
	say("SEATS both seated %s" % _bench_nicks())
	await wait(3.0)   # Peach is refused meanwhile
	main.controller.stand_up()
	check(await wait_until(func(): return Session.seat_of(Session.my_id).is_empty(), 10.0), "I stood up")
	check(await wait_until(func(): return _bench_nicks() == {mine: "Peach", 1 - mine: "Sky"}, 20.0), "Peach takes my seat; Sky keeps hers (%s)" % _bench_nicks())
	check(await wait_until(func(): return _bench_nicks() == {mine: "Peach"}, 40.0), "Sky's seat frees when Sky disconnects (%s)" % _bench_nicks())
	check(await wait_until(func(): return Session.seat_holders(id).is_empty(), 30.0), "the bench is free after Peach stands")
	say("SEATS done")
	await wait(2.0)


## Sky sits at the same moment as Sunny, then disconnects while seated.
func _role_seat_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 3), "sees both friends arrive")
	main.controller.go_to_room(_living())
	check(await wait_until(func(): return not _bench().is_empty(), 20.0), "sees the bench")
	var id: String = _bench()["id"]
	var r := await ask(Session.sit(id))
	check(r.get("ok", false), "sat down at the same time as Sunny (%s)" % r.get("error", "ok"))
	check(await wait_until(func(): return Session.seat_holders(id).size() == 2, 10.0) and _bench_nicks().size() == 2 and _bench_nicks().values().has("Sunny"), "sees Sunny on the other seat (%s)" % _bench_nicks())
	check(await wait_until(func(): return _drawn_on_seat("Sunny", 1 - int(r.get("seat", 0))), 10.0), "Sunny's child is drawn sitting next to mine")
	check(await wait_until(func(): return _bench_nicks().values().has("Peach"), 40.0), "sees Peach take Sunny's seat")
	await wait(1.0)
	say("SEATS leaving while seated")
	Session.leave()   # the disconnect frees my seat on the server


## Peach finds the bench full, is told so, and sits as soon as Sunny gets up.
func _role_seat_c() -> void:
	check(await wait_until(func(): return Session.players.size() >= 3), "sees both friends arrive")
	main.controller.go_to_room(_living())
	check(await wait_until(func(): return Session.seat_holders(_bench().get("id", "")).size() == 2, 30.0), "sees both seats taken")
	var id: String = _bench()["id"]
	var r := await ask(Session.sit(id))
	check(not r.get("ok", true) and r.get("error") == "Someone is playing on it.", "a third child is told the bench is full (%s)" % r.get("error"))
	var toasts := []
	main.controller.toast.connect(func(t): toasts.append(t))
	main.controller.do_context({"type": "sit", "id": id})
	check(await wait_until(func(): return toasts.has("Someone is playing on it."), 10.0), "tapping Sit on the full bench shows why")
	check(await wait_until(func(): return Session.seat_holders(id).size() == 1, 30.0), "sees Sunny get up")
	r = await ask(Session.sit(id))
	check(r.get("ok", false) and _bench_nicks().get(r.get("seat", -1)) == "Peach", "sat on the freed seat (%s)" % r.get("error", "ok"))
	check(await wait_until(func(): return _bench_nicks().size() == 1, 40.0), "sees Sky's seat free when she disconnects")
	await wait(1.0)
	main.controller.stand_up()
	check(await wait_until(func(): return Session.seat_holders(id).is_empty(), 10.0), "stood up: the bench is free")
	await wait(3.0)


## After a server restart the bench is still there and every seat is free (seats are never saved).
func _role_seat_check() -> void:
	check(await wait_until(func(): return not _bench().is_empty(), 20.0), "the bamboo bench is still in the living room after the restart")
	check(Session.seats.is_empty(), "nobody is sitting: seats are not part of the save")
	var r := await ask(Session.sit(_bench()["id"]))
	check(r.get("ok", false) and r.get("seat") == 0, "the first child to sit gets seat 0")
	await wait(1.0)


# ------------------------------------------------------------- r18: animals visit houses (net_test.py --visits)

func _house() -> Dictionary:
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	return houses[0]


func _animal_pos(kind: String) -> Vector2:
	for st in Animals.states:
		if st["kind"] == kind:
			return st["pos"]
	return Vector2.INF


## This device draws the visitor `kind` in its room, beside child `peer`.
func _guest_beside(kind: String, peer: int) -> bool:
	var n: Node3D = main.world.guest_layer.guests.get(kind)
	var kid: Node3D = main.world.kids.get(peer)
	return n != null and kid != null and n.visible and Vector2(n.position.x, n.position.z).distance_to(Vector2(kid.position.x, kid.position.z)) < 2.5


func _stand(p: Vector2) -> void:
	main.controller.pos = p
	main.controller._place_kid()
	main.controller._send_state()
	await wait(0.6)


## Sunny invites Pip, goes home with it, dances, climbs the stairs and disconnects inside.
func _role_visit_a() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees Sky arrive")
	check(await wait_until(func(): return _animal_pos("pig") != Vector2.INF, 10.0), "sees Pip")
	await _stand(_animal_pos("pig") + Vector2(1.5, 0))
	var r := await ask(Session.visit_animal("elephant", true))
	check(r.get("error", "") == "Tumble is too big for the door, but loves to play outside.", "the server keeps Tumble outside (%s)" % r.get("error"))
	r = await ask(Session.visit_animal("pig", true))
	check(r.get("ok", false), "Pip comes home with me (%s)" % r.get("error", "ok"))
	check(await wait_until(func(): return Animals.guests.get("pig", 0) == Session.my_id, 10.0), "the visit reaches me")
	await wait(2.0)
	check(_animal_pos("pig").distance_to(main.controller.pos) < 3.0, "Pip follows me outdoors (%.1f m)" % _animal_pos("pig").distance_to(main.controller.pos))
	main.controller.go_to_room(TownModel.room_space(_house()["id"], 0, 0))
	check(await wait_until(func(): return _guest_beside("pig", Session.my_id), 10.0), "Pip is in the living room with me")
	say("VISIT inside")
	check(await wait_until(func(): return Session.players.size() >= 3, 40.0), "sees Peach join late")
	await wait(2.0)
	Session.send_emote("dance")
	say("VISIT danced")
	await wait(3.0)
	main.controller.go_to_room(TownModel.room_space(_house()["id"], 1, 0))
	check(await wait_until(func(): return _guest_beside("pig", Session.my_id), 10.0), "Pip comes up the stairs with me")
	say("VISIT upstairs")
	await wait(4.0)
	say("VISIT leaving inside")
	Session.leave()   # the disconnect ends the visit on the server


## Sky waits in the living room and sees Pip come in beside Sunny, answer her dance, and leave with her.
func _role_visit_b() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2), "sees Sunny arrive")
	main.controller.go_to_room(TownModel.room_space(_house()["id"], 0, 0))
	var a := _peer_named("Sunny")
	check(await wait_until(func(): return Animals.guests.get("pig", 0) == a, 30.0), "learns that Pip visits Sunny")
	check(await wait_until(func(): return _guest_beside("pig", a), 20.0), "sees Pip come into the living room beside Sunny")
	var pig: Node3D = main.world.guest_layer.guests.get("pig")
	check(await wait_until(func(): return pig != null and is_instance_valid(pig) and pig.action == "dance", 30.0), "sees Pip answer Sunny's dance")
	check(await wait_until(func(): return not main.world.guest_layer.guests.has("pig"), 20.0), "Pip goes upstairs with Sunny (not in my room any more)")
	main.controller.go_to_room(TownModel.room_space(_house()["id"], 1, 0))
	check(await wait_until(func(): return _guest_beside("pig", a), 10.0), "upstairs, Pip is beside Sunny again")
	check(await wait_until(func(): return not Animals.guests.has("pig"), 40.0), "when Sunny disconnects inside, the visit ends")
	check(await wait_until(func(): return not main.world.guest_layer.guests.has("pig"), 5.0), "and Pip is no longer drawn inside")
	await wait(2.0)


## Peach joins late, outdoors: she learns about the visit, does not see Pip in town meanwhile, and sees
## it back at the front door when Sunny disconnects inside.
func _role_visit_c() -> void:
	check(await wait_until(func(): return Session.players.size() >= 2 and Animals.guests.has("pig"), 60.0), "a late joiner learns that Pip is visiting")
	await wait(1.0)
	check(not main.world.animals.get("pig").visible, "Pip is not drawn outdoors while inside")
	var door := TownModel.door_point(_house())
	check(await wait_until(func(): return not Animals.guests.has("pig"), 60.0), "sees the visit end")
	check(await wait_until(func(): return _animal_pos("pig").distance_to(door) < 2.5 and main.world.animals.get("pig").visible, 5.0),
		"Pip is back outdoors by the house's front door (%.1f m)" % _animal_pos("pig").distance_to(door))
	await wait(2.0)


## After a server restart nobody is visiting (visits are never saved) and Pip is outdoors.
func _role_visit_check() -> void:
	check(await wait_until(func(): return _animal_pos("pig") != Vector2.INF, 15.0), "the animals are out after the restart")
	check(Animals.guests.is_empty(), "nobody is visiting after the restart")
	check(main.world.animals.get("pig").visible, "Pip is drawn outdoors")
	await wait(1.0)


# ------------------------------------------------------------- r19-connect: joining a big town (net_test.py --connect)

const TownFixture := preload("res://tests/town_fixture.gd")


## connect_big: a town above 64 KiB arrives whole (every item, compared by digest with the fixture).
## connect_refused: the server cannot send the town (old 64 KiB buffers, or above its limit): the child is
##   told so and is not left on Connecting.
## connect_stuck: this client keeps Godot's 64 KiB inbound buffer (as shipped in r13b): it cannot receive
##   the town and gives up after Session.WELCOME_TIMEOUT instead of waiting forever.
func _role_connect(url: String, avatar: Dictionary, invite: String, rejected: Array) -> void:
	Session.net_buffer_override = int(main.args.get("net-buffer", "0"))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main.args.get("fixture", "")))
	var fm = TownModel.new()
	fm.from_dict(fixture)
	var want_digest := TownFixture.items_digest(fm.items)
	say("FIXTURE %d items" % fm.items.size())
	var t0 := Time.get_ticks_msec()
	Session.join(url, avatar, invite)
	match role:
		"connect_big":
			check(await wait_until(func(): return Session.is_online() or Session.state == "failed", 15.0) and Session.is_online(), "joined a town above 64 KiB (%d ms)" % (Time.get_ticks_msec() - t0))
			check(Session.model.items.size() == fm.items.size(), "received every item (%d of %d)" % [Session.model.items.size(), fm.items.size()])
			check(TownFixture.items_digest(Session.model.items) == want_digest, "every item arrived unchanged (digest)")
			var r := await ask(Session.place("flowers", "town", Session.model.find_free_spot("flowers", "town", Vector2(0, 6)), 0, -1))
			check(r.get("ok", false), "and can play: placed flowers (%s)" % r.get("error", "ok"))
		"connect_refused":
			check(await wait_until(func(): return rejected[0] != "" or Session.is_online(), 15.0), "the server answered within 15 s")
			check(rejected[0] == Session.ERR_TOWN_TOO_BIG and Session.state == "failed", "told that the town is too big to join (%s, %s)" % [rejected[0], Session.state])
			check(Session.model.items.is_empty() and not Session.is_online(), "no partial town was received")
		"connect_stuck", "connect_silent":
			# connect_stuck: the town is too big for this client's 64 KiB buffer, so the connection closes.
			# connect_silent: the server accepts the connection but never sends the town (a stub).
			# Either way the client must end in failed (the menu then says it could not reach the town),
			# within the welcome timeout, never staying on Connecting.
			check(await wait_until(func(): return Session.state != "connecting", Session.WELCOME_TIMEOUT + 8.0), "the client stops waiting (%s after %.1f s)" % [Session.state, (Time.get_ticks_msec() - t0) / 1000.0])
			check(Session.state == "failed" and Session.model.items.is_empty(), "it ends in failed with no partial town, so the menu can say so")
			var secs := (Time.get_ticks_msec() - t0) / 1000.0
			if role == "connect_silent":
				check(secs >= Session.WELCOME_TIMEOUT - 1.0 and secs <= Session.WELCOME_TIMEOUT + 5.0, "it gave up at the welcome timeout (%.1f s, timeout %.0f s)" % [secs, Session.WELCOME_TIMEOUT])
			else:
				check(secs <= Session.WELCOME_TIMEOUT + 5.0, "it failed within the welcome timeout (%.1f s)" % secs)

