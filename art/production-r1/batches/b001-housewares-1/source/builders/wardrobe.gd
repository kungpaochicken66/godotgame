## Two-door wardrobe: body, crown, plinth, raised door panels, knobs, bun feet.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood_dark")
	var d: String = p.get("door", "wood")
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 1.42, 0.55), 0.04, 3), Transform3D(Basis(), Vector3(0, 0.8, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(1.08, 0.09, 0.62), 0.035, 2), Transform3D(Basis(), Vector3(0, 1.53, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(1.04, 0.08, 0.59), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.12, 0)))
	for s in [-1.0, 1.0]:
		P.panel(G, b, d, Vector3(s * 0.245, 0.82, 0.275), 0.44, 1.18, 0.025, 0.03)
		P.panel(G, b, w, Vector3(s * 0.245, 1.08, 0.3), 0.3, 0.42, 0.015, 0.03)
		P.panel(G, b, w, Vector3(s * 0.245, 0.55, 0.3), 0.3, 0.42, 0.015, 0.03)
		P.knob(G, b, "gold", Vector3(s * 0.05, 0.82, 0.31), 0.025)
		for z in [-0.2, 0.2]:
			P.bun_foot(G, b, w, Vector3(s * 0.4, 0, z), 0.05, 0.1)
	return b
