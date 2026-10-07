## Sports ball resting on the floor: sphere split into colored gores (beach ball) or a
## single color with seam tubes (basketball). Origin at the contact point.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var r: float = p.get("r", 0.17)
	var gores: Array = p.get("gores", [])
	if gores.size() > 0:
		var n := gores.size()
		for k in n:
			var f := func(u: float, v: float) -> Vector3:
				var th := u * PI
				var ph := (k + v) * TAU / n
				return Vector3(sin(th) * cos(ph), -cos(th), sin(th) * sin(ph)) * r + Vector3(0, r, 0)
			G.param_surface(b, gores[k], f, 12, 4, Vector3(0, r, 0))
		G.puck(b, "white", r * 0.2, r * 0.06, r * 0.02, Transform3D(Basis(), Vector3(0, 2.0 * r - r * 0.03, 0)), 16)
	else:
		b.add_mesh(p.get("color", "terracotta"), G.sphere(r, 12), Transform3D(Basis(), Vector3(0, r, 0)))
		var seams := []
		for k in 24:
			var a := TAU * k / 24.0
			seams.append(Vector3(cos(a) * r * 1.005, r + sin(a) * r * 1.005, 0))
		G.tube(b, "ink", seams, r * 0.03, 1, 6, true)
		var s2 := []
		for k in 24:
			var a := TAU * k / 24.0
			s2.append(Vector3(0, r + sin(a) * r * 1.005, cos(a) * r * 1.005))
		G.tube(b, "ink", s2, r * 0.03, 1, 6, true)
	return b
