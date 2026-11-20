## The visible 3D town or cottage interior, kept in sync with Session.model.
##
## Only one space is shown at a time: the outdoor town, or the inside of the
## cottage the local child has entered. Also owns lighting, evening mode,
## the Wishing Tree with its lanterns, Cozy Spot sparkles and other children.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Props := preload("res://scripts/art/props.gd")
const KidScript := preload("res://scripts/art/kid.gd")
const AnimalScript := preload("res://scripts/art/animal.gd")
const ActivityWorld := preload("res://scripts/world/activity_world.gd")
const PetWorld := preload("res://scripts/world/pet_world.gd")
const GuestWorld := preload("res://scripts/world/guest_world.gd")
const DecoMotion := preload("res://scripts/world/deco_motion.gd")
const PlayWorld := preload("res://scripts/world/play_world.gd")
const ContraptionWorld := preload("res://scripts/world/contraption_world.gd")
const PuzzleWorld := preload("res://scripts/world/puzzle_world.gd")
const RideWorld := preload("res://scripts/world/ride_world.gd")
const EchoWorld := preload("res://scripts/world/echo_world.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Places := preload("res://scripts/core/places.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooWorld := preload("res://scripts/world/zoo_world.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const ThousandWorld := preload("res://scripts/world/thousand_world.gd")
const ThousandPeople := preload("res://scripts/art/thousand_people.gd")
const ThousandTransit := preload("res://scripts/world/thousand_transit.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const ThousandEvents := preload("res://scripts/world/thousand_events.gd")

signal view_changed(space: String)

var view_space := "town"
var item_nodes := {}          # id -> Node3D for items in view_space
var kids := {}                # peer id -> kid node
var animals := {}             # species -> animal node (outdoors only)
var activity: Node3D          # activity landmarks, weather, acorn, hearts (activity_world.gd)
var pet_layer: Node3D         # companion pets (pet_world.gd)
var guest_layer: Node3D       # animal friends visiting a house (guest_world.gd, r18)
## Decorative motion (r20, deco_motion.gd): item id -> motion state, only for items of the space on screen.
var deco := {}
## Local Reduce motion setting (user://settings.cfg): decorations stay still.
var reduce_motion := DecoMotion.load_reduce()
var play_fx: Node3D           # track ball, music boxes, trail arrow (play_world.gd)
var contraptions: Node3D      # links, sparks, pinwheels, bubbles, rings (contraption_world.gd)
var puzzle_fx: Node3D         # puzzle rooms: keys, dials, chest lights and lid (puzzle_world.gd)
var ride_fx: Node3D           # rideable carts on their rails (ride_world.gd)
var echo_fx: Node3D           # friends' hellos: see-through figures (echo_world.gd)
var _weather_tint: MeshInstance3D
var weather_now := "sunny"     # the town's weather, also shown in the zoo
var evening := 0.0            # 0 day .. 1 evening, animated

var _town: Node3D
var _room: Node3D
## The zoo map (zoo_world.gd): created the first time a child goes there, kept afterwards.
var zoo_world: Node3D
const CITY_PEOPLE_SCRIPT := "res://scripts/art/city_people.gd"
var city_people: Node3D = null   # city r2: the city's people (art/city_people.gd), a child of city_world
var city_world: Node3D            # city r1: the miniature city district, built the first time it is shown
## city-web: the web city's logic-only CityWorld (never built, never drawn): the static poses of seats and
## gondolas, and the wheel's angle on the CityWeb clock. The page draws the city; Godot places the children.
var city_logic: Node3D
## city-web: what the cutaway would hide in the web city ({"hidden", "regions"}, see web_cutaway) and a
## counter that changes whenever it changes (the bridge sends it to the page then).
var _web_cutaway := {"hidden": {}, "regions": []}
## thousand-town: Thousand Town's world (world/thousand_world.gd), built the first time it is shown (or behind the
## journey card, prepare_thousand), kept afterwards; under it its residents (art/thousand_people.gd) and its buses,
## taxis and street traffic (world/thousand_transit.gd), both on the world's sim and today's plans and both set to
## the same view time as the light, once a frame (_thousand_frame).
var thousand_world: Node3D
var thousand_people: Node3D
var thousand_transit: Node3D
## The fireworks and the plaza fountain's jets (world/thousand_events.gd: status(), watch_point(kind)), under the
## Thousand world, driving itself from the world's view time and the camera (drive); 400 sparks on the TV.
var thousand_events: Node = null
var _thousand_plans: RefCounted = null
var _thousand_frame_no := -1
var _thousand_tv := -1
var web_cutaway_rev := 0
var _items_root: Node3D
var _spots_root: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _lanterns := {}           # spot -> Node3D
var _twinkling := false       # dance party: every lantern hangs out and twinkles
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
	activity = ActivityWorld.new()
	activity.name = "Activities"
	add_child(activity)
	activity.setup(self, _town)
	pet_layer = PetWorld.new()
	pet_layer.name = "Pets"
	add_child(pet_layer)
	pet_layer.setup(self)
	guest_layer = GuestWorld.new()
	guest_layer.name = "Guests"
	add_child(guest_layer)
	guest_layer.setup(self)
	Animals.guests_changed.connect(func(_g): _update_animal_visibility())
	play_fx = PlayWorld.new()
	add_child(play_fx)
	play_fx.setup(self)
	contraptions = ContraptionWorld.new()
	contraptions.name = "Contraptions"
	add_child(contraptions)
	contraptions.setup(self)
	puzzle_fx = PuzzleWorld.new()
	add_child(puzzle_fx)
	puzzle_fx.setup(self)
	ride_fx = RideWorld.new()
	add_child(ride_fx)
	ride_fx.setup(self)
	echo_fx = EchoWorld.new()
	echo_fx.name = "Echoes"
	add_child(echo_fx)
	echo_fx.setup(self)
	Animals.focus_changed.connect(func(_f): _refresh_animal_lines())
	Session.cooking_changed.connect(func(stove, _recipe, on): _steam(stove, on))
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
	Session.avatar_changed.connect(func(peer):
		var kid: Node3D = kids.get(peer)
		if kid and Session.players.has(peer):
			kid.setup(Session.players[peer]["avatar"]))
	Session.lantern_lit.connect(_on_lantern_lit)
	Session.evening_changed.connect(_on_evening)
	Session.lamplight.connect(_on_lamplight)
	Session.lock_changed.connect(_on_lock_changed)
	Animals.updated.connect(_on_animals)
	Animals.thrown.connect(func(from: Vector2, to: Vector2):
		if animals.has("dog"):
			animals["dog"].show_throw(from, to))
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


var lamplight_drawn := 0      # times the fireflies gathered on this device (for tests)

## Every lamp post is lit this evening: fireflies rise around each one, with a soft chime.
## With Reduce motion on, the chime and the message stay and nothing flies.
func _on_lamplight(_by: Array) -> void:
	lamplight_drawn += 1
	Sfx.play("lantern")
	if reduce_motion or view_space != "town":
		return
	for id in item_nodes:
		var node: Node3D = item_nodes[id]
		if node.get_meta("item")["kind"] != "lamp_post":
			continue
		var p := CPUParticles3D.new()
		p.name = "LamplightFireflies"
		p.one_shot = true
		p.amount = 14
		p.lifetime = 3.0
		p.explosiveness = 0.2
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.9
		p.gravity = Vector3(0, 0.35, 0)
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.4
		p.mesh = Kit.sphere(0.035, 4)
		p.material_override = Kit.mat(Color("#fff3a8"), 0.4, Color("#ffe98a"))
		p.position = Vector3(0, 1.9, 0)
		node.add_child(p)
		p.emitting = true
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free())


func _apply_evening() -> void:
	var e := evening
	_env.background_color = weather_sky.lerp(EVENING_SKY, e)
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
	_apply_switched_lamps()
	if Places.is_city(view_space):
		_city_light(_city_weights())   # the city keeps its own light, whatever the town's evening
	elif view_space == Places.THOUSAND:
		_thousand_light()   # Thousand Town follows its own clock


## Is this lamp switched on by a contraption (shining by day too)?
func lamp_on(id: String) -> bool:
	var it: Dictionary = Session.model.items.get(id, {})
	return Catalog.LAMPS.has(it.get("kind", "")) and bool(it.get("on", false)) and not it.has("gift")


## How bright an item's own lamp is: fully on when a contraption switched it on, else the evening.
func lamp_level(id: String) -> float:
	return 1.0 if lamp_on(id) else evening


## Lamps a contraption switched on shine whatever the time of day (the evening sets every lamp
## first; this lifts the switched ones), with a soft halo so the lamp reads as lit in daylight.
func _apply_switched_lamps() -> void:
	for id in item_nodes:
		var node: Node3D = item_nodes[id]
		var on := lamp_on(id)
		var halo := node.get_node_or_null("LampHalo") as MeshInstance3D
		if not on:
			if halo:
				halo.queue_free()
				halo.name = "LampHaloGone"
			continue
		var at := Vector3(0, 1.0, 0)
		for l in node.find_children("*", "OmniLight3D", true, false):
			if l.is_in_group("lamp"):
				(l as OmniLight3D).light_energy = 1.6
				at = node.global_transform.affine_inverse() * (l as OmniLight3D).global_position if l.is_inside_tree() else (l as OmniLight3D).position
		for g in node.find_children("*", "MeshInstance3D", true, false):
			if g.is_in_group("glow") and g.material_override is StandardMaterial3D:
				(g.material_override as StandardMaterial3D).emission_energy_multiplier = 0.9
		if halo == null:
			halo = MeshInstance3D.new()
			halo.name = "LampHalo"
			halo.mesh = Kit.sphere(0.22, 10)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1.0, 0.87, 0.5, 0.4)
			halo.material_override = m
			node.add_child(halo)
		halo.position = at


