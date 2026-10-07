## Activities in the 3D world: how children find and see them.
##
## The activity square: playful landmarks around the Wishing Tree start each
## shared activity. Bell = evening, drum = dance party, weather vane = weather,
## acorn stump = hide-and-seek, photo board = photo ideas. A landmark nobody on
## this device has tried yet twinkles and shows its name from afar; once tried
## it shows its name only up close. Animals carry wishes (a bubble over their
## head), presents sit in the world with a name tag, garden beds grow in place,
## and each room shows its heart stickers and (in living rooms) a guest book.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/core/palette.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const Wishes := preload("res://scripts/core/wishes.gd")
const SETTINGS_PATH := "user://settings.cfg"

## Landmark id -> offset from the Wishing Tree center (x, z) and the action it offers.
const LANDMARKS := {
	"bell": {"offset": Vector2(1.6, 1.9), "label": "Evening"},
	"drum": {"offset": Vector2(2.7, 0.3), "label": "Party!"},
	"vane": {"offset": Vector2(-1.6, 1.9), "label": "Change the weather"},
	"stump": {"offset": Vector2(-2.7, 0.3), "label": "Hide and seek"},
	"board": {"offset": Vector2(0.0, 2.75), "label": "Photo ideas"},
}
## Guest book stand in every ground-floor living room (left wall, front part).
const GUEST_BOOK := Vector2(-3.3, 2.0)

var world: Node3D
var _landmarks := {}          # id -> Node3D
## Landmark names are drawn by the HUD as tappable tags (see landmark_tags()).
var _sparkles := {}           # id -> CPUParticles3D
var _discovered := {}
var _weather_root: Node3D
var _acorn: Node3D
var _wish_bubble: Sprite3D
var _party_fx: CPUParticles3D
var _warm_fx: CPUParticles3D
var _room_extras: Node3D
var _t := 0.0


func setup(w: Node3D, town_root: Node3D) -> void:
	world = w
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for id in cfg.get_value("player", "discovered", []):
		_discovered[id] = true
	_build_landmarks(town_root)
	_weather_root = Node3D.new()
	town_root.add_child(_weather_root)
	_acorn = _build_acorn()
	add_child(_acorn)
	_acorn.visible = false
	_wish_bubble = Sprite3D.new()
	_wish_bubble.texture = UI.icon("wish", 96)
	_wish_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_wish_bubble.no_depth_test = true
	_wish_bubble.pixel_size = 0.008
	_wish_bubble.visible = false
	add_child(_wish_bubble)
	_party_fx = _confetti(Vector3(TownModel.WISHING_TREE.x, 3.5, TownModel.WISHING_TREE.y), 60, 6.0)
	town_root.add_child(_party_fx)
	_warm_fx = _confetti(Vector3.ZERO, 12, 0.6)
	add_child(_warm_fx)
	Session.town_data_changed.connect(_on_data)
	Session.town_reset.connect(func(): _on_data("weather"))
	Activities.hs_changed.connect(_refresh_acorn)
	Activities.warmth_changed.connect(func(_l, _a): _refresh_acorn())
	Activities.party_changed.connect(func(on): _party_fx.emitting = on)
	Activities.wish_done.connect(func(_animal, _id, at, _by): burst(Vector3(at.x, 0.5, at.y)))
	Session.gift_opened.connect(func(id, _from, _peer):
		var n: Node3D = world.item_nodes.get(id)
		if n:
			burst(n.global_position + Vector3(0, 0.6, 0)))
	_on_data("weather")


## World point a child walks to for a landmark's action.
func point(id: String) -> Vector2:
	var off: Vector2 = LANDMARKS[id]["offset"]
	return TownModel.WISHING_TREE + off + off.normalized() * 0.6


func mark_discovered(id: String) -> void:
	if _discovered.has(id):
		return
	_discovered[id] = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "discovered", _discovered.keys())
	cfg.save(SETTINGS_PATH)
	if _sparkles.has(id):
		_sparkles[id].emitting = false


func is_discovered(id: String) -> bool:
	return _discovered.has(id)


## The landmark under a screen point (tap from afar to walk there and use it).
func pick(camera: Camera3D, screen: Vector2) -> String:
	if world.view_space != "town":
		return ""
	var best := ""
	var best_d := 70.0
	for id in _landmarks:
		var c: Vector3 = _landmarks[id].global_position + Vector3(0, 1.0, 0)
		if camera.is_position_behind(c):
			continue
		var d := camera.unproject_position(c).distance_to(screen)
		if d < best_d:
			best_d = d
			best = id
	return best


# ------------------------------------------------------------- landmarks

