## Builds every asset of a batch spec: godot --headless --path . --script res://build_batch.gd -- <spec.json> <out_models_dir> [asset_id...]
## Each asset: res://builders/<archetype>.gd provides `static func build(G, p: Dictionary) -> Object` (a cozy_geo Builder).
## Writes <asset_id>.glb and <asset_id>.build.json (tris, export error, generator ms, markers).
extends SceneTree
const G := preload("res://kit/cozy_geo.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var out: String = a[1]
	var only := a.slice(2)
	DirAccess.make_dir_recursive_absolute(out)
	for asset in spec["assets"]:
		var id: String = asset["asset_id"]
		if only.size() > 0 and not only.has(id):
			continue
		var t0 := Time.get_ticks_msec()
		var arch: GDScript = load("res://builders/%s.gd" % asset["archetype"])
		var b = arch.build(G, asset.get("params", {}))
		# Settle on the declared anchor plane; the applied offset is recorded (a large one
		# means the builder's origin is wrong; markers move too, and G8 would catch a
		# support surface that no longer matches its manifest).
		var before: AABB = b.bounds()
		b.snap(asset["manifest"].get("anchor", "ground"), asset["manifest"].get("anchor", "ground") != "ground")
		var after: AABB = b.bounds()
		var snap_offset := after.position - before.position
		var r := G.export_glb(b, id, "%s/%s.glb" % [out, id], "Lantern Lane nookipedia-model-production. Original procedural geometry (cozy-game-modeling kit); reference used for function only.")
		r["generator_ms"] = Time.get_ticks_msec() - t0
		r["archetype"] = asset["archetype"]
		r["snap_offset"] = [snap_offset.x, snap_offset.y, snap_offset.z]
		r["markers"] = {}
		for m in b.markers:
			var p: Vector3 = b.markers[m].origin
			r["markers"][m] = [p.x, p.y, p.z]
		var f := FileAccess.open("%s/%s.build.json" % [out, id], FileAccess.WRITE)
		f.store_string(JSON.stringify(r, "  "))
		print("%s tris=%d err=%d ms=%d" % [id, r.tris, r.err, r.generator_ms])
	quit()
