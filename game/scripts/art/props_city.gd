## The miniature city's art (design/city-district.md): voxel-style builders for every kind CityMap names.
##
## Everything is crisp boxes with small bevels on a 0.1-0.2 m module, matte, coloured only by vertex
## colours taken from CityMap.COLORS (in fixed shade steps, see `col`), with no textures. Builders do not
## make one node per part: they append to an `Acc` (a vertex-coloured mesh accumulator), and the world
## commits one Acc per storey, so a whole storey is one draw call (like Kit.merge_parts, but direct).
##
## Conventions: 1 unit = 1 m, y up, +x east, +z south (toward the default camera). A furniture builder
## works in a local frame whose origin is its footprint centre on the floor and whose front faces +z.
## People and vehicles face +z at ry = 0 (a node's rotation.y = atan2(dir.x, dir.z)).
extends RefCounted

const CityMap := preload("res://scripts/core/city_map.gd")

## The only shade steps used on palette colours (positive: toward white, negative: toward black).
const SHADES: Array[float] = [-0.5, -0.3, -0.15, 0.0, 0.2, 0.4, 0.6, 0.8]
const RAIL_H := 1.0          # top of every railing above its floor
const DOOR_H := 2.2          # clear height of a door
const SILL := 1.0            # window sill above the storey floor (the wall alone guards up to here)
const HEAD := 2.3            # window head above the storey floor
const INSET := 0.05          # a railing's centre line inside the walkable edge
## Furniture whose front is not +z.
const FRONT := {"sofa": "+x", "shelf": "+x", "rower": "-x"}
## Furniture that stands against a wall and faces into its room (the world picks the side).
const WALL_KINDS := ["bookshelf", "coffee_bar", "shelf", "sofa", "bread_display", "flower_stand", "freezer", "mirror_wall", "weight_rack"]
## Every FURNITURE and GROUND_SOLIDS kind the art builds (the tests hold CityMap to this list).
const KINDS := ["counter", "cafe_table", "umbrella_table", "shelf", "planter", "dining_table", "kitchen_bar", "treadmill",
	"weight_rack", "mat", "bike", "mirror_wall", "reception", "sofa", "desk", "plant", "meeting_table", "shop_counter",
	"bread_display", "bookshelf", "flower_stand", "freezer", "bistro_table", "coffee_bar", "pavilion_post",
	"rower", "stair_base", "bus_shelter", "wheel_leg", "wheel_platform", "tree", "lamp", "flower_bed", "carousel"]
## Each shop's accent (awning stripes, sign) and icon (door transom).
const SHOP_ICON := {"bakery": "bread", "corner_cafe": "cup", "bookstore": "book", "flowers": "flower", "icecream": "cone"}

static var _vc: StandardMaterial3D


## A palette colour at one of the SHADES steps.
static func col(name: String, s := 0.0) -> Color:
	assert(SHADES.has(s), "city art: shade %s is not a palette step" % s)
	var base: Color = CityMap.COLORS[name]
	return base.lightened(s) if s > 0.0 else base.darkened(-s)


## A raw colour (a cabin's, a shop's accent, a vehicle's) at one of the SHADES steps.
static func shade(c: Color, s := 0.0) -> Color:
	assert(SHADES.has(s), "city art: shade %s is not a palette step" % s)
	return c.lightened(s) if s > 0.0 else c.darkened(-s)


## Every colour the city may use (the tests hold the vertex colours to this list): the COLORS keys, the
## cabins' pastels, the shops' accents and the vehicles' paints, each at every SHADES step.
static func palette() -> Array[Color]:
	var bases: Array[Color] = []
	for k: String in CityMap.COLORS:
		bases.append(CityMap.COLORS[k])
	for c: Color in CityMap.CABIN_COLORS:
		bases.append(c)
	for k: String in CityMap.SHOP_ACCENTS:
		bases.append(CityMap.SHOP_ACCENTS[k])
	for v: Dictionary in CityMap.VEHICLES:
		if v.has("color"):
			bases.append(v["color"])
	var out: Array[Color] = []
	for b in bases:
		for s: float in SHADES:
			out.append(shade(b, s))
	return out


## A building's body colour key (the shop row is mint), its trim key (fascias, bands, corner pilasters)
## and its base band colour (r2: white trims and deeper bases keep the buildings apart).
static func body_key(bid: String) -> String:
	var b: Dictionary = CityMap.BUILDINGS[bid]
	return "mint" if bool(b.get("shop", false)) else String(b["color"])


static func trim_key(bid: String) -> String:
	match body_key(bid):
		"blue": return "blue_trim"
		"yellow": return "yellow_trim"
		"coral": return "peach"
		"mint": return "mint_deep"
	return "white"


static func base_color(bid: String) -> Color:
	match body_key(bid):
		"coral": return col("peach")
		"mint": return col("mint_deep")
	return col(body_key(bid), -0.15)


## A shop's accent (awnings, sign boards, counters): CityMap.SHOP_ACCENTS.
static func accent(shop: String) -> Color:
	return CityMap.SHOP_ACCENTS.get(shop, col("peach"))


## The one material: matte, vertex coloured, metallic 0, no texture.
static func material() -> StandardMaterial3D:
	if _vc == null:
		_vc = StandardMaterial3D.new()
		_vc.vertex_color_use_as_albedo = true
		_vc.vertex_color_is_srgb = true
		_vc.roughness = 0.92
		_vc.metallic = 0.0
		_vc.metallic_specular = 0.3
		_vc.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return _vc


# ===================================================================== the mesh accumulator

## Collects flat-shaded, vertex-coloured polygons in a local frame `xf`; `commit` makes one mesh.
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var xf := Transform3D.IDENTITY
	## While set (height, amount): vertices are darkened by up to `amount` toward the ground, fading out
	## by `height`, a gentle depth cue at the foot of tall walls.
	var fade := Vector2.ZERO
	## Where lit parts go (windows, signs, lamp heads, bulbs): a second accumulator committed with the
	## emissive night material (city r3). null: they stay in this one.
	var glow: Acc = null

	## The accumulator for lit parts, in this one's current frame.
	func lit() -> Acc:
		if glow == null:
			return self
		glow.xf = xf
		return glow

	func is_empty() -> bool:
		return v.is_empty()

	func tris() -> int:
		return int(idx.size() / 3.0)

	## A convex polygon (3 or 4 points) with its outward normal, wound so its front faces outward.
	func poly(pts: Array[Vector3], nn: Vector3, color: Color) -> void:
		var base := v.size()
		var wn := (xf.basis * nn).normalized()
		for p in pts:
			var wp := xf * p
			v.append(wp)
			n.append(wn)
			if fade.y > 0.0:
				var k := 1.0 - fade.y * clampf(1.0 - wp.y / fade.x, 0.0, 1.0)
				c.append(Color(color.r * k, color.g * k, color.b * k, color.a))
			else:
				c.append(color)
		var cr := (pts[1] - pts[0]).cross(pts[2] - pts[0])
		var flip := cr.dot(nn) > 0.0
		for k in range(1, pts.size() - 1):
			if flip:
				idx.append_array([base, base + k + 1, base + k])
			else:
				idx.append_array([base, base + k, base + k + 1])

	## A box (centre, size) with an optional bevel `b` (a chamfer: 44 triangles; plain: 12) and basis.
	func box(center: Vector3, size: Vector3, color: Color, b := 0.0, basis := Basis.IDENTITY) -> void:
		var h := size * 0.5
		# tiny parts read as crisp cubes anyway: no bevel below 0.12 m
		if minf(size.x, minf(size.y, size.z)) < 0.12:
			b = 0.0
		b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.8)
		var e := h - Vector3(b, b, b)
		var quads: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for ax in 3:
			var u := (ax + 1) % 3
			var w := (ax + 2) % 3
			for s: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = []
				for q in quads:
					var p := Vector3()
					p[ax] = h[ax] * s
					p[u] = e[u] * q.x
					p[w] = e[w] * q.y
					pts.append(basis * p + center)
				var nn := Vector3()
				nn[ax] = s
				poly(pts, basis * nn, color)
		if b <= 0.0005:
			return
		for m in 3:
			var k := (m + 1) % 3
			var l := (m + 2) % 3
			for s: float in [-1.0, 1.0]:
				for t: float in [-1.0, 1.0]:
					var pts: Array[Vector3] = []
					for mm: float in [-1.0, 1.0]:
						var pa := Vector3()
						pa[k] = h[k] * s
						pa[l] = e[l] * t
						pa[m] = e[m] * mm
						var pb := Vector3()
						pb[k] = e[k] * s
						pb[l] = h[l] * t
						pb[m] = e[m] * mm
						if mm < 0.0:
							pts.append(basis * pa + center)
							pts.append(basis * pb + center)
						else:
							pts.append(basis * pb + center)
							pts.append(basis * pa + center)
					var nn := Vector3()
					nn[k] = s
					nn[l] = t
					poly(pts, basis * nn.normalized(), color)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var pts: Array[Vector3] = [
						basis * Vector3(sx * h.x, sy * e.y, sz * e.z) + center,
						basis * Vector3(sx * e.x, sy * h.y, sz * e.z) + center,
						basis * Vector3(sx * e.x, sy * e.y, sz * h.z) + center]
					poly(pts, basis * Vector3(sx, sy, sz).normalized(), color)

	## An axis-aligned box from its minimum corner to its maximum corner.
	func span(lo: Vector3, hi: Vector3, color: Color, b := 0.0) -> void:
		box((lo + hi) * 0.5, (hi - lo).abs(), color, b)

	## A flat-sided prism (radius to the flats' corners, `sides`) along the basis's y axis.
	func prism(center: Vector3, radius: float, height: float, color: Color, sides := 8, basis := Basis.IDENTITY) -> void:
		var ring: Array[Vector3] = []
		for i in sides:
			var a := TAU * (float(i) + 0.5) / float(sides)
			ring.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		var hy := Vector3(0, height * 0.5, 0)
		for i in sides:
			var p0 := ring[i]
			var p1 := ring[(i + 1) % sides]
			var mid := ((p0 + p1) * 0.5).normalized()
			var pts: Array[Vector3] = [basis * (p0 - hy) + center, basis * (p1 - hy) + center, basis * (p1 + hy) + center, basis * (p0 + hy) + center]
			poly(pts, basis * mid, color)
			var top: Array[Vector3] = [basis * hy + center, basis * (p0 + hy) + center, basis * (p1 + hy) + center]
			poly(top, basis * Vector3.UP, color)
			var bot: Array[Vector3] = [basis * -hy + center, basis * (p1 - hy) + center, basis * (p0 - hy) + center]
			poly(bot, basis * Vector3.DOWN, color)

	## A box from p0 to p1 (its length), `w` wide and `d` deep across it.
	func beam(p0: Vector3, p1: Vector3, w: float, d: float, color: Color, b := 0.0) -> void:
		var dir := p1 - p0
		var length := dir.length()
		if length < 0.001:
			return
		var y := dir / length
		var hint := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
		var x := hint.cross(y).normalized()
		var z := x.cross(y).normalized()
		box((p0 + p1) * 0.5, Vector3(w, length, d), color, b, Basis(x, y, z))

	## Appends another mesh's surfaces (for example a Kit.rounded_box) in one colour.
	func mesh(m: Mesh, at: Transform3D, color: Color) -> void:
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var base := v.size()
			var full := xf * at
			for i in mv.size():
				v.append(full * mv[i])
				n.append((full.basis * mn[i]).normalized())
				c.append(color)
			var mi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in mi.size():
				idx.append(base + mi[i])

	## The collected polygons as one mesh.
	func build_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am

	## One MeshInstance3D named `name` under `parent` (nothing when empty).
	func commit(parent: Node3D, name: String, mat: Material) -> MeshInstance3D:
		if v.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = am
		mi.material_override = mat
		parent.add_child(mi)
		return mi


static func acc() -> Acc:
	return Acc.new()


## A frame for a footprint: origin at the rect centre on the floor, local +z facing `front`.
## Returns [Transform3D, width along local x, depth along local z].
static func frame(rect: Rect2, y: float, front := "+z") -> Array:
	var ry := 0.0
	var w := rect.size.x
	var d := rect.size.y
	match front:
		"+x":
			ry = PI * 0.5
			w = rect.size.y
			d = rect.size.x
		"-x":
			ry = -PI * 0.5
			w = rect.size.y
			d = rect.size.x
		"-z":
			ry = PI
	var c := rect.get_center()
	return [Transform3D(Basis(Vector3.UP, ry), Vector3(c.x, y, c.y)), w, d]


# ===================================================================== walkable geometry (navigation contract)

## A stair's walking height at a ground point (a straight ramp from y0 at its low end to y1).
static func stair_height(st: Dictionary, p: Vector2) -> float:
	var r: Rect2 = st["rect"]
	var t := 0.0
	match String(st["up"]):
		"-z": t = (r.end.y - p.y) / r.size.y
		"+z": t = (p.y - r.position.y) / r.size.y
		"-x": t = (r.end.x - p.x) / r.size.x
		"+x": t = (p.x - r.position.x) / r.size.x
	return lerpf(float(st["y0"]), float(st["y1"]), clampf(t, 0.0, 1.0))


## A rect's four edges: {axis ("x": the line x = c, running along z; "z": the line z = c), c, a, b, out}.
## `out` is the side (-1/+1 along the axis) that is outside the rect; `hole` flips it.
static func _rect_edges(r: Rect2, hole := false) -> Array[Dictionary]:
	var f := -1 if hole else 1
	var out: Array[Dictionary] = [
		{"axis": "x", "c": r.position.x, "a": r.position.y, "b": r.end.y, "out": -f, "side": "xmin"},
		{"axis": "x", "c": r.end.x, "a": r.position.y, "b": r.end.y, "out": f, "side": "xmax"},
		{"axis": "z", "c": r.position.y, "a": r.position.x, "b": r.end.x, "out": -f, "side": "zmin"},
		{"axis": "z", "c": r.end.y, "a": r.position.x, "b": r.end.x, "out": f, "side": "zmax"}]
	return out


## The low and high end sides of a stair's rect, by its "up".
static func stair_ends(st: Dictionary) -> Array[String]:
	match String(st["up"]):
		"-z": return ["zmax", "zmin"]
		"+z": return ["zmin", "zmax"]
		"-x": return ["xmax", "xmin"]
	return ["xmin", "xmax"]


## Every boundary edge of every upper walkable surface. Region edges and hole edges have a fixed "y";
## stair ends have their end's height; stair long sides are "side" (always a railing).
static func edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[id]
		for e in _rect_edges(reg["rect"]):
			e["owner"] = id
			e["role"] = "edge"
			e["y"] = float(reg["y"])
			out.append(e)
		for h: Rect2 in reg["holes"]:
			for e in _rect_edges(h, true):
				e["owner"] = id
				e["role"] = "hole"
				e["y"] = float(reg["y"])
				out.append(e)
	for id: String in CityMap.STAIRS:
		var st: Dictionary = CityMap.STAIRS[id]
		var ends := stair_ends(st)
		for e in _rect_edges(st["rect"]):
			e["owner"] = id
			if e["side"] == ends[0]:
				e["role"] = "end"
				e["y"] = float(st["y0"])
			elif e["side"] == ends[1]:
				e["role"] = "end"
				e["y"] = float(st["y1"])
			else:
				e["role"] = "side"
				e["y"] = -1.0
			out.append(e)
	return out


