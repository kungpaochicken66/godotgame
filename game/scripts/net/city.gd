## City (autoload): the miniature city district's shared state on the authority and what each device draws
## (design/city-district.md "Playable rules"). Modelled on Zoo.
##
## The solo device, the hosting device or the dedicated server runs a CityRules.Rules only while at least
## one player is in the city: the first arrival wakes it, the last one leaving drops it (the state goes
## back to an empty shape). Every physics frame it ticks the rules with the children in the city; four
## times a second it sends the packed state to the peers whose recorded space is the city only (a solo or
## host device draws it locally), and an arriving peer gets the newest state at once. One-shot effects go
## reliably to the same peers. Clients never simulate: they draw the newest state at the time estimated
## from it.
##
## Wire format of a state: rules.pack() (Float64, see CityRules.Rules.pack) and nothing else.
## Client form (`states`): {"time", "ferris_angle" (gondola 0, CityRules convention),
##   "vehicles": [{"kind", "pos", "ry", "s", "v", "stopped", "dwell", "stop", "color"}], "occupancy": {key: peer},
##   "riders": {gondola: [peers]}, "weather" (index), "since", "prev" (Vector3), "ride": {peer: {"g", "seat", "t_board", "exit_at"}}}.
## weather_weights(states, t) works on it (aliases weather_since / weather_prev too).
## Effects: "weather" {"peer", "weather"}; "ride_off" {"peer", "pos": Vector2, "region", "gondola"}; "order" / "shop" {"peer", "key", "line", "prop"}.
##
## city-web (design/city-threejs.md section 6): the same script runs twice, as the autoloads City (the map
## "city", drawn by Godot) and CityWeb (the map "city_web", drawn by a web page). Each instance serves the map
## its node name says (`map`): only that map's children wake it, are ticked, hold its places and receive its
## states and effects. The RPCs are node-path based, so the two never mix.
extends Node

const CityRules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const Places := preload("res://scripts/core/places.gd")

const SEND_EVERY := 0.25
## A longer stall than this is dropped, not replayed.
const MAX_DT := 0.25
## A child holding a seat or machine who walks this far (m) beyond REACH from it stands up.
const HOLD_SLACK := 1.5
const EFFECT_KINDS := ["ride_off", "order", "shop", "weather"]

## The newest state (time = the authority's clock at that packet).
signal updated(states: Dictionary)
## A one-shot effect (see the header).
signal effect(kind: String, data: Dictionary)

## The map this instance serves (from its node name: CityWeb serves "city_web", anything else "city").
var map := Places.CITY
var states: Dictionary = {}
var rules                          # authority only: CityRules.Rules while a player is in the city
var _send := 0.0
var _pkt_time := 0.0
var _pkt_at := -1.0
var _est_floor := 0.0


func _enter_tree() -> void:
	map = map_for_name(String(name))


## The map a City node of this name serves.
static func map_for_name(node_name: String) -> String:
	return Places.CITY_WEB if node_name.to_lower() == "cityweb" else Places.CITY


func _ready() -> void:
	states = empty_state()
	Session.connection_changed.connect(func(s: String):
		if s != "online":
			_reset())
	Session.town_reset.connect(_reset)


static func empty_state() -> Dictionary:
	return {"time": 0.0, "ferris_angle": 0.0, "vehicles": [], "occupancy": {}, "riders": {}, "ride": {},
		"weather": 0, "since": -float(CityMap.WEATHER_BLEND), "prev": Vector3(1.0, 0.0, 0.0),
		"weather_since": -float(CityMap.WEATHER_BLEND), "weather_prev": Vector3(1.0, 0.0, 0.0)}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _reset() -> void:
	rules = null
	_send = 0.0
	_pkt_at = -1.0
	_pkt_time = 0.0
	_est_floor = 0.0
	states = empty_state()
	updated.emit(states)


# ------------------------------------------------------------- who is in the city (pure)

