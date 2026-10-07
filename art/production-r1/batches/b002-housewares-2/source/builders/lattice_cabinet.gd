## Low lattice cabinet: open top shelf, two doors with vertical lattice slats, short legs.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.04, 0.42), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.84, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.04, 0.42), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.56, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.04, 0.42), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.1, 0)))
	for x in [-0.48, 0.48]:
		b.add_mesh(w, G.rounded_box(Vector3(0.04, 0.8, 0.42), 0.015, 2), Transform3D(Basis(), Vector3(x, 0.46, 0)))
		for z in [-0.17, 0.17]:
			G.rod(b, w, 0.03, 0.03, 0.1, Transform3D(Basis(), Vector3(x * 0.92, 0, z)), 8)
	b.add_mesh(w, G.rounded_box(Vector3(0.96, 0.76, 0.03), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.47, -0.195)))
	for s in [-1.0, 1.0]:
		var x0: float = s * 0.235
		b.add_mesh("paper", G.rounded_box(Vector3(0.44, 0.42, 0.02), 0.008, 1), Transform3D(Basis(), Vector3(x0, 0.33, 0.19)))
		P.slats(G, b, w, x0 - 0.2, x0 + 0.2, 0.12, 0.54, 0.205, 5, 0.025)
		for y in [0.13, 0.33, 0.53]:
			b.add_mesh(w, G.rounded_box(Vector3(0.44, 0.025, 0.03), 0.008, 1), Transform3D(Basis(), Vector3(x0, y, 0.205)))
		P.knob(G, b, "charcoal", Vector3(s * 0.03, 0.33, 0.225), 0.018)
	return b
