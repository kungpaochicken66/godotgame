## Exports the Godot city for the Three.js city (design/city-threejs.md), so both cities come from the same
## builder and the same data and cannot drift apart:
##   data/city.json + data/city.bin   the built city (CityWorld.build() plus the people's part meshes) as a mesh
##                                    pack (scripts/web/mesh_pack.gd), material roles named
##   data/consts.json                 every constant of the city's scripts (scripts/web/web_json.gd convention),
##                                    plus "extra" tables from tests/web_city/export_<area>.gd (static extra())
##
##   scripts/godot.sh --headless --path game --script res://tests/web_city/export.gd -- [--out=/abs/dir]
## Without --out it writes res://web_city/data. web_city_tests (and the battery) export to a temporary folder
## and compare byte for byte with the checked-in files.
extends SceneTree

const MeshPack := preload("res://scripts/web/mesh_pack.gd")
const WebJson := preload("res://scripts/web/web_json.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")
const PEOPLE_SCRIPT := "res://scripts/art/city_people.gd"

## The scripts whose constants the page reads (key -> path).
const CONST_SCRIPTS := {
	"CityMap": "res://scripts/core/city_map.gd",
	"CityRules": "res://scripts/core/city_rules.gd",
	"CityNav": "res://scripts/core/city_nav.gd",
	"CityOrbit": "res://scripts/world/city_orbit.gd",
	"CityWorld": "res://scripts/world/city_world.gd",
	"PropsCity": "res://scripts/art/props_city.gd",
	"PeopleData": "res://scripts/core/city_people_data.gd",
	"People": "res://scripts/art/city_people.gd",
}
## Workers' extra tables: tests/web_city/export_<area>.gd with `static func extra() -> Dictionary`.
const EXTRA_AREAS := ["world", "people", "camera", "kids"]
const EXPORT_VERSION := 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://web_city/data"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	var holder := Node3D.new()
	root.add_child(holder)
	var cw = CityWorld.new()
	cw.name = "City"
	holder.add_child(cw)
	cw.setup(holder)
	cw.build()
	var people: Node3D = null
	if ResourceLoader.exists(PEOPLE_SCRIPT):
		var ps := load(PEOPLE_SCRIPT) as GDScript
		if ps and ps.can_instantiate():
			people = ps.new()
			people.name = "People"
			cw.add_child(people)
			people.call("setup", cw)
	await process_frame
	var pack := MeshPack.Pack.new()
	var roles := {"_glow_mat": "glow", "_cabin_mat": "cabin", "_ground_mat": "ground", "_puddle_mat": "puddle",
		"_pool_mat": "pool", "_rain_mat": "rain"}
	for prop in roles:
		var m = cw.get(prop)
		if m is Material:
			pack.roles[m] = roles[prop]
	pack.roles[load("res://scripts/art/props_city.gd").material()] = "base"
	pack.add_tree(cw)
	var header := pack.header()
	header["export_version"] = EXPORT_VERSION
	var ok := _write(out.path_join("city.json"), JSON.stringify(header, "", false).to_utf8_buffer())
	ok = ok and _write(out.path_join("city.bin"), pack.bytes())
	var consts := {"export_version": EXPORT_VERSION}
	for key in CONST_SCRIPTS:
		var s := load(CONST_SCRIPTS[key]) as Script
		consts[key] = WebJson.script_consts(s) if s else {}
	var extra := {}
	for area in EXTRA_AREAS:
		var p := "res://tests/web_city/export_%s.gd" % area
		if ResourceLoader.exists(p):
			var es := load(p) as GDScript
			if es and es.has_method("extra"):
				extra[area] = WebJson.value(es.call("extra"))
	consts["extra"] = extra
	ok = ok and _write(out.path_join("consts.json"), JSON.stringify(consts, "", false).to_utf8_buffer())
	var verts := 0
	for m in header["meshes"]:
		for s in m["surfaces"]:
			verts += int(s["count"])
	print("WEB CITY EXPORT %s: %d nodes, %d meshes, %d vertices, %d bytes, materials %s" % [
		"OK" if ok else "FAILED", header["nodes"].size(), header["meshes"].size(), verts, header["bytes"], str(header["materials"].keys())])
	quit(0 if ok else 1)


func _write(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return false
	f.store_buffer(data)
	f.close()
	return true
