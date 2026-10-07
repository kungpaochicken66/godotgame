## Oval-top table on two sculpted arch legs (swept tubes). Flat top = ONE support slot.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var top_y := 0.66
	var oval := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		oval.append(Vector2(cos(a) * 0.56, sin(a) * 0.29))
	G.plan_slab(b, p.get("top", "blue"), oval, top_y - 0.05, 0.05, 0.02)
	for s in [-1.0, 1.0]:
		G.tube(b, p.get("legs", "red"), [Vector3(s * 0.4, 0.045, -0.18), Vector3(s * 0.32, 0.3, -0.12), Vector3(s * 0.28, top_y - 0.04, 0.0), Vector3(s * 0.32, 0.3, 0.12), Vector3(s * 0.4, 0.045, 0.18)], 0.035, 4, 10)
		for z in [-0.18, 0.18]:
			b.add_mesh(p.get("legs", "red"), G.sphere(0.045, 6), Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), Vector3(s * 0.4, 0.0226, z)))
	b.marker("Support0", Vector3(0, top_y, 0))
	return b
