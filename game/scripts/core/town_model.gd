## Authoritative shared-town data: items, lanterns and time of day.
##
## Pure logic without scene-tree dependencies, so it runs identically on the
## dedicated server, in solo play and in headless tests. Positions are meters on
## the ground plane. "town" is the outdoor space. Every cottage is three
## stories tall with two rooms per floor; each room is its own space named
## "<cottage id>:<floor>:<room>" (for example "i1:0:0" is the ground-floor
## living room), so furniture, saves and player presence are per room.
extends RefCounted

const PetRules := preload("res://scripts/core/pets.gd")
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
## Labels only (rooms are keyed by floor and number, so renaming keeps saves).
## Code-built r7 kinds replaced by the modeled p002 items (design/pets-rooms-assets.md):
## a town saved with the old kinds loads with the new ones.
const KIND_ALIASES := {"cooking_pot": "kitchen_pot", "frying_pan": "kitchen_pan_set", "utensil_crock": "kitchen_utensil_crock",
	"plate_stack": "kitchen_plate_rack", "rice_sack": "kitchen_rice_sack", "egg_basket": "kitchen_egg_basket",
	"veggie_basket": "kitchen_veg_basket", "dish_rice": "dish_rice_bowl", "dish_soup": "dish_veg_soup", "dish_egg": "dish_fried_egg",
	"dish_omelette": "dish_rice_meal", "game_tv": "game_tv_stand", "game_console": "game_console_set", "game_tablet": "game_handheld_dock",
	"bean_bag": "game_bean_bag", "game_shelf": "game_storage_cubby", "gaming_desk": "table"}
const ROOM_NAMES := [["Living room", "Kitchen"], ["Bedroom", "Game room"], ["Pet room", "Art studio"]]
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
const ERR_WALL_OPENING := "That part of the wall is a door or window."
const ERR_HEADROOM := "Not enough room under the ceiling there."
const ERR_WALL_CLEARANCE := "Not enough room in front of the wall there."
const ERR_NOT_GIFT := "That is not a present."
const ERR_GIFT_FOR_OTHER := "That present is for someone else."
const ERR_CANNOT_WRAP := "That cannot be wrapped."
const ERR_TOO_MANY_GIFTS := "That doorstep is full of presents already."
const ERR_TRAIL_FULL := "A trail has five signs at most."
const MAX_GIFTS_PER_RECIPIENT := 3
const CEILING_Y := 2.8
## Space kept between a hanging item and anything standing under it.
const HEADROOM_GAP := 0.05
## Space kept between a wall item's lowest point and anything standing in front of it.
const WALL_GAP := 0.05
## The left wall's window (along-wall center z, half width) must stay uncovered.
const LEFT_WINDOW := Vector2(-1.8, 0.6)
const WEATHERS := ["sunny", "rain", "autumn", "snow"]
const GROWTH_MAX := 3
## Rain puddles (decoration only, never block placement); Pip splashes in them.
const PUDDLES := [Vector2(-6.5, 12.5), Vector2(5.5, 13.0), Vector2(13.0, 0.5), Vector2(-14.0, 9.0), Vector2(-3.0, -15.0)]
## Half size of a drawn puddle (an ellipse, wider along x).
const PUDDLE_HALF := Vector2(0.9, 0.63)
## Items with a look a child picks (the snowman's face): kind -> number of variants.
const VARIANTS := {"snowman": 3, "trail_sign": 4, "track_switch": 2}
## Trail signs are numbered 1..MAX_TRAIL_SIGNS in the order they are placed (F06).
const MAX_TRAIL_SIGNS := 5
## A music box's tune (F08): one 8-step bitmask per sound (bell, drum, chime, bass).
const MUSIC_ROWS := 4
const MUSIC_STEPS := 8
const MUSIC_DEFAULT := [17, 85, 64, 1]


## The puddle a point stands in, or -1 (children splash, design F04).
static func puddle_at(p: Vector2) -> int:
	for i in PUDDLES.size():
		var d: Vector2 = (p - PUDDLES[i]) / PUDDLE_HALF
		if d.length_squared() < 1.0:
			return i
	return -1

