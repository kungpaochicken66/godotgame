## Zoo (autoload): runs the zoo's animals on the authority and shares them with the children who
## are in the zoo (docs/zoo-engineering-standard.md sections 3, 4 and 8).
##
## The solo device, the hosting device or the dedicated server runs ZooBrain only while at least one
## player is in the zoo: the first arrival wakes it with a fresh spawn(), the last one leaving drops
## it. It packs the brain four times a second and sends that only to the peers whose recorded space
## is the zoo (a solo or host device draws it locally). One-shot events go reliably to the same
## peers. Clients never simulate: they draw the newest state at the time estimated from it. The
## discovery log (Session.model.maps) is recorded here, once per species and answer.
extends Node

const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")
const Places := preload("res://scripts/core/places.gd")

const SEND_EVERY := 0.25
## At most this many brain steps per frame; a longer stall is dropped, not replayed.
const MAX_STEPS := 5
## Seconds over which a child's speed and velocity are smoothed.
const SMOOTH := 0.5
## "Moved" means more than this many metres from where the child last stood still.
const STILL_MOVE := 0.05
## "Running" metres count only while the smoothed speed is at least this (m/s), over this many seconds.
const RUN_SPEED := 2.0
const RUN_WINDOW := 2.0
## A move of more than this in one step (m) is a jump (an arrival, a reconnect), not running.
const JUMP := 3.0
## Children within this distance (m) share the credit for a discovery.
const NEAR_FOUND := 8.0
## The one-shot effects the clients draw (section 3). "found" is recorded, not drawn.
const EFFECT_KINDS := ["roar", "bell", "banana", "treat", "splash", "slide", "pump", "shower", "drums", "trumpet"]   # zoo r2: Mabel

## The newest states, in the ZooBrain.unpack shape (time = the local estimate at arrival).
signal updated(states: Dictionary)
## A one-shot effect at a place in the zoo; `who` is the animal's id, or "".
signal effect(kind: String, at: Vector3, who: String)
## The discovery log changed (a new answer was found).
signal found_changed()

var states: Dictionary = {"time": 0.0, "animals": []}
var brain                          # authority only: ZooBrain while a player is in the zoo
var _acc := 0.0
var _send := 0.0
var _last_pack := PackedFloat32Array()
var _emotes := {}                  # peer -> [kind, time]
var _track := {}                   # peer -> the child's motion record (authority)
var _pkt_time := 0.0               # the brain time of the newest packet (every device)
var _pkt_at := -1.0                # the local clock when it arrived
var _est_floor := 0.0              # the estimate never runs backwards


func _ready() -> void:
	Session.emote.connect(func(peer: int, kind: String): _emotes[peer] = [kind, _now()])
	Session.connection_changed.connect(func(s: String):
		if s != "online":
			_reset())
	Session.town_reset.connect(func():
		_reset()
		found_changed.emit())
	Session.town_changed.connect(_refresh_toys)
	Session.town_data_changed.connect(func(key: String):
		if key == "maps":
			found_changed.emit())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Forget everything (the connection or the town changed).
func _reset() -> void:
	brain = null
	_acc = 0.0
	_last_pack = PackedFloat32Array()
	_track.clear()
	_pkt_at = -1.0
	_pkt_time = 0.0
	_est_floor = 0.0
	states = {"time": 0.0, "animals": []}
	updated.emit(states)


# ------------------------------------------------------------- who is in the zoo (pure)

## The peers whose recorded space is on the zoo's map, in order.
static func in_zoo(players: Dictionary) -> Array:
	var out := []
	for p in players:
		if Places.map_of(str(players[p].get("state", {}).get("space", "town"))) == Places.ZOO:
			out.append(p)
	out.sort()
	return out


## The remote peers a zoo message goes to: in the zoo and with an open connection.
static func recipients(players: Dictionary, open: Array) -> Array:
	return in_zoo(players).filter(func(p): return open.has(p))


# ------------------------------------------------------------- the authority

## Authority: a player's space changed (a journey) or a player left. Wakes the zoo with its first
## visitor, drops it when empty and gives an arriving peer the newest state at once.
func on_space_changed(peer: int) -> void:
	if not Session.is_authority():
		return
	_sync_awake()
	if brain != null and in_zoo(Session.players).has(peer):
		_send_to(peer, brain.pack())


## Authority: a player left the town (a disconnect).
func peer_left(peer: int) -> void:
	_emotes.erase(peer)
	_track.erase(peer)
	on_space_changed(peer)


func _sync_awake() -> void:
	var any := not in_zoo(Session.players).is_empty()
	if any and brain == null:
		_wake()
	elif not any and brain != null:
		brain = null
		_acc = 0.0
		_last_pack = PackedFloat32Array()
		_track.clear()


