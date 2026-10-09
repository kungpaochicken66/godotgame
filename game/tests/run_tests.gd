## Headless unit tests for game rules, saves, Cozy Spots, avatars and locales.
##   godot --headless --path game -s res://tests/run_tests.gd
extends SceneTree

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Palette := preload("res://scripts/core/palette.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const PlacementDock := preload("res://scripts/ui/placement_dock.gd")
const Wishes := preload("res://scripts/core/wishes.gd")
const PhotoIdeas := preload("res://scripts/core/photo_ideas.gd")
const HideSeek := preload("res://scripts/core/hide_seek.gd")

var Session: Node   # the autoload; looked up at runtime in script mode
var _failures := 0
var _checks := 0
var _current := "":
	set(v):
		_current = v
		if _catcher:
			_catcher.owner_test = v
var _catcher: ErrorCatcher

## Engine and script errors expected on purpose, per test (substring of the message).
## Every other error fails its test: a test that stops on a script error can no
## longer pass silently. Warnings are not counted.
const EXPECTED_ERRORS := {
	# The damaged-save check writes "{ not json" and must fall back to the .bak copy.
	"test_session_solo": ["Parse JSON failed"],
	# The photo store test writes a damaged photo on purpose: it must show no picture, not stop.
	"test_photo_store": ["ERR_FILE_CORRUPT", "Error loading image"],
}


## Collects engine errors (including SCRIPT ERROR) with the test that was running.
class ErrorCatcher extends Logger:
	var owner_test := ""
	var errors: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append({"test": owner_test, "type": error_type, "text": "%s %s (%s:%d)" % [code, rationale, file, line]})
		_lock.unlock()


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	var tests := [
		"test_catalog", "test_default_town", "test_placement_rules", "test_cottage_door",
		"test_move_paint", "test_remove_restore_house", "test_save_roundtrip", "test_bad_saves",
		"test_cozy_spots", "test_avatar", "test_locales", "test_capacity", "test_free_spot",
		"test_animals_roam_and_play", "test_animals_social", "test_animals_yield_to_items",
		"test_animals_deterministic_and_packed", "test_animals_without_favorites",
		"test_dock_choice", "test_dock_hysteresis",
		"test_house_rooms_and_stairs", "test_migrate_v1_save", "test_bigger_town",
		"test_scale_contract", "test_tabletop_place_and_reject", "test_tabletop_follow_remove_undo",
		"test_tabletop_saves", "test_tabletop_restore_order", "test_tabletop_rotated_fit",
		"test_modeled_assets", "test_mounted_items", "test_furniture_r2", "test_headroom", "test_ceiling_turn", "test_wall_clearance", "test_wall_clearance_heights", "test_photo_store", "test_toybox_names", "test_wish_rules", "test_gift_rules", "test_garden_rules",
		"test_hearts_and_visits", "test_photo_idea_rules", "test_activity_data_saves", "test_hide_and_seek_warmth",
		"test_landmark_tag_layout", "test_item_query", "test_item_query_large_fixture", "test_tap_choices",
		"test_deployment_config", "test_activity_guide", "test_feedback_keeps_clear_of_tags",
		"test_room_themes", "test_pet_rules", "test_cooking_rules", "test_pets_cooking_saves", "test_pet_models", "test_photo_library",
		"test_play_rules", "test_fetch_brain", "test_dress_and_poses", "test_track_rules", "test_trail_rules",
		"test_music_box_rules", "test_story_rules",
		"test_invite_rules", "test_animal_games", "test_blueprint_rules", "test_r11_props_and_rig",
		"test_r11b_review_fixes", "test_wear_catalog", "test_wear_rules", "test_wear_kid",
	]
	for t in tests:
		_current = t
		call(t)
	_current = "test_session_solo"
	await test_session_solo()
	_current = "test_music"
	test_music()
	_current = "test_tabletop_session_race"
	await test_tabletop_session_race()
	_current = "test_activities_session"
	await test_activities_session()
	_current = "test_play_session"
	await test_play_session()
	_current = "test_batch2_session"
	await test_batch2_session()
	_current = "test_r11_session"
	await test_r11_session()
	_current = "test_wear_session"
	await test_wear_session()
	await test_wear_thumbs()
	_current = "engine errors"
	_check_engine_errors()
	print("\n%d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


## Every engine or script error must be an expected one for its test, and every
## expected one must have happened (so the negative checks really ran).
func _check_engine_errors() -> void:
	var seen := {}
	for e in _catcher.errors:
		var allowed: Array = EXPECTED_ERRORS.get(e["test"], [])
		var hit := ""
		for pattern in allowed:
			if pattern in e["text"]:
				hit = pattern
		if hit != "":
			seen[e["test"] + "|" + hit] = true
		_current = e["test"]
		ok(hit != "", "unexpected engine error%s: %s" % [" (SCRIPT ERROR)" if e["type"] == Logger.ERROR_TYPE_SCRIPT else "", e["text"]])
	for t in EXPECTED_ERRORS:
		for pattern in EXPECTED_ERRORS[t]:
			_current = t
			ok(seen.has(t + "|" + pattern), "the expected error \"%s\" happened (its negative check ran)" % pattern)


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
		ok(d["layer"] in ["solid", "flat", "mounted"], "%s layer" % kind)
		ok((d["layer"] == "mounted") == (d.get("anchor", "ground") != "ground"), "%s: mounted exactly when hung on a wall or ceiling" % kind)
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
	eq(m.place("tree", "town", TownModel.TOWN_HALF.x - 0.2, 0, 0).get("error"), TownModel.ERR_EDGE, "edge")
	eq(m.place("bench", "town", 0, -5, 0).get("error"), TownModel.ERR_TREE, "wishing tree")
	eq(m.place("bed", "town", -5, 5, 0).get("error"), TownModel.ERR_INDOORS, "beds are indoor")
	eq(m.place("swing", "i999", 0, 0, 0).get("error"), TownModel.ERR_NO_HOUSE, "unknown house")
	eq(m.place("rocket", "town", 0, 0, 0).get("error"), TownModel.ERR_UNKNOWN, "unknown kind")
	var house = m.place("cottage", "town", -8, 0, 0)
	ok(house["ok"], "cottage")
	var hid: String = TownModel.room_space(house["item"]["id"], 0, 0)
	ok(m.place("chair", hid, 0, 0, 0)["ok"], "chair inside")
	eq(m.place("swing", hid, 1, 1, 0).get("error"), TownModel.ERR_OUTDOORS, "swing is outdoor")
	eq(m.place("bookshelf", hid, 3.8, 0, 0).get("error"), TownModel.ERR_EDGE, "room walls")
	eq(m.place("bookshelf", hid, TownModel.ROOM_DOOR.x, TownModel.ROOM_DOOR.y + 0.2, 0).get("error"), TownModel.ERR_DOORWAY, "exit door kept clear")
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
	eq(m.place("cottage", "town", 0, -(TownModel.TOWN_HALF.y - 2.0), 4).get("error"), TownModel.ERR_EDGE, "edge for cottage body")
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
	m.place("bed", TownModel.room_space(h["id"], 1, 0), -2, -1, 0)
	m.place("rug", TownModel.room_space(h["id"], 2, 1), 0, 0, 0)
	var other = m.place("cottage", "town", -9, 0, 0)["item"]
	m.place("chair", TownModel.room_space(other["id"], 0, 0), 0, 0, 0)
	var r = m.remove(h["id"])
	ok(r["ok"], "remove house")
	eq(r["removed"].size(), 3, "house and its two items")
	eq(m.items_in_house(h["id"]).size(), 0, "contents of every floor packed away")
	eq(m.items_in_house(other["id"]).size(), 1, "other house untouched")
	var back = m.restore(r["removed"])
	ok(back["ok"], "undo")
	ok(m.items.has(h["id"]), "original id kept")
	eq(m.items_in_house(h["id"]).size(), 2, "furniture back inside")
	eq(m.items_in(TownModel.room_space(h["id"], 2, 1)).size(), 1, "back in the same attic room")
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
	var hid: String = TownModel.room_space(h["id"], 0, 1)
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
	for sp in AnimalBrain.SPECIES.values():
		needed.append(sp["name"])
		needed.append(sp["hobby"])
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
	var room := TownModel.room_space(h["id"], 0, 0)
	var placed := 0
	for x in range(-3, 4):
		for z in range(-2, 3):
			if m.place("rug", room, x * 1.0, z * 1.0, 0)["ok"]:
				placed += 1
	ok(placed < TownModel.MAX_ROOM_ITEMS, "rug overlap limits density")
	for i in TownModel.MAX_ROOM_ITEMS:
		m.items["x%d" % i] = {"id": "x%d" % i, "kind": "teddy", "space": room, "x": 0.0, "z": 0.0, "rot": 0, "color": 0}
	eq(m.place("teddy", room, 1, 1, 0).get("error"), TownModel.ERR_ROOM_FULL, "room capacity")


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



# ------------------------------------------------------------- animal friends

func _simulate(brain, model, seconds: float, kids := [], watch := func(_b): pass) -> void:
	for i in int(seconds / AnimalBrain.STEP):
		brain.tick(model, kids)
		watch.call(brain)


func test_animals_roam_and_play() -> void:
	var m = TownModel.make_default()
	m.place("seesaw", "town", 9.0, -6.0, 0)
	var before := JSON.stringify(m.to_dict())
	var brain = AnimalBrain.new(11)
	brain.spawn(m)
	eq(brain.animals.size(), 5, "five animal friends")
	var seen := {}
	var travelled := {}
	var last := {}
	var bad := [0]
	_simulate(brain, m, 240.0, [], func(b):
		for a in b.animals:
			seen.get_or_add(a["kind"], {})[a["action"]] = true
			var r: float = AnimalBrain.SPECIES[a["kind"]]["radius"]
			if not AnimalBrain.is_clear(m, a["pos"], r) or is_nan(a["pos"].x):
				bad[0] += 1
			if last.has(a["kind"]):
				travelled[a["kind"]] = travelled.get(a["kind"], 0.0) + last[a["kind"]].distance_to(a["pos"])
			last[a["kind"]] = a["pos"])
	eq(bad[0], 0, "animals never stand inside items, the Wishing Tree or off the edge")
	for kind in AnimalBrain.ORDER:
		ok(travelled.get(kind, 0.0) > 15.0, "%s roams around (%.0f m)" % [kind, travelled.get(kind, 0.0)])
	ok(seen["pig"].has("splash"), "pig splashes by the pond")
	ok(seen["rabbit"].has("hop") and seen["rabbit"].has("garden"), "rabbit hops and gardens")
	ok(seen["sheep"].has("sing"), "sheep sings by lamps, benches and swings")
	ok(seen["dog"].has("ball") and seen["dog"].has("run"), "dog kicks and chases its ball")
	ok(seen["elephant"].has("look") or seen["elephant"].has("spray"), "elephant explores")
	var social := 0
	for kind in seen:
		if seen[kind].has("chat") or seen[kind].has("rest"):
			social += 1
	ok(social >= 3, "animals also rest and chat with each other")
	eq(JSON.stringify(m.to_dict()), before, "animals never change the town or its save")


func test_animals_social() -> void:
	var m = TownModel.make_default()
	var brain = AnimalBrain.new(5)
	brain.spawn(m)
	var pig: Dictionary = brain.animals[0]
	var kid := {"id": 7, "pos": pig["pos"] + Vector2(1.2, 0), "emote": ""}
	var greeted := [false]
	_simulate(brain, m, 3.0, [kid], func(b): greeted[0] = greeted[0] or b.animals[0]["action"] == "greet")
	ok(greeted[0], "an animal greets a child who comes close")
	var sheep: Dictionary = brain.animals[2]
	var dancer := {"id": 8, "pos": sheep["pos"] + Vector2(5, 1), "emote": "dance"}
	var danced := [false]
	_simulate(brain, m, 20.0, [dancer], func(b): danced[0] = danced[0] or b.animals[2]["action"] == "dance")
	ok(danced[0], "the sheep joins a dancing child")
	var dog_near := [INF]
	var player := {"id": 9, "pos": Vector2(-8, 9), "emote": ""}
	_simulate(brain, m, 120.0, [player], func(b):
		if b.animals[3]["action"] in ["ball", "run"]:
			dog_near[0] = minf(dog_near[0], b.animals[3]["pos"].distance_to(player["pos"])))
	ok(dog_near[0] < 7.0, "the dog plays ball near the child (%.1f m)" % dog_near[0])


func test_animals_yield_to_items() -> void:
	var m = TownModel.make_default()
	var brain = AnimalBrain.new(3)
	brain.spawn(m)
	var pig: Dictionary = brain.animals[0]
	var spot: Vector2 = pig["pos"]
	var r: Dictionary = m.place("tree", "town", spot.x, spot.y, 0)
	ok(r["ok"], "a child can place an item right where an animal stands")
	brain.tick(m, [])
	ok(AnimalBrain.is_clear(m, brain.animals[0]["pos"], AnimalBrain.SPECIES["pig"]["radius"]), "the animal steps aside")
	# Boxed in by fences: it must not freeze or walk through them.
	var b2 = AnimalBrain.new(4)
	var m2 = TownModel.new()
	m2.place("pond", "town", 0, 6, 0)
	b2.spawn(m2)
	_simulate(b2, m2, 60.0)
	for a in b2.animals:
		ok(AnimalBrain.is_clear(m2, a["pos"], AnimalBrain.SPECIES[a["kind"]]["radius"]), "%s clear in a bare town" % a["kind"])


func test_animals_deterministic_and_packed() -> void:
	var m = TownModel.make_default()
	var a = AnimalBrain.new(42)
	var b = AnimalBrain.new(42)
	a.spawn(m)
	b.spawn(m)
	_simulate(a, m, 30.0)
	_simulate(b, m, 30.0)
	eq(a.pack(), b.pack(), "same seed and town give the same animals")
	var states := AnimalBrain.unpack(a.pack())
	eq(states.size(), 5, "unpacked all animals")
	for i in states.size():
		ok(states[i]["pos"].distance_to(a.animals[i]["pos"]) < 0.001 and states[i]["action"] == a.animals[i]["action"], "%s survives packing" % states[i]["kind"])
	eq(a.pack().size() * 4, 120, "network state is 120 bytes")
	eq(AnimalBrain.unpack(PackedFloat32Array([1, 2, 3])).size(), 0, "short packets ignored")


func test_animals_without_favorites() -> void:
	var m = TownModel.new()   # no pond, flowers, lamps or benches
	var brain = AnimalBrain.new(9)
	brain.spawn(m)
	var moved := [0.0]
	var start: Vector2 = brain.animals[0]["pos"]
	_simulate(brain, m, 60.0, [], func(b): moved[0] = maxf(moved[0], b.animals[0]["pos"].distance_to(start)))
	ok(moved[0] > 2.0, "the pig still wanders when there is no pond")


# ------------------------------------------------------------- placement tools

## Layout like the HUD: tools centered above a toy box, or under the top bar.
func _zones(view: Rect2, tools := Vector2(560, 150), catalog_h := 316.0) -> Dictionary:
	var x := view.position.x + (view.size.x - tools.x) * 0.5
	var catalog_top := view.end.y - catalog_h
	return {"bottom": Rect2(x, catalog_top - tools.y - 8, tools.x, tools.y).merge(Rect2(view.position.x, catalog_top, view.size.x - 252, catalog_h)),
		"top": Rect2(x, view.position.y + 104, tools.x, tools.y)}


func test_dock_choice() -> void:
	# 4:3 iPad, iPad Air 5 (2360x1640) and iPhone landscape with notch/home-indicator insets.
	var views := {
		"ipad": Rect2(0, 0, 1366, 1024),
		"ipad_air": Rect2(0, 0, 1475, 1024),
		"iphone": Rect2(154, 0, 2208 - 308, 1024 - 55),
	}
	for name in views:
		var view: Rect2 = views[name]
		var z := _zones(view)
		var covered := 0
		for fx in [0.05, 0.3, 0.5, 0.7, 0.95]:
			for fy in [0.15, 0.35, 0.55, 0.7, 0.85, 0.95]:
				var c := view.position + view.size * Vector2(fx, fy)
				var ghost := Rect2(c - Vector2(70, 90), Vector2(140, 120))
				var dock := "bottom"
				for i in 3:
					dock = PlacementDock.choose(dock, ghost, z["bottom"], z["top"])
				var hidden: float = PlacementDock.overlap(ghost, z[dock])
				if hidden > 0.0:
					covered += 1
				if fy >= 0.7 and fx > 0.2 and fx < 0.8:
					eq(dock, "top", "%s: item low in the middle (%.2f, %.2f) moves the tools up" % [name, fx, fy])
				if fy <= 0.35:
					eq(dock, "bottom", "%s: item high up (%.2f, %.2f) keeps the tools at the bottom" % [name, fx, fy])
		eq(covered, 0, "%s: no tested position leaves the item under a menu" % name)
		ok(z["top"].position.y >= view.position.y + 100 and z["top"].end.x <= view.end.x, "%s: top tools inside the safe area" % name)


func test_dock_hysteresis() -> void:
	var view := Rect2(0, 0, 1366, 1024)
	var z := _zones(view)
	var boundary: float = z["bottom"].position.y
	var dock := "bottom"
	var switches := 0
	# A finger wobbling around the boundary for a while.
	for i in 200:
		var y := boundary - 125 + sin(i * 0.7) * 30.0
		var ghost := Rect2(Vector2(640, y), Vector2(120, 120))
		var next := PlacementDock.choose(dock, ghost, z["bottom"], z["top"])
		if next != dock:
			switches += 1
		dock = next
	ok(switches <= 1, "no back-and-forth while wobbling at the edge (%d switches)" % switches)
	dock = PlacementDock.choose("top", Rect2(640, boundary - 160, 120, 120), z["bottom"], z["top"])
	eq(dock, "top", "stays up until the item is clearly away from the bottom")
	dock = PlacementDock.choose("top", Rect2(640, 300, 120, 120), z["bottom"], z["top"])
	eq(dock, "bottom", "returns to the usual place when the item is high again")
	dock = PlacementDock.choose("top", Rect2(640, 110, 140, 160), z["bottom"], z["top"])
	eq(dock, "bottom", "moves back down if the item goes under the top tools")


# ------------------------------------------------------------- music

func test_music() -> void:
	var music: Node = root.get_node("Music")
	var stream = load("res://assets/audio/meadow_lanterns.wav")
	ok(stream is AudioStreamWAV, "music track imports as audio")
	if stream is AudioStreamWAV:
		ok(absf(stream.get_length() - 16 * 4 * 60.0 / 84.0) < 0.05, "16 bars at 84 BPM (%.2f s)" % stream.get_length())
	var saved := [music.music_on, music.music_volume, music.sounds_on]
	music.set_context("town")
	music.set_music_volume(1.0)
	ok(music.target_db() <= -9.0, "full volume stays gentle (%.1f dB)" % music.target_db())
	music.set_context("home")
	ok(music.target_db() < -12.0, "softer inside houses")
	music.set_music_on(false)
	ok(music.target_db() <= -79.0, "music can be switched off")
	music.set_sounds_on(false)
	ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "sounds off mutes the effects bus")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	eq([cfg.get_value("audio", "music_on"), cfg.get_value("audio", "sounds_on")], [false, false], "audio settings saved")
	music.set_music_on(saved[0])
	music.set_music_volume(saved[1])
	music.set_sounds_on(saved[2])
	music.set_context("silent")



# ------------------------------------------------------------- houses with floors

func test_house_rooms_and_stairs() -> void:
	var m = TownModel.make_default()
	var house: String = m.items_in("town").filter(func(i): return i["kind"] == "cottage")[0]["id"]
	var rooms := []
	for f in TownModel.FLOORS:
		for r in TownModel.ROOMS_PER_FLOOR:
			rooms.append(TownModel.room_space(house, f, r))
	eq(rooms.size(), 6, "three floors with two rooms each")
	for room in rooms:
		ok(m.is_space(room), "%s is a valid room" % room)
		ok(TownModel.room_name(room) != "", "%s has a name" % room)
	ok(not m.is_space(house + ":3:0") and not m.is_space(house + ":0:2") and not m.is_space("i999:0:0"), "no rooms outside the house plan")
	# Every room reaches the front door, and every doorway leads back the same way.
	for room in rooms:
		var seen := {room: true}
		var queue := [room]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for p in TownModel.portals(cur):
				if p["target"] != "town" and not seen.has(p["target"]):
					seen[p["target"]] = true
					queue.append(p["target"])
		eq(seen.size(), 6, "%s connects to all six rooms" % room)
		for p in TownModel.portals(room):
			if p["target"] == "town":
				continue
			var back := TownModel.portals(p["target"]).filter(func(q): return q["target"] == room)
			eq(back.size(), 1, "%s -> %s has a way back" % [room, p["target"]])
			var land := TownModel.arrival(room, p["target"])
			ok(absf(land.x) < TownModel.ROOM_HALF.x - 0.3 and absf(land.y) < TownModel.ROOM_HALF.y - 0.3, "arrival in %s is inside the room" % p["target"])
			ok(m.items_in(p["target"]).all(func(i): return Vector2(i["x"], i["z"]).distance_to(land) > Catalog.get_def(i["kind"])["radius"] * 0.9 or Catalog.get_def(i["kind"])["layer"] == "flat"), "arrival in %s is not inside furniture" % p["target"])
	var exits := 0
	for room in rooms:
		exits += TownModel.portals(room).filter(func(p): return p["kind"] == "exit").size()
	eq(exits, 1, "one front door, on the ground floor")
	var ups := TownModel.portals(rooms[0]).filter(func(p): return p["kind"] == "up")
	eq(ups.size(), 1, "stairs up from the living room")
	eq(TownModel.portals(TownModel.room_space(house, 2, 0)).filter(func(p): return p["kind"] == "up").size(), 0, "no stairs above the attic")
	# Furniture is per room, and doorways stay clear.
	ok(m.place("chair", rooms[3], -1.5, 1.0, 0)["ok"], "furnish the playroom")
	eq(m.items_in(rooms[3]).filter(func(i): return i["kind"] == "chair").size(), 1, "chair is in the playroom")
	eq(m.items_in(rooms[2]).filter(func(i): return i["kind"] == "chair").size(), 0, "not in the bedroom")
	eq(m.place("bookshelf", rooms[0], TownModel.STAIRS_UP.x, TownModel.STAIRS_UP.y + 0.3, 0).get("error"), TownModel.ERR_DOORWAY, "stairs kept clear")
	eq(m.place("bookshelf", rooms[1], TownModel.ROOM_DOOR.x, TownModel.ROOM_DOOR.y + 0.3, 0).get("error"), TownModel.ERR_DOORWAY, "kitchen door kept clear")
	eq(m.place("sofa", rooms[0], TownModel.SIDE_DOOR.x + 0.4, TownModel.SIDE_DOOR.y, 0).get("error"), TownModel.ERR_DOORWAY, "side door kept clear")
	var before: int = m.items_in_house(house).size()
	var removed: Dictionary = m.remove(house)
	eq(removed["removed"].size(), before + 1, "putting the house away packs all six rooms")


func test_migrate_v1_save() -> void:
	# A real version-1 save: the old single room used the cottage id as its space.
	var v1 := {"schema": 1, "next_id": 9, "evening": true, "lanterns": {"tea_party": {"by": ["Sky"], "t": 5}}, "items": [
		{"id": "i1", "kind": "cottage", "space": "town", "x": -9.0, "z": -6.0, "rot": 1, "color": 2},
		{"id": "i2", "kind": "bed", "space": "i1", "x": -2.6, "z": -1.8, "rot": 0, "color": 5},
		{"id": "i3", "kind": "bookshelf", "space": "i1", "x": -0.6, "z": -2.3, "rot": 0, "color": 6},
		{"id": "i4", "kind": "rug", "space": "i1", "x": 0.0, "z": 0.3, "rot": 0, "color": 2},
		{"id": "i5", "kind": "tree", "space": "town", "x": 15.0, "z": 13.0, "rot": 0, "color": 5},
	]}
	var m = TownModel.new()
	ok(m.from_dict(v1), "version 1 save loads")
	var living := TownModel.room_space("i1", 0, 0)
	eq(m.items_in(living).size(), 3, "old furniture moved into the ground-floor living room")
	eq(m.last_migration.get("furniture"), 3, "migration report counts furniture")
	eq(m.last_migration.get("nudged"), 1, "the bookshelf in front of the new stairs was nudged")
	var shelf: Dictionary = m.items["i3"]
	eq(m.check("bookshelf", living, shelf["x"], shelf["z"], 0, "i3"), "", "nudged bookshelf is valid")
	eq([m.items["i2"]["x"], m.items["i2"]["z"]], [-2.6, -1.8], "other furniture keeps its place")
	ok(m.items.has("i5") and m.lanterns.has("tea_party") and m.evening, "town, lanterns and evening kept")
	var again = TownModel.new()
	ok(again.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "migrated town saves as version 2")
	eq(again.to_dict()["schema"], 2, "schema 2 written")
	eq(again.items, m.items, "nothing changes on the next load")
	ok(again.last_migration.is_empty(), "no second migration")


func test_bigger_town() -> void:
	eq(TownModel.TOWN_HALF, Vector2(26, 22), "outdoor area is 52 x 44 m")
	var m = TownModel.make_default()
	var far := 0
	for item in m.items_in("town"):
		if absf(item["x"]) > 16.0 or absf(item["z"]) > 14.0:
			far += 1
	ok(far >= 15, "the new countryside has things to discover (%d items)" % far)
	ok(m.place("cottage", "town", 21.0, -8.0, 6)["ok"], "room to build beyond the old edge")



# ------------------------------------------------------------- scale contract

const H := 1.30   # neutral avatar head top, design/object-scale-and-surfaces.md


func _model_bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).material_override as BaseMaterial3D
		if mat and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue   # contact shadows are not part of the object
		var xf := Transform3D()
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_scale_contract() -> void:
	var Props = load("res://scripts/art/props.gd")
	var kid = load("res://scripts/art/kid.gd").new()
	root.add_child(kid)
	kid.setup(Avatar.PRESETS[0], false)
	var head := 0.0
	for mi in kid.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var shown := true
		var p: Node = mi
		while p != kid:
			shown = shown and (p as Node3D).visible
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		if shown and not (mi.material_override is BaseMaterial3D and mi.material_override.transparency != 0):
			head = maxf(head, (xf * mi.get_aabb()).end.y)
	ok(absf(head - H) < 0.06, "neutral avatar head top is H = 1.30 (measured %.2f)" % head)
	kid.free()
	for kind in Catalog.ITEMS:
		var d: Dictionary = Catalog.ITEMS[kind]
		ok(d.has_all(["size_class", "anchor", "bounds", "tabletop_eligible"]), "%s has the contract fields" % kind)
		ok(d["size_class"] in ["landmark", "tree", "large", "medium", "small", "flat"] and d["anchor"] in ["ground", "wall", "ceiling"], "%s class and anchor" % kind)
		var n: Node3D = Props.build(kind, d["color"], 1)
		var b := _model_bounds(n)
		n.free()
		var want: Vector3 = d["bounds"]
		ok((b.size - want).abs().x < 0.12 and (b.size - want).abs().y < 0.12 and (b.size - want).abs().z < 0.12,
			"%s model matches its bounds (built %s, catalog %s)" % [kind, b.size, want])
		if d["anchor"] == "ground":
			ok(b.position.y > -0.15 and b.position.y < 0.1, "%s stands on the ground (bottom %.2f)" % [kind, b.position.y])
		elif d["anchor"] == "wall":
			ok(absf(b.get_center().y) < 0.05 and b.position.z > -0.02, "%s: origin is its center on the wall plane" % kind)
		else:
			ok(b.end.y < 0.05 and b.end.y > -0.1, "%s: origin is its ceiling hook (top %.2f)" % [kind, b.end.y])
		ok(d["radius"] <= 0.75 * maxf(want.x, want.z) + 0.15, "%s footprint stays close to the model size" % kind)
		if d["size_class"] == "tree":
			ok(d["radius"] < 0.5 * maxf(want.x, want.z), "%s trunk footprint is narrower than its canopy" % kind)
		match d["size_class"]:
			"tree":
				ok(want.y >= 1.6 * H and want.y <= 2.0 * H, "%s is 1.6-2.0 H tall (%.2f H)" % [kind, want.y / H])
				ok(maxf(want.x, want.z) <= 2.0, "%s canopy at most 2 units wide" % kind)
			"small":
				ok(want.y >= 0.2 * H and want.y <= 0.45 * H, "%s is 0.2-0.45 H (%.2f H)" % [kind, want.y / H])
		if d["tabletop_eligible"]:
			ok(Catalog.fits_on(kind, "table"), "%s fits on a table" % kind)
	var chair: Vector3 = Catalog.ITEMS["chair"]["bounds"]
	for big in ["table", "sofa", "bed", "bookshelf"]:
		var bb: Vector3 = Catalog.ITEMS[big]["bounds"]
		ok(maxf(bb.x, bb.z) >= 1.5 * chair.x, "%s is clearly larger than a chair" % big)
	ok(Catalog.ITEMS["cottage"]["bounds"].y > 4.0 * H, "the cottage landmark is not shrunk")
	eq(Catalog.height("tree"), Catalog.ITEMS["tree"]["bounds"].y, "heights come from the contract bounds")