# ------------------------------------------------------------- town and room

func _build_town_ground() -> void:
	var half := TownModel.TOWN_HALF
	# Raised lawn plateau with soft edges, then a lower meadow that continues beyond.
	Kit.part(_town, Kit.rounded_box(Vector3(half.x * 2 + 1.2, 1.0, half.y * 2 + 1.2), 0.45), Palette.GRASS, Vector3(0, -0.5, 0))
	var meadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
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
	# The forest is flattened into one mesh: one draw call instead of a hundred.
	var forest := Node3D.new()
	forest.name = "Forest"
	_town.add_child(forest)
	for i in 110:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * (half.x + 3.5 + rng.randf() * 14.0), sin(a) * (half.y + 3.5 + rng.randf() * 12.0))
		var tree := Props.build("pine" if rng.randf() < 0.45 else "tree", [5, 5, 5, 1, 3][rng.randi() % 5], i)
		# Scenery variety only (0.9-1.2); see design/object-scale-and-surfaces.md.
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.2)), Vector3(p.x, -0.55, p.y))
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
		Kit.ball(_town, 14.0, Palette.GRASS_DARK.darkened(0.05), Vector3(cos(a) * (half.x * 2 + 20), -9.5, sin(a) * (half.y * 2 + 18)), Vector3(1.6, 1, 1))
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


## Weather tints the sky and lays a soft color wash over the lawn (activity H).
func set_weather_tint(w: String) -> void:
	if _weather_tint == null:
		_weather_tint = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(TownModel.TOWN_HALF.x * 2 + 1.0, TownModel.TOWN_HALF.y * 2 + 1.0)
		_weather_tint.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_weather_tint.material_override = m
		_weather_tint.position.y = 0.012
		_weather_tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_town.add_child(_weather_tint)
	var tint := {"sunny": Color(1, 1, 1, 0), "rain": Color(0.32, 0.42, 0.6, 0.16), "autumn": Color(0.9, 0.55, 0.22, 0.22), "snow": Color(1, 1, 1, 0.45)}
	(_weather_tint.material_override as StandardMaterial3D).albedo_color = tint.get(w, tint["sunny"])
	_weather_tint.visible = w != "sunny"
	weather_sky = {"sunny": DAY_SKY, "rain": Color("#a9b8c4"), "autumn": Color("#ecd2b0"), "snow": Color("#dfe8ef")}.get(w, DAY_SKY)
	weather_now = w
	if zoo_world:
		zoo_world.set_weather(w)   # the zoo shows the town's weather (zoo design 10.7)
	_apply_evening()


