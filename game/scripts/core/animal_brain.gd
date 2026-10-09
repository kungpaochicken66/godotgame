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
		"likes": ["garden_bed", "flowers", "bush", "plant", "tree"], "play": "garden", "move": "hop"},
	"sheep": {"name": "Wooly", "hobby": "%s loves music and dancing!", "speed": 1.1, "radius": 0.5,
		"likes": ["lamp_post", "bench", "swing", "seesaw"], "play": "sing", "move": "walk"},
	"dog": {"name": "Biscuit", "hobby": "%s loves playing ball!", "speed": 2.4, "radius": 0.4,
		"likes": [], "play": "ball", "move": "walk"},
	"elephant": {"name": "Tumble", "hobby": "%s loves exploring every corner!", "speed": 0.9, "radius": 0.8,
		"likes": [], "play": "look", "move": "walk"},
}
const ORDER := ["pig", "rabbit", "sheep", "dog", "elephant"]
## Broadcast action names (index is sent over the network).
## New actions go at the end so the indices of older ones stay the same.
const ACTIONS := ["idle", "walk", "hop", "run", "splash", "garden", "sing", "dance", "ball", "look", "spray", "greet", "rest", "chat", "carry"]
## Fetch with a child (design/playability-8-12.md F03): how far a ball flies and
## how close to the dog a child must stand to throw.
const THROW_MAX := 8.0
const THROW_REACH := 8.0
## The dog gives the ball back once it is this close to the thrower.
const BRING_REACH := 1.3
## Each animal's own game with children (F03, r11). Biscuit's is fetch (above).
const GAMES := {"sheep": "copy", "rabbit": "tend", "pig": "splash_with", "elephant": "fountain"}
const GAME_PLANS := ["game_go", "copy", "tend", "splash_with", "fountain"]
## Wooly answers a child's emote with its own move (call and response).
## (Answers are standing moves: hop and walk belong to moving and would be reset.)
const COPY := {"wave": "greet", "cheer": "sing", "dance": "dance", "heart": "chat"}
const FOUNTAINS := ["heart", "star", "round"]
## A copy game ends this long after the last emote it answered.
const COPY_SECONDS := 40.0
const STEP := 0.1
## Exploration grid for the elephant: 7 x 7 cells spanning the whole town.
const CELL := TownModel.TOWN_HALF / 3.6
const SPAWNS := [Vector2(-5, 8), Vector2(-9, 2), Vector2(4, 9.5), Vector2(-2, 11), Vector2(12, 14)]

var animals: Array = []      # Array of Dictionary, one per species in ORDER
var rng := RandomNumberGenerator.new()
var time := 0.0
var _visits := {}            # explored grid cell -> visit count (elephant)
## Dance parade (activity E): while time < parade_until, everyone circles the tree.
var parade_until := -1.0
## Things the authority must do for the animals (the brain never edits the town):
## {"kind": "grow", "id"} after Bramble tends a bed; {"kind": "fountain", "shape", "at"}.
var events := []


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
			"progress_t": 0.0, "best_d": INF, "greeted": {}, "partner": -1, "kicks": 0, "thrower": 0,
			"playmates": [], "game_until": 0.0, "copied_t": 0.0, "option": 0, "target_id": ""})


## Advances the simulation. kids: Array of {"id": int, "pos": Vector2, "emote": String}.
func tick(model, kids: Array, dt := STEP) -> void:
	time += dt
	if time < parade_until:
		_parade(model, dt)
		return
	for i in animals.size():
		_think(model, kids, i, dt)
	for i in animals.size():
		_move(model, kids, i, dt)


# ------------------------------------------------------------- celebrations

## A wish came true: the animal runs to the spot and dances there.
func celebrate(kind: String, at: Vector2, model) -> void:
	for a in animals:
		if a["kind"] == kind:
			a["plan"] = "dance"
			a["goal"] = _free_near(model, at + Vector2(0.8, 0.8), SPECIES[kind]["radius"])
			a["progress_t"] = 0.0
			a["best_d"] = INF


