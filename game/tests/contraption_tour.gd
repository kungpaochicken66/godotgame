## Contraptions and a living town through the real UI (design/contraptions-and-town-life.md).
## Touch (default): the Contraptions toy box tab and its idea line, a Big button placed from it, the
## dotted links in Decorate, a tap on the button and Press, the chain (lamp, music box, pinwheel) one
## hop at a time, a step pad walked onto and its bubbles, Wooly coming for the music with its line and
## ring and its card, Pip looking at a new thing, Reduce motion, a room whose lights a button switches
## on by day, and the new texts in each language.
## Controller (--tv): the same things with simulated controller events only: the pointer and A on the
## real buttons, X for Press, the left stick to walk onto the step pad, + to place.
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/contraption_tour.gd \
##                   --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/contraption_tour.gd \
##                   --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv --locales=en,ja
## Logic only, no renderer (EC2): add --headless before --path, and --no-shots --window=WxH after --.
## Friends are not needed: net_test.py --contraptions covers real clients. At most 24 screenshots (ten
## cases and two per language).
## r2 (after the Mac's first rendered run): every screenshot that is evidence for something now asserts,
## from the camera and the HUD's own rectangles, that the thing is on screen and not under a control,
## and waits for an earlier message to fade. No game file changed.
## The animals are parked while the chain is timed (one walking over the step pad would switch a lamp
## at a random moment); the living-town cases put Wooly and Pip where the case needs them and let
## the real brain do the rest.
extends "res://tests/tv_tour.gd"

