## Tall case (grandfather) clock: plinth, waist with pendulum window, hood with face, arched crown.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w := "wood_dark"
	b.add_mesh(w, G.rounded_box(Vector3(0.48, 0.18, 0.32), 0.04, 2), Transform3D(Basis(), Vector3(0, 0.09, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(0.38, 0.74, 0.26), 0.04, 2), Transform3D(Basis(), Vector3(0, 0.53, 0)))
	G.bevel_slab(b, "cream", G.rounded_rect(0.2, 0.44, 0.06, 3), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0.56, 0.13)))
	G.rod_between(b, "gold", Vector3(0, 0.76, 0.145), Vector3(0, 0.42, 0.145), 0.008, 6)
	G.puck(b, "gold", 0.045, 0.014, 0.005, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.41, 0.14)), 18)
	b.add_mesh(w, G.rounded_box(Vector3(0.46, 0.42, 0.3), 0.05, 2), Transform3D(Basis(), Vector3(0, 1.1, 0)))
	G.bevel_slab(b, w, G.scallop_top(0.46, 0.2, 0.11, 1, 0.0), 0.28, 0.03, Transform3D(Basis(), Vector3(0, 1.27, 0)))
	G.puck(b, "cream", 0.15, 0.024, 0.008, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 1.1, 0.142)), 28)
	for k in 4:
		var a := TAU * k / 4.0
		b.add_mesh("gold", G.sphere(0.014, 4), Transform3D(Basis(), Vector3(sin(a) * 0.115, 1.1 + cos(a) * 0.115, 0.168)))
	b.add_mesh("ink", G.rounded_box(Vector3(0.02, 0.1, 0.01), 0.005, 1), Transform3D(Basis(Vector3.BACK, deg_to_rad(-30)), Vector3(0.025, 1.14, 0.172)))
	b.add_mesh("ink", G.rounded_box(Vector3(0.018, 0.07, 0.01), 0.005, 1), Transform3D(Basis(Vector3.BACK, deg_to_rad(100)), Vector3(-0.03, 1.095, 0.17)))
	for s in [-1.0, 1.0]:
		b.add_mesh("gold", G.sphere(0.03, 5), Transform3D(Basis(), Vector3(s * 0.2, 1.33, 0)))
	return b
