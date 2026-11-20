## The zoo's animals: a pure, seeded simulation (design/zoo-and-world-journeys.md sections 7,
## 10 and 22.4). It runs only on the authority (the solo device, the host or the server) and
## only while a child is in the zoo; clients draw the packed states. It never changes the town.
##
## Every animal is always doing one action with a start time, a duration and two end points.
## Monkeys move only along the routes of ZooMap.LINKS, so a move starts and ends on a valid
## anchor, and an anchor holds one monkey at a time. Choices are weighted by where the monkey
## is and what is near it, with per-monkey cooldowns, no immediate repeat, a troop-wide rule
## against two monkeys starting the same move within three seconds, a limit on how many are
## in a big move at once, and real rests in between. Sequences (the Ring Run, the vine and its
## hop chain, the Spire) run as one action instance.
extends RefCounted

const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")

const STEP := 0.1
## Broadcast action names: the index is sent over the network. New ones go at the end.
const ACTIONS := ["idle", "walk", "run", "climb", "descend", "rings", "leap", "drop", "vine", "hop",
	"balance", "sit_dangle", "tail_hang", "peek", "play_ball", "somersault", "groom", "scratch",
	"look_around", "bask", "patrol", "survey", "yawn", "roar", "nod", "nap", "eat", "catch", "bell",
	"chase", "follow", "pass", "pose", "blink", "roll", "stalk", "pounce", "copy", "groomed",
	"prowl", "swim", "soak", "shake", "stretch", "lick", "chuff", "show_walk", "hide", "peekaboo", "pool_leap",
	"browse", "drink", "bow", "canter", "look", "tongue", "graze", "dust_roll", "swish", "trot", "gallop", "buck",
	"prance", "toss", "float", "twirl", "fountain", "chomp", "surface", "shower", "dive", "slide", "juggle", "beg",
	"belly_eat", "paws", "bob", "full", "step_back", "tyre", "drum", "hug_kick", "push_ball", "sit_on", "scratch_log",
	"faces", "puzzled", "pat",
	# zoo r2 (appended): panda, elephant, penguin
	"munch", "sit_up", "spray", "dust", "ear_flap", "trumpet", "waddle", "flap", "preen"]
## Monkey moves that are "big": they carry the whole body a long way or turn it over.
const BIG := ["climb", "descend", "rings", "leap", "drop", "vine", "hop", "balance", "tail_hang",
	"somersault", "chase", "follow", "catch", "bell"]
## Monkey rests: short, small motions between big moves.
const RESTS := ["look_around", "scratch", "sit_dangle"]
## Per-monkey cooldowns (seconds) of the moves a monkey chooses for itself.
const COOLDOWN := {"climb": 20.0, "descend": 20.0, "rings": 30.0, "leap": 20.0, "vine": 40.0,
	"hop": 20.0, "balance": 35.0, "tail_hang": 45.0, "somersault": 30.0, "peek": 35.0, "play_ball": 40.0,
	"run": 8.0, "drop": 0.0, "chase": 60.0, "follow": 60.0, "pass": 50.0, "groom": 60.0}
const TROOP_GAP := 3.0           # no two monkeys start the same move within this, except shared plays
## Plays two or more monkeys start together on purpose (they are one shared play).
const SHARED := ["copy", "chase", "follow", "pose", "pass", "groom", "groomed"]
const MAX_BIG := 3                # at most this many monkeys in a big move at once
const MAX_BIG_REDUCED := 2
const REST_RANGE := Vector2(2.0, 6.0)
const REST_RANGE_REDUCED := Vector2(3.0, 8.0)
const SOCIAL_EVERY := Vector2(14.0, 26.0)   # seconds between two social plays of the troop
const NEAR_CHILD := 8.0

## Lion actions a lion chooses for itself, with durations and cooldowns.
const LION_COOLDOWN := {"bask": 25.0, "survey": 18.0, "yawn": 30.0, "patrol": 35.0, "nap": 30.0,
	"groom": 25.0, "stalk": 45.0, "peek": 40.0}
const LION_SPEED := 1.1

## Sizes for the rig and the tests (section 6.3 and 22.5).
const SPECIES := {
	"lion": {"name_key": "Lion", "height": 1.55, "length": 2.1, "radius": 0.9},
	"lioness": {"name_key": "Lioness", "height": 1.35, "length": 1.95, "radius": 0.85},
	"tiger": {"name_key": "Tiger", "height": 1.40, "length": 2.2, "radius": 0.9},
	"monkey": {"name_key": "Monkey", "height": 1.10, "length": 0.8, "radius": 0.45},
	"giraffe": {"name_key": "Giraffe", "height": 2.80, "length": 2.0, "radius": 0.9},
	"zebra": {"name_key": "Zebra", "height": 1.65, "length": 1.9, "radius": 0.8},
	"hippo": {"name_key": "Hippo", "height": 1.35, "length": 2.3, "radius": 1.0},
	"otter": {"name_key": "Otter", "height": 1.30, "length": 1.3, "radius": 0.5},
	"panda": {"name_key": "Panda", "height": 1.27, "length": 2.2, "radius": 0.92},   # the GLB scaled 1.15 (ZooAnimal.SPECIES_SCALE)
	"elephant": {"name_key": "Elephant", "height": 2.40, "length": 3.45, "radius": 1.5},
	"penguin": {"name_key": "Penguin", "height": 1.20, "length": 0.54, "radius": 0.42},   # the GLB scaled 1.2 (ZooAnimal.SPECIES_SCALE)
}
const EMOTES := ["wave", "cheer", "dance", "heart"]

var rng := RandomNumberGenerator.new()
## The ground and water animals draw from their own stream, so adding or changing a species never
## shifts the monkeys' seeded behaviour (and the other way round).
var grng := RandomNumberGenerator.new()
var time := 0.0
var animals: Array = []           # [{...}] in ZooMap.ORDER
var reduce_motion := false
var events: Array = []            # one-shot effects for this tick: {"kind", "who", "at"}
var _occupied := {}               # monkey anchor -> animal id (where it is or is going)
var _troop_starts := {}           # action -> time it last started on any monkey
var _next_social := 0.0
var _last_emote := {}             # child id -> time of the emote already answered
var _roared_at := -99.0
var _tyre_level := 0
## For tests: every action instance started, in order: [time, id, action, seq].
var history: Array = []
var history_on := false


func _init(seed := 2026) -> void:
	rng.seed = seed
	grng.seed = int(seed) * 7919 + 104729


## Fresh animals at their homes ("the zoo wakes when the first child arrives").
func spawn() -> void:
	time = 0.0
	animals.clear()
	_occupied.clear()
	_troop_starts.clear()
	_next_social = rng.randf_range(SOCIAL_EVERY.x, SOCIAL_EVERY.y) * 0.5
	for id in ZooMap.ORDER:
		var r: Dictionary = ZooMap.RESIDENTS[id]
		var a := {"id": id, "species": r["species"], "action": "idle", "t0": 0.0, "dur": 0.0,
			"from": Vector3.ZERO, "to": Vector3.ZERO, "ry": PI, "param": 0.0, "cool": {}, "last": "",
			"anchor": "", "plan": [], "seq": false, "partner": "", "follow": "", "line": "", "treats": []}
		if r["species"] == "monkey":
			var p := ZooMap.anchor_pos(r["home"])
			a["anchor"] = r["home"]
			a["from"] = p
			a["to"] = p
			_occupied[r["home"]] = id
			# Staggered first rests: no two start in step.
			_begin(a, "look_around", p, p, rng.randf_range(0.5, 4.0))
		else:
			var s: Dictionary = ZooMap.SPOTS[r["home"]]
			var p := Vector3(s["pos"].x, s["height"], s["pos"].y)
			a["from"] = p
			a["to"] = p
			_begin(a, ZooLife.LIFE[r["species"]]["routine"][0][0], p, p, grng.randf_range(3.0, 6.0))
		animals.append(a)


func animal(id: String) -> Dictionary:
	for a in animals:
		if a["id"] == id:
			return a
	return {}


## Where an animal is now (on its path).
func pos_of(a: Dictionary) -> Vector3:
	return path_point(a["action"], a["from"], a["to"], progress(a), a["param"])


func progress(a: Dictionary) -> float:
	return clampf((time - a["t0"]) / maxf(a["dur"], 0.001), 0.0, 1.0)


## A monkey in a big move, or between two steps of a sequence it is still running (it keeps its turn).
func is_big(a: Dictionary) -> bool:
	return a["species"] == "monkey" and a["action"] in BIG and (time < a["t0"] + a["dur"] or not a["plan"].is_empty())


func big_count() -> int:
	var n := 0
	for a in animals:
		if is_big(a):
			n += 1
	return n


# ---------------------------------------------------------------- the step

## kids: [{"id", "pos": Vector2, "emote": String, "emote_t": float}] for children in the zoo.
func tick(kids: Array, dt := STEP) -> void:
	time += dt
	_answer_emotes(kids)
	for a in animals:
		if time >= a["t0"] + a["dur"]:
			_finish(a)
			if a["species"] == "monkey":
				_monkey_next(a, kids)
			else:
				_ground_next(a, kids)
		elif a["species"] != "monkey" and a["follow"] != "":
			_follow_think(a, kids)
	if time >= _next_social:
		# a play that could not start is tried again soon
		_next_social = time + (rng.randf_range(SOCIAL_EVERY.x, SOCIAL_EVERY.y) if _try_social(kids) else 3.0)
	_keep_troop_alive(kids, dt)


## Ambient life (section 22.4): the troop is never all at rest for long while a child is there.
## After TROOP_QUIET seconds of everyone resting, the monkey that has rested longest ends its rest.
const TROOP_QUIET := 5.0
var _troop_quiet := 0.0


func _keep_troop_alive(kids: Array, dt: float) -> void:
	var resting: Array = []
	for a in animals:
		if a["species"] != "monkey":
			continue
		if not (a["action"] in RESTS or a["action"] == "idle") or not a["plan"].is_empty():
			_troop_quiet = 0.0
			return
		resting.append(a)
	_troop_quiet += dt
	if _troop_quiet < TROOP_QUIET or kids.is_empty() or resting.is_empty():
		return
	resting.sort_custom(func(x, y): return x["t0"] < y["t0"])
	var a: Dictionary = resting[0]
	a["dur"] = maxf(0.1, time - a["t0"])   # its rest ends now; it chooses a move next step
	_troop_quiet = 0.0


func _begin(a: Dictionary, action: String, from: Vector3, to: Vector3, dur: float, param := 0.0, seq := false) -> void:
	a["action"] = action
	a["from"] = from
	a["to"] = to
	a["t0"] = time
	a["dur"] = maxf(dur, 0.1)
	a["param"] = param
	a["seq"] = seq
	if to.distance_to(from) > 0.05:
		a["ry"] = atan2(to.x - from.x, to.z - from.z)
	if a["species"] == "monkey" and not action in RESTS and action != "idle" and not seq:
		_troop_starts[action] = time
	if action == "trumpet":
		events.append({"kind": "trumpet", "who": a["id"], "at": from})
	if history_on:
		history.append([time, a["id"], action, seq])