const Contraptions := preload("res://scripts/core/contraptions.gd")
const TownLife := preload("res://scripts/core/town_life.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const DecoMotion := preload("res://scripts/world/deco_motion.gd")

const SAVE := "user://contraption_tour_town.json"
## Offsets from the button: a row to the east, and a step pad with its bubble machine to the south.
const ROW := [["lamp_post", Vector2(1.5, 0.0)], ["music_box", Vector2(3.0, 0.0)], ["pinwheel", Vector2(4.5, 0.0)]]
const PAD_AT := Vector2(0.0, 3.2)
const BUBBLES_AT := Vector2(1.5, 3.2)

var tv := false
var ids := {}
var base := Vector2.ZERO
var _case_ok := false
var _stick_up := Vector2.ZERO
## Diagnosis (r2, after a Press by X did nothing in one rendered run on the 4.8 Metal build): what
## each layer saw, so a failure names its layer instead of only its symptom.
var _real_mouse := 0          # mouse or touch events that did not come from the controller layer or this driver
var _real_mouse_first := ""
var _own_taps := 0            # frames in which this driver itself sends finger taps (touch mode)
var _ctx_presses := 0         # times the real action button reported "pressed"
var _replies := []            # every reply from the authority: [request id, result]


## Independent regression oracle for the reported TV overlap: inspect the actual card row and
## disabled Undo, not PadInput.targets(), which deliberately omits disabled navigation targets.
func toybox_hints_clear(what: String) -> void:
	if not tv:
		return
	var hud: Control = main.hud
	var hint: Rect2 = pad.hint_rect()
	var clip: Rect2 = hud._card_scroll.get_global_rect().intersection(get_viewport().get_visible_rect())
	var covered := []
	var visible := 0
	for card in hud._cards.get_children():
		if not card.is_visible_in_tree():
			continue
		var part: Rect2 = card.get_global_rect().intersection(clip)
		if not part.has_area():
			continue
		visible += 1
		if part.intersects(hint):
			covered.append(str(card.get_meta("kind", card.name)))
	check(pad._hint_panel.visible and pad._area().encloses(hint), "%s: hints are visible inside the safe area" % what)
	check(visible >= 2, "%s: the visible toy-box cards are checked" % what)
	check(covered.is_empty(), "%s: hints cover no visible toy-box card (%s)" % [what, covered])
	check(not hud._undo_btn.is_visible_in_tree() or not hud._undo_btn.get_global_rect().intersects(hint), "%s: hints leave Undo readable even when disabled" % what)
	var scrollbar: ScrollBar = hud._card_scroll.get_h_scroll_bar()
	check(not scrollbar.is_visible_in_tree() or not scrollbar.get_global_rect().intersects(hint), "%s: hints leave the card scrollbar clear" % what)


func shot(name: String) -> void:
	if _n >= 24 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/contraption_%s_%02d_%s.png" % [shots, tag, _n, name])


## Counts pointer events from outside. The controller layer marks the events it sends ("pad") and this
## driver marks its own taps and drags ("tour", pets_tour.gd); any other mouse or touch event came from
## the machine's own mouse or trackpad (or a tool moving it). One such movement between an injected
## press and its release makes a button drop the press: the button sees the pointer leave it. Until
## first-steps r7 this was counted in controller runs only. (The Mac's six-language phone run of r7:
## four tab taps in a row left the tab unchanged, with nothing in the log to say why. Shown headless on
## EC2: one outside movement between press and release gives exactly that. Not shown: that this is
## what happened there. Now every run counts, and a tap that misses says what it saw.)
func _input(event: InputEvent) -> void:
	if (event is InputEventMouse or event is InputEventScreenTouch) and not event.has_meta("pad") and not event.has_meta("tour"):
		_real_mouse += 1
		if _real_mouse_first == "":
			_real_mouse_first = "%s at %s, frame %d" % [event.get_class(), (event as InputEventMouse).position.round() if event is InputEventMouse else "?", Engine.get_process_frames()]
		if _real_mouse <= 20:
			print("DIAG outside pointer event %d: %s at %s, frame %d, %d ms" % [_real_mouse, event.get_class(), (event as InputEventMouse).position.round() if event is InputEventMouse else "?", Engine.get_process_frames(), Time.get_ticks_msec()])
			# Where it came from, for diagnosis only (first-steps r9: the Mac's r8 runs met untagged motion
			# outside the window, source unknown). The count above is unchanged by this line. Device -1 is
			# the engine's own emulation (touch from mouse or mouse from touch); the global position is the
			# window's, as the system reports it; relative and velocity tell a moving pointer from a still one.
			var mm := event as InputEventMouse
			print("DIAG outside pointer event %d source: device %d; global %s; relative %s; velocity %s; buttons %d; system pointer %s; window at %s size %s focused %s; meta %s" % [_real_mouse, event.device,
				mm.global_position.round() if mm else "?", (event as InputEventMouseMotion).relative if event is InputEventMouseMotion else "-",
				(event as InputEventMouseMotion).velocity.round() if event is InputEventMouseMotion else "-", mm.button_mask if mm else 0,
				DisplayServer.mouse_get_position(), get_window().position, get_window().size, get_window().has_focus(), str(event.get_meta_list())])


func case_ended(what: String) -> void:
	check(_case_ok, "the %s case ran to its end" % what)
	_case_ok = false


## Presses a real button: a finger tap, or the pointer and A on a controller.
func act(b: Control, what: String) -> void:
	if b == null:
		check(false, "%s is there to press" % what)
		return
	if tv:
		await choose(b, what)
	else:
		await press(b)


## Uses the context action once it offers `type`: the action button, or X on a controller.
func do_context(type: String, timeout := 8.0) -> bool:
	var c: Node = main.controller
	if not await until(func(): return c._ctx.get("type", "") == type and main.hud._context_btn.is_visible_in_tree(), timeout):
		return false
	var presses0 := _ctx_presses
	var replies0 := _replies.size()
	var mouse0 := _real_mouse
	var f0 := Engine.get_process_frames()
	if tv:
		await btn(phys("X"))
	else:
		await press(main.hud._context_btn)
	await until(func(): return _replies.size() > replies0, 1.0)
	# One line per use, pass or fail: which layer did what.
	print("DIAG context \"%s\" by %s: action button pressed %d time(s); authority replies %s; pointer %s; outside pointer events %d; window focused %s; %d frames, %d fps" % [type,
		"X" if tv else "tap", _ctx_presses - presses0, str(_replies.slice(replies0).map(func(r): return r[1])), pad.cursor.round() if pad else "-",
		_real_mouse - mouse0, get_window().has_focus(), Engine.get_process_frames() - f0, int(Engine.get_frames_per_second())])
	check(_ctx_presses - presses0 == 1, "the real action button reported exactly one press (%d)" % (_ctx_presses - presses0))
	return true


## Leaves Decorate: the Done button, or B on a controller (as its hints say).
func leave_decorate() -> void:
	var c: Node = main.controller
	if not tv:
		await press(main.hud._decorate_btn)
		return
	for i in 3:
		if c.mode != "decorate":
			break
		await btn(phys("B"))
		await frames(3)


## Where a world point is on screen, or null when it is off screen, outside the safe area or under a
## HUD control (the same test a tap must pass).
func seen_at(point: Vector3) -> Variant:
	var cam: Camera3D = main.rig.camera
	if cam.is_position_behind(point):
		return null
	var at := cam.unproject_position(point)
	if not playable_rect().has_point(at) or ui_blocker_at(at) != "":
		return null
	return at


func item_seen(id: String) -> bool:
	var it: Dictionary = Session.model.items.get(id, {})
	return not it.is_empty() and seen_at(Vector3(it["x"], 0.12, it["z"])) != null


## Waits until the last message has faded, so a screenshot shows the scene and not an old toast.
func calm() -> void:
	await until(func(): return Time.get_ticks_msec() / 1000.0 > main.hud._toast_until + 0.6, 5.0)
	await frames(3)


## The other zoom level, through the real Zoom button.
func zoom_button() -> void:
	var b: Button = button_text(main.hud, "Zoom")
	check(b != null, "the Zoom button is there")
	if b:
		await act(b, "Zoom")
		await settle_camera()


## The width on screen of the line over an animal, in pixels of the canvas (from the label's own
## font and size, projected through the camera).
func line_width_px(node: Node3D, text: String) -> float:
	var label: Label3D = node._label
	var w: float = label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
	var cam: Camera3D = main.rig.camera
	var c: Vector3 = label.global_position
	var right: Vector3 = cam.global_transform.basis.x
	return cam.unproject_position(c - right * w * 0.5).distance_to(cam.unproject_position(c + right * w * 0.5))


func scroll_into_view(b: Control) -> Control:
	if b == null:
		return null
	var p := b.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p:
		(p as ScrollContainer).ensure_control_visible(b)
		await frames(3)
	return b


func stand_at(p: Vector2) -> void:
	var c: Node = main.controller
	c.pos = p
	c._walk_target = null
	c._place_kid()
	c._send_state()
	main.rig.snap()
	await frames(3)


func ask_result(req: int) -> Dictionary:
	var out := [{}]
	main.controller._ask(req, func(r): out[0] = r)
	await until(func(): return not out[0].is_empty(), 5.0)
	return out[0]


func put(kind: String, space: String, at: Vector2) -> String:
	var r: Dictionary = await ask_result(Session.place(kind, space, at, 0, -2))
	check(r.get("ok", false), "set up: a %s at %s (%s)" % [kind, at, r.get("error", "ok")])
	return r.get("item", {}).get("id", "")


func animal(kind: String) -> Dictionary:
	for a in Animals.brain.animals:
		if a["kind"] == kind:
			return a
	return {}


## Everyone rests far away (except the kinds listed), so nobody steps on the pad or comes to look.
func park_animals(except := []) -> void:
	var i := 0
	for a in Animals.brain.animals:
		if except.has(a["kind"]) or a["guest"] != 0:
			continue
		a["pos"] = Vector2(-22.0 + i * 2.0, -19.0)
		a["goal"] = null
		a["plan"] = "rest"
		a["action"] = "rest"
		a["timer"] = 999.0
		a["use"] = {}
		a["focus"] = {}
		i += 1


func lamp_energy(id: String) -> float:
	var node: Node3D = main.world.item_nodes.get(id)
	if node == null:
		return -1.0
	for l in node.find_children("*", "OmniLight3D", true, false):
		if l.is_in_group("lamp"):
			return (l as OmniLight3D).light_energy
	return -1.0


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "420"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "420"))
		print("CONTRAPTION %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("CONTRAPTION start tag=%s input=%s engine=%s renderer=%s" % [tag, "controller" if tv else "touch",
		Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method()])
	hud._context_btn.pressed.connect(func(): _ctx_presses += 1)
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	for f in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var reduce_before: bool = DecoMotion.load_reduce()
	Session.start_solo(SAVE, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	main.world.set_reduce_motion(false)
	check(Animals.brain != null and main.world.contraptions != null, "the animals are out and the contraption layer is there")
	park_animals()
	await _build(hud, c)
	case_ended("toy box and placing")
	await _links(hud, c)
	case_ended("links")
	await _chain(hud, c)
	case_ended("chain")
	await _step_pad(hud, c)
	case_ended("step pad")
	await _town_life(hud, c)
	case_ended("living town")
	await _reduce_motion(hud, c)
	case_ended("reduce motion")
	await _room(hud, c)
	case_ended("room lights")
	for loc in locales:
		await _texts_in(loc, hud, c)
		case_ended("[%s] texts" % loc)
	main.world.set_reduce_motion(reduce_before)
	I18n.set_locale(locales[0])
	if tv:
		check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the controller tour (%d; first: %s)" % [_real_mouse, _real_mouse_first])
	print("CONTRAPTION %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## The Contraptions tab, its idea line and a Big button placed from it; then the rest of the row.
func _build(hud: Control, c: Node) -> void:
	# Free ground for the whole layout, away from anything that takes part in contraptions.
	var found := false
	for z in range(9, 18):
		for x in range(-14, 10):
			var b := Vector2(x, z)
			var fits := Session.model.check("push_button", "town", b.x, b.y, 0) == "" \
				and ROW.all(func(e): return Session.model.check(e[0], "town", b.x + e[1].x, b.y + e[1].y, 0) == "") \
				and Session.model.check("step_pad", "town", b.x + PAD_AT.x, b.y + PAD_AT.y, 0) == "" \
				and Session.model.check("bubble_machine", "town", b.x + BUBBLES_AT.x, b.y + BUBBLES_AT.y, 0) == "" \
				and Session.model.items_in("town").all(func(i): return Vector2(i["x"], i["z"]).distance_to(b + Vector2(2.2, 1.6)) > 5.5 or not Contraptions.takes_part(i["kind"]))
			if fits and not found:
				base = b
				found = true
	check(found, "free ground for the contraption (%s)" % base)
	await stand_at(base + Vector2(0.0, 1.8))
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0), "Decorate opens the toy box")
	var tab: Button = await scroll_into_view(find_button(hud._tabs, "tab", "Contraptions"))
	check(tab != null, "the toy box has a Contraptions tab outdoors")
	await act(tab, "the Contraptions tab")
	await frames(3)
	check(hud._hint.text == RoomThemes.TOOLKIT_IDEAS["Contraptions"], "the tab shows its idea line (%s)" % hud._hint.text)
	for kind in ["push_button", "step_pad", "pinwheel", "bubble_machine", "lamp_post", "music_box"]:
		check(hud._cards.find_children("*", "Button", true, false).any(func(b): return b.get_meta("kind", "") == kind), "the tab offers the %s" % kind)
	toybox_hints_clear("Contraptions tab, first capture frame")
	await shot("toybox_tab")
	var card: Button = await scroll_into_view(find_button(hud._cards, "kind", "push_button"))
	var before: Array = Session.model.items.keys()
	await act(card, "the Big button card")
	check(await until(func(): return c.ghost != null and c.g_kind == "push_button", 2.0), "the card starts placing a Big button")
	if c.g_error != "":
		print("DIAG the ghost shows \"%s\" at %s" % [c.g_error, c.g_pos])
	if tv:
		await btn(JOY_BUTTON_START)
	else:
		await press(hud._place_btn)
	check(await until(func(): return Session.model.items.size() == before.size() + 1, 3.0), "Place here puts the Big button in town")
	var made: Array = Session.model.items.keys().filter(func(k): return not before.has(k))
	ids["push_button"] = made[0] if not made.is_empty() else ""
	check(ids["push_button"] != "" and Session.model.items[ids["push_button"]]["kind"] == "push_button", "it is a Big button")
	if c.ghost != null:
		if tv:
			await btn(phys("B"))
		else:
			await press(hud._cancel_btn)
	if c.mode == "decorate":
		await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done leaves Decorate")
	# Set up: the button goes to the layout's corner and the other things join it (the authority's
	# normal requests; placing each from the toy box is the same path as the button's).
	var bp := Vector2(Session.model.items[ids["push_button"]]["x"], Session.model.items[ids["push_button"]]["z"])
	if bp.distance_to(base) > 0.01:
		var mv: Dictionary = await ask_result(Session.move(ids["push_button"], base, 0))
		check(mv.get("ok", false), "set up: the button moves to %s (%s)" % [base, mv.get("error", "ok")])
	for e in ROW:
		ids[e[0]] = await put(e[0], "town", base + e[1])
	ids["step_pad"] = await put("step_pad", "town", base + PAD_AT)
	ids["bubble_machine"] = await put("bubble_machine", "town", base + BUBBLES_AT)
	park_animals()   # whoever came to look at the new things goes back to rest
	await frames(4)
	check(ids.values().all(func(i): return i != "" and main.world.item_nodes.has(i)), "all seven things are drawn")
	_case_ok = true


