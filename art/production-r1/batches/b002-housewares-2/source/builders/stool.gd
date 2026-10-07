## Four-leg stool with a puffy cushion (arcade/bar style).
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var leg: String = p.get("frame", "steel")
	var seat_y := 0.46
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			G.rod_between(b, leg, Vector3(x * 0.2, 0.0, z * 0.2), Vector3(x * 0.15, seat_y - 0.02, z * 0.15), 0.022, 10, 0.6)
	var ring := []
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4
		ring.append(Vector3(cos(a) * 0.255, 0.16, sin(a) * 0.255))
	G.tube(b, leg, ring, 0.014, 3, 8, true)
	b.add_mesh(leg, G.rounded_box(Vector3(0.38, 0.04, 0.38), 0.015, 2), Transform3D(Basis(), Vector3(0, seat_y - 0.02, 0)))
	G.pillow(b, p.get("cushion", "red"), Vector3(0.42, 0.1, 0.42), 0.38, 0.35, Transform3D(Basis(), Vector3(0, seat_y + 0.035, 0)), 10, 24)
	b.marker("Seat0", Vector3(0, seat_y + 0.08, 0))
	return b
