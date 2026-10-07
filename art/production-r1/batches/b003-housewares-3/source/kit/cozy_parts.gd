## Reusable rounded parts built on cozy_geo.gd (cozy-game-modeling skill v2).
## All functions take the kit G and a Builder b; positions are in the asset frame.
extends RefCounted


## Bun foot from the floor (y=0) up to h (bury the top 1-3 cm into the body above).
static func bun_foot(G, b, mat: String, pos: Vector3, r := 0.05, h := 0.09) -> void:
	G.rod(b, mat, r, r * 0.9, h, Transform3D(Basis(), pos), 12, 0.55)


## Squashed ball knob sticking out along +z (or along `facing`).
static func knob(G, b, mat: String, pos: Vector3, r := 0.032, facing := Vector3.BACK) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP if absf(facing.y) < 0.9 else Vector3.BACK)
	b.add_mesh(mat, G.sphere(r, 6), Transform3D(basis.scaled(Vector3(1, 1, 0.75)), pos))


## Rounded drawer/door panel on a front plane at z = front_z, protruding `depth`.
static func panel(G, b, mat: String, center: Vector3, w: float, h: float, depth := 0.04, r := 0.02) -> void:
	b.add_mesh(mat, G.rounded_box(Vector3(w, h, depth + 0.02), r, 2), Transform3D(Basis(), center + Vector3(0, 0, depth * 0.5 - 0.01)))


## Bamboo pole from a to c: rod with slightly swollen node rings every `seg`.
static func bamboo(G, b, a: Vector3, c: Vector3, r: float, seg := 0.22, mat := "bamboo", node_mat := "bamboo_dark") -> void:
	G.rod_between(b, mat, a, c, r, 10)
	var d := c - a
	var n := int(d.length() / seg)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	for k in range(1, n + 1):
		var p := a + y * minf(seg * k, d.length() - r)
		G.puck(b, node_mat, r * 1.13, r * 0.35, r * 0.15, Transform3D(Basis(x, y, x.cross(y)), p - y * r * 0.17), 10)


## Flat glowing screen inset on a front face (emissive "screen" material).
static func screen(G, b, center: Vector3, w: float, h: float, normal := Vector3.BACK) -> void:
	var basis := Basis.looking_at(-normal, Vector3.UP)
	G.bevel_slab(b, "screen", G.rounded_rect(w, h, minf(w, h) * 0.12, 3), 0.02, 0.006, Transform3D(basis, center))


## Balloon: sphere-ish egg with a small knot, origin at the knot.
static func balloon(G, b, mat: String, pos: Vector3, r: float) -> void:
	G.egg(b, mat, r, r * 1.08, r, -0.08, 0.0, Transform3D(Basis(), pos), 8, 12)
	G.rod(b, mat, r * 0.18, r * 0.05, r * 0.2, Transform3D(Basis(Vector3.RIGHT, PI), pos + Vector3(0, r * 0.05, 0)), 8, 0.5)


## Slatted panel: n vertical rounded slats between x0 and x1 (in the plane z = z), y range.
static func slats(G, b, mat: String, x0: float, x1: float, y0: float, y1: float, z: float, n: int, t := 0.035) -> void:
	for k in n:
		var x := lerpf(x0, x1, (k + 0.5) / n)
		b.add_mesh(mat, G.rounded_box(Vector3(t, y1 - y0, t), t * 0.4, 1), Transform3D(Basis(), Vector3(x, (y0 + y1) * 0.5, z)))
