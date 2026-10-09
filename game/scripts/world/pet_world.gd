## Shows every adopted pet: the one each child chose follows that child (seen by
## everyone in the same room or in town), the others rest in their owner's Pet
## room by the matching furniture. Pets are drawn by each device from the shared
## pet data and the owners' positions; they never block walking or taps on items.
extends Node3D

const PetScript := preload("res://scripts/art/pet.gd")
const PetRules := preload("res://scripts/core/pets.gd")

## Where a resting pet likes to be: furniture kind and marker, in order.
const HOME_SPOTS := {
	"cat": [["petroom_cat_tree", "Rest0"], ["petroom_bed_round", "Sleep0"], ["petroom_scratch_post", ""]],
	"dog": [["petroom_dog_house", "Sleep0"], ["petroom_bed_round", "Sleep0"], ["petroom_toy_bone", ""]],
	"bird": [["petroom_perch_stand", "Perch0"], ["petroom_bird_cage", "Perch0"]],
	"butterfly": [["petroom_butterfly_house", "Perch0"], ["plant", ""], ["flower_pot_bloom", ""]],
}
const FOLLOW_GAP := 0.8

var world: Node3D
var pets := {}        # "pid/pet_id" -> pet node
var _homes := {}      # key -> Vector3 resting point (rooms only)
var _t := 0.0
var _owner_spaces := ""   # where every pet owner is, to notice a door or stairs
var _check := 0.0


func setup(w: Node3D) -> void:
	world = w
	Session.town_data_changed.connect(func(key):
		if key == "pets":
			rebuild())
	Session.town_reset.connect(rebuild)
	Session.players_changed.connect(rebuild)
	Session.item_changed.connect(func(_i): _place_homes())
	Session.items_removed.connect(func(_ids): _place_homes())
	Session.pet_happy.connect(func(owner, pet_id, _action, _nick):
		var n: Node3D = pets.get(owner + "/" + pet_id)
		if n:
			n.happy())
	world.view_changed.connect(func(_s): rebuild())
	I18n.locale_changed.connect(func(_c):
		for n in pets.values():
			n.refresh_label())


func _owner_peer(pid: String) -> int:
	for peer in Session.players:
		if Session.players[peer].get("pid", "") == pid:
			return peer
	return 0


## Which pets belong in the room on screen, and how ({key: {pid, pet, follow_peer}}).
func wanted() -> Dictionary:
	var out := {}
	for pid in Session.model.pets:
		var e: Dictionary = Session.model.pets[pid]
		var peer := _owner_peer(pid)
		var owner_space: String = Session.players.get(peer, {}).get("state", {}).get("space", "") if peer != 0 else ""
		for pet in e["pets"]:
			var following: bool = peer != 0 and e["active"] == pet["id"] and e["mode"] == "follow"
			var space: String = owner_space if following else PetRules.pet_room(Session.model, pid)
			if space == world.view_space:
				out[pid + "/" + pet["id"]] = {"pid": pid, "pet": pet, "follow_peer": peer if following else 0}
	return out


func rebuild() -> void:
	if world == null:
		return
	var want := wanted()
	for key in pets.keys():
		var w: Dictionary = want.get(key, {})
		var n: Node3D = pets[key]
		if w.is_empty() or n.family != w["pet"]["family"] or n.get_meta("color") != w["pet"]["color"] or n.pet_name != w["pet"]["name"]:
			n.queue_free()
			pets.erase(key)
	for key in want:
		var w: Dictionary = want[key]
		var n: Node3D = pets.get(key)
		if n == null:
			n = PetScript.new()
			n.setup(w["pet"]["family"], w["pet"]["color"], w["pet"]["name"])
			n.set_meta("color", w["pet"]["color"])
			n.owner_pid = w["pid"]
			n.pet_id = w["pet"]["id"]
			add_child(n)
			pets[key] = n
			_snap(n, w)
		n.set_meta("follow_peer", w["follow_peer"])
	_place_homes()


