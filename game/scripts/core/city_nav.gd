## Navigation for the miniature city district (design/city-district.md): pure, static, no nodes.
##
## A position is (Vector2 xz, region String); region "" is the ground. Every walkable thing is a
## "place": the ground, each REGIONS rectangle (minus its holes), each stair. Places touch only
## through the shared edges of the header rule in city_map.gd (a shared segment of at least 0.8 m
## at the same height): those are the portals. Everything else is an obstacle or a railing.
##
## A child is a disc of radius R = 0.3 m, so the centre is kept R inside every upper edge, R away
## from walls, solids, furniture and holes; at a portal the centre may go through the shared segment
## (shrunk by R at both ends), which is the "corridor": a band R deep either side of the edge.
## Doors are thinner than 2R, so a door is made only of its two corridors.
##
## step() moves in sub-steps of 0.1 m with axis sliding and region switches through portals only
## (a crossing needs the centre to pass the edge line inside the portal range and be allowed on the
## other side). route() is A* over a graph of cached nodes (obstacle corners and portal gates) with
## straight lines inside a place. pick() casts a ray at everything and returns the nearest hit if it
## is a walkable top (floor-aware: roofs, walls, undersides and edges of slabs block).
extends RefCounted

const CityMap := preload("res://scripts/core/city_map.gd")

## The child's body radius.
const R := 0.3
const EPS := 1e-4
const SUB := 0.1
const PORTAL_MIN := 0.8
## How far past an edge the crossing waypoint lies.
const CROSS_IN := 0.03
const GATE_SPACING := 2.5
## Corner nodes lie this far off an obstacle's grown edge and gates this far inside their corridor, so a
## walker that arrives within the controller's 0.08 m of a waypoint is never on the wrong side of a limit.
const NODE_CLEAR := 0.12
const GATE_MARGIN := 0.15
## A door opening is this tall above its floor (picking through the wall's doorway).
const DOOR_OPEN := 2.4
## Walls block taps (the art raises them to the building's height). False: only floors and roofs do.
const PICK_WALLS := true

static var _built := false
static var _places: Dictionary = {}
static var _order: Array = []
static var _vis: Dictionary = {}
static var _bmap: Dictionary = {}
static var _people: Array = []
static var _people_loaded := false

const PEOPLE_DATA := "res://scripts/core/city_people_data.gd"


## The standing people, solid to children: [{"region", "at": Vector2, "r"}] from CityPeopleData.solids()
## (loaded when the script exists, so the navigation works before it lands).
static func people_solids() -> Array:
	if not _people_loaded:
		_people_loaded = true
		if ResourceLoader.exists(PEOPLE_DATA):
			var scr: GDScript = load(PEOPLE_DATA) as GDScript
			if scr != null:
				var got: Variant = scr.call("solids")
				if got is Array:
					_people = got
	return _people


# ------------------------------------------------------------------ geometry helpers

static func _in(r: Rect2, p: Vector2, e: float = EPS) -> bool:
	return p.x >= r.position.x - e and p.x <= r.end.x + e and p.y >= r.position.y - e and p.y <= r.end.y + e


static func _inside(r: Rect2, p: Vector2, e: float = EPS) -> bool:
	return p.x > r.position.x + e and p.x < r.end.x - e and p.y > r.position.y + e and p.y < r.end.y - e


static func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var dv: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		var av: float = a[axis]
		if absf(dv) < 1e-9:
			if av <= lo or av >= hi:
				return false
		else:
			var u0 := (lo - av) / dv
			var u1 := (hi - av) / dv
			if u0 > u1:
				var tmp := u0
				u0 = u1
				u1 = tmp
			t0 = maxf(t0, u0)
			t1 = minf(t1, u1)
			if t0 >= t1 - 1e-9:
				return false
	return t0 < t1


