## A cartoon child: built from soft primitives and animated procedurally.
##
## Big head, small body, dot eyes and blush keep the silhouette readable at
## gameplay distance. Animations: idle, walk, sit, swing, ride, rest, plus the
## emotes wave, cheer, dance and heart, which play on top of any pose.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Avatar := preload("res://scripts/core/avatar.gd")

const HIP_HEIGHT := 0.36
const EMOTE_TIME := 1.8

var avatar := {}
var anim := "idle"
var emote_kind := ""
var walk_speed := 0.0
var interpolate := false

var _t := 0.0
var _emote_t := 0.0
var _blink_t := 2.0
var _target_pos := Vector3.ZERO
var _target_ry := 0.0
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _mouth_smile: Node3D
var _mouth_open: Node3D
var _heart: Node3D
var _label: Label3D
var _shadow: Node3D


func setup(data: Dictionary, show_name := true) -> void:
	avatar = Avatar.sanitize(data)
	for c in get_children():
		c.queue_free()
	_legs.clear()
	_arms.clear()
	_eyes.clear()
	_build()
	if show_name:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = false
		_label.pixel_size = 0.004
		_label.font_size = 44
		_label.outline_size = 14
		_label.modulate = Color("#344d40")
		_label.outline_modulate = Color("#fffdf6")
		_label.position = Vector3(0, 1.62, 0)
		_label.render_priority = 2
		add_child(_label)
		refresh_label()


func refresh_label() -> void:
	if _label:
		_label.text = tr(avatar.get("nick", ""))
		_label.font = I18n.ui_font()


func _build() -> void:
	var skin: Color = Palette.SKIN[avatar["skin"]]
	var hair: Color = Palette.HAIR[avatar["hair_color"]]
	var outfit := Palette.paint(avatar["outfit_color"])
	if avatar["outfit_color"] == 0:
		outfit = Color("#efe2c6")
	_shadow = Kit.blob_shadow(self, 0.36, 0.28)
	_body = Node3D.new()
	add_child(_body)

	# Legs and shoes.
	var bottoms := Color("#5b7fa6") if avatar["outfit"] == 1 else outfit
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.095, HIP_HEIGHT, 0)
		_body.add_child(leg)
		Kit.part(leg, Kit.capsule(0.075, 0.34), skin, Vector3(0, -0.17, 0))
		Kit.part(leg, Kit.capsule(0.085, 0.2), bottoms, Vector3(0, -0.06, 0))
		Kit.box(leg, Vector3(0.14, 0.09, 0.2), Color("#fdf8ef"), Vector3(0, -0.32, 0.03), 0.04)
		_legs.append(leg)

	# Torso by outfit.
	match avatar["outfit"]:
		0: # Overalls over a cream shirt
			Kit.box(_body, Vector3(0.36, 0.3, 0.26), Color("#fdf8ef"), Vector3(0, 0.55, 0), 0.11)
			Kit.box(_body, Vector3(0.38, 0.2, 0.28), outfit, Vector3(0, 0.45, 0), 0.08)
			Kit.box(_body, Vector3(0.22, 0.14, 0.05), outfit, Vector3(0, 0.58, 0.12), 0.03)
			for side in [-1, 1]:
				Kit.box(_body, Vector3(0.05, 0.16, 0.04), outfit, Vector3(side * 0.09, 0.66, 0.12), 0.015)
				Kit.ball(_body, 0.022, Palette.paint(1), Vector3(side * 0.09, 0.61, 0.145))
		1: # T-shirt and shorts
			Kit.box(_body, Vector3(0.37, 0.3, 0.27), outfit, Vector3(0, 0.56, 0), 0.11)
			Kit.box(_body, Vector3(0.36, 0.12, 0.26), bottoms, Vector3(0, 0.41, 0), 0.06)
			Kit.ball(_body, 0.045, Palette.paint(0), Vector3(0.08, 0.6, 0.13), Vector3(1, 1, 0.3))
		2: # Dress
			Kit.box(_body, Vector3(0.34, 0.22, 0.25), outfit, Vector3(0, 0.6, 0), 0.1)
			Kit.cyl(_body, 0.16, 0.27, 0.3, outfit, Vector3(0, 0.42, 0))
			Kit.cyl(_body, 0.27, 0.275, 0.04, outfit.lightened(0.35), Vector3(0, 0.28, 0))

	# Arms hang from shoulder pivots so emotes can raise them.
	var sleeve := Color("#fdf8ef") if avatar["outfit"] == 0 else outfit
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.215, 0.66, 0)
		_body.add_child(arm)
		Kit.part(arm, Kit.capsule(0.055, 0.3), skin, Vector3(side * 0.02, -0.14, 0), Vector3(0, 0, side * 8))
		Kit.part(arm, Kit.capsule(0.068, 0.16), sleeve, Vector3(side * 0.005, -0.04, 0))
		Kit.ball(arm, 0.06, skin, Vector3(side * 0.04, -0.29, 0))
		_arms.append(arm)

	# Head with face; built facing +z.
	_head = Node3D.new()
	_head.position = Vector3(0, 0.72, 0)
	_body.add_child(_head)
	Kit.ball(_head, 0.3, skin, Vector3(0, 0.29, 0), Vector3(1.04, 0.96, 1))
	for side in [-1, 1]:
		Kit.ball(_head, 0.06, skin, Vector3(side * 0.3, 0.27, 0), Vector3(0.6, 1, 1))
		var eye := Node3D.new()
		eye.position = Vector3(side * 0.105, 0.3, 0.262)
		_head.add_child(eye)
		Kit.ball(eye, 0.046, Color("#2b2320"), Vector3.ZERO, Vector3(0.85, 1.15, 0.5))
		Kit.ball(eye, 0.015, Color.WHITE, Vector3(side * -0.012, 0.018, 0.02))
		_eyes.append(eye)
		Kit.ball(_head, 0.05, Color("#f6a7a0"), Vector3(side * 0.175, 0.21, 0.235), Vector3(1.2, 0.7, 0.4))
	_mouth_smile = Node3D.new()
	_head.add_child(_mouth_smile)
	Kit.part(_mouth_smile, Kit.torus(0.022, 0.034), Color("#b4544a"), Vector3(0, 0.205, 0.272), Vector3(78, 0, 0), Vector3(1, 1, 0.8))
	Kit.ball(_mouth_smile, 0.04, skin, Vector3(0, 0.222, 0.27), Vector3(1.2, 0.6, 0.55))
	_mouth_open = Node3D.new()
	_head.add_child(_mouth_open)
	Kit.ball(_mouth_open, 0.045, Color("#9a3f3a"), Vector3(0, 0.19, 0.266), Vector3(1, 0.8, 0.4))
	Kit.ball(_mouth_open, 0.025, Color("#f08b86"), Vector3(0, 0.172, 0.282), Vector3(1, 0.6, 0.4))
	_mouth_open.visible = false
	_build_hair(hair)

	_heart = Node3D.new()
	_heart.position = Vector3(0, 1.55, 0)
	add_child(_heart)
	var heart_c := Color("#ef6f86")
	for side in [-1, 1]:
		Kit.ball(_heart, 0.09, heart_c, Vector3(side * 0.07, 0.04, 0))
	Kit.part(_heart, Kit.cylinder(0.0, 0.135, 0.17, 4), heart_c, Vector3(0, -0.07, 0), Vector3(180, 45, 0), Vector3(1, 1, 0.55))
	_heart.visible = false
	Kit.merge_parts(self)


