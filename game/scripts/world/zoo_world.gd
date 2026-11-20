## The zoo map in the world (design/zoo-and-world-journeys.md sections 8 and 12;
## docs/zoo-engineering-standard.md section 2): ground, habitats, structures and stations built
## once from ZooMap, and the fourteen animals drawn from the authority's states (Zoo.states).
## Built the first time a child goes to the zoo and kept afterwards; hidden in town.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const PropsZoo := preload("res://scripts/art/props_zoo.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")
const ZooAnimal := preload("res://scripts/art/zoo_animal.gd")
const Props := preload("res://scripts/art/props.gd")

## Animals farther than this from this device's child are hidden and not posed (section 15).
const DRAW_RANGE := 30.0

var world: Node3D                 # the town world (its local child, its reduce-motion setting)
var animals := {}                 # resident id -> ZooAnimal node
var reduce_motion := false
var _states := {}                 # the latest Zoo states
var _tyre: Node3D
var _vine_rope: MeshInstance3D
var _waterhole: Node3D
var _water_until := 0.0
var _built := false
var _ground: Node3D


func setup(w: Node3D) -> void:
	world = w
	var zoo := get_node_or_null("/root/Zoo")
	if zoo:
		zoo.updated.connect(func(st): _states = st)
		zoo.effect.connect(_on_effect)
	I18n.locale_changed.connect(func(_c): _refresh_signs())


## Builds the map once (it is static: positions come from ZooMap).
func build() -> void:
	if _built:
		return
	_built = true
	_ground = Node3D.new()
	_ground.name = "ZooGround"
	add_child(_ground)
	_build_ground()
	_build_areas()
	_build_structures()
	_build_stations()
	_build_station_and_plaza()
	_build_edge()
	Kit.merge_parts(_ground)
	for id in ZooMap.ORDER:
		var r: Dictionary = ZooMap.RESIDENTS[id]
		var a: Node3D = ZooAnimal.new()
		a.name = "Zoo_" + id
		add_child(a)
		a.setup(r["species"], id, int(r.get("variant", 0)), bool(r.get("young", false)))
		a.visible = false
		animals[id] = a


func _build_ground() -> void:
	var base := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ZooMap.HALF.x * 2.0 + 40.0, ZooMap.HALF.y * 2.0 + 40.0)
	base.mesh = pm
	base.material_override = Kit.mat(Color("#a9d27f"))
	base.position.y = -0.02
	add_child(base)
	# habitat grounds: sandy rock hills, golden savanna, green and sandy splash bay
	var tint := {"lion_hill": Color("#e2cf9c"), "tiger_hill": Color("#b9d68a"), "monkey_hill": Color("#a6cf7a"),
		"savanna": Color("#e6d690"), "splash_bay": Color("#d9e3a0"), "bamboo_grove": Color("#bcd98f")}   # zoo r2: the grove's bamboo green
	for h in ZooMap.HABITATS:
		var r: Rect2 = ZooMap.HABITATS[h]
		Kit.part(_ground, Kit.rounded_box(Vector3(r.size.x, 0.02, r.size.y), 0.01, 1), tint.get(h, Color("#c8dc96")), Vector3(r.get_center().x, -0.005, r.get_center().y))
	for k in ZooMap.LAWNS:
		var r: Rect2 = ZooMap.LAWNS[k]
		Kit.part(_ground, Kit.rounded_box(Vector3(r.size.x, 0.02, r.size.y), 0.01, 1), Color("#b3d98a"), Vector3(r.get_center().x, -0.004, r.get_center().y))


