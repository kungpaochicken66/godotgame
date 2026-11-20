## Thousand Town with the TV controller only (unified r4, Apple TV feedback): every step is a joypad event through
## the real TV layer (Input.parse_input_event -> PadInput -> the HUD, the controller, the camera rig); no action is
## called directly and no button is pressed by its signal.
##   the town stop -> D-pad and A on "Ride to Thousand Town" -> arrival -> the hints (concise, contextual, in the
##   controller's own labels) -> predictable D-pad focus (the time column steps down and back up the same way; every
##   HUD button reachable) -> the clock line explains Auto vs a held time -> the time button (- / Select) holds Day,
##   Dusk, Night and returns to Auto -> A on the Auto glass button from a held time -> the stick walks the child to
##   the ferris wheel along the pavements -> Y rides it -> on the wheel the right stick looks around the cabin's view
##   and ZL / ZR zoom it (the follow camera behind it does not move) -> off at the bottom (Y) -> the camera behind
##   the child as before -> Ride home (D-pad, A) -> the town.
##   Headless: scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_pad_tour.gd --tv \
##                 --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv
##             ... --pad-layout=standard ... --tag=atv-std
##   Rendered (Mac GPU): scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/thousand_pad_tour.gd \
##                 --tv --pad-layout=nintendo --tag=atv --shots=/abs/dir
## Ends with "THOUSAND PAD TOUR <tag>: N checks, F failures"; exits 1 on any failure.
extends "res://tests/zoo_tour.gd"

const TvModeT := preload("res://scripts/core/tv_mode.gd")
const PeopleT := preload("res://scripts/art/thousand_people.gd")

var c: Node
var hud: Control
var pad: Node


func _joy(b: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.set_meta("synthetic", true)   # injected by this test driver, not hardware
		e.button_index = b
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		Input.parse_input_event(e)
		await frames(2)


func _shot(name: String) -> void:
	if main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("%s/thousand_pad_%s_%s.png" % [shots, tag, name]) == OK, "saved " + name)


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


func _dpad_path(from: Vector2, target: Control) -> Array:
	var ts: Array = pad.targets()
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	var queue: Array = [[from, []]]
	var seen := {}
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		for dn in dirs:
			var n := _snap_from(ts, cur[0], dirs[dn])
			if n == null or seen.has(n):
				continue
			seen[n] = true
			var way: Array = (cur[1] as Array) + [dn]
			if n == target:
				return way
			queue.append([n.get_global_rect().get_center(), way])
	return []


const DPAD := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}


func point_at(target: Control, what: String) -> bool:
	for i in 16:
		if target.get_global_rect().has_point(pad.cursor):
			break
		var path := _dpad_path(pad.cursor, target)
		if path.is_empty():
			break
		await _joy(DPAD[path[0]])
	var on: bool = target.get_global_rect().has_point(pad.cursor)
	check(on, "the D-pad brings the pointer to %s" % what)
	return on


func press_button(target: Control, what: String) -> bool:
	if not await point_at(target, what):
		return false
	await _joy(pad.confirm_button())
	return true


func hint_text() -> String:
	return " | ".join(pad.hint_parts().map(func(p): return "%s %s" % [p[0], p[1]]))


## unified r6 (the Mac's uncapped display gave up a long leg after 1,500 frames, x 14.98 of 25): bounded by game time,
## 1,500 physics steps (25 s at 60 Hz) and 180 s of wall time, not by frames, so the display's frame rate does not matter.
func _stick_to(p: Vector2, tol: float) -> bool:
	var steps := [0]
	var tick := func(): steps[0] += 1
	get_tree().physics_frame.connect(tick)
	var t0 := Time.get_ticks_msec()
	while steps[0] < 1500 and Time.get_ticks_msec() - t0 < 180000:
		var d: Vector2 = p - c.pos
		if d.length() < tol:
			break
		var r: Vector2 = main.rig.flat_right()
		var f: Vector2 = main.rig.flat_forward()
		var v := Vector2(d.normalized().dot(r), -d.normalized().dot(f)).normalized() * (1.0 if d.length() > 1.5 else 0.6)
		_axis(JOY_AXIS_LEFT_X, v.x)
		_axis(JOY_AXIS_LEFT_Y, v.y)
		await frames(1)
	get_tree().physics_frame.disconnect(tick)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	return c.pos.distance_to(p) < tol + 0.3


