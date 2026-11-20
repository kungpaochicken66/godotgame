## The unified candidate's tram stop, end to end through the real game (unified r1): one solo session plays the
## three destinations the town's tram stop offers besides the zoo and the city, and checks that every return brings
## the child back to the stop with the town as it was:
##   the town and its HUD -> the walk to the stop -> its distinct entries (Ride to the zoo, Ride to the city, Ride to
##   Thousand Town, Roller Coaster Workshop, Explore the lantern reef) -> the Workshop (own child, a quick boarding,
##   a lap, off at the platform, Ride home straight from that platform) -> the stop again -> the Lantern Reef (own child,
##   town hidden, swimming, depth up and down, the camera turned, a view change, back) -> the stop again -> Ride to
##   Thousand Town (journey, arrival in the follow camera and its HUD, a street interaction: "Who's here?" at a
##   building's door, Night by the time button with a night picture, Ride home) -> the stop, the town HUD exactly as
##   at the start.
## unified r6 adds: the zoo and the city there and back (Ride home); after every return the stop's entries, the main
## world's own actions and (TV) the pointer back on the button that left, shown focused; the five destinations in one
## look (normal, focused, pressed); in every world (the stop, the Workshop and its platform, the reef, the zoo, the city,
## Thousand Town, home) every action and hint inside the TV safe area (touch: the screen); in Thousand Town none of the
## main world's own actions (Pets, Story, Hello, the lantern scrapbook, Decorate) shown or reachable. Pictures: stop,
## stop_focus (TV), workshop, workshop_platform, home_workshop, reef_depth, reef, home_reef, zoo, home_zoo, city,
## home_city, thousand, thousand_whos_here, thousand_night, home. Touch at 1920x1080 checks the tap on Courtyard Housing
## through the game's own tap target (the Mac's r5 1080p touch failure).
## Touch by default, fingers only: taps on the HUD's buttons; in the Workshop a card boards, Get off and the platform's
## Ride home button; in the reef a press-drag-release on the left half swims, Ascend and Descend held change the depth,
## a drag on the right half turns the camera, no controller hint shows; in Thousand Town a tap on a building walks the
## child to its door and asks who is there. --tv: the controller only, through the real layers (every event made by
## Input.parse_input_event and tagged synthetic; no handler is called directly): the stick walks; Start (+) opens the
## Workshop (Workshop r4's binding); the D-pad and A press the reef's and Thousand Town's buttons; in the Workshop the
## hint offers B / + Ride home at the platform and B rides home from there (unified r4); in the reef the hint panel
## shows the layout's labels, the left stick swims, ZR and ZL rise and sink, the right stick looks, the context button
## (X on a Nintendo pad, Y otherwise, as the hint says) changes the view and + (Start) returns; the reef adopts the
## controller from its events (no connection signal headless); in Thousand Town the stick walks to a door and the
## context button asks who is there; B closes.
##   Headless: scripts/godot.sh --headless --path game -- --driver=res://tests/station_tour.gd --no-shots \
##                 --window=1366x1024 --tag=ipad
##             ... --tv --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv
##   Rendered (Mac GPU, the player-camera evidence of record): scripts/godot.sh --path game --resolution 1920x1080 \
##                 -- --driver=res://tests/station_tour.gd --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv
## Ends with "STATION TOUR <tag>: N checks, F failures" and exits 1 on any failure.
extends "res://tests/coaster_tour.gd"

const ReefDive := preload("res://scripts/reef/reef_dive.gd")
const TvModeS := preload("res://scripts/core/tv_mode.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")

var c: Node
var hud: Control
var board := Vector2.ZERO
var _start_buttons: Array = []
var _journeys: Array = []
## Where the child stood when it left on a local trip (Workshop, reef): read once the trip has opened, when the town's
## controller is paused and the position can no longer move (r2: recorded before the press it could still be settling
## from the walk, 0.28 m on the Mac's rendered run).
var _stand := Vector2.ZERO
## Thousand Town: the walkable legs from the station forecourt to Courtyard Housing (as thousand_loop_tour.gd).
const TO_COURTYARD := [Vector2(-51.75, 3.75), Vector2(-52.25, -2.75), Vector2(-54.75, -5.75), Vector2(-64.6, -5.75)]
const COURTYARD := "h-courtyard"


## Visible HUD buttons (path and text): the town HUD's state for the before/after comparison.
func hud_buttons() -> Array:
	var out: Array = []
	for b in hud.find_children("*", "BaseButton", true, false):
		if (b as Control).is_visible_in_tree():
			out.append("%s|%s" % [str(hud.get_path_to(b)), (b as Button).text if b is Button else ""])
	out.sort()
	return out


## unified r6: the TV's title-safe area (TvMode) on a TV, else the screen.
func _safe() -> Rect2:
	var vr := get_viewport().get_visible_rect()
	if TvModeS.active():
		var m := vr.size * Vector2(TvModeS.SAFE_X, TvModeS.SAFE_Y)
		return Rect2(vr.position + m, vr.size - 2.0 * m)
	return vr


## unified r6: every given control that shows (action buttons, hints, a world's title) lies whole inside _safe().
func _safe_check(where: String, controls: Array) -> void:
	await frames(2)
	var safe := _safe().grow(0.5)
	var out := []
	var n := 0
	for ctl in controls:
		if ctl == null or not is_instance_valid(ctl) or not (ctl as Control).is_visible_in_tree():
			continue
		n += 1
		var r := (ctl as Control).get_global_rect()
		if not safe.encloses(r):
			out.append("%s %s" % [(ctl as Button).text if ctl is Button and (ctl as Button).text != "" else str(ctl.name), r])
	check(n > 0 and out.is_empty(), "%s: every action and hint inside the %s (%d shown; outside: %s)" % [where, "TV safe area" if TvModeS.active() else "screen", n, str(out)])