# ------------------------------------------------------------- tabletop

func _table_town() -> Array:
	var m = TownModel.new()
	var t = m.place("table", "town", 4.0, 4.0, 0)["item"]
	return [m, t["id"]]


func test_tabletop_place_and_reject() -> void:
	var setup := _table_town()
	var m = setup[0]
	var table: String = setup[1]
	var pot: Dictionary = m.place("plant", "town", 9, 9, 0, 3, table)
	ok(pot["ok"], "a flower pot goes on the table")
	eq(pot["item"].get("host"), table, "it remembers its table")
	eq([pot["item"]["x"], pot["item"]["z"]], [4.0, 4.0], "it sits on the surface center, not where it was dropped")
	eq(m.place("teddy", "town", 4, 4, 0, -2, table).get("error"), TownModel.ERR_SURFACE_TAKEN, "a second item is rejected")
	eq(m.place("chair", "town", 4, 4, 0, -2, table).get("error"), TownModel.ERR_NO_FIT, "a chair cannot go on a table")
	eq(m.place("table", "town", 4, 4, 0, -2, table).get("error"), TownModel.ERR_NO_FIT, "no table on a table")
	eq(m.place("teddy", "town", 4, 4, 0, -2, pot["item"]["id"]).get("error"), TownModel.ERR_NOT_SUPPORT, "nothing stacks on the decoration")
	var bench = m.place("bench", "town", -4, 4, 0)["item"]
	eq(m.place("teddy", "town", -4, 4, 0, -2, bench["id"]).get("error"), TownModel.ERR_NOT_SUPPORT, "only declared surfaces hold things")
	ok(m.place("chair", "town", 4.0, 5.2, 0)["ok"], "chairs still go around the table")
	ok(m.place("plant", "town", 5.3, 3.0, 0)["ok"], "flower pots still go on the floor")
	var room = m.place("cottage", "town", -9, -6, 0)["item"]
	var kitchen := TownModel.room_space(room["id"], 0, 1)
	var t2 = m.place("table", kitchen, 0, 0, 0)["item"]
	eq(m.place("teddy", "town", 0, 0, 0, -2, t2["id"]).get("error"), TownModel.ERR_NOT_SUPPORT, "host and item share a space")
	ok(m.place("teddy", kitchen, 0, 0, 0, -2, t2["id"])["ok"], "teddy on the kitchen table")


func test_tabletop_follow_remove_undo() -> void:
	var setup := _table_town()
	var m = setup[0]
	var table: String = setup[1]
	var pot: String = m.place("plant", "town", 0, 0, 1, 3, table)["item"]["id"]
	var r: Dictionary = m.move(table, 7.0, 2.0, 2)
	ok(r["ok"], "move the table")
	eq(r["moved"].size(), 1, "the move reports the pot that came along")
	eq([m.items[pot]["x"], m.items[pot]["z"], m.items[pot]["rot"]], [7.0, 2.0, 3], "pot follows the table and turns with it")
	ok(m.move(pot, 1.0, 1.0, 0)["ok"] and not m.items[pot].has("host"), "the pot can be lifted onto the floor")
	ok(m.move(pot, 0, 0, 0, table)["ok"] and m.items[pot].get("host") == table, "and put back on the table")
	var rem: Dictionary = m.remove(table)
	eq(rem["removed"].size(), 2, "putting the table away packs its pot too")
	ok(not m.items.has(pot), "pot gone with the table")
	var back: Dictionary = m.restore(rem["removed"])
	ok(back["ok"] and m.items.has(table) and m.items.get(pot, {}).get("host") == table, "undo brings back both, still on top")
	# Removing only the pot leaves the table free again.
	m.remove(pot)
	ok(m.place("plant", "town", 0, 0, 0, 1, table)["ok"], "a free table accepts a new decoration")


func test_tabletop_saves() -> void:
	var setup := _table_town()
	var m = setup[0]
	var table: String = setup[1]
	var pot: String = m.place("plant", "town", 0, 0, 0, 3, table)["item"]["id"]
	var m2 = TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "save with a decoration loads")
	eq(m2.items[pot].get("host"), table, "the decoration is still on its table")
	eq(m2.place("teddy", "town", 0, 0, 0, -2, table).get("error"), TownModel.ERR_SURFACE_TAKEN, "occupancy survives the reload")
	# Broken data: a missing host and two items claiming one table. Nothing is deleted.
	var data: Dictionary = m.to_dict()
	data["items"].append({"id": "i90", "kind": "teddy", "space": "town", "x": 2.0, "z": 2.0, "rot": 0, "color": 7, "host": table})
	data["items"].append({"id": "i91", "kind": "teddy", "space": "town", "x": -3.0, "z": 6.0, "rot": 0, "color": 7, "host": "i404"})
	data["next_id"] = 92
	var m3 = TownModel.new()
	ok(m3.from_dict(data), "save with broken host data loads")
	eq(m3.items.size(), m.items.size() + 2, "no item is lost")
	eq(m3.attachments_of(table).size(), 1, "the table still holds exactly one item")
	ok(not m3.items["i91"].has("host") and m3.items["i91"]["x"] == -3.0, "an item with a missing table stays where it was on the floor")
	# Old saves (no host field anywhere) load unchanged.
	var old = TownModel.make_default()
	var plain := JSON.stringify(old.to_dict())
	var m4 = TownModel.new()
	ok(m4.from_dict(JSON.parse_string(plain)) and JSON.stringify(m4.to_dict()) == plain, "older saves load unchanged")


## Two players drop a decoration on the same table at the same moment: the
## authority applies them in order, so exactly one wins.
func test_tabletop_session_race() -> void:
	var path := "user://test_tabletop_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	var t := await _result(Session.place("table", "town", Vector2(-6, 9), 0, -2))
	var table: String = t["item"]["id"]
	var a: int = Session.place("plant", "town", Vector2(-6, 9), 0, 3, table)
	var b: int = Session.place("plant", "town", Vector2(-6, 9), 0, 6, table)
	var results := {}
	var cb := func(r_id: int, r: Dictionary): results[r_id] = r
	Session.request_done.connect(cb)
	for i in 5:
		await process_frame
	Session.request_done.disconnect(cb)
	ok(results.get(a, {}).get("ok", false), "first decoration lands")
	eq(results.get(b, {}).get("error"), TownModel.ERR_SURFACE_TAKEN, "second one is turned away")
	eq(Session.model.attachments_of(table).size(), 1, "exactly one item on the table")
	Session.leave()



