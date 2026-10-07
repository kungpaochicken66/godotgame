## Deterministic asset validator v2 (cozy-game-modeling skill).
## godot --headless --path <project> --script <this> -- <spec.json> <models_dir> <out.json> [imported_res_dir] [registry.json]
## spec.json: {"assets": [{"asset_id", "manifest": {anchor, size_class, interact,
##   tabletop_eligible, footprint_radius, support_surface?, wearable?}}]}
## registry.json (optional): {"hosts": [{"host_id", "usable_size_xz"}], "eligible": [{"item_id", "size_xz"}]}
##   known support hosts and tabletop-eligible items from the game and earlier batches.
## Gates (all must pass for "accepted_geometry"; this is NOT artistic approval):
##  G1 load: runtime glTF load OK; editor-imported copy matches runtime counts (if given)
##  G2 geometry: 0 triangles wound against normals, 0 degenerate, 0 open edges,
##     0 unsupported pieces (overlap graph from the anchor plane)
##  G3 anchor/origin: ground: min_y = 0 and footprint center near origin; wall: min_z = 0;
##     ceiling: max_y = 0
##  G4 size class (contract §3): small h 0.26..0.585; medium h 0.78..1.56; large long side
##     >= 0.78 (1.5 chair widths); flat h < 0.1. Wall/ceiling: small/medium/large by
##     longest side <= 0.6 / <= 1.2 / > 1.2 (lab rule, contract silent)
##  G5 footprint (contract §2): ground solid radius <= 0.75 * longest side + 0.15
##  G6 markers: Seating -> Seat0, Bed -> Sleep0, Lighting -> Light0
##  G7 budget: 1..6 materials; tris <= 6000
##  G8 support (if declared): max_items == 1; grid of downward rays over the usable
##     rectangle all hit an upward-facing triangle at local_position.y +- 0.002; the
##     Support0 marker equals local_position; and the host accepts EVERY known eligible
##     item at one or more of the 8 rotations (otherwise it would break "eligible items fit
##     every host" in the game)
##  G9 tabletop eligible: small class, ground anchor, and fits EVERY known host at one or
##     more rotations; the full 8-rotation matrix (turned box |w cos a| + |d sin a|) is reported
extends SceneTree

