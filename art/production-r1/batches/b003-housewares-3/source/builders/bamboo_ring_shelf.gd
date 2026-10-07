## Round bamboo shelf: a bamboo hoop on two feet with three bamboo-slat shelves inside.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var R := 0.55
	var cy := R + 0.1
	for z in [-0.14, 0.14]:
		var hoop := []
		for k in 18:
			var a := TAU * k / 18.0
			hoop.append(Vector3(cos(a) * R, cy + sin(a) * R, z))
		G.tube(b, "bamboo", hoop, 0.04, 1, 10, true)
	for y in [-0.3, 0.05, 0.36]:
		var hw := sqrt(R * R - y * y) - 0.02
		for k in 3:
			var z := lerpf(-0.13, 0.13, k / 2.0)
			P.bamboo(G, b, Vector3(-hw, cy + y, z), Vector3(hw, cy + y, z), 0.026, 0.6)
		for x in [-hw + 0.03, hw - 0.03]:
			G.rod_between(b, "bamboo_dark", Vector3(x, cy + y - 0.03, -0.15), Vector3(x, cy + y - 0.03, 0.15), 0.02, 8)
	for s in [-1.0, 1.0]:
		b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.12, 0.08, 0.42), 0.03, 2), Transform3D(Basis(), Vector3(s * 0.25, 0.04, 0)))
		P.bamboo(G, b, Vector3(s * 0.25, 0.06, 0), Vector3(s * 0.25, cy - sqrt(R * R - 0.0625) + 0.02, 0), 0.035, 0.2)
	return b
