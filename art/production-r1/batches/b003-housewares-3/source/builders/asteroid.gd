## Lumpy space rock: deterministic low-frequency noise on a squashed sphere, a few crater dimples.
static func _n(d: Vector3) -> float:
	return 0.09 * sin(d.x * 3.1 + 1.3) * sin(d.y * 2.7 + 0.4) + 0.06 * sin(d.z * 4.3 + d.x * 2.0) + 0.05 * sin(d.y * 5.0 - d.z * 3.0 + 2.0)

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var R: Vector3 = Vector3(0.44, 0.36, 0.4)
	var craters := [Vector3(0.5, 0.5, 0.7).normalized(), Vector3(-0.6, 0.3, 0.6).normalized(), Vector3(0.1, 0.9, -0.3).normalized(), Vector3(-0.3, -0.1, -0.9).normalized()]
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var d := Vector3(sin(th) * cos(ph), -cos(th), sin(th) * sin(ph))
		var k := 1.0 + _n(d)
		for c in craters:
			var t: float = d.dot(c)
			if t > 0.93:
				k -= 0.08 * (t - 0.93) / 0.07
		return Vector3(d.x * R.x, d.y * R.y, d.z * R.z) * k + Vector3(0, 0.36, 0)
	G.param_surface(b, p.get("rock", "stone"), f, 18, 32, Vector3(0, 0.36, 0))
	return b