func _build_areas() -> void:
	var seed := 1
	for k in ZooMap.AREAS:
		var a: Dictionary = ZooMap.AREAS[k]
		var r: Rect2 = a["rect"]
		var c := r.get_center()
		seed += 1
		match a["kind"]:
			"path", "bay":
				Kit.part(_ground, Kit.rounded_box(Vector3(r.size.x, 0.03, r.size.y), 0.01, 1), Color("#efe0b8") if a["kind"] == "path" else Color("#f3e7c6"), Vector3(c.x, 0.0, c.y))
			"terrace":
				if k == "tiger_log":
					var log := PropsZoo.log_bridge(r.size.y)
					log.rotation.y = PI * 0.5
					log.position = Vector3(c.x, 0.0, c.y)
					add_child(log)
				elif k in ["monkey_west_tower", "monkey_east_tower"]:
					var t := PropsZoo.tower(a["height"])
					t.position = Vector3(c.x, 0.0, c.y)
					add_child(t)
				elif k == "monkey_spire":
					var sp := PropsZoo.spire([0.8, 1.4, 2.0, 3.2])
					sp.position = Vector3(c.x, 0.0, c.y + 0.3)
					add_child(sp)
				elif k == "monkey_hammock":
					var hm := PropsZoo.hammock()
					hm.position = Vector3(c.x, 0.0, c.y)
					add_child(hm)
				elif k == "monkey_west_perch":
					var t := PropsZoo.tower(a["height"])
					t.position = Vector3(c.x, 0.0, c.y)
					add_child(t)
				elif a["height"] > 0.05:
					var rk := PropsZoo.rock(Vector3(r.size.x, a["height"], r.size.y), seed)
					rk.position = Vector3(c.x, 0.0, c.y)
					add_child(rk)
				else:
					# the lions' den: a dark mouth in the crag
					Kit.part(_ground, Kit.rounded_box(Vector3(r.size.x * 0.7, 1.2, 0.4), 0.3, 1), Color("#5f6672"), Vector3(c.x, 0.6, r.position.y + 0.1))
			"backdrop":
				var cr := PropsZoo.crag(Vector3(r.size.x, a["height"], r.size.y), seed)
				cr.position = Vector3(c.x, 0.0, c.y)
				add_child(cr)
				if k == "tiger_falls":
					var f := PropsZoo.falls(4.0, a["height"])
					f.position = Vector3(c.x + 2.5, 0.0, r.end.y + 0.2)
					add_child(f)
			"water":
				var w := PropsZoo.water(r.size, 0.6)
				w.position = Vector3(c.x, 0.0, c.y)
				add_child(w)
				if k == "savanna_waterhole":
					_waterhole = w
			"thicket":
				var b := PropsZoo.bamboo(r.size)
				b.position = Vector3(c.x, 0.0, c.y)
				add_child(b)
			"planting":
				Kit.part(_ground, Kit.rounded_box(Vector3(r.size.x, 0.14, r.size.y), 0.06, 1), Color("#7fbb6a"), Vector3(c.x, 0.07, c.y))
			"grass":
				for i in 7:
					var gx: float = r.position.x + fmod(i * 1.37, r.size.x)
					var gz: float = r.position.y + fmod(i * 2.11, r.size.y)
					Kit.part(_ground, Kit.capsule(0.12, 0.7), Color("#c9c26b"), Vector3(gx, 0.3, gz))


func _build_structures() -> void:
	for s in ZooMap.SOLIDS:
		var n: Node3D
		match s["kind"]:
			"acacia": n = PropsZoo.acacia()
			"scratch_tree": n = PropsZoo.scratch_tree()
			"shade_tree": n = PropsZoo.shade_tree()
			"shower": n = PropsZoo.shower_arch()
			"bench": n = Props.build("bench", 5)   # the plaza's benches (design 8.6), the town's own model
		if n:
			n.position = Vector3(s["at"].x, 0.0, s["at"].y)
			n.rotation.y = float(s.get("ry", 0.0))
			add_child(n)
	# Monkey Hill: the Ring Run (hands at 2.7 m) along z, the vine arch, the tyre, the bridge.
	var ring := PropsZoo.ring_run(7.4, 3.0, 7)
	ring.rotation.y = PI * 0.5
	ring.position = Vector3(23.5, 0.0, -18.6)
	add_child(ring)
	var arch := PropsZoo.vine_arch(ZooMap.VINE_LENGTH + ZooMap.HANG + 0.45)
	arch.position = Vector3(36.2, 0.0, -17.6)
	arch.rotation.y = PI * 0.5
	add_child(arch)
	_vine_rope = Kit.part(self, Kit.capsule(0.035, 1.0), Color("#8a6a3d"), Vector3.ZERO)
	_vine_rope.visible = false
	var frame := PropsZoo.tyre_frame()
	frame.position = Vector3(33.4, 0.0, -20.6)
	add_child(frame)
	_tyre = Node3D.new()
	_tyre.position = Vector3(33.4, 0.0, -20.6) + PropsZoo.TYRE_PIVOT
	add_child(_tyre)
	_tyre.add_child(PropsZoo.tyre())
	# The Net Bridge: a sloped beam from the West Tower (1.6 m) to the West Perch (1.2 m).
	var a := ZooMap.anchor_pos("m_west_tower")
	var b := ZooMap.anchor_pos("m_west_perch")
	var mid := (a + b) * 0.5
	var bridge := Kit.part(_ground, Kit.rounded_box(Vector3(0.36, 0.12, a.distance_to(b)), 0.05, 1), Color("#b88a55"), Vector3(mid.x, mid.y - 0.06, mid.z))
	bridge.rotation.x = atan2(b.y - a.y, -(b.z - a.z))


