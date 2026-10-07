## Anchor statue on a round stone plinth: shank, ring, stock, curved arms with flukes (swept tubes).
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var m: String = p.get("metal", "charcoal")
	G.puck(b, "stone", 0.27, 0.12, 0.03, Transform3D(Basis(), Vector3.ZERO), 28)
	G.puck(b, "stone", 0.21, 0.06, 0.02, Transform3D(Basis(), Vector3(0, 0.11, 0)), 24)
	G.rod_between(b, m, Vector3(0, 0.14, 0), Vector3(0, 0.82, 0), 0.032, 12)
	var ring := []
	for k in 10:
		var a := TAU * k / 10.0
		ring.append(Vector3(sin(a) * 0.06, 0.86 + cos(a) * 0.06, 0))
	G.tube(b, m, ring, 0.016, 3, 8, true)
	G.rod_between(b, m, Vector3(-0.17, 0.72, 0), Vector3(0.17, 0.72, 0), 0.022, 10, 0.9)
	G.tube(b, m, [Vector3(-0.21, 0.44, 0), Vector3(-0.17, 0.3, 0), Vector3(-0.06, 0.22, 0), Vector3(0.0, 0.215, 0), Vector3(0.06, 0.22, 0), Vector3(0.17, 0.3, 0), Vector3(0.21, 0.44, 0)], 0.03, 4, 12)
	for s in [-1.0, 1.0]:
		G.egg(b, m, 0.045, 0.06, 0.02, 0.2, 0.0, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-20)), Vector3(s * 0.205, 0.4, 0)), 6, 10)
	return b
