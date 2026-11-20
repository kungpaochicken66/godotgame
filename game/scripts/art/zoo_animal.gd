## A zoo animal: a code-built model on a tree of named pivots, posed in code every frame
## (design/zoo-and-world-journeys.md sections 4, 6.3 and 7; docs/zoo-engineering-standard.md).
##
## Same technique and look as the town's animals (animal.gd) and the child (kid.gd): rounded
## primitives from mesh_kit, flat matte colours, parts merged per pivot. Larger than the town's
## animals (zoo scale classes, section 6.1), with two-segment limbs, a neck, a jaw and a tail
## chain so actions change the whole silhouette. The world places the node (ZooBrain.path_point);
## this script only poses it from the action, its progress and the time.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")

var species := ""
var animal_id := ""
var variant := 0
var young := false
var action := "idle"
var u := 0.0                    # progress of the current action, 0..1
var param := 0.0
var reduce_motion := false
var hanging := false            # on a ring or the vine: drawn from the hands
var _t := 0.0
var _phase := 0.0               # each animal's own offset, so no two move in step
var _pivots := {}               # name -> Node3D
var _rest := {}                 # name -> rest rotation (Vector3)
var _body: Node3D
var _prop: Node3D               # a ball, a banana or an ice pop, shown by some actions
var _label: Label3D
var _drops: Node3D              # water drops for a shake or a splash
## Measured once after building (for the readability tests): the model's height in its usual pose.
var size := Vector3.ZERO
## zoo r2: species drawn from the imported Everything Library models (standard 11.1). Loaded at
## runtime, so this script never depends on the skin script at parse time.
const SKIN_SCRIPT := "res://scripts/art/zoo_skin.gd"
const POSE_EXTRA_SCRIPT := "res://scripts/art/zoo_pose_extra.gd"
const SPECIES_SCALE := {"penguin": 1.2, "panda": 1.15}
const SKINNED := {"lion": true, "giraffe": true, "zebra": true, "panda": true, "elephant": true, "penguin": true}
var _skin: Dictionary = {}       # what ZooSkin.build returned (empty for the procedural rigs)
static var _skin_script: Script = null
static var _pose_extra: Script = null

const DARK := Color("#2b2320")
const WHITE := Color("#fffdf6")


func setup(sp: String, id := "", var_index := 0, is_young := false) -> void:
	species = sp
	animal_id = id
	variant = var_index
	young = is_young
	_phase = float(hash(id) % 1000) / 1000.0 * TAU
	_body = _pivot(self, "body", Vector3.ZERO)
	# zoo r2 (standard 11.1): the Everything Library models, skinned and driven by the same pivots.
	var skin_script: Script = load(SKIN_SCRIPT) if SKINNED.has(species) and ResourceLoader.exists(SKIN_SCRIPT) else null
	if skin_script != null and skin_script.has_model(species):
		_skin = skin_script.build(self, _body, species)
		for k in _skin["pivots"]:
			_pivots[k] = _skin["pivots"][k]
		size = _skin["size"]
		_prop = _skin["pivots"].get("prop")
	else:
		match species:
			"lion": _build_cat(true, false)
			"lioness": _build_cat(false, false)
			"tiger": _build_cat(false, true)
			"giraffe": _build_giraffe()
			"zebra": _build_zebra()
			"hippo": _build_hippo()
			"otter": _build_otter()
			"monkey": _build_monkey()
	if young:
		scale = Vector3.ONE * 0.78
	if SPECIES_SCALE.has(species):
		# zoo r2: the penguin at an emperor's 1.2 m and the panda at 1.27 m (their GLBs are 1.0 and 1.1 m),
		# so they read at 115 px from their bays like the other residents (design 22.5.2's readability
		# rule; the otter was resized the same way in r1).
		scale = Vector3.ONE * float(SPECIES_SCALE[species])
		size *= float(SPECIES_SCALE[species])
	if _skin.is_empty():
		Kit.merge_parts(self)   # never on a skinned mesh: merging would cut it from its skeleton
	for k in _pivots:
		_rest[k] = (_pivots[k] as Node3D).rotation
	for k in _skin.get("rest", {}):
		_rest[k] = _skin["rest"][k]
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0035
	_label.font_size = 44
	_label.outline_size = 12
	_label.modulate = Color("#7a5a3a")
	_label.outline_modulate = WHITE
	_label.visible = false
	add_child(_label)


## The name tag and the line over the head (the world sets the text, translated).
func set_label(text: String, busy: bool, head_height: float) -> void:
	_label.text = text
	_label.visible = text != ""
	_label.modulate = Color("#b0486a") if busy else Color("#7a5a3a")
	_label.font_size = 50 if busy else 44
	_label.position.y = head_height + 0.35


static var _caps := {}


## A capsule with few segments (the kit's is 672 triangles; a limb needs far fewer).
func _capsule(r: float, h: float) -> CapsuleMesh:
	var key := "%.3f|%.3f" % [r, h]
	if not _caps.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 10 if r >= 0.1 else 8
		m.rings = 2
		_caps[key] = m
	return _caps[key]


func _rbox(sz: Vector3, r: float) -> ArrayMesh:
	return Kit.rounded_box(sz, r, 2)


