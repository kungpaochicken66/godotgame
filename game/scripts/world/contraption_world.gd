## Drawn effects for contraptions and the living town (design/contraptions-and-town-life.md):
## the dotted links shown while decorating, the spark that hops from thing to thing, a pressed
## button or step pad, a spinning pinwheel, a bubble machine's bubbles, and the soft ring under
## the thing an animal is busy with. Everything here is local drawing from shared state and
## events; nothing is sent or saved. With Reduce motion on nothing spins, flies or pulses:
## things answer with a short glow instead.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Contraptions := preload("res://scripts/core/contraptions.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const SPARK := Color("#ffd27a")
const LINK := Color("#f2a541")
const RING := Color("#ef6f86")

var world: Node3D
var links_on := false
var link_pairs := []          # [[from id, to id]] drawn now (for tests)
var sparks_drawn := 0         # sparks started on this device (for tests)
var effects := {}             # effect name -> times drawn on this device (for tests)
var presses := 0              # trigger presses drawn (for tests)
var spinning := {}            # pinwheel id -> seconds left
var bubbling := {}            # bubble machine id -> seconds left
var windy := false            # pinwheels are turning in the autumn wind on this device (for tests)
var rings := {}               # item id -> ring node (things animals are busy with)
var _links_root: Node3D
var _rings_root: Node3D
var _recent := {}             # item id -> seconds since a spark touched it (no sparks back to those)
var _flying := []             # [{"node", "from", "to", "t"}]
var _dirty := false
var _t := 0.0


func setup(w: Node3D) -> void:
	world = w
	_links_root = Node3D.new()
	_links_root.name = "Links"
	add_child(_links_root)
	_rings_root = Node3D.new()
	_rings_root.name = "Rings"
	add_child(_rings_root)
	Session.contraption_triggered.connect(_on_trigger)
	Session.contraption_reacted.connect(_on_react)
	Session.item_changed.connect(func(_i): _dirty = true)
	Session.items_removed.connect(func(_i): _dirty = true)
	Session.town_reset.connect(func(): _dirty = true)
	world.view_changed.connect(func(_s): _dirty = true)
	Animals.focus_changed.connect(func(_f): _dirty = true)


# ------------------------------------------------------------- links (decorating)

## Shows or hides the dotted lines between linked things (the controller calls this with the mode).
func show_links(on: bool) -> void:
	links_on = on
	_dirty = true


func _item_point(id: String, lift := 0.12) -> Vector3:
	var it: Dictionary = Session.model.items.get(id, {})
	if it.is_empty():
		return Vector3.ZERO
	# On the floor plan: a ceiling light and the button under it are joined along the floor.
	return Vector3(it["x"], lift, it["z"])


func _rebuild_links() -> void:
	for c in _links_root.get_children():
		c.queue_free()
	link_pairs = Contraptions.links(Session.model, world.view_space) if links_on else []
	var mat := Kit.mat(LINK, 0.6, LINK * 0.5)
	for pair in link_pairs:
		var a := _item_point(pair[0])
		var b := _item_point(pair[1])
		if a.distance_to(b) < 0.3:
			# One thing right above the other (a ceiling light over a button): a small ring around the spot.
			Kit.part(_links_root, Kit.torus(0.3, 0.36), mat, a)
			continue
		var n := maxi(2, int(a.distance_to(b) / 0.22))
		for i in range(1, n):
			var dot := MeshInstance3D.new()
			dot.mesh = Kit.sphere(0.035, 6)
			dot.material_override = mat
			dot.position = a.lerp(b, float(i) / n)
			_links_root.add_child(dot)
		# A little arrow head at the far end: the spark goes this way first.
		var head := Kit.part(_links_root, Kit.cylinder(0.0, 0.07, 0.14, 8), mat, a.lerp(b, 0.82))
		head.look_at_from_position(head.position, b + Vector3(0, 0.0001, 0), Vector3.UP)
		head.rotate_object_local(Vector3.RIGHT, -PI / 2.0)


## The reactors this thing would set off first (for the placement hint).
func linked_count(id: String) -> int:
	return Contraptions.linked(Session.model, id).size()


# ------------------------------------------------------------- rings under what animals use

func _rebuild_rings() -> void:
	for c in _rings_root.get_children():
		c.queue_free()
	rings.clear()
	if world.view_space != "town":
		return
	for kind in Animals.focus:
		var id: String = Animals.focus[kind].get("id", "")
		var it: Dictionary = Session.model.items.get(id, {})
		if it.is_empty() or it["space"] != "town" or rings.has(id):
			continue
		var r: float = Catalog.get_def(it["kind"])["radius"] + 0.25
		var ring := Kit.part(_rings_root, Kit.torus(r - 0.04, r + 0.02), Kit.mat(RING, 0.6, RING * 0.4), Vector3(it["x"], 0.06, it["z"]))
		rings[id] = ring


# ------------------------------------------------------------- sparks and effects

func _count(effect: String) -> void:
	effects[effect] = int(effects.get(effect, 0)) + 1


func _in_view(id: String) -> bool:
	return world.item_nodes.has(id)


