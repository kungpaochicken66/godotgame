## Small woven bamboo basket (lathe body + raised weave rings) holding a green bottle.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var prof: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0), Vector2(0.11, 0), Vector2(0.15, 0.08), Vector2(0.16, 0.2), Vector2(0.15, 0.26), Vector2(0.13, 0.26), Vector2(0.135, 0.2), Vector2(0.12, 0.1), Vector2(0.0, 0.08)]), 3)
	G.lathe(b, "bamboo", prof, 24)
	for y in [0.06, 0.14, 0.22]:
		var ring := []
		var rr: float = 0.135 + (0.022 if y > 0.1 else 0.0)
		for k in 12:
			var a := TAU * k / 12.0
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		G.tube(b, "bamboo_dark", ring, 0.012, 2, 6, true)
	var bottle: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0.06), Vector2(0.06, 0.06), Vector2(0.065, 0.25), Vector2(0.05, 0.3), Vector2(0.025, 0.34), Vector2(0.025, 0.4), Vector2(0.0, 0.405)]), 3)
	G.lathe(b, "teal", bottle, 16, Transform3D(Basis(Vector3.BACK, deg_to_rad(-10)), Vector3(0.02, 0.0, 0)))
	return b
