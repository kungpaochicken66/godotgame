## The visible 3D town or cottage interior, kept in sync with Session.model.
##
## Only one space is shown at a time: the outdoor town, or the inside of the
## cottage the local child has entered. Also owns lighting, evening mode,
## the Wishing Tree with its lanterns, Cozy Spot sparkles and other children.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Props := preload("res://scripts/art/props.gd")
const KidScript := preload("res://scripts/art/kid.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")

signal view_changed(space: String)

var view_space := "town"
var item_nodes := {}          # id -> Node3D for items in view_space
var kids := {}                # peer id -> kid node
var evening := 0.0            # 0 day .. 1 evening, animated

var _town: Node3D
var _room: Node3D
var _items_root: Node3D
var _spots_root: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _lanterns := {}           # spot -> Node3D
var _fireflies: CPUParticles3D
var _evening_target := 0.0
var _t := 0.0
var _lock_tags := {}          # item id -> Label3D

const DAY_SKY := Color("#cfe9ef")
const EVENING_SKY := Color("#3c4a78")


func _ready() -> void:
	_build_environment()
	_town = Node3D.new()
	_town.name = "Town"
	add_child(_town)
	_build_town_ground()
	_build_wishing_tree()
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_spots_root = Node3D.new()
	_spots_root.name = "Spots"
	add_child(_spots_root)
	Session.town_reset.connect(_rebuild_items)
	Session.item_changed.connect(_on_item_changed)
	Session.items_removed.connect(_on_items_removed)
	Session.players_changed.connect(_sync_players)
	Session.player_state.connect(_on_player_state)
	Session.emote.connect(_on_emote)
	Session.lantern_lit.connect(_on_lantern_lit)
	Session.evening_changed.connect(_on_evening)
	Session.lock_changed.connect(_on_lock_changed)
	I18n.locale_changed.connect(func(_c): _refresh_labels())
	set_view("town")


# ------------------------------------------------------------- environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = DAY_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#eef3ef")
	_env.ambient_light_energy = 0.5
	_env.fog_enabled = true
	_env.fog_light_color = DAY_SKY
	_env.fog_density = 0.004
	we.environment = _env
	add_child(we)
	# Real-time shadows are off: soft blob shadows keep objects grounded,
	# cost less on iPad and avoid a lighting artifact seen in the test renderer.
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_sun.light_energy = 0.8
	_sun.light_color = Color("#fff4e0")
	add_child(_sun)


func _on_evening(on: bool) -> void:
	_evening_target = 1.0 if on else 0.0