## unified r6: the HUD's actions on screen now (its visible buttons, not the floating name tags) and the controller hint.
func _hud_controls() -> Array:
	var out: Array = []
	for b in hud.find_children("*", "BaseButton", true, false):
		var ctl := b as Control
		if ctl.is_visible_in_tree() and not (hud._tag_layer as Node).is_ancestor_of(ctl) and ctl.size.x >= 4.0:
			out.append(ctl)
	if tv and main.pad and main.pad._hint_panel.visible:
		out.append(main.pad._hint_panel)
	return out


## unified r6: a button's look in its normal, focused (hover: the controller's pointer or the mouse) and pressed states.
func _style_sig(b: Button) -> String:
	var parts := []
	for st in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(st) as StyleBoxFlat
		parts.append("%s:%s/%d/%s" % [st, sb.bg_color.to_html(), sb.border_width_top, sb.border_color.to_html()] if sb else st + ":?")
	parts.append("font %d" % b.get_theme_font_size("font_size"))
	parts.append("h %d" % int(b.size.y))
	parts.append("icon %s" % (str(b.icon.get_instance_id()) if b.icon else "none"))
	return " ".join(parts)


## unified r7 (the Mac's real window: the GUI hover was lost after a journey's card): the pad's own selection is `ctl`
## and its focus ring is drawn on it (PadInput.selected, the PadFocusRing node), whatever the mouse hover says.
func _ring_on(ctl: Control) -> bool:
	var ring: Control = main.pad.get_node_or_null("PadFocusRing")
	var r := ctl.get_global_rect()
	return main.pad.selection() == ctl and ring != null and ring.is_visible_in_tree() \
		and ring.get_global_rect().position.distance_to(r.position) < 1.0 and ring.size.distance_to(r.size) < 1.0


## unified r6 (TV): the control the pointer is on before a trip (or its place), to compare after the return.
func _focus_before() -> Array:
	if not tv:
		return []
	return [main.pad._target_at(main.pad.cursor), main.pad.cursor]


## unified r6 (TV): back at the stop, the pointer is where it was: on the control used to leave (restored by PadInput
## once the stop's buttons show), or at its place when it was on none.
func _focus_after(before: Array, what: String) -> void:
	if not tv or before.is_empty():
		return
	await until(func(): return not main.pad.focus_waiting(), 5.0)
	await frames(3)
	var ctl: Control = before[0]
	if ctl != null and is_instance_valid(ctl):
		check(ctl.is_visible_in_tree() and ctl.get_global_rect().has_point(main.pad.cursor) and _ring_on(ctl),
			"after %s the pointer is back on %s, selected with the focus ring drawn (pointer %s)" % [what, (ctl as Button).text if ctl is Button else str(ctl.name), main.pad.cursor])
		# r7: the real window's own mouse elsewhere (the Mac's run: no hover on the button after the journey). A motion
		# that is not the pad's takes the GUI hover away; the pad's selection and ring must not depend on it.
		var away := InputEventMouseMotion.new()
		away.position = get_viewport().get_final_transform() * Vector2(4, 4)
		away.global_position = away.position
		Input.parse_input_event(away)
		await frames(3)
		var lost_hover: bool = ctl is BaseButton and not (ctl as BaseButton).is_hovered()
		check(lost_hover and _ring_on(ctl) and main.pad.cursor.distance_to(ctl.get_global_rect().get_center()) < ctl.get_global_rect().size.length(),
			"after %s, with the window's mouse elsewhere (hover lost: %s), %s stays selected with its ring" % [what, lost_hover, (ctl as Button).text if ctl is Button else str(ctl.name)])
	else:
		check(main.pad.cursor.distance_to(before[1]) < 1.0, "after %s the pointer is where it was (%s)" % [what, main.pad.cursor])


func _shot(name: String) -> void:
	if main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	var target := "%s/station_%s_%s.png" % [shots, tag, name]
	check(get_viewport().get_texture().get_image().save_png(target) == OK, "saved " + name)


func _joy(b: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.set_meta("synthetic", true)   # injected by this test driver, not hardware
		e.button_index = b
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		Input.parse_input_event(e)
		await frames(2)


## The controller's pointer onto `target` with the D-pad (PadInput jumps between the HUD's buttons), then A. The
## shortest D-pad path is planned as PadInput.snap chooses (as thousand_loop_tour.gd), again after every press.
func pad_press_button(target: Control, what: String) -> bool:
	var pad: Node = main.pad
	var names := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}
	var seen := []
	for i in 14:
		if target.get_global_rect().has_point(pad.cursor):
			break
		var path := _dpad_path(target)
		if path.is_empty():
			break
		seen.append(path[0])
		await _joy(names[path[0]])
	var on: bool = target.get_global_rect().has_point(pad.cursor)
	if not on:
		print("DIAG cursor %s target %s rect %s in targets %s" % [pad.cursor, what, target.get_global_rect(), pad.targets().has(target)])
		for t: Control in pad.targets():
			print("DIAG   target %s %s" % [(t as Button).text if t is Button else str(t.name), t.get_global_rect()])
	check(on, "the D-pad brings the pointer to %s (%s)" % [what, ",".join(seen)])
	if on:
		await _joy(pad.confirm_button())
	return on


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


func _dpad_path(target: Control) -> Array:
	var pad: Node = main.pad
	var ts: Array = pad.targets()
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	var queue: Array = [[pad.cursor, []]]
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


func _press(target: Control, what: String) -> void:
	if tv:
		await pad_press_button(target, what)
	else:
		await _touch_button(target)


