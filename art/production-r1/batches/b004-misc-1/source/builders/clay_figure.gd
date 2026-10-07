## Stylized ancient clay figurine: wide rounded body, short limbs, big goggle eyes and crown band.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("clay", "wood_dark")
	G.pillow(b, c, Vector3(0.26, 0.24, 0.16), 0.6, 0.7, Transform3D(Basis(), Vector3(0, 0.26, 0)), 10, 20)
	for s in [-1.0, 1.0]:
		G.egg(b, c, 0.055, 0.08, 0.05, 0.1, 0.0, Transform3D(Basis(Vector3.BACK, s * 0.2), Vector3(s * 0.07, 0.0, 0)), 8, 12)
		G.egg(b, c, 0.045, 0.065, 0.04, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-125)), Vector3(s * 0.11, 0.33, 0)), 7, 10)
	b.add_mesh(c, G.sphere(0.12, 8), Transform3D(Basis().scaled(Vector3(1.15, 0.9, 0.9)), Vector3(0, 0.45, 0)))
	for s in [-1.0, 1.0]:
		b.add_mesh("stone", G.sphere(0.045, 6), Transform3D(Basis().scaled(Vector3(1.3, 0.8, 0.6)), Vector3(s * 0.055, 0.46, 0.09)))
		b.add_mesh("ink", G.rounded_box(Vector3(0.07, 0.008, 0.012), 0.003, 1), Transform3D(Basis(), Vector3(s * 0.055, 0.46, 0.115)))
	var crown := []
	for k in 12:
		var a := TAU * k / 12.0
		crown.append(Vector3(cos(a) * 0.12, 0.515 + 0.012 * sin(a * 3.0), sin(a) * 0.1))
	G.tube(b, c, crown, 0.02, 2, 6, true)
	for k in 3:
		b.add_mesh("stone", G.sphere(0.015, 4), Transform3D(Basis(), Vector3(-0.05 + k * 0.05, 0.3, 0.075)))
	return b