var weather_sky := DAY_SKY

func bell_point() -> Vector2:
	return TownModel.WISHING_TREE + Vector2(1.6, 2.5)


func _refresh_lanterns() -> void:
	for spot in _lanterns:
		_lanterns[spot].visible = _twinkling or Session.model.lanterns.has(spot)


## During a dance party all eight lanterns hang out and twinkle one after another.
## Afterward only the lit ones stay, at their normal glow.
func _twinkle_lanterns() -> void:
	var on: bool = Activities.is_party()
	if on != _twinkling:
		_twinkling = on
		_refresh_lanterns()
		if not on:
			_apply_evening()
	if not on:
		return
	var i := 0
	for lantern in _lanterns.values():
		var pulse := 0.5 + 0.5 * sin(_t * 6.0 + i * TAU / 8.0)
		for g in lantern.get_children():
			if g.is_in_group("glow"):
				(g.material_override as StandardMaterial3D).emission_energy_multiplier = lerpf(0.3, 1.6, pulse)
		var light: OmniLight3D = lantern.get_child(-1) as OmniLight3D
		if light:
			light.light_energy = lerpf(0.4, 2.0, pulse) * maxf(evening, 0.35)
		i += 1


func lanterns_twinkling() -> bool:
	return _twinkling


## Builds one room of a cottage: floor, back and left walls (front and right are
## cut away like a dollhouse), and a doorway or staircase for every way out.
func _build_room(space: String) -> void:
	for c in _room.get_children():
		c.queue_free()
	var info := TownModel.parse_room(space)
	var house: Dictionary = Session.model.items.get(info["house"], {})
	var half := TownModel.ROOM_HALF
	var tint := Palette.paint(house.get("color", 0))
	# Each room has its own gentle wall color; floors get lighter going up.
	var room_hue: float = [0.0, 0.08, -0.06, 0.12, -0.1, 0.04][info["floor"] * 2 + info["room"]]
	var wall_c := tint.lerp(Palette.PLASTER, 0.72)
	wall_c.h = wrapf(wall_c.h + room_hue, 0.0, 1.0)
	var floor_c := Color("#e1b67f").lightened(0.06 * info["floor"])
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
	Kit.box(_room, Vector3(half.x * 2 + 0.6, 2.8, 0.3), wall_c, Vector3(0, 1.4, -half.y - 0.15), 0.08)
	Kit.box(_room, Vector3(0.3, 2.8, half.y * 2 + 0.6), wall_c.darkened(0.06), Vector3(-half.x - 0.15, 1.4, 0), 0.08)
	Kit.box(_room, Vector3(half.x * 2 + 0.6, 0.16, 0.34), Palette.WOOD, Vector3(0, 0.08, -half.y - 0.12), 0.04)
	Kit.box(_room, Vector3(0.34, 0.16, half.y * 2 + 0.6), Palette.WOOD, Vector3(-half.x - 0.12, 0.08, 0), 0.04)
	for portal in TownModel.portals(space):
		_build_portal(portal, tint)
	var win := Node3D.new()
	win.position = Vector3(-half.x + 0.02, 1.5, -1.8)
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
	if activity:
		activity.decorate_room(_room, space)


## A doorway (to another room or outside) or a staircase opening, with a sign.
func _build_portal(portal: Dictionary, tint: Color) -> void:
	var half := TownModel.ROOM_HALF
	var at: Vector2 = portal["at"]
	var n := Node3D.new()
	if portal["wall"] == "left":
		n.position = Vector3(-half.x + 0.02, 0, at.y)
		n.rotation_degrees.y = 90
	else:
		n.position = Vector3(at.x, 0, -half.y + 0.02)
	_room.add_child(n)
	var kind: String = portal["kind"]
	if kind in ["up", "down"]:
		# Stair opening: a dark arch with wooden steps climbing up or leading down.
		Kit.box(n, Vector3(1.2, 2.0, 0.1), Color("#6b5443"), Vector3(0, 1.0, 0.0), 0.1)
		for i in 5:
			var step_y := 0.12 + i * 0.32 if kind == "up" else 1.4 - i * 0.32
			Kit.box(n, Vector3(1.0, 0.1, 0.24), Palette.WOOD.lightened(0.05 * i), Vector3(0, step_y, 0.08), 0.03)
		Kit.box(n, Vector3(0.08, 1.9, 0.12), Palette.WOOD_DARK, Vector3(-0.58, 0.95, 0.08), 0.03)
		Kit.box(n, Vector3(0.08, 1.9, 0.12), Palette.WOOD_DARK, Vector3(0.58, 0.95, 0.08), 0.03)
	else:
		var door_c := tint.darkened(0.15) if kind == "exit" else Palette.WOOD
		Kit.box(n, Vector3(1.0, 1.7, 0.12), door_c, Vector3(0, 0.85, 0), 0.1)
		Kit.ball(n, 0.06, Palette.paint(1), Vector3(0.32, 0.85, 0.08))
	# A soft mat in front shows where to stand.
	Kit.box(n, Vector3(1.2, 0.04, 0.7), Palette.paint(5).darkened(0.1) if kind == "exit" else Palette.paint(0).darkened(0.08), Vector3(0, 0.02, 0.5), 0.02)
	var sign := Label3D.new()
	sign.text = tr(portal["label"])
	sign.font = I18n.ui_font()
	sign.font_size = 44
	sign.pixel_size = 0.004
	sign.outline_size = 12
	sign.modulate = Color("#557c5e")
	sign.outline_modulate = Color("#fffdf6")
	sign.position = Vector3(0, 2.25, 0.12)
	n.add_child(sign)


# ------------------------------------------------------------- view switching

