## Rendered check of the How to play guide (eight illustrated activities) and of
## PT-AH-001 (photo and idea messages stay readable next to landmark name tags).
##   xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 -- \
##       --driver=res://tests/guide_tour.gd --shots=/abs/dir --tag=ipad --locales=en,zh-CN,ja,es,fr,de
## iPhone: --resolution 2208x1024 --tag=iphone --safe-insets=154,0,154,55
## PT-AH-001 pose (the playtest window): --resolution 1100x800 --tag=pt001 --locales=zh-CN,en
extends Node

const ActivityGuide := preload("res://scripts/ui/activity_guide.gd")
const TownModel := preload("res://scripts/core/town_model.gd")

var main: Node
var failures := 0
var shots := ""
var tag := ""
var _n := 0


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + "[%s] %s" % [tag, what])
	if not cond:
		failures += 1


func _ready() -> void:
	shots = main.args.get("shots", ProjectSettings.globalize_path("user://shots"))
	tag = main.args.get("tag", "view")
	DirAccess.make_dir_recursive_absolute(shots)
	_run.call_deferred()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func until(cond: Callable, timeout := 8.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await wait(0.1)
		t += 0.1
	return cond.call()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/guide_%s_%02d_%s.png" % [shots, tag, _n, name])


## Taps at a point in canvas (UI) coordinates. With the canvas_items stretch the
## window may be scaled (e.g. 1100x800 shows a 1408x1024 canvas at 0.78), so the
## point is mapped to window coordinates first, as a real finger would be.
## r16b: like a finger, the pointer is moved to the point before the press and again before the lift. In a
## real window the desktop cursor can deliver a motion elsewhere between the two; a Button then treats the
## press as slid off and ignores the release (the r16 Mac "Back returns to the cards" failure).
func tap(canvas_pos: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_final_transform() * canvas_pos
	for pressed in [true, false]:
		var m := InputEventMouseMotion.new()
		m.position = screen
		m.global_position = screen
		m.button_mask = 0 if pressed else MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		if pressed:
			await _between_press_and_lift()
		await get_tree().process_frame


## Diagnosis hook (the r16b probe injects a desktop-cursor motion here); nothing happens in the tour.
func _between_press_and_lift() -> void:
	pass


func press(b: Control) -> void:
	var scroll := b.get_parent().get_parent() as ScrollContainer
	if scroll:
		scroll.ensure_control_visible(b)
		await frames(2)
	await tap(b.get_global_rect().get_center())
	await frames(3)


func inside(area: Rect2, r: Rect2) -> bool:
	return r.size != Vector2.ZERO and area.grow(0.5).encloses(r)


func node(root: Node, name: String) -> Control:
	return root.find_child(name, true, false) as Control


func cards(hud: Control) -> Array:
	var grid := node(hud._overlay, "GuideCards")
	return grid.get_children().filter(func(c): return not c.is_queued_for_deletion()) if grid else []


func stand(p: Vector2) -> void:
	main.controller.pos = p
	main.controller._place_kid()
	main.rig.snap()
	await frames(4)


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	while not main.thumbs.is_done:
		await get_tree().process_frame
	var save := "user://guide_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	print("INFO [%s] viewport %s, safe area %s" % [tag, get_viewport().get_visible_rect().size, area])
	var locales: Array = main.args.get("locales", "en").split(",")
	if tag == "pt001":
		for loc in locales:
			await _pt_ah_001(loc, hud, c, area)
	else:
		for loc in locales:
			await _guide_in(loc, hud, c, area)
		I18n.set_locale(locales[0])
		await _go_there(hud, c)
	print("GUIDE %s %s: %d failures" % [tag, "PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)


## Open the guide from its button, see eight different cards, open and leave every activity.
func _guide_in(loc: String, hud: Control, c: Node, area: Rect2) -> void:
	I18n.set_locale(loc)
	await stand(TownModel.WISHING_TREE + Vector2(0, 8.5))
	await frames(4)
	var btn: Button = hud._guide_btn
	check(btn.is_visible_in_tree() and inside(area, btn.get_global_rect()) and btn.size.y >= 56.0, "[%s] the Activities button is visible in the safe area (%s)" % [loc, tr("Activities")])
	for t in hud.visible_tag_rects():
		check(not t.intersects(btn.get_global_rect()), "[%s] no name tag covers the Activities button" % loc)
	var mode_before: String = c.mode
	var weather_before: String = Session.model.weather
	var items_before: int = Session.model.items.size()
	await press(btn)
	check(hud.guide_open(), "[%s] the guide opens" % loc)
	var list := cards(hud)
	check(list.size() == 8, "[%s] eight activity cards" % loc)
	var textures := {}
	for card in list:
		var art := node(card, "Art") as TextureRect
		if art and art.texture:
			textures[art.texture.get_rid()] = true
		check(inside(area, card.get_global_rect()) or node(hud._overlay, "GuideScroll") != null, "[%s] card %s is reachable" % [loc, card.get_meta("guide_id")])
		check(card.size.y >= 120.0 and card.size.x >= 200.0, "[%s] card %s is a big touch target" % [loc, card.get_meta("guide_id")])
	check(textures.size() == 8, "[%s] every card has its own illustration" % loc)
	await shot("%s_overview" % loc)
	# Every activity: open, read, go back (or close for the last one).
	var ids: Array = ActivityGuide.ENTRIES.map(func(e): return e["id"])
	for i in ids.size():
		var card: Control = null
		for x in cards(hud):
			if x.get_meta("guide_id") == ids[i]:
				card = x
		check(card != null, "[%s] card %s is listed" % [loc, ids[i]])
		if card == null:
			continue
		await press(card)
		var detail := node(hud._overlay, "GuideDetail")
		check(detail != null and detail.get_meta("guide_id") == ids[i], "[%s] %s opens its how-to" % [loc, ids[i]])
		if detail == null:
			continue
		var text := node(detail, "GuideText")
		var labels := text.find_children("*", "Label", true, false)
		var all := " ".join(labels.map(func(l): return l.text))
		var e := ActivityGuide.find(ids[i])
		var where := ActivityGuide.line(e["where"], func(t): return tr(t))
		check(all.contains(where), "[%s] %s shows where to start in this language" % [loc, ids[i]])
		for s in e["steps"]:
			if s is Array:
				for lab in s[1]:
					check(all.contains(tr(lab)), "[%s] %s names the on-screen label \"%s\"" % [loc, ids[i], tr(lab)])
		check(inside(area, detail.get_global_rect()) and inside(area, node(detail, "GuideGo").get_global_rect()) and inside(area, node(detail, "GuideBack").get_global_rect()), "[%s] %s fits the safe area" % [loc, ids[i]])
		if loc in ["de", "ja", locales_first()] or i == 0:
			await shot("%s_%s" % [loc, ids[i]])
		if i < ids.size() - 1:
			await press(node(detail, "GuideBack"))
			check(cards(hud).size() == 8, "[%s] Back returns to the cards" % loc)
		else:
			await press(node(hud._overlay, "GuideClose"))
	check(not hud.guide_open(), "[%s] Close leaves the guide" % loc)
	check(c.mode == mode_before and Session.model.weather == weather_before and Session.model.items.size() == items_before
		and Activities.hs.get("phase") == "none" and not Activities.is_party(), "[%s] reading the guide changed nothing in the game" % loc)


func locales_first() -> String:
	return main.args.get("locales", "en").split(",")[0]


## Go there walks next to the landmark and stops: no game starts by itself.
func _go_there(hud: Control, c: Node) -> void:
	await stand(TownModel.WISHING_TREE + Vector2(0, 9.5))
	for spec in [["acorn", "stump"], ["party", "drum"], ["weather", "vane"], ["photos", "board"]]:
		var weather_before: String = Session.model.weather
		hud.open_guide(spec[0])
		await frames(4)
		await press(node(hud._overlay, "GuideGo"))
		check(not hud.guide_open(), "Go there closes the guide (%s)" % spec[0])
		var at: Vector2 = main.world.activity.point(spec[1])
		check(await until(func(): return c.pos.distance_to(at) < 1.6, 12.0), "the child walks next to the %s" % spec[1])
		await wait(0.6)
		check(Activities.hs.get("phase") == "none" and not Activities.is_party() and Session.model.weather == weather_before and hud._overlay.get_child_count() == 0,
			"arriving at the %s starts nothing by itself" % spec[1])
		check(c._ctx.get("id") == spec[1] or (spec[1] == "bell" and c._ctx.get("type") == "bell"), "the %s's own button is offered instead" % spec[1])
		if spec[0] == "acorn":
			await shot("go_there_stump")
	# Indoors, Go there is honest instead of teleporting.
	var home: String = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]["id"]
	c.enter_house(home)
	await wait(1.0)
	var space_before: String = c.space
	hud.open_guide("party")
	await frames(4)
	await press(node(hud._overlay, "GuideGo"))
	check(c.space == space_before and hud.guide_open() and hud._toast_label.text == "Go outside first. It is on the town square.", "indoors, Go there says to go outside first")
	await press(node(hud._overlay, "GuideClose"))
	# The wish card: with no wish, an honest hint; nothing is created.
	hud.open_guide("wishes")
	await frames(4)
	var wishes_before: Dictionary = Session.model.wishes.duplicate(true)
	await press(node(hud._overlay, "GuideGo"))
	check(Session.model.wishes == wishes_before, "Show the wish never makes a wish")
	hud._close_overlay()
	c.exit_house()
	await wait(1.0)


## PT-AH-001: in front of the Photo ideas board at the recorded pose, the photo
## message stays fully readable while the landmark tags are shown.
func _pt_ah_001(loc: String, hud: Control, c: Node, area: Rect2) -> void:
	I18n.set_locale(loc)
	main.rig.zoom = 0
	await stand(main.world.activity.point("board") + Vector2(0.6, 1.6))
	await wait(1.0)
	var tags_before: Array = hud.visible_tag_rects()
	check(tags_before.size() >= 1, "[%s] landmark tags are showing at the recorded pose (%d)" % [loc, tags_before.size()])
	check(hud._tag_layer.get_index() == 0, "[%s] tags are drawn under every other HUD part" % loc)
	var photos_before: int = hud._photos.size()
	var ideas_before: Dictionary = Session.model.photo_ideas.duplicate(true)
	for attempt in 2:
		var cam_btn: Control = null
		for b in hud.find_children("*", "Button", true, false):
			if b.tooltip_text == "Take a photo":
				cam_btn = b
		await tap(cam_btn.get_global_rect().get_center())
		await until(func(): return hud._toast.modulate.a > 0.9, 3.0)
		await frames(3)
		var toast: Rect2 = hud._toast.get_global_rect()
		var clear := true
		for t in hud.visible_tag_rects():
			if t.intersects(toast):
				clear = false
		check(clear, "[%s] photo %d: no name tag covers the message" % [loc, attempt + 1])
		check(not hud.visible_tag_rects().is_empty(), "[%s] photo %d: the landmark tags stay available" % [loc, attempt + 1])
		await shot("%s_photo_%d" % [loc, attempt + 1])
		await wait(3.2)
	check(hud._photos.size() == photos_before + 2, "[%s] both photos are in the scrapbook" % loc)
	for k in ideas_before:
		check(Session.model.photo_ideas.has(k), "[%s] completed idea %s stays recorded" % [loc, k])
	# A first-time idea message at the tree.
	hud.show_toast(tr("Photo idea done: %s") % tr("An animal friend by a pond"))
	await frames(4)
	var toast: Rect2 = hud._toast.get_global_rect()
	check(hud.visible_tag_rects().all(func(t): return not t.intersects(toast)), "[%s] an idea message is not covered either" % loc)
	await shot("%s_idea_message" % loc)
	await wait(3.2)
