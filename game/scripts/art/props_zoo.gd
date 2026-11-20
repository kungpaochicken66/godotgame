## The zoo's toys and scenery (docs/zoo-engineering-standard.md section 6, design/zoo-and-world-journeys.md
## sections 4.1, 8 and 14.1). Everything is built from `mesh_kit.gd` primitives with matte soft colours and
## merged; the only transparent part is the water and the only texture is the blob shadow.
##
## Conventions as in `props.gd`: the origin is the ground centre, the front faces +z, y is up, 1 unit = 1 m.
## Low ring counts keep the budgets: a default sphere is 576 triangles, a rounded box with 3 segments 588.
extends RefCounted

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")

const KINDS := ["tram_stop", "zoo_ball", "zoo_box", "scratching_log", "leaf_feeder", "hay_bale", "play_mirror"]

## Where a swinging tyre hangs: add `tyre()` at this point of `tyre_frame()` and rotate it about x or z.
const TYRE_PIVOT := Vector3(0, 2.44, 0)

# Cool grey rock (it must contrast with a golden lion), sand, warm wood and leafy greens.
const ROCK := Color("#a3adbb")
const ROCK_DARK := Color("#8a95a6")
const ROCK_LIGHT := Color("#b9c1cc")
const SAND := Color("#ecdba9")
const STRAW := Color("#ebd07c")
const LEAF := Color("#8cc46c")
const LEAF_DARK := Color("#6eae5c")
const LEAF_LIGHT := Color("#a9d47f")
const CREAM := Color("#fbf6e8")
const WHITE := Color("#fbfaf4")
const GLASS := Color("#d4ebf4")
const ROPE := Color("#d8bd8a")
const GOLD := Color("#f2cf6b")
const NIGHT := Color("#5f6a78")


## Builds one catalog kind. `color` is a paint index (see Palette.PAINT); negative means cream.
static func build(kind: String, color: int) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var c: Color = Palette.paint(color) if color >= 0 else Palette.paint(0)
	match kind:
		"tram_stop": _tram_stop(root, c)
		"zoo_ball": _zoo_ball(root, c)
		"zoo_box": _zoo_box(root, c)
		"scratching_log": _scratching_log(root, c)
		"leaf_feeder": _leaf_feeder(root, c)
		"hay_bale": _hay_bale(root, c)
		"play_mirror": _play_mirror(root, c)
		_: Kit.blob_shadow(root, 0.4)
	Kit.merge_parts(root)
	return root


# ------------------------------------------------------------------- helpers

static func _shade(c: Color, d: float) -> Color:
	return c.lightened(d) if d >= 0.0 else c.darkened(-d)


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 7919 + 17
	return r


## A rounded box with few segments, so a small part costs about 100 triangles.
static func _rb(n: Node3D, size: Vector3, color: Variant, pos: Vector3, radius := 0.05, rot := Vector3.ZERO, seg := 1) -> MeshInstance3D:
	return Kit.part(n, Kit.rounded_box(size, radius, seg), color, pos, rot)


static func _ball(n: Node3D, radius: float, color: Variant, pos: Vector3, scl := Vector3.ONE, rings := 6) -> MeshInstance3D:
	return Kit.part(n, Kit.sphere(radius, rings), color, pos, Vector3.ZERO, scl)


static func _cy(n: Node3D, top: float, bottom: float, h: float, color: Variant, pos: Vector3, rot := Vector3.ZERO, sides := 10) -> MeshInstance3D:
	return Kit.part(n, Kit.cylinder(top, bottom, h, sides), color, pos, rot)


static func _finish(n: Node3D) -> Node3D:
	Kit.merge_parts(n)
	return n


## A new merged scenery root.
static func _root(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	return n


# ----------------------------------------------------------------- the toys

## 3.2 x 2.4 x 2.0: a platform, a short rail with a toy tram car, and a sign post with a paw.
static func _tram_stop(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.9, 0.2)
	# Platform on the back half, rail in front.
	_rb(n, Vector3(3.2, 0.25, 1.1), Palette.PATH, Vector3(0, 0.125, -0.45), 0.08, Vector3.ZERO, 2)
	_rb(n, Vector3(3.2, 0.06, 0.1), Palette.STONE.darkened(0.1), Vector3(0, 0.26, 0.04), 0.02)
	for x in [-1.3, -0.65, 0.0, 0.65, 1.3]:
		_rb(n, Vector3(0.14, 0.08, 0.76), Palette.WOOD_DARK, Vector3(x, 0.04, 0.62), 0.03)
	for z in [0.3, 0.94]:
		_rb(n, Vector3(3.2, 0.08, 0.1), ROCK_DARK, Vector3(0, 0.12, z), 0.03)
	_car(n, Vector3(0.35, 0.16, 0.62), 1.9, 0.7, c)
	# A bench on the platform.
	_rb(n, Vector3(0.9, 0.08, 0.34), Palette.WOOD, Vector3(0.3, 0.6, -0.7), 0.03)
	for x in [-0.12, 0.72]:
		_rb(n, Vector3(0.08, 0.3, 0.3), Palette.WOOD_DARK, Vector3(x, 0.4, -0.7), 0.02)
	# The sign post with a paw: pole, round board, one pad and four toes.
	_cy(n, 0.07, 0.08, 2.2, Palette.WOOD_DARK, Vector3(-1.18, 1.1, -0.65), Vector3.ZERO, 8)
	_cy(n, 0.42, 0.42, 0.1, CREAM, Vector3(-1.18, 2.0, -0.55), Vector3(90, 0, 0), 12)
	_ball(n, 0.15, c.darkened(0.05), Vector3(-1.18, 1.93, -0.49), Vector3(1, 0.85, 0.5), 5)
	for p in [Vector2(-0.24, 0.05), Vector2(-0.08, 0.2), Vector2(0.08, 0.2), Vector2(0.24, 0.05)]:
		_ball(n, 0.07, c.darkened(0.05), Vector3(-1.18 + p.x, 1.93 + p.y, -0.49), Vector3(1, 1, 0.5), 4)
	_ball(n, 0.1, Palette.WOOD_DARK, Vector3(-1.18, 2.3, -0.65), Vector3.ONE, 5)
	_cy(n, 0.05, 0.05, 0.2, Palette.WOOD_DARK, Vector3(-1.18, 2.3, -0.65), Vector3.ZERO, 6)


## The toy tram: a rounded car on four small wheels. `o` is where its wheels touch the rail.
static func _car(n: Node3D, o: Vector3, length: float, width: float, c: Color) -> void:
	_rb(n, Vector3(length, 0.7, width), c, o + Vector3(0, 0.5, 0), 0.16, Vector3.ZERO, 2)
	_rb(n, Vector3(length - 0.12, 0.12, width - 0.06), CREAM, o + Vector3(0, 0.9, 0), 0.05)
	_rb(n, Vector3(length * 0.72, 0.26, width + 0.04), GLASS, o + Vector3(0, 0.62, 0), 0.05)
	_rb(n, Vector3(0.14, 0.12, width - 0.2), GOLD, o + Vector3(length * 0.5 - 0.04, 0.34, 0), 0.04)
	for sx in [-0.3, 0.3]:
		for sz in [-1.0, 1.0]:
			_cy(n, 0.12, 0.12, 0.08, Palette.WOOD_DARK, o + Vector3(length * sx, 0.12, sz * (width * 0.5 - 0.04)), Vector3(90, 0, 0), 8)


static func _zoo_ball(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.22, 0.2)
	_ball(n, 0.25, c, Vector3(0, 0.25, 0), Vector3.ONE, 8)
	# Soft patches on the six sides, kept inside the 0.5 m bounds.
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0)]
	for d: Vector3 in dirs:
		var p: Vector3 = Vector3(0, 0.25, 0) + d * 0.2
		var s := Vector3(1, 1, 1) - d.abs() * 0.7
		_ball(n, 0.1, CREAM, p, s, 4)


