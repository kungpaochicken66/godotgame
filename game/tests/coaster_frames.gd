## Matching before/after frames of the Roller Coaster Workshop clearance conflicts (unified r6).
## Builds the park through the real game (main.tscn, a solo session, the Hud's Workshop path), boards each ride
## with the park's own _board(), holds the train still (moving = false) and puts it at chosen frame indices with
## CoasterLine.place(); the park's own _ride_camera() then sets view 0 (rider eye; the child hidden) or view 1
## (chase; the child seated). All on-screen UI layers are hidden, so only the 3D scene is compared.
## Shots: for every interval of a clearance JSON (tests/coaster_clearance.gd) its first, worst and last sample,
## plus explicit arclengths (lead car, metres from frame 0; frame = round(s / ds)). Names depend only on ride,
## frame and view: <ride>_f<frame:04d>_v<view>.png, so an r5 and an r6 run write the same set of names.
## Uses only APIs that exist unchanged in unified r5 (coaster_park.gd setup/_board/_ride_camera/interact/view,
## coaster_line.gd place/ds/frames/moving/design), so the file can be copied into an extracted r5 tree.
##   Rendered (Mac):  scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/coaster_frames.gd \
##                        --plan=/abs/coaster-clearance-r5.json --frames-out=/abs/frames-r5 \
##                        [--at="comet-run:344,520;neon-wings:14"] [--views=0,1] [--parts=car,rider,track]
##   Logic only:      add --headless before --path and --dry after --: no pictures; prints every camera transform.
## Writes <frames-out>/manifest.json (+ .txt); prints "COASTER FRAMES n shots" and exits 0 (1 on a failure).
extends Node

var main: Node
var park: Node
var out := ""
var dry := false
var failures := 0


func _ready() -> void:
	dry = main.args.has("dry")
	out = main.args.get("frames-out", ProjectSettings.globalize_path("user://coaster-frames"))
	DirAccess.make_dir_recursive_absolute(out)
	if not dry and DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1920, 1080)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## {ride: {frame: [reasons]}} from --plan intervals and --at arclengths.
func _plan() -> Dictionary:
	var shots := {}
	var parts: PackedStringArray = str(main.args.get("parts", "car,rider,track")).split(",", false)
	if main.args.has("plan"):
		var data = JSON.parse_string(FileAccess.get_file_as_string(main.args["plan"]))
		if data is Dictionary:
			for it in data.get("intervals", []):
				if not parts.has(str(it.part)):
					continue
				var why := "%s %s %s..%s" % [it.part, it.object.name, it.first, it.last]
				for f in [int(it.first), int(it.worst_frame), int(it.last)]:
					_want(shots, str(it.ride), f, why)
		else:
			print("FRAMES plan not readable: ", main.args["plan"])
			failures += 1
	for group in str(main.args.get("at", "")).split(";", false):
		var kv := group.split(":", true, 1)
		if kv.size() != 2:
			continue
		for value in kv[1].split(",", false):
			_want(shots, kv[0].strip_edges(), -1, "at %s m" % value.strip_edges(), float(value))
	return shots


func _want(shots: Dictionary, ride: String, frame: int, why: String, s := -1.0) -> void:
	if not shots.has(ride):
		shots[ride] = {}
	var key: Variant = frame if s < 0.0 else "s%s" % s
	if not shots[ride].has(key):
		shots[ride][key] = []
	shots[ride][key].append(why)


func _run() -> void:
	var save := "user://coaster-frames-town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await get_tree().create_timer(1.0).timeout
	main.controller.stop_for_workshop()   # the Hud's Workshop button path (hud.gd)
	park = load("res://scripts/world/coaster_park.gd").new()
	park.setup(main)
	var t := 0.0
	while park.journey > 0.0 and t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_hide_ui(get_tree().root)
	var views: PackedStringArray = str(main.args.get("views", "0,1")).split(",", false)
	var shots := _plan()
	var manifest := []
	for line in park.lines:
		if not shots.has(line.design):
			continue
		var n: int = line.frames.size()
		var frames := {}
		for key in shots[line.design]:
			var f: int = posmod(roundi(float(str(key).trim_prefix("s")) / line.ds), n) if key is String else posmod(int(key), n)
			if not frames.has(f):
				frames[f] = []
			frames[f].append_array(shots[line.design][key])
		var order: Array = frames.keys()
		order.sort()
		park._board(line)
		line.moving = false   # held still: the park's _process no longer advances it
		if park.active != line:
			print("FRAMES could not board ", line.design)
			failures += 1
			continue
		for f in order:
			line.place(f * line.ds)
			for v in views:
				park.view = int(v)
				park._ride_camera()
				await _frames(2)
				park._ride_camera()
				var name := "%s_f%04d_v%s.png" % [line.design, f, v]
				var cam: Camera3D = park.cam
				var car: Transform3D = line.cars[0].global_transform
				var expect: Vector3 = car * line.eye
				var entry := {"name": name, "ride": line.design, "frame": f, "s": snappedf(f * line.ds, 0.01), "view": int(v),
					"camera": _xf(cam.global_transform), "lead_car": _xf(car), "kid_visible": park.kid.visible, "why": frames[f]}
				if int(v) == 0 and cam.global_position.distance_to(expect) > 0.01:
					print("FRAMES rider eye off at ", name)
					failures += 1
				if not dry:
					await RenderingServer.frame_post_draw
					var img := get_viewport().get_texture().get_image()
					entry["size"] = [img.get_width(), img.get_height()]
					if img.save_png(out.path_join(name)) != OK:
						failures += 1
				manifest.append(entry)
				print("FRAMES %s cam=%s kid=%s %s" % [name, entry.camera, park.kid.visible, "; ".join(PackedStringArray(frames[f]))])
		line.place(line.stop)
		park.interact()   # stopped at the platform: Get off
		await _frames(2)
	var f := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"dry": dry, "engine": Engine.get_version_info().string, "shots": manifest}, "  "))
	f.close()
	var names := PackedStringArray()
	for e in manifest:
		names.append(e.name)
	var tf := FileAccess.open(out.path_join("manifest.txt"), FileAccess.WRITE)
	tf.store_string("\n".join(names) + "\n")
	tf.close()
	print("COASTER FRAMES %d shots, %d failures -> %s" % [manifest.size(), failures, out])
	get_tree().quit(1 if failures else 0)


func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			c.visible = false
		_hide_ui(c)


func _xf(t: Transform3D) -> Array:
	var e := t.basis.get_euler()
	return [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001),
		snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)]
