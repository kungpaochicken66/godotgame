## r20 decorative motion through the real game (design/decorative-motion.md): a ceiling fan's blades turn,
## a bird mobile and a red paper lantern sway, a candle chandelier and a bamboo floor lantern glow gently
## in the evening. Time-separated originals show the movement. Then Reduce motion (Sound and music, real
## taps) stops it at once, frozen-after-toggle originals and pixel checks prove it, and the room change,
## removal, re-placing, a reload and turning it back on are checked. A timed workload measures the cost.
## At most 8 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/motion_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja --timeout=400
## Logic only, no renderer (EC2 smoke): add --headless before --path, --no-shots and --window=2208x1024
## after --. Pixel checks need the renderer; desktop frame times are not iPhone or iPad measurements.
extends "res://tests/play_tour.gd"

const DecoMotion := preload("res://scripts/world/deco_motion.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const SPOTS := {
	"ceiling_fan_light": Vector2(-1.6, -0.6),
	"bird_mobile": Vector2(1.8, -1.4),
	"red_paper_lantern": Vector2(2.8, 0.4),
	"candle_ring_chandelier": Vector2(0.6, 1.2),
	"bamboo_floor_lantern": Vector2(-3.3, 2.2),
}

var _case_done := false
var _ids := {}
var _room := ""


func shot(name: String) -> void:
	if _n >= 8 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/motion_%s_%02d_%s.png" % [shots, tag, _n, name])


func rendered() -> bool:
	return not main.args.has("no-shots") and DisplayServer.get_name() != "headless"


func case_ended(what: String) -> void:
	check(_case_done, "the %s case ran to its end" % what)
	_case_done = false


