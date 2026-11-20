## Rendered frames of Thousand Town's interactions at the player's camera (design/thousand-town.md, "Interactions"):
## the real game (TownWorld, the play controller, the camera rig, the HUD, the child at 1.30 m) rides the tram to
## Thousand Town and uses world/thousand_play.gd; each frame is saved as PNG with the renderer's counts. The town's
## clock is set through the world's `clock` Callable (as tests/thousand_play_tests.gd does). EC2 evidence: Mesa
## llvmpipe software GL, so the look and the counts are real and the frame times are not.
##   xvfb-run -a -s "-screen 0 1400x1100x24" scripts/godot.sh --path game --resolution 1366x1024 \
##       -s res://tests/thousand_play_capture.gd -- --shots=../build/dual-host/thousand-town/shots/play
extends "res://tests/puzzle_ride_tests.gd"

const Places := preload("res://scripts/core/places.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")

var TownWorld: GDScript
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control
var tp: Node
var tw: Node3D
var pp: Node3D
var tr_node: Node3D
var shots := ""
var _lines: Array[String] = []
var _clock := {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	TownWorld = load("res://scripts/world/town_world.gd")
	shots = ProjectSettings.globalize_path("res://").path_join("../../shots/play")
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
	print("\nTHOUSAND PLAY CAPTURE: %d checks, %d failures; frames in %s" % [_checks, _failures, shots.simplify_path()])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _until(cond: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout:
			return false
	return true


func _view_clock() -> Dictionary:
	return _clock.duplicate()


func _at(day: int, minute: float) -> void:
	_clock = {"day": day, "minute": minute, "mode": "auto", "speed": 1}
	await _until(func(): return tw.plans() != null and tw.plans().day == day and absf(float(pp._minute) - fposmod(minute, 1440.0)) < 0.01, 60.0)
	await process_frame


func _stand(p: Vector2, ry: float) -> void:
	c._walk_target = null
	c._city_route = []
	c.pos = tw.resolve_walk(p)
	c.ry = ry
	c._place_kid()
	var kid: Node3D = world.local_kid()
	if kid:
		kid.interpolate = false   # the local child follows the controller, never a network target
	rig.t_yaw = ry + PI
	rig._t_manual = 999.0
	rig.snap()


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
	tp = c.thousand_play


func _shot(name: String, what: String, settle := 6, keep_toast := false) -> void:
	hud._refresh_thousand_play()
	if not keep_toast:
		hud._toast.modulate.a = 0.0   # an earlier frame's message is not part of this one
	for i in settle:
		await process_frame
	var t0 := Time.get_ticks_usec()
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var img := root.get_viewport().get_texture().get_image()
	ok(img.save_png(shots.path_join(name + ".png")) == OK, "saved %s" % name)
	var chip: String = hud._tt_chip_label.text if hud._tt_chip.visible else ""
	var kid: Node3D = world.local_kid()
	var ev: Node = world.thousand_events
	_lines.append("  %s: child %s, camera %s, sparks %s" % [name, kid.global_position if kid else Vector3.ZERO, rig.camera.global_position,
		str(ev.status().get("sparks", 0)) if ev else "-"])
	var card: String = hud._tt_card_name.text if hud._tt_card.visible else ""
	_lines.append("%s.png | %s | %s day %d | chip \"%s\" | card \"%s\" | %d draw calls, %d residents drawn | %.0f ms/frame (llvmpipe)" % [
		name, what, Places.THOUSAND, int(_clock.day), chip, card, draws, pp.counts()["drawn"], ms])


## The show second, within [from, to), that puts the most sparks inside the camera's frame (as
## tests/thousand_events_capture.gd chooses it).
func _best_second(ev: Node, from: float, to: float) -> float:
	var cam: Camera3D = rig.camera
	var best := from
	var best_n := -1
	var t := from
	while t < to:
		var buf: PackedFloat32Array = ev.sparks_at(1, 1290.0, t, cam.global_position)
		var n := 0
		for i in buf.size() / 16:
			if cam.is_position_in_frustum(Vector3(buf[i * 16 + 3], buf[i * 16 + 7], buf[i * 16 + 11])):
				n += 1
		if n > best_n:
			best_n = n
			best = t
		t += 0.5
	_lines.append("  fireworks: show second %.1f, %d sparks in the frame" % [best, best_n])
	return best


## A drawn walker going to a building, not riding: [id] or [].
func _walker(min_remaining: float) -> Array:
	var best := []
	var bd := INF
	for id: int in pp.drawn_ids():
		var info: Dictionary = pp.info(id, "en")
		if str(info.get("mode", "")) != "walk" or str(info.get("trip", "")) == "outing" or info.has("stops"):
			continue
		if float(info.get("remaining_m", 0.0)) < min_remaining or tw.door_point(str(info.get("to", ""))) == Vector2.INF:
			continue
		var p: Vector3 = pp.position_of(id)
		var d := Vector2(p.x, p.z).distance_to(c.pos)
		if d < bd:
			bd = d
			best = [id]
	return best


func _capture() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://capture_thousand_play.json")
	await process_frame
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 20.0), "the tram stop offers Thousand Town")
	hud._context_alt3_btn.pressed.emit()
	ok(await _until(func(): return c.space == Places.THOUSAND and c.journey_to == "", 240.0), "arrived in Thousand Town")
	tw = world.thousand_world
	pp = world.thousand_people
	tr_node = world.thousand_transit
	tw.clock = _view_clock
	# I1: meeting a commuter (07:50)
	await _at(1, 470.0)
	var w := _walker(60.0)
	ok(not w.is_empty(), "a commuter")
	if not w.is_empty():
		var p: Vector3 = pp.position_of(w[0])
		var ahead: Vector3 = pp.info(w[0], "en").get("destination", p)
		var dir := Vector2(ahead.x - p.x, ahead.z - p.z).normalized()
		# stand ahead of them, facing back toward them, a little to the side
		var me := Vector2(p.x, p.z) + dir * 3.2 + Vector2(-dir.y, dir.x) * 0.9
		_stand(me, atan2(p.x - me.x, p.z - me.y))
		tp.meet(w[0])
		rig.t_yaw = c.ry + PI + 0.7   # a little to the side, so the child does not hide the resident
		rig.snap()
		await _shot("01_meet_card", "I1: Say hello to a commuter: the child turns and waves, the card (name, role, age, now, heading with arrival time), the marker over them (07:50)")
		# I2: follow
		hud._tt_card_follow.pressed.emit()
		rig._t_manual = 999.0
		_clock.minute = 470.0
		for k in 30:
			_clock.minute += 0.05
			await process_frame
		var rp: Vector3 = pp.position_of(w[0])
		rig.t_yaw = atan2(c.pos.x - rp.x, c.pos.y - rp.z)   # behind the child, the resident ahead, their way beyond
		rig.snap()
		await _shot("02_follow_route", "I2: following: the chip (Following NAME · to PLACE · about N min, Stop) and the rest of the resident's route on the ground")
		var eta := float(pp.info(w[0], "en").get("eta_minute", 480.0))
		var to: String = str(pp.info(w[0], "en").get("to", ""))
		await _at(1, eta + 0.4)
		var door: Vector2 = tw.door_point(to)
		_stand(door + (door - Vector2(tw.building_at(door).get("rect", Rect2(door, Vector2.ONE)).get_center())).normalized() * 3.0, 0.0)
		rig.t_yaw = atan2(c.pos.x - door.x, c.pos.y - door.y)
		c.ry = rig.t_yaw + PI
		c._place_kid()
		rig.snap()
		await _until(func(): return tp.state == "follow_inside", 10.0)
		await _shot("03_follow_inside", "I2: the resident went into the building: the chip offers its Who's here?; the marker over the door")
		tp.end_all()
	# I4: waiting at a stop, then on the bus (08:00)
	await _at(1, 480.0)
	var st: Dictionary = tp.stands()
	var dep: Dictionary = tr_node.next_departures("bus-stop-4", 1)[0]
	var road: Vector2 = Vector2(21.0, -38.8)
	_stand(st["bus-stop-4"], atan2(road.x - st["bus-stop-4"].x, road.y - st["bus-stop-4"].y) + 0.6)
	tp.start_wait("bus-stop-4")
	await _shot("04_wait_bus", "I4: waiting at the stop: the chip counts down to the next bus")
	await _at(1, float(dep.arrive_minute) + 0.15)
	_stand(st["bus-stop-4"], atan2(road.x - st["bus-stop-4"].x, road.y - st["bus-stop-4"].y) + 0.6)
	await _shot("05_bus_here", "I4: the bus stands at the stop: The bus is here! with Get on the bus")
	tp.board(str(dep.vehicle))
	await _at(1, float(dep.depart_minute) + 0.4)
	rig._t_manual = 0.0
	for k in 20:
		_clock.minute += 0.02
		await process_frame
	await _shot("06_bus_riding", "I4: riding: the child seated in the bus, the camera stands back behind it, the chip names the next stop")
	tp.end_all()
	# I5: the ferris wheel at dusk (18:30, the amusement park open)
	await _at(1, 1110.0)
	_stand(tp.wheel_board_point(), 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	tw.anim_offset = ceilf((now + 1.0) / 180.0) * 180.0 - now - 0.3
	tp.start_wheel()
	await _until(func(): return tp.state == "wheel", 30.0)
	tw.anim_offset += 50.0
	await _shot("07_wheel_view", "I5: on the ferris wheel near the top at 18:30: the camera at the cabin's open front looking out over the town (the child is in the cabin behind it)", 12)
	tp.end_all()
	# I6: the night market (21:30)
	await _at(1, 1290.0)
	var stall: Dictionary = TMap.data().waterfront.stalls[21]
	var counter := Vector2(float(stall.x) - float(stall.side) * (float(stall.d) * 0.5 + 0.8), float(stall.z))
	_stand(counter + Vector2(0.0, 1.6), atan2(float(stall.x) - counter.x, float(stall.z) - counter.y - 1.6))
	c.pos = counter
	tp.buy_snack(tp.stall_here())
	_stand(counter + Vector2(-float(stall.side) * 1.2, 1.4), atan2(float(stall.x) - counter.x, -1.4) + 0.4)
	rig.t_yaw = c.ry + PI * 0.5 + 0.5   # on the child's right, a little in front: the hand with the snack
	rig.snap()
	await _shot("08_market_snack", "I6: a snack from the night market at 21:30, in the child's right hand; the toast names a shopkeeper who is there", 6, true)
	tp.end_all()
	# I7: the fireworks (21:30) and the fountain show (19:40)
	var ev: Node = world.thousand_events
	if ev:
		ev.pin_show_seconds = 50.0
	tp.press_show("fireworks")
	c._walk_target = null
	c._city_route = []
	c.pos = tp._watch_point.stand
	await _until(func(): return tp._watch_arrived, 10.0)
	rig.snap()
	if ev:
		ev.pin_show_seconds = _best_second(ev, 30.0, 70.0)
	await _shot("09_fireworks_watch", "I7: Watch the fireworks: at the events node's watch point, the camera on the show (21:30, the show second with the most sparks in the frame)", 10)
	tp.end_all()
	if ev:
		ev.pin_show_seconds = -1.0
	await _at(1, 1180.0)
	tp.press_show("fountain")
	c._walk_target = null
	c._city_route = []
	c.pos = tp._watch_point.stand
	await _until(func(): return tp._watch_arrived, 10.0)
	rig.snap()
	await _shot("10_fountain_watch", "I7: Watch the fountain show at 19:40: the camera holds on the plaza fountain", 10)
	tp.end_all()
	# the town at noon: the show buttons say when
	await _at(1, 720.0)
	_stand(Vector2(-52.0, 3.6), PI / 2.0)
	await _shot("11_noon_buttons", "the show buttons at 12:00 say when they are next on (Fireworks at 19:00, Fountain show at 19:00)")
