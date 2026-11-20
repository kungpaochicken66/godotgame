## Rideable carts (design/puzzle-rooms-and-rides.md): a child lays ride rails on
## 2 m cells, gets into the cart at its station and rides around what they built.
##
## The toy-track pieces (track_rules.gd) are NOT reused: they are 0.94 m boards
## for a 9 cm ball, with bell and light arches under half a meter high that a
## seated child (hips 0.45 m up, head about 1.2 m) would pass through, a start
## with one opening and a finish that only catches. Ride rails are their own
## three kinds, sized for the cart: 2 m cells, a 1 m curve radius and a cart
## 0.8 m wide, so two parallel tracks keep 1.2 m between carts' sides.
##
## Pure rules, unit-tested; the authority runs a ride and every device draws it
## from the same route and distance. Nothing can strand a child: a cart stops by
## itself at the end of an open track, before anything solid standing on the
## rails, and at its station after LAPS laps; getting off is always allowed.
##
## Ports are quarter turns q of the piece's own facing, as in track_rules.gd:
## the world direction of port q is TownModel.facing(rot + 2 * q); q 0 = front,
## 1 = local +x side, 2 = back.
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const STATION := "ride_station"
## A straight rail that is also a contraption trigger: a cart passing over its middle sets off
## what stands near it (core/contraptions.gd), every time round.
const SIGNAL := "ride_signal"
const KINDS := ["ride_station", "ride_straight", "ride_curve", "ride_signal"]
const PORTS := {"ride_station": [0, 2], "ride_straight": [0, 2], "ride_curve": [2, 1], "ride_signal": [0, 2]}
## Cell size in meters (Catalog "grid" of the three kinds).
const CELL := 2.0
## Meters a second: slower than walking (3.4), so the camera follows as gently as it does on foot.
const SPEED := 2.4
## A closed circuit is ridden this many times round, then the cart stops at its station.
const LAPS := 3
## The longest route followed, in pieces.
const MAX_LEGS := 80
## On an open track the cart stops this far before the last piece's end.
const STOP_MARGIN := 0.7
## Getting in needs the child this close to the station.
const BOARD_REACH := 3.0
## Half the cart's width, and how far beside the rails a child steps off.
const CART_HALF := 0.4
const STEP_OFF := 1.15

const ERR_NOT_HERE := "That cart is not here."
const ERR_WALK := "Walk to the cart to get in."
const ERR_TAKEN := "Someone is riding this cart."
const ERR_NOT_RIDING := "Get into the cart first."
const ERR_NO_TRACK := "The cart needs a rail in front of it."
const ERR_END := "The rails end here. Get off, or add a rail."
const ERR_BLOCKED := "Something is standing on the rails."
const ERR_BROKEN := "The rails changed under the cart. Get off to send it home."


static func is_rail(kind: String) -> bool:
	return KINDS.has(kind)


static func cell_of(item: Dictionary) -> Vector2i:
	return Vector2i(roundi(item["x"] / CELL), roundi(item["z"] / CELL))


static func dir_of(rot: int, q: int) -> Vector2i:
	var f := TownModel.facing(rot + 2 * q)
	return Vector2i(roundi(f.x), roundi(f.y))


## Which port of this piece faces world direction d (or -1).
static func port_facing(item: Dictionary, d: Vector2i) -> int:
	for q in 4:
		if dir_of(item["rot"], q) == d:
			return q
	return -1


static func _usable(it: Dictionary) -> bool:
	return not it.is_empty() and not it.has("gift") and it["space"] == "town"


## One piece of a route: [cell x, cell z, in x, in z, out x, out z]. "in" is the
## direction of travel entering the cell, "out" leaving it (equal on a straight).
static func leg_length(leg: Array) -> float:
	return CELL if (leg[2] == leg[4] and leg[3] == leg[5]) else PI * 0.5 * CELL * 0.5


## Where the cart is u (0..1) of the way through a leg: {"pos", "dir"} in meters.
static func leg_pose(leg: Array, u: float) -> Dictionary:
	var c := Vector2(leg[0], leg[1]) * CELL
	var a := Vector2(leg[2], leg[3])
	var b := Vector2(leg[4], leg[5])
	if a == b:
		return {"pos": c + a * (u - 0.5) * CELL, "dir": a}
	# A quarter circle about the cell corner between the way in and the way out.
	var pivot := c - a * CELL * 0.5 + b * CELL * 0.5
	var th := clampf(u, 0.0, 1.0) * PI * 0.5
	return {"pos": pivot + (-b * cos(th) + a * sin(th)) * CELL * 0.5, "dir": (a * cos(th) + b * sin(th)).normalized()}


