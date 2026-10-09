## Focused check of the production models r2 (design/model-release-r2.md) through the real UI: in a
## house room, the toy box's Ceiling and On the wall filters list the new models; a chandelier, a
## string of paper lanterns and a ceiling fan are hung and an insect chart and an antler mount put on
## the wall by real taps; a room-high pavilion's ghost turns red under the chandelier (no room under
## the ceiling) and cannot be placed; in the evening the lamps light up. At most 8 shots.
## r15: a drapery is turned with Turn while being hung, turned again when edited (Done) and once more
## then cancelled (Cancel keeps the turn); a wall item ignores Turn. r16: next to a station clock on the left
## wall, a floor lamp's ghost turns red when turned 45 degrees (no room in front of the wall) and fits
## square; a photo
## taken with the camera comes back in the scrapbook from the device after the in-memory pictures are
## dropped (as after a restart). At most 10 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/furn_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path, --no-shots and
## --window=2208x1024 after --.
extends "res://tests/play_tour.gd"

const Catalog := preload("res://scripts/core/catalog.gd")

const R2_CEILING_SHOWN := ["crystal_chandelier", "paper_lantern_string", "ceiling_fan_light"]
const R2_WALL_SHOWN := ["insect_chart_poster", "antler_wall_mount"]


func shot(name: String) -> void:
	if _n >= 10 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/furn_%s_%02d_%s.png" % [shots, tag, _n, name])


## Framing: puts the child at p (as play2_tour's go()).
func go(p: Vector2) -> void:
	main.controller._walk_target = null
	main.controller._pending_ctx = {}
	main.controller.pos = p
	main.controller._place_kid()
	await wait(0.6)


## Transient feedback has faded (bounded), so evidence shows the room and the actual controls.
func feedback_settled() -> void:
	var hud: Control = main.hud
	check(await until(func(): return hud._toast.modulate.a <= 0.01, 5.0), "the last message has faded before the picture")
	await frames(3)


## While the placement tools show, a message never covers them (r13 Mac: the placed message sat
## over Turn and Place here). Sampled on each of n frames.
func toast_clear_of_tools(what: String, n := 20) -> void:
	var hud: Control = main.hud
	var worst := ""
	for i in n:
		await get_tree().process_frame
		if hud._toast.modulate.a > 0.01 and hud._tools.is_visible_in_tree():
			var t: Rect2 = hud._toast.get_global_rect()
			var tools: Rect2 = hud._tools_col.get_global_rect()
			if t.intersects(tools):
				worst += "frame %d alpha %.2f %s over %s; " % [i, hud._toast.modulate.a, t, tools]
	check(worst == "", "%s: no message covers the placement tools (%s)" % [what, worst if worst != "" else "clear"])


## Every visible toy box card shows its whole name: broken only between words, every line shown,
## nothing trimmed, inside the card; and no two cards read the same.
func cards_readable(what: String) -> void:
	var hud: Control = main.hud
	var cards: Array = hud._cards.get_children().filter(func(b): return b.has_meta("kind"))
	var bad := []
	var seen := {}
	var dup := []
	for b in cards:
		var labels: Array = b.find_children("*", "Label", true, false)
		if labels.size() != 1:
			bad.append("%s: %d labels" % [b.get_meta("kind"), labels.size()])
			continue
		var l: Label = labels[0]
		var shown := tr(l.text)
		if l.autowrap_mode != TextServer.AUTOWRAP_WORD or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING \
				or l.get_line_count() > 3 or l.get_visible_line_count() < l.get_line_count() \
				or not b.get_global_rect().grow(0.5).encloses(l.get_global_rect()) or l.get_minimum_size().y > l.size.y + 0.5:
			bad.append("%s (%d of %d lines)" % [shown, l.get_visible_line_count(), l.get_line_count()])
		if seen.has(shown):
			dup.append(shown)
		seen[shown] = true
	check(not cards.is_empty() and bad.is_empty(), "%s: all %d cards show their whole names (%s)" % [what, cards.size(), bad])
	check(dup.is_empty(), "%s: no two cards read the same (%s)" % [what, dup])


