## tv-diag audit r2: a controller-only usability AUDIT of the Apple TV route (design/tv-controller.md). It walks
## the route a child takes with one Switch Pro Controller and records what the screen offers at every step; it
## never fails on a finding (findings are for the source owner to judge), only on a step it could not carry out.
##   title -> Play -> (B back, Play again) -> Let's go! -> the town -> the left stick to the tram stop -> Y: Ride to
##   the city -> the city: the left stick, R / L, the right stick, ZL / ZR, Look (D-pad to it, A, D-pad steps, B),
##   Reset view, the cafe seat (X Sit down, B, the stick while seated, X Stand up), the weather buttons (D-pad, A),
##   Decorate unreachable (every controller button and every HUD button), Ride home (D-pad, A) -> the town again,
##   Decorate there (D-pad, A, B).
## Input: only synthetic joypad events (Input.parse_input_event), each tagged at its source with the meta
## "synthetic". No taps, no mouse, no direct calls that move the child or press a button. State is only read,
## except the test's own save file (the Play button's solo start is pointed at it, as tests/tv_tour.gd does).
## Each step prints "AUDIT <step> <kind> <json>"; findings print "AUDIT FINDING ..."; the run ends with
## "TV ROUTE AUDIT: N steps, F findings, E errors" and exits 0 when it reached the end without errors.
##   scripts/godot.sh --headless --path game -- --driver=res://tests/tv_route_audit.gd --tv --pad-layout=nintendo \
##       --window=1920x1080 --no-shots [--pad-trace] [--first-steps]
## Headless: this shows logic, focus targets, hint texts and rectangles, and states. It cannot show feel, timing,
## the renderer's picture, the physical letters printed on a controller, or what tvOS does with a press.
extends "res://tests/pets_tour.gd"

const TvMode := preload("res://scripts/core/tv_mode.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const Places := preload("res://scripts/core/places.gd")
const SAVE := "user://tv_route_audit_town.json"
const DEV := 0
const DIRS := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
const DPAD := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}
## HUD buttons the Decorate sweep does not press: they leave the place (or, headless, wait for a drawn frame).
const SWEEP_SKIP := ["Leave town", "Ride home", "Take a photo"]

var pad: Node
var ctrl: Node
var hd: Control
var _steps := 0
var _step := "S00.start"
var _findings := {}        # key -> {"sev", "what", "steps": [], "evidence"}
var _order: Array = []     # finding keys in the order first seen
var _errors := 0
var _events: Array = []
var _finished := false
var _modals_seen := {}     # dialog name -> "closed by B" / "NOT closed by B"


# ------------------------------------------------------------- reporting

func step(name: String) -> void:
	_steps += 1
	_step = "S%02d.%s" % [_steps, name]
	print("AUDIT %s begin" % _step)


func audit(kind: String, data: Dictionary) -> void:
	print("AUDIT %s %s %s" % [_step, kind, JSON.stringify(data)])


## A finding: deduplicated by key; every step it showed in is listed.
func finding(key: String, sev: String, what: String, evidence: Variant = null) -> void:
	if not _findings.has(key):
		_findings[key] = {"sev": sev, "what": what, "steps": [], "evidence": evidence}
		_order.append(key)
		print("AUDIT FINDING %s [%s] %s: %s %s" % [key, sev, _step, what, JSON.stringify(evidence) if evidence != null else ""])
	(_findings[key]["steps"] as Array).append(_step)


## A step the driver could not carry out (a script or route error, not a usability finding).
func error(what: String) -> void:
	_errors += 1
	print("AUDIT ERROR %s %s" % [_step, what])


# ------------------------------------------------------------- controller input (synthetic, tagged)

func joy(b: int, pressed: bool) -> void:
	if _finished:
		return
	var e := InputEventJoypadButton.new()
	e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
	e.device = DEV
	e.button_index = b
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func btn(b: int) -> void:
	joy(b, true)
	await frames(2)
	joy(b, false)
	await frames(3)


func axis(a: int, v: float) -> void:
	if _finished:
		return
	var e := InputEventJoypadMotion.new()
	e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
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
	await frames(3)


func trigger(a: int) -> void:
	axis(a, 1.0)
	await frames(3)
	axis(a, 0.0)
	await frames(3)


## The Godot button of a printed Nintendo letter, as the controller layer maps it now.
func phys(label: String) -> int:
	match label:
		"A": return pad.confirm_button()
		"B": return pad.back_button()
		"X": return JOY_BUTTON_Y
		"Y": return JOY_BUTTON_X
		"+": return JOY_BUTTON_START
		"L": return JOY_BUTTON_LEFT_SHOULDER
		"R": return JOY_BUTTON_RIGHT_SHOULDER
	return -1


# ------------------------------------------------------------- reading state

func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


func _r(r: Rect2) -> Array:
	return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]


func _nm(t: Variant) -> String:
	if t == null or not is_instance_valid(t):
		return ""
	var ctl := t as Control
	if ctl is Button and (ctl as Button).text != "":
		return (ctl as Button).text
	if ctl.tooltip_text != "":
		return ctl.tooltip_text
	return str(ctl.name)


## Apple's title-safe area of this screen (tv_mode.gd).
func tv_safe() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	return Rect2(vs.x * TvMode.SAFE_X, vs.y * TvMode.SAFE_Y, vs.x * (1.0 - 2.0 * TvMode.SAFE_X), vs.y * (1.0 - 2.0 * TvMode.SAFE_Y))


func _dialogs() -> Array:
	var out := []
	for ch in hd._overlay.get_children():
		if ch.is_queued_for_deletion():
			continue
		var title := ""
		for l in ch.find_children("*", "Label", true, false):
			if (l as Label).is_visible_in_tree() and (l as Label).text.strip_edges() != "":
				title = (l as Label).text.left(40)
				break
		out.append("%s(%s)" % [ch.name, title])
	return out


## Which start screen shows (the menus have no names for them): the first of its telling buttons.
func _menu_screen() -> String:
	if not main.menus.visible:
		return ""
	for t in ["Let's go!", "Play", "Join"]:
		if _button(main.menus, t) != null:
			return {"Let's go!": "character", "Play": "title", "Join": "friends"}[t]
	return "other"


func state() -> Dictionary:
	var kid: Node3D = main.world.local_kid() if main.world else null
	var s := {"menus": main.menus.visible, "hud": hd.visible, "modal": pad.is_modal(), "space": ctrl.space, "mode": ctrl.mode,
		"level": ctrl.level, "pos": _v(ctrl.pos), "walk": ctrl._walk_target != null, "journey": ctrl.journey_to,
		"ctx": str(ctrl._ctx.get("type", "")), "ctx_label": str(ctrl._ctx.get("label", "")),
		"alt": str((ctrl._ctx.get("alt", {}) as Dictionary).get("label", "")), "hold": str(ctrl.city_hold.get("key", "")),
		"looking": ctrl.city_looking, "look": str(main.rig.city_look), "paused": ctrl.city_paused,
		"catalog": hd._catalog.visible, "decorate_btn": hd._decorate_btn.is_visible_in_tree(),
		"dialogs": _dialogs(), "anim": str(kid.get("anim")) if kid else "", "menu_screen": _menu_screen()}
	if main.rig.on_city:
		var cs: Dictionary = main.rig.city_state
		s["cam"] = {"city": true, "yaw": roundi(rad_to_deg(float(cs.get("yaw", 0.0)))), "dist": snappedf(float(cs.get("distance", 0.0)), 0.1),
			"out": bool(cs.get("out", false))}
	else:
		s["cam"] = {"city": false, "yaw_step": main.rig.yaw_step, "zoom": main.rig.zoom}
	var city := get_node_or_null("/root/City")
	if city and ctrl.space == Places.CITY and (city.states as Dictionary).has("weather"):
		s["weather"] = CityMap.WEATHERS[clampi(int(city.states["weather"]), 0, CityMap.WEATHERS.size() - 1)]
	return s


