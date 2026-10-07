## Woven bamboo sphere: interlaced rings (closed tubes) on a small base, with a flower tucked in.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var R := 0.155
	var cy := R + 0.03
	G.puck(b, "wood_dark", 0.09, 0.04, 0.012, Transform3D(Basis(), Vector3.ZERO), 16)
	var axes := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 1, 0).normalized(), Vector3(-1, 1, 0).normalized(), Vector3(0, 1, 1).normalized(), Vector3(0, 1, -1).normalized()]
	for ax in axes:
		var u: Vector3 = ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var w: Vector3 = ax.cross(u).normalized()
		var ring := []
		for k in 20:
			var a := TAU * k / 20.0
			ring.append(Vector3(0, cy, 0) + (u * cos(a) + w * sin(a)) * R)
		G.tube(b, "bamboo", ring, 0.014, 1, 6, true)
	var flower: PackedVector2Array = G.lobed_circle(0.06, 5, 0.35, 6)
	G.bevel_slab(b, p.get("flower", "blue"), flower, 0.02, 0.008, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30)), Vector3(0.0, cy + R * 0.85, R * 0.5)))
	b.add_mesh("butter", G.sphere(0.018, 5), Transform3D(Basis(), Vector3(0.0, cy + R * 0.85 + 0.01, R * 0.5 + 0.012)))
	return b
