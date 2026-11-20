## Code-built props for contraptions (design/contraptions-and-town-life.md): the
## big button and the step pad that set things off, and the pinwheel and bubble
## machine that answer. Same soft primitive style as props.gd and props_play.gd.
##
## Named parts the world animates (world/contraption_world.gd):
##   "Cap"    the button's dome, pressed down for a moment
##   "Pad"    the step pad's top, pressed down for a moment
##   "Wheel"  the pinwheel's sails, turning about local z
##   "Nozzle" where the bubble machine's bubbles come out
extends RefCounted

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")

const KINDS := ["push_button", "step_pad", "pinwheel", "bubble_machine"]
const CREAM := Color("#fbf3e3")


static func build(n: Node3D, kind: String, c: Color) -> void:
	match kind:
		"push_button": _button(n, c)
		"step_pad": _pad(n, c)
		"pinwheel": _pinwheel(n, c)
		"bubble_machine": _bubbles(n, c)


static func _pivot(n: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	n.add_child(p)
	return p


## A big, friendly button on a little wooden box: the dome is the paint color.
static func _button(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.34, 0.18)
	Kit.box(n, Vector3(0.44, 0.16, 0.44), Palette.WOOD, Vector3(0, 0.08, 0), 0.05)
	Kit.cyl(n, 0.17, 0.18, 0.04, CREAM, Vector3(0, 0.18, 0))
	var cap := _pivot(n, Vector3(0, 0.2, 0))
	cap.name = "Cap"
	Kit.ball(cap, 0.15, c, Vector3(0, 0.0, 0), Vector3(1, 0.72, 1))
	Kit.ball(cap, 0.04, c.lerp(Color.WHITE, 0.6), Vector3(-0.05, 0.075, 0.04), Vector3(1, 0.5, 1))   # a soft highlight


## A flat, springy pad with two footprints: stepping on it sets things off.
static func _pad(n: Node3D, c: Color) -> void:
	Kit.box(n, Vector3(0.84, 0.03, 0.84), Palette.WOOD, Vector3(0, 0.015, 0), 0.012)
	var top := _pivot(n, Vector3(0, 0.03, 0))
	top.name = "Pad"
	Kit.box(top, Vector3(0.74, 0.03, 0.74), c, Vector3(0, 0.015, 0), 0.012)
	for x in [-0.14, 0.14]:
		Kit.ball(top, 0.085, CREAM, Vector3(x, 0.03, 0.03), Vector3(0.8, 0.08, 1.3))
		Kit.ball(top, 0.05, CREAM, Vector3(x, 0.03, -0.14), Vector3(1, 0.1, 0.8))


## A pinwheel on a stick: four sails in the paint color and its lighter shade.
static func _pinwheel(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.3, 0.15)
	Kit.cyl(n, 0.11, 0.14, 0.06, Palette.STONE, Vector3(0, 0.03, 0))
	Kit.cyl(n, 0.02, 0.025, 0.95, CREAM, Vector3(0, 0.5, 0))
	var wheel := _pivot(n, Vector3(0, 0.95, 0.05))
	wheel.name = "Wheel"
	for i in 4:
		var a := TAU * i / 4.0
		var blade := Node3D.new()
		blade.rotation.z = a
		wheel.add_child(blade)
		# Each sail is a flat petal, tilted a little like folded paper.
		Kit.box(blade, Vector3(0.11, 0.26, 0.012), c if i % 2 == 0 else c.lerp(Color.WHITE, 0.55), Vector3(0.05, 0.15, 0.0), 0.005, Vector3(0, 28, -18))
	Kit.ball(wheel, 0.035, Color("#f2c75c"), Vector3(0, 0, 0.02))


## A round pot with a funnel on top that blows soap bubbles.
static func _bubbles(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.36, 0.18)
	Kit.cyl(n, 0.2, 0.24, 0.26, c, Vector3(0, 0.13, 0))
	Kit.cyl(n, 0.21, 0.21, 0.03, CREAM, Vector3(0, 0.27, 0))
	Kit.cyl(n, 0.13, 0.06, 0.14, CREAM, Vector3(0, 0.35, 0))        # the funnel
	Kit.part(n, Kit.torus(0.105, 0.135), c.darkened(0.15), Vector3(0, 0.42, 0))
	for p in [Vector3(-0.2, 0.16, 0.13), Vector3(0.21, 0.12, 0.1)]:   # two painted bubbles on the pot
		Kit.ball(n, 0.045, Color("#dff1fa"), p, Vector3(1, 1, 0.4))
	var nozzle := _pivot(n, Vector3(0, 0.44, 0))
	nozzle.name = "Nozzle"
