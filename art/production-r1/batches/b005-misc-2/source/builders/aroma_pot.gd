## Ceramic aroma burner: bowl on a lantern body with an opening showing a small glowing candle.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var c: String = p.get("glaze", "white")
	var body: PackedVector2Array = G.smooth_path(PackedVector2Array([Vector2(0, 0), Vector2(0.1, 0), Vector2(0.11, 0.08), Vector2(0.095, 0.18), Vector2(0.085, 0.2), Vector2(0.0, 0.2)]), 3)
	G.lathe(b, c, body, 24)
	var bowl := PackedVector2Array([Vector2(0, 0.19), Vector2(0.08, 0.19), Vector2(0.13, 0.24), Vector2(0.14, 0.27), Vector2(0.125, 0.272), Vector2(0.11, 0.25), Vector2(0.0, 0.235)])
	G.lathe(b, c, bowl, 24)
	G.puck(b, "blue", 0.1, 0.006, 0.002, Transform3D(Basis(), Vector3(0, 0.236, 0)), 20)
	G.bevel_slab(b, "charcoal", G.rounded_rect(0.08, 0.09, 0.035, 3), 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0.07, 0.1)))
	G.puck(b, "bulb", 0.022, 0.03, 0.008, Transform3D(Basis(), Vector3(0, 0.03, 0.1)), 12)
	b.marker("Light0", Vector3(0, 0.06, 0.1))
	return b
