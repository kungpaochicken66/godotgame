## Wooden insect house: slatted box with a solid roof, carry handle and a leaf inside.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	b.add_mesh(w, G.rounded_box(Vector3(0.96, 0.08, 0.52), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.06, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.08, 0.56), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.6, 0)))
	for x in [-0.46, 0.46]:
		for z in [-0.24, 0.24]:
			G.rod(b, w, 0.025, 0.025, 0.58, Transform3D(Basis(), Vector3(x, 0.03, z)), 8)
	P.slats(G, b, w, -0.44, 0.44, 0.1, 0.56, 0.245, 11, 0.022)
	P.slats(G, b, w, -0.44, 0.44, 0.1, 0.56, -0.245, 11, 0.022)
	for x in [-0.46, 0.46]:
		for k in 5:
			var z := lerpf(-0.2, 0.2, (k + 0.5) / 5.0)
			b.add_mesh(w, G.rounded_box(Vector3(0.022, 0.46, 0.022), 0.008, 1), Transform3D(Basis(), Vector3(x, 0.33, z)))
	G.tube(b, "wood_dark", [Vector3(-0.2, 0.63, 0), Vector3(-0.17, 0.75, 0), Vector3(0, 0.79, 0), Vector3(0.17, 0.75, 0), Vector3(0.2, 0.63, 0)], 0.02, 4, 8)
	G.egg(b, "leaf", 0.08, 0.13, 0.025, 0.2, 0.03, Transform3D(Basis(Vector3.BACK, deg_to_rad(20)), Vector3(-0.1, 0.09, 0)), 6, 10)
	return b
