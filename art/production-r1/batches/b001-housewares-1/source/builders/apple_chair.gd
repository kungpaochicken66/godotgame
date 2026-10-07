## Apple-themed chair: pedestal base, red bowl seat with cream cushion, apple-shaped back, stem and leaf.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "charcoal", 0.24, 0.05, 0.02, Transform3D(Basis(), Vector3.ZERO), 28)
	G.rod(b, "charcoal", 0.045, 0.04, 0.32, Transform3D(Basis(), Vector3(0, 0.03, 0)), 12)
	G.puck(b, "red", 0.27, 0.16, 0.07, Transform3D(Basis(), Vector3(0, 0.3, 0)), 32)
	G.pillow(b, "cream", Vector3(0.44, 0.09, 0.42), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.47, 0.02)), 10, 24)
	var back: PackedVector2Array = G.blob_outline([[-0.12, 0.26, 0.16], [0.12, 0.26, 0.16], [0, 0.15, 0.2]], 22.0, 48)
	G.bevel_slab(b, "red", back, 0.12, 0.045, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8)), Vector3(0, 0.42, -0.17)))
	G.rod_between(b, "wood_dark", Vector3(0, 0.84, -0.2), Vector3(0.02, 0.97, -0.21), 0.018)
	G.egg(b, "leaf", 0.05, 0.07, 0.015, 0.2, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-70)), Vector3(0.02, 0.92, -0.21)), 6, 10)
	b.marker("Seat0", Vector3(0, 0.52, 0.03))
	return b
