## Authoritative shared-town data: items, lanterns and time of day.
##
## Pure logic without scene-tree dependencies, so it runs identically on the
## dedicated server, in solo play and in headless tests. Positions are meters on
## the ground plane. "town" is the outdoor space; every cottage id is also an
## indoor space whose furniture belongs to that cottage.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")
const Palette := preload("res://scripts/core/palette.gd")

const SCHEMA := 1
const TOWN_HALF := Vector2(16.0, 14.0)
const ROOM_HALF := Vector2(4.0, 3.0)
const WISHING_TREE := Vector2(0.0, -5.0)
const WISHING_TREE_RADIUS := 2.4
const TOWN_SPAWN := Vector2(0.0, 9.0)
## Exit door inside every cottage, on the back wall.
const ROOM_DOOR := Vector2(2.5, -2.4)
const ROOM_SPAWN := Vector2(2.5, -1.4)
const DOOR_CLEARANCE := 0.75
const MAX_TOWN_ITEMS := 300
const MAX_ROOM_ITEMS := 40
const ROT_STEPS := 8

const ERR_UNKNOWN := "That item is not in the toy box."
const ERR_OUTDOORS := "That belongs outdoors."
const ERR_INDOORS := "That belongs indoors."
const ERR_EDGE := "Too close to the edge. Move it inward."
const ERR_OVERLAP := "Too close to another item. Leave a little space."
const ERR_DOOR := "Keep the front door clear."
const ERR_TREE := "That spot belongs to the Wishing Tree."
const ERR_ROOM_FULL := "This house is full of things already."
const ERR_TOWN_FULL := "The town is full of things already."
const ERR_GONE := "That item is gone."
const ERR_NO_HOUSE := "That house is gone."

var items := {}            # id -> item dictionary
var lanterns := {}         # spot kind -> {"by": [nicknames], "t": unix seconds}
var evening := false
var next_id := 1


# ---------------------------------------------------------------- geometry

static func rot_to_radians(rot: int) -> float:
	return float(posmod(rot, ROT_STEPS)) * TAU / ROT_STEPS


## World-plane direction a cottage door faces. rot 0 faces +z (toward the camera).
static func facing(rot: int) -> Vector2:
	var a := rot_to_radians(rot)
	return Vector2(sin(a), cos(a))


static func door_point(item: Dictionary) -> Vector2:
	var r: float = Catalog.get_def("cottage")["radius"]
	return Vector2(item["x"], item["z"]) + facing(item["rot"]) * (r + 0.55)


static func snap(v: float) -> float:
	return snappedf(v, 0.05)


func items_in(space: String) -> Array:
	var out := []
	for item in items.values():
		if item["space"] == space:
			out.append(item)
	return out


func is_space(space: String) -> bool:
	return space == "town" or (items.has(space) and items[space]["kind"] == "cottage")


## Returns "" when the placement is allowed, otherwise an English message key.
func validate(kind: String, space: String, x: float, z: float, ignore_id := "") -> String:
	if not Catalog.has(kind):
		return ERR_UNKNOWN
	if not is_space(space):
		return ERR_NO_HOUSE
	if not Catalog.allowed_in(kind, space):
		return ERR_OUTDOORS if space != "town" else ERR_INDOORS
	var def := Catalog.get_def(kind)
	var r: float = def["radius"]
	var half := TOWN_HALF if space == "town" else ROOM_HALF
	if absf(x) + r > half.x or absf(z) + r > half.y:
		return ERR_EDGE
	var p := Vector2(x, z)
	if space == "town" and p.distance_to(WISHING_TREE) < WISHING_TREE_RADIUS + r:
		return ERR_TREE
	if ignore_id == "" or not items.has(ignore_id):
		var count := items_in(space).size()
		if space == "town" and count >= MAX_TOWN_ITEMS:
			return ERR_TOWN_FULL
		if space != "town" and count >= MAX_ROOM_ITEMS:
			return ERR_ROOM_FULL
	var solid: bool = def["layer"] == "solid"
	if space != "town" and solid and p.distance_to(ROOM_DOOR) < DOOR_CLEARANCE + r:
		return ERR_DOOR
	for other in items_in(space):
		if other["id"] == ignore_id:
			continue
		var odef := Catalog.get_def(other["kind"])
		var op := Vector2(other["x"], other["z"])
		if odef["layer"] == def["layer"] and p.distance_to(op) < r + odef["radius"]:
			return ERR_OVERLAP
		# Nothing solid may block a cottage door, and a cottage may not face into something.
		if solid and other["kind"] == "cottage" and p.distance_to(door_point(other)) < DOOR_CLEARANCE + r:
			return ERR_DOOR
	return ""


