## Rendered tour of the eight activities and how a child discovers them.
## Uses real taps on landmarks from afar, the HUD buttons children press, and
## checks what is shown. Screenshots go to --shots.
##   xvfb-run -a -s "-screen 0 1366x1024x24" scripts/godot.sh --path game -- --driver=res://tests/activities_tour.gd --shots=/abs/dir
extends Node

const TownModel := preload("res://scripts/core/town_model.gd")
const Wishes := preload("res://scripts/core/wishes.gd")

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


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func until(cond: Callable, timeout := 10.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await wait(0.2)
		t += 0.2
	return cond.call()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/act_%02d_%s.png" % [shots, _n, name])


func tap(screen: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		await get_tree().process_frame


func screen_of(p: Vector3) -> Vector2:
	return main.rig.camera.unproject_position(p)


func stand(p: Vector2) -> void:
	main.controller.pos = p
	main.controller._place_kid()
	main.rig.snap()
	await frames(4)


func _run() -> void:
	var c: Node = main.controller
	var hud: Control = main.hud
	var aw: Node3D = main.world.activity
	# Start fresh: a new town and no landmark tried yet on this device.
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("player", "discovered", [])
	cfg.save("user://settings.cfg")
	for id in aw._discovered.keys():
		aw._discovered.erase(id)
	while not main.thumbs.is_done:
		await frames(5)
	var save := "user://activities_tour.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	for id in aw._sparkles:
		aw._sparkles[id].emitting = true
	# Discovery: the activity square twinkles and names itself from afar.
	await stand(TownModel.WISHING_TREE + Vector2(0, 8.5))
	main.rig.zoom = 1
	await wait(1.5)
	check(aw._sparkles.values().all(func(p): return p.emitting), "untried landmarks twinkle")
	var tags: Array = hud.visible_tag_rects()
	check(tags.size() >= 2 and tags.size() <= 3, "the nearest untried landmarks show name tags from across the plaza (%d)" % tags.size())
	var clear := true
	for i in tags.size():
		if tags[i].position.y < hud.get_global_rect().position.y + hud.TOP_BAR_H:
			clear = false
		for j in range(i + 1, tags.size()):
			if tags[i].intersects(tags[j]):
				clear = false
	check(clear, "name tags never overlap and never hide under the top bar")
	await shot("activity_square")

	# B. Hide-and-seek: tap the acorn stump from afar; the child walks there and starts.
	# Walk closer so the stump's tag is one of the nearest, then tap the tag itself.
	await stand(aw.point("stump") + Vector2(-1.5, 4.0))
	await wait(1.0)
	var stump_tag: Button = hud._tags.get("stump")
	check(stump_tag != null and stump_tag.visible, "the acorn stump has a tappable name tag")
	if stump_tag != null and stump_tag.visible:
		await tap(stump_tag.get_global_rect().get_center())
	else:
		await tap(screen_of(aw._landmarks["stump"].global_position + Vector3(0, 0.6, 0)))
	check(await until(func(): return Activities.hs.get("phase") == "seeking", 15.0), "tapping the stump walks there and starts hide-and-seek (an animal hides alone)")
	check(not aw._sparkles["stump"].emitting, "once tried, the stump stops twinkling")
	await wait(1.0)
	check(hud._activity_chip.visible and hud._warmth_dots.visible, "the game chip shows warmth dots and a Stop button")
	await shot("hide_and_seek_chip")
	var stop: Button = hud._activity_chip.find_children("*", "Button", true, false)[0]
	stop.pressed.emit()
	check(await until(func(): return Activities.hs.get("phase") == "none"), "Stop ends hide-and-seek")
	await frames(3)
	check(not hud._activity_chip.visible, "the chip goes away")

	# E. Dance party at the drum (walk up, use the action button).
	await stand(aw.point("drum"))
	await frames(5)
	check(c._ctx.get("id") == "drum" and hud._context_btn.visible, "standing by the drum offers Party!")
	check(not hud._tags.has("drum") or not hud._tags["drum"].visible, "no second Party! tag over the child while the button offers it")
	hud._context_btn.pressed.emit()
	check(await until(func(): return Activities.is_party()), "the drum starts a dance party")
	check(Music.is_party() or not Music.music_on, "the music joins in")
	main.rig.zoom = 1
	await wait(3.0)
	check(main.world.lanterns_twinkling() and main.world._lanterns.values().all(func(l): return l.visible), "all eight lanterns hang out and twinkle")
	await shot("dance_party")
	Activities.stop_party()
	await frames(5)
	check(not main.world.lanterns_twinkling() and main.world._lanterns.keys().all(func(k): return main.world._lanterns[k].visible == Session.model.lanterns.has(k)), "after the party only lit lanterns stay")

	# H. Weather vane: rain, autumn, snow, back to sunny.
	await stand(aw.point("vane"))
	await frames(5)
	check(c._ctx.get("id") == "vane", "standing by the vane offers Change the weather")
	for w in ["rain", "autumn", "snow"]:
		hud._context_btn.pressed.emit()
		check(await until(func(): return Session.model.weather == w), "the vane turns to %s" % w)
		await wait(2.5)
		await shot("weather_" + w)
	hud._context_btn.pressed.emit()
	check(await until(func(): return Session.model.weather == "sunny"), "and back to sunny")

	# G. Photo ideas board, then a photo that fulfills one.
	await stand(aw.point("board"))
	await frames(5)
	hud._context_btn.pressed.emit()
	await wait(0.6)
	check(hud._overlay.get_child_count() > 0, "the board shows the photo ideas")
	await shot("photo_ideas_board")
	hud._close_overlay()
	var spot := TownModel.TOWN_SPAWN + Vector2(-5, 2)
	var t: Dictionary = (await _ask(Session.place("table", "town", spot, 0, -2)))
	await _ask(Session.place("plant", "town", spot, 0, 3, t["item"]["id"]))
	await stand(spot + Vector2(0, 2.5))
	main.rig.zoom = 0
	await wait(1.5)
	main._take_photo()
	check(await until(func(): return Session.model.photo_ideas.has("pot_on_table")), "a photo of a pot on a table checks off that idea")

	# A. Animal wish: the pig shows a bubble; tapping it opens the wish card.
	Session.model.wishes["active"] = {"animal": "pig", "id": "pig_picnic"}
	Session.share("wishes")
	var pig: Node3D = main.world.animals["pig"]
	await stand(Vector2(pig.global_position.x, pig.global_position.z) + Vector2(0, 3.0))
	await wait(1.0)
	check(aw._wish_bubble.visible, "the wishing animal has a bubble over its head")
	await tap(screen_of(pig.global_position + Vector3(0, 0.4, 0)))
	await wait(0.6)
	check(hud._overlay.get_child_count() > 0, "tapping the pig opens its wish card")
	await shot("wish_card")
	var help: Button = hud._overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == "I'll help!")[0]
	help.pressed.emit()
	await wait(0.6)
	check(c.mode == "decorate" and hud._category == "Wish", "I'll help! opens the toy box on the Wish tab")
	await shot("wish_tab")
	var pond: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "pond")[0]
	c.begin_new("blanket")
	c._move_ghost_to(Vector2(pond["x"] - 1.0, pond["z"] + 3.3))
	await frames(2)
	if c.g_error != "":
		c._move_ghost_to(Vector2(pond["x"] + 1.2, pond["z"] + 3.4))
	c.confirm_ghost()
	check(await until(func(): return Session.model.wishes["stickers"].size() == 1), "placing the blanket by the pond makes Pip's wish come true")
	await wait(1.5)
	await shot("wish_came_true")
	c.set_mode("play")

	# C. Presents: wrap a bench for anyone, then open it.
	var bench: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "bench")[0]
	c.set_mode("decorate")
	c.select_item(bench["id"])
	await frames(5)
	check(hud._gift_btn.visible, "editing an item offers Gift")
	hud._gift_btn.pressed.emit()
	await wait(0.4)
	await shot("gift_picker")
	var anyone: Button = hud._overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == "For anyone")[0]
	anyone.pressed.emit()
	check(await until(func(): return Session.model.items[bench["id"]].has("gift")), "the bench is wrapped as a present")
	c.set_mode("play")
	await stand(Vector2(bench["x"], bench["z"]) + Vector2(0, 1.8))
	await wait(1.0)
	await shot("present_waiting")
	check(c._ctx.get("type") == "unwrap", "standing by it offers Open the present")
	hud._context_btn.pressed.emit()
	check(await until(func(): return not Session.model.items[bench["id"]].has("gift")), "opening turns it back into the bench")

	# D. Garden bed: place, water three times, full bloom.
	var bed: Dictionary = await _ask(Session.place("garden_bed", "town", TownModel.TOWN_SPAWN + Vector2(5, 3), 0, 6))
	await stand(Vector2(bed["item"]["x"], bed["item"]["z"]) + Vector2(0, 1.7))
	for i in 3:
		await frames(4)
		check(c._ctx.get("type") == "water", "the bed offers Water")
		hud._context_btn.pressed.emit()
		await wait(2.3)
	check(Session.model.items[bed["item"]["id"]]["growth"] == 3, "three waterings bring it to full bloom")
	await shot("garden_bloom")

	# F + wall/ceiling: inside a house, hang a clock and a mobile, leave a heart, read the guest book.
	var home: String = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]["id"]
	c.enter_house(home)
	await wait(1.0)
	c.set_mode("decorate")
	c.begin_new("wall_clock")
	c._move_ghost_to(Vector2(1.0, -2.0))
	await frames(2)
	check(c.g_error == "" and is_equal_approx(c.ghost.position.y, 1.5) and c.g_pos.y == -TownModel.ROOM_HALF.y, "the clock ghost snaps onto the back wall")
	c.confirm_ghost()
	c.begin_new("bird_mobile")
	c._move_ghost_to(Vector2(0.5, 1.0))
	await frames(2)
	check(c.g_error == "" and is_equal_approx(c.ghost.position.y, TownModel.CEILING_Y), "the mobile hangs from the ceiling")
	c.confirm_ghost()
	await frames(5)
	c.set_mode("play")
	var room: String = c.space
	check(Session.model.items_in(room).any(func(i): return i["kind"] == "wall_clock") and Session.model.items_in(room).any(func(i): return i["kind"] == "bird_mobile"), "clock and mobile are in the room")
	hud._heart_btn.pressed.emit()
	check(await until(func(): return Session.model.hearts.get(room, {}).has(Session.my_pid)), "the heart button leaves a heart sticker")
	await stand(main.world.activity.GUEST_BOOK + Vector2(1.0, 0))
	await frames(5)
	check(c._ctx.get("type") == "guest_book", "the guest book stand offers Guest book")
	hud._context_btn.pressed.emit()
	await wait(0.5)
	await shot("room_clock_mobile_guestbook")
	hud._close_overlay()
	print("ACTIVITY TOUR %s: %d failures" % ["PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)


func _ask(req: int) -> Dictionary:
	var out := {}
	var got := [false]
	var cb := func(r_id: int, r: Dictionary):
		if r_id == req:
			out.merge(r)
			got[0] = true
	Session.request_done.connect(cb)
	await until(func(): return got[0], 5.0)
	Session.request_done.disconnect(cb)
	return out