## What changed between two states (the position only beyond 0.25 m).
func diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := {}
	for k in b:
		if k == "pos":
			if Vector2(a["pos"][0], a["pos"][1]).distance_to(Vector2(b["pos"][0], b["pos"][1])) > 0.25:
				d["pos"] = [a["pos"], b["pos"]]
		elif not a.has(k) or str(a[k]) != str(b[k]):
			d[k] = [a.get(k), b[k]]
	return d


## The D-pad / pointer target under the pointer, and how much of it shows.
func under_pointer() -> Dictionary:
	var safe := tv_safe()
	for t in pad.targets():
		if (t as Control).get_global_rect().has_point(pad.cursor):
			var vis: Rect2 = pad._visible_rect(t)
			return {"name": _nm(t), "rect": _r(vis), "visible": vis.has_area(), "in_safe": safe.grow(0.5).encloses(vis)}
	var hov: Control = get_viewport().gui_get_hovered_control()
	return {"name": "(world)" if hov == null else "(%s)" % hov.name}


## The screen at this step: hints (parts, text, rectangle), the pointer and its target, the safe area.
func screen(what: String) -> Dictionary:
	await wait(0.35)   # the hints are placed every frame; the text follows the state
	var parts: Array = pad.hint_parts()
	var hr: Rect2 = pad.hint_rect()
	var safe := tv_safe()
	var area: Rect2 = pad._area()
	var over_btn: Array = pad.targets(true).filter(func(t): return (pad._visible_rect(t) as Rect2).intersects(hr)).map(func(t): return _nm(t))
	var over_txt: int = pad.readable_rects().filter(func(r): return (r as Rect2).intersects(hr)).size()
	var under := under_pointer()
	var d := {"what": what, "hint_text": pad._hint_label.text, "parts": parts, "hint_rect": _r(hr),
		"hint_shown": pad._hint_panel.visible and pad.shown and pad.visible, "hint_in_safe": safe.grow(0.5).encloses(hr),
		"hint_over_buttons": over_btn, "hint_over_texts": over_txt, "pointer": _v(pad.cursor),
		"pointer_shown": pad._cursor_node.visible and pad.visible, "pointer_in_safe": safe.has_point(pad.cursor), "under_pointer": under,
		"hud_area": _r(area), "tv_safe": _r(safe), "state": state()}
	var bad := label_problems(parts)
	d["label_problems"] = bad
	audit("screen", d)
	if not d["hint_shown"] and ctrl.journey_to == "":
		finding("hints_hidden_" + what, "awkward", "the controller hints are not shown at '%s'" % what)
	if d["hint_shown"] and not d["hint_in_safe"]:
		finding("hints_outside_safe", "awkward", "the hint bar leaves the TV title-safe area", {"hint": d["hint_rect"], "safe": d["tv_safe"]})
	if d["hint_shown"] and not over_btn.is_empty():
		finding("hints_over_button", "awkward", "the hint bar covers a button", {"buttons": over_btn, "hint": d["hint_rect"]})
	if d["hint_shown"] and over_txt > 0:
		finding("hints_over_text", "cosmetic", "the hint bar covers readable text", {"texts": over_txt, "hint": d["hint_rect"]})
	if under.has("visible") and (not under["visible"] or not under["in_safe"]):
		finding("target_outside_safe_" + str(under["name"]), "awkward", "the button under the pointer is not fully inside the TV safe area", under)
	if not bad.is_empty():
		finding("label_mismatch", "blocker", "a hint names the wrong controller letter", bad)
	if not area.grow(0.5).encloses(safe) and not safe.grow(0.5).encloses(area):
		finding("hud_area_not_safe", "cosmetic", "the HUD's area is not Apple's title-safe area", {"hud": d["hud_area"], "safe": d["tv_safe"]})
	return d


## Each hint's letter against the Nintendo layout: A confirm, B back, X the context action, Y the second
## action or turning, + place, L R the camera.
func label_problems(parts: Array) -> Array:
	var want := {"Select": "A", "Back": "B", "Done": "B", "Cancel": "B", "Turn camera": "L R", "Pointer": tr("Right stick"),
		"Move": tr("Left stick"), "Turn": "Y", "Place here": "+", "Jump to buttons": tr("D-pad"),
		# tv-diag r2: the Look hints (pad_input.gd hint_parts while city_looking)
		"Stop looking": "B", "Look around": tr("D-pad")}
	if hd._context_btn.is_visible_in_tree():
		want[str(hd._context_btn.text)] = "X"
	if hd._context_alt_btn.is_visible_in_tree():
		want[str(hd._context_alt_btn.text)] = "Y"
	var out := []
	for p in parts:
		if not want.has(str(p[1])):
			out.append("unknown hint %s %s" % [p[0], p[1]])
		elif want[str(p[1])] != str(p[0]):
			out.append("%s shown as %s, wanted %s" % [p[1], p[0], want[str(p[1])]])
	return out


## Presses a button and reports what changed, flagging changes outside `expect` (keys of state()).
func push(label: String, expect: Array, settle := 0.6) -> Dictionary:
	var s0 := state()
	_events.clear()
	var b := phys(label)
	await btn(b)
	await wait(settle)
	var s1 := state()
	var d := diff(s0, s1)
	var unexpected := d.keys().filter(func(k): return not expect.has(k) and k != "anim")
	audit("press", {"label": label, "godot_button": b, "role": pad.role_of(b), "changed": d, "events": _events.duplicate(),
		"expected": expect, "unexpected": unexpected})
	return {"changed": d, "unexpected": unexpected, "events": _events.duplicate(), "before": s0, "after": s1}


## B at this step: what it does, and whether that is ever destructive or surprising.
func probe_b(what: String, expect: Array) -> Dictionary:
	var r := await push("B", expect)
	var d: Dictionary = r["changed"]
	var kind := "nothing" if d.is_empty() else ",".join(d.keys())
	audit("b_probe", {"what": what, "effect": kind, "changed": d})
	if not (r["unexpected"] as Array).is_empty():
		finding("b_unexpected_" + what, "awkward", "B at '%s' changed %s" % [what, r["unexpected"]], d)
	for k in ["journey", "space", "mode", "catalog"]:
		if d.has(k) and not expect.has(k):
			finding("b_destructive_" + what, "blocker", "B at '%s' changed %s" % [what, k], d)
	return r


# ------------------------------------------------------------- pointer navigation (D-pad first, then the right stick)

