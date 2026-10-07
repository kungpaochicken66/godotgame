## Rocking ram seat: two curved rockers, woolly body with bumps, head with curled horns, seat cushion.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	for s in [-1.0, 1.0]:
		var arc := []
		for k in 7:
			var a := deg_to_rad(-120.0 + 60.0 * k / 6.0)
			arc.append(Vector3(s * 0.17, 1.0 + sin(a) * 1.0 + 0.035, cos(a) * 1.0))
		G.tube(b, "gold", arc, 0.035, 3, 10)
		G.rod_between(b, "gold", Vector3(s * 0.17, 0.05, 0.0), Vector3(s * 0.12, 0.3, 0.0), 0.03)
	G.rod_between(b, "gold", Vector3(-0.17, 0.12, 0.3), Vector3(0.17, 0.12, 0.3), 0.022)
	G.rod_between(b, "gold", Vector3(-0.17, 0.12, -0.3), Vector3(0.17, 0.12, -0.3), 0.022)
	G.egg(b, "white", 0.2, 0.3, 0.19, 0.0, 0.0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.42, -0.3)), 10, 16)
	for k in 9:
		var a := TAU * k / 9.0
		b.add_mesh("white", G.sphere(0.075, 6), Transform3D(Basis(), Vector3(cos(a) * 0.17, 0.44 + sin(a) * 0.12, 0.05 - (k % 3) * 0.15)))
	G.pillow(b, "pink", Vector3(0.24, 0.07, 0.28), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.6, -0.04)), 8, 20)
	G.egg(b, "cream", 0.1, 0.12, 0.11, -0.1, 0.0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(70)), Vector3(0, 0.56, 0.22)), 8, 14)
	b.add_mesh("white", G.sphere(0.1, 6), Transform3D(Basis(), Vector3(0, 0.66, 0.2)))
	for s in [-1.0, 1.0]:
		var horn := []
		for k in 8:
			var a := deg_to_rad(90.0 - 300.0 * k / 7.0)
			var rr := 0.075 * (1.0 - 0.07 * k)
			horn.append(Vector3(s * (0.075 + 0.03 * k / 7.0), 0.66 + sin(a) * rr, 0.17 + cos(a) * rr))
		G.tube(b, "gold", horn, 0.026, 3, 8)
		b.add_mesh("ink", G.sphere(0.014, 4), Transform3D(Basis(), Vector3(s * 0.045, 0.68, 0.29)))
	b.marker("Seat0", Vector3(0, 0.64, -0.04))
	return b
