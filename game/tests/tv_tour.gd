## TV controller tour (atv-r20-controller, design/tv-controller.md). Every step goes through simulated game
## controller events only (Input.parse_input_event of joypad buttons and sticks): no taps, no mouse. It runs
## on the Apple TV itself (devicectl with driver arguments) as well as headless.
##   phase main (default): launch menus, the TV join screen (no text entry, no address shown), solo play,
##     walking with the deadzone, the camera, a dialog that holds the world still, the context action, the
##     game's camera and the scrapbook, Decorate (pick, move, turn, place, cancel), B safety on an
##     unfamiliar and a confirmation dialog, Swap A and B, six languages, disconnect and reconnect, and a
##     storage write (settings, a town save, a photo) with immediate read-back.
##   --phase=reopen: a fresh launch reads the storage back (the same bytes), then removes the tour's data.
##   --phase=menus_back (with --pad-trace): the Mac r2 GPU failure path, five times over: title, Play with
##     friends, Let's go!, the friends screen, B, the character screen, B, the title, each B pressed as soon
##     as the new screen exists. Bounded (about 30 s); every action, tap and release is traced.
##   --phase=defaults, then --phase=defaults_restart after relaunching: the native LanternDefaults module on
##     the TV (put/get, the exact whole-store budget, a corrupt copy, recovery after the staging file is
##     deleted or invalid, the copies after a restart) with synthetic files under user://tv_smoke/ and only
##     lantern.test.* names, all removed at the end.
## The tour plays in its own town (user://tv_tour_town.json), never the child's town. It writes a small
## result, user://tv_tour_result.json, and screenshots to --shots (for example user://tv_shots). It never
## prints or stores the town address, invite, avatar or save contents: only names, counts and hashes.
##   Device: --driver=res://tests/tv_tour.gd --tv --shots=user://tv_shots --tag=atv [--phase=reopen]
##   Headless: scripts/godot.sh --headless --path game -- --driver=res://tests/tv_tour.gd --tv \
##       --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv
extends "res://tests/pets_tour.gd"

const PhotoStore := preload("res://scripts/core/photo_store.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const PadInput := preload("res://scripts/ui/pad_input.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const TOUR_SAVE := "user://tv_tour_town.json"
const STORE := "user://tv_tour_storage.json"
const RESULT := "user://tv_tour_result.json"
const SETTINGS := "user://settings.cfg"
const DEV := 0
const MAX_SHOTS := 14
const CASES := {"main": ["launch and menus", "TV join screen", "solo start", "walk", "camera", "dialog holds the world", "context action",
	"camera photo and scrapbook", "decorate", "B safety", "swap A and B", "languages", "disconnect", "siri remote menu", "storage write"],
	"reopen": ["storage reopen"], "back": ["menus back"], "defaults": ["defaults smoke"], "defaults_restart": ["defaults restart"], "menus_back": ["menus back loop"], "cleanup_photo": ["cleanup photo"]}

var pad: Node
var _phase := "main"
var _checks := 0
var _done := []
var _shot_names := []
var _finished := false
var _fake_defaults: RefCounted = null   # held while registered (dry run only)
var _photos_before := []   # the game's photos before this tour ran (never touched)
var _photos_recorded := false   # cleanup only ever runs once that list was taken
const ARTIFACTS := "user://tv_tour_artifacts.json"


func check(cond: bool, what: String) -> void:
	_checks += 1
	super.check(cond, what)


func shot(name: String) -> void:
	if _n >= MAX_SHOTS or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	var file := "tv_%s_%02d_%s.png" % [tag, _n, name]
	var err := get_viewport().get_texture().get_image().save_png("%s/%s" % [shots, file])
	check(err == OK, "screenshot %s saved (%d)" % [file, err])
	_shot_names.append(file)


func case_done(name: String) -> void:
	_done.append(name)
	print("CASE %s done" % name)


# ------------------------------------------------------------- controller

## The button printed with this letter on the controller in use (Nintendo: A is on the right).
func phys(label: String) -> int:
	var nin: bool = pad.layout == "nintendo"
	match label:
		"A": return JOY_BUTTON_B if nin else JOY_BUTTON_A
		"B": return JOY_BUTTON_A if nin else JOY_BUTTON_B
		"X": return JOY_BUTTON_Y if nin else JOY_BUTTON_X
		"Y": return JOY_BUTTON_X if nin else JOY_BUTTON_Y
	return -1


func joy_button(b: int, pressed: bool) -> void:
	if _finished:
		return   # after the result is written (a time-out) the tour acts no more
	var e := InputEventJoypadButton.new()
	e.device = DEV
	e.button_index = b
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func btn(b: int) -> void:
	joy_button(b, true)
	await frames(2)
	joy_button(b, false)
	await frames(3)


func axis(a: int, v: float) -> void:
	if _finished:
		return
	var e := InputEventJoypadMotion.new()
	e.device = DEV
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func stick(left: bool, v: Vector2, sec: float) -> void:
	var ax := JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X
	var ay := JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y
	axis(ax, v.x)
	axis(ay, v.y)
	await wait(sec)
	axis(ax, 0.0)
	axis(ay, 0.0)
	await frames(2)


## Steers the pointer with the right stick until it is inside `r` (bounded).
func steer(r: Rect2) -> void:
	for i in 90:
		if r.has_point(pad.cursor):
			break
		var d: Vector2 = r.get_center() - pad.cursor
		var v := d.normalized() * clampf(d.length() / 260.0, 0.4, 1.0)
		axis(JOY_AXIS_RIGHT_X, v.x)
		axis(JOY_AXIS_RIGHT_Y, v.y)
		await frames(1)
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_RIGHT_Y, 0.0)
	await frames(2)


## Brings the pointer onto a control like a child would: the D-pad first, the right stick when the D-pad
## lands elsewhere. Returns true when the pointer is on it.
func go_to(target: Control) -> bool:
	if target == null or not target.is_visible_in_tree():
		return false
	for i in 12:
		var r := target.get_global_rect()
		if r.has_point(pad.cursor):
			return true
		var d: Vector2 = r.get_center() - pad.cursor
		var b: int
		if absf(d.x) > absf(d.y):
			b = JOY_BUTTON_DPAD_RIGHT if d.x > 0 else JOY_BUTTON_DPAD_LEFT
		else:
			b = JOY_BUTTON_DPAD_DOWN if d.y > 0 else JOY_BUTTON_DPAD_UP
		var before: float = pad.cursor.distance_to(r.get_center())
		await btn(b)
		await frames(2)
		if pad.cursor.distance_to(target.get_global_rect().get_center()) >= before - 1.0:
			break   # the D-pad chose another button: steer instead
	await steer(target.get_global_rect())
	return target.get_global_rect().has_point(pad.cursor)


## Points at a control and presses the controller's confirm button (A).
func choose(target: Control, what: String) -> void:
	var ok := await go_to(target)
	check(ok, "the pointer reaches %s" % what)
	if ok:
		check(_area().encloses(target.get_global_rect()), "%s is inside the TV safe area" % what)
		await btn(phys("A"))
		await frames(4)


