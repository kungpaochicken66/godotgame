## 07 wall clock: original. Rounded-square sage body (one beveled outline), cream face
## disc, 12 terracotta hour dots, two hands, center cap. WALL anchor: origin = center of
## the back plane (z = 0), body extends to +z. Not placeable in the game yet (contract:
## ground-only placement), recorded for future wall support.
const MANIFEST := {
	"asset_id": "07-wall-clock", "target_name": "Wall clock", "anchor": "wall",
	"size_class": "small", "tabletop_eligible": false,
	"footprint": {"shape": "wall_rect", "size_xy": [0.44, 0.44], "collision_radius_recommendation": 0.0},
	"wall_mount": {"recommended_center_height": 1.5, "back_plane_z": 0.0},
	"integration_status": "recorded_not_placeable (contract v1 is ground-only)",
	"interaction": {},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var t := 0.1
	G.bevel_slab(b, "sage", G.rounded_rect(0.44, 0.44, 0.13, 5), t, 0.035, Transform3D(Basis(), Vector3(0, 0, t * 0.5)))
	var face_basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)  # lathe +y -> world +z
	G.puck(b, "cream", 0.17, 0.03, 0.012, Transform3D(face_basis, Vector3(0, 0, t - 0.012)), 32)
	var fz := t + 0.018
	for k in 12:
		var a := TAU * k / 12.0
		b.add_mesh("terracotta", G.sphere(0.016 if k % 3 == 0 else 0.012, 4), Transform3D(Basis().scaled(Vector3(1, 1, 0.6)), Vector3(sin(a) * 0.135, cos(a) * 0.135, fz)))
	b.add_mesh("terracotta", G.rounded_box(Vector3(0.026, 0.12, 0.014), 0.007, 1), Transform3D(Basis(Vector3.BACK, deg_to_rad(-50)), Vector3(0.045, 0.04, fz + 0.004)))
	b.add_mesh("ink", G.rounded_box(Vector3(0.02, 0.085, 0.012), 0.006, 1), Transform3D(Basis(Vector3.BACK, deg_to_rad(150)), Vector3(-0.02, -0.036, fz + 0.002)))
	b.add_mesh("sage", G.sphere(0.022, 5), Transform3D(Basis().scaled(Vector3(1, 1, 0.7)), Vector3(0, 0, fz + 0.008)))
	return b
