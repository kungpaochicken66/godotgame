## Authoritative shared-town data: items, lanterns and time of day.
##
## Pure logic without scene-tree dependencies, so it runs identically on the
## dedicated server, in solo play and in headless tests. Positions are meters on
## the ground plane. "town" is the outdoor space. Every cottage is three
## stories tall with two rooms per floor; each room is its own space named
## "<cottage id>:<floor>:<room>" (for example "i1:0:0" is the ground-floor
## living room), so furniture, saves and player presence are per room.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")
const Palette := preload("res://scripts/core/palette.gd")

## Save format. 1: one room per cottage (space = cottage id). 2: rooms per floor.
const SCHEMA := 2
## Outdoor area: 52 x 44 m (version 1 was 32 x 28 m; every old position still fits).
const TOWN_HALF := Vector2(26.0, 22.0)
const ROOM_HALF := Vector2(4.0, 3.0)
const WISHING_TREE := Vector2(0.0, -5.0)
const WISHING_TREE_RADIUS := 2.4
const TOWN_SPAWN := Vector2(0.0, 9.0)
## Doorway slots inside every room: floor points just in front of each opening.
## The back-wall slot is the front door on the ground floor (unchanged since v1),
## the way downstairs on upper floors, and the way back in the second rooms.
const ROOM_DOOR := Vector2(2.5, -2.4)
const STAIRS_UP := Vector2(-0.6, -2.4)
const SIDE_DOOR := Vector2(-3.4, 0.3)
const ROOM_SPAWN := Vector2(2.5, -1.4)
const FLOORS := 3
const ROOMS_PER_FLOOR := 2
const ROOM_NAMES := [["Living room", "Kitchen"], ["Bedroom", "Playroom"], ["Attic", "Art studio"]]
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
const ERR_DOORWAY := "Keep doors and stairs clear."
const ERR_TREE := "That spot belongs to the Wishing Tree."
const ERR_ROOM_FULL := "This house is full of things already."
const ERR_TOWN_FULL := "The town is full of things already."
const ERR_GONE := "That item is gone."
const ERR_NO_HOUSE := "That house is gone."
const ERR_NO_FIT := "That does not fit on top."
const ERR_SURFACE_TAKEN := "There is already something on top."
const ERR_NOT_SUPPORT := "That cannot hold things."

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


## Everything inside a cottage, across all of its rooms.
func items_in_house(house: String) -> Array:
	return items.values().filter(func(i): return house_of(i["space"]) == house)


func items_in(space: String) -> Array:
	var out := []
	for item in items.values():
		if item["space"] == space:
			out.append(item)
	return out


func is_space(space: String) -> bool:
	if space == "town":
		return true
	var r := parse_room(space)
	return not r.is_empty() and items.has(r["house"]) and items[r["house"]]["kind"] == "cottage"


static func room_space(house: String, floor: int, room: int) -> String:
	return "%s:%d:%d" % [house, floor, room]


## {"house", "floor", "room"} for a room space, {} for the town or malformed names.
static func parse_room(space: String) -> Dictionary:
	var parts := space.split(":")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {}
	var f := int(parts[1])
	var r := int(parts[2])
	if f < 0 or f >= FLOORS or r < 0 or r >= ROOMS_PER_FLOOR:
		return {}
	return {"house": parts[0], "floor": f, "room": r}


static func house_of(space: String) -> String:
	return parse_room(space).get("house", "")


static func room_name(space: String) -> String:
	var r := parse_room(space)
	return ROOM_NAMES[r["floor"]][r["room"]] if not r.is_empty() else ""


## Ways out of a room: doors between rooms, stairs between floors and the front door.
## Each: {"kind": exit|up|down|room, "at": floor point, "wall": back|left, "target": space, "label": text}.
static func portals(space: String) -> Array:
	var r := parse_room(space)
	if r.is_empty():
		return []
	var h: String = r["house"]
	var f: int = r["floor"]
	var out := []
	if r["room"] == 0:
		if f == 0:
			out.append({"kind": "exit", "at": ROOM_DOOR, "wall": "back", "target": "town", "label": "Go outside"})
		else:
			out.append({"kind": "down", "at": ROOM_DOOR, "wall": "back", "target": room_space(h, f - 1, 0), "label": "Go downstairs"})
		if f < FLOORS - 1:
			out.append({"kind": "up", "at": STAIRS_UP, "wall": "back", "target": room_space(h, f + 1, 0), "label": "Go upstairs"})
		out.append({"kind": "room", "at": SIDE_DOOR, "wall": "left", "target": room_space(h, f, 1), "label": ROOM_NAMES[f][1]})
	else:
		out.append({"kind": "room", "at": ROOM_DOOR, "wall": "back", "target": room_space(h, f, 0), "label": ROOM_NAMES[f][0]})
	return out


