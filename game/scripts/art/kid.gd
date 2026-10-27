## A cartoon child: built from soft primitives and animated procedurally.
##
## Big head, small body, dot eyes and blush keep the silhouette readable at
## gameplay distance. Animations: idle, walk, sit, swing, ride, rest, plus the
## emotes wave, cheer, dance and heart, which play on top of any pose.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Wearables := preload("res://scripts/core/wearables.gd")
## Wearable scenes kept loaded (least recently used are dropped beyond this), shared by every child.
const WEAR_CACHE_MAX := 40

const HIP_HEIGHT := 0.36
const EMOTE_TIME := 1.8
const POSE_TIME := 6.0   # story poses hold long enough to take a picture

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
## Worn clothing meshes (r12), rebuilt with the rig: {"standing": [standing Body meshes of items
## with a seated variant], "sit": [*_sit meshes], "held": [held item meshes], "all": [every mesh]}.
var _wear := {"standing": [], "sit": [], "held": [], "all": []}
## The worn set's pose state this frame (core/wearables.gd pose_state), for tests and tours.
var wear_state := {}
static var _wear_scenes := {}          # wearable id -> PackedScene (bounded, LRU)
static var _wear_order: Array = []     # least recently used first


func setup(data: Dictionary, show_name := true) -> void:
	avatar = Avatar.sanitize(data)
	# Detach before freeing so the rebuilt rig gets its exact names (docs/kid-rig.md).
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_legs.clear()
	_arms.clear()
	_eyes.clear()
	_wear = {"standing": [], "sit": [], "held": [], "all": []}
	_build()
	_mount_wear()
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
	# Baked parts a worn garment replaces are simply not built (EQUIP_HANDOFF 2, kid_rig HIDES).
	var hide := Wearables.hides(avatar.get("wear", {}))
	var body_part := func(center_y: float) -> bool:
		return not (hide.has("outfit_body") or (center_y < 0.5 and hide.has("outfit_body_low")))
	var skin: Color = Palette.SKIN[avatar["skin"]]
	var hair: Color = Palette.HAIR[avatar["hair_color"]]
	var outfit := Palette.paint(avatar["outfit_color"])
	if avatar["outfit_color"] == 0:
		outfit = Color("#efe2c6")
	_shadow = Kit.blob_shadow(self, 0.36, 0.28)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	# Legs and shoes.
	var bottoms := Color("#5b7fa6") if avatar["outfit"] == 1 else outfit
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(side * 0.095, HIP_HEIGHT, 0)
		_body.add_child(leg)
		Kit.part(leg, Kit.capsule(0.075, 0.34), skin, Vector3(0, -0.17, 0))
		if not hide.has("outfit_leg"):
			Kit.part(leg, Kit.capsule(0.085, 0.2), bottoms, Vector3(0, -0.06, 0))
		if not hide.has("shoe"):
			Kit.box(leg, Vector3(0.14, 0.09, 0.2), Color("#fdf8ef"), Vector3(0, -0.32, 0.03), 0.04)
		_legs.append(leg)

	# Torso by outfit.
	match avatar["outfit"]:
		0: # Overalls over a cream shirt
			if body_part.call(0.55):
				Kit.box(_body, Vector3(0.36, 0.3, 0.26), Color("#fdf8ef"), Vector3(0, 0.55, 0), 0.11)
			if body_part.call(0.45):
				Kit.box(_body, Vector3(0.38, 0.2, 0.28), outfit, Vector3(0, 0.45, 0), 0.08)
			if body_part.call(0.58):
				Kit.box(_body, Vector3(0.22, 0.14, 0.05), outfit, Vector3(0, 0.58, 0.12), 0.03)
				for side in [-1, 1]:
					Kit.box(_body, Vector3(0.05, 0.16, 0.04), outfit, Vector3(side * 0.09, 0.66, 0.12), 0.015)
					Kit.ball(_body, 0.022, Palette.paint(1), Vector3(side * 0.09, 0.61, 0.145))
		1: # T-shirt and shorts
			if body_part.call(0.56):
				Kit.box(_body, Vector3(0.37, 0.3, 0.27), outfit, Vector3(0, 0.56, 0), 0.11)
				Kit.ball(_body, 0.045, Palette.paint(0), Vector3(0.08, 0.6, 0.13), Vector3(1, 1, 0.3))
			if body_part.call(0.41):
				Kit.box(_body, Vector3(0.36, 0.12, 0.26), bottoms, Vector3(0, 0.41, 0), 0.06)
		2: # Dress
			if body_part.call(0.6):
				Kit.box(_body, Vector3(0.34, 0.22, 0.25), outfit, Vector3(0, 0.6, 0), 0.1)
			if body_part.call(0.42):
				Kit.cyl(_body, 0.16, 0.27, 0.3, outfit, Vector3(0, 0.42, 0))
				Kit.cyl(_body, 0.27, 0.275, 0.04, outfit.lightened(0.35), Vector3(0, 0.28, 0))

	# Arms hang from shoulder pivots so emotes can raise them.
	var sleeve := Color("#fdf8ef") if avatar["outfit"] == 0 else outfit
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(side * 0.215, 0.66, 0)
		_body.add_child(arm)
		Kit.part(arm, Kit.capsule(0.055, 0.3), skin, Vector3(side * 0.02, -0.14, 0), Vector3(0, 0, side * 8))
		if not hide.has("outfit_arm"):
			Kit.part(arm, Kit.capsule(0.068, 0.16), sleeve, Vector3(side * 0.005, -0.04, 0))
		Kit.ball(arm, 0.06, skin, Vector3(side * 0.04, -0.29, 0))
		_arms.append(arm)
		if side > 0:
			_build_prop(arm, avatar.get("prop", ""))

	# Head with face; built facing +z.
	_head = Node3D.new()
	_head.name = "Head"
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
	if not hide.has("hair"):
		_build_hair(hair)
	_build_hat(avatar.get("hat", ""))

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