## The peers whose recorded space is the city map `m`, in order.
static func in_map(players: Dictionary, m: String) -> Array:
	var out := []
	for p in players:
		if Places.map_of(str(players[p].get("state", {}).get("space", Places.TOWN))) == m:
			out.append(p)
	out.sort()
	return out


## The peers whose recorded space is this instance's city map, in order.
func in_city(players: Dictionary) -> Array:
	return in_map(players, map)


## The remote peers a city message goes to: in this city map and with an open connection.
func recipients(players: Dictionary, open: Array) -> Array:
	return in_city(players).filter(func(p): return open.has(p))


## The state in the client form, from a packed one ({} when malformed).
static func decode(data: PackedFloat64Array) -> Dictionary:
	var u := CityRules.unpack(data)
	if not u["ok"]:
		return {}
	var t: float = u["time"]
	var out := empty_state()
	out["time"] = t
	out["ferris_angle"] = CityRules.gondola_angle(0, t)
	var list: Array = []
	for i in (u["vehicles"] as Array).size():
		var v: Dictionary = u["vehicles"][i]
		var p := CityRules.vehicle_pose(i, float(v["s"]))
		p["s"] = float(v["s"])
		p["v"] = float(v["v"])
		p["stopped"] = float(v["v"]) < 0.01
		p["stop"] = int(v.get("stop", -1))   # a bus's next stop (index into CityRules.stop_arcs()), -1 for a car
		p["dwell"] = float(v.get("dwell", 0.0))   # seconds still to wait at a bus stop (0: not waiting)
		p["color"] = (CityMap.VEHICLES[i] as Dictionary).get("color", Color.WHITE)
		list.append(p)
	out["vehicles"] = list
	out["occupancy"] = (u["occupancy"] as Dictionary).duplicate()
	var by_g: Dictionary = {}
	for peer: int in u["riders"]:
		var r: Dictionary = u["riders"][peer]
		var g := int(r["g"])
		if not by_g.has(g):
			by_g[g] = []
		(by_g[g] as Array).append(peer)
	for g in by_g:
		(by_g[g] as Array).sort()
	out["riders"] = by_g
	out["ride"] = (u["riders"] as Dictionary).duplicate(true)
	var wst: Dictionary = u["weather"]
	out["weather"] = int(wst["weather"])
	out["since"] = float(wst["since"])
	out["prev"] = wst["prev"]
	out["weather_since"] = out["since"]
	out["weather_prev"] = out["prev"]
	return out


# ------------------------------------------------------------- the authority

## Authority: a player's space changed (a journey) or a player left. Wakes the city with its first
## visitor, drops it when empty, frees what a departed child held and gives an arriving peer the
## newest state at once.
func on_space_changed(peer: int) -> void:
	if not Session.is_authority():
		return
	_sync_awake()
	if rules != null and in_city(Session.players).has(peer):
		_send_to(peer, rules.pack())


## Authority: a player left the town (a disconnect).
func peer_left(peer: int) -> void:
	if rules != null:
		rules.leave(peer)
	on_space_changed(peer)
	if rules != null:
		_publish()


func _sync_awake() -> void:
	var here := in_city(Session.players)
	if not here.is_empty() and rules == null:
		rules = CityRules.new()
		_send = SEND_EVERY
	elif here.is_empty() and rules != null:
		_reset()   # asleep: the state goes back to an empty shape
		return
	if rules != null:
		for peer: int in _members():
			if not here.has(peer):
				rules.leave(peer)   # travelled away or disconnected: the place is free at once


func _members() -> Array:
	var out: Array = (rules.occupancy.values() as Array).duplicate()
	for peer: int in rules.riders:
		if not out.has(peer):
			out.append(peer)
	return out


func _physics_process(delta: float) -> void:
	if Session.is_authority() and Session.is_online():
		advance(delta)