## Review case: a decoration older than its table, inside a cottage that is put
## away and brought back. Restore must rebuild cottage -> table -> decoration.
func test_tabletop_restore_order() -> void:
	var m = TownModel.new()
	var house: String = m.place("cottage", "town", 0, 0, 0)["item"]["id"]
	var kitchen := TownModel.room_space(house, 0, 1)
	var pot: String = m.place("plant", kitchen, -2.0, 1.5, 0, 3)["item"]["id"]   # created first
	var table: String = m.place("table", kitchen, 0.5, 0.5, 0)["item"]["id"]
	ok(m.move(pot, 0, 0, 0, table)["ok"], "older pot moved onto the newer table")
	var removed: Array = m.remove(house)["removed"]
	var order: Array = removed.map(func(e): return e["id"])
	ok(order.find(pot) < order.find(table), "removal lists the decoration before its table (the risky order)")
	var inputs := {"as removed": removed, "reversed": removed.duplicate(), "shuffled": removed.duplicate()}
	inputs["reversed"].reverse()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(inputs["shuffled"].size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = inputs["shuffled"][i]
		inputs["shuffled"][i] = inputs["shuffled"][j]
		inputs["shuffled"][j] = tmp
	for name in inputs:
		var copy = TownModel.new()
		copy.from_dict(m.to_dict())
		var r: Dictionary = copy.restore(inputs[name])
		ok(r["ok"] and r["skipped"].is_empty(), "%s: everything comes back" % name)
		ok(copy.items.has(house) and copy.items.has(table) and copy.items.has(pot), "%s: ids are kept" % name)
		eq(copy.items.get(pot, {}).get("host", ""), table, "%s: the pot is back on its table, not on the floor" % name)
		eq(copy.items.get(table, {}).get("space", ""), kitchen, "%s: the table is back in the kitchen" % name)
	# Partial failure: the table's spot is taken. The pot falls back to the floor; nothing is dropped silently.
	var t2 = TownModel.new()
	var tbl: String = t2.place("table", "town", 4, 4, 0)["item"]["id"]
	var pot2: String = t2.place("plant", "town", 0, 0, 0, 3, tbl)["item"]["id"]
	var gone: Array = t2.remove(tbl)["removed"]
	ok(t2.place("tree", "town", 4, 5.0, 0)["ok"], "a tree now overlaps where the table stood")
	var r2: Dictionary = t2.restore(gone)
	eq(r2["skipped"], [tbl], "the blocked table is reported, not silently dropped")
	ok(t2.items.has(pot2) and not t2.items[pot2].has("host"), "its pot comes back on the floor")
	# A cottage that cannot come back reports everything that was inside.
	var t3 = TownModel.new()
	var h3: String = t3.place("cottage", "town", 0, 0, 0)["item"]["id"]
	t3.place("bed", TownModel.room_space(h3, 1, 0), 0, 0.5, 0)
	var gone3: Array = t3.remove(h3)["removed"]
	t3.place("pond", "town", 0, 0, 0)
	var r3: Dictionary = t3.restore(gone3)
	eq(r3["skipped"].size(), 2, "a blocked cottage reports itself and its bed")


func test_tabletop_rotated_fit() -> void:
	var surface: Dictionary = Catalog.support_surface("table")
	var area: Vector2 = surface["usable_size_xz"]
	ok(area.length() <= 1.2 + 0.001, "usable area is inside the round 1.2 top (diagonal %.3f)" % area.length())
	var long_item := Vector3(0.84, 0.3, 0.5)
	ok(Catalog.fits_surface(long_item, surface, 0), "a 0.84 x 0.5 item fits straight")
	ok(not Catalog.fits_surface(long_item, surface, 1), "the same item turned 45 degrees overhangs and is refused")
	ok(Catalog.fits_surface(long_item, surface, 4), "turned 180 degrees it fits again")
	ok(not Catalog.fits_surface(Vector3(0.9, 0.3, 0.9), surface, 0), "a 0.9 square would overhang the round top")
	for kind in ["plant", "teddy"]:
		for steps in 8:
			ok(Catalog.fits_on(kind, "table", steps), "%s fits at %d x 45 degrees" % [kind, steps])
	var m = TownModel.new()
	var table: Dictionary = m.place("table", "town", 0, 0, 3)["item"]
	ok(m.place("plant", "town", 0, 0, 5, 3, table["id"])["ok"], "rotation is checked relative to the table")



## The reviewed pilot-10 models (art/pilot-10-v1): markers, support, fit and the
## two wall/ceiling models that are not placeable yet.
func test_modeled_assets() -> void:
	var Props = load("res://scripts/art/props.gd")
	var modeled := Catalog.ITEMS.keys().filter(func(k): return Catalog.ITEMS[k].has("model"))
	eq(modeled.size(), 10 + 130 + 13 + 21 + 42, "the ten pilot models, the 130 production models (release r1), the 13 pet room models (p001), the 21 kitchen and game room models (p002) and the 42 wall and ceiling models (r2) are placeable")
	for kind in modeled:
		ok(ResourceLoader.exists(Catalog.ITEMS[kind]["model"]), "%s model is in the game" % kind)
		eq(Catalog.ITEMS[kind]["color"], -1, "%s keeps its modeled colors (not paintable)" % kind)
	eq(Catalog.PENDING_MODELS.size(), 0, "no reviewed model is left pending")
	eq(Catalog.anchor("wall_clock"), "wall", "the clock hangs on a wall")
	eq(Catalog.anchor("bird_mobile"), "ceiling", "the mobile hangs from the ceiling")
	var table: Node3D = Props.build("cozy_round_table", -1, 1)
	var support := table.get_node_or_null("Support0") as Node3D
	ok(support != null and support.position.distance_to(Catalog.support_surface("cozy_round_table")["local_position"]) < 0.01,
		"the table's Support0 marker matches its support surface")
	table.free()
	var chair: Node3D = Props.build("scallop_chair", -1, 1)
	ok(chair.get_node_or_null("Seat0") != null and absf(chair.get_node("Seat0").position.y - 0.56) < 0.01, "chair sits children at its Seat0 marker")
	chair.free()
	var bed: Node3D = Props.build("scallop_bed", -1, 1)
	ok(bed.get_node_or_null("Sleep0") != null, "bed rests children at its Sleep0 marker")
	bed.free()
	var lamp: Node3D = Props.build("desk_lamp", -1, 1)
	ok(lamp.find_children("*", "OmniLight3D", true, false).size() == 1, "desk lamp lights up at its Light0 marker in the evening")
	lamp.free()
	# Support fit, truthfully: the lamp's turned box is about 0.565 at 45 degrees.
	for steps in [0, 2, 4, 6]:
		ok(Catalog.fits_on("desk_lamp", "cozy_round_table", steps), "lamp fits the round table at %d x 45 degrees" % steps)
	for steps in [1, 3, 5, 7]:
		ok(not Catalog.fits_on("desk_lamp", "cozy_round_table", steps), "lamp turned %d x 45 degrees would overhang: refused" % steps)
	for steps in 8:
		ok(Catalog.fits_on("flower_pot_bloom", "cozy_round_table", steps), "blooming pot fits at %d x 45 degrees" % steps)
	ok(not Catalog.fits_on("chair", "cozy_round_table") and Catalog.support_surface("curved_counter").is_empty(), "the counter declares no surface and chairs never go on tables")
	var m = TownModel.new()
	var house: String = m.place("cottage", "town", 0, 0, 0)["item"]["id"]
	var kitchen := TownModel.room_space(house, 0, 1)
	var t: String = m.place("cozy_round_table", kitchen, 0.5, 0.5, 0)["item"]["id"]
	eq(m.place("desk_lamp", kitchen, 0, 0, 1, -2, t).get("error"), TownModel.ERR_NO_FIT, "a lamp turned 45 degrees is refused on the new table")
	ok(m.place("desk_lamp", kitchen, 0, 0, 2, -2, t)["ok"], "the lamp turned 90 degrees fits")
	eq(m.place("flower_pot_bloom", kitchen, 0, 0, 0, -2, t).get("error"), TownModel.ERR_SURFACE_TAKEN, "still one item per table")
	ok(m.place("scallop_bed", TownModel.room_space(house, 1, 0), 0.5, 0.5, 0)["ok"] and m.place("curved_counter", kitchen, -1.5, 1.8, 0)["ok"], "bed and counter place on the floor")



# ------------------------------------------------------------- activities (design/playfulness-proposals.md)

func _house(m) -> Dictionary:
	var h: String = m.place("cottage", "town", 0, 0, 0)["item"]["id"]
	return {"id": h, "living": TownModel.room_space(h, 0, 0), "kitchen": TownModel.room_space(h, 0, 1), "attic": TownModel.room_space(h, 2, 0)}


func test_mounted_items() -> void:
	var m = TownModel.new()
	var h := _house(m)
	var clock: Dictionary = m.place("wall_clock", h["living"], 0.4, -2.1, 3)
	ok(clock["ok"], "a clock goes on the back wall")
	eq([clock["item"]["z"], clock["item"]["rot"], clock["item"]["y"]], [-TownModel.ROOM_HALF.y, 0, 1.5], "it snaps onto the wall, faces into the room, at 1.5 m")
	eq(m.place("wall_clock", h["living"], 2.5, -2.5, 0).get("error"), TownModel.ERR_WALL_OPENING, "not over the front door")
	eq(m.place("wall_clock", h["living"], -0.6, -2.6, 0).get("error"), TownModel.ERR_WALL_OPENING, "not over the stairs")
	eq(m.place("wall_clock", h["living"], -3.6, -1.8, 0).get("error"), TownModel.ERR_WALL_OPENING, "not over the window")
	eq(m.place("wall_clock", h["living"], -3.6, 0.3, 0).get("error"), TownModel.ERR_WALL_OPENING, "not over the side door")
	var side: Dictionary = m.place("wall_clock", h["living"], -3.7, 2.0, 0)
	ok(side["ok"] and side["item"]["x"] == -TownModel.ROOM_HALF.x and side["item"]["rot"] == 2, "a clock on the left wall faces +x")
	eq(m.place("wall_clock", h["living"], 0.6, -2.9, 0).get("error"), TownModel.ERR_OVERLAP, "clocks do not overlap on a wall")
	eq(m.place("wall_clock", h["living"], 3.9, -2.9, 0).get("error"), TownModel.ERR_EDGE, "a clock stays within the wall")
	eq(m.place("wall_clock", "town", 0, 8, 0).get("error"), TownModel.ERR_INDOORS, "wall items are for rooms")
	ok(m.place("teddy", h["living"], 0.4, -2.4, 0)["ok"], "things can stand under a wall clock")
	var mobile: Dictionary = m.place("bird_mobile", h["kitchen"], 0.5, 0.5, 0)
	ok(mobile["ok"] and is_equal_approx(mobile["item"]["y"], TownModel.CEILING_Y), "a mobile hangs from the ceiling")
	ok(m.place("table", h["kitchen"], 0.5, 0.5, 0)["ok"], "a table can stand under a mobile")
	eq(m.place("bird_mobile", h["kitchen"], 0.9, 0.5, 0).get("error"), TownModel.ERR_OVERLAP, "mobiles do not tangle")
	eq(m.place("bird_mobile", h["kitchen"], 3.8, 0, 0).get("error"), TownModel.ERR_EDGE, "a mobile stays inside the room")
	var moved: Dictionary = m.move(clock["item"]["id"], 1.5, -1.0, 5)
	ok(moved["ok"] and moved["item"]["rot"] == 0 and moved["item"]["z"] == -TownModel.ROOM_HALF.y, "moving keeps it on the wall")
	var again = TownModel.new()
	ok(again.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "saves with mounted items load")
	eq(again.items[side["item"]["id"]]["y"], 1.5, "mount height survives a reload")
	var room_items: Array = again.items_in(h["living"])
	ok(room_items.filter(func(i): return Catalog.anchor(i["kind"]) != "ground").all(func(i): return Catalog.get_def(i["kind"])["layer"] == "mounted"), "mounted items never block walking")


## Production models r2 (design/model-release-r2.md): 38 ceiling and 4 wall items from frozen b011/b012.
const R2_WALL := ["antler_wall_mount", "bone_doorplate", "breaker_box", "insect_chart_poster"]
const R2_CEILING := ["bare_bulb_pendant", "barrel_wood_pendant", "candle_ring_chandelier", "ceiling_fan_light",
	"ceiling_spotlight_bar", "cone_shade_pendant", "crystal_chandelier", "disco_ball", "dreamy_star_strings",
	"drum_shade_pendant", "dual_hanging_screens", "enamel_pendant", "fluorescent_fixture", "glowing_moss_strands",
	"hanging_cube_lamp", "hanging_guide_board", "hanging_plant_shelves", "hanging_screen", "hanging_shop_sign",
	"ivy_vine_garland", "kitchen_range_hood", "milk_glass_pendant", "nordic_pendant", "paper_chain_garland",
	"paper_lantern_string", "paper_lattice_pendant", "paper_ornithopter", "red_paper_lantern",
	"spiral_crystal_chandelier", "split_curtain_tall", "split_curtain_wide", "stage_light_bar",
	"stained_glass_pendant", "swag_drapery", "three_globe_fixture", "tiered_lantern_cluster", "umbrella_pendant",
	"wood_frame_pendant"]
## The 25 with a Light0 marker (lamps that light up in the evening).
const R2_LIT := ["bare_bulb_pendant", "barrel_wood_pendant", "candle_ring_chandelier", "ceiling_fan_light",
	"ceiling_spotlight_bar", "cone_shade_pendant", "crystal_chandelier", "drum_shade_pendant", "enamel_pendant",
	"fluorescent_fixture", "glowing_moss_strands", "hanging_cube_lamp", "kitchen_range_hood", "milk_glass_pendant",
	"nordic_pendant", "paper_lantern_string", "paper_lattice_pendant", "red_paper_lantern",
	"spiral_crystal_chandelier", "stage_light_bar", "stained_glass_pendant", "three_globe_fixture",
	"tiered_lantern_cluster", "umbrella_pendant", "wood_frame_pendant"]


func test_furniture_r2() -> void:
	var Props = load("res://scripts/art/props.gd")
	var all: Array = R2_WALL + R2_CEILING
	eq(all.size(), 42, "42 r2 references, 42 unique models")
	var bad := []
	for kind in all:
		var d: Dictionary = Catalog.get_def(kind)
		var want := "wall" if R2_WALL.has(kind) else "ceiling"
		if d.is_empty() or d["anchor"] != want or d["layer"] != "mounted" or d["space"] != "home" or d["seats"] != 0 \
				or d["model"] != "res://assets/models/%s.glb" % kind or not ResourceLoader.exists(d["model"]):
			bad.append(kind)
	eq(bad, [], "every r2 model is an indoor wall or ceiling decoration with its frozen GLB")
	# Hanging items leave room for children to walk under them.
	var lowest := 9.0
	for kind in R2_CEILING:
		lowest = minf(lowest, TownModel.CEILING_Y - Catalog.height(kind))
	ok(lowest > H + 0.5, "every ceiling item hangs well above a child's head (lowest bottom %.2f m)" % lowest)
	# Lamps light up from their Light0 marker; decorations do not.
	var lights := []
	for kind in all:
		var n: Node3D = Props.build(kind, -1, 1)
		var lit: bool = n.find_children("*", "OmniLight3D", true, false).size() == 1
		if lit != R2_LIT.has(kind):
			lights.append(kind)
		n.free()
	eq(lights, [], "the 25 lamps light up in the evening, the other 17 do not")
	# The antler mount is hung by its center: the frozen GLB is shifted in the game, not rewritten.
	eq(Catalog.get_def("antler_wall_mount").get("model_offset"), Vector3(0, 0.071, 0), "the antler mount is centered by a catalog offset")
	# Each one can be placed, moved and removed through the same rules as every other item.
	var m = TownModel.new()
	var h := _house(m)
	var placed := {}
	var fails := []
	var rooms := [h["living"], h["kitchen"], h["attic"], TownModel.room_space(h["id"], 1, 0), TownModel.room_space(h["id"], 1, 1), TownModel.room_space(h["id"], 2, 1)]
	var spots_c := [Vector2(-2.0, -1.0), Vector2(0.0, -1.0), Vector2(2.0, -1.0), Vector2(-2.0, 1.2), Vector2(0.0, 1.2), Vector2(2.0, 1.2), Vector2(0.0, 0.1)]
	var n_c := 0
	for kind in R2_CEILING:
		var room: String = rooms[n_c / spots_c.size()]
		var sp: Vector2 = spots_c[n_c % spots_c.size()]
		var r: Dictionary = m.place(kind, room, sp.x, sp.y, 3)
		if not r.get("ok", false) or not is_equal_approx(r["item"]["y"], TownModel.CEILING_Y) or r["item"]["rot"] != 3:   # r15: keeps its turn
			fails.append("%s %s" % [kind, r.get("error", "")])
		else:
			placed[kind] = r["item"]["id"]
		n_c += 1
	for kind in R2_WALL:   # the first free stretch of the attic's back wall (doors, stairs and other items refuse)
		var r := {}
		for step in 25:
			r = m.place(kind, h["attic"], -3.0 + step * 0.25, -2.9, 0)
			if r.get("ok", false):
				break
		if not r.get("ok", false) or r["item"]["z"] != -TownModel.ROOM_HALF.y or not is_equal_approx(r["item"]["y"], Catalog.get_def(kind)["mount_height"]):
			fails.append("%s %s" % [kind, r.get("error", "")])
		else:
			placed[kind] = r["item"]["id"]
	eq(fails, [], "all 42 hang where they were put (ceiling at 2.8 m with the turn asked for, walls at their mount height)")
	var mv: Dictionary = m.move(placed["disco_ball"], 0.3, 0.6, 0)
	ok(mv.get("ok", false) and mv["item"]["y"] == TownModel.CEILING_Y, "a ceiling item moves along the ceiling")
	ok(m.place("kitchen_range_hood", h["kitchen"], 0.0, 0.1, 0).get("error") == TownModel.ERR_OVERLAP, "hanging items do not tangle")
	ok(m.place("ceiling_fan_light", "town", 0, 8, 0).get("error") == TownModel.ERR_INDOORS, "ceiling items are for rooms")
	ok(m.place("teddy", h["living"], -2.0, -1.0, 0)["ok"], "small things stand under a lamp")
	# Saves keep them; an older save without them loads unchanged.
	var again = TownModel.new()
	ok(again.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "a save with r2 items loads")
	ok(placed.keys().all(func(k): return again.items.has(placed[k]) and again.items[placed[k]]["kind"] == k and again.items[placed[k]]["y"] == m.items[placed[k]]["y"]), "all 42 come back in place")
	ok(m.remove(placed["breaker_box"])["ok"] and not m.items.has(placed["breaker_box"]), "a wall item can be put away")


func test_headroom() -> void:
	var m = TownModel.new()
	var h := _house(m)
	var room: String = h["living"]
	var pav: Dictionary = m.place("garden_pavilion", room, 1.2, 0.4, 0)
	ok(pav["ok"], "the room-high pavilion stands in an empty room")
	eq(m.place("cone_shade_pendant", room, 1.2, 0.4, 0).get("error"), TownModel.ERR_HEADROOM, "a lamp cannot hang into the pavilion")
	eq(m.place("bird_mobile", room, 1.4, 0.6, 0).get("error"), TownModel.ERR_HEADROOM, "nor can the older mobile")
	ok(m.place("cone_shade_pendant", room, -3.0, 2.0, 0)["ok"], "it hangs where nothing tall stands")
	m.remove(pav["item"]["id"])
	var lamp: Dictionary = m.place("spiral_crystal_chandelier", room, 1.2, 0.4, 0)
	ok(lamp["ok"], "the chandelier hangs once the pavilion is gone")
	eq(m.place("garden_pavilion", room, 1.2, 0.4, 0).get("error"), TownModel.ERR_HEADROOM, "the pavilion cannot be built into a chandelier")
	var shelf: Dictionary = m.place("bookshelf", room, 1.2, 0.4, 0)
	ok(shelf["ok"], "a 1.6 m bookshelf fits under the lowest-hanging chandelier (bottom %.2f m)" % (TownModel.CEILING_Y - Catalog.height("spiral_crystal_chandelier")))
	m.remove(shelf["item"]["id"])
	var far: Dictionary = m.place("garden_pavilion", room, -1.6, 1.4, 0)
	ok(far["ok"], "the pavilion stands away from the chandelier")
	eq(m.move(far["item"]["id"], 1.0, 0.8, 0).get("error"), TownModel.ERR_HEADROOM, "and cannot be moved under it")
	eq(m.move(lamp["item"]["id"], -1.6, 1.4, 0).get("error"), TownModel.ERR_HEADROOM, "nor the chandelier moved over it")
	ok(m.move(lamp["item"]["id"], 2.0, -1.8, 0)["ok"], "the chandelier moves to free ceiling")
	eq(m.check("bird_mobile", room, -1.6, 1.4, 0), TownModel.ERR_HEADROOM, "the placement preview uses the same rule")
	eq(m.check("bird_mobile", "town", 0, 0, 0), TownModel.ERR_INDOORS, "outdoors is still refused first")


## r16: the scrapbook keeps the game's own photos across restarts, in its own folder only.
func test_photo_store() -> void:
	var PS = load("res://scripts/core/photo_store.gd")
	var dir := "user://test_photo_store"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	var img := Image.create(90, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color.CORNFLOWER_BLUE)
	var a: String = PS.save(img, dir)
	var b: String = PS.save(img, dir)
	ok(a != "" and b != "" and a != b, "two photos taken in the same moment get their own files (%s, %s)" % [a, b])
	ok(Array(DirAccess.get_files_at(dir)).all(func(f): return not f.ends_with(".tmp")), "no half-written files are left")
	# A restart: nothing in memory, only what is on the device.
	eq(PS.list(dir), [a, b], "after a restart the scrapbook finds both photos, oldest first")
	var t: Texture2D = PS.thumbnail(b, dir)
	ok(t != null and t.get_width() == 30 and t.get_height() == 20, "a photo is shown as a smaller picture (30 x 20)")
	# Older photos (before r16 there was no index) are adopted, in time order.
	img.save_png(dir.path_join("photo_1700000000.png"))
	eq(PS.list(dir), ["photo_1700000000.png", a, b], "an older photo of this game without an index entry is shown too, first")
	# Things that are not this game's photos are never listed or opened.
	img.save_png(dir.path_join("holiday.png"))
	img.save_png(dir.path_join("photo_abc.png"))
	var idx := FileAccess.open(dir.path_join("scrapbook.json"), FileAccess.WRITE)
	idx.store_string(JSON.stringify({"version": 1, "photos": [a, "../../secret.png", "/etc/passwd", b, a]}))
	idx.close()
	eq(PS.list(dir), ["photo_1700000000.png", a, b], "other files and unsafe index entries are ignored")
	ok(PS.thumbnail("../photo_1700000000.png", dir) == null, "a path outside the folder is never opened")
	# A missing photo is left out (not an error); the other files stay; nothing is deleted.
	DirAccess.remove_absolute(dir.path_join(a))
	eq(PS.list(dir), ["photo_1700000000.png", b], "a missing photo is left out")
	ok(PS.thumbnail(a, dir) == null, "and has no picture")
	# A damaged photo gives no picture; a damaged index falls back to the files.
	var bad := FileAccess.open(dir.path_join(b), FileAccess.WRITE)
	bad.store_string("not a png")
	bad.close()
	ok(PS.thumbnail(b, dir) == null, "a damaged photo shows no picture and does not stop the scrapbook")
	var broken := FileAccess.open(dir.path_join("scrapbook.json"), FileAccess.WRITE)
	broken.store_string("{")
	broken.close()
	eq(PS.list(dir), ["photo_1700000000.png", b], "a damaged index falls back to this game's photo files")
	var c: String = PS.save(img, dir)
	eq(PS.list(dir), ["photo_1700000000.png", b, c], "and the next photo is kept with the others")
	ok(FileAccess.file_exists(dir.path_join(b)) and FileAccess.file_exists(dir.path_join("holiday.png")), "no file was deleted along the way")
	# Privacy by construction: the store reads only its own folder and never uses the network or other paths.
	var src := FileAccess.get_file_as_string("res://scripts/core/photo_store.gd")
	ok(not src.contains("HTTP") and not src.contains("get_system_dir") and not src.contains("OS.") and not src.contains("Session"), "the photo store uses no network, no system folders and no multiplayer")
	eq(PS.list("user://test_photo_store_none"), [], "no folder yet: an empty scrapbook, no error")


## r16b: the height boundary on real catalog pairs, both placement orders. The footprints are first
## shown to overlap, so only the height rule decides. Top vs the wall item's bottom:
## above (3.5 cm of real overlap), within the 5 cm gap (0.7 mm below), exactly 5 cm below, 5.5 cm below.
func test_wall_clearance_heights() -> void:
	var E := TownModel.ERR_WALL_CLEARANCE
	var cases := [
		["paper_floor_lamp", "towel_rack", true, "3.5 cm above the rack's bottom (real overlap)"],
		["petroom_cat_tree", "egg_bow_wreath", true, "0.7 mm below the wreath's bottom (inside the 5 cm gap)"],
		["cash_machine", "egg_wall_clock", false, "exactly 5 cm below the clock's bottom"],
		["space_suit_display", "towel_rack", false, "5.5 cm below the rack's bottom"],
	]
	for cs in cases:
		var floor_kind: String = cs[0]
		var wall_kind: String = cs[1]
		var want_err: String = E if cs[2] else ""
		var m = TownModel.new()
		var h := _house(m)
		var room: String = h["living"]
		var w: Dictionary = m.place(wall_kind, room, 0.7, -2.9, 0)
		ok(w["ok"], "%s hangs on the back wall" % wall_kind)
		# The nearest spot to the wall that is fine in an empty room (edges, door) and where the two
		# footprints really overlap on the floor plan, facing the room or turned.
		var empty = TownModel.new()
		var he := _house(empty)
		var wb: Dictionary = m._wall_box(wall_kind, w["item"]["x"], w["item"]["z"])
		var z := 0.0
		var spot_rot := -1
		for i in range(20):
			z = -2.95 + 0.05 * i
			for rot in [0, 2]:
				if empty.check(floor_kind, he["living"], 0.7, z, rot) == "" \
						and TownModel._rect_overlaps(wb["rect"], TownModel._floor_corners(floor_kind, 0.7, z, rot)):
					spot_rot = rot
					break
			if spot_rot >= 0:
				break
		ok(spot_rot >= 0, "%s at z %.2f overlaps %s on the floor plan (precondition)" % [floor_kind, z, wall_kind])
		eq(m.check(floor_kind, room, 0.7, z, spot_rot), want_err, "standing %s in front of %s, %s" % [floor_kind, wall_kind, cs[3]])
		# The other order: the standing item first, then the wall item behind it.
		var m2 = TownModel.new()
		var h2 := _house(m2)
		var f: Dictionary = m2.place(floor_kind, h2["living"], 0.7, z, spot_rot)
		ok(f["ok"], "%s stands against the wall first" % floor_kind)
		eq(m2.place(wall_kind, h2["living"], 0.7, -2.9, 0).get("error", ""), want_err, "hanging %s behind %s, %s" % [wall_kind, floor_kind, cs[3]])


## r16: wall items and tall standing items do not meet; low furniture under a picture and tall
## furniture beside one stay allowed. Boxes from the catalog bounds; both orders; moves; rotation.
func test_wall_clearance() -> void:
	var m = TownModel.new()
	var h := _house(m)
	var room: String = h["living"]
	var E := TownModel.ERR_WALL_CLEARANCE
	# Towel rack on the back wall at x 0.7 (spots chosen clear of the door at 2.5 and the stairs at -0.6): 0.48 wide, 0.175 deep, bottom at 1.5 - 0.175 = 1.325 m.
	var rack: Dictionary = m.place("towel_rack", room, 0.7, -2.9, 0)
	ok(rack["ok"], "a towel rack hangs on the back wall")
	eq(m.place("floor_lamp", room, 0.7, -2.7, 0).get("error"), E, "a 1.62 m floor lamp cannot stand in front of it (its back touches the wall)")
	ok(m.check("floor_lamp", room, 0.7, -2.5, 0) == "", "2.5 cm clear of the rack's front it may stand (boundary, valid)")
	eq(m.check("floor_lamp", room, 1.2, -2.7, 0), E, "4 cm under the rack's side is refused (boundary, invalid)")
	ok(m.check("floor_lamp", room, 1.3, -2.7, 0) == "", "right beside the rack is fine (boundary, valid)")
	ok(m.check("table", room, 0.9, -2.35, 0) == "", "a 0.7 m table under the rack is fine (harmless vertical separation)")
	ok(m.check("teddy", room, 0.7, -2.75, 0) == "", "so is a small toy under it")
	# Rotation counts: a bookshelf (1.1 x 0.44) faces the room fine, but turned sideways it reaches the wall.
	ok(m.check("bookshelf", room, 0.8, -2.4, 0) == "", "a bookshelf facing the room clears the rack")
	eq(m.check("bookshelf", room, 0.8, -2.4, 2), E, "turned sideways its end reaches the rack")
	# The other order: a lamp already standing; a wall item cannot be hung behind it.
	var lamp: Dictionary = m.place("floor_lamp", room, -2.4, -2.7, 0)
	ok(lamp["ok"], "a floor lamp stands against the back wall")
	eq(m.place("towel_rack", room, -2.4, -2.9, 0).get("error"), E, "a rack cannot be hung behind the lamp")
	ok(m.place("towel_rack", room, -3.0, -2.9, 0).get("error", "") != E, "beside the lamp the wall is not refused for clearance")
	# Moves keep the state when refused, in both directions.
	var free_lamp: Dictionary = m.place("floor_lamp", room, 0.7, -2.0, 0)
	var before: Dictionary = m.items[free_lamp["item"]["id"]].duplicate()
	eq(m.move(free_lamp["item"]["id"], 0.7, -2.7, 0).get("error"), E, "moving a lamp in front of the rack is refused")
	eq(m.items[free_lamp["item"]["id"]], before, "and the lamp stays exactly where it was")
	var rack_before: Dictionary = m.items[rack["item"]["id"]].duplicate()
	eq(m.move(rack["item"]["id"], -2.4, -2.9, 0).get("error"), E, "moving the rack behind the standing lamp is refused")
	eq(m.items[rack["item"]["id"]], rack_before, "and the rack stays where it was")
	# The left wall too.
	var side: Dictionary = m.place("towel_rack", h["attic"], -3.9, 2.0, 0)
	ok(side["ok"] and side["item"]["x"] == -TownModel.ROOM_HALF.x, "a rack on the attic's left wall")
	eq(m.check("floor_lamp", h["attic"], -3.7, 2.0, 0), E, "a lamp against it is refused")
	ok(m.check("floor_lamp", h["attic"], -3.5, 2.0, 0) == "", "2.5 cm clear it is fine")
	# A table-top item counts with its table's height (effective height, contract of top_of).
	var portrait: Dictionary = m.place("framed_painting_portrait", h["kitchen"], 1.0, -2.9, 0)
	var tbl: Dictionary = m.place("table", h["kitchen"], -1.0, 1.0, 0)
	ok(portrait["ok"] and tbl["ok"], "a low portrait (bottom 1.075 m) and a table")
	ok(m.wall_clearance("flower_pot_bloom", h["kitchen"], 1.0, -2.8, 0) == "", "a 0.57 m pot on the floor fits under the portrait")
	eq(m.wall_clearance("flower_pot_bloom", h["kitchen"], 1.0, -2.8, 0, "", tbl["item"]["id"]), E, "the same pot standing on a 0.7 m table top would reach into it")
	# Older saves with an overlap load untouched; the overlap stays editable and can be corrected.
	var d: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	d["items"].append({"id": "i900", "kind": "floor_lamp", "space": room, "x": 0.7, "z": -2.7, "rot": 0, "color": 1})
	d["next_id"] = 901
	var old = TownModel.new()
	ok(old.from_dict(d) and old.items.has("i900") and is_equal_approx(old.items["i900"]["x"], 0.7) and is_equal_approx(old.items["i900"]["z"], -2.7), "an older save with a lamp in front of the rack loads unchanged (nothing moved or deleted)")
	eq(old.move("i900", 0.7, -2.65, 0).get("error"), E, "nudging it while it still overlaps is refused (state kept)")
	ok(old.move("i900", 0.0, 0.5, 0)["ok"], "moving it clear corrects it")
	ok(old.remove(rack["item"]["id"])["ok"], "and either item can always be put away")


## r15: ceiling items turn in 45-degree steps (stored in the item's rot, like floor items); wall items
## still face into the room; a turn never changes whether a ceiling item fits; saves keep the turn.
func test_ceiling_turn() -> void:
	var m = TownModel.new()
	var h := _house(m)
	var room: String = h["living"]
	var drape: Dictionary = m.place("swag_drapery", room, -1.5, 0.5, 2)
	ok(drape["ok"] and drape["item"]["rot"] == 2 and is_equal_approx(drape["item"]["y"], TownModel.CEILING_Y), "a ceiling item is hung turned a quarter (rot 2)")
	var garland: Dictionary = m.place("paper_chain_garland", room, 1.5, 0.5, 3)
	ok(garland["ok"] and garland["item"]["rot"] == 3, "and at 45-degree steps (rot 3)")
	var mv: Dictionary = m.move(drape["item"]["id"], -1.5, 0.5, 6)
	ok(mv["ok"] and mv["item"]["rot"] == 6 and mv["item"]["x"] == -1.5, "turning in place keeps it where it hangs (rot 6)")
	mv = m.move(drape["item"]["id"], -1.0, 1.0, 9)
	ok(mv["ok"] and mv["item"]["rot"] == 1, "turns wrap around (9 -> 1)")
	# Wall and floor items keep their behaviour.
	var poster: Dictionary = m.place("insect_chart_poster", h["attic"], -2.6, -2.9, 5)
	ok(poster["ok"] and poster["item"]["rot"] == 0, "a wall item still faces into the room (asked 5, got %d)" % poster["item"].get("rot", -1))
	var side: Dictionary = m.place("wall_clock", h["attic"], -3.7, 2.0, 1)
	ok(side["ok"] and side["item"]["rot"] == 2, "and on the left wall faces +x")
	var teddy: Dictionary = m.place("teddy", room, 0.0, -1.5, 3)
	ok(teddy["ok"] and teddy["item"]["rot"] == 3, "floor items turn as before")
	# A turn never makes a refused spot valid, nor a valid one refused (every ceiling rule is a circle).
	var pav: Dictionary = m.place("garden_pavilion", h["kitchen"], 1.2, 0.4, 0)
	var same := true
	for r in 8:
		same = same and m.check("cone_shade_pendant", h["kitchen"], 1.2, 0.4, r) == TownModel.ERR_HEADROOM
		same = same and m.check("swag_drapery", h["kitchen"], 3.6, -2.0, r) == TownModel.ERR_EDGE
		same = same and m.check("swag_drapery", room, -1.0, 1.0, r) == TownModel.ERR_OVERLAP
		same = same and m.check("swag_drapery", h["kitchen"], -2.5, 1.5, r) == ""
	ok(pav["ok"] and same, "every turn gives the same answer: headroom, edge, overlap and a free spot")
	eq(m.move(garland["item"]["id"], -1.0, 1.0, 5).get("error"), TownModel.ERR_OVERLAP, "a turn while moving cannot make it overlap another")
	ok(m.items[garland["item"]["id"]]["rot"] == 3, "a refused move leaves the turn unchanged")
	# Saves keep the turn; an older save (ceiling items at rot 0) loads unchanged.
	var again = TownModel.new()
	ok(again.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "a save with turned ceiling items loads")
	eq([again.items[drape["item"]["id"]]["rot"], again.items[garland["item"]["id"]]["rot"], again.items[poster["item"]["id"]]["rot"], again.items[teddy["item"]["id"]]["rot"]], [1, 3, 0, 3], "every turn survives save and load")
	var old: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	for e in old["items"]:
		if e["id"] == drape["item"]["id"]:
			e["rot"] = 0
	var older = TownModel.new()
	ok(older.from_dict(old) and older.items[drape["item"]["id"]]["rot"] == 0, "an older save with an unturned ceiling item stays unturned")
	# Undo and restore bring the turn back.
	var gone: Dictionary = m.remove(garland["item"]["id"])
	var back: Dictionary = m.restore(gone["removed"])
	ok(back["ok"] and m.items.values().any(func(i): return i["kind"] == "paper_chain_garland" and i["rot"] == 3), "putting it back restores its turn")


## r13 Mac (05_de_toybox_ceiling): two cards both read "Hängelampe mit..." and long German words broke
## mid-word. Every toy box name now fits its card whole, broken only between words, in every language.
func test_toybox_names() -> void:
	var I18n = root.get_node("I18n")
	var UIK = load("res://scripts/ui/ui_kit.gd")
	var Hud = load("res://scripts/ui/hud.gd")
	var keep: String = I18n.current
	var bad := []
	var widened := {}
	var dup := []
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		I18n.set_locale(code, false)
		var font: Font = I18n.ui_font()
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var by_tab := {}
		for kind in Catalog.ITEMS:
			var shown: String = cat.get(Catalog.ITEMS[kind]["name"], Catalog.ITEMS[kind]["name"])
			var fit: Dictionary = UIK.fit_text(font, shown, Hud.CARD_TEXT_W, Hud.CARD_NAME_LINES, Hud.CARD_NAME_SIZES)
			var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			var para := TextParagraph.new()
			para.break_flags = flags
			para.width = fit["width"]
			para.add_string(shown, font, fit["size"])
			var wide := 0.0
			for i in para.get_line_count():
				wide = maxf(wide, para.get_line_width(i))
			if para.get_line_count() > Hud.CARD_NAME_LINES or wide > fit["width"] + 0.5 or fit["size"] < 13:
				bad.append("%s %s" % [code, shown])
			if fit["width"] > Hud.CARD_TEXT_W:
				widened["%s %s" % [code, shown]] = int(fit["width"])
			var tab: String = Catalog.ITEMS[kind]["category"]
			by_tab.get_or_add(tab, {})
			if by_tab[tab].has(shown):
				dup.append("%s %s: %s" % [code, tab, shown])
			by_tab[tab][shown] = true
	eq(bad, [], "every toy box name fits its card whole: at most 3 lines, broken only between words, 13 px or larger")
	eq(dup, [], "no two things in one toy box tab share a name, in any language")
	ok(widened.values().all(func(w): return w <= Hud.CARD_TEXT_W * 1.6), "a card widens only a little for a very long word (%s)" % [widened])
	print("DIAG toy box cards widened for one long word: %s" % [widened])
	I18n.set_locale("de", false)
	var font_de: Font = I18n.ui_font()
	var de: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/de.json"))
	for name in ["Hängelampe mit Trommelschirm", "Hängelampe mit Kegelschirm", "Deckenventilator mit Licht", "Bühnenlichtleiste", "Dunstabzugshaube", "Doppelte Hängebildschirme", "Dreikugelleuchte"]:
		ok(Catalog.ITEMS.values().any(func(d): return de.get(d["name"], "") == name), "%s is a German toy box name" % name)
		var fit: Dictionary = UIK.fit_text(font_de, name, Hud.CARD_TEXT_W, Hud.CARD_NAME_LINES, Hud.CARD_NAME_SIZES)
		ok(fit["lines"] <= 3 and fit["size"] >= 13, "[de] %s shows whole (%d px, %d lines, card text %d px)" % [name, fit["size"], fit["lines"], fit["width"]])
	var a: Dictionary = UIK.fit_text(font_de, "Hängelampe mit Trommelschirm", Hud.CARD_TEXT_W, 3, Hud.CARD_NAME_SIZES)
	ok(a["lines"] >= 2, "the two hanging lamp names keep their distinguishing last word on screen (not cut after \"mit\")")
	I18n.set_locale(keep, false)


func test_wish_rules() -> void:
	for animal in Wishes.ANIMALS:
		eq(Wishes.TEMPLATES[animal].size(), 4, "%s has four wishes" % animal)
		for t in Wishes.TEMPLATES[animal]:
			ok(t["kinds"].all(func(k): return Catalog.allowed_in(k, "town")), "%s uses outdoor toy box items" % t["id"])
			ok(t["text"] != "", "%s has words" % t["id"])
	var m = TownModel.new()
	m.place("pond", "town", 10, 10, 0)
	eq(Wishes.met_at(m, "pig_picnic"), null, "a pond alone is not a picnic")
	m.place("blanket", "town", 10, 6.8, 0)
	ok(Wishes.met_at(m, "pig_picnic") != null, "a blanket near the pond meets Pip's wish")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 20:
		var w := Wishes.pick(m, rng)
		ok(w.is_empty() or Wishes.met_at(m, w["id"]) == null, "picked wishes are never already met")
	var t2 = TownModel.new()
	var a = t2.place("fence", "town", 0, 8, 0)["item"]
	t2.place("fence", "town", 1.4, 8, 0)
	ok(Wishes.met_at(t2, "elephant_fence") == null, "two fences are not three")
	t2.place("fence", "town", -1.4, 8, 0)
	ok(Wishes.met_at(t2, "elephant_fence") != null, "three fences are")
	t2.wrap(a["id"], "p1", "Sky", "", 1)
	ok(Wishes.met_at(t2, "elephant_fence") == null, "wrapped presents do not count")


func test_gift_rules() -> void:
	var m = TownModel.new()
	var bench: String = m.place("bench", "town", 4, 4, 0)["item"]["id"]
	var r: Dictionary = m.wrap(bench, "aaa", "Sunny", "bbb", 4)
	ok(r["ok"] and r["item"]["gift"]["to"] == "bbb", "wrap a bench for one friend")
	eq(m.wrap(bench, "aaa", "Sunny", "bbb", 4).get("error"), TownModel.ERR_CANNOT_WRAP, "already wrapped")
	eq(m.unwrap(bench, "ccc").get("error"), TownModel.ERR_GIFT_FOR_OTHER, "only the recipient opens it")
	var opened: Dictionary = m.unwrap(bench, "bbb")
	ok(opened["ok"] and not m.items[bench].has("gift") and opened["gift"]["from_nick"] == "Sunny", "the recipient opens it into a normal bench")
	eq(m.unwrap(bench, "bbb").get("error"), TownModel.ERR_NOT_GIFT, "it is not a present any more")
	var h := _house(m)
	eq(m.wrap(h["id"], "aaa", "Sunny", "", 0).get("error"), TownModel.ERR_CANNOT_WRAP, "houses are not wrapped")
	var table: String = m.place("table", "town", -6, 6, 0)["item"]["id"]
	var pot: String = m.place("plant", "town", 0, 0, 0, 1, table)["item"]["id"]
	eq(m.wrap(table, "aaa", "Sunny", "", 0).get("error"), TownModel.ERR_CANNOT_WRAP, "not a table carrying something")
	eq(m.wrap(pot, "aaa", "Sunny", "", 0).get("error"), TownModel.ERR_CANNOT_WRAP, "not something sitting on a table")
	var count := 0
	for i in 4:
		var f: String = m.place("flowers", "town", -12 + i * 1.5, -10, 0)["item"]["id"]
		if m.wrap(f, "aaa", "Sunny", "", 0)["ok"]:
			count += 1
	eq(count, TownModel.MAX_GIFTS_PER_RECIPIENT, "at most three presents wait for the same recipient")
	ok(m.unwrap(m.items.values().filter(func(i): return i.has("gift"))[0]["id"], "anyone-can-open")["ok"], "presents for anyone can be opened by anyone")
	var t3 = TownModel.new()
	t3.place("table", "town", 4, 4, 0)
	var c1: String = t3.place("chair", "town", 5.2, 4, 0)["item"]["id"]
	t3.place("chair", "town", 2.8, 4, 0)
	t3.wrap(c1, "a", "A", "", 0)
	ok(not CozySpots.newly_formed(t3).has("tea_party"), "a wrapped chair does not complete a tea party")


func test_garden_rules() -> void:
	var m = TownModel.new()
	var bed: Dictionary = m.place("garden_bed", "town", 6, 6, 0)
	eq(bed["item"]["growth"], 0, "a new garden bed starts as seeds")
	for i in 3:
		ok(m.grow(bed["item"]["id"])["ok"], "it grows (step %d)" % (i + 1))
	eq(m.items[bed["item"]["id"]]["growth"], TownModel.GROWTH_MAX, "full bloom after three steps")
	ok(not m.grow(bed["item"]["id"])["ok"], "it stays in bloom: no wilting, nothing to lose")
	ok(not m.grow(m.place("bush", "town", -6, 6, 0)["item"]["id"])["ok"], "only garden beds grow")
	var m2 = TownModel.new()
	m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	eq(m2.items[bed["item"]["id"]]["growth"], 3, "growth survives a reload")
	var Props = load("res://scripts/art/props.gd")
	var seedling: Node3D = Props.build("garden_bed", 3, 1, 0)
	var bloom: Node3D = Props.build("garden_bed", 3, 1, 3)
	ok(_model_bounds(bloom).size.y > _model_bounds(seedling).size.y + 0.25, "the bloom is visibly taller than the seeds")
	seedling.free()
	bloom.free()


func test_hearts_and_visits() -> void:
	var m = TownModel.new()
	var h := _house(m)
	ok(m.toggle_heart(h["attic"], "p1", "Sky"), "leave a heart in the attic")
	ok(not m.toggle_heart(h["attic"], "p1", "Sky"), "tap again to take it back")
	m.toggle_heart(h["attic"], "p1", "Sky")
	m.toggle_heart(h["attic"], "p2", "Leaf")
	eq(m.hearts[h["attic"]].size(), 2, "one heart per player per room")
	ok(not m.toggle_heart("town", "p1", "Sky"), "hearts are for rooms")
	ok(m.note_visit(h["id"], "p2", "Leaf") and not m.note_visit(h["id"], "p2", "Leaf"), "the guest book lists each visitor once")
	m.remove(h["id"])
	ok(not m.hearts.has(h["attic"]) and not m.visits.has(h["id"]), "putting a house away clears its hearts and guest book")


func test_photo_idea_rules() -> void:
	eq(PhotoIdeas.IDEAS.size(), 8, "eight photo ideas")
	eq(PhotoIdeas.evaluate({}), [], "an empty photo matches nothing")
	var all := PhotoIdeas.evaluate({"space": "town", "evening": true, "weather": "snow", "kids": 2, "animals": ["pig", "dog", "sheep"],
		"kinds": ["pond"], "shared_seat": true, "swinging": true, "tabletop": true, "lanterns": 2, "room_items": 0})
	for idea in ["friends_bench", "animal_pond", "pot_on_table", "lantern_evening", "swing_ride", "three_animals", "weather_friend"]:
		ok(all.has(idea), "%s recognized" % idea)
	ok(not all.has("cozy_room"), "a cozy room needs to be indoors")
	eq(PhotoIdeas.evaluate({"space": "i1:0:0", "room_items": 6}), ["cozy_room"], "six things in a room is cozy")
	eq(PhotoIdeas.evaluate({"animals": ["pig", "pig", "dog"]}), [], "three animals means three different friends")
	eq(PhotoIdeas.evaluate({"evening": true, "lanterns": 0}), [], "no lanterns lit, no lantern photo")


func test_activity_data_saves() -> void:
	var m = TownModel.make_default()
	m.roster["p1"] = {"nick": "Sky", "color": 4, "seen": 1}
	m.wishes = {"active": {"animal": "pig", "id": "pig_picnic"}, "stickers": [{"animal": "dog", "id": "dog_tea", "by": ["Sky"], "t": 2}]}
	m.weather = "snow"
	m.photo_ideas["swing_ride"] = {"by": ["Sky"], "t": 3}
	var m2 = TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "activity data loads")
	eq([m2.roster, m2.wishes, m2.weather, m2.photo_ideas], [m.roster, m.wishes, m.weather, m.photo_ideas], "roster, wishes, weather and photo ideas survive")
	var legacy: Dictionary = m.to_dict()
	for k in ["roster", "wishes", "weather", "hearts", "visits", "photo_ideas"]:
		legacy.erase(k)
	var m3 = TownModel.new()
	ok(m3.from_dict(legacy) and m3.weather == "sunny" and m3.wishes["stickers"].is_empty(), "revision-2 saves without activity data load with defaults")
	var junk: Dictionary = m.to_dict()
	junk["weather"] = "lava"
	junk["wishes"] = "nope"
	junk["hearts"] = {"x": 5}
	var m4 = TownModel.new()
	ok(m4.from_dict(junk) and m4.weather == "sunny" and m4.hearts.is_empty(), "damaged activity data falls back safely")


