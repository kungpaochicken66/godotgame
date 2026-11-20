## Headless tests for the city's people (design/city-district.md "City r2"): the counts per place against
## CityMap.PEOPLE_BUDGET; every person on an A1 NPC place (or clear standing room), inside its region, clear of
## every child's place and of solid furniture; the looks (regenerated from their seeds), their variety and no
## look-alike neighbours; nobody in sync; walkers on CityRules' lanes swinging each arm against the leg on its
## side; the Ferris passengers never in a child's gondola and boarding or leaving only at the bottom (a
## simulated authority with children boarding, riding and dropping out); the carousel riders on their horses;
## determinism and Pause; the cutaway hiding; the draw-call, triangle and per-frame transform budgets.
## Nothing renders.
##   scripts/godot.sh --headless --path game -s res://tests/city_people_tests.gd
extends SceneTree

const CityMap := preload("res://scripts/core/city_map.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")
const Data := preload("res://scripts/core/city_people_data.gd")
const People := preload("res://scripts/art/city_people.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")

const MAX_CALLS := 16
const MAX_TRIS := 45000
const MAX_WRITES := 700
## The gondola's clear height inside (floor to the underside of its roof).
const CABIN_CLEAR := 0.915

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var cw: CityWorld
var pp: People


func _initialize() -> void:
	cw = CityWorld.new()
	root.add_child(cw)
	cw.build()
	pp = People.new()
	cw.add_child(pp)
	pp.time_override = 20.0
	pp.riders_override = {}
	pp.weather_override = {"weather": 0, "since": -4.0, "prev": Vector3(1, 0, 0)}
	pp.setup(cw)
	for t: String in ["test_counts", "test_actions", "test_places", "test_solids", "test_looks", "test_variety", "test_no_sync",
			"test_walkers", "test_geometry", "test_ferris", "test_carousel", "test_determinism", "test_hidden", "test_budgets",
			"test_no_randomness", "test_rain_who", "test_spots_and_paths", "test_rain_cover", "test_weather_cycle",
			"test_posture"]:
		_current = t
		call(t)
	for line: String in _report:
		print(line)
	print("\nCITY PEOPLE TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


# ------------------------------------------------------------------ helpers

static func _norm(region: String) -> String:
	return "" if region == "ground" else region


func _furniture() -> Array:
	var all: Array = []
	all.append_array(CityMap.FURNITURE)
	if "EXTRA_FURNITURE" in PropsCity:
		all.append_array(PropsCity.EXTRA_FURNITURE)
	return all


func _static_people() -> Array:
	var out: Array = []
	for p: Variant in pp.people:
		if p.kind == People.K_STATIC:
			out.append(p)
	return out


func _kind(k: int) -> Array:
	var out: Array = []
	for p: Variant in pp.people:
		if p.kind == k:
			out.append(p)
	return out


## The world position of a part's centre.
func _at(p: Variant, part: int) -> Vector3:
	return pp.part_transform(p, part).origin


func _is_zero(xf: Transform3D) -> bool:
	return xf.basis.get_scale().length() < 1e-4


## Inside a region (a body of radius r stays on it): ground between the walls, upper floors inside the rect and
## out of the stair wells.
func _inside(region: String, pos: Vector2, r: float) -> bool:
	if region == "ground":
		if not CityMap.OUTER_PAVEMENT.has_point(pos):
			return false
		for w: Rect2 in CityMap.GROUND_WALLS:
			if w.grow(r * 0.5).has_point(pos):
				return false
		return true
	var reg: Dictionary = CityMap.REGIONS[region]
	if not (reg["rect"] as Rect2).grow(-r).has_point(pos):
		return false
	for h: Rect2 in reg["holes"]:
		if h.grow(r).has_point(pos):
			return false
	return true


func _rect_dist(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


func _role_of(e: Dictionary) -> String:
	return String(e["role"])


func _all_looks() -> Array:
	var out: Array = []
	for e: Dictionary in Data.PEOPLE:
		out.append([e["look"], int(e["seed"]), _role_of(e), String(e["id"])])
	for i in Data.WALKER_LOOKS.size():
		var w: Dictionary = Data.WALKER_LOOKS[i]
		out.append([w["look"], int(w["seed"]), "walker", "walker_%d" % i])
	for sl: Dictionary in Data.FERRIS_SLOTS:
		for l: Dictionary in sl["looks"]:
			out.append([l["look"], int(l["seed"]), "rider", "ferris_%d" % int(sl["slot"])])
	for c: Dictionary in Data.CAROUSEL_RIDERS:
		out.append([c["look"], int(c["seed"]), String(c["role"]), String(c["id"])])
	return out


func _triple(l: Dictionary) -> String:
	return "%s/%s/%s" % [l["hair_style"], (l["hair_color"] as Color).to_html(false), (l["top_color"] as Color).to_html(false)]


# ------------------------------------------------------------------ tests

func test_counts() -> void:
	var c := Data.counts()
	var total := 0
	var line := "people by place:"
	for k: String in CityMap.PEOPLE_BUDGET:
		var want := int(CityMap.PEOPLE_BUDGET[k])
		total += want
		ok(int(c.get(k, 0)) == want, "%s: %d people, budget %d" % [k, int(c.get(k, 0)), want])
		line += " %s %d," % [k, int(c.get(k, 0))]
	ok(c.size() == (CityMap.PEOPLE_BUDGET as Dictionary).size(), "no place outside the budget (%s)" % str(c.keys()))
	_report.append(line.trim_suffix(",") + " = %d" % total)
	ok(pp.people.size() == total, "%d people built (%d budgeted)" % [pp.people.size(), total])
	ok(Data.WALKER_LOOKS.size() == int(CityMap.PEDESTRIANS), "a look per walker (%d)" % int(CityMap.PEDESTRIANS))
	var seen := []
	for t: float in [20.0, 101.0, 333.3, 1000.0]:
		pp.pose_at(t)
		var shown := 0
		for p: Variant in pp.people:
			if p.shown:
				shown += 1
		seen.append(shown)
		ok(shown >= total - 4 and shown <= total, "about 50 visible at %.0f s (%d)" % [t, shown])
	_report.append("visible at 20, 101, 333, 1000 s (no child riding): %s" % str(seen))


func test_actions() -> void:
	var by_action := {}
	for p: Variant in pp.people:
		by_action[p.action] = int(by_action.get(p.action, 0)) + 1
		ok(p.action in Data.ACTIONS, "%s: a known action (%s)" % [p.id, p.action])
	var line := "people by action:"
	var keys: Array = by_action.keys()
	keys.sort()
	for k: String in keys:
		line += " %s %d," % [k, int(by_action[k])]
	_report.append(line.trim_suffix(","))
	var missing: Array = []
	for a: String in Data.ACTIONS:
		if not by_action.has(a):
			missing.append(a)
	# "lift" has no NPC place (PropsCity.NPC_PLACES has none with pose lift) and the gym's four go to the
	# treadmill, the bike, the rower and the mat; the pose is implemented for when a place comes.
	ok(missing.is_empty() or missing == ["lift"], "every action shown but lift (missing %s)" % str(missing))
	if not missing.is_empty():
		_report.append("actions not shown: %s (no NPC place for it)" % str(missing))
	for e: Dictionary in Data.PEOPLE:
		var a := String(e["action"])
		ok(a in Data.SEATED_ACTIONS or a in Data.STANDING_ACTIONS or a in Data.MACHINE_ACTIONS, "%s: %s is seated, standing or a machine" % [e["id"], a])


func test_places() -> void:
	var places := {}
	if "NPC_PLACES" in PropsCity:
		for np: Dictionary in PropsCity.NPC_PLACES:
			places[String(np["id"])] = np
	ok(not places.is_empty(), "PropsCity.NPC_PLACES exists")
	var furn := _furniture()
	var own_kind := {"run": "treadmill", "cycle": "bike", "row": "rower", "stretch": "mat"}
	var used := {}
	for e: Dictionary in Data.PEOPLE:
		var id := String(e["id"])
		var region := String(e["region"])
		var pos: Vector2 = e["pos"]
		var action := String(e["action"])
		ok(region == "ground" or CityMap.REGIONS.has(region), "%s: region %s" % [id, region])
		ok(CityMap.PEOPLE_BUDGET.has(String(e["place"])), "%s: place %s is a budget key" % [id, e["place"]])
		var npc := String(e["npc"])
		if npc != "":
			ok(places.has(npc), "%s: NPC place %s exists" % [id, npc])
			ok(not used.has(npc), "%s: NPC place %s used once" % [id, npc])
			used[npc] = true
			if places.has(npc):
				var np: Dictionary = places[npc]
				ok(np["pos"] == pos and float(np["ry"]) == float(e["ry"]) and String(np["region"]) == region,
					"%s: exactly on its NPC place (%s, ry %.3f)" % [id, str(np["pos"]), float(np["ry"])])
				ok(String(np["place"]) == String(e["place"]), "%s: the place's budget key" % id)
				ok(String(np["pose"]) == String(e["pose"]), "%s: the place's pose" % id)
				var pose := String(np["pose"])
				if action in Data.SEATED_ACTIONS:
					ok(pose in ["sit", "desk"], "%s: seated on a seat (%s)" % [id, pose])
				elif action in own_kind:
					ok(pose == action, "%s: %s on a %s place" % [id, action, pose])
				else:
					ok(pose == "stand", "%s: standing on a standing place" % id)
		else:
			ok(Data.is_standing(e), "%s: only standing people stand off the NPC places" % id)
		var r := Data.SOLID_R if Data.is_standing(e) else 0.2
		ok(_inside(region, pos, 0.2), "%s: inside %s" % [id, region])
		for k: String in CityMap.INTERACTIONS:
			var it: Dictionary = CityMap.INTERACTIONS[k]
			if _norm(String(it["region"])) != _norm(region):
				continue
			var d := pos.distance_to(it["pos"])
			ok(d >= Data.MIN_CLEAR, "%s: %.2f m from the child's place %s (>= %.1f)" % [id, d, k, Data.MIN_CLEAR])
		# solid furniture: a standing person's body clear of it (but the machine they stand on); a seated
		# person's seat not inside a table (but their own machine)
		for f: Dictionary in furn:
			if String(f["region"]) != region:
				continue
			var rect: Rect2 = f["rect"]
			var own := own_kind.has(action) and String(f["kind"]) == String(own_kind[action]) and rect.has_point(pos)
			if own:
				continue
			if Data.is_standing(e):
				ok(_rect_dist(rect, pos) >= Data.SOLID_R - 0.02, "%s: clear of the %s at %s (%.2f)" % [id, f["kind"], str(rect.position), _rect_dist(rect, pos)])
			else:
				ok(not rect.grow(-0.02).has_point(pos), "%s: not inside the %s" % [id, f["kind"]])
		if region == "ground":
			for sd: Dictionary in CityMap.GROUND_SOLIDS:
				if sd.has("rect"):
					ok(_rect_dist(sd["rect"], pos) >= r - 0.02, "%s: clear of the %s" % [id, sd["kind"]])
				else:
					ok(pos.distance_to(sd["at"]) >= float(sd["r"]) + r - 0.02, "%s: clear of the %s" % [id, sd["kind"]])
	# nobody on top of anybody
	for i in Data.PEOPLE.size():
		for j in range(i + 1, Data.PEOPLE.size()):
			var a: Dictionary = Data.PEOPLE[i]
			var b: Dictionary = Data.PEOPLE[j]
			if a["region"] == b["region"]:
				ok((a["pos"] as Vector2).distance_to(b["pos"]) >= 0.55, "%s and %s apart" % [a["id"], b["id"]])


func test_solids() -> void:
	var sol := Data.solids()
	var standing := 0
	for e: Dictionary in Data.PEOPLE:
		if Data.is_standing(e):
			standing += 1
	ok(sol.size() == standing and standing > 0, "a solid per standing person (%d of %d)" % [sol.size(), standing])
	for s: Dictionary in sol:
		ok(s.has("region") and s.has("at") and s.has("r") and float(s["r"]) == Data.SOLID_R, "a solid's fields (%s)" % str(s))
	var nav: GDScript = load("res://scripts/core/city_nav.gd") as GDScript
	if nav != null and nav.has_method("people_solids"):
		var got: Variant = nav.call("people_solids")
		ok(got is Array and (got as Array).size() == sol.size(), "CityNav reads the solids (%d)" % ((got as Array).size() if got is Array else -1))
	_report.append("solid standing people: %d (r %.2f)" % [sol.size(), Data.SOLID_R])


func test_looks() -> void:
	var keys := ["sex", "skin", "hair_style", "hair_color", "top", "top_color", "bottom_color", "shoes", "accessory", "accent"]
	for la: Array in _all_looks():
		var l: Dictionary = la[0]
		var gen := Data.look_from_seed(int(la[1]), String(la[2]))
		var same := is_equal_approx(float(l["scale"]), float(gen["scale"]))
		for k: String in keys:
			if l[k] != gen[k]:
				same = false
		ok(same, "%s: its look is look_from_seed(%d, %s)" % [la[3], int(la[1]), la[2]])
		ok(String(l["hair_style"]) in Data.HAIR_STYLES and String(l["top"]) in Data.TOPS, "%s: a known hair style and top" % la[3])
	# heights: adults about 1.6 to 1.8 m, the passengers child-sized (the cabins are)
	for la: Array in _all_looks():
		var l: Dictionary = la[0]
		var h := float(l["scale"]) * 1.8
		if String(la[2]) == "rider":
			ok(h > 0.9 and h < 1.2, "%s: a child (%.2f m)" % [la[3], h])
		else:
			ok(h >= 1.6 and h <= 1.85, "%s: %.2f m tall" % [la[3], h])


func test_variety() -> void:
	var looks := _all_looks()
	var women := 0
	var styles := {}
	var tops := {}
	var skins := {}
	var triples := {}
	for la: Array in looks:
		var l: Dictionary = la[0]
		if String(l["sex"]) == "f":
			women += 1
		styles[String(l["hair_style"])] = true
		tops[String(l["top"])] = true
		skins[(l["skin"] as Color).to_html(false)] = true
		var tr_key := _triple(l)
		ok(not triples.has(tr_key), "%s: no other person has %s" % [la[3], tr_key])
		triples[tr_key] = true
	var frac := float(women) / float(looks.size())
	ok(frac >= 0.4 and frac <= 0.6, "about half women (%d of %d)" % [women, looks.size()])
	for s: String in ["long", "bun", "ponytail", "short", "curly"]:
		ok(styles.has(s), "hair style %s" % s)
	ok(styles.has("bald") or styles.has("cap"), "bald or a cap")
	ok(styles.size() >= 6, "at least 6 hair styles (%d)" % styles.size())
	for t: String in ["tee", "shirt", "jacket", "dress", "sports"]:
		ok(tops.has(t), "top %s" % t)
	ok(tops.has("apron") or tops.has("uniform"), "aprons or uniforms for staff")
	ok(skins.size() >= 6, "skin tones (%d)" % skins.size())
	_report.append("looks: %d (%d women), %d hair styles, %d tops, %d skin tones" % [looks.size(), women, styles.size(), tops.size(), skins.size()])
	# no look-alike neighbours within 3 m, at several times (walkers and riders move)
	var worst := INF
	for t: float in [12.0, 47.5, 133.0, 260.0, 801.0]:
		pp.pose_at(t)
		var pts: Array = []
		for p: Variant in pp.people:
			if p.shown:
				pts.append([_at(p, People.P_TORSO), _triple(p.look), p.id])
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				var d := (pts[i][0] as Vector3).distance_to(pts[j][0] as Vector3)
				if d < 3.0:
					ok(pts[i][1] != pts[j][1], "%s and %s, %.1f m apart, look alike at %.0f s" % [pts[i][2], pts[j][2], d, t])
					worst = minf(worst, d)


func test_no_sync() -> void:
	var offs := {}
	for p: Variant in pp.people:
		var tm := Data.timing(p.id)
		var key := "%.6f/%.6f" % [float(tm["offset"]), float(tm["rate"])]
		ok(not offs.has(key), "%s: its own clock" % p.id)
		offs[key] = true
		ok(float(tm["slot"]) >= 4.0 and float(tm["slot"]) <= 9.0, "%s: an idle event every 4 to 9 s (%.1f)" % [p.id, float(tm["slot"])])
	# nobody moves in step: no two people with the same action phase, now or a little later
	var times: Array[float] = [10.0, 77.7, 523.1, 2001.9]
	var phases: Array = []
	for t: float in times:
		var ph: Array[float] = []
		for p: Variant in pp.people:
			ph.append(pp.phase_of(p, t))
		phases.append(ph)
	var n := pp.people.size()
	var in_step := 0
	var exact := 0
	for i in n:
		for j in range(i + 1, n):
			var close := 0
			for k in times.size():
				var d := absf(float(phases[k][i]) - float(phases[k][j]))
				d = minf(d, 1.0 - d)
				if d < 1e-6:
					exact += 1
				if d < 0.02:
					close += 1
			if close == times.size():
				in_step += 1
				ok(false, "%s and %s move in step" % [pp.people[i].id, pp.people[j].id])
	ok(exact == 0, "no two action phases equal at the sampled times (%d)" % exact)
	ok(in_step == 0, "no pair in step over the sampled times")


func test_walkers() -> void:
	var walkers := _kind(People.K_WALKER)
	ok(walkers.size() == int(CityMap.PEDESTRIANS), "%d walkers" % walkers.size())
	var swings := 0
	var opposite := 0
	var bob_lo := INF
	var bob_hi := -INF
	for k in 60:
		var t := 5.0 + 0.0731 * float(k)
		pp.pose_at(t)
		var ws := CityRules.walkers(t)
		for p: Variant in walkers:
			var w: Dictionary = ws[p.index]
			var wp: Vector2 = w["pos"]
			var torso := _at(p, People.P_TORSO)
			ok(Vector2(torso.x, torso.z).distance_to(wp) < 0.35, "%s on CityRules' walker %d at %.2f s" % [p.id, p.index, t])
			var inv: Transform3D = (p.world as Transform3D).affine_inverse()
			var pel := inv * _at(p, People.P_PELVIS)
			for side in 2:
				var hand := inv * _at(p, People.P_HAND0 + side)
				var shoe := inv * _at(p, People.P_SHOE0 + side)
				var leg := shoe.z - pel.z
				if absf(leg) > 0.15:
					swings += 1
					if signf(hand.z - pel.z) == -signf(leg):
						opposite += 1
			if p.index == 0:
				var ty := (inv * torso).y
				bob_lo = minf(bob_lo, ty)
				bob_hi = maxf(bob_hi, ty)
	ok(swings > 100 and opposite == swings, "each arm swings against the leg on its side (%d of %d strides)" % [opposite, swings])
	ok(bob_hi - bob_lo > 0.01 and bob_hi - bob_lo < 0.1, "a slight bob (%.3f m)" % (bob_hi - bob_lo))
	# the walkers' phases are staggered
	var ph := {}
	for w: Dictionary in CityRules.walkers(42.0):
		ph["%.4f" % float(w.get("phase", 0.0))] = true
	ok(ph.size() == walkers.size(), "walkers out of step (%d phases)" % ph.size())


func test_geometry() -> void:
	pp.pose_at(30.0)
	for p: Variant in _static_people():
		var e: Dictionary = {}
		for x: Dictionary in Data.PEOPLE:
			if String(x["id"]) == p.id:
				e = x
		var root_y: float = (p.root as Transform3D).origin.y
		var head := _at(p, People.P_HEAD)
		var top: float = head.y + 0.175 * p.s
		if Data.is_standing(e) and p.action != "stretch":
			ok(top - root_y > 1.5 and top - root_y < 1.9, "%s: head top %.2f m above the floor" % [p.id, top - root_y])
			var foot: float = minf(_at(p, People.P_SHOE0).y, _at(p, People.P_SHOE1).y) - 0.04 * float(p.s)
			ok(absf(foot - root_y) < 0.03, "%s: feet on the floor (%.3f)" % [p.id, foot - root_y])
		elif p.seated:
			var above: float = top - root_y - float(p.seat)
			ok(above > 0.8 and above < 1.15, "%s: seated head top %.2f m above the seat" % [p.id, above])
			var lap := _at(p, People.P_LAP)
			ok(absf(lap.y - (root_y + p.seat + People.SIT_HIP * p.s)) < 0.05, "%s: sits on the seat" % p.id)
		if p.action == "type":
			var desk: float = root_y + (p.table as Vector2).y
			for k in 2:
				var h := _at(p, People.P_HAND0 + k)
				ok(absf(h.y - desk) < 0.12, "%s: hand %d at the keyboard (%.2f over the desk)" % [p.id, k, h.y - desk])
		if p.action in ["serve_counter", "wipe_counter"]:
			var counter: float = root_y + (p.table as Vector2).y
			var h := _at(p, People.P_HAND0)
			ok(absf(h.y - counter) < 0.15, "%s: a hand on the counter (%.2f)" % [p.id, h.y - counter])


func test_ferris() -> void:
	var rules := CityRules.new()
	var board_at: Vector2 = CityMap.FERRIS["board_at"]
	var prev := {}
	var prev_t := 0.0
	var visible_time := 0.0
	var max_seen := 0
	var with_child := 0
	var changes := 0
	var dropped := 0
	var boarded := 0
	pp._child_lap = {}
	var dt := 0.5
	var steps := int(2400.0 / dt)
	for k in steps:
		var t: float = rules.time
		# children: one tries to board every ~23 s; every third ride drops out mid-air
		if k % 46 == 7:
			var peer := 100 + int(k / 46.0) % 3
			if not rules.is_riding(peer):
				var b: Dictionary = rules.board(peer, t, "", board_at)
				if b.get("ok", false):
					boarded += 1
		if k % 46 == 40 and int(k / 46.0) % 3 == 1:
			for peer: int in rules.riders.keys():
				rules.leave(peer)
				dropped += 1
		var by_g := {}
		for peer: int in rules.riders:
			var g := int((rules.riders[peer] as Dictionary)["g"])
			if not by_g.has(g):
				by_g[g] = []
			(by_g[g] as Array).append(peer)
		if not by_g.is_empty():
			with_child += 1
		pp.riders_override = by_g
		var fer: Dictionary = pp.ferris_now(t)
		var seats := {}
		for slot: int in fer:
			var f: Array = fer[slot]
			var g := int(f[0])
			ok(not by_g.has(g), "slot %d in gondola %d with a child aboard at %.1f s" % [slot, g, t])
			var key := "%d/%d" % [g, int(f[1])]
			ok(not seats.has(key), "two passengers on seat %s at %.1f s" % [key, t])
			seats[key] = true
		ok(fer.size() <= 4, "at most 4 passengers (%d)" % fer.size())
		max_seen = maxi(max_seen, fer.size())
		if not fer.is_empty():
			visible_time += dt * float(fer.size())
		# a change (on, off, another gondola or person) only while the gondolas concerned are at the bottom
		for slot in 4:
			var a: Variant = prev.get(slot, null)
			var b: Variant = fer.get(slot, null)
			if str(a) == str(b) or k == 0:
				continue
			changes += 1
			for f: Variant in [a, b]:
				if f == null:
					continue
				var g := int((f as Array)[0])
				var at_b := CityRules.at_bottom(g, t) or CityRules.at_bottom(g, prev_t)
				ok(at_b, "slot %d changed (%s -> %s) at %.1f s with gondola %d away from the bottom" % [slot, str(a), str(b), t, g])
		prev = fer
		prev_t = t
		rules.tick(dt)
	pp.riders_override = {}
	_report.append("Ferris (2400 s simulated, %d boardings, %d drop-outs): up to %d passengers, %.1f on average; %d changes, all at the bottom" % [
		boarded, dropped, max_seen, visible_time / 2400.0, changes])
	ok(boarded > 20 and dropped > 3 and with_child > 100, "the simulation had children riding (%d, %d)" % [boarded, dropped])
	ok(max_seen == 4 and visible_time / 2400.0 > 1.5, "passengers ride most of the time")
	# drawn in their gondolas, under the roof
	var checked := 0
	for t: float in [3.0, 41.0, 77.0, 150.0, 222.0]:
		pp._child_lap = {}
		pp.pose_at(t)
		var fer: Dictionary = pp.ferris_now(t)
		for p: Variant in _kind(People.K_FERRIS):
			if not fer.has(p.index):
				ok(not p.shown and _is_zero(pp.part_transform(p, People.P_TORSO)), "%s hidden off the wheel at %.0f s" % [p.id, t])
				continue
			var f: Array = fer[p.index]
			var seat: Transform3D = CityWorld.rider_transform(int(f[0]), CityWorld.ferris_angle_at(t), int(f[1]))
			var lap := _at(p, People.P_LAP)
			ok(lap.distance_to(seat.origin + Vector3(0, People.BENCH_Y, 0)) < 0.25, "%s on its seat in gondola %d" % [p.id, int(f[0])])
			var top: float = _at(p, People.P_HEAD).y + 0.175 * p.s
			ok(top - seat.origin.y <= CABIN_CLEAR, "%s: head under the cabin roof (%.2f m)" % [p.id, top - seat.origin.y])
			ok(p.look == ((Data.FERRIS_SLOTS[p.index]["looks"] as Array)[int(f[2])] as Dictionary)["look"], "%s: the look of this ride" % p.id)
			checked += 1
	ok(checked >= 8, "passengers checked in place (%d)" % checked)


func test_carousel() -> void:
	var riders := _kind(People.K_CAROUSEL)
	ok(riders.size() == 2, "two carousel riders")
	ok(cw.has_method("carousel_seat_transform"), "CityWorld.carousel_seat_transform exists")
	for p: Variant in riders:
		var ys: Array = []
		for t: float in [3.0, 3.65, 4.3, 9.1]:
			pp.pose_at(t)
			var seat: Transform3D = CityWorld.carousel_seat_transform(p.index, t)
			var pel := _at(p, People.P_PELVIS)
			ok(Vector2(pel.x, pel.z).distance_to(Vector2(seat.origin.x, seat.origin.z)) < 0.12, "%s on horse %d at %.2f s" % [p.id, p.index, t])
			ys.append(pel.y - seat.origin.y)
			var fwd := seat.basis.z.normalized()
			var face := ((p.world as Transform3D).basis.z).normalized()
			ok(fwd.dot(face) > 0.99, "%s faces where the horse goes" % p.id)
		var spread: float = (ys.max() as float) - (ys.min() as float)
		ok(spread < 0.01, "%s bobs with its horse (%.3f)" % [p.id, spread])


func _buffers() -> Array:
	return pp.snapshot()


func test_determinism() -> void:
	pp.pose_at(41.3)
	var a := _buffers()
	pp.pose_at(41.3)
	ok(_buffers() == a, "two pose_at(41.3) give the same transforms")
	pp.pose_at(97.0)
	ok(_buffers() != a, "another time, another pose")
	pp.pose_at(41.3)
	ok(_buffers() == a, "pose_at(41.3) again after another time: the same")
	# frame by frame, everybody who moves is where pose_at puts them (riders' legs go with their gondola)
	pp.pose_at(150.0)
	for k in 30:
		pp.frame(150.0 + float(k + 1) / 30.0)
	var live := pp.snapshot()
	var t_end := 151.0
	var moving: Array = []
	for p: Variant in pp.people:
		if p.fast:
			moving.append(p)
	var before: Array = []
	for p: Variant in moving:
		var parts: Array = []
		for part in People.P_COUNT:
			parts.append(pp.part_transform(p, part))
		before.append(parts)
	pp.pose_at(t_end)
	var off := 0
	for i in moving.size():
		for part in People.P_COUNT:
			var a0: Transform3D = before[i][part]
			var b0: Transform3D = pp.part_transform(moving[i], part)
			if not a0.is_equal_approx(b0):
				off += 1
				if off < 6:
					ok(false, "%s part %d: frame() and pose_at() differ" % [moving[i].id, part])
	ok(off == 0 and live.size() > 0, "frame() poses every moving person as pose_at() does (%d parts differ)" % off)
	pp.pose_at(41.3)
	# Pause: the same view time writes nothing and changes nothing
	ok(pp.frame(41.3) == 0 and _buffers() == a, "paused (same view time): nothing moves")


func test_hidden() -> void:
	pp.pose_at(60.0)
	var hide := ["office_l1", "gym_roof"]
	pp.set_hidden_regions(hide)
	pp.frame(60.02)
	pp.frame(60.04)
	var hid := 0
	for p: Variant in _static_people():
		var z := _is_zero(pp.part_transform(p, People.P_TORSO)) and _is_zero(pp.part_transform(p, People.P_HEAD))
		if p.region in hide:
			ok(z, "%s hidden with %s" % [p.id, p.region])
			hid += 1
		else:
			ok(not z, "%s still shown" % p.id)
	ok(hid >= 8, "people hidden on cut-away storeys (%d)" % hid)
	pp.set_hidden_regions([])
	pp.frame(60.06)
	pp.frame(60.08)
	for p: Variant in _static_people():
		ok(not _is_zero(pp.part_transform(p, People.P_TORSO)), "%s back" % p.id)


func test_budgets() -> void:
	var calls := 0
	var tris := 0
	var instances := 0
	var mat := PropsCity.material()
	for c: Node in pp.get_children():
		ok(c is MultiMeshInstance3D, "%s is a MultiMeshInstance3D" % c.name)
		if not c is MultiMeshInstance3D:
			continue
		var mi := c as MultiMeshInstance3D
		var mm := mi.multimesh
		ok(mm.use_colors and mm.transform_format == MultiMesh.TRANSFORM_3D, "%s: per-instance colours" % mi.name)
		ok(mi.material_override == mat and (mat as StandardMaterial3D).vertex_color_use_as_albedo, "%s: the city's matte vertex-colour material" % mi.name)
		var faces := int(mm.mesh.get_faces().size() / 3.0)
		if mm.instance_count > 0:
			calls += mm.mesh.get_surface_count()
		tris += faces * mm.instance_count
		instances += mm.instance_count
		_report.append("  %s: %d instances x %d triangles" % [mi.name, mm.instance_count, faces])
	_report.append("people: %d draw calls, %d triangles, %d instances (budgets %d, %d)" % [calls, tris, instances, MAX_CALLS, MAX_TRIS])
	ok(calls <= MAX_CALLS, "draw calls %d <= %d" % [calls, MAX_CALLS])
	ok(tris <= MAX_TRIS, "triangles %d <= %d" % [tris, MAX_TRIS])
	var full := pp.pose_at(50.0)
	var worst := 0
	var total := 0
	for i in 240:
		var w := pp.frame(50.0 + float(i + 1) / 60.0)
		worst = maxi(worst, w)
		total += w
	_report.append("instance transforms per frame: at most %d, %.0f on average (a full pose_at: %d)" % [worst, float(total) / 240.0, full])
	ok(worst <= MAX_WRITES, "at most %d transforms per frame (%d)" % [MAX_WRITES, worst])


func test_no_randomness() -> void:
	for path: String in ["res://scripts/art/city_people.gd", "res://scripts/core/city_people_data.gd"]:
		var src := FileAccess.get_file_as_string(path)
		ok(src.length() > 0, "%s read" % path)
		for bad: String in ["randf", "randi", "RandomNumberGenerator", "Time.get_"]:
			ok(not src.contains(bad), "%s has no %s" % [path, bad])


# ------------------------------------------------------------------ city r3: rain, umbrellas, posture

const W_SUNNY := 0
const W_RAIN := 1
const W_NIGHT := 2
## Nobody moves faster than this (m/s): a hurried walk, a walker catching up, a horse, a gondola.
const MAX_SPEED := 3.0


func _wx(w: int, since: float, prev: int) -> void:
	var mix := Vector3(1, 0, 0)
	if prev == W_RAIN:
		mix = Vector3(0, 1, 0)
	elif prev == W_NIGHT:
		mix = Vector3(0, 0, 1)
	pp.weather_override = {"weather": w, "since": since, "prev": mix}


func _reacting(shelter_only: bool) -> Array:
	var out: Array = []
	for p: Variant in pp.people:
		if p.react and not (shelter_only and p.umbrella):
			out.append(p)
	return out


func _in_cover(p: Variant, pos: Vector3) -> bool:
	var reg := String((pp.spots[p.spot] as Dictionary)["region"])
	for c: Dictionary in Data.covers():
		if String(c["region"]) == reg and (c["rect"] as Rect2).grow(0.3).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


func test_rain_who() -> void:
	var counts := {"walkers": 0, "static": 0, "carousel": 0}
	var eligible := 0
	var umbrellas := 0
	var shelter: Array = []
	var umb: Array = []
	for p: Variant in pp.people:
		if p.kind == People.K_STATIC:
			var e: Dictionary = {}
			for x: Dictionary in Data.PEOPLE:
				if String(x["id"]) == p.id:
					e = x
			var pos: Vector2 = e["pos"]
			var outdoor := not Data.is_indoor(p.region, pos) and not Data.under_cover(p.region, pos)
			ok(p.react == outdoor, "%s reacts to rain only outdoors and uncovered (%s)" % [p.id, str(outdoor)])
		if p.kind == People.K_FERRIS:
			ok(not p.react, "%s: a gondola is a cover" % p.id)
		if p.kind in [People.K_WALKER, People.K_CAROUSEL]:
			ok(p.react, "%s reacts" % p.id)
		if not p.react:
			continue
		if p.kind == People.K_WALKER:
			counts["walkers"] += 1
		elif p.kind == People.K_CAROUSEL:
			counts["carousel"] += 1
		else:
			counts["static"] += 1
		var may: bool = p.kind == People.K_WALKER or (p.kind == People.K_STATIC and (p.seated or p.legs_seat))
		if may:
			eligible += 1
			ok(p.umbrella == Data.umbrella_for(p.id), "%s: umbrella by its id" % p.id)
		else:
			ok(not p.umbrella, "%s: staff and riders take cover, no umbrella" % p.id)
		if p.umbrella:
			umbrellas += 1
			umb.append(p.id)
			ok(p.slots[People.P_UMBRELLA] >= 0, "%s has an umbrella part" % p.id)
		else:
			shelter.append(p.id)
			ok(p.kind == People.K_WALKER or p.spot >= 0, "%s has a cover spot" % p.id)
	var share := float(umbrellas) / float(maxi(eligible, 1))
	ok(share >= 0.2 and share <= 0.5, "about a third open umbrellas (%d of %d, share %.2f)" % [umbrellas, eligible, float(CityMap.UMBRELLA_SHARE)])
	_report.append("rain: %d react (%d walkers, %d static, %d carousel); umbrellas %d of %d who may %s; take cover %d %s" % [
		_reacting(false).size(), counts["walkers"], counts["static"], counts["carousel"], umbrellas, eligible, str(umb), shelter.size(), str(shelter)])


func test_spots_and_paths() -> void:
	var seen := {}
	for i in pp.spots.size():
		var sp: Dictionary = pp.spots[i]
		var q: Vector2 = sp["pos"]
		var key := "%s/%.2f/%.2f" % [sp["region"], q.x, q.y]
		ok(not seen.has(key), "spot %s listed once" % key)
		seen[key] = true
		for k: String in CityMap.INTERACTIONS:
			var it: Dictionary = CityMap.INTERACTIONS[k]
			if _norm(String(it["region"])) == _norm(String(sp["region"])):
				ok(q.distance_to(it["pos"]) >= Data.MIN_CLEAR, "spot %s clear of the child's place %s" % [key, k])
		ok(Data.under_cover(String(sp["region"]), q, 0.0), "spot %s is under its cover" % key)
	# the static people's paths are real routes: every 0.1 m walkable on its region
	for p: Variant in _reacting(true):
		if p.kind != People.K_STATIC:
			continue
		ok(p.base.size() >= 2, "%s has a path" % p.id)
		var bad := 0
		for i in range(1, p.base.size()):
			var a: Vector3 = p.base[i - 1]
			var b: Vector3 = p.base[i]
			var n := maxi(1, ceili(a.distance_to(b) / 0.1))
			for j in n + 1:
				var q := a.lerp(b, float(j) / float(n))
				if Vector2(q.x, q.z).distance_to(Vector2(p.base[0].x, p.base[0].z)) < Data.SOLID_R + 0.35:
					continue
				var r0 := String(p.base_reg[i - 1])
				var r1 := String(p.base_reg[i])
				if not CityNav.allowed(_norm(r0), Vector2(q.x, q.z)) and not CityNav.allowed(_norm(r1), Vector2(q.x, q.z)):
					bad += 1
		ok(bad == 0, "%s: its route is walkable (%d bad samples)" % [p.id, bad])
	# every walker's way off its lane to a spot: walkable every 0.1 m (CityNav.allowed), the lane point aside
	var legs := 0
	var bad_legs := 0
	for key: Vector2i in People._exits:
		var ex: Dictionary = People._exits[key]
		if ex.is_empty():
			continue
		legs += 1
		var leg: PackedVector2Array = ex["leg"]
		var bad := 0
		for i in range(1, leg.size()):
			var n := maxi(1, ceili(leg[i - 1].distance_to(leg[i]) / 0.1))
			for j in n + 1:
				var q := leg[i - 1].lerp(leg[i], float(j) / float(n))
				if q.distance_to(leg[0]) < 0.3:
					continue
				if not CityNav.allowed("", q):
					bad += 1
		if bad > 0:
			bad_legs += 1
			if bad_legs < 6:
				ok(false, "walker leg %s to %s: %d samples not walkable" % [str(key), str(leg[leg.size() - 1]), bad])
	ok(legs > 30 and bad_legs == 0, "walkers' ways to cover are walkable (%d legs, %d bad)" % [legs, bad_legs])
	_report.append("cover spots: %d (A1 COVERS, extra overhead covers, CityNav.cover_spots); walker legs to cover: %d" % [pp.spots.size(), legs])


func test_rain_cover() -> void:
	pp.reset_weather()
	_wx(W_SUNNY, -4.0, W_SUNNY)
	pp.pose_at(50.0)
	var t0 := 60.0
	_wx(W_RAIN, t0, W_SUNNY)
	pp.pose_at(t0)
	var travel := 0.0
	var starts: Array[float] = []
	for p: Variant in _reacting(true):
		var st := float(p.rec.get("start", t0))
		ok(st >= t0 - 1e-6 and st <= t0 + float(CityMap.RAIN_COVER_SPREAD) + 1e-6, "%s starts within the spread (%.2f)" % [p.id, st - t0])
		starts.append(st)
		travel = maxf(travel, pp._plen(p) / Data.HURRY_SPEED)
	starts.sort()
	var distinct := true
	for i in range(1, starts.size()):
		if starts[i] - starts[i - 1] < 0.01:
			distinct = false
	ok(distinct, "start times differ (staggered): %s" % str(starts))
	ok(starts[starts.size() - 1] - starts[0] > 3.0, "spread over seconds (%.1f s)" % (starts[starts.size() - 1] - starts[0]))
	# groups: some start within a second of each other
	var close := 0
	for i in range(1, starts.size()):
		if starts[i] - starts[i - 1] < 1.0:
			close += 1
	ok(close >= 2, "small groups start together (%d close pairs)" % close)
	var t_end := t0 + float(CityMap.RAIN_COVER_SPREAD) + travel + 0.2
	var t := t0
	var moved := 0
	while t < t_end:
		t += 0.1
		pp.pose_at(t)
	for p: Variant in _reacting(false):
		var torso := _at(p, People.P_TORSO)
		if p.umbrella:
			ok(not _is_zero(pp.part_transform(p, People.P_UMBRELLA)) and float(pp._eval(p, t)["umb"]) >= 1.0, "%s: umbrella open" % p.id)
			continue
		ok(_in_cover(p, torso), "%s under cover by %.1f s (at %s)" % [p.id, t_end - t0, str(torso)])
		var sp: Dictionary = pp.spots[p.spot]
		var q: Vector2 = sp["pos"]
		ok(Vector2(torso.x, torso.z).distance_to(q) < 0.35, "%s at its spot" % p.id)
		moved += 1
	_report.append("rain at %.0f s: %d people under cover by +%.1f s (spread %.0f s + longest walk %.1f s), umbrellas open" % [
		t0, moved, t_end - t0, float(CityMap.RAIN_COVER_SPREAD), travel])
	# one person per spot
	var used := {}
	for p: Variant in _reacting(true):
		ok(not used.has(p.spot), "%s: its own spot" % p.id)
		used[p.spot] = true


## A whole cycle at 0.1 s: sunny, rain, sunny again mid-way, rain again, sunny, rain mid-return, night. Nobody
## jumps, nobody vanishes, nobody waits on a child's place, the frame budget holds; at the end everybody is back
## exactly where and as they are on a dry day; and a coarser run lands on the same poses (determinism).
func test_weather_cycle() -> void:
	var changes: Array = [[-4.0, W_SUNNY], [30.0, W_RAIN], [36.0, W_SUNNY], [42.0, W_RAIN], [100.0, W_SUNNY],
		[103.0, W_RAIN], [140.0, W_NIGHT], [200.0, W_SUNNY]]
	var res := _run_cycle(changes, 0.1, 290.0, true)
	var res2 := _run_cycle(changes, 0.37, 290.0, false)
	ok(res == res2, "the same cycle in coarser steps lands on the same poses (deterministic from the shared times)")
	# back to normal: the same as a city that never saw rain
	pp.reset_weather()
	_wx(W_SUNNY, -4.0, W_SUNNY)
	pp.pose_at(290.0)
	var dry: Array = []
	for p: Variant in pp.people:
		if p.kind != People.K_FERRIS:
			for part in People.P_COUNT:
				dry.append(pp.part_transform(p, part))
	var same := dry.size() == (res as Array).size()
	var diff := 0
	if same:
		for i in dry.size():
			if not (dry[i] as Transform3D).is_equal_approx((res as Array)[i] as Transform3D):
				diff += 1
	ok(same and diff == 0, "after the rain everybody is back at their places and activities (%d parts differ)" % diff)


func _run_cycle(changes: Array, dt: float, t_end: float, checks: bool) -> Array:
	pp.reset_weather()
	var ci := 0
	_wx(int(changes[0][1]), float(changes[0][0]), W_SUNNY)
	var t := 0.0
	pp.pose_at(t)
	var last := {}
	var count0 := -1
	var worst := 0.0
	var worst_id := ""
	var max_writes := 0
	var still := {}
	while t < t_end - 1e-9:
		t = minf(t_end, t + dt)
		while ci + 1 < changes.size() and float(changes[ci + 1][0]) <= t:
			ci += 1
			_wx(int(changes[ci][1]), float(changes[ci][0]), int(changes[ci - 1][1]))
		if checks:
			max_writes = maxi(max_writes, pp.frame(t))
		else:
			pp.pose_at(t)
		if not checks:
			continue
		var shown := 0
		for p: Variant in pp.people:
			if p.kind == People.K_FERRIS:
				continue
			if p.shown:
				shown += 1
			var pos := _at(p, People.P_TORSO)
			if last.has(p.id):
				var step := (last[p.id] as Vector3).distance_to(pos)
				if step > worst:
					worst = step
					worst_id = "%s at %.1f s" % [p.id, t]
				# at rest somewhere: never on a child's place
				if step < 1e-4 and p.react:
					still[p.id] = Vector2(pos.x, pos.z)
			last[p.id] = pos
		if count0 < 0:
			count0 = shown
		ok(shown == count0, "nobody vanishes at %.1f s (%d of %d)" % [t, shown, count0])
	if checks:
		var on_child := 0
		for id: String in still:
			var q: Vector2 = still[id]
			for k: String in CityMap.INTERACTIONS:
				var it: Dictionary = CityMap.INTERACTIONS[k]
				var pr: Variant = pp.person(id)
				if _norm(String(it["region"])) == "" and String(pr.region) == "ground" and q.distance_to(it["pos"]) < Data.MIN_CLEAR:
					on_child += 1
		ok(on_child == 0, "nobody who reacts to rain rests on a child's place (%d)" % on_child)
		ok(worst <= MAX_SPEED * dt + 0.05, "nobody jumps: the largest step in %.1f s is %.3f m (%s)" % [dt, worst, worst_id])
		ok(max_writes <= MAX_WRITES, "at most %d transforms per frame through the weather (%d)" % [MAX_WRITES, max_writes])
		_report.append("weather cycle at %.1f s steps: largest step %.3f m (%s), %d visible throughout, at most %d transforms per frame" % [
			dt, worst, worst_id, count0, max_writes])
	pp.pose_at(t_end)
	var out: Array = []
	for p: Variant in pp.people:
		if p.kind != People.K_FERRIS:
			for part in People.P_COUNT:
				out.append(pp.part_transform(p, part))
	return out


## Seated people adjust their posture now and then (shift, lean back, cross the legs), on their own slot.
func test_posture() -> void:
	pp.reset_weather()
	_wx(W_SUNNY, -4.0, W_SUNNY)
	var kinds := {}
	var crossed := 0
	for p: Variant in _static_people():
		if not (p.seated or p.legs_seat):
			continue
		var t := 0.0
		while t < 60.0:
			var tau: float = p.tau(t)
			var ev: Vector3 = People._event(p, tau + 3.7, 3.6, 151)
			if ev.y >= 0.0 and ev.x > 0.9:
				kinds[int(ev.z * 3.0)] = true
			t += 0.5
		pp.pose_at(13.0)
	for t2: float in [5.0, 9.0, 13.0, 17.0, 21.0, 25.0]:
		pp.pose_at(t2)
		for p: Variant in _static_people():
			if p.seated and absf(float(p.pose.cross)) > 0.5:
				crossed += 1
	ok(kinds.size() == 3, "posture shifts, leans back and crossed legs all happen (%s)" % str(kinds.keys()))
	ok(crossed > 0, "someone crosses their legs (%d samples)" % crossed)
