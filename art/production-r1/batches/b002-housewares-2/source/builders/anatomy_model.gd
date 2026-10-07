## Friendly classroom anatomy figure on a stand: cream body, simple colored organs on the torso front.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "charcoal", 0.2, 0.05, 0.02, Transform3D(Basis(), Vector3.ZERO), 24)
	G.rod(b, "steel", 0.018, 0.018, 0.5, Transform3D(Basis(), Vector3(0, 0.04, -0.07)), 8)
	for s in [-1.0, 1.0]:
		G.rod_between(b, "cream", Vector3(s * 0.06, 0.05, 0), Vector3(s * 0.07, 0.48, 0), 0.042)
		G.rod_between(b, "cream", Vector3(s * 0.15, 0.82, 0), Vector3(s * 0.19, 0.52, 0.02), 0.035)
	G.egg(b, "cream", 0.15, 0.2, 0.1, 0.18, 0.0, Transform3D(Basis(), Vector3(0, 0.44, 0)), 10, 16)
	G.rod(b, "cream", 0.045, 0.045, 0.1, Transform3D(Basis(), Vector3(0, 0.8, 0)), 10)
	b.add_mesh("cream", G.sphere(0.13, 8), Transform3D(Basis(), Vector3(0, 0.98, 0)))
	b.add_mesh("pink", G.sphere(0.055, 6), Transform3D(Basis().scaled(Vector3(1, 1.2, 0.6)), Vector3(-0.055, 0.72, 0.07)))
	b.add_mesh("pink", G.sphere(0.055, 6), Transform3D(Basis().scaled(Vector3(1, 1.2, 0.6)), Vector3(0.055, 0.72, 0.07)))
	b.add_mesh("red", G.sphere(0.04, 6), Transform3D(Basis().scaled(Vector3(1, 1, 0.7)), Vector3(0.02, 0.68, 0.09)))
	b.add_mesh("red", G.sphere(0.06, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.6)), Vector3(0, 0.58, 0.075)))
	b.add_mesh("pink", G.sphere(0.05, 6), Transform3D(Basis().scaled(Vector3(1.3, 1, 0.6)), Vector3(0, 0.5, 0.075)))
	return b
