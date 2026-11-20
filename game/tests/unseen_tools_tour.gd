## The placement tools take no press while they take their place unseen (first-steps r9, review D10).
## For 3 frames after a thing is picked the tools are laid out unseen (hud.gd, _pick_frames). In r8 they
## still took presses then: EC2 run 3 of furn_tour.gd pressed Turn in those frames, hit another button and
## put the thing away. A press that lands on a tool while it cannot be seen must do nothing, neither
## then nor when the finger lifts after the tools have appeared; once they are shown they work as before.
##
## Probes, each right after a pick from the toy box's place (the dock at the bottom edge), aimed at the
## centre of a tool button as laid out in that frame:
##   a finger: press while unseen, lift one frame later (Turn; Cancel, which would end the hold);
##   on a controller (--tv): the controller layer's pointer and A, pad_input.tap_at (Turn; Cancel);
##   on a controller: its Turn button (X on a Nintendo layout), pad_input._run("turn"), which presses the
##     real Turn button through the GUI and presses it again a few frames later if it did not answer: no
##     turn while the tools are unseen, exactly one once they are shown.
## A probe counts only when its press reached the game while the tools were unseen (recorded on arrival,
## before the GUI saw it) at a point inside the aimed button: otherwise it is a set-up failure.
## The controller probes call the controller layer directly in the first unseen frame: a real controller
## button takes one more frame to become a press, and by then the tools are shown.
## Then the visible tools: Turn turns the thing, Cancel puts it back, Place here places a new thing
## (a finger; on a controller also the pointer and A, X and +). A new thing has no Put away button.
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/unseen_tools_tour.gd \
##                   --tag=iphone --safe-insets=154,0,154,55 --no-shots
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/unseen_tools_tour.gd \
##                   --tv --pad-layout=nintendo --tag=atv --no-shots
## Logic only (EC2): add --headless before --path, and --window=WxH after --. No pictures: nothing to see.
## Its town is its own save (user://unseen_tools_tour_town.json), deleted at the start of every run.
extends "res://tests/puzzle_ride_tour.gd"

const UNSEEN_TOWN := "user://unseen_tools_tour_town.json"
const KIND := "lamp_post"

var _arm := false          # record the next press that arrives
var _arrived := {}         # what the game looked like when the probe's press arrived


func _input(event: InputEvent) -> void:
	super._input(event)   # the outside-pointer guard stays on
	if _arm and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_arm = false
		var hud: Control = main.hud
		var at: Vector2 = (event as InputEventMouseButton).position   # already in the HUD's own coordinates here
		var on := ""
		for b in hud._tools_row.get_children():
			if b is Button and b.is_visible_in_tree() and b.get_global_rect().has_point(at):
				on = b.text
		_arrived = {"pick_frames": hud._pick_frames, "alpha": hud._tools_box.modulate.a, "at": at, "on": on, "frame": Engine.get_process_frames()}


func state() -> Array:
	var c: Node = main.controller
	var hud: Control = main.hud
	var g: Vector3 = c.ghost.global_position if c.ghost != null else Vector3.INF
	return [c.ghost != null, c.g_kind, c.g_rot, g.snapped(Vector3.ONE * 0.001), c.g_color, hud._swatches.visible, hud._overlay.get_child_count(), Session.model.items.size()]


func tool(label: String) -> Button:
	for b in main.hud._tools_row.get_children():
		if b is Button and b.text == label:
			return b
	return null


## Picks a new thing from the toy box's place; returns once the first unseen frame is laid out.
func pick() -> bool:
	var hud: Control = main.hud
	var c: Node = main.controller
	await tools_back_to_bottom()
	check(hud.dock == "bottom" and c.ghost == null, "set up: nothing held and the toy box at the bottom edge (place \"%s\")" % hud.dock)
	c.begin_new(KIND)
	check(c.ghost != null and hud._pick_frames == 3 and hud._tools_box.modulate.a < 0.01, "set up: a %s is picked and the tools take their place unseen (frames %d, alpha %.2f)" % [KIND, hud._pick_frames, hud._tools_box.modulate.a])
	await get_tree().process_frame
	return hud._pick_frames > 0


func tools_back_to_bottom() -> void:
	var c: Node = main.controller
	if c.ghost != null:
		c.cancel_ghost()
		await until(func(): return c.ghost == null, 3.0)
	await frames(8)


func probe(how: String, label: String) -> void:
	var hud: Control = main.hud
	var w := "%s on the unseen %s" % [how, label]
	if not await pick():
		check(false, "%s: set up: the tools are still unseen one frame after the pick (frames %d)" % [w, hud._pick_frames])
		return
	var b := tool(label)
	check(b != null and b.is_visible_in_tree() and b.get_global_rect().has_area(), "%s: set up: the button is laid out (%s)" % [w, b.get_global_rect() if b else "none"])
	if b == null:
		return
	var aim: Vector2 = b.get_global_rect().get_center()
	var before := state()
	_arrived = {}
	_arm = true
	if how == "a finger":
		var screen: Vector2 = get_viewport().get_final_transform() * aim
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			e.position = screen
			e.global_position = screen
			e.set_meta("tour", true)
			Input.parse_input_event(e)
			await get_tree().process_frame
	else:
		pad.tap_at(aim)   # the controller layer's pointer and A: press now, lift on the next frame
	await frames(12)
	await tools_settled()
	_arm = false
	check(not _arrived.is_empty() and int(_arrived["pick_frames"]) > 0 and float(_arrived["alpha"]) < 0.01 and _arrived["on"] == label, "%s: set up: the press arrived while the tools were unseen, on the %s button (%s)" % [w, label, str(_arrived)])
	var after := state()
	check(after == before, "%s: the press does nothing, neither while the tools are unseen nor when it lifts after they are shown (before %s, after %s)" % [w, str(before), str(after)])
	check(hud._tools_box.modulate.a > 0.99 and hud._pick_frames == 0, "%s: then the tools are shown" % w)


