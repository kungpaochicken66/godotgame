## Bamboo slit drum: three bamboo tubes of different lengths on two raised blocks, two mallets resting across.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var lens := [0.46, 0.4, 0.34]
	var y := 0.2
	for x in [-0.12, 0.12]:
		b.add_mesh("bamboo_dark", G.rounded_box(Vector3(0.07, 0.16, 0.36), 0.025, 2), Transform3D(Basis(), Vector3(x, 0.08, 0)))
	for k in 3:
		var z := -0.11 + k * 0.11
		var L: float = lens[k]
		P.bamboo(G, b, Vector3(-L * 0.5, y, z), Vector3(L * 0.5, y, z), 0.055, 0.2)
		b.add_mesh("ink", G.rounded_box(Vector3(0.14, 0.012, 0.022), 0.005, 1), Transform3D(Basis(), Vector3(0, y + 0.052, z)))
	for k in 2:
		var x := -0.05 + k * 0.1
		G.rod_between(b, "wood", Vector3(x, y + 0.066, -0.12), Vector3(x + 0.03, y + 0.066, 0.13), 0.012, 6)
		b.add_mesh("red", G.sphere(0.025, 5), Transform3D(Basis(), Vector3(x + 0.032, y + 0.07, 0.15)))
	return b