func _build_landmarks(root: Node3D) -> void:
	for id in LANDMARKS:
		if id == "bell":
			continue   # the bell is part of the Wishing Tree model
		var n := Node3D.new()
		n.name = "Landmark_" + id
		var off: Vector2 = LANDMARKS[id]["offset"]
		n.position = Vector3(TownModel.WISHING_TREE.x + off.x, 0, TownModel.WISHING_TREE.y + off.y)
		n.rotation.y = atan2(off.x, off.y)
		root.add_child(n)
		match id:
			"drum":
				Kit.blob_shadow(n, 0.5)
				Kit.cyl(n, 0.36, 0.36, 0.5, Palette.paint(3), Vector3(0, 0.25, 0))
				Kit.cyl(n, 0.38, 0.38, 0.06, Palette.paint(0), Vector3(0, 0.52, 0))
				Kit.cyl(n, 0.38, 0.38, 0.06, Palette.paint(1), Vector3(0, 0.02, 0))
				for a in 6:
					Kit.box(n, Vector3(0.03, 0.45, 0.03), Palette.paint(1), Vector3(cos(a * TAU / 6) * 0.37, 0.27, sin(a * TAU / 6) * 0.37), 0.01, Vector3(0, 0, 20))
				Kit.part(n, Kit.capsule(0.03, 0.4), Palette.WOOD, Vector3(0.2, 0.62, 0.1), Vector3(0, 0, 60))
			"vane":
				Kit.blob_shadow(n, 0.3)
				Kit.cyl(n, 0.04, 0.05, 1.9, Color("#5d6b62"), Vector3(0, 0.95, 0))
				var top := Node3D.new()
				top.name = "Spin"
				top.position.y = 1.95
				n.add_child(top)
				Kit.box(top, Vector3(0.7, 0.04, 0.04), Color("#5d6b62"), Vector3.ZERO, 0.01)
				Kit.part(top, Kit.cylinder(0.0, 0.12, 0.2, 3), Palette.paint(4), Vector3(0.38, 0, 0), Vector3(0, 0, -90))
				Kit.box(top, Vector3(0.22, 0.2, 0.02), Palette.paint(1), Vector3(-0.32, 0.05, 0), 0.02)
				Kit.ball(n, 0.08, Palette.paint(1), Vector3(0, 2.1, 0))
			"stump":
				Kit.blob_shadow(n, 0.55)
				Kit.cyl(n, 0.42, 0.5, 0.55, Palette.WOOD_DARK, Vector3(0, 0.27, 0))
				Kit.cyl(n, 0.36, 0.36, 0.04, Palette.WOOD, Vector3(0, 0.56, 0))
				Kit.cyl(n, 0.18, 0.18, 0.05, Color("#4a3a2c"), Vector3(0, 0.57, 0))
				# A golden acorn peeks out of the hollow: this is the hide-and-seek stump.
				Kit.ball(n, 0.1, Color("#e3b341"), Vector3(0.05, 0.66, 0.05), Vector3(1, 1.2, 1))
				Kit.cyl(n, 0.09, 0.11, 0.06, Palette.WOOD_DARK, Vector3(0.05, 0.78, 0.05))
			"board":
				Kit.blob_shadow(n, 0.5)
				for x in [-0.45, 0.45]:
					Kit.cyl(n, 0.04, 0.04, 1.3, Palette.WOOD, Vector3(x, 0.65, 0))
				Kit.box(n, Vector3(1.1, 0.75, 0.08), Palette.WOOD, Vector3(0, 1.15, 0), 0.04)
				Kit.box(n, Vector3(0.98, 0.63, 0.1), Palette.paint(0), Vector3(0, 1.15, 0.01), 0.03)
				for i in 4:
					Kit.box(n, Vector3(0.36, 0.24, 0.11), Palette.paint([4, 2, 5, 6][i]), Vector3(-0.22 + (i % 2) * 0.44, 1.29 - (i / 2) * 0.3, 0.02), 0.02)
		Kit.merge_parts(n)
		_landmarks[id] = n
	# The bell lives on the Wishing Tree model; track a stand-in point for it.
	var bell := Node3D.new()
	var boff: Vector2 = LANDMARKS["bell"]["offset"]
	bell.position = Vector3(TownModel.WISHING_TREE.x + boff.x, 0, TownModel.WISHING_TREE.y + boff.y)
	root.add_child(bell)
	_landmarks["bell"] = bell
	for id in _landmarks:
		var sp := _confetti(Vector3(0, 1.2, 0), 8, 1.4)
		_landmarks[id].add_child(sp)   # in the tree first: particles need a transform to start
		sp.emitting = not _discovered.has(id)
		_sparkles[id] = sp


## Height above the ground where each landmark's name tag points.
const TAG_HEIGHT := {"vane": 2.3, "bell": 2.1, "drum": 1.0, "stump": 1.0, "board": 1.8}


