## The zoo, end to end through the real game (design/zoo-and-world-journeys.md 19.2 to 19.4):
## the tram stop in town, the journey and its card, the animals arriving from the authority,
## liveliness and the copycat, a station, Look with Offer a treat, the zoo camera (turns and three
## zooms), the zoo toy box's tabs, Ride home, the town's view restored, and a refused journey that
## leaves the child where it was. Touch by default; --tv drives the action button with the game
## controller's X and B through PadInput.
##   Headless (EC2): scripts/godot.sh --headless --path game -- --driver=res://tests/zoo_tour.gd \
##       --no-shots --window=1366x1024 --tag=ipad
##   TV:             ... --tv --pad-layout=nintendo --window=1920x1080 --tag=atv
extends "res://tests/pets_tour.gd"

const Places := preload("res://scripts/core/places.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")

var _checks := 0
var tv := false


func check(cond: bool, what: String) -> void:
	_checks += 1
	super.check(cond, what)


## The action button: by touch, or by the controller's context button (X on a Nintendo pad).
func act() -> void:
	if tv:
		var pad: Node = main.pad
		check(pad != null, "the game controller layer exists in TV mode")
		if pad:
			var b := JOY_BUTTON_Y   # PadInput.role_of: the context role is this button on every layout
			for pressed in [true, false]:
				var e := InputEventJoypadButton.new()
				e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
				e.button_index = b
				e.pressed = pressed
				Input.parse_input_event(e)
				await frames(3)
	else:
		await press(main.hud._context_btn)


func _axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


## By touch a tap on the ground; on TV the left stick, steered toward the goal as it shows on
## screen (stick up is screen up), as a child with a controller walks. Bounded.
func walk_to(p: Vector2) -> void:
	if not tv:
		await super.walk_to(p)
		return
	var c: Node = main.controller
	var cam: Camera3D = main.rig.camera
	for i in 600:
		if c.pos.distance_to(p) < 0.6:
			break
		var a := cam.unproject_position(Vector3(c.pos.x, 0, c.pos.y))
		var b := cam.unproject_position(Vector3(p.x, 0, p.y))
		var v := (b - a).normalized() * (1.0 if c.pos.distance_to(p) > 1.5 else 0.7)
		_axis(JOY_AXIS_LEFT_X, v.x)
		_axis(JOY_AXIS_LEFT_Y, v.y)
		await frames(1)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	check(c.pos.distance_to(p) < 1.2, "the stick walks the child to %s (%s)" % [p, c.pos])


func back_button() -> void:
	var pad: Node = main.pad
	if pad == null:
		return
	var b: int = pad.back_button()
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
		e.button_index = b
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(2)


## Walks far by tapping the ground a few metres ahead at a time, along waypoints (taps must be on
## screen, like a child's finger).
func walk_far(points: Array) -> void:
	var c: Node = main.controller
	for p in points:
		var goal: Vector2 = p
		# Face the way: the turn whose forward is closest to the direction (the zoo's 45 degree steps).
		var d: Vector2 = goal - c.pos
		if d.length() > 0.5:
			main.rig.yaw_step = posmod(int(round(atan2(-d.x, -d.y) / (TAU / 8.0))), 8)
			await settle_camera()
		for i in 25:
			if c.pos.distance_to(goal) < (0.8 if tv else 1.2):
				break
			var step: Vector2 = c.pos + (goal - c.pos).limit_length(4.0)
			await walk_to(step)
			await until(func(): return not c.walking, 4.0)


## The animal nearest the child that shows on screen, inside the safe area and not under the HUD.
func _animal_in_view() -> Node3D:
	var c: Node = main.controller
	var cam: Camera3D = main.rig.camera
	var best: Node3D = null
	var bestd := INF
	for id in main.world.zoo_world.animals:
		var n: Node3D = main.world.zoo_world.animals[id]
		if not n.visible:
			continue
		var pt := n.global_position + Vector3(0, 0.6, 0)
		if cam.is_position_behind(pt):
			continue
		var sp: Vector2 = cam.unproject_position(pt)
		if not playable_rect().has_point(sp) or ui_blocker_at(sp) != "":
			continue
		var d := Vector2(n.position.x, n.position.z).distance_to(c.pos)
		if d < bestd:
			bestd = d
			best = n
	return best