## Decorate shows what is linked to what; Done hides it again.
func _links(hud: Control, c: Node) -> void:
	var cw: Node = main.world.contraptions
	check(not cw.links_on and cw.link_pairs.is_empty(), "no links are drawn while playing")
	await stand_at(base + Vector2(2.2, 5.5))
	await zoom_button()   # the other zoom level for this picture (Decorate's tools cover the camera buttons)
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return cw.links_on and cw.link_pairs.size() == 4, 3.0), "Decorate draws four links (%s)" % str(cw.link_pairs))
	# For the picture: the first place where all seven things are in view above the open toy box.
	var all_seen := false
	for off in [Vector2(2.2, 4.4), Vector2(2.2, 5.5), Vector2(2.2, 6.5), Vector2(1.0, 5.0), Vector2(3.5, 5.0), Vector2(2.2, 3.4), Vector2(2.2, 7.5)]:
		await stand_at(base + off)
		await settle_camera()
		if ids.values().all(func(i): return item_seen(i)):
			all_seen = true
			break
	check(all_seen, "all seven linked things are on screen, clear of the toy box and the messages (%s)" % str(ids.keys().filter(func(k): return not item_seen(ids[k]))))
	await calm()
	var want := [[ids["push_button"], ids["lamp_post"]], [ids["lamp_post"], ids["music_box"]], [ids["music_box"], ids["pinwheel"]], [ids["step_pad"], ids["bubble_machine"]]]
	for pair in want:
		check(cw.link_pairs.has(pair), "a link from %s to %s" % [Session.model.items[pair[0]]["kind"], Session.model.items[pair[1]]["kind"]])
	check(cw._links_root.get_child_count() >= 4 * 4, "each link is a dotted line with an arrow head (%d parts)" % cw._links_root.get_child_count())
	if tv:
		await hints_ok("decorating with links")
	await settle_camera()
	await shot("links")
	await leave_decorate()
	await zoom_button()
	check(await until(func(): return c.mode == "play" and not cw.links_on and cw.link_pairs.is_empty(), 3.0), "Done hides the links")
	await frames(3)
	check(cw._links_root.get_child_count() == 0, "and removes the dotted lines")
	_case_ok = true


