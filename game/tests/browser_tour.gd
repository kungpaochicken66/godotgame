## Rendered check of the toy box browser and of picking things in a crowded room
## (design/item-browser-ux.md). Uses real taps on real controls, in every locale.
##   xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 -- \
##       --driver=res://tests/browser_tour.gd --shots=/abs/dir --tag=ipad --locales=en,zh-CN,ja,es,fr,de
## iPhone landscape: --resolution 2208x1024 --tag=iphone --safe-insets=154,0,154,55
extends Node

const Catalog := preload("res://scripts/core/catalog.gd")
const ItemQuery := preload("res://scripts/ui/item_query.gd")

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
	get_viewport().get_texture().get_image().save_png("%s/browser_%s_%02d_%s.png" % [shots, tag, _n, name])


## Taps at a point in canvas (UI) coordinates. With the canvas_items stretch the
## window may be scaled (e.g. 1100x800 shows a 1408x1024 canvas at 0.78), so the
## point is mapped to window coordinates first, as a real finger would be.
func tap(canvas_pos: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_final_transform() * canvas_pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		await get_tree().process_frame


## Taps a control where the child would: its visible center (scrolled into view first).
func press(b: Control) -> void:
	var scroll := b.get_parent().get_parent() as ScrollContainer
	if scroll:
		scroll.ensure_control_visible(b)
		await frames(2)
	await tap(b.get_global_rect().get_center())
	await frames(2)


func typed(text: String) -> void:
	var hud: Control = main.hud
	hud._search.grab_focus()
	hud._search.select_all()
	hud._search.delete_text(0, hud._search.text.length())
	hud._search.insert_text_at_caret(text)
	await wait(0.35)   # the toy box waits 0.15 s after the last key


func chip(hud: Control, key: String, value: String) -> Button:
	for b in hud._tabs.get_children():
		if b is Button and b.get_meta(key, "") == value:
			return b
	return null


func card(hud: Control, kind: String) -> Button:
	for b in hud._cards.get_children():
		if b.get_meta("kind", "") == kind:
			return b
	return null


func shown_kinds(hud: Control) -> Array:
	return hud._cards.get_children().filter(func(b): return not b.is_queued_for_deletion()).map(func(b): return b.get_meta("kind"))


func inside(area: Rect2, r: Rect2) -> bool:
	return r.size != Vector2.ZERO and area.grow(0.5).encloses(r)


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


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	while not main.thumbs.is_done:
		await get_tree().process_frame
	var save := "user://browser_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	hud._recent = []
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	print("INFO [%s] viewport %s, safe area %s" % [tag, get_viewport().get_visible_rect().size, area])
	var home: String = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]["id"]
	c.enter_house(home)
	await wait(1.0)
	c.set_mode("decorate")
	await frames(5)
	var locales: Array = main.args.get("locales", "en").split(",")
	for loc in locales:
		await _browse_in(loc, hud, c, area)
	I18n.set_locale(locales[0])
	await frames(5)
	await _repeat_placement(hud, c, area)
	await _crowded_room(hud, c, area)
	await _responsiveness(hud)
	print("BROWSER %s %s: %d failures" % [tag, "PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)


## Search, no results and reset, and a placement filter, in one language.
func _browse_in(loc: String, hud: Control, c: Node, area: Rect2) -> void:
	I18n.set_locale(loc)
	hud._category = "Cozy things"
	hud._placement = ""
	hud._set_query("")
	await frames(5)
	var kinds := shown_kinds(hud)
	check(hud._catalog.is_visible_in_tree() and kinds.size() == Catalog.kinds_for("Cozy things", c.space).size(), "[%s] Cozy things lists all %d items" % [loc, kinds.size()])
	check(hud._count.text == tr("%d things") % kinds.size(), "[%s] the count says %s" % [loc, hud._count.text])
	check(inside(area, hud._catalog.get_global_rect()) and inside(area, hud._search.get_global_rect()), "[%s] toy box and search field are inside the safe area" % loc)
	var small := false
	for b in hud._tabs.get_children():
		if b is Button and b.size.y < 56.0:
			small = true
	check(not small and hud._search.size.y >= 56.0 and hud._things_btn.size.y >= 56.0, "[%s] tabs, filters, search and Things here are at least 56 px tall" % loc)
	await shot("%s_toybox" % loc)
	# Search by the localized name, typed in capitals: the wall clock comes first.
	var name: String = tr(Catalog.ITEMS["wall_clock"]["name"])
	await typed(name.to_upper())
	kinds = shown_kinds(hud)
	check(not kinds.is_empty() and kinds[0] == "wall_clock", "[%s] searching \"%s\" finds the wall clock first" % [loc, name.to_upper()])
	check(hud._count.text == (tr("1 thing") if kinds.size() == 1 else tr("%d things") % kinds.size()), "[%s] the count matches the %d results" % [loc, kinds.size()])
	# A part of the name also works (two characters for Chinese and Japanese, a word elsewhere).
	var part: String = name.substr(name.length() - 2) if loc in ["zh-CN", "ja"] else name.split(" ")[name.split(" ").size() - 1]
	await typed(part)
	check(shown_kinds(hud).has("wall_clock"), "[%s] part of the name (\"%s\") finds it too" % [loc, part])
	# The keyboard: the toy box rises above it and stays readable.
	var kb: float = area.size.y * 0.42
	hud.debug_keyboard_height = kb
	hud._search.grab_focus()
	await frames(4)
	var r: Rect2 = hud._catalog.get_global_rect()
	check(r.end.y <= area.end.y - kb + 1.0 and r.position.y >= area.position.y + hud.TOP_BAR_H - 1.0, "[%s] with the keyboard up, the toy box sits between it and the top bar" % loc)
	await shot("%s_keyboard" % loc)
	hud.debug_keyboard_height = 0.0
	hud._search.release_focus()
	await frames(3)
	await shot("%s_search" % loc)
	# Nothing found, then Clear search brings the tab back.
	await typed("zzqx")
	check(hud._empty.is_visible_in_tree() and shown_kinds(hud).is_empty() and hud._empty_label.text.contains("zzqx"), "[%s] a search with no results says so" % loc)
	await shot("%s_no_results" % loc)
	await press(hud._empty_btn)
	await frames(3)
	check(hud._query == "" and hud._search.text == "" and hud._category == "Cozy things" and shown_kinds(hud).size() == Catalog.kinds_for("Cozy things", c.space).size(), "[%s] Clear search brings back the whole tab" % loc)
	# A placement filter from the catalog metadata, then off again.
	var wall := chip(hud, "placement", "wall")
	check(wall != null, "[%s] Cozy things offers an On the wall filter" % loc)
	if wall:
		await press(wall)
		kinds = shown_kinds(hud)
		check(not kinds.is_empty() and kinds.all(func(k): return Catalog.anchor(k) == "wall"), "[%s] On the wall shows %d wall items only" % [loc, kinds.size()])
		await shot("%s_wall_filter" % loc)
		await press(chip(hud, "placement", "wall"))
		check(hud._placement == "" and shown_kinds(hud).size() == Catalog.kinds_for("Cozy things", c.space).size(), "[%s] tapping the filter again shows everything" % loc)


## Place the same thing twice from its card, keeping the toy box where it was.
func _repeat_placement(hud: Control, c: Node, area: Rect2) -> void:
	await press(chip(hud, "tab", "Furniture"))
	var chair := card(hud, "chair")
	check(chair != null, "Furniture has the chair card")
	if chair == null:
		return
	hud._card_scroll.ensure_control_visible(chair)
	await frames(3)
	var before_scroll: int = hud._card_scroll.scroll_horizontal
	var count_before: int = Session.model.items_in(c.space).filter(func(i): return i["kind"] == "chair").size()
	for round in 2:
		await press(card(hud, "chair"))
		await until(func(): return c.ghost != null)
		check(hud._tools_name.text == tr("Chair") and hud._tools_name.is_visible_in_tree(), "the tools name the chair being placed")
		# Somewhere free, then Place here.
		var spot = Session.model.find_free_spot("chair", c.space, Vector2(-1.2 + round * 1.2, 0.8))
		if spot != null:
			c._move_ghost_to(spot)
		await frames(3)
		await press(hud._place_btn)
		await until(func(): return c.ghost == null)
		await wait(0.3)
		check(hud._category == "Furniture" and abs(hud._card_scroll.scroll_horizontal - before_scroll) <= 2, "after placing, the toy box stays on Furniture at the same place (round %d)" % (round + 1))
	var count_after: int = Session.model.items_in(c.space).filter(func(i): return i["kind"] == "chair").size()
	check(count_after == count_before + 2, "two chairs were placed with two taps on the same card (%d -> %d)" % [count_before, count_after])
	check(hud._recent.size() >= 1 and hud._recent[0] == "chair" and chip(hud, "tab", "Recent") != null, "Recent appears with the chair first")
	var b := card(hud, "chair")
	check(b != null and b.get_theme_stylebox("normal") is StyleBoxFlat and (b.get_theme_stylebox("normal") as StyleBoxFlat).border_width_top >= 4, "the chair card is outlined as the last one taken")
	await shot("repeat_placement")
	# Undo still takes back one placement.
	c.undo()
	await until(func(): return Session.model.items_in(c.space).filter(func(i): return i["kind"] == "chair").size() == count_before + 1)
	check(Session.model.items_in(c.space).filter(func(i): return i["kind"] == "chair").size() == count_before + 1, "Undo takes back the last chair only")
	# Cancel on a new item says where it went and changes nothing.
	var n_items: int = Session.model.items.size()
	await press(card(hud, "chair"))
	await until(func(): return c.ghost != null)
	var cancel: Button = null
	for x in hud._tools_row.get_children():
		if x is Button and x.text == "Cancel":
			cancel = x
	await press(cancel)
	await frames(3)
	check(c.ghost == null and Session.model.items.size() == n_items and hud._toast.visible and hud._toast_label.text == tr("Back in the toy box."), "Cancel puts it back in the toy box and says so")
	await press(chip(hud, "tab", "Recent"))
	check(shown_kinds(hud).size() >= 1 and shown_kinds(hud)[0] == "chair", "the Recent tab lists the chair first")


## A table with a flower pot on it, a teddy and a chair close by: a tap among
## them asks which one; Things here lists them all.
func _crowded_room(hud: Control, c: Node, area: Rect2) -> void:
	c.cancel_ghost()
	var center := Vector2(0.4, -0.6)
	var t := await _ask(Session.place("table", c.space, center, 0, 1))
	check(t.get("ok", false), "a table stands in the room")
	if not t.get("ok", false):
		return
	var table: String = t["item"]["id"]
	var pot := await _ask(Session.place("plant", c.space, center, 0, 2, table))
	check(pot.get("ok", false), "a flower pot sits on the table")
	for spec in [["teddy", Vector2(0.75, 0.15)], ["chair", Vector2(-0.2, 0.8)]]:
		var spot = Session.model.find_free_spot(spec[0], c.space, center + spec[1])
		var r := await _ask(Session.place(spec[0], c.space, spot if spot != null else center + spec[1], 0, 3))
		check(r.get("ok", false), "a %s stands close to the table" % spec[0])
	await wait(0.6)
	c.pos = center + Vector2(0, 2.2)
	c._place_kid()
	main.rig.snap()
	await frames(5)
	# Find a spot over the table where more than one thing is under the finger.
	var cam: Camera3D = main.rig.camera
	var at := Vector2.ZERO
	var choices := []
	var base: Vector2 = cam.unproject_position(Vector3(center.x, 0.75, center.y))
	for dy in range(-40, 60, 8):
		for dx in range(-40, 60, 8):
			var p := base + Vector2(dx, dy)
			var ch: Array = ItemQuery.tap_choices(main.world.pick_candidates(cam, p))
			if ch.size() > 1 and ch.has(pot["item"]["id"]):
				at = p
				choices = ch
				break
		if not choices.is_empty():
			break
	check(choices.size() > 1, "there is a spot where the pot and its neighbors are all under the finger (%d)" % choices.size())
	if not choices.is_empty():
		await tap(at)
		await frames(4)
		var chooser: Rect2 = hud.chooser_rect()
		check(chooser.size != Vector2.ZERO and inside(area, chooser), "a tap there opens Which one? inside the safe area")
		check(c.ghost == null, "nothing was picked up before choosing")
		await shot("which_one")
		var rows := _rows(hud._overlay)
		check(rows.size() == choices.size(), "the chooser offers %d things" % rows.size())
		var pot_row: Button = null
		for r in rows:
			if r.get_meta("item_id") == pot["item"]["id"]:
				pot_row = r
		check(pot_row != null and pot_row.text.contains(tr("on a table")), "the flower pot row says it is on a table")
		if pot_row:
			await press(pot_row)
			await until(func(): return c.ghost != null)
			check(c.g_edit_id == pot["item"]["id"], "choosing the pot lifts only the pot")
			c.cancel_ghost()
			await frames(3)
			check(Session.model.items[pot["item"]["id"]].get("host", "") == table, "Cancel leaves the pot on its table")
	# Things here: every item in the room, nearest first; a row picks it up.
	await press(hud._things_btn)
	await frames(4)
	var rows := _rows(hud._overlay)
	check(rows.size() == Session.model.items_in(c.space).size(), "Things here lists all %d things in the room" % rows.size())
	await shot("things_here")
	var trow: Button = null
	for r in rows:
		if r.get_meta("item_id") == table:
			trow = r
	if trow:
		await press(trow)
		await until(func(): return c.ghost != null)
		check(c.g_edit_id == table, "a Things here row picks up the table")
		c.cancel_ghost()


func _rows(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "Button", true, false):
		if n.has_meta("item_id"):
			out.append(n)
	return out


## Building the cards stays quick with the real catalog; a fixture-sized row
## (600 cards from real kinds, test only) is timed too.
func _responsiveness(hud: Control) -> void:
	hud._category = "All"
	hud._set_query("")
	var t0 := Time.get_ticks_usec()
	hud._rebuild_cards()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("INFO [%s] All tab, %d real items: cards built in %.1f ms" % [tag, shown_kinds(hud).size(), ms])
	check(ms < 400.0, "the All tab builds in %.1f ms" % ms)
	var kinds: Array = Catalog.ITEMS.keys()
	t0 = Time.get_ticks_usec()
	var made := []
	for i in 600:
		made.append(hud._card(kinds[i % kinds.size()]))
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	for b in made:
		b.free()
	print("INFO [%s] fixture-sized row: 600 cards in %.1f ms (test only)" % [tag, ms])
	check(ms < 1500.0, "600 cards build in %.1f ms" % ms)
	await frames(2)