func button_text(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and (b.text == text or b.tooltip_text == text or b.get_meta("dialog_button", "") == text):
			return b
	return null


func _area() -> Rect2:
	return pad._area()


func modal_open() -> bool:
	return pad.is_modal()


func hints_ok(what: String) -> void:
	await wait(0.5)   # the place is chosen again five times a second: two rounds after the screen settled
	var r: Rect2 = pad.hint_rect()
	check(pad._hint_panel.visible and _area().encloses(r), "%s: the controller hints show inside the safe area (%s)" % [what, r])
	var over: Array = pad.targets().filter(func(t): return t.get_global_rect().intersects(r))
	check(over.is_empty(), "%s: the hints cover no button (%s)" % [what, over.map(func(t): return str(t.name))])
	if not over.is_empty():
		print("DIAG %s: area %s, hints %s, %d buttons, %d texts, catalog %s, tools %s" % [what, _area(), r, pad.targets().size(), _texts_on_screen().size(),
			main.hud._catalog.get_global_rect() if main.hud._catalog.visible else "hidden", main.hud._tools.get_global_rect() if main.hud._tools.visible else "hidden"])
	var covered: Array = _texts_on_screen().filter(func(l): return _text_rect(l).intersects(r))
	check(covered.is_empty(), "%s: the hints cover no readable text (%s)" % [what, covered.map(func(l): return str(l.text).left(40))])


## Readable text on screen, found independently of pad_input.gd: visible, non-empty labels of the open dialog
## or menu (else the HUD, not the world's name tags), not faded out.
func _texts_on_screen() -> Array:
	var root: Node = main.menus if main.menus.visible else (main.hud._overlay if modal_open() else main.hud)
	var out := []
	for n in root.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text.strip_edges() == "" or main.hud._tag_layer.is_ancestor_of(l):
			continue
		if not modal_open() and main.hud._overlay.is_ancestor_of(l):
			continue
		var a := 1.0
		var c: Node = l
		while c is CanvasItem:
			a *= (c as CanvasItem).modulate.a
			c = c.get_parent()
		if a >= 0.05 and _text_rect(l).has_area():
			out.append(l)
	return out


func _text_rect(l: Control) -> Rect2:
	var r := l.get_global_rect()
	var p := l.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	return r.intersection((p as ScrollContainer).get_global_rect()) if p else r


# ------------------------------------------------------------- run

func _run() -> void:
	pad = main.pad
	if main.args.has("fake-defaults") and not Engine.has_singleton("LanternDefaults"):
		# EC2 dry run only: the stand-in (tests/fake_defaults.gd), kept in a file across the relaunch.
		_fake_defaults = load("res://tests/fake_defaults.gd").new("user://fake_defaults.bin")
		Engine.register_singleton("LanternDefaults", _fake_defaults)
		print("DIAG dry run: a stand-in LanternDefaults (not the native module)")
	_phase = main.args.get("phase", "main")
	get_tree().create_timer(float(main.args.get("timeout", "420"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "420"))
		_finish())
	print("TVTOUR start phase=%s os=%s tv=%s engine=%s renderer=%s user_dir=%s" % [_phase, OS.get_name(), TvMode.active(),
		Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method(), _dir_kind()])
	await wait(1.0)
	if _phase == "reopen":
		await _reopen()
	elif _phase == "back":
		await _back_probe()
	elif _phase == "cleanup_photo":
		await _cleanup_photo()
	elif _phase == "menus_back":
		await _menus_back_loop()
	elif _phase == "defaults":
		await _defaults_smoke()
	elif _phase == "defaults_restart":
		await _defaults_restart()
	else:
		await _main_phase()
	_finish()


## Fail fast: the cases run in order and the phase stops at the first case with a failure, so a broken
## prerequisite never runs the cases that depend on it (they are reported as not run).
func _main_phase() -> void:
	var c: Node = main.controller
	var hud: Control = main.hud
	var steps := [_launch, _join_screen, _start_solo, _walk.bind(c), _camera.bind(c), _modal.bind(c, hud), _context.bind(c, hud),
		_photo.bind(c, hud), _decorate.bind(c, hud), _b_safety.bind(c, hud), _swap.bind(c, hud), _languages.bind(c, hud),
		_disconnect.bind(c, hud), _siri_menu.bind(c, hud), _storage_write]
	for step in steps:
		var f0 := failures
		var d0 := _done.size()
		await step.call()
		if failures > f0 or _done.size() == d0:
			print("ABORT the main phase after a failing case (%d failures, %s); later cases are not run" % [failures - f0, "ended" if _done.size() > d0 else "did not reach its end"])
			return


func _launch() -> void:
	_photos_before = PhotoStore.list()
	_photos_recorded = true
	var menus: Control = main.menus
	I18n.set_locale("en")
	PadInput.set_swap(false)
	# Launch: the menus answer the controller; no ui_* action carries joypad input any more.
	check(menus.visible, "the game starts at its menus")
	var joy_in_ui := []
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_select", "ui_cancel"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				joy_in_ui.append(a)
	check(joy_in_ui.is_empty(), "no ui_* action reacts to the controller (no double actions): %s" % [joy_in_ui])
	if TvMode.active() and not main.args.has("safe-insets"):
		var vs: Vector2 = get_viewport().get_visible_rect().size
		check(absf(menus.offset_left - vs.x * TvMode.SAFE_X) < 1.5 or menus.offset_left > vs.x * TvMode.SAFE_X,
			"the menus keep to the TV title-safe edge (%.0f px of %.0f)" % [menus.offset_left, vs.x])
	await btn(JOY_BUTTON_DPAD_DOWN)
	check(pad.shown and pad._cursor_node.visible, "the controller pointer appears when the controller is used")
	await hints_ok("title")
	check(pad.layout in ["nintendo", "standard"], "controller layout: %s" % pad.layout)
	check(pad.confirm_button() == phys("A") and pad.back_button() == phys("B"), "the button labelled A confirms and the one labelled B goes back")
	await shot("title")
	await choose(button_text(menus, "Play"), "Play")
	check(await until(func(): return button_text(menus, "Let's go!") != null, 3.0), "Play opens the character screen")
	await btn(phys("B"))
	check(await until(func(): return button_text(menus, "Play") != null, 3.0), "B goes back to the title")
	case_done("launch and menus")


func _join_screen() -> void:
	var menus: Control = main.menus
	# The TV join screen: nothing to type, the prepared town only, its address never on screen.
	await choose(button_text(menus, "Play with friends"), "Play with friends")
	await until(func(): return button_text(menus, "Let's go!") != null, 3.0)
	await choose(button_text(menus, "Let's go!"), "Let's go!")
	check(await until(func(): return menus.find_child("TownAddress", true, false) != null, 3.0) or not TvMode.active(), "the friends screen opens")
	if TvMode.active():
		var edits := menus.find_children("*", "LineEdit", true, false).filter(func(e): return e.is_visible_in_tree())
		check(edits.is_empty(), "no text field is offered on a TV (no keyboard)")
		var join := menus.find_child("Join", true, false) as Button
		check(join != null and join.disabled == menus.deployment.is_empty(), "Join is on exactly when the app has a prepared town (%s)" % ("prepared" if not menus.deployment.is_empty() else "not prepared"))
		var shown_addr := menus.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree() and str(l.text).contains("://"))
		check(shown_addr.is_empty(), "no server address is shown on screen")
		await shot("friends_tv")
	await btn(phys("B"))
	await until(func(): return button_text(menus, "Let's go!") != null, 3.0)
	await btn(phys("B"))
	check(await until(func(): return button_text(menus, "Play") != null, 3.0), "B, B: back to the title")
	case_done("TV join screen")


