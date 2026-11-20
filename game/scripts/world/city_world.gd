## The miniature city district in the world (design/city-district.md): built once from CityMap, then
## the moving things (vehicles, the wheel and its gondolas, the carousel) are drawn at view_time().
##
## Node organisation (the owner relies on these names):
##   Ground                      roads, pavements, kerbs, markings, lawns, the white base plate (1 mesh)
##   Street/{Shell,Detail}       trees, lamps, planters, the bus shelter
##   Buildings/<id>/<level>      level = L0, L1, ... (CityMap floors) and Roof; meta "base_y";
##                               each holds Shell (walls, slabs, railings, furniture) and Detail (goods).
##                               Shop fronts (display windows, door, sign, awning) are in their L0; the
##                               coral tower's terrace and canopy in gym/L1; its pavilion in gym/Roof
##   Stairs/<id>                 exterior stairs (interior stairs live in their building's level)
##   Skywalks/<id>               deck, canopy and railings
##   Ferris/Base                 A-frames, platform, sign (static)
##   Ferris/Wheel                rims, spokes and hub, rotated about z by the wheel angle
##   Ferris/Gondola<i>           eight gondolas, kept level (gondola_transform)
##   (the carousel's plinth, fence and sign are part of Street)
##   Carousel/Turn               the turning deck, column, poles and canopy (rotation.y = carousel angle),
##                               with Turn/Horses: one MultiMesh of 8 bobbing horses
##   Moving/Vehicles/Vehicle<i>  one per CityMap.VEHICLES entry (meta "kind"), in its colour, forward +z
## Walkers and people are the people node's (city r2, A2). Everything ambient is drawn at view_time().
extends Node3D

const CityRulesScript := preload("res://scripts/core/city_rules.gd")

const CityMap := preload("res://scripts/core/city_map.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")

## A sensible distance for hiding small goods (set_detail_range); not applied by default, so the
## overview keeps every detail.
const DETAIL_RANGE := 35.0

var world: Node3D
var levels := {}                   # building id -> Array[Node3D] (L0.., Roof), meta "base_y"
var wheel: Node3D
var gondolas: Array[Node3D] = []
var vehicles: Array[Node3D] = []
var riders := {}                   # gondola index -> [peer ids], from the latest states
var _states := {}
var _built := false
var _accs := {}                    # node path -> [Acc shell, Acc detail]


func setup(w: Node3D) -> void:
	world = w


## Builds the whole district once (static: everything comes from CityMap).
func build() -> void:
	if _built:
		return
	_built = true
	_make_materials()
	for bid: String in CityMap.BUILDINGS:
		_level_nodes(bid)
	_ground()
	_buildings()
	_ceiling_lights()
	_regions()
	_stairs()
	_furniture()
	_seats()
	_street()
	_ferris()
	_commit()
	_carousel()
	_moving()
	_weather_nodes()
	_update_weather(true)


# ===================================================================== accumulators and levels

func _acc(path: String) -> Array:
	if not _accs.has(path):
		var glow := PropsCity.acc()
		var shell := PropsCity.acc()
		var detail := PropsCity.acc()
		shell.glow = glow
		detail.glow = glow
		_accs[path] = [shell, detail, glow]
	return _accs[path]


func _shell(path: String) -> PropsCity.Acc:
	return _acc(path)[0]


func _detail(path: String) -> PropsCity.Acc:
	return _acc(path)[1]


## The level node path of a building at a walking height ("Buildings/office/L1", ".../Roof").
static func level_path(bid: String, y: float) -> String:
	var b: Dictionary = CityMap.BUILDINGS[bid]
	var floors: Array = b["floors"]
	for k in floors.size():
		if absf(float(floors[k]) - y) < 0.05:
			return "Buildings/%s/L%d" % [bid, k]
	return "Buildings/%s/Roof" % bid


## Where a region's art goes: its building's level, or its own skywalk node.
static func region_path(rid: String) -> String:
	if rid == "ground":
		return "Street"
	var reg: Dictionary = CityMap.REGIONS[rid]
	var bid := String(reg["building"])
	if bid == "":
		return "Skywalks/" + rid
	return level_path(bid, float(reg["y"]))


## A ground thing goes in the building whose rect holds it, else the street.
static func ground_path(p: Vector2) -> String:
	var bid := PropsCity.building_at(p)
	return level_path(bid, 0.0) if bid != "" else "Street"


func _node(path: String) -> Node3D:
	var cur: Node3D = self
	for part in path.split("/"):
		var nx := cur.get_node_or_null(NodePath(part)) as Node3D
		if nx == null:
			nx = Node3D.new()
			nx.name = part
			cur.add_child(nx)
		cur = nx
	return cur


func _level_nodes(bid: String) -> void:
	var b: Dictionary = CityMap.BUILDINGS[bid]
	var floors: Array = b["floors"]
	var list: Array[Node3D] = []
	for k in floors.size():
		var n := _node("Buildings/%s/L%d" % [bid, k])
		n.set_meta("base_y", float(floors[k]))
		list.append(n)
	var r := _node("Buildings/%s/Roof" % bid)
	r.set_meta("base_y", float(b["roof"]))
	list.append(r)
	levels[bid] = list


func _commit() -> void:
	var mat := PropsCity.material()
	for path: String in _accs:
		var pair: Array = _accs[path]
		var shell: PropsCity.Acc = pair[0]
		var detail: PropsCity.Acc = pair[1]
		var glow: PropsCity.Acc = pair[2]
		if path == "Ground":
			shell.commit(self, "Ground", _ground_mat)
			detail.commit(self, "GroundDetail", _ground_mat)
			continue
		var n := _node(path)
		shell.commit(n, "Shell", mat)
		detail.commit(n, "Detail", mat)
		glow.commit(n, "Glow", _glow_mat)
	_accs.clear()


# ===================================================================== the ground

func _ground() -> void:
	var a := _shell("Ground")
	var hx := CityMap.HALF.x
	var hz := CityMap.HALF.y
	# a white plinth, so the block reads as a miniature on the white world
	a.span(Vector3(-hx, -0.5, -hz), Vector3(hx, 0.0, hz), PropsCity.col("white"))
	a.span(Vector3(-hx - 0.3, -0.8, -hz - 0.3), Vector3(hx + 0.3, -0.45, hz + 0.3), PropsCity.col("white", -0.15))
	# outer pavement, road, block pavement, the lot
	for r in _ring(CityMap.OUTER_PAVEMENT, CityMap.ROAD_OUTER):
		a.span(Vector3(r.position.x, -0.1, r.position.y), Vector3(r.end.x, 0.02, r.end.y), PropsCity.col("pavement"))
	for r in _ring(CityMap.ROAD_OUTER, CityMap.ROAD_INNER):
		a.span(Vector3(r.position.x, -0.1, r.position.y), Vector3(r.end.x, 0.01, r.end.y), PropsCity.col("road"))
	for r in _ring(CityMap.ROAD_INNER, CityMap.LOT):
		a.span(Vector3(r.position.x, -0.1, r.position.y), Vector3(r.end.x, 0.02, r.end.y), PropsCity.col("pavement"))
	var lot := CityMap.LOT
	a.span(Vector3(lot.position.x, -0.1, lot.position.y), Vector3(lot.end.x, 0.015, lot.end.y), PropsCity.col("ground"))
	# paving joints across both pavement rings
	_joints(a, CityMap.OUTER_PAVEMENT, CityMap.ROAD_OUTER, 1.5)
	_joints(a, CityMap.ROAD_INNER, CityMap.LOT, 1.5)
	# kerbs: just outside each pavement edge that meets the road
	_kerb_ring(a, CityMap.ROAD_INNER, true)
	_kerb_ring(a, CityMap.ROAD_OUTER, false)
	# lawns around the lot's trees
	for lr: Rect2 in [Rect2(-21.6, -0.6, 10.2, 2.2), Rect2(-6.4, 1.4, 2.8, 2.2), Rect2(3.6, 1.4, 2.8, 2.2), Rect2(20.9, -7.1, 2.0, 2.2), Rect2(20.9, 9.9, 2.0, 2.2)]:
		a.span(Vector3(lr.position.x, 0.0, lr.position.y), Vector3(lr.end.x, 0.022, lr.end.y), PropsCity.col("green", 0.2))
		a.span(Vector3(lr.position.x - 0.08, 0.0, lr.position.y - 0.08), Vector3(lr.end.x + 0.08, 0.018, lr.end.y + 0.08), PropsCity.col("kerb"))
	_markings(a)
	_paths(a)


## The paved pedestrian paths (CityMap.PATHS): banded pavers between kerb-stone edges, laid across the
## path's length.
func _paths(a: PropsCity.Acc) -> void:
	for r: Rect2 in CityMap.PATHS:
		var pieces: Array[Rect2] = [r.grow(-0.08)]
		PropsCity.slab(a, pieces, 0.024, PropsCity.col("pavement", -0.15), PropsCity.col("pavement", -0.15), PropsCity.col("cream"), "planks_z" if r.size.x >= r.size.y else "planks_x", 0.5)
		for e in _ring(r, r.grow(-0.08)):
			a.span(Vector3(e.position.x, -0.05, e.position.y), Vector3(e.end.x, 0.03, e.end.y), PropsCity.col("kerb"))


## The ring between an outer and an inner rect, as four rects.
static func _ring(outer: Rect2, inner: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y - outer.position.y),
		Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
		Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
		Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y)]
	return out


func _joints(a: PropsCity.Acc, outer: Rect2, inner: Rect2, step: float) -> void:
	var tone := PropsCity.col("kerb")
	for r in _ring(outer, inner):
		var along_x := r.size.x >= r.size.y
		var length := r.size.x if along_x else r.size.y
		var n := int(length / step)
		for i in range(1, n):
			var t := float(i) * length / float(n)
			if along_x:
				var x := r.position.x + t
				a.span(Vector3(x - 0.02, 0.0, r.position.y), Vector3(x + 0.02, 0.024, r.end.y), tone)
			else:
				var z := r.position.y + t
				a.span(Vector3(r.position.x, 0.0, z - 0.02), Vector3(r.end.x, 0.024, z + 0.02), tone)


