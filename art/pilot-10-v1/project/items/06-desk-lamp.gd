## 06 desk lamp: original small tabletop prop. Cream puck base, wood post, ball elbow,
## short arm, sage dome shade as ONE lathe shell (outside, lip, inside) tilted to face
## forward-down, warm emissive bulb. Origin = xz bounds center (base sits 0.085 behind it).
const MANIFEST := {
	"asset_id": "06-desk-lamp", "target_name": "Desk lamp", "anchor": "ground",
	"size_class": "small", "tabletop_eligible": true,
	"footprint": {"shape": "circle", "diameter": 0.31, "collision_radius_recommendation": 0.18},
	"interaction": {"Light0": "light source position (bulb)"},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	G.puck(b, "cream", 0.12, 0.055, 0.025, Transform3D(Basis(), Vector3.ZERO), 28)
	G.rod(b, "wood", 0.03, 0.028, 0.31, Transform3D(Basis(), Vector3(0, 0.03, -0.02)), 12)
	var e := Vector3(0, 0.345, -0.02)
	b.add_mesh("wood", G.sphere(0.048, 6), Transform3D(Basis(), e))
	var axis := Vector3(0, cos(deg_to_rad(50)), -sin(deg_to_rad(50)))
	var apex := e + Vector3(0, 0.03, 0.09)
	G.rod_between(b, "wood", e, apex, 0.026, 10)
	var o := apex - axis * 0.13
	var basis := Basis(Vector3.RIGHT, axis, Vector3.RIGHT.cross(axis))
	var prof := PackedVector2Array()
	for k in 7:  # inside, apex -> rim
		var t := deg_to_rad(90.0 - 90.0 * k / 6.0)
		prof.append(Vector2(0.105 * cos(t), 0.11 * sin(t)))
	for k in 7:  # outside, rim -> apex
		var t := deg_to_rad(90.0 * k / 6.0)
		prof.append(Vector2(0.122 * cos(t), 0.13 * sin(t) - 0.004))
	G.lathe(b, "sage", prof, 24, Transform3D(basis, o))
	b.add_mesh("bulb", G.sphere(0.042, 6), Transform3D(basis, o + axis * 0.045))
	b.marker("Light0", o + axis * 0.045)
	b.scale_all(1.3)  # readability: tiny props are enlarged (contract small = 0.2-0.45 H)
	# Center the xz bounds on the origin (shade leans forward) so placing the origin at
	# a support center cannot overhang. Measured extent z -0.156..0.326 -> shift -0.085.
	b.offset_all(Vector3(0, 0, -0.085))
	return b
