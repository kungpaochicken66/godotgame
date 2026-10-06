## 03 single bed: original. Four rod posts with ball finials, scalloped sage headboard
## (one beveled outline), low footboard, rails, puffy cream mattress, sage blanket with a
## cream fold, pillow. Mattress (1.56) fits a lying child (H = 1.30).
const MANIFEST := {
	"asset_id": "03-bed", "target_name": "Single bed", "anchor": "ground",
	"size_class": "large", "tabletop_eligible": false,
	"footprint": {"shape": "box", "size_xz": [0.98, 1.74], "collision_radius_recommendation": 0.85},
	"interaction": {"Sleep0": "lie down; head toward -z (headboard)"},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var hx := 0.46
	var hz := 0.82
	for x in [-hx, hx]:
		G.rod(b, "wood", 0.06, 0.06, 0.92, Transform3D(Basis(), Vector3(x, 0, -hz)), 12)
		b.add_mesh("wood", G.sphere(0.078, 6), Transform3D(Basis(), Vector3(x, 0.94, -hz)))
		G.rod(b, "wood", 0.06, 0.06, 0.58, Transform3D(Basis(), Vector3(x, 0, hz)), 12)
		b.add_mesh("wood", G.sphere(0.078, 6), Transform3D(Basis(), Vector3(x, 0.6, hz)))
		b.add_mesh("wood", G.rounded_box(Vector3(0.08, 0.16, 1.64), 0.035, 2), Transform3D(Basis(), Vector3(x * 0.96, 0.27, 0)))
	b.add_mesh("wood", G.rounded_box(Vector3(0.88, 0.08, 1.62), 0.03, 2), Transform3D(Basis(), Vector3(0, 0.26, 0)))
	G.bevel_slab(b, "sage", G.scallop_top(0.88, 0.46, 0.1), 0.07, 0.025, Transform3D(Basis(), Vector3(0, 0.36, -hz)))
	b.add_mesh("wood", G.rounded_box(Vector3(0.88, 0.24, 0.06), 0.025, 2), Transform3D(Basis(), Vector3(0, 0.38, hz)))
	G.pillow(b, "cream", Vector3(0.84, 0.17, 1.58), 0.35, 0.3, Transform3D(Basis(), Vector3(0, 0.37, 0)), 8, 24)
	G.pillow(b, "sage", Vector3(0.9, 0.09, 1.04), 0.4, 0.35, Transform3D(Basis(), Vector3(0, 0.45, 0.25)), 8, 24)
	G.pillow(b, "cream", Vector3(0.9, 0.07, 0.13), 0.6, 0.5, Transform3D(Basis(), Vector3(0, 0.475, -0.27)), 8, 20)
	G.pillow(b, "cream", Vector3(0.52, 0.12, 0.27), 0.6, 0.5, Transform3D(Basis(), Vector3(0, 0.5, -0.58)), 8, 20)
	b.marker("Sleep0", Vector3(0, 0.5, 0))
	return b