const H := 1.30
const KNOWN_HOSTS := [
	{"host_id": "table (game)", "usable_size_xz": [0.84, 0.84]},
	{"host_id": "cozy_round_table (pilot)", "usable_size_xz": [0.56, 0.56]},
]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var models: String = a[1]
	var out_path: String = a[2]
	var imported: String = a[3] if a.size() > 3 else ""
	var hosts: Array = KNOWN_HOSTS.duplicate(true)
	var eligible: Array = []
	if a.size() > 4 and FileAccess.file_exists(a[4]):
		var reg = JSON.parse_string(FileAccess.get_file_as_string(a[4]))
		if reg is Array:
			hosts.append_array(reg)
		else:
			hosts = reg.get("hosts", hosts)
			eligible = reg.get("eligible", [])
	var results := {}
	var measured := {}
	for asset in spec["assets"]:
		var id: String = asset["asset_id"]
		var man: Dictionary = asset["manifest"]
		var r := {"gates": {}, "measured": {}}
		var path := "%s/%s.glb" % [models, id]
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(path, st)
		if err != OK:
			r["gates"]["G1_load"] = {"pass": false, "detail": "runtime load error %d" % err}
			results[id] = r
			continue
		var root := doc.generate_scene(st)
		var anchor: String = man.get("anchor", "ground")
		var m := _measure(root, anchor)
		m["glb_bytes"] = FileAccess.get_file_as_bytes(path).size()
		m["markers"] = {}
		for c in root.get_children():
			if c is Node3D and not (c is MeshInstance3D):
				m["markers"][String(c.name)] = _v(c.position)
		r["measured"] = m
		measured[id] = m
		# G1
		var g1 := {"pass": true, "detail": "runtime ok"}
		if imported != "":
			var ip := "%s/%s.glb" % [imported, id]
			var packed = load(ip) if ResourceLoader.exists(ip) else null
			if packed is PackedScene:
				var inst: Node = packed.instantiate()
				var m2 := _measure(inst, anchor)
				var same: bool = m2.tris == m.tris and m2.surfaces == m.surfaces and (m2.size as Array) == (m.size as Array)
				g1 = {"pass": same, "detail": "editor import tris %d surf %d size %s" % [m2.tris, m2.surfaces, m2.size]}
				inst.free()
			else:
				g1 = {"pass": false, "detail": "editor-imported copy missing: " + ip}
		r["gates"]["G1_load"] = g1
		# G2
		var g2: bool = m.flipped == 0 and m.degenerate == 0 and m.open_edges == 0 and m.unsupported == 0
		r["gates"]["G2_geometry"] = {"pass": g2, "detail": "flipped %d degenerate %d %s open %d unsupported %d %s pieces %d" % [m.flipped, m.degenerate, m.first_degenerate, m.open_edges, m.unsupported, m.unsupported_at if m.unsupported > 0 else "", m.pieces]}
		# G3
		var s: Array = m.size
		var g3 := true
		var d3 := ""
		match anchor:
			"ground":
				g3 = absf(m.min[1]) < 0.002 and absf(m.center[0]) <= 0.12 and absf(m.center[2]) <= 0.12
				d3 = "min_y %.4f center_xz (%.3f, %.3f)" % [m.min[1], m.center[0], m.center[2]]
			"wall":
				g3 = absf(m.min[2]) < 0.002 and absf(m.center[0]) <= 0.05
				d3 = "back plane min_z %.4f center_x %.3f" % [m.min[2], m.center[0]]
			"ceiling":
				g3 = absf(m.max[1]) < 0.002 and absf(m.center[0]) <= 0.12 and absf(m.center[2]) <= 0.12
				d3 = "top max_y %.4f" % m.max[1]
			_:
				g3 = false
				d3 = "unknown anchor " + anchor
		r["gates"]["G3_anchor_origin"] = {"pass": g3, "detail": d3}
		# G4
		var sc: String = man.get("size_class", "")
		var longest: float = maxf(s[0], s[2])
		var g4 := false
		if anchor == "ground":
			match sc:
				"small": g4 = s[1] >= 0.26 and s[1] <= 0.585
				"medium": g4 = s[1] >= 0.78 and s[1] <= 1.56
				"large": g4 = longest >= 0.78
				"flat": g4 = s[1] < 0.1
		else:
			var big: float = maxf(maxf(s[0], s[1]), s[2])
			match sc:
				"small": g4 = big <= 0.6
				"medium": g4 = big > 0.6 and big <= 1.2
				"large": g4 = big > 1.2
		r["gates"]["G4_size_class"] = {"pass": g4, "detail": "%s: size %s (h %.3f = %.2f H, long side %.3f)" % [sc, s, s[1], s[1] / H, longest]}
		# G5
		var rad: float = man.get("footprint_radius", 0.0)
		var g5 := true
		if anchor == "ground" and man.get("layer", "solid") == "solid":
			g5 = rad > 0.0 and rad <= 0.75 * longest + 0.15
		r["gates"]["G5_footprint"] = {"pass": g5, "detail": "radius %.3f, limit %.3f" % [rad, 0.75 * longest + 0.15]}
		# G6
		var need := {"Seating": "Seat0", "Bed": "Sleep0", "Lighting": "Light0"}
		var it: String = man.get("interact", "-")
		var g6 := true
		if need.has(it):
			g6 = m["markers"].has(need[it])
		r["gates"]["G6_markers"] = {"pass": g6, "detail": "interact %s markers %s" % [it, m["markers"].keys()]}
		# G7
		var g7: bool = m.surfaces >= 1 and m.surfaces <= 6 and m.tris <= 6000
		r["gates"]["G7_budget"] = {"pass": g7, "detail": "tris %d materials %d" % [m.tris, m.surfaces]}
		# G8
		if man.get("support_surface") != null:
			r["gates"]["G8_support"] = _support_check(root, man["support_surface"], m["markers"])
		results[id] = r
		root.free()
	# G8 host acceptance and G9 need all hosts / eligible items: registry + this spec.
	for asset in spec["assets"]:
		var ss = asset["manifest"].get("support_surface")
		if ss != null:
			hosts.append({"host_id": asset["asset_id"], "usable_size_xz": ss["usable_size_xz"]})
		if asset["manifest"].get("tabletop_eligible", false) and measured.has(asset["asset_id"]):
			var sz: Array = measured[asset["asset_id"]].size
			eligible.append({"item_id": asset["asset_id"], "size_xz": [sz[0], sz[2]]})
	for asset in spec["assets"]:
		var id: String = asset["asset_id"]
		if not results.has(id) or not results[id]["measured"].has("size"):
			continue
		var man: Dictionary = asset["manifest"]
		var s: Array = measured[id].size
		var mat := {}
		var every_host := true
		for h in hosts:
			var ok_rot := _fit_rotations([s[0], s[2]], h["usable_size_xz"])
			mat[h["host_id"]] = ok_rot
			if ok_rot.is_empty():
				every_host = false
		results[id]["fit_matrix_degrees"] = mat
		if man.get("tabletop_eligible", false):
			var g9: bool = man.get("size_class") == "small" and every_host and man.get("anchor") == "ground"
			results[id]["gates"]["G9_tabletop"] = {"pass": g9, "detail": "fits every one of %d hosts at some rotation: %s" % [hosts.size(), every_host]}
		var ss = man.get("support_surface")
		if ss != null and results[id]["gates"].has("G8_support"):
			var refused := []
			var accepts := {}
			for e in eligible:
				var rots := _fit_rotations(e["size_xz"], ss["usable_size_xz"])
				accepts[e["item_id"]] = rots
				if rots.is_empty():
					refused.append(e["item_id"])
			results[id]["host_accepts_degrees"] = accepts
			var g8: Dictionary = results[id]["gates"]["G8_support"]
			g8["detail"] += "; refuses eligible items: %s" % [refused]
			g8["pass"] = g8["pass"] and refused.is_empty()
	var summary := {}
	for id in results:
		var ok := true
		for g in results[id]["gates"]:
			ok = ok and results[id]["gates"][g]["pass"]
		results[id]["accepted_geometry"] = ok
		summary[id] = ok
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"validator": "validate_assets.gd v2.1", "hosts": hosts, "eligible": eligible, "summary": summary, "results": results}, "  "))
	for id in results:
		var fails := []
		for g in results[id]["gates"]:
			if not results[id]["gates"][g]["pass"]:
				fails.append("%s(%s)" % [g, results[id]["gates"][g]["detail"]])
		print("%s %s %s" % [id, "PASS" if summary[id] else "FAIL", " ".join(fails)])
	quit()


