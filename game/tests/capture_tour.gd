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


## Tabletop decorations through the real placement ghost: put a flower pot on
## the kitchen table, see a second item refused, move the table (the pot follows),
## then undo.
func _tabletop_steps(c: Node, room: String) -> void:
	var table: Dictionary = Session.model.items_in(room).filter(func(i): return i["kind"] == "table")[0]
	c.begin_new("plant")
	c._move_ghost_to(Vector2(table["x"] + 0.2, table["z"] - 0.1))
	await frames(2)
	check(c.g_host == table["id"] and c.g_error == "", "flower pot ghost snaps onto the table top")
	check(absf(c.ghost.position.y - 0.70) < 0.01, "ghost sits on the surface (y %.2f)" % c.ghost.position.y)
	c.confirm_ghost()
	await frames(4)
	var pots: Array = Session.model.attachments_of(table["id"])
	check(pots.size() == 1 and pots[0]["kind"] == "plant", "flower pot is on the table")
	var node: Node3D = main.world.item_nodes.get(pots[0]["id"]) if not pots.is_empty() else null
	check(node != null and absf(node.position.y - 0.70) < 0.01, "drawn on the table top, not floating or sunk")
	c.begin_new("teddy")
	c._move_ghost_to(Vector2(table["x"], table["z"]))
	await frames(2)
	check(c.g_error == TownModel.ERR_SURFACE_TAKEN, "a second decoration is refused: %s" % c.g_error)
	await shot("tabletop_second_refused")
	c.cancel_ghost()
	c.select_item(table["id"])
	await frames(4)
	c._move_ghost_to(Vector2(table["x"] - 0.5, table["z"] + 0.75))
	c.turn_ghost()
	c.turn_ghost()
	c.confirm_ghost()
	await frames(4)
	var moved: Dictionary = Session.model.items[table["id"]]
	var pot: Dictionary = Session.model.items[pots[0]["id"]]
	check(Vector2(pot["x"], pot["z"]).distance_to(Vector2(moved["x"], moved["z"])) < 0.01 and pot["host"] == table["id"], "the pot moves and turns with the table")
	await wait(0.5)
	await shot("tabletop_pot_on_table")
	c.undo()
	await frames(4)
	check(Vector2(Session.model.items[pots[0]["id"]]["x"], Session.model.items[pots[0]["id"]]["z"]).distance_to(Vector2(table["x"], table["z"])) < 0.01, "undo puts table and pot back together")


## Reviewed models in play: pot on the cozy table via the ghost, the lamp refused
## when turned 45 degrees, and a child sitting at the scallop chair's Seat0 marker.
func _modeled_steps(c: Node, room: String) -> void:
	var table: Dictionary = Session.model.items_in(room).filter(func(i): return i["kind"] == "cozy_round_table")[0]
	c.begin_new("desk_lamp")
	c.turn_ghost()
	c._move_ghost_to(Vector2(table["x"], table["z"]))
	await frames(2)
	check(c.g_host == table["id"] and c.g_error == TownModel.ERR_NO_FIT, "a lamp turned 45 degrees is refused on the cozy table: %s" % c.g_error)
	c.cancel_ghost()
	c.begin_new("flower_pot_bloom")
	c._move_ghost_to(Vector2(table["x"], table["z"]))
	await frames(2)
	check(c.g_host == table["id"] and c.g_error == "", "blooming pot snaps onto the cozy table")
	c.confirm_ghost()
	await frames(4)
	var pots: Array = Session.model.attachments_of(table["id"])
	check(pots.size() == 1, "blooming pot on the cozy table")
	if not pots.is_empty():
		check(absf(main.world.item_nodes[pots[0]["id"]].position.y - 0.66) < 0.01, "pot rests at the table's Support0 height 0.66")
	c.set_mode("play")
	var chair: Dictionary = Session.model.items_in(room).filter(func(i): return i["kind"] == "scallop_chair")[0]
	c.pos = Vector2(chair["x"], chair["z"]) + TownModel.facing(chair["rot"]) * 0.9
	c._place_kid()
	c.do_context({"type": "sit", "id": chair["id"]})
	await wait(1.0)
	var seat: Node3D = main.world.item_nodes[chair["id"]].find_child("Seat0", true, false)
	var kid: Node3D = main.world.local_kid()
	check(seat != null and kid.anim == "sit" and kid.global_position.distance_to(seat.global_position) < 0.5, "child sits on the scallop chair at its Seat0 marker")
	main.rig.zoom = 1
	await wait(1.5)
	await shot("room_modeled_furniture")
	main.rig.zoom = 0
	c.stand_up()
	await frames(3)
	c.set_mode("decorate")


