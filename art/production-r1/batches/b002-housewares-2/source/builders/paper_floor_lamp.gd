## Floor lamp: tall square paper shade in a wood frame on a round base; bulb inside (Light0).
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	G.puck(b, "charcoal", 0.15, 0.04, 0.015, Transform3D(Basis(), Vector3.ZERO), 22)
	G.rod(b, w, 0.025, 0.025, 0.66, Transform3D(Basis(), Vector3(0, 0.03, 0)), 10)
	b.add_mesh("paper", G.rounded_box(Vector3(0.24, 0.62, 0.24), 0.03, 2), Transform3D(Basis(), Vector3(0, 1.0, 0)))
	for x in [-0.125, 0.125]:
		for z in [-0.125, 0.125]:
			G.rod(b, w, 0.016, 0.016, 0.7, Transform3D(Basis(), Vector3(x, 0.66, z)), 8)
	for y in [0.69, 1.33]:
		b.add_mesh(w, G.rounded_box(Vector3(0.28, 0.035, 0.28), 0.012, 1), Transform3D(Basis(), Vector3(0, y, 0)))
	b.add_mesh("bulb", G.sphere(0.06, 6), Transform3D(Basis(), Vector3(0, 1.0, 0)))
	b.marker("Light0", Vector3(0, 1.0, 0))
	return b