## The parts of an edge where it connects (to another surface at the same height along a shared
## segment of at least 0.8 m, or a stair end to the ground): an Array of Vector2(a, b).
static func shared_intervals(e: Dictionary, all: Array[Dictionary]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if e["role"] == "side":
		return out
	if e["role"] == "end" and float(e["y"]) < 0.01:
		out.append(Vector2(e["a"], e["b"]))
		return out
	for f in all:
		if f["owner"] == e["owner"] or f["role"] == "side" or f["axis"] != e["axis"]:
			continue
		if absf(float(f["c"]) - float(e["c"])) > 0.01 or int(f["out"]) != -int(e["out"]) or absf(float(f["y"]) - float(e["y"])) > 0.01:
			continue
		var a := maxf(e["a"], f["a"])
		var b := minf(e["b"], f["b"])
		if b - a >= 0.8 - 0.001:
			out.append(Vector2(a, b))
	return out


## [a, b] minus the given intervals.
static func subtract(a: float, b: float, cuts: Array[Vector2]) -> Array[Vector2]:
	var parts: Array[Vector2] = [Vector2(a, b)]
	for cut in cuts:
		var next: Array[Vector2] = []
		for p in parts:
			if cut.y <= p.x or cut.x >= p.y:
				next.append(p)
				continue
			if cut.x > p.x:
				next.append(Vector2(p.x, cut.x))
			if cut.y < p.y:
				next.append(Vector2(cut.y, p.y))
		parts = next
	var out: Array[Vector2] = []
	for p in parts:
		if p.y - p.x > 0.01:
			out.append(p)
	return out


## Where a building's walls stand at a height: the guard for an open edge that runs inside a wall
## (thin GROUND_WALLS rect, the building rising at least a railing's height above `y`).
static func wall_covers(p0: Vector2, p1: Vector2, y: float) -> bool:
	for w: Rect2 in CityMap.GROUND_WALLS:
		var g := w.grow(0.02)
		if not (g.has_point(p0) and g.has_point(p1)):
			continue
		var bid := building_at(w.get_center())
		if bid != "" and float(CityMap.BUILDINGS[bid]["roof"]) >= y + RAIL_H:
			return true
	return false


static func building_at(p: Vector2) -> String:
	for bid: String in CityMap.BUILDINGS:
		var r: Rect2 = CityMap.BUILDINGS[bid]["rect"]
		if r.grow(0.01).has_point(p):
			return bid
	return ""


## Every guarded edge piece of every upper region (stair sides are guarded by the stair itself):
## {owner, a: Vector3, b: Vector3, inward: Vector2, kind: "wall" | "railing"}.
static func guard_segments() -> Array[Dictionary]:
	var all := edges()
	var out: Array[Dictionary] = []
	for e in all:
		if e["role"] == "side" or e["role"] == "end":
			continue
		var y: float = e["y"]
		for iv in subtract(e["a"], e["b"], shared_intervals(e, all)):
			var p0: Vector2
			var p1: Vector2
			var inward: Vector2
			if e["axis"] == "x":
				p0 = Vector2(e["c"], iv.x)
				p1 = Vector2(e["c"], iv.y)
				inward = Vector2(-float(e["out"]), 0.0)
			else:
				p0 = Vector2(iv.x, e["c"])
				p1 = Vector2(iv.y, e["c"])
				inward = Vector2(0.0, -float(e["out"]))
			out.append({"owner": e["owner"], "a": Vector3(p0.x, y, p0.y), "b": Vector3(p1.x, y, p1.y), "inward": inward,
				"kind": "wall" if wall_covers(p0, p1, y) else "railing"})
	return out


## Rect minus holes, as disjoint rects.
static func rect_minus(r: Rect2, holes: Array) -> Array[Rect2]:
	var parts: Array[Rect2] = [r]
	for h: Rect2 in holes:
		var next: Array[Rect2] = []
		for p in parts:
			if not p.intersects(h):
				next.append(p)
				continue
			var i := p.intersection(h)
			if i.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				next.append(Rect2(p.position.x, i.end.y, p.size.x, p.end.y - i.end.y))
			if i.position.x > p.position.x:
				next.append(Rect2(p.position.x, i.position.y, i.position.x - p.position.x, i.size.y))
			if i.end.x < p.end.x:
				next.append(Rect2(i.end.x, i.position.y, p.end.x - i.end.x, i.size.y))
		parts = next
	return parts


# ===================================================================== architecture

## A railing along a walkable edge (p0, p1 at floor height), its centre INSET inside toward `inward`:
## posts, a 0.12 m top rail ending at RAIL_H, a kick rail and square balusters every 0.2 m.
static func railing(a: Acc, p0: Vector3, p1: Vector3, inward: Vector2, post: Color, rail: Color) -> void:
	var off := Vector3(inward.x, 0, inward.y) * INSET
	var dir := p1 - p0
	var length := dir.length()
	if length < 0.02:
		return
	var u := dir / length
	var q0 := p0 + off + u * minf(0.04, length * 0.5)
	var q1 := p1 + off - u * minf(0.04, length * 0.5)
	var along_x := absf(u.x) > 0.5
	var y := p0.y
	var top_size := Vector3(length, 0.12, 0.08) if along_x else Vector3(0.08, 0.12, length)
	var mid := (p0 + p1) * 0.5 + off
	a.box(Vector3(mid.x, y + RAIL_H - 0.06, mid.z), top_size, rail, 0.02)
	var kick := Vector3(length, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, length)
	a.box(Vector3(mid.x, y + 0.11, mid.z), kick, rail)
	var posts := maxi(2, int(ceil(length / 1.2)) + 1)
	if length < 0.3:
		posts = 1
	for i in posts:
		var t := 0.5 if posts == 1 else float(i) / float(posts - 1)
		var p := q0.lerp(q1, t)
		a.box(Vector3(p.x, y + (RAIL_H - 0.06) * 0.5, p.z), Vector3(0.08, RAIL_H - 0.06, 0.08), post, 0.015)
	var bars := int(floor(length / 0.2))
	for i in range(1, bars):
		var p := p0 + off + u * (float(i) * length / float(bars))
		a.box(Vector3(p.x, y + 0.5, p.z), Vector3(0.035, 0.76, 0.035), rail)


## A wall piece along x or z between two heights with openings ({u0, u1, v0, v1}: along-wall and
## height ranges), windows framed, and a pale liner on the face toward `inside`.
static func wall(a: Acc, d: Acc, r: Rect2, y0: float, y1: float, color: Color, liner: Color, inside: Vector2, openings: Array[Vector4], windows: Array[Vector4], display := false) -> void:
	var along_x := r.size.x >= r.size.y
	var u_lo := r.position.x if along_x else r.position.y
	var u_hi := r.end.x if along_x else r.end.y
	var t_lo := r.position.y if along_x else r.position.x
	var t_hi := r.end.y if along_x else r.end.x
	var all: Array[Vector4] = []
	all.append_array(openings)
	all.append_array(windows)
	all.sort_custom(func(p: Vector4, q: Vector4) -> bool: return p.x < q.x)
	var pieces: Array[Vector4] = []   # u0, u1, v0, v1
	var cur := u_lo
	for o in all:
		if o.x > cur + 0.001:
			pieces.append(Vector4(cur, o.x, y0, y1))
		if o.z > y0 + 0.001:
			pieces.append(Vector4(o.x, o.y, y0, o.z))
		if o.w < y1 - 0.001:
			pieces.append(Vector4(o.x, o.y, o.w, y1))
		cur = maxf(cur, o.y)
	if cur < u_hi - 0.001:
		pieces.append(Vector4(cur, u_hi, y0, y1))
	var inner_t := t_hi if (inside.y > 0.0 if along_x else inside.x > 0.0) else t_lo
	var sgn := 1.0 if inner_t == t_hi else -1.0
	for p in pieces:
		_wall_box(a, along_x, p.x, p.y, t_lo, t_hi, p.z, p.w, color)
		_wall_box(a, along_x, p.x, p.y, inner_t, inner_t + sgn * 0.012, p.z, p.w, liner)
	var outer_t := t_lo if sgn > 0.0 else t_hi
	var white := col("white")
	for wdw in windows:
		# glass in the middle of the wall, a frame band inside the opening, a mullion and a sill
		# a display window's glass sits near the street face, leaving a niche for goods behind it
		var tm := (t_lo + t_hi) * 0.5 if not display else outer_t + sgn * 0.06
		_wall_box(a.lit(), along_x, wdw.x, wdw.y, tm - 0.02, tm + 0.02, wdw.z, wdw.w, col("glass"))
		var tf0 := t_lo - 0.025
		var tf1 := t_hi + 0.025
		_wall_box(a, along_x, wdw.x, wdw.x + 0.08, tf0, tf1, wdw.z, wdw.w, white)
		_wall_box(a, along_x, wdw.y - 0.08, wdw.y, tf0, tf1, wdw.z, wdw.w, white)
		_wall_box(a, along_x, wdw.x, wdw.y, tf0, tf1, wdw.w - 0.08, wdw.w, white)
		_wall_box(a, along_x, wdw.x, wdw.y, tf0, tf1, wdw.z, wdw.z + 0.06, white)
		var um := (wdw.x + wdw.y) * 0.5
		_wall_box(d, along_x, um - 0.03, um + 0.03, tm - 0.04, tm + 0.04, wdw.z, wdw.w, white)
		var bar := wdw.z + (wdw.w - wdw.z) * (0.78 if display else 0.62)
		_wall_box(d, along_x, wdw.x, wdw.y, tm - 0.04, tm + 0.04, bar, bar + 0.05, white)
		var so := outer_t - sgn * 0.1
		var ext := 0.0 if display else 0.08
		_wall_box(a, along_x, wdw.x - ext, wdw.y + ext, minf(so, outer_t), maxf(so, outer_t), wdw.z - 0.08, wdw.z, white)
	for o in openings:
		# a door frame on both faces, outside the opening
		for face in [t_lo - 0.04, t_hi]:
			var f0: float = face
			_wall_box(a, along_x, o.x - 0.12, o.x, f0, f0 + 0.04, o.z, o.w + 0.12, white)
			_wall_box(a, along_x, o.y, o.y + 0.12, f0, f0 + 0.04, o.z, o.w + 0.12, white)
			_wall_box(a, along_x, o.x - 0.12, o.y + 0.12, f0, f0 + 0.04, o.w, o.w + 0.12, white)


static func _wall_box(a: Acc, along_x: bool, u0: float, u1: float, t0: float, t1: float, v0: float, v1: float, color: Color) -> void:
	if absf(u1 - u0) < 0.001 or absf(v1 - v0) < 0.001 or absf(t1 - t0) < 0.0005:
		return
	if along_x:
		a.span(Vector3(minf(u0, u1), v0, minf(t0, t1)), Vector3(maxf(u0, u1), v1, maxf(t0, t1)), color)
	else:
		a.span(Vector3(minf(t0, t1), v0, minf(u0, u1)), Vector3(maxf(t0, t1), v1, maxf(u0, u1)), color)


## Window openings (Vector4 u0, u1, v0, v1) evenly along a wall of `length` from `u_lo`, avoiding doors.
static func window_row(u_lo: float, length: float, base: float, doors: Array[Vector4], blocked: Array[Vector2] = []) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var count := int((length - 1.0) / 2.4)
	if count < 1 and length >= 2.2:
		count = 1
	var mid := u_lo + length * 0.5
	for i in count:
		var uc := mid + (float(i) - float(count - 1) * 0.5) * 2.4
		var ok := true
		for dr in doors:
			if uc + 0.6 > dr.x - 0.4 and uc - 0.6 < dr.y + 0.4:
				ok = false
		for bl in blocked:
			if uc + 0.6 > bl.x - 0.1 and uc - 0.6 < bl.y + 0.1:
				ok = false
		if ok:
			out.append(Vector4(uc - 0.6, uc + 0.6, base + SILL, base + HEAD))
	return out


## A floor slab (rect minus holes) between y - SLAB and y with a patterned top skin.
static func slab(a: Acc, pieces: Array[Rect2], y: float, body: Color, top_a: Color, top_b: Color, pattern := "plain", module := 1.0) -> void:
	for r in pieces:
		a.span(Vector3(r.position.x, y - CityMap.SLAB, r.position.y), Vector3(r.end.x, y - 0.02, r.end.y), body)
		match pattern:
			"planks_x", "planks_z":
				var along_x := pattern == "planks_x"
				var lo := r.position.y if along_x else r.position.x
				var hi := r.end.y if along_x else r.end.x
				var k := int(floor(lo / module))
				var s := float(k) * module
				while s < hi - 0.001:
					var s0 := maxf(s, lo)
					var s1 := minf(s + module, hi)
					var cc := top_a if posmod(k, 2) == 0 else top_b
					if along_x:
						a.span(Vector3(r.position.x, y - 0.02, s0), Vector3(r.end.x, y, s1), cc)
					else:
						a.span(Vector3(s0, y - 0.02, r.position.y), Vector3(s1, y, r.end.y), cc)
					s += module
					k += 1
			"checker":
				var ix := int(floor(r.position.x / module))
				var x := float(ix) * module
				while x < r.end.x - 0.001:
					var iz := int(floor(r.position.y / module))
					var z := float(iz) * module
					while z < r.end.y - 0.001:
						var cc := top_a if posmod(ix + iz, 2) == 0 else top_b
						a.span(Vector3(maxf(x, r.position.x), y - 0.02, maxf(z, r.position.y)), Vector3(minf(x + module, r.end.x), y, minf(z + module, r.end.y)), cc)
						z += module
						iz += 1
					x += module
					ix += 1
			_:
				a.span(Vector3(r.position.x, y - 0.02, r.position.y), Vector3(r.end.x, y, r.end.y), top_a)


## A straight stair of CityMap.STEPS steps (tops on the height line at each tread's centre), built so it
## stands up: a stone landing pad at its foot, the lowest steps solid down to the floor, two stringers
## that start on the floor and end on a header beam under the top landing, columns under the header
## (and at mid-span outdoors), handrails with balusters and newel posts on both long sides.
static func stair(a: Acc, st: Dictionary, body: Color, tread: Color, rail: Color, post: Color, exterior: bool) -> void:
	var y0: float = st["y0"]
	var y1: float = st["y1"]
	var fr := stair_frame(st)
	var length: float = fr[1]
	var width: float = fr[2]
	var save := a.xf
	a.xf = save * (fr[0] as Transform3D)
	var n := CityMap.STEPS
	var run := length / float(n)
	var rise := (y1 - y0) / float(n)
	var hw := width * 0.5
	var slope := rise / run
	# the landing pad at the foot
	var pw := hw + (0.15 if exterior else 0.0)
	a.span(Vector3(-pw, y0, -0.9), Vector3(pw, y0 + 0.03, 0.0), col("kerb"))
	a.span(Vector3(-pw + 0.06, y0 + 0.03, -0.12), Vector3(pw - 0.06, y0 + 0.034, -0.06), col("yellow"))
	for i in n:
		var zc := (float(i) + 0.5) * run
		var top := y0 + (float(i) + 0.5) * rise
		if top - y0 < 0.7:
			a.span(Vector3(-hw + 0.01, y0, zc - run * 0.5), Vector3(hw - 0.01, top - 0.04, zc + run * 0.5), body)
		else:
			a.box(Vector3(0, top - 0.11, zc), Vector3(width - 0.02, 0.18, run), body)
		a.box(Vector3(0, top - 0.025, zc - 0.015), Vector3(width, 0.05, run + 0.03), tread, 0.01)
	# stringers: from where they rest on the floor (just behind the solid steps) to the header beam
	var drop := 0.45
	var z0 := (drop + 0.14) / slope
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw - 0.08)
		a.beam(Vector3(x, y0 + z0 * slope - drop, z0), Vector3(x, y1 - drop, length - 0.12), 0.12, 0.24, body, 0.02)
		a.span(Vector3(x - 0.1, y0, z0 - 0.2), Vector3(x + 0.1, y0 + 0.06, z0 + 0.2), col("dark", 0.2))
	# the header under the top landing and the columns carrying it (and the stringers at mid-span)
	a.span(Vector3(-hw + 0.02, y1 - 0.66, length - 0.3), Vector3(hw - 0.02, y1 - 0.32, length), body)
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw - 0.12)
		a.span(Vector3(x - 0.08, y0, length - 0.23), Vector3(x + 0.08, y1 - 0.66, length - 0.07), body)
		a.span(Vector3(x - 0.12, y0, length - 0.27), Vector3(x + 0.12, y0 + 0.08, length - 0.03), col("dark", 0.2))
		if exterior:
			var zm := length * 0.55
			var under := y0 + zm * slope - drop - 0.14
			a.span(Vector3(sx * (hw - 0.08) - 0.06, y0, zm - 0.06), Vector3(sx * (hw - 0.08) + 0.06, under, zm + 0.06), body)
	# handrails: posts every other step, balusters each step, a sloped rail, a mid rail, newels
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw - INSET)
		for i in n:
			var zc := (float(i) + 0.5) * run
			var top := y0 + (float(i) + 0.5) * rise
			if i % 2 == 0 or i == n - 1:
				a.box(Vector3(x, top + RAIL_H * 0.5 - 0.06, zc), Vector3(0.07, RAIL_H - 0.12, 0.07), post, 0.015)
			else:
				a.box(Vector3(x, top + 0.45, zc), Vector3(0.035, 0.8, 0.035), rail)
		var r0 := Vector3(x, y0 + RAIL_H - 0.06, 0.03)
		var r1 := Vector3(x, y1 + RAIL_H - 0.06, length - 0.03)
		a.beam(r0, r1, 0.08, 0.11, rail, 0.02)
		a.beam(r0 - Vector3(0, 0.5, 0), r1 - Vector3(0, 0.5, 0), 0.05, 0.05, rail)
		for zz: float in [0.04, length - 0.04]:
			var ty := y0 if zz < 1.0 else y1
			a.box(Vector3(x, ty + (RAIL_H + 0.1) * 0.5, zz), Vector3(0.1, RAIL_H + 0.1, 0.1), post, 0.02)
			a.box(Vector3(x, ty + RAIL_H + 0.08, zz), Vector3(0.14, 0.06, 0.14), rail, 0.02)
	if exterior and y0 < 0.01:
		# the solid footprint under an exterior stair: a planter where the stair is high enough
		var zp := length * 0.45
		a.box(Vector3(0, 0.22, (zp + length - 0.45) * 0.5), Vector3(width - 0.36, 0.44, length - 0.45 - zp), col("pavement", -0.15), 0.03)
		var z := zp + 0.3
		var i := 0
		while z < length - 0.7:
			var g := col("green", -0.15 if i % 2 == 0 else 0.0)
			a.box(Vector3(-0.22 + 0.44 * float(i % 2), 0.62, z), Vector3(0.44, 0.4, 0.44), g, 0.06)
			z += 0.55
			i += 1
	a.xf = save


## A stair's local frame: [Transform3D (origin at the low end's centre on the ground plane, +z up the
## run, +x across), run length, width].
static func stair_frame(st: Dictionary) -> Array:
	var r: Rect2 = st["rect"]
	var up := String(st["up"])
	var along_z := up.ends_with("z")
	var low := Vector3()
	var dir := Vector3()
	match up:
		"-z":
			low = Vector3(r.get_center().x, 0, r.end.y)
			dir = Vector3(0, 0, -1)
		"+z":
			low = Vector3(r.get_center().x, 0, r.position.y)
			dir = Vector3(0, 0, 1)
		"-x":
			low = Vector3(r.end.x, 0, r.get_center().y)
			dir = Vector3(-1, 0, 0)
		_:
			low = Vector3(r.position.x, 0, r.get_center().y)
			dir = Vector3(1, 0, 0)
	var side := Vector3.UP.cross(dir)
	return [Transform3D(Basis(side, Vector3.UP, dir), low), r.size.y if along_z else r.size.x, r.size.x if along_z else r.size.y]


## A skywalk: a deck with visible thickness (edge bands along its guarded sides, steel beams under it,
## corbels where it bears on the buildings at its two ends) and a light canopy on four posts.
## `guards`: its guard_segments (railing kind), so no band stands in a shared opening.
static func skywalk(a: Acc, r: Rect2, y: float, guards: Array[Dictionary]) -> void:
	var deck: Array[Rect2] = [r]
	slab(a, deck, y, col("white", -0.15), col("pavement"), col("pavement", 0.4), "planks_x" if r.size.x < r.size.y else "planks_z", 0.4)
	var along_x := r.size.x >= r.size.y
	for g in guards:
		var p0: Vector3 = g["a"]
		var p1: Vector3 = g["b"]
		var inward: Vector2 = g["inward"]
		var o := Vector3(-inward.x, 0, -inward.y) * 0.07
		var lo := Vector3(minf(minf(p0.x, p1.x), p0.x + o.x), y - 0.46, minf(minf(p0.z, p1.z), p0.z + o.z))
		var hi := Vector3(maxf(maxf(p0.x, p1.x), p0.x + o.x), y - 0.1, maxf(maxf(p0.z, p1.z), p0.z + o.z))
		a.span(lo, hi, col("blue"))
		a.span(Vector3(lo.x, y - 0.1, lo.z), Vector3(hi.x, y - 0.02, hi.z), col("white"))
	for s: float in [0.0, 1.0]:
		if along_x:
			var z := r.position.y + 0.12 + s * (r.size.y - 0.36)
			a.span(Vector3(r.position.x, y - 0.42, z), Vector3(r.end.x, y - CityMap.SLAB, z + 0.12), col("dark", 0.2))
		else:
			var x := r.position.x + 0.12 + s * (r.size.x - 0.36)
			a.span(Vector3(x, y - 0.42, r.position.y), Vector3(x + 0.12, y - CityMap.SLAB, r.end.y), col("dark", 0.2))
	# corbels at both ends, on the walls the deck rests on
	for e in 2:
		if along_x:
			var x0 := r.position.x if e == 0 else r.end.x - 0.3
			a.span(Vector3(x0, y - 0.62, r.position.y + 0.05), Vector3(x0 + 0.3, y - CityMap.SLAB, r.end.y - 0.05), col("white", -0.15))
			a.span(Vector3(x0 + (0.0 if e == 0 else 0.15), y - 0.78, r.position.y + 0.15), Vector3(x0 + (0.15 if e == 0 else 0.3), y - 0.62, r.end.y - 0.15), col("white", -0.15))
		else:
			var z0 := r.position.y if e == 0 else r.end.y - 0.3
			a.span(Vector3(r.position.x + 0.05, y - 0.62, z0), Vector3(r.end.x - 0.05, y - CityMap.SLAB, z0 + 0.3), col("white", -0.15))
	# canopy: four slender posts at the corners, a frame and a pale glass roof
	var ch := 2.5
	for cx: float in [r.position.x + 0.06, r.end.x - 0.06]:
		for cz: float in [r.position.y + 0.06, r.end.y - 0.06]:
			a.box(Vector3(cx, y + ch * 0.5, cz), Vector3(0.08, ch, 0.08), col("white"), 0.015)
	var g2 := r.grow(0.15)
	a.span(Vector3(g2.position.x, y + ch, g2.position.y), Vector3(g2.end.x, y + ch + 0.06, g2.end.y), col("glass", 0.4))
	for s: float in [0.0, 1.0]:
		if along_x:
			var z := g2.position.y + s * g2.size.y
			a.span(Vector3(g2.position.x, y + ch - 0.04, z - 0.06), Vector3(g2.end.x, y + ch + 0.1, z + 0.06), col("white"))
		else:
			var x := g2.position.x + s * g2.size.x
			a.span(Vector3(x - 0.06, y + ch - 0.04, g2.position.y), Vector3(x + 0.06, y + ch + 0.1, g2.end.y), col("white"))
	var ribs := int((r.size.x if along_x else r.size.y) / 0.8)
	for i in range(1, ribs):
		var t := float(i) / float(ribs)
		if along_x:
			var x := lerpf(g2.position.x, g2.end.x, t)
			a.span(Vector3(x - 0.03, y + ch + 0.05, g2.position.y), Vector3(x + 0.03, y + ch + 0.09, g2.end.y), col("white"))
		else:
			var z := lerpf(g2.position.y, g2.end.y, t)
			a.span(Vector3(g2.position.x, y + ch + 0.05, z - 0.03), Vector3(g2.end.x, y + ch + 0.09, z + 0.03), col("white"))


# ===================================================================== voxel icons and signs

const ICONS := {
	"bread": {"rows": ["..www..", ".wcwcw.", "wwwwwww", "wwwwwww", ".wwwww."], "map": {"w": ["wood", 0.0], "c": ["cream", 0.0]}},
	"flower": {"rows": [".p.p.", "ppypp", ".ppp.", "g.g.g", ".ggg.", "..g.."], "map": {"p": ["coral", 0.0], "y": ["yellow", 0.0], "g": ["green_deep", 0.0]}},
	"teddy": {"rows": ["w...w", "wwwww", "wkwkw", "wwnww", ".www."], "map": {"w": ["wood", 0.0], "k": ["dark", 0.0], "n": ["dark", 0.0]}},
	"book": {"rows": ["bb...bb", "bwbbbwb", "bwwbwwb", "bwwbwwb", "bbbbbbb"], "map": {"b": ["blue", 0.0], "w": ["white", 0.0]}},
	"cone": {"rows": [".ppp.", "ppmpp", ".mmm.", ".www.", "..w.."], "map": {"p": ["coral", 0.4], "m": ["green", 0.4], "w": ["wood", 0.0]}},
	"cup": {"rows": [".s.s..", "..s...", "ccccc.", "ccccck", "ccccc.", ".ccc.."], "map": {"s": ["white", -0.15], "c": ["coral", 0.0], "k": ["coral", 0.0]}},
	"briefcase": {"rows": ["..kk..", ".k..k.", "yyyyyy", "yykkyy", "yyyyyy"], "map": {"k": ["dark", 0.0], "y": ["yellow", 0.0]}},
	"dumbbell": {"rows": ["k.....k", "kk...kk", "kkkkkkk", "kk...kk", "k.....k"], "map": {"k": ["dark", 0.0]}},
	"bus": {"rows": ["bbbbbb", "bgbgbg", "bbbbbb", "bbbbbb", ".k..k."], "map": {"b": ["blue", 0.0], "g": ["glass", 0.0], "k": ["dark", 0.0]}},
	"star": {"rows": ["...y...", "..yyy..", "yyyyyyy", ".yyyyy.", ".yy.yy.", "y.....y"], "map": {"y": ["yellow", 0.0]}},
	"plate": {"rows": [".w...k", "www.k.", ".w.k..", "...k..", "......"], "map": {"w": ["white", 0.0], "k": ["dark", 0.0]}},
}


## A pixel icon standing in the local x-y plane, centred at `c`, facing +z, `px` per pixel.
static func icon(a: Acc, name: String, c: Vector3, px: float, depth := 0.05) -> void:
	var ic: Dictionary = ICONS[name]
	var rows: Array = ic["rows"]
	var mp: Dictionary = ic["map"]
	var h := rows.size()
	var w := String(rows[0]).length()
	for j in h:
		var row := String(rows[j])
		var i := 0
		while i < w:
			var ch := row[i]
			if ch == ".":
				i += 1
				continue
			var k := i
			while k + 1 < w and row[k + 1] == ch:
				k += 1
			var spec: Array = mp[ch]
			var x0 := (float(i) - float(w) * 0.5) * px
			var x1 := (float(k + 1) - float(w) * 0.5) * px
			var y := (float(h) * 0.5 - float(j) - 0.5) * px
			a.box(c + Vector3((x0 + x1) * 0.5, y, depth * 0.5), Vector3(x1 - x0, px, depth), col(String(spec[0]), float(spec[1])))
			i = k + 1


## A framed sign board (local, facing +z) with an icon.
static func sign_board(a: Acc, c: Vector3, size: Vector2, board: Color, frame_col: Color, icon_name: String) -> void:
	a.box(c, Vector3(size.x, size.y, 0.1), frame_col, 0.03)
	a.lit().box(c + Vector3(0, 0, 0.03), Vector3(size.x - 0.12, size.y - 0.12, 0.06), board, 0.01)
	if icon_name != "":
		var ic: Dictionary = ICONS[icon_name]
		var rows: Array = ic["rows"]
		var px := minf((size.y - 0.2) / float(rows.size()), (size.x - 0.2) / float(String(rows[0]).length()))
		icon(a, icon_name, c + Vector3(0, 0, 0.06), px)


## A framed sign board (local, facing +z) with an English word in voxel letters, sized to fit.
static func text_sign(a: Acc, c: Vector3, size: Vector2, board: Color, frame_col: Color, word: String, letters: Color) -> void:
	a.box(c, Vector3(size.x, size.y, 0.1), frame_col, 0.03)
	a.lit().box(c + Vector3(0, 0, 0.03), Vector3(size.x - 0.12, size.y - 0.12, 0.06), board, 0.01)
	var px := minf((size.y - 0.22) / 5.0, (size.x - 0.3) / float(text_cols(word)))
	text(a, word, c + Vector3(0, 0, 0.06), px, letters, 0.05)


# ===================================================================== furniture (FURNITURE kinds)

