## Space suit on a display stand: rounded white suit, helmet with dark visor, backpack, boots.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "charcoal", 0.26, 0.05, 0.02, Transform3D(Basis(), Vector3.ZERO), 24)
	for s in [-1.0, 1.0]:
		b.add_mesh("steel", G.rounded_box(Vector3(0.13, 0.1, 0.2), 0.04, 2), Transform3D(Basis(), Vector3(s * 0.08, 0.1, 0.02)))
		G.rod_between(b, "white", Vector3(s * 0.08, 0.12, 0), Vector3(s * 0.09, 0.5, 0), 0.06, 12)
		G.rod_between(b, "white", Vector3(s * 0.19, 0.86, 0), Vector3(s * 0.25, 0.56, 0.03), 0.05, 12)
		b.add_mesh("steel", G.sphere(0.05, 6), Transform3D(Basis(), Vector3(s * 0.255, 0.53, 0.035)))
	G.pillow(b, "white", Vector3(0.38, 0.46, 0.27), 0.45, 0.5, Transform3D(Basis(), Vector3(0, 0.7, 0)), 10, 24)
	b.add_mesh("white", G.rounded_box(Vector3(0.32, 0.36, 0.14), 0.05, 2), Transform3D(Basis(), Vector3(0, 0.74, -0.16)))
	b.add_mesh("blue", G.rounded_box(Vector3(0.14, 0.1, 0.03), 0.015, 1), Transform3D(Basis(), Vector3(0, 0.76, 0.14)))
	G.puck(b, "steel", 0.12, 0.05, 0.02, Transform3D(Basis(), Vector3(0, 0.92, 0)), 20)
	b.add_mesh("white", G.sphere(0.17, 10), Transform3D(Basis(), Vector3(0, 1.1, 0)))
	G.pillow(b, "ink", Vector3(0.22, 0.15, 0.1), 0.6, 0.6, Transform3D(Basis(), Vector3(0, 1.11, 0.12)), 8, 20)
	return b
