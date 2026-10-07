## Bamboo floor lantern: four bamboo poles framing paper panels, cap, glowing bulb inside.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var hx := 0.17
	b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.44, 0.06, 0.44), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.03, 0)))
	for x in [-hx, hx]:
		for z in [-hx, hx]:
			P.bamboo(G, b, Vector3(x, 0.03, z), Vector3(x, 1.0, z), 0.03, 0.25)
	b.add_mesh("paper", G.rounded_box(Vector3(0.32, 0.6, 0.32), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.6, 0)))
	b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.44, 0.06, 0.44), 0.02, 2), Transform3D(Basis(), Vector3(0, 1.0, 0)))
	b.add_mesh("bulb", G.sphere(0.06, 6), Transform3D(Basis(), Vector3(0, 0.6, 0)))
	b.marker("Light0", Vector3(0, 0.6, 0))
	return b