func test_hide_and_seek_warmth() -> void:
	var secret := {"space": "i9:2:0", "x": 1.0, "z": 1.0}
	eq(HideSeek.warmth_level({"space": "i9:2:0", "x": 1.5, "z": 1.0}, secret), 4, "right next to it")
	eq(HideSeek.warmth_level({"space": "i9:2:0", "x": 4.0, "z": 1.0}, secret), 3, "same room")
	eq(HideSeek.warmth_level({"space": "i9:0:0", "x": 1.0, "z": 1.0}, secret), 1, "another room of the same house is a little warm")
	eq(HideSeek.warmth_level({"space": "town", "x": 1.0, "z": 1.0}, secret), 1, "outdoors while it is in a house")
	eq(HideSeek.warmth_level({"space": "i7:0:0", "x": 1.0, "z": 1.0}, secret), 0, "a different house is cold")
	var town := {"space": "town", "x": 0.0, "z": 0.0}
	eq(HideSeek.warmth_level({"space": "town", "x": 20.0, "z": 0.0}, town), 0, "far across town is cold")


## The real autoloads in solo play: every activity starts, plays and ends.
func test_activities_session() -> void:
	var Act: Node = root.get_node("Activities")
	var path := "user://test_activities_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	ok(Session.device_player_id().length() == 32 and Session.my_pid == Session.device_player_id(), "this device has a stable player id")
	ok(Session.model.roster.has(Session.my_pid), "the town remembers the player id in its roster")
	# A: a wish, fulfilled by an edit.
	Session.model.wishes["active"] = {"animal": "pig", "id": "pig_picnic"}
	var done := []
	var cb := func(animal, id, _at, by): done.append([animal, id, by])
	Act.wish_done.connect(cb)
	await _result(Session.place("pond", "town", Vector2(-14, 15), 0, -2))
	await _result(Session.place("blanket", "town", Vector2(-14, 18.2), 0, 3))
	await process_frame
	Act.wish_done.disconnect(cb)
	eq(done.size(), 1, "the wish came true once")
	eq(Session.model.wishes["stickers"].size(), 1, "a sticker is in the scrapbook")
	ok(Session.model.wishes["active"].is_empty(), "no wish is waiting now")
	# B: hide-and-seek alone: an animal hides the acorn; a second start does not restart it.
	var msgs := []
	var mcb := func(t): msgs.append(t)
	Act.message.connect(mcb)
	Act.start_hide_and_seek()
	await process_frame
	eq(Act.hs.get("phase"), "seeking", "alone, an animal hides the acorn and you seek")
	eq(Act.hs.get("hider"), 0, "the hider is an animal")
	ok(not Act.hs.has("acorn"), "the hidden spot is not shared before the hint")
	var started: float = Act.hs.get("started", 0.0)
	Act.start_hide_and_seek()
	await process_frame
	ok(msgs.size() == 1 and Act.hs.get("started") == started, "a second start joins the running game")
	Act.stop_hide_and_seek()
	await process_frame
	eq(Act.hs.get("phase"), "none", "Stop ends it")
	# E: party, joining a running party, stopping.
	Act.start_party()
	await process_frame
	var brain = root.get_node("Animals").brain
	ok(Act.is_party() and brain != null and brain.parade_until > brain.time, "the dance parade starts")
	Act.start_party()
	await process_frame
	ok(msgs.size() == 2, "starting again joins in")
	Act.stop_party()
	await process_frame
	ok(not Act.is_party(), "Stop ends the party")
	Act.message.disconnect(mcb)
	# H: weather cycles and is saved.
	await _result(Session.change_weather())
	eq(Session.model.weather, "rain", "the vane turns to rain")
	# D: watering a garden bed.
	var bed: Dictionary = await _result(Session.place("garden_bed", "town", Vector2(-10, 15), 0, 6))
	var w: Dictionary = await _result(Session.water(bed["item"]["id"]))
	ok(w.get("ok", false) and Session.model.items[bed["item"]["id"]]["growth"] == 1, "watering grows the bed")
	# C: a present for anyone, opened by this player.
	var gift: Dictionary = await _result(Session.wrap(bed["item"]["id"], "", 2))
	ok(gift.get("ok", false), "wrap the garden bed as a present")
	eq((await _result(Session.sit(bed["item"]["id"]))).get("error", ""), "Open the present first!", "presents cannot be sat on")
	var opened := []
	Session.gift_opened.connect(func(id, from, _p): opened.append(from))
	await _result(Session.unwrap(bed["item"]["id"]))
	await process_frame
	eq(opened.size(), 1, "opening the present is announced")
	# F: a heart and a visit.
	var h: String = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]["id"]
	var attic := TownModel.room_space(h, 2, 0)
	Session.send_state({"space": attic, "x": 0.0, "z": 0.0, "ry": 0.0, "anim": "idle"})
	await _result(Session.toggle_heart(attic))
	ok(Session.model.hearts.get(attic, {}).has(Session.my_pid), "a heart in the attic")
	ok(Session.model.visits.get(h, {}).has(Session.my_pid), "the guest book noted the visit")
	# G: photo ideas are recorded once.
	var p1: Dictionary = await _result(Session.report_photo(["swing_ride", "nonsense"]))
	eq(p1.get("new"), ["swing_ride"], "a new photo idea is recorded; unknown ids are ignored")
	eq((await _result(Session.report_photo(["swing_ride"]))).get("new"), [], "the same idea is only celebrated once")
	Session.save_now()
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	ok(Session.model.weather == "rain" and Session.model.wishes["stickers"].size() == 1 and Session.model.photo_ideas.has("swing_ride") and Session.model.hearts.has(attic), "all activity progress survives a reload")
	Session.leave()



func test_landmark_tag_layout() -> void:
	var TagLayout = load("res://scripts/ui/tag_layout.gd")
	var area := Rect2(0, 0, 1366, 1024)
	var top := Rect2(0, 0, 1366, 104)
	var bottom := Rect2(0, 908, 1366, 116)
	var size := Vector2(220, 56)
	# Five landmarks bunched together, as on the plaza from far away.
	var cands := []
	for i in 5:
		cands.append({"id": "l%d" % i, "screen": Vector2(600 + i * 40, 300 + (i % 2) * 10), "size": size})
	var placed: Array = TagLayout.place(cands, area, [top, bottom])
	ok(placed.size() >= 2 and placed.size() <= 3, "two or three tags show, never all five (%d)" % placed.size())
	for i in placed.size():
		ok(area.encloses(placed[i]["rect"]) and not placed[i]["rect"].intersects(top) and not placed[i]["rect"].intersects(bottom), "tag %d is inside the safe area and clear of the bars" % i)
		for j in range(i + 1, placed.size()):
			ok(not placed[i]["rect"].intersects(placed[j]["rect"]), "tags %d and %d do not overlap" % [i, j])
	eq(placed[0]["id"], "l0", "the nearest landmark is named first")
	var high: Array = TagLayout.place([{"id": "x", "screen": Vector2(600, 90), "size": size}], area, [top, bottom])
	ok(high.is_empty() or not high[0]["rect"].intersects(top), "a tag never hides under the top bar")
	# Landmarks right under the top bar get their tags below their feet instead of vanishing.
	var under := []
	for i in 4:
		under.append({"id": "u%d" % i, "screen": Vector2(450 + i * 150, 120), "foot": Vector2(450 + i * 150, 230), "size": size})
	var below: Array = TagLayout.place(under, area, [top, bottom])
	eq(below.size(), 3, "three tags fit below landmarks that stand under the top bar")
	for i in below.size():
		ok(not below[i]["rect"].intersects(top), "tag below the foot clears the top bar")
		for j in range(i + 1, below.size()):
			ok(not below[i]["rect"].intersects(below[j]["rect"]), "tags below feet do not overlap")
	var edge: Array = TagLayout.place([{"id": "e", "screen": Vector2(1360, 500), "size": size}], area, [top, bottom])
	ok(edge.size() == 1 and edge[0]["rect"].end.x <= area.end.x - 8.0, "a tag near the screen edge is pulled inside")



func test_item_query() -> void:
	var Q = load("res://scripts/ui/item_query.gd")
	var ident := func(t): return t
	var home := func(k): return Catalog.allowed_in(k, "living")
	var town := func(k): return Catalog.allowed_in(k, "town")
	eq(Q.normalize("  Caf\u00e9   TABLE "), "cafe table", "search folds case, accents and spaces")
	eq(Q.normalize("\uff21\uff22\uff23"), "abc", "full-width letters are plain letters")
	# Tabs match the catalog: All is every indoor item, a category is exactly kinds_for.
	var all_home: Array = Catalog.ITEMS.keys().filter(func(k): return Catalog.allowed_in(k, "living"))
	eq(Q.query(Catalog.ITEMS, home, "All", "", "", ident).size(), all_home.size(), "All lists every indoor item")
	for cat in Catalog.HOME_CATEGORIES:
		var got: Array = Q.query(Catalog.ITEMS, home, cat, "", "", ident)
		var want: Array = Catalog.kinds_for(cat, "living")
		got.sort()
		want.sort()
		eq(got, want, "tab %s shows exactly its category" % cat)
	var town_all: Array = Q.query(Catalog.ITEMS, town, "All", "", "", ident)
	ok(town_all.all(func(k): return Catalog.allowed_in(k, "town")), "town results are all allowed outdoors")
	# Search: across tabs, ranked, case-insensitive.
	var clock: Array = Q.query(Catalog.ITEMS, home, "Furniture", "", "wall clock", ident)
	eq(clock[0] if not clock.is_empty() else "", "wall_clock", "an exact name comes first, from any tab")
	ok(Q.query(Catalog.ITEMS, home, "Furniture", "", "CLOCK", ident).has("wall_clock"), "search ignores case")
	ok(Q.query(Catalog.ITEMS, home, "All", "", "zzqx", ident).is_empty(), "nonsense finds nothing")
	ok(Q.query(Catalog.ITEMS, town, "All", "", "clock", ident).is_empty(), "indoor items never show outdoors, even by search")
	# Localized names: the shown language first, English as a fallback.
	var fr := func(t): return {"Wall clock": "Horloge murale", "Teddy bear": "Ours en peluche"}.get(t, t)
	ok(Q.query(Catalog.ITEMS, home, "All", "", "horloge", fr).has("wall_clock"), "search finds the localized name")
	var zh := func(t): return "\u6302\u949f" if t == "Wall clock" else t
	ok(Q.query(Catalog.ITEMS, home, "All", "", "\u949f", zh).has("wall_clock"), "Chinese substring search works")
	var items := {
		"a": {"name": "Caf\u00e9 table", "category": "Furniture", "anchor": "ground", "size_class": "large", "seats": 0},
		"b": {"name": "Table lamp", "category": "Furniture", "anchor": "ground", "size_class": "small", "tabletop_eligible": true},
		"c": {"name": "Big round table", "category": "Furniture", "anchor": "ground", "size_class": "large", "support_surface": {"usable_size_xz": Vector2.ONE}},
		"d": {"name": "Notable clock", "category": "Cozy things", "anchor": "wall", "size_class": "small"},
		"e": {"name": "Table", "category": "Furniture", "anchor": "ground", "size_class": "large"},
	}
	var any := func(_k): return true
	eq(Q.query(items, any, "All", "", "table", ident), ["e", "b", "c", "a", "d"], "rank: whole name, start, word start, then anywhere (alphabetical within)")
	eq(Q.query(items, any, "All", "", "CAFE", ident), ["a"], "accents and case do not matter")
	# Placement filters derived from metadata.
	eq(Q.query(items, any, "All", "wall", "", ident), ["d"], "On the wall shows only wall items")
	eq(Q.query(items, any, "All", "small", "", ident), ["b"], "Small things shows the table-top lamp")
	eq(Q.query(items, any, "All", "tables", "", ident), ["c"], "Tables shows items with a surface")
	var chips: Array = Q.placement_chips(items, items.keys())
	ok(chips.any(func(c): return c["id"] == "wall" and c["count"] == 1), "the wall filter is offered with its count")
	ok(not chips.any(func(c): return c["id"] == "ceiling"), "an empty filter is not offered")
	eq(Q.placement_chips(items, ["d"]), [], "no filters when they would not split the results")
	for kind in Q.query(Catalog.ITEMS, home, "Cozy things", "wall", "", ident):
		if Catalog.anchor(kind) != "wall":
			ok(false, "%s in the wall filter" % kind)
	ok(Q.placement_chips(Catalog.ITEMS, Catalog.kinds_for("Cozy things", "living")).any(func(c): return c["id"] == "wall"), "real Cozy things offer On the wall")
	# Recent: newest first, no duplicates, capped, unknown kinds dropped.
	var r: Array = []
	for k in ["chair", "table", "chair", "plant"]:
		r = Q.remember(r, k)
	eq(r, ["plant", "chair", "table"], "recent: newest first without duplicates")
	for i in 15:
		r = Q.remember(r, "k%d" % i)
	eq(r.size(), Q.RECENT_MAX, "recent is capped")
	eq(Q.query(Catalog.ITEMS, home, "Recent", "", "", ident, ["teddy", "no_such_kind", "tree", "chair"]), ["teddy", "chair"], "Recent keeps its order and skips unknown or outdoor kinds")


func test_item_query_large_fixture() -> void:
	var Q = load("res://scripts/ui/item_query.gd")
	var fixture: Dictionary = load("res://tests/fixtures/large_catalog.gd").build(2000)
	eq(fixture.size(), 2000, "fixture (test only) has 2000 generated entries")
	ok(not fixture.keys().any(func(k): return Catalog.has(k)), "fixture entries never enter the game catalog")
	eq(load("res://tests/fixtures/large_catalog.gd").build(2000).keys(), fixture.keys(), "fixture is deterministic")
	var ident := func(t): return t
	var any := func(_k): return true
	# Best of three passes per query, so a busy machine does not fail the check.
	var total := 0.0
	var runs := 0
	var sizes := []
	for q in ["", "lamp", "cafe", "tall clock", "0042", "zzqx", "cozy", "s"]:
		for placement in ["", "wall", "seats"]:
			var best := INF
			var n := 0
			for rep in 3:
				var t0 := Time.get_ticks_usec()
				n = Q.query(fixture, any, "All", placement, q, ident).size()
				best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
			sizes.append(n)
			total += best
			runs += 1
	var ms := total / runs
	print("item query, 2000-entry fixture: %.2f ms per query (best of 3, %d queries)" % [ms, runs])
	ok(ms < 30.0, "a query over 2000 entries stays under 30 ms here (%.2f ms; headless EC2)" % ms)
	eq(sizes[0], 2000, "no filter shows the whole fixture")
	ok(sizes[3] == 100, "\"lamp\" finds every lamp (100) (got %d)" % sizes[3])
	ok(sizes[6] > 0, "\"cafe\" finds the Caf\u00e9 signs")
	eq(sizes[15], 0, "nonsense finds nothing in a big catalog")


