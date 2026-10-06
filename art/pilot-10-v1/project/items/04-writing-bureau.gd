## 04 writing bureau: original. One beveled body from a filleted slant-front side
## profile (extruded across the width), sage writing flap on the slope, two sage
## drawers, knobs, bun feet. Slope is not a support surface.
const MANIFEST := {
	"asset_id": "04-writing-bureau", "target_name": "Writing bureau", "anchor": "ground",
	"size_class": "large", "tabletop_eligible": false,
	"footprint": {"shape": "box", "size_xz": [0.78, 0.46], "collision_radius_recommendation": 0.38},
	"interaction": {},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var w := 0.78
	var fz := 0.225
	var lift := 0.07
	# Side profile in (u = -z, y), CCW.
	var prof := PackedVector2Array([Vector2(-fz, lift), Vector2(fz, lift), Vector2(fz, 0.95), Vector2(0.03, 0.95), Vector2(-fz, 0.53)])
	var side := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT)
	G.bevel_slab(b, "wood", G.rounded_polygon(prof, 0.06, 4), w, 0.04, Transform3D(side, Vector3.ZERO))
	# Writing flap on the slope.
	var a := Vector2(fz, 0.53)
	var c := Vector2(-0.03, 0.95)
	var dir := (c - a).normalized()
	var nrm := Vector2(dir.y, -dir.x)  # outward (front-up) normal of the slope in (z, y)
	var mid := (a + c) * 0.5 + nrm * 0.012
	var fb := Basis(Vector3.RIGHT, Vector3(0, dir.y, dir.x), Vector3(0, nrm.y, nrm.x))
	b.add_mesh("sage", G.rounded_box(Vector3(w - 0.12, (c - a).length() - 0.1, 0.045), 0.02, 2), Transform3D(fb, Vector3(0, mid.y, mid.x)))
	b.add_mesh("wood", G.sphere(0.035, 6), Transform3D(fb.scaled(Vector3(1, 1, 0.75)), Vector3(0, mid.y, mid.x) - fb.y * 0.1 + fb.z * 0.025))
	for y in [0.19, 0.4]:
		b.add_mesh("sage", G.rounded_box(Vector3(w - 0.12, 0.17, 0.05), 0.022, 2), Transform3D(Basis(), Vector3(0, y, fz + 0.005)))
		b.add_mesh("wood", G.sphere(0.035, 6), Transform3D(Basis().scaled(Vector3(1, 1, 0.75)), Vector3(0, y, fz + 0.04)))
	for x in [-w * 0.5 + 0.11, w * 0.5 - 0.11]:
		for z in [-0.13, 0.13]:
			G.rod(b, "wood", 0.05, 0.045, lift + 0.03, Transform3D(Basis(), Vector3(x, 0, z)), 12, 0.55)
	return b
