## Wall clocks by style (p.style): "flower" lobed body, "egg" egg-shaped body, "neon" round with
## a glowing ring, "station" double-sided face on a bracket sticking out from the wall,
## "cuckoo" little house with roof, door, bird and hanging weights. WALL anchor: z = 0 back plane.
static func _face(G, b, c: Vector3, r: float, basis: Basis, hands := "ink", dots := "terracotta") -> void:
	G.puck(b, "cream", r, 0.02, 0.007, Transform3D(basis * Basis(Vector3.RIGHT, PI / 2), c - basis * Vector3(0, 0, 0.01)), 28)
	for k in 12:
		var a := TAU * k / 12.0
		b.add_mesh(dots, G.sphere(r * (0.07 if k % 3 == 0 else 0.05), 4), Transform3D(basis, c + basis * Vector3(sin(a) * r * 0.78, cos(a) * r * 0.78, 0.012)))
	b.add_mesh(hands, G.rounded_box(Vector3(r * 0.12, r * 0.62, 0.01), r * 0.04, 1), Transform3D(basis * Basis(Vector3.BACK, deg_to_rad(-40)), c + basis * Vector3(r * 0.2, r * 0.24, 0.015)))
	b.add_mesh(hands, G.rounded_box(Vector3(r * 0.1, r * 0.45, 0.01), r * 0.03, 1), Transform3D(basis * Basis(Vector3.BACK, deg_to_rad(120)), c + basis * Vector3(r * 0.19, -r * 0.11, 0.013)))
	b.add_mesh(hands, G.sphere(r * 0.09, 4), Transform3D(basis.scaled(Vector3(1, 1, 0.5)), c + basis * Vector3(0, 0, 0.018)))

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var style: String = p.get("style", "flower")
	var body: String = p.get("body", "pink")
	match style:
		"flower":
			G.bevel_slab(b, body, G.lobed_circle(0.24, 5, 0.28, 10), 0.08, 0.03, Transform3D(Basis(), Vector3(0, 0, 0.04)))
			_face(G, b, Vector3(0, 0, 0.07), 0.12, Basis())
		"egg":
			var egg := PackedVector2Array()
			for k in 40:
				var a := TAU * k / 40.0
				var y := sin(a)
				egg.append(Vector2(cos(a) * 0.19 * (1.0 - 0.12 * y), y * 0.25))
			G.bevel_slab(b, body, egg, 0.08, 0.03, Transform3D(Basis(), Vector3(0, 0, 0.04)))
			for q in [[-0.1, 0.12, "pink"], [0.09, -0.15, "butter"], [0.11, 0.14, "pink"]]:
				b.add_mesh(q[2], G.sphere(0.045, 6), Transform3D(Basis().scaled(Vector3(1, 1, 0.35)), Vector3(q[0], q[1], 0.08)))
			_face(G, b, Vector3(0, -0.01, 0.07), 0.11, Basis())
		"neon":
			G.puck(b, "steel", 0.22, 0.08, 0.025, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.0)), 32)
			var ring := []
			for k in 24:
				var a := TAU * k / 24.0
				ring.append(Vector3(cos(a) * 0.2, sin(a) * 0.2, 0.085))
			G.tube(b, p.get("neon", "red"), ring, 0.018, 1, 8, true)
			_face(G, b, Vector3(0, 0, 0.08), 0.16, Basis(), "ink", "red")
		"station":
			b.add_mesh("charcoal", G.rounded_box(Vector3(0.12, 0.2, 0.04), 0.015, 2), Transform3D(Basis(), Vector3(0, 0, 0.02)))
			G.rod_between(b, "charcoal", Vector3(0, 0, 0.03), Vector3(0, 0, 0.12), 0.025, 8)
			var side := Basis(Vector3.UP, PI / 2)
			G.puck(b, "charcoal", 0.17, 0.08, 0.025, Transform3D(side * Basis(Vector3.RIGHT, PI / 2), Vector3(-0.04, 0, 0.29)), 30)
			for s in [-1.0, 1.0]:
				var face_basis := Basis(Vector3.UP, s * PI / 2)
				_face(G, b, Vector3(s * 0.045, 0, 0.29), 0.14, face_basis)
		"cuckoo":
			var w: String = p.get("wood", "wood")
			b.add_mesh(w, G.rounded_box(Vector3(0.3, 0.3, 0.16), 0.03, 2), Transform3D(Basis(), Vector3(0, 0, 0.08)))
			for s in [-1.0, 1.0]:
				b.add_mesh("wood_dark", G.rounded_box(Vector3(0.24, 0.035, 0.2), 0.012, 1), Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-38)), Vector3(s * 0.085, 0.2, 0.09)))
			b.add_mesh("wood_dark", G.rounded_box(Vector3(0.07, 0.07, 0.02), 0.012, 1), Transform3D(Basis(), Vector3(0, 0.1, 0.165)))
			b.add_mesh("butter", G.sphere(0.025, 5), Transform3D(Basis(), Vector3(0, 0.1, 0.18)))
			_face(G, b, Vector3(0, -0.03, 0.163), 0.085, Basis())
			for s in [-1.0, 1.0]:
				G.rod_between(b, "ink", Vector3(s * 0.06, -0.15, 0.1), Vector3(s * 0.06, -0.33, 0.1), 0.004, 4)
				G.egg(b, "wood_dark", 0.025, 0.05, 0.025, 0.0, 0.0, Transform3D(Basis(), Vector3(s * 0.06, -0.43, 0.1)), 6, 8)
	return b
