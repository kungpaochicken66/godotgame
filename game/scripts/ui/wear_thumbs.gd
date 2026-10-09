## Wardrobe pictures (r14): renders a wearable's frozen GLB to a small picture only when its tile
## is on screen, keeps a bounded cache, and holds no viewport while idle. Nothing here runs at app
## startup: the HUD creates this node the first time the Wardrobe opens. docs/wearables.md.
##
## want(ids) replaces the queue with the tiles now visible (most important first), so fast tab
## changes and scrolling never render stale rows; a render already under way finishes into the
## cache. picture_ready(id, texture) is emitted for each finished picture (texture null if it failed).
extends Node

const Wearables := preload("res://scripts/core/wearables.gd")

signal picture_ready(id: String, texture: Texture2D)

## Picture size in pixels (shown at 76 px on the tile; 2x for sharp screens).
const SIZE := 128
## At most this many pictures stay in memory (about 64 KB each); the biggest tab has 50 items.
const CACHE_MAX := 120
## The render viewport is freed after this many seconds with nothing to do.
const IDLE_FREE := 2.0

var cache := {}            # id -> Texture2D (least recently used first in _order)
var failed := {}           # id -> true: no picture could be made (not retried this session)
var renders := 0           # pictures made (for tests and measurements)
var stub := false          # no renderer (headless): a flat per-item colour stands in, logic unchanged
## Test hook: a Callable(id) -> Texture2D replacing the renderer.
var render_override := Callable()

var _order: Array = []
var _queue: Array = []
var _busy := false
var _idle := 0.0
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


func _ready() -> void:
	stub = DisplayServer.get_name() == "headless"


## The tiles on screen now, in the order they should get pictures. Cached ones are touched (kept
## fresh in the cache); missing ones are queued; everything else is dropped from the queue.
func want(ids: Array) -> void:
	_queue.clear()
	for id in ids:
		if cache.has(id):
			_touch(id)
		elif not failed.has(id) and Wearables.has(id) and not _queue.has(id):
			_queue.append(id)
	if not _queue.is_empty() and not _busy:
		_run()


func get_cached(id: String) -> Texture2D:
	if cache.has(id):
		_touch(id)
		return cache[id]
	return null


## Drops these pictures from memory (they are made again when next shown).
func forget(ids: Array) -> void:
	for id in ids:
		cache.erase(id)
		_order.erase(id)
		failed.erase(id)


func queued() -> Array:
	return _queue.duplicate()


func viewports_alive() -> int:
	return 1 if is_instance_valid(_vp) else 0


func _touch(id: String) -> void:
	_order.erase(id)
	_order.append(id)


func _store(id: String, tex: Texture2D) -> void:
	if tex == null:
		failed[id] = true
	else:
		cache[id] = tex
		_touch(id)
		while _order.size() > CACHE_MAX:
			cache.erase(_order.pop_front())
	picture_ready.emit(id, tex)


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		if cache.has(id) or failed.has(id):
			continue
		var tex: Texture2D = null
		if render_override.is_valid():
			tex = render_override.call(id)
			await get_tree().process_frame
		elif stub:
			tex = _stub_texture(id)
			await get_tree().process_frame
		else:
			tex = await _render(id)
		renders += 1
		_store(id, tex)
	_busy = false
	_idle = 0.0


func _process(delta: float) -> void:
	if _busy or not is_instance_valid(_vp):
		return
	_idle += delta
	if _idle >= IDLE_FREE:
		_vp.queue_free()
		_vp = null
		_cam = null
		_stage = null


func _ensure_viewport() -> void:
	if is_instance_valid(_vp):
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#eef3ef")
	env.environment.ambient_light_energy = 0.6
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 0.85
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 26
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


## One picture: the garment as worn by a standing child (the GLB's pivots sit at the child's rest
## offsets), seated variants hidden, framed to its own bounds from slightly above and to the side.
func _render(id: String) -> Texture2D:
	_ensure_viewport()
	var scene := load(Wearables.glb(id)) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	_stage.add_child(inst)
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if str(m.name).ends_with("_sit"):
			m.visible = false
			continue
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var tex: Texture2D = null
	if not first:
		var dir := Vector3(0.32, 0.22, 1.0).normalized()
		var span := maxf(maxf(box.size.x, box.size.y), box.size.z) * 1.12
		var dist := span / (2.0 * tan(deg_to_rad(_cam.fov * 0.5))) + box.size.z * 0.5
		_cam.position = box.get_center() + dir * dist
		_cam.basis = Basis.looking_at(-dir, Vector3.UP)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	inst.free()
	return tex


## Headless stand-in: a distinct flat colour per item, so every tile, cache and queue rule is
## exercised exactly as with real pictures (no renderer exists to make real ones).
func _stub_texture(id: String) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var h := hash(id)
	img.fill(Color8(h & 255, (h >> 8) & 255, (h >> 16) & 255))
	return ImageTexture.create_from_image(img)
