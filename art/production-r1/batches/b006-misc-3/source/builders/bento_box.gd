## Bamboo lunch basket: woven box with lid propped behind, rice balls, pickled plum, greens, a bamboo cup.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("bamboo", G.rounded_box(Vector3(0.36, 0.1, 0.24), 0.025, 2), Transform3D(Basis(), Vector3(0, 0.05, 0)))
	for z in [-0.12, 0.12]:
		b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.37, 0.015, 0.012), 0.005, 1), Transform3D(Basis(), Vector3(0, 0.07, z)))
	b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.34, 0.02, 0.22), 0.008, 1), Transform3D(Basis(), Vector3(0, 0.1, 0)))
	for k in 2:
		G.egg(b, "white", 0.045, 0.04, 0.035, 0.25, 0.0, Transform3D(Basis(), Vector3(-0.1 + k * 0.08, 0.1, -0.02)), 6, 10)
		b.add_mesh("ink", G.rounded_box(Vector3(0.04, 0.03, 0.01), 0.004, 1), Transform3D(Basis(), Vector3(-0.1 + k * 0.08, 0.13, 0.016)))
	b.add_mesh("red", G.sphere(0.02, 5), Transform3D(Basis(), Vector3(0.06, 0.12, 0.05)))
	for k in 3:
		b.add_mesh("leaf_light", G.sphere(0.03, 5), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0.1 + (k % 2) * 0.03, 0.12, -0.05 + k * 0.03)))
	P.bamboo(G, b, Vector3(0.24, 0.0, -0.05), Vector3(0.24, 0.28, -0.05), 0.04, 0.14)
	G.puck(b, "bamboo_dark", 0.042, 0.01, 0.003, Transform3D(Basis(), Vector3(0.24, 0.28, -0.05)), 12)
	return b
