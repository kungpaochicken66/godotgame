## r17 two-seat benches through the real UI (design/two-seat-benches.md). The local child taps the
## bamboo bench and sits; a friend sits on the other seat; a third child is refused; Get up puts the
## child in front of their own seat; tapping Sit on a full bench says why; then a turned sofa and a turned
## town bench with friends in different outfits. Friends are stand-ins whose requests go through the
## authority's own handler (the network test net_test.py --seats covers real clients). At most 8 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/bench_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja --timeout=400
## Logic only, no renderer (EC2 smoke): add --headless before --path, --no-shots and --window=2208x1024
## after --.
extends "res://tests/play_tour.gd"

const Avatar := preload("res://scripts/core/avatar.gd")
const Props := preload("res://scripts/art/props.gd")
const World := preload("res://scripts/world/town_world.gd")

const SKY := 4242     # stand-in friends (peer ids the solo authority does not use)
const PEACH := 4343
const FULL := "Someone is playing on it."

## Each case sets this as its last line; the runner checks it, so a case cut short (a script error or a
## missing precondition) fails the tour instead of passing silently (r16c lesson).
var _case_done := false
var _town_bench_id := ""


func shot(name: String) -> void:
	if _n >= 8 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/bench_%s_%02d_%s.png" % [shots, tag, _n, name])


func case_ended(what: String) -> void:
	check(_case_done, "the %s case ran to its end" % what)
	_case_done = false


## A stand-in friend in the given outfit, standing at a point of a space.
func add_friend(peer: int, preset: int, wear: Dictionary, space: String, at: Vector2) -> void:
	var av: Dictionary = Avatar.PRESETS[preset].duplicate(true)
	av["wear"] = wear
	Session.players[peer] = {"avatar": Avatar.sanitize(av), "state": {"space": space, "x": at.x, "z": at.y, "ry": 0.0, "anim": "idle"}, "pid": "friend%d" % peer}
	Session.players_changed.emit()


func friend_sits(peer: int, id: String) -> void:
	Session._srv_sit(peer, 0, id)   # the request a friend's client sends, handled by the authority
	await frames(3)


## This client draws `peer`'s child sitting on seat `seat` of item `id`.
func drawn_on(peer: int, id: String, seat: int) -> bool:
	var kid: Node3D = main.world.kids.get(peer)
	var node: Node3D = main.world.item_nodes.get(id)
	var mk: Node3D = Props.seat_marker(node, seat) if node else null
	return kid != null and mk != null and kid.visible and kid.anim in ["sit", "ride"] \
		and kid.global_transform.origin.distance_to(World.seat_transform(mk).origin) < 0.01


func place(kind: String, space: String, at: Vector2, rot: int) -> String:
	var r: Dictionary = await ask_result(Session.place(kind, space, at, rot, -1))
	check(r.get("ok", false), "set up: a %s at %s turned %d (%s)" % [kind, at, rot, r.get("error", "ok")])
	return r.get("item", {}).get("id", "")


