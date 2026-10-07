## Sitting plush bear (or panda by colors): round body, head, ears, muzzle, limbs, eyes.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("fur", "wood")
	var c2: String = p.get("accent", c)
	var m: String = p.get("muzzle", "cream")
	G.egg(b, c, 0.12, 0.12, 0.1, -0.1, 0.0, Transform3D(Basis(), Vector3(0, 0.0, 0)), 8, 14)
	b.add_mesh(c, G.sphere(0.11, 8), Transform3D(Basis(), Vector3(0, 0.31, 0.01)))
	for s in [-1.0, 1.0]:
		b.add_mesh(c2, G.sphere(0.04, 6), Transform3D(Basis().scaled(Vector3(1, 1, 0.6)), Vector3(s * 0.08, 0.4, 0.0)))
		G.egg(b, c2, 0.04, 0.06, 0.04, 0.0, 0.0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(80)), Vector3(s * 0.07, 0.04, -0.01)), 6, 10)
		G.egg(b, c2, 0.035, 0.07, 0.035, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-30)), Vector3(s * 0.1, 0.12, 0.03)), 6, 10)
		if p.get("patches", false):
			b.add_mesh(c2, G.sphere(0.03, 5), Transform3D(Basis().scaled(Vector3(1, 1.2, 0.5)), Vector3(s * 0.04, 0.33, 0.1)))
		b.add_mesh("ink", G.sphere(0.012, 4), Transform3D(Basis(), Vector3(s * 0.04, 0.33, 0.115)))
	b.add_mesh(m, G.sphere(0.045, 6), Transform3D(Basis().scaled(Vector3(1, 0.8, 0.7)), Vector3(0, 0.28, 0.1)))
	b.add_mesh("ink", G.sphere(0.014, 4), Transform3D(Basis(), Vector3(0, 0.295, 0.13)))
	if p.has("ribbon"):
		b.add_mesh(p["ribbon"], G.sphere(0.03, 5), Transform3D(Basis().scaled(Vector3(1.5, 0.8, 0.6)), Vector3(0, 0.21, 0.08)))
	return b