## Mirrors PadInput.snap's choice (along + 2.5 * |cross|, at least 8 px along, not the target under the point).
func _snap_from(ts: Array, from: Vector2, dir: Vector2) -> Control:
	var best: Control = null
	var best_score := INF
	for t in ts:
		var center: Vector2 = (t as Control).get_global_rect().get_center()
		var d := center - from
		var along := d.dot(dir)
		if along < 8.0 or (t as Control).get_global_rect().has_point(from):
			continue
		var score := along + 2.5 * absf(d.cross(dir))
		if score < best_score:
			best_score = score
			best = t
	return best


## The D-pad graph of the targets on screen now, and which targets the D-pad alone reaches from the pointer.
func dpad_map(what: String, dirs: Array = ["up", "down", "left", "right"]) -> Dictionary:
	var ts: Array = pad.targets()
	var graph := {}
	var seen := {}
	var off_axis := []
	var todo: Array = []
	for dn in dirs:
		var first := _snap_from(ts, pad.cursor, DIRS[dn])
		if first and not seen.has(first):
			seen[first] = true
			todo.append(first)
	for t in pad.targets():
		if (t as Control).get_global_rect().has_point(pad.cursor) and not seen.has(t):
			seen[t] = true
			todo.append(t)
	while not todo.is_empty():
		var t: Control = todo.pop_front()
		var row := {}
		for dn in dirs:
			var n := _snap_from(ts, t.get_global_rect().get_center(), DIRS[dn])
			row[dn] = _nm(n)
			if n:
				var dv: Vector2 = n.get_global_rect().get_center() - t.get_global_rect().get_center()
				if absf(dv.cross(DIRS[dn])) > 4.0 * dv.dot(DIRS[dn]):
					off_axis.append("%s %s -> %s (%d px %s, %d px sideways)" % [_nm(t), dn, _nm(n), roundi(dv.dot(DIRS[dn])), dn, roundi(absf(dv.cross(DIRS[dn])))])
			if n and not seen.has(n):
				seen[n] = true
				todo.append(n)
		graph["%s@%s" % [_nm(t), _r(t.get_global_rect())]] = row
	var unreached: Array = ts.filter(func(t): return not seen.has(t)).map(func(t): return _nm(t))
	var names: Array = ts.map(func(t): return _nm(t))
	audit("dpad_map", {"what": what, "targets": names, "count": ts.size(), "unreached": unreached, "off_axis": off_axis, "graph": graph})
	if not off_axis.is_empty():
		finding("dpad_off_axis", "awkward", "some D-pad presses jump almost sideways (more than 76 degrees off the pressed direction; PadInput.snap accepts any target at least 8 px that way), first seen at '%s'" % what, off_axis)
		audit("dpad_off_axis", {"what": what, "jumps": off_axis})
	if not unreached.is_empty():
		finding("dpad_unreached_" + what, "awkward", "at '%s' the D-pad alone never reaches %s (only the right stick does)" % [what, unreached], {"targets": names})
	return {"targets": names, "unreached": unreached}


## Brings the pointer onto a control like a child would (tests/tv_tour.gd go_to): the D-pad first, the right
## stick when the D-pad goes elsewhere. lr=false keeps off D-pad left / right (they step places while looking).
func go_to(target: Control, what: String, lr := true) -> Dictionary:
	var res := {"what": what, "ok": false, "dpad": 0, "stick": false, "path": []}
	if target == null or not target.is_visible_in_tree():
		res["why"] = "not on screen"
		audit("go_to", res)
		return res
	for i in 12:
		var r := target.get_global_rect()
		if r.has_point(pad.cursor):
			break
		var d: Vector2 = r.get_center() - pad.cursor
		var dn: String
		if absf(d.x) > absf(d.y) and lr:
			dn = "right" if d.x > 0 else "left"
		else:
			dn = "down" if d.y > 0 else "up"
		var before: float = pad.cursor.distance_to(r.get_center())
		await btn(DPAD[dn])
		await frames(3)
		res["dpad"] += 1
		(res["path"] as Array).append("%s->%s" % [dn, under_pointer()["name"]])
		if pad.cursor.distance_to(target.get_global_rect().get_center()) >= before - 1.0:
			break
	if not target.get_global_rect().has_point(pad.cursor):
		res["stick"] = true
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 5000:
			if not is_instance_valid(target) or not target.is_visible_in_tree():
				break
			var r2 := target.get_global_rect()
			if r2.has_point(pad.cursor):
				break
			var d2: Vector2 = r2.get_center() - pad.cursor
			var v := d2.normalized() * clampf(d2.length() / 260.0, 0.4, 1.0)
			axis(JOY_AXIS_RIGHT_X, v.x)
			axis(JOY_AXIS_RIGHT_Y, v.y)
			await frames(1)
		axis(JOY_AXIS_RIGHT_X, 0.0)
		axis(JOY_AXIS_RIGHT_Y, 0.0)
		await frames(3)
	res["ok"] = is_instance_valid(target) and target.get_global_rect().has_point(pad.cursor)
	res["in_safe"] = tv_safe().grow(0.5).encloses(target.get_global_rect()) if is_instance_valid(target) else false
	audit("go_to", res)
	var tag_names: Array = hd._tags.values().map(func(b): return (b as Button).text)
	var via_tag: bool = (res["path"] as Array).any(func(step): return tag_names.has(str(step).split("->")[-1]))
	if res["ok"] and res["stick"] and not what.begins_with("sweep "):
		if via_tag:
			finding("tag_detour_" + what, "awkward", "pressing the D-pad toward '%s' detours through a world name tag and loops, so the pointer never gets there by the D-pad (the right stick had to)" % what, res["path"])
		else:
			finding("stick_needed_" + what, "awkward", "pressing the D-pad toward '%s' does not get there; the right stick had to steer the pointer" % what, res["path"])
	if res["ok"] and not res["in_safe"]:
		finding("outside_safe_" + what, "awkward", "'%s' is not inside the TV safe area" % what, _r(target.get_global_rect()))
	return res


## The pointer onto open world (no HUD target under it) near the screen centre, by the right stick.
func pointer_to_world() -> void:
	var goal := tv_safe().get_center() + Vector2(0, -120)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		if pad.cursor.distance_to(goal) < 20.0:
			break
		var d: Vector2 = goal - pad.cursor
		var v := d.normalized() * clampf(d.length() / 260.0, 0.4, 1.0)
		axis(JOY_AXIS_RIGHT_X, v.x)
		axis(JOY_AXIS_RIGHT_Y, v.y)
		await frames(1)
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_RIGHT_Y, 0.0)
	await frames(3)


# ------------------------------------------------------------- walking with the left stick

## Town: steered toward the goal as it shows on screen (stick up is screen up), as tests/zoo_tour.gd does.
func walk_town(p: Vector2) -> bool:
	var cam: Camera3D = main.rig.camera
	for i in 900:
		if ctrl.pos.distance_to(p) < 0.6:
			break
		var a := cam.unproject_position(Vector3(ctrl.pos.x, 0, ctrl.pos.y))
		var b := cam.unproject_position(Vector3(p.x, 0, p.y))
		var v := (b - a).normalized() * (1.0 if ctrl.pos.distance_to(p) > 1.5 else 0.7)
		axis(JOY_AXIS_LEFT_X, v.x)
		axis(JOY_AXIS_LEFT_Y, v.y)
		await frames(1)
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	return ctrl.pos.distance_to(p) < 1.2


