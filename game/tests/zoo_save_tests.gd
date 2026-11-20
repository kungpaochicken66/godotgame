## Headless tests for the zoo's model, saves and compatibility (docs/zoo-engineering-standard.md section 7):
## schema 3 and its migrations from real schema-1 and schema-2 saves, the zoo space and its cap and blocked
## ground, the catalog entries, the town's tram stop and its rules, the "maps" key, and the three save files
## (main, a schema-2 .bak projection, the .maps sidecar) with a frozen schema-2 reader, a downgrade and an
## upgrade, damaged parts, and the Apple TV copy of the sidecar. Nothing here renders.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_save_tests.gd
extends SceneTree

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Blueprints := preload("res://scripts/core/blueprints.gd")
const Durable := preload("res://scripts/core/durable.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const FakeDefaults := preload("res://tests/fake_defaults.gd")

const FIXTURES := "res://tests/fixtures/saves/"
const DIR := "user://zoo_save_w1"
## The kinds an app from before the zoo has never heard of.
const ZOO_KINDS := ["zoo_ball", "zoo_box", "scratching_log", "leaf_feeder", "hay_bale", "play_mirror"]
## Section 6 of the standard: the sizes the catalog must state (w x h x d, m).
const BOUNDS := {"tram_stop": Vector3(3.2, 2.4, 2.0), "zoo_ball": Vector3(0.5, 0.5, 0.5), "zoo_box": Vector3(0.9, 0.8, 0.9),
	"scratching_log": Vector3(1.8, 0.8, 0.8), "leaf_feeder": Vector3(0.9, 2.4, 0.9), "hay_bale": Vector3(1.1, 0.8, 0.8),
	"play_mirror": Vector3(1.0, 1.3, 0.4)}
const STAYS := "The tram stop stays in town. You can move it."
## Open ground in the zoo's south-west lawn: nothing blocks a toy anywhere here.
const LAWN := Rect2(-38.0, 17.0, 18.0, 10.0)

var Session: Node
var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	await process_frame   # the autoloads are in the tree from the first frame
	Session = root.get_node("Session")
	DirAccess.make_dir_recursive_absolute(DIR)
	for t in ["test_constants", "test_catalog_entries", "test_zoo_space", "test_zoo_cap_and_loading", "test_zoo_things_not_elsewhere",
			"test_tram_stop_rules", "test_tram_stop_placement", "test_tram_stop_door", "test_blueprints", "test_maps_key",
			"test_migration_v1", "test_migration_v2", "test_projection_and_old_reader", "test_sidecar_merge", "test_damaged_parts",
			"test_durable_sidecar"]:
		_current = t
		call(t)
	for t in ["test_session_files", "test_session_downgrade_roundtrip", "test_session_first_migration_copies", "test_session_refusals"]:
		_current = t
		await call(t)
	print("\nZOO SAVE TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func eq(a: Variant, b: Variant, what: String) -> void:
	ok(a == b, "%s: expected %s, got %s" % [what, b, a])


# ---------------------------------------------------------------- helpers

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + name))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## What a save file does to numbers: through JSON text and back.
func _via_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _loaded(data: Dictionary) -> TownModel:
	var m := TownModel.new()
	ok(m.from_dict(_via_json(data)), "the save loads")
	return m


func _put(m: TownModel, kind: String, space: String, x: float, z: float, rot := 0) -> String:
	var r: Dictionary = m.place(kind, space, x, z, rot)
	ok(r["ok"], "placing %s in %s at (%.1f, %.1f): %s" % [kind, space, x, z, r.get("error", "")])
	return r.get("item", {}).get("id", "")


## kind|space|x|z|rot|color: an item without its id.
func _sig(i: Dictionary) -> String:
	return "%s|%s|%.2f|%.2f|%d|%d" % [i["kind"], i["space"], float(i["x"]), float(i["z"]), int(i["rot"]), int(i["color"])]


func _sigs(items: Array) -> Array:
	var out: Array = items.map(func(i): return _sig(i))
	out.sort()
	return out


func _zoo_items(m: TownModel) -> Array:
	return m.items.values().filter(func(i): return i["space"] == "zoo")


## A town with some zoo things, the picnic list, found answers and a moved tram stop.
func _zoo_town() -> TownModel:
	var m: TownModel = TownModel.make_default()
	var x := -36.0
	for kind in ["zoo_ball", "zoo_box", "scratching_log", "leaf_feeder", "hay_bale", "play_mirror", "bench", "garden_umbrella"]:
		_put(m, kind, "zoo", x, 22.0)
		x += 3.0
	m.maps = {"zoo": {"found": {"lion": {"wave": {"by": ["Sunny", "Sky"], "t": 1700000000}}, "monkey": {"copy": {"by": ["Sunny"], "t": 1700000500}}}}}
	return m


