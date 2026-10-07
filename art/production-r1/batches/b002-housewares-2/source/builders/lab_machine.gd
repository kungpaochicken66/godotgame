## Whimsical lab machine: steel cabinet, upper unit with screen, dial pucks, lamps, swept pipes.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("steel", G.rounded_box(Vector3(1.1, 0.66, 0.5), 0.05, 3), Transform3D(Basis(), Vector3(0, 0.36, 0)))
	b.add_mesh("charcoal", G.rounded_box(Vector3(1.06, 0.05, 0.46), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.025, 0)))
	b.add_mesh("white", G.rounded_box(Vector3(0.56, 0.38, 0.4), 0.05, 2), Transform3D(Basis(), Vector3(-0.2, 0.86, -0.02)))
	P.screen(G, b, Vector3(-0.2, 0.88, 0.185), 0.36, 0.22)
	for k in 3:
		G.puck(b, "charcoal", 0.05, 0.03, 0.01, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.1 + k * 0.14, 0.5, 0.245)), 16)
		b.add_mesh("gold", G.rounded_box(Vector3(0.012, 0.04, 0.012), 0.004, 1), Transform3D(Basis(), Vector3(0.1 + k * 0.14, 0.51, 0.28)))
	for k in 4:
		P.panel(G, b, "white", Vector3(-0.38 + k * 0.12, 0.24, 0.25), 0.09, 0.09, 0.02, 0.015)
	G.tube(b, "white", [Vector3(0.08, 0.86, 0.0), Vector3(0.22, 0.9, 0.0), Vector3(0.32, 0.8, 0.05), Vector3(0.36, 0.69, 0.08)], 0.035, 4, 10)
	G.tube(b, "gold", [Vector3(0.48, 0.69, -0.1), Vector3(0.5, 0.9, -0.1), Vector3(0.42, 1.0, -0.12), Vector3(0.1, 1.0, -0.12), Vector3(0.02, 0.98, -0.12)], 0.025, 4, 10)
	for k in 2:
		G.rod(b, "charcoal", 0.03, 0.03, 0.06, Transform3D(Basis(), Vector3(-0.38 + k * 0.36, 1.04, -0.02)), 10)
		b.add_mesh("bulb", G.sphere(0.045, 6), Transform3D(Basis(), Vector3(-0.38 + k * 0.36, 1.12, -0.02)))
	return b