## Landmarks to name on screen, nearest first. Untried landmarks are named from
## farther away so children notice them; tried ones only up close.
func landmark_tags(camera: Camera3D) -> Array:
	var out := []
	var me: Node3D = world.local_kid()
	if me == null or world.view_space != "town":
		return out
	for id in _landmarks:
		var anchor: Vector3 = _landmarks[id].global_position + Vector3(0, TAG_HEIGHT[id], 0)
		var d := me.global_position.distance_to(_landmarks[id].global_position)
		if d > (13.0 if not _discovered.has(id) else 4.5) or camera.is_position_behind(anchor):
			continue
		var text: String = LANDMARKS[id]["label"]
		if id == "bell" and Session.model.evening:
			text = "Morning"
		out.append({"id": id, "text": text, "screen": camera.unproject_position(anchor),
			"foot": camera.unproject_position(_landmarks[id].global_position), "distance": d, "new": not _discovered.has(id)})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out


func _confetti(pos: Vector3, amount: int, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread
	p.gravity = Vector3(0, -0.6, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.direction = Vector3(0, 1, 0)
	p.spread = 180
	p.color_ramp = _rainbow()
	var m := BoxMesh.new()
	m.size = Vector3(0.07, 0.07, 0.015)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	p.emitting = false
	return p


static func _rainbow() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Palette.paint(3))
	g.set_color(1, Palette.paint(4))
	g.add_point(0.33, Palette.paint(1))
	g.add_point(0.66, Palette.paint(5))
	return g


## A one-shot confetti burst (wishes come true, presents opened, acorn found).
func burst(at: Vector3) -> void:
	var p := _confetti(at, 40, 0.5)
	p.one_shot = true
	p.explosiveness = 0.9
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -3.0, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)
	Sfx.play("lantern")


# ------------------------------------------------------------- hide-and-seek acorn

func _build_acorn() -> Node3D:
	var n := Node3D.new()
	Kit.ball(n, 0.16, Color("#e3b341"), Vector3(0, 0.2, 0), Vector3(1, 1.2, 1))
	Kit.cyl(n, 0.15, 0.17, 0.1, Palette.WOOD_DARK, Vector3(0, 0.38, 0))
	Kit.cyl(n, 0.02, 0.02, 0.1, Palette.WOOD_DARK, Vector3(0, 0.47, 0))
	var glow := Kit.ball(n, 0.24, Kit.glow_mat(Color("#ffe08a")), Vector3(0, 0.22, 0))
	glow.name = "Glow"
	var beam := Kit.cyl(n, 0.06, 0.06, 6.0, Kit.mat(Color(1.0, 0.9, 0.5, 0.35)), Vector3(0, 3.0, 0))
	beam.name = "Beam"
	return n


func _refresh_acorn() -> void:
	var hs: Dictionary = Activities.hs
	var spot: Dictionary = {}
	if hs.get("phase") == "seeking":
		spot = Activities.near_acorn if not Activities.near_acorn.is_empty() else hs.get("acorn", {})
	_acorn.visible = not spot.is_empty() and spot.get("space", "") == world.view_space
	if _acorn.visible:
		_acorn.global_position = Vector3(spot["x"], 0.0, spot["z"])
		_acorn.get_node("Beam").visible = hs.get("hint", false)
	var me: Node3D = world.local_kid()
	_warm_fx.emitting = hs.get("phase") == "seeking" and Activities.warmth >= 2 and me != null
	_warm_fx.amount = 4 + Activities.warmth * 6


func acorn_visible() -> bool:
	return _acorn.visible


# ------------------------------------------------------------- rooms

## Called after a room is built: heart stickers on the back wall and, in living
## rooms, the guest book stand.
func decorate_room(room_root: Node3D, space: String) -> void:
	_room_extras = Node3D.new()
	room_root.add_child(_room_extras)
	var r := TownModel.parse_room(space)
	if r.get("floor", -1) == 0 and r.get("room", -1) == 0:
		var stand := Node3D.new()
		stand.position = Vector3(GUEST_BOOK.x, 0, GUEST_BOOK.y)
		stand.rotation_degrees.y = 90
		_room_extras.add_child(stand)
		Kit.cyl(stand, 0.05, 0.07, 0.9, Palette.WOOD, Vector3(0, 0.45, 0))
		Kit.box(stand, Vector3(0.5, 0.06, 0.36), Palette.WOOD, Vector3(0, 0.92, 0), 0.03, Vector3(-20, 0, 0))
		Kit.box(stand, Vector3(0.42, 0.05, 0.3), Palette.paint(0), Vector3(0, 0.96, 0), 0.02, Vector3(-20, 0, 0))
		Kit.box(stand, Vector3(0.03, 0.06, 0.3), Palette.paint(3), Vector3(0, 0.98, 0), 0.01, Vector3(-20, 0, 0))
		var l := Label3D.new()
		l.text = tr("Guest book")
		l.font = I18n.ui_font()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.0035
		l.font_size = 40
		l.outline_size = 12
		l.modulate = Color("#557c5e")
		l.outline_modulate = Color("#fffdf6")
		l.position.y = 1.4
		stand.add_child(l)
	_refresh_hearts(space)