func set_view(space: String) -> void:
	if not Places.is_map(space) and not Session.model.is_space(space):
		space = "town"
	view_space = space
	_town.visible = space == "town"
	_room.visible = Places.is_room(space)
	if space == Places.CITY:
		if city_world == null:
			city_world = CityWorld.new()
			city_world.name = "City"
			add_child(city_world)
			city_world.setup(self)
			city_world.build()
			# city r2: the city's people (A2), drawn as a few batched meshes on the city's view clock.
			var people_script := load(CITY_PEOPLE_SCRIPT) as GDScript if ResourceLoader.exists(CITY_PEOPLE_SCRIPT) else null
			if people_script and people_script.can_instantiate():
				var people: Node3D = people_script.new()
				people.name = "People"
				city_world.add_child(people)
				people.call("setup", city_world)
				city_people = people
		var city := get_node_or_null("/root/City")
		if city and city.has_signal("updated") and not city.updated.is_connected(city_world.set_states):
			city.updated.connect(city_world.set_states)
	if city_world:
		city_world.visible = space == Places.CITY
	if space == Places.CITY_WEB and city_logic == null:
		# city-web: the Godot city is neither built nor shown; this logic-only CityWorld answers the poses.
		city_logic = CityWorld.new()
		city_logic.name = "CityWebLogic"
		city_logic.visible = false
		var web := get_node_or_null("/root/CityWeb")
		if web and web.has_method("est_time"):
			city_logic.clock = Callable(web, "est_time")
		add_child(city_logic)
		city_logic.setup(self)
		if web and web.has_signal("updated"):
			web.updated.connect(city_logic.set_states)
	_apply_white_world(Places.is_city(space))
	if space == Places.THOUSAND:
		prepare_thousand()
		_thousand_light()
		_thousand_frame()
	if thousand_world:
		thousand_world.visible = space == Places.THOUSAND
	if space == Places.ZOO:
		if zoo_world == null:
			zoo_world = ZooWorld.new()
			zoo_world.name = "Zoo"
			add_child(zoo_world)
			zoo_world.setup(self)
			zoo_world.reduce_motion = reduce_motion
		zoo_world.build()
		zoo_world.set_weather(weather_now)
		_apply_evening()   # its lamps join the town's evening
	if zoo_world:
		zoo_world.visible = space == Places.ZOO
	if Places.is_room(space):
		_build_room(space)
	_rebuild_items()
	_sync_players()
	_update_animal_visibility()
	view_changed.emit(space)


func _rebuild_items() -> void:
	# Any map (town, zoo, city) stays in view; only a room that no longer exists falls back to the town.
	# (city r1: the city is a map but not a decorating space, so TownModel.is_space rightly says no.)
	if not Places.is_map(view_space) and not Session.model.is_space(view_space):
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


## Steam and a soft glow over a stove while something is cooking on it.
func _steam(stove_id: String, on: bool) -> void:
	var node: Node3D = item_nodes.get(stove_id)
	if node == null:
		return
	var old := node.get_node_or_null("Steam")
	if old:
		old.queue_free()
	if not on:
		return
	var p := CPUParticles3D.new()
	p.name = "Steam"
	var top := node.find_child("Cook0", true, false) as Node3D
	p.position = top.position if top else Vector3(0, 1.0, 0)
	p.amount = 18
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 15
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.15, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	var mat := Kit.mat(Color(1, 1, 1, 0.55))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	node.add_child(p)


func _make_item(item: Dictionary, pop := true) -> Node3D:
	var node: Node3D
	if item.has("gift"):
		node = Props.build_present(item["kind"], item["gift"].get("paper", 0))
		node.add_child(_gift_tag(item["gift"]))
	else:
		node = Props.build(item["kind"], item["color"], int(item["id"].substr(1)), int(item.get("growth", 3)), int(item.get("variant", 0)), item)
	node.set_meta("item", item.duplicate())
	node.position = Vector3(item["x"], item_y(item), item["z"])
	node.rotation.y = TownModel.rot_to_radians(item["rot"])
	_items_root.add_child(node)
	item_nodes[item["id"]] = node
	if Session.cooking.has(item["id"]):
		_steam(item["id"], true)
	if DecoMotion.has_motion(item["kind"]) and not item.has("gift"):
		var st := DecoMotion.attach(node, item["kind"], item["id"])
		if not st.is_empty():
			deco[item["id"]] = st
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
		if prev["color"] != item["color"] or prev["kind"] != item["kind"] or prev.get("gift") != item.get("gift") or prev.get("growth") != item.get("growth") \
				or prev.get("variant") != item.get("variant") or prev.get("num") != item.get("num") or prev.get("pix") != item.get("pix"):
			old.queue_free()
			item_nodes.erase(item["id"])
			_make_item(item)
		else:
			var relit: bool = prev.get("on") != item.get("on")
			old.set_meta("item", item.duplicate())
			if relit:
				_apply_evening()   # a lamp was switched on or off
			var tw := create_tween().set_parallel()
			tw.tween_property(old, "position", Vector3(item["x"], item_y(item), item["z"]), 0.2)
			tw.tween_property(old, "rotation:y", _closest_angle(old.rotation.y, TownModel.rot_to_radians(item["rot"])), 0.2)
	_refresh_spots()


## "For Sky" / "For anyone" with who it is from, floating over a present.
func _gift_tag(g: Dictionary) -> Label3D:
	var l := Label3D.new()
	var to: String = g.get("to", "")
	var for_whom: String = tr("For anyone") if to == "" else tr("For %s") % tr(Session.model.roster.get(to, {}).get("nick", "?"))
	l.text = for_whom + "\n" + tr("From %s") % tr(g.get("from_nick", ""))
	l.font = I18n.ui_font()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0032
	l.font_size = 36
	l.outline_size = 10
	l.modulate = Color("#b4544a")
	l.outline_modulate = Color("#fffdf6")
	l.position.y = 1.5
	return l