## City: the stick along the city's navigation route (stairs, skywalks, doors), as tests/city_tour.gd stick_go.
func walk_city(region: String, at: Vector2) -> bool:
	var route: Array = CityNav.route(ctrl.level, ctrl.pos, region, at)
	if route.is_empty():
		return false
	var stuck := 0
	for w in route:
		var p: Vector2 = w["pos"]
		for i in 900:
			var d: Vector2 = p - ctrl.pos
			if d.length() < 0.1:
				break
			var rgt: Vector2 = main.rig.flat_right()
			var fwd: Vector2 = main.rig.flat_forward()
			var push := 1.0 if d.length() > 0.8 else 0.4
			var s := Vector2(d.normalized().dot(rgt), -d.normalized().dot(fwd)).normalized() * push
			axis(JOY_AXIS_LEFT_X, s.x)
			axis(JOY_AXIS_LEFT_Y, s.y)
			var before: Vector2 = ctrl.pos
			await frames(1)
			stuck = stuck + 1 if (ctrl.pos as Vector2).distance_to(before) < 0.002 else 0
			if stuck > 90:
				break
		if stuck > 90:
			break
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	return ctrl.level == region and (ctrl.pos as Vector2).distance_to(at) < 0.6


## Closes whatever dialog is open with B, recording whether B could (a dialog B cannot close is a dead end).
func close_with_b(what: String) -> bool:
	for i in 4:
		if not pad.is_modal() or main.menus.visible:
			return true
		var names := _dialogs()
		await btn(phys("B"))
		await wait(0.4)
		var closed: bool = not pad.is_modal() or _dialogs() != names
		for n in names:
			_modals_seen[n] = "closed by B" if closed else "NOT closed by B"
		audit("b_close", {"what": what, "dialogs": names, "closed": closed})
		if not closed:
			finding("b_dead_end_" + str(names), "blocker", "B does not close the dialog %s" % [names])
			return false
	return not pad.is_modal()


# ------------------------------------------------------------- the route

func _run() -> void:
	pad = main.pad
	ctrl = main.controller
	hd = main.hud
	get_tree().create_timer(float(main.args.get("timeout", "600"))).timeout.connect(func():
		if not _finished:
			error("the audit did not finish within %s s" % main.args.get("timeout", "600"))
			_finish(false))
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	ctrl.mode_changed.connect(func(m): _events.append("mode:" + str(m)))
	ctrl.space_changed.connect(func(s): _events.append("space:" + str(s)))
	ctrl.journey.connect(func(ph, to): _events.append("journey:%s:%s" % [ph, to]))
	ctrl.city_look_changed.connect(func(on): _events.append("look:%s" % on))
	ctrl.open_panel.connect(func(p, _d): _events.append("panel:" + str(p)))
	ctrl.hint.connect(func(t): _events.append("hint:" + str(t)))
	ctrl.toast.connect(func(t): _events.append("toast:" + str(t)))
	hd.leave_requested.connect(func(): _events.append("LEAVE_TOWN"))
	hd.photo_requested.connect(func(): _events.append("photo"))
	hd._overlay.child_entered_tree.connect(func(n): _events.append("dialog:" + str(n.name)))
	var pad_src := FileAccess.get_file_as_bytes("res://scripts/ui/pad_input.gd")
	audit("env", {"os": OS.get_name(), "tv": TvMode.active(), "engine": Engine.get_version_info()["string"],
		"window": _v(get_viewport().get_visible_rect().size), "pad_input_sha256": _sha(pad_src), "first_steps": main.args.has("first-steps"),
		"pad_trace": main.args.has("pad-trace")})
	await wait(1.0)
	var stages := [_title, _start, _town, _town_tag, _to_tram, _ride_to_city, _city_arrival, _city_walk, _city_camera, _city_look,
		_city_reset, _city_seat, _city_weather, _city_no_decorate, _ride_home, _town_again, _leave_town]
	for s in stages:
		if _finished:
			return
		var e0 := _errors
		await s.call()
		if _errors > e0:
			print("AUDIT %s stop: the route cannot go on after this step" % _step)
			break
	_finish(true)


func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()


func _title() -> void:
	step("title")
	var menus: Control = main.menus
	if not menus.visible:
		error("the game did not start at its menus")
		return
	audit("before_input", {"pointer_shown": pad._cursor_node.visible, "hints_shown": pad._hint_panel.visible, "cursor": _v(pad.cursor), "layout": pad.layout})
	await btn(JOY_BUTTON_DPAD_DOWN)
	audit("mapping", {"layout": pad.layout, "swap_ab": pad.swap_ab, "confirm": [pad.confirm_button(), pad.label_of(pad.confirm_button())],
		"back": [pad.back_button(), pad.label_of(pad.back_button())], "JOY_Y": pad.label_of(JOY_BUTTON_Y), "JOY_X": pad.label_of(JOY_BUTTON_X),
		"START": pad.label_of(JOY_BUTTON_START), "L": pad.label_of(JOY_BUTTON_LEFT_SHOULDER), "R": pad.label_of(JOY_BUTTON_RIGHT_SHOULDER)})
	if pad.layout != "nintendo" or pad.confirm_button() != JOY_BUTTON_B or pad.back_button() != JOY_BUTTON_A:
		finding("mapping", "blocker", "the Nintendo layout does not confirm on the right face button (A) and go back on the bottom one (B)",
			{"layout": pad.layout, "swap_ab": pad.swap_ab})
	await screen("title")
	await dpad_map("title")
	var b := await probe_b("title", [])
	if (b["changed"] as Dictionary).is_empty():
		finding("b_title_noop_hint", "cosmetic", "at the title the hints say 'B Back' but B does nothing (there is no Back; the Siri Remote's Menu arms Home here)")
	step("play")
	var play: Button = _button(menus, "Play")
	var g := await go_to(play, "Play")
	if not g["ok"]:
		error("the pointer did not reach Play")
		return
	await push("A", ["menus", "dialogs"])
	if not await until(func(): return _button(menus, "Let's go!") != null, 3.0):
		error("Play did not open the character screen")
		return
	await screen("character screen")
	await dpad_map("character screen")
	await probe_b("character screen", ["menu_screen"])
	if _button(menus, "Play") == null:
		finding("b_character_not_back", "awkward", "B on the character screen did not return to the title")
	else:
		audit("note", {"text": "B on the character screen returned to the title"})
		await go_to(_button(menus, "Play"), "Play")
		await push("A", [])
		await until(func(): return _button(menus, "Let's go!") != null, 3.0)


func _start() -> void:
	step("lets_go")
	var menus: Control = main.menus
	for conn in menus.play_solo.get_connections():
		menus.play_solo.disconnect(conn["callable"])
	menus.play_solo.connect(func(avatar): Session.start_solo(SAVE, avatar))   # the audit's own town, never the child's
	var go := _button(menus, "Let's go!")
	var g := await go_to(go, "Let's go!")
	if not g["ok"]:
		error("the pointer did not reach Let's go!")
		return
	await btn(phys("A"))
	if not await until(func(): return hd.visible and not menus.visible, 10.0):
		error("Let's go! did not start the town")
		return
	await wait(1.5)
	if pad.is_modal():
		await screen("welcome dialog")
		await close_with_b("welcome dialog")
	if pad.is_modal():
		error("a dialog is still open after B")