## At the stop with the town's tram offered, the child where it was, the town HUD and camera back.
func at_stop(after: String, journey := false) -> void:
	await until(func(): return c._ctx.get("type", "") == "tram", 6.0)
	check(c.space == "town" and c.journey_to == "" and c.enabled and main.world.visible and main.rig.camera.current,
		"after %s: the town, its world and camera, walking enabled" % after)
	journey = journey or after == "Thousand Town"
	var spot := _stand if not journey else board
	var reach := 0.05 if not journey else 1.5
	check(c.pos.distance_to(spot) < reach and main.world.local_kid() != null and main.world.local_kid().is_visible_in_tree()
		and main.world.local_kid().global_position.distance_to(Vector3(c.pos.x, 0, c.pos.y)) < 0.2,
		"after %s: the child stands at the tram stop again, where it left (%s, %.2f m from %s)" % [after, c.pos, c.pos.distance_to(spot), spot])
	check(hud.visible and c._ctx.get("type", "") == "tram" and hud._workshop_btn.is_visible_in_tree() and hud._reef_btn.is_visible_in_tree(),
		"after %s: the stop's entries are offered again" % after)
	if tv:
		check(main.pad.process_mode != Node.PROCESS_MODE_DISABLED, "after %s: the controller layer runs again" % after)
	# unified r6: the main world's own actions are back (Thousand Town hides them)
	check(hud._pets_btn.is_visible_in_tree() and hud._story_btn.is_visible_in_tree() and hud._echo_btn.is_visible_in_tree()
		and hud._lantern_btn.is_visible_in_tree() and hud._decorate_btn.is_visible_in_tree(),
		"after %s: Pets, Story, Hello, the lantern scrapbook and Decorate are offered again" % after)


func _run() -> void:
	tv = main.args.has("tv")
	c = main.controller
	hud = main.hud
	for f in ["user://station-tour.json", "user://station-tour.json.bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	c.journey.connect(func(phase: String, to: String): _journeys.append([phase, to]))
	Session.start_solo("user://station-tour.json", main.menus.avatar)
	await wait(1)
	await settle_camera()
	if tv:
		check(TvModeS.active() and main.pad != null, "TV mode with the controller layer")
	board = TownModel.tram_stop_boarding(Session.model)
	if tv:
		await walk_to(board)
	else:
		await _tap_open_ground(board)
	await _still()
	# r3 (Mac r2 touch run): a tap that lands on the stop or its "Zoo tram" tag walks there with the zoo ride pending,
	# which then starts by itself; the tour's walk must arrive with nothing pending, as a child who walked over.
	check(c._pending_ctx.is_empty() and c.journey_to == "" and c.space == "town",
		"the walk to the stop arrives with no ride pending (pending %s, journey %s)" % [str(c._pending_ctx.get("type", "")), c.journey_to])
	await until(func(): return c._ctx.get("type", "") == "tram" and hud._workshop_btn.is_visible_in_tree(), 8)
	await frames(4)
	_start_buttons = hud_buttons()
	# --- the stop's distinct entries
	var entries := {"zoo": hud._context_btn, "city": hud._context_alt_btn, "thousand": hud._context_alt3_btn,
		"workshop": hud._workshop_btn, "reef": hud._reef_btn}
	var texts := []
	for k in entries:
		var b: Button = entries[k]
		check(b.is_visible_in_tree() and b.text != "", "the stop offers %s (%s)" % [k, b.text])
		texts.append(b.text)
	var uniq := {}
	for t in texts:
		uniq[t] = true
	check(uniq.size() == texts.size(), "five distinct station entries: %s" % str(texts))
	check(hud._context_alt3_btn.text == "Ride to Thousand Town" and hud._workshop_btn.text == "Roller Coaster Workshop"
		and hud._reef_btn.text == "Explore the lantern reef", "named Ride to Thousand Town, Roller Coaster Workshop, Explore the lantern reef")
	var rects := []
	for k in entries:
		rects.append((entries[k] as Control).get_global_rect())
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				overlap = true
	check(not overlap, "no two station entries overlap on screen")
	# unified r6 (Apple TV feedback): every destination is one kind of button in the game's theme
	var sigs := {}
	for k in entries:
		sigs[_style_sig(entries[k])] = true
	var sig0 := _style_sig(hud._workshop_btn)
	var hover0 := hud._workshop_btn.get_theme_stylebox("hover") as StyleBoxFlat
	check(sigs.size() == 1 and hover0 != null and hover0.border_color == UI.FOCUS_RING and hover0.border_width_top == UI.FOCUS_W
		and sig0.get_slice(" ", 0) != sig0.get_slice(" ", 1) and sig0.get_slice(" ", 1) != sig0.get_slice(" ", 2),
		"the five destinations look alike: normal, focused (the theme's focus ring) and pressed (%s)" % str(sigs.keys()))
	await _safe_check("at the stop", _hud_controls())
	await _shot("stop")
	if tv:
		# the pointer on a destination shows it focused (the hover state, from the pointer's own mouse motion)
		await pad_press_button_no_confirm(hud._reef_btn, "Explore the lantern reef")
		check(_ring_on(hud._reef_btn), "the destination under the pointer is selected, with the focus ring drawn")
		await _shot("stop_focus")
	var f := _focus_before()
	if tv:
		f = [hud._workshop_btn, Vector2.ZERO]   # Start (+) taps the Workshop's button: the pointer rests on it
	await _workshop()
	await at_stop("the Workshop")
	await _focus_after(f, "the Workshop")
	await _shot("home_workshop")
	if tv:
		await pad_press_button_no_confirm(hud._reef_btn, "Explore the lantern reef")
	f = _focus_before()
	await _reef()
	await at_stop("the Lantern Reef")
	await _focus_after(f, "the Lantern Reef")
	await _shot("home_reef")
	await _trip(hud._context_btn, Places.ZOO, "Ride to the zoo")
	await _trip(hud._context_alt_btn, Places.CITY, "Ride to the city")
	f = []
	await _thousand()
	await at_stop("Thousand Town")
	await frames(4)
	var end_buttons := hud_buttons()
	check(end_buttons == _start_buttons, "the town HUD at the stop is exactly as at the start (%d buttons)" % end_buttons.size())
	if end_buttons != _start_buttons:
		print("  start: ", _start_buttons, "\n  end:   ", end_buttons)
	await _card_gone("the return home")
	await _focus_after(_thousand_focus, "Thousand Town")
	await _safe_check("home again", _hud_controls())
	await _shot("home")
	_done()


## unified r6: a journey from the stop and back (the zoo, the city): there and its HUD (Ride home, inside the safe
## area), Ride home, the stop as it was, the pointer back on the button that left.
func _trip(btn: Button, to: String, what: String) -> void:
	await _still()
	await until(func(): return c._ctx.get("type", "") == "tram" and btn.is_visible_in_tree(), 6.0)
	await frames(3)
	var name: String = btn.text
	check(name == tr(what), "the stop offers %s (%s)" % [what, name])
	if tv:
		await pad_press_button_no_confirm(btn, what)
	var f := _focus_before()
	await _tram_ready()
	if tv:
		await _joy(main.pad.confirm_button())
	else:
		await _touch_button(btn)
	var arrived := await until(func(): return c.space == to and c.journey_to == "", 30.0)
	check(arrived, "%s arrives (%s)" % [what, c.space])
	if not arrived:
		return
	await _card_gone("the arrival: " + to)
	await frames(8)
	check(hud._ride_home.is_visible_in_tree() and (hud._ride_home.get_theme_stylebox("hover") as StyleBoxFlat).border_color == UI.FOCUS_RING,
		"%s: Ride home is offered, in the destinations' look" % to)
	check(not hud._workshop_btn.is_visible_in_tree() and not hud._reef_btn.is_visible_in_tree(), "%s: no town-stop entries" % to)
	await _safe_check("in " + to, _hud_controls())
	await _shot(to)
	await _tram_ready()
	await _press(hud._ride_home, "Ride home")
	var home := await until(func(): return c.space == "town" and c.journey_to == "", 30.0)
	check(home, "Ride home from %s returns to the town" % to)
	await _card_gone("the return from " + to)
	await at_stop(to, true)
	await _focus_after(f, what)
	await _shot("home_" + to)


## r6: the authority takes a journey at most once a second of wall time (Session.JOURNEY_REST: "The tram is getting
## ready"); a headless run at a fixed frame rate gets there sooner than a child could. Wait as a child would.
func _tram_ready() -> void:
	var last := func() -> float:
		var t := -99.0
		for v in Session._last_journey.values():   # solo: the one local peer, whatever its id
			t = maxf(t, float(v))
		return t
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() / 1000.0 - float(last.call()) <= Session.JOURNEY_REST + 0.2 and Time.get_ticks_msec() - t0 < 3000:
		await frames(1)   # wall time: the authority's rest is wall time, and `until` counts game time


## The pointer onto `target` with the D-pad, without pressing it (r6: the focused look, the remembered control).
func pad_press_button_no_confirm(target: Control, what: String) -> void:
	var pad: Node = main.pad
	var names := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}
	for i in 14:
		if target.get_global_rect().has_point(pad.cursor):
			break
		var path := _dpad_path(target)
		if path.is_empty():
			break
		await _joy(names[path[0]])
	await frames(2)
	check(target.get_global_rect().has_point(pad.cursor), "the D-pad brings the pointer to %s" % what)


