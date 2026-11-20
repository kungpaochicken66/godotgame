## Animals (autoload): runs the animal friends on the authority and shares them.
##
## The solo device, the hosting device or the dedicated server simulates the
## animals (scripts/core/animal_brain.gd) and broadcasts a compact state four
## times a second; every peer draws the same animals. Animals are not part of
## the town save and never affect placement or other shared state.
extends Node

const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const TownLife := preload("res://scripts/core/town_life.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")
const SEND_EVERY := 0.25

signal updated(states: Array)
## A child threw Biscuit's ball (fetch): draw it flying.
signal thrown(from: Vector2, to: Vector2)
## Tumble sprays a shaped fountain (F03, r11): heart, star or round.
signal fountain(shape: String, at: Vector2, ry: float)
## House visits changed (r18): guests is {animal kind: peer}.
signal guests_changed(guests: Dictionary)
## A living town: what each animal is busy with changed. focus is {animal kind: {"id", "why"}}.
signal focus_changed(focus: Dictionary)

var brain                     # authority only
var states: Array = []        # latest states for drawing (all peers)
var _acc := 0.0
var _send := 0.0
var _emotes := {}             # peer -> [kind, time]
## House visits (r18, design/animal-visits.md): animal kind -> the peer it is visiting with. Kept by the
## authority and sent to every device; never saved.
var guests := {}
## Animal passengers: kind -> the cart station whose trailer it rides in (every device).
var riders := {}
signal riders_changed(r: Dictionary)
const RIDE_ERRORS := {
	"too_big": "Tumble is too big for the trailer, but loves to watch.",
	"far": "Call them from closer to the cart.",
	"taken": "They are with a friend right now.",
	"busy": "They are busy playing. Try again in a moment.",
	"party": "Everyone is at the party!",
}
## How far behind the cart's middle the trailer rides, in meters along the rails.
const TRAILER_GAP := 1.4
var _guest_space := {}        # authority: kind -> the space its child was last seen in
## A living town (design/contraptions-and-town-life.md): animal kind -> {"id": the thing it is busy with
## ("" for the rolling ball), "why": the reason (core/town_life.gd)}. Kept by the authority and sent to
## every device when it changes; never saved.
var focus := {}


func _ready() -> void:
	Session.town_reset.connect(_on_town_reset)
	Session.town_reset.connect(_on_town_reset_riders)
	Session.connection_changed.connect(func(s):
		if s != "online":
			brain = null
			states = []
			guests = {}
			riders = {}
			riders_changed.emit(riders)
			_guest_space = {}
			focus = {}
			updated.emit(states)
			guests_changed.emit(guests)
			focus_changed.emit(focus))
	Session.player_joined_authority.connect(func(peer):
		if multiplayer.get_peers().has(peer):
			ev_guests.rpc_id(peer, guests)   # a late joiner learns who is visiting
			ev_riders.rpc_id(peer, riders)   # and who is riding in a trailer
			ev_focus.rpc_id(peer, focus))
	Session.players_changed.connect(_release_departed)
	Session.emote.connect(func(peer, kind): _emotes[peer] = [kind, Time.get_ticks_msec() / 1000.0])


func _on_town_reset_riders() -> void:
	riders = {}
	riders_changed.emit(riders)


func _on_town_reset() -> void:
	guests = {}
	_guest_space = {}
	focus = {}
	guests_changed.emit(guests)
	focus_changed.emit(focus)
	if Session.is_authority():
		brain = AnimalBrain.new()
		brain.spawn(Session.model)
		_publish()


## Children outdoors, as the brain sees them.
func kid_inputs() -> Array:
	var out := []
	var now := Time.get_ticks_msec() / 1000.0
	for peer in Session.players:
		var s: Dictionary = Session.players[peer].get("state", {})
		if s.get("space", "town") != "town":
			continue
		var e: Array = _emotes.get(peer, ["", -99.0])
		out.append({"id": peer, "pos": Vector2(s.get("x", 0.0), s.get("z", 0.0)), "emote": e[0] if now - e[1] < 3.0 else "", "emote_t": e[1]})
	return out


