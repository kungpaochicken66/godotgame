## A friendly animal: soft primitive model plus procedural animation per action.
##
## Static parts are merged into a few meshes; legs, head, ears, tail and trunk
## stay separate so they can move. Effects (splash drops, music notes, the dog's
## ball, water spray) are tiny and only shown while their action plays.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")

var kind := ""
var action := "idle"
var _t := 0.0
var _target_pos := Vector3.ZERO
var _target_ry := 0.0
var _ball_target := Vector3.ZERO
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _tail: Node3D
var _trunk: Node3D
var _ball: Node3D
var _fx: CPUParticles3D
var _label: Label3D
var _react_t := 0.0
var _hop_phase := 0.0


func setup(species: String) -> void:
	kind = species
	_body = Node3D.new()
	add_child(_body)
	match kind:
		"pig": _build_pig()
		"rabbit": _build_rabbit()
		"sheep": _build_sheep()
		"dog": _build_dog()
		"elephant": _build_elephant()
	Kit.merge_parts(self)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0035
	_label.font_size = 40
	_label.outline_size = 12
	_label.modulate = Color("#7a5a3a")
	_label.outline_modulate = Color("#fffdf6")
	_label.position.y = 1.0 if kind != "elephant" else 2.0
	_label.visible = false
	add_child(_label)
	refresh_label()


func refresh_label() -> void:
	_label.text = tr(AnimalBrain.SPECIES[kind]["name"])
	_label.font = I18n.ui_font()


func show_name(on: bool) -> void:
	_label.visible = on


func set_state(s: Dictionary, snap := false) -> void:
	_target_pos = Vector3(s["pos"].x, 0, s["pos"].y)
	_target_ry = s["ry"]
	action = s["action"]
	_ball_target = Vector3(s["ball"].x, 0.12, s["ball"].y)
	if snap:
		position = _target_pos
		rotation.y = _target_ry
		if _ball:
			_ball.global_position = _ball_target


## A happy reaction when a child taps the animal (local only).
func react() -> void:
	_react_t = 1.2


# ------------------------------------------------------------- models

