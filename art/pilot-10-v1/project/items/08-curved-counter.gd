## 08 curved counter: original. Plan-view annular sectors (bowed toward +z, the
## customer side) extruded vertically: wood base band on bun feet, sage body, deep
## wood top. No baked decoration; no support slot (too narrow for the eligible props).
const R := 1.05     # plan radius of the arc center line
const TOP_Y := 0.8
const SPAN := 64.0  # degrees
const MANIFEST := {
	"asset_id": "08-curved-counter", "target_name": "Curved counter", "anchor": "ground",
	"size_class": "large", "tabletop_eligible": false,
	"footprint": {"shape": "arc_band", "size_xz": [1.38, 0.62], "collision_radius_recommendation": 0.62},
	"support_surface": null,
	"support_note": "not declared: the flat top band allows only ~0.32 x 0.32 inside both curved edges, smaller than both pilot tabletop props (0.32 x 0.39 lamp, 0.39 x 0.39 pot)",
	"interaction": {"Front0": "customer side faces +z (documented, no marker)"},
}

static func _sector(G, b, mat: String, r_in: float, r_out: float, y0: float, h: float, bevel: float) -> void:
	# local (x, y) -> world (x, -z); local z (thickness) -> world +y. Arc centered on +z.
	var basis := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	var o: PackedVector2Array = G.annular_sector(r_in, r_out, 270.0 - SPAN * 0.5, 270.0 + SPAN * 0.5, 28)
	G.bevel_slab(b, mat, o, h, bevel, Transform3D(basis, Vector3(0, y0 + h * 0.5, -R)))

static func build(G) -> Object:
	var b = G.Builder.new()
	_sector(G, b, "wood", R - 0.17, R + 0.17, 0.06, 0.09, 0.03)
	_sector(G, b, "sage", R - 0.15, R + 0.15, 0.13, TOP_Y - 0.19, 0.04)
	_sector(G, b, "wood", R - 0.22, R + 0.2, TOP_Y - 0.075, 0.075, 0.03)
	for a in [-SPAN * 0.36, SPAN * 0.36]:
		for rr in [R - 0.1, R + 0.1]:
			var ang := deg_to_rad(90.0 + a)
			G.rod(b, "wood", 0.05, 0.045, 0.1, Transform3D(Basis(), Vector3(cos(ang) * rr, 0, sin(ang) * rr - R)), 12, 0.55)
	return b
