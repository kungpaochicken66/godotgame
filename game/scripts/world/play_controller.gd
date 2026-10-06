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

signal context_changed(ctx: Dictionary)
signal mode_changed(mode: String)
signal ghost_changed(info: Dictionary)   # {} when nothing is being placed or edited
signal hint(text: String)
signal toast(text: String)
signal confirm_remove(item: Dictionary, contents: int)
signal space_changed(space: String)
signal undo_changed(available: bool)

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

var _walk_target: Variant = null
var _pending_ctx := {}
var _ctx := {}
var _send_t := 0.0
var _last_sent := {}
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _requests := {}            # req id -> Callable(result)
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
var _g_orig := {}


func _ready() -> void:
	Session.request_done.connect(_on_request_done)
	Session.joined.connect(_on_joined)
	Session.seats_changed.connect(_refresh_context)


func setup(w: Node3D, r: Node3D) -> void:
	world = w
	rig = r
	world.view_changed.connect(_on_view_changed)


func _on_joined(_id: int) -> void:
	var s: Dictionary = Session.players.get(Session.my_id, {}).get("state", {})
	pos = Vector2(s.get("x", 0.0), s.get("z", 9.0))
	ry = s.get("ry", PI)
	space = "town"
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
		if (event.factor > 1.0 and rig.zoom == 1) or (event.factor < 1.0 and rig.zoom == 0):
			rig.toggle_zoom()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if (event.button_index == MOUSE_BUTTON_WHEEL_UP) == (rig.zoom == 1):
			rig.toggle_zoom()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_Q: rig.rotate_step(-1)
		KEY_E: rig.rotate_step(1)
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				undo()
			else:
				rig.toggle_zoom()
		KEY_R: turn_ghost()
		KEY_ENTER, KEY_KP_ENTER: confirm_ghost()
		KEY_ESCAPE: cancel_ghost()
		KEY_SPACE:
			if not _ctx.is_empty():
				do_context()
		KEY_1: Session.send_emote("wave")
		KEY_2: Session.send_emote("cheer")
		KEY_3: Session.send_emote("dance")
		KEY_4: Session.send_emote("heart")


func _tap(screen: Vector2) -> void:
	var cam: Camera3D = rig.camera
	if mode == "decorate":
		var id: String = world.pick_item(cam, screen)
		if ghost and (id == "" or id == g_edit_id):
			var gp = world.ground_point(cam, screen)
			if gp != null:
				_move_ghost_to(gp)
			return
		if id != "" and ghost == null:
			select_item(id)
			return
	else:
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
	if gp != null:
		_walk_to(gp, {})


func _walk_to(p: Vector2, then: Dictionary) -> void:
	_walk_target = p
	_pending_ctx = then