func _start_solo() -> void:
	var menus: Control = main.menus
	var hud: Control = main.hud
	# Solo play in the tour's own town (the real Play and Let's go! buttons; only the save file differs).
	for f in [TOUR_SAVE, TOUR_SAVE + ".bak", STORE]:   # a stale record of an earlier run must never be read back
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	for conn in menus.play_solo.get_connections():
		menus.play_solo.disconnect(conn["callable"])
	menus.play_solo.connect(func(avatar): Session.start_solo(TOUR_SAVE, avatar))
	await choose(button_text(menus, "Play"), "Play")
	await until(func(): return button_text(menus, "Let's go!") != null, 3.0)
	await choose(button_text(menus, "Let's go!"), "Let's go!")
	check(await until(func(): return hud.visible and not menus.visible, 10.0), "Let's go! starts the town")
	await wait(1.5)
	for i in 4:
		if modal_open():
			await btn(phys("B"))   # a welcome card: B closes it through its own Close
			await wait(0.4)
	check(not modal_open(), "no dialog is left open")
	case_done("solo start")


func _walk(c: Node) -> void:
	var p0: Vector2 = c.pos
	await stick(true, Vector2(0.14, 0.0), 0.6)
	check(c.pos.distance_to(p0) < 0.05, "a stick resting inside the deadzone does not walk (%.2f m)" % c.pos.distance_to(p0))
	await stick(true, Vector2(0.0, -1.0), 1.0)
	var moved: float = c.pos.distance_to(p0)
	check(moved > 1.0, "the left stick walks (%.1f m)" % moved)
	var p1: Vector2 = c.pos
	await wait(0.4)
	check(c.pos.distance_to(p1) < 0.05 and c.pad_move == Vector2.ZERO, "letting go stops at once")
	await hints_ok("play")
	# Readable text decides the place by itself (Mac r1: the hints covered the town status): a status-like
	# label where the hints now are sends them elsewhere, still covering no button.
	# The hints may be placed again (5 times a second) at any frame, so the precondition is checked against
	# a snapshot taken right after an explicit placement, not against wherever the hints are a frame later.
	pad._place_hints()
	var snapshot: Rect2 = pad.hint_rect()
	var marker := Label.new()
	marker.text = "Town status (test)"
	marker.size = Vector2(240, 36)
	main.hud.add_child(marker)
	marker.global_position = snapshot.position + Vector2(20, 10)   # on the hints' place, in screen terms
	check(marker.get_global_rect().intersects(snapshot), "(the test text sits where the hints were placed: %s, text %s)" % [snapshot, marker.get_global_rect()])
	await frames(2)
	pad._place_hints()
	check(not pad.hint_rect().intersects(marker.get_global_rect()), "the hints move off readable text (%s, text %s)" % [pad.hint_rect(), marker.get_global_rect()])
	check(pad.targets().all(func(t): return not t.get_global_rect().intersects(pad.hint_rect())), "and still cover no button")
	marker.queue_free()
	await frames(2)
	await shot("walk")
	case_done("walk")


func _camera(c: Node) -> void:
	var y0: int = main.rig.yaw_step
	await btn(JOY_BUTTON_RIGHT_SHOULDER)
	check(main.rig.yaw_step != y0, "R turns the camera")
	await btn(JOY_BUTTON_LEFT_SHOULDER)
	check(main.rig.yaw_step == y0, "L turns it back")
	# ZL over the world zooms (a wheel step where the pointer is, like a mouse wheel).
	var world_spot := Rect2(_area().get_center() + Vector2(-40, -140), Vector2(80, 60))
	await steer(world_spot)
	# As with a mouse wheel (play_controller.gd): down zooms in from the far view, up zooms back out.
	var z0: int = main.rig.zoom
	var first := JOY_AXIS_TRIGGER_RIGHT if z0 == 0 else JOY_AXIS_TRIGGER_LEFT
	var second := JOY_AXIS_TRIGGER_LEFT if z0 == 0 else JOY_AXIS_TRIGGER_RIGHT
	axis(first, 1.0)
	await frames(3)
	axis(first, 0.0)
	await frames(3)
	check(main.rig.zoom != z0, "one trigger press zooms (zoom %d -> %d)" % [z0, main.rig.zoom])
	axis(second, 1.0)
	await frames(3)
	axis(second, 0.0)
	await frames(3)
	check(main.rig.zoom == z0, "the other trigger zooms back (zoom %d)" % main.rig.zoom)
	case_done("camera")


func _modal(c: Node, hud: Control) -> void:
	await choose(hud._lantern_btn, "the Scrapbook button")
	check(await until(func(): return modal_open(), 2.0), "the Scrapbook opens")
	var p0: Vector2 = c.pos
	var cur0: Vector2 = pad.cursor
	await stick(true, Vector2(1.0, 0.0), 0.5)
	check(c.pos.distance_to(p0) < 0.05 and pad.cursor.distance_to(cur0) > 50.0, "in a dialog the left stick moves the pointer, never the child")
	var outside: Array = pad.targets().filter(func(t): return not hud._overlay.is_ancestor_of(t))
	check(outside.is_empty(), "the D-pad only reaches the dialog's own buttons")
	await hints_ok("dialog")
	var close := button_text(hud._overlay, "Close")
	check(close != null and _area().encloses(close.get_global_rect()), "the Scrapbook's Close is on screen in the safe area (%s)" % (close.get_global_rect() if close else "missing"))
	await btn(phys("B"))
	check(await until(func(): return not modal_open(), 2.0), "B closes the Scrapbook (its Close button)")
	case_done("dialog holds the world")


func _context(c: Node, hud: Control) -> void:
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	if houses.is_empty():
		check(false, "the town has a house")
		return
	c.pos = TownModel.door_point(houses[0])   # setup: stand at the first house's door
	c._place_kid()
	main.rig.snap()
	check(await until(func(): return c._ctx.get("type", "") == "enter" and hud._context_btn.is_visible_in_tree(), 5.0), "at a door the game offers to go in")
	var parts: Array = pad.hint_parts()
	check(parts.any(func(p): return p[0] == "X" if pad.layout == "nintendo" else p[0] == "Y"), "the hints name the context button")
	await btn(phys("X"))
	check(await until(func(): return c.space != "town", 4.0), "X goes into the house (the context action)")
	await wait(1.0)
	# Mac r1 visual finding: here the context button holds the bottom centre and the hints covered the
	# town status at the top. They must find a place that covers neither.
	check(await until(func(): return hud._context_btn.is_visible_in_tree(), 3.0), "(inside, the context button shows)")
	await hints_ok("inside a house")
	check(not pad.hint_rect().intersects(hud._status.get_global_rect()), "the hints leave the town status readable (%s, status %s)" % [pad.hint_rect(), hud._status.get_global_rect()])
	await shot("inside")
	if await until(func(): return c._ctx.get("type", "") == "exit", 1.0):
		await btn(phys("X"))
	else:
		c.go_to_room("town")
	check(await until(func(): return c.space == "town", 4.0), "and back out to town")
	await wait(0.8)
	case_done("context action")


