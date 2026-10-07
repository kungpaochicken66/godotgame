## Two-seat bamboo bench: five long seat poles, bamboo legs and stretchers.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var hx := 0.55
	var seat_y := 0.42
	for k in 5:
		var z := lerpf(-0.17, 0.17, k / 4.0)
		P.bamboo(G, b, Vector3(-hx - 0.05, seat_y, z), Vector3(hx + 0.05, seat_y, z), 0.04, 0.55)
	for x in [-hx + 0.08, hx - 0.08]:
		for z in [-0.15, 0.15]:
			P.bamboo(G, b, Vector3(x, 0.0, z), Vector3(x, seat_y - 0.02, z), 0.04, 0.3)
		G.rod_between(b, "bamboo_dark", Vector3(x, 0.14, -0.2), Vector3(x, 0.14, 0.2), 0.025, 8)
		G.rod_between(b, "bamboo_dark", Vector3(x, seat_y - 0.05, -0.2), Vector3(x, seat_y - 0.05, 0.2), 0.03, 8)
	G.rod_between(b, "bamboo_dark", Vector3(-hx + 0.08, 0.14, 0), Vector3(hx - 0.08, 0.14, 0), 0.025, 8)
	b.marker("Seat0", Vector3(-0.27, seat_y + 0.05, 0))
	b.marker("Seat1", Vector3(0.27, seat_y + 0.05, 0))
	return b
