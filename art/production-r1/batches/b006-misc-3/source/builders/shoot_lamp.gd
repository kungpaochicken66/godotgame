## Bamboo-shoot table lamp: layered pointed sheaths (stacked egg shells) glowing from inside, on a disc base.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "wood_dark", 0.13, 0.04, 0.015, Transform3D(Basis(), Vector3.ZERO), 22)
	var core: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0.03), Vector2(0.1, 0.03), Vector2(0.11, 0.15), Vector2(0.07, 0.35), Vector2(0.0, 0.48)]), 3)
	G.lathe(b, "bulb", core, 20)
	for k in 6:
		var a := TAU * k / 6.0
		var y := 0.04 + (k % 2) * 0.08
		G.egg(b, "wood" if k % 2 == 0 else "butter", 0.06, 0.18 - (k % 2) * 0.03, 0.025, -0.5, 0.0, Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, deg_to_rad(10)), Vector3(sin(a) * 0.07, y, cos(a) * 0.07)), 6, 10)
	b.marker("Light0", Vector3(0, 0.25, 0))
	return b
