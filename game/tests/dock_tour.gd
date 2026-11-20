## Rendered check that the placement tools never cover the item being placed.
## Drags a table with real mouse events (finger held down) to screen positions
## across both halves and the edges, then checks overlap, button reachability,
## stability while holding still, and the return to the usual layout.
##   xvfb-run -a -s "-screen 0 2300x1100x24" scripts/godot.sh --path game --resolution 2208x1024 -- \
##       --driver=res://tests/dock_tour.gd --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55
extends Node

const PlacementDock := preload("res://scripts/ui/placement_dock.gd")

var main: Node
var failures := 0
var shots := ""
var tag := ""
var _switches := 0


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


func mouse(pos: Vector2, pressed: Variant = null) -> void:
	var e: InputEvent
	if pressed == null:
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = m
	else:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		e = b
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame


func ghost_screen() -> Vector2:
	var c: Node = main.controller
	return main.rig.camera.unproject_position(c.ghost.global_position + Vector3(0, 0.4, 0))


func visible_rect(ctrl: Control) -> Rect2:
	return ctrl.get_global_rect() if ctrl.is_visible_in_tree() else Rect2()


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	if main.args.has("window"):
		# --window=WxH: the device geometry without a renderer (headless ignores --resolution).
		var wh: PackedStringArray = str(main.args["window"]).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	while not main.thumbs.is_done and not main.args.has("no-shots"):
		await get_tree().process_frame
	var save := "user://dock_town.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(save)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	print("INFO [%s] viewport %s, safe area %s" % [tag, get_viewport().get_visible_rect().size, area])
	c.set_mode("decorate")
	# A thing placed at once: the toy box steps aside while it is held and comes back when it is
	# placed. (The closing lines of this tour can only show the "put back" half: the table ends too
	# close to the town's edge to be placed.)
	var items_before: int = Session.model.items.size()
	c.begin_new("table")
	await wait(1.5)
	# first-steps r8: which of the tools' two places depends on where the child stands (r7: always the
	# bottom edge, which hid a child standing there). What is required is what the place is for.
	check(c.ghost != null and hud.dock in ["low", "top"] and not hud._catalog.visible, "while a thing is held the tools are at the bottom edge or at the top and the toy box is tucked away (dock %s)" % hud.dock)
	var me0: Rect2 = hud.avatar_screen_rect()
	var tools0 := visible_rect(hud._tools_col)
	check(tools0.has_area() and not tools0.intersects(hud.ghost_screen_rect()) and not (me0.has_area() and tools0.intersects(me0)), "with the thing just picked the tools cover neither it nor the child (tools %s, item %s, child %s, dock %s)" % [tools0, hud.ghost_screen_rect(), me0, hud.dock])
	check(c.g_error == "", "set up: the first table can be placed where it appears (%s)" % c.g_error)
	c.confirm_ghost()
	await wait(1.0)
	check(c.ghost == null and Session.model.items.size() == items_before + 1 and hud._catalog.visible and hud.dock == "bottom", "toy box visible again once the thing is placed (things %d -> %d, dock %s)" % [items_before, Session.model.items.size(), hud.dock])
	c.begin_new("table")
	await wait(1.5)
	var last_dock: String = hud.dock
	var targets := [["low_center", 0.5, 0.8], ["bottom_edge", 0.5, 0.93], ["low_left", 0.06, 0.85], ["low_right", 0.8, 0.85],
		["middle", 0.5, 0.5], ["high_center", 0.5, 0.25], ["high_left", 0.06, 0.3], ["right_edge", 0.95, 0.55]]
	for t in targets:
		var goal: Vector2 = area.position + area.size * Vector2(t[1], t[2])
		# Press on the item, then drag slowly like a finger.
		var start := ghost_screen()
		await mouse(start, true)
		var steps := 30
		_switches = 0
		var last_switch_t := -99.0
		last_dock = hud.dock
		for i in range(1, steps + 1):
			await mouse(start.lerp(goal, float(i) / steps))
			if hud.dock != last_dock:
				var now := Time.get_ticks_msec() / 1000.0
				if now - last_switch_t < 0.8:
					_switches += 1   # a flip straight back: oscillation
				last_switch_t = now
				last_dock = hud.dock
				print("SWITCH [%s] %s step %d -> %s item %s zones %s" % [tag, t[0], i, hud.dock, hud.ghost_screen_rect(), hud.zones()])
		await wait(0.6)
		# Holding still must not make the menu move.
		var held: String = hud.dock
		for i in 20:
			await get_tree().process_frame
		check(hud.dock == held, "%s: menu stays put while the finger holds still" % t[0])
		# An item held in the lower part of the screen sends the tools up, wherever it is side to side,
		# as it did until first-steps r5 (r4's logs: "dock top" for these four at both layouts): the
		# whole strip at the bottom edge is cleared, not only the part under the tools.
		if str(t[0]) in ["low_center", "bottom_edge", "low_left", "low_right"]:
			check(hud.dock == "top", "%s: an item in the lower part of the screen sends the tools to the top (dock %s)" % [t[0], hud.dock])
		check(_switches == 0, "%s: no flip-flopping during the drag" % t[0])
		var ghost: Rect2 = hud.ghost_screen_rect()
		var tools := visible_rect(hud._tools_col)
		var catalog := visible_rect(hud._catalog)
		check(not ghost.intersects(tools), "%s: tools do not cover the item (tools %s, item %s, dock %s)" % [t[0], tools, ghost, hud.dock])
		check(not ghost.intersects(catalog), "%s: toy box does not cover the item" % t[0])
		# Confirm, cancel and turn remain on screen inside the safe area.
		# Cancel is found by its label: the row also holds buttons hidden while placing (Gift).
		var cancel_btn: Button = hud._tools_row.get_children().filter(func(x): return x is Button and x.text == "Cancel")[0]
		for b in [hud._place_btn, hud._tools_row.get_child(0), cancel_btn]:
			check(b.is_visible_in_tree() and area.encloses(b.get_global_rect()), "%s: '%s' reachable" % [t[0], b.text])
		if not main.args.has("no-shots"):   # --no-shots: the same checks without a renderer (headless)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/dock_%s_%s.png" % [shots, tag, t[0]])
		await mouse(goal, false)
		await wait(1.6)
	# After letting go the camera recenters on the item and the tools take the place that suits the
	# picture at rest. Until first-steps r5 that was above the toy box, with the toy box shown again at
	# once ("tools back above the toy box after letting go", "toy box visible again"). Since r7 the toy
	# box stays tucked away for as long as the thing is held, and r7 required "tools back at the bottom
	# edge after letting go". Since r8 the place at rest is chosen by where the child stands (bottom
	# edge, or top when the child stands at the bottom edge), so that line now asks for what the place
	# is for: one of the two places, the item clear, the child clear. (Declared in the r8 request: a
	# deliberate change of behaviour, not a way round a failure.)
	check(hud.dock in ["low", "top"], "after letting go the tools are at the bottom edge or at the top (dock %s)" % hud.dock)
	var rest: Rect2 = hud.ghost_screen_rect()
	check(rest.has_area() and not rest.intersects(visible_rect(hud._tools_col)) and not rest.intersects(visible_rect(hud._catalog)),
		"after letting go neither the tools nor the toy box cover the item (tools %s, item %s)" % [visible_rect(hud._tools_col), rest])
	var me: Rect2 = hud.avatar_screen_rect()
	print("INFO [%s] at rest: dock %s, tools %s, item %s, child %s" % [tag, hud.dock, visible_rect(hud._tools_col), rest, me])
	check(not (me.has_area() and visible_rect(hud._tools_col).intersects(me)), "after letting go the tools do not cover the child either (tools %s, child %s, dock %s)" % [visible_rect(hud._tools_col), me, hud.dock])
	if c.g_error == "":
		c.confirm_ghost()
	else:
		print("INFO [%s] the item cannot be placed here (%s): it is put back instead" % [tag, c.g_error])
		c.cancel_ghost()
	await wait(0.5)
	check(c.ghost == null and hud._catalog.visible and hud.dock == "bottom", "toy box visible again once the thing is put back (or placed)")
	print("DOCK %s %s: %d failures" % [tag, "PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)
