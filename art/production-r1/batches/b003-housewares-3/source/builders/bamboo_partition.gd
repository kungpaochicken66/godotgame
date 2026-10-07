## Bamboo partition: low wooden base with a row of bamboo poles of varied heights and two tie rails.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	b.add_mesh("wood_dark", G.rounded_box(Vector3(1.0, 0.08, 0.24), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.04, 0)))
	var hs := [1.25, 1.05, 1.35, 1.15, 1.3, 1.0, 1.2]
	for k in hs.size():
		var x := lerpf(-0.42, 0.42, k / 6.0)
		P.bamboo(G, b, Vector3(x, 0.05, 0), Vector3(x, hs[k], 0), 0.045, 0.28)
	for y in [0.35, 0.85]:
		G.rod_between(b, "bamboo_dark", Vector3(-0.47, y, 0.05), Vector3(0.47, y, 0.05), 0.016, 8)
	return b
