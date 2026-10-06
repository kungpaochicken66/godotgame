## Animal friends who roam the town and play by themselves.
##
## Pure, deterministic simulation (seeded RNG, fixed time step) that runs only
## on the authority; clients just draw the broadcast states. Animals read the
## town model and children's positions but never change the town, are never
## saved, and never block placement: if an item lands on an animal, the animal
## steps aside.
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

## Each species has a favorite activity ("hobby") that shapes where it goes.
const SPECIES := {
	"pig": {"name": "Pip", "hobby": "%s loves splashing in muddy puddles!", "speed": 1.4, "radius": 0.45,
		"likes": ["pond"], "play": "splash", "move": "walk"},
	"rabbit": {"name": "Bramble", "hobby": "%s loves hopping and gardening!", "speed": 2.0, "radius": 0.35,
		"likes": ["flowers", "bush", "plant", "tree"], "play": "garden", "move": "hop"},
	"sheep": {"name": "Wooly", "hobby": "%s loves music and dancing!", "speed": 1.1, "radius": 0.5,
		"likes": ["lamp_post", "bench", "swing", "seesaw"], "play": "sing", "move": "walk"},
	"dog": {"name": "Biscuit", "hobby": "%s loves playing ball!", "speed": 2.4, "radius": 0.4,
		"likes": [], "play": "ball", "move": "walk"},
	"elephant": {"name": "Tumble", "hobby": "%s loves exploring every corner!", "speed": 0.9, "radius": 0.8,
		"likes": [], "play": "look", "move": "walk"},
}
const ORDER := ["pig", "rabbit", "sheep", "dog", "elephant"]
## Broadcast action names (index is sent over the network).
const ACTIONS := ["idle", "walk", "hop", "run", "splash", "garden", "sing", "dance", "ball", "look", "spray", "greet", "rest", "chat"]
const STEP := 0.1
## Exploration grid for the elephant: 7 x 7 cells spanning the whole town.
const CELL := TownModel.TOWN_HALF / 3.6
const SPAWNS := [Vector2(-5, 8), Vector2(-9, 2), Vector2(4, 9.5), Vector2(-2, 11), Vector2(12, 14)]

var animals: Array = []      # Array of Dictionary, one per species in ORDER
var rng := RandomNumberGenerator.new()
var time := 0.0
var _visits := {}            # explored grid cell -> visit count (elephant)


func _init(seed := 2026) -> void:
	rng.seed = seed


## Places the cast on free ground. Call after a town is loaded.
func spawn(model) -> void:
	animals.clear()
	for i in ORDER.size():
		var kind: String = ORDER[i]
		var def: Dictionary = SPECIES[kind]
		var p := _free_near(model, SPAWNS[i], def["radius"])
		animals.append({"kind": kind, "pos": p, "ry": rng.randf() * TAU, "action": "idle",
			"goal": null, "plan": "", "timer": rng.randf_range(0.5, 2.0), "ball": p + Vector2(0.8, 0),
			"progress_t": 0.0, "best_d": INF, "greeted": {}, "partner": -1, "kicks": 0})


## Advances the simulation. kids: Array of {"id": int, "pos": Vector2, "emote": String}.
func tick(model, kids: Array, dt := STEP) -> void:
	time += dt
	for i in animals.size():
		_think(model, kids, i, dt)
	for i in animals.size():
		_move(model, kids, i, dt)


# ------------------------------------------------------------- decisions

func _think(model, kids: Array, i: int, dt: float) -> void:
	var a: Dictionary = animals[i]
	var def: Dictionary = SPECIES[a["kind"]]
	# Greet a child who comes close (once in a while per child).
	if a["plan"] in ["", "wander", "rest", "play"] and a["goal"] == null:
		for k in kids:
			if k["pos"].distance_to(a["pos"]) < 2.4 and time - a["greeted"].get(k["id"], -99.0) > 20.0:
				a["greeted"][k["id"]] = time
				_do(a, "greet", 2.0)
				a["ry"] = _face(a["pos"], k["pos"])
				return
	# The sheep cannot resist joining a dancing child.
	if a["kind"] == "sheep" and a["plan"] != "dance":
		for k in kids:
			if k.get("emote", "") == "dance" and k["pos"].distance_to(a["pos"]) < 10.0:
				a["plan"] = "dance"
				a["goal"] = _free_near(model, k["pos"] + Vector2(1.2, 0.4), def["radius"])
				return
	if a["goal"] != null:
		return
	a["timer"] -= dt
	if a["timer"] > 0.0:
		_continue_activity(model, kids, a)
		return
	_choose(model, kids, i)


func _choose(model, kids: Array, i: int) -> void:
	var a: Dictionary = animals[i]
	var def: Dictionary = SPECIES[a["kind"]]
	var roll := rng.randf()
	var hobby_spot = _hobby_spot(model, kids, a)
	if roll < 0.55 and hobby_spot != null:
		a["plan"] = "play"
		a["goal"] = hobby_spot
	elif roll < 0.7:
		var friend := _pick_friend(i)
		if friend >= 0:
			a["plan"] = "chat"
			a["partner"] = friend
			a["goal"] = _free_near(model, animals[friend]["pos"].lerp(a["pos"], 0.3), def["radius"])
		else:
			_wander(model, a)
	elif roll < 0.8:
		_do(a, "rest", rng.randf_range(3.0, 5.0))
		a["plan"] = "rest"
	else:
		_wander(model, a)


