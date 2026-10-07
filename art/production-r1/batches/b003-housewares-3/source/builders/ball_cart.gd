## Wheeled ball cart: tube frame box with wire bars, a heap of balls, four wheels.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var fr: String = p.get("frame", "leaf")
	var hx := 0.48
	var hz := 0.27
	var y0 := 0.12
	var y1 := 0.72
	for y in [y0, y1]:
		G.tube(b, fr, [Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)], 0.02, 1, 8, true)
	for x in [-hx, hx]:
		for z in [-hz, hz]:
			G.rod_between(b, fr, Vector3(x, y0, z), Vector3(x, y1, z), 0.02, 8)
			G.puck(b, "charcoal", 0.05, 0.04, 0.015, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(x + 0.02, 0.05, z)), 14)
			G.rod_between(b, "charcoal", Vector3(x, 0.05, z), Vector3(x, y0, z), 0.012, 6)
	for k in 7:
		var x := lerpf(-hx, hx, (k + 1) / 8.0)
		for z in [-hz, hz]:
			G.rod_between(b, fr, Vector3(x, y0, z), Vector3(x, y1, z), 0.008, 6, 0.5)
	for k in 3:
		var z := lerpf(-hz, hz, (k + 1) / 4.0)
		for x in [-hx, hx]:
			G.rod_between(b, fr, Vector3(x, y0, z), Vector3(x, y1, z), 0.008, 6, 0.5)
		G.rod_between(b, fr, Vector3(-hx, y0, z), Vector3(hx, y0, z), 0.01, 6, 0.5)
	var balls := [Vector3(-0.3, 0.24, -0.1), Vector3(-0.1, 0.24, 0.1), Vector3(0.12, 0.24, -0.08), Vector3(0.32, 0.24, 0.1), Vector3(-0.2, 0.43, 0.05), Vector3(0.02, 0.44, 0.0), Vector3(0.22, 0.42, -0.02), Vector3(-0.05, 0.6, 0.02)]
	for q in balls:
		b.add_mesh(p.get("ball", "terracotta"), G.sphere(0.12, 7), Transform3D(Basis(), q))
	return b
