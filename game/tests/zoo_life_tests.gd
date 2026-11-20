## Headless tests for the zoo's ground and water life, zoo r2 (docs/zoo-engineering-standard.md
## section 11.2): Bao the panda, Mabel the elephant, Pebble and Flip the penguins, and the footprint
## avoidance of every ground and water resident. Nothing here renders.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_life_tests.gd
extends SceneTree

const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooBrain := preload("res://scripts/core/zoo_brain.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")

const NEW := ["panda", "elephant", "penguin"]
const SEEDS := [3, 11, 21, 77, 2026]

var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	for t in ["test_data", "test_actions_and_sizes", "test_treats", "test_emote_answers", "test_signatures", "test_toys",
			"test_liveliness", "test_penguin_water", "test_elephant_dry", "test_avoidance_long", "test_avoidance_with_children",
			"test_waypoints", "test_pack_roundtrip", "test_keep_clear"]:
		_current = t
		call(t)
	print("\nZOO LIFE TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func _kid(id: int, pos: Vector2, extra := {}) -> Dictionary:
	var k := {"id": id, "pos": pos, "emote": "", "emote_t": 0.0, "still": 0.0, "speed": 0.0, "run": 0.0, "vel": Vector2.ZERO}
	k.merge(extra, true)
	return k


func _fresh(seed: int, warm := 30) -> ZooBrain:
	var b := ZooBrain.new(seed)
	b.spawn()
	for i in warm:
		b.tick([])
	return b


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _in_kind(p: Vector2, kinds: Array) -> bool:
	for k in ZooMap.AREAS:
		var a: Dictionary = ZooMap.AREAS[k]
		if a["kind"] in kinds and (a["rect"] as Rect2).has_point(p):
			return true
	return false


# ---------------------------------------------------------------- data

func test_data() -> void:
	for sp in NEW:
		ok(ZooLife.LIFE.has(sp), "%s has a life table" % sp)
		var life: Dictionary = ZooLife.LIFE[sp]
		var hab: Rect2 = ZooMap.HABITATS[ZooBrain.HOME_OF[sp]]
		ok(life["routine"].size() >= 5, "%s does five or more things by itself" % sp)
		ok(life["emotes"].size() == 4 and life["emotes"].has("wave") and life["emotes"].has("cheer") and life["emotes"].has("heart") and life["emotes"].has("dance"), "%s answers the four emotes" % sp)
		for o in life["routine"]:
			ok(o[0] in ZooBrain.ACTIONS, "%s: routine action %s is a known action" % [sp, o[0]])
			for t in o[6]:
				ok(t[0] in ZooBrain.ACTIONS, "%s: then-action %s is known" % [sp, t[0]])
			for spot in o[1]:
				if spot == "":
					continue
				ok(ZooMap.SPOTS.has(spot), "%s: spot %s exists" % [sp, spot])
				if not ZooMap.SPOTS.has(spot):
					continue
				var s: Dictionary = ZooMap.SPOTS[spot]
				ok(hab.has_point(s["pos"]), "%s: %s lies in its habitat" % [sp, spot])
				ok(o[0] in s["use"], "%s: %s is a place to %s" % [sp, spot, o[0]])
		for e in life["emotes"]:
			ok(life["emotes"][e][0] in ZooBrain.ACTIONS, "%s: the %s answer is a known action" % [sp, e])
		var t: Array = life["treat"]
		ok(ZooMap.SPOTS.has(t[1]) and "eat" in ZooMap.SPOTS[t[1]]["use"], "%s eats at %s" % [sp, t[1]])
		ok(ZooLife.ANSWERS.has(sp) and ZooLife.ANSWERS[sp].has("treat"), "%s has discoverable answers with a treat" % sp)
	for kind in ZooLife.TOY_ANSWERS:
		for sp in ZooLife.TOY_ANSWERS[kind]:
			ok(ZooLife.TOY_ANSWERS[kind][sp][0] in ZooBrain.ACTIONS, "toy %s / %s answers with a known action" % [kind, sp])
	for key in ["sit_up", "trumpet", "spray", "waddle"]:
		ok(ZooBrain.LINE_KEYS.has(key) and ZooLife.LINES.has(key), "line %s is sent and written" % key)
	for key in ZooBrain.LINE_KEYS:
		ok(ZooLife.LINES.has(key), "line key %s has text" % key)
	# the water spots have a negative height, like the otters'
	for spot in ["penguin_swim_a", "penguin_swim_b"]:
		ok(float(ZooMap.SPOTS[spot]["height"]) < -0.05, "%s is in water" % spot)
	for spot in ["penguin_shore_a", "penguin_shore_b", "elephant_dust", "elephant_waterhole", "panda_bamboo", "panda_lawn"]:
		ok(not _in_kind(ZooMap.SPOTS[spot]["pos"], ["water"]), "%s is dry ground" % spot)


func test_actions_and_sizes() -> void:
	var tail := ["munch", "sit_up", "spray", "dust", "ear_flap", "trumpet", "waddle", "flap", "preen"]
	var n: int = ZooBrain.ACTIONS.size()
	for i in tail.size():
		ok(ZooBrain.ACTIONS[n - tail.size() + i] == tail[i], "action %s is appended in order (index %d)" % [tail[i], n - tail.size() + i])
	ok(ZooBrain.ACTIONS.find("pat") == n - tail.size() - 1, "the old actions did not move")
	ok(ZooBrain.SPECIES["panda"]["radius"] == 0.92 and ZooBrain.SPECIES["elephant"]["radius"] == 1.5 and ZooBrain.SPECIES["penguin"]["radius"] == 0.42, "the footprints are the standard's")
	ok(ZooBrain.SPECIES["panda"]["height"] == 1.27 and ZooBrain.SPECIES["panda"]["length"] == 2.2 and ZooBrain.SPECIES["elephant"]["length"] == 3.45 and ZooBrain.SPECIES["penguin"]["height"] == 1.2 and ZooBrain.SPECIES["penguin"]["length"] == 0.54, "heights and lengths are the standard's")
	ok(ZooBrain.HOME_OF["panda"] == "bamboo_grove" and ZooBrain.HOME_OF["elephant"] == "savanna" and ZooBrain.HOME_OF["penguin"] == "splash_bay", "homes")
	for id in ["bao", "mabel", "pebble", "flip"]:
		ok(ZooMap.ORDER.has(id) and ZooMap.RESIDENTS[id]["species"] in NEW, "%s is a resident" % id)
	ok(ZooMap.ORDER.size() == 18, "eighteen residents")


# ---------------------------------------------------------------- treats

func _ate(b: ZooBrain, id: String, at_spot: String, steps: int) -> bool:
	var seen := false
	for i in steps:
		b.tick([])
		var a: Dictionary = b.animal(id)
		if a["action"] == "eat" and _xz(b.pos_of(a)).distance_to(ZooMap.SPOTS[at_spot]["pos"]) < 0.6:
			seen = true
	return seen


func test_treats() -> void:
	# a direct offer
	for c in [["bao", "panda_treat"], ["mabel", "elephant_treat"], ["pebble", "penguin_shore_b"], ["flip", "penguin_shore_b"]]:
		var b := _fresh(5)
		ok(b.offer_to(c[0], Vector2.ZERO) == "", "%s takes a treat" % c[0])
		ok(_ate(b, c[0], c[1], 400), "%s eats it at %s" % [c[0], c[1]])
	# the tables: the animal with the fewest treats comes, so a round of offers reaches everyone
	var stations := {"grove_treats": ["bao"], "savanna_treats": ["mabel", "topper", "zig", "zag"], "splash_treats": ["pebble", "flip", "bubbles", "skip", "ripple"]}
	for st in stations:
		var b := _fresh(9)
		var who: Array = stations[st]
		var ate := {}
		for n in who.size():
			ok(b.use_station(st, ZooMap.STATIONS[st]["pos"]) == "", "%s is answered (offer %d)" % [st, n + 1])
			for i in 80 if n < who.size() - 1 else 300:   # all offers within a minute: the fewest treats comes
				b.tick([])
				for id in who:
					if b.animal(id)["action"] == ZooLife.LIFE[ZooMap.RESIDENTS[id]["species"]]["treat"][0]:
						ate[id] = true
		for id in who:
			ok(ate.has(id), "%s: %s took it (%s)" % [st, id, ZooLife.LIFE[ZooMap.RESIDENTS[id]["species"]]["treat"][0]])
		# every discovery is reported once per offer
	var b2 := _fresh(5)
	b2.offer_to("mabel", Vector2.ZERO)
	ok(b2.events.any(func(e): return e["kind"] == "found" and e["species"] == "elephant" and e["answer"] == "treat"), "a treat for Mabel is reported for the discovery log")
	# full and happy after three
	var b3 := _fresh(6)
	var full := false
	for n in 4:
		b3.offer_to("bao", Vector2.ZERO)
		full = full or b3.animal("bao")["action"] == "full"
		for i in 30:
			b3.tick([])
	ok(full, "the fourth treat in a minute: Bao is full and happy")
	# the pump: Mabel sprays at the waterhole
	var b4 := _fresh(7)
	ok(b4.use_station("savanna_pump", ZooMap.STATIONS["savanna_pump"]["pos"]) == "", "the pump is answered")
	var sprayed := false
	for i in 400:
		b4.tick([])
		if b4.animal("mabel")["action"] == "spray" and _xz(b4.pos_of(b4.animal("mabel"))).distance_to(ZooMap.SPOTS["elephant_waterhole"]["pos"]) < 0.6:
			sprayed = true
	ok(sprayed, "pumping water: Mabel sprays at the waterhole")


# ---------------------------------------------------------------- answers

func test_emote_answers() -> void:
	var near := {"panda": "bao", "elephant": "mabel", "penguin": "pebble"}
	var n := 0
	for sp in NEW:
		var id: String = near[sp]
		for e in ["wave", "cheer", "heart", "dance"]:
			var b := ZooBrain.new(4)
			b.spawn()
			var a0: Dictionary = b.animal(id)
			var at := _xz(b.pos_of(a0)) + Vector2(0.0, 1.9 if sp != "penguin" else 1.1)
			n += 1
			var want: Array = ZooLife.LIFE[sp]["emotes"][e]
			if sp == "elephant" and e == "cheer":
				want = ["ear_flap", 2.2]   # a cheer in the meadow, not at the gate
			b.tick([_kid(1, at, {"emote": e, "emote_t": float(n)})])
			var a: Dictionary = b.animal(id)
			ok(a["action"] == want[0], "%s answers a %s with %s (got %s)" % [id, e, want[0], a["action"]])
			ok(absf(a["dur"] - want[1]) < 0.01, "%s's %s answer lasts %.1f s" % [id, e, want[1]])
			ok(a["action"] != "idle" and (b.pos_of(a) - a["from"]).length() < 0.01, "%s answers in place" % id)
	# Mabel trumpets back to a cheer at the savanna gate
	var b := ZooBrain.new(4)
	b.spawn()
	b.tick([_kid(1, Vector2(0.0, 11.2), {"emote": "cheer", "emote_t": 1.0})])
	var m: Dictionary = b.animal("mabel")
	ok(m["action"] == "trumpet" and m["line"] == "trumpet", "a cheer at the savanna gate: Mabel trumpets")
	ok(b.events.any(func(e): return e["kind"] == "trumpet" and e["who"] == "mabel"), "a trumpet event is sent for the sound")
	ok(b.events.any(func(e): return e["kind"] == "found" and e["species"] == "elephant" and e["answer"] == "trumpet"), "the trumpet is reported for the discovery log")
	ok(b.animal("zig")["action"] == "buck", "the zebras still buck")
	ok(ZooBrain.LINE_KEYS.has(m["line"]), "and the line travels")


func test_signatures() -> void:
	# Bao: a child standing still at the grove gate
	var b := _fresh(12)
	var sat := false
	var came := false
	var found := false
	for i in 400:
		b.tick([_kid(1, Vector2(27.0, 9.0), {"still": 3.0})])
		var a: Dictionary = b.animal("bao")
		if a["action"] == "sit_up" and a["line"] == "sit_up":
			sat = true
			if _xz(b.pos_of(a)).distance_to(ZooMap.SPOTS["panda_treat"]["pos"]) < 0.8:
				came = true
		for e in b.events:
			if e["kind"] == "found" and e["species"] == "panda" and e["answer"] == "sit_up":
				found = true
		b.events.clear()
	ok(sat, "a still child at the grove gate: Bao sits up")
	ok(came, "and comes to the front of the grove to do it")
	ok(found, "and it is reported for the discovery log")
	# the penguins waddle beside a child running along the beach
	var b2 := _fresh(13)
	var both := 0
	var found2 := false
	var near := 0
	for i in 500:
		var x := -30.0 + 5.0 * sin(i * 0.05)
		var vx := 2.6 * cos(i * 0.05)
		b2.tick([_kid(1, Vector2(x, 7.5), {"speed": 2.6, "run": 7.0, "vel": Vector2(vx, 0.0)})])
		if b2.animal("pebble")["action"] == "waddle" and b2.animal("flip")["action"] == "waddle" and b2.animal("pebble")["follow"] == "waddle":
			both += 1
			var pp: Vector3 = b2.pos_of(b2.animal("pebble"))
			if absf(pp.x - x) < 6.0 and pp.y > -0.05:
				near += 1
		for e in b2.events:
			if e["kind"] == "found" and e["species"] == "penguin" and e["answer"] == "waddle":
				found2 = true
		b2.events.clear()
	ok(both > 20, "a child running along the beach: both penguins waddle with it (%d steps)" % both)
	ok(near > 10, "alongside the child, on land (%d steps)" % near)
	ok(found2, "the waddle is reported for the discovery log")
	var again := false
	for i in 200:
		b2.tick([])
	ok(b2.animal("pebble")["follow"] == "", "when the child stops the penguins go back to their day")


func test_toys() -> void:
	var b := _fresh(8)
	b.toys = [{"kind": "zoo_ball", "pos": Vector2(27.5, 2.0)}, {"kind": "scratching_log", "pos": Vector2(-10.0, 8.0)}, {"kind": "play_mirror", "pos": Vector2(-33.0, 8.0)}]
	var seen := {}
	for i in 3000:
		b.tick([])
		for a in b.animals:
			if a["species"] in NEW and a["action"] in ["play_ball", "dust", "preen", "munch"]:
				for t in b.toys:
					if _xz(b.pos_of(a)).distance_to(t["pos"]) < 1.6:
						seen[a["species"] + ":" + t["kind"]] = true
	ok(seen.has("panda:zoo_ball"), "a ball in the grove: Bao plays with it (%s)" % str(seen.keys()))
	# (the leaf feeder is also the giraffe's and zebras' favourite: whoever is there holds the spot, so Mabel's own toy is the log)
	ok(seen.has("elephant:scratching_log"), "a log in the meadow: Mabel dusts herself at it (%s)" % str(seen.keys()))
	ok(seen.has("penguin:play_mirror"), "a mirror on the beach: the penguins preen at it (%s)" % str(seen.keys()))


# ---------------------------------------------------------------- liveliness and surfaces

func test_liveliness() -> void:
	for seed in [3, 21, 2026]:
		var b := ZooBrain.new(seed)
		b.spawn()
		b.history_on = true
		for i in 1200:
			b.tick([])
		for sp in NEW:
			var seen := {}
			for h in b.history:
				if ZooMap.RESIDENTS[h[1]]["species"] == sp:
					seen[h[2]] = true
			ok(seen.size() >= 4, "seed %d: %s changed action at least 4 times over 120 s (%s)" % [seed, sp, str(seen.keys())])
	# the signature of each species shows within 120 s
	var b2 := ZooBrain.new(21)
	b2.spawn()
	b2.history_on = true
	for i in 1200:
		b2.tick([])
	var acts := {}
	for h in b2.history:
		acts[ZooMap.RESIDENTS[h[1]]["species"] + ":" + h[2]] = true
	for key in ["panda:munch", "elephant:dust", "elephant:ear_flap", "penguin:preen"]:
		ok(acts.has(key), "within 120 s: %s" % key)


func test_penguin_water() -> void:
	for seed in SEEDS:
		var b := ZooBrain.new(seed)
		b.spawn()
		b.history_on = true
		var lowest := 0.0
		var in_water_ok := true
		var bad := ""
		for i in 3000:
			b.tick([])
			for id in ["pebble", "flip"]:
				var a: Dictionary = b.animal(id)
				var p: Vector3 = b.pos_of(a)
				lowest = minf(lowest, p.y)
				if p.y < -0.05 and not a["action"] in ["swim", "dive", "surface", "slide", "idle"]:
					in_water_ok = false
					bad = "%s %s at y %.2f" % [id, a["action"], p.y]
				if a["action"] == "waddle" and (a["from"].y < -0.05 or a["to"].y < -0.05):
					in_water_ok = false
					bad = "%s waddles in water" % id
				if a["action"] == "swim" and a["from"].y > -0.05 and a["to"].y > -0.05:
					in_water_ok = false
					bad = "%s swims on land" % id
				if a["action"] in ["walk", "prowl", "trot", "gallop", "run"]:
					in_water_ok = false
					bad = "%s uses %s" % [id, a["action"]]
		ok(in_water_ok, "seed %d: penguins waddle on land and swim or dive in water (%s)" % [seed, bad])
		ok(lowest < -0.25, "seed %d: the penguins went into the pool (lowest y %.2f)" % [seed, lowest])
		var waddled := false
		var swam := false
		var dived := false
		for h in b.history:
			if h[1] in ["pebble", "flip"]:
				waddled = waddled or h[2] == "waddle"
				swam = swam or h[2] == "swim"
				dived = dived or h[2] == "dive"
		ok(waddled and swam and dived, "seed %d: waddle, swim and dive all happen (%s %s %s)" % [seed, waddled, swam, dived])
	# the path heights: a swim between two water spots is negative all along
	var from: Vector3 = Vector3(-29.0, -0.3, -1.5)
	var to: Vector3 = Vector3(-33.0, -0.3, -0.5)
	for u in [0.0, 0.3, 0.7, 1.0]:
		ok(ZooBrain.path_point("swim", from, to, u).y < -0.25, "swimming at %.1f stays in the water" % u)
	ok(ZooBrain.path_point("waddle", Vector3(-33.5, 0.0, 5.0), Vector3(-25.5, 0.0, 5.1), 0.5).y == 0.0, "waddling stays on the ground")
	ok(ZooBrain.path_point("waddle", Vector3(0, 0, 0), Vector3(2, 0, 0), 0.5).distance_to(Vector3(1, 0, 0)) < 0.01, "a waddle moves steadily")


func test_elephant_dry() -> void:
	for seed in SEEDS:
		var b := ZooBrain.new(seed)
		b.spawn()
		var wet := 0
		var moved := 0.0
		var last := _xz(b.pos_of(b.animal("mabel")))
		for i in 3000:
			b.tick([])
			var p := _xz(b.pos_of(b.animal("mabel")))
			if _in_kind(p, ["water"]):
				wet += 1
			moved += p.distance_to(last)
			last = p
		ok(wet == 0, "seed %d: Mabel never enters the waterhole (%d steps in it)" % [seed, wet])
		ok(moved > 20.0, "seed %d: Mabel does walk (%.0f m)" % [seed, moved])


# ---------------------------------------------------------------- avoidance

const DRY := ["lion", "lioness", "giraffe", "zebra", "elephant", "panda"]


## Checks one run: footprints never overlap by more than 0.1 m, every animal in its habitat and off
## water for the species that stay dry. Returns [overlaps, outside, wet, worst overlap, note].
func _audit(b: ZooBrain, kids_at: Callable, steps: int) -> Array:
	var overlaps := 0
	var outside := 0
	var wet := 0
	var worst := 0.0
	var note := ""
	for i in steps:
		b.tick(kids_at.call(i, b))
		var ps: Array = []
		for a in b.animals:
			if a["species"] == "monkey":
				continue
			var p := _xz(b.pos_of(a))
			ps.append([a, p])
			var hab: Rect2 = ZooMap.HABITATS[ZooBrain.HOME_OF[a["species"]]]
			if not hab.has_point(p):
				outside += 1
				note = "%s outside at %s (%s, %.1f)" % [a["id"], p, a["action"], b.time]
			if a["species"] in DRY and _in_kind(p, ["water"]):
				wet += 1
				note = "%s in water at %s (%s, %.1f)" % [a["id"], p, a["action"], b.time]
		for x in ps.size():
			for y in range(x + 1, ps.size()):
				var ra: float = ZooBrain.SPECIES[ps[x][0]["species"]]["radius"]
				var rb: float = ZooBrain.SPECIES[ps[y][0]["species"]]["radius"]
				var over: float = ra + rb - (ps[x][1] as Vector2).distance_to(ps[y][1])
				if over > 0.1:
					overlaps += 1
					if over > worst:
						worst = over
						note = "%s and %s overlap by %.2f (%s / %s at %.1f)" % [ps[x][0]["id"], ps[y][0]["id"], over, ps[x][0]["action"], ps[y][0]["action"], b.time]
	return [overlaps, outside, wet, worst, note]


func test_avoidance_long() -> void:
	for seed in SEEDS:
		var b := ZooBrain.new(seed)
		b.spawn()
		var r := _audit(b, func(_i, _b): return [], 3000)
		ok(r[0] == 0, "seed %d, 300 s: no two footprints overlap by more than 0.1 m (%d steps; %s)" % [seed, r[0], r[4]])
		ok(r[1] == 0, "seed %d: every animal stays in its habitat (%d; %s)" % [seed, r[1], r[4]])
		ok(r[2] == 0, "seed %d: the animals that stay dry never enter water (%d; %s)" % [seed, r[2], r[4]])


func test_avoidance_with_children() -> void:
	# children wander in every habitat, stand still, run and cheer; nobody is ever inside another
	for seed in [5, 41]:
		var b := ZooBrain.new(seed)
		b.spawn()
		b.toys = [{"kind": "zoo_ball", "pos": Vector2(27.5, 1.0)}, {"kind": "leaf_feeder", "pos": Vector2(2.0, 6.0)}, {"kind": "play_mirror", "pos": Vector2(-33.0, 8.0)}]
		var r := _audit(b, func(i, _b):
			var t := float(i) * 0.1
			return [_kid(1, Vector2(sin(t * 0.07) * 9.0, 9.0 + 2.0 * sin(t * 0.3)), {"speed": 1.2}),
				_kid(2, Vector2(-30.0 + 4.0 * sin(t * 0.11), 7.5), {"speed": 2.6, "run": 7.0, "vel": Vector2(2.6 * cos(t * 0.11), 0.0)}),
				_kid(3, Vector2(27.0, 9.0), {"still": 3.0}),
				_kid(4, Vector2(30.0 + 3.0 * sin(t * 0.2), 3.0 + 2.0 * cos(t * 0.17)), {"speed": 1.0})], 3000)
		ok(r[0] == 0, "seed %d with children: no footprint overlaps by more than 0.1 m (%d steps; %s)" % [seed, r[0], r[4]])
		ok(r[1] == 0, "seed %d with children: every animal stays in its habitat (%d; %s)" % [seed, r[1], r[4]])
		ok(r[2] == 0, "seed %d with children: the dry ones stay dry (%d; %s)" % [seed, r[2], r[4]])
	# rain: the lions' den spots are 1.8 m apart and the lions still fit
	var b2 := ZooBrain.new(5)
	b2.spawn()
	b2.weather = "rain"
	var r2 := _audit(b2, func(_i, _b): return [], 1500)
	ok(r2[0] == 0 and r2[1] == 0, "in the rain: still no overlaps (%s)" % r2[4])


func _park(b: ZooBrain, id: String, at: Vector2) -> void:
	var a: Dictionary = b.animal(id)
	var v := Vector3(at.x, 0.0, at.y)
	a["from"] = v
	a["to"] = v
	a["action"] = "idle"
	a["t0"] = b.time
	a["dur"] = 999.0
	a["plan"] = []


func test_waypoints() -> void:
	# a walk with an animal in the way takes a side-step waypoint (or waits)
	var b := ZooBrain.new(2)
	b.spawn()
	for i in 20:
		b.tick([])
	_park(b, "zag", Vector2(-11.0, 11.0))
	_park(b, "topper", Vector2(-10.0, -4.0))
	_park(b, "mabel", Vector2(2.0, -1.9))
	_park(b, "zig", Vector2(-6.0, -2.5))
	var zig: Dictionary = b.animal("zig")
	var dest := Vector3(9.0, 0.0, -1.0)
	var r: int = b._plan_walk(zig, dest, [["graze", 5.0]], false)
	ok(r == 1, "a zebra walks past the elephant standing on its way (%d)" % r)
	var plan: Array = zig["plan"]
	ok(plan.size() >= 2 and plan[0][0] == "walk_to" and (plan[0][1] as Vector3).distance_to(dest) > 0.5, "by a side-step waypoint (plan %s)" % str(plan))
	var wp: Vector3 = plan[0][1] if not plan.is_empty() else Vector3.ZERO
	var rs: float = ZooBrain.SPECIES["zebra"]["radius"] + ZooBrain.SPECIES["elephant"]["radius"]
	var clear := true
	for pts in [[zig["from"], zig["to"]], [zig["to"], dest]]:
		for k in 21:
			var q: Vector3 = (pts[0] as Vector3).lerp(pts[1], k / 20.0)
			if _xz(q).distance_to(Vector2(2.0, -1.9)) < rs - 0.05:
				clear = false
	ok(clear, "and the walk clears the elephant's footprint (waypoint %s)" % wp)
	ok(ZooMap.HABITATS["savanna"].has_point(_xz(wp)) and not _in_kind(_xz(wp), ["water", "terrace", "thicket", "backdrop"]), "the waypoint is inside the habitat on valid ground")
	# a held destination is skipped: nothing starts, nothing changes
	var b2 := ZooBrain.new(2)
	b2.spawn()
	_park(b2, "mabel", Vector2(9.0, -1.0))
	var z2: Dictionary = b2.animal("zig")
	var plan_before: Array = z2["plan"].duplicate(true)
	ok(b2._spot_taken(z2, Vector3(9.0, 0.0, -1.0), b2._others(z2)), "a spot an elephant stands on is held")
	ok(b2._plan_walk(z2, Vector3(9.0, 0.0, -1.0), [["graze", 5.0]], false) == 0 and z2["plan"] == plan_before, "a walk to a held spot is refused and changes nothing")
	var held := false
	for id in ["zig", "zag", "topper"]:
		held = held or b2._spot_taken(b2.animal(id), _spot3("zebra_graze_c"), b2._others(b2.animal(id)))
	ok(held, "and the others skip that spot too")
	# the elephant goes round the waterhole, never through it
	var b3 := ZooBrain.new(4)
	b3.spawn()
	_park(b3, "topper", Vector2(-10.0, -4.0))
	_park(b3, "zig", Vector2(-6.0, -4.5))
	_park(b3, "zag", Vector2(-11.0, 11.0))
	var m: Dictionary = b3.animal("mabel")
	var r3: int = b3._plan_walk(m, _spot3("elephant_waterhole"), [["spray", 3.0]], false)
	ok(r3 == 1, "Mabel finds a way to the waterhole (%d)" % r3)
	var pts3: Array = [m["from"], m["to"]]
	for st in m["plan"]:
		if st[0] == "walk_to":
			pts3.append(st[1])
	ok(pts3.size() >= 3, "by a detour round the water (%s)" % str(pts3))
	var wet3 := false
	for i in range(pts3.size() - 1):
		for k in 41:
			var q: Vector3 = (pts3[i] as Vector3).lerp(pts3[i + 1], k / 40.0)
			if _in_kind(_xz(q), ["water"]):
				wet3 = true
	ok(not wet3, "no point of it is in the water")
	# a penguin enters the pool at its edge: waddle on land, swim in the water
	var b4 := ZooBrain.new(4)
	b4.spawn()
	var pb: Dictionary = b4.animal("pebble")
	ok(b4._plan_walk(pb, _spot3("penguin_swim_a"), [["swim", 3.0]], false) == 1, "Pebble goes for a swim")
	ok(pb["action"] == "waddle", "first a waddle (%s)" % pb["action"])
	var names: Array = [pb["action"]]
	for st in pb["plan"]:
		if st[0] == "walk_to":
			names.append(b4._move_name(pb, pb["to"], st[1]))
	ok(names.has("swim") and names[0] == "waddle", "then a swim from the edge (%s)" % str(names))


func _spot3(spot: String) -> Vector3:
	var s: Dictionary = ZooMap.SPOTS[spot]
	return Vector3(s["pos"].x, s["height"], s["pos"].y)


# ---------------------------------------------------------------- network and keep clear

func test_pack_roundtrip() -> void:
	for seed in [3, 21]:
		var b := ZooBrain.new(seed)
		b.spawn()
		for i in 900:
			b.tick([])
			if i % 300 == 299:
				var d: Dictionary = ZooBrain.unpack(b.pack())
				ok(d["animals"].size() == 18, "eighteen residents travel")
				ok(absf(d["time"] - b.time) < 0.01, "with the time")
				var bad := 0
				for k in b.animals.size():
					var a: Dictionary = b.animals[k]
					var u: Dictionary = d["animals"][k]
					var same: bool = u["id"] == a["id"] and u["species"] == a["species"] and u["action"] == a["action"] and u["seq"] == a["seq"] \
						and u["from"].distance_to(a["from"]) < 0.001 and u["to"].distance_to(a["to"]) < 0.001 and absf(u["ry"] - a["ry"]) < 0.001 \
						and absf(u["t0"] - a["t0"]) < 0.01 and absf(u["dur"] - a["dur"]) < 0.01 and absf(u["param"] - a["param"]) < 0.001 and u["line"] == a["line"]
					if not same:
						bad += 1
						print("  differs: %s" % a["id"])
				ok(bad == 0, "seed %d, step %d: every resident survives packing exactly (%d differ)" % [seed, i, bad])
	# every new action survives the trip by name
	for act in ["munch", "sit_up", "spray", "dust", "ear_flap", "trumpet", "waddle", "flap", "preen"]:
		var b2 := ZooBrain.new(1)
		b2.spawn()
		b2.animals[14]["action"] = act
		var d2: Dictionary = ZooBrain.unpack(b2.pack())
		ok(d2["animals"][14]["action"] == act, "%s is sent by name" % act)
	for key in ZooBrain.LINE_KEYS:
		var b3 := ZooBrain.new(1)
		b3.spawn()
		b3.animals[15]["line"] = key
		ok(ZooBrain.unpack(b3.pack())["animals"][15]["line"] == key, "line %s is sent by name" % key)


func test_keep_clear() -> void:
	# a child standing on a resting animal of each new species: it steps back, away, and stays inside
	for c in [["bao", Vector2(0.3, 0.0)], ["mabel", Vector2(0.4, 0.2)], ["pebble", Vector2(0.2, -0.1)], ["flip", Vector2(-0.2, 0.2)]]:
		var b := _fresh(4, 5)
		var id: String = c[0]
		# wait for a moment of rest
		for i in 400:
			if b.animal(id)["action"] in ["munch", "dust", "preen", "ear_flap", "nap", "look", "flap", "graze", "sit_up"]:
				break
			b.tick([])
		var p0 := _xz(b.pos_of(b.animal(id)))
		var kid := p0 + (c[1] as Vector2)
		var stepped := false
		var d0 := p0.distance_to(kid)
		var hab: Rect2 = ZooMap.HABITATS[ZooBrain.HOME_OF[b.animal(id)["species"]]]
		var inside := true
		var wet := false
		var far := 0.0
		for i in 400:
			b.tick([_kid(1, kid)])
			var a: Dictionary = b.animal(id)
			stepped = stepped or a["action"] == "step_back"
			var q := _xz(b.pos_of(a))
			far = maxf(far, q.distance_to(kid))
			inside = inside and hab.has_point(q)
			wet = wet or (_in_kind(q, ["water"]) and a["species"] != "penguin")
		var r: float = ZooBrain.SPECIES[b.animal(id)["species"]]["radius"]
		ok(stepped, "%s steps back from a child standing on it" % id)
		ok(far > d0 + 0.8, "%s moved away from the child (%.2f to %.2f)" % [id, d0, far])
		ok(inside and not wet, "%s stayed inside its habitat and out of the water" % id)
		ok(r > 0.0, "%s has a footprint" % id)