func ask_result(req: int) -> Dictionary:
	var out := [{}]
	main.controller._ask(req, func(r): out[0] = r)
	await until(func(): return not out[0].is_empty(), 5.0)
	return out[0]


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("BENCH %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://bench_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	var room := TownModel.room_space(houses[0]["id"], 0, 0)
	_case_done = false
	await _bamboo(hud, c, room)
	case_ended("bamboo bench")
	await _sofa_turned(c, room)
	case_ended("turned sofa")
	await _town_bench(hud, c)
	case_ended("turned town bench")
	for loc in locales.slice(1):
		await _full_in(loc, hud, c)
		case_ended("[%s] full bench" % loc)
	print("BENCH %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## The bamboo bench: tap it to sit, a friend joins, a third child is refused, Get up, the full bench.
func _bamboo(hud: Control, c: Node, room: String) -> void:
	var id := await place("bamboo_bench", room, Vector2(1.0, 0.0), 0)
	if id == "":
		return
	c.go_to_room(room)
	await wait(1.0)
	c.pos = Vector2(1.0, 1.4)
	c._place_kid()
	main.rig.snap()
	await settle_camera()
	await tap_item(id)
	check(await until(func(): return Session.seat_of(Session.my_id) == [id, 0], 8.0), "tapping the bench walks over and sits on the first seat (%s)" % [Session.seat_of(Session.my_id)])
	check(await until(func(): return drawn_on(Session.my_id, id, 0), 4.0), "my child is drawn on seat 0")
	add_friend(SKY, 1, {"dress": "bekasab_robe", "hand": "apple_umbrella"}, room, Vector2(1.6, 1.4))
	await friend_sits(SKY, id)
	check(Session.seat_holders(id) == {0: Session.my_id, 1: SKY}, "Sky sits on the other seat (%s)" % Session.seat_holders(id))
	check(await until(func(): return drawn_on(SKY, id, 1), 4.0), "Sky's child is drawn on seat 1, next to mine")
	await settle_camera()
	await shot("bamboo_two_seated")
	add_friend(PEACH, 2, {"dress": "cozy_paradise_planning_coat", "head": "alpinist_hat", "bag": "basket_pack"}, room, Vector2(0.2, 1.5))
	await friend_sits(PEACH, id)
	check(Session.seat_holders(id) == {0: Session.my_id, 1: SKY}, "a third child is refused: the bench stays as it was")
	# Get up: the button the game offers while seated.
	check(c._ctx.get("type", "") == "stand", "while seated the action is Get up")
	check(await use_context("stand"), "tapped Get up")
	check(await until(func(): return Session.seat_of(Session.my_id).is_empty(), 4.0), "I stood up")
	var right := Vector2(1, 0)   # the bench faces +z unturned, so seat 0 is on the -x side
	check(c.pos.y > 0.3 and (c.pos - Vector2(1.0, 0.0)).dot(right) < -0.25, "I stand in front of my own seat, not in the middle (%s)" % c.pos)
	check(Session.seat_holders(id) == {1: SKY}, "Sky is still seated")
	await friend_sits(PEACH, id)
	check(Session.seat_holders(id) == {0: PEACH, 1: SKY}, "Peach takes the freed seat")
	check(await until(func(): return drawn_on(PEACH, id, 0), 4.0), "Peach (coat, alpinist hat, backpack) is drawn on seat 0")
	# The bench is full: the Sit action says why instead of doing nothing.
	await _tap_full_bench(hud, c, id)
	await settle_camera()
	await shot("bamboo_full_message")
	Session._free_seats_of(SKY)
	Session._free_seats_of(PEACH)
	await frames(5)
	check(not drawn_on(SKY, id, 1) and main.world.kids[SKY].anim == "idle", "friends stand up when their seats free")
	_case_done = true


func _tap_full_bench(hud: Control, c: Node, id: String) -> void:
	var item: Dictionary = Session.model.items[id]
	c.pos = Vector2(item["x"], item["z"]) + TownModel.facing(item["rot"]) * 0.95
	c._place_kid()
	await frames(5)
	check(await until(func(): return c._ctx.get("type", "") == "sit" and c._ctx.get("id", "") == id, 4.0), "next to the full bench the action is still %s" % tr("Sit"))
	check(await use_context("sit"), "tapped %s on the full bench" % tr("Sit"))
	check(await until(func(): return hud._toast_label.text == FULL and hud._toast.modulate.a > 0.5, 4.0), "the message says the bench is taken (%s)" % tr(FULL))
	check(Session.seat_of(Session.my_id).is_empty(), "and I am not seated")


## A sofa turned 270 degrees with two friends in different outfits; nobody is pulled off their seat.
func _sofa_turned(c: Node, room: String) -> void:
	var id := await place("sofa", room, Vector2(-1.2, 1.4), 6)
	if id == "":
		return
	add_friend(SKY, 1, {"dress": "bekasab_robe", "hand": "apple_umbrella"}, room, Vector2(-0.4, 1.4))
	await friend_sits(SKY, id)
	await friend_sits(PEACH, id)
	check(Session.seat_holders(id) == {0: SKY, 1: PEACH}, "both friends sit on the turned sofa (%s)" % Session.seat_holders(id))
	check(await until(func(): return drawn_on(SKY, id, 0) and drawn_on(PEACH, id, 1), 4.0), "both are drawn on their own seats of the turned sofa")
	c.pos = Vector2(0.0, 1.4)
	c._place_kid()
	main.rig.snap()
	await settle_camera()
	await wait(0.5)
	check(drawn_on(SKY, id, 0) and drawn_on(PEACH, id, 1), "seated friends stay on their seats while time passes")
	await shot("sofa_turned_friends")
	Session._free_seats_of(SKY)
	Session._free_seats_of(PEACH)
	await frames(3)
	_case_done = true


## The town bench turned 135 degrees: I sit by tapping, Peach in the coat and hat sits beside me.
func _town_bench(hud: Control, c: Node) -> void:
	c.exit_house()
	await wait(1.0)
	var at := Vector2(-4.0, 9.0)
	var id := await place("bench", "town", at, 3)
	_town_bench_id = id
	if id == "":
		return
	var p: Dictionary = Session.players[PEACH]
	p["state"] = {"space": "town", "x": at.x + 1.0, "z": at.y + 1.0, "ry": 0.0, "anim": "idle"}
	Session.players_changed.emit()
	main.world._update_kid_visibility(PEACH)
	c.pos = at + TownModel.facing(3) * 1.6
	c._place_kid()
	main.rig.snap()
	await settle_camera()
	await tap_item(id)
	check(await until(func(): return Session.seat_of(Session.my_id) == [id, 0], 8.0), "tapping the turned town bench seats me (%s)" % [Session.seat_of(Session.my_id)])
	await friend_sits(PEACH, id)
	check(Session.seat_holders(id) == {0: Session.my_id, 1: PEACH}, "Peach sits beside me")
	check(await until(func(): return drawn_on(Session.my_id, id, 0) and drawn_on(PEACH, id, 1), 4.0), "both are drawn on their own seats of the turned bench")
	await settle_camera()
	await shot("town_bench_turned")
	check(await use_context("stand"), "tapped Get up")
	check(await until(func(): return Session.seat_of(Session.my_id).is_empty(), 4.0), "I stood up from the town bench")
	Session._free_seats_of(PEACH)
	await frames(3)
	_case_done = true


## The full-bench message in another language.
func _full_in(loc: String, hud: Control, c: Node) -> void:
	I18n.set_locale(loc)
	await frames(3)
	var id := _town_bench_id
	if not Session.model.items.has(id):
		check(false, "[%s] the turned town bench is there" % loc)
		return
	await friend_sits(SKY, id)
	Session.players[SKY]["state"]["space"] = "town"
	main.world._update_kid_visibility(SKY)
	await friend_sits(PEACH, id)
	check(Session.seat_holders(id).size() == 2, "[%s] both seats of the town bench are taken" % loc)
	await _tap_full_bench(hud, c, id)
	check(tr(FULL) != FULL or loc == "en", "[%s] the message is translated" % loc)
	await settle_camera()
	await shot("%s_full_message" % loc)
	Session._free_seats_of(SKY)
	Session._free_seats_of(PEACH)
	await frames(3)
	_case_done = true