func test_tap_choices() -> void:
	var Q = load("res://scripts/ui/item_query.gd")
	eq(Q.tap_choices([]), [], "no hit, no choice")
	eq(Q.tap_choices([{"id": "a", "score": 0.6}]), ["a"], "a single hit is picked")
	eq(Q.tap_choices([{"id": "a", "score": 0.2}, {"id": "b", "score": 0.25}]), ["a"], "a dead-center hit is picked")
	eq(Q.tap_choices([{"id": "a", "score": 0.7}, {"id": "b", "score": 0.4}]), ["b", "a"], "two close calls are offered, closest first")
	eq(Q.tap_choices([{"id": "a", "score": 0.35}, {"id": "b", "score": 0.95}]), ["a"], "a clearly closer item is picked")
	var many := []
	for i in 6:
		many.append({"id": "i%d" % i, "score": 0.5 + i * 0.05})
	eq(Q.tap_choices(many).size(), 4, "at most four are offered")



func test_deployment_config() -> void:
	var D = load("res://scripts/net/deployment.gd")
	var good: Dictionary = D.parse('{"schema": 1, "multiplayer_url": "wss://town.example.org/lantern", "invite_code": "abc-123"}')
	ok(good["ok"] and good["url"] == "wss://town.example.org/lantern" and good["invite"] == "abc-123", "a valid private config is read")
	ok(D.parse('{"schema": 1, "multiplayer_url": "wss://town.example.org:8443"}')["ok"], "the invite is optional; a port is fine")
	for bad in ["", "not json", "[]", '{"multiplayer_url": "wss://a.example.org"}', '{"schema": 2, "multiplayer_url": "wss://a.example.org"}',
			'{"schema": "1", "multiplayer_url": "wss://a.example.org"}', '{"schema": 1.5, "multiplayer_url": "wss://a.example.org"}',
			'{"schema": 1}', '{"schema": 1, "multiplayer_url": "https://a.example.org"}', '{"schema": 1, "multiplayer_url": "ws://a.example.org"}',
			'{"schema": 1, "multiplayer_url": "wss://user:pw@a.example.org"}', '{"schema": 1, "multiplayer_url": "wss://a.example.org:99999"}',
			'{"schema": 1, "multiplayer_url": "wss://"}', '{"schema": 1, "multiplayer_url": " wss://a.example.org"}',
			'{"schema": 1, "multiplayer_url": "wss://a.example.org", "invite_code": "has space"}',
			'{"schema": 1, "multiplayer_url": "wss://a.example.org", "invite_code": 42}']:
		var r: Dictionary = D.parse(bad)
		ok(not r["ok"] and r["reason"] != "" and not r["reason"].contains("example"), "malformed config is refused without echoing values: %s" % bad.left(40))
	ok(D.parse('{"schema": 1, "multiplayer_url": "ws://127.0.0.1:9080"}')["ok"], "ws:// is allowed for loopback testing")
	ok(D.parse('{"schema": 1, "multiplayer_url": "ws://[::1]:9080"}')["ok"], "ws:// to IPv6 loopback is allowed")
	ok(D.valid_url("ws://192.168.1.5:9080") and not D.valid_url("ws://192.168.1.5:9080", true), "a LAN ws:// address works by hand but not in packaged config")
	ok(not D.valid_invite("") and not D.valid_invite("a b") and not D.valid_invite("\u00e9t\u00e9") and D.valid_invite("Ab-9_~!") and not D.valid_invite("x".repeat(257)), "invite characters and length")
	# A missing packaged file is normal; a broken one is ignored.
	eq(D.load_config("res://private/no_such_file.json"), {}, "no private config: nothing is prefilled")
	var broken := "user://deploy_broken.json"
	var f := FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	eq(D.load_config(broken), {}, "a malformed private config is ignored (manual entry stays)")
	# Address precedence (docs/deployment.md section 2).
	var cfg := {"url": "wss://town.example.org", "invite": "k1"}
	eq(D.shown_address(cfg, {}), "wss://town.example.org", "the packaged address is prefilled")
	eq(D.shown_address(cfg, {"server": "ws://10.0.0.9:9080"}), "wss://town.example.org", "an old saved test server does not override the packaged default")
	eq(D.shown_address(cfg, {"override": "ws://10.0.0.9:9080", "override_base": "wss://old.example.org"}), "wss://town.example.org", "an edit made against an older default is dropped")
	eq(D.shown_address(cfg, {"override": "ws://10.0.0.9:9080", "override_base": "wss://town.example.org"}), "ws://10.0.0.9:9080", "a deliberate edit against this default is kept")
	eq(D.shown_address({}, {"server": "ws://10.0.0.9:9080"}), "ws://10.0.0.9:9080", "public build: the last address used")
	eq(D.shown_address({}, {}), "ws://127.0.0.1:9080", "public build without history: the local default")
	var st: Dictionary = D.remember_address(cfg, {}, "ws://10.0.0.9:9080")
	eq([st["override"], st["override_base"]], ["ws://10.0.0.9:9080", "wss://town.example.org"], "joining elsewhere records an edit tied to this default")
	st = D.remember_address(cfg, st, "wss://town.example.org")
	eq(st["override"], "", "joining the packaged address again clears the edit")
	eq(D.remember_address({}, {}, "ws://10.0.0.9:9080")["server"], "ws://10.0.0.9:9080", "public build remembers the address")
	eq(D.invite_for(cfg, "wss://town.example.org", "typed"), "k1", "the packaged invite goes with the packaged address")
	eq(D.invite_for(cfg, "ws://10.0.0.9:9080", " typed "), "typed", "another address uses the typed invite")
	eq(D.invite_for({"url": "wss://town.example.org", "invite": ""}, "wss://town.example.org", "typed"), "typed", "no packaged invite: the typed one is used")
	# Constant-time comparison works on digests.
	ok(D.same_invite("secret-1", "secret-1") and not D.same_invite("secret-1", "secret-2") and not D.same_invite("", "secret-1") and not D.same_invite("secret-1", "secret-1 "), "invite comparison")
	# Server invite file.
	var path := ProjectSettings.globalize_path("user://invite_test")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("  door-42  \nsecond line ignored\n")
	f.close()
	FileAccess.set_unix_permissions(path, 0x180)   # 600
	var r: Dictionary = D.read_invite_file(path)
	ok(r["ok"] and r["invite"] == "door-42" and not r["loose"], "invite file: first line, trimmed; 600 is not loose")
	FileAccess.set_unix_permissions(path, 0x1A4)   # 644
	ok(D.read_invite_file(path)["loose"], "a world-readable invite file is flagged")
	ok(not D.read_invite_file(path + "_missing")["ok"], "a missing invite file is an error")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n")
	f.close()
	ok(not D.read_invite_file(path)["ok"], "an empty invite file is an error")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(broken)
	ok(Session.PROTOCOL == 9, "protocol 9 (invite handshake, play ideas, r12 wardrobe)")


func test_activity_guide() -> void:
	var G = load("res://scripts/ui/activity_guide.gd")
	var Art = load("res://scripts/ui/guide_art.gd")
	eq(G.ENTRIES.map(func(e): return e["id"]), ["wishes", "acorn", "gifts", "garden", "party", "visits", "photos", "weather"], "the guide covers A-H in order")
	var arts := {}
	for e in G.ENTRIES:
		for f in ["title", "tagline", "where", "steps", "success", "alone", "friends", "go", "go_label", "art"]:
			ok(e.has(f), "%s has %s" % [e["id"], f])
		ok(e["steps"].size() >= 2, "%s has at least two steps" % e["id"])
		arts[Art.SCENES.get(e["art"], "")] = true
		var tex: Texture2D = Art.texture(e["art"])
		ok(tex != null and tex.get_width() == 320 and tex.get_height() == 220, "%s illustration renders (320x220)" % e["id"])
		var go: String = e["go"]
		ok(go in ["wish", "decorate", "garden", "door"] or (go.begins_with("landmark:") and go.trim_prefix("landmark:") in ["stump", "drum", "board", "vane"]), "%s has a safe next step (%s)" % [e["id"], go])
	eq(arts.size(), 8, "eight different illustrations")
	# Every key and every label it names exist in all six languages, and labels are real on-screen labels.
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/en.json"))
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing: Array = G.keys().filter(func(k): return not cat.has(k))
		eq(missing, [], "%s has every guide string" % code)
	for e in G.ENTRIES:
		for l in [e["where"], e["friends"], e.get("extra", "")] + e["steps"]:
			if l is Array:
				eq(l[0].count("%s"), l[1].size(), "placeholders match labels: %s" % l[0].left(30))
				for lab in l[1]:
					ok(en.has(lab), "guide label \"%s\" is a real UI string" % lab)
	var ident := func(t): return t
	eq(G.line(["Tap %s and choose %s or a friend.", ["Gift", "For anyone"]], ident), "Tap Gift and choose For anyone or a friend.", "labels are filled in")
	# The guide text never mentions hidden-game state.
	ok(not FileAccess.get_file_as_string("res://scripts/ui/activity_guide.gd").contains("_secret") and not FileAccess.get_file_as_string("res://scripts/ui/activity_guide.gd").contains("near_acorn"), "the guide reads no hidden acorn state")


## PT-AH-001: feedback is reserved space for name tags.
func test_feedback_keeps_clear_of_tags() -> void:
	var TagLayout = load("res://scripts/ui/tag_layout.gd")
	var area := Rect2(0, 0, 1366, 1024)
	var top := Rect2(0, 0, 1366, 104)
	var toast := Rect2(560, 196, 300, 64).grow(8.0)   # the photo-saved message
	var size := Vector2(150, 56)
	# Landmarks whose tags would sit right on the message (the recorded pose).
	var cands := [{"id": "bell", "screen": Vector2(745, 262), "foot": Vector2(745, 330), "size": size},
		{"id": "drum", "screen": Vector2(860, 270), "foot": Vector2(860, 330), "size": size},
		{"id": "vane", "screen": Vector2(520, 255), "foot": Vector2(520, 330), "size": size}]
	var free: Array = TagLayout.place(cands, area, [top])
	ok(free.any(func(p): return p["rect"].intersects(toast)), "without the reservation a tag lands on the message (reproduces PT-AH-001)")
	var placed: Array = TagLayout.place(cands, area, [top, toast])
	ok(placed.size() >= 2, "tags still show beside the message (%d)" % placed.size())
	for p in placed:
		ok(not p["rect"].intersects(toast), "tag %s keeps clear of the message" % p["id"])



func test_room_themes() -> void:
	var RT = load("res://scripts/core/room_themes.gd")
	var Q = load("res://scripts/ui/item_query.gd")
	eq(TownModel.ROOM_NAMES, [["Living room", "Kitchen"], ["Bedroom", "Game room"], ["Pet room", "Art studio"]], "rooms: Kitchen, Game room and Pet room")
	# Every promised supply is a real, placeable catalog item in its theme tab.
	var promised := {
		"Kitchen": ["kitchen_counter", "kitchen_stove", "kitchen_sink", "kitchen_fridge", "kitchen_pot", "kitchen_pan_set", "kitchen_utensil_crock",
			"kitchen_plate_rack", "kitchen_rice_sack", "kitchen_egg_basket", "kitchen_veg_basket", "dish_rice_bowl", "dish_veg_soup", "dish_fried_egg",
			"dish_rice_meal", "table", "chair"],
		"Games": ["game_handheld_dock", "game_console_set", "game_controller", "game_tv_stand", "game_bean_bag", "game_storage_cubby", "table", "arcade_cabinet_red"],
		"Pets": ["petroom_bed_round", "petroom_dog_house", "petroom_food_bowl", "petroom_water_bowl", "petroom_cat_tree", "petroom_scratch_post",
			"petroom_toy_yarn", "petroom_toy_bone", "petroom_toy_mouse", "petroom_feather_wand", "petroom_bird_cage", "petroom_perch_stand", "petroom_butterfly_house"],
	}
	var home := func(k): return Catalog.allowed_in(k, "c1:0:1")
	for tab in promised:
		var shown: Array = Q.query(Catalog.ITEMS, home, tab, "", "", func(t): return t, [], RT.extra_for(tab))
		for k in promised[tab]:
			ok(Catalog.has(k) and shown.has(k), "%s tab offers %s" % [tab, k])
	ok(Q.query(Catalog.ITEMS, home, "All", "", "stove", func(t): return t).has("kitchen_stove"), "search finds the stove")
	ok(Q.query(Catalog.ITEMS, home, "All", "", "handheld", func(t): return t).has("game_handheld_dock"), "search finds the handheld game")
	eq([RT.tab_for_room("Kitchen"), RT.tab_for_room("Game room"), RT.tab_for_room("Pet room"), RT.tab_for_room("Bedroom")], ["Kitchen", "Games", "Pets", ""], "rooms open their own tab")
	ok(Catalog.support_surface("kitchen_counter").size() > 0 and Catalog.fits_on("kitchen_pot", "kitchen_counter"), "a pot fits on the kitchen counter")
	ok(Catalog.fits_on("kitchen_pot", "kitchen_stove"), "a pot fits on the stove top")
	ok(Catalog.fits_on("game_console_set", "table"), "the console fits on the table")
	# Starter sets: empty themed rooms are furnished once; furnished rooms are left alone.
	var m := TownModel.new()
	m.place("cottage", "town", 0.0, 6.0, 0)
	var house: String = m.items.values()[0]["id"]
	var bedroom := TownModel.room_space(house, 1, 0)
	var kitchen := TownModel.room_space(house, 0, 1)
	var game := TownModel.room_space(house, 1, 1)
	var petroom := TownModel.room_space(house, 2, 0)
	m.place("teddy", game, 0.0, 0.0, 0)
	m.place("table", kitchen, 0.5, 0.5, 0)
	eq([RT.setup_label(m, kitchen), RT.setup_label(m, petroom), RT.setup_label(m, game), RT.setup_label(m, bedroom), RT.setup_label(m, "town")],
		["Set up the kitchen", "Set up the pet room", "Set up the game room", "", ""], "themed rooms without their key item offer a one-tap set-up")
	var n: int = RT.furnish(m)
	ok(n >= 20, "starter sets placed (%d items)" % n)
	var kinds := func(space): return m.items_in(space).map(func(i): return i["kind"])
	for k in ["kitchen_stove", "kitchen_sink", "kitchen_fridge", "kitchen_counter", "kitchen_rice_sack", "kitchen_egg_basket", "kitchen_veg_basket", "kitchen_pot", "kitchen_pan_set", "table"]:
		ok(kinds.call(kitchen).has(k), "the kitchen starts with %s" % k)
	for k in ["petroom_bed_round", "petroom_dog_house", "petroom_food_bowl", "petroom_water_bowl", "petroom_cat_tree", "petroom_perch_stand", "petroom_butterfly_house"]:
		ok(kinds.call(petroom).has(k), "the pet room starts with %s" % k)
	ok(kinds.call(game).has("teddy") and kinds.call(game).has("game_tv_stand") and kinds.call(game).has("game_console_set"), "set-up adds what is missing and keeps what was there")
	ok(m.items_in(game).any(func(i): return i["kind"] == "game_console_set" and i.has("host")), "the console starts on the table")
	ok(m.items_in(kitchen).any(func(i): return i["kind"] == "kitchen_pan_set" and m.items.get(i.get("host", ""), {}).get("kind", "") == "kitchen_stove"), "the pan starts on the stove (turned to fit)")
	ok(m.items_in(kitchen).any(func(i): return i["kind"] == "kitchen_pot" and m.items.get(i.get("host", ""), {}).get("kind", "") == "kitchen_counter"), "the pot starts on the counter")
	var C = load("res://scripts/core/cooking.gd")
	for r in C.ORDER:
		eq(C.missing(m, kitchen, r), [], "after set-up the kitchen can cook %s" % r)
	eq(kinds.call(kitchen).filter(func(k): return k == "table").size(), 1, "a table that was already there is not doubled")
	eq(m.items_in(bedroom).size(), 0, "other rooms stay empty")
	for it in m.items_in(kitchen) + m.items_in(petroom):
		eq(m.check(it["kind"], it["space"], it["x"], it["z"], it["rot"], it["id"]) if not it.has("host") else "", "", "starter %s obeys the placement rules" % it["kind"])
	for it in m.items_in(kitchen).filter(func(i): return i["kind"] == "kitchen_stove"):
		m.remove(it["id"])
	eq(RT.furnish(m), 0, "starter sets are offered only once per room")
	var m2 := TownModel.new()
	m2.place("cottage", "town", 0.0, 6.0, 0)
	var k2 := TownModel.room_space(m2.items.values()[0]["id"], 0, 1)
	m2.place("kitchen_stove", k2, 0.0, -2.2, 0)
	eq(RT.setup_label(m2, k2), "", "a kitchen that has a stove is not offered a set-up")
	eq(RT.setup_label(m, kitchen), "", "a set-up room offers no second set-up")


func test_pet_rules() -> void:
	var P = load("res://scripts/core/pets.gd")
	eq(P.ORDER, ["cat", "dog", "bird", "butterfly"], "pet families: cat, dog, bird, butterfly")
	for f in P.FAMILIES:
		ok(not f in ["lizard", "gecko", "snake", "spider", "bug", "beetle"], "no creepy pets (%s)" % f)
	var m := TownModel.new()
	m.place("cottage", "town", 0.0, 6.0, 0)
	var house: String = m.items.values()[0]["id"]
	var a := "a".repeat(32)
	var r: Dictionary = P.adopt(m, a, "cat", 1, 2, house)
	ok(r["ok"] and r["pet"]["name"] == "Pumpkin" and P.entry(m, a)["active"] == r["pet"]["id"], "adopting a cat makes it the one that follows")
	ok(not P.adopt(m, a, "lizard", 0, 0, house)["ok"], "no lizards")
	ok(not P.adopt(m, a, "dog", 5, 0, house)["ok"] and not P.adopt(m, a, "dog", 0, 9, house)["ok"] and not P.adopt(m, a, "bird", 2, 0, house)["ok"], "unknown variants or names are refused")
	for f in ["dog", "bird", "butterfly"]:
		ok(P.adopt(m, a, f, 0, 0, house)["ok"], "adopt a %s" % f)
	ok(not P.adopt(m, a, "cat", 0, 0, house)["ok"], "four pets at most")
	eq(P.entry(m, a)["pets"].size(), 4, "four pets owned")
	var bird: String = P.entry(m, a)["pets"][2]["id"]
	ok(P.set_active(m, a, bird)["ok"] and P.entry(m, a)["active"] == bird, "choose which pet follows")
	ok(not P.set_active(m, a, "p99")["ok"], "cannot choose someone else's pet")
	eq(P.space_of(m, a, bird, "town"), "town", "a following pet is where its owner is")
	ok(P.set_mode(m, a, "home")["ok"], "send pets home")
	eq(P.space_of(m, a, bird, "town"), TownModel.room_space(house, 2, 0), "a resting pet is in its owner's Pet room")
	# Care: pat anywhere the pet is; feeding needs a food bowl in reach.
	var room := TownModel.room_space(house, 2, 0)
	ok(not P.care(m, a, bird, "pat", "town", Vector2.ZERO, "town")["ok"], "cannot pat a pet that is somewhere else")
	ok(P.care(m, a, bird, "pat", room, Vector2.ZERO, "town")["ok"], "pat a pet in its room")
	eq(P.care(m, a, bird, "feed", room, Vector2.ZERO, "town").get("error", ""), "Bring your pet to a food bowl, then feed it.", "feeding without a bowl explains what to do")
	m.place("petroom_food_bowl", room, 0.6, 0.0, 0)
	ok(P.care(m, a, bird, "feed", room, Vector2.ZERO, "town")["ok"], "feed at a food bowl")
	eq([P.find_pet(m, a, bird)["pats"], P.find_pet(m, a, bird)["meals"]], [1, 1], "care is counted")
	# Saved data is cleaned.
	var bad := {"x": {"pets": [{"id": "p1", "family": "gecko"}, {"id": "p2", "family": "dog", "color": 7, "name": "Rex<b>"}], "active": "p1", "mode": "fly"}}
	var clean: Dictionary = P.sanitize(bad)
	eq(clean["x"]["pets"].size(), 1, "unknown families are dropped from saves")
	eq([clean["x"]["pets"][0]["color"], clean["x"]["pets"][0]["name"], clean["x"]["active"], clean["x"]["mode"]], [2, "Noodle", "p2", "follow"], "bad colors, names, active pet and mode are repaired")
	var renamed: Dictionary = P.sanitize({"y": {"pets": [{"id": "p1", "family": "dog", "name": "Biscuit"}, {"id": "p2", "family": "bird", "name": "Pip"}], "active": "p1"}})
	eq(renamed["y"]["pets"].map(func(p): return p["name"]), ["Noodle", "Poppy"], "pets named after town animals (r7/r8) get their new names")
	for fam in P.ORDER:
		for n in P.FAMILIES[fam]["names"]:
			ok(not n in ["Pip", "Bramble", "Wooly", "Biscuit", "Tumble"], "pet name %s is not a town animal's name" % n)


func test_cooking_rules() -> void:
	var C = load("res://scripts/core/cooking.gd")
	var m := TownModel.new()
	m.place("cottage", "town", 0.0, 6.0, 0)
	var house: String = m.items.values()[0]["id"]
	var k := TownModel.room_space(house, 0, 1)
	var stove: Dictionary = m.place("kitchen_stove", k, 0.0, -2.0, 0)["item"]
	var at := Vector2(0.0, -1.0)
	eq(C.check(m, stove["id"], "rice", k, at, {}), "Some ingredients are missing in this room.", "no rice sack: no rice bowl")
	eq(C.missing(m, k, "stew"), ["kitchen_rice_sack", "kitchen_veg_basket", "kitchen_pot"], "the recipe card lists what is missing")
	m.place("kitchen_rice_sack", k, -2.0, -1.0, 0)
	eq(C.check(m, stove["id"], "rice", k, at, {}), "", "with a rice sack the rice bowl can be cooked")
	eq(C.check(m, stove["id"], "rice", k, Vector2(3.0, 2.0), {}), "Stand next to the stove to cook.", "must stand at the stove")
	eq(C.check(m, stove["id"], "rice", "town", at, {}), "Stand next to the stove to cook.", "must be in the kitchen")
	eq(C.check(m, stove["id"], "rice", k, at, {stove["id"]: "soup"}), "Someone is cooking on this stove. Try again in a moment.", "one dish at a time per stove")
	eq(C.check(m, stove["id"], "cake", k, at, {}), "That recipe is not in the book.", "unknown recipes are refused")
	eq(C.check(m, "i999", "rice", k, at, {}), "That stove is not here.", "unknown stoves are refused")
	var dish: Dictionary = C.serve(m, stove["id"], "rice")
	ok(dish.get("kind", "") == "dish_rice_bowl" and dish["space"] == k, "the rice bowl is served in the kitchen")
	ok(Vector2(dish["x"], dish["z"]).distance_to(Vector2(stove["x"], stove["z"])) < 2.0, "next to the stove")
	eq(C.check_eat(m, dish["id"], k, Vector2(dish["x"], dish["z"])), "", "it can be eaten up close")
	eq(C.check_eat(m, dish["id"], k, Vector2(3.5, 2.5)), "Walk to the dish to eat it.", "but not from across the room")
	eq(C.check_eat(m, stove["id"], k, at), "That dish is not here.", "a stove is not food")
	for r in C.ORDER:
		ok(Catalog.has(C.RECIPES[r]["dish"]) and C.RECIPES[r]["needs"].all(func(n): return Catalog.has(n)), "recipe %s uses real items" % r)


func test_pets_cooking_saves() -> void:
	var P = load("res://scripts/core/pets.gd")
	var RT = load("res://scripts/core/room_themes.gd")
	var m := TownModel.new()
	m.place("cottage", "town", 0.0, 6.0, 0)
	var house: String = m.items.values()[0]["id"]
	RT.furnish(m)
	P.adopt(m, "b".repeat(32), "dog", 2, 1, house)
	m.cooked["b".repeat(32)] = 3
	var m2 := TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "a town with pets, starters and cooking saves and loads")
	eq(m2.pets, m.pets, "pets survive a save")
	eq(m2.starter.keys().size(), m.starter.keys().size(), "starter rooms survive a save")
	eq(m2.cooked, m.cooked, "cooking counts survive a save")
	eq(RT.furnish(m2), 0, "a loaded town is not furnished twice")
	# An r6 save (no new keys) loads unchanged.
	var old := m.to_dict()
	for key in ["pets", "starter", "cooked"]:
		old.erase(key)
	var m3 := TownModel.new()
	ok(m3.from_dict(old) and m3.pets.is_empty() and m3.cooked.is_empty() and m3.items.size() == m.items.size(), "an older save loads with no pets and every item")
	# A town saved by r7 with the code-built kitchen kinds loads them as the modeled ones.
	var r7 := m.to_dict()
	var k := TownModel.room_space(house, 0, 1)
	for spec in [["cooking_pot", "kitchen_pot"], ["dish_omelette", "dish_rice_meal"], ["game_tablet", "game_handheld_dock"]]:
		r7["items"].append({"id": "i%d" % (900 + r7["items"].size()), "kind": spec[0], "space": k, "x": 3.2, "z": 2.2 - 0.6 * float(r7["items"].size() % 3), "rot": 0, "color": -1})
	var m4 := TownModel.new()
	ok(m4.from_dict(r7), "an r7 save loads")
	for spec in [["cooking_pot", "kitchen_pot"], ["dish_omelette", "dish_rice_meal"], ["game_tablet", "game_handheld_dock"]]:
		ok(m4.items.values().any(func(i): return i["kind"] == spec[1]) and not m4.items.values().any(func(i): return i["kind"] == spec[0]), "r7 %s became %s" % spec)