## A 0.25 m kerb along a rect's edge, on the pavement side (inside the rect for the block's edge,
## outside it for the outer pavement), reaching 0.01 m over the road.
func _kerb_ring(a: PropsCity.Acc, r: Rect2, inside: bool) -> void:
	var k := PropsCity.col("kerb")
	var w := 0.25
	var g := r.grow(0.01) if inside else r.grow(w)
	var s := r.grow(-w) if inside else r.grow(-0.01)
	for p in _ring(g, s):
		a.span(Vector3(p.position.x, -0.05, p.position.y), Vector3(p.end.x, 0.06, p.end.y), k)


func _markings(a: PropsCity.Acc) -> void:
	var white := PropsCity.col("white")
	var skips: Array[Rect2] = []
	for cr: Rect2 in CityMap.CROSSINGS:
		skips.append(cr)
	var bay := Rect2(CityMap.BUS_BAY.x - 1.4, CityMap.BUS_BAY.y - 4.2, 2.8, 8.4)
	# solid edge lines 0.35 m inside both kerbs, broken at the crossings
	for r: Rect2 in [CityMap.ROAD_INNER.grow(0.4), CityMap.ROAD_OUTER.grow(-0.4)]:
		_outline(a, r, 0.1, white, skips, false)
	# a dashed centre line along the loop, skipping the crossings and the bus bay
	var centre := Rect2(CityMap.ROAD_LOOP[0], CityMap.ROAD_LOOP[2] - CityMap.ROAD_LOOP[0])
	var dash_skips: Array[Rect2] = skips.duplicate()
	dash_skips.append(bay)
	_outline(a, centre, 0.12, white, dash_skips, true)
	# zebra crossings
	for cr: Rect2 in CityMap.CROSSINGS:
		var across_z := absf(cr.get_center().y) > CityMap.ROAD_INNER.end.y
		var n := 6
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			if across_z:
				var x := lerpf(cr.position.x, cr.end.x, t)
				a.span(Vector3(x - 0.25, 0.0, cr.position.y + 0.5), Vector3(x + 0.25, 0.016, cr.end.y - 0.5), white)
			else:
				var z := lerpf(cr.position.y, cr.end.y, t)
				a.span(Vector3(cr.position.x + 0.5, 0.0, z - 0.25), Vector3(cr.end.x - 0.5, 0.016, z + 0.25), white)
	# the bus bay: a yellow box with a "BUS" bar at each end
	var y := PropsCity.col("yellow")
	var none: Array[Rect2] = []
	_outline(a, bay, 0.12, y, none, false)
	for z: float in [bay.position.y + 0.6, bay.end.y - 0.6]:
		a.span(Vector3(bay.position.x + 0.5, 0.0, z - 0.15), Vector3(bay.end.x - 0.5, 0.016, z + 0.15), y)


## An axis-aligned rectangle of lines (solid or dashed 1.5/1.5) on the road, minus the skip rects.
func _outline(a: PropsCity.Acc, r: Rect2, w: float, color: Color, skips: Array[Rect2], dashed: bool) -> void:
	var hw := w * 0.5
	var lines: Array[Array] = [
		[true, r.position.y, r.position.x, r.end.x], [true, r.end.y, r.position.x, r.end.x],
		[false, r.position.x, r.position.y, r.end.y], [false, r.end.x, r.position.y, r.end.y]]
	for ln in lines:
		var along_x: bool = ln[0]
		var cc: float = ln[1]
		var cuts: Array[Vector2] = []
		for s in skips:
			if along_x and cc >= s.position.y and cc <= s.end.y:
				cuts.append(Vector2(s.position.x, s.end.x))
			elif not along_x and cc >= s.position.x and cc <= s.end.x:
				cuts.append(Vector2(s.position.y, s.end.y))
		for iv in PropsCity.subtract(float(ln[2]) - hw, float(ln[3]) + hw, cuts):
			var pieces: Array[Vector2] = []
			if dashed:
				var u := iv.x + 0.75
				while u + 1.5 <= iv.y:
					pieces.append(Vector2(u, u + 1.5))
					u += 3.0
			else:
				pieces.append(iv)
			for p in pieces:
				if along_x:
					a.span(Vector3(p.x, 0.0, cc - hw), Vector3(p.y, 0.016, cc + hw), color)
				else:
					a.span(Vector3(cc - hw, 0.0, p.x), Vector3(cc + hw, 0.016, p.y), color)


# ===================================================================== buildings

func _buildings() -> void:
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		var rect: Rect2 = b["rect"]
		var floors: Array = b["floors"]
		var roof: float = b["roof"]
		var cname := PropsCity.body_key(bid)
		var shop := bool(b.get("shop", false))
		var color := PropsCity.col(cname)
		var liner := PropsCity.col(cname, 0.6)
		var trim := PropsCity.col(PropsCity.trim_key(bid))
		var walls := _walls_of(rect)
		var centre := rect.get_center()
		for k in floors.size():
			var base := float(floors[k])
			var top := float(floors[k + 1]) if k + 1 < floors.size() else roof - CityMap.SLAB
			var path := level_path(bid, base)
			var a := _shell(path)
			var d := _detail(path)
			for wr in walls:
				var along_x := wr.size.x >= wr.size.y
				var wc := wr.get_center()
				var inside := Vector2(0.0, signf(centre.y - wc.y)) if along_x else Vector2(signf(centre.x - wc.x), 0.0)
				var doors := _doors_in(wr, base)
				var windows: Array[Vector4] = []
				var outer_probe := wc - inside * (0.5 + (wr.size.y if along_x else wr.size.x))
				var exterior := PropsCity.building_at(outer_probe) == ""
				var front_wall := shop and along_x and wr.position.y >= rect.end.y - 0.5
				var back_of_shop := shop and along_x and not front_wall
				if front_wall:
					# a display window (glass near the street face, a niche of goods behind it)
					for wn in PropsCity.shop_windows(bid):
						if (wn["rect"] as Rect2).is_equal_approx(wr):
							windows.append(Vector4(wn["u0"], wn["u1"], PropsCity.DISPLAY_V.x, PropsCity.DISPLAY_V.y))
				elif exterior and not back_of_shop:
					var u_lo := wr.position.x if along_x else wr.position.y
					windows = PropsCity.window_row(u_lo, wr.size.x if along_x else wr.size.y, base, doors, _blocked(bid, base, wr, inside))
				# walls darken gently toward the ground (a depth cue), white trims and a deeper base band
				a.fade = Vector2(4.0, 0.1)
				PropsCity.wall(a, d, wr, base, top, color, liner, inside, doors, windows, front_wall)
				a.fade = Vector2.ZERO
				if exterior and k + 1 < floors.size():
					_band(a, wr, inside, top - 0.28, top - 0.12, PropsCity.col("white") if cname != "coral" else trim)
				if exterior and k == 0:
					_band(a, wr, inside, 0.0, 0.45, PropsCity.base_color(bid), 0.0 if front_wall else 0.06)
				if exterior and not front_wall:
					_pilasters(a, wr, inside, base, top, trim)
			# the floor of the ground storey, and the slab fronts on the open face
			if k == 0:
				_ground_floor(a, bid, rect)
			else:
				_front_band(a, rect, base, trim if cname == "coral" else color)
			if shop and k == 0:
				PropsCity.shop_front(a, d, bid, rect, roof)
		_roof(bid, rect, roof, cname)
		_front_signs(bid, rect)


