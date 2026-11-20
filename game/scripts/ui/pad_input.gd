## Game controller layer (atv-r20-controller, design/tv-controller.md). One controller plays the whole game
## without touch or mouse:
##   left stick   walk (play), move the thing being placed (decorate), or move the pointer in a dialog
##   right stick  move the pointer
##   A (confirm)  tap where the pointer is: the real button or the real world tap, exactly like a finger
##   B (back)     the dialog's own Close/Cancel/Back button, cancel placing, leave Decorate
##   X / Y        the context action (Sit, Go in, ...) / turn the thing being placed
##   L / R        turn the camera; ZL / ZR scroll a list or zoom; + places; the D-pad jumps between buttons
## In Thousand Town (design/thousand-town.md section 7) the right stick orbits the follow camera instead of moving
## the pointer (outside dialogs), and the D-pad still jumps between the HUD's buttons, the time buttons included.
## A Nintendo controller is positional in Godot (SDL): its A is on the right (Godot JOY_BUTTON_B) and its B at
## the bottom (Godot JOY_BUTTON_A), so the confirm and back buttons follow the label, not the position.
## Button presses only queue an action; actions run in _process, never inside input handling. Each joypad
## event is consumed here, so nothing else (GUI focus, ui_* actions) can act on it a second time.
extends CanvasLayer

