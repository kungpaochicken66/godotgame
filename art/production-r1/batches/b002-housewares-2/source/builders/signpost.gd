## Wooden signpost with two arrow boards at different angles (no lettering).
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "stone", 0.14, 0.06, 0.02, Transform3D(Basis(), Vector3.ZERO), 18)
	G.rod(b, "wood_dark", 0.045, 0.04, 1.12, Transform3D(Basis(), Vector3(0, 0.03, 0)), 12)
	b.add_mesh("wood_dark", G.sphere(0.05, 6), Transform3D(Basis(), Vector3(0, 1.15, 0)))
	var arrow := PackedVector2Array([Vector2(-0.24, -0.075), Vector2(0.17, -0.075), Vector2(0.26, 0.0), Vector2(0.17, 0.075), Vector2(-0.24, 0.075)])
	var boards := [[0.98, 15.0, "wood", 0.13], [0.78, -25.0, "cream", 0.12]]
	for bd in boards:
		var yaw := deg_to_rad(bd[1])
		var basis := Basis(Vector3.UP, yaw)
		var off: Vector3 = basis * Vector3(bd[3], 0, 0)
		G.bevel_slab(b, bd[2], G.rounded_polygon(arrow, 0.03, 3), 0.045, 0.014, Transform3D(basis, Vector3(0, bd[0], 0) + off))
		b.add_mesh("gold", G.sphere(0.014, 4), Transform3D(basis, Vector3(0, bd[0], 0) + basis * Vector3(0.0, 0, 0.026)))
	return b
