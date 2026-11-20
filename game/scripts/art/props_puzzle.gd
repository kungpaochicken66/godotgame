## Code-built props for puzzle rooms and rideable carts
## (design/puzzle-rooms-and-rides.md), in the same soft primitive style as
## props.gd, props_play.gd and props_contraption.gd. No model, texture or sound
## file is used.
##
## Named parts the world animates:
##   puzzle_chest   "Lid" (hinged at the back, opens upward), "Treasure" (shown when open),
##                  "Lights" (where world/puzzle_world.gd puts one light per key and dial)
##   puzzle_key     "Key" (hidden once it is found)
##   puzzle_dial    "Pictures" with "Pic0".."Pic3" (one shown at a time), "Knob"
##   ride_station   "Cart" (moved along the rails by world/ride_world.gd) with "Seat0" and "Wheels"
extends RefCounted

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")

const KINDS := ["puzzle_chest", "puzzle_key", "puzzle_dial", "puzzle_clue_circle", "puzzle_clue_square",
	"puzzle_clue_triangle", "puzzle_clue_flower", "ride_station", "ride_straight", "ride_curve", "ride_signal", "weather_bell", "picture_board"]
const CLUE_KINDS := ["puzzle_clue_circle", "puzzle_clue_square", "puzzle_clue_triangle", "puzzle_clue_flower"]
const CREAM := Color("#fbf3e3")
const INK := Color("#3d5a50")
const GOLD := Color("#f2c75c")
const RAIL := Color("#8d8f96")
## Rail gauge (between the two rails' middles) and cell size, as in core/ride_rules.gd.
const GAUGE := 0.6
const CELL := 2.0


static func build(n: Node3D, kind: String, c: Color, color_index: int, item := {}) -> void:
	match kind:
		"picture_board": _board(n, c, str(item.get("pix", "")))
		"puzzle_chest": _chest(n, c)
		"puzzle_key": _key(n, c)
		"puzzle_dial": _dial(n, c, color_index)
		"ride_station": _station(n, c)
		"ride_straight": _straight(n)
		"ride_curve": _curve(n)
		"ride_signal": _signal(n, c)
		"weather_bell": _weather_bell(n, c)
		_:
			if CLUE_KINDS.has(kind):
				_clue(n, c, color_index, CLUE_KINDS.find(kind))