## Finger-like taps (as in visit_tour, r18b): the pointer moves to the point before press and lift.
func tap(canvas_pos: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_final_transform() * canvas_pos
	for pressed in [true, false]:
		var m := InputEventMouseMotion.new()
		m.position = screen
		m.global_position = screen
		m.button_mask = 0 if pressed else MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		await get_tree().process_frame


func world() -> Node3D:
	return main.world


## Every animated part's pose and every glowing lamp's brightness, keyed by item.
func poses() -> Dictionary:
	var out := {}
	for id in world().deco:
		var st: Dictionary = world().deco[id]
		if st.has("part") and is_instance_valid(st["part"]):
			out[id] = st["part"].transform
		elif st.has("light") and is_instance_valid(st["light"]):
			out[id] = st["light"].light_energy
	return out


func same_pose(a, b) -> bool:
	return a.is_equal_approx(b) if a is Transform3D else is_equal_approx(a, b)


## Screen region of an item (its model's box), for pixel comparisons.
func screen_rect(id: String) -> Rect2:
	var node: Node3D = world().item_nodes.get(id)
	var cam: Camera3D = main.rig.camera
	var r := Rect2()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Shadow":
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		for i in 8:
			var p := cam.unproject_position(a.get_endpoint(i))
			r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
			first = false
	return r.grow(6.0).intersection(get_viewport().get_visible_rect())


func frame_image() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Mean absolute pixel difference (0..255) inside a rect.
func pixel_change(a: Image, b: Image, r: Rect2) -> float:
	var sum := 0.0
	var n := 0
	var step := 2
	for y in range(int(r.position.y), int(r.end.y), step):
		for x in range(int(r.position.x), int(r.end.x), step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			n += 1
	return sum / maxf(1.0, n)


func set_reduce_by_tap(hud: Control, on: bool, shot_name := "") -> void:
	hud.open_sound()
	await frames(4)
	var b := hud._overlay.find_child("ReduceMotion", true, false) as Button
	check(b != null and b.is_visible_in_tree() and playable_rect().encloses(b.get_global_rect()), "the settings show %s with its switch, on screen" % tr("Reduce motion"))
	if b == null:
		return
	if shot_name != "":
		await shot(shot_name)
	if world().reduce_motion != on:
		await press(b)
		await frames(3)
	check(world().reduce_motion == on, "%s is now %s" % [tr("Reduce motion"), "on" if on else "off"])
	await close_dialogs()


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("MOTION %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	if world().reduce_motion:
		world().set_reduce_motion(false)   # a clean start for this test profile
	var save := "user://motion_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	_case_done = false
	await _moving(hud, c)
	case_ended("moving")
	await _reduced(hud, c)
	case_ended("reduce motion")
	await _lifecycle(hud, c)
	case_ended("lifecycle")
	await _workload(c)
	case_ended("workload")
	for loc in locales.slice(1):
		I18n.set_locale(loc)
		await frames(3)
		hud.open_sound()
		await frames(4)
		var b := hud._overlay.find_child("ReduceMotion", true, false) as Button
		check(b != null and tr("Reduce motion") != "Reduce motion", "[%s] the setting is translated (%s)" % [loc, tr("Reduce motion")])
		await shot("%s_settings" % loc)
		await close_dialogs()
	if world().reduce_motion:
		world().set_reduce_motion(false)
	print("MOTION %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## The five decorations in the living room at evening: everything moves, and differently over time.
func _moving(hud: Control, c: Node) -> void:
	var houses: Array = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return a["id"] < b["id"])
	_room = TownModel.room_space(houses[0]["id"], 0, 0)
	if not Session.model.evening:
		Session.ring_bell()
	for k in SPOTS:
		var at: Vector2 = SPOTS[k]
		if Catalog.anchor(k) == "ground":
			var free = Session.model.find_free_spot(k, _room, at)
			at = free if free != null else at
		var r: Dictionary = await ask_result(Session.place(k, _room, at, 0, -1))
		check(r.get("ok", false), "set up: %s (%s)" % [k, r.get("error", "ok")])
		_ids[k] = r.get("item", {}).get("id", "")
	c.go_to_room(_room)
	await wait(1.0)
	c.pos = Vector2(0.6, 2.4)
	c._place_kid()
	main.rig.snap()
	check(await until(func(): return world().evening > 0.99, 6.0), "it is evening (the lamps are on)")
	await settle_camera()
	check(world().deco.size() == 5, "all five decorations have motion here (%d)" % world().deco.size())
	var p0 := poses()
	var img0: Image = await frame_image() if rendered() else null
	await shot("moving_a")
	await wait(0.6)
	var p1 := poses()
	var img1: Image = await frame_image() if rendered() else null
	await shot("moving_b")
	for k in _ids:
		var id: String = _ids[k]
		check(p0.has(id) and p1.has(id) and not same_pose(p0[id], p1[id]), "%s (%s) changed between frames 0.6 s apart" % [k, DecoMotion.MOTION[k]])
	if img0 and img1:
		for k in ["ceiling_fan_light", "bird_mobile", "red_paper_lantern"]:
			var d := pixel_change(img0, img1, screen_rect(_ids[k]))
			print("PIXELS moving %s: %.2f" % [k, d])
			check(d > 0.5, "%s visibly moves on screen (mean change %.2f)" % [k, d])
	_case_done = true


## Reduce motion through the real settings: still at once, still 0.6 s later, remembered.
func _reduced(hud: Control, c: Node) -> void:
	await set_reduce_by_tap(hud, true, "settings_reduce_motion")
	check(DecoMotion.load_reduce(), "the setting is saved on this device")
	for id in world().deco:
		var st: Dictionary = world().deco[id]
		if st.has("part"):
			check(st["part"].transform.is_equal_approx(st["base"]), "%s is back in its still pose at once" % st["kind"])
		else:
			check(is_equal_approx(st["light"].light_energy, DecoMotion.LAMP_ENERGY * world().evening), "%s glows steadily at once" % st["kind"])
	await settle_camera()
	var p0 := poses()
	var img0: Image = await frame_image() if rendered() else null
	await shot("reduced_a")
	await wait(0.6)
	var p1 := poses()
	var img1: Image = await frame_image() if rendered() else null
	await shot("reduced_b")
	for id in p0:
		check(p1.has(id) and same_pose(p0[id], p1[id]), "%s stays frozen after the toggle" % world().deco[id]["kind"])
	if img0 and img1:
		for k in _ids:
			var d := pixel_change(img0, img1, screen_rect(_ids[k]))
			print("PIXELS reduced %s: %.2f" % [k, d])
			check(d < 0.3, "%s does not change on screen (mean change %.2f)" % [k, d])
	_case_done = true


## Room changes, removal, re-placing and a reload keep everything consistent with the setting.
func _lifecycle(hud: Control, c: Node) -> void:
	# Upstairs and back: the rebuilt decorations stay still while Reduce motion is on.
	c.go_to_room(TownModel.room_space(TownModel.house_of(_room), 1, 0))
	await wait(0.6)
	check(world().deco.is_empty(), "upstairs nothing of the living room moves (no hidden work)")
	c.go_to_room(_room)
	await wait(0.6)
	check(world().deco.size() == 5, "back in the living room the decorations are rebuilt with motion")
	var p0 := poses()
	await wait(0.4)
	check(poses().keys().all(func(id): return same_pose(p0[id], poses()[id])), "and stay still while Reduce motion is on")
	# Turned off again: they move again.
	await set_reduce_by_tap(hud, false)
	var q0 := poses()
	await wait(0.5)
	var q1 := poses()
	check(q0.keys().all(func(id): return not same_pose(q0[id], q1[id])), "with Reduce motion off they move again")
	# Remove the fan: its motion goes with it. Put it back: a fresh fan turns.
	var fan: String = _ids["ceiling_fan_light"]
	var r: Dictionary = await ask_result(Session.remove(fan))
	check(r.get("ok", false), "the fan is put away")
	await wait(0.5)
	check(not world().deco.has(fan), "the removed fan's motion is gone")
	r = await ask_result(Session.place("ceiling_fan_light", _room, SPOTS["ceiling_fan_light"], 0, -1))
	_ids["ceiling_fan_light"] = r.get("item", {}).get("id", "")
	await wait(0.3)
	var nf: String = _ids["ceiling_fan_light"]
	check(world().deco.has(nf), "a new fan gets motion")
	var a0 = poses().get(nf)
	await wait(0.3)
	check(a0 != null and not same_pose(a0, poses().get(nf)), "and its blades turn")
	# Save, leave and load the town again: decorations come back moving, nothing about motion is saved.
	Session.save_now()
	var saved := FileAccess.get_file_as_string("user://motion_tour_town.json")
	check(not saved.contains("reduce") and not saved.contains("Blade"), "the town save holds no motion state")
	Session.leave()
	Session.start_solo("user://motion_tour_town.json", main.menus.avatar)
	await wait(1.0)
	c.go_to_room(_room)
	await wait(0.8)
	check(world().deco.size() == 5, "after the reload the five decorations have motion again")
	var s0 := poses()
	await wait(0.4)
	check(s0.keys().all(func(id): return not same_pose(s0[id], poses()[id])), "and move")
	await settle_camera()
	await shot("moving_after_reload")
	_case_done = true


## A busy room: 12 more fans and lanterns (17 moving things). The cost of the motion pass itself is timed,
## and frame times with motion on and off are printed. Desktop numbers, not iPhone or iPad ones.
func _workload(c: Node) -> void:
	var extra := 0
	for i in 30:
		var k: String = ["ceiling_fan_light", "red_paper_lantern", "bird_mobile"][i % 3]
		var p := Vector2(-3.4 + (i % 6) * 1.35, -2.2 + (i / 6) * 1.1)
		var r: Dictionary = await ask_result(Session.place(k, _room, p, 0, -1))
		if r.get("ok", false):
			extra += 1
		if extra >= 12:
			break
	await wait(0.5)
	var n: int = world().deco.size()
	check(n >= 15, "a busy room: %d moving decorations" % n)
	var cost := 0
	var frames_n := 120
	for i in frames_n:
		var t0 := Time.get_ticks_usec()
		world()._animate_deco()
		cost += Time.get_ticks_usec() - t0
		await get_tree().process_frame
	var per_frame := float(cost) / frames_n
	print("PERF motion pass: %d decorations, %.1f us per frame (avg of %d)" % [n, per_frame, frames_n])
	check(per_frame < 500.0, "the motion pass costs under 0.5 ms per frame for %d decorations (%.1f us)" % [n, per_frame])
	var times := {}
	for on in [false, true]:
		world().set_reduce_motion(on)
		await wait(0.3)
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_process_frames()
		await wait(2.0)
		times[on] = float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1, Engine.get_process_frames() - f0)
	world().set_reduce_motion(false)
	print("PERF frame time (desktop, this machine): motion %.2f ms, reduced %.2f ms" % [times[false], times[true]])
	_case_done = true


func ask_result(req: int) -> Dictionary:
	var out := [{}]
	main.controller._ask(req, func(r): out[0] = r)
	await until(func(): return not out[0].is_empty(), 5.0)
	return out[0]