func _photo(c: Node, hud: Control) -> void:
	var asked := [0]
	hud.photo_requested.connect(func(): asked[0] += 1)
	var before: int = PhotoStore.list().size()
	var cam := button_text(hud, "Take a photo")
	# Mac r1 visual finding: the controller hints were in the saved photo. At the moment the picture is read,
	# nothing but the world may be drawn; afterwards everything comes back as it was.
	var seen := []
	main.capture_observer = func(state): seen.append(state)
	if main.args.has("no-shots"):
		main.capture_wait = func(): await get_tree().process_frame   # headless draws no frame to wait for
	var pad_shown: bool = pad.visible and pad._cursor_node.visible
	await choose(cam, "the camera button")
	check(asked[0] == 1, "one A press takes exactly one photo (%d)" % asked[0])
	check(await until(func(): return seen.size() == 1, 4.0), "the picture was read once (%d)" % seen.size())
	check(seen.size() == 1 and not seen[0]["hud"] and not seen[0]["pad"], "while it was read, the HUD and the controller pointer and hints were hidden (%s)" % [seen])
	check(await until(func(): return hud.visible, 3.0) and pad.visible and pad._cursor_node.visible == pad_shown, "afterwards the HUD, pointer and hints are back as they were")
	# The same for a story picture (the story flow takes its pictures with the same camera).
	await wait(1.0)
	while modal_open():
		await btn(phys("B"))
		await wait(0.3)
	await choose(hud._story_btn, "the Story button")
	var card: Button = null
	for b in hud._overlay.find_children("*", "Button", true, false):
		if b.has_meta("story_card") and b.is_visible_in_tree():
			card = b
			break
	await choose(card, "a story card")
	check(await until(func(): return not hud.story.is_empty(), 2.0), "a story is started")
	await wait(0.5)
	await choose(button_text(hud, "Take a photo"), "the camera button for a story picture")
	check(await until(func(): return seen.size() == 2, 4.0) and not seen[-1]["hud"] and not seen[-1]["pad"], "a story picture is read with the overlays hidden too (%s)" % [seen])
	check(await until(func(): return hud.visible, 3.0) and pad.visible, "and they come back after it")
	hud.story = {}   # setup: end the unfinished story (not part of the check)
	hud._refresh_play_chip()
	main.capture_observer = Callable()
	main.capture_wait = Callable()
	if main.args.has("no-shots"):
		if _finished:
			return
		var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
		img.fill(Color.CORNFLOWER_BLUE)
		PhotoStore.save(img)
		print("DIAG no renderer: the captured frame is empty, so a stand-in photo is stored for the scrapbook steps")
	check(await until(func(): return PhotoStore.list().size() == before + 1, 6.0), "the photo is kept in the scrapbook on this device")
	_note_artifacts()
	await wait(1.0)
	while modal_open():
		await btn(phys("B"))
		await wait(0.3)
	check(await until(func(): return hud.visible, 4.0), "the game is back after the photo")
	await choose(hud._lantern_btn, "the Scrapbook button")
	await frames(4)
	# R20 shows the newest photos as pictures in the Scrapbook (meta "photo"); ZR scrolls the list to them.
	var thumbs: Array = hud._overlay.find_children("*", "TextureRect", true, false).filter(func(r): return r.has_meta("photo") and r.is_visible_in_tree())
	check(not thumbs.is_empty(), "the Scrapbook shows the photos (%d)" % thumbs.size())
	if not thumbs.is_empty():
		var thumb: Control = thumbs[-1]
		var sc: ScrollContainer = pad._scroll_of(thumb)
		if sc:
			await steer(Rect2(sc.get_global_rect().get_center() - Vector2(30, 30), Vector2(60, 60)))
			for k in 12:
				if sc.get_global_rect().grow(1.0).encloses(thumb.get_global_rect()):
					break
				axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
				await frames(2)
				axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
				await frames(3)
		check(_area().encloses(thumb.get_global_rect()) and (sc == null or sc.get_global_rect().grow(1.0).encloses(thumb.get_global_rect())),
			"ZR scrolls the Scrapbook until the newest photo is in view, inside the safe area")
	await shot("scrapbook_photo")
	await btn(phys("B"))
	await until(func(): return not modal_open(), 2.0)
	case_done("camera photo and scrapbook")


func _decorate(c: Node, hud: Control) -> void:
	var pressed := [0]
	hud._decorate_btn.pressed.connect(func(): pressed[0] += 1)
	await choose(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0) and pressed[0] == 1, "A presses Decorate exactly once")
	check(c._walk_target == null, "and the same press is not also a tap on the world")
	check(not hud._search.is_visible_in_tree() or TvMode.can_type(), "the toy box offers no search field on a TV; its tabs browse everything")
	var card: Button = null
	for b in hud._cards.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.has_meta("kind") and Catalog.anchor(b.get_meta("kind")) == "ground" and Catalog.grid(b.get_meta("kind")) == 0.0:
			card = b
			break
	var placed_kind: String = card.get_meta("kind") if card else ""
	await choose(card, "a toy box card")
	check(await until(func(): return c.ghost != null, 2.0), "the card starts placing it")
	await hints_ok("placing")
	await shot("placing")
	var g0: Vector2 = c.g_pos
	var p0: Vector2 = c.pos
	await stick(true, Vector2(1.0, 0.0), 0.8)
	check(c.g_pos.distance_to(g0) >= 0.5 and c.pos.distance_to(p0) < 0.05, "the left stick moves the thing, not the child (%.2f m)" % c.g_pos.distance_to(g0))
	var r0: int = c.g_rot
	await btn(phys("Y"))
	check(c.g_rot != r0, "Y turns it")
	if c.g_error != "":
		await stick(true, Vector2(-1.0, 0.6), 0.6)
	var n0: int = Session.model.items.size()
	await btn(JOY_BUTTON_START)
	check(await until(func(): return Session.model.items.size() == n0 + 1, 3.0), "+ places it (Place here)")
	if c.ghost == null:
		# The toy box rebuilds its cards after a placement: find the same kind's card again.
		var again: Button = null
		for b in hud._cards.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and b.get_meta("kind", "") == placed_kind:
				again = b
		await choose(again, "the toy box card again")
	check(await until(func(): return c.ghost != null, 2.0), "placing another")
	var n1: int = Session.model.items.size()
	await btn(phys("B"))
	check(await until(func(): return c.ghost == null, 2.0) and Session.model.items.size() == n1 and not hud._tools.is_visible_in_tree(), "B cancels placing: nothing added, the tools close")
	check(c.mode == "decorate", "and stays in Decorate")
	case_done("decorate")


func _b_safety(c: Node, hud: Control) -> void:
	# An unfamiliar dialog whose first option is destructive: B must choose neither option.
	var called := []
	hud._dialog("Test dialog", "", [["Throw everything away", func(): called.append("destructive"), false], ["Maybe later", func(): called.append("other"), true]])
	await frames(3)
	await btn(phys("B"))
	await frames(4)
	check(called.is_empty() and not modal_open(), "B on an unfamiliar dialog closes it without choosing any option (%s)" % [called])
	# A confirmation while editing (Put this house away?): B is "Keep it", which also ends the edit cleanly.
	var placed: Array = Session.model.items.values().filter(func(i): return i.get("space") == c.space and Catalog.anchor(i["kind"]) == "ground")
	if not placed.is_empty():
		var id: String = placed[-1]["id"]
		c.select_item(id)
		check(await until(func(): return c.ghost != null and c.g_edit_id == id, 2.0), "(editing an item)")
		hud._confirm_remove(Session.model.items[id], 3)
		await frames(3)
		await btn(phys("B"))
		check(await until(func(): return not modal_open() and c.ghost == null, 2.0) and Session.model.items.has(id), "B on the confirmation keeps the item and ends the edit (Keep it)")
	# Leaving Decorate: B with nothing being placed presses Done.
	await btn(phys("B"))
	check(await until(func(): return c.mode == "play", 2.0), "B leaves Decorate")
	case_done("B safety")


