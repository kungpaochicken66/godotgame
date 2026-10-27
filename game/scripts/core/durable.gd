## Apple TV progress that survives the TV clearing space (atv-r20-controller, design/tv-controller.md,
## "Saving on a TV"). tvOS keeps only 500 KB of an app's local data for sure (NSUserDefaults); every file
## the app writes, user:// included (Library/Caches/GodotApp on tvOS), may be deleted when the TV needs
## space and the app is not running. The game keeps writing its files as everywhere else and, on a TV only,
## also keeps a checked copy of its small progress files in that persistent storage through the native
## LanternDefaults module (tv/native/lantern_defaults):
##   settings.cfg, blueprints.json, town_solo.json and town_hosted.json
## Each copy is "lld1", the raw size (u32), SHA-256 of the raw bytes, then the deflated bytes. The module
## computes the exact serialized size of the whole persistent domain with the new value BEFORE writing and
## refuses anything above 384 KiB, keeping the old value. A file is copied only when its content is valid
## for the game (the town model, the blueprint and settings rules); a copy is used only when it unpacks to
## exactly its recorded size and SHA-256 and that content is valid too. At launch a missing or invalid file
## comes back from its copy; a valid file always wins (a copy can only lag behind it).
## Photos and stories are media: too big for this, they stay in the purgeable cache, and the game says so.
## Off a TV (iPhone, iPad, desktop, the server) none of this runs.
extends RefCounted

const TvMode := preload("res://scripts/core/tv_mode.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Blueprints := preload("res://scripts/core/blueprints.gd")
const BRIDGE := "LanternDefaults"   # the get_singleton name of the native module
const MAGIC := "lld1"   # format tag of a copy
const HEADER := 40                 # magic 4 + raw size 4 + SHA-256 32
const MAX_RAW := 8 * 1024 * 1024   # a copy claiming more raw bytes than this is damaged
const BUDGET := 384 * 1024         # enforced by the module on the whole serialized domain
const MAX_VALUE := 192 * 1024      # the module's largest single value
## path -> [key, kind, largest copy in bytes]
const FILES := {
	"user://settings.cfg": ["settings", "config", 16 * 1024],
	"user://blueprints.json": ["blueprints", "blueprints", 48 * 1024],
	"user://town_solo.json": ["town_solo", "town", 176 * 1024],
	"user://town_hosted.json": ["town_hosted", "town", 176 * 1024],
}

## Tests and the device smoke phase use their own files and keys ("test." keys, user://tv_smoke/...).
static var files: Dictionary = FILES
## Tests put a stand-in module here; otherwise the native module on a TV.
static var backend: Object = null
## key -> "ok", "too_big", "no_room", "failed", "restored", "damaged", "restore_failed" or "unavailable"
static var status := {}
static var _seen := {}   # path -> SHA-256 of the content last looked at (poll)


static func _backend() -> Object:
	if backend != null:
		return backend
	if Engine.has_singleton(BRIDGE):
		return Engine.get_singleton(BRIDGE)
	return null


static func enabled() -> bool:
	return backend != null or TvMode.active()


## The module is in this build: progress on this TV is kept safely.
static func available() -> bool:
	return _backend() != null


# ------------------------------------------------------------- copies

static func pack(raw: PackedByteArray) -> PackedByteArray:
	var out := MAGIC.to_ascii_buffer()
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, raw.size())
	out.append_array(n)
	out.append_array(digest(raw))
	out.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return out