## A breadth-first search on a 1 m grid over ThousandWorld._blocked (body plus a margin), 8 neighbours, then pulled tight: the legs of
## a walk from `a` to `b` (empty when there is no way).
func _plan(a: Vector2, b: Vector2) -> Array:
	var tw: Node3D = main.world.thousand_world
	var body: float = tw.BODY + 0.2
	var free := func(p: Vector2) -> bool: return not tw._blocked(p, body)
	var lo := Vector2(minf(a.x, b.x) - 40.0, minf(a.y, b.y) - 40.0)
	var size := Vector2i(int(absf(a.x - b.x) + 80.0), int(absf(a.y - b.y) + 80.0))
	var cell := func(p: Vector2) -> Vector2i: return Vector2i(int(round(p.x - lo.x)), int(round(p.y - lo.y)))
	var at := func(k: Vector2i) -> Vector2: return lo + Vector2(k)
	var start: Vector2i = cell.call(a)
	var goal: Vector2i = cell.call(b)
	var came := {start: start}
	var queue: Array = [start]
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var found := false
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if Vector2(cur - goal).length() < 1.5:
			goal = cur
			found = true
			break
		for d: Vector2i in dirs:
			var n: Vector2i = cur + d
			if came.has(n) or n.x < 0 or n.y < 0 or n.x > size.x or n.y > size.y:
				continue
			var pn: Vector2 = at.call(n)
			if not free.call(pn) or not free.call((pn + at.call(cur)) * 0.5):
				continue
			came[n] = cur
			queue.append(n)
	if not found:
		return []
	var path: Array = [b]
	var k2: Vector2i = goal
	while k2 != start:
		path.push_front(at.call(k2))
		k2 = came[k2]
	# pull tight: from each point, the farthest later point in a free straight line
	var clear := func(p: Vector2, q: Vector2) -> bool:
		var n := maxi(1, int(p.distance_to(q) / 0.25))
		for i in n + 1:
			if not free.call(p.lerp(q, float(i) / n)):
				return false
		return true
	var legs: Array = []
	var from: Vector2 = a
	var i := 0
	while i < path.size():
		var j := path.size() - 1
		while j > i and not clear.call(from, path[j]):
			j -= 1
		legs.append(path[j])
		from = path[j]
		i = j + 1
	return legs


func _mode() -> String:
	var t := get_node_or_null("/root/Thousand")
	return str(t.states.get("mode", "")) if t else ""


