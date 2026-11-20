## Renders the six imported animals in a row, with a 1.30 m box for the child, under the game's town
## daylight (TownWorld: sky #cfe9ef, ambient #eef3ef at 0.5, sun #fff4e0 at 0.8, -52/-38 degrees).
## Two 1280 x 720 PNGs: the front (faces, colours) and the zoo's own camera angle (40 degrees down,
## 42 degree field, 15 m away). The Blender previews already show each animal's side.
## Needs a GPU window (not --headless):
##   godot --path <pack> --resolution 1280x720 -s res://render_lineup.gd -- --out=<absolute folder>
extends SceneTree

const ORDER := ["everything_panda", "everything_lion", "everything_elephant", "everything_giraffe", "everything_zebra", "everything_penguin"]


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return fallback


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := _arg("out", ProjectSettings.globalize_path("res://renders"))
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfe9ef")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#eef3ef")
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.8
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#a8d18d")
	ground.material_override = gm
	world.add_child(ground)
	var x := 0.0
	var placed := 0
	for aid in ORDER:
		var scene := load("res://models/%s.glb" % aid) as PackedScene
		if scene == null:
			push_error("missing %s" % aid)
			continue
		var n := scene.instantiate() as Node3D
		var box := _bounds(n)
		n.position.x = x - box.position.x
		world.add_child(n)
		x += box.size.x + 0.8
		placed += 1
	var kid := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 1.30, 0.3)
	kid.mesh = bm
	var km := StandardMaterial3D.new()
	km.albedo_color = Color("#e9806e")
	kid.material_override = km
	kid.position = Vector3(x + 0.2, 0.65, 0)
	world.add_child(kid)
	var mid := Vector3((x + 0.4) * 0.5, 1.2, 0)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var views := {
		"lineup_front": [mid + Vector3(0, 0.6, 22), 30.0],
		"lineup_zoo_camera": [mid + Vector3(0, sin(deg_to_rad(40.0)) * 15.0, cos(deg_to_rad(40.0)) * 15.0), 42.0],
	}
	for name in views:
		var v: Array = views[name]
		cam.fov = v[1]
		cam.position = v[0]
		cam.look_at(mid, Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := out.path_join(name + ".png")
		var err := img.save_png(path)
		print("RENDER %s %s (%d animals, %dx%d, error %d)" % [name, path, placed, img.get_width(), img.get_height(), err])
	quit(0 if placed == ORDER.size() else 1)


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