## Resting spots by the matching furniture of the Pet room on screen.
func _place_homes() -> void:
	_homes.clear()
	var used := {}
	var i := 0
	for key in pets:
		var n: Node3D = pets[key]
		if int(n.get_meta("follow_peer", 0)) != 0:
			continue
		var spot := Vector3(-1.5 + (i % 4) * 1.0, 0, 1.2 - (i / 4) * 0.8)
		for pref in HOME_SPOTS.get(n.family, []):
			var found := false
			for id in world.item_nodes:
				var node: Node3D = world.item_nodes[id]
				if node.get_meta("item")["kind"] != pref[0] or used.has(id + pref[1]):
					continue
				var m := node.find_child(pref[1], true, false) as Node3D if pref[1] != "" else null
				spot = m.global_position if m else node.global_position + Vector3(0.5, 0, 0.4)
				used[id + pref[1]] = true
				found = true
				break
			if found:
				break
		if n.flying() and spot.y < 0.3:
			spot.y = PetRules.HOVER[n.family]
		_homes[key] = spot
		i += 1


func _snap(n: Node3D, w: Dictionary) -> void:
	var kid: Node3D = world.kids.get(w["follow_peer"]) if w["follow_peer"] != 0 else null
	if kid:
		n.global_position = kid.global_position + Vector3(0.5, PetRules.HOVER[n.family] + 0.5 if n.flying() else 0.0, -0.5)


## Owners move between rooms after the view changes (and friends move on their
## own), so a few times a second the layer checks where every owner is.
func _owner_signature() -> String:
	var parts := []
	for pid in Session.model.pets:
		var peer := _owner_peer(pid)
		parts.append("%s=%s" % [pid, Session.players.get(peer, {}).get("state", {}).get("space", "") if peer != 0 else ""])
	return ",".join(parts)


func _process(delta: float) -> void:
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		var sig := _owner_signature()
		if sig != _owner_spaces:
			_owner_spaces = sig
			rebuild()
	for key in pets:
		var n: Node3D = pets[key]
		var peer := int(n.get_meta("follow_peer", 0))
		var target: Vector3
		if peer != 0:
			var kid: Node3D = world.kids.get(peer)
			if kid == null or not kid.visible:
				n.visible = false
				continue
			n.visible = true
			var ry: float = kid.rotation.y
			var fwd := Vector3(sin(ry), 0, cos(ry))
			var right := Vector3(cos(ry), 0, -sin(ry))
			# Beside and a little behind, so the pet stays in view when the child walks toward the camera.
			target = kid.global_position - fwd * FOLLOW_GAP * 0.4 + right * 0.75
			if n.flying():
				# Hover a little above the handoff's suggested height so it stays in view beside the child.
				target += Vector3(sin(_t * 1.7 + n.get_instance_id() % 7) * 0.25, PetRules.HOVER[n.family] + 0.5 + sin(_t * 2.3) * 0.1, 0)
		else:
			n.visible = true
			target = _homes.get(key, n.global_position)
			if n.flying():
				target += Vector3(sin(_t * 1.1) * 0.12, 0.05 + sin(_t * 2.0) * 0.04, cos(_t * 0.9) * 0.12)
		var to := target - n.global_position
		var dist := to.length()
		var step := minf(dist, (5.0 if dist > 3.0 else 2.6) * delta)
		if dist > 6.0:
			n.global_position = target   # caught up after a door or stairs
			step = 0.0
		elif dist > 0.05:
			n.global_position += to / dist * step
		n.speed = step / maxf(delta, 0.0001)
		var flat := Vector2(to.x, to.z)
		if flat.length() > 0.08:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(flat.x, flat.y), minf(1.0, delta * 8.0))


## The pet under a screen point: {owner, pet_id} or {}.
func pick(camera: Camera3D, screen: Vector2) -> Dictionary:
	var best := {}
	var best_d := 56.0
	for key in pets:
		var n: Node3D = pets[key]
		if not n.visible:
			continue
		var c := n.global_position + Vector3(0, 0.0 if n.flying() else 0.25, 0)
		if camera.is_position_behind(c):
			continue
		var d := camera.unproject_position(c).distance_to(screen)
		if d < best_d:
			best_d = d
			best = {"owner": n.owner_pid, "pet_id": n.pet_id}
	return best
