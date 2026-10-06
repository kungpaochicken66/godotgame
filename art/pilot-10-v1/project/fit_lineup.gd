## Support-fit checks + fit demo renders + scale lineup (pilot-specific).
## godot --rendering-driver opengl3 --path . --script res://fit_lineup.gd -- <models_dir> <out_dir> <game_chair.glb>
## Fit: prop origin placed at the host's Support0 marker; the prop's bounds (relative to
## its origin) must lie inside usable_size_xz around that point, bottom exactly at the
## surface. Lineup: avatar proxy (H = 1.30 from game/scripts/art/kid.gd), the game's
## current chair, then the 10 pilot items; wall clock on a wall at 1.5, mobile under a
## 2.8 ceiling bar. Visual fit demo only: no runtime parenting is implemented here.
extends SceneTree

const H := 1.30
var vp: SubViewport
var cam: Camera3D
var models: String


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	models = a[0]
	var out: String = a[1]
	var game_chair: String = a[2]
	DirAccess.make_dir_recursive_absolute(out)
	_setup(Vector2i(1600, 900))
	await process_frame
	# ---------- numeric fit checks
	var report := {}
	for host in ["02-round-table", "08-curved-counter"]:
		var hm: Dictionary = _build_json(host)["manifest"]
		if hm.get("support_surface") == null:
			report[host] = {"support_surface": null, "note": hm.get("support_note", "")}
			continue
		var ss: Dictionary = hm["support_surface"]
		var hn := _load(models + "/%s.glb" % host)
		var sup: Vector3 = hn.get_node("Support0").position
		hn.free()
		for prop in ["06-desk-lamp", "09-flower-pot"]:
			var pn := _load(models + "/%s.glb" % prop)
			var pb := _aabb(pn, Transform3D.IDENTITY)
			pn.free()
			var u: Array = ss["usable_size_xz"]
			var c: Array = ss["local_position"]
			var inside: bool = pb.position.x >= -u[0] * 0.5 and pb.end.x <= u[0] * 0.5 and pb.position.z >= -u[1] * 0.5 and pb.end.z <= u[1] * 0.5
			report["%s<-%s" % [host, prop]] = {
				"support_marker": [sup.x, sup.y, sup.z], "manifest_local_position": c,
				"marker_matches_manifest": sup.distance_to(Vector3(c[0], c[1], c[2])) < 0.002,
				"prop_bounds_size_xz": [snappedf(pb.size.x, 0.001), snappedf(pb.size.z, 0.001)],
				"prop_extent_from_origin": [snappedf(pb.position.x, 0.001), snappedf(pb.end.x, 0.001), snappedf(pb.position.z, 0.001), snappedf(pb.end.z, 0.001)],
				"usable_size_xz": u, "fits_contract_rule_size": pb.size.x <= u[0] and pb.size.z <= u[1],
				"fits_origin_centered_no_overhang": inside, "prop_bottom_y": snappedf(pb.position.y, 0.0001),
				"no_float_no_sink": absf(pb.position.y) < 0.002,
			}
	var f := FileAccess.open(out + "/support_fit_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	# ---------- fit demo renders (table + one prop each)
	for prop in ["09-flower-pot", "06-desk-lamp"]:
		var root := Node3D.new()
		vp.add_child(root)
		var t := _load(models + "/02-round-table.glb")
		root.add_child(t)
		var p := _load(models + "/%s.glb" % prop)
		p.position = t.get_node("Support0").position
		root.add_child(p)
		_ortho(Vector3(0, 0.55, 0), 1.6, 35.0, 22.0)
		await _shot(out + "/fit_table_%s_threequarter.png" % prop)
		_ortho(Vector3(0, 0.55, 0), 1.6, 0.0, 4.0)
		await _shot(out + "/fit_table_%s_front_level.png" % prop)
		_game(Vector3(0, 0.5, 0), 6.0)
		await _shot(out + "/fit_table_%s_game_close.png" % prop)
		root.queue_free()
		await process_frame
	# ---------- lineup
	var row := Node3D.new()
	vp.add_child(row)
	var items := [["Avatar proxy H=1.30", "", 0.45], ["Game chair (current)", game_chair, 0.6],
		["01 chair", "01-chair", 0.65], ["02 round table", "02-round-table", 1.1], ["03 bed", "03-bed", 1.1],
		["04 bureau", "04-writing-bureau", 0.9], ["05 open shelf", "05-open-shelf", 1.05],
		["06 desk lamp", "06-desk-lamp", 0.5], ["07 wall clock (wall 1.5)", "07-wall-clock", 0.6],
		["08 curved counter", "08-curved-counter", 1.45], ["09 flower pot", "09-flower-pot", 0.5],
		["10 bird mobile (ceiling 2.8)", "10-bird-mobile", 0.95]]
	var total := 0.0
	for it in items:
		total += it[2]
	var x := -total * 0.5
	var labels := []
	for it in items:
		x += it[2] * 0.5
		var n: Node3D
		if it[1] == "":
			n = _avatar()
		else:
			n = _load(it[1] if it[1].ends_with(".glb") else models + "/%s.glb" % it[1])
		n.position.x = x
		if it[1] == "07-wall-clock":
			n.position += Vector3(0, 1.5, -0.6)
			var w := _box(Vector3(0.7, 2.8, 0.06), Color("#efe2cf"), Vector3(x, 1.4, -0.63))
			row.add_child(w)
		elif it[1] == "10-bird-mobile":
			n.position.y = 2.8
			row.add_child(_box(Vector3(0.9, 0.05, 0.3), Color("#d9c7ad"), Vector3(x, 2.825, 0)))
		row.add_child(n)
		labels.append([it[0], x])
		x += it[2] * 0.5
	var floor := _box(Vector3(total + 1.0, 0.02, 2.4), Color("#e0b27a"), Vector3(0, -0.011, 0))
	row.add_child(floor)
	_ortho(Vector3(0, 1.4, 0), 5.6, 0.0, 8.0)
	await _labeled_shot(out + "/lineup_isolated_front.png", labels, 0.0)
	var tags := []
	for l in labels:
		var t: String = l[0].split(" ")[0]
		tags.append([{"Avatar": "H", "Game": "G"}.get(t, t), l[1]])
	_game(Vector3(0, 0.9, 0), 11.0 * 1.25)
	await _labeled_shot(out + "/lineup_game_camera.png", tags, 0.0)
	quit()


func _setup(size: Vector2i) -> void:
	vp = SubViewport.new()
	vp.size = size
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


func _ortho(target: Vector3, size: float, yaw_deg: float, elev_deg: float) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	var y := deg_to_rad(yaw_deg)
	var e := deg_to_rad(elev_deg)
	var d := Vector3(sin(y) * cos(e), sin(e), cos(y) * cos(e))
	cam.transform = Transform3D(Basis.looking_at(-d), target + d * 8.0)


## The game's room camera: pitch 40, yaw 28, fov 42 (distance given).
func _game(focus: Vector3, dist: float) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 42.0
	var y := deg_to_rad(28.0)
	var p := deg_to_rad(40.0)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.transform = Transform3D(Basis.looking_at(-off), focus + off)


func _shot(path: String) -> void:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)


func _labeled_shot(path: String, labels: Array, y: float) -> void:
	var cl := CanvasLayer.new()
	vp.add_child(cl)
	await process_frame
	for l in labels:
		var lab := Label.new()
		lab.text = l[0]
		lab.add_theme_font_size_override("font_size", 15)
		lab.add_theme_color_override("font_color", Color("#3c4a3a"))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.size = Vector2(120, 50)
		lab.position = cam.unproject_position(Vector3(l[1], y, 0.9)) - Vector2(60, -6)
		cl.add_child(lab)
	await _shot(path)
	cl.queue_free()


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


func _build_json(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(models + "/%s.build.json" % id))


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


## Neutral stand-in for the game's child: body capsule + head sphere, top at H.
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