## Fetch: a child at `from` threw the ball toward `to`. The dog runs after it
## ("chase") and carries it back to that child ("bring"). Returns where the ball
## lands (clamped to THROW_MAX and moved off solid things), or null when the dog
## cannot play now (the parade, or it is bringing someone else's ball).
func throw_ball(model, thrower: int, from: Vector2, to: Vector2) -> Variant:
	var a := dog()
	if a.is_empty() or time < parade_until:
		return null
	if a["plan"] == "bring" and a["thrower"] != thrower:
		return null
	var d := to - from
	if d.length() > THROW_MAX:
		to = from + d.normalized() * THROW_MAX
	# The dog runs in straight lines (no path finding), so the ball stops at the
	# farthest point along the throw that the dog can run to and back from: it
	# "bounces" off a bench or tree instead of landing where the dog cannot go.
	# A throw into something close glances off to the side (up to 80 degrees).
	var r: float = SPECIES["dog"]["radius"]
	var land := a["pos"] as Vector2
	var best := -1.0
	var want := from.distance_to(to)
	for turn in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
		var end: Vector2 = from + (to - from).rotated(deg_to_rad(turn))
		var steps := int(ceilf(want / 0.25))
		for i in range(steps, -1, -1):
			var p: Vector2 = from.lerp(end, float(i) / maxf(1.0, steps))
			if is_clear(model, p, r) and _clear_line(model, a["pos"], p, r) and _clear_line(model, p, from, r):
				if from.distance_to(p) > best:
					best = from.distance_to(p)
					land = p
				break
		if best >= 0.6 * want:
			break
	a["ball"] = land
	a["thrower"] = thrower
	a["kicks"] = 0
	a["plan"] = "chase"
	a["goal"] = land
	a["progress_t"] = 0.0
	a["best_d"] = INF
	return land


## A child asks an animal to play its game. Returns "started", "joined" (the game
## is already on: the child joins it), or "" when the animal cannot play now.
## target: where to play (a pond edge, a garden bed) or Vector2.INF for "by the child".
func play_with(model, kind: String, peer: int, at: Vector2, option := 0, target: Variant = null, target_id := "") -> String:
	if not GAMES.has(kind) or time < parade_until:
		return ""
	var a := {}
	for x in animals:
		if x["kind"] == kind:
			a = x
	if a.is_empty():
		return ""
	if a["plan"] in GAME_PLANS:
		if not a["playmates"].has(peer):
			a["playmates"].append(peer)
		return "joined"
	var r: float = SPECIES[kind]["radius"]
	a["playmates"] = [peer]
	a["option"] = posmod(option, FOUNTAINS.size())
	a["target_id"] = target_id
	a["plan"] = "game_go"
	a["goal"] = _free_near(model, target if target != null else at + Vector2(1.4, 0.8), r)
	a["progress_t"] = 0.0
	a["best_d"] = INF
	return "started"


func dog() -> Dictionary:
	for a in animals:
		if a["kind"] == "dog":
			return a
	return {}


func start_parade(seconds: float) -> void:
	parade_until = time + seconds
	for i in animals.size():
		animals[i]["parade_angle"] = TAU * i / animals.size()


func stop_parade() -> void:
	parade_until = -1.0
	for a in animals:
		a["goal"] = null
		a["plan"] = ""
		_do(a, "idle", 1.0)


## Everyone dances around the Wishing Tree in a circle.
func _parade(model, dt: float) -> void:
	var center := TownModel.WISHING_TREE
	for a in animals:
		var angle: float = a.get("parade_angle", 0.0) + dt * 0.35
		a["parade_angle"] = angle
		var target := center + Vector2(cos(angle), sin(angle)) * 4.6
		var d: Vector2 = target - a["pos"]
		var step: float = minf(d.length(), SPECIES[a["kind"]]["speed"] * 1.2 * dt)
		if d.length() > 0.01:
			a["pos"] = resolve(model, a["pos"] + d.normalized() * step, SPECIES[a["kind"]]["radius"])
			a["ry"] = atan2(d.x, d.y)
		a["action"] = "dance" if d.length() < 0.6 else "walk"
		a["goal"] = null


# ------------------------------------------------------------- decisions

func _think(model, kids: Array, i: int, dt: float) -> void:
	var a: Dictionary = animals[i]
	var def: Dictionary = SPECIES[a["kind"]]
	# Bringing the ball back: keep heading for the child who threw it.
	if a["plan"] == "bring":
		var found := false
		for k in kids:
			if k["id"] == a["thrower"]:
				found = true
				var gap: Vector2 = a["pos"] - k["pos"]
				if gap.length() < BRING_REACH:   # close enough to hand it over, wherever the child stands
					a["goal"] = null
					_arrive(model, a)
					return
				a["goal"] = k["pos"] + (gap.normalized() if gap.length() > 0.01 else Vector2(0, 1)) * 0.9
		if not found:   # the child went inside or left: drop the ball here
			_drop_ball(a)
			_do(a, "idle", 1.0)
		return
	if a["plan"] in ["copy", "tend", "splash_with", "fountain"]:
		_game_think(model, kids, a, dt)
		return
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
	if a["kind"] == "pig" and model.weather == "rain":
		var puddle: Vector2 = TownModel.PUDDLES[rng.randi() % TownModel.PUDDLES.size()]
		return _free_near(model, puddle, r)
	var spots := []
	for item in model.items_in("town"):
		if item["kind"] in def["likes"] and not item.has("gift"):
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


