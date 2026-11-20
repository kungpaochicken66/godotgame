## Rendered frames of Thousand Town's events (world/thousand_events.gd; design/thousand-town.md sections 8, 9)
## through the real game, as tests/thousand_world_capture.gd does: TownWorld, the play controller, the camera
## rig, the HUD and the child ride the tram from the town stop to Thousand Town. This capture then adds the
## events node under the Thousand world the way the integration will (drive = true: it reads the world's
## view_time() and the viewport camera every frame), stands the child at the events' watch points and sets the
## time with the HUD's Day / Night buttons; held minutes other than the presets are written into the
## authority's clock (Thousand.clock, then _publish), as the HUD's Auto would reach them.
## The fireworks frames use watch_point("fireworks").camera (watch_camera(): behind the child, tilted up to
## the sky), standing in for the "Watch" interaction the lead adds; frame 06 is the plain follow camera at the
## same spot for comparison. The show second is pinned (pin_show_seconds) to the moment, within the show, that
## puts the most sparks in that frame, so the frame is reproducible.
## Each frame is saved as PNG with the renderer's own counts: draw calls, primitives and objects, and the
## events' own share (the same frame with the events node hidden).
## EC2 evidence: Mesa llvmpipe software GL. The look and the counts are real; the frame times are not.
##   xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 \
##       -s res://tests/thousand_events_capture.gd -- --shots=../../shots/events
extends "res://tests/puzzle_ride_tests.gd"

const Places := preload("res://scripts/core/places.gd")
const Events := preload("res://scripts/world/thousand_events.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")

var TownWorld: GDScript
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control
var ev: Node3D
var shots := ""
var _lines: Array[String] = []


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	TownWorld = load("res://scripts/world/town_world.gd")
	shots = ProjectSettings.globalize_path("res://").path_join("../../shots/events")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
			if shots.is_relative_path():
				shots = ProjectSettings.globalize_path("res://").path_join(shots)
	DirAccess.make_dir_recursive_absolute(shots)
	_current = "capture"
	await _capture()
	var ran := _checks
	ok(ran >= 20, "the capture ran through (%d checks; a broken game script stops it early)" % ran)
	for line in _lines:
		print(line)
	print("\nTHOUSAND EVENTS CAPTURE: %d checks, %d failures; frames in %s" % [_checks, _failures, shots.simplify_path()])
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


## Holds the clock at `minute` (the Night button first, so the clock holds; then the authority's minute).
func _hold(minute: float) -> void:
	await _mode("night")
	var thousand := root.get_node("Thousand")
	thousand.clock["minute"] = minute
	thousand._publish()
	ok(await _until(func(): return absf(float(thousand.states.get("minute", 0.0)) - minute) < 0.01, 4.0),
		"the clock holds at %s" % Clock.format_minute(minute))


## Stands the child at p facing ry (Lantern Lane's yaw: forward (sin ry, cos ry)), the camera behind it.
func _stand(p: Vector2, ry: float, cam: Variant = null) -> void:
	c.pos = p
	c.ry = ry
	c._place_kid()
	var kid: Node3D = world.local_kid()
	if kid and kid.has_method("set_target"):
		kid.set_target(kid.position, ry, true)
	rig.set_process(cam == null)
	rig.t_yaw = ry + PI
	rig._t_manual = 999.0   # hold the framing
	rig.snap()
	if cam != null:
		rig.camera.global_transform = cam



## The show second, within [from, to), that puts the most sparks inside the camera's frame.
func _best_second(from: float, to: float) -> float:
	var cam: Camera3D = rig.camera
	var best := from
	var best_n := -1
	var t := from
	while t < to:
		var buf: PackedFloat32Array = ev.sparks_at(1, 1200.0, t, cam.global_position)
		var n := 0
		for i in buf.size() / 16:
			if cam.is_position_in_frustum(Vector3(buf[i * 16 + 3], buf[i * 16 + 7], buf[i * 16 + 11])):
				n += 1
		if n > best_n:
			best_n = n
			best = t
		t += 0.25
	_lines.append("best second in [%.0f, %.0f): %.2f s with %d sparks in the frame" % [from, to, best, best_n])
	return best


