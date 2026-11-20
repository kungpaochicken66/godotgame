## Puzzle rooms and rideable carts through the real UI (design/puzzle-rooms-and-rides.md).
## Touch (default): the Puzzles toy box tab and its idea line, a chest placed from it, the dotted
## lines that join a puzzle in Decorate, the chest's card while it is locked, a key picked up, a dial
## turned to its clue's picture, the chest opened (and the lamp beside it answering), Start again,
## Reduce motion; then the Rides tab, a station placed from it, a ring of rails, Get in the cart, Go!,
## Stop, Get off, a ride that ends where a rail is missing; and the chest's card and the cart's two
## buttons in each language.
## Controller (--tv): the same with simulated controller events only: the pointer and A on the real
## buttons, X for the action, Y for Get off, + to place. The outside-pointer guard of the contraption
## tour stays on: any mouse, trackpad or touch event that is not the controller layer's fails the run.
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/puzzle_ride_tour.gd \
##                   --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/puzzle_ride_tour.gd \
##                   --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv --locales=en,zh-CN,ja,es,fr,de
## Logic only, no renderer (EC2): add --headless before --path, and --no-shots --window=WxH after --.
## The town is its own save (user://puzzle_ride_tour_town.json), deleted at the start of every run:
## the game's real town is never read or written. Friends are not needed: net_test.py --puzzles
## covers real clients. At most 44 screenshots (fourteen cases, four per language: the chest's card,
## the editing tools with the child in the toy box's strip, the editing tools with the child above it,
## the cart; and two of a tall thing held, once per run): 40 for six languages, 24 for two.
extends "res://tests/contraption_tour.gd"

const Puzzles := preload("res://scripts/core/puzzles.gd")
const Wishes := preload("res://scripts/core/wishes.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")

const TOUR_TOWN := "user://puzzle_ride_tour_town.json"
## Offsets from the chest.
const KEY_AT := Vector2(3.0, 0.5)
const DIAL_AT := Vector2(0.5, 2.4)
const CLUE_AT := Vector2(3.0, 2.6)
const LAMP_AT := Vector2(-1.5, 0.0)
const LILAC := 6

var pz := {}            # puzzle part ids
var rails := []         # ids of the ring, station first
var ring := []          # [[kind, cell, rot]]
var station := ""
var station_at := Vector2.ZERO
var _alt_presses := 0
var _tall_done := false   # the tall thing is held once per run, in the first language


func shot(name: String) -> void:
	if _n >= 44 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/puzzle_ride_%s_%02d_%s.png" % [shots, tag, _n, name])


func put_as(kind: String, at: Vector2, rot := 0, color := -2) -> String:
	var r: Dictionary = await ask_result(Session.place(kind, "town", at, rot, color))
	check(r.get("ok", false), "set up: a %s at %s (%s)" % [kind, at, r.get("error", "ok")])
	return r.get("item", {}).get("id", "")


func item_at(id: String) -> Vector2:
	var it: Dictionary = Session.model.items.get(id, {})
	return Vector2(it.get("x", 0.0), it.get("z", 0.0))


func dialog(name: String) -> Node:
	for ch in main.hud._overlay.get_children():
		if ch.name == name and not ch.is_queued_for_deletion():
			return ch
	return null


func dialog_text(root: Node) -> String:
	return "\n".join(root.find_children("*", "Label", true, false).map(func(l): return tr(str(l.text))))


## The Get off button: a tap, or Y on a controller (as the hints say).
func get_off() -> void:
	var before := _alt_presses
	if tv:
		await btn(phys("Y"))
	else:
		await press(main.hud._context_alt_btn)
	await until(func(): return Session.ride_of(Session.my_id) == "", 3.0)
	check(_alt_presses - before == 1, "the real Get off button reported exactly one press (%d)" % (_alt_presses - before))


## A toy box button by its meta, scrolled into view. The toy box rebuilds its rows when its contents
## change, so the button is looked up again after the scroll instead of trusting the one found before.
func toybox_button(row: Control, key: String, value: String) -> Button:
	for attempt in 3:
		var b: Button = find_button(row, key, value)
		if b == null:
			await frames(4)
			continue
		var p := b.get_parent()
		while p != null and not p is ScrollContainer:
			p = p.get_parent()
		if p:
			(p as ScrollContainer).ensure_control_visible(b)
		await frames(3)
		if is_instance_valid(b) and b.is_inside_tree() and not b.is_queued_for_deletion():
			return b
	return find_button(row, key, value)


## Places one thing from its toy box card: the tab, the card, Place here. Returns its id.
func place_from_tab(tab_name: String, kind: String) -> String:
	var hud: Control = main.hud
	var c: Node = main.controller
	var card: Button = await toybox_button(hud._cards, "kind", kind)
	var before: Array = Session.model.items.keys()
	await act(card, "the %s card" % kind)
	check(await until(func(): return c.ghost != null and c.g_kind == kind, 2.0), "the card starts placing a %s" % kind)
	if c.g_error != "":
		print("DIAG the ghost shows \"%s\" at %s" % [c.g_error, c.g_pos])
	if tv:
		await btn(JOY_BUTTON_START)
	else:
		await press(hud._place_btn)
	check(await until(func(): return Session.model.items.size() == before.size() + 1, 3.0), "Place here puts the %s in town (from the %s tab)" % [kind, tab_name])
	var made: Array = Session.model.items.keys().filter(func(k): return not before.has(k))
	if c.ghost != null:
		if tv:
			await btn(phys("B"))
		else:
			await press(button_text(hud._tools_row, "Cancel"))
	return made[0] if not made.is_empty() else ""