func _finish(a: Dictionary) -> void:
	if a["species"] == "monkey" and a["action"] in ["run", "climb", "descend", "rings", "leap", "drop", "vine", "hop", "balance", "chase", "follow"]:
		a["from"] = a["to"]


# ---------------------------------------------------------------- monkeys

func _monkey_next(a: Dictionary, kids: Array) -> void:
	var here: String = a["anchor"]
	var p := ZooMap.anchor_pos(here)
	# A plan (a sequence, an answer to a child, a social play) goes on without a rest.
	if not a["plan"].is_empty():
		var step: Array = a["plan"][0]
		if step[0] == "move":
			var to: String = step[1]
			var cap := MAX_BIG_REDUCED if reduce_motion else MAX_BIG
			var next_big: bool = (step[3] if step.size() > 3 else step[2]) in BIG
			if _occupied.get(to, a["id"]) != a["id"] or (next_big and not a["action"] in BIG and big_count() >= cap):
				# A monkey that is only resting there steps aside for one on its way (a child's bell, a
				# banana): a rest never blocks a plan for long (seed 24 waited 18 s at m_nook_b).
				var holder: Dictionary = animal(str(_occupied.get(to, "")))
				if not holder.is_empty() and holder != a and (_free(holder) or _yields(holder)):
					if not _make_way(holder, a["plan"].map(func(st): return st[1] if st[0] == "move" else "")) \
							and not (next_big and not a["action"] in BIG and big_count() >= cap):
						# Nowhere to step aside (a one-monkey path, seed 3 at m_nook_a): the two pass each
						# other, the resting one hopping back to where the other stood.
						var hid: String = holder["id"]
						if _link_move(to, here) in BIG and big_count() >= cap:
							_begin(a, "look_around", p, p, 0.6, 0.0, true)
							return
						_move(holder, here, _link_move(to, here), true)
						a["plan"].pop_front()
						_move(a, to, step[2], true, step[3] if step.size() > 3 else "")
						_occupied[here] = hid
						a["waited"] = 0.0
						return
				elif not holder.is_empty() and holder != a and not holder["plan"].is_empty() \
						and holder["plan"][0][0] == "move" and holder["plan"][0][1] == here:
					# Head-on on a one-monkey path (seed 286): the one not answering a child turns back.
					if str(holder["line"]) == "" or str(a["line"]) != "":
						holder["plan"] = []
					else:
						a["plan"] = []
						_begin(a, _rest_for(here), p, p, 1.0)
						return
				a["waited"] = float(a.get("waited", 0.0)) + 0.6
				if a["waited"] > PLAN_WAIT_MAX:
					a["waited"] = 0.0
					a["plan"] = []   # never stuck: the plan is given up and the monkey goes on with its life
					a["line"] = ""
					_begin(a, _rest_for(here), p, p, 1.0)
					return
				_begin(a, "look_around", p, p, 0.6, 0.0, true)   # wait for the anchor (or a turn) to clear
				return
			a["waited"] = 0.0
			a["plan"].pop_front()
			_move(a, to, step[2], true, step[3] if step.size() > 3 else "")
			return
		a["plan"].pop_front()
		_begin(a, step[1], p, p, step[2], step[3] if step.size() > 3 else 0.0, true)
		if step[1] == "bell":
			events.append({"kind": "bell", "who": a["id"], "at": p})
		return
	a["line"] = ""
	var was_rest: bool = a["action"] in RESTS or a["action"] == "idle"
	if not was_rest:
		var r := REST_RANGE_REDUCED if reduce_motion else REST_RANGE
		_begin(a, _rest_for(here), p, p, rng.randf_range(r.x, r.y))
		return
	# Choose a big move, unless too many are under way.
	if big_count() >= (MAX_BIG_REDUCED if reduce_motion else MAX_BIG):
		_begin(a, _rest_for(here), p, p, 1.0)
		return
	var choice := _choose_monkey_move(a, kids)
	if choice.is_empty():
		_begin(a, _rest_for(here), p, p, 1.0)
		return
	if choice["kind"] == "link":
		_move(a, choice["to"], choice["move"], false)
		_queue_sequence(a)
	else:
		_begin(a, choice["action"], p, p, choice["dur"])
	a["last"] = a["action"]
	a["cool"][a["action"]] = time + float(COOLDOWN.get(a["action"], 20.0))


func _rest_for(anchor: String) -> String:
	var kind: String = ZooMap.ANCHORS[anchor]["kind"]
	if kind in ["perch", "ledge", "rock", "hammock"] and rng.randf() < 0.5:
		return "sit_dangle"
	return "look_around" if rng.randf() < 0.65 else "scratch"


## Starts a move along a route to another anchor; reserves the target.
func _move(a: Dictionary, to: String, move: String, seq: bool, action_name := "") -> void:
	var from: String = a["anchor"]
	_occupied.erase(from)
	_occupied[to] = a["id"]
	a["anchor"] = to
	var fp := ZooMap.anchor_pos(from)
	var tp := ZooMap.anchor_pos(to)
	var name := action_name if action_name != "" else move
	_begin(a, name, fp, tp, move_seconds(move, fp, tp) * (1.25 if name == "follow" else (0.85 if name == "chase" else 1.0)), 0.0, seq)


## A resting monkey moves one link off an anchor another monkey needs: to a free anchor that is not
## on that monkey's way, by an ordinary move (no ring, vine or swing anchor, no big move when another
## exists). Returns whether it moved.
## The anchors still ahead of monkeys answering a child (a bell, a banana): the others do not choose
## them by themselves, so a climber is not kept waiting by a troop-mate going the same way.
func _reserved_for_children(me: Dictionary) -> Dictionary:
	var out := {}
	for m in animals:
		if m == me or m["species"] != "monkey" or str(m["line"]) == "" or m["plan"].is_empty():
			continue
		for st in m["plan"]:
			if st[0] == "move":
				out[st[1]] = true
	return out


## A monkey busy only with something of its own, in place (grooming, scratching, a ball): it can stop
## to make way. Not one moving between anchors (it would jump), nor one with a plan or a line.
func _yields(m: Dictionary) -> bool:
	return m["plan"].is_empty() and str(m["line"]) == "" and (m["from"] as Vector3).distance_to(m["to"]) < 0.01


const PLAN_WAIT_MAX := 8.0   # seconds a planned step waits for its anchor before the plan is dropped


func _make_way(m: Dictionary, avoid: Array) -> bool:
	var best: Array = []
	var reserved := _reserved_for_children(m)
	for l in ZooMap.links_from(m["anchor"]):
		var to: String = l[1]
		if _occupied.has(to) or to in avoid or reserved.has(to) or ZooMap.ANCHORS[to]["kind"] in ["ring", "vine", "swing"]:
			continue
		if best.is_empty() or (best[2] in BIG and not l[2] in BIG):
			best = l
	if best.is_empty():
		return false
	_move(m, best[1], best[2], true)   # an answer to another monkey, not a move of its own choosing
	return true


## After the first step of a sequence, the rest of it.
func _queue_sequence(a: Dictionary) -> void:
	match a["anchor"]:
		"m_ring_s":
			a["plan"] = [["move", "m_ring_n", "rings"], ["move", "m_west_n", "drop"]]
		"m_ring_n":
			a["plan"] = [["move", "m_ring_s", "rings"], ["move", "m_wt_foot", "drop"]]
		"m_vine":
			a["plan"] = [["move", "m_rock_a", "vine"]]
			if rng.randf() < 0.6:
				a["plan"] += [["move", "m_rock_b", "hop"], ["move", "m_rock_c", "hop"], ["move", "m_rocks", "hop"]]
		"m_spire_1":
			a["plan"] = [["move", "m_spire_2", "climb"], ["move", "m_spire_3", "climb"]]


func _choose_monkey_move(a: Dictionary, kids: Array) -> Dictionary:
	var here: String = a["anchor"]
	var kind: String = ZooMap.ANCHORS[here]["kind"]
	var near_child := _near_child(ZooMap.anchor_pos(here), kids, NEAR_CHILD)
	var options: Array = []   # {"kind", "action", "to", "move", "dur", "w"}
	var reserved := _reserved_for_children(a)
	for l in ZooMap.links_from(here):
		var move: String = l[2]
		if _occupied.has(l[1]) or reserved.has(l[1]):
			continue
		var w: float = {"run": 2.0, "climb": 3.0, "descend": 2.0, "leap": 3.0, "hop": 2.5, "balance": 2.5, "drop": 1.0, "rings": 4.0, "vine": 5.0}.get(move, 1.0)
		if near_child and move in ["leap", "rings", "vine", "climb", "balance"]:
			w *= 1.6
		# A child on the lane or in the court draws a monkey onto the rings beside them.
		if move == "leap" and l[1] == "m_ring_s" and _kid_near_rings(kids):
			w *= 2.5
		options.append({"kind": "link", "action": move, "to": l[1], "move": move, "w": w})
	if kind == "ground":
		options.append({"kind": "inplace", "action": "somersault", "dur": 1.1, "w": 1.6 * (1.5 if near_child else 1.0)})
		options.append({"kind": "inplace", "action": "play_ball", "dur": 3.2, "w": 1.4})
		if here in ["m_court_n", "m_wt_foot", "m_et_foot", "m_west_n", "m_rocks"]:
			options.append({"kind": "inplace", "action": "peek", "dur": 2.8, "w": 1.3 * (2.0 if near_child else 1.0)})
	elif kind in ["perch", "hammock", "ledge"]:
		options.append({"kind": "inplace", "action": "tail_hang", "dur": 3.6, "w": 1.6})
		options.append({"kind": "inplace", "action": "play_ball", "dur": 3.2, "w": 1.0})
	elif kind == "rock":
		options.append({"kind": "inplace", "action": "somersault", "dur": 1.1, "w": 0.8})
		options.append({"kind": "inplace", "action": "play_ball", "dur": 3.2, "w": 0.8})
	elif kind == "swing":
		options.append({"kind": "inplace", "action": "tyre", "dur": 3.4, "w": 1.5})
	# Rules: cooldowns, no immediate repeat, the troop-wide gap.
	var allowed: Array = options.filter(func(o): return _may_start(a, o["action"]))
	if allowed.is_empty():
		# Never trapped: cooldowns are preferences, so any move but the last one may run.
		allowed = options.filter(func(o): return o["action"] != a["last"] and time - float(_troop_starts.get(o["action"], -99.0)) >= TROOP_GAP)
	if allowed.is_empty():
		return {}   # waits a moment: the 3 s troop gap passes soon
	var total := 0.0
	for o in allowed:
		total += o["w"]
	var pick := rng.randf() * total
	for o in allowed:
		pick -= o["w"]
		if pick <= 0.0:
			return o
	return allowed[-1]


