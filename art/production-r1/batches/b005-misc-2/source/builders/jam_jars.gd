## Three jam jars (two side by side, one stacked) with gingham-colored cloth lids tied with string.
static func _jar(G, b, pos: Vector3, fill: String, lid: String) -> void:
	var jar: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0), Vector2(0.055, 0), Vector2(0.065, 0.03), Vector2(0.065, 0.09), Vector2(0.055, 0.11), Vector2(0.0, 0.112)]), 3)
	G.lathe(b, fill, jar, 20, Transform3D(Basis(), pos))
	var cap := PackedVector2Array([Vector2(0, 0.105), Vector2(0.075, 0.1), Vector2(0.07, 0.125), Vector2(0.03, 0.14), Vector2(0.0, 0.142)])
	G.lathe(b, lid, cap, 20, Transform3D(Basis(), pos))
	G.puck(b, "white", 0.06, 0.012, 0.004, Transform3D(Basis(), pos + Vector3(0, 0.095, 0)), 18)

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var fill: String = p.get("fill", "red")
	_jar(G, b, Vector3(-0.07, 0, 0.02), fill, "pink")
	_jar(G, b, Vector3(0.07, 0, -0.01), fill, "white")
	_jar(G, b, Vector3(0.0, 0.142, 0.005), fill, "pink")
	return b
