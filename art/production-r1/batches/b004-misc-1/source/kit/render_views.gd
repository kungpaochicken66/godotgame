## Renders review views of GLBs with the game's lighting (cozy-game-modeling skill).
## godot --rendering-driver opengl3 --path <project> --script <this> -- <out_dir> [size=2.0] [anchors=<json>] <glb>...
## Per model writes <name>_{front,side,rear,threequarter}.png (orthographic, one
## shared frame size so items keep relative scale), <name>_closeup.png (auto-fit
## three-quarter) and <name>_game.png (perspective with the game's room camera:
## pitch 40, yaw 28, fov 42, distance 11 m, plus a floor/wall corner and a 1.2 m
## child-height scale post) and <name>_gamenear.png (same angles at 4.5 m).
## Anchors (from anchors json, default floor): floor/surface model sits on y=0;
## wall model's back is the z=0 plane (staged on a wall at 1.5 m in the game view);
## ceiling model hangs from y=0 (staged under a 2.8 m ceiling in the game view).
extends SceneTree

const VIEWS := {"front": 0.0, "side": 90.0, "rear": 180.0, "threequarter": 35.0}
const SIZE := Vector2i(512, 512)
const WALL_MOUNT_Y := 1.5
const CEILING_Y := 2.8

var vp: SubViewport
var cam: Camera3D


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var out_dir: String = args.pop_front()
	var ortho := 2.0
	var anchors := {}
	while not args.is_empty() and "=" in args[0]:
		var kv: PackedStringArray = args.pop_front().split("=")
		if kv[0] == "size":
			ortho = float(kv[1])
		elif kv[0] == "anchors":
			anchors = JSON.parse_string(FileAccess.get_file_as_string(kv[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	vp = SubViewport.new()
	vp.size = SIZE
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#f6efe2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#eef3ef")
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	# The game's sun (town_world.gd); no realtime shadows, like the game.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.8
	sun.light_color = Color("#fff4e0")
	vp.add_child(sun)
	cam = Camera3D.new()
	vp.add_child(cam)
	await process_frame
	for path in args:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(path, st) != OK:
			push_error("load failed " + path)
			continue
		var model := doc.generate_scene(st)
		_wrap_materials(model)
		var name: String = path.get_file().get_basename()
		var anchor: String = anchors.get(name, "floor")
		if anchor == "ground":
			anchor = "floor"
		var pivot := Node3D.new()
		vp.add_child(pivot)
		pivot.add_child(model)
		var box := _aabb(model, Transform3D.IDENTITY)
		var stage := _stage_ortho(anchor, box)
		vp.add_child(stage)
		# Orthographic views, model turned under a fixed camera.
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		for view in VIEWS:
			pivot.rotation_degrees.y = -VIEWS[view]
			if stage.has_node("Wall"):
				stage.get_node("Wall").visible = view != "rear"
			_ortho_cam(box.get_center(), ortho)
			await _shot("%s/%s_%s.png" % [out_dir, name, view])
		pivot.rotation_degrees.y = -35.0
		# Target the bounds center as rotated with the model (wall/ceiling items sit off-origin).
		_ortho_cam(pivot.transform.basis * box.get_center(), maxf(box.size.length() * 1.05, 0.4))
		await _shot("%s/%s_closeup.png" % [out_dir, name])
		stage.queue_free()
		# Game camera view.
		pivot.rotation_degrees.y = 0.0
		var room := _stage_room(anchor, box)
		vp.add_child(room)
		if anchor == "wall":
			pivot.position = Vector3(0, WALL_MOUNT_Y, 0)
		elif anchor == "ceiling":
			pivot.position = Vector3(0, CEILING_Y, 0)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 42.0
		var focus := pivot.position + box.get_center()
		var yaw := deg_to_rad(28.0)
		var pitch := deg_to_rad(40.0)
		var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 11.0
		cam.transform = Transform3D(Basis.looking_at(-off), focus + off)
		await _shot("%s/%s_game.png" % [out_dir, name], 3)
		# Same camera angles, 4.5 m away: readability check closer than the room view.
		var off2 := off.normalized() * 4.5
		cam.transform = Transform3D(Basis.looking_at(-off2), focus + off2)
		await _shot("%s/%s_gamenear.png" % [out_dir, name], 3)
		room.queue_free()
		pivot.queue_free()
		await process_frame
	quit()


func _ortho_cam(target: Vector3, size: float) -> void:
	cam.size = size
	var dir := Vector3(0, sin(deg_to_rad(18)), cos(deg_to_rad(18)))
	cam.transform = Transform3D(Basis.looking_at(-dir), target + dir * 4.0)


func _shot(path: String, frames := 2) -> void:
	for k in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


## Floor disc (floor/surface) or a wall panel at z=0 (wall); nothing for ceiling.
func _stage_ortho(anchor: String, box: AABB) -> Node3D:
	var s := Node3D.new()
	if anchor in ["floor", "surface"]:
		var d := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := maxf(0.55, maxf(box.size.x, box.size.z) * 0.62)
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.02
		cm.radial_segments = 64
		d.mesh = cm
		d.position.y = -0.0105
		d.material_override = _mat(Color("#e3c08e"))
		s.add_child(d)
	elif anchor == "wall":
		var w := MeshInstance3D.new()
		w.name = "Wall"
		var bm := BoxMesh.new()
		bm.size = Vector3(box.size.x + 0.5, box.size.y + 0.5, 0.04)
		w.mesh = bm
		w.position = Vector3(box.get_center().x, box.get_center().y, -0.021)
		w.material_override = _mat(Color("#efe2cf"))
		s.add_child(w)
	return s


## Room corner like the game's interior: floor, back wall (z = -1.2), left wall,
## and a 1.2 m capsule standing in for the child, for scale.
func _stage_room(anchor: String, box: AABB) -> Node3D:
	var s := Node3D.new()
	var back_z := 0.0 if anchor == "wall" else minf(box.position.z - 0.25, -0.6)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5, 4)
	floor.mesh = pm
	floor.position = Vector3(0, 0, back_z + 2.0)
	floor.material_override = _mat(Color("#e0b27a"))
	s.add_child(floor)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5, 2.8, 0.2)
	wall.mesh = bm
	wall.position = Vector3(0, 1.4, back_z - 0.1 - (0.0 if anchor != "wall" else 0.001))
	wall.material_override = _mat(Color("#efe2cf"))
	s.add_child(wall)
	var kid := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 1.2
	kid.mesh = cap
	kid.position = Vector3(box.end.x + 0.45, 0.6, back_z + 0.6)
	kid.material_override = _mat(Color("#c9c3d9"))
	s.add_child(kid)
	return s


func _wrap_materials(n: Node) -> void:
	if n is MeshInstance3D:
		for i in n.mesh.get_surface_count():
			var m := n.mesh.surface_get_material(i) as BaseMaterial3D
			if m:
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP  # not stored in glTF
	for c in n.get_children():
		_wrap_materials(c)


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D:
		xf = xf * n.transform
	if n is MeshInstance3D:
		out = xf * n.mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _aabb(c, xf)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out