static func _zoo_box(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.4, 0.2)
	var cardboard := Color("#d9b27c").lerp(c, 0.25)
	_rb(n, Vector3(0.9, 0.06, 0.86), cardboard.darkened(0.08), Vector3(0, 0.03, 0), 0.02)
	_rb(n, Vector3(0.9, 0.8, 0.08), cardboard, Vector3(0, 0.4, -0.39), 0.03)
	_rb(n, Vector3(0.9, 0.8, 0.08), cardboard, Vector3(0, 0.4, 0.39), 0.03)
	for x in [-0.41, 0.41]:
		_rb(n, Vector3(0.08, 0.8, 0.7), cardboard.lightened(0.04), Vector3(x, 0.4, 0), 0.03)
	# A tape stripe along the rim and a hand hole on the front.
	_rb(n, Vector3(0.9, 0.1, 0.1), c, Vector3(0, 0.75, 0.4), 0.03)
	_rb(n, Vector3(0.34, 0.14, 0.06), cardboard.darkened(0.35), Vector3(0, 0.4, 0.43), 0.04)


static func _scratching_log(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.36, 0.22)
	_cy(n, 0.4, 0.4, 1.8, Palette.WOOD, Vector3(0, 0.4, 0), Vector3(0, 0, 90), 12)
	for x in [-0.55, 0.0, 0.55]:
		_cy(n, 0.405, 0.405, 0.1, c, Vector3(x, 0.4, 0), Vector3(0, 0, 90), 12)
	# Pale scratched strokes on the front.
	for i in 3:
		_rb(n, Vector3(0.07, 0.3, 0.06), Palette.WOOD.lightened(0.25), Vector3(-0.3 + i * 0.3, 0.4, 0.4), 0.02, Vector3(0, 0, 10 - i * 10))
	# Chocks so it does not roll.
	for x in [-0.6, 0.6]:
		_rb(n, Vector3(0.3, 0.12, 0.7), Palette.WOOD_DARK, Vector3(x, 0.06, 0), 0.04)


static func _leaf_feeder(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.4, 0.2)
	_rb(n, Vector3(0.9, 0.12, 0.9), Palette.WOOD_DARK, Vector3(0, 0.06, 0), 0.05)
	_cy(n, 0.1, 0.12, 1.9, Palette.WOOD, Vector3(0, 1.0, 0), Vector3.ZERO, 8)
	# A trough high up (a giraffe's mouth height) heaped with leaves.
	_rb(n, Vector3(0.9, 0.24, 0.9), c, Vector3(0, 1.98, 0), 0.08, Vector3.ZERO, 2)
	_rb(n, Vector3(0.7, 0.1, 0.7), LEAF_DARK, Vector3(0, 2.1, 0), 0.04)
	for p in [Vector3(-0.2, 2.18, -0.15), Vector3(0.2, 2.18, -0.1), Vector3(0, 2.18, 0.2), Vector3(0.0, 2.18, -0.1)]:
		_ball(n, 0.22, LEAF if p.x >= 0.0 else LEAF_LIGHT, p, Vector3.ONE, 5)


static func _hay_bale(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.36, 0.2)
	_rb(n, Vector3(1.1, 0.78, 0.78), STRAW, Vector3(0, 0.39, 0), 0.14, Vector3.ZERO, 2)
	for x in [-0.3, 0.3]:
		_rb(n, Vector3(0.08, 0.8, 0.8), c, Vector3(x, 0.4, 0), 0.04)
	# Loose straw on top.
	for i in 3:
		_rb(n, Vector3(0.28, 0.06, 0.07), STRAW.lightened(0.12), Vector3(-0.25 + i * 0.25, 0.77, -0.1 + i * 0.1), 0.02, Vector3(0, 25 * (i - 1), 0))


