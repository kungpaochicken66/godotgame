## House visits (r18, design/animal-visits.md): an animal friend visiting a child is drawn in the room
## that child is in, by every device showing that room. It follows the child (doors and stairs too), like
## a following pet, and answers emotes made in that room with a move of its own. Drawn from the shared
## visit list (Animals.guests) and the child's position; never blocks walking or taps on items.
extends Node3D

const AnimalScript := preload("res://scripts/art/animal.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")
const TownModel := preload("res://scripts/core/town_model.gd")

const GAP := 1.0          # behind the child
const ANSWER_SECONDS := 2.0

var world: Node3D
var guests := {}          # kind -> animal node in this room
var _answer := {}         # kind -> [action, until]
var _t := 0.0


func setup(w: Node3D) -> void:
	world = w
	Animals.guests_changed.connect(func(_g): rebuild())
	Session.players_changed.connect(rebuild)
	Session.player_state.connect(func(_p, _s): rebuild())
	world.view_changed.connect(func(_s): rebuild())
	Session.emote.connect(_on_emote)
	I18n.locale_changed.connect(func(_c):
		for n in guests.values():
			n.refresh_label())


## Visitors whose child is in the room on screen: {kind: peer}.
func wanted() -> Dictionary:
	var out := {}
	if world.view_space == "town":
		return out
	for kind in Animals.guests:
		var peer: int = Animals.guests[kind]
		if Session.players.has(peer) and world.space_of(peer) == world.view_space:
			out[kind] = peer
	return out


func rebuild() -> void:
	var want := wanted()
	for kind in guests.keys():
		if not want.has(kind):
			guests[kind].queue_free()
			guests.erase(kind)
	for kind in want:
		if guests.has(kind):
			continue
		var n: Node3D = AnimalScript.new()
		n.setup(kind)
		add_child(n)
		guests[kind] = n
		var p := _spot(kind, want[kind])
		n.set_state({"pos": p, "ry": 0.0, "action": "greet", "ball": p}, true)
		n.show_name(true)


## Where a visitor stands: behind its child, inside the room's walls.
func _spot(kind: String, peer: int) -> Vector2:
	var kid: Node3D = world.kids.get(peer)
	if kid == null:
		return Vector2.ZERO
	var back := Vector2(-sin(kid.rotation.y), -cos(kid.rotation.y)) * GAP
	var p := Vector2(kid.position.x, kid.position.z) + back
	var r: float = AnimalBrain.SPECIES[kind]["radius"]
	return Vector2(clampf(p.x, -TownModel.ROOM_HALF.x + r, TownModel.ROOM_HALF.x - r),
		clampf(p.y, -TownModel.ROOM_HALF.y + r, TownModel.ROOM_HALF.y - r))


func _on_emote(peer: int, kind: String) -> void:
	if not AnimalBrain.COPY.has(kind):
		return
	if world.space_of(peer) != world.view_space:
		return
	for g in guests:
		_answer[g] = [AnimalBrain.COPY[kind], _t + ANSWER_SECONDS]
		var n: Node3D = guests[g]
		var kid: Node3D = world.kids.get(peer)
		if kid:
			n._target_ry = atan2(kid.position.x - n.position.x, kid.position.z - n.position.z)


func _process(delta: float) -> void:
	_t += delta
	var want := wanted()
	for kind in guests:
		if not want.has(kind):
			continue
		var n: Node3D = guests[kind]
		var p := _spot(kind, want[kind])
		var here := Vector2(n.position.x, n.position.z)
		var moving := here.distance_to(p) > 0.15
		var ans: Array = _answer.get(kind, ["", -1.0])
		var action: String = ans[0] if _t < ans[1] else (AnimalBrain.SPECIES[kind]["move"] if moving else "idle")
		var ry: float = atan2(p.x - here.x, p.y - here.y) if moving else n._target_ry
		n.set_state({"pos": p if moving else here, "ry": ry, "action": action, "ball": here + Vector2(0.3, 0.3)})


## The visitor under a screen point, if any.
func pick(camera: Camera3D, screen: Vector2) -> String:
	var best := ""
	var best_d := 60.0
	for k in guests:
		var c: Vector3 = guests[k].global_position + Vector3(0, 0.4, 0)
		if camera.is_position_behind(c):
			continue
		var d := camera.unproject_position(c).distance_to(screen)
		if d < best_d:
			best_d = d
			best = k
	return best
