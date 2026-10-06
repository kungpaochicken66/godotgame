## Builds the 3D model for every catalog item. Origin is the ground center and
## the front faces +z. Proportions are set against a 1.2 m tall child so doors,
## seats and tables read as usable.
##
## Conventions used by the world:
##   "Seat0", "Seat1" Marker3D: where a seated child goes, facing the marker's +z
##   "Pivot" Node3D: part that animates (swing seat, seesaw plank)
##   group "glow": MeshInstance3D whose material brightens in the evening
##   group "lamp": OmniLight3D switched on in the evening
extends RefCounted

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Catalog := preload("res://scripts/core/catalog.gd")


static func build(kind: String, color_index: int, seed := 0) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var c := Palette.paint(color_index) if color_index >= 0 else Color.WHITE
	var model_path: String = Catalog.get_def(kind).get("model", "")
	if model_path != "":
		_modeled(root, kind, model_path)
		return root
	match kind:
		"cottage": _cottage(root, c)
		"tree": _tree(root, c, seed)
		"pine": _pine(root)
		"bush": _bush(root, c, seed)
		"flowers": _flowers(root, c, seed)
		"path_stone": _path_stone(root, seed)
		"pond": _pond(root)
		"lamp_post": _lamp_post(root, c)
		"fence": _fence(root, c)
		"swing": _swing(root, c)
		"seesaw": _seesaw(root, c)
		"bench": _bench(root, c)
		"blanket": _blanket(root, c)
		"bed": _bed(root, c)
		"chair": _chair(root, c)
		"table": _table(root)
		"sofa": _sofa(root, c)
		"bookshelf": _bookshelf(root, c)
		"rug": _rug(root, c)
		"plant": _plant(root, c)
		"floor_lamp": _floor_lamp(root, c)
		"teddy": _teddy(root, c)
		_: Kit.box(root, Vector3(0.5, 0.5, 0.5), Color.MAGENTA, Vector3(0, 0.25, 0))
	Kit.merge_parts(root)
	return root