func _town() -> void:
	step("town")
	await screen("town")
	var m := await dpad_map("town")
	if not (m["targets"] as Array).has("Decorate"):
		finding("town_no_decorate", "blocker", "the town shows no Decorate for the D-pad")
	elif (m["unreached"] as Array).has("Decorate"):
		finding("town_decorate_unreached", "awkward", "Decorate is in the town but the D-pad does not reach it")
	await probe_b("town, nothing open", [])
	# A over the open world: the controller's confirm taps the world, so the child walks to the pointer.
	await pointer_to_world()
	var r := await push("A", ["pos", "walk"], 1.5)
	audit("a_on_world", {"space": "town", "under": under_pointer(), "changed": r["changed"]})
	if (r["changed"] as Dictionary).has("pos") or (r["changed"] as Dictionary).has("walk"):
		finding("a_world_walks", "awkward", "A with the pointer resting on open world walks the child to the pointer (the confirm button is also a world tap); a child pressing A to 'select' sets off a walk",
			r["changed"])
	await until(func(): return ctrl._walk_target == null, 6.0)


## The world's name tags (hud.gd _tag: "tapping a name walks there and uses it") are D-pad targets among the HUD
## buttons. A on the tram stop's "Zoo tram" tag: does it ride? If so, the way back from the zoo by the controller.
func _town_tag() -> void:
	step("town_tag")
	var tags: Array = pad.targets().filter(func(t): return hd._tag_layer.is_ancestor_of(t))
	audit("tags", {"names": tags.map(func(t): return _nm(t))})
	var tram: Control = hd._tags.get("tram_stop")
	if tram == null or not tags.has(tram):
		audit("note", {"text": "no Zoo tram tag is a D-pad target here"})
		return
	var g := await go_to(tram, "the Zoo tram tag")
	if not g["ok"]:
		audit("note", {"text": "the pointer did not reach the Zoo tram tag"})
		return
	var r := await push("A", ["pos", "walk", "journey", "space", "ctx", "ctx_label", "alt", "cam", "decorate_btn", "dialogs"], 0.3)
	var rode := await until(func(): return ctrl.journey_to != "" or ctrl.space == Places.ZOO, 10.0)
	audit("tag_a", {"changed": r["changed"], "rode": rode, "dpad_path": g["path"], "to": ctrl.journey_to})
	if not rode:
		return
	finding("tag_a_rides", "awkward", "the town's world name tags are D-pad targets in the same jumps as the HUD buttons, and A on the 'Zoo tram' tag walks the child to the stop and rides to the zoo straight away (no confirmation)",
		{"dpad_path": g["path"]})
	if not await until(func(): return ctrl.space == Places.ZOO and ctrl.journey_to == "", 15.0):
		error("the accidental zoo ride did not arrive")
		return
	await wait(1.0)
	if pad.is_modal():
		await close_with_b("zoo arrival dialog")
	await screen("zoo (reached by the tag)")
	await dpad_map("zoo")
	await probe_b("zoo", [])
	var gh := await go_to(hd._ride_home, "Ride home (zoo)")
	if not gh["ok"]:
		error("the pointer did not reach Ride home in the zoo")
		return
	await push("A", ["journey", "space", "ctx", "ctx_label", "alt", "cam", "decorate_btn", "dialogs", "pos", "level"], 0.2)
	if not await until(func(): return ctrl.space == Places.TOWN and ctrl.journey_to == "", 15.0):
		error("Ride home from the zoo did not bring the child back")
		return
	await wait(1.0)
	audit("note", {"text": "back in town from the zoo by D-pad and A on Ride home"})


func _to_tram() -> void:
	step("walk_to_tram")
	var board: Variant = TownModel.tram_stop_boarding(Session.model)
	if board == null:
		error("the town has no tram stop boarding point")
		return
	var from: Vector2 = ctrl.pos
	var ok := await walk_town(board)
	audit("walk", {"to": "tram stop", "from": _v(from), "at": _v(ctrl.pos), "goal": _v(board), "arrived": ok})
	if not ok:
		error("the left stick did not bring the child to the tram stop")
		return
	if not await until(func(): return ctrl._ctx.get("type", "") == "tram", 6.0):
		error("the tram stop offers no ride (%s)" % ctrl._ctx.get("type", ""))
		return
	var d := await screen("tram stop")
	var parts: Array = d["parts"]
	var names: Array = parts.map(func(p): return "%s %s" % [p[0], p[1]])
	audit("tram_hints", {"parts": names, "main": hd._context_btn.text, "alt": hd._context_alt_btn.text if hd._context_alt_btn.is_visible_in_tree() else "",
		"alt2": hd._context_alt2_btn.visible})
	if not names.has("Y Ride to the city"):
		finding("tram_city_hint", "awkward", "the hints at the tram stop do not say 'Y Ride to the city'", names)
	await probe_b("tram stop", [])


func _ride_to_city() -> void:
	step("ride_to_city")
	var r := await push("Y", ["journey", "space", "ctx", "ctx_label", "alt", "cam", "menus", "dialogs", "pos", "weather", "decorate_btn"], 0.2)
	if not (r["events"] as Array).any(func(e): return str(e).begins_with("journey:start:city")):
		error("Y at the tram stop did not start the ride to the city (%s)" % [r["events"]])
		return
	# During the journey the card takes every input: A, B, X, Y, + and the stick must do nothing.
	var s0 := state()
	_events.clear()
	var during: bool = ctrl.journey_to != ""
	for l in ["A", "B", "X", "Y", "+"]:
		await btn(phys(l))
	axis(JOY_AXIS_LEFT_Y, -1.0)
	await frames(6)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(2)
	var s1 := state()
	audit("journey_inputs", {"journey_was_on": during, "still_on": ctrl.journey_to != "", "events": _events.duplicate(), "changed": diff(s0, s1)})
	if ctrl.journey_to != "":
		var jd := await screen("journey card")
		if jd["hint_shown"] and ctrl.journey_to != "":
			finding("journey_hints", "cosmetic", "during the journey card (the controller acts on nothing) the hint bar and pointer still show 'A Select, Right stick Pointer, L R Turn camera' over the card", jd["hint_text"])
	if _events.any(func(e): return not str(e).begins_with("journey") and not str(e).begins_with("space") and not str(e).begins_with("toast")):
		finding("journey_input_leak", "blocker", "a button during the journey card did something", _events.duplicate())
	if not await until(func(): return ctrl.space == Places.CITY and ctrl.journey_to == "", 12.0):
		error("the child did not arrive in the city")
		return
	await wait(0.8)


func _city_arrival() -> void:
	step("city_arrival")
	var d := await screen("city arrival")
	var st: Dictionary = d["state"]
	if st["decorate_btn"]:
		finding("city_decorate_shown", "blocker", "Decorate shows in the city (dest-fix r1)")
	var keys: Array = (d["parts"] as Array).map(func(p): return str(p[0]))
	if not keys.has(tr("Left stick")) or not keys.any(func(k): return k.contains("ZL")):
		finding("hints_no_walk_zoom", "cosmetic", "in play the hints never name the left stick (walk), ZL / ZR (zoom) or the D-pad (buttons); they name A Select, the right stick Pointer and L R", keys)
	audit("arrival_ctx", {"ctx": st["ctx"], "label": st["ctx_label"], "pos": st["pos"], "bus_stop": _v(CityMap.BUS_STOP)})
	if st["ctx"] == "tram_home":
		finding("arrival_x_rides_home", "awkward", "on arrival in the city the child stands within reach of the bus stop, so the first X press is 'Ride home' and ends the visit at once",
			{"ctx": st["ctx_label"], "pos": st["pos"]})
	await dpad_map("city")
	await probe_b("city arrival", [])