func _build_hair(c: Color) -> void:
	var cap := Kit.ball(_head, 0.315, c, Vector3(0, 0.34, -0.035), Vector3(1.04, 0.86, 1.0))
	cap.name = "HairCap"
	match avatar["hair"]:
		0: # Bob with bangs
			Kit.ball(_head, 0.33, c, Vector3(0, 0.25, -0.06), Vector3(1.1, 0.78, 0.86))
			Kit.ball(_head, 0.25, c, Vector3(0, 0.47, 0.13), Vector3(1.15, 0.38, 0.62))
			Kit.ball(_head, 0.05, Palette.paint(1), Vector3(0.2, 0.46, 0.2))
		1: # Ponytail
			Kit.ball(_head, 0.24, c, Vector3(0, 0.47, 0.12), Vector3(1.1, 0.35, 0.6))
			Kit.ball(_head, 0.045, Palette.paint(3), Vector3(0, 0.44, -0.3))
			Kit.ball(_head, 0.13, c, Vector3(0, 0.32, -0.38), Vector3(0.9, 1.3, 0.9))
		2: # Curls
			for i in 9:
				var a := TAU * i / 9.0
				Kit.ball(_head, 0.11, c, Vector3(cos(a) * 0.25, 0.47 + sin(a * 2.0) * 0.03, sin(a) * 0.2 - 0.03))
			Kit.ball(_head, 0.12, c, Vector3(0.05, 0.58, 0.02))
			Kit.ball(_head, 0.1, c, Vector3(-0.1, 0.5, 0.2))
			Kit.ball(_head, 0.09, c, Vector3(0.12, 0.49, 0.2))
		3: # Two buns
			Kit.ball(_head, 0.24, c, Vector3(0, 0.46, 0.13), Vector3(1.12, 0.36, 0.6))
			for side in [-1, 1]:
				Kit.ball(_head, 0.11, c, Vector3(side * 0.19, 0.58, -0.04))
		4: # Short and tufty
			Kit.ball(_head, 0.2, c, Vector3(0.03, 0.48, 0.13), Vector3(1.25, 0.4, 0.62))
			Kit.ball(_head, 0.07, c, Vector3(0.0, 0.64, 0.02))
			Kit.ball(_head, 0.06, c, Vector3(0.07, 0.62, -0.06))


