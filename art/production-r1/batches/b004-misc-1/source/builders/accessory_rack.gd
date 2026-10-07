## Small accessories rack: A-frame tube stand with a top bar, hanging necklaces (closed tubes) and a lower shelf with trinkets.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var fr: String = p.get("frame", "white")
	var hx := 0.26
	for s in [-1.0, 1.0]:
		G.rod_between(b, fr, Vector3(s * hx, 0.0, -0.15), Vector3(s * hx, 0.82, 0), 0.018, 8)
		G.rod_between(b, fr, Vector3(s * hx, 0.0, 0.15), Vector3(s * hx, 0.82, 0), 0.018, 8)
	G.rod_between(b, fr, Vector3(-hx - 0.03, 0.82, 0), Vector3(hx + 0.03, 0.82, 0), 0.02, 8)
	b.add_mesh(fr, G.rounded_box(Vector3(0.5, 0.03, 0.2), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.3, 0)))
	var cols := ["gold", "pink", "teal", "lilac"]
	for k in 4:
		var x := -0.18 + k * 0.12
		var drop := 0.22 + (k % 2) * 0.08
		var loop := []
		for j in 10:
			var a := TAU * j / 10.0
			loop.append(Vector3(x + sin(a) * 0.04, 0.82 - drop * 0.5 - cos(a) * drop * 0.5, 0.0))
		G.tube(b, cols[k], loop, 0.006, 2, 5, true)
		b.add_mesh(cols[k], G.sphere(0.022, 5), Transform3D(Basis(), Vector3(x, 0.82 - drop - 0.01, 0)))
	b.add_mesh("pink", G.rounded_box(Vector3(0.1, 0.06, 0.08), 0.02, 1), Transform3D(Basis(), Vector3(-0.12, 0.345, 0)))
	b.add_mesh("blue", G.sphere(0.04, 6), Transform3D(Basis(), Vector3(0.1, 0.355, 0)))
	return b
