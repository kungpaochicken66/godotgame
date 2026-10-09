## The scrapbook's own photos on this device (r16). Pictures the game's camera takes are kept as PNG
## files in the game's own user folder, with a small local index of their file names, so the scrapbook
## shows them again after the app restarts. Nothing here reads any other folder (never the Photos
## library or other apps' files), sends pictures over the network, or goes into the shared town save.
## Writes go to a temporary file first and are then renamed into place, so an interrupted write never
## leaves a half-written photo or index. Missing or damaged files are skipped, never deleted.
## docs/photos.md.
extends RefCounted

const DIR := "user://photos"
const INDEX := "scrapbook.json"
## File names this module writes (photo_<unix ms>.png) or older builds wrote (photo_<unix s>.png).
const NAME_RE := "^photo_[0-9]{9,14}\\.png$"

static var _re: RegEx


static func _valid_name(name: String) -> bool:
	if _re == null:
		_re = RegEx.create_from_string(NAME_RE)
	return _re.search(name) != null


## Saves a camera picture; returns its file name (relative to dir), or "" if it could not be written.
static func save(img: Image, dir := DIR) -> String:
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var name := "photo_%d.png" % stamp
	while FileAccess.file_exists(dir.path_join(name)):   # two photos in one millisecond
		stamp += 1
		name = "photo_%d.png" % stamp
	var tmp := dir.path_join(name + ".tmp")
	if img.save_png(tmp) != OK or DirAccess.rename_absolute(tmp, dir.path_join(name)) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	var names := _read_index(dir)
	names.append(name)
	_write_index(dir, names)
	return name


## The scrapbook's photos, oldest first: the index, then any older photo files of this game that the
## index does not list yet (photos taken before r16 had no index). Only existing, valid names.
static func list(dir := DIR) -> Array:
	var out: Array = _read_index(dir).filter(func(n): return FileAccess.file_exists(dir.path_join(n)))
	var legacy := []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if _valid_name(f) and not out.has(f):
				legacy.append(f)
	return _merge(out, legacy)


## A small picture of one photo for the scrapbook, or null if the file is missing or damaged.
static func thumbnail(name: String, dir := DIR, shrink := 3) -> Texture2D:
	if not _valid_name(name):
		return null
	var path := dir.path_join(name)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		return null
	img.resize(maxi(1, img.get_width() / shrink), maxi(1, img.get_height() / shrink))
	return ImageTexture.create_from_image(img)


static func _stamp(name: String) -> int:
	var digits := name.substr(6, name.length() - 10)
	var v := int(digits)
	return v * 1000 if digits.length() <= 10 else v   # older names counted seconds


static func _merge(a: Array, b: Array) -> Array:
	var all := a + b
	all.sort_custom(func(x, y): return _stamp(x) < _stamp(y))
	return all


static func _read_index(dir: String) -> Array:
	var path := dir.path_join(INDEX)
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()   # reports a damaged index quietly (parse_string would log an engine error)
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return []
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("photos")) != TYPE_ARRAY:
		return []   # a damaged index is rebuilt from the files on the next save
	var out := []
	for n in data["photos"]:
		if typeof(n) == TYPE_STRING and _valid_name(n) and not out.has(n):
			out.append(n)
	return out


static func _write_index(dir: String, names: Array) -> void:
	var tmp := dir.path_join(INDEX + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": 1, "photos": names}))
	f.close()
	DirAccess.rename_absolute(tmp, dir.path_join(INDEX))