func _wander(model, a: Dictionary) -> void:
	var def: Dictionary = SPECIES[a["kind"]]
	a["plan"] = "wander"
	var d := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 7.0)
	a["goal"] = _free_near(model, a["pos"] + d, def["radius"])


## Where this species likes to play right now, or null.
func _hobby_spot(model, kids: Array, a: Dictionary) -> Variant:
	var def: Dictionary = SPECIES[a["kind"]]
	var r: float = def["radius"]
	match a["kind"]:
		"dog":
			# Ball games happen near children when anyone is around, otherwise on open lawn.
			if not kids.is_empty():
				var k: Dictionary = kids[rng.randi() % kids.size()]
				return _free_near(model, k["pos"] + Vector2.from_angle(rng.randf() * TAU) * 2.5, r)
			return _free_near(model, Vector2(rng.randf_range(-8, 8), rng.randf_range(2, 10)), r)
		"elephant":
			return _free_near(model, _least_visited_cell(), r)
	var spots := []
	for item in model.items_in("town"):
		if item["kind"] in def["likes"]:
			spots.append(item)
	if spots.is_empty():
		return null
	var item: Dictionary = spots[rng.randi() % spots.size()]
	var c := Vector2(item["x"], item["z"])
	var reach: float = Catalog.get_def(item["kind"])["radius"] + r + 0.25
	return _free_near(model, c + Vector2.from_angle(rng.randf() * TAU) * reach, r)


func _least_visited_cell() -> Vector2:
	var best := Vector2.ZERO
	var best_n := INF
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var n: float = _visits.get(Vector2i(cx, cz), 0) + rng.randf() * 0.5
			if n < best_n:
				best_n = n
				best = Vector2(cx, cz) * CELL
	return best


func _pick_friend(i: int) -> int:
	var options := []
	for j in animals.size():
		if j != i and animals[j]["plan"] in ["", "wander", "rest"] and animals[j]["pos"].distance_to(animals[i]["pos"]) < 12.0:
			options.append(j)
	return options[rng.randi() % options.size()] if not options.is_empty() else -1


func _do(a: Dictionary, action: String, seconds: float) -> void:
	a["action"] = action
	a["timer"] = seconds
	a["goal"] = null


## Called when a goal is reached.
func _arrive(model, a: Dictionary) -> void:
	var def: Dictionary = SPECIES[a["kind"]]
	match a["plan"]:
		"play":
			var action: String = def["play"]
			if a["kind"] == "elephant":
				_visits[_cell(a["pos"])] = _visits.get(_cell(a["pos"]), 0) + 1
				action = "spray" if _near_kind(model, a["pos"], "pond", 3.6) else "look"
			_do(a, action, 1.0 if a["kind"] == "dog" else rng.randf_range(4.0, 7.0))
			if a["kind"] == "dog":
				a["kicks"] = 3
				a["ball"] = a["pos"]
			for item in model.items_in("town"):
				if item["kind"] in def["likes"] and Vector2(item["x"], item["z"]).distance_to(a["pos"]) < 4.0:
					a["ry"] = _face(a["pos"], Vector2(item["x"], item["z"]))
					break
		"chat":
			var p: int = a["partner"]
			if p >= 0 and p < animals.size() and animals[p]["pos"].distance_to(a["pos"]) < 2.6:
				_do(a, "chat", 3.0)
				a["ry"] = _face(a["pos"], animals[p]["pos"])
				var b: Dictionary = animals[p]
				if b["goal"] == null and b["plan"] != "play":
					_do(b, "chat", 3.0)
					b["plan"] = "chat"
					b["ry"] = _face(b["pos"], a["pos"])
			else:
				_do(a, "idle", 1.0)
		"dance":
			_do(a, "dance", 4.0)
		"fetch":
			# The dog reached the ball and kicks it again.
			a["kicks"] -= 1
			if a["kicks"] > 0:
				_do(a, "ball", 0.6)
			else:
				_do(a, "idle", 1.5)
		_:
			_do(a, "idle", rng.randf_range(1.0, 3.0))


## Ongoing activity details while the timer runs.
func _continue_activity(model, kids: Array, a: Dictionary) -> void:
	if a["kind"] == "dog" and a["action"] == "ball" and a["timer"] < 0.15 and a["kicks"] > 0:
		# Kick the ball a few meters, then run after it.
		var ang: float = a["ry"] + rng.randf_range(-0.9, 0.9)
		var dir := Vector2(sin(ang), cos(ang))   # facing convention: rot 0 looks along +z
		a["ball"] = _free_near(model, a["pos"] + dir * rng.randf_range(3.0, 5.0), 0.2)
		a["plan"] = "fetch"
		a["goal"] = a["ball"]


