## Session (autoload): the shared town, the players in it and all networking.
##
## One authority owns the TownModel: the dedicated server, the hosting device,
## or this device in solo play (Godot's OfflineMultiplayerPeer reports itself as
## the server). Clients only send requests; the authority validates, applies,
## saves and broadcasts. Every peer keeps a mirror of the model for rendering.
extends Node

const TownModel := preload("res://scripts/core/town_model.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

## 2: three-story houses with rooms ("<house>:<floor>:<room>" spaces) and a larger town.
## 3: tabletop decorations ("host" on items, place/move carry a host id).
const PROTOCOL := 3
const MAX_PLAYERS := 4
const DEFAULT_PORT := 9080
const SAVE_DELAY := 1.5
const JOIN_TIMEOUT := 10.0

signal connection_changed(state: String)      # offline, connecting, online, failed, disconnected
signal joined(peer_id: int)
signal rejected(reason: String)
signal town_reset()
signal item_changed(item: Dictionary)
signal items_removed(ids: Array)
signal players_changed()
signal player_state(peer_id: int, state: Dictionary)
signal emote(peer_id: int, kind: String)
signal lock_changed(item_id: String, peer_id: int)
signal seats_changed()
signal lantern_lit(spot: String, by: Array)
signal evening_changed(on: bool)
signal saved(ok: bool)
signal request_failed(error: String)
signal request_done(req: int, result: Dictionary)

var model = TownModel.new()
var players := {}        # peer id -> {"avatar": {...}, "state": {...}}
var locks := {}          # item id -> peer id
var seats := {}          # item id -> {seat index: peer id}
var mode := "none"       # none, solo, host, client, server
var state := "offline"
var save_path := ""
var my_id := 0
var my_avatar := {}
var last_save_ok := true
var dirty := false

var _save_timer := 0.0
var _pending := {}       # peer id -> seconds since connect without joining
var _req_counter := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not is_authority():
		return
	if dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_now()
	for peer in _pending.keys():
		_pending[peer] += delta
		if _pending[peer] > JOIN_TIMEOUT:
			_pending.erase(peer)
			_kick(peer)


func is_authority() -> bool:
	return mode in ["solo", "host", "server"]


func is_online() -> bool:
	return state == "online"


# ------------------------------------------------------------- starting

func start_solo(path: String, avatar: Dictionary) -> void:
	_reset_peer()
	mode = "solo"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_load_town(path)
	_set_state("online")
	_srv_join(1, Avatar.sanitize(avatar), PROTOCOL)


## Listens for friends and plays on this device (LAN or forwarded port).
func start_host(path: String, avatar: Dictionary, port := DEFAULT_PORT) -> int:
	_reset_peer()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		_set_state("failed")
		return err
	mode = "host"
	multiplayer.multiplayer_peer = peer
	_load_town(path)
	_set_state("online")
	_srv_join(1, Avatar.sanitize(avatar), PROTOCOL)
	return OK


## Headless dedicated town server; no local player.
func start_server(path: String, port := DEFAULT_PORT, bind := "*") -> int:
	_reset_peer()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, bind)
	if err != OK:
		return err
	mode = "server"
	multiplayer.multiplayer_peer = peer
	_load_town(path)
	_set_state("online")
	print("[server] Lantern Lane town server listening on %s:%d, save: %s" % [bind, port, path])
	return OK


func join(url: String, avatar: Dictionary) -> int:
	_reset_peer()
	mode = "client"
	my_avatar = Avatar.sanitize(avatar)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		_set_state("failed")
		return err
	multiplayer.multiplayer_peer = peer
	_set_state("connecting")
	return OK


func leave() -> void:
	if is_authority() and dirty:
		save_now()
	_reset_peer()
	mode = "none"
	_set_state("offline")


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	locks.clear()
	seats.clear()
	_pending.clear()
	my_id = 0
	model = TownModel.new()


func _set_state(s: String) -> void:
	state = s
	connection_changed.emit(s)


# ------------------------------------------------------------- persistence