## What a thing in the world covers on screen, from its own visible meshes (not from the HUD's estimate).
func node_screen_rect(n: Node3D) -> Rect2:
	var cam: Camera3D = main.rig.camera
	var r := Rect2()
	var first := true
	if n == null or not n.is_visible_in_tree():
		return r
	for m in n.find_children("*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and (m as MeshInstance3D).mesh != null:
			var box: AABB = (m as MeshInstance3D).get_aabb()
			for i in 8:
				var pt: Vector3 = (m as MeshInstance3D).global_transform * box.get_endpoint(i)
				if cam.is_position_behind(pt):
					continue
				var at: Vector2 = cam.unproject_position(pt)
				r = Rect2(at, Vector2.ZERO) if first else r.expand(at)
				first = false
	return r


## While a thing is placed or edited, the tools must leave the child and the thing visible, lie on
## nothing else, be whole on screen and stay usable. (The Mac's pictures of first-steps r5 at the iPhone
## layout: the editing tools lay on the child's face and body, in German on the name too, while every
## rectangle check against the other controls passed.) The child and the thing are measured from their
## own meshes; the tools from the two panels that are actually drawn.
##
## Where the child stands is set here, not left to chance. While a thing is held the camera follows the
## thing (play_controller sets rig.follow to it in every frame), not the child, so the child may be
## anywhere on screen or off it. first-steps r6 dragged the thing to a point of the screen while the
## camera was still gliding and believed the camera would come back to the child: on the Mac the child
## then stood under the corner column, half outside the safe area, and the check had no premise (r6
## feedback). Now the camera rests on the thing first; then the child is stood, by its own picture on
## screen, at six places, and the tools are judged at each:
##   at the left and at the right of the open part of the screen,
##   high up, under the top bar (where the tools' upper place is),
##   at the bottom edge, in the strip where the toy box lies while it is browsed: in the middle of
##   it, and to the left of the middle (both under where the tools' lower place is),
##   and in the middle just above that strip (where r5's tools lay on the child).
## At every one of the six the tools must not touch the child, the name tag or the thing.
##
## first-steps r7 did not ask that in the strip. There it compared with what the toy box had hidden
## before the thing was picked up, and passed while the Mac's pictures showed the child hidden behind
## the tools (r7 feedback: less hidden than before is not visible). That comparison and the "inside
## the toy box's place" line are kept, as measurements; they no longer stand in for the child being
## clear. On a controller the hints strip is judged with the tools: in the Mac's r7 picture at the TV
## layout it lay on the child's name, and no check looked at it.
## `rest` is the toy box's rectangle while it is browsed, taken before the thing was picked up;
## `picture`, when given, names a picture taken with the child in the middle of the strip.
func tools_clear(what: String, rest: Rect2, picture := "") -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	await settle_camera()   # on the thing held: that is what the camera follows now
	await tools_settled()
	var fixed := [["the corner column", hud._side_col], ["the camera buttons", hud._cam_tools], ["the left menu", hud._left_stack], ["the first-steps line", hud._first_chip]]
	# The open part of the screen: beside the left menu, the corner column and the camera buttons, under
	# the top bar, down to the bottom edge (the toy box is tucked away while a thing is held).
	var left: float = area.position.x
	var right: float = area.end.x
	if hud._left_stack.is_visible_in_tree():
		left = maxf(left, hud._left_stack.get_global_rect().end.x)
	for other in [hud._side_col, hud._cam_tools]:
		if other.is_visible_in_tree():
			right = minf(right, other.get_global_rect().position.x)
	var top: float = area.position.y + hud.TOP_BAR_H
	var open := Rect2(left + 12.0, top + 12.0, right - left - 24.0, area.end.y - top - 24.0)
	var above: float = rest.position.y - 12.0   # just above the strip where the toy box lies
	# The child is drawn larger the lower it stands: its size is taken at the bottom edge.
	var size: Vector2 = (await stand_child_at(open.get_center().x, open.end.y)).size
	check(rest.has_area() and size.x > 0.0 and open.size.x > size.x * 3.0 and above - open.position.y > size.y, "%s: set up: the open part of the screen has room for the child (open %s, toy box %s, child %s)" % [what, open, rest, size])
	# The tools have two places. A child that reached into both at once could be clear of neither.
	var z: Dictionary = hud.zones()
	var low_zone: Rect2 = z.get("low", z["bottom"])
	var between: float = low_zone.position.y - z["top"].end.y
	check(between > size.y + 16.0, "%s: the room between the tools' two places is taller than the child (%d px between %d and %d; the child at the bottom edge is %d px tall)" % [what, int(between), int(z["top"].end.y), int(low_zone.position.y), int(size.y)])
	var thing0 := node_screen_rect(c.ghost)
	check(thing0.has_area() and thing0.position.y >= z["top"].end.y and thing0.end.y <= low_zone.position.y, "%s: the camera rests the thing between the tools' two places, clear of both (thing %s; the places end at %d and begin at %d)" % [what, thing0, int(z["top"].end.y), int(low_zone.position.y)])
	if hud.has_method("placement_rects"):
		# What the tools are placed by is the picture the camera glides to; at rest it must be the picture on screen.
		var planned: Rect2 = hud.placement_rects()[0]
		var now: Rect2 = hud.ghost_screen_rect()
		check(planned.position.distance_to(now.position) <= 1.5 and planned.size.distance_to(now.size) <= 1.5, "%s: at rest the thing is where the tools were told it would be (planned %s, on screen %s)" % [what, planned, now])
	var mid_y: float = open.position.y + (above - open.position.y) * 0.5 + size.y * 0.5
	var spots := [
		["at the left", open.position.x + size.x * 0.75, mid_y, false],
		["at the right", open.end.x - size.x * 0.75, mid_y, false],
		["high up, under the top bar", open.get_center().x + size.x * 2.0, open.position.y + size.y, false],
		["where the toy box lies, left of the middle", open.position.x + open.size.x * 0.3, open.end.y, true],
		["where the toy box lies", open.get_center().x, open.end.y, true],
		["in the middle above the toy box's place", open.get_center().x, above, false]]   # last: the caller's picture shows it
	for spot in spots:
		var w := "%s, the child %s" % [what, spot[0]]
		var put: Rect2 = await stand_child_at(spot[1], spot[2])
		# The child is where it was meant to be (not left at the place before because there was no
		# ground under the point, or because the steps did not arrive).
		check(put.has_area() and absf(put.get_center().x - float(spot[1])) <= 2.0 and absf(put.end.y - float(spot[2])) <= 2.0, "%s: set up: the child stands where it was put (middle %d, lower edge %d; child %s)" % [w, int(spot[1]), int(spot[2]), put])
		await tools_settled()
		var panels := []        # the placement tools: the buttons' panel and, where it is shown, the line above it
		for pnl in [hud._tools, hud._hint_panel]:
			if pnl.is_visible_in_tree():
				panels.append(pnl.get_global_rect())
		var over := panels.duplicate()   # everything laid over the world for placing: the tools and the controller's hints
		if tv and pad._hint_panel.is_visible_in_tree():
			over.append(pad._hint_panel.get_global_rect())
		var kid := kid_screen_rect()
		var thing := node_screen_rect(c.ghost)
		check(panels.size() >= 1 and kid.has_area() and area.grow(1.0).encloses(kid) and thing.has_area() and area.intersects(thing), "%s: the tools are shown, the child is whole on screen and the thing is on screen (place \"%s\"; child %s, thing %s, screen %s)" % [w, hud.dock, kid, thing, area])
		var under := []
		for pair in fixed:
			var other: Control = pair[1]
			if other != null and other.is_visible_in_tree() and other.get_global_rect().intersects(kid):
				under.append(pair[0])
		check(under.is_empty() and kid.position.y >= top, "%s: set up: the child stands in the open, under no menu (%s; child %s)" % [w, str(under), kid])
		if spot[3]:
			check(kid.end.y > rest.position.y + 20.0 and rest.intersects(kid), "%s: set up: the child stands in the toy box's strip (child %s, toy box %s)" % [w, kid, rest])
		else:
			check(kid.end.y <= rest.position.y + 1.0, "%s: set up: the child stands above the toy box's place (child %s, toy box from %d)" % [w, kid, int(rest.position.y)])
		# What this is about: nothing laid over the world for placing touches the child.
		check(over.all(func(r): return not r.intersects(kid)), "%s: the tools do not cover the child or the name tag (place \"%s\"; tools%s %s, child %s)" % [w, hud.dock, " and controller hints" if over.size() > panels.size() else "", str(over), kid])
		check(not (hud._catalog.is_visible_in_tree() and hud._catalog.get_global_rect().intersects(kid)), "%s: the toy box does not cover the child either" % w)
		if spot[3] and picture != "" and str(spot[0]) == "where the toy box lies":
			await shot(picture)
		# Measurements kept from r7: what the tools hide of the child, against what the toy box hid of it
		# while it was shown.
		var under_tools := 0.0
		var newly := 0.0
		for r in over:
			var part: Rect2 = r.intersection(kid) if r.intersects(kid) else Rect2()
			under_tools += part.get_area()
			newly += part.get_area() - (part.intersection(rest).get_area() if part.intersects(rest) else 0.0)
		var under_toybox: float = rest.intersection(kid).get_area() if rest.intersects(kid) else 0.0
		print("DIAG %s: child %d px2; under the tools now %d px2; under the toy box while it was shown %d px2; under the tools and not under the toy box %d px2 (place \"%s\")" % [w, int(kid.get_area()), int(under_tools), int(under_toybox), int(newly), hud.dock])
		check(newly < 0.5, "%s: the tools hide no part of the child that the toy box did not hide while it was shown (%d px2; under the tools %d px2, under the toy box %d px2)" % [w, int(newly), int(under_tools), int(under_toybox)])
		# At the bottom edge the tools lie inside the toy box's own rectangle.
		if hud.dock == "low":
			check(panels.all(func(r): return rest.grow(1.0).encloses(r)), "%s: at the bottom edge the tools lie inside the toy box's own place, so they cover nothing that it did not cover (tools %s, toy box %s)" % [w, str(panels), rest])
		check(over.all(func(r): return not r.intersects(thing)), "%s: the tools do not cover the thing being placed (place \"%s\"; tools %s, thing %s)" % [w, hud.dock, str(over), thing])
		var on := []
		for pair in fixed + [["the toy box", hud._catalog]]:
			var other: Control = pair[1]
			if other != null and other.is_visible_in_tree():
				for r in panels:
					if other.get_global_rect().intersects(r):
						on.append("%s by %d x %d px" % [pair[0], int(other.get_global_rect().intersection(r).size.x), int(other.get_global_rect().intersection(r).size.y)])
		check(on.is_empty() and over.all(func(r): return area.grow(1.0).encloses(r)), "%s: the tools lie on nothing else and are whole inside the safe area (%s; tools %s in %s)" % [w, str(on), str(over), area])
		var shown: Array = hud._tools_row.get_children().filter(func(b): return b is Button and b.visible)
		check(shown.all(func(b): return hud._tools.get_global_rect().grow(1.0).encloses(b.get_global_rect()) and b.get_global_rect().size.x >= b.get_combined_minimum_size().x - 0.5 and b.get_global_rect().size.y >= 56.0), "%s: every button is whole inside the tools panel and big enough to tap (%d buttons)" % [w, shown.size()])
		for i in shown.size():
			for j in range(i + 1, shown.size()):
				if shown[i].get_global_rect().intersects(shown[j].get_global_rect()):
					check(false, "%s: the buttons %s and %s do not overlap" % [w, tr(shown[i].text), tr(shown[j].text)])
		# The line that says what to do (or why not) is on screen and readable, wherever it now lives.
		var line: Label = hud.get("_tools_hint") if hud.get("_tools_hint") != null and (hud.get("_tools_hint") as Label).is_visible_in_tree() else hud._hint
		check(line.is_visible_in_tree() and str(line.text) != "" and area.grow(1.0).encloses(line.get_global_rect()), "%s: the line that says what to do is shown, whole on screen (\"%s\")" % [w, tr(str(line.text)).left(40)])
		if tv:
			var reach: Array = pad.targets()
			check(shown.all(func(b): return b.disabled or reach.has(b)), "%s: the controller's pointer can jump to every enabled tool button" % w)


## The tools choose their place after a short dwell (by the clock): wait until the place has held for
## a moment, by frames and by the clock.
func tools_settled() -> void:
	var hud: Control = main.hud
	var held := ""
	var since := 0
	var t0 := Time.get_ticks_msec()
	for i in 900:
		await frames(1)
		if hud.dock != held:
			held = hud.dock
			since = 0
			t0 = Time.get_ticks_msec()
		else:
			since += 1
		if since >= 45 and Time.get_ticks_msec() - t0 >= 1000:
			break
	await frames(4)


## Stands the child so that its picture on screen (its own meshes and name tag) has its middle at
## `mid_x` and its lower edge at `bottom`. Set-up: the child is put there, it does not walk; the camera
## is not touched. Returns the child's rectangle on screen (empty where there is no ground).
func stand_child_at(mid_x: float, bottom: float) -> Rect2:
	var c: Node = main.controller
	var cam: Camera3D = main.rig.camera
	var feet := Vector2(mid_x, bottom)
	var kid := Rect2()
	for i in 5:
		var gp = main.world.ground_point(cam, feet)
		if gp == null:
			return Rect2()
		c.pos = gp
		c._walk_target = null
		c._place_kid()
		c._send_state()
		await frames(2)
		kid = kid_screen_rect()
		var off := Vector2(mid_x - kid.get_center().x, bottom - kid.end.y)
		if off.length() < 0.5:
			break
		feet += off
	return kid


## The child's place on screen from its own meshes and its name tag (not from the HUD's own estimate).
func kid_screen_rect() -> Rect2:
	var kid: Node3D = main.world.local_kid()
	var cam: Camera3D = main.rig.camera
	var r := Rect2()
	var first := true
	if kid == null or not kid.is_visible_in_tree():
		return r
	var points := []
	for m in kid.find_children("*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and (m as MeshInstance3D).mesh != null:
			var box: AABB = (m as MeshInstance3D).get_aabb()
			for i in 8:
				points.append((m as MeshInstance3D).global_transform * box.get_endpoint(i))
	for l in kid.find_children("*", "Label3D", true, false):
		if l.is_visible_in_tree() and (l as Label3D).text != "":
			# A billboard: its width and height lie along the camera's own axes.
			var half: Vector3 = (l as Label3D).get_aabb().size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					points.append((l as Label3D).global_position + cam.global_basis.x * half.x * sx + cam.global_basis.y * half.y * sy)
	for pt in points:
		if cam.is_position_behind(pt):
			continue
		var at: Vector2 = cam.unproject_position(pt)
		r = Rect2(at, Vector2.ZERO) if first else r.expand(at)
		first = false
	return r


## The idea line must leave the child visible and sit on nothing else (the Mac's pictures of
## first-steps r1: a three-line idea covered the child's face and body; a line count says nothing
## about that). Judged from rectangles on screen: the panel against the child's own meshes and name
## tag, and against every other part of the screen it could land on.
func idea_line_clear(what: String) -> void:
	var hud: Control = main.hud
	await settle_camera()
	await frames(3)
	var panel: Rect2 = hud._hint_panel.get_global_rect()
	var kid := kid_screen_rect()
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	check(hud._hint_panel.is_visible_in_tree() and panel.has_area() and kid.has_area(), "%s: the idea line and the child are both on screen (%s, %s)" % [what, panel, kid])
	check(not panel.intersects(kid), "%s: the idea line does not cover the child or the name tag (line %s, child %s)" % [what, panel, kid])
	check(area.grow(1.0).encloses(panel), "%s: the idea line is whole, inside the screen's safe area (%s in %s)" % [what, panel, area])
	var over := []
	for pair in [["the left menu", hud._left_stack], ["the corner column", hud._side_col], ["the camera buttons", hud._cam_tools], ["the toy box", hud._catalog], ["the first-steps line", hud._first_chip]]:
		var c: Control = pair[1]
		if c != null and c.is_visible_in_tree() and c.get_global_rect().intersects(panel):
			over.append(pair[0])
	check(over.is_empty(), "%s: the idea line lies on nothing else (%s)" % [what, str(over)])


func open_tab(name: String) -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	if c.mode != "decorate":
		await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0), "Decorate opens the toy box")
	var tab: Button = await toybox_button(hud._tabs, "tab", name)
	check(tab != null, "the toy box has a %s tab here" % name)
	# What the tap met, printed when the tab does not answer (one tap, never a second try).
	var fired := [0]
	var outside0 := _real_mouse
	var at := Vector2.ZERO
	var seen := ""
	if tab != null:
		tab.pressed.connect(func(): fired[0] += 1)
		at = tab.get_global_rect().get_center()
		seen = "tab %s, %s" % [tab.get_global_rect(), _tab_row_state(hud, at)]
	await act(tab, "the %s tab" % name)
	await frames(4)
	var answered: bool = hud._hint.text == RoomThemes.TOOLKIT_IDEAS[name] and hud._hint_panel.visible
	if not answered:
		print("DIAG the %s tab did not answer: its pressed signal fired %d time(s); outside pointer events during the tap %d (in all %d); category now \"%s\"; before the tap: %s; after: the button %s, %s; window focused %s; frame %d, %d fps" % [name,
			fired[0], _real_mouse - outside0, _real_mouse, hud._category, seen, "is still there at %s" % tab.get_global_rect() if is_instance_valid(tab) and tab.is_inside_tree() else "is gone",
			_tab_row_state(hud, at), get_window().has_focus(), Engine.get_process_frames(), int(Engine.get_frames_per_second())])
	check(answered, "the %s tab shows its idea line (%s)" % [name, hud._hint.text])