## Handheld props (r11) hang from ArmR/Hand, a pivot at the right hand; they
## follow every arm move (wave, cheer, poses). docs/kid-rig.md.
func _build_prop(arm: Node3D, prop: String) -> void:
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0.04, -0.29, 0.0)
	arm.add_child(hand)
	match prop:
		"magnifier":
			Kit.cyl(hand, 0.015, 0.018, 0.14, Palette.WOOD_DARK, Vector3(0, 0.02, 0.04), Vector3(70, 0, 0))
			Kit.part(hand, Kit.torus(0.06, 0.08), Color("#c9ad7a"), Vector3(0, 0.05, 0.16), Vector3(0, 0, 0))
			var glass := Kit.part(hand, Kit.cylinder(0.062, 0.062, 0.01, 20), Kit.mat(Color(0.75, 0.9, 1.0, 0.45), 0.2), Vector3(0, 0.05, 0.16), Vector3(90, 0, 0))
			glass.name = "Lens"
		"baton":
			Kit.cyl(hand, 0.006, 0.012, 0.3, Color("#fdf8ef"), Vector3(0, 0.0, 0.14), Vector3(80, 0, 0))
			Kit.ball(hand, 0.022, Palette.WOOD_DARK, Vector3(0, -0.02, 0.0))
		"umbrella":
			# The canopy's rim (hand ~0.37 m + 1.28 m) stays above the tallest hat (~1.63 m).
			Kit.cyl(hand, 0.012, 0.012, 1.34, Palette.WOOD_DARK, Vector3(0, 0.67, 0.02))
			Kit.part(hand, Kit.cylinder(0.02, 0.46, 0.16, 8), Palette.paint(2), Vector3(-0.1, 1.36, 0.02))
		"flag":
			Kit.cyl(hand, 0.008, 0.008, 0.36, Palette.WOOD_DARK, Vector3(0, 0.15, 0.02))
			Kit.box(hand, Vector3(0.012, 0.11, 0.17), Palette.paint(4), Vector3(0, 0.27, 0.1), 0.01)