## What a photo shows, from the game's own state (activity G). Deterministic:
## no image analysis. Only things inside the camera's view in this space count.
func photo_facts(camera: Camera3D) -> Dictionary:
	var vp := camera.get_viewport().get_visible_rect()
	var on_screen := func(p: Vector3) -> bool:
		return not camera.is_position_behind(p) and vp.has_point(camera.unproject_position(p))
	var facts := {"space": view_space, "evening": Session.model.evening, "weather": Session.model.weather,
		"kids": 0, "animals": [], "kinds": [], "shared_seat": false, "swinging": false, "tabletop": false,
		"lanterns": 0, "room_items": Session.model.items_in(view_space).size()}
	for peer in kids:
		if kids[peer].visible and on_screen.call(kids[peer].global_position + Vector3(0, 0.8, 0)):
			facts["kids"] += 1
	if view_space == "town":
		for k in animals:
			if animals[k].visible and on_screen.call(animals[k].global_position + Vector3(0, 0.4, 0)):
				facts["animals"].append(k)
		if on_screen.call(Vector3(TownModel.WISHING_TREE.x, 3.0, TownModel.WISHING_TREE.y)):
			facts["lanterns"] = Session.model.lanterns.size()
	if view_space == "zoo" and zoo_world != null:
		var species: Array = []
		for zid in zoo_world.animals:
			var za: Node3D = zoo_world.animals[zid]
			if za.visible and on_screen.call(za.global_position + Vector3(0, 0.6, 0)):
				species.append(str(za.species))
		facts["zoo_animals"] = species
	for id in item_nodes:
		var item: Dictionary = item_nodes[id].get_meta("item")
		if item.has("gift") or not on_screen.call(item_nodes[id].global_position + Vector3(0, 0.3, 0)):
			continue
		facts["kinds"].append(item["kind"])
		if item.has("host"):
			facts["tabletop"] = true
		var holders: Dictionary = Session.seats.get(id, {})
		if holders.size() >= 2:
			facts["shared_seat"] = true
		if item["kind"] == "swing" and not holders.is_empty():
			facts["swinging"] = true
	return facts


## Height an item stands at: the support surface of its host, or the floor.
func item_y(item: Dictionary) -> float:
	if item.has("y"):
		return float(item["y"])   # wall and ceiling items hang at their mount height
	var host: Dictionary = Session.model.items.get(item.get("host", ""), {})
	if host.is_empty():
		return 0.0
	return Catalog.support_surface(host["kind"]).get("local_position", Vector3.ZERO).y


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
	if view_space != "town" and ids.has(TownModel.house_of(view_space)):
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
	var y := CityNav.height(str(s.get("level", "")), Vector2(s["x"], s["z"])) if Places.is_city(str(s.get("space", ""))) else 0.0
	if str(s.get("space", "")) == Places.THOUSAND:
		y = thousand_height(Vector2(s["x"], s["z"]))
	kid.set_target(Vector3(s["x"], y, s["z"]), s["ry"], was_hidden)


func _on_animals(states: Array) -> void:
	var seen := {}
	for st in states:
		var node: Node3D = animals.get(st["kind"])
		var fresh := node == null
		if fresh:
			node = AnimalScript.new()
			node.setup(st["kind"])
			add_child(node)
			animals[st["kind"]] = node
		node.set_state(st, fresh)
		if fresh:
			node.set_line(Animals.focus_line(st["kind"]))
		seen[st["kind"]] = true
	for k in animals.keys():
		if not seen.has(k):
			animals[k].queue_free()
			animals.erase(k)
	_update_animal_visibility()


func _update_animal_visibility() -> void:
	var me: Node3D = local_kid()
	for k in animals:
		var a: Node3D = animals[k]
		a.visible = view_space == "town" and not visiting_indoors(k)
		a.show_name(a.visible and (a.line != "" or (me != null and me.position.distance_to(a.position) < 4.0)))


## A living town: an animal busy with something a child made says so over its head.
func _refresh_animal_lines() -> void:
	for k in animals:
		animals[k].set_line(Animals.focus_line(k))


## True while an animal friend is inside a house with the child it visits (r18): it is drawn in that
## room (guest_world.gd) and not outdoors.
func visiting_indoors(kind: String) -> bool:
	var peer: int = Animals.guests.get(kind, 0)
	return peer != 0 and space_of(peer) != "town"


## Where a child is: this device's own child is wherever the view is (a client's own entry in
## Session.players is not updated by its own moves); friends are where their last state says.
func space_of(peer: int) -> String:
	if peer == Session.my_id:
		return view_space
	return str(Session.players.get(peer, {}).get("state", {}).get("space", "town"))


## In the zoo, a child slides around rock, water, plantings and trees (ZooMap's blockers).
func _zoo_push_out(p: Vector2, body: float) -> Vector2:
	for k in ZooMap.AREAS:
		var a: Dictionary = ZooMap.AREAS[k]
		if not a["kind"] in ["terrace", "backdrop", "planting", "water", "thicket"]:
			continue
		var r: Rect2 = (a["rect"] as Rect2).grow(body)
		if r.has_point(p):
			var dl := p.x - r.position.x
			var dr := r.end.x - p.x
			var dt := p.y - r.position.y
			var db := r.end.y - p.y
			var m := minf(minf(dl, dr), minf(dt, db))
			if m == dl:
				p.x = r.position.x - 0.01
			elif m == dr:
				p.x = r.end.x + 0.01
			elif m == dt:
				p.y = r.position.y - 0.01
			else:
				p.y = r.end.y + 0.01
	for s in ZooMap.SOLIDS:
		var c: Vector2 = s["at"]
		var rr: float = s["r"] + body
		if p.distance_to(c) < rr:
			p = c + ((p - c).normalized() if p.distance_to(c) > 0.001 else Vector2.RIGHT) * rr
	if p.distance_to(ZooMap.STATION) < 1.3 + body:
		p = ZooMap.STATION + (p - ZooMap.STATION).normalized() * (1.3 + body)
	return p


## The animal under a screen point, if any (in the zoo: a resident's id).
func pick_animal(camera: Camera3D, screen: Vector2) -> String:
	if view_space == Places.ZOO and zoo_world:
		return zoo_world.pick(camera, screen)
	if view_space != "town":
		return ""
	var best := ""
	var best_d := 60.0
	for k in animals:
		var a: Node3D = animals[k]
		if not a.visible:
			continue
		var c := a.global_position + Vector3(0, 0.9 if k == "elephant" else 0.4, 0)
		if camera.is_position_behind(c):
			continue
		var d := camera.unproject_position(c).distance_to(screen)
		if d < best_d:
			best_d = d
			best = k
	return best


func _on_emote(peer: int, kind: String) -> void:
	var kid: Node3D = kids.get(peer)
	if kid:
		kid.play_emote(kind)


