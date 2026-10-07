## Re-loads exported GLBs and measures them (cozy-game-modeling skill).
##  1. runtime GLTFDocument load of <models_dir>/*.glb
##  2. the editor-imported copy under res://imported_check/ if present (copy the GLBs
##     there and run `godot --headless --path . --import` first)
## godot --headless --path . --script <this> -- <models_dir> <out_json> [anchors.json]
## anchors.json: {"<glb basename>": "floor" | "wall" | "ceiling" | "surface"}.
##   floor/surface: lowest point at y=0.  wall: back plane at z=0, model in +z.
##   ceiling: attachment point at y=0, model hangs into -y.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var report := {}
	var anchors := {}
	if args.size() > 2:
		anchors = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".glb"))
	files.sort()
	for f: String in files:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(dir + "/" + f, st)
		var runtime := doc.generate_scene(st)
		var anchor: String = anchors.get(f.get_basename(), "floor")
		var r := _measure(runtime, anchor)
		r["markers"] = {}
		for c in runtime.get_children():
			if not (c is MeshInstance3D) and c is Node3D:
				r["markers"][String(c.name)] = [snappedf(c.position.x, 0.001), snappedf(c.position.y, 0.001), snappedf(c.position.z, 0.001)]
		r["anchor"] = anchor
		r["anchor_ok"] = _anchor_ok(anchor, r)
		r["runtime_gltf_load_error"] = err
		r["glb_bytes"] = FileAccess.get_file_as_bytes(dir + "/" + f).size()
		r["gltf_copyright"] = st.copyright
		var imp_path: String = "res://imported_check/" + f
		var packed = load(imp_path) if ResourceLoader.exists(imp_path) else null
		if packed is PackedScene:
			var inst: Node = packed.instantiate()
			var r2 := _measure(inst, anchor)
			r["editor_import"] = {"ok": true, "tris": r2.tris, "surfaces": r2.surfaces, "size_m": r2.size_m,
				"matches_runtime_load": r2.tris == r.tris and r2.surfaces == r.surfaces}
			inst.free()
		else:
			r["editor_import"] = {"ok": false}
		runtime.free()
		report[f.get_basename()] = r
		print("%s tris=%d surf=%d flipped=%d degenerate=%d open=%d floating=%d anchor=%s ok=%s import=%s" % [f, r.tris, r.surfaces, r.tris_wound_against_normals, r.degenerate_tris, r.open_boundary_edges, r.pieces_not_touching_anything, r.anchor, r.anchor_ok, r.editor_import.get("matches_runtime_load", false)])
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	quit()


func _anchor_ok(anchor: String, r: Dictionary) -> bool:
	match anchor:
		"floor", "surface":
			return absf(r.min_y) < 0.002
		"wall":
			return absf(r.min_z) < 0.002
		"ceiling":
			return absf(r.max_y) < 0.002
	return false


func _measure(root: Node, anchor := "floor") -> Dictionary:
	var meshes := []
	_collect(root, Transform3D.IDENTITY, meshes)
	var tris := 0
	var verts := 0
	var surfaces := 0
	var mats := {}
	var flipped := 0
	var degenerate := 0
	var box := AABB()
	var first := true
	var all_v := PackedVector3Array()
	var all_i := PackedInt32Array()
	for m in meshes:
		var mesh: Mesh = m[0]
		var xf: Transform3D = m[1]
		for s in mesh.get_surface_count():
			surfaces += 1
			var mat := mesh.surface_get_material(s)
			mats[mat.resource_name if mat else "none"] = (mat as BaseMaterial3D).albedo_color.to_html(false) if mat else ""
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			verts += v.size()
			var base := all_v.size()
			for p in v:
				var w := xf * p
				all_v.append(w)
				box = AABB(w, Vector3.ZERO) if first else box.expand(w)
				first = false
			for t in range(0, idx.size(), 3):
				tris += 1
				var a0 := v[idx[t]]
				var cr := (v[idx[t + 1]] - a0).cross(v[idx[t + 2]] - a0)
				if cr.length_squared() < 1e-14:
					degenerate += 1
				# Godot front faces are clockwise, so the cross product points inward.
				elif cr.dot(n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]) > 0.0:
					flipped += 1
				all_i.append_array([base + idx[t], base + idx[t + 1], base + idx[t + 2]])
	var parts := _components(all_v, all_i, anchor)
	return {
		"tris": tris, "vertices": verts, "surfaces": surfaces, "materials": mats,
		"size_m": [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)],
		"min_y": snappedf(box.position.y, 0.0001), "max_y": snappedf(box.end.y, 0.0001),
		"min_z": snappedf(box.position.z, 0.0001),
		"center_xz": [snappedf(box.get_center().x, 0.001), snappedf(box.get_center().z, 0.001)],
		"tris_wound_against_normals": flipped, "degenerate_tris": degenerate,
		"connected_pieces": parts.count, "open_boundary_edges": parts.open_edges,
		"pieces_not_touching_anything": parts.floating,
	}


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D:
		xf = xf * n.transform
	if n is MeshInstance3D:
		out.append([n.mesh, xf])
	for c in n.get_children():
		_collect(c, xf, out)


## Welds by position, counts connected pieces and open edges, and flags pieces whose
## bounds neither touch the anchor plane nor overlap another piece (a "floating" part).
## Bounds overlap is crude: it cannot prove parts really touch (inspect renders too).
func _components(v: PackedVector3Array, idx: PackedInt32Array, anchor := "floor") -> Dictionary:
	var key := {}
	var rep := PackedInt32Array()
	for p in v:
		var k := p.snapped(Vector3.ONE * 1e-4)
		if not key.has(k):
			key[k] = key.size()
		rep.append(key[k])
	var uf := PackedInt32Array(range(key.size()))
	var find := func(x: int) -> int:
		while uf[x] != x:
			x = uf[x]
		return x
	var edges := {}
	for t in range(0, idx.size(), 3):
		var r := [rep[idx[t]], rep[idx[t + 1]], rep[idx[t + 2]]]
		for j in 3:
			var e := Vector2i(mini(r[j], r[(j + 1) % 3]), maxi(r[j], r[(j + 1) % 3]))
			edges[e] = edges.get(e, 0) + 1
			var a: int = find.call(r[j])
			var b: int = find.call(r[(j + 1) % 3])
			if a != b:
				uf[b] = a
	var open := 0
	for e in edges:
		if edges[e] == 1:
			open += 1
	var boxes := {}
	for k in key:
		var root: int = find.call(key[k])
		boxes[root] = AABB(k, Vector3.ZERO) if not boxes.has(root) else boxes[root].expand(k)
	# Supported = touches the anchor plane, or overlaps (bounds) a supported piece.
	var list := boxes.values()
	var supported := {}
	var queue := []
	for i in list.size():
		var bi: AABB = list[i].grow(0.002)
		var on_plane: bool = bi.position.y <= 0.003 if anchor in ["floor", "surface"] else (bi.position.z <= 0.003 if anchor == "wall" else bi.end.y >= -0.003)
		if on_plane:
			supported[i] = true
			queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in list.size():
			if not supported.has(j) and list[i].grow(0.002).intersects(list[j]):
				supported[j] = true
				queue.append(j)
	var floating := list.size() - supported.size()
	return {"count": list.size(), "open_edges": open, "floating": floating}