## Extra check for cottages: their own door must face open ground.
func validate_door(item_kind: String, space: String, x: float, z: float, rot: int, ignore_id := "") -> String:
	if item_kind != "cottage":
		return ""
	var door: Vector2 = Vector2(x, z) + facing(rot) * (Catalog.get_def("cottage")["radius"] + 0.55)
	if absf(door.x) + DOOR_CLEARANCE > TOWN_HALF.x or absf(door.y) + DOOR_CLEARANCE > TOWN_HALF.y:
		return ERR_DOOR
	for other in items_in(space):
		if other["id"] == ignore_id or Catalog.get_def(other["kind"])["layer"] != "solid":
			continue
		if door.distance_to(Vector2(other["x"], other["z"])) < DOOR_CLEARANCE + Catalog.get_def(other["kind"])["radius"]:
			return ERR_DOOR
	return ""


func check(kind: String, space: String, x: float, z: float, rot: int, ignore_id := "") -> String:
	var err := validate(kind, space, x, z, ignore_id)
	return err if err != "" else validate_door(kind, space, x, z, rot, ignore_id)


# ---------------------------------------------------------------- operations

func _new_id() -> String:
	var id := "i%d" % next_id
	next_id += 1
	return id


func place(kind: String, space: String, x: float, z: float, rot: int, color := -2) -> Dictionary:
	x = snap(x)
	z = snap(z)
	rot = posmod(rot, ROT_STEPS)
	var err := check(kind, space, x, z, rot)
	if err != "":
		return {"ok": false, "error": err}
	var def := Catalog.get_def(kind)
	if color == -2 or def["color"] == -1:
		color = def["color"]
	else:
		color = clampi(color, 0, Palette.PAINT.size() - 1)
	var item := {"id": _new_id(), "kind": kind, "space": space, "x": x, "z": z, "rot": rot, "color": color}
	items[item["id"]] = item
	return {"ok": true, "item": item.duplicate()}


func move(id: String, x: float, z: float, rot: int) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	x = snap(x)
	z = snap(z)
	rot = posmod(rot, ROT_STEPS)
	var err := check(item["kind"], item["space"], x, z, rot, id)
	if err != "":
		return {"ok": false, "error": err}
	item["x"] = x
	item["z"] = z
	item["rot"] = rot
	return {"ok": true, "item": item.duplicate()}


func paint(id: String, color: int) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	if Catalog.get_def(item["kind"])["color"] == -1:
		return {"ok": false, "error": ERR_UNKNOWN}
	item["color"] = clampi(color, 0, Palette.PAINT.size() - 1)
	return {"ok": true, "item": item.duplicate()}


## Removing a cottage packs away its furniture too; all removed items are
## returned (cottage first) so the action can be undone.
func remove(id: String) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var removed := [items[id].duplicate()]
	if items[id]["kind"] == "cottage":
		for inner in items_in(id):
			removed.append(inner.duplicate())
	for entry in removed:
		items.erase(entry["id"])
	return {"ok": true, "removed": removed}


