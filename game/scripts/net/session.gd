## Session (autoload): the shared town, the players in it and all networking.
##
## One authority owns the TownModel: the dedicated server, the hosting device,
## or this device in solo play (Godot's OfflineMultiplayerPeer reports itself as
## the server). Clients only send requests; the authority validates, applies,
## saves and broadcasts. Every peer keeps a mirror of the model for rendering.
extends Node

const Durable := preload("res://scripts/core/durable.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const PhotoIdeas := preload("res://scripts/core/photo_ideas.gd")

## 2: three-story houses with rooms ("<house>:<floor>:<room>" spaces) and a larger town.
## 3: tabletop decorations ("host" on items, place/move carry a host id).
## 4: device player ids, activities (wishes, presents, gardens, hearts, weather, photos).
## 5: join handshake with invites. 6: play ideas (snacks, snowman faces, "On display", fetch).
## 7: play ideas batch 2 (dress-up, story poses, trails, music boxes, toy tracks).
## 8: r11 (invitations, animal games, boats and leaf piles, blueprints, props, music parts, starter trail).
## 9: r12 wearable clothing (the "wear" action; worn items travel inside the avatar).
const Deployment := preload("res://scripts/net/deployment.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")
const PetRules := preload("res://scripts/core/pets.gd")
const Cooking := preload("res://scripts/core/cooking.gd")
const PlayRules := preload("res://scripts/core/play_rules.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const TrackRules := preload("res://scripts/core/track_rules.gd")
const Invites := preload("res://scripts/core/invites.gd")
const Blueprints := preload("res://scripts/core/blueprints.gd")
const Wearables := preload("res://scripts/core/wearables.gd")
const Contraptions := preload("res://scripts/core/contraptions.gd")
const Puzzles := preload("res://scripts/core/puzzles.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")
const Lamplight := preload("res://scripts/core/lamplight.gd")
const PictureBoard := preload("res://scripts/core/picture_board.gd")
const Echoes := preload("res://scripts/core/echoes.gd")
const Places := preload("res://scripts/core/places.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
## 13: town evenings and more (request lamp; event ev_lamplight; see design/town-evenings-and-more.md).
## 12 was puzzle rooms and rideable carts (requests puzzle, puzzle_reset, ride; events ev_puzzle, ev_ride).
## 11 was contraptions and a living town (request press; events ev_trigger, ev_react, Animals.ev_focus).
## 14: the zoo (requests travel, zoo_use, zoo_offer; the Zoo autoload's events; ev_town_data key maps; see
## docs/zoo-engineering-standard.md section 8). A move between maps happens only through travel.
## 20: Thousand Town (the map "thousand"; requests thousand_time, thousand_board, thousand_off; the Thousand autoload's
## ev_thousand_state and ev_thousand_effect; design/thousand-town.md section 3). The save schema is unchanged.
const PROTOCOL := 20   # thousand-town: the map thousand and its Thousand autoload; 19 was city-web's second city map (city_web, the CityWeb autoload); 18 city r3's shared weather (city r2 17: the vehicles' dwell; city r1 16; zoo r2 15)
const MAX_PLAYERS := 4
const DEFAULT_PORT := 9080
const SAVE_DELAY := 1.5
const JOIN_TIMEOUT := 10.0
## r19-connect (incident 2026-10-11 Asia/Shanghai): the welcome snapshot (the whole town) is one WebSocket message, and
## Godot's default 64 KiB WebSocket buffers refused a real 364-item town (75.6 KB): the server could not
## send it and the client stayed on Connecting. Every peer (client, hosted town, dedicated server) now
## uses NET_BUFFER_BYTES in each direction, on both ends. The welcome is refused clearly above
## WELCOME_LIMIT (never truncated). Within the town caps (300 outdoor items, 40 per room) the largest
## synthetic town measured is 2.76 MB (56 houses, every room full), so one message fits; a town that could
## outgrow WELCOME_LIMIT would need chunked snapshots instead (docs/multiplayer.md).
const NET_BUFFER_BYTES := 4 * 1024 * 1024
const WELCOME_LIMIT := 3 * 1024 * 1024
## A client that is connected but has no welcome after this long gives up instead of waiting forever.
const WELCOME_TIMEOUT := 20.0
const ERR_TOWN_TOO_BIG := "This town is too big to join right now."

signal connection_changed(state: String)      # offline, connecting, online, failed, disconnected
signal joined(peer_id: int)
## Just before a request leaves for the authority (_ask). The controller sends where the child is now, so the
## authority judges reach from the present position, not from a state up to 0.1 s old: a Cook pressed right
## after the tap's walk reached the stove was refused as too far (city-web r1 battery, pets tour).
signal before_request(method: String)
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
## Town-level activity data changed (key: roster, wishes, weather, hearts, visits, photo_ideas).
signal town_data_changed(key: String)
signal gift_opened(item_id: String, from_nick: String, by_peer: int)
signal cooking_changed(stove_id: String, recipe: String, on: bool)
signal cooked(stove_id: String, dish_id: String, recipe: String, nick: String, by_peer: int)
signal ate(peer: int, kind: String)
## A snack was shared (F01): everyone near `at` in `space` cheered.
signal snack_shared(peer: int, kind: String, space: String, at: Vector2, nick: String)
## A player changed hat or clothes color in town (F07).
signal avatar_changed(peer: int)
## Trail progress (F06): `found` signs of `total` found; done when the trail is finished.
signal trail_changed(peer: int, found: int, total: int, done: bool, nick: String)
## A toy track ball rolls (F02): cells in order, how it ends, where it stopped, bells rung.
signal track_rolled(start_id: String, cells: Array, end: String, at: Vector2, bells: Array)
## r11: an invitation card for this player; a friend joined my invitation.
signal invited(card: Dictionary)
signal invite_joined(nick: String, kind: String)
## r11: a paper boat sails (on the water at `center`); someone jumped in a leaf pile.
signal boat_sailed(id: String, center: Vector2, radius: float)
signal leaves_jumped(id: String, peer: int, together: bool)
## r11: who plays which part of a music box: {row: nick}.
signal music_parts_changed(id: String, parts: Dictionary)
signal pet_happy(owner_pid: String, pet_id: String, action: String, nick: String)
## Authority only: the town changed after an edit (activities re-check wishes).
signal town_changed()
## Contraptions: a trigger was set off; a spark from `from` reached reactor `id` and it did `effect`
## ("light", "music", "roll", "spin", "bubbles"); `on` is the new state of a lamp or a music box.
signal contraption_triggered(id: String)
signal contraption_reacted(id: String, from: String, effect: String, on: bool)
## Puzzle rooms: a space's shared puzzle progress changed (`was` is what it was on this device).
signal puzzle_changed(space: String, st: Dictionary, was: Dictionary)
## Rideable carts: a cart's ride changed ({} when the cart is home and empty).
signal ride_changed(id: String, ride: Dictionary)
## The lamplighter walk: every lamp post is lit this evening (once per evening, for everyone).
signal lamplight(by: Array)
## Authority only: a player finished joining (activities send their live state).
signal player_joined_authority(peer: int)

var model = TownModel.new()
var players := {}        # peer id -> {"avatar": {...}, "state": {...}}
var locks := {}          # item id -> peer id
var seats := {}          # item id -> {seat index: peer id}
var mode := "none"       # none, solo, host, client, server
var state := "offline"
var save_path := ""
var my_id := 0
var my_avatar := {}
## This device's player id (see design/playfulness-proposals.md, "Identity").
var my_pid := ""
var last_save_ok := true
var dirty := false

var _save_timer := 0.0
var _pending := {}       # peer id -> seconds since connect without joining
## Test and diagnosis overrides (scripts/net_test.py --connect): 0 keeps the defaults above. A buffer of
## -1 leaves Godot's own default (64 KiB), reproducing the shipped r13b behaviour.
var net_buffer_override := 0
var welcome_limit_override := 0
var _connecting_t := 0.0
var _req_counter := 0
## Optional town invite (authority only; never logged). "" = open town.
var invite := ""
var _join_invite := ""                  # client: the invite sent with this join
var _refused := {}                      # authority: refused connections still open
var cooking := {}                       # stove id -> {"recipe", "left" (s), "peer"}; shared, not saved
var trail_walk := {}                    # authority: peer -> signs found on the trail they follow; not saved
var _track_busy := {}                   # authority: start id -> msec when its ball is home again
var inbox := {}                         # authority: peer -> {inviter pid: card}; not saved
var _last_invite := {}                  # authority: peer -> {"kind|target": unix seconds} of their last invitation
var _last_journey := {}                 # authority: peer -> seconds (Time.get_ticks_msec) of their last journey
var _station_rest := {}                 # authority: zoo station id -> seconds of its last use
var _leaf_jumps := {}                   # authority: leaf pile id -> [peer, unix msec] of the last jump
var music_parts := {}                   # music box id -> {row: peer}; temporary, cleared when they leave
var _sparks := []                       # authority: sparks on their way [{"at" msec, "id", "from", "chain", "trigger"}]
var _trigger_rest := {}                 # authority: trigger id -> msec when it works again
var _on_pads := {}                      # authority: who ("p<peer>" or an animal) -> {step pad id: true}
var _pad_spaces = null                  # authority: {space: true} for spaces with a step pad (null = look again)
var puzzles := {}                       # space -> shared puzzle progress (core/puzzles.gd); every device, not saved
var _puzzle_sig := {}                   # authority: space -> Puzzles.signature when its puzzle last started
var rides := {}                         # station id -> {"peer", "phase", "route", "s", "end", "t", "why"}; every device, not saved
var _lamplight_done := false            # authority: the fireflies already gathered this evening
var _join_refused := false              # client: the town said no (reason already shown)
## A refused connection is closed by the client once it has read the reason. The
## server closes it itself only after this grace (still before AUTH_TIMEOUT); it
## never becomes a peer, so it gets no town data and holds no slot meanwhile.
const REFUSE_GRACE := 5.0
const AUTH_TIMEOUT := 10.0


func _ready() -> void:
	# Run before every other node each frame, so connections that started closing
	# are dropped before anyone broadcasts to them (_drop_closing_peers).
	process_priority = -100
	process_physics_priority = -100
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_authenticating.connect(_on_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_auth_failed)


func _process(delta: float) -> void:
	if mode == "client" and state == "connecting":
		_connecting_t += delta
		if _connecting_t > WELCOME_TIMEOUT:
			print("[client] no town after %.0f s: giving up" % WELCOME_TIMEOUT)
			_reset_peer()
			mode = "none"
			_set_state("failed")
		return
	if not is_authority():
		return
	_drop_closing_peers()
	_tick_cooking(delta)
	_tick_contraptions()
	_tick_rides()
	_echo_prune_t += delta
	if _echo_prune_t > 600.0:
		_echo_prune_t = 0.0
		prune_echoes()
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
	_srv_join(1, Avatar.sanitize(avatar), PROTOCOL, device_player_id())


## Listens for friends and plays on this device (LAN or forwarded port).
## Every WebSocket peer (client, hosted town, dedicated server) is made here, with room for the whole
## town in one message on both ends (NET_BUFFER_BYTES; set before create_*).
func _new_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	var size := net_buffer_override if net_buffer_override != 0 else NET_BUFFER_BYTES
	if size > 0:
		peer.inbound_buffer_size = size
		peer.outbound_buffer_size = size
	return peer


## The largest welcome this authority sends: its own limit, and never more than its peer can queue in one
## message (Godot reports a too-big send only in the log, and rpc_id still returns OK).
func welcome_limit() -> int:
	var limit := welcome_limit_override if welcome_limit_override > 0 else WELCOME_LIMIT
	var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if ws and ws.outbound_buffer_size > 0:
		limit = mini(limit, ws.outbound_buffer_size - 4096)   # room for the RPC header
	return limit


func start_host(path: String, avatar: Dictionary, port := DEFAULT_PORT) -> int:
	_reset_peer()
	var peer := _new_peer()
	var err := peer.create_server(port)
	if err != OK:
		_set_state("failed")
		return err
	mode = "host"
	invite = ""
	_use_auth()
	multiplayer.multiplayer_peer = peer
	_load_town(path)
	_set_state("online")
	_srv_join(1, Avatar.sanitize(avatar), PROTOCOL, device_player_id())
	return OK


## Headless dedicated town server; no local player.
func start_server(path: String, port := DEFAULT_PORT, bind := "*", town_invite := "") -> int:
	_reset_peer()
	var peer := _new_peer()
	var err := peer.create_server(port, bind)
	if err != OK:
		return err
	mode = "server"
	invite = town_invite
	_use_auth()
	multiplayer.multiplayer_peer = peer
	_load_town(path)
	_set_state("online")
	print("[server] Lantern Lane town server listening on %s:%d, save: %s, invite: %s" % [bind, port, path, "required" if invite != "" else "off"])
	return OK


func join(url: String, avatar: Dictionary, town_invite := "") -> int:
	_reset_peer()
	mode = "client"
	my_avatar = Avatar.sanitize(avatar)
	_join_invite = town_invite
	_join_refused = false
	_use_auth()
	var peer := _new_peer()
	var err := peer.create_client(url)
	if err != OK:
		_set_state("failed")
		return err
	multiplayer.multiplayer_peer = peer
	_connecting_t = 0.0
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
	_sparks.clear()
	_trigger_rest.clear()
	_on_pads.clear()
	_pad_spaces = null
	puzzles.clear()
	_puzzle_sig.clear()
	rides.clear()
	_lamplight_done = false
	_pending.clear()
	_refused.clear()
	_last_journey.clear()
	_station_rest.clear()
	my_id = 0
	model = TownModel.new()


func _set_state(s: String) -> void:
	state = s
	connection_changed.emit(s)


# ------------------------------------------------------------- persistence

func _load_town(path: String) -> void:
	save_path = path
	_pad_spaces = null
	model = null
	for candidate in [path, path + ".bak"]:
		if FileAccess.file_exists(candidate):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(candidate))
			var m = TownModel.new()
			if typeof(parsed) == TYPE_DICTIONARY and m.from_dict(parsed):
				model = m
				if not m.last_migration.is_empty():
					# Keep the untouched old save once (.v1 for schema 1, .v2 for schema 2), then write the new format soon.
					var original := "%s.v%d" % [path, int(m.last_migration["from"])]
					if not FileAccess.file_exists(original):
						DirAccess.copy_absolute(candidate, original)
					dirty = true
					print("Town save migrated: %s (original kept as %s)" % [m.last_migration, original.get_file()])
				if m.tram_added:
					dirty = true   # a town that had no tram stop has one now: save it
				if int(parsed.get("schema", -1)) == 2 and FileAccess.file_exists(path + ".maps"):
					# A schema-2 file after a downgrade (or its .bak projection): bring the zoo's things and maps back.
					var side := JSON.new()
					if side.parse(FileAccess.get_file_as_string(path + ".maps")) == OK and typeof(side.data) == TYPE_DICTIONARY:
						var back: Dictionary = m.merge_sidecar(side.data)
						if back["items"] > 0 or back["maps"]:
							dirty = true
						print("Zoo sidecar merged: %d things (%d with new ids), maps %s" % [back["items"], back["remapped"], "restored" if back["maps"] else "none"])
					else:
						push_warning("Could not read zoo sidecar %s" % (path + ".maps"))
				break
			push_warning("Could not read town save %s" % candidate)
	if model == null:
		model = TownModel.make_default()
		dirty = true
	if not model.echoes.is_empty() and Echoes.prune(model, echo_now()):
		dirty = true   # hellos older than seven days are gone when the town opens
	# A loaded town starts with every puzzle ready to play and every cart at home.
	puzzles.clear()
	rides.clear()
	_puzzle_sig.clear()
	for sp in Puzzles.spaces(model):
		_puzzle_sig[sp] = Puzzles.signature(model, sp)
	town_reset.emit()
	evening_changed.emit(model.evening)


## Atomic save (schema 3, docs/zoo-engineering-standard.md section 7). Three files, each written to a temp file and
## renamed: <path>.maps (the zoo's things and maps, so a downgrade and an upgrade lose nothing), <path>.bak (a
## schema-2 projection of the same town: an older app that refuses schema 3 still finds the whole town) and the
## main file last.
func save_now() -> bool:
	dirty = false
	if save_path == "":
		return false
	var dir := save_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var put := func(to: String, data: Dictionary) -> bool:
		var out := FileAccess.open(to + ".tmp", FileAccess.WRITE)
		if out == null:
			return false
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		return DirAccess.rename_absolute(to + ".tmp", to) == OK
	var main: Dictionary = model.to_dict()
	var side_ok: bool = put.call(save_path + ".maps", model.to_sidecar())
	var bak_ok: bool = put.call(save_path + ".bak", model.to_dict_v2(main))
	if not side_ok or not bak_ok:
		push_warning("Could not write the town's backup files next to %s" % save_path)
	var ok: bool = put.call(save_path, main)
	if ok:
		Durable.mirror(save_path)   # Apple TV: also keep the checked copy (nothing elsewhere)
		if side_ok:
			Durable.mirror(save_path + ".maps")
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

# ------------------------------------------------------------- join handshake
# Before a connection becomes a peer it must authenticate (docs/deployment.md):
# until then it gets no snapshot or broadcast and holds no player slot.

func _use_auth() -> void:
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _on_auth
	sm.auth_timeout = AUTH_TIMEOUT
	# Every message goes through the authority, so the engine's own peer relaying
	# is not used; turned off, a leaving friend is never announced to a socket
	# that is already closing (an intermittent engine send error with 4 players).
	sm.server_relay = false


func _on_authenticating(peer: int) -> void:
	if mode == "client" and peer == 1:
		var hello := {"v": PROTOCOL, "invite": _join_invite}
		(multiplayer as SceneMultiplayer).send_auth(1, JSON.stringify(hello).to_utf8_buffer())


func _on_auth(peer: int, data: PackedByteArray) -> void:
	var sm := multiplayer as SceneMultiplayer
	if mode == "client":
		match data.get_string_from_utf8():
			"ok": sm.complete_auth(1)
			"invite": _refused_by_town("This town needs the right invite code.")
			"update": _refused_by_town("Please update the app to play together.")
		return
	if not is_authority():
		return
	var hello = Deployment.quiet_json(data.get_string_from_utf8())
	if not hello is Dictionary or int(hello.get("v", 0)) != PROTOCOL:
		_refuse(peer, "update")
		return
	var given = hello.get("invite", "")
	if invite != "" and not (given is String and Deployment.same_invite(given, invite)):
		_refuse(peer, "invite")
		return
	sm.send_auth(peer, "ok".to_utf8_buffer())
	sm.complete_auth(peer)


## Tells a connection why it cannot join, then closes it (it never became a peer).
func _refuse(peer: int, why: String) -> void:
	(multiplayer as SceneMultiplayer).send_auth(peer, why.to_utf8_buffer())
	if mode == "server":
		print("[server] a connection was refused (%s)" % ("wrong or missing invite" if why == "invite" else "old app"))
	_refused[peer] = true
	# Closing right away could make the reason and the close reach the client in the
	# same network poll (a TLS proxy can hold small frames), and the client would
	# drop the unread reason. The client closes after reading it; this is a fallback.
	get_tree().create_timer(REFUSE_GRACE).timeout.connect(func():
		if _refused.has(peer) and multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
			_refused.erase(peer)
			(multiplayer.multiplayer_peer as WebSocketMultiplayerPeer).disconnect_peer(peer))


## Client: show why, then close the connection ourselves.
func _refused_by_town(reason: String) -> void:
	_join_refused = true
	rejected.emit(reason)
	_close_refused.call_deferred()


func _close_refused() -> void:
	if mode == "client" and _join_refused:
		_reset_peer()
		mode = "none"
		_set_state("offline")


func _on_auth_failed(peer: int) -> void:
	_refused.erase(peer)
	if mode == "client" and state == "connecting" and not _join_refused:
		_set_state("failed")


func _on_peer_connected(peer: int) -> void:
	if is_authority():
		_pending[peer] = 0.0
	elif mode == "client" and peer == 1:
		pass


func _on_peer_disconnected(peer: int) -> void:
	if not is_authority():
		return
	_pending.erase(peer)
	_last_journey.erase(peer)
	if not players.has(peer):
		return
	players.erase(peer)
	# Friends often leave together, so everything here goes only to open connections.
	for item_id in locks.keys():
		if locks[item_id] == peer:
			locks.erase(item_id)
			_broadcast_open(&"ev_lock", [item_id, 0])
	_free_seats_of(peer)
	trail_walk.erase(peer)   # a friend leaving never blocks the others' trail
	_puzzle_left("")         # a solved puzzle nobody is at any more tidies itself up
	_on_pads.erase("p%d" % peer)
	inbox.erase(peer)
	var left_pid := pid_of(peer)
	for sp in model.display:
		model.set_helper(sp, left_pid, false)
	for id in music_parts.keys():
		for row in music_parts[id].keys():
			if music_parts[id][row] == peer:
				music_parts[id].erase(row)
		_send_parts(id)
	_broadcast_open(&"ev_player_left", [peer])
	Zoo.peer_left(peer)   # the zoo sleeps when its last child is gone
	for city in city_nodes():
		city.peer_left(peer)   # frees a seat, a machine or a gondola place at once
	var thousand := thousand_node()
	if thousand:
		thousand.peer_left(peer)   # frees a bus seat; the town's clock stops when nobody is there
	print("[server] peer %d left, %d playing" % [peer, players.size()])


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	rq_join.rpc_id(1, my_avatar, PROTOCOL, device_player_id())


func _on_connection_failed() -> void:
	_set_state("failed")


func _on_server_disconnected() -> void:
	players.clear()
	locks.clear()
	seats.clear()
	# Closed before the town arrived (e.g. a town too big for this app's buffer): a failed join, so the
	# menu says it could not reach the town instead of staying on Connecting (r19-connect).
	_set_state("failed" if state == "connecting" else "disconnected")
	players_changed.emit()


func _kick(peer: int) -> void:
	# The turned-away child may already have closed the connection.
	if multiplayer.multiplayer_peer and peer != 1 and multiplayer.get_peers().has(peer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)


## Runs a call_local event here and on every peer whose connection is still
## open, like `.rpc()` but without send errors for friends who are just leaving.
func _broadcast_open(method: StringName, args: Array) -> void:
	callv(method, args)
	for other in _open_peers():
		Callable(self, &"rpc_id").callv([other, method] + args)


## A friend whose connection is already closing is let go at once, before any
## broadcast this frame (sending to a closing WebSocket is an engine error).
## Session is the first autoload, so this runs right after the network poll.
## Peers this loop already closed: the multiplayer API can still list them for a
## frame after the WebSocket layer removed them, and asking for them then is an error.
var _dropped := {}

func _drop_closing_peers() -> void:
	var mp := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if mp == null:
		return
	var listed := multiplayer.get_peers()
	for p in _dropped.keys():
		if not listed.has(p):
			_dropped.erase(p)
	for p in listed:
		if _dropped.has(p):
			continue
		var ws := mp.get_peer(p)
		if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			_dropped[p] = true
			mp.disconnect_peer(p, true)


## Connected peers whose WebSocket is open (a closing one would log a send error).
func _open_peers() -> Array:
	var mp := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	var out := []
	for p in multiplayer.get_peers():
		if mp == null:
			out.append(p)
			continue
		# A peer can still be listed for a moment after its socket is gone (get_peer is then null): skip it,
		# or the whole broadcast would stop with a script error (zoo r2 battery, server_zoo.log).
		var ws := mp.get_peer(p)
		if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			out.append(p)
	return out


# ------------------------------------------------------------- client API
# Each call reaches the authority directly (solo/host) or by RPC (client).

func _ask(method: String, args: Array) -> int:
	before_request.emit(method)
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


## Ride the tram to another map ("town" or "zoo"). The reply: {"ok", "space", "x", "z", "ry"}, or
## {"ok": false, "error"}; nothing changes until it says yes (docs/zoo-engineering-standard.md section 4).
func travel(to: String) -> int:
	return _ask("travel", [to])


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
	if not Avatar.is_emote(kind):
		return
	if is_authority():
		_srv_emote(my_id, kind)
	elif is_online():
		rq_emote.rpc_id(1, kind)


## A random id created once per device and kept in settings. It identifies a
## device for gifts, hearts and visits; it is not an account or a secret.
static func device_player_id() -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var pid := str(cfg.get_value("player", "id", ""))
	if not _valid_pid(pid):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		pid = ""
		for i in 16:
			pid += "%02x" % rng.randi_range(0, 255)
		cfg.set_value("player", "id", pid)
		cfg.save("user://settings.cfg")
	return pid


static func _valid_pid(pid: String) -> bool:
	return pid.length() == 32 and pid.is_valid_hex_number()


func pid_of(peer: int) -> String:
	return players.get(peer, {}).get("pid", "")


func peer_of_pid(pid: String) -> int:
	for p in players:
		if players[p].get("pid", "") == pid:
			return p
	return 0


func wrap(id: String, to_pid: String, paper: int) -> int:
	return _ask("wrap", [id, to_pid, paper])


func unwrap(id: String) -> int:
	return _ask("unwrap", [id])


func water(id: String) -> int:
	return _ask("water", [id])


func toggle_heart(space: String) -> int:
	return _ask("heart", [space])


func change_weather() -> int:
	return _ask("weather", [])


func report_photo(ideas: Array) -> int:
	return _ask("photo", [ideas])


func furnish_room(space: String) -> int:
	return _ask("furnish", [space])


func adopt_pet(family: String, color: int, name_index: int) -> int:
	return _ask("adopt", [family, color, name_index])


func pet_follow(pet_id: String) -> int:
	return _ask("pet_follow", [pet_id])


func pet_mode(mode: String) -> int:
	return _ask("pet_mode", [mode])


func pet_care(owner_pid: String, pet_id: String, action: String) -> int:
	return _ask("pet_care", [owner_pid, pet_id, action])


func cook(stove_id: String, recipe: String) -> int:
	return _ask("cook", [stove_id, recipe])


func eat(dish_id: String) -> int:
	return _ask("eat", [dish_id])


func make_snack(tray_id: String, base: String, topping: String) -> int:
	return _ask("snack", [tray_id, base, topping])


func share_snack(snack_id: String) -> int:
	return _ask("share_snack", [snack_id])


func change_face(id: String) -> int:
	return _ask("face", [id])


func set_display(space: String, on: bool) -> int:
	return _ask("display", [space, on])


func throw_ball(at: Vector2) -> int:
	return _ask("fetch", [at.x, at.y])


## Dress-up: outfit -1 and prop "-" keep what the child wears now.
func dress(hat: String, outfit_color: int, outfit := -1, prop := "-") -> int:
	return _ask("dress", [hat, outfit_color, outfit, prop])


## Wardrobe (r12): put on an accepted wearable in its slot, or take the slot off with id "".
func wear(slot: String, id: String) -> int:
	return _ask("wear", [slot, id])


func send_invite(kind: String, target: String) -> int:
	return _ask("invite", [kind, target])


## answer: "join", "not_now", or "leave" (stop helping).
func answer_invite(from_pid: String, answer: String) -> int:
	return _ask("invite_reply", [from_pid, answer])


func play_with_animal(kind: String, option := 0) -> int:
	return _ask("animal_play", [kind, option])


## House visits (r18): ask an animal friend home (on), or say goodbye (off).
func visit_animal(kind: String, on: bool) -> int:
	return _ask("animal_visit", [kind, on])


func sail_boat(id: String) -> int:
	return _ask("boat", [id])


func jump_in_leaves(id: String) -> int:
	return _ask("leaves", [id])


## pieces: Blueprints.plan(...) for the current space.
func place_blueprint(space: String, pieces: Array) -> int:
	return _ask("blueprint", [space, pieces])


func claim_music_part(id: String, row: int) -> int:
	return _ask("music_part", [id, row])


func starter_trail() -> int:
	return _ask("starter_trail", [])


func follow_trail(on: bool) -> int:
	return _ask("trail", [on])


func toggle_note(id: String, row: int, step: int) -> int:
	return _ask("music", [id, row, step])


func play_music(id: String, on: bool) -> int:
	return _ask("music_play", [id, on])


## Contraptions: press a big button.
func press(id: String) -> int:
	return _ask("press", [id])


## Animal passengers: from a cart at its station, ask an animal into the trailer (on) or let it out (off).
func ride_with_animal(kind: String, on: bool) -> int:
	return _ask("animal_ride", [kind, on])


## Friend echoes: leave a hello of three emotes where the child stands (it replaces their last one).
func leave_echo(emotes: Array) -> int:
	return _ask("echo_leave", [emotes])


## Take your own hello away.
func delete_echo() -> int:
	return _ask("echo_delete", [])


## Answer a friend's hello with one emote (owner_pid is the friend's player id).
func answer_echo(owner_pid: String, emote: String) -> int:
	return _ask("echo_answer", [owner_pid, emote])


## I have looked at the answers to my hello.
func seen_echo() -> int:
	return _ask("echo_seen", [])


## The picture board: paint one square (color 0 clears it, 1 to 8 are the paint colors).
func set_pixel(id: String, index: int, color: int) -> int:
	return _ask("pixel", [id, index, color])


## The lamplighter walk: light a lamp post by hand, or put it out.
func toggle_lamp(id: String) -> int:
	return _ask("lamp", [id])


## Puzzle rooms: pick up a key, turn a picture dial or open the chest (by the part's id).
func use_puzzle(id: String) -> int:
	return _ask("puzzle", [id])


## Starts the puzzle of the space the child is in again. Anyone there may.
func reset_puzzle(space: String) -> int:
	return _ask("puzzle_reset", [space])


## Rideable carts: "board" (get in), "go" or "stop". Getting off is stand().
func ride(station_id: String, what: String) -> int:
	return _ask("ride", [station_id, what])


## The puzzle progress of a space as this device knows it (a fresh puzzle when nothing was said yet:
## fresh is the same on every device, so only changes travel).
func puzzle_state(space: String) -> Dictionary:
	if puzzles.has(space):
		return puzzles[space]
	return Puzzles.fresh(model, space)


## How far a cart is from its station's middle right now, in meters along its route.
func ride_distance(id: String) -> float:
	var r: Dictionary = rides.get(id, {})
	if r.is_empty():
		return 0.0
	if r["phase"] != "moving":
		return float(r["s"])
	return minf(float(r["end"]), float(r["s"]) + RideRules.SPEED * (Time.get_ticks_msec() - int(r["t"])) / 1000.0)


## The cart this child rides: its station id, or "".
func ride_of(peer: int) -> String:
	for id in rides:
		if int(rides[id]["peer"]) == peer:
			return id
	return ""


func roll_track(start_id: String) -> int:
	return _ask("track", [start_id])


## Someone else put this space on display: {"pid", "nick"}, else {}.
func display_by_other(space: String) -> Dictionary:
	var d: Dictionary = model.display_by(space)
	return d if not d.is_empty() and d.get("pid", "") != my_pid else {}


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
func rq_join(avatar: Dictionary, protocol: int, pid := "") -> void:
	if is_authority():
		_srv_join(multiplayer.get_remote_sender_id(), Avatar.sanitize(avatar), protocol, str(pid))


@rpc("any_peer", "call_remote", "reliable")
func rq_action(method: String, req: int, args: Array) -> void:
	if not is_authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not players.has(peer):
		return
	if not method in ["place", "move", "paint", "remove", "restore", "lock", "unlock", "sit", "stand", "bell",
			"wrap", "unwrap", "water", "heart", "weather", "photo", "furnish", "adopt", "pet_follow", "pet_mode",
			"pet_care", "cook", "eat", "snack", "share_snack", "face", "display", "fetch",
			"dress", "trail", "music", "music_play", "track",
			"invite", "invite_reply", "animal_play", "animal_visit", "boat", "leaves", "blueprint", "music_part", "starter_trail", "wear", "press",
			"puzzle", "puzzle_reset", "ride", "lamp", "pixel", "echo_leave", "echo_delete", "echo_answer", "echo_seen", "animal_ride",
			"travel", "zoo_use", "zoo_offer", "city_use", "city_board", "city_off", "city_release", "city_weather",
			"thousand_time", "thousand_board", "thousand_off"]:
		return
	var expected := {"place": 7, "move": 5, "paint": 2, "remove": 1, "restore": 1, "lock": 1, "unlock": 1, "sit": 1, "stand": 0, "bell": 0,
		"wrap": 3, "unwrap": 1, "water": 1, "heart": 1, "weather": 0, "photo": 1, "furnish": 1, "adopt": 3, "pet_follow": 1,
		"pet_mode": 1, "pet_care": 3, "cook": 2, "eat": 1,
		"snack": 3, "share_snack": 1, "face": 1, "display": 2, "fetch": 2,
		"dress": 4, "trail": 1, "music": 3, "music_play": 2, "track": 1,
		"invite": 2, "invite_reply": 2, "animal_play": 2, "animal_visit": 2, "boat": 1, "leaves": 1, "blueprint": 2, "music_part": 2, "starter_trail": 0, "wear": 2, "press": 1,
		"puzzle": 1, "puzzle_reset": 1, "ride": 2, "lamp": 1, "pixel": 3, "echo_leave": 1, "echo_delete": 0, "echo_answer": 2, "echo_seen": 0, "animal_ride": 2,
		"travel": 1, "zoo_use": 1, "zoo_offer": 1, "city_use": 1, "city_board": 0, "city_off": 0, "city_release": 0, "city_weather": 1,
		"thousand_time": 2, "thousand_board": 1, "thousand_off": 0}
	if args.size() != expected[method]:
		return
	callv("_srv_" + method, [peer, req] + args)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rq_state(s: Dictionary) -> void:
	if is_authority() and players.has(multiplayer.get_remote_sender_id()):
		_srv_state(multiplayer.get_remote_sender_id(), s)


@rpc("any_peer", "call_remote", "reliable")
func rq_emote(kind: String) -> void:
	if is_authority() and players.has(multiplayer.get_remote_sender_id()) and Avatar.is_emote(kind):
		_srv_emote(multiplayer.get_remote_sender_id(), kind)


# ------------------------------------------------------------- authority logic

func _reply(peer: int, req: int, result: Dictionary) -> void:
	if peer == my_id and mode != "server":
		# Deliver after the caller has registered its callback, like a network reply.
		_on_result.call_deferred(req, result)
	elif peer != 0 and _open_peers().has(peer):
		ev_result.rpc_id(peer, req, result)


func _srv_join(peer: int, avatar: Dictionary, protocol: int, pid := "") -> void:
	_pending.erase(peer)
	if protocol != PROTOCOL:
		_reject(peer, "Please update the app to play together.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject(peer, "The town is full right now")
		return
	# One device = one player id. A missing or malformed id gets a fresh one for this visit.
	if not _valid_pid(pid) or peer_of_pid(pid) != 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		pid = "%016x%016x" % [rng.randi(), rng.randi()]
		pid = pid.left(32).rpad(32, "0")
	prune_echoes()
	players[peer] = {"avatar": avatar, "state": _spawn_state(), "pid": pid}
	model.roster[pid] = {"nick": avatar["nick"], "color": avatar["outfit_color"], "seen": int(Time.get_unix_time_from_system())}
	_mark_dirty()
	if peer == 1 and mode != "server":
		my_pid = pid
		my_id = 1
		my_avatar = avatar
		_after_welcome()
	else:
		# The whole town in one message: refused clearly (never truncated) if it is too big to send.
		var welcome := [peer, model.to_dict(), _players_snapshot(), locks, _seats_snapshot()]
		var size := var_to_bytes(welcome).size()
		var sent: int = ERR_OUT_OF_MEMORY if size > welcome_limit() else rpc_id(peer, &"ev_welcome", welcome[0], welcome[1], welcome[2], welcome[3], welcome[4])
		if sent != OK:
			print("[server] could not send the town to peer %d (%d bytes, limit %d, error %d)" % [peer, size, welcome_limit(), sent])
			players.erase(peer)
			_reject(peer, ERR_TOWN_TOO_BIG)
			return
		for stove in cooking:
			ev_cooking.rpc_id(peer, stove, cooking[stove]["recipe"], true)
		for sp in puzzles:
			ev_puzzle.rpc_id(peer, sp, puzzles[sp])   # puzzles under way (a fresh one needs no message)
		for id in rides:
			ev_ride.rpc_id(peer, id, _ride_wire(id))
		ev_player_joined.rpc(peer, avatar, players[peer]["state"], pid)
	ev_town_data.rpc("roster", model.roster)
	player_joined_authority.emit(peer)
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


## "On display" (F10): edits by others are refused there until it is taken off display.
func _display_err(peer: int, space: String) -> String:
	return PlayRules.display_error(model, str(space), pid_of(peer))


func _srv_place(peer: int, req: int, kind: String, space: String, x: float, z: float, rot: int, color: int, host := "") -> void:
	var shown := _display_err(peer, space)
	var r: Dictionary = {"ok": false, "error": shown} if shown != "" else model.place(kind, space, x, z, rot, color, host)
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
		Animals.item_placed(r["item"]["id"])   # a living town: someone may come and look
	_reply(peer, req, r)


func _srv_move(peer: int, req: int, id: String, x: float, z: float, rot: int, host := "") -> void:
	var err := _can_edit(peer, id)
	if err == "":
		err = _display_err(peer, PlayRules.item_space(model, id))
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.move(id, x, z, rot, host)
	if r["ok"]:
		ev_item.rpc(r["item"])
		for att in r.get("moved", []):
			ev_item.rpc(att)
		_after_change()
	_reply(peer, req, r)


func _srv_paint(peer: int, req: int, id: String, color: int) -> void:
	var holder: int = locks.get(id, 0)
	var shown := _display_err(peer, PlayRules.item_space(model, id))
	var r: Dictionary = {"ok": false, "error": "Someone else is using that."} if holder != 0 and holder != peer else (
		{"ok": false, "error": shown} if shown != "" else model.paint(id, color))
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


func _srv_remove(peer: int, req: int, id: String) -> void:
	var err := TownModel.ERR_TRAM_STAYS if model.items.get(id, {}).get("kind", "") == TownModel.TRAM_STOP else _can_edit(peer, id)
	if err == "":
		err = _display_err(peer, PlayRules.item_space(model, id))
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.remove(id)
	if r["ok"]:
		var ids: Array = r["removed"].map(func(e): return e["id"])
		for i in ids:
			locks.erase(i)
		ev_removed.rpc(ids)
		_after_change()
	_reply(peer, req, r)


func _srv_restore(peer: int, req: int, entries: Array) -> void:
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and _display_err(peer, str(e.get("space", ""))) != "":
			_reply(peer, req, {"ok": false, "error": _display_err(peer, str(e.get("space", ""))), "items": [], "skipped": []})
			return
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
	elif model.items[id].has("gift"):
		err = "Open the present first!"
	var capacity: int = Catalog.seats(model.items[id]["kind"]) if err == "" else 0
	var taken: Dictionary = seats.get(id, {})
	var seat := -1
	if err == "":
		# The first free seat; a child already on this item keeps their own seat (r17: two-seat benches).
		for s in capacity:
			if taken.get(s, peer) == peer:
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
				if rides.has(id):
					# Getting off, sitting somewhere else or leaving the town: the cart goes home empty.
					_broadcast_open(&"ev_ride", [id, {}])
		if seats[id].is_empty():
			seats.erase(id)
	if changed:
		_broadcast_open(&"ev_seats", [_seats_snapshot()])


func _srv_bell(peer: int, req: int) -> void:
	model.evening = not model.evening
	ev_evening.rpc(model.evening)
	_mark_dirty()
	_lamplight_done = false   # a new evening (or morning): the fireflies can gather again
	_check_lamplight()        # the bell rung with every lamp already lit
	_reply(peer, req, {"ok": true})


## The least time between two journeys of one child (seconds).
const JOURNEY_REST := 1.0
## A zoo station rests this long after each use (seconds).
const STATION_REST := 1.2
## How much farther than ZooMap.STATION_REACH the authority still believes a child (positions are the client's word).
const STATION_SLACK := 0.4
## A child must be this close to an animal (m) to offer it a treat.
const OFFER_REACH := 3.5
const ZOO_ERRORS := {
	"busy": "They are busy right now. Try again in a moment.",
	"unknown": "That is not something to use.",
}


## A child asks the tram to take them to another map. Only this changes a player's map.
func _srv_travel(peer: int, req: int, to) -> void:
	var dest := str(to)
	var now := Time.get_ticks_msec() / 1000.0
	var cur := str(players.get(peer, {}).get("state", {}).get("space", "town"))
	var from_map := Places.map_of(cur)
	if not dest in Places.DESTINATIONS.get(from_map, []):
		_reply(peer, req, {"ok": false, "error": "The tram does not go there from here."})
		return
	if now - float(_last_journey.get(peer, -99.0)) < JOURNEY_REST:
		_reply(peer, req, {"ok": false, "error": "The tram is getting ready. Try again in a moment."})
		return
	_last_journey[peer] = now
	var note := ""
	var at: Vector2
	var ry := 0.0
	if dest == Places.ZOO:
		at = Places.arrival(Places.ZOO, _free_arrival_slot(peer))
		ry = ZooMap.ARRIVAL_RY
		note = Animals.child_boards(peer)   # a house visit ends: the animal (its English name) waits in town
	elif Places.is_city(dest):
		at = Places.arrival(dest, _free_arrival_slot(peer, dest))
		ry = CityMap.ARRIVAL_RY
		note = Animals.child_boards(peer)   # the same when the tram goes to the city
	elif dest == Places.THOUSAND:
		at = Places.arrival(dest, _free_arrival_slot(peer, dest))
		ry = Places.THOUSAND_ARRIVAL_RY   # the station forecourt, facing east (design/thousand-town.md section 3)
		note = Animals.child_boards(peer)   # and to Thousand Town
	else:
		var arrival := _town_arrival(peer)
		at = arrival["at"]
		ry = arrival["ry"]
	# The journey leaves the seat, the locks and the puzzle of the old place behind.
	_free_seats_of(peer)
	for item_id in locks.keys():
		if locks[item_id] == peer:
			locks.erase(item_id)
			_broadcast_open(&"ev_lock", [item_id, 0])
	var clean := {"space": dest, "x": snappedf(at.x, 0.01), "z": snappedf(at.y, 0.01), "ry": snappedf(ry, 0.01), "anim": "idle"}
	players[peer]["state"] = clean
	_puzzle_left(cur)
	for other in players:
		if other != peer and other != 1 and multiplayer.get_peers().has(other):   # only connected peers
			ev_player_state.rpc_id(other, peer, clean)
	if mode != "server" and peer != my_id:
		player_state.emit(peer, clean)
	var reply := {"ok": true, "space": dest, "x": clean["x"], "z": clean["z"], "ry": clean["ry"]}
	if note != "":
		reply["waits"] = note   # the visiting animal's English name; the client says it waits in town
	_reply(peer, req, reply)
	Zoo.on_space_changed(peer)
	for city in city_nodes():
		city.on_space_changed(peer)
	var thousand := thousand_node()
	if thousand:
		thousand.on_space_changed(peer)   # the first arrival starts the town's clock


## The first of a map's four arrival places (the zoo's platform, the city's bus stop) that no other
## child on that map stands on.
func _free_arrival_slot(peer: int, map := Places.ZOO) -> int:
	var slots: Array = ZooMap.ARRIVALS if map == Places.ZOO else (Places.THOUSAND_ARRIVALS if map == Places.THOUSAND else CityMap.ARRIVALS)
	for i in slots.size():
		var taken := false
		for other in players:
			var st: Dictionary = players[other].get("state", {})
			if other != peer and str(st.get("space", "")) == map \
					and Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))).distance_to(slots[i]) < 0.5:
				taken = true
		if not taken:
			return i
	return 0