func _build_stations() -> void:
	for st in ZooMap.STATIONS:
		var p: Vector2 = ZooMap.STATIONS[st]["pos"]
		var n: Node3D
		if st.ends_with("_treats") or st == "monkey_bananas":
			n = PropsZoo.treat_table()
		elif st == "tiger_ball":
			n = PropsZoo.ball_basket()
		elif st == "monkey_bell":
			n = PropsZoo.bell_rope()
		elif st == "monkey_bongos":
			n = PropsZoo.bongo_logs()
		elif st == "savanna_pump":
			n = PropsZoo.water_pump()
		if n:
			n.position = Vector3(p.x, 0.0, p.y)
			add_child(n)


## The Zoo Station (8 x 4 m platform, the tram), the plaza with its map board, benches and lamps,
## and a sign at every habitat's entry.
var _signs: Array = []


func _build_station_and_plaza() -> void:
	var st := PropsZoo.station(Vector2(8.0, 4.0))
	st.position = Vector3(ZooMap.STATION.x, 0.0, ZooMap.STATION.y + 0.4)
	add_child(st)
	var car := PropsZoo.tram_car()
	car.position = Vector3(ZooMap.STATION.x, 0.0, ZooMap.STATION.y + 1.6)
	car.rotation.y = PI * 0.5
	add_child(car)
	Kit.part(_ground, Kit.rounded_box(Vector3(12.0, 0.03, 12.0), 0.4, 1), Color("#f3e7c6"), Vector3(ZooMap.PLAZA.x, 0.0, ZooMap.PLAZA.y))
	Kit.part(_ground, Kit.rounded_box(Vector3(4.0, 0.03, 14.0), 0.01, 1), Color("#efe0b8"), Vector3(0.0, 0.0, 19.0))   # station to the meadow gate
	var board := PropsZoo.map_board()
	board.position = Vector3(ZooMap.PLAZA.x - 2.8, 0.0, ZooMap.PLAZA.y)
	board.rotation.y = PI * 0.25
	add_child(board)
	for x in [-4.5, 4.5]:
		var l := PropsZoo.lamp()
		l.position = Vector3(x, 0.0, ZooMap.PLAZA.y + 1.5)
		add_child(l)
		# Lit at evening like the town's lamps (design 10.7): the town's evening sets every "lamp".
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.55, 0)
		light.omni_range = 6.0
		light.light_color = Color("#ffd8a0")
		light.light_energy = 0.0
		light.add_to_group("lamp")
		l.add_child(light)
	for h in ZooMap.HABITATS:
		var r: Rect2 = ZooMap.HABITATS[h]
		var at := Vector3(r.get_center().x + 2.6, 0.0, r.end.y + 0.6) if r.end.y <= -10.0 else Vector3(r.get_center().x, 0.0, r.end.y + 0.8)
		var s := PropsZoo.sign_post(ZooMap.HABITAT_NAMES[h])
		s.position = at
		s.set_meta("text_key", ZooMap.HABITAT_NAMES[h])
		add_child(s)
		_signs.append(s)


func _refresh_signs() -> void:
	for s in _signs:
		for l in (s as Node).find_children("*", "Label3D", true, false):
			(l as Label3D).text = tr(str(s.get_meta("text_key", "")))