func _apply_evening() -> void:
	var e := evening
	_env.background_color = DAY_SKY.lerp(EVENING_SKY, e)
	_env.fog_light_color = _env.background_color
	_env.ambient_light_color = Color("#eef3ef").lerp(Color("#c9c2ee"), e)
	_env.ambient_light_energy = lerpf(0.5, 0.55, e)
	_sun.light_energy = lerpf(0.8, 0.32, e)
	_sun.light_color = Color("#fff4e0").lerp(Color("#ffb37a"), e)
	get_tree().call_group("lamp", "set", "light_energy", 1.6 * e)
	for g in get_tree().get_nodes_in_group("glow"):
		var m := (g as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			var glow: Color = g.get_meta("glow_color", Color("#ffd98a"))
			m.emission = glow
			m.emission_energy_multiplier = lerpf(0.15, 0.9, e)
	if _fireflies:
		_fireflies.emitting = e > 0.5 and view_space == "town"


# ------------------------------------------------------------- town and room

func _build_town_ground() -> void:
	var half := TownModel.TOWN_HALF
	# Raised lawn plateau with soft edges, then a lower meadow that continues beyond.
	Kit.part(_town, Kit.rounded_box(Vector3(half.x * 2 + 1.2, 1.0, half.y * 2 + 1.2), 0.45), Palette.GRASS, Vector3(0, -0.5, 0))
	var meadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	meadow.mesh = pm
	meadow.material_override = Kit.mat(Palette.GRASS_DARK)
	meadow.position.y = -0.55
	_town.add_child(meadow)
	# Plaza around the Wishing Tree.
	var plaza := Kit.part(_town, Kit.cylinder(3.4, 3.4, 0.04, 48), Palette.PATH, Vector3(TownModel.WISHING_TREE.x, 0.0, TownModel.WISHING_TREE.y))
	plaza.name = "Plaza"
	# Decorative woods and hills outside the editable area so the town feels nestled.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# The forest is flattened into one mesh: one draw call instead of seventy.
	var forest := Node3D.new()
	forest.name = "Forest"
	_town.add_child(forest)
	for i in 70:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * (half.x + 3.5 + rng.randf() * 14.0), sin(a) * (half.y + 3.5 + rng.randf() * 12.0))
		var tree := Props.build("pine" if rng.randf() < 0.45 else "tree", [5, 5, 5, 1, 3][rng.randi() % 5], i)
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(1.0, 1.6)), Vector3(p.x, -0.55, p.y))
		var merged := tree.get_node("Merged") as MeshInstance3D
		tree.remove_child(merged)
		merged.transform = xf * merged.transform
		merged.material_override = Kit.mat(Color.WHITE)
		merged.set_meta("vertex_colors", true)
		forest.add_child(merged)
		tree.free()
	Kit.merge_parts(forest)
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		Kit.ball(_town, 14.0, Palette.GRASS_DARK.darkened(0.05), Vector3(cos(a) * 52, -9.5, sin(a) * 46), Vector3(1.6, 1, 1))
	_fireflies = CPUParticles3D.new()
	_fireflies.amount = 40
	_fireflies.lifetime = 4.0
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fireflies.emission_box_extents = Vector3(half.x, 0.8, half.y)
	_fireflies.position.y = 1.2
	_fireflies.gravity = Vector3(0, 0.05, 0)
	_fireflies.initial_velocity_min = 0.1
	_fireflies.initial_velocity_max = 0.3
	_fireflies.direction = Vector3(0, 1, 0)
	_fireflies.spread = 180
	var fm := SphereMesh.new()
	fm.radius = 0.05
	fm.height = 0.1
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("#fff3a0")
	fm.material = fmat
	_fireflies.mesh = fm
	_fireflies.emitting = false
	_town.add_child(_fireflies)
	Kit.merge_parts(_town)


func _build_wishing_tree() -> void:
	var root := Node3D.new()
	root.name = "WishingTree"
	root.position = Vector3(TownModel.WISHING_TREE.x, 0, TownModel.WISHING_TREE.y)
	_town.add_child(root)
	Kit.blob_shadow(root, 2.6, 0.3)
	Kit.cyl(root, 0.42, 0.7, 3.0, Palette.WOOD_DARK, Vector3(0, 1.5, 0))
	for a in [0.0, 2.1, 4.2]:
		Kit.cyl(root, 0.12, 0.35, 0.8, Palette.WOOD_DARK, Vector3(cos(a) * 0.65, 0.2, sin(a) * 0.65), Vector3(sin(a) * 60, 0, -cos(a) * 60))
	var leaf := Color("#8cc77a")
	Kit.ball(root, 2.3, leaf, Vector3(0, 4.6, 0), Vector3(1.1, 0.8, 1.1))
	for i in 6:
		var a := TAU * i / 6.0
		Kit.ball(root, 1.4, leaf.darkened(0.05 + 0.03 * (i % 2)), Vector3(cos(a) * 1.9, 3.9, sin(a) * 1.9))
	# Eight lantern hooks under the canopy, one per Cozy Spot.
	for i in CozySpots.ORDER.size():
		var spot: String = CozySpots.ORDER[i]
		var a := TAU * i / 8.0 + 0.3
		var hook := Node3D.new()
		hook.position = Vector3(cos(a) * 3.15, 2.05, sin(a) * 3.15)
		root.add_child(hook)
		Kit.cyl(hook, 0.012, 0.012, 1.0, Color("#6b5a48"), Vector3(0, 0.5, 0))
		var lantern := Node3D.new()
		lantern.name = spot
		hook.add_child(lantern)
		var c: Color = CozySpots.SPOTS[spot]["lantern"]
		var body := Kit.part(lantern, Kit.rounded_box(Vector3(0.34, 0.42, 0.34), 0.14), Kit.glow_mat(c), Vector3(0, -0.2, 0))
		body.add_to_group("glow")
		body.set_meta("glow_color", c)
		Kit.box(lantern, Vector3(0.24, 0.06, 0.24), Palette.WOOD_DARK, Vector3(0, 0.03, 0), 0.02)
		Kit.box(lantern, Vector3(0.24, 0.06, 0.24), Palette.WOOD_DARK, Vector3(0, -0.43, 0), 0.02)
		var light := OmniLight3D.new()
		light.light_color = c
		light.omni_range = 3.0
		light.light_energy = 0.0
		light.position.y = -0.2
		light.add_to_group("lamp")
		lantern.add_child(light)
		_lanterns[spot] = lantern
	# The evening bell in front of the tree.
	var bell := Node3D.new()
	bell.name = "Bell"
	bell.position = Vector3(1.6, 0, 1.9)
	root.add_child(bell)
	Kit.box(bell, Vector3(0.14, 1.7, 0.14), Palette.WOOD, Vector3(0, 0.85, 0), 0.05)
	Kit.box(bell, Vector3(0.7, 0.12, 0.14), Palette.WOOD, Vector3(-0.28, 1.7, 0), 0.05)
	Kit.cyl(bell, 0.1, 0.2, 0.28, Palette.paint(1), Vector3(-0.5, 1.48, 0))
	Kit.ball(bell, 0.05, Palette.WOOD_DARK, Vector3(-0.5, 1.33, 0))
	Kit.merge_parts(root)
	_refresh_lanterns()