func _workshop() -> void:
	await _still()
	var before: Vector2 = c.pos
	if tv:
		await _joy(JOY_BUTTON_START)   # Workshop r4: Start (+) takes the Workshop tram from the stop
		await frames(6)
	else:
		await _touch_button(hud._workshop_btn)
	park = null
	for node in main.get_children():
		if node is Park:
			park = node
	check(park != null, "the Roller Coaster Workshop opens from the stop")
	if park == null:
		return
	_stand = c.pos
	check(_stand.distance_to(before) < 0.3 and c.process_mode == Node.PROCESS_MODE_DISABLED,
		"the town's controller is paused where the child stood (%.2f m from before the press)" % _stand.distance_to(before))
	await wait(1.4)
	check(park.cam.current and park.kid.avatar == main.world.kids[Session.my_id].avatar, "the Workshop shows the player's own child")
	check(not main.world.visible and not hud.visible, "the town and its HUD are put away meanwhile")
	await _safe_check("in the Workshop", [park.label, park.hint_panel, park.action, park.home_action] + park.cards)
	await _shot("workshop")
	var line = park.lines[0]
	if tv:
		await _joy(main.pad.confirm_button())
	else:
		await _touch_button(park.cards[0])
	check(line.moving and park.kid.get_parent() == line.cars[0], "a quick boarding seats the child on %s" % line.title)
	var t := 0.0
	while line.moving and t < 120.0:
		await wait(0.25)
		t += 0.25
	check(not line.moving, "the lap ends at the platform")
	if tv:
		await _joy(main.pad.confirm_button())
	else:
		await _touch_button(park.action)
	check(not park.active and park.kid.get_parent() == park and park.nearby() == line, "off the train onto the platform")
	# unified r4: home straight from the platform, no walk back to the central tram
	await frames(3)
	await _safe_check("at the Workshop's platform", [park.label, park.hint_panel, park.action, park.home_action])
	await _shot("workshop_platform")
	if tv:
		var want := "%s / %s  %s" % [main.pad.label_of(main.pad.back_button()), main.pad.label_of(JOY_BUTTON_START), tr("Ride home")]
		check(park.hint_panel.visible and park.hint.text.contains(want), "the platform's hint offers %s (%s)" % [want, park.hint.text])
		await _joy(main.pad.back_button())
	else:
		check(park.home_action.is_visible_in_tree() and park.action.is_visible_in_tree() and park.action.text == tr("Board train")
			and not park.home_action.get_global_rect().intersects(park.action.get_global_rect()),
			"the platform offers Ride home beside Board train")
		await _touch_button(park.home_action)
	check(is_instance_valid(park) and park.riding_home, "Ride home from the platform starts the shuttle")
	await until(func(): return not is_instance_valid(park), 6.0)
	check(not is_instance_valid(park), "the shuttle takes the child home from the platform")