func _refresh_labels() -> void:
	if Places.is_room(view_space):
		_build_room(view_space)   # door and stair signs
	for k in kids.values():
		k.refresh_label()
	for a in animals.values():
		a.refresh_label()
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
	if Places.is_city(view_space) and _env:
		_city_light(_city_weights())   # city r3: the light follows the shared weather, smoothly
	elif view_space == Places.THOUSAND and _env:
		_thousand_light()   # thousand-town: the light follows the shared town clock
		_thousand_frame()   # and the residents and the buses the same time
	_scale_own_label()
	if absf(evening - _evening_target) > 0.001:
		evening = move_toward(evening, _evening_target, delta * 0.5)
		_apply_evening()
	for marker in _spots_root.get_children():
		marker.rotation.y += delta * 0.6
		var s := 1.0 + sin(_t * 3.0) * 0.06
		marker.scale = Vector3(s, 1, s)
	for lantern in _lanterns.values():
		lantern.rotation.z = sin(_t * 1.3 + lantern.get_index()) * 0.08
	_twinkle_lanterns()
	ride_fx.advance(delta)   # carts first: a seated child is put on the cart where it is this frame
	_animate_play_items()
	_update_animal_visibility()
	_animate_deco()


## dest-fix r1: in a city the player's own name stays readable at every zoom. Within OWN_LABEL_NEAR of the
## camera it has its usual size; farther it grows with the distance (at most OWN_LABEL_MAX), so on the city's
## overview (about 96 m) it marks where the child is. Everywhere else, and for everyone else, it is unchanged.
const OWN_LABEL_NEAR := 20.0   # beyond the strolling view (about 15 m from the focus, 15.3 m from the child)
const OWN_LABEL_MAX := 6.0


func _scale_own_label() -> void:
	var kid = kids.get(Session.my_id)
	if kid == null or not is_instance_valid(kid) or not kid.has_method("set_label_scale"):
		return
	var s := 1.0
	if Places.is_city(view_space):
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			s = clampf(cam.global_position.distance_to(kid.global_position) / OWN_LABEL_NEAR, 1.0, OWN_LABEL_MAX)
	kid.set_label_scale(s)


## Decorations of the space on screen move (deco_motion.gd); a node that was rebuilt or removed drops
## out. Runs after the evening lamps are set, so a glow scales this frame's brightness.
func _animate_deco() -> void:
	for id in deco.keys():
		var st: Dictionary = deco[id]
		var node = st["node"]
		if not is_instance_valid(node) or item_nodes.get(id) != node:
			deco.erase(id)
			continue
		if not reduce_motion and node.is_visible_in_tree():
			DecoMotion.tick(st, _t, lamp_level(id))


func _exit_tree() -> void:
	deco.clear()
	DecoMotion.clear_cache()


## Reduce motion on: every decoration is still at once (and after restarts); off: they move again.
func set_reduce_motion(on: bool) -> void:
	if zoo_world:
		zoo_world.reduce_motion = on
	reduce_motion = on
	DecoMotion.save_reduce(on)
	if on:
		for id in deco:
			var st: Dictionary = deco[id]
			if is_instance_valid(st["node"]):
				DecoMotion.rest(st, lamp_level(id))


## Where a seated child's root goes for a seat marker: hips on the marker, facing its +z.
static func seat_transform(marker: Node3D) -> Transform3D:
	return marker.global_transform * Transform3D(Basis(), Vector3(0, -KidScript.HIP_HEIGHT + 0.02, -0.06))


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
			# Seats come from markers in the model: SeatN, or Sleep0 on modeled beds.
			var marker := Props.seat_marker(node, s)
			var kid: Node3D = kids.get(peer)
			if marker and kid:
				kid.global_transform = seat_transform(marker)
				var action: String = Catalog.get_def(node.get_meta("item")["kind"]).get("action", "Sit")
				kid.anim = {"Swing": "swing", "Ride": "ride", "Rest": "rest"}.get(action, "sit")
				seated[peer] = true
	for id in item_nodes:
		if Session.seats.has(id):
			continue
		var pivot := item_nodes[id].get_node_or_null("Pivot") as Node3D
		if pivot:
			pivot.rotation.x = lerpf(pivot.rotation.x, 0.0, 0.05)
	for peer in kids:
		var kid: Node3D = kids[peer]
		# In the city the seats, machines and gondolas are the City's (place_city_friends and the controller's
		# _city_frame pose those children every frame); only town seats are released here.
		if Places.is_city(view_space) or view_space == Places.THOUSAND:
			break   # thousand-town: no town seats there; the bus and the wheel pose the children (thousand_play.gd)
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
	for c in pick_candidates(camera, screen):
		if c["score"] < best_d:
			best_d = c["score"]
			best = c["id"]
	return best


## Every item under a screen point: [{id, score}], score = distance from the
## projected center over the projected radius (lower is closer).
func pick_candidates(camera: Camera3D, screen: Vector2) -> Array:
	var out := []
	for id in item_nodes:
		var node: Node3D = item_nodes[id]
		if not node.visible:
			continue
		var item: Dictionary = node.get_meta("item")
		var r: float = Catalog.get_def(item["kind"])["radius"]
		var best := INF
		for h in [0.15, 0.6, 1.2]:
			var c := node.global_position + Vector3(0, h * clampf(r, 0.4, 2.0), 0)
			if camera.is_position_behind(c):
				continue
			var sp := camera.unproject_position(c)
			var edge := camera.unproject_position(c + camera.global_basis.x * r)
			var pr := maxf(sp.distance_to(edge), 22.0)
			var d := sp.distance_to(screen)
			if d < pr:
				best = minf(best, d / pr)
		if best < INF:
			out.append({"id": id, "score": best})
	return out


## Pushes a walking child out of solid items, walls and the Wishing Tree (in Thousand Town: its world's
## walkable ground, thousand_world.resolve_walk).
func resolve_walk(p: Vector2, body := 0.28) -> Vector2:
	if view_space == Places.THOUSAND and thousand_world:
		return thousand_world.resolve_walk(p)
	var half := Places.half(view_space)
	if view_space == Places.ZOO:
		p = _zoo_push_out(p, body)
	for item in Session.model.items_in(view_space):
		var def := Catalog.get_def(item["kind"])
		if def["layer"] != "solid" or item.has("host"):
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


