## Cozy rounded-toy geometry kit for Godot 4.x (GDScript, no addons).
## Distilled from the 2026-10-06 model lab (lab_geo.gd) plus rounded_box from the
## game's mesh_kit.gd. Accumulates triangles per named material and exports one GLB
## (one surface per material) with optional marker nodes (seat, anchor, light...).
## Every triangle is re-wound to agree with its vertex normals, so shapes may be
## parameterized in any direction and still face outward.
extends RefCounted

## Default matte palette. Override per call with Builder.new({"name": Color}).
const PALETTE := {
	"wood": Color("#d9a466"), "wood_dark": Color("#b98352"), "sage": Color("#8fab84"),
	"sage_dark": Color("#7a9670"), "cream": Color("#f3ead8"), "terracotta": Color("#cd8160"),
	"soil": Color("#7a5a45"), "leaf": Color("#7ea56f"), "leaf_light": Color("#93b882"),
	"butter": Color("#efd48c"), "rose": Color("#d98c74"), "ink": Color("#4d3b30"),
	"bulb": Color("#fff1c9"),
}
## Materials that glow slightly (glTF emissive). Keep this list short.
const EMISSIVE := {"bulb": 0.6}


class Builder:
	var surfs := {}
	var markers := {}  # name -> Transform3D (exported as empty nodes)
	var palette := {}
	var _mats := {}

	func _init(extra_palette := {}) -> void:
		palette = PALETTE.duplicate()
		palette.merge(extra_palette, true)

	func _surf(mat: String) -> Dictionary:
		if not surfs.has(mat):
			assert(palette.has(mat), "unknown material " + mat)
			surfs[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
		return surfs[mat]

	## Indexed triangles; each is wound to face along its normals (Godot front = clockwise).
	func add(mat: String, verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array, xf := Transform3D.IDENTITY) -> void:
		var s := _surf(mat)
		var base: int = s.v.size()
		var nb := xf.basis.inverse().transposed()
		for k in verts.size():
			s.v.append(xf * verts[k])
			s.n.append((nb * normals[k]).normalized())
		for t in range(0, idx.size(), 3):
			var a := base + idx[t]
			var b := base + idx[t + 1]
			var c := base + idx[t + 2]
			var cr: Vector3 = (s.v[b] - s.v[a]).cross(s.v[c] - s.v[a])
			if cr.length_squared() < 1e-14:
				continue
			if cr.dot(s.n[a] + s.n[b] + s.n[c]) > 0.0:
				s.i.append_array([a, c, b])
			else:
				s.i.append_array([a, b, c])

	func add_mesh(mat: String, mesh: Mesh, xf := Transform3D.IDENTITY) -> void:
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(arr[Mesh.ARRAY_VERTEX].size()))
			add(mat, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], idx, xf)

	## Uniform scale of everything built so far (vertices and markers), applied ONCE
	## in the builder so the exported asset is final-size (no runtime rescale).
	func scale_all(f: float) -> void:
		for m in surfs:
			var v: PackedVector3Array = surfs[m].v
			for k in v.size():
				v[k] *= f
			surfs[m].v = v
		for k in markers:
			markers[k].origin *= f

	## Moves everything built so far (e.g. center an asymmetric prop's bounds on its
	## origin so support placement by origin cannot overhang).
	func offset_all(d: Vector3) -> void:
		for m in surfs:
			var v: PackedVector3Array = surfs[m].v
			for k in v.size():
				v[k] += d
			surfs[m].v = v
		for k in markers:
			markers[k].origin += d

	func marker(name: String, pos: Vector3, yaw_deg := 0.0) -> void:
		markers[name] = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)

	func tri_count() -> int:
		var n := 0
		for m in surfs:
			n += surfs[m].i.size() / 3
		return n

	func material(name: String) -> StandardMaterial3D:
		if not _mats.has(name):
			var m := StandardMaterial3D.new()
			m.resource_name = name
			m.albedo_color = palette[name]
			m.roughness = 0.9
			m.metallic = 0.0
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			if EMISSIVE.has(name):
				m.emission_enabled = true
				m.emission = palette[name]
				m.emission_energy_multiplier = EMISSIVE[name]
			_mats[name] = m
		return _mats[name]

	func to_mesh(mesh_name: String) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		mesh.resource_name = mesh_name
		var names := surfs.keys()
		names.sort()
		for m in names:
			var s: Dictionary = surfs[m]
			if s.i.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = s.v
			arrays[Mesh.ARRAY_NORMAL] = s.n
			arrays[Mesh.ARRAY_INDEX] = s.i
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var si := mesh.get_surface_count() - 1
			mesh.surface_set_material(si, material(m))
			mesh.surface_set_name(si, m)
		return mesh


