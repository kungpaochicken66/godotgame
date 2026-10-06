## Rendered end-to-end tour of solo play. Drives the real game through its
## public controller API plus a few real input events, asserts outcomes and
## saves screenshots for visual review.
##   xvfb-run -a -s "-screen 0 1366x1024x24" scripts/godot.sh --path game -- \
##       --driver=res://tests/capture_tour.gd --shots=/abs/dir [--locales=en,ja]
extends Node

const TownModel := preload("res://scripts/core/town_model.gd")

var main: Node
var shots := ""
var failures := 0
var _n := 0


func _ready() -> void:
	shots = main.args.get("shots", ProjectSettings.globalize_path("user://shots"))
	DirAccess.make_dir_recursive_absolute(shots)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func frames(n := 10) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var path := "%s/%02d_%s.png" % [shots, _n, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func tap(screen: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		await get_tree().process_frame


func screen_of(p: Vector2) -> Vector2:
	return main.rig.camera.unproject_position(Vector3(p.x, 0, p.y))


func _run() -> void:
	var c: Node = main.controller
	var locales: PackedStringArray = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0], false)
	while not main.thumbs.is_done:
		await frames(5)
	await wait(0.5)
	await shot("title")
	main.menus.show_screen("creator")
	await wait(0.6)
	await shot("creator")

	# Fresh solo town.
	var save := "user://capture_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	check(main.hud.visible and not main.menus.visible, "solo play starts in the town")
	check(Session.model.items.size() > 20, "default town loaded")
	await shot("town")

	# Real tap-to-walk input on open lawn.
	var start: Vector2 = c.pos
	var goal := start + Vector2(2.5, -1.5)
	await tap(screen_of(goal))
	await wait(1.5)
	check(c.pos.distance_to(goal) < 0.5, "tap on the lawn walks there (%.2f m away)" % c.pos.distance_to(goal))

	# Decorate: a tea party by the path forms a Cozy Spot and lights a lantern.
	c.set_mode("decorate")
	await frames(3)
	var base := Vector2(-6.0, 5.0)
	c.begin_new("table")
	c._move_ghost_to(base)
	await wait(0.4)
	await shot("decorate_ghost")
	c.confirm_ghost()
	await frames(3)
	var lantern_events := []
	Session.lantern_lit.connect(func(spot, _by): lantern_events.append(spot))
	for dx in [-1.25, 1.25]:
		c.begin_new("chair")
		c._move_ghost_to(base + Vector2(dx, 0))
		for i in (2 if dx < 0 else 6):
			c.turn_ghost()
		c.confirm_ghost()
		await frames(3)
	check(lantern_events.has("tea_party"), "tea party lights a lantern")
	check(Session.model.lanterns.has("tea_party"), "lantern recorded in the town save")
	c.pos = base + Vector2(0, 3)
	c._place_kid()
	await wait(0.8)
	await shot("lantern_celebration")

	# Invalid placement is refused with a hint.
	c.begin_new("tree")
	c._move_ghost_to(TownModel.WISHING_TREE)
	await frames(2)
	check(c.g_error == TownModel.ERR_TREE, "cannot plant on the Wishing Tree plaza")
	await shot("invalid_placement")
	c.cancel_ghost()

	# Edit an existing item: move, paint and undo.
	var bench_id := ""
	for item in Session.model.items_in("town"):
		if item["kind"] == "bench":
			bench_id = item["id"]
	c.select_item(bench_id)
	await frames(3)
	check(Session.lock_holder(bench_id) == Session.my_id, "selecting locks the item for me")
	c.paint_ghost(6)
	c._move_ghost_to(Vector2(Session.model.items[bench_id]["x"] - 1.0, Session.model.items[bench_id]["z"]))
	c.confirm_ghost()
	await frames(3)
	check(Session.model.items[bench_id]["color"] == 6, "bench painted lilac")
	check(Session.lock_holder(bench_id) == 0, "lock released after editing")
	c.undo()
	await frames(3)
	c.undo()
	await frames(3)
	check(Session.model.items[bench_id]["color"] == 5, "undo restores the paint")

	# Go inside the first cottage and furnish it.
	c.set_mode("play")
	var home := ""
	for item in Session.model.items_in("town"):
		if item["kind"] == "cottage":
			home = item["id"]
			break
	c.enter_house(home)
	await wait(1.2)
	check(main.world.view_space == home, "inside the cottage")
	c.set_mode("decorate")
	for spec in [["bed", Vector2(0.4, -1.9)], ["sofa", Vector2(-2.6, 1.6)], ["bookshelf", Vector2(-3.2, -2.2)], ["floor_lamp", Vector2(-1.6, -2.4)], ["teddy", Vector2(1.6, 0.9)]]:
		c.begin_new(spec[0])
		c._move_ghost_to(spec[1])
		if c.g_error != "":
			print("NOTE ", spec[0], " ", c.g_error)
		c.confirm_ghost()
		await frames(3)
	check(Session.model.items_in(home).size() >= 6, "furniture belongs to this cottage")
	c.set_mode("play")
	await wait(1.0)
	await shot("interior")
	c.exit_house()
	await wait(1.0)
	check(main.world.view_space == "town", "back outside")

	# The swing really animates with the child on it.
	var swing := ""
	for item in Session.model.items_in("town"):
		if item["kind"] == "swing":
			swing = item["id"]
	c.pos = Vector2(Session.model.items[swing]["x"], Session.model.items[swing]["z"]) + Vector2(1.6, 0)
	c._place_kid()
	c.do_context({"type": "sit", "id": swing})
	await wait(1.3)
	check(not Session.seat_of(Session.my_id).is_empty(), "sitting on the swing")
	var pivot: Node3D = main.world.item_nodes[swing].get_node("Pivot")
	var sway := 0.0
	for i in 20:
		sway = maxf(sway, absf(pivot.rotation.x))
		await wait(0.05)
	check(sway > 0.15, "swing is swaying (%.2f rad)" % sway)
	await shot("swing")
	c.stand_up()
	await frames(3)

	# Ring the evening bell.
	c.pos = main.world.bell_point() + Vector2(0.6, 0.6)
	c._place_kid()
	await frames(5)
	check(c._ctx.get("type") == "bell", "bell action offered near the Wishing Tree")
	c.do_context()
	await wait(2.6)
	check(Session.model.evening, "evening for everyone")
	Session.send_emote("cheer")
	c.pos = TownModel.WISHING_TREE + Vector2(-1.2, 4.2)
	c.ry = 0.0
	c._place_kid()
	main.rig.zoom = 1
	await wait(2.5)
	await shot("evening")
	main.rig.zoom = 0

	main.hud.open_scrapbook()
	await wait(0.5)
	await shot("scrapbook")
	main.hud._close_overlay()

	# Autosave reached disk.
	await wait(2.0)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(save))
	check(typeof(saved) == TYPE_DICTIONARY and saved["lanterns"].has("tea_party"), "town autosaved with its lantern")

	# Every requested language, with the town and a placement draft kept.
	c.set_mode("decorate")
	c.begin_new("flowers")
	var draft_pos: Vector2 = c.g_pos
	var before: int = Session.model.items.size()
	for code in locales:
		I18n.set_locale(code, false)
		await wait(0.5)
		check(c.ghost != null and c.g_pos == draft_pos, "%s keeps the placement draft" % code)
		await shot("decorate_%s" % code)
	check(Session.model.items.size() == before, "switching language leaves the town unchanged")
	c.cancel_ghost()
	I18n.set_locale("en", false)
	print("TOUR %s: %d failures" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)
