## Aluminum briefcase standing on its edge: ridged shell, latches and a top handle.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("steel", G.rounded_box(Vector3(0.5, 0.36, 0.14), 0.03, 3), Transform3D(Basis(), Vector3(0, 0.18, 0)))
	for z in [-0.072, 0.072]:
		for y in [0.1, 0.18, 0.26]:
			b.add_mesh("white", G.rounded_box(Vector3(0.44, 0.012, 0.01), 0.004, 1), Transform3D(Basis(), Vector3(0, y, z)))
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.5, 0.36, 0.012), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.18, 0)))
	for x in [-0.15, 0.15]:
		b.add_mesh("charcoal", G.rounded_box(Vector3(0.04, 0.03, 0.15), 0.01, 1), Transform3D(Basis(), Vector3(x, 0.355, 0)))
	G.tube(b, "charcoal", [Vector3(-0.07, 0.355, 0), Vector3(-0.06, 0.4, 0), Vector3(0.06, 0.4, 0), Vector3(0.07, 0.355, 0)], 0.014, 3, 8)
	return b