static func _seg_hits_circle(a: Vector2, b: Vector2, c: Vector3) -> bool:
	var ab := b - a
	var center := Vector2(c.x, c.y)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-12 else clampf((center - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(center) < c.z - 1e-3


# ------------------------------------------------------------------ the places

static func _new_place(id: String, kind: String, rect: Rect2, y0: float, y1: float) -> Dictionary:
	var inner := rect.grow(-R)
	return {"id": id, "kind": kind, "rect": rect, "y0": y0, "y1": y1, "up": "", "building": "",
		"holes": [], "ex": [], "exg": [], "circ": [], "cor": [], "portals": [], "nodes": [], "links": {},
		"inner": inner, "has_inner": inner.size.x > 0.0 and inner.size.y > 0.0}


## The map's data names the ground "ground" in FURNITURE and INTERACTIONS; here it is "".
static func _rn(region: String) -> String:
	return "" if region == "ground" else region


static func _ensure() -> void:
	if _built:
		return
	_built = true
	_build()


static func _build() -> void:
	_places = {}
	_order = [""]
	_vis = {}
	_bmap = {}
	var ground := _new_place("", "ground", Rect2(-CityMap.HALF, CityMap.HALF * 2.0), 0.0, 0.0)
	for w: Rect2 in CityMap.GROUND_WALLS:
		(ground["ex"] as Array).append(w.grow(R))
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		if s.has("rect"):
			var rr: Rect2 = s["rect"]
			var arr: Array = ground["exg"] if String(s["kind"]) == "stair_base" else ground["ex"]
			arr.append(rr.grow(R))
		else:
			var at: Vector2 = s["at"]
			(ground["circ"] as Array).append(Vector3(at.x, at.y, float(s["r"]) + R))
	_places[""] = ground
	for id: String in CityMap.REGIONS:
		var rd: Dictionary = CityMap.REGIONS[id]
		var pl := _new_place(id, "region", rd["rect"], float(rd["y"]), float(rd["y"]))
		pl["building"] = String(rd["building"])
		for h: Rect2 in rd["holes"]:
			(pl["holes"] as Array).append(h)
			(pl["exg"] as Array).append(h.grow(R))
		_places[id] = pl
		_order.append(id)
	for id: String in CityMap.STAIRS:
		var sd: Dictionary = CityMap.STAIRS[id]
		var pl := _new_place(id, "stair", sd["rect"], float(sd["y0"]), float(sd["y1"]))
		pl["up"] = String(sd["up"])
		pl["building"] = String(sd.get("building", ""))
		_places[id] = pl
		_order.append(id)
	for f: Dictionary in CityMap.FURNITURE:
		var key := _rn(String(f["region"]))
		if _places.has(key):
			var fr: Rect2 = f["rect"]
			((_places[key] as Dictionary)["ex"] as Array).append(fr.grow(R))
	for ps: Dictionary in people_solids():
		var pkey := _rn(String(ps.get("region", "")))
		if _places.has(pkey):
			var pat: Vector2 = ps["at"]
			((_places[pkey] as Dictionary)["circ"] as Array).append(Vector3(pat.x, pat.y, float(ps["r"]) + R))
	_find_portals()
	for id: String in _order:
		_make_corridors(_places[id])
	_make_nodes()


static func _link(a: String, b: String, axis: int, e: float, lo: float, hi: float, side: int) -> void:
	(((_places[a] as Dictionary)["portals"]) as Array).append({"to": b, "axis": axis, "e": e, "lo": lo, "hi": hi, "side": side})
	(((_places[b] as Dictionary)["portals"]) as Array).append({"to": a, "axis": axis, "e": e, "lo": lo, "hi": hi, "side": -side})


static func _find_portals() -> void:
	var regs: Array = []
	for id: String in _order:
		if (_places[id] as Dictionary)["kind"] == "region":
			regs.append(id)
	# region to region: facing edges at the same height
	for ia: String in regs:
		var a: Dictionary = _places[ia]
		var ra: Rect2 = a["rect"]
		for ib: String in regs:
			if ia == ib:
				continue
			var b: Dictionary = _places[ib]
			if absf(float(a["y0"]) - float(b["y0"])) > 0.01:
				continue
			var rb: Rect2 = b["rect"]
			if absf(ra.end.x - rb.position.x) < 0.01:
				var lo := maxf(ra.position.y, rb.position.y)
				var hi := minf(ra.end.y, rb.end.y)
				if hi - lo >= PORTAL_MIN - 1e-6:
					_link(ia, ib, 0, ra.end.x, lo, hi, 1)
			if absf(ra.end.y - rb.position.y) < 0.01:
				var lo2 := maxf(ra.position.x, rb.position.x)
				var hi2 := minf(ra.end.x, rb.end.x)
				if hi2 - lo2 >= PORTAL_MIN - 1e-6:
					_link(ia, ib, 1, ra.end.y, lo2, hi2, 1)
	# stair ends to the ground or a region at the end's height
	for id: String in _order:
		var s: Dictionary = _places[id]
		if s["kind"] != "stair":
			continue
		var rect: Rect2 = s["rect"]
		var up: String = s["up"]
		var axis := 1 if up.ends_with("z") else 0
		var plus := up.begins_with("+")
		var lo_c: float = rect.position[axis]
		var hi_c: float = rect.end[axis]
		var lat_lo: float = rect.position[1 - axis]
		var lat_hi: float = rect.end[1 - axis]
		# the high end is on the "up" side
		var ends := [
			{"e": hi_c if plus else lo_c, "n": 1 if plus else -1, "y": float(s["y1"])},
			{"e": lo_c if plus else hi_c, "n": -1 if plus else 1, "y": float(s["y0"])}]
		for end: Dictionary in ends:
			var e: float = end["e"]
			var n: int = end["n"]
			var best_lo := 0.0
			var best_hi := 0.0
			var best_to := ""
			var has_best := false
			for pid: String in _order:
				var p: Dictionary = _places[pid]
				if p["kind"] == "stair" or absf(float(p["y0"]) - float(end["y"])) > 0.01:
					continue
				var run_lo := 0.0
				var run_hi := -1.0
				var cur_lo := 0.0
				var in_run := false
				var steps := int(round((lat_hi - lat_lo) / 0.05))
				for k in steps + 1:
					var u := lat_lo + (lat_hi - lat_lo) * float(k) / float(maxi(steps, 1))
					var q := Vector2(u, e + n * 0.04) if axis == 1 else Vector2(e + n * 0.04, u)
					var covered := _in(p["rect"], q, 0.0)
					if covered:
						for h: Rect2 in p["holes"]:
							if _inside(h, q, 1e-6):
								covered = false
					if covered and not in_run:
						in_run = true
						cur_lo = u
					if covered and in_run and u - cur_lo > run_hi - run_lo:
						run_lo = cur_lo
						run_hi = u
					if not covered:
						in_run = false
				if run_hi - run_lo >= PORTAL_MIN - 1e-6 and run_hi - run_lo > best_hi - best_lo:
					best_lo = run_lo
					best_hi = run_hi
					best_to = pid
					has_best = true
			if has_best:
				_link(id, best_to, axis, e, best_lo, best_hi, n)


static func _make_corridors(pl: Dictionary) -> void:
	var cor: Array = pl["cor"]
	var rect: Rect2 = pl["rect"]
	for p: Dictionary in pl["portals"]:
		var axis: int = p["axis"]
		var e: float = p["e"]
		var side: int = p["side"]
		var lo2: float = float(p["lo"]) + R
		var hi2: float = float(p["hi"]) - R
		if hi2 < lo2:
			lo2 = (float(p["lo"]) + float(p["hi"])) * 0.5
			hi2 = lo2
		var depth := minf(R, rect.size[axis])
		var cmin := e - depth if side > 0 else e
		if axis == 0:
			cor.append(Rect2(Vector2(cmin, lo2), Vector2(depth, hi2 - lo2)))
		else:
			cor.append(Rect2(Vector2(lo2, cmin), Vector2(hi2 - lo2, depth)))


static func _allowed_pl(pl: Dictionary, p: Vector2) -> bool:
	var in_cor := false
	for c: Rect2 in pl["cor"]:
		if _in(c, p):
			in_cor = true
			break
	if not in_cor:
		if not pl["has_inner"] or not _in(pl["inner"], p):
			return false
		for r: Rect2 in pl["exg"]:
			if _inside(r, p):
				return false
	for r: Rect2 in pl["ex"]:
		if _inside(r, p):
			return false
	for c: Vector3 in pl["circ"]:
		if p.distance_to(Vector2(c.x, c.y)) < c.z - EPS:
			return false
	return true


static func _make_nodes() -> void:
	# corner nodes first
	for id: String in _order:
		var pl: Dictionary = _places[id]
		var nodes: Array = pl["nodes"]
		var rects: Array = []
		rects.append_array(pl["ex"])
		rects.append_array(pl["exg"])
		for r: Rect2 in rects:
			var g := r.grow(NODE_CLEAR)
			for c: Vector2 in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
				if _allowed_pl(pl, c):
					nodes.append(c)
		for c: Vector3 in pl["circ"]:
			var rad := c.z / cos(PI / 8.0) * 1.01 + NODE_CLEAR
			for k in 8:
				var ang := TAU * (float(k) + 0.5) / 8.0
				var q := Vector2(c.x, c.y) + Vector2(cos(ang), sin(ang)) * rad
				if _allowed_pl(pl, q):
					nodes.append(q)
	# gates: one pair of nodes per usable lateral position of each portal
	for ia: String in _order:
		var a: Dictionary = _places[ia]
		for p: Dictionary in a["portals"]:
			var ib: String = p["to"]
			if _order.find(ib) < _order.find(ia):
				continue
			var b: Dictionary = _places[ib]
			var axis: int = p["axis"]
			var e: float = p["e"]
			var side: int = p["side"]
			var lo2: float = float(p["lo"]) + R
			var hi2: float = float(p["hi"]) - R
			var length := hi2 - lo2
			# keep the gates off the corridor's own limits, so a walker that stops short of a waypoint (the
			# controller accepts 0.08 m) is still inside the corridor and can enter it
			var margin := minf(GATE_MARGIN, maxf(length, 0.0) * 0.25)
			lo2 += margin
			hi2 -= margin
			length = hi2 - lo2
			var count := 1 if length < 0.01 else maxi(3, ceili(length / GATE_SPACING) + 1)
			var da := minf(R, (a["rect"] as Rect2).size[axis] * 0.5)
			var db := minf(R, (b["rect"] as Rect2).size[axis] * 0.5)
			for k in count:
				var u := (lo2 + hi2) * 0.5 if count == 1 else lo2 + length * float(k) / float(count - 1)
				var a_in := _pt(axis, e - side * da, u)
				var cross_b := _pt(axis, e + side * CROSS_IN, u)
				var b_in := _pt(axis, e + side * db, u)
				var cross_a := _pt(axis, e - side * CROSS_IN, u)
				if not (_allowed_pl(a, a_in) and _allowed_pl(b, cross_b) and _allowed_pl(b, b_in) and _allowed_pl(a, cross_a)):
					continue
				var na := (a["nodes"] as Array).size()
				var nb := (b["nodes"] as Array).size()
				(a["nodes"] as Array).append(a_in)
				(b["nodes"] as Array).append(b_in)
				var cost := da + db + 2.0 * CROSS_IN
				(a["links"] as Dictionary)[na] = {"to": ib, "j": nb, "cross": cross_b, "cost": cost}
				(b["links"] as Dictionary)[nb] = {"to": ia, "j": na, "cross": cross_a, "cost": cost}


static func _pt(axis: int, c: float, u: float) -> Vector2:
	return Vector2(c, u) if axis == 0 else Vector2(u, c)


# ------------------------------------------------------------------ public queries

## Every place id: "" (ground), the REGIONS and the STAIRS.
static func place_ids() -> Array:
	_ensure()
	return _order.duplicate()


static func has_place(region: String) -> bool:
	_ensure()
	region = _rn(region)
	return _places.has(region)


## The rectangle of a place (the ground: the whole map).
static func place_rect(region: String) -> Rect2:
	_ensure()
	region = _rn(region)
	return (_places[region] as Dictionary)["rect"] if _places.has(region) else Rect2()


## The portals of a place: [{"to", "axis" (0: the edge is the line x = e), "e", "lo", "hi", "side" (+1: the
## neighbour lies at larger coordinates)}].
static func portals(region: String) -> Array:
	_ensure()
	region = _rn(region)
	return ((_places[region] as Dictionary)["portals"] as Array).duplicate(true) if _places.has(region) else []


## Can a child's centre stand here?
static func allowed(region: String, p: Vector2) -> bool:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return false
	return _allowed_pl(_places[region], p)


## The walking height of a position (stairs interpolate along "up").
static func height(region: String, p: Vector2) -> float:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return 0.0
	var pl: Dictionary = _places[region]
	if pl["kind"] != "stair":
		return float(pl["y0"])
	var r: Rect2 = pl["rect"]
	var up: String = pl["up"]
	var t := 0.0
	match up:
		"-z":
			t = (r.end.y - p.y) / r.size.y
		"+z":
			t = (p.y - r.position.y) / r.size.y
		"-x":
			t = (r.end.x - p.x) / r.size.x
		_:
			t = (p.x - r.position.x) / r.size.x
	return lerpf(float(pl["y0"]), float(pl["y1"]), clampf(t, 0.0, 1.0))


## The nearest standing place to p on the region (p itself when it is allowed). {} for an unknown region.
static func snap(region: String, p: Vector2) -> Dictionary:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return {}
	var pl: Dictionary = _places[region]
	if _allowed_pl(pl, p):
		return {"region": region, "pos": p}
	var best := Vector2.ZERO
	var found := false
	for k in range(1, 121):
		var rad := 0.05 * float(k)
		var best_d := INF
		var count := 16 + k * 2
		for a in count:
			var ang := TAU * float(a) / float(count)
			var q := p + Vector2(cos(ang), sin(ang)) * rad
			if _allowed_pl(pl, q) and q.distance_to(p) < best_d:
				best_d = q.distance_to(p)
				best = q
				found = true
		if found:
			break
	if not found:
		return {}
	return {"region": region, "pos": best}


## A standing point inside a place (for tests and for the art's probes): its middle, or the nearest allowed.
static func probe(region: String) -> Vector2:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return Vector2.ZERO
	var pl: Dictionary = _places[region]
	var r: Rect2 = pl["rect"]
	var s := snap(region, r.get_center())
	return Vector2(s["pos"]) if not s.is_empty() else r.get_center()


## Places where people can wait out the rain, all standable and reachable (snapped to the nearest free spot):
## [{"kind": "awning" | "shelter" | "canopy", "id", "region": "", "pos": Vector2}]. Awnings: three spots in a
## row just outside each shop front (z + 0.3 to 0.9 past the front); shelters: the four sides of every
## bus_shelter solid (its inside is solid); canopy: eight spots round every carousel just outside its fence.
## Data-driven from BUILDINGS, SHOP_DOORS and GROUND_SOLIDS. The inside of a solid is never a target:
## route() snaps to the nearest free spot anyway.
static func cover_spots() -> Array:
	_ensure()
	var out: Array = []
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		if not bool(b.get("shop", false)):
			continue
		var r: Rect2 = b["rect"]
		var mid := r.get_center().x
		if CityMap.SHOP_DOORS.has(bid):
			var d: Vector2 = CityMap.SHOP_DOORS[bid]
			mid = (d.x + d.y) * 0.5
		for k in 3:
			var s := snap("", Vector2(mid + float(k - 1), r.end.y + 0.3 + 0.3 * float(k)))
			if not s.is_empty():
				out.append({"kind": "awning", "id": "%s:%d" % [bid, k], "region": "", "pos": s["pos"]})
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		var kind: String = sd["kind"]
		if kind == "bus_shelter":
			var rr: Rect2 = sd["rect"]
			var c := rr.get_center()
			var gap := R + 0.2
			var sides := [Vector2(rr.position.x - gap, c.y), Vector2(rr.end.x + gap, c.y), Vector2(c.x, rr.position.y - gap), Vector2(c.x, rr.end.y + gap)]
			for k in 4:
				var s2 := snap("", sides[k])
				if not s2.is_empty():
					out.append({"kind": "shelter", "id": "%s:%d" % [str(c), k], "region": "", "pos": s2["pos"]})
		elif kind == "carousel":
			var cc: Vector2 = sd["at"]
			for k in 8:
				var s3 := snap("", cc + Vector2.from_angle(TAU * float(k) / 8.0) * (float(sd["r"]) + R + 0.1))
				if not s3.is_empty():
					out.append({"kind": "canopy", "id": "%s:%d" % [str(cc), k], "region": "", "pos": s3["pos"]})
	return out


## Where a traveller arrives at the bus stop: {"region": "", "pos", "ry"}; slots wrap.
static func arrival(slot: int) -> Dictionary:
	_ensure()
	var list: Array = CityMap.ARRIVALS
	var p: Vector2 = list[posmod(slot, list.size())]
	var s := snap("", p)
	return {"region": "", "pos": Vector2(s["pos"]) if not s.is_empty() else p, "ry": CityMap.ARRIVAL_RY}


## Places reachable on foot from a position: the place ids, found over the portals that have a usable gate.
static func reachable(region: String, _p: Vector2 = Vector2.ZERO) -> Array:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return []
	var seen: Dictionary = {region: true}
	var queue: Array = [region]
	while queue.size() > 0:
		var cur: String = queue.pop_front()
		var links: Dictionary = (_places[cur] as Dictionary)["links"]
		for k: int in links:
			var to: String = (links[k] as Dictionary)["to"]
			if not seen.has(to):
				seen[to] = true
				queue.append(to)
	return seen.keys()


# ------------------------------------------------------------------ stepping

static func _try(region: String, a: Vector2, q: Vector2) -> Variant:
	var pl: Dictionary = _places[region]
	for p: Dictionary in pl["portals"]:
		var axis: int = p["axis"]
		var e: float = p["e"]
		var side: int = p["side"]
		if side * (q[axis] - e) > 1e-6 and side * (a[axis] - e) <= 1e-6:
			var along: float = q[1 - axis]
			if along >= float(p["lo"]) - 1e-6 and along <= float(p["hi"]) + 1e-6:
				var to: String = p["to"]
				if _allowed_pl(_places[to], q):
					return {"region": to, "pos": q}
	if _allowed_pl(pl, q):
		return {"region": region, "pos": q}
	return null


static func _sub(region: String, a: Vector2, q: Vector2) -> Dictionary:
	var r: Variant = _try(region, a, q)
	if r != null:
		return r
	var dx := q.x - a.x
	var dz := q.y - a.y
	var first := Vector2(q.x, a.y) if absf(dx) >= absf(dz) else Vector2(a.x, q.y)
	var second := Vector2(a.x, q.y) if absf(dx) >= absf(dz) else Vector2(q.x, a.y)
	for c: Vector2 in [first, second]:
		if c.distance_to(a) > 1e-9:
			var r2: Variant = _try(region, a, c)
			if r2 != null:
				return r2
	return {"region": region, "pos": a}


## Move from `from` toward `to` on `region`, at most all the way: {"region", "pos"}. Walls, solids,
## furniture, holes and railings stop (sliding along them); only a portal changes the region.
## A position that is not allowed (a child sitting in a seat) first moves toward the nearest allowed place.
static func step(region: String, from: Vector2, to: Vector2) -> Dictionary:
	_ensure()
	region = _rn(region)
	if not _places.has(region):
		return {"region": region, "pos": from}
	var d := to - from
	var dist := d.length()
	if dist < 1e-9:
		return {"region": region, "pos": from}
	if not _allowed_pl(_places[region], from):
		var s := snap(region, from)
		if s.is_empty():
			return {"region": region, "pos": from}
		var sp: Vector2 = s["pos"]
		var to_s := sp - from
		if to_s.length() <= dist:
			return {"region": region, "pos": sp}
		return {"region": region, "pos": from + to_s.normalized() * dist}
	var n := maxi(1, ceili(dist / SUB))
	var seg := d / float(n)
	var cur_region := region
	var cur := from
	for i in n:
		var nxt := _sub(cur_region, cur, cur + seg)
		var np: Vector2 = nxt["pos"]
		if np.distance_to(cur) < 1e-9 and nxt["region"] == cur_region:
			break
		cur_region = nxt["region"]
		cur = np
	return {"region": cur_region, "pos": cur}


# ------------------------------------------------------------------ routing

static func _seg_free(pl: Dictionary, a: Vector2, b: Vector2) -> bool:
	if pl["has_inner"] and _in(pl["inner"], a) and _in(pl["inner"], b):
		for r: Rect2 in pl["ex"]:
			if _seg_hits_rect(a, b, r.grow(-1e-3)):
				return false
		for r: Rect2 in pl["exg"]:
			if _seg_hits_rect(a, b, r.grow(-1e-3)):
				return false
		for c: Vector3 in pl["circ"]:
			if _seg_hits_circle(a, b, c):
				return false
		return true
	# an end outside the inner rectangle (a door, a corridor): sample
	var span := a.distance_to(b)
	var n := maxi(1, ceili(span / 0.05))
	for i in n + 1:
		if not _allowed_pl(pl, a.lerp(b, float(i) / float(n))):
			return false
	return true


static func _vis_nodes(pi: int, i: int, j: int) -> bool:
	var lo := mini(i, j)
	var hi := maxi(i, j)
	var key := pi * 1000000 + lo * 1000 + hi
	if _vis.has(key):
		return _vis[key]
	var pl: Dictionary = _places[_order[pi]]
	var nodes: Array = pl["nodes"]
	var ok := _seg_free(pl, nodes[lo], nodes[hi])
	_vis[key] = ok
	return ok


## A goal exactly on a portal edge would flicker between the two places: move it 0.1 m clear of the edge.
static func _off_edges(region: String, p: Vector2) -> Vector2:
	var out := p
	for q: Dictionary in (_places[region] as Dictionary)["portals"]:
		var axis: int = q["axis"]
		var side: int = q["side"]
		var d: float = side * (float(q["e"]) - out[axis])
		var along: float = out[1 - axis]
		if d >= -1e-6 and d < 0.1 and along >= float(q["lo"]) - 1e-6 and along <= float(q["hi"]) + 1e-6:
			var moved := out
			moved[axis] = out[axis] - side * (0.1 - d)
			if _allowed_pl(_places[region], moved):
				out = moved
	return out


## A walkable path: waypoints [{"region", "pos"}], the last the (snapped) target; [] when there is none.
## Walk it with step(); a waypoint whose region differs from the child's is just past a portal edge.
static func route(from_region: String, from_pos: Vector2, to_region: String, to_pos: Vector2) -> Array:
	_ensure()
	from_region = _rn(from_region)
	to_region = _rn(to_region)
	if not _places.has(from_region) or not _places.has(to_region):
		return []
	var ss := snap(from_region, from_pos)
	var gs := snap(to_region, to_pos)
	if ss.is_empty() or gs.is_empty():
		return []
	var sp: Vector2 = ss["pos"]
	var gp: Vector2 = _off_edges(to_region, gs["pos"])
	var spi := _order.find(from_region)
	var gpi := _order.find(to_region)
	var start_key := Vector2i(-1, 0)
	var goal_key := Vector2i(-2, 0)
	if spi == gpi and _seg_free(_places[from_region], sp, gp):
		return [{"region": to_region, "pos": gp}]
	var g: Dictionary = {start_key: 0.0}
	var f: Dictionary = {start_key: sp.distance_to(gp)}
	var came: Dictionary = {}
	var open: Array = [start_key]
	var closed: Dictionary = {}
	var gpl: Dictionary = _places[to_region]
	var found := false
	var guard := 0
	while open.size() > 0 and guard < 4000:
		guard += 1
		var bi := 0
		var bf := INF
		for k in open.size():
			var fv: float = f[open[k]]
			if fv < bf:
				bf = fv
				bi = k
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == goal_key:
			found = true
			break
		closed[cur] = true
		var cg: float = g[cur]
		var cpi := spi
		var cpos := sp
		var cidx := -1
		if cur != start_key:
			cpi = cur.x
			cidx = cur.y
			cpos = ((_places[_order[cpi]] as Dictionary)["nodes"] as Array)[cidx]
		var cpl: Dictionary = _places[_order[cpi]]
		var nbs: Array = []
		var nodes: Array = cpl["nodes"]
		for j in nodes.size():
			if j == cidx:
				continue
			var ok := _seg_free(cpl, cpos, nodes[j]) if cidx < 0 else _vis_nodes(cpi, cidx, j)
			if ok:
				nbs.append([Vector2i(cpi, j), cpos.distance_to(nodes[j])])
		if cpi == gpi and _seg_free(gpl, cpos, gp):
			nbs.append([goal_key, cpos.distance_to(gp)])
		if cidx >= 0 and (cpl["links"] as Dictionary).has(cidx):
			var lk: Dictionary = (cpl["links"] as Dictionary)[cidx]
			nbs.append([Vector2i(_order.find(String(lk["to"])), int(lk["j"])), float(lk["cost"])])
		for nb: Array in nbs:
			var key: Vector2i = nb[0]
			if closed.has(key):
				continue
			var ng: float = cg + float(nb[1])
			if not g.has(key) or ng < float(g[key]) - 1e-9:
				g[key] = ng
				came[key] = cur
				var npos := gp
				if key != goal_key:
					npos = ((_places[_order[key.x]] as Dictionary)["nodes"] as Array)[key.y]
				f[key] = ng + npos.distance_to(gp)
				if not open.has(key):
					open.append(key)
	if not found:
		return []
	var keys: Array = [goal_key]
	var k2: Vector2i = goal_key
	while came.has(k2):
		k2 = came[k2]
		keys.push_front(k2)
	var out: Array = []
	var prev_place := spi
	var prev_idx := -1
	for key: Vector2i in keys:
		if key == start_key:
			continue
		if key == goal_key:
			out.append({"region": to_region, "pos": gp})
			continue
		if key.x != prev_place:
			var lk2: Dictionary = ((_places[_order[prev_place]] as Dictionary)["links"] as Dictionary)[prev_idx]
			out.append({"region": _order[key.x], "pos": lk2["cross"]})
		out.append({"region": _order[key.x], "pos": ((_places[_order[key.x]] as Dictionary)["nodes"] as Array)[key.y]})
		prev_place = key.x
		prev_idx = key.y
	# drop repeated points
	var clean: Array = []
	for w: Dictionary in out:
		if clean.is_empty() or (clean[-1] as Dictionary)["region"] != w["region"] or ((clean[-1] as Dictionary)["pos"] as Vector2).distance_to(w["pos"]) > 1e-4:
			clean.append(w)
	return _pull(from_region, sp, clean)


## Greedy string pulling inside each place: a waypoint is dropped when the straight line from the last kept
## point to a later one of the same place is free. Crossing waypoints (the region changes) stay.
static func _pull(from_region: String, start: Vector2, wps: Array) -> Array:
	var out: Array = []
	var anchor := start
	var anchor_region := from_region
	var i := 0
	while i < wps.size():
		var w: Dictionary = wps[i]
		var best := i
		if w["region"] == anchor_region:
			var pl: Dictionary = _places[anchor_region]
			var j := i + 1
			while j < wps.size() and (wps[j] as Dictionary)["region"] == anchor_region:
				if _seg_free(pl, anchor, (wps[j] as Dictionary)["pos"]):
					best = j
				j += 1
		var keep: Dictionary = wps[best]
		out.append(keep)
		anchor = keep["pos"]
		anchor_region = keep["region"]
		i = best + 1
	return out


# ------------------------------------------------------------------ picking

static func _building_of_occluder(o: Dictionary) -> Array:
	var out: Array = []
	var r: Rect2 = o["rect"]
	for id: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[id]
		if r.intersects(b["rect"]) and absf(float(b["roof"]) - float(o["y"])) < 0.3:
			out.append(id)
	return out


## The buildings a wall belongs to (a shop divider belongs to both neighbours).
static func _wall_buildings(w: Rect2) -> Array:
	var out: Array = []
	for id: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[id]
		if (b["rect"] as Rect2).grow(0.2).encloses(w):
			out.append(id)
	return out


## Which storeys are hidden while a child stands here: {building id: highest visible floor y}. A child on
## the ground inside a building hides everything above the ground floor; on a floor, terrace or stair of a
## building, everything above it. Pass it to pick() so a tap never lands on a floor that is not drawn.
static func storeys_hidden(region: String, pos: Vector2) -> Dictionary:
	_ensure()
	region = _rn(region)
	var out: Dictionary = {}
	if region == "":
		for id: String in CityMap.BUILDINGS:
			if _in((CityMap.BUILDINGS[id] as Dictionary)["rect"], pos, 0.0):
				out[id] = 0.0
		return out
	if not _places.has(region):
		return out
	var pl: Dictionary = _places[region]
	var b: String = pl["building"]
	var top := float(pl["y0"])
	if pl["kind"] == "stair":
		# an interior stair belongs to the storey it starts from; while on it, its upper end stays drawn
		top = maxf(float(pl["y0"]), float(pl["y1"]))
	if b != "":
		out[b] = top
	return out


static func _cand(best: Array, t: float, res: Dictionary) -> void:
	if t <= 1e-6:
		return
	var bt: float = best[0]
	# a tie (a wall's top level with a terrace) goes to the walkable thing
	if t < bt - 1e-5 or (t < bt + 1e-5 and not res.is_empty() and (best[1] as Dictionary).is_empty()):
		best[0] = t
		best[1] = res


## The drawn storeys are those whose base is at most the visible height + 0.05 (CityWorld.apply_hidden).
const HIDE_TOL := 0.05


static func _hidden(hide: Dictionary, building: String, base_y: float) -> bool:
	return building != "" and hide.has(building) and base_y > float(hide[building]) + HIDE_TOL


## Cast a ray (any length direction): the nearest thing it meets, when that is a walkable top.
## {"region", "pos": Vector2 xz} or {} (a roof, a wall, an underside or an edge is in front, or nothing).
## `hide` is storeys_hidden() of the viewing child: hidden storeys (their floors, interior stairs, roofs and walls) neither block nor pick; the walls of drawn storeys, the child's own included, still block.
static func pick(ray_origin: Vector3, ray_dir: Vector3, hide: Dictionary = {}) -> Dictionary:
	_ensure()
	var o := ray_origin
	var d := ray_dir
	var best: Array = [INF, {}]
	var half := CityMap.HALF
	# the ground plane
	if d.y < -1e-9:
		var t := -o.y / d.y
		var p := o + d * t
		if absf(p.x) <= half.x and absf(p.z) <= half.y:
			_cand(best, t, {"region": "", "pos": Vector2(p.x, p.z)})
	for id: String in _order:
		if id == "":
			continue
		var pl: Dictionary = _places[id]
		# a stair belongs to the storey it starts from (y0); a floor or terrace to the storey at its own height
		if _hidden(hide, String(pl["building"]), float(pl["y0"])):
			continue
		if pl["kind"] == "region":
			_pick_slab(best, o, d, pl)
		else:
			_pick_stair(best, o, d, pl)
	for oc: Dictionary in CityMap.OCCLUDERS:
		var hidden_roof := false
		for bid: String in _building_of_occluder(oc):
			if _hidden(hide, bid, float(oc["y"])):
				hidden_roof = true
		if hidden_roof or absf(d.y) < 1e-9:
			continue
		var y: float = oc["y"]
		var t2 := (y - o.y) / d.y
		var p2 := o + d * t2
		if _in(oc["rect"], Vector2(p2.x, p2.z), 0.0):
			_cand(best, t2, {})
	if PICK_WALLS:
		for w: Rect2 in CityMap.GROUND_WALLS:
			var owners := _wall_buildings(w)
			if owners.is_empty():
				var t0 := _ray_box(o, d, Vector3(w.position.x, 0.0, w.position.y), Vector3(w.end.x, 3.2, w.end.y))
				if t0 > 1e-6:
					_cand(best, t0, {})
				continue
			# one box per storey: the walls of a hidden storey are not there, the others are
			var bid2: String = owners[0]
			var floors: Array = (CityMap.BUILDINGS[bid2] as Dictionary)["floors"]
			for k in floors.size():
				var lo_y: float = floors[k]
				var hi_y: float = floors[k + 1] if k + 1 < floors.size() else float((CityMap.BUILDINGS[bid2] as Dictionary)["roof"])
				var shown := false
				for ob: String in owners:
					if not _hidden(hide, ob, lo_y):
						shown = true
				if not shown:
					continue
				var t3 := _ray_box(o, d, Vector3(w.position.x, lo_y, w.position.y), Vector3(w.end.x, hi_y, w.end.y))
				if t3 > 1e-6 and t3 < float(best[0]) and not _in_doorway(o + d * t3, bid2):
					_cand(best, t3, {})
	return best[1]


static func _in_doorway(p: Vector3, building: String) -> bool:
	for id: String in CityMap.REGIONS:
		var rd: Dictionary = CityMap.REGIONS[id]
		if rd["kind"] != "door" or rd["building"] != building:
			continue
		var y: float = rd["y"]
		if _in((rd["rect"] as Rect2).grow(0.02), Vector2(p.x, p.z), 0.0) and p.y >= y - 0.02 and p.y <= y + DOOR_OPEN:
			return true
	return false


## Entry parameter of a ray into a box, or -1 (miss, or the origin is inside).
static func _ray_box(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := -INF
	var t1 := INF
	for axis in 3:
		var dv: float = d[axis]
		var ov: float = o[axis]
		if absf(dv) < 1e-12:
			if ov < lo[axis] or ov > hi[axis]:
				return -1.0
		else:
			var u0 := (lo[axis] - ov) / dv
			var u1 := (hi[axis] - ov) / dv
			if u0 > u1:
				var tmp := u0
				u0 = u1
				u1 = tmp
			t0 = maxf(t0, u0)
			t1 = minf(t1, u1)
	if t0 > t1 or t0 <= 1e-6:
		return -1.0
	return t0


static func _in_slab_rect(pl: Dictionary, x: float, z: float) -> bool:
	if not _in(pl["rect"], Vector2(x, z), 0.0):
		return false
	for h: Rect2 in pl["holes"]:
		if _inside(h, Vector2(x, z), 1e-6):
			return false
	return true


static func _pick_slab(best: Array, o: Vector3, d: Vector3, pl: Dictionary) -> void:
	var y: float = pl["y0"]
	var r: Rect2 = pl["rect"]
	if absf(d.y) > 1e-9:
		var t := (y - o.y) / d.y
		var p := o + d * t
		if _in_slab_rect(pl, p.x, p.z):
			if d.y < 0.0:
				_cand(best, t, {"region": pl["id"], "pos": Vector2(p.x, p.z)})
			else:
				_cand(best, t, {})
		var tb := (y - CityMap.SLAB - o.y) / d.y
		var pb := o + d * tb
		if _in_slab_rect(pl, pb.x, pb.z):
			_cand(best, tb, {})
	# the four side faces of the slab (its edge) block
	var tbox := _ray_box(o, d, Vector3(r.position.x, y - CityMap.SLAB, r.position.y), Vector3(r.end.x, y, r.end.y))
	if tbox > 1e-6:
		var pe := o + d * tbox
		if absf(pe.y - y) > 1e-5 and absf(pe.y - (y - CityMap.SLAB)) > 1e-5:
			_cand(best, tbox, {})


static func _pick_stair(best: Array, o: Vector3, d: Vector3, pl: Dictionary) -> void:
	var r: Rect2 = pl["rect"]
	var y0: float = pl["y0"]
	var y1: float = pl["y1"]
	var up: String = pl["up"]
	var dy := y1 - y0
	# plane y = a + bx x + bz z
	var a := 0.0
	var bx := 0.0
	var bz := 0.0
	match up:
		"-z":
			bz = -dy / r.size.y
			a = y0 + dy * r.end.y / r.size.y
		"+z":
			bz = dy / r.size.y
			a = y0 - dy * r.position.y / r.size.y
		"-x":
			bx = -dy / r.size.x
			a = y0 + dy * r.end.x / r.size.x
		_:
			bx = dy / r.size.x
			a = y0 - dy * r.position.x / r.size.x
	var denom := d.y - bx * d.x - bz * d.z
	if absf(denom) < 1e-9:
		return
	for k in 2:
		var shift := 0.0 if k == 0 else CityMap.SLAB
		var t := (a - shift + bx * o.x + bz * o.z - o.y) / denom
		var p := o + d * t
		if _in(r, Vector2(p.x, p.z), 0.0):
			if k == 0 and d.y - bx * d.x - bz * d.z < 0.0:
				_cand(best, t, {"region": pl["id"], "pos": Vector2(p.x, p.z)})
			else:
				_cand(best, t, {})
