## Renders every catalog item (and the four preset children) into one image for visual review.
##   xvfb-run scripts/godot.sh --path game res://tests/prop_gallery.tscn -- out=/abs/path.png
extends Node3D

const Props := preload("res://scripts/art/props.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Palette := preload("res://scripts/core/palette.gd")


func _ready() -> void:
	var root := get_viewport()
	var out := "user://prop_gallery.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#f5f1e7")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#e8eef0")
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.8
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Palette.GRASS
	ground.material_override = gm
	world.add_child(ground)
	var kinds := Catalog.ITEMS.keys()
	var cols := 6
	for i in kinds.size():
		var kind: String = kinds[i]
		var node := Props.build(kind, Catalog.ITEMS[kind]["color"], i)
		var spacing := 4.4
		node.position = Vector3((i % cols - (cols - 1) * 0.5) * spacing, 0, (i / cols) * 4.6 - 7)
		if kind == "cottage":
			node.scale = Vector3.ONE * 0.6
		world.add_child(node)
	var kid_script = load("res://scripts/art/kid.gd")
	if kid_script:
		var presets = load("res://scripts/core/avatar.gd").PRESETS
		for j in presets.size():
			var kid = kid_script.new()
			world.add_child(kid)
			kid.setup(presets[j], false)
			kid.position = Vector3(-4 + j * 1.6, 0, 11.5)
			kid.rotation.y = 0.3
			kid.anim = ["idle", "walk", "idle", "idle"][j]
			if j >= 2:
				kid.play_emote(["", "", "wave", "cheer"][j])
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.position = Vector3(0, 15, 21)
	cam.basis = Basis.looking_at(Vector3(0, 0, 2.5) - cam.position)
	if "focus=kids" in OS.get_cmdline_user_args():
		cam.position = Vector3(-1.6, 2.6, 15.6)
		cam.basis = Basis.looking_at(Vector3(-1.6, 0.7, 11.5) - cam.position)
	for f in 8:
		await get_tree().process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	Music.quit_game()