## Along-wall ranges hidden by tall furniture standing against a wall's inner face on a storey (no
## window is cut behind a bookcase, a shelf or a mirror).
static func _blocked(bid: String, base: float, wr: Rect2, inside: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var b: Dictionary = CityMap.BUILDINGS[bid]
	var brect: Rect2 = b["rect"]
	var along_x := wr.size.x >= wr.size.y
	for f: Dictionary in CityMap.FURNITURE:
		if not PropsCity.WALL_KINDS.has(String(f["kind"])):
			continue
		var rid := String(f["region"])
		var fr: Rect2 = f["rect"]
		if rid == "ground":
			if base > 0.05 or not brect.has_point(fr.get_center()):
				continue
		elif String(CityMap.REGIONS[rid]["building"]) != bid or absf(float(CityMap.REGIONS[rid]["y"]) - base) > 0.05:
			continue
		var gap := 0.0
		if along_x:
			gap = fr.position.y - wr.end.y if inside.y > 0.0 else wr.position.y - fr.end.y
			if gap > -0.05 and gap < 0.45:
				out.append(Vector2(fr.position.x, fr.end.x))
		else:
			gap = fr.position.x - wr.end.x if inside.x > 0.0 else wr.position.x - fr.end.x
			if gap > -0.05 and gap < 0.45:
				out.append(Vector2(fr.position.y, fr.end.y))
	return out


## The building's share of GROUND_WALLS (each wall clipped to the building rect).
static func _walls_of(rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w: Rect2 in CityMap.GROUND_WALLS:
		if not w.intersects(rect):
			continue
		var i := w.intersection(rect)
		if i.size.x > 0.05 and i.size.y > 0.05:
			out.append(i)
	return out


## Door openings (u0, u1, v0, v1) in a wall at a storey base, from the door regions.
static func _doors_in(wr: Rect2, base: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var along_x := wr.size.x >= wr.size.y
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		if String(reg["kind"]) != "door" or absf(float(reg["y"]) - base) > 0.05:
			continue
		var dr: Rect2 = reg["rect"]
		if not dr.grow(0.01).intersects(wr):
			continue
		if along_x:
			out.append(Vector4(dr.position.x, dr.end.x, base, base + PropsCity.DOOR_H))
		else:
			out.append(Vector4(dr.position.y, dr.end.y, base, base + PropsCity.DOOR_H))
	return out


func _band(a: PropsCity.Acc, wr: Rect2, inside: Vector2, y0: float, y1: float, color: Color, ext := 0.06) -> void:
	var along_x := wr.size.x >= wr.size.y
	if along_x:
		var z := wr.position.y if inside.y > 0.0 else wr.end.y
		var zo := z - inside.y * 0.06
		a.span(Vector3(wr.position.x - ext, y0, minf(z, zo)), Vector3(wr.end.x + ext, y1, maxf(z, zo)), color)
	else:
		var x := wr.position.x if inside.x > 0.0 else wr.end.x
		var xo := x - inside.x * 0.06
		a.span(Vector3(minf(x, xo), y0, wr.position.y - ext), Vector3(maxf(x, xo), y1, wr.end.y + ext), color)


## Corner pilasters at both ends of an exterior wall, standing 0.05 proud of its outer face.
func _pilasters(a: PropsCity.Acc, wr: Rect2, inside: Vector2, y0: float, y1: float, color: Color) -> void:
	var along_x := wr.size.x >= wr.size.y
	for e in 2:
		if along_x:
			var x0 := wr.position.x if e == 0 else wr.end.x - 0.4
			var z := wr.position.y if inside.y > 0.0 else wr.end.y
			a.span(Vector3(x0, y0, minf(z, z - inside.y * 0.05)), Vector3(x0 + 0.4, y1, maxf(z, z - inside.y * 0.05)), color)
		else:
			var z0 := wr.position.y if e == 0 else wr.end.y - 0.4
			var x := wr.position.x if inside.x > 0.0 else wr.end.x
			a.span(Vector3(minf(x, x - inside.x * 0.05), y0, z0), Vector3(maxf(x, x - inside.x * 0.05), y1, z0 + 0.4), color)


## The slab's front on the open (+z) face: a band in the building colour under the floor line.
func _front_band(a: PropsCity.Acc, rect: Rect2, y: float, color: Color) -> void:
	a.span(Vector3(rect.position.x - 0.04, y - 0.26, rect.end.y), Vector3(rect.end.x + 0.04, y - 0.02, rect.end.y + 0.05), color)


func _ground_floor(a: PropsCity.Acc, bid: String, rect: Rect2) -> void:
	var pieces: Array[Rect2] = [rect]
	match bid:
		"office": PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("white"), PropsCity.col("blue", 0.6), "checker", 1.0)
		"cafe": PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("cream"), PropsCity.col("wood", 0.4), "checker", 0.5)
		"gym": PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("peach", 0.6), PropsCity.col("peach", 0.6), "plain")
		"corner_cafe": PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("cream"), PropsCity.col("peach", 0.6), "checker", 0.5)
		"icecream": PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("white"), PropsCity.col("blue", 0.6), "checker", 0.5)
		_: PropsCity.slab(a, pieces, 0.03, PropsCity.col("white", -0.15), PropsCity.col("wood", 0.4), PropsCity.col("wood", 0.2), "planks_z", 0.3)


## Roofs nobody walks on (the office, the shops) get a slab, parapet and roof clutter; walkable roofs
## get their slab from _regions and here only a fascia band.
func _roof(bid: String, rect: Rect2, roof: float, cname: String) -> void:
	var b: Dictionary = CityMap.BUILDINGS[bid]
	var path := "Buildings/%s/Roof" % bid
	var a := _shell(path)
	var d := _detail(path)
	var band: Color = PropsCity.col("roof")
	# the fascia stands proud only on sides with no neighbouring building (no coplanar overlaps)
	var ctr2 := rect.get_center()
	var gl := 0.05 if PropsCity.building_at(Vector2(rect.position.x - 0.2, ctr2.y)) == "" else 0.0
	var gr := 0.05 if PropsCity.building_at(Vector2(rect.end.x + 0.2, ctr2.y)) == "" else 0.0
	var gt := 0.05 if PropsCity.building_at(Vector2(ctr2.x, rect.position.y - 0.2)) == "" else 0.0
	var gb := 0.05 if PropsCity.building_at(Vector2(ctr2.x, rect.end.y + 0.2)) == "" else 0.0
	for r in _ring(rect.grow_individual(gl, gt, gr, gb), rect.grow(-0.05)):
		a.span(Vector3(r.position.x, roof - 0.26, r.position.y), Vector3(r.end.x, roof - 0.04, r.end.y), band)
	if b.has("roof_terrace"):
		return
	a.span(Vector3(rect.position.x, roof - CityMap.SLAB, rect.position.y), Vector3(rect.end.x, roof, rect.end.y), PropsCity.col("roof", 0.2))
	var ph := 0.5 if bid == "office" else 0.3
	for r in _ring(rect, rect.grow(-0.25)):
		a.span(Vector3(r.position.x, roof, r.position.y), Vector3(r.end.x, roof + ph, r.end.y), PropsCity.col(cname))
	for r in _ring(rect.grow(0.04), rect.grow(-0.29)):
		a.span(Vector3(r.position.x, roof + ph, r.position.y), Vector3(r.end.x, roof + ph + 0.06, r.end.y), PropsCity.col("roof"))
	var ctr := rect.get_center()
	if bid == "office":
		# air units, a water tank and a skylight
		for i in 2:
			var p := Vector3(ctr.x - 3.0 + float(i) * 2.0, roof, rect.position.y + 2.0)
			a.box(p + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), PropsCity.col("white", -0.15), 0.05)
			d.box(p + Vector3(0, 0.91, 0), Vector3(0.8, 0.04, 0.8), PropsCity.col("dark", 0.2))
		a.prism(Vector3(rect.end.x - 2.0, roof + 0.9, rect.position.y + 2.2), 0.8, 1.6, PropsCity.col("blue", -0.15), 8)
		a.prism(Vector3(rect.end.x - 2.0, roof + 1.75, rect.position.y + 2.2), 0.86, 0.1, PropsCity.col("white"), 8)
		for i in 4:
			var lp := Vector3(rect.end.x - 2.0 + (float(i % 2) - 0.5) * 1.0, roof + 0.05, rect.position.y + 2.2 + (float(i >> 1) - 0.5) * 1.0)
			a.box(lp, Vector3(0.12, 0.1, 0.12), PropsCity.col("dark"))
		a.span(Vector3(ctr.x - 1.5, roof, ctr.y), Vector3(ctr.x + 1.5, roof + 0.25, ctr.y + 3.0), PropsCity.col("white"))
		a.span(Vector3(ctr.x - 1.4, roof + 0.25, ctr.y + 0.1), Vector3(ctr.x + 1.4, roof + 0.29, ctr.y + 2.9), PropsCity.col("glass"))
	else:
		a.box(Vector3(ctr.x + 1.5, roof + 0.25, ctr.y - 1.0), Vector3(0.6, 0.5, 0.6), PropsCity.col("white", -0.15), 0.04)
		d.box(Vector3(ctr.x + 1.5, roof + 0.55, ctr.y - 1.0), Vector3(0.7, 0.08, 0.7), PropsCity.col("dark", 0.2))
		a.span(Vector3(ctr.x - 2.0, roof, ctr.y - 1.6), Vector3(ctr.x, roof + 0.18, ctr.y + 0.4), PropsCity.col("white"))
		a.span(Vector3(ctr.x - 1.9, roof + 0.18, ctr.y - 1.5), Vector3(ctr.x - 0.1, roof + 0.21, ctr.y + 0.3), PropsCity.col("glass"))


## Signs on the big buildings' fronts (the shops carry theirs on the fascia).
func _front_signs(bid: String, rect: Rect2) -> void:
	var b: Dictionary = CityMap.BUILDINGS[bid]
	if bool(b.get("shop", false)):
		return
	var roof: float = b["roof"]
	var path := "Buildings/%s/Roof" % bid
	var a := _shell(path)
	var save := a.xf
	match bid:
		"office":
			a.xf = Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, roof + 0.25, rect.end.y + 0.02))
			PropsCity.text_sign(a, Vector3(0, 0.55, 0), Vector2(3.4, 0.9), PropsCity.col("white"), PropsCity.col("blue", -0.15), "OFFICE", PropsCity.col("blue", -0.3))
		"cafe":
			a.xf = Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, roof, rect.end.y + 0.12))
			PropsCity.text_sign(a, Vector3(0, 2.88 - roof, 0), Vector2(2.2, 0.5), PropsCity.col("white"), PropsCity.col("yellow", -0.15), "CAFE", PropsCity.col("roof", -0.15))
			_awning(a, rect.size.x - 0.6, 2.55 - roof, "yellow")
		"gym":
			a.xf = Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x - 2.5, roof, rect.end.y + 0.08))
			PropsCity.text_sign(a, Vector3(0, 0.55, 0), Vector2(1.8, 0.8), PropsCity.col("white"), PropsCity.col("peach"), "GYM", PropsCity.col("roof", -0.15))
	a.xf = save


## A striped awning (local, at the frame's origin, hanging out toward +z from y0).
func _awning(a: PropsCity.Acc, width: float, y0: float, accent: String) -> void:
	var depth := 1.0
	var slope := atan2(0.35, depth)
	var stripes := int(width / 0.5)
	var sw := width / float(stripes)
	for i in stripes:
		var cx := -width * 0.5 + (float(i) + 0.5) * sw
		var cc: Color = PropsCity.col(accent) if i % 2 == 0 else PropsCity.col("white")
		a.box(Vector3(cx, y0 - 0.175, depth * 0.5 - 0.1), Vector3(sw, 0.06, sqrt(depth * depth + 0.1225)), cc, 0.0, Basis(Vector3.RIGHT, slope))
		a.box(Vector3(cx, y0 - 0.45, depth - 0.08), Vector3(sw, 0.18, 0.04), cc)


# ===================================================================== upper regions: slabs and railings

