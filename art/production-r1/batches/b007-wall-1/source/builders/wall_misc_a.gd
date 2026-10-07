## Assorted wall pieces (p.kind). WALL anchor: back plane z = 0, model in +z, centered on x.
const P := preload("res://kit/cozy_parts.gd")

static func _plate(G, b, mat: String, outline: PackedVector2Array, t := 0.04) -> void:
	G.bevel_slab(b, mat, outline, t, 0.012, Transform3D(Basis(), Vector3(0, 0, t * 0.5)))

static func _shield(G, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 25:
		var t := float(k) / 24.0
		var y := lerpf(h * 0.5, -h * 0.5, t)
		var x := w * 0.5 * (1.0 if t < 0.55 else cos((t - 0.55) / 0.45 * PI / 2))
		pts.append(Vector2(x, y))
	for k in range(23, 0, -1):
		pts.append(Vector2(-pts[k].x, pts[k].y))
	var out := PackedVector2Array()
	for k in range(pts.size() - 1, -1, -1):
		out.append(pts[k])
	return G.rounded_polygon(out, 0.03, 2)

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	match p.get("kind", ""):
		"aircon":
			b.add_mesh("white", G.rounded_box(Vector3(0.9, 0.28, 0.2), 0.06, 3), Transform3D(Basis(), Vector3(0, 0, 0.1)))
			b.add_mesh("stone", G.rounded_box(Vector3(0.8, 0.04, 0.03), 0.012, 1), Transform3D(Basis(), Vector3(0, -0.1, 0.19)))
			P.screen(G, b, Vector3(0.33, 0.07, 0.2), 0.08, 0.03)
		"phone":
			b.add_mesh("wood_dark", G.rounded_box(Vector3(0.22, 0.34, 0.12), 0.03, 2), Transform3D(Basis(), Vector3(0, 0, 0.06)))
			for s in [-1.0, 1.0]:
				b.add_mesh("gold", G.sphere(0.03, 5), Transform3D(Basis().scaled(Vector3(1, 1, 0.6)), Vector3(s * 0.06, 0.1, 0.125)))
			G.puck(b, "charcoal", 0.035, 0.08, 0.012, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, -0.02, 0.1)), 14)
			G.tube(b, "charcoal", [Vector3(-0.1, 0.06, 0.08), Vector3(-0.15, 0.03, 0.12), Vector3(-0.16, -0.06, 0.12)], 0.012, 2, 6)
			G.rod_between(b, "charcoal", Vector3(-0.16, -0.06, 0.12), Vector3(-0.16, -0.16, 0.12), 0.03, 10)
			G.rod_between(b, "gold", Vector3(0.11, 0.03, 0.06), Vector3(0.16, 0.0, 0.06), 0.012, 6)
		"bust_plaque":
			_plate(G, b, "wood_dark", _shield(G, 0.36, 0.44))
			G.egg(b, "gold", 0.08, 0.1, 0.05, -0.1, 0.0, Transform3D(Basis(), Vector3(0, -0.08, 0.05)), 8, 12)
			b.add_mesh("gold", G.sphere(0.075, 8), Transform3D(Basis(), Vector3(0, 0.1, 0.07)))
		"bug_plaque":
			_plate(G, b, "wood_dark", _shield(G, 0.36, 0.44))
			for s in [-1.0, 1.0]:
				var wing: PackedVector2Array = G.blob_outline([[s * 0.07, 0.04, 0.065], [s * 0.05, -0.06, 0.045]], 22.0, 24)
				G.bevel_slab(b, "gold", wing, 0.02, 0.007, Transform3D(Basis(), Vector3(0, 0, 0.05)))
			G.egg(b, "gold", 0.018, 0.08, 0.018, 0.0, 0.0, Transform3D(Basis(), Vector3(0, -0.08, 0.06)), 6, 8)
		"bronze_plaque":
			_plate(G, b, "wood_dark", G.lobed_circle(0.2, 8, 0.08, 6), 0.035)
			G.bevel_slab(b, "gold", G.lobed_circle(0.13, 12, 0.12, 4), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0, 0.042)))
			G.puck(b, "wood_dark", 0.06, 0.012, 0.004, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.05)), 18)
		"autographs":
			for i in 3:
				for j in 2:
					var x := -0.24 + i * 0.24 + (j % 2) * 0.03
					var y := 0.1 - j * 0.24 + (i % 2) * 0.02
					b.add_mesh("white", G.rounded_box(Vector3(0.17, 0.2, 0.03), 0.012, 1), Transform3D(Basis(), Vector3(x, y, 0.015)))
					b.add_mesh("ink", G.rounded_box(Vector3(0.1, 0.012, 0.006), 0.004, 1), Transform3D(Basis(Vector3.BACK, 0.4), Vector3(x, y, 0.031)))
					b.add_mesh("blue" if (i + j) % 2 == 0 else "red", G.sphere(0.025, 4), Transform3D(Basis().scaled(Vector3(1, 1, 0.3)), Vector3(x - 0.04, y + 0.05, 0.031)))
		"bamboo_decor":
			b.add_mesh("wood_dark", G.rounded_box(Vector3(0.14, 0.04, 0.12), 0.015, 1), Transform3D(Basis(), Vector3(0, -0.22, 0.06)))
			for k in 3:
				var h := 0.3 - k * 0.07
				P.bamboo(G, b, Vector3(-0.04 + k * 0.04, -0.21, 0.05 + (k % 2) * 0.02), Vector3(-0.04 + k * 0.04, -0.21 + h, 0.05 + (k % 2) * 0.02), 0.022, 0.12)
			for k in 4:
				G.egg(b, "leaf", 0.02, 0.06, 0.008, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-60 + k * 40)), Vector3(0, -0.18, 0.08)), 5, 8)
			for k in 3:
				b.add_mesh("red", G.sphere(0.016, 4), Transform3D(Basis(), Vector3(0.05 + k * 0.02, -0.17 - k * 0.012, 0.09)))
		"towel_rack":
			for x in [-0.22, 0.22]:
				b.add_mesh("steel", G.rounded_box(Vector3(0.04, 0.1, 0.03), 0.01, 1), Transform3D(Basis(), Vector3(x, 0.05, 0.015)))
				G.rod_between(b, "steel", Vector3(x, 0.08, 0.02), Vector3(x, 0.08, 0.16), 0.012, 6)
			G.rod_between(b, "steel", Vector3(-0.24, 0.08, 0.16), Vector3(0.24, 0.08, 0.16), 0.012, 6)
			G.rod_between(b, "steel", Vector3(-0.24, 0.08, 0.06), Vector3(0.24, 0.08, 0.06), 0.012, 6)
			for k in 2:
				G.pillow(b, "white", Vector3(0.18, 0.08, 0.1), 0.5, 0.5, Transform3D(Basis(), Vector3(-0.1 + k * 0.2, 0.13, 0.11)), 8, 16)
			G.pillow(b, "teal", Vector3(0.2, 0.26, 0.03), 0.5, 0.45, Transform3D(Basis(), Vector3(0.0, -0.05, 0.16)), 8, 16)
		"bone_plate":
			var bone: PackedVector2Array = G.blob_outline([[-0.2, 0.05, 0.06], [-0.2, -0.05, 0.06], [0.2, 0.05, 0.06], [0.2, -0.05, 0.06], [0.0, 0.0, 0.07], [-0.1, 0.0, 0.065], [0.1, 0.0, 0.065]], 25.0, 56)
			_plate(G, b, "wood", bone, 0.04)
		"boomerang":
			var pts := []
			for k in 9:
				var a := deg_to_rad(200.0 - 130.0 * k / 8.0)
				pts.append(Vector3(cos(a) * 0.25, sin(a) * 0.25 - 0.12, 0.025))
			G.tube(b, "wood", pts, 0.03, 3, 8)
			for q in [pts[2], pts[6]]:
				G.puck(b, "red", 0.032, 0.012, 0.004, Transform3D(Basis(Vector3.RIGHT, PI / 2), q + Vector3(0, 0, 0.018)), 12)
			b.add_mesh("steel", G.rounded_box(Vector3(0.04, 0.04, 0.025), 0.008, 1), Transform3D(Basis(), pts[4] + Vector3(0, 0.0, -0.012)))
		"breaker":
			b.add_mesh("white", G.rounded_box(Vector3(0.4, 0.26, 0.08), 0.03, 2), Transform3D(Basis(), Vector3(0, 0, 0.04)))
			b.add_mesh("charcoal", G.rounded_box(Vector3(0.06, 0.12, 0.03), 0.01, 1), Transform3D(Basis(), Vector3(-0.13, 0.0, 0.085)))
			for i in 4:
				for j in 2:
					b.add_mesh("charcoal", G.rounded_box(Vector3(0.035, 0.07, 0.025), 0.008, 1), Transform3D(Basis(), Vector3(-0.04 + i * 0.05, 0.05 - j * 0.1, 0.085)))
		"broom":
			b.add_mesh("wood_dark", G.rounded_box(Vector3(0.06, 0.06, 0.04), 0.015, 1), Transform3D(Basis(), Vector3(0, 0.32, 0.02)))
			G.rod_between(b, "wood", Vector3(0, 0.33, 0.04), Vector3(-0.06, -0.2, 0.06), 0.016, 8)
			G.egg(b, "butter", 0.08, 0.1, 0.03, 0.4, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(6)) * Basis(Vector3.RIGHT, PI), Vector3(-0.055, -0.15, 0.06)), 8, 12)
			G.rod_between(b, "wood", Vector3(0, 0.33, 0.02), Vector3(0.1, 0.0, 0.04), 0.012, 6)
			b.add_mesh("teal", G.rounded_box(Vector3(0.18, 0.15, 0.03), 0.02, 2), Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0.12, -0.07, 0.05)))
	return b
