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
var _current := ""


func _initialize() -> void:
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
		"test_modeled_assets", "test_mounted_items", "test_wish_rules", "test_gift_rules", "test_garden_rules",
		"test_hearts_and_visits", "test_photo_idea_rules", "test_activity_data_saves", "test_hide_and_seek_warmth",
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
	eq(modeled.size(), 10 + 130, "the ten pilot models and the 130 production models (release r1) are placeable")
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