## Where a child arrives in town and which way they face: in front of the tram stop's door (not while a
## friend holds the stop), else the usual place.
func _town_arrival(peer: int) -> Dictionary:
	var stop: String = model.tram_stop_id()
	if stop != "" and locks.get(stop, 0) in [0, peer]:
		var spot = TownModel.tram_stop_boarding(model)
		if spot is Vector2:
			var f: Vector2 = TownModel.facing(int(model.items[stop]["rot"]))
			return {"at": spot, "ry": atan2(f.x, f.y)}
	var fallback := _spawn_state()
	return {"at": Vector2(fallback["x"], fallback["z"]), "ry": 0.0}


## A child uses a zoo station (the action button). The authority checks the place, the reach and the rest.
func _srv_zoo_use(peer: int, req: int, station) -> void:
	var id := str(station)
	var w := _where(peer)
	if w["space"] != Places.ZOO or Zoo.brain == null:
		_reply(peer, req, {"ok": false, "error": "Take the tram to the zoo first."})
		return
	if not ZooMap.STATIONS.has(id):
		_reply(peer, req, {"ok": false, "error": ZOO_ERRORS["unknown"]})
		return
	if (w["pos"] as Vector2).distance_to(ZooMap.STATIONS[id]["pos"]) > ZooMap.STATION_REACH + STATION_SLACK:
		_reply(peer, req, {"ok": false, "error": "Walk closer first."})
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_station_rest.get(id, -99.0)) < STATION_REST:
		_reply(peer, req, {"ok": false, "error": ZOO_ERRORS["busy"]})
		return
	_station_rest[id] = now
	var why: String = Zoo.brain.use_station(id, w["pos"])
	if why != "":
		_reply(peer, req, {"ok": false, "error": str(ZOO_ERRORS.get(why, ZOO_ERRORS["busy"]))})
		return
	_reply(peer, req, {"ok": true, "station": id})


