## Scale lineup from the game camera: child, trees, large furniture, a chair and
## small decorations (one on a table when tabletop support exists).
##   xvfb-run -a scripts/godot.sh --path game res://tests/scale_lineup.tscn -- out=/abs/file.png
extends Node3D

const Props := preload("res://scripts/art/props.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Kit := preload("res://scripts/art/mesh_kit.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")


func _ready() -> void:
	var out := "user://scale_lineup.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#cfe9ef")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#eef3ef")
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.8
	add_child(sun)
	Kit.part(self, Kit.rounded_box(Vector3(30, 1.0, 14), 0.4), Palette.GRASS, Vector3(0, -0.5, 0))
	var row := [["kid", -6.6], ["tree", -4.6], ["pine", -2.3], ["bed", -0.2], ["sofa", 1.9], ["table", 4.0], ["chair", 5.6], ["teddy", 6.6], ["lamp_post", 7.6]]
	var host := "table"
	var decoration := "plant"
	if "set=modeled" in OS.get_cmdline_user_args():
		# The reviewed pilot-10 models with the same child and an ordinary tree.
		row = [["kid", -6.6], ["tree", -4.8], ["scallop_bed", -2.6], ["open_shelf", -0.7], ["curved_counter", 1.2], ["cozy_round_table", 3.3],
			["scallop_chair", 4.9], ["writing_bureau", 6.1], ["desk_lamp", 7.3]]
		host = "cozy_round_table"
		decoration = "flower_pot_bloom"
	for spec in row:
		var x: float = spec[1]
		var n: Node3D
		if spec[0] == "kid":
			n = load("res://scripts/art/kid.gd").new()
			add_child(n)
			n.setup(load("res://scripts/core/avatar.gd").PRESETS[0], false)
		else:
			n = Props.build(spec[0], Catalog.ITEMS[spec[0]]["color"], 3)
			add_child(n)
		n.position = Vector3(x, 0, 0)
	# A flower pot on the table if tables are support hosts, otherwise beside it.
	var pot := Props.build(decoration, Catalog.ITEMS[decoration]["color"], 1)
	add_child(pot)
	var host_x: float = row.filter(func(r): return r[0] == host)[0][1]
	var surface: Dictionary = Catalog.ITEMS[host].get("support_surface", {})
	pot.position = Vector3(host_x, 0, 0) + (surface["local_position"] if not surface.is_empty() else Vector3(0, 0, 1.0))
	var cam := Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	var pitch := CameraRig.PITCH
	var dist: float = 16.5
	var focus := Vector3(0.5, 0.8, 0)
	var offset := Vector3(0, sin(pitch), cos(pitch)) * dist
	cam.position = focus + offset
	cam.basis = Basis.looking_at(-offset.normalized(), Vector3.UP)
	for f in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
