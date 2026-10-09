## Code-built props for the play ideas (design/playability-8-12.md): the snack
## tray and its snacks (F01), the snowman (F04), toy tracks (F02), trail signs
## (F06) and the music box (F08). Same soft primitive style as
## props.gd; a modeled version can replace any of them through the catalog.
extends RefCounted

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")

const UI := preload("res://scripts/ui/ui_kit.gd")

const KINDS := ["snack_tray", "snack_cookie", "snack_juice", "snack_sandwich", "snowman",
	"track_start", "track_straight", "track_curve", "track_switch", "track_bell", "track_finish",
	"trail_sign", "music_box", "track_light",
	"paper_boat", "leaf_pile", "garden_umbrella", "stage_moon", "stage_mountain", "stage_curtain"]
const TRACK_HALF := 0.47
const RAIL := Color("#b9824f")
const CREAM := Color("#fbf3e3")


## c: the item's paint color (the snack's topping, the snowman's scarf, a track's trim);
## variant: the snowman's face, a switch's way, a trail sign's clue; item: the saved
## item for per-item details (a trail sign's number).
static func build(n: Node3D, kind: String, c: Color, variant := 0, item := {}) -> void:
	match kind:
		"track_start", "track_straight", "track_curve", "track_switch", "track_bell", "track_finish", "track_light":
			_track(n, kind, c, variant)
		"paper_boat": _paper_boat(n, c)
		"leaf_pile": _leaf_pile(n, c)
		"garden_umbrella": _garden_umbrella(n, c)
		"stage_moon": _stage_moon(n, c)
		"stage_mountain": _stage_mountain(n, c)
		"stage_curtain": _stage_curtain(n, c)
		"trail_sign": _trail_sign(n, c, int(item.get("num", 1)), variant)
		"music_box": _music_box(n, c)
		"snack_tray": _tray(n, c)
		"snack_cookie": _cookie(n, c)
		"snack_juice": _juice(n, c)
		"snack_sandwich": _sandwich(n, c)
		"snowman": _snowman(n, c, variant)


static func _tray(n: Node3D, c: Color) -> void:
	# A little picnic tray on a stand, with a sign: the snack stand anywhere.
	Kit.box(n, Vector3(0.44, 0.03, 0.32), Palette.WOOD, Vector3(0, 0.2, 0), 0.02)
	for x in [-0.2, 0.2]:
		Kit.box(n, Vector3(0.03, 0.06, 0.32), Palette.WOOD_DARK, Vector3(x, 0.235, 0), 0.01)
	Kit.cyl(n, 0.05, 0.08, 0.19, Palette.WOOD_DARK, Vector3(0, 0.095, 0))
	Kit.box(n, Vector3(0.16, 0.1, 0.02), c.lerp(CREAM, 0.3), Vector3(0.12, 0.3, -0.15), 0.02)   # little sign
	Kit.cyl(n, 0.008, 0.008, 0.1, Palette.WOOD_DARK, Vector3(0.12, 0.24, -0.15))
	Kit.cyl(n, 0.04, 0.035, 0.05, CREAM, Vector3(-0.12, 0.24, 0.05))       # an empty cup
	Kit.cyl(n, 0.07, 0.06, 0.015, CREAM, Vector3(0.0, 0.22, 0.06))         # an empty plate


static func _stand(n: Node3D) -> void:
	# Snacks sit on a small cake stand so they read well at 0.26 m and fit any table.
	Kit.cyl(n, 0.12, 0.12, 0.02, CREAM, Vector3(0, 0.16, 0))
	Kit.cyl(n, 0.025, 0.05, 0.16, CREAM, Vector3(0, 0.08, 0))


static func _cookie(n: Node3D, c: Color) -> void:
	_stand(n)
	for i in 3:
		Kit.cyl(n, 0.065, 0.065, 0.025, Color("#d9a466"), Vector3(-0.03 + i * 0.03, 0.185 + i * 0.026, 0.01 * i))
	for p in [Vector3(-0.01, 0.255, 0.02), Vector3(0.04, 0.255, -0.01), Vector3(0.02, 0.26, 0.04)]:
		Kit.ball(n, 0.014, c, p)


static func _juice(n: Node3D, c: Color) -> void:
	_stand(n)
	Kit.cyl(n, 0.045, 0.038, 0.1, Color(0.95, 0.97, 1.0), Vector3(0, 0.22, 0))
	Kit.cyl(n, 0.04, 0.034, 0.08, c.lerp(Color("#f6b03c"), 0.4), Vector3(0, 0.215, 0))
	Kit.cyl(n, 0.006, 0.006, 0.12, Color("#e9806e"), Vector3(0.015, 0.29, 0.0), Vector3(0, 0, 12))
	Kit.ball(n, 0.018, c, Vector3(-0.035, 0.27, 0))