func _physics_process(delta: float) -> void:
	if brain == null or not Session.is_authority() or not Session.is_online():
		return
	_acc += delta
	for kind in guests:
		var host: Dictionary = Session.players.get(guests[kind], {})
		if not host.is_empty():
			_guest_space[kind] = str(host.get("state", {}).get("space", "town"))
	_carry_riders()
	var kids := kid_inputs()
	while _acc >= AnimalBrain.STEP:
		_acc -= AnimalBrain.STEP
		brain.tick(Session.model, kids)
		for ev in brain.events:
			if ev["kind"] == "fountain":
				ev_fountain.rpc(ev["shape"], ev["at"], ev["ry"])
			elif ev["kind"] == "grow":
				Session.grow_by_animal(ev["id"])
		brain.events.clear()
		# An animal that walks onto a step pad sets it off, like a child, while a child is outdoors to
		# see it (an empty town does not switch its own lamps and save itself all night).
		if not kids.is_empty():
			for a in brain.animals:
				if not a["away"]:
					Session.step_on_pads(a["kind"], "town", a["pos"])
	var f: Dictionary = brain.focus_map()
	if f != focus:
		ev_focus.rpc(f)
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		_publish()


func _publish() -> void:
	ev_animals.rpc(brain.pack())


@rpc("authority", "call_local", "unreliable_ordered")
func ev_animals(data: PackedFloat32Array) -> void:
	states = AnimalBrain.unpack(data)
	updated.emit(states)


@rpc("authority", "call_local", "reliable")
func ev_thrown(from: Vector2, to: Vector2) -> void:
	thrown.emit(from, to)


@rpc("authority", "call_local", "reliable")
func ev_fountain(shape: String, at: Vector2, ry: float) -> void:
	fountain.emit(shape, at, ry)


# ------------------------------------------------------------- a living town

## Authority: a child placed something outdoors; the nearest free animal comes to look.
func item_placed(id: String) -> void:
	if brain and Session.is_authority():
		brain.notice(Session.model, id)


## Authority: something was switched on or set off; the animals who love it come over.
func enliven(id: String) -> void:
	if brain and Session.is_authority():
		brain.enliven(Session.model, id)


## Authority: a toy-track ball rolls to `end`; Biscuit may run to watch.
func watch_ball(end: Vector2) -> void:
	if brain and Session.is_authority():
		brain.watch_ball(Session.model, end)


## The line for what an animal is busy with ("" when it is on its own routine), untranslated with %s
## for its name.
func focus_line(kind: String) -> String:
	return TownLife.say(str(focus.get(kind, {}).get("why", "")))


@rpc("authority", "call_local", "reliable")
func ev_focus(f: Dictionary) -> void:
	var clean := {}
	for k in f:
		if AnimalBrain.ORDER.has(str(k)) and typeof(f[k]) == TYPE_DICTIONARY and TownLife.say(str(f[k].get("why", ""))) != "":
			clean[str(k)] = {"id": str(f[k].get("id", "")).left(16), "why": str(f[k]["why"])}
	focus = clean
	focus_changed.emit(focus)


# ------------------------------------------------------------- house visits (r18)

## Messages for the brain's refusals (the client shows them translated).
const VISIT_ERRORS := {
	"too_big": "Tumble is too big for the door, but loves to play outside.",
	"far": "Walk closer to invite them.",
	"taken": "They are already visiting a friend.",
	"has_guest": "One animal friend at a time can come home with you.",
	"busy": "They are busy playing. Try again in a moment.",
	"party": "Everyone is at the party!",
}


## Authority: a child asks an animal home (on) or says goodbye (off). Returns "" or the reason.
func request_visit(peer: int, kind: String, on: bool, space: String, at: Vector2) -> String:
	if brain == null:
		return "Invite animal friends outdoors."
	if not on:
		if guests.get(kind, 0) != peer:
			return ""   # nothing to end: already gone home
		end_visit(kind)
		return ""
	if space != "town":
		return "Invite animal friends outdoors."
	var why: String = brain.start_visit(kind, peer, at)
	if why != "":
		return VISIT_ERRORS.get(why, why)
	guests[kind] = peer
	_guest_space[kind] = "town"
	_share_guests()
	return ""


## Authority: a child boards the tram. Their animal friend cannot come along, so the visit ends and it
## waits in town. Returns the line to show ("%s will wait for you in town."), or "" when nothing ended.
## Returns the English name of the animal that was visiting with this child ("" for none; a child has at
## most one visitor). The client says "%s will wait for you in town." in its own language.
func child_boards(peer: int) -> String:
	var name := ""
	for kind in guests.keys():
		if guests[kind] == peer:
			name = str(AnimalBrain.SPECIES.get(kind, {}).get("name", kind))
			end_visit(kind)
	return name


## Authority: ends a visit. An animal that was in a house appears at that house's front door outdoors.
func end_visit(kind: String) -> void:
	if not guests.has(kind):
		return
	var door = null
	var house := TownModel.house_of(str(_guest_space.get(kind, "town")))
	if house != "" and Session.model.items.has(house):
		door = TownModel.door_point(Session.model.items[house])
	if brain:
		brain.end_visit(Session.model, kind, door)
	guests.erase(kind)
	_guest_space.erase(kind)
	_share_guests()
	_publish()


