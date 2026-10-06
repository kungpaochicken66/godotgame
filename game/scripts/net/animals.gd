## Animals (autoload): runs the animal friends on the authority and shares them.
##
## The solo device, the hosting device or the dedicated server simulates the
## animals (scripts/core/animal_brain.gd) and broadcasts a compact state four
## times a second; every peer draws the same animals. Animals are not part of
## the town save and never affect placement or other shared state.
extends Node

const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const SEND_EVERY := 0.25

signal updated(states: Array)

var brain                     # authority only
var states: Array = []        # latest states for drawing (all peers)
var _acc := 0.0
var _send := 0.0
var _emotes := {}             # peer -> [kind, time]


func _ready() -> void:
	Session.town_reset.connect(_on_town_reset)
	Session.connection_changed.connect(func(s):
		if s != "online":
			brain = null
			states = []
			updated.emit(states))
	Session.emote.connect(func(peer, kind): _emotes[peer] = [kind, Time.get_ticks_msec() / 1000.0])


func _on_town_reset() -> void:
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
		out.append({"id": peer, "pos": Vector2(s.get("x", 0.0), s.get("z", 0.0)), "emote": e[0] if now - e[1] < 3.0 else ""})
	return out


func _physics_process(delta: float) -> void:
	if brain == null or not Session.is_authority() or not Session.is_online():
		return
	_acc += delta
	var kids := kid_inputs()
	while _acc >= AnimalBrain.STEP:
		_acc -= AnimalBrain.STEP
		brain.tick(Session.model, kids)
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
