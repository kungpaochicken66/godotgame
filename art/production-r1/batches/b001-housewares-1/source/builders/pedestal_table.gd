## Round pedestal side table on a three-foot base; flat top = ONE support slot.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood_dark")
	var top_y: float = p.get("top_y", 0.8)
	var r: float = p.get("r", 0.33)
	G.puck(b, w, r, 0.05, 0.025, Transform3D(Basis(), Vector3(0, top_y - 0.05, 0)), 36)
	G.puck(b, w, 0.09, 0.05, 0.02, Transform3D(Basis(), Vector3(0, top_y - 0.09, 0)), 18)
	var prof := PackedVector2Array([Vector2(0, 0.1), Vector2(0.05, 0.1), Vector2(0.06, 0.2), Vector2(0.04, 0.4), Vector2(0.045, 0.6), Vector2(0.035, top_y - 0.06), Vector2(0, top_y - 0.06)])
	G.lathe(b, w, prof, 14)
	G.puck(b, w, 0.08, 0.1, 0.03, Transform3D(Basis(), Vector3(0, 0.04, 0)), 18)
	for k in 3:
		var a := TAU * k / 3.0
		var tip := Vector3(cos(a) * 0.25, 0.035, sin(a) * 0.25)
		G.rod_between(b, w, Vector3(0, 0.1, 0), tip, 0.028, 10)
		b.add_mesh(w, G.sphere(0.036, 5), Transform3D(Basis(), tip))
	b.marker("Support0", Vector3(0, top_y, 0))
	return b