## Builds one FURNITURE kind into `a` (large parts) and `d` (small details) at its footprint.
## `theme` names the place (a shop id, "cafe", "restaurant", "office", "gym").
static func furniture(a: Acc, d: Acc, kind: String, rect: Rect2, y: float, theme := "", front := "") -> void:
	var fr := frame(rect, y, front if front != "" else String(FRONT.get(kind, "+z")))
	var xf: Transform3D = fr[0]
	var w: float = fr[1]
	var dd: float = fr[2]
	var sa := a.xf
	var sd := d.xf
	a.xf = sa * xf
	d.xf = sd * xf
	match kind:
		"counter": _counter(a, d, w, dd)
		"cafe_table":
			_cafe_table(a, d, w, dd, theme == "cafe_terrace", theme == "corner_cafe")
			if theme == "cafe":
				_pendant(d, 3.0 - y)
		"umbrella_table": _cafe_table(a, d, w, dd, true, false)
		"shelf": _jar_shelf(a, d, w, dd)
		"planter": planter(a, d, w, dd, theme)
		"dining_table":
			_dining_table(a, d, w, dd, theme)
			if theme == "cafe":
				_pendant(d, 3.0 - y)
		"kitchen_bar": _kitchen_bar(a, d, w, dd)
		"treadmill": _treadmill(a, d, w, dd)
		"weight_rack": _weight_rack(a, d, w, dd)
		"mat": _mat(a, d, w, dd)
		"bike": _bike(a, d, w, dd)
		"mirror_wall": _mirror_wall(a, d, w, dd)
		"reception": _reception(a, d, w, dd)
		"sofa": _sofa(a, d, w, dd)
		"desk": _desk(a, d, w, dd)
		"plant": _plant(a, d, w, dd)
		"meeting_table": _meeting_table(a, d, w, dd)
		"shop_counter": _shop_counter(a, d, w, dd, theme)
		"bread_display": _bread_display(a, d, w, dd)
		"bookshelf": _bookshelf(a, d, w, dd, theme)
		"flower_stand": _flower_stand(a, d, w, dd)
		"freezer": _freezer(a, d, w, dd)
		"bistro_table": _bistro_table(a, d, w, dd, theme)
		"coffee_bar": _coffee_bar(a, d, w, dd)
		"pavilion_post": _pavilion_post(a, w, dd)
		"rower": _rower(a, d, w, dd)
		_: a.box(Vector3(0, 0.4, 0), Vector3(w, 0.8, dd), col("cream", -0.15), 0.04)
	a.xf = sa
	d.xf = sd


static func _counter(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.06, 0), Vector3(w - 0.1, 0.12, dd - 0.12), col("dark"))
	a.box(Vector3(0, 0.52, -0.02), Vector3(w - 0.04, 0.8, dd - 0.08), col("wood", -0.15), 0.02)
	a.box(Vector3(0, 0.95, 0), Vector3(w, 0.06, dd), col("cream"), 0.02)
	var slats := int(w / 0.4)
	for i in slats:
		a.box(Vector3(-w * 0.5 + 0.2 + float(i) * (w - 0.4) / float(maxi(slats - 1, 1)), 0.52, dd * 0.5 - 0.03), Vector3(0.28, 0.72, 0.04), col("yellow") if i % 2 == 0 else col("yellow", 0.4))
	# coffee machine, cups, a cake stand and a till
	a.box(Vector3(-w * 0.5 + 0.45, 1.24, -0.1), Vector3(0.6, 0.52, 0.42), col("dark"), 0.04)
	a.box(Vector3(-w * 0.5 + 0.45, 1.52, -0.1), Vector3(0.64, 0.06, 0.46), col("white", -0.15), 0.02)
	d.box(Vector3(-w * 0.5 + 0.45, 1.12, 0.12), Vector3(0.3, 0.04, 0.04), col("white", -0.15))
	for i in 4:
		d.box(Vector3(-w * 0.5 + 1.0 + float(i) * 0.16, 1.03, 0.15), Vector3(0.1, 0.1, 0.1), col("white"), 0.015)
		d.box(Vector3(-w * 0.5 + 1.0 + float(i) * 0.16, 1.62, -0.1), Vector3(0.1, 0.1, 0.1), col("peach") if i % 2 == 0 else col("white"), 0.015)
	a.prism(Vector3(0.4, 1.0, 0), 0.24, 0.04, col("white"), 8)
	a.box(Vector3(0.4, 1.1, 0), Vector3(0.06, 0.16, 0.06), col("white"))
	a.prism(Vector3(0.4, 1.2, 0), 0.3, 0.03, col("white"), 8)
	d.box(Vector3(0.4, 1.31, 0), Vector3(0.36, 0.18, 0.36), col("peach", 0.4), 0.03)
	d.box(Vector3(0.4, 1.41, 0), Vector3(0.36, 0.04, 0.36), col("cream"), 0.01)
	d.box(Vector3(0.4, 1.45, 0), Vector3(0.06, 0.06, 0.06), col("berry"))
	for i in 3:
		d.box(Vector3(1.0 + float(i) * 0.24, 1.03, 0.1), Vector3(0.18, 0.1, 0.18), col("wood", 0.2), 0.03)
		d.box(Vector3(1.0 + float(i) * 0.24, 1.09, 0.1), Vector3(0.18, 0.03, 0.18), col("peach", 0.4) if i != 1 else col("cream"))
	a.box(Vector3(w * 0.5 - 0.35, 1.08, -0.05), Vector3(0.36, 0.2, 0.3), col("dark", 0.2), 0.03)
	d.box(Vector3(w * 0.5 - 0.35, 1.22, -0.12), Vector3(0.3, 0.16, 0.04), col("glass"))


static func _cafe_table(a: Acc, d: Acc, w: float, dd: float, umbrella: bool, with_chairs: bool) -> void:
	if with_chairs:
		_chairs_around(a, w, "cafe")
	a.box(Vector3(0, 0.025, 0), Vector3(0.44, 0.05, 0.44), col("dark"), 0.015)
	a.box(Vector3(0, 0.36, 0), Vector3(0.08, 0.66, 0.08), col("dark"))
	a.box(Vector3(0, 0.71, 0), Vector3(w, 0.05, dd), col("white"), 0.02)
	a.box(Vector3(0, 0.67, 0), Vector3(w - 0.1, 0.04, dd - 0.1), col("wood"))
	d.box(Vector3(0.18, 0.79, -0.1), Vector3(0.1, 0.11, 0.1), col("white"), 0.015)
	d.box(Vector3(0.18, 0.84, -0.1), Vector3(0.06, 0.02, 0.06), col("wood", -0.5))
	d.box(Vector3(-0.15, 0.8, 0.12), Vector3(0.07, 0.14, 0.07), col("glass"))
	d.box(Vector3(-0.15, 0.92, 0.12), Vector3(0.1, 0.08, 0.1), col("peach", 0.4), 0.02)
	d.prism(Vector3(0.0, 0.74, 0.18), 0.11, 0.02, col("white"), 8)
	d.box(Vector3(0.0, 0.77, 0.18), Vector3(0.1, 0.05, 0.08), col("yellow"))
	d.prism(Vector3(-0.18, 0.74, -0.18), 0.09, 0.02, col("white"), 8)
	d.box(Vector3(-0.18, 0.78, -0.18), Vector3(0.08, 0.08, 0.08), col("white"))
	if umbrella:
		a.box(Vector3(0, 1.3, 0), Vector3(0.05, 1.9, 0.05), col("white"))
		# a stepped square canopy in stripes
		var steps: Array[Vector2] = [Vector2(2.2, 2.08), Vector2(1.6, 2.2), Vector2(1.0, 2.3), Vector2(0.45, 2.38)]
		for i in steps.size():
			var s := steps[i]
			a.box(Vector3(0, s.y, 0), Vector3(s.x, 0.12, s.x), col("yellow") if i % 2 == 0 else col("cream"), 0.03)
		for i in 8:
			var ang := TAU * float(i) / 8.0
			a.box(Vector3(cos(ang) * 1.02, 1.97, sin(ang) * 1.02), Vector3(0.16, 0.1, 0.16), col("cream") if i % 2 == 0 else col("yellow"), 0.02)
		a.box(Vector3(0, 2.47, 0), Vector3(0.1, 0.1, 0.1), col("white"), 0.02)


static func _jar_shelf(a: Acc, d: Acc, w: float, dd: float) -> void:
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.04), 1.0, 0), Vector3(0.08, 2.0, dd), col("wood", -0.15))
	a.box(Vector3(0, 1.0, -dd * 0.5 + 0.02), Vector3(w, 2.0, 0.04), col("cream", -0.15))
	var jars := ["coral", "yellow", "green", "berry", "wood", "glass"]
	for k in 5:
		var yy := 0.08 + float(k) * 0.46
		a.box(Vector3(0, yy, 0), Vector3(w - 0.08, 0.05, dd - 0.02), col("wood"))
		if k == 0:
			continue
		var n := int((w - 0.3) / 0.3)
		for i in n:
			var c := String(jars[(i + k) % jars.size()])
			var x := -w * 0.5 + 0.3 + float(i) * 0.3
			d.box(Vector3(x, yy + 0.13, 0.02), Vector3(0.16, 0.2, 0.16), col("glass"), 0.02)
			d.box(Vector3(x, yy + 0.1, 0.02), Vector3(0.12, 0.12, 0.12), col(c))
			d.box(Vector3(x, yy + 0.25, 0.02), Vector3(0.12, 0.04, 0.12), col("wood", -0.3))


## A planter box (any size); along the front of a long ground planter, a wooden bench ledge.
static func planter(a: Acc, d: Acc, w: float, dd: float, theme := "") -> void:
	var h := 0.45 if theme == "street" else 0.5
	a.box(Vector3(0, h * 0.5, 0), Vector3(w, h, dd), col("cream", -0.15) if theme == "street" else col("wood", -0.15), 0.04)
	a.box(Vector3(0, h + 0.03, 0), Vector3(w + 0.06, 0.06, dd + 0.06), col("white"), 0.02)
	var has_bench := theme == "street" and w >= 2.0
	var soil_d := dd - 0.16 - (0.3 if has_bench else 0.0)
	var soil_z := -(0.3 if has_bench else 0.0) * 0.5
	a.box(Vector3(0, h + 0.04, soil_z), Vector3(w - 0.16, 0.04, soil_d), col("wood", -0.5))
	var n := maxi(1, int(w / 0.45))
	for i in n:
		var x := -w * 0.5 + 0.3 + float(i) * (w - 0.6) / float(maxi(n - 1, 1))
		var hh := 0.3 + 0.12 * float((i * 7) % 3)
		a.box(Vector3(x, h + 0.04 + hh * 0.5, soil_z), Vector3(0.36, hh, minf(0.36, soil_d)), col("green", -0.15 if i % 2 == 0 else 0.0), 0.06)
		var fc: Array[String] = ["coral", "yellow", "berry", "white"]
		d.box(Vector3(x + 0.08, h + 0.1 + hh, soil_z + 0.06), Vector3(0.1, 0.1, 0.1), col(fc[i % 4], 0.2 if fc[i % 4] == "coral" else 0.0), 0.02)
		d.box(Vector3(x - 0.1, h + 0.04 + hh * 0.7, soil_z - 0.1), Vector3(0.08, 0.08, 0.08), col(fc[(i + 2) % 4]), 0.02)
	if has_bench:
		for i in 3:
			a.box(Vector3(0, h + 0.07, dd * 0.5 - 0.08 - float(i) * 0.1), Vector3(w - 0.1, 0.05, 0.08), col("wood"), 0.015)


static func _dining_table(a: Acc, d: Acc, w: float, dd: float, theme: String) -> void:
	var outdoor := theme == "restaurant" or theme == "cafe_terrace" or theme == "gym_terrace"
	if theme == "cafe":
		# an indoor table: four chairs along its long sides, facing it
		for sz: float in [-1.0, 1.0]:
			for sx: float in [-1.0, 1.0]:
				var sv := a.xf
				a.xf = sv * Transform3D(Basis(Vector3.UP, PI if sz > 0.0 else 0.0), Vector3(sx * w * 0.24, 0, sz * (dd * 0.5 + 0.28)))
				chair(a, "cafe")
				a.xf = sv
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * (w * 0.5 - 0.1), 0.35, sz * (dd * 0.5 - 0.1)), Vector3(0.07, 0.7, 0.07), col("wood", -0.3))
	a.box(Vector3(0, 0.73, 0), Vector3(w, 0.06, dd), col("white"), 0.02)
	a.box(Vector3(0, 0.765, 0), Vector3(w * 0.5, 0.012, dd + 0.02), col("peach"))
	for p: Vector2 in [Vector2(-0.3, 0), Vector2(0.3, 0)]:
		d.prism(Vector3(p.x, 0.775, p.y), 0.16, 0.02, col("white"), 8)
		d.box(Vector3(p.x, 0.795, p.y), Vector3(0.14, 0.03, 0.14), col("green", 0.2) if p.x < 0.0 else col("peach", 0.4), 0.01)
		d.box(Vector3(p.x, 0.82, p.y - 0.2), Vector3(0.06, 0.1, 0.06), col("glass"))
	d.box(Vector3(0, 0.8, 0.2), Vector3(0.06, 0.06, 0.06), col("cream"))
	d.box(Vector3(0, 0.85, 0.2), Vector3(0.02, 0.04, 0.02), col("yellow"))
	# tableware on every side and a little vase of flowers
	for p: Vector2 in [Vector2(0, -0.3), Vector2(0, 0.3)]:
		d.prism(Vector3(p.x - 0.1, 0.775, p.y), 0.13, 0.02, col("white"), 8)
		d.box(Vector3(p.x - 0.1, 0.792, p.y), Vector3(0.1, 0.02, 0.1), col("yellow", -0.15))
		d.box(Vector3(p.x + 0.12, 0.81, p.y), Vector3(0.05, 0.09, 0.05), col("glass"))
	d.box(Vector3(0.15, 0.82, 0.0), Vector3(0.07, 0.1, 0.07), col("blue", 0.4))
	d.box(Vector3(0.15, 0.9, 0.0), Vector3(0.11, 0.07, 0.11), col("peach"))
	if not outdoor:
		return
	# a parasol over every rooftop table
	a.box(Vector3(0, 1.35, 0), Vector3(0.05, 1.3, 0.05), col("white"))
	var steps: Array[Vector2] = [Vector2(2.0, 2.05), Vector2(1.4, 2.17), Vector2(0.8, 2.27)]
	for i in steps.size():
		a.box(Vector3(0, steps[i].y, 0), Vector3(steps[i].x, 0.12, steps[i].x), col("peach") if i % 2 == 0 else col("cream"), 0.03)
	a.box(Vector3(0, 2.36, 0), Vector3(0.1, 0.1, 0.1), col("white"), 0.02)


static func _kitchen_bar(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.5, 0), Vector3(w - 0.04, 1.0, dd - 0.04), col("peach"), 0.03)
	a.box(Vector3(0, 1.03, 0.04), Vector3(w + 0.04, 0.06, dd + 0.08), col("white"), 0.02)
	for i in int(w / 0.5):
		a.box(Vector3(-w * 0.5 + 0.25 + float(i) * 0.5, 0.5, dd * 0.5), Vector3(0.06, 0.8, 0.03), col("peach", 0.4))
	# the cook's side: a grill, pots, plates, a menu board and a striped canopy on two posts
	a.box(Vector3(-w * 0.25, 1.12, -0.15), Vector3(0.9, 0.12, 0.4), col("dark"), 0.02)
	for i in 3:
		d.box(Vector3(-w * 0.25 - 0.3 + float(i) * 0.3, 1.24, -0.15), Vector3(0.2, 0.12, 0.2), col("dark", 0.2), 0.03)
	for i in 4:
		d.prism(Vector3(w * 0.1 + float(i) * 0.3, 1.075, 0.15), 0.12, 0.03, col("white"), 8)
		d.box(Vector3(w * 0.1 + float(i) * 0.3, 1.1, 0.15), Vector3(0.1, 0.04, 0.1), col("yellow", -0.15) if i % 2 == 0 else col("green"))
	# a menu board standing on the bar's back edge, bottles, and two bar stools for diners
	for sx: float in [-0.4, 0.4]:
		a.box(Vector3(w * 0.3 + sx, 1.2, -dd * 0.5 + 0.08), Vector3(0.05, 0.3, 0.05), col("dark"))
	sign_board(a, Vector3(w * 0.3, 1.66, -dd * 0.5 + 0.08), Vector2(1.0, 0.66), col("cream"), col("peach", -0.15), "plate")
	for i in 5:
		d.box(Vector3(-w * 0.5 + 0.2 + float(i) * 0.12, 1.16, -dd * 0.5 + 0.12), Vector3(0.07, 0.2, 0.07), col("green", -0.3) if i % 2 == 0 else col("berry"))
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * w * 0.33, 0, dd * 0.5 + 0.35)
		a.prism(p + Vector3(0, 0.03, 0), 0.2, 0.06, col("dark"), 6)
		a.box(p + Vector3(0, 0.36, 0), Vector3(0.06, 0.6, 0.06), col("dark"))
		a.prism(p + Vector3(0, 0.7, 0), 0.19, 0.08, col("peach"), 8)


static func _treadmill(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.07, 0.05), Vector3(w - 0.04, 0.14, dd - 0.1), col("dark"), 0.03)
	a.box(Vector3(0, 0.145, 0.1), Vector3(w - 0.24, 0.02, dd - 0.4), col("dark", 0.2))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.06), 0.16, 0.05), Vector3(0.1, 0.06, dd - 0.2), col("white", -0.15))
		a.beam(Vector3(sx * (w * 0.5 - 0.06), 0.14, -dd * 0.5 + 0.12), Vector3(sx * (w * 0.5 - 0.06), 1.15, -dd * 0.5 + 0.25), 0.07, 0.07, col("white", -0.15))
		a.box(Vector3(sx * (w * 0.5 - 0.06), 1.0, -dd * 0.5 + 0.55), Vector3(0.06, 0.06, 0.6), col("dark"))
	a.box(Vector3(0, 1.22, -dd * 0.5 + 0.27), Vector3(w - 0.04, 0.12, 0.3), col("peach"), 0.03)
	d.box(Vector3(0, 1.26, -dd * 0.5 + 0.43), Vector3(0.36, 0.08, 0.02), col("glass"))
	d.box(Vector3(0.22, 1.29, -dd * 0.5 + 0.35), Vector3(0.08, 0.04, 0.08), col("yellow"))


static func _weight_rack(a: Acc, d: Acc, w: float, _dd: float) -> void:
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.05), 0.6, -0.05), Vector3(0.08, 1.2, 0.5), col("dark"))
	a.box(Vector3(0, 0.3, -0.05), Vector3(w, 0.05, 0.5), col("dark", 0.2))
	a.box(Vector3(0, 0.75, -0.05), Vector3(w, 0.05, 0.5), col("dark", 0.2))
	for i in 5:
		var x := -w * 0.5 + 0.25 + float(i) * (w - 0.5) / 4.0
		var c := col("peach") if i % 2 == 0 else col("blue")
		var sz := 0.1 + 0.02 * float(i)
		for sx: float in [-1.0, 1.0]:
			d.box(Vector3(x + sx * 0.09, 0.4, -0.05), Vector3(0.05, sz * 1.4, sz * 1.4), c, 0.01)
		d.box(Vector3(x, 0.4, -0.05), Vector3(0.18, 0.03, 0.03), col("white", -0.15))
	# a barbell across the top and a stack of plates beside it
	a.box(Vector3(0, 1.25, 0.05), Vector3(w + 0.2, 0.04, 0.04), col("white", -0.15))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 + 0.02), 1.25, 0.05), Vector3(0.06, 0.36, 0.36), col("dark"), 0.02)
		a.box(Vector3(sx * (w * 0.5 - 0.06), 1.25, 0.05), Vector3(0.05, 0.26, 0.26), col("peach"), 0.02)
	for k in 3:
		d.box(Vector3(-w * 0.5 + 0.3, 0.82 + float(k) * 0.05, -0.05), Vector3(0.3, 0.04, 0.3), col("dark", 0.2) if k % 2 == 0 else col("peach", -0.15), 0.01)


static func _mat(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.02, 0), Vector3(w, 0.04, dd), col("peach", 0.4), 0.01)
	a.box(Vector3(0, 0.042, 0), Vector3(w - 0.2, 0.004, dd - 0.2), col("peach", 0.6))
	a.box(Vector3(w * 0.5 - 0.35, 0.3, -dd * 0.5 + 0.35), Vector3(0.5, 0.5, 0.5), col("blue", 0.4), 0.18)
	d.box(Vector3(-w * 0.5 + 0.25, 0.12, dd * 0.5 - 0.2), Vector3(0.18, 0.16, 0.14), col("dark"), 0.04)
	d.box(Vector3(-w * 0.5 + 0.25, 0.23, dd * 0.5 - 0.2), Vector3(0.12, 0.05, 0.04), col("dark"))
	d.box(Vector3(-w * 0.5 + 0.55, 0.04, dd * 0.5 - 0.2), Vector3(0.12, 0.06, 0.3), col("yellow"), 0.02)


static func _bike(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.04, 0), Vector3(w - 0.2, 0.08, dd - 0.1), col("dark"), 0.02)
	# flywheel at the front (-z), a frame, the saddle at the back, handlebars at the front
	a.prism(Vector3(0, 0.36, -dd * 0.5 + 0.28), 0.26, 0.08, col("peach"), 10, Basis(Vector3.FORWARD, PI * 0.5))
	a.prism(Vector3(0, 0.36, -dd * 0.5 + 0.28), 0.12, 0.12, col("white", -0.15), 8, Basis(Vector3.FORWARD, PI * 0.5))
	a.beam(Vector3(0, 0.08, dd * 0.5 - 0.3), Vector3(0, 0.72, dd * 0.5 - 0.38), 0.07, 0.07, col("white", -0.15))
	a.beam(Vector3(0, 0.08, -dd * 0.5 + 0.2), Vector3(0, 0.98, -dd * 0.5 + 0.3), 0.07, 0.07, col("white", -0.15))
	a.beam(Vector3(0, 0.36, -dd * 0.5 + 0.28), Vector3(0, 0.5, dd * 0.5 - 0.34), 0.06, 0.06, col("white", -0.15))
	a.box(Vector3(0, 0.76, dd * 0.5 - 0.38), Vector3(0.2, 0.06, 0.28), col("dark"), 0.02)
	a.box(Vector3(0, 1.0, -dd * 0.5 + 0.32), Vector3(0.46, 0.04, 0.06), col("dark"))
	d.box(Vector3(0, 1.04, -dd * 0.5 + 0.26), Vector3(0.16, 0.1, 0.06), col("glass"), 0.01)
	for sx: float in [-1.0, 1.0]:
		d.box(Vector3(sx * 0.12, 0.34, -0.02), Vector3(0.04, 0.04, 0.16), col("dark"))


static func _mirror_wall(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 1.2, -dd * 0.25), Vector3(w, 2.0, 0.06), col("white"), 0.02)
	a.box(Vector3(0, 1.2, -dd * 0.25 + 0.035), Vector3(w - 0.12, 1.88, 0.02), col("glass", 0.4))
	for i in range(1, int(w / 1.5)):
		d.box(Vector3(-w * 0.5 + float(i) * 1.5, 1.2, -dd * 0.25 + 0.05), Vector3(0.04, 1.88, 0.02), col("white"))
	a.box(Vector3(0, 0.95, dd * 0.5 - 0.02), Vector3(w - 0.2, 0.05, 0.05), col("wood"))