# ------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if world == null or world.local_kid() == null:
		return
	var kid: Node3D = world.local_kid()
	var move := Vector2.ZERO
	if enabled and not _seated():
		var kb := Vector2(
			Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
			Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up"))
		for k in [[KEY_D, Vector2.RIGHT], [KEY_A, Vector2.LEFT], [KEY_S, Vector2.DOWN], [KEY_W, Vector2.UP]]:
			if Input.is_physical_key_pressed(k[0]) and not Input.is_key_pressed(KEY_CTRL):
				kb += k[1]
		if kb.length() > 0.1:
			_walk_target = null
			move = (rig.flat_right() * kb.x - rig.flat_forward() * kb.y).normalized()
		elif _walk_target != null:
			var d: Vector2 = _walk_target - pos
			var stop := 0.9 if not _pending_ctx.is_empty() else 0.08
			if d.length() <= stop:
				_walk_target = null
				if not _pending_ctx.is_empty():
					var ctx := _pending_ctx
					_pending_ctx = {}
					do_context(ctx)
			else:
				move = d.normalized()
	# The camera glides to an item being placed, but holds still while a finger drags it.
	rig.follow = ghost if ghost and not _dragging else null
	walking = move.length() > 0.01
	if walking:
		var before := pos
		pos = world.resolve_walk(pos + move * WALK_SPEED * delta)
		if _walk_target != null and before.distance_to(pos) < WALK_SPEED * delta * 0.15:
			_walk_target = null   # Blocked: stop instead of pushing forever.
		ry = lerp_angle(ry, atan2(move.x, move.y), minf(1.0, delta * 12.0))
	if not _seated():
		kid.anim = "walk" if walking else "idle"
		kid.walk_speed = WALK_SPEED
		_place_kid()
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		_send_state()
	_refresh_context()


func _place_kid() -> void:
	var kid: Node3D = world.local_kid()
	if kid and not _seated():
		kid.position = Vector3(pos.x, 0, pos.y)
		kid.rotation = Vector3(0, ry, 0)


func _send_state() -> void:
	var seat := Session.seat_of(Session.my_id)
	var anim := "walk" if walking else "idle"
	if not seat.is_empty():
		var kid: Node3D = world.local_kid()
		anim = kid.anim if kid else "sit"
	var s := {"space": space, "x": snappedf(pos.x, 0.01), "z": snappedf(pos.y, 0.01), "ry": snappedf(ry, 0.01), "anim": anim}
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
	if def.get("seats", 0) > 0:
		var p := Vector2(item["x"], item["z"])
		var front: Vector2 = p + TownModel.facing(item["rot"]) * (def["radius"] + 0.4)
		return {"type": "sit", "id": id, "label": def["action"], "icon": "sit", "at": front if from_tap else p}
	return {}


func _refresh_context() -> void:
	var ctx := {}
	if mode == "play" and world:
		if _seated():
			ctx = {"type": "stand", "label": "Get up", "icon": "stand"}
		elif space == "town":
			if pos.distance_to(world.bell_point()) < 1.7:
				ctx = {"type": "bell", "label": "Evening" if not Session.model.evening else "Morning", "icon": "bell", "at": world.bell_point()}
			var best := 2.0
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
			if pos.distance_to(TownModel.ROOM_DOOR) < 1.6:
				ctx = {"type": "exit", "label": "Go outside", "icon": "door"}
			var best := 2.0
			for item in Session.model.items_in(space):
				var c := _context_for_item(item["id"])
				if c.is_empty():
					continue
				var d := pos.distance_to(c["at"])
				if d < Catalog.get_def(item["kind"])["radius"] + 1.0 and d < best:
					best = d
					ctx = c
	var key := func(c: Dictionary): return [c.get("type"), c.get("id"), c.get("label")]
	if key.call(ctx) != key.call(_ctx):
		_ctx = ctx
		context_changed.emit(ctx)


func do_context(ctx: Dictionary = {}) -> void:
	if ctx.is_empty():
		ctx = _ctx
	match ctx.get("type", ""):
		"enter": enter_house(ctx["id"])
		"exit": exit_house()
		"sit":
			_ask(Session.sit(ctx["id"]), func(r):
				if r.get("ok"):
					walking = false
					_walk_target = null)
		"stand": stand_up()
		"bell": Session.ring_bell()


func enter_house(id: String) -> void:
	if not Session.model.is_space(id) or id == "town":
		return
	cancel_ghost()
	space = id
	pos = TownModel.ROOM_SPAWN
	ry = 0.0
	_walk_target = null
	world.set_view(id)
	rig.set_room(true)
	_place_kid()
	_send_state()
	space_changed.emit(space)


func exit_house() -> void:
	var house: Dictionary = Session.model.items.get(space, {})
	cancel_ghost()
	if house.is_empty():
		pos = TownModel.TOWN_SPAWN
	else:
		pos = world_resolve_in("town", TownModel.door_point(house) + TownModel.facing(house["rot"]) * 0.4)
		ry = TownModel.rot_to_radians(house["rot"])
	space = "town"
	_walk_target = null
	world.set_view("town")
	rig.set_room(false)
	_place_kid()
	rig.snap()
	_send_state()
	space_changed.emit(space)


func world_resolve_in(_space: String, p: Vector2) -> Vector2:
	return world.resolve_walk(p)


func stand_up() -> void:
	var seat := Session.seat_of(Session.my_id)
	if seat.is_empty():
		return
	var item: Dictionary = Session.model.items.get(seat[0], {})
	Session.stand()
	if not item.is_empty():
		var def := Catalog.get_def(item["kind"])
		pos = world.resolve_walk(Vector2(item["x"], item["z"]) + TownModel.facing(item["rot"]) * (def["radius"] + 0.45))
		ry = TownModel.rot_to_radians(item["rot"])
	var kid: Node3D = world.local_kid()
	if kid:
		kid.anim = "idle"
	_place_kid()


func _on_view_changed(view: String) -> void:
	# The house we were in was put away by a friend: step back outside.
	if view != space:
		space = view
		pos = world.resolve_walk(TownModel.TOWN_SPAWN)
		rig.set_room(view != "town")
		cancel_ghost()
		_place_kid()
		space_changed.emit(space)


# ------------------------------------------------------------- decorating

func set_mode(m: String) -> void:
	if m == mode:
		return
	if m == "play":
		cancel_ghost()
	elif _seated():
		stand_up()
	mode = m
	_refresh_context()
	mode_changed.emit(mode)


func begin_new(kind: String) -> void:
	cancel_ghost()
	if not Catalog.allowed_in(kind, space):
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
	ghost.position = Vector3(g_pos.x, 0, g_pos.y)
	_validate_ghost()


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
	if ghost:
		g_rot = posmod(g_rot + 1, 8)
		var model := ghost.get_node("Model") as Node3D
		create_tween().tween_property(model, "rotation:y", model.rotation.y + TAU / 8.0, 0.15)
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
	g_error = Session.model.check(g_kind, space, g_pos.x, g_pos.y, g_rot, g_edit_id)
	if g_error == "" and g_pos.distance_to(pos) < 0.2 + Catalog.get_def(g_kind)["radius"] and Catalog.get_def(g_kind)["layer"] == "solid":
		g_error = "Step aside so it does not land on you."
	var m := _ghost_ring.material_override as StandardMaterial3D
	m.albedo_color = Color("#7cc28a") if g_error == "" else Color("#ef8a73")
	ghost_changed.emit(ghost_info())


func ghost_info() -> Dictionary:
	if ghost == null:
		return {}
	return {"kind": g_kind, "editing": g_edit_id != "", "error": g_error, "color": g_color,
		"paintable": Catalog.get_def(g_kind)["color"] >= 0}


func confirm_ghost() -> void:
	if ghost == null or g_error != "":
		if g_error != "":
			hint.emit(g_error)
		return
	if g_edit_id == "":
		_ask(Session.place(g_kind, space, g_pos, g_rot, g_color), func(r):
			if r.get("ok"):
				_push_undo({"type": "place", "id": r["item"]["id"]})
				toast.emit("Placed! Pick another, or tap Done.")
				Sfx.play("place"))
		_clear_ghost()
	else:
		var id := g_edit_id
		var orig := _g_orig
		var moved: bool = not (is_equal_approx(orig["x"], g_pos.x) and is_equal_approx(orig["z"], g_pos.y)) or orig["rot"] != g_rot
		var painted: bool = orig["color"] != g_color
		if moved:
			_ask(Session.move(id, g_pos, g_rot), func(r):
				if r.get("ok"):
					_push_undo({"type": "move", "id": id, "x": orig["x"], "z": orig["z"], "rot": orig["rot"]})
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
			toast.emit("Last action undone.")
	match e["type"]:
		"place": _ask(Session.remove(e["id"]), done)
		"move": _ask(Session.move(e["id"], Vector2(e["x"], e["z"]), e["rot"]), done)
		"paint": _ask(Session.paint(e["id"], e["color"]), done)
		"remove": _ask(Session.restore(e["items"]), done)