func _city_walk() -> void:
	step("city_walk")
	var p0: Vector2 = ctrl.pos
	var fwd: Vector2 = main.rig.flat_forward()
	await stick(true, Vector2(0.0, -1.0), 1.0)
	var moved: Vector2 = ctrl.pos - p0
	var p1: Vector2 = ctrl.pos
	await wait(0.4)
	var after_release: float = ctrl.pos.distance_to(p1)
	audit("walk", {"pushed": "left stick up 1 s", "moved_m": snappedf(moved.length(), 0.01), "along_view": snappedf(moved.normalized().dot(fwd), 0.01) if moved.length() > 0.01 else 0.0,
		"drift_after_release_m": snappedf(after_release, 0.01), "level": ctrl.level})
	if moved.length() < 0.5:
		finding("city_stick_no_walk", "blocker", "the left stick does not walk the child in the city", {"moved": moved.length()})
	elif moved.normalized().dot(fwd) < 0.7:
		finding("city_stick_not_view_relative", "awkward", "stick up does not walk away from the camera (into the screen)", {"dot": moved.normalized().dot(fwd)})
	if after_release > 0.1:
		finding("city_stick_drift", "awkward", "the child keeps walking after the stick is let go", {"m": after_release})
	await screen("city walking")


func _city_camera() -> void:
	step("city_camera")
	var s0 := state()
	await push("R", ["cam"], 0.6)
	await push("L", ["cam"], 0.6)
	var y0: int = s0["cam"]["yaw"]
	var s1 := state()
	audit("lr", {"yaw_before": y0, "yaw_after_R_then_L": s1["cam"]["yaw"]})
	# The right stick: the pointer, not the view (design/tv-controller.md).
	var cur0: Vector2 = pad.cursor
	var cs0: Dictionary = state()["cam"]
	await stick(false, Vector2(1.0, 0.0), 0.4)
	audit("right_stick", {"pointer_moved_px": roundi(pad.cursor.distance_to(cur0)), "cam_before": cs0, "cam_after": state()["cam"]})
	if str(cs0) == str(state()["cam"]):
		finding("no_analog_orbit", "awkward", "in the city the right stick only moves the pointer; the view can only turn in 22.5-degree steps with L / R and never tilt (touch can orbit and tilt freely)")
	# ZL / ZR with the pointer on open world, then with the pointer resting on a HUD button (after the D-pad).
	await pointer_to_world()
	var z0: float = float(main.rig.city_state["distance"])
	await trigger(JOY_AXIS_TRIGGER_LEFT)
	var z1: float = float(main.rig.city_state["distance"])
	await trigger(JOY_AXIS_TRIGGER_RIGHT)
	var z2: float = float(main.rig.city_state["distance"])
	audit("zoom_world", {"under": under_pointer(), "dist": [z0, z1, z2]})
	if not z1 < z0:
		finding("zl_no_zoom_world", "awkward", "ZL does not zoom in with the pointer over the city", {"dist": [z0, z1]})
	var reset: Control = hd.find_child("CityReset", true, false)
	await go_to(reset, "Reset view")
	var z3: float = float(main.rig.city_state["distance"])
	await trigger(JOY_AXIS_TRIGGER_LEFT)
	var z4: float = float(main.rig.city_state["distance"])
	audit("zoom_on_button", {"under": under_pointer(), "dist": [z3, z4]})
	if is_equal_approx(z3, z4):
		finding("zoom_dead_on_button", "awkward", "ZL / ZR do nothing while the pointer rests on a HUD button (where the D-pad leaves it): the wheel event goes to the button, not the city",
			{"under": under_pointer()["name"], "dist": [z3, z4]})
	else:
		await trigger(JOY_AXIS_TRIGGER_RIGHT)
	var pulls := 0
	var dists := []
	for i in 40:
		if bool(main.rig.city_state.get("out", false)):
			break
		await trigger(JOY_AXIS_TRIGGER_RIGHT)
		pulls += 1
		dists.append(snappedf(float(main.rig.city_state["distance"]), 0.1))
	audit("zoom_out", {"overview": bool(main.rig.city_state.get("out", false)), "zr_pulls_from_stroll": pulls, "dists": dists})
	if pulls > 8:
		finding("zr_many_pulls", "awkward", "from the strolling view it takes %d ZR pulls to reach the overview of the block (one wheel step per pull)" % pulls, dists)
	if not bool(main.rig.city_state.get("out", false)):
		finding("zr_no_overview", "awkward", "ZR does not reach the overview of the whole block")
	await screen("city overview")
	# The HUD's Zoom button (in the camera column the D-pad reaches): press it repeatedly from the strolling view.
	var zb: Control = null
	for t in pad.targets():
		if _nm(t) == "Zoom":
			zb = t
	if zb:
		var rs: Control = hd.find_child("CityReset", true, false)
		await go_to(rs, "Reset view")
		await push("A", ["cam"], 0.2)
		await until(func(): return not main.rig.city_gliding(), 3.0)
		await go_to(zb, "Zoom")
		var zs := [snappedf(float(main.rig.city_state["distance"]), 0.1)]
		for i in 7:
			await btn(phys("A"))
			await wait(0.2)
			zs.append(snappedf(float(main.rig.city_state["distance"]), 0.1))
		audit("zoom_button", {"dists_per_press": zs, "out": bool(main.rig.city_state.get("out", false))})
		var closer := false
		for i in range(1, zs.size()):
			if float(zs[i]) < float(zs[i - 1]) - 0.05:
				closer = true
		if not closer:
			finding("zoom_button_one_way", "awkward", "in the city the HUD's Zoom button only ever zooms out, level by level, and then stays on the overview (camera_rig.gd toggle_zoom: step_zoom(-1), and at the end CityOrbit.reset, which is the overview); a controller player who does not know ZL cannot come back in with it", zs)