## Whether an animal of radius r can walk the straight line from a to b (the
## ends may touch a child or item it will step around; the middle must be clear).
func _clear_line(model, a: Vector2, b: Vector2, r: float) -> bool:
	var n := int(ceilf(a.distance_to(b) / 0.2))
	for i in range(1, n):
		if not is_clear(model, a.lerp(b, float(i) / n), r):
			return false
	return true


func _game_start(model, a: Dictionary) -> void:
	match GAMES[a["kind"]]:
		"copy":
			a["plan"] = "copy"
			a["game_until"] = time + COPY_SECONDS
			_do(a, "sing", 1.5)
		"tend":
			a["plan"] = "tend"
			_do(a, "garden", 6.0)
		"splash_with":
			a["plan"] = "splash_with"
			_do(a, "splash", 5.0)
		"fountain":
			a["plan"] = "fountain"
			_do(a, "spray", 5.0)
			events.append({"kind": "fountain", "shape": FOUNTAINS[a["option"]], "at": a["pos"], "ry": a["ry"]})


## While an animal plays its game: Wooly answers emotes; the others finish their
## turn and go back to their own routine (no meters, nothing to keep up).
func _game_think(model, kids: Array, a: Dictionary, dt: float) -> void:
	a["timer"] -= dt
	if a["plan"] == "copy":
		for k in kids:
			if a["playmates"].has(k["id"]) and k.get("emote", "") != "" and float(k.get("emote_t", 0.0)) > a["copied_t"]:
				a["copied_t"] = float(k["emote_t"])
				a["game_until"] = time + COPY_SECONDS
				_do(a, COPY.get(k["emote"], "look"), 2.0)
				a["ry"] = _face(a["pos"], k["pos"])
				return
		if a["timer"] <= 0.0:
			a["action"] = "idle"
		if time > a["game_until"] or not kids.any(func(k): return a["playmates"].has(k["id"])):
			_end_game(a)
		return
	if a["timer"] <= 0.0:
		if a["plan"] == "tend" and a["target_id"] != "":
			events.append({"kind": "grow", "id": a["target_id"]})
		_end_game(a)


func _end_game(a: Dictionary) -> void:
	a["plan"] = ""
	a["playmates"] = []
	a["target_id"] = ""
	_do(a, "idle", 1.5)


## The ball lands at the dog's feet; fetch is over.
func _drop_ball(a: Dictionary) -> void:
	a["ball"] = a["pos"] + Vector2(sin(a["ry"]), cos(a["ry"])) * 0.6
	a["thrower"] = 0
	a["plan"] = ""


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
			if a["kind"] == "pig" and model.weather == "rain":
				action = "splash"
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
		"game_go":
			_game_start(model, a)
		"chase":
			a["plan"] = "bring"
			a["goal"] = a["pos"]   # updated toward the thrower on the next think
		"bring":
			_drop_ball(a)
			_do(a, "greet", 2.0)
			a["plan"] = ""
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
			var running: bool = a["plan"] in ["fetch", "chase", "bring"]
			var speed: float = def["speed"] * (1.5 if running else 1.0)
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
			a["action"] = ("carry" if a["plan"] == "bring" else "run") if running else def["move"]
			_check_stuck(model, a, to.length(), dt)
	elif a["action"] in ["walk", "hop", "run", "carry"]:
		a["action"] = "idle"
	var next := resolve(model, p, r)
	# Never squeeze into a gap narrower than the animal: stay put and re-plan instead.
	if not is_clear(model, next, r) and is_clear(model, a["pos"], r):
		next = a["pos"]
	a["pos"] = next
	if a["kind"] == "dog" and a["plan"] == "fetch" and a["goal"] != null:
		a["ball"] = a["goal"]
	if a["plan"] == "bring":
		a["ball"] = a["pos"] + Vector2(sin(a["ry"]), cos(a["ry"])) * 0.35   # in the dog's mouth


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
		if a["plan"] == "game_go" and dist < 3.0:
			_game_start(model, a)   # close enough to the child: play right here
			return
		if a["plan"] == "game_go":
			a["playmates"] = []
		if a["plan"] == "bring":
			_drop_ball(a)
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
