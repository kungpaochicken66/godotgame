## Flower wreath: twig/leaf hoop (closed tubes) with leaf clusters and one-piece lobed flower heads.
## p: flower (material), petals (lobes), depth (petal notch), n (flower count), center, ring, extra.
## WALL anchor: back plane z = 0.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var R: float = p.get("R", 0.19)
	var ring: String = p.get("ring", "wood_dark")
	for k in 3:
		var pts := []
		for j in 18:
			var a := TAU * j / 18.0 + k * 0.3
			var rr := R + (k - 1) * 0.018
			pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0.035 + (k % 2) * 0.012))
		G.tube(b, ring, pts, 0.022, 1, 6, true)
	for j in 14:
		var a := TAU * j / 14.0
		G.egg(b, "leaf" if j % 2 == 0 else "leaf_light", 0.03, 0.055, 0.012, 0.1, 0.0, Transform3D(Basis(Vector3.BACK, a + 1.2) * Basis(Vector3.RIGHT, 0.3), Vector3(cos(a) * (R + 0.03), sin(a) * (R + 0.03), 0.05)), 4, 6)
	var n: int = p.get("n", 5)
	var span: float = p.get("span", TAU)
	var start: float = p.get("start", -0.3)
	for j in n:
		var a := start + span * (j + 0.5) / n
		var fr: float = p.get("size", 0.055) * (1.0 if j % 2 == 0 else 0.85)
		var c := Vector3(cos(a) * R, sin(a) * R, 0.07)
		var mat: String = p.get("flower", "pink") if j % 3 != 2 or not p.has("flower2") else p["flower2"]
		G.bevel_slab(b, mat, G.lobed_circle(fr, p.get("petals", 5), p.get("depth", 0.3), 4), 0.025, 0.009, Transform3D(Basis(Vector3.BACK, a), c), 1)
		b.add_mesh(p.get("center", "butter"), G.sphere(fr * 0.3, 5), Transform3D(Basis().scaled(Vector3(1, 1, 0.6)), c + Vector3(0, 0, 0.014)))
	if p.has("bow"):
		for s in [-1.0, 1.0]:
			G.egg(b, p["bow"], 0.04, 0.06, 0.015, 0.2, 0.0, Transform3D(Basis(Vector3.BACK, s * deg_to_rad(-70)), Vector3(0, R + 0.02, 0.08)), 6, 10)
		b.add_mesh(p["bow"], G.sphere(0.025, 5), Transform3D(Basis(), Vector3(0, R + 0.02, 0.085)))
	if p.has("eggs"):
		var cols: Array = p["eggs"]
		for j in cols.size():
			var a := PI + 0.4 + j * 0.45
			G.egg(b, cols[j], 0.03, 0.04, 0.025, 0.0, 0.0, Transform3D(Basis(Vector3.BACK, a - PI / 2), Vector3(cos(a) * R, sin(a) * R, 0.06)), 6, 10)
	return b
