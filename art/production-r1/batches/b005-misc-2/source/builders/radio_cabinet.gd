## Arched wooden table radio: one arched outline body, cloth grille with ribs, two knobs and a dial.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood_dark")
	var body := PackedVector2Array([Vector2(-0.17, 0.0), Vector2(0.17, 0.0), Vector2(0.17, 0.25)])
	body.append_array(G.arc(Vector2(0, 0.25), 0.17, 0, 180, 16).slice(1, 16))
	body.append(Vector2(-0.17, 0.25))
	G.bevel_slab(b, w, G.rounded_polygon(body, 0.02, 2), 0.2, 0.025, Transform3D(Basis(), Vector3(0, 0.0, 0)))
	var grille := PackedVector2Array([Vector2(-0.11, 0.14), Vector2(0.11, 0.14), Vector2(0.11, 0.26)])
	grille.append_array(G.arc(Vector2(0, 0.26), 0.11, 0, 180, 12).slice(1, 12))
	grille.append(Vector2(-0.11, 0.26))
	G.bevel_slab(b, "cream", grille, 0.02, 0.006, Transform3D(Basis(), Vector3(0, 0, 0.1)))
	for k in 5:
		var x := -0.08 + k * 0.04
		b.add_mesh(w, G.rounded_box(Vector3(0.012, 0.18, 0.012), 0.004, 1), Transform3D(Basis(), Vector3(x, 0.24, 0.112)))
	for x in [-0.09, 0.09]:
		P.knob(G, b, "gold", Vector3(x, 0.07, 0.11), 0.022)
	G.puck(b, "butter", 0.03, 0.012, 0.004, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.07, 0.1)), 16)
	return b
