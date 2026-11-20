## Thousand Town's whole playable loop through the real game (design/thousand-town.md sections 3-7 and 13): the real
## Main node (world, controller, camera rig, HUD, menus, the controller layer) runs a solo town; this driver then
## plays only by player input. Touch (default): taps and drags as the mouse events the game takes from a finger
## (as every other tour), a pinch as InputEventMagnifyGesture, HUD buttons by a tap on their rectangle. TV
## (--pad, with --tv): only game controller events through PadInput (Input.parse_input_event of joypad buttons and
## axes): the left stick walks, the D-pad and A press HUD buttons, X and Y the action buttons, B goes back, the
## right stick orbits and ZL / ZR zoom. No button's pressed signal is emitted directly, no position is set.
## One continuous session:
##   the town and its HUD -> the walk to the tram stop -> "Ride to Thousand Town" -> the journey card -> arrival on
##   the station forecourt (follow camera, HUD) -> exploring (streets, the canal and a wall stop the child, orbit,
##   zoom, occlusion) -> Say hello, the card, Follow, the chip, Stop -> "Who's here?" at Courtyard Housing -> the
##   bus (wait, countdown, Auto 4x, board, ride, get off at the next stop) -> Day, Dusk, Night -> a night market
##   snack -> Watch the fireworks -> Ride home while watching -> the town, its HUD exactly as before.
## Each step prints PASS / FAIL lines; the run ends with "THOUSAND LOOP TOUR <touch|tv>: N checks, F failures" and
## exits 1 on any failure, an engine error, a script error in this driver, or the wall-clock limit.
## Waits are by condition with limits in game seconds (the physics clock), so they stretch by themselves on a
## slow renderer; the game's timings are unchanged.
##   Headless (logic):  scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_loop_tour.gd \
##       --no-shots --window=1366x1024
##                      ... --tv --pad --pad-layout=nintendo --no-shots --window=1920x1080
##   Rendered (EC2 software GL, frames and README):
##       timeout 3000 xvfb-run -a -s "-screen 0 1960x1200x24" scripts/godot.sh --path game --resolution 1366x1024 \
##           -- --driver=res://tests/thousand_loop_tour.gd --physics-steps=150 [--shots=/abs/dir]
##       ... --resolution 1920x1080 -- --driver=res://tests/thousand_loop_tour.gd --tv --pad --pad-layout=nintendo \
##           --physics-steps=150
##   Frames default to build/dual-host/thousand-town/shots/loop-touch and loop-tv.
##   --physics-steps=N: on software GL (0.4-2.5 s a frame) Engine.max_physics_steps_per_frame is STEER_STEPS (24, for
##   Godot's 8) through the tour and N while the child follows a resident: the town's shown clock, its residents and
##   its buses follow wall time, the child game time (the README says so). --stop-after=_step ends early (development).
## Residents are met where they happen to walk by (the forecourt, the canal bank, Courtyard Housing or a street
## corner on the way to the bus): touch taps one on screen, TV catches one up with the stick.
extends "res://tests/pets_tour.gd"

const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const SAVE := "user://thousand_loop_tour_town.json"
const DEV := 0
const LABEL := "EC2 Mesa llvmpipe software GL, Godot 4.7.2 Compatibility; frame times not representative; not device evidence"
## The route, on walkable straight legs (art/thousand_people.gd's pavement graph, checked with the child's own
## resolver): the forecourt, the pedestrian street east, back, the Courtyard Housing door, then south along the
## street at x -50.75 and east at z -44 to bus stop 3; after the ride, from bus stop 4 to the night market.
const ARRIVAL := Vector2(-52.0, 3.6)
const EAST := [Vector2(-40.0, 3.6)]
const TO_COURTYARD := [Vector2(-51.75, 3.75), Vector2(-52.25, -2.75), Vector2(-54.75, -5.75), Vector2(-64.6, -5.75)]
const COURTYARD := "h-courtyard"
const TO_STOP := [Vector2(-54.75, -5.75), Vector2(-50.75, -6.75), Vector2(-50.75, -35.75), Vector2(-45.25, -35.75), Vector2(-43.75, -37.25),
	Vector2(-43.75, -43.75), Vector2(-37.75, -43.75), Vector2(-36.75, -44.75), Vector2(-23.75, -44.75), Vector2(-23.75, -44.25), Vector2(-21.75, -44.25)]
const STOP_A := "bus-stop-3"
const STALL := 21   # a juice stall on the east promenade, beside the fireworks' watch point
const DPAD := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}

var pad_mode := false
var mode_name := "touch"
var c: Node
var hud: Control
var pad: Node
var tp: Node
var shots_dir := ""
var save_shots := true
var _checks := 0
var _rows: Array = []
var _finished := false
var _dead := ""
var _catcher: Catcher
var _town_buttons: Array = []
var _town_buttons_start: Array = []
## Watchers over the whole stay in Thousand Town (sampled every frame).
var _samples := 0
var _in_solid := []
var _cam_in_box := []
var _undithered := []
var _hidden_kid := 0
var _cam_in_dithered := 0
var _occluded_frames := 0
var _max_occluded := 0
var _trail: Array = []
var _trail_on := false
var _journeys: Array = []
var _hello_done := false
var _phys_t := 0.0
var _turned := false   # the last stick_step turned the camera instead of walking
var _last_gdt := 1.0 / 60.0   # game seconds the last drawn frame took
var _phys_prev := 0.0


class Catcher extends Logger:
	var errors: Array = []
	var driver_error := false
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s %s (%s:%d)" % [code, rationale, file, line])
		var bt := ""
		for b in script_backtraces:
			bt += str(b)
		if file.contains("thousand_loop_tour") or bt.contains("thousand_loop_tour") or error_type == ERROR_TYPE_SCRIPT:
			driver_error = true
		_lock.unlock()


func check(cond: bool, what: String) -> void:
	_checks += 1
	super.check(cond, what)


# ------------------------------------------------------------- waiting

## Waits for `cond` up to `game_sec` seconds of game (physics) time, and never longer than a generous wall-clock
## limit: on a slow software renderer the physics clock advances at most 8 steps a drawn frame, so the limit in
## wall time stretches by itself.
func until_g(cond: Callable, game_sec := 6.0) -> bool:
	var t := 0.0
	var w0 := Time.get_ticks_msec()
	var wall := maxf(60.0, game_sec * 60.0)
	while not cond.call():
		if _finished:
			return false
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > game_sec or (Time.get_ticks_msec() - w0) / 1000.0 > wall:
			return cond.call()
	return true


## One drawn frame; returns the game (physics) seconds that passed in it.
func step_frame() -> float:
	var t0 := _phys_t
	await get_tree().process_frame
	return _phys_t - t0


func _physics_process(delta: float) -> void:
	_phys_t += delta


func game_wait(sec: float) -> void:
	await until_g(func(): return false, sec)


# ------------------------------------------------------------- the world as the player sees it

func tw() -> Node3D:
	return main.world.thousand_world if c.space == Places.THOUSAND else null


func pp() -> Node3D:
	return main.world.thousand_people


func kid() -> Node3D:
	return main.world.local_kid()


func cam() -> Camera3D:
	return main.rig.camera


func clock_text() -> String:
	if c.space != Places.THOUSAND or tw() == null:
		return "town (Lantern Lane)"
	var vt: Dictionary = tw().view_time()
	return "%s day %d (%s %dx)" % [tp.hhmm(fposmod(float(vt.get("minute", 0.0)), 1440.0)), int(vt.get("day", 1)), str(vt.get("mode", "")), int(vt.get("speed", 1))]


func drawn() -> int:
	return int(pp().counts().get("drawn", 0)) if c.space == Places.THOUSAND and pp() != null else 0


## The HUD's visible buttons (paths), outside dialogs and the floating name tags: "the town HUD" to compare.
func visible_buttons() -> Array:
	var out: Array = []
	for b in hud.find_children("*", "BaseButton", true, false):
		if not (b as Control).is_visible_in_tree() or hud._overlay.is_ancestor_of(b) or hud._tag_layer.is_ancestor_of(b):
			continue
		out.append(str(hud.get_path_to(b)))
	out.sort()
	return out


func modal() -> bool:
	for ch in hud._overlay.get_children():
		if not ch.is_queued_for_deletion():
			return true
	return false


## The child's height on screen in pixels (feet to the top of the head, 1.30 m), and its chest's screen point.
func kid_screen() -> Dictionary:
	var k := kid()
	if k == null or cam().is_position_behind(k.global_position + Vector3(0, 0.9, 0)):
		return {"h": 0.0, "chest": Vector2(-1, -1), "on": false}
	var feet := cam().unproject_position(k.global_position)
	var head := cam().unproject_position(k.global_position + Vector3(0, 1.3, 0))
	var chest := cam().unproject_position(k.global_position + Vector3(0, 0.9, 0))
	var vs := get_viewport().get_visible_rect().size
	return {"h": feet.distance_to(head), "chest": chest, "on": Rect2(Vector2.ZERO, vs).has_point(chest)}


func _process(_delta: float) -> void:
	if _phys_t > _phys_prev:
		_last_gdt = _phys_t - _phys_prev   # the game seconds of the frame just run (for the stick's push)
	_phys_prev = _phys_t
	if _catcher and _catcher.driver_error and _dead == "" and not _finished:
		_dead = "a script error in the tour driver: %s" % str(_catcher.errors.back() if not _catcher.errors.is_empty() else "")
		check(false, _dead)
		_finish()
		return
	if _finished or c == null or c.space != Places.THOUSAND or c.journey_to != "" or tw() == null:
		return
	# the watchers: the child never stands inside a solid, the camera is never inside an occluder box, every box
	# between the camera and the child is drawn dithered (the world's set_occluded), and the child stays visible
	_samples += 1
	if _trail_on and (_trail.is_empty() or c.pos.distance_to(_trail.back()) > 0.3):
		_trail.append(c.pos)
	var k := kid()
	if k == null or not k.is_visible_in_tree():
		_hidden_kid += 1
	if not tp.busy() and tw()._blocked(c.pos):
		if _in_solid.size() < 5:
			_in_solid.append(c.pos)
	var r: Node3D = main.rig
	if r.on_thousand and r.t_watch == null and not r.t_overview and k != null:
		var eye: Vector3 = cam().global_position
		var chest := k.global_position + Vector3(0, r.T_CHEST, 0)
		var boxes: Array = tw().occluders()
		for i in boxes.size():
			if (boxes[i] as AABB).has_point(eye):
				_cam_in_dithered += 1
				# inside a solid is only all right while that solid is drawn as a screen door (the child seen through it)
				if not (tw().occluded() as Array).has(i) and _cam_in_box.size() < 5:
					_cam_in_box.append([i, eye])
		var between: Array = r.blocking(chest, eye, boxes)
		if not between.is_empty():
			_occluded_frames += 1
			_max_occluded = maxi(_max_occluded, between.size())
			var told: Array = tw().occluded()
			for i in between.slice(0, 4):
				if not told.has(i) and _undithered.size() < 5:
					_undithered.append([i, eye])


