## Small child's chair: bent-tube frame (swept tubes), cream seat and back panels.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var fr: String = p.get("frame", "red")
	for s in [-1.0, 1.0]:
		G.tube(b, fr, [Vector3(s * 0.17, 0.03, 0.17), Vector3(s * 0.17, 0.3, 0.15), Vector3(s * 0.17, 0.32, -0.12), Vector3(s * 0.17, 0.52, -0.16)], 0.022, 4, 8)
		G.tube(b, fr, [Vector3(s * 0.17, 0.03, -0.17), Vector3(s * 0.17, 0.28, -0.13)], 0.022, 2, 8)
		G.tube(b, fr, [Vector3(s * 0.17, 0.03, 0.17), Vector3(s * 0.17, 0.022, 0.0), Vector3(s * 0.17, 0.03, -0.17)], 0.02, 2, 8)
	G.tube(b, fr, [Vector3(-0.17, 0.52, -0.16), Vector3(0.0, 0.535, -0.165), Vector3(0.17, 0.52, -0.16)], 0.022, 3, 8)
	G.pillow(b, "cream", Vector3(0.38, 0.06, 0.34), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.33, 0.01)), 8, 20)
	G.pillow(b, "cream", Vector3(0.34, 0.18, 0.05), 0.45, 0.4, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10)), Vector3(0, 0.44, -0.145)), 8, 20)
	b.marker("Seat0", Vector3(0, 0.36, 0.02))
	return b
