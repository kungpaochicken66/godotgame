## Builds pilot items: godot --headless --path . --script res://build_items.gd -- <out_dir> <item_id>...
## Each res://items/<id>.gd provides `static func build(G) -> Builder` and `const MANIFEST`.
## Writes <out_dir>/<id>.glb and <out_dir>/<id>.build.json (tris, export error, manifest).
extends SceneTree
const G := preload("res://kit/cozy_geo.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for id in args.slice(1):
		var t0 := Time.get_ticks_msec()
		var item: GDScript = load("res://items/%s.gd" % id)
		var b = item.build(G)
		var man: Dictionary = item.MANIFEST.duplicate(true)
		var r := G.export_glb(b, id, "%s/%s.glb" % [out, id], man.get("copyright", "Lantern Lane cozy pilot-10 v1 (2026-10-06). Original procedural geometry."))
		r["generator_ms"] = Time.get_ticks_msec() - t0
		r["manifest"] = man
		r["markers"] = {}
		for m in b.markers:
			var p: Vector3 = b.markers[m].origin
			r["markers"][m] = [p.x, p.y, p.z]
		var f := FileAccess.open("%s/%s.build.json" % [out, id], FileAccess.WRITE)
		f.store_string(JSON.stringify(r, "  "))
		print("%s tris=%d err=%d ms=%d" % [id, r.tris, r.err, r.generator_ms])
	quit()