static func _reception(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.55, 0), Vector3(w, 1.1, dd), col("blue"), 0.03)
	a.box(Vector3(0, 1.13, 0.04), Vector3(w + 0.06, 0.06, dd + 0.1), col("white"), 0.02)
	a.box(Vector3(0, 0.75, -0.18), Vector3(w - 0.3, 0.05, dd - 0.3), col("white", -0.15))
	for i in int(w / 0.3):
		a.box(Vector3(-w * 0.5 + 0.15 + float(i) * 0.3, 0.55, dd * 0.5 + 0.005), Vector3(0.14, 0.8, 0.02), col("blue", 0.2))
	a.box(Vector3(-0.6, 1.36, -0.1), Vector3(0.5, 0.34, 0.04), col("dark"), 0.01)
	d.box(Vector3(-0.6, 1.36, -0.075), Vector3(0.44, 0.28, 0.01), col("glass"))
	d.box(Vector3(0.5, 1.2, 0.1), Vector3(0.12, 0.08, 0.12), col("yellow"), 0.03)
	_pot_plant(d, Vector3(w * 0.5 - 0.25, 1.16, -0.1), 0.18, 0.4)


static func _sofa(a: Acc, d: Acc, w: float, dd: float) -> void:
	var c := col("peach")
	a.box(Vector3(0, 0.22, 0.05), Vector3(w, 0.3, dd - 0.1), col("peach", -0.15), 0.05)
	a.box(Vector3(0, 0.62, -dd * 0.5 + 0.12), Vector3(w, 0.64, 0.24), c, 0.06)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.1), 0.42, 0.05), Vector3(0.2, 0.4, dd - 0.1), c, 0.06)
	var n := 2
	for i in n:
		var x := (float(i) - 0.5) * (w - 0.4) / float(n)
		a.box(Vector3(x, 0.43, 0.12), Vector3((w - 0.44) / float(n) - 0.03, 0.12, dd - 0.34), col("peach", 0.2), 0.04)
	d.box(Vector3(-w * 0.25, 0.62, -dd * 0.5 + 0.3), Vector3(0.36, 0.32, 0.1), col("yellow"), 0.05)
	d.box(Vector3(w * 0.25, 0.62, -dd * 0.5 + 0.3), Vector3(0.36, 0.32, 0.1), col("blue", 0.2), 0.05)


static func _desk(a: Acc, d: Acc, w: float, dd: float) -> void:
	# its office chair, where the worker sits (pulled up to the desk from +z)
	var sv := a.xf
	a.xf = sv * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, dd * 0.5 + 0.2))
	chair(a, "office")
	a.xf = sv
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.05), 0.36, 0), Vector3(0.06, 0.72, dd - 0.1), col("white", -0.15))
	a.box(Vector3(0, 0.74, 0), Vector3(w, 0.05, dd), col("white"), 0.02)
	a.box(Vector3(-w * 0.5 + 0.25, 0.35, 0), Vector3(0.4, 0.6, dd - 0.15), col("blue", 0.2), 0.02)
	a.box(Vector3(0, 0.79, -dd * 0.5 + 0.18), Vector3(0.18, 0.04, 0.14), col("dark"))
	a.box(Vector3(0, 0.9, -dd * 0.5 + 0.2), Vector3(0.05, 0.2, 0.04), col("dark"))
	a.box(Vector3(0, 1.12, -dd * 0.5 + 0.2), Vector3(0.62, 0.38, 0.04), col("dark"), 0.01)
	d.box(Vector3(0, 1.12, -dd * 0.5 + 0.225), Vector3(0.56, 0.32, 0.01), col("glass"))
	d.box(Vector3(0, 0.775, 0.1), Vector3(0.44, 0.02, 0.14), col("white", -0.15))
	d.box(Vector3(0.36, 0.8, 0.12), Vector3(0.08, 0.08, 0.08), col("peach"), 0.01)
	d.box(Vector3(w * 0.5 - 0.15, 0.79, -0.15), Vector3(0.1, 0.04, 0.1), col("dark"))
	d.beam(Vector3(w * 0.5 - 0.15, 0.8, -0.15), Vector3(w * 0.5 - 0.2, 1.1, -0.05), 0.03, 0.03, col("dark"))
	d.box(Vector3(w * 0.5 - 0.22, 1.08, 0.0), Vector3(0.14, 0.08, 0.14), col("yellow"), 0.02)


static func _pot_plant(a: Acc, base: Vector3, r: float, h: float) -> void:
	a.box(base + Vector3(0, r * 0.7, 0), Vector3(r * 1.4, r * 1.4, r * 1.4), col("peach", -0.15), 0.03)
	a.box(base + Vector3(0, r * 1.4 + h * 0.4, 0), Vector3(r * 1.6, h * 0.8, r * 1.6), col("green"), 0.05)
	a.box(base + Vector3(0, r * 1.4 + h * 0.9, 0), Vector3(r, h * 0.4, r), col("green", 0.2), 0.04)


static func _plant(a: Acc, d: Acc, w: float, _dd: float) -> void:
	a.box(Vector3(0, 0.22, 0), Vector3(w * 0.7, 0.44, w * 0.7), col("white"), 0.04)
	a.box(Vector3(0, 0.45, 0), Vector3(w * 0.74, 0.04, w * 0.74), col("blue"), 0.01)
	a.box(Vector3(0, 0.62, 0), Vector3(0.06, 0.4, 0.06), col("wood", -0.3))
	a.box(Vector3(0, 0.95, 0), Vector3(w * 0.9, 0.5, w * 0.9), col("green"), 0.06)
	a.box(Vector3(0, 1.3, 0), Vector3(w * 0.6, 0.3, w * 0.6), col("green", 0.2), 0.05)
	d.box(Vector3(0.18, 1.0, 0.18), Vector3(0.18, 0.2, 0.18), col("green_deep"), 0.04)


static func _meeting_table(a: Acc, d: Acc, w: float, dd: float) -> void:
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.3), 0.36, 0), Vector3(0.1, 0.72, dd - 0.4), col("white", -0.15))
	a.box(Vector3(0, 0.74, 0), Vector3(w, 0.06, dd), col("wood"), 0.03)
	# six office chairs drawn up to its long sides, papers, laptops and mugs at each place
	for i in 3:
		var x := (float(i) - 1.0) * w / 3.2
		for sz: float in [-1.0, 1.0]:
			var sv := a.xf
			a.xf = sv * Transform3D(Basis(Vector3.UP, PI if sz > 0.0 else 0.0), Vector3(x, 0, sz * (dd * 0.5 + 0.25)))
			chair(a, "office")
			a.xf = sv
			d.box(Vector3(x, 0.79, sz * (dd * 0.5 - 0.25)), Vector3(0.3, 0.02, 0.22), col("white", -0.15) if i != 1 else col("dark"))
			d.box(Vector3(x + 0.25, 0.82, sz * (dd * 0.5 - 0.2)), Vector3(0.08, 0.09, 0.08), col("peach") if i % 2 == 0 else col("white"))
	d.box(Vector3(0, 0.8, 0), Vector3(0.12, 0.1, 0.12), col("glass"))
	d.box(Vector3(0, 0.9, 0), Vector3(0.14, 0.1, 0.14), col("yellow"), 0.03)


static func _shop_counter(a: Acc, d: Acc, w: float, dd: float, shop: String) -> void:
	var acc_c := accent(shop)
	a.box(Vector3(0, 0.05, 0), Vector3(w - 0.06, 0.1, dd - 0.06), col("dark"))
	a.box(Vector3(0, 0.5, 0), Vector3(w, 0.8, dd), col("mint_deep"), 0.03)
	a.box(Vector3(0, 0.93, 0.02), Vector3(w + 0.06, 0.06, dd + 0.06), col("white"), 0.02)
	for i in int(w / 0.4):
		a.box(Vector3(-w * 0.5 + 0.2 + float(i) * 0.4, 0.5, dd * 0.5 + 0.01), Vector3(0.24, 0.66, 0.02), acc_c)
	match shop:
		"bakery":
			a.box(Vector3(0.3, 1.18, 0), Vector3(1.1, 0.42, dd - 0.1), col("glass"), 0.02)
			a.box(Vector3(0.3, 1.4, 0), Vector3(1.14, 0.04, dd - 0.06), col("wood"))
			for i in 4:
				d.box(Vector3(-0.1 + float(i) * 0.26, 1.48, 0.05), Vector3(0.2, 0.12, 0.14), col("wood", 0.2) if i % 2 == 0 else col("yellow", -0.15), 0.05)
			d.box(Vector3(-0.7, 1.02, 0), Vector3(0.4, 0.12, 0.3), col("wood", -0.3), 0.02)
			for i in 3:
				d.box(Vector3(-0.8 + float(i) * 0.1, 1.12, 0), Vector3(0.09, 0.08, 0.2), col("wood", 0.2), 0.03)
		"flowers":
			for i in 4:
				var x := -0.7 + float(i) * 0.46
				d.box(Vector3(x, 1.08, 0), Vector3(0.18, 0.24, 0.18), col("glass"), 0.02)
				d.box(Vector3(x, 1.3, 0), Vector3(0.04, 0.3, 0.04), col("green_deep"))
				var fc: Array[String] = ["coral", "berry", "yellow", "white"]
				d.box(Vector3(x, 1.5, 0), Vector3(0.24, 0.16, 0.24), col(fc[i], 0.2 if fc[i] == "berry" else 0.0), 0.05)
				d.box(Vector3(x + 0.1, 1.42, 0.06), Vector3(0.1, 0.1, 0.1), col("green"), 0.02)
		"corner_cafe":
			a.box(Vector3(-0.45, 1.2, -0.08), Vector3(0.5, 0.48, 0.36), col("white", -0.15), 0.04)
			a.box(Vector3(-0.45, 1.46, -0.08), Vector3(0.54, 0.04, 0.4), col("dark"))
			d.box(Vector3(-0.45, 1.06, 0.14), Vector3(0.1, 0.08, 0.1), col("white"))
			for i in 3:
				d.box(Vector3(-0.05 + float(i) * 0.13, 1.02, 0.12), Vector3(0.1, 0.09, 0.1), col("white"))
			a.prism(Vector3(0.55, 0.98, 0), 0.22, 0.04, col("white"), 8)
			d.box(Vector3(0.55, 1.06, 0), Vector3(0.24, 0.12, 0.24), col("peach", 0.4))
			d.box(Vector3(0.55, 1.13, 0), Vector3(0.24, 0.03, 0.24), col("cream"))
			d.box(Vector3(0.55, 1.17, 0), Vector3(0.06, 0.06, 0.06), col("berry"))
		"bookstore":
			for k in 3:
				for i in 4:
					var bcs: Array[String] = ["blue", "coral", "green", "yellow", "berry"]
					d.box(Vector3(-0.6 + float(k) * 0.5, 1.0 + float(i) * 0.06, 0), Vector3(0.34 - float(i % 2) * 0.04, 0.05, 0.26), col(bcs[(i + k) % 5]), 0.01)
			d.box(Vector3(0.7, 1.0, 0.05), Vector3(0.46, 0.03, 0.32), col("white"))
		"icecream":
			a.box(Vector3(0, 1.06, 0), Vector3(w - 0.2, 0.2, dd - 0.15), col("white", -0.15), 0.02)
			var ic: Array = [["coral", 0.4], ["green", 0.4], ["wood", -0.3], ["yellow", 0.4], ["cream", 0.0], ["berry", 0.4]]
			for i in 6:
				var spec: Array = ic[i]
				d.box(Vector3(-0.75 + float(i) * 0.3, 1.17, 0.05), Vector3(0.24, 0.04, 0.24), col(String(spec[0]), float(spec[1])))
			a.box(Vector3(0, 1.36, -0.15), Vector3(w - 0.2, 0.04, 0.3), col("glass"))
			for i in 3:
				d.box(Vector3(0.6 + float(i) * 0.12, 1.24, -0.2), Vector3(0.07, 0.14, 0.07), col("wood"))
				d.box(Vector3(0.6 + float(i) * 0.12, 1.34, -0.2), Vector3(0.1, 0.08, 0.1), col("peach", 0.4) if i != 1 else col("green", 0.4), 0.03)
	# a little till at one end
	a.box(Vector3(w * 0.5 - 0.25, 1.06, -0.05), Vector3(0.3, 0.18, 0.26), col("dark", 0.2), 0.03)


## A chair whose sitter faces local +z (the back is at -z). Style: cafe, restaurant, office, terrace.
static func chair(a: Acc, style: String, tint := Color(0, 0, 0, 0)) -> void:
	if style == "office":
		a.prism(Vector3(0, 0.04, 0), 0.26, 0.04, col("dark"), 5)
		a.box(Vector3(0, 0.24, 0), Vector3(0.06, 0.36, 0.06), col("dark"))
		a.box(Vector3(0, 0.45, 0), Vector3(0.46, 0.08, 0.44), col("dark", 0.2), 0.03)
		a.box(Vector3(0, 0.78, -0.22), Vector3(0.44, 0.52, 0.06), col("dark", 0.2), 0.03)
		return
	var seat := col("wood") if style == "cafe" else (col("white") if style == "restaurant" else col("yellow"))
	if tint.a > 0.0:
		seat = tint
	var leg := col("dark") if style != "cafe" else col("wood", -0.3)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * 0.18, 0.21, sz * 0.17), Vector3(0.04, 0.42, 0.04), leg)
	a.box(Vector3(0, 0.44, 0), Vector3(0.44, 0.05, 0.42), seat, 0.015)
	a.box(Vector3(0, 0.72, -0.19), Vector3(0.44, 0.06, 0.04), seat, 0.015)
	a.box(Vector3(0, 0.84, -0.19), Vector3(0.44, 0.06, 0.04), col("peach") if style == "restaurant" else seat, 0.015)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.18, 0.66, -0.19), Vector3(0.04, 0.4, 0.04), leg)


# ===================================================================== street furniture

## A voxel tree: square grate, trunk, stepped green canopy (about 3.6 m).
static func tree(a: Acc, d: Acc, variant: int) -> void:
	for p: Vector4 in [Vector4(0, 0.48, 1.0, 0.04), Vector4(0, -0.48, 1.0, 0.04), Vector4(0.48, 0, 0.04, 1.0), Vector4(-0.48, 0, 0.04, 1.0)]:
		a.box(Vector3(p.x, 0.04, p.y), Vector3(p.z, 0.08, p.w), col("dark", 0.2))
	a.box(Vector3(0, 0.03, 0), Vector3(0.92, 0.04, 0.92), col("wood", -0.3))
	a.box(Vector3(0, 0.9, 0), Vector3(0.24, 1.8, 0.24), col("wood", -0.3), 0.03)
	a.box(Vector3(0.18, 1.55, 0), Vector3(0.3, 0.1, 0.1), col("wood", -0.3))
	var g0 := col("green")
	var g1 := col("green_deep")
	var g2 := col("green", 0.2)
	a.box(Vector3(0, 2.25, 0), Vector3(1.7, 1.1, 1.7), g0, 0.1)
	a.box(Vector3(0, 3.0, 0), Vector3(1.2, 0.6, 1.2), g2, 0.08)
	a.box(Vector3(0, 3.42, 0), Vector3(0.6, 0.3, 0.6), g2, 0.06)
	var r := RandomNumberGenerator.new()
	r.seed = variant
	for i in 4:
		var ang := TAU * float(i) / 4.0 + r.randf() * 0.6
		d.box(Vector3(cos(ang) * 0.82, 2.0 + r.randf() * 0.5, sin(ang) * 0.82), Vector3(0.5, 0.5, 0.5), g1, 0.06)
	d.box(Vector3(0.5, 2.85, 0.4), Vector3(0.12, 0.12, 0.12), col("peach", 0.2), 0.02)


## A street lamp (about 3.9 m): plinth, square pole, two little banners and a lantern.
static func lamp(a: Acc, d: Acc, banner: String) -> void:
	a.box(Vector3(0, 0.15, 0), Vector3(0.32, 0.3, 0.32), col("dark"), 0.03)
	a.box(Vector3(0, 1.85, 0), Vector3(0.12, 3.4, 0.12), col("dark"), 0.02)
	a.box(Vector3(0, 3.5, 0), Vector3(0.2, 0.08, 0.2), col("dark"))
	a.lit().box(Vector3(0, 3.7, 0), Vector3(0.3, 0.36, 0.3), col("cream"), 0.03)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * 0.15, 3.7, sz * 0.15), Vector3(0.04, 0.38, 0.04), col("dark"))
	a.box(Vector3(0, 3.92, 0), Vector3(0.38, 0.08, 0.38), col("dark"), 0.02)
	a.box(Vector3(0, 4.0, 0), Vector3(0.2, 0.08, 0.2), col("dark"))
	d.box(Vector3(0.22, 2.7, 0), Vector3(0.32, 0.03, 0.03), col("dark"))
	d.box(Vector3(0.26, 2.35, 0), Vector3(0.26, 0.66, 0.02), col(banner))
	d.box(Vector3(0.26, 2.35, 0.012), Vector3(0.12, 0.12, 0.01), col("white"))


## The bus shelter (local: width w along x, depth dd along z, the back panel at -z, open to the road at +z).
static func bus_shelter(a: Acc, d: Acc, w: float, dd: float) -> void:
	var white := col("white")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * (w * 0.5 - 0.06), 1.3, sz * (dd * 0.5 - 0.06)), Vector3(0.08, 2.6, 0.08), col("dark"), 0.015)
	# the roof reaches 0.7 m past the back over the pavement, where people wait dry (r3)
	a.box(Vector3(0, 2.66, -0.3), Vector3(w + 0.2, 0.12, dd + 1.0), col("blue"), 0.03)
	a.box(Vector3(0, 2.75, -0.3), Vector3(w, 0.06, dd + 0.8), white, 0.02)
	a.box(Vector3(0, 1.35, -dd * 0.5 + 0.06), Vector3(w - 0.16, 2.1, 0.04), col("glass"))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.06), 1.35, 0.0), Vector3(0.04, 2.1, dd - 0.2), col("glass"))
	a.box(Vector3(0, 2.45, -dd * 0.5 + 0.06), Vector3(w - 0.16, 0.08, 0.06), col("dark"))
	# bench and a map/timetable panel
	a.box(Vector3(0, 0.44, -dd * 0.5 + 0.3), Vector3(w * 0.6, 0.06, 0.36), col("wood"), 0.02)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * w * 0.25, 0.21, -dd * 0.5 + 0.3), Vector3(0.06, 0.42, 0.3), col("dark"))
	a.box(Vector3(w * 0.5 - 0.6, 1.4, -dd * 0.5 + 0.1), Vector3(0.7, 0.9, 0.04), white, 0.01)
	for i in 4:
		d.box(Vector3(w * 0.5 - 0.6, 1.65 - float(i) * 0.15, -dd * 0.5 + 0.125), Vector3(0.5, 0.06, 0.01), col("blue") if i == 0 else col("dark", 0.2))
	# the bus stop sign on its own pole at the road end
	var px := -w * 0.5 + 0.12
	a.box(Vector3(px, 1.5, dd * 0.5 - 0.1), Vector3(0.08, 3.0, 0.08), col("dark"))
	text_sign(a, Vector3(px + 0.2, 2.95, dd * 0.5 - 0.06), Vector2(1.1, 0.42), white, col("blue", -0.15), "BUS STOP", col("blue", -0.3))


# ===================================================================== the Ferris wheel

## Rim radius (gondola pivots) and the half spacing of the wheel's two rims along z.
const RIM_Z := 0.68
const GONDOLA_HALF := Vector3(0.75, 0.0, 0.6)


## The rotating wheel in its own frame (the hub at the origin, the wheel in the x-y plane):
## two berry rims, cream spokes and inner ring, the gondola axles, rim bulbs and the hub.
static func ferris_wheel(a: Acc) -> void:
	var rad: float = CityMap.FERRIS["radius"]
	var n := 32
	var berry := col("berry")
	var cream := col("cream")
	for z: float in [-RIM_Z, RIM_Z]:
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			var p0 := Vector3(cos(a0) * rad, sin(a0) * rad, z)
			var p1 := Vector3(cos(a1) * rad, sin(a1) * rad, z)
			a.beam(p0, p1, 0.16, 0.1, berry, 0.02)
			a.beam(p0 * Vector3(0.78, 0.78, 1), p1 * Vector3(0.78, 0.78, 1), 0.08, 0.06, cream)
			var o := Vector3(cos(a0), sin(a0), 0) * (rad + 0.12) + Vector3(0, 0, z)
			a.lit().box(o, Vector3(0.12, 0.12, 0.12), cream, 0.02)
		for i in 16:
			var ang := TAU * float(i) / 16.0
			var tip := Vector3(cos(ang) * rad, sin(ang) * rad, z)
			a.beam(Vector3(cos(ang) * 0.5, sin(ang) * 0.5, z), tip, 0.07, 0.06, cream)
	for i in 8:
		var ang := -PI * 0.5 + TAU * float(i) / 8.0
		var p := Vector3(cos(ang) * rad, sin(ang) * rad, 0)
		a.box(p, Vector3(0.1, 0.1, RIM_Z * 2.0 + 0.12), col("dark"))
		var q := Vector3(cos(ang + TAU / 16.0) * rad, sin(ang + TAU / 16.0) * rad, 0)
		a.box(q, Vector3(0.07, 0.07, RIM_Z * 2.0), cream)
	var zb := Basis(Vector3.RIGHT, PI * 0.5)
	a.prism(Vector3.ZERO, 0.62, RIM_Z * 2.0 + 0.1, berry, 8, zb)
	a.prism(Vector3.ZERO, 0.38, RIM_Z * 2.0 + 0.3, cream, 8, zb)
	icon(a, "star", Vector3(0, 0, RIM_Z + 0.15), 0.07, 0.04)


