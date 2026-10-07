## Labeled grid of reference icons (2D only): godot --path . --script <this> -- out.png "Title" "label|png" ...
extends SceneTree
const COLS := 8
const CELL := Vector2i(190, 170)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var items := a.slice(2)
	var rows := ceili(items.size() / float(COLS))
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * CELL.x, 50 + rows * CELL.y)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#fbf6ec")
	bg.size = vp.size
	vp.add_child(bg)
	var t := Label.new()
	t.text = a[1]
	t.position = Vector2(10, 8)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#3c4a3a"))
	vp.add_child(t)
	for i in items.size():
		var p: PackedStringArray = items[i].split("|")
		var x := (i % COLS) * CELL.x
		var y := 50 + (i / COLS) * CELL.y
		var img := Image.load_from_file(p[1])
		if img:
			img.resize(112, 112, Image.INTERPOLATE_NEAREST)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(x + (CELL.x - 112) / 2, y)
			vp.add_child(tr)
		var l := Label.new()
		l.text = p[0]
		l.position = Vector2(x + 4, y + 112)
		l.size = Vector2(CELL.x - 8, 52)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color("#3c4a3a"))
		vp.add_child(l)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(a[0])
	quit()