## Press the button: the lamp, the music box and the pinwheel answer one after another.
func _chain(hud: Control, c: Node) -> void:
	var cw: Node = main.world.contraptions
	var log := []
	var t0 := [0]
	var on_react := func(id, _from, effect, on): log.append([effect, id, on, Time.get_ticks_msec() - t0[0]])
	Session.contraption_reacted.connect(on_react)
	await stand_at(base + Vector2(-2.6, 1.4))
	check(c._ctx.get("type", "") != "press", "from a few steps away the button is not offered yet")
	# Beside the button, so the camera sees the button and its row on a narrow screen too (walking
	# there: the step pad case; a tap on the button: the Reduce motion case).
	var row_ids := [ids["push_button"], ids["lamp_post"], ids["music_box"], ids["pinwheel"]]
	for off in [Vector2(0.75, 0.95), Vector2(-0.95, 0.45), Vector2(0.0, 1.1)]:
		await stand_at(base + off)
		await settle_camera()
		if row_ids.all(func(i): return item_seen(i)):
			break
	check(await until(func(): return c._ctx.get("type", "") == "press" and hud._context_btn.is_visible_in_tree(), 8.0), "next to the button the action is Press")
	check(row_ids.all(func(i): return item_seen(i)), "the button and its row are on screen (%s)" % str(row_ids.filter(func(i): return not item_seen(i))))
	await calm()
	check(hud._context_btn.text == "Press", "the action button says Press (%s)" % hud._context_btn.text)
	if tv:
		var parts: Array = pad.hint_parts()
		# r12: hint_parts() holds source texts; the hint label shows them translated. Require both, in any language.
		check(parts.any(func(p): return str(p[1]) == "Press") and tr("Press") in str(pad._hint_label.text), "the controller hints name Press (%s; shown: %s)" % [str(parts), pad._hint_label.text])
		await hints_ok("at the button")
	await settle_camera()
	await shot("press_offered")
	var presses0: int = cw.presses
	var wheel: Node3D = main.world.item_nodes[ids["pinwheel"]].get_node("Wheel")
	var angle0: float = wheel.rotation.z
	t0[0] = Time.get_ticks_msec()
	check(await do_context("press"), "Press is used (%s)" % ("X" if tv else "the action button"))
	check(await until(func(): return cw.presses == presses0 + 1, 2.0), "the button dips")
	check(await until(func(): return log.size() >= 1, 2.0), "the lamp answers first")
	check(lamp_energy(ids["lamp_post"]) > 1.5 and main.world.item_nodes[ids["lamp_post"]].get_node_or_null("LampHalo") != null, "the lamp post shines by day, with its halo (energy %.2f)" % lamp_energy(ids["lamp_post"]))
	check(not Session.model.evening, "(it is day)")
	check(cw._flying.size() >= 1 or cw.sparks_drawn >= 2, "a spark is on its way to the next thing")
	await shot("chain_running")
	check(await until(func(): return log.size() >= 3, 3.0), "the music box and the pinwheel follow")
	check(log.map(func(e): return [e[0], e[1], e[2]]) == [["light", ids["lamp_post"], true], ["music", ids["music_box"], true], ["spin", ids["pinwheel"], true]],
		"lamp on, music on, pinwheel spinning, in that order (%s)" % str(log.map(func(e): return e[0])))
	if log.size() == 3:
		check(log[1][3] - log[0][3] >= 350 and log[2][3] - log[1][3] >= 350, "one after another, not all at once (%s ms)" % str(log.map(func(e): return e[3])))
	check(Session.model.items[ids["music_box"]]["on"], "the music box plays")
	await wait(0.5)
	check(absf(wheel.rotation.z - angle0) > 0.5 and cw.spinning.has(ids["pinwheel"]), "the pinwheel's sails turn")
	check(cw.sparks_drawn >= 3 and int(cw.effects.get("light", 0)) == 1 and int(cw.effects.get("music", 0)) == 1 and int(cw.effects.get("spin", 0)) == 1, "three sparks and three effects were drawn (%d, %s)" % [cw.sparks_drawn, str(cw.effects)])
	check(not log.any(func(e): return e[1] == ids["bubble_machine"]), "the bubble machine by the step pad is not part of this chain")
	await wait(5.2)
	check(not cw.spinning.has(ids["pinwheel"]), "after a few seconds the pinwheel is still again")
	Session.contraption_reacted.disconnect(on_react)
	_case_ok = true