static func _play_mirror(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.18, 0.2)
	for x in [-0.32, 0.32]:
		_rb(n, Vector3(0.2, 0.1, 0.4), c.darkened(0.08), Vector3(x, 0.05, 0), 0.04)
	_rb(n, Vector3(1.0, 1.1, 0.12), c, Vector3(0, 0.65, 0), 0.1, Vector3.ZERO, 2)
	_rb(n, Vector3(0.78, 0.9, 0.06), GLASS, Vector3(0, 0.65, 0.06), 0.04)
	# Round ears on top.
	for x in [-0.38, 0.38]:
		_ball(n, 0.1, c, Vector3(x, 1.2, 0), Vector3.ONE, 5)


# ------------------------------------------------------------ the stations

static func tram_car() -> Node3D:
	var n := _root("tram_car")
	Kit.blob_shadow(n, 0.85, 0.2)
	_car(n, Vector3.ZERO, 2.4, 0.95, Palette.paint(2))
	return _finish(n)


## The platform and shelter of a station (8 x 4 m at the Zoo Station), the tram stops on the +z side.
static func station(size: Vector2) -> Node3D:
	var n := _root("station")
	_rb(n, Vector3(size.x, 0.3, size.y), Palette.PATH, Vector3(0, 0.15, 0), 0.08, Vector3.ZERO, 2)
	_rb(n, Vector3(size.x, 0.06, 0.14), Palette.WOOD, Vector3(0, 0.33, size.y * 0.5 - 0.1), 0.02)
	var sw: float = minf(size.x * 0.6, 4.8)
	var sz: float = -size.y * 0.5 + 1.0
	for x in [-sw * 0.5 + 0.2, sw * 0.5 - 0.2]:
		_cy(n, 0.09, 0.09, 2.2, Palette.WOOD_DARK, Vector3(x, 1.4, sz + 0.5), Vector3.ZERO, 8)
		_cy(n, 0.09, 0.09, 2.2, Palette.WOOD_DARK, Vector3(x, 1.4, sz - 0.5), Vector3.ZERO, 8)
	_rb(n, Vector3(sw, 0.2, 1.8), Palette.paint(3), Vector3(0, 2.6, sz), 0.08, Vector3(-4, 0, 0), 2)
	_rb(n, Vector3(sw - 0.5, 0.5, 0.1), CREAM, Vector3(0, 0.75, sz - 0.8), 0.04)
	_rb(n, Vector3(sw - 1.2, 0.1, 0.4), Palette.WOOD, Vector3(0, 0.7, sz - 0.5), 0.03)
	for x in [-sw * 0.5 + 0.8, sw * 0.5 - 0.8]:
		_rb(n, Vector3(0.1, 0.4, 0.34), Palette.WOOD_DARK, Vector3(x, 0.5, sz - 0.5), 0.03)
	return _finish(n)


# ------------------------------------------------------------------- rocks

## A flat-topped, softly faceted rock block. Its top is exactly at `size.y`; animals stand on it.
static func rock(size: Vector3, seed: int) -> Node3D:
	var n := _root("rock")
	var r := _rng(seed)
	var rad: float = minf(0.3, size.y * 0.3)
	var tone: float = r.randf_range(-0.04, 0.04)
	# A wide base block, and a narrower upper block (turned a little) that carries the flat top.
	var h0: float = size.y * 0.62
	_rb(n, Vector3(size.x, h0, size.z), _shade(ROCK_DARK, tone), Vector3(0, h0 * 0.5, 0), rad, Vector3.ZERO, 2)
	var up := Vector3(size.x * r.randf_range(0.8, 0.9), size.y * 0.7, size.z * r.randf_range(0.78, 0.9))
	var off := Vector3(r.randf_range(-0.05, 0.05) * size.x, 0, r.randf_range(-0.05, 0.05) * size.z)
	_rb(n, up, _shade(ROCK, tone), Vector3(off.x, size.y - up.y * 0.5, off.z), rad, Vector3(0, r.randf_range(-5.0, 5.0), 0), 2)
	# A few rounded boulders at the foot, below the top.
	for i in 3:
		var a: float = TAU * (float(i) + r.randf()) / 3.0
		var br: float = minf(size.y * 0.3, 0.35)
		var p := Vector3(cos(a) * (size.x * 0.5 - br), br * 0.7, sin(a) * (size.z * 0.5 - br))
		_ball(n, br, _shade(ROCK_DARK, 0.04 + tone), p, Vector3(1.0, 0.7, 1.0), 5)
	return _finish(n)


## A taller broken rock mass for backdrops and dens: tiers that narrow toward the top (`size.y`).
static func crag(size: Vector3, seed: int) -> Node3D:
	var n := _root("crag")
	var r := _rng(seed)
	var tiers := 4
	var y := 0.0
	for i in tiers:
		var f: float = 1.0 - 0.17 * float(i)
		var h: float = size.y * (0.4 if i == 0 else 0.25)
		if i == tiers - 1:
			h = size.y - y
		var sz := Vector3(size.x * f, h, size.z * f)
		var p := Vector3(r.randf_range(-0.08, 0.08) * size.x * float(i), y + h * 0.5, -0.06 * size.z * float(i))
		_rb(n, sz, _shade(ROCK, 0.05 * float(i) - 0.06), p, minf(0.35, h * 0.3), Vector3(0, r.randf_range(-7.0, 7.0), 0), 2)
		y += h * 0.85
	return _finish(n)


# ------------------------------------------------------------------- plants

