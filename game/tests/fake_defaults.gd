## A stand-in for the native LanternDefaults module (tv/native/lantern_defaults) with the same rules, for
## unit tests and EC2 dry runs of the TV tour's defaults phases (--fake-defaults). Not native evidence:
## the whole store is measured here as var_to_bytes of every key and value (the module uses the binary
## property list), always BEFORE writing, and a refusal leaves every value as it was. Only "test." names.
extends RefCounted

const BUDGET := 384 * 1024
const MAX_VALUE := 192 * 1024

var store := {}
var budget_bytes := BUDGET
var puts := 0
var persist_path := ""   # dry runs keep the store across a relaunch in this file


func _init(path := "") -> void:
	persist_path = path
	if path != "" and FileAccess.file_exists(path):
		var data = bytes_to_var(FileAccess.get_file_as_bytes(path))
		if typeof(data) == TYPE_DICTIONARY:
			store = data


func _save() -> void:
	if persist_path != "":
		var f := FileAccess.open(persist_path, FileAccess.WRITE)
		f.store_buffer(var_to_bytes(store))
		f.close()


func _size(d: Dictionary) -> int:
	return var_to_bytes(d).size()


func budget() -> int:
	return BUDGET


func domain_bytes() -> int:
	return _size(store)


func candidate_bytes(name: String, data: PackedByteArray) -> int:
	var c := store.duplicate()
	c["lantern." + name] = data
	return _size(c)


func put_blob(name: String, data: PackedByteArray) -> int:
	if not name.begins_with("test."):
		return ERR_INVALID_PARAMETER
	if data.is_empty() or data.size() > MAX_VALUE:
		return ERR_INVALID_DATA
	if candidate_bytes(name, data) > budget_bytes:
		return ERR_OUT_OF_MEMORY
	store["lantern." + name] = data
	puts += 1
	_save()
	return OK


func get_blob(name: String) -> PackedByteArray:
	return store.get("lantern." + name, PackedByteArray())


func erase_blob(name: String) -> bool:
	var had := store.erase("lantern." + name)
	_save()
	return had


func keys(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in store:
		if str(k).begins_with("lantern." + prefix):
			out.append(str(k).substr(8))
	out.sort()
	return out