var items := {}            # id -> item dictionary
var lanterns := {}         # spot kind -> {"by": [nicknames], "t": unix seconds}
var evening := false
var next_id := 1
# Activities (design/playfulness-proposals.md). All optional; none gates the toy box.
var roster := {}           # player id -> {"nick", "color", "seen"}: display only, ids are the identity
var wishes := {"active": {}, "stickers": []}
var weather := "sunny"
var hearts := {}           # room space -> {player id: nick}
var visits := {}           # cottage id -> {player id: nick}
var photo_ideas := {}      # idea id -> {"by": [nicknames], "t": unix seconds}
# Pets, themed rooms and cooking (design/pets-kitchen-photos.md). Optional in saves.
var pets := {}             # player id -> {"pets": [...], "active", "mode", "home"} (see core/pets.gd)
var starter := {}          # room space -> true once its starter set was offered
var cooked := {}           # player id -> number of dishes cooked
# Play ideas (design/playability-8-12.md). Optional in saves.
var display := {}          # space -> {"pid", "nick"}: "On display", others ask before changing it
var keepsakes := []        # [{"kind": "trail", "by": [nicknames], "t"}]: trail keepsake stickers (F06)


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
		if other["id"] == ignore_id or other.has("host") or Catalog.anchor(other["kind"]) != "ground":
			continue   # items on a table top, a wall or the ceiling are not on the floor
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
	if Catalog.anchor(kind) != "ground":
		var slot := mount_slot(kind, x, z)
		return check_mounted(kind, space, slot["x"], slot["z"], ignore_id)
	var err := validate(kind, space, x, z, ignore_id)
	if err == "":
		err = validate_door(kind, space, x, z, rot, ignore_id)
	return err if err != "" else clearance(kind, space, x, z, rot, ignore_id)


# ---------------------------------------------------------------- wall and ceiling anchors
# Wall items hang on a room's back wall (facing +z) or left wall (facing +x);
# ceiling items hang from the ceiling. Neither occupies the floor or blocks walking.

## Where a wall or ceiling item goes for a floor point: x, z, rot and height y. A ceiling item keeps
## the turn it is given (r15: eight 45-degree steps, like floor items; every ceiling rule is a circle,
## so a turn never changes whether it fits); a wall item faces into the room from its wall.
static func mount_slot(kind: String, x: float, z: float, rot := 0) -> Dictionary:
	if Catalog.anchor(kind) == "ceiling":
		return {"x": snap(x), "z": snap(z), "rot": posmod(rot, ROT_STEPS), "y": CEILING_Y}
	var y: float = Catalog.get_def(kind).get("mount_height", 1.5)
	if absf(z + ROOM_HALF.y) <= absf(x + ROOM_HALF.x):
		return {"x": snap(x), "z": -ROOM_HALF.y, "rot": 0, "y": y, "wall": "back"}
	return {"x": -ROOM_HALF.x, "z": snap(z), "rot": 2, "y": y, "wall": "left"}


static func _wall_of(item_x: float, item_z: float) -> String:
	return "back" if absf(item_z + ROOM_HALF.y) < 0.01 else "left"


## How high a standing item reaches (its own height, plus its host's surface and anything on it).
func top_of(kind: String, host := "", carried := []) -> float:
	var base := 0.0
	if host != "" and items.has(host):
		base = Catalog.support_surface(items[host]["kind"]).get("local_position", Vector3.ZERO).y
	var top := base + Catalog.height(kind)
	var surface_y: float = Catalog.support_surface(kind).get("local_position", Vector3.ZERO).y
	for c in carried:
		top = maxf(top, base + surface_y + Catalog.height(c["kind"]))
	return top


## Everything a standing item must keep clear of: hanging items above it and wall items behind it.
func clearance(kind: String, space: String, x: float, z: float, rot: int, ignore_id := "", host := "") -> String:
	var err := headroom(kind, space, x, z, ignore_id, host)
	return err if err != "" else wall_clearance(kind, space, x, z, rot, ignore_id, host)