func _city_look() -> void:
	step("city_look")
	var look: Control = hd.find_child("CityLook", true, false)
	var g := await go_to(look, "Look around")
	if not g["ok"]:
		error("the pointer did not reach Look around")
		return
	await push("A", ["looking", "cam", "look"], 0.4)
	if not ctrl.city_looking:
		error("A on Look around did not start Look")
		return
	var d := await screen("looking")
	var under_after: Dictionary = under_pointer()
	audit("look_button_moved", {"pointer": _v(pad.cursor), "under": under_after, "look_btn": _r(look.get_global_rect()),
		"pause_btn": _r((hd.find_child("CityPause", true, false) as Control).get_global_rect())})
	if str(under_after.get("name", "")) != "Stop looking":
		# A second A, as a child presses to stop looking, lands where the button was.
		var r2 := await push("A", ["looking", "look", "cam"], 1.2)
		audit("look_second_a", {"changed": r2["changed"], "still_looking": ctrl.city_looking})
		finding("look_button_moves", "awkward", "after A on Look around the camera column re-centres (Pause appears), so the Look button (now Stop looking) moves out from under the pointer; a second A hits %s instead of stopping Look" % under_after.get("name", "?"),
			{"pointer": _v(pad.cursor), "stop_looking": _r(look.get_global_rect()), "second_a_changed": r2["changed"]})
		if not ctrl.city_looking:
			await go_to(look, "Look around")
			await push("A", ["looking", "cam", "look"], 0.4)
	var names: Array = (d["parts"] as Array).map(func(p): return "%s %s" % [p[0], p[1]])
	if not names.any(func(n): return str(n).contains("D-pad")) or not names.any(func(n): return str(n).begins_with("B ")):
		finding("look_hints_missing", "awkward", "while looking the hints say nothing about the D-pad stepping places or B to stop looking; they show the walking hints", names)
	await dpad_map("looking (up/down only)", ["up", "down"])
	var seen := []
	for i in 4:
		await btn(JOY_BUTTON_DPAD_RIGHT)
		await until(func(): return not main.rig.city_gliding(), 3.0)
		seen.append(str(main.rig.city_look))
	await btn(JOY_BUTTON_DPAD_LEFT)
	await until(func(): return not main.rig.city_gliding(), 3.0)
	seen.append(str(main.rig.city_look))
	audit("look_steps", {"right_x4_then_left": seen, "order": CityMap.LOOK_ORDER, "pointer_under": under_pointer()})
	if seen.has(""):
		finding("look_step_blank", "awkward", "a D-pad step in Look landed on no place", seen)
	# The left stick while looking: the camera is on a place, so the child walking now walks out of sight.
	var p0: Vector2 = ctrl.pos
	await stick(true, Vector2(0.0, 1.0), 0.6)
	var walked: float = ctrl.pos.distance_to(p0)
	audit("look_stick", {"walked_m": snappedf(walked, 0.01), "still_looking": ctrl.city_looking, "look": main.rig.city_look})
	if walked > 0.3:
		finding("look_stick_walks_unseen", "awkward", "the left stick walks the child while Look keeps the camera on a place: the child walks out of view and the next B glides back to a child that moved", {"m": walked})
	# Pause by the D-pad (up / down move between the camera column's buttons while looking).
	var pause: Control = hd.find_child("CityPause", true, false)
	var gp := await go_to(pause, "Pause the city", false)
	if gp["ok"]:
		await push("A", ["paused"], 0.3)
		await screen("looking, paused")
		await go_to(pause, "Resume", false)
		await push("A", ["paused"], 0.3)
	# A on the world while looking: a Look tap (a place, or out to the overview), never a walk.
	await pointer_to_world()
	var ra := await push("A", ["look", "cam"], 1.5)
	if (ra["changed"] as Dictionary).has("pos") or (ra["changed"] as Dictionary).has("walk"):
		finding("look_a_walks", "blocker", "A on the world while looking walked the child", ra["changed"])
	# B ends Look and glides back to the child.
	var rb := await probe_b("looking", ["looking", "look", "cam", "paused"])
	await until(func(): return not main.rig.city_gliding(), 3.0)
	if ctrl.city_looking:
		finding("look_b_stuck", "blocker", "B does not end Look")
	audit("look_end", {"state": state(), "b_changed": rb["changed"]})


func _city_reset() -> void:
	step("city_reset")
	await push("R", ["cam"], 0.3)
	await pointer_to_world()
	await trigger(JOY_AXIS_TRIGGER_RIGHT)
	await trigger(JOY_AXIS_TRIGGER_RIGHT)
	var before: Dictionary = state()["cam"]
	var reset: Control = hd.find_child("CityReset", true, false)
	var g := await go_to(reset, "Reset view")
	if not g["ok"]:
		error("the pointer did not reach Reset view")
		return
	await push("A", ["cam"], 0.2)
	await until(func(): return not main.rig.city_gliding(), 3.0)
	var after: Dictionary = state()["cam"]
	audit("reset", {"before": before, "after": after})
	if after["out"] or str(before) == str(after):
		finding("reset_no_effect", "awkward", "Reset view by A did not bring back the strolling view", {"before": before, "after": after})
	await screen("after reset")


func _city_seat() -> void:
	step("city_seat")
	var seat: Dictionary = CityMap.INTERACTIONS["cafe_seat_a"]
	var region: String = "" if seat["region"] == "ground" else str(seat["region"])
	var ok := await walk_city(region, seat["pos"])
	audit("walk", {"to": "cafe seat", "arrived": ok, "at": _v(ctrl.pos), "level": ctrl.level})
	if not ok:
		error("the stick did not bring the child to the cafe seat")
		return
	if not await until(func(): return ctrl._ctx.get("type", "") == "city_use", 4.0):
		error("the cafe seat offers nothing (%s)" % ctrl._ctx)
		return
	var d := await screen("at the cafe seat")
	var names: Array = (d["parts"] as Array).map(func(p): return "%s %s" % [p[0], p[1]])
	if not names.has("X " + str(seat["label"])):
		finding("seat_hint", "awkward", "the hints at the seat do not say 'X %s'" % seat["label"], names)
	var cur0: Vector2 = pad.cursor
	await push("X", ["hold", "ctx", "ctx_label", "anim", "pos"], 1.0)
	if not await until(func(): return not ctrl.city_hold.is_empty(), 3.0):
		error("X did not sit the child down")
		return
	var sd := await screen("seated")
	audit("x_moves_pointer", {"before": _v(cur0), "after": _v(pad.cursor), "under": sd["under_pointer"]})
	if pad.cursor.distance_to(cur0) > 40.0 and str(sd["under_pointer"].get("name", "")) == "Stand up":
		finding("x_moves_pointer", "awkward", "X (the context action) moves the pointer onto the context button, so the next A repeats it: after X Sit down, A stands the child up; after Y Ride to the city the pointer is left at the bottom centre",
			{"before": _v(cur0), "after": _v(pad.cursor)})
	await probe_b("seated", [])
	if not ctrl.city_hold.is_empty():
		audit("note", {"text": "B while seated keeps the child seated (only X Stand up gets up)"})
	var p0: Vector2 = ctrl.pos
	await stick(true, Vector2(0.0, 1.0), 0.6)
	audit("seated_stick", {"moved_m": snappedf(ctrl.pos.distance_to(p0), 0.01), "hold": str(ctrl.city_hold.get("key", "")), "anim": str(main.world.local_kid().anim)})
	if ctrl.city_hold.is_empty():
		audit("note", {"text": "the left stick stands the child up and walks"})
	elif ctrl.pos.distance_to(p0) > 0.3:
		finding("seated_slides", "awkward", "the stick moves a seated child without standing it up", {"m": ctrl.pos.distance_to(p0)})
	else:
		finding("seated_stick_ignored", "cosmetic", "while seated the left stick does nothing; only X (Stand up) gets up, and B does nothing either")
	if not ctrl.city_hold.is_empty():
		await push("X", ["hold", "ctx", "ctx_label", "anim"], 1.0)
		if not await until(func(): return ctrl.city_hold.is_empty(), 3.0):
			error("X did not stand the child up")
			return
	await screen("stood up")


