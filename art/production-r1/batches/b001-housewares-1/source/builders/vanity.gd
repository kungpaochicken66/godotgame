## Vanity desk: two drawer pedestals, top, small top drawers, oval mirror on posts.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood_dark")
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.05, 0.44), 0.02, 2), Transform3D(Basis(), Vector3(0, 0.725, 0)))
	for s in [-1.0, 1.0]:
		b.add_mesh(w, G.rounded_box(Vector3(0.28, 0.66, 0.42), 0.03, 2), Transform3D(Basis(), Vector3(s * 0.36, 0.38, 0)))
		for y in [0.25, 0.52]:
			P.panel(G, b, "wood", Vector3(s * 0.36, y, 0.21), 0.22, 0.2, 0.02, 0.015)
			P.knob(G, b, "gold", Vector3(s * 0.36, y, 0.235), 0.017)
		b.add_mesh(w, G.rounded_box(Vector3(0.22, 0.11, 0.26), 0.025, 2), Transform3D(Basis(), Vector3(s * 0.36, 0.8, -0.06)))
		P.knob(G, b, "gold", Vector3(s * 0.36, 0.8, 0.075), 0.014)
		G.rod_between(b, w, Vector3(s * 0.16, 0.74, -0.16), Vector3(s * 0.2, 1.05, -0.16), 0.022)
	var oval := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
		oval.append(Vector2(cos(a) * 0.21, sin(a) * 0.27))
	G.bevel_slab(b, w, oval, 0.05, 0.02, Transform3D(Basis(), Vector3(0, 1.05, -0.16)))
	var glass := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
		glass.append(Vector2(cos(a) * 0.165, sin(a) * 0.225))
	G.bevel_slab(b, "steel", glass, 0.02, 0.006, Transform3D(Basis(), Vector3(0, 1.05, -0.13)))
	return b