## r3: a tap on open ground beside `p`: no item, no animal, no landmark tag under the finger (a tap on the tram stop
## or its tag would walk there with the zoo ride pending).
func _tap_open_ground(p: Vector2) -> void:
	await settle_camera(2.0)
	var cam: Camera3D = main.rig.camera
	var spot := Vector2.INF
	var best := INF
	for dx in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5]:
		for dz in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5]:
			var q: Vector2 = p + Vector2(dx, dz)
			var aim := cam.unproject_position(Vector3(q.x, 0, q.y))
			var free: bool = main.world.pick_candidates(cam, aim).is_empty() and str(main.world.activity.pick(cam, aim)) == "" \
				and str(main.world.pick_animal(cam, aim)) == ""
			if free and q.distance_to(p) < best:
				best = q.distance_to(p)
				spot = q
	check(spot != Vector2.INF, "open ground beside the tram stop for a finger (%s)" % spot)
	if spot == Vector2.INF:
		return
	await tap_at_world(Vector3(spot.x, 0, spot.y), "the open ground beside the tram stop")
	await until(func(): return c._ctx.get("type", "") == "tram", 8.0)


## r3: a finger on a button only once it holds still (a dialog popping in, a row being refitted): the EC2 run of
## record's touch on Close landed while the "Who's here?" dialog was still animating in, and missed.
func _touch_button(button: Button) -> void:
	var last := button.get_global_rect()
	var calm := 0
	var t0 := Time.get_ticks_msec()
	while calm < 3 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
		var now := button.get_global_rect()
		calm = calm + 1 if now.is_equal_approx(last) and button.is_visible_in_tree() else 0
		last = now
	await super._touch_button(button)


## A finger held on `at` (canvas coordinates) for `sec` seconds, optionally moved by `move` px in steps, then lifted.
func finger(index: int, at: Vector2, sec: float, move := Vector2.ZERO) -> void:
	var xf := get_viewport().get_final_transform()
	var p: Vector2 = xf * at
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = p
	e.pressed = true
	Input.parse_input_event(e)
	await frames(1)
	var steps := 8
	for i in steps:
		var d := InputEventScreenDrag.new()
		d.index = index
		d.relative = move / steps
		p += move / steps
		d.position = p
		Input.parse_input_event(d)
		await frames(1)
	await wait(sec)
	var r := InputEventScreenTouch.new()
	r.index = index
	r.position = p
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


