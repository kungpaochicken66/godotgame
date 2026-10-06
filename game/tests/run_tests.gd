## Headless unit tests for game rules, saves, Cozy Spots, avatars and locales.
##   godot --headless --path game -s res://tests/run_tests.gd
extends SceneTree

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Palette := preload("res://scripts/core/palette.gd")

var Session: Node   # the autoload; looked up at runtime in script mode
var _failures := 0
var _checks := 0
var _current := ""


func _initialize() -> void:
	Session = root.get_node("Session")
	var tests := [
		"test_catalog", "test_default_town", "test_placement_rules", "test_cottage_door",
		"test_move_paint", "test_remove_restore_house", "test_save_roundtrip", "test_bad_saves",
		"test_cozy_spots", "test_avatar", "test_locales", "test_capacity", "test_free_spot",
	]
	for t in tests:
		_current = t
		call(t)
	_current = "test_session_solo"
	await test_session_solo()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func eq(a: Variant, b: Variant, what: String) -> void:
	ok(a == b, "%s: expected %s, got %s" % [what, b, a])


func test_catalog() -> void:
	var categories := Catalog.TOWN_CATEGORIES + Catalog.HOME_CATEGORIES
	for kind in Catalog.ITEMS:
		var d: Dictionary = Catalog.ITEMS[kind]
		ok(d.has_all(["name", "category", "space", "radius", "layer", "color", "seats"]), "%s fields" % kind)
		ok(categories.has(d["category"]), "%s category" % kind)
		ok(d["space"] in ["town", "home", "both"], "%s space" % kind)
		ok(d["layer"] in ["solid", "flat"], "%s layer" % kind)
		ok(d["color"] >= -1 and d["color"] < Palette.PAINT.size(), "%s color" % kind)
		ok(d["seats"] == 0 or d.has("action"), "%s seated items need an action" % kind)
		var tabs := 0
		for c in categories:
			if Catalog.kinds_for(c, "town").has(kind) or Catalog.kinds_for(c, "i1").has(kind):
				tabs += 1
		ok(tabs >= 1, "%s reachable from a catalog tab" % kind)


func test_default_town() -> void:
	var m = TownModel.make_default()
	ok(m.items.size() > 20, "default town is decorated")
	for item in m.items.values():
		eq(m.check(item["kind"], item["space"], item["x"], item["z"], item["rot"], item["id"]), "", "default %s %s valid" % [item["kind"], item["id"]])
	var kinds: Array = m.items.values().map(func(i): return i["kind"])
	for needed in ["cottage", "pond", "path_stone", "tree", "swing"]:
		ok(kinds.has(needed), "default town has %s" % needed)
	eq(CozySpots.detect(m).size(), 0, "first lanterns are left for the players to discover")
	eq(m.lanterns.size(), 0, "no lanterns lit at start")


func test_placement_rules() -> void:
	var m = TownModel.new()
	ok(m.place("tree", "town", 5, 5, 0)["ok"], "tree on open lawn (the old preview bug)")
	eq(m.place("tree", "town", 5.5, 5, 0).get("error"), TownModel.ERR_OVERLAP, "overlapping solids")
	ok(m.place("path_stone", "town", 7, 7, 0)["ok"], "path stone")
	ok(m.place("chair", "town", 7, 7, 0)["ok"], "solid item may stand on a flat item")
	eq(m.place("path_stone", "town", 7.2, 7, 0).get("error"), TownModel.ERR_OVERLAP, "flat items overlap each other")
	eq(m.place("tree", "town", 15.8, 0, 0).get("error"), TownModel.ERR_EDGE, "edge")
	eq(m.place("bench", "town", 0, -5, 0).get("error"), TownModel.ERR_TREE, "wishing tree")
	eq(m.place("bed", "town", -5, 5, 0).get("error"), TownModel.ERR_INDOORS, "beds are indoor")
	eq(m.place("swing", "i999", 0, 0, 0).get("error"), TownModel.ERR_NO_HOUSE, "unknown house")
	eq(m.place("rocket", "town", 0, 0, 0).get("error"), TownModel.ERR_UNKNOWN, "unknown kind")
	var house = m.place("cottage", "town", -8, 0, 0)
	ok(house["ok"], "cottage")
	var hid: String = house["item"]["id"]
	ok(m.place("chair", hid, 0, 0, 0)["ok"], "chair inside")
	eq(m.place("swing", hid, 1, 1, 0).get("error"), TownModel.ERR_OUTDOORS, "swing is outdoor")
	eq(m.place("bookshelf", hid, 3.8, 0, 0).get("error"), TownModel.ERR_EDGE, "room walls")
	eq(m.place("bookshelf", hid, TownModel.ROOM_DOOR.x, TownModel.ROOM_DOOR.y + 0.2, 0).get("error"), TownModel.ERR_DOOR, "exit door kept clear")
	ok(m.place("rug", hid, TownModel.ROOM_DOOR.x, TownModel.ROOM_DOOR.y + 0.9, 0)["ok"], "rugs may lie by the door")
	eq(m.place("tree", "town", 3, 3, 9)["item"]["rot"], 1, "rotation wraps to 8 steps")
	ok(is_equal_approx(m.place("bush", "town", 3.033, -1.987, 0)["item"]["x"], 3.05), "positions snap to 5 cm")


