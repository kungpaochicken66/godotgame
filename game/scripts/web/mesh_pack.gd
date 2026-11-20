## A compact mesh pack for the Three.js city (design/city-threejs.md): a node tree, its meshes and the roles of
## their materials, as one JSON header and one little-endian binary blob. The page's js/meshpack.js reads it.
##
## Used at build time by tests/web_city/export.gd (the city: data/city.json + data/city.bin) and at run time by
## the bridge for the children (each child's rig, sent once per look).
##
## Header (JSON):
##   {"version": 1, "nodes": [...], "meshes": [...], "materials": {role: {...}}, "bytes": n}
##   node: {"name", "parent" (index, -1 for the root), "xf" (12 floats: basis x, y, z columns, then origin),
##          "visible", "mesh" (index or -1), "kind" ("node", "mesh", "multimesh", "light"),
##          "mm": {"mesh", "count", "colors": bool} for a MultiMesh (instances are the page's to set),
##          "light": {"color", "range", "energy"} for an OmniLight3D, "meta": {...} (base_y, kind, energy)}
##   mesh: {"surfaces": [{"material" (role), "count" (vertices), "pos", "nrm", "col", "idx", "icount", "i16"}]}
##     pos: byte offset of float32 x,y,z per vertex; nrm: int8 x,y,z,0 (x127); col: uint8 r,g,b,a (sRGB, as
##     Godot stores vertex colours) or -1; idx: byte offset of uint16 (i16) or uint32 indices, or -1.
##   material roles: the caller names known materials (glow, cabin, ground, ...); any other one is "m<k>"
##     with its parameters, so nothing is lost.
##
## Optional, off by default (the city export uses none of them, so its files do not change):
##   exclude    {Node: true}: these nodes and their subtrees are left out (the children's name labels).
##   track      the packed nodes are kept in pack order in `tracked` (the bridge poses them by index).
##   textures   each surface also carries "uv" (byte offset of float32 u,v per vertex, or -1), and a material
##              with an albedo texture carries "texture": {"kind": "gradient", "w", "h", "fill" ("linear",
##              "radial", "square"), "from" [u, v], "to" [u, v], "offsets" [...], "colors" [[r, g, b, a] ...]}
##              (a GradientTexture2D, described so the page draws it itself) or {"kind": "png", "w", "h",
##              "png" (base64)} for another texture whose image can be read, else {"kind": "missing"}.
extends RefCounted