## The tab row as a tap meets it: how far it is scrolled, its range, and which tab lies under a point.
func _tab_row_state(hud: Control, p: Vector2) -> String:
	var sc := hud._tabs.get_parent() as ScrollContainer
	var bar := sc.get_h_scroll_bar()
	var under := "(outside the row's view)"
	if sc.get_global_rect().has_point(p):
		under = "(no tab)"
		for b in hud._tabs.get_children():
			if b is Button and (b as Button).get_global_rect().has_point(p):
				under = str(b.get_meta("tab", b.get_meta("placement", "?")))
	return "row scrolled %d of %d (view %d wide, row %d wide), under the tap point: %s" % [sc.scroll_horizontal, int(bar.max_value), int(bar.page), int(hud._tabs.size.x), under]


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "480"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "480"))
		print("PUZZLE_RIDE %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("PUZZLE_RIDE start tag=%s input=%s engine=%s renderer=%s protocol=%d" % [tag, "controller" if tv else "touch",
		Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method(), Session.PROTOCOL])
	hud._context_btn.pressed.connect(func(): _ctx_presses += 1)
	hud._context_alt_btn.pressed.connect(func(): _alt_presses += 1)
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	for f in [TOUR_TOWN, TOUR_TOWN + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var reduce_before: bool = DecoMotion.load_reduce()
	Session.start_solo(TOUR_TOWN, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	main.world.set_reduce_motion(false)
	# No animal wish during the tour: a wish arriving adds a toy box tab and rebuilds the tab row at a
	# moment set by the clock, which could free a tab this driver is about to press. Wishes have their
	# own tests; like the parked animals, this only keeps an unrelated timer out of the timing.
	Activities._wish_wait = -1.0e6
	check(Session.model.wishes.get("active", {}).is_empty(), "no animal wish is active during the tour")
	check(main.world.puzzle_fx != null and main.world.ride_fx != null, "the puzzle and ride layers are there")
	park_animals()
	await _puzzle_build(hud, c)
	case_ended("puzzle toy box and placing")
	await _puzzle_links(hud, c)
	case_ended("puzzle lines")
	await _puzzle_solve(hud, c)
	case_ended("puzzle solved")
	await _puzzle_again(hud, c)
	case_ended("puzzle again")
	await _ride_build(hud, c)
	case_ended("rides toy box and rails")
	await _ride(hud, c)
	case_ended("ride")
	await _ride_end(hud, c)
	case_ended("ride to the end of the rails")
	await _toybox_rebuild(hud, c)
	case_ended("toy box rebuilt while choosing")
	for loc in locales:
		await _texts_for(loc, hud, c)
		case_ended("[%s] puzzle and ride texts" % loc)
	main.world.set_reduce_motion(reduce_before)
	I18n.set_locale(locales[0])
	# Controller or touch: nothing but this driver may move the pointer (see contraption_tour.gd, _input).
	check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the %s tour (%d; first: %s)" % ["controller" if tv else "touch", _real_mouse, _real_mouse_first])
	print("PUZZLE_RIDE %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


# ------------------------------------------------------------- puzzle rooms

## The Puzzles tab, its idea line and a chest placed from it; then the rest of a small puzzle.
func _puzzle_build(hud: Control, c: Node) -> void:
	var found := false
	for z in range(9, 17):
		for x in range(-14, 8):
			var b := Vector2(x, z)
			var fits: bool = [["puzzle_chest", Vector2.ZERO], ["puzzle_key", KEY_AT], ["puzzle_dial", DIAL_AT], ["puzzle_clue_triangle", CLUE_AT], ["lamp_post", LAMP_AT]].all(
				func(e): return Session.model.check(e[0], "town", b.x + e[1].x, b.y + e[1].y, 0) == "") \
				and Session.model.items_in("town").all(func(i): return Vector2(i["x"], i["z"]).distance_to(b + Vector2(1.0, 1.2)) > 5.5 or not Contraptions.takes_part(i["kind"]))
			if fits and not found:
				base = b
				found = true
	check(found, "free ground for the puzzle (%s)" % base)
	await stand_at(base + Vector2(1.2, 4.2))
	await open_tab("Puzzles")
	await idea_line_clear("Puzzles tab, as first opened")
	for kind in Puzzles.KINDS:
		check(hud._cards.find_children("*", "Button", true, false).any(func(b): return b.get_meta("kind", "") == kind), "the tab offers the %s" % kind)
	toybox_hints_clear("Puzzles tab")
	await shot("puzzles_tab")
	pz["chest"] = await place_from_tab("Puzzles", "puzzle_chest")
	check(pz["chest"] != "" and Session.model.items[pz["chest"]]["kind"] == "puzzle_chest", "it is a treasure chest")
	if c.mode == "decorate":
		await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done leaves Decorate")
	if item_at(pz["chest"]).distance_to(base) > 0.01:
		var mv: Dictionary = await ask_result(Session.move(pz["chest"], base, 0))
		check(mv.get("ok", false), "set up: the chest moves to %s (%s)" % [base, mv.get("error", "ok")])
	pz["key"] = await put_as("puzzle_key", base + KEY_AT)
	pz["dial"] = await put_as("puzzle_dial", base + DIAL_AT, 0, LILAC)
	pz["clue"] = await put_as("puzzle_clue_triangle", base + CLUE_AT, 0, LILAC)
	pz["lamp"] = await put_as("lamp_post", base + LAMP_AT)
	park_animals()
	await frames(4)
	check(pz.values().all(func(i): return i != "" and main.world.item_nodes.has(i)), "all five things are drawn")
	eq_parts()
	check(main.world.puzzle_fx.lights.get(pz["chest"]) == [false, false], "the chest shows two unlit lights: one for the key, one for the dial (%s)" % str(main.world.puzzle_fx.lights.get(pz["chest"])))
	var dial_node: Node3D = main.world.item_nodes[pz["dial"]]
	var shown: Array = dial_node.get_node("Pictures").get_children().filter(func(p): return p.visible).map(func(p): return str(p.name))
	check(shown == ["Pic%d" % int(Session.puzzle_state("town")["dials"][pz["dial"]])] and shown != ["Pic2"], "the dial shows one picture, and not the triangle yet (%s)" % str(shown))
	_case_ok = true


func eq_parts() -> void:
	var p: Dictionary = Puzzles.parts(Session.model, "town")
	check(p["chests"] == [pz["chest"]] and p["keys"] == [pz["key"]] and p["dials"] == [{"id": pz["dial"], "color": LILAC, "target": 2}],
		"the puzzle is one chest, one key and the Lilac dial that wants a triangle (%s)" % str(p))


## Decorate joins the puzzle's parts with lines of squares, next to the contraption's round dots.
func _puzzle_links(hud: Control, c: Node) -> void:
	await stand_at(base + Vector2(1.2, 4.2))
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0), "Decorate")
	await frames(4)
	var pairs: Array = main.world.puzzle_fx.link_pairs
	check(pairs.has([pz["key"], pz["chest"], "key"]) and pairs.has([pz["dial"], pz["chest"], "dial"]) and pairs.has([pz["clue"], pz["dial"], "clue"]) and pairs.size() == 3,
		"lines join the key and the dial to the chest, and the clue card to its dial (%s)" % str(pairs))
	check(main.world.puzzle_fx._links_root.get_child_count() > 10, "the lines are drawn (%d squares)" % main.world.puzzle_fx._links_root.get_child_count())
	check(main.world.contraptions.link_pairs.has([pz["chest"], pz["lamp"]]), "the chest is linked to the lamp beside it, as a contraption trigger")
	await settle_camera()
	# The camera buttons keep clear of the column in the corner and of the toy box (Mac pictures of
	# town-play r1 and before: Put on display lay over the turn and zoom buttons on short screens).
	var cam_r: Rect2 = hud._cam_tools.get_global_rect()
	var col_r: Rect2 = hud._side_col.get_global_rect()
	var area0: Rect2 = _area() if tv else hud.get_global_rect()
	check(not cam_r.intersects(col_r), "while decorating, the camera buttons and the corner column do not overlap (%s, %s)" % [cam_r, col_r])
	check(not cam_r.intersects(hud._catalog.get_global_rect()) and area0.grow(1.0).encloses(cam_r), "and the camera buttons are clear of the toy box, inside the safe area (%s, toy box %s, area %s)" % [cam_r, hud._catalog.get_global_rect(), area0])
	# They moved up, not sideways: still at the right edge where a thumb rests, and under the top bar.
	check(absf(cam_r.end.x - (hud.get_global_rect().end.x - 16.0)) < 1.0 and cam_r.position.y >= hud.get_global_rect().position.y + hud.TOP_BAR_H, "the camera buttons are still at the right edge, under the top bar (%s in %s)" % [cam_r, hud.get_global_rect()])
	check(item_seen(pz["chest"]) and item_seen(pz["dial"]), "the chest and the dial are on screen with the toy box open")
	await shot("puzzle_lines")
	await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done")
	await frames(4)
	check(main.world.puzzle_fx.link_pairs.is_empty() and main.world.puzzle_fx._links_root.get_children().all(func(n): return n.is_queued_for_deletion()), "in play the lines are gone")
	_case_ok = true


## The chest's card while locked, the key, the dial, the chest opened and the lamp beside it.
func _puzzle_solve(hud: Control, c: Node) -> void:
	var fx: Node3D = main.world.puzzle_fx
	await stand_at(base + Vector2(0.3, 1.0))
	check(await do_context("puzzle_chest"), "the action button offers the treasure chest")
	check(await until(func(): return dialog("Puzzle") != null, 2.0), "its card opens")
	var card := dialog("Puzzle")
	if card:
		var text := dialog_text(card)
		check((tr("Keys found: %d of %d") % [0, 1]) in text and (tr("Pictures right: %d of %d") % [0, 1]) in text, "the card says what the chest still needs (%s)" % text.replace("\n", " | "))
		check(button_text(card, "Open the chest") == null and button_text(card, "Start again") != null, "locked: no Open button yet, Start again is there")
		if tv:
			await hints_ok("the chest's card")
		await shot("chest_card_locked")
		await act(button_text(card, "Close"), "Close")
	check(await until(func(): return dialog("Puzzle") == null, 2.0), "Close closes the card")
	# The key.
	await stand_at(base + KEY_AT + Vector2(0.0, 0.7))
	check(await do_context("puzzle"), "next to the key the action is Pick up the key")
	check(hud._context_btn.text == "Pick up the key" or not Session.puzzle_state("town")["found"].is_empty(), "named so")
	check(await until(func(): return Session.puzzle_state("town")["found"].has(pz["key"]), 3.0), "the key is found")
	await frames(4)
	check(fx.keys_flown == 1, "the key is seen going to the chest (%d)" % fx.keys_flown)
	check(not main.world.item_nodes[pz["key"]].get_node("Key").visible, "the key is gone from its cushion")
	check(fx.lights.get(pz["chest"]) == [true, false], "the chest's key light is lit (%s)" % str(fx.lights.get(pz["chest"])))
	check(await until(func(): return c._ctx.get("id", "") != pz["key"], 2.0), "a found key offers nothing more")
	await wait(0.9)
	await shot("key_found")
	# The dial, turned until it shows the clue card's triangle.
	await stand_at(base + DIAL_AT + Vector2(0.0, 0.8))
	var turns := 0
	while not Puzzles.progress(Session.model, "town", Session.puzzle_state("town"))["ready"] and turns < 4:
		var before := int(Session.puzzle_state("town")["dials"][pz["dial"]])
		check(await do_context("puzzle"), "next to the dial the action is Turn the dial")
		check(await until(func(): return int(Session.puzzle_state("town")["dials"][pz["dial"]]) == (before + 1) % 4, 3.0), "a turn shows the next picture")
		turns += 1
	check(turns >= 1 and turns <= 3, "the triangle was at most three turns away (%d)" % turns)
	await frames(4)
	var shown: Array = main.world.item_nodes[pz["dial"]].get_node("Pictures").get_children().filter(func(p): return p.visible).map(func(p): return str(p.name))
	check(shown == ["Pic2"], "the dial shows the triangle (%s)" % str(shown))
	check(fx.lights.get(pz["chest"]) == [true, true], "both lights on the chest are lit")
	check(hud._toast_label.text == "The chest is unlocked! Go and open it.", "the child who did it is told the chest is unlocked (%s)" % hud._toast_label.text)
	await settle_camera()
	await shot("dial_right")
	# Open it.
	await stand_at(base + Vector2(0.3, 1.0))
	check(await do_context("puzzle_chest"), "the chest's card again")
	check(await until(func(): return dialog("Puzzle") != null, 2.0), "it opens")
	card = dialog("Puzzle")
	var open_btn: Button = button_text(card, "Open the chest") if card else null
	check(open_btn != null, "now the card has Open the chest")
	if open_btn:
		await act(open_btn, "Open the chest")
	check(await until(func(): return Session.puzzle_state("town")["open"], 3.0), "the chest is open")
	await wait(1.0)
	var chest_node: Node3D = main.world.item_nodes[pz["chest"]]
	check(absf(chest_node.get_node("Lid").rotation.x - fx.LID_OPEN) < 0.05 and chest_node.get_node("Treasure").visible, "the lid is up and the treasure shows")
	check(fx.opens_drawn == 1, "the opening was drawn once")
	check(hud._toast_label.text == tr("%s opened the treasure chest!") % tr(Session.nick_of(Session.my_id)), "everyone reads who opened it (%s)" % hud._toast_label.text)
	check(await until(func(): return Session.model.items[pz["lamp"]].get("on", false), 2.0), "the lamp beside the chest lights up: an opened chest is a contraption trigger")
	await settle_camera()
	check(item_seen(pz["chest"]), "the open chest is on screen")
	await shot("chest_open")
	_case_ok = true


## Start again from the chest's card; then the same find with Reduce motion on.
func _puzzle_again(hud: Control, c: Node) -> void:
	var fx: Node3D = main.world.puzzle_fx
	await calm()
	await stand_at(base + Vector2(0.3, 1.0))
	check(await do_context("puzzle_chest"), "the open chest's card")
	check(await until(func(): return dialog("Puzzle") != null, 2.0), "it opens")
	var card := dialog("Puzzle")
	if card:
		check((tr("Opened by %s!") % tr(Session.nick_of(Session.my_id))) in dialog_text(card), "it says who opened the chest (%s)" % dialog_text(card).replace("\n", " | "))
		await act(button_text(card, "Start again"), "Start again")
	check(await until(func(): return not Session.puzzle_state("town")["open"] and Session.puzzle_state("town")["found"].is_empty(), 3.0), "the puzzle starts again")
	await frames(6)
	var chest_node: Node3D = main.world.item_nodes[pz["chest"]]
	check(absf(chest_node.get_node("Lid").rotation.x) < 0.05 and not chest_node.get_node("Treasure").visible, "the lid is shut")
	check(main.world.item_nodes[pz["key"]].get_node("Key").visible, "the key is back on its cushion")
	check(fx.lights.get(pz["chest"]) == [false, false], "both lights are out")
	check(int(Session.puzzle_state("town")["dials"][pz["dial"]]) != 2, "the dial is turned away from the triangle")
	check(hud._toast_label.text == "The puzzle is ready to play again.", "and the child is told (%s)" % hud._toast_label.text)
	await shot("puzzle_again")
	# Reduce motion: the key still goes to the chest, without the flight.
	main.world.set_reduce_motion(true)
	await stand_at(base + KEY_AT + Vector2(0.0, 0.7))
	check(await do_context("puzzle"), "Pick up the key, Reduce motion on")
	check(await until(func(): return Session.puzzle_state("town")["found"].has(pz["key"]), 3.0), "the key is found")
	await frames(3)
	check(fx._fx_root.get_child_count() == 0 and fx.keys_flown == 2, "nothing flies, and the chest's light is lit all the same")
	check(fx.lights.get(pz["chest"]) == [true, false], "the light is lit")
	main.world.set_reduce_motion(false)
	var r: Dictionary = await ask_result(Session.reset_puzzle("town"))
	check(r.get("ok", false), "set up: the puzzle starts again")
	_case_ok = true


# ------------------------------------------------------------- rideable carts

static func _curve_rot(d_in: Vector2i, d_out: Vector2i) -> int:
	for rot in [0, 2, 4, 6]:
		if [RideRules.dir_of(rot, 2), RideRules.dir_of(rot, 1)].has(-d_in) and [RideRules.dir_of(rot, 2), RideRules.dir_of(rot, 1)].has(d_out):
			return rot
	return 0


static func _straight_rot(d: Vector2i) -> int:
	for rot in [0, 2, 4, 6]:
		if RideRules.dir_of(rot, 0) == d:
			return rot
	return 0


## A ring of w x h cells ridden +x along the row z = cz, the station in its second cell.
static func ring_pieces(cx: int, cz: int, w: int, h: int) -> Array:
	var path := []
	for x in range(1, w):
		path.append(Vector2i(cx + x, cz))
	for z in range(1, h):
		path.append(Vector2i(cx + w - 1, cz + z))
	for x in range(w - 2, -1, -1):
		path.append(Vector2i(cx + x, cz + h - 1))
	for z in range(h - 2, -1, -1):
		path.append(Vector2i(cx, cz + z))
	var out := []
	for i in path.size():
		var cell: Vector2i = path[i]
		var d_in: Vector2i = cell - path[(i - 1 + path.size()) % path.size()]
		var d_out: Vector2i = path[(i + 1) % path.size()] - cell
		if i == 0:
			out.append([RideRules.STATION, cell, _straight_rot(d_out)])
		elif d_in == d_out:
			out.append(["ride_straight", cell, _straight_rot(d_out)])
		else:
			out.append(["ride_curve", cell, _curve_rot(d_in, d_out)])
	return out


## The Rides tab, a station placed from it, then a ring of rails 8 x 4 m.
func _ride_build(hud: Control, c: Node) -> void:
	var found := false
	for cz in range(1, 9):
		for cx in range(-11, 8):
			var pieces := ring_pieces(cx, cz, 4, 2)
			var mid := Vector2(cx * 2.0 + 3.0, cz * 2.0 + 1.0)
			if not found and mid.distance_to(base) > 9.0 and pieces.all(func(p): return Session.model.check(p[0], "town", p[1].x * 2.0, p[1].y * 2.0, p[2]) == "") \
					and RideRules._solids(Session.model).all(func(s): return s[0].distance_to(mid) > 5.6 + s[1]):
				ring = pieces
				found = true
	check(found, "free ground for a ring of rails")
	station_at = Vector2(ring[0][1]) * 2.0
	await stand_at(station_at + Vector2(0.0, 5.0))
	await open_tab("Rides")
	for kind in RideRules.KINDS:
		check(hud._cards.find_children("*", "Button", true, false).any(func(b): return b.get_meta("kind", "") == kind), "the tab offers the %s" % kind)
	toybox_hints_clear("Rides tab")
	await shot("rides_tab")
	var first := await place_from_tab("Rides", RideRules.STATION)
	check(first != "" and Session.model.items[first]["kind"] == RideRules.STATION, "it is a cart station")
	var at := item_at(first)
	check(is_equal_approx(fposmod(at.x, 2.0), 0.0) and is_equal_approx(fposmod(at.y, 2.0), 0.0) and int(Session.model.items[first]["rot"]) % 2 == 0, "it sits on a whole 2 m cell in a quarter turn (%s)" % at)
	if c.mode == "decorate":
		await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done leaves Decorate")
	check((await ask_result(Session.remove(first))).get("ok", false), "set up: that station is put away again")
	rails.clear()
	for p in ring:
		rails.append(await put_as(p[0], Vector2(p[1]) * 2.0, p[2]))
	station = rails[0]
	park_animals()
	await frames(4)
	var r: Dictionary = RideRules.route(Session.model, station)
	check(r["end"] == "loop" and r["legs"].size() == ring.size(), "the rails are a circuit of %d pieces (%s)" % [ring.size(), r["end"]])
	var node: Node3D = main.world.item_nodes.get(station)
	check(node != null and node.get_node_or_null("Cart") != null and not node.get_node("Cart").top_level, "the cart stands at its station")
	await stand_at(station_at + Vector2(0.0, 1.7))
	await settle_camera()
	check(item_seen(station), "the station is on screen")
	await shot("ring")
	_case_ok = true


func _cart_pos() -> Vector2:
	return main.world.ride_fx.pose_of(station)["pos"]


## Get in, Go!, Stop, Get off.
func _ride(hud: Control, c: Node) -> void:
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	await stand_at(station_at + Vector2(0.0, 1.7))
	check(await do_context("ride_board"), "next to the station the action is Get in the cart")
	check(await until(func(): return Session.ride_of(Session.my_id) == station, 3.0), "the child is in the cart")
	check(await until(func(): return c._ctx.get("type", "") == "ride_go" and hud._context_alt_btn.is_visible_in_tree(), 2.0), "in the cart: Go!, and Get off beside it")
	check(hud._context_btn.text == "Go!" and hud._context_alt_btn.text == "Get off", "named so (%s, %s)" % [hud._context_btn.text, hud._context_alt_btn.text])
	var main_r: Rect2 = hud._context_btn.get_global_rect()
	var alt_r: Rect2 = hud._context_alt_btn.get_global_rect()
	check(not main_r.intersects(alt_r) and area.grow(1.0).encloses(main_r) and area.grow(1.0).encloses(alt_r), "the two buttons do not overlap and are inside the safe area (%s, %s)" % [main_r, alt_r])
	check(alt_r.size.x >= 88.0 and alt_r.size.y >= 80.0, "Get off is a full-size touch target (%s)" % alt_r.size)
	await frames(4)
	var kid: Node3D = main.world.local_kid()
	check(Vector2(kid.global_position.x, kid.global_position.z).distance_to(station_at) < 0.4 and kid.anim == "sit", "the child sits in the cart at the station (%s)" % kid.anim)
	check(main.world.kids.size() == 1, "and is drawn once")
	if tv:
		await hints_ok("in the cart")
		check(("%s  %s" % [pad.label_of(JOY_BUTTON_X), tr("Get off")]) in pad._hint_label.text, "the hints name the button for Get off (%s)" % pad._hint_label.text)
	await settle_camera()
	await shot("in_cart")
	# Go.
	var yaw_before: float = main.rig._yaw
	var moved_before: float = main.world.ride_fx.moved
	check(await do_context("ride_go"), "Go!")
	check(await until(func(): return Session.rides.get(station, {}).get("phase", "") == "moving", 2.0), "the cart sets off")
	check(await until(func(): return c._ctx.get("type", "") == "ride_stop", 2.0) and hud._context_btn.text == "Stop", "while it moves the action is Stop")
	await wait(1.6)
	var here := _cart_pos()
	check(here.distance_to(station_at) > 2.0, "the cart is on its way (%.1f m from the station)" % here.distance_to(station_at))
	check(main.world.ride_fx.moved - moved_before > 2.0, "it was drawn moving (%.1f m)" % (main.world.ride_fx.moved - moved_before))
	# The child against the cart as it was drawn in the same frame: on the cart's own seat. (The first
	# form compared the child's node with where the cart is "now" by the clock, within 0.45 m. The seat
	# is 0.24 m from the cart's middle by design, and a child drawn a frame ago is further behind the
	# clock by the frame's length times the cart's speed: at 28 frames a second on a loaded host that
	# made 0.60 m and failed with nothing wrong in the picture.)
	var drawn: Vector2 = main.world.ride_fx._last.get(station, here)
	var seat: Node3D = preload("res://scripts/art/props.gd").seat_marker(main.world.item_nodes[station], 0)
	var seat_at: Vector3 = main.world.seat_transform(seat).origin if seat else Vector3(INF, INF, INF)
	var rider := Vector2(kid.global_position.x, kid.global_position.z)
	check(seat != null and rider.distance_to(Vector2(seat_at.x, seat_at.z)) < 0.05, "the child rides in it: drawn on the cart's seat (%.2f m off it; %.2f m from the cart's middle as drawn, %.2f m from where the cart is by the clock)" % [rider.distance_to(Vector2(seat_at.x, seat_at.z)), rider.distance_to(drawn), rider.distance_to(here)])
	check(Vector2(seat_at.x, seat_at.z).distance_to(drawn) < 0.45, "and the seat is in the cart (%.2f m from its middle)" % Vector2(seat_at.x, seat_at.z).distance_to(drawn))
	check(c.pos.distance_to(drawn) < 0.3, "and is where the cart is for everyone else (%.2f m)" % c.pos.distance_to(drawn))
	check(drawn.distance_to(here) < 0.2 + RideRules.SPEED * 0.5, "the drawn cart follows the clock (%.2f m behind)" % drawn.distance_to(here))
	check(is_equal_approx(main.rig._yaw, yaw_before), "the camera has not turned")
	var focus := Vector2(main.rig._focus.x, main.rig._focus.z)
	check(focus.distance_to(here) < 2.5, "and follows gently: its aim is %.1f m behind the cart" % focus.distance_to(here))
	check(seen_at(Vector3(here.x, 0.6, here.y)) != null, "the cart is on screen, under no control")
	await shot("riding")
	# Stop.
	check(await do_context("ride_stop"), "Stop")
	check(await until(func(): return Session.rides.get(station, {}).get("phase", "") == "stopped", 2.0), "the cart stops")
	var held := _cart_pos()
	await wait(0.4)
	check(_cart_pos().distance_to(held) < 0.001, "and stands still")
	check(await until(func(): return c._ctx.get("type", "") == "ride_go", 2.0), "the action is Go! again")
	# Get off, out on the rails.
	await get_off()
	check(Session.ride_of(Session.my_id) == "" and Session.seat_of(Session.my_id).is_empty(), "the child is out of the cart")
	await frames(4)
	check(c.pos.distance_to(held) > 0.9 and c.pos.distance_to(held) < 1.6, "standing beside where the cart was (%.2f m away)" % c.pos.distance_to(held))
	check(main.world.resolve_walk(c.pos).distance_to(c.pos) < 0.01, "on free ground")
	check(kid.anim != "sit" and absf(kid.global_position.y) < 0.01, "on their feet (%s)" % kid.anim)
	check(not main.world.item_nodes[station].get_node("Cart").top_level, "the cart is back at its station")
	check(not hud._context_alt_btn.is_visible_in_tree(), "the second button is gone")
	check(main.world.kids.size() == 1, "one child on screen")
	await settle_camera()
	await shot("got_off")
	_case_ok = true


## A rail is put away ahead of the cart: it rides to the end of the rails, stops and says why.
func _ride_end(hud: Control, c: Node) -> void:
	await stand_at(station_at + Vector2(0.0, 1.7))
	check(await do_context("ride_board"), "Get in the cart")
	check(await until(func(): return Session.ride_of(Session.my_id) == station, 3.0), "in the cart")
	check(await do_context("ride_go"), "Go!")
	check(await until(func(): return Session.rides.get(station, {}).get("phase", "") == "moving", 2.0), "moving")
	var far: int = ring.size() - 2
	check((await ask_result(Session.remove(rails[far]))).get("ok", false), "a rail far ahead is put away during the ride")
	check(Session.rides[station]["route"]["end"] == "end" and Session.rides[station]["phase"] == "moving", "the cart keeps going on what is left")
	check(await until(func(): return Session.rides.get(station, {}).get("phase", "") == "stopped", 12.0), "and stops by itself")
	check(Session.rides[station]["why"] == "end", "at the end of the rails (%s)" % Session.rides[station]["why"])
	var gap := Vector2(ring[far][1]) * 2.0
	check(_cart_pos().distance_to(gap) < 2.2 and _cart_pos().distance_to(gap) > 1.2, "a little before the missing rail (%.2f m from its middle)" % _cart_pos().distance_to(gap))
	check(hud._toast_label.text == RideRules.ERR_END, "the rider reads why (%s)" % hud._toast_label.text)
	check(main.world.ride_fx._arrow.visible and Vector2(main.world.ride_fx._arrow.global_position.x, main.world.ride_fx._arrow.global_position.z).distance_to(gap) < 0.1, "an arrow hangs over the missing rail")
	await frames(3)
	var kid: Node3D = main.world.local_kid()
	var seat_end: Node3D = preload("res://scripts/art/props.gd").seat_marker(main.world.item_nodes[station], 0)
	check(seat_end != null and Vector2(kid.global_position.x, kid.global_position.z).distance_to(Vector2(main.world.seat_transform(seat_end).origin.x, main.world.seat_transform(seat_end).origin.z)) < 0.05, "the child is still in the cart, on its seat")
	await settle_camera()
	await shot("rails_end")
	check(await do_context("ride_go"), "Go! at the end of the rails")
	await frames(6)
	check(Session.rides[station]["phase"] == "stopped", "does not move the cart")
	await get_off()
	check(Session.ride_of(Session.my_id) == "" and main.world.resolve_walk(c.pos).distance_to(c.pos) < 0.01, "Get off there puts the child on free ground")
	rails[far] = await put_as(ring[far][0], gap, ring[far][2])
	check(RideRules.route(Session.model, station)["end"] == "loop", "set up: the ring is whole again")
	_case_ok = true


# ------------------------------------------------------------- the toy box rebuilt while choosing

## Untyped on purpose: a freed button cannot be passed as a Button.
func _stale(b) -> bool:
	return not is_instance_valid(b) or b.is_queued_for_deletion() or not b.is_inside_tree()


## The card on screen at a point of the toy box's card row, if any (what a finger there would press).
func card_at(point: Vector2) -> Button:
	var clip: Rect2 = main.hud._card_scroll.get_global_rect()
	for b in main.hud._cards.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.has_meta("kind") and clip.has_point(point) and b.get_global_rect().has_point(point):
			return b
	return null


## The toy box rebuilds its tab and card rows whenever its contents change. One ordinary cause is an
## animal's wish arriving (a Wish tab appears) or ending (it goes), at a moment set by the clock. The
## long cases above keep wishes out (test isolation); this case brings one in on purpose, through the
## authority's own timer, while a puzzle card and then the Rides tab have just been found and scrolled
## to. It shows: the buttons found before are gone (so the rebuild really happened), the rebuild by
## itself selects, places and blocks nothing, the button now at the same place is a real one for the
## same thing, and choosing the re-found button places exactly that thing.
func _toybox_rebuild(hud: Control, c: Node) -> void:
	await calm()
	await stand_at(station_at + Vector2(0.0, 5.0))
	await open_tab("Puzzles")
	var old_card = await toybox_button(hud._cards, "kind", "puzzle_key")   # untyped: it will be freed
	check(old_card != null and not _stale(old_card), "a Puzzle key card is found and scrolled into view")
	var spot: Vector2 = old_card.get_global_rect().get_center() if old_card else Vector2.ZERO
	# Mac run of town-play r1 (puzzle47-iphone): the row was at its start while the toy box still
	# remembered this tab one card further on (a return to the remembered place had been lost after a
	# tab switch), and the wish's rebuild then slid the row to that stale place: the card under the
	# finger became another thing. That state is set up here on purpose, so the check below does not
	# depend on frame timing: what the game remembers for this tab differs from what is on screen.
	var row: ScrollContainer = hud._card_scroll
	var bar: ScrollBar = row.get_h_scroll_bar()
	var here: float = row.scroll_horizontal
	var room: float = bar.max_value - bar.page
	var stale: float = here + 142.0 if here + 142.0 <= room else (here - 142.0 if here >= 142.0 else here)
	if stale == here:
		print("DIAG [%s] the card row does not scroll at this layout (%d of %d): a stale remembered place cannot move it" % [tag, int(here), int(room)])
	hud._scroll_pos[hud._view_key()] = stale
	var items_before: int = Session.model.items.size()
	var replies_before := _replies.size()
	check(find_button(hud._tabs, "tab", "Wish") == null and Session.model.wishes.get("active", {}).is_empty(), "no wish yet")
	# The authority's own timer makes the wish on its next tick (net/activities.gd), as in normal play.
	Activities._wish_wait = Wishes.FIRST_WISH_AFTER + Wishes.NEXT_WISH_AFTER
	check(await until(func(): return not Session.model.wishes.get("active", {}).is_empty(), 3.0), "an animal's wish arrives (%s)" % str(Session.model.wishes.get("active", {}).get("id", "")))
	Activities._wish_wait = -1.0e6
	await frames(3)
	check(_stale(old_card), "the toy box was rebuilt: the card found a moment ago is no longer on screen")
	check(find_button(hud._tabs, "tab", "Wish") != null, "a Wish tab appeared")
	check(hud._category == "Puzzles" and c.mode == "decorate", "the child's own tab is still open (%s)" % hud._category)
	check(c.ghost == null and Session.model.items.size() == items_before and _replies.size() == replies_before, "the rebuild itself chose and placed nothing, and asked the town for nothing")
	check(hud._overlay.get_child_count() == 0, "no dialog was opened by it")
	var under := card_at(spot)
	check(under != null and not _stale(under) and under.get_meta("kind", "") == "puzzle_key", "the card now at the same place is a new, real card for the same thing (%s)" % (str(under.get_meta("kind", "")) if under else "none"))
	check(absf(row.scroll_horizontal - here) < 1.0, "the row is exactly where it was on screen, whatever the toy box remembered for this tab (%d, was %d, remembered %d)" % [row.scroll_horizontal, int(here), int(stale)])
	if tv:
		toybox_hints_clear("Puzzles tab after the rebuild")
	await shot("rebuilt_while_choosing")
	var made := await place_from_tab("Puzzles", "puzzle_key")
	check(made != "" and Session.model.items.get(made, {}).get("kind", "") == "puzzle_key", "choosing the card found again places a Puzzle key, not something else (%s)" % Session.model.items.get(made, {}).get("kind", "nothing"))
	check(Session.model.items.size() == items_before + 1, "exactly one thing was placed")
	# The other way round: the wish ends while the Rides tab is held.
	var old_tab = await toybox_button(hud._tabs, "tab", "Rides")   # untyped: it will be freed
	check(old_tab != null and not _stale(old_tab), "the Rides tab is found and scrolled into view")
	Session.model.wishes["active"] = {}
	Session.share("wishes")   # what the authority does when a wish is granted (activities.gd _check_wish)
	await frames(3)
	check(_stale(old_tab) and find_button(hud._tabs, "tab", "Wish") == null, "the wish ended and the tab row was rebuilt: the tab found before is gone, and so is the Wish tab")
	check(hud._category == "Puzzles" and c.ghost == null and Session.model.items.size() == items_before + 1, "again nothing was chosen or placed by the rebuild")
	var tab: Button = await toybox_button(hud._tabs, "tab", "Rides")
	check(tab != null and not _stale(tab), "the Rides tab is found again")
	await act(tab, "the Rides tab")
	await frames(4)
	check(hud._category == "Rides" and hud._hint.text == RoomThemes.TOOLKIT_IDEAS["Rides"], "it opens the Rides tab and its idea line (%s)" % hud._category)
	var kinds: Array = hud._cards.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("kind") and not b.is_queued_for_deletion()).map(func(b): return b.get_meta("kind"))
	check(kinds.has("ride_curve") and not kinds.has("puzzle_key"), "with the rides' cards, not the puzzle's (%d cards)" % kinds.size())
	var curve := await place_from_tab("Rides", "ride_curve")
	check(curve != "" and Session.model.items.get(curve, {}).get("kind", "") == "ride_curve", "choosing a card there places a Curved cart rail (%s)" % Session.model.items.get(curve, {}).get("kind", "nothing"))
	if tv:
		toybox_hints_clear("Rides tab after the rebuild")
	# Coming back to a tab returns its row to where the child left it, and the game's memory and the
	# screen agree afterwards (the lost return on the Mac left them apart).
	await act(await toybox_button(hud._tabs, "tab", "Puzzles"), "the Puzzles tab")
	await frames(6)
	await toybox_button(hud._cards, "kind", hud._cards.get_child(hud._cards.get_child_count() - 1).get_meta("kind"))   # scroll to the last card
	await frames(3)
	var left_at: int = row.scroll_horizontal
	# The row really went to its end: as far as its cards are wider than the row. (Earlier runs of this
	# case could pass with the row stopped short both times, 226 and 226 at the iPad layout, because the
	# row's range was still the Rides tab's; the place left is now checked against the cards.)
	var room_here: int = int(maxf(hud._cards.get_combined_minimum_size().x - row.size.x, 0.0))
	check(left_at == room_here and hud._cards.get_child_count() > 9, "the Puzzles row scrolls all the way to its last card (%d of %d, %d cards)" % [left_at, room_here, hud._cards.get_child_count()])
	if left_at == 0:
		print("DIAG [%s] the Puzzles row does not scroll at this layout: returning to a remembered place is not exercised here" % tag)
	await act(await toybox_button(hud._tabs, "tab", "Rides"), "the Rides tab")
	await frames(6)
	check(hud._category == "Rides" and row.scroll_horizontal == 0, "the Rides tab starts at its own place (%d)" % row.scroll_horizontal)
	await act(await toybox_button(hud._tabs, "tab", "Puzzles"), "the Puzzles tab")
	check(await until(func(): return hud._category == "Puzzles" and row.scroll_horizontal == left_at and not hud._row_settling, 2.0), "back on the Puzzles tab the row returns to where it was left (%d, left at %d)" % [row.scroll_horizontal, left_at])
	check(int(hud._scroll_pos.get(hud._view_key(), -1.0)) == row.scroll_horizontal, "what the toy box remembers for the tab is what is on screen (%d and %d)" % [int(hud._scroll_pos.get(hud._view_key(), -1.0)), row.scroll_horizontal])
	# The same return when the tap lands at the start of a frame, before the new cards are laid out.
	# EC2 producer run and trace of 2026-11-13 (iPad layout): the game's first attempt then scrolled the
	# row while its range was still the Rides tab's; the range stayed short for as long as nothing asked
	# for it again, and the row stopped at 226 instead of 794. Whether a tap lands like that depends on
	# frame timing (it failed one run in three), so that order is set up here on purpose: the tab's own
	# press handler runs and, in the same frame, before any layout, the row is asked for its place once.
	await act(await toybox_button(hud._tabs, "tab", "Rides"), "the Rides tab")
	await frames(6)
	var bar2: ScrollBar = row.get_h_scroll_bar()
	var short_room: int = int(maxf(hud._cards.get_combined_minimum_size().x - row.size.x, 0.0))   # from the Rides cards themselves
	check(absf(bar2.max_value - hud._cards.get_combined_minimum_size().x) < 1.0, "on the Rides tab the row's range is that of the Rides cards (%d of %d)" % [int(bar2.max_value), int(hud._cards.get_combined_minimum_size().x)])
	var back: Button = await toybox_button(hud._tabs, "tab", "Puzzles")
	check(hud._category == "Rides" and back != null and row.scroll_horizontal == 0, "set up: on the Rides tab again, at its start")
	if back:
		back.pressed.emit()
		row.scroll_horizontal = left_at
	if left_at <= short_room:
		print("DIAG [%s] the Rides row scrolls as far as the place left on Puzzles (%d of %d): a short range cannot cut the return here" % [tag, left_at, short_room])
	else:
		check(row.scroll_horizontal < left_at, "set up: in that frame the row's range is still the Rides tab's, and the request is cut short (%d of %d)" % [row.scroll_horizontal, left_at])
	check(await until(func(): return hud._category == "Puzzles" and row.scroll_horizontal == left_at and not hud._row_settling, 2.0), "a tap that lands before the new cards are laid out still returns the row to where it was left (%d, left at %d)" % [row.scroll_horizontal, left_at])
	check(absf(bar2.max_value - hud._cards.get_combined_minimum_size().x) < 1.0 and hud._cards.get_child_count() > 9, "and the row's range is that of its cards, so it can be scrolled to the last one and no further (%d of %d)" % [int(bar2.max_value), int(hud._cards.get_combined_minimum_size().x)])
	check(int(hud._scroll_pos.get(hud._view_key(), -1.0)) == row.scroll_horizontal, "memory and screen agree again (%d and %d)" % [int(hud._scroll_pos.get(hud._view_key(), -1.0)), row.scroll_horizontal])
	# Nothing is left blocked: Done works, the action button works.
	await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done leaves Decorate")
	for id in [made, curve]:
		if id != "":
			check((await ask_result(Session.remove(id))).get("ok", false), "set up: the extra %s is put away again" % Session.model.items.get(id, {}).get("kind", "thing"))
	eq_parts()
	check(RideRules.route(Session.model, station)["end"] == "loop", "the ring is as it was")
	await stand_at(station_at + Vector2(0.0, 1.7))
	check(await until(func(): return c._ctx.get("type", "") == "ride_board" and hud._context_btn.is_visible_in_tree(), 3.0), "and the action button offers the cart as before")
	_case_ok = true