func zoo_node() -> Node:
	return get_node_or_null("/root/Zoo")


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	tv = main.args.has("tv")
	get_tree().create_timer(float(main.args.get("timeout", "300"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "300"))
		print("ZOO TOUR %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	var save := "user://zoo_tour_town.json"
	for f in [save, save + ".bak", save + ".maps", save + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	I18n.set_locale(str(main.args.get("locales", "en")).split(",")[0])
	await frames(3)
	check(zoo_node() != null, "the Zoo autoload is running")
	# ---- the tram stop in town (9.1)
	var stops: Array = Session.model.items.values().filter(func(i): return i["kind"] == "tram_stop")
	check(stops.size() == 1, "a new town has exactly one tram stop (%d)" % stops.size())
	var board: Variant = TownModel.tram_stop_boarding(Session.model)
	check(board != null, "the tram stop has a boarding point")
	if board == null:
		_finish()
		return
	var me_at: Vector2 = c.pos
	check(me_at.distance_to(board) < 9.0, "the stop is near where a child arrives (%.1f m)" % me_at.distance_to(board))
	await settle_camera()
	var stop_pos: Vector2 = Vector2(stops[0]["x"], stops[0]["z"]) if stops[0].has("x") else board
	var stop_screen: Vector2 = main.rig.camera.unproject_position(Vector3(stop_pos.x, 0.5, stop_pos.y))
	check(playable_rect().has_point(stop_screen), "the tram stop is in the first view on arrival (%s)" % stop_screen.round())
	var town_yaw: int = 3
	if tv:
		await walk_to(board)
		check(await until(func(): return c._ctx.get("type", "") == "tram", 10.0), "at the stop the action is Ride to the zoo (%s)" % c._ctx.get("type", ""))
		main.rig.yaw_step = town_yaw   # the town's own view, to be restored on return
		await settle_camera()
	# ---- the journey (12.3)
	var t0 := Time.get_ticks_msec() / 1000.0
	var phases: Array = []
	c.journey.connect(func(ph, to): phases.append([ph, to, Time.get_ticks_msec() / 1000.0 - t0]))
	if tv:
		await act()   # X: the context button
	else:
		# Touch: tap the stop itself ("Tap it, Ride to the zoo", design 17.1); the child walks there and rides.
		var sp: Vector2 = Vector2(stops[0]["x"], stops[0]["z"])
		# The stop's name tag (design 9.1) shows on arrival.
		var tag: Button = hud._tags.get("tram_stop")
		check(tag != null and tag.is_visible_in_tree() and tag.text == tr("Zoo tram"), "the stop's tag Zoo tram shows on arrival")
		# The town's own view, to be restored on return: the first turn other than the default whose view
		# still shows a part of the stop a finger can tap (not under a tag or button).
		var aim_h := -1.0
		for y in [3, 1, 2, 5, 6, 7, 4]:
			main.rig.yaw_step = y
			await settle_camera()
			for h in [0.6, 0.4, 0.9, 1.2, 1.5]:
				var a2: Vector2 = main.rig.camera.unproject_position(Vector3(sp.x, h, sp.y))
				if not main.rig.camera.is_position_behind(Vector3(sp.x, h, sp.y)) and playable_rect().has_point(a2) and ui_blocker_at(a2) == "":
					aim_h = h
					break
			if aim_h > 0.0:
				town_yaw = y
				break
		check(aim_h > 0.0, "part of the stop is clear to tap in a turned view (yaw %d)" % town_yaw)
		await tap_at_world(Vector3(sp.x, maxf(aim_h, 0.6), sp.y), "the tram stop")
		check(await until(func(): return c.journey_to == Places.ZOO, 10.0), "tapping the stop walks there and starts the ride")
		t0 += phases[0][2] if not phases.is_empty() else 0.0   # timed from the ride's own start
	print("DIAG journey after act: journey_to=%s space=%s phases=%s" % [c.journey_to, c.space, str(phases)])
	check(phases.size() >= 1 and phases[0][0] == "start" and phases[0][1] == Places.ZOO, "the journey starts (%s)" % str(phases))
	check(hud.get_node_or_null("JourneyCard") != null and (hud.get_node("JourneyCard").visible or c.space == Places.ZOO), "the journey card shows")
	check(await until(func(): return c.space == Places.ZOO and c.journey_to == "", 10.0), "the child arrives in the zoo")
	var took := Time.get_ticks_msec() / 1000.0 - t0
	check(took >= 1.15 and took < 5.0, "the journey takes at least the card's 1.2 s and stays short (%.2f s)" % took)
	await wait(0.5)
	var card: Control = hud.get_node_or_null("JourneyCard")
	check(card != null and not card.visible, "the card is gone on arrival")
	check(main.rig.on_zoo and main.rig.yaw_step == 0 and is_equal_approx(main.rig.distance(), 9.5), "the zoo starts at the designed view (yaw 0, 9.5 m)")
	check(c.pos.distance_to(ZooMap.ARRIVALS[0]) < 2.5, "the child stands on the station platform (%s)" % c.pos)
	check(main.world.zoo_world != null and main.world.zoo_world.visible, "the zoo world is shown")
	check(await until(func(): return not zoo_node().states.get("animals", []).is_empty(), 5.0), "the animals' states arrive from the authority")
	check(main.world.zoo_world.animals.size() == 18, "eighteen animals are drawn (%d)" % main.world.zoo_world.animals.size())
	check(hud._location.visible and hud._location.text.begins_with(tr("Zoo")), "the place shows the zoo (%s)" % hud._location.text)
	check(hud._ride_home.visible, "Ride home is always there in the zoo")
	check(hud._cam_tools.get_child(0).visible and hud._cam_tools.get_child(1).visible, "the turn buttons show in the zoo")
	# ---- the zoo camera (22.7): turns and three zooms
	var y0: int = main.rig.yaw_step
	await press(hud._cam_tools.get_child(1))
	check(main.rig.yaw_step == posmod(y0 + 1, 8), "Rotate turns the view a step")
	var dists := []
	for i in 3:
		await press(hud._cam_tools.get_child(2))
		dists.append(main.rig.distance())
	dists.sort()
	check(dists == [8.0, 9.5, 15.0], "Zoom steps through 8, 9.5 and 15 m in the zoo (%s)" % str(dists))
	main.rig.yaw_step = 0
	while not is_equal_approx(main.rig.distance(), 9.5):
		await press(hud._cam_tools.get_child(2))
	await settle_camera()
	# ---- Monkey Hill: liveliness, the copycat, the bell (22.4)
	await walk_far([Vector2(0.0, 12.5), Vector2(0.0, -7.5), Vector2(15.0, -7.5), Vector2(29.0, -7.5), Vector2(29.0, -12.0), Vector2(29.0, -18.0)])
	check(c.pos.distance_to(Vector2(29.0, -18.0)) < 2.5, "the child walks to the Monkey Court (%s)" % c.pos)
	var seen := {}
	for i in 60:
		await wait(0.2)
		for st in zoo_node().states.get("animals", []):
			if st["species"] == "monkey" and not st["action"] in ZooBrain.RESTS:
				seen[st["action"]] = true
	check(seen.size() >= 3, "the monkeys play in 12 s with no input (%s)" % str(seen.keys()))
	# Only free monkeys copy (zoo standard 6.4): when every one is busy on a ring, a vine or a swing, a child
	# dances again, so up to four dances, 3 s apart (city r1 battery: the troop was all busy once in eight runs).
	var copied := false
	for attempt in 4:
		Session.send_emote("dance")
		for i in 30:
			await wait(0.1)
			for st in zoo_node().states.get("animals", []):
				if st["action"] == "copy":
					copied = true
		if copied:
			break
	check(copied, "a dance on Monkey Hill: the troop copies it")
	# 1.5 m off: inside the 1.8 m reach, outside the 1.2 m within which a tap on the ground uses the station
	# (The stick stops within 0.6 m of its goal, so the controller walks to 0.9 m.)
	await walk_far([ZooMap.STATIONS["monkey_bell"]["pos"] + Vector2(0, 0.9 if tv else 1.5)])
	main.rig.yaw_step = 0
	await settle_camera()
	check(await until(func(): return c._ctx.get("type", "") == "zoo_station" and c._ctx.get("id", "") == "monkey_bell", 8.0), "at the bell the action is Ring the bell (%s)" % c._ctx)
	# A ring can be refused when the monkeys are busy ("Try again in a moment", design 10.3); the child
	# then rings again a moment later, as the line says. At most three tries.
	var hints: Array = []
	var on_hint := func(t): hints.append(t)
	c.hint.connect(on_hint)
	var rang := false
	for attempt in 3:
		hints.clear()
		await act()
		await wait(0.5)
		if hints.has("They are busy right now. Try again in a moment."):
			print("DIAG bell: busy on try %d: %s" % [attempt + 1, str(zoo_node().states.get("animals", []).filter(func(st): return st["species"] == "monkey").map(func(st): return [st["id"], st["action"], st.get("line", "")]))])
			await wait(2.0)
			continue
		rang = await until(func(): return zoo_node().states.get("animals", []).any(func(st): return st["action"] == "bell"), 25.0)
		break
	c.hint.disconnect(on_hint)
	if not rang:
		print("DIAG bell: ctx %s monkeys %s" % [c._ctx, str(zoo_node().states.get("animals", []).filter(func(st): return st["species"] == "monkey").map(func(st): return [st["id"], st["action"]]))])
	check(rang, "a monkey races up the Spire and rings the bell")
	# ---- Look (11.1) with Offer a treat
	await settle_camera()
	# The nearest animal actually in view (on screen, not under the HUD). The monkeys move about the
	# whole hill, so the tour waits up to 12 s for one to be in view, as a child would.
	var node: Node3D = null
	for k in 60:
		node = _animal_in_view()
		if node != null:
			break
		await wait(0.2)
	if node == null:
		print("DIAG look: pos %s yaw %d dist %.1f area %s" % [c.pos, main.rig.yaw_step, main.rig.distance(), playable_rect()])
		for id in main.world.zoo_world.animals:
			var n: Node3D = main.world.zoo_world.animals[id]
			var pt := n.global_position + Vector3(0, 0.6, 0)
			var sp: Vector2 = main.rig.camera.unproject_position(pt)
			print("DIAG   %s vis=%s at %s screen %s blocker '%s'" % [id, n.visible, pt.round(), sp.round(), ui_blocker_at(sp)])
	check(node != null, "an animal comes into view to look at within 12 s")
	if node == null:
		_finish()
		return
	await tap_at_world(node.global_position + Vector3(0, 0.6, 0), "an animal (%s)" % node.name)
	check(await until(func(): return c.look_id != "", 3.0), "tapping an animal starts Look (%s)" % c.look_id)
	if c.look_id != "":
		check(hud._look_strip != null and hud._look_strip.visible, "the Look strip shows")
		var offer: Button = hud._look_strip.find_child("Offer", true, false)
		check(offer != null and offer.is_visible_in_tree(), "it offers a treat")
		var looked: String = c.look_id
		hud._dialog("Photo ideas", "", [["Close", func(): pass, true]])
		await frames(2)
		check(c.look_id == "" and not hud._look_strip.visible, "a dialog ends Look")
		await close_dialogs()
		c.start_look(looked)
		await frames(2)
		check(c.look_id == looked, "Look starts again on %s" % looked)
		if tv:
			await back_button()
			check(c.look_id == "", "B ends Look")
		else:
			var done_b: Button = hud._look_strip.find_child("Done", true, false)
			var rects := []
			for k in 5:
				rects.append(done_b.get_global_rect().position.round())
				await frames(1)
			await press(done_b)
			if c.look_id != "":
				print("DIAG done: rects over 5 frames %s, now %s, look %s, strip place %s" % [rects, done_b.get_global_rect(), c.look_id, hud._look_place])
			check(c.look_id == "", "Done ends Look")
	# ---- the zoo toy box (10.4)
	await press(hud._decorate_btn)
	await frames(4)
	var tabs: Array = hud._tabs.get_children().filter(func(b): return b.has_meta("tab")).map(func(b): return b.get_meta("tab"))
	check(tabs.has("Zoo") and tabs.has("Picnic") and not tabs.has("Nature"), "the zoo's toy box has the Zoo and Picnic tabs (%s)" % str(tabs))
	await press(hud._decorate_btn)
	await frames(3)
	# ---- the scrapbook's Zoo friends page (10.6): its own page, so the scrapbook is as short as before
	hud.open_scrapbook()
	await frames(3)
	var zbtn: Button = null
	for bt in hud._overlay.find_children("*", "Button", true, false):
		if bt.text == tr("Zoo friends"):
			zbtn = bt
	check(zbtn != null, "the scrapbook has a Zoo friends button")
	if zbtn:
		zbtn.pressed.emit()
		await frames(3)
		var rows: Array = hud._overlay.find_children("ZooFriends_*", "VBoxContainer", true, false)
		# One row per ZooLife.ANSWERS entry: the seven species, with Rory (lion) and Honey (lioness) apart.
		var credit: Node = hud._overlay.find_child("AnimalModelCredit", true, false)
		check(credit != null and credit is Label and "CC BY 4.0" in (credit as Label).text and "David OReilly" in (credit as Label).text,
			"the page credits the Everything Library models (CC BY 4.0)")
		check(rows.size() == ZooLife.ANSWERS.size() and rows.size() == 11, "the Zoo friends page lists every animal kind: r1's eight and the panda, elephant and penguin (%d rows)" % rows.size())
		var back: Button = null
		for bt in hud._overlay.find_children("*", "Button", true, false):
			if bt.get_meta("dialog_button", "") == "Back":
				back = bt
		check(back != null, "the page has Back")
		if back:
			back.pressed.emit()
			await frames(4)
			check(hud._overlay.get_child_count() > 0 and hud._overlay.find_children("*", "Button", true, false).any(func(bt): return bt.text == tr("Zoo friends")), "Back returns to the scrapbook")
	await close_dialogs()
	# ---- Ride home (9.2) and the town's view
	t0 = Time.get_ticks_msec() / 1000.0
	await press(hud._ride_home)
	check(await until(func(): return c.space == "town" and c.journey_to == "", 10.0), "Ride home brings the child back to town")
	check(not main.rig.on_zoo and main.rig.yaw_step == town_yaw, "the town's own view comes back (yaw %d)" % main.rig.yaw_step)
	check(c.pos.distance_to(board) < 2.5, "arriving at the town's tram stop (%s)" % c.pos)
	check(not hud._ride_home.visible, "Ride home is not shown in town")
	check(main.world.activity._discovered.has("tram_stop"), "after a ride the stop's tag shows only close by")
	# ---- refusals (12.4): an unknown place is refused by the authority; nothing changes
	c.ride("moon")
	await frames(3)
	check(c.journey_to == "" and c.space == "town", "a journey to an unknown place does not start")
	var refused := {}
	var req: int = Session.travel("moon")
	c._ask(req, func(r): refused.merge(r))
	check(await until(func(): return not refused.is_empty(), 3.0) and not refused.get("ok", true), "the authority refuses an unknown destination (%s)" % str(refused))
	check(c.space == "town" and Session.players[Session.my_id]["state"].get("space", "") == "town", "and the child stays in town")
	var card2: Control = hud.get_node_or_null("JourneyCard")
	check(card2 == null or not card2.visible, "no card is left showing")
	_finish()


func _finish() -> void:
	print("ZOO TOUR %s %s: %d checks, %d failures" % [tag, "PASS" if failures == 0 else "FAIL", _checks, failures])
	Music.quit_game(1 if failures else 0)