## A ring of hedges and trees just outside the walkable edge, so turned and wide views never show
## the end of the world (camera note: map bounds).
func _build_edge() -> void:
	var hx := ZooMap.HALF.x + 0.6
	var hz := ZooMap.HALF.y + 0.6
	var step := 6.0
	var x := -hx
	while x < hx:
		for z in [-hz, hz]:
			var h := PropsZoo.hedge(step)
			h.position = Vector3(x + step * 0.5, 0.0, z)
			add_child(h)
		x += step
	var z := -hz
	while z < hz:
		for xx in [-hx, hx]:
			var h := PropsZoo.hedge(step)
			h.rotation.y = PI * 0.5
			h.position = Vector3(xx, 0.0, z + step * 0.5)
			add_child(h)
		z += step
	for i in 16:
		var t := PropsZoo.shade_tree()
		var ang := TAU * i / 16.0
		t.position = Vector3(cos(ang) * (hx + 4.0), 0.0, sin(ang) * (hz + 4.0))
		add_child(t)


# ---------------------------------------------------------------- drawing the animals

# ------------------------------------------------------------- the town's weather, shown here too

const WEATHER_BOX := 15.0          # half size of the falling weather around the child (town density)
var _weather_tint: MeshInstance3D
var _weather_fx: CPUParticles3D
var weather := "sunny"


## The town's weather shows in the zoo (design 10.7): the same ground wash and falling rain, snow or
## leaves. They fall in a box that follows the child, at the town's density, not over the whole map.
func set_weather(w: String) -> void:
	weather = w
	if _weather_tint == null:
		_weather_tint = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = ZooMap.HALF * 2.0 + Vector2(1, 1)
		_weather_tint.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_weather_tint.material_override = m
		_weather_tint.position.y = 0.012
		_weather_tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_weather_tint)
	var tint := {"sunny": Color(1, 1, 1, 0), "rain": Color(0.32, 0.42, 0.6, 0.16), "autumn": Color(0.9, 0.55, 0.22, 0.22), "snow": Color(1, 1, 1, 0.45)}
	(_weather_tint.material_override as StandardMaterial3D).albedo_color = tint.get(w, tint["sunny"])
	_weather_tint.visible = w != "sunny"
	if _weather_fx:
		_weather_fx.queue_free()
		_weather_fx = null
	if w == "sunny" or not tint.has(w):
		return
	var p := CPUParticles3D.new()
	var area := (WEATHER_BOX * 2.0) * (WEATHER_BOX * 2.0) / (52.0 * 44.0)   # the town's density
	p.amount = int((160 if w == "rain" else 90) * area)
	p.lifetime = 2.5 if w == "rain" else 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(WEATHER_BOX, 0.5, WEATHER_BOX)
	p.position.y = 9.0
	p.direction = Vector3(0, -1, 0)
	p.spread = 5 if w == "rain" else 25
	p.gravity = Vector3(0, -9.0 if w == "rain" else -0.6, 0)
	p.initial_velocity_min = 4.0 if w == "rain" else 0.3
	p.initial_velocity_max = 6.0 if w == "rain" else 0.8
	var m := BoxMesh.new()
	m.size = {"rain": Vector3(0.02, 0.3, 0.02), "snow": Vector3(0.13, 0.13, 0.13)}.get(w, Vector3(0.14, 0.02, 0.1))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"rain": Color("#7fb0d6"), "snow": Color("#ffffff"), "autumn": Color("#e9934b")}[w]
	m.material = mat
	p.mesh = m
	p.emitting = true
	_weather_fx = p
	add_child(p)


