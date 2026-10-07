## Display model on a stand: oval dark base, post, small blank plaque, and a stylized
## animal (p.kind: fish | butterfly | ant | cricket | bagworm). Colors via params.
static func _stand(G, b, w: float, d: float, post_h: float) -> void:
	var oval := PackedVector2Array()
	for k in 32:
		var a := TAU * k / 32.0
		oval.append(Vector2(cos(a) * w * 0.5, sin(a) * d * 0.5))
	G.plan_slab(b, "charcoal", oval, 0.0, 0.05, 0.018)
	b.add_mesh("steel", G.rounded_box(Vector3(0.1, 0.035, 0.02), 0.008, 1), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30)), Vector3(0, 0.05, d * 0.32)))
	G.rod(b, "steel", 0.012, 0.012, post_h, Transform3D(Basis(), Vector3(0, 0.04, 0)), 8)

static func _fish(G, b, p: Dictionary, y: float) -> void:
	var L: float = p.get("length", 0.36)
	var H: float = p.get("height", 0.12)
	var c: String = p.get("color", "blue")
	var c2: String = p.get("fin", c)
	G.egg(b, c, H * 0.5, L * 0.5, H * 0.32, -0.15, 0.0, Transform3D(Basis(Vector3.BACK, -PI / 2), Vector3(-L * 0.5, y, 0)), 8, 14)
	# Fins scale with body HEIGHT (a slim fish keeps small fins): tail ~1.2 H, dorsal ~0.5 H.
	var tail: PackedVector2Array = G.blob_outline([[0.0, H * 0.28, H * 0.3], [0.0, -H * 0.28, H * 0.3]], 6.0 / H, 24)
	G.bevel_slab(b, c2, tail, 0.022, 0.008, Transform3D(Basis(), Vector3(-L * 0.5 - H * 0.12, y, 0)))
	var dh: float = H * 0.25 * float(p.get("dorsal", 1.0))
	var fin: PackedVector2Array = G.blob_outline([[0.0, 0.0, dh], [dh * 1.2, dh * 0.3, dh * 0.8]], 4.0 / dh, 20)
	G.bevel_slab(b, c2, fin, 0.016, 0.006, Transform3D(Basis(), Vector3(-L * 0.05, y + H * 0.42, 0)))
	for s in [-1.0, 1.0]:
		b.add_mesh("ink", G.sphere(0.012, 4), Transform3D(Basis(), Vector3(L * 0.36, y + H * 0.12, s * H * 0.26)))
	if p.has("stripes"):
		for k in int(p["stripes"]):
			var x := lerpf(-L * 0.3, L * 0.25, (k + 0.5) / float(p["stripes"]))
			# Band slightly larger than the egg body's cross-section at x, so it shows as a stripe.
			var t := clampf(x / (L * 0.5), -0.98, 0.98)
			var sec := sqrt(1.0 - t * t) * (1.0 - 0.15 * t)
			b.add_mesh(p.get("stripe_color", "ink"), G.sphere(1.0, 8), Transform3D(Basis().scaled(Vector3(0.012, H * 0.5 * sec * 1.06, H * 0.32 * sec * 1.06)), Vector3(x, y, 0)))

static func _butterfly(G, b, p: Dictionary, y: float) -> void:
	var c: String = p.get("color", "red")
	G.egg(b, "ink", 0.015, 0.06, 0.015, 0.0, 0.0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, y, -0.06)), 6, 8)
	for s in [-1.0, 1.0]:
		var wing: PackedVector2Array = G.blob_outline([[s * 0.08, 0.06, 0.07], [s * 0.06, -0.04, 0.05]], 20.0, 28)
		G.bevel_slab(b, c, wing, 0.012, 0.004, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-25)) * Basis(Vector3.RIGHT, -PI / 2), Vector3(0, y + 0.01, 0)))
		G.rod_between(b, "ink", Vector3(0, y, 0.055), Vector3(s * 0.04, y + 0.06, 0.1), 0.004, 4)

static func _insect(G, b, p: Dictionary, y: float, kind: String) -> void:
	var c: String = p.get("color", "ink")
	if kind == "ant":
		for k in 3:
			var r: float = [0.04, 0.03, 0.055][k]
			b.add_mesh(c, G.sphere(r, 6), Transform3D(Basis().scaled(Vector3(1, 0.8, 1.2)), Vector3(0, y, 0.08 - k * 0.08)))
		for s in [-1.0, 1.0]:
			for k in 3:
				var z := 0.03 - k * 0.03
				G.tube(b, c, [Vector3(s * 0.02, y, z), Vector3(s * 0.09, y + 0.03, z + 0.01 * (k - 1)), Vector3(s * 0.12, y - 0.04, z + 0.03 * (k - 1))], 0.006, 2, 5)
			G.tube(b, c, [Vector3(s * 0.015, y + 0.03, 0.1), Vector3(s * 0.05, y + 0.08, 0.13), Vector3(s * 0.07, y + 0.09, 0.17)], 0.005, 2, 5)
	elif kind == "cricket":
		G.egg(b, c, 0.04, 0.09, 0.035, 0.1, 0.0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, y, -0.09)), 7, 10)
		b.add_mesh(c, G.sphere(0.035, 6), Transform3D(Basis(), Vector3(0, y + 0.005, 0.1)))
		for s in [-1.0, 1.0]:
			G.egg(b, p.get("wing", "charcoal"), 0.045, 0.08, 0.008, 0.2, 0.0, Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.BACK, s * 0.25), Vector3(s * 0.02, y + 0.035, -0.06)), 6, 10)
			G.tube(b, c, [Vector3(s * 0.03, y - 0.01, -0.03), Vector3(s * 0.08, y + 0.05, -0.07), Vector3(s * 0.11, y - 0.05, -0.12)], 0.008, 2, 5)
			G.tube(b, c, [Vector3(s * 0.015, y + 0.02, 0.12), Vector3(s * 0.06, y + 0.08, 0.2), Vector3(s * 0.12, y + 0.1, 0.24)], 0.004, 2, 5)
	elif kind == "bagworm":
		var hx := 0.09
		G.tube(b, "wood_dark", [Vector3(hx, y + 0.27, 0), Vector3(hx, y + 0.2, 0)], 0.006, 1, 5)
		G.egg(b, c, 0.045, 0.1, 0.045, 0.15, 0.0, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(hx, y + 0.21, 0)), 7, 10)
		for k in 6:
			var a := k * 1.1
			G.egg(b, "wood", 0.018, 0.035, 0.008, 0.0, 0.0, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.2), Vector3(hx + cos(a) * 0.035, y + 0.15 - k * 0.022, sin(a) * 0.035)), 4, 6)

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var kind: String = p.get("kind", "fish")
	var post: float = p.get("post", 0.2)
	_stand(G, b, p.get("base_w", 0.34), p.get("base_d", 0.22), post)
	var y := 0.04 + post
	match kind:
		"fish":
			_fish(G, b, p, y + p.get("height", 0.12) * 0.42)
		"butterfly":
			_butterfly(G, b, p, y + 0.01)
		_:
			if kind == "bagworm":
				G.tube(b, "steel", [Vector3(0, y - 0.01, 0), Vector3(0, y + 0.28, 0), Vector3(0.09, y + 0.28, 0)], 0.012, 1, 6)
				_insect(G, b, p, y, kind)
			else:
				_insect(G, b, p, y + 0.02, kind)
	return b