## A child offers a treat to a resident, from within OFFER_REACH metres.
func _srv_zoo_offer(peer: int, req: int, animal_id) -> void:
	var id := str(animal_id)
	var w := _where(peer)
	if w["space"] != Places.ZOO or Zoo.brain == null:
		_reply(peer, req, {"ok": false, "error": "Take the tram to the zoo first."})
		return
	var a: Dictionary = Zoo.brain.animal(id)
	if a.is_empty():
		_reply(peer, req, {"ok": false, "error": "There is nobody by that name here."})
		return
	var p: Vector3 = Zoo.brain.pos_of(a)
	if Vector2(p.x, p.z).distance_to(w["pos"]) > OFFER_REACH:
		_reply(peer, req, {"ok": false, "error": "Walk closer to offer a treat."})
		return
	var why: String = Zoo.brain.offer_to(id, w["pos"])
	if why != "":
		_reply(peer, req, {"ok": false, "error": str(ZOO_ERRORS.get(why, ZOO_ERRORS["busy"]))})
		return
	_reply(peer, req, {"ok": true, "animal": id})


func _srv_state(peer: int, s: Dictionary) -> void:
	if not players.has(peer):
		return
	var space := str(s.get("space", "town"))
	if not (Places.is_map(space) or model.is_space(space)):
		space = "town"
	var was_in := str(players[peer]["state"].get("space", "town"))
	# Only travel changes a player's map: a late packet from before a journey is dropped (it moves
	# between a map and its own rooms only).
	var was_map := Places.map_of(was_in)
	if was_map != "" and Places.map_of(space) != was_map:
		return
	var clean := {"space": space, "x": float(s.get("x", 0.0)), "z": float(s.get("z", 0.0)),
		"ry": float(s.get("ry", 0.0)), "anim": str(s.get("anim", "idle")).left(16)}
	# city r1: the level a child stands on (a CityMap region or stair id; "" is the ground), city only.
	var level := str(s.get("level", "")).left(24)
	if Places.is_city(space) and level != "" and CityNav.has_place(level):
		clean["level"] = level
	players[peer]["state"] = clean
	if was_in != space:
		_puzzle_left(was_in)
	step_on_pads("p%d" % peer, space, Vector2(clean["x"], clean["z"]))
	var house := TownModel.house_of(space)
	if house != "" and model.note_visit(house, pid_of(peer), nick_of(peer)):
		_mark_dirty()
		ev_town_data.rpc("visits", model.visits)
	for other in players:
		if other != peer and other != 1 and multiplayer.get_peers().has(other):   # only connected peers
			ev_player_state.rpc_id(other, peer, clean)
	if mode != "server" and peer != my_id:
		player_state.emit(peer, clean)