## Wall items and standing items must not meet (r16; r13 recorded wall items sinking into tall
## furniture). Each side is its real box from the catalog bounds: a wall item is its width along the
## wall by its depth into the room, from its bottom (mount height minus half its height) upward; a
## standing item is its footprint turned by its rot, from the floor (or the table it stands on) up to
## its top. They conflict only if the boxes overlap on the floor plane AND the standing item reaches
## within WALL_GAP of the wall item's bottom or above it, so low furniture under a picture and tall furniture
## beside one are both fine. Checked for wall items (against what stands there) and for standing items
## (against the wall items behind them). Existing saves are not checked on load.
func wall_clearance(kind: String, space: String, x: float, z: float, rot: int, ignore_id := "", host := "") -> String:
	if space == "town" or not is_space(space):
		return ""
	var a := Catalog.anchor(kind)
	if a == "wall":
		var wb := _wall_box(kind, x, z)
		for other in items_in(space):
			if other["id"] == ignore_id or Catalog.anchor(other["kind"]) != "ground":
				continue
			if not _reaches_wall_item(top_of(other["kind"], other.get("host", "")), wb["bottom"]):
				continue
			if _rect_overlaps(wb["rect"], _floor_corners(other["kind"], other["x"], other["z"], other["rot"])):
				return ERR_WALL_CLEARANCE
		return ""
	if a != "ground":
		return ""
	var carried: Array = attachments_of(ignore_id) if ignore_id != "" else []
	var my_top := top_of(kind, host, carried)
	var corners := _floor_corners(kind, x, z, rot)
	for other in items_in(space):
		if other["id"] == ignore_id or Catalog.anchor(other["kind"]) != "wall":
			continue
		var wb := _wall_box(other["kind"], other["x"], other["z"])
		if _reaches_wall_item(my_top, wb["bottom"]) and _rect_overlaps(wb["rect"], corners):
			return ERR_WALL_CLEARANCE
	return ""


## True when a standing item's top comes closer than WALL_GAP to a wall item's lowest point (or above
## it). r16b: r16 compared with bottom + WALL_GAP, which let tops up to 5 cm ABOVE the bottom through
## (real overlap). Exactly WALL_GAP below is still fine; 1 mm absorbs float32 catalog bounds.
static func _reaches_wall_item(top: float, bottom: float) -> bool:
	return top > bottom - WALL_GAP + 0.001


## A wall item's floor-plane rectangle (x, z) and the height of its lowest point.
func _wall_box(kind: String, x: float, z: float) -> Dictionary:
	var b: Vector3 = Catalog.get_def(kind)["bounds"]
	var y: float = mount_slot(kind, x, z)["y"]
	var rect := Rect2(x - b.x * 0.5, -ROOM_HALF.y, b.x, b.z) if _wall_of(x, z) == "back" \
		else Rect2(-ROOM_HALF.x, z - b.x * 0.5, b.z, b.x)
	return {"rect": rect, "bottom": y - b.y * 0.5}


## The four floor-plane corners (x, z) of a standing item's footprint box, turned by rot.
static func _floor_corners(kind: String, x: float, z: float, rot: int) -> Array:
	var b: Vector3 = Catalog.get_def(kind)["bounds"]
	var basis := Basis(Vector3.UP, rot_to_radians(rot))
	var out := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var v := basis * Vector3(c.x * b.x * 0.5, 0, c.y * b.z * 0.5)
		out.append(Vector2(x + v.x, z + v.z))
	return out


## True when an axis-aligned rectangle and a convex quad overlap by more than 1 cm (separating axes).
static func _rect_overlaps(r: Rect2, quad: Array) -> bool:
	var rc := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var axes := [Vector2(1, 0), Vector2(0, 1), (quad[1] - quad[0]).normalized(), (quad[3] - quad[0]).normalized()]
	for ax in axes:
		var a0 := INF
		var a1 := -INF
		var b0 := INF
		var b1 := -INF
		for p in rc:
			a0 = minf(a0, ax.dot(p))
			a1 = maxf(a1, ax.dot(p))
		for p in quad:
			b0 = minf(b0, ax.dot(p))
			b1 = maxf(b1, ax.dot(p))
		if minf(a1, b1) - maxf(a0, b0) <= 0.01:
			return false
	return true