## Authority: moves the city on by `delta` seconds (the physics loop calls this; tests do too).
func advance(delta: float) -> void:
	_sync_awake()
	if rules == null:
		return
	delta = minf(delta, MAX_DT)
	var kids := kid_inputs()
	var exits: Array = rules.tick(delta, kids)
	_stand_up_walkers(kids)
	var list: Array = []
	for e: Dictionary in exits:
		list.append(["ride_off", {"peer": int(e["peer"]), "pos": e["pos"], "region": str(e["region"]), "gondola": int(e["gondola"])}])
	if not list.is_empty():
		_emit_effects(list)
		_publish()
	_send -= delta
	if _send <= 0.0:
		_send = SEND_EVERY
		_publish()


## What the rules are told: [{"id", "pos", "region"}] for each child in the city.
func kid_inputs() -> Array:
	var out := []
	for peer in in_city(Session.players):
		var st: Dictionary = Session.players[peer].get("state", {})
		out.append({"id": peer, "pos": Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))), "region": str(st.get("level", ""))})
	return out


## A child who has walked away from the seat or machine they hold stands up (a client that forgot to say so).
func _stand_up_walkers(kids: Array) -> void:
	var changed := false
	for k: Dictionary in kids:
		var peer: int = k["id"]
		var key: String = rules.held(peer)
		if key == "":
			continue
		var it: Dictionary = CityMap.INTERACTIONS[key]
		var region := "" if str(it["region"]) == "ground" else str(it["region"])
		if region != str(k["region"]) or (k["pos"] as Vector2).distance_to(it["pos"]) > CityMap.REACH + HOLD_SLACK:
			rules.release(peer)
			changed = true
	if changed:
		_publish()


func _local_in_city() -> bool:
	return Session.mode != "server" and in_city(Session.players).has(Session.my_id)


func _publish() -> void:
	var data: PackedFloat64Array = rules.pack()
	if _local_in_city():
		_apply(data)
	for p in recipients(Session.players, Session._open_peers()):
		ev_city_state.rpc_id(p, data)


func _send_to(peer: int, data: PackedFloat64Array) -> void:
	if peer == Session.my_id and Session.mode != "server":
		_apply(data)
	elif Session._open_peers().has(peer):
		ev_city_state.rpc_id(peer, data)


func _emit_effects(list: Array) -> void:
	for p in recipients(Session.players, Session._open_peers()):
		ev_city_effect.rpc_id(p, list)
	if _local_in_city():
		_play_effects(list)


# ------------------------------------------------------------- requests (the authority answers)

## The kind sentence for a refusal; short and kind.
static func refusal(reason: String, key := "") -> String:
	match reason:
		"busy":
			var kind := str((CityMap.INTERACTIONS.get(key, {}) as Dictionary).get("kind", ""))
			return "Someone is sitting there." if kind == "seat" else "Someone is using that."
		"far":
			return "Walk closer first."
		"level":
			return "Go to the right floor first."
		"riding":
			return "Finish your ride first."
		"wait":
			return "Wait for a gondola at the bottom."
		"full":
			return "That gondola is full."
		"not_riding":
			return "You are not on the wheel."
	return "That does not work right now."


func _ready_rules() -> bool:
	_sync_awake()
	return rules != null


func srv_use(peer: int, level: String, pos: Vector2, key: String) -> Dictionary:
	if not _ready_rules():
		return {"ok": false, "error": "Take the tram to the city first."}
	var r: Dictionary = rules.use(peer, key, level, pos)
	if not r.get("ok", false):
		return {"ok": false, "reason": str(r.get("reason", "")), "error": refusal(str(r.get("reason", "")), key)}
	var kind := str(r.get("kind", ""))
	if kind == "order" or kind == "shop":
		_emit_effects([[kind, {"peer": peer, "key": key, "line": str(r.get("line", "")), "prop": str(r.get("prop", ""))}]])
	_publish()
	return r


func srv_board(peer: int, level: String, pos: Vector2) -> Dictionary:
	if not _ready_rules():
		return {"ok": false, "error": "Take the tram to the city first."}
	var r: Dictionary = rules.board(peer, rules.time, level, pos)
	if not r.get("ok", false):
		return {"ok": false, "reason": str(r.get("reason", "")), "error": refusal(str(r.get("reason", "")))}
	_publish()
	return r