func _srv_emote(peer: int, kind: String) -> void:
	ev_emote.rpc(peer, kind)
	if trail_walk.has(peer):
		_trail_emote(peer, kind)


## After any edit: save soon, and light lanterns for newly formed Cozy Spots.
func _after_change() -> void:
	_mark_dirty()
	_pad_spaces = null
	_sync_puzzles()
	_reroute_rides()
	_check_lamplight()
	prune_echoes()   # a hello in a house that was just put away goes with it
	var names: Array = players.values().map(func(p): return p["avatar"]["nick"])
	for spot in CozySpots.newly_formed(model):
		model.lanterns[spot] = {"by": names, "t": int(Time.get_unix_time_from_system())}
		ev_lantern.rpc(spot, names)
	town_changed.emit()


# ------------------------------------------------------------- activities (authority)

func _srv_wrap(peer: int, req: int, id: String, to_pid: String, paper: int) -> void:
	var err := TownModel.ERR_TRAM_STAYS if model.items.get(id, {}).get("kind", "") == TownModel.TRAM_STOP else _can_edit(peer, id)
	if err == "" and to_pid != "" and not model.roster.has(to_pid):
		err = TownModel.ERR_GIFT_FOR_OTHER
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.wrap(id, pid_of(peer), nick_of(peer), to_pid, paper)
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


func _srv_unwrap(peer: int, req: int, id: String) -> void:
	var r: Dictionary = model.unwrap(id, pid_of(peer))
	if r["ok"]:
		ev_item.rpc(r["item"])
		ev_gift_opened.rpc(id, r["gift"].get("from_nick", ""), peer)
		_after_change()
	_reply(peer, req, r)


var _water_t := {}

func _srv_water(peer: int, req: int, id: String) -> void:
	# Watering is fun, not grinding: a short pause per bed keeps it from being spammed.
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_water_t.get(id, -99.0)) < 2.0:
		_reply(peer, req, {"ok": false, "error": ""})
		return
	_water_t[id] = now
	var r: Dictionary = model.grow(id)
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


## The slow in-session growth tick (activities call it about once a minute).
func grow_all() -> void:
	if not is_authority():
		return
	var grew := false
	for item in model.items.values():
		if item["kind"] == "garden_bed" and not item.has("gift"):
			var r: Dictionary = model.grow(item["id"])
			if r["ok"]:
				ev_item.rpc(r["item"])
				grew = true
	if grew:
		_after_change()


func _srv_heart(peer: int, req: int, space: String) -> void:
	var on: bool = model.toggle_heart(space, pid_of(peer), nick_of(peer))
	ev_town_data.rpc("hearts", model.hearts)
	_mark_dirty()
	_reply(peer, req, {"ok": true, "on": on})


func _srv_weather(peer: int, req: int) -> void:
	var i := TownModel.WEATHERS.find(model.weather)
	model.weather = TownModel.WEATHERS[(i + 1) % TownModel.WEATHERS.size()]
	ev_town_data.rpc("weather", model.weather)
	_mark_dirty()
	# Weather toys: every weather bell rings when the weather changes, and sets off what stands near it.
	var bells := 0
	for it in model.items_in("town"):
		if it["kind"] == "weather_bell" and fire_trigger(it["id"]):
			bells += 1
	_reply(peer, req, {"ok": true, "weather": model.weather, "bells": bells})


func _srv_photo(peer: int, req: int, ideas: Array) -> void:
	var fresh := []
	var names: Array = players.values().map(func(p): return p["avatar"]["nick"])
	for idea in ideas:
		if PhotoIdeas.text_of(str(idea)) != "" and not model.photo_ideas.has(str(idea)):
			model.photo_ideas[str(idea)] = {"by": names, "t": int(Time.get_unix_time_from_system())}
			fresh.append(str(idea))
	if not fresh.is_empty():
		ev_town_data.rpc("photo_ideas", model.photo_ideas)
		_mark_dirty()
	_reply(peer, req, {"ok": true, "new": fresh})


# ------------------------------------------------------------- themed rooms, pets, cooking

## Where a player stands: {space, pos}.
func _where(peer: int) -> Dictionary:
	var st: Dictionary = players.get(peer, {}).get("state", {})
	return {"space": str(st.get("space", "town")), "pos": Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))),
		"level": str(st.get("level", ""))}


# ------------------------------------------------------------- the city (city r1; net/city.gd, autoload City)

func city_use(key: String) -> int:
	return _ask("city_use", [key])


func city_board() -> int:
	return _ask("city_board", [])


func city_off() -> int:
	return _ask("city_off", [])


