## Top-loading washing machine: white rounded body, steel lid, control strip with dial and buttons.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("white", G.rounded_box(Vector3(0.6, 0.86, 0.6), 0.06, 3), Transform3D(Basis(), Vector3(0, 0.45, 0)))
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.56, 0.04, 0.56), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.025, 0)))
	b.add_mesh("steel", G.rounded_box(Vector3(0.46, 0.03, 0.4), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.885, 0.05)))
	b.add_mesh("white", G.rounded_box(Vector3(0.58, 0.14, 0.1), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.94, -0.24)))
	G.puck(b, "steel", 0.04, 0.025, 0.01, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(-0.15, 0.95, -0.19)), 16)
	P.screen(G, b, Vector3(0.05, 0.95, -0.186), 0.12, 0.06)
	for k in 2:
		P.knob(G, b, "blue", Vector3(0.18 + k * 0.06, 0.95, -0.19), 0.014)
	b.add_mesh("blue", G.rounded_box(Vector3(0.2, 0.025, 0.02), 0.008, 1), Transform3D(Basis(), Vector3(0, 0.75, 0.3)))
	return b