## A gondola hanging from its pivot (the origin): a hanger yoke, a berry or cream cabin with benches
## on its two ends (riders face each other along x), corner posts and a stepped roof.
static func gondola(a: Acc, i: int) -> void:
	var hang: float = CityMap.FERRIS["hang"]
	var main: Color = CityMap.CABIN_COLORS[posmod(i, CityMap.CABIN_COLORS.size())]
	var trim := col("white")
	var hx := GONDOLA_HALF.x
	var hz := GONDOLA_HALF.z
	var floor_y := -hang
	a.box(Vector3(0, -0.05, 0), Vector3(0.16, 0.16, RIM_Z * 2.0 - 0.06), col("dark"))
	for sz: float in [-1.0, 1.0]:
		a.box(Vector3(0, -0.12, sz * 0.22), Vector3(0.06, 0.16, 0.05), col("dark"))
	a.box(Vector3(0, -0.24, 0), Vector3(hx * 2.0 + 0.1, 0.1, hz * 2.0 + 0.08), main, 0.03)
	a.box(Vector3(0, -0.16, 0), Vector3(hx * 1.2, 0.08, hz * 1.2), trim, 0.02)
	a.box(Vector3(0, -0.31, 0), Vector3(hx * 2.0 + 0.12, 0.05, hz * 2.0 + 0.1), trim)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * (hx - 0.04), (floor_y - 0.29) * 0.5, sz * (hz - 0.04)), Vector3(0.06, -0.29 - floor_y, 0.06), trim)
	a.box(Vector3(0, floor_y - 0.05, 0), Vector3(hx * 2.0, 0.1, hz * 2.0), col("dark", 0.2), 0.02)
	# low walls: ends full, the sides with a gap in the middle for boarding
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (hx - 0.03), floor_y + 0.28, 0), Vector3(0.06, 0.56, hz * 2.0), main, 0.01)
		a.box(Vector3(sx * (hx - 0.25), floor_y + 0.15, 0), Vector3(0.4, 0.3, hz * 2.0 - 0.12), trim, 0.02)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			a.box(Vector3(sx * (hx - 0.27), floor_y + 0.28, sz * (hz - 0.03)), Vector3(0.5, 0.56, 0.06), main, 0.01)
		a.box(Vector3(0, floor_y + 0.58, sz * (hz - 0.03)), Vector3(hx * 2.0, 0.05, 0.08), trim)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (hx - 0.03), floor_y + 0.58, 0), Vector3(0.08, 0.05, hz * 2.0), trim)


## The static base (world coordinates): one leg on each CityMap wheel_leg circle, so two A-frames stand
## in the planes either side of the gondolas; braces, bearings, the axle, the boarding platform (no rails
## on it: gondolas sweep low over its ends) and a name sign on the front A-frame's brace.
static func ferris_base(a: Acc) -> void:
	var hub: Vector3 = CityMap.FERRIS["hub"]
	var cream := col("cream")
	var berry := col("berry")
	var feet: Array[Vector2] = []
	for s in CityMap.GROUND_SOLIDS:
		if String(s["kind"]) == "wheel_leg":
			feet.append(s["at"])
	var tops := {}
	for f in feet:
		var sx := signf(f.x - hub.x)
		var sz := signf(f.y - hub.z)
		a.prism(Vector3(f.x, 0.08, f.y), 0.38, 0.16, col("kerb"), 8)
		var top := Vector3(hub.x + sx * 0.3, hub.y, f.y)
		a.beam(Vector3(f.x, 0.16, f.y), top, 0.2, 0.2, cream, 0.03)
		tops[Vector2(sx, sz)] = top
		a.box(Vector3(f.x, 0.26, f.y), Vector3(0.3, 0.2, 0.3), berry, 0.03)
	var yb := 3.4
	for sz: float in [-1.0, 1.0]:
		var zb := hub.z + sz * absf(feet[0].y - hub.z)
		var xs: Array[float] = []
		for f in feet:
			if signf(f.y - hub.z) == sz:
				var t := (yb - 0.16) / (hub.y - 0.16)
				xs.append(lerpf(f.x, hub.x + signf(f.x - hub.x) * 0.3, t))
		if xs.size() == 2:
			a.box(Vector3((xs[0] + xs[1]) * 0.5, yb, zb), Vector3(absf(xs[1] - xs[0]), 0.16, 0.14), berry, 0.03)
			if sz > 0.0:
				# the name sign on the front brace, between the legs
				var sb := a.xf
				a.xf = sb * Transform3D(Basis.IDENTITY, Vector3(hub.x, yb + 0.5, zb + 0.08))
				a.box(Vector3.ZERO, Vector3(3.8, 0.66, 0.08), berry, 0.02)
				a.lit().box(Vector3(0, 0, 0.03), Vector3(3.64, 0.5, 0.04), cream)
				text(a, "FERRIS WHEEL", Vector3(0, 0, 0.05), 0.048, berry, 0.04)
				for k in 2:
					a.box(Vector3(-1.2 + 2.4 * float(k), -0.4, -0.02), Vector3(0.06, 0.18, 0.06), col("dark"))
				a.xf = sb
		a.box(Vector3(hub.x, hub.y, zb), Vector3(0.7, 0.6, 0.3), berry, 0.05)
	a.prism(hub, 0.16, absf(feet[0].y - hub.z) * 2.0 + 0.4, col("dark"), 8, Basis(Vector3.RIGHT, PI * 0.5))
	# the platform: a cream deck with a berry skirt, a yellow edge and a front step
	var pr := Rect2()
	for s in CityMap.GROUND_SOLIDS:
		if String(s["kind"]) == "wheel_platform":
			pr = s["rect"]
	var deck_top: float = float(CityMap.FERRIS["board_y"]) - 0.1
	a.span(Vector3(pr.position.x, 0.0, pr.position.y), Vector3(pr.end.x, deck_top - 0.04, pr.end.y - 0.3), berry)
	a.span(Vector3(pr.position.x - 0.02, deck_top - 0.04, pr.position.y - 0.02), Vector3(pr.end.x + 0.02, deck_top, pr.end.y - 0.28), cream)
	a.span(Vector3(pr.position.x + 0.1, deck_top, pr.end.y - 0.42), Vector3(pr.end.x - 0.1, deck_top + 0.005, pr.end.y - 0.32), col("yellow"))
	a.span(Vector3(pr.position.x + 0.2, 0.0, pr.end.y - 0.3), Vector3(pr.end.x - 0.2, deck_top * 0.5, pr.end.y), cream)


# ===================================================================== people and vehicles

const SHIRTS: Array[String] = ["blue", "coral", "yellow", "green", "berry", "white"]
const TROUSERS: Array[Array] = [["dark", 0.0], ["blue", -0.3], ["wood", -0.3], ["dark", 0.2], ["blue", -0.5], ["cream", -0.15]]
const SKINS: Array[Array] = [["wood", 0.4], ["wood", 0.0], ["wood", -0.3], ["cream", -0.15]]
const HAIRS: Array[Array] = [["dark", 0.0], ["wood", -0.5], ["yellow", -0.15], ["wood", -0.3], ["dark", 0.2]]


static func _spec(list: Array[Array], i: int) -> Color:
	var s: Array = list[posmod(i, list.size())]
	return col(String(s[0]), float(s[1]))


## Upper body of a townsperson (pelvis at `hip`), arms at the sides or forward (seated at a table).
static func _upper(a: Acc, v: int, hip: float, arms_forward: bool) -> void:
	var shirt := col(SHIRTS[posmod(v, SHIRTS.size())])
	var trousers := _spec(TROUSERS, v)
	var skin := _spec(SKINS, v * 3 + 1)
	var hair := _spec(HAIRS, v * 2)
	a.box(Vector3(0, hip + 0.03, 0), Vector3(0.36, 0.14, 0.21), trousers, 0.02)
	a.box(Vector3(0, hip + 0.33, 0), Vector3(0.4, 0.48, 0.23), shirt, 0.04)
	a.box(Vector3(0, hip + 0.55, 0.0), Vector3(0.26, 0.06, 0.2), col("white"), 0.02)
	a.box(Vector3(0, hip + 0.6, 0), Vector3(0.1, 0.06, 0.1), skin)
	for sx: float in [-1.0, 1.0]:
		if arms_forward:
			a.box(Vector3(sx * 0.25, hip + 0.44, 0.0), Vector3(0.11, 0.22, 0.13), shirt, 0.02)
			a.box(Vector3(sx * 0.22, hip + 0.3, 0.16), Vector3(0.1, 0.1, 0.34), shirt, 0.02)
			a.box(Vector3(sx * 0.2, hip + 0.3, 0.37), Vector3(0.09, 0.09, 0.09), skin, 0.02)
		else:
			a.box(Vector3(sx * 0.265, hip + 0.31, 0), Vector3(0.11, 0.46, 0.13), shirt, 0.02)
			a.box(Vector3(sx * 0.265, hip + 0.04, 0), Vector3(0.09, 0.1, 0.1), skin, 0.02)
	var hy := hip + 0.78
	a.box(Vector3(0, hy, 0), Vector3(0.3, 0.32, 0.28), skin, 0.04)
	a.box(Vector3(0, hy + 0.17, -0.01), Vector3(0.32, 0.08, 0.3), hair, 0.02)
	a.box(Vector3(0, hy + 0.04, -0.13), Vector3(0.32, 0.26, 0.06), hair, 0.02)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.07, hy + 0.02, 0.141), Vector3(0.04, 0.05, 0.01), col("dark"))
		a.box(Vector3(sx * 0.1, hy - 0.06, 0.141), Vector3(0.05, 0.03, 0.01), col("peach", 0.4))
	a.box(Vector3(0, hy - 0.08, 0.141), Vector3(0.08, 0.02, 0.01), col("berry"))
	match posmod(v, 6):
		1: a.box(Vector3(0, hy + 0.24, 0), Vector3(0.36, 0.06, 0.34), col("yellow"), 0.02)
		2: a.box(Vector3(0.2, hip + 0.18, -0.16), Vector3(0.3, 0.28, 0.1), col("wood"), 0.03)
		4: a.box(Vector3(0, hip + 0.28, -0.15), Vector3(0.3, 0.34, 0.12), col("peach"), 0.04)


## A walking townsperson: a Node3D with "Body", "LegL" and "LegR" (legs pivot at the hip, swing about x).
static func walker(v: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Walker"
	var hip := 0.78
	var body := Acc.new()
	_upper(body, v, hip, false)
	var bnode := Node3D.new()
	bnode.name = "BodyPivot"
	root.add_child(bnode)
	body.commit(bnode, "Body", material())
	for sx: float in [-1.0, 1.0]:
		var leg := Acc.new()
		leg.box(Vector3(0, -0.37, 0), Vector3(0.14, 0.74, 0.16), _spec(TROUSERS, v), 0.02)
		leg.box(Vector3(0, -0.74, 0.03), Vector3(0.15, 0.08, 0.24), col("dark"), 0.02)
		var pivot := Node3D.new()
		pivot.name = "LegL" if sx < 0.0 else "LegR"
		pivot.position = Vector3(sx * 0.095, hip, 0)
		root.add_child(pivot)
		leg.commit(pivot, "Mesh", material())
	return root


## A seated townsperson (local: on a chair at the origin, facing +z, hands on the table).
static func seated_person(a: Acc, v: int) -> void:
	var hip := 0.5
	var trousers := _spec(TROUSERS, v)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.095, hip, 0.12), Vector3(0.15, 0.15, 0.4), trousers, 0.02)
		a.box(Vector3(sx * 0.095, hip * 0.5, 0.3), Vector3(0.14, hip, 0.15), trousers, 0.02)
		a.box(Vector3(sx * 0.095, 0.04, 0.33), Vector3(0.15, 0.08, 0.24), col("dark"), 0.02)
	_upper(a, v, hip, true)


## The city bus (7 x 2.4 x 2.9, forward +z, doors on its right, -x): one mesh.
static func bus(paint := Color(0, 0, 0, 0)) -> Node3D:
	var a := Acc.new()
	var blue := paint if paint.a > 0.0 else col("blue")
	var white := col("white")
	var glass := col("glass")
	var dark := col("dark")
	a.box(Vector3(0, 0.45, 0), Vector3(2.3, 0.42, 6.9), dark, 0.04)
	a.box(Vector3(0, 1.05, 0), Vector3(2.4, 0.9, 7.0), blue, 0.08)
	a.box(Vector3(0, 1.95, 0), Vector3(2.34, 0.9, 6.94), glass, 0.04)
	a.box(Vector3(0, 2.55, 0), Vector3(2.4, 0.3, 7.0), white, 0.1)
	a.box(Vector3(0, 2.76, -0.8), Vector3(1.4, 0.18, 1.8), col("white", -0.15), 0.05)
	a.box(Vector3(0, 1.52, 0), Vector3(2.42, 0.08, 7.02), white)
	for i in 6:
		var z := -2.9 + float(i) * 1.16
		for sx: float in [-1.0, 1.0]:
			a.box(Vector3(sx * 1.18, 1.95, z), Vector3(0.06, 0.9, 0.14), blue)
	# front: windscreen frame, destination sign, lights, bumper; back: lights
	a.box(Vector3(0, 2.3, 3.49), Vector3(1.9, 0.22, 0.04), dark)
	a.box(Vector3(0, 2.3, 3.51), Vector3(1.2, 0.12, 0.02), col("yellow"))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.85, 0.85, 3.5), Vector3(0.3, 0.16, 0.04), col("cream"), 0.02)
		a.box(Vector3(sx * 0.9, 0.85, -3.5), Vector3(0.22, 0.2, 0.04), col("berry"), 0.02)
	a.box(Vector3(0, 0.5, 3.52), Vector3(2.3, 0.2, 0.08), dark, 0.03)
	a.box(Vector3(0, 0.5, -3.52), Vector3(2.3, 0.2, 0.08), dark, 0.03)
	# doors on the right (-x)
	for z: float in [2.4, -0.3]:
		a.box(Vector3(-1.21, 1.35, z), Vector3(0.04, 1.9, 1.0), dark, 0.01)
		a.box(Vector3(-1.225, 1.45, z), Vector3(0.02, 1.6, 0.84), glass)
		a.box(Vector3(-1.235, 1.45, z), Vector3(0.02, 1.6, 0.04), dark)
	var wheels := [Vector2(1.08, 2.3), Vector2(-1.08, 2.3), Vector2(1.08, -2.3), Vector2(-1.08, -2.3)]
	for wpos: Vector2 in wheels:
		a.prism(Vector3(wpos.x, 0.45, wpos.y), 0.45, 0.3, dark, 10, Basis(Vector3.BACK, PI * 0.5))
		a.prism(Vector3(wpos.x + signf(wpos.x) * 0.1, 0.45, wpos.y), 0.2, 0.12, white, 8, Basis(Vector3.BACK, PI * 0.5))
	var root := Node3D.new()
	root.name = "Bus"
	a.commit(root, "Body", material())
	return root


## A small car (3.6 x 1.8 x 1.4, forward +z) in one of the palette's colours: one mesh.
static func car(v: int, color := Color(0, 0, 0, 0)) -> Node3D:
	var a := Acc.new()
	var paints: Array[String] = ["roof", "yellow", "green", "blue"]
	var paint := color if color.a > 0.0 else col(paints[posmod(v, paints.size())])
	var dark := col("dark")
	a.box(Vector3(0, 0.56, 0), Vector3(1.8, 0.52, 3.6), paint, 0.12)
	a.box(Vector3(0, 1.04, -0.15), Vector3(1.6, 0.48, 2.0), col("glass"), 0.08)
	a.box(Vector3(0, 1.31, -0.15), Vector3(1.64, 0.08, 1.9), paint, 0.03)
	for z: float in [-0.15]:
		for sx: float in [-1.0, 1.0]:
			a.box(Vector3(sx * 0.805, 1.04, z), Vector3(0.04, 0.48, 0.08), paint)
	a.box(Vector3(0, 0.84, 0), Vector3(1.82, 0.04, 3.62), col("white"))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.6, 0.66, 1.79), Vector3(0.3, 0.14, 0.04), col("cream"), 0.02)
		a.box(Vector3(sx * 0.65, 0.66, -1.79), Vector3(0.24, 0.12, 0.04), col("berry"), 0.02)
	a.box(Vector3(0, 0.36, 1.82), Vector3(1.7, 0.14, 0.08), col("white", -0.15), 0.03)
	a.box(Vector3(0, 0.36, -1.82), Vector3(1.7, 0.14, 0.08), col("white", -0.15), 0.03)
	a.box(Vector3(0, 0.56, 1.81), Vector3(0.6, 0.12, 0.02), dark)
	for wpos: Vector2 in [Vector2(0.82, 1.15), Vector2(-0.82, 1.15), Vector2(0.82, -1.15), Vector2(-0.82, -1.15)]:
		a.prism(Vector3(wpos.x, 0.3, wpos.y), 0.3, 0.24, dark, 10, Basis(Vector3.BACK, PI * 0.5))
		a.prism(Vector3(wpos.x + signf(wpos.x) * 0.08, 0.3, wpos.y), 0.13, 0.1, col("white"), 8, Basis(Vector3.BACK, PI * 0.5))
	var root := Node3D.new()
	root.name = "Car"
	a.commit(root, "Body", material())
	return root


# ===================================================================== lettering

## A 5 x 5 voxel alphabet (the letters the city's signs use).
const FONT := {
	"A": [".###.", "#...#", "#####", "#...#", "#...#"], "B": ["####.", "#...#", "####.", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", ".####"], "E": ["#####", "#....", "####.", "#....", "#####"],
	"F": ["#####", "#....", "####.", "#....", "#...."], "H": ["#...#", "#...#", "#####", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "#####"], "K": ["#...#", "#..#.", "###..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#####"], "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", ".###."], "R": ["####.", "#...#", "####.", "#..#.", "#...#"],
	"S": [".####", "#....", ".###.", "....#", "####."], "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."], "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#"],
	"P": ["####.", "#...#", "####.", "#....", "#...."], "T": ["#####", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", ".###."], "D": ["####.", "#...#", "#...#", "#...#", "####."],
	"G": [".####", "#....", "#..##", "#...#", ".###."],
}


## Pixel columns a text needs (5 per letter, 1 between letters, 3 for a space).
static func text_cols(t: String) -> int:
	var n := 0
	for i in t.length():
		n += 3 if t[i] == " " else 5
		if i < t.length() - 1:
			n += 1
	return n


## Voxel letters standing in the local x-y plane, centred at `c`, facing +z, `px` per pixel.
static func text(a: Acc, t: String, c: Vector3, px: float, color: Color, depth := 0.05) -> void:
	var x := -float(text_cols(t)) * 0.5 * px
	for i in t.length():
		var ch := t[i]
		if ch == " " or not FONT.has(ch):
			x += 4.0 * px
			continue
		var rows: Array = FONT[ch]
		for j in 5:
			var row := String(rows[j])
			var k := 0
			while k < 5:
				if row[k] != "#":
					k += 1
					continue
				var e := k
				while e + 1 < 5 and row[e + 1] == "#":
					e += 1
				var x0 := x + float(k) * px
				var x1 := x + float(e + 1) * px
				a.box(c + Vector3((x0 + x1) * 0.5, (2.0 - float(j)) * px, depth * 0.5), Vector3(x1 - x0, px, depth), color)
				k = e + 1
		x += 6.0 * px


# ===================================================================== shops

## A shop front's display windows: [{rect: the GROUND_WALLS window wall, u0, u1: the glass along x}],
## each leaving a 0.12 m pier at its ends and clear of the building's side walls.
static func shop_windows(shop: String) -> Array[Dictionary]:
	var b: Dictionary = CityMap.BUILDINGS[shop]
	var r: Rect2 = b["rect"]
	var out: Array[Dictionary] = []
	for w: Rect2 in CityMap.GROUND_WALLS:
		if w.size.x < w.size.y or w.position.y < r.end.y - 0.5 or not w.intersects(r):
			continue
		var wr := w.intersection(r)
		var u0 := wr.position.x + 0.12
		var u1 := wr.end.x - 0.12
		for side: Rect2 in CityMap.GROUND_WALLS:
			if side.size.x >= side.size.y or not side.intersects(wr):
				continue
			if side.end.x > wr.position.x and side.position.x <= wr.position.x + 0.01:
				u0 = maxf(u0, side.end.x + 0.12)
			if side.position.x < wr.end.x and side.end.x >= wr.end.x - 0.01:
				u1 = minf(u1, side.position.x - 0.12)
		out.append({"rect": wr, "u0": u0, "u1": u1})
	return out


## The display window opening (u0, u1, v0, v1) in a front wall.
const DISPLAY_V := Vector2(0.55, 2.3)