func _fit_rotations(size_xz: Array, usable: Array) -> Array:
	var ok := []
	for k in 8:
		var ang := deg_to_rad(45.0 * k)
		var tw := absf(size_xz[0] * cos(ang)) + absf(size_xz[1] * sin(ang))
		var td := absf(size_xz[0] * sin(ang)) + absf(size_xz[1] * cos(ang))
		if tw <= usable[0] + 1e-6 and td <= usable[1] + 1e-6:
			ok.append(45 * k)
	return ok


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]


## Downward ray grid (11 x 11) over the usable rectangle.
func _support_check(root: Node, ss: Dictionary, markers: Dictionary) -> Dictionary:
	var lp: Array = ss["local_position"]
	var u: Array = ss["usable_size_xz"]
	var tris := []
	_tris(root, Transform3D.IDENTITY, tris)
	var bad := 0
	var worst := 0.0
	for i in 11:
		for j in 11:
			var x: float = lp[0] - u[0] * 0.5 + u[0] * i / 10.0
			var z: float = lp[2] - u[1] * 0.5 + u[1] * j / 10.0
			var from := Vector3(x, lp[1] + 5.0, z)
			var best := -INF
			var best_n := Vector3.ZERO
			for t in tris:
				var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, t[0], t[1], t[2])
				if hit != null and hit.y > best:
					best = hit.y
					best_n = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
			var dy := absf(best - lp[1]) if best > -INF else INF
			worst = maxf(worst, dy)
			if dy > 0.002 or absf(best_n.y) < 0.99:
				bad += 1
	var marker_ok := markers.has("Support0") and Vector3(markers["Support0"][0], markers["Support0"][1], markers["Support0"][2]).distance_to(Vector3(lp[0], lp[1], lp[2])) < 0.002
	var ok: bool = int(ss.get("max_items", 0)) == 1 and bad == 0 and marker_ok
	return {"pass": ok, "detail": "rays off-surface %d/121, worst dy %.4f, max_items %s, Support0 matches %s" % [bad, worst, ss.get("max_items"), marker_ok]}