func _swap(c: Node, hud: Control) -> void:
	await choose(button_text(hud, "Sound and music"), "the Sound and music button")
	var sw := hud._overlay.find_child("SwapAB", true, false) as Button
	check(sw != null, "the settings offer Swap A and B")
	if sw:
		await choose(sw, "Swap A and B")
		check(PadInput.swap_ab and pad.confirm_button() == phys("B"), "after swapping, the button labelled B confirms")
		sw = hud._overlay.find_child("SwapAB", true, false) as Button
		var ok := await go_to(sw)
		if ok:
			await btn(phys("B"))   # now the confirm button
		check(not PadInput.swap_ab and pad.confirm_button() == phys("A"), "swapping back with it restores A")
	await btn(phys("B"))
	check(await until(func(): return not modal_open(), 2.0), "B closes the settings")
	case_done("swap A and B")


func _languages(c: Node, hud: Control) -> void:
	for loc in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		I18n.set_locale(loc)
		await frames(3)
		await choose(hud._lantern_btn, "[%s] the Scrapbook button" % loc)
		await until(func(): return modal_open(), 2.0)
		await hints_ok("[%s] dialog" % loc)
		var text: String = pad._hint_label.text
		check(text.contains(tr("Select")) and (loc == "en" or tr("Select") != "Select"), "[%s] the hints are in this language" % loc)
		# The font the hint actually draws with has every character of the translated hint (Apple TV r4:
		# Japanese showed boxes for kanji, because the hints used Godot's own Latin font).
		var hint_font: Font = pad._hint_label.get_theme_font("font")
		var missing := []
		for ch in text:
			if ch.strip_edges() != "" and not hint_font.has_char(ch.unicode_at(0)):
				missing.append(ch)
		check(missing.is_empty(), "[%s] the hint font has every character of the hints (%s; missing %s)" % [loc, hint_font.get_font_name(), missing])
		var close := button_text(hud._overlay, "Close")
		check(close != null and _area().encloses(close.get_global_rect()), "[%s] Close is inside the safe area" % loc)
		if loc in ["de", "ja", "zh-CN"]:   # CJK hint glyphs visible on the actual TV (r5)
			await shot("%s_scrapbook" % loc)
		await btn(phys("B"))
		await until(func(): return not modal_open(), 2.0)
	I18n.set_locale("en")
	case_done("languages")


func _disconnect(c: Node, hud: Control) -> void:
	# A real controller may be connected beside the simulated one (on the Apple TV the paired Switch Pro is).
	# Then a disconnect of the simulated controller correctly falls back to the real one; both cases are checked.
	var all: Array = Input.get_connected_joypads()
	var others: Array = all.filter(func(d): return d != DEV)
	print("DIAG controllers connected %s (%s); in use %d; simulated device %d" % [all, all.map(func(d): return Input.get_joy_name(d)), pad.device, DEV])
	await btn(JOY_BUTTON_DPAD_DOWN)
	check(pad.device == DEV, "(the simulated controller %d is the one in use: %d)" % [DEV, pad.device])
	axis(JOY_AXIS_LEFT_Y, -1.0)
	await wait(0.4)
	check(c.walking, "(walking)")
	Input.joy_connection_changed.emit(DEV, false)
	await frames(2)
	var p0: Vector2 = c.pos
	await wait(0.4)
	check(c.pos.distance_to(p0) < 0.05 and c.pad_move == Vector2.ZERO, "a controller that disconnects mid-walk stops the child")
	check(str(hud._toast_label.text) == "Controller disconnected", "the game says the controller disconnected")
	if others.is_empty():
		check(pad.device == -1 and not pad._cursor_node.visible, "with no controller left the pointer hides")
		Input.joy_connection_changed.emit(DEV, true)
		await frames(2)
		check(str(hud._toast_label.text) == "Controller connected" and pad.device == DEV and pad.shown, "when it comes back the game says so and uses it")
	else:
		check(pad.device == others[0] and pad.shown and pad._cursor_node.visible, "another connected controller (%d) takes over at once; the pointer stays" % others[0])
		Input.joy_connection_changed.emit(DEV, true)
		await frames(2)
		check(pad.device == others[0], "a returning controller does not take over by itself (%d stays in use)" % others[0])
		await btn(JOY_BUTTON_DPAD_DOWN)
		check(pad.device == DEV, "pressing a button on it makes it the one in use")
	# A press whose release never comes (the controller went away): nothing stays pressed.
	await steer(Rect2(_area().get_center() + Vector2(-40, -140), Vector2(80, 60)))
	joy_button(phys("A"), true)
	await frames(1)
	Input.joy_connection_changed.emit(DEV, false)
	await frames(3)
	check(Input.get_mouse_button_mask() == 0, "no tap stays pressed after a disconnect")
	Input.joy_connection_changed.emit(DEV, true)
	await btn(JOY_BUTTON_DPAD_DOWN)
	check(pad.shown and pad.device == DEV, "the controller works again after reconnecting")
	await btn(phys("B"))
	case_done("disconnect")


# ------------------------------------------------------------- storage

func _dir_kind() -> String:
	var parts := OS.get_user_data_dir().split("/", false)
	return "/".join(parts.slice(-2)) if parts.size() >= 2 else "?"   # never the full container path


