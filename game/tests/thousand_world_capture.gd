## Rendered frames of Thousand Town's world at the player's camera (design/thousand-town.md sections 6, 8, 9):
## the real game (TownWorld, the play controller, the camera rig's Thousand Town follow camera, the HUD and the
## child at 1.30 m) rides the tram to Thousand Town, then stands the child at chosen places and sets the time
## with the HUD's Day / Dusk / Night buttons. Each frame is saved as PNG with the renderer's own counts (draw
## calls, primitives, objects). EC2 evidence: Mesa llvmpipe software GL, so the look and the counts are real
## and the frame times are not; device feel is the Mac's and the iPad's.
##   xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 \
##       -s res://tests/thousand_world_capture.gd -- --shots=../build/dual-host/thousand-town/shots/world
extends "res://tests/puzzle_ride_tests.gd"

const Places := preload("res://scripts/core/places.gd")

var TownWorld: GDScript
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control
var shots := ""
var _lines: Array[String] = []


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	TownWorld = load("res://scripts/world/town_world.gd")
	shots = ProjectSettings.globalize_path("res://").path_join("../../shots/world")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
			if shots.is_relative_path():
				shots = ProjectSettings.globalize_path("res://").path_join(shots)
	DirAccess.make_dir_recursive_absolute(shots)
	_current = "capture"
	await _capture()
	for line in _lines:
		print(line)
	print("\nTHOUSAND WORLD CAPTURE: %d checks, %d failures; frames in %s" % [_checks, _failures, shots.simplify_path()])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _until(cond: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout:
			return false
	return true


func _build_game() -> void:
	holder = Node.new()
	holder.name = "Main"
	root.add_child(holder)
	var thumbs: Node = load("res://scripts/ui/thumbnails.gd").new()
	holder.add_child(thumbs)
	world = TownWorld.new()
	world.name = "World"
	holder.add_child(world)
	rig = load("res://scripts/world/camera_rig.gd").new()
	holder.add_child(rig)
	c = load("res://scripts/world/play_controller.gd").new()
	holder.add_child(c)
	c.setup(world, rig)
	var ui := CanvasLayer.new()
	holder.add_child(ui)
	hud = load("res://scripts/ui/hud.gd").new()
	ui.add_child(hud)
	hud.bind(c, thumbs)


func _mode(mode: String) -> void:
	var thousand := root.get_node("Thousand")
	if thousand.states.get("mode", "") != mode:
		(hud._thousand_time_btns[mode] as Button).pressed.emit()
		ok(await _until(func(): return thousand.states.get("mode", "") == mode, 4.0), "the %s button" % mode)


## Stands the child at p facing ry (Lantern Lane's yaw: forward (sin ry, cos ry)), the camera behind it.
func _stand(p: Vector2, ry: float) -> void:
	c.pos = p
	c.ry = ry
	c._place_kid()
	var kid: Node3D = world.local_kid()
	if kid and kid.has_method("set_target"):
		kid.set_target(kid.position, ry, true)
	rig.t_yaw = ry + PI
	rig._t_manual = 999.0   # hold the framing
	rig.snap()


func _shot(name: String, what: String) -> void:
	for i in 8:
		await process_frame
	var t0 := Time.get_ticks_usec()
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var img := root.get_viewport().get_texture().get_image()
	var path := shots.path_join(name + ".png")
	ok(img.save_png(path) == OK, "saved %s" % name)
	var tw: Node3D = world.thousand_world
	var kid: Node3D = world.local_kid()
	var cam: Camera3D = rig.camera
	# the same frame without the town: what the child, its label and shadow and the rest of the game draw
	tw.visible = false
	for i in 3:
		await process_frame
	var rest := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	if name.begins_with("01"):
		# what the rest of the game draws in Thousand Town, by its top node under the TownWorld
		var by := {}
		for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
			if not g.is_visible_in_tree():
				continue
			var top: Node = g
			while top.get_parent() != null and top.get_parent() != world and top.get_parent() != root:
				top = top.get_parent()
			var key := "%s/%s" % [top.get_parent().name if top.get_parent() else "", top.name]
			by[key] = int(by.get(key, 0)) + 1
		_lines.append("visible geometry outside the town, by top node: %s" % str(by))
	tw.visible = true
	for i in 3:
		await process_frame
	var at: Vector2 = cam.unproject_position(kid.global_position + Vector3(0, 0.65, 0)) if kid else Vector2.ZERO
	var size := root.get_viewport().get_visible_rect().size
	var in_frame := kid != null and not cam.is_position_behind(kid.global_position) and Rect2(Vector2.ZERO, size).has_point(at)
	ok(in_frame, "%s: the child is in the frame (%s)" % [name, at])
	var head: Vector2 = cam.unproject_position(kid.global_position + Vector3(0, 1.3, 0)) if kid else Vector2.ZERO
	_lines.append("%s.png | %s | %s %s | child at (%.1f, %.1f) %.0f px tall | %d draw calls (the town %d, the child and the rest of the game %d), %d primitives, %d objects | %.0f ms/frame (llvmpipe) | occluded %s | daylight %.2f lamps %.2f lit panes %d" % [
		name, what, Places.THOUSAND, str(tw.view_time().get("minute", 0.0)), c.pos.x, c.pos.y, absf(at.y - head.y), draws, draws - rest, rest, prims, objs, ms,
		str(tw.occluded()), float(tw.light.get("daylight", 0.0)), float(tw.light.get("lamps", 0.0)), int(tw.light.get("windows_lit", 0))])


func _capture() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://capture_thousand_world.json")
	await process_frame
	# the tram, as a player takes it
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 4.0), "the tram stop offers Thousand Town")
	hud._context_alt3_btn.pressed.emit()
	ok(await _until(func(): return c.space == Places.THOUSAND and c.journey_to == "", 180.0), "arrived in Thousand Town")
	var tw: Node3D = world.thousand_world
	ok(tw != null and tw.visible, "its world is shown")
	_lines.append("build: %s" % str(tw.stats()))
	var arr: Transform3D = tw.arrival()
	var a := Vector2(arr.origin.x, arr.origin.z)
	await _mode("day")
	_stand(a, PI / 2.0)
	await _shot("01_arrival_day", "arrival, the forecourt corner, looking east along the z = 0 street (Day 12:00)")
	_stand(Vector2(-44.6, -27.0), PI)
	await _shot("02_street_day", "a street: the avenue pavement looking north to the towers and the hospital (Day)")
	_stand(Vector2(-4.0, -20.0), PI / 2.0)
	await _shot("03_bridge_day", "the canal footbridge at z = -20, on the deck (0.975 m), looking east (Day)")
	await _mode("night")
	_stand(Vector2(-11.0, -44.0), PI)
	await _shot("04_market_night", "the night market on the west promenade, looking north (Night 21:30)")
	await _mode("dusk")
	_stand(Vector2(66.0, 48.0), 0.0)
	await _shot("05_wheel_dusk", "the ferris wheel from inside the amusement park, looking south (Dusk 18:40)")
	await _mode("night")
	_stand(a, PI / 2.0)
	await _shot("06_arrival_night", "arrival again at night, paired with 01 (Night 21:30)")
	await _mode("day")
	_stand(Vector2(30.0, 7.3), PI)
	await _shot("07_occluded_day", "against the mall's north face looking north: the camera, held at 4 m, is inside the mall's box, which is dithered (Day)")
	_stand(a, PI / 2.0)
	c.set_thousand_look(true)
	ok(await _until(func(): return not rig.thousand_gliding(), 4.0), "Look glides to the overview")
	await _shot("08_overview_day", "Look: the overview of the whole town (Day)")
	c.set_thousand_look(false)