## Opens the toy box on a tab with a placement filter (Ceiling, On the wall) by real taps.
func open_filtered(tab: String, placement: String) -> void:
	var hud: Control = main.hud
	if main.controller.mode != "decorate":
		await press(hud._decorate_btn)
	await press(await scrolled_to(find_button(hud._tabs, "tab", tab)))
	await frames(3)
	var chip: Button = find_button(hud._tabs, "placement", placement)
	check(chip != null, "the %s tab offers the %s filter" % [tab, placement])
	if chip and hud._placement != placement:
		await press(await scrolled_to(chip))
		await frames(3)
	check(hud._placement == placement, "the %s filter is on" % placement)


## Hangs one item from the open, filtered toy box: its card, the ghost on a free spot, Place here.
func hang(kind: String, near: Vector2) -> String:
	var hud: Control = main.hud
	var c: Node = main.controller
	var card: Button = find_button(hud._cards, "kind", kind)
	check(card != null, "the toy box shows %s" % kind)
	if card == null:
		return ""
	# Framing (as in play3): the child stands so the new ghost appears on the wanted spot, facing
	# into the room (toward the back wall for wall items). The ghost's tool panel covers the middle
	# of the screen, so a floor tap is only the fallback.
	var r: float = Catalog.get_def(kind)["radius"] + 1.2
	c.ry = PI if Catalog.anchor(kind) == "wall" else 0.0
	await go(near + Vector2(0, r) if Catalog.anchor(kind) == "wall" else near - Vector2(0, r))
	c.ry = PI if Catalog.anchor(kind) == "wall" else 0.0
	var before: Array = Session.model.items.keys()
	await press(await scrolled_to(card))
	await frames(3)
	if c.g_error != "":
		# A tap on the floor moves the ghost there (the game's decorate input), guarded as reachable.
		await settle_camera()
		var goal: Vector2 = main.rig.camera.unproject_position(Vector3(near.x, 0, near.y))
		var bl := ui_blocker_at(goal)
		if bl != "":
			var bn: Control = main.hud.find_child(bl, true, false)
			print("DIAG blocker %s path %s rect %s filter %d texts %s" % [bl, main.hud.get_path_to(bn), bn.get_global_rect(), bn.mouse_filter, bn.find_children("*", "Label", true, false).map(func(x): return x.text) + bn.find_children("*", "Button", true, false).map(func(x): return x.text)])
		await tap_at_world(Vector3(near.x, 0, near.y), "the floor under the %s spot" % kind)
		await frames(3)
	print("DIAG ghost for %s at %s (%s)" % [kind, c.g_pos, c.g_error if c.g_error != "" else "fits"])
	check(c.g_error == "", "%s can hang where it is shown (%s)" % [kind, c.g_error])
	await press(hud._place_btn)
	await until(func(): return Session.model.items.size() > before.size(), 5.0)
	var made: Array = Session.model.items.keys().filter(func(k): return not before.has(k) and Session.model.items[k]["kind"] == kind)
	check(not made.is_empty(), "hung %s" % kind)
	if c.mode == "decorate":
		await press(hud._decorate_btn)   # Done
	return made[0] if not made.is_empty() else ""


## r16c: a script error (e.g. a freed node passed to a helper) ends only the case function it happens
## in, and the tour would go on to report PASS. Each case sets this flag as its last line, so a case that
## stopped early (script error or a missing precondition) is a failure of the tour.
var _case_done := false


