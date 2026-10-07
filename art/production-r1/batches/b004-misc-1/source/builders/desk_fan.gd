## Air circulator fan: round body with ring grille and spokes, hub, stand and base.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("body", "white")
	b.add_mesh(c, G.rounded_box(Vector3(0.28, 0.06, 0.22), 0.025, 2), Transform3D(Basis(), Vector3(0, 0.03, 0)))
	for s in [-1.0, 1.0]:
		G.rod_between(b, c, Vector3(s * 0.12, 0.05, 0), Vector3(s * 0.17, 0.27, 0), 0.02, 8)
	var face := Basis(Vector3.RIGHT, PI / 2)
	G.puck(b, c, 0.17, 0.14, 0.05, Transform3D(face, Vector3(0, 0.29, -0.07)), 28)
	var cy := 0.29
	for r in [0.155, 0.11, 0.065]:
		var ring := []
		for k in 16:
			var a := TAU * k / 16.0
			ring.append(Vector3(cos(a) * r, cy + sin(a) * r, 0.072))
		G.tube(b, c, ring, 0.006, 2, 5, true)
	for k in 8:
		var a := TAU * k / 8.0
		G.rod_between(b, c, Vector3(cos(a) * 0.03, cy + sin(a) * 0.03, 0.072), Vector3(cos(a) * 0.158, cy + sin(a) * 0.158, 0.072), 0.005, 4, 0.5)
	G.puck(b, "steel", 0.035, 0.03, 0.01, Transform3D(face, Vector3(0, cy, 0.065)), 14)
	return b