## A windowed shop front (world coordinates): the English sign with voxel letters, a striped awning,
## the door's lintel, transom, frame, threshold and mat, goods in the display windows, pendant lamps and
## wall shelves behind the counter. The window walls themselves come from GROUND_WALLS (the world).
static func shop_front(a: Acc, d: Acc, shop: String, r: Rect2, roof: float) -> void:
	var b: Dictionary = CityMap.BUILDINGS[shop]
	var bc := body_key(shop)
	var acc_c := accent(shop)
	var top := roof - CityMap.SLAB
	var fz := r.end.y
	var door: Vector2 = CityMap.SHOP_DOORS.get(shop, Vector2(r.get_center().x - 0.8, r.get_center().x + 0.8))
	var white := col("white")
	# above the door: a lintel wall with a transom light and the shop's icon, then the door frame
	a.span(Vector3(door.x, DOOR_H + 0.42, fz - 0.3), Vector3(door.y, top, fz), col(bc))
	a.lit().span(Vector3(door.x, DOOR_H + 0.12, fz - 0.17), Vector3(door.y, DOOR_H + 0.42, fz - 0.13), col("glass"))
	a.span(Vector3((door.x + door.y) * 0.5 - 0.03, DOOR_H + 0.12, fz - 0.2), Vector3((door.x + door.y) * 0.5 + 0.03, DOOR_H + 0.42, fz - 0.1), white)
	for face: float in [fz - 0.34, fz]:
		a.span(Vector3(door.x - 0.12, 0.0, face), Vector3(door.x, DOOR_H + 0.12, face + 0.04), white)
		a.span(Vector3(door.y, 0.0, face), Vector3(door.y + 0.12, DOOR_H + 0.12, face + 0.04), white)
		a.span(Vector3(door.x - 0.12, DOOR_H, face), Vector3(door.y + 0.12, DOOR_H + 0.12, face + 0.04), white)
	a.span(Vector3(door.x, 0.0, fz - 0.3), Vector3(door.y, 0.03, fz + 0.02), col("kerb"))
	d.span(Vector3(door.x + 0.15, 0.0, fz + 0.06), Vector3(door.y - 0.15, 0.027, fz + 0.56), shade(acc_c, -0.15))
	# the sign board across the front with its name in voxel letters
	var board := acc_c
	var letters := col("dark")
	var sw := r.size.x - 0.7
	var sb := a.xf
	a.xf = sb * Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, 2.89, fz))
	a.box(Vector3(0, 0, 0.04), Vector3(sw, 0.56, 0.08), col("white"), 0.02)
	a.lit().box(Vector3(0, 0, 0.07), Vector3(sw - 0.1, 0.46, 0.04), board)
	var t := String(b.get("sign", String(b.get("name", ""))).to_upper())
	var px := minf(0.075, (sw - 0.4) / float(text_cols(t)))
	text(a, t, Vector3(0, 0, 0.09), px, letters, 0.05)
	a.xf = sb
	# the awning: striped, sloping out over the pavement and the outdoor tables
	var x0 := r.position.x + 0.3
	var x1 := r.end.x - 0.3
	var depth := 1.0
	var slope := atan2(0.35, depth)
	var stripes := int((x1 - x0) / 0.5)
	var stw := (x1 - x0) / float(stripes)
	for i in stripes:
		var cx := x0 + (float(i) + 0.5) * stw
		var cc := acc_c if i % 2 == 0 else white
		a.box(Vector3(cx, 2.5 - 0.175, fz + depth * 0.5), Vector3(stw, 0.05, sqrt(depth * depth + 0.1225)), cc, 0.0, Basis(Vector3.RIGHT, slope))
		a.box(Vector3(cx, 2.05, fz + depth + 0.02), Vector3(stw, 0.16, 0.04), cc)
		if i % 2 == 0:
			a.box(Vector3(cx, 1.95, fz + depth + 0.02), Vector3(stw * 0.6, 0.05, 0.04), cc)
	for x: float in [x0 + 0.1, x1 - 0.1]:
		a.beam(Vector3(x, 2.55, fz + 0.02), Vector3(x, 2.15, fz + depth - 0.02), 0.04, 0.04, col("dark"))
	# goods in the display windows: a low riser and a glass shelf in each niche
	for wn in shop_windows(shop):
		var wr: Rect2 = wn["rect"]
		var u0: float = wn["u0"]
		var u1: float = wn["u1"]
		var zi := wr.position.y + 0.02
		var zg := wr.end.y - 0.09
		var zc := (zi + zg) * 0.5
		d.span(Vector3(u0 + 0.08, DISPLAY_V.x, zi), Vector3(u1 - 0.08, DISPLAY_V.x + 0.1, zi + 0.09), shade(acc_c, 0.4))
		d.span(Vector3(u0 + 0.08, 1.4, zi), Vector3(u1 - 0.08, 1.43, zg), col("glass", 0.4))
		var n := int((u1 - u0 - 0.2) / 0.3)
		for i in n:
			var x := u0 + 0.2 + float(i) * (u1 - u0 - 0.4) / float(maxi(n - 1, 1))
			_good(d, shop, Vector3(x, DISPLAY_V.x + (0.1 if i % 2 == 0 else 0.0), zc), i, false)
			_good(d, shop, Vector3(x, 1.43, zc), i + 2, false)
	# pendant lamps and, behind the counter, shelves on the back wall (the bookstore has its shelves)
	for lx: float in [r.get_center().x - 1.4, r.get_center().x + 1.4]:
		d.span(Vector3(lx - 0.01, 2.5, 11.4 - 0.01 + (r.position.y - 8.0)), Vector3(lx + 0.01, top, 11.4 + 0.01 + (r.position.y - 8.0)), col("dark"))
		d.lit().box(Vector3(lx, 2.42, 11.4 + (r.position.y - 8.0)), Vector3(0.36, 0.18, 0.36), acc_c, 0.04)
	if shop != "bookstore":
		var by := r.position.y + 0.3
		var cx := r.get_center().x
		for sy: float in [1.6, 2.2]:
			a.span(Vector3(cx - 2.0, sy, by), Vector3(cx + 2.0, sy + 0.05, by + 0.22), col("wood"))
			for sx: float in [-1.9, 1.9]:
				a.span(Vector3(cx + sx - 0.03, sy - 0.12, by), Vector3(cx + sx + 0.03, sy, by + 0.18), col("dark"))
		for k in 2:
			_goods_row(d, shop, Vector3(cx - 1.8, 1.65 + float(k) * 0.6, by + 0.11), 3.6, k)


## A row of goods along x on a shelf (start point, length) for each kind of shop.
static func _goods_row(d: Acc, shop: String, p: Vector3, length: float, k: int) -> void:
	var n := int(length / 0.3)
	for i in n:
		_good(d, shop, p + Vector3(float(i) * length / float(n) + 0.15, 0, 0), i + k * 3, false)


static func _good(d: Acc, shop: String, p: Vector3, i: int, along_z: bool) -> void:
	var tones: Array[String] = ["coral", "blue", "yellow", "green", "berry"]
	match shop:
		"bakery":
			if i % 3 == 0:
				d.box(p + Vector3(0, 0.06, 0), Vector3(0.22, 0.12, 0.18), col("wood", -0.3), 0.02)
				d.box(p + Vector3(0, 0.14, 0), Vector3(0.14, 0.06, 0.12), col("wood", 0.2))
			elif i % 3 == 1:
				d.box(p + Vector3(0, 0.06, 0), Vector3(0.24 if not along_z else 0.12, 0.1, 0.12 if not along_z else 0.24), col("wood"), 0.04)
			else:
				d.box(p + Vector3(0, 0.05, 0), Vector3(0.16, 0.08, 0.14), col("yellow", -0.15))
		"corner_cafe":
			if i % 3 == 0:
				d.box(p + Vector3(0, 0.06, 0), Vector3(0.1, 0.1, 0.1), col("white"))
				d.box(p + Vector3(0.12, 0.06, 0), Vector3(0.1, 0.1, 0.1), col(tones[i % 5], 0.2))
			elif i % 3 == 1:
				d.box(p + Vector3(0, 0.05, 0), Vector3(0.22, 0.08, 0.16), col("peach", 0.4))
				d.box(p + Vector3(0, 0.1, 0), Vector3(0.22, 0.03, 0.16), col("cream"))
			else:
				d.box(p + Vector3(0, 0.09, 0), Vector3(0.12, 0.18, 0.12), col("glass"))
				d.box(p + Vector3(0, 0.07, 0), Vector3(0.08, 0.1, 0.08), col("wood", -0.5))
		"flowers":
			d.box(p + Vector3(0, 0.08, 0), Vector3(0.16, 0.16, 0.16), col("peach", -0.15))
			d.box(p + Vector3(0, 0.22, 0), Vector3(0.2, 0.14, 0.18), col("green"), 0.04)
			d.box(p + Vector3(0.03, 0.31, 0.0), Vector3(0.1, 0.08, 0.1), col(tones[i % 5], 0.2))
		"bookstore":
			for bk in 4:
				var off := (float(bk) - 1.5) * 0.065
				var hh := 0.22 + 0.04 * float((i + bk) % 3)
				var o := Vector3(0, hh * 0.5, off) if along_z else Vector3(off, hh * 0.5, 0)
				d.box(p + o, Vector3(0.18, hh, 0.055) if along_z else Vector3(0.055, hh, 0.18), col(tones[(i + bk) % 5], -0.15 if bk % 2 == 0 else 0.0))
		"icecream":
			if i % 2 == 0:
				d.box(p + Vector3(0, 0.08, 0), Vector3(0.18, 0.16, 0.16), col("white"))
				d.box(p + Vector3(0, 0.17, 0), Vector3(0.16, 0.03, 0.14), col(tones[i % 5], 0.4))
			else:
				d.box(p + Vector3(0, 0.08, 0), Vector3(0.06, 0.16, 0.06), col("wood"))
				d.box(p + Vector3(0, 0.2, 0), Vector3(0.11, 0.1, 0.11), col(tones[(i + 1) % 5], 0.4), 0.0)


# ===================================================================== new furniture (refinement)

## A pendant lamp over a table, hung from a ceiling `ceiling` above the local floor.
static func _pendant(d: Acc, ceiling: float) -> void:
	d.span(Vector3(-0.01, 2.3, -0.01), Vector3(0.01, ceiling, 0.01), col("dark"))
	d.lit().box(Vector3(0, 2.22, 0), Vector3(0.34, 0.16, 0.34), col("yellow"), 0.04)
	d.box(Vector3(0, 2.13, 0), Vector3(0.2, 0.03, 0.2), col("cream"))


## Two chairs facing a small table from its left and right (local x).
static func _chairs_around(a: Acc, w: float, style: String, tint := Color(0, 0, 0, 0)) -> void:
	for sx: float in [-1.0, 1.0]:
		var sv := a.xf
		a.xf = sv * Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(sx * (w * 0.5 + 0.32), 0, 0))
		chair(a, style, tint)
		a.xf = sv


## A bakery's bread display: a wooden cabinet with three stepped tiers of loaves, buns and baguettes.
static func _bread_display(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.4, 0), Vector3(w, 0.8, dd), col("wood", -0.15), 0.03)
	for i in int(w / 0.5):
		a.box(Vector3(-w * 0.5 + 0.25 + float(i) * 0.5, 0.42, dd * 0.5), Vector3(0.4, 0.6, 0.03), col("cream"))
	var tiers: Array[Vector3] = [Vector3(0.82, dd * 0.25, dd * 0.5), Vector3(1.02, -dd * 0.05, dd * 0.35), Vector3(1.22, -dd * 0.3, dd * 0.3)]
	for k in tiers.size():
		var tz := tiers[k]
		a.box(Vector3(0, tz.x - 0.02, tz.y), Vector3(w, 0.04 + tz.x - 0.82, tz.z), col("wood"))
		var n := int((w - 0.2) / 0.3)
		for i in n:
			var x := -w * 0.5 + 0.25 + float(i) * (w - 0.5) / float(maxi(n - 1, 1))
			var p := Vector3(x, tz.x, tz.y)
			match (i + k) % 4:
				0:
					d.box(p + Vector3(0, 0.07, 0), Vector3(0.24, 0.12, 0.14), col("wood"), 0.04)
				1:
					d.box(p + Vector3(0, 0.04, 0), Vector3(0.28, 0.06, 0.06), col("wood", 0.2))
					d.box(p + Vector3(0, 0.04, 0.07), Vector3(0.28, 0.06, 0.06), col("wood", 0.2))
				2:
					d.box(p + Vector3(-0.06, 0.05, 0), Vector3(0.1, 0.08, 0.1), col("yellow", -0.15))
					d.box(p + Vector3(0.06, 0.05, 0), Vector3(0.1, 0.08, 0.1), col("yellow", -0.15))
				_:
					d.box(p + Vector3(0, 0.05, 0), Vector3(0.2, 0.08, 0.16), col("wood", -0.3))
					d.box(p + Vector3(0, 0.1, 0), Vector3(0.14, 0.03, 0.1), col("cream"))
	a.box(Vector3(0, 1.45, -dd * 0.5 + 0.03), Vector3(w, 0.4, 0.06), col("wood", -0.3), 0.02)


## A bookcase against a wall: frame, five shelves of books (varied heights and colours), a few gaps.
static func _bookshelf(a: Acc, d: Acc, w: float, dd: float, theme: String) -> void:
	var h := 2.2 if theme == "bookstore" else 2.0
	var frame_c := col("wood", -0.15) if theme != "office" else col("white", -0.15)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * (w * 0.5 - 0.03), h * 0.5, 0), Vector3(0.06, h, dd), frame_c)
	a.box(Vector3(0, h * 0.5, -dd * 0.5 + 0.02), Vector3(w, h, 0.04), col("cream") if theme != "office" else col("blue", 0.6))
	a.box(Vector3(0, h - 0.03, 0), Vector3(w, 0.06, dd), frame_c)
	var tones: Array[String] = ["blue", "coral", "green", "yellow", "berry", "white", "dark"]
	for k in 5:
		var yy := 0.06 + float(k) * (h - 0.1) / 5.0
		a.box(Vector3(0, yy, 0), Vector3(w - 0.08, 0.04, dd - 0.02), frame_c)
		var x := -w * 0.5 + 0.08
		var i := k * 7
		while x < w * 0.5 - 0.15:
			if i % 9 == 4:
				x += 0.22
				i += 1
				continue
			var bw := 0.07 + 0.02 * float(i % 2)
			var bh := 0.24 + 0.04 * float(i % 3)
			d.box(Vector3(x + bw * 0.5, yy + 0.02 + bh * 0.5, 0.02), Vector3(bw - 0.01, bh, dd * 0.75), col(tones[i % tones.size()], -0.15 if i % 3 == 0 else 0.0))
			x += bw
			i += 1


## A florist's three-tier stand with buckets and bouquets.
static func _flower_stand(a: Acc, d: Acc, w: float, dd: float) -> void:
	var tiers := 3
	for k in tiers:
		var zc := dd * 0.5 - (float(k) + 0.5) * dd / float(tiers)
		var hh := 0.35 + 0.3 * float(k)
		a.box(Vector3(0, hh * 0.5, zc), Vector3(w, hh, dd / float(tiers)), col("white") if k % 2 == 0 else col("green", 0.6), 0.02)
		var n := int(w / 0.34)
		for i in n:
			var x := -w * 0.5 + 0.2 + float(i) * (w - 0.4) / float(maxi(n - 1, 1))
			var fc: Array[String] = ["coral", "yellow", "berry", "white", "blue"]
			d.box(Vector3(x, hh + 0.1, zc), Vector3(0.18, 0.2, 0.18), col("dark", 0.2) if i % 2 == 0 else col("peach", -0.15))
			d.box(Vector3(x, hh + 0.24, zc), Vector3(0.04, 0.1, 0.04), col("green_deep"))
			d.box(Vector3(x, hh + 0.33, zc), Vector3(0.22, 0.12, 0.2), col("green"), 0.04)
			d.box(Vector3(x - 0.04, hh + 0.42, zc + 0.03), Vector3(0.1, 0.08, 0.1), col(fc[(i + k) % 5], 0.2 if fc[(i + k) % 5] != "white" else 0.0))
			d.box(Vector3(x + 0.06, hh + 0.4, zc - 0.04), Vector3(0.08, 0.08, 0.08), col(fc[(i + k + 2) % 5], 0.4 if fc[(i + k + 2) % 5] == "berry" else 0.0))


## An ice cream freezer: a white chest with a coloured band, open tubs of every flavour under a
## sloped glass sneeze guard at the front, and a cone stand.
static func _freezer(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.42, 0), Vector3(w, 0.84, dd), col("white"), 0.04)
	a.box(Vector3(0, 0.62, dd * 0.5), Vector3(w - 0.1, 0.14, 0.02), col("peach", 0.4))
	a.box(Vector3(0, 0.08, dd * 0.5 - 0.02), Vector3(w - 0.1, 0.12, 0.04), col("dark", 0.2))
	var flavours: Array = [["coral", 0.4], ["green", 0.4], ["wood", -0.3], ["yellow", 0.4], ["cream", 0.0], ["berry", 0.4], ["blue", 0.4], ["white", 0.0]]
	var n := int((w - 0.2) / 0.3)
	for i in n:
		var spec: Array = flavours[i % flavours.size()]
		var x := -w * 0.5 + 0.22 + float(i) * (w - 0.44) / float(maxi(n - 1, 1))
		for zz: float in [-0.15, 0.15]:
			d.box(Vector3(x, 0.85, zz), Vector3(0.24, 0.03, 0.24), col("white", -0.15))
			d.box(Vector3(x, 0.88, zz), Vector3(0.2, 0.04, 0.2), col(String(spec[0]), float(spec[1])))
	a.beam(Vector3(-w * 0.5 + 0.05, 0.86, dd * 0.5 - 0.05), Vector3(-w * 0.5 + 0.05, 1.12, dd * 0.5 - 0.3), 0.04, 0.04, col("white", -0.15))
	a.beam(Vector3(w * 0.5 - 0.05, 0.86, dd * 0.5 - 0.05), Vector3(w * 0.5 - 0.05, 1.12, dd * 0.5 - 0.3), 0.04, 0.04, col("white", -0.15))
	a.box(Vector3(0, 0.99, dd * 0.5 - 0.17), Vector3(w - 0.08, 0.03, 0.36), col("glass", 0.4), 0.0, Basis(Vector3.RIGHT, -0.8))
	for i in 3:
		d.box(Vector3(w * 0.5 - 0.2 - float(i) * 0.1, 0.94, -dd * 0.5 + 0.12), Vector3(0.06, 0.16, 0.06), col("wood"))
		d.box(Vector3(w * 0.5 - 0.2 - float(i) * 0.1, 1.05, -dd * 0.5 + 0.12), Vector3(0.1, 0.08, 0.1), col("peach", 0.4) if i != 1 else col("yellow", 0.4))


## A small round bistro table with two chairs (outdoors on the pavement, or on a terrace).
static func _bistro_table(a: Acc, d: Acc, w: float, _dd: float, theme: String) -> void:
	var seat := accent(theme) if CityMap.SHOP_ACCENTS.has(theme) else col("peach")
	_chairs_around(a, w, "bistro", seat)
	a.prism(Vector3(0, 0.03, 0), 0.22, 0.06, col("dark"), 8)
	a.box(Vector3(0, 0.37, 0), Vector3(0.06, 0.66, 0.06), col("dark"))
	a.prism(Vector3(0, 0.72, 0), w * 0.5, 0.05, col("white"), 10)
	d.box(Vector3(0.12, 0.79, 0.06), Vector3(0.1, 0.1, 0.1), col("white"))
	d.box(Vector3(-0.1, 0.78, -0.08), Vector3(0.18, 0.02, 0.18), col("white", -0.15))
	d.box(Vector3(-0.1, 0.81, -0.08), Vector3(0.12, 0.05, 0.1), col("peach", 0.4) if theme != "bookstore" else col("blue"))
	d.box(Vector3(0.0, 0.84, 0.16), Vector3(0.06, 0.14, 0.06), col("glass"))
	d.box(Vector3(0.0, 0.94, 0.16), Vector3(0.08, 0.06, 0.08), col("yellow"))


## The yellow cafe's coffee bar against its wall: espresso machine, grinder, cups, a pastry case with
## cakes, a menu board above and three stools in front.
static func _coffee_bar(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.06, 0.02), Vector3(w - 0.1, 0.12, dd - 0.1), col("dark"))
	a.box(Vector3(0, 0.55, 0), Vector3(w, 0.86, dd), col("yellow", -0.15), 0.03)
	for i in int(w / 0.4):
		a.box(Vector3(-w * 0.5 + 0.2 + float(i) * 0.4, 0.55, dd * 0.5 + 0.01), Vector3(0.3, 0.7, 0.02), col("wood", 0.2))
	a.box(Vector3(0, 1.01, 0.03), Vector3(w + 0.06, 0.06, dd + 0.08), col("wood"), 0.02)
	# espresso machine with two group heads, a grinder, stacked cups
	var mx := -w * 0.5 + 0.55
	a.box(Vector3(mx, 1.3, -0.12), Vector3(0.7, 0.52, 0.42), col("white", -0.15), 0.04)
	a.box(Vector3(mx, 1.58, -0.12), Vector3(0.74, 0.05, 0.46), col("dark"))
	for gx: float in [-0.16, 0.16]:
		d.box(Vector3(mx + gx, 1.16, 0.1), Vector3(0.1, 0.08, 0.1), col("dark"))
		d.box(Vector3(mx + gx, 1.07, 0.12), Vector3(0.07, 0.07, 0.07), col("white"))
	a.box(Vector3(mx + 0.55, 1.24, -0.15), Vector3(0.2, 0.4, 0.2), col("dark", 0.2), 0.03)
	d.box(Vector3(mx + 0.55, 1.52, -0.15), Vector3(0.16, 0.16, 0.16), col("glass"))
	for i in 3:
		for k in 2:
			d.box(Vector3(mx + 0.85 + float(i) * 0.12, 1.08 + float(k) * 0.08, -0.2), Vector3(0.1, 0.07, 0.1), col("white"))
	# the pastry case: an open frame with a glass top, cakes on two shelves
	var cx := w * 0.5 - 0.6
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(cx + sx * 0.46, 1.27, sz * 0.24), Vector3(0.04, 0.46, 0.04), col("white"))
	a.box(Vector3(cx, 1.51, 0), Vector3(0.98, 0.03, 0.54), col("glass", 0.4))
	a.box(Vector3(cx, 1.26, 0), Vector3(0.9, 0.02, 0.46), col("white"))
	for i in 3:
		d.box(Vector3(cx - 0.3 + float(i) * 0.3, 1.1, 0), Vector3(0.2, 0.1, 0.2), col("peach", 0.4) if i != 1 else col("wood", -0.3), 0.0)
		d.box(Vector3(cx - 0.3 + float(i) * 0.3, 1.16, 0), Vector3(0.2, 0.02, 0.2), col("cream"))
		d.box(Vector3(cx - 0.3 + float(i) * 0.3, 1.32, 0), Vector3(0.12, 0.1, 0.12), col("yellow", 0.4) if i != 1 else col("berry", 0.4))
	# a menu board on the wall above, and three stools in front
	sign_board(a, Vector3(0, 2.15, -dd * 0.5 - 0.02), Vector2(1.6, 0.7), col("dark"), col("wood"), "cup")
	for i: int in [0, 2]:
		var p := Vector3((float(i) - 1.0) * w * 0.3, 0, dd * 0.5 + 0.25)
		a.prism(p + Vector3(0, 0.03, 0), 0.18, 0.06, col("dark"), 6)
		a.box(p + Vector3(0, 0.36, 0), Vector3(0.05, 0.6, 0.05), col("dark"))
		a.box(p + Vector3(0, 0.5, 0), Vector3(0.24, 0.03, 0.03), col("dark"))
		a.prism(p + Vector3(0, 0.7, 0), 0.18, 0.07, col("yellow"), 8)


## One post of the rooftop pavilion (its frame and roof come from pergola()).
static func _pavilion_post(a: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.08, 0), Vector3(w + 0.1, 0.16, dd + 0.1), col("peach", -0.15), 0.02)
	a.box(Vector3(0, PAVILION_H * 0.5, 0), Vector3(w - 0.04, PAVILION_H, dd - 0.04), col("white"), 0.02)
	a.box(Vector3(0, PAVILION_H - 0.12, 0), Vector3(w + 0.08, 0.1, dd + 0.08), col("peach"), 0.02)


## Height of the pavilion's beams above its floor.
const PAVILION_H := 2.8


