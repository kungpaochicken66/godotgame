## 05 open shelf: original. Four rod posts with finials, four rounded shelves, two back
## rails, a few baked books (decor, not slots). Declares NO support surface.
const MANIFEST := {
	"asset_id": "05-open-shelf", "target_name": "Open shelf", "anchor": "ground",
	"size_class": "large", "tabletop_eligible": false,
	"footprint": {"shape": "box", "size_xz": [0.98, 0.38], "collision_radius_recommendation": 0.45},
	"interaction": {},
	"notes": "baked books are decoration; shelves are intentionally not support surfaces",
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var hx := 0.44
	var hz := 0.14
	var h := 1.28
	for x in [-hx, hx]:
		for z in [-hz, hz]:
			G.rod(b, "wood", 0.045, 0.045, h, Transform3D(Basis(), Vector3(x, 0, z)), 12)
			b.add_mesh("wood", G.sphere(0.062, 6), Transform3D(Basis(), Vector3(x, h + 0.02, z)))
	for y in [0.12, 0.47, 0.82, 1.16]:
		b.add_mesh("wood", G.rounded_box(Vector3(0.94, 0.05, 0.34), 0.02, 2), Transform3D(Basis(), Vector3(0, y, 0)))
	for y in [0.65, 1.0]:
		G.rod_between(b, "wood", Vector3(-hx, y, -hz), Vector3(hx, y, -hz), 0.022, 8)
	# Books: shelf 3 upright row, shelf 1 small stack.
	var books := [["sage", 0.07, 0.24], ["cream", 0.06, 0.21], ["terracotta", 0.075, 0.25], ["sage_dark", 0.06, 0.2]]
	var x := -0.36
	for bk in books:
		b.add_mesh(bk[0], G.rounded_box(Vector3(bk[1], bk[2], 0.2), 0.015, 1), Transform3D(Basis(), Vector3(x + bk[1] * 0.5, 0.845 + bk[2] * 0.5, 0.0)))
		x += bk[1] + 0.008
	b.add_mesh("terracotta", G.rounded_box(Vector3(0.09, 0.22, 0.2), 0.015, 1), Transform3D(Basis(Vector3.BACK, deg_to_rad(-18)), Vector3(x + 0.08, 0.845 + 0.105, 0.0)))
	b.add_mesh("sage", G.rounded_box(Vector3(0.3, 0.05, 0.22), 0.015, 1), Transform3D(Basis(), Vector3(0.18, 0.17, 0.0)))
	b.add_mesh("cream", G.rounded_box(Vector3(0.27, 0.05, 0.2), 0.015, 1), Transform3D(Basis(Vector3.UP, 0.1), Vector3(0.18, 0.218, 0.0)))
	return b
