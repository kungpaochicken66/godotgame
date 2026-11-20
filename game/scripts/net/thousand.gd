## Thousand (autoload): Thousand Town's shared state on the authority and what each device draws
## (design/thousand-town.md sections 2-4). Shaped like City (net/city.gd).
##
## The shared town clock {day, minute, mode, speed}:
##   - The first arrival starts it at day 1, 08:00 (minute 480), a Monday; not the real local time.
##   - After that it runs only while at least one child is in the town (Places.THOUSAND). An empty town
##     keeps its clock where it stopped; a new session (Session.town_reset, going offline) forgets it.
##   - Modes: "auto" runs MINUTES_PER_SECOND sim minutes per real second times `speed` (1, 2 or 4);
##     "day", "dusk" and "night" jump to 12:00, 18:40 and 21:30 (PRESETS) and hold there. Auto resumes from
##     the held time. Any child in the town may choose (srv_time_mode); the authority decides.
## Bus seats (srv_board_bus / srv_off_bus): a child reserves one of BUS_SEATS seats on bus `vehicle`; leaving
## the town frees it. The buses' motion comes later from core/thousand_clock.gd (W-SIM); this API stays.
##
## The solo device, the hosting device or the dedicated server is the authority. About once a second, and at
## once after every change, it sends the packed state to the peers whose recorded space is the town (a solo
## or host device applies it locally); an arriving peer gets it at once. Effects go reliably to the same peers.
## Clients never run the clock: they draw the newest state at the time estimated from it (est_clock()).
##
## Wire format (Float64): [WIRE, started, day, minute, mode index (MODES), speed, n, (peer, vehicle, seat) x n].
## Client form (`states`): {"started": bool, "day": int, "minute": float, "mode": String, "speed": int,
##   "riders": {peer: {"v": vehicle, "seat": seat}}}.
## Effects: "time" {"peer", "mode", "speed", "day", "minute"}; "bus" {"peer", "v", "seat"} (seat -1: got off).
extends Node

const Places := preload("res://scripts/core/places.gd")

const WIRE := 1.0
const MODES := ["auto", "day", "dusk", "night"]
## The held minute of each preset (12:00, 18:40, 21:30).
const PRESETS := {"day": 720.0, "dusk": 1120.0, "night": 1290.0}
const SPEEDS := [1, 2, 4]
const START_DAY := 1
const START_MINUTE := 480.0
const DAY_MINUTES := 1440.0
## Auto at 1x: one sim minute per real second (a 24-minute day; design section 4).
const MINUTES_PER_SECOND := 1.0
const SEND_EVERY := 1.0
## A longer stall than this is dropped, not replayed.
const MAX_DT := 0.25
## TODO(lead): the bus count and seats come from core/thousand_clock.gd / thousand_map.gd once they exist
## (upstream's station loop has 3 buses).
const BUSES := 3
const BUS_SEATS := 4
const EFFECT_KINDS := ["time", "bus"]

## The newest state (client form).
signal updated(states: Dictionary)
## A one-shot effect (see the header).
signal effect(kind: String, data: Dictionary)

var states: Dictionary = {}
## Authority: the clock ({} until the first arrival).
var clock: Dictionary = {}
## Authority: peer -> {"v": vehicle, "seat": seat}.
var seats: Dictionary = {}
var _send := 0.0
var _pkt_at := -1.0
var _est_floor := -1.0


func _ready() -> void:
	states = empty_state()
	Session.connection_changed.connect(func(s: String):
		if s != "online":
			_reset())
	Session.town_reset.connect(_reset)


static func empty_state() -> Dictionary:
	return {"started": false, "day": START_DAY, "minute": START_MINUTE, "mode": "auto", "speed": 1, "riders": {}}


static func fresh_clock() -> Dictionary:
	return {"day": START_DAY, "minute": START_MINUTE, "mode": "auto", "speed": 1}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _reset() -> void:
	clock = {}
	seats = {}
	_send = 0.0
	_pkt_at = -1.0
	_est_floor = -1.0
	states = empty_state()
	updated.emit(states)


# ------------------------------------------------------------- the clock (pure)

## Moves a clock on by `seconds` of real time (auto only; a preset holds). Day 1 is a Monday.
static func step_clock(c: Dictionary, seconds: float) -> Dictionary:
	var out := c.duplicate()
	if str(out["mode"]) != "auto" or seconds <= 0.0:
		return out
	var m := float(out["minute"]) + seconds * MINUTES_PER_SECOND * float(out["speed"])
	var d := int(out["day"])
	while m >= DAY_MINUTES:
		m -= DAY_MINUTES
		d += 1
	out["minute"] = m
	out["day"] = d
	return out