static func _marker(n: Node3D, name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	n.add_child(p)
	return p


## One of the four pictures, flat, facing +z, about `size` across. Told apart by
## shape alone (never by color): a circle, a square, a triangle and a flower.
static func picture(parent: Node3D, index: int, size: float, ink := INK) -> void:
	match posmod(index, 4):
		0:
			Kit.part(parent, Kit.cylinder(size * 0.42, size * 0.42, 0.014, 28), ink, Vector3.ZERO, Vector3(90, 0, 0))
		1:
			Kit.box(parent, Vector3(size * 0.74, size * 0.74, 0.014), ink, Vector3.ZERO, 0.005)
		2:
			Kit.part(parent, Kit.cylinder(size * 0.5, size * 0.5, 0.014, 3), ink, Vector3(0, -size * 0.09, 0), Vector3(-90, 0, 0))
		3:
			for i in 5:
				var a := TAU * i / 5.0
				Kit.part(parent, Kit.cylinder(size * 0.17, size * 0.17, 0.014, 16), ink,
					Vector3(sin(a), cos(a), 0) * size * 0.27, Vector3(90, 0, 0))
			Kit.part(parent, Kit.cylinder(size * 0.11, size * 0.11, 0.018, 16), ink.lerp(Color.WHITE, 0.55), Vector3.ZERO, Vector3(90, 0, 0))


## Small dots that say which color a card or dial is without relying on color:
## color index + 1 of them (1 to 8), in a row along the top.
static func _pips(parent: Node3D, color_index: int, width: float, at: Vector3) -> void:
	var count := clampi(color_index, 0, Palette.PAINT.size() - 1) + 1
	var step := minf(0.056, width / float(count))
	var radius := minf(0.02, step * 0.42)   # as large as fits without touching (1.3 cm at first: hard to count)
	for i in count:
		Kit.ball(parent, radius, INK, at + Vector3((i - (count - 1) * 0.5) * step, 0, 0))


## A wooden treasure chest; the lid is the paint color.
static func _chest(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.55, 0.2)
	Kit.box(n, Vector3(0.8, 0.34, 0.5), Palette.WOOD, Vector3(0, 0.17, 0), 0.04)
	for x in [-0.3, 0.3]:
		Kit.box(n, Vector3(0.07, 0.35, 0.52), Palette.WOOD_DARK, Vector3(x, 0.17, 0), 0.02)
	var lights := _marker(n, "Lights", Vector3(0, 0.25, 0.262))
	lights.set_meta("width", 0.5)
	# What is inside, seen when the lid is up: gold and two gems.
	var treasure := _marker(n, "Treasure", Vector3(0, 0.33, 0))
	Kit.ball(treasure, 0.2, GOLD, Vector3(0, -0.02, 0), Vector3(1.5, 0.45, 1.0))
	Kit.ball(treasure, 0.06, Color("#ec8fa3"), Vector3(-0.15, 0.06, 0.05), Vector3(1, 1.2, 1))
	Kit.ball(treasure, 0.06, Color("#86c3e6"), Vector3(0.14, 0.06, -0.04), Vector3(1, 1.2, 1))
	Kit.part(treasure, Kit.cylinder(0.0, 0.07, 0.11, 5), GOLD.lightened(0.3), Vector3(0, 0.12, 0))
	treasure.visible = false
	var lid := _marker(n, "Lid", Vector3(0, 0.34, -0.25))
	Kit.box(lid, Vector3(0.8, 0.2, 0.5), c, Vector3(0, 0.1, 0.25), 0.09)
	for x in [-0.3, 0.3]:
		Kit.box(lid, Vector3(0.07, 0.215, 0.52), Palette.WOOD_DARK, Vector3(x, 0.1, 0.25), 0.02)
	Kit.box(lid, Vector3(0.12, 0.13, 0.04), GOLD, Vector3(0, 0.03, 0.51), 0.015)   # the lock plate
	Kit.ball(lid, 0.02, INK, Vector3(0, 0.02, 0.532))


## A golden key standing on a little cushion in the paint color.
static func _key(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.16, 0.16)
	Kit.cyl(n, 0.085, 0.1, 0.05, c, Vector3(0, 0.025, 0))
	var key := _marker(n, "Key", Vector3(0, 0.05, 0))
	Kit.part(key, Kit.torus(0.028, 0.06), GOLD, Vector3(0, 0.19, 0), Vector3(90, 0, 0))
	Kit.box(key, Vector3(0.03, 0.15, 0.03), GOLD, Vector3(0, 0.075, 0), 0.01)
	Kit.box(key, Vector3(0.05, 0.022, 0.026), GOLD, Vector3(0.035, 0.03, 0), 0.006)
	Kit.box(key, Vector3(0.04, 0.022, 0.026), GOLD, Vector3(0.03, 0.07, 0), 0.006)


## A post with a picture board and a knob: each turn shows the next picture.
## The board's frame is the paint color; the dots on top repeat it by count.
static func _dial(n: Node3D, c: Color, color_index: int) -> void:
	Kit.blob_shadow(n, 0.3, 0.18)
	Kit.cyl(n, 0.17, 0.2, 0.06, Palette.STONE, Vector3(0, 0.03, 0))
	Kit.cyl(n, 0.035, 0.04, 0.58, Palette.WOOD_DARK, Vector3(0, 0.34, 0))
	Kit.box(n, Vector3(0.44, 0.42, 0.07), c, Vector3(0, 0.78, 0), 0.03)
	Kit.box(n, Vector3(0.34, 0.31, 0.02), CREAM, Vector3(0, 0.765, 0.034), 0.008)
	_pips(n, color_index, 0.36, Vector3(0, 0.955, 0.036))
	var knob := _marker(n, "Knob", Vector3(0.245, 0.78, 0))
	Kit.cyl(knob, 0.03, 0.03, 0.05, Palette.WOOD_DARK, Vector3(0, 0, 0), Vector3(0, 0, 90))
	Kit.ball(knob, 0.045, GOLD, Vector3(0.035, 0, 0))
	var pics := _marker(n, "Pictures", Vector3(0, 0.765, 0.05))
	for i in 4:
		var p := _marker(pics, "Pic%d" % i, Vector3.ZERO)
		picture(p, i, 0.3)
		p.visible = i == 0


## A small card on an easel showing one picture. Its frame is the paint color.
static func _clue(n: Node3D, c: Color, color_index: int, pic: int) -> void:
	Kit.blob_shadow(n, 0.2, 0.15)
	var card := _marker(n, "Card", Vector3(0, 0.2, 0.0))
	card.rotation_degrees.x = -12.0
	Kit.box(card, Vector3(0.32, 0.36, 0.03), c, Vector3.ZERO, 0.012)
	Kit.box(card, Vector3(0.26, 0.26, 0.012), CREAM, Vector3(0, -0.02, 0.016), 0.005)
	_pips(card, color_index, 0.26, Vector3(0, 0.145, 0.018))
	var art := _marker(card, "Picture", Vector3(0, -0.02, 0.026))
	picture(art, pic, 0.24)
	Kit.box(n, Vector3(0.03, 0.3, 0.03), Palette.WOOD_DARK, Vector3(0, 0.14, -0.075), 0.008, Vector3(18, 0, 0))   # the easel's leg


# ------------------------------------------------------------- ride rails

static func _sleeper(n: Node3D, pos: Vector3, yaw_deg: float) -> void:
	Kit.box(n, Vector3(GAUGE + 0.2, 0.04, 0.14), Palette.WOOD_DARK, pos, 0.012, Vector3(0, yaw_deg, 0))


## Two rails on wooden sleepers, front (+z) to back, the full length of a 2 m cell.
static func _straight(n: Node3D) -> void:
	for x in [-GAUGE * 0.5, GAUGE * 0.5]:
		Kit.box(n, Vector3(0.07, 0.05, CELL), RAIL, Vector3(x, 0.065, 0), 0.015)
	for i in 5:
		_sleeper(n, Vector3(0, 0.02, -0.8 + i * 0.4), 0.0)


## A quarter circle from the back (-z) to the local +x side, 1 m radius.
static func _curve(n: Node3D) -> void:
	var pivot := Vector3(CELL * 0.5, 0, -CELL * 0.5)
	var steps := 8
	for side in [-0.5, 0.5]:
		var r: float = CELL * 0.5 + GAUGE * side
		for i in steps:
			var a := (i + 0.5) / steps * PI * 0.5   # 0 at the back port, a quarter turn at the side port
			var p: Vector3 = pivot + Vector3(-cos(a), 0, sin(a)) * r
			var seg: float = r * PI * 0.5 / steps + 0.03
			Kit.box(n, Vector3(0.07, 0.05, seg), RAIL, Vector3(p.x, 0.065, p.z), 0.015, Vector3(0, rad_to_deg(a), 0))
	for i in 4:
		var a := (i + 0.5) / 4.0 * PI * 0.5
		var p := pivot + Vector3(-cos(a), 0, sin(a)) * CELL * 0.5
		_sleeper(n, Vector3(p.x, 0.02, p.z), rad_to_deg(a))


## An easel with an 8 x 8 picture: each painted square is a small tile in its paint color.
## The frame is the board's own paint color. An empty board shows its cream ground.
static func _board(n: Node3D, c: Color, pix: String) -> void:
	Kit.blob_shadow(n, 0.5, 0.18)
	for x in [-0.36, 0.36]:
		Kit.box(n, Vector3(0.05, 1.2, 0.05), Palette.WOOD_DARK, Vector3(x, 0.6, -0.02), 0.012, Vector3(-9, 0, 0))
	Kit.box(n, Vector3(0.05, 1.05, 0.05), Palette.WOOD_DARK, Vector3(0, 0.5, -0.2), 0.012, Vector3(16, 0, 0))
	var face := _marker(n, "Face", Vector3(0, 0.78, 0.06))
	face.rotation_degrees.x = -9.0
	Kit.box(face, Vector3(0.96, 0.96, 0.05), c, Vector3.ZERO, 0.02)
	Kit.box(face, Vector3(0.86, 0.86, 0.02), CREAM, Vector3(0, 0, 0.022), 0.006)
	var cells := _marker(face, "Cells", Vector3(0, 0, 0.036))
	var step := 0.86 / 8.0
	for i in mini(pix.length(), 64):
		var d := pix.unicode_at(i) - 48
		if d < 1 or d > Palette.PAINT.size():
			continue
		# Square 0 is the top left, as in the card.
		Kit.box(cells, Vector3(step * 0.94, step * 0.94, 0.012), Palette.paint(d - 1),
			Vector3((i % 8 - 3.5) * step, (3.5 - (i >> 3)) * step, 0), 0.004)


## A straight rail with a signal post beside it: a disc in the paint color on a swinging arm ("Swing").
## A cart riding over it sets off what stands near (a contraption trigger).
static func _signal(n: Node3D, c: Color) -> void:
	_straight(n)
	Kit.cyl(n, 0.11, 0.13, 0.06, Palette.STONE, Vector3(-0.72, 0.03, 0))
	Kit.cyl(n, 0.03, 0.035, 0.95, Palette.WOOD_DARK, Vector3(-0.72, 0.5, 0))
	var arm := _marker(n, "Swing", Vector3(-0.72, 0.95, 0))
	Kit.box(arm, Vector3(0.36, 0.05, 0.05), Palette.WOOD_DARK, Vector3(0.14, 0, 0), 0.015)
	Kit.part(arm, Kit.cylinder(0.14, 0.14, 0.04, 20), c, Vector3(0.3, 0, 0), Vector3(90, 0, 0))
	Kit.part(arm, Kit.cylinder(0.07, 0.07, 0.05, 16), CREAM, Vector3(0.3, 0, 0), Vector3(90, 0, 0))
	Kit.ball(n, 0.05, GOLD, Vector3(-0.72, 1.02, 0))


## A post with three chimes hanging from a little roof in the paint color ("Swing" holds the chimes).
## It rings whenever the weather changes, and sets off what stands near (a contraption trigger).
static func _weather_bell(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.28, 0.16)
	Kit.cyl(n, 0.13, 0.16, 0.06, Palette.STONE, Vector3(0, 0.03, 0))
	Kit.cyl(n, 0.03, 0.035, 1.1, Palette.WOOD_DARK, Vector3(0, 0.6, 0))
	Kit.part(n, Kit.cylinder(0.0, 0.25, 0.14, 4), c, Vector3(0, 1.22, 0), Vector3(0, 45, 0))
	Kit.box(n, Vector3(0.46, 0.03, 0.05), Palette.WOOD_DARK, Vector3(0, 1.13, 0), 0.01)
	var chimes := _marker(n, "Swing", Vector3(0, 1.12, 0))
	for i in 3:
		var x := (i - 1) * 0.15
		Kit.cyl(chimes, 0.022, 0.022, 0.22 + i * 0.05, GOLD, Vector3(x, -0.15 - i * 0.025, 0.06))


## Rails with a little platform and a flag in the paint color, and the cart waiting on them.
static func _station(n: Node3D, c: Color) -> void:
	_straight(n)
	Kit.box(n, Vector3(0.42, 0.1, 1.5), Palette.WOOD, Vector3(-0.74, 0.05, 0), 0.03)
	Kit.cyl(n, 0.03, 0.035, 1.05, Palette.WOOD_DARK, Vector3(-0.82, 0.6, -0.6))
	Kit.box(n, Vector3(0.3, 0.2, 0.025), c, Vector3(-0.66, 1.0, -0.6), 0.01)
	Kit.ball(n, 0.045, GOLD, Vector3(-0.82, 1.14, -0.6))
	var cart := _marker(n, "Cart", Vector3.ZERO)
	build_cart(cart, c)
	var trailer := _marker(n, "Trailer", Vector3(0, 0, -1.4))   # net/animals.gd TRAILER_GAP
	build_trailer(trailer, c)


## The trailer behind the cart: a low open wagon for one animal friend ("Pet0" is where it sits).
## A flatbed 0.84 m wide and 0.95 m long, its floor 0.24 m up, with a low rim (8 cm) instead of sides:
## the animals that ride are up to about a meter across, so their wool or fur may hang over the rim
## rather than poke through a wall (Mac review of town-play r1: the first trailer was a small box that
## the sheep stood in and through).
static func build_trailer(t: Node3D, c: Color) -> void:
	var dark := c.darkened(0.18)
	Kit.box(t, Vector3(0.84, 0.07, 0.95), dark, Vector3(0, 0.2, 0), 0.025)
	for x in [-0.4, 0.4]:
		Kit.box(t, Vector3(0.05, 0.08, 0.95), c, Vector3(x, 0.275, 0), 0.02)
	Kit.box(t, Vector3(0.84, 0.08, 0.05), c, Vector3(0, 0.275, -0.45), 0.02)
	Kit.box(t, Vector3(0.84, 0.08, 0.05), c, Vector3(0, 0.275, 0.45), 0.02)
	Kit.box(t, Vector3(0.05, 0.05, 0.36), Palette.WOOD_DARK, Vector3(0, 0.2, 0.65), 0.012)   # the drawbar to the cart
	for x in [-GAUGE * 0.5, GAUGE * 0.5]:
		for z in [-0.28, 0.28]:
			Kit.cyl(t, 0.09, 0.09, 0.06, Palette.WOOD_DARK, Vector3(x, 0.18, z), Vector3(0, 0, 90))
	var seat := Marker3D.new()
	seat.name = "Pet0"
	seat.position = Vector3(0, 0.24, 0)
	t.add_child(seat)


## The cart: a tub in the paint color on four wheels, open at the top, with a seat.
## It faces +z (the way it rides). 0.8 m wide, 1.1 m long, sides 0.52 m high.
static func build_cart(cart: Node3D, c: Color) -> void:
	var dark := c.darkened(0.18)
	Kit.box(cart, Vector3(0.74, 0.08, 1.06), dark, Vector3(0, 0.2, 0), 0.03)                 # the floor
	for x in [-0.36, 0.36]:
		Kit.box(cart, Vector3(0.07, 0.3, 1.1), c, Vector3(x, 0.37, 0), 0.03)                # the sides
	Kit.box(cart, Vector3(0.78, 0.3, 0.07), c, Vector3(0, 0.37, -0.52), 0.03)               # the back
	Kit.box(cart, Vector3(0.78, 0.24, 0.07), c, Vector3(0, 0.34, 0.52), 0.03)               # the front, a little lower
	Kit.box(cart, Vector3(0.6, 0.06, 0.3), CREAM, Vector3(0, 0.36, -0.2), 0.025)            # the seat
	Kit.box(cart, Vector3(0.6, 0.22, 0.05), CREAM, Vector3(0, 0.46, -0.44), 0.02)           # its back rest
	Kit.cyl(cart, 0.02, 0.02, 0.56, Palette.WOOD_DARK, Vector3(0, 0.5, 0.36), Vector3(0, 0, 90))   # the bar to hold
	Kit.ball(cart, 0.05, GOLD, Vector3(0, 0.4, 0.58))                                       # the lamp
	var wheels := _marker(cart, "Wheels", Vector3.ZERO)
	for x in [-GAUGE * 0.5, GAUGE * 0.5]:
		for z in [-0.34, 0.34]:
			Kit.cyl(wheels, 0.11, 0.11, 0.07, Palette.WOOD_DARK, Vector3(x, 0.2, z), Vector3(0, 0, 90))
	var seat := Marker3D.new()
	seat.name = "Seat0"
	seat.position = Vector3(0, 0.42, -0.18)
	cart.add_child(seat)