func _leg(pos: Vector3, length: float, radius: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_body.add_child(pivot)
	Kit.part(pivot, Kit.capsule(radius, length), color, Vector3(0, -length * 0.5 + radius * 0.5, 0))
	_legs.append(pivot)
	return pivot


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _eyes(head: Node3D, y: float, z: float, spread: float, size := 0.035) -> void:
	for side in [-1, 1]:
		Kit.ball(head, size, Color("#2b2320"), Vector3(side * spread, y, z), Vector3(0.9, 1.1, 0.6))
		Kit.ball(head, size * 0.35, Color.WHITE, Vector3(side * spread - side * 0.01, y + 0.012, z + 0.015))


func _build_pig() -> void:
	var pink := Color("#f4b3bd")
	Kit.blob_shadow(self, 0.5, 0.25)
	Kit.ball(_body, 0.34, pink, Vector3(0, 0.42, 0), Vector3(1.0, 0.9, 1.25))
	for x in [-0.15, 0.15]:
		for z in [-0.22, 0.22]:
			_leg(Vector3(x, 0.24, z), 0.26, 0.07, pink.darkened(0.08))
	_head = _pivot(_body, Vector3(0, 0.55, 0.36))
	Kit.ball(_head, 0.24, pink, Vector3.ZERO)
	Kit.cyl(_head, 0.1, 0.11, 0.1, pink.darkened(0.1), Vector3(0, -0.03, 0.22), Vector3(90, 0, 0))
	for x in [-0.04, 0.04]:
		Kit.ball(_head, 0.022, Color("#b0566a"), Vector3(x, -0.03, 0.275))
	_eyes(_head, 0.08, 0.2, 0.09)
	for side in [-1, 1]:
		var ear := _pivot(_head, Vector3(side * 0.14, 0.18, 0.02))
		Kit.part(ear, Kit.cylinder(0.0, 0.08, 0.13, 4), pink.darkened(0.05), Vector3(0, 0.05, 0), Vector3(-20, 45, side * 20))
		_ears.append(ear)
	_tail = _pivot(_body, Vector3(0, 0.5, -0.42))
	Kit.part(_tail, Kit.torus(0.03, 0.06), pink.darkened(0.1), Vector3.ZERO, Vector3(0, 90, 0))
	_fx = _particles(Color("#9b7b55"), Vector3(0, 0.1, 0.1), 0.7)   # muddy splashes


func _build_rabbit() -> void:
	var fur := Color("#c9a27e")
	Kit.blob_shadow(self, 0.4, 0.25)
	Kit.ball(_body, 0.24, fur, Vector3(0, 0.3, -0.03), Vector3(1.0, 1.0, 1.2))
	Kit.ball(_body, 0.15, Color("#f3e8d8"), Vector3(0, 0.27, 0.13), Vector3(1, 1.1, 0.7))
	for x in [-0.12, 0.12]:
		_leg(Vector3(x, 0.12, -0.12), 0.12, 0.07, fur.darkened(0.05))
		_leg(Vector3(x * 0.7, 0.14, 0.14), 0.13, 0.045, fur.darkened(0.05))
	_head = _pivot(_body, Vector3(0, 0.55, 0.12))
	Kit.ball(_head, 0.18, fur, Vector3.ZERO)
	Kit.ball(_head, 0.06, Color("#f3e8d8"), Vector3(0, -0.06, 0.15), Vector3(1.3, 0.8, 0.7))
	Kit.ball(_head, 0.025, Color("#e58a9a"), Vector3(0, -0.02, 0.18))
	_eyes(_head, 0.04, 0.15, 0.08)
	for side in [-1, 1]:
		var ear := _pivot(_head, Vector3(side * 0.07, 0.14, -0.02))
		Kit.part(ear, Kit.capsule(0.05, 0.36), fur, Vector3(0, 0.16, 0), Vector3(-8, 0, side * 10), Vector3(1, 1, 0.55))
		Kit.part(ear, Kit.capsule(0.028, 0.28), Color("#f1b9c3"), Vector3(0, 0.16, 0.022), Vector3(-8, 0, side * 10), Vector3(1, 1, 0.4))
		_ears.append(ear)
	_tail = _pivot(_body, Vector3(0, 0.3, -0.31))
	Kit.ball(_tail, 0.07, Color("#fbf6ee"), Vector3.ZERO)
	_fx = _particles(Color("#8cc77a"), Vector3(0, 0.1, 0.3), 0.6)   # flying leaves while gardening


func _build_sheep() -> void:
	var wool := Color("#fbf8f1")
	var face := Color("#4a3f3a")
	Kit.blob_shadow(self, 0.55, 0.25)
	for p in [Vector3(0, 0.5, 0), Vector3(-0.15, 0.58, 0.12), Vector3(0.15, 0.58, 0.12), Vector3(-0.15, 0.56, -0.15),
			Vector3(0.15, 0.56, -0.15), Vector3(0, 0.66, 0), Vector3(0, 0.48, 0.22), Vector3(0, 0.5, -0.25)]:
		Kit.ball(_body, 0.2, wool, p)
	for x in [-0.13, 0.13]:
		for z in [-0.18, 0.18]:
			_leg(Vector3(x, 0.3, z), 0.3, 0.045, face)
	_head = _pivot(_body, Vector3(0, 0.62, 0.34))
	Kit.ball(_head, 0.15, face, Vector3(0, 0, 0.02), Vector3(0.9, 1.1, 1.0))
	Kit.ball(_head, 0.12, wool, Vector3(0, 0.12, -0.02))
	_eyes(_head, 0.03, 0.15, 0.06, 0.03)
	for side in [-1, 1]:
		var ear := _pivot(_head, Vector3(side * 0.15, 0.02, 0.0))
		Kit.part(ear, Kit.capsule(0.04, 0.16), face, Vector3(side * 0.06, 0, 0), Vector3(0, 0, side * 80))
		_ears.append(ear)
	_tail = _pivot(_body, Vector3(0, 0.55, -0.42))
	Kit.ball(_tail, 0.08, wool, Vector3.ZERO)
	_fx = _particles(Color("#7a68c8"), Vector3(0, 1.0, 0), 1.0)


func _build_dog() -> void:
	var fur := Color("#d29a5c")
	var light := Color("#f6e3c6")
	Kit.blob_shadow(self, 0.45, 0.25)
	Kit.ball(_body, 0.22, fur, Vector3(0, 0.4, 0), Vector3(0.9, 0.85, 1.45))
	Kit.ball(_body, 0.14, light, Vector3(0, 0.38, 0.18), Vector3(0.9, 1, 0.8))
	for x in [-0.11, 0.11]:
		for z in [-0.18, 0.2]:
			_leg(Vector3(x, 0.3, z), 0.3, 0.05, fur)
	_head = _pivot(_body, Vector3(0, 0.6, 0.3))
	Kit.ball(_head, 0.17, fur, Vector3.ZERO)
	Kit.ball(_head, 0.09, light, Vector3(0, -0.05, 0.14), Vector3(1, 0.8, 1.2))
	Kit.ball(_head, 0.035, Color("#3a2a22"), Vector3(0, -0.01, 0.25))
	_eyes(_head, 0.05, 0.14, 0.07)
	for side in [-1, 1]:
		var ear := _pivot(_head, Vector3(side * 0.15, 0.08, -0.02))
		Kit.part(ear, Kit.capsule(0.055, 0.2), fur.darkened(0.25), Vector3(0, -0.08, 0), Vector3(0, 0, side * 15), Vector3(1, 1, 0.5))
		_ears.append(ear)
	_tail = _pivot(_body, Vector3(0, 0.48, -0.3))
	Kit.part(_tail, Kit.capsule(0.03, 0.2), fur, Vector3(0, 0.08, -0.03), Vector3(-35, 0, 0))
	_ball = Node3D.new()
	_ball.top_level = true
	add_child(_ball)
	Kit.ball(_ball, 0.12, Color("#e9806e"), Vector3.ZERO)
	Kit.part(_ball, Kit.torus(0.1, 0.125), Color("#fffdf6"), Vector3.ZERO, Vector3(90, 0, 0))
	_ball.visible = false


func _build_elephant() -> void:
	var grey := Color("#aab4c4")
	Kit.blob_shadow(self, 0.9, 0.28)
	Kit.ball(_body, 0.55, grey, Vector3(0, 0.95, 0), Vector3(1.0, 0.9, 1.25))
	for x in [-0.28, 0.28]:
		for z in [-0.38, 0.38]:
			_leg(Vector3(x, 0.62, z), 0.62, 0.15, grey.darkened(0.05))
	_head = _pivot(_body, Vector3(0, 1.25, 0.62))
	Kit.ball(_head, 0.36, grey, Vector3.ZERO)
	_eyes(_head, 0.1, 0.3, 0.15, 0.04)
	for side in [-1, 1]:
		var ear := _pivot(_head, Vector3(side * 0.32, 0.05, -0.08))
		Kit.part(ear, Kit.sphere(0.3), grey.lightened(0.08), Vector3(side * 0.12, 0, 0), Vector3(0, side * 20, 0), Vector3(1, 1.1, 0.25))
		Kit.part(ear, Kit.sphere(0.22), Color("#e9b8c4"), Vector3(side * 0.12, 0, 0.04), Vector3(0, side * 20, 0), Vector3(1, 1.1, 0.2))
		_ears.append(ear)
	_trunk = _pivot(_head, Vector3(0, -0.08, 0.3))
	var seg := _trunk
	for i in 4:
		var next := _pivot(seg, Vector3(0, -0.16, 0.0) if i > 0 else Vector3.ZERO)
		Kit.part(next, Kit.capsule(0.09 - i * 0.012, 0.22), grey, Vector3(0, -0.08, 0))
		seg = next
	_tail = _pivot(_body, Vector3(0, 1.0, -0.66))
	Kit.part(_tail, Kit.capsule(0.03, 0.3), grey.darkened(0.1), Vector3(0, -0.12, 0))
	_fx = _particles(Color("#7fd0e0"), Vector3(0, 1.6, 0.9), 1.4)


func _particles(color: Color, pos: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = life
	p.position = pos
	p.direction = Vector3(0, 1, 0.3)
	p.spread = 35
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -1.2, 0)
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material = mat
	p.mesh = m
	p.emitting = false
	add_child(p)
	return p


# ------------------------------------------------------------- animation

func _process(delta: float) -> void:
	_t += delta
	position = position.lerp(_target_pos, minf(1.0, delta * 6.0))
	rotation.y = lerp_angle(rotation.y, _target_ry, minf(1.0, delta * 6.0))
	if _ball:
		_ball.visible = action in ["ball", "run"]
		var bp := _ball.global_position.lerp(_ball_target, minf(1.0, delta * 5.0))
		_ball.global_position = Vector3(bp.x, 0.12 + absf(sin(_t * 6.0)) * (0.15 if action == "run" else 0.0), bp.z)
		_ball.rotation.x += delta * (8.0 if action == "run" else 0.0)
	_pose(delta)


func _pose(delta: float) -> void:
	if _body == null:
		return
	var moving := action in ["walk", "run", "hop"]
	var speed := 14.0 if action == "run" else 9.0
	var swing := sin(_t * speed)
	var bob := 0.0
	var head_x := 0.0
	var body_x := 0.0
	var body_ry := 0.0
	var leg_a := 0.0
	var ear_a := sin(_t * 2.0) * 0.08
	var tail_a := sin(_t * 3.0) * 0.3
	var fx_on := false
	match action:
		"walk", "run":
			leg_a = swing * 0.6
			bob = absf(swing) * 0.03
		"hop":
			_hop_phase += delta * 5.0
			bob = absf(sin(_hop_phase)) * 0.22
			leg_a = 0.6 if sin(_hop_phase * 2.0) > 0 else -0.3
		"splash":
			bob = absf(sin(_t * 6.0)) * 0.25
			tail_a = sin(_t * 12.0) * 0.6
			fx_on = true
		"garden":
			head_x = 0.5 + sin(_t * 6.0) * 0.12
			body_x = 0.15
			fx_on = true
		"sing":
			head_x = -0.25
			body_ry = sin(_t * 2.5) * 0.25
			bob = absf(sin(_t * 2.5)) * 0.05
			fx_on = true
		"dance":
			body_ry = _t * 4.0
			bob = absf(sin(_t * 8.0)) * 0.15
			fx_on = true
		"ball":
			head_x = 0.3
			tail_a = sin(_t * 18.0) * 0.7
		"look":
			head_x = -0.3
			body_ry = sin(_t * 0.8) * 0.4
		"spray":
			head_x = -0.4
			fx_on = true
		"greet", "chat":
			bob = absf(sin(_t * 7.0)) * (0.1 if action == "greet" else 0.03)
			head_x = sin(_t * 5.0) * 0.15
			tail_a = sin(_t * 16.0) * 0.6
		"rest":
			bob = -0.12
			head_x = 0.25
			leg_a = 0.0
	if _react_t > 0.0:
		_react_t -= delta
		bob = maxf(bob, absf(sin(_react_t * 9.0)) * 0.3)
		tail_a = sin(_t * 18.0) * 0.7
	_body.position.y = lerpf(_body.position.y, bob, minf(1.0, delta * 14.0))
	_body.rotation.x = lerpf(_body.rotation.x, body_x, minf(1.0, delta * 6.0))
	_body.rotation.y = body_ry if action == "dance" else lerp_angle(_body.rotation.y, body_ry, minf(1.0, delta * 6.0))
	for i in _legs.size():
		var phase := 1.0 if (i % 2 == 0) == (i < 2) else -1.0
		_legs[i].rotation.x = leg_a * phase if moving and action != "hop" else (leg_a if action == "hop" else 0.0)
	if _head:
		_head.rotation.x = lerpf(_head.rotation.x, head_x, minf(1.0, delta * 6.0))
	for i in _ears.size():
		_ears[i].rotation.z = ear_a * (1 if i == 0 else -1) + (sin(_t * 3.0) * 0.25 if kind == "elephant" else 0.0)
	if _tail:
		_tail.rotation.y = tail_a
	if _trunk:
		var curl := -1.2 if action in ["spray", "look"] else sin(_t * 1.5) * 0.25
		var seg := _trunk
		while seg.get_child_count() > 0:
			seg.rotation.x = lerpf(seg.rotation.x, curl * 0.35, minf(1.0, delta * 5.0))
			var next: Node3D = null
			for c in seg.get_children():
				if c is Node3D and not (c is MeshInstance3D):
					next = c
			if next == null:
				break
			seg = next
	if _fx:
		_fx.emitting = fx_on