# ------------------------------------------------------------- Thousand Town (design/thousand-town.md)

## The light of Thousand Town at its clock's time (its world sets the sun, ambient and background).
func _thousand_light() -> void:
	if thousand_world == null:
		return
	var t: Dictionary = thousand_world.view_time()
	thousand_world.set_time(int(t.get("day", 1)), float(t.get("minute", 480.0)))


## Builds Thousand Town's world, residents and transit once (hidden until it is shown) and places everybody for
## the current time with every route searched now: called behind the journey card, so the arrival has no hitch.
## Idempotent; the town's own light is not touched (the Thousand world's light is set only while it is shown).
func prepare_thousand() -> void:
	if thousand_world == null:
		thousand_world = ThousandWorld.new()
		thousand_world.name = "Thousand"
		thousand_world.visible = view_space == Places.THOUSAND
		add_child(thousand_world)
		thousand_world.setup(self)
		thousand_world.build()
	if thousand_events == null:
		thousand_events = ThousandEvents.new()
		thousand_events.name = "Events"
		thousand_world.add_child(thousand_events)
		thousand_events.setup(thousand_world)
		thousand_events.spark_cap = ThousandEvents.MAX_SPARKS_TV if TvMode.active() else ThousandEvents.MAX_SPARKS
		thousand_events.drive = true
	var t: Dictionary = thousand_world.view_time()
	var day := int(t.get("day", 1))
	var plans: RefCounted = thousand_world.ensure_plans(day)
	if thousand_transit == null:
		thousand_transit = ThousandTransit.new()
		thousand_transit.name = "Transit"
		thousand_world.add_child(thousand_transit)
		thousand_transit.setup()
		for kind in ["bus", "taxi"]:
			var tpl: Node3D = thousand_world.vehicle_template(kind)
			if tpl:
				tpl.visible = false   # the transit draws them; the world must not show its templates
	if thousand_people == null:
		thousand_people = ThousandPeople.new()
		thousand_people.name = "People"
		thousand_world.add_child(thousand_people)
		thousand_people.setup(thousand_world.sim, null, thousand_world)
		_thousand_tv = 1 if TvMode.active() else 0
		thousand_people.budget_profile("tv" if _thousand_tv == 1 else "ipad")
		if plans != null:
			thousand_people.set_plans(plans)
			_thousand_plans = plans
			var kid := local_kid()
			var a: Vector2 = Places.THOUSAND_ARRIVALS[0]
			thousand_people.focus(kid.global_position if kid and view_space == Places.THOUSAND else Vector3(a.x, 0.125, a.y))
			thousand_people.warm(day, float(t.get("minute", 480.0)))
	thousand_transit.set_time(day, float(t.get("minute", 480.0)))


## Once a frame in Thousand Town: the residents and the transit at the view time the light uses. The residents use
## the world's plans (set_plans when the day's plans change); while a new day's plans are still being built a few
## residents a frame, the residents hold their last frame rather than build their own.
func _thousand_frame() -> void:
	if thousand_world == null or thousand_people == null or thousand_transit == null:
		return
	var f := Engine.get_process_frames()
	if f == _thousand_frame_no:
		return
	_thousand_frame_no = f
	var t: Dictionary = thousand_world.view_time()
	var day := int(t.get("day", 1))
	var minute := float(t.get("minute", 480.0))
	thousand_transit.set_time(day, minute)
	var plans: RefCounted = thousand_world.plans()
	if plans != null and plans != _thousand_plans:
		_thousand_plans = plans
		thousand_people.set_plans(plans)
	var tv := 1 if TvMode.active() else 0
	if tv != _thousand_tv:
		_thousand_tv = tv
		thousand_people.budget_profile("tv" if tv == 1 else "ipad")   # design section 8: 96 figures on the TV
		if thousand_events:
			thousand_events.spark_cap = ThousandEvents.MAX_SPARKS_TV if tv == 1 else ThousandEvents.MAX_SPARKS
	var kid := local_kid()
	if kid:
		thousand_people.focus(kid.global_position)
	if plans != null and int(plans.get("day")) == day:
		thousand_people.set_time(day, minute)


## The ground height in Thousand Town (0 before its world is built).
func thousand_height(p: Vector2) -> float:
	return thousand_world.height_at(p) if thousand_world else 0.0


## A walking step in Thousand Town from `from` to `to`: blocked steps slide along the edge or stay.
func resolve_thousand(from: Vector2, to: Vector2) -> Vector2:
	if thousand_world == null:
		return resolve_walk(to)
	return thousand_world.resolve_walk(to, from)


# ------------------------------------------------------------- the city (city r1)

## The city is a miniature on a clean white world (design/city-district.md): white sky, no fog. Leaving it
## puts the town's sky, weather and evening back.
func _apply_white_world(on: bool) -> void:
	if _env == null:
		return
	if on:
		_city_light(_city_weights())
	else:
		_env.fog_enabled = true
		_env.adjustment_enabled = false
		if _sun:
			_sun.light_color = Color("#fff4e0")
			_sun.light_energy = 0.8
		_apply_evening()