func case_ended(what: String) -> void:
	check(_case_done, "the %s case ran to its end" % what)
	_case_done = false


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("FURN %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://furn_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	var room := TownModel.room_space(houses[0]["id"], 0, 0)
	c.go_to_room(room)
	await wait(1.0)
	check(c.space == room, "inside the first house's living room")
	_case_done = false
	await _hang_items(hud, c, room)
	case_ended("hanging items")
	await _turns(hud, c, room)
	case_ended("turns")
	await _headroom(hud, c, room)
	case_ended("headroom")
	await _wall_clearance(hud, c, room)
	case_ended("wall clearance")
	await _evening(c, room)
	case_ended("evening")
	await _scrapbook_restart(hud)
	case_ended("scrapbook restart")
	for loc in locales:
		await _cards_r2(loc, hud, area)
		case_ended("[%s] toy box names" % loc)
	print("FURN %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


func _hang_items(hud: Control, c: Node, room: String) -> void:
	await open_filtered("Cozy things", "ceiling")
	var cards: Array = hud._cards.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("kind")).map(func(b): return b.get_meta("kind"))
	check(cards.size() == 39 and cards.all(func(k): return Catalog.anchor(k) == "ceiling"), "the Ceiling filter lists the 38 new hanging items and the bird mobile (%d)" % cards.size())
	await cards_readable("Ceiling")
	await shot("toybox_ceiling")
	# The chandelier hangs over the one stretch of this room where a room-high pavilion could stand
	# (clear of the doors and stairs), so the headroom rule is what refuses it there.
	var spots := [Vector2(-1.5, 0.5), Vector2(1.5, -0.8), Vector2(1.3, 1.6)]
	var ids := []
	for i in R2_CEILING_SHOWN.size():
		ids.append(await hang(R2_CEILING_SHOWN[i], spots[i]))
		await open_filtered("Cozy things", "ceiling")
	for id in ids:
		var it: Dictionary = Session.model.items.get(id, {})
		check(not it.is_empty() and is_equal_approx(it.get("y", 0.0), TownModel.CEILING_Y) and it["space"] == room, "%s hangs from the ceiling of this room" % it.get("kind", "?"))
	await open_filtered("Cozy things", "wall")
	for i in R2_WALL_SHOWN.size():
		var id := await hang(R2_WALL_SHOWN[i], Vector2(-1.8 + i * 1.6, -2.4))
		var it: Dictionary = Session.model.items.get(id, {})
		check(not it.is_empty() and (it["z"] == -TownModel.ROOM_HALF.y or it["x"] == -TownModel.ROOM_HALF.x) and is_equal_approx(it["y"], Catalog.get_def(it["kind"])["mount_height"]), "%s hangs on a wall at %.2f m" % [it.get("kind", "?"), it.get("y", 0.0)])
		await open_filtered("Cozy things", "wall")
	if c.mode == "decorate":
		await press(hud._decorate_btn)   # Done
	await settle_camera()
	for id in Session.model.items_in(room).map(func(i): return i["id"]):
		var n: Node3D = main.world.item_nodes.get(id)
		var it: Dictionary = Session.model.items[id]
		if Catalog.anchor(it["kind"]) != "ground":
			check(n != null and absf(n.global_position.y - it["y"]) < 0.01, "%s is drawn at its height in the room" % it["kind"])
	await feedback_settled()
	await settle_camera()
	await shot("room_day")
	_case_done = true   # r16c: the runner checks each case ran to its end


## The pavilion's ghost turns red under the chandelier and cannot be placed there.
func _headroom(hud: Control, c: Node, room: String) -> void:
	var chs: Array = Session.model.items_in(room).filter(func(i): return i["kind"] == "crystal_chandelier")
	check(chs.size() == 1, "the chandelier from the first case hangs in the room (%d)" % chs.size())
	if chs.size() != 1:
		return
	var ch: Dictionary = chs[0]
	if c.mode != "decorate":
		await press(hud._decorate_btn)
	await press(await scrolled_to(find_button(hud._tabs, "tab", "Furniture")))
	await frames(3)
	if live_card("garden_pavilion") == null:
		await press(await scrolled_to(find_button(hud._tabs, "tab", "Furniture")))
		await frames(3)
	check(live_card("garden_pavilion") != null, "the pavilion is in the toy box")
	if live_card("garden_pavilion") == null:
		return
	# Framing: the camera follows the child, and the ghost's tool panel covers the middle of the
	# screen, so the child stands to the side of the chandelier and the spot in front of it shows left of the panel.
	c.ry = 0.0
	await go(Vector2(ch["x"] + 2.8, ch["z"] + 1.0))
	var before: int = Session.model.items.size()
	# r16c: the strip can be rebuilt while the child walks (0.6 s), freeing the card found above (the
	# r16b Mac script error). The card is looked up again now and the pavilion ghost is verified.
	await press_card("garden_pavilion")
	if c.ghost == null or c.g_kind != "garden_pavilion":
		return
	await frames(3)
	await settle_camera()
	# A floor tap in front of the chandelier, clear of its own pick area (a tap on an existing item
	# does not move a ghost): the pavilion's 1.3 m footprint still reaches under it.
	await tap_at_world(Vector3(ch["x"] - 0.1, 0, ch["z"] + 1.1), "the floor in front of the chandelier")
	await frames(3)
	check(c.g_error == TownModel.ERR_HEADROOM, "under the chandelier the ghost says there is no room under the ceiling (%s at %s)" % [c.g_error, c.g_pos])
	await toast_clear_of_tools("the pavilion ghost")
	# A message arriving while the tools show (here the game's own place-refusal path is a hint, so
	# the shared toast is raised the way other feedback raises it) moves clear of them.
	hud.show_toast(tr("Placed! Pick another, or tap Done."))
	await toast_clear_of_tools("a message during placement")
	await feedback_settled()
	check(hud._place_btn.is_visible_in_tree() and hud._place_btn.disabled and hud._hint_panel.is_visible_in_tree(), "Place here is shown but off, with the reason above it")
	await shot("headroom_red")
	await press(hud._place_btn)
	await frames(10)
	check(Session.model.items.size() == before, "nothing is built there")
	c.cancel_ghost()
	await frames(3)
	if c.mode == "decorate":
		await press(hud._decorate_btn)
	_case_done = true   # r16c: the runner checks each case ran to its end


## Evening: the hung lamps light up (Light0), the decorations do not.
func _evening(c: Node, room: String) -> void:
	Session.ring_bell()   # setup only: the bell flow itself is covered by the capture tour
	check(await until(func(): return Session.model.evening, 5.0), "it is evening")
	await wait(2.5)
	var lit := []
	var dark := []
	for it in Session.model.items_in(room):
		if Catalog.anchor(it["kind"]) == "ground":
			continue
		var n: Node3D = main.world.item_nodes.get(it["id"])
		var lights: Array = n.find_children("*", "OmniLight3D", true, false) if n else []
		if lights.is_empty():
			dark.append(it["kind"])
		elif lights.all(func(l): return l.light_energy > 0.5):
			lit.append(it["kind"])
	lit.sort()
	check(lit == ["ceiling_fan_light", "crystal_chandelier", "paper_lantern_string"], "the three hanging lamps glow in the evening (%s)" % [lit])
	check(dark.has("insect_chart_poster") and dark.has("antler_wall_mount"), "the wall decorations have no lamp")
	await settle_camera()
	await shot("room_evening")
	_case_done = true   # r16c: the runner checks each case ran to its end


func _cards_r2(loc: String, hud: Control, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	await open_filtered("Cozy things", "ceiling")
	var cards: Array = hud._cards.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("kind"))
	check(cards.all(func(b): return tr(Catalog.get_def(b.get_meta("kind"))["name"]) != Catalog.get_def(b.get_meta("kind"))["name"] or loc == "en"), "[%s] the hanging items have translated names" % loc)
	await cards_readable("[%s] Ceiling" % loc)
	if loc == "de":
		# The two cards the r13 Mac picture showed as identical "Hängelampe mit..." now read in full.
		for k in ["drum_shade_pendant", "cone_shade_pendant"]:
			var card: Button = find_button(hud._cards, "kind", k)
			var l: Label = card.find_children("*", "Label", true, false)[0] if card else null
			check(l != null and tr(l.text) == tr(Catalog.get_def(k)["name"]) and l.get_visible_line_count() == l.get_line_count(), "[de] %s reads in full: %s" % [k, tr(Catalog.get_def(k)["name"])])
		await scrolled_to(find_button(hud._cards, "kind", "drum_shade_pendant"))
		await frames(3)
	var view: Control = hud._cards
	while view != null and not view is ScrollContainer:
		view = view.get_parent()
	var r: Rect2 = view.get_global_rect() if view else Rect2()
	check(view != null and area.grow(0.5).encloses(r), "[%s] the toy box card strip stays inside the safe area (%s)" % [loc, r])
	await shot("%s_toybox_ceiling" % loc)
	await press(hud._decorate_btn)
	_case_done = true   # r16c: the runner checks each case ran to its end


## A placement tool button (Turn, Cancel) by its English label, checked touch-safe and inside the safe area.
func tool_button(label: String) -> Button:
	var hud: Control = main.hud
	for b in hud._tools.find_children("*", "Button", true, false):
		if b.text == label and b.is_visible_in_tree():
			var r: Rect2 = b.get_global_rect()
			check(r.size.x >= 52.0 and r.size.y >= 52.0 and hud.get_global_rect().grow(0.5).encloses(r), "%s is touch-safe and inside the safe area (%s)" % [label, r])
			return b
	check(false, "the placement tools show %s" % label)
	return null


## The ghost's drawn turn matches its rot once the Turn animation has finished.
func ghost_turn_matches(c: Node) -> bool:
	var model: Node3D = c.ghost.get_node("Model") if c.ghost else null
	return model != null and absf(wrapf(model.rotation.y - TownModel.rot_to_radians(c.g_rot), -PI, PI)) < 0.02


## r15: turning ceiling items while hanging them, when editing (Done) and editing then cancelling.
func _turns(hud: Control, c: Node, room: String) -> void:
	# Hang a long drapery, turned twice (90 degrees) before placing.
	await open_filtered("Cozy things", "ceiling")
	var card: Button = find_button(hud._cards, "kind", "swag_drapery")
	check(card != null, "the toy box shows the drapery")
	if card == null:
		return
	c.ry = 0.0
	await go(Vector2(-1.4, -1.6) - Vector2(0, Catalog.get_def("swag_drapery")["radius"] + 1.2))
	c.ry = 0.0
	var before: Array = Session.model.items.keys()
	await press_card("swag_drapery")   # the cards are rebuilt while the child moves
	await frames(3)
	check(c.ghost != null and c.g_rot == 0, "the drapery ghost starts unturned")
	var turn := tool_button("Turn")
	for i in 2:
		await press(turn)
		await wait(0.25)   # the Turn animation (0.15 s)
	check(c.g_rot == 2 and ghost_turn_matches(c) and c.g_error == "", "Turn twice: the ghost is turned a quarter (rot %d) and still fits" % c.g_rot)
	await press(hud._place_btn)
	await until(func(): return Session.model.items.size() > before.size(), 5.0)
	var made: Array = Session.model.items.keys().filter(func(k): return not before.has(k) and Session.model.items[k]["kind"] == "swag_drapery")
	check(made.size() == 1 and Session.model.items[made[0]]["rot"] == 2, "hung turned a quarter (rot %s)" % (Session.model.items[made[0]]["rot"] if made.size() else "?"))
	if made.is_empty():
		return
	var id: String = made[0]
	if c.mode == "decorate":
		await press(hud._decorate_btn)   # Done
	await settle_camera()
	var node: Node3D = main.world.item_nodes.get(id)
	check(node != null and absf(wrapf(node.rotation.y - TownModel.rot_to_radians(2), -PI, PI)) < 0.02, "the hung drapery is drawn turned a quarter")
	# r16: the placement message fades before the picture (r15 Mac 03: it covered the drapery).
	await feedback_settled()
	await settle_camera()
	await shot("ceiling_turned")
	# Edit: tap it, Turn once, Done -> rot 3 (another 45 degrees).
	await press(hud._decorate_btn)
	await settle_camera()
	await tap_at_world(node.global_position + Vector3(0, -0.2, 0), "the hung drapery")
	check(await until(func(): return c.g_edit_id == id, 5.0), "tapping the drapery picks it up to edit")
	await press(tool_button("Turn"))
	await wait(0.25)
	check(c.g_rot == 3 and ghost_turn_matches(c), "Turn while editing: rot 3")
	await shot("ceiling_edit_turn")
	await press(hud._place_btn)   # Done
	check(await until(func(): return Session.model.items[id]["rot"] == 3, 5.0), "Done keeps the new turn (rot %d)" % Session.model.items[id]["rot"])
	# Edit again, Turn, Cancel -> unchanged.
	await settle_camera()
	node = main.world.item_nodes.get(id)
	await tap_at_world(node.global_position + Vector3(0, -0.2, 0), "the hung drapery")
	check(await until(func(): return c.g_edit_id == id, 5.0), "picked up again")
	await press(tool_button("Turn"))
	await wait(0.25)
	check(c.g_rot == 4, "turned once more in the ghost (rot 4)")
	await press(tool_button("Cancel"))
	await frames(10)
	node = main.world.item_nodes.get(id)
	check(c.ghost == null and Session.model.items[id]["rot"] == 3 and node != null and node.visible and absf(wrapf(node.rotation.y - TownModel.rot_to_radians(3), -PI, PI)) < 0.02, "Cancel leaves it as it was (rot %d, drawn at rot 3)" % Session.model.items[id]["rot"])
	# A wall item still ignores Turn (it faces into the room).
	await open_filtered("Cozy things", "wall")
	var wcard: Button = find_button(hud._cards, "kind", "bone_doorplate")
	if wcard:
		c.ry = PI
		await go(Vector2(1.6, -2.4) + Vector2(0, Catalog.get_def("bone_doorplate")["radius"] + 1.2))
		c.ry = PI
		await press_card("bone_doorplate")
		await frames(3)
		print("DIAG doorplate card pressed: ghost %s kind %s mode %s cards %s" % [c.ghost != null, c.g_kind, c.mode, main.hud._cards.get_children().filter(func(x): return not x.is_queued_for_deletion()).map(func(x): return x.get_meta("kind", "")).slice(0, 6)])
		check(c.ghost != null and c.g_kind == "bone_doorplate", "the doorplate's ghost is out")
		var r0: int = c.g_rot
		await press(tool_button("Turn"))
		await wait(0.25)
		check(c.g_rot == r0, "Turn does not turn a wall item (rot %d)" % c.g_rot)
		await press(tool_button("Cancel"))
		await frames(5)
	if c.mode == "decorate":
		await press(hud._decorate_btn)
	_case_done = true   # r16c: the runner checks each case ran to its end


## r16: wall clearance through the real UI, without drags (the camera follows a dragged ghost, so a spot
## next to it can sit under the tool panel). A 46 cm deep station clock is hung on the left wall; a
## floor lamp's ghost fits beside it unturned, turns red at 45 degrees (its corner reaches the clock) and
## fits again at 90 degrees.
func _wall_clearance(hud: Control, c: Node, room: String) -> void:
	# The clock on the left wall at z 1.5 (clear of the window and the side door).
	await open_filtered("Cozy things", "wall")
	c.ry = -PI / 2.0
	await go(Vector2(-3.6 + Catalog.get_def("station_wall_clock")["radius"] + 1.2, 1.5))
	c.ry = -PI / 2.0
	var before: Array = Session.model.items.keys()
	await press_card("station_wall_clock")
	await frames(3)
	print("DIAG ghost for station_wall_clock at %s (%s)" % [c.g_pos, c.g_error if c.g_error != "" else "fits"])
	await press(hud._place_btn)
	await until(func(): return Session.model.items.size() > before.size(), 5.0)
	var clocks: Array = Session.model.items_in(room).filter(func(i): return i["kind"] == "station_wall_clock")
	check(clocks.size() == 1 and clocks[0]["x"] == -TownModel.ROOM_HALF.x, "a station clock hangs on the left wall (%s)" % [clocks.map(func(i): return [i["x"], i["z"]])])
	if clocks.is_empty():
		return
	var cz: float = clocks[0]["z"]
	if c.mode == "decorate":
		await press(hud._decorate_btn)
	# The lamp's ghost beside it, unturned: fits.
	await open_filtered("Cozy things", "floor")
	c.ry = -PI / 2.0
	await go(Vector2(-3.25 + Catalog.get_def("floor_lamp")["radius"] + 1.2, cz))
	c.ry = -PI / 2.0
	var n: int = Session.model.items.size()
	await press_card("floor_lamp")
	await frames(3)
	print("DIAG ghost for floor_lamp at %s rot %d (%s)" % [c.g_pos, c.g_rot, c.g_error if c.g_error != "" else "fits"])
	check(c.ghost != null and c.g_pos.distance_to(Vector2(-3.25, cz)) < 0.3 and c.g_error == "", "the lamp's ghost fits beside the clock, unturned")
	# Turned 45 degrees its corner reaches into the clock's space: refused, Place here off.
	await press(tool_button("Turn"))
	await wait(0.25)
	check(c.g_rot == 1 and c.g_error == TownModel.ERR_WALL_CLEARANCE, "turned 45 degrees, the ghost says there is no room in front of the wall (%s)" % c.g_error)
	await feedback_settled()
	check(hud._place_btn.disabled and hud._hint_panel.is_visible_in_tree(), "Place here is off, with the reason shown")
	await shot("wall_clearance_red")
	await press(hud._place_btn)
	await frames(10)
	check(Session.model.items.size() == n, "nothing is placed there")
	# Turned again (square to the wall) it fits.
	await press(tool_button("Turn"))
	await wait(0.25)
	check(c.g_rot == 2 and c.g_error == "", "turned square again the lamp fits (%s)" % c.g_error)
	await press(tool_button("Cancel"))
	await frames(5)
	if c.mode == "decorate":
		await press(hud._decorate_btn)
	_case_done = true   # r16c: the runner checks each case ran to its end


## The toy box card of a kind that is on screen now (not one being freed after a rebuild).
func live_card(kind: String) -> Button:
	for b in main.hud._cards.get_children():
		if b.get_meta("kind", "") == kind and not b.is_queued_for_deletion() and b.is_visible_in_tree():
			return b
	return null


## Presses the card of a kind and checks that this kind's ghost came out. The strip is rebuilt now and
## then (recently used items move to the front), so a tap can meet another card; then that ghost is
## cancelled with the real Cancel button and the card is pressed again (at most three tries, logged).
func press_card(kind: String) -> void:
	var c: Node = main.controller
	for attempt in 3:
		var b := live_card(kind)
		if b == null:
			await frames(2)
			continue
		await scrolled_to(b)
		b = live_card(kind)
		if b == null:
			continue
		await press(b)
		await frames(2)
		if c.ghost != null and c.g_kind == kind:
			return
		print("DIAG press_card %s: try %d gave %s; the strip was rebuilt under the tap" % [kind, attempt + 1, c.g_kind if c.ghost else "no ghost"])
		if c.ghost != null:
			await press(tool_button("Cancel"))
			await frames(3)
	check(false, "the toy box card for %s gives its ghost" % kind)


## Drags the ghost onto a floor point with real guarded drags until it is there (at most three). First
## the child stands where that point shows on screen clear of the HUD (the tool panel covers the middle).
func drag_ghost_to(c: Node, target: Vector2, what: String) -> void:
	for off in [Vector2(2.6, 1.3), Vector2(3.2, 0.6), Vector2(-2.6, 1.3), Vector2(2.0, 2.2), Vector2(-2.0, 2.2)]:
		var spot: Vector2 = (target + off).clamp(-TownModel.ROOM_HALF + Vector2(0.5, 0.5), TownModel.ROOM_HALF - Vector2(0.5, 0.5))
		await go(spot)
		await settle_camera()
		var aim: Vector2 = main.rig.camera.unproject_position(Vector3(target.x, 0, target.y))
		if playable_rect().has_point(aim) and ui_blocker_at(aim) == "":
			break
	for attempt in 3:
		if c.ghost == null or c.g_pos.distance_to(target) < 0.13:
			break
		await settle_camera()
		await drag_world(c.ghost.global_position + Vector3(0, 0.4, 0), Vector3(target.x, 0, target.y), what)
		await frames(3)
	print("DIAG %s: ghost at %s (target %s)" % [what, c.g_pos, target])


func tooltip_btn(root: Node, tip: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.tooltip_text == tip and b.is_visible_in_tree():
			return b
	return null


## r16: a photo kept on the device is shown again after the in-memory pictures are gone (a restart).
func _scrapbook_restart(hud: Control) -> void:
	var PS = load("res://scripts/core/photo_store.gd")
	var before: Array = PS.list()
	if main.args.has("no-shots"):
		# Headless has no picture to take; the store keeps a stand-in so the scrapbook path is the same.
		var img := Image.create(240, 160, false, Image.FORMAT_RGBA8)
		img.fill(Color.SANDY_BROWN)
		PS.save(img)
		print("DIAG no renderer: the photo is made by the store directly")
	else:
		var cam := tooltip_btn(hud, "Take a photo")
		check(cam != null, "the camera button is there")
		if cam:
			await press(cam)
	check(await until(func(): return PS.list().size() == before.size() + 1, 5.0), "the photo is kept on this device (%d -> %d)" % [before.size(), PS.list().size()])
	var newest: String = PS.list()[-1] if not PS.list().is_empty() else ""
	await feedback_settled()
	# As after a restart: nothing of the photos is left in memory.
	hud._photos.clear()
	hud._photo_thumbs.clear()
	await press(hud._lantern_btn)
	await frames(4)
	var shown: Array = hud._overlay.find_children("*", "TextureRect", true, false).filter(func(r): return r.has_meta("photo") and r.texture != null)
	check(not shown.is_empty() and hud._photo_thumbs.has(newest) and shown[-1].texture == hud._photo_thumbs[newest], "the scrapbook shows the newest photo again, read from the device (%s)" % newest)
	await shot("scrapbook_restored")
	await close_dialogs()
	_case_done = true   # r16c: the runner checks each case ran to its end

