## Practice amplifier: dark cabinet, grille, control strip with knobs, top handle.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.52, 0.46, 0.3), 0.05, 3), Transform3D(Basis(), Vector3(0, 0.255, 0)))
	G.bevel_slab(b, "ink", G.rounded_rect(0.44, 0.27, 0.04, 3), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0.2, 0.15)))
	b.add_mesh("stone", G.rounded_box(Vector3(0.44, 0.06, 0.02), 0.008, 1), Transform3D(Basis(), Vector3(0, 0.405, 0.152)))
	for k in 4:
		P.knob(G, b, "gold", Vector3(-0.15 + k * 0.1, 0.405, 0.165), 0.017)
	for s in [-1.0, 1.0]:
		G.rod_between(b, "ink", Vector3(s * 0.13, 0.47, 0), Vector3(s * 0.13, 0.5, 0), 0.018)
	G.rod_between(b, "ink", Vector3(-0.14, 0.5, 0), Vector3(0.14, 0.5, 0), 0.02)
	for x in [-0.2, 0.2]:
		for z in [-0.1, 0.1]:
			P.bun_foot(G, b, "ink", Vector3(x, 0, z), 0.025, 0.04)
	return b