func _regions() -> void:
	var guards := PropsCity.guard_segments()
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		var rect: Rect2 = reg["rect"]
		var y: float = reg["y"]
		var kind := String(reg["kind"])
		var path := region_path(rid)
		var a := _shell(path)
		var cut: Array[Rect2] = []
		for h: Rect2 in reg["holes"]:
			for sid: String in CityMap.STAIRS:
				var st: Dictionary = CityMap.STAIRS[sid]
				if (st["rect"] as Rect2).intersects(h) and float(st["y0"]) < y - 0.05:
					cut.append(h)
		var pieces := PropsCity.rect_minus(rect, cut)
		var bid := String(reg["building"])
		match kind:
			"skywalk":
				var own: Array[Dictionary] = []
				for g in guards:
					if g["owner"] == rid and g["kind"] == "railing":
						own.append(g)
				PropsCity.skywalk(a, rect, y, own)
			"door":
				var along_x := rect.size.x >= rect.size.y
				var g := rect.grow_individual(0.0 if along_x else 0.03, 0.03 if along_x else 0.0, 0.0 if along_x else 0.03, 0.03 if along_x else 0.0)
				a.span(Vector3(g.position.x, y - 0.1, g.position.y), Vector3(g.end.x, y + 0.005, g.end.y), PropsCity.col("white", -0.15))
			"balcony":
				PropsCity.slab(a, pieces, y, PropsCity.col("white"), PropsCity.col("pavement"), PropsCity.col("pavement"), "plain")
				_cantilever(a, rect, y, PropsCity.col("blue"))
			"terrace":
				if rid == "gym_terrace":
					PropsCity.slab(a, pieces, y, PropsCity.col("white", -0.15), PropsCity.col("wood", 0.2), PropsCity.col("wood", 0.4), "planks_z", 0.3)
					_cantilever(a, rect, y, PropsCity.col("peach"))
					PropsCity.facade_canopy(a, rect.position.x, rect.end.x, rect.position.y, float(CityMap.BUILDINGS["gym"]["roof"]) - 0.4, rect.size.y - 0.05, "coral")
				elif bid == "cafe":
					PropsCity.slab(a, pieces, y, PropsCity.col("white", -0.15), PropsCity.col("wood", 0.2), PropsCity.col("wood", 0.4), "planks_z", 0.4)
				else:
					PropsCity.slab(a, pieces, y, PropsCity.col("white", -0.15), PropsCity.col("pavement"), PropsCity.col("white"), "checker", 1.0)
			_:
				if bid == "gym":
					PropsCity.slab(a, pieces, y, PropsCity.col("white", -0.15), PropsCity.col("peach", 0.6), PropsCity.col("white"), "checker", 1.0)
				else:
					PropsCity.slab(a, pieces, y, PropsCity.col("white", -0.15), PropsCity.col("wood", 0.4), PropsCity.col("wood", 0.2), "planks_x", 0.3)
		# hole rims: a thin white edge around every cut stair well
		for h in cut:
			for r in _ring(h.grow(0.04), h):
				a.span(Vector3(r.position.x, y - 0.24, r.position.y), Vector3(r.end.x, y + 0.01, r.end.y), PropsCity.col("white"))
		var post: Color = PropsCity.col("white", -0.15)
		var rail: Color = PropsCity.col("white")
		match bid:
			"office": post = PropsCity.col("blue")
			"cafe": post = PropsCity.col("yellow", -0.15)
			"gym": post = PropsCity.col("peach")
		for g in guards:
			if g["owner"] != rid or g["kind"] != "railing":
				continue
			PropsCity.railing(a, g["a"], g["b"], g["inward"], post, rail)
			# warm bulbs along the terraces' and the balcony's rails (lit at night)
			if rid in ["cafe_terrace", "gym_terrace", "gym_roof", "office_balcony"]:
				var p0: Vector3 = g["a"]
				var p1: Vector3 = g["b"]
				var inward: Vector2 = g["inward"]
				var off := Vector3(inward.x, 0, inward.y) * PropsCity.INSET
				var n := int(p0.distance_to(p1) / 0.6)
				for k in range(1, n):
					var q := p0.lerp(p1, float(k) / float(n)) + off
					a.lit().box(Vector3(q.x, q.y + PropsCity.RAIL_H + 0.05, q.z), Vector3(0.07, 0.07, 0.07), PropsCity.col("yellow", 0.4))
	_rooftop_lights()


## A slab that reaches out from a building's open front (its rect's -z edge is the facade): a coloured
## fascia on its three free edges and stepped brackets under it.
func _cantilever(a: PropsCity.Acc, rect: Rect2, y: float, color: Color) -> void:
	a.span(Vector3(rect.position.x - 0.04, y - 0.3, rect.end.y - 0.02), Vector3(rect.end.x + 0.04, y - 0.02, rect.end.y + 0.04), color)
	for x: float in [rect.position.x, rect.end.x]:
		a.span(Vector3(x - 0.04, y - 0.3, rect.position.y), Vector3(x + 0.04, y - 0.02, rect.end.y), color)
	var xs: Array[float] = [rect.position.x + 0.25, rect.get_center().x, rect.end.x - 0.25]
	PropsCity.corbels(a, xs, rect.position.y, rect.end.y, y, PropsCity.col("white", -0.15))
	# flower boxes hung on the outside of the front railing
	var n := int(rect.size.x / 2.0)
	for i in n:
		var x := rect.position.x + (float(i) + 0.5) * rect.size.x / float(n)
		a.span(Vector3(x - 0.45, y + 0.55, rect.end.y + 0.01), Vector3(x + 0.45, y + 0.78, rect.end.y + 0.25), PropsCity.col("white"))
		a.span(Vector3(x - 0.42, y + 0.78, rect.end.y + 0.04), Vector3(x + 0.42, y + 0.92, rect.end.y + 0.22), PropsCity.col("green"))
		for k in 3:
			var fx := x - 0.3 + float(k) * 0.3
			a.span(Vector3(fx - 0.06, y + 0.92, rect.end.y + 0.08), Vector3(fx + 0.06, y + 1.0, rect.end.y + 0.18), PropsCity.col("peach", 0.2) if (i + k) % 2 == 0 else PropsCity.col("yellow"))


## The rooftop restaurant's string lights: four tall corner poles and sagging strings of bulbs.
func _rooftop_lights() -> void:
	var reg: Dictionary = CityMap.REGIONS["gym_roof"]
	var r: Rect2 = reg["rect"]
	var y: float = reg["y"]
	var path := region_path("gym_roof")
	var a := _shell(path)
	var d := _detail(path)
	var h := 2.6
	var corners: Array[Vector3] = []
	for p: Vector2 in [Vector2(r.position.x + 0.05, r.position.y + 0.05), Vector2(r.end.x - 0.05, r.position.y + 0.05), Vector2(r.end.x - 0.05, r.end.y - 0.05), Vector2(r.position.x + 0.05, r.end.y - 0.05)]:
		a.box(Vector3(p.x, y + h * 0.5, p.y), Vector3(0.08, h, 0.08), PropsCity.col("dark"))
		corners.append(Vector3(p.x, y + h - 0.05, p.y))
	for i in 4:
		var p0 := corners[i]
		var p1 := corners[(i + 1) % 4]
		var n := 12
		var prev := p0
		for k in range(1, n + 1):
			var t := float(k) / float(n)
			var q := p0.lerp(p1, t) - Vector3(0, sin(t * PI) * 0.45, 0)
			d.beam(prev, q, 0.02, 0.02, PropsCity.col("dark"))
			if k < n:
				d.box(q - Vector3(0, 0.06, 0), Vector3(0.08, 0.1, 0.08), PropsCity.col("cream") if k % 2 == 0 else PropsCity.col("yellow", 0.4), 0.02)
			prev = q


# ===================================================================== stairs

func _stairs() -> void:
	for sid: String in CityMap.STAIRS:
		var st: Dictionary = CityMap.STAIRS[sid]
		var r: Rect2 = st["rect"]
		var bid := PropsCity.building_at(r.get_center())
		var near := bid if bid != "" else _nearest_building(r.get_center())
		var path := level_path(bid, float(st["y0"])) if bid != "" else "Stairs/" + sid
		PropsCity.stair(_shell(path), st, PropsCity.col(PropsCity.body_key(near)), PropsCity.col("cream"), PropsCity.col("white"), PropsCity.base_color(near), bid == "")