## A reviewed GLB model. Its scale is final (baked in the builder), so it is never
## rescaled here. Markers in the file (Seat0, Sleep0, Support0, Light0) are kept
## as nodes and used by the game.
static func _modeled(root: Node3D, kind: String, path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		Kit.box(root, Catalog.get_def(kind)["bounds"], Color.MAGENTA, Vector3(0, Catalog.height(kind) * 0.5, 0))
		return
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	# Soft matte look like the procedural props (Lambert-wrap is not stored in glTF).
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m:
				m = m.duplicate()
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				(mi as MeshInstance3D).set_surface_override_material(si, m)
	var b: Vector3 = Catalog.get_def(kind)["bounds"]
	Kit.blob_shadow(root, maxf(b.x, b.z) * 0.55, 0.22)
	# Bring markers to the prop root so seating code finds them by name.
	for marker in ["Seat0", "Sleep0", "Support0", "Light0"]:
		var node := model.find_child(marker, true, false) as Node3D
		if node:
			var m3 := Marker3D.new()
			m3.name = marker
			m3.transform = model.transform * _relative(model, node)
			root.add_child(m3)
	var light := root.get_node_or_null("Light0") as Node3D
	if light:
		_light(root, light.position, Color("#ffd690"), 3.0)


static func _relative(top: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != top and n != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _shade(c: Color, f: float) -> Color:
	return c.darkened(f) if f > 0 else c.lightened(-f)


static func _seat(root: Node3D, name: String, pos: Vector3, yaw := 0.0) -> Marker3D:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	m.rotation.y = yaw
	root.add_child(m)
	return m


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


# ---------------------------------------------------------------- outdoors

## Three-story cottage: same footprint and front door as before, stacked floors
## with trim bands, windows on every floor, a little balcony and the roof on top.
static func _cottage(n: Node3D, roof: Color) -> void:
	Kit.blob_shadow(n, 2.5, 0.28)
	var wall := Palette.PLASTER
	var lift := 3.6   # two upper floors of 1.8 m each
	Kit.box(n, Vector3(3.6, 0.3, 2.9), Palette.STONE, Vector3(0, 0.15, 0), 0.1)
	Kit.box(n, Vector3(3.4, 2.1 + lift, 2.7), wall, Vector3(0, 1.3 + lift * 0.5, 0), 0.12)
	# Wooden trim between floors makes the three stories easy to read.
	for y in [2.35, 4.15]:
		Kit.box(n, Vector3(3.5, 0.14, 2.8), Palette.WOOD, Vector3(0, y, 0), 0.05)
	# Roof: two soft slabs meeting at the ridge, with gable fill.
	var roof_c := roof
	for s in [-1, 1]:
		Kit.box(n, Vector3(2.35, 0.24, 3.3), roof_c, Vector3(s * 0.92, 2.95 + lift, 0), 0.1, Vector3(0, 0, -s * 36))
	var gable := Kit.part(n, PrismMesh.new(), wall, Vector3(0, 2.75 + lift, 0), Vector3.ZERO, Vector3(2.9, 1.0, 2.6))
	(gable.mesh as PrismMesh).size = Vector3(1, 1, 1)
	Kit.box(n, Vector3(0.5, 0.9, 0.5), Palette.STONE, Vector3(-0.9, 3.4 + lift, -0.5), 0.08)
	Kit.box(n, Vector3(0.6, 0.12, 0.6), _shade(roof_c, 0.2), Vector3(-0.9, 3.85 + lift, -0.5), 0.05)
	# Front door (faces +z), arched with a round window.
	var door_c := _shade(roof_c, 0.15)
	Kit.box(n, Vector3(0.95, 1.5, 0.16), door_c, Vector3(0.55, 1.05, 1.37), 0.12)
	Kit.ball(n, 0.47, door_c, Vector3(0.55, 1.8, 1.37), Vector3(1, 0.55, 0.17))
	Kit.ball(n, 0.06, Palette.paint(1), Vector3(0.85, 1.05, 1.47))
	Kit.ball(n, 0.15, Color("#bfe3f0"), Vector3(0.55, 1.55, 1.46), Vector3(1, 1, 0.3))
	Kit.box(n, Vector3(1.3, 0.16, 0.6), Palette.STONE, Vector3(0.55, 0.38, 1.65), 0.06)
	# Windows that glow warmly in the evening, on every floor.
	_window(n, Vector3(-0.85, 1.45, 1.36), roof_c)
	for y in [3.25, 5.05]:
		for side in [-1, 1]:
			_window(n, Vector3(side * 1.71, y, 0.2), roof_c, 90)
	for side in [-1, 1]:
		_window(n, Vector3(side * 1.71, 1.45, 0.2), roof_c, 90)
		_window(n, Vector3(side * 0.8, 3.25, 1.36), roof_c)
	# Second-floor balcony with a railing and flowers.
	Kit.box(n, Vector3(2.6, 0.12, 0.5), Palette.WOOD, Vector3(0, 2.5, 1.6), 0.04)
	for i in 7:
		Kit.box(n, Vector3(0.06, 0.42, 0.06), Palette.WOOD, Vector3(-1.2 + i * 0.4, 2.75, 1.82), 0.02)
	Kit.box(n, Vector3(2.6, 0.08, 0.08), Palette.WOOD_DARK, Vector3(0, 2.98, 1.82), 0.03)
	for i in 5:
		Kit.ball(n, 0.09, Palette.paint([3, 1, 6, 0, 3][i]), Vector3(-1.0 + i * 0.5, 2.65, 1.62))
	# Round attic window on the top floor.
	var attic := Kit.part(n, Kit.torus(0.26, 0.34), Palette.WOOD, Vector3(0, 5.05, 1.37), Vector3(90, 0, 0))
	attic.name = "AtticFrame"
	var glass := Kit.part(n, Kit.cylinder(0.27, 0.27, 0.06), Kit.glow_mat(Color("#b9dcea")), Vector3(0, 5.05, 1.36), Vector3(90, 0, 0))
	glass.add_to_group("glow")
	glass.set_meta("glow_color", Color("#ffd98a"))
	# Window box flowers on the ground floor.
	Kit.box(n, Vector3(0.85, 0.16, 0.22), Palette.WOOD, Vector3(-0.85, 1.0, 1.5), 0.05)
	for i in 4:
		Kit.ball(n, 0.08, Palette.paint([3, 1, 0, 6][i]), Vector3(-1.15 + i * 0.2, 1.13, 1.5))


static func _window(n: Node3D, pos: Vector3, frame: Color, yaw := 0.0) -> void:
	var w := Node3D.new()
	w.position = pos
	w.rotation_degrees.y = yaw
	n.add_child(w)
	Kit.box(w, Vector3(0.78, 0.78, 0.12), Palette.WOOD, Vector3.ZERO, 0.06)
	var glass := Kit.box(w, Vector3(0.6, 0.6, 0.14), Kit.glow_mat(Color("#b9dcea")), Vector3(0, 0, 0.01), 0.04)
	glass.add_to_group("glow")
	glass.set_meta("glow_color", Color("#ffd98a"))
	Kit.box(w, Vector3(0.06, 0.6, 0.16), Palette.WOOD, Vector3.ZERO, 0.02)
	Kit.box(w, Vector3(0.6, 0.06, 0.16), Palette.WOOD, Vector3.ZERO, 0.02)


## Ordinary round tree, about 1.85 H tall (see design/object-scale-and-surfaces.md).
static func _tree(n: Node3D, leaves: Color, seed: int) -> void:
	var r := _rng(seed)
	Kit.blob_shadow(n, 1.0, 0.26)
	Kit.cyl(n, 0.11, 0.17, 1.0, Palette.WOOD_DARK, Vector3(0, 0.5, 0))
	Kit.cyl(n, 0.05, 0.08, 0.4, Palette.WOOD_DARK, Vector3(0.17, 0.95, 0), Vector3(0, 0, -40))
	var c := leaves
	Kit.ball(n, 0.62, c, Vector3(0, 1.55, 0))
	for i in 5:
		var a := TAU * i / 5.0 + r.randf() * 0.5
		var off := Vector3(cos(a) * 0.5, 1.3 + r.randf() * 0.3, sin(a) * 0.5)
		Kit.ball(n, 0.4 + r.randf() * 0.08, _shade(c, 0.05 + r.randf() * 0.08), off)
	Kit.ball(n, 0.38, c.lightened(0.08), Vector3(0, 2.04, 0.06))

static func _pine(n: Node3D) -> void:
	Kit.blob_shadow(n, 0.8, 0.26)
	Kit.cyl(n, 0.09, 0.12, 0.5, Palette.WOOD_DARK, Vector3(0, 0.25, 0))
	var g := Color("#5f9a6a")
	for i in 3:
		Kit.cyl(n, 0.05, 0.75 - i * 0.18, 0.8, _shade(g, -i * 0.06), Vector3(0, 0.8 + i * 0.46, 0))

static func _bush(n: Node3D, berry: Color, seed: int) -> void:
	var r := _rng(seed)
	Kit.blob_shadow(n, 0.8)
	var g := Color("#7fb36c")
	Kit.ball(n, 0.48, g, Vector3(0, 0.42, 0))
	Kit.ball(n, 0.36, _shade(g, 0.06), Vector3(-0.32, 0.32, 0.1))
	Kit.ball(n, 0.34, _shade(g, -0.05), Vector3(0.3, 0.3, 0.05))
	for i in 7:
		var a := r.randf() * TAU
		var y := 0.3 + r.randf() * 0.5
		Kit.ball(n, 0.07, berry, Vector3(cos(a) * 0.45, y, sin(a) * 0.45 + 0.05))


static func _flowers(n: Node3D, petal: Color, seed: int) -> void:
	var r := _rng(seed)
	Kit.blob_shadow(n, 0.55, 0.18)
	Kit.ball(n, 0.42, Color("#86b866"), Vector3(0, 0.02, 0), Vector3(1, 0.35, 1))
	for i in 6:
		var a := TAU * i / 6.0 + r.randf() * 0.4
		var d := 0.12 + r.randf() * 0.22
		var p := Vector3(cos(a) * d, 0.22 + r.randf() * 0.12, sin(a) * d)
		Kit.cyl(n, 0.012, 0.012, p.y, Color("#6aa257"), Vector3(p.x, p.y * 0.5, p.z))
		for k in 5:
			var pa := TAU * k / 5.0
			Kit.ball(n, 0.055, petal if i % 3 != 2 else Palette.paint(0), p + Vector3(cos(pa) * 0.06, 0, sin(pa) * 0.06), Vector3(1, 0.5, 1))
		Kit.ball(n, 0.035, Color("#f6d55c"), p + Vector3(0, 0.02, 0))


static func _path_stone(n: Node3D, seed: int) -> void:
	var r := _rng(seed)
	var s := Kit.part(n, Kit.rounded_box(Vector3(0.78, 0.1, 0.66), 0.05), Palette.PATH, Vector3(0, 0.03, 0))
	s.rotation.y = r.randf() * TAU
	Kit.part(n, Kit.rounded_box(Vector3(0.3, 0.1, 0.24), 0.04), _shade(Palette.PATH, 0.05),
		Vector3(0.36, 0.025, -0.3).rotated(Vector3.UP, s.rotation.y))


static func _pond(n: Node3D) -> void:
	var water := Kit.mat(Palette.WATER, 0.15)
	Kit.part(n, Kit.cylinder(1.75, 1.75, 0.06, 40), Color("#4aa9b6"), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
	Kit.part(n, Kit.cylinder(1.65, 1.65, 0.05, 40), water, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
	var r := _rng(7)
	for i in 16:
		var a := TAU * i / 16.0
		var p := Vector3(cos(a) * 1.82, 0.12, sin(a) * 1.82 * 0.82)
		Kit.ball(n, 0.24 + r.randf() * 0.08, _shade(Palette.STONE, r.randf() * 0.1), p, Vector3(1, 0.7, 1))
	for p in [Vector3(-0.6, 0.09, 0.2), Vector3(0.5, 0.09, -0.4), Vector3(0.2, 0.09, 0.6)]:
		Kit.part(n, Kit.cylinder(0.22, 0.22, 0.02), Color("#79b866"), p)
		Kit.ball(n, 0.07, Palette.paint(3).lightened(0.3), p + Vector3(0.05, 0.05, 0))
	for p in [Vector3(1.55, 0, -0.75), Vector3(1.7, 0, -0.45), Vector3(-1.6, 0, 0.6)]:
		Kit.cyl(n, 0.02, 0.02, 0.9, Color("#6aa257"), p + Vector3(0, 0.45, 0))
		Kit.part(n, Kit.capsule(0.05, 0.22), Color("#9a6a45"), p + Vector3(0, 0.85, 0))


static func _lamp_post(n: Node3D, frame: Color) -> void:
	Kit.blob_shadow(n, 0.4)
	Kit.cyl(n, 0.2, 0.24, 0.18, Color("#5d6b62"), Vector3(0, 0.09, 0))
	Kit.cyl(n, 0.06, 0.07, 2.2, Color("#5d6b62"), Vector3(0, 1.2, 0))
	Kit.box(n, Vector3(0.38, 0.06, 0.38), frame, Vector3(0, 2.3, 0), 0.02)
	var glass := Kit.box(n, Vector3(0.3, 0.42, 0.3), Kit.glow_mat(Color("#fff3c4")), Vector3(0, 2.55, 0), 0.06)
	glass.add_to_group("glow")
	glass.set_meta("glow_color", Color("#ffd27a"))
	Kit.cyl(n, 0.02, 0.28, 0.2, frame, Vector3(0, 2.86, 0))
	Kit.ball(n, 0.05, frame, Vector3(0, 2.98, 0))
	_light(n, Vector3(0, 2.5, 0), Color("#ffcf7a"), 5.0)


static func _light(n: Node3D, pos: Vector3, color: Color, radius: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = radius
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.add_to_group("lamp")
	n.add_child(l)


static func _fence(n: Node3D, c: Color) -> void:
	for x in [-0.55, 0.55]:
		Kit.box(n, Vector3(0.14, 0.75, 0.14), c, Vector3(x, 0.375, 0), 0.05)
		Kit.ball(n, 0.08, c, Vector3(x, 0.77, 0))
	for y in [0.28, 0.55]:
		Kit.box(n, Vector3(1.3, 0.1, 0.07), _shade(c, 0.06), Vector3(0, y, 0.02), 0.03)


static func _swing(n: Node3D, seat: Color) -> void:
	Kit.blob_shadow(n, 1.4, 0.2)
	var wood := Palette.WOOD
	for side in [-1, 1]:
		for lean in [-1, 1]:
			Kit.box(n, Vector3(0.14, 2.35, 0.14), wood, Vector3(side * 1.05, 1.12, lean * 0.36), 0.05, Vector3(lean * 17, 0, 0))
	Kit.box(n, Vector3(2.4, 0.18, 0.18), _shade(wood, 0.1), Vector3(0, 2.25, 0), 0.06)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 2.2, 0)
	n.add_child(pivot)
	for x in [-0.3, 0.3]:
		Kit.cyl(pivot, 0.02, 0.02, 1.62, Color("#e8d7b0"), Vector3(x, -0.81, 0))
	Kit.box(pivot, Vector3(0.78, 0.09, 0.36), seat, Vector3(0, -1.66, 0), 0.04)
	_seat(pivot, "Seat0", Vector3(0, -1.62, 0))


static func _seesaw(n: Node3D, plank: Color) -> void:
	Kit.blob_shadow(n, 1.5, 0.18)
	Kit.box(n, Vector3(0.5, 0.5, 0.4), Palette.WOOD, Vector3(0, 0.25, 0), 0.12)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 0.55, 0)
	n.add_child(pivot)
	Kit.box(pivot, Vector3(0.36, 0.1, 3.0), plank, Vector3(0, 0, 0), 0.05)
	for z in [-1, 1]:
		Kit.box(pivot, Vector3(0.42, 0.12, 0.42), _shade(plank, -0.15), Vector3(0, 0.08, z * 1.22), 0.05)
		Kit.box(pivot, Vector3(0.06, 0.3, 0.06), Palette.WOOD_DARK, Vector3(0, 0.25, z * 0.95), 0.02)
		Kit.box(pivot, Vector3(0.36, 0.06, 0.06), Palette.WOOD_DARK, Vector3(0, 0.4, z * 0.95), 0.02)
	_seat(pivot, "Seat0", Vector3(0, 0.14, 1.22), PI)
	_seat(pivot, "Seat1", Vector3(0, 0.14, -1.22), 0.0)


static func _bench(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.95, 0.2)
	for x in [-0.65, 0.65]:
		Kit.box(n, Vector3(0.12, 0.42, 0.42), Palette.WOOD_DARK, Vector3(x, 0.21, 0), 0.04)
	for i in 3:
		Kit.box(n, Vector3(1.6, 0.06, 0.14), c, Vector3(0, 0.45, -0.16 + i * 0.16), 0.025)
	for i in 2:
		Kit.box(n, Vector3(1.6, 0.13, 0.06), c, Vector3(0, 0.68 + i * 0.2, -0.27), 0.03, Vector3(-12, 0, 0))
	_seat(n, "Seat0", Vector3(-0.38, 0.47, 0.02))
	_seat(n, "Seat1", Vector3(0.38, 0.47, 0.02))


static func _blanket(n: Node3D, c: Color) -> void:
	Kit.box(n, Vector3(1.8, 0.04, 1.4), Palette.paint(0), Vector3(0, 0.02, 0), 0.02)
	for i in 4:
		Kit.box(n, Vector3(0.22, 0.045, 1.4), c, Vector3(-0.68 + i * 0.45, 0.025, 0), 0.02)
		Kit.box(n, Vector3(1.8, 0.046, 0.2), c.lightened(0.15), Vector3(0, 0.026, -0.5 + i * 0.33), 0.02)
	Kit.box(n, Vector3(0.42, 0.24, 0.3), Palette.WOOD, Vector3(0.45, 0.14, -0.25), 0.07)
	Kit.part(n, Kit.torus(0.17, 0.2), Palette.WOOD_DARK, Vector3(0.45, 0.27, -0.25), Vector3(90, 0, 0), Vector3(1.1, 1, 1))
	Kit.ball(n, 0.08, Color("#e45b4f"), Vector3(-0.3, 0.1, 0.2))


# ---------------------------------------------------------------- indoors

static func _bed(n: Node3D, duvet: Color) -> void:
	Kit.blob_shadow(n, 1.0, 0.18)
	var wood := Palette.WOOD
	Kit.box(n, Vector3(1.05, 0.28, 1.8), wood, Vector3(0, 0.24, 0), 0.06)
	Kit.box(n, Vector3(1.12, 0.85, 0.12), wood, Vector3(0, 0.45, -0.92), 0.06)
	Kit.box(n, Vector3(1.12, 0.5, 0.12), wood, Vector3(0, 0.27, 0.92), 0.06)
	for x in [-0.56, 0.56]:
		Kit.ball(n, 0.08, _shade(wood, 0.1), Vector3(x, 0.9, -0.92))
	Kit.box(n, Vector3(0.98, 0.16, 1.7), Palette.paint(0).lightened(0.4), Vector3(0, 0.46, 0), 0.07)
	Kit.box(n, Vector3(1.02, 0.12, 1.15), duvet, Vector3(0, 0.56, 0.28), 0.06)
	Kit.box(n, Vector3(0.66, 0.15, 0.36), Color.WHITE.darkened(0.03), Vector3(0, 0.6, -0.62), 0.07)
	_seat(n, "Seat0", Vector3(0, 0.62, 0.1))


static func _chair(n: Node3D, cushion: Color) -> void:
	Kit.blob_shadow(n, 0.42, 0.18)
	var wood := Palette.WOOD
	for x in [-0.2, 0.2]:
		for z in [-0.2, 0.2]:
			Kit.box(n, Vector3(0.08, 0.42, 0.08), wood, Vector3(x, 0.21, z), 0.03)
	Kit.box(n, Vector3(0.52, 0.07, 0.52), wood, Vector3(0, 0.43, 0), 0.03)
	Kit.box(n, Vector3(0.46, 0.08, 0.44), cushion, Vector3(0, 0.49, 0.02), 0.04)
	for x in [-0.2, 0.2]:
		Kit.box(n, Vector3(0.08, 0.55, 0.08), wood, Vector3(x, 0.72, -0.22), 0.03)
	Kit.box(n, Vector3(0.5, 0.2, 0.07), wood, Vector3(0, 0.88, -0.22), 0.04)
	_seat(n, "Seat0", Vector3(0, 0.5, 0.02))


static func _table(n: Node3D) -> void:
	Kit.blob_shadow(n, 0.7, 0.2)
	var wood := Palette.WOOD
	Kit.cyl(n, 0.6, 0.6, 0.08, wood, Vector3(0, 0.66, 0))
	Kit.cyl(n, 0.07, 0.09, 0.62, _shade(wood, 0.12), Vector3(0, 0.33, 0))
	Kit.cyl(n, 0.3, 0.32, 0.05, _shade(wood, 0.12), Vector3(0, 0.03, 0))
	# The top is left clear: it is a support surface for one small decoration.


static func _sofa(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 1.0, 0.2)
	Kit.box(n, Vector3(1.7, 0.36, 0.8), _shade(c, 0.1), Vector3(0, 0.24, 0), 0.12)
	Kit.box(n, Vector3(1.7, 0.6, 0.24), c, Vector3(0, 0.62, -0.3), 0.12)
	for x in [-0.78, 0.78]:
		Kit.box(n, Vector3(0.24, 0.48, 0.8), c, Vector3(x, 0.44, 0), 0.11)
	for x in [-0.33, 0.33]:
		Kit.box(n, Vector3(0.64, 0.16, 0.6), c.lightened(0.1), Vector3(x, 0.48, 0.06), 0.07)
	Kit.box(n, Vector3(0.36, 0.3, 0.12), Palette.paint(1), Vector3(-0.42, 0.72, -0.12), 0.06, Vector3(-10, 10, 0))
	_seat(n, "Seat0", Vector3(-0.35, 0.56, 0.08))
	_seat(n, "Seat1", Vector3(0.35, 0.56, 0.08))


static func _bookshelf(n: Node3D, c: Color) -> void:
	Kit.blob_shadow(n, 0.65, 0.2)
	Kit.box(n, Vector3(1.1, 1.6, 0.42), c, Vector3(0, 0.8, 0), 0.06)
	Kit.box(n, Vector3(0.98, 1.44, 0.3), _shade(c, 0.25), Vector3(0, 0.82, 0.08), 0.03)
	var r := _rng(3)
	for shelf in 3:
		var y := 0.18 + shelf * 0.48
		Kit.box(n, Vector3(1.0, 0.05, 0.36), c, Vector3(0, y, 0.05), 0.02)
		var x := -0.42
		while x < 0.4:
			var w := 0.06 + r.randf() * 0.05
			var h := 0.26 + r.randf() * 0.12
			Kit.box(n, Vector3(w, h, 0.24), Palette.paint(r.randi_range(1, 7)), Vector3(x + w * 0.5, y + h * 0.5 + 0.025, 0.08), 0.015)
			x += w + 0.015


static func _rug(n: Node3D, c: Color) -> void:
	Kit.part(n, Kit.cylinder(1.1, 1.1, 0.03, 40), c, Vector3(0, 0.015, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	Kit.part(n, Kit.cylinder(0.85, 0.85, 0.035, 40), Palette.paint(0), Vector3(0, 0.018, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	Kit.part(n, Kit.cylinder(0.55, 0.55, 0.04, 40), c.lightened(0.25), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.72))


## Flower pot: a small decoration (about 0.4 H) that fits on a table top.
static func _plant(n: Node3D, bloom: Color) -> void:
	Kit.blob_shadow(n, 0.25, 0.2)
	Kit.cyl(n, 0.15, 0.11, 0.24, Color("#d98c62"), Vector3(0, 0.12, 0))
	Kit.cyl(n, 0.16, 0.16, 0.05, Color("#e39d74"), Vector3(0, 0.24, 0))
	Kit.ball(n, 0.15, Color("#7fb36c"), Vector3(0, 0.35, 0))
	Kit.ball(n, 0.1, Color("#6ea65d"), Vector3(0.09, 0.42, 0.03))
	for i in 5:
		var a := TAU * i / 5.0
		Kit.ball(n, 0.05, bloom, Vector3(cos(a) * 0.11, 0.44 + (i % 2) * 0.03, sin(a) * 0.11))

static func _floor_lamp(n: Node3D, shade: Color) -> void:
	Kit.blob_shadow(n, 0.35, 0.2)
	Kit.cyl(n, 0.2, 0.22, 0.05, Palette.WOOD_DARK, Vector3(0, 0.025, 0))
	Kit.cyl(n, 0.025, 0.025, 1.35, Palette.WOOD_DARK, Vector3(0, 0.7, 0))
	var s := Kit.cyl(n, 0.16, 0.3, 0.34, Kit.glow_mat(shade.lightened(0.3)), Vector3(0, 1.45, 0))
	s.add_to_group("glow")
	s.set_meta("glow_color", Color("#ffd98a"))
	_light(n, Vector3(0, 1.3, 0), Color("#ffd690"), 4.0)


## Teddy bear: a small decoration (about 0.35 H) that fits on a table top.
static func _teddy(root: Node3D, fur: Color) -> void:
	Kit.blob_shadow(root, 0.24, 0.2)
	var n := Node3D.new()
	n.scale = Vector3.ONE * 0.75
	root.add_child(n)
	var light := fur.lightened(0.35)
	Kit.ball(n, 0.17, fur, Vector3(0, 0.17, 0), Vector3(1, 1.05, 0.9))
	Kit.ball(n, 0.08, light, Vector3(0, 0.16, 0.12), Vector3(1, 1.2, 0.5))
	Kit.ball(n, 0.14, fur, Vector3(0, 0.42, 0))
	Kit.ball(n, 0.06, light, Vector3(0, 0.4, 0.12), Vector3(1, 0.8, 0.8))
	Kit.ball(n, 0.02, Color("#3a2a22"), Vector3(0, 0.42, 0.18))
	for x in [-0.06, 0.06]:
		Kit.ball(n, 0.018, Color("#3a2a22"), Vector3(x, 0.47, 0.125))
	for x in [-0.11, 0.11]:
		Kit.ball(n, 0.055, fur, Vector3(x, 0.54, -0.01))
		Kit.ball(n, 0.06, fur, Vector3(x * 1.4, 0.06, 0.08))
		Kit.ball(n, 0.055, fur, Vector3(x * 1.6, 0.22, 0.04))
	Kit.box(n, Vector3(0.12, 0.05, 0.05), Palette.paint(3), Vector3(0, 0.31, 0.11), 0.02)