## Safe place to stand after arriving in "to" from "from": just inside the matching doorway.
static func arrival(from: String, to: String) -> Vector2:
	for p in portals(to):
		if p["target"] == from:
			return p["at"] + (Vector2(1.0, 0) if p["wall"] == "left" else Vector2(0, 1.0))
	return ROOM_SPAWN


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
	if space != "town" and solid:
		for portal in portals(space):
			if p.distance_to(portal["at"]) < DOOR_CLEARANCE + r:
				return ERR_DOORWAY
	for other in items_in(space):
		if other["id"] == ignore_id or other.has("host"):
			continue   # items on a table top are not on the floor
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


# ---------------------------------------------------------------- support surfaces
# See design/object-scale-and-surfaces.md: a host with a support_surface holds at
# most one tabletop_eligible item, stored as "host": <host id>.

func attachments_of(host_id: String) -> Array:
	return items.values().filter(func(i): return i.get("host", "") == host_id)


## World ground position of a host's support surface center.
func surface_point(host: Dictionary) -> Vector2:
	var local: Vector3 = Catalog.support_surface(host["kind"]).get("local_position", Vector3.ZERO)
	var off := Vector2(local.x, local.z).rotated(-rot_to_radians(host["rot"]))
	return Vector2(host["x"], host["z"]) + off


## "" when an item of this kind may go on that host (ignoring ignore_id itself).
func check_attach(kind: String, host_id: String, ignore_id := "", rot := 0) -> String:
	if not items.has(host_id):
		return ERR_GONE
	var host: Dictionary = items[host_id]
	if host.has("host") or Catalog.support_surface(host["kind"]).is_empty() or host_id == ignore_id:
		return ERR_NOT_SUPPORT
	if not attachments_of(ignore_id).is_empty() and ignore_id != "":
		return ERR_NOT_SUPPORT   # something carrying an item cannot itself go on top
	if not Catalog.fits_on(kind, host["kind"], rot - int(host["rot"])):
		return ERR_NO_FIT
	var surface: Dictionary = Catalog.support_surface(host["kind"])
	var taken := attachments_of(host_id).filter(func(i): return i["id"] != ignore_id).size()
	if taken >= int(surface.get("max_items", 1)):
		return ERR_SURFACE_TAKEN
	return ""


func place(kind: String, space: String, x: float, z: float, rot: int, color := -2, host := "") -> Dictionary:
	x = snap(x)
	z = snap(z)
	rot = posmod(rot, ROT_STEPS)
	var err := ""
	if host != "":
		err = check_attach(kind, host, "", rot)
		if err == "" and items[host]["space"] != space:
			err = ERR_NOT_SUPPORT
		if err == "" and not Catalog.allowed_in(kind, space):
			err = ERR_OUTDOORS if space != "town" else ERR_INDOORS
		if err == "":
			var sp := surface_point(items[host])
			x = snap(sp.x)
			z = snap(sp.y)
	else:
		err = check(kind, space, x, z, rot)
	if err != "":
		return {"ok": false, "error": err}
	var def := Catalog.get_def(kind)
	if color == -2 or def["color"] == -1:
		color = def["color"]
	else:
		color = clampi(color, 0, Palette.PAINT.size() - 1)
	var item := {"id": _new_id(), "kind": kind, "space": space, "x": x, "z": z, "rot": rot, "color": color}
	if host != "":
		item["host"] = host
	items[item["id"]] = item
	return {"ok": true, "item": item.duplicate()}