## Puts previously removed items back (undo). Items whose spot is now taken are
## skipped; furniture follows its restored cottage.
func restore(entries: Array) -> Dictionary:
	var restored := []
	var remap := {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has_all(["id", "kind", "space", "x", "z", "rot", "color"]):
			continue
		var space: String = remap.get(entry["space"], entry["space"])
		var result := place(entry["kind"], space, entry["x"], entry["z"], int(entry["rot"]), int(entry["color"]))
		if not result["ok"]:
			if entry["kind"] == "cottage":
				return {"ok": restored.size() > 0, "error": result["error"], "items": restored}
			continue
		# Keep the original id when it is free so other players' references stay valid.
		var item: Dictionary = result["item"]
		if not items.has(entry["id"]):
			items.erase(item["id"])
			item["id"] = entry["id"]
			items[item["id"]] = item.duplicate()
		remap[entry["id"]] = item["id"]
		restored.append(item)
	if restored.is_empty():
		return {"ok": false, "error": ERR_OVERLAP, "items": []}
	return {"ok": true, "items": restored}


## Free spot near a point, searched in a spiral, for new items and spawning.
func find_free_spot(kind: String, space: String, near: Vector2, rot := 0) -> Variant:
	for ring in range(0, 14):
		var steps := maxi(1, ring * 6)
		for s in steps:
			var a := TAU * s / steps
			var p := near + Vector2(cos(a), sin(a)) * ring * 0.6
			if check(kind, space, snap(p.x), snap(p.y), rot) == "":
				return Vector2(snap(p.x), snap(p.y))
	return null


# ---------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	var list := items.values().duplicate(true)
	list.sort_custom(func(a, b): return int(a["id"].substr(1)) < int(b["id"].substr(1)))
	return {"schema": SCHEMA, "next_id": next_id, "items": list, "lanterns": lanterns.duplicate(true), "evening": evening}


## Loads a save, dropping anything malformed instead of failing the whole town.
func from_dict(data: Dictionary) -> bool:
	if int(data.get("schema", -1)) != SCHEMA:
		return false
	items.clear()
	lanterns = {}
	next_id = maxi(1, int(data.get("next_id", 1)))
	var list: Array = data.get("items", [])
	# Cottages first so their furniture finds its space.
	list = list.filter(func(e): return typeof(e) == TYPE_DICTIONARY)
	list.sort_custom(func(a, b): return a.get("kind") == "cottage" and b.get("kind") != "cottage")
	for e in list:
		if not e.has_all(["id", "kind", "space", "x", "z", "rot", "color"]) or not Catalog.has(e["kind"]):
			continue
		if not is_space(e["space"]) or items.has(e["id"]):
			continue
		var item := {"id": str(e["id"]), "kind": e["kind"], "space": str(e["space"]), "x": snap(float(e["x"])),
			"z": snap(float(e["z"])), "rot": posmod(int(e["rot"]), ROT_STEPS), "color": int(e["color"])}
		items[item["id"]] = item
		var n := int(item["id"].substr(1))
		next_id = maxi(next_id, n + 1)
	var lit: Dictionary = data.get("lanterns", {})
	for spot in lit:
		lanterns[str(spot)] = {"by": Array(lit[spot].get("by", [])), "t": int(lit[spot].get("t", 0))}
	evening = bool(data.get("evening", false))
	return true


# ---------------------------------------------------------------- default town

static func make_default():
	var m = load("res://scripts/core/town_model.gd").new()
	var add := func(kind: String, space: String, x: float, z: float, rot := 0, color := -2) -> String:
		var r: Dictionary = m.place(kind, space, x, z, rot, color)
		assert(r["ok"], "Default town item rejected: %s %s" % [kind, r.get("error")])
		return r["item"]["id"]
	var home: String = add.call("cottage", "town", -9.0, -6.0, 1, 2)
	var studio: String = add.call("cottage", "town", 8.5, -9.0, 0, 4)
	add.call("pond", "town", 8.0, 3.5)
	# A gentle stepping-stone path from the spawn point toward the Wishing Tree and homes.
	for p in [Vector2(0, 6.4), Vector2(0.3, 5.0), Vector2(0, 3.6), Vector2(-0.4, 2.2), Vector2(-2.0, 0.6),
			Vector2(-3.5, -1.0), Vector2(-5.0, -2.6), Vector2(2.3, 1.2), Vector2(3.8, -0.4), Vector2(5.3, -2.0), Vector2(6.8, -3.6)]:
		add.call("path_stone", "town", p.x, p.y, 0)
	for p in [Vector2(-13, 6), Vector2(13.5, -3), Vector2(-4.5, -11.5), Vector2(13.5, 10.5), Vector2(-14, -11)]:
		add.call("tree", "town", p.x, p.y)
	add.call("tree", "town", 3.5, -12.0, 0, 3)
	add.call("pine", "town", -14.5, -2.5)
	add.call("pine", "town", 14.5, -11.5)
	var blooms := [[Vector2(-6.2, -1.5), 3], [Vector2(-11.5, -1.8), 1], [Vector2(-7.2, 1.0), 6]]
	for b in blooms:
		add.call("flowers", "town", b[0].x, b[0].y, 0, b[1])
	add.call("bush", "town", -12.5, 1.5)
	add.call("bush", "town", 11.5, -6.5, 0, 6)
	add.call("swing", "town", 12.0, -1.0, 0)
	add.call("bench", "town", 4.0, 6.5, 0)
	add.call("lamp_post", "town", -3.0, 6.5)
	add.call("rug", home, 0.0, 0.3)
	add.call("bed", home, -2.6, -1.8, 0)
	add.call("plant", home, -3.4, 2.4)
	add.call("plant", studio, 3.4, 2.4, 0, 4)
	return m
