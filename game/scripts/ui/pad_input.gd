## Game controller layer (atv-r20-controller, design/tv-controller.md). One controller plays the whole game
## without touch or mouse:
##   left stick   walk (play), move the thing being placed (decorate), or move the pointer in a dialog
##   right stick  move the pointer
##   A (confirm)  tap where the pointer is: the real button or the real world tap, exactly like a finger
##   B (back)     the dialog's own Close/Cancel/Back button, cancel placing, leave Decorate
##   X / Y        the context action (Sit, Go in, ...) / turn the thing being placed
##   L / R        turn the camera; ZL / ZR scroll a list or zoom; + places; the D-pad jumps between buttons
## A Nintendo controller is positional in Godot (SDL): its A is on the right (Godot JOY_BUTTON_B) and its B at
## the bottom (Godot JOY_BUTTON_A), so the confirm and back buttons follow the label, not the position.
## Button presses only queue an action; actions run in _process, never inside input handling. Each joypad
## event is consumed here, so nothing else (GUI focus, ui_* actions) can act on it a second time.
extends CanvasLayer

const UI := preload("res://scripts/ui/ui_kit.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const SETTINGS_PATH := "user://settings.cfg"

const DEADZONE := 0.22         # radial; motion is rescaled to start from 0 just outside it
const CURSOR_SPEED := 1100.0   # UI pixels per second at full tilt
const GHOST_SPEED := 2.2       # metres per second for a thing being placed
const TRIGGER_ON := 0.55
const TRIGGER_OFF := 0.35
const REPEAT_DELAY := 0.4      # D-pad: held, it repeats after this, then every REPEAT_EVERY
const REPEAT_EVERY := 0.16
const NINTENDO_VENDOR := 0x057E
const DISCOVER_EVERY := 0.5    # seconds between looks for a controller while there is none
## The safe choices of a dialog, in order, for B.
const BACK_LABELS := ["Close", "Cancel", "Back", "Not now", "Keep it", "Done"]

signal acted(action: String)   # after each action ran (tests)
signal controller_used()       # any controller button or stick (the Siri Remote's Menu disarms on it)

## The controller's confirm and back buttons are swapped (Settings), for a controller that reports its
## buttons the other way round. Saved on this device.
static var swap_ab := false
static var _loaded := false

var main: Node
var device := -1               # the controller in use; -1 when none
var layout := "standard"       # "nintendo": confirm is the right face button, labelled A
var forced_layout := ""        # tests: --pad-layout=nintendo|standard (a simulated controller has no name)
var cursor := Vector2(400, 300)
var shown := false             # pointer and hints on screen (a controller is in use)
var _axes := {}                # JoyAxis -> value, for the controller in use
var _queue: Array = []
var _trig := {}
var _dpad := -1
var _dpad_t := 0.0
var _ghost_goal: Variant = null
var _release_at: Variant = null   # a tap's release, sent the next frame
var _recentre: Control = null     # after scrolling a list, put the pointer back on this
var _tap_next: Control = null     # a button being scrolled into view: tapped once it really is there
var _tap_tries := 0
const TAP_TRIES := 10             # frames to wait for a scrolled list to settle before giving up
## --pad-trace: one line per action, chosen button, tap point, press and release frame (diagnosis only;
## never the town address, invite or save content).
var trace := false
var _cursor_node: Control
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_text := ""
var _discover_t := 0.0
var _place_at := 0


static func load_swap() -> bool:
	if not _loaded:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		swap_ab = bool(cfg.get_value("controller", "swap_ab", false))
		_loaded = true
	return swap_ab


static func set_swap(on: bool) -> void:
	swap_ab = on
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("controller", "swap_ab", on)
	cfg.save(SETTINGS_PATH)


## Radial deadzone: nothing inside it, then 0..1 again up to full tilt (no jump at the edge).
static func deadzone(v: Vector2, dz := DEADZONE) -> Vector2:
	var l := v.length()
	if l <= dz:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - dz) / (1.0 - dz))


static func layout_for(joy_name: String, vendor: int) -> String:
	var n := joy_name.to_lower()
	if vendor == NINTENDO_VENDOR or n.contains("nintendo") or n.contains("switch") or n.contains("joy-con") or n.contains("pro controller"):
		return "nintendo"
	return "standard"