## Hanging items and standing items must not meet (r2: pendants hang down to 0.87 m below the 2.8 m
## ceiling; the garden pavilion stands 2.81 m). For a ceiling kind, checks the standing items under it;
## for a standing kind (on the floor or on a host at host_xz), checks the ceiling items above it.
func headroom(kind: String, space: String, x: float, z: float, ignore_id := "", host := "") -> String:
	if space == "town" or not is_space(space):
		return ""
	var p := Vector2(x, z)
	if Catalog.anchor(kind) == "ceiling":
		var b: Vector3 = Catalog.get_def(kind)["bounds"]
		var bottom := CEILING_Y - b.y
		for other in items_in(space):
			if other["id"] == ignore_id or Catalog.anchor(other["kind"]) != "ground":
				continue
			var top := top_of(other["kind"], other.get("host", ""))
			var reach: float = Catalog.get_def(other["kind"])["radius"] + maxf(b.x, b.z) * 0.5
			if top > bottom - HEADROOM_GAP and p.distance_to(Vector2(other["x"], other["z"])) < reach:
				return ERR_HEADROOM
		return ""
	if Catalog.anchor(kind) != "ground":
		return ""
	var carried: Array = attachments_of(ignore_id) if ignore_id != "" else []
	var my_top := top_of(kind, host, carried)
	for other in items_in(space):
		if other["id"] == ignore_id or Catalog.anchor(other["kind"]) != "ceiling":
			continue
		var ob: Vector3 = Catalog.get_def(other["kind"])["bounds"]
		var reach: float = Catalog.get_def(kind)["radius"] + maxf(ob.x, ob.z) * 0.5
		if my_top > CEILING_Y - ob.y - HEADROOM_GAP and p.distance_to(Vector2(other["x"], other["z"])) < reach:
			return ERR_HEADROOM
	return ""