func _refresh_hearts(space: String) -> void:
	if _room_extras == null or not is_instance_valid(_room_extras):
		return
	var old := _room_extras.get_node_or_null("Hearts")
	if old:
		old.free()
	var hearts := Node3D.new()
	hearts.name = "Hearts"
	_room_extras.add_child(hearts)
	var room: Dictionary = Session.model.hearts.get(space, {})
	var i := 0
	for pid in room:
		var x := -2.9 + i * 0.9
		var h := Node3D.new()
		h.position = Vector3(x, 2.3, -TownModel.ROOM_HALF.y + 0.05)
		hearts.add_child(h)
		var c := Color("#ef6f86")
		for side in [-1, 1]:
			Kit.ball(h, 0.11, c, Vector3(side * 0.08, 0.04, 0), Vector3(1, 1, 0.4))
		Kit.part(h, Kit.cylinder(0.0, 0.16, 0.2, 4), c, Vector3(0, -0.09, 0), Vector3(180, 45, 0), Vector3(1, 1, 0.3))
		var l := Label3D.new()
		l.text = room[pid]
		l.font = I18n.ui_font()
		l.pixel_size = 0.003
		l.font_size = 36
		l.outline_size = 10
		l.modulate = Color("#b4544a")
		l.outline_modulate = Color("#fffdf6")
		l.position = Vector3(0, -0.32, 0.02)
		h.add_child(l)
		i += 1
		if i >= 8:
			break


# ------------------------------------------------------------- weather and data

func _on_data(key: String) -> void:
	match key:
		"weather":
			_apply_weather(Session.model.weather)
		"hearts":
			if world.view_space != "town":
				_refresh_hearts(world.view_space)


func _apply_weather(w: String) -> void:
	for c in _weather_root.get_children():
		c.queue_free()
	world.set_weather_tint(w)
	if w == "sunny":
		return
	var half := TownModel.TOWN_HALF
	var p := CPUParticles3D.new()
	p.amount = 160 if w == "rain" else 90
	p.lifetime = 2.5 if w == "rain" else 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half.x, 0.5, half.y)
	p.position.y = 9.0
	p.direction = Vector3(0, -1, 0)
	p.spread = 5 if w == "rain" else 25
	p.gravity = Vector3(0, -9.0 if w == "rain" else -0.6, 0)
	p.initial_velocity_min = 4.0 if w == "rain" else 0.3
	p.initial_velocity_max = 6.0 if w == "rain" else 0.8
	var m := BoxMesh.new()
	match w:
		"rain":
			m.size = Vector3(0.02, 0.3, 0.02)
		"snow":
			m.size = Vector3(0.13, 0.13, 0.13)
		_:
			m.size = Vector3(0.14, 0.02, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"rain": Color("#7fb0d6"), "snow": Color("#ffffff"), "autumn": Color("#e9934b")}[w]
	m.material = mat
	p.mesh = m
	p.emitting = true
	_weather_root.add_child(p)
	if w == "rain":
		for pt in TownModel.PUDDLES:
			Kit.part(_weather_root, Kit.cylinder(0.9, 0.9, 0.02, 24), Kit.mat(Color("#7fb5cf"), 0.1), Vector3(pt.x, 0.02, pt.y), Vector3.ZERO, Vector3(1, 1, 0.7))


# ------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_t += delta
	var me: Node3D = world.local_kid()
	var vane: Node3D = _landmarks.get("vane")
	if vane:
		vane.get_node("Spin").rotation.y = sin(_t * 0.5) * 1.2
	if _acorn.visible:
		_acorn.rotation.y += delta * 1.5
		_acorn.get_node("Glow").scale = Vector3.ONE * (1.0 + sin(_t * 4.0) * 0.15)
	if me:
		_warm_fx.global_position = me.global_position + Vector3(0, 1.8, 0)
	# Wish bubble over the animal who is wishing.
	var active: Dictionary = Session.model.wishes.get("active", {})
	var animal: Node3D = world.animals.get(active.get("animal", ""))
	_wish_bubble.visible = animal != null and animal.visible
	if _wish_bubble.visible:
		_wish_bubble.global_position = animal.global_position + Vector3(0, 1.4 if active["animal"] != "elephant" else 2.4, 0) + Vector3(0, sin(_t * 3.0) * 0.08, 0)