static func acacia() -> Node3D:
	var n := _root("acacia")
	Kit.blob_shadow(n, 1.2, 0.24)
	_cy(n, 0.12, 0.2, 2.2, Palette.WOOD_DARK, Vector3(0, 1.1, 0), Vector3.ZERO, 8)
	_cy(n, 0.07, 0.11, 0.9, Palette.WOOD_DARK, Vector3(0.35, 2.0, 0), Vector3(0, 0, -40), 8)
	_cy(n, 0.07, 0.11, 0.9, Palette.WOOD_DARK, Vector3(-0.35, 2.0, 0.05), Vector3(0, 0, 40), 8)
	# A wide flat crown, top at about 2.8 m.
	_ball(n, 1.0, LEAF_DARK.lightened(0.1), Vector3(0, 2.45, 0), Vector3(1.35, 0.32, 1.3), 8)
	_ball(n, 0.8, LEAF_LIGHT.darkened(0.05), Vector3(-0.75, 2.4, 0.2), Vector3(1.1, 0.3, 1.0), 6)
	_ball(n, 0.8, LEAF, Vector3(0.8, 2.5, -0.15), Vector3(1.1, 0.3, 1.0), 6)
	return _finish(n)


static func shade_tree() -> Node3D:
	var n := _root("shade_tree")
	Kit.blob_shadow(n, 1.6, 0.26)
	_cy(n, 0.2, 0.3, 1.8, Palette.WOOD_DARK, Vector3(0, 0.9, 0), Vector3.ZERO, 8)
	_cy(n, 0.09, 0.14, 0.9, Palette.WOOD_DARK, Vector3(0.45, 1.8, 0), Vector3(0, 0, -45), 8)
	_cy(n, 0.09, 0.14, 0.9, Palette.WOOD_DARK, Vector3(-0.45, 1.8, 0), Vector3(0, 0, 45), 8)
	_ball(n, 1.15, LEAF, Vector3(0, 2.7, 0), Vector3.ONE, 8)
	_ball(n, 0.8, LEAF_DARK, Vector3(0.95, 2.35, 0.3), Vector3.ONE, 6)
	_ball(n, 0.8, LEAF_LIGHT.darkened(0.04), Vector3(-0.9, 2.45, -0.3), Vector3.ONE, 6)
	_ball(n, 0.65, LEAF_LIGHT, Vector3(0.1, 3.3, 0.2), Vector3.ONE, 6)
	return _finish(n)


## Sparse stalks 1.4 to 1.8 m tall inside `size` (x by z), with leaf tufts.
static func bamboo(size: Vector2) -> Node3D:
	var n := _root("bamboo")
	var r := _rng(int(size.x * 10.0 + size.y))
	var count: int = clampi(int(size.x * size.y * 0.6), 4, 24)
	var greens: Array[Color] = [Color("#9ccb73"), Color("#85bd68"), Color("#b0d985")]
	for i in count:
		var x: float = r.randf_range(-0.5, 0.5) * (size.x - 0.2)
		var z: float = r.randf_range(-0.5, 0.5) * (size.y - 0.2)
		var h: float = r.randf_range(1.4, 1.8)
		var g: Color = greens[i % 3]
		_cy(n, 0.05, 0.06, h, g, Vector3(x, h * 0.5, z), Vector3(r.randf_range(-3, 3), 0, r.randf_range(-3, 3)), 6)
		_ball(n, 0.15, g.lightened(0.08), Vector3(x + 0.1, h - 0.1, z), Vector3(1.6, 0.5, 0.8), 3)
	return _finish(n)


## A low clipped hedge `length` m long along x (0.8 m high, 0.6 m deep).
static func hedge(length: float) -> Node3D:
	var n := _root("hedge")
	_rb(n, Vector3(length, 0.7, 0.6), LEAF_DARK, Vector3(0, 0.35, 0), 0.22, Vector3.ZERO, 2)
	var count: int = maxi(2, int(length / 0.55))
	for i in count:
		var x: float = -length * 0.5 + (float(i) + 0.5) * length / float(count)
		_ball(n, 0.28, LEAF if i % 2 == 0 else LEAF_LIGHT.darkened(0.04), Vector3(x, 0.62, 0.0), Vector3(1.0, 0.8, 1.0), 4)
	return _finish(n)


# ------------------------------------------------------------------- water

## A flat calm pond (an ellipse of `size`, x by z) with a soft sand shore. `depth` darkens the colour.
## The surface is the only translucent part, one matte material, node "Water".
static func water(size: Vector2, depth: float) -> Node3D:
	var n := _root("water")
	var unit := Kit.cylinder(1.0, 1.0, 0.04, 28)
	Kit.part(n, unit, SAND, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(size.x * 0.5 + 0.55, 1.0, size.y * 0.5 + 0.55))
	Kit.part(n, unit, SAND.darkened(0.12), Vector3(0, 0.035, 0), Vector3.ZERO, Vector3(size.x * 0.5 + 0.2, 1.0, size.y * 0.5 + 0.2))
	var d: float = clampf(depth / 2.0, 0.0, 1.0)
	var col: Color = Palette.WATER.darkened(d * 0.25)
	col.a = 0.86
	var surface := Kit.part(n, unit, Kit.mat(col, 0.9), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(size.x * 0.5, 1.0, size.y * 0.5))
	surface.name = "Water"
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return _finish(n)