func check_mounted(kind: String, space: String, x: float, z: float, ignore_id := "") -> String:
	if not Catalog.has(kind):
		return ERR_UNKNOWN
	if not is_space(space):
		return ERR_NO_HOUSE
	if space == "town":
		return ERR_INDOORS
	if (ignore_id == "" or not items.has(ignore_id)) and items_in(space).size() >= MAX_ROOM_ITEMS:
		return ERR_ROOM_FULL
	var b: Vector3 = Catalog.get_def(kind)["bounds"]
	if Catalog.anchor(kind) == "ceiling":
		var r := maxf(b.x, b.z) * 0.5
		if absf(x) + r > ROOM_HALF.x or absf(z) + r > ROOM_HALF.y:
			return ERR_EDGE
		for other in items_in(space):
			if other["id"] != ignore_id and Catalog.anchor(other["kind"]) == "ceiling":
				var ob: Vector3 = Catalog.get_def(other["kind"])["bounds"]
				if Vector2(x, z).distance_to(Vector2(other["x"], other["z"])) < r + maxf(ob.x, ob.z) * 0.5:
					return ERR_OVERLAP
		return headroom(kind, space, x, z, ignore_id)
	var wall := _wall_of(x, z)
	var along := x if wall == "back" else z
	var half: float = ROOM_HALF.x if wall == "back" else ROOM_HALF.y
	var w := b.x * 0.5
	if absf(along) + w > half - 0.1:
		return ERR_EDGE
	var openings := []
	for p in portals(space):
		if p["wall"] == wall:
			openings.append(Vector2(p["at"].x if wall == "back" else p["at"].y, 0.65))
	if wall == "left":
		openings.append(LEFT_WINDOW)
	for o in openings:
		if absf(along - o.x) < w + o.y:
			return ERR_WALL_OPENING
	for other in items_in(space):
		if other["id"] == ignore_id or Catalog.anchor(other["kind"]) != "wall" or _wall_of(other["x"], other["z"]) != wall:
			continue
		var o_along: float = other["x"] if wall == "back" else other["z"]
		if absf(along - o_along) < w + Catalog.get_def(other["kind"])["bounds"].x * 0.5:
			return ERR_OVERLAP
	return wall_clearance(kind, space, x, z, 0, ignore_id)


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
	if Catalog.grid(kind) > 0.0:
		var g := grid_snap(kind, x, z, rot)
		x = g["x"]
		z = g["z"]
		rot = g["rot"]
	var err := ""
	var mount := {}
	if Catalog.anchor(kind) != "ground":
		mount = mount_slot(kind, x, z, rot)
		x = mount["x"]
		z = mount["z"]
		rot = mount["rot"]
		err = check_mounted(kind, space, x, z)
		host = ""
	elif host != "":
		err = check_attach(kind, host, "", rot)
		if err == "" and items[host]["space"] != space:
			err = ERR_NOT_SUPPORT
		if err == "" and not Catalog.allowed_in(kind, space):
			err = ERR_OUTDOORS if space != "town" else ERR_INDOORS
		if err == "":
			var sp := surface_point(items[host])
			x = snap(sp.x)
			z = snap(sp.y)
			err = clearance(kind, space, x, z, rot, "", host)
	else:
		err = check(kind, space, x, z, rot)
	if err == "" and kind == "trail_sign" and free_trail_number() == 0:
		err = ERR_TRAIL_FULL
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
	if not mount.is_empty():
		item["y"] = mount["y"]
	if kind == "garden_bed":
		item["growth"] = 0
	if VARIANTS.has(kind):
		item["variant"] = 0
	if kind == "trail_sign":
		item["num"] = free_trail_number()
	if kind == "music_box":
		item["song"] = MUSIC_DEFAULT.duplicate()
		item["on"] = false
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
	if Catalog.grid(item["kind"]) > 0.0:
		var g := grid_snap(item["kind"], x, z, rot)
		x = g["x"]
		z = g["z"]
		rot = g["rot"]
	var err := ""
	if Catalog.anchor(item["kind"]) != "ground":
		var mount := mount_slot(item["kind"], x, z, rot)
		x = mount["x"]
		z = mount["z"]
		rot = mount["rot"]
		host = ""
		err = check_mounted(item["kind"], item["space"], x, z, id)
	elif host != "":
		err = check_attach(item["kind"], host, id, rot)
		if err == "" and items[host]["space"] != item["space"]:
			err = ERR_NOT_SUPPORT
		if err == "":
			var sp := surface_point(items[host])
			x = snap(sp.x)
			z = snap(sp.y)
			err = clearance(item["kind"], item["space"], x, z, rot, id, host)
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
	if removed[0]["kind"] == "cottage":
		visits.erase(id)
		for space in hearts.keys():
			if house_of(space) == id:
				hearts.erase(space)
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
		if VARIANTS.has(entry["kind"]):
			items[item["id"]]["variant"] = posmod(int(entry.get("variant", 0)), VARIANTS[entry["kind"]])
		_restore_extras(items[item["id"]], entry)
		remap[entry["id"]] = item["id"]
		restored.append(items[item["id"]].duplicate())
	if restored.is_empty():
		return {"ok": false, "error": ERR_OVERLAP, "items": [], "skipped": skipped}
	return {"ok": true, "items": restored, "skipped": skipped}


# ---------------------------------------------------------------- activity operations

## Wrap an item as a present for one player id (or "" for anyone).
func wrap(id: String, from_pid: String, from_nick: String, to_pid: String, paper: int) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	if item.has("gift"):
		return {"ok": false, "error": ERR_CANNOT_WRAP}
	if item["kind"] == "cottage" or item.has("host") or not attachments_of(id).is_empty():
		return {"ok": false, "error": ERR_CANNOT_WRAP}
	var waiting := items.values().filter(func(i): return i.has("gift") and i["gift"]["to"] == to_pid).size()
	if waiting >= MAX_GIFTS_PER_RECIPIENT:
		return {"ok": false, "error": ERR_TOO_MANY_GIFTS}
	item["gift"] = {"to": to_pid, "from": from_pid, "from_nick": from_nick, "paper": clampi(paper, 0, Palette.PAINT.size() - 1)}
	return {"ok": true, "item": item.duplicate(true)}


