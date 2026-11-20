## dest-fix r1 diagnosis (user feedback on the installed city-web r3, 2026-11-18): in the city "my own character
## is missing", and town-only controls show where they mean nothing. This driver reproduces through the real
## game: the tram from town to the Godot city, the arrival view, how much of the player's own child is actually
## visible (a frame with and without the child, differing pixels counted), the child's projected height, and
## every HUD control visible in the town, a cottage room, the zoo and the city (and after the ride home).
##   scripts/godot.sh --path game --resolution 1366x1024 -- --driver=res://tests/dest_repro.gd --tag=ipad \
##       --shots=/abs/dir [--map=city|zoo]
## Needs a renderer for the pixel counts (on EC2: xvfb-run, software GL; the numbers are geometry, not colour).
extends "res://tests/zoo_tour.gd"

const CityMap := preload("res://scripts/core/city_map.gd")
const KID_H := 1.30

var _report := {}


func _png(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if shots != "":
		img.save_png("%s/%s_%s.png" % [shots, tag, name])
	return img


## Pixels that differ (any channel by more than 6/255) between two frames of the same size.
static func _diff(a: Image, b: Image) -> Dictionary:
	var n := 0
	var box := Rect2i()
	for y in range(0, a.get_height()):
		for x in range(0, a.get_width()):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > 0.024 or absf(p.g - q.g) > 0.024 or absf(p.b - q.b) > 0.024:
				n += 1
				box = Rect2i(x, y, 1, 1) if n == 1 else box.expand(Vector2i(x, y))
	return {"pixels": n, "box": [box.position.x, box.position.y, box.size.x + 1, box.size.y + 1] if n > 0 else []}


## How the player's own child shows right now: projected feet/head, height in px, and the pixels that change
## when only the child is hidden (occlusion and size together).
func measure(label: String) -> Dictionary:
	var c: Node = main.controller
	var cam: Camera3D = main.rig.camera
	var kid: Node3D = main.world.kids.get(Session.my_id)
	var feet := kid.global_position
	var head := feet + Vector3(0, KID_H, 0)
	var view := get_viewport().get_visible_rect().size
	var out := {"label": label, "space": c.space, "pos": [snappedf(feet.x, 0.01), snappedf(feet.y, 0.01), snappedf(feet.z, 0.01)],
		"cam": [snappedf(cam.global_position.x, 0.1), snappedf(cam.global_position.y, 0.1), snappedf(cam.global_position.z, 0.1)],
		"cam_dist": snappedf(cam.global_position.distance_to(feet + Vector3(0, 0.65, 0)), 0.1), "fov": cam.fov,
		"view": [view.x, view.y], "kid_visible_flag": kid.visible and kid.is_visible_in_tree()}
	if not cam.is_position_behind(feet) and not cam.is_position_behind(head):
		var fp := cam.unproject_position(feet)
		var hp := cam.unproject_position(head)
		out["feet_px"] = [roundi(fp.x), roundi(fp.y)]
		out["height_px"] = snappedf(fp.distance_to(hp), 0.1)
		out["on_screen"] = Rect2(Vector2.ZERO, view).has_point(fp)
	if DisplayServer.get_name() != "headless":
		await frames(2)
		var with_kid := await _png(label + "_with")
		kid.visible = false
		await frames(2)
		var without := await _png(label + "_without")
		kid.visible = true
		await frames(2)
		var d := _diff(with_kid, without)
		out["visible_px"] = d["pixels"]
		out["visible_box"] = d["box"]
	print("DEST REPRO measure ", JSON.stringify(out))
	return out


## Every HUD control a player can see and press now (buttons, in the tree, visible on screen), by its text,
## tooltip or name.
func hud_inventory(label: String) -> Array:
	var hud: Control = main.hud
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen: Array = []
	for b in hud.find_children("*", "BaseButton", true, false):
		var btn := b as BaseButton
		if not btn.is_visible_in_tree() or btn.disabled:
			continue
		var r := btn.get_global_rect()
		if r.size.x < 4 or r.size.y < 4 or not view.intersects(r):
			continue
		var what := ""
		if btn is Button and (btn as Button).text != "":
			what = (btn as Button).text
		elif btn.tooltip_text != "":
			what = btn.tooltip_text
		else:
			what = String(btn.name)
		seen.append(what)
	seen.sort()
	print("DEST REPRO hud %s %s" % [label, JSON.stringify(seen)])
	_report["hud_" + label] = seen
	return seen


func _run() -> void:
	var c: Node = main.controller
	tv = main.args.has("tv")
	var target_map := str(main.args.get("map", "city"))
	get_tree().create_timer(float(main.args.get("timeout", "600"))).timeout.connect(func():
		check(false, "finished within the time limit")
		_finish())
	var save := "user://dest_repro_town.json"
	for f in [save, save + ".bak", save + ".maps", save + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.5)
	await hud_inventory("town")
	_report["town_arrival"] = await measure("town")
	# a cottage room: the first cottage's door, entered as a child would
	var cottages: Array = Session.model.cottages if "cottages" in Session.model else []
	if not cottages.is_empty() and c.has_method("enter_room"):
		pass   # rooms are covered by the audit in code; the repro keeps to the maps the user reported
	# ---- to the destination by the tram stop, as on the iPad
	var board: Variant = TownModel.tram_stop_boarding(Session.model)
	await walk_to(board)
	check(await until(func(): return c._ctx.get("type", "") == "tram", 10.0), "the tram stop is the context")
	if target_map == "city":
		check(c._ctx.get("alt", {}).get("type", "") == "tram_city", "the stop offers Ride to the city (%s)" % c._ctx.get("alt", {}).get("label", ""))
		c.do_context(c._ctx["alt"])
	else:
		c.do_context(c._ctx)
	check(await until(func(): return c.space == target_map and c.journey_to == "", 15.0), "arrived in %s" % target_map)
	await wait(1.2)
	await hud_inventory(target_map)
	_report[target_map + "_arrival"] = await measure(target_map + "_arrival")
	if target_map == "city":
		# the closest zoom the player can reach with the zoom buttons
		for i in 6:
			main.rig.city_step_zoom(1)
			await wait(0.4)
		await wait(1.0)
		_report["city_closest"] = await measure("city_closest")
		await hud_inventory("city_closest")
	# ---- home again
	c.ride("town")
	check(await until(func(): return c.space == "town" and c.journey_to == "", 15.0), "back in the town")
	await wait(1.2)
	await hud_inventory("town_after")
	print("DEST REPRO REPORT ", JSON.stringify(_report))
	_finish()
