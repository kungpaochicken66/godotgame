## 02 round table: original. Thick rounded top with a FLAT, level usable top face
## (no baked decoration), under-apron disc, four chunky splayed-free legs fully under
## the top (physically plausible hidden legs). One support slot for one small prop.
const TOP_Y := 0.66
const MANIFEST := {
	"asset_id": "02-round-table", "target_name": "Round table", "anchor": "ground",
	"size_class": "large", "tabletop_eligible": false,
	"footprint": {"shape": "circle", "diameter": 1.0, "collision_radius_recommendation": 0.52},
	"support_surface": {"local_position": [0.0, TOP_Y, 0.0], "usable_size_xz": [0.56, 0.56], "max_items": 1,
		"accepts": "tabletop_eligible props only (e.g. 06-desk-lamp, 09-flower-pot)"},
	"interaction": {"Support0": "one small tabletop prop, origin placed here"},
}

static func build(G) -> Object:
	var b = G.Builder.new()
	# Top: flat-topped puck; flat region radius = 0.5 - 0.035 rim.
	G.puck(b, "wood", 0.5, 0.08, 0.035, Transform3D(Basis(), Vector3(0, TOP_Y - 0.08, 0)), 40)
	# Apron disc tucked under the top, legs plug into it.
	G.puck(b, "wood_dark", 0.36, 0.08, 0.03, Transform3D(Basis(), Vector3(0, TOP_Y - 0.14, 0)), 32)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		G.rod(b, "wood", 0.075, 0.08, TOP_Y - 0.1, Transform3D(Basis(), Vector3(cos(a) * 0.3, 0, sin(a) * 0.3)), 14)
	b.marker("Support0", Vector3(0, TOP_Y, 0))
	return b
