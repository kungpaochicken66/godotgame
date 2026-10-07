## Balloon arch on two weighted bases. p: colors [a, b], radius (arch), r (balloon).
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var cols: Array = p.get("colors", ["gold", "white"])
	var b = G.Builder.new()
	var R: float = p.get("radius", 0.82)
	var r: float = p.get("r", 0.11)
	var pts := []
	for k in 4:
		pts.append(Vector3(-R, 0.2 + k * 0.17, 0))
	var n := 15
	for k in n + 1:
		var a := PI - PI * k / n
		pts.append(Vector3(cos(a) * R, 0.82 + sin(a) * R, 0))
	for k in range(3, -1, -1):
		pts.append(Vector3(R, 0.2 + k * 0.17, 0))
	var i := 0
	for q in pts:
		for s in [-1.0, 1.0]:
			var c: String = cols[i % cols.size()]
			b.add_mesh(c, G.sphere(r, 5), Transform3D(Basis(), q + Vector3(0, 0, s * r * 0.62)))
			i += 1
	for x in [-R, R]:
		b.add_mesh("steel", G.rounded_box(Vector3(0.3, 0.16, 0.3), 0.04, 2), Transform3D(Basis(), Vector3(x, 0.08, 0)))
	return b