## Moves an item on the floor (host "") or onto a support surface (host id).
## Anything on top of a moved host follows it. "moved" lists those attachments.
func move(id: String, x: float, z: float, rot: int, host := "") -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	x = snap(x)
	z = snap(z)
	rot = posmod(rot, ROT_STEPS)
	var err := ""
	if host != "":
		err = check_attach(item["kind"], host, id, rot)
		if err == "" and items[host]["space"] != item["space"]:
			err = ERR_NOT_SUPPORT
		if err == "":
			var sp := surface_point(items[host])
			x = snap(sp.x)
			z = snap(sp.y)
	else:
		err = check(item["kind"], item["space"], x, z, rot, id)
	if err != "":
		return {"ok": false, "error": err}
	var old_rot: int = item["rot"]
	item["x"] = x
	item["z"] = z
	item["rot"] = rot
	if host != "":
		item["host"] = host
	else:
		item.erase("host")
	var moved := []
	for att in attachments_of(id):
		var sp := surface_point(item)
		att["x"] = snap(sp.x)
		att["z"] = snap(sp.y)
		att["rot"] = posmod(att["rot"] + rot - old_rot, ROT_STEPS)
		moved.append(att.duplicate())
	return {"ok": true, "item": item.duplicate(), "moved": moved}


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
		removed.append_array(items_in_house(id).map(func(i): return i.duplicate()))
	removed.append_array(attachments_of(id).map(func(i): return i.duplicate()))
	for entry in removed:
		items.erase(entry["id"])
	return {"ok": true, "removed": removed}


## Puts previously removed items back (undo). Items whose spot is now taken are
## skipped; furniture follows its restored cottage.
func restore(entries: Array) -> Dictionary:
	# Restore in dependency order whatever order the entries come in: cottages,
	# then floor items (including tables), then decorations that sit on a table.
	# A decoration can be older than its table, so insertion order is not enough.
	var tiers := [[], [], []]
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has_all(["id", "kind", "space", "x", "z", "rot", "color"]):
			continue
		var tier := 0 if entry["kind"] == "cottage" else (2 if str(entry.get("host", "")) != "" else 1)
		tiers[tier].append(entry)
	var ordered: Array = tiers[0] + tiers[1] + tiers[2]
	var restored := []
	var skipped := []
	var remap := {}
	for i in ordered.size():
		var entry: Dictionary = ordered[i]
		var space: String = entry["space"]
		var room := parse_room(space)
		if not room.is_empty() and remap.has(room["house"]):
			space = room_space(remap[room["house"]], room["floor"], room["room"])
		var host: String = remap.get(entry.get("host", ""), entry.get("host", ""))
		var result := place(entry["kind"], space, entry["x"], entry["z"], int(entry["rot"]), int(entry["color"]), host)
		if not result["ok"] and host != "":
			# The table could not come back: put the decoration on the floor instead, if there is room.
			result = place(entry["kind"], space, entry["x"], entry["z"], int(entry["rot"]), int(entry["color"]))
		if not result["ok"]:
			if entry["kind"] == "cottage":
				# Without its house nothing inside can come back; report all of it.
				for rest in ordered.slice(i):
					skipped.append(rest["id"])
				return {"ok": restored.size() > 0, "error": result["error"], "items": restored, "skipped": skipped}
			skipped.append(entry["id"])
			continue
		# Keep the original id when it is free so other players' references stay valid.
		var item: Dictionary = result["item"]
		if not items.has(entry["id"]):
			items.erase(item["id"])
			item["id"] = entry["id"]
			items[item["id"]] = item.duplicate()
		remap[entry["id"]] = item["id"]
		restored.append(items[item["id"]].duplicate())
	if restored.is_empty():
		return {"ok": false, "error": ERR_OVERLAP, "items": [], "skipped": skipped}
	return {"ok": true, "items": restored, "skipped": skipped}


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
## Version 1 saves are migrated: a cottage's furniture moves into its ground-floor
## living room, and anything that would block the new doorways or stairs is
## nudged to the nearest free spot in the same room. last_migration reports it.
var last_migration := {}