func bell_point() -> Vector2:
	return TownModel.WISHING_TREE + Vector2(1.6, 2.5)


func _refresh_lanterns() -> void:
	for spot in _lanterns:
		_lanterns[spot].visible = Session.model.lanterns.has(spot)


func _build_room(house: Dictionary) -> void:
	for c in _room.get_children():
		c.queue_free()
	var half := TownModel.ROOM_HALF
	var wall_c := Palette.paint(house.get("color", 0)).lerp(Palette.PLASTER, 0.72)
	var floor_c := Color("#e1b67f")
	# Dark surroundings so the dollhouse room reads as a cozy box.
	var base := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	base.mesh = pm
	base.material_override = Kit.mat(Color("#cbbfa8"))
	base.position.y = -0.3
	_room.add_child(base)
	Kit.part(_room, Kit.rounded_box(Vector3(half.x * 2 + 0.6, 0.5, half.y * 2 + 0.6), 0.12), floor_c, Vector3(0, -0.25, 0))
	for i in range(-3, 4):
		Kit.box(_room, Vector3(half.x * 2 + 0.4, 0.012, 0.03), floor_c.darkened(0.08), Vector3(0, 0.002, i * 0.85), 0.005)
	# Back wall with the exit door, left wall with a window. Front and right are cut away.
	Kit.box(_room, Vector3(half.x * 2 + 0.6, 2.8, 0.3), wall_c, Vector3(0, 1.4, -half.y - 0.15), 0.08)
	Kit.box(_room, Vector3(0.3, 2.8, half.y * 2 + 0.6), wall_c.darkened(0.06), Vector3(-half.x - 0.15, 1.4, 0), 0.08)
	Kit.box(_room, Vector3(half.x * 2 + 0.6, 0.16, 0.34), Palette.WOOD, Vector3(0, 0.08, -half.y - 0.12), 0.04)
	Kit.box(_room, Vector3(0.34, 0.16, half.y * 2 + 0.6), Palette.WOOD, Vector3(-half.x - 0.12, 0.08, 0), 0.04)
	var door_c := Palette.paint(house.get("color", 0)).darkened(0.15)
	var dx := TownModel.ROOM_DOOR.x
	Kit.box(_room, Vector3(1.0, 1.7, 0.12), door_c, Vector3(dx, 0.85, -half.y + 0.02), 0.1)
	Kit.ball(_room, 0.06, Palette.paint(1), Vector3(dx + 0.32, 0.85, -half.y + 0.1))
	Kit.box(_room, Vector3(1.3, 0.04, 0.8), Palette.paint(5).darkened(0.1), Vector3(dx, 0.02, -half.y + 0.55), 0.02)
	var win := Node3D.new()
	win.position = Vector3(-half.x + 0.02, 1.5, -0.3)
	win.rotation_degrees.y = 90
	_room.add_child(win)
	Kit.box(win, Vector3(1.1, 1.0, 0.12), Palette.WOOD, Vector3.ZERO, 0.06)
	var glass := Kit.box(win, Vector3(0.9, 0.8, 0.14), Kit.glow_mat(Color("#bfe3f0")), Vector3(0, 0, 0.01), 0.04)
	glass.add_to_group("glow")
	glass.set_meta("glow_color", Color("#7a86c8"))
	Kit.box(win, Vector3(0.06, 0.8, 0.16), Palette.WOOD, Vector3.ZERO, 0.02)
	# A warm ceiling light so evening interiors stay cozy.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 0)
	lamp.omni_range = 7.0
	lamp.light_energy = 0.0
	lamp.light_color = Color("#ffd8a0")
	lamp.add_to_group("lamp")
	_room.add_child(lamp)
	Kit.merge_parts(_room)