func _reef() -> void:
	await _still()
	var before: Vector2 = c.pos
	await _press(hud._reef_btn, "Explore the lantern reef")
	await until(func(): return is_instance_valid(main.reef), 4.0)
	var dive = main.reef
	check(dive != null and dive is ReefDive, "the Lantern Reef opens from the stop")
	if dive == null:
		return
	_stand = c.pos
	check(_stand.distance_to(before) < 0.3 and c.process_mode == Node.PROCESS_MODE_DISABLED,
		"the town's controller is paused where the child stood (%.2f m from before the press)" % _stand.distance_to(before))
	await frames(4)
	check(dive.child.avatar.get("nick", "") == main.world.kids[Session.my_id].avatar.get("nick", "") and dive.child.visible,
		"the reef shows the player's own child")
	check(not hud.visible and not main.world.visible and not c.enabled and main.pad.process_mode == Node.PROCESS_MODE_DISABLED,
		"the town, its HUD, the walking controls and the controller layer are paused")
	check(dive.camera.current, "the reef's follow camera is in use")
	var size := get_viewport().get_visible_rect().size
	if tv:
		# unified r4: the controller hint, in the layout's labels (a Nintendo pad: ZR / ZL, X for the view, B / + / -)
		var hint: String = dive.pad_hint_label.text
		var p: Node = main.pad
		var wants := [tr("Left stick") + "  " + tr("Swim"), tr("Right stick") + "  " + tr("Look around"),
			p.label_of_axis(JOY_AXIS_TRIGGER_RIGHT) + "  " + tr("Ascend"), p.label_of_axis(JOY_AXIS_TRIGGER_LEFT) + "  " + tr("Descend"),
			p.label_of(JOY_BUTTON_Y) + "  " + tr("Switch view"),
			"%s / %s / %s  %s" % [p.label_of(p.back_button()), p.label_of(JOY_BUTTON_START), p.label_of(JOY_BUTTON_BACK), tr("Back to town")]]
		var missing := wants.filter(func(w): return not hint.contains(w))
		check(dive.pad_hint.is_visible_in_tree() and missing.is_empty(), "the reef's controller hint shows (missing %s): %s" % [str(missing), hint.replace("\n", " | ")])
		if p.layout == "nintendo":
			check(hint.contains("ZR") and hint.contains("ZL") and hint.contains("X  ") and hint.contains("B / + / -"), "with the Nintendo pad's printed labels")
		check(p.role_of(JOY_BUTTON_Y) == "context" and dive.button_role(JOY_BUTTON_Y) == "context" and not ["back", "place"].has(dive.button_role(JOY_BUTTON_Y)),
			"the view button is the context button and no exit")
		await _reef_hint_bounds(dive)
	else:
		check(not dive.pad_hint.is_visible_in_tree(), "no controller hint for touch")
	# swimming
	var start: Vector3 = dive.swimmer.position
	var fwd: Vector3 = dive.look
	if tv:
		_axis(JOY_AXIS_LEFT_Y, -1.0)
		await frames(1)
		check(dive.pad_id == 0, "the reef reads the controller its events come from (device %d)" % dive.pad_id)
		await wait(0.8)
		_axis(JOY_AXIS_LEFT_Y, 0.0)
	else:
		await finger(0, Vector2(size.x * 0.25, size.y * 0.6), 0.8, Vector2(0, -90))   # press, drag up, hold, release
	await frames(2)
	var moved: Vector3 = dive.swimmer.position - start
	check(moved.dot(fwd) > 0.4, "%s swims the child forward (%.2f m along the view)" % ["the left stick" if tv else "a finger dragged up on the left half", moved.dot(fwd)])
	check(dive.touch_move == Vector2.ZERO and dive.move_touch == -1, "and the swimming stops when it is let go")
	# depth
	var y0: float = dive.swimmer.position.y
	if tv:
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await wait(0.8)
		_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	else:
		await finger(0, _reef_button(dive, "Ascend").get_global_rect().get_center(), 0.8)
	await frames(2)
	var y1: float = dive.swimmer.position.y
	if tv:
		_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
		await wait(0.8)
		_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	else:
		await finger(0, _reef_button(dive, "Descend").get_global_rect().get_center(), 0.8)
	await frames(2)
	var y2: float = dive.swimmer.position.y
	check(y1 > y0 + 0.4, "%s rises (%.2f -> %.2f m)" % ["ZR" if tv else "Ascend held", y0, y1])
	check(y2 < y1 - 0.4, "%s sinks (%.2f -> %.2f m)" % ["ZL" if tv else "Descend held", y1, y2])
	check(dive.touch_lift == 0.0, "and the depth holds once let go")
	await _shot("reef_depth")
	# the camera
	var yaw0: float = dive.yaw
	var cam0: Vector3 = dive.camera.global_position
	if tv:
		_axis(JOY_AXIS_RIGHT_X, 1.0)
		await wait(0.5)
		_axis(JOY_AXIS_RIGHT_X, 0.0)
	else:
		await finger(1, Vector2(size.x * 0.72, size.y * 0.45), 0.1, Vector2(-160, 0))   # a drag on the right half looks
	await frames(2)
	check(absf(wrapf(dive.yaw - yaw0, -PI, PI)) > 0.2 and dive.camera.global_position.distance_to(cam0) > 0.2,
		"%s turns the follow camera around the child (%.2f rad)" % ["the right stick" if tv else "a drag on the right half", wrapf(dive.yaw - yaw0, -PI, PI)])
	check(dive.child.visible and dive.camera.global_position.distance_to(dive.swimmer.position) > 1.15, "the child stays in view of the follow camera")
	var v0: int = dive.view_mode
	if tv:
		await _joy(JOY_BUTTON_Y)   # PadInput's context button: the one the hint names (X on a Nintendo pad)
	else:
		await _touch_button(dive.view_button)
	check(dive.view_mode == (v0 + 1) % 4 and is_instance_valid(main.reef), "the view changes and the dive stays (%s)" % dive.view_button.text)
	if tv:
		await _joy(main.pad.confirm_button())
		check(is_instance_valid(main.reef) and dive.view_mode == (v0 + 1) % 4, "confirm neither changes the view nor leaves")
	await _safe_check("in the reef", dive.controls.find_children("*", "Button", true, false) + [dive.pad_hint, dive.touch_hint])
	await _shot("reef")
	if tv:
		await _joy(JOY_BUTTON_START)   # the reef's controller return
	else:
		var back := _reef_button(dive, "Back")
		check(back != null, "the reef's Back button")
		if back:
			await _touch_button(back)
	await until(func(): return main.reef == null, 4.0)
	await frames(2)
	check(main.reef == null and not is_instance_valid(dive), "back from the reef")


## unified r5 (Mac's rendered r4 frame: the reef's hint ran off the right edge; the test had checked only that it
## showed and what it said): in every language the whole panel and every line of its text lie inside the TV's safe
## area and the screen, clear of the Back / view buttons, and nothing is cut (the label is at least its own minimum
## size, every wrapped line shown). Layouts: this run's (--pad-layout); the tour runs with nintendo and standard.
func _reef_hint_bounds(dive: Node) -> void:
	var before: String = I18n.current
	for loc in ["en", "de", "zh-CN", "ja", "fr", "es"]:
		I18n.set_locale(loc, false)
		await frames(4)   # the hint is rebuilt and fitted a frame later (deferred), then laid out
		var panel: Control = dive.pad_hint
		var label: Label = dive.pad_hint_label
		var safe_r: Rect2 = dive.safe.get_global_rect()
		var screen: Rect2 = get_viewport().get_visible_rect()
		var pr := panel.get_global_rect()
		var lr := label.get_global_rect()
		var top: Rect2 = dive.top_row.get_global_rect() if dive.top_row else Rect2()
		var lines_ok := label.get_line_count() <= maxi(1, label.get_visible_line_count()) and label.visible_characters < 0
		var whole := label.size.x + 0.5 >= label.get_combined_minimum_size().x and label.size.y + 0.5 >= label.get_combined_minimum_size().y
		check(panel.is_visible_in_tree() and safe_r.encloses(pr) and screen.encloses(pr) and pr.encloses(lr) and not pr.intersects(top)
			and lines_ok and whole and label.text.contains(tr("Back to town")),
			"[%s %s] the reef's controller hint lies whole inside the TV safe area (panel %s in %s; %d lines; clear of %s)" % [loc, main.pad.layout, pr, safe_r, label.get_line_count(), top])
	I18n.set_locale(before, false)
	await frames(4)


func _reef_button(dive: Node, text: String) -> Button:
	for b in dive.controls.find_children("*", "Button", true, false):
		if (b as Button).text == text or (b as Button).text == tr(text):
			return b
	return null


var _thousand_focus: Array = []


