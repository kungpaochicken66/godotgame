## Three-tier afternoon tea stand: plates on a central rod with a ring handle, tiny cakes and sandwiches.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.rod(b, "gold", 0.012, 0.012, 0.5, Transform3D(Basis(), Vector3(0, 0.0, 0)), 8)
	G.puck(b, "gold", 0.07, 0.02, 0.008, Transform3D(Basis(), Vector3.ZERO), 16)
	var tiers := [[0.03, 0.16], [0.2, 0.13], [0.36, 0.1]]
	for t in tiers:
		G.puck(b, "white", t[1], 0.018, 0.007, Transform3D(Basis(), Vector3(0, t[0], 0)), 24)
	var ring := []
	for k in 10:
		var a := TAU * k / 10.0
		ring.append(Vector3(sin(a) * 0.035, 0.53 + cos(a) * 0.035, 0))
	G.tube(b, "gold", ring, 0.008, 2, 6, true)
	var cakes := ["pink", "butter", "red", "pink", "butter"]
	for k in 5:
		var a := TAU * k / 5.0
		b.add_mesh(cakes[k], G.rounded_box(Vector3(0.05, 0.035, 0.05), 0.012, 1), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.1, 0.066, sin(a) * 0.1)))
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		G.egg(b, "wood", 0.025, 0.03, 0.025, 0.0, 0.0, Transform3D(Basis(), Vector3(cos(a) * 0.075, 0.215, sin(a) * 0.075)), 5, 8)
		b.add_mesh("white", G.sphere(0.012, 4), Transform3D(Basis(), Vector3(cos(a) * 0.075, 0.27, sin(a) * 0.075)))
	for k in 3:
		var a := TAU * k / 3.0
		b.add_mesh("red", G.sphere(0.022, 5), Transform3D(Basis(), Vector3(cos(a) * 0.05, 0.395, sin(a) * 0.05)))
	return b
