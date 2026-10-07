## Low wooden armchair: slatted back, flat arms, sage cushion.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	for x in [-0.25, 0.25]:
		G.rod(b, w, 0.035, 0.035, 0.6, Transform3D(Basis(), Vector3(x, 0, 0.2)), 10)
		G.rod_between(b, w, Vector3(x, 0, -0.22), Vector3(x, 0.92, -0.3), 0.035)
		b.add_mesh(w, G.rounded_box(Vector3(0.08, 0.04, 0.56), 0.018, 2), Transform3D(Basis(), Vector3(x, 0.6, -0.03)))
	b.add_mesh(w, G.rounded_box(Vector3(0.52, 0.06, 0.48), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.36, -0.01)))
	P.slats(G, b, w, -0.2, 0.2, 0.42, 0.86, -0.27, 5, 0.045)
	b.add_mesh(w, G.rounded_box(Vector3(0.56, 0.06, 0.05), 0.02, 2), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-5)), Vector3(0, 0.87, -0.29)))
	G.pillow(b, p.get("cushion", "sage"), Vector3(0.44, 0.1, 0.42), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.43, 0.0)), 10, 24)
	b.marker("Seat0", Vector3(0, 0.48, 0.02))
	return b
