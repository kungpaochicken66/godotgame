## Decorative urn: one lathe profile (foot, belly, neck, open lip with dark interior) and two arc handles.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var body: String = p.get("body", "stone")
	var trim: String = p.get("trim", "gold")
	var foot := PackedVector2Array([Vector2(0, 0), Vector2(0.1, 0), Vector2(0.105, 0.02), Vector2(0.09, 0.04)])
	var belly: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0.09, 0.04), Vector2(0.07, 0.07), Vector2(0.13, 0.15), Vector2(0.165, 0.24), Vector2(0.16, 0.32), Vector2(0.12, 0.4), Vector2(0.095, 0.44)]), 4)
	var lip := PackedVector2Array([Vector2(0.095, 0.44), Vector2(0.11, 0.47), Vector2(0.135, 0.5), Vector2(0.125, 0.515), Vector2(0.1, 0.505)])
	var inner := PackedVector2Array([Vector2(0.1, 0.505), Vector2(0.085, 0.45), Vector2(0.0, 0.43)])
	G.lathe(b, trim, foot, 28)
	G.lathe(b, body, belly, 28)
	G.lathe(b, trim, lip, 28)
	G.lathe(b, "ink", inner, 28)
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * 0.1, 0.43, 0), Vector3(s * 0.19, 0.44, 0), Vector3(s * 0.225, 0.38, 0), Vector3(s * 0.2, 0.3, 0), Vector3(s * 0.155, 0.27, 0)]
		G.tube(b, trim, pts, 0.016, 3, 8)
	return b
