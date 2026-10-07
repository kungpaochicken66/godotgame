## Food served on a small wooden pedestal tray (house rule for plated food: raises the dish
## into the contract "small" height range and keeps it readable). p.kind selects the dish.
const TOP := 0.18  # plate surface height

static func _tray(G, b, plate: String, r := 0.17) -> void:
	G.puck(b, "wood", 0.12, 0.03, 0.012, Transform3D(Basis(), Vector3.ZERO), 22)
	G.rod(b, "wood", 0.04, 0.035, 0.12, Transform3D(Basis(), Vector3(0, 0.02, 0)), 12)
	G.puck(b, "wood", 0.18, 0.025, 0.01, Transform3D(Basis(), Vector3(0, 0.135, 0)), 28)
	if plate != "":
		G.puck(b, plate, r, 0.022, 0.009, Transform3D(Basis(), Vector3(0, 0.158, 0)), 28)

static func _ball(G, b, m: String, p: Vector3, r: float, sc := Vector3.ONE) -> void:
	b.add_mesh(m, G.sphere(r, 6), Transform3D(Basis().scaled(sc), p))

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var kind: String = p.get("kind", "pie")
	match kind:
		"fry":
			_tray(G, b, "white")
			for k in 2:
				G.egg(b, "gold", 0.05, 0.09, 0.03, 0.2, 0.0, Transform3D(Basis(Vector3.UP, 0.4 + k * 0.5) * Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.RIGHT, -0.25), Vector3(-0.06 + k * 0.09, TOP + 0.025, -0.08)), 8, 12)
			for k in 5:
				_ball(G, b, "leaf_light", Vector3(0.06 + (k % 2) * 0.04, TOP + 0.03 + k * 0.006, 0.06 - k * 0.02), 0.045, Vector3(1, 0.7, 1))
			_ball(G, b, "red", Vector3(-0.08, TOP + 0.03, 0.07), 0.032)
			_ball(G, b, "butter", Vector3(0.02, TOP + 0.025, 0.09), 0.03, Vector3(1.4, 0.7, 0.8))
		"skillet":
			_tray(G, b, "")
			G.puck(b, "charcoal", 0.15, 0.08, 0.02, Transform3D(Basis(), Vector3(0, 0.158, 0)), 28)
			G.puck(b, "gold", 0.13, 0.03, 0.01, Transform3D(Basis(), Vector3(0, 0.21, 0)), 24)
			G.rod_between(b, "charcoal", Vector3(0.14, 0.21, 0), Vector3(0.24, 0.23, 0), 0.016)
			for k in 5:
				var a := TAU * k / 5.0
				G.egg(b, "steel", 0.018, 0.05, 0.012, 0.0, 0.0, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI / 2), Vector3(cos(a) * 0.06, 0.245, sin(a) * 0.06)), 5, 8)
				_ball(G, b, "white", Vector3(cos(a + 0.6) * 0.09, 0.245, sin(a + 0.6) * 0.09), 0.018)
			_ball(G, b, "red", Vector3(0, 0.25, 0), 0.02)
			for k in 3:
				_ball(G, b, "red", Vector3(-0.03 + k * 0.03, 0.25, 0.03), 0.012)
		"pie":
			_tray(G, b, "white")
			var crust := PackedVector2Array([Vector2(0, TOP), Vector2(0.13, TOP), Vector2(0.15, TOP + 0.05), Vector2(0.155, TOP + 0.075), Vector2(0.13, TOP + 0.085), Vector2(0.0, TOP + 0.09)])
			G.lathe(b, "gold", G.smooth_path(crust, 2), 28)
			for k in 5:
				var t := -0.1 + k * 0.05
				var hw := sqrt(maxf(0.0, 0.13 * 0.13 - t * t))
				G.rod_between(b, "butter", Vector3(t, TOP + 0.093, -hw), Vector3(t, TOP + 0.093, hw), 0.012, 6)
				G.rod_between(b, "butter", Vector3(-hw, TOP + 0.096, t), Vector3(hw, TOP + 0.096, t), 0.012, 6)
		"slice":
			_tray(G, b, "white")
			var wedge := PackedVector2Array([Vector2(-0.02, -0.11), Vector2(0.1, 0.06), Vector2(0.05, 0.1), Vector2(-0.06, 0.12)])
			G.plan_slab(b, "gold", G.rounded_polygon(wedge, 0.02, 3), TOP, 0.06, 0.012)
			G.plan_slab(b, "red", G.rounded_polygon(PackedVector2Array([Vector2(-0.01, -0.06), Vector2(0.075, 0.06), Vector2(0.04, 0.085), Vector2(-0.04, 0.095)]), 0.015, 3), TOP + 0.05, 0.03, 0.01)
			_ball(G, b, "leaf", Vector3(0.02, TOP + 0.085, 0.06), 0.02, Vector3(1, 0.5, 1.4))
		"jelly":
			_tray(G, b, "white")
			var dome := PackedVector2Array([Vector2(0, TOP), Vector2(0.11, TOP), Vector2(0.105, TOP + 0.05), Vector2(0.08, TOP + 0.1), Vector2(0.0, TOP + 0.11)])
			G.lathe(b, "butter", G.smooth_path(dome, 3), 28)
			G.egg(b, "red", 0.02, 0.04, 0.012, 0.3, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-70)), Vector3(-0.01, TOP + 0.105, 0)), 6, 10)
			_ball(G, b, "leaf", Vector3(0.03, TOP + 0.11, 0.0), 0.015, Vector3(1.4, 0.5, 0.8))
		"potatoes":
			_tray(G, b, "white")
			for k in 3:
				var a := TAU * k / 3.0
				var pos := Vector3(cos(a) * 0.065, TOP + 0.03, sin(a) * 0.065)
				_ball(G, b, "wood", pos, 0.05, Vector3(1.2, 0.8, 0.9))
				_ball(G, b, "butter", pos + Vector3(0, 0.035, 0), 0.03, Vector3(1.2, 0.5, 0.8))
				b.add_mesh("white", G.rounded_box(Vector3(0.03, 0.02, 0.03), 0.006, 1), Transform3D(Basis(), pos + Vector3(0, 0.055, 0)))
			var top_pos := Vector3(0.0, TOP + 0.08, 0.0)
			_ball(G, b, "wood", top_pos, 0.05, Vector3(1.2, 0.8, 0.9))
			_ball(G, b, "butter", top_pos + Vector3(0, 0.035, 0), 0.03, Vector3(1.2, 0.5, 0.8))
		"soup":
			_tray(G, b, "")
			var bowl := PackedVector2Array([Vector2(0, 0.158), Vector2(0.06, 0.158), Vector2(0.065, 0.17), Vector2(0.13, 0.22), Vector2(0.14, 0.27), Vector2(0.125, 0.272), Vector2(0.12, 0.25), Vector2(0.0, 0.245)])
			G.lathe(b, "white", bowl, 28)
			G.puck(b, "gold", 0.118, 0.005, 0.002, Transform3D(Basis(), Vector3(0, 0.246, 0)), 24)
			for k in 3:
				G.egg(b, "butter", 0.02, 0.035, 0.012, 0.3, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-80)) * Basis(Vector3.UP, k), Vector3(-0.04 + k * 0.04, 0.255, -0.02 + k * 0.02)), 5, 8)
			_ball(G, b, "leaf", Vector3(0.05, 0.255, -0.04), 0.015, Vector3(1.4, 0.5, 1))
		"carpaccio":
			_tray(G, b, "")
			var oval := PackedVector2Array()
			for k in 32:
				var a := TAU * k / 32.0
				oval.append(Vector2(cos(a) * 0.17, sin(a) * 0.12))
			G.plan_slab(b, "teal", oval, 0.158, 0.022, 0.009)
			for k in 6:
				var a := TAU * k / 6.0
				G.puck(b, "pink", 0.04, 0.008, 0.003, Transform3D(Basis(), Vector3(cos(a) * 0.08, TOP - 0.003 + (k % 2) * 0.004, sin(a) * 0.05)), 14)
			for k in 4:
				_ball(G, b, "leaf_light", Vector3(-0.02 + k * 0.015, TOP + 0.008, 0.0), 0.018, Vector3(1, 0.6, 1))
			_ball(G, b, "red", Vector3(0.03, TOP + 0.018, 0.02), 0.015)
			G.puck(b, "butter", 0.045, 0.012, 0.005, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(-0.01, TOP + 0.04, -0.008)), 16)
		"donuts":
			_tray(G, b, "white")
			for k in 3:
				var a := TAU * k / 3.0 + 0.3
				var pos := Vector3(cos(a) * 0.07, TOP + 0.035, sin(a) * 0.07)
				_ball(G, b, "wood", pos, 0.055, Vector3(1, 0.65, 1))
				_ball(G, b, "red", pos + Vector3(0, 0.0, 0.05), 0.015)
				_ball(G, b, "white", pos + Vector3(0, 0.03, 0), 0.035, Vector3(1, 0.3, 1))
			var tp := Vector3(0, TOP + 0.085, 0)
			_ball(G, b, "wood", tp, 0.055, Vector3(1, 0.65, 1))
			_ball(G, b, "white", tp + Vector3(0, 0.03, 0), 0.035, Vector3(1, 0.3, 1))
			_ball(G, b, "red", tp + Vector3(0, 0.0, 0.05), 0.015)
	return b