## A clock after a child chose `mode` (and, for auto, `speed`; 0 keeps the current speed).
static func apply_mode(c: Dictionary, mode: String, speed := 0) -> Dictionary:
	var out := c.duplicate()
	out["mode"] = mode
	if PRESETS.has(mode):
		out["minute"] = float(PRESETS[mode])
	elif speed in SPEEDS:
		out["speed"] = speed
	return out


## The speed after `speed` when Auto is pressed again: 1 -> 2 -> 4 -> 1.
static func next_speed(speed: int) -> int:
	var i := SPEEDS.find(speed)
	return int(SPEEDS[(i + 1) % SPEEDS.size()]) if i >= 0 else 1


## "08:00" for a minute of the day.
static func clock_text(minute: float) -> String:
	var m := int(floor(fposmod(minute, DAY_MINUTES)))
	return "%02d:%02d" % [m / 60, m % 60]


# ------------------------------------------------------------- who is in the town (pure)

## The peers whose recorded space is Thousand Town, in order.
static func in_map(players: Dictionary) -> Array:
	var out := []
	for p in players:
		if Places.map_of(str(players[p].get("state", {}).get("space", Places.TOWN))) == Places.THOUSAND:
			out.append(p)
	out.sort()
	return out


func in_town(players: Dictionary) -> Array:
	return in_map(players)


## The remote peers a message goes to: in the town and with an open connection.
func recipients(players: Dictionary, open: Array) -> Array:
	return in_map(players).filter(func(p): return open.has(p))


# ------------------------------------------------------------- the wire