func test_pet_models() -> void:
	var P = load("res://scripts/core/pets.gd")
	var Pet = load("res://scripts/art/pet.gd")
	var want := {"cat": ["Head", "LegBL", "LegBR", "LegFL", "LegFR", "Tail"], "dog": ["Head", "LegBL", "LegBR", "LegFL", "LegFR", "Tail"],
		"bird": ["Head", "Tail", "WingL", "WingR"], "butterfly": ["WingL", "WingR"]}
	var n := 0
	for fam in P.ORDER:
		for v in P.FAMILIES[fam]["variants"].size():
			var pet = Pet.new()
			root.add_child(pet)
			pet.setup(fam, v, P.FAMILIES[fam]["names"][0])
			var j: Array = pet.joints()
			j.sort()
			ok(pet.model_loaded, "%s loads its modeled actor %s" % [fam, pet.model_id])
			eq(j, want[fam], "%s exposes its joint hooks" % pet.model_id)
			# Moving the joints is what the follow animation does; they must turn.
			pet.speed = 2.0
			pet._process(0.13)
			var turned: bool = j.any(func(h): return pet._joints[h].rotation.length() > 0.01)
			ok(turned, "%s joints animate" % pet.model_id)
			pet.free()
			n += 1
	eq(n, 10, "ten modeled pets: 3 cats, 3 dogs, 2 birds, 2 butterflies")



func test_photo_library() -> void:
	var lib = load("res://scripts/ui/photo_library.gd").new()
	root.add_child(lib)
	ok(not lib.available(), "off iOS there is no native Photos saver (desktop keeps local saving)")
	eq(lib.save("/tmp/none.png"), "local", "off iOS the answer is local, never a claimed Photos save")
	lib.free()
	var gdip := FileAccess.get_file_as_string("res://ios/plugins/photo_library/photo_library.gdip")
	ok(gdip.contains("NSPhotoLibraryAddUsageDescription") and not gdip.contains("NSPhotoLibraryUsageDescription"), "the plugin asks only for add-only access")
	ok(gdip.contains("Photos.framework"), "the plugin links the Photos framework")
	var mm := FileAccess.get_file_as_string("res://ios/plugins/photo_library/src/photo_library.mm")
	ok(mm.contains("PHAccessLevelAddOnly") and mm.contains("completionHandler") and mm.contains("UIApplicationOpenSettingsURLString"), "native code: add-only, completion-based, Settings path")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok(preset.contains("plugins/PhotoLibrary=true") and preset.contains('privacy/photolibrary_usage_description=""'), "the iOS export enables the plugin and requests no full library access")
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/en.json"))
	ok(en.has("Lantern Lane saves the photos you take to your photo library."), "the purpose string is in the locale catalogs")


# ------------------------------------------------------------- play ideas (design/playability-8-12.md)

func test_play_rules() -> void:
	var PR = load("res://scripts/core/play_rules.gd")
	var RT = load("res://scripts/core/room_themes.gd")
	var m := TownModel.new()
	var tray: Dictionary = m.place("snack_tray", "town", 6.0, -8.0, 0)["item"]
	ok(not tray.is_empty(), "a snack tray can be placed outdoors")
	var at := Vector2(6.0, -6.8)
	eq(PR.check_snack(m, tray["id"], "snack_cookie", "berry", "town", Vector2(0, 0)), "Stand next to the snack tray to make a snack.", "making a snack needs the tray close by")
	eq(PR.check_snack(m, tray["id"], "pizza", "berry", "town", at), "That snack is not on the card.", "only the card's snacks")
	eq(PR.check_snack(m, "nope", "snack_cookie", "berry", "town", at), "That snack tray is not here.", "a missing tray is refused")
	var made := {}
	for base in PR.BASES:
		for top in PR.TOPPING_ORDER:
			eq(PR.check_snack(m, tray["id"], base, top, "town", at), "", "%s with %s can be made" % [base, top])
			made = PR.make_snack(m, tray["id"], base, top)
			ok(made.get("kind") == base and made.get("color") == PR.TOPPINGS[top], "%s with %s is a real item in the topping color" % [base, top])
	eq(m.items.values().filter(func(i): return PR.is_snack(i["kind"])).size(), 9, "all nine snacks were placed next to the tray")
	var far := Vector2(made["x"], made["z"]) + Vector2(5, 0)
	eq(PR.check_share(m, made["id"], "town", far), "Walk to the snack to share it.", "sharing needs the snack close by")
	eq(PR.check_share(m, made["id"], "town", Vector2(made["x"], made["z"])), "", "a snack close by can be shared")
	eq(PR.check_share(m, tray["id"], "town", Vector2(tray["x"], tray["z"])), "That snack is not here.", "the tray itself is not a snack")
	for kind in ["snack_tray", "snack_cookie", "snack_juice", "snack_sandwich"]:
		ok(Catalog.allowed_in(kind, "town") and Catalog.ITEMS[kind]["tabletop_eligible"], "%s goes indoors, outdoors and on tables" % kind)
	# The snowman's face (F04): placed with face 0, changes in turn, saves, comes back on undo.
	var sm: Dictionary = m.place("snowman", "town", -6.0, -8.0, 0, 4)["item"]
	eq(sm.get("variant"), 0, "a new snowman has the first face")
	eq(m.next_variant(sm["id"])["item"]["variant"], 1, "Change face shows the next face")
	m.next_variant(sm["id"])
	eq(m.next_variant(sm["id"])["item"]["variant"], 0, "three faces, then the first again")
	m.next_variant(sm["id"])
	ok(not m.next_variant(tray["id"])["ok"], "only items with faces change face")
	var removed: Array = m.remove(sm["id"])["removed"]
	eq(m.restore(removed)["items"][0].get("variant"), 1, "undo brings the snowman back with its face")
	ok(not Catalog.allowed_in("snowman", "home:0:0") and Catalog.get_def("snowman")["color"] >= 0, "the snowman stays outdoors and its scarf can be painted")
	# On display (F10).
	var a := "a".repeat(32)
	var b := "b".repeat(32)
	ok(m.set_display("town", true, a, "Sunny"), "the town square can be put on display")
	eq(PR.display_error(m, "town", b), "This place is on display.", "a friend is asked before changing it")
	eq(PR.display_error(m, "town", a), "", "the one who put it on display can still change it")
	ok(not m.set_display("nowhere:0:0", true, a, "Sunny"), "only real places go on display")
	var m2 := TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "a town with snacks, a snowman and a display mark saves and loads")
	eq(m2.display_by("town").get("nick"), "Sunny", "the display mark survives a save")
	eq(m2.items[sm["id"]].get("variant"), 1, "the snowman's face survives a save")
	var old := m.to_dict()
	old.erase("display")
	var m3 := TownModel.new()
	ok(m3.from_dict(old) and m3.display.is_empty(), "an r8 save (no display key) loads with nothing on display")
	m.set_display("town", false, b, "Kai")
	eq(PR.display_error(m, "town", b), "", "anyone may take it off display (after the client asks)")
	# Puddles (F04) and toolkits (F09).
	eq(TownModel.puddle_at(TownModel.PUDDLES[1]), 1, "standing in a puddle is detected")
	eq(TownModel.puddle_at(TownModel.PUDDLES[1] + Vector2(0, 0.8)), -1, "next to a puddle is dry")
	for t in RT.TOOLKITS:
		ok(RT.extra_for(t).size() >= 8, "toolkit %s has enough things" % t)
		ok(RT.TOOLKIT_IDEAS.has(t), "toolkit %s has an idea line" % t)
		for k in RT.TOOLKIT_ITEMS[t]:
			ok(Catalog.has(k), "toolkit %s item %s exists" % [t, k])
	eq(RT.toolkits_for("town"), RT.TOOLKITS, "all four toolkits have outdoor things")
	var dm = TownModel.make_default()
	eq(RT.toolkits_for(TownModel.room_space(dm.items.values().filter(func(i): return i["kind"] == "cottage")[0]["id"], 0, 0)), RT.TOOLKITS, "and indoor things")


func test_fetch_brain() -> void:
	var m = TownModel.make_default()
	var brain = AnimalBrain.new(7)
	brain.spawn(m)
	var dog: Dictionary = brain.dog()
	var kid_pos: Vector2 = dog["pos"] + Vector2(1.5, 0)
	var kids := [{"id": 5, "pos": kid_pos, "emote": ""}]
	var land = brain.throw_ball(m, 5, kid_pos, kid_pos + Vector2(0, 20))
	ok(land != null and land.distance_to(kid_pos) <= AnimalBrain.THROW_MAX + 0.6, "a throw lands at most THROW_MAX away (%s)" % land)
	eq(dog["plan"], "chase", "Biscuit runs after the ball")
	var seen := {"run": false, "carry": false}
	var refused := [false]
	var dropped := []   # [dog pos, ball pos] when the ball is given back
	_simulate(brain, m, 14.0, kids, func(br):
		var d: Dictionary = br.dog()
		if d["action"] in seen:
			seen[d["action"]] = true
		if d["plan"] == "bring" and not refused[0]:
			refused[0] = br.throw_ball(m, 9, kid_pos, kid_pos + Vector2(3, 0)) == null
		if dropped.is_empty() and seen["carry"] and d["thrower"] == 0:
			dropped.append_array([d["pos"], d["ball"]]))
	ok(seen["run"] and seen["carry"], "Biscuit runs to the ball and carries it back (%s)" % seen)
	ok(refused[0], "while bringing it to one child, another child waits for a turn")
	ok(not dropped.is_empty() and dropped[0].distance_to(kid_pos) < 1.6, "the ball comes back to the thrower (%s)" % [dropped])
	ok(not dropped.is_empty() and dropped[1].distance_to(kid_pos) < 1.6, "the ball is dropped at the child's feet")
	# The thrower goes inside: the dog drops the ball where it is.
	brain.throw_ball(m, 5, kid_pos, kid_pos + Vector2(-5, 0))
	_simulate(brain, m, 3.0, kids)
	_simulate(brain, m, 0.5, [])
	ok(dog["plan"] != "bring" and dog["thrower"] == 0, "no thrower outdoors: the game ends")
	# Throws all over the default town (r10 fix): the dog runs in straight lines, so a
	# throw toward a bench or tree stops short or glances aside where the dog can run
	# to and back. Every throw that lands away from the child must come back.
	var total := 0
	var short := 0
	var lost := []
	for x in range(-24, 25, 3):
		for z in range(-20, 21, 3):
			var b2 = AnimalBrain.new(5)
			b2.spawn(m)
			var thrower: Vector2 = AnimalBrain.resolve(m, Vector2(x, z), 0.3)
			b2.dog()["pos"] = AnimalBrain.resolve(m, thrower - Vector2(1.2, 0), 0.4)
			var landed = b2.throw_ball(m, 5, thrower, thrower + Vector2(0, 5))
			if landed == null:
				continue
			total += 1
			if landed.distance_to(thrower) < 1.6:
				short += 1   # hemmed in on every side: the ball drops at the child's feet
				continue
			var carried := [false]
			for i in 250:
				b2.tick(m, [{"id": 5, "pos": thrower, "emote": ""}])
				carried[0] = carried[0] or b2.dog()["action"] == "carry"
				if b2.dog()["thrower"] == 0:
					break
			if not (carried[0] and b2.dog()["pos"].distance_to(thrower) < 2.5):
				lost.append(thrower)
	ok(total > 200 and lost.is_empty(), "every throw across the town comes back (%d throws, lost at %s)" % [total, lost])
	ok(short * 20 <= total, "only a few throws are blocked on every side (%d of %d)" % [short, total])
	var packed := AnimalBrain.unpack(brain.pack())
	ok(AnimalBrain.ACTIONS.find("carry") > AnimalBrain.ACTIONS.find("chat"), "the new action is appended (old indices unchanged)")
	eq(packed.size(), AnimalBrain.ORDER.size(), "states still pack")
	brain.start_parade(5.0)
	ok(brain.throw_ball(m, 5, kid_pos, kid_pos + Vector2(2, 0)) == null, "no fetch during the dance parade")


func test_play_session() -> void:
	var path := "user://test_play_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	var me: int = Session.my_id
	var place := func(p: Vector2): Session.players[me]["state"] = {"space": "town", "x": p.x, "z": p.y}
	var free := func(kind: String, near: Vector2) -> Vector2: return Session.model.find_free_spot(kind, "town", near)
	var r := await _result(Session.place("snack_tray", "town", free.call("snack_tray", Vector2(-10, -12)), 0, -2))
	ok(r.get("ok", false), "a snack tray is placed")
	var tray: String = r.get("item", {}).get("id", "")
	place.call(Vector2(Session.model.items[tray]["x"], Session.model.items[tray]["z"] + 1.0))
	r = await _result(Session.make_snack(tray, "snack_sandwich", "mint"))
	ok(r.get("ok", false), "a snack is made at the tray (%s)" % r.get("error", ""))
	var snack: Dictionary = Session.model.items.get(r.get("id", ""), {})
	eq(snack.get("color"), 5, "the mint topping colors the snack")
	place.call(Vector2(-30, -30))
	eq((await _result(Session.make_snack(tray, "snack_cookie", "berry"))).get("error"), "Stand next to the snack tray to make a snack.", "the authority checks the distance")
	place.call(Vector2(snack["x"], snack["z"]))
	var cheers := []
	var cb := func(peer, kind): cheers.append([peer, kind])
	Session.emote.connect(cb)
	r = await _result(Session.share_snack(snack["id"]))
	Session.emote.disconnect(cb)
	ok(r.get("ok", false) and not Session.model.items.has(snack["id"]), "sharing eats the snack")
	eq(cheers, [[me, "cheer"]], "everyone close by cheers (here: the sharer)")
	# The snowman's face.
	r = await _result(Session.place("snowman", "town", free.call("snowman", Vector2(-14, -12)), 0, -2))
	var sm: String = r.get("item", {}).get("id", "")
	r = await _result(Session.change_face(sm))
	eq(Session.model.items[sm].get("variant"), 1, "Change face goes through the authority")
	# On display: a friend's mark refuses edits until it is taken off.
	place.call(Vector2(-10, -11))
	r = await _result(Session.set_display("town", true))
	ok(r.get("on", false) and Session.model.display_by("town").get("pid") == Session.my_pid, "the town square goes on display")
	r = await _result(Session.place("bench", "town", free.call("bench", Vector2(-12, -16)), 0, -2))
	ok(r.get("ok", false), "the one who put it on display keeps decorating")
	Session.model.display["town"] = {"pid": "f".repeat(32), "nick": "Kai"}
	eq(Session.display_by_other("town").get("nick"), "Kai", "the client sees a friend's display mark")
	for res in [await _result(Session.place("bench", "town", free.call("bench", Vector2(-16, -16)), 0, -2)),
			await _result(Session.paint(sm, 2)), await _result(Session.remove(sm)), await _result(Session.change_face(sm))]:
		eq(res.get("error"), "This place is on display.", "edits on display are refused")
	r = await _result(Session.set_display("town", false))
	ok(r.get("ok", false) and not r.get("on", true), "anyone may take it off display")
	ok((await _result(Session.paint(sm, 2))).get("ok", false), "then it can be changed")
	# Fetch with Biscuit.
	var brain = root.get_node("Animals").brain
	var dog: Dictionary = brain.dog()
	place.call(dog["pos"] + Vector2(1.2, 0))
	r = await _result(Session.throw_ball(dog["pos"] + Vector2(1.2, 5)))
	ok(r.get("ok", false) and dog["plan"] == "chase", "a throw starts fetch (%s)" % r.get("error", ""))
	place.call(dog["pos"] + Vector2(30, 0))
	eq((await _result(Session.throw_ball(dog["pos"]))).get("error"), "Stand closer to Biscuit to play fetch.", "throwing needs Biscuit close by")
	Session.leave()


# ------------------------------------------------------------- play ideas batch 2

func test_dress_and_poses() -> void:
	eq(Avatar.sanitize({"hat": "crown"})["hat"], "crown", "a known hat is kept")
	eq(Avatar.sanitize({"hat": "jetpack"})["hat"], "", "an unknown hat becomes no hat")
	eq(Avatar.sanitize({"nick": "Sky"})["hat"], "", "an older avatar without a hat loads with none")
	for p in Avatar.POSES:
		ok(Avatar.is_emote(p) and Avatar.POSE_NAMES.has(p), "pose %s can be sent and has a name" % p)
	ok(not Avatar.is_emote("fly"), "unknown emotes are refused")
	var Kid = load("res://scripts/art/kid.gd")
	for h in Avatar.HATS:
		var kid = Kid.new()
		root.add_child(kid)
		var av: Dictionary = Avatar.PRESETS[2].duplicate()
		av["hat"] = h
		kid.setup(av, false)
		for path in ["Body", "Body/LegL", "Body/LegR", "Body/ArmL", "Body/ArmR", "Body/Head", "Body/Head/Hat"]:
			ok(kid.get_node_or_null(path) != null, "[%s] the rig has %s (docs/kid-rig.md)" % [h, path])
		var hat: Node3D = kid.get_node_or_null("Body/Head/Hat")
		var parts: Array = hat.find_children("*", "MeshInstance3D", true, false) if hat else []
		ok((h == "") == parts.is_empty(), "[%s] the hat is built under Body/Head/Hat" % h)
		var top := 0.0
		for mi in parts:
			var xf := Transform3D()
			var p: Node = mi
			while p != kid:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			top = maxf(top, (xf * mi.get_aabb()).end.y)
		if h != "":
			ok(top > H and top < H + 0.45, "[%s] the hat sits on the head (top %.2f)" % [h, top])
		for pose in Avatar.POSES:
			kid.play_emote(pose)
			kid._pose(0.1)
		ok(hat.position == Vector3.ZERO and hat.rotation == Vector3.ZERO, "[%s] poses never move the hat off the head" % h)
		av["hat"] = "crown"
		kid.setup(av, false)   # a dress-up change in town rebuilds the rig
		ok(kid.get_children().filter(func(c): return c.name == "Body").size() == 1 and kid.get_node_or_null("Body/Head/Hat") != null, "[%s] a rebuilt rig keeps its exact names" % h)
		kid.free()


func test_track_rules() -> void:
	var TR = load("res://scripts/core/track_rules.gd")
	var m := TownModel.new()
	var put := func(kind: String, x: float, z: float, rot: int) -> String:
		var r: Dictionary = m.place(kind, "town", x, z, rot)
		ok(r["ok"], "%s placed at %s (%s)" % [kind, Vector2(x, z), r.get("error", "")])
		return r.get("item", {}).get("id", "")
	var s: String = put.call("track_start", 2.3, 1.8, 1)
	eq([m.items[s]["x"], m.items[s]["z"], m.items[s]["rot"]], [2.0, 2.0, 2], "track pieces snap to whole meters and quarter turns")
	m.move(s, 2.0, 2.0, 0)
	var straight: String = put.call("track_straight", 2.0, 3.0, 0)
	put.call("track_curve", 2.0, 4.0, 0)
	var bell: String = put.call("track_bell", 3.0, 4.0, 2)
	var fin: String = put.call("track_finish", 4.0, 4.0, 0)
	var r: Dictionary = TR.route(m, s)
	eq(r["end"], "finish", "the ball rolls from the start to the finish")
	eq(r["cells"], [Vector2(2, 2), Vector2(2, 3), Vector2(2, 4), Vector2(3, 4), Vector2(4, 4)], "along every piece in order, round the curve")
	eq(r["bells"], [bell], "and rings the bell on the way")
	m.remove(fin)
	r = TR.route(m, s)
	ok(r["end"] == "gap" and r["at"] == Vector2(4, 4), "a missing piece: the ball waits there (%s)" % r["at"])
	m.move(straight, 2.0, 3.0, 2)
	r = TR.route(m, s)
	ok(r["end"] == "wrong_way" and r["at"] == Vector2(2, 3), "a piece turned the wrong way stops the ball and is shown")
	# A switch sends the ball ahead or to the side.
	m.remove(straight)
	var sw: String = put.call("track_switch", 2.0, 3.0, 0)
	put.call("track_finish", 3.0, 3.0, 0)
	eq(TR.route(m, s)["cells"].size(), 4, "switch ahead: on to the curve and the bell")
	m.next_variant(sw)
	r = TR.route(m, s)
	ok(r["end"] == "finish" and r["cells"][-1] == Vector2(3, 3), "switch flipped: the ball goes to the side")
	ok(TR.route(m, sw)["cells"].is_empty(), "only a start piece rolls a ball")
	# A closed loop brings the ball home to its start.
	var m2 := TownModel.new()
	var start2: String = m2.place("track_start", "town", 0.0, 0.0, 0)["item"]["id"]
	for spec in [["track_curve", 0, 1, 0], ["track_curve", 1, 1, 2], ["track_straight", 1, 0, 0], ["track_curve", 1, -1, 4], ["track_curve", 0, -1, 6]]:
		ok(m2.place(spec[0], "town", spec[1], spec[2], spec[3])["ok"], "loop piece %s" % [spec])
	var r2: Dictionary = TR.route(m2, start2)
	ok(r2["end"] == "loop" and r2["cells"].size() == 7 and r2["cells"][-1] == Vector2.ZERO, "a loop brings the ball home (%s, %d cells)" % [r2["end"], r2["cells"].size()])
	var saved := TownModel.new()
	ok(saved.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))) and saved.items[sw]["variant"] == 1, "tracks and the switch way save and load")
	ok(not Catalog.allowed_in("track_start", "home:0:0"), "tracks are an outdoor toy")


func test_trail_rules() -> void:
	var PR = load("res://scripts/core/play_rules.gd")
	var m := TownModel.new()
	var ids := []
	for i in 5:
		var r: Dictionary = m.place("trail_sign", "town", -8.0 + i * 3.0, -10.0, 0, 3)
		ok(r["ok"] and r["item"]["num"] == i + 1, "sign %d is numbered in order" % (i + 1))
		ids.append(r["item"]["id"])
	eq(m.place("trail_sign", "town", 8.0, -14.0, 0)["error"], TownModel.ERR_TRAIL_FULL, "a trail has five signs at most")
	var gone: Array = m.remove(ids[1])["removed"]
	eq(m.place("trail_sign", "town", 8.0, -14.0, 0)["item"]["num"], 2, "a new sign fills the free number")
	m.remove(m.trail_signs()[1]["id"])
	eq(m.restore(gone)["items"][0]["num"], 2, "undo brings a sign back with its number")
	eq(m.trail_signs().map(func(s): return s["num"]), [1, 2, 3, 4, 5], "signs are walked in number order")
	eq(PR.check_follow(m, "home:0:0"), "Trails are outdoors.", "trails are outdoors")
	eq(PR.check_follow(m, "town"), "", "a trail of five can be followed")
	var first: Dictionary = m.trail_signs()[0]
	var at := Vector2(first["x"], first["z"] + 1.0)
	eq(PR.clue_of(first), "wave", "the first clue is a wave")
	ok(not PR.trail_step(m, 0, "town", at, "dance"), "the wrong emote does not count")
	ok(not PR.trail_step(m, 0, "town", at + Vector2(6, 0), "wave"), "the right emote far away does not count")
	ok(PR.trail_step(m, 0, "town", at, "wave"), "the clue at the sign finds it")
	m.next_variant(first["id"])
	eq(PR.clue_of(m.items[first["id"]]), "cheer", "Change clue shows the next clue")
	var k1: Dictionary = PR.add_keepsake(m, "Sky", 1000)
	PR.add_keepsake(m, "Sunny", 1060)
	PR.add_keepsake(m, "Sky", 1100)
	eq(k1["by"], ["Sky", "Sunny"], "friends finishing together share one keepsake")
	PR.add_keepsake(m, "Leaf", 5000)
	eq(m.keepsakes.size(), 2, "a later walk makes a new keepsake")
	var m2 := TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))), "a town with a trail saves and loads")
	eq(m2.trail_signs().map(func(s): return s["num"]), [1, 2, 3, 4, 5], "sign numbers survive a save")
	eq(m2.keepsakes, m.keepsakes, "keepsakes survive a save")
	var old := m.to_dict()
	old.erase("keepsakes")
	var m3 := TownModel.new()
	ok(m3.from_dict(old) and m3.keepsakes.is_empty(), "an older save loads with no keepsakes")


