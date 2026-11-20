## Ride home straight from each of the Roller Coaster Workshop's six platforms (unified r4, physical Apple TV feedback),
## end to end through the real game. One solo session; for each of the six lines in turn: from the town's tram stop the
## Workshop opens, the child boards that line from its quick boarding card, rides the whole lap, gets off at the
## platform and rides home directly from there (no walk back to the central tram), and the town comes back exactly as
## it was: the town's world, controller, camera rig, controller layer and Siri Remote layer running and shown again, the
## rig's camera current, the child standing where it left at the stop, the stop's entries and the HUD as at the start,
## and nothing stale (no held stick, no pending walk or ride, no queued controller action; the child stays put).
## Also checked: no Ride home while the train runs or while it stands at the platform with the child still aboard, and
## a second press during the shuttle's journey does nothing (one return, no double trigger).
## Touch by default, fingers and mouse only: a tap on the stop's Workshop button, on the card, on Get off and on the
## platform's Ride home button (beside Board train); before one Ride home a tap on the walkway starts a walk that the
## ride must drop. --tv: the controller only (every event made by Input.parse_input_event and tagged synthetic; no
## handler is called directly): + (Start) at the stop, the D-pad to the card and the confirm button to board and to get
## off, then the back button (even lines) or + (odd lines) as the platform's hint offers; before one Ride home the left
## stick is held and still held when the town is back. Ride timing is the Workshop's own (laps of 26 to 65 s).
##   Headless: scripts/godot.sh --headless --fixed-fps 30 --path game -- --driver=res://tests/coaster_home_tour.gd \
##                 --no-shots --window=1366x1024 --tag=ipad
##             ... --tv --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv
## Ends with "COASTER HOME TOUR <tag>: N checks, F failures" and exits 1 on any failure.
extends "res://tests/station_tour.gd"

var _stale_walks := 0