func eq_rooms(n: int, want: int) -> void:
	check(n == want, "visited all %d rooms (%d)" % [want, n])


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

	# Three-story cottage: walk through all six rooms using doors and stairs,
	# furnish each one, and come back out through the front door.
	c.set_mode("play")
	var home := ""
	for item in Session.model.items_in("town"):
		if item["kind"] == "cottage":
			home = item["id"]
			break
	var h: Dictionary = Session.model.items[home]
	c.pos = TownModel.door_point(h) + TownModel.facing(h["rot"]) * 2.5
	c._place_kid()
	main.rig.zoom = 1
	await wait(2.0)
	await shot("three_story_house")
	main.rig.zoom = 0
	c.enter_house(home)
	await wait(1.0)
	var R := func(f: int, r: int) -> String: return TownModel.room_space(home, f, r)
	check(main.world.view_space == R.call(0, 0), "front door leads into the ground-floor living room")
	check(Music.context == "home", "music softens indoors")
	var furnish := {
		R.call(0, 0): [["sofa", Vector2(0.5, 2.0)], ["bookshelf", Vector2(-2.6, -2.2)], ["floor_lamp", Vector2(-1.6, -1.4)]],
		R.call(0, 1): [["chair", Vector2(-0.75, 0.5), 2], ["chair", Vector2(1.75, 0.5), 6]],
		R.call(1, 0): [["bed", Vector2(1.2, 1.4)], ["rug", Vector2(-1.0, 0.8)]],
		R.call(1, 1): [["sofa", Vector2(-1.5, 1.6)], ["writing_bureau", Vector2(-2.6, -2.3)], ["desk_lamp", Vector2(1.2, -1.2)]],
		R.call(2, 0): [["bookshelf", Vector2(-2.6, -2.2)], ["chair", Vector2(-1.4, -1.0)], ["floor_lamp", Vector2(-3.3, -0.9)]],
		R.call(2, 1): [["rug", Vector2(0, 0.5)], ["cozy_round_table", Vector2(0.2, 0.6)], ["scallop_chair", Vector2(1.4, 0.6), 6],
			["open_shelf", Vector2(-2.6, -2.4)], ["curved_counter", Vector2(-1.8, 2.1)], ["scallop_bed", Vector2(2.6, 1.6)]],
	}
	var route := [R.call(0, 1), R.call(0, 0), R.call(1, 0), R.call(1, 1), R.call(1, 0), R.call(2, 0), R.call(2, 1), R.call(2, 0), R.call(1, 0), R.call(0, 0)]
	var visited := {}
	var expected_location := {R.call(0, 0): "Floor 1 · Living room", R.call(0, 1): "Floor 1 · Kitchen", R.call(1, 0): "Floor 2 · Bedroom",
		R.call(1, 1): "Floor 2 · Playroom", R.call(2, 0): "Floor 3 · Attic", R.call(2, 1): "Floor 3 · Art studio"}
	for step in route.size() + 1:
		var room: String = c.space
		if not visited.has(room):
			visited[room] = true
			check(main.hud.location_text() == expected_location[room], "location shows %s" % expected_location[room])
			c.set_mode("decorate")
			for spec in furnish[room]:
				c.begin_new(spec[0])
				c._move_ghost_to(spec[1])
				for i in (spec[2] if spec.size() > 2 else 0):
					c.turn_ghost()
				if c.g_error != "":
					print("NOTE ", room, " ", spec[0], " ", c.g_error)
				c.confirm_ghost()
				await frames(3)
			if room == R.call(0, 1):
				await _tabletop_steps(c, room)
			if room == R.call(2, 1):
				await _modeled_steps(c, room)
			c.set_mode("play")
			await wait(0.8)
			await shot("room_%s" % room.substr(room.find(":") + 1).replace(":", "_"))
		if step == route.size():
			break
		# Walk to the doorway or stairs that lead to the next room, like a child would.
		var target: String = route[step]
		var way: Array = c.portal_contexts().filter(func(p): return p.get("target", "town") == target)
		check(way.size() == 1, "a way from %s to %s" % [room, target])
		if way.is_empty():
			break
		var before: Vector2 = c.pos
		c._walk_to(way[0]["at"], way[0])
		var t := 0.0
		while c.space != target and t < 12.0:
			await wait(0.2)
			t += 0.2
		check(c.space == target and main.world.view_space == target, "walked from %s to %s (%.1fs)" % [room, target, t])
		check(TownModel.portals(target).any(func(p): return p["target"] == room and c.pos.distance_to(p["at"]) < 1.6), "arrived next to the way back")
	eq_rooms(visited.size(), 6)
	var counts := {}
	for room in furnish:
		counts[room] = Session.model.items_in(room).map(func(i): return i["kind"])
		check(Session.model.items_in(room).size() >= furnish[room].size(), "%s furnished" % room)
	# Only the occupied room is shown.
	check(main.world.item_nodes.keys().all(func(id): return Session.model.items[id]["space"] == c.space), "only the current room's furniture is drawn")
	var out: Array = c.portal_contexts().filter(func(p): return p["type"] == "exit")
	c._walk_to(out[0]["at"], out[0])
	var tt := 0.0
	while c.space != "town" and tt < 12.0:
		await wait(0.2)
		tt += 0.2
	check(main.world.view_space == "town", "back outside through the front door")
	check(c.pos.distance_to(TownModel.door_point(h)) < 1.5, "standing at the cottage's front door (%.2f m)" % c.pos.distance_to(TownModel.door_point(h)))
	check(main.hud.location_text() == "", "location hidden outdoors")

	# The bigger countryside: walk out to the east meadow.
	var meadow := Vector2(16.5, 15.5)
	c.pos = Vector2(9.0, 10.0)
	c._place_kid()
	c._walk_to(meadow, {})
	await wait(5.0)
	check(c.pos.distance_to(meadow) < 1.0, "walked out into the new meadow (%.1f m away)" % c.pos.distance_to(meadow))
	main.rig.zoom = 1
	await wait(2.0)
	await shot("countryside")
	main.rig.zoom = 0
	check(Animals.states.size() == 5, "five animal friends are out")
	c.pos = Vector2(-2.0, 7.0)
	c._place_kid()
	main.rig.zoom = 1
	await wait(3.0)
	await shot("animals")
	main.rig.zoom = 0
	check(Music.context == "town" and Music.is_playing(), "music plays outdoors")
	main.hud.open_sound()
	await wait(0.4)
	await shot("sound_settings")
	main.hud._close_overlay()

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
	# Reload the save: every room keeps its own furniture.
	Session.save_now()
	var rooms_before := {}
	for item in Session.model.items.values():
		rooms_before.get_or_add(item["space"], []).append(item["kind"])
	Session.leave()
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var rooms_after := {}
	for item in Session.model.items.values():
		rooms_after.get_or_add(item["space"], []).append(item["kind"])
	for room in rooms_before:
		rooms_before[room].sort()
		rooms_after.get(room, []).sort()
	check(rooms_before == rooms_after, "every room's furniture survives a reload (%d spaces)" % rooms_before.size())
	I18n.set_locale("en", false)
	print("TOUR %s: %d failures" % ["PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)