func city_release() -> int:
	return _ask("city_release", [])


## city r3: the city's weather (an index into CityMap.WEATHERS), shared by everyone in the city.
func city_weather(w: int) -> int:
	return _ask("city_weather", [w])


## The City autoloads, one per city map (City for "city", CityWeb for "city_web"; city-web), those running.
func city_nodes() -> Array:
	var out := []
	for path in ["/root/City", "/root/CityWeb"]:
		var n := get_node_or_null(path)
		if n:
			out.append(n)
	return out


## The City autoload that serves a space's city map (null when the space is not a city map).
func city_of(space: String) -> Node:
	if space == Places.CITY:
		return get_node_or_null("/root/City")
	if space == Places.CITY_WEB:
		return get_node_or_null("/root/CityWeb")
	return null


## Every city request goes to the City autoload of the asking child's city map, which owns that map's shared
## state (seats, machines, the wheel, the traffic); here only the place, level and position are checked and passed.
func _city_call(peer: int, req: int, method: String, args: Array) -> void:
	var w := _where(peer)
	var city := city_of(str(w["space"]))
	if city == null:
		_reply(peer, req, {"ok": false, "error": "Take the tram to the city first."})
		return
	_reply(peer, req, city.callv(method, [peer, w["level"], w["pos"]] + args))


func _srv_city_use(peer: int, req: int, key) -> void:
	_city_call(peer, req, "srv_use", [str(key)])


func _srv_city_board(peer: int, req: int) -> void:
	_city_call(peer, req, "srv_board", [])


func _srv_city_off(peer: int, req: int) -> void:
	_city_call(peer, req, "srv_off", [])


func _srv_city_release(peer: int, req: int) -> void:
	_city_call(peer, req, "srv_release", [])


func _srv_city_weather(peer: int, req: int, w) -> void:
	if typeof(w) != TYPE_INT and typeof(w) != TYPE_FLOAT:
		_reply(peer, req, {"ok": false, "error": "That does not work right now."})
		return
	_city_call(peer, req, "srv_weather", [int(w)])


# ------------------------------------------------------------- Thousand Town (net/thousand.gd, autoload Thousand)

## Thousand Town's time: "auto" (speed 1, 2 or 4; 0 keeps it), "day", "dusk" or "night", shared by everyone there.
func thousand_time(mode: String, speed := 0) -> int:
	return _ask("thousand_time", [mode, speed])


## A seat on one of Thousand Town's buses (index), and getting off again.
func thousand_board(vehicle: int) -> int:
	return _ask("thousand_board", [vehicle])


func thousand_off() -> int:
	return _ask("thousand_off", [])


func thousand_node() -> Node:
	return get_node_or_null("/root/Thousand")


## Every Thousand request goes to the Thousand autoload, which owns the town's clock and bus seats.
func _thousand_call(peer: int, req: int, method: String, args: Array) -> void:
	var t := thousand_node()
	if t == null or _where(peer)["space"] != Places.THOUSAND:
		_reply(peer, req, {"ok": false, "error": "Take the tram to Thousand Town first."})
		return
	_reply(peer, req, t.callv(method, [peer] + args))


func _srv_thousand_time(peer: int, req: int, mode, speed) -> void:
	if typeof(mode) != TYPE_STRING or not (typeof(speed) == TYPE_INT or typeof(speed) == TYPE_FLOAT):
		_reply(peer, req, {"ok": false, "error": "That does not work right now."})
		return
	_thousand_call(peer, req, "srv_time_mode", [str(mode).left(8), int(speed)])


func _srv_thousand_board(peer: int, req: int, vehicle) -> void:
	if not (typeof(vehicle) == TYPE_INT or typeof(vehicle) == TYPE_FLOAT):
		_reply(peer, req, {"ok": false, "error": "That does not work right now."})
		return
	_thousand_call(peer, req, "srv_board_bus", [int(vehicle)])


func _srv_thousand_off(peer: int, req: int) -> void:
	_thousand_call(peer, req, "srv_off_bus", [])


func _srv_furnish(peer: int, req: int, space: String) -> void:
	if _where(peer)["space"] != str(space):
		_reply(peer, req, {"ok": false, "error": "Go into that room first."})
		return
	if _display_err(peer, str(space)) != "":
		_reply(peer, req, {"ok": false, "error": _display_err(peer, str(space))})
		return
	var placed: Array = RoomThemes.furnish_room(model, str(space))
	if placed.is_empty():
		_reply(peer, req, {"ok": false, "error": "This room is already set up."})
		return
	for item in placed:
		ev_item.rpc(item)
	ev_town_data.rpc("starter", model.starter)
	_after_change()
	_reply(peer, req, {"ok": true, "count": placed.size()})


func _srv_adopt(peer: int, req: int, family: String, color: int, name_index: int) -> void:
	var house := TownModel.house_of(_where(peer)["space"])
	var r: Dictionary = PetRules.adopt(model, pid_of(peer), str(family), int(color), int(name_index), house)
	if r["ok"]:
		share("pets")
	_reply(peer, req, r)


func _srv_pet_follow(peer: int, req: int, pet_id: String) -> void:
	var pid := pid_of(peer)
	var r: Dictionary = PetRules.set_active(model, pid, str(pet_id))
	if r["ok"] and str(pet_id) != "":
		r = PetRules.set_mode(model, pid, "follow")
	if r["ok"]:
		share("pets")
	_reply(peer, req, r)


func _srv_pet_mode(peer: int, req: int, mode: String) -> void:
	var r: Dictionary = PetRules.set_mode(model, pid_of(peer), str(mode))
	if r["ok"]:
		share("pets")
	_reply(peer, req, r)


func _srv_pet_care(peer: int, req: int, owner_pid: String, pet_id: String, action: String) -> void:
	var owner := peer_of_pid(str(owner_pid))
	var owner_space: String = _where(owner)["space"] if owner != 0 else ""
	var w := _where(peer)
	var r: Dictionary = PetRules.care(model, str(owner_pid), str(pet_id), str(action), w["space"], w["pos"], owner_space)
	if r["ok"]:
		ev_pet_happy.rpc(str(owner_pid), str(pet_id), str(action), nick_of(peer))
		share("pets")
	_reply(peer, req, r)


func _srv_cook(peer: int, req: int, stove_id: String, recipe: String) -> void:
	var w := _where(peer)
	var err := Cooking.check(model, str(stove_id), str(recipe), w["space"], w["pos"], cooking)
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	cooking[str(stove_id)] = {"recipe": str(recipe), "left": Cooking.COOK_SECONDS, "peer": peer}
	ev_cooking.rpc(str(stove_id), str(recipe), true)
	_reply(peer, req, {"ok": true, "seconds": Cooking.COOK_SECONDS})


## Authority: finishes dishes on the hob and serves them as real items.
func _tick_cooking(delta: float) -> void:
	for stove in cooking.keys():
		cooking[stove]["left"] -= delta
		if cooking[stove]["left"] > 0.0:
			continue
		var c: Dictionary = cooking[stove]
		cooking.erase(stove)
		ev_cooking.rpc(stove, c["recipe"], false)
		var dish: Dictionary = Cooking.serve(model, stove, c["recipe"])
		if dish.is_empty():
			continue   # the stove was put away or the kitchen is full: nothing is served
		ev_item.rpc(dish)
		var pid := pid_of(c["peer"])
		if pid != "":
			model.cooked[pid] = int(model.cooked.get(pid, 0)) + 1
			ev_town_data.rpc("cooked", model.cooked)
		ev_cooked.rpc(stove, dish["id"], c["recipe"], nick_of(c["peer"]), c["peer"])
		_after_change()


func _srv_eat(peer: int, req: int, dish_id: String) -> void:
	var w := _where(peer)
	var err := Cooking.check_eat(model, str(dish_id), w["space"], w["pos"])
	if err == "" and locks.get(str(dish_id), 0) not in [0, peer]:
		err = "Someone else is using that."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var kind: String = model.items[str(dish_id)]["kind"]
	var r: Dictionary = model.remove(str(dish_id))
	if r.get("ok", false):
		ev_removed.rpc(r["removed"].map(func(i): return i["id"]))
		ev_ate.rpc(peer, kind)
		_after_change()
	_reply(peer, req, {"ok": r.get("ok", false), "kind": kind})


# ------------------------------------------------------------- play ideas (design/playability-8-12.md)

func _srv_snack(peer: int, req: int, tray_id: String, base: String, topping: String) -> void:
	var w := _where(peer)
	var err := PlayRules.check_snack(model, str(tray_id), str(base), str(topping), w["space"], w["pos"])
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var item: Dictionary = PlayRules.make_snack(model, str(tray_id), str(base), str(topping))
	if item.is_empty():
		_reply(peer, req, {"ok": false, "error": "There is no room for a snack here."})
		return
	ev_item.rpc(item)
	_after_change()
	_reply(peer, req, {"ok": true, "id": item["id"], "kind": item["kind"]})


## Sharing a snack: it is eaten, and everyone close by (the sharer too) cheers;
## outdoors the nearest animal friend dances along.
func _srv_share_snack(peer: int, req: int, snack_id: String) -> void:
	var w := _where(peer)
	var err := PlayRules.check_share(model, str(snack_id), w["space"], w["pos"])
	if err == "" and locks.get(str(snack_id), 0) not in [0, peer]:
		err = "Someone else is using that."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var it: Dictionary = model.items[str(snack_id)]
	var at := Vector2(it["x"], it["z"])
	var r: Dictionary = model.remove(str(snack_id))
	ev_removed.rpc(r["removed"].map(func(i): return i["id"]))
	var cheered := 0
	for p in players:
		var pw := _where(p)
		if pw["space"] == it["space"] and pw["pos"].distance_to(at) <= PlayRules.SHARE_REACH:
			ev_emote.rpc(p, "cheer")
			cheered += 1
	if it["space"] == "town" and Animals.brain:
		var best := ""
		var best_d := 12.0
		for a in Animals.brain.animals:
			var d: float = a["pos"].distance_to(at)
			if d < best_d:
				best_d = d
				best = a["kind"]
		if best != "":
			Animals.brain.celebrate(best, at, model)
	ev_snack_shared.rpc(peer, it["kind"], it["space"], at, nick_of(peer))
	_after_change()
	_reply(peer, req, {"ok": true, "kind": it["kind"], "cheered": cheered})


func _srv_face(peer: int, req: int, id: String) -> void:
	var err := _can_edit(peer, str(id))
	if err == "":
		err = _display_err(peer, PlayRules.item_space(model, str(id)))
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.next_variant(str(id))
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


## Puts a space on display or takes it off. Only from inside it; anyone may take
## it off (the client asks first), so nothing is ever locked for good.
func _srv_display(peer: int, req: int, space: String, on: bool) -> void:
	if _where(peer)["space"] != str(space) or not model.is_space(str(space)):
		_reply(peer, req, {"ok": false, "error": "Go there first."})
		return
	var now: bool = model.set_display(str(space), bool(on), pid_of(peer), nick_of(peer))
	share("display")
	_reply(peer, req, {"ok": true, "on": now})


## Fetch with Biscuit (F03): the child throws toward a spot outdoors.
func _srv_fetch(peer: int, req: int, x: float, z: float) -> void:
	var w := _where(peer)
	var err := ""
	var brain = Animals.brain
	if w["space"] != "town" or brain == null:
		err = "Play fetch outdoors with Biscuit."
	elif brain.dog().is_empty() or brain.dog()["pos"].distance_to(w["pos"]) > AnimalBrain.THROW_REACH:
		err = "Stand closer to Biscuit to play fetch."
	var land = null if err != "" else brain.throw_ball(model, peer, w["pos"], Vector2(float(x), float(z)))
	if err == "" and land == null:
		err = "They are already visiting a friend." if brain.dog().get("guest", 0) != 0 else "Biscuit is busy. Try again in a moment."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	Animals.ev_thrown.rpc(w["pos"], land)
	_reply(peer, req, {"ok": true, "x": land.x, "z": land.y})


# ------------------------------------------------------------- play ideas batch 2

## Dress-up (F07): a hat and clothes color, changed in town at any time.
func _srv_dress(peer: int, req: int, hat: String, outfit_color: int, outfit: int, prop: String) -> void:
	var av: Dictionary = players[peer]["avatar"].duplicate()
	av["hat"] = str(hat)
	av["outfit_color"] = int(outfit_color)
	if int(outfit) >= 0:
		av["outfit"] = int(outfit)
	if str(prop) != "-":
		av["prop"] = str(prop)
	# A procedural hat or prop chosen now replaces the worn head or hand item (and the reverse in _srv_wear).
	var worn: Dictionary = av.get("wear", {}).duplicate()
	if str(hat) != "":
		worn.erase("head")
	if str(prop) != "-" and str(prop) != "":
		worn.erase("hand")
	av["wear"] = worn
	av = Avatar.sanitize(av)
	players[peer]["avatar"] = av
	var pid := pid_of(peer)
	if model.roster.has(pid):
		model.roster[pid]["color"] = av["outfit_color"]
	ev_avatar.rpc(peer, av)
	_reply(peer, req, {"ok": true, "avatar": av})