func _wake() -> void:
	brain = ZooBrain.new(int(Time.get_unix_time_from_system()))
	brain.reduce_motion = local_reduce_motion()
	brain.spawn()
	_acc = 0.0
	_send = SEND_EVERY
	_refresh_toys()


## This device's own Reduce Motion setting (the authority's, as the standard says).
static func local_reduce_motion() -> bool:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	return bool(cfg.get_value("display", "reduce_motion", false))


## The toys in the zoo, from the model: {"kind", "pos"}.
func toys_from_model() -> Array:
	var out := []
	for id in Session.model.items:
		var it: Dictionary = Session.model.items[id]
		if str(it.get("space", "")) == Places.ZOO:
			out.append({"kind": str(it["kind"]), "pos": Vector2(float(it["x"]), float(it["z"]))})
	return out


func _refresh_toys() -> void:
	if brain != null:
		brain.toys = toys_from_model()


func _physics_process(delta: float) -> void:
	if Session.is_authority() and Session.is_online():
		advance(delta)


## Authority: moves the zoo on by `delta` seconds (the physics loop calls this; tests do too).
func advance(delta: float) -> void:
	_sync_awake()
	if brain == null:
		return
	_acc += delta
	brain.weather = str(Session.model.weather) if Session.model != null else "sunny"
	var steps := 0
	while _acc >= ZooBrain.STEP and steps < MAX_STEPS:
		_acc -= ZooBrain.STEP
		steps += 1
		_update_tracks(ZooBrain.STEP)
		brain.tick(kid_inputs(), ZooBrain.STEP)
		_drain_events()
	if _acc >= ZooBrain.STEP:
		_acc = 0.0   # a stall: do not replay it
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		_publish()


## What the brain is told about each child in the zoo (section 3).
func kid_inputs() -> Array:
	var out := []
	var now := _now()
	for peer in in_zoo(Session.players):
		var t: Dictionary = _track.get(peer, {})
		if t.is_empty():
			continue
		var e: Array = _emotes.get(peer, ["", -99.0])
		out.append({"id": peer, "pos": t["pos"], "emote": e[0] if now - float(e[1]) < 3.0 else "", "emote_t": float(e[1]),
			"still": float(t["still"]), "speed": float(t["speed"]), "vel": t["vel"], "run": _run_metres(t)})
	return out


func _run_metres(t: Dictionary) -> float:
	var sum := 0.0
	for r in t["runs"]:
		sum += float(r[1])
	return sum


## Updates each zoo child's motion record from the position the authority knows.
func _update_tracks(dt: float) -> void:
	var here := in_zoo(Session.players)
	for peer in _track.keys():
		if not here.has(peer):
			_track.erase(peer)
	for peer in here:
		var st: Dictionary = Session.players[peer].get("state", {})
		var p := Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0)))
		if not _track.has(peer):
			_track[peer] = {"pos": p, "anchor": p, "still": 0.0, "speed": 0.0, "vel": Vector2.ZERO, "runs": [], "clock": 0.0}
			continue
		var t: Dictionary = _track[peer]
		var step: Vector2 = p - t["pos"]
		if step.length() > JUMP:
			# A jump (an arrival slot, a reconnect): not running, and standing begins anew.
			step = Vector2.ZERO
			t["anchor"] = p
			t["still"] = 0.0
		var k := 1.0 - exp(-dt / SMOOTH)
		t["vel"] = (t["vel"] as Vector2).lerp(step / dt, k)
		t["speed"] = lerpf(float(t["speed"]), step.length() / dt, k)
		t["clock"] = float(t["clock"]) + dt
		if float(t["speed"]) >= RUN_SPEED:
			t["runs"].append([t["clock"], step.length()])
		while not t["runs"].is_empty() and float(t["clock"]) - float(t["runs"][0][0]) > RUN_WINDOW:
			t["runs"].pop_front()
		if p.distance_to(t["anchor"]) > STILL_MOVE:
			t["anchor"] = p
			t["still"] = 0.0
		else:
			t["still"] = float(t["still"]) + dt
		t["pos"] = p


## Sends the brain's one-shot events to the zoo peers, records discoveries, clears the list.
func _drain_events() -> void:
	if brain.events.is_empty():
		return
	var list := []
	for ev in brain.events:
		var clean := {"kind": str(ev.get("kind", "")), "who": str(ev.get("who", "")), "at": ev.get("at", Vector3.ZERO)}
		if clean["kind"] == "found":
			clean["species"] = str(ev.get("species", ""))
			clean["answer"] = str(ev.get("answer", ""))
			_record_found(clean)
		list.append(clean)
	brain.events.clear()
	for p in recipients(Session.players, Session._open_peers()):
		ev_zoo_events.rpc_id(p, list)
	if _local_in_zoo():
		_play_events(list)