func _process(_delta: float) -> void:
	if _weather_fx and world and world.local_kid():
		var k: Vector3 = world.local_kid().global_position
		_weather_fx.global_position = Vector3(k.x, 9.0, k.z)
	if not visible or _states.is_empty():
		return
	var zoo := get_node_or_null("/root/Zoo")
	var now: float = zoo.est_time() if zoo else float(_states.get("time", 0.0))
	var me: Node3D = world.local_kid() if world else null
	for st in _states.get("animals", []):
		var node: Node3D = animals.get(st["id"])
		if node == null:
			continue
		var dur: float = maxf(float(st["dur"]), 0.001)
		var u := clampf((now - float(st["t0"])) / dur, 0.0, 1.0)
		var p: Vector3 = ZooBrain.path_point(st["action"], st["from"], st["to"], u, st["param"])
		var far := me != null and Vector2(p.x, p.z).distance_to(Vector2(me.position.x, me.position.z)) > DRAW_RANGE
		node.visible = not far
		node.set_process(not far)
		if far:
			continue
		node.position = p
		node.rotation.y = lerp_angle(node.rotation.y, float(st["ry"]), 0.25)
		node.action = st["action"]
		node.u = u
		node.param = st["param"]
		node.reduce_motion = reduce_motion
		_draw_extras(node, st, u, p)
		_label(node, st, me)
	if _waterhole:
		_waterhole.position.y = 0.06 if Time.get_ticks_msec() / 1000.0 < _water_until else 0.0


func _label(node: Node3D, st: Dictionary, me: Node3D) -> void:
	var name: String = tr(ZooMap.RESIDENTS[st["id"]]["name"])
	var line: String = st.get("line", "")
	var near := me != null and me.position.distance_to(node.position) < 6.0
	var text := ""
	if line != "" and ZooLife.LINES.has(line):
		text = tr(ZooLife.LINES[line]) % name
	elif near:
		text = name
	node.set_label(text, line != "", node.usual_height() + (0.0 if node.species != "monkey" else 0.2))


## The vine's rope while a monkey swings, the tyre's swing.
func _draw_extras(node: Node3D, st: Dictionary, u: float, p: Vector3) -> void:
	if st["action"] == "vine" and u < 0.75:
		var pivot: Vector3 = st["from"] + Vector3(0, ZooMap.VINE_LENGTH + ZooMap.HANG, 0)
		var hands := p + (pivot - p).normalized() * ZooMap.HANG
		_vine_rope.visible = true
		var mid := (pivot + hands) * 0.5
		_vine_rope.position = mid
		_vine_rope.scale = Vector3(1, pivot.distance_to(hands), 1)
		_vine_rope.look_at_from_position(mid, hands, Vector3.RIGHT)
		_vine_rope.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		node.rotation.x = 0.0
	elif st["action"] != "vine" and _vine_rope.visible and node.species == "monkey" and st["id"] == _vine_owner:
		_vine_rope.visible = false
	if st["action"] == "vine":
		_vine_owner = st["id"]
	if st["action"] == "tyre" and _tyre:
		_tyre.rotation.x = sin(Time.get_ticks_msec() / 1000.0 * 2.6) * (0.2 + float(st["param"]) * 0.12) * (0.5 if reduce_motion else 1.0)


var _vine_owner := ""


## The animal under a screen point: the nearest animal whose projected box (never under 44 px,
## section 16.2) holds the point.
func pick(camera: Camera3D, screen: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in animals:
		var a: Node3D = animals[id]
		if not a.visible:
			continue
		var h: float = a.usual_height()
		var top := a.global_position + Vector3(0, h, 0)
		var foot := a.global_position
		if camera.is_position_behind(top) or camera.is_position_behind(foot):
			continue
		var t := camera.unproject_position(top)
		var f := camera.unproject_position(foot)
		var w := maxf(44.0, absf(f.y - t.y) * 0.7)
		var box := Rect2(Vector2(t.x - w * 0.5, t.y), Vector2(w, maxf(44.0, f.y - t.y)))
		if box.has_point(screen):
			var d := screen.distance_to((t + f) * 0.5)
			if d < best_d:
				best_d = d
				best = id
	return best


func animal_node(id: String) -> Node3D:
	return animals.get(id)


func _on_effect(kind: String, at: Vector3, _who: String) -> void:
	if not visible:
		return
	match kind:
		"roar": Sfx.play("rawr")
		"bell": Sfx.play("bell")
		"banana", "treat": Sfx.play("pop")
		"splash", "slide": Sfx.play("splash")
		"pump":
			Sfx.play("splash")
			_water_until = Time.get_ticks_msec() / 1000.0 + 60.0
		"shower": Sfx.play("splash")
		"drums": Sfx.play("mb_drum")
		"trumpet": Sfx.play("trumpet")   # zoo r2: Mabel the elephant
		"found": Sfx.play("place")
