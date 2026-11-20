## Draws rideable carts (design/puzzle-rooms-and-rides.md): every cart that is
## out moves along its route from Session.rides (the authority's route and
## distance, this device's clock), and a cart nobody rides stands at its station.
## A seated child follows the cart through its "Seat0" marker like any seat
## (town_world.gd), so the rider is never drawn twice or left behind.
##
## The camera is not touched here: it keeps following the child with the same
## gentle glide and the same fixed direction as on foot, and the cart is slower
## than walking, so a ride never turns or shakes the view.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")

signal ride_hint(text: String)

var world: Node3D
var moved := 0.0              # meters carts were drawn moving on this device (for tests)
var hints := 0                # hints shown to this device's rider (for tests)
var seated := {}              # animal kind -> its node while it is drawn sitting in a trailer (legs tucked away)
var passengers_drawn := {}    # animal kind -> station whose trailer it was drawn in on this device (for tests)
var _arrow: Node3D
var _arrow_t := 0.0
var _last := {}               # station id -> Vector2 where its cart was drawn last


func setup(w: Node3D) -> void:
	world = w
	_arrow = Node3D.new()
	_arrow.top_level = true
	_arrow.visible = false
	add_child(_arrow)
	var c := Color("#ef6f86")
	Kit.part(_arrow, Kit.cylinder(0.0, 0.2, 0.32, 4), Kit.mat(c, 0.6, c * 0.6), Vector3(0, 0, 0), Vector3(180, 45, 0))
	Kit.cyl(_arrow, 0.06, 0.06, 0.26, Kit.mat(c, 0.6, c * 0.6), Vector3(0, 0.27, 0))
	Session.ride_changed.connect(_on_ride)


## Where a cart is now: {"pos": Vector2, "dir": Vector2}. A cart at home is at its station.
func pose_of(id: String) -> Dictionary:
	var r: Dictionary = Session.rides.get(id, {})
	if not r.is_empty() and not r["route"]["legs"].is_empty():
		return RideRules.pose(r["route"], Session.ride_distance(id))
	var it: Dictionary = Session.model.items.get(id, {})
	if it.is_empty():
		return {"pos": Vector2.ZERO, "dir": Vector2(0, 1)}
	return {"pos": Vector2(it["x"], it["z"]), "dir": RideRules.TownModel.facing(it["rot"])}


## Moves every cart on screen. Called by the world before it seats the children, so a rider is
## placed on the cart where it is this frame.
func advance(delta: float) -> void:
	if _arrow_t > 0.0:
		_arrow_t -= delta
		_arrow.visible = _arrow_t > 0.0 and world.view_space == "town"
		_arrow.position.y = 1.0 + sin(_arrow_t * 5.0) * 0.08
	# An animal that is no longer in a trailer stands on its own legs again.
	for kind in seated.keys():
		var was: Node3D = seated[kind]
		if not is_instance_valid(was):
			seated.erase(kind)
		elif not Animals.riders.has(kind) or not Animals.aboard(kind):
			for leg in was._legs:
				leg.visible = true
			seated.erase(kind)
	if world.view_space != "town":
		return
	for id in world.item_nodes:
		var node: Node3D = world.item_nodes[id]
		if node.get_meta("item")["kind"] != RideRules.STATION:
			continue
		var cart := node.get_node_or_null("Cart") as Node3D
		if cart == null:
			continue
		var trailer := node.get_node_or_null("Trailer") as Node3D
		if not Session.rides.has(id):
			if cart.top_level:
				cart.top_level = false
				cart.transform = Transform3D.IDENTITY
			if trailer and trailer.top_level:
				trailer.top_level = false
				trailer.transform = Transform3D(Basis(), Vector3(0, 0, -Animals.TRAILER_GAP))   # as built (props_puzzle.gd)
			_last.erase(id)
			continue
		if trailer:
			# The trailer follows on the same rails, a little behind; an animal friend aboard sits in it.
			var tp: Dictionary = Animals.trailer_pose(id)
			trailer.top_level = true
			trailer.global_transform = Transform3D(Basis(Vector3.UP, atan2(tp["dir"].x, tp["dir"].y)), Vector3(tp["pos"].x, 0, tp["pos"].y))
			for kind in Animals.riders:
				var pet: Node3D = world.animals.get(kind)
				if Animals.riders[kind] == id and pet and Animals.aboard(kind):
					# Sitting in the trailer: legs tucked away, the body resting on the trailer's floor.
					var hip: float = pet._legs[0].position.y if not pet._legs.is_empty() else 0.0
					var at: Vector3 = trailer.global_position + Vector3(0, 0.26 - hip, 0)
					pet.position = at
					pet._target_pos = at
					pet.rotation.y = trailer.rotation.y
					pet._target_ry = trailer.rotation.y
					for leg in pet._legs:
						leg.visible = false
					seated[kind] = pet
					passengers_drawn[kind] = id
		var p := pose_of(id)
		var at: Vector2 = p["pos"]
		cart.top_level = true
		cart.global_transform = Transform3D(Basis(Vector3.UP, atan2(p["dir"].x, p["dir"].y)), Vector3(at.x, 0, at.y))
		var step: float = at.distance_to(_last.get(id, at))
		_last[id] = at
		if step > 0.0 and step < 1.0:
			moved += step


## Tells this device's rider why the cart stopped, and points at the place.
func _on_ride(id: String, ride: Dictionary) -> void:
	if ride.is_empty() or int(ride["peer"]) != Session.my_id or ride["phase"] != "stopped":
		return
	var text := ""
	match str(ride["why"]):
		"end", "long": text = RideRules.ERR_END
		"wrong_way": text = "The next rail does not join up. Turn it, or get off."
		"blocked": text = RideRules.ERR_BLOCKED
		"broken": text = RideRules.ERR_BROKEN
	if text == "":
		return
	hints += 1
	ride_hint.emit(text)
	if ride["why"] != "broken":
		var at: Vector2 = ride["route"]["at"]
		_arrow.global_position = Vector3(at.x, 1.0, at.y)
		_arrow_t = 5.0
