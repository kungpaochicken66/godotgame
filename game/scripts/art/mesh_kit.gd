## Procedural toy-like geometry: rounded boxes, cached primitives and soft materials.
##
## All art in the first playable is generated from code so it stays consistent,
## light on iPad memory and easy for the creator's ideas to be added as new
## builders. Shapes favor clear silhouettes and gentle bevels over texture detail.
extends RefCounted

static var _materials := {}
static var _meshes := {}


static func mat(color: Color, roughness := 0.9, emission := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [color.to_html(), roughness, emission.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission.a > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.0
	_materials[key] = m
	return m


## Unique material (not cached) for parts whose glow or color animates.
static func glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.15
	return m


## Box with spherical edges. Normals are exact, so it shades like a soft toy.
static func rounded_box(size: Vector3, radius: float, seg := 3) -> ArrayMesh:
	radius = minf(radius, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	var key := "rb|%s|%.3f|%d" % [size, radius, seg]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var axis_coords := func(half: float) -> Array:
		var c := []
		for i in seg + 1:
			c.append(-half + radius * float(i) / seg)
		for i in seg + 1:
			c.append(half - radius + radius * float(i) / seg)
		return c
	var cx: Array = axis_coords.call(h.x)
	var cy: Array = axis_coords.call(h.y)
	var cz: Array = axis_coords.call(h.z)
	# Each face: normal axis, sign, and the two in-plane coordinate lists.
	var faces := [[0, 1, cy, cz], [0, -1, cy, cz], [1, 1, cx, cz], [1, -1, cx, cz], [2, 1, cx, cy], [2, -1, cx, cy]]
	for f in faces:
		var ax: int = f[0]
		var sgn: float = f[1]
		var ua: Array = f[2]
		var va: Array = f[3]
		var base := verts.size()
		for i in ua.size():
			for j in va.size():
				var p := Vector3()
				p[ax] = h[ax] * sgn
				var others := [1, 2] if ax == 0 else ([0, 2] if ax == 1 else [0, 1])
				p[others[0]] = ua[i]
				p[others[1]] = va[j]
				var inner := p.clamp(-h + Vector3.ONE * radius, h - Vector3.ONE * radius)
				var n := (p - inner).normalized()
				verts.append(inner + n * radius)
				normals.append(n)
		var w := va.size()
		for i in ua.size() - 1:
			for j in w - 1:
				var a := base + i * w + j
				var quad := [a, a + w, a + w + 1, a + 1]
				_tri(indices, verts, normals, quad[0], quad[1], quad[2])
				_tri(indices, verts, normals, quad[0], quad[2], quad[3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


## Godot treats clockwise triangles as front faces; orient each triangle so its
## winding agrees with the outward vertex normals. Degenerate corner triangles are skipped.
static func _tri(indices: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int) -> void:
	var cross := (v[b] - v[a]).cross(v[c] - v[a])
	if cross.length_squared() < 1e-12:
		return
	if cross.dot(n[a] + n[b] + n[c]) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


static func sphere(radius: float, rings := 12) -> SphereMesh:
	var key := "sp|%.3f|%d" % [radius, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = rings * 2
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func cylinder(top: float, bottom: float, height: float, sides := 20) -> CylinderMesh:
	var key := "cy|%.3f|%.3f|%.3f|%d" % [top, bottom, height, sides]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = sides
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "ca|%.3f|%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 16
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "to|%.3f|%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 10
		_meshes[key] = m
	return _meshes[key]


## Adds a mesh part. Rotation in degrees.
static func part(parent: Node3D, mesh: Mesh, color: Variant, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = color if color is Material else mat(color)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, color: Variant, pos: Vector3, round := 0.06, rot := Vector3.ZERO) -> MeshInstance3D:
	return part(parent, rounded_box(size, round), color, pos, rot)


static func ball(parent: Node3D, radius: float, color: Variant, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	return part(parent, sphere(radius), color, pos, Vector3.ZERO, scl)


static func cyl(parent: Node3D, top: float, bottom: float, height: float, color: Variant, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return part(parent, cylinder(top, bottom, height), color, pos, rot)


## Soft round contact shadow that keeps objects visually grounded on any renderer.
static func blob_shadow(parent: Node3D, radius: float, strength := 0.22) -> MeshInstance3D:
	var key := "shadow|%.2f" % strength
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _shadow_texture()
		m.albedo_color = Color(0.18, 0.25, 0.12, strength)
		m.render_priority = -1
		_materials[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.2, radius * 2.2)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _materials[key]
	mi.position.y = 0.015
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static var _shadow_tex: Texture2D

static func _shadow_texture() -> Texture2D:
	if _shadow_tex:
		return _shadow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_shadow_tex = t
	return t


static var _vc_material: StandardMaterial3D

## Merges the plain mesh parts directly under each node of a model into one
## vertex-colored mesh. Animated pivots, glowing and transparent parts stay
## separate. This turns a prop from dozens of draw calls into a few, which
## matters for iPad GPUs (and for the software renderer used in tests).
static func merge_parts(node: Node3D) -> void:
	for child in node.get_children():
		if child is Node3D and not (child is MeshInstance3D):
			merge_parts(child)
	var parts: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D and child.get_child_count() == 0 and not child.is_in_group("glow"):
			var m := child.material_override as StandardMaterial3D
			if m and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not m.emission_enabled:
				parts.append(child)
	if parts.size() < 2:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for mi in parts:
		var xf := mi.transform
		var basis_n := xf.basis.inverse().transposed()
		var mat_ := mi.material_override as StandardMaterial3D
		var color := mat_.albedo_color
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var base := verts.size()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var vc = arr[Mesh.ARRAY_COLOR] if mat_.vertex_color_use_as_albedo or mi.has_meta("vertex_colors") else null
			for i in v.size():
				verts.append(xf * v[i])
				normals.append((basis_n * n[i]).normalized())
				colors.append(vc[i] if vc != null and not vc.is_empty() else color)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null or idx.is_empty():
				for i in v.size():
					indices.append(base + i)
			else:
				# Mirrored scales flip triangle winding.
				var flip: bool = xf.basis.determinant() < 0.0
				for i in range(0, idx.size(), 3):
					if flip:
						indices.append_array([base + idx[i], base + idx[i + 2], base + idx[i + 1]])
					else:
						indices.append_array([base + idx[i], base + idx[i + 1], base + idx[i + 2]])
		mi.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _vc_material == null:
		_vc_material = StandardMaterial3D.new()
		_vc_material.vertex_color_use_as_albedo = true
		_vc_material.roughness = 0.9
		_vc_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var merged := MeshInstance3D.new()
	merged.name = "Merged"
	merged.mesh = mesh
	merged.material_override = _vc_material
	node.add_child(merged)
	node.move_child(merged, 0)
