## Low light-wood platform bed with a slatted headboard, mattress, quilt and pillow.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	b.add_mesh(w, G.rounded_box(Vector3(1.04, 0.16, 1.84), 0.04, 2), Transform3D(Basis(), Vector3(0, 0.16, 0)))
	for x in [-0.46, 0.46]:
		for z in [-0.84, 0.84]:
			G.rod(b, w, 0.045, 0.045, 0.12, Transform3D(Basis(), Vector3(x, 0, z)), 10)
	b.add_mesh(w, G.rounded_box(Vector3(1.08, 0.08, 0.08), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.82, -0.9)))
	for x in [-0.5, 0.5]:
		G.rod(b, w, 0.04, 0.04, 0.86, Transform3D(Basis(), Vector3(x, 0.08, -0.9)), 10)
	P.slats(G, b, w, -0.46, 0.46, 0.24, 0.8, -0.9, 7, 0.05)
	G.pillow(b, "cream", Vector3(0.96, 0.15, 1.74), 0.35, 0.3, Transform3D(Basis(), Vector3(0, 0.29, 0.02)), 10, 24)
	G.pillow(b, p.get("quilt", "sage"), Vector3(1.0, 0.08, 1.12), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.37, 0.3)), 8, 24)
	G.pillow(b, "white", Vector3(0.56, 0.11, 0.3), 0.55, 0.45, Transform3D(Basis(), Vector3(0, 0.4, -0.6)), 8, 20)
	b.marker("Sleep0", Vector3(0, 0.42, 0))
	return b