func test_music_box_rules() -> void:
	var PR = load("res://scripts/core/play_rules.gd")
	var m := TownModel.new()
	var r: Dictionary = m.place("music_box", "town", 5.0, -9.0, 0)
	ok(r["ok"] and r["item"]["song"] == TownModel.MUSIC_DEFAULT and r["item"]["on"] == false, "a new music box has a starter tune and is quiet")
	var id: String = r["item"]["id"]
	eq(PR.notes_at(m.items[id]["song"], 0), ["bell", "drum", "bass"], "the starter tune's first step")
	m.toggle_note(id, 3, 0)
	eq(PR.notes_at(m.items[id]["song"], 0), ["bell", "drum"], "a tap turns a note off")
	m.toggle_note(id, 2, 1)
	eq(PR.notes_at(m.items[id]["song"], 1), ["chime"], "and another on")
	ok(not m.toggle_note(id, 4, 0)["ok"] and not m.toggle_note(id, 0, 8)["ok"], "only the 4 x 8 cells exist")
	m.set_music_on(id, true)
	eq(PR.music_step(0), 0, "the loop starts at step 0")
	eq(PR.music_step(PR.STEP_MS * 9), 1, "and wraps after eight steps")
	eq(PR.check_music(m, id, "town", Vector2(5, -8)), "", "next to the box it can be played")
	eq(PR.check_music(m, id, "town", Vector2(5, 0)), "Walk to the music box to play it.", "far away it cannot")
	var song: Array = m.items[id]["song"].duplicate()
	var removed: Array = m.remove(id)["removed"]
	var back: Dictionary = m.restore(removed)["items"][0]
	ok(back["song"] == song and back["on"], "undo brings the tune back")
	var m2 := TownModel.new()
	ok(m2.from_dict(JSON.parse_string(JSON.stringify(m.to_dict()))) and m2.items[back["id"]]["song"] == song, "the tune survives a save")
	eq(TownModel.sanitize_song([999, -3, "x"]), TownModel.MUSIC_DEFAULT, "a damaged tune falls back to the starter tune")
	eq(TownModel.sanitize_song([999, -3, 5, 1]), [255, 0, 5, 1], "out-of-range cells are clamped")
	ok(Catalog.allowed_in("music_box", "town") and Catalog.allowed_in("music_box", "home:0:0"), "music boxes go indoors and outdoors")


func test_story_rules() -> void:
	var S = load("res://scripts/core/story.gd")
	eq(S.move([0, 1, 2], 0, 1), [1, 0, 2], "a picture moves right")
	eq(S.move([0, 1, 2], 0, -1), [0, 1, 2], "the first picture cannot move further left")
	eq(S.card("rain")["title"], "Unexpected Rain", "cards are found by id")
	eq(S.card("nope")["id"], "none", "an unknown card is the no-title card")
	var panels := []
	for c in [Color.RED, Color.GREEN, Color.BLUE]:
		var img := Image.create(800, 450, false, Image.FORMAT_RGBA8)
		img.fill(c)
		panels.append(img)
	var strip: Image = S.compose(panels, [2, 0, 1])
	eq(strip.get_size(), Vector2i(3 * S.PANEL_W + 4 * S.GAP, S.PANEL_H + 2 * S.GAP), "the strip has three panels on paper")
	ok(strip.get_pixel(S.GAP + 10, S.GAP + 10).is_equal_approx(Color.BLUE), "the order is kept (blue first)")
	ok(strip.get_pixel(S.GAP * 2 + S.PANEL_W + 10, S.GAP + 10).is_equal_approx(Color.RED), "red second")
	var dir := "user://test_stories"
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else []:
		DirAccess.remove_absolute(dir.path_join(f))
	ok(S.save(strip, "rain", 100, dir) != "", "a story is kept on the device")
	S.save(strip, "none", 200, dir)
	var stored: Array = S.list(dir)
	eq(stored.map(func(e): return e["card"]), ["none", "rain"], "stories are listed newest first with their cards")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func test_batch2_session() -> void:
	var path := "user://test_batch2_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	var me: int = Session.my_id
	var at := func(p: Vector2): Session.players[me]["state"] = {"space": "town", "x": p.x, "z": p.y}
	var free := func(kind: String, near: Vector2) -> Vector2: return Session.model.find_free_spot(kind, "town", near)
	# Dress-up.
	var changed := []
	var cb := func(peer): changed.append(peer)
	Session.avatar_changed.connect(cb)
	var r := await _result(Session.dress("explorer", 5))
	Session.avatar_changed.disconnect(cb)
	ok(r.get("ok", false) and Session.players[me]["avatar"]["hat"] == "explorer" and Session.players[me]["avatar"]["outfit_color"] == 5, "dress-up goes through the authority")
	eq(changed, [me], "everyone hears about the new look")
	eq(Session.model.roster[Session.my_pid]["color"], 5, "the roster color follows the clothes")
	r = await _result(Session.dress("jetpack", 99))
	eq(Session.players[me]["avatar"]["hat"], "", "an unknown hat is refused safely")
	# A trail of two signs, walked with clues.
	var signs := []
	for p in [Vector2(-12, -16), Vector2(-6, -16)]:
		r = await _result(Session.place("trail_sign", "town", free.call("trail_sign", p), 0, -2))
		signs.append(r.get("item", {}))
	ok(signs.all(func(s): return not s.is_empty()), "two trail signs placed")
	var progress := []
	var tcb := func(peer, found, total, done, _nick): progress.append([peer, found, total, done])
	Session.trail_changed.connect(tcb)
	at.call(Vector2(0, 0))
	ok((await _result(Session.follow_trail(true))).get("ok", false), "following the trail starts")
	at.call(Vector2(signs[0]["x"], signs[0]["z"] + 1.0))
	Session.send_emote("dance")
	Session.send_emote("wave")
	await _result(0)
	at.call(Vector2(signs[1]["x"], signs[1]["z"] + 1.0))
	Session.send_emote("wave")
	await _result(0)
	Session.trail_changed.disconnect(tcb)
	eq(progress, [[me, 0, 2, false], [me, 1, 2, false], [me, 2, 2, true]], "only the clue at each sign counts; the last one finishes")
	ok(Session.model.keepsakes.size() == 1 and Session.model.keepsakes[0]["by"] == ["Sunny"], "the walker gets a keepsake sticker")
	ok(not Session.trail_walk.has(me), "the walk is over")
	# A music box tune.
	r = await _result(Session.place("music_box", "town", free.call("music_box", Vector2(10, -16)), 0, -2))
	var mb: Dictionary = r.get("item", {})
	at.call(Vector2(30, 30))
	eq((await _result(Session.toggle_note(mb["id"], 0, 3))).get("error"), "Walk to the music box to play it.", "the tune is changed next to the box")
	at.call(Vector2(mb["x"], mb["z"] + 1.0))
	ok((await _result(Session.toggle_note(mb["id"], 0, 3))).get("ok", false), "a note is added")
	ok((await _result(Session.play_music(mb["id"], true))).get("ok", false) and Session.model.items[mb["id"]]["on"], "the music box plays")
	# A toy track.
	var base := Vector2(99, 99)
	for x in range(6, 22):
		for z in range(-18, 18):
			var c := Vector2(x, z)
			if base.x == 99 and Session.model.check("track_start", "town", c.x, c.y, 0) == "" and Session.model.check("track_finish", "town", c.x, c.y + 1, 0) == "":
				base = c
	r = await _result(Session.place("track_start", "town", base, 0, -2))
	var st: String = r.get("item", {}).get("id", "")
	await _result(Session.place("track_finish", "town", base + Vector2(0, 1), 0, -2))
	var rolled := []
	var rcb := func(id, cells, end, _at, _bells): rolled.append([id, cells.size(), end])
	Session.track_rolled.connect(rcb)
	at.call(base + Vector2(1.5, 0))
	r = await _result(Session.roll_track(st))
	ok(r.get("ok", false), "the ball rolls (%s)" % r.get("error", ""))
	eq((await _result(Session.roll_track(st))).get("error"), "The ball is still rolling.", "one ball per start at a time")
	Session.track_rolled.disconnect(rcb)
	eq(rolled, [[st, 2, "finish"]], "everyone sees the ball reach the finish")
	ok(Session.save_now(), "save")
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	ok(Session.model.items.has(mb["id"]) and Session.model.items[mb["id"]]["on"] and Session.model.keepsakes.size() == 1, "music box and keepsake survive a restart")
	Session.leave()


# ------------------------------------------------------------- r11: invitations, animal games, blueprints, weather toys

func test_invite_rules() -> void:
	var I = load("res://scripts/core/invites.gd")
	var a := "a".repeat(32)
	eq(I.check("rocket", "town", 2, -99, 100, "", a), "That invitation is not on the list.", "only listed invitations")
	eq(I.check("music", "town", 0, -99, 100, "", a), "No friends are in town right now.", "alone there is no one to invite")
	eq(I.check("music", "town", 1, 99, 100, "", a), "Your friends have your invitation.", "a second tap right away just keeps the card")
	eq(I.check("help", "town", 1, -99, 100, "", a), "Put this place on display first, then ask friends to help.", "help needs your own display")
	eq(I.check("help", "town", 1, -99, 100, a, a), "", "asking for help on your own display")
	var inbox := {}
	I.add(inbox, I.card(a, "Sunny", "music", "i9", "town", Vector2(1, 2), 100))
	I.add(inbox, I.card(a, "Sunny", "trail", "i3", "town", Vector2(1, 2), 110))
	I.add(inbox, I.card("b".repeat(32), "Kai", "fetch", "", "town", Vector2(3, 2), 105))
	var cards: Array = I.live(inbox, 120)
	eq(cards.map(func(c): return c["kind"]), ["trail", "fetch"], "one card per friend: the newer invitation replaces the older")
	eq(I.live(inbox, 110 + I.LIFETIME + 1).size(), 0, "cards end on their own")
	for k in I.KINDS:
		ok(I.KINDS[k] != "", "invitation %s has a text" % k)


func test_animal_games() -> void:
	var m = TownModel.make_default()
	var brain = AnimalBrain.new(9)
	brain.spawn(m)
	var kid_at := Vector2(-2, 8)
	var sheep: Dictionary = brain.animals.filter(func(a): return a["kind"] == "sheep")[0]
	sheep["pos"] = kid_at + Vector2(3, 0)
	eq(brain.play_with(m, "sheep", 5, kid_at), "started", "Wooly starts its game")
	eq(brain.play_with(m, "sheep", 6, kid_at + Vector2(1, 0)), "joined", "a friend joins the running game instead of taking Wooly away")
	ok(sheep["playmates"] == [5, 6], "both children play with Wooly")
	var kids := [{"id": 5, "pos": kid_at, "emote": "", "emote_t": 0.0}, {"id": 6, "pos": kid_at + Vector2(1, 0), "emote": "", "emote_t": 0.0}]
	_simulate(brain, m, 6.0, kids)
	eq(sheep["plan"], "copy", "Wooly arrived and waits for an emote")
	kids[0]["emote"] = "dance"
	kids[0]["emote_t"] = 50.0
	_simulate(brain, m, 0.3, kids)
	eq(sheep["action"], "dance", "Wooly answers a dance with a dance")
	kids[0]["emote"] = ""
	kids[1]["emote"] = "cheer"
	kids[1]["emote_t"] = 51.0
	_simulate(brain, m, 0.3, kids)
	eq(sheep["action"], "sing", "and the friend's cheer with a song")
	kids[1]["emote"] = ""
	_simulate(brain, m, AnimalBrain.COPY_SECONDS + 2.0, kids)
	ok(sheep["plan"] != "copy" and sheep["playmates"].is_empty(), "after a quiet while Wooly goes back to its routine")
	# Bramble tends a bed: the authority is asked to grow it (the brain never edits the town).
	var bed: Dictionary = m.place("garden_bed", "town", -8.0, 12.0, 0)["item"]
	var rabbit: Dictionary = brain.animals.filter(func(a): return a["kind"] == "rabbit")[0]
	rabbit["pos"] = Vector2(-5, 12)
	brain.events.clear()
	eq(brain.play_with(m, "rabbit", 5, Vector2(-7, 13), 0, Vector2(-7, 12.0), bed["id"]), "started", "Bramble starts gardening")
	var before := JSON.stringify(m.to_dict())
	_simulate(brain, m, 14.0, [{"id": 5, "pos": Vector2(-7, 13), "emote": "", "emote_t": 0.0}])
	ok(brain.events.any(func(e): return e["kind"] == "grow" and e["id"] == bed["id"]), "after tending, the bed is due to grow")
	eq(JSON.stringify(m.to_dict()), before, "the brain itself changed nothing in the town")
	# Tumble's fountain and Pip's splash.
	var ele: Dictionary = brain.animals.filter(func(a): return a["kind"] == "elephant")[0]
	ele["pos"] = Vector2(4, 14)
	brain.events.clear()
	brain.play_with(m, "elephant", 5, Vector2(6, 14), 1)
	var sprayed := [false]
	_simulate(brain, m, 10.0, [{"id": 5, "pos": Vector2(6, 14), "emote": "", "emote_t": 0.0}], func(b): sprayed[0] = sprayed[0] or ele["action"] == "spray")
	ok(sprayed[0] and brain.events.any(func(e): return e["kind"] == "fountain" and e["shape"] == "star"), "Tumble sprays a star fountain")
	var pig: Dictionary = brain.animals.filter(func(a): return a["kind"] == "pig")[0]
	brain.play_with(m, "pig", 5, pig["pos"] + Vector2(2, 0))
	var splashed := [false]
	_simulate(brain, m, 10.0, [{"id": 5, "pos": pig["pos"] + Vector2(2, 0), "emote": "", "emote_t": 0.0}], func(b): splashed[0] = splashed[0] or pig["action"] == "splash")
	ok(splashed[0], "Pip splashes with the child")
	eq(brain.play_with(m, "dog", 5, kid_at), "", "Biscuit's game is fetch, not this")
	brain.start_parade(5.0)
	eq(brain.play_with(m, "sheep", 5, kid_at), "", "not during the dance parade")
	var PW = load("res://scripts/world/play_world.gd")
	for shape in AnimalBrain.FOUNTAINS:
		var pts: PackedVector3Array = PW.fountain_points(shape)
		ok(pts.size() == 48 and Array(pts).all(func(v): return absf(v.x) <= 0.7 and absf(v.y) <= 0.7), "the %s fountain outline is sized for Tumble" % shape)


func test_blueprint_rules() -> void:
	var B = load("res://scripts/core/blueprints.gd")
	var m := TownModel.new()
	var table: Dictionary = m.place("table", "town", 4.0, -10.0, 0, 3)["item"]
	var chair: Dictionary = m.place("chair", "town", 4.0, -8.8, 4, 2)["item"]
	var pot: Dictionary = m.place("plant", "town", 4.0, -10.0, 0, 1, table["id"])["item"]
	m.place("chair", "town", 9.0, -10.0, 0)   # too far: not in the group
	var sm: Dictionary = m.place("snowman", "town", 2.6, -10.0, 0, 4)["item"]
	m.next_variant(sm["id"])
	var bp: Dictionary = B.capture(m, table["id"])
	eq(bp["pieces"].map(func(p): return p["kind"]), ["table", "chair", "snowman", "plant"], "the table, what is near it, and what sits on it")
	eq(bp["pieces"][3]["on"], 0, "the plant remembers it sits on the table")
	eq(bp["pieces"][2]["variant"], 1, "the snowman keeps its face")
	ok(B.capture(m, "nope")["pieces"].is_empty(), "nothing to capture from a missing thing")
	# Placed somewhere else, turned a quarter: the chair stays in front of the table, turned along.
	var planned: Array = B.plan(bp, Vector2(-6, -14), 2)
	var pc: Dictionary = planned[1]
	ok(Vector2(pc["x"], pc["z"]).is_equal_approx(Vector2(-6 + 1.2, -14)), "a quarter turn moves the chair round the table (%s)" % Vector2(pc["x"], pc["z"]))
	eq(pc["rot"], 6, "and turns it with the group")
	var errs: Array = B.preview(m, "town", planned)
	eq(errs, ["", "", "", ""], "the preview shows every piece fits here")
	eq(m.items.size(), 5, "the preview changed nothing")
	var r: Dictionary = B.apply(m, "town", planned)
	eq(r["placed"].size(), 4, "all four pieces placed")
	ok(r["placed"][3].get("host", "") == r["placed"][0]["id"], "the plant sits on the new table")
	var again: Array = B.preview(m, "town", planned)
	ok(again.all(func(e): return e != ""), "the same spot again: every piece reports why it does not fit")
	var indoors: Array = B.preview(m, "home:0:0", B.plan(bp, Vector2.ZERO, 0))
	ok(indoors.all(func(e): return e != ""), "pieces never go where they are not allowed (here: no such house)")
	var path := "user://test_blueprints.json"
	ok(B.save_all([{"name": "Picnic", "pieces": bp["pieces"]}, {"name": "Rocket", "pieces": bp["pieces"]}], path), "blueprints are kept on the device")
	var back: Array = B.load_all(path)
	ok(back.size() == 1 and back[0]["name"] == "Picnic" and back[0]["pieces"].size() == 4, "only names from the list load")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	eq(B.load_all(path), [], "a damaged file loads as no blueprints")
	DirAccess.remove_absolute(path)
	ok(not B.capturable({"id": "x", "kind": "cottage"}) and not B.capturable({"id": "x", "kind": "wall_clock"}), "houses and wall things stay out of blueprints")


func test_r11_props_and_rig() -> void:
	for kind in ["paper_boat", "leaf_pile", "garden_umbrella", "stage_moon", "stage_mountain", "stage_curtain", "track_light"]:
		ok(Catalog.has(kind), "%s is in the toy box" % kind)
	ok(not Catalog.allowed_in("leaf_pile", "home:0:0") and Catalog.allowed_in("stage_curtain", "home:0:0"), "leaf piles outdoors, stage pieces anywhere")
	var RT = load("res://scripts/core/room_themes.gd")
	ok(RT.TOOLKIT_ITEMS["Little Theater"].has("stage_curtain") and RT.TOOLKIT_ITEMS["Rainy Day"].has("paper_boat"), "toolkits list the new pieces")
	eq(Avatar.sanitize({"prop": "baton"})["prop"], "baton", "a known prop is kept")
	eq(Avatar.sanitize({"prop": "sword"})["prop"], "", "an unknown prop becomes nothing in hand")
	var Kid = load("res://scripts/art/kid.gd")
	var kid = Kid.new()
	root.add_child(kid)
	var av: Dictionary = Avatar.PRESETS[0].duplicate()
	av["hat"] = "chef"
	av["prop"] = "umbrella"
	kid.setup(av, false)
	var hand: Node3D = kid.get_node_or_null("Body/ArmR/Hand")
	ok(hand != null and hand.get_child_count() > 0, "the umbrella is held at Body/ArmR/Hand (docs/kid-rig.md)")
	var tops := {"hat": 0.0, "hand": 0.0}
	for path in ["Body/Head/Hat", "Body/ArmR/Hand"]:
		var holder: Node3D = kid.get_node(path)
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D()
			var p: Node = mi
			while p != kid:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var b: AABB = xf * mi.get_aabb()
			if path.ends_with("Hat"):
				tops["hat"] = maxf(tops["hat"], b.end.y)
			else:
				tops["hand"] = maxf(tops["hand"], b.end.y)
	# The canopy is the top 0.16 m of the umbrella (pole and canopy are merged into one mesh).
	ok(tops["hand"] - 0.16 > tops["hat"], "the umbrella canopy clears the tallest hat (rim %.2f > hat %.2f)" % [tops["hand"] - 0.16, tops["hat"]])
	kid.free()


func test_r11_session() -> void:
	var path := "user://test_r11_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	var me: int = Session.my_id
	var at := func(p: Vector2): Session.players[me]["state"] = {"space": "town", "x": p.x, "z": p.y}
	var free := func(kind: String, near: Vector2) -> Vector2: return Session.model.find_free_spot(kind, "town", near)
	at.call(Vector2(0, 6))
	eq((await _result(Session.send_invite("music", ""))).get("error"), "No friends are in town right now.", "alone, nothing is sent")
	# A friend (a test stand-in that is not connected) for the authority's bookkeeping.
	var fpid := "f".repeat(32)
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": 2.0, "z": 6.0}, "pid": fpid}
	ok((await _result(Session.set_display("town", true))).get("on", false), "the square is on display")
	var r := await _result(Session.send_invite("help", "town"))
	ok(r.get("ok", false) and r.get("sent") == 1, "Please help me edit goes to the friend")
	ok(Session.inbox.get(77, {}).has(Session.my_pid), "the friend has one card from me")
	r = await _result(Session.send_invite("help", "town"))
	eq(r.get("error"), "Your friends have your invitation.", "tapping again does not pile up cards")
	# r11 closeout regression: a DIFFERENT invitation right after one must go out
	# (it was refused by a per-inviter cooldown; seen once in net_test --r11).
	r = await _result(Session.send_invite("music", "i1"))
	ok(r.get("ok", false) and r.get("sent") == 1, "a different invitation right away is sent (%s)" % r)
	eq(Session.inbox[77][Session.my_pid]["kind"], "music", "and it replaces the earlier card (one card per friend)")
	r = await _result(Session.send_invite("help", "town"))
	ok(r.get("ok", false), "switching back to help is a different invitation again")
	eq(PlayRules_display(fpid), "This place is on display.", "before joining, the friend is asked first")
	Session._srv_invite_reply(77, 0, Session.my_pid, "join")
	eq(PlayRules_display(fpid), "", "after Join, the friend may help edit")
	ok(not JSON.stringify(Session.model.to_dict()).contains(fpid), "helping is never saved")
	Session._srv_invite_reply(77, 0, Session.my_pid, "leave")
	eq(PlayRules_display(fpid), "This place is on display.", "Leave ends the helping")
	await _result(Session.set_display("town", false))
	# Music parts.
	r = await _result(Session.place("music_box", "town", free.call("music_box", Vector2(8, -14)), 0, -2))
	var mb: Dictionary = r.get("item", {})
	at.call(Vector2(mb["x"], mb["z"] + 1.0))
	Session.players[77]["state"] = {"space": "town", "x": mb["x"] + 1.0, "z": mb["z"] + 1.0}
	ok((await _result(Session.claim_music_part(mb["id"], 1))).get("mine", false), "I take the drum part")
	eq(Session.music_part_names(mb["id"]), {1: "Sunny"}, "everyone sees who plays which part")
	var song_before: Array = Session.model.items[mb["id"]]["song"].duplicate()
	Session._srv_music(77, 0, mb["id"], 1, 2)
	eq(Session.model.items[mb["id"]]["song"], song_before, "a friend's tap on my part is kindly refused")
	Session._srv_music(77, 0, mb["id"], 2, 2)
	ok(int(Session.model.items[mb["id"]]["song"][2]) != int(song_before[2]), "the other parts are open to everyone")
	ok(not (await _result(Session.claim_music_part(mb["id"], 1))).get("mine", true), "tapping my part again lets it go")
	Session.players.erase(77)
	# Animal games through the authority.
	at.call(Vector2(0, 6))
	var brain = root.get_node("Animals").brain
	var rabbit: Dictionary = brain.animals.filter(func(a): return a["kind"] == "rabbit")[0]
	rabbit["pos"] = Vector2(1, 7)
	if Session.model.items.values().filter(func(i): return i["kind"] == "garden_bed" and Vector2(i["x"], i["z"]).distance_to(Vector2(0, 6)) < 15.0).is_empty():
		eq((await _result(Session.play_with_animal("rabbit", 0))).get("error"), "Bramble needs a garden bed nearby. There is one in the toy box.", "Bramble needs a bed")
	r = await _result(Session.place("garden_bed", "town", free.call("garden_bed", Vector2(3, 8)), 0, -2))
	var bed: Dictionary = r.get("item", {})
	eq((await _result(Session.play_with_animal("rabbit", 0))).get("result"), "started", "Bramble comes to garden")
	# Real time: Bramble walks over, gardens for 6 s, then the Animals autoload asks the authority.
	var waited := 0.0
	while int(Session.model.items[bed["id"]].get("growth", 0)) == 0 and waited < 20.0:
		await create_timer(0.25).timeout
		waited += 0.25
	eq(int(Session.model.items[bed["id"]].get("growth", 0)), 1, "the bed grew one stage after Bramble tended it (%.1f s)" % waited)
	at.call(Vector2(30, 30))
	eq((await _result(Session.play_with_animal("sheep", 0))).get("error"), "Walk closer to play together.", "animals play with children close by")
	# Paper boat and leaf pile.
	r = await _result(Session.place("paper_boat", "town", free.call("paper_boat", Vector2(-20, -18)), 0, -2))
	var boat: Dictionary = r.get("item", {})
	at.call(Vector2(boat["x"], boat["z"] + 1.0))
	eq((await _result(Session.sail_boat(boat["id"]))).get("error"), "Put the boat next to a pond (or a puddle when it rains) to sail it.", "a boat needs water nearby")
	var pond: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "pond")[0]
	var dock: Vector2 = free.call("paper_boat", Vector2(pond["x"], pond["z"]) + Vector2(0, 2.6))
	ok(dock.distance_to(Vector2(pond["x"], pond["z"])) < 3.6, "a spot next to the pond (%.1f m)" % dock.distance_to(Vector2(pond["x"], pond["z"])))
	await _result(Session.move(boat["id"], dock, 0))
	at.call(dock + Vector2(0.8, 0))
	var sailed := []
	var scb := func(id, c, rad): sailed.append([id, c, rad])
	Session.boat_sailed.connect(scb)
	ok((await _result(Session.sail_boat(boat["id"]))).get("ok", false), "the boat sails")
	Session.boat_sailed.disconnect(scb)
	ok(sailed.size() == 1 and sailed[0][1] == Vector2(pond["x"], pond["z"]), "around the pond")
	r = await _result(Session.place("leaf_pile", "town", free.call("leaf_pile", Vector2(12, 12)), 0, -2))
	var pile: Dictionary = r.get("item", {})
	at.call(Vector2(pile["x"], pile["z"] + 1.0))
	ok((await _result(Session.jump_in_leaves(pile["id"]))).get("ok", false), "jump in the leaves")
	ok(not (await _result(Session.jump_in_leaves(pile["id"]))).get("together", true), "jumping twice alone is not 'together'")
	# Blueprint: capture a group and place it elsewhere; undo removes it.
	var B = load("res://scripts/core/blueprints.gd")
	var bp: Dictionary = B.capture(Session.model, pile["id"])
	at.call(Vector2(-14, 16))
	var target: Vector2 = free.call("leaf_pile", Vector2(-14, 18))
	r = await _result(Session.place_blueprint("town", B.plan(bp, target, 0)))
	ok(r.get("ok", false) and r.get("ids", []).size() >= 1, "a blueprint goes in piece by piece (%s)" % r)
	for id in r.get("ids", []):
		await _result(Session.remove(id))
	ok(r.get("ids", []).all(func(id): return not Session.model.items.has(id)), "and every placed piece can be put away again")
	# Dress-up with clothes style and a handheld prop; the starter trail.
	r = await _result(Session.dress("", 4, 2, "baton"))
	ok(Session.players[me]["avatar"]["outfit"] == 2 and Session.players[me]["avatar"]["prop"] == "baton", "clothes style and a baton")
	r = await _result(Session.dress("crown", 4))
	ok(Session.players[me]["avatar"]["prop"] == "baton" and Session.players[me]["avatar"]["hat"] == "crown", "changing the hat keeps the baton")
	if Session.model.trail_signs().size() < 2:
		r = await _result(Session.starter_trail())
		ok(r.get("ok", false) and Session.model.trail_signs().size() >= 2, "a starter trail is suggested (%d signs)" % r.get("count", 0))
		ok(Session.model.trail_signs().map(func(s): return s.get("variant", 0)).size() >= 2, "with clues")
	eq((await _result(Session.starter_trail())).get("error"), "There is a trail already. Follow it, or move its signs.", "only when there is no trail yet")
	Session.leave()


