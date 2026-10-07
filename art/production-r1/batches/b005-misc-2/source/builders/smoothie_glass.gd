## Smoothie in a handled glass mug with a striped straw and a fruit slice on the rim.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var mug := PackedVector2Array([Vector2(0, 0), Vector2(0.075, 0), Vector2(0.085, 0.02), Vector2(0.09, 0.24), Vector2(0.08, 0.245), Vector2(0.078, 0.23), Vector2(0.0, 0.225)])
	G.lathe(b, p.get("drink", "butter"), mug, 24)
	G.tube(b, "white", [Vector3(0.085, 0.19, 0), Vector3(0.14, 0.18, 0), Vector3(0.14, 0.07, 0), Vector3(0.085, 0.06, 0)], 0.015, 3, 8)
	G.rod_between(b, "red", Vector3(-0.02, 0.15, 0.0), Vector3(-0.05, 0.33, -0.03), 0.009, 6)
	G.egg(b, p.get("fruit", "red"), 0.04, 0.05, 0.012, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-80)), Vector3(0.05, 0.24, 0.05)), 6, 10)
	return b