## Trails (F06): start or stop following. Progress lives on the authority only.
func _srv_trail(peer: int, req: int, on: bool) -> void:
	if not bool(on):
		trail_walk.erase(peer)
		_reply(peer, req, {"ok": true, "on": false})
		return
	var err := PlayRules.check_follow(model, _where(peer)["space"])
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	trail_walk[peer] = 0
	ev_trail.rpc(peer, 0, model.trail_signs().size(), false, nick_of(peer))
	_reply(peer, req, {"ok": true, "on": true, "total": model.trail_signs().size()})


## An emote next to the next sign with its clue finds it; the last one finishes
## the trail and adds the child to the trail keepsake.
func _trail_emote(peer: int, kind: String) -> void:
	var w := _where(peer)
	var found: int = trail_walk[peer]
	var total: int = model.trail_signs().size()
	if found >= total:
		trail_walk.erase(peer)   # the trail got shorter while walking: it is done
		return
	if not PlayRules.trail_step(model, found, w["space"], w["pos"], kind):
		return
	found += 1
	var done := found >= total
	if done:
		trail_walk.erase(peer)
		PlayRules.add_keepsake(model, nick_of(peer), int(Time.get_unix_time_from_system()))
		share("keepsakes")
	else:
		trail_walk[peer] = found
	ev_trail.rpc(peer, found, total, done, nick_of(peer))


func _srv_music(peer: int, req: int, id: String, row: int, step: int) -> void:
	var w := _where(peer)
	var err := PlayRules.check_music(model, str(id), w["space"], w["pos"])
	if err == "":
		err = _display_err(peer, PlayRules.item_space(model, str(id)))
	var holder: int = music_parts.get(str(id), {}).get(int(row), 0)
	if err == "" and holder != 0 and holder != peer:
		err = "A friend is playing this part."
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.toggle_note(str(id), int(row), int(step))
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


## Start and stop are play, not decoration: allowed in a place on display too.
func _srv_music_play(peer: int, req: int, id: String, on: bool) -> void:
	var w := _where(peer)
	var err := PlayRules.check_music(model, str(id), w["space"], w["pos"])
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.set_music_on(str(id), bool(on))
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
		if on:
			Animals.enliven(str(id))   # a living town: music lovers come over
	_reply(peer, req, r)


## Toy tracks (F02): roll the ball from a start piece. One ball per start at a time.
func _srv_track(peer: int, req: int, start_id: String) -> void:
	var w := _where(peer)
	var start: Dictionary = model.items.get(str(start_id), {})
	var err := ""
	if start.is_empty() or start["kind"] != "track_start" or start.has("gift"):
		err = "That track start is not here."
	elif w["space"] != "town" or Vector2(start["x"], start["z"]).distance_to(w["pos"]) > 3.0:
		err = "Walk to the track start to roll the ball."
	elif Time.get_ticks_msec() < int(_track_busy.get(str(start_id), 0)):
		err = "The ball is still rolling."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var r: Dictionary = _roll(str(start_id), {"seen": {}, "steps": 0})
	_reply(peer, req, {"ok": true, "end": r["end"], "cells": r["cells"].size(), "bells": r["bells"].size()})


## Rolls the ball from a start piece (the caller checked it may). The bells, lights and finish it
## passes are contraption triggers: each sets off what stands near it as the ball goes by.
func _roll(start_id: String, chain: Dictionary) -> Dictionary:
	var r: Dictionary = TrackRules.route(model, start_id)
	var now := Time.get_ticks_msec()
	_track_busy[start_id] = now + int(r["cells"].size() * TrackRules.CELL_SECONDS * 1000.0)
	ev_track.rpc(start_id, r["cells"], r["end"], r["at"], r["bells"])
	for t in Contraptions.ball_triggers(model, r):
		_sparks.append({"at": now + int(t[0]), "id": t[1], "from": start_id, "chain": chain, "trigger": true})
	if not r["cells"].is_empty():
		Animals.watch_ball(r["cells"][-1])
	return r


# ------------------------------------------------------------- contraptions (authority)

func _srv_press(peer: int, req: int, id: String) -> void:
	var w := _where(peer)
	var err := Contraptions.check_press(model, str(id), w["space"], w["pos"])
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var fired := fire_trigger(str(id))
	_reply(peer, req, {"ok": true, "fired": fired, "linked": Contraptions.linked(model, str(id)).size()})


## Sets off a trigger: everyone sees it, and a spark leaves for each reactor near it. Returns false
## while the trigger is resting or when this chain has been here already. Setting things off is play,
## not decoration, so it also works in a place on display.
func fire_trigger(id: String, chain := {}) -> bool:
	var it: Dictionary = model.items.get(id, {})
	if it.is_empty() or it.has("gift") or not Contraptions.is_trigger(it["kind"]):
		return false
	var now := Time.get_ticks_msec()
	if now < int(_trigger_rest.get(id, 0)):
		return false
	if chain.is_empty():
		chain = {"seen": {}, "steps": 0}
	if chain["seen"].has(id):
		return false
	chain["seen"][id] = true
	_trigger_rest[id] = now + Contraptions.COOLDOWN_MS
	ev_trigger.rpc(id)
	_spread(id, chain, now)
	return true


func _spread(from: String, chain: Dictionary, now: int) -> void:
	for to in Contraptions.linked(model, from):
		if chain["seen"].has(to) or int(chain["steps"]) >= Contraptions.MAX_STEPS:
			continue
		chain["seen"][to] = true
		chain["steps"] = int(chain["steps"]) + 1
		_sparks.append({"at": now + Contraptions.HOP_MS, "id": to, "from": from, "chain": chain, "trigger": false})


func _tick_contraptions() -> void:
	if _sparks.is_empty():
		return
	var now := Time.get_ticks_msec()
	var due := _sparks.filter(func(s): return int(s["at"]) <= now)
	if due.is_empty():
		return
	_sparks = _sparks.filter(func(s): return int(s["at"]) > now)
	due.sort_custom(func(a, b): return int(a["at"]) < int(b["at"]))
	for s in due:
		if s["trigger"]:
			fire_trigger(s["id"], s["chain"])
		else:
			_react(s)


## A spark lands on a reactor: it does its thing (as the town is now) and passes the spark on.
func _react(s: Dictionary) -> void:
	var id: String = s["id"]
	var it: Dictionary = model.items.get(id, {})
	if it.is_empty() or it.has("gift"):
		return
	var effect := Contraptions.effect_of(it["kind"])
	var on := true
	match effect:
		"light":
			on = not bool(it.get("on", false))
			var r: Dictionary = model.set_lamp_on(id, on)
			if not r["ok"]:
				return
			ev_item.rpc(r["item"])
			_after_change()
		"music":
			on = not bool(it.get("on", false))
			var r: Dictionary = model.set_music_on(id, on)
			if not r["ok"]:
				return
			ev_item.rpc(r["item"])
			_after_change()
		"roll":
			if it["space"] != "town" or Time.get_ticks_msec() < int(_track_busy.get(id, 0)):
				return   # its ball is still rolling
			_roll(id, s["chain"])
		"spin", "bubbles":
			pass
		_:
			return
	ev_react.rpc(id, str(s["from"]), effect, on)
	if it["space"] == "town" and (effect in ["spin", "bubbles"] or (effect == "music" and on)):
		Animals.enliven(id)   # a living town: the ones who love it come over
	_spread(id, s["chain"], Time.get_ticks_msec())


## Someone (a child "p<peer>", or an animal outdoors) stands at `pos`: step pads they just stepped
## onto are set off. Authority only.
func step_on_pads(who: String, space: String, pos: Vector2) -> void:
	if not is_authority():
		return
	# Children and animals report where they stand many times a second: look through the town only
	# when it changed, and through a space only when it has a step pad at all.
	if _pad_spaces == null:
		_pad_spaces = {}
		for it in model.items.values():
			if it["kind"] == "step_pad":
				_pad_spaces[it["space"]] = true
	if not _pad_spaces.has(space):
		_on_pads.erase(who)
		return
	var now := {}
	for id in Contraptions.pads_under(model, space, pos):
		now[id] = true
		if not _on_pads.get(who, {}).has(id):
			fire_trigger(id)
	if now.is_empty():
		_on_pads.erase(who)
	else:
		_on_pads[who] = now


# ------------------------------------------------------------- the lamplighter walk (authority)

## A lamp post is lit or put out by hand. Play, not decoration: it works in a place on display, like
## a button's press. The lamp is the same as one a contraption switched: it shines by day and is saved.
func _srv_lamp(peer: int, req: int, id: String) -> void:
	var w := _where(peer)
	var err := Lamplight.check(model, str(id), w["space"], w["pos"])
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.set_lamp_on(str(id), not bool(model.items[str(id)].get("on", false)))
	if r["ok"]:
		ev_item.rpc(r["item"])
		r["on"] = bool(r["item"].get("on", false))
		r["lit"] = Lamplight.count(model)
		_after_change()
	_reply(peer, req, r)


## In the evening, the moment every lamp post in town is lit (by hand or by a contraption), the
## fireflies gather for everyone. Once per evening: putting a lamp out and lighting it again does
## not repeat it; the bell starts a new evening.
func _check_lamplight() -> void:
	if _lamplight_done or not model.evening or not Lamplight.all_lit(model):
		return
	_lamplight_done = true
	ev_lamplight.rpc(players.values().map(func(p): return p["avatar"]["nick"]))


# ------------------------------------------------------------- friend echoes (authority)

## Seconds since 1970 for echoes. Tests move it instead of waiting seven days.
var echo_clock_offset := 0

func echo_now() -> int:
	return int(Time.get_unix_time_from_system()) + echo_clock_offset


## Old echoes and echoes whose house is gone are dropped: when a town is loaded, when someone joins,
## after any edit, and every ten minutes while the town runs.
func prune_echoes() -> void:
	if not model.echoes.is_empty() and Echoes.prune(model, echo_now()):
		share("echoes")


var _echo_prune_t := 0.0

func _srv_echo_leave(peer: int, req: int, emotes) -> void:   # untyped: whatever a client sent is checked by the rules
	var st: Dictionary = players[peer]["state"]
	var r: Dictionary = Echoes.leave(model, pid_of(peer), players[peer]["avatar"], str(st.get("space", "town")),
		Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))), float(st.get("ry", 0.0)), emotes, echo_now())
	if r["ok"]:
		share("echoes")
	_reply(peer, req, r)


func _srv_echo_delete(peer: int, req: int) -> void:
	var had: bool = Echoes.remove(model, pid_of(peer))
	if had:
		share("echoes")
	_reply(peer, req, {"ok": true, "had": had})


func _srv_echo_answer(peer: int, req: int, owner_pid: String, emote: String) -> void:
	var w := _where(peer)
	var err := Echoes.check_answer(model, str(owner_pid), pid_of(peer), w["space"], w["pos"], echo_now())
	var r: Dictionary = {"ok": false, "error": err} if err != "" else Echoes.answer(model, str(owner_pid), pid_of(peer), nick_of(peer), str(emote), echo_now())
	if r["ok"]:
		share("echoes")
	_reply(peer, req, r)


func _srv_echo_seen(peer: int, req: int) -> void:
	if Echoes.mark_seen(model, pid_of(peer)):
		share("echoes")
	_reply(peer, req, {"ok": true})


# ------------------------------------------------------------- the picture board (authority)

## One square of a picture board. Like a music box's notes this changes what a child made, so it is
## refused in a place someone else put on display. One square per request: two children painting at
## once never overwrite each other's squares.
func _srv_pixel(peer: int, req: int, id: String, index: int, color: int) -> void:
	var w := _where(peer)
	var err := PictureBoard.check(model, str(id), w["space"], w["pos"])
	if err == "":
		err = _display_err(peer, PlayRules.item_space(model, str(id)))
	var r: Dictionary = {"ok": false, "error": err} if err != "" else model.set_pixel(str(id), int(index), int(color))
	if r["ok"]:
		ev_item.rpc(r["item"])
		_after_change()
	_reply(peer, req, r)


# ------------------------------------------------------------- puzzle rooms (authority)

## A key, a dial or the chest is used. Progress belongs to the space and to everyone in the town:
## whoever is there helps the same puzzle along. Using a puzzle is play, not decoration, so it also
## works in a place on display.
func _srv_puzzle(peer: int, req: int, id: String) -> void:
	var w := _where(peer)
	var err := Puzzles.check_use(model, str(id), w["space"], w["pos"])
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var space: String = model.items[str(id)]["space"]
	var st: Dictionary = Puzzles.sanitize(model, space, puzzles.get(space))
	var r: Dictionary = Puzzles.use(model, st, str(id), nick_of(peer))
	if r["ok"]:
		ev_puzzle.rpc(space, st)
		if r["what"] == "open":
			fire_trigger(str(id))   # an opened chest is a contraption trigger: lamps, music and bubbles near it answer
	r["progress"] = Puzzles.progress(model, space, st)
	_reply(peer, req, r)


## Starts the puzzle of the space the child stands in again: keys back, dials turned away, chest shut.
## Anyone there may, at any time, so a puzzle can always be replayed and nobody is ever stuck in one.
func _srv_puzzle_reset(peer: int, req: int, space: String) -> void:
	space = str(space)
	if _where(peer)["space"] != space or Puzzles.signature(model, space) == "":
		_reply(peer, req, {"ok": false, "error": Puzzles.ERR_NOT_HERE})
		return
	ev_puzzle.rpc(space, Puzzles.fresh(model, space))
	_reply(peer, req, {"ok": true})


