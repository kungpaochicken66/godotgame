## Arcade cabinet from one filleted side profile extruded across the width; glowing angled
## screen, marquee, control panel (joystick + buttons, or a key grid for the "keys" style).
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var body: String = p.get("body", "white")
	var acc: String = p.get("accent", "blue")
	var w := 0.62
	var prof := PackedVector2Array([Vector2(-0.33, 0), Vector2(0.25, 0), Vector2(0.25, 0.68), Vector2(0.42, 0.76), Vector2(0.42, 0.83), Vector2(0.2, 0.86), Vector2(0.1, 1.28), Vector2(0.22, 1.31), Vector2(0.22, 1.46), Vector2(-0.33, 1.46)])
	G.profile_x(b, body, prof, w, 0.03, 0.05)  # fillet > bevel inset
	b.add_mesh(acc, G.rounded_box(Vector3(w - 0.08, 0.12, 0.03), 0.012, 1), Transform3D(Basis(), Vector3(0, 1.385, 0.228)))
	b.add_mesh(acc, G.rounded_box(Vector3(w + 0.012, 0.05, 0.5), 0.02, 1), Transform3D(Basis(), Vector3(0, 0.03, -0.05)))
	var a := Vector2(0.2, 0.86)
	var c := Vector2(0.1, 1.28)
	var dir := (c - a).normalized()
	var nrm := Vector2(dir.y, -dir.x)
	var mid := (a + c) * 0.5 + nrm * 0.012
	P.screen(G, b, Vector3(0, mid.y, mid.x), 0.42, 0.3, Vector3(0, nrm.y, nrm.x).normalized())
	b.add_mesh("charcoal", G.rounded_box(Vector3(0.22, 0.2, 0.03), 0.015, 1), Transform3D(Basis(), Vector3(0, 0.4, 0.255)))
	if p.get("panel", "stick") == "keys":
		for i in 8:
			for j in 2:
				b.add_mesh("white" if body != "white" else "stone", G.rounded_box(Vector3(0.045, 0.02, 0.04), 0.008, 1), Transform3D(Basis(), Vector3(-0.19 + i * 0.054, 0.85, 0.27 + j * 0.06)))
	else:
		G.rod(b, "charcoal", 0.012, 0.012, 0.06, Transform3D(Basis(), Vector3(-0.15, 0.83, 0.32)), 8)
		b.add_mesh(acc, G.sphere(0.03, 5), Transform3D(Basis(), Vector3(-0.15, 0.9, 0.32)))
		for i in 3:
			for j in 2:
				b.add_mesh(acc if j == 0 else "gold", G.sphere(0.02, 4), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0.0 + i * 0.07, 0.848, 0.29 + j * 0.06)))
	return b