func PlayRules_display(pid: String) -> String:
	return load("res://scripts/core/play_rules.gd").display_error(Session.model, "town", pid)


# ------------------------------------------------------------- r11b: fixes from the r11 Mac image review

func test_r11b_review_fixes() -> void:
	# Every name a player reads from these lists is in all six catalogs ("Bell" was
	# missing everywhere: the string extractor treated it as a node name).
	var PR = load("res://scripts/core/play_rules.gd")
	var I = load("res://scripts/core/invites.gd")
	var B = load("res://scripts/core/blueprints.gd")
	var RT = load("res://scripts/core/room_themes.gd")
	var S = load("res://scripts/core/story.gd")
	var texts := []
	texts.append_array(PR.SOUND_NAMES.values())
	texts.append_array(Avatar.POSE_NAMES.values())
	texts.append_array(Avatar.HAT_NAMES.values())
	texts.append_array(Avatar.PROP_NAMES.values())
	texts.append_array(Avatar.OUTFITS)
	texts.append_array(I.KINDS.values())
	texts.append_array(B.NAMES)
	texts.append_array(RT.TOOLKITS)
	texts.append_array(RT.TOOLKIT_IDEAS.values())
	for c in S.CARDS:
		texts.append(c["prompt"])
		if c["title"] != "":
			texts.append(c["title"])
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing := texts.filter(func(t): return not cat.has(t) or str(cat[t]).strip_edges() == "")
		eq(missing, [], "[%s] every listed player-facing name is translated" % code)
	var de: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/de.json"))
	var ja: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/ja.json"))
	ok(de.get("Bell") == "Glocke" and ja.get("Bell") == "\u30d9\u30eb", "the music box bell row is translated")
	# The paper boat's lap stays inside the pond's water (an ellipse 1.65 x 1.35 m,
	# rim stones beyond) for every turn of the pond; the review saw it on the rim.
	var PW = load("res://scripts/world/play_world.gd")
	for rot in 8:
		var turn := TownModel.rot_to_radians(rot)
		var worst := 0.0
		for i in 64:
			var p: Vector2 = PW.sail_point(Vector2(5, -3), PW.POND_SAIL, turn, TAU * i / 64.0)
			var local := (p - Vector2(5, -3)).rotated(turn)
			worst = maxf(worst, Vector2(local.x / (1.65 - 0.2), local.y / (1.35 - 0.2)).length())
		ok(worst <= 1.0, "pond turned %d: the whole lap is on the water, clear of the rim (%.2f)" % [rot, worst])
	# A held prop stays upright through every emote and pose (the review saw the
	# umbrella swing sideways in the real story strip).
	var Kid = load("res://scripts/art/kid.gd")
	var kid = Kid.new()
	root.add_child(kid)
	var av: Dictionary = Avatar.PRESETS[0].duplicate()
	av["prop"] = "umbrella"
	kid.setup(av, false)
	var hand: Node3D = kid.get_node("Body/ArmR/Hand")
	var worst_tilt := 0.0
	for e in Avatar.EMOTES + Avatar.POSES:
		kid.play_emote(e)
		for f in 6:
			kid._pose(0.1)
			var xf := Transform3D()
			var n: Node = hand
			while n != kid:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			worst_tilt = maxf(worst_tilt, rad_to_deg(xf.basis.y.normalized().angle_to(Vector3.UP)))
	ok(worst_tilt < 25.0, "the umbrella stays upright in every emote and pose (worst tilt %.0f degrees)" % worst_tilt)
	kid.free()


# ------------------------------------------------------------- r12: wearable clothing

const W := preload("res://scripts/core/wearables.gd")


func test_wear_catalog() -> void:
	var items: Dictionary = W.items()
	var gated: Dictionary = W.gated()
	eq(items.size(), 434, "all 434 frozen wearables are in the wardrobe (wear-r2 complete, rev5 hold contract)")
	eq(gated.size(), 0, "no item is gated since the rev5 final acceptance")
	ok(gated.keys().all(func(k): return not items.has(k)), "no gated item is in the wardrobe")
	var per := {}
	for id in items:
		per[items[id]["category"]] = per.get(items[id]["category"], 0) + 1
	eq(per, {"Tops": 49, "Bottoms": 50, "Dress-up": 50, "Headwear": 48, "Accessories": 48, "Socks": 48, "Shoes": 43, "Bags": 48, "Umbrellas": 50}, "categories")
	var bad := []
	for id in items:
		var d: Dictionary = items[id]
		var path := W.glb(id)
		if not ResourceLoader.exists(path) or FileAccess.get_sha256(path) != d["sha256"]:
			bad.append(id + " file")
		if not W.SLOTS.has(d["slot"]) or (d["held"] != (d["slot"] == "hand")):
			bad.append(id + " slot")
		if d["sit"] and not (d["parts"].has("Body") and d["parts"].has("Body_sit") and d["parts"].has("LegL_sit") and d["parts"].has("LegR_sit")):
			bad.append(id + " sit parts")
	eq(bad, [], "every GLB matches its frozen hash; slots and seated parts are consistent")
	eq(items.values().filter(func(d): return d["sit"]).size(), 61, "the 61 skirted garments use their frozen seated variants")
	var held: Array = items.values().filter(func(d): return d["held"])
	eq(held.size(), 60, "60 held items (50 umbrellas, 10 hand-held bags)")
	ok(held.all(func(d): return d["slot"] == "hand" and d["parts"] == ["ArmR"] and d.get("hold", "") != ""), "each held item is a right-hand part with its W9 hold record")
	eq(held.filter(func(d): return str(d.get("hold")).begins_with("pilot")).size(), 4, "4 from the accepted pilot, 56 from the frozen rev5 records")
	eq(items.values().filter(func(d): return d["band"]).size(), 15, "15 band-style headwear keep the hair")
	var texts: Array = items.values().map(func(d): return d["name"])
	texts.append_array(W.CATEGORIES)
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing := texts.filter(func(t): return not cat.has(t) or str(cat[t]).strip_edges() == "")
		eq(missing, [], "[%s] every wardrobe item and category name is translated" % code)
		var dup := []
		for c in W.CATEGORIES:
			var seen := {}
			for d in items.values().filter(func(x): return x["category"] == c):
				var t: String = str(cat.get(d["name"], d["name"]))
				if seen.has(t):
					dup.append(t)
				seen[t] = true
		eq(dup, [], "[%s] no two wardrobe items in one tab share a name (tiles can be told apart)" % code)


func test_wear_rules() -> void:
	var dress := "paradise_planning_maxi"
	var top := "a_tee"
	var r: Dictionary = W.equip({}, "top", top)
	ok(r["ok"] and r["wear"] == {"top": top}, "wear a top")
	r = W.equip(r["wear"], "bottom", "acid_washed_jeans")
	r = W.equip(r["wear"], "dress", dress)
	eq(r["wear"], {"dress": dress}, "a dress-up replaces the top and the bottom")
	r = W.equip(r["wear"], "top", top)
	eq(r["wear"], {"top": top}, "a top replaces the dress-up")
	ok(W.equip({}, "hand", "bat_umbrella")["ok"], "a rev5 umbrella can be held")
	# A gated item (none since rev5; the mechanism stays for later batches) is refused.
	W.data()["gated"]["test_gated"] = {"name": "Test", "category": "Umbrellas", "waiting_for": "test"}
	eq(W.equip({}, "hand", "test_gated")["error"], "That one is not ready to wear yet.", "a gated item is refused")
	W.data()["gated"].erase("test_gated")
	eq(W.equip({}, "head", top)["error"], "That is not in the wardrobe.", "an item only goes in its own slot")
	eq(W.equip({}, "tail", top)["error"], "That is not a place to wear things.", "unknown slots are refused")
	eq(W.equip({"top": top}, "top", "")["wear"], {}, "taking off")
	eq(W.sanitize({"top": top, "dress": dress, "head": "nope", "face": top}), {"dress": dress}, "saved sets keep only valid items; a dress-up wins")
	eq(W.sanitize("junk"), {}, "damaged data wears nothing")
	eq(W.hides({"top": top}), ["outfit_body", "outfit_arm"], "a top replaces the baked torso and sleeves")
	var band: String = W.items().keys().filter(func(k): return W.get_def(k)["band"])[0]
	var hat: String = W.items().keys().filter(func(k): return W.get_def(k)["slot"] == "head" and not W.get_def(k)["band"])[0]
	eq(W.hides({"head": band}), [], "band headwear keeps the hair")
	eq(W.hides({"head": hat}), ["hair"], "other headwear replaces the hair")
	# Pose states (EQUIP_HANDOFF 9 precedence).
	var dz := {"dress": dress}
	var dh := {"dress": dress, "hand": "apple_umbrella"}
	var bag := {"hand": "basket_bag"}
	var umb := {"hand": "apple_umbrella"}
	var expect := [
		[dz, "sit", true, true, false], [dz, "swing", true, false, false], [dz, "walk", false, false, false],
		[dh, "sit", true, true, false], [dh, "rest", true, true, false], [dh, "walk", false, false, true],
		[umb, "sit", false, false, true], [umb, "swing", false, false, false], [umb, "ride", false, false, false],
		[bag, "sit", false, false, false], [bag, "idle", false, false, true]]
	for e in expect:
		var st: Dictionary = W.pose_state(e[1], e[0])
		ok(st["seated"] == e[2] and st["sit_hands"] == e[3] and st["held_visible"] == e[4], "%s in %s: %s" % [e[0].values(), e[1], st])
	# Avatars: older ones wear nothing; worn head/hand items replace the procedural hat/prop.
	eq(Avatar.sanitize({"nick": "Sky"})["wear"], {}, "an older avatar wears nothing")
	var av := Avatar.sanitize({"hat": "chef", "prop": "umbrella", "wear": {"head": hat, "hand": "apple_umbrella"}})
	ok(av["hat"] == "" and av["prop"] == "" and av["wear"].size() == 2, "worn head and hand items replace the hat and the prop")


## Vertices of the baked (non-wearable) meshes under a node.
func _baked_vertices(kid: Node3D, wear_meshes: Array) -> int:
	var n := 0
	for mi in kid.find_children("*", "MeshInstance3D", true, false):
		if wear_meshes.has(mi) or not mi.mesh:
			continue
		for sfc in mi.mesh.get_surface_count():
			n += (mi.mesh.surface_get_arrays(sfc)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func test_wear_kid() -> void:
	var Kid = load("res://scripts/art/kid.gd")
	var base: Dictionary = Avatar.PRESETS[0].duplicate(true)
	var kid0 = Kid.new()
	root.add_child(kid0)
	kid0.setup(base, false)
	var bare: int = _baked_vertices(kid0, [])
	kid0.free()
	var worn := {"dress": "paradise_planning_maxi", "hand": "apple_umbrella", "shoes": W.ids_in("Shoes")[0],
		"socks": W.ids_in("Socks")[0], "face": W.ids_in("Accessories")[0], "bag": W.ids_in("Bags").filter(func(k): return not W.get_def(k)["held"])[0]}
	var av := base.duplicate(true)
	av["wear"] = worn
	var kid = Kid.new()
	root.add_child(kid)
	kid.setup(av, false)
	var expected := 0
	for id in worn.values():
		expected += W.get_def(id)["parts"].size()
	eq(kid._wear["all"].size(), expected, "every part of every worn item is mounted (%d)" % expected)
	var pivot_ok: bool = kid._wear["all"].all(func(m): return m.transform == Transform3D.IDENTITY \
		and str(m.name).trim_suffix("_sit").ends_with("_" + str(m.get_parent().name)))
	ok(pivot_ok, "each part hangs under the child node of its own pivot with an identity transform")
	ok(_baked_vertices(kid, kid._wear["all"]) < bare, "the baked outfit and shoes the clothes replace are not built")
	# The handoff's hide/restore sequence.
	var held: Array = kid._wear["held"]
	for step in [["walk", false, true], ["sit", true, false], ["idle", false, true], ["swing", true, false], ["walk", false, true],
			["idle", false, true], ["rest", true, false], ["idle", false, true]]:
		kid.anim = step[0]
		kid._pose(0.016)
		var sit_on: bool = kid._wear["sit"].all(func(m): return m.visible)
		var stand_on: bool = kid._wear["standing"].all(func(m): return m.visible)
		ok(sit_on == step[1] and stand_on == (not step[1]) and kid._wear["sit"].any(func(m): return m.visible) == step[1], "%s: seated cloth %s, standing cloth %s (never both)" % [step[0], step[1], not step[1]])
		ok(held.all(func(m): return m.visible == step[2]), "%s: the umbrella is %s" % [step[0], "shown" if step[2] else "hidden"])
		if step[0] in ["sit", "rest"]:
			ok(is_equal_approx(kid._arms[0].rotation.x, W.SIT_HANDS_X) and is_equal_approx(kid._arms[1].rotation.x, W.SIT_HANDS_X), "%s in a seated dress: hands forward over the knees" % step[0])
		if step[2]:
			var a: Node3D = kid._arms[1]
			ok(a.rotation.x >= W.HOLD_X.x - 0.001 and a.rotation.x <= W.HOLD_X.y + 0.001 and a.rotation.z >= -0.001 and a.rotation.z <= W.HOLD_Z.y + 0.001, "%s: the holding arm stays in the envelope" % step[0])
	# Emotes while holding: the wave plays on the left arm; the right arm keeps holding.
	kid.anim = "idle"
	kid.play_emote("wave")
	kid._pose(0.016)
	ok(kid._arms[1].rotation.z <= W.HOLD_Z.y + 0.001 and kid._arms[0].rotation.z < -1.5 and held.all(func(m): return m.visible), "wave with an umbrella: the left arm waves, the right holds")
	# Rebuilding (a dress-up change in town) never duplicates the clothes.
	for i in 3:
		kid.setup(av, false)
	var in_tree: Array = kid.find_children("*", "MeshInstance3D", true, false).filter(func(m): return str(m.name).begins_with("paradise_planning_maxi_"))
	eq(in_tree.size(), W.get_def("paradise_planning_maxi")["parts"].size(), "after three rebuilds the dress is there once")
	# Headwear: a band keeps the hair, a hat replaces it.
	var band: String = W.items().keys().filter(func(k): return W.get_def(k)["band"])[0]
	var hat: String = W.items().keys().filter(func(k): return W.get_def(k)["slot"] == "head" and not W.get_def(k)["band"])[0]
	var hb := base.duplicate(true)
	hb["wear"] = {"head": band}
	kid.setup(hb, false)
	var v_band: int = _baked_vertices(kid, kid._wear["all"])
	hb["wear"] = {"head": hat}
	kid.setup(hb, false)
	ok(v_band == bare and _baked_vertices(kid, kid._wear["all"]) < bare, "band headwear keeps the hair; a hat hides it")
	kid.free()
	# Loading stays bounded however many items are tried on.
	var k2 = Kid.new()
	root.add_child(k2)
	for id in W.ids_in("Socks") + W.ids_in("Shoes"):
		var a2 := base.duplicate(true)
		a2["wear"] = {W.get_def(id)["slot"]: id}
		k2.setup(a2, false)
	ok(Kid.wear_cache_size() <= Kid.WEAR_CACHE_MAX, "at most %d wearable scenes stay loaded (%d)" % [Kid.WEAR_CACHE_MAX, Kid.wear_cache_size()])
	k2.free()


## Wardrobe pictures (r14): on demand, bounded, never stale. A stub renderer makes a distinct
## texture per item so the queue and cache rules are checked without a GPU.
func test_wear_thumbs() -> void:
	var WT = load("res://scripts/ui/wear_thumbs.gd")
	var t = WT.new()
	root.add_child(t)
	var made := []
	t.render_override = func(id: String) -> Texture2D:
		made.append(id)
		if id == "goggles":
			return null   # a model that cannot be pictured
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color8(hash(id) & 255, (hash(id) >> 8) & 255, 7))
		return ImageTexture.create_from_image(img)
	var settle := func() -> void:
		var n := 0
		while (t._busy or not t.queued().is_empty()) and n < 600:
			await process_frame
			n += 1
	eq(t.viewports_alive(), 0, "no viewport before anything is asked")
	var dress: Array = W.ids_in("Dress-up").slice(0, 10)
	t.want(dress)
	await settle.call()
	eq(made, dress, "the visible tiles are pictured in order, once each")
	ok(dress.all(func(id): return t.get_cached(id) != null), "and kept")
	var tex: Array = dress.map(func(id): return t.get_cached(id))
	var uniq := {}
	for x in tex:
		uniq[x.get_instance_id()] = true
	eq(uniq.size(), 10, "each tile has its own picture")
	t.want(dress)
	await settle.call()
	eq(made.size(), 10, "warm: reopening the same rows renders nothing new")
	# Fast tab changes: only the last wanted rows are pictured (one render may already be under way).
	var tops: Array = W.ids_in("Tops").slice(0, 8)
	var shoes: Array = W.ids_in("Shoes").slice(0, 6)
	var before := made.size()
	t.want(tops)
	t.want(shoes)
	await settle.call()
	var after: Array = made.slice(before)
	ok(shoes.all(func(id): return after.has(id)), "the last tab's rows are pictured")
	ok(after.filter(func(id): return tops.has(id)).size() <= 1, "rows of a tab left quickly are not rendered (at most the one under way: %d)" % after.filter(func(id): return tops.has(id)).size())
	eq(t.queued(), [], "nothing stale is left in the queue")
	# Failures are not retried; the rest still arrive.
	t.want(["goggles", "boots"])
	await settle.call()
	ok(t.failed.has("goggles") and t.get_cached("goggles") == null and t.get_cached("boots") != null, "a model that cannot be pictured is skipped; the next one still comes")
	var n_made := made.size()
	t.want(["goggles"])
	await settle.call()
	eq(made.size(), n_made, "and it is not retried")
	# The cache stays bounded; the rows on screen are kept fresh and survive eviction.
	var all_ids: Array = W.items().keys()
	all_ids.sort()
	var keep: Array = dress.slice(0, 4)
	for i in range(0, 200, 25):
		t.want(keep + all_ids.slice(i, i + 25))
		await settle.call()
	ok(t.cache.size() <= WT.CACHE_MAX, "at most %d pictures in memory (%d)" % [WT.CACHE_MAX, t.cache.size()])
	ok(keep.all(func(id): return t.cache.has(id)), "pictures still on screen are not evicted")
	ok(t._order.size() == t.cache.size(), "the eviction order tracks the cache exactly")
	# The render viewport exists only while working and is freed when idle.
	t.render_override = Callable()
	t.stub = false
	t._ensure_viewport()
	eq(t.viewports_alive(), 1, "one viewport while pictures are being made")
	var waited := 0.0
	while t.viewports_alive() > 0 and waited < WT.IDLE_FREE + 1.5:
		await create_timer(0.1).timeout
		waited += 0.1
	eq(t.viewports_alive(), 0, "and none after %.1f s idle" % WT.IDLE_FREE)
	t.queue_free()
	# Nothing at startup: the HUD makes the picture maker only when the Wardrobe opens.
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	ok(hud_src.count("WearThumbs.new()") == 1 and hud_src.contains("func wardrobe_thumbs()"), "the HUD creates the picture maker lazily, in one place")


func test_wear_session() -> void:
	var path := "user://test_wear_town.json"
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	var me: int = Session.my_id
	var changed := []
	var cb := func(peer): changed.append(peer)
	Session.avatar_changed.connect(cb)
	var r := await _result(Session.wear("dress", "paradise_planning_maxi"))
	ok(r.get("ok", false) and Session.players[me]["avatar"]["wear"] == {"dress": "paradise_planning_maxi"}, "wearing goes through the authority")
	eq(changed, [me], "everyone hears about the new look")
	W.data()["gated"]["test_gated"] = {"name": "Test", "category": "Umbrellas", "waiting_for": "test"}
	eq((await _result(Session.wear("hand", "test_gated"))).get("error"), "That one is not ready to wear yet.", "the authority refuses gated items")
	W.data()["gated"].erase("test_gated")
	ok((await _result(Session.wear("hand", "furoshiki_bag"))).get("ok", false), "a rev5 hand-held bag is accepted")
	eq((await _result(Session.wear("head", "a_tee"))).get("error"), "That is not in the wardrobe.", "and items in the wrong slot")
	await _result(Session.wear("hand", "apple_umbrella"))
	await _result(Session.dress("", 3, -1, "flag"))
	ok(Session.players[me]["avatar"]["prop"] == "flag" and not Session.players[me]["avatar"]["wear"].has("hand"), "a handheld prop replaces the held umbrella")
	var hat: String = W.items().keys().filter(func(k): return W.get_def(k)["slot"] == "head")[0]
	await _result(Session.wear("head", hat))
	ok(Session.players[me]["avatar"]["hat"] == "" and Session.players[me]["avatar"]["wear"]["head"] == hat, "headwear replaces the procedural hat")
	await _result(Session.dress("crown", 3))
	ok(not Session.players[me]["avatar"]["wear"].has("head"), "and the hat replaces the headwear")
	var keep: Dictionary = Session.players[me]["avatar"].duplicate(true)
	Session.avatar_changed.disconnect(cb)
	Session.leave()
	# The device keeps the look (settings); joining again with it wears the same things.
	Session.start_solo(path, keep)
	await process_frame
	eq(Session.players[Session.my_id]["avatar"]["wear"], keep["wear"], "the worn set comes back after leaving and joining again")
	Session.leave()
