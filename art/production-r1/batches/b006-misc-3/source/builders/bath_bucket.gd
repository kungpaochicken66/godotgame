## Bath bucket: thick-walled round tub (single lathe: outside, rim, inside, floor), with a towel draped on the rim.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("color", "white")
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(0.15, 0), Vector2(0.17, 0.02), Vector2(0.19, 0.26), Vector2(0.18, 0.275), Vector2(0.165, 0.265), Vector2(0.148, 0.04), Vector2(0.0, 0.035)])
	G.lathe(b, c, prof, 32)
	G.pillow(b, p.get("towel", "teal"), Vector3(0.12, 0.05, 0.18), 0.5, 0.5, Transform3D(Basis(Vector3.BACK, deg_to_rad(-60)), Vector3(0.18, 0.24, 0.0)), 8, 16)
	return b
