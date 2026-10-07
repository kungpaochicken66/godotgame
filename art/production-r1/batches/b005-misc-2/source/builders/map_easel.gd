## Old map on a small tabletop easel: parchment sheet with a few faint shapes, rolled ends, wooden easel.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-15))
	var c := Vector3(0, 0.2, 0.0)
	b.add_mesh("paper", G.rounded_box(Vector3(0.34, 0.24, 0.012), 0.004, 1), Transform3D(tilt, c))
	for s in [-1.0, 1.0]:
		G.rod_between(b, "butter", tilt * Vector3(s * 0.17, -0.125, 0.0) + c, tilt * Vector3(s * 0.17, 0.125, 0.0) + c, 0.016, 10)
	var land: PackedVector2Array = G.blob_outline([[-0.05, 0.02, 0.05], [0.03, -0.02, 0.04], [0.07, 0.04, 0.025]], 25.0, 32)
	G.bevel_slab(b, "leaf_light", land, 0.006, 0.002, Transform3D(tilt, c + tilt * Vector3(0, 0, 0.007)))
	b.add_mesh("red", G.sphere(0.01, 4), Transform3D(tilt, c + tilt * Vector3(0.03, 0.0, 0.01)))
	var w := "wood_dark"
	for s in [-1.0, 1.0]:
		G.rod_between(b, w, Vector3(s * 0.12, 0.0, 0.06), Vector3(s * 0.08, 0.34, -0.03), 0.012, 6)
	G.rod_between(b, w, Vector3(0, 0.0, -0.12), Vector3(0, 0.32, -0.03), 0.012, 6)
	G.rod_between(b, w, Vector3(-0.16, 0.07, 0.05), Vector3(0.16, 0.07, 0.05), 0.014, 6)
	return b