static func _nearest_building(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for bid: String in CityMap.BUILDINGS:
		var r: Rect2 = CityMap.BUILDINGS[bid]["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if q.distance_to(p) < bd:
			bd = q.distance_to(p)
			best = bid
	return best


# ===================================================================== furniture, seats and townsfolk

func _furniture() -> void:
	var all: Array = []
	all.append_array(CityMap.FURNITURE)
	all.append_array(PropsCity.EXTRA_FURNITURE)
	for f: Dictionary in all:
		var rect: Rect2 = f["rect"]
		var rid := String(f["region"])
		var path := ground_path(rect.get_center()) if rid == "ground" else region_path(rid)
		var y := 0.03 if rid == "ground" and path != "Street" else (0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"]))
		var kind := String(f["kind"])
		var theme := furniture_theme(rid, rect)
		var front := ""
		if PropsCity.WALL_KINDS.has(kind):
			front = _wall_front(rect, rid)
		PropsCity.furniture(_shell(path), _detail(path), kind, rect, y, theme, front)
	_flowerpots()
	# the rooftop restaurant's pavilion over its posts
	var posts := Rect2()
	var first := true
	var prid := ""
	for f: Dictionary in CityMap.FURNITURE:
		if String(f["kind"]) == "pavilion_post":
			posts = f["rect"] if first else posts.merge(f["rect"])
			first = false
			prid = String(f["region"])
	if not first:
		var pp := region_path(prid)
		PropsCity.pergola(_shell(pp), _detail(pp), posts, float(CityMap.REGIONS[prid]["y"]))


## Flowerpots (art only, small): either side of every shop door against the facade, and in the office's
## free corners on each upper floor.
const POTS := [
	{"region": "office_l1", "pos": Vector2(-11.75, -13.35)}, {"region": "office_l1", "pos": Vector2(-22.35, -2.4)},
	{"region": "office_l2", "pos": Vector2(-11.75, -13.35)}, {"region": "office_l2", "pos": Vector2(-22.35, -2.4)},
	{"region": "office_l2", "pos": Vector2(-11.7, -2.4)}, {"region": "ground", "pos": Vector2(-11.75, -13.35)},
	{"region": "gym_terrace", "pos": Vector2(7.6, -1.75)}, {"region": "cafe_terrace", "pos": Vector2(2.6, -1.4)},
]


func _flowerpots() -> void:
	var k := 0
	for shop: String in CityMap.SHOP_DOORS:
		var door: Vector2 = CityMap.SHOP_DOORS[shop]
		var fz := (CityMap.BUILDINGS[shop]["rect"] as Rect2).end.y
		for x: float in [door.x - 0.32, door.y + 0.32]:
			var a := _shell("Street")
			var d := _detail("Street")
			a.xf = Transform3D(Basis.IDENTITY, Vector3(x, 0.02, fz + 0.17))
			d.xf = a.xf
			PropsCity.flowerpot(a, d, k)
			a.xf = Transform3D.IDENTITY
			d.xf = Transform3D.IDENTITY
			k += 1
	for p: Dictionary in POTS:
		var rid := String(p["region"])
		var pos: Vector2 = p["pos"]
		var path := ground_path(pos) if rid == "ground" else region_path(rid)
		var y := 0.03 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
		var a := _shell(path)
		var d := _detail(path)
		a.xf = Transform3D(Basis.IDENTITY, Vector3(pos.x, y, pos.y))
		d.xf = a.xf
		PropsCity.flowerpot(a, d, k)
		a.xf = Transform3D.IDENTITY
		d.xf = Transform3D.IDENTITY
		k += 1


## How a furniture item is dressed: the shop, building or terrace it stands in.
static func furniture_theme(rid: String, rect: Rect2) -> String:
	match rid:
		"gym_roof": return "restaurant"
		"cafe_terrace", "gym_terrace": return rid
	if rid != "ground":
		return String(CityMap.REGIONS[rid]["building"])
	var bid := PropsCity.building_at(rect.get_center())
	return bid if bid != "" else _nearest_building(rect.get_center())


## The side a wall-standing item faces: into its building, across its short side.
static func _wall_front(rect: Rect2, rid: String) -> String:
	var bid := PropsCity.building_at(rect.get_center()) if rid == "ground" else String(CityMap.REGIONS[rid]["building"])
	if bid == "":
		return "+z"
	var bc := (CityMap.BUILDINGS[bid]["rect"] as Rect2).get_center()
	var c := rect.get_center()
	if rect.size.x < rect.size.y:
		return "+x" if c.x < bc.x else "-x"
	return "+z" if c.y < bc.y else "-z"


## A chair under every seat interaction (desks bring their own), and the seated townsfolk on theirs.
func _seats() -> void:
	for iid: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[iid]
		var kind := String(it["kind"])
		if kind != "seat":
			continue
		var rid := String(it["region"])
		var style := _seat_style(rid)
		var path := ground_path(it["pos"]) if rid == "ground" else region_path(rid)
		var a := _shell(path)
		var save := a.xf
		a.xf = _floor_offset(seat_transform(iid), rid, path)
		PropsCity.chair(a, style)
		a.xf = save
	# chairs for the people's places that have no drawn seat yet (PropsCity.NPC_PLACES)
	for np: Dictionary in PropsCity.NPC_PLACES:
		if not bool(np.get("chair", false)):
			continue
		var rid := String(np["region"])
		var pos: Vector2 = np["pos"]
		var path := ground_path(pos) if rid == "ground" else region_path(rid)
		var y := 0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
		var a := _shell(path)
		var save := a.xf
		a.xf = _floor_offset(Transform3D(Basis(Vector3.UP, float(np["ry"])), Vector3(pos.x, y, pos.y)), rid, path)
		PropsCity.chair(a, _seat_style(rid))
		a.xf = save


static func _seat_style(rid: String) -> String:
	match rid:
		"cafe_terrace": return "terrace"
		"gym_roof": return "restaurant"
	return "cafe"


## Ground things inside a building stand on its 3 cm floor.
static func _floor_offset(xf: Transform3D, rid: String, path: String) -> Transform3D:
	if rid == "ground" and path != "Street":
		return Transform3D(xf.basis, xf.origin + Vector3(0, 0.03, 0))
	return xf


# ===================================================================== the street

func _street() -> void:
	var a := _shell("Street")
	var d := _detail("Street")
	var tree_i := 3
	var bed_i := 0
	var banners: Array[String] = ["coral", "blue", "yellow"]
	var li := 0
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		var kind := String(s["kind"])
		var at := Vector3()
		if s.has("at"):
			var p: Vector2 = s["at"]
			at = Vector3(p.x, 0.0, p.y)
		match kind:
			"tree":
				a.xf = Transform3D(Basis(Vector3.UP, float(tree_i) * 0.7), at)
				d.xf = a.xf
				PropsCity.tree(a, d, tree_i)
				tree_i += 1
			"lamp":
				a.xf = Transform3D(Basis.IDENTITY, at)
				d.xf = a.xf
				PropsCity.lamp(a, d, banners[li % banners.size()])
				li += 1
			"planter":
				var r: Rect2 = s["rect"]
				var fr := PropsCity.frame(r, 0.0, "+z")
				a.xf = fr[0]
				d.xf = fr[0]
				PropsCity.planter(a, d, float(fr[1]), float(fr[2]), "street")
			"bus_shelter":
				var r: Rect2 = s["rect"]
				var fr := PropsCity.frame(r, 0.0, "-x")
				a.xf = fr[0]
				d.xf = fr[0]
				PropsCity.bus_shelter(a, d, float(fr[1]), float(fr[2]))
			"flower_bed":
				var r: Rect2 = s["rect"]
				var fr := PropsCity.frame(r, 0.0, "+z" if r.size.x >= r.size.y else "+x")
				a.xf = fr[0]
				d.xf = fr[0]
				PropsCity.flower_bed(a, d, float(fr[1]), float(fr[2]), bed_i)
				bed_i += 1
		a.xf = Transform3D.IDENTITY
		d.xf = Transform3D.IDENTITY
	# the carousel's fixed plinth, fence and sign (its turning part is Carousel/Turn)
	PropsCity.carousel_base(a, carousel_gap_dir())
	# r3: slim street lamps along both pavement loops, around the carousel and beside the bus stops
	for lp in PropsCity.STREET_LAMPS:
		a.xf = Transform3D(Basis.IDENTITY, Vector3(lp.x, 0.02, lp.y))
		PropsCity.lamp_slim(a)
	# a BUS STOP sign and a small shelter at every bus stop, on the outer pavement
	for xf in bus_stop_frames():
		a.xf = xf
		d.xf = xf
		PropsCity.bus_stop(a, d)
	a.xf = Transform3D.IDENTITY
	d.xf = Transform3D.IDENTITY


# ===================================================================== the Ferris wheel

func _ferris() -> void:
	var root := _node("Ferris")
	var base := PropsCity.acc()
	var base_glow := PropsCity.acc()
	base.glow = base_glow
	PropsCity.ferris_base(base)
	base.commit(root, "Base", PropsCity.material())
	base_glow.commit(root, "BaseGlow", _glow_mat)
	wheel = Node3D.new()
	wheel.name = "Wheel"
	wheel.position = CityMap.FERRIS["hub"]
	root.add_child(wheel)
	var wa := PropsCity.acc()
	var wg := PropsCity.acc()
	wa.glow = wg
	PropsCity.ferris_wheel(wa)
	wa.commit(wheel, "Mesh", PropsCity.material())
	wg.commit(wheel, "Glow", _glow_mat)
	for i in int(CityMap.FERRIS["gondolas"]):
		var g := Node3D.new()
		g.name = "Gondola%d" % i
		g.transform = gondola_transform(i, 0.0)
		root.add_child(g)
		var ga := PropsCity.acc()
		PropsCity.gondola(ga, i)
		ga.commit(g, "Mesh", _cabin_mat)
		gondolas.append(g)


## A gondola's rim angle (radians, in the wheel's x-y plane): gondola 0 is at the bottom at angle 0,
## and a positive wheel angle turns the wheel counter-clockwise as seen from the camera (+z).
static func gondola_angle(i: int, angle: float) -> float:
	return -PI * 0.5 + angle + TAU * float(i) / float(CityMap.FERRIS["gondolas"])


## Where gondola i hangs at a wheel angle: its pivot on the rim, level (identity basis).
## The gondola's floor is CityMap.FERRIS.hang below this point.
static func gondola_transform(i: int, angle: float) -> Transform3D:
	var hub: Vector3 = CityMap.FERRIS["hub"]
	var r: float = CityMap.FERRIS["radius"]
	var a := gondola_angle(i, angle)
	return Transform3D(Basis.IDENTITY, hub + Vector3(cos(a) * r, sin(a) * r, 0.0))


## Where a rider sits in gondola i (slot 0 on the west bench facing east, slot 1 facing west),
## at the gondola floor; the avatar's sitting pose puts it on the 0.3 m bench.
static func rider_transform(i: int, angle: float, slot: int) -> Transform3D:
	var g := gondola_transform(i, angle)
	var sx := -0.5 if slot % 2 == 0 else 0.5
	var ry := PI * 0.5 if slot % 2 == 0 else -PI * 0.5
	return Transform3D(Basis(Vector3.UP, ry), g.origin + Vector3(sx, -float(CityMap.FERRIS["hang"]), 0.0))


# ===================================================================== interactions

## Where an avatar sits or stands for an INTERACTIONS entry: at its pos on its region's height,
## facing the table, machine or counter it uses (the nearest furniture or solid on its level).
static func seat_transform(interaction_id: String) -> Transform3D:
	var it: Dictionary = CityMap.INTERACTIONS.get(interaction_id, {})
	if it.is_empty():
		return Transform3D.IDENTITY
	return _facing_transform(String(it["region"]), it["pos"], String(it["kind"]))


static func _facing_transform(rid: String, pos: Vector2, kind: String) -> Transform3D:
	var y := 0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
	var dir := Vector2(0, -1)
	if kind == "ride":
		var hub: Vector3 = CityMap.FERRIS["hub"]
		dir = Vector2(0.0, signf(hub.z - pos.y))
	else:
		var rects: Array[Rect2] = []
		for f: Dictionary in CityMap.FURNITURE:
			if String(f["region"]) == rid:
				rects.append(f["rect"])
		if rid == "ground":
			for s: Dictionary in CityMap.GROUND_SOLIDS:
				if s.has("rect") and String(s["kind"]) != "stair_base":
					rects.append(s["rect"])
		var best := INF
		for r in rects:
			var q := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
			var dist := q.distance_to(pos)
			if dist < best:
				best = dist
				# inside a machine's footprint: face its console at -z
				dir = (q - pos).normalized() if dist > 0.02 else Vector2(0, -1)
	var ry := atan2(dir.x, dir.y)
	return Transform3D(Basis(Vector3.UP, ry), Vector3(pos.x, y, pos.y))


# ===================================================================== cutaways and level of detail

## Hides every storey, slab and roof of `building` above `level_y` (the storey the child is on stays,
## with the floor it stands on). building "" shows everything again.
func set_cutaway(level_y: float, building: String) -> void:
	for bid: String in levels:
		for n: Node3D in levels[bid]:
			n.visible = building != bid or float(n.get_meta("base_y", 0.0)) <= level_y + 0.05


## The same from CityNav.storeys_hidden(region, pos) ({building id: highest visible floor y}), so the
## drawn storeys always match the pickable ones. An empty dictionary shows everything.
func apply_hidden(hidden: Dictionary) -> void:
	for bid: String in levels:
		for n: Node3D in levels[bid]:
			n.visible = not hidden.has(bid) or float(n.get_meta("base_y", 0.0)) <= float(hidden[bid]) + 0.05


## Hides the small goods (every "Detail" mesh) beyond `range_m` from the camera; 0 shows them always.
func set_detail_range(range_m: float) -> void:
	for n in find_children("Detail", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = range_m
		mi.visibility_range_end_margin = 4.0 if range_m > 0.0 else 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# ===================================================================== moving things (r2)

func _moving() -> void:
	var vroot := _node("Moving/Vehicles")
	for i in CityMap.VEHICLES.size():
		var spec: Dictionary = CityMap.VEHICLES[i]
		var v := _make_vehicle(String(spec["kind"]), i)
		vroot.add_child(v)
		vehicles.append(v)
		var lp := _loop_at(CityMap.ROAD_LOOP, float(spec["start"]))
		v.position = Vector3(lp[0].x, 0.0, lp[0].y)
		v.rotation.y = atan2(lp[1].x, lp[1].y)


## A vehicle in its CityMap.VEHICLES colour (buses and cars alike).
func _make_vehicle(kind: String, i: int) -> Node3D:
	var paint := Color(0, 0, 0, 0)
	if i < CityMap.VEHICLES.size():
		paint = (CityMap.VEHICLES[i] as Dictionary).get("color", paint)
	var v := PropsCity.bus(paint) if kind == "bus" else PropsCity.car(i, paint)
	v.name = "Vehicle%d" % i
	v.set_meta("kind", kind)
	return v


## A point and direction a fraction t along a closed loop (by length).
static func _loop_at(loop: Array, t: float) -> Array[Vector2]:
	var total := 0.0
	for i in loop.size():
		total += (loop[i] as Vector2).distance_to(loop[(i + 1) % loop.size()])
	var s := fposmod(t, 1.0) * total
	for i in loop.size():
		var p0: Vector2 = loop[i]
		var p1: Vector2 = loop[(i + 1) % loop.size()]
		var seg := p0.distance_to(p1)
		if s <= seg:
			var hit: Array[Vector2] = [p0.lerp(p1, s / seg), (p1 - p0).normalized()]
			return hit
		s -= seg
	var first: Array[Vector2] = [loop[0] as Vector2, Vector2(1, 0)]
	return first


## The latest shared states (City's client form): {"time", "ferris_angle", "vehicles": [{"kind", "pos",
## "ry", "s", "v", "stopped", optional "dwell"}], "riders": {gondola: [peers]}, ...}. Walkers and people
## are drawn by the people node (A2), not here.
func set_states(states: Dictionary) -> void:
	_states = states
	riders = states.get("riders", {})


# ===================================================================== view time, pause and resume

## The view is at most this many times faster than the clock while it catches up after a pause.
const CATCH_UP := 3.0
## How long vehicles glide from their frozen pose to the live one on resume (s).
const RESUME_GLIDE := 0.6

## Optional clock for tests (a Callable returning seconds); otherwise the City's estimated clock.
var clock := Callable()
var _view := 0.0
var _view_ok := false
var _paused := false
var _glide := 0.0
var _shown := {}                   # vehicle index -> [Vector3 pos, float ry] as last drawn
var _frozen := {}                  # vehicle index -> [Vector3 pos, float ry] when resumed


## The shared city clock as this device estimates it.
func city_clock() -> float:
	if clock.is_valid():
		return float(clock.call())
	var city := get_node_or_null("/root/City") if is_inside_tree() else null
	if city and city.has_method("est_time"):
		return float(city.call("est_time"))
	return float(_states.get("time", 0.0))


## The time everything ambient on this screen is drawn at: the city clock, except while paused (frozen)
## and just after (it runs up to CATCH_UP times faster, eased, until it meets the clock again).
func view_time() -> float:
	return _view if _view_ok else city_clock()


## Freezes (true) or releases (false) the view time on this screen only; the shared city keeps running.
func set_paused(on: bool) -> void:
	if on == _paused:
		return
	if not _view_ok:
		_view = city_clock()
		_view_ok = true
	_paused = on
	if not on:
		_glide = RESUME_GLIDE
		_frozen = _shown.duplicate(true)


func is_paused() -> bool:
	return _paused


## Moves the view time on by one frame (`delta` real seconds).
func advance_view(delta: float) -> void:
	var c := city_clock()
	if not _view_ok:
		_view = c
		_view_ok = true
		return
	if _paused:
		return
	var lag := c - _view
	if lag <= 0.0005:
		_view = c        # in step (or the city's clock started afresh)
		return
	# catching up: faster while far behind, easing back toward the clock's own pace as it closes in
	var rate := clampf(1.0 + (CATCH_UP - 1.0) * smoothstep(0.0, 1.5, lag), 1.15, CATCH_UP)
	_view = minf(c, _view + rate * delta)


## The wheel's angle at a clock time (CityRules' convention: gondola 0 at the bottom at 0).
static func ferris_angle_at(t: float) -> float:
	return CityRulesScript.gondola_angle(0, t)


## The wheel's angle as drawn now (use it to seat riders exactly in the drawn gondolas).
func ferris_angle_now() -> float:
	return ferris_angle_at(view_time())


func _process(delta: float) -> void:
	if not _built:
		return
	advance_view(delta)
	_update_weather()
	_follow_rain()
	var t := view_time()
	var angle := ferris_angle_at(t)
	if wheel:
		wheel.rotation.z = angle
	for i in gondolas.size():
		gondolas[i].transform = gondola_transform(i, angle)
	_pose_carousel(t)
	_pose_vehicles(delta)


## Vehicles: drawn from the shared state, eased between packets (extrapolated along the road by their
## speed); frozen while paused; on resume they glide from the frozen pose to the live one.
func _pose_vehicles(delta: float) -> void:
	if _paused:
		return
	var vs: Array = _states.get("vehicles", [])
	var now := city_clock()
	var st_time := float(_states.get("time", now))
	if _glide > 0.0:
		_glide = maxf(0.0, _glide - delta)
	for i in vs.size():
		var st: Dictionary = vs[i]
		var kind := String(st.get("kind", "car"))
		if i >= vehicles.size() or String(vehicles[i].get_meta("kind", "")) != kind:
			var nv := _make_vehicle(kind, i)
			_node("Moving/Vehicles").add_child(nv)
			if i < vehicles.size():
				vehicles[i].queue_free()
				vehicles[i] = nv
			else:
				vehicles.append(nv)
			_shown.erase(i)
		var target := _live_pose(i, st, now - st_time)
		var pos: Vector3 = target[0]
		var ry: float = target[1]
		if _glide > 0.0 and _frozen.has(i):
			var k := smoothstep(0.0, 1.0, 1.0 - _glide / RESUME_GLIDE)
			var from: Array = _frozen[i]
			pos = (from[0] as Vector3).lerp(pos, k)
			ry = lerp_angle(float(from[1]), ry, k)
		elif _shown.has(i):
			var prev: Array = _shown[i]
			var p0: Vector3 = prev[0]
			if p0.distance_to(pos) < 6.0:
				var f := 1.0 - exp(-14.0 * delta)
				pos = p0.lerp(pos, f)
				ry = lerp_angle(float(prev[1]), ry, f)
		var v := vehicles[i]
		v.visible = true
		v.position = pos
		v.rotation.y = ry
		_shown[i] = [pos, ry]
	for i in range(vs.size(), vehicles.size()):
		vehicles[i].visible = false


## A vehicle's live pose: along the road from its arc position and speed when the state has them
## (extrapolated by up to 0.5 s since the packet), else the state's pos and ry.
func _live_pose(i: int, st: Dictionary, since: float) -> Array:
	if st.has("s") and i < CityMap.VEHICLES.size():
		var speed := 0.0 if bool(st.get("stopped", false)) or float(st.get("dwell", 0.0)) > 0.0 else float(st.get("v", 0.0))
		var pose: Dictionary = CityRulesScript.vehicle_pose(i, float(st["s"]) + speed * clampf(since, 0.0, 0.5))
		var p: Vector2 = pose["pos"]
		return [Vector3(p.x, 0.0, p.y), float(pose["ry"])]
	return [_v3(st.get("pos", Vector3.ZERO)), float(st.get("ry", 0.0))]


## Positions from the shared state may be ground points (Vector2 x, z) or 3D points (owner integration, city r1).
static func _v3(p: Variant) -> Vector3:
	if p is Vector2:
		return Vector3((p as Vector2).x, 0.0, (p as Vector2).y)
	return p as Vector3


# ===================================================================== the carousel (r2)

var carousel_turn: Node3D
var _horses: MultiMeshInstance3D
var horse_xf: Array[Transform3D] = []      # the horses' transforms last handed to the MultiMesh (Turn frame)


func _carousel() -> void:
	var root := _node("Carousel")
	var c: Vector2 = CityMap.CAROUSEL["center"]
	root.set_meta("note", "the fixed base is in Street")
	carousel_turn = Node3D.new()
	carousel_turn.name = "Turn"
	carousel_turn.position = Vector3(c.x, 0.0, c.y)
	root.add_child(carousel_turn)
	var ta := PropsCity.acc()
	var tg := PropsCity.acc()
	ta.glow = tg
	PropsCity.carousel_turn(ta)
	ta.commit(carousel_turn, "Mesh", PropsCity.material())
	tg.commit(carousel_turn, "Glow", _glow_mat)
	var ha := PropsCity.acc()
	PropsCity.carousel_horse(ha)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ha.build_mesh()
	mm.instance_count = int(CityMap.CAROUSEL["horses"])
	for i in mm.instance_count:
		mm.set_instance_color(i, CityMap.CABIN_COLORS[i % CityMap.CABIN_COLORS.size()])
	_horses = MultiMeshInstance3D.new()
	_horses.name = "Horses"
	_horses.multimesh = mm
	_horses.material_override = PropsCity.material()
	carousel_turn.add_child(_horses)
	_pose_carousel(0.0)


## The side the fence opens on (PropsCity.carousel_gap_dir).
static func carousel_gap_dir() -> Vector2:
	return PropsCity.carousel_gap_dir()


## The platform's turn at a clock time: counter-clockwise seen from above (rotation.y grows), one turn
## per CAROUSEL.period, the way the horses' heads point.
static func carousel_angle_at(t: float) -> float:
	return TAU * fposmod(t / float(CityMap.CAROUSEL["period"]), 1.0)


## How high horse i rides above its lowest point at a clock time: 0..CAROUSEL.bob, each horse a quarter
## cycle after the one before.
static func carousel_bob(i: int, t: float) -> float:
	var phase := TAU * t / float(CityMap.CAROUSEL["bob_period"]) + float(i) * PI * 0.5
	return float(CityMap.CAROUSEL["bob"]) * 0.5 * (1.0 - cos(phase))


## Horse i in the turning platform's frame at a clock time (its pole on the ring, nose along the motion).
static func carousel_horse_local(i: int, t: float) -> Transform3D:
	var phi := TAU * float(i) / float(CityMap.CAROUSEL["horses"])
	var p := Vector3(cos(phi) * PropsCity.CAROUSEL_RING, PropsCity.CAROUSEL_DECK + carousel_bob(i, t), -sin(phi) * PropsCity.CAROUSEL_RING)
	return Transform3D(Basis(Vector3.UP, phi - PI), p)


## Horse i in the world at a clock time.
static func carousel_horse_transform(i: int, t: float) -> Transform3D:
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var turn := Transform3D(Basis(Vector3.UP, carousel_angle_at(t)), Vector3(c.x, 0.0, c.y))
	return turn * carousel_horse_local(i, t)


## Where a rider sits on horse i at a clock time: on the saddle, facing where the horse goes.
static func carousel_seat_transform(i: int, t: float) -> Transform3D:
	var h := carousel_horse_transform(i, t)
	return Transform3D(h.basis, h * Vector3(0, PropsCity.SADDLE_Y + 0.05, 0))


func _pose_carousel(t: float) -> void:
	if carousel_turn == null:
		return
	carousel_turn.rotation.y = carousel_angle_at(t)
	var mm := _horses.multimesh
	horse_xf.resize(mm.instance_count)
	for i in mm.instance_count:
		horse_xf[i] = carousel_horse_local(i, t)
		mm.set_instance_transform(i, horse_xf[i])


# ===================================================================== bus stops (r2)

## Where each BUS_STOPS sign and shelter stands (PropsCity.bus_stop_frames).
static func bus_stop_frames() -> Array[Transform3D]:
	return PropsCity.bus_stop_frames()


# ===================================================================== r3: weather and night lighting
#
# Everything here is built once in build(); a weather change only sets parameters of these existing
# materials and nodes (albedo, roughness, specular, emission energy, alpha, particle ratio, light energy,
# visibility). Nothing is created or freed afterwards, so nothing pops, reloads or flickers.

## The warm colour of every lit part, light pool and real light.
const WARM := Color("#ffc46e")
## The real lights (all of them: no shadows, no distance fade): position, range, energy at full glow.
const LIGHTS := [
	{"name": "Restaurant", "at": Vector3(11.8, 8.8, -8.5), "range": 8.0, "energy": 1.2},
	{"name": "Carousel", "at": Vector3(15.5, 3.0, 12.2), "range": 6.5, "energy": 1.0},
	{"name": "Shops", "at": Vector3(-8.0, 2.6, 17.0), "range": 11.0, "energy": 0.8},
	{"name": "CafeTerrace", "at": Vector3(-2.0, 5.6, -5.0), "range": 7.0, "energy": 0.9},
]
## Puddles (centre, radii) on pavements, paths and roads, faded in with the wetness.
const PUDDLES := [
	[Vector2(-12.0, -16.0), Vector2(0.7, 0.42)], [Vector2(14.0, -16.1), Vector2(0.6, 0.4)], [Vector2(24.0, 0.5), Vector2(0.42, 0.75)],
	[Vector2(-6.0, 16.2), Vector2(0.65, 0.4)], [Vector2(10.0, 16.1), Vector2(0.8, 0.45)], [Vector2(-20.0, -24.0), Vector2(0.7, 0.42)],
	[Vector2(20.0, 24.0), Vector2(0.65, 0.42)], [Vector2(-32.0, -14.0), Vector2(0.42, 0.7)], [Vector2(32.0, 12.0), Vector2(0.42, 0.65)],
	[Vector2(-15.0, -19.2), Vector2(1.1, 0.5)], [Vector2(12.0, 21.0), Vector2(1.0, 0.5)], [Vector2(-28.6, -10.0), Vector2(0.5, 1.0)],
	[Vector2(27.4, 8.0), Vector2(0.5, 1.1)], [Vector2(-15.0, 6.3), Vector2(0.8, 0.4)], [Vector2(16.0, 6.3), Vector2(0.9, 0.42)],
	[Vector2(-9.0, 0.0), Vector2(0.6, 0.45)],
]
## The rain: at most this many drops, falling in a box this wide around the camera's focus.
const RAIN_DROPS := 2400
const RAIN_HALF := 17.0
const RAIN_TOP := 14.0
## Light pool radius under every lamp (they overlap along the pavements).
const POOL_R := 4.4

var _glow_mat: StandardMaterial3D        # windows, signs, lamp heads, bulbs: emission by glow
var _cabin_mat: StandardMaterial3D       # the gondolas: lit cabins at night
var _ground_mat: StandardMaterial3D      # roads, pavements, paths, the lot: wet = darker and glossier
var _puddle_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
var _rain_mat: StandardMaterial3D
var _puddles: MeshInstance3D
var _pools: MeshInstance3D
var _rain: GeometryInstance3D             # GPUParticles3D (or CPUParticles3D where GPU particles are unavailable)
var _lights: Array[OmniLight3D] = []
var _weather_override := {}
var _weights := {"sunny": 1.0, "rain": 0.0, "night": 0.0}
var _applied := Vector3(-1.0, -1.0, -1.0)
## Set before build() to use CPU particles for the rain.
var cpu_rain := false


func _make_materials() -> void:
	var base := PropsCity.material()
	_glow_mat = base.duplicate() as StandardMaterial3D
	_glow_mat.emission_enabled = true
	_glow_mat.emission = WARM
	_glow_mat.emission_energy_multiplier = 0.0
	_cabin_mat = _glow_mat.duplicate() as StandardMaterial3D
	_ground_mat = base.duplicate() as StandardMaterial3D
	_puddle_mat = base.duplicate() as StandardMaterial3D
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puddle_mat.albedo_color = Color(1, 1, 1, 0)
	_puddle_mat.roughness = 0.06
	_puddle_mat.metallic_specular = 0.9
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_pool_mat.vertex_color_use_as_albedo = true
	_pool_mat.vertex_color_is_srgb = true
	_pool_mat.albedo_color = Color(1, 1, 1, 0)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.albedo_color = Color(0.8, 0.88, 1.0, 0.0)


## Warm ceiling panels under every slab that roofs a storey (lit at night). They live with the slab above
## them, so a cutaway that hides a storey's ceiling hides its lights too.
func _ceiling_lights() -> void:
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		var rect: Rect2 = b["rect"]
		var floors: Array = b["floors"]
		var roof: float = b["roof"]
		for k in floors.size():
			var above := float(floors[k + 1]) if k + 1 < floors.size() else roof
			var path := level_path(bid, above) if k + 1 < floors.size() else "Buildings/%s/Roof" % bid
			var holes: Array[Rect2] = []
			for rid: String in CityMap.REGIONS:
				var reg: Dictionary = CityMap.REGIONS[rid]
				if String(reg["building"]) == bid and absf(float(reg["y"]) - above) < 0.05:
					for h: Rect2 in reg["holes"]:
						holes.append(h.grow(0.4))
			var y := above - CityMap.SLAB - 0.01
			var inner := rect.grow(-1.2)
			var nx := maxi(1, roundi(inner.size.x / 3.5))
			var nz := maxi(1, roundi(inner.size.y / 3.5))
			var g := _acc(path)[2] as PropsCity.Acc
			# The panels are placed in the city's frame. The glow accumulator keeps the frame of whoever used it
			# last (a sign's, through Acc.lit()), which put the office's and the gym's top-floor panels high in
			# the sky (found by the web city's export, 2026-11-17).
			g.xf = Transform3D.IDENTITY
			for i in nx:
				for j in nz:
					var c := Vector2(inner.position.x + (float(i) + 0.5) * inner.size.x / float(nx), inner.position.y + (float(j) + 0.5) * inner.size.y / float(nz))
					var cell := Rect2(c - Vector2(0.6, 0.25), Vector2(1.2, 0.5))
					var clear := true
					for h in holes:
						if h.intersects(cell):
							clear = false
					if clear:
						g.span(Vector3(cell.position.x, y - 0.02, cell.position.y), Vector3(cell.end.x, y, cell.end.y), PropsCity.col("white"))


## The weather's own nodes: puddles, light pools, the rain and the few real lights (all built once).
func _weather_nodes() -> void:
	var root := _node("Weather")
	# puddles: flat glossy patches 1.6 cm above the highest paving they lie on
	var pa := PropsCity.acc()
	for pd: Array in PUDDLES:
		var c: Vector2 = pd[0]
		var r: Vector2 = pd[1]
		var pts: Array[Vector3] = []
		for k in 12:
			var ang := TAU * float(k) / 12.0
			var wob := 1.0 + 0.12 * sin(float(k) * 2.3 + c.x)
			pts.append(Vector3(c.x + cos(ang) * r.x * wob, 0.04, c.y + sin(ang) * r.y * wob))
		for k in 12:
			var tri: Array[Vector3] = [Vector3(c.x, 0.04, c.y), pts[k], pts[(k + 1) % 12]]
			pa.poly(tri, Vector3.UP, PropsCity.col("glass", -0.15))
	_puddles = pa.commit(root, "Puddles", _puddle_mat)
	_puddles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# light pools under every lamp: soft warm discs (vertex alpha 1 at the centre, 0 at the rim), additive
	var la := PropsCity.acc()
	var lamps: Array[Vector2] = []
	lamps.append_array(PropsCity.STREET_LAMPS)
	for s2: Dictionary in CityMap.GROUND_SOLIDS:
		if String(s2["kind"]) == "lamp":
			lamps.append(s2["at"])
	var warm := PropsCity.col("yellow", 0.4)
	for lp in lamps:
		var centre := Vector3(lp.x, 0.07, lp.y)
		var base_i := la.v.size()
		la.v.append(centre)
		la.n.append(Vector3.UP)
		la.c.append(warm)
		for k in 16:
			var ang := TAU * float(k) / 16.0
			la.v.append(centre + Vector3(cos(ang) * POOL_R, 0, sin(ang) * POOL_R))
			la.n.append(Vector3.UP)
			la.c.append(Color(warm.r, warm.g, warm.b, 0.0))
		for k in 16:
			la.idx.append_array([base_i, base_i + 1 + (k + 1) % 16, base_i + 1 + k])
	_pools = la.commit(root, "LightPools", _pool_mat)
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_rain(root)
	for spec: Dictionary in LIGHTS:
		var l := OmniLight3D.new()
		l.name = String(spec["name"]) + "Light"
		l.position = spec["at"]
		l.omni_range = float(spec["range"])
		l.light_color = WARM
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.distance_fade_enabled = false
		l.light_bake_mode = Light3D.BAKE_DISABLED
		l.set_meta("energy", float(spec["energy"]))
		root.add_child(l)
		_lights.append(l)


func _build_rain(root: Node3D) -> void:
	var streak := BoxMesh.new()
	streak.size = Vector3(0.014, 0.42, 0.014)
	streak.material = _rain_mat
	var dir := Vector3(0.14, -1.0, 0.06).normalized()
	if cpu_rain:
		var cp := CPUParticles3D.new()
		cp.amount = RAIN_DROPS
		cp.lifetime = 1.5
		cp.local_coords = false
		cp.mesh = streak
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cp.emission_box_extents = Vector3(RAIN_HALF, 0.4, RAIN_HALF)
		cp.direction = dir
		cp.spread = 3.0
		cp.initial_velocity_min = 10.0
		cp.initial_velocity_max = 12.0
		cp.gravity = Vector3(0, -4.0, 0)
		cp.particle_flag_align_y = true
		cp.emitting = false
		_rain = cp
	else:
		var gp := GPUParticles3D.new()
		gp.amount = RAIN_DROPS
		gp.lifetime = 1.5
		gp.local_coords = false
		gp.draw_pass_1 = streak
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(RAIN_HALF, 0.4, RAIN_HALF)
		pm.direction = dir
		pm.spread = 3.0
		pm.initial_velocity_min = 10.0
		pm.initial_velocity_max = 12.0
		pm.gravity = Vector3(0, -4.0, 0)
		pm.particle_flag_align_y = true
		gp.process_material = pm
		gp.amount_ratio = 0.0
		gp.visibility_aabb = AABB(Vector3(-RAIN_HALF - 3.0, -RAIN_TOP - 3.0, -RAIN_HALF - 3.0), Vector3(RAIN_HALF * 2.0 + 6.0, RAIN_TOP + 6.0, RAIN_HALF * 2.0 + 6.0))
		gp.emitting = false
		_rain = gp
	_rain.name = "Rain"
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.position = Vector3(0, RAIN_TOP, 0)
	_rain.visible = false
	root.add_child(_rain)


## The current weather mix {"sunny", "rain", "night"} (sums to 1) as drawn on this screen.
func weather_weights() -> Dictionary:
	return _weights.duplicate()


## The look blended by the weights: every WEATHER_LOOK field (colours and numbers).
func weather_look() -> Dictionary:
	var out := {}
	for wname: String in CityMap.WEATHER_LOOK:
		var w := float(_weights.get(wname, 0.0))
		var look: Dictionary = CityMap.WEATHER_LOOK[wname]
		for k: String in look:
			var v: Variant = look[k]
			if v is Color:
				out[k] = (out.get(k, Color(0, 0, 0, 0)) as Color) + (v as Color) * w
			else:
				out[k] = float(out.get(k, 0.0)) + float(v) * w
	return out


## Tests (and a weather preview) may pin the weights; {} returns to the shared weather.
func set_weather_override(weights: Dictionary) -> void:
	_weather_override = weights.duplicate()
	if _built:
		_update_weather(true)


func _compute_weights() -> Dictionary:
	var w := {}
	if not _weather_override.is_empty():
		w = _weather_override
	elif _states.has("weather"):
		# the plain weather state CityRules expects ("prev" as an Array; City's client form has a Vector3)
		var prev: Variant = _states.get("prev", _states.get("weather_prev", [1.0, 0.0, 0.0]))
		var pa: Array = [prev.x, prev.y, prev.z] if prev is Vector3 else (prev as Array)
		var since := float(_states.get("since", _states.get("weather_since", -float(CityMap.WEATHER_BLEND))))
		w = CityRulesScript.weather_weights({"weather": int(_states["weather"]), "since": since, "prev": pa}, view_time())
	else:
		return {"sunny": 1.0, "rain": 0.0, "night": 0.0}
	var sum := 0.0
	for k: String in CityMap.WEATHERS:
		sum += maxf(0.0, float(w.get(k, 0.0)))
	if sum < 1e-6:
		return {"sunny": 1.0, "rain": 0.0, "night": 0.0}
	var out := {}
	for k: String in CityMap.WEATHERS:
		out[k] = maxf(0.0, float(w.get(k, 0.0))) / sum
	return out


func _update_weather(force := false) -> void:
	_weights = _compute_weights()
	var look := weather_look()
	var v := Vector3(float(look.get("wet", 0.0)), float(look.get("glow", 0.0)), float(look.get("rain", 0.0)))
	if not force and v.distance_to(_applied) < 1e-4:
		return
	_applied = v
	_apply_look(v.x, v.y, v.z)


## Sets the weather's material and node parameters (nothing is created or freed).
func _apply_look(wet: float, glow: float, rain: float) -> void:
	_ground_mat.albedo_color = Color(1.0 - 0.2 * wet, 1.0 - 0.18 * wet, 1.0 - 0.13 * wet)
	_ground_mat.roughness = lerpf(0.92, 0.32, wet)
	_ground_mat.metallic_specular = lerpf(0.3, 0.75, wet)
	_puddle_mat.albedo_color = Color(1, 1, 1, 0.6 * wet)
	_puddles.visible = wet > 0.003
	_glow_mat.emission_energy_multiplier = 1.6 * glow
	_cabin_mat.emission_energy_multiplier = 0.45 * glow
	_pool_mat.albedo_color = Color(1, 1, 1, 0.5 * glow)
	_pools.visible = glow > 0.003
	_rain_mat.albedo_color = Color(0.8, 0.88, 1.0, 0.5 * rain)
	if _rain is GPUParticles3D:
		(_rain as GPUParticles3D).amount_ratio = rain
		(_rain as GPUParticles3D).emitting = rain > 0.003
	elif _rain is CPUParticles3D:
		(_rain as CPUParticles3D).emitting = rain > 0.003
	_rain.visible = rain > 0.003
	for l in _lights:
		l.light_energy = float(l.get_meta("energy", 1.0)) * glow


## The point the camera looks at on the ground (the rain falls around it), kept on the map. `camera`
## defaults to the viewport's current camera.
func rain_focus(camera: Camera3D = null) -> Vector3:
	var p := Vector3.ZERO
	var cam: Camera3D = camera
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam:
		var cxf := cam.global_transform if cam.is_inside_tree() else cam.transform
		var o := cxf.origin
		var f := -cxf.basis.z
		p = o + f * (-o.y / f.y) if f.y < -0.05 else o
	p.x = clampf(p.x, CityMap.OUTER_PAVEMENT.position.x, CityMap.OUTER_PAVEMENT.end.x)
	p.z = clampf(p.z, CityMap.OUTER_PAVEMENT.position.y, CityMap.OUTER_PAVEMENT.end.y)
	return Vector3(p.x, 0.0, p.z)


## A camera to follow instead of the viewport's (tests, or a rig that renders elsewhere).
var focus_camera: Camera3D


func _follow_rain() -> void:
	if _rain and _rain.visible:
		_rain.position = rain_focus(focus_camera) + Vector3(0, RAIN_TOP, 0)
