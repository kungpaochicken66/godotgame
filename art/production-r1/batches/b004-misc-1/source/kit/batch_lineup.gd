## Batch scale lineups + tabletop fit demos (cozy-game-modeling skill).
## godot --rendering-driver opengl3 --path <project> --script <this> -- <spec.json> <models_dir> <out_dir> <chair.glb> <host_table.glb>
## Lineups: avatar proxy (H = 1.30), reference chair, then up to 8 batch assets per image,
## ground items on the floor, wall items on a wall panel at 1.5, ceiling items under a
## 2.8 bar. Two views per row: isolated orthographic front (labels) and the game room
## camera (pitch 40, yaw 28, fov 42) at a distance fitting the row (numbered tags).
## Fit demos: each tabletop-eligible asset placed by origin at the host's Support0, at
## rotation 0 and 45 degrees (visual only; the validator's matrix is the fit evidence).
extends SceneTree

const H := 1.30
var vp: SubViewport
var cam: Camera3D


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var models: String = a[1]
	var out: String = a[2]
	var chair: String = a[3]
	var host: String = a[4]
	DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.8
	sun.light_color = Color("#fff4e0")
	vp.add_child(sun)
	cam = Camera3D.new()
	vp.add_child(cam)
	await process_frame
	var assets: Array = spec["assets"]
	var page := 0
	for start in range(0, assets.size(), 8):
		page += 1
		var row := Node3D.new()
		vp.add_child(row)
		var entries := [["H avatar", "", 0.5, "ground"], ["C chair", chair, 0.65, "ground"]]
		var n := start
		for asset in assets.slice(start, start + 8):
			n += 1
			entries.append(["%d %s" % [n, asset["asset_id"]], "%s/%s.glb" % [models, asset["asset_id"]], 0.0, asset["manifest"]["anchor"]])
		var x := 0.0
		var labels := []
		var total := 0.0
		var nodes := []
		for e in entries:
			var node: Node3D = _avatar() if e[1] == "" else _load(e[1])
			var w: float = e[2]
			if w == 0.0:
				var bx := _aabb(node, Transform3D.IDENTITY)
				w = maxf(bx.size.x, 0.35) + 0.25
			nodes.append([node, w, e])
			total += w
		x = -total * 0.5
		for nd in nodes:
			var node: Node3D = nd[0]
			var w: float = nd[1]
			var e: Array = nd[2]
			x += w * 0.5
			node.position.x = x
			if e[3] == "wall":
				node.position += Vector3(0, 1.5, -0.7)
				row.add_child(_box(Vector3(w, 2.8, 0.06), Color("#efe2cf"), Vector3(x, 1.4, -0.73)))
			elif e[3] == "ceiling":
				node.position.y = 2.8
				row.add_child(_box(Vector3(w, 0.05, 0.6), Color("#d9c7ad"), Vector3(x, 2.825, 0)))
			row.add_child(node)
			labels.append([e[0], x])
			x += w * 0.5
		row.add_child(_box(Vector3(total + 0.6, 0.02, 2.4), Color("#e0b27a"), Vector3(0, -0.011, 0)))
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(3.2, total * 9.0 / 16.0 + 0.2)
		var d := Vector3(0, sin(deg_to_rad(8)), cos(deg_to_rad(8)))
		var tgt := Vector3(0, cam.size * 0.5 - 0.35, 0)
		cam.transform = Transform3D(Basis.looking_at(-d), tgt + d * 10.0)
		await _labeled("%s/lineup_%d_isolated.png" % [out, page], labels, true)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 42.0
		var yaw := deg_to_rad(28.0)
		var pitch := deg_to_rad(40.0)
		var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * maxf(6.0, total * 1.25)
		cam.transform = Transform3D(Basis.looking_at(-off), Vector3(0, 0.8, 0) + off)
		await _labeled("%s/lineup_%d_game.png" % [out, page], labels, false)
		row.queue_free()
		await process_frame
	# Fit demos.
	for asset in assets:
		if not asset["manifest"].get("tabletop_eligible", false):
			continue
		for rot in [0, 45]:
			var root := Node3D.new()
			vp.add_child(root)
			var t := _load(host)
			root.add_child(t)
			var p := _load("%s/%s.glb" % [models, asset["asset_id"]])
			p.position = t.get_node("Support0").position
			p.rotation_degrees.y = rot
			root.add_child(p)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 1.7
			var dd := Vector3(sin(deg_to_rad(35)) * cos(deg_to_rad(30)), sin(deg_to_rad(30)), cos(deg_to_rad(35)) * cos(deg_to_rad(30)))
			cam.transform = Transform3D(Basis.looking_at(-dd), Vector3(0, 0.62, 0) + dd * 8.0)
			await _shot("%s/fit_%s_rot%d.png" % [out, asset["asset_id"], rot])
			root.queue_free()
			await process_frame
	quit()


func _labeled(path: String, labels: Array, full: bool) -> void:
	var cl := CanvasLayer.new()
	vp.add_child(cl)
	await process_frame
	for l in labels:
		var lab := Label.new()
		lab.text = l[0] if full else l[0].split(" ")[0]
		lab.add_theme_font_size_override("font_size", 14 if full else 18)
		lab.add_theme_color_override("font_color", Color("#3c4a3a"))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.size = Vector2(150, 60)
		lab.position = cam.unproject_position(Vector3(l[1], 0, 1.0)) - Vector2(75, -4)
		cl.add_child(lab)
	await _shot(path)
	cl.queue_free()


func _shot(path: String) -> void:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)


func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(path, st)
	var n: Node3D = doc.generate_scene(st)
	_wrap(n)
	return n


func _wrap(n: Node) -> void:
	if n is MeshInstance3D:
		for i in n.mesh.get_surface_count():
			var m := n.mesh.surface_get_material(i) as BaseMaterial3D
			if m:
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	for c in n.get_children():
		_wrap(c)


func _box(size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	m.material_override = mat
	m.position = pos
	return m


func _avatar() -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#c9c3d9")
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.19
	cap.height = 0.72
	body.mesh = cap
	body.position.y = 0.36
	body.material_override = mat
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.3
	sp.height = 0.58
	head.mesh = sp
	head.position.y = H - 0.29
	head.material_override = mat
	n.add_child(head)
	return n


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
