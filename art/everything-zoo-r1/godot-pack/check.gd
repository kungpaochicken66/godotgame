## Checks the everything-zoo-r1 animals as this project imports them, ready to use. Run after an import:
##   godot --headless --path <pack> --import
##   godot --headless --path <pack> -s res://check.gd
## Optional: -- --manifests=res://manifests --models=res://models --report=res://check_report.json
## Per asset (from its manifest): the file's SHA-256; the post-import ran; one mesh; every vertex has a
## colour and they vary; each material takes its colour from the vertex colours (linear, as glTF), with
## the game's Lambert-wrap diffuse, no texture, matte (metallic 0, roughness at least 0.9) and back
## faces culled; the triangle count; the height (1 %), the ground contact and the footprint centre
## (1 cm). A manifest with "colour_probe_linear" (self-test only) also checks the first colour's value.
## Writes a JSON report and exits 1 on any failure. It renders nothing.
extends SceneTree

var _checks := 0
var _fails: Array = []
var _report := {"assets": {}}


func ok(cond: bool, asset: String, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append("%s: %s" % [asset, what])
		print("FAIL [%s] %s" % [asset, what])
	_report["assets"].get_or_add(asset, []).append({"ok": cond, "check": what})


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return fallback


func _initialize() -> void:
	var man_dir := _arg("manifests", "res://manifests")
	var model_dir := _arg("models", "res://models")
	var report_path := _arg("report", "res://check_report.json")
	var names: Array = []
	var d := DirAccess.open(man_dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".manifest.json"):
				names.append(f)
	names.sort()
	ok(not names.is_empty(), "pack", "manifests found in %s" % man_dir)
	for f in names:
		var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(man_dir.path_join(f)))
		if typeof(man) != TYPE_DICTIONARY:
			ok(false, f, "the manifest parses")
			continue
		_check_asset(man, model_dir)
	_report["checks"] = _checks
	_report["failures"] = _fails
	_report["engine"] = Engine.get_version_info()["string"]
	var out := FileAccess.open(report_path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(_report, "  ", true) + "\n")
	print("EVERYTHING CHECK %s: %d checks, %d failures" % ["PASS" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	quit(1 if not _fails.is_empty() else 0)


func _check_asset(man: Dictionary, model_dir: String) -> void:
	var aid: String = str(man.get("asset_id", "?"))
	var path := model_dir.path_join(aid + ".glb")
	ok(FileAccess.file_exists(path), aid, "the GLB is in the pack (%s)" % path)
	if not FileAccess.file_exists(path):
		return
	var sha := FileAccess.get_sha256(path)
	ok(sha == str(man.get("glb_sha256", "")), aid, "the GLB's SHA-256 matches the manifest (%s)" % sha)
	var scene := load(path) as PackedScene
	ok(scene != null, aid, "Godot imports it as a scene")
	if scene == null:
		return
	var root := scene.instantiate() as Node3D
	ok(int(root.get_meta("everything_post_import", 0)) > 0, aid, "the post-import made it ready to use (%s material(s))" % str(root.get_meta("everything_post_import", 0)))
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	ok(meshes.size() == 1, aid, "exactly one mesh (%d)" % meshes.size())
	if meshes.size() != 1:
		root.free()
		return
	var mi := meshes[0] as MeshInstance3D
	# The mesh's transform within the scene, then its bounds there.
	var xf := Transform3D()
	var n: Node = mi
	while n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var box: AABB = xf * mi.mesh.get_aabb()
	var target := float(man.get("target_height", 0.0))
	var measured := {"height": box.size.y, "min_y": box.position.y, "center_x": box.get_center().x,
		"center_z": box.get_center().z, "size": [box.size.x, box.size.y, box.size.z]}
	ok(absf(box.size.y - target) <= target * 0.01, aid, "height %.3f m, target %.2f m" % [box.size.y, target])
	ok(absf(box.position.y) <= 0.01, aid, "stands on the ground (lowest point %.4f)" % box.position.y)
	ok(absf(box.get_center().x) <= 0.01 and absf(box.get_center().z) <= 0.01, aid,
		"footprint centred on the origin (%.4f, %.4f)" % [box.get_center().x, box.get_center().z])
	var tris := 0
	var colours := {}
	var has_colour := true
	var sum := Color(0, 0, 0, 0)
	var nsum := 0
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		tris += (idx.size() if idx.size() > 0 else verts.size()) / 3
		var cols = arrays[Mesh.ARRAY_COLOR]
		if cols == null or (cols as PackedColorArray).size() != verts.size():
			has_colour = false
		else:
			for c in cols:
				colours[Color(snappedf(c.r, 0.02), snappedf(c.g, 0.02), snappedf(c.b, 0.02))] = true
				sum += c
				nsum += 1
		var mat := mi.get_active_material(s)
		var bm := mat as BaseMaterial3D
		ok(bm != null, aid, "surface %d has a standard material" % s)
		if bm:
			ok(bm.vertex_color_use_as_albedo and not bm.vertex_color_is_srgb, aid, "surface %d takes its colour from the vertex colours, linear" % s)
			ok(bm.diffuse_mode == BaseMaterial3D.DIFFUSE_LAMBERT_WRAP, aid, "surface %d has the game's soft diffuse" % s)
			ok(bm.cull_mode == BaseMaterial3D.CULL_BACK, aid, "surface %d culls back faces (single-sided)" % s)
			ok(bm.albedo_texture == null and bm.roughness_texture == null and bm.metallic_texture == null and bm.normal_texture == null,
				aid, "surface %d has no texture" % s)
			ok(bm.metallic <= 0.001 and bm.roughness >= 0.9, aid, "surface %d is matte (metallic %.2f, roughness %.2f)" % [s, bm.metallic, bm.roughness])
	ok(has_colour, aid, "every vertex has a colour")
	if man.has("colour_probe_linear"):
		var probe: Array = man["colour_probe_linear"]
		var first: Color = (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0] if has_colour else Color.BLACK
		ok(absf(first.r - float(probe[0])) < 0.01 and absf(first.g - float(probe[1])) < 0.01 and absf(first.b - float(probe[2])) < 0.01,
			aid, "colours arrive as stored, linear (first %s, file %s)" % [first, probe])
	ok(colours.size() >= 3, aid, "the colours vary (%d distinct)" % colours.size())
	ok(tris == int(man.get("triangles", -1)), aid, "%d triangles, manifest %s" % [tris, str(man.get("triangles", "?"))])
	measured["triangles"] = tris
	measured["distinct_colours"] = colours.size()
	# Information, not a gate: the average vertex colour as sRGB (what an unlit picture would show).
	var mean := (sum / float(maxi(nsum, 1))).linear_to_srgb() if nsum > 0 else Color.BLACK
	measured["mean_colour_srgb"] = [snappedf(mean.r, 0.001), snappedf(mean.g, 0.001), snappedf(mean.b, 0.001)]
	_report["measured_" + aid] = measured
	print("ASSET %s: %.2f m high, %d triangles, %d colours, mean colour (sRGB) %s, sha %s" % [aid, box.size.y, tris, colours.size(), str(measured.get("mean_colour_srgb")), sha.left(12)])
	root.free()