func test_cottage_door() -> void:
	var m = TownModel.new()
	var h = m.place("cottage", "town", 0, 4, 0)
	ok(h["ok"], "cottage")
	var door: Vector2 = TownModel.door_point(h["item"])
	ok(door.distance_to(Vector2(0, 4 + 2.85)) < 0.01, "door faces +z at rot 0")
	eq(m.place("tree", "town", door.x, door.y + 0.3, 0).get("error"), TownModel.ERR_DOOR, "tree blocking the door")
	ok(m.place("path_stone", "town", door.x, door.y, 0)["ok"], "path at the door is fine")
	eq(m.place("cottage", "town", 0, -12.0, 4).get("error"), TownModel.ERR_EDGE, "edge for cottage body")
	ok(m.place("pond", "town", -8, 8, 0)["ok"], "pond")
	eq(m.place("cottage", "town", -8, 3.1, 0).get("error"), TownModel.ERR_DOOR, "cottage facing into a pond")


func test_move_paint() -> void:
	var m = TownModel.new()
	var a = m.place("bench", "town", 4, 4, 0)["item"]
	var b = m.place("bench", "town", 8, 4, 0)["item"]
	ok(m.move(a["id"], 5, 6, 2)["ok"], "move")
	eq(m.items[a["id"]]["rot"], 2, "rotated")
	eq(m.move(a["id"], 8.5, 4, 0).get("error"), TownModel.ERR_OVERLAP, "move into another")
	eq(m.items[a["id"]]["x"], 5.0, "failed move leaves item")
	ok(m.move(b["id"], 8, 4, 3)["ok"], "turning in place ignores itself")
	ok(m.paint(a["id"], 6)["ok"], "paint")
	eq(m.items[a["id"]]["color"], 6, "painted")
	eq(m.paint(a["id"], 99)["item"]["color"], Palette.PAINT.size() - 1, "paint clamps")
	var stone = m.place("path_stone", "town", 0, 8, 0)["item"]
	ok(not m.paint(stone["id"], 2)["ok"], "unpaintable")
	eq(m.move("nope", 0, 0, 0).get("error"), TownModel.ERR_GONE, "missing id")


func test_remove_restore_house() -> void:
	var m = TownModel.new()
	var h = m.place("cottage", "town", 0, 0, 0)["item"]
	m.place("bed", h["id"], -2, -1, 0)
	m.place("rug", h["id"], 0, 0, 0)
	var other = m.place("cottage", "town", -9, 0, 0)["item"]
	m.place("chair", other["id"], 0, 0, 0)
	var r = m.remove(h["id"])
	ok(r["ok"], "remove house")
	eq(r["removed"].size(), 3, "house and its two items")
	eq(m.items_in(h["id"]).size(), 0, "contents packed away")
	eq(m.items_in(other["id"]).size(), 1, "other house untouched")
	var back = m.restore(r["removed"])
	ok(back["ok"], "undo")
	ok(m.items.has(h["id"]), "original id kept")
	eq(m.items_in(h["id"]).size(), 2, "furniture back inside")
	m.remove(h["id"])
	m.place("pond", "town", 0, 0, 0)
	ok(not m.restore(r["removed"])["ok"], "cannot restore into an occupied spot")


func test_save_roundtrip() -> void:
	var m = TownModel.make_default()
	m.lanterns["tea_party"] = {"by": ["Sunny", "Sky"], "t": 123}
	m.evening = true
	var text := JSON.stringify(m.to_dict())
	var m2 = TownModel.new()
	ok(m2.from_dict(JSON.parse_string(text)), "load")
	eq(m2.items.size(), m.items.size(), "item count survives JSON")
	for id in m.items:
		eq(m2.items.get(id), m.items[id], "item %s survives JSON" % id)
	eq(m2.lanterns, m.lanterns, "lanterns survive")
	eq(m2.evening, true, "evening survives")
	eq(m2.next_id, m.next_id, "id counter")
	var fresh = m2.place("tree", "town", -10, 10, 0)
	ok(fresh["ok"] and not m.items.has(fresh["item"]["id"]), "new ids do not collide after load")


