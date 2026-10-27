## Renders the Lantern Lane Apple TV brand art (tv/brand/src/*.svg) to the PNG sizes of tv/brand/brand.json
## with Godot's own SVG renderer, and checks each image: exact size, the back layer opaque, the upper
## layers transparent around their art. Writes tv/brand/png/ and tv/brand/png/manifest.json (SHA-256).
##   scripts/godot.sh --headless --path game -s res://tests/tv_brand_rasterize.gd
extends SceneTree



func _init() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../tv/brand").simplify_path()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("brand.json")))
	DirAccess.make_dir_recursive_absolute(root.path_join("png"))
	var manifest := {}
	var failures := 0
	for set_name in spec:
		var entry: Dictionary = spec[set_name]
		var layers: Array = entry.get("layers", [""])
		for scale in entry["sizes"]:
			var size: Array = entry["sizes"][scale]
			for layer in layers:
				var src_name: String = ("app_icon_%s.svg" % layer) if layer != "" else ("%s.svg" % set_name)
				var text := FileAccess.get_file_as_string(root.path_join("src").path_join(src_name))
				var base := _svg_width(text)
				var img := Image.new()
				var err := img.load_svg_from_string(text, float(size[0]) / base)
				var out_name := "%s%s_%s.png" % [set_name, ("_" + layer) if layer != "" else "", scale]
				var ok := err == OK and img.get_width() == int(size[0]) and img.get_height() == int(size[1])
				if ok and (layer == "back" or layer == ""):
					ok = _alpha_min(img) == 1.0                    # opaque
				elif ok:
					ok = _alpha_at(img, Vector2i(1, 1)) == 0.0      # transparent around the art
				img.save_png(root.path_join("png").path_join(out_name))
				manifest[out_name] = {"size": size, "sha256": FileAccess.get_sha256(root.path_join("png").path_join(out_name))}
				print("%s %s %dx%d" % ["PASS" if ok else "FAIL", out_name, img.get_width(), img.get_height()])
				if not ok:
					failures += 1
	var f := FileAccess.open(root.path_join("png/manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  ", true))
	f.close()
	print("BRAND %s: %d images, %d failures" % ["PASS" if failures == 0 else "FAIL", manifest.size(), failures])
	quit(1 if failures else 0)


func _svg_width(text: String) -> float:
	var m := RegEx.create_from_string('width="([0-9.]+)"').search(text)
	return float(m.get_string(1)) if m else 256.0


func _alpha_min(img: Image) -> float:
	var lo := 1.0
	for y in range(0, img.get_height(), 7):
		for x in range(0, img.get_width(), 7):
			lo = minf(lo, img.get_pixel(x, y).a)
	return lo


func _alpha_at(img: Image, p: Vector2i) -> float:
	return img.get_pixelv(p).a