## The rooftop restaurant's pavilion over its posts' rect (world coordinates, floor y): perimeter beams,
## open slats so the interior shows from above, a striped canvas over the kitchen side, pendant lamps
## and strings of lights between the posts.
static func pergola(a: Acc, d: Acc, r: Rect2, y: float) -> void:
	var c := Rect2(r.position + Vector2(0.15, 0.15), r.size - Vector2(0.3, 0.3))   # post centres
	var top := y + PAVILION_H
	for z: float in [c.position.y, c.end.y]:
		a.span(Vector3(c.position.x - 0.25, top - 0.06, z - 0.1), Vector3(c.end.x + 0.25, top + 0.2, z + 0.1), col("peach"))
	for x: float in [c.position.x, c.end.x]:
		a.span(Vector3(x - 0.1, top - 0.06, c.position.y - 0.25), Vector3(x + 0.1, top + 0.2, c.end.y + 0.25), col("peach"))
	var n := int((c.size.x + 0.5) / 0.45)
	for i in n + 1:
		var x := c.position.x - 0.25 + float(i) * (c.size.x + 0.5) / float(n)
		a.span(Vector3(x - 0.04, top + 0.2, c.position.y - 0.35), Vector3(x + 0.04, top + 0.34, c.end.y + 0.35), col("white"))
	# the RESTAURANT sign standing on the front beam
	var sv := a.xf
	a.xf = sv * Transform3D(Basis.IDENTITY, Vector3(c.get_center().x, top + 0.68, c.end.y + 0.02))
	text_sign(a, Vector3.ZERO, Vector2(4.8, 0.62), col("white"), col("peach"), "RESTAURANT", col("roof", -0.15))
	for x: float in [-1.8, 1.8]:
		a.box(Vector3(x, -0.39, -0.02), Vector3(0.06, 0.22, 0.06), col("dark"))
	a.xf = sv
	# the canvas over the kitchen third
	var stripes := int(c.size.x / 0.6)
	for i in stripes:
		var x0 := c.position.x + float(i) * c.size.x / float(stripes)
		a.span(Vector3(x0, top + 0.34, c.position.y - 0.2), Vector3(x0 + c.size.x / float(stripes), top + 0.38, c.position.y + 1.3), col("peach") if i % 2 == 0 else col("cream"))
	# pendant lamps over the bar and lights strung along the open front
	for i in 3:
		var lx := c.position.x + 1.0 + float(i) * 1.3
		d.span(Vector3(lx - 0.01, top - 0.62, c.position.y + 0.85), Vector3(lx + 0.01, top - 0.06, c.position.y + 0.87), col("dark"))
		d.lit().box(Vector3(lx, top - 0.7, c.position.y + 0.86), Vector3(0.34, 0.16, 0.34), col("peach", 0.4), 0.04)
	var p0 := Vector3(c.position.x, top - 0.1, c.end.y + 0.12)
	var p1 := Vector3(c.end.x, top - 0.1, c.end.y + 0.12)
	var m := 16
	var prev := p0
	for k in range(1, m + 1):
		var t := float(k) / float(m)
		var q := p0.lerp(p1, t) - Vector3(0, sin(t * PI) * 0.4, 0)
		d.beam(prev, q, 0.02, 0.02, col("dark"))
		if k < m:
			d.lit().box(q - Vector3(0, 0.06, 0), Vector3(0.08, 0.1, 0.08), col("cream") if k % 2 == 0 else col("yellow", 0.4))
		prev = q
	# hanging planters on the two front posts
	for x: float in [c.position.x, c.end.x]:
		d.box(Vector3(x, top - 0.75, c.end.y + 0.25), Vector3(0.3, 0.24, 0.3), col("white"), 0.04)
		d.box(Vector3(x, top - 0.56, c.end.y + 0.25), Vector3(0.36, 0.16, 0.36), col("green"), 0.05)
		d.span(Vector3(x - 0.01, top - 0.63, c.end.y + 0.24), Vector3(x + 0.01, top - 0.06, c.end.y + 0.26), col("dark"))


## A striped shade canopy hung on a facade along x at z_wall, sloping out toward +z by `depth`.
static func facade_canopy(a: Acc, x0: float, x1: float, z_wall: float, y_top: float, depth: float, stripe: String) -> void:
	var drop := 0.5
	var slope := atan2(drop, depth)
	var stripes := int((x1 - x0) / 0.6)
	var sw := (x1 - x0) / float(stripes)
	for i in stripes:
		var cx := x0 + (float(i) + 0.5) * sw
		var cc := col(stripe) if i % 2 == 0 else col("white")
		a.box(Vector3(cx, y_top - drop * 0.5, z_wall + depth * 0.5), Vector3(sw, 0.05, sqrt(depth * depth + drop * drop)), cc, 0.0, Basis(Vector3.RIGHT, slope))
		a.box(Vector3(cx, y_top - drop - 0.08, z_wall + depth + 0.02), Vector3(sw, 0.16, 0.04), cc)
	var ties := int((x1 - x0) / 2.5) + 1
	for i in ties:
		var x := lerpf(x0 + 0.1, x1 - 0.1, float(i) / float(maxi(ties - 1, 1)))
		a.beam(Vector3(x, y_top + 0.35, z_wall + 0.02), Vector3(x, y_top - drop + 0.03, z_wall + depth - 0.02), 0.03, 0.03, col("dark"))


## Stepped voxel brackets under a cantilevered slab whose building face is z_face and which reaches out
## toward +z to z_far; `xs` are the brackets' x positions.
static func corbels(a: Acc, xs: Array[float], z_face: float, z_far: float, y: float, color: Color) -> void:
	var reach := z_far - z_face
	for x in xs:
		a.span(Vector3(x - 0.1, y - 0.36, z_face), Vector3(x + 0.1, y - CityMap.SLAB, z_face + reach * 0.9), color)
		a.span(Vector3(x - 0.1, y - 0.52, z_face), Vector3(x + 0.1, y - 0.36, z_face + reach * 0.6), color)
		a.span(Vector3(x - 0.1, y - 0.68, z_face), Vector3(x + 0.1, y - 0.52, z_face + reach * 0.3), color)


## A raised flower bed (local, front +z): a stone kerb, soil, leafy clumps and rows of bright flowers.
static func flower_bed(a: Acc, d: Acc, w: float, dd: float, seed_i: int) -> void:
	var h := 0.35
	for r in [Rect2(-w * 0.5, -dd * 0.5, w, 0.1), Rect2(-w * 0.5, dd * 0.5 - 0.1, w, 0.1), Rect2(-w * 0.5, -dd * 0.5 + 0.1, 0.1, dd - 0.2), Rect2(w * 0.5 - 0.1, -dd * 0.5 + 0.1, 0.1, dd - 0.2)]:
		var rr: Rect2 = r
		a.span(Vector3(rr.position.x, 0.0, rr.position.y), Vector3(rr.end.x, h, rr.end.y), col("kerb"))
	a.span(Vector3(-w * 0.5 + 0.1, 0.0, -dd * 0.5 + 0.1), Vector3(w * 0.5 - 0.1, h - 0.06, dd * 0.5 - 0.1), col("wood", -0.5))
	var fc: Array[String] = ["coral", "yellow", "berry", "white", "blue"]
	var cols := int((w - 0.2) / 0.26)
	for i in cols:
		var x := -w * 0.5 + 0.23 + float(i) * (w - 0.46) / float(maxi(cols - 1, 1))
		for row in 2:
			var z := (float(row) - 0.5) * (dd - 0.3) * 0.5
			var k := i + row * 2 + seed_i
			if (i + row) % 3 == 0:
				a.box(Vector3(x, h + 0.08, z), Vector3(0.22, 0.2, 0.22), col("green", -0.15 if k % 2 == 0 else 0.0), 0.05)
			else:
				d.box(Vector3(x, h + 0.06, z), Vector3(0.04, 0.16, 0.04), col("green_deep"))
				d.box(Vector3(x, h + 0.04, z), Vector3(0.16, 0.06, 0.12), col("green"))
				var fcn := fc[k % fc.size()]
				d.box(Vector3(x, h + 0.18, z), Vector3(0.12, 0.08, 0.12), col(fcn, 0.4 if fcn == "berry" or fcn == "blue" else 0.0))


# ===================================================================== r2: places for the city's people

## Extra furniture drawn as art only (not solid yet; the owner may add these rects to CityMap.FURNITURE):
## the machines, desks and tables that the people (city_people, A2) use, so none of them ever takes a
## child's place. Same fields as CityMap.FURNITURE.
## NPC-only furniture that children may walk over (the stretching mat). The solid NPC furniture moved to
## CityMap.FURNITURE (owner, city r2), so the navigation blocks it.
const EXTRA_FURNITURE := [
	{"region": "ground", "kind": "mat", "rect": Rect2(15.6, -7.6, 2.0, 1.0)},
]

## Where the city's people sit, stand, work and exercise (r2, for the people worker): never on or within
## 0.9 m of a child's place (CityMap.INTERACTIONS on the same region). pos is on the region's floor; ry
## is the facing (a node's rotation.y; 0 faces +z); pose: sit | stand | desk | run | cycle | row | lift |
## stretch. "chair": true where the art draws a chair just for this place (others reuse a drawn seat).
const NPC_PLACES := [
	# office: the desks without a child's place, the new desk pairs, the meeting table
	{"id": "office_l1_desk_c", "place": "office", "region": "office_l1", "pos": Vector2(-19.9, -5.6), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l1_desk_d", "place": "office", "region": "office_l1", "pos": Vector2(-16.9, -5.6), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l1_desk_e", "place": "office", "region": "office_l1", "pos": Vector2(-14.1, -5.6), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l1_desk_f", "place": "office", "region": "office_l1", "pos": Vector2(-14.1, -10.0), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l2_desk_a", "place": "office", "region": "office_l2", "pos": Vector2(-19.9, -5.0), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l2_desk_b", "place": "office", "region": "office_l2", "pos": Vector2(-16.9, -5.0), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l2_desk_c", "place": "office", "region": "office_l2", "pos": Vector2(-14.1, -5.0), "ry": PI, "pose": "desk", "chair": false},
	{"id": "office_l2_meeting_a", "place": "office", "region": "office_l2", "pos": Vector2(-19.4375, -10.25), "ry": 0.0, "pose": "sit", "chair": false},
	{"id": "office_l2_meeting_b", "place": "office", "region": "office_l2", "pos": Vector2(-17.5625, -8.35), "ry": PI, "pose": "sit", "chair": false},
	# the rooftop restaurant: the free sides of every table, the bar stools, the cook
	{"id": "restaurant_t1_n", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.8, -8.85), "ry": 0.0, "pose": "sit", "chair": true},
	{"id": "restaurant_t1_s", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.8, -6.95), "ry": PI, "pose": "sit", "chair": true},
	{"id": "restaurant_t2_n", "place": "restaurant", "region": "gym_roof", "pos": Vector2(13.8, -6.85), "ry": 0.0, "pose": "sit", "chair": true},
	{"id": "restaurant_t2_s", "place": "restaurant", "region": "gym_roof", "pos": Vector2(13.8, -4.95), "ry": PI, "pose": "sit", "chair": true},
	{"id": "restaurant_t3_w", "place": "restaurant", "region": "gym_roof", "pos": Vector2(7.75, -5.7), "ry": PI * 0.5, "pose": "sit", "chair": true},
	{"id": "restaurant_t3_e", "place": "restaurant", "region": "gym_roof", "pos": Vector2(9.65, -5.7), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "restaurant_t4_n", "place": "restaurant", "region": "gym_roof", "pos": Vector2(15.9, -9.45), "ry": 0.0, "pose": "sit", "chair": true},
	{"id": "restaurant_t4_s", "place": "restaurant", "region": "gym_roof", "pos": Vector2(15.9, -7.55), "ry": PI, "pose": "sit", "chair": true},
	{"id": "restaurant_t5_w", "place": "restaurant", "region": "gym_roof", "pos": Vector2(9.95, -4.7), "ry": PI * 0.5, "pose": "sit", "chair": true},
	{"id": "restaurant_t5_e", "place": "restaurant", "region": "gym_roof", "pos": Vector2(11.85, -4.7), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "restaurant_bar_w", "place": "restaurant", "region": "gym_roof", "pos": Vector2(8.68, -12.25), "ry": PI, "pose": "sit", "chair": false},
	{"id": "restaurant_bar_e", "place": "restaurant", "region": "gym_roof", "pos": Vector2(11.32, -12.25), "ry": PI, "pose": "sit", "chair": false},
	{"id": "restaurant_cook", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.6, -13.75), "ry": 0.0, "pose": "stand", "chair": false},
	# the yellow cafe: the dining table, a bar stool, the two new tables, the barista at the counter's end
	{"id": "cafe_dining_a", "place": "cafe", "region": "ground", "pos": Vector2(0.912, -9.28), "ry": 0.0, "pose": "sit", "chair": false},
	{"id": "cafe_dining_b", "place": "cafe", "region": "ground", "pos": Vector2(1.488, -9.28), "ry": 0.0, "pose": "sit", "chair": false},
	{"id": "cafe_dining_c", "place": "cafe", "region": "ground", "pos": Vector2(0.912, -7.82), "ry": PI, "pose": "sit", "chair": false},
	{"id": "cafe_dining_d", "place": "cafe", "region": "ground", "pos": Vector2(1.488, -7.82), "ry": PI, "pose": "sit", "chair": false},
	{"id": "cafe_bar_stool", "place": "cafe", "region": "ground", "pos": Vector2(-5.55, -5.04), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "cafe_t3_w", "place": "cafe", "region": "ground", "pos": Vector2(-2.62, -4.0), "ry": PI * 0.5, "pose": "sit", "chair": true},
	{"id": "cafe_t3_e", "place": "cafe", "region": "ground", "pos": Vector2(-1.18, -4.0), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "cafe_t4_w", "place": "cafe", "region": "ground", "pos": Vector2(-5.92, -2.8), "ry": PI * 0.5, "pose": "sit", "chair": true},
	{"id": "cafe_t4_e", "place": "cafe", "region": "ground", "pos": Vector2(-4.48, -2.8), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "cafe_barista", "place": "cafe", "region": "ground", "pos": Vector2(0.5, -10.2), "ry": -PI * 0.5, "pose": "stand", "chair": false},
	# the cafe terrace: the free sides of its tables, two new tables
	{"id": "terrace_t1_e", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-3.3, -5.6), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "terrace_t2_e", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(0.7, -5.6), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "terrace_umbrella_w", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-3.1, -2.6), "ry": PI * 0.5, "pose": "sit", "chair": true},
	{"id": "terrace_umbrella_e", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-1.3, -2.6), "ry": -PI * 0.5, "pose": "sit", "chair": true},
	{"id": "terrace_t3_n", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-4.0, -9.65), "ry": 0.0, "pose": "sit", "chair": true},
	{"id": "terrace_t3_s", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-4.0, -7.75), "ry": PI, "pose": "sit", "chair": true},
	{"id": "terrace_t4_n", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-0.5, -9.65), "ry": 0.0, "pose": "sit", "chair": true},
	{"id": "terrace_t4_s", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-0.5, -7.75), "ry": PI, "pose": "sit", "chair": true},
	# the tower's first-floor terrace: both chairs at each bistro table
	{"id": "tower_t1_w", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(8.68, -2.05), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "tower_t1_e", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(10.02, -2.05), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "tower_t2_w", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(12.28, -2.05), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "tower_t2_e", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(13.62, -2.05), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "tower_t3_w", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(14.68, -2.05), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "tower_t3_e", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(16.02, -2.05), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	# the shops: staff behind each counter, a browser at each shop's display, the little cafe's chairs
	{"id": "bakery_staff", "place": "shops", "region": "ground", "pos": Vector2(-18.1, 12.2), "ry": 0.0, "pose": "stand", "chair": false},
	{"id": "corner_cafe_staff", "place": "shops", "region": "ground", "pos": Vector2(-12.1, 12.2), "ry": 0.0, "pose": "stand", "chair": false},
	{"id": "bookstore_staff", "place": "shops", "region": "ground", "pos": Vector2(-6.1, 12.2), "ry": 0.0, "pose": "stand", "chair": false},
	{"id": "flowers_staff", "place": "shops", "region": "ground", "pos": Vector2(-0.1, 12.2), "ry": 0.0, "pose": "stand", "chair": false},
	{"id": "icecream_staff", "place": "shops", "region": "ground", "pos": Vector2(5.9, 12.2), "ry": 0.0, "pose": "stand", "chair": false},
	{"id": "bakery_browse", "place": "shops", "region": "ground", "pos": Vector2(-20.9, 10.3), "ry": PI, "pose": "stand", "chair": false},
	{"id": "bookstore_browse", "place": "shops", "region": "ground", "pos": Vector2(-8.0, 9.75), "ry": PI, "pose": "stand", "chair": false},
	{"id": "flowers_browse", "place": "shops", "region": "ground", "pos": Vector2(-2.9, 10.35), "ry": PI, "pose": "stand", "chair": false},
	{"id": "icecream_browse", "place": "shops", "region": "ground", "pos": Vector2(2.9, 10.1), "ry": PI, "pose": "stand", "chair": false},
	{"id": "corner_cafe_t1_w", "place": "shops", "region": "ground", "pos": Vector2(-16.32, 10.4), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "corner_cafe_t1_e", "place": "shops", "region": "ground", "pos": Vector2(-14.88, 10.4), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "corner_cafe_t2_w", "place": "shops", "region": "ground", "pos": Vector2(-13.32, 10.0), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "corner_cafe_t2_e", "place": "shops", "region": "ground", "pos": Vector2(-11.88, 10.0), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	# outdoor seating on the pavement
	{"id": "bistro_bakery_w", "place": "bistro", "region": "ground", "pos": Vector2(-22.72, 15.55), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_bakery_e", "place": "bistro", "region": "ground", "pos": Vector2(-21.38, 15.55), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_cafe_w", "place": "bistro", "region": "ground", "pos": Vector2(-16.72, 15.55), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_cafe_e", "place": "bistro", "region": "ground", "pos": Vector2(-15.38, 15.55), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_cafe2_w", "place": "bistro", "region": "ground", "pos": Vector2(-12.52, 15.55), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_cafe2_e", "place": "bistro", "region": "ground", "pos": Vector2(-11.18, 15.55), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_books_w", "place": "bistro", "region": "ground", "pos": Vector2(-10.72, 15.55), "ry": PI * 0.5, "pose": "sit", "chair": false},
	{"id": "bistro_books_e", "place": "bistro", "region": "ground", "pos": Vector2(-9.38, 15.55), "ry": -PI * 0.5, "pose": "sit", "chair": false},
	# the gym: a third treadmill, a rowing machine and a stretching mat below; two more bikes in the studio
	{"id": "gym_treadmill_c", "place": "gym", "region": "ground", "pos": Vector2(13.5, -12.3), "ry": PI, "pose": "run", "chair": false},
	{"id": "gym_rower", "place": "gym", "region": "ground", "pos": Vector2(13.7, -9.5), "ry": PI * 0.5, "pose": "row", "chair": false},
	{"id": "gym_mat", "place": "gym", "region": "ground", "pos": Vector2(16.6, -7.1), "ry": 0.0, "pose": "stretch", "chair": false},
	{"id": "studio_bike_c", "place": "gym", "region": "gym_l1", "pos": Vector2(14.0, -12.3), "ry": PI, "pose": "cycle", "chair": false},
	{"id": "studio_bike_d", "place": "gym", "region": "gym_l1", "pos": Vector2(16.0, -12.3), "ry": PI, "pose": "cycle", "chair": false},
]


## A rowing machine (local: the rail along z, the flywheel at -z, the seat sliding behind the centre).
static func _rower(a: Acc, d: Acc, w: float, dd: float) -> void:
	a.box(Vector3(0, 0.12, 0.1), Vector3(0.12, 0.08, dd - 0.3), col("white", -0.15))
	for sz: float in [-1.0, 1.0]:
		a.box(Vector3(0, 0.05, sz * (dd * 0.5 - 0.12)), Vector3(w - 0.1, 0.1, 0.12), col("dark"))
	a.prism(Vector3(0, 0.36, -dd * 0.5 + 0.22), 0.26, 0.2, col("peach"), 10, Basis(Vector3.FORWARD, PI * 0.5))
	a.prism(Vector3(0, 0.36, -dd * 0.5 + 0.22), 0.14, 0.24, col("dark"), 8, Basis(Vector3.FORWARD, PI * 0.5))
	a.box(Vector3(0, 0.22, 0.3), Vector3(0.3, 0.06, 0.3), col("dark", 0.2), 0.02)
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.12, 0.2, -dd * 0.5 + 0.55), Vector3(0.14, 0.04, 0.24), col("dark"))
	d.box(Vector3(0, 0.5, -dd * 0.5 + 0.5), Vector3(0.4, 0.04, 0.04), col("dark"))
	d.box(Vector3(0, 0.62, -dd * 0.5 + 0.3), Vector3(0.18, 0.12, 0.04), col("glass"))


## A small terracotta flowerpot with a leafy plant and blossoms (local, on the floor).
static func flowerpot(a: Acc, d: Acc, k: int) -> void:
	a.box(Vector3(0, 0.15, 0), Vector3(0.3, 0.3, 0.3), col("coral", -0.15) if k % 2 == 0 else col("white"), 0.03)
	a.box(Vector3(0, 0.31, 0), Vector3(0.34, 0.04, 0.34), col("coral") if k % 2 == 0 else col("mint_deep"))
	a.box(Vector3(0, 0.48, 0), Vector3(0.34, 0.3, 0.34), col("green") if k % 3 != 0 else col("green_deep"), 0.06)
	a.box(Vector3(0, 0.7, 0), Vector3(0.2, 0.18, 0.2), col("green_deep"), 0.04)
	var fc: Array[String] = ["peach", "yellow", "berry", "white", "blue"]
	d.box(Vector3(0.1, 0.66, 0.08), Vector3(0.08, 0.08, 0.08), col(fc[k % 5], 0.4 if fc[k % 5] == "berry" else 0.0))
	d.box(Vector3(-0.09, 0.6, -0.1), Vector3(0.08, 0.08, 0.08), col(fc[(k + 2) % 5]))


## A bus stop on the outer pavement (local: the road at +z): a pole with a BUS STOP sign, a small
## canopy on two posts and a bench.
static func bus_stop(a: Acc, d: Acc) -> void:
	a.box(Vector3(-1.3, 1.4, 0.3), Vector3(0.08, 2.8, 0.08), col("dark"))
	var sb := a.xf
	a.xf = sb * Transform3D(Basis.IDENTITY, Vector3(-1.3, 2.55, 0.36))
	a.box(Vector3.ZERO, Vector3(1.1, 0.42, 0.06), col("blue", -0.15), 0.02)
	a.lit().box(Vector3(0, 0, 0.03), Vector3(1.0, 0.32, 0.03), col("white"))
	text(a, "BUS STOP", Vector3(0, 0, 0.045), 0.02, col("blue", -0.3), 0.02)
	a.xf = sb
	for x: float in [-0.6, 0.6]:
		a.box(Vector3(x, 1.15, -0.25), Vector3(0.07, 2.3, 0.07), col("dark"))
	a.box(Vector3(0, 2.34, 0.0), Vector3(1.7, 0.08, 0.9), col("roof"), 0.02)
	a.box(Vector3(0, 2.28, 0.43), Vector3(1.7, 0.06, 0.04), col("white"))
	a.box(Vector3(0, 1.3, -0.3), Vector3(1.3, 1.6, 0.03), col("glass"))
	a.box(Vector3(0, 0.44, -0.12), Vector3(1.1, 0.05, 0.3), col("wood"), 0.015)
	for x: float in [-0.45, 0.45]:
		a.box(Vector3(x, 0.21, -0.12), Vector3(0.05, 0.42, 0.26), col("dark"))
	d.box(Vector3(0.35, 1.5, -0.28), Vector3(0.4, 0.5, 0.01), col("white"))
	d.box(Vector3(0.35, 1.68, -0.272), Vector3(0.32, 0.06, 0.01), col("blue"))


