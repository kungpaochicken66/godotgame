## Thick cut bamboo segment with a slanted opening and a warm glow inside, on a small base.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var r: float = p.get("r", 0.15)
	var h: float = p.get("h", 0.8)
	G.puck(b, "wood_dark", r * 1.45, 0.05, 0.02, Transform3D(Basis(), Vector3.ZERO), 24)
	var f := func(u: float, v: float) -> Vector3:
		var a := v * TAU
		var top := h - h * 0.22 * (0.5 + 0.5 * cos(a))
		return Vector3(cos(a) * r, lerpf(0.04, top, u), sin(a) * r)
	G.param_surface(b, "bamboo", f, 6, 24, Vector3(0, 0.4, 0))
	var g := func(u: float, v: float) -> Vector3:
		var a := v * TAU
		var top := h - h * 0.22 * (0.5 + 0.5 * cos(a))
		return Vector3(cos(a) * r * (1.0 - u), top, sin(a) * r * (1.0 - u)) if u < 0.999 else Vector3(0, h - h * 0.11, 0)
	G.param_surface(b, "bulb", g, 3, 24, Vector3(0, 0.3, 0))
	var cap := func(u: float, v: float) -> Vector3:
		var a := v * TAU
		return Vector3(cos(a) * r * (1.0 - u), 0.04, sin(a) * r * (1.0 - u))
	G.param_surface(b, "bamboo", cap, 2, 24, Vector3(0, 0.3, 0))
	for y in [h * 0.35, h * 0.7]:
		G.puck(b, "bamboo_dark", r * 1.08, 0.04, 0.012, Transform3D(Basis(), Vector3(0, y, 0)), 24)
	G.egg(b, "leaf", r * 0.33, r * 0.73, 0.015, 0.2, 0.02, Transform3D(Basis(Vector3.BACK, deg_to_rad(-40)), Vector3(r * 0.8, h * 0.62, 0)), 6, 10)
	if p.get("candle", false):
		G.rod(b, "white", r * 0.35, r * 0.35, h * 0.3, Transform3D(Basis(), Vector3(0, h - h * 0.15, 0)), 12)
		G.egg(b, "bulb", r * 0.15, r * 0.25, r * 0.15, 0.0, 0.0, Transform3D(Basis(), Vector3(0, h + h * 0.15, 0)), 5, 8)
		b.marker("Light0", Vector3(0, h + h * 0.2, 0))
	else:
		b.marker("Light0", Vector3(0, h - 0.12, 0))
	return b