func _city_weather() -> void:
	step("city_weather")
	var box: Control = hd.find_child("CityWeather", true, false)
	if box == null or not box.is_visible_in_tree():
		error("no weather buttons in the city")
		return
	for wname in ["rain", "night", "sunny"]:
		var b: Control = hd.find_child("Weather_" + wname, true, false)
		var g := await go_to(b, "weather " + wname)
		if not g["ok"]:
			error("the pointer did not reach the %s button" % wname)
			return
		var r := await push("A", ["weather"], 0.4)
		audit("weather", {"button": wname, "changed": r["changed"], "under": under_pointer()})
		if state().get("weather", "") != wname:
			finding("weather_" + wname, "awkward", "A on the %s button did not change the weather" % wname, r["changed"])
	await screen("weather buttons")


## Decorate is reachable by no controller button in the city: every button of the controller, then A on every
## HUD button the pointer can reach (except the ones that leave), each followed by B to close what opened.
func _city_no_decorate() -> void:
	step("city_no_decorate")
	await pointer_to_world()
	var decorate_seen := []
	for l in ["B", "+", "Y", "L", "R"]:
		var r := await push(l, ["cam", "pos", "walk"], 0.4)
		if ctrl.mode != "play" or hd._catalog.visible:
			decorate_seen.append(l)
	for t in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		await trigger(t)
	for dn in DPAD:
		await btn(DPAD[dn])
		if ctrl.mode != "play" or hd._catalog.visible:
			decorate_seen.append(dn)
	# X only where it is not a ride (the context action at this spot).
	audit("x_here", {"ctx": str(ctrl._ctx.get("type", ""))})
	if not str(ctrl._ctx.get("type", "")) in ["tram_home", "city_board"]:
		await push("X", ["hold", "ctx", "ctx_label", "anim", "pos", "walk"], 0.6)
		if ctrl.mode != "play" or hd._catalog.visible:
			decorate_seen.append("X")
		if not ctrl.city_hold.is_empty():
			await push("X", ["hold", "ctx", "ctx_label", "anim"], 0.6)
	var ts: Array = pad.targets()
	var tried := []
	for t in ts:
		if not is_instance_valid(t) or not (t as Control).is_visible_in_tree():
			continue
		var n := _nm(t)
		if n in SWEEP_SKIP or not (t is BaseButton):
			continue
		if hd._tag_layer.is_ancestor_of(t) or t in [hd._context_btn, hd._context_alt_btn, hd._context_alt2_btn]:
			continue
		var g := await go_to(t, "sweep " + n, not ctrl.city_looking)
		if not g["ok"]:
			continue
		var r := await push("A", ["cam", "looking", "look", "paused", "weather", "dialogs", "modal", "pos", "walk"], 0.6)
		tried.append(n)
		if ctrl.mode != "play" or hd._catalog.visible:
			decorate_seen.append("A on " + n)
		if pad.is_modal():
			await screen("dialog from " + n)
			await close_with_b("dialog from " + n)
		if ctrl.city_looking:
			await btn(phys("B"))
			await until(func(): return not main.rig.city_gliding(), 3.0)
		if ctrl.space != Places.CITY:
			error("A on %s left the city" % n)
			return
	audit("decorate_sweep", {"pressed": tried, "skipped": SWEEP_SKIP, "decorate_or_catalog_opened_by": decorate_seen,
		"leave_town_in_targets": pad.targets().any(func(t): return _nm(t) == "Leave town")})
	if not decorate_seen.is_empty():
		finding("city_decorate_reachable", "blocker", "Decorate or the toy box opened in the city", decorate_seen)
	if pad.targets().any(func(t): return _nm(t) == "Leave town"):
		finding("city_leave_town_reachable", "awkward", "in the city the D-pad reaches 'Leave town' (top right, one jump up from the camera column); its name says town while the child is in the city (see leave_one_press for what one A does)")


func _ride_home() -> void:
	step("ride_home")
	var g := await go_to(hd._ride_home, "Ride home")
	if not g["ok"]:
		error("the pointer did not reach Ride home")
		return
	await screen("Ride home focused")
	var town_cam := {"yaw_step": main.rig._town_yaw_step, "zoom": main.rig._town_zoom}
	var r := await push("A", ["journey", "space", "ctx", "ctx_label", "alt", "cam", "weather", "decorate_btn", "dialogs", "pos", "level"], 0.2)
	if not (r["events"] as Array).any(func(e): return str(e).begins_with("journey:start:town")):
		error("A on Ride home did not start the ride (%s)" % [r["events"]])
		return
	if not await until(func(): return ctrl.space == Places.TOWN and ctrl.journey_to == "", 12.0):
		error("the child did not come home")
		return
	await wait(0.8)
	var cam: Dictionary = state()["cam"]
	audit("home", {"cam": cam, "town_cam_kept": town_cam})
	if cam["city"] or int(cam["yaw_step"]) != int(town_cam["yaw_step"]) or int(cam["zoom"]) != int(town_cam["zoom"]):
		finding("home_cam", "awkward", "the town's own view did not come back after the city", {"cam": cam, "want": town_cam})


func _town_again() -> void:
	step("town_again")
	await screen("town again")
	if not hd._decorate_btn.is_visible_in_tree():
		finding("home_no_decorate", "blocker", "Decorate is not back in the town")
		return
	var g := await go_to(hd._decorate_btn, "Decorate")
	if not g["ok"]:
		error("the pointer did not reach Decorate")
		return
	await push("A", ["mode", "catalog", "ctx", "ctx_label", "alt", "dialogs", "modal"], 0.6)
	if ctrl.mode != "decorate":
		finding("home_decorate_no", "blocker", "A on Decorate did not open decorating in the town")
		return
	await screen("decorating")
	await dpad_map("decorating")
	await probe_b("decorating", ["mode", "catalog", "ctx", "ctx_label", "alt", "modal", "dialogs"])
	if ctrl.mode != "play":
		finding("decorate_b_stuck", "blocker", "B does not leave Decorate")
	await screen("town, done decorating")


## Leave town (top right, beside Language; reached by the D-pad from the camera column): one A press.
func _leave_town() -> void:
	step("leave_town")
	var leave := _button(hd, "Leave town")
	var g := await go_to(leave, "Leave town")
	if not g["ok"]:
		error("the pointer did not reach Leave town")
		return
	var r := await push("A", ["menus", "hud", "modal", "menu_screen", "dialogs"], 1.0)
	audit("leave", {"changed": r["changed"], "events": r["events"], "at_title": main.menus.visible, "dpad_path": g["path"]})
	if main.menus.visible:
		finding("leave_one_press", "awkward", "one A on 'Leave town' ends the session and shows the title at once, with no question (confirmed in town; the same button shows in the city and the zoo)",
			{"dpad_path": g["path"]})


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and ((b as Button).text == text or (b as Button).tooltip_text == text):
			return b
	return null


func _finish(reached_end: bool) -> void:
	if _finished:
		return
	_finished = true
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	var list := []
	for k in _order:
		var f: Dictionary = _findings[k]
		list.append({"key": k, "sev": f["sev"], "what": f["what"], "steps": f["steps"]})
	audit("summary", {"reached_end": reached_end, "modals_seen": _modals_seen, "findings": list})
	for f in [SAVE, SAVE + ".bak", SAVE + ".maps", SAVE + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("TV ROUTE AUDIT: %d steps, %d findings, %d errors" % [_steps, _order.size(), _errors])
	Music.quit_game(0 if reached_end and _errors == 0 else 1)
