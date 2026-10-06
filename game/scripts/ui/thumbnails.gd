## Renders catalog thumbnails from the real 3D models, once, at startup.
extends Node

const Props := preload("res://scripts/art/props.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

signal finished()

const SIZE := 144

var textures := {}            # kind -> Texture2D
var is_done := false

var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#eef3ef")
	env.environment.ambient_light_energy = 0.55
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 0.8
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_generate.call_deferred()


func _generate() -> void:
	for kind in Catalog.ITEMS:
		var def: Dictionary = Catalog.ITEMS[kind]
		var model := Props.build(kind, def["color"], 1)
		_stage.add_child(model)
		var r: float = def["radius"]
		var h: float = {"cottage": 3.8, "tree": 3.6, "pine": 3.2, "lamp_post": 3.0, "swing": 2.4, "floor_lamp": 1.7, "bookshelf": 1.6}.get(kind, maxf(r * 1.2, 0.9))
		var size := maxf(r * 2.3, h * 1.15)
		var focus := Vector3(0, h * 0.42, 0)
		var dir := Vector3(0.55, 0.62, 1.0).normalized()
		_cam.position = focus + dir * size / (2.0 * tan(deg_to_rad(_cam.fov * 0.5)))
		_cam.basis = Basis.looking_at(-dir, Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img and not img.is_empty():
			textures[kind] = ImageTexture.create_from_image(img)
		model.free()
	is_done = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	finished.emit()
