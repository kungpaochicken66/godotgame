## Smoke test: every cozy_geo helper builds watertight-ish geometry and exports.
## godot --headless --path <project> --script <kit>/smoke_test.gd -- <out_dir>
extends SceneTree
const G := preload("cozy_geo.gd")
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var b := G.Builder.new()
	b.add_mesh("wood", G.rounded_box(Vector3(0.4, 0.2, 0.3), 0.05), Transform3D(Basis(), Vector3(0, 0.1, 0)))
	G.rod(b, "wood", 0.04, 0.04, 0.3, Transform3D(Basis(), Vector3(0.5, 0, 0)))
	G.rod_between(b, "wood", Vector3(0.5, 0.1, 0), Vector3(0.8, 0.1, 0.2), 0.02)
	G.puck(b, "cream", 0.15, 0.05, 0.02, Transform3D(Basis(), Vector3(-0.5, 0, 0)))
	G.egg(b, "leaf", 0.05, 0.1, 0.03, 0.3, 0.02, Transform3D(Basis(), Vector3(-0.5, 0.05, 0)))
	G.pillow(b, "cream", Vector3(0.3, 0.1, 0.3), 0.3, 0.3, Transform3D(Basis(), Vector3(0, 0.25, 0)))
	G.bevel_slab(b, "sage", G.scallop_top(0.4, 0.3, 0.07), 0.05, 0.02, Transform3D(Basis(), Vector3(0, 0, -0.5)))
	G.bevel_slab(b, "rose", G.lobed_circle(0.1, 5, 0.35), 0.03, 0.01, Transform3D(Basis(), Vector3(0.5, 0, -0.5)))
	G.bevel_slab(b, "sage", G.rounded_rect(0.3, 0.3, 0.08), 0.06, 0.02, Transform3D(Basis(), Vector3(-0.5, 0.15, -0.5)))
	G.bevel_slab(b, "wood", G.annular_sector(0.5, 0.7, 30, 150), 0.05, 0.02, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, 0.5)))
	b.marker("Seat0", Vector3(0, 0.3, 0))
	var r := G.export_glb(b, "smoke", out + "/smoke.glb", "smoke test")
	print("smoke tris=%d err=%d" % [r.tris, r.err])
	quit()