## A stepped rock face with white falling water (strips and drops, no particles). `width` along x.
static func falls(width: float, height: float) -> Node3D:
	var n := _root("falls")
	var depth := 1.8
	var step: float = depth / 3.0
	for i in 3:
		var th: float = height * float(i + 1) / 3.0
		var w: float = width * (1.0 - 0.08 * float(2 - i))
		var d: float = depth - step * float(i)
		var front: float = depth * 0.5 - step * float(i)
		var zc2: float = front - d * 0.5
		_rb(n, Vector3(w, th, d), _shade(ROCK, 0.03 * float(i) - 0.05), Vector3(0, th * 0.5, zc2), minf(0.3, th * 0.3), Vector3.ZERO, 2)
		# White water pouring over this tier's front onto the next lower one.
		if i > 0:
			var lower: float = height * float(i) / 3.0
			var fall: float = th - lower
			for k in 3:
				var x: float = (float(k) - 1.0) * w * 0.22
				_rb(n, Vector3(0.22, fall, 0.1), WHITE, Vector3(x, lower + fall * 0.5, front + 0.04), 0.04)
	# The lowest tier carries a sheet over its front into the pool, with a few drops.
	var first: float = height / 3.0
	for k in 3:
		_rb(n, Vector3(0.22, first, 0.1), WHITE, Vector3((float(k) - 1.0) * width * 0.2, first * 0.5, depth * 0.5 + 0.04), 0.04)
	for p in [Vector2(-0.5, 0.35), Vector2(0.1, 0.5), Vector2(0.55, 0.3)]:
		_ball(n, 0.09, WHITE, Vector3(p.x * width * 0.5, 0.2, depth * 0.5 + 0.35), Vector3.ONE, 4)
	# Foam at the foot.
	_cy(n, 1.0, 1.0, 0.05, WHITE.darkened(0.04), Vector3(0, 0.025, depth * 0.5 + 0.3), Vector3.ZERO, 16).scale = Vector3(width * 0.3, 1.0, 0.6)
	return _finish(n)


# --------------------------------------------------------- climbing and play

## A balance bridge of logs along x, deck top at 0.6 m.
static func log_bridge(length: float) -> Node3D:
	var n := _root("log_bridge")
	for i in 4:
		var z: float = (float(i) - 1.5) * 0.3
		_cy(n, 0.15, 0.15, length, Palette.WOOD if i % 2 == 0 else Palette.WOOD.darkened(0.06), Vector3(0, 0.45, z), Vector3(0, 0, 90), 8)
	for x in [-length * 0.5 + 0.35, length * 0.5 - 0.35]:
		_rb(n, Vector3(0.2, 0.32, 1.3), Palette.WOOD_DARK, Vector3(x, 0.16, 0), 0.05)
		for z in [-0.7, 0.7]:
			_rb(n, Vector3(0.1, 0.5, 0.1), Palette.WOOD_DARK, Vector3(x, 0.85, z), 0.03)
	for z in [-0.7, 0.7]:
		_cy(n, 0.04, 0.04, length - 0.7, ROPE, Vector3(0, 1.0, z), Vector3(0, 0, 90), 6)
	return _finish(n)


## A tree trunk to stretch against: 2.6 m tall, pale scratches on the +z side.
static func scratch_tree() -> Node3D:
	var n := _root("scratch_tree")
	Kit.blob_shadow(n, 0.9, 0.24)
	_cy(n, 0.2, 0.28, 2.6, Palette.WOOD_DARK, Vector3(0, 1.3, 0), Vector3.ZERO, 10)
	for i in 4:
		_rb(n, Vector3(0.07, 0.7, 0.06), Palette.WOOD.lightened(0.2), Vector3(-0.1 + i * 0.07, 0.9 + 0.12 * float(i % 2), 0.25), 0.02, Vector3(0, 0, 8 - i * 4))
	_ball(n, 0.85, LEAF, Vector3(0, 2.8, 0), Vector3.ONE, 7)
	_ball(n, 0.55, LEAF_LIGHT, Vector3(0.5, 3.15, 0.1), Vector3.ONE, 5)
	return _finish(n)


## Seven-ring (or `rings`) run along x: a beam whose top is at `height`, hoops with hands at height - 0.3.
static func ring_run(length: float, height: float, rings: int) -> Node3D:
	var n := _root("ring_run")
	for x in [-length * 0.5 + 0.15, length * 0.5 - 0.15]:
		_cy(n, 0.1, 0.12, height - 0.1, Palette.WOOD, Vector3(x, (height - 0.1) * 0.5, 0), Vector3.ZERO, 8)
		_rb(n, Vector3(0.5, 0.1, 0.5), Palette.WOOD_DARK, Vector3(x, 0.05, 0), 0.04)
	_rb(n, Vector3(length, 0.16, 0.18), Palette.WOOD_DARK, Vector3(0, height - 0.08, 0), 0.05)
	var hands: float = height - 0.3
	var hoop := 0.16
	for i in rings:
		var x: float = -length * 0.5 + length * (float(i) + 1.0) / (float(rings) + 1.0)
		_cy(n, 0.03, 0.03, 0.3 - hoop, ROPE, Vector3(x, height - 0.16 - (0.3 - hoop) * 0.5 + 0.0, 0), Vector3.ZERO, 5)
		for k in 6:
			var a: float = TAU * float(k) / 6.0
			_ball(n, 0.05, GOLD if i % 2 == 0 else Palette.paint(3), Vector3(x + cos(a) * hoop, hands + sin(a) * hoop, 0), Vector3.ONE, 3)
	return _finish(n)