func _run() -> void:
	tv = main.args.has("tv")
	c = main.controller
	hud = main.hud
	for f in ["user://coaster-home-tour.json", "user://coaster-home-tour.json.bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo("user://coaster-home-tour.json", main.menus.avatar)
	await wait(1)
	await settle_camera()
	board = TownModel.tram_stop_boarding(Session.model)
	if tv:
		await walk_to(board)
	else:
		await _tap_open_ground(board)
	await _still()
	await until(func(): return c._ctx.get("type", "") == "tram" and hud._workshop_btn.is_visible_in_tree(), 8)
	await frames(4)
	check(hud._workshop_btn.is_visible_in_tree(), "the Workshop is offered at the town's tram stop")
	_start_buttons = hud_buttons()
	for i in 6:
		if not await _line_home(i):
			break
	if not tv:
		check(_stale_walks > 0, "a walk started on a platform was dropped by Ride home (%d lines)" % _stale_walks)
	_done()


## One line: open the Workshop, board line i, ride its lap, get off, ride home from its platform, check the town.
func _line_home(i: int) -> bool:
	await _still()
	var before: Vector2 = c.pos
	if tv:
		await _joy(JOY_BUTTON_START)   # Workshop r4: + (Start) takes the Workshop tram from the stop
		await frames(6)
	else:
		await _touch_button(hud._workshop_btn)
	park = null
	for node in main.get_children():
		if node is Park:
			park = node
	check(park != null, "line %d: the Workshop opens from the stop" % i)
	if park == null:
		return false
	_stand = c.pos
	check(_stand.distance_to(before) < 0.3 and c.process_mode == Node.PROCESS_MODE_DISABLED and not main.world.visible and not hud.visible,
		"line %d: the town is paused and put away, the child kept where it stood" % i)
	await until(func(): return park.journey <= 0.0, 4.0)
	await frames(3)
	var line = park.lines[i]
	check(park.shortcuts.visible and park.cam.current, "line %d: the boarding cards at the arrival" % i)
	# board line i from its card
	if tv:
		if i >= 3:
			await _joy(JOY_BUTTON_DPAD_DOWN)
		for k in i % 3:
			await _joy(JOY_BUTTON_DPAD_RIGHT)
		check(park.selected == i, "line %d: the D-pad selects %s" % [i, line.title])
		await _joy(main.pad.confirm_button())
	else:
		await _touch_button(park.cards[i])
	check(line.moving and park.active == line and park.kid.get_parent() == line.cars[0], "line %d: the child boards %s" % [i, line.title])
	if not line.moving:
		return false
	if i == 0:
		# no Ride home while the train runs
		await wait(1.0)
		if tv:
			await _joy(main.pad.back_button())
			await _joy(JOY_BUTTON_START)
		else:
			check(not park.home_action.is_visible_in_tree(), "no Ride home button while riding")
		check(is_instance_valid(park) and park.active == line and line.moving and not park.riding_home and park.journey <= 0.0,
			"line 0: nothing rides home while the train runs")
	var t := 0.0
	while line.moving and t < 150.0:
		await wait(0.25)
		t += 0.25
	check(not line.moving and is_equal_approx(line.distance, line.stop), "line %d: the lap ends at the platform (%.0f s)" % [i, t])
	if line.moving:
		return false
	await frames(2)
	if i == 0:
		# docked with the child still aboard: back and + do not take it home
		if tv:
			await _joy(main.pad.back_button())
			await _joy(JOY_BUTTON_START)
		else:
			check(not park.home_action.is_visible_in_tree(), "no Ride home button while still aboard")
		check(is_instance_valid(park) and park.active == line and not park.riding_home, "line 0: still aboard at the platform until Get off")
	# get off
	if tv:
		await _joy(main.pad.confirm_button())
	else:
		await _touch_button(park.action)
	check(not park.active and park.kid.get_parent() == park and park.nearby() == line and park.kid.position.distance_to(line.board) < 1.0,
		"line %d: off the train onto %s's platform" % [i, line.title])
	await frames(3)
	# ride home from the platform
	if tv:
		var want := "%s / %s  %s" % [main.pad.label_of(main.pad.back_button()), main.pad.label_of(JOY_BUTTON_START), tr("Ride home")]
		check(park.hint_panel.visible and park.hint.text.contains(want), "line %d: the hint offers %s (%s)" % [i, want, park.hint.text])
		if i == 1:
			_axis(JOY_AXIS_LEFT_X, 1.0)   # held: the child walks; it is still held when the town is back
			await wait(0.15)
		await _joy(main.pad.back_button() if i % 2 == 0 else JOY_BUTTON_START)
	else:
		check(park.home_action.is_visible_in_tree() and park.home_action.text == tr("Ride home") and park.action.is_visible_in_tree()
			and park.action.text == tr("Board train") and not park.home_action.get_global_rect().intersects(park.action.get_global_rect()),
			"line %d: the platform offers Ride home beside Board train" % i)
		if await _walk_tap(line):
			_stale_walks += 1
		await _touch_button(park.home_action)
	check(is_instance_valid(park) and park.riding_home and park.journey > 0.0 and park.kid.get_parent() == park.shuttle,
		"line %d: Ride home seats the child in the shuttle at the platform" % i)
	if i == 0 and is_instance_valid(park):
		var j0: float = park.journey
		if tv:
			await _joy(main.pad.back_button())
		else:
			await tap(park.home_action.get_global_rect().get_center())   # where the button was: it is gone now
		check(is_instance_valid(park) and park.riding_home and park.journey < j0, "line 0: a second press during the journey does nothing")
	await until(func(): return not is_instance_valid(park), 6.0)
	check(not is_instance_valid(park), "line %d: the shuttle takes the child home from the platform" % i)
	await _town_restored("line %d" % i)
	if tv and i == 1:
		await wait(0.5)
		check(c.pos.distance_to(_stand) < 0.05 and c.pad_move == Vector2.ZERO,
			"line 1: the stick still held from the Workshop does not walk the child in town (%.2f m)" % c.pos.distance_to(_stand))
		_axis(JOY_AXIS_LEFT_X, 0.0)
		await frames(3)
	return true


## A finger tap on the walkway two metres toward the centre from the platform (if a finger can reach it there: on
## screen and not under a card or button), so a walk is under way when Ride home is tapped. True if it was tapped.
func _walk_tap(line) -> bool:
	var inward: Vector3 = (park.exit_point - line.board)
	inward.y = 0.0
	var spot: Vector3 = park.kid.global_position + inward.normalized() * 2.0
	var aim: Vector2 = park.cam.unproject_position(spot)
	if park.cam.is_position_behind(spot) or not get_viewport().get_visible_rect().grow(-20).has_point(aim):
		return false
	for ctl in park.panel.find_children("*", "Control", true, false):
		var cc := ctl as Control
		if cc.mouse_filter != Control.MOUSE_FILTER_IGNORE and cc.is_visible_in_tree() and cc.get_global_rect().grow(8).has_point(aim):
			return false
	await tap(aim)
	await frames(2)
	var walking: bool = park.goal.distance_to(park.kid.position) > 0.5
	check(walking, "a tap on the walkway starts a walk (%s)" % line.title)
	return walking


## The town exactly as it was when the child left for the Workshop, with nothing left over from it.
func _town_restored(after: String) -> void:
	await at_stop(after)
	check(main.world.process_mode == Node.PROCESS_MODE_INHERIT and c.process_mode == Node.PROCESS_MODE_INHERIT
		and main.rig.process_mode == Node.PROCESS_MODE_INHERIT and main.pad.process_mode == Node.PROCESS_MODE_INHERIT,
		"%s: the town's world, controller, camera rig and controller layer run again" % after)
	if main.tv_remote:
		check(main.tv_remote.process_mode != Node.PROCESS_MODE_DISABLED, "%s: the Siri Remote's Menu works again" % after)
	check(main.pad.visible and hud.visible and main.world.visible and main.rig.camera.current and get_viewport().get_camera_3d() == main.rig.camera,
		"%s: the town's view, HUD and controller layer are shown, the rig's camera in use" % after)
	var parks := main.get_children().filter(func(n): return n is Park)
	check(parks.is_empty(), "%s: no Workshop is left behind" % after)
	check(c.pad_move == Vector2.ZERO and c._walk_target == null and c._pending_ctx.is_empty() and c.journey_to == ""
		and (main.pad._axes as Dictionary).values().all(func(v): return absf(float(v)) < 0.2) and (main.pad._queue as Array).is_empty(),
		"%s: nothing stale: no stick, walk, pending ride or queued controller action" % after)
	await wait(0.6)
	check(c.pos.distance_to(_stand) < 0.05 and c.journey_to == "" and c.space == "town",
		"%s: the child stays at the stop (%.3f m)" % [after, c.pos.distance_to(_stand)])
	await frames(2)
	var now := hud_buttons()
	check(now == _start_buttons, "%s: the town HUD at the stop is exactly as at the start (%d buttons)" % [after, now.size()])
	if now != _start_buttons:
		print("  start: ", _start_buttons, "\n  now:   ", now)


func _done() -> void:
	print("COASTER HOME TOUR %s: %d checks, %d failures" % [tag, _checks, failures])
	Music.quit_game(1 if failures else 0)