func _load_town(path: String) -> void:
	save_path = path
	model = null
	for candidate in [path, path + ".bak"]:
		if FileAccess.file_exists(candidate):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(candidate))
			var m = TownModel.new()
			if typeof(parsed) == TYPE_DICTIONARY and m.from_dict(parsed):
				model = m
				if not m.last_migration.is_empty():
					# Keep the untouched old save once, then write the new format soon.
					if not FileAccess.file_exists(path + ".v1"):
						DirAccess.copy_absolute(candidate, path + ".v1")
					dirty = true
					print("Town save migrated: %s (original kept as %s.v1)" % [m.last_migration, path.get_file()])
				break
			push_warning("Could not read town save %s" % candidate)
	if model == null:
		model = TownModel.make_default()
		dirty = true
	town_reset.emit()
	evening_changed.emit(model.evening)


## Atomic save: write a temp file, keep the previous save as .bak, then rename.
func save_now() -> bool:
	dirty = false
	if save_path == "":
		return false
	var dir := save_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	var ok := f != null
	if ok:
		f.store_string(JSON.stringify(model.to_dict(), "\t"))
		f.close()
		if FileAccess.file_exists(save_path):
			DirAccess.copy_absolute(save_path, save_path + ".bak")
		ok = DirAccess.rename_absolute(tmp, save_path) == OK
	if not ok:
		dirty = true
		_save_timer = SAVE_DELAY * 4
	last_save_ok = ok
	ev_saved.rpc(ok)
	return ok


func _mark_dirty() -> void:
	dirty = true
	_save_timer = SAVE_DELAY


# ------------------------------------------------------------- connection events

func _on_peer_connected(peer: int) -> void:
	if is_authority():
		_pending[peer] = 0.0
	elif mode == "client" and peer == 1:
		pass


func _on_peer_disconnected(peer: int) -> void:
	if not is_authority():
		return
	_pending.erase(peer)
	if not players.has(peer):
		return
	players.erase(peer)
	for item_id in locks.keys():
		if locks[item_id] == peer:
			locks.erase(item_id)
			ev_lock.rpc(item_id, 0)
	_free_seats_of(peer)
	ev_player_left.rpc(peer)
	print("[server] peer %d left, %d playing" % [peer, players.size()])


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	rq_join.rpc_id(1, my_avatar, PROTOCOL)


func _on_connection_failed() -> void:
	_set_state("failed")


func _on_server_disconnected() -> void:
	players.clear()
	locks.clear()
	seats.clear()
	_set_state("disconnected")
	players_changed.emit()


func _kick(peer: int) -> void:
	if multiplayer.multiplayer_peer and peer != 1:
		multiplayer.multiplayer_peer.disconnect_peer(peer)


# ------------------------------------------------------------- client API
# Each call reaches the authority directly (solo/host) or by RPC (client).

func _ask(method: String, args: Array) -> int:
	_req_counter += 1
	var req := _req_counter
	if is_authority():
		callv("_srv_" + method, [my_id, req] + args)
	elif is_online():
		rq_action.rpc_id(1, method, req, args)
	else:
		request_failed.emit("Decorating is paused until we reconnect.")
		return -1
	return req


func place(kind: String, space: String, pos: Vector2, rot: int, color: int, host := "") -> int:
	return _ask("place", [kind, space, pos.x, pos.y, rot, color, host])


func move(id: String, pos: Vector2, rot: int, host := "") -> int:
	return _ask("move", [id, pos.x, pos.y, rot, host])


func paint(id: String, color: int) -> int:
	return _ask("paint", [id, color])


func remove(id: String) -> int:
	return _ask("remove", [id])


func restore(entries: Array) -> int:
	return _ask("restore", [entries])


func lock(id: String) -> int:
	return _ask("lock", [id])


func unlock(id: String) -> int:
	return _ask("unlock", [id])


func sit(id: String) -> int:
	return _ask("sit", [id])


func stand() -> int:
	return _ask("stand", [])


func ring_bell() -> int:
	return _ask("bell", [])


func send_state(s: Dictionary) -> void:
	if is_authority():
		_srv_state(my_id, s)
	elif is_online():
		rq_state.rpc_id(1, s)