func _on_trigger(id: String) -> void:
	_recent[id] = 0.0
	if not _in_view(id):
		return
	presses += 1
	var node: Node3D = world.item_nodes[id]
	var swing := node.get_node_or_null("Swing") as Node3D
	if swing and not world.reduce_motion:
		# A signal rail's arm and a weather bell's chimes swing when they are set off.
		var tws := create_tween()
		tws.tween_property(swing, "rotation:z", 0.5, 0.12)
		tws.tween_property(swing, "rotation:z", -0.35, 0.2)
		tws.tween_property(swing, "rotation:z", 0.0, 0.3)
	if swing:
		_near_sound("mb_bell", id)
	var part := node.get_node_or_null("Cap") as Node3D
	var dip := 0.05
	if part == null:
		part = node.get_node_or_null("Pad") as Node3D
		dip = 0.02
	if part:
		var rest_y: float = part.get_meta("rest_y", part.position.y)
		part.set_meta("rest_y", rest_y)
		var tw := create_tween()
		tw.tween_property(part, "position:y", rest_y - dip, 0.07)
		tw.tween_property(part, "position:y", rest_y, 0.25)
	_near_sound("tap", id)
	_send_sparks(id)


func _on_react(id: String, _from: String, effect: String, _on: bool) -> void:
	_recent[id] = 0.0
	if not _in_view(id):
		return
	_count(effect)
	var node: Node3D = world.item_nodes[id]
	match effect:
		"light", "music":
			_pop(node)
			_near_sound("pop", id)
		"spin":
			spinning[id] = Contraptions.EFFECT_SECONDS["spin"]
			_near_sound("mb_chime", id)
			if world.reduce_motion:
				_pop(node)
		"bubbles":
			bubbling[id] = Contraptions.EFFECT_SECONDS["bubbles"]
			_near_sound("pop", id)
			if world.reduce_motion:
				_pop(node)
			else:
				_bubbles(node)
	_send_sparks(id)


## Sparks leave for everything this thing passes the spark on to (the authority walks the same
## links one hop later); nothing flies back to a thing the chain has just been through.
func _send_sparks(from: String) -> void:
	for to in Contraptions.linked(Session.model, from):
		if _recent.has(to):
			continue
		sparks_drawn += 1
		if world.reduce_motion:
			continue   # the things themselves still answer, one after another
		var s := MeshInstance3D.new()
		s.mesh = Kit.sphere(0.07, 8)
		s.material_override = Kit.mat(SPARK, 0.4, SPARK)
		add_child(s)
		_flying.append({"node": s, "from": _item_point(from, 0.3), "to": _item_point(to, 0.3), "t": 0.0})


func _pop(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 1.1, 0.1)
	tw.tween_property(node, "scale", Vector3.ONE, 0.25)


func _bubbles(node: Node3D) -> void:
	var nozzle := node.get_node_or_null("Nozzle") as Node3D
	var old := node.get_node_or_null("Bubbles")
	if old:
		old.queue_free()
	var p := CPUParticles3D.new()
	p.name = "Bubbles"
	p.amount = 22
	p.lifetime = 2.6
	p.position = nozzle.position if nozzle else Vector3(0, 0.45, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 28
	p.gravity = Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.7
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var m := SphereMesh.new()
	m.radius = 0.062   # a little larger and bluer than at first: they were pale and small on grass in the Mac's pictures
	m.height = 0.124
	m.radial_segments = 10
	m.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.68, 0.88, 1.0, 0.8)
	m.material = mat
	p.mesh = m
	node.add_child(p)
	p.emitting = true


func _near_sound(name: String, id: String) -> void:
	var me: Node3D = world.local_kid()
	var node: Node3D = world.item_nodes.get(id)
	if me and node and me.global_position.distance_to(node.global_position) < 14.0:
		Sfx.play(name)


func _process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	if _dirty:
		_dirty = false
		_rebuild_links()
		_rebuild_rings()
	for id in _recent.keys():
		_recent[id] += delta
		if _recent[id] > 3.0:
			_recent.erase(id)
	for f in _flying.duplicate():
		f["t"] += delta / (Contraptions.HOP_MS / 1000.0)
		var k: float = minf(f["t"], 1.0)
		var p: Vector3 = f["from"].lerp(f["to"], k)
		f["node"].position = p + Vector3(0, sin(k * PI) * 0.35, 0)
		if f["t"] >= 1.0:
			f["node"].queue_free()
			_flying.erase(f)
	for id in spinning.keys():
		spinning[id] -= delta
		var node: Node3D = world.item_nodes.get(id)
		var wheel := node.get_node_or_null("Wheel") as Node3D if node else null
		if wheel and not world.reduce_motion:
			# Fast at first, then slowing to a stop.
			wheel.rotation.z += delta * 9.0 * clampf(spinning[id] / 2.0, 0.0, 1.0)
		if spinning[id] <= 0.0:
			spinning.erase(id)
	# Weather toys: in windy autumn weather every pinwheel outdoors turns by itself.
	windy = Session.model.weather == "autumn" and world.view_space == "town" and not world.reduce_motion
	if windy:
		for id in world.item_nodes:
			var node: Node3D = world.item_nodes[id]
			if node.get_meta("item")["kind"] == "pinwheel" and not spinning.has(id) and not node.get_meta("item").has("gift"):
				var wheel := node.get_node_or_null("Wheel") as Node3D
				if wheel:
					wheel.rotation.z += delta * 2.6
	for id in bubbling.keys():
		bubbling[id] -= delta
		if bubbling[id] <= 0.0:
			bubbling.erase(id)
			var node: Node3D = world.item_nodes.get(id)
			var p := node.get_node_or_null("Bubbles") as CPUParticles3D if node else null
			if p:
				p.emitting = false
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(p):
						p.queue_free())
	if not world.reduce_motion:
		var s := 1.0 + sin(_t * 3.0) * 0.05
		for ring in rings.values():
			ring.scale = Vector3(s, 1, s)