## Authority: the first time a town sees an answer, it is written to the model with the names of the
## children within NEAR_FOUND metres, saved and shared.
func _record_found(ev: Dictionary) -> void:
	if not ("maps" in Session.model):
		return   # the town model without the discovery log (before schema 3)
	var species: String = ev["species"]
	var answer: String = ev["answer"]
	if species == "" or answer == "":
		return
	var maps: Dictionary = Session.model.maps
	if typeof(maps.get(Places.ZOO)) != TYPE_DICTIONARY:
		maps[Places.ZOO] = {}
	var zoo: Dictionary = maps[Places.ZOO]
	if typeof(zoo.get("found")) != TYPE_DICTIONARY:
		zoo["found"] = {}
	var found_map: Dictionary = zoo["found"]
	if typeof(found_map.get(species)) != TYPE_DICTIONARY:
		found_map[species] = {}
	var of_species: Dictionary = found_map[species]
	if of_species.has(answer):
		return
	var at: Vector3 = ev["at"]
	var by := []
	for peer in in_zoo(Session.players):
		var st: Dictionary = Session.players[peer].get("state", {})
		if Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))).distance_to(Vector2(at.x, at.z)) <= NEAR_FOUND:
			var nick := Session.nick_of(peer)
			if nick != "" and not by.has(nick):
				by.append(nick)
	of_species[answer] = {"by": by, "t": int(Time.get_unix_time_from_system())}
	Session.share("maps")   # sends ev_town_data("maps", ...) and marks the town dirty


func _local_in_zoo() -> bool:
	return Session.mode != "server" and in_zoo(Session.players).has(Session.my_id)


func _publish() -> void:
	var data: PackedFloat32Array = brain.pack()
	_last_pack = data
	if _local_in_zoo():
		_apply(data)
	for p in recipients(Session.players, Session._open_peers()):
		ev_zoo_state.rpc_id(p, data)


func _send_to(peer: int, data: PackedFloat32Array) -> void:
	if peer == Session.my_id and Session.mode != "server":
		_apply(data)
	elif Session._open_peers().has(peer):
		ev_zoo_state.rpc_id(peer, data)


# ------------------------------------------------------------- every device

@rpc("authority", "call_remote", "unreliable_ordered")
func ev_zoo_state(data: PackedFloat32Array) -> void:
	_apply(data)


@rpc("authority", "call_remote", "reliable")
func ev_zoo_events(list: Array) -> void:
	_play_events(list)


func _apply(data: PackedFloat32Array) -> void:
	var s := ZooBrain.unpack(data)
	if s["animals"].is_empty():
		return   # not a whole state of this version's zoo
	if float(s["time"]) < _pkt_time - 0.5:
		_est_floor = 0.0   # the zoo woke up afresh: its clock started again
	_pkt_time = s["time"]
	_pkt_at = _now()
	states = s
	updated.emit(states)


## The zoo's clock as this device estimates it: the newest packet's time plus the time since it
## arrived (never running backwards between two packets).
func est_time() -> float:
	if _pkt_at < 0.0:
		return 0.0
	_est_floor = maxf(_est_floor, _pkt_time + (_now() - _pkt_at))
	return _est_floor


func _play_events(list: Array) -> void:
	for ev in list:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var kind := str(ev.get("kind", ""))
		if not kind in EFFECT_KINDS:
			continue
		var at: Variant = ev.get("at", Vector3.ZERO)
		effect.emit(kind, at if typeof(at) == TYPE_VECTOR3 else Vector3.ZERO, str(ev.get("who", "")))


# ------------------------------------------------------------- requests and the discovery log

## Use a station (an id of ZooMap.STATIONS). The reply is {"ok"} or {"ok": false, "error"}
## (Session.request_done).
func use(station: String) -> int:
	return Session._ask("zoo_use", [station])


## Offer a treat to a resident (an id of ZooMap.ORDER).
func offer(animal_id: String) -> int:
	return Session._ask("zoo_offer", [animal_id])


## What the town has found about a species: {answer: {"by": [nicks], "t": unix}}.
func found(species: String) -> Dictionary:
	if not ("maps" in Session.model):
		return {}
	var maps: Dictionary = Session.model.maps
	var zoo: Variant = maps.get(Places.ZOO)
	if typeof(zoo) != TYPE_DICTIONARY:
		return {}
	var all: Variant = (zoo as Dictionary).get("found")
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var mine: Variant = (all as Dictionary).get(species)
	return mine if typeof(mine) == TYPE_DICTIONARY else {}


## The hint for the first answer of this species not yet found ("" when all are).
func hint(species: String) -> String:
	var answers: Dictionary = ZooLife.ANSWERS.get(species, {})
	var got := found(species)
	for answer in answers:
		if not got.has(answer):
			return str(answers[answer])
	return ""