func send_emote(kind: String) -> void:
	if not Avatar.EMOTES.has(kind):
		return
	if is_authority():
		_srv_emote(my_id, kind)
	elif is_online():
		rq_emote.rpc_id(1, kind)


func nick_of(peer: int) -> String:
	return players.get(peer, {}).get("avatar", {}).get("nick", "")


func lock_holder(item_id: String) -> int:
	return locks.get(item_id, 0)


func seat_holders(item_id: String) -> Dictionary:
	return seats.get(item_id, {})


func seat_of(peer: int) -> Array:
	for item_id in seats:
		for s in seats[item_id]:
			if seats[item_id][s] == peer:
				return [item_id, s]
	return []


# ------------------------------------------------------------- RPC: client -> authority

@rpc("any_peer", "call_remote", "reliable")
func rq_join(avatar: Dictionary, protocol: int) -> void:
	if is_authority():
		_srv_join(multiplayer.get_remote_sender_id(), Avatar.sanitize(avatar), protocol)


@rpc("any_peer", "call_remote", "reliable")
func rq_action(method: String, req: int, args: Array) -> void:
	if not is_authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not players.has(peer):
		return
	if not method in ["place", "move", "paint", "remove", "restore", "lock", "unlock", "sit", "stand", "bell"]:
		return
	var expected := {"place": 7, "move": 5, "paint": 2, "remove": 1, "restore": 1, "lock": 1, "unlock": 1, "sit": 1, "stand": 0, "bell": 0}
	if args.size() != expected[method]:
		return
	callv("_srv_" + method, [peer, req] + args)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rq_state(s: Dictionary) -> void:
	if is_authority() and players.has(multiplayer.get_remote_sender_id()):
		_srv_state(multiplayer.get_remote_sender_id(), s)


@rpc("any_peer", "call_remote", "reliable")
func rq_emote(kind: String) -> void:
	if is_authority() and players.has(multiplayer.get_remote_sender_id()) and Avatar.EMOTES.has(kind):
		_srv_emote(multiplayer.get_remote_sender_id(), kind)


# ------------------------------------------------------------- authority logic

func _reply(peer: int, req: int, result: Dictionary) -> void:
	if peer == my_id and mode != "server":
		# Deliver after the caller has registered its callback, like a network reply.
		_on_result.call_deferred(req, result)
	elif peer != 0 and multiplayer.get_peers().has(peer):
		ev_result.rpc_id(peer, req, result)


