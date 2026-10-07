## Labeled contact sheet from rendered PNGs (pure 2D layout; cozy-game-modeling skill).
## godot --path . --script <this> -- out.png "Title" [views=front,side,rear,threequarter,closeup,game] "Row label|dir/prefix" ...
## Each row shows <prefix>_<view>.png for each view.
extends SceneTree

var VIEWS := ["front", "side", "rear", "threequarter"]
const CELL := 230
const LABEL_W := 250

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var title: String = args[1]
	var rows := args.slice(2)
	if rows.size() > 0 and rows[0].begins_with("views="):
		VIEWS = Array(rows[0].substr(6).split(","))
		rows = rows.slice(1)
	var vp := SubViewport.new()
	vp.size = Vector2i(LABEL_W + CELL * VIEWS.size(), 70 + 28 + rows.size() * (CELL + 6))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#fbf6ec")
	bg.size = vp.size
	vp.add_child(bg)
	_label(vp, title, Vector2(16, 14), 30, Color("#3c4a3a"))
	for i in VIEWS.size():
		_label(vp, VIEWS[i].replace("threequarter", "three-quarter"), Vector2(LABEL_W + i * CELL + 8, 66), 18, Color("#6b6255"))
	for r in rows.size():
		var parts: PackedStringArray = rows[r].split("|")
		var y := 98 + r * (CELL + 6)
		_label(vp, parts[0].replace("\\n", "\n"), Vector2(16, y + 20), 19, Color("#3c4a3a"), LABEL_W - 24)
		for i in VIEWS.size():
			var img := Image.load_from_file("%s_%s.png" % [parts[1], VIEWS[i]])
			if img == null:
				continue
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(LABEL_W + i * CELL, y)
			vp.add_child(tr)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	quit()

func _label(parent: Node, text: String, pos: Vector2, size: int, color: Color, width := 0) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if width > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size.x = width
	parent.add_child(l)