func from_dict(data: Dictionary) -> bool:
	var schema := int(data.get("schema", -1))
	if schema != SCHEMA and schema != 1:
		return false
	items.clear()
	lanterns = {}
	last_migration = {}
	next_id = maxi(1, int(data.get("next_id", 1)))
	var list: Array = data.get("items", [])
	# Cottages first so their furniture finds its space.
	list = list.filter(func(e): return typeof(e) == TYPE_DICTIONARY)
	list.sort_custom(func(a, b): return a.get("kind") == "cottage" and b.get("kind") != "cottage")
	var moved_in := 0
	var hosted := {}   # item id -> saved host id, checked once everything is loaded
	for e in list:
		if not e.has_all(["id", "kind", "space", "x", "z", "rot", "color"]) or not Catalog.has(e["kind"]):
			continue
		var space := str(e["space"])
		if schema == 1 and space != "town":
			space = room_space(space, 0, 0)
			moved_in += 1
		if not is_space(space) or items.has(str(e["id"])):
			continue
		var item := {"id": str(e["id"]), "kind": e["kind"], "space": space, "x": snap(float(e["x"])),
			"z": snap(float(e["z"])), "rot": posmod(int(e["rot"]), ROT_STEPS), "color": int(e["color"])}
		items[item["id"]] = item
		if e.has("host"):
			hosted[item["id"]] = str(e["host"])
		var n := int(item["id"].substr(1))
		next_id = maxi(next_id, n + 1)
	var lit: Dictionary = data.get("lanterns", {})
	for spot in lit:
		lanterns[str(spot)] = {"by": Array(lit[spot].get("by", [])), "t": int(lit[spot].get("t", 0))}
	evening = bool(data.get("evening", false))
	# Re-attach tabletop items. Invalid, missing or doubled hosts leave the item
	# where it was as a floor item: nothing a child made is ever deleted.
	for id in hosted:
		var item: Dictionary = items[id]
		var host: String = hosted[id]
		if items.has(host) and items[host]["space"] == item["space"] and check_attach(item["kind"], host, id, item["rot"]) == "":
			item["host"] = host
			var sp := surface_point(items[host])
			item["x"] = snap(sp.x)
			item["z"] = snap(sp.y)
	if schema == 1:
		last_migration = {"from": 1, "furniture": moved_in, "nudged": _clear_doorways()}
	return true


## Moves solid furniture out of doorway and stair openings. Returns how many moved.
func _clear_doorways() -> int:
	var moved := 0
	for item in items.values():
		if item["space"] == "town" or Catalog.get_def(item["kind"])["layer"] != "solid":
			continue
		var p := Vector2(item["x"], item["z"])
		var blocking := false
		for portal in portals(item["space"]):
			if p.distance_to(portal["at"]) < DOOR_CLEARANCE + Catalog.get_def(item["kind"])["radius"]:
				blocking = true
		if not blocking:
			continue
		items.erase(item["id"])
		var spot = find_free_spot(item["kind"], item["space"], p, item["rot"])
		if spot != null:
			item["x"] = snap(spot.x)
			item["z"] = snap(spot.y)
			moved += 1
		items[item["id"]] = item
	return moved


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
	# The wider countryside added with the larger map: a west grove, an east meadow
	# with a second pond, a north orchard and trails leading out from the center.
	for p in [Vector2(-21, 9), Vector2(-23, 2), Vector2(-20.5, -4.5), Vector2(-23.5, -11), Vector2(-18.5, -17)]:
		add.call("pine", "town", p.x, p.y)
	for p in [Vector2(-19, 14), Vector2(-22.5, 16.5), Vector2(-17.5, 4)]:
		add.call("tree", "town", p.x, p.y)
	for p in [Vector2(-9, -18), Vector2(1, -19), Vector2(11, -18.5), Vector2(20, -17)]:
		add.call("tree", "town", p.x, p.y, 0, 3)
	add.call("pond", "town", 20.0, 12.0)
	for p in [Vector2(10.5, 7.5), Vector2(12.0, 8.6), Vector2(13.6, 9.4), Vector2(15.2, 10.4), Vector2(-7.5, 9.6),
			Vector2(-9.1, 10.4), Vector2(-10.8, 11.0), Vector2(-12.5, 11.4)]:
		add.call("path_stone", "town", p.x, p.y, 0)
	var meadow := [[Vector2(17, 17), 1], [Vector2(22, 18.5), 6], [Vector2(13.5, 16), 3], [Vector2(-13, 18), 2]]
	for b in meadow:
		add.call("flowers", "town", b[0].x, b[0].y, 0, b[1])
	for p in [Vector2(23.5, 3), Vector2(-15.5, -7), Vector2(16, -13)]:
		add.call("bush", "town", p.x, p.y, 0, 3)
	for x in [17.0, 18.4, 19.8]:
		add.call("fence", "town", x, 20.0, 0)
	# Rooms: living room and kitchen downstairs, bedroom and playroom, attic and studio.
	add.call("rug", room_space(home, 0, 0), 0.0, 0.3)
	add.call("plant", room_space(home, 0, 0), -3.4, 2.4)
	add.call("table", room_space(home, 0, 1), 0.5, 0.5)
	add.call("bed", room_space(home, 1, 0), -2.6, -1.8, 0)
	add.call("teddy", room_space(home, 1, 1), 1.5, 1.0)
	add.call("plant", room_space(studio, 0, 0), 3.4, 2.4, 0, 4)
	return m