func srv_off(peer: int, _level: String, _pos: Vector2) -> Dictionary:
	if not _ready_rules():
		return {"ok": false, "error": "Take the tram to the city first."}
	var r: Dictionary = rules.request_off(peer, rules.time)
	if not r.get("ok", false):
		return {"ok": false, "reason": str(r.get("reason", "")), "error": refusal(str(r.get("reason", "")))}
	r["wait"] = maxf(0.0, float(r["exit_at"]) - rules.time)   # seconds until the gondola is back at the bottom
	_publish()
	return r


## Anyone in the city may choose the weather (w is an index of CityMap.WEATHERS); everyone in the city sees it.
func srv_weather(peer: int, _level: String, _pos: Vector2, w: int) -> Dictionary:
	if not in_city(Session.players).has(peer):
		return {"ok": false, "error": "Take the tram to the city first."}
	if not _ready_rules():
		return {"ok": false, "error": "Take the tram to the city first."}
	if w < 0 or w >= (CityMap.WEATHERS as Array).size():
		return {"ok": false, "error": "The city does not have that weather."}
	rules.set_weather(w)
	_emit_effects([["weather", {"peer": peer, "weather": w}]])
	_publish()
	return {"ok": true, "weather": w}


func srv_release(peer: int, _level: String, _pos: Vector2) -> Dictionary:
	if not _ready_rules():
		return {"ok": false, "error": "Take the tram to the city first."}
	var key: String = rules.release(peer)
	if key != "":
		_publish()
	return {"ok": true, "key": key}


# ------------------------------------------------------------- every device

@rpc("authority", "call_remote", "unreliable_ordered")
func ev_city_state(data: PackedFloat64Array) -> void:
	_apply(data)


@rpc("authority", "call_remote", "reliable")
func ev_city_effect(list: Array) -> void:
	_play_effects(list)


func _apply(data: PackedFloat64Array) -> void:
	var s := decode(data)
	if s.is_empty():
		push_warning("City: a state of another version (or malformed) was ignored (%d values)" % data.size())
		return   # not a whole state of this version's city
	if float(s["time"]) < _pkt_time - 0.5:
		_est_floor = 0.0   # the city woke up afresh: its clock started again
	_pkt_time = float(s["time"])
	_pkt_at = _now()
	states = s
	updated.emit(states)


## The city's clock as this device estimates it: the newest packet's time plus the time since it
## arrived (never running backwards between two packets).
func est_time() -> float:
	if _pkt_at < 0.0:
		return 0.0
	_est_floor = maxf(_est_floor, _pkt_time + (_now() - _pkt_at))
	return _est_floor


func _play_effects(list: Array) -> void:
	for item in list:
		if typeof(item) != TYPE_ARRAY or (item as Array).size() != 2 or typeof(item[1]) != TYPE_DICTIONARY:
			continue
		var kind := str(item[0])
		if kind in EFFECT_KINDS:
			effect.emit(kind, item[1])


# ------------------------------------------------------------- client convenience

func use(key: String) -> int:
	return Session.city_use(key)


func board() -> int:
	return Session.city_board()


func off() -> int:
	return Session.city_off()


func release() -> int:
	return Session.city_release()


## Choose the city's weather (an index of CityMap.WEATHERS).
func set_weather(w: int) -> int:
	return Session.city_weather(w)


## The weather mix {"sunny", "rain", "night"} now, from the newest state at the estimated clock
## (the same on every device up to the clock estimate).
func weights() -> Dictionary:
	return CityRules.weather_weights(states, est_time())


## Who holds an interaction in the newest state (-1: nobody).
func occupant(key: String) -> int:
	return int((states["occupancy"] as Dictionary).get(key, -1))


## The gondola a peer rides in the newest state (-1: not riding).
func riding(peer: int) -> int:
	var by_g: Dictionary = states["riders"]
	for g in by_g:
		if (by_g[g] as Array).has(peer):
			return int(g)
	return -1