static func pack_state(c: Dictionary, s: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array([WIRE, 0.0 if c.is_empty() else 1.0])
	var cc: Dictionary = fresh_clock() if c.is_empty() else c
	out.append_array([float(cc["day"]), float(cc["minute"]), float(MODES.find(str(cc["mode"]))), float(cc["speed"])])
	var peers := s.keys()
	peers.sort()
	out.append(float(peers.size()))
	for p in peers:
		out.append_array([float(p), float(s[p]["v"]), float(s[p]["seat"])])
	return out


## The client form of a packed state ({} when malformed or of another version).
static func decode(data: PackedFloat64Array) -> Dictionary:
	if data.size() < 7 or data[0] != WIRE:
		return {}
	var mode_i := int(data[4])
	var speed := int(data[5])
	var n := int(data[6])
	if mode_i < 0 or mode_i >= MODES.size() or not speed in SPEEDS or n < 0 or data.size() != 7 + n * 3:
		return {}
	var riders := {}
	for i in n:
		riders[int(data[7 + i * 3])] = {"v": int(data[8 + i * 3]), "seat": int(data[9 + i * 3])}
	return {"started": data[1] > 0.5, "day": int(data[2]), "minute": float(data[3]), "mode": MODES[mode_i], "speed": speed,
		"riders": riders}


func pack() -> PackedFloat64Array:
	return pack_state(clock, seats)


# ------------------------------------------------------------- the authority

## Authority: a player's space changed (a journey) or a player left. The first arrival starts the clock;
## a child who left the town gives up a bus seat; an arriving peer gets the newest state at once.
func on_space_changed(peer: int) -> void:
	if not Session.is_authority():
		return
	var here := in_town(Session.players)
	if clock.is_empty() and not here.is_empty():
		clock = fresh_clock()
		_send = SEND_EVERY
	var freed := false
	for p in seats.keys():
		if not here.has(p):
			seats.erase(p)
			freed = true
	if here.has(peer) or freed:
		_publish()


## Authority: a player left the town (a disconnect).
func peer_left(peer: int) -> void:
	seats.erase(peer)
	on_space_changed(peer)


func _physics_process(delta: float) -> void:
	if Session.is_authority() and Session.is_online():
		advance(delta)


## Authority: moves the clock on by `delta` seconds, only while someone is in the town (the physics loop
## calls this; tests do too).
func advance(delta: float) -> void:
	if clock.is_empty() or in_town(Session.players).is_empty():
		return
	clock = step_clock(clock, minf(delta, MAX_DT))
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		_publish()


func _local_in_town() -> bool:
	return Session.mode != "server" and in_town(Session.players).has(Session.my_id)


func _publish() -> void:
	var data := pack()
	if _local_in_town():
		_apply(data)
	for p in recipients(Session.players, Session._open_peers()):
		ev_thousand_state.rpc_id(p, data)


func _emit_effects(list: Array) -> void:
	for p in recipients(Session.players, Session._open_peers()):
		ev_thousand_effect.rpc_id(p, list)
	if _local_in_town():
		_play_effects(list)


# ------------------------------------------------------------- requests (the authority answers)

## Anyone in the town may choose the time: "auto" (speed 1, 2, 4, or 0 to keep it), "day", "dusk", "night".
func srv_time_mode(peer: int, mode: String, speed := 0) -> Dictionary:
	if not in_town(Session.players).has(peer) or clock.is_empty():
		return {"ok": false, "error": "Take the tram to Thousand Town first."}
	if not mode in MODES or not (speed == 0 or speed in SPEEDS):
		return {"ok": false, "error": "That does not work right now."}
	clock = apply_mode(clock, mode, speed)
	_emit_effects([["time", {"peer": peer, "mode": clock["mode"], "speed": clock["speed"], "day": clock["day"], "minute": clock["minute"]}]])
	_send = SEND_EVERY
	_publish()
	return {"ok": true, "mode": clock["mode"], "speed": clock["speed"], "day": clock["day"], "minute": clock["minute"]}


## A seat on bus `vehicle` (0 .. BUSES-1). Stub: the seat is reserved; where the bus is comes later.
func srv_board_bus(peer: int, vehicle: int) -> Dictionary:
	if not in_town(Session.players).has(peer) or clock.is_empty():
		return {"ok": false, "error": "Take the tram to Thousand Town first."}
	if vehicle < 0 or vehicle >= BUSES:
		return {"ok": false, "error": "That does not work right now."}
	if seats.has(peer):
		if int(seats[peer]["v"]) == vehicle:
			return {"ok": true, "v": vehicle, "seat": int(seats[peer]["seat"])}
		return {"ok": false, "reason": "riding", "error": "Get off the bus first."}
	var taken := []
	for p in seats:
		if int(seats[p]["v"]) == vehicle:
			taken.append(int(seats[p]["seat"]))
	for seat in BUS_SEATS:
		if not taken.has(seat):
			seats[peer] = {"v": vehicle, "seat": seat}
			_emit_effects([["bus", {"peer": peer, "v": vehicle, "seat": seat}]])
			_publish()
			return {"ok": true, "v": vehicle, "seat": seat}
	return {"ok": false, "reason": "full", "error": "That bus is full."}


func srv_off_bus(peer: int) -> Dictionary:
	if not seats.has(peer):
		return {"ok": false, "reason": "not_riding", "error": "You are not on a bus."}
	var v := int(seats[peer]["v"])
	seats.erase(peer)
	_emit_effects([["bus", {"peer": peer, "v": v, "seat": -1}]])
	_publish()
	return {"ok": true, "v": v}


# ------------------------------------------------------------- every device

@rpc("authority", "call_remote", "unreliable_ordered")
func ev_thousand_state(data: PackedFloat64Array) -> void:
	_apply(data)


@rpc("authority", "call_remote", "reliable")
func ev_thousand_effect(list: Array) -> void:
	_play_effects(list)


func _apply(data: PackedFloat64Array) -> void:
	var s := decode(data)
	if s.is_empty():
		push_warning("Thousand: a state of another version (or malformed) was ignored (%d values)" % data.size())
		return
	var was: Dictionary = states
	if str(s["mode"]) != str(was.get("mode", "")) or int(s["speed"]) != int(was.get("speed", 0)) \
			or _abs_minute(s) < _abs_minute(was) - 2.0:
		_est_floor = -1.0   # a new mode, speed or start: the estimate starts again from this packet
	_pkt_at = _now()
	states = s
	updated.emit(states)


static func _abs_minute(s: Dictionary) -> float:
	return float(int(s.get("day", START_DAY)) - 1) * DAY_MINUTES + float(s.get("minute", START_MINUTE))


## The town clock as this device estimates it: {"day", "minute", "mode", "speed"} from the newest state plus,
## in auto, the time since it arrived (never running backwards between two packets of one mode).
func est_clock() -> Dictionary:
	var base := {"day": int(states["day"]), "minute": float(states["minute"]), "mode": str(states["mode"]), "speed": int(states["speed"])}
	if _pkt_at < 0.0 or not bool(states["started"]) or base["mode"] != "auto":
		return base
	var est := step_clock(base, _now() - _pkt_at)
	var a := _abs_minute(est)
	if a < _est_floor:
		a = _est_floor
		est["day"] = int(a / DAY_MINUTES) + 1
		est["minute"] = fposmod(a, DAY_MINUTES)
	_est_floor = a
	return est


func _play_effects(list: Array) -> void:
	for item in list:
		if typeof(item) != TYPE_ARRAY or (item as Array).size() != 2 or typeof(item[1]) != TYPE_DICTIONARY:
			continue
		var kind := str(item[0])
		if kind in EFFECT_KINDS:
			effect.emit(kind, item[1])


# ------------------------------------------------------------- client convenience (through Session's request path)

## Choose the town's time: "auto" (speed 1, 2, 4; 0 keeps it), "day", "dusk" or "night".
func set_time_mode(mode: String, speed := 0) -> int:
	return Session.thousand_time(mode, speed)


func board_bus(vehicle: int) -> int:
	return Session.thousand_board(vehicle)


func off_bus() -> int:
	return Session.thousand_off()


## The bus a peer sits in, in the newest state (-1: none).
func riding(peer: int) -> int:
	return int((states["riders"] as Dictionary).get(peer, {}).get("v", -1))