## A climbing tower with its deck top at `height`, a pole and a net ramp up the +z side.
static func tower(height: float) -> Node3D:
	var n := _root("tower")
	Kit.blob_shadow(n, 1.0, 0.22)
	for x in [-0.7, 0.7]:
		for z in [-0.7, 0.7]:
			_cy(n, 0.09, 0.1, height, Palette.WOOD, Vector3(x, height * 0.5, z), Vector3.ZERO, 8)
	_rb(n, Vector3(1.7, 0.16, 1.7), Palette.WOOD_DARK, Vector3(0, height - 0.08, 0), 0.05, Vector3.ZERO, 2)
	for z in [-0.78]:
		_rb(n, Vector3(1.7, 0.4, 0.08), Palette.WOOD, Vector3(0, height + 0.2, z), 0.03)
	for x in [-0.78, 0.78]:
		_rb(n, Vector3(0.08, 0.4, 1.6), Palette.WOOD, Vector3(x, height + 0.2, 0), 0.03)
	_cy(n, 0.06, 0.06, 0.9, Palette.WOOD_DARK, Vector3(0.6, height + 0.55, -0.6), Vector3.ZERO, 6)
	_rb(n, Vector3(0.7, 0.3, 0.1), Palette.paint(1), Vector3(0.6, height + 0.9, -0.6), 0.04)
	# The net ramp: a slanted rope-coloured board with rungs.
	var run := 1.5
	var ang: float = atan2(height, run)
	var len_: float = sqrt(height * height + run * run)
	var mid := Vector3(0, height * 0.5, 0.85 + run * 0.5)
	_rb(n, Vector3(1.0, 0.07, len_), ROPE, mid, 0.03, Vector3(rad_to_deg(ang), 0, 0))
	for i in 4:
		var t: float = (float(i) + 0.5) / 4.0
		_rb(n, Vector3(1.1, 0.07, 0.07), Palette.WOOD_DARK, Vector3(0, height * (1.0 - t), 0.85 + run * t) + Vector3(0, 0.05, 0), 0.02)
	return _finish(n)


## A low balance beam along x with its top at 0.5 m.
static func beam(length: float) -> Node3D:
	var n := _root("beam")
	_rb(n, Vector3(length, 0.16, 0.3), Palette.WOOD, Vector3(0, 0.42, 0), 0.06, Vector3.ZERO, 2)
	for x in [-length * 0.5 + 0.35, length * 0.5 - 0.35]:
		_rb(n, Vector3(0.18, 0.34, 0.5), Palette.WOOD_DARK, Vector3(x, 0.17, 0), 0.05)
	return _finish(n)


## Two posts and a crossbar whose top is at `height`, with two hanging vines, hands near their ends.
static func vine_arch(height: float) -> Node3D:
	var n := _root("vine_arch")
	for x in [-1.3, 1.3]:
		_cy(n, 0.12, 0.15, height, Palette.WOOD, Vector3(x, height * 0.5, 0), Vector3.ZERO, 8)
		_rb(n, Vector3(0.6, 0.1, 0.6), Palette.WOOD_DARK, Vector3(x, 0.05, 0), 0.04)
	_rb(n, Vector3(3.0, 0.2, 0.22), Palette.WOOD_DARK, Vector3(0, height - 0.1, 0), 0.06)
	for p in [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)]:
		_cy(n, 0.04, 0.04, 2.0, LEAF_DARK, Vector3(p.x, height - 1.1, 0), Vector3.ZERO, 6)
		_ball(n, 0.1, LEAF, Vector3(p.x, height - 2.1, 0), Vector3.ONE, 4)
	for x in [-1.0, -0.2, 0.7, 1.2]:
		_ball(n, 0.2, LEAF, Vector3(x, height - 0.25, 0.05), Vector3(1.0, 0.8, 1.0), 4)
	return _finish(n)


## A rock spire with a ledge at each height (ascending), e.g. [0.8, 1.4, 2.0, 3.2].
static func spire(heights: Array) -> Node3D:
	var n := _root("spire")
	var hs: Array = heights.duplicate()
	hs.sort()
	var count: int = hs.size()
	for i in count:
		var h: float = float(hs[i])
		var f: float = 1.0 - 0.2 * float(i)
		var sz := Vector3(2.4 * f, h, 1.8 * f)
		_rb(n, sz, _shade(ROCK, 0.04 * float(i) - 0.05), Vector3(0.0, h * 0.5, -0.3 * float(i)), minf(0.3, h * 0.3), Vector3(0, 6.0 * float(i % 2) - 3.0, 0), 2)
	return _finish(n)


## A hammock between two posts; the cloth top is about 0.75 m.
static func hammock() -> Node3D:
	var n := _root("hammock")
	for x in [-1.0, 1.0]:
		_cy(n, 0.07, 0.09, 1.2, Palette.WOOD_DARK, Vector3(x, 0.6, 0), Vector3.ZERO, 8)
		_rb(n, Vector3(0.4, 0.08, 0.4), Palette.WOOD_DARK, Vector3(x, 0.04, 0), 0.03)
		_cy(n, 0.03, 0.03, 0.66, ROPE, Vector3(x * 0.88, 0.88, 0), Vector3(0, 0, -x * 38.0), 5)
	_ball(n, 1.0, Palette.paint(4), Vector3(0, 0.62, 0), Vector3(0.78, 0.1, 0.38), 6)
	_ball(n, 1.0, Palette.paint(3), Vector3(0, 0.66, 0), Vector3(0.45, 0.1, 0.28), 5)
	return _finish(n)


## The frame the tyre hangs from: two A-posts and a crossbar. Hang `tyre()` at TYRE_PIVOT.
static func tyre_frame() -> Node3D:
	var n := _root("tyre_frame")
	Kit.blob_shadow(n, 1.1, 0.22)
	for x in [-1.1, 1.1]:
		_cy(n, 0.1, 0.12, 2.6, Palette.WOOD, Vector3(x, 1.3, 0), Vector3.ZERO, 8)
		_rb(n, Vector3(0.5, 0.1, 0.9), Palette.WOOD_DARK, Vector3(x, 0.05, 0), 0.04)
		_cy(n, 0.06, 0.06, 1.2, Palette.WOOD_DARK, Vector3(x * 0.75, 0.55, 0.0), Vector3(0, 0, -x * 12.0), 6)
	_rb(n, Vector3(2.6, 0.16, 0.2), Palette.WOOD_DARK, Vector3(0, 2.52, 0), 0.05)
	_ball(n, 0.09, ROPE, Vector3(0, 2.44, 0), Vector3.ONE, 4)
	return _finish(n)