## After any edit: a puzzle whose parts changed (placed, moved, painted, wrapped, put away) starts
## again as the town is now, so progress never points at parts that are gone or mean something else.
func _sync_puzzles() -> void:
	var now := {}
	for sp in Puzzles.spaces(model):
		now[sp] = Puzzles.signature(model, sp)
	for sp in now:
		if _puzzle_sig.get(sp, "") != now[sp]:
			_puzzle_sig[sp] = now[sp]
			if puzzles.has(sp):
				ev_puzzle.rpc(sp, Puzzles.fresh(model, sp))
	for sp in _puzzle_sig.keys():
		if not now.has(sp):
			_puzzle_sig.erase(sp)
			if puzzles.has(sp):
				ev_puzzle.rpc(sp, {})


## A child left a space (or the town). An opened chest with nobody left at it shuts and its puzzle
## starts again, so the next visitor finds it ready. A half-solved puzzle is left as it is.
func _puzzle_left(space: String) -> void:
	for sp in puzzles.keys():
		if (space == "" or sp == space) and bool(puzzles[sp].get("open", false)):
			if not players.values().any(func(p): return str(p["state"].get("space", "town")) == sp):
				_broadcast_open(&"ev_puzzle", [sp, Puzzles.fresh(model, sp)])


# ------------------------------------------------------------- rideable carts (authority)

## What every device needs to draw a cart: who rides, the route and how far along it is now.
func _ride_wire(id: String) -> Dictionary:
	var r: Dictionary = rides.get(id, {})
	if r.is_empty():
		return {}
	return {"peer": r["peer"], "phase": r["phase"], "route": r["route"], "s": ride_distance(id), "end": r["end"], "why": r["why"]}


func _send_ride(id: String) -> void:
	ev_ride.rpc(id, _ride_wire(id))


## Get in, go or stop. The seat is an ordinary seat (seats, ev_seats), so everything that already
## protects a seated child holds: the station cannot be moved or put away under them, and getting up,
## sitting elsewhere or leaving the town frees the cart.
func _srv_ride(peer: int, req: int, id: String, what: String) -> void:
	id = str(id)
	var r: Dictionary = rides.get(id, {})
	match str(what):
		"board":
			var w := _where(peer)
			var err := RideRules.check_board(model, id, w["space"], w["pos"])
			if err == "" and locks.get(id, 0) != 0:
				err = "Someone else is using that."
			if err == "" and not seats.get(id, {}).values().all(func(p): return p == peer):
				err = RideRules.ERR_TAKEN
			if err != "":
				_reply(peer, req, {"ok": false, "error": err})
				return
			if r.is_empty():
				_free_seats_of(peer)   # one seat per child: leaving a bench or another cart first
				seats[id] = {0: peer}
				ev_seats.rpc(_seats_snapshot())
				var route: Dictionary = RideRules.route(model, id)
				rides[id] = {"peer": peer, "phase": "ready", "route": route, "s": 0.0, "end": RideRules.end_distance(route),
					"t": Time.get_ticks_msec(), "why": ""}
				_send_ride(id)
			_reply(peer, req, {"ok": true, "end": rides[id]["route"]["end"], "pieces": rides[id]["route"]["legs"].size()})
		"go":
			if r.is_empty() or int(r["peer"]) != peer:
				_reply(peer, req, {"ok": false, "error": RideRules.ERR_NOT_RIDING})
				return
			if r["phase"] == "moving":
				_reply(peer, req, {"ok": true})
				return
			if r["why"] == "broken":
				_reply(peer, req, {"ok": false, "error": RideRules.ERR_BROKEN})
				return
			var route: Dictionary = RideRules.route(model, id)
			var s := float(r["s"])
			var end := RideRules.end_distance(route) if r["phase"] == "ready" else RideRules.rebased_end(route, s, float(r["end"]) - s)
			var err := RideRules.go_error(route, s)
			if err == "" and s >= end - 0.01:
				err = RideRules.ERR_END
			if err != "":
				_reply(peer, req, {"ok": false, "error": err, "at": route["at"]})
				return
			r["route"] = route
			r["end"] = end
			r["phase"] = "moving"
			r["why"] = ""
			r["sig"] = s
			r["t"] = Time.get_ticks_msec()
			_send_ride(id)
			_reply(peer, req, {"ok": true, "loop": route["loop"], "pieces": route["legs"].size()})
		"stop":
			if r.is_empty() or int(r["peer"]) != peer:
				_reply(peer, req, {"ok": false, "error": RideRules.ERR_NOT_RIDING})
				return
			if r["phase"] == "moving":
				r["s"] = ride_distance(id)
				r["phase"] = "stopped"
				r["t"] = Time.get_ticks_msec()
				_send_ride(id)
			_reply(peer, req, {"ok": true})
		_:
			_reply(peer, req, {"ok": false, "error": RideRules.ERR_NOT_HERE})


## A cart that reached the end of its ride stops by itself: at its station after the last lap of a
## circuit (ready to go again), or at the last piece of an open track.
func _tick_rides() -> void:
	for id in rides.keys():
		var r: Dictionary = rides[id]
		if r["phase"] == "moving":
			# Signal rails the cart passed since the last look set off what stands near them.
			var now_at := ride_distance(id)
			for sig in RideRules.signals_between(r["route"], float(r.get("sig", r["s"])), now_at):
				fire_trigger(sig)
			r["sig"] = now_at
		if r["phase"] != "moving" or ride_distance(id) < float(r["end"]) - 0.001:
			continue
		var at_station: bool = r["route"]["loop"] and absf(fposmod(float(r["end"]) + 0.01, RideRules.total_length(r["route"])) - 0.01) < 0.02
		r["phase"] = "ready" if at_station else "stopped"
		r["s"] = 0.0 if at_station else float(r["end"])
		r["end"] = RideRules.end_distance(r["route"]) if at_station else float(r["end"])
		r["why"] = "lap" if at_station else str(r["route"]["end"])
		r["t"] = Time.get_ticks_msec()
		_send_ride(id)


## After any edit: every cart that is out follows the rails as they are now. A piece added ahead is
## ridden; a piece taken away ahead ends the ride before the gap; and when the piece under the cart
## itself is gone or turned, the cart stops where it is until its rider gets off.
func _reroute_rides() -> void:
	for id in rides.keys():
		var r: Dictionary = rides[id]
		var route: Dictionary = RideRules.route(model, id)
		if route["legs"] == r["route"]["legs"] and route["end"] == r["route"]["end"] and r["why"] != "broken":
			continue
		var s := ride_distance(id)
		var now := Time.get_ticks_msec()
		var on_new := RideRules.rebase(r["route"], s, route)
		if on_new < 0.0:
			r["s"] = s
			r["end"] = s
			r["phase"] = "stopped"
			r["why"] = "broken"   # the old route is kept: it still says where the cart stands
		elif r["phase"] == "ready":
			r["route"] = route
			r["s"] = 0.0
			r["end"] = RideRules.end_distance(route)
		else:
			r["end"] = RideRules.rebased_end(route, on_new, float(r["end"]) - s)
			r["route"] = route
			r["s"] = on_new
			r["why"] = ""   # the rails under the cart are part of a route again
		r["t"] = now
		r["sig"] = float(r["s"])   # signals are counted from where the cart is on the new route
		_send_ride(id)


# ------------------------------------------------------------- r12: wardrobe

## The authority checks every item against the accepted catalog (gated and unknown ids are
## refused), applies the slot conflicts, and shares the new look like any dress-up change.
func _srv_wear(peer: int, req: int, slot: String, id: String) -> void:
	var av: Dictionary = players[peer]["avatar"].duplicate(true)
	var r: Dictionary = Wearables.equip(av.get("wear", {}), str(slot), str(id))
	if not r["ok"]:
		_reply(peer, req, {"ok": false, "error": r["error"]})
		return
	av["wear"] = r["wear"]
	if r["wear"].has("head"):
		av["hat"] = ""
	if r["wear"].has("hand"):
		av["prop"] = ""
	av = Avatar.sanitize(av)
	players[peer]["avatar"] = av
	ev_avatar.rpc(peer, av)
	_reply(peer, req, {"ok": true, "avatar": av})


# ------------------------------------------------------------- r11: invitations, animal games, weather toys, blueprints

## Where a player would go to join them: their space and spot.
func _invite_spot(peer: int) -> Dictionary:
	var w := _where(peer)
	return {"space": w["space"], "at": w["pos"]}


func _srv_invite(peer: int, req: int, kind: String, target: String) -> void:
	var now := int(Time.get_unix_time_from_system())
	var w := _where(peer)
	var pid := pid_of(peer)
	var owner: String = model.display_by(w["space"]).get("pid", "") if str(kind) == "help" else ""
	# The cooldown only stops repeating the same invitation; a different one goes out
	# at once and (one card per inviter) replaces the earlier card.
	var key := "%s|%s" % [str(kind), str(target).left(64)]
	var last: Dictionary = _last_invite.get(peer, {})
	var err := Invites.check(str(kind), w["space"], players.size() - 1, int(last.get(key, -99)), now, owner, pid)
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	_last_invite[peer] = {key: now}
	var c: Dictionary = Invites.card(pid, nick_of(peer), str(kind), str(target).left(64), w["space"], w["pos"], now)
	var sent := 0
	for other in players:
		if other == peer or other == 0:
			continue
		Invites.add(inbox.get_or_add(other, {}), c)
		if other == my_id and mode != "server":
			invited.emit(c)
		elif _open_peers().has(other):
			ev_invite.rpc_id(other, c)
		sent += 1
	_reply(peer, req, {"ok": true, "sent": sent})


## Join takes the friend to the inviter (the client walks there); for "help" it
## also lets them edit the place on display. Not now just closes the card.
func _srv_invite_reply(peer: int, req: int, from_pid: String, answer: String) -> void:
	var c: Dictionary = inbox.get(peer, {}).get(str(from_pid), {})
	var pid := pid_of(peer)
	if str(answer) == "leave":
		for sp in model.display:
			if model.display[sp]["pid"] == str(from_pid):
				model.set_helper(sp, pid, false)
		share("display")
		_reply(peer, req, {"ok": true})
		return
	if c.is_empty() or int(Time.get_unix_time_from_system()) - int(c["t"]) > Invites.LIFETIME:
		inbox.get(peer, {}).erase(str(from_pid))
		_reply(peer, req, {"ok": false, "error": "That invitation has ended."})
		return
	inbox[peer].erase(str(from_pid))
	if str(answer) != "join":
		_reply(peer, req, {"ok": true, "joined": false})
		return
	if c["kind"] == "help":
		if model.display_by(c["space"]).get("pid", "") != c["from"]:
			_reply(peer, req, {"ok": false, "error": "That place is not on display any more."})
			return
		model.set_helper(c["space"], pid, true)
		share("display")
	var inviter := peer_of_pid(str(from_pid))
	if inviter == my_id and mode != "server":
		invite_joined.emit(nick_of(peer), c["kind"])
	elif inviter != 0 and _open_peers().has(inviter):
		ev_invite_joined.rpc_id(inviter, nick_of(peer), c["kind"])
	_reply(peer, req, {"ok": true, "joined": true, "card": c})


## An animal's own game (F03): Wooly, Bramble, Pip or Tumble plays with the child.
func _srv_animal_visit(peer: int, req: int, kind: String, on: bool) -> void:
	var w := _where(peer)
	var err: String = Animals.request_visit(peer, str(kind), bool(on), w["space"], w["pos"])
	_reply(peer, req, {"ok": err == "", "error": err, "kind": str(kind), "on": bool(on)})


func _srv_animal_ride(peer: int, req: int, kind: String, on: bool) -> void:
	var err: String = Animals.request_ride(peer, str(kind), bool(on))
	_reply(peer, req, {"ok": err == "", "error": err, "kind": str(kind), "on": bool(on)})


func _srv_animal_play(peer: int, req: int, kind: String, option: int) -> void:
	var w := _where(peer)
	var brain = Animals.brain
	var err := ""
	var a := {}
	if brain != null:
		for x in brain.animals:
			if x["kind"] == str(kind):
				a = x
	if w["space"] != "town" or brain == null or a.is_empty() or not AnimalBrain.GAMES.has(str(kind)):
		err = "Play with the animals outdoors."
	elif a.get("guest", 0) != 0:
		err = "They are already visiting a friend."
	elif a["pos"].distance_to(w["pos"]) > 10.0:
		err = "Walk closer to play together."
	var target = null
	var target_id := ""
	if err == "" and str(kind) == "rabbit":
		var bed := _nearest(w["pos"], func(i): return i["kind"] == "garden_bed" and not i.has("gift"), 15.0)
		if bed.is_empty():
			err = "Bramble needs a garden bed nearby. There is one in the toy box."
		else:
			target_id = bed["id"]
			target = Vector2(bed["x"], bed["z"]) + (w["pos"] - Vector2(bed["x"], bed["z"])).normalized() * 1.0
	if err == "" and str(kind) == "pig":
		var water := _nearest_water(w["pos"])
		if not water.is_empty():
			target = water["center"] + (w["pos"] - water["center"]).normalized() * (water["radius"] + 0.6)
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var result: String = brain.play_with(model, str(kind), peer, w["pos"], int(option), target, target_id)
	if result == "":
		_reply(peer, req, {"ok": false, "error": "Everyone is at the party!"})
		return
	_reply(peer, req, {"ok": true, "result": result})


