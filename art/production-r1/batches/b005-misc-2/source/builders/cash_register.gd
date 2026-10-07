## Old-fashioned cash register: brass-colored body, sloped key bed with round keys, top display, drawer, crank.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var m: String = p.get("metal", "gold")
	var prof := PackedVector2Array([Vector2(-0.14, 0.0), Vector2(0.16, 0.0), Vector2(0.16, 0.1), Vector2(0.12, 0.2), Vector2(-0.02, 0.27), Vector2(-0.02, 0.36), Vector2(-0.14, 0.36)])
	G.profile_x(b, m, prof, 0.4, 0.02, 0.03)
	b.add_mesh("wood_dark", G.rounded_box(Vector3(0.38, 0.07, 0.03), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.05, 0.16)))
	b.add_mesh(m, G.sphere(0.018, 5), Transform3D(Basis(), Vector3(0, 0.05, 0.18)))
	var a := Vector2(0.12, 0.2)
	var c := Vector2(-0.02, 0.27)
	for i in 5:
		for j in 3:
			var t := (j + 0.5) / 3.0
			var q := a.lerp(c, t)
			b.add_mesh("white" if j != 1 else "cream", G.sphere(0.017, 5), Transform3D(Basis(), Vector3(-0.14 + i * 0.07, q.y + 0.012, q.x)))
	b.add_mesh("cream", G.rounded_box(Vector3(0.26, 0.08, 0.02), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.32, -0.01)))
	G.rod_between(b, m, Vector3(0.2, 0.14, 0.0), Vector3(0.26, 0.14, 0.0), 0.012, 6)
	G.rod_between(b, m, Vector3(0.26, 0.14, 0.0), Vector3(0.26, 0.21, 0.04), 0.012, 6)
	b.add_mesh("wood_dark", G.sphere(0.022, 5), Transform3D(Basis(), Vector3(0.26, 0.22, 0.045)))
	return b
