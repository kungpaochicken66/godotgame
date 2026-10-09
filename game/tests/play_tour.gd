## Focused check of the play ideas for ages 8-12 (design/playability-8-12.md) through
## the real UI: Biscuit's card and fetch by tapping the ground, the Snack Stand
## toolkit tab and the snack card, sharing, the snowman's face, a rain-puddle
## splash, and "On display" with the ask-first dialog. At most 10 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/play_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path and --no-shots after --.
extends "res://tests/pets_tour.gd"

const PlayRules := preload("res://scripts/core/play_rules.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")


func shot(name: String) -> void:
	if _n >= 10 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/play_%s_%02d_%s.png" % [shots, tag, _n, name])


## Swipes a sideways row (tabs or cards) until the button is on screen, like a finger would.
func scrolled_to(b: Control) -> Control:
	if b == null:
		return null
	var p := b.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p:
		(p as ScrollContainer).ensure_control_visible(b)
		await frames(3)
	return b


func dog_node() -> Node3D:
	return main.world.animals.get("dog")


func dog_state() -> Dictionary:
	for st in Animals.states:
		if st["kind"] == "dog":
			return st
	return {}


## Places a new thing through the toy box: its tab, its card, then Place here.
func place_from_toybox(tab: String, kind: String) -> String:
	var hud: Control = main.hud
	var c: Node = main.controller
	if c.mode != "decorate":
		await press(hud._decorate_btn)
	await press(await scrolled_to(find_button(hud._tabs, "tab", tab)))
	await frames(3)
	if RoomThemes.TOOLKIT_IDEAS.has(tab):
		check(hud._hint.text == RoomThemes.TOOLKIT_IDEAS[tab], "the %s tab shows its idea line (%s)" % [tab, hud._hint.text])
	var card: Button = find_button(hud._cards, "kind", kind)
	check(card != null, "the %s tab shows the %s card" % [tab, kind])
	if card == null:
		return ""
	var before: Array = Session.model.items.keys()
	await press(await scrolled_to(card))
	await frames(3)
	# The ghost starts "in front of" the child; if it shows red there, move it the way a
	# player does (the hint says "Drag it"): a real drag onto free ground in view.
	for attempt in 3:
		if c.g_error == "":
			break
		var spot = Session.model.find_free_spot(kind, c.space, c.pos + Vector2(-1.5 + attempt * 1.5, -2.0))
		if spot == null:
			break
		await settle_camera()
		await drag_world(c.ghost.global_position + Vector3(0, 0.4, 0), Vector3(spot.x, 0, spot.y), "the %s ghost" % kind)
		await frames(3)
		print("DIAG ghost for %s: dragged toward %s, now at %s (%s)" % [kind, spot, c.g_pos, c.g_error if c.g_error != "" else "fits"])
	check(c.g_error == "", "the %s can go where it is shown (%s)" % [kind, c.g_error])
	await press(hud._place_btn)
	await until(func(): return Session.model.items.size() > before.size(), 5.0)
	var made: Array = Session.model.items.keys().filter(func(k): return not before.has(k) and Session.model.items[k]["kind"] == kind)
	check(not made.is_empty(), "placed a %s from the %s tab" % [kind, tab])
	await press(hud._decorate_btn)   # Done
	return made[0] if not made.is_empty() else ""


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "300"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "300"))
		print("PLAY %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://play_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	await _fetch(hud, c)
	await _snacks(hud, c)
	await _snowman_and_puddle(hud, c)
	await _display(hud, c)
	for loc in locales:
		await _cards_in(loc, hud, c, area)
	print("PLAY %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## F03: tap Biscuit, Play fetch, tap the ground; Biscuit runs, carries it back.
func _fetch(hud: Control, c: Node) -> void:
	check(await until(func(): return dog_node() != null, 10.0), "Biscuit is in town")
	# Stand near Biscuit (the authority checks the distance) and tap Biscuit.
	var dp: Vector2 = dog_state()["pos"]
	c.pos = dp + Vector2(2.0, 0.0)
	c._place_kid()
	await wait(1.0)
	await settle_camera()
	var d: Node3D = dog_node()
	await tap_at_world(d.global_position + Vector3(0, 0.4, 0), "Biscuit")
	check(await until(func(): return hud._overlay.get_node_or_null("Fetch") != null, 5.0), "tapping Biscuit opens the fetch card")
	await frames(4)
	await shot("fetch_card")
	await press(find_button(hud._overlay, "dialog_button", "Play fetch"))
	check(c.fetch_mode and await until(func(): return c._ctx.get("type") == "stop_fetch", 3.0), "fetch mode is on and offers Stop fetch")
	# Throw away from the camera (up the screen): +z is toward the camera, and a throw
	# 4.5 m that way was aimed below the bottom edge of an iPhone screen (found in r11d).
	var target: Vector2 = c.pos + Vector2(0, -4.5)
	await settle_camera()
	await walk_to(target)   # in fetch mode a ground tap throws instead of walking
	var seen := {"run": false, "carry": false}
	check(await until(func():
		var a: String = dog_state().get("action", "")
		if a in seen:
			seen[a] = true
		return seen["carry"], 12.0), "Biscuit runs for the ball and picks it up (%s)" % seen)
	await shot("fetch_carry")
	check(await until(func(): return dog_state().get("action") != "carry", 12.0), "Biscuit gives the ball back")
	check(dog_state().get("pos", Vector2(99, 99)).distance_to(c.pos) < 2.5, "next to the thrower")
	check(c.pos.distance_to(target) > 2.0, "the child stayed put while throwing")
	await press(hud._context_btn)   # Stop fetch
	check(not c.fetch_mode, "Stop fetch ends the game")


## F01 + F09: the Snack Stand tab with its idea line; the snack card; Share.
func _snacks(hud: Control, c: Node) -> void:
	c.pos = Vector2(8, -9)
	c._place_kid()
	await wait(0.5)
	var tray := await place_from_toybox("Snack Stand", "snack_tray")
	if tray == "":
		return
	await wait(0.5)
	await tap_item(tray)
	check(await until(func(): return hud._overlay.get_node_or_null("Snacks") != null, 10.0), "tapping the tray opens the snack card")
	await frames(4)
	await shot("snack_card")
	var before: int = Session.model.items.size()
	await press(find_button(hud._overlay, "snack", ["snack_sandwich", "berry"]))
	check(await until(func(): return Session.model.items.size() == before + 1, 5.0), "a berry sandwich is made")
	var snack: Array = Session.model.items.values().filter(func(i): return i["kind"] == "snack_sandwich")
	if snack.is_empty():
		return
	check(snack[0]["color"] == PlayRules.TOPPINGS["berry"], "in the berry color")
	await wait(0.6)
	await shot("snack_made")
	await tap_item(snack[0]["id"])
	check(await until(func(): return not Session.model.items.has(snack[0]["id"]), 10.0), "tapping the snack shares it")


## F04: the snowman's face, and a splash when walking into a rain puddle.
func _snowman_and_puddle(hud: Control, c: Node) -> void:
	c.pos = Vector2(-8, -12)
	c._place_kid()
	await wait(0.5)
	var sm := await place_from_toybox("Rainy Day", "snowman")
	if sm != "":
		await wait(0.5)
		await tap_item(sm)
		check(await until(func(): return Session.model.items[sm].get("variant") == 1, 10.0), "tapping the snowman changes its face")
		await wait(0.5)
		await shot("snowman")
	for i in 4:
		if Session.model.weather == "rain":
			break
		Session.change_weather()
		await wait(0.5)
	check(Session.model.weather == "rain", "it rains")
	var pd: Vector2 = TownModel.PUDDLES[1]
	c.pos = pd + Vector2(3.0, 0)
	c._place_kid()
	await wait(0.6)
	await walk_to(pd)
	check(await until(func(): return main.world.activity._in_puddle.get(Session.my_id, -1) == 1, 8.0), "walking into the puddle splashes")
	await shot("puddle_splash")
	Session.change_weather()


## F10: put the square on display; a friend's mark asks before decorating.
func _display(hud: Control, c: Node) -> void:
	await press(hud._decorate_btn)
	check(hud._display_btn.visible, "decorating offers Put on display")
	await press(hud._display_btn)
	check(await until(func(): return Session.model.display_by("town").get("pid") == Session.my_pid, 5.0), "the square is on display")
	await press(hud._decorate_btn)   # Done
	check(await until(func(): return hud._display_badge.visible, 3.0), "the On display badge shows while playing")
	# As if a friend had put it on display.
	Session.model.display["town"] = {"pid": "f".repeat(32), "nick": "Kai"}
	hud._refresh_display()
	await press(hud._decorate_btn)
	check(c.mode == "play" and await until(func(): return find_button(hud._overlay, "dialog_button", "Change it") != null, 3.0), "decorating a friend's display asks first")
	await shot("display_ask")
	await press(find_button(hud._overlay, "dialog_button", "Change it"))
	check(c.mode == "decorate" and await until(func(): return Session.model.display_by("town").is_empty(), 5.0), "Change it takes it off display and starts decorating")
	await press(hud._decorate_btn)


## The new cards fit the safe area in this language.
func _cards_in(loc: String, hud: Control, c: Node, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	hud._open_panel("fetch", {})
	await frames(4)
	var r := dialog_rect(hud)
	check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the fetch card fits the safe area" % loc)
	await close_dialogs()
	var trays: Array = Session.model.items.values().filter(func(i): return i["kind"] == "snack_tray")
	if trays.is_empty():
		return
	hud._open_panel("snack", {"tray": trays[0]["id"]})
	await frames(4)
	r = dialog_rect(hud)
	check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the snack card fits the safe area" % loc)
	await shot("%s_snack_card" % loc)
	await close_dialogs()