## Open a present. Only its recipient may (anyone, if it is for anyone).
func unwrap(id: String, pid: String) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	if not item.has("gift"):
		return {"ok": false, "error": ERR_NOT_GIFT}
	if item["gift"]["to"] != "" and item["gift"]["to"] != pid:
		return {"ok": false, "error": ERR_GIFT_FOR_OTHER}
	var gift: Dictionary = item["gift"]
	item.erase("gift")
	return {"ok": true, "item": item.duplicate(true), "gift": gift}


## A garden bed grows one stage (watering or the in-session growth tick).
func grow(id: String) -> Dictionary:
	if not items.has(id) or items[id]["kind"] != "garden_bed":
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	if int(item.get("growth", 0)) >= GROWTH_MAX:
		return {"ok": false, "error": ""}
	item["growth"] = int(item.get("growth", 0)) + 1
	return {"ok": true, "item": item.duplicate(true)}


## Toy track pieces (F02) snap to whole meters and quarter turns.
static func grid_snap(kind: String, x: float, z: float, rot: int) -> Dictionary:
	var g := Catalog.grid(kind)
	return {"x": roundf(x / g) * g, "z": roundf(z / g) * g, "rot": posmod(int(roundf(rot / 2.0)) * 2, ROT_STEPS)}


## The lowest free trail sign number, or 0 when the trail has all its signs.
func free_trail_number() -> int:
	var used := {}
	for it in items_in("town"):
		if it["kind"] == "trail_sign":
			used[int(it.get("num", 0))] = true
	for n in range(1, MAX_TRAIL_SIGNS + 1):
		if not used.has(n):
			return n
	return 0


## Trail signs in walking order (by number, then age).
func trail_signs() -> Array:
	var out := items_in("town").filter(func(i): return i["kind"] == "trail_sign" and not i.has("gift"))
	out.sort_custom(func(a, b): return [int(a.get("num", 0)), int(a["id"].substr(1))] < [int(b.get("num", 0)), int(b["id"].substr(1))])
	return out


## A tune's cells: Array of MUSIC_ROWS ints, each an 8-bit step mask.
static func sanitize_song(v) -> Array:
	var out := MUSIC_DEFAULT.duplicate()
	if typeof(v) == TYPE_ARRAY and v.size() == MUSIC_ROWS:
		for r in MUSIC_ROWS:
			out[r] = clampi(int(v[r]), 0, (1 << MUSIC_STEPS) - 1)
	return out


## Turns one note of a music box on or off.
func toggle_note(id: String, row: int, step: int) -> Dictionary:
	if not items.has(id) or items[id]["kind"] != "music_box" or items[id].has("gift"):
		return {"ok": false, "error": ERR_GONE}
	if row < 0 or row >= MUSIC_ROWS or step < 0 or step >= MUSIC_STEPS:
		return {"ok": false, "error": ERR_UNKNOWN}
	var song: Array = sanitize_song(items[id].get("song"))
	song[row] = song[row] ^ (1 << step)
	items[id]["song"] = song
	return {"ok": true, "item": items[id].duplicate(true)}


func set_music_on(id: String, on: bool) -> Dictionary:
	if not items.has(id) or items[id]["kind"] != "music_box" or items[id].has("gift"):
		return {"ok": false, "error": ERR_GONE}
	items[id]["on"] = on
	return {"ok": true, "item": items[id].duplicate(true)}


## Per-kind fields an undo brings back: a trail sign keeps its number when it is
## still free (else it gets the next free one), a music box keeps its tune.
func _restore_extras(item: Dictionary, entry: Dictionary) -> void:
	if item["kind"] == "trail_sign":
		var want := int(entry.get("num", 0))
		var taken := items_in("town").any(func(i): return i["kind"] == "trail_sign" and i["id"] != item["id"] and int(i.get("num", 0)) == want)
		if want >= 1 and want <= MAX_TRAIL_SIGNS and not taken:
			item["num"] = want
	if item["kind"] == "music_box":
		item["song"] = sanitize_song(entry.get("song"))
		item["on"] = bool(entry.get("on", false))