## Dress-up hats (F07) sit on the hair; each reads clearly with every hairstyle.
## Rig contract (docs/kid-rig.md): hats are built under Body/Head/Hat, a pivot at
## the head origin; hair is never hidden; nothing else moves when a hat changes.
func _build_hat(hat: String) -> void:
	var cream := Color("#fdf8ef")
	var hat_root := Node3D.new()
	hat_root.name = "Hat"
	_head.add_child(hat_root)
	match hat:
		"chef":
			Kit.cyl(hat_root, 0.2, 0.21, 0.08, cream, Vector3(0, 0.6, -0.02))
			Kit.ball(hat_root, 0.22, cream, Vector3(0, 0.74, -0.02), Vector3(1.05, 0.75, 1.05))
			for a in [-0.12, 0.0, 0.12]:
				Kit.ball(hat_root, 0.11, cream, Vector3(a, 0.8, 0.05 if a == 0.0 else -0.02))
		"explorer":
			var khaki := Color("#c9ad7a")
			Kit.cyl(hat_root, 0.4, 0.4, 0.025, khaki, Vector3(0, 0.56, -0.02))
			Kit.cyl(hat_root, 0.21, 0.24, 0.17, khaki, Vector3(0, 0.65, -0.02))
			Kit.cyl(hat_root, 0.245, 0.245, 0.04, Color("#7a5a3a"), Vector3(0, 0.6, -0.02))
		"crown":
			var gold := Color("#f2c75c")
			Kit.cyl(hat_root, 0.24, 0.24, 0.09, gold, Vector3(0, 0.62, -0.02))
			for i in 5:
				var a := TAU * i / 5.0
				Kit.part(hat_root, Kit.cylinder(0.0, 0.055, 0.12, 4), gold, Vector3(sin(a) * 0.21, 0.72, cos(a) * 0.21 - 0.02))
			Kit.ball(hat_root, 0.035, Palette.paint(2), Vector3(0, 0.63, 0.23))
		"rain":
			var yellow := Color("#f4cf4a")
			Kit.ball(hat_root, 0.29, yellow, Vector3(0, 0.55, -0.04), Vector3(1.12, 0.62, 1.12))
			Kit.cyl(hat_root, 0.36, 0.42, 0.03, yellow, Vector3(0, 0.46, -0.08))


# ------------------------------------------------------------- worn clothing (r12)

## A wearable's scene, loaded once and kept in a small shared LRU cache.
static func wear_scene(id: String) -> PackedScene:
	if _wear_scenes.has(id):
		_wear_order.erase(id)
		_wear_order.append(id)
		return _wear_scenes[id]
	var path := Wearables.glb(id)
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		return null
	_wear_scenes[id] = scene
	_wear_order.append(id)
	while _wear_order.size() > WEAR_CACHE_MAX:
		_wear_scenes.erase(_wear_order.pop_front())
	return scene


static func wear_cache_size() -> int:
	return _wear_scenes.size()


## Mounts every worn item: each <id>_<Pivot>[_sit] mesh goes under the child's node for that
## pivot with an identity transform (EQUIP_HANDOFF 1). Called after setup(), so a rebuilt rig
## always gets fresh meshes and the old ones go with the old rig (no duplicates).
func _mount_wear() -> void:
	var pivots := {"Body": _body, "Head": _head, "ArmL": _arms[0], "ArmR": _arms[1], "LegL": _legs[0], "LegR": _legs[1]}
	var wear: Dictionary = avatar.get("wear", {})
	for slot in wear:
		var id: String = wear[slot]
		var scene := wear_scene(id)
		if scene == null:
			continue
		var def := Wearables.get_def(id)
		var inst := scene.instantiate()
		for pivot in inst.get_children():
			var target: Node3D = pivots.get(str(pivot.name))
			if target == null:
				continue
			for mesh in pivot.get_children():
				if not mesh is MeshInstance3D:
					continue
				pivot.remove_child(mesh)
				mesh.owner = null
				mesh.transform = Transform3D.IDENTITY
				target.add_child(mesh)
				_wear["all"].append(mesh)
				var part := str(mesh.name).trim_prefix(id + "_")
				if part.ends_with("_sit"):
					_wear["sit"].append(mesh)
					mesh.visible = false
				elif part == "Body" and def.get("sit", false):
					_wear["standing"].append(mesh)
				if def.get("held", false):
					_wear["held"].append(mesh)
		inst.free()
	_apply_wear_state(Wearables.pose_state(anim, wear))


