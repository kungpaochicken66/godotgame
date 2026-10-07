## Bamboo water slide for noodles: long split-bamboo trough sloping down on X-legs into a catch bowl.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var L := 1.9
	var hi := 0.86
	var lo := 0.52
	var tilt := atan2(hi - lo, L)
	# U-shaped trough section in (z, y), extruded along x then tilted.
	var u := PackedVector2Array()
	for k in 13:
		var a := deg_to_rad(180.0 + 180.0 * k / 12.0)
		u.append(Vector2(cos(a) * 0.09, sin(a) * 0.09))
	for k in range(12, -1, -1):
		var a := deg_to_rad(180.0 + 180.0 * k / 12.0)
		u.append(Vector2(cos(a) * 0.065, sin(a) * 0.065 + 0.004))
	var basis := Basis(Vector3.BACK, -tilt)
	var mid := Vector3(0, (hi + lo) * 0.5, 0)
	var trough = G.Builder.new()
	G.profile_x(trough, "bamboo", u, L, 0.012, 0.0)
	for m in trough.surfs:
		var s: Dictionary = trough.surfs[m]
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		for k in s.v.size():
			nv.append(basis * s.v[k] + mid)
			nn.append(basis * s.n[k])
		b.add(m, nv, nn, s.i)
	for k in 3:
		var x := lerpf(-L * 0.42, L * 0.42, k / 2.0)
		var y := lerpf(hi, lo, (x + L * 0.5) / L) - 0.09
		for s in [-1.0, 1.0]:
			P.bamboo(G, b, Vector3(x - 0.12, 0.0, s * 0.16), Vector3(x + 0.0, y + 0.02, -s * 0.03), 0.028, 0.25)
	var bowl := PackedVector2Array([Vector2(0, 0), Vector2(0.17, 0), Vector2(0.2, 0.2), Vector2(0.18, 0.21), Vector2(0.0, 0.17)])
	G.lathe(b, "wood_dark", bowl, 24, Transform3D(Basis(), Vector3(L * 0.5 + 0.12, 0.25, 0)))
	G.rod(b, "wood_dark", 0.06, 0.06, 0.26, Transform3D(Basis(), Vector3(L * 0.5 + 0.12, 0.0, 0)), 12)
	b.snap("ground", true)  # center the footprint (the catch bowl extends +x)
	return b