func _sha(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


## Settings, the town save and a photo, each written and read straight back. Only hashes are kept.
func _storage_write() -> void:
	var token := "%08x" % (randi() & 0x7fffffff)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("tv_tour", "marker", token)
	check(cfg.save(SETTINGS) == OK, "settings can be written")
	var back := ConfigFile.new()
	check(back.load(SETTINGS) == OK and back.get_value("tv_tour", "marker", "") == token, "and read back")
	check(Session.save_now(), "the town save can be written")
	var town_sha := _sha(TOUR_SAVE)
	check(town_sha != "", "and is on this device")
	var photo: String = PhotoStore.list()[-1] if not PhotoStore.list().is_empty() else ""
	var photo_path := PhotoStore.DIR.path_join(photo)
	var photo_sha := _sha(photo_path)
	check(photo != "" and photo_sha != "" and Image.load_from_file(ProjectSettings.globalize_path(photo_path)) != null, "the photo file can be read back")
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	check(f != null, "the tour record can be written")
	if f:
		f.store_string(JSON.stringify({"token": token, "town_sha": town_sha, "items": Session.model.items.size(), "photo": photo, "photo_sha": photo_sha}))
		f.close()
	print("STORAGE wrote settings marker, town %s, photo %s" % [town_sha.left(12), photo_sha.left(12)])
	case_done("storage write")


func _reopen() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(STORE)) if FileAccess.file_exists(STORE) else null
	check(typeof(data) == TYPE_DICTIONARY, "the first run's record is still here after relaunching")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var cfg := ConfigFile.new()
	check(cfg.load(SETTINGS) == OK and cfg.get_value("tv_tour", "marker", "") == data["token"], "the settings kept their value across the relaunch")
	check(_sha(TOUR_SAVE) == data["town_sha"], "the town save is byte-identical after relaunching")
	Session.start_solo(TOUR_SAVE, main.menus.avatar)
	await wait(1.0)
	check(Session.model.items.size() == int(data["items"]), "and loads with every item (%d)" % Session.model.items.size())
	var photo_path := PhotoStore.DIR.path_join(str(data["photo"]))
	check(PhotoStore.list().has(data["photo"]) and _sha(photo_path) == data["photo_sha"], "the photo is still in the scrapbook, the same bytes")
	check(PhotoStore.thumbnail(str(data["photo"])) != null, "and its picture loads")
	# Clean up the tour's own data only.
	Session.dirty = false
	Session.leave()
	cfg.erase_section_key("tv_tour", "marker")
	cfg.save(SETTINGS)
	for p in [photo_path, TOUR_SAVE, TOUR_SAVE + ".bak", STORE, ARTIFACTS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("STORAGE reopened: settings, town and photo intact; tour data removed")
	case_done("storage reopen")


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _phase == "main" and not _done.has("storage write") and _photos_recorded:
		_cleanup_after_abort()
	var expected: Array = CASES.get(_phase, [])
	for name in expected:
		if not _done.has(name):
			check(false, "case %s ran to its end" % name)
	var ok := failures == 0
	var result := {"phase": _phase, "pass": ok, "failures": failures, "checks": _checks, "cases_done": _done,
		"cases_expected": expected, "screenshots": _shot_names, "layout": pad.layout if pad else "", "tv": TvMode.active(),
		"os": OS.get_name(), "engine": Engine.get_version_info()["string"], "renderer": RenderingServer.get_current_rendering_method(),
		"user_dir": _dir_kind()}
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	print("TVTOUR %s %s %s: %d failures, %d checks, %d screenshots, result %s" % [tag, _phase, "PASS" if ok else "FAIL", failures,
		_checks, _shot_names.size(), "written" if f else "NOT WRITTEN"])
	Music.quit_game(0 if ok else 1)


## Small bounded phase: Play, then B on the character screen, with what B selected and where.
func _back_probe() -> void:
	var menus: Control = main.menus
	pad.acted.connect(func(a): print("DIAG acted %s cursor %s" % [a, pad.cursor]))
	await btn(JOY_BUTTON_DPAD_DOWN)
	await choose(button_text(menus, "Play"), "Play")
	check(await until(func(): return button_text(menus, "Let's go!") != null, 3.0), "Play opens the character screen")
	await frames(3)
	for b in menus.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree():
			print("DIAG button '%s' tip '%s' rect %s disabled %s queued %s" % [b.text if b is Button else "", b.tooltip_text, b.get_global_rect(), b.disabled, b.is_queued_for_deletion()])
	var sel: BaseButton = pad._button_in(menus, ["Back"])
	print("DIAG B selects %s at %s" % [sel.text if sel else "nothing", sel.get_global_rect() if sel else Rect2()])
	if sel:
		sel.pressed.connect(func(): print("DIAG Back pressed signal"))
	await btn(phys("B"))
	await frames(4)
	print("DIAG after B: screen %s, cursor %s, hovered %s, menus rect %s, visible rect %s" % [menus._screen, pad.cursor,
		get_viewport().gui_get_hovered_control().get_path() if get_viewport().gui_get_hovered_control() else "none", menus.get_global_rect(), get_viewport().get_visible_rect()])
	check(await until(func(): return button_text(menus, "Play") != null, 3.0), "B goes back to the title")
	case_done("menus back")


# ------------------------------------------------------------- native defaults smoke (device only)

const SMOKE_DIR := "user://tv_smoke"
const SMOKE_EXPECT := "user://tv_smoke/expect.json"


func _smoke_files() -> Dictionary:
	return {SMOKE_DIR + "/settings.cfg": ["test.smoke.settings", "config", 16 * 1024],
		SMOKE_DIR + "/town.json": ["test.smoke.town", "town", 176 * 1024]}


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _defaults_smoke() -> void:
	var Durable = load("res://scripts/core/durable.gd")
	var be: Object = Engine.get_singleton("LanternDefaults") if Engine.has_singleton("LanternDefaults") else null
	check(be != null, "the LanternDefaults module is in this build")
	if be == null:
		return
	var leftover: PackedStringArray = be.call("keys", "test.")
	for k in leftover:
		be.call("erase_blob", k)   # an earlier interrupted smoke run: only test names
	print("DEFAULTS leftover test names removed: %d" % leftover.size())
	var d0: int = be.call("domain_bytes")
	check(int(be.call("budget")) == 384 * 1024, "the module's budget is 384 KiB of the whole store")
	print("DEFAULTS domain before: %d bytes" % d0)
	Durable.files = _smoke_files()
	Durable.status = {}
	var token := "%08x" % (randi() & 0x7fffffff)
	var cfgp := SMOKE_DIR + "/settings.cfg"
	var town := SMOKE_DIR + "/town.json"
	_write_text(cfgp, "[tv_smoke]\nmarker=\"%s\"\n" % token)
	_write_text(town, JSON.stringify(TownModel.make_default().to_dict()))
	check(Durable.mirror(cfgp) == "ok" and Durable.mirror(town) == "ok", "both synthetic files are copied")
	var town_raw := FileAccess.get_file_as_bytes(town)
	var blob: PackedByteArray = be.call("get_blob", "test.smoke.town")
	check(Durable.unpack(blob) == town_raw, "the copy reads back to the same bytes")
	check(int(be.call("candidate_bytes", "test.smoke.town", blob)) == int(be.call("domain_bytes")), "the exact size of the store with an unchanged value equals its size now")
	# The whole-store budget: fill close to it, then a write that would pass it is refused, nothing changes.
	# Every filler and the refused value are DISTINCT bytes: a binary property list may keep identical data
	# values once, which would make a store of repeated blobs look smaller than it is.
	var n := 0
	while int(be.call("domain_bytes")) + 150 * 1024 + 4096 < 384 * 1024 and n < 3:
		n += 1
		check(int(be.call("put_blob", "test.smoke.fill%d" % n, _distinct_blob(150 * 1024, n))) == OK, "(filler %d stored)" % n)
	var before_bytes: int = be.call("domain_bytes")
	var before_keys: PackedStringArray = be.call("keys", "test.")
	var big := _distinct_blob(150 * 1024, 99)
	var over: int = be.call("candidate_bytes", "test.smoke.over", big)
	var err: int = be.call("put_blob", "test.smoke.over", big)
	check(over > 384 * 1024 and err == ERR_OUT_OF_MEMORY, "a write that would make the store %d bytes is refused (%d)" % [over, err])
	check(int(be.call("domain_bytes")) == before_bytes and be.call("keys", "test.") == before_keys, "and the store is exactly as before")
	for i in range(1, n + 1):
		be.call("erase_blob", "test.smoke.fill%d" % i)
	print("DEFAULTS budget: %d fillers, %d bytes before, refused at %d" % [n, before_bytes, over])
	# A corrupt copy is never used.
	var bad := blob.duplicate()
	bad[bad.size() - 3] = bad[bad.size() - 3] ^ 0x55
	check(int(be.call("put_blob", "test.smoke.town", bad)) == OK, "(a corrupt copy is stored on purpose)")
	DirAccess.remove_absolute(town)
	check(Durable.restore(town) == "damaged" and not FileAccess.file_exists(town), "a corrupt copy is never used")
	check(int(be.call("put_blob", "test.smoke.town", blob)) == OK, "(the good copy is back)")
	# The staging file deleted (as a purge would) or invalid: it comes back.
	check(Durable.restore(town) == "restored" and FileAccess.get_file_as_bytes(town) == town_raw, "a deleted staging file comes back from its copy")
	_write_text(town, JSON.stringify({"schema": 99}))
	check(Durable.restore(town) == "restored" and FileAccess.get_file_as_bytes(town) == town_raw, "an invalid staging file is replaced by the copy")
	var f := FileAccess.open(SMOKE_EXPECT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"token": token, "d0": d0, "town_sha": Durable.digest(town_raw).hex_encode(),
			"settings_sha": Durable.digest(FileAccess.get_file_as_bytes(cfgp)).hex_encode()}))
		f.close()
	Durable.files = Durable.FILES
	print("DEFAULTS first launch done; relaunch with --phase=defaults_restart")
	case_done("defaults smoke")