## Solid things standing on the ground outdoors (not on a table): the cart never drives through them.
static func _solids(model) -> Array:
	var out := []
	for it in model.items_in("town"):
		var def: Dictionary = Catalog.get_def(it["kind"])
		if def.get("layer", "") == "solid" and not it.has("host") and Catalog.anchor(it["kind"]) == "ground":
			out.append([Vector2(it["x"], it["z"]), float(def["radius"]) * (0.95 if it["kind"] == "cottage" else 0.8) + CART_HALF])
	return out


static func _leg_blocked(leg: Array, solids: Array) -> bool:
	for i in 5:
		var p: Vector2 = leg_pose(leg, i / 4.0)["pos"]
		for s in solids:
			if p.distance_to(s[0]) < s[1]:
				return true
	return false


## The cart's route from its station as the town is now:
## {"legs": [leg], "end", "at": Vector2 (the cell where the rails stop, in meters), "loop": bool}
##   end "loop"       the rails come back into the station's back: a circuit
##       "end"        no rail ahead (an open track: the cart stops at its last piece)
##       "wrong_way"  the next rail does not join up
##       "blocked"    something solid stands on the next rail
##       "long"       more than MAX_LEGS pieces
## legs[0] is always the station itself (the cart starts at its middle).
static func route(model, station_id: String) -> Dictionary:
	var station: Dictionary = model.items.get(station_id, {})
	var out := {"legs": [], "end": "end", "at": Vector2.ZERO, "loop": false, "signals": []}
	if not _usable(station) or station["kind"] != STATION:
		return out
	var grid := {}
	for it in model.items_in("town"):
		if is_rail(it["kind"]) and not it.has("gift"):
			grid[cell_of(it)] = it
	var solids := _solids(model)
	var cell := cell_of(station)
	var d := dir_of(station["rot"], 0)
	var first := [cell.x, cell.y, d.x, d.y, d.x, d.y]
	out["legs"].append(first)
	out["at"] = Vector2(cell) * CELL
	if _leg_blocked(first, solids):
		out["end"] = "blocked"
		return out
	for i in MAX_LEGS:
		cell += d
		out["at"] = Vector2(cell) * CELL
		var piece: Dictionary = grid.get(cell, {})
		if piece.is_empty():
			out["end"] = "end"
			return out
		var q_in := port_facing(piece, -d)
		if not PORTS[piece["kind"]].has(q_in):
			out["end"] = "wrong_way"
			return out
		if piece["id"] == station_id:
			if q_in != 2:
				out["end"] = "wrong_way"   # rails must come into the station from behind
				return out
			out["end"] = "loop"
			out["loop"] = true
			out["at"] = Vector2(cell_of(station)) * CELL
			return out
		if piece["kind"] == STATION:
			out["end"] = "end"   # another cart's station: this cart stops before it
			return out
		var ports: Array = PORTS[piece["kind"]]
		var q_out: int = ports[1] if q_in == ports[0] else ports[0]
		var b := dir_of(piece["rot"], q_out)
		var leg := [cell.x, cell.y, d.x, d.y, b.x, b.y]
		if _leg_blocked(leg, solids):
			out["end"] = "blocked"
			return out
		if piece["kind"] == SIGNAL:
			out["signals"].append([out["legs"].size(), piece["id"]])   # [leg index, id], in riding order
		out["legs"].append(leg)
		d = b
	out["end"] = "long"
	return out


## The signal rails whose middle a cart passed while going from s0 to s1 meters (s0 < s1), in the
## order it passed them. On a circuit a signal is passed again every lap.
static func signals_between(r: Dictionary, s0: float, s1: float) -> Array:
	var found := []
	var legs: Array = r.get("legs", [])
	var lap := total_length(r)
	for sig in r.get("signals", []):
		var at := -CELL * 0.5
		for j in int(sig[0]):
			at += leg_length(legs[j])
		at += leg_length(legs[int(sig[0])]) * 0.5
		if r.get("loop", false) and lap > 0.0:
			var d := at + maxf(0.0, ceilf((s0 - at) / lap)) * lap   # this signal's first passing at or after s0
			if d <= s0:
				d += lap
			while d <= s1:
				found.append([d, sig[1]])
				d += lap
		elif at > s0 and at <= s1:
			found.append([at, sig[1]])
	found.sort()
	return found.map(func(f): return f[1])