## The rule of an app from before the zoo, frozen: it reads schema 2 only, keeps the kinds it knows and the
## spaces it knows (the town, and a room of a cottage that is in the file), and drops the rest.
func _old_reader(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or int(data.get("schema", -1)) != 2:
		return {"ok": false, "items": []}
	var unknown: Array = ZOO_KINDS + ["tram_stop"]
	var cottages := {}
	for e in data.get("items", []):
		if typeof(e) == TYPE_DICTIONARY and e.get("kind") == "cottage":
			cottages[str(e["id"])] = true
	var kept := []
	for e in data.get("items", []):
		if typeof(e) != TYPE_DICTIONARY or not e.has_all(["id", "kind", "space", "x", "z", "rot", "color"]):
			continue
		if not Catalog.has(str(e["kind"])) or unknown.has(str(e["kind"])):
			continue
		var space := str(e["space"])
		var parts := space.split(":")
		if space != "town" and not (parts.size() == 3 and cottages.has(parts[0]) and int(parts[1]) < 3 and int(parts[2]) < 2):
			continue
		kept.append(e)
	return {"ok": true, "items": kept}


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _clean(path: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".maps", ".maps.tmp", ".bak.tmp", ".v1", ".v2"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _start(path: String) -> void:
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame


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


# ---------------------------------------------------------------- the model

func test_constants() -> void:
	eq(TownModel.SCHEMA, 3, "schema 3")
	eq(TownModel.MAX_ZOO_ITEMS, 80, "80 things in the zoo")
	eq(TownModel.MAX_TOWN_ITEMS, 300, "the town still holds 300")
	var m := TownModel.new()
	ok(m.is_space("zoo") and m.is_space("town") and not m.is_space("i1:0:0") and not m.is_space("nowhere"), "the zoo is a space")
	ok(not m.from_dict({"schema": 4}) and not m.from_dict({"schema": 0}) and not m.from_dict({}), "other schemas are refused")
	ok(TownModel.new().from_dict({"schema": 3}) and TownModel.new().from_dict({"schema": 2}) and TownModel.new().from_dict({"schema": 1}), "schemas 1, 2 and 3 load")


func test_catalog_entries() -> void:
	eq(Catalog.zoo_kinds().size(), 6, "six zoo toys")
	for kind in ZOO_KINDS:
		ok(Catalog.zoo_kinds().has(kind), "%s is a zoo toy" % kind)
	for kind in BOUNDS:
		var d: Dictionary = Catalog.get_def(kind)
		ok(not d.is_empty(), "%s is in the catalog" % kind)
		ok(d.has_all(["name", "category", "space", "radius", "layer", "color", "seats", "size_class", "anchor", "bounds", "tabletop_eligible"]), "%s has every field" % kind)
		eq(d["bounds"], BOUNDS[kind], "%s states the bounds the builder makes" % kind)
		ok(d["size_class"] in ["landmark", "tree", "large", "medium", "small", "flat"] and d["anchor"] == "ground", "%s class and anchor" % kind)
		ok(d["radius"] <= 0.75 * maxf(d["bounds"].x, d["bounds"].z) + 0.15, "%s footprint stays close to the model size" % kind)
		ok(d["radius"] >= 0.2 and d["layer"] == "solid" and d["color"] == -1 and not d["tabletop_eligible"], "%s is a solid, unpainted floor thing" % kind)
		if d["size_class"] == "small":
			ok(d["bounds"].y >= 0.2 * 1.3 and d["bounds"].y <= 0.45 * 1.3, "%s fits the small class (0.2 to 0.45 H)" % kind)
		if kind != "tram_stop":
			eq(d["space"], "zoo", "%s belongs to the zoo" % kind)
			eq(d["category"], "Zoo", "%s is in the Zoo tab" % kind)
	var stop: Dictionary = Catalog.get_def("tram_stop")
	eq([stop["space"], stop["category"], stop["size_class"]], ["town", "", "landmark"], "the tram stop: a landmark of the town in no toy box tab")
	for space in ["town", "zoo", "i1:0:0", "home:1:1"]:
		ok(not Catalog.offered("tram_stop", space), "the tram stop is offered in no toy box (%s)" % space)
	for cat in Catalog.TOWN_CATEGORIES + Catalog.HOME_CATEGORIES + Catalog.ZOO_CATEGORIES + [""]:
		for space in ["town", "zoo", "i1:0:0"]:
			ok(not Catalog.kinds_for(cat, space).has("tram_stop"), "no tab lists the tram stop (%s in %s)" % [cat, space])
	# allowed_in for the zoo: the zoo toys and the Picnic list, nothing else; the tram stop stays in town.
	for kind in ZOO_KINDS:
		ok(Catalog.allowed_in(kind, "zoo"), "%s is allowed in the zoo" % kind)
		ok(not Catalog.allowed_in(kind, "town") and not Catalog.allowed_in(kind, "i1:0:0") and not Catalog.allowed_in(kind, "i2:2:1"), "%s is allowed nowhere else" % kind)
		ok(Catalog.offered(kind, "zoo") and not Catalog.offered(kind, "town"), "%s is offered by the zoo's toy box only" % kind)
	eq(Catalog.kinds_for("Zoo", "zoo"), ZOO_KINDS, "the Zoo tab lists the six toys in order")
	eq(Catalog.kinds_for("Zoo", "town"), [], "the Zoo tab is empty in town")
	eq(Catalog.kinds_for("Picnic", "zoo"), ["bench", "blanket", "flowers", "fence", "garden_umbrella", "picture_board"], "the Picnic tab")
	for kind in Catalog.ZOO_PICNIC:
		ok(Catalog.allowed_in(kind, "zoo"), "%s may also be placed in the zoo" % kind)
	ok(not Catalog.allowed_in("tram_stop", "zoo") and not Catalog.allowed_in("tram_stop", "i1:0:0") and Catalog.allowed_in("tram_stop", "town"), "the tram stop is a town thing")
	for kind in ["cottage", "pond", "chair", "table", "rug", "swing", "track_start", "ride_station", "puzzle_chest", "push_button", "tree", "music_box", "wall_clock", "scallop_chair"]:
		if Catalog.has(kind):
			ok(not Catalog.allowed_in(kind, "zoo"), "%s is not offered in the zoo" % kind)
	# Nothing existing changed for the town and the rooms.
	ok(Catalog.allowed_in("tree", "town") and not Catalog.allowed_in("tree", "i1:0:0") and Catalog.allowed_in("chair", "town") and Catalog.allowed_in("chair", "i1:0:0"), "town and rooms keep their rules")
	# The builders: when the zoo's props exist, the dispatch hands the zoo's kinds to them.
	if ResourceLoader.exists("res://scripts/art/props_zoo.gd"):
		var Props = load("res://scripts/art/props.gd")
		var PropsZoo = load("res://scripts/art/props_zoo.gd")
		eq(PropsZoo.KINDS.size(), 7, "the zoo builds seven kinds")
		for kind in PropsZoo.KINDS:
			ok(Catalog.has(kind), "the builder's %s is in the catalog" % kind)
			var n: Node3D = Props.build(kind, Catalog.get_def(kind)["color"], 1)
			ok(n != null and n.name == kind and n.get_child_count() > 0, "%s is built by the zoo's builders" % kind)
			n.free()
		for kind in Catalog.zoo_kinds() + ["tram_stop"]:
			ok(PropsZoo.KINDS.has(kind), "the catalog's %s has a zoo builder" % kind)


func test_zoo_space() -> void:
	var m := TownModel.new()
	# Open ground takes every zoo toy.
	var x := -36.0
	for kind in ZOO_KINDS:
		eq(m.validate(kind, "zoo", x, 22.0), "", "%s on open zoo ground" % kind)
		x += 3.0
	# No Wishing Tree in the zoo: the town's tree spot is open savanna ground here.
	eq(m.validate("zoo_ball", "zoo", TownModel.WISHING_TREE.x, TownModel.WISHING_TREE.y), "", "the Wishing Tree is the town's, not the zoo's")
	eq(m.validate("zoo_ball", "town", TownModel.WISHING_TREE.x, TownModel.WISHING_TREE.y), TownModel.ERR_ZOO_ONLY, "a zoo toy is refused in town, and told why")
	eq(m.validate("zoo_ball", "i1:0:0", 0, 0), TownModel.ERR_NO_HOUSE, "and in a room that is not there")
	# The map's limits are the zoo's (84 x 64 m), not the town's or a room's.
	eq(m.validate("zoo_ball", "zoo", 40.0, 0.0), "", "the zoo is wider than the town")
	eq(m.validate("zoo_ball", "zoo", 0.0, 31.9), TownModel.ERR_EDGE, "the zoo's own edge (south)")
	eq(m.validate("zoo_ball", "zoo", 41.9, 0.0), TownModel.ERR_EDGE, "the zoo's own edge (east)")
	# Blocked ground: the same ground a child cannot walk on (ZooMap.blocked_for_child).
	var blocked := {"Lion Sun Rock": Vector2(0.0, -15.0), "Lion Crag": Vector2(0.0, -27.0), "Splash pool": Vector2(-30.0, 0.0),
		"Savanna waterhole": Vector2(5.0, 2.5), "Tram at the station": ZooMap.STATION, "Monkey ring strip": Vector2(23.5, -18.0), "an acacia": Vector2(-8.0, 0.5)}
	for what in blocked:
		var p: Vector2 = blocked[what]
		ok(ZooMap.blocked_for_child(p), "(the map says %s is blocked)" % what)
		eq(m.validate("zoo_ball", "zoo", p.x, p.y), TownModel.ERR_ZOO_BLOCKED, "no toy on %s" % what)
	# Every position the map blocks is refused, every one it does not is accepted (sampled over the whole zoo).
	var refused := 0
	var taken := 0
	for ix in range(-40, 41, 4):
		for iz in range(-30, 31, 4):
			var p := Vector2(ix, iz)
			var err: String = m.validate("zoo_ball", "zoo", p.x, p.y)
			if ZooMap.blocked_for_child(p):
				if err != "":
					refused += 1
				else:
					ok(false, "a blocked point %s was accepted" % p)
			elif err == "":
				taken += 1
			else:
				ok(false, "an open point %s was refused: %s" % [p, err])
	ok(refused > 20 and taken > 100, "the sample sees both blocked (%d) and open (%d) ground" % [refused, taken])
	# Overlap and the toys' own rules work as outdoors.
	var a := _put(m, "zoo_box", "zoo", -30.0, 22.0)
	eq(m.place("zoo_box", "zoo", -30.4, 22.0, 0).get("error"), TownModel.ERR_OVERLAP, "two boxes cannot overlap")
	ok(m.place("zoo_box", "zoo", -28.0, 22.0, 0)["ok"], "a box beside it is fine")
	ok(m.move(a, -30.0, 24.0, 2)["ok"], "a toy can be moved and turned")
	eq(m.move(a, 0.0, -15.0, 0).get("error"), TownModel.ERR_ZOO_BLOCKED, "but not onto the rock")
	eq(m.items[a]["z"], 24.0, "and stays where it was")
	ok(m.check("zoo_ball", "zoo", -20.0, 22.0, 0) == "" and m.check("zoo_ball", "zoo", 0.0, -15.0, 0) == TownModel.ERR_ZOO_BLOCKED, "check() agrees (clearance is an outdoor rule here)")
	# A free spot near a blocked one is found, and is itself valid.
	var near = m.find_free_spot("zoo_ball", "zoo", Vector2(0.0, -15.0))
	ok(near != null and m.check("zoo_ball", "zoo", near.x, near.y, 0) == "", "a free spot near the rock is valid")
	# Picnic things are fine on open ground; presents and "On display" are not for the zoo.
	var bench := _put(m, "bench", "zoo", -20.0, 24.0)
	ok(m.wrap(bench, "p1", "Sunny", "", 0).get("ok", true) == false, "no presents in the zoo")
	ok(not m.set_display("zoo", true, "p1", "Sunny") and not m.display.has("zoo"), "no 'On display' in the zoo")
	eq(m.place("cottage", "zoo", -30.0, 20.0, 0).get("error"), TownModel.ERR_NOT_ZOO, "a cottage is not a zoo thing")
	eq(m.place("chair", "zoo", -30.0, 20.0, 0).get("error"), TownModel.ERR_NOT_ZOO, "nor is a chair, though rooms and town take it")
	# Removing and undoing work as everywhere.
	var gone: Dictionary = m.remove(bench)
	ok(gone["ok"] and not m.items.has(bench), "a picnic bench is put away")
	ok(m.restore(gone["removed"])["ok"] and m.items.has(bench), "and comes back with undo")
	# A town and a zoo do not share their counts or their walls.
	eq(m.items_in("town").size(), 0, "nothing leaked into the town")


func test_zoo_cap_and_loading() -> void:
	var m := TownModel.new()
	var n := 0
	var ids := []
	for iz in range(0, 10):
		for ix in range(0, 9):
			if n >= TownModel.MAX_ZOO_ITEMS:
				break
			var r: Dictionary = m.place("zoo_ball", "zoo", LAWN.position.x + 1.0 + ix * 1.8, LAWN.position.y + 1.0 + iz * 0.9, 0)
			ok(r["ok"], "ball %d: %s" % [n, r.get("error", "")])
			if r["ok"]:
				ids.append(r["item"]["id"])
				n += 1
	eq(m.items_in("zoo").size(), 80, "eighty things fit")
	eq(m.place("zoo_ball", "zoo", -37.0, 28.0, 0).get("error"), TownModel.ERR_ZOO_FULL, "the 81st is refused")
	eq(m.place("bench", "zoo", -37.0, 28.0, 0).get("error"), TownModel.ERR_ZOO_FULL, "for any kind")
	ok(m.move(ids[3], -37.0, 28.0, 0)["ok"], "moving a thing in a full zoo is fine")
	ok(m.remove(ids[0])["ok"] and m.place("zoo_ball", "zoo", -37.5, 28.2, 0)["ok"], "putting one away makes room")
	# The zoo's cap is its own: the town and the rooms are unaffected, and so are theirs.
	ok(m.place("tree", "town", 5, 5, 0)["ok"], "the town takes things while the zoo is full")
	eq(m.items_in("zoo").size(), 80, "still eighty")
	# A save brings them all back; a save with too many (tampered) keeps the first 80 and nothing breaks.
	var back := _loaded(m.to_dict())
	eq(_sigs(_zoo_items(back)), _sigs(_zoo_items(m)), "all eighty come back")
	var d: Dictionary = _via_json(m.to_dict())
	for i in 10:
		d["items"].append({"id": "i%d" % (900 + i), "kind": "zoo_ball", "space": "zoo", "x": -37.0 + i * 0.2, "z": 28.5, "rot": 0, "color": -1})
	eq(_zoo_items(_loaded(d)).size(), 80, "a save past the cap is cut to eighty")
	# Positions are not re-checked on load: a thing a child placed stays, even if the map changes later.
	var odd := _via_json(TownModel.new().to_dict())
	odd["items"] = [{"id": "i1", "kind": "zoo_ball", "space": "zoo", "x": 0.0, "z": -15.0, "rot": 0, "color": -1}]
	eq(_zoo_items(_loaded(odd)).size(), 1, "a toy on ground the map blocks now is kept, nothing a child made is deleted")


func test_zoo_things_not_elsewhere() -> void:
	# A save that puts zoo toys outside the zoo, or town things in the zoo, loses only those.
	var d := _via_json(TownModel.new().to_dict())
	d["items"] = [
		{"id": "i1", "kind": "cottage", "space": "town", "x": -9.0, "z": -6.0, "rot": 1, "color": 2},
		{"id": "i2", "kind": "zoo_ball", "space": "town", "x": 5.0, "z": 5.0, "rot": 0, "color": -1},
		{"id": "i3", "kind": "zoo_box", "space": "i1:0:0", "x": 0.0, "z": 0.0, "rot": 0, "color": -1},
		{"id": "i4", "kind": "chair", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": 0},
		{"id": "i5", "kind": "cottage", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": 2},
		{"id": "i6", "kind": "zoo_ball", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": -1},
		{"id": "i7", "kind": "no_such_kind", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": -1},
		{"id": "i8", "kind": "bench", "space": "zoo", "x": -26.0, "z": 22.0, "rot": 0, "color": 5},
		{"id": "i9", "kind": "tram_stop", "space": "zoo", "x": -22.0, "z": 22.0, "rot": 0, "color": -1},
		{"id": "i10", "kind": "zoo_ball", "space": "nowhere", "x": 0.0, "z": 0.0, "rot": 0, "color": -1}]
	d["next_id"] = 11
	var m := _loaded(d)
	var kept: Array = m.items.keys()
	kept.sort()
	var want := ["i1", "i6", "i8"]
	for id in m.items:
		if m.items[id]["kind"] == "tram_stop":
			want.append(id)   # the one the game adds
	want.sort()
	eq(kept, want, "only the cottage, the ball and the bench in the zoo, and the town's own tram stop, are kept")
	ok(not m.items.has("i9"), "a tram stop in the zoo is not kept")


# ---------------------------------------------------------------- the tram stop

func test_tram_stop_rules() -> void:
	var m: TownModel = TownModel.make_default()
	var stops: Array = m.items.values().filter(func(i): return i["kind"] == "tram_stop")
	eq(stops.size(), 1, "a new town has exactly one tram stop")
	var stop: Dictionary = stops[0]
	eq(stop["space"], "town", "in town")
	eq(m.tram_stop_id(), stop["id"], "tram_stop_id finds it")
	var d: float = Vector2(stop["x"], stop["z"]).distance_to(TownModel.TOWN_SPAWN)
	ok(d >= 4.0 and d <= 6.0, "it stands 4 to 6 m from the arrival point (%.2f m)" % d)
	eq(m.check("tram_stop", "town", stop["x"], stop["z"], stop["rot"], stop["id"]), "", "and is a valid place for it")
	# Exactly one: no second can be placed, restored or loaded.
	ok(not m.place("tram_stop", "town", 15.0, 15.0, 0)["ok"], "a second tram stop cannot be placed")
	eq(m.ensure_tram_stop(), false, "ensure_tram_stop adds nothing when there is one")
	eq(m.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "still one")
	var dup := _via_json(m.to_dict())
	dup["items"].append({"id": "i999", "kind": "tram_stop", "space": "town", "x": 15.0, "z": 15.0, "rot": 0, "color": -1})
	var twice := _loaded(dup)
	eq(twice.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "a save with two keeps one")
	eq(twice.tram_stop_id(), stop["id"], "the older one")
	# Movable, like a cottage.
	var mv: Dictionary = m.move(stop["id"], -12.0, 14.0, 2)
	ok(mv["ok"], "it can be moved and turned: %s" % mv.get("error", ""))
	eq([m.items[stop["id"]]["x"], m.items[stop["id"]]["z"], m.items[stop["id"]]["rot"]], [-12.0, 14.0, 2], "to where it was put")
	# Never put away, never wrapped, in the model and so everywhere.
	var r: Dictionary = m.remove(stop["id"])
	eq(r.get("error"), STAYS, "put away is refused with the kind message")
	ok(not r["ok"] and m.items.has(stop["id"]), "and it is still there")
	var w: Dictionary = m.wrap(stop["id"], "p1", "Sunny", "", 0)
	eq(w.get("error"), STAYS, "wrapping is refused with the same message")
	ok(not w["ok"] and not m.items[stop["id"]].has("gift"), "no gift tag")
	eq(TownModel.ERR_TRAM_STAYS, STAYS, "the constant is the sentence")
	# It is not one of the 300.
	var full: TownModel = TownModel.make_default()
	var placed := 0
	for iz in range(0, 20):
		for ix in range(0, 26):
			if full._count_in("town") >= TownModel.MAX_TOWN_ITEMS:
				break
			var p := Vector2(-24.0 + ix * 1.9, -20.0 + iz * 1.9)
			if full.place("flowers", "town", p.x, p.y, 0)["ok"]:
				placed += 1
	eq(full._count_in("town"), 300, "the town holds 300 things not counting the stop")
	eq(full.items_in("town").size(), 301, "301 items with it")
	eq(full.place("flowers", "town", 23.0, 20.0, 0).get("error"), TownModel.ERR_TOWN_FULL, "the town is full at 300")
	ok(full.tram_stop_id() != "", "and the stop is still there")
	# A full town that lost its stop gets it back (it needs no room in the 300).
	full.items.erase(full.tram_stop_id())
	ok(full.ensure_tram_stop(), "a full town gets its tram stop back")
	eq(full._count_in("town"), 300, "still 300 without it")
	# Zoo toys and the town's stop do not mix in the caps.
	var z: TownModel = TownModel.make_default()
	_put(z, "zoo_ball", "zoo", -30.0, 22.0)
	eq(z._count_in("town"), z.items_in("town").size() - 1, "the stop is the only thing not counted")
	# Every kind of load adds it: a schema-2 save without one, a schema-3 save that lost it.
	var no_stop := _via_json(m.to_dict())
	no_stop["items"] = no_stop["items"].filter(func(i): return i["kind"] != "tram_stop")
	var re := TownModel.new()
	ok(re.from_dict(no_stop), "a schema-3 save without a stop loads")
	ok(re.tram_added and re.tram_stop_id() != "" and re.last_migration.is_empty(), "and gets one (not a migration)")
	var again := _loaded(re.to_dict())
	ok(not again.tram_added, "a town that has one adds none")
	# Not offered, not allowed anywhere else.
	ok(Catalog.get_def("tram_stop")["category"] == "" and not Catalog.allowed_in("tram_stop", "zoo"), "(catalog)")


func test_tram_stop_placement() -> void:
	# An existing town: the stop goes to the free spot nearest the designed one and nothing a child made moves.
	var d := _fixture("town_v1.json")
	# A child's bench on the designed spot (this schema-1 save has its bench on the first spot, (5.5, 8.5); the
	# spot moved into the iPad's first view, so the bench is put on the current spot to keep this case).
	d["items"].append({"id": "i900", "kind": "bench", "space": "town", "x": TownModel.TRAM_STOP_SPOT.x, "z": TownModel.TRAM_STOP_SPOT.y, "rot": 0, "color": 5})
	var before: Array = d["items"].filter(func(i): return i["space"] == "town").map(func(i): return _sig(i))
	var m := _loaded(d)
	ok(m.items.has("i900"), "(the bench on the designed spot loads)")
	var stop: Dictionary = m.items[m.tram_stop_id()]
	var at := Vector2(stop["x"], stop["z"])
	# The bench sits on the designed spot, so the stop is beside it, not on it.
	ok(at.distance_to(TownModel.TRAM_STOP_SPOT) > 0.5 and at.distance_to(TownModel.TRAM_STOP_SPOT) < 4.0, "the stop is near the designed spot, not on the bench (%.2f m)" % at.distance_to(TownModel.TRAM_STOP_SPOT))
	var d_spawn: float = at.distance_to(TownModel.TOWN_SPAWN)
	ok(d_spawn >= 3.0 and d_spawn <= 8.0, "still close to the arrival point (%.2f m)" % d_spawn)
	var after: Array = m.items_in("town").filter(func(i): return i["kind"] != "tram_stop").map(func(i): return _sig(i))
	before.sort()
	after.sort()
	eq(after, before, "nothing in town was moved")
	eq(m.check("tram_stop", "town", at.x, at.y, stop["rot"], stop["id"]), "", "the stop is valid where it is")
	# Surround the designed spot with solid things: the nearest free place is used, within the spiral's reach or the grid.
	var crowded: TownModel = TownModel.new()
	for ix in range(-9, 0, 2):
		for iz in range(3, 12, 2):
			crowded.place("tree", "town", float(ix), float(iz), 0)
	crowded.place("pond", "town", 4.0, 9.0, 0)
	ok(crowded.ensure_tram_stop(), "a crowded town still gets its stop")
	var cs: Dictionary = crowded.items[crowded.tram_stop_id()]
	eq(crowded.check("tram_stop", "town", cs["x"], cs["z"], cs["rot"], cs["id"]), "", "in a valid place")
	# A town with no free ground at all is left as it is (nothing added, nothing broken). The cap would stop a real
	# town well before this, so the pines are put in directly.
	var tight := TownModel.new()
	var pines := 0
	var gx := -25.5
	while gx <= 25.5:
		var gz := -21.5
		while gz <= 21.5:
			pines += 1
			tight.items["i%d" % pines] = {"id": "i%d" % pines, "kind": "pine", "space": "town", "x": gx, "z": gz, "rot": 0, "color": -1}
			gz += 1.9
		gx += 1.9
	tight.next_id = pines + 1
	eq(tight.ensure_tram_stop(), false, "a town with no room gets no stop and nothing breaks")
	eq(tight.tram_stop_id(), "", "and has none")
	eq(tight.items.size(), pines, "with its things as they were")
	# The boarding point is in front of the stop: a floor point, not inside it.
	var board: Variant = TownModel.tram_stop_boarding(m)
	ok(board is Vector2, "boarding is a point")
	var front := TownModel.facing(stop["rot"])
	ok(at.distance_to(board) > 1.4 and (board - at).normalized().dot(front) > 0.99, "in front of the stop, along its facing (%.2f m)" % at.distance_to(board))
	ok(absf(board.x) < TownModel.TOWN_HALF.x and absf(board.y) < TownModel.TOWN_HALF.y, "inside the town")
	eq(TownModel.tram_stop_boarding(TownModel.new()), null, "no stop, no boarding point")
	# A child standing there is not inside anything solid: no item's footprint contains the point.
	for it in m.items_in("town"):
		if Catalog.get_def(it["kind"])["layer"] == "solid":
			ok(board.distance_to(Vector2(it["x"], it["z"])) >= Catalog.get_def(it["kind"])["radius"] + 0.3 or it["id"] == stop["id"], "the boarding point is clear of %s" % it["id"])


func test_tram_stop_door() -> void:
	var m := TownModel.new()
	var id := _put(m, "tram_stop", "town", 0.0, 0.0, 0)   # faces +z
	var door: Vector2 = TownModel.door_point(m.items[id])
	ok(door.distance_to(Vector2(0.0, 1.95)) < 0.001, "the door is 0.55 m beyond the footprint, as a cottage's")
	eq(TownModel.tram_stop_boarding(m), door, "it is the boarding point")
	# Nothing solid may stand on the boarding point (the cottage door rule).
	eq(m.place("tree", "town", door.x, door.y + 0.3, 0).get("error"), TownModel.ERR_DOOR, "a tree in the doorway is refused")
	eq(m.place("bench", "town", door.x + 0.3, door.y + 0.5, 0).get("error"), TownModel.ERR_DOOR, "a bench too")
	ok(m.place("path_stone", "town", door.x, door.y, 0)["ok"], "a stepping stone is flat and fine")
	ok(m.place("tree", "town", 6.0, 6.0, 0)["ok"], "trees elsewhere are fine")
	# Its own door must face open ground.
	var tree: String = _put(m, "tree", "town", 10.0, 0.0)
	eq(m.validate_door("tram_stop", "town", 10.0, -2.2, 0), TownModel.ERR_DOOR, "facing a tree is refused (validate_door)")
	eq(m.check("tram_stop", "town", 10.0, -2.2, 0, id), TownModel.ERR_DOOR, "check says so too")
	eq(m.validate_door("tram_stop", "town", 0.0, 21.0, 0), TownModel.ERR_DOOR, "facing out of the town is refused")
	eq(m.validate_door("tram_stop", "town", 10.0, -2.2, 4, id), "", "turned the other way it is fine")
	var moved: Dictionary = m.move(id, 10.0, -2.2, 0)
	eq(moved.get("error"), TownModel.ERR_DOOR, "moving it so it faces a tree is refused")
	ok(m.move(id, 10.0, -2.2, 4)["ok"], "and fine when turned away")
	ok(m.items.has(tree), "(the tree is still there)")
	eq(TownModel.has_door("cottage"), true, "cottages have a door")
	eq(TownModel.has_door("tram_stop"), true, "and so does the tram stop")
	eq(TownModel.has_door("bench"), false, "a bench has none")
	# The cottage door rule is unchanged.
	var h := TownModel.new()
	var cot := _put(h, "cottage", "town", -9.0, -6.0, 1)
	ok(TownModel.door_point(h.items[cot]).distance_to(Vector2(-9.0, -6.0) + TownModel.facing(1) * (2.3 + 0.55)) < 0.001, "a cottage's door point is as it was")


func test_blueprints() -> void:
	var m: TownModel = TownModel.make_default()
	var stop: Dictionary = m.items[m.tram_stop_id()]
	var near: Vector2 = m.find_free_spot("bench", "town", Vector2(stop["x"] - 4.0, stop["z"] - 4.0), 0)
	_put(m, "bench", "town", near.x, near.y)
	ok(not Blueprints.capturable(stop), "the tram stop is not capturable")
	ok(Blueprints.capturable({"kind": "bench", "space": "town", "id": "i1"}), "(a bench is)")
	ok(not Blueprints.capturable({"kind": "zoo_ball", "space": "zoo", "id": "i1"}), "nothing in the zoo is")
	var bench_id: String = m.items.values().filter(func(i): return i["kind"] == "bench" and Vector2(i["x"], i["z"]).distance_to(Vector2(stop["x"], stop["z"])) > 3.0)[0]["id"]
	var bp: Dictionary = Blueprints.capture(m, bench_id, 12.0)
	ok(bp["pieces"].size() > 0, "a blueprint of the neighbourhood has pieces")
	ok(bp["pieces"].all(func(p): return p["kind"] != "tram_stop"), "but never the tram stop, though it is within reach")
	eq(Blueprints.capture(m, m.tram_stop_id())["pieces"].size(), 0, "a blueprint cannot start from it")
	# Placing one: a tram stop piece is refused, the rest go in.
	var planned := [{"kind": "tram_stop", "x": 14.0, "z": 14.0, "rot": 0, "color": -1}, {"kind": "bench", "x": -14.0, "z": 15.0, "rot": 0, "color": 5}]
	var r: Dictionary = Blueprints.apply(m, "town", planned)
	eq(r["errors"][0], TownModel.ERR_UNKNOWN, "the tram stop piece is refused")
	eq(r["errors"][1], "", "the bench piece goes in")
	eq(m.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "still one stop")
	# Zoo toys do not go into the town or a room through a blueprint; nothing goes into the zoo.
	var z: Dictionary = Blueprints.apply(m, "town", [{"kind": "zoo_ball", "x": 10.0, "z": 16.0, "rot": 0, "color": -1}])
	eq(z["errors"][0], TownModel.ERR_ZOO_ONLY, "a zoo toy piece is refused in town")
	var zz: Dictionary = Blueprints.apply(m, "zoo", [{"kind": "zoo_ball", "x": -30.0, "z": 22.0, "rot": 0, "color": -1}, {"kind": "bench", "x": -26.0, "z": 22.0, "rot": 0, "color": 5}])
	eq(zz["errors"], [TownModel.ERR_NOT_ZOO, TownModel.ERR_NOT_ZOO], "blueprints are not offered in the zoo")
	eq(m.items_in("zoo").size(), 0, "nothing was placed there")
	# The preview works on a copy and does not add or move a stop.
	var prev: Array = Blueprints.preview(m, "town", planned)
	eq(prev[0], TownModel.ERR_UNKNOWN, "the preview refuses it too")
	eq(m.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "and changed nothing")


# ---------------------------------------------------------------- maps

func test_maps_key() -> void:
	var good := {"zoo": {"found": {"lion": {"wave": {"by": ["Sunny", "Sky"], "t": 1700000000}}, "otter": {"splash": {"by": [], "t": 5}}}}}
	eq(TownModel.sanitize_maps(_via_json(good)), good.duplicate(true), "a good key comes back as it was")
	var m := TownModel.new()
	eq(m.to_dict().has("maps"), false, "no maps, no key")
	m.maps = TownModel.sanitize_maps(good)
	eq(m.to_dict()["maps"], good, "saved under maps when there is something")
	eq(_loaded(m.to_dict()).maps, good, "and loaded back")
	# Species and answers the game does not know are kept, as strings.
	var odd := {"zoo": {"found": {"unicorn": {"sparkle": {"by": ["Sunny"], "t": 9}}}}}
	eq(TownModel.sanitize_maps(odd), odd, "unknown species and answers are kept")
	eq(TownModel.sanitize_maps({"jungle": {"found": {"lion": {"wave": {"by": [], "t": 1}}}}}).keys(), ["jungle"], "and unknown maps")
	# Anything of the wrong shape is dropped, never fatal.
	var junk: Array = ["text", 5, 2.5, null, [], [1, 2], true, {}, {"zoo": 5}, {"zoo": "x"}, {"zoo": []}, {"zoo": {}}, {"zoo": {"found": 5}},
		{"zoo": {"found": []}}, {"zoo": {"found": {"lion": 5}}}, {"zoo": {"found": {"lion": []}}}, {"zoo": {"found": {"lion": {"wave": 5}}}},
		{"zoo": {"found": {"lion": {"wave": "x"}}}}, {"zoo": {"found": {"lion": {}}}}, {"zoo": {"found": {"": {"a": {"by": [], "t": 1}}}}},
		{"zoo": {"found": {"lion": {"": {"by": [], "t": 1}}}}}]
	for j in junk:
		var clean: Dictionary = TownModel.sanitize_maps(j)
		eq(clean, {}, "malformed maps %s become nothing" % [j])
	var mixed := {"zoo": {"found": {"lion": {"wave": {"by": ["Sunny", 5, null, ["x"]], "t": "soon"}, "roar": 7, "nod": {"by": "Sunny", "t": -3}}, "bad": 4}}}
	var fixed: Dictionary = TownModel.sanitize_maps(mixed)
	eq(fixed["zoo"]["found"]["lion"]["wave"], {"by": ["Sunny"], "t": 0}, "a bad name and a bad time are repaired")
	eq(fixed["zoo"]["found"]["lion"].keys().size(), 2, "a bad answer is dropped, the others stay")
	eq(fixed["zoo"]["found"]["lion"]["nod"], {"by": [], "t": 0}, "a wrong 'by' and a negative time are repaired")
	ok(not fixed["zoo"]["found"].has("bad"), "a bad species is dropped")
	# Sizes are bounded: nicknames, finders, answers and species.
	var big := {"zoo": {"found": {}}}
	for s in 30:
		big["zoo"]["found"]["species%02d" % s] = {}
		for a in 30:
			big["zoo"]["found"]["species%02d" % s]["answer%02d" % a] = {"by": ["averyveryverylongnickname", "b", "c", "d", "e", "f", "g", "h", "i", "j"], "t": 1}
	var small: Dictionary = TownModel.sanitize_maps(big)
	eq(small["zoo"]["found"].size(), TownModel.MAX_MAP_SPECIES, "species are bounded")
	eq(small["zoo"]["found"]["species00"].size(), TownModel.MAX_MAP_ANSWERS, "answers are bounded")
	var one: Dictionary = small["zoo"]["found"]["species00"]["answer00"]
	ok(one["by"].size() == TownModel.MAX_FINDERS and one["by"][0].length() == 16, "finders are bounded and names are 16 letters at most")
	# In a save: bad maps load as no maps and the town is whole.
	var base: Dictionary = _via_json(TownModel.make_default().to_dict())
	for j in junk:
		var d: Dictionary = base.duplicate(true)
		d["maps"] = j
		var loaded := TownModel.new()
		ok(loaded.from_dict(d), "a save with damaged maps loads (%s)" % [j])
		eq(loaded.maps, {}, "and has none")
		eq(loaded.items.size(), base["items"].size(), "with every item")


# ---------------------------------------------------------------- migrations

func test_migration_v1() -> void:
	var v1 := _fixture("town_v1.json")
	eq(int(v1["schema"]), 1, "(the fixture is a schema-1 save)")
	var m := TownModel.new()
	ok(m.from_dict(_via_json(v1)), "a schema-1 save loads")
	eq(m.last_migration.get("from"), 1, "reported as from 1")
	eq(m.last_migration.get("furniture"), 3, "with its furniture count")
	ok(m.last_migration.get("tram_stop", false), "and that the stop was added")
	eq(m.to_dict()["schema"], 3, "it saves as schema 3")
	# The town is unchanged apart from the stop.
	var town_before: Array = v1["items"].filter(func(i): return i["space"] == "town").map(func(i): return _sig(i))
	var town_after: Array = m.items_in("town").filter(func(i): return i["kind"] != "tram_stop").map(func(i): return _sig(i))
	town_before.sort()
	town_after.sort()
	eq(town_after, town_before, "town contents are untouched")
	eq(m.items_in(TownModel.room_space("i1", 0, 0)).size(), 3, "the old rooms moved into the living room, as before")
	ok(m.evening and m.lanterns.has("tea_party"), "lanterns and evening kept")
	eq(m.maps, {}, "no maps yet")
	eq(_zoo_items(m).size(), 0, "no zoo things")
	var re := _loaded(m.to_dict())
	ok(re.last_migration.is_empty() and re.items == m.items, "the next load is not a migration and changes nothing")


func test_migration_v2() -> void:
	for name in ["town_v2_activities.json", "town_v2_furniture.json"]:
		var v2 := _fixture(name)
		eq(int(v2["schema"]), 2, "(%s is a schema-2 save)" % name)
		var m := TownModel.new()
		ok(m.from_dict(_via_json(v2)), "%s loads" % name)
		eq(m.last_migration.get("from"), 2, "%s is reported as from 2" % name)
		ok(m.last_migration.get("tram_stop", false) and m.tram_added, "%s gets its tram stop" % name)
		eq(m.to_dict()["schema"], 3, "%s saves as schema 3" % name)
		# Every item of the old save is still there, exactly, and the stop is the only new one.
		var old_sigs: Array = _sigs(v2["items"])
		var new_items: Array = m.items.values().filter(func(i): return i["kind"] != "tram_stop")
		eq(_sigs(new_items), old_sigs, "%s: every old item is unchanged" % name)
		eq(m.items.size(), v2["items"].size() + 1, "%s: one item more" % name)
		for e in v2["items"]:
			ok(m.items.has(e["id"]) and m.items[e["id"]]["kind"] == e["kind"], "%s: id %s kept its kind" % [name, e["id"]])
			if e.has("gift"):
				ok(m.items[e["id"]].has("gift") and m.items[e["id"]]["gift"]["to"] == e["gift"]["to"], "%s: the present is still wrapped" % name)
		ok(m.next_id >= int(v2["next_id"]) + 1, "%s: ids keep counting up (%d)" % [name, m.next_id])
		for key in ["lanterns", "roster", "wishes", "hearts", "visits", "photo_ideas", "pets", "cooked", "display", "keepsakes", "weather", "evening"]:
			var a: Variant = m.to_dict()[key]
			var b: Variant = _loaded(m.to_dict()).to_dict()[key]
			ok(a == b, "%s: %s is stable" % [name, key])
		ok(not m.to_dict().has("maps"), "%s: no maps key until there are maps" % name)
		var re := _loaded(m.to_dict())
		ok(re.last_migration.is_empty() and not re.tram_added and re.items == m.items, "%s: the next load changes nothing" % name)
		# The stop stands where a child can use it.
		var stop: Dictionary = m.items[m.tram_stop_id()]
		eq(m.check("tram_stop", "town", stop["x"], stop["z"], stop["rot"], stop["id"]), "", "%s: the stop is valid" % name)
		ok(Vector2(stop["x"], stop["z"]).distance_to(TownModel.TOWN_SPAWN) < 9.0, "%s: and near the arrival point" % name)


# ---------------------------------------------------------------- files, as data

func test_projection_and_old_reader() -> void:
	var m := _zoo_town()
	_put(m, "bench", "town", 9.0, 10.0)
	m.echoes = {"p1": {"nick": "Sunny", "avatar": {}, "space": "zoo", "x": 0.0, "z": 20.0, "ry": 0.0, "emotes": ["wave"], "t": 1, "answers": {}}}
	var main: Dictionary = _via_json(m.to_dict())
	var bak: Dictionary = _via_json(m.to_dict_v2())
	eq(int(main["schema"]), 3, "the main file is schema 3")
	eq(int(bak["schema"]), 2, "the backup is schema 2")
	var base: Dictionary = m.to_dict()
	var from_base: Dictionary = m.to_dict_v2(base)
	eq(_via_json(from_base), bak, "a projection made from a fresh to_dict() is the same")
	eq(int(base["schema"]), 3, "and leaves that dictionary alone")
	ok(base.has("maps") and base["items"].any(func(i): return i["space"] == "zoo"), "(maps and zoo things still there)")
	ok(main.has("maps") and not bak.has("maps"), "no maps in the backup")
	ok(bak["items"].all(func(i): return i["space"] != "zoo" and i["kind"] != "tram_stop"), "no zoo things and no tram stop in the backup")
	ok(not bak.has("echoes"), "and no hello left in the zoo")
	var town_main: Array = main["items"].filter(func(i): return i["space"] != "zoo" and i["kind"] != "tram_stop")
	eq(_sigs(bak["items"]), _sigs(town_main), "every town and room item is in the backup")
	eq(bak["items"].map(func(i): return i["id"]), town_main.map(func(i): return i["id"]), "with its id, in order")
	for key in main:
		if not key in ["schema", "items", "maps", "echoes"]:
			eq(bak.get(key), main[key], "the backup keeps %s" % key)
	eq(bak["next_id"], main["next_id"], "ids never repeat")
	# An app from before the zoo: it refuses the main file and loads the backup with every town item.
	eq(_old_reader(main)["ok"], false, "the frozen schema-2 reader refuses the main file")
	var old: Dictionary = _old_reader(bak)
	ok(old["ok"], "and accepts the backup")
	eq(_sigs(old["items"]), _sigs(town_main), "keeping every town and room item")
	eq(old["items"].size(), bak["items"].size(), "dropping nothing of the town")
	# What the old reader would have done with the zoo's things, had it been shown them: it drops them.
	var raw: Dictionary = main.duplicate(true)
	raw["schema"] = 2
	var lenient: Dictionary = _old_reader(raw)
	eq(lenient["items"].size(), town_main.size(), "(an old reader drops unknown kinds and spaces by itself)")
	# The projection is a faithful old town for the current model too.
	var cur := TownModel.new()
	ok(cur.from_dict(bak), "this app reads the backup")
	eq(cur.last_migration.get("from"), 2, "as a migration")
	eq(_sigs(cur.items.values().filter(func(i): return i["kind"] != "tram_stop")), _sigs(town_main), "with every town item")
	eq(cur.maps, {}, "and no zoo")
	# A town without any zoo: the projection is the main file with schema 2 (and without the stop).
	var plain: TownModel = TownModel.make_default()
	var p3: Dictionary = _via_json(plain.to_dict())
	var p2: Dictionary = _via_json(plain.to_dict_v2())
	eq(p2["items"].size(), p3["items"].size() - 1, "one item fewer: the stop")
	p3["schema"] = 2
	p2["schema"] = 2   # (both numbers came through JSON)
	p3["items"] = p3["items"].filter(func(i): return i["kind"] != "tram_stop")
	eq(p2, p3, "otherwise identical")
	# The projection does not change the model it came from.
	eq(m.to_dict()["schema"], 3, "to_dict_v2 leaves the model alone")
	ok(_zoo_items(m).size() == 8 and m.tram_stop_id() != "" and not m.maps.is_empty(), "and its contents")


func test_sidecar_merge() -> void:
	var m := _zoo_town()
	var side: Dictionary = _via_json(m.to_sidecar())
	eq(int(side["schema"]), 3, "the sidecar is schema 3")
	eq(side.keys().size(), 3, "with items, maps and its schema")
	eq(side["items"].size(), 8, "it holds the zoo's eight things")
	ok(side["items"].all(func(i): return i["space"] == "zoo"), "only the zoo's")
	eq(side["maps"], _via_json(m.maps), "and the maps")
	var empty := TownModel.new().to_sidecar()
	eq([empty["schema"], empty["items"], empty["maps"]], [3, [], {}], "an empty zoo has an empty sidecar")
	# Merging into the town an older app saved (a schema-2 file: no zoo, new ids).
	var town2: Dictionary = _via_json(m.to_dict_v2())
	var up := TownModel.new()
	ok(up.from_dict(town2), "the schema-2 file loads")
	var r: Dictionary = up.merge_sidecar(side)
	eq([r["items"], r["remapped"], r["maps"]], [8, 0, true], "all eight come back, none renumbered, with maps")
	eq(_sigs(_zoo_items(up)), _sigs(_zoo_items(m)), "exactly the same things")
	for id in m.items:
		if m.items[id]["space"] == "zoo":
			ok(up.items.has(id) and up.items[id]["kind"] == m.items[id]["kind"], "%s kept its id" % id)
	eq(up.maps, m.maps, "and the maps")
	ok(up.next_id >= m.next_id - 1, "new ids continue after theirs")
	# Ids that are taken (the older app made new things) are renumbered, nothing is lost.
	var taken := TownModel.new()
	ok(taken.from_dict(town2), "again")
	var zoo_ids: Array = side["items"].map(func(i): return i["id"])
	for id in zoo_ids:
		taken.items[id] = {"id": id, "kind": "bench", "space": "town", "x": -20.0 + zoo_ids.find(id) * 2.0, "z": -15.0, "rot": 0, "color": 5}   # the old app's own
	var before_town := taken.items.size()
	var r2: Dictionary = taken.merge_sidecar(side)
	eq([r2["items"], r2["remapped"]], [8, 8], "all eight come back, every one under a new id")
	eq(taken.items.size(), before_town + 8, "and nothing was overwritten")
	eq(_sigs(_zoo_items(taken)), _sigs(_zoo_items(m)), "the same things")
	var ids: Array = taken.items.keys()
	var distinct := {}
	for id in ids:
		distinct[id] = true
	eq(distinct.size(), ids.size(), "ids are all different")
	for id in zoo_ids:
		eq(taken.items[id]["kind"], "bench", "%s is still the old app's" % id)
	var fresh := taken.place("zoo_ball", "zoo", -37.5, 27.0, 0)
	ok(fresh["ok"] and not zoo_ids.has(fresh["item"]["id"]), "the next new id is free")
	# A merge twice adds the things twice? No: the same sidecar merged again renumbers (ids taken) but the cap holds.
	var capped := TownModel.new()
	ok(capped.from_dict(town2), "capped")
	for i in 3:
		capped.merge_sidecar(side)
	ok(_zoo_items(capped).size() <= 80, "never more than eighty (%d)" % _zoo_items(capped).size())
	# Maps merge: what is already found stays, what is only in the sidecar is added.
	var have := TownModel.new()
	ok(have.from_dict(town2), "maps")
	have.maps = {"zoo": {"found": {"lion": {"wave": {"by": ["Mia"], "t": 77}, "roar": {"by": ["Mia"], "t": 78}}}}}
	have.merge_sidecar(side)
	eq(have.maps["zoo"]["found"]["lion"]["wave"], {"by": ["Mia"], "t": 77}, "an answer found here stays as it is")
	eq(have.maps["zoo"]["found"]["lion"]["roar"]["by"], ["Mia"], "and the others stay")
	ok(have.maps["zoo"]["found"].has("monkey"), "what only the sidecar knew is added")


func test_damaged_parts() -> void:
	var m := _zoo_town()
	var side: Dictionary = _via_json(m.to_sidecar())
	var base := TownModel.new()
	ok(base.from_dict(_via_json(m.to_dict_v2())), "a town to merge into")
	var before: int = base.items.size()
	for bad in ["text", 5, null, [], {}, {"schema": 2, "items": side["items"], "maps": side["maps"]}, {"schema": "3"}, {"schema": 3, "items": "x", "maps": 5}]:
		var t := TownModel.new()
		t.from_dict(_via_json(m.to_dict_v2()))
		var r: Dictionary = t.merge_sidecar(bad)
		eq([r["items"], r["maps"]], [0, false], "a damaged sidecar (%s) changes nothing" % [bad])
		eq(t.items.size(), before, "and drops nothing")
	# Damaged pieces: the good ones come back.
	var mixed := side.duplicate(true)
	mixed["items"] = [5, "x", {"id": "i1"}, {"id": "i2", "kind": "zoo_ball", "space": "town", "x": 1.0, "z": 1.0, "rot": 0, "color": -1},
		{"id": "i3", "kind": "cottage", "space": "zoo", "x": 1.0, "z": 1.0, "rot": 0, "color": 2}, {"id": "i4", "kind": "zoo_ball", "space": "zoo", "x": "a", "z": 1.0, "rot": 0, "color": -1},
		{"id": "i5", "kind": 7, "space": "zoo", "x": 1.0, "z": 1.0, "rot": 0, "color": -1}, side["items"][0], side["items"][1]]
	mixed["maps"] = "junk"
	var t2 := TownModel.new()
	t2.from_dict(_via_json(m.to_dict_v2()))
	var r2: Dictionary = t2.merge_sidecar(mixed)
	eq(r2["items"], 2, "only the two good things come back")
	eq(r2["maps"], false, "damaged maps are dropped")
	eq(t2.maps, {}, "so there are none")
	# A damaged main file's parts: a zoo item with junk fields is dropped on load, the rest stays.
	var d: Dictionary = _via_json(m.to_dict())
	d["items"].append({"id": "i700", "kind": "zoo_ball", "space": "zoo", "x": 1.0})
	d["items"].append(5)
	d["items"].append({"id": "i701", "kind": "zoo_ball", "space": "zoo", "x": -20.0, "z": 22.0, "rot": 99, "color": -1})
	var l := _loaded(d)
	eq(_zoo_items(l).size(), 9, "eight, and the one with a wild turn (made a valid turn); the broken ones are gone")
	eq(l.items["i701"]["rot"], posmod(99, 8), "the turn is made valid")


# ---------------------------------------------------------------- the Apple TV copy

func test_durable_sidecar() -> void:
	var side_a := "user://zoo_save_w1/durable_town_solo.json.maps"
	var main_a := "user://zoo_save_w1/durable_town_solo.json"
	_clean(main_a)
	ok(Durable.files.has("user://town_solo.json.maps") and Durable.files.has("user://town_hosted.json.maps"), "both towns' sidecars are mirrored")
	eq(Durable.files["user://town_solo.json.maps"][2], Durable.SIDECAR_COPY, "within the stated byte budget")
	eq(Durable.SIDECAR_COPY, 24 * 1024, "24 KiB a copy")
	eq(Durable.files["user://town_solo.json.maps"][1], "maps", "of kind maps")
	var m := _zoo_town()
	var text := JSON.stringify(m.to_sidecar(), "\t")
	ok(Durable.valid("maps", text.to_utf8_buffer()), "a real sidecar is valid")
	for bad in ["", "{}", "[]", "not json", JSON.stringify({"schema": 2, "items": [], "maps": {}}), JSON.stringify({"schema": 3, "items": {}, "maps": {}}), JSON.stringify({"schema": 3, "items": [], "maps": []}), JSON.stringify({"schema": 99})]:
		ok(not Durable.valid("maps", bad.to_utf8_buffer()), "not valid: %s" % bad.left(40))
	# A full zoo and a full found log fit their budget, packed as the module stores them.
	var big := TownModel.new()
	var n := 0
	for iz in range(0, 10):
		for ix in range(0, 9):
			if n < 80 and big.place("zoo_ball" if n % 2 == 0 else "hay_bale", "zoo", LAWN.position.x + 1.0 + ix * 1.9, LAWN.position.y + 1.0 + iz * 0.9, n % 8)["ok"]:
				n += 1
	eq(big.items_in("zoo").size(), 80, "eighty things")
	var found := {}
	for s in TownModel.MAX_MAP_SPECIES:
		found["species_%02d" % s] = {}
		for a in TownModel.MAX_MAP_ANSWERS:
			found["species_%02d" % s]["answer_%02d_name" % a] = {"by": ["Nickname%d" % 1, "Nickname2", "Nickname3", "Nickname4", "Nickname5", "Nickname6", "Nickname7", "Nickname8"], "t": 1700000000 + a * 977 + s}
	big.maps = TownModel.sanitize_maps({"zoo": {"found": found}})
	var raw := JSON.stringify(big.to_sidecar(), "\t").to_utf8_buffer()
	var blob: PackedByteArray = Durable.pack(raw)
	ok(blob.size() <= Durable.SIDECAR_COPY, "the biggest sidecar the rules allow packs to %d bytes, within %d" % [blob.size(), Durable.SIDECAR_COPY])
	# A realistic one is a fraction of it.
	var small_blob: PackedByteArray = Durable.pack(text.to_utf8_buffer())
	ok(small_blob.size() < 3 * 1024, "a typical sidecar packs to %d bytes" % small_blob.size())
	# The copy is made, kept when the file goes, brought back, and never made from a bad file.
	var fake := FakeDefaults.new()
	var saved_files: Dictionary = Durable.files
	var saved_backend: Object = Durable.backend
	Durable.backend = fake
	Durable.status = {}
	Durable.files = {main_a: ["test.town_maps_main", "town", 176 * 1024], side_a: ["test.town_maps", "maps", Durable.SIDECAR_COPY]}
	_write(side_a, text)
	eq(Durable.mirror(side_a), "ok", "the sidecar is copied")
	eq(Durable.unpack(fake.get_blob("test.town_maps")), text.to_utf8_buffer(), "and unpacks to the same bytes")
	DirAccess.remove_absolute(side_a)
	eq(Durable.restore(side_a), "restored", "a sidecar the TV deleted comes back")
	eq(FileAccess.get_file_as_string(side_a), text, "exactly")
	eq(Durable.restore(side_a), "kept", "a valid file is kept")
	_write(side_a, "{ damaged")
	eq(Durable.mirror(side_a), "", "a damaged sidecar is never copied")
	eq(Durable.restore(side_a), "restored", "and is replaced from the good copy")
	Durable.files[side_a] = ["test.town_maps", "maps", 64]
	_write(side_a, text)
	eq(Durable.mirror(side_a), "too_big", "a sidecar above its share is refused")
	Durable.files[side_a] = ["test.town_maps", "maps", Durable.SIDECAR_COPY]
	# The town file is still a town the model accepts with the sidecar present (schema 3 main).
	_write(main_a, JSON.stringify(m.to_dict(), "\t"))
	eq(Durable.mirror(main_a), "ok", "the schema-3 town is valid for the TV copy")
	Durable.files = saved_files
	Durable.backend = saved_backend
	Durable.status = {}
	_clean(main_a)


# ---------------------------------------------------------------- the real session: files on disk

## Loads a town as a starting app does, without a frame in between (so the autosave has not run yet).
func _load(path: String) -> void:
	Session._load_town(path)


func _sorted_sigs(items: Array) -> Array:
	var out: Array = items.duplicate()
	out.sort()
	return out


func test_session_files() -> void:
	var path := DIR + "/files_town.json"
	_clean(path)
	await _start(path)
	ok(Session.model.tram_stop_id() != "", "a new solo town has its tram stop")
	for p in [["zoo_ball", -36.0, 22.0], ["hay_bale", -32.0, 22.0], ["bench", -27.0, 22.0], ["zoo_box", -20.0, 20.0]]:
		var r: Dictionary = Session.model.place(p[0], "zoo", p[1], p[2], 0)
		ok(r["ok"], "placed a %s: %s" % [p[0], r.get("error", "")])
	Session.model.maps = {"zoo": {"found": {"lion": {"wave": {"by": ["Sunny"], "t": 1700000000}}}}}
	var town_items: Array = Session.model.items.values().filter(func(i): return i["space"] != "zoo" and i["kind"] != "tram_stop")
	var zoo_now: Array = _zoo_items(Session.model)
	eq(zoo_now.size(), 4, "four zoo things to save")
	ok(Session.save_now(), "the town saves")
	for f in [path, path + ".bak", path + ".maps"]:
		ok(FileAccess.file_exists(f), "%s exists" % f.get_file())
	ok(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".maps.tmp") and not FileAccess.file_exists(path + ".bak.tmp"), "no temp file is left")
	var main: Dictionary = _read(path)
	var bak: Dictionary = _read(path + ".bak")
	var side: Dictionary = _read(path + ".maps")
	eq(int(main["schema"]), 3, "main is schema 3")
	ok(main["items"].any(func(i): return i["kind"] == "tram_stop") and main["items"].any(func(i): return i["space"] == "zoo") and main.has("maps"), "with the stop, the zoo and the maps")
	eq(int(bak["schema"]), 2, ".bak is a schema-2 projection")
	ok(bak["items"].all(func(i): return i["space"] != "zoo" and i["kind"] != "tram_stop") and not bak.has("maps"), "without zoo things, stop or maps")
	eq(_sigs(bak["items"]), _sigs(town_items), "and with every town item")
	eq(int(side["schema"]), 3, ".maps is schema 3")
	eq(_sigs(side["items"]), _sigs(zoo_now), "holding the zoo's things")
	eq(side["maps"], main["maps"], "and the maps")
	eq(_old_reader(main)["ok"], false, "a schema-2 reader refuses the main file")
	eq(_old_reader(bak)["items"].size(), town_items.size(), "and keeps every town item of the backup")
	# A restart reads the main file as it is: nothing is migrated, merged or added.
	_load(path)
	eq(_sigs(_zoo_items(Session.model)), _sigs(zoo_now), "restart: the zoo's things are there")
	ok(Session.model.last_migration.is_empty() and not Session.model.tram_added and not Session.dirty, "restart: nothing migrated, nothing to save")
	eq(Session.model.maps["zoo"]["found"]["lion"]["wave"]["t"], 1700000000, "restart: the found log is there")
	# Saved again with no zoo things at all: the sidecar says so (a downgrade and an upgrade must not bring them back).
	for it in _zoo_items(Session.model):
		Session.model.remove(it["id"])
	Session.model.maps = {}
	ok(Session.save_now(), "saves again")
	var empty: Dictionary = _read(path + ".maps")
	eq([empty["items"], empty["maps"]], [[], {}], "an emptied zoo leaves an empty sidecar")
	_load(path)
	eq(_zoo_items(Session.model).size(), 0, "restart: no zoo things")
	eq(Session.model.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "restart: one stop")
	ok(not Session.model.maps.has("zoo"), "restart: no maps")


func test_session_downgrade_roundtrip() -> void:
	var path := DIR + "/roundtrip_town.json"
	_clean(path)
	await _start(path)
	var placed := {}
	for p in [["zoo_ball", -36.0, 22.0], ["zoo_box", -33.0, 22.0], ["scratching_log", -29.0, 22.0], ["leaf_feeder", -25.0, 22.0], ["picture_board", -21.0, 22.0], ["bench", -37.0, 25.0]]:
		var r: Dictionary = Session.model.place(p[0], "zoo", p[1], p[2], 1)
		ok(r["ok"], "placed %s: %s" % [p[0], r.get("error", "")])
		placed[r["item"]["id"]] = _sig(r["item"])
	Session.model.maps = {"zoo": {"found": {"giraffe": {"nod": {"by": ["Sunny"], "t": 1700000123}}}}}
	var stop_id: String = Session.model.tram_stop_id()
	ok(Session.model.move(stop_id, -12.0, 14.0, 2)["ok"], "the stop is moved")
	var town_sigs: Array = _sigs(Session.model.items.values().filter(func(i): return i["space"] != "zoo" and i["kind"] != "tram_stop"))
	var zoo_sigs: Array = _sorted_sigs(placed.values())
	ok(Session.save_now(), "saved by the new app")
	# DOWNGRADE: an older app finds the main file is schema 3 and refuses it, loads .bak (schema 2), plays, and saves
	# its own schema-2 file as main (and its own backup). It never touches .maps.
	eq(_old_reader(_read(path))["ok"], false, "the older app refuses the main file")
	var old: Dictionary = _old_reader(_read(path + ".bak"))
	ok(old["ok"], "and loads the backup")
	eq(_sigs(old["items"]), town_sigs, "with every town item")
	var old_save: Dictionary = _read(path + ".bak")
	old_save["schema"] = 2
	# It made something new: a bench, with the next id it had.
	old_save["items"].append({"id": "i%d" % int(old_save["next_id"]), "kind": "bench", "space": "town", "x": -15.0, "z": 15.0, "rot": 0, "color": 5})
	old_save["next_id"] = int(old_save["next_id"]) + 1
	_write(path, JSON.stringify(old_save, "\t"))
	DirAccess.copy_absolute(path, path + ".bak")
	# UPGRADE: the new app loads the schema-2 main file and finds the sidecar.
	_load(path)
	eq(Session.model.last_migration.get("from"), 2, "the new app migrates the older app's save")
	var back: Array = _zoo_items(Session.model)
	eq(back.size(), placed.size(), "every zoo thing is back (%d of %d)" % [back.size(), placed.size()])
	eq(_sigs(back), zoo_sigs, "exactly as they were")
	for id in placed:
		ok(Session.model.items.has(id) and Session.model.items[id]["space"] == "zoo", "%s kept its id" % id)
	eq(Session.model.maps["zoo"]["found"]["giraffe"]["nod"]["t"], 1700000123, "the found log is back")
	ok(Session.model.items.values().any(func(i): return i["kind"] == "bench" and i["space"] == "town" and i["x"] == -15.0), "and what the older app made stays")
	eq(Session.model.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "one tram stop")
	ok(Session.dirty, "the town will be saved in the new format")
	ok(Session.save_now(), "saved again")
	eq(int(_read(path)["schema"]), 3, "main is schema 3 again")
	_load(path)
	eq(_sigs(_zoo_items(Session.model)), zoo_sigs, "and a plain restart keeps them")
	# The same, with the older app's new thing taking an id the zoo already uses: the zoo's things come back, one of
	# them under a new id, none lost.
	var again: Dictionary = _read(path + ".bak")
	again["schema"] = 2
	var clash_id: String = placed.keys()[0]
	again["items"].append({"id": clash_id, "kind": "bench", "space": "town", "x": -16.0, "z": 16.0, "rot": 0, "color": 5})
	_write(path, JSON.stringify(again, "\t"))
	_load(path)
	var back2: Array = _zoo_items(Session.model)
	eq(back2.size(), placed.size(), "with a clashing id every zoo thing is still back (%d of %d)" % [back2.size(), placed.size()])
	ok(Session.model.items[clash_id]["kind"] == "bench" and Session.model.items[clash_id]["space"] == "town", "the id belongs to what the older app made")
	eq(_sigs(back2), zoo_sigs, "and the zoo's things are the same")
	# The main file damaged or gone: the backup and the sidecar bring the town and the zoo back.
	ok(Session.save_now(), "saved")
	_write(path, "{ not json at all")
	_load(path)
	eq(_sigs(_zoo_items(Session.model)), zoo_sigs, "a damaged main file: the backup and the sidecar bring everything back")
	eq(Session.model.items.values().filter(func(i): return i["kind"] == "tram_stop").size(), 1, "with a tram stop")
	DirAccess.remove_absolute(path)
	_load(path)
	eq(_sigs(_zoo_items(Session.model)), zoo_sigs, "a missing main file: the same")


func test_session_first_migration_copies() -> void:
	await _start(DIR + "/copies_town.json")
	# A schema-2 file: its untouched original is kept once as .v2, as a schema-1 file is as .v1.
	var path := DIR + "/migrate_town.json"
	_clean(path)
	var v2_text := FileAccess.get_file_as_string(FIXTURES + "town_v2_furniture.json")
	_write(path, v2_text)
	_load(path)
	ok(FileAccess.file_exists(path + ".v2"), "the schema-2 original is kept as .v2")
	eq(FileAccess.get_file_as_string(path + ".v2"), v2_text, "untouched, byte for byte")
	ok(not FileAccess.file_exists(path + ".v1"), "(and no .v1)")
	ok(Session.dirty, "the new format is written soon")
	ok(Session.model.tram_stop_id() != "", "the stop was added")
	ok(Session.save_now(), "saved")
	eq(int(_read(path)["schema"]), 3, "main is schema 3")
	eq(FileAccess.get_file_as_string(path + ".v2"), v2_text, "the original is not touched by the save")
	# A second migration never overwrites it: put another schema-2 file in place and load.
	_write(path, FileAccess.get_file_as_string(FIXTURES + "town_v2_activities.json"))
	_load(path)
	eq(FileAccess.get_file_as_string(path + ".v2"), v2_text, "the first original stays")
	# Schema 1 keeps its own copy.
	var p1 := DIR + "/migrate1_town.json"
	_clean(p1)
	var v1_text := FileAccess.get_file_as_string(FIXTURES + "town_v1.json")
	_write(p1, v1_text)
	_load(p1)
	eq(FileAccess.get_file_as_string(p1 + ".v1"), v1_text, "a schema-1 original is kept as .v1")
	ok(not FileAccess.file_exists(p1 + ".v2"), "and not as .v2")
	eq(Session.model.items_in("i1:0:0").size(), 3, "(and migrated)")
	# A schema-3 file is no migration: no copy, nothing to save.
	var p3 := DIR + "/migrate3_town.json"
	_clean(p3)
	_load(p3)
	ok(Session.save_now(), "a new town saves")
	_load(p3)
	ok(not FileAccess.file_exists(p3 + ".v1") and not FileAccess.file_exists(p3 + ".v2"), "a schema-3 town makes no copy")
	ok(not Session.dirty, "and is not dirty")
	# A damaged sidecar beside a schema-2 file is dropped, not fatal.
	var pd := DIR + "/migrated_damaged.json"
	_clean(pd)
	_write(pd, v2_text)
	_write(pd + ".maps", "{ this is not a sidecar")
	_load(pd)
	ok(Session.model != null and Session.model.items.size() > 20, "a damaged sidecar: the town loads")
	eq(_zoo_items(Session.model).size(), 0, "with no zoo things")
	_write(pd + ".maps", JSON.stringify({"schema": 3, "items": [{"id": "i5000", "kind": "zoo_ball", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": -1}, 7], "maps": "junk"}))
	_load(pd)
	eq(_zoo_items(Session.model).size(), 1, "a sidecar with one good thing and damaged maps: the thing comes back")
	eq(Session.model.maps, {}, "the maps are dropped")
	_write(pd + ".maps", "[1, 2, 3]")
	_load(pd)
	ok(Session.model.items.size() > 20 and _zoo_items(Session.model).size() == 0, "a sidecar that is not an object is ignored")
	# A sidecar beside a schema-3 file is not merged (the main file is the truth).
	_write(pd, JSON.stringify(Session.model.to_dict()))
	_write(pd + ".maps", JSON.stringify({"schema": 3, "items": [{"id": "i5000", "kind": "zoo_ball", "space": "zoo", "x": -30.0, "z": 22.0, "rot": 0, "color": -1}], "maps": {}}))
	_load(pd)
	eq(_zoo_items(Session.model).size(), 0, "a schema-3 main file does not take a stale sidecar")


func test_session_refusals() -> void:
	var path := DIR + "/refusals_town.json"
	_clean(path)
	await _start(path)
	var stop_id: String = Session.model.tram_stop_id()
	ok(stop_id != "", "the tram stop is there")
	var r: Dictionary = await _result(Session.remove(stop_id))
	ok(not r.get("ok", true), "putting the tram stop away is refused")
	eq(r.get("error"), STAYS, "with the kind message")
	ok(Session.model.items.has(stop_id), "and it stays")
	var w: Dictionary = await _result(Session.wrap(stop_id, "", 0))
	ok(not w.get("ok", true), "wrapping it is refused")
	eq(w.get("error"), STAYS, "with the same message")
	ok(not Session.model.items[stop_id].has("gift"), "no tag")
	# Other things are put away as before.
	var bench: String = Session.model.place("bench", "town", 15.0, 12.0, 0)["item"]["id"]
	var rb: Dictionary = await _result(Session.remove(bench))
	ok(rb.get("ok", false), "other things are put away as before: %s" % rb.get("error", ""))
	# A blueprint in the zoo is refused by the authority, even for a child who is there.
	var me: int = Session.my_id
	var before_state: Dictionary = Session.players[me]["state"].duplicate()
	Session.players[me]["state"]["space"] = "zoo"
	var bp: Dictionary = await _result(Session.place_blueprint("zoo", [{"kind": "bench", "x": -30.0, "z": 22.0, "rot": 0, "color": 5}]))
	Session.players[me]["state"] = before_state
	ok(not bp.get("ok", true), "a blueprint in the zoo is refused")
	eq(bp.get("error"), TownModel.ERR_NOT_ZOO, "with the zoo's own message")
	eq(_zoo_items(Session.model).size(), 0, "and places nothing")
