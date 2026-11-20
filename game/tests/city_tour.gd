## The city district end to end through the real game (design/city-district.md, acceptance path 5): the
## tram from town, the strolling view on arrival (dest-fix r1) and the overview one zoom-out away, orbit, zoom and reset, walking into the cafe and
## sitting, climbing to the office's upper floor and crossing both skywalks, the rooftop restaurant, the
## treadmill, a shop, the Ferris wheel (board at the bottom, ride, off at the bottom), and the bus home.
## Every walk is a real tap on a floor-aware pick; every use is the action button.
##   Headless: scripts/godot.sh --headless --path game -- --driver=res://tests/city_tour.gd --no-shots \
##       --window=1366x1024 --tag=ipad
##   TV (controller only: the stick walks CityNav's routes, L/R turn, the triggers zoom, the context button):
##       ... --tv --pad-layout=nintendo --window=1920x1080 --tag=atv
##   Mac GPU frames: scripts/godot.sh --path game --resolution 1280x720 -- --driver=res://tests/city_tour.gd \
##       --shots=/abs/dir --tag=ipad   (at most 30 JPG frames: overview, cutaways, stairs, skywalks, wheel,
##       avatar level, each interaction)
extends "res://tests/zoo_tour.gd"

const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const CityOrbit := preload("res://scripts/world/city_orbit.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const MAX_FRAMES := 30   # r3: three weather frames more (sunny, rain, night); dest-fix r1: the arrival frame
## The refinement close-ups for the Mac capture (user feedback 2026-11-16): [name, focus, yaw, pitch deg, distance].
## The camera looks north at yaw 0, at the open fronts and the shop row.
const SHOWCASE := [
	["shop_row", Vector3(-8.0, 1.2, 15.0), 0.0, 24.0, 15.0],
	["coral_terraces", Vector3(13.0, 3.6, -5.0), 0.2, 26.0, 15.0],
	["rooftop_restaurant", Vector3(11.8, 6.6, -11.0), 0.5, 48.0, 12.0],
	["office_interior", Vector3(-17.0, 3.0, -6.0), -0.2, 18.0, 13.0],
	["cafe_coffee_bar", Vector3(-3.0, 0.8, -6.0), 0.15, 28.0, 11.0],
	["stairs_skywalks", Vector3(-6.0, 3.0, -8.0), 0.9, 32.0, 18.0],
	["paths_flower_beds", Vector3(-4.0, 0.0, 4.0), 0.3, 55.0, 20.0],
	["ferris_wheel", Vector3(16.0, 5.0, 4.0), -0.6, 18.0, 22.0],
]

var _frames := 0


func frame(name: String) -> void:
	if _frames >= MAX_FRAMES:
		check(false, "at most %d frames (%s is one more)" % [MAX_FRAMES, name])
		return
	if main.args.has("frames-dry"):
		_frames += 1   # headless: every frame step runs and is counted, nothing is rendered or saved
		return
	if main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_frames += 1
	var err := get_viewport().get_texture().get_image().save_jpg("%s/city_%s_%02d_%s.jpg" % [shots, tag, _frames, name], 0.85)
	check(err == OK, "frame %s saved" % name)


## GPU frames only: each refined area from a fixed close view (the camera follows a marker, then the child again).
func showcase() -> void:
	if main.args.has("no-shots") and not main.args.has("frames-dry"):
		return
	var mark := Node3D.new()
	main.world.add_child(mark)
	var keep: Node3D = main.rig.target
	for v in SHOWCASE:
		mark.global_position = (v[1] as Vector3) - Vector3(0.0, CityOrbit.FOCUS_LIFT, 0.0)
		main.rig.target = mark
		main.rig.city_state = {"yaw": float(v[2]), "pitch": deg_to_rad(float(v[3])), "distance": float(v[4]), "out": false}
		main.rig.snap()
		await frames(4)
		await frame("show_" + str(v[0]))
	main.rig.target = keep
	mark.queue_free()
	main.rig.city_overview()
	main.rig.snap()
	await frames(3)


func city() -> Node:
	return get_node_or_null("/root/City")


## Taps the screen point where a world point shows (a real finger), only if it is on screen and free of UI.
func tap_world(p: Vector3, what: String) -> bool:
	var cam: Camera3D = main.rig.camera
	if cam.is_position_behind(p):
		check(false, "%s is in front of the camera" % what)
		return false
	var aim := cam.unproject_position(p)
	var ok_tap := playable_rect().has_point(aim) and ui_blocker_at(aim) == ""
	check(ok_tap, "the tap on %s is on screen and free (%s; in play area %s, blocked by '%s')" % [what, aim.round(), playable_rect().has_point(aim), ui_blocker_at(aim)])
	if ok_tap:
		await tap(aim)
	return ok_tap


## Walks to a place in the city by tapping it in the overview (the whole block shows at about 19 px a
## metre on an iPad, enough for a finger), then waits for the child to get there.
func go(region: String, at: Vector2, what: String, approach: Variant = null) -> bool:
	var c: Node = main.controller
	if tv:
		return await stick_go(region, at, what)
	main.rig.city_overview()   # dest-fix r1: Reset view now returns to the child; the walks tap on the whole block
	main.rig.snap()
	await frames(3)
	var y := CityNav.height(region, at)
	if approach != null:
		# Inside a building under its terrace or roof: walk up to the front first, then look in from a low,
		# close view (as a player would) and tap the floor inside.
		var ap: Vector2 = approach
		if not await tap_world(Vector3(ap.x, 0.0, ap.y), what + " (its front)"):
			return false
		check(await until(func(): return c.pos.distance_to(ap) < 1.3, 40.0), "the child walks up to %s's front (%s)" % [what, c.pos.round()])
		var d: Vector2 = at - (c.pos as Vector2)
		main.rig.city_state = {"yaw": atan2(-d.x, -d.y), "pitch": deg_to_rad(26.0), "distance": 9.0, "out": false}
		main.rig.snap()
		await frames(3)
	if not await tap_world(Vector3(at.x, y, at.y), what):
		return false
	var arrived := await until(func(): return c.level == region and c.pos.distance_to(at) < 1.3, 40.0)
	check(arrived, "the child walks to %s (at %s on '%s', wanted %s on '%s')" % [what, c.pos.round(), c.level, at, region])
	# The walk ends a little later (a tapped seat or machine is used on arrival, 0.9 m out): settle first.
	await until(func(): return c._walk_target == null and c._pending_ctx.is_empty(), 3.0)
	await wait(0.3)
	return arrived


## TV: the stick walks the route the city's navigation gives (the stairs, skywalks and doors in turn),
## pushed toward each waypoint as a player would, gently near it.
func stick_go(region: String, at: Vector2, what: String) -> bool:
	var c: Node = main.controller
	var route: Array = CityNav.route(c.level, c.pos, region, at)
	check(not route.is_empty(), "there is a way to %s" % what)
	var stuck := 0
	for w in route:
		var p: Vector2 = w["pos"]
		for i in 900:
			var d: Vector2 = p - c.pos
			if d.length() < 0.1:
				break
			var r: Vector2 = main.rig.flat_right()
			var f: Vector2 = main.rig.flat_forward()
			var push := 1.0 if d.length() > 0.8 else 0.4
			var stick := Vector2(d.normalized().dot(r), -d.normalized().dot(f)).normalized() * push
			_axis(JOY_AXIS_LEFT_X, stick.x)
			_axis(JOY_AXIS_LEFT_Y, stick.y)
			var before: Vector2 = c.pos
			await frames(1)
			stuck = stuck + 1 if (c.pos as Vector2).distance_to(before) < 0.002 else 0
			if stuck > 90:
				break
		if stuck > 90:
			break
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	var arrived: bool = c.level == region and (c.pos as Vector2).distance_to(at) < 0.6
	check(arrived, "the stick walks the child to %s (at %s on '%s', wanted %s on '%s')" % [what, (c.pos as Vector2).round(), c.level, at, region])
	return arrived


func _pad_button(b: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.set_meta("synthetic", true)   # tv-diag: injected by this test driver, not hardware
		e.button_index = b
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(3)


func _pad_trigger(axis: int) -> void:
	for v in [1.0, 0.0]:
		_axis(axis, v)
		await frames(3)


func use_here(type: String, what: String) -> bool:
	var c: Node = main.controller
	var ok_ctx := await until(func(): return c._ctx.get("type", "") == type, 6.0)
	check(ok_ctx, "%s is offered (%s)" % [what, c._ctx])
	if ok_ctx:
		await act()   # zoo_tour: by touch, or the controller's context button with --tv
		await wait(0.6)
	return ok_ctx


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	tv = main.args.has("tv")
	get_tree().create_timer(float(main.args.get("timeout", "600"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "600"))
		_finish()
		)
	var save := "user://city_tour_town.json"
	for f in [save, save + ".bak", save + ".maps", save + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	check(Session.PROTOCOL == 20, "protocol 20")
	check(city() != null, "the City autoload is running")
	# ---- from town: the tram stop offers the city beside the zoo
	var board: Variant = TownModel.tram_stop_boarding(Session.model)
	await walk_to(board)
	check(await until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.get("alt", {}).get("type", "") == "tram_city", 10.0), "the tram stop offers Ride to the city")
	c.do_context(c._ctx["alt"])
	check(await until(func(): return c.space == "city" and c.journey_to == "", 12.0), "the child arrives in the city")
	check(c.pos.distance_to(CityMap.ARRIVALS[0]) < 1.5, "at the bus stop (%s)" % c.pos)
	# dest-fix r1 (the user's acceptance: furniture placement does not apply in the city): no Decorate here, and
	# decorate mode cannot be entered by any path (the HUD button, the controller's or keyboard's shortcut)
	var hud0: Control = main.hud
	check(not hud0._decorate_btn.is_visible_in_tree(), "the city shows no Decorate")
	c.set_mode("decorate")
	check(c.mode == "play", "decorate mode cannot be entered in the city")
	check(Catalog.kinds_for("Furniture", "city").is_empty() and not Catalog.allowed_in("bamboo_floor_lantern", "city"), "and the toy box offers nothing for the city")
	await wait(0.6)
	# A town change while the child is in the city (a friend decorating) rebuilds the town's items: the
	# city must stay in view (it once fell back to the town's view and lost the city's poses and light).
	main.world._rebuild_items()
	await frames(2)
	check(main.world.view_space == "city" and main.world.city_world.visible, "the city stays in view when the town changes (%s)" % main.world.view_space)
	# ---- r2: the city is already alive on arrival: about 50 people, moving, nobody to start
	var people: Node = main.world.city_people
	check(people != null and people.visible, "the city's people are there")
	if people:
		check(people.people.size() >= 50, "about fifty people (%d)" % people.people.size())
		var snap0: Array = people.snapshot()
		await wait(0.5)
		var snap1: Array = people.snapshot()
		var moved := 0
		for i in mini(snap0.size(), snap1.size()):
			for j in mini((snap0[i] as Array).size(), (snap1[i] as Array).size()):
				if not (snap0[i][j] as Transform3D).is_equal_approx(snap1[i][j]):
					moved += 1
		check(moved > 50, "and already moving, half a second after arriving (%d parts moved)" % moved)
	# ---- dest-fix r1 (the user's acceptance on the installed r3: the city is for strolling with one's own
	# character): the city opens on the strolling view that follows the player's own child, large and centred,
	# its name readable; the whole block is one zoom-out away, where the own name grows to stay readable.
	var cam: Camera3D = main.rig.camera
	var view := get_viewport().get_visible_rect().size
	var stroll: Dictionary = CityOrbit.stroll(main.rig._aspect())
	check(main.rig.on_city and not bool(main.rig.city_state.get("out", false))
		and is_equal_approx(float(main.rig.city_state["distance"]), float(stroll["distance"])),
		"the city opens on the strolling view (%.1f m, was the overview)" % float(main.rig.city_state["distance"]))
	await frames(3)
	var me: Node3D = main.world.kids.get(Session.my_id)
	var feet_sp := cam.unproject_position(me.global_position)
	var head_sp := cam.unproject_position(me.global_position + Vector3(0, 1.3, 0))
	check(feet_sp.distance_to(head_sp) >= 60.0, "the player's own child is large on arrival (%.0f px tall, was 13)" % feet_sp.distance_to(head_sp))
	check(absf(feet_sp.x - view.x * 0.5) < view.x * 0.15 and absf(feet_sp.y - view.y * 0.5) < view.y * 0.25,
		"and near the middle of the screen (%s)" % feet_sp.round())
	check(me._label != null and is_equal_approx(me._label.scale.x, 1.0), "its name at its usual size")
	await frame("arrival")
	for i in 6:
		main.rig.city_step_zoom(-1)
	main.rig.snap()
	await frames(3)
	check(bool(main.rig.city_state.get("out", false)), "zooming out reaches the overview")
	var inside := 0
	for corner in [Vector3(-CityMap.HALF.x + 3, 0, -CityMap.HALF.y + 3), Vector3(CityMap.HALF.x - 3, 0, -CityMap.HALF.y + 3),
			Vector3(-CityMap.HALF.x + 3, 0, CityMap.HALF.y - 3), Vector3(CityMap.HALF.x - 3, 0, CityMap.HALF.y - 3), Vector3(16.0, 13.6, 4.0)]:
		var sp := cam.unproject_position(corner)
		if not cam.is_position_behind(corner) and Rect2(Vector2.ZERO, view).has_point(sp):
			inside += 1
	check(inside == 5, "the whole block and the top of the wheel are in the overview (%d of 5)" % inside)
	check(me._label.scale.x > 4.0, "and the player's own name grows to stay readable there (x%.1f)" % me._label.scale.x)
	await frame("overview")
	main.rig.city_reset()
	main.rig.snap()
	await frames(2)
	check(not bool(main.rig.city_state.get("out", false)) and is_equal_approx(float(main.rig.city_state["distance"]), float(stroll["distance"])),
		"Reset view brings the child back (the strolling view)")
	# ---- orbit, zoom, reset
	var yaw0: float = main.rig.city_state["yaw"]
	if tv:
		# The controller (design/tv-controller.md: the triggers are the mouse wheel): R turns the view a step,
		# ZL zooms in, ZR zooms back out to the whole block.
		await _pad_button(JOY_BUTTON_RIGHT_SHOULDER)
		check(absf(angle_difference(yaw0, float(main.rig.city_state["yaw"]))) > 0.1, "R turns the view")
		var dz: float = main.rig.city_state["distance"]
		await _pad_trigger(JOY_AXIS_TRIGGER_LEFT)
		check(float(main.rig.city_state["distance"]) < dz and not bool(main.rig.city_state.get("out", false)), "ZL zooms in")
		for i in 30:
			if bool(main.rig.city_state.get("out", false)):
				break
			await _pad_trigger(JOY_AXIS_TRIGGER_RIGHT)
		check(bool(main.rig.city_state.get("out", false)), "ZR zooms back out to the whole block")
	if not tv:
		await _touch_camera(view, c, hud)
	await showcase()
	await _look(c, hud)
	await _weather_and_pan(c, hud)
	# ---- the cafe: walk in through the open front and sit down
	await _cafe_and_on(c, hud)


## city r3: the shared weather by the glass buttons on the right (a gradual blend, the light follows, nothing
## is created or destroyed), and a right drag that pans (never a tap, never moves the child; Reset clears it).
func _weather_and_pan(c: Node, hud: Control) -> void:
	var cw: Node = main.world.city_world
	var box: Control = hud.find_child("CityWeather", true, false)
	check(box != null and box.is_visible_in_tree(), "the weather buttons are on the right in the city")
	var view := get_viewport().get_visible_rect().size
	if box:
		check(box.get_global_rect().get_center().x > view.x * 0.8, "on the right (%.0f of %.0f)" % [box.get_global_rect().get_center().x, view.x])
	var nodes0 := _count_nodes(cw)
	var sky0: Color = main.world._env.background_color
	for wname in ["rain", "night", "sunny"]:
		var b: Button = hud.find_child("Weather_" + wname, true, false)
		check(b != null, "a %s button" % wname)
		if b == null:
			continue
		if tv:
			b.pressed.emit()   # the controller's A on the button (its pointer reaches it like every HUD button)
		else:
			await press(b)
		var want := CityMap.WEATHERS.find(wname)
		check(await until(func(): return int(city().states.get("weather", -1)) == want, 3.0), "the city's weather is %s for everyone" % wname)
		if not cw.has_method("weather_weights"):
			check(false, "city_world.weather_weights exists")
			continue
		# A blend, not a cut: some time into the change the mix is part-way, then it settles.
		await wait(float(CityMap.WEATHER_BLEND) * 0.35)
		var mid: float = float(cw.weather_weights().get(wname, 0.0))
		check(mid > 0.05 and mid < 0.95, "%s blends in gradually (%.2f a third of the way)" % [wname, mid])
		await wait(float(CityMap.WEATHER_BLEND) * 0.8)
		check(float(cw.weather_weights().get(wname, 0.0)) > 0.98, "and settles on %s" % wname)
		await frame("weather_" + wname)
	check(_count_nodes(cw) == nodes0, "no node was created or destroyed by the weather (%d, %d)" % [nodes0, _count_nodes(cw)])
	check(main.world._env.background_color.is_equal_approx(sky0), "back to the sunny white sky")
	# Right drag pans (desktop); the child stays and nothing is tapped.
	if not tv:
		main.rig.city_reset()
		main.rig.snap()
		await frames(2)
		var at: Vector2 = c.pos
		var p0: Vector2 = view * 0.5
		var press_r := InputEventMouseButton.new()
		press_r.button_index = MOUSE_BUTTON_RIGHT
		press_r.pressed = true
		press_r.position = p0
		c._city_input(press_r)
		for i in 10:
			var m := InputEventMouseMotion.new()
			m.position = p0 + Vector2(i * 18.0, i * 6.0)
			c._city_input(m)
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_RIGHT
		rel.pressed = false
		rel.position = p0 + Vector2(180, 60)
		c._city_input(rel)
		var pan: Vector3 = main.rig.city_state.get("pan", Vector3.ZERO)
		check(pan.length() > 1.0, "a right drag pans the view (%s)" % pan)
		check(c.pos.distance_to(at) < 0.05 and c._walk_target == null, "and neither walks nor taps")
		main.rig.city_reset()
		check((main.rig.city_state.get("pan", Vector3.ZERO) as Vector3).length() < 0.001, "Reset view clears the pan")


func _count_nodes(n: Node) -> int:
	var k := 1
	for ch in n.get_children():
		k += _count_nodes(ch)
	return k


## city r2, Look: a tap glides in to a building (no snap), empty space glides back, Pause freezes the city on
## this screen and Resume catches up, Esc (B on a controller) ends it and taps walk again. The child stays.
func _look(c: Node, hud: Control) -> void:
	var rig: Node = main.rig
	var kid_at: Vector2 = c.pos
	var look_btn: Button = hud.find_child("CityLook", true, false)
	check(look_btn != null and look_btn.is_visible_in_tree(), "Look around is there in the city")
	check(not (hud.find_child("CityPause", true, false) as Control).is_visible_in_tree(), "Pause shows only while looking")
	if tv:
		c.set_city_look(true)   # the controller reaches the button with the D-pad; the toggle is the same call
	else:
		await press(look_btn)
	check(c.city_looking, "Look is on")
	var pause_btn: Button = hud.find_child("CityPause", true, false)
	check(pause_btn.is_visible_in_tree(), "Pause shows while looking")
	var view := get_viewport().get_visible_rect().size
	var targets := ["office", "tower", "ferris", "carousel"] if not tv else []
	for key in targets:
		var p: Dictionary = CityMap.LOOK_PLACES[key]
		rig.city_overview()
		rig.snap()
		await frames(3)
		# Where a player taps: the tower low on its open front (its upper part is the rooftop restaurant).
		# (the wheel stands in front of the tower's east part, seen from the south: tap its west end)
		var aim: Vector3 = Vector3(7.9, 1.6, -3.1) if key == "tower" else (p["focus"] as Vector3)
		var cam: Camera3D = rig.camera
		var sp := cam.unproject_position(aim)
		await tap(sp)
		await frames(2)
		var d0: float = cam.global_position.distance_to(aim)
		check(rig.city_look == key, "a tap on the %s looks at it (%s)" % [key, rig.city_look])
		check(rig.city_gliding(), "the camera glides to the %s, it does not jump" % key)
		await wait(float(rig._glide_dur) * 0.4)   # the glide's own length (shorter with Reduce motion)
		var d_mid: float = cam.global_position.distance_to(aim)
		await until(func(): return not rig.city_gliding(), 3.0)
		await frames(2)
		var d1: float = cam.global_position.distance_to(aim)
		check(d1 < d_mid and d_mid < d0, "closer and closer: %.1f, %.1f, %.1f m" % [d0, d_mid, d1])
		var want: float = CityOrbit.look_state(key, view.x / view.y)["distance"]
		check(absf(d1 - want) < 1.0, "framed at %.1f m (wanted %.1f for this screen)" % [d1, want])
		await frame("look_" + key)
	if tv:
		var seen := {}
		for i in 3:
			await _pad_button(JOY_BUTTON_DPAD_RIGHT)
			await until(func(): return not rig.city_gliding(), 3.0)
			seen[rig.city_look] = true
		check(seen.size() == 3 and not seen.has(""), "the D-pad steps through three places (%s)" % str(seen.keys()))
	# Empty space (the white world beyond the block) glides back to the overview, still looking.
	if not tv:
		# Empty space: a point free of the HUD over no place (the road, a lawn, the white world), as a player taps.
		var empty := Vector2(-1, -1)
		var cam2: Camera3D = rig.camera
		for gy in range(6, 0, -1):
			for gx in range(1, 10):
				var sp := Vector2(view.x * gx / 10.0, view.y * gy / 7.0)
				if playable_rect().has_point(sp) and ui_blocker_at(sp) == "" \
						and CityOrbit.pick_place(cam2.project_ray_origin(sp), cam2.project_ray_normal(sp)) == "":
					empty = sp
					break
			if empty.x >= 0.0:
				break
		check(empty.x >= 0.0, "there is empty space on screen to tap (%s)" % empty)
		await tap(empty)
		await until(func(): return not rig.city_gliding(), 3.0)
		check(rig.city_look == "" and c.city_looking, "a tap on empty space glides back to the overview, still looking")
		rig.city_look_at("restaurant")
		await until(func(): return not rig.city_gliding(), 3.0)
	# Pause and Resume
	var cw: Node = main.world.city_world
	if cw.has_method("view_time"):
		var t0: float = cw.view_time()
		if tv:
			c.set_city_paused(true)
		else:
			await press(pause_btn)
		check(c.city_paused, "Pause pauses")
		var tp: float = cw.view_time()
		await wait(1.0)
		check(absf(cw.view_time() - tp) < 0.05, "while paused the city stands still on this screen (%.2f, %.2f)" % [tp, cw.view_time()])
		check(Session.is_authority() and city().est_time() > tp + 0.5, "the shared city runs on")
		if tv:
			c.set_city_paused(false)
		else:
			await press(pause_btn)
		check(not c.city_paused, "Resume")
		await wait(0.2)
		var tr0: float = cw.view_time()
		await wait(0.2)
		check(cw.view_time() > tr0 and cw.view_time() <= city().est_time() + 0.05, "and catches up without jumping")
		check(t0 >= 0.0, "the city was running on arrival")
	else:
		check(false, "the city's view clock (city_world.view_time) exists")
	await frame("look_paused")
	# Esc (B on a controller) ends Look: back to the strolling view (dest-fix r1), and taps walk again.
	if tv:
		await back_button()
	else:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		Input.parse_input_event(esc)
	await frames(3)
	check(not c.city_looking and not c.city_paused, "Esc / B leaves Look")
	await until(func(): return not rig.city_gliding(), 3.0)
	check(not bool(rig.city_state.get("out", false)) and rig.city_look == "", "and glides back to the strolling view, the child again (dest-fix r1)")
	check(c.pos.distance_to(kid_at) < 0.5 and c.space == "city", "the child stayed where it was all along")


func _touch_camera(view: Vector2, c: Node, hud: Control) -> void:
	var yaw0: float = main.rig.city_state["yaw"]
	main.controller._city_input(_mouse_button(Vector2(view.x * 0.5, view.y * 0.85), true))
	for i in 8:
		var e := InputEventMouseMotion.new()
		e.position = Vector2(view.x * 0.5 + i * 20.0, view.y * 0.85)
		main.controller._city_input(e)
	main.controller._city_input(_mouse_button(Vector2(view.x * 0.5 + 160.0, view.y * 0.85), false))
	check(absf(angle_difference(yaw0, float(main.rig.city_state["yaw"]))) > 0.1, "a drag orbits the view")
	check(c.space == "city" and c.pos.distance_to(CityMap.ARRIVALS[0]) < 1.5, "and does not move the child")
	var d0: float = main.rig.city_state["distance"]
	var wheel := _mouse_button(Vector2(view.x * 0.5, view.y * 0.5), true)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	main.controller._city_input(wheel)
	check(float(main.rig.city_state["distance"]) < d0, "the wheel zooms in")
	check(hud.get_node_or_null("%CityReset") != null or hud.find_child("CityReset", true, false) != null, "Reset view is there in the city")
	await press(hud.find_child("CityReset", true, false))
	check(not bool(main.rig.city_state.get("out", false)), "Reset view returns to the strolling view (dest-fix r1)")


func _cafe_and_on(c: Node, hud: Control) -> void:
	if await go("", CityMap.INTERACTIONS["cafe_seat_a"]["pos"], "the cafe seat", Vector2(-3.0, 0.8)):
		await frame("cafe_inside")
		# A tap on a seat walks there and sits (the zoo's stations work the same way); if not yet, use it.
		if c.city_hold.is_empty():
			await use_here("city_use", "Sit down")
		if true:
			check(await until(func(): return not c.city_hold.is_empty() and main.world.local_kid().anim == "sit", 3.0), "the child sits at the cafe table (hold %s, anim %s, view %s, space %s)" % [c.city_hold, main.world.local_kid().anim, main.world.view_space, c.space])
			await frame("cafe_sitting")
			await use_here("city_release", "Stand up")
			check(await until(func(): return c.city_hold.is_empty() and main.world.local_kid().anim != "sit", 2.0), "and stands up (hold %s, anim %s)" % [c.city_hold, main.world.local_kid().anim])
			if main.args.has("stop-after-cafe"):
				_finish()
				return
	# ---- up the office's outside stair, across skywalk A to the cafe terrace, skywalk B to the gym, up to the roof
	# The office's first floor shows through its open front only near the facade (the floor above covers the rest).
	if await go("office_l1", Vector2(-17.0, -2.6), "the office's first floor (through the open front)"):
		check(absf(main.world.local_kid().global_position.y - 3.2) < 0.15, "the child stands at 3.2 m (%.2f)" % main.world.local_kid().global_position.y)
		await frame("office_l1_cutaway")
	if await go("cafe_terrace", Vector2(-2.0, -8.0), "the cafe terrace (across skywalk A)"):
		await frame("cafe_terrace")
	var told: Array = []
	var on_toast := func(t): told.append(t)
	c.toast.connect(on_toast)
	if await go("gym_roof", CityMap.INTERACTIONS["restaurant_order"]["pos"], "the rooftop restaurant (across skywalk B and up)"):
		await frame("rooftop")
		if not told.has(CityMap.LINES["dinner"]):
			await use_here("city_use", "Order dinner")
		check(await until(func(): return told.has(CityMap.LINES["dinner"]), 3.0), "dinner comes (%s)" % str(told))
	c.toast.disconnect(on_toast)
	# ---- back down to the gym's treadmill
	if await go("", CityMap.INTERACTIONS["gym_treadmill_a"]["pos"] + Vector2(0, 0.7), "the gym treadmill", Vector2(10.5, 0.5)):
		if c.city_hold.is_empty():
			await use_here("city_use", "Run on the treadmill")
		if true:
			check(await until(func(): return main.world.local_kid().anim == "jog", 3.0), "the child runs on the treadmill")
			await frame("treadmill")
			await use_here("city_release", "Stand up")
	# ---- a shop: a tap on its doorstep walks the child in through the door to the counter
	main.rig.city_overview()
	main.rig.snap()
	await frames(3)
	if tv:
		await go("", CityMap.INTERACTIONS["shop_icecream"]["pos"], "the ice cream shop (in through its door)")
		await use_here("city_use", "Buy an ice cream")
	elif await tap_world(Vector3(4.0, 0.0, 15.6), "the ice cream shop's doorstep"):
		check(await until(func(): return c.pos.distance_to(CityMap.INTERACTIONS["shop_icecream"]["pos"]) < 1.0, 30.0), "the child walks in through the door (%s)" % c.pos.round())
		await frame("shop")
	# ---- the Ferris wheel: board at the bottom, ride, get off at the bottom
	if await go("", CityMap.FERRIS["board_at"], "the Ferris wheel platform"):
		var boarded := false
		for attempt in 12:
			if c._city_riding() >= 0:
				boarded = true   # the tap on the platform boarded (tap-to-use)
				break
			await use_here("city_board", "Ride the wheel")
			if await until(func(): return c._city_riding() >= 0, 2.0):
				boarded = true
				break
			await wait(4.0)
		check(boarded, "the child boards a gondola at the bottom")
		if boarded:
			await wait(16.0)   # a fifth of a turn: the gondola is well up
			check(main.world.local_kid().global_position.y > 2.0 and main.world.local_kid().anim == "ride", "riding up (%.1f m, anim %s)" % [main.world.local_kid().global_position.y, main.world.local_kid().anim])
			await frame("ferris_ride")
			await use_here("city_off", "Get off at the bottom")
			var off := await until(func(): return c._city_riding() < 0, CityMap.FERRIS["period"] + 10.0)
			check(off, "off at the bottom")
			check(c.pos.distance_to(CityMap.FERRIS["board_at"]) < 1.6 and c.level == "", "back on the platform (%s)" % c.pos)
	# ---- the bus home
	if await go("", CityMap.BUS_STOP, "the bus stop"):
		if c.space == "city" and c.journey_to == "":
			await use_here("tram_home", "Ride home")   # unless the tap on the stop already set off
		check(await until(func(): return c.space == "town" and c.journey_to == "", 12.0), "the bus brings the child home to town")
		check(not main.rig.on_city, "the town's camera comes back")
		# dest-fix r1: decorating is back at home
		check(main.hud._decorate_btn.is_visible_in_tree(), "Decorate is back in the town")
		c.set_mode("decorate")
		check(c.mode == "decorate", "and decorate mode opens again")
		c.set_mode("play")
	_finish()


func _mouse_button(p: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	return e


func _finish() -> void:
	print("CITY TOUR %s %s: %d checks, %d failures, %d frames" % [tag, "PASS" if failures == 0 else "FAIL", _checks, failures, _frames])
	Music.quit_game(1 if failures else 0)
