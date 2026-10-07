## Ant farm: green frame holding a thin soil slab with tunnel chambers, on a base.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var fr: String = p.get("frame", "leaf")
	b.add_mesh(fr, G.rounded_box(Vector3(0.36, 0.06, 0.14), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.03, 0)))
	for x in [-0.165, 0.165]:
		b.add_mesh(fr, G.rounded_box(Vector3(0.04, 0.44, 0.08), 0.015, 2), Transform3D(Basis(), Vector3(x, 0.27, 0)))
	b.add_mesh(fr, G.rounded_box(Vector3(0.37, 0.04, 0.08), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.48, 0)))
	b.add_mesh("wood", G.rounded_box(Vector3(0.3, 0.4, 0.04), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.26, 0)))
	b.add_mesh("soil", G.rounded_box(Vector3(0.3, 0.26, 0.046), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.19, 0)))
	var tunnels := [[Vector3(-0.08, 0.3, 0.024), Vector3(-0.05, 0.22, 0.024), Vector3(0.02, 0.18, 0.024), Vector3(0.08, 0.1, 0.024)], [Vector3(0.06, 0.3, 0.024), Vector3(0.05, 0.24, 0.024), Vector3(0.0, 0.2, 0.024)]]
	for t in tunnels:
		G.tube(b, "wood", t, 0.012, 3, 6)
	for q in [Vector3(-0.05, 0.22, 0.025), Vector3(0.08, 0.1, 0.025), Vector3(0.0, 0.18, 0.025)]:
		b.add_mesh("wood", G.sphere(0.025, 5), Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.4)), q))
	return b
