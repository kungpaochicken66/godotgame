## Baseball set: glove (one rounded mitt with a thumb lobe) holding a ball, bat leaning on it.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var mitt: PackedVector2Array = G.blob_outline([[0.0, 0.0, 0.1], [0.0, 0.08, 0.085], [-0.1, 0.02, 0.05]], 18.0, 40)
	G.bevel_slab(b, "wood", mitt, 0.07, 0.025, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60)), Vector3(0.0, 0.1, -0.02)))
	b.add_mesh("white", G.sphere(0.05, 8), Transform3D(Basis(), Vector3(0.0, 0.14, 0.04)))
	G.tube(b, "red", [Vector3(-0.035, 0.15, 0.08), Vector3(0.0, 0.18, 0.088), Vector3(0.035, 0.15, 0.08)], 0.005, 2, 5)
	var bat: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0), Vector2(0.025, 0.0), Vector2(0.02, 0.02), Vector2(0.016, 0.2), Vector2(0.03, 0.38), Vector2(0.034, 0.48), Vector2(0.02, 0.5), Vector2(0.0, 0.5)]), 3)
	G.lathe(b, "red", bat, 14, Transform3D(Basis(Vector3.BACK, deg_to_rad(52)), Vector3(0.36, 0.02, -0.05)))
	return b