## Walk onto the step pad: the bubble machine blows bubbles.
func _step_pad(_hud: Control, c: Node) -> void:
	var cw: Node = main.world.contraptions
	var pad_pos: Vector2 = base + PAD_AT
	await stand_at(pad_pos + Vector2(0.0, 2.0))
	var bubbles0: int = int(cw.effects.get("bubbles", 0))
	var presses0: int = cw.presses
	if tv:
		# Which way the left stick's "up" walks on this screen, then steer onto the pad.
		var p0: Vector2 = c.pos
		await stick(true, Vector2(0.0, -1.0), 0.25)
		_stick_up = (c.pos - p0).normalized() if c.pos.distance_to(p0) > 0.05 else Vector2(0, -1)
		for i in 40:
			var d: Vector2 = pad_pos - c.pos
			if d.length() < 0.3 or cw.presses > presses0:
				break
			var right := Vector2(-_stick_up.y, _stick_up.x)
			var v := Vector2(d.normalized().dot(right), -d.normalized().dot(_stick_up))
			axis(JOY_AXIS_LEFT_X, v.x)
			axis(JOY_AXIS_LEFT_Y, v.y)
			await frames(4)
		axis(JOY_AXIS_LEFT_X, 0.0)
		axis(JOY_AXIS_LEFT_Y, 0.0)
		await frames(3)
		check(c.pos.distance_to(pad_pos) < Contraptions.PAD_REACH + 0.2, "the left stick walks onto the step pad (%.2f m away)" % c.pos.distance_to(pad_pos))
	else:
		await walk_to(pad_pos)
		check(await until(func(): return c.pos.distance_to(pad_pos) < Contraptions.PAD_REACH, 6.0), "a tap on the pad walks onto it (%.2f m away)" % c.pos.distance_to(pad_pos))
	check(await until(func(): return cw.presses == presses0 + 1, 3.0), "stepping on the pad sets it off")
	check(await until(func(): return int(cw.effects.get("bubbles", 0)) == bubbles0 + 1, 3.0), "the bubble machine answers")
	var machine: Node3D = main.world.item_nodes[ids["bubble_machine"]]
	var p := machine.get_node_or_null("Bubbles") as CPUParticles3D
	check(p != null and p.emitting and cw.bubbling.has(ids["bubble_machine"]), "bubbles rise from its funnel")
	await wait(0.8)
	await settle_camera()
	await shot("bubbles")
	await wait(1.5)
	check(cw.presses == presses0 + 1, "standing on the pad does not set it off again")
	await wait(4.0)
	check(not cw.bubbling.has(ids["bubble_machine"]), "after a few seconds the bubbles stop")
	_case_ok = true