static func _sandwich(n: Node3D, c: Color) -> void:
	_stand(n)
	Kit.box(n, Vector3(0.14, 0.02, 0.1), Color("#f2d9a6"), Vector3(0, 0.18, 0), 0.01)
	Kit.box(n, Vector3(0.14, 0.012, 0.1), Color("#7fbf5a"), Vector3(0, 0.196, 0), 0.005)
	Kit.box(n, Vector3(0.13, 0.014, 0.09), c, Vector3(0, 0.209, 0), 0.005)
	Kit.box(n, Vector3(0.14, 0.02, 0.1), Color("#f2d9a6"), Vector3(0, 0.226, 0), 0.01)
	Kit.cyl(n, 0.004, 0.004, 0.06, Palette.WOOD, Vector3(0, 0.26, 0))
	Kit.ball(n, 0.012, c, Vector3(0, 0.29, 0))


static func _snowman(n: Node3D, scarf: Color, face: int) -> void:
	Kit.blob_shadow(n, 0.4, 0.18)
	var snow := Color("#f7fbff")
	Kit.ball(n, 0.32, snow, Vector3(0, 0.3, 0))
	Kit.ball(n, 0.24, snow, Vector3(0, 0.76, 0))
	Kit.ball(n, 0.18, snow, Vector3(0, 1.12, 0))
	Kit.part(n, Kit.torus(0.14, 0.2), scarf, Vector3(0, 0.98, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	Kit.box(n, Vector3(0.07, 0.22, 0.04), scarf, Vector3(0.1, 0.86, 0.17), 0.02, Vector3(0, 0, -10))
	Kit.cyl(n, 0.0, 0.03, 0.14, Color("#f08a3c"), Vector3(0, 1.12, 0.22), Vector3(90, 0, 0))   # carrot nose
	for x in [-0.06, 0.06]:
		Kit.ball(n, 0.02, Color("#2b2320"), Vector3(x, 1.18, 0.16))
	match face % 3:
		0:   # smile
			for i in 5:
				var a := deg_to_rad(-40 + i * 20)
				Kit.ball(n, 0.012, Color("#2b2320"), Vector3(sin(a) * 0.08, 1.06 - cos(a) * 0.02 + 0.02 * abs(i - 2), 0.165))
		1:   # surprised "o"
			Kit.part(n, Kit.torus(0.02, 0.032), Color("#2b2320"), Vector3(0, 1.05, 0.17), Vector3(90, 0, 0))
		2:   # wink and grin
			Kit.box(n, Vector3(0.05, 0.01, 0.01), Color("#2b2320"), Vector3(0.06, 1.18, 0.165), 0.004)
			Kit.box(n, Vector3(0.1, 0.014, 0.01), Color("#2b2320"), Vector3(0, 1.05, 0.17), 0.006, Vector3(0, 0, 8))
	for s in [-1, 1]:   # twig arms
		Kit.cyl(n, 0.012, 0.016, 0.36, Color("#7a5a3a"), Vector3(s * 0.36, 0.86, 0), Vector3(0, 0, s * -60))
	for y in [0.62, 0.76, 0.9]:
		Kit.ball(n, 0.022, Color("#2b2320"), Vector3(0, y, 0.235 if y < 0.8 else 0.21))


# ------------------------------------------------------------- toy tracks (F02)
# Each piece is one 1 m cell. Local +z is "front"; a curve turns from the back
# edge to the local +x edge (the same ports as core/track_rules.gd).

static func _track(n: Node3D, kind: String, c: Color, variant: int) -> void:
	Kit.box(n, Vector3(0.94, 0.05, 0.94), Palette.WOOD, Vector3(0, 0.025, 0), 0.04)
	Kit.box(n, Vector3(0.9, 0.012, 0.9), c.lerp(Palette.WOOD, 0.55), Vector3(0, 0.056, 0), 0.03)
	match kind:
		"track_straight", "track_bell", "track_start", "track_light":
			_rails_straight(n)
		"track_curve":
			_rails_curve(n)
		"track_switch":
			_rails_straight(n)
			_rails_curve(n)
			# A flag points to the way the ball will go: front, or to the side.
			var flag := Vector3(0.0, 0.0, 0.28) if variant % 2 == 0 else Vector3(0.28, 0.0, 0.0)
			Kit.cyl(n, 0.015, 0.015, 0.3, Palette.WOOD_DARK, Vector3(-0.32, 0.2, -0.32))
			Kit.ball(n, 0.06, c, Vector3(-0.32, 0.36, -0.32))
			Kit.cyl(n, 0.0, 0.07, 0.14, c, Vector3(flag.x * 0.9, 0.12, flag.z * 0.9), Vector3(90, 0, 0) if variant % 2 == 0 else Vector3(0, 0, -90))
		"track_finish":
			# A friendly toy face with an open mouth catches the ball.
			Kit.cyl(n, 0.3, 0.32, 0.22, c, Vector3(0, 0.16, 0))
			Kit.cyl(n, 0.2, 0.2, 0.05, Color("#9a3f3a"), Vector3(0, 0.255, 0))
			for x in [-0.12, 0.12]:
				Kit.ball(n, 0.05, Color("#fdf8ef"), Vector3(x, 0.33, -0.22))
				Kit.ball(n, 0.025, Color("#2b2320"), Vector3(x, 0.34, -0.18))
	if kind == "track_bell":
		for x in [-0.3, 0.3]:
			Kit.cyl(n, 0.02, 0.02, 0.42, Palette.WOOD_DARK, Vector3(x, 0.25, 0))
		Kit.box(n, Vector3(0.66, 0.04, 0.05), Palette.WOOD_DARK, Vector3(0, 0.46, 0), 0.015)
		Kit.cyl(n, 0.03, 0.08, 0.11, Color("#f2c75c"), Vector3(0, 0.38, 0))
	if kind == "track_light":
		# A little signal lamp that lights up as the ball passes (node "Lamp").
		Kit.cyl(n, 0.02, 0.025, 0.34, Palette.WOOD_DARK, Vector3(0.34, 0.2, 0.0))
		var lamp := Kit.ball(n, 0.07, Color("#fff1b8"), Vector3(0.34, 0.4, 0.0))
		lamp.material_override = Kit.mat(Color("#fff1b8"), 0.6, Color("#ffd27a"))
		lamp.name = "Lamp"
	if kind == "track_start":
		# A little tower at the back where the ball waits.
		Kit.box(n, Vector3(0.36, 0.3, 0.26), c, Vector3(0, 0.2, -0.3), 0.05)
		Kit.box(n, Vector3(0.28, 0.04, 0.4), Palette.WOOD_DARK, Vector3(0, 0.25, -0.05), 0.02, Vector3(-20, 0, 0))
		Kit.ball(n, 0.07, Color("#e9806e"), Vector3(0, 0.42, -0.3))


static func _rails_straight(n: Node3D) -> void:
	for x in [-0.12, 0.12]:
		Kit.box(n, Vector3(0.04, 0.05, 0.94), RAIL, Vector3(x, 0.085, 0), 0.015)


static func _rails_curve(n: Node3D) -> void:
	# Quarter circles around the back/+x corner, from the back edge to the +x edge.
	var corner := Vector2(TRACK_HALF, -TRACK_HALF)
	for r in [TRACK_HALF - 0.12, TRACK_HALF + 0.12]:
		for i in 6:
			var a := (i + 0.5) / 6.0 * PI * 0.5
			var p: Vector2 = corner + Vector2(-cos(a), sin(a)) * r
			var seg: float = r * PI * 0.5 / 6.0 + 0.02
			Kit.box(n, Vector3(0.04, 0.05, seg), RAIL, Vector3(p.x, 0.085, p.y), 0.015, Vector3(0, rad_to_deg(-a), 0))


# ------------------------------------------------------------- trail signs (F06)

static func _trail_sign(n: Node3D, c: Color, num: int, clue: int) -> void:
	Kit.blob_shadow(n, 0.3, 0.2)
	Kit.cyl(n, 0.045, 0.055, 0.8, Palette.WOOD_DARK, Vector3(0, 0.4, 0))
	Kit.cyl(n, 0.24, 0.24, 0.06, c, Vector3(0, 0.95, 0), Vector3(90, 0, 0))
	Kit.cyl(n, 0.2, 0.2, 0.065, Color("#fdf8ef"), Vector3(0, 0.95, 0), Vector3(90, 0, 0))
	Kit.box(n, Vector3(0.22, 0.12, 0.04), c, Vector3(0.0, 0.62, 0.05), 0.03)   # little arrow board
	Kit.cyl(n, 0.0, 0.07, 0.1, c, Vector3(0.15, 0.62, 0.05), Vector3(0, 0, -90))
	var label := Label3D.new()
	label.text = str(num)
	label.font_size = 96
	label.pixel_size = 0.0028
	label.modulate = Color("#344d40")
	label.outline_size = 0
	label.position = Vector3(-0.07, 0.95, 0.036)
	n.add_child(label)
	var back := label.duplicate() as Label3D
	back.position = Vector3(0.07, 0.95, -0.036)
	back.rotation.y = PI
	n.add_child(back)
	var icon := Sprite3D.new()
	icon.texture = UI.icon(["wave", "cheer", "dance", "heart"][posmod(clue, 4)], 64)
	icon.pixel_size = 0.0028
	icon.position = Vector3(0.08, 0.95, 0.036)
	n.add_child(icon)


# ------------------------------------------------------------- music box (F08)

## A little garden band stand: bell, drum, chimes and a bass mushroom on a
## wooden cart, with four lamps that glow on the beat (node "Beat").
static func _music_box(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.45, 0.2)
	Kit.box(n, Vector3(0.78, 0.12, 0.48), Palette.WOOD, Vector3(0, 0.22, 0), 0.04)
	for x in [-0.32, 0.32]:
		for z in [-0.18, 0.18]:
			Kit.cyl(n, 0.03, 0.035, 0.16, Palette.WOOD_DARK, Vector3(x, 0.08, z))
	Kit.box(n, Vector3(0.8, 0.04, 0.5), c, Vector3(0, 0.3, 0), 0.02)
	# Bell on a little frame.
	Kit.cyl(n, 0.012, 0.012, 0.32, Palette.WOOD_DARK, Vector3(-0.3, 0.46, -0.1))
	Kit.cyl(n, 0.03, 0.075, 0.1, Color("#f2c75c"), Vector3(-0.3, 0.58, -0.1))
	# Drum.
	Kit.cyl(n, 0.1, 0.1, 0.14, Palette.paint(2), Vector3(-0.08, 0.39, 0.06))
	Kit.cyl(n, 0.102, 0.102, 0.02, Color("#fdf8ef"), Vector3(-0.08, 0.465, 0.06))
	# Chimes.
	Kit.box(n, Vector3(0.22, 0.03, 0.03), Palette.WOOD_DARK, Vector3(0.14, 0.72, -0.12), 0.01)
	for i in 3:
		Kit.cyl(n, 0.012, 0.012, 0.22 - i * 0.04, Color("#cfd8e3"), Vector3(0.07 + i * 0.07, 0.6 + i * 0.02, -0.12))
	for x in [0.04, 0.24]:
		Kit.cyl(n, 0.01, 0.01, 0.42, Palette.WOOD_DARK, Vector3(x, 0.5, -0.12))
	# Bass mushroom.
	Kit.cyl(n, 0.05, 0.06, 0.16, Color("#fdf8ef"), Vector3(0.28, 0.4, 0.1))
	Kit.ball(n, 0.12, Palette.paint(5), Vector3(0.28, 0.5, 0.1), Vector3(1, 0.55, 1))
	var beat := Node3D.new()
	beat.name = "Beat"
	n.add_child(beat)
	for i in 4:
		var glow := Kit.ball(beat, 0.035, Color("#fff1b8"), Vector3(-0.3 + i * 0.2, 0.33, 0.25))
		glow.material_override = Kit.mat(Color("#fff1b8"), 0.6, Color("#ffd27a"))


# ------------------------------------------------------------- weather toys (F04, r11)

## A folded paper boat on a little wooden stand (it sails on a pond nearby).
static func _paper_boat(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.2, 0.15)
	Kit.box(n, Vector3(0.3, 0.04, 0.16), Palette.WOOD, Vector3(0, 0.02, 0), 0.015)
	var boat := Node3D.new()
	boat.name = "Boat"
	n.add_child(boat)
	var paper := c.lerp(Color.WHITE, 0.55)
	Kit.box(boat, Vector3(0.36, 0.05, 0.12), paper, Vector3(0, 0.07, 0), 0.02)
	for s in [-1, 1]:
		Kit.box(boat, Vector3(0.12, 0.05, 0.1), paper, Vector3(s * 0.2, 0.1, 0), 0.02, Vector3(0, 0, s * -35))
	Kit.part(boat, Kit.cylinder(0.0, 0.1, 0.16, 3), paper.darkened(0.05), Vector3(0, 0.18, 0), Vector3(0, 90, 0), Vector3(1, 1, 0.25))


## A heap of autumn leaves to jump into (any weather; the color is the leaf mix).
static func _leaf_pile(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.6, 0.15)
	var tones := [Color("#e9934b"), Color("#d96a3c"), Color("#f2c75c"), c.lerp(Color("#e9934b"), 0.5)]
	Kit.ball(n, 0.5, tones[0], Vector3(0, 0.12, 0), Vector3(1.15, 0.45, 1.0))
	for i in 9:
		var a := TAU * i / 9.0
		Kit.ball(n, 0.16, tones[i % tones.size()], Vector3(cos(a) * 0.32, 0.2 + (i % 3) * 0.04, sin(a) * 0.27), Vector3(1, 0.4, 1))
	Kit.ball(n, 0.2, tones[2], Vector3(0.05, 0.3, 0.02), Vector3(1, 0.5, 1))


## A big garden umbrella: shade for a snack stand or a rainy-day corner.
static func _garden_umbrella(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.5, 0.15)
	Kit.cyl(n, 0.16, 0.2, 0.08, Palette.STONE, Vector3(0, 0.04, 0))
	Kit.cyl(n, 0.025, 0.025, 1.9, Color("#fdf8ef"), Vector3(0, 0.95, 0))
	Kit.part(n, Kit.cylinder(0.04, 1.0, 0.36, 8), c, Vector3(0, 1.98, 0))
	Kit.part(n, Kit.cylinder(1.0, 1.02, 0.06, 8), c.lerp(Color.WHITE, 0.5), Vector3(0, 1.78, 0))
	Kit.ball(n, 0.05, c.darkened(0.2), Vector3(0, 2.18, 0))


# ------------------------------------------------------------- stage pieces (F05, r11)
# Cardboard cutouts on little wooden feet turn any room or lawn into a stage.

static func _cutout_feet(n: Node3D, w: float) -> void:
	for x in [-w * 0.35, w * 0.35]:
		Kit.box(n, Vector3(0.08, 0.06, 0.28), Palette.WOOD_DARK, Vector3(x, 0.03, 0.04), 0.02)


static func _stage_moon(n: Node3D, c: Color) -> void:
	_cutout_feet(n, 0.6)
	var card := Color("#f2c75c").lerp(c, 0.2)
	Kit.cyl(n, 0.3, 0.3, 0.03, card, Vector3(0, 0.62, 0), Vector3(90, 0, 0))
	Kit.cyl(n, 0.25, 0.25, 0.04, Palette.paint(4).lerp(Color("#3a4a6b"), 0.5), Vector3(0.14, 0.68, 0.0), Vector3(90, 0, 0))   # night sky bite
	Kit.box(n, Vector3(0.04, 0.34, 0.04), Palette.WOOD_DARK, Vector3(0, 0.2, -0.03), 0.01)
	for p in [Vector3(-0.2, 1.0, 0.0), Vector3(0.24, 1.02, 0.0)]:
		Kit.ball(n, 0.035, Color("#fff1b8"), p)


static func _stage_mountain(n: Node3D, c: Color) -> void:
	_cutout_feet(n, 1.0)
	# Upright cones squashed front to back read as flat cardboard peaks.
	Kit.part(n, Kit.cylinder(0.0, 0.5, 0.9, 16), c.lerp(Color("#8fae8a"), 0.6), Vector3(-0.15, 0.45, 0), Vector3.ZERO, Vector3(1, 1, 0.08))
	Kit.part(n, Kit.cylinder(0.0, 0.36, 0.66, 16), c.lerp(Color("#7a9a76"), 0.5), Vector3(0.28, 0.33, 0.03), Vector3.ZERO, Vector3(1, 1, 0.08))
	Kit.part(n, Kit.cylinder(0.0, 0.11, 0.2, 16), Color("#fdf8ef"), Vector3(-0.15, 0.8, 0.03), Vector3.ZERO, Vector3(1, 1, 0.08))


static func _stage_curtain(n: Node3D, c: Color) -> void:
	_cutout_feet(n, 1.2)
	for x in [-0.6, 0.6]:
		Kit.cyl(n, 0.025, 0.025, 1.5, Palette.WOOD_DARK, Vector3(x, 0.75, -0.05))
	Kit.box(n, Vector3(1.3, 0.06, 0.06), Palette.WOOD_DARK, Vector3(0, 1.5, -0.05), 0.02)
	for s in [-1, 1]:
		for i in 3:
			Kit.cyl(n, 0.07, 0.09, 1.36, c, Vector3(s * (0.52 - i * 0.11), 0.8, -0.02 + (i % 2) * 0.03))
	Kit.box(n, Vector3(1.24, 0.14, 0.05), c.darkened(0.15), Vector3(0, 1.4, 0.0), 0.03)
