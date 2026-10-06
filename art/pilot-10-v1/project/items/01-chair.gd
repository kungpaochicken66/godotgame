## 01 chair: REUSED baseline. Same construction/dimensions as the accepted lab chair
## B_procedural_chair (../project/scripts/build_models.gd _b_chair), ported to the kit
## API unchanged in shape; only a Seat0 marker is added. Not a new design.
const MANIFEST := {
	"asset_id": "01-chair", "target_name": "Rounded toy chair", "anchor": "ground",
	"size_class": "medium", "tabletop_eligible": false,
	"footprint": {"shape": "box", "size_xz": [0.54, 0.50], "collision_radius_recommendation": 0.38},
	"interaction": {"Seat0": "sit, facing +z"},
	"reuse": "geometry reused from tools/opus-model-lab-20261006/models/B_procedural_chair.glb builder",
}

static func build(G) -> Object:
	var b = G.Builder.new()
	var lx := 0.2
	var fz := 0.18
	var bz := -0.19
	for x in [-lx, lx]:
		G.rod(b, "wood", 0.05, 0.055, 0.44, Transform3D(Basis(), Vector3(x, 0, fz)), 12)
		G.rod(b, "wood", 0.05, 0.05, 0.98, Transform3D(Basis(), Vector3(x, 0, bz)), 12)
		b.add_mesh("wood", G.sphere(0.068, 6), Transform3D(Basis(), Vector3(x, 1.0, bz)))
		G.rod(b, "wood", 0.026, 0.026, fz - bz, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x, 0.15, bz)), 10, 0.5)
	b.add_mesh("wood", G.rounded_box(Vector3(0.52, 0.08, 0.5), 0.035, 2), Transform3D(Basis(), Vector3(0, 0.42, -0.005)))
	G.pillow(b, "cream", Vector3(0.48, 0.13, 0.47), 0.32, 0.28, Transform3D(Basis(), Vector3(0, 0.495, 0.0)), 10, 24)
	G.bevel_slab(b, "sage", G.scallop_top(0.42, 0.30, 0.07), 0.065, 0.024, Transform3D(Basis(), Vector3(0, 0.62, bz)))
	b.marker("Seat0", Vector3(0, 0.56, 0.02))
	return b