## A sphere with few rings for small parts (section 14.1: a default sphere is 576 triangles).
func _ball(parent: Node3D, r: float, color: Variant, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var rings := 9 if r >= 0.2 else (7 if r >= 0.08 else 5)
	return Kit.part(parent, Kit.sphere(r, rings), color, pos, Vector3.ZERO, scl)


func _pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	_pivots[name] = n
	return n


func _eyes(head: Node3D, y: float, z: float, spread: float, w: float) -> void:
	# A dark oval with a white highlight (section 4.2: at least 0.12 m wide on adults)
	for side in [-1, 1]:
		_ball(head, w * 0.5, DARK, Vector3(side * spread, y, z), Vector3(0.85, 1.1, 0.55))
		_ball(head, w * 0.18, WHITE, Vector3(side * spread - side * w * 0.12, y + w * 0.18, z + w * 0.22))


## A two-segment leg: hip (upper) -> knee (lower) -> paw. Returns the upper pivot.
func _leg(name: String, at: Vector3, upper: float, lower: float, r: float, color: Color, paw_color: Color) -> Node3D:
	var hip := _pivot(_body, name, at)
	Kit.part(hip, _capsule(r, upper + r), color, Vector3(0, -upper * 0.5, 0))
	var knee := _pivot(hip, name + "_low", Vector3(0, -upper, 0))
	Kit.part(knee, _capsule(r * 0.9, lower + r), color, Vector3(0, -lower * 0.5, 0))
	_ball(knee, r * 1.25, paw_color, Vector3(0, -lower, r * 0.35), Vector3(1.0, 0.7, 1.3))
	return hip


## A tail as a chain of pivots, each segment lagging its parent (like the elephant's trunk).
func _tail(at: Vector3, segments: int, seg_len: float, r: float, color: Color, tip_color: Color, tip_r: float, rings := 0, ring_color := Color.BLACK) -> void:
	var parent := _pivot(_body, "tail0", at)
	parent.rotation.x = deg_to_rad(-35.0)
	for i in segments:
		var rr := r * (1.0 - 0.12 * i)
		Kit.part(parent, _capsule(rr, seg_len + rr), ring_color if rings > 0 and i % 2 == 1 and i >= segments - rings * 2 else color, Vector3(0, 0, -seg_len * 0.5), Vector3(90, 0, 0))
		if i < segments - 1:
			parent = _pivot(parent, "tail%d" % (i + 1), Vector3(0, 0, -seg_len))
	_ball(parent, tip_r, tip_color, Vector3(0, 0, -seg_len))


# ---------------------------------------------------------------- the big cats

## Lion (mane), lioness, tiger (bands). Section 6.3: lion 1.55 m at the mane, 2.1 long; lioness
## 1.35, 1.95; tiger 1.40, 2.2, tail 1.1.
func _build_cat(mane: bool, stripes: bool) -> void:
	var gold := Color("#e6b45a") if not stripes else Color("#ef9a3c")
	if species == "lioness":
		gold = Color("#ecc27a")
	var pale := Color("#f8ead0")
	var mane_c := Color("#a8622c")
	var band := Color("#3a2f2b")
	var long := 2.1 if mane else (2.2 if stripes else 1.95)
	var hip := 0.62 if not stripes else 0.6
	var torso := Vector3(0.62, 0.56, long * 0.62)
	Kit.blob_shadow(self, 0.95, 0.24)
	Kit.part(_body, _rbox(torso, 0.26), gold, Vector3(0, hip + 0.24, 0))
	_ball(_body, 0.3, pale, Vector3(0, hip + 0.06, 0.05), Vector3(0.95, 0.5, 2.2))   # a pale belly
	if stripes:
		for i in 6:
			var z := torso.z * 0.42 - i * torso.z * 0.17
			Kit.part(_body, _rbox(Vector3(torso.x + 0.03, 0.12, 0.13), 0.05), band, Vector3(0, hip + 0.46, z))
	var lw := torso.x * 0.36
	var lz := torso.z * 0.36
	for side in [-1, 1]:
		_leg("leg_f%s" % ("l" if side < 0 else "r"), Vector3(side * lw, hip + 0.08, lz), 0.36, hip - 0.36 + 0.08, 0.11, gold, pale)
		_leg("leg_b%s" % ("l" if side < 0 else "r"), Vector3(side * lw, hip + 0.08, -lz), 0.36, hip - 0.36 + 0.08, 0.12, gold, pale)
	var neck := _pivot(_body, "neck", Vector3(0, hip + 0.22, torso.z * 0.44))
	neck.rotation.x = deg_to_rad(-20.0)
	var head := _pivot(neck, "head", Vector3(0, 0.12, 0.2))
	var hs := 0.5 if mane else 0.46
	if mane:
		# The round dark-crowned ruff: five lobes, readable from above (section 4.2).
		_ball(head, 0.5, mane_c, Vector3(0, 0.02, -0.08), Vector3(1.05, 1.0, 0.75))
		for i in 6:
			var a := TAU * i / 6.0
			_ball(head, 0.17, mane_c.darkened(0.12), Vector3(cos(a) * 0.38, 0.02 + sin(a) * 0.34, -0.12))
	_ball(head, hs * 0.5, gold, Vector3(0, 0, 0.06), Vector3(1.0, 0.95, 0.95))
	_ball(head, 0.17, pale, Vector3(0, -0.08, 0.27), Vector3(1.3, 0.85, 0.9))     # muzzle
	_ball(head, 0.06, Color("#5a3a32"), Vector3(0, -0.01, 0.38), Vector3(1.3, 0.8, 0.8))   # nose
	if species == "lioness" or stripes:
		_ball(head, 0.12, WHITE, Vector3(0, -0.2, 0.2), Vector3(1.2, 0.7, 0.9))   # white chin
	if stripes:
		for side in [-1, 1]:
			_ball(head, 0.12, WHITE, Vector3(side * 0.2, -0.08, 0.14), Vector3(0.7, 1.0, 0.8))   # cheek ruffs
			Kit.part(head, _rbox(Vector3(0.05, 0.18, 0.05), 0.02), band, Vector3(side * 0.12, 0.17, 0.2), Vector3(0, 0, side * 20.0))
	_eyes(head, 0.07, 0.21, 0.11, 0.13)
	for side in [-1, 1]:
		_ball(head, 0.09, gold.darkened(0.05), Vector3(side * 0.17, 0.22, -0.02), Vector3(1.0, 1.0, 0.5))
		if stripes:
			_ball(head, 0.04, WHITE, Vector3(side * 0.17, 0.22, -0.06))   # a white spot on each ear back
	var jaw := _pivot(head, "jaw", Vector3(0, -0.13, 0.12))
	_ball(jaw, 0.13, pale, Vector3(0, -0.02, 0.1), Vector3(1.15, 0.5, 1.1))
	_ball(jaw, 0.08, Color("#d9737e"), Vector3(0, 0.03, 0.12), Vector3(1.0, 0.4, 1.0))   # the mouth inside
	_tail(Vector3(0, hip + 0.42, -torso.z * 0.5), 4, 0.24 if not stripes else 0.27, 0.06, gold, mane_c if not stripes else band, 0.1 if not stripes else 0.07, 3 if stripes else 0, band)
	size = Vector3(1.05 if mane else 0.7, 1.55 if mane else (1.4 if stripes else 1.35), long)
	_prop = _pivot(self, "prop", Vector3(0, 0.25, 0.9))
	_ball(_prop, 0.25, Color("#ec8fa3"), Vector3.ZERO)
	_prop.visible = false


# ---------------------------------------------------------------- savanna

## Giraffe: 2.8 m, shoulder 1.75, 2.0 long; a neck chain; large patches; two horns.
func _build_giraffe() -> void:
	var cream := Color("#f2d89c")
	var patch := Color("#b97437")
	Kit.blob_shadow(self, 0.95, 0.24)
	Kit.part(_body, _rbox(Vector3(0.6, 0.6, 1.3), 0.26), cream, Vector3(0, 1.45, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var x := (0.31 if i % 2 == 0 else -0.31)
		Kit.part(_body, _rbox(Vector3(0.06, 0.2, 0.24), 0.04), patch, Vector3(x, 1.4 + rng.randf_range(-0.12, 0.12), -0.5 + i * 0.12))
	for i in 4:
		Kit.part(_body, _rbox(Vector3(0.24, 0.05, 0.22), 0.04), patch, Vector3(rng.randf_range(-0.12, 0.12), 1.76, -0.45 + i * 0.3))
	for side in [-1, 1]:
		_leg("leg_f%s" % ("l" if side < 0 else "r"), Vector3(side * 0.2, 1.3, 0.45), 0.66, 0.62, 0.08, cream, Color("#6b4a32"))
		_leg("leg_b%s" % ("l" if side < 0 else "r"), Vector3(side * 0.2, 1.3, -0.45), 0.66, 0.62, 0.085, cream, Color("#6b4a32"))
	var n0 := _pivot(_body, "neck", Vector3(0, 1.65, 0.55))
	n0.rotation.x = deg_to_rad(-55.0)
	Kit.part(n0, _capsule(0.13, 0.62), cream, Vector3(0, 0.28, 0))
	Kit.part(n0, _rbox(Vector3(0.05, 0.16, 0.18), 0.03), patch, Vector3(0.13, 0.3, 0.0))
	var n1 := _pivot(n0, "neck1", Vector3(0, 0.56, 0))
	Kit.part(n1, _capsule(0.11, 0.56), cream, Vector3(0, 0.26, 0))
	Kit.part(n1, _rbox(Vector3(0.05, 0.14, 0.16), 0.03), patch, Vector3(-0.11, 0.24, 0.0))
	Kit.part(n1, _rbox(Vector3(0.05, 0.4, 0.06), 0.02), patch.darkened(0.2), Vector3(0, 0.2, -0.1))   # mane line
	var head := _pivot(n1, "head", Vector3(0, 0.56, 0))
	head.rotation.x = deg_to_rad(55.0)
	_ball(head, 0.18, cream, Vector3(0, 0.02, 0.08), Vector3(1.0, 1.0, 1.4))
	_ball(head, 0.12, cream.darkened(0.06), Vector3(0, -0.04, 0.3), Vector3(1.0, 0.9, 1.1))
	_eyes(head, 0.06, 0.15, 0.13, 0.12)
	for side in [-1, 1]:
		Kit.part(head, _capsule(0.03, 0.18), cream, Vector3(side * 0.07, 0.2, -0.02))
		_ball(head, 0.045, Color("#4a3428"), Vector3(side * 0.07, 0.3, -0.02))   # dark-tipped horns
		var ear := _pivot(head, "ear_%s" % ("l" if side < 0 else "r"), Vector3(side * 0.17, 0.1, -0.04))
		_ball(ear, 0.07, cream, Vector3(side * 0.05, 0, 0), Vector3(1.4, 0.6, 0.6))
	var jaw := _pivot(head, "jaw", Vector3(0, -0.1, 0.25))
	_ball(jaw, 0.08, cream.darkened(0.04), Vector3(0, -0.02, 0.06), Vector3(1.1, 0.5, 1.3))
	_tail(Vector3(0, 1.62, -0.66), 3, 0.24, 0.035, cream, Color("#4a3428"), 0.07)
	size = Vector3(0.7, 2.8, 2.0)
	_prop = _pivot(self, "prop", Vector3(0, 2.3, 0.9))
	_ball(_prop, 0.16, Color("#7fb069"), Vector3.ZERO, Vector3(1.4, 0.8, 1.0))
	_prop.visible = false


## Zebra: 1.65 m at the ears, 1.9 long; five body bands, two neck bands, an upright mane crest.
func _build_zebra() -> void:
	var white := Color("#f4f1ea")
	var black := Color("#33302e")
	Kit.blob_shadow(self, 0.8, 0.24)
	Kit.part(_body, _rbox(Vector3(0.52, 0.5, 1.25), 0.22), white, Vector3(0, 1.0, 0))
	for i in 5:
		Kit.part(_body, _rbox(Vector3(0.56, 0.12, 0.12), 0.04), black, Vector3(0, 1.08, 0.42 - i * 0.2), Vector3(10.0 * (i - 2), 0, 0))
	for side in [-1, 1]:
		_leg("leg_f%s" % ("l" if side < 0 else "r"), Vector3(side * 0.16, 0.86, 0.42), 0.42, 0.44, 0.075, white, black)
		_leg("leg_b%s" % ("l" if side < 0 else "r"), Vector3(side * 0.16, 0.86, -0.42), 0.42, 0.44, 0.08, white, black)
	var neck := _pivot(_body, "neck", Vector3(0, 1.08, 0.55))
	neck.rotation.x = deg_to_rad(-38.0)
	Kit.part(neck, _capsule(0.13, 0.52), white, Vector3(0, 0.22, 0))
	for i in 2:
		Kit.part(neck, _rbox(Vector3(0.28, 0.09, 0.28), 0.04), black, Vector3(0, 0.12 + i * 0.2, 0))
	Kit.part(neck, _rbox(Vector3(0.07, 0.5, 0.12), 0.03), black, Vector3(0, 0.26, -0.13))   # the upright crest
	var head := _pivot(neck, "head", Vector3(0, 0.36, 0.04))
	head.rotation.x = deg_to_rad(70.0)
	_ball(head, 0.16, white, Vector3(0, 0, 0.08), Vector3(1.0, 1.0, 1.5))
	_ball(head, 0.12, black, Vector3(0, -0.04, 0.32), Vector3(1.0, 0.9, 0.9))   # dark muzzle
	_eyes(head, 0.06, 0.12, 0.12, 0.12)
	for side in [-1, 1]:
		Kit.part(head, _capsule(0.045, 0.16), white, Vector3(side * 0.09, 0.21, -0.04))
		_ball(head, 0.04, black, Vector3(side * 0.09, 0.29, -0.04))
	var jaw := _pivot(head, "jaw", Vector3(0, -0.09, 0.26))
	_ball(jaw, 0.08, black.lightened(0.1), Vector3(0, -0.02, 0.04), Vector3(1.0, 0.5, 1.2))
	_tail(Vector3(0, 1.12, -0.64), 3, 0.18, 0.035, white, black, 0.07)
	size = Vector3(0.6, 1.65, 1.9)
	_prop = _pivot(self, "prop", Vector3(0, 1.0, 0.95))
	Kit.part(_prop, _rbox(Vector3(0.3, 0.16, 0.2), 0.05), Color("#e3c56b"), Vector3.ZERO)
	_prop.visible = false


# ---------------------------------------------------------------- Splash Bay

## Hippo: 1.35 m, 2.3 long, 1.2 wide; a barrel body, a wide square muzzle, ears that twirl,
## four peg teeth, a pink mouth.
func _build_hippo() -> void:
	var grey := Color("#9d8fb0")
	var pink := Color("#ef9fae")
	Kit.blob_shadow(self, 1.05, 0.24)
	Kit.part(_body, _rbox(Vector3(1.15, 0.85, 1.7), 0.4), grey, Vector3(0, 0.72, 0))
	_ball(_body, 0.45, grey.lightened(0.08), Vector3(0, 0.42, 0.05), Vector3(1.15, 0.5, 1.6))
	for side in [-1, 1]:
		_leg("leg_f%s" % ("l" if side < 0 else "r"), Vector3(side * 0.36, 0.42, 0.52), 0.22, 0.24, 0.15, grey, grey.darkened(0.1))
		_leg("leg_b%s" % ("l" if side < 0 else "r"), Vector3(side * 0.36, 0.42, -0.52), 0.22, 0.24, 0.16, grey, grey.darkened(0.1))
	var neck := _pivot(_body, "neck", Vector3(0, 0.78, 0.8))
	var head := _pivot(neck, "head", Vector3(0, 0.06, 0.18))
	Kit.part(head, _rbox(Vector3(0.78, 0.48, 0.62), 0.22), grey, Vector3(0, 0.08, 0.12))
	Kit.part(head, _rbox(Vector3(0.92, 0.36, 0.42), 0.18), grey.lightened(0.06), Vector3(0, -0.04, 0.5))   # wide muzzle
	for side in [-1, 1]:
		_ball(head, 0.05, DARK, Vector3(side * 0.18, 0.08, 0.72), Vector3(1.2, 0.8, 0.5))   # nostrils
	_eyes(head, 0.3, 0.2, 0.22, 0.13)
	for side in [-1, 1]:
		var ear := _pivot(head, "ear_%s" % ("l" if side < 0 else "r"), Vector3(side * 0.26, 0.36, -0.06))
		_ball(ear, 0.07, grey.darkened(0.08), Vector3(0, 0.03, 0), Vector3(1.0, 1.0, 0.6))
	var jaw := _pivot(head, "jaw", Vector3(0, -0.2, 0.2))
	Kit.part(jaw, _rbox(Vector3(0.84, 0.18, 0.62), 0.08), grey.darkened(0.04), Vector3(0, -0.06, 0.24))
	Kit.part(jaw, _rbox(Vector3(0.7, 0.06, 0.5), 0.03), pink, Vector3(0, 0.04, 0.24))
	for x in [-0.28, -0.1, 0.1, 0.28]:
		Kit.part(jaw, _rbox(Vector3(0.07, 0.12, 0.07), 0.03), WHITE, Vector3(x, 0.08, 0.48))   # peg teeth
	_tail(Vector3(0, 0.88, -0.86), 2, 0.12, 0.05, grey, grey.darkened(0.15), 0.05)
	size = Vector3(1.2, 1.35, 2.3)
	_prop = _pivot(self, "prop", Vector3(0, 0.6, 1.4))
	_ball(_prop, 0.22, Color("#7fbf6a"), Vector3.ZERO)
	_ball(_prop, 0.18, Color("#ef7f8a"), Vector3(0, 0.02, 0.05))
	_prop.visible = false


## Otter, enlarged (section 22.5 item 2): 1.30 m standing, at least 0.85 m on all fours with the
## head up; cream face and throat, a big nose, a thick tapered tail, paws held together.
func _build_otter() -> void:
	var brown := Color("#8c5a37") if variant == 0 else Color("#7b4f33")
	var cream := Color("#f1dcb6")
	Kit.blob_shadow(self, 0.55, 0.24)
	# The body pivot stands at the hips; standing upright is the usual pose near children.
	_body.position = Vector3(0, 0.3, 0)
	var chest := _pivot(_body, "chest", Vector3(0, 0.0, 0))
	Kit.part(chest, _capsule(0.24, 0.72), brown, Vector3(0, 0.32, 0))
	_ball(chest, 0.2, cream, Vector3(0, 0.46, 0.1), Vector3(1.0, 1.6, 0.8))   # throat and belly
	var head := _pivot(chest, "head", Vector3(0, 0.78, 0.02))
	_ball(head, 0.2, brown, Vector3(0, 0.05, 0), Vector3(1.05, 0.95, 1.0))
	_ball(head, 0.15, cream, Vector3(0, -0.02, 0.12), Vector3(1.2, 0.85, 0.8))   # cream face
	_ball(head, 0.065, DARK, Vector3(0, 0.03, 0.27), Vector3(1.3, 0.9, 0.8))   # the big nose
	_eyes(head, 0.11, 0.15, 0.09, 0.12)
	for side in [-1, 1]:
		_ball(head, 0.05, brown.darkened(0.1), Vector3(side * 0.17, 0.14, -0.02))
	var jaw := _pivot(head, "jaw", Vector3(0, -0.08, 0.14))
	_ball(jaw, 0.07, cream, Vector3(0, -0.02, 0.04), Vector3(1.2, 0.5, 1.0))
	for side in [-1, 1]:
		var arm := _pivot(chest, "arm_%s" % ("l" if side < 0 else "r"), Vector3(side * 0.2, 0.56, 0.08))
		arm.rotation.x = deg_to_rad(-50.0)
		Kit.part(arm, _capsule(0.07, 0.24), brown, Vector3(0, -0.1, 0))
		var fore := _pivot(arm, "fore_%s" % ("l" if side < 0 else "r"), Vector3(0, -0.22, 0))
		Kit.part(fore, _capsule(0.065, 0.2), brown, Vector3(0, -0.08, 0))
		_ball(fore, 0.07, brown.darkened(0.12), Vector3(0, -0.2, 0.02))
		_leg("leg_%s" % ("l" if side < 0 else "r"), Vector3(side * 0.14, 0.02, 0.0), 0.16, 0.14, 0.08, brown, brown.darkened(0.12))
	_tail(Vector3(0, 0.0, -0.18), 3, 0.2, 0.11, brown, brown.darkened(0.08), 0.06)
	size = Vector3(0.5, 1.3, 1.3)
	_prop = _pivot(self, "prop", Vector3(0, 1.05, 0.3))
	_ball(_prop, 0.08, Color("#b7b2a8"), Vector3.ZERO)
	_prop.visible = false


# ---------------------------------------------------------------- monkeys

const MONKEY_COLORS := [Color("#9a6a43"), Color("#b8834f"), Color("#7d5a46"), Color("#a7855f"), Color("#c4945c")]


## Monkey (section 6.3, 22.4): 1.10 m sitting, long arms and tail, a pale face disc of 0.34 m,
## round ears; five flat colour variants; Bibi is the young one (0.78 of the size). The body
## root is the feet (the anchor point); hanging actions are drawn from the hands.
func _build_monkey() -> void:
	var fur: Color = MONKEY_COLORS[variant % MONKEY_COLORS.size()]
	var face := Color("#f2d6b0")
	Kit.blob_shadow(self, 0.45, 0.22)
	var hips := _pivot(_body, "hips", Vector3(0, 0.62, 0))
	var chest := _pivot(hips, "chest", Vector3.ZERO)
	Kit.part(chest, _capsule(0.21, 0.6), fur, Vector3(0, 0.27, 0))
	_ball(chest, 0.15, face.darkened(0.04), Vector3(0, 0.26, 0.1), Vector3(1.0, 1.5, 0.7))   # pale tummy
	var head := _pivot(chest, "head", Vector3(0, 0.6, 0.02))
	_ball(head, 0.22, fur, Vector3(0, 0.08, -0.02))
	_ball(head, 0.17, face, Vector3(0, 0.06, 0.1), Vector3(1.0, 1.0, 0.65))   # the face disc
	_ball(head, 0.09, face.darkened(0.05), Vector3(0, -0.02, 0.2), Vector3(1.3, 0.8, 0.8))   # snout
	_ball(head, 0.03, DARK, Vector3(0, 0.01, 0.28))
	_eyes(head, 0.1, 0.19, 0.075, 0.12)
	for side in [-1, 1]:
		_ball(head, 0.08, fur.darkened(0.06), Vector3(side * 0.23, 0.1, -0.02), Vector3(0.6, 1.0, 1.0))
		_ball(head, 0.05, face, Vector3(side * 0.25, 0.1, -0.01), Vector3(0.5, 1.0, 1.0))
	var jaw := _pivot(head, "jaw", Vector3(0, -0.06, 0.16))
	_ball(jaw, 0.06, face.darkened(0.08), Vector3(0, -0.02, 0.04), Vector3(1.3, 0.5, 1.0))
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var arm := _pivot(chest, "arm_" + s, Vector3(side * 0.22, 0.48, 0.0))
		Kit.part(arm, _capsule(0.06, 0.4), fur, Vector3(0, -0.19, 0))
		var fore := _pivot(arm, "fore_" + s, Vector3(0, -0.38, 0))
		Kit.part(fore, _capsule(0.055, 0.38), fur, Vector3(0, -0.18, 0))
		_ball(fore, 0.075, face.darkened(0.1), Vector3(0, -0.4, 0))   # the hand
		var thigh := _pivot(hips, "leg_" + s, Vector3(side * 0.12, -0.02, 0.0))
		Kit.part(thigh, _capsule(0.065, 0.32), fur, Vector3(0, -0.15, 0))
		var shin := _pivot(thigh, "leg_%s_low" % s, Vector3(0, -0.3, 0))
		Kit.part(shin, _capsule(0.058, 0.3), fur, Vector3(0, -0.14, 0))
		_ball(shin, 0.08, face.darkened(0.1), Vector3(0, -0.29, 0.05), Vector3(1.0, 0.6, 1.4))
	# The long tail: a chain that curls.
	var t := _pivot(hips, "tail0", Vector3(0, 0.05, -0.18))
	t.rotation.x = deg_to_rad(35.0)
	for i in 3:
		Kit.part(t, _capsule(0.045 - i * 0.006, 0.36), fur, Vector3(0, 0, -0.16), Vector3(90, 0, 0))
		if i < 2:
			t = _pivot(t, "tail%d" % (i + 1), Vector3(0, 0, -0.32))
	size = Vector3(0.6, 1.66, 0.5)
	_prop = _pivot(self, "prop", Vector3(0, 1.6, 0.3))
	_ball(_prop, 0.13, Color("#ec8fa3"), Vector3.ZERO)
	_prop.visible = false


# ---------------------------------------------------------------- posing

func _process(delta: float) -> void:
	_t += delta
	_pose(delta)


## Every pivot's target this frame: name -> Euler angles (radians). The body also gets an offset.
func _pose(delta: float) -> void:
	var target := {}
	var body_off := Vector3.ZERO
	var body_rot := Vector3.ZERO
	var t := _t + _phase
	var amp := 0.6 if reduce_motion else 1.0
	if _prop:
		_prop.visible = false
	if species == "monkey":
		_pose_monkey(target, t, amp)
		body_off = target.get("_off", Vector3.ZERO)
		body_rot = target.get("_rot", Vector3.ZERO)
	else:
		_pose_animal(target, t, amp)
		body_off = target.get("_off", Vector3.ZERO)
		body_rot = target.get("_rot", Vector3.ZERO)
	var rate := minf(1.0, delta * 10.0)
	_body.position = _body.position.lerp(_base_body() + body_off, rate)
	_body.rotation = _body.rotation.lerp(body_rot, rate)
	for k in _pivots:
		if k == "body" or k == "prop":
			continue
		var n: Node3D = _pivots[k]
		var goal: Vector3 = _rest[k] + target.get(k, Vector3.ZERO)
		n.rotation = n.rotation.lerp(goal, rate)
	if not _skin.is_empty():
		if _skin_script == null:
			_skin_script = load(SKIN_SCRIPT)
		_skin_script.sync(_skin["skeleton"], _skin["pivots"])


func _base_body() -> Vector3:
	return Vector3(0, 0.3, 0) if species == "otter" else Vector3.ZERO


func _legs_walk(target: Dictionary, t: float, speed: float, swing: float, knee: float) -> void:
	var s := sin(t * speed)
	for k in ["leg_fl", "leg_br"]:
		target[k] = Vector3(s * swing, 0, 0)
		target[k + "_low"] = Vector3(maxf(0.0, -s) * knee, 0, 0)
	for k in ["leg_fr", "leg_bl"]:
		target[k] = Vector3(-s * swing, 0, 0)
		target[k + "_low"] = Vector3(maxf(0.0, s) * knee, 0, 0)


func _tail_sway(target: Dictionary, t: float, a: float, speed: float) -> void:
	for i in 5:
		target["tail%d" % i] = Vector3(0, sin(t * speed - i * 0.6) * a, 0)


## Four-legged and water animals: lion, lioness, tiger, giraffe, zebra, hippo, otter.
func _pose_animal(target: Dictionary, t: float, amp: float) -> void:
	if species in ["panda", "elephant", "penguin"]:
		# zoo r2's new species: their poses live in zoo_pose_extra.gd (W6), on the same pivot model.
		if _pose_extra == null and ResourceLoader.exists(POSE_EXTRA_SCRIPT):
			_pose_extra = load(POSE_EXTRA_SCRIPT)
		if _pose_extra != null:
			_pose_extra.pose(species, action, target, t, amp, u, 0.0, reduce_motion)   # t carries this animal's phase
		return
	var off := Vector3(0, sin(t * 1.6) * 0.012, 0)   # breathing
	var rot := Vector3.ZERO
	_tail_sway(target, t, 0.25, 1.4)
	var ears := sin(t * 1.3) * 0.08
	target["ear_l"] = Vector3(0, 0, ears)
	target["ear_r"] = Vector3(0, 0, -ears)
	var lie := func(depth: float):
		for k in ["leg_fl", "leg_fr"]:
			target[k] = Vector3(-1.2, 0, 0)
			target[k + "_low"] = Vector3(1.0, 0, 0)
		for k in ["leg_bl", "leg_br"]:
			target[k] = Vector3(1.1, 0, 0)
			target[k + "_low"] = Vector3(-1.3, 0, 0)
		off.y -= depth
	var sit := func():
		for k in ["leg_bl", "leg_br"]:
			target[k] = Vector3(1.2, 0, 0)
			target[k + "_low"] = Vector3(-1.4, 0, 0)
		rot.x = -0.32
		off.y -= 0.12
	var otter := species == "otter"
	match action:
		"walk", "prowl", "trot", "patrol", "show_walk", "step_back", "canter":
			var spd: float = {"walk": 6.0, "prowl": 4.5, "trot": 9.0, "patrol": 6.0, "show_walk": 4.0, "step_back": 7.0, "canter": 11.0}[action]
			_legs_walk(target, t, spd, 0.5 * amp, 0.7 * amp)
			off.y += absf(sin(t * spd)) * 0.03 * amp
			if action == "prowl" or action == "show_walk":
				off.y -= 0.12   # low and slinky
				target["neck"] = Vector3(0.25, 0, 0)
				_tail_sway(target, t, 0.45, 2.0)
			if action == "canter":
				off.y += absf(sin(t * 5.5)) * 0.12 * amp
			if otter:
				rot.x = 1.15   # down on all fours to walk
		"gallop":
			var g := sin(t * 13.0)
			for k in ["leg_fl", "leg_fr"]:
				target[k] = Vector3(g * 0.9 * amp, 0, 0)
				target[k + "_low"] = Vector3(maxf(0.0, -g) * 1.0, 0, 0)
			for k in ["leg_bl", "leg_br"]:
				target[k] = Vector3(-g * 0.9 * amp, 0, 0)
				target[k + "_low"] = Vector3(maxf(0.0, g) * 1.0, 0, 0)
			off.y += absf(sin(t * 6.5)) * 0.16 * amp
			target["neck"] = Vector3(0.3, 0, 0)
		"bask", "nap", "soak", "hide":
			lie.call(0.38 if species in ["lion", "lioness", "tiger"] else 0.25)
			if action == "nap":
				target["neck"] = Vector3(0.45, 0, 0)
				target["head"] = Vector3(0.2, 0.4, 0)
			if action == "hide":
				off.y -= 0.12
				target["neck"] = Vector3(0.35, 0, 0)
		"survey", "look", "blink", "nod", "chuff", "full", "puzzled":
			if species in ["lion", "lioness", "tiger"]:
				sit.call()
			if action == "look":
				target["neck"] = Vector3(-0.15, sin(t * 0.8) * 0.6, 0)
			if action == "nod":
				target["head"] = Vector3(absf(sin(t * 3.0)) * 0.4 * amp, 0, 0)
			if action == "chuff":
				target["jaw"] = Vector3(absf(sin(t * 6.0)) * 0.25, 0, 0)
			if action == "puzzled":
				target["head"] = Vector3(0, 0, 0.35)
			if action == "full":
				target["jaw"] = Vector3(0.15, 0, 0)
				rot.z = sin(t * 2.0) * 0.08
		"yawn", "roar", "chomp", "fountain":
			if species in ["lion", "lioness", "tiger"]:
				sit.call()
			var open := sin(clampf(u, 0.0, 1.0) * PI)
			var deg: float = {"yawn": 55.0, "roar": 50.0, "chomp": 60.0, "fountain": 35.0}[action]
			target["jaw"] = Vector3(deg_to_rad(deg) * open * (0.7 if reduce_motion else 1.0), 0, 0)
			target["neck"] = Vector3(-0.35 * open, 0, 0)
			if action == "roar":
				target["head"] = Vector3(-0.15, sin(t * 18.0) * 0.06 * open * amp, 0)   # the mane shakes
		"roll", "dust_roll", "pounce", "hug_kick":
			if action == "pounce":
				var k := clampf(u, 0.0, 1.0)
				off.y += sin(k * PI) * 0.45 * amp
				rot.x = lerpf(0.25, -0.2, k)
				_legs_walk(target, t, 0.0, 0.0, 0.0)
			else:
				lie.call(0.3)
				rot.z = sin(clampf(u, 0.0, 1.0) * TAU) * 1.8 * amp
				for k in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
					target[k] = Vector3(-0.9 + sin(t * 9.0) * 0.4 * amp, 0, 0)
		"stalk", "peekaboo", "sit_on", "scratch_log", "pat":
			off.y -= 0.18
			target["neck"] = Vector3(0.2, 0, 0)
			_tail_sway(target, t, 0.6, 5.0)
			if action == "peekaboo":
				var rise := smoothstep(0.1, 0.5, u) * (1.0 - smoothstep(0.85, 1.0, u))
				off.y = lerpf(-0.6, -0.15, rise)   # the ears first, then the eyes, rise out of the stalks
			if action == "sit_on":
				sit.call()
				off.y += 0.8
			if action in ["scratch_log", "pat"]:
				target["leg_fl"] = Vector3(-1.3 + sin(t * 8.0) * 0.3, 0, 0)
				target["leg_fr"] = Vector3(-1.1 - sin(t * 8.0) * 0.3, 0, 0)
		"stretch":
			rot.x = -0.7
			off.y += 0.35
			for k in ["leg_fl", "leg_fr"]:
				target[k] = Vector3(-2.0, 0, 0)
				target[k + "_low"] = Vector3(-0.2 + sin(t * 6.0) * 0.2, 0, 0)
		"lick", "groom", "eat", "tongue", "graze", "browse", "drink", "belly_eat":
			var head_down: float = {"lick": 0.5, "groom": 0.6, "eat": 0.6, "tongue": -0.3, "graze": 1.0, "browse": -0.25, "drink": 1.1, "belly_eat": 0.0}[action]
			target["neck"] = Vector3(head_down, 0, 0)
			target["jaw"] = Vector3(absf(sin(t * 5.0)) * 0.2, 0, 0)
			if action == "drink" and species == "giraffe":
				target["leg_fl"] = Vector3(0, 0, 0.35)   # front legs splayed
				target["leg_fr"] = Vector3(0, 0, -0.35)
				target["neck1"] = Vector3(0.9, 0, 0)
				off.y -= 0.35
			if action in ["lick", "eat", "tongue", "belly_eat"]:
				_prop.visible = true
			if action == "belly_eat":
				rot.x = -1.4   # floats on its back
				off.y -= 0.3
		"bow":
			target["neck"] = Vector3(1.0 * smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.85, 1.0, u)), 0, 0)
			target["neck1"] = Vector3(0.6 * smoothstep(0.0, 0.3, u), 0, 0)
		"buck", "prance", "toss":
			rot.x = -sin(clampf(u, 0.0, 1.0) * PI * (2.0 if action == "buck" else 1.0)) * 0.5 * amp
			target["neck"] = Vector3(-0.4 + sin(t * 7.0) * 0.3, 0, 0)
			if action == "prance":
				_legs_walk(target, t, 10.0, 0.6 * amp, 0.8)
		"shake", "bob", "twirl":
			if action == "shake" and species == "lion":
				# A mane shake: the head and neck, the body still (design 7.3).
				sit.call()
				target["neck"] = Vector3(0, 0, sin(t * 16.0) * 0.32 * amp)
				target["head"] = Vector3(0, sin(t * 16.0 + 0.6) * 0.28 * amp, 0)
			else:
				rot.z = sin(t * (22.0 if action == "shake" else 4.0)) * (0.25 if action == "shake" else 0.08) * amp
			if action == "twirl":
				target["ear_l"] = Vector3(0, t * 9.0, 0)
				target["ear_r"] = Vector3(0, -t * 9.0, 0)
		"swim", "float", "surface", "dive", "slide", "escort":
			if otter:
				rot.x = 1.35 if action in ["swim", "dive", "slide", "escort"] else -1.3   # on its back when floating
				if action == "dive":
					off.y -= sin(clampf(u, 0.0, 1.0) * PI) * 0.7 * amp
			else:
				_legs_walk(target, t, 3.0, 0.4, 0.4)
			if action == "surface":
				off.y += smoothstep(0.0, 0.4, u) * 0.35
		"pool_leap":
			rot.x = lerpf(-0.4, 0.5, clampf(u, 0.0, 1.0))
			for k in ["leg_fl", "leg_fr"]:
				target[k] = Vector3(-1.2, 0, 0)
			for k in ["leg_bl", "leg_br"]:
				target[k] = Vector3(1.0, 0, 0)
		"beg", "paws", "juggle", "push_ball":
			# The otter stands up: paws held together, or waving, or a pebble flying up.
			if otter:
				target["arm_l"] = Vector3(-1.2, 0, 0.3)
				target["arm_r"] = Vector3(-1.2, 0, -0.3)
				if action == "paws":
					target["arm_l"] = Vector3(-2.4, 0, 0.4 + sin(t * 9.0) * 0.4)
					target["arm_r"] = Vector3(-2.4, 0, -0.4 - sin(t * 9.0) * 0.4)
				if action == "juggle":
					_prop.visible = true
					_prop.position = Vector3(0, 1.05 + absf(sin(t * 4.0)) * 0.6 * amp, 0.3)
				if action == "push_ball":
					rot.x = 1.15
					_prop.visible = true
					_prop.position = Vector3(0, 0.15, 0.55)
			else:
				_prop.visible = action == "push_ball"
		"shower":
			target["neck"] = Vector3(-0.5, 0, 0)
			target["jaw"] = Vector3(0.6, 0, 0)
		_:
			pass
	# Otters stand upright by default (their usual pose near children: section 22.5 item 2).
	target["_off"] = off
	target["_rot"] = rot


## Monkeys: whole-body actions (section 22.4). The world places the root on the action's path
## (feet); here the limbs and body show climbing, hanging, swinging, leaping and play.
func _pose_monkey(target: Dictionary, t: float, amp: float) -> void:
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	var k := clampf(u, 0.0, 1.0)
	for i in 5:
		target["tail%d" % i] = Vector3(sin(t * 2.0 - i * 0.7) * 0.3, sin(t * 1.3 - i * 0.5) * 0.25, 0)
	var arms_up := func(l: float, r: float):
		target["arm_l"] = Vector3(-l, 0, 0.15)
		target["arm_r"] = Vector3(-r, 0, -0.15)
	match action:
		"run", "chase", "follow", "walk":
			var spd := 12.0 if action != "follow" else 9.0
			var s := sin(t * spd)
			rot.x = 0.55   # knuckle-walking, on all fours
			off.y -= 0.16
			target["arm_l"] = Vector3(-0.9 + s * 0.6 * amp, 0, 0)
			target["arm_r"] = Vector3(-0.9 - s * 0.6 * amp, 0, 0)
			target["leg_l"] = Vector3(-s * 0.7 * amp, 0, 0)
			target["leg_r"] = Vector3(s * 0.7 * amp, 0, 0)
			target["leg_l_low"] = Vector3(maxf(0.0, s) * 0.9, 0, 0)
			target["leg_r_low"] = Vector3(maxf(0.0, -s) * 0.9, 0, 0)
			off.y += absf(s) * 0.05 * amp
		"climb":
			var s := sin(t * 9.0)
			arms_up.call(2.6 + s * 0.4, 2.6 - s * 0.4)   # hands reach up in turn
			target["leg_l"] = Vector3(-1.0 - s * 0.5, 0, 0)
			target["leg_r"] = Vector3(-1.0 + s * 0.5, 0, 0)
			target["leg_l_low"] = Vector3(1.2, 0, 0)
			target["leg_r_low"] = Vector3(1.2, 0, 0)
			rot.x = -0.15
		"descend":
			if k < 0.7:
				rot.x = PI * 0.92   # head first down the pole
				off.y += 1.2
				var s := sin(t * 9.0)
				arms_up.call(2.4 + s * 0.4, 2.4 - s * 0.4)
			else:
				rot.x = lerpf(PI * 0.92, TAU, (k - 0.7) / 0.3) if not reduce_motion else 0.0   # the flip to land
				off.y += lerpf(1.2, 0.0, (k - 0.7) / 0.3)
		"rings", "vine", "tyre":
			# Hanging: the body hangs from the hands, HANG (1.55 m) above the feet.
			arms_up.call(3.05, 3.05)
			if action == "rings":
				var s := sin(k * PI * 6.0)
				arms_up.call(3.05 + maxf(0.0, s) * 0.3, 3.05 + maxf(0.0, -s) * 0.3)
				rot.z = s * 0.35 * amp   # the pendulum from the holding hand
				target["arm_l"] = Vector3(-3.05, 0, 0.15 + maxf(0.0, s) * 0.5)
				target["arm_r"] = Vector3(-3.05, 0, -0.15 - maxf(0.0, -s) * 0.5)
			if action == "vine" and k > 0.75:
				arms_up.call(2.2, 2.2)   # let go: arms forward in the flight
				target["leg_l_low"] = Vector3(1.4, 0, 0)
				target["leg_r_low"] = Vector3(1.4, 0, 0)
			if action == "tyre":
				arms_up.call(2.9, 2.9)
				rot.x = sin(t * 2.6) * (0.25 + param * 0.15) * amp
				target["leg_l"] = Vector3(-1.4, 0, 0)
				target["leg_r"] = Vector3(-1.4, 0, 0)
				target["leg_l_low"] = Vector3(1.5, 0, 0)
				target["leg_r_low"] = Vector3(1.5, 0, 0)
			else:
				target["leg_l"] = Vector3(-0.5, 0, 0)
				target["leg_r"] = Vector3(-0.3, 0, 0)
				target["leg_l_low"] = Vector3(0.9, 0, 0)
				target["leg_r_low"] = Vector3(0.7, 0, 0)
		"leap", "hop", "drop", "catch":
			var crouch := 1.0 - smoothstep(0.0, 0.12, k) if k < 0.15 else smoothstep(0.85, 1.0, k)
			off.y -= crouch * 0.18
			if k > 0.12 and k < 0.88:
				arms_up.call(2.3, 2.3)   # stretch in the air, then tuck
				target["leg_l"] = Vector3(-1.0, 0, 0)
				target["leg_r"] = Vector3(-1.0, 0, 0)
				target["leg_l_low"] = Vector3(1.3, 0, 0)
				target["leg_r_low"] = Vector3(1.3, 0, 0)
			if action == "catch":
				_prop.visible = true
				off.y += sin(k * PI) * 0.7 * amp
		"balance":
			target["arm_l"] = Vector3(0, 0, 1.45 + sin(t * 2.0) * 0.15)   # arms out
			target["arm_r"] = Vector3(0, 0, -1.45 + sin(t * 2.0) * 0.15)
			rot.z = sin(t * 2.4) * 0.12 * amp   # a wobble
			var s := sin(t * 5.0)
			target["leg_l"] = Vector3(s * 0.4, 0, 0)
			target["leg_r"] = Vector3(-s * 0.4, 0, 0)
			for i in 5:
				target["tail%d" % i] = Vector3(-0.3, sin(t * 2.4 + i) * 0.5, 0)   # the tail as a counterweight
		"sit_dangle", "eat", "groomed":
			off.y -= 0.32
			target["leg_l"] = Vector3(-1.5, 0, 0)
			target["leg_r"] = Vector3(-1.5, 0, 0)
			target["leg_l_low"] = Vector3(1.2 + sin(t * 3.0) * 0.4, 0, 0)   # legs swing over the edge
			target["leg_r_low"] = Vector3(1.2 - sin(t * 3.0) * 0.4, 0, 0)
			target["head"] = Vector3(0, sin(t * 0.7) * 0.6, 0)
			if action == "eat":
				_prop.visible = true
				_prop.position = Vector3(0.15, 1.0, 0.25)
				target["arm_r"] = Vector3(-1.8 + sin(t * 4.0) * 0.3, 0, 0)
		"tail_hang":
			rot.x = PI   # upside down, hanging by the tail
			off.y += 1.75
			target["arm_l"] = Vector3(-0.3 + sin(t * 3.0) * 0.6 * amp, 0, 0.3)
			target["arm_r"] = Vector3(-0.3 - sin(t * 3.0) * 0.6 * amp, 0, -0.3)
			for i in 5:
				target["tail%d" % i] = Vector3(-0.6, 0, 0)
		"peek":
			var out := sin(k * PI)
			off.x = out * 0.35   # leans out from behind its post
			rot.z = -out * 0.4
			target["head"] = Vector3(0, -out * 0.3, out * 0.3)
			target["ear_l"] = Vector3(0, 0, out * 0.3)
		"play_ball", "pass":
			_prop.visible = true
			var toss := absf(sin(t * 3.0))
			_prop.position = Vector3(0, 1.3 + toss * 0.9 * amp, 0.25)
			arms_up.call(1.6 + toss * 1.2, 1.6 + toss * 1.2)
			if action == "pass":
				_prop.position = Vector3(0, 1.2 + sin(k * PI) * 1.4, 0.25 + sin(k * PI) * 1.5)
		"somersault":
			if reduce_motion:
				off.y += sin(k * PI) * 0.35   # a hop instead (section 22.4)
			else:
				rot.x = k * TAU
				off.y += sin(k * PI) * 0.65
			target["leg_l_low"] = Vector3(1.4, 0, 0)
			target["leg_r_low"] = Vector3(1.4, 0, 0)
		"groom":
			off.y -= 0.32
			target["arm_l"] = Vector3(-1.4 + sin(t * 6.0) * 0.25, 0, 0.3)
			target["arm_r"] = Vector3(-1.2 - sin(t * 6.0) * 0.25, 0, -0.3)
			target["head"] = Vector3(0.35, 0, 0)
			target["leg_l"] = Vector3(-1.5, 0, 0)
			target["leg_r"] = Vector3(-1.5, 0, 0)
		"scratch":
			target["arm_r"] = Vector3(-2.6, 0, -0.6 + sin(t * 10.0) * 0.25)
			target["head"] = Vector3(0, 0, 0.3)
		"look_around":
			target["head"] = Vector3(0, sin(t * 0.9) * 0.9, 0)
			off.y -= 0.1
		"copy", "pose", "faces", "drum", "bell":
			var e := int(param)
			if action == "copy" and e == 0 or action == "faces":   # wave
				target["arm_r"] = Vector3(-2.7, 0, -0.4 + sin(t * 10.0) * 0.5)
			elif action == "copy" and e == 1 or action == "pose":   # cheer: a jump, arms up
				arms_up.call(3.0, 3.0)
				off.y += absf(sin(t * 6.0)) * 0.3 * amp
			elif action == "copy" and e == 2:   # dance: a spin with long arms
				rot.y = t * 6.0 * amp
				target["arm_l"] = Vector3(0, 0, 1.4)
				target["arm_r"] = Vector3(0, 0, -1.4)
				off.y += absf(sin(t * 8.0)) * 0.15
			elif action == "copy" and e == 3:   # heart: a hug
				target["arm_l"] = Vector3(-1.5, 0.9, 0)
				target["arm_r"] = Vector3(-1.5, -0.9, 0)
			elif action == "drum":
				off.y -= 0.3
				target["arm_l"] = Vector3(-1.2 + maxf(0.0, sin(t * 12.0)) * 0.8, 0, 0)
				target["arm_r"] = Vector3(-1.2 + maxf(0.0, -sin(t * 12.0)) * 0.8, 0, 0)
			elif action == "bell":
				target["arm_r"] = Vector3(-2.9 + sin(t * 8.0) * 0.5, 0, 0)
				arms_up.call(1.0, 2.9 + sin(t * 8.0) * 0.5)
		_:
			target["head"] = Vector3(0, sin(t * 0.5) * 0.3, 0)
	target["_off"] = off
	target["_rot"] = rot


## The model's height in its usual pose, for the readability tests (section 22.5 item 2).
func usual_height() -> float:
	if species == "monkey":
		return 1.1 * (0.78 if young else 1.0)
	return size.y