func _srv_join(peer: int, avatar: Dictionary, protocol: int) -> void:
	_pending.erase(peer)
	if protocol != PROTOCOL:
		_reject(peer, "Please update the app to play together.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject(peer, "The town is full right now")
		return
	players[peer] = {"avatar": avatar, "state": _spawn_state()}
	if peer == 1 and mode != "server":
		my_id = 1
		my_avatar = avatar
		_after_welcome()
	else:
		ev_welcome.rpc_id(peer, peer, model.to_dict(), _players_snapshot(), locks, _seats_snapshot())
		ev_player_joined.rpc(peer, avatar, players[peer]["state"])
	if mode == "server":
		print("[server] %s joined as peer %d, %d playing" % [avatar["nick"], peer, players.size()])


func _reject(peer: int, reason: String) -> void:
	if peer == 1 and mode != "server":
		rejected.emit(reason)
		return
	ev_reject.rpc_id(peer, reason)
	get_tree().create_timer(0.5).timeout.connect(_kick.bind(peer))


func _spawn_state() -> Dictionary:
	var spot = model.find_free_spot("chair", "town", TownModel.TOWN_SPAWN)
	var p: Vector2 = spot if spot != null else TownModel.TOWN_SPAWN
	return {"space": "town", "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"}


func _players_snapshot() -> Dictionary:
	var out := {}
	for p in players:
		out[p] = players[p].duplicate(true)
	return out


func _seats_snapshot() -> Dictionary:
	return seats.duplicate(true)


func _can_edit(peer: int, id: String) -> String:
	var holder: int = locks.get(id, 0)
	if holder != 0 and holder != peer:
		return "Someone else is using that."
	if not seats.get(id, {}).is_empty():
		return "Someone is playing on it."
	for att in model.attachments_of(id):
		if locks.get(att["id"], 0) not in [0, peer]:
			return "Someone else is using that."
	if model.items.has(id) and model.items[id]["kind"] == "cottage":
		for p in players:
			if p != peer and TownModel.house_of(str(players[p]["state"].get("space", ""))) == id:
				return "Someone is inside this house."
	return ""


func _srv_place(peer: int, req: int, kind: String, space: String, x: float, z: float, rot: int, color: int, host := "") -> void:
	var r: Dictionary = model.place(kind, space, x, z, rot, color, host)
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


func _srv_move(peer: int, req: int, id: String, x: float, z: float, rot: int, host := "") -> void:
	var err := _can_edit(peer, id)
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.move(id, x, z, rot, host)
	if r["ok"]:
		ev_item.rpc(r["item"])
		for att in r.get("moved", []):
			ev_item.rpc(att)
		_after_change()
	_reply(peer, req, r)


func _srv_paint(peer: int, req: int, id: String, color: int) -> void:
	var holder: int = locks.get(id, 0)
	var r: Dictionary = {"ok": false, "error": "Someone else is using that."} if holder != 0 and holder != peer else model.paint(id, color)
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


func _srv_remove(peer: int, req: int, id: String) -> void:
	var err := _can_edit(peer, id)
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.remove(id)
	if r["ok"]:
		var ids: Array = r["removed"].map(func(e): return e["id"])
		for i in ids:
			locks.erase(i)
		ev_removed.rpc(ids)
		_after_change()
	_reply(peer, req, r)


func _srv_restore(peer: int, req: int, entries: Array) -> void:
	var r: Dictionary = model.restore(entries)
	for item in r.get("items", []):
		ev_item.rpc(item)
	if r["ok"]:
		_after_change()
	_reply(peer, req, r)


func _srv_lock(peer: int, req: int, id: String) -> void:
	var err := "" if model.items.has(id) else TownModel.ERR_GONE
	if err == "":
		err = _can_edit(peer, id)
	if err == "":
		for other in locks.keys():
			if locks[other] == peer and other != id:
				locks.erase(other)
				ev_lock.rpc(other, 0)
		locks[id] = peer
		ev_lock.rpc(id, peer)
	_reply(peer, req, {"ok": err == "", "error": err, "id": id})


func _srv_unlock(peer: int, req: int, id: String) -> void:
	if locks.get(id, 0) == peer:
		locks.erase(id)
		ev_lock.rpc(id, 0)
	_reply(peer, req, {"ok": true, "id": id})


func _srv_sit(peer: int, req: int, id: String) -> void:
	var err := ""
	if not model.items.has(id):
		err = TownModel.ERR_GONE
	elif locks.get(id, 0) != 0:
		err = "Someone else is using that."
	var capacity: int = Catalog.get_def(model.items[id]["kind"]).get("seats", 0) if err == "" else 0
	var taken: Dictionary = seats.get(id, {})
	var seat := -1
	if err == "":
		for s in capacity:
			if not taken.has(s):
				seat = s
				break
		if seat < 0:
			err = "Someone is playing on it."
	if err == "":
		_free_seats_of(peer)
		seats.get_or_add(id, {})[seat] = peer
		ev_seats.rpc(_seats_snapshot())
	_reply(peer, req, {"ok": err == "", "error": err, "id": id, "seat": seat})


func _srv_stand(peer: int, req: int) -> void:
	_free_seats_of(peer)
	_reply(peer, req, {"ok": true})


func _free_seats_of(peer: int) -> void:
	var changed := false
	for id in seats.keys():
		for s in seats[id].keys():
			if seats[id][s] == peer:
				seats[id].erase(s)
				changed = true
		if seats[id].is_empty():
			seats.erase(id)
	if changed:
		ev_seats.rpc(_seats_snapshot())


func _srv_bell(peer: int, req: int) -> void:
	model.evening = not model.evening
	ev_evening.rpc(model.evening)
	_mark_dirty()
	_reply(peer, req, {"ok": true})


func _srv_state(peer: int, s: Dictionary) -> void:
	if not players.has(peer):
		return
	var space := str(s.get("space", "town"))
	if not model.is_space(space):
		space = "town"
	var clean := {"space": space, "x": float(s.get("x", 0.0)), "z": float(s.get("z", 0.0)),
		"ry": float(s.get("ry", 0.0)), "anim": str(s.get("anim", "idle")).left(16)}
	players[peer]["state"] = clean
	for other in players:
		if other != peer and other != 1:
			ev_player_state.rpc_id(other, peer, clean)
	if mode != "server" and peer != my_id:
		player_state.emit(peer, clean)


func _srv_emote(peer: int, kind: String) -> void:
	ev_emote.rpc(peer, kind)


## After any edit: save soon, and light lanterns for newly formed Cozy Spots.
func _after_change() -> void:
	_mark_dirty()
	var names: Array = players.values().map(func(p): return p["avatar"]["nick"])
	for spot in CozySpots.newly_formed(model):
		model.lanterns[spot] = {"by": names, "t": int(Time.get_unix_time_from_system())}
		ev_lantern.rpc(spot, names)


# ------------------------------------------------------------- RPC: authority -> clients
# call_local lets solo and host devices render the same events as clients.

@rpc("authority", "call_remote", "reliable")
func ev_welcome(peer: int, town: Dictionary, snapshot: Dictionary, lock_map: Dictionary, seat_map: Dictionary) -> void:
	my_id = peer
	model = TownModel.new()
	model.from_dict(town)
	players = snapshot
	locks = lock_map
	seats = seat_map
	_set_state("online")
	town_reset.emit()
	evening_changed.emit(model.evening)
	_after_welcome()


func _after_welcome() -> void:
	joined.emit(my_id)
	players_changed.emit()
	seats_changed.emit()


@rpc("authority", "call_remote", "reliable")
func ev_reject(reason: String) -> void:
	_set_state("failed")
	rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func ev_result(req: int, result: Dictionary) -> void:
	_on_result(req, result)


func _on_result(req: int, result: Dictionary) -> void:
	if not result.get("ok", false) and result.get("error", "") != "":
		request_failed.emit(result["error"])
	request_done.emit(req, result)


@rpc("authority", "call_local", "reliable")
func ev_item(item: Dictionary) -> void:
	if not is_authority():
		model.items[item["id"]] = item
	item_changed.emit(item)


@rpc("authority", "call_local", "reliable")
func ev_removed(ids: Array) -> void:
	if not is_authority():
		for id in ids:
			model.items.erase(id)
			locks.erase(id)
	items_removed.emit(ids)


@rpc("authority", "call_local", "reliable")
func ev_player_joined(peer: int, avatar: Dictionary, s: Dictionary) -> void:
	if not is_authority():
		players[peer] = {"avatar": avatar, "state": s}
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func ev_player_left(peer: int) -> void:
	if not is_authority():
		players.erase(peer)
	players_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func ev_player_state(peer: int, s: Dictionary) -> void:
	if players.has(peer):
		players[peer]["state"] = s
	player_state.emit(peer, s)


@rpc("authority", "call_local", "reliable")
func ev_emote(peer: int, kind: String) -> void:
	emote.emit(peer, kind)


@rpc("authority", "call_local", "reliable")
func ev_lock(item_id: String, peer: int) -> void:
	if not is_authority():
		if peer == 0:
			locks.erase(item_id)
		else:
			locks[item_id] = peer
	lock_changed.emit(item_id, peer)


@rpc("authority", "call_local", "reliable")
func ev_seats(seat_map: Dictionary) -> void:
	if not is_authority():
		seats = seat_map
	seats_changed.emit()


@rpc("authority", "call_local", "reliable")
func ev_lantern(spot: String, by: Array) -> void:
	if not is_authority():
		model.lanterns[spot] = {"by": by, "t": int(Time.get_unix_time_from_system())}
	lantern_lit.emit(spot, by)


@rpc("authority", "call_local", "reliable")
func ev_evening(on: bool) -> void:
	model.evening = on
	evening_changed.emit(on)


@rpc("authority", "call_local", "reliable")
func ev_saved(ok: bool) -> void:
	last_save_ok = ok
	saved.emit(ok)