func _may_start(a: Dictionary, action: String) -> bool:
	if action == a["last"]:
		return false
	if time < float(a["cool"].get(action, -1.0)):
		return false
	return time - float(_troop_starts.get(action, -99.0)) >= TROOP_GAP


static func move_seconds(move: String, from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var rise := absf(to.y - from.y)
	match move:
		"run": return maxf(0.8, flat / 2.6)
		"climb": return 0.6 + rise * 1.1 + flat * 0.3
		"descend": return 0.9 + rise * 0.8 + flat * 0.25
		"rings": return maxf(2.0, flat / 1.6)
		"leap": return 0.9 + flat * 0.12
		"drop": return 0.7
		"vine": return 3.4
		"hop": return 0.6
		"balance": return maxf(2.0, flat / 1.2)
	return 1.0


func _near_child(p: Vector3, kids: Array, r: float) -> bool:
	for k in kids:
		if Vector2(p.x, p.z).distance_to(k["pos"]) < r:
			return true
	return false


func _kid_near_rings(kids: Array) -> bool:
	for k in kids:
		var kp: Vector2 = k["pos"]
		if kp.x > 24.0 and kp.x < 31.0 and kp.y > -23.0 and kp.y < -10.0:
			return true
	return false


## A monkey is free for a plan when it is resting or idle, not in a sequence.
func _free(a: Dictionary) -> bool:
	return a["plan"].is_empty() and (a["action"] in RESTS or a["action"] == "idle" or time >= a["t0"] + a["dur"])


# ---------------------------------------------------------------- social play

func _try_social(kids: Array) -> bool:
	var free: Array = animals.filter(func(x): return x["species"] == "monkey" and _free(x) and ZooMap.ANCHORS[x["anchor"]]["kind"] == "ground")
	if free.size() < 2:
		return false
	var room := (MAX_BIG_REDUCED if reduce_motion else MAX_BIG) - big_count()
	# chase and follow put two monkeys in a big move; a pass and grooming do not
	var kinds := ["chase", "follow", "pass", "groom"].filter(func(k): return time >= float(_troop_starts.get("social_" + k, -999.0)) + float(COOLDOWN[k]) and (k in ["pass", "groom"] or room >= 2))
	if kinds.is_empty():
		return false
	var kind: String = kinds[rng.randi() % kinds.size()]
	var lead: Dictionary = free[rng.randi() % free.size()]
	var others: Array = free.filter(func(x): return x["id"] != lead["id"])
	others.sort_custom(func(x, y): return ZooMap.anchor_pos(x["anchor"]).distance_to(ZooMap.anchor_pos(lead["anchor"])) < ZooMap.anchor_pos(y["anchor"]).distance_to(ZooMap.anchor_pos(lead["anchor"])))
	var mate: Dictionary = others[0]
	match kind:
		"pass":
			var lp := ZooMap.anchor_pos(lead["anchor"])
			var mp := ZooMap.anchor_pos(mate["anchor"])
			if lp.distance_to(mp) > 8.0:
				return false
			_begin(lead, "pass", lp, lp, 3.2, _target_param(mp))
			_begin(mate, "pass", mp, mp, 3.2, _target_param(lp))
			lead["ry"] = atan2(mp.x - lp.x, mp.z - lp.z)
			mate["ry"] = atan2(lp.x - mp.x, lp.z - mp.z)
			lead["partner"] = mate["id"]
			mate["partner"] = lead["id"]
		"groom":
			var pa := route(lead["anchor"], "m_nook_a", true)
			var pb := route(mate["anchor"], "m_nook_b", true)
			if pa.is_empty() or pb.is_empty():
				return false
			if _occupied.get("m_nook_a", lead["id"]) != lead["id"] or _occupied.get("m_nook_b", mate["id"]) != mate["id"]:
				return false
			lead["plan"] = _walk_plan(pa) + [["do", "groom", 7.0]]
			mate["plan"] = _walk_plan(pb) + [["do", "groomed", 7.0]]
			_monkey_next(lead, kids)
			_monkey_next(mate, kids)
		"chase", "follow":
			var path := _ground_tour(lead["anchor"], 3, [])
			if path.size() < 2:
				return false
			var to_lead := route(mate["anchor"], path[0], true)
			if to_lead.size() < 2 or to_lead.size() > 3:
				return false
			var lp: Array = []
			for i in range(1, path.size()):
				lp.append(["move", path[i], "run", kind])
			lead["plan"] = lp + [["do", "somersault" if kind == "chase" else "pose", 1.1]]
			# the mate runs to where the leader started, then the same anchors a beat behind
			var mp: Array = []
			for i in range(1, to_lead.size()):
				mp.append(["move", to_lead[i], "run", kind])
			for i in range(1, path.size() - 1):
				mp.append(["move", path[i], "run", kind])
			mate["plan"] = mp + [["do", "pose" if kind == "chase" else "somersault", 1.1]]
			_monkey_next(lead, kids)
			mate["dur"] = (time - mate["t0"]) + 0.5   # starts half a second later
			mate["action"] = "look_around"
	_troop_starts["social_" + kind] = time
	if history_on:
		history.append([time, lead["id"], "social_" + kind, false])
	return true


static func _target_param(p: Vector3) -> float:
	# packs a ground target into one float: x in metres * 1000 + (z + 500): both within +-500 m
	return roundf(p.x * 10.0) * 10000.0 + roundf((p.z + 500.0) * 10.0)


static func unpack_target(v: float) -> Vector2:
	var xi := roundf(v / 10000.0)
	var zi := v - xi * 10000.0
	return Vector2(xi / 10.0, zi / 10.0 - 500.0)


func _walk_plan(path: Array) -> Array:
	var out: Array = []
	for i in range(1, path.size()):
		out.append(["move", path[i], _link_move(path[i - 1], path[i])])
	return out


static func _link_move(a: String, b: String) -> String:
	for l in ZooMap.LINKS:
		if l[0] == a and l[1] == b:
			return l[2]
	return "run"


## A random ground route of up to n steps from an anchor, avoiding occupied anchors (except `allow`).
func _ground_tour(from: String, n: int, allow: Array) -> Array:
	var path: Array = [from]
	var here := from
	for i in n:
		var nexts: Array = ZooMap.links_from(here).filter(func(l): return l[2] == "run" and not path.has(l[1]) and (not _occupied.has(l[1]) or allow.has(l[1])))
		if nexts.is_empty():
			break
		here = nexts[rng.randi() % nexts.size()][1]
		path.append(here)
	return path


## The shortest route between two anchors (breadth first). ground_only keeps to "run" links.
static func route(from: String, to: String, ground_only := false, blocked := {}) -> Array:
	if from == to:
		return [from]
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var here: String = queue.pop_front()
		for l in ZooMap.links_from(here):
			if ground_only and l[2] != "run":
				continue
			if prev.has(l[1]) or (blocked.has(l[1]) and l[1] != to):
				continue
			prev[l[1]] = here
			if l[1] == to:
				var out: Array = [to]
				var c: String = here
				while c != "":
					out.push_front(c)
					c = prev[c]
				return out
			queue.append(l[1])
	return []


# ---------------------------------------------------------------- answers to children

## Which habitat each species lives in (its answers come from children in or near it).
const HOME_OF := {"lion": "lion_hill", "lioness": "lion_hill", "tiger": "tiger_hill", "monkey": "monkey_hill",
	"giraffe": "savanna", "zebra": "savanna", "hippo": "splash_bay", "otter": "splash_bay",
	"panda": "bamboo_grove", "elephant": "savanna", "penguin": "splash_bay"}
const STILL := 1.5               # seconds a child stands still before the "stand still" answers
const TREATS_FULL := 3           # treats in a minute before "full and happy"


func _answer_emotes(kids: Array) -> void:
	for k in kids:
		var e: String = k.get("emote", "")
		if e == "" or not e in EMOTES:
			continue
		var et: float = k.get("emote_t", 0.0)
		if _last_emote.get(k["id"], -99.0) == et:
			continue
		_last_emote[k["id"]] = et
		var hill := _hill_near(k["pos"])
		if hill == "monkey_hill":
			_monkeys_copy(EMOTES.find(e), k["pos"])
			_found("monkey", "copy", k["pos"])
		elif hill != "":
			_ground_answer(hill, e, k["pos"])


## The habitat a child is in, or beside (within 4 m of its edge), else "".
func _hill_near(p: Vector2) -> String:
	var h := ZooMap.habitat_at(p)
	if h != "":
		return h
	for name in ZooMap.HABITATS:
		if (ZooMap.HABITATS[name] as Rect2).grow(4.0).has_point(p):
			return name
	return ""


## The copycat (section 6.4): every free monkey copies the emote in a ripple.
func _monkeys_copy(emote: int, at: Vector2) -> void:
	var i := 0
	var troop: Array = animals.filter(func(x): return x["species"] == "monkey")
	troop.sort_custom(func(x, y): return Vector2(pos_of(x).x, pos_of(x).z).distance_to(at) < Vector2(pos_of(y).x, pos_of(y).z).distance_to(at))
	for a in troop:
		if not _free(a) or ZooMap.ANCHORS[a["anchor"]]["kind"] in ["ring", "vine", "swing"]:
			continue
		var p := ZooMap.anchor_pos(a["anchor"])
		# A ripple: each one starts a beat after the one before (the copy is meant to match).
		_begin(a, "look_around", p, p, 0.25 * i + 0.05, 0.0, true)
		a["plan"] = [["do", "copy", 1.8, float(emote)]]
		a["ry"] = atan2(at.x - p.x, at.y - p.z)
		a["line"] = "copy"
		i += 1


## A child's emote in a ground or water habitat: its animals answer (section 6.4).
func _ground_answer(hill: String, e: String, at: Vector2) -> void:
	var who: Array = animals.filter(func(x): return x["species"] != "monkey" and HOME_OF[x["species"]] == hill)
	if who.is_empty():
		return
	if hill == "lion_hill" and e == "cheer":
		var rory := animal("rory")
		var honey := animal("honey")
		var roarer: Dictionary = rory if time - _roared_at > 6.0 else honey
		_do_answer(roarer, "roar", 2.6, at, "roar")
		_roared_at = time
		events.append({"kind": "roar", "who": roarer["id"], "at": pos_of(roarer)})
		_found(roarer["species"], "roar", at)
		# Reactions: the other lion chuffs, the zebras next door look up.
		var other: Dictionary = honey if roarer == rory else rory
		if _ground_free(other):
			_do_answer(other, "nod", 1.6, at, "")
		for z in animals.filter(func(x): return x["species"] == "zebra" and _ground_free(x)):
			_do_answer(z, "survey", 2.0, Vector2(pos_of(roarer).x, pos_of(roarer).z), "")
		return
	if hill == "tiger_hill" and e == "cheer":
		_tiger_show_walk()
		return
	if hill == "lion_hill" and e == "dance":
		_do_answer(animal("honey"), "roll", 2.8, at, "")
		_found("lioness", "roll", at)
		return
	if hill == "savanna" and e == "cheer":
		for z in animals.filter(func(x): return x["species"] == "zebra"):
			_do_answer(z, "buck", 1.8, at, "")
		_found("zebra", "buck", at)
		# Mabel trumpets back to a cheer at the gate; elsewhere in the meadow she only flaps her ears.
		var mabel := animal("mabel")
		if _ground_free(mabel):
			if (ZooMap.AREAS["savanna_gate"]["rect"] as Rect2).grow(3.0).has_point(at):
				_do_answer(mabel, "trumpet", 2.6, at, "trumpet")
				_found("elephant", "trumpet", at)
			else:
				_do_answer(mabel, "ear_flap", 2.2, at, "")
		return
	# Otherwise the nearest animal of the habitat answers with its species' move.
	var a := _nearest(who, at)
	var ans: Array = ZooLife.LIFE[a["species"]]["emotes"].get(e, ["nod", 2.0])
	_do_answer(a, ans[0], ans[1], at, "")


func _nearest(list: Array, at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for a in list:
		var p := pos_of(a)
		var d := Vector2(p.x, p.z).distance_to(at)
		if d < bd:
			bd = d
			best = a
	return best


## An answer in place, facing the child; whatever it was doing continues afterwards.
func _do_answer(a: Dictionary, action: String, dur: float, look_at: Vector2, line: String) -> void:
	if a.is_empty():
		return
	var p := pos_of(a)
	_begin(a, action, p, p, dur)
	a["ry"] = atan2(look_at.x - p.x, look_at.y - p.z)
	a["follow"] = ""
	a["plan"] = []
	a["line"] = line
	_settle(a)


## The discovery log (section 10.6): the first time a town sees an answer it is recorded
## (by the autoload, with the names of the children near `at`).
func _found(species: String, answer: String, at: Vector2) -> void:
	events.append({"kind": "found", "species": species, "answer": answer, "at": Vector3(at.x, 0, at.y)})


func _ground_free(a: Dictionary) -> bool:
	return not a.is_empty() and a["plan"].is_empty() and a["follow"] == "" and a["line"] == ""


# ---------------------------------------------------------------- stations

## A station was used by a child (the authority checked the reach). Returns "" or an error key.
func use_station(station: String, by: Vector2) -> String:
	match station:
		"lion_treats", "tiger_treats", "savanna_treats", "splash_treats", "grove_treats":
			return _treat_at(station, by)
		"tiger_ball":
			return "" if _tiger_pool_leap() else "busy"
		"savanna_pump":
			events.append({"kind": "pump", "who": "", "at": Vector3(5.5, 0, 2.5)})
			var any := false
			var spots := ["savanna_drink", "savanna_drink_b", "savanna_drink"]
			var i := 0
			for a in animals.filter(func(x): return x["species"] in ["giraffe", "zebra"]):
				_go_and_do(a, spots[i % spots.size()], "drink", 6.0, "")
				i += 1
				any = true
			if any:
				_found("giraffe", "drink", by)
			var mabel := animal("mabel")
			if not mabel.is_empty() and mabel["follow"] == "":
				_go_and_do(mabel, "elephant_waterhole", "spray", 5.0, "spray")
				_found("elephant", "spray", by)
			return ""
		"splash_shower":
			events.append({"kind": "shower", "who": "", "at": Vector3(-22.4, 0, 6.4)})
			_go_and_do(animal("bubbles"), "hippo_shower", "shower", 6.0, "")
			for o in animals.filter(func(x): return x["species"] == "otter"):
				_otter_slide(o)
			_found("hippo", "shower", by)
			return ""
		"monkey_bananas":
			var m := _nearest_free_monkey(ZooMap.anchor_pos("m_banana"))
			if m.is_empty():
				return "busy"
			var path := route(m["anchor"], "m_banana")
			if path.is_empty() or (_occupied.has("m_banana") and _occupied["m_banana"] != m["id"]):
				return "busy"
			m["plan"] = _walk_plan(path) + [["do", "catch", 1.4], ["do", "eat", 3.4]]
			m["line"] = "eat"
			_monkey_next(m, [])
			events.append({"kind": "banana", "who": m["id"], "at": ZooMap.anchor_pos("m_banana")})
			_found("monkey", "catch", by)
			return ""
		"monkey_bell":
			# A monkey already climbing to the top rings it on arrival (it is on its way; seed 60).
			var spire := ["m_spire_1", "m_spire_2", "m_spire_3"]
			if animals.any(func(m): return m["species"] == "monkey" and str(m["line"]) == "bell" and not m["plan"].is_empty()):
				return ""   # a ring is already on its way up
			for m in animals:
				if m["species"] != "monkey" or str(m["line"]) != "":
					continue
				var tops: Array = m["plan"].map(func(st): return st[0] == "move" and st[1] == "m_spire_3")
				var k := tops.find(true)
				if k >= 0 or (m["anchor"] == "m_spire_3" and not m["plan"].is_empty()):
					m["plan"] = (m["plan"].slice(0, k + 1) if k >= 0 else []) + [["do", "bell", 2.4]]
					m["line"] = "bell"
					for o in animals:   # nobody else heads up the Spire now
						if o != m and o["species"] == "monkey" and str(o["line"]) == "":
							var cut: int = o["plan"].map(func(st): return st[0] == "move" and st[1] in spire).find(true)
							if cut >= 0:
								o["plan"] = o["plan"].slice(0, cut)
					_found("monkey", "bell", by)
					return ""
			# Otherwise the highest monkey on the Spire rings it (after what it is doing now), whatever it
			# was about to do; the others there give up their plans (they are below it, off its way).
			var w: Dictionary = {}
			for l in ["m_spire_3", "m_spire_2", "m_spire_1"]:
				var on: Dictionary = animal(str(_occupied.get(l, "")))
				if on.is_empty():
					continue
				if str(on["line"]) == "bell":
					return ""   # a ring is already on its way up: this child's ring is answered by it
				if w.is_empty():
					w = on
				else:
					on["plan"] = []
			if w.is_empty():
				w = _nearest_free_monkey(ZooMap.anchor_pos("m_court_n"))
			if w.is_empty():
				return "busy"
			var blocked := {}
			for k in _occupied:
				if _occupied[k] != w["id"]:
					blocked[k] = true
			var path := route(w["anchor"], "m_spire_3", false, blocked)
			if path.is_empty():
				path = route(w["anchor"], "m_spire_3")   # none clear now: the usual way, others make way
			if path.is_empty():
				return "busy"
			w["plan"] = _walk_plan(path) + [["do", "bell", 2.4]]
			w["line"] = "bell"
			for o in animals:   # nobody else heads up the Spire now
				if o != w and o["species"] == "monkey" and str(o["line"]) == "":
					var cut2: int = o["plan"].map(func(st): return st[0] == "move" and st[1] in spire).find(true)
					if cut2 >= 0:
						o["plan"] = o["plan"].slice(0, cut2)
			if _free(w):
				_monkey_next(w, [])   # otherwise its plan starts when what it is doing ends
			# The others cheer the climber where they stand.
			for a in animals:
				if a["species"] == "monkey" and a != w and _free(a):
					var p := ZooMap.anchor_pos(a["anchor"])
					_begin(a, "pose", p, p, 1.4, 0.0, true)
			_found("monkey", "bell", by)
			return ""
		"monkey_tyre":
			return _push_tyre(by)
		"monkey_bongos":
			events.append({"kind": "drums", "who": "", "at": Vector3(26.0, 0, -16.0)})
			var n := 0
			for a in animals:
				if a["species"] != "monkey" or not _free(a) or ZooMap.ANCHORS[a["anchor"]]["kind"] in ["ring", "vine", "swing"]:
					continue
				var p := ZooMap.anchor_pos(a["anchor"])
				if n < 2 and ZooMap.ANCHORS[a["anchor"]]["kind"] == "ground":
					_begin(a, "copy", p, p, 8.0, 2.0, true)   # two dance (the dance emote)
				else:
					_begin(a, "drum", p, p, 8.0, 0.0, true)
				a["line"] = "drums"
				n += 1
			_found("monkey", "drums", by)
			return "" if n > 0 else "busy"
	return "unknown"


## Treat tables: the free animal of that habitat with the fewest recent treats comes; three in a
## minute and it is full and happy (section 10.2). Nothing is carried and nothing runs out.
func _treat_at(station: String, by: Vector2) -> String:
	var hill: String = ZooMap.STATIONS[station]["hill"]
	var who: Array = animals.filter(func(x): return x["species"] != "monkey" and HOME_OF[x["species"]] == hill and x["follow"] == "")
	if who.is_empty():
		return "busy"
	who.sort_custom(func(x, y): return _recent_treats(x) < _recent_treats(y) or (_recent_treats(x) == _recent_treats(y) and Vector2(pos_of(x).x, pos_of(x).z).distance_to(by) < Vector2(pos_of(y).x, pos_of(y).z).distance_to(by)))
	return offer_to(who[0]["id"], by)


func _recent_treats(a: Dictionary) -> int:
	return a["treats"].filter(func(t): return time - t < 60.0).size()


## A treat for one animal (a treat table, or the Look strip's "Offer a treat").
func offer_to(id: String, by: Vector2) -> String:
	var a := animal(id)
	if a.is_empty():
		return "unknown"
	if a["species"] == "monkey":
		return use_station("monkey_bananas", by)
	if _recent_treats(a) >= TREATS_FULL:
		_do_answer(a, "full", 2.4, by, "full")
		return ""
	a["treats"].append(time)
	var t: Array = ZooLife.LIFE[a["species"]]["treat"]
	var after: Array = []
	if a["species"] == "otter":
		after = [["belly_eat", 3.0]]
	_go_and_do(a, t[1], t[0], t[2], "eat", after)
	if a["species"] == "hippo":
		events.append({"kind": "splash", "who": id, "at": _spot_v(t[1])})
		for o in animals.filter(func(x): return x["species"] == "otter" and _ground_free(x)):
			_do_answer(o, "bob", 1.6, Vector2(o["to"].x, o["to"].z), "")   # the wave rocks the otters
		_found("hippo", "chomp", by)
	else:
		_found(a["species"], "treat", by)
	return ""


func _spot_v(spot: String) -> Vector3:
	var s: Dictionary = ZooMap.SPOTS[spot]
	return Vector3(s["pos"].x, s["height"], s["pos"].y)


## Walk (or swim) to a spot, then do an action there for `dur`, then the `after` steps. The walk
## goes by the same avoidance as every other (a side-step waypoint, a detour round water); a child's
## treat or a station is answered even when nothing is clear (`force`).
func _go_and_do(a: Dictionary, spot: String, action: String, dur: float, line: String, after: Array = []) -> void:
	if a.is_empty():
		return
	a["follow"] = ""
	a["line"] = line
	var r := _plan_walk(a, _spot_v(spot), [[action, dur]] + after, true)
	if r == 2:
		_ground_next(a, [])


func _move_name(a: Dictionary, from: Vector3, to: Vector3) -> String:
	if a["species"] == "penguin":
		return "swim" if (from.y < -0.05 or to.y < -0.05) else "waddle"
	if from.y < -0.05 and to.y < -0.05:
		return "swim"
	var m: String = ZooLife.LIFE[a["species"]]["move"]
	return "walk" if m == "swim" else m


func _walk_seconds(a: Dictionary, from: Vector3, to: Vector3) -> float:
	var life: Dictionary = ZooLife.LIFE[a["species"]]
	var sp: float = life["speed"]
	if life.has("swim_speed") and (from.y < -0.05 or to.y < -0.05):
		sp = life["swim_speed"]
	return maxf(0.6, from.distance_to(to) / sp)


func _nearest_free_monkey(to: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for a in animals:
		if a["species"] != "monkey" or not a["plan"].is_empty():
			continue
		if ZooMap.ANCHORS[a["anchor"]]["kind"] in ["ring", "vine", "swing"]:
			continue
		var d := ZooMap.anchor_pos(a["anchor"]).distance_to(to)
		if d < bd:
			bd = d
			best = a
	return best


## The tyre swing: a monkey climbs on, each push swings it higher, the third sends it off with a
## turn in the air (section 10.3).
func _push_tyre(by: Vector2) -> String:
	var on: Dictionary = {}
	for a in animals:
		if a["species"] == "monkey" and a["anchor"] == "m_tyre":
			on = a
	if on.is_empty():
		var m := _nearest_free_monkey(ZooMap.anchor_pos("m_tyre"))
		if m.is_empty() or _occupied.has("m_tyre"):
			return "busy"
		var path := route(m["anchor"], "m_tyre")
		if path.is_empty():
			return "busy"
		_tyre_level = 1
		m["plan"] = _walk_plan(path) + [["do", "tyre", 3.0, 1.0]]
		m["line"] = "tyre"
		_monkey_next(m, [])
		_found("monkey", "tyre", by)
		return ""
	_tyre_level = mini(_tyre_level + 1, 3)
	var p := ZooMap.anchor_pos("m_tyre")
	if _tyre_level >= 3:
		on["plan"] = [["move", "m_court_e", "leap"], ["do", "pose", 1.2]]
		_begin(on, "tyre", p, p, 2.6, 3.0, true)
	else:
		on["plan"] = []
		_begin(on, "tyre", p, p, 3.0, float(_tyre_level), true)
	return ""


# ---------------------------------------------------------------- ground and water animals

## What a ground or water animal does next: a plan step, an answer to a child nearby, a toy, or
## its own routine (weighted, with cooldowns and no immediate repeat). A destination another animal
## holds is skipped; if every option is held the animal rests a moment and chooses again.
func _ground_next(a: Dictionary, kids: Array) -> void:
	var p := pos_of(a)
	a["from"] = p
	if not a["plan"].is_empty():
		var step: Array = a["plan"].pop_front()
		match step[0]:
			"patrol_to", "walk_to", "swim_to", "show_walk_to", "leap_to", "slide_to":
				var dest: Vector3 = step[1]
				var name: String = {"patrol_to": "patrol", "walk_to": _move_name(a, p, dest), "swim_to": "swim",
					"show_walk_to": "show_walk", "leap_to": "pool_leap", "slide_to": "slide"}[step[0]]
				var dur: float = step[2] if step.size() > 2 else _walk_seconds(a, p, dest)
				_begin(a, name, p, dest, dur)
				if name == "slide":
					events.append({"kind": "slide", "who": a["id"], "at": dest})
					var hippo := animal("bubbles")
					if _ground_free(hippo):
						_do_answer(hippo, "twirl", 2.4, Vector2(dest.x, dest.z), "")
				if name == "pool_leap":
					events.append({"kind": "splash", "who": a["id"], "at": dest})
			_:
				_begin(a, step[0], p, p, step[1])
		return
	a["line"] = ""
	if _signature(a, kids):
		return
	if _keep_clear(a, kids):
		return
	if _toy_play(a):
		return
	if _den_in_rain(a, p, kids):
		return
	var life: Dictionary = ZooLife.LIFE[a["species"]]
	var options: Array = life["routine"].filter(func(o): return o[0] != a["last"] and time >= float(a["cool"].get(o[0], -1.0)))
	if options.is_empty():
		options = life["routine"].duplicate()
	while not options.is_empty():
		var total := 0.0
		for o in options:
			total += o[2]
		var pick := grng.randf() * total
		var o: Array = options[-1]
		for x in options:
			pick -= x[2]
			if pick <= 0.0:
				o = x
				break
		options.erase(o)
		var r := _try_routine(a, o, p, kids)
		if r == 1:
			return
		if r == 2:
			_ground_next(a, kids)
			return
	_begin(a, "idle", p, p, 1.5)   # every place is held: rest a moment, then choose again


## Starts one routine entry. Returns 0 when it could not (every spot held or no clear way: nothing
## changed), 1 when it began, 2 when its plan is set and the animal is already there.
func _try_routine(a: Dictionary, o: Array, p: Vector3, kids: Array) -> int:
	var dur: float = grng.randf_range(o[3], o[4])
	var spots: Array = o[1]
	var start: int = grng.randi() % spots.size()
	var others := _others(a)
	for k in spots.size():
		var spot: String = spots[(start + k) % spots.size()]
		if spot == "":
			a["last"] = o[0]
			a["cool"][o[0]] = time + float(o[5])
			_begin(a, o[0], p, p, dur)
			return 1
		var dest := _spot_v(spot)
		if _child_at(dest, kids, 1.2) and spots.size() > 1 and k < spots.size() - 1:
			continue
		var extra: Array = []
		var tail: Array = [[o[0], dur]]
		for t in o[6]:
			tail.append(t)
		match o[0]:
			"patrol":
				extra = [_spot_v("lion_ridge_north")]
				tail = [["patrol_to", extra[0]], ["patrol_to", dest], ["survey", 4.0]]
			"show_walk":
				extra = [_spot_v("tiger_log_north")]
				tail = [["show_walk_to", extra[0], 5.0], ["pose", 1.6]]
			"slide":
				extra = [_spot_v("penguin_slide_end" if a["species"] == "penguin" else "otter_slide_end")]
				tail = [["slide_to", extra[0], 1.3], ["surface" if a["species"] == "penguin" else "float", 3.0]]
		if _spot_taken(a, dest, others) or extra.any(func(e): return _spot_taken(a, e, others)):
			continue
		var r := _plan_walk(a, dest, tail, false, others)
		if r != 0:
			a["last"] = o[0]
			a["cool"][o[0]] = time + float(o[5])
			return r
	return 0


## In the rain the lions rest in their den (design 10.7); they still answer children first.
func _den_in_rain(a: Dictionary, p: Vector3, kids: Array) -> bool:
	if weather != "rain" or not DEN_SPOTS.has(a["id"]):
		return false
	var dest: Vector3 = DEN_SPOTS[a["id"]]
	a["last"] = "nap"
	var r := _plan_walk(a, dest, [["nap", grng.randf_range(8.0, 14.0)]], false)
	if r == 0:
		_begin(a, "idle", p, p, 1.5)
	elif r == 2:
		_ground_next(a, kids)
	return true


func _child_at(p: Vector3, kids: Array, r: float) -> bool:
	return _near_child(p, kids, r)


## Never trapped (section 13): a large land animal at rest steps back from a child walking into it,
## away from the child, or 50 or 100 degrees to either side when something is in that way. Never into
## water, and never into another animal's footprint.
func _keep_clear(a: Dictionary, kids: Array) -> bool:
	var p := pos_of(a)
	if p.y < -0.05:
		return false
	var r: float = SPECIES[a["species"]]["radius"] + 0.35
	for k in kids:
		var kp: Vector2 = k["pos"]
		var d := Vector2(p.x, p.z).distance_to(kp)
		if d < r:
			var away := (Vector2(p.x, p.z) - kp).normalized() if d > 0.01 else Vector2(0, -1)
			var rect: Rect2 = ZooMap.HABITATS[HOME_OF[a["species"]]]
			var others := _others(a)
			for turn in [0.0, 50.0, -50.0, 100.0, -100.0]:
				var to2 := Vector2(p.x, p.z) + away.rotated(deg_to_rad(turn)) * 1.4
				to2 = Vector2(clampf(to2.x, rect.position.x + 0.5, rect.end.x - 0.5), clampf(to2.y, rect.position.y + 0.5, rect.end.y - 0.5))
				if _in_water(to2):
					continue
				var dest := Vector3(to2.x, maxf(0.0, ZooMap.surface_height(to2)), to2.y)
				if not _conflict(a, [[p, dest, "step_back", 1.0]], others).is_empty():
					continue
				_begin(a, "step_back", p, dest, 1.0)
				return true
			return false
	return false


## The zoo toy box (section 10.4): an animal whose habitat holds a toy it likes goes to play.
var toys: Array = []              # [{"kind", "pos": Vector2}] in the zoo, from the model, set by the autoload
## The town's weather, set by the autoload (design 10.7: the only zoo behaviour tied to it is the lions'
## den in the rain).
var weather := "sunny"
## Where each lion shelters in the rain: side by side in the den mouth (lion_den terrace).
const DEN_SPOTS := {"rory": Vector3(5.8, 0.0, -25.0), "honey": Vector3(7.6, 0.0, -25.0)}


func _toy_play(a: Dictionary) -> bool:
	if toys.is_empty() or grng.randf() > ZooLife.TOY_CHANCE:
		return false
	var rect: Rect2 = ZooMap.HABITATS[HOME_OF[a["species"]]]
	var liked: Array = toys.filter(func(t): return rect.has_point(t["pos"]) and ZooLife.TOY_ANSWERS.get(t["kind"], {}).has(a["species"]))
	if liked.is_empty():
		return false
	var t: Dictionary = liked[grng.randi() % liked.size()]
	var ans: Array = ZooLife.TOY_ANSWERS[t["kind"]][a["species"]]
	if a["cool"].has("toy_" + t["kind"]) and time < a["cool"]["toy_" + t["kind"]]:
		return false
	a["cool"]["toy_" + t["kind"]] = time + 6.0   # tried again soon if nothing is clear
	var p := pos_of(a)
	var tp: Vector2 = t["pos"]
	var off := (Vector2(p.x, p.z) - tp).normalized() if Vector2(p.x, p.z).distance_to(tp) > 0.01 else Vector2(0, 1)
	var near := tp + off * (0.2 if ans[0] in ["sit_on", "hide", "bask", "nap", "browse"] else 0.9)
	var dest := Vector3(near.x, maxf(0.0, ZooMap.surface_height(near)), near.y)
	if not rect.grow(-0.3).has_point(near):
		return false
	if _in_water(near):
		if not a["species"] in SWIMMERS:
			return false
		if ZooMap.surface_height(near) == 0.0:
			dest.y = WATER_Y.get(a["species"], -0.3)
	var r := _plan_walk(a, dest, [[ans[0], ans[1] if ans[1] > 0.0 else 2.0]], false)
	if r == 0:
		return false
	a["cool"]["toy_" + t["kind"]] = time + 25.0
	if t["kind"] == "zoo_ball" and a["species"] == "otter":
		a["line"] = "fetch"
		_found("otter", "fetch", tp)
	elif t["kind"] == "zoo_ball" and a["species"] == "lion":
		_found("lion", "ball", tp)
	elif t["kind"] == "zoo_ball" and a["species"] == "panda":
		_found("panda", "ball", tp)
	if r == 2:
		_ground_next(a, [])
	a["ry"] = atan2(tp.x - p.x, tp.y - p.z)
	return true


func _in_water(p: Vector2) -> bool:
	for k in ZooMap.AREAS:
		if ZooMap.AREAS[k]["kind"] == "water" and (ZooMap.AREAS[k]["rect"] as Rect2).has_point(p):
			return true
	return false


# ---------------------------------------------------------------- signatures (section 6.4)

## Answers to how a child moves or stands. True when one started.
func _signature(a: Dictionary, kids: Array) -> bool:
	match a["species"]:
		"lion":
			var k := _child_in(kids, "lion_pass", -21.0, -12.5)
			if not k.is_empty() and a["id"] == "rory":
				_start_follow(a, k, "pace")
				_found("lion", "pace", k["pos"])
				return true
		"tiger":
			var k := _still_in(kids, "tiger_thicket_bay")
			if not k.is_empty() and time >= float(a["cool"].get("peekaboo", -1.0)):
				a["cool"]["peekaboo"] = time + 20.0
				_go_and_do(a, "tiger_hide", "peekaboo", 4.0, "peekaboo", [["blink", 2.0]])
				_found("tiger", "peekaboo", k["pos"])
				return true
		"giraffe":
			for k in kids:
				if float(k.get("still", 0.0)) >= STILL and Vector2(pos_of(a).x, pos_of(a).z).distance_to(k["pos"]) < 3.0 and time >= float(a["cool"].get("bow", -1.0)):
					a["cool"]["bow"] = time + 15.0
					_do_answer(a, "bow", 3.5, k["pos"], "bow")
					a["plan"] = [["blink", 2.0]]
					_found("giraffe", "bow", k["pos"])
					return true
		"zebra":
			for k in kids:
				if float(k.get("run", 0.0)) >= 6.0 and ZooMap.habitat_at(k["pos"]) == "savanna" and Vector2(pos_of(a).x, pos_of(a).z).distance_to(k["pos"]) < 12.0:
					_start_follow(a, k, "gallop")
					_found("zebra", "gallop", k["pos"])
					var g := animal("topper")
					if _ground_free(g):
						_do_answer(g, "look", 2.4, k["pos"], "")
					return true
		"hippo":
			var k := _still_in(kids, "splash_jetty")
			if not k.is_empty() and time >= float(a["cool"].get("surface", -1.0)):
				a["cool"]["surface"] = time + 15.0
				_go_and_do(a, "hippo_jetty", "surface", 4.0, "surface")
				_found("hippo", "surface", k["pos"])
				return true
		"otter":
			var k := _child_in(kids, "splash_bank", -4.0, 9.0)
			if not k.is_empty() and float(k.get("speed", 0.0)) > 0.4:
				_start_follow(a, k, "escort")
				_found("otter", "escort", k["pos"])
				return true
		"panda":
			# A child standing still at the gate: Bao comes to the front of the grove and sits up.
			var k := _still_in(kids, "grove_gate")
			if not k.is_empty() and time >= float(a["cool"].get("sit_up_hi", -1.0)):
				a["cool"]["sit_up_hi"] = time + 20.0
				_go_and_do(a, "panda_treat", "sit_up", 4.0, "sit_up", [["blink", 2.0]])
				_found("panda", "sit_up", k["pos"])
				return true
		"penguin":
			# A child running along the beach: the penguins waddle alongside.
			var beach: Rect2 = (ZooMap.AREAS["splash_beach"]["rect"] as Rect2).grow(1.5)
			for k in kids:
				if float(k.get("run", 0.0)) >= 6.0 and beach.has_point(k["pos"]) and Vector2(pos_of(a).x, pos_of(a).z).distance_to(k["pos"]) < 14.0:
					_start_follow(a, k, "waddle")
					_found("penguin", "waddle", k["pos"])
					return true
	return false


func _child_in(kids: Array, area: String, zmin := -999.0, zmax := 999.0) -> Dictionary:
	var r: Rect2 = ZooMap.AREAS[area]["rect"]
	for k in kids:
		var kp: Vector2 = k["pos"]
		if r.has_point(kp) and kp.y > zmin and kp.y < zmax:
			return k
	return {}


func _still_in(kids: Array, area: String) -> Dictionary:
	var r: Rect2 = (ZooMap.AREAS[area]["rect"] as Rect2).grow(0.4)
	for k in kids:
		if r.has_point(k["pos"]) and float(k.get("still", 0.0)) >= STILL:
			return k
	return {}


## Moving alongside a child: Rory paces the Ridge, the zebras gallop beside a running child, the
## otters swim along the bank. Re-aimed while the child keeps going; ends when they stop or leave.
func _start_follow(a: Dictionary, k: Dictionary, kind: String) -> void:
	a["follow"] = kind
	a["follow_t"] = time
	a["plan"] = []
	a["line"] = {"pace": "pace", "gallop": "gallop", "escort": "escort", "waddle": "waddle"}[kind]
	_follow_aim(a, k)


func _follow_aim(a: Dictionary, k: Dictionary) -> void:
	var p := pos_of(a)
	var kp: Vector2 = k["pos"]
	var dest: Vector3
	var speed: float = ZooLife.LIFE[a["species"]]["speed"]
	var action := "patrol"
	match a["follow"]:
		"pace":
			var ridge: Rect2 = ZooMap.AREAS["lion_ridge"]["rect"]
			dest = Vector3(-7.0, 0.9, clampf(kp.y, ridge.position.y + 0.6, ridge.end.y - 0.6))
			speed *= 1.2
		"gallop":
			var vel: Vector2 = k.get("vel", Vector2.ZERO)
			var dir := vel.normalized() if vel.length() > 0.1 else Vector2(1, 0)
			var side := Vector2(-dir.y, dir.x) * (3.0 if a["id"] == "zig" else -3.0)
			var t := kp + dir * 4.0 + side
			var r: Rect2 = (ZooMap.HABITATS["savanna"] as Rect2).grow(-1.0)
			t = Vector2(clampf(t.x, r.position.x, r.end.x), clampf(t.y, r.position.y, r.end.y))
			dest = Vector3(t.x, 0.0, t.y)
			speed = 4.0
			action = "gallop"
		"escort":
			dest = Vector3(-35.2 if a["id"] == "skip" else -34.4, -0.3, clampf(kp.y, -2.6, 3.8))
			speed = 2.2
			action = "swim"
		"waddle":
			var vel2: Vector2 = k.get("vel", Vector2.ZERO)
			var along := signf(vel2.x) if absf(vel2.x) > 0.1 else 1.0
			var x := clampf(kp.x + along * 2.0 + (0.8 if a["id"] == "pebble" else -0.8), -35.0, -24.0)
			dest = Vector3(x, 0.0, 5.2)
			speed = 1.8
			action = "waddle"
	# Never into another animal or into water: round them by the same routes as any walk, else hold a
	# moment and aim again.
	if not a["species"] in SWIMMERS:
		var out := _out_of_water(a, _v2(dest))
		dest = Vector3(out.x, dest.y, out.y)
	# An animal going about its own business in the way stops where it stands (twice at most).
	for attempt in 3:
		var others := _others(a)
		var direct: Array = [[p, dest, action, maxf(0.5, p.distance_to(dest) / speed)]]
		var c := _conflict(a, direct, others)
		for pts in _routes(a, p, dest, c):
			var legs: Array = []
			for i in pts.size() - 1:
				legs.append([pts[i], pts[i + 1], action, maxf(0.5, (pts[i] as Vector3).distance_to(pts[i + 1]) / speed)])
			if _dry_ok(a, legs) and _conflict(a, legs, others).is_empty():
				_begin(a, action, legs[0][0], legs[0][1], legs[0][3])
				return
		var blocker := animal(str(c.get("who", "")))
		if blocker.is_empty() or blocker["follow"] != "" or str(blocker["line"]) != "":
			break
		var bp := pos_of(blocker)
		blocker["plan"] = []
		_begin(blocker, "idle", bp, bp, 1.5)
		_settle(blocker)
	_begin(a, "idle", p, p, 0.4)
	_settle(a)


func _follow_think(a: Dictionary, kids: Array) -> void:
	var k: Dictionary = {}
	match a["follow"]:
		"pace":
			k = _child_in(kids, "lion_pass", -21.0, -12.5)
		"gallop":
			for x in kids:
				if float(x.get("speed", 0.0)) > 2.0 and ZooMap.habitat_at(x["pos"]) == "savanna":
					k = x
			if time - float(a.get("follow_t", time)) > 12.0:
				k = {}
		"escort":
			k = _child_in(kids, "splash_bank", -4.0, 9.0)
		"waddle":
			for x in kids:
				if float(x.get("speed", 0.0)) > 2.0 and (ZooMap.AREAS["splash_beach"]["rect"] as Rect2).grow(1.5).has_point(x["pos"]):
					k = x
			if time - float(a.get("follow_t", time)) > 12.0:
				k = {}
	if k.is_empty():
		var p := pos_of(a)
		var end_action: String = {"pace": "survey", "gallop": "toss", "escort": "float", "waddle": "flap"}[a["follow"]]
		a["follow"] = ""
		a["line"] = ""
		_begin(a, end_action, p, p, {"toss": 2.4, "flap": 2.0}.get(end_action, 3.0))
		_settle(a)
		return
	if progress(a) > 0.5 or a["to"].distance_to(pos_of(a)) < 0.3:
		_follow_aim(a, k)


func _tiger_pool_leap() -> bool:
	var t := animal("tango")
	if t.is_empty() or t["follow"] != "":
		return false
	var ledge := _spot_v("tiger_ledge")
	var splash := Vector3(-31.2, -0.35, -20.2)
	var shore := Vector3(-31.2, -0.35, -18.9)
	var bank := Vector3(-31.2, 0.0, -17.9)
	var p := pos_of(t)
	t["line"] = "pool_leap"
	t["follow"] = ""
	t["plan"] = [["leap_to", splash, 1.3], ["swim_to", shore, 1.6], ["walk_to", bank, 1.0], ["shake", 1.4]]
	_begin(t, "prowl" if p.distance_to(ledge) > 0.3 else "survey", p, ledge, maxf(0.4, p.distance_to(ledge) / 1.6))
	_found("tiger", "pool_leap", Vector2(splash.x, splash.z))
	return true


func _tiger_show_walk() -> void:
	var t := animal("tango")
	if t.is_empty():
		return
	var p := pos_of(t)
	var south := _spot_v("tiger_log_south")
	t["line"] = "show_walk"
	t["follow"] = ""
	t["plan"] = [["show_walk_to", _spot_v("tiger_log_north"), 5.0], ["pose", 1.6]]
	_begin(t, "prowl", p, south, maxf(0.4, p.distance_to(south) / 1.6))
	_found("tiger", "show_walk", Vector2(south.x, south.z))


func _otter_slide(o: Dictionary) -> void:
	o["follow"] = ""
	if _plan_walk(o, _spot_v("otter_slide_top"), [["slide_to", _spot_v("otter_slide_end"), 1.3], ["float", 3.0]], true) == 2:
		_ground_next(o, [])


# ---------------------------------------------------------------- footprints and avoidance
# Standard 11.2. Authoritative, deterministic, no random numbers, no physics bodies. A ground or
# water animal's footprint is a circle of SPECIES.radius. The rule, for every ground and water
# resident (monkeys keep to their anchors):
#  (a) a destination spot is skipped when it lies within the sum of the two radii of another
#      animal's position now, or of where that animal is going (its current target and the end of
#      its plan); when every spot of every option is held, the animal rests 1.5 s and chooses again;
#  (b) a walk is checked in time against every other animal's whole known plan (the segments of its
#      current action and its queued steps, ending where it will stay): sampled every SAMPLE seconds,
#      the two circles must keep the sum of the radii plus CLEAR_MARGIN (the margin is not asked at the
#      two ends of a leg). If the straight walk fails, ONE side-step waypoint is tried: the blocking
#      animal's position at the moment of closest approach, offset perpendicular to the walk by the
#      sum of the radii + 0.3 (then +1.0 and +1.7 when that is still blocked), on either side, nearest
#      first; the first waypoint that gives a clear walk wins; if none does the animal waits and
#      chooses again (or, for a child's treat or station, goes anyway);
#  (c) every waypoint lies inside the habitat (0.4 m in from its edge) and on a valid surface: dry
#      ground and no terrace, thicket or backdrop, unless the species swims (hippo, otter, tiger,
#      penguin), in which case water is valid at the species' water height. Animals that must stay
#      dry never cross a water area: a walk that would is detoured round its corners (one or two
#      waypoints, grown by radius + 0.3). Penguins waddle on land, swim in water, and enter or leave
#      the pool at its edge.

## Species that may use water areas (the others never enter them).
const SWIMMERS := ["hippo", "otter", "tiger", "penguin"]
## The height of a swimmer's body root in water, by species (default -0.3).
const WATER_Y := {"hippo": -0.55, "tiger": -0.35}
const CLEAR_MARGIN := 0.2
const SAMPLE := 0.2
const SIDE_STEPS := [0.3, 1.0, 1.7]
const STEP_NAMES := {"patrol_to": "patrol", "swim_to": "swim", "show_walk_to": "show_walk", "leap_to": "pool_leap", "slide_to": "slide"}


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _radius(a: Dictionary) -> float:
	return float(SPECIES[a["species"]]["radius"])


## One plan step as a leg: [from, to, action name, seconds]. An in-place step is a leg that stays.
func _step_leg(b: Dictionary, at: Vector3, step: Array) -> Array:
	if step.size() > 1 and step[1] is Vector3:
		var dest: Vector3 = step[1]
		var name: String = _move_name(b, at, dest) if step[0] == "walk_to" else STEP_NAMES.get(step[0], "walk")
		var dur: float = step[2] if step.size() > 2 else _walk_seconds(b, at, dest)
		return [at, dest, name, dur]
	return [at, at, "idle", float(step[1])]


## An animal's plan was cut short (a follow ended, an answer began, it stopped for a follower): any other
## animal whose known plan now runs into its footprint stops where it stands. Everyone is clear of
## everyone at this instant, so stopping in place never overlaps.
func _settle(c: Dictionary) -> void:
	var mine := _timeline(c)
	var box := Rect2(_v2(mine[0][2]), Vector2.ZERO)
	for seg in mine:
		box = box.expand(_v2(seg[2])).expand(_v2(seg[3]))
	var rc := _radius(c)
	for o in _others(c):
		var rs: float = rc + o["r"]
		if not box.grow(rs + 0.1).intersects(o["box"]):
			continue
		var tl: Array = o["tl"]
		var end := time
		for seg in tl:
			if seg[1] != INF:
				end = maxf(end, seg[1])
		for seg in mine:
			if seg[1] != INF:
				end = maxf(end, seg[1])
		var clash := false
		var t := time
		while t <= end + SAMPLE and not clash:
			clash = _tl_pos(tl, t).distance_to(_tl_pos(mine, t)) < rs
			t += SAMPLE
		if clash:
			var b := animal(str(o["id"]))
			if b["plan"].is_empty() and b["to"].distance_to(b["from"]) < 0.01:
				continue   # it is not going anywhere; the other one's own check kept clear of it
			var pb := pos_of(b)
			b["plan"] = []
			_begin(b, "idle", pb, pb, 1.0)


## Where an animal will be: [[t0, t1, from, to, action]...] from its current action through its queued
## plan, then staying put (t1 = INF).
func _timeline(b: Dictionary) -> Array:
	var tl: Array = []
	var t1: float = b["t0"] + b["dur"]
	tl.append([b["t0"], t1, b["from"], b["to"], b["action"]])
	var at: Vector3 = b["to"]
	var t := t1
	for step in b["plan"]:
		var l: Array = _step_leg(b, at, step)
		tl.append([t, t + l[3], l[0], l[1], l[2]])
		t += l[3]
		at = l[1]
	tl.append([t, INF, at, at, "idle"])
	return tl


func _seg_pos(seg: Array, s: float) -> Vector2:
	var d: float = seg[1] - seg[0]
	if d <= 0.0 or seg[1] == INF:
		return _v2(seg[3])
	return _v2(path_point(seg[4], seg[2], seg[3], clampf((s - seg[0]) / d, 0.0, 1.0)))


func _tl_pos(tl: Array, s: float) -> Vector2:
	for seg in tl:
		if s < seg[1]:
			return _seg_pos(seg, s)
	return _v2(tl[-1][3])


## The other ground and water animals: [{"r", "tl", "box"}].
func _others(a: Dictionary) -> Array:
	var out: Array = []
	for b in animals:
		if b == a or b["species"] == "monkey":
			continue
		var tl := _timeline(b)
		var box := Rect2(_v2(tl[0][2]), Vector2.ZERO)
		for seg in tl:
			box = box.expand(_v2(seg[2])).expand(_v2(seg[3]))
		out.append({"id": b["id"], "r": _radius(b), "tl": tl, "box": box})
	return out


## Is a destination held: within the two radii of another animal's position now, of the end of its
## current action, or of where its plan leaves it?
func _spot_taken(a: Dictionary, dest: Vector3, others: Array) -> bool:
	var d := _v2(dest)
	for o in others:
		var rs: float = _radius(a) + o["r"]
		var tl: Array = o["tl"]
		if d.distance_to(_tl_pos(tl, time)) < rs or d.distance_to(_v2(tl[0][3])) < rs or d.distance_to(_v2(tl[-1][3])) < rs:
			return true
	return false


static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


## The first place a chain of legs comes within the footprints of another animal: {} when clear, else
## {"at": the other's position then, "rs": the two radii}.
func _conflict(a: Dictionary, legs: Array, others: Array) -> Dictionary:
	if legs.is_empty():
		return {}
	var ra := _radius(a)
	var box := Rect2(_v2(legs[0][0]), Vector2.ZERO)
	var total := 0.0
	for l in legs:
		box = box.expand(_v2(l[0])).expand(_v2(l[1]))
		total += l[3]
	var s_end := time + total
	var last: Vector2 = _v2(legs[-1][1])
	for o in others:
		var rs: float = ra + o["r"]
		var tl: Array = o["tl"]
		if not box.grow(rs + CLEAR_MARGIN + 0.1).intersects(o["box"]):
			continue
		var t := time
		# a pair already closer than the margin only has to not come closer
		var d0 := _v2(legs[0][0]).distance_to(_tl_pos(tl, time))
		for l in legs:
			var n := maxi(1, int(ceil(l[3] / SAMPLE)))
			var moving: bool = l[2] != "idle"
			for i in n + 1:
				var u := float(i) / float(n)
				var mine := _v2(path_point(l[2], l[0], l[1], u))
				var theirs := _tl_pos(tl, t + l[3] * u)
				var d := mine.distance_to(theirs)
				if d < rs or (moving and i > 0 and i < n and d < rs + CLEAR_MARGIN and d < d0 - 0.01):
					return {"at": theirs, "rs": rs, "who": o["id"]}
			t += l[3]
		# after the chain I stay on its last point; the other must not come to it
		for seg in tl:
			if seg[1] > s_end:
				var q0 := _seg_pos(seg, maxf(seg[0], s_end))
				var q1 := _v2(seg[3])
				if _dist_seg(last, q0, q1) < rs:
					return {"at": q1, "rs": rs, "who": o["id"]}
	return {}


## The water areas of the animal's habitat.
func _water_rects(a: Dictionary) -> Array:
	var out: Array = []
	var hab: Rect2 = ZooMap.HABITATS[HOME_OF[a["species"]]]
	for k in ZooMap.AREAS:
		var ar: Dictionary = ZooMap.AREAS[k]
		if ar["kind"] == "water" and hab.intersects(ar["rect"]):
			out.append(ar["rect"])
	return out


static func _seg_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(d[axis]) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return false
		else:
			var ta: float = (lo - a[axis]) / d[axis]
			var tb: float = (hi - a[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


## Animals that stay dry never cross water: land to land for a penguin, any leg for the others.
func _dry_ok(a: Dictionary, legs: Array) -> bool:
	var sp: String = a["species"]
	if sp in SWIMMERS and sp != "penguin":
		return true
	var rects := _water_rects(a)
	for l in legs:
		var from: Vector3 = l[0]
		var to: Vector3 = l[1]
		if sp == "penguin" and (from.y < -0.05 or to.y < -0.05):
			continue
		for r in rects:
			if _seg_hits(_v2(from), _v2(to), (r as Rect2).grow(-0.02 if sp == "penguin" else 0.3)):
				return false
	return true


## A point moved to the nearest edge of the water area it lies in (for animals that stay dry).
func _out_of_water(a: Dictionary, p: Vector2) -> Vector2:
	for r in _water_rects(a):
		var g: Rect2 = (r as Rect2).grow(0.5)
		if g.has_point(p):
			var opts: Array = [Vector2(g.position.x, p.y), Vector2(g.end.x, p.y), Vector2(p.x, g.position.y), Vector2(p.x, g.end.y)]
			opts.sort_custom(func(x, y): return x.distance_to(p) < y.distance_to(p))
			return opts[0]
	return p


## A point an animal may stop at on the way: inside the habitat, dry (unless it swims there), and not on
## a terrace, thicket or backdrop.
func _valid_point(a: Dictionary, p: Vector2) -> bool:
	var hab: Rect2 = ZooMap.HABITATS[HOME_OF[a["species"]]]
	if not hab.grow(-0.4).has_point(p):
		return false
	for k in ZooMap.AREAS:
		var ar: Dictionary = ZooMap.AREAS[k]
		if (ar["rect"] as Rect2).has_point(p):
			if ar["kind"] == "water" and not a["species"] in SWIMMERS:
				return false
			if ar["kind"] in ["terrace", "backdrop", "thicket"]:
				return false
	return true


func _point_v(a: Dictionary, p: Vector2) -> Vector3:
	return Vector3(p.x, WATER_Y.get(a["species"], -0.3) if _in_water(p) else 0.0, p.y)


## A chain of points as legs (a penguin's walk splits where it enters or leaves the water).
func _make_legs(a: Dictionary, pts: Array) -> Array:
	var legs: Array = []
	for i in pts.size() - 1:
		var from: Vector3 = pts[i]
		var to: Vector3 = pts[i + 1]
		var parts: Array = [[from, to]]
		if a["species"] == "penguin" and (from.y < -0.05) != (to.y < -0.05):
			var wf := from.y < -0.05
			var lo := 0.0
			var hi := 1.0
			for it in 14:
				var mid := (lo + hi) * 0.5
				if _in_water(_v2(from.lerp(to, mid))) == wf:
					lo = mid
				else:
					hi = mid
			var e1 := from.lerp(to, lo)
			var e2 := from.lerp(to, hi)
			e1.y = -0.3 if wf else 0.0
			e2.y = 0.0 if wf else -0.3
			parts = [[from, e1], [e1, e2], [e2, to]]
		for seg in parts:
			legs.append([seg[0], seg[1], _move_name(a, seg[0], seg[1]), _walk_seconds(a, seg[0], seg[1])])
	return legs


func _tail_legs(a: Dictionary, at: Vector3, tail: Array) -> Array:
	var legs: Array = []
	var cur := at
	for step in tail:
		var l: Array = _step_leg(a, cur, step)
		legs.append(l)
		cur = l[1]
	return legs


## Candidate routes from p to dest, nearest first: the straight walk, then one or two waypoints round
## water, then one side-step waypoint beside the animal in the way.
func _routes(a: Dictionary, p: Vector3, dest: Vector3, conflict: Dictionary) -> Array:
	var cands: Array = []   # [length, [points]]
	var ra := _radius(a)
	var p2 := _v2(p)
	var d2 := _v2(dest)
	if not (a["species"] in SWIMMERS and a["species"] != "penguin"):
		for r in _water_rects(a):
			var g: Rect2 = (r as Rect2).grow(ra + 0.3)
			var cs: Array = [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]
			for i in 4:
				var c1: Vector2 = cs[i]
				var c2: Vector2 = cs[(i + 1) % 4]
				if _valid_point(a, c1):
					cands.append([p2.distance_to(c1) + c1.distance_to(d2), [_point_v(a, c1)]])
				if _valid_point(a, c1) and _valid_point(a, c2):
					cands.append([p2.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(d2), [_point_v(a, c1), _point_v(a, c2)]])
					cands.append([p2.distance_to(c2) + c2.distance_to(c1) + c1.distance_to(d2), [_point_v(a, c2), _point_v(a, c1)]])
	if not conflict.is_empty() and p2.distance_to(d2) > 0.01:
		var dir := (d2 - p2).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var at: Vector2 = conflict["at"]
		for off in SIDE_STEPS:
			for side in [1.0, -1.0]:
				var w: Vector2 = at + perp * side * (float(conflict["rs"]) + off)
				if _valid_point(a, w):
					cands.append([p2.distance_to(w) + w.distance_to(d2), [_point_v(a, w)]])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array = [[p, dest]]
	for c in cands:
		var chain: Array = [p]
		chain.append_array(c[1])
		chain.append(dest)
		out.append(chain)
	return out


## Plans a walk to `dest` followed by the steps `tail`, by the avoidance rule, and starts it.
## Returns 0 when nothing is clear (nothing changed), 1 when the first leg began, 2 when the animal is
## already there (its plan is `tail`; the caller starts it with _ground_next). `force` goes anyway.
func _plan_walk(a: Dictionary, dest: Vector3, tail: Array, force := false, others_in: Array = []) -> int:
	var p := pos_of(a)
	var others: Array = others_in if not others_in.is_empty() else _others(a)
	if p.distance_to(dest) <= 0.3:
		if not force and not _conflict(a, _tail_legs(a, p, tail), others).is_empty():
			return 0
		a["plan"] = tail.duplicate(true)
		return 2
	var routes := _routes(a, p, dest, _conflict(a, _make_legs(a, [p, dest]) + _tail_legs(a, dest, tail), others))
	var best: Array = []
	var fallback: Array = []
	for pts in routes:
		var legs := _make_legs(a, pts)
		if not _dry_ok(a, legs):
			continue
		if fallback.is_empty():
			fallback = legs
		if _conflict(a, legs + _tail_legs(a, dest, tail), others).is_empty():
			best = legs
			break
	if best.is_empty():
		if not force:
			return 0
		best = fallback if not fallback.is_empty() else _make_legs(a, [p, dest])
	var plan: Array = []
	for i in range(1, best.size()):
		plan.append(["walk_to", best[i][1], best[i][3]])
	plan.append_array(tail.duplicate(true))
	a["plan"] = plan
	_begin(a, best[0][2], best[0][0], best[0][1], best[0][3])
	return 1


# ---------------------------------------------------------------- paths (shared with drawing)

## Where an animal is along its action at progress u. Same function on every device, so the
## same state draws the same motion everywhere.
static func path_point(action: String, from: Vector3, to: Vector3, u: float, _param := 0.0) -> Vector3:
	var k := clampf(u, 0.0, 1.0)
	match action:
		"walk", "run", "patrol", "chase", "follow", "prowl", "trot", "swim", "gallop", "show_walk", "step_back", "waddle":
			var s := k * k * (3.0 - 2.0 * k) if action in ["patrol", "walk", "step_back", "show_walk"] else k
			return from.lerp(to, s)
		"slide":
			return from.lerp(to, k * k)
		"pool_leap":
			return _arc(from, to, 0.7, k)
		"balance":
			return from.lerp(to, k)
		"rings":
			return from.lerp(to, k)
		"climb":
			# across to the pole first, then straight up
			var mid := Vector3(lerpf(from.x, to.x, 0.8), from.y, lerpf(from.z, to.z, 0.8))
			if k < 0.25:
				return from.lerp(mid, k / 0.25)
			var c := (k - 0.25) / 0.75
			return Vector3(lerpf(mid.x, to.x, c), lerpf(from.y, to.y, c), lerpf(mid.z, to.z, c))
		"descend":
			var mid := Vector3(lerpf(from.x, to.x, 0.2), to.y, lerpf(from.z, to.z, 0.2))
			if k < 0.7:
				var c := k / 0.7
				return Vector3(lerpf(from.x, mid.x, c), lerpf(from.y, mid.y, c), lerpf(from.z, mid.z, c))
			return mid.lerp(to, (k - 0.7) / 0.3)
		"leap":
			return _arc(from, to, 0.8, k)
		"hop":
			return _arc(from, to, 0.45, k)
		"drop":
			return _arc(from, to, 0.1, k)
		"vine":
			# 0..0.75: on the vine (the grip swings under the anchor); then the flight to the rock
			# the body hangs along the rope: feet are VINE_LENGTH + HANG from the pivot
			var reach := ZooMap.VINE_LENGTH + ZooMap.HANG
			var pivot := from + Vector3(0, reach, 0)
			var swing_end := 0.75
			if k < swing_end:
				var ang := vine_angle(k / swing_end)
				return pivot + Vector3(0, -reach * cos(ang), -reach * sin(ang))
			var rel := pivot + Vector3(0, -reach * cos(ZooMap.VINE_ARC), -reach * sin(ZooMap.VINE_ARC))
			return _arc(rel, to, 0.5, (k - swing_end) / (1.0 - swing_end))
	return to if k >= 1.0 else from.lerp(to, k)


## The vine's angle over its swing (0..1): two growing swings, released at the far peak.
## It starts hanging straight down (angle 0) and ends at the far peak (VINE_ARC, toward -z).
static func vine_angle(s: float) -> float:
	var amp := ZooMap.VINE_ARC * (0.55 + 0.45 * s)
	return amp * sin(TAU * 1.25 * clampf(s, 0.0, 1.0))


static func _arc(from: Vector3, to: Vector3, lift: float, k: float) -> Vector3:
	var p := from.lerp(to, k)
	var top := maxf(from.y, to.y) + lift
	p.y = lerpf(from.y, to.y, k) + (top - lerpf(from.y, to.y, 0.5)) * 4.0 * k * (1.0 - k)
	return p


# ---------------------------------------------------------------- network

const FIELDS := 14
## The line shown over an animal busy with a child, by index (0 = none): ZooLife.LINES' keys.
const LINE_KEYS := ["roar", "pace", "eat", "peekaboo", "pool_leap", "copy", "bell", "bow", "gallop", "surface",
	"escort", "full", "rings", "drums", "tyre", "fetch", "show_walk", "sit_up", "trumpet", "spray", "waddle"]


## [time, then per animal: from x y z, to x y z, ry, action, t0, dur, param, seq, spare, spare]
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array([time])
	for a in animals:
		out.append_array([a["from"].x, a["from"].y, a["from"].z, a["to"].x, a["to"].y, a["to"].z, a["ry"],
			float(ACTIONS.find(a["action"])), a["t0"], a["dur"], a["param"], 1.0 if a["seq"] else 0.0,
			float(LINE_KEYS.find(a["line"]) + 1), 0.0])
	return out


## The states for drawing: {"time", "animals": [{"id", "species", "action", "from", "to", "ry", "t0", "dur", "param"}]}.
static func unpack(data: PackedFloat32Array) -> Dictionary:
	var out := {"time": 0.0, "animals": []}
	if data.size() < 1 or (data.size() - 1) % FIELDS != 0 or (data.size() - 1) / FIELDS != ZooMap.ORDER.size():
		return out
	out["time"] = data[0]
	for i in ZooMap.ORDER.size():
		var o := 1 + i * FIELDS
		var act := int(data[o + 7])
		var id: String = ZooMap.ORDER[i]
		out["animals"].append({"id": id, "species": ZooMap.RESIDENTS[id]["species"],
			"from": Vector3(data[o], data[o + 1], data[o + 2]), "to": Vector3(data[o + 3], data[o + 4], data[o + 5]),
			"ry": data[o + 6], "action": ACTIONS[act] if act >= 0 and act < ACTIONS.size() else "idle",
			"t0": data[o + 8], "dur": data[o + 9], "param": data[o + 10], "seq": data[o + 11] > 0.5,
			"line": LINE_KEYS[int(data[o + 12]) - 1] if int(data[o + 12]) >= 1 and int(data[o + 12]) <= LINE_KEYS.size() else ""})
	return out