func _thousand() -> void:
	_journeys.clear()
	if tv:
		await pad_press_button_no_confirm(hud._context_alt3_btn, "Ride to Thousand Town")
	_thousand_focus = _focus_before()
	await _tram_ready()
	await _press(hud._context_alt3_btn, "Ride to Thousand Town")
	var arrived := await until(func(): return c.space == Places.THOUSAND and c.journey_to == "", 20.0)
	check(arrived, "Ride to Thousand Town arrives in Thousand Town")
	if not arrived:
		return
	await frames(6)
	check(main.rig.on_thousand and hud._thousand_time.visible and hud._ride_home.is_visible_in_tree(),
		"the follow camera and Thousand Town's HUD (time buttons, Ride home)")
	check(not hud._workshop_btn.is_visible_in_tree() and not hud._reef_btn.is_visible_in_tree(), "no town-stop entries in Thousand Town")
	await _card_gone("the arrival in Thousand Town")
	# unified r6 (Apple TV feedback): the main world's own actions are not offered here, so they are neither shown,
	# nor D-pad stops, nor tappable; the actions every map has stay
	var main_only := {"Pets": hud._pets_btn, "Story": hud._story_btn, "Hello": hud._echo_btn, "the lantern scrapbook": hud._lantern_btn, "Decorate": hud._decorate_btn}
	var shown := []
	var stops := []
	var ts: Array = main.pad.targets(true) if main.pad else []
	for k in main_only:
		if (main_only[k] as Control).is_visible_in_tree():
			shown.append(k)
		if ts.has(main_only[k]):
			stops.append(k)
	check(shown.is_empty() and stops.is_empty(), "Thousand Town offers none of the main world's own actions (shown %s, D-pad stops %s)" % [str(shown), str(stops)])
	check(hud._guide_btn.is_visible_in_tree() and hud._dress_btn.is_visible_in_tree() and hud._emotes.is_visible_in_tree()
		and hud._thousand_time_btns["day"].is_visible_in_tree(), "it keeps Activities, Dress up, the emotes and its own time buttons")
	await _safe_check("in Thousand Town", _hud_controls())
	await _shot("thousand")
	await _street()
	# Night by the time button
	if tv:
		await pad_press_button(hud._thousand_time_btns["night"], "Night")
	else:
		await _touch_button(hud._thousand_time_btns["night"])
	var tn := get_node_or_null("/root/Thousand")
	var held := await until(func(): return tn != null and str(tn.states.get("mode", "")) == "night", 4.0)
	await wait(0.6)
	var l: Dictionary = main.world.thousand_world.light
	check(held and float(l.get("daylight", 1.0)) < 0.05 and float(l.get("lamps", 0.0)) > 0.5 and int(l.get("windows_lit", 0)) > 0,
		"Night: the town's time held at night, lamps on and windows lit (daylight %.2f, lamps %.2f, %d windows)" % [float(l.get("daylight", -1)), float(l.get("lamps", -1)), int(l.get("windows_lit", -1))])
	await _shot("thousand_night")
	await _tram_ready()
	if tv:
		await pad_press_button(hud._ride_home, "Ride home")
	else:
		await _touch_button(hud._ride_home)
	var home := await until(func(): return c.space == "town" and c.journey_to == "", 20.0)
	check(home, "Ride home returns to the town")
	check(not main.rig.on_thousand and not hud._thousand_time.visible, "the town's camera and HUD again")


## A street interaction in Thousand Town: "Who's here?" at a building's door, as the simulation says it now.
func _street() -> void:
	var tw: Node3D = main.world.thousand_world
	var cam: Camera3D = main.rig.camera
	var asked := ""
	if tv:
		for w: Vector2 in TO_COURTYARD + [tw.door_point(COURTYARD)]:
			await _stick_to(w, 0.6)
		await until(func(): return c._ctx.get("type", "") == "thousand_inspect", 3.0)
		check(c._ctx.get("type", "") == "thousand_inspect", "at a door the action button offers Who's here? (%s)" % hud._context_btn.text)
		asked = str(c._ctx.get("id", ""))
		await act()   # Y: the context action
	else:
		# Courtyard Housing, the nearest building with a door: the finger walks the child there by taps on the street
		# (the camera turned toward each by a drag), then taps the building's front; the child walks to its door and
		# asks who is there.
		var best: Dictionary = {}
		for site: Dictionary in tw.sites():
			if str(site.get("id", "")) == COURTYARD:
				best = site
		check(not best.is_empty() and best.get("door") is Vector2, "Courtyard Housing and its door")
		if best.is_empty():
			return
		for w: Vector2 in TO_COURTYARD:
			await _tap_walk(w)
		check(c.pos.distance_to(TO_COURTYARD[-1]) < 1.5, "taps on the street walk the child to Courtyard Housing (%s)" % c.pos)
		var target: Vector2 = (best.rect as Rect2).get_center()
		var d: Vector2 = target - c.pos
		var want := atan2(-d.x, -d.y)   # the follow camera behind the child, looking at the building
		var dx: float = wrapf(main.rig.t_yaw - want, -PI, PI) / float(main.rig.T_ORBIT_PER_PX)
		var size := get_viewport().get_visible_rect().size
		await mouse_drag(Vector2(size.x * 0.5, size.y * 0.55), Vector2(size.x * 0.5 + dx, size.y * 0.55))
		await wait(0.5)
		var aim := Vector2(-1, -1)
		var people: Node = main.world.thousand_people
		for yy in range(8, 2, -1):
			for xx in range(1, 20):
				if aim.x >= 0.0:
					continue
				var p := Vector2(size.x * xx / 20.0, size.y * yy / 10.0)
				if not playable_rect().has_point(p) or ui_blocker_at(p) != "":
					continue
				if people and people.has_method("pick_screen") and people.pick_screen(cam, p) >= 0:
					continue
				# r6: the building the game itself takes for a tap there (PlayController.thousand_tap_target)
				if str((c.thousand_tap_target(p).get("site", {}) as Dictionary).get("id", "")) == str(best.id):
					aim = p
		asked = str(best.id)
		check(aim.x >= 0.0, "%s is in view for a finger after the drag turned the camera" % asked)
		if aim.x >= 0.0:
			print("DIAG tap %s on %s from %s" % [aim.round(), asked, c.pos])
			await tap(aim)
	var opened := await until(func(): return hud.thousand_inspect_panel() != null, 30.0)
	check(opened, "%s opens Who's here? for %s" % ["Y at the door" if tv else "the tap", asked])
	if not opened:
		return
	var panel: Node = hud.thousand_inspect_panel()
	check(str(panel.get_meta("building", "")) == asked and (panel.get_node("Status") as Label).text != "",
		"it says how many people are in %s now (%s)" % [asked, (panel.get_node("Status") as Label).text])
	await _shot("thousand_whos_here")
	if tv:
		await _joy(main.pad.back_button())
	else:
		var close: Button = null
		for bt in hud._overlay.find_children("*", "Button", true, false):
			if (bt as Button).is_visible_in_tree() and (bt as Button).text == "Close":
				close = bt
		if close:
			await _touch_button(close)
	check(await until(func(): return hud.thousand_inspect_panel() == null, 3.0), "%s closes it" % ("B" if tv else "Close"))