func test_bad_saves() -> void:
	var m = TownModel.new()
	ok(not m.from_dict({"schema": 99}), "unknown schema rejected")
	ok(m.from_dict({"schema": 1, "items": [
		{"id": "i1", "kind": "chair", "space": "i9", "x": 0, "z": 0, "rot": 0, "color": 0},
		{"id": "i9", "kind": "cottage", "space": "town", "x": 0, "z": 0, "rot": 0, "color": 0},
		{"id": "i2", "kind": "unicorn", "space": "town", "x": 0, "z": 0, "rot": 0, "color": 0},
		"garbage", {"id": "i3"},
	]}), "tolerant load")
	eq(m.items.size(), 2, "valid entries kept, cottage loaded before its furniture")
	eq(m.next_id, 10, "id counter beyond loaded ids")


func _spot_kinds(m) -> Array:
	return CozySpots.detect(m).map(func(s): return s["spot"])


func test_cozy_spots() -> void:
	var m = TownModel.new()
	var h = m.place("cottage", "town", -10, -8, 0)["item"]
	var hid: String = h["id"]
	m.place("table", "town", 4, 4, 0)
	m.place("chair", "town", 5.2, 4, 0)
	ok(not _spot_kinds(m).has("tea_party"), "one chair is not a party")
	m.place("chair", "town", 2.8, 4, 0)
	ok(_spot_kinds(m).has("tea_party"), "tea party")
	m.place("bookshelf", hid, -3, -2, 0)
	m.place("sofa", hid, -1.5, -0.5, 0)
	m.place("floor_lamp", hid, -3.3, -0.6, 0)
	ok(_spot_kinds(m).has("reading_nook"), "reading nook")
	m.place("tree", "town", -4, 6, 0)
	for p in [Vector2(-5.5, 6), Vector2(-2.5, 6), Vector2(-4, 7.5)]:
		m.place("flowers", "town", p.x, p.y, 0)
	ok(_spot_kinds(m).has("flower_ring"), "flower ring")
	m.place("pond", "town", 10, 8, 0)
	m.place("blanket", "town", 10, 5.0, 0)
	ok(_spot_kinds(m).has("pond_picnic"), "pond picnic")
	m.place("bed", hid, 2.5, 1.5, 0)
	m.place("rug", hid, 0, 1.5, 0)
	ok(not _spot_kinds(m).has("sleepover"), "one bed")
	m.place("bed", hid, -2.5, 1.8, 0)
	ok(_spot_kinds(m).has("sleepover"), "sleepover")
	m.place("lamp_post", "town", -10, 6, 0)
	for p in [Vector2(-11, 6), Vector2(-9, 6), Vector2(-10, 7), Vector2(-10, 5)]:
		m.place("path_stone", "town", p.x, p.y, 0)
	ok(_spot_kinds(m).has("lantern_path"), "lantern path")
	m.place("swing", "town", 10, -2, 0)
	m.place("seesaw", "town", 13, -4, 0)
	ok(_spot_kinds(m).has("playground"), "playground")
	var door := TownModel.door_point(h)
	m.place("bench", "town", door.x + 1.6, door.y + 0.4, 0)
	m.place("plant", "town", door.x - 1.4, door.y + 0.2, 0)
	ok(_spot_kinds(m).has("front_porch"), "front porch")
	for s in CozySpots.ORDER:
		ok(CozySpots.SPOTS.has(s), "%s defined" % s)
	eq(CozySpots.newly_formed(m).size(), CozySpots.SPOTS.size(), "all eight spots formed")
	m.lanterns["tea_party"] = {"by": [], "t": 0}
	ok(not CozySpots.newly_formed(m).has("tea_party"), "lit spots are not new")


func test_avatar() -> void:
	var a := Avatar.sanitize({"nick": "<script>", "skin": 99, "hair": -3, "outfit_color": 4})
	eq(a["nick"], "Sunny", "unknown nicknames replaced")
	eq(a["skin"], Palette.SKIN.size() - 1, "skin clamped")
	eq(a["hair"], 0, "hair clamped")
	eq(a["outfit_color"], 4, "color kept")
	eq(Avatar.sanitize("bad")["nick"], "Sunny", "non-dictionary")
	for p in Avatar.PRESETS:
		eq(Avatar.sanitize(p), p, "preset is valid")


