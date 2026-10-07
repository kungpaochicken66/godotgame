## Three-panel folding screen in zigzag: wood frames with paper insets and feet.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: String = p.get("wood", "wood")
	var pw := 0.4
	var h := 1.2
	var hinge := Vector3(-pw * 1.5 * cos(deg_to_rad(25)), 0, 0)
	for k in 3:
		var yaw := deg_to_rad(25.0 if k % 2 == 0 else -25.0)
		var basis := Basis(Vector3.UP, yaw)
		var dir := Vector3(cos(yaw), 0, -sin(yaw))
		var c := hinge + dir * pw * 0.5
		var frame := Transform3D(basis, c)
		for s in [-1.0, 1.0]:
			G.rod_between(b, w, frame * Vector3(s * pw * 0.48, 0.0, 0), frame * Vector3(s * pw * 0.48, h, 0), 0.025, 10)
		for y in [0.1, h - 0.03]:
			b.add_mesh(w, G.rounded_box(Vector3(pw, 0.05, 0.05), 0.02, 1), frame * Transform3D(Basis(), Vector3(0, y, 0)))
		b.add_mesh("paper", G.rounded_box(Vector3(pw - 0.06, h - 0.2, 0.025), 0.01, 1), frame * Transform3D(Basis(), Vector3(0, h * 0.5 + 0.04, 0)))
		b.add_mesh(w, G.rounded_box(Vector3(pw - 0.06, 0.03, 0.03), 0.01, 1), frame * Transform3D(Basis(), Vector3(0, h * 0.55, 0)))
		hinge += dir * pw
	return b