func confirm_button() -> int:
	var c := JOY_BUTTON_B if layout == "nintendo" else JOY_BUTTON_A
	if swap_ab:
		c = JOY_BUTTON_A if c == JOY_BUTTON_B else JOY_BUTTON_B
	return c


func back_button() -> int:
	return JOY_BUTTON_A if confirm_button() == JOY_BUTTON_B else JOY_BUTTON_B


func role_of(button: int) -> String:
	if button == confirm_button():
		return "confirm"
	if button == back_button():
		return "back"
	match button:
		JOY_BUTTON_Y: return "context"
		JOY_BUTTON_X: return "turn"
		JOY_BUTTON_LEFT_SHOULDER: return "cam_left"
		JOY_BUTTON_RIGHT_SHOULDER: return "cam_right"
		JOY_BUTTON_START: return "place"
		JOY_BUTTON_DPAD_UP: return "up"
		JOY_BUTTON_DPAD_DOWN: return "down"
		JOY_BUTTON_DPAD_LEFT: return "left"
		JOY_BUTTON_DPAD_RIGHT: return "right"
	return ""


## The letter printed on that button of this controller.
func label_of(button: int) -> String:
	var nin := layout == "nintendo"
	match button:
		JOY_BUTTON_A: return "B" if nin else "A"
		JOY_BUTTON_B: return "A" if nin else "B"
		JOY_BUTTON_X: return "Y" if nin else "X"
		JOY_BUTTON_Y: return "X" if nin else "Y"
		JOY_BUTTON_START: return "+" if nin else "Start"
		JOY_BUTTON_LEFT_SHOULDER: return "L" if nin else "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "R" if nin else "RB"
	return "?"


func _ready() -> void:
	layer = 100
	load_swap()
	# The default ui_* actions bind the left stick, the D-pad and a face button. The game reads ui_* for
	# keyboard walking and the GUI for focus, so with those bindings one press would act twice (walk and
	# move the pointer, or a focused button and a tap). This layer handles every joypad event instead.
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					InputMap.action_erase_event(action, e)
	_cursor_node = _Pointer.new()
	_cursor_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_node.visible = false
	_cursor_node.name = "PadPointer"
	add_child(_cursor_node)
	_hint_panel = UI.panel(14, Color(1, 1, 1, 0.92))
	_hint_panel.name = "PadHints"
	# This layer is outside the HUD and menus, so it must take the game's shared theme itself: its font is
	# switched per language (I18n.ui_font with the bundled Chinese and Japanese fonts). Without it the hints
	# fell back to Godot's own Latin font, and on the Apple TV Japanese showed boxes for kanji.
	_hint_panel.theme = UI.theme()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	_hint_label = UI.label("", 20, UI.TEXT)
	_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # built from translated parts
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(_hint_label)
	add_child(_hint_panel)
	Input.joy_connection_changed.connect(_on_joy)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_use(pads[0])
	cursor = _area().get_center()


func bind(m: Node) -> void:
	main = m


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_reset()   # nothing keeps walking or stays pressed while the app is away


func _use(dev: int) -> void:
	device = dev
	var info: Dictionary = Input.get_joy_info(dev) if Input.get_connected_joypads().has(dev) else {}
	var vendor := str(info.get("vendor_id", "0"))
	layout = forced_layout if forced_layout != "" else layout_for(Input.get_joy_name(dev), int(vendor) if vendor.is_valid_int() else 0)


func _on_joy(dev: int, connected: bool) -> void:
	if connected:
		if device == -1:
			_use(dev)
			_show(true)
			_toast("Controller connected")
	elif dev == device:
		_reset()
		device = -1
		var pads := Input.get_connected_joypads()
		pads.erase(dev)
		if pads.is_empty():
			_show(false)
		else:
			_use(pads[0])
		_toast("Controller disconnected")


## Drops everything held: no walking, no moving, no pressed tap, no queued action.
func _reset() -> void:
	_axes.clear()
	_queue.clear()
	_trig.clear()
	_dpad = -1
	_ghost_goal = null
	_recentre = null
	_tap_next = null
	if _release_at != null:
		_mouse_button(_release_at, MOUSE_BUTTON_LEFT, false)
		_release_at = null
	if main and main.controller:
		main.controller.pad_move = Vector2.ZERO