## Authority: Bramble finished tending a bed (the brain asks; it never edits the town).
func grow_by_animal(id: String) -> void:
	if not is_authority() or not model.items.has(id):
		return
	var r: Dictionary = model.grow(id)
	if r.get("ok", false):
		ev_item.rpc(r["item"])
		_after_change()


func _nearest(at: Vector2, pick: Callable, within: float) -> Dictionary:
	var best := {}
	var best_d := within
	for it in model.items_in("town"):
		if pick.call(it) and Vector2(it["x"], it["z"]).distance_to(at) <= best_d:
			best_d = Vector2(it["x"], it["z"]).distance_to(at)
			best = it
	return best


## The nearest water outdoors: a pond, or a puddle while it rains. {center, radius} or {}.
func _nearest_water(at: Vector2, within := 15.0) -> Dictionary:
	var pond := _nearest(at, func(i): return i["kind"] == "pond", within)
	var out := {}
	if not pond.is_empty():
		out = {"center": Vector2(pond["x"], pond["z"]), "radius": 1.6, "id": pond["id"]}
	if model.weather == "rain":
		for p in TownModel.PUDDLES:
			if p.distance_to(at) < within and (out.is_empty() or p.distance_to(at) < out["center"].distance_to(at)):
				out = {"center": p, "radius": 0.5, "id": ""}
	return out


## Paper boats (F04): a boat next to water sails a lap and comes back.
func _srv_boat(peer: int, req: int, id: String) -> void:
	var it: Dictionary = model.items.get(str(id), {})
	var w := _where(peer)
	var err := ""
	if it.is_empty() or it["kind"] != "paper_boat" or it.has("gift"):
		err = "That boat is not here."
	elif w["space"] != "town" or Vector2(it["x"], it["z"]).distance_to(w["pos"]) > 3.0:
		err = "Walk to the boat to sail it."
	var water := {} if err != "" else _nearest_water(Vector2(it["x"], it["z"]), 3.6)
	if err == "" and water.is_empty():
		err = "Put the boat next to a pond (or a puddle when it rains) to sail it."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	ev_boat.rpc(str(id), water["center"], water["radius"])
	_reply(peer, req, {"ok": true})


## Leaf piles (F04): jump in; two friends within a few seconds make a big burst.
func _srv_leaves(peer: int, req: int, id: String) -> void:
	var it: Dictionary = model.items.get(str(id), {})
	var w := _where(peer)
	if it.is_empty() or it["kind"] != "leaf_pile" or it.has("gift") or w["space"] != "town" \
			or Vector2(it["x"], it["z"]).distance_to(w["pos"]) > 2.4:
		_reply(peer, req, {"ok": false, "error": "Walk to the leaf pile to jump in."})
		return
	var now := Time.get_ticks_msec()
	var last: Array = _leaf_jumps.get(str(id), [0, -99999])
	var together: bool = last[0] != peer and now - int(last[1]) < 4000
	_leaf_jumps[str(id)] = [peer, now]
	ev_emote.rpc(peer, "cheer")
	ev_leaves.rpc(str(id), peer, together)
	_reply(peer, req, {"ok": true, "together": together})


## Blueprints (F09): the pieces go in one by one with the normal rules; what does
## not fit is skipped and reported. The group can then be changed piece by piece.
func _srv_blueprint(peer: int, req: int, space: String, pieces: Array) -> void:
	var err := ""
	if _where(peer)["space"] != str(space) or not model.is_space(str(space)):
		err = "Go there first."
	elif str(space) == TownModel.ZOO:
		err = TownModel.ERR_NOT_ZOO   # blueprints are not offered in the zoo
	elif pieces.is_empty() or pieces.size() > Blueprints.MAX_PIECES or not pieces.all(func(p): return p is Dictionary):
		err = "That blueprint is empty."
	if err == "":
		err = _display_err(peer, str(space))
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	var r: Dictionary = Blueprints.apply(model, str(space), pieces)
	for item in r["placed"]:
		ev_item.rpc(item)
	if not r["placed"].is_empty():
		_after_change()
	_reply(peer, req, {"ok": not r["placed"].is_empty(), "error": "" if not r["placed"].is_empty() else "None of it fits here.",
		"ids": r["placed"].map(func(i): return i["id"]), "skipped": r["errors"].filter(func(e): return e != "").size()})


## Music parts (F08): a child may take one sound row of a box as "my part"; the
## others leave it to them until they let go or leave. Taking a part is optional.
func _srv_music_part(peer: int, req: int, id: String, row: int) -> void:
	var w := _where(peer)
	var err := PlayRules.check_music(model, str(id), w["space"], w["pos"])
	if err == "" and (int(row) < 0 or int(row) >= PlayRules.SOUNDS.size()):
		err = "That part is not in the music box."
	var parts: Dictionary = music_parts.get_or_add(str(id), {})
	var holder: int = parts.get(int(row), 0)
	if err == "" and holder != 0 and holder != peer:
		err = "A friend is playing this part."
	if err != "":
		_reply(peer, req, {"ok": false, "error": err})
		return
	if holder == peer:
		parts.erase(int(row))
	else:
		parts[int(row)] = peer
	_send_parts(str(id))
	_reply(peer, req, {"ok": true, "mine": holder != peer})


func _send_parts(id: String) -> void:
	var named := {}
	for row in music_parts.get(id, {}):
		named[row] = nick_of(music_parts[id][row])
	ev_music_parts.rpc(id, named)


## A suggested starter trail (F06): three signs by the Wishing Tree, the bell and
## a pond, with different clues, when the town has fewer than two signs.
func _srv_starter_trail(peer: int, req: int) -> void:
	if model.trail_signs().size() >= PlayRules.MIN_TRAIL:
		_reply(peer, req, {"ok": false, "error": "There is a trail already. Follow it, or move its signs."})
		return
	var spots := [TownModel.WISHING_TREE + Vector2(3.2, 2.0), TownModel.WISHING_TREE + Vector2(-4.0, 3.5), TownModel.WISHING_TREE + Vector2(1.0, 7.0)]
	var pond := _nearest(TownModel.WISHING_TREE, func(i): return i["kind"] == "pond", 30.0)
	if not pond.is_empty():
		spots[2] = Vector2(pond["x"], pond["z"]) + Vector2(0, 3.0)
	var placed := []
	var clue := 0
	for sp in spots:
		if model.free_trail_number() == 0:
			break
		var at = model.find_free_spot("trail_sign", "town", sp)
		if at == null:
			continue
		var r: Dictionary = model.place("trail_sign", "town", at.x, at.y, 0)
		if r["ok"]:
			model.items[r["item"]["id"]]["variant"] = [0, 2, 3][clue % 3]
			clue += 1
			placed.append(model.items[r["item"]["id"]].duplicate(true))
	for it in placed:
		ev_item.rpc(it)
	if not placed.is_empty():
		_after_change()
	_reply(peer, req, {"ok": placed.size() >= PlayRules.MIN_TRAIL, "count": placed.size(),
		"error": "" if placed.size() >= PlayRules.MIN_TRAIL else "There is no room for a trail right now."})


@rpc("authority", "call_remote", "reliable")
func ev_invite(c: Dictionary) -> void:
	invited.emit(c)


@rpc("authority", "call_remote", "reliable")
func ev_invite_joined(nick: String, kind: String) -> void:
	invite_joined.emit(nick, kind)


@rpc("authority", "call_local", "reliable")
func ev_boat(id: String, center: Vector2, radius: float) -> void:
	boat_sailed.emit(id, center, radius)


@rpc("authority", "call_local", "reliable")
func ev_leaves(id: String, peer: int, together: bool) -> void:
	leaves_jumped.emit(id, peer, together)


@rpc("authority", "call_local", "reliable")
func ev_music_parts(id: String, parts: Dictionary) -> void:
	_part_names[id] = parts
	music_parts_changed.emit(id, parts)


var _part_names := {}   # music box id -> {row: nick} (every device)

func music_part_names(id: String) -> Dictionary:
	return _part_names.get(id, {})


@rpc("authority", "call_local", "reliable")
func ev_avatar(peer: int, av: Dictionary) -> void:
	if players.has(peer):
		players[peer]["avatar"] = Avatar.sanitize(av)
	avatar_changed.emit(peer)


@rpc("authority", "call_local", "reliable")
func ev_trail(peer: int, found: int, total: int, done: bool, nick: String) -> void:
	trail_changed.emit(peer, found, total, done, nick)


@rpc("authority", "call_local", "reliable")
func ev_trigger(id: String) -> void:
	contraption_triggered.emit(id)


@rpc("authority", "call_local", "reliable")
func ev_react(id: String, from: String, effect: String, on: bool) -> void:
	contraption_reacted.emit(id, from, effect, on)


@rpc("authority", "call_local", "reliable")
func ev_lamplight(by: Array) -> void:
	lamplight.emit(by)


## A space's puzzle progress ({} = it has no puzzle parts any more).
@rpc("authority", "call_local", "reliable")
func ev_puzzle(space: String, st: Dictionary) -> void:
	var was: Dictionary = puzzles.get(space, {})
	if st.is_empty():
		puzzles.erase(space)
	else:
		puzzles[space] = st if is_authority() else Puzzles.sanitize(model, space, st)
	puzzle_changed.emit(space, st, was)


## A cart's ride ({} = home and empty). Each device keeps its own clock for "s".
@rpc("authority", "call_local", "reliable")
func ev_ride(id: String, ride: Dictionary) -> void:
	if ride.is_empty():
		rides.erase(id)
	elif is_authority():
		pass   # the authority's own record is the truth; this call only tells its own screen
	else:
		var route: Dictionary = ride.get("route", {}) if typeof(ride.get("route")) == TYPE_DICTIONARY else {}
		rides[id] = {"peer": int(ride.get("peer", 0)), "phase": str(ride.get("phase", "ready")),
			"route": {"legs": Array(route.get("legs", [])), "end": str(route.get("end", "end")), "at": route.get("at", Vector2.ZERO),
				"loop": bool(route.get("loop", false))},
			"s": float(ride.get("s", 0.0)), "end": float(ride.get("end", 0.0)), "t": Time.get_ticks_msec(), "why": str(ride.get("why", ""))}
	ride_changed.emit(id, rides.get(id, {}))


@rpc("authority", "call_local", "reliable")
func ev_track(start_id: String, cells: Array, end: String, at: Vector2, bells: Array) -> void:
	track_rolled.emit(start_id, cells, end, at, bells)


## Shares one piece of town-level activity data with everyone (authority only).
func share(key: String) -> void:
	if is_authority():
		ev_town_data.rpc(key, model.get(key))
		_mark_dirty()


@rpc("authority", "call_local", "reliable")
func ev_town_data(key: String, value: Variant) -> void:
	if key in ["roster", "wishes", "weather", "hearts", "visits", "photo_ideas", "pets", "cooked", "starter", "display", "keepsakes", "echoes", "maps"]:
		if key == "maps" and typeof(value) != TYPE_DICTIONARY:
			return
		if not is_authority():
			model.set(key, Echoes.sanitize(value) if key == "echoes" else value)
		town_data_changed.emit(key)


@rpc("authority", "call_local", "reliable")
func ev_gift_opened(id: String, from_nick: String, by_peer: int) -> void:
	gift_opened.emit(id, from_nick, by_peer)


@rpc("authority", "call_local", "reliable")
func ev_cooking(stove_id: String, recipe: String, on: bool) -> void:
	if not is_authority():
		if on:
			cooking[stove_id] = {"recipe": recipe}
		else:
			cooking.erase(stove_id)
	cooking_changed.emit(stove_id, recipe, on)


@rpc("authority", "call_local", "reliable")
func ev_cooked(stove_id: String, dish_id: String, recipe: String, nick: String, by_peer: int) -> void:
	cooked.emit(stove_id, dish_id, recipe, nick, by_peer)


@rpc("authority", "call_local", "reliable")
func ev_ate(peer: int, kind: String) -> void:
	ate.emit(peer, kind)


@rpc("authority", "call_local", "reliable")
func ev_snack_shared(peer: int, kind: String, space: String, at: Vector2, nick: String) -> void:
	snack_shared.emit(peer, kind, space, at, nick)


@rpc("authority", "call_local", "reliable")
func ev_pet_happy(owner_pid: String, pet_id: String, action: String, nick: String) -> void:
	pet_happy.emit(owner_pid, pet_id, action, nick)


# ------------------------------------------------------------- RPC: authority -> clients
# call_local lets solo and host devices render the same events as clients.

@rpc("authority", "call_remote", "reliable")
func ev_welcome(peer: int, town: Dictionary, snapshot: Dictionary, lock_map: Dictionary, seat_map: Dictionary) -> void:
	my_id = peer
	model = TownModel.new()
	model.from_dict(town)
	my_pid = snapshot.get(peer, {}).get("pid", "")
	players = snapshot
	locks = lock_map
	seats = seat_map
	puzzles.clear()   # puzzles under way and carts that are out arrive right after the town
	rides.clear()
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
func ev_player_joined(peer: int, avatar: Dictionary, s: Dictionary, pid := "") -> void:
	if not is_authority():
		players[peer] = {"avatar": avatar, "state": s, "pid": pid}
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