# ------------------------------------------------------------- view switching

func set_view(space: String) -> void:
	if space != "town" and not Session.model.is_space(space):
		space = "town"
	view_space = space
	_town.visible = space == "town"
	_room.visible = space != "town"
	if space != "town":
		_build_room(Session.model.items[space])
	_rebuild_items()
	_sync_players()
	view_changed.emit(space)


func _rebuild_items() -> void:
	if view_space != "town" and not Session.model.is_space(view_space):
		set_view("town")
		return
	for n in item_nodes.values():
		n.queue_free()
	item_nodes.clear()
	for t in _lock_tags.values():
		t.queue_free()
	_lock_tags.clear()
	for item in Session.model.items_in(view_space):
		_make_item(item, false)
	for id in Session.locks:
		_on_lock_changed(id, Session.locks[id])
	_refresh_lanterns()
	_refresh_spots()
	_apply_evening()


func _make_item(item: Dictionary, pop := true) -> Node3D:
	var node := Props.build(item["kind"], item["color"], int(item["id"].substr(1)))
	node.set_meta("item", item.duplicate())
	node.position = Vector3(item["x"], 0, item["z"])
	node.rotation.y = TownModel.rot_to_radians(item["rot"])
	_items_root.add_child(node)
	item_nodes[item["id"]] = node
	if pop:
		node.scale = Vector3.ONE * 0.5
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_apply_evening()
	return node


func _on_item_changed(item: Dictionary) -> void:
	if item["space"] != view_space:
		return
	var old: Node3D = item_nodes.get(item["id"])
	if old == null:
		_make_item(item)
	else:
		var prev: Dictionary = old.get_meta("item")
		if prev["color"] != item["color"] or prev["kind"] != item["kind"]:
			old.queue_free()
			item_nodes.erase(item["id"])
			_make_item(item)
		else:
			old.set_meta("item", item.duplicate())
			var tw := create_tween().set_parallel()
			tw.tween_property(old, "position", Vector3(item["x"], 0, item["z"]), 0.2)
			tw.tween_property(old, "rotation:y", _closest_angle(old.rotation.y, TownModel.rot_to_radians(item["rot"])), 0.2)
	_refresh_spots()


static func _closest_angle(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)


func _on_items_removed(ids: Array) -> void:
	for id in ids:
		var n: Node3D = item_nodes.get(id)
		if n:
			item_nodes.erase(id)
			var tw := create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(n.queue_free)
		if _lock_tags.has(id):
			_lock_tags[id].queue_free()
			_lock_tags.erase(id)
	if view_space != "town" and ids.has(view_space):
		set_view("town")
	_refresh_spots()


# ------------------------------------------------------------- Cozy Spots

func _refresh_spots() -> void:
	for c in _spots_root.get_children():
		c.queue_free()
	for s in CozySpots.detect(Session.model):
		if s["space"] != view_space:
			continue
		var marker := Node3D.new()
		marker.position = Vector3(s["at"].x, 0.05, s["at"].y)
		_spots_root.add_child(marker)
		var c: Color = CozySpots.SPOTS[s["spot"]]["lantern"]
		var ring := Kit.part(marker, Kit.torus(0.9, 1.0), Kit.glow_mat(c), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.3, 1))
		ring.set_meta("pulse", true)
		var sparkle := CPUParticles3D.new()
		sparkle.amount = 10
		sparkle.lifetime = 1.6
		sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sparkle.emission_sphere_radius = 0.9
		sparkle.gravity = Vector3(0, 0.35, 0)
		sparkle.initial_velocity_min = 0.05
		sparkle.initial_velocity_max = 0.2
		sparkle.scale_amount_min = 0.5
		sparkle.scale_amount_max = 1.0
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.08
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = c.lightened(0.4)
		sm.material = smat
		sparkle.mesh = sm
		sparkle.position.y = 0.6
		marker.add_child(sparkle)