# ===================================================================== r2: the carousel

## Radius of the horses' ring on the turning platform, and the saddle's height above the deck.
const CAROUSEL_RING := 1.75
## The carousel canopy's rim radius (r3: wide enough to keep people dry outside the fence).
const CAROUSEL_CANOPY := 3.5
const CAROUSEL_DECK := 0.3
const SADDLE_Y := 0.95


## The carousel's fixed parts (world coordinates): a round plinth and a low fence with a gap on the side
## facing `gap_dir` (a unit vector on the ground), and a CAROUSEL sign over the gap.
static func carousel_base(a: Acc, gap_dir: Vector2) -> void:
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var r: float = CityMap.CAROUSEL["radius"]
	var at := Vector3(c.x, 0, c.y)
	a.prism(at + Vector3(0, 0.06, 0), r + 0.15, 0.12, col("kerb"), 24)
	a.prism(at + Vector3(0, 0.125, 0), r + 0.05, 0.01, col("white"), 24)
	var fr := r + 0.35
	var gap_a := atan2(-gap_dir.y, gap_dir.x)     # angles measured counter-clockwise from above (+x, then -z)
	var n := 28
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var mid := (a0 + a1) * 0.5
		if absf(wrapf(mid - gap_a, -PI, PI)) < 0.32:
			continue
		var p0 := at + Vector3(cos(a0) * fr, 0, -sin(a0) * fr)
		var p1 := at + Vector3(cos(a1) * fr, 0, -sin(a1) * fr)
		a.beam(p0 + Vector3(0, 0.62, 0), p1 + Vector3(0, 0.62, 0), 0.06, 0.06, col("white"))
		a.beam(p0 + Vector3(0, 0.3, 0), p1 + Vector3(0, 0.3, 0), 0.04, 0.04, col("mint_deep"))
		a.box(p0 + Vector3(0, 0.33, 0), Vector3(0.07, 0.66, 0.07), col("mint_deep"))
		if absf(wrapf(a1 - gap_a, -PI, PI)) < 0.33:
			a.box(p1 + Vector3(0, 0.33, 0), Vector3(0.07, 0.66, 0.07), col("mint_deep"))
	# the sign arch over the gap
	var g := Vector3(gap_dir.x, 0, gap_dir.y)
	var side := Vector3(-g.z, 0, g.x)
	var gc := at + g * fr
	for s: float in [-1.0, 1.0]:
		a.box(gc + side * s * 0.75 + Vector3(0, 1.2, 0), Vector3(0.1, 2.4, 0.1), col("peach", -0.15))
	var sb := a.xf
	a.xf = sb * Transform3D(Basis(Vector3.UP, atan2(g.x, g.z)), gc + Vector3(0, 2.45, 0))
	a.box(Vector3.ZERO, Vector3(1.9, 0.42, 0.08), col("peach", -0.15), 0.02)
	a.lit().box(Vector3(0, 0, 0.04), Vector3(1.8, 0.32, 0.04), col("cream"))
	text(a, "CAROUSEL", Vector3(0, 0, 0.06), 0.035, col("berry"), 0.03)
	a.xf = sb


## The turning part in its own frame (origin at the centre on the ground): the deck, the centre column,
## a brass pole per horse and the striped peach and mint canopy at roof_y.
static func carousel_turn(a: Acc) -> void:
	var r: float = CityMap.CAROUSEL["radius"]
	var roof_y: float = CityMap.CAROUSEL["roof_y"]
	var n: int = CityMap.CAROUSEL["horses"]
	a.prism(Vector3(0, 0.13 + CAROUSEL_DECK * 0.5 - 0.06, 0), r, CAROUSEL_DECK - 0.12, col("mint"), 24)
	a.prism(Vector3(0, CAROUSEL_DECK - 0.005, 0), r - 0.12, 0.01, col("cream"), 24)
	a.prism(Vector3(0, (CAROUSEL_DECK + roof_y) * 0.5, 0), 0.42, roof_y - CAROUSEL_DECK, col("cream"), 12)
	for y: float in [1.0, 2.2]:
		a.prism(Vector3(0, y, 0), 0.47, 0.18, col("berry"), 12)
	for i in n:
		var ang := TAU * float(i) / float(n)
		var p := Vector3(cos(ang) * CAROUSEL_RING, 0, -sin(ang) * CAROUSEL_RING)
		a.box(p + Vector3(0, (CAROUSEL_DECK + roof_y) * 0.5, 0), Vector3(0.05, roof_y - CAROUSEL_DECK, 0.05), col("yellow", -0.15))
	# the canopy: a ring of striped sloped panels, a scalloped valance and a finial
	var m := 16
	var rr := CAROUSEL_CANOPY
	var chord := 2.0 * PI * rr / float(m) + 0.06
	for i in m:
		var ang := TAU * (float(i) + 0.5) / float(m)
		var outer := Vector3(cos(ang) * rr, roof_y, -sin(ang) * rr)
		var inner := Vector3(cos(ang) * 0.3, roof_y + 1.0, -sin(ang) * 0.3)
		var cc := col("peach") if i % 2 == 0 else col("mint")
		# a panel from the rim up to the crown, its width along the ring's tangent
		var yv := (inner - outer).normalized()
		var tv := Vector3(-sin(ang), 0, -cos(ang))
		a.box((outer + inner) * 0.5, Vector3(chord, (inner - outer).length(), 0.06), cc, 0.0, Basis(tv, yv, tv.cross(yv)))
		a.box(outer + Vector3(0, -0.14, 0), Vector3(0.06, 0.22, chord), cc, 0.0, Basis(Vector3.UP, ang))
	# bulbs around the canopy's rim (lit at night)
	for i in 32:
		var ang := TAU * float(i) / 32.0
		a.lit().box(Vector3(cos(ang) * (rr + 0.04), roof_y - 0.28, -sin(ang) * (rr + 0.04)), Vector3(0.09, 0.09, 0.09), col("yellow", 0.4))
	a.prism(Vector3(0, roof_y + 1.02, 0), 0.4, 0.12, col("white"), 12)
	a.prism(Vector3(0, roof_y + 1.2, 0), 0.08, 0.3, col("yellow", -0.15), 8)
	a.box(Vector3(0.18, roof_y + 1.42, 0), Vector3(0.3, 0.16, 0.02), col("berry"))
	a.prism(Vector3(0, roof_y - 0.01, 0), rr, 0.02, col("cream"), 24)


## One carousel horse (local: its pole at the origin, saddle at SADDLE_Y, nose toward +z), white so a
## MultiMesh instance colour tints it a pastel; saddle, mane and hooves in palette colours.
static func carousel_horse(a: Acc) -> void:
	var body := col("white")
	a.box(Vector3(0, SADDLE_Y - 0.12, 0), Vector3(0.3, 0.32, 0.9), body, 0.06)
	a.box(Vector3(0, SADDLE_Y + 0.1, 0.42), Vector3(0.22, 0.42, 0.2), body, 0.04)
	a.box(Vector3(0, SADDLE_Y + 0.3, 0.6), Vector3(0.2, 0.2, 0.36), body, 0.04)
	a.box(Vector3(0, SADDLE_Y + 0.3, 0.79), Vector3(0.14, 0.12, 0.04), col("dark", 0.2))
	a.box(Vector3(0, SADDLE_Y + 0.28, 0.38), Vector3(0.08, 0.44, 0.14), col("berry"))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.07, SADDLE_Y + 0.42, 0.5), Vector3(0.05, 0.1, 0.05), body)
		a.box(Vector3(sx * 0.11, SADDLE_Y + 0.33, 0.66), Vector3(0.02, 0.05, 0.05), col("dark"))
		# front legs prancing, back legs reaching down
		a.beam(Vector3(sx * 0.1, SADDLE_Y - 0.22, 0.3), Vector3(sx * 0.1, SADDLE_Y - 0.4, 0.55), 0.08, 0.08, body)
		a.beam(Vector3(sx * 0.1, SADDLE_Y - 0.22, -0.32), Vector3(sx * 0.1, SADDLE_Y - 0.62, -0.4), 0.08, 0.08, body)
		a.box(Vector3(sx * 0.1, SADDLE_Y - 0.66, -0.41), Vector3(0.1, 0.06, 0.1), col("yellow", -0.15))
		a.box(Vector3(sx * 0.1, SADDLE_Y - 0.43, 0.59), Vector3(0.1, 0.06, 0.1), col("yellow", -0.15))
	a.box(Vector3(0, SADDLE_Y + 0.05, 0.0), Vector3(0.34, 0.06, 0.36), col("berry"), 0.02)
	a.box(Vector3(0, SADDLE_Y - 0.1, 0.0), Vector3(0.36, 0.2, 0.06), col("yellow"))
	a.beam(Vector3(0, SADDLE_Y - 0.05, -0.45), Vector3(0, SADDLE_Y - 0.35, -0.6), 0.08, 0.06, col("yellow", -0.15))


## The side the fence opens on: toward the nearest paved path.
static func carousel_gap_dir() -> Vector2:
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var best := Vector2(0, -1)
	var bd := INF
	for r: Rect2 in CityMap.PATHS:
		var q := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if q.distance_to(c) < bd and q.distance_to(c) > 0.01:
			bd = q.distance_to(c)
			best = (q - c).normalized()
	return best



## Where each BUS_STOPS sign and shelter stands: on the outer pavement beside the stop, facing the road,
## slid along the road if it would stand on a crossing.
static func bus_stop_frames() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var outer := CityMap.ROAD_OUTER
	for p: Vector2 in CityMap.BUS_STOPS:
		var n := Vector2.ZERO           # toward the outer pavement
		var travel := Vector2.ZERO      # clockwise traffic
		if absf(p.y - outer.position.y) < absf(p.y - outer.end.y) and absf(p.y - outer.position.y) < 4.0:
			n = Vector2(0, -1)
			travel = Vector2(1, 0)
		elif absf(p.y - outer.end.y) < 4.0:
			n = Vector2(0, 1)
			travel = Vector2(-1, 0)
		elif absf(p.x - outer.end.x) < 4.0:
			n = Vector2(1, 0)
			travel = Vector2(0, 1)
		else:
			n = Vector2(-1, 0)
			travel = Vector2(0, -1)
		var edge := absf(outer.position.y) if n.y != 0.0 else absf(outer.end.x)
		var at := p
		if n.y != 0.0:
			at.y = n.y * (edge + 0.95)
		else:
			at.x = n.x * (edge + 0.95)
		for _k in 20:
			var foot := Rect2(at - Vector2(1.6, 1.6), Vector2(3.2, 3.2))
			var hit := Rect2()
			for cr: Rect2 in CityMap.CROSSINGS:
				if cr.intersects(foot):
					hit = cr
			if hit.size == Vector2.ZERO:
				break
			var away := signf((at - hit.get_center()).dot(travel))
			at += travel * (away if away != 0.0 else 1.0) * 0.5
		out.append(Transform3D(Basis(Vector3.UP, atan2(-n.x, -n.y)), Vector3(at.x, 0.02, at.y)))
	return out


# ===================================================================== r3: street lamps

## A slim street lamp (local, on the ground): a dark post and a warm lit head under a green cap.
static func lamp_slim(a: Acc) -> void:
	a.box(Vector3(0, 0.08, 0), Vector3(0.24, 0.16, 0.24), col("dark"))
	a.box(Vector3(0, 1.75, 0), Vector3(0.09, 3.3, 0.09), col("dark"))
	a.box(Vector3(0, 3.42, 0), Vector3(0.18, 0.05, 0.18), col("dark"))
	a.lit().box(Vector3(0, 3.6, 0), Vector3(0.26, 0.32, 0.26), col("cream"), 0.03)
	a.box(Vector3(0, 3.8, 0), Vector3(0.32, 0.07, 0.32), col("roof"))


## The extra street lamps (r3; thin, not solid): along both pavement loops about 8 m apart, 0.35 m from
## the road's edge, flanking every crossing, around the carousel and beside every bus stop. The
## GROUND_SOLIDS lamps are kept as they are.
static var STREET_LAMPS: Array[Vector2] = street_lamps()

## Extra lamps placed by hand where the loops meet the west bus shelter and its crossing.
const MANUAL_LAMPS: Array[Vector2] = [Vector2(-24.65, 7.2), Vector2(-24.65, -4.3)]


static func street_lamps() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var taken: Array[Vector2] = []
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		if String(s["kind"]) == "lamp":
			taken.append(s["at"])
	for m in MANUAL_LAMPS:
		out.append(m)
		taken.append(m)
	for ring: Rect2 in [CityMap.ROAD_INNER.grow(-0.35), CityMap.ROAD_OUTER.grow(0.35)]:
		var corners: Array[Vector2] = [ring.position, Vector2(ring.end.x, ring.position.y), ring.end, Vector2(ring.position.x, ring.end.y)]
		for side in 4:
			var a := corners[side]
			var b := corners[(side + 1) % 4]
			var dir := (b - a).normalized()
			var n := int(ceil(a.distance_to(b) / 8.0))
			for k in n:
				var p := a.lerp(b, float(k) / float(n))
				var cands: Array[Vector2] = [p]
				# a crossing's mouth: a lamp on either side of it instead
				for cr: Rect2 in CityMap.CROSSINGS:
					if cr.grow(0.6).has_point(p):
						var lo := (cr.position - p).dot(dir) if dir.x + dir.y > 0.0 else (cr.end - p).dot(dir)
						var hi := (cr.end - p).dot(dir) if dir.x + dir.y > 0.0 else (cr.position - p).dot(dir)
						cands = [p + dir * (lo - 0.9), p + dir * (hi + 0.9)]
				for c in cands:
					var q := _lamp_spot(c, dir, taken)
					if q.x < 1e5:
						out.append(q)
						taken.append(q)
	# around the carousel (clear of its gap), and beside every bus stop
	var cc: Vector2 = CityMap.CAROUSEL["center"]
	var gap := carousel_gap_dir()
	for i in 6:
		var ang := TAU * float(i) / 6.0 + PI / 6.0
		var d := Vector2(cos(ang), -sin(ang))
		if d.dot(gap) > 0.75:
			continue
		var q := _lamp_spot(cc + d * 4.2, Vector2(-d.y, d.x), taken)
		if q.x < 1e5:
			out.append(q)
			taken.append(q)
	for xf in bus_stop_frames():
		var side := xf.basis.x
		var q := _lamp_spot(Vector2(xf.origin.x, xf.origin.z) + Vector2(side.x, side.z) * 1.7, Vector2(side.x, side.z), taken)
		if q.x < 1e5:
			out.append(q)
			taken.append(q)
	return out


## A clear spot for a lamp near p (slid along `dir` up to 3 m): off the crossings and road, 0.7 m from
## every solid, wall, ground furniture and bus shelter, 2.5 m from any other lamp. Vector2(INF, INF) if none.
static func _lamp_spot(p: Vector2, dir: Vector2, taken: Array[Vector2]) -> Vector2:
	for t in taken:
		if t.distance_to(p) < 2.5:
			return Vector2(INF, INF)
	var shelters := bus_stop_frames()
	for k in 13:
		var off := 0.5 * float((k + 1) >> 1) * (1.0 if k % 2 == 1 else -1.0)
		var q := p + dir * off
		if _lamp_clear(q, shelters):
			var near := false
			for t in taken:
				if t.distance_to(q) < 2.5:
					near = true
			if not near:
				return q
	return Vector2(INF, INF)


static func _lamp_clear(q: Vector2, shelters: Array[Transform3D]) -> bool:
	if not CityMap.OUTER_PAVEMENT.has_point(q):
		return false
	if CityMap.ROAD_OUTER.has_point(q) and not CityMap.ROAD_INNER.has_point(q):
		return false   # on the road
	for cr: Rect2 in CityMap.CROSSINGS:
		if cr.grow(0.6).has_point(q):
			return false
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		if s.has("rect") and (s["rect"] as Rect2).grow(0.7).has_point(q):
			return false
		if s.has("at") and (s["at"] as Vector2).distance_to(q) < float(s["r"]) + 0.7:
			return false
	for f: Dictionary in CityMap.FURNITURE:
		if String(f["region"]) == "ground" and (f["rect"] as Rect2).grow(0.7).has_point(q):
			return false
	for w: Rect2 in CityMap.GROUND_WALLS:
		if w.grow(0.7).has_point(q):
			return false
	for xf in shelters:
		if Vector2(xf.origin.x, xf.origin.z).distance_to(q) < 1.6:
			return false
	return true


# ===================================================================== r3: covers for the people

## Where a person can stand dry in the rain (for the people worker): under the shop awnings, just inside
## each shop door, in the bus shelters, under the carousel's canopy rim, inside the open ground floors and
## under the skywalks and the coral tower's terrace and canopy. Every stand spot is clear of solids and
## 0.9 m from every child's place on its region.
const COVERS := [
	{"id": "awning_bakery", "kind": "awning", "region": "ground", "rect": Rect2(-22.7, 15.0, 5.4, 1.0), "stand": [Vector2(-20.0, 15.6), Vector2(-17.9, 15.6)]},
	{"id": "awning_corner_cafe", "kind": "awning", "region": "ground", "rect": Rect2(-16.7, 15.0, 5.4, 1.0), "stand": [Vector2(-14.0, 15.6)]},
	{"id": "awning_bookstore", "kind": "awning", "region": "ground", "rect": Rect2(-10.7, 15.0, 5.4, 1.0), "stand": [Vector2(-8.0, 15.6), Vector2(-5.9, 15.6)]},
	{"id": "awning_flowers", "kind": "awning", "region": "ground", "rect": Rect2(-4.7, 15.0, 5.4, 1.0), "stand": [Vector2(-4.0, 15.6), Vector2(-2.0, 15.6), Vector2(0.3, 15.4)]},
	{"id": "awning_icecream", "kind": "awning", "region": "ground", "rect": Rect2(1.3, 15.0, 5.4, 1.0), "stand": [Vector2(2.0, 15.6), Vector2(4.0, 15.6), Vector2(6.0, 15.6)]},
	{"id": "inside_bakery", "kind": "interior", "region": "ground", "rect": Rect2(-22.2, 13.6, 4.4, 1.0), "stand": [Vector2(-21.7, 14.1), Vector2(-18.3, 14.1)]},
	{"id": "inside_corner_cafe", "kind": "interior", "region": "ground", "rect": Rect2(-16.2, 13.6, 4.4, 1.0), "stand": [Vector2(-15.7, 14.1), Vector2(-12.3, 14.1)]},
	{"id": "inside_bookstore", "kind": "interior", "region": "ground", "rect": Rect2(-10.2, 13.6, 4.4, 1.0), "stand": [Vector2(-9.7, 14.1), Vector2(-6.3, 14.1)]},
	{"id": "inside_flowers", "kind": "interior", "region": "ground", "rect": Rect2(-4.2, 13.6, 4.4, 1.0), "stand": [Vector2(-3.7, 14.1), Vector2(-0.3, 14.1)]},
	{"id": "inside_icecream", "kind": "interior", "region": "ground", "rect": Rect2(1.8, 13.6, 4.4, 1.0), "stand": [Vector2(2.3, 14.1), Vector2(5.7, 14.1)]},
	{"id": "shelter_west", "kind": "shelter", "region": "ground", "rect": Rect2(-23.6, 2.0, 0.8, 4.0), "stand": [Vector2(-23.3, 3.2), Vector2(-23.3, 4.8)]},
	{"id": "shelter_north", "kind": "shelter", "region": "ground", "rect": Rect2(7.15, -24.4, 1.7, 0.9), "stand": [Vector2(7.6, -23.8), Vector2(8.4, -23.8)]},
	{"id": "shelter_east", "kind": "shelter", "region": "ground", "rect": Rect2(31.5, -5.85, 0.9, 1.7), "stand": [Vector2(31.8, -5.4), Vector2(31.8, -4.6)]},
	{"id": "shelter_south", "kind": "shelter", "region": "ground", "rect": Rect2(-8.85, 23.5, 1.7, 0.9), "stand": [Vector2(-8.4, 23.8), Vector2(-7.6, 23.8)]},
	{"id": "shelter_west_outer", "kind": "shelter", "region": "ground", "rect": Rect2(-32.4, 4.15, 0.9, 1.7), "stand": [Vector2(-31.8, 4.6), Vector2(-31.8, 5.4)]},
	{"id": "carousel", "kind": "canopy", "region": "ground", "rect": Rect2(12.0, 8.7, 7.0, 7.0), "stand": [Vector2(17.8, 9.9), Vector2(13.2, 9.9), Vector2(13.2, 14.5), Vector2(17.8, 14.5)]},
	{"id": "office_lobby", "kind": "interior", "region": "ground", "rect": Rect2(-22.7, -4.0, 11.4, 2.0), "stand": [Vector2(-21.0, -3.0), Vector2(-17.5, -3.4), Vector2(-13.5, -3.0)]},
	{"id": "cafe_room", "kind": "interior", "region": "ground", "rect": Rect2(-6.7, -2.6, 9.4, 1.6), "stand": [Vector2(-3.4, -1.7), Vector2(0.0, -2.2), Vector2(2.0, -2.0)]},
	{"id": "gym_floor", "kind": "interior", "region": "ground", "rect": Rect2(7.3, -5.0, 11.4, 2.0), "stand": [Vector2(10.0, -4.3), Vector2(16.2, -4.0)]},
	{"id": "under_tower_terrace", "kind": "canopy", "region": "ground", "rect": Rect2(7.3, -3.0, 11.4, 1.6), "stand": [Vector2(9.0, -2.2), Vector2(12.0, -2.2), Vector2(15.0, -2.2)]},
	{"id": "under_skywalk_a", "kind": "canopy", "region": "ground", "rect": Rect2(-9.2, -11.0, 2.2, 2.0), "stand": [Vector2(-8.0, -10.0)]},
	{"id": "under_skywalk_b", "kind": "canopy", "region": "ground", "rect": Rect2(3.0, -11.0, 2.2, 1.6), "stand": [Vector2(4.0, -10.2)]},
	{"id": "tower_terrace_canopy", "kind": "canopy", "region": "gym_terrace", "rect": Rect2(7.3, -3.0, 11.4, 1.55), "stand": [Vector2(7.8, -2.6), Vector2(11.15, -2.7)]},
]


# ===================================================================== a bench (pavement)

static func bench(a: Acc) -> void:
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.7, 0.22, 0), Vector3(0.08, 0.44, 0.42), col("dark"))
	for i in 3:
		a.box(Vector3(0, 0.44, -0.14 + float(i) * 0.14), Vector3(1.6, 0.05, 0.11), col("wood"), 0.015)
	for i in 2:
		a.box(Vector3(0, 0.66 + float(i) * 0.14, -0.22), Vector3(1.6, 0.1, 0.04), col("wood"), 0.015)