## The music box plays: Wooly comes over to dance, says so, and its card says so. Pip comes to look
## at a new thing.
func _town_life(hud: Control, c: Node) -> void:
	var cw: Node = main.world.contraptions
	var box: Vector2 = base + ROW[1][1]
	check(Session.model.items[ids["music_box"]]["on"], "(the music box is still playing from the chain)")
	var sheep := animal("sheep")
	sheep["pos"] = Animals.brain._free_near(Session.model, box + Vector2(0.5, -4.0), 0.5)
	sheep["plan"] = ""
	sheep["action"] = "idle"
	sheep["timer"] = 0.3
	sheep["use"] = {}
	await stand_at(box + Vector2(-1.0, 2.6))
	check(await until(func(): return Animals.focus.get("sheep", {}).get("why", "") == "music", 20.0), "Wooly hears the music box and heads for it (%s)" % str(Animals.focus))
	check(Animals.focus.get("sheep", {}).get("id", "") == ids["music_box"], "its focus is this music box")
	var node: Node3D = main.world.animals.get("sheep")
	var line: String = tr("%s loves this music!") % tr("Wooly")
	check(node != null and node.line == "%s loves this music!" and node._label.text == line and node._label.visible, "the line over Wooly says so (%s)" % (node._label.text if node else "no node"))
	check(await until(func(): return cw.rings.has(ids["music_box"]), 2.0), "a ring marks the music box")
	check(await until(func(): return animal("sheep")["action"] == "dance" and animal("sheep")["pos"].distance_to(box) < 2.2, 20.0), "Wooly arrives and dances by the box (%.1f m, %s)" % [animal("sheep")["pos"].distance_to(box), animal("sheep")["action"]])
	await wait(0.6)
	await settle_camera()
	await shot("wooly_music")
	# Its card says what it is doing first.
	var cam: Camera3D = main.rig.camera
	var aim: Vector2 = cam.unproject_position(node.global_position + Vector3(0, 0.4, 0))
	if tv:
		for i in 5:   # the pointer may start far away: keep steering until it is on Wooly
			aim = cam.unproject_position(node.global_position + Vector3(0, 0.4, 0))
			if pad.cursor.distance_to(aim) < 16.0:
				break
			await steer(Rect2(aim - Vector2(12, 12), Vector2(24, 24)))
		check(main.world.pick_animal(cam, pad.cursor) == "sheep", "the pointer is on Wooly (%s, Wooly at %s)" % [pad.cursor.round(), aim.round()])
		print("DIAG pointer %s, Wooly on screen at %s, picks \"%s\", modal %s" % [pad.cursor.round(), aim.round(), main.world.pick_animal(cam, pad.cursor), modal_open()])
		await btn(phys("A"))
	else:
		await tap_at_world(node.global_position + Vector3(0, 0.4, 0), "Wooly")
	check(await until(func(): return hud._overlay.get_child_count() > 0, 3.0), "a tap on Wooly opens its card")
	var texts: Array = hud._overlay.find_children("*", "Label", true, false).map(func(l): return str(l.text))
	check(texts.any(func(t): return t.begins_with(line)), "the card begins with what Wooly is doing (%s)" % str(texts).left(160))
	if tv:
		await hints_ok("Wooly's card")
	await shot("wooly_card")
	await close_dialogs()
	# After its dance Wooly does something else: its own routine, or another thing it likes (the lamp
	# is on), never the music box again straight away.
	check(await until(func(): return Animals.focus.get("sheep", {}).get("id", "") != ids["music_box"], 14.0), "after its dance Wooly leaves the music box")
	await frames(3)
	check(node.line == Animals.focus_line("sheep") and node.line != "%s loves this music!", "and the line over it follows (now \"%s\")" % node._label.text)
	# A new thing near Pip.
	var pig := animal("pig")
	var spot = Session.model.find_free_spot("bench", "town", base + Vector2(-3.5, 2.0))
	pig["pos"] = Animals.brain._free_near(Session.model, Vector2(spot.x, spot.y) + Vector2(-0.5, -3.5), 0.45)
	pig["plan"] = ""
	pig["action"] = "idle"
	pig["timer"] = 4.0
	pig["use"] = {}
	pig["noticed_t"] = -99.0
	await stand_at(Vector2(spot.x, spot.y) + Vector2(1.5, 2.2))
	var bench: String = await put("bench", "town", Vector2(spot.x, spot.y))
	check(await until(func(): return Animals.focus.get("pig", {}) == {"id": bench, "why": "new"}, 4.0), "Pip notices the new bench (%s)" % str(Animals.focus))
	var pnode: Node3D = main.world.animals.get("pig")
	check(pnode != null and pnode._label.text == tr("%s wonders what this is.") % tr("Pip"), "the line over Pip says it wonders what this is")
	check(await until(func(): return animal("pig")["action"] == "look" and animal("pig")["pos"].distance_to(Vector2(spot.x, spot.y)) < 2.2, 15.0), "Pip walks up and looks at the bench")
	await settle_camera()
	await shot("pip_new_bench")
	park_animals()
	check(await until(func(): return Animals.focus.is_empty(), 3.0), "(the animals rest again)")
	check(await until(func(): return cw.rings.is_empty(), 2.0), "the rings are gone with the focus")
	_case_ok = true


