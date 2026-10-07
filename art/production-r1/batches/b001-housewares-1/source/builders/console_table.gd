## Narrow console table with two drawers; flat top declared as ONE support slot.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood_dark")
	var top_y := 0.73
	b.add_mesh(w, G.rounded_box(Vector3(1.0, 0.05, 0.42), 0.02, 2), Transform3D(Basis(), Vector3(0, top_y - 0.025, 0)))
	b.add_mesh(w, G.rounded_box(Vector3(0.92, 0.13, 0.36), 0.025, 2), Transform3D(Basis(), Vector3(0, top_y - 0.11, 0)))
	for s in [-1.0, 1.0]:
		P.panel(G, b, "wood", Vector3(s * 0.22, top_y - 0.11, 0.18), 0.36, 0.08, 0.02, 0.012)
		P.knob(G, b, "gold", Vector3(s * 0.22, top_y - 0.11, 0.205), 0.018)
		for z in [-0.14, 0.14]:
			G.rod(b, w, 0.026, 0.04, top_y - 0.12, Transform3D(Basis(), Vector3(s * 0.42, 0, z)), 12)
	b.marker("Support0", Vector3(0, top_y, 0))
	return b