func _run() -> void:
	tv = true
	c = main.controller
	hud = main.hud
	pad = main.pad
	for f in ["user://thousand-pad-tour.json", "user://thousand-pad-tour.json.bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	check(TvModeT.active() and pad != null, "TV mode with the controller layer (--tv)")
	Session.start_solo("user://thousand-pad-tour.json", main.menus.avatar)
	await wait(1)
	await settle_camera()
	await walk_to(TownModel.tram_stop_boarding(Session.model))
	await until(func(): return c._ctx.get("type", "") == "tram" and hud._context_alt3_btn.is_visible_in_tree(), 8)
	await press_button(hud._context_alt3_btn, "Ride to Thousand Town")
	check(await until(func(): return c.space == "thousand" and c.journey_to == "", 20.0), "arrived in Thousand Town")
	await until(func(): return hud._journey_card == null or not hud._journey_card.visible, 4.0)
	await frames(6)
	await _hints()
	await _focus()
	await _time()
	await _wheel()
	await _home()
	print("THOUSAND PAD TOUR %s: %d checks, %d failures" % [tag, _checks, failures])
	Music.quit_game(1 if failures else 0)


## Concise, contextual, in this controller's labels.
func _hints() -> void:
	var parts: Array = pad.hint_parts()
	print("HINTS at arrival: ", hint_text())
	check(parts.size() <= 5, "at most five hints (%d: %s)" % [parts.size(), hint_text()])
	var names: Array = parts.map(func(p): return str(p[1]))
	check(not names.has("Jump to buttons") and not names.has("Pointer"), "no generic hints (%s)" % hint_text())
	check(parts.any(func(p): return str(p[1]) == "Time" and str(p[0]) == pad.label_of(JOY_BUTTON_BACK)), "the time button named by its own label (%s)" % pad.label_of(JOY_BUTTON_BACK))
	check(parts.any(func(p): return str(p[1]) == "Turn camera"), "the camera on the right stick")
	var want_back := "-" if pad.layout == "nintendo" else "Select"
	check(pad.label_of(JOY_BUTTON_BACK) == want_back and pad.label_of_axis(JOY_AXIS_TRIGGER_RIGHT) == ("ZR" if pad.layout == "nintendo" else "RT"),
		"layout-aware labels (%s: %s, %s)" % [pad.layout, pad.label_of(JOY_BUTTON_BACK), pad.label_of_axis(JOY_AXIS_TRIGGER_RIGHT)])
	var shown: String = pad._hint_label.text if pad.get("_hint_label") else ""
	check(shown != "" and pad._hint_panel.visible, "the hint bar shows (%s)" % shown)
	await _shot("arrival_hints")


## Predictable D-pad focus: the time column steps down and back up through the same buttons, and every HUD button
## can be reached from every other.
func _focus() -> void:
	var order := ["day", "dusk", "night", "auto"]
	if not await point_at(hud._thousand_time_btns["day"], "Day"):
		return
	var down_seen := ["day"]
	for i in 3:
		await _joy(JOY_BUTTON_DPAD_DOWN)
		for m in order:
			if (hud._thousand_time_btns[m] as Control).get_global_rect().has_point(pad.cursor):
				down_seen.append(m)
	check(down_seen == order, "D-pad down walks the time column in order (%s)" % str(down_seen))
	var up_seen := []
	for i in 3:
		await _joy(JOY_BUTTON_DPAD_UP)
		for m in order:
			if (hud._thousand_time_btns[m] as Control).get_global_rect().has_point(pad.cursor):
				up_seen.append(m)
	check(up_seen == ["night", "dusk", "day"], "and up walks it back the same way (%s)" % str(up_seen))
	var ts: Array = pad.targets()
	var unreachable := []
	for t: Control in ts:
		var from: Vector2 = (hud._thousand_time_btns["day"] as Control).get_global_rect().get_center()
		if t != hud._thousand_time_btns["day"] and _dpad_path(from, t).is_empty():
			unreachable.append((t as Button).text if t is Button and (t as Button).text != "" else str(t.name))
	check(unreachable.is_empty(), "every Thousand Town button can be reached with the D-pad (%d buttons; unreachable %s)" % [ts.size(), str(unreachable)])


## The clock line, the time button (- / Select) through Day, Dusk, Night and back to Auto, and A on Auto.
func _time() -> void:
	var clock: Label = hud._thousand_clock
	check(clock != null and clock.is_visible_in_tree() and clock.text.contains(":") and clock.text.contains(tr("Auto: time runs by itself (%s)").get_slice("(", 0).strip_edges()),
		"the clock line says the time and that Auto runs it (%s)" % (clock.text if clock else ""))
	var seen := []
	for i in 4:
		await _joy(JOY_BUTTON_BACK)
		await until(func(): return _mode() != (seen.back() if not seen.is_empty() else "auto"), 3.0)
		await frames(3)
		seen.append(_mode())
		if _mode() == "night":
			await wait(0.6)
			var l: Dictionary = main.world.thousand_world.light
			check(float(l.get("daylight", 1.0)) < 0.05 and clock.text.begins_with("21:30") and clock.text.contains(tr("Night")),
				"Night held: dark, 21:30, and the line says it stays (%s)" % clock.text)
			await _shot("night_held")
	check(seen == ["day", "dusk", "night", "auto"], "the time button steps Day, Dusk, Night and back to Auto (%s)" % str(seen))
	var t0: Dictionary = main.world.thousand_world.view_time()
	await wait(2.5)
	var t1: Dictionary = main.world.thousand_world.view_time()
	check(_mode() == "auto" and float(t1.get("minute", 0)) > float(t0.get("minute", 0)) + 1.0, "Auto: the clock runs again (%.1f -> %.1f)" % [float(t0.get("minute", 0)), float(t1.get("minute", 0))])
	# a held time, then A on the Auto glass button
	await _joy(JOY_BUTTON_BACK)
	await until(func(): return _mode() == "day", 3.0)
	await press_button(hud._thousand_time_btns["auto"], "Auto")
	check(await until(func(): return _mode() == "auto", 3.0), "A on the Auto button returns to Auto from a held time")
	await _shot("auto")


## The ferris wheel: walk there with the stick, ride it with Y, look around with the right stick, zoom with ZL / ZR.
func _wheel() -> void:
	var tp: Node = c.thousand_play
	# by day, so the park is open (Day through the time button)
	await _joy(JOY_BUTTON_BACK)
	await until(func(): return _mode() == "day", 3.0)
	var bp: Vector2 = tp.wheel_board_point()
	# the way a player finds it: around the walls and over a footbridge, planned on the child's own walkability
	# (ThousandNav, with a margin), then walked leg by leg with the left stick. (The residents' pavement routes pass
	# where the child cannot walk; a known open item.)
	var pts := _plan(c.pos, bp)
	print("DIAG plan from %s to %s: %d legs %s" % [c.pos, bp, pts.size(), str(pts)])
	check(not pts.is_empty(), "a walking way to the ferris wheel (%d legs)" % pts.size())
	for p in pts:
		if not await _stick_to(p, 0.7):
			print("DIAG leg to %s stopped at %s" % [p, c.pos])
	check(await _stick_to(bp, 0.5), "the stick walks the child to the wheel (%s, %.1f m)" % [c.pos, c.pos.distance_to(bp)])
	check(await until(func(): return c._ctx.get("type", "") == "tt_wheel", 3.0), "the action button offers the wheel (%s)" % hud._context_btn.text)
	var hints_seen := []
	c.hint.connect(func(t): hints_seen.append(str(t)))
	# Noon (Day, held): the park's opening follows the visitors' plans (thousand_play.next_open), so the venue's
	# own state decides; assert what it says rather than assuming noon is open.
	var row_noon: Dictionary = tp.site_row("c-amusement")
	var open_noon := bool(row_noon.get("open", false))
	print("DIAG noon: venue %s at %s" % [str(row_noon), str(main.world.thousand_world.view_time())])
	await _joy(JOY_BUTTON_Y)   # the context button's role on every layout
	await frames(4)
	if open_noon:
		check(tp.state in ["wheel_wait", "wheel"], "at noon the park is open (its state says so) and Y starts the ride (%s)" % tp.state)
		await _joy(pad.back_button())   # wait for dusk instead, as the approved capture boards
		await until(func(): return tp.state == "", 3.0)
	else:
		check(tp.state == "" and hints_seen.any(func(t): return t.contains(tr("The amusement park is closed").get_slice(".", 0))),
			"at noon the park is closed (its state says so) and Y says when it opens (%s)" % str(hints_seen))
	# Dusk (18:40) with the time button, as the approved capture boards at dusk
	await _joy(JOY_BUTTON_BACK)
	check(await until(func(): return _mode() == "dusk", 3.0), "the time button holds Dusk (%s)" % _mode())
	await wait(0.8)
	var row_dusk: Dictionary = tp.site_row("c-amusement")
	print("DIAG dusk: venue %s at %s" % [str(row_dusk), str(main.world.thousand_world.view_time())])
	check(bool(row_dusk.get("open", false)), "at dusk the park is open (its state: %s)" % str(row_dusk.get("open", null)))
	await until(func(): return c._ctx.get("type", "") == "tt_wheel", 3.0)
	hints_seen.clear()
	await _joy(JOY_BUTTON_Y)
	check(await until(func(): return tp.state == "wheel", 60.0), "Y rides the wheel; a cabin takes the child (%s)" % tp.state)
	if tp.state != "wheel":
		return
	await until(func(): return not main.rig.thousand_gliding(), 4.0)
	await frames(4)
	print("HINTS on the wheel: ", hint_text())
	check(pad.hint_parts().any(func(p): return str(p[1]) == "Look around"), "the hints say the right stick looks around (%s)" % hint_text())
	var yaw0: float = main.rig.t_yaw
	var dist0: float = main.rig.t_dist
	var fwd0: Vector3 = -main.rig.camera.global_basis.z
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await wait(0.6)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 1.0)
	await wait(0.4)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await frames(3)
	var fwd1: Vector3 = -main.rig.camera.global_basis.z
	check(fwd0.angle_to(fwd1) > 0.3 and absf(main.rig.t_watch_yaw) > 0.3, "the right stick turns the cabin's view (%.2f rad)" % fwd0.angle_to(fwd1))
	check(is_equal_approx(main.rig.t_yaw, yaw0), "and not the hidden follow camera behind it")
	var fov0: float = main.rig.camera.fov
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(3)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(3)
	check(absf(main.rig.camera.fov - fov0) > 1.0 and is_equal_approx(main.rig.t_dist, dist0), "ZR zooms the cabin's view (fov %.1f -> %.1f), not the follow distance" % [fov0, main.rig.camera.fov])
	await _shot("wheel_look")
	check(await until(func(): return tp.can_get_off_wheel() or tp.state != "wheel", 120.0), "the cabin comes back down")
	if tp.state == "wheel":
		await _joy(JOY_BUTTON_Y)
	check(await until(func(): return tp.state == "" and main.rig.t_watch == null, 4.0), "off the wheel at the bottom")
	await until(func(): return not main.rig.thousand_gliding(), 4.0)
	await frames(3)
	check(main.rig.camera.global_position.distance_to(main.world.local_kid().global_position) < main.rig.T_MAX + 3.0 and main.world.local_kid().visible,
		"the follow camera is behind the child again (%.1f m)" % main.rig.camera.global_position.distance_to(main.world.local_kid().global_position))
	check(is_zero_approx(main.rig.t_watch_yaw) and is_zero_approx(main.rig.t_watch_pitch) and is_equal_approx(main.rig.camera.fov, main.rig.FOV),
		"the cabin's adjustments end with the ride (fov %.1f)" % main.rig.camera.fov)


func _home() -> void:
	await press_button(hud._ride_home, "Ride home")
	check(await until(func(): return c.space == "town" and c.journey_to == "", 20.0), "Ride home returns to the town")
	await until(func(): return hud._journey_card == null or not hud._journey_card.visible, 4.0)
	check(not main.rig.on_thousand and not hud._thousand_time.visible and not hud._thousand_clock.visible and hud._decorate_btn.is_visible_in_tree(),
		"the town's camera and HUD again (no time buttons, no clock line)")
	await _shot("home")
