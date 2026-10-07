## Analog kitchen scale: rounded body with a round dial face and needle, a bowl on top.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("body", "red")
	b.add_mesh(c, G.rounded_box(Vector3(0.26, 0.2, 0.22), 0.06, 3), Transform3D(Basis(), Vector3(0, 0.11, 0)))
	b.add_mesh(c, G.rounded_box(Vector3(0.28, 0.03, 0.24), 0.012, 2), Transform3D(Basis(), Vector3(0, 0.015, 0)))
	var face := Basis(Vector3.RIGHT, PI / 2)
	G.puck(b, "white", 0.085, 0.02, 0.008, Transform3D(face, Vector3(0, 0.12, 0.1)), 24)
	for k in 8:
		var a := TAU * k / 8.0
		b.add_mesh("ink", G.rounded_box(Vector3(0.006, 0.018, 0.006), 0.002, 1), Transform3D(Basis(Vector3.BACK, -a), Vector3(sin(a) * 0.065, 0.12 + cos(a) * 0.065, 0.122)))
	b.add_mesh("red", G.rounded_box(Vector3(0.008, 0.06, 0.008), 0.003, 1), Transform3D(Basis(Vector3.BACK, -0.6), Vector3(0.016, 0.145, 0.124)))
	G.rod(b, "steel", 0.025, 0.025, 0.04, Transform3D(Basis(), Vector3(0, 0.2, 0)), 10)
	var bowl := PackedVector2Array([Vector2(0, 0.23), Vector2(0.07, 0.23), Vector2(0.15, 0.27), Vector2(0.165, 0.3), Vector2(0.155, 0.302), Vector2(0.14, 0.28), Vector2(0.0, 0.245)])
	G.lathe(b, "steel", bowl, 28)
	return b