# ------------------------------------------------------------- control

func play_emote(kind: String) -> void:
	emote_kind = kind
	_emote_t = EMOTE_TIME


## Remote children glide toward the latest network state.
func set_target(pos: Vector3, ry: float, snap := false) -> void:
	_target_pos = pos
	_target_ry = ry
	interpolate = true
	if snap:
		position = pos
		rotation.y = ry


func _process(delta: float) -> void:
	_t += delta
	if interpolate:
		var before := position
		position = position.lerp(_target_pos, minf(1.0, delta * 10.0))
		rotation.y = lerp_angle(rotation.y, _target_ry, minf(1.0, delta * 10.0))
		if anim == "walk" or anim == "idle":
			anim = "walk" if before.distance_to(_target_pos) > 0.03 else "idle"
	_pose(delta)


func _pose(delta: float) -> void:
	if _body == null:
		return
	var seated := anim in ["sit", "swing", "ride", "rest"]
	var swing := sin(_t * 9.0)
	var bob := 0.0
	var leg_a := [0.0, 0.0]
	var arm_x := [0.0, 0.0]
	var arm_z := [0.0, 0.0]
	match anim:
		"walk":
			leg_a = [swing * 0.65, -swing * 0.65]
			arm_x = [-swing * 0.55, swing * 0.55]
			bob = absf(swing) * 0.045
		"idle":
			bob = sin(_t * 2.2) * 0.008
			arm_z = [sin(_t * 2.2) * 0.04, -sin(_t * 2.2) * 0.04]
		"sit", "rest":
			leg_a = [-1.45, -1.45]
			arm_x = [-0.5, -0.5]
		"swing":
			leg_a = [-1.2 + sin(_t * 2.4) * 0.35, -1.2 + sin(_t * 2.4) * 0.35]
			arm_x = [-2.7, -2.7]
		"ride":
			leg_a = [-1.3, -1.3]
			arm_x = [-1.1, -1.1]
	var mouth_open := false
	var eyes_closed := anim == "rest"
	_heart.visible = false
	if _emote_t > 0.0:
		_emote_t -= delta
		var k := _t * 12.0
		match emote_kind:
			"wave":
				arm_z[1] = 2.6
				arm_x[1] = 0.0
				arm_z[1] += sin(k) * 0.35
				mouth_open = true
			"cheer":
				arm_z = [-2.7, 2.7]
				arm_x = [0.0, 0.0]
				if not seated:
					bob = absf(sin(_t * 7.0)) * 0.22
				mouth_open = true
			"dance":
				arm_z = [-1.4 + sin(k * 0.5) * 0.6, 1.4 + sin(k * 0.5) * 0.6]
				if not seated:
					_body.rotation.y = sin(_t * 5.0) * 0.6
					bob = absf(sin(_t * 10.0)) * 0.08
				mouth_open = true
			"heart":
				_heart.visible = true
				_heart.position.y = 1.55 + (EMOTE_TIME - _emote_t) * 0.25
				_heart.rotation.y = _t * 2.0
				arm_x = [-0.6, -0.6]
				arm_z = [0.5, -0.5]
				eyes_closed = true
		if _emote_t <= 0.0:
			emote_kind = ""
	else:
		_body.rotation.y = lerpf(_body.rotation.y, 0.0, minf(1.0, delta * 8.0))
	_body.position.y = bob
	for i in 2:
		_legs[i].rotation.x = leg_a[i]
		_arms[i].rotation.x = arm_x[i]
		_arms[i].rotation.z = arm_z[i]
	_head.rotation.x = 0.12 if anim == "rest" else 0.0
	# Blink every few seconds.
	_blink_t -= delta
	var blink := _blink_t < 0.12
	if _blink_t < 0.0:
		_blink_t = randf_range(2.0, 4.5)
	for e in _eyes:
		e.scale.y = 0.15 if (blink or eyes_closed) else 1.0
	_mouth_open.visible = mouth_open
	_mouth_smile.visible = not mouth_open
	_shadow.visible = not seated
