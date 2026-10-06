## 09 flower pot: original small tabletop prop. Lathe pot (terracotta wall + cream rolled
## rim + soil cap sharing end vertices), four broad egg leaves, two stems with one-piece
## five-lobed flower heads (single outline, no overlapping petals) and cream centers.
const MANIFEST := {
	"asset_id": "09-flower-pot", "target_name": "Flower pot", "anchor": "ground",
	"size_class": "small", "tabletop_eligible": true,
	"footprint": {"shape": "circle", "diameter": 0.33, "collision_radius_recommendation": 0.18},
	"interaction": {},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var body := PackedVector2Array([Vector2(0, 0)])
	body.append_array(G.arc(Vector2(0.095, 0.025), 0.025, -90, 0, 3))
	body.append(Vector2(0.13, 0.2))
	var rim := PackedVector2Array([Vector2(0.13, 0.2)])
	rim.append_array(G.arc(Vector2(0.135, 0.228), 0.028, -100, 90, 7))
	rim.append(Vector2(0.12, 0.256))
	rim.append(Vector2(0.115, 0.226))
	var soil := PackedVector2Array([Vector2(0.115, 0.226), Vector2(0.06, 0.232), Vector2(0.0, 0.236)])
	G.lathe(b, "terracotta", body, 24)
	G.lathe(b, "cream", rim, 24)
	G.lathe(b, "soil", soil, 24)
	for k in 4:
		var yaw := deg_to_rad(45.0 + 90.0 * k)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(40))
		G.egg(b, "leaf" if k % 2 == 0 else "leaf_light", 0.075, 0.11, 0.028, 0.25, 0.02, Transform3D(basis, Vector3(0, 0.19, 0)), 8, 12)
	var heads := [Vector3(-0.055, 0.47, 0.03), Vector3(0.07, 0.42, 0.04)]
	for h in heads:
		G.rod_between(b, "leaf", Vector3(h.x * 0.3, 0.2, 0), h, 0.011, 8)
		var face := Basis(Vector3.RIGHT, deg_to_rad(-20))  # tilt the flower toward the viewer
		G.bevel_slab(b, "rose", G.lobed_circle(0.065, 5, 0.32, 6), 0.03, 0.012, Transform3D(face, h))
		b.add_mesh("cream", G.sphere(0.024, 5), Transform3D(face.scaled(Vector3(1, 1, 0.6)), h + face.z * 0.014))
	b.scale_all(1.08)  # enlarged for readability, capped so height stays <= 0.45 H (0.585) per contract small class
	return b