func _tris(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D:
		xf = xf * n.transform
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var arr: Array = n.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				out.append([xf * v[idx[t]], xf * v[idx[t + 1]], xf * v[idx[t + 2]]])
	for c in n.get_children():
		_tris(c, xf, out)


func _measure(root: Node, anchor: String) -> Dictionary:
	var meshes := []
	_collect(root, Transform3D.IDENTITY, meshes)
	var tris := 0
	var surfaces := 0
	var mats := {}
	var flipped := 0
	var degenerate := 0
	var first_degenerate := ""
	var box := AABB()
	var first := true
	var all_v := PackedVector3Array()
	var all_i := PackedInt32Array()
	for mm in meshes:
		var mesh: Mesh = mm[0]
		var xf: Transform3D = mm[1]
		for s in mesh.get_surface_count():
			surfaces += 1
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			mats[mat.resource_name if mat else "none"] = mat.albedo_color.to_html(false) if mat else ""
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
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
					if first_degenerate == "":
						first_degenerate = "%s at %s" % [mat.resource_name if mat else "?", _v(xf * a0)]
				elif cr.dot(n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]) > 0.0:
					flipped += 1
				all_i.append_array([base + idx[t], base + idx[t + 1], base + idx[t + 2]])
	var comp := _components(all_v, all_i, anchor)
	return {"tris": tris, "vertices": all_v.size(), "surfaces": surfaces, "materials": mats,
		"size": _v(box.size), "min": _v(box.position), "max": _v(box.end), "center": _v(box.get_center()),
		"flipped": flipped, "degenerate": degenerate, "first_degenerate": first_degenerate, "unsupported_at": comp.unsupported_at, "open_edges": comp.open, "pieces": comp.count, "unsupported": comp.unsupported}


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D:
		xf = xf * n.transform
	if n is MeshInstance3D:
		out.append([n.mesh, xf])
	for c in n.get_children():
		_collect(c, xf, out)


func _components(v: PackedVector3Array, idx: PackedInt32Array, anchor: String) -> Dictionary:
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
			var ra: int = find.call(r[j])
			var rb: int = find.call(r[(j + 1) % 3])
			if ra != rb:
				uf[rb] = ra
	var open := 0
	for e in edges:
		if edges[e] == 1:
			open += 1
	var boxes := {}
	for k in key:
		var root: int = find.call(key[k])
		boxes[root] = AABB(k, Vector3.ZERO) if not boxes.has(root) else boxes[root].expand(k)
	var list := boxes.values()
	var supported := {}
	var queue := []
	for i in list.size():
		var bi: AABB = list[i].grow(0.002)
		var on: bool
		match anchor:
			"wall": on = bi.position.z <= 0.003
			"ceiling": on = bi.end.y >= -0.003
			_: on = bi.position.y <= 0.003
		if on:
			supported[i] = true
			queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in list.size():
			if not supported.has(j) and list[i].grow(0.002).intersects(list[j]):
				supported[j] = true
				queue.append(j)
	var where := []
	for i in list.size():
		if not supported.has(i) and where.size() < 4:
			where.append(_v(list[i].get_center()))
	return {"count": list.size(), "open": open, "unsupported": list.size() - supported.size(), "unsupported_at": where}