## Reduce motion: the chain still works, but nothing flies or spins.
func _reduce_motion(_hud: Control, c: Node) -> void:
	var cw: Node = main.world.contraptions
	main.world.set_reduce_motion(true)
	var wheel: Node3D = main.world.item_nodes[ids["pinwheel"]].get_node("Wheel")
	var angle0: float = wheel.rotation.z
	var spins0: int = int(cw.effects.get("spin", 0))
	var presses0: int = cw.presses
	var lit0: bool = Session.model.items[ids["lamp_post"]].get("on", false)
	if tv:
		await stand_at(base + Vector2(0.0, 1.0))
		check(await do_context("press"), "Press with Reduce motion on (X)")
	else:
		# A tap on the button from a few steps away: the child walks over and presses it in one go.
		await stand_at(base + Vector2(-2.6, 1.4))
		await tap_item(ids["push_button"])
	check(await until(func(): return cw.presses == presses0 + 1, 8.0), "the button is pressed with Reduce motion on (%s)" % ("X" if tv else "a tap on it walks over and presses"))
	var flew := [0]
	for i in 20:
		flew[0] = maxi(flew[0], cw._flying.size())
		await wait(0.1)
	check(int(cw.effects.get("spin", 0)) == spins0 + 1, "the pinwheel still answers")
	check(Session.model.items[ids["lamp_post"]].get("on", false) != lit0, "the lamp still switches (%s -> %s)" % [lit0, not lit0])
	check(flew[0] == 0, "no spark flies")
	check(is_equal_approx(wheel.rotation.z, angle0), "the pinwheel's sails stay still")
	await wait(1.0)
	main.world.set_reduce_motion(false)
	_case_ok = true


## A room: a button, a floor lamp beside it and a ceiling light above it, switched on by day.
func _room(hud: Control, c: Node) -> void:
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	var room := TownModel.room_space(houses[0]["id"], 1, 1)
	# Go in first and open the toy box, to choose a spot for the button that stays in view with it open.
	c.go_to_room(room)
	check(await until(func(): return c.space == room, 4.0), "in the room")
	await wait(0.8)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	await stand_at(Vector2(2.6, 1.6))
	await act(hud._decorate_btn, "Decorate")
	await until(func(): return c.mode == "decorate", 2.0)
	await settle_camera()
	var b_at = null
	for cand in [Vector2(-0.6, -1.3), Vector2(0.4, -1.3), Vector2(-1.4, -1.0), Vector2(-0.6, -0.6), Vector2(1.2, -1.2), Vector2(-2.2, -0.8), Vector2(0.0, 0.0)]:
		var sp = Session.model.find_free_spot("push_button", room, cand)
		if b_at == null and sp != null and seen_at(Vector3(sp.x, 0.12, sp.y)) != null and seen_at(Vector3(sp.x + 1.3, 0.12, sp.y)) != null:
			b_at = sp
	check(b_at != null, "a spot for the button that the open toy box does not cover")
	await leave_decorate()
	if b_at == null:
		return
	var rb: String = await put("push_button", room, b_at)
	var l_at = null
	for off in [Vector2(1.3, 0.0), Vector2(-1.3, 0.0), Vector2(0.0, 1.3), Vector2(1.1, 0.9), Vector2(-1.1, 0.9), Vector2(0.0, -1.3)]:
		if l_at == null and Session.model.check("floor_lamp", room, b_at.x + off.x, b_at.y + off.y, 0) == "":
			l_at = Vector2(b_at.x, b_at.y) + off
	check(l_at != null, "room for a floor lamp beside the button")
	var rl: String = await put("floor_lamp", room, l_at if l_at != null else Vector2.ZERO)
	var rc: String = await put("ceiling_fan_light", room, Vector2(b_at.x, b_at.y))
	if rb == "" or rl == "" or rc == "":
		return
	check(await until(func(): return main.world.item_nodes.has(rb) and main.world.item_nodes.has(rl), 4.0), "the room's new things are drawn")
	await stand_at(Vector2(b_at.x, b_at.y) + (Vector2(b_at.x, b_at.y) - l_at).normalized() * 0.9)
	check(lamp_energy(rl) < 0.1 and lamp_energy(rc) < 0.1, "by day the room's lamps are off (%.2f, %.2f)" % [lamp_energy(rl), lamp_energy(rc)])
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return main.world.contraptions.link_pairs.size() >= 2, 3.0), "Decorate in the room draws its links (%s)" % str(main.world.contraptions.link_pairs))
	check(main.world.contraptions.link_pairs.has([rb, rl]) and main.world.contraptions.link_pairs.has([rb, rc]), "from the button to the floor lamp and to the light on the ceiling above it")
	check(main.world.contraptions._links_root.get_children().any(func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh is TorusMesh), "the light straight above shows as a ring around the button")
	check(item_seen(rb) and item_seen(rl), "the button, its ring and the link to the floor lamp are on screen, clear of the toy box")
	await calm()
	await shot("room_links")
	await leave_decorate()
	await until(func(): return c.mode == "play", 2.0)
	check(await do_context("press"), "Press in the room")
	check(await until(func(): return Session.model.items[rl].get("on", false) and Session.model.items[rc].get("on", false), 3.0), "both lights are switched on")
	await frames(4)
	check(lamp_energy(rl) > 1.5 and lamp_energy(rc) > 0.5, "and they shine (%.2f, %.2f)" % [lamp_energy(rl), lamp_energy(rc)])
	check(main.world.item_nodes[rl].get_node_or_null("LampHalo") != null and main.world.item_nodes[rc].get_node_or_null("LampHalo") != null, "each with its halo")
	await calm()
	await shot("room_lit")
	# Leave and come back: the lamps are still on (the state is the town's, not the screen's).
	c.go_to_room("town")
	check(await until(func(): return c.space == "town", 4.0), "back outside")
	await wait(0.6)
	c.go_to_room(room)
	check(await until(func(): return c.space == room and main.world.item_nodes.has(rl), 4.0), "and in again")
	await frames(6)
	check(lamp_energy(rl) > 1.5, "the floor lamp is still on")
	c.go_to_room("town")
	await until(func(): return c.space == "town", 4.0)
	await wait(0.6)
	_case_ok = true


