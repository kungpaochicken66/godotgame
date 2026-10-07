## Acoustic guitar leaning in a floor stand. Body = one smooth two-circle outline.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-12))
	var pos := Vector3(0, 0.12, 0.06)
	var gx := Transform3D(tilt, pos)
	var body: PackedVector2Array = G.blob_outline([[0, 0.14, 0.135], [0, 0.35, 0.1]], 28.0, 48)
	G.bevel_slab(b, p.get("body", "wood"), body, 0.09, 0.025, gx)
	G.puck(b, "ink", 0.045, 0.012, 0.004, gx * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.3, 0.04)), 20)
	b.add_mesh("wood_dark", G.rounded_box(Vector3(0.1, 0.022, 0.02), 0.008, 1), gx * Transform3D(Basis(), Vector3(0, 0.12, 0.048)))
	b.add_mesh("wood_dark", G.rounded_box(Vector3(0.05, 0.3, 0.034), 0.012, 2), gx * Transform3D(Basis(), Vector3(0, 0.58, 0)))
	b.add_mesh("wood_dark", G.rounded_box(Vector3(0.075, 0.11, 0.036), 0.015, 2), gx * Transform3D(Basis(), Vector3(0, 0.77, 0)))
	for s in [-1.0, 1.0]:
		for k in 2:
			b.add_mesh("gold", G.sphere(0.012, 4), gx * Transform3D(Basis(), Vector3(s * 0.045, 0.74 + k * 0.05, 0)))
	var neck_back: Vector3 = gx * Vector3(0, 0.56, -0.03)
	G.rod_between(b, "charcoal", Vector3(0, 0, -0.2), neck_back, 0.016)
	for s in [-1.0, 1.0]:
		G.rod_between(b, "charcoal", Vector3(s * 0.15, 0, 0.14), Vector3(s * 0.11, 0.15, 0.08), 0.016)
		G.rod_between(b, "charcoal", Vector3(s * 0.15, 0.012, 0.14), Vector3(0, 0.012, -0.2), 0.014)
	G.rod_between(b, "charcoal", Vector3(-0.13, 0.14, 0.085), Vector3(0.13, 0.14, 0.085), 0.018)
	return b