## The next look of an item with variants (the snowman's face).
func next_variant(id: String) -> Dictionary:
	if not items.has(id) or not VARIANTS.has(items[id]["kind"]) or items[id].has("gift"):
		return {"ok": false, "error": ERR_GONE}
	var item: Dictionary = items[id]
	item["variant"] = (int(item.get("variant", 0)) + 1) % VARIANTS[item["kind"]]
	return {"ok": true, "item": item.duplicate(true)}


## Puts a room or the town square on display (or takes it off). Returns whether it is on display now.
func set_display(space: String, on: bool, pid: String, nick: String) -> bool:
	if not is_space(space):
		return false
	if on:
		display[space] = {"pid": pid.left(64), "nick": nick.left(16)}
	else:
		display.erase(space)
	return display.has(space)


## Display marks without their helpers: helping is temporary and never saved.
func _display_saved() -> Dictionary:
	var out := {}
	for sp in display:
		out[sp] = {"pid": display[sp]["pid"], "nick": display[sp]["nick"]}
	return out


## A friend joined (or left) a "Please help me edit" invitation for this space.
func set_helper(space: String, pid: String, on: bool) -> bool:
	if not display.has(space):
		return false
	var helpers: Array = display[space].get("helpers", [])
	if on and not helpers.has(pid):
		helpers.append(pid.left(64))
	elif not on:
		helpers.erase(pid)
	display[space]["helpers"] = helpers
	return true


## Who put this space on display ({} when it is not). The one who did may change it freely.
func display_by(space: String) -> Dictionary:
	return display.get(space, {})


## Leave or take back your heart sticker in a room. Returns whether it is now there.
func toggle_heart(space: String, pid: String, nick: String) -> bool:
	if parse_room(space).is_empty() or not is_space(space):
		return false
	var room: Dictionary = hearts.get_or_add(space, {})
	if room.has(pid):
		room.erase(pid)
		if room.is_empty():
			hearts.erase(space)
		return false
	room[pid] = nick
	return true


func note_visit(house: String, pid: String, nick: String) -> bool:
	if not items.has(house) or items[house]["kind"] != "cottage":
		return false
	var book: Dictionary = visits.get_or_add(house, {})
	var fresh := not book.has(pid)
	book[pid] = nick
	return fresh


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
	return {"schema": SCHEMA, "next_id": next_id, "items": list, "lanterns": lanterns.duplicate(true), "evening": evening,
		"roster": roster.duplicate(true), "wishes": wishes.duplicate(true), "weather": weather, "hearts": hearts.duplicate(true),
		"visits": visits.duplicate(true), "photo_ideas": photo_ideas.duplicate(true),
		"pets": pets.duplicate(true), "starter": starter.keys(), "cooked": cooked.duplicate(true),
		"display": _display_saved(), "keepsakes": keepsakes.duplicate(true)}


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
		if e.has("kind") and KIND_ALIASES.has(str(e["kind"])):
			e = e.duplicate()
			e["kind"] = KIND_ALIASES[str(e["kind"])]
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
		_load_optional(item, e)
		var n := int(item["id"].substr(1))
		next_id = maxi(next_id, n + 1)
	var lit: Dictionary = data.get("lanterns", {})
	for spot in lit:
		lanterns[str(spot)] = {"by": Array(lit[spot].get("by", [])), "t": int(lit[spot].get("t", 0))}
	evening = bool(data.get("evening", false))
	_load_activities(data)
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