## The new texts in a language: the tab, its idea line, the item names, Press, and an animal's line.
func _texts_in(loc: String, hud: Control, c: Node) -> void:
	I18n.set_locale(loc)
	await frames(4)
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	await stand_at(base + Vector2(0.0, 1.0))
	check(await until(func(): return c._ctx.get("type", "") == "press" and hud._context_btn.is_visible_in_tree(), 4.0), "[%s] Press is offered" % loc)
	check(hud._context_btn.text == "Press" and (loc == "en" or tr("Press") != "Press"), "[%s] the action is Press, shown as \"%s\"" % [loc, tr("Press")])
	check(area.grow(1.0).encloses(hud._context_btn.get_global_rect()), "[%s] the action button is inside the safe area" % loc)
	for key in ["Big button", "Step pad", "Pinwheel", "Bubble machine", "Contraptions"]:
		check(loc == "en" or tr(key) != key, "[%s] \"%s\" is translated (%s)" % [loc, key, tr(key)])
	for a in TownLife.ATTRACTIONS:
		check("%s" in tr(a["say"]) and (loc == "en" or tr(a["say"]) != a["say"]), "[%s] the line for %s keeps the name and is translated" % [loc, a["why"]])
	# The line over an animal follows the language at once.
	var sheep := animal("sheep")
	var box: Vector2 = base + ROW[1][1]
	if not Session.model.items[ids["music_box"]]["on"]:
		await stand_at(box + Vector2(0.0, 1.2))   # the tune is started from next to the box
		await ask_result(Session.play_music(ids["music_box"], true))
	check(Session.model.items[ids["music_box"]]["on"], "[%s] the music box plays" % loc)
	sheep["pos"] = Animals.brain._free_near(Session.model, box + Vector2(0.3, -2.4), 0.5)
	sheep["plan"] = ""
	sheep["timer"] = 0.2
	sheep["use"] = {}
	sheep["last_use"] = ""
	Animals.enliven(ids["music_box"])
	check(await until(func(): return Animals.focus.get("sheep", {}).get("why", "") == "music", 10.0), "[%s] Wooly comes for the music" % loc)
	var node: Node3D = main.world.animals.get("sheep")
	check(node != null and node._label.text == tr("%s loves this music!") % tr("Wooly"), "[%s] the line over Wooly is in this language (%s)" % [loc, node._label.text if node else ""])
	# A picture of the line itself: Wooly dancing by the box, the whole line on screen in play.
	await stand_at(box + Vector2(-0.6, 2.4))
	check(await until(func(): return animal("sheep")["action"] == "dance" and animal("sheep")["pos"].distance_to(box) < 2.2, 15.0), "[%s] Wooly dances by the box" % loc)
	await settle_camera()
	await calm()
	var w_px: float = line_width_px(node, node._label.text)
	var mid = seen_at(node._label.global_position)
	var cam: Camera3D = main.rig.camera
	var right: Vector3 = cam.global_transform.basis.x
	var half: float = node._label.font.get_string_size(node._label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, node._label.font_size).x * node._label.pixel_size * 0.5
	check(mid != null and seen_at(node._label.global_position - right * half) != null and seen_at(node._label.global_position + right * half) != null,
		"[%s] the whole line over Wooly is on screen, under no control (%d px wide)" % [loc, int(w_px)])
	# Every line an animal can show, at this distance: none wider than a third of the screen.
	var widest := ["", 0.0]
	for key in TownLife.ATTRACTIONS.map(func(a): return a["say"]) + TownLife.SAY.values():
		for who in ["Wooly", "Bramble", "Biscuit", "Tumble", "Pip"]:
			var px: float = line_width_px(node, tr(key) % tr(who))
			if px > widest[1]:
				widest = [tr(key) % tr(who), px]
	print("DIAG [%s] line over Wooly %d px; the widest line is %d px of %d: %s" % [loc, int(w_px), int(widest[1]), int(area.size.x), widest[0]])
	check(widest[1] < area.size.x / 3.0, "[%s] the widest line an animal can show is under a third of the screen (%d px)" % [loc, int(widest[1])])
	await shot("line_%s" % loc)
	await stand_at(base + Vector2(0.0, 1.0))
	# The tab and its idea line fit.
	await act(hud._decorate_btn, "Decorate")
	await until(func(): return c.mode == "decorate", 2.0)
	var tab: Button = await scroll_into_view(find_button(hud._tabs, "tab", "Contraptions"))
	check(tab != null and tab.text in ["Contraptions", tr("Contraptions")], "[%s] the tab is there, shown as \"%s\"" % [loc, tr("Contraptions")])
	await act(tab, "the Contraptions tab")
	await frames(4)
	check(hud._hint.text == RoomThemes.TOOLKIT_IDEAS["Contraptions"] and hud._hint_panel.visible, "[%s] the idea line shows" % loc)
	check(area.grow(1.0).encloses(hud._hint_panel.get_global_rect()), "[%s] the idea line fits the screen (%s in %s)" % [loc, hud._hint_panel.get_global_rect(), area])
	await settle_camera()
	toybox_hints_clear("[%s] Contraptions tab" % loc)
	await shot("texts_%s" % loc)
	await leave_decorate()
	await until(func(): return c.mode == "play", 2.0)
	park_animals()
	await until(func(): return Animals.focus.is_empty(), 3.0)
	_case_ok = true