## Writes <path> as GLB: root Node3D <name> with one MeshInstance3D and one empty
## Node3D per marker. Returns {"err", "tris"}.
static func export_glb(b: Builder, name: String, path: String, copyright := "") -> Dictionary:
	var root := Node3D.new()
	root.name = name
	var mi := MeshInstance3D.new()
	mi.name = name + "_mesh"
	mi.mesh = b.to_mesh(name)
	root.add_child(mi)
	mi.owner = root
	for m in b.markers:
		var n := Node3D.new()
		n.name = m
		n.transform = b.markers[m]
		root.add_child(n)
		n.owner = root
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	st.copyright = copyright
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	root.free()
	return {"err": err, "tris": b.tri_count()}


# ------------------------------------------------------------------ primitives

## Box with spherical edges and exact normals (from the game's mesh_kit.gd).
## seg 2 is enough for small parts; 3 for large visible bodies.
static func rounded_box(size: Vector3, radius: float, seg := 2) -> ArrayMesh:
	radius = minf(radius, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	var h := size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var coords := func(half: float) -> Array:
		var c := []
		for i in seg + 1:
			c.append(-half + radius * float(i) / seg)
		for i in seg + 1:
			c.append(half - radius + radius * float(i) / seg)
		return c
	var cx: Array = coords.call(h.x)
	var cy: Array = coords.call(h.y)
	var cz: Array = coords.call(h.z)
	for f in [[0, 1, cy, cz], [0, -1, cy, cz], [1, 1, cx, cz], [1, -1, cx, cz], [2, 1, cx, cy], [2, -1, cx, cy]]:
		var ax: int = f[0]
		var ua: Array = f[2]
		var va: Array = f[3]
		var base := verts.size()
		var others := [1, 2] if ax == 0 else ([0, 2] if ax == 1 else [0, 1])
		for i in ua.size():
			for j in va.size():
				var p := Vector3()
				p[ax] = h[ax] * f[1]
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
				indices.append_array([a, a + w, a + w + 1, a, a + w + 1, a + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh  # winding is fixed by Builder.add


static func sphere(radius: float, rings := 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = rings * 2
	m.rings = rings
	return m


## Parametric surface P(u, v) on a (nu+1) x (nv+1) grid with central-difference
## normals, flipped to point away from `center` (fine for convex-ish shapes).
static func param_surface(b: Builder, mat: String, f: Callable, nu: int, nv: int, center: Vector3, xf := Transform3D.IDENTITY) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var e := 1e-3
	for i in nu + 1:
		for j in nv + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			var p: Vector3 = f.call(u, v)
			var uc := clampf(u, 2 * e, 1 - 2 * e)
			var n: Vector3 = (f.call(uc + e, v) - f.call(uc - e, v)).cross(f.call(uc, v + e) - f.call(uc, v - e)).normalized()
			if n.dot(p - center) < 0.0:
				n = -n
			verts.append(p)
			normals.append(n)
	var w := nv + 1
	for i in nu:
		for j in nv:
			var a := i * w + j
			idx.append_array([a, a + w, a + w + 1, a, a + w + 1, a + 1])
	b.add(mat, verts, normals, idx, xf)


## Surface of revolution around +y from a Vector2(r, y) profile. Normals are the
## right-hand side of travel (outward when the profile runs bottom -> top on the
## outside, over a lip and down the inside). Several lathes sharing end points give
## seamless color bands (e.g. pot wall / rim / soil) with no gap.
static func lathe(b: Builder, mat: String, profile: PackedVector2Array, sides: int, xf := Transform3D.IDENTITY) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var n2 := PackedVector2Array()
	for k in profile.size():
		var t := profile[mini(k + 1, profile.size() - 1)] - profile[maxi(k - 1, 0)]
		n2.append(Vector2(t.y, -t.x).normalized())
	for s in sides + 1:
		var a := TAU * s / sides
		for k in profile.size():
			verts.append(Vector3(profile[k].x * cos(a), profile[k].y, profile[k].x * sin(a)))
			normals.append(Vector3(n2[k].x * cos(a), n2[k].y, n2[k].x * sin(a)).normalized())
	var w := profile.size()
	for s in sides:
		for k in w - 1:
			var a := s * w + k
			idx.append_array([a, a + w, a + w + 1, a, a + w + 1, a + 1])
	b.add(mat, verts, normals, idx, xf)


static func arc(center: Vector2, radius: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(k) / steps))
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


## Rounded rod along +y (0..h) with filleted ends: legs, posts, rails, bun feet.
static func rod(b: Builder, mat: String, r_bottom: float, r_top: float, h: float, xf: Transform3D, sides := 12, fillet := 0.6) -> void:
	var fb := r_bottom * fillet
	var ft := r_top * fillet
	var p := PackedVector2Array([Vector2(0, 0)])
	p.append_array(arc(Vector2(r_bottom - fb, fb), fb, -90, 0, 3))
	p.append_array(arc(Vector2(r_top - ft, h - ft), ft, 0, 90, 3))
	p.append(Vector2(0, h))
	lathe(b, mat, p, sides, xf)


## Rod between two points (stretchers, arms, strings).
static func rod_between(b: Builder, mat: String, a: Vector3, c: Vector3, r: float, sides := 10, fillet := 0.5) -> void:
	var d := c - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	rod(b, mat, r, r, d.length(), Transform3D(Basis(x, y, x.cross(y)), a), sides, fillet)


## Disc / puck: flat cylinder with rounded rim, y from 0 to h.
static func puck(b: Builder, mat: String, r: float, h: float, rim: float, xf: Transform3D, sides := 24) -> void:
	var p := PackedVector2Array([Vector2(0, 0)])
	p.append_array(arc(Vector2(r - rim, rim), rim, -90, 0, 3))
	p.append_array(arc(Vector2(r - rim, h - rim), rim, 0, 90, 3))
	p.append(Vector2(0, h))
	lathe(b, mat, p, sides, xf)


## Egg / ellipsoid from its bottom tip: radii (rx, ry, rz), top widened by `taper`,
## optional bend toward +z. Leaves, petals, bird bodies.
static func egg(b: Builder, mat: String, rx: float, ry: float, rz: float, taper: float, bend: float, xf: Transform3D, rings := 8, segs := 14) -> void:
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var y := -cos(th)
		var k := 1.0 + taper * y
		var p := Vector3(sin(th) * cos(ph) * rx * k, (y + 1.0) * ry, sin(th) * sin(ph) * rz * k)
		p.z += bend * pow((y + 1.0) * 0.5, 2.0)
		return p
	param_surface(b, mat, f, rings, segs, Vector3(0, ry, bend * 0.25), xf)


## Superellipsoid pillow centered at origin (cushions, mattresses, blankets).
static func pillow(b: Builder, mat: String, size: Vector3, e1: float, e2: float, xf: Transform3D, nu := 10, nv := 24) -> void:
	var h := size * 0.5
	var sp := func(w: float, m: float) -> float:
		return signf(w) * pow(absf(w), m)
	var f := func(u: float, v: float) -> Vector3:
		var th := lerpf(-PI / 2, PI / 2, u)
		var ph := v * TAU
		var ct: float = sp.call(cos(th), e1)
		return Vector3(h.x * ct * sp.call(cos(ph), e2), h.y * sp.call(sin(th), e1), h.z * ct * sp.call(sin(ph), e2))
	param_surface(b, mat, f, nu, nv, Vector3.ZERO, xf)


## Rounded-edge slab from ONE closed CCW 2D outline (x right, y up), thickness t
## along local z, quarter-round bevel r on both faces. Use it for anything with a
## custom silhouette (scalloped backs, flower heads, clock bodies, slanted cabinet
## sides, curved counters) instead of overlapping several primitives.
static func bevel_slab(b: Builder, mat: String, outline: PackedVector2Array, t: float, r: float, xf: Transform3D, steps := 3) -> void:
	var n := outline.size()
	var on := PackedVector2Array()
	for k in n:
		var d0 := (outline[k] - outline[(k - 1 + n) % n]).normalized()
		var d1 := (outline[(k + 1) % n] - outline[k]).normalized()
		on.append((Vector2(d0.y, -d0.x) + Vector2(d1.y, -d1.x)).normalized())
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var rings := []
	for s in range(steps, -1, -1):
		rings.append([-1.0, s])
	for s in range(0, steps + 1):
		rings.append([1.0, s])
	for ring in rings:
		var side: float = ring[0]
		var a: float = PI / 2 * ring[1] / steps
		var inset := r * (1.0 - cos(a))
		var z := side * ((t * 0.5 - r) + r * sin(a))
		for k in n:
			var p := outline[k] - on[k] * inset
			verts.append(Vector3(p.x, p.y, z))
			normals.append(Vector3(on[k].x * cos(a), on[k].y * cos(a), side * sin(a)).normalized())
	for ri in rings.size() - 1:
		for k in n:
			var a := ri * n + k
			var bb := ri * n + (k + 1) % n
			idx.append_array([a, a + n, bb + n, a, bb + n, bb])
	var inner := PackedVector2Array()
	for k in n:
		inner.append(outline[k] - on[k] * r)
	var tri := Geometry2D.triangulate_polygon(inner)
	if tri.is_empty():
		push_error("bevel_slab: cap triangulation failed (outline self-intersects after inset %.3f)" % r)
	for side in [-1.0, 1.0]:
		var base := verts.size()
		for k in n:
			verts.append(Vector3(inner[k].x, inner[k].y, side * t * 0.5))
			normals.append(Vector3(0, 0, side))
		for q in tri:
			idx.append(base + q)
	b.add(mat, verts, normals, idx, xf)


# ------------------------------------------------------------------ outlines (CCW)

static func smooth_max(vals: Array, k: float) -> float:
	var m: float = vals.max()
	var s := 0.0
	for x in vals:
		s += exp((x - m) * k)
	return m + log(s) / k


static func rounded_rect(w: float, h: float, r: float, steps := 4) -> PackedVector2Array:
	var p := PackedVector2Array()
	var hw := w * 0.5
	var hh := h * 0.5
	p.append_array(arc(Vector2(hw - r, -hh + r), r, -90, 0, steps))
	p.append_array(arc(Vector2(hw - r, hh - r), r, 0, 90, steps))
	p.append_array(arc(Vector2(-hw + r, hh - r), r, 90, 180, steps))
	p.append_array(arc(Vector2(-hw + r, -hh + r), r, 180, 270, steps))
	return p


## Any CCW polygon with every corner filleted (radius clamped to the shorter edge).
## Use for side profiles (slant-front desks, wedges) fed to bevel_slab.
static func rounded_polygon(pts: PackedVector2Array, r: float, steps := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for k in n:
		var p := pts[k]
		var a := (pts[(k - 1 + n) % n] - p)
		var c := (pts[(k + 1) % n] - p)
		var rr := minf(r, minf(a.length(), c.length()) * 0.45)
		var p0 := p + a.normalized() * rr
		var p1 := p + c.normalized() * rr
		for s in steps + 1:
			var t := float(s) / steps
			out.append(p0.lerp(p, t).lerp(p.lerp(p1, t), t))  # quadratic Bezier fillet
	return out


## Panel 0..h tall with `lobes` soft bumps on top blended by smooth max: one
## outline, so no overlapping scallop pieces or seams.
static func scallop_top(w: float, h: float, lobe_h: float, lobes := 3, mid_boost := 0.012) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rc := 0.035
	var hw := w * 0.5
	pts.append_array(arc(Vector2(-hw + rc, rc), rc, 180, 270, 3))
	pts.append_array(arc(Vector2(hw - rc, rc), rc, 270, 360, 3))
	var lr := w / (2.0 * lobes)
	var steps := 10 * lobes
	for s in steps + 1:
		var x := lerpf(hw, -hw, float(s) / steps)
		var vals := []
		for l in lobes:
			var dx := clampf((x - (-hw + lr * (2 * l + 1))) / lr, -1.0, 1.0)
			vals.append(h - lobe_h + lobe_h * sqrt(1.0 - dx * dx) + (mid_boost if l == lobes / 2 else 0.0))
		var edge := clampf((absf(x) - (hw - 0.02)) / 0.02, 0.0, 1.0)
		pts.append(Vector2(x, smooth_max(vals, 70.0) - edge * 0.02))
	return pts


## Radial lobed outline (flower head, cloud, cookie). Center at origin.
static func lobed_circle(r: float, lobes: int, depth: float, steps_per_lobe := 10) -> PackedVector2Array:
	var p := PackedVector2Array()
	var n := lobes * steps_per_lobe
	for k in n:
		var a := TAU * k / n
		var rr := r * (1.0 - depth + depth * pow(absf(cos(a * lobes * 0.5)), 0.6))
		p.append(Vector2(cos(a), sin(a)) * rr)
	return p


## Annular sector in the xy plane (curved counters, arched rails): angles in degrees
## measured from +x, inner/outer radii, rounded ends.
static func annular_sector(r_in: float, r_out: float, a0: float, a1: float, steps := 24) -> PackedVector2Array:
	var p := PackedVector2Array()
	var rc := (r_out - r_in) * 0.5
	var rm := (r_out + r_in) * 0.5
	for k in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(k) / steps))
		p.append(Vector2(cos(a), sin(a)) * r_out)
	var e1 := Vector2(cos(deg_to_rad(a1)), sin(deg_to_rad(a1))) * rm
	p.append_array(arc(e1, rc, a1, a1 + 180, 5).slice(1, 5))
	for k in steps + 1:
		var a := deg_to_rad(lerpf(a1, a0, float(k) / steps))
		p.append(Vector2(cos(a), sin(a)) * r_in)
	var e0 := Vector2(cos(deg_to_rad(a0)), sin(deg_to_rad(a0))) * rm
	p.append_array(arc(e0, rc, a0 + 180, a0 + 360, 5).slice(1, 5))
	return p


# ------------------------------------------------------------------ reuse path

## Loads a GLB and returns its triangles unwelded, node transforms baked:
## [{node, mat, v: PackedVector3Array}] (3 consecutive vertices per triangle).
static func load_triangles(path: String) -> Array:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return []
	var root := doc.generate_scene(st)
	var out := []
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	return out


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D:
		xf = xf * n.transform
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var arr: Array = n.mesh.surface_get_arrays(s)
			var v := PackedVector3Array()
			var src: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in arr[Mesh.ARRAY_INDEX]:
				v.append(xf * src[i])
			var mat: Material = n.mesh.surface_get_material(s)
			out.append({"node": String(n.name), "mat": mat.resource_name if mat else "", "v": v})
	for c in n.get_children():
		_collect(c, xf, out)


## Keeps triangles whose centroid passes keep(centroid, face_normal), applies xf,
## and re-derives normals (smoothing only below `smooth_angle`; use ~30 for boxy
## parts - smoothing across 90-degree box edges makes diagonal creases).
## Returns [kept, dropped]. After cutting: run verify_glb and patch real holes.
static func retain(b: Builder, mat: String, v_src: PackedVector3Array, keep: Callable, xf: Transform3D, smooth_angle := 30.0) -> Array:
	var v := PackedVector3Array()
	var dropped := 0
	for t in range(0, v_src.size(), 3):
		var c := (v_src[t] + v_src[t + 1] + v_src[t + 2]) / 3.0
		var fn := (v_src[t + 2] - v_src[t]).cross(v_src[t + 1] - v_src[t]).normalized()
		if keep.call(c, fn):
			for j in 3:
				v.append(xf * v_src[t + j])
		else:
			dropped += 1
	var idx := PackedInt32Array(range(v.size()))
	b.add(mat, v, smooth_normals(v, idx, smooth_angle), idx)
	return [v.size() / 3, dropped]


static func smooth_normals(verts: PackedVector3Array, idx: PackedInt32Array, max_angle: float) -> PackedVector3Array:
	var fn := []
	var by_pos := {}
	for t in range(0, idx.size(), 3):
		fn.append((verts[idx[t + 2]] - verts[idx[t]]).cross(verts[idx[t + 1]] - verts[idx[t]]))
		for j in 3:
			var key := verts[idx[t + j]].snapped(Vector3.ONE * 1e-4)
			if not by_pos.has(key):
				by_pos[key] = []
			by_pos[key].append(t / 3)
	var out := PackedVector3Array()
	out.resize(verts.size())
	var cos_lim := cos(deg_to_rad(max_angle))
	for t in range(0, idx.size(), 3):
		var own: Vector3 = fn[t / 3].normalized()
		for j in 3:
			var acc := Vector3.ZERO
			for f in by_pos[verts[idx[t + j]].snapped(Vector3.ONE * 1e-4)]:
				if fn[f].normalized().dot(own) >= cos_lim:
					acc += fn[f]
			out[idx[t + j]] = acc.normalized()
	return out