class Pack:
	var nodes: Array = []
	var meshes: Array = []
	var materials := {}
	var roles := {}            # Material -> role
	var _mesh_ids := {}        # Mesh -> index
	var bin := StreamPeerBuffer.new()
	var skip_hidden := false
	var exclude := {}          # Node -> true: left out with their subtrees (optional)
	var track := false         # keep the packed nodes in pack order in `tracked` (optional)
	var tracked: Array = []
	var textures := false      # carry UVs and albedo textures (optional; see the header)

	func _init() -> void:
		bin.big_endian = false

	func _align4() -> void:
		while bin.get_position() % 4 != 0:
			bin.put_u8(0)

	func role_of(mat: Material) -> String:
		if mat == null:
			return "none"
		if roles.has(mat):
			var r: String = roles[mat]
			if not materials.has(r):
				materials[r] = _describe(mat)
			return r
		var r2 := "m%d" % roles.size()
		roles[mat] = r2
		materials[r2] = _describe(mat)
		return r2

	func _describe(mat: Material) -> Dictionary:
		var d := describe(mat)
		if textures and mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
			d["texture"] = describe_texture((mat as BaseMaterial3D).albedo_texture)
		return d

	## A texture for the page (see the header, "textures").
	static func describe_texture(tex: Texture2D) -> Dictionary:
		if tex is GradientTexture2D:
			var gt := tex as GradientTexture2D
			var offsets: Array = []
			var colors: Array = []
			if gt.gradient:
				for i in gt.gradient.get_point_count():
					offsets.append(gt.gradient.get_offset(i))
					var c := gt.gradient.get_color(i)
					colors.append([c.r, c.g, c.b, c.a])
			return {"kind": "gradient", "w": gt.width, "h": gt.height,
				"fill": ["linear", "radial", "square"][clampi(gt.fill, 0, 2)],
				"from": [gt.fill_from.x, gt.fill_from.y], "to": [gt.fill_to.x, gt.fill_to.y], "offsets": offsets, "colors": colors}
		var img: Image = tex.get_image() if tex else null
		if img == null or img.is_empty():
			return {"kind": "missing"}
		if img.is_compressed():
			img = img.duplicate()
			if img.decompress() != OK:
				return {"kind": "missing"}
		return {"kind": "png", "w": img.get_width(), "h": img.get_height(), "png": Marshalls.raw_to_base64(img.save_png_to_buffer())}

	static func describe(mat: Material) -> Dictionary:
		var d := {"type": mat.get_class()}
		if mat is StandardMaterial3D:
			var m := mat as StandardMaterial3D
			d["albedo"] = [m.albedo_color.r, m.albedo_color.g, m.albedo_color.b, m.albedo_color.a]
			d["vertex_color"] = m.vertex_color_use_as_albedo
			d["vertex_srgb"] = m.vertex_color_is_srgb
			d["roughness"] = m.roughness
			d["metallic"] = m.metallic
			d["specular"] = m.metallic_specular
			d["unshaded"] = m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			d["transparent"] = m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			d["blend"] = ["mix", "add", "sub", "mul", "premul"][m.blend_mode] if m.blend_mode < 5 else "mix"
			d["depth_write"] = m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED
			d["cull"] = ["back", "front", "none"][m.cull_mode]
			d["emission"] = [m.emission.r, m.emission.g, m.emission.b] if m.emission_enabled else null
			d["emission_energy"] = m.emission_energy_multiplier
		return d

	func add_mesh(mesh: Mesh, override: Material = null) -> int:
		if _mesh_ids.has(mesh) and override == null:
			return _mesh_ids[mesh]
		var surfaces: Array = []
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var mat: Material = override if override else mesh.surface_get_material(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sd := {"material": role_of(mat), "count": v.size(), "pos": -1, "nrm": -1, "col": -1, "idx": -1, "icount": 0, "i16": false}
			if textures:
				sd["uv"] = -1
			_align4()
			sd["pos"] = bin.get_position()
			bin.put_data(v.to_byte_array())
			var n = arr[Mesh.ARRAY_NORMAL]
			if n != null and (n as PackedVector3Array).size() == v.size():
				_align4()
				sd["nrm"] = bin.get_position()
				var nb := PackedByteArray()
				nb.resize(v.size() * 4)
				var nn: PackedVector3Array = n
				for i in nn.size():
					nb.encode_s8(i * 4, clampi(roundi(nn[i].x * 127.0), -127, 127))
					nb.encode_s8(i * 4 + 1, clampi(roundi(nn[i].y * 127.0), -127, 127))
					nb.encode_s8(i * 4 + 2, clampi(roundi(nn[i].z * 127.0), -127, 127))
				bin.put_data(nb)
			var c = arr[Mesh.ARRAY_COLOR]
			if c != null and (c as PackedColorArray).size() == v.size():
				_align4()
				sd["col"] = bin.get_position()
				var cb := PackedByteArray()
				cb.resize(v.size() * 4)
				var cc: PackedColorArray = c
				for i in cc.size():
					cb[i * 4] = clampi(roundi(cc[i].r * 255.0), 0, 255)
					cb[i * 4 + 1] = clampi(roundi(cc[i].g * 255.0), 0, 255)
					cb[i * 4 + 2] = clampi(roundi(cc[i].b * 255.0), 0, 255)
					cb[i * 4 + 3] = clampi(roundi(cc[i].a * 255.0), 0, 255)
				bin.put_data(cb)
			var uv = arr[Mesh.ARRAY_TEX_UV] if textures else null
			if uv != null and (uv as PackedVector2Array).size() == v.size():
				_align4()
				sd["uv"] = bin.get_position()
				bin.put_data((uv as PackedVector2Array).to_byte_array())
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				var ii: PackedInt32Array = idx
				_align4()
				sd["idx"] = bin.get_position()
				sd["icount"] = ii.size()
				if v.size() <= 65535:
					sd["i16"] = true
					var ib := PackedByteArray()
					ib.resize(ii.size() * 2)
					for k in ii.size():
						ib.encode_u16(k * 2, ii[k])
					bin.put_data(ib)
				else:
					bin.put_data(ii.to_byte_array())
			surfaces.append(sd)
		meshes.append({"surfaces": surfaces})
		var id := meshes.size() - 1
		if override == null:
			_mesh_ids[mesh] = id
		return id

	static func xf12(t: Transform3D) -> Array:
		return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]

	## Adds `n` and its subtree (Node3D only); returns its index.
	func add_tree(n: Node, parent := -1) -> int:
		if not (n is Node3D):
			return -1
		var n3 := n as Node3D
		if skip_hidden and not n3.visible:
			return -1
		if not exclude.is_empty() and exclude.has(n):
			return -1
		var d := {"name": String(n.name), "parent": parent, "xf": xf12(n3.transform), "visible": n3.visible, "mesh": -1, "kind": "node"}
		var meta := {}
		for k in n.get_meta_list():
			var mv = n.get_meta(k)
			if mv is float or mv is int or mv is String or mv is bool:
				meta[String(k)] = mv
		if not meta.is_empty():
			d["meta"] = meta
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			d["kind"] = "mesh"
			d["mesh"] = add_mesh(mi.mesh, mi.material_override)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
			var mmi := n as MultiMeshInstance3D
			d["kind"] = "multimesh"
			d["mm"] = {"mesh": add_mesh(mmi.multimesh.mesh, mmi.material_override), "count": mmi.multimesh.instance_count,
				"colors": mmi.multimesh.use_colors}
		elif n is OmniLight3D:
			var l := n as OmniLight3D
			d["kind"] = "light"
			d["light"] = {"color": [l.light_color.r, l.light_color.g, l.light_color.b], "range": l.omni_range, "energy": l.light_energy}
		nodes.append(d)
		var me := nodes.size() - 1
		if track:
			tracked.append(n)
		for c in n.get_children():
			add_tree(c, me)
		return me

	func header() -> Dictionary:
		return {"version": 1, "nodes": nodes, "meshes": meshes, "materials": materials, "bytes": bin.get_size()}

	func bytes() -> PackedByteArray:
		return bin.data_array
