## Baby crib: four rounded posts, slatted sides on all four faces, mattress and small pillow.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	var hx := 0.3
	var hz := 0.44
	for x in [-hx, hx]:
		for z in [-hz, hz]:
			G.rod(b, w, 0.035, 0.035, 0.84, Transform3D(Basis(), Vector3(x, 0, z)), 10)
			b.add_mesh(w, G.sphere(0.045, 6), Transform3D(Basis(), Vector3(x, 0.85, z)))
	for y in [0.2, 0.8]:
		for x in [-hx, hx]:
			G.rod_between(b, w, Vector3(x, y, -hz), Vector3(x, y, hz), 0.022, 8)
		for z in [-hz, hz]:
			G.rod_between(b, w, Vector3(-hx, y, z), Vector3(hx, y, z), 0.022, 8)
	for z in [-hz, hz]:
		P.slats(G, b, w, -hx + 0.04, hx - 0.04, 0.2, 0.8, z, 5, 0.022)
	for x in [-hx, hx]:
		for k in 7:
			var z := lerpf(-hz + 0.05, hz - 0.05, (k + 0.5) / 7.0)
			b.add_mesh(w, G.rounded_box(Vector3(0.022, 0.6, 0.022), 0.008, 1), Transform3D(Basis(), Vector3(x, 0.5, z)))
	b.add_mesh(w, G.rounded_box(Vector3(0.58, 0.04, 0.86), 0.015, 2), Transform3D(Basis(), Vector3(0, 0.22, 0)))
	G.pillow(b, "white", Vector3(0.54, 0.1, 0.82), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.28, 0)), 8, 20)
	G.pillow(b, "pink", Vector3(0.3, 0.07, 0.18), 0.5, 0.45, Transform3D(Basis(), Vector3(0, 0.35, -0.3)), 8, 16)
	return b