## The swinging tyre with its rope. The origin is the hanging point, the tyre hangs below it.
static func tyre() -> Node3D:
	var n := _root("tyre")
	_cy(n, 0.04, 0.04, 1.3, ROPE, Vector3(0, -0.65, 0), Vector3.ZERO, 5)
	Kit.part(n, Kit.torus(0.17, 0.43), NIGHT, Vector3(0, -1.62, 0), Vector3(90, 0, 0))
	return _finish(n)


## A bell on a post with a rope to pull. The bell is at about 2.0 m, the rope end at 1.0 m.
static func bell_rope() -> Node3D:
	var n := _root("bell_rope")
	Kit.blob_shadow(n, 0.5, 0.2)
	_cy(n, 0.08, 0.1, 2.4, Palette.WOOD, Vector3(0, 1.2, 0), Vector3.ZERO, 8)
	_rb(n, Vector3(0.1, 0.1, 0.7), Palette.WOOD_DARK, Vector3(0, 2.35, 0.3), 0.03)
	_cy(n, 0.12, 0.26, 0.3, GOLD, Vector3(0, 2.0, 0.58), Vector3.ZERO, 10)
	_ball(n, 0.13, GOLD, Vector3(0, 2.2, 0.58), Vector3.ONE, 5)
	_ball(n, 0.07, GOLD.darkened(0.15), Vector3(0, 1.82, 0.58), Vector3.ONE, 4)
	_cy(n, 0.03, 0.03, 0.8, ROPE, Vector3(0, 1.4, 0.58), Vector3.ZERO, 5)
	_ball(n, 0.08, Palette.paint(3), Vector3(0, 0.95, 0.58), Vector3.ONE, 4)
	return _finish(n)


## Two drums of different heights.
static func bongo_logs() -> Node3D:
	var n := _root("bongo_logs")
	Kit.blob_shadow(n, 0.7, 0.22)
	_cy(n, 0.22, 0.24, 0.6, Palette.WOOD, Vector3(-0.28, 0.3, 0), Vector3.ZERO, 12)
	_cy(n, 0.26, 0.28, 0.75, Palette.WOOD.darkened(0.06), Vector3(0.3, 0.375, 0.05), Vector3.ZERO, 12)
	_cy(n, 0.2, 0.2, 0.05, CREAM, Vector3(-0.28, 0.61, 0), Vector3.ZERO, 12)
	_cy(n, 0.24, 0.24, 0.05, CREAM, Vector3(0.3, 0.76, 0.05), Vector3.ZERO, 12)
	_cy(n, 0.245, 0.255, 0.1, Palette.paint(3), Vector3(-0.28, 0.4, 0), Vector3.ZERO, 12)
	_cy(n, 0.285, 0.295, 0.1, Palette.paint(1), Vector3(0.3, 0.5, 0.05), Vector3.ZERO, 12)
	return _finish(n)


## A hand pump on a stone base, with a long handle and a spout.
static func water_pump() -> Node3D:
	var n := _root("water_pump")
	Kit.blob_shadow(n, 0.5, 0.2)
	_rb(n, Vector3(0.6, 0.2, 0.6), Palette.STONE, Vector3(0, 0.1, 0), 0.08)
	_cy(n, 0.11, 0.14, 0.9, Color("#7fb6d9"), Vector3(0, 0.65, 0), Vector3.ZERO, 10)
	_ball(n, 0.15, Color("#7fb6d9"), Vector3(0, 1.12, 0), Vector3.ONE, 5)
	_rb(n, Vector3(0.12, 0.12, 0.4), Color("#7fb6d9"), Vector3(0, 0.8, 0.28), 0.04)
	_rb(n, Vector3(0.1, 0.1, 0.8), Palette.WOOD_DARK, Vector3(0, 1.3, -0.2), 0.04, Vector3(-18, 0, 0))
	_ball(n, 0.08, Palette.paint(3), Vector3(0, 1.17, 0.18), Vector3.ONE, 4)
	return _finish(n)


## An arch with a shower head and falling drops.
static func shower_arch() -> Node3D:
	var n := _root("shower_arch")
	for x in [-1.1, 1.1]:
		_cy(n, 0.09, 0.11, 2.4, Color("#86c3e6"), Vector3(x, 1.2, 0), Vector3.ZERO, 8)
		_rb(n, Vector3(0.5, 0.1, 0.5), Palette.STONE, Vector3(x, 0.05, 0), 0.04)
	_rb(n, Vector3(2.5, 0.2, 0.24), Color("#86c3e6"), Vector3(0, 2.3, 0), 0.08, Vector3.ZERO, 2)
	_cy(n, 0.3, 0.3, 0.1, CREAM, Vector3(0, 2.15, 0), Vector3.ZERO, 12)
	for i in 5:
		var x: float = (float(i) - 2.0) * 0.12
		var h: float = 0.3 + 0.1 * float(i % 3)
		_rb(n, Vector3(0.07, h, 0.07), Color("#cbe9f5"), Vector3(x, 2.05 - h * 0.5, 0.05 * float(i % 2)), 0.03)
	return _finish(n)


## A table of treats (fruit in a bowl and a loaf), 1.3 x 0.7.
static func treat_table() -> Node3D:
	var n := _root("treat_table")
	Kit.blob_shadow(n, 0.7, 0.2)
	_rb(n, Vector3(1.3, 0.1, 0.7), Palette.WOOD, Vector3(0, 0.7, 0), 0.04)
	_rb(n, Vector3(1.0, 0.04, 0.5), Palette.paint(3), Vector3(0, 0.77, 0), 0.02)
	for x in [-0.55, 0.55]:
		for z in [-0.25, 0.25]:
			_rb(n, Vector3(0.1, 0.66, 0.1), Palette.WOOD_DARK, Vector3(x, 0.33, z), 0.03)
	_cy(n, 0.24, 0.16, 0.14, Palette.WOOD_DARK, Vector3(-0.3, 0.86, 0), Vector3.ZERO, 10)
	_ball(n, 0.1, Color("#e8735f"), Vector3(-0.36, 0.98, 0.03), Vector3.ONE, 4)
	_ball(n, 0.1, Color("#9ccb73"), Vector3(-0.24, 0.98, -0.04), Vector3.ONE, 4)
	_ball(n, 0.1, GOLD, Vector3(-0.3, 1.04, 0.0), Vector3.ONE, 4)
	_rb(n, Vector3(0.36, 0.14, 0.2), Color("#d9a466"), Vector3(0.3, 0.86, 0.0), 0.06)
	return _finish(n)