# ------------------------------------------------------------- per language

## The chest's card and the cart's two buttons, in one language.
func _texts_for(loc: String, hud: Control, c: Node) -> void:
	I18n.set_locale(loc)
	await frames(4)
	await calm()
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	for key in ["Treasure chest", "Puzzle key", "Picture dial", "Triangle clue card", "Cart station", "Straight cart rail", "Curved cart rail", "Puzzles", "Rides",
			"Pick up the key", "Turn the dial", "Get in the cart", "Go!", "Get off", "Start again", "Open the chest", RoomThemes.TOOLKIT_IDEAS["Puzzles"], RoomThemes.TOOLKIT_IDEAS["Rides"],
			RideRules.ERR_END, Puzzles.ERR_LOCKED]:
		check(loc == "en" or tr(key) != key, "[%s] \"%s\" is translated (%s)" % [loc, key.left(30), tr(key).left(30)])
	# The chest's card.
	await stand_at(base + Vector2(0.3, 1.0))
	check(await do_context("puzzle_chest"), "[%s] the chest's card" % loc)
	check(await until(func(): return dialog("Puzzle") != null, 2.0), "[%s] it opens" % loc)
	var card := dialog("Puzzle")
	if card:
		await frames(3)
		var panel: Control = card.find_children("*", "PanelContainer", true, false)[0]
		check(area.grow(1.0).encloses(panel.get_global_rect()), "[%s] the card fits the screen (%s in %s)" % [loc, panel.get_global_rect(), area])
		check((tr("Keys found: %d of %d") % [0, 1]) in dialog_text(card), "[%s] it counts the keys in this language" % loc)
		for b in card.find_children("*", "Button", true, false):
			check(panel.get_global_rect().grow(1.0).encloses(b.get_global_rect()), "[%s] the button \"%s\" is inside the card" % [loc, tr(b.text)])
		if tv:
			await hints_ok("[%s] the chest's card" % loc)
		await shot("card_%s" % loc)
		await act(button_text(card, "Close"), "Close")
	check(await until(func(): return dialog("Puzzle") == null, 2.0), "[%s] the card closes" % loc)
	# The Puzzles tab's idea line fits.
	await open_tab("Puzzles")
	check(area.grow(1.0).encloses(hud._hint_panel.get_global_rect()), "[%s] the Puzzles idea line fits the screen (%s in %s)" % [loc, hud._hint_panel.get_global_rect(), area])
	# At most three lines (the first wording ran to five), and, which the line count cannot show, clear
	# of the child: on every tab that has an idea line, in this language.
	check(hud._hint.get_line_count() <= 3, "[%s] the Puzzles idea line is at most three lines (%d)" % [loc, hud._hint.get_line_count()])
	await idea_line_clear("[%s] Puzzles" % loc)
	for other in RoomThemes.TOOLKIT_IDEAS.keys():
		if other != "Puzzles" and find_button(hud._tabs, "tab", other) != null:
			await open_tab(other)
			# Judged only when it is this tab's line that is shown. (The Mac's r7 phone run: four tabs did
			# not open, and the lines below measured the line of the tab before and passed.)
			if hud._hint.text == RoomThemes.TOOLKIT_IDEAS[other]:
				await idea_line_clear("[%s] %s (%d lines)" % [loc, other, hud._hint.get_line_count()])
			else:
				check(false, "[%s] %s: the idea line cannot be judged, the tab did not open" % [loc, other])
	await open_tab("Puzzles")
	var cam_l: Rect2 = hud._cam_tools.get_global_rect()
	check(not cam_l.intersects(hud._side_col.get_global_rect()) and not cam_l.intersects(hud._catalog.get_global_rect()), "[%s] the camera buttons are clear of the corner column and the toy box (%s, column %s, toy box %s)" % [loc, cam_l, hud._side_col.get_global_rect(), hud._catalog.get_global_rect()])
	toybox_hints_clear("[%s] Puzzles tab" % loc)
	# While a thing is being placed, the placement tools lie on nothing else in this language. (The
	# Mac's German iPad picture: the tools reached 16 px under "Ausstellen" in the corner column.)
	var rest: Rect2 = hud._catalog.get_global_rect()   # where the toy box lies while it is browsed
	var home: Vector2 = c.pos
	var pick: Button = await toybox_button(hud._cards, "kind", "puzzle_key")
	await act(pick, "the Puzzle key card")
	check(await until(func(): return c.ghost != null and hud._tools.is_visible_in_tree(), 2.0), "[%s] picking a card shows the placement tools" % loc)
	# The thing stays where the game put it, in front of the child; the child is stood at six places.
	await tools_clear("[%s] placing a new thing" % loc, rest)
	c.cancel_ghost()
	check(await until(func(): return c.ghost == null, 2.0), "[%s] placing is cancelled again" % loc)
	await stand_at(home)
	# The same while a placed thing is edited: more buttons (put away, blueprint, give). They were wider
	# than the screen allows beside the corner column in every language (measured on first-steps r3 at
	# the iPad layout: 1227 px in English, 1437 px in German); the row must wrap instead.
	# The tools box does not shrink by itself after it has been wider (it is anchored, not laid out by a
	# parent). In the first r4 pass that left it 1131 px wide once, after the row had wrapped, depending
	# on what had been shown before. That state is set up on purpose here: the box is left as wide as
	# the screen before the chest is picked up.
	hud._tools_box.size.x = area.size.x
	c.select_item(pz["chest"])
	check(await until(func(): return c.ghost != null and c.g_edit_id == pz["chest"] and hud._tools.is_visible_in_tree(), 3.0), "[%s] the chest is picked up to edit it" % loc)
	await tools_clear("[%s] editing a placed thing" % loc, rest, "edit_tools_strip_%s" % loc)
	var shown: Array = hud._tools_row.get_children().filter(func(b): return b is Button and b.visible)
	check(shown.size() >= 5, "[%s] editing shows more buttons than placing (%d)" % [loc, shown.size()])
	# One word for placing, whether the thing is new or edited, and it is not the corner button's word.
	check(tr(hud._place_btn.text) != tr(hud._decorate_btn.text) or not hud._decorate_btn.is_visible_in_tree(), "[%s] the tools' own button does not carry the corner button's word (\"%s\", corner \"%s\")" % [loc, tr(hud._place_btn.text), tr(hud._decorate_btn.text)])
	check(hud._tools_box.size.x <= hud._tools_box.get_combined_minimum_size().x + 1.0, "[%s] the tools box is no wider than what it holds, although it was left as wide as the screen (%d of %d)" % [loc, int(hud._tools_box.size.x), int(hud._tools_box.get_combined_minimum_size().x)])
	await shot("edit_tools_%s" % loc)   # the tools while editing, for whoever judges the picture
	c.cancel_ghost()
	check(await until(func(): return c.ghost == null and Session.model.items.has(pz["chest"]), 2.0), "[%s] editing is cancelled again and the chest is where it was" % loc)
	await stand_at(home)
	# A tall thing, once per run (first language): the camera steps back until it stands whole between
	# the tools' two places, and the tools keep off it and off the child as for any other thing. (Until
	# first-steps r7 no check held a thing taller than a chest.)
	if not _tall_done:
		_tall_done = true
		var paths: Button = await toybox_button(hud._tabs, "tab", "Paths & water")
		check(paths != null, "set up: the toy box has the tab with the lamp post")
		await act(paths, "the Paths & water tab")
		await frames(4)
		var lamp: Button = await toybox_button(hud._cards, "kind", "lamp_post")
		check(lamp != null, "set up: the lamp post's card is in the toy box")
		var rest_tall: Rect2 = hud._catalog.get_global_rect()
		await act(lamp, "the Lamp post card")
		check(await until(func(): return c.ghost != null and c.g_kind == "lamp_post" and hud._tools.is_visible_in_tree(), 2.0), "picking the lamp post shows the placement tools")
		await tools_clear("placing a tall thing (a lamp post)", rest_tall, "tall_tools_strip")
		await shot("tall_tools")
		c.cancel_ghost()
		check(await until(func(): return c.ghost == null, 2.0), "placing the lamp post is cancelled again")
		await stand_at(home)
	await leave_decorate()
	await until(func(): return c.mode == "play", 2.0)
	# In the cart: both buttons, whole, apart, inside the safe area.
	await stand_at(station_at + Vector2(0.0, 1.7))
	check(await do_context("ride_board"), "[%s] Get in the cart" % loc)
	check(await until(func(): return Session.ride_of(Session.my_id) == station and hud._context_alt_btn.is_visible_in_tree(), 3.0), "[%s] in the cart" % loc)
	await frames(4)
	var main_r: Rect2 = hud._context_btn.get_global_rect()
	var alt_r: Rect2 = hud._context_alt_btn.get_global_rect()
	check(not main_r.intersects(alt_r) and area.grow(1.0).encloses(main_r) and area.grow(1.0).encloses(alt_r), "[%s] Go! and Get off are apart and inside the safe area (%s, %s)" % [loc, main_r, alt_r])
	for b in [hud._context_btn, hud._context_alt_btn]:
		var need: float = b.get_theme_font("font").get_string_size(tr(b.text), HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		check(need <= b.size.x - 24.0, "[%s] \"%s\" fits its button (%d px of %d)" % [loc, tr(b.text), int(need), int(b.size.x)])
	if tv:
		await hints_ok("[%s] in the cart" % loc)
		check(tr("Get off") in pad._hint_label.text, "[%s] the hints name Get off (%s)" % [loc, pad._hint_label.text])
	await settle_camera()
	await shot("cart_%s" % loc)
	await get_off()
	check(Session.ride_of(Session.my_id) == "", "[%s] out of the cart" % loc)
	_case_ok = true