## The city's light (r2, r3): brighter and cleaner, never grey; blended between the shared weather's looks
## (CityMap.WEATHER_LOOK: sunny, rain, night) by the weights city_world computes from the shared clock, so a
## change glides over WEATHER_BLEND seconds and only parameters move: nothing is created or destroyed.
## (Real-time shadows stay off in the whole game: soft blob shadows ground things, which also means no
## shadow can flicker while the view moves. The shadow settings of r1 and r2 had no effect and are gone.)
func _city_light(weights: Dictionary = {"sunny": 1.0}) -> void:
	var mix := {}
	for key in ["sky", "ambient", "sun"]:
		mix[key] = Color(0, 0, 0, 0)
	for key in ["ambient_energy", "sun_energy", "saturation"]:
		mix[key] = 0.0
	var total := 0.0
	for w in weights:
		total += float(weights[w])
	for w in weights:
		var look: Dictionary = CityMap.WEATHER_LOOK.get(w, CityMap.WEATHER_LOOK["sunny"])
		var k := float(weights[w]) / maxf(total, 0.0001)
		for key in ["sky", "ambient", "sun"]:
			mix[key] = (mix[key] as Color) + (look[key] as Color) * k
		for key in ["ambient_energy", "sun_energy", "saturation"]:
			mix[key] = float(mix[key]) + float(look[key]) * k
	_env.background_color = mix["sky"]
	_env.fog_enabled = false
	_env.ambient_light_color = mix["ambient"]
	_env.ambient_light_energy = mix["ambient_energy"]
	_env.adjustment_enabled = true
	_env.adjustment_saturation = mix["saturation"]
	_env.adjustment_contrast = 1.04
	_env.adjustment_brightness = 1.02
	if _sun:
		_sun.light_color = mix["sun"]
		_sun.light_energy = mix["sun_energy"]


## The weather weights the city is drawn with now (sunny until city_world can say). In the web city, the
## CityWeb state's weights (Godot's own window shows only the children there).
func _city_weights() -> Dictionary:
	if view_space == Places.CITY_WEB:
		var web := get_node_or_null("/root/CityWeb")
		var ww: Dictionary = web.weights() if web and web.has_method("weights") else {}
		return ww if not ww.is_empty() else {"sunny": 1.0}
	if city_world and city_world.has_method("weather_weights"):
		var w: Dictionary = city_world.weather_weights()
		if not w.is_empty():
			return w
	return {"sunny": 1.0}


## A floor-aware tap in the city: the nearest walkable surface along the ray; floors, roofs and walls above
## stop it, except the storeys the cutaway hides around the child. {} when nothing walkable was hit.
func pick_city(camera: Camera3D, screen: Vector2, level: String, at: Vector2) -> Dictionary:
	if city_world == null:
		return {}
	return CityNav.pick(camera.project_ray_origin(screen), camera.project_ray_normal(screen), CityNav.storeys_hidden(level, at))


## city-web: the same floor-aware pick from a ray (the page's camera ray: origin and direction, world space).
static func pick_city_ray(origin: Vector3, dir: Vector3, level: String, at: Vector2) -> Dictionary:
	if dir.length() < 0.0001:
		return {}
	return CityNav.pick(origin, dir.normalized(), CityNav.storeys_hidden(level, at))


## The CityWorld whose poses and clock serve the city map in view: the built Godot city, the web city's
## logic-only one, or null outside a city map.
func active_city() -> Node3D:
	if view_space == Places.CITY:
		return city_world
	if view_space == Places.CITY_WEB:
		return city_logic
	return null


## Friends riding the wheel or holding a seat or machine are drawn where the shared state says (their own
## walking target would pull them off a gondola or a chair).
func place_city_friends(states: Dictionary) -> void:
	var cw := active_city()
	if cw == null:
		return
	# r2: the wheel is drawn at the city's view time; seat riders at the same angle so they stay in their gondola.
	var angle := float(cw.ferris_angle_now()) if cw.has_method("ferris_angle_now") else float(states.get("ferris_angle", 0.0))
	var riders: Dictionary = states.get("riders", {})
	var placed := {}
	for g in riders:
		var list: Array = riders[g]
		for slot in list.size():
			var peer := int(list[slot])
			if peer == Session.my_id or not kids.has(peer):
				continue
			var kid: Node3D = kids[peer]
			kid.global_transform = cw.rider_transform(int(g), angle, slot)
			kid.anim = "ride"
			placed[peer] = true
	var occ: Dictionary = states.get("occupancy", {})
	for key in occ:
		var peer := int(occ[key])
		if peer == Session.my_id or not kids.has(peer) or placed.has(peer) or not CityMap.INTERACTIONS.has(key):
			continue
		var how: Array = CityMap.HOLD_POSES.get(_city_pose(str(key)), ["sit", 0.44])
		var xf: Transform3D = cw.seat_transform(str(key))
		xf.origin.y += float(how[1])
		var kid: Node3D = kids[peer]
		kid.global_transform = xf
		kid.anim = str(how[0])


static func _city_pose(key: String) -> String:
	var kind: String = CityMap.INTERACTIONS[key]["kind"]
	if kind == "exercise":
		return "run" if key.contains("treadmill") else ("lift" if key.contains("weights") else "cycle")
	return "sit"


## Hides the storeys above the child inside a building, so it stays readable (the art and the taps agree).
func update_city_cutaway(level: String, at: Vector2) -> void:
	if view_space == Places.CITY_WEB:
		# city-web: nothing of the Godot city is drawn; the page receives the same cutaway (web_cutaway).
		var cut := city_cutaway(level, at)
		if cut != _web_cutaway:
			_web_cutaway = cut
			web_cutaway_rev += 1
		return
	if city_world:
		var hidden: Dictionary = CityNav.storeys_hidden(level, at)
		city_world.apply_hidden(hidden)
		if city_people and city_people.has_method("set_hidden_regions"):
			city_people.call("set_hidden_regions", hidden_regions(hidden))


## The people on a cut-away storey go with it: every region of that building above the floor shown.
static func hidden_regions(hidden: Dictionary) -> Array:
	var regions: Array = []
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		var b := str(reg.get("building", ""))
		if b != "" and hidden.has(b) and float(reg["y"]) > float(hidden[b]) + 0.01:
			regions.append(rid)
	return regions


## What the cutaway around a child at `level` / `at` hides: "hidden" (CityWorld.apply_hidden's argument) and
## "regions" (the people's set_hidden_regions argument).
static func city_cutaway(level: String, at: Vector2) -> Dictionary:
	var hidden: Dictionary = CityNav.storeys_hidden(level, at)
	return {"hidden": hidden, "regions": hidden_regions(hidden)}


## city-web: the newest cutaway of the web city, for the page: {"hidden", "regions", "rev"} (rev changes
## whenever hidden or regions change).
func web_cutaway() -> Dictionary:
	return {"hidden": (_web_cutaway["hidden"] as Dictionary).duplicate(), "regions": (_web_cutaway["regions"] as Array).duplicate(), "rev": web_cutaway_rev}