# ------------------------------------------------------------- evidence

func frame_shot(name: String, what: String) -> void:
	var draws := 0
	var file := "-"
	var ms := 0.0
	if save_shots and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		ms = (Time.get_ticks_usec() - t0) / 1000.0
		draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var img := get_viewport().get_texture().get_image()
		file = "%02d_%s.png" % [_rows.size() + 1, name]
		var err := img.save_png(shots_dir.path_join(file))
		check(err == OK, "frame %s saved" % file)
	else:
		await frames(1)
	var ks := kid_screen()
	_rows.append({"file": file, "what": what, "clock": clock_text(), "draws": draws, "drawn": drawn(), "ms": ms,
		"kid_px": int(round(ks["h"])), "cam": cam().global_position.snapped(Vector3(0.1, 0.1, 0.1)), "pos": c.pos.snapped(Vector2(0.1, 0.1))})
	print("SHOT %s | %s | %s | %d draw calls | %d residents drawn | child %d px | %.0f ms" % [file, what, clock_text(), draws, drawn(), int(round(ks["h"])), ms])


func write_readme() -> void:
	if not save_shots or DisplayServer.get_name() == "headless":
		return
	var path := shots_dir.path_join("README.md")
	var notes := ""
	if FileAccess.file_exists(path):
		var old := FileAccess.get_file_as_string(path)
		var at := old.find("<!-- review notes -->")
		if at >= 0:
			notes = old.substr(at)
	var vs := get_viewport().get_visible_rect().size
	var lines: Array[String] = []
	lines.append("# Thousand Town loop tour, %s" % ("TV controller" if pad_mode else "touch"))
	lines.append("")
	lines.append("Evidence label: %s." % LABEL)
	lines.append("")
	lines.append("Made by `game/tests/thousand_loop_tour.gd`%s at %dx%d through the real Main scene (world, controller, camera rig, HUD, menus, PadInput). Input: %s." % [
		" --tv --pad --pad-layout=nintendo" if pad_mode else "", int(vs.x), int(vs.y),
		"only synthetic game controller events (joypad buttons and axes through PadInput)" if pad_mode else "taps and drags as the mouse events the game takes from a finger, a pinch as a magnify gesture"])
	lines.append("Not by input: the solo town is started with `Session.start_solo` on the tour's own save (the title menus are not part of this loop). The town's time is changed only with the HUD's Day, Dusk, Night and Auto buttons (no test clock).")
	if main.args.has("physics-steps"):
		lines.append("Engine setting for the software renderer: `Engine.max_physics_steps_per_frame` = %d (Godot's default 8) during the tour, and %d while the child follows a resident. At 0.4-2.5 s a frame Godot's default would run the child at a small fraction of wall time while the town's shown clock, its residents and its buses follow wall time (`Thousand.est_clock`); the higher limit while following lets the child keep pace with a resident. Game logic unchanged." % [STEER_STEPS, int(main.args["physics-steps"])])
	lines.append("")
	lines.append("Result: THOUSAND LOOP TOUR %s: %d checks, %d failures." % [mode_name, _checks, failures])
	lines.append("")
	lines.append("| # | Frame | Step, what it shows | Thousand Town clock | Draw calls | Residents drawn | Child on screen (px) | Frame time (llvmpipe, not representative) |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		lines.append("| %d | %s | %s | %s | %d | %d | %d | %.0f ms |" % [i + 1, r.file, str(r.what).replace("|", "/"), r.clock, r.draws, r.drawn, r.kid_px, r.ms])
	lines.append("")
	lines.append("Draw calls: the renderer's own count for the whole frame (3D and HUD), RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME. Residents drawn: art/thousand_people.gd counts().drawn (0 outside Thousand Town).")
	lines.append("")
	lines.append(notes if notes != "" else "<!-- review notes -->\n## Review notes\n\n(none yet)\n")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()


# ------------------------------------------------------------- touch input

## A drag on the screen (press, moves, release) like a finger, from `a` to `b` in canvas coordinates.
func drag(a: Vector2, b: Vector2, steps := 10) -> void:
	var xf := get_viewport().get_final_transform()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = xf * a
	down.global_position = down.position
	Input.parse_input_event(down)
	await get_tree().process_frame
	var p := a
	for i in range(1, steps + 1):
		var nx := a.lerp(b, float(i) / steps)
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = xf * nx
		mv.global_position = mv.position
		mv.relative = (nx - p) * xf.get_scale()
		Input.parse_input_event(mv)
		p = nx
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = xf * p
	up.global_position = up.position
	Input.parse_input_event(up)
	await get_tree().process_frame


## A free spot for a finger on the world near the middle of the screen (not on the HUD).
func world_spot() -> Vector2:
	var area := playable_rect()
	for p in [area.get_center() + Vector2(0, -60), area.get_center() + Vector2(-200, -40), area.get_center() + Vector2(200, -40), area.get_center()]:
		if ui_blocker_at(p) == "":
			return p
	return area.get_center()


## Turns the follow camera by drags until it stands opposite `goal` (so the goal is ahead on screen).
func touch_face(goal: Vector2) -> void:
	for n in 4:
		var d: Vector2 = goal - c.pos
		if d.length() < 0.5:
			return
		var want := atan2(-d.x, -d.y)
		var diff := wrapf(main.rig.t_yaw - want, -PI, PI)
		if absf(diff) < 0.25:
			return
		var px := clampf(diff / main.rig.T_ORBIT_PER_PX, -900.0, 900.0)
		var s := world_spot()
		await drag(s - Vector2(px * 0.5, 0), s + Vector2(px * 0.5, 0), 6)
		await frames(2)


## A tap on the ground at `p` (only where a finger could: on screen, in the safe area, off the HUD, not on a
## resident). Returns false when it could not be tapped.
func tap_ground(p: Vector2, what: String) -> bool:
	var y: float = tw().height_at(p) if tw() else 0.0
	var at := Vector3(p.x, y, p.y)
	var aim := cam().unproject_position(at)
	var ok_tap := not cam().is_position_behind(at) and playable_rect().has_point(aim) and ui_blocker_at(aim) == ""
	var why := ""
	if not ok_tap:
		why = "off screen or under the HUD (%s, %s)" % [aim.round(), ui_blocker_at(aim)]
	elif c.space == Places.THOUSAND and pp() != null and pp().pick_screen(cam(), aim) >= 0:
		ok_tap = false   # a resident under the finger would be met instead
		var who: int = pp().pick_screen(cam(), aim)
		why = "a resident under the finger (%d at %s, %s)" % [who, pp().position_of(who).snapped(Vector3(0.1, 0.1, 0.1)), str(pp().info(who, "en").get("mode", ""))]
	elif c.space == Places.THOUSAND and main.world.ground_point(cam(), aim) is Vector2 and tw().building_at(main.world.ground_point(cam(), aim)).get("door") is Vector2:
		ok_tap = false   # the tap would land on a building (Who's here?)
		why = "a building under the finger"
	if not ok_tap:
		print("DIAG no tap on %s at %s: %s" % [what, p, why])
		return false
	await tap(aim)
	return true


## In the town: a tap on open ground near `p` (no item under the finger: a tap on an item walks there and uses it).
func town_tap_open(p: Vector2, what: String) -> void:
	await settle_camera(2.0)
	var spot := p
	var best := INF
	for dx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for dz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var q: Vector2 = p + Vector2(dx, dz)
			var aim := cam().unproject_position(Vector3(q.x, 0, q.y))
			if main.world.pick_candidates(cam(), aim).is_empty() and q.distance_to(p) < best:
				best = q.distance_to(p)
				spot = q
	await tap_at_world(Vector3(spot.x, 0, spot.y), what)


# ------------------------------------------------------------- controller input

func joy(b: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
	e.device = DEV
	e.button_index = b
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func btn(b: int) -> void:
	joy(b, true)
	await frames(1)
	joy(b, false)
	await frames(2)


func axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
	e.device = DEV
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


## The right stick held, a frame at a time, so the follow camera's yaw changes by `delta_yaw` radians: PadInput turns
## it by the stick (after its dead zone) times T_STICK_RATE times the frame's time, and a software-rendered frame lasts
## up to seconds, so the push is scaled by the last frame's time. Stick right lowers the yaw.
func pad_orbit_by(delta_yaw: float, wall_limit := 12.0) -> void:
	var left := delta_yaw
	var dt := clampf(get_process_delta_time(), 0.016, 3.0)
	var w0 := Time.get_ticks_msec()
	var dz: float = pad.DEADZONE
	while absf(left) > 0.06 and Time.get_ticks_msec() - w0 < wall_limit * 1000.0:
		var frac := clampf(absf(left) / (main.rig.T_STICK_RATE * dt), 0.05, 1.0)
		var y0: float = main.rig.t_yaw
		axis(JOY_AXIS_RIGHT_X, -signf(left) * (dz + (1.0 - dz) * frac))
		await get_tree().process_frame
		axis(JOY_AXIS_RIGHT_X, 0.0)
		await get_tree().process_frame
		dt = clampf(get_process_delta_time(), 0.016, 3.0)
		left -= wrapf(main.rig.t_yaw - y0, -PI, PI)
	axis(JOY_AXIS_RIGHT_X, 0.0)
	await frames(1)


func stick_off() -> void:
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_RIGHT_Y, 0.0)


## The left stick toward a world point, as it shows from the follow camera (stick up walks away from the camera).
func stick_toward(p: Vector2, push: float) -> void:
	var d: Vector2 = p - c.pos
	if d.length() < 0.001:
		return
	var r: Vector2 = main.rig.flat_right()
	var f: Vector2 = main.rig.flat_forward()
	var v := Vector2(d.normalized().dot(r), -d.normalized().dot(f)).normalized() * push
	axis(JOY_AXIS_LEFT_X, v.x)
	axis(JOY_AXIS_LEFT_Y, v.y)


## One frame of walking toward `p` with the controller, as a player does with the follow camera: when the goal is
## well off the camera's forward, the right stick turns the camera toward it first (the stick then pushes almost
## straight ahead). On a software renderer a frame lasts seconds and the camera swings behind the child within one, so
## a sideways push given against the old view would land in the new one; pushing ahead keeps that harmless.
## Returns the game seconds the frame took.
func stick_step(p: Vector2, push: float) -> float:
	_catchup(false)
	var d: Vector2 = p - c.pos
	var err := wrapf(atan2(-d.x, -d.y) - main.rig.t_yaw, -PI, PI)
	_turned = absf(err) > (0.2 if d.length() > 2.0 else 0.6) and d.length() > 0.8
	if _turned:
		stick_off()
		var t0 := _phys_t
		await pad_orbit_by(err, 4.0)
		return _phys_t - t0
	stick_toward(p, push)
	return await step_frame()


## The physics catch-up on a slow software renderer (--physics-steps=N): STEER_STEPS a frame (0.4 s of play at 60 Hz)
## for the tour, N only while the child follows a resident by itself. The town's shown clock, its residents and its
## buses follow wall time; at Godot's own 8 steps a frame the child would lag far behind them. More steps all the time
## would make each frame longer still (every step runs the controller), and a stick event, read a frame late, would
## carry the child far past where it was aimed.
const STEER_STEPS := 24


func _catchup(fast: bool) -> void:
	if main.args.has("physics-steps"):
		Engine.max_physics_steps_per_frame = int(main.args["physics-steps"]) if fast else mini(STEER_STEPS, int(main.args["physics-steps"]))


## Brings the controller's pointer onto a HUD control with the D-pad (PadInput.snap), then presses A.
func pad_press(target: Control, what: String) -> bool:
	if not await pad_point(target, what):
		return false
	await btn(pad.confirm_button())
	await frames(2)
	return true


## A on a HUD button that starts a journey: the pointer to it, then A held for one frame and released; returns as soon
## as the journey to `to` has started (a catch-up of several physics steps a frame ends the card within a few frames).
func pad_press_journey(target: Control, what: String, to: String) -> void:
	if not await pad_point(target, what):
		return
	var b: int = pad.confirm_button()
	joy(b, true)
	await get_tree().process_frame
	joy(b, false)
	for i in 6:
		if not _journey_started(to).is_empty():
			return
		await get_tree().process_frame


func pad_point(target: Control, what: String) -> bool:
	if target == null or not target.is_visible_in_tree():
		check(false, "%s is on screen for the D-pad" % what)
		return false
	# the shortest D-pad path, choosing as PadInput.snap chooses (a player finds it by trying), planned again after
	# every press (the HUD may have moved meanwhile)
	var pressed := []
	for i in 12:
		if not is_instance_valid(target) or target.get_global_rect().has_point(pad.cursor):
			break
		var path := _dpad_path(target)
		if path.is_empty():
			break
		await btn(DPAD[path[0]])
		pressed.append(path[0])
	var reached: bool = is_instance_valid(target) and target.get_global_rect().has_point(pad.cursor)
	var names: Array = pad.targets().map(func(t): return "%s@%s" % [(t as Button).text if t is Button and (t as Button).text != "" else str(t.name), (t as Control).get_global_rect().get_center().round()])
	check(reached, "the D-pad brings the pointer to %s (%s)%s" % [what, ",".join(pressed), "" if reached else " - no D-pad path from %s among %s" % [pad.cursor.round(), str(names)]])
	return reached


## PadInput.snap's choice from a point (two passes: within 60 degrees of the direction first, then any).
func _snap_from(ts: Array, from: Vector2, dir: Vector2) -> Control:
	for pass_i in 2:
		var best: Control = null
		var best_score := INF
		for t: Control in ts:
			var d := t.get_global_rect().get_center() - from
			var along := d.dot(dir)
			if along < 8.0 or t.get_global_rect().has_point(from):
				continue
			var side := absf(d.cross(dir))
			if pass_i == 0 and side > along * 1.7320508:
				continue
			var score := along + 2.5 * side
			if score < best_score:
				best_score = score
				best = t
		if best:
			return best
	return null


## Breadth-first over the D-pad's jumps from the pointer to `target`: the directions to press ([] if none).
func _dpad_path(target: Control) -> Array:
	var ts: Array = pad.targets()
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	var start: Vector2 = pad.cursor
	var queue: Array = [[start, []]]
	var seen := {}
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		var at: Vector2 = cur[0]
		for dn in dirs:
			var n := _snap_from(ts, at, dirs[dn])
			if n == null or seen.has(n):
				continue
			seen[n] = true
			var way: Array = (cur[1] as Array) + [dn]
			if n == target:
				return way
			queue.append([n.get_global_rect().get_center(), way])
	return []


# ------------------------------------------------------------- walking by input

## Walks along straight legs: by taps on the ground (touch; the camera turned by a drag when a leg's end is not
## ahead) or by the left stick (TV). Each leg must end within `tol` of its point. Returns false when a leg fails.
func walk_legs(points: Array, what: String, tol := 0.8, quiet := false) -> bool:
	for p: Vector2 in points:
		if not await walk_leg(p, tol):
			if quiet:
				return false
			check(false, "%s: the child walks to %s by %s (at %s)" % [what, p, "the stick" if pad_mode else "taps", c.pos.snapped(Vector2(0.01, 0.01))])
			return false
	if not quiet:
		check(true, "%s: walked by %s to %s" % [what, "the stick" if pad_mode else "taps", c.pos.snapped(Vector2(0.01, 0.01))])
	return true


func walk_leg(p: Vector2, tol: float) -> bool:
	for attempt in 3:
		if await _walk_leg_once(p, tol):
			return true
		# stuck in a corner: a step aside that the child can walk, the one that ends nearest the goal (as a player
		# wiggles the stick or taps beside), then the leg again
		var best := Vector2.INF
		for k in 16:
			var q: Vector2 = c.pos + Vector2.from_angle(TAU * k / 16.0) * 1.5
			if _straight_walk(c.pos, q) and (best == Vector2.INF or q.distance_to(p) < best.distance_to(p)):
				best = q
		if best == Vector2.INF or not await _walk_leg_once(best, 0.6):
			return false
	return c.pos.distance_to(p) <= tol


func _walk_leg_once(p: Vector2, tol: float) -> bool:
	if pad_mode:
		var stuck := 0.0
		var t := 0.0
		while c.pos.distance_to(p) > tol * 0.6 and t < 60.0 and not _finished:
			var dist: float = c.pos.distance_to(p)
			var before: Vector2 = c.pos
			var step: float = await stick_step(p, 1.0 if dist > 3.0 else 0.45)
			t += step
			stuck = stuck + step if c.pos.distance_to(before) < 0.005 and not _turned else 0.0
			if stuck > 1.5:
				break
		stick_off()
		await frames(2)
		return c.pos.distance_to(p) <= tol
	# touch: taps no farther than 14 m ahead, each walked out before the next
	for n in 12:
		if c.pos.distance_to(p) <= tol * 0.6:
			break
		var goal: Vector2 = c.pos + (p - c.pos).limit_length(14.0)
		await touch_face(goal)
		var tapped := false
		var dir: Vector2 = (goal - c.pos).normalized()
		var side := Vector2(-dir.y, dir.x)
		var reach: float = c.pos.distance_to(goal)
		for along in [reach, reach * 0.75, reach * 0.5]:
			for lat in [0.0, 0.6, -0.6]:
				if tapped or along < 0.3:
					continue
				var g2: Vector2 = c.pos + dir * along + side * lat
				if tw() != null and tw()._blocked(g2):
					continue
				if await tap_ground(g2, "ground"):
					tapped = true
		if not tapped:
			# nothing tappable on the way from here (a resident in front of the camera): look from a little to the
			# side and try again, as a player would
			await _look_around(0.45 if n % 2 == 0 else -0.9)
			await game_wait(0.3)
			continue
		await until_g(func(): return c._walk_target == null, 8.0)
	return c.pos.distance_to(p) <= tol


# ------------------------------------------------------------- the tour

func _ready() -> void:
	_catcher = Catcher.new()
	OS.add_logger(_catcher)
	super._ready()


func _run() -> void:
	c = main.controller
	hud = main.hud
	pad = main.pad
	tp = c.thousand_play
	pad_mode = main.args.has("pad")
	mode_name = "tv" if pad_mode else "touch"
	tag = mode_name
	save_shots = not main.args.has("no-shots")
	shots_dir = str(main.args.get("shots", ProjectSettings.globalize_path("res://").path_join("../../shots/loop-" + mode_name))).simplify_path()
	if save_shots:
		DirAccess.make_dir_recursive_absolute(shots_dir)
	get_tree().create_timer(float(main.args.get("timeout", "2900")), true, false, true).timeout.connect(func():
		if not _finished:
			check(false, "the tour finished within %s s of wall-clock time" % main.args.get("timeout", "2900"))
			_finish())
	if pad_mode:
		check(TvMode.active() and pad != null, "TV mode with the controller layer (--tv --pad)")
	if main.args.has("physics-steps"):
		# Software GL draws a frame in 0.4-2.5 s; Godot then runs at most 8 physics steps (0.13 s of game) a frame.
		# A higher catch-up limit keeps game time nearer wall time; the game's logic and timings are unchanged.
		_catchup(false)   # STEER_STEPS; the full value only while following
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2", SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	c.journey.connect(_on_journey)
	Session.start_solo(SAVE, main.menus.avatar)
	if not await until_g(func(): return hud.visible and not main.menus.visible and kid() != null, 10.0):
		check(false, "the solo town starts")
		_finish()
		return
	await game_wait(0.8)
	if pad_mode and modal():
		await btn(pad.back_button())
	var steps := [_town, _ride_there, _arrival, _explore, _who_is_here, _bus, _lighting, _market, _fireworks, _home]
	for s: Callable in steps:
		if _finished:
			return
		var ok_step: bool = await s.call()
		if not ok_step:
			check(false, "the loop could not go on after %s" % s.get_method())
			break
		if str(main.args.get("stop-after", "")) == str(s.get_method()):
			break   # development only: a shorter run
	_finish()


## The town with its HUD; the walk to the tram stop; its offer.
func _town() -> bool:
	check(c.space == "town" and kid() != null and kid().is_visible_in_tree(), "the child in the normal Lantern Lane town")
	check(hud.visible and hud._decorate_btn.is_visible_in_tree() and not hud._thousand_time.visible and not hud._ride_home.visible,
		"the town HUD (Decorate shown; no Thousand Town time buttons, no Ride home)")
	_town_buttons_start = visible_buttons()
	print("TOWN HUD buttons at the start: %s" % ", ".join(_town_buttons_start.map(func(p): return str(p).get_file())))
	await frame_shot("town_start", "the normal Lantern Lane town with the town HUD, at the start")
	var board: Vector2 = TownModel.tram_stop_boarding(Session.model)
	if pad_mode:
		var t := 0.0
		while c.pos.distance_to(board) > 0.45 and t < 20.0:
			var a := cam().unproject_position(Vector3(c.pos.x, 0, c.pos.y))
			var b := cam().unproject_position(Vector3(board.x, 0, board.y))
			_catchup(false)
			var v0: Vector2 = (b - a).normalized() * (1.0 if c.pos.distance_to(board) > 1.5 else 0.5)
			axis(JOY_AXIS_LEFT_X, v0.x)
			axis(JOY_AXIS_LEFT_Y, v0.y)
			t += await step_frame()
		stick_off()
	else:
		# a tap on the open ground beside the stop (a tap on the stop itself would ride to the zoo at once)
		await town_tap_open(board, "the open ground beside the tram stop")
	var offered := await until_g(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 12.0)
	check(offered, "walking to the town's tram stop by %s: its action is offered (%s)" % ["the stick" if pad_mode else "a tap", str(c._ctx.get("label", ""))])
	if not offered:
		return false
	await until_g(func(): return c._walk_target == null, 4.0)
	await frames(3)
	var alt3: Button = hud._context_alt3_btn
	check(alt3.is_visible_in_tree() and alt3.text == "Ride to Thousand Town", "the stop offers \"Ride to Thousand Town\" (%s)" % alt3.text)
	var others := [hud._context_btn.text, hud._context_alt_btn.text if hud._context_alt_btn.is_visible_in_tree() else ""]
	check(not others.has("Ride to Thousand Town") and others[0] != "", "as a distinct destination beside the others (%s)" % str(others))
	_town_buttons = visible_buttons()
	await frame_shot("stop_offer", "the town's tram stop: the action buttons offer the zoo, the city and \"Ride to Thousand Town\"")
	return true


## The journey's phases as the controller announces them, with what the card said at its start ([phase, to, title,
## credit shown]); a catch-up of several physics steps a frame can end a journey within a few drawn frames.
func _on_journey(phase: String, to: String) -> void:
	var title := ""
	var credit := false
	if hud._journey_card != null:
		title = (hud._journey_card.get_node("Box/V/Title") as Label).text
		var cr := hud._journey_card.get_node("Box/V/Credit") as Label
		credit = cr.visible and cr.text.contains("YiHuiShiBY") and cr.text.contains("CC BY 4.0")
	_journeys.append([phase, to, title, credit])


func _journey_started(to: String) -> Array:
	for j: Array in _journeys:
		if j[0] == "start" and j[1] == to:
			return j
	return []


func _ride_there() -> bool:
	_journeys.clear()
	if pad_mode:
		await pad_press_journey(hud._context_alt3_btn, "Ride to Thousand Town", Places.THOUSAND)
	else:
		await tap(hud._context_alt3_btn.get_global_rect().get_center())
	var started := await until_g(func(): return not _journey_started(Places.THOUSAND).is_empty(), 3.0)
	check(started, "pressing it starts the journey to Thousand Town")
	if not started:
		return false
	var j := _journey_started(Places.THOUSAND)
	check(j[2] == "To Thousand Town", "the journey card names Thousand Town (%s)" % j[2])
	check(j[3], "and carries the CC BY credit")
	if c.journey_to == Places.THOUSAND:
		await frame_shot("journey_card", "the journey card: To Thousand Town, with the CC BY credit")
	var arrived := await until_g(func(): return c.space == Places.THOUSAND and c.journey_to == "", 12.0)
	check(arrived, "the child arrives in Thousand Town")
	return arrived


func _arrival() -> bool:
	await frames(4)
	var k := kid()
	check(k != null and k.is_visible_in_tree(), "the child is visible")
	check(c.pos.distance_to(ARRIVAL) < 0.6, "on the station forecourt (%s)" % c.pos)
	check(main.rig.on_thousand and main.world.view_space == Places.THOUSAND and main.world.thousand_world.visible, "the follow camera in Thousand Town's world")
	var to_kid: Vector3 = k.global_position - cam().global_position
	var facing := Vector2(sin(c.ry), cos(c.ry))
	check(Vector2(to_kid.x, to_kid.z).normalized().dot(facing) > 0.95, "the camera stands behind the child (%s, child facing %s)" % [cam().global_position.snapped(Vector3(0.01, 0.01, 0.01)), facing.snapped(Vector2(0.01, 0.01))])
	var ks := kid_screen()
	var vs := get_viewport().get_visible_rect().size
	check(ks["on"] and (ks["chest"] as Vector2).y > vs.y * 0.55 and absf((ks["chest"] as Vector2).x - vs.x * 0.5) < vs.x * 0.15,
		"the child in the lower middle of the frame (%s of %s)" % [(ks["chest"] as Vector2).round(), vs])
	check(float(ks["h"]) >= 80.0 and float(ks["h"]) <= 260.0, "the child at a sensible size on screen (%.0f px tall)" % float(ks["h"]))
	check(hud._location.visible and hud._location.text.begins_with("Thousand Town"), "the place line (%s)" % hud._location.text)
	check(hud._ride_home.is_visible_in_tree(), "Ride home")
	check(hud._thousand_time.is_visible_in_tree() and hud._thousand_time_btns.keys() == ["day", "dusk", "night", "auto"], "the time buttons: Day, Dusk, Night, Auto")
	check(hud._thousand_look.is_visible_in_tree(), "Look")
	check(hud._tt_shows["fireworks"].is_visible_in_tree() and hud._tt_shows["fountain"].is_visible_in_tree(), "the two show buttons")
	var now := visible_buttons()
	var hidden: Array = _town_buttons_start.filter(func(p): return not now.has(p))
	check(not hud._decorate_btn.is_visible_in_tree() and hidden.has(str(hud.get_path_to(hud._decorate_btn))), "the town-only HUD parts are hidden (%s)" % ", ".join(hidden.map(func(p): return str(p).get_file())))
	check(thousand_node().states["started"] and int(thousand_node().states["day"]) == 1, "the town's clock runs (%s)" % clock_text())
	await frame_shot("arrival", "arrival on the station forecourt: the child from behind, looking east along the pedestrian street; the Thousand Town HUD")
	return k != null


func thousand_node() -> Node:
	return get_node("/root/Thousand")


func _explore() -> bool:
	if not await _try_hello("the station forecourt"):
		return false
	# controllable: one input moves the child
	var p0: Vector2 = c.pos
	if not await walk_legs(EAST, "the pedestrian street east"):
		return false
	check(c.pos.distance_to(p0) > 8.0, "the child moved by input (%.1f m)" % c.pos.distance_to(p0))
	await frame_shot("explore_street", "exploring: walked east along the pedestrian street from the forecourt (the camera followed)")
	# the camera follows: it stays behind and near the child
	var k := kid()
	var d_cam: float = cam().global_position.distance_to(k.global_position + Vector3(0, 0.9, 0))
	check(d_cam < main.rig.t_dist + 1.0 and kid_screen()["on"], "the follow camera kept up (%.1f m from the chest)" % d_cam)
	# orbit: a drag / the right stick; zoom: a pinch / the triggers
	var y0: float = main.rig.t_yaw
	if pad_mode:
		await pad_orbit_by(-1.2)
	else:
		var s := world_spot()
		await drag(s, s + Vector2(-260, 0), 10)
	var dy: float = absf(wrapf(main.rig.t_yaw - y0, -PI, PI))
	check(dy > 0.3, "%s orbits the camera around the child (%.2f rad)" % ["the right stick" if pad_mode else "a drag", dy])
	await frames(2)
	check(kid_screen()["on"], "the child stays on screen while orbiting")
	await frame_shot("explore_orbit", "exploring: the camera orbited by %s around the child (a view to its side)" % ("the right stick" if pad_mode else "a drag"))
	var d0: float = main.rig.t_dist
	if pad_mode:
		axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await frames(3)
		axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		await frames(3)
	else:
		var g := InputEventMagnifyGesture.new()
		g.factor = 0.8
		g.position = get_viewport().get_final_transform() * world_spot()
		Input.parse_input_event(g)
		await frames(3)
	var d1: float = main.rig.t_dist
	check(d1 > d0 + 0.5, "%s zooms out (%.1f -> %.1f m)" % ["ZR" if pad_mode else "a pinch", d0, d1])
	if pad_mode:
		axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
		await frames(3)
		axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
		await frames(3)
	else:
		var g2 := InputEventMagnifyGesture.new()
		g2.factor = 1.25
		g2.position = get_viewport().get_final_transform() * world_spot()
		Input.parse_input_event(g2)
		await frames(3)
	check(absf(main.rig.t_dist - d0) < 0.3, "%s zooms back in (%.1f m)" % ["ZL" if pad_mode else "a pinch", main.rig.t_dist])
	# the canal stops the child: east to the water's edge, then into it
	if not await walk_legs([Vector2(-12.0, 3.6)], "to the canal's west bank"):
		return false
	var before: Vector2 = c.pos
	if pad_mode:
		var t := 0.0
		var n1 := 0
		while t < 2.0 and n1 < 600:
			n1 += 1
			var dt1: float = await stick_step(Vector2(10.0, 3.6), 1.0)
			t += 0.0 if _turned else dt1   # pushing time only (turning the camera first does not count)
		stick_off()
	else:
		await touch_face(Vector2(2.0, 3.6))
		var tapped := await tap_ground(Vector2(2.0, 3.6), "the canal")
		check(tapped, "a tap on the canal's water")
		await until_g(func(): return c._walk_target == null, 4.0)
	check(c.pos.x > before.x + 2.0 and c.pos.x <= -7.5, "walking into the canal stops at the bank (x %.2f; the water is |x| < 7.5)" % c.pos.x)
	await frame_shot("canal_bank", "exploring: the child stopped at the canal's bank (no bridge here); the towers across the water")
	return await _try_hello("the canal bank")


## I1 and I2, wherever the child is when a resident walks by: Say hello, their card, Follow, the chip, Stop; then
## back the way the child came. Tried on the way (the forecourt, the canal bank, Courtyard Housing, each street
## corner to the bus stop) until it has happened once. Returns false when it could not get back.
func _try_hello(where: String) -> bool:
	if _hello_done:
		return true
	var who := -1
	for look in (1 if pad_mode else 4):
		if pad_mode:
			# a walker to catch up with on fast frames; on EC2's software GL (seconds a frame) the residents keep the
			# wall-clock pace of the town's clock while each press reaches the game frames later: someone standing
			who = _walker_near([]) if _last_gdt < 0.1 else -1
			if who < 0:
				who = _still_near()
		else:
			who = _walker_on_screen()
		if who >= 0:
			break
		await _look_around(PI / 2.0)
	if who < 0:
		print("DIAG nobody walking by at %s (%s)" % [where, clock_text()])
		return true
	_hello_done = true
	_trail = [c.pos]
	_trail_on = true
	await _meet_and_follow(who)
	# back the way the child came (a walkable trail)
	_trail_on = false
	_trail.append(c.pos)
	_trail.reverse()
	if tp.card_open:
		if pad_mode:
			await btn(pad.back_button())
		else:
			await press(hud._tt_card.find_child("CloseCard", true, false))
	var start: Vector2 = _trail.back()
	var simple := _simplify(_trail)
	if await walk_legs(simple, "back along the way the child came (to %s)" % where, 1.0, true) and await walk_legs([start], "", 0.4, true):
		check(true, "back along the way the child came (to %s): walked to %s" % [where, c.pos.snapped(Vector2(0.01, 0.01))])
		return true
	# a cut corner did not suit the child's own walking: the whole trail from the nearest point of it
	var k := 0
	for i in _trail.size():
		if (_trail[i] as Vector2).distance_to(c.pos) < (_trail[k] as Vector2).distance_to(c.pos):
			k = i
	return await walk_legs(_trail.slice(k), "back along the way the child came (to %s)" % where, 1.2) \
		and await walk_legs([start], "back to %s" % where, 0.6)


func _meet_and_follow(who: int) -> void:
	var still: bool = str(pp().info(who, "en").get("mode", "")) not in ["walk", "jog"]
	if pad_mode and still:
		# walk up to them with the stick, then X (or Y) while Say hello is offered
		var rs: Vector3 = pp().position_of(who)
		var q := Vector2(rs.x, rs.z)
		await walk_legs([q + (c.pos - q).normalized() * 1.5], "up to a resident standing nearby", 0.8)
		var got := ""
		if await until_g(func(): return str(c._ctx.get("type", "")) == "tt_hello" or str((c._ctx.get("alt", {}) as Dictionary).get("type", "")) == "tt_hello", 2.0):
			got = "main" if str(c._ctx.get("type", "")) == "tt_hello" else "alt"
		check(got != "", "beside them the action buttons offer Say hello (%s)" % hud._context_btn.text)
		if got == "":
			_hello_done = false
			return
		await btn(JOY_BUTTON_Y if got == "main" else JOY_BUTTON_X)
	elif pad_mode:
		# catch up with them with the stick (the child walks 3.4 m/s, residents at most 2.2) until the action
		# buttons offer Say hello; then X (or Y for the second action button)
		var got := ""
		var t := 0.0
		var stuck := 0.0
		while t < 25.0 and got == "" and stuck < 1.5:
			var rp: Vector3 = pp().position_of(who)
			if rp == Vector3.INF:
				break
			var d: float = c.pos.distance_to(Vector2(rp.x, rp.z))
			var before: Vector2 = c.pos
			var dt: float = await stick_step(Vector2(rp.x, rp.z), 1.0 if d > 1.2 else 0.6)
			t += dt
			stuck = stuck + dt if c.pos.distance_to(before) < 0.004 and d > 1.2 and not _turned else 0.0
			if str(c._ctx.get("type", "")) == "tt_hello":
				got = "main"
			elif str((c._ctx.get("alt", {}) as Dictionary).get("type", "")) == "tt_hello":
				got = "alt"
			if got != "":
				# pressed at once, still walking with them (they would be out of reach a moment later)
				joy(JOY_BUTTON_Y if got == "main" else JOY_BUTTON_X, true)
				for k in 3:
					var rq: Vector3 = pp().position_of(who)
					stick_toward(Vector2(rq.x, rq.z), 0.6)
					await get_tree().process_frame
				joy(JOY_BUTTON_Y if got == "main" else JOY_BUTTON_X, false)
		stick_off()
		await frames(2)
		if got == "":
			var rp2: Vector3 = pp().position_of(who)
			print("DIAG lost resident %d (%s) after %.1f s, stuck %.1f s, %.1f m away" % [who, str(pp().info(who, "en").get("mode", "")), t, stuck,
				c.pos.distance_to(Vector2(rp2.x, rp2.z)) if rp2 != Vector3.INF else -1.0])
			_hello_done = false   # try again with someone else further on
			return
		check(true, "catching up with a resident by the stick: the action buttons offer Say hello, pressed (%s)" % ("X" if got == "main" else "Y"))
	else:
		# a tap on them; a software-rendered frame lasts long enough for a walker to move a body width, so the
		# finger leads them by one frame (where they will be when the tap is released), and tries again if missed
		for k in 4:
			if k == 2:
				# EC2's software GL draws a frame in about 2 s, and the residents keep the town clock's (wall-clock)
				# pace, so a walker moves 2-3 m between a finger's press and release: someone standing still instead
				var still_id := _walker_on_screen(true)
				if still_id < 0:
					break
				print("DIAG the walker moved too far between frames for a tap; meeting resident %d, who stands still" % still_id)
				who = still_id
			var p0: Vector3 = pp().position_of(who)
			await get_tree().process_frame
			var p1: Vector3 = pp().position_of(who)
			if p0 == Vector3.INF or p1 == Vector3.INF or cam().is_position_behind(p1):
				break
			var aim := cam().unproject_position(p1 + (p1 - p0) + Vector3(0, 1.1, 0))
			if not playable_rect().has_point(aim) or ui_blocker_at(aim) != "":
				break
			await tap(aim)
			if await until_g(func(): return tp.card_open, 0.5):
				break
	var opened := await until_g(func(): return tp.card_open and hud._tt_card.is_visible_in_tree(), 2.0)
	if not opened and not still:
		# a walker can be out of reach again by the time the press (or, on software GL, the finger's release) arrives:
		# the next one further on (the loop checks at the bus stop that somebody was met)
		print("DIAG Say hello / the tap missed %d, who had walked on; trying again further on" % who)
		_hello_done = false
		return
	check(opened, "%s: the child greets them and the resident card opens" % ("X / Y Say hello" if pad_mode else "a tap on the resident"))
	if not opened:
		return
	var met: int = tp.selected
	var info: Dictionary = pp().info(met, "en")
	check(hud._tt_card_name.text == tw().sim.name_of(met, "en") and hud._tt_card_name.text != "", "the card names them (%s)" % hud._tt_card_name.text)
	check(hud._tt_card_who.text.contains(str(int(info.get("age", -1)))) and hud._tt_card_now.text != "", "role, age and what they do now (%s; %s; %s)" % [hud._tt_card_who.text, hud._tt_card_now.text, hud._tt_card_heading.text])
	check(kid().emote_kind == "wave", "the child waves")
	check(await until_g(func(): return tp._marker != null and tp._marker.visible, 1.0), "a marker floats over them")
	# the camera turned (a drag / the right stick) so the resident is in view beside the child, as a player would
	var rpm: Vector3 = pp().position_of(met)
	if rpm != Vector3.INF:
		var dm: Vector2 = Vector2(rpm.x, rpm.z) - c.pos
		var want_m := atan2(-dm.x, -dm.y) + 0.45
		if pad_mode:
			await pad_orbit_by(wrapf(want_m - main.rig.t_yaw, -PI, PI))
		else:
			var px := clampf(wrapf(main.rig.t_yaw - want_m, -PI, PI) / main.rig.T_ORBIT_PER_PX, -900.0, 900.0)
			var sp := world_spot()
			await drag(sp - Vector2(px * 0.5, 0), sp + Vector2(px * 0.5, 0), 6)
	await frame_shot("hello_card", "I1 Say hello: the resident card (name, role, age, now, heading) and the marker over them")
	if not hud._tt_card_follow.is_visible_in_tree():
		check(false, "the card offers Follow (they are %s)" % str(info.get("mode", "")))
		if pad_mode:
			await btn(pad.back_button())
		else:
			await press(hud._tt_card.find_child("CloseCard", true, false))
		return
	if pad_mode:
		await pad_press(hud._tt_card_follow, "Follow")
	else:
		await press(hud._tt_card_follow)
	var following := await until_g(func(): return tp.state == "follow" and hud._tt_chip.is_visible_in_tree(), 2.0)
	check(following, "Follow: the card gives way to the chip")
	if not following:
		return
	check(hud._tt_chip_label.text.begins_with("Following " + tw().sim.name_of(met, "en")), "the chip: %s" % hud._tt_chip_label.text)
	var start: Vector2 = c.pos
	var rp_start: Vector3 = pp().position_of(met)
	var t2 := 0.0
	var gap := INF
	# following for a while: at least 4 s, and until the child has caught up (it walks faster than any resident)
	_catchup(true)
	while (t2 < 4.0 or gap > 6.0) and t2 < 7.0 and tp.state == "follow":
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		var rq: Vector3 = pp().position_of(met)
		gap = c.pos.distance_to(Vector2(rq.x, rq.z)) if rq != Vector3.INF else INF
	_catchup(false)
	var rp2: Vector3 = pp().position_of(met)
	gap = c.pos.distance_to(Vector2(rp2.x, rp2.z))
	var they_moved: float = Vector2(rp_start.x, rp_start.z).distance_to(Vector2(rp2.x, rp2.z)) if rp2 != Vector3.INF else 0.0
	check(c.pos.distance_to(start) > 2.0 or (they_moved < 2.0 and gap < 4.5),
		"the child walks after them by itself (%.1f m; they moved %.1f m)" % [c.pos.distance_to(start), they_moved])
	check(tp.state in ["follow", "follow_inside"] and (gap < 9.0 or tp.state == "follow_inside"),
		"and keeps up (%.1f m behind after %.1f s; %s)" % [gap, t2, "still following" if tp.state == "follow" else "the follow went on to: '%s', toast '%s'" % [tp.state, hud._toast_label.text]])
	var walking_now: bool = str(pp().info(met, "en").get("mode", "")) in ["walk", "jog"]
	check(int(tp._route.get_meta("dashes", 0)) > 0 or tp.state != "follow" or not walking_now,
		"their way ahead is drawn on the ground (%d dashes; %s)" % [int(tp._route.get_meta("dashes", 0)), "walking" if walking_now else "standing still, no way to draw"])
	await frame_shot("follow_chip", "I2 Following: the chip (Following NAME, to PLACE, about N min, Stop) and their way drawn on the ground")
	if pad_mode:
		await btn(pad.back_button())
	else:
		var stop_btn: Button = hud._tt_chip_btns.find_child("Chip_end", true, false)
		await press(stop_btn)
	check(await until_g(func(): return tp.state == "" and not hud._tt_chip.is_visible_in_tree(), 2.0), "%s ends following; the chip goes" % ("B" if pad_mode else "Stop"))


## A walked trail cut to its corners: from each point, on to the farthest later point the child's own walking reaches
## in a straight line (the world's resolver, as the controller walks) and at most 14 m away.
func _simplify(trail: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < trail.size() - 1:
		var j := trail.size() - 1
		while j > i + 1 and ((trail[i] as Vector2).distance_to(trail[j]) > 14.0 or not _straight_walk(trail[i], trail[j])):
			j -= 1
		out.append(trail[j])
		i = j
	return out


## Whether the child walks straight from `a` to `b` without a wall turning it aside (read only: the resolver).
func _straight_walk(a: Vector2, b: Vector2) -> bool:
	var cur := a
	if a.distance_to(b) > 40.0 or tw()._blocked(a):
		return false
	var n := ceili(a.distance_to(b) / 0.1)
	for k in range(1, n + 1):
		var want: Vector2 = a.lerp(b, float(k) / n)
		var nx: Vector2 = tw().resolve_walk(want, cur)
		if nx.distance_to(want) > 0.02:
			return false
		cur = nx
	return true


## TV on slow frames: the nearest drawn resident standing still (talking, waiting, standing) whom the child reaches by
## a straight walk to 1.5 m short of them, or -1.
func _still_near() -> int:
	var near: Array = []
	for id: int in pp().drawn_ids():
		var info: Dictionary = pp().info(id, "en")
		if str(info.get("mode", "")) not in ["stand", "talk", "wait", "waiting", "eat"]:
			continue
		var p: Vector3 = pp().position_of(id)
		if p == Vector3.INF:
			continue
		var d := Vector2(p.x, p.z).distance_to(c.pos)
		if d < 25.0 and d > 0.5:
			near.append([d, id, Vector2(p.x, p.z)])
	near.sort()
	for e: Array in near.slice(0, 8):
		var q: Vector2 = e[2]
		if _straight_walk(c.pos, q + (c.pos - q).normalized() * 1.5):
			return int(e[1])
	return -1


## TV: the nearest drawn resident walking a long way, with a clear straight way to them (not in `skip`), or -1.
func _walker_near(skip: Array) -> int:
	var g = load("res://scripts/art/thousand_people.gd").ground()
	var best := -1
	var bd := 35.0
	var why := {}
	for id: int in pp().drawn_ids():
		if skip.has(id):
			continue
		var info: Dictionary = pp().info(id, "en")
		var p: Vector3 = pp().position_of(id)
		var d := Vector2(p.x, p.z).distance_to(c.pos)
		var r := ""
		if str(info.get("mode", "")) not in ["walk", "jog"]:
			r = "mode " + str(info.get("mode", ""))
		elif float(info.get("remaining_m", 0.0)) < 12.0 and str(info.get("trip", "")) != "outing":
			r = "short"
		elif d >= bd:
			r = "far"
		elif not g.clear(c.pos, Vector2(p.x, p.z)):
			r = "no clear way"
		if r != "":
			why[r] = int(why.get(r, 0)) + 1
			continue
		bd = d
		best = id
	if best < 0:
		print("DIAG no walker near %s: %s" % [c.pos, str(why)])
	return best


## Orbits the follow camera by about `angle` radians: a drag (touch) or the right stick (TV).
func _look_around(angle: float) -> void:
	var y0: float = main.rig.t_yaw
	if pad_mode:
		await pad_orbit_by(-angle)
	else:
		var s := world_spot()
		await drag(s + Vector2(angle / main.rig.T_ORBIT_PER_PX * 0.5, 0), s - Vector2(angle / main.rig.T_ORBIT_PER_PX * 0.5, 0), 6)


## A drawn resident on screen near the child who walks somewhere (a long trip, not a bus rider), with a clear
## straight way to them (the controller walks up to them).
func _walker_on_screen(still := false) -> int:
	var best := -1
	var bd := 22.0
	var area := playable_rect()
	var g = load("res://scripts/art/thousand_people.gd").ground()
	var why := {}
	for id: int in pp().drawn_ids():
		var info: Dictionary = pp().info(id, "en")
		var r := ""
		var p: Vector3 = pp().position_of(id)
		var d := Vector2(p.x, p.z).distance_to(c.pos)
		var aim := cam().unproject_position(p + Vector3(0, 1.1, 0))
		if still:
			if str(info.get("mode", "")) not in ["stand", "talk", "wait", "waiting", "eat"]:
				r = "mode"
		elif str(info.get("mode", "")) not in ["walk", "jog"]:
			r = "mode"
		elif float(info.get("remaining_m", 0.0)) < 8.0 and str(info.get("trip", "")) not in ["outing", "loop"]:
			r = "short trip"
		elif d < 2.5 or d >= bd:
			r = "distance"
		elif cam().is_position_behind(p) or not area.has_point(aim) or ui_blocker_at(aim) != "":
			r = "off screen"
		elif pad_mode and not g.clear(c.pos, Vector2(p.x, p.z)):
			r = "no clear way"   # the controller walks up to them
		elif pp().pick_screen(cam(), aim) != id:
			r = "hidden"
		if r != "":
			why[r] = int(why.get(r, 0)) + 1
			continue
		bd = d
		best = id
	if best < 0:
		print("DIAG no walker: %s" % str(why))
	return best


## I3: Who's here? at Courtyard Housing: the panel with the people in it now, then closed.
func _who_is_here() -> bool:
	if not await walk_legs(TO_COURTYARD, "to Courtyard Housing", 1.0):
		return false
	var door: Vector2 = tw().door_point(COURTYARD)
	if pad_mode:
		await walk_legs([door], "to its door", 0.6)
		check(await until_g(func(): return c._ctx.get("type", "") == "thousand_inspect" and str(c._ctx.get("id", "")) == COURTYARD, 2.0),
			"at the door the action button offers Who's here? (%s)" % hud._context_btn.text)
		await btn(JOY_BUTTON_Y)
	else:
		# a tap on the building: the child walks to its door and asks who is there
		var rect: Rect2 = tw().building_at(door + Vector2(0, -3.0)).get("rect", Rect2())
		check(rect.has_area(), "Courtyard Housing's walls are in front of the child")
		await touch_face(Vector2(door.x, rect.get_center().y))
		await settle_camera(2.0)
		var aimed := Vector2(-1, -1)
		for dx in [-2.0, -4.0, 2.0, -6.0, 4.0]:
			for h in [0.6, 1.4]:
				if aimed.x >= 0.0:
					continue
				var face := Vector3(door.x + dx, h, rect.end.y - 0.8)
				if cam().is_position_behind(face):
					continue
				var aim := cam().unproject_position(face)
				var gp = main.world.ground_point(cam(), aim)
				if not playable_rect().has_point(aim) or ui_blocker_at(aim) != "" or pp().pick_screen(cam(), aim) >= 0:
					continue
				if gp is Vector2 and str(tw().building_at(gp).get("id", "")) == COURTYARD:
					aimed = aim
		check(aimed.x >= 0.0, "Courtyard Housing's front is on screen for a finger")
		if aimed.x >= 0.0:
			await tap(aimed)
			await frames(2)
			print("DIAG building tap at %s: ground %s, walk %s, pending %s, ctx %s, card %s, dialogs %d, child %s" % [aimed.round(),
				str(main.world.ground_point(cam(), aimed)), str(c._walk_target), str(c._pending_ctx.get("type", "")), str(c._ctx.get("type", "")),
				tp.card_open, hud._overlay.get_child_count(), c.pos])
	var panel_ok := await until_g(func(): return hud.thousand_inspect_panel() != null, 8.0)
	check(panel_ok, "%s opens the Who's here? panel" % ("X at the door" if pad_mode else "a tap on the building"))
	if not panel_ok:
		return true
	var panel: Node = hud.thousand_inspect_panel()
	var row: Dictionary = tp.site_row(COURTYARD)
	var here: Array = panel.data.get("here", [])
	check(str(panel.get_meta("building", "")) == COURTYARD, "for Courtyard Housing")
	check(not row.is_empty() and here.size() == mini(int(row.get("count", -1)), 12) and (panel.get_node("Status") as Label).text.contains(str(int(row.get("count", -1)))),
		"it lists the people in it now, as the simulation's sample says (%d here; %s)" % [int(row.get("count", -1)), (panel.get_node("Status") as Label).text])
	var names: Array = here.map(func(r): return str(r.get("name", "")))
	check(here.is_empty() or names.all(func(n): return n != ""), "real residents by name (%s)" % ", ".join(names.slice(0, 4)))
	await frame_shot("whos_here", "I3 Who's here? at Courtyard Housing: open or closed, how many are in it now, their names")
	if pad_mode:
		await btn(pad.back_button())
	else:
		await press(_dialog_button("Close"))
	check(await until_g(func(): return hud.thousand_inspect_panel() == null and not modal(), 2.0), "%s closes the panel" % ("B" if pad_mode else "Close"))
	# occlusion: the camera swung round behind the building's wall; it pulls in or dithers, the child stays seen
	# the nearest turn of the camera that puts a building's wall between it and the child
	var want: float = main.rig.t_yaw
	var kd := INF
	var kid0: Vector3 = kid().global_position
	for k in 24:
		var yaw := TAU * k / 24.0
		var eye0: Vector3 = main.rig.follow_xform(kid0, yaw, main.rig.t_dist).origin
		var hit: float = main.rig.pull_in(kid0 + Vector3(0, 0.9, 0), eye0, tw().occluders())
		if hit < (kid0 + Vector3(0, 0.9, 0)).distance_to(eye0) - 0.5 and absf(wrapf(yaw - main.rig.t_yaw, -PI, PI)) < kd:
			kd = absf(wrapf(yaw - main.rig.t_yaw, -PI, PI))
			want = yaw
	if pad_mode:
		await pad_orbit_by(wrapf(want - main.rig.t_yaw, -PI, PI))
	else:
		var diff := wrapf(main.rig.t_yaw - want, -PI, PI)
		var s := world_spot()
		await drag(s, s + Vector2(diff / main.rig.T_ORBIT_PER_PX, 0), 12)
	await frames(3)
	var k := kid()
	var chest := k.global_position + Vector3(0, 0.9, 0)
	var eye: Vector3 = cam().global_position
	var boxes: Array = tw().occluders()
	var inside := boxes.filter(func(b): return (b as AABB).has_point(eye))
	var between: Array = main.rig.blocking(chest, eye, boxes)
	var pulled: bool = eye.distance_to(chest) < main.rig.follow_xform(k.global_position, main.rig.t_yaw, main.rig.t_dist).origin.distance_to(chest) - 0.3
	check(inside.is_empty(), "with the camera turned toward the building it is not inside a solid")
	check(pulled or not between.is_empty(), "the camera is pulled in (%.1f m) or the building between is dithered (%s)" % [eye.distance_to(chest), str(between)])
	check(between.all(func(i): return (tw().occluded() as Array).has(i)), "whatever stands between is drawn dithered (%s of %s)" % [str(tw().occluded()), str(between)])
	check(kid_screen()["on"], "and the child stays on screen")
	check(kd < INF, "a turn of the camera puts Courtyard Housing between the camera and the child")
	await frame_shot("occlusion", "occlusion: the camera turned toward Courtyard Housing; it is pulled in before the wall, the child in view")
	return await _try_hello("Courtyard Housing")


func _dialog_button(text: String) -> Button:
	for b in hud._overlay.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and (b as Button).text == text:
			return b
	return null


## I4: the bus. Wait at bus stop 3 (the chip counts down), Auto at 4x, board, ride, get off at the next stop.
func _bus() -> bool:
	for w: Vector2 in TO_STOP:
		if not await walk_legs([w], "south and east through the streets to bus stop 3", 1.0):
			return false
		if not await _try_hello("the street corner %s" % w):
			return false
	check(_hello_done, "a resident walked by somewhere on the way to say hello to (I1, I2)")
	await frame_shot("explore_south", "exploring: down the street west of the towers to the cross street at z -44 (bus stop 3 ahead)")
	var offered := await until_g(func(): return c._ctx.get("type", "") in ["tt_wait", "tt_board"], 2.0)
	check(offered, "at the stop the action button offers the bus (%s)" % hud._context_btn.text)
	if not offered:
		return false
	if str(c._ctx.get("type", "")) == "tt_wait":
		if pad_mode:
			await btn(JOY_BUTTON_Y)
		else:
			await press(hud._context_btn)
		check(await until_g(func(): return tp.state == "wait_bus" and hud._tt_chip.is_visible_in_tree(), 2.0), "Wait for the bus: the chip")
		await until_g(func(): return c._walk_target == null, 3.0)
		var t0: String = hud._tt_chip_label.text
		check(t0.contains("next bus in"), "the chip counts down to the next bus (%s)" % t0)
		await until_g(func(): return hud._tt_chip_label.text != t0, 3.0)
		check(hud._tt_chip_label.text != t0 or hud._tt_chip_label.text.contains("is here"), "and the countdown runs (%s)" % hud._tt_chip_label.text)
		await frame_shot("bus_wait", "I4 waiting at bus stop 3: the chip counts down to the next bus")
		# the clock to 4x with the Auto button (a second and a third press while it runs)
		for i in 2:
			if pad_mode:
				await pad_press(hud._thousand_time_btns["auto"], "Auto")
			else:
				await press(hud._thousand_time_btns["auto"])
			await until_g(func(): return int(thousand_node().states["speed"]) == [2, 4][i], 2.0)
		check(int(thousand_node().states["speed"]) == 4 and hud.thousand_speed_badge() == "4×", "Auto pressed twice more: the clock runs at 4x (%s)" % hud.thousand_speed_badge())
		check(tp.state == "wait_bus", "still waiting at the stop")
		var came := await until_g(func(): return c._ctx.get("type", "") == "tt_board", 45.0)
		check(came, "the bus comes: The bus is here! (%s)" % hud._tt_chip_label.text)
		if not came:
			return false
	if pad_mode:
		await btn(JOY_BUTTON_Y)
	else:
		var b: Button = hud._tt_chip_btns.find_child("Chip_bus_board", true, false)
		await press(b if b != null else hud._context_btn)
	var on := await until_g(func(): return tp.state == "bus", 2.0)
	check(on, "Get on the bus: the child boards")
	if not on:
		return false
	var vid: String = tp.bus_id
	check(await until_g(func(): return kid().anim == "sit" and kid().global_position.distance_to(main.world.thousand_transit.vehicle(vid).pos) < 3.5, 1.0),
		"seated in the bus (%s, %.1f m from the bus)" % [kid().anim, kid().global_position.distance_to(main.world.thousand_transit.vehicle(vid).pos)])
	var rode := await until_g(func(): return str(main.world.thousand_transit.vehicle(vid).get("status", "")) != "dwelling", 20.0)
	check(rode, "the bus leaves the stop with the child")
	await until_g(func(): return hud._tt_chip_label.text.contains("next stop"), 3.0)
	check(hud._tt_chip_label.text.contains("next stop"), "the riding chip names the next stop (%s)" % hud._tt_chip_label.text)
	check(main.rig.t_dist >= 10.0 and kid_screen()["on"], "the camera stands back behind the bus, the child in view")
	await frame_shot("bus_riding", "I4 riding the bus: seated inside, the camera behind the bus, the chip names the next stop")
	var at_stop := await until_g(func(): return c._ctx.get("type", "") == "tt_bus_off", 40.0)
	check(at_stop, "at the next stop: Get off (%s)" % hud._tt_chip_label.text)
	if not at_stop:
		return false
	var stop_now := str(main.world.thousand_transit.vehicle(vid).get("stop", ""))
	if pad_mode:
		await btn(JOY_BUTTON_Y)
	else:
		await press(hud._context_btn)
	var off := await until_g(func(): return tp.state == "" and kid().anim != "sit", 2.0)
	check(off and stop_now == "bus-stop-4", "off the bus at the next stop (%s)" % stop_now)
	check(absf(main.rig.t_dist - main.rig.T_DIST) < 0.5, "the camera back behind the child")
	await frame_shot("bus_off", "I4 got off at bus stop 4, across the canal; the toast names the stop")
	return off


## Day, Dusk and Night by the HUD's time buttons: the town's light follows (daylight, lamps, lit windows).
func _lighting() -> bool:
	# toward the market's promenade, then each preset
	if not await walk_legs([Vector2(12.75, -50.25)], "from the stop toward the night market", 1.0):
		return false
	var seen := {}
	for m in ["day", "dusk", "night"]:
		if pad_mode:
			await pad_press(hud._thousand_time_btns[m], m.capitalize())
		else:
			await press(hud._thousand_time_btns[m])
		var held := await until_g(func(): return str(thousand_node().states["mode"]) == m, 2.0)
		await game_wait(0.5)
		var l: Dictionary = tw().light
		seen[m] = {"minute": float(l.get("minute", -1.0)), "daylight": float(l.get("daylight", -1.0)), "lamps": float(l.get("lamps", -1.0)),
			"windows_lit": int(l.get("windows_lit", -1)), "sun": float(l.get("sun_energy", -1.0))}
		check(held and (hud._thousand_time_btns[m] as Button).modulate.a > 0.99, "%s: the town's time is held and the button lit (%s)" % [m.capitalize(), clock_text()])
		print("LIGHT %s %s" % [m, str(seen[m])])
		await frame_shot("light_" + m, "%s by the time button: %s" % [m.capitalize(), {"day": "12:00, full daylight", "dusk": "18:40, the low sun, lamps coming on", "night": "21:30, lamps, lit windows, the market's lanterns"}[m]])
	if pad_mode:
		# the triggers zoom wherever the pointer rests, here on the Night button just pressed
		var on_btn: bool = (hud._thousand_time_btns["night"] as Control).get_global_rect().has_point(pad.cursor)
		var z0: float = main.rig.t_dist
		axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await frames(3)
		axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		await frames(3)
		var z1: float = main.rig.t_dist
		axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
		await frames(3)
		axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
		await frames(3)
		check(z1 > z0 + 0.5 and absf(main.rig.t_dist - z0) < 0.3, "ZR and ZL zoom with the pointer on a HUD button (on the Night button: %s; %.1f -> %.1f -> %.1f m)" % [on_btn, z0, z1, main.rig.t_dist])
	var d: Dictionary = seen.get("day", {})
	var u: Dictionary = seen.get("dusk", {})
	var n: Dictionary = seen.get("night", {})
	if d.is_empty() or u.is_empty() or n.is_empty():
		return false
	check(is_equal_approx(d.minute, 720.0) and is_equal_approx(u.minute, 1120.0) and is_equal_approx(n.minute, 1290.0), "the world draws 12:00, 18:40 and 21:30")
	check(d.daylight > 0.99 and u.daylight > 0.0 and u.daylight < d.daylight and n.daylight < 0.05, "the daylight factor falls: %.2f, %.2f, %.2f" % [d.daylight, u.daylight, n.daylight])
	check(d.sun > u.sun and u.sun >= n.sun, "the sun dims: %.2f, %.2f, %.2f" % [d.sun, u.sun, n.sun])
	check(d.lamps < 0.01 and n.lamps > 0.5 and n.lamps >= u.lamps, "the lamps come on: %.2f, %.2f, %.2f" % [d.lamps, u.lamps, n.lamps])
	check(n.windows_lit > d.windows_lit, "more windows are lit at night: %d, %d, %d" % [d.windows_lit, u.windows_lit, n.windows_lit])
	return true


## I6: a snack at a night market stall (open at 21:30).
func _market() -> bool:
	var stall: Dictionary = preload("res://scripts/core/thousand_map.gd").data().waterfront.stalls[STALL]
	var counter := Vector2(float(stall.x) - float(stall.side) * (float(stall.d) * 0.5 + 0.8), float(stall.z))
	# first the canal's edge on this side: walking west from the promenade stops at the water
	var before: Vector2 = c.pos
	if pad_mode:
		var t := 0.0
		var n2 := 0
		while t < 2.5 and n2 < 600:
			n2 += 1
			var dt2: float = await stick_step(Vector2(-4.0, c.pos.y), 1.0)
			t += 0.0 if _turned else dt2   # pushing time only
		stick_off()
	else:
		await touch_face(Vector2(2.0, c.pos.y))
		check(await tap_ground(Vector2(2.0, c.pos.y), "the canal"), "a tap on the canal's water from the east promenade")
		await until_g(func(): return c._walk_target == null, 4.0)
	check(c.pos.x < before.x - 1.0 and c.pos.x >= 7.5, "the canal stops the child on the east bank too (x %.2f)" % c.pos.x)
	if not await walk_legs([Vector2(12.75, -50.25), counter], "to a juice stall's counter", 0.7):
		return false
	check(tp.market_open() and bool(tw().light.get("market_busy", false)), "at 21:30 the night market is open and its lanterns bright")
	var offered := await until_g(func(): return c._ctx.get("type", "") == "tt_snack" or str((c._ctx.get("alt", {}) as Dictionary).get("type", "")) == "tt_snack", 2.0)
	check(offered, "the action buttons offer Buy a snack (%s / %s)" % [hud._context_btn.text, hud._context_alt_btn.text])
	if not offered:
		return true
	var main_one: bool = c._ctx.get("type", "") == "tt_snack"
	if pad_mode:
		await btn(JOY_BUTTON_Y if main_one else JOY_BUTTON_X)
	else:
		await press(hud._context_btn if main_one else hud._context_alt_btn)
	check(await until_g(func(): return tp.has_snack(), 2.0), "Buy a snack: the child has one")
	var snack: Node = kid().find_child("TTSnack", true, false)
	check(snack != null and snack.get_parent().name == "Hand", "held in the right hand")
	var keepers: Array = tp.market_keepers().map(func(i): return tw().sim.name_of(i, "en"))
	var toast_text: String = hud._toast_label.text
	check(keepers.any(func(nm): return toast_text.contains(nm)), "a shopkeeper who is at the market now hands it over (%s)" % toast_text)
	# the camera round to the child's right side (a drag / the right stick), where the snack is held
	var want_s: float = c.ry + PI * 0.5 + 0.35
	if pad_mode:
		await pad_orbit_by(wrapf(want_s - main.rig.t_yaw, -PI, PI))
	else:
		var pxs := clampf(wrapf(main.rig.t_yaw - want_s, -PI, PI) / main.rig.T_ORBIT_PER_PX, -900.0, 900.0)
		var ss := world_spot()
		await drag(ss - Vector2(pxs * 0.5, 0), ss + Vector2(pxs * 0.5, 0), 6)
	await frame_shot("market_snack", "I6 the night market at 21:30: a snack in the child's right hand (the camera turned to that side); the toast names the shopkeeper")
	return true


## I7: Watch the fireworks from the promenade (the show is on at 21:30), the camera on the bursts.
func _fireworks() -> bool:
	var b: Button = hud._tt_shows["fireworks"]
	check(b.is_visible_in_tree() and b.text == "Watch the fireworks", "the show button says the fireworks are on (%s)" % b.text)
	if pad_mode:
		await pad_press(b, "Watch the fireworks")
	else:
		await press(b)
	check(await until_g(func(): return tp.state == "watch", 2.0), "Watch the fireworks: the child goes to watch")
	var there := await until_g(func(): return tp._watch_arrived, 20.0)
	check(there and main.rig.t_watch is Transform3D, "at the watch point the camera turns to the show")
	await until_g(func(): return not main.rig.thousand_gliding(), 4.0)
	var ev: Node = main.world.thousand_events
	check(ev != null and bool(ev.status().get("fireworks", false)), "the fireworks are on")
	await until_g(func(): return int(ev.status().get("sparks", 0)) > 20, 12.0)
	await until_g(func(): return int(ev.status().get("sparks", 0)) >= 450, 15.0)   # a full moment of the show
	check(int(ev.status().get("sparks", 0)) > 0, "sparks in the sky (%d)" % int(ev.status().get("sparks", 0)))
	await until_g(func(): return hud._tt_chip_label.text == "Watching the fireworks", 2.0)
	check(hud._tt_chip_label.text == "Watching the fireworks", "the chip: %s" % hud._tt_chip_label.text)
	await frame_shot("fireworks", "I7 Watch the fireworks: the child on the promenade, the camera on the show (and the snack still in hand)")
	return tp.state == "watch"


## Ride home while watching: the journey card, the town, its HUD exactly as before, the child controllable.
func _home() -> bool:
	check(tp.state == "watch", "riding home from inside an interaction (watching the fireworks)")
	_journeys.clear()
	if pad_mode:
		await pad_press_journey(hud._ride_home, "Ride home", "town")
	else:
		await tap(hud._ride_home.get_global_rect().get_center())
	var started := await until_g(func(): return not _journey_started("town").is_empty(), 3.0)
	check(started, "Ride home starts the journey")
	if not started:
		return false
	var j := _journey_started("town")
	check(j[2] == "Back to town" and not j[3], "the journey card: %s" % j[2])
	if c.journey_to == "town":
		await frame_shot("ride_home_card", "Ride home: the journey card, Back to town")
	var home := await until_g(func(): return c.space == "town" and c.journey_to == "", 12.0)
	check(home, "back in the town")
	if not home:
		return false
	await game_wait(0.6)
	var board: Vector2 = TownModel.tram_stop_boarding(Session.model)
	check(c.pos.distance_to(board) < 1.0, "at the town's tram stop (%s)" % c.pos)
	check(tp.state == "" and not tp.card_open and not tp.has_snack() and main.rig.t_watch == null and not main.rig.on_thousand, "every Thousand Town interaction ended (no watching, card or snack), the town's camera")
	check(not hud._thousand_time.is_visible_in_tree() and not hud._thousand_look.is_visible_in_tree() and not hud._tt_box.is_visible_in_tree()
		and not hud._tt_shows["fireworks"].is_visible_in_tree() and not hud._tt_shows["fountain"].is_visible_in_tree(), "no Thousand time buttons, Look, chip, card or show buttons")
	await until_g(func(): return c._ctx.get("type", "") == "tram", 3.0)
	await frames(3)
	var now := visible_buttons()
	check(now == _town_buttons, "the town HUD exactly as it was at the stop before the journey (%d buttons; missing %s, extra %s)" % [now.size(),
		str(_town_buttons.filter(func(p): return not now.has(p))), str(now.filter(func(p): return not _town_buttons.has(p)))])
	check(kid() != null and kid().is_visible_in_tree() and kid().anim != "sit", "the child at home, as it was")
	await frame_shot("back_home", "back home at the town's tram stop: the town HUD as before the journey")
	# controllable at home
	var p0: Vector2 = c.pos
	var goal: Vector2 = p0 + Vector2(3.0, 2.0)
	if pad_mode:
		var t := 0.0
		while t < 1.5:
			var a := cam().unproject_position(Vector3(c.pos.x, 0, c.pos.y))
			var bb := cam().unproject_position(Vector3(goal.x, 0, goal.y))
			var v := (bb - a).normalized()
			axis(JOY_AXIS_LEFT_X, v.x)
			axis(JOY_AXIS_LEFT_Y, v.y)
			t += await step_frame()
		stick_off()
	else:
		await town_tap_open(goal, "the town's open ground")
		await until_g(func(): return c._walk_target == null, 4.0)
	check(c.pos.distance_to(p0) > 1.5, "the child walks at home by %s (%.1f m)" % ["the stick" if pad_mode else "a tap", c.pos.distance_to(p0)])
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	stick_off()
	# the watchers over the stay in Thousand Town
	check(_samples > 50, "the watchers sampled the stay in Thousand Town (%d frames)" % _samples)
	check(_in_solid.is_empty(), "the child never stood inside a solid (%s)" % str(_in_solid))
	check(_cam_in_box.is_empty(), "the follow camera was never inside an occluder box that was not dithered (%d frames inside a dithered one; misses %s)" % [_cam_in_dithered, str(_cam_in_box)])
	check(_undithered.is_empty(), "every occluder between the camera and the child was dithered (%d frames had one, at most %d at once; misses %s)" % [_occluded_frames, _max_occluded, str(_undithered)])
	check(_hidden_kid == 0, "the child was visible in every frame (%d hidden)" % _hidden_kid)
	if _catcher:
		for e in _catcher.errors:
			check(false, "unexpected engine error: %s" % e)
		OS.remove_logger(_catcher)
	write_readme()
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2", SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("THOUSAND LOOP TOUR %s: %d checks, %d failures" % [mode_name, _checks, failures])
	Music.quit_game(1 if failures > 0 else 0)