func _show(on: bool) -> void:
	shown = on
	_cursor_node.visible = on
	_hint_panel.visible = on
	if not on and main and main.controller:
		main.controller.pad_move = Vector2.ZERO


func _toast(text: String) -> void:
	if main and main.hud and main.hud.visible:
		main.hud.show_toast(text)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		if event is InputEventJoypadButton or absf(event.axis_value) > DEADZONE:
			controller_used.emit()
		if device == -1:
			_use(event.device)
		if event.device != device:
			if event is InputEventJoypadButton and event.pressed:
				_reset()
				_use(event.device)   # the controller that was just pressed takes over
			else:
				return
		if not shown:
			_show(true)
		if event is InputEventJoypadMotion:
			_axes[event.axis] = event.axis_value
			if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
				var on: bool = _trig.get(event.axis, false)
				if not on and event.axis_value >= TRIGGER_ON:
					_trig[event.axis] = true
					_queue.append("scroll_up" if event.axis == JOY_AXIS_TRIGGER_LEFT else "scroll_down")
				elif on and event.axis_value <= TRIGGER_OFF:
					_trig[event.axis] = false
		elif event.pressed:
			var r := role_of(event.button_index)
			if r in ["up", "down", "left", "right"]:
				_dpad = event.button_index
				_dpad_t = REPEAT_DELAY
			if r != "":
				_queue.append(r)
		elif event.button_index == _dpad:
			_dpad = -1
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and not event.has_meta("pad") and shown:
		_show(false)   # a finger or a mouse took over: hide the pointer until the controller is used again


func _process(delta: float) -> void:
	if _release_at != null:
		_mouse_button(_release_at, MOUSE_BUTTON_LEFT, false)
		_trace("release at %s" % _release_at)
		_release_at = null
	if main == null:
		return
	if device == -1:
		# A paired controller can appear seconds after launch without a connection signal (seen on the
		# Apple TV: none at start, the Switch Pro Controller after about 3 s), so keep looking for one.
		_discover_t -= delta
		if _discover_t <= 0.0:
			_discover_t = DISCOVER_EVERY
			var pads := Input.get_connected_joypads()
			if not pads.is_empty():
				_use(pads[0])
				if TvMode.active():
					_show(true)   # on a TV the controller is the only way to play: show the pointer at once
		return
	if _recentre != null:
		if is_instance_valid(_recentre) and _recentre.is_visible_in_tree():
			_move_cursor(_recentre.get_global_rect().get_center())
		_recentre = null
	if _tap_next != null:
		var t := _tap_next
		if not is_instance_valid(t) or not t.is_visible_in_tree() or _stale(t):
			_trace("tap dropped: the button is gone")
			_tap_next = null
		elif _tappable(t):
			_tap_next = null
			tap_at(t.get_global_rect().get_center())
		else:
			# The list has not settled at its new scroll yet (seen with real frame timing on the Mac):
			# scroll again and wait, a bounded number of frames, instead of tapping clipped space.
			_tap_tries += 1
			_scroll_of(t).ensure_control_visible(t)
			if _tap_tries >= TAP_TRIES:
				_trace("tap given up: %s still outside its list after %d frames" % [_name(t), _tap_tries])
				_tap_next = null
	var ls := deadzone(Vector2(_axes.get(JOY_AXIS_LEFT_X, 0.0), _axes.get(JOY_AXIS_LEFT_Y, 0.0)))
	var rs := deadzone(Vector2(_axes.get(JOY_AXIS_RIGHT_X, 0.0), _axes.get(JOY_AXIS_RIGHT_Y, 0.0)))
	var c: Node = main.controller
	var pointer := rs
	if is_modal():
		pointer += ls   # in a dialog or menu either stick moves the pointer; nobody walks behind it
		c.pad_move = Vector2.ZERO
		_ghost_goal = null
	elif c.ghost != null:
		c.pad_move = Vector2.ZERO
		if ls != Vector2.ZERO:
			if _ghost_goal == null:
				_ghost_goal = c.g_pos
			_ghost_goal += (main.rig.flat_right() * ls.x - main.rig.flat_forward() * ls.y) * GHOST_SPEED * delta
			c._move_ghost_to(_ghost_goal)
		else:
			_ghost_goal = null
	else:
		c.pad_move = ls
		_ghost_goal = null
	if pointer != Vector2.ZERO:
		_move_cursor(cursor + pointer * pointer.length() * CURSOR_SPEED * delta)
	if _dpad != -1:
		_dpad_t -= delta
		if _dpad_t <= 0.0:
			_dpad_t = REPEAT_EVERY
			_queue.append(role_of(_dpad))
	var todo := _queue.duplicate()
	_queue.clear()
	for a in todo:
		_trace("action %s (modal %s, menus %s)" % [a, is_modal(), main.menus.visible if main.menus else false])
		_run(a)
		acted.emit(a)
	_update_hints()


