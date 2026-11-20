## Local player brain: walking, tapping, context actions and decorating.
##
## Touch first: tap the ground to walk, tap a door, swing or bench to use it.
## In decorate mode, tap an item to pick it up, drag it, turn it, paint it and
## confirm. Keyboard shortcuts exist for desktop testing only.
extends Node

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Props := preload("res://scripts/art/props.gd")
const Kit := preload("res://scripts/art/mesh_kit.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const ItemQuery := preload("res://scripts/ui/item_query.gd")
const Cooking := preload("res://scripts/core/cooking.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")
const PlayRules := preload("res://scripts/core/play_rules.gd")
const Blueprints := preload("res://scripts/core/blueprints.gd")
const Contraptions := preload("res://scripts/core/contraptions.gd")
const Puzzles := preload("res://scripts/core/puzzles.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")
const Lamplight := preload("res://scripts/core/lamplight.gd")
const Echoes := preload("res://scripts/core/echoes.gd")
const Places := preload("res://scripts/core/places.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")
const CityOrbit := preload("res://scripts/world/city_orbit.gd")
const ThousandPlay := preload("res://scripts/world/thousand_play.gd")

signal context_changed(ctx: Dictionary)
signal mode_changed(mode: String)
signal ghost_changed(info: Dictionary)   # {} when nothing is being placed or edited
signal hint(text: String)
signal toast(text: String)
signal confirm_remove(item: Dictionary, contents: int)
signal space_changed(space: String)
signal undo_changed(available: bool)
signal item_placed(kind: String)             # a new item of this kind landed (Recent)
signal choose_item(ids: Array, screen: Vector2)   # a tap hit several items: ask which one
## Ask the HUD to open an activity panel: "wish", "photo_ideas", "guest_book".
signal open_panel(panel: String, data: Dictionary)
## Decorating a place someone else put on display: the HUD asks first (F10).
signal ask_display(space: String, by: Dictionary)
## A blueprint preview changed (F09): {} when none, else {"name", "fits", "total"}.
signal blueprint_changed(info: Dictionary)
## The tram journey (design/zoo-and-world-journeys.md 12.3): phase "start", "done" or "failed".
signal journey(phase: String, to: String)
## Look (11.1): the zoo animal this child is looking at ("" when none).
signal look_changed(id: String)

const WALK_SPEED := 3.4
const TAP_SLOP := 14.0
const GHOST_SNAP := 0.25

var world: Node3D
var rig: Node3D
var mode := "play"
var space := "town"
var pos := Vector2.ZERO
var ry := PI
var walking := false
var enabled := true
var pad_move := Vector2.ZERO   # the game controller's left stick (pad_input.gd), deadzoned, length <= 1

var _walk_target: Variant = null
var _stall_t := 0.0                   # thousand-town: seconds the walk has made no progress
const THOUSAND_STALL := 0.5
var _pending_ctx := {}
var _ctx := {}
var _send_t := 0.0
var _party_t := 0.0
var _last_sent := {}
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _requests := {}            # req id -> Callable(result)
var fetch_mode := false        # playing fetch with Biscuit: a ground tap throws the ball (F03)
var journey_to := ""
## city r1: the level the child stands on in the city (a CityMap region or stair id; "" = the ground), the
## route being walked (waypoints {"region","pos"}), the gesture under the finger, and the seat or machine held.
var level := ""
var _city_route: Array = []
var _city_gesture: Dictionary = {}
var city_hold: Dictionary = {}
## city r2, Look: while on, a tap glides the camera to a building, shop or ride (or back to the overview on
## empty space) instead of walking; Esc, B or the Look button ends it. Pause (only while looking) freezes the
## city's people, rides and traffic on this screen. The child stays, visible, and keeps its action button.
var city_looking := false
var city_paused := false
signal city_look_changed(on: bool)           # the map a journey is going to ("" when not travelling)
## thousand-town: Look in Thousand Town (the camera flies to an overview of the whole town and back).
var thousand_looking := false
signal thousand_look_changed(on: bool)
## A press in Thousand Town: where it began and whether it became an orbit (a drag beyond TAP_SLOP).
var _t_press := Vector2.ZERO
var _t_pressed := false
var _t_orbiting := false
## Thousand Town's interactions (world/thousand_play.gd): meeting and following residents, the bus, the wheel, the
## night market, the shows. A child of this node; the HUD reads its chip and card.
var thousand_play: Node
## How near a door (m) offers "Who's here?", and how near the station's back the tram home.
const THOUSAND_DOOR_REACH := 2.0
const THOUSAND_TRAVEL_REACH := 2.5
var _journey_t0 := 0.0
var _journey_from := ""        # the map the journey left (asked for again on a timeout)
var _journey_elapsed := 0.0    # game time on the journey: a pause in the background does not count
var look_id := ""              # the zoo animal being looked at
const JOURNEY_MIN := 1.2       # the card shows at least this long (12.3)
const JOURNEY_TIMEOUT := 8.0   # then the tram "could not leave" (12.4)
const LOOK_REACH := 3.5
const LOOK_END := 9.0
## A blueprint being placed (F09): {"bp", "at", "rot", "plan", "errors", "nodes"}; {} when none.
var bp := {}
var _undo: Array = []

# Placement ghost
var ghost: Node3D
var _ghost_ring: MeshInstance3D
var g_kind := ""
var g_pos := Vector2.ZERO
var g_rot := 0
var g_color := 0
var g_edit_id := ""            # editing an existing item when not empty
var g_error := ""
## Table the ghost sits on ("" = floor). Only tabletop-eligible items can have one.
var g_host := ""
var _g_orig := {}


func _ready() -> void:
	thousand_play = ThousandPlay.new()
	thousand_play.name = "ThousandPlay"
	add_child(thousand_play)
	thousand_play.setup(self)
	thousand_play.changed.connect(_refresh_context)
	Session.request_done.connect(_on_request_done)
	# Every request is preceded by the child's present state (one ordered stream: the authority reads the state
	# first). Before, only the city's actions did this (_city_do); the kitchen's Cook did not.
	Session.before_request.connect(func(_method: String):
		if world != null:
			_send_state())
	Session.joined.connect(_on_joined)
	# dest-fix r1: arriving where nothing can be decorated (a city) ends decorate mode (back in play).
	space_changed.connect(func(s: String):
		if mode == "decorate" and not Places.decoratable(s):
			set_mode("play"))
	for path in ["/root/City", "/root/CityWeb"]:
		var city := get_node_or_null(path)
		if city:
			# city r1: the wheel brings this child back to the platform; a friend's order or purchase pops.
			# city-web: the same for the web city (each City instance's effects reach only its own map).
			var city_map: String = Places.CITY_WEB if path == "/root/CityWeb" else Places.CITY
			city.effect.connect(func(kind: String, data: Dictionary):
				if kind == "ride_off" and int(data.get("peer", 0)) == Session.my_id:
					city_ride_off(data.get("pos", CityMap.FERRIS["board_at"]), str(data.get("region", "")))
				elif kind in ["order", "shop"] and int(data.get("peer", 0)) != Session.my_id and space == city_map:
					Sfx.play("pop"))
	Session.connection_changed.connect(func(st):
		if st in ["disconnected", "failed", "offline"] and journey_to != "":
			_journey_failed(""))
	Session.seats_changed.connect(_refresh_context)
	Session.puzzle_changed.connect(func(_s, _st, _was): _refresh_context())
	Session.ride_changed.connect(func(_id, _ride): _refresh_context())


func setup(w: Node3D, r: Node3D) -> void:
	world = w
	rig = r
	world.view_changed.connect(_on_view_changed)


func _on_joined(_id: int) -> void:
	var s: Dictionary = Session.players.get(Session.my_id, {}).get("state", {})
	pos = Vector2(s.get("x", 0.0), s.get("z", 9.0))
	ry = s.get("ry", PI)
	space = "town"
	if journey_to != "":
		_journey_failed("")   # the card goes; a new session always starts in town
	journey_to = ""
	end_look()
	if rig.on_zoo:
		rig.leave_zoo()   # a new session always starts in town (9.2)
	if rig.on_city:
		rig.leave_city()
	thousand_end_all()
	if rig.on_thousand:
		rig.leave_thousand()
	_end_thousand_look()
	level = ""
	_city_route = []
	city_hold = {}
	if city_looking:
		city_looking = false
		city_paused = false
		city_look_changed.emit(false)
	_undo.clear()
	undo_changed.emit(false)
	set_mode("play")
	world.set_view("town")
	_place_kid()
	rig.target = world.local_kid()
	rig.set_room(false)


func _ask(req: int, cb: Callable) -> void:
	if req > 0:
		_requests[req] = cb


func _on_request_done(req: int, result: Dictionary) -> void:
	if _requests.has(req):
		var cb: Callable = _requests[req]
		_requests.erase(req)
		cb.call(result)


# ------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or world == null or world.local_kid() == null:
		return
	if space == Places.CITY_WEB:
		return   # city-web: the page takes the input (web_tap, web_act, ...); Godot's own window does not walk the child
	if space == Places.CITY and mode == "play" and _city_input(event):
		return
	if space == Places.THOUSAND and mode == "play" and _thousand_input(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			_dragging = ghost != null and _near_ghost(event.position)
		else:
			if _pressed and not _dragging and event.position.distance_to(_press_pos) < TAP_SLOP:
				_tap(event.position)
			_pressed = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressed and _dragging:
		_drag_ghost(event.position)

	elif event is InputEventMagnifyGesture:
		if rig.on_zoo:
			if event.factor > 1.0:
				rig.zoom_in()
			elif event.factor < 1.0:
				rig.zoom_out()
		elif (event.factor > 1.0 and rig.zoom == 1) or (event.factor < 1.0 and rig.zoom == 0):
			rig.toggle_zoom()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if rig.on_zoo:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				rig.zoom_in()
			else:
				rig.zoom_out()
		elif (event.button_index == MOUSE_BUTTON_WHEEL_UP) == (rig.zoom == 1):
			rig.toggle_zoom()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


## A finger already dragging the item keeps dragging it when it passes over the menus: otherwise the
## placement tools and the toy box take its motion, the item stops under them and the tools never move
## away (Mac dock check, iPad Air bottom_edge). Only a drag that started on the item is kept; menu taps
## and everything else go through the normal input path.
func _input(event: InputEvent) -> void:
	if not _dragging or ghost == null or not enabled:
		return
	if event is InputEventMouseMotion and _pressed:
		_drag_ghost(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_pressed = false
		_dragging = false
		get_viewport().set_input_as_handled()


func _key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_Q: rig.rotate_step(-1)
		KEY_E: rig.rotate_step(1)
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				if Places.decoratable(space):
					undo()   # unified r6: never a town placement undone from Thousand Town or a city
			else:
				rig.toggle_zoom()
		KEY_R: turn_ghost()
		KEY_ENTER, KEY_KP_ENTER: confirm_ghost()
		KEY_ESCAPE:
			if space == Places.CITY and city_looking:
				set_city_look(false)
			elif thousand_looking:
				set_thousand_look(false)
			elif space == Places.THOUSAND and thousand_play.back():
				pass   # thousand-town: closes the resident card, or ends following, waiting or watching
			else:
				cancel_ghost()
		KEY_SPACE:
			if not _ctx.is_empty():
				do_context()
		KEY_1: Session.send_emote("wave")
		KEY_2: Session.send_emote("cheer")
		KEY_3: Session.send_emote("dance")
		KEY_4: Session.send_emote("heart")


func _tap(screen: Vector2) -> void:
	var cam: Camera3D = rig.camera
	if space == Places.CITY and mode == "play":
		_city_tap(screen)
		return
	if space == Places.THOUSAND and mode == "play":
		_thousand_tap(screen)
		return
	if mode == "decorate" and not bp.is_empty():
		var gp = world.ground_point(cam, screen)
		if gp != null:
			move_blueprint(gp)
		return
	if mode == "decorate":
		var choices: Array = ItemQuery.tap_choices(world.pick_candidates(cam, screen))
		var id: String = choices[0] if not choices.is_empty() else ""
		if ghost and (id == "" or id == g_edit_id or choices.has(g_edit_id)):
			var gp = world.ground_point(cam, screen)
			if gp != null:
				_move_ghost_to(gp)
			return
		if choices.size() > 1 and ghost == null:
			# Several things under the finger and none clearly closest: ask, never guess.
			Sfx.play("tap")
			choose_item.emit(choices, screen)
			return
		if id != "" and ghost == null:
			select_item(id)
			return
	else:
		var pet: Dictionary = world.pet_layer.pick(cam, screen)
		if not pet.is_empty():
			Sfx.play("tap")
			open_panel.emit("pet", pet)
			return
		# An animal friend visiting a house (r18): it hops and shows its card (Say goodbye).
		var guest: String = world.guest_layer.pick(cam, screen) if space != "town" else ""
		if guest != "":
			world.guest_layer.guests[guest].react()
			Sfx.play("tap")
			open_panel.emit("guest", {"kind": guest})
			return
		if space == Places.ZOO:
			var zid: String = world.pick_animal(cam, screen)
			if zid != "":
				Sfx.play("tap")
				start_look(zid)
				return
			var zgp = world.ground_point(cam, screen)
			if zgp != null:
				for c in _zoo_contexts():
					if (zgp as Vector2).distance_to(c["at"]) < 1.2:
						if pos.distance_to(c["at"]) < 1.6:
							do_context(c)
						else:
							_walk_to(c["at"], c)
						return
		var animal: String = world.pick_animal(cam, screen) if space != Places.ZOO else ""
		if animal == "dog" and fetch_mode:
			animal = ""   # playing fetch: a tap near Biscuit still throws
		if animal != "":
			# Tapping an animal friend: it reacts and shows its wish, or its favorite game.
			world.animals[animal].react()
			Sfx.play("tap")
			if Session.model.wishes.get("active", {}).get("animal", "") == animal:
				open_panel.emit("wish", Session.model.wishes["active"])
			elif animal == "dog":
				open_panel.emit("fetch", {})
			elif AnimalBrain.GAMES.has(animal):
				open_panel.emit("animal", {"kind": animal})
			else:
				var def: Dictionary = AnimalBrain.SPECIES[animal]
				toast.emit(tr(def["hobby"]) % tr(def["name"]))
			return
		var mark: String = world.activity.pick(cam, screen) if space == "town" else ""
		if mark != "":
			var ctx := _landmark_context(mark)
			if pos.distance_to(ctx["at"]) < 1.6:
				do_context(ctx)
			else:
				_walk_to(ctx["at"], ctx)
			return
		if Places.is_room(space):
			var gp = world.ground_point(cam, screen)
			if gp != null:
				for c in portal_contexts():
					if gp.distance_to(c["at"]) < 1.0:
						_walk_to(c["at"], c)
						return
		var id: String = world.pick_item(cam, screen)
		if id != "":
			var ctx := _context_for_item(id, true)
			if not ctx.is_empty():
				if pos.distance_to(ctx["at"]) < 1.6:
					do_context(ctx)
				else:
					_walk_to(ctx["at"], ctx)
				return
	if _seated():
		return
	var gp = world.ground_point(cam, screen)
	if gp != null and fetch_mode and mode == "play" and space == "town":
		throw_ball(gp)
		return
	if gp != null:
		_walk_to(gp, {})


## Join an invitation (F10): go to the friend's place and walk next to them.
func travel_to(target_space: String, at: Vector2) -> void:
	_prepare_walk()
	if Places.map_of(target_space) != Places.map_of(space) and Places.map_of(target_space) != "":
		# Another map: the tram picks the child up, then it walks to the friend (12.5).
		ride(Places.map_of(target_space), func(): travel_to(target_space, at))
		return
	if target_space != space:
		if target_space == "town":
			exit_house()
		elif Session.model.is_space(target_space):
			go_to_room(target_space)
		else:
			return
	var near: Vector2 = at + (pos - at).normalized() * 1.2 if pos.distance_to(at) > 1.2 else pos
	_walk_to(world.resolve_walk(near), {})


# ------------------------------------------------------------- blueprints (F09)

## Starts placing a saved blueprint: a preview in front of the child; a ground
## tap moves it, Turn turns it a quarter, Place puts in every piece that fits.
func begin_blueprint(blueprint: Dictionary) -> void:
	cancel_ghost()
	cancel_blueprint()
	if mode != "decorate":
		set_mode("decorate")
		if mode != "decorate":
			return   # the place is on display: the HUD asks first
	bp = {"bp": blueprint, "rot": int(roundf(ry / (TAU / 8.0))) % 8 / 2 * 2, "nodes": [],
		"at": world.resolve_walk(pos + Vector2(sin(ry), cos(ry)) * 2.5)}
	_refresh_blueprint()


func move_blueprint(at: Vector2) -> void:
	if bp.is_empty():
		return
	bp["at"] = Vector2(snappedf(at.x, GHOST_SNAP), snappedf(at.y, GHOST_SNAP))
	_refresh_blueprint()


func turn_blueprint() -> void:
	if bp.is_empty():
		return
	bp["rot"] = posmod(int(bp["rot"]) + 2, 8)
	_refresh_blueprint()


func _refresh_blueprint() -> void:
	for n in bp["nodes"]:
		n.queue_free()
	bp["nodes"] = []
	bp["plan"] = Blueprints.plan(bp["bp"], bp["at"], bp["rot"])
	bp["errors"] = Blueprints.preview(Session.model, space, bp["plan"])
	for i in bp["plan"].size():
		var p: Dictionary = bp["plan"][i]
		var holder := Node3D.new()
		world.add_child(holder)
		var model := Props.build(p["kind"], p["color"], 999, 3, int(p["variant"]))
		model.rotation.y = TownModel.rot_to_radians(p["rot"])
		holder.add_child(model)
		var r: float = Catalog.get_def(p["kind"])["radius"]
		var ring := MeshInstance3D.new()
		ring.mesh = Kit.torus(r * 0.92, r + 0.08)
		ring.scale = Vector3(1, 0.25, 1)
		ring.position.y = 0.04
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("#7fc77a") if bp["errors"][i] == "" else Color("#ef6f86")
		ring.material_override = m
		holder.add_child(ring)
		var y := 0.0
		if int(p["on"]) >= 0 and int(p["on"]) < i:
			y = Catalog.support_surface(bp["plan"][p["on"]]["kind"]).get("local_position", Vector3.ZERO).y
		holder.position = Vector3(p["x"], y, p["z"])
		bp["nodes"].append(holder)
	blueprint_changed.emit({"name": bp["bp"].get("name", ""), "fits": bp["errors"].count(""), "total": bp["plan"].size()})


func place_blueprint() -> void:
	if bp.is_empty():
		return
	var planned: Array = bp["plan"]
	var where := space
	_ask(Session.place_blueprint(where, planned), func(r):
		if r.get("ok"):
			Sfx.play("place")
			_push_undo({"type": "blueprint", "ids": r["ids"]})
			toast.emit(tr("Placed %d things.") % r["ids"].size() if int(r.get("skipped", 0)) == 0 \
				else tr("Placed %d things; %d did not fit.") % [r["ids"].size(), int(r["skipped"])])
		elif r.get("error", "") != "":
			hint.emit(r["error"]))
	cancel_blueprint()


func cancel_blueprint() -> void:
	if bp.is_empty():
		return
	for n in bp["nodes"]:
		n.queue_free()
	bp = {}
	blueprint_changed.emit({})


## Fetch with Biscuit: turn toward the spot and throw; Biscuit runs and brings it back.
func start_fetch() -> void:
	if space != "town":
		return
	set_mode("play")
	fetch_mode = true
	_refresh_context()
	hint.emit("Tap the ground to throw the ball for Biscuit.")


func stop_fetch() -> void:
	fetch_mode = false
	_refresh_context()


func throw_ball(at: Vector2) -> void:
	if at.distance_to(pos) > 0.3:
		ry = atan2(at.x - pos.x, at.y - pos.y)
		_place_kid()
	walking = false
	_walk_target = null
	Sfx.play("pop")
	_ask(Session.throw_ball(at), func(r):
		if r.get("ok"):
			Session.send_emote("wave")
		elif r.get("error", "") != "":
			hint.emit(r["error"]))


func stop_for_workshop() -> void:
	_walk_target = null
	_pending_ctx = {}
	pad_move = Vector2.ZERO
	walking = false
	Sfx.play("tram")


func _walk_to(p: Vector2, then: Dictionary) -> void:
	_walk_target = p
	_pending_ctx = then


# ------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if world == null or world.local_kid() == null:
		return
	var kid: Node3D = world.local_kid()
	var move := Vector2.ZERO
	rig.reduce_motion = world.reduce_motion
	_check_journey()
	_check_look()
	if Places.is_city(space):
		_city_frame(kid)
	if space == Places.THOUSAND and journey_to == "":
		thousand_play.frame(delta, kid)   # thousand-town: following, the bus, the wheel, the shows
	if enabled and journey_to == "" and not _seated() and not _city_busy() and not _thousand_busy():
		var kb := Vector2(
			Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
			Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up"))
		for k in [[KEY_D, Vector2.RIGHT], [KEY_A, Vector2.LEFT], [KEY_S, Vector2.DOWN], [KEY_W, Vector2.UP]]:
			if Input.is_physical_key_pressed(k[0]) and not Input.is_key_pressed(KEY_CTRL):
				kb += k[1]
		if space == Places.CITY_WEB:
			kb = Vector2.ZERO   # city-web: only the page's taps walk the child (its camera is not Godot's)
		if kb.length() > 0.1:
			_walk_target = null
			_thousand_manual()
			move = (rig.flat_right() * kb.x - rig.flat_forward() * kb.y).normalized()
		elif pad_move != Vector2.ZERO and space != Places.CITY_WEB:
			_walk_target = null   # the stick walks at the speed it is pushed
			_thousand_manual()
			move = (rig.flat_right() * pad_move.x - rig.flat_forward() * pad_move.y).limit_length(1.0)
		elif _walk_target != null:
			var d: Vector2 = _walk_target - pos
			var stop := 0.9 if not _pending_ctx.is_empty() and _city_route.is_empty() else 0.08
			if d.length() <= stop and not _city_route.is_empty():
				_walk_target = (_city_route.pop_front() as Dictionary)["pos"]   # the next waypoint of a city route
			elif d.length() <= stop:
				_walk_target = null
				if not _pending_ctx.is_empty():
					var ctx := _pending_ctx
					_pending_ctx = {}
					do_context(ctx)
			else:
				move = d.normalized()
	# The camera glides to an item being placed, and holds completely still while a
	# finger drags it, so the item stays under the finger and the menus do not jump.
	rig.follow = ghost
	rig.hold = _dragging and ghost != null
	walking = move.length() > 0.01
	if walking:
		var before := pos
		if Places.is_city(space):
			# city r1: walls, railings, stairs and floors (CityNav); the level follows the walk.
			var stepped := CityNav.step(level, pos, pos + move * WALK_SPEED * delta)
			pos = stepped["pos"]
			level = stepped["region"]
		elif space == Places.THOUSAND:
			pos = world.resolve_thousand(pos, pos + move * WALK_SPEED * delta)   # slides along walls and the canal
		else:
			pos = world.resolve_walk(pos + move * WALK_SPEED * delta)
		var stalled := before.distance_to(pos) < WALK_SPEED * delta * 0.15
		# thousand-town: Thousand Town's walls slide the child along them, and a step that grazes an edge can stall
		# for a frame or two before the slide carries on (the loop tour: a tap on Courtyard Housing, a walk to a
		# market counter, both stopped dead at once). There a walk ends only after THOUSAND_STALL s without progress.
		_stall_t = _stall_t + delta if stalled else 0.0
		if _walk_target != null and stalled and (space != Places.THOUSAND or _stall_t >= THOUSAND_STALL):
			_walk_target = null   # Blocked: stop instead of pushing forever.
		ry = lerp_angle(ry, atan2(move.x, move.y), minf(1.0, delta * 12.0))
	if _city_busy():
		pass   # held on a seat or machine, or riding the wheel: _city_frame placed the child
	elif _thousand_busy():
		pass   # thousand-town: on the bus or the ferris wheel, thousand_play placed the child
	elif not _seated():
		kid.anim = "walk" if walking else "idle"
		kid.walk_speed = WALK_SPEED
		_place_kid()
	else:
		var cart := Session.ride_of(Session.my_id)
		if cart != "" and world.ride_fx:
			# Riding: where this child is, for friends, saves of nothing, and for stepping off, is where the cart is.
			var p: Dictionary = world.ride_fx.pose_of(cart)
			pos = p["pos"]
			ry = atan2(p["dir"].x, p["dir"].y)
	# At a dance party near the Wishing Tree everyone dances along.
	if Activities.is_party() and space == "town" and not walking and not _seated() and pos.distance_to(TownModel.WISHING_TREE) < 9.0:
		_party_t -= delta
		if _party_t <= 0.0:
			_party_t = 1.8
			Session.send_emote("dance")
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		_send_state()
	_refresh_context()


func _place_kid() -> void:
	var kid: Node3D = world.local_kid()
	if kid and not _seated():
		var y := CityNav.height(level, pos) if Places.is_city(space) else 0.0
		if space == Places.THOUSAND:
			y = world.thousand_height(pos)
		kid.position = Vector3(pos.x, y, pos.y)
		kid.rotation = Vector3(0, ry, 0)


func _send_state() -> void:
	var seat := Session.seat_of(Session.my_id)
	var anim := "walk" if walking else "idle"
	if not seat.is_empty():
		var kid: Node3D = world.local_kid()
		anim = kid.anim if kid else "sit"
	if (Places.is_city(space) and _city_busy()) or _thousand_busy():
		var kid2: Node3D = world.local_kid()
		anim = kid2.anim if kid2 else "sit"
	var s := {"space": space, "x": snappedf(pos.x, 0.01), "z": snappedf(pos.y, 0.01), "ry": snappedf(ry, 0.01), "anim": anim}
	if Places.is_city(space) and level != "":
		s["level"] = level
	if s != _last_sent:
		_last_sent = s
		Session.send_state(s)


func _seated() -> bool:
	return not Session.seat_of(Session.my_id).is_empty()


# ------------------------------------------------------------- context actions

func _context_for_item(id: String, from_tap := false) -> Dictionary:
	var item: Dictionary = Session.model.items.get(id, {})
	if item.is_empty() or item["space"] != space:
		return {}
	var def := Catalog.get_def(item["kind"])
	if item["kind"] == "cottage":
		var door := TownModel.door_point(item)
		return {"type": "enter", "id": id, "label": "Go inside", "icon": "door", "at": door}
	if item["kind"] == "tram_stop":
		var board: Variant = TownModel.tram_stop_boarding(Session.model)
		var stop := {"type": "tram", "id": id, "label": "Ride to the zoo", "icon": "tram", "at": board if board != null else Vector2(item["x"], item["z"] + 1.6),
			"alt": {"type": "tram_city", "label": "Ride to the city", "icon": "tram"}}
		if Places.available(Places.CITY_WEB):
			# city-web: the third journey, only on a device that can show the web city.
			stop["alt2"] = {"type": "tram_city_web", "label": "Ride to the city (web)", "icon": "tram"}
		if Places.available(Places.THOUSAND):
			# thousand-town: the fourth journey, offered on every device (the TV too).
			stop["alt3"] = {"type": "tram_thousand", "label": "Ride to Thousand Town", "icon": "tram"}
		return stop
	var here := Vector2(item["x"], item["z"])
	var near: Vector2 = here + TownModel.facing(item["rot"]) * (def["radius"] + 0.4)
	if item.has("gift"):
		var g: Dictionary = item["gift"]
		if g.get("to", "") == "" or g.get("to", "") == Session.my_pid:
			return {"type": "unwrap", "id": id, "label": "Open the present", "icon": "gift", "at": near if from_tap else here}
		return {}
	if item["kind"] == "garden_bed":
		return {"type": "water", "id": id, "label": "Water", "icon": "water", "at": near if from_tap else here}
	if item["kind"] == "kitchen_stove":
		return {"type": "cook", "id": id, "label": "Cook", "icon": "cook", "at": near if from_tap else here}
	if Cooking.DISHES.has(item["kind"]):
		return {"type": "eat", "id": id, "label": "Eat", "icon": "cook", "at": near if from_tap else here}
	if item["kind"] == "snack_tray":
		return {"type": "snack", "id": id, "label": "Make a snack", "icon": "cook", "at": near if from_tap else here}
	if PlayRules.is_snack(item["kind"]):
		return {"type": "share_snack", "id": id, "label": "Share", "icon": "cheer", "at": near if from_tap else here}
	if item["kind"] == "snowman":
		return {"type": "face", "id": id, "label": "Change face", "icon": "paint", "at": near if from_tap else here}
	if item["kind"] == "track_start":
		return {"type": "track", "id": id, "label": "Roll the ball", "icon": "play", "at": near if from_tap else here}
	if item["kind"] == "push_button":
		return {"type": "press", "id": id, "label": "Press", "icon": "play", "at": near if from_tap else here}
	if item["kind"] == "picture_board":
		return {"type": "board", "id": id, "label": "Paint a picture", "icon": "paint", "at": near if from_tap else here}
	if item["kind"] == Lamplight.KIND:
		var lit: bool = bool(item.get("on", false))
		return {"type": "lamp", "id": id, "label": "Put out the lamp" if lit else "Light the lamp", "icon": "lantern", "at": near if from_tap else here}
	if item["kind"] == Puzzles.KEY:
		if Session.puzzle_state(space)["found"].has(id):
			return {}   # already at the chest
		return {"type": "puzzle", "id": id, "label": "Pick up the key", "icon": "key", "at": near if from_tap else here}
	if item["kind"] == Puzzles.DIAL:
		return {"type": "puzzle", "id": id, "label": "Turn the dial", "icon": "turn", "at": near if from_tap else here}
	if item["kind"] == Puzzles.CHEST:
		return {"type": "puzzle_chest", "id": id, "label": "Treasure chest", "icon": "gift", "at": near if from_tap else here}
	if item["kind"] == RideRules.STATION:
		if Session.rides.has(id):
			return {}   # a friend is riding this cart
		return {"type": "ride_board", "id": id, "label": "Get in the cart", "icon": "sit", "at": here}
	if item["kind"] == "track_switch":
		return {"type": "face", "id": id, "label": "Flip the switch", "icon": "turn", "at": near if from_tap else here}
	if item["kind"] == "trail_sign":
		return {"type": "trail_sign", "id": id, "label": tr("Trail sign %d") % int(item.get("num", 1)), "icon": "wave", "at": near if from_tap else here}
	if item["kind"] == "music_box":
		return {"type": "music", "id": id, "label": "Play music", "icon": "music", "at": near if from_tap else here}
	if item["kind"] == "paper_boat":
		return {"type": "boat", "id": id, "label": "Sail the boat", "icon": "water", "at": near if from_tap else here}
	if item["kind"] == "leaf_pile":
		return {"type": "leaves", "id": id, "label": "Jump in!", "icon": "cheer", "at": near if from_tap else here}
	if Catalog.seats(item["kind"]) > 0:
		var p := Vector2(item["x"], item["z"])
		var front: Vector2 = p + TownModel.facing(item["rot"]) * (def["radius"] + 0.4)
		return {"type": "sit", "id": id, "label": def["action"], "icon": "sit", "at": front if from_tap else p}
	return {}


func _landmark_context(mark: String) -> Dictionary:
	var at: Vector2 = world.activity.point(mark)
	match mark:
		"bell":
			return {"type": "bell", "id": "bell", "label": "Evening" if not Session.model.evening else "Morning", "icon": "bell", "at": at}
		"drum":
			return {"type": "landmark", "id": mark, "label": "Party!", "icon": "drum", "at": at}
		"vane":
			return {"type": "landmark", "id": mark, "label": "Change the weather", "icon": "weather", "at": at}
		"stump":
			return {"type": "landmark", "id": mark, "label": "Hide and seek", "icon": "acorn", "at": at}
		_:
			return {"type": "landmark", "id": mark, "label": "Photo ideas", "icon": "board", "at": at}


## Activity actions that outrank everything else nearby.
func _activity_context() -> Dictionary:
	var hs: Dictionary = Activities.hs
	if hs.get("phase") == "hiding" and hs.get("hider") == Session.my_id:
		return {"type": "hide_here", "label": "Hide the acorn here", "icon": "acorn"}
	if hs.get("phase") == "seeking" and hs.get("hider") != Session.my_id and world.activity.acorn_visible():
		var spot: Dictionary = Activities.near_acorn if not Activities.near_acorn.is_empty() else hs.get("acorn", {})
		if spot.get("space", "") == space and pos.distance_to(Vector2(spot["x"], spot["z"])) < Activities.FIND_DISTANCE:
			return {"type": "find_acorn", "label": "Pick up the acorn!", "icon": "acorn"}
	return {}


func _refresh_context() -> void:
	var ctx := {}
	if mode == "play" and world:
		var act := _activity_context()
		if not act.is_empty():
			ctx = act
		elif fetch_mode and space == "town":
			ctx = {"type": "stop_fetch", "label": "Stop fetch", "icon": "close"}
		elif Session.ride_of(Session.my_id) != "":
			# In a cart: one big button to go or stop, and Get off beside it at any time.
			var cart := Session.ride_of(Session.my_id)
			var off := {"type": "stand", "label": "Get off", "icon": "stand"}
			if Session.rides[cart]["phase"] == "moving":
				ctx = {"type": "ride_stop", "id": cart, "label": "Stop", "icon": "close", "alt": off}
			else:
				ctx = {"type": "ride_go", "id": cart, "label": "Go!", "icon": "play", "alt": off}
		elif _seated():
			ctx = {"type": "stand", "label": "Get up", "icon": "stand"}
		elif Places.is_city(space):
			ctx = _city_context()
		elif space == Places.THOUSAND:
			ctx = _thousand_context()
		elif space == Places.ZOO:
			var best := 2.0
			for c in _zoo_contexts():
				var d := pos.distance_to(c["at"])
				if d < 1.8 and d < best:
					best = d
					ctx = c
			for item in Session.model.items_in(space):
				var c := _context_for_item(item["id"])
				if c.is_empty():
					continue
				var d := pos.distance_to(c["at"])
				if d < Catalog.get_def(item["kind"])["radius"] + 1.1 and d < best:
					best = d
					ctx = c
		elif space == "town":
			var best := 2.0
			for mark in world.activity.LANDMARKS:
				var c := _landmark_context(mark)
				var d := pos.distance_to(c["at"])
				if d < 1.6 and d < best:
					best = d
					ctx = c
			for item in Session.model.items_in("town"):
				var c := _context_for_item(item["id"])
				if c.is_empty():
					continue
				var reach: float = 1.6 if c["type"] == "enter" else Catalog.get_def(item["kind"])["radius"] + 1.1
				var d := pos.distance_to(c["at"])
				if d < reach and d < best:
					best = d
					ctx = c
		else:
			var best := 2.0
			var room := TownModel.parse_room(space)
			if room.get("floor", -1) == 0 and room.get("room", -1) == 0 and pos.distance_to(world.activity.GUEST_BOOK) < 1.6:
				ctx = {"type": "guest_book", "label": "Guest book", "icon": "book", "at": world.activity.GUEST_BOOK}
				best = pos.distance_to(world.activity.GUEST_BOOK)
			for c in portal_contexts():
				var d := pos.distance_to(c["at"])
				if d < 1.6 and d < best:
					best = d
					ctx = c
			for item in Session.model.items_in(space):
				var c := _context_for_item(item["id"])
				if c.is_empty():
					continue
				var d := pos.distance_to(c["at"])
				if d < Catalog.get_def(item["kind"])["radius"] + 1.0 and d < best:
					best = d
					ctx = c
			# An empty Kitchen, Game room or Pet room offers its starter set once.
			if ctx.is_empty():
				var setup := RoomThemes.setup_label(Session.model, space)
				if setup != "":
					ctx = {"type": "setup", "label": setup, "icon": "decorate"}
	# A friend's hello (or the child's own) right here, when nothing else is in reach.
	if ctx.is_empty() and mode == "play" and world and not _seated():
		var owner: String = Echoes.near(Session.model, space, pos, 1.8)
		if owner != "":
			var mine: bool = owner == Session.my_pid
			ctx = {"type": "echo", "id": owner, "label": "Your hello" if mine else "Answer the hello", "icon": "wave"}
	var key := func(c: Dictionary): return [c.get("type"), c.get("id"), c.get("label"), (c.get("alt", {}) as Dictionary).get("type"),
		(c.get("alt", {}) as Dictionary).get("id")]
	if key.call(ctx) != key.call(_ctx):
		_ctx = ctx
		context_changed.emit(ctx)


## The second action of the current context (in a cart: Get off), if it has one.
func do_context_alt() -> void:
	var alt: Dictionary = _ctx.get("alt", {})
	if not alt.is_empty():
		do_context(alt)


## city-web: the third action of the current context (the tram stop's Ride to the city (web)), if it has one.
func do_context_alt2() -> void:
	var alt2: Dictionary = _ctx.get("alt2", {})
	if not alt2.is_empty():
		do_context(alt2)


## thousand-town: the fourth action of the current context (the tram stop's Ride to Thousand Town).
func do_context_alt3() -> void:
	var alt3: Dictionary = _ctx.get("alt3", {})
	if not alt3.is_empty():
		do_context(alt3)


func do_context(ctx: Dictionary = {}) -> void:
	if ctx.is_empty():
		ctx = _ctx
	match ctx.get("type", ""):
		"enter": enter_house(ctx["id"])
		"exit": exit_house()
		"portal": go_to_room(ctx["target"])
		"sit":
			_ask(Session.sit(ctx["id"]), func(r):
				if r.get("ok"):
					walking = false
					_walk_target = null
				elif r.get("error", "") != "":
					toast.emit(r["error"]))   # e.g. both seats of a bench are taken
		"stand": stand_up()
		"bell":
			world.activity.mark_discovered("bell")
			Session.ring_bell()
		"landmark": _use_landmark(ctx["id"])
		"unwrap": Session.unwrap(ctx["id"])
		"water":
			Sfx.play("pop")
			Session.water(ctx["id"])
		"guest_book":
			open_panel.emit("guest_book", {"house": TownModel.house_of(space)})
		"hide_here":
			Activities.hide_here()
		"find_acorn":
			Activities.find_acorn()
		"cook":
			open_panel.emit("cook", {"stove": ctx["id"]})
		"eat":
			_ask(Session.eat(ctx["id"]), func(r):
				if r.get("ok"):
					Session.send_emote("cheer"))
		"stop_fetch":
			stop_fetch()
		"track":
			Sfx.play("tap")
			_ask(Session.roll_track(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"]))
		"press":
			_ask(Session.press(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"])
				elif r.get("ok") and r.get("fired") and int(r.get("linked", 0)) == 0:
					hint.emit("Nothing is close enough yet. Put a lamp, a music box or a pinwheel within two steps."))
		"puzzle":
			_ask(Session.use_puzzle(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"])
				elif r.get("ok") and r.get("progress", {}).get("ready", false):
					hint.emit("The chest is unlocked! Go and open it."))
		"lamp":
			_ask(Session.toggle_lamp(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"])
				elif r.get("ok") and r.get("on"):
					Sfx.play("lantern"))
		"echo":
			open_panel.emit("echo", {"owner": ctx["id"]})
		"board":
			open_panel.emit("board", {"id": ctx["id"]})
		"puzzle_chest":
			open_panel.emit("puzzle", {"id": ctx["id"]})
		"ride_board":
			_ask(Session.ride(ctx["id"], "board"), func(r):
				if r.get("ok"):
					walking = false
					_walk_target = null
				elif r.get("error", "") != "":
					toast.emit(r["error"]))
		"ride_go":
			Sfx.play("tap")
			_ask(Session.ride(ctx["id"], "go"), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"]))
		"ride_stop":
			Sfx.play("tap")
			Session.ride(ctx["id"], "stop")
		"trail_sign":
			open_panel.emit("trail_sign", {"id": ctx["id"]})
		"boat":
			Sfx.play("tap")
			_ask(Session.sail_boat(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"]))
		"leaves":
			_ask(Session.jump_in_leaves(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"]))
		"music":
			open_panel.emit("music", {"id": ctx["id"]})
		"snack":
			open_panel.emit("snack", {"tray": ctx["id"]})
		"share_snack":
			Sfx.play("pop")
			Session.share_snack(ctx["id"])
		"face":
			Sfx.play("tap")
			_ask(Session.change_face(ctx["id"]), func(r):
				if not r.get("ok") and r.get("error", "") != "":
					hint.emit(r["error"]))
		"tram":
			ride(Places.ZOO)
		"tram_city":
			ride(Places.CITY)
		"tram_city_web":
			ride(Places.CITY_WEB)
		"tram_thousand":
			ride(Places.THOUSAND)
		"thousand_inspect":
			Sfx.play("tap")
			open_panel.emit("thousand_inspect", {"id": ctx["id"]})
		"tt_hello", "tt_wait", "tt_board", "tt_bus_off", "tt_wheel", "tt_wheel_off", "tt_snack":
			thousand_play.do(ctx)
		"city_use", "city_board", "city_off", "city_release":
			_city_do(ctx)
		"tram_home":
			ride(Places.TOWN)
		"zoo_station":
			var zoo := get_node_or_null("/root/Zoo")
			if zoo:
				_ask(zoo.use(ctx["id"]), func(r):
					if not r.get("ok", false) and str(r.get("error", "")) != "":
						hint.emit(r["error"]))
		"setup":
			Sfx.play("pop")
			_ask(Session.furnish_room(space), func(r):
				if r.get("ok"):
					toast.emit("All set up! Tap Decorate to change anything."))


## Context actions for the doorways and stairs of the current room.
func portal_contexts() -> Array:
	var out := []
	for p in TownModel.portals(space):
		if p["kind"] == "exit":
			out.append({"type": "exit", "label": "Go outside", "icon": "door", "at": p["at"]})
		else:
			out.append({"type": "portal", "target": p["target"], "label": p["label"], "at": p["at"],
				"icon": {"up": "stairs_up", "down": "stairs_down"}.get(p["kind"], "door")})
	return out


## Enters a cottage through its front door into the ground-floor living room.
## Tapping a landmark's name tag: walk over and use it.
func walk_to_landmark(mark: String) -> void:
	if mark == "tram_stop":   # the stop's "Zoo tram" tag: walk to it and ride (zoo design 9.1)
		var sctx := _context_for_item(Session.model.tram_stop_id(), true)
		if sctx.is_empty():
			return
		if pos.distance_to(sctx["at"]) < 1.6:
			do_context(sctx)
		else:
			_walk_to(sctx["at"], sctx)
		return
	var ctx := _landmark_context(mark)
	if pos.distance_to(ctx["at"]) < 1.6:
		do_context(ctx)
	else:
		_walk_to(ctx["at"], ctx)


## Walks next to a landmark without using it (the activity guide's "Go there"):
## its action button appears on arrival and the child decides.
func walk_near_landmark(mark: String) -> void:
	if space != "town":
		return
	_prepare_walk()
	var at: Vector2 = world.activity.point(mark)
	_walk_to(at + (pos - at).normalized() * 1.0 if pos.distance_to(at) > 1.0 else pos, {})


## Walks to the nearest cottage door without going in.
func walk_to_door() -> void:
	if space != "town":
		return
	var best = null
	for item in Session.model.items_in("town"):
		if item["kind"] == "cottage":
			var d := TownModel.door_point(item)
			if best == null or pos.distance_to(d) < pos.distance_to(best):
				best = d
	if best != null:
		_prepare_walk()
		_walk_to(best, {})


func _prepare_walk() -> void:
	if mode != "play":
		set_mode("play")
	if _seated():
		stand_up()


func _use_landmark(mark: String) -> void:
	world.activity.mark_discovered(mark)
	Sfx.play("tap")
	match mark:
		"drum": Activities.start_party()
		"vane":
			_ask(Session.change_weather(), func(r):
				if r.get("ok") and int(r.get("bells", 0)) > 0:
					toast.emit("The weather bells are ringing!"))
		"stump": Activities.start_hide_and_seek()
		"board": open_panel.emit("photo_ideas", {})


## Wrap the item being edited as a present for a player id ("" = anyone).
func wrap_selected(to_pid: String, paper: int) -> void:
	if g_edit_id == "":
		return
	var id := g_edit_id
	_finish_edit()
	_ask(Session.wrap(id, to_pid, paper), func(r):
		if r.get("ok"):
			toast.emit("Wrapped! It waits here for them.")
			Sfx.play("place"))


func enter_house(id: String) -> void:
	if not Session.model.is_space(TownModel.room_space(id, 0, 0)):
		return
	go_to_room(TownModel.room_space(id, 0, 0))


## Moves through a doorway or the stairs to another room, arriving just inside
## the matching opening so the way back is right behind the child.
func go_to_room(target: String) -> void:
	if target == "town":
		exit_house()
		return
	if not Session.model.is_space(target):
		return
	cancel_ghost()
	var from := space
	space = target
	pos = TownModel.arrival(from, target)
	ry = 0.0
	_walk_target = null
	_pending_ctx = {}
	world.set_view(target)
	pos = world.resolve_walk(pos)
	rig.set_room(true)
	_place_kid()
	_send_state()
	Sfx.play("tap")
	fetch_mode = false
	space_changed.emit(space)


func exit_house() -> void:
	var house: Dictionary = Session.model.items.get(TownModel.house_of(space), {})
	cancel_ghost()
	space = "town"
	_walk_target = null
	# Switch to the town first so walking limits are the town's, not the room's.
	world.set_view("town")
	if house.is_empty():
		pos = TownModel.TOWN_SPAWN
	else:
		pos = world.resolve_walk(TownModel.door_point(house) + TownModel.facing(house["rot"]) * 0.4)
		ry = TownModel.rot_to_radians(house["rot"])
	rig.set_room(false)
	_place_kid()
	rig.snap()
	_send_state()
	fetch_mode = false
	space_changed.emit(space)


func stand_up() -> void:
	var seat := Session.seat_of(Session.my_id)
	if seat.is_empty():
		return
	var item: Dictionary = Session.model.items.get(seat[0], {})
	var cart := Session.ride_of(Session.my_id)
	if cart != "" and world.ride_fx:
		# Out of a cart: step onto free ground beside it, wherever on the rails it stands.
		var p: Dictionary = world.ride_fx.pose_of(cart)
		Session.stand()
		pos = _step_off(p["pos"], p["dir"])
		ry = atan2(p["dir"].x, p["dir"].y)
		item = {}
	else:
		Session.stand()
	if not item.is_empty():
		var def := Catalog.get_def(item["kind"])
		var center := Vector2(item["x"], item["z"])
		var facing := TownModel.facing(item["rot"])
		# In front of the child's own seat, so two children leaving one bench do not stand on each other.
		var side := Vector2.ZERO
		var node: Node3D = world.item_nodes.get(seat[0])
		var marker := Props.seat_marker(node, seat[1]) if node else null
		if marker:
			var off := Vector2(marker.global_position.x, marker.global_position.z) - center
			side = off - facing * off.dot(facing)
		pos = world.resolve_walk(center + side + facing * (def["radius"] + 0.45))
		ry = TownModel.rot_to_radians(item["rot"])
	var kid: Node3D = world.local_kid()
	if kid:
		kid.anim = "idle"
	_place_kid()


## The first spot beside a cart where a child can stand (nothing solid there), else the nearest free ground.
func _step_off(at: Vector2, dir: Vector2) -> Vector2:
	for p in RideRules.step_off_points(at, dir):
		var free: Vector2 = world.resolve_walk(p)
		if free.distance_to(p) < 0.05:
			return free
	return world.resolve_walk(RideRules.step_off_points(at, dir)[0])


func _on_view_changed(view: String) -> void:
	# The house we were in was put away by a friend: step back outside.
	if view != space:
		space = view
		pos = world.resolve_walk(TownModel.TOWN_SPAWN)
		rig.set_room(Places.is_room(view))
		cancel_ghost()
		_place_kid()
		fetch_mode = false
		space_changed.emit(space)


# ------------------------------------------------------------- decorating

func set_mode(m: String, confirmed := false) -> void:
	if m == mode:
		return
	# dest-fix r1: a place that cannot be decorated (a city) never enters decorate mode, whatever asks (the
	# HUD hides its button; the controller's and keyboard's shortcuts and a blueprint land here too).
	if m == "decorate" and not Places.decoratable(space):
		return
	# Someone put this place on display: ask before changing it (the HUD confirms).
	if m == "decorate" and not confirmed and not Session.display_by_other(space).is_empty():
		ask_display.emit(space, Session.display_by_other(space))
		return
	fetch_mode = false
	if m == "play":
		cancel_blueprint()
		cancel_ghost()
	elif _seated():
		stand_up()
	mode = m
	if world and world.contraptions:
		world.contraptions.show_links(mode == "decorate")   # dotted lines between linked things
	if world and world.puzzle_fx:
		world.puzzle_fx.show_links(mode == "decorate")      # and between a puzzle's parts
	_refresh_context()
	mode_changed.emit(mode)


func begin_new(kind: String) -> void:
	cancel_ghost()
	if not Catalog.allowed_in(kind, space):
		if space == Places.ZOO:
			hint.emit(TownModel.ERR_NOT_ZOO)
		elif Catalog.get_def(kind)["space"] == Places.ZOO:
			hint.emit(TownModel.ERR_ZOO_ONLY)
		else:
			hint.emit(TownModel.ERR_OUTDOORS if space != "town" else TownModel.ERR_INDOORS)
		return
	var forward := Vector2(sin(ry), cos(ry))
	var spot = Session.model.find_free_spot(kind, space, pos + forward * (Catalog.get_def(kind)["radius"] + 1.2))
	if spot == null:
		spot = pos + forward * 2.0
	g_kind = kind
	g_rot = 0
	g_color = Catalog.get_def(kind)["color"]
	g_edit_id = ""
	_make_ghost()
	_move_ghost_to(spot)


func select_item(id: String) -> void:
	var item: Dictionary = Session.model.items.get(id, {})
	if item.is_empty():
		return
	_ask(Session.lock(id), func(r):
		if not r.get("ok") or not Session.model.items.has(id):
			return
		cancel_ghost()
		var it: Dictionary = Session.model.items[id]
		g_kind = it["kind"]
		g_rot = it["rot"]
		g_color = it["color"]
		g_edit_id = id
		_g_orig = it.duplicate()
		if world.item_nodes.has(id):
			world.item_nodes[id].visible = false
		_make_ghost()
		_move_ghost_to(Vector2(it["x"], it["z"])))


func _make_ghost() -> void:
	if ghost:
		ghost.queue_free()
	ghost = Node3D.new()
	world.add_child(ghost)
	var model := Props.build(g_kind, g_color, 999)
	model.name = "Model"
	ghost.add_child(model)
	var r: float = Catalog.get_def(g_kind)["radius"]
	_ghost_ring = MeshInstance3D.new()
	_ghost_ring.mesh = Kit.torus(r * 0.92, r + 0.08)
	_ghost_ring.scale = Vector3(1, 0.25, 1)
	_ghost_ring.position.y = 0.04
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_ring.material_override = m
	ghost.add_child(_ghost_ring)
	model.rotation.y = TownModel.rot_to_radians(g_rot)


func _move_ghost_to(p: Vector2) -> void:
	if ghost == null:
		return
	g_pos = Vector2(snappedf(p.x, GHOST_SNAP), snappedf(p.y, GHOST_SNAP))
	if Catalog.grid(g_kind) > 0.0:
		g_pos = g_pos.snapped(Vector2.ONE * Catalog.grid(g_kind))   # track pieces sit on whole cells
	g_host = _support_under(p)
	var y := 0.0
	if Catalog.anchor(g_kind) != "ground":
		# Wall items slide onto the nearest wall; ceiling items hang above the finger, keeping their turn.
		var slot := TownModel.mount_slot(g_kind, g_pos.x, g_pos.y, g_rot)
		g_pos = Vector2(slot["x"], slot["z"])
		g_rot = slot["rot"]
		ghost.get_node("Model").rotation.y = TownModel.rot_to_radians(g_rot)
		ghost.position = Vector3(g_pos.x, slot["y"], g_pos.y)
		_ghost_ring.position.y = -float(slot["y"]) + 0.04
		_validate_ghost()
		return
	if g_host != "":
		# Snap onto the table top: the decoration sits exactly on the surface.
		var host: Dictionary = Session.model.items[g_host]
		g_pos = Session.model.surface_point(host)
		y = Catalog.support_surface(host["kind"])["local_position"].y
	ghost.position = Vector3(g_pos.x, y, g_pos.y)
	_validate_ghost()


## A support host (table) under this floor point that the ghost item may go on.
func _support_under(p: Vector2) -> String:
	if not Catalog.get_def(g_kind).get("tabletop_eligible", false):
		return ""
	var best := ""
	var best_d := INF
	for item in Session.model.items_in(space):
		if item["id"] == g_edit_id or Catalog.support_surface(item["kind"]).is_empty():
			continue
		var d := p.distance_to(Vector2(item["x"], item["z"]))
		if d < Catalog.get_def(item["kind"])["radius"] + 0.15 and d < best_d:
			best_d = d
			best = item["id"]
	return best


func _drag_ghost(screen: Vector2) -> void:
	var gp = world.ground_point(rig.camera, screen)
	if gp != null:
		_move_ghost_to(gp)


func _near_ghost(screen: Vector2) -> bool:
	if ghost == null:
		return false
	var cam: Camera3D = rig.camera
	var r: float = Catalog.get_def(g_kind)["radius"]
	var c := cam.unproject_position(ghost.global_position + Vector3(0, 0.4, 0))
	var e := cam.unproject_position(ghost.global_position + Vector3(0, 0.4, 0) + cam.global_basis.x * (r + 0.3))
	return c.distance_to(screen) < maxf(c.distance_to(e), 60.0)


func turn_ghost() -> void:
	# Floor and ceiling items turn in 45-degree steps; a wall item always faces into the room.
	if ghost and Catalog.anchor(g_kind) != "wall":
		var step := 2 if Catalog.grid(g_kind) > 0.0 else 1   # track pieces turn in quarter turns
		g_rot = posmod(g_rot + step, 8)
		var model := ghost.get_node("Model") as Node3D
		create_tween().tween_property(model, "rotation:y", model.rotation.y + TAU / 8.0 * step, 0.15)
		_validate_ghost()


func paint_ghost(color: int) -> void:
	if ghost and Catalog.get_def(g_kind)["color"] >= 0:
		g_color = color
		var rot: float = ghost.get_node("Model").rotation.y
		ghost.get_node("Model").free()
		var model := Props.build(g_kind, g_color, 999)
		model.name = "Model"
		model.rotation.y = rot
		ghost.add_child(model)
		_validate_ghost()


func _validate_ghost() -> void:
	if g_host != "":
		g_error = Session.model.check_attach(g_kind, g_host, g_edit_id, g_rot)
		if g_error == "":
			g_error = Session.model.clearance(g_kind, space, g_pos.x, g_pos.y, g_rot, g_edit_id, g_host)
	else:
		g_error = Session.model.check(g_kind, space, g_pos.x, g_pos.y, g_rot, g_edit_id)
	if g_error == "" and g_host == "" and g_pos.distance_to(pos) < 0.2 + Catalog.get_def(g_kind)["radius"] and Catalog.get_def(g_kind)["layer"] == "solid":
		g_error = "Step aside so it does not land on you."
	var m := _ghost_ring.material_override as StandardMaterial3D
	m.albedo_color = Color("#7cc28a") if g_error == "" else Color("#ef8a73")
	ghost_changed.emit(ghost_info())


func ghost_info() -> Dictionary:
	if ghost == null:
		return {}
	return {"kind": g_kind, "editing": g_edit_id != "", "error": g_error, "color": g_color, "on_table": g_host != "",
		"paintable": Catalog.get_def(g_kind)["color"] >= 0}


func confirm_ghost() -> void:
	if ghost == null or g_error != "":
		if g_error != "":
			hint.emit(g_error)
		return
	if g_edit_id == "":
		_ask(Session.place(g_kind, space, g_pos, g_rot, g_color, g_host), func(r):
			if r.get("ok"):
				_push_undo({"type": "place", "id": r["item"]["id"]})
				item_placed.emit(r["item"]["kind"])
				var links: int = Contraptions.linked(Session.model, r["item"]["id"]).size() if Contraptions.is_trigger(r["item"]["kind"]) else 0
				toast.emit(tr("Placed! Linked things: %d") % links if links > 0 else "Placed! Pick another, or tap Done.")
				Sfx.play("place"))
		_clear_ghost()
	else:
		var id := g_edit_id
		var orig := _g_orig
		var host := g_host
		var moved: bool = not (is_equal_approx(orig["x"], g_pos.x) and is_equal_approx(orig["z"], g_pos.y)) or orig["rot"] != g_rot or orig.get("host", "") != host
		var painted: bool = orig["color"] != g_color
		if moved:
			_ask(Session.move(id, g_pos, g_rot, host), func(r):
				if r.get("ok"):
					_push_undo({"type": "move", "id": id, "x": orig["x"], "z": orig["z"], "rot": orig["rot"], "host": orig.get("host", "")})
					Sfx.play("place"))
		if painted:
			_ask(Session.paint(id, g_color), func(r):
				if r.get("ok"):
					_push_undo({"type": "paint", "id": id, "color": orig["color"]}))
		_finish_edit()


func cancel_ghost() -> void:
	if ghost == null:
		return
	if g_edit_id != "":
		_finish_edit()
	else:
		_clear_ghost()


func _finish_edit() -> void:
	var id := g_edit_id
	_clear_ghost()
	if id != "":
		Session.unlock(id)
		if world.item_nodes.has(id):
			world.item_nodes[id].visible = true


func _clear_ghost() -> void:
	if ghost:
		ghost.queue_free()
	ghost = null
	g_edit_id = ""
	g_host = ""
	g_error = ""
	ghost_changed.emit({})


## Put away the item being edited. A cottage with furniture asks first.
func put_away(confirmed := false) -> void:
	if g_edit_id == "":
		return
	var item: Dictionary = Session.model.items.get(g_edit_id, {})
	var contents: int = Session.model.items_in(g_edit_id).size() if item.get("kind") == "cottage" else 0
	if contents > 0 and not confirmed:
		confirm_remove.emit(item, contents)
		return
	var id := g_edit_id
	_clear_ghost()
	_ask(Session.remove(id), func(r):
		if r.get("ok"):
			_push_undo({"type": "remove", "items": r["removed"]})
			toast.emit("Put away. Tap Undo to bring it back.")
			Sfx.play("pop")
		elif world.item_nodes.has(id):
			world.item_nodes[id].visible = true)
	Session.unlock(id)


func _push_undo(entry: Dictionary) -> void:
	_undo.append(entry)
	if _undo.size() > 30:
		_undo.pop_front()
	undo_changed.emit(true)


## Undo only this player's own recent actions, applied as new shared edits.
func undo() -> void:
	if _undo.is_empty():
		return
	cancel_ghost()
	var e: Dictionary = _undo.pop_back()
	undo_changed.emit(not _undo.is_empty())
	var done := func(r):
		if r.get("ok"):
			# Undo never drops things silently: say so if something could not come back.
			toast.emit("Some things could not go back." if not r.get("skipped", []).is_empty() else "Last action undone.")
	match e["type"]:
		"place": _ask(Session.remove(e["id"]), done)
		"move": _ask(Session.move(e["id"], Vector2(e["x"], e["z"]), e["rot"], e.get("host", "")), done)
		"paint": _ask(Session.paint(e["id"], e["color"]), done)
		"remove": _ask(Session.restore(e["items"]), done)
		"blueprint":
			for id in e["ids"]:
				_ask(Session.remove(id), done)


# ------------------------------------------------------------- the zoo: journeys, stations, Look

## The tram stop and stations within reach in the zoo (contexts for the action button).
func _zoo_contexts() -> Array:
	var out: Array = [{"type": "tram_home", "label": "Ride home", "icon": "tram", "at": ZooMap.STATION + Vector2(0, -1.6)}]
	for st in ZooMap.STATIONS:
		var d: Dictionary = ZooMap.STATIONS[st]
		out.append({"type": "zoo_station", "id": st, "label": d["label"], "icon": d["icon"], "at": d["pos"]})
	return out


var _journey_then := Callable()


## Rides the tram to another map (12.3): a held thing is cancelled, a seat is left, Look ends;
## the card shows; the origin stays until the authority says yes; a refusal or no answer within
## 8 s leaves the child where it was, with the action offered again (12.4).
func ride(to: String, then := Callable()) -> void:
	if journey_to != "" or to == Places.map_of(space) or not Places.is_map(to):
		return
	if not Places.available(to):
		hint.emit("That place can't be reached from here.")   # city-web: not on this device (an invitation, a test)
		return
	cancel_ghost()
	if not bp.is_empty():
		cancel_blueprint()
	if _seated():
		stand_up()
	if fetch_mode:
		stop_fetch()
	end_look()
	set_mode("play")
	_walk_target = null
	_pending_ctx = {}
	journey_to = to
	_journey_then = then
	_journey_t0 = Time.get_ticks_msec() / 1000.0
	_journey_elapsed = 0.0
	_journey_from = Places.map_of(space)
	if Places.map_of(space) == Places.THOUSAND:
		thousand_end_all()   # thousand-town: following, waiting, the bus, the wheel or a show end cleanly
	Sfx.play("tram")
	journey.emit("start", to)
	if to == Places.THOUSAND and world.has_method("prepare_thousand"):
		# thousand-town: the town, its residents and its buses are built behind the journey card once it is fully
		# shown (it fades in over 0.3 s), so the arrival has no hitch; the way home never waits for this.
		await get_tree().create_timer(0.35).timeout
		await get_tree().process_frame
		if journey_to != to:
			return
		world.prepare_thousand()
		if journey_to != to:
			return
	var req: int = Session.travel(to)
	if req < 0:
		_journey_failed("The tram could not leave right now. You are still where you were.")
		return
	_ask(req, func(r):
		if journey_to != to:
			return   # already timed out
		if not r.get("ok", false):
			_journey_failed(str(r.get("error", "The tram could not leave right now. You are still where you were.")))
			return
		_arrive(to, Vector2(float(r.get("x", 0.0)), float(r.get("z", 0.0))), float(r.get("ry", PI)))
		if str(r.get("waits", "")) != "":
			toast.emit(tr("%s will wait for you in town.") % tr(str(r["waits"]))))


func _arrive(to: String, at: Vector2, at_ry: float) -> void:
	if space == Places.THOUSAND and to != Places.THOUSAND:
		thousand_end_all()
	if to == Places.ZOO and world.activity:
		world.activity.mark_discovered("tram_stop")   # its tag now shows only close by
	space = to
	world.set_view(to)
	level = ""
	_city_route = []
	city_hold = {}
	if city_looking:
		city_looking = false
		city_paused = false
		city_look_changed.emit(false)
	pos = at if Places.is_city(to) else world.resolve_walk(at)
	ry = at_ry
	_end_thousand_look()
	if to == Places.ZOO:
		rig.enter_zoo()
	elif rig.on_zoo:
		rig.leave_zoo()
	if Places.is_city(to):
		rig.enter_city()   # the strolling view that follows the child (dest-fix r1; was the whole block's overview)
	elif rig.on_city:
		rig.leave_city()
	if to == Places.THOUSAND:
		rig.enter_thousand(world.thousand_world, ry)   # behind the child, looking east (design/thousand-town.md 3, 6)
	elif rig.on_thousand:
		rig.leave_thousand()
	rig.set_room(false)
	_place_kid()
	rig.snap()
	_send_state()
	space_changed.emit(space)
	_journey_arrived = true


var _journey_arrived := false


## The card stays at least JOURNEY_MIN; the journey fails after JOURNEY_TIMEOUT without an answer.
func _check_journey() -> void:
	if journey_to == "":
		return
	_journey_elapsed += minf(get_physics_process_delta_time(), 0.25)
	var t := _journey_elapsed
	if _journey_arrived and t >= JOURNEY_MIN:
		var to := journey_to
		journey_to = ""
		_journey_arrived = false
		journey.emit("done", to)
		if to == Places.ZOO:
			_welcome_once()
		if _journey_then.is_valid():
			var f := _journey_then
			_journey_then = Callable()
			f.call()
	elif not _journey_arrived and t >= JOURNEY_TIMEOUT:
		# The answer may still come, or the authority may have moved us: ask for the origin again (the
		# request names a place, so it is harmless when we never left).
		var back := _journey_from
		_journey_failed("The tram could not leave right now. You are still where you were.")
		if back != "":
			Session.travel(back)


## "Welcome to the zoo!" on this device's first arrival (design 12.3).
func _welcome_once() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if bool(cfg.get_value("zoo", "welcomed", false)):
		return
	cfg.set_value("zoo", "welcomed", true)
	cfg.save("user://settings.cfg")
	toast.emit("Welcome to the zoo!")


func _journey_failed(msg: String) -> void:
	var to := journey_to
	journey_to = ""
	_journey_arrived = false
	_journey_then = Callable()
	journey.emit("failed", to)
	if msg != "":
		hint.emit(msg)


## Look at a zoo animal: walk to within LOOK_REACH, then the camera frames its head with the child.
func start_look(id: String) -> void:
	var node: Node3D = world.zoo_world.animal_node(id) if world.zoo_world else null
	if node == null:
		return
	look_id = id
	rig.look_node = node
	rig.look_height = node.usual_height()
	var at := Vector2(node.position.x, node.position.z)
	if pos.distance_to(at) > LOOK_REACH:
		var p: Vector2 = at + (pos - at).normalized() * (LOOK_REACH - 0.5)
		_walk_to(world.resolve_walk(p), {})
	look_changed.emit(id)


func end_look() -> void:
	if look_id == "":
		return
	look_id = ""
	if rig:
		rig.look_node = null
	look_changed.emit("")


## Look ends on walking away, decorating, or the animal moving more than LOOK_END off (11.1).
func _check_look() -> void:
	if look_id == "":
		return
	var node: Node3D = world.zoo_world.animal_node(look_id) if world.zoo_world else null
	if node == null or space != Places.ZOO or mode != "play" or ghost != null:
		end_look()
		return
	if pos.distance_to(Vector2(node.position.x, node.position.z)) > LOOK_END:
		end_look()


# ------------------------------------------------------------- Thousand Town (design/thousand-town.md)

## A press, a drag and a release in Thousand Town: a drag beyond TAP_SLOP orbits the follow camera, a pinch or
## the wheel zooms, and a release that is still a tap walks (or inspects a building). Keys go on as elsewhere.
func _thousand_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_t_pressed = true
			_t_orbiting = false
			_t_press = event.position
		else:
			if _t_pressed and not _t_orbiting and event.position.distance_to(_t_press) < TAP_SLOP:
				_tap(event.position)
			_t_pressed = false
			_t_orbiting = false
		return true
	if event is InputEventMouseMotion and _t_pressed:
		if not _t_orbiting and event.position.distance_to(_t_press) >= TAP_SLOP:
			_t_orbiting = true
		if _t_orbiting:
			rig.thousand_orbit(event.relative)
		return true
	if event is InputEventMagnifyGesture:
		rig.thousand_zoom(event.factor)
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom_in()
		else:
			rig.zoom_out()
		return true
	return false


## A tap in Thousand Town: on a building, the child walks to its door and asks who is there; elsewhere it walks.
func _thousand_tap(screen: Vector2) -> void:
	if _seated() or _thousand_busy():
		return   # on the bus or the wheel: Get off is the action button
	if thousand_play.tap(screen):
		return   # a resident: the child waves and the card opens
	var hit: Dictionary = thousand_tap_target(screen)
	if hit.is_empty():
		return
	var gp: Vector2 = hit.ground
	_thousand_manual()
	Sfx.play("tap")
	var b: Dictionary = hit.site
	if not b.is_empty() and b.get("door") is Vector2:
		var ctx := {"type": "thousand_inspect", "id": str(b["id"]), "label": "Who's here?", "icon": "look", "at": b["door"]}
		if pos.distance_to(b["door"]) < THOUSAND_DOOR_REACH:
			do_context(ctx)
		else:
			_walk_to(b["door"], ctx)
		return
	_walk_to(gp, {})


## unified r6: what a tap at `screen` in Thousand Town means, without doing it: {"ground": the walkable point the finger
## meets (Vector2), "site": the building it asks about, or {}}; {} off the ground. The building is the one the ray meets
## before the ground (ThousandWorld.building_on_ray), else the site under the ground point (a place or a low roof).
func thousand_tap_target(screen: Vector2) -> Dictionary:
	var gp = world.ground_point(rig.camera, screen)
	if gp == null:
		return {}
	# The ground is raised on the footbridges and platforms (up to about 1 m): meet the finger's ray at the height
	# found there, or a tap on a bridge deck walks to a point well beyond it (the loop tour, on the canal bridges).
	var from: Vector3 = rig.camera.project_ray_origin(screen)
	var dir: Vector3 = rig.camera.project_ray_normal(screen)
	for i in 3:
		var h: float = world.thousand_height(gp)
		if absf(dir.y) < 1e-4 or absf(h) < 1e-3:
			break
		var t := (h - from.y) / dir.y
		if t < 0.0:
			break
		var hit := from + dir * t
		gp = Vector2(hit.x, hit.z)
	var tw: Node3D = world.thousand_world
	var b: Dictionary = {}
	if tw:
		var ground_t: float = (Vector3(gp.x, world.thousand_height(gp), gp.y) - from).dot(dir)
		b = tw.building_on_ray(from, dir, ground_t)
		if b.is_empty():
			b = tw.building_at(gp)
	return {"ground": gp, "site": b}


## What the action button offers in Thousand Town, best first (the second is its alt): on the bus or the wheel only
## Get off (at a stop, at the bottom); else the bus and the wheel (thousand_play.contexts()), "Who's here?" at a
## door, "Buy a snack" at a stall's counter, "Say hello" to a resident close by, the tram home at the station's back.
func _thousand_context() -> Dictionary:
	var tw: Node3D = world.thousand_world if world else null
	if tw == null:
		return {}
	var list: Array = thousand_play.contexts()
	if not _thousand_busy() and thousand_play.state != "wheel_wait":
		var door: Dictionary = tw.door_near(pos, THOUSAND_DOOR_REACH)
		if not door.is_empty():
			list.append({"type": "thousand_inspect", "id": str(door["id"]), "label": "Who's here?", "icon": "look", "at": door["door"]})
		var stall: Dictionary = thousand_play.stall_context()
		if not stall.is_empty():
			list.append(stall)
		var hello: Dictionary = thousand_play.hello_context()
		if not hello.is_empty():
			list.append(hello)
		if pos.distance_to(tw.STATION_TRAVEL) < THOUSAND_TRAVEL_REACH:
			list.append({"type": "tram_home", "label": "Ride home", "icon": "tram", "at": tw.STATION_TRAVEL})
	if list.is_empty():
		return {}
	var ctx: Dictionary = (list[0] as Dictionary).duplicate()
	if list.size() > 1:
		ctx["alt"] = list[1]
	return ctx


## On the bus or the ferris wheel in Thousand Town: the child is placed there, not walked.
func _thousand_busy() -> bool:
	return space == Places.THOUSAND and thousand_play != null and thousand_play.busy()


## The child walks by itself (stick, keys, a tap on the ground): following, waiting and watching end.
func _thousand_manual() -> void:
	if space == Places.THOUSAND and thousand_play != null:
		thousand_play.manual_walk()


## Ends every Thousand Town interaction cleanly (the tram home, leaving the town, a new session).
func thousand_end_all() -> void:
	if thousand_play != null:
		thousand_play.end_all()


## Look in Thousand Town: the camera flies to the overview of the whole town (on) and back (off).
func set_thousand_look(on: bool) -> void:
	if space != Places.THOUSAND:
		on = false
	if on == thousand_looking:
		return
	thousand_looking = on
	rig.thousand_set_overview(on)
	thousand_look_changed.emit(on)


func _end_thousand_look() -> void:
	if thousand_looking:
		thousand_looking = false
		if rig:
			rig.thousand_set_overview(false)
		thousand_look_changed.emit(false)


# ------------------------------------------------------------- the city (city r1, design/city-district.md)

## The City autoload of the city map the child is on (City or CityWeb; null outside a city map).
func _city_node() -> Node:
	if space == Places.CITY_WEB:
		return get_node_or_null("/root/CityWeb")
	return get_node_or_null("/root/City")


## Riding the wheel or holding a seat or machine: the child is placed by the city, not by walking.
func _city_busy() -> bool:
	return Places.is_city(space) and (_city_riding() >= 0 or not city_hold.is_empty())


func _city_riding() -> int:
	var city := _city_node()
	return int(city.riding(Session.my_id)) if city and city.has_method("riding") else -1


## Every frame in the city: the cutaway around the child, the child on its seat, machine or gondola, and the
## friends who ride or hold places (drawn where the shared state says).
func _city_frame(kid: Node3D) -> void:
	world.update_city_cutaway(level, pos)
	var city := _city_node()
	var cw: Node3D = world.active_city()
	if city == null or cw == null:
		return
	if not city_hold.is_empty() and city.has_method("occupant") and int(city.occupant(str(city_hold["key"]))) != Session.my_id \
			and city.states.has("occupancy"):
		city_hold = {}   # the authority freed it (a reconnect, a reset)
	var g := _city_riding()
	if g >= 0:
		var xf: Transform3D = cw.rider_transform(g, float(cw.ferris_angle_now()), _rider_slot(city, g, Session.my_id))
		kid.global_transform = xf
		kid.anim = "ride"
		pos = Vector2(xf.origin.x, xf.origin.z)
	elif not city_hold.is_empty():
		_hold_pose(kid, str(city_hold["key"]), str(city_hold.get("pose", "sit")))
	world.place_city_friends(city.states)


func _rider_slot(city: Node, g: int, peer: int) -> int:
	var riders: Array = (city.states.get("riders", {}) as Dictionary).get(g, [])
	return maxi(riders.find(peer), 0)


func _hold_pose(kid: Node3D, key: String, pose: String) -> void:
	var how: Array = CityMap.HOLD_POSES.get(pose, ["sit", 0.44])
	var cw: Node3D = world.active_city()
	var xf: Transform3D = cw.seat_transform(key) if cw else Transform3D(Basis.IDENTITY, Vector3(pos.x, CityNav.height(level, pos), pos.y))
	xf.origin.y += float(how[1])
	kid.global_transform = xf
	kid.anim = str(how[0])


## A press, a drag and a release in the city (CityOrbit's arbitration): a drag on empty ground orbits, a
## pinch or the wheel zooms, and only a release that is still a tap walks or uses something.
func _city_input(event: InputEvent) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# city r3: a right drag pans (desktop); it is never a tap.
		if event.pressed:
			_city_gesture = CityOrbit.gesture_new("mouse", "ground", event.position, now, get_viewport().get_visible_rect().size.y / 1080.0, "right")
		else:
			_city_gesture = {}
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_city_gesture = CityOrbit.gesture_new("mouse", "ground", event.position, now, get_viewport().get_visible_rect().size.y / 1080.0)
		elif not _city_gesture.is_empty():
			if CityOrbit.gesture_end(_city_gesture, now) == "tap":
				_tap(event.position)
			_city_gesture = {}
		return true
	if event is InputEventMouseMotion and not _city_gesture.is_empty():
		_city_gesture = CityOrbit.gesture_move(_city_gesture, event.position, now, 1)
		if _city_gesture["mode"] == "orbit":
			rig.city_orbit(_city_gesture["delta"])
		elif _city_gesture["mode"] == "pan":
			rig.city_pan(_city_gesture["delta"])
		return true
	if event is InputEventMagnifyGesture:
		rig.city_zoom(event.factor)
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		rig.city_zoom(CityOrbit.wheel_factor(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0))
		return true
	return false


## A tap in the city: the nearest walkable surface along the ray (never through a floor). Near a thing to
## use, the child walks there and uses it; otherwise it walks there, by stairs and skywalks if needed.
func _city_tap(screen: Vector2) -> void:
	if city_looking:
		var key := _look_pick(screen)
		Sfx.play("tap")
		if key != "":
			rig.city_look_at(key)
		else:
			rig.city_look_out()
		return
	if _city_riding() >= 0:
		return   # riding takes no other input; Get off is the action button
	_city_tap_hit(world.pick_city(rig.camera, screen, level, pos))


## What a play tap on a picked city surface does (the Godot city's tap and the web city's web_tap).
func _city_tap_hit(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	Sfx.play("tap")
	if not city_hold.is_empty():
		_city_do({"type": "city_release"})
	var best := {}
	var best_d := 2.0   # a tap on a shop's doorstep or beside a table uses it (the child walks in)
	for c in _city_contexts():
		if c["region"] == hit["region"] and (c["at"] as Vector2).distance_to(hit["pos"]) < best_d:
			best_d = (c["at"] as Vector2).distance_to(hit["pos"])
			best = c
	if not best.is_empty():
		_city_walk(best["region"], best["at"], best)
	else:
		_city_walk(str(hit["region"]), hit["pos"], {})


func _city_walk(region: String, at: Vector2, then: Dictionary) -> void:
	_prepare_walk()
	var route: Array = CityNav.route(level, pos, region, at)
	if route.is_empty():
		hint.emit("That place can't be reached from here.")
		return
	_city_route = route
	_walk_target = (_city_route.pop_front() as Dictionary)["pos"]
	_pending_ctx = then


## The things a child can do in the city, each on its level ("" is the ground).
func _city_contexts() -> Array:
	var out: Array = []
	for key in CityMap.INTERACTIONS:
		var d: Dictionary = CityMap.INTERACTIONS[key]
		var region: String = "" if d["region"] == "ground" else d["region"]
		var kind: String = d["kind"]
		var icon: String = {"seat": "sit", "order": "cook", "exercise": "cheer", "desk": "book", "shop": "gift", "ride": "play", "travel": "tram"}.get(kind, "play")
		var type: String = "tram_home" if kind == "travel" else ("city_board" if kind == "ride" else "city_use")
		out.append({"type": type, "id": key, "key": key, "label": d["label"], "icon": icon, "at": d["pos"], "region": region})
	return out


func _city_context() -> Dictionary:
	if _city_riding() >= 0:
		return {"type": "city_off", "label": "Get off at the bottom", "icon": "stand"}
	if not city_hold.is_empty():
		return {"type": "city_release", "label": "Stand up", "icon": "stand"}
	var best := {}
	var best_d := CityMap.REACH
	for c in _city_contexts():
		if c["region"] != level:
			continue
		var d := pos.distance_to(c["at"])
		if d < best_d:
			best_d = d
			best = c
	return best


func _city_do(ctx: Dictionary) -> void:
	var city := _city_node()
	if city == null:
		return
	# Whatever the child does now replaces a walk still under way and the action it was going to do on
	# arrival (city tour: pressing Sit before the tapped walk ended, then Stand up, sat the child down again).
	_walk_target = null
	_pending_ctx = {}
	_city_route = []
	# The authority judges reach from the last state it has: send where the child is now, ahead of the request
	# (one WebSocket stream keeps the order), or a press right after a walk is judged 0.1 s back, too far.
	_send_t = 0.1
	_send_state()
	match str(ctx["type"]):
		"city_use":
			Sfx.play("tap")
			_ask(city.use(str(ctx["key"])), func(r):
				if not r.get("ok", false):
					hint.emit(str(r.get("error", "")))
				elif r.get("hold", false):
					city_hold = {"key": str(r.get("key", ctx["key"])), "pose": str(r.get("pose", "sit"))}
				elif str(r.get("line", "")) != "":
					Sfx.play("pop")
					toast.emit(CityMap.LINES.get(str(r["line"]), "")))
		"city_board":
			Sfx.play("tap")
			_ask(city.board(), func(r):
				if not r.get("ok", false):
					hint.emit(str(r.get("error", ""))))
		"city_off":
			_ask(city.off(), func(r):
				if not r.get("ok", false):
					hint.emit(str(r.get("error", ""))))
		"city_release":
			city_hold = {}
			_ask(city.release(), func(_r): pass)
			_place_kid()


## The wheel brought this child back to the platform (the City's "ride_off" event for me).
func city_ride_off(at: Vector2, region: String) -> void:
	pos = at
	level = region
	_place_kid()


# ------------------------------------------------------------------ city-web: the page's input (design/city-threejs.md 6.3)
# The web city's page draws everything and sends its input here (scripts/web/web_city_bridge.gd); the child,
# its routes, actions and the shared state stay Godot's, exactly as in the Godot city.

func _web_ready() -> bool:
	return space == Places.CITY_WEB and enabled and world != null and world.local_kid() != null and journey_to == ""


## A play tap on the page: its camera ray (world space). The same floor-aware pick (CityNav.pick past the
## storeys the cutaway hides around the child), the same things within 2 m, the same walk by CityNav.route.
func web_tap(origin: Vector3, dir: Vector3) -> void:
	if not _web_ready() or mode != "play":
		return
	if _city_riding() >= 0:
		return   # riding takes no other input; Get off is the action button
	_city_tap_hit(world.pick_city_ray(origin, dir, level, pos))


## The page's action button: does the current context (as the Godot action button does).
func web_act() -> void:
	if not _web_ready() or mode != "play":
		return
	_refresh_context()
	if not _ctx.is_empty():
		do_context()


## The page's weather buttons: w is an index into CityMap.WEATHERS (shared by everyone in the web city).
func web_weather(w: int) -> void:
	if not _web_ready():
		return
	var city := _city_node()
	if city and city.has_method("set_weather"):
		_ask(city.set_weather(w), func(r):
			if not r.get("ok", false) and str(r.get("error", "")) != "":
				hint.emit(str(r["error"])))


## The page's Town button: the child rides home (the bus stop's travel context does the same).
func web_home() -> void:
	if space == Places.CITY_WEB:
		ride(Places.TOWN)


## The action button for the page: {} when nothing, else {"type", "label" (translated), "icon"}.
func web_ctx() -> Dictionary:
	if space != Places.CITY_WEB or mode != "play" or _ctx.is_empty():
		return {}
	return {"type": str(_ctx.get("type", "")), "label": tr(str(_ctx.get("label", ""))), "icon": str(_ctx.get("icon", ""))}


## The local child for the page's frame message: {"id", "level", "pos" [x, z], "riding" (gondola or -1),
## "hold" (key or ""), "ctx" (web_ctx() or null)}.
func web_me() -> Dictionary:
	var ctx := web_ctx()
	return {"id": Session.my_id, "level": level, "pos": [pos.x, pos.y], "riding": _city_riding() if space == Places.CITY_WEB else -1,
		"hold": str(city_hold.get("key", "")), "ctx": ctx if not ctx.is_empty() else null}


# ------------------------------------------------------------------ city r2: Look and Pause

## Look on or off. Off glides back to the overview and gives taps back to walking (and resumes the city).
func set_city_look(on: bool) -> void:
	if space != Places.CITY:
		on = false
	if on == city_looking:
		return
	city_looking = on
	if not on:
		set_city_paused(false)
		rig.city_stroll()   # dest-fix r1: back to the child (was the overview)
	city_look_changed.emit(on)


## The controller's D-pad while looking: the next or previous place of CityMap.LOOK_ORDER.
func city_look_step(dir: int) -> void:
	if not city_looking:
		return
	var order: Array = CityMap.LOOK_ORDER
	var i := order.find(rig.city_look)
	i = (0 if dir > 0 else order.size() - 1) if i < 0 else posmod(i + dir, order.size())
	rig.city_look_at(str(order[i]))


## Pause the city's ambient motion on this screen only (the shared city runs on for friends).
func set_city_paused(on: bool) -> void:
	if on and not city_looking:
		on = false
	city_paused = on
	if world and world.city_world and world.city_world.has_method("set_paused"):
		world.city_world.set_paused(on)


## The Look place under a screen point, or "" for empty space.
func _look_pick(screen: Vector2) -> String:
	var cam: Camera3D = rig.camera
	return CityOrbit.pick_place(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
