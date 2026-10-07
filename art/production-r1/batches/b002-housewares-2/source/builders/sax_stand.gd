## Saxophone on a tripod stand: swept gold body tube (J-bend), flared lathe bell, neck + mouthpiece, key buttons.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var gold: String = p.get("metal", "gold")
	var body := [Vector3(0.0, 0.74, 0.0), Vector3(0.0, 0.6, 0.0), Vector3(0.0, 0.38, 0.0), Vector3(0.025, 0.26, 0.0), Vector3(0.09, 0.22, 0.0), Vector3(0.14, 0.27, 0.0), Vector3(0.15, 0.36, 0.0)]
	G.tube(b, gold, body, 0.038, 4, 12)
	var bell := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.045, 0.06), Vector2(0.07, 0.13), Vector2(0.095, 0.16), Vector2(0.085, 0.165), Vector2(0.06, 0.135), Vector2(0.0, 0.12)])
	G.lathe(b, gold, G.smooth_path(bell, 3), 20, Transform3D(Basis(Vector3.BACK, deg_to_rad(-12)), Vector3(0.152, 0.33, 0)))
	G.tube(b, gold, [Vector3(0.0, 0.72, 0.0), Vector3(-0.01, 0.8, 0.0), Vector3(-0.05, 0.84, 0.0), Vector3(-0.1, 0.83, 0.0)], 0.018, 4, 10)
	G.rod_between(b, "ink", Vector3(-0.095, 0.832, 0.0), Vector3(-0.15, 0.82, 0.0), 0.016, 8, 0.8)
	for k in 5:
		b.add_mesh("white", G.sphere(0.014, 4), Transform3D(Basis(), Vector3(0.0, 0.66 - k * 0.07, 0.036)))
	G.rod_between(b, "charcoal", Vector3(0.0, 0.06, -0.06), Vector3(0.0, 0.62, -0.03), 0.014)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		G.rod_between(b, "charcoal", Vector3(0.0, 0.08, -0.06), Vector3(cos(a) * 0.18, 0.0, -0.06 + sin(a) * 0.18), 0.013)
	G.rod_between(b, "charcoal", Vector3(0.0, 0.3, -0.05), Vector3(0.0, 0.3, -0.02), 0.014)
	return b