## Bytes that differ for every seed (and do not compress away): one per filler key.
func _distinct_blob(size: int, seed: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5eed0000 + seed
	var out := PackedByteArray()
	out.resize(size)
	for i in size:
		out[i] = rng.randi() & 0xff
	return out


func _defaults_restart() -> void:
	var Durable = load("res://scripts/core/durable.gd")
	var be: Object = Engine.get_singleton("LanternDefaults") if Engine.has_singleton("LanternDefaults") else null
	check(be != null, "the LanternDefaults module is in this build")
	var expect = JSON.parse_string(FileAccess.get_file_as_string(SMOKE_EXPECT)) if FileAccess.file_exists(SMOKE_EXPECT) else null
	check(typeof(expect) == TYPE_DICTIONARY, "the first launch's record is here")
	if be == null or typeof(expect) != TYPE_DICTIONARY:
		return
	Durable.files = _smoke_files()
	Durable.status = {}
	var town := SMOKE_DIR + "/town.json"
	var cfgp := SMOKE_DIR + "/settings.cfg"
	check(Durable.digest(Durable.unpack(be.call("get_blob", "test.smoke.town"))).hex_encode() == expect["town_sha"], "after relaunching, the town copy is intact")
	check(Durable.digest(Durable.unpack(be.call("get_blob", "test.smoke.settings"))).hex_encode() == expect["settings_sha"], "and the settings copy")
	for p in [town, cfgp]:
		DirAccess.remove_absolute(p)   # as if the TV had cleared its cache while the app was closed
	check(Durable.restore(town) == "restored" and Durable.restore(cfgp) == "restored", "both files come back after the cache is cleared")
	check(Durable.digest(FileAccess.get_file_as_bytes(town)).hex_encode() == expect["town_sha"] and Durable.digest(FileAccess.get_file_as_bytes(cfgp)).hex_encode() == expect["settings_sha"], "byte for byte")
	# Clean up exactly the test names and files.
	for k in be.call("keys", "test."):
		be.call("erase_blob", k)
	check((be.call("keys", "test.") as PackedStringArray).is_empty(), "every lantern.test.* name is removed")
	var d1: int = be.call("domain_bytes")
	print("DEFAULTS domain after cleanup: %d bytes (before the smoke: %d)" % [d1, int(expect["d0"])])
	check(d1 <= int(expect["d0"]), "the store is no bigger than before the smoke run")
	for p in [town, cfgp, SMOKE_EXPECT, town + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(SMOKE_DIR)
	Durable.files = Durable.FILES
	case_done("defaults restart")


# ------------------------------------------------------------- menus back loop (Mac r2 GPU diagnosis)

func _menus_back_loop() -> void:
	var menus: Control = main.menus
	pad.trace = true
	await btn(JOY_BUTTON_DPAD_DOWN)
	for i in 5:
		check(await until(func(): return button_text(menus, "Play with friends") != null, 3.0), "[%d] at the title" % i)
		await choose(button_text(menus, "Play with friends"), "[%d] Play with friends" % i)
		check(await until(func(): return button_text(menus, "Let's go!") != null, 3.0), "[%d] the character screen" % i)
		await choose(button_text(menus, "Let's go!"), "[%d] Let's go!" % i)
		check(await until(func(): return menus.find_child("TownAddress", true, false) != null, 3.0), "[%d] the friends screen" % i)
		await btn(phys("B"))
		check(await until(func(): return button_text(menus, "Let's go!") != null, 3.0), "[%d] B: back to the character screen" % i)
		# No settling frames on purpose: the next B comes as soon as the screen exists (the r2 GPU timing).
		var t0 := Engine.get_process_frames()
		await btn(phys("B"))
		var ok := await until(func(): return button_text(menus, "Play") != null, 3.0)
		print("DIAG [%d] second B: %d frames, back at the title: %s, screen %s" % [i, Engine.get_process_frames() - t0, ok, menus._screen])
		check(ok, "[%d] B again: back to the title" % i)
		if not ok:
			return
	# A slow list: the character screen's list is held at its old scroll for 3 frames after B, as a slow
	# layout pass would. A tap before it settles hits clipped space; the controller must wait and land.
	await choose(button_text(menus, "Play"), "[slow] Play")
	check(await until(func(): return button_text(menus, "Let's go!") != null, 3.0), "[slow] the character screen")
	var sc: ScrollContainer = pad._scroll_of(button_text(menus, "Back"))
	check(sc != null and not pad._tappable(button_text(menus, "Back")), "(the Back button starts out of view in its list)")
	var held := [0]
	var hold := func():
		if held[0] < 3 and is_instance_valid(sc):
			sc.scroll_vertical = 0
			held[0] += 1
	get_tree().process_frame.connect(hold)
	await btn(phys("B"))
	var ok2 := await until(func(): return button_text(menus, "Play") != null, 3.0)
	get_tree().process_frame.disconnect(hold)
	check(held[0] == 3, "(the list was held for 3 frames)")
	check(ok2, "[slow] B still lands on Back once the list has settled: back to the title")
	case_done("menus back loop")


# ------------------------------------------------------------- the tour's own artifacts

## Photos this run created (the game's photos from before the tour are never touched), noted in a small
## file so a later cleanup knows exactly which ones are the tour's.
func _note_artifacts() -> void:
	if _finished:
		return
	var mine: Array = PhotoStore.list().filter(func(n): return not _photos_before.has(n))
	var f := FileAccess.open(ARTIFACTS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"photos": mine}))
		f.close()