## Turns the follow camera toward `p` with a finger drag, then taps the street there; waits for the walk.
func _tap_walk(p: Vector2) -> void:
	var cam: Camera3D = main.rig.camera
	var size := get_viewport().get_visible_rect().size
	if (p - c.pos).length() < 0.8:
		return
	# r2: on the Mac's rendered run the first target was aimed while the follow camera was still swinging in after the
	# arrival (it projected at (-528, 862)); the finger now waits for the camera to settle before aiming, and turns it
	# again if the street is still not in view (at most three tries, each a real drag).
	var h: float = main.world.thousand_height(p)
	var aim := Vector2(-1, -1)
	var ok_aim := false
	for attempt in 3:
		await _settle_follow()
		var d: Vector2 = p - c.pos
		var want := atan2(-d.x, -d.y)
		var dx: float = wrapf(main.rig.t_yaw - want, -PI, PI) / float(main.rig.T_ORBIT_PER_PX)
		if absf(dx) > 20.0:
			await mouse_drag(Vector2(size.x * 0.5, size.y * 0.55), Vector2(size.x * 0.5 + dx, size.y * 0.55))
			await _settle_follow()
		aim = cam.unproject_position(Vector3(p.x, h, p.y))
		ok_aim = not cam.is_position_behind(Vector3(p.x, h, p.y)) and playable_rect().has_point(aim) and ui_blocker_at(aim) == ""
		if ok_aim:
			break
		print("DIAG street %s not in view yet (%s), try %d" % [p, aim.round(), attempt + 1])
	check(ok_aim, "the street at %s is in view for a finger (%s)" % [p, aim.round()])
	if not ok_aim:
		return
	await tap(aim)
	await until(func(): return c._walk_target == null or c.pos.distance_to(p) < 0.5, 12.0)
	await _still()


## r2: the travel card fades out over 0.35 s after a journey; the arrival and home pictures waited for it only to
## start fading (the Mac's r1 frames showed it dissolving). Wait until it has fully left (hidden by its tween), then a
## drawn frame, so those pictures document the restored HUD.
func _card_gone(what: String) -> void:
	var gone := func() -> bool:
		var card: Control = hud._journey_card
		return card == null or not card.visible
	var ok: bool = await until(gone, 4.0)
	await frames(2)
	if not main.args.has("no-shots"):
		await RenderingServer.frame_post_draw
	check(ok and gone.call() and hud.visible, "after %s the travel card has left the screen and the HUD shows" % what)


## Waits (at most 4 s) until the follow camera holds still for three frames in a row (no glide, no swing).
func _settle_follow() -> void:
	var cam: Camera3D = main.rig.camera
	var last: Transform3D = cam.global_transform
	var calm := 0
	var t0 := Time.get_ticks_msec()
	while calm < 3 and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		var now: Transform3D = cam.global_transform
		var still: bool = now.origin.distance_to(last.origin) < 0.01 and now.basis.z.angle_to(last.basis.z) < 0.003 \
			and not (main.rig.has_method("thousand_gliding") and main.rig.thousand_gliding())
		calm = calm + 1 if still else 0
		last = now


## Waits (at most 4 s) until the child stands still: no walk under way and the same place for five frames.
func _still() -> void:
	var last: Vector2 = c.pos
	var calm := 0
	var t0 := Time.get_ticks_msec()
	while calm < 5 and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		var now: Vector2 = c.pos
		calm = calm + 1 if c._walk_target == null and now.distance_to(last) < 0.001 else 0
		last = now


## A finger drag as the mouse events the game takes from a finger (Thousand Town: a drag orbits the follow camera).
func mouse_drag(a: Vector2, b: Vector2, steps := 12) -> void:
	var xf := get_viewport().get_final_transform()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = xf * a
	e.pressed = true
	Input.parse_input_event(e)
	await frames(1)
	var last := a
	for i in steps:
		var p := a.lerp(b, float(i + 1) / steps)
		var m := InputEventMouseMotion.new()
		m.position = xf * p
		m.relative = p - last
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = p
		Input.parse_input_event(m)
		await frames(1)
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.position = xf * b
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


## The left stick toward a point in Thousand Town, relative to the follow camera (bounded by game time).
## unified r6 (the Mac's uncapped display: a frame-count budget ran out in less game time than the walk needs): the
## budget is 900 physics steps (15 s of game time at 60 Hz) and 120 s of wall time, whatever the frame rate.
func _stick_to(p: Vector2, tol: float) -> void:
	var steps := [0]
	var tick := func(): steps[0] += 1
	get_tree().physics_frame.connect(tick)
	var t0 := Time.get_ticks_msec()
	while steps[0] < 900 and Time.get_ticks_msec() - t0 < 120000:
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
	await frames(2)


func _done() -> void:
	print("STATION TOUR %s: %d checks, %d failures" % [tag, _checks, failures])
	Music.quit_game(1 if failures else 0)