## Optional per-item fields, each checked so a damaged save cannot break the town.
func _load_optional(item: Dictionary, e: Dictionary) -> void:
	if Catalog.anchor(item["kind"]) != "ground":
		var slot := mount_slot(item["kind"], item["x"], item["z"], item["rot"])   # a ceiling item keeps its turn
		item["x"] = slot["x"]
		item["z"] = slot["z"]
		item["rot"] = slot["rot"]
		item["y"] = slot["y"]
	if item["kind"] == "garden_bed":
		item["growth"] = clampi(int(e.get("growth", 0)), 0, GROWTH_MAX)
	if VARIANTS.has(item["kind"]):
		item["variant"] = posmod(int(e.get("variant", 0)), VARIANTS[item["kind"]])
	if item["kind"] == "trail_sign":
		item["num"] = clampi(int(e.get("num", 1)), 1, MAX_TRAIL_SIGNS)
	if item["kind"] == "music_box":
		item["song"] = sanitize_song(e.get("song"))
		item["on"] = bool(e.get("on", false))
	if Catalog.grid(item["kind"]) > 0.0:
		var g := grid_snap(item["kind"], item["x"], item["z"], item["rot"])
		item["x"] = g["x"]
		item["z"] = g["z"]
		item["rot"] = g["rot"]
	var g = e.get("gift")
	if typeof(g) == TYPE_DICTIONARY and item["kind"] != "cottage":
		item["gift"] = {"to": str(g.get("to", "")).left(64), "from": str(g.get("from", "")).left(64),
			"from_nick": str(g.get("from_nick", "")).left(16), "paper": clampi(int(g.get("paper", 0)), 0, Palette.PAINT.size() - 1)}


## Town-level activity data; anything missing or malformed falls back to defaults.
func _load_activities(data: Dictionary) -> void:
	roster = {}
	var r = data.get("roster", {})
	if typeof(r) == TYPE_DICTIONARY:
		for pid in r:
			if typeof(r[pid]) == TYPE_DICTIONARY:
				roster[str(pid)] = {"nick": str(r[pid].get("nick", "")), "color": int(r[pid].get("color", 0)), "seen": int(r[pid].get("seen", 0))}
	wishes = {"active": {}, "stickers": []}
	var w = data.get("wishes", {})
	if typeof(w) == TYPE_DICTIONARY:
		if typeof(w.get("active")) == TYPE_DICTIONARY:
			wishes["active"] = w["active"]
		if typeof(w.get("stickers")) == TYPE_ARRAY:
			for x in w["stickers"]:
				if typeof(x) == TYPE_DICTIONARY:
					wishes["stickers"].append({"animal": str(x.get("animal", "")), "id": str(x.get("id", "")), "by": Array(x.get("by", [])), "t": int(x.get("t", 0))})
	weather = str(data.get("weather", "sunny"))
	if not WEATHERS.has(weather):
		weather = "sunny"
	hearts = _nested_dict(data.get("hearts", {}))
	visits = _nested_dict(data.get("visits", {}))
	pets = PetRules.sanitize(data.get("pets", {}))
	starter = {}
	var st = data.get("starter", [])
	if typeof(st) == TYPE_ARRAY:
		for sp in st:
			if is_space(str(sp)) and str(sp) != "town":
				starter[str(sp)] = true
	cooked = {}
	var ck = data.get("cooked", {})
	if typeof(ck) == TYPE_DICTIONARY:
		for pid in ck:
			cooked[str(pid).left(64)] = maxi(0, int(ck[pid]))
	display = {}
	var dp = data.get("display", {})
	if typeof(dp) == TYPE_DICTIONARY:
		for sp in dp:
			if is_space(str(sp)) and typeof(dp[sp]) == TYPE_DICTIONARY:
				display[str(sp)] = {"pid": str(dp[sp].get("pid", "")).left(64), "nick": str(dp[sp].get("nick", "")).left(16)}
	keepsakes = []
	var ks = data.get("keepsakes", [])
	if typeof(ks) == TYPE_ARRAY:
		for k in ks:
			if typeof(k) == TYPE_DICTIONARY and str(k.get("kind", "")) == "trail":
				keepsakes.append({"kind": "trail", "by": Array(k.get("by", [])).map(func(n): return str(n).left(16)), "t": int(k.get("t", 0))})
	photo_ideas = {}
	var ph = data.get("photo_ideas", {})
	if typeof(ph) == TYPE_DICTIONARY:
		for k in ph:
			if typeof(ph[k]) == TYPE_DICTIONARY:
				photo_ideas[str(k)] = {"by": Array(ph[k].get("by", [])), "t": int(ph[k].get("t", 0))}


static func _nested_dict(v) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if typeof(v[k]) == TYPE_DICTIONARY:
				out[str(k)] = {}
				for pid in v[k]:
					out[str(k)][str(pid)] = str(v[k][pid])
	return out


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