# ------------------------------------------------------------- animal passengers

## Where a cart's trailer is: {"pos", "dir"}; behind the cart on its route, or behind the station.
func trailer_pose(station: String) -> Dictionary:
	var r: Dictionary = Session.rides.get(station, {})
	if not r.is_empty() and not r["route"]["legs"].is_empty():
		var d: float = Session.ride_distance(station) - TRAILER_GAP
		if not r["route"]["loop"] and d < -RideRules.CELL * 0.5:
			# On an open track there are no rails behind the station: the trailer stands straight behind it.
			var leg: Array = r["route"]["legs"][0]
			var ahead := Vector2(leg[2], leg[3])
			return {"pos": Vector2(leg[0], leg[1]) * RideRules.CELL + ahead * d, "dir": ahead}
		return RideRules.pose(r["route"], d)
	var it: Dictionary = Session.model.items.get(station, {})
	if it.is_empty():
		return {"pos": Vector2.ZERO, "dir": Vector2(0, 1)}
	var dir: Vector2 = TownModel.facing(it["rot"])
	return {"pos": Vector2(it["x"], it["z"]) - dir * TRAILER_GAP, "dir": dir}


## Authority: a child in a cart at its station asks an animal for a ride (on), or lets it out (off).
## Returns "" or the reason. An animal gets in and out at the station only.
func request_ride(peer: int, kind: String, on: bool) -> String:
	if brain == null:
		return RIDE_ERRORS["far"]
	var station: String = Session.ride_of(peer)
	if not on:
		if riders.get(kind, "") != "" and riders[kind] == station:
			end_ride(kind)
		return ""
	if station == "":
		return "Get into the cart first."
	if Session.rides[station]["phase"] != "ready":
		return "Animals get in at the station. Ride back there first."
	if riders.values().has(station) and riders.get(kind, "") != station:
		return "One animal friend at a time rides in the trailer."
	var why: String = brain.start_ride(kind, station, trailer_pose(station)["pos"])
	if why != "":
		return RIDE_ERRORS.get(why, why)
	riders[kind] = station
	ev_riders.rpc(riders)
	return ""


## Authority: the animal hops out beside its cart's station.
func end_ride(kind: String) -> void:
	if not riders.has(kind):
		return
	var it: Dictionary = Session.model.items.get(riders[kind], {})
	var at: Vector2 = Vector2(it["x"], it["z"]) + TownModel.facing(it["rot"] + 6) * 1.4 if not it.is_empty() else brain.animal(kind).get("pos", Vector2.ZERO)
	if brain:
		brain.end_ride(Session.model, kind, at)
	riders.erase(kind)
	ev_riders.rpc(riders)
	_publish()


## Authority, every tick: a passenger whose cart went home (its child got off, sat elsewhere or left
## the town) or whose town is at a party hops out at the station; one that is aboard is carried.
func _carry_riders() -> void:
	for kind in riders.keys():
		var station: String = riders[kind]
		if not Session.rides.has(station) or brain.time < brain.parade_until:
			end_ride(kind)
			continue
		var p := trailer_pose(station)
		brain.carry(kind, p["pos"], atan2(p["dir"].x, p["dir"].y))


@rpc("authority", "call_local", "reliable")
func ev_riders(r: Dictionary) -> void:
	var clean := {}
	for k in r:
		if AnimalBrain.VISITORS.has(str(k)):
			clean[str(k)] = str(r[k])
	riders = clean
	riders_changed.emit(riders)


## Is this animal sitting in a trailer right now (on this device's knowledge)?
func aboard(kind: String) -> bool:
	if not riders.has(kind):
		return false
	for st in states:
		if st["kind"] == kind:
			return st["pos"].distance_to(trailer_pose(riders[kind])["pos"]) < 1.5
	return false


## Authority: a child who left or disconnected takes nobody with them.
func _release_departed() -> void:
	if not Session.is_authority():
		return
	for kind in guests.keys():
		if not Session.players.has(guests[kind]):
			end_visit(kind)


func _share_guests() -> void:
	ev_guests.rpc(guests)


@rpc("authority", "call_local", "reliable")
func ev_guests(g: Dictionary) -> void:
	var clean := {}
	for k in g:
		if AnimalBrain.VISITORS.has(str(k)):
			clean[str(k)] = int(g[k])
	guests = clean
	guests_changed.emit(guests)
