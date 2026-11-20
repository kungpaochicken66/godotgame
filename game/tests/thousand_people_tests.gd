## Headless tests for Thousand Town's residents in the street (art/thousand_people.gd; design/thousand-town.md
## sections 1, 5 and 8). Nothing renders.
##   scripts/godot.sh --headless --path game -s res://tests/thousand_people_tests.gd
## The ground: walkable and blocked samples, every door and stop reachable. Counts: at a morning commute, midday,
## the evening, the night and a Sunday, everybody the sim puts outdoors is drawn, aboard a ride or nowhere (never
## more, never fewer), each drawn figure is a real resident in an outdoor state, standing on walkable ground (checked
## against the raw town.json and solids.json data, independently of the raster), near the ground's height, and a
## walker gets closer to where it is going. Heights by age; determinism; picking; the budgets and LOD; the per-frame
## cost (reported, with a generous bound).
extends SceneTree

const Sim := preload("res://scripts/core/thousand_sim.gd")
const Data := preload("res://scripts/core/thousand_sim_data.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const People := preload("res://scripts/art/thousand_people.gd")

const MINUTES := [[1, 450.0, "weekday 07:30"], [1, 720.0, "weekday 12:00"], [1, 1020.0, "weekday 17:00"],
	[1, 1260.0, "weekday 21:00"], [1, 180.0, "weekday 03:00"], [7, 600.0, "sunday 10:00"], [6, 1140.0, "saturday 19:00"]]
## EC2 headless bound for one frame of people (milliseconds, average over 4 s of frames); the measured value is printed.
const FRAME_MS_BOUND := 4.0

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var sim: Sim
var pp: People
var _solids: Array[Rect2] = []
var _zebras: Array[Rect2] = []
var _roads: Array = []
var _footbridges: Array[Rect2] = []
var _covers: Array[Rect2] = []


func _initialize() -> void:
	sim = Sim.new()
	pp = People.new()
	root.add_child(pp)
	pp.sync_routes = true
	pp.setup(sim)
	_load_raw()
	for t: String in ["test_ground", "test_routes", "test_counts", "test_walkers_move", "test_heights", "test_looks",
			"test_inside_not_drawn", "test_determinism", "test_picking", "test_info", "test_budgets", "test_timing"]:
		_current = t
		call(t)
	for line: String in _report:
		print(line)
	print("\nTHOUSAND PEOPLE TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		if _failures < 80:
			print("FAIL [%s] %s" % [_current, what])


# ------------------------------------------------------------------ the raw data, for an independent check

static func _rect(d: Dictionary) -> Rect2:
	return Rect2(float(d.x) - float(d.w) * 0.5, float(d.z) - float(d.d) * 0.5, float(d.w), float(d.d))


func _load_raw() -> void:
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string("res://thousand_town/data/solids.json"))
	for s: Dictionary in j.data.solids:
		if s.has("rect"):
			_solids.append(_rect(s.rect))
	var town := TMap.data()
	for c: Dictionary in town.crossings:
		for z: Dictionary in c.zebras:
			var r := _rect(z)
			_zebras.append(r.grow_individual(0.0, 1.0, 0.0, 1.0) if String(z.walk_axis) == "z" else r.grow_individual(1.0, 0.0, 1.0, 0.0))
	_roads = TMap.roads()
	for b: Dictionary in town.bridges:
		if String(b.kind) == "footbridge":
			_footbridges.append(_rect(b))
	for t: Dictionary in town.tunnels:
		_covers.append(Rect2(-float(t.cover_x), float(t.z) - float(t.half_d), float(t.cover_x) * 2.0, float(t.half_d) * 2.0))


## Walkable by the raw data: on the board, not in a solid's footprint, not in the canal (but on a footbridge), not
## on a roadway (but on a zebra, the pedestrian street or a tunnel cover). Returns "" or the reason.
func _raw_block(p: Vector2) -> String:
	if absf(p.x) > 95.0 or absf(p.y) > 129.0:
		return "off the board"
	for r in _solids:
		if r.has_point(p):
			return "in a solid %s" % r
	var on_bridge := false
	for r in _footbridges:
		if r.has_point(p):
			on_bridge = true
	if absf(p.x) < 7.5 and not on_bridge:
		return "in the canal"
	for rd: Dictionary in _roads:
		var r: Rect2 = rd.rect
		if not r.has_point(p):
			continue
		if float(rd.walk_only_to) > 0.0 and absf(p.x) <= float(rd.walk_only_to):
			continue
		var ok_here := false
		for z in _zebras:
			if z.has_point(p):
				ok_here = true
		for c in _covers:
			if c.has_point(p) and absf(p.x) >= 7.5:
				ok_here = true
		if not ok_here:
			return "on the roadway of %s" % rd.id
	return ""


# ------------------------------------------------------------------ tests

func test_ground() -> void:
	var g := People.ground()
	ok(g.walkable(Vector2(-52.0, 3.6)), "the arrival point is walkable")
	ok(not g.walkable(Vector2(0.0, 60.0)), "the canal is not walkable")
	ok(g.walkable(Vector2(0.0, 20.0)) and g.walkable(Vector2(0.0, -20.0)), "the footbridges are walkable")
	ok(not g.walkable(Vector2(0.0, 40.0)), "the road bridge is not a pavement")
	ok(not g.walkable(Vector2(-48.0, -60.0)), "the avenue's roadway is not walkable")
	ok(g.walkable(Vector2(-48.0, -84.5)), "a zebra across the avenue is walkable")
	ok(g.walkable(Vector2(-30.0, 0.0)), "the pedestrian street (z = 0) is walkable")
	ok(not g.walkable(Vector2(-66.0, -102.0)), "the primary school's building is not walkable")
	ok(absf(g.y_at(Vector2(-60.0, -10.0)) - 0.125) < 1e-4, "the pavement is at 0.125 m")
	ok(g.y_at(Vector2(0.0, 20.0)) > 0.9, "the footbridge rises (%.2f m)" % g.y_at(Vector2(0.0, 20.0)))
	# the raster agrees with the raw data on a grid of samples
	var bad := 0
	var n := 0
	for x in range(-94, 95, 3):
		for z in range(-128, 129, 3):
			var p := Vector2(x + 0.37, z + 0.61)
			if g.walkable(p):
				n += 1
				if _raw_block(p) != "":
					bad += 1
	ok(bad == 0, "every walkable raster sample is walkable by the raw data (%d of %d are not)" % [bad, n])
	_report.append("ground: built in %.1f ms, %d walkable samples of the 3 m grid" % [g.build_ms, n])


func test_routes() -> void:
	var lay := pp.layout()
	var nodes: PackedVector2Array = lay.nodes
	var doors: PackedInt32Array = lay.doors
	var g := People.ground()
	var arrival := pp._node(Vector2(-52.0, 3.6))
	var missing := 0
	for b in doors.size():
		var venue := String(pp._loc_venue[b]) != ""
		ok(venue or doors[b] >= 0, "building %s has a door node" % Data.BUILDINGS[b]["id"])
	var targets := PackedInt32Array()
	for b in doors.size():
		if doors[b] >= 0:
			targets.append(doors[b])
	for s: Dictionary in lay.stops:
		targets.append(int(s.node))
	for key: String in lay.venues:
		var hubs: PackedInt32Array = lay.venues[key].hubs
		ok(not hubs.is_empty(), "venue %s has hubs" % key)
		ok((lay.venues[key].spots as PackedVector2Array).size() >= 4, "venue %s has spots (%d)" % [key, (lay.venues[key].spots as PackedVector2Array).size()])
		if not hubs.is_empty():
			targets.append(hubs[0])
	var off := 0
	for t in targets:
		var r: Variant = pp._route(arrival, t)
		var path: PackedVector2Array = r
		if path.is_empty():
			missing += 1
			print("  no route from the arrival to %s" % nodes[t])
			continue
		for k in path.size() - 1:
			var d := path[k].distance_to(path[k + 1])
			var steps := maxi(1, ceili(d / 0.25))
			for q in steps + 1:
				var p := path[k].lerp(path[k + 1], float(q) / steps)
				if not g.walkable(p) or _raw_block(p) != "":
					off += 1
	ok(missing == 0, "every door, stop and venue is reachable from the arrival (%d are not)" % missing)
	ok(off == 0, "every route sample is on walkable ground (%d are not)" % off)
	_report.append("routes: %d targets from the arrival; %d routes cached, %.1f ms of route search in all" % [targets.size(),
		People.ground().routes.size(), People.ground().route_ms])


## The sim's outdoor people at minute m: the street (COMMUTE and street spots) plus the outdoor venues.
func _sim_outdoor(day: int, m: float) -> int:
	var plans := sim.build_day(day)
	var occ := sim.occupancy(plans, m)
	var n: int = occ.street
	var pb: PackedInt32Array = occ.per_building
	for b in pb.size():
		if String(Data.BUILDINGS[b]["kind"]) in Data.OUTDOOR_KINDS:
			n += pb[b]
	return n


func test_counts() -> void:
	pp.set_budget(1000, 40, 32.0, 1000.0)
	for row: Array in MINUTES:
		var day: int = row[0]
		var m: float = row[1]
		pp.set_time(day, m)
		var c := pp.counts()
		var want := _sim_outdoor(day, m)
		var plans := sim.build_day(day)
		var occ := sim.occupancy(plans, m)
		ok(int(c.outdoor) == want, "%s: outdoor %d == the sim's %d" % [row[2], c.outdoor, want])
		ok(int(c.street) <= int(occ.street), "%s: the commuters are within the sim's street count" % row[2])
		ok(int(c.drawn) + int(c.aboard) + int(c.fading) == want, "%s: drawn %d + aboard %d + fading %d == outdoor %d" % [row[2], c.drawn, c.aboard, c.fading, want])
		ok(int(c.fading) <= want / 10 + 2, "%s: few are faded right out (%d)" % [row[2], c.fading])
		ok(int(c.pending) == 0 and int(c.unroutable) == 0, "%s: nobody pending (%d) or unroutable (%d)" % [row[2], c.pending, c.unroutable])
		var snap := pp.drawn_snapshot()
		var bad_state := 0
		var bad_ground := 0
		var bad_y := 0
		var first_bad := ""
		for id: int in snap:
			var st := sim.state_at(plans, id, m)
			var loc := int(st.get("location", -1))
			var outdoor := loc == Data.STREET or (loc >= 0 and String(Data.BUILDINGS[loc]["kind"]) in Data.OUTDOOR_KINDS)
			if id < 0 or id >= sim.count or not outdoor:
				bad_state += 1
			var o: Vector3 = snap[id].xf.origin
			var why := _raw_block(Vector2(o.x, o.z))
			if why != "" or not People.ground().walkable(Vector2(o.x, o.z)):
				bad_ground += 1
				if first_bad == "":
					first_bad = "%d (%s, %s) at %s: %s" % [id, sim.role_name(id), pp.info(id).get("trip", ""), o, why]
			if absf(o.y - People.ground().y_at(Vector2(o.x, o.z))) > 0.01:
				bad_y += 1
		ok(bad_state == 0, "%s: every drawn figure is a resident the sim puts outdoors (%d are not)" % [row[2], bad_state])
		ok(bad_ground == 0, "%s: every drawn figure stands on walkable ground (%d do not; first %s)" % [row[2], bad_ground, first_bad])
		ok(bad_y == 0, "%s: every figure stands at the ground's height (%d do not)" % [row[2], bad_y])
		_report.append("%s: sim street %d, outdoor %d; drawn %d, aboard %d, fading %d" % [row[2], occ.street, want, c.drawn, c.aboard, c.fading])


func test_walkers_move() -> void:
	pp.set_budget(1000, 40, 32.0, 1000.0)
	for m0: float in [450.0, 1020.0]:
		pp.set_time(1, m0)
		var before := {}
		for i in pp.drawn_ids():
			var inf := pp.info(i)
			if inf.get("trip", "") == "walk" and inf.get("mode", "") == "walk":
				before[i] = [float(inf.remaining_m), pp.position_of(i)]
		pp.set_time(1, m0 + 0.5)
		var closer := 0
		var worse := 0
		for i: int in before:
			var inf := pp.info(i)
			if not inf.has("remaining_m") or inf.get("trip", "") != "walk":
				continue
			if float(inf.remaining_m) < float(before[i][0]) - 0.05:
				closer += 1
			elif float(inf.remaining_m) > float(before[i][0]) + 1e-3:
				worse += 1
		ok(before.size() > 20, "minute %d: plenty of walkers (%d)" % [m0, before.size()])
		ok(worse == 0, "minute %d: no walker gets farther from its destination (%d do)" % [m0, worse])
		ok(closer >= before.size() * 0.9, "minute %d: the walkers get closer in half a minute (%d of %d)" % [m0, closer, before.size()])


func test_heights() -> void:
	var adult := People.RIG_HEIGHT * People.height_scale(35, false)
	var woman := People.RIG_HEIGHT * People.height_scale(35, true)
	ok(adult > 1.65 and adult < 1.75, "an adult man is about 1.70 m (%.3f)" % adult)
	ok(absf(woman / adult - 0.97) < 1e-4, "a woman is 0.97 of a man (%.3f m)" % woman)
	var five := People.RIG_HEIGHT * People.height_scale(5, false)
	var twelve := People.RIG_HEIGHT * People.height_scale(12, false)
	ok(absf(five / adult - 0.55) < 1e-4, "a five-year-old is 0.55 of an adult (%.3f m)" % five)
	ok(absf(twelve / adult - 0.76) < 1e-4, "a twelve-year-old is 0.76 of an adult (%.3f m)" % twelve)
	ok(People.height_scale(80, false) < People.height_scale(50, false), "the old are a little shorter")
	ok(absf(People.head_scale(1) - 1.46) < 1e-6 and absf(People.head_scale(30) - 1.0) < 1e-6, "upstream's head curve")
	# every drawn figure carries its resident's scale
	pp.set_time(1, 450.0)
	var snap := pp.drawn_snapshot()
	var bad := 0
	for id: int in snap:
		var s: float = (snap[id].xf as Transform3D).basis.get_scale().y
		if absf(s - People.height_scale(sim.age[id], sim.gender[id] == 1)) > 1e-4:
			bad += 1
	ok(bad == 0, "every drawn figure's scale is its resident's height scale (%d are not)" % bad)
	_report.append("heights: man %.2f m, woman %.2f m, age 12 %.2f m, age 5 %.2f m (the player's child is 1.30 m)" % [adult, woman, twelve, five])


func test_looks() -> void:
	var roles := {}
	var colors := {}
	for i in sim.count:
		var lk := pp.look_of(i)
		roles[lk.role] = true
		colors["%s/%s" % [lk.colors[1].to_html(), lk.colors[2].to_html()]] = true
		ok(int(lk.hair) >= 0 and int(lk.hair) <= 6, "hair style in range for %d" % i)
	ok(roles.size() == 20, "all 20 roles have a look (%d)" % roles.size())
	ok(colors.size() >= 60, "the town wears many outfits (%d top/bottom pairs)" % colors.size())
	ok(People.ROLE_LOOKS.size() == 20, "a look table for each of the 20 roles")
	var nurse := -1
	var doc := -1
	for i in sim.count:
		if nurse < 0 and sim.role_name(i) == "medical-nurse":
			nurse = i
		if doc < 0 and sim.role_name(i) == "medical-doc":
			doc = i
	ok(int(pp.look_of(doc).flags) & (1 << People.F_COAT) != 0, "a doctor wears the white coat")
	ok((pp.look_of(nurse).colors[2] as Color).is_equal_approx(Color("#eef1ef")), "a nurse wears white trousers")


func test_inside_not_drawn() -> void:
	pp.set_budget(1000, 40, 32.0, 1000.0)
	pp.set_time(1, 600.0)
	var plans := sim.build_day(1)
	var drawn := {}
	for i in pp.drawn_ids():
		drawn[i] = true
	var inside_drawn := 0
	var inside := 0
	for i in sim.count:
		var st := sim.state_at(plans, i, 600.0)
		var loc := int(st.location)
		if loc != Data.STREET and not String(Data.BUILDINGS[loc]["kind"]) in Data.OUTDOOR_KINDS:
			inside += 1
			if drawn.has(i):
				inside_drawn += 1
	ok(inside > 700, "most of the town is indoors at 10:00 (%d)" % inside)
	ok(inside_drawn == 0, "nobody inside a building is drawn (%d are)" % inside_drawn)
	var c := pp.counts()
	var total := 0
	for k: String in c.indoors:
		total += int(c.indoors[k])
	ok(total == inside, "counts() reports the indoor occupancy (%d == %d)" % [total, inside])


func test_determinism() -> void:
	var other := People.new()
	root.add_child(other)
	other.sync_routes = true
	other.setup(sim)
	for row: Array in MINUTES:
		pp.set_budget(160, 40, 32.0, 110.0)
		other.set_budget(160, 40, 32.0, 110.0)
		pp.focus(Vector3(-52, 0.125, 3.6))
		other.focus(Vector3(-52, 0.125, 3.6))
		pp.set_time(int(row[0]), float(row[1]) + 3.3)
		other.set_time(7, 300.0)
		other.set_time(int(row[0]), float(row[1]) + 3.3)
		var a := pp.drawn_snapshot()
		var b := other.drawn_snapshot()
		var same := a.size() == b.size()
		for id: int in a:
			if not b.has(id) or not (a[id].xf as Transform3D).is_equal_approx(b[id].xf) or not (a[id].custom as Color).is_equal_approx(b[id].custom):
				same = false
		ok(same, "%s: two instances with different histories draw the same (%d / %d)" % [row[2], a.size(), b.size()])
	other.queue_free()


func test_picking() -> void:
	pp.set_budget(160, 40, 32.0, 110.0)
	pp.focus(Vector3(-52, 0.125, 3.6))
	pp.set_time(1, 1020.0)
	var snap := pp.drawn_snapshot()
	var tried := 0
	var hits := 0
	for id: int in snap:
		if tried >= 25:
			break
		var o: Vector3 = snap[id].xf.origin
		var h := People.RIG_HEIGHT * People.height_scale(sim.age[id], sim.gender[id] == 1)
		var chest := o + Vector3(0, h * 0.6, 0)
		var eye := chest + Vector3(0.0, 1.2, 4.5)
		# skip figures with another one between them and the eye (the ray comes from 4.5 m to the south)
		var blocked := false
		for other: int in snap:
			var q: Vector3 = snap[other].xf.origin
			if other != id and absf(q.x - o.x) < 1.0 and q.z - o.z > -1.0 and q.z - o.z < 5.0:
				blocked = true
		if blocked:
			continue
		tried += 1
		var got := pp.pick(eye, chest - eye)
		if got == id:
			hits += 1

	ok(tried >= 10, "enough isolated figures to pick (%d)" % tried)
	ok(hits == tried, "the ray at a figure's chest picks that resident (%d of %d)" % [hits, tried])
	ok(pp.pick(Vector3(0, 50, 0), Vector3(0, 1, 0)) == -1, "a ray into the sky picks nobody")
	var some: int = snap.keys()[0]
	ok(pp.nearest(snap[some].xf.origin, 0.01) == some, "nearest() finds the resident standing there")


func test_info() -> void:
	pp.set_budget(1000, 40, 32.0, 1000.0)
	pp.set_time(1, 450.0)
	var walker := -1
	for i in pp.drawn_ids():
		var inf := pp.info(i)
		if inf.get("trip", "") == "walk" and inf.get("mode", "") == "walk":
			walker = i
			break
	ok(walker >= 0, "a walker to follow at 07:30")
	var inf := pp.info(walker)
	for key: String in ["name", "role", "age", "state", "where", "from", "to", "destination", "progress", "remaining_m", "eta_minute", "mode", "position"]:
		ok(inf.has(key), "info() has %s" % key)
	ok(String(inf.state) == "COMMUTE", "the walker is commuting")
	ok(pp.route_of(walker).size() >= 2, "route_of() gives the commute's polyline")
	var p := pp.position_of(walker)
	var pts := pp.route_of(walker)
	var on := INF
	for k in pts.size() - 1:
		on = minf(on, Geometry3D.get_closest_point_to_segment(p, pts[k], pts[k + 1]).distance_to(p))
	ok(on < 0.6, "the walker is on its route (%.2f m)" % on)
	ok(String(pp.info(walker, "zh-CN").name) != String(inf.name), "names follow the locale")
	var plans := sim.build_day(1)
	var indoor := -1
	for i in sim.count:
		if int(sim.state_at(plans, i, 450.0).location) == sim.home[i]:
			indoor = i
			break
	ok(pp.position_of(indoor) != Vector3.INF and String(pp.info(indoor).mode) == "inside", "an indoor resident is at its door, inside")
	_report.append("follow: %s (%s) %s -> %s, %.0f m to go" % [inf.name, inf.role, inf.from, inf.to, inf.remaining_m])


func test_budgets() -> void:
	for prof: String in ["ipad", "tv"]:
		pp.budget_profile(prof)
		var cap := 160 if prof == "ipad" else 96
		for spot: Vector3 in [Vector3(-52, 0.125, 3.6), Vector3(0, 0.1, 30), Vector3(48, 0.1, -40)]:
			pp.focus(spot)
			for m: float in [450.0, 1020.0]:
				pp.set_time(1, m)
				var st := pp.stats()
				ok(int(st.drawn) <= cap, "%s at %s %d: at most %d figures (%d)" % [prof, spot, m, cap, st.drawn])
				ok(int(st.near) <= pp.max_near, "%s: at most %d near figures (%d)" % [prof, pp.max_near, st.near])
				ok(pp.draw_calls() <= 2, "%s: two draw calls at most (%d)" % [prof, pp.draw_calls()])
				var snap := pp.drawn_snapshot()
				var far := 0
				var near_far := 0
				for id: int in snap:
					var d := (snap[id].xf.origin as Vector3).distance_to(spot)
					if d > pp.far_m + 0.01:
						far += 1
					if bool(snap[id].near) and d > pp.near_m + 0.01:
						near_far += 1
				ok(far == 0, "%s: nobody drawn beyond %.0f m (%d)" % [prof, pp.far_m, far])
				ok(near_far == 0, "%s: no full figure beyond %.0f m (%d)" % [prof, pp.near_m, near_far])
	var near_mesh := People.figure_mesh(false)
	var far_mesh := People.figure_mesh(true)
	var tn := (near_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var tf := (far_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	ok(tn < 2400 and tf < 400, "figure triangles: near %d, far %d" % [tn, tf])
	_report.append("meshes: near figure %d triangles (every look feature included), far %d; draw calls 2" % [tn, tf])


func test_timing() -> void:
	for prof: String in ["ipad", "tv"]:
		pp.budget_profile(prof)
		pp.sync_routes = false
		pp.focus(Vector3(-52, 0.125, 3.6))
		for m0: float in [450.0, 1020.0]:
			pp.set_time(1, m0)
			var total := 0.0
			var worst := 0.0
			var n := 240
			for f in n:
				pp.focus(Vector3(-52 + f * 0.02, 0.125, 3.6))
				var t := Time.get_ticks_usec()
				pp.set_time(1, m0 + f / 60.0)
				var dt := (Time.get_ticks_usec() - t) / 1000.0
				total += dt
				worst = maxf(worst, dt)
			var st := pp.stats()
			ok(total / n < FRAME_MS_BOUND, "%s at %d: people update %.3f ms a frame on average (bound %.1f)" % [prof, m0, total / n, FRAME_MS_BOUND])
			_report.append("timing %s %s: people update avg %.3f ms, worst %.3f ms (%d drawn, %d near, %d outdoors, %d draw calls)" % [
				prof, "07:30" if m0 == 450.0 else "17:00", total / n, worst, st.drawn, st.near, st.active, st.draw_calls])
	pp.sync_routes = true
