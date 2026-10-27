## Animals (autoload): runs the animal friends on the authority and shares them.
##
## The solo device, the hosting device or the dedicated server simulates the
## animals (scripts/core/animal_brain.gd) and broadcasts a compact state four
## times a second; every peer draws the same animals. Animals are not part of
## the town save and never affect placement or other shared state.
extends Node

const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const SEND_EVERY := 0.25

signal updated(states: Array)
## A child threw Biscuit's ball (fetch): draw it flying.
signal thrown(from: Vector2, to: Vector2)
## Tumble sprays a shaped fountain (F03, r11): heart, star or round.
signal fountain(shape: String, at: Vector2, ry: float)
## House visits changed (r18): guests is {animal kind: peer}.
signal guests_changed(guests: Dictionary)

var brain                     # authority only
var states: Array = []        # latest states for drawing (all peers)
var _acc := 0.0
var _send := 0.0
var _emotes := {}             # peer -> [kind, time]
## House visits (r18, design/animal-visits.md): animal kind -> the peer it is visiting with. Kept by the
## authority and sent to every device; never saved.
var guests := {}
var _guest_space := {}        # authority: kind -> the space its child was last seen in


func _ready() -> void:
	Session.town_reset.connect(_on_town_reset)
	Session.connection_changed.connect(func(s):
		if s != "online":
			brain = null
			states = []
			guests = {}
			_guest_space = {}
			updated.emit(states)
			guests_changed.emit(guests))
	Session.player_joined_authority.connect(func(peer):
		if multiplayer.get_peers().has(peer):
			ev_guests.rpc_id(peer, guests))   # a late joiner learns who is visiting
	Session.players_changed.connect(_release_departed)
	Session.emote.connect(func(peer, kind): _emotes[peer] = [kind, Time.get_ticks_msec() / 1000.0])


func _on_town_reset() -> void:
	guests = {}
	_guest_space = {}
	guests_changed.emit(guests)
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
