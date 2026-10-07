## Wish bamboo in a pot: tall stalk with side twigs, leaf clusters and hanging paper strips.
const P := preload("res://kit/cozy_parts.gd")

static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(0.16, 0), Vector2(0.19, 0.24), Vector2(0.16, 0.25), Vector2(0.0, 0.23)])
	G.lathe(b, "wood_dark", prof, 20)
	P.bamboo(G, b, Vector3(0, 0.2, 0), Vector3(0.02, 1.3, 0), 0.035, 0.25)
	var twigs := [[0.55, 40.0], [0.75, 160.0], [0.95, 280.0], [1.1, 60.0], [1.25, 200.0]]
	var cols := ["pink", "butter", "pink", "butter", "pink"]
	for k in twigs.size():
		var y: float = twigs[k][0]
		var a := deg_to_rad(twigs[k][1])
		var dir := Vector3(cos(a), 0.35, sin(a)).normalized()
		var tip := Vector3(0, y, 0) + dir * 0.28
		G.rod_between(b, "bamboo", Vector3(0, y, 0), tip, 0.012, 6)
		for j in 3:
			var la := a + (j - 1) * 0.6
			G.egg(b, "leaf", 0.03, 0.09, 0.016, 0.0, 0.0, Transform3D(Basis(Vector3(-sin(la), 0, cos(la)), deg_to_rad(-60)), tip), 6, 10)
		b.add_mesh(cols[k], G.rounded_box(Vector3(0.05, 0.14, 0.012), 0.005, 1), Transform3D(Basis(Vector3.UP, -a), Vector3(0, y, 0) + dir * 0.17 + Vector3(0, -0.06, 0)))
	return b