const UI := preload("res://scripts/ui/ui_kit.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const PlacesP := preload("res://scripts/core/places.gd")
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
signal controller_changed(connected: bool, info: Dictionary)   # tv-diag: a controller came or went (the bench logs it)

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
var _tap_rect := Rect2()          # where that button was a frame ago: it is tapped only once it holds still
var _tap_watch: BaseButton = null # the button a tap was just sent to
var _tap_heard := false           # ... and whether it answered with its pressed signal
var _tap_check := 0               # the frame by which it must have answered
var _tap_again := 0               # taps repeated for the same press because the button did not answer
const TAP_TRIES := 10             # frames to wait for a scrolled list to settle before giving up
const TAP_CHECK_AFTER := 4        # frames after a tap by which its button must have answered
const TAP_AGAIN := 2              # at most this many repeats of a tap that did not arrive
## --pad-trace: one line per action, chosen button, tap point, press and release frame (diagnosis only;
## never the town address, invite or save content).
var trace := false
## tv-diag: controller counters for the benchmark's phase summaries (--city-bench), never a line per frame. They
## count what reached this layer: actions by role, trigger pulls, stick use. "origin_synthetic" counts events a test
## driver tagged where it made them (meta "synthetic"); "origin_untagged" counts all others, which is hardware or any
## source that did not tag itself: an InputEvent alone cannot prove where it came from.
var counts := {}
var _cursor_node: Control
## unified r7 (the Mac's real-window 1080p run: after a journey home the pointer was back on "Ride to Thousand Town" but
## the button showed no focus ring; the look had come from the GUI's mouse hover, which the fading travel card and the
## window's own mouse take over): the pad's selection is its own state, the enabled control under the pointer,
## recomputed every frame, and its focus ring (the theme's, UI.FOCUS_RING) is drawn by this layer, whatever the hover.
var selected: Control = null
var _ring: Control
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_text := ""
var _hint_area := Rect2()
var _hint_size := Vector2.ZERO
var _hint_buttons: Array = []
var _hint_texts: Array = []
var _hint_keep: Array = []
var _discover_t := 0.0


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
		JOY_BUTTON_BACK: return "time"   # unified r4: Thousand Town's time (- / Select / View / Share)
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
		JOY_BUTTON_BACK: return "-" if nin else "Select"
		JOY_BUTTON_LEFT_SHOULDER: return "L" if nin else "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "R" if nin else "RB"
	return "?"


## unified r4: the name printed on a trigger of this controller (ZL / ZR on a Nintendo pad, LT / RT otherwise).
func label_of_axis(axis: int) -> String:
	var nin := layout == "nintendo"
	match axis:
		JOY_AXIS_TRIGGER_LEFT: return "ZL" if nin else "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "ZR" if nin else "RT"
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
	# unified r7: the pad's own focus ring, drawn under the pointer over the selected control (see _select)
	_ring = _FocusRing.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_ring.name = "PadFocusRing"
	add_child(_ring)
	_cursor_node = _Pointer.new()
	_cursor_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_node.visible = false
	_cursor_node.name = "PadPointer"
	add_child(_cursor_node)
	# unified r6: the shared hint panel of every world (UI.hint_panel). This layer is outside the HUD and menus, so
	# the panel takes the game's shared theme itself: its font is switched per language (I18n.ui_font with the bundled
	# Chinese and Japanese fonts). Without it the hints fell back to Godot's own Latin font, and on the Apple TV
	# Japanese showed boxes for kanji.
	_hint_panel = UI.hint_panel()
	_hint_panel.name = "PadHints"
	_hint_panel.visible = false
	_hint_label = UI.hint_label()
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
	if trace:
		print("PADINFO %s" % JSON.stringify(controller_info()))


## tv-diag: the controller in use, as Godot reports it: name, GUID (a model mapping id, not a serial), the layout
## chosen and why, which printed letters confirm and go back, and the joy info Godot exposes (vendor and product ids).
## No user data. {"connected": false} without a controller.
func controller_info() -> Dictionary:
	var pads := Input.get_connected_joypads()
	if device == -1 or not pads.has(device):
		return {"connected": false, "count": pads.size()}
	var info := Input.get_joy_info(device)
	var keep := {}
	for k in ["vendor_id", "product_id", "raw_name"]:
		if info.has(k):
			keep[k] = info[k]
	return {"connected": true, "count": pads.size(), "name": Input.get_joy_name(device), "guid": Input.get_joy_guid(device),
		"layout": layout, "layout_forced": forced_layout != "", "swap_ab": swap_ab,
		"confirm": label_of(confirm_button()), "back": label_of(back_button()), "info": keep}


## tv-diag: the counters since the last call (then cleared).
func take_counts() -> Dictionary:
	var out := counts
	counts = {}
	return out


func _count(event: InputEvent, what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1
	var origin := "origin_synthetic" if event.has_meta("synthetic") else "origin_untagged"
	counts[origin] = int(counts.get(origin, 0)) + 1


func _on_joy(dev: int, connected: bool) -> void:
	if connected:
		if device == -1:
			_use(dev)
			_show(true)
			_toast("Controller connected")
		controller_changed.emit(true, controller_info())
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
		controller_changed.emit(false, controller_info())


## Drops everything held: no walking, no moving, no pressed tap, no queued action.
func _reset() -> void:
	_axes.clear()
	_queue.clear()
	_trig.clear()
	_dpad = -1
	_ghost_goal = null
	_recentre = null
	_tap_next = null
	_unwatch()
	_tap_again = 0
	if _release_at != null:
		_mouse_button(_release_at, MOUSE_BUTTON_LEFT, false)
		_release_at = null
	if main and main.controller:
		main.controller.pad_move = Vector2.ZERO


func _show(on: bool) -> void:
	shown = on
	_cursor_node.visible = on
	if not on:
		_ring.visible = false   # unified r7: no selection without the pointer
		selected = null
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
			if absf(event.axis_value) > DEADZONE and absf(float(_axes.get(event.axis, 0.0))) <= DEADZONE:
				_count(event, "stick_push" if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] else ("stick_right_push" if event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y] else "trigger_move"))
			_axes[event.axis] = event.axis_value
			if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
				var on: bool = _trig.get(event.axis, false)
				if not on and event.axis_value >= TRIGGER_ON:
					_trig[event.axis] = true
					_count(event, "zl" if event.axis == JOY_AXIS_TRIGGER_LEFT else "zr")
					_queue.append("scroll_up" if event.axis == JOY_AXIS_TRIGGER_LEFT else "scroll_down")
				elif on and event.axis_value <= TRIGGER_OFF:
					_trig[event.axis] = false
		elif event.pressed:
			var r := role_of(event.button_index)
			_count(event, r if r != "" else "button_%d" % event.button_index)
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
	_check_tap()
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
	_track_focus()   # unified r6
	if _recentre != null:
		if is_instance_valid(_recentre) and _recentre.is_visible_in_tree():
			_move_cursor(_recentre.get_global_rect().get_center())
		_recentre = null
	if _tap_next != null:
		var t := _tap_next
		if not is_instance_valid(t) or not t.is_visible_in_tree() or _stale(t):
			_trace("tap dropped: the button is gone")
			_tap_next = null
		elif _tappable(t) and t.get_global_rect() == _tap_rect:
			_tap_next = null
			_watch(t)
			tap_at(t.get_global_rect().get_center())
		elif _tappable(t):
			# In view, but it moved since the last frame: the list is still settling. A tap sent now
			# could land where the button no longer is by the time it arrives.
			_tap_rect = t.get_global_rect()
			_tap_tries += 1
			if _tap_tries >= TAP_TRIES:
				_trace("tap given up: %s did not hold still for %d frames" % [_name(t), _tap_tries])
				_tap_next = null
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
	if not is_modal() and c != null and str(c.get("space")) == "thousand" and main.rig != null and bool(main.rig.get("on_thousand")):
		main.rig.thousand_orbit_stick(rs, delta)   # the right stick orbits around the child
		pointer = Vector2.ZERO
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
	elif bool(c.get("city_looking")):
		c.pad_move = Vector2.ZERO   # tv-diag r2 (audit finding 5): while looking at a place the child stays
		_ghost_goal = null
	else:
		c.pad_move = ls
		_ghost_goal = null
	if pointer != Vector2.ZERO:
		_move_cursor(cursor + pointer * pointer.length() * CURSOR_SPEED * delta)
	if _dpad != -1:
		# thousand-town loop tour: one long frame (a hitch, or seconds a frame on a software renderer) must not turn
		# a single press into a repeat in the same frame, so the hold is counted at most 0.1 s a frame
		_dpad_t -= minf(delta, 0.1)
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
	if c != null and str(c.get("journey_to")) != "":
		return   # the zoo journey card is up: the controller acts on nothing (zoo design 16.1)
	var modal := is_modal()
	match a:
		"confirm":
			var under := _target_at(cursor)
			if under != null and not modal and String(under.name) == "LeaveTown" and hud.has_method("confirm_leave"):
				hud.confirm_leave()   # tv-diag r2 (audit finding 2): A on Leave town asks first (B: Not now)
				return
			tap_at(cursor)
			if under != null:
				if not modal:
					_kept[_map_now()] = under   # unified r6: where the pointer comes back to on this map
				_follow_after_tap(under)
		"back":
			_back()
		"context":
			if not modal and hud._context_btn.is_visible_in_tree():
				_shortcut_tap(hud._context_btn)
		"turn":
			if not modal and c.ghost != null:
				var b := _tool("Turn")
				if b:
					tap_control(b)
				else:
					c.turn_ghost()
			elif not modal and hud._context_alt_btn.is_visible_in_tree():
				_shortcut_tap(hud._context_alt_btn)   # in a cart: Get off
		"place":
			if not modal and hud._workshop_btn.is_visible_in_tree():
				tap_control(hud._workshop_btn)
			elif not modal and c.ghost != null:
				var b := _tool("Place here")
				if b:
					tap_control(b)
				else:
					c.confirm_ghost()
		"time":
			# unified r4: in Thousand Town, the next time of day (Day, Dusk, Night, Auto), as the glass buttons
			if not modal and str(c.get("space")) == "thousand" and hud.has_method("cycle_time"):
				hud.cycle_time()
		"cam_left", "cam_right":
			if not modal:
				main.rig.rotate_step(-1 if a == "cam_left" else 1)
		"scroll_up", "scroll_down":
			if not modal and main.rig and bool(main.rig.get("on_city")):
				main.rig.city_step_zoom(1 if a == "scroll_up" else -1)   # tv-diag r2: ZL one level closer, ZR farther
			else:
				_wheel(MOUSE_BUTTON_WHEEL_UP if a == "scroll_up" else MOUSE_BUTTON_WHEEL_DOWN)
		"up", "down", "left", "right":
			if a in ["left", "right"] and not is_modal() and bool(main.controller.get("city_looking")):
				main.controller.city_look_step(-1 if a == "left" else 1)   # city r2: Look steps through the places
			else:
				snap({"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}[a])


## tv-diag r2: the control the pointer is on (the targets a finger could tap), or null.
func _target_at(p: Vector2) -> Control:
	for t in targets():
		if (t as Control).get_global_rect().has_point(p):
			return t
	return null


## tv-diag r2 (audit finding 3): after A on a control that then moves (Look around: Pause appears and the
## column re-centres), the pointer follows it, so a second A reaches the same control.
func _follow_after_tap(c: Control) -> void:
	var at := cursor
	# The column re-centres over a few frames (layout, then the HUD's own update), so watch for a short while
	# (FOLLOW_FRAMES) rather than a fixed two frames: a fixed wait passed in one run and missed in the next.
	for i in FOLLOW_FRAMES:
		await get_tree().process_frame
		# Only while nothing else moved the pointer (the stick, the D-pad, a test driver).
		if cursor != at or not is_instance_valid(c) or not c.is_visible_in_tree():
			return
		if not c.get_global_rect().has_point(cursor):
			_move_cursor(c.get_global_rect().get_center())
			return

const FOLLOW_FRAMES := 20

## unified r6 (Apple TV feedback): the pointer per map. A then the control under the pointer is remembered for the
## map it was pressed in (the tram stop's "Ride to Thousand Town"); arriving back in the town puts the pointer on that
## control again once it shows (the stop's journeys appear a moment after the arrival); arriving elsewhere puts it on
## the action button if one shows. The player's own pointer moves always win: a move meanwhile cancels it.
var _kept := {}              # map -> the Control last pressed there
var _focus_map := ""
var _focus_want: Control = null
var _focus_until := 0.0
var _focus_from := Vector2.INF
var _hud_was_on := true
var _focus_frame := 0
const FOCUS_WAIT := 4.0      # seconds an arrival waits for its remembered control to show


func _map_now() -> String:
	var c: Node = main.controller if main else null
	return PlacesP.map_of(str(c.get("space"))) if c != null else ""


func _track_focus() -> void:
	var c: Node = main.controller
	# The HUD back after a local trip (the Workshop, the reef hide it): the control under the pointer had lost its
	# hover (focused) look, as nothing moved; one motion where the pointer is gives it back.
	# (The layer itself is paused during those trips, so a gap in its frames counts as well.)
	var hud_on: bool = main.hud != null and main.hud.is_visible_in_tree()
	var frame := Engine.get_process_frames()
	if hud_on and (not _hud_was_on or frame - _focus_frame > 2):
		_poke_hover.call_deferred()
	_hud_was_on = hud_on
	_focus_frame = frame
	if c == null or str(c.get("journey_to")) != "":
		return
	var m := _map_now()
	if m != _focus_map:
		var first := _focus_map == ""
		_focus_map = m
		if not first:
			# Back home (the town) to the control that left it; elsewhere to the map's action button, if any.
			var kept: Variant = _kept.get(m) if m == PlacesP.TOWN else null
			_focus_want = kept if kept is Control and is_instance_valid(kept) else main.hud.get("_context_btn")
			_focus_until = Time.get_ticks_msec() / 1000.0 + FOCUS_WAIT
			_focus_from = cursor
	if _focus_want == null:
		return
	if cursor != _focus_from or Time.get_ticks_msec() / 1000.0 > _focus_until or not is_instance_valid(_focus_want):
		_focus_want = null   # the player moved the pointer, or the control did not come
		return
	if not is_modal() and targets().has(_focus_want):
		_move_cursor(_focus_want.get_global_rect().get_center())
		_poke_hover()
		_trace("focus restored on %s" % _name(_focus_want))
		_focus_want = null


## A mouse motion where the pointer is, so the control under it shows its focused (hover) look again.
func _poke_hover() -> void:
	var e := InputEventMouseMotion.new()
	e.position = _screen(cursor)
	e.global_position = e.position
	_inject(e)


## unified r6: the control the pointer was put on by the last arrival (tests), or null while it waits.
func focus_waiting() -> bool:
	return _focus_want != null


## tv-diag r2 (audit finding 4): Y and X act through their button without leaving the pointer on it (after X
## Sit down, the next A stood the child up). The pointer returns where it was once the tap is released.
func _shortcut_tap(c: Control) -> void:
	var keep := cursor
	tap_control(c)
	var tapped_at := cursor
	await get_tree().process_frame
	await get_tree().process_frame
	# Not when the shortcut opened a card or dialog (its buttons are what the pointer is for now: the puzzle
	# chest's X opens its card), and not when something else moved the pointer meanwhile.
	if is_modal() or (main.menus and main.menus.visible) or cursor != tapped_at:
		return
	_move_cursor(keep)


## B: the open dialog's own safe button, the menus' Back, cancel placing, or leave Decorate. Always through
## the real button when there is one, so the game does exactly what that button does.
func _back() -> void:
	var c: Node = main.controller
	var hud: Control = main.hud
	if bool(c.get("city_looking")) and not is_modal() and not (main.menus and main.menus.visible):
		c.set_city_look(false)   # city r2: B leaves Look, gliding back to the overview
		return
	if bool(c.get("thousand_looking")) and not is_modal() and not (main.menus and main.menus.visible):
		c.set_thousand_look(false)   # thousand-town: B flies back behind the child
		return
	var tp: Node = c.get("thousand_play")
	if str(c.get("space")) == "thousand" and tp != null and not is_modal() and not (main.menus and main.menus.visible) and tp.back():
		return   # thousand-town: B closes the resident card, or ends following, waiting for the bus or watching
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
	if str(c.get("look_id")) != "":
		c.end_look()   # Look at a zoo animal ends on B (zoo design 11.1)
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
## The tap is checked afterwards: a button that did not answer with its pressed signal (the Mac's TV
## tour of first-steps r1 once lost B on the character screen, same coordinates as in a run that
## passed; the cause was not established) is tapped again, at most TAP_AGAIN times, never a button
## that did answer.
func tap_control(c: Control, again := false) -> void:
	if not again:
		_tap_again = 0
	if not _tappable(c):
		_scroll_of(c).ensure_control_visible(c)
		_tap_next = c
		_tap_tries = 0
		_tap_rect = Rect2()
		_trace("scroll to %s %s" % [_name(c), c.get_global_rect()])
		return
	_trace("tap %s %s" % [_name(c), c.get_global_rect()])
	_watch(c)
	tap_at(c.get_global_rect().get_center())


func _watch(c: Control) -> void:
	_unwatch()
	if c is BaseButton:
		_tap_watch = c
		_tap_heard = false
		_tap_check = Engine.get_process_frames() + TAP_CHECK_AFTER
		(c as BaseButton).pressed.connect(_on_tap_heard)


func _unwatch() -> void:
	if _tap_watch != null and is_instance_valid(_tap_watch) and _tap_watch.pressed.is_connected(_on_tap_heard):
		_tap_watch.pressed.disconnect(_on_tap_heard)
	_tap_watch = null


func _on_tap_heard() -> void:
	_tap_heard = true


## A few frames after a tap: if its button is still there and never answered, tap it again.
func _check_tap() -> void:
	if _tap_watch == null or Engine.get_process_frames() < _tap_check:
		return
	var t := _tap_watch
	var heard := _tap_heard
	_unwatch()
	if heard or not is_instance_valid(t) or not t.is_visible_in_tree() or t.disabled or _stale(t):
		_tap_again = 0
		return
	if _tap_again >= TAP_AGAIN:
		_trace("tap not received by %s after %d repeats: given up" % [_name(t), _tap_again])
		_tap_again = 0
		return
	_tap_again += 1
	_trace("tap not received by %s: again (%d)" % [_name(t), _tap_again])
	tap_control(t, true)


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
	# tv-diag r2 (audit finding 9): prefer targets within 60 degrees of the pressed direction (some jumps went
	# almost sideways, e.g. Rain left -> Language); only when none lies in that cone, the nearest as before.
	for pass_i in 2:
		for t in targets():
			var center: Vector2 = t.get_global_rect().get_center()
			var d := center - cursor
			var along := d.dot(dir)
			if along < 8.0 or t.get_global_rect().has_point(cursor):
				continue
			var side := absf(d.cross(dir))
			if pass_i == 0 and side > along * 1.7320508:
				continue
			var score := along + 2.5 * side
			if score < best_score:
				best_score = score
				best = t
		if best:
			break
	if best:
		var sc := _scroll_of(best)
		if sc:
			sc.ensure_control_visible(best)
			_recentre = best
		_move_cursor(best.get_global_rect().get_center())
	return best


## Everything a finger could tap right now: in the open dialog or menu only, else the HUD.
func targets(include_disabled := false) -> Array:
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
		# Unseen is not a target: a side menu stepped aside for a held thing, or the tools in the frames
		# they take their place (first-steps r10; hud.gd _keep_menus_clear, _set_tools_unseen).
		if _alpha(c) < 0.05:
			continue
		if skip and skip.is_ancestor_of(c):
			continue
		# tv-diag r2 (audit finding 1): the floating name tags over the world are not D-pad stops. They move with
		# the camera, so a D-pad press could land on "Zoo tram" and one A rode to the zoo. The pointer (right
		# stick) still reaches them; the tram stop is also the context button when the child is there.
		if main.hud.get("_tag_layer") and (main.hud._tag_layer as Node).is_ancestor_of(c):
			continue
		var ok: bool = (c is BaseButton and (include_disabled or not c.disabled)) or (c is Range and not c is ScrollBar) \
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
	var lr := UI.glyphs([label_of(JOY_BUTTON_LEFT_SHOULDER), label_of(JOY_BUTTON_RIGHT_SHOULDER)])   # unified r6: LB / RB, as the other worlds
	if is_modal():
		return [[ok, "Select"], [back, "Back"], [tr("D-pad"), "Jump to buttons"]]
	if c.ghost != null:
		return [[tr("Left stick"), "Move"], [label_of(JOY_BUTTON_X), "Turn"], [label_of(JOY_BUTTON_START), "Place here"], [back, "Cancel"]]
	if main.hud._workshop_btn.is_visible_in_tree():
		return [[label_of(JOY_BUTTON_START),"Roller Coaster Workshop"],[label_of(JOY_BUTTON_Y),str(main.hud._context_btn.text)],[ok,"Select"]]
	var parts := [[ok, "Select"]]
	if bool(c.get("city_looking")):
		parts.append([tr("D-pad"), "Look around"])   # tv-diag r2 (audit finding 6): left / right step through the places
		parts.append([back, "Stop looking"])
		parts.append([lr, "Turn camera"])
		return parts
	if c.mode == "decorate":
		parts.append([back, "Done"])
	elif main.hud._context_btn.is_visible_in_tree():
		parts.append([label_of(JOY_BUTTON_Y), str(main.hud._context_btn.text)])
		if main.hud._context_alt_btn.is_visible_in_tree():
			parts.append([label_of(JOY_BUTTON_X), str(main.hud._context_alt_btn.text)])
	if str(c.get("space")) == "thousand":
		# unified r4 (Apple TV feedback): concise and contextual. Only what applies now, at most five: the actions
		# offered (Y, X), Back when something can be ended, the camera, and the time button. "Select" (A) only when
		# the pointer rests on a button; the D-pad's jumping is shown by the pointer itself.
		parts = []
		var under := _target_at(cursor)
		if under != null:
			parts.append([ok, "Select"])
		var tp: Node = c.get("thousand_play")
		if main.hud._context_btn.is_visible_in_tree():
			parts.append([label_of(JOY_BUTTON_Y), str(main.hud._context_btn.text)])
			if main.hud._context_alt_btn.is_visible_in_tree():
				parts.append([label_of(JOY_BUTTON_X), str(main.hud._context_alt_btn.text)])
		if tp != null and (bool(tp.get("card_open")) or str(tp.get("state")) in ["follow", "follow_inside", "wait_bus", "watch", "wheel_wait"]):
			parts.append([back, "Back"])   # closes the card, ends following, waiting or watching
		if tp != null and str(tp.get("state")) == "wheel":
			parts.append([tr("Right stick"), "Look around"])   # the cabin's view turns (camera_rig t_watch_free)
		else:
			parts.append([tr("Right stick"), "Turn camera"])
		parts.append([label_of(JOY_BUTTON_BACK), "Time"])
		return parts.slice(0, 5)
	else:
		parts.append([tr("Right stick"), "Pointer"])
		parts.append([lr, "Turn camera"])
	return parts


func _update_hints() -> void:
	if not shown:
		return
	var text := UI.HINT_SEP.join(hint_parts().map(func(p): return UI.hint_part(str(p[0]), tr(p[1]))))
	var changed := text != _hint_text
	if changed:
		_hint_text = text
		_hint_label.text = text
		_hint_panel.reset_size()
	# A tab switch or scroll can move cards without changing the hint text. Updating only every
	# 200 ms left the old hint position over new cards for several rendered frames.
	var ts := targets(true)
	_select(ts)
	_place_hints(ts)


## unified r7: the selection (the enabled target under the pointer, the smallest if they nest) and its ring. Nothing is
## selected while a journey's card is up or the pointer is over no control.
func _select(ts: Array) -> void:
	var best: Control = null
	var c: Node = main.controller
	if c == null or str(c.get("journey_to")) == "":
		for t: Control in ts:
			if t is BaseButton and (t as BaseButton).disabled:
				continue
			var r := _visible_rect(t)
			if r.has_point(cursor) and (best == null or r.get_area() < _visible_rect(best).get_area()):
				best = t
	selected = best
	if best == null:
		_ring.visible = false
		return
	var r := _visible_rect(best)
	var radius := 16.0
	var sb := best.get_theme_stylebox("normal") if best is Button else null
	if sb is StyleBoxFlat:
		radius = float((sb as StyleBoxFlat).corner_radius_top_left)
	if not _ring.visible or _ring.position != r.position or _ring.size != r.size or float(_ring.get_meta("radius", -1.0)) != radius:
		_ring.position = r.position
		_ring.size = r.size
		_ring.set_meta("radius", radius)
		_ring.queue_redraw()
	_ring.visible = true


## unified r7: the control the pad has selected (tests, and the hint's "Select"), or null.
func selection() -> Control:
	return selected


## Inside the safe area, covering neither a button nor readable text (the town status, a toast, a dialog's
## or a panel's labels). It tries every row (the lower half from the bottom up, then the upper half from the
## top down), centred, then left and right; if nothing is free it takes the place covering no button and
## the least text. While a thing is held the hints also keep off the thing and off the player's own
## child (the Mac's r7 picture at the TV layout: the hints lay on the child's name).
func _place_hints(ts: Array = []) -> void:
	var area := _area()
	var s := _hint_panel.get_combined_minimum_size()
	# Disabled controls still have names/icons a child needs to read (for example Undo).
	# Navigation keeps offscreen scroll targets, but hint placement only protects their visible part.
	if ts.is_empty():
		ts = targets(true)
	var buttons: Array = ts.map(func(t): return _visible_rect(t)).filter(func(r): return r.has_area())
	var texts := readable_rects()
	# The held thing and the child, as the HUD judges them for its tools (where the camera will rest); the
	# thing's box takes in its own meshes' boxes, as for the side menus (first-steps r11: a menu that steps
	# aside for the meshes must not leave room for the hints on them).
	var keep: Array = []
	if main.controller != null and main.controller.ghost != null and not is_modal():
		var boxes: Array = main.hud.placement_rects()
		var meshes: Rect2 = main.hud.ghost_mesh_rect()
		if meshes.has_area():
			boxes[0] = (boxes[0] as Rect2).merge(meshes) if (boxes[0] as Rect2).has_area() else meshes
		for r in boxes:
			if (r as Rect2).has_area():
				var g: Rect2 = (r as Rect2).grow(8.0)
				keep.append(Rect2(g.position.snapped(Vector2(4, 4)), g.size.snapped(Vector2(4, 4))))
	# Observe geometry every frame, but only search for a new position when something changed.
	# This keeps fast tab/scroll transitions safe without repeating the row search on a still screen.
	if area == _hint_area and s == _hint_size and buttons == _hint_buttons and texts == _hint_texts and keep == _hint_keep:
		return
	_hint_keep = keep
	_hint_area = area
	_hint_size = s
	_hint_buttons = buttons
	_hint_texts = texts
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
			for k in keep:
				if k.intersects(r):
					score += 500000.0   # rather a little text than the child or the thing; never a button
			if score == 0.0:
				_hint_panel.position = r.position
				return
			if score < best_score:
				best_score = score
				best = r.position
	_hint_panel.position = best


## The on-screen part of a control, clipped by every ancestor that clips its children.
func _visible_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect().intersection(get_viewport().get_visible_rect())
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents:
			rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect


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
## unified r7: the focus ring of the pad's selection, the theme's (UI.FOCUS_RING, UI.FOCUS_W) on the control's own corners.
class _FocusRing extends Control:
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(int(get_meta("radius", 16.0)))
		sb.set_border_width_all(UI.FOCUS_W)
		sb.border_color = UI.FOCUS_RING
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


class _Pointer extends Control:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.85, 0.35, 0.28))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.25, 0.2, 0.15, 0.85), 3.0)
		var tip := PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(14, 35), Vector2(19, 32), Vector2(13, 21), Vector2(23, 21)])
		draw_colored_polygon(tip, Color.WHITE)
		draw_polyline(tip + PackedVector2Array([tip[0]]), Color(0.2, 0.15, 0.1), 2.5)