# ------------------------------------------------------------- movement

func _move(model, kids: Array, i: int, dt: float) -> void:
	var a: Dictionary = animals[i]
	var def: Dictionary = SPECIES[a["kind"]]
	var r: float = def["radius"]
	var p: Vector2 = a["pos"]
	if a["goal"] != null:
		var goal: Vector2 = a["goal"]
		var to := goal - p
		if to.length() < 0.25:
			a["goal"] = null
			a["best_d"] = INF
			_arrive(model, a)
		else:
			var speed: float = def["speed"] * (1.5 if a["plan"] == "fetch" else 1.0)
			var dir := to.normalized()
			# Gentle separation from other animals and children.
			for j in animals.size():
				if j != i:
					var away: Vector2 = p - animals[j]["pos"]
					var gap: float = away.length()
					if gap < 1.0 + r and gap > 0.01:
						dir += away.normalized() * (1.0 + r - gap) * 1.5
			for k in kids:
				var away: Vector2 = p - k["pos"]
				if away.length() < 0.9 and away.length() > 0.01:
					dir += away.normalized() * 0.8
			p += dir.normalized() * minf(speed * dt, to.length())
			a["ry"] = lerp_angle(a["ry"], atan2(dir.x, dir.y), minf(1.0, dt * 8.0))
			a["action"] = "run" if a["plan"] == "fetch" else def["move"]
			_check_stuck(model, a, to.length(), dt)
	elif a["action"] in ["walk", "hop", "run"]:
		a["action"] = "idle"
	var next := resolve(model, p, r)
	# Never squeeze into a gap narrower than the animal: stay put and re-plan instead.
	if not is_clear(model, next, r) and is_clear(model, a["pos"], r):
		next = a["pos"]
	a["pos"] = next
	if a["kind"] == "dog" and a["plan"] == "fetch" and a["goal"] != null:
		a["ball"] = a["goal"]


## Gives up on goals it cannot get closer to (blocked by new items or a crowd).
func _check_stuck(model, a: Dictionary, dist: float, dt: float) -> void:
	a["progress_t"] += dt
	if dist < a["best_d"] - 0.15:
		a["best_d"] = dist
		a["progress_t"] = 0.0
	elif a["progress_t"] > 1.5:
		a["progress_t"] = 0.0
		a["best_d"] = INF
		a["goal"] = null
		a["plan"] = ""
		_wander(model, a)


## Keeps an animal out of solid items, the Wishing Tree and off the town edge.
static func resolve(model, p: Vector2, r: float) -> Vector2:
	var half := TownModel.TOWN_HALF
	# A few passes: stepping out of one item can step into a neighbor.
	for pass_i in 8:
		var moved := false
		for item in model.items_in("town"):
			var def := Catalog.get_def(item["kind"])
			if def["layer"] != "solid" or item.has("host"):
				continue
			var c := Vector2(item["x"], item["z"])
			var min_d: float = def["radius"] * 0.9 + r
			var d := p - c
			if d.length() < min_d - 0.001:
				p = c + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * min_d
				moved = true
		var t := TownModel.WISHING_TREE
		if p.distance_to(t) < 1.1 + r - 0.001:
			p = t + (p - t).normalized() * (1.1 + r)
			moved = true
		var clamped := Vector2(clampf(p.x, -half.x + r, half.x - r), clampf(p.y, -half.y + r, half.y - r))
		moved = moved or clamped != p
		p = clamped
		if not moved:
			break
	return p


static func is_clear(model, p: Vector2, r: float) -> bool:
	return resolve(model, p, r).distance_to(p) < 0.05   # footprints are approximate circles


func _free_near(model, p: Vector2, r: float) -> Vector2:
	for ring in 8:
		for s in maxi(1, ring * 6):
			var q := p + Vector2.from_angle(TAU * s / maxi(1, ring * 6)) * ring * 0.5
			if is_clear(model, q, r):
				return q
	return resolve(model, p, r)


func _near_kind(model, p: Vector2, kind: String, dist: float) -> bool:
	for item in model.items_in("town"):
		if item["kind"] == kind and Vector2(item["x"], item["z"]).distance_to(p) < dist:
			return true
	return false


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL.x), roundi(p.y / CELL.y))


static func _face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


# ------------------------------------------------------------- network form

## Compact state for broadcasting: 6 floats per animal.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for a in animals:
		out.append_array([a["pos"].x, a["pos"].y, a["ry"], float(ACTIONS.find(a["action"])), a["ball"].x, a["ball"].y])
	return out


static func unpack(data: PackedFloat32Array) -> Array:
	var out := []
	for i in range(0, data.size() - 5, 6):
		var idx := i / 6
		if idx >= ORDER.size():
			break
		out.append({"kind": ORDER[idx], "pos": Vector2(data[i], data[i + 1]), "ry": data[i + 2],
			"action": ACTIONS[clampi(int(data[i + 3]), 0, ACTIONS.size() - 1)], "ball": Vector2(data[i + 4], data[i + 5])})
	return out