## A basket of play balls (0.85 m across).
static func ball_basket() -> Node3D:
	var n := _root("ball_basket")
	Kit.blob_shadow(n, 0.45, 0.2)
	_cy(n, 0.42, 0.33, 0.5, Palette.WOOD, Vector3(0, 0.25, 0), Vector3.ZERO, 12)
	_cy(n, 0.44, 0.44, 0.08, Palette.WOOD_DARK, Vector3(0, 0.5, 0), Vector3.ZERO, 12)
	_ball(n, 0.17, Palette.paint(2), Vector3(-0.15, 0.58, 0.05), Vector3.ONE, 5)
	_ball(n, 0.17, Palette.paint(4), Vector3(0.17, 0.6, -0.05), Vector3.ONE, 5)
	_ball(n, 0.17, Palette.paint(1), Vector3(0.0, 0.68, 0.15), Vector3.ONE, 5)
	return _finish(n)


# ------------------------------------------------------------------- signs

## A wooden sign post with a Label3D in the style of the town's portal signs.
static func sign_post(text: String) -> Node3D:
	var n := _root("sign_post")
	Kit.blob_shadow(n, 0.4, 0.2)
	_cy(n, 0.07, 0.09, 1.9, Palette.WOOD_DARK, Vector3(0, 0.95, 0), Vector3.ZERO, 8)
	_rb(n, Vector3(1.5, 0.55, 0.1), CREAM, Vector3(0, 1.85, 0), 0.06)
	_rb(n, Vector3(1.56, 0.08, 0.12), Palette.WOOD, Vector3(0, 2.15, 0), 0.03)
	_rb(n, Vector3(1.56, 0.08, 0.12), Palette.WOOD, Vector3(0, 1.55, 0), 0.03)
	Kit.merge_parts(n)
	var label := Label3D.new()
	label.name = "Label"
	label.text = TranslationServer.translate(text)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var i18n: Node = tree.root.get_node_or_null("I18n")
		if i18n != null and i18n.has_method("ui_font"):
			label.font = i18n.call("ui_font")
	label.font_size = 44
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = Color("#557c5e")
	label.outline_modulate = Color("#fffdf6")
	label.width = 330.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector3(0, 1.85, 0.07)
	n.add_child(label)
	return n


## The plaza map board: habitats as little coloured patches on a framed panel.
static func map_board() -> Node3D:
	var n := _root("map_board")
	Kit.blob_shadow(n, 1.0, 0.22)
	for x in [-0.85, 0.85]:
		_cy(n, 0.08, 0.1, 1.5, Palette.WOOD_DARK, Vector3(x, 0.75, -0.05), Vector3.ZERO, 8)
	_rb(n, Vector3(2.0, 1.3, 0.14), Palette.WOOD, Vector3(0, 1.5, 0), 0.06)
	_rb(n, Vector3(1.8, 1.1, 0.06), CREAM, Vector3(0, 1.5, 0.06), 0.03)
	_rb(n, Vector3(1.7, 0.14, 0.2), Palette.paint(3), Vector3(0, 2.2, 0.0), 0.06)
	# Habitats: three hills across the back, meadow, pool, plaza.
	var spots := [[Vector2(-0.55, 0.3), Vector2(0.45, 0.3), Color("#e8c46a")], [Vector2(0.0, 0.3), Vector2(0.5, 0.3), ROCK],
		[Vector2(0.55, 0.3), Vector2(0.45, 0.3), LEAF], [Vector2(-0.55, -0.15), Vector2(0.45, 0.3), Palette.WATER],
		[Vector2(0.0, -0.15), Vector2(0.5, 0.3), LEAF_LIGHT], [Vector2(0.55, -0.15), Vector2(0.45, 0.3), LEAF_DARK]]
	for s in spots:
		var p: Vector2 = s[0]
		var sz: Vector2 = s[1]
		_rb(n, Vector3(sz.x, sz.y, 0.06), s[2], Vector3(p.x, 1.62 + p.y * 0.8 - 0.1, 0.1), 0.05)
	_rb(n, Vector3(0.9, 0.16, 0.06), Palette.PATH, Vector3(0, 1.15, 0.1), 0.04)
	return _finish(n)


## A lamp post like the town's, without a light node (the zoo adds no lights).
static func lamp() -> Node3D:
	var n := _root("lamp")
	Kit.blob_shadow(n, 0.4, 0.2)
	var frame := Color("#5d6b62")
	_cy(n, 0.2, 0.24, 0.18, frame, Vector3(0, 0.09, 0), Vector3.ZERO, 10)
	_cy(n, 0.06, 0.07, 2.2, frame, Vector3(0, 1.2, 0), Vector3.ZERO, 8)
	_rb(n, Vector3(0.38, 0.08, 0.38), frame, Vector3(0, 2.3, 0), 0.03)
	_rb(n, Vector3(0.3, 0.42, 0.3), Color("#fff3c4"), Vector3(0, 2.55, 0), 0.06)
	_cy(n, 0.03, 0.28, 0.2, frame, Vector3(0, 2.86, 0), Vector3.ZERO, 10)
	_ball(n, 0.06, frame, Vector3(0, 2.98, 0), Vector3.ONE, 4)
	return _finish(n)