## A main run that stopped before its storage step leaves its photo and its town behind: remove exactly
## those (photos created during this run, and the tour's own town files).
func _cleanup_after_abort() -> void:
	var mine: Array = PhotoStore.list().filter(func(n): return not _photos_before.has(n))
	for n in mine:
		DirAccess.remove_absolute(PhotoStore.DIR.path_join(n))
	if not mine.is_empty():
		PhotoStore._write_index(PhotoStore.DIR, PhotoStore._read_index(PhotoStore.DIR).filter(func(n): return not mine.has(n)))
	Session.dirty = false   # the tour town must not be saved again on the way out
	for p in [TOUR_SAVE, TOUR_SAVE + ".bak", ARTIFACTS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("CLEANUP the stopped main run removed its own %d photo(s) and its tour town; earlier photos untouched (%d)" % [mine.size(), _photos_before.size()])


## --phase=cleanup_photo --photo=<exact name> --sha256=<its hash>: removes ONE photo left by an earlier stopped
## tour, only when both its exact name and the SHA-256 of its bytes match, then drops only that name from the
## scrapbook index. No patterns, nothing else: every other photo stays.
func _cleanup_photo() -> void:
	var name: String = main.args.get("photo", "")
	var want: String = str(main.args.get("sha256", "")).to_lower()
	var before: Array = PhotoStore.list()
	var path := PhotoStore.DIR.path_join(name)
	var named := name.begins_with("photo_") and name.ends_with(".png") and not name.contains("/") and before.has(name)
	check(named, "the exact named photo exists in the scrapbook")
	var sha := FileAccess.get_sha256(path) if named else ""
	check(named and want.length() == 64 and sha == want, "and its bytes have exactly the given SHA-256 (%s)" % sha.left(12))
	if not (named and sha == want):
		print("CLEANUP refused: nothing removed")
		case_done("cleanup photo")
		return
	check(DirAccess.remove_absolute(path) == OK, "the photo file is removed")
	PhotoStore._write_index(PhotoStore.DIR, PhotoStore._read_index(PhotoStore.DIR).filter(func(n): return n != name))
	var after: Array = PhotoStore.list()
	check(not after.has(name) and after.size() == before.size() - 1 and before.filter(func(n): return n != name).all(func(n): return after.has(n)),
		"only that photo is gone; every other photo is still there (%d)" % after.size())
	print("CLEANUP removed exactly one photo; %d others untouched" % after.size())
	case_done("cleanup photo")



# ------------------------------------------------------------- Siri Remote Menu (tv_remote.gd)

## Menu goes back one step like B; in town with nothing open it leaves to the title; at the title the next
## press is handed to tvOS (Home). A stand-in remote queues the presses (they cannot be simulated through
## the Game Controller framework); on the TV the real module's view-controller switch is checked too.
func _siri_menu(c: Node, hud: Control) -> void:
	var tvr: Node = main.tv_remote
	check(tvr != null, "the Siri Remote Menu handler runs on a TV")
	if tvr == null:
		return
	var real: Object = Engine.get_singleton("LanternRemote") if Engine.has_singleton("LanternRemote") else null
	print("DIAG Siri Remote: native module %s, remote connected %s" % [real != null, real.call("remote_connected") if real else "n/a"])
	if real:
		check(real.call("set_system_back", true) and real.call("is_system_back"), "the native module hands Menu to tvOS when asked")
		check(real.call("set_system_back", false) and not real.call("is_system_back"), "and takes it back")
	var fake = load("res://tests/fake_remote.gd").new()
	var saved_backend: Object = tvr.backend
	tvr.backend = fake
	var menus: Control = main.menus
	# A dialog: Menu closes it, like B.
	await choose(hud._lantern_btn, "the Scrapbook button")
	check(await until(func(): return modal_open(), 2.0), "(the Scrapbook is open)")
	fake.press()
	check(await until(func(): return not modal_open(), 2.0), "Menu closes the dialog")
	# Placing: Menu cancels it; Decorate: Menu leaves it.
	await choose(hud._decorate_btn, "Decorate")
	await until(func(): return c.mode == "decorate", 2.0)
	var card: Button = null
	for b in hud._cards.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.has_meta("kind") and Catalog.anchor(b.get_meta("kind")) == "ground":
			card = b
			break
	await choose(card, "a toy box card")
	check(await until(func(): return c.ghost != null, 2.0), "(placing)")
	var n0: int = Session.model.items.size()
	fake.press()
	check(await until(func(): return c.ghost == null, 2.0) and Session.model.items.size() == n0, "Menu cancels placing, nothing added")
	fake.press()
	check(await until(func(): return c.mode == "play", 2.0), "Menu leaves Decorate")
	await wait(0.6)   # the HUD switches back from Decorate
	# The engine's go-back request (a Menu press that reached UIKit) does the same.
	await choose(hud._lantern_btn, "the Scrapbook button")
	await until(func(): return modal_open(), 2.0)
	tvr._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(await until(func(): return not modal_open(), 2.0), "the engine's go-back request closes it too")
	# In town with nothing open: back to the title.
	fake.press()
	check(await until(func(): return menus.visible and str(menus._screen) == "title", 4.0), "Menu in town leaves to the title")
	check(not tvr.armed and not fake.system_back, "(Home not armed yet)")
	# The controller's B at the title never arms Home.
	await btn(phys("B"))
	check(not tvr.armed and not fake.system_back and not get_tree().quit_on_go_back, "the controller's B at the title does not touch Home")
	# Menu at the title arms Home: the next Menu press goes to tvOS.
	fake.press()
	check(await until(func(): return tvr.armed, 2.0) and fake.system_back and get_tree().quit_on_go_back, "Menu at the title hands the next Menu press to tvOS (Home)")
	await frames(2)
	var note: Control = tvr.note
	check(note.visible and _area().encloses(note.get_global_rect()), "a note says so, inside the safe area")
	var note_text: String = (note.get_child(0) as Label).text
	var hint_font: Font = (note.get_child(0) as Label).get_theme_font("font")
	check(tr(note_text) != "" and Array(tr(note_text).split("")).all(func(ch): return ch.strip_edges() == "" or hint_font.has_char(ch.unicode_at(0))), "the note's font has its characters")
	check(pad.targets().all(func(t): return not t.get_global_rect().intersects(note.get_global_rect())), "the note covers no button")
	await shot("home_armed")
	# While armed, controller input reaches only UIKit, so the native side ends it (a timeout or another
	# press); the game must follow at once. (A stand-in here: the physical A/B check is a device check.)
	fake.drop_system_back()
	check(await until(func(): return not tvr.armed and not note.visible and not get_tree().quit_on_go_back, 2.0), "when the native side ends the armed state, the game follows at once")
	fake.press()
	check(await until(func(): return tvr.armed, 2.0), "(armed again)")
	# Any controller input the game does see disarms it as well.
	await btn(JOY_BUTTON_DPAD_DOWN)
	check(not tvr.armed and not fake.system_back and not get_tree().quit_on_go_back and not note.visible, "controller input disarms Home at once")
	fake.press()
	check(await until(func(): return tvr.armed, 2.0), "(armed again)")
	# Leaving the title disarms it as well; then back into the tour's town for the storage step.
	await choose(button_text(menus, "Play"), "Play")
	check(await until(func(): return not tvr.armed and not fake.system_back, 2.0), "leaving the title disarms Home")
	await until(func(): return button_text(menus, "Let's go!") != null, 3.0)
	await choose(button_text(menus, "Let's go!"), "Let's go!")
	check(await until(func(): return hud.visible and not menus.visible, 10.0), "(back in the tour's town)")
	await wait(1.0)
	while modal_open():
		await btn(phys("B"))
		await wait(0.3)
	tvr.backend = saved_backend
	case_done("siri remote menu")
