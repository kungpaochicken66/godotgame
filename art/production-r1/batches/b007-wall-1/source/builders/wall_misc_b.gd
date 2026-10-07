## More wall pieces (p.kind). WALL anchor: back plane z = 0, model in +z, centered on x.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	match p.get("kind", ""):
		"poster":
			b.add_mesh("charcoal", G.rounded_box(Vector3(0.42, 0.6, 0.03), 0.012, 1), Transform3D(Basis(), Vector3(0, 0, 0.015)))
			b.add_mesh("paper", G.rounded_box(Vector3(0.37, 0.55, 0.02), 0.006, 1), Transform3D(Basis(), Vector3(0, 0, 0.026)))
			var cols := ["leaf", "red", "butter", "blue", "leaf", "red"]
			for i in 4:
				for j in 5:
					b.add_mesh(cols[(i + j * 2) % 6], G.sphere(0.022, 4), Transform3D(Basis().scaled(Vector3(1.3, 1, 0.35)), Vector3(-0.12 + i * 0.08, 0.18 - j * 0.09, 0.037)))
		"board":
			var w: float = p.get("w", 0.8)
			var h: float = p.get("h", 0.5)
			b.add_mesh(p.get("frame", "wood"), G.rounded_box(Vector3(w, h, 0.04), 0.02, 2), Transform3D(Basis(), Vector3(0, 0, 0.02)))
			b.add_mesh(p.get("surface", "sage"), G.rounded_box(Vector3(w - 0.08, h - 0.08, 0.02), 0.008, 1), Transform3D(Basis(), Vector3(0, 0, 0.035)))
			var notes := [[-0.25, 0.08, 0.16, 0.2, "white"], [-0.05, 0.1, 0.14, 0.12, "butter"], [0.18, 0.04, 0.18, 0.22, "white"], [-0.18, -0.12, 0.15, 0.1, "white"], [0.05, -0.1, 0.12, 0.14, "butter"]]
			for n in notes:
				var x: float = n[0] * w / 0.8
				var y: float = n[1] * h / 0.5
				b.add_mesh(n[4], G.rounded_box(Vector3(n[2], n[3], 0.008), 0.003, 1), Transform3D(Basis(Vector3.BACK, x * 0.3), Vector3(x, y, 0.047)))
				b.add_mesh("red", G.sphere(0.012, 4), Transform3D(Basis(), Vector3(x, y + n[3] * 0.4, 0.055)))
		"garland":
			var w2: float = p.get("w", 0.9)
			var pts := []
			for k in 9:
				var t := float(k) / 8.0
				pts.append(Vector3(lerpf(-w2 * 0.5, w2 * 0.5, t), -0.12 * sin(t * PI), 0.04))
			for x in [-w2 * 0.5, w2 * 0.5]:
				b.add_mesh("steel", G.rounded_box(Vector3(0.03, 0.03, 0.04), 0.008, 1), Transform3D(Basis(), Vector3(x, 0.0, 0.02)))
			G.tube(b, p.get("string", "cream"), pts, 0.006, 3, 5)
			var items: Array = p.get("items", ["bulb"])
			for k in 7:
				var t := (k + 1) / 8.0
				var q := Vector3(lerpf(-w2 * 0.5, w2 * 0.5, t), -0.12 * sin(t * PI), 0.04)
				var m: String = items[k % items.size()]
				match p.get("style", "bulbs"):
					"bulbs":
						G.egg(b, m, 0.03, 0.04, 0.03, 0.15, 0.0, Transform3D(Basis(Vector3.RIGHT, PI), q + Vector3(0, -0.005, 0)), 6, 10)
						if k == 3:
							b.marker("Light0", q + Vector3(0, -0.04, 0))
					"eggs":
						G.egg(b, m, 0.03, 0.04, 0.025, 0.0, 0.0, Transform3D(Basis(Vector3.RIGHT, PI), q + Vector3(0, -0.004, 0)), 6, 10)
					"bunches":
						G.rod_between(b, "wood_dark", q, q + Vector3(0, -0.1, 0), 0.006, 4)
						for j in 3:
							b.add_mesh(m, G.sphere(0.022, 4), Transform3D(Basis(), q + Vector3(-0.02 + j * 0.02, -0.11 - (j % 2) * 0.02, 0.01)))
						G.egg(b, "leaf_light", 0.015, 0.05, 0.006, 0.0, 0.0, Transform3D(Basis(Vector3.RIGHT, PI), q + Vector3(0.015, -0.02, 0.005)), 4, 6)
		"fish_wall_unused":
			pass
		"fish_wall":
			for k in 4:
				var x := -0.12 + (k % 2) * 0.24
				var y := 0.1 - (k / 2) * 0.2
				G.egg(b, "butter", 0.06, 0.08, 0.03, 0.1, 0.0, Transform3D(Basis(Vector3.BACK, -PI / 2), Vector3(x - 0.08, y, 0.03)), 6, 10)
				G.bevel_slab(b, "charcoal", G.blob_outline([[0, 0.025, 0.03], [0, -0.025, 0.03]], 25.0, 16), 0.02, 0.006, Transform3D(Basis(), Vector3(x - 0.09, y, 0.03)))
				G.puck(b, "charcoal", 0.03, 0.03, 0.01, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x, y, 0.0)), 10)
				b.add_mesh("ink", G.sphere(0.01, 4), Transform3D(Basis(), Vector3(x + 0.05, y + 0.015, 0.055)))
		"cherry_lamp":
			b.add_mesh("wood_dark", G.rounded_box(Vector3(0.06, 0.08, 0.04), 0.015, 1), Transform3D(Basis(), Vector3(0, 0.2, 0.02)))
			for s in [-1.0, 1.0]:
				G.tube(b, "leaf", [Vector3(0, 0.2, 0.04), Vector3(s * 0.05, 0.1, 0.08), Vector3(s * 0.1, 0.0, 0.09)], 0.012, 3, 6)
				b.add_mesh("red", G.sphere(0.09, 8), Transform3D(Basis(), Vector3(s * 0.1, -0.08, 0.1)))
				b.add_mesh("bulb", G.sphere(0.03, 5), Transform3D(Basis(), Vector3(s * 0.08, -0.04, 0.17)))
			G.egg(b, "leaf", 0.04, 0.07, 0.01, 0.2, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-60)), Vector3(0.02, 0.2, 0.05)), 6, 10)
			b.marker("Light0", Vector3(0, -0.06, 0.12))
		"coconut_planter":
			b.add_mesh("steel", G.rounded_box(Vector3(0.04, 0.04, 0.12), 0.01, 1), Transform3D(Basis(), Vector3(0, 0.33, 0.06)))
			for k in 3:
				var a := TAU * k / 3.0
				G.rod_between(b, "cream", Vector3(0, 0.33, 0.12), Vector3(cos(a) * 0.1, 0.0, 0.16 + sin(a) * 0.1), 0.006, 4)
			var shell: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, -0.12), Vector2(0.06, -0.115), Vector2(0.11, -0.06), Vector2(0.125, 0.0), Vector2(0.11, 0.01), Vector2(0.0, -0.01)]), 3)
			G.lathe(b, "wood_dark", shell, 20, Transform3D(Basis(), Vector3(0, 0.0, 0.16)))
			for k in 5:
				var a := TAU * k / 5.0
				G.egg(b, "leaf", 0.03, 0.09, 0.01, 0.0, 0.02, Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), deg_to_rad(-40)), Vector3(0, -0.01, 0.16)), 5, 8)
		"crest":
			var crest: PackedVector2Array = G.blob_outline([[0, 0.05, 0.13], [-0.12, -0.05, 0.08], [0.12, -0.05, 0.08], [0, -0.13, 0.07]], 20.0, 48)
			G.bevel_slab(b, "charcoal", crest, 0.04, 0.012, Transform3D(Basis(), Vector3(0, 0, 0.02)))
			G.bevel_slab(b, "steel", G.lobed_circle(0.06, 4, 0.3, 6), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0.0, 0.045)))
		"deer":
			var plate: PackedVector2Array = G.blob_outline([[0, 0, 0.13], [0, -0.06, 0.12]], 18.0, 40)
			G.bevel_slab(b, "wood_dark", plate, 0.03, 0.01, Transform3D(Basis(), Vector3(0, -0.15, 0.015)))
			G.egg(b, "wood", 0.08, 0.13, 0.08, -0.25, 0.0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(70)), Vector3(0, -0.2, 0.03)), 8, 12)
			for s in [-1.0, 1.0]:
				G.tube(b, "butter", [Vector3(s * 0.04, -0.05, 0.08), Vector3(s * 0.1, 0.08, 0.08), Vector3(s * 0.12, 0.22, 0.06)], 0.018, 3, 6)
				G.tube(b, "butter", [Vector3(s * 0.1, 0.08, 0.08), Vector3(s * 0.18, 0.14, 0.08)], 0.014, 2, 6)
				G.egg(b, "wood", 0.03, 0.05, 0.015, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-70)), Vector3(s * 0.06, -0.08, 0.1)), 5, 8)
				b.add_mesh("ink", G.sphere(0.012, 4), Transform3D(Basis(), Vector3(s * 0.035, -0.13, 0.17)))
		"dreamy_rack":
			b.add_mesh("pink", G.rounded_box(Vector3(0.5, 0.04, 0.16), 0.015, 2), Transform3D(Basis(), Vector3(0, -0.08, 0.08)))
			for x in [-0.2, 0.2]:
				b.add_mesh("pink", G.rounded_box(Vector3(0.03, 0.1, 0.14), 0.01, 1), Transform3D(Basis(), Vector3(x, -0.13, 0.07)))
			b.add_mesh("lilac", G.sphere(0.07, 6), Transform3D(Basis(), Vector3(-0.1, 0.0, 0.08)))
			b.add_mesh("lilac", G.sphere(0.05, 6), Transform3D(Basis(), Vector3(-0.1, 0.1, 0.08)))
			for s in [-1.0, 1.0]:
				G.egg(b, "lilac", 0.02, 0.05, 0.015, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, s * -0.2), Vector3(-0.1 + s * 0.025, 0.13, 0.08)), 4, 6)
			b.add_mesh("pink", G.sphere(0.06, 6), Transform3D(Basis(), Vector3(0.1, -0.005, 0.08)))
			b.add_mesh("pink", G.sphere(0.045, 6), Transform3D(Basis(), Vector3(0.1, 0.085, 0.08)))
			b.add_mesh("butter", G.rounded_box(Vector3(0.06, 0.04, 0.05), 0.012, 1), Transform3D(Basis(), Vector3(0.0, -0.04, 0.09)))
	return b