## Meters once round a circuit (or along the whole of an open track, station included).
static func total_length(r: Dictionary) -> float:
	var sum := 0.0
	for leg in r.get("legs", []):
		sum += leg_length(leg)
	return sum


## How far from the station's middle a ride goes before the cart stops by itself.
static func end_distance(r: Dictionary) -> float:
	if r.get("loop", false):
		return total_length(r) * LAPS
	if r.get("legs", []).size() < 2:
		return 0.0
	return maxf(0.0, total_length(r) - CELL * 0.5 - STOP_MARGIN)


## Can a ride start from here? "" or the reason.
static func go_error(r: Dictionary, s: float) -> String:
	if r.get("legs", []).size() < 2:
		return ERR_BLOCKED if r.get("end", "") == "blocked" else ERR_NO_TRACK
	if s >= end_distance(r) - 0.01:
		return ERR_BLOCKED if r.get("end", "") == "blocked" else ERR_END
	return ""


## Which leg the cart is on, and how far into it, s meters from the station's
## middle (on a circuit s keeps growing lap after lap): {"leg": index, "offset": meters}.
static func locate(r: Dictionary, s: float) -> Dictionary:
	var legs: Array = r.get("legs", [])
	if legs.is_empty():
		return {"leg": -1, "offset": 0.0}
	var along := s + CELL * 0.5   # measured from where the station's leg begins
	if r.get("loop", false):
		along = fposmod(along, total_length(r))
	else:
		along = clampf(along, 0.0, total_length(r))
	for i in legs.size():
		var l := leg_length(legs[i])
		if along <= l or i == legs.size() - 1:
			return {"leg": i, "offset": minf(along, l)}
		along -= l
	return {"leg": legs.size() - 1, "offset": 0.0}


## Where the cart is and which way it points: {"pos": Vector2, "dir": Vector2, "leg": index}.
static func pose(r: Dictionary, s: float) -> Dictionary:
	var at := locate(r, s)
	if at["leg"] < 0:
		return {"pos": Vector2.ZERO, "dir": Vector2(0, 1), "leg": -1}
	var leg: Array = r["legs"][at["leg"]]
	var p := leg_pose(leg, at["offset"] / leg_length(leg))
	p["leg"] = at["leg"]
	return p


## The town changed while a cart was out. Where is it on the new route?
## Returns the new distance from the station, or -1.0 when the piece under the
## cart is no longer part of the route (the cart stops where it is).
static func rebase(old: Dictionary, s: float, new: Dictionary) -> float:
	var at := locate(old, s)
	if at["leg"] < 0:
		return -1.0
	var mine: Array = old["legs"][at["leg"]]
	var start := -CELL * 0.5
	var legs: Array = new.get("legs", [])
	for j in legs.size():
		if legs[j] == mine:
			return start + at["offset"]
		start += leg_length(legs[j])
	return -1.0


## Where a ride that had `left` meters to go ends on a new route, from distance s.
static func rebased_end(new: Dictionary, s: float, left: float) -> float:
	if not new.get("loop", false):
		return maxf(s, end_distance(new))
	var lap := total_length(new)
	var to_station := lap - fposmod(s, lap)
	var laps_left := clampi(ceili((left - 0.01) / lap), 1, LAPS)
	return s + to_station + (laps_left - 1) * lap


## Can this child get into this cart? "" or the reason (the caller checks the seat).
static func check_board(model, station_id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(station_id, {})
	if not _usable(it) or it["kind"] != STATION:
		return ERR_NOT_HERE
	if actor_space != "town" or Vector2(it["x"], it["z"]).distance_to(actor_pos) > BOARD_REACH:
		return ERR_WALK
	return ""


## Spots beside the cart to step off onto, best first (right of the way it faces, then left).
static func step_off_points(at: Vector2, dir: Vector2) -> Array:
	var side := Vector2(-dir.y, dir.x)
	return [at + side * STEP_OFF, at - side * STEP_OFF, at - dir * STEP_OFF]
