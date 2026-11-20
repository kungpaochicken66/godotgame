## Mac GPU capture for zoo r2 (the six imported animals in the actual zoo). It walks the child, as the
## zoo tour does, to four viewing places and saves JPG frames of each imported species: idle, a walk
## sequence (which shows turning too), the answer to a wave and to a cheer, and a wide frame where the
## habitat's animals share the ground (avoidance). A JSON log names every frame with the animals'
## states at that moment, so a reviewer can tell what each picture should show.
##   GPU (Mac): scripts/godot.sh --path game --resolution 1280x720 -- --driver=res://tests/zoo_capture.gd \
##       --shots=/abs/dir --tag=ipad
##   Logic only (no frames): add --headless before --path and --no-shots after --.
## At most 48 frames (JPEG, quality 0.85, about 100-200 KB each).
extends "res://tests/zoo_tour.gd"

const MAX_FRAMES := 48
const WALKS := ["walk", "waddle", "trot", "canter", "gallop", "prowl", "patrol", "show_walk", "step_back", "swim"]
## Viewing places, the way there from the zoo plaza, and the imported species seen from each.
const STOPS := [
	{"name": "savanna", "path": [Vector2(0.0, 13.0), Vector2(0.0, 11.0)], "species": ["elephant", "giraffe", "zebra"]},
	{"name": "grove", "path": [Vector2(0.0, 13.5), Vector2(15.0, 13.5), Vector2(27.0, 9.4)], "species": ["panda"]},
	{"name": "splash", "path": [Vector2(0.0, 13.5), Vector2(-18.0, 13.5), Vector2(-29.5, 7.6)], "species": ["penguin"]},
	{"name": "lion", "path": [Vector2(0.0, 11.0), Vector2(0.0, -7.0), Vector2(1.8, -10.4)], "species": ["lion"]},
]

var _frames := 0
var _log: Array = []


func frame(name: String) -> void:
	var states: Array = zoo_node().states.get("animals", [])
	var row := {"frame": name, "child": [snappedf(main.controller.pos.x, 0.01), snappedf(main.controller.pos.y, 0.01)],
		"animals": states.filter(func(st): return main.world.zoo_world.animal_node(st["id"]) != null and main.world.zoo_world.animal_node(st["id"]).visible) \
			.map(func(st): return {"id": st["id"], "action": st["action"]})}
	_log.append(row)
	if main.args.has("no-shots") or _frames >= MAX_FRAMES:
		print("FRAME %s (not saved)" % name)
		return
	await RenderingServer.frame_post_draw
	_frames += 1
	var path := "%s/zoo_r2_%s_%02d_%s.jpg" % [shots, tag, _frames, name]
	var err := get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	check(err == OK, "frame %s saved (%d)" % [name, err])


func _resident_of(sp: String) -> String:
	for id in ZooMap.ORDER:
		if ZooMap.RESIDENTS[id]["species"] == sp:
			return id
	return ""


func _action_of(id: String) -> String:
	for st in zoo_node().states.get("animals", []):
		if st["id"] == id:
			return st["action"]
	return ""


func _run() -> void:
	var c: Node = main.controller
	tv = false
	get_tree().create_timer(float(main.args.get("timeout", "600"))).timeout.connect(func():
		check(false, "the capture finished within %s s" % main.args.get("timeout", "600"))
		_write_log()
		Music.quit_game(1))
	var save := "user://zoo_capture_town.json"
	for f in [save, save + ".bak", save + ".maps", save + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	c.ride(Places.ZOO)
	check(await until(func(): return c.space == Places.ZOO and c.journey_to == "", 12.0), "the child rides to the zoo")
	check(await until(func(): return zoo_node().states.get("animals", []).size() == ZooMap.ORDER.size(), 6.0), "all residents arrive")
	await wait(2.0)
	for stop in STOPS:
		main.rig.yaw_step = 0
		await walk_far(stop["path"])
		main.rig.yaw_step = 0
		await settle_camera()
		for sp in stop["species"]:
			var id := _resident_of(sp)
			var node: Node3D = main.world.zoo_world.animal_node(id)
			check(node != null and node.visible, "%s (%s) is drawn at %s" % [id, sp, stop["name"]])
			# Walking: up to 25 s for a walk to start, then three frames 0.3 s apart.
			if await until(func(): return _action_of(id) in WALKS, 25.0):
				for i in 3:
					await frame("%s_%s_walk%d_%s" % [stop["name"], sp, i, _action_of(id)])
					await wait(0.3)
			else:
				print("NOTE %s did not walk within 25 s at %s" % [id, stop["name"]])
			# Idle (any action that is not a walk), then the answers to a wave and a cheer.
			await until(func(): return not _action_of(id) in WALKS, 15.0)
			await frame("%s_%s_idle_%s" % [stop["name"], sp, _action_of(id)])
			for emote in ["wave", "cheer"]:
				Session.send_emote(emote)
				await wait(1.4)
				await frame("%s_%s_%s_%s" % [stop["name"], sp, emote, _action_of(id)])
				await wait(2.0)
		# The habitat wide: the residents sharing the ground (avoidance and floor contact).
		while not is_equal_approx(main.rig.distance(), 15.0):
			await press(main.hud._cam_tools.get_child(2))
		await settle_camera()
		await frame("%s_wide" % stop["name"])
		while not is_equal_approx(main.rig.distance(), 9.5):
			await press(main.hud._cam_tools.get_child(2))
	_write_log()
	print("ZOO CAPTURE %s %s: %d checks, %d failures, %d frames" % [tag, "PASS" if failures == 0 else "FAIL", _checks, failures, _frames])
	Music.quit_game(1 if failures else 0)


func _write_log() -> void:
	var f := FileAccess.open("%s/zoo_r2_%s_frames.json" % [shots, tag], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_log, " ") + "\n")