## The original bytes of a copy, or empty when it is damaged in any way. The recorded size is checked
## (1 .. 8 MiB) before inflating, so inflating is bounded; size and SHA-256 are checked after.
static func unpack(blob) -> PackedByteArray:
	if typeof(blob) != TYPE_PACKED_BYTE_ARRAY or blob.size() <= HEADER or blob.slice(0, 4).get_string_from_ascii() != MAGIC:
		return PackedByteArray()
	var n: int = blob.decode_u32(4)
	if n <= 0 or n > MAX_RAW:
		return PackedByteArray()
	var raw: PackedByteArray = blob.slice(HEADER).decompress(n, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != n or digest(raw) != blob.slice(8, HEADER):
		return PackedByteArray()
	return raw


static func digest(b: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish()


## Content the game would accept: a town the town model loads, blueprints every one of which the
## blueprint rules accept, settings that parse with a valid device id (if any). Not just readable.
static func valid(kind: String, raw: PackedByteArray) -> bool:
	if raw.is_empty() or raw.size() > MAX_RAW:
		return false
	var text := raw.get_string_from_utf8()
	match kind:
		"config":
			var cfg := ConfigFile.new()
			if cfg.parse(text) != OK:
				return false
			var pid := str(cfg.get_value("player", "id", ""))
			return pid == "" or (pid.length() == 32 and pid.is_valid_hex_number())
		"town":
			var data = JSON.parse_string(text)
			return typeof(data) == TYPE_DICTIONARY and TownModel.new().from_dict(data)
		"blueprints":
			var list = JSON.parse_string(text)
			return typeof(list) == TYPE_ARRAY and list.all(func(b): return Blueprints.usable(b))
	return false


# ------------------------------------------------------------- mirror and restore

## After a file was written: keep its copy. An invalid file is never copied; a refused copy (too big,
## no room in the budget, a failed write) leaves the last good copy as it was. Returns the status.
static func mirror(path: String) -> String:
	if not enabled() or not files.has(path):
		return ""
	var key: String = files[path][0]
	var be := _backend()
	if be == null:
		status[key] = "unavailable"
		return status[key]
	var raw := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	if not valid(files[path][1], raw):
		return ""
	if status.get(key, "") == "restore_failed":
		return status[key]   # a good copy could not be brought back: never overwrite it this session
	var blob := pack(raw)
	if blob.size() > int(files[path][2]) or blob.size() > MAX_VALUE:
		status[key] = "too_big"
		return status[key]
	var old: PackedByteArray = be.call("get_blob", key)
	if old == blob:
		status[key] = "ok"
		return status[key]
	var err: int = be.call("put_blob", key, blob)
	match err:
		OK:
			status[key] = "ok" if be.call("get_blob", key) == blob else "failed"
		ERR_OUT_OF_MEMORY:
			status[key] = "no_room"   # the whole domain would pass the budget: the old copy stays
		ERR_INVALID_DATA:
			status[key] = "too_big"
		_:
			status[key] = "failed"
	return status[key]


static func mirror_all() -> void:
	for path in files:
		if FileAccess.file_exists(path):
			mirror(path)


## Copies any progress file whose content changed since the last look (settings change from many
## places). Content, not time or size: two edits of the same length in one second are both noticed.
static func poll() -> void:
	if not enabled():
		return
	for path in files:
		if not FileAccess.file_exists(path):
			continue
		var stamp := digest(FileAccess.get_file_as_bytes(path)).hex_encode()
		if _seen.get(path, "") != stamp:
			_seen[path] = stamp
			mirror(path)


## Before a file is read: a missing or invalid file comes back from a good copy. A valid file is kept.
## Returns "restored", "damaged", "none", "kept" or "".
static func restore(path: String) -> String:
	if not enabled() or not files.has(path):
		return ""
	var key: String = files[path][0]
	var kind: String = files[path][1]
	var be := _backend()
	if be == null:
		status[key] = "unavailable"
		return ""
	var cur := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	if valid(kind, cur):
		return "kept"
	var blob: PackedByteArray = be.call("get_blob", key)
	if blob.is_empty():
		return "none"
	var raw := unpack(blob)
	if raw.is_empty() or not valid(kind, raw):
		status[key] = "damaged"
		return "damaged"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f != null:
		f.store_buffer(raw)
		f.close()
	if f == null or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		# The good copy stays (mirror will not overwrite it this session) and the child is told.
		status[key] = "restore_failed"
		return "restore_failed"
	status[key] = "restored"
	return "restored"


static func restore_all() -> void:
	for path in files:
		restore(path)


## What the child is told about the town in `path` on this TV, or "".
static func town_notice(path: String) -> String:
	if not TvMode.active() or not files.has(path):
		return ""
	match status.get(files[path][0], ""):
		"unavailable", "too_big", "no_room", "failed":
			return "This TV cannot keep this town safely. It may be lost when the TV needs space."
		"restored":
			return "Your town was brought back from this TV's safe copy."
		"damaged":
			return "This TV's safe copy of your town was damaged, so it could not be brought back."
		"restore_failed":
			return "Your town's safe copy could not be brought back right now. It is kept for next time."
	return ""