func test_locales() -> void:
	var langs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/languages.json"))
	eq(langs.keys().size(), 6, "six languages")
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/en.json"))
	for key in en:
		eq(en[key], key, "English catalog is the source")
	for code in ["zh-CN", "ja", "es", "fr", "de"]:
		var cat = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		ok(typeof(cat) == TYPE_DICTIONARY, "%s parses" % code)
		if typeof(cat) != TYPE_DICTIONARY:
			continue
		for key in en:
			ok(cat.has(key) and str(cat[key]).strip_edges() != "", "%s translates '%s'" % [code, key])
		for key in cat:
			ok(en.has(key), "%s has no stray key '%s'" % [code, key])
	var needed := []
	for kind in Catalog.ITEMS:
		needed.append(Catalog.ITEMS[kind]["name"])
		needed.append(Catalog.ITEMS[kind]["category"])
		if Catalog.ITEMS[kind].has("action"):
			needed.append(Catalog.ITEMS[kind]["action"])
	for s in CozySpots.SPOTS.values():
		needed.append(s["name"])
		needed.append(s["hint"])
	for p in Palette.PAINT:
		needed.append(p["name"])
	needed += Avatar.NICKNAMES + Avatar.HAIR_STYLES + Avatar.OUTFITS
	var model_script: Script = TownModel
	var constants := model_script.get_script_constant_map()
	for c in constants:
		if c.begins_with("ERR_"):
			needed.append(constants[c])
	for key in needed:
		ok(en.has(key), "English catalog has game string '%s'" % key)


func test_capacity() -> void:
	var m = TownModel.new()
	var h = m.place("cottage", "town", 0, 0, 0)["item"]
	var placed := 0
	for x in range(-3, 4):
		for z in range(-2, 3):
			if m.place("rug", h["id"], x * 1.0, z * 1.0, 0)["ok"]:
				placed += 1
	ok(placed < TownModel.MAX_ROOM_ITEMS, "rug overlap limits density")
	for i in TownModel.MAX_ROOM_ITEMS:
		m.items["x%d" % i] = {"id": "x%d" % i, "kind": "teddy", "space": h["id"], "x": 0.0, "z": 0.0, "rot": 0, "color": 0}
	eq(m.place("teddy", h["id"], 1, 1, 0).get("error"), TownModel.ERR_ROOM_FULL, "room capacity")


func test_free_spot() -> void:
	var m = TownModel.make_default()
	var spot = m.find_free_spot("swing", "town", Vector2(0, 6))
	ok(spot != null, "free spot found near the path")
	if spot != null:
		eq(m.check("swing", "town", spot.x, spot.y, 0), "", "free spot is valid")


func _result(req: int) -> Dictionary:
	var out := {}
	var cb := func(r_id: int, r: Dictionary):
		if r_id == req:
			out.merge(r)
	Session.request_done.connect(cb)
	for i in 5:
		await process_frame
	Session.request_done.disconnect(cb)
	return out


## The real Session autoload in solo mode: requests, locks, seats, lanterns,
## autosave, reload and recovery from a damaged save file.
func test_session_solo() -> void:
	await process_frame   # autoloads enter the tree after _initialize
	var path := "user://test_session_town.json"
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[1])
	eq(Session.players.size(), 1, "solo player joined")
	eq(Session.nick_of(Session.my_id), "Sky", "avatar kept")
	var r := await _result(Session.place("table", "town", Vector2(-6, 5), 0, -2))
	ok(r.get("ok", false), "place through the session")
	await _result(Session.place("chair", "town", Vector2(-7.25, 5), 2, 0))
	await _result(Session.place("chair", "town", Vector2(-4.75, 5), 6, 0))
	ok(Session.model.lanterns.has("tea_party"), "lantern lit by the authority")
	eq(Session.model.lanterns.get("tea_party", {}).get("by"), ["Sky"], "lantern credits the player")
	var bad := await _result(Session.place("tree", "town", Vector2(0, -5), 0, -2))
	eq(bad.get("error"), TownModel.ERR_TREE, "authority rejects invalid placement")
	var table_id: String = r["item"]["id"]
	Session.locks[table_id] = 4242  # as if a friend were holding it
	var blocked := await _result(Session.move(table_id, Vector2(-6, 6), 0))
	eq(blocked.get("error"), "Someone else is using that.", "locked items cannot be moved")
	Session.locks.erase(table_id)
	var swing: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "swing")[0]
	ok((await _result(Session.sit(swing["id"]))).get("ok", false), "sit on the swing")
	eq(Session.seat_of(Session.my_id), [swing["id"], 0], "seat recorded")
	eq((await _result(Session.remove(swing["id"]))).get("error"), "Someone is playing on it.", "occupied swing cannot be put away")
	await _result(Session.stand())
	ok(Session.seat_of(Session.my_id).is_empty(), "stood up")
	await _result(Session.ring_bell())
	ok(Session.model.evening, "bell switches to evening")
	ok(Session.save_now(), "save succeeds")
	var count: int = Session.model.items.size()
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	eq(Session.model.items.size(), count, "town reloads with every item")
	ok(Session.model.lanterns.has("tea_party") and Session.model.evening, "lantern and evening reload")
	# A damaged save falls back to the previous good copy instead of losing the town.
	Session.save_now()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	eq(Session.model.items.size(), count, "damaged save recovered from .bak")
	Session.leave()
