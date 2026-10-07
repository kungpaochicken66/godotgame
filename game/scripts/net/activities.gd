## Activities (autoload): the optional games of design/playfulness-proposals.md
## that need a referee. Animal wishes (A), hide-and-seek (B), the dance parade (E)
## and the in-session garden growth tick (D) run on the authority; clients only
## send requests and draw the shared state. Presents (C), hearts and visits (F),
## photo ideas (G) and weather (H) are plain town edits handled by Session.
##
## Nothing here can gate the toy box, cost anything or punish waiting.
extends Node

const Wishes := preload("res://scripts/core/wishes.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const HideSeek := preload("res://scripts/core/hide_seek.gd")

const PARTY_SECONDS := 30.0
const HINT_AFTER := 180.0
const FIND_DISTANCE := 2.5
const SHOW_ACORN_WITHIN := 2.0
const GROW_EVERY := 60.0

signal wish_done(animal: String, wish_id: String, at: Vector2, by: Array)
signal hs_changed()                      # hide-and-seek public state changed
signal warmth_changed(level: int, acorn: Dictionary)
signal hs_found(nick: String)
signal hs_ended(reason: String)
signal party_changed(active: bool)
signal message(text: String)             # replies such as "already going"

## Public hide-and-seek state, the same on every device:
## {"phase": "none"|"hiding"|"seeking", "hider": peer (0 = an animal), "hider_nick", "started", "hint", "acorn"}
## "acorn" ({space, x, z}) is only filled once the gentle hint is on.
var hs := {"phase": "none"}
var warmth := 0
var near_acorn := {}                     # the acorn, revealed only when this child is close
var party_left := 0.0

var _secret := {}                        # authority: where the acorn really is
var _wish_wait := 0.0
var _grow_wait := 0.0
var _warm_wait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Session.town_changed.connect(_check_wish)
	Session.player_joined_authority.connect(_sync_late_joiner)
	Session.connection_changed.connect(func(s):
		if s != "online":
			_reset())
	Session.town_reset.connect(func():
		if Session.is_authority():
			_reset())
	multiplayer.peer_disconnected.connect(_on_peer_left)


func _reset() -> void:
	hs = {"phase": "none"}
	_secret = {}
	warmth = 0
	near_acorn = {}
	party_left = 0.0
	_wish_wait = 0.0
	hs_changed.emit()
	party_changed.emit(false)


func is_party() -> bool:
	return party_left > 0.0


# ------------------------------------------------------------- client API

func start_hide_and_seek() -> void:
	_send("hs", "start")


func hide_here() -> void:
	_send("hs", "hide")


func find_acorn() -> void:
	_send("hs", "find")


func stop_hide_and_seek() -> void:
	_send("hs", "stop")


func start_party() -> void:
	_send("party", "start")


func stop_party() -> void:
	_send("party", "stop")


func _send(game: String, action: String) -> void:
	if Session.is_authority():
		_srv(Session.my_id, game, action)
	elif Session.is_online():
		rq_activity.rpc_id(1, game, action)


@rpc("any_peer", "call_remote", "reliable")
func rq_activity(game: String, action: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if Session.is_authority() and Session.players.has(peer) and game in ["hs", "party"]:
		_srv(peer, game, action)


func _tell(peer: int, text: String) -> void:
	if peer == Session.my_id and Session.mode != "server":
		message.emit(text)
	elif multiplayer.get_peers().has(peer):
		ev_message.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func ev_message(text: String) -> void:
	message.emit(text)


# ------------------------------------------------------------- authority

func _srv(peer: int, game: String, action: String) -> void:
	if game == "party":
		if action == "start":
			if party_left > 0.0:
				_tell(peer, "The party is on. Dance along!")   # a second start simply joins in
			else:
				_set_party(PARTY_SECONDS)
		elif action == "stop":
			_set_party(0.0)
		return
	match action:
		"start":
			if hs["phase"] != "none":
				_tell(peer, "A game of hide-and-seek is already going. Join in!")
				return
			if Session.players.size() <= 1:
				_animal_hides(peer)
			else:
				hs = {"phase": "hiding", "hider": peer, "hider_nick": Session.nick_of(peer), "started": _now(), "hint": false}
				_publish()
		"hide":
			if hs["phase"] != "hiding" or hs.get("hider") != peer:
				return
			var st: Dictionary = Session.players[peer]["state"]
			_secret = {"space": st.get("space", "town"), "x": float(st.get("x", 0.0)), "z": float(st.get("z", 0.0))}
			hs["phase"] = "seeking"
			hs["started"] = _now()
			_publish()
		"find":
			if hs["phase"] != "seeking" or peer == hs.get("hider") or _secret.is_empty():
				return
			var st: Dictionary = Session.players[peer]["state"]
			if st.get("space", "town") == _secret["space"] and Vector2(st.get("x", 0.0), st.get("z", 0.0)).distance_to(Vector2(_secret["x"], _secret["z"])) <= FIND_DISTANCE:
				var nick := Session.nick_of(peer)
				_end("found")
				ev_hs_found.rpc(nick, peer)
		"stop":
			if hs["phase"] != "none":
				_end("stopped")


## Alone in town: an animal friend hides the acorn somewhere outdoors.
func _animal_hides(peer: int) -> void:
	var st: Dictionary = Session.players[peer]["state"]
	var me := Vector2(st.get("x", 0.0), st.get("z", 0.0))
	var spot = null
	for attempt in 20:
		var d := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(9.0, 16.0)
		spot = Session.model.find_free_spot("chair", "town", me + d)
		if spot != null:
			break
	if spot == null:
		spot = TownModel.TOWN_SPAWN
	_secret = {"space": "town", "x": spot.x, "z": spot.y}
	var hider: String = ["Tumble", "Bramble", "Biscuit"][_rng.randi() % 3]
	hs = {"phase": "seeking", "hider": 0, "hider_nick": hider, "started": _now(), "hint": false}
	_publish()


func _end(reason: String) -> void:
	hs = {"phase": "none"}
	_secret = {}
	ev_hs.rpc(hs, reason)


func _publish() -> void:
	ev_hs.rpc(hs, "")


func _on_peer_left(peer: int) -> void:
	if Session.is_authority() and hs["phase"] != "none" and hs.get("hider") == peer:
		_end("hider_left")


func _set_party(seconds: float) -> void:
	var brain = Animals.brain
	if brain:
		if seconds > 0.0:
			brain.start_parade(seconds)
		else:
			brain.stop_parade()
	ev_party.rpc(seconds)


func _sync_late_joiner(peer: int) -> void:
	if peer == Session.my_id and Session.mode != "server":
		return
	ev_hs.rpc_id(peer, hs, "")
	if party_left > 0.0:
		ev_party.rpc_id(peer, party_left)


func _check_wish() -> void:
	var active: Dictionary = Session.model.wishes.get("active", {})
	if active.is_empty():
		return
	var at = Wishes.met_at(Session.model, active.get("id", ""))
	if at == null:
		return
	var names: Array = Session.players.values().map(func(p): return p["avatar"]["nick"])
	Session.model.wishes["stickers"].append({"animal": active["animal"], "id": active["id"], "by": names, "t": int(Time.get_unix_time_from_system())})
	Session.model.wishes["active"] = {}
	_wish_wait = 0.0
	Session.share("wishes")
	if Animals.brain:
		Animals.brain.celebrate(active["animal"], at, Session.model)
	ev_wish_done.rpc(active["animal"], active["id"], at, names)
	# Sometimes the happy animal leaves a little present for anyone (activity C, solo flavor).
	if _rng.randf() < 0.5:
		_animal_present(active["animal"], at)


func _animal_present(animal: String, at: Vector2) -> void:
	var gifts := {"pig": "flowers", "rabbit": "plant", "sheep": "lamp_post", "dog": "bench", "elephant": "tree"}
	var kind: String = gifts.get(animal, "flowers")
	var spot = Session.model.find_free_spot(kind, "town", at + Vector2(1.5, 1.5))
	if spot == null:
		return
	var placed: Dictionary = Session.model.place(kind, "town", spot.x, spot.y, 0)
	if not placed.get("ok", false):
		return
	var name: String = AnimalBrain.SPECIES[animal]["name"]
	var w: Dictionary = Session.model.wrap(placed["item"]["id"], "animal:" + animal, name, "", _rng.randi_range(0, 7))
	if not w.get("ok", false):
		Session.model.remove(placed["item"]["id"])
		return
	Session.ev_item.rpc(w["item"])
	Session._mark_dirty()


func _process(delta: float) -> void:
	if party_left > 0.0:
		party_left = maxf(0.0, party_left - delta)
		if party_left == 0.0:
			party_changed.emit(false)
	if not Session.is_authority() or not Session.is_online() or Session.players.is_empty():
		return
	# Animal wishes: a new one after a while of play; nothing ever expires.
	if Session.model.wishes.get("active", {}).is_empty():
		_wish_wait += delta
		var wait: float = Wishes.FIRST_WISH_AFTER if Session.model.wishes["stickers"].is_empty() else Wishes.NEXT_WISH_AFTER
		if _wish_wait >= wait:
			_wish_wait = 0.0
			var w := Wishes.pick(Session.model, _rng)
			if not w.is_empty():
				Session.model.wishes["active"] = w
				Session.share("wishes")
	# Gardens grow while children play outdoors.
	if Session.players.values().any(func(p): return p["state"].get("space", "town") == "town"):
		_grow_wait += delta
		if _grow_wait >= GROW_EVERY:
			_grow_wait = 0.0
			Session.grow_all()
	# Hide-and-seek: warmth for every seeker, and a gentle hint after a while.
	if hs["phase"] == "seeking" and not _secret.is_empty():
		_warm_wait -= delta
		if _warm_wait <= 0.0:
			_warm_wait = 0.4
			_send_warmth()
		if not hs.get("hint", false) and _now() - float(hs.get("started", 0.0)) > HINT_AFTER:
			hs["hint"] = true
			hs["acorn"] = _secret.duplicate()
			_publish()


func _send_warmth() -> void:
	for peer in Session.players:
		if peer == hs.get("hider"):
			continue
		var st: Dictionary = Session.players[peer]["state"]
		var level := HideSeek.warmth_level(st, _secret)
		var reveal := {}
		if st.get("space", "town") == _secret["space"] and Vector2(st.get("x", 0.0), st.get("z", 0.0)).distance_to(Vector2(_secret["x"], _secret["z"])) <= SHOW_ACORN_WITHIN:
			reveal = _secret.duplicate()
		if peer == Session.my_id and Session.mode != "server":
			_apply_warmth(level, reveal)
		elif multiplayer.get_peers().has(peer):
			ev_warmth.rpc_id(peer, level, reveal)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------- authority -> clients

@rpc("authority", "call_local", "reliable")
func ev_hs(state: Dictionary, reason: String) -> void:
	hs = state
	if hs.get("phase", "none") == "none":
		warmth = 0
		near_acorn = {}
		if reason != "":
			hs_ended.emit(reason)
	hs_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func ev_warmth(level: int, reveal: Dictionary) -> void:
	_apply_warmth(level, reveal)


func _apply_warmth(level: int, reveal: Dictionary) -> void:
	warmth = level
	near_acorn = reveal
	warmth_changed.emit(level, reveal)


@rpc("authority", "call_local", "reliable")
func ev_hs_found(nick: String, peer: int) -> void:
	hs_found.emit(nick)
	Session.emote.emit(peer, "cheer")


@rpc("authority", "call_local", "reliable")
func ev_party(seconds: float) -> void:
	party_left = seconds
	party_changed.emit(seconds > 0.0)


@rpc("authority", "call_local", "reliable")
func ev_wish_done(animal: String, wish_id: String, at: Vector2, by: Array) -> void:
	wish_done.emit(animal, wish_id, at, by)
