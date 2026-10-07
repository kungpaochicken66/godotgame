## Garden pavilion: stone platform, four posts, two inner benches, square hipped roof (4-sided lathe) with finial.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new({"straw": Color("#c9a86a"), "straw_dark": Color("#a88a52")})
	var half := 0.95
	b.add_mesh("stone", G.rounded_box(Vector3(2.3, 0.12, 2.3), 0.04, 2), Transform3D(Basis(), Vector3(0, 0.06, 0)))
	for x in [-half, half]:
		for z in [-half, half]:
			G.rod(b, "wood_dark", 0.07, 0.07, 1.86, Transform3D(Basis(), Vector3(x, 0.1, z)), 12)
	for x in [-half, half]:
		G.rod_between(b, "wood_dark", Vector3(x, 1.86, -half), Vector3(x, 1.86, half), 0.06, 10)
		G.rod_between(b, "wood_dark", Vector3(-half, 1.86, x), Vector3(half, 1.86, x), 0.06, 10)
	for z in [-0.72, 0.72]:
		b.add_mesh("wood", G.rounded_box(Vector3(1.5, 0.06, 0.32), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.46, z)))
		for x in [-0.6, 0.6]:
			G.rod(b, "wood", 0.04, 0.04, 0.36, Transform3D(Basis(), Vector3(x, 0.1, z)), 8)
	var roof := PackedVector2Array([Vector2(0.0, 1.86), Vector2(1.95, 1.82), Vector2(1.98, 1.9), Vector2(0.2, 2.62), Vector2(0.0, 2.66)])
	G.lathe(b, "straw", roof, 4, Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO))
	G.puck(b, "straw_dark", 0.16, 0.1, 0.04, Transform3D(Basis(), Vector3(0, 2.6, 0)), 12)
	b.add_mesh("wood_dark", G.sphere(0.07, 6), Transform3D(Basis(), Vector3(0, 2.74, 0)))
	return b