## Shows the standing or seated meshes (never both) and the held item per the pose state.
func _apply_wear_state(st: Dictionary) -> void:
	wear_state = st
	for m in _wear["sit"]:
		m.visible = st["seated"]
	for m in _wear["standing"]:
		m.visible = not st["seated"]
	for m in _wear["held"]:
		m.visible = st["held_visible"]


# ------------------------------------------------------------- control

func play_emote(kind: String) -> void:
	emote_kind = kind
	_emote_t = POSE_TIME if Avatar.POSES.has(kind) else EMOTE_TIME


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
	# A seated child is placed on its seat by the world each frame; easing toward the friend's last
	# walking position here would pull it off the seat (r17: seen as a drifting friend on a bench).
	if interpolate and not anim in ["sit", "swing", "ride", "rest"]:
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
			"surprised":
				arm_z = [-1.9, 1.9]
				arm_x = [-0.4, -0.4]
				mouth_open = true
				_head.rotation.x = -0.15
			"think":
				arm_x[1] = -2.1
				arm_z[1] = -0.5
				_head.rotation.z = 0.18
			"proud":
				arm_z = [-0.6, 0.6]
				arm_x = [0.5, 0.5]
				_head.rotation.x = -0.2
				if not seated:
					bob = 0.03
			"sneak":
				arm_x = [-0.9, -0.9]
				if not seated:
					bob = -0.08
					leg_a = [sin(_t * 4.0) * 0.3, -sin(_t * 4.0) * 0.3]
					_body.rotation.x = 0.2
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
	if not Avatar.POSES.has(emote_kind):
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, minf(1.0, delta * 8.0))
		_head.rotation.z = lerpf(_head.rotation.z, 0.0, minf(1.0, delta * 8.0))
	_body.position.y = bob
	# Worn clothing (EQUIP_HANDOFF 9): seated variants swap on the frame the anim changes; with
	# one shown in sit/rest the arms go forward over the knees; a held item keeps the right arm in
	# the hold envelope and an emote's right-arm move plays on the left arm instead.
	if not _wear["all"].is_empty():
		var st := Wearables.pose_state(anim, avatar.get("wear", {}))
		if st != wear_state:
			_apply_wear_state(st)
		if st["sit_hands"]:
			arm_x = [Wearables.SIT_HANDS_X, Wearables.SIT_HANDS_X]
			arm_z = [0.0, 0.0]
		elif st["hold"]:
			var outside: bool = arm_x[1] < Wearables.HOLD_X.x or arm_x[1] > Wearables.HOLD_X.y \
				or arm_z[1] < Wearables.HOLD_Z.x or arm_z[1] > Wearables.HOLD_Z.y
			if outside and _emote_t > 0.0 and absf(arm_z[0]) < 0.1 and absf(arm_x[0]) < 0.6:
				arm_x[0] = arm_x[1]
				arm_z[0] = -arm_z[1]
			arm_x[1] = clampf(arm_x[1], Wearables.HOLD_X.x, Wearables.HOLD_X.y)
			arm_z[1] = clampf(arm_z[1], Wearables.HOLD_Z.x, Wearables.HOLD_Z.y)
	for i in 2:
		_legs[i].rotation.x = leg_a[i]
		_arms[i].rotation.x = arm_x[i]
		_arms[i].rotation.z = arm_z[i]
	# A handheld prop stays upright whatever the arm does (an umbrella over the
	# head even with arms out in a pose); docs/kid-rig.md.
	var hand := _arms[1].get_node_or_null("Hand") as Node3D
	if hand:
		hand.basis = _arms[1].basis.inverse()
	if not Avatar.POSES.has(emote_kind):
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
