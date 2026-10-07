## Backlit box sign on a small stand: dark box with a glowing face panel (no lettering).
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.42, 0.26, 0.14), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.17, 0)))
	G.bevel_slab(b, p.get("glow", "red"), G.rounded_rect(0.36, 0.2, 0.03, 3), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0.17, 0.07)))
	for k in 3:
		b.add_mesh("bulb", G.rounded_box(Vector3(0.07, 0.03, 0.01), 0.008, 1), Transform3D(Basis(), Vector3(-0.1 + k * 0.1, 0.17, 0.082)))
	for x in [-0.15, 0.15]:
		b.add_mesh("charcoal", G.rounded_box(Vector3(0.05, 0.05, 0.16), 0.015, 1), Transform3D(Basis(), Vector3(x, 0.025, 0)))
	b.marker("Light0", Vector3(0, 0.17, 0.09))
	return b
