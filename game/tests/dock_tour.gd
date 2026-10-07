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
	while not main.thumbs.is_done:
		await get_tree().process_frame
	var save := "user://dock_town.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(save)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	print("INFO [%s] viewport %s, safe area %s" % [tag, get_viewport().get_visible_rect().size, area])
	c.set_mode("decorate")
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
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/dock_%s_%s.png" % [shots, tag, t[0]])
		await mouse(goal, false)
		await wait(1.6)
	# After letting go the camera recenters on the item and the tools return.
	check(hud.dock == "bottom", "tools back above the toy box after letting go")
	check(hud._catalog.visible, "toy box visible again")
	c.confirm_ghost()
	await wait(0.5)
	print("DOCK %s %s: %d failures" % [tag, "PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)