## The controller's own Turn button pressed while the tools are unseen: no turn until they are shown, then exactly one.
func probe_pad_turn() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	var w := "the controller's Turn button while the tools are unseen"
	if not await pick():
		check(false, "%s: set up: the tools are still unseen one frame after the pick" % w)
		return
	var rot0: int = c.g_rot
	var before := state()
	_arrived = {}
	_arm = true
	pad._run("turn")
	var turned_unseen := false
	for i in 6:
		await get_tree().process_frame
		if hud._pick_frames > 0 and c.g_rot != rot0:
			turned_unseen = true
	await frames(12)
	await tools_settled()
	check(not _arrived.is_empty() and int(_arrived["pick_frames"]) > 0 and _arrived["on"] == "Turn", "%s: set up: its press arrived while the tools were unseen, on Turn (%s)" % [w, str(_arrived)])
	check(not turned_unseen, "%s: the thing does not turn while the tools are unseen" % w)
	var after := state()
	before[2] = (rot0 + 1) % 8
	check(posmod(c.g_rot - rot0, 8) == 1 and after == before, "%s: once they are shown it turns exactly one step and nothing else changes (before %s, after %s)" % [w, str(before), str(after)])


## The tools once shown work as before.
func visible_tools() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	await pick()
	await frames(6)
	await tools_settled()
	check(hud._tools_box.modulate.a > 0.99 and hud._pick_frames == 0, "visible tools: set up: the tools are shown")
	var rot0: int = c.g_rot
	await press(tool("Turn"))
	await frames(4)
	check(posmod(c.g_rot - rot0, 8) == 1, "visible tools: a finger on Turn turns the thing one step (%d to %d)" % [rot0, c.g_rot])
	if tv:
		rot0 = c.g_rot
		await choose(tool("Turn"), "Turn")
		await frames(6)
		check(posmod(c.g_rot - rot0, 8) == 1, "visible tools: the controller's pointer and A on Turn turn the thing one step (%d to %d)" % [rot0, c.g_rot])
		rot0 = c.g_rot
		await btn(JOY_BUTTON_X)
		await frames(8)
		check(posmod(c.g_rot - rot0, 8) == 1, "visible tools: the controller's Turn button turns the thing one step (%d to %d)" % [rot0, c.g_rot])
	await press(tool("Cancel"))
	check(await until(func(): return c.ghost == null, 3.0), "visible tools: a finger on Cancel puts the new thing back")
	var n0: int = Session.model.items.size()
	await pick()
	await frames(6)
	await tools_settled()
	for off in [Vector2(2.5, 0), Vector2(-2.5, 0), Vector2(0, 2.5), Vector2(0, -2.5), Vector2(3.5, 3.5), Vector2(-3.5, -3.5)]:
		c._move_ghost_to(c.pos + off)
		await frames(4)
		if c.g_error == "":
			break
	await tools_settled()
	check(c.g_error == "", "visible tools: set up: the new thing can be placed here (\"%s\")" % c.g_error)
	if tv:
		await btn(JOY_BUTTON_START)
		check(await until(func(): return c.ghost == null and Session.model.items.size() == n0 + 1, 4.0), "visible tools: the controller's + places the new thing (%d to %d things)" % [n0, Session.model.items.size()])
	else:
		await press(tool("Place here"))
		check(await until(func(): return c.ghost == null and Session.model.items.size() == n0 + 1, 4.0), "visible tools: a finger on Place here places the new thing (%d to %d things)" % [n0, Session.model.items.size()])


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "300"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "300"))
		print("UNSEEN_TOOLS %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("UNSEEN_TOOLS start tag=%s input=%s engine=%s" % [tag, "controller" if tv else "touch", Engine.get_version_info()["string"]])
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	for f in [UNSEEN_TOWN, UNSEEN_TOWN + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(UNSEEN_TOWN, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	I18n.set_locale("en")
	await frames(3)
	Activities._wish_wait = -1.0e6   # no animal wish rebuilding the toy box during the tour (as puzzle_ride_tour)
	park_animals()
	await settle_camera()
	if c.mode != "decorate":
		await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 3.0), "set up: the Decorate button opens Decorate")
	await wait(1.0)
	for label in ["Turn", "Cancel"]:
		await probe("a finger", label)
		if tv:
			await probe("the controller's pointer and A", label)
	if tv:
		await probe_pad_turn()
	await tools_back_to_bottom()
	await visible_tools()
	check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the %s tour (%d; first: %s)" % ["controller" if tv else "touch", _real_mouse, _real_mouse_first])
	print("UNSEEN_TOOLS %s %s: %d failures" % [tag, "PASS" if failures == 0 else "FAIL", failures])
	Music.quit_game(1 if failures else 0)