func _shot(name: String, what: String) -> void:
	for i in 6:
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
	var st: Dictionary = ev.status()
	var dr: Dictionary = ev.drawn()
	# the same frame without the events: their own draw calls
	ev.visible = false
	for i in 3:
		await process_frame
	var without := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	ev.visible = true
	for i in 3:
		await process_frame
	var cam: Camera3D = rig.camera
	var kid: Node3D = world.local_kid()
	var at: Vector2 = cam.unproject_position(kid.global_position + Vector3(0, 0.65, 0)) if kid else Vector2.ZERO
	var size := root.get_viewport().get_visible_rect().size
	var in_frame := kid != null and not cam.is_position_behind(kid.global_position) and Rect2(Vector2.ZERO, size).has_point(at)
	ok(in_frame, "%s: the child is in the frame (%s)" % [name, at])
	var tw: Node3D = world.thousand_world
	_lines.append("%s.png | %s | %s | child at (%.1f, %.1f) | %d draw calls (the events %d), %d primitives, %d objects | %.0f ms/frame (llvmpipe) | fireworks %s phase %s second %.2f, %d sparks drawn, %d shells | fountain %s level %.2f, %d jets, %d spray | daylight %.2f" % [
		name, what, Clock.format_minute(float(tw.view_time().get("minute", 0.0))), c.pos.x, c.pos.y, draws, draws - without,
		prims, objs, ms, str(st.fireworks), st.phase, float(st.show_seconds), int(dr.fireworks), int(st.shells), st.fountain,
		float(st.fountain_level), int(dr.jets), int(dr.spray), float(tw.light.get("daylight", 0.0))])


func _capture() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://capture_thousand_events.json")
	await process_frame
	# the tram, as a player takes it
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 4.0), "the tram stop offers Thousand Town")
	hud._context_alt3_btn.pressed.emit()
	ok(await _until(func(): return c.space == Places.THOUSAND and c.journey_to == "", 180.0), "arrived in Thousand Town")
	var tw: Node3D = world.thousand_world
	ok(tw != null and tw.visible, "its world is shown")
	# the integration: the events under the Thousand world, driving themselves
	ev = Events.new()
	ev.name = "Events"
	tw.add_child(ev)
	ev.setup(tw)
	ev.drive = true
	var fw: Dictionary = ev.watch_point("fireworks")
	var fo: Dictionary = ev.watch_point("fountain")
	ok(not fw.is_empty() and not fo.is_empty(), "both watch points")
	_lines.append("watch fireworks: %s" % str(fw))
	_lines.append("watch fountain: %s" % str(fo))
	# 1. the fireworks mid-show (the weave) from the canal promenade, the watch camera
	await _hold(1200.0)
	_stand(fw.stand, fw.ry, fw.camera)
	ev.pin_show_seconds = _best_second(30.0, 70.0)
	await _shot("01_fireworks_weave", "the fireworks mid-show (the weave) from the east canal promenade, the watch camera (Night, 20:00 held)")
	# 2. the finale
	ev.pin_show_seconds = _best_second(72.0, 90.0)
	await _shot("02_fireworks_finale", "the finale from the same spot (20:00 held)")
	# 3. the fountain's show at dusk, 19:05, from the plaza (the follow camera)
	ev.pin_show_seconds = -1.0
	await _hold(1145.0)
	_stand(fo.stand, fo.ry)
	await _shot("03_fountain_show_dusk", "the plaza fountain's show at dusk from the watch point (19:05 held), the follow camera")
	# 4. the fountain's show at night
	await _hold(1230.0)
	_stand(fo.stand, fo.ry)
	await _shot("04_fountain_show_night", "the fountain's show at night, lit colours (20:30 held), the follow camera")
	# 5. the fountain by day
	await _mode("day")
	_stand(fo.stand, fo.ry)
	await _shot("05_fountain_day", "the fountain by day: daytime level 0.45 (Day 12:00), the follow camera")
	ok(not ev.status().fireworks and ev.drawn().fireworks == 0, "no fireworks by day")
	# 6. the plain follow camera at the fireworks spot (what a player sees without the Watch tilt)
	await _hold(1200.0)
	ev.pin_show_seconds = 50.0
	_stand(fw.stand, fw.ry)
	await _shot("06_fireworks_follow_camera", "the fireworks spot with the ordinary follow camera, no tilt (20:00 held, show 50 s)")
	ev.pin_show_seconds = -1.0
	rig.set_process(true)