func _on_lantern_lit(spot: String, _by: Array) -> void:
	_refresh_lanterns()
	if _lanterns.has(spot) and view_space == "town":
		var l: Node3D = _lanterns[spot]
		l.scale = Vector3.ONE * 0.1
		create_tween().tween_property(l, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Where a newly formed spot of this kind is, for celebrations and the camera.
func spot_position(spot: String) -> Variant:
	for s in CozySpots.detect(Session.model):
		if s["spot"] == spot and s["space"] == view_space:
			return Vector3(s["at"].x, 0, s["at"].y)
	return null


# ------------------------------------------------------------- children

func _sync_players() -> void:
	for peer in kids.keys():
		if not Session.players.has(peer):
			kids[peer].queue_free()
			kids.erase(peer)
	for peer in Session.players:
		var p: Dictionary = Session.players[peer]
		var kid: Node3D = kids.get(peer)
		if kid == null:
			kid = KidScript.new()
			add_child(kid)
			kid.setup(p["avatar"])
			kids[peer] = kid
			var s: Dictionary = p.get("state", {})
			kid.set_target(Vector3(s.get("x", 0.0), 0, s.get("z", 0.0)), s.get("ry", 0.0), true)
			if peer == Session.my_id:
				kid.interpolate = false
		_update_kid_visibility(peer)


func local_kid() -> Node3D:
	return kids.get(Session.my_id)


func _update_kid_visibility(peer: int) -> void:
	var kid: Node3D = kids.get(peer)
	if kid and peer != Session.my_id:
		kid.visible = Session.players.get(peer, {}).get("state", {}).get("space", "town") == view_space


func _on_player_state(peer: int, s: Dictionary) -> void:
	var kid: Node3D = kids.get(peer)
	if kid == null or peer == Session.my_id:
		return
	var was_hidden := not kid.visible
	_update_kid_visibility(peer)
	var anim: String = s.get("anim", "idle")
	if anim in ["sit", "swing", "ride", "rest"]:
		kid.anim = anim
	elif kid.anim in ["sit", "swing", "ride", "rest"]:
		kid.anim = "idle"
	kid.set_target(Vector3(s["x"], 0, s["z"]), s["ry"], was_hidden)


func _on_emote(peer: int, kind: String) -> void:
	var kid: Node3D = kids.get(peer)
	if kid:
		kid.play_emote(kind)


func _refresh_labels() -> void:
	for k in kids.values():
		k.refresh_label()
	for id in _lock_tags.keys():
		_on_lock_changed(id, Session.lock_holder(id))


func _on_lock_changed(item_id: String, peer: int) -> void:
	if _lock_tags.has(item_id):
		_lock_tags[item_id].queue_free()
		_lock_tags.erase(item_id)
	if peer == 0 or peer == Session.my_id or not item_nodes.has(item_id):
		return
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.004
	tag.font_size = 40
	tag.outline_size = 12
	tag.font = I18n.ui_font()
	tag.modulate = Color("#557c5e")
	tag.outline_modulate = Color("#fffdf6")
	tag.text = tr("%s is decorating here") % tr(Session.nick_of(peer))
	tag.position = item_nodes[item_id].position + Vector3(0, 2.4, 0)
	add_child(tag)
	_lock_tags[item_id] = tag


# ------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_t += delta
	if absf(evening - _evening_target) > 0.001:
		evening = move_toward(evening, _evening_target, delta * 0.5)
		_apply_evening()
	for marker in _spots_root.get_children():
		marker.rotation.y += delta * 0.6
		var s := 1.0 + sin(_t * 3.0) * 0.06
		marker.scale = Vector3(s, 1, s)
	for lantern in _lanterns.values():
		lantern.rotation.z = sin(_t * 1.3 + lantern.get_index()) * 0.08
	_animate_play_items()


## Swings sway and seesaws rock while children ride them; seated children follow seats.
func _animate_play_items() -> void:
	var seated := {}
	for item_id in Session.seats:
		var node: Node3D = item_nodes.get(item_id)
		if node == null:
			continue
		var holders: Dictionary = Session.seats[item_id]
		var pivot := node.get_node_or_null("Pivot") as Node3D
		if pivot:
			match node.get_meta("item")["kind"]:
				"swing":
					pivot.rotation.x = sin(_t * 2.4) * 0.55
				"seesaw":
					if holders.size() >= 2:
						pivot.rotation.x = sin(_t * 2.0) * 0.22
					else:
						var side := 1.0 if holders.has(0) else -1.0
						pivot.rotation.x = side * (0.18 + sin(_t * 3.0) * 0.03)
		for s in holders:
			var peer: int = holders[s]
			var marker := node.find_child("Seat%d" % s, true, false) as Node3D
			var kid: Node3D = kids.get(peer)
			if marker and kid:
				kid.global_transform = marker.global_transform * Transform3D(Basis(), Vector3(0, -KidScript.HIP_HEIGHT + 0.02, -0.06))
				kid.anim = {"swing": "swing", "seesaw": "ride", "bed": "rest"}.get(node.get_meta("item")["kind"], "sit")
				seated[peer] = true
	for id in item_nodes:
		if Session.seats.has(id):
			continue
		var pivot := item_nodes[id].get_node_or_null("Pivot") as Node3D
		if pivot:
			pivot.rotation.x = lerpf(pivot.rotation.x, 0.0, 0.05)
	for peer in kids:
		var kid: Node3D = kids[peer]
		if not seated.has(peer) and kid.anim in ["sit", "swing", "ride", "rest"]:
			kid.anim = "idle"
			kid.rotation.x = 0.0
			kid.rotation.z = 0.0
			var st: Dictionary = Session.players.get(peer, {}).get("state", {})
			if peer != Session.my_id and not st.is_empty():
				kid.set_target(Vector3(st["x"], 0, st["z"]), st["ry"], true)


# ------------------------------------------------------------- queries for controllers

## Projects a screen point onto the ground plane (y = 0).
func ground_point(camera: Camera3D, screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-4:
		return null
	var t := -from.y / dir.y
	if t < 0:
		return null
	var p := from + dir * t
	return Vector2(p.x, p.z)


## The item under a screen point, judged by projected footprint and height.
func pick_item(camera: Camera3D, screen: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in item_nodes:
		var node: Node3D = item_nodes[id]
		var item: Dictionary = node.get_meta("item")
		var r: float = Catalog.get_def(item["kind"])["radius"]
		for h in [0.15, 0.6, 1.2]:
			var c := node.global_position + Vector3(0, h * clampf(r, 0.4, 2.0), 0)
			if camera.is_position_behind(c):
				continue
			var sp := camera.unproject_position(c)
			var edge := camera.unproject_position(c + camera.global_basis.x * r)
			var pr := maxf(sp.distance_to(edge), 22.0)
			var d := sp.distance_to(screen)
			if d < pr and d / pr < best_d:
				best_d = d / pr
				best = id
	return best


## Pushes a walking child out of solid items, walls and the Wishing Tree.
func resolve_walk(p: Vector2, body := 0.28) -> Vector2:
	var half := TownModel.TOWN_HALF if view_space == "town" else TownModel.ROOM_HALF
	for item in Session.model.items_in(view_space):
		var def := Catalog.get_def(item["kind"])
		if def["layer"] != "solid":
			continue
		var c := Vector2(item["x"], item["z"])
		var r: float = def["radius"] * (0.8 if item["kind"] != "cottage" else 0.95) + body
		var d := p - c
		if d.length() < r:
			p = c + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * r
	if view_space == "town":
		var t := TownModel.WISHING_TREE
		if p.distance_to(t) < 1.0 + body:
			p = t + (p - t).normalized() * (1.0 + body)
	p.x = clampf(p.x, -half.x + body, half.x - body)
	p.y = clampf(p.y, -half.y + body, half.y - body)
	return p