# ------------------------------------------------------------- state

## A dialog or the start menus are open: the world must not move behind them.
func is_modal() -> bool:
	if main.menus and main.menus.visible:
		return true
	for ch in main.hud._overlay.get_children():
		if not ch.is_queued_for_deletion():
			return true
	return false


func _area() -> Rect2:
	var vr := get_viewport().get_visible_rect()
	if main and main.hud:
		var r: Rect2 = main.hud.get_global_rect().intersection(vr)
		if r.has_area():
			return r
	return vr


# ------------------------------------------------------------- actions

func _run(a: String) -> void:
	var c: Node = main.controller
	var hud: Control = main.hud
	var modal := is_modal()
	match a:
		"confirm":
			tap_at(cursor)
		"back":
			_back()
		"context":
			if not modal and hud._context_btn.is_visible_in_tree():
				tap_control(hud._context_btn)
		"turn":
			if not modal and c.ghost != null:
				var b := _tool("Turn")
				if b:
					tap_control(b)
				else:
					c.turn_ghost()
		"place":
			if not modal and c.ghost != null:
				var b := _tool("Place here")
				if b:
					tap_control(b)
				else:
					c.confirm_ghost()
		"cam_left", "cam_right":
			if not modal:
				main.rig.rotate_step(-1 if a == "cam_left" else 1)
		"scroll_up", "scroll_down":
			_wheel(MOUSE_BUTTON_WHEEL_UP if a == "scroll_up" else MOUSE_BUTTON_WHEEL_DOWN)
		"up", "down", "left", "right":
			snap({"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}[a])


## B: the open dialog's own safe button, the menus' Back, cancel placing, or leave Decorate. Always through
## the real button when there is one, so the game does exactly what that button does.
func _back() -> void:
	var c: Node = main.controller
	var hud: Control = main.hud
	if main.menus and main.menus.visible:
		var b := _button_in(main.menus, ["Back"])
		if b:
			tap_control(b)
		return
	if is_modal():
		# Only a button known to be safe (Close, Cancel, Keep it, ...). A dialog without one is closed
		# without choosing any of its options: B never confirms, however the buttons are ordered.
		var b := _button_in(hud._overlay, BACK_LABELS)
		if b:
			tap_control(b)
		else:
			hud._close_overlay()
		return
	if c.ghost != null:
		var b := _tool("Cancel")
		if b:
			tap_control(b)
		else:
			c.cancel_ghost()
		return
	if c.mode == "decorate":
		if not c.bp.is_empty():
			c.cancel_blueprint()
		elif hud._decorate_btn.is_visible_in_tree():
			tap_control(hud._decorate_btn)


## The first visible, enabled button labelled one of `labels` (in that order), or null. Never any other.
func _button_in(root: Node, labels: Array) -> BaseButton:
	var buttons := root.find_children("*", "BaseButton", true, false).filter(func(b): return b.is_visible_in_tree() and not b.disabled and not _stale(b))
	for l in labels:
		for b in buttons:
			if b.get_meta("dialog_button", "") == l or (b is Button and b.text == l):
				return b
	return null


func _tool(label: String) -> BaseButton:
	for b in main.hud._tools.find_children("*", "Button", true, false):
		if b.text == label and b.is_visible_in_tree() and not b.disabled:
			return b
	return null


# ------------------------------------------------------------- pointer

func _move_cursor(p: Vector2) -> void:
	var r := get_viewport().get_visible_rect()
	p = p.clamp(r.position, r.end - Vector2.ONE)
	if p == cursor:
		return
	cursor = p
	_cursor_node.position = cursor
	var e := InputEventMouseMotion.new()
	e.position = _screen(cursor)
	e.global_position = e.position
	_inject(e)


## A finger tap where the pointer is: press now, release on the next frame.
func tap_at(p: Vector2) -> void:
	_move_cursor(p)
	if _release_at != null:
		_mouse_button(_release_at, MOUSE_BUTTON_LEFT, false)
	_mouse_button(cursor, MOUSE_BUTTON_LEFT, true)
	_release_at = cursor
	_trace("press at %s" % cursor)


## Taps a button like a finger would: when it sits in a list scrolled out of view (a clipped part
## cannot be tapped), the list scrolls to it first and the tap follows on the next frame.
func tap_control(c: Control) -> void:
	if not _tappable(c):
		_scroll_of(c).ensure_control_visible(c)
		_tap_next = c
		_tap_tries = 0
		_trace("scroll to %s %s" % [_name(c), c.get_global_rect()])
		return
	_trace("tap %s %s" % [_name(c), c.get_global_rect()])
	tap_at(c.get_global_rect().get_center())


## A finger could hit it now: its centre is inside the visible part of the list it scrolls in (if any).
func _tappable(c: Control) -> bool:
	var sc := _scroll_of(c)
	return sc == null or sc.get_global_rect().has_point(c.get_global_rect().get_center())


## Part of a screen that is being replaced (its node, or one above it, is queued for deletion).
func _stale(c: Node) -> bool:
	var n := c
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


func _name(c: Control) -> String:
	return "'%s'" % (c.text if c is Button and c.text != "" else str(c.name))


func _trace(text: String) -> void:
	if trace:
		print("PADTRACE f%d %s" % [Engine.get_process_frames(), text])


func _wheel(button: int) -> void:
	_mouse_button(cursor, button, true)
	_mouse_button(cursor, button, false)


func _mouse_button(p: Vector2, button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	e.position = _screen(p)
	e.global_position = e.position
	_inject(e)


func _screen(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _inject(e: InputEvent) -> void:
	e.set_meta("pad", true)
	Input.parse_input_event(e)


## D-pad: the pointer jumps to the nearest button in that direction (scrolling a list to show it).
func snap(dir: Vector2) -> Control:
	var best: Control = null
	var best_score := INF
	for t in targets():
		var center: Vector2 = t.get_global_rect().get_center()
		var d := center - cursor
		var along := d.dot(dir)
		if along < 8.0 or t.get_global_rect().has_point(cursor):
			continue
		var score := along + 2.5 * absf(d.cross(dir))
		if score < best_score:
			best_score = score
			best = t
	if best:
		var sc := _scroll_of(best)
		if sc:
			sc.ensure_control_visible(best)
			_recentre = best
		_move_cursor(best.get_global_rect().get_center())
	return best


## Everything a finger could tap right now: in the open dialog or menu only, else the HUD.
func targets() -> Array:
	var root: Node
	var skip: Node = null
	if main.menus and main.menus.visible:
		root = main.menus
	elif is_modal():
		root = main.hud._overlay
	else:
		root = main.hud
		skip = main.hud._overlay
	var vr := get_viewport().get_visible_rect()
	var out := []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x < 4.0 or c.size.y < 4.0 or _stale(c):
			continue
		if skip and skip.is_ancestor_of(c):
			continue
		var ok: bool = (c is BaseButton and not c.disabled) or (c is Range and not c is ScrollBar) \
			or (c is LineEdit and c.editable) or (c.mouse_filter == Control.MOUSE_FILTER_STOP and c.has_meta("photo_name"))
		if not ok:
			continue
		if not vr.has_point(c.get_global_rect().get_center()) and _scroll_of(c) == null:
			continue
		out.append(c)
	return out


func _scroll_of(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	return p as ScrollContainer


# ------------------------------------------------------------- hints

func hint_parts() -> Array:
	var c: Node = main.controller
	var ok := label_of(confirm_button())
	var back := label_of(back_button())
	var lr := label_of(JOY_BUTTON_LEFT_SHOULDER) + " " + label_of(JOY_BUTTON_RIGHT_SHOULDER)
	if is_modal():
		return [[ok, "Select"], [back, "Back"], [tr("D-pad"), "Jump to buttons"]]
	if c.ghost != null:
		return [[tr("Left stick"), "Move"], [label_of(JOY_BUTTON_X), "Turn"], [label_of(JOY_BUTTON_START), "Place here"], [back, "Cancel"]]
	var parts := [[ok, "Select"]]
	if c.mode == "decorate":
		parts.append([back, "Done"])
	elif main.hud._context_btn.is_visible_in_tree():
		parts.append([label_of(JOY_BUTTON_Y), str(main.hud._context_btn.text)])
	parts.append([tr("Right stick"), "Pointer"])
	parts.append([lr, "Turn camera"])
	return parts


func _update_hints() -> void:
	if not shown:
		return
	var text := "    ".join(hint_parts().map(func(p): return "%s  %s" % [p[0], tr(p[1])]))
	var changed := text != _hint_text
	if changed:
		_hint_text = text
		_hint_label.text = text
		_hint_panel.reset_size()
	var now := Time.get_ticks_msec()
	if changed or now >= _place_at:
		_place_at = now + 200   # what is on screen moves; the place is chosen again five times a second
		_place_hints()


## Inside the safe area, covering neither a button nor readable text (the town status, a toast, a dialog's
## or a panel's labels). It tries every row (the lower half from the bottom up, then the upper half from the
## top down), centred, then left and right; if nothing is free it takes the place covering no button and
## the least text.
func _place_hints() -> void:
	var area := _area()
	var s := _hint_panel.get_combined_minimum_size()
	var buttons: Array = targets().map(func(t): return t.get_global_rect())
	var texts := readable_rects()
	var xs := [area.get_center().x - s.x / 2.0, area.position.x + 8.0, area.end.x - s.x - 8.0]
	# Every row of the safe area: the lower half from the bottom up, then the upper half from the top down.
	var ys := []
	var mid := area.get_center().y - s.y / 2.0
	var row := area.end.y - s.y - 8.0
	while row >= mid:
		ys.append(row)
		row -= 24.0
	row = area.position.y + 8.0
	while row < mid:
		ys.append(row)
		row += 24.0
	var best := Vector2(xs[0], ys[0])
	var best_score := INF
	for y in ys:
		for x in xs:
			var r := Rect2(Vector2(x, y), s)
			if not area.encloses(r):
				continue
			var score := 0.0
			for b in buttons:
				if b.intersects(r):
					score += 1000000.0
			for t in texts:
				if t.intersects(r):
					score += t.intersection(r).get_area()
			if score == 0.0:
				_hint_panel.position = r.position
				return
			if score < best_score:
				best_score = score
				best = r.position
	_hint_panel.position = best


## Visible text a child reads, where the hints must not go: labels of the open dialog or menu, or of the
## HUD (not the world's name tags), each cut to the list it scrolls in.
func readable_rects() -> Array:
	var roots := []
	if main.menus and main.menus.visible:
		roots = [main.menus]
	elif is_modal():
		roots = [main.hud._overlay]
	else:
		roots = [main.hud]
	var skip: Array = [main.hud._tag_layer]
	if not is_modal():
		skip.append(main.hud._overlay)
	var out := []
	for root in roots:
		for n in root.find_children("*", "Control", true, false):
			if not (n is Label or n is RichTextLabel):
				continue
			var l := n as Control
			if not l.is_visible_in_tree() or str(l.get("text")).strip_edges() == "" or _alpha(l) < 0.05:
				continue
			if skip.any(func(k): return k != null and k.is_ancestor_of(l)):
				continue
			var r := l.get_global_rect()
			var sc := _scroll_of(l)
			if sc:
				r = r.intersection(sc.get_global_rect())
			if r.has_area():
				out.append(r)
	return out


func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a if n == c else (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


func hint_rect() -> Rect2:
	return Rect2(_hint_panel.position, _hint_panel.get_combined_minimum_size())


## A clear pointer: a white arrow with a dark outline and a soft ring, drawn above everything.
class _Pointer extends Control:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.85, 0.35, 0.28))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.25, 0.2, 0.15, 0.85), 3.0)
		var tip := PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(14, 35), Vector2(19, 32), Vector2(13, 21), Vector2(23, 21)])
		draw_colored_polygon(tip, Color.WHITE)
		draw_polyline(tip + PackedVector2Array([tip[0]]), Color(0.2, 0.15, 0.1), 2.5)
