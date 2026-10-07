## Generic cash machine (ATM-like): steel body, dark fascia, glowing screen, keypad shelf, sign.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.6, 0.06, 0.46), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.03, 0)))
	b.add_mesh("steel", G.rounded_box(Vector3(0.62, 1.06, 0.48), 0.05, 3), Transform3D(Basis(), Vector3(0, 0.58, 0)))
	b.add_mesh(p.get("accent", "blue"), G.rounded_box(Vector3(0.64, 0.16, 0.5), 0.05, 2), Transform3D(Basis(), Vector3(0, 1.12, 0)))
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.5, 0.5, 0.06), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.8, 0.23)))
	P.screen(G, b, Vector3(0, 0.86, 0.262), 0.36, 0.24)
	b.add_mesh("steel", G.rounded_box(Vector3(0.44, 0.05, 0.16), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.58, 0.29)))
	for i in 3:
		for j in 3:
			b.add_mesh("white", G.rounded_box(Vector3(0.05, 0.024, 0.035), 0.008, 1), Transform3D(Basis(), Vector3(-0.07 + i * 0.07, 0.612, 0.24 + j * 0.045)))
	b.add_mesh("ink", G.rounded_box(Vector3(0.12, 0.025, 0.03), 0.008, 1), Transform3D(Basis(), Vector3(0.14, 0.66, 0.262)))
	return b
