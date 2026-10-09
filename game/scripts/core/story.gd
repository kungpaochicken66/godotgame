## Three-panel stories (design/playability-8-12.md F05): an inspiration card,
## three pictures, any order, kept on this device. Pure helpers, unit-tested.
## There is no right picture and nothing is scored; titles are optional.
extends RefCounted

const PANELS := 3
const DIR := "user://stories"
## Inspiration cards: a title (may be empty: pictures only) and a prompt.
const CARDS := [
	{"id": "opening", "title": "Opening Day", "prompt": "Something new opens in town. Who comes first?"},
	{"id": "rain", "title": "Unexpected Rain", "prompt": "Everyone is outside when the rain starts…"},
	{"id": "together", "title": "Solving It Together", "prompt": "Something goes wrong. How do friends fix it?"},
	{"id": "snack", "title": "The Snack Mix-up", "prompt": "The snacks got mixed up. What happens next?"},
	{"id": "none", "title": "", "prompt": "No title: tell it with pictures only."},
]
const PANEL_W := 480
const PANEL_H := 360
const GAP := 16
const PAPER := Color("#fbf3e3")
## Height of the title band above the panels when the story has a caption (r11).
const CAPTION_H := 72


static func card(id: String) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return CARDS[-1]


## Moves the panel at index i one place left (-1) or right (+1).
static func move(order: Array, i: int, dir: int) -> Array:
	var out := order.duplicate()
	var j := i + dir
	if i < 0 or i >= out.size() or j < 0 or j >= out.size():
		return out
	var t = out[i]
	out[i] = out[j]
	out[j] = t
	return out


## The strip: the panels side by side in `order` on paper, each cropped to 4:3.
## caption: an optional picture of the title (drawn by the game on a renderer);
## it goes in a band above the panels. Without one the strip has no band.
static func compose(panels: Array, order: Array, caption: Image = null) -> Image:
	var w := PANELS * PANEL_W + (PANELS + 1) * GAP
	var band := CAPTION_H if caption != null and not caption.is_empty() else 0
	var h := PANEL_H + 2 * GAP + band
	var strip := Image.create(w, h, false, Image.FORMAT_RGBA8)
	strip.fill(PAPER)
	if band > 0:
		var cap: Image = caption.duplicate()
		cap.convert(Image.FORMAT_RGBA8)
		if cap.get_width() > w - 2 * GAP or cap.get_height() > band:
			var k := minf(float(w - 2 * GAP) / cap.get_width(), float(band) / cap.get_height())
			cap.resize(int(cap.get_width() * k), int(cap.get_height() * k))
		strip.blend_rect(cap, Rect2i(Vector2i.ZERO, cap.get_size()), Vector2i((w - cap.get_width()) / 2, (band - cap.get_height()) / 2 + GAP / 2))
	for slot in mini(PANELS, order.size()):
		var src: Image = panels[order[slot]]
		if src == null or src.is_empty():
			continue
		var img: Image = src.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		# Crop the middle to 4:3, then scale to the panel size.
		var want := float(PANEL_W) / PANEL_H
		var cw := img.get_width()
		var ch := img.get_height()
		if float(cw) / ch > want:
			cw = int(ch * want)
		else:
			ch = int(cw / want)
		img = img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
		img.resize(PANEL_W, PANEL_H, Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(img, Rect2i(0, 0, PANEL_W, PANEL_H), Vector2i(GAP + slot * (PANEL_W + GAP), GAP + band))
	return strip


## Keeps a story on this device: the strip as PNG plus its card. Returns the PNG path.
static func save(strip: Image, card_id: String, now: int, dir := DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/story_%d.png" % [dir, now]
	if strip.save_png(path) != OK:
		return ""
	var f := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"card": card_id, "t": now}))
		f.close()
	return path


## Stories kept on this device, newest first: [{"png", "card", "t"}].
static func list(dir := DIR) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if not (f.begins_with("story_") and f.ends_with(".png")):
			continue
		var path := dir.path_join(f)
		var meta := {}
		var side := path.get_basename() + ".json"
		var raw := FileAccess.get_file_as_string(side) if FileAccess.file_exists(side) else ""
		var j := JSON.new()
		if raw != "" and j.parse(raw) == OK and j.data is Dictionary:
			meta = j.data
		out.append({"png": path, "card": str(meta.get("card", "none")), "t": int(meta.get("t", 0))})
	out.sort_custom(func(a, b): return a["t"] > b["t"])
	return out
