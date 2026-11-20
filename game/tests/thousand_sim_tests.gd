## Headless parity tests for Thousand Town's resident simulation and clock (core/thousand_sim.gd,
## thousand_sim_data.gd, thousand_clock.gd) against fixtures that upstream's own code produced in Node
## (scripts/thousand_town/sim_fixtures.mjs -> tests/thousand/fixtures/*.json).
##   godot --headless --path game -s res://tests/thousand_sim_tests.gd
## Exact: the random numbers, the roster, the templates, the plans of all 1000 residents for days 1, 6, 7
## and 42, the states and occupancy at the sample minutes. Within 1e-6: lighting factors and window rules,
## sun and moon, transit, events. Also reports how long a day of plans takes to build.
extends SceneTree

const Data := preload("res://scripts/core/thousand_sim_data.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const Sim := preload("res://scripts/core/thousand_sim.gd")

const FIXTURES := "res://tests/thousand/fixtures/"
const TOL := 1e-6
const UP := Clock.UPSTREAM_SECONDS_PER_SIM_MINUTE
const MAX_FAIL_LINES := 60

var _checks := 0
var _failures := 0
var _sim: Sim
var _days := {}
var _roster_ms := 0.0


func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	_sim = Sim.new()
	_roster_ms = (Time.get_ticks_usec() - t0) / 1000.0
	for t in ["test_rng", "test_clock", "test_roster", "test_names", "test_templates", "test_plans", "test_incremental",
			"test_occupancy", "test_lighting", "test_sky", "test_transit", "test_events", "test_wrappers", "test_timing"]:
		call(t)
	print("THOUSAND SIM TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		if _failures <= MAX_FAIL_LINES:
			print("FAIL: ", msg)


func _near(a: float, b: float, msg: String, tol: float = TOL) -> void:
	_ok(absf(a - b) <= tol, "%s: %.12f vs %.12f" % [msg, a, b])


func _angle_near(a: float, b: float, msg: String) -> void:
	var d := absf(fposmod(a - b + PI, TAU) - PI)
	_ok(d <= TOL, "%s: %.12f vs %.12f" % [msg, a, b])


func _load(name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(FIXTURES + name)
	var data: Variant = JSON.parse_string(text)
	_ok(data is Dictionary, "fixture %s loads" % name)
	return data if data is Dictionary else {}


func _plans(day: int) -> Sim.DayPlans:
	if not _days.has(day):
		_days[day] = _sim.build_day(day)
	return _days[day]


func _column(columns: Array, name: String) -> int:
	return columns.find(name)


# Fixture location and substate lists -> the port's ids.
func _location_map(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n: String in names:
		out.append(Data.STREET if n == "street" else int(_sim.building_index.get(n, -99)))
	return out


func _substate_map(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n: String in names:
		if n == "indoor":
			out.append(Data.INDOOR)
		elif n.begins_with("indoor-"):
			out.append(Data.INDOOR + Data.substate_id(n.substr(7)))
		else:
			out.append(Data.substate_id(n))
	return out


func _building(id: Variant) -> int:
	return -1 if id == null else int(_sim.building_index[id])

# ---------------------------------------------------------------- random numbers


func test_rng() -> void:
	var fx := _load("rng.json")
	for entry: Dictionary in fx["mulberry32"]:
		var a := Data.Rng.new(int(entry["seed"]))
		var b := Data.Rng.new(int(entry["seed"]))
		var same := true
		for expected: float in entry["outputs"]:
			if a.next_u32() != int(expected) or b.next() != expected / 4294967296.0:
				same = false
		_ok(same, "mulberry32 seed %d: 64 outputs" % int(entry["seed"]))
	for entry: Dictionary in fx["hash32"]:
		_ok(Data.hash32(entry["key"]) == int(entry["hash"]), "hash32(%s)" % entry["key"])
	for entry: Dictionary in fx["variants"]:
		_ok(_sim.variant[_sim.index_of(entry["id"])] == int(entry["variant"]), "variant of %s" % entry["id"])
	for entry: Dictionary in fx["dayRng"]:
		var rng := Data.Rng.new(Data.hash32("%d:%s:%d" % [Data.SEED, entry["id"], int(entry["day"])]))
		var same := true
		for expected: float in entry["outputs"]:
			if rng.next_u32() != int(expected):
				same = false
		_ok(same, "day rng of %s day %d" % [entry["id"], int(entry["day"])])
	# The 32-bit multiply at its edges, and rounding of halves.
	_ok(Data.imul32(0xFFFFFFFF, 0xFFFFFFFF) == 1 and Data.imul32(0x80000000, 2) == 0 and Data.imul32(65536, 65536) == 0
		and Data.imul32(123456789, 987654321) == ((123456789 * 987654321) & 0xFFFFFFFF), "imul32 wraps to 32 bits")
	_ok(Data.js_round(2.5) == 3 and Data.js_round(-2.5) == -2 and Data.js_round(-0.4) == 0 and Data.js_round(-0.6) == -1, "js_round rounds halves up")

# ---------------------------------------------------------------- clock


func test_clock() -> void:
	var fx := _load("clock.json")
	var c: Dictionary = fx["constants"]
	_ok(int(c["minutesPerDay"]) == Clock.MINUTES_PER_DAY and int(c["daysPerWeek"]) == Clock.DAYS_PER_WEEK
		and float(c["secondsPerSimMinute"]) == UP, "clock constants")
	_ok(Clock.SECONDS_PER_SIM_MINUTE == 1.0 and Clock.UNIT_M == 0.5, "Lantern Lane runs one sim minute per second, one unit is half a metre")
	var anchors: Dictionary = c["anchors"]
	var anchors_ok := anchors.size() == Clock.ANCHORS.size()
	for key: String in anchors:
		anchors_ok = anchors_ok and int(anchors[key]) == int(Clock.ANCHORS.get(key, -1))
	_ok(anchors_ok, "day anchors")
	_ok(c["dayTypes"] == Data.DAY_TYPES, "day type names")
	for i in 3:
		_ok(Data.SHIFTS[i] == Vector2i(int(c["shifts"][i]["start"]), int(c["shifts"][i]["end"])), "shift %d" % i)
	for row: Array in fx["elapsed"]:
		var s: float = row[0]
		_ok(Clock.total_minutes(s, UP) == int(row[1]) and Clock.minute_of_day(s, UP) == int(row[2])
			and Clock.day_index(s, UP) == int(row[3]), "elapsed %.3f s" % s)
	for row: Array in fx["days"]:
		var day := int(row[0])
		_ok(Clock.dow(day) == int(row[1]) and Data.DAY_TYPES[Clock.day_type(day)] == row[2]
			and Clock.is_weekend(day) == row[3] and Clock.week_index(day) == int(row[4]), "day %d" % day)
	for row: Array in fx["minutes"]:
		var m: float = row[0]
		_near(Clock.daylight(m), row[1], "daylight(%.3f)" % m, 1e-9)
		_ok(Clock.is_night(m) == row[2] and Clock.format_minute(m) == row[3], "night and format at %.3f" % m)
	for row: Array in fx["shiftWindow"]:
		_ok(Clock.shift_window(floori(row[0])) == Vector2i(int(row[1]), int(row[2])), "shift window %s" % str(row[0]))
	_ok(Clock.seconds_at(2, 30.0) == 1470.0 and Clock.minute_of_day(Clock.seconds_at(2, 30.0)) == 30
		and Clock.day_index(Clock.seconds_at(2, 30.0)) == 2, "Lantern Lane seconds for (day, minute)")
	_ok(Clock.day_type(Clock.START_DAY) == Data.DAY_WEEKDAY and Clock.START_MINUTE == 480, "the clock starts at 08:00 on a Monday")

# ---------------------------------------------------------------- roster


func test_roster() -> void:
	var fx := _load("roster.json")
	_ok(int(fx["seed"]) == _sim.town_seed and _sim.count == 1000 and Data.CENSUS.size() == 20, "seed, 1000 residents, 20 roles")
	var by_role: Dictionary = fx["stats"]["byRole"]
	var total := 0
	for row: Dictionary in Data.CENSUS:
		total += int(row["count"])
		_ok(int(by_role.get(row["role"], -1)) == int(row["count"]), "census count of %s" % row["role"])
	_ok(total == 1000 and by_role.size() == 20, "the census sums to 1000")
	_ok(Data.SUBSTATES.size() == Data.INDOOR and Data.ZH_SURNAMES.length() == 100, "table sizes")

	var bc: Array = fx["buildingColumns"]
	var rows: Array = fx["buildings"]
	_ok(rows.size() == Data.BUILDINGS.size() and rows.size() == 31 and Data.STREET == 31, "31 ledger buildings")
	for b in mini(rows.size(), Data.BUILDINGS.size()):
		var row: Array = rows[b]
		var mine: Dictionary = Data.BUILDINGS[b]
		var type: Variant = row[_column(bc, "type")]
		var annex: Variant = row[_column(bc, "annexOf")]
		var annex_clinic: Variant = row[_column(bc, "annexClinic")]
		_ok(mine["id"] == row[0] and mine["kind"] == row[1] and mine["type"] == (type if type != null else "")
			and int(mine["cap"]) == int(row[_column(bc, "capacity")]) and Data.POLICIES[mine["open"]] == row[_column(bc, "open")]
			and mine["annex_of"] == (annex if annex != null else "") and mine["clinic"] == (annex_clinic if annex_clinic != null else ""),
			"building %s" % str(row[0]))
		_ok(_sim.workers[b] == int(row[_column(bc, "workers")]) and _sim.housed[b] == int(row[_column(bc, "residents")])
			and _sim.venue_use[b] == int(row[_column(bc, "venueUse")]) and _sim.homes[b].size() == _sim.housed[b],
			"workers, residents and leisure seats of %s" % str(row[0]))
	var kinds: Dictionary = fx["kinds"]
	var kinds_ok := kinds.size() == _sim.kinds.size()
	for kind: String in kinds:
		kinds_ok = kinds_ok and _sim.kinds.has(kind) and Data.BUILDINGS[_sim.kinds[kind]]["id"] == kinds[kind]
	_ok(kinds_ok, "first building of every kind")

	var rc: Array = fx["residentColumns"]
	var residents: Array = fx["residents"]
	_ok(residents.size() == _sim.count, "roster size")
	var col := {}
	for name: String in rc:
		col[name] = rc.find(name)
	for i in mini(residents.size(), _sim.count):
		var r: Array = residents[i]
		var leisure: Variant = r[col["leisureVenue"]]
		var want_leisure := Sim.LEISURE_NONE if leisure == null else (Sim.LEISURE_HOME if leisure == "HOME" else _building(leisure))
		var work_kind: Variant = r[col["workplaceKind"]]
		var mine_kind: Variant = null if _sim.workplace[i] < 0 else Data.BUILDINGS[_sim.workplace[i]]["kind"]
		var problems := PackedStringArray()
		if _sim.ids[i] != r[col["id"]]: problems.append("id")
		if _sim.ordinal[i] != int(r[col["ordinal"]]): problems.append("ordinal")
		if _sim.role_name(i) != r[col["role"]]: problems.append("role")
		if _sim.age[i] != int(r[col["age"]]): problems.append("age")
		if ("M" if _sim.gender[i] == 0 else "F") != r[col["gender"]]: problems.append("gender")
		if _sim.birth_month[i] != int(r[col["birthMonth"]]): problems.append("birth month")
		if roundi(_sim.pace[i] * 100.0) != int(r[col["pace100"]]): problems.append("pace")
		if roundi(_sim.sociability[i] * 100.0) != int(r[col["sociability100"]]): problems.append("sociability")
		if _sim.home[i] != _building(r[col["home"]]): problems.append("home")
		if _sim.workplace[i] != _building(r[col["workplace"]]): problems.append("workplace")
		if mine_kind != work_kind: problems.append("workplace kind")
		if _sim.shift_index[i] != int(r[col["shiftIndex"]]): problems.append("shift")
		if _sim.clinic[i] != _building(r[col["clinic"]]): problems.append("clinic")
		if _sim.duty_post[i] != _building(r[col["dutyPost"]]): problems.append("duty post")
		if Data.POLICIES[_sim.venue_policy[i]] != r[col["venuePolicy"]]: problems.append("venue policy")
		if _sim.leisure_venue[i] != want_leisure: problems.append("leisure venue")
		if _sim.variant[i] != int(r[col["variant"]]): problems.append("variant")
		if _sim.name_zh[i] != r[col["name"]]: problems.append("name")
		if _sim.pinyin[i] != r[col["pinyin"]]: problems.append("pinyin")
		_ok(problems.is_empty(), "resident %s: %s" % [str(r[0]), ", ".join(problems)])
	# pace is exactly a whole number of hundredths, as upstream's Math.round(x * 100) / 100
	var pace_ok := true
	for i in _sim.count:
		pace_ok = pace_ok and _sim.pace[i] == roundi(_sim.pace[i] * 100.0) / 100.0 and absf(_sim.pace[i]) <= 0.2
	_ok(pace_ok, "pace is in hundredths within +-0.2")
	var other := Sim.new()
	_ok(other.name_zh == _sim.name_zh and other.home == _sim.home and other.variant == _sim.variant, "the roster is the same on every build")
	_ok(_sim.index_of("office-037") == 40 + 80 + 50 + 70 + 36 and _sim.index_of("nobody-001") == -1, "index_of")
	var one := _sim.resident(0)
	_ok(one["id"] == "preschooler-001" and one["role"] == "preschooler" and one["name_zh"] == _sim.name_zh[0], "resident() for the panel")


func test_names() -> void:
	var zh := {}
	for i in _sim.count:
		zh[_sim.name_of(i, "zh-CN")] = true
	_ok(zh.size() == 1000 and _sim.name_of(5, "zh_CN") == _sim.name_zh[5], "1000 different zh-CN names (upstream's)")
	_ok(Data.zh_name_characters().length() > 150, "the zh-CN name character set for the font subset")
	var other := Sim.new()
	for locale: String in ["en", "ja", "es", "fr", "de"]:
		var pools: Dictionary = Data.NAME_POOLS[locale]
		var pool_ok := true
		var seen := {}
		for key: String in ["male", "female", "family"]:
			var pool: Array = pools[key]
			pool_ok = pool_ok and pool.size() == Data.NAME_POOL_SIZE
			for n: String in pool:
				pool_ok = pool_ok and n.strip_edges() == n and n != "" and not seen.has(n)
				seen[n] = true
		_ok(pool_ok, "%s pools: 32 given names per gender and 32 family names, none twice" % locale)
		var names := {}
		var stable := true
		for i in _sim.count:
			var n := _sim.name_of(i, locale)
			names[n] = true
			stable = stable and n == other.name_of(i, locale) and n.contains(" ")
		_ok(names.size() == 1000, "1000 different %s names (%d)" % [locale, names.size()])
		_ok(stable, "%s names are stable" % locale)
	_ok(_sim.name_of(0, "en_US") == _sim.name_of(0, "en") and _sim.name_of(0, "xx") == _sim.name_of(0, "en"), "region suffix ignored, unknown locale gets English")
	var ja_first: String = _sim.name_of(0, "ja").split(" ")[0]
	_ok(Data.NAME_POOLS["ja"]["family"].has(ja_first), "Japanese names put the family name first")

# ---------------------------------------------------------------- templates


func test_templates() -> void:
	var fx := _load("templates.json")
	_ok(fx["states"] == Data.STATES, "state names in upstream's order")
	var names: Array = (fx["hashes"] as Dictionary).keys()
	names.sort()
	var mine := Data.TEMPLATES.duplicate()
	mine.sort()
	_ok(names == mine, "the 23 templates")
	var role_template: Dictionary = fx["roleTemplate"]
	var map_ok := role_template.size() == Data.ROLE_TEMPLATE.size()
	for role: String in role_template:
		map_ok = map_ok and Data.TEMPLATES[Data.ROLE_TEMPLATE.get(role, 0)] == role_template[role]
	_ok(map_ok, "role -> template map")
	var token_of := PackedInt32Array()
	for t: String in Data.TOKENS:
		token_of.append((fx["tokens"] as Array).find(t))
	var sub_of := PackedInt32Array()
	var subs_known := true
	for s: String in Data.SUBSTATES:
		sub_of.append((fx["substates"] as Array).find(s))
		subs_known = subs_known and sub_of[sub_of.size() - 1] >= 0
	_ok(subs_known and (fx["substates"] as Array).size() == Data.SUBSTATES.size(), "the substate table is upstream's set")
	var shift_start := {"none": -1, "early": 480, "mid": 960, "night": 0}
	var contexts: Array = fx["contexts"]
	for id in Data.TEMPLATES.size():
		var name: String = Data.TEMPLATES[id]
		var hashes: Array = fx["hashes"].get(name, [])
		var bad := PackedStringArray()
		for ci in contexts.size():
			var c: Dictionary = contexts[ci]
			var h := 0x811C9DC5
			for v in 100:
				var segs := Data.template(id, v, shift_start[c["shift"]], int(c["ordinal"]), c["role"],
					Data.DAY_TYPES.find(c["dayType"]), c["halfDay"])
				for k in segs.size():
					var x := segs[k]
					if k % 5 == 3:
						x = token_of[x]
					elif k % 5 == 4:
						x = sub_of[x]
					h = Data.imul32(h ^ x, 0x01000193)
				h = Data.imul32(h ^ 0xFFFF, 0x01000193)
			if ci >= hashes.size() or h != int(hashes[ci]):
				bad.append(str(c))
		_ok(bad.is_empty(), "template %s, variants 0..99 in %d contexts; differs in: %s" % [name, contexts.size(), "; ".join(bad)])
	# Each role's plain weekday template.
	_ok(Data.template_for("medical-nurse", 2, "hospital", Data.POLICY_DAILY, Data.DAY_WEEKDAY, false) == Data.T_SHIFT_NIGHT
		and Data.template_for("worker", -1, "market", Data.POLICY_DAILY, Data.DAY_SUNDAY, false) == Data.T_MARKET_EARLY
		and Data.template_for("office", -1, "tower", Data.POLICY_WEEKDAY, Data.DAY_SATURDAY, false) == Data.T_WEEKEND
		and Data.template_for("clerk", -1, "bank", Data.POLICY_SAT_AM, Data.DAY_SATURDAY, false) == Data.T_CLERK
		and Data.template_for("worker", -1, "workshop", Data.POLICY_WEEKDAY, Data.DAY_SUNDAY, true) == Data.T_DUTY, "template_for overrides")

# ---------------------------------------------------------------- plans


func test_plans() -> void:
	var fx := _load("plans.json")
	var loc := _location_map(fx["locations"])
	var sub := _substate_map(fx["substates"])
	_ok(not loc.has(-99) and fx["states"] == Data.STATES, "plan tables")
	for key: String in fx["days"]:
		var day := int(key)
		var entry: Dictionary = fx["days"][key]
		var plans := _plans(day)
		_ok(Data.DAY_TYPES[plans.day_type] == entry["dayType"] and plans.built == 1000 and plans.first.size() == 1001, "day %d is a %s" % [day, entry["dayType"]])
		var posts := PackedStringArray()
		for b in _sim.duty_posts(plans.day_type):
			posts.append(Data.BUILDINGS[b]["id"])
		_ok(Array(posts) == entry["dutyPosts"], "duty posts on day %d" % day)
		var want: Array = entry["segments"]
		var duty: Array = entry["duty"]
		var changes: Array = entry["stateChanges"]
		var same := 0
		for i in _sim.count:
			var w: Array = want[i]
			var from := plans.first[i] * 5
			var n := plans.first[i + 1] * 5 - from
			var equal := n == w.size()
			if equal:
				for k in range(0, n, 5):
					if plans.segs[from + k] != int(w[k]) or plans.segs[from + k + 1] != int(w[k + 1]) or plans.segs[from + k + 2] != int(w[k + 2]) \
							or plans.segs[from + k + 3] != loc[int(w[k + 3])] or plans.segs[from + k + 4] != sub[int(w[k + 4])]:
						equal = false
						break
			var want_duty := -1 if int(duty[i]) < 0 else loc[int(duty[i])]
			equal = equal and plans.duty[i] == want_duty and _sim.state_changes(plans, i) == int(changes[i])
			if equal:
				same += 1
			_ok(equal, "plan of %s on day %d" % [_sim.ids[i], day])
		var invalid := 0
		for i in _sim.count:
			if not _sim.validate(plans, i).is_empty():
				invalid += 1
		_ok(invalid == (entry["invalid"] as Array).size() and invalid == 0, "every plan of day %d validates (%d invalid)" % [day, invalid])
		@warning_ignore("integer_division")
		print("  day %d (%s): %d of 1000 plans identical, %d segments" % [day, entry["dayType"], same, plans.segs.size() / 5])
	# More days by hash: weekdays, the following weekends (the duty roster turns with the week), far days.
	var sub_hash := PackedInt64Array()
	for id in Data.INDOOR * 2:
		sub_hash.append(Data.hash32(Data.substate_name(id)))
	var sweep: Dictionary = fx["hashes"]
	var swept := 0
	for key: String in sweep:
		var day := int(key)
		var plans := _plans(day) if (fx["days"] as Dictionary).has(key) else _sim.build_day(day)
		var h := 0x811C9DC5
		for i in _sim.count:
			for at in range(plans.first[i] * 5, plans.first[i + 1] * 5, 5):
				h = ((h ^ plans.segs[at]) * 0x01000193) & 0xFFFFFFFF
				h = ((h ^ plans.segs[at + 1]) * 0x01000193) & 0xFFFFFFFF
				h = ((h ^ plans.segs[at + 2]) * 0x01000193) & 0xFFFFFFFF
				h = ((h ^ plans.segs[at + 3]) * 0x01000193) & 0xFFFFFFFF
				h = ((h ^ sub_hash[plans.segs[at + 4]]) * 0x01000193) & 0xFFFFFFFF
			h = ((h ^ (plans.duty[i] if plans.duty[i] >= 0 else 0xFFFF)) * 0x01000193) & 0xFFFFFFFF
		swept += 1
		_ok(h == int(sweep[key]), "plans of day %d by hash (%s)" % [day, Data.DAY_TYPES[plans.day_type]])
	print("  %d days of plans identical by hash" % swept)
	# The validator rejects what it should.
	var broken := _sim.build_day(1)
	broken.segs[broken.first[3] * 5 + 1] += 7
	_ok(not _sim.validate(broken, 3).is_empty() and _sim.validate(broken, 4).is_empty(), "validate reports an overlap")
	var p := _sim.plan(_plans(1), 0)
	_ok(p.size() == _sim.segment_count(_plans(1), 0) and p[0]["start"] == 0 and p[p.size() - 1]["end"] == 1440, "plan() covers the day")


func test_incremental() -> void:
	var whole := _plans(7)
	var parts := _sim.begin_day(7)
	var steps := 0
	while not _sim.build_more(parts, 137):
		steps += 1
	_ok(steps == 7 and parts.segs == whole.segs and parts.first == whole.first and parts.duty == whole.duty, "building a day in parts gives the same plans")
	var again := _sim.build_day(42)
	_sim.build_day(3)
	_ok(again.segs == _plans(42).segs and _sim.build_day(42).segs == again.segs, "a day's plans do not depend on what was built before")
	_ok(Sim.new().build_day(6).segs == _plans(6).segs, "another simulation builds the same day")

# ---------------------------------------------------------------- states and occupancy


func test_occupancy() -> void:
	var fx := _load("occupancy.json")
	var loc := _location_map(fx["locations"])
	var sub := _substate_map(fx["substates"])
	for s: Dictionary in fx["samples"]:
		var day := int(s["day"])
		var minute := float(s["minute"])
		var plans := _plans(day)
		var label := "day %d %s" % [day, Clock.format_minute(minute)]
		var occ := _sim.occupancy(plans, minute)
		var want: Dictionary = s["occupancy"]
		var per: Dictionary = want["perBuilding"]
		var per_ok := true
		for b in _sim.building_count:
			per_ok = per_ok and occ["per_building"][b] == int(per.get(Data.BUILDINGS[b]["id"], 0))
		var states_ok := true
		for k in Data.STATES.size():
			states_ok = states_ok and occ["by_state"][k] == int(want["byState"].get(Data.STATES[k], 0))
		_ok(occ["street"] == int(want["street"]) and occ["missing"] == int(want["missing"]), "%s: %d on the street" % [label, int(want["street"])])
		_ok(per_ok, "%s: occupancy per building" % label)
		_ok(states_ok, "%s: occupancy per state" % label)

		var rows: Array = s["states"]
		var wrong := 0
		for i in _sim.count:
			var at := _sim.state_at(plans, i, minute)
			var r: Array = rows[i]
			if at.is_empty() or at["state"] != int(r[0]) or at["location"] != loc[int(r[1])] or at["substate"] != sub[int(r[2])] \
					or at["state_since"] != int(r[3]) or at["until_minute"] != int(r[4]):
				wrong += 1
		_ok(wrong == 0, "%s: state_at of all residents (%d differ)" % [label, wrong])

		var view := _sim.sample(plans, minute)
		_ok(view["night"] == s["night"] and view["street"] == occ["street"] and view["by_state"] == occ["by_state"]
			and view["per_building"] == occ["per_building"] and view["missing"] == 0, "%s: sample agrees with occupancy" % label)
		var f: Array = s["factors"]
		var mf: Dictionary = view["factors"]
		_ok(absf(mf["minute"] - f[0]) <= TOL and absf(mf["daylight"] - f[1]) <= TOL and absf(mf["lamps"] - f[2]) <= TOL
			and absf(mf["dusk"] - f[3]) <= TOL and absf(mf["windows"] - f[4]) <= TOL, "%s: lighting factors" % label)
		var heading: Dictionary = s["streetByDestination"]
		var heading_ok := true
		for b in _sim.building_count:
			heading_ok = heading_ok and view["street_by_destination"][b] == int(heading.get(Data.BUILDINGS[b]["id"], 0))
		_ok(heading_ok and view["street_by_destination"][Data.STREET] == int(heading.get("street", 0)), "%s: walkers by destination" % label)
		var outdoor: Dictionary = s["outdoor"]
		var buildings: Array = s["buildings"]
		for b in _sim.building_count:
			var w: Dictionary = buildings[b]
			var mine: Dictionary = view["buildings"][b]
			var problems := PackedStringArray()
			if mine["id"] != w["id"]: problems.append("id")
			var present: PackedInt32Array = mine["present"]
			var want_present: Array = w["present"]
			var present_ok: bool = present.size() == want_present.size() and mine["count"] == present.size()
			if present_ok:
				for k in present.size():
					if present[k] != int(want_present[k]):
						present_ok = false
						break
			if not present_ok: problems.append("present")
			for k in Data.STATES.size():
				if mine["by_state"][k] != int(w["byState"].get(Data.STATES[k], 0)): problems.append("by state " + Data.STATES[k])
			if mine["open"] != w["open"]: problems.append("open")
			if mine["awake"] != int(w["awake"]): problems.append("awake")
			if mine["working"] != int(w["working"]): problems.append("working")
			if mine["staff"] != int(w["staff"]): problems.append("staff")
			if mine["visitors"] != int(w["visitors"]): problems.append("visitors")
			if mine["home_count"] != int(w["homeCount"]): problems.append("home count")
			if absf(mine["door_open"] - w["doorOpen"]) > TOL: problems.append("door")
			if absf(mine["activity_light"] - w["lightLevel"]) > TOL: problems.append("activity light")
			var l: Array = w["lighting"]
			if mine["open"] != l[0] or mine["count"] != int(l[1]) or mine["awake"] != int(l[2]): problems.append("lighting inputs")
			if absf(mine["light"] - l[3]) > TOL: problems.append("light %.9f vs %.9f" % [mine["light"], l[3]])
			if mine["max_panes"] != int(l[4]): problems.append("max panes")
			if absf(mine["entry"] - l[5]) > TOL or absf(mine["facade"] - l[6]) > TOL or absf(mine["decoration"] - l[7]) > TOL: problems.append("entry, facade or decoration")
			if mine["outdoor"] != outdoor.has(w["id"]):
				problems.append("outdoor")
			elif mine["outdoor"]:
				var o: Array = outdoor[w["id"]]
				var shown: int = mine["count"] if mine["open"] else 0
				if shown != int(o[0]) or (mine["staff"] if mine["open"] else 0) != int(o[1]) or mine["open"] != o[3]: problems.append("outdoor crowd")
			_ok(problems.is_empty(), "%s: building %s: %s" % [label, str(w["id"]), ", ".join(problems)])
	# Peak concurrent occupants, every five minutes of a weekday and of a Sunday.
	for key: String in fx["peaks"]:
		var peaks := _sim.peak_occupancy(_plans(int(key)), 5)
		var want: Dictionary = fx["peaks"][key]
		var peaks_ok := true
		for b in _sim.building_count + 1:
			peaks_ok = peaks_ok and peaks[b] == int(want.get(Data.location_name(b), 0))
		_ok(peaks_ok, "peak occupancy of day %s (street peak %d)" % [key, peaks[Data.STREET]])
	# Upstream merges only the day's first and last segment: resident 0 sleeps 0-5, 5-410 and 1280-1440 on day 1.
	var first_piece := _sim.state_at(_plans(1), 0, 0.0)
	var last_piece := _sim.state_at(_plans(1), 0, 1439.0)
	_ok(first_piece["state"] == Data.ST_SLEEPING and first_piece["state_since"] == last_piece["state_since"] - 1440
		and last_piece["until_minute"] == first_piece["until_minute"] + 1440, "a sleep that wraps midnight is one span")

# ---------------------------------------------------------------- lighting


func test_lighting() -> void:
	var fx := _load("lighting.json")
	for row: Array in fx["factors"]:
		var f := Clock.factors(row[0])
		var label := "factors(%.3f)" % float(row[0])
		_ok(absf(f["minute"] - row[1]) <= TOL and absf(f["daylight"] - row[2]) <= TOL and absf(f["lamps"] - row[3]) <= TOL
			and absf(f["dusk"] - row[4]) <= TOL and absf(f["windows"] - row[5]) <= TOL,
			"%s: %s vs %s" % [label, str(f), str(row)])
		_ok(absf(Clock.lamp_level(row[0]) - row[3]) <= TOL and absf(Clock.dusk_level(row[0]) - row[4]) <= TOL
			and absf(Clock.window_level(row[0]) - row[5]) <= TOL, label + " through the single functions")
	for row: Array in fx["open"]:
		_ok(Clock.is_open(Data.POLICIES.find(row[0]), int(row[1]), float(row[2])) == row[3], "is_open(%s, day %d, %d)" % [row[0], int(row[1]), int(row[2])])
	for row: Array in fx["owl"]:
		var coin := Clock.owl_coin(row[0])
		_ok((coin < 0.38) == (float(row[1]) > 0.0) and coin >= 0.0 and coin < 1.0, "night-owl coin of %s (%.3f)" % [row[0], coin])
		_near(Clock.window_rule("housing", 10, true, 0, 0, 1400.0, coin)["room"], row[1], "night-owl windows of %s" % row[0])
	for row: Array in fx["dispatch"]:
		var same := true
		var k := 0
		for m in range(0, 1440, 30):
			same = same and Clock.dispatch(row[0], int(row[1]), m) == row[2][k]
			k += 1
		_ok(same, "dispatch(%s, %d) through the day" % [row[0], int(row[1])])
	_ok((fx["buildingIds"] as Array).size() == _sim.building_count, "lighting rows per building")
	# Window rules of every building every ten minutes, a weekday and a Saturday.
	for key: String in fx["buildings"]:
		var plans := _plans(int(key))
		var rows: Array = fx["buildings"][key]
		var worst := 0.0
		var k := 0
		for m in range(0, 1440, 10):
			var view := _sim.sample(plans, m)
			var row: Array = rows[k]
			k += 1
			var bad := PackedStringArray()
			for b in _sim.building_count:
				var mine: Dictionary = view["buildings"][b]
				var l: Array = row[b]
				var d := maxf(maxf(absf(mine["light"] - l[3]), absf(mine["entry"] - l[5])), maxf(absf(mine["facade"] - l[6]), absf(mine["decoration"] - l[7])))
				worst = maxf(worst, d)
				if mine["open"] != l[0] or mine["count"] != int(l[1]) or mine["awake"] != int(l[2]) or mine["max_panes"] != int(l[4]) or d > TOL:
					bad.append(str(mine["id"]))
			_ok(bad.is_empty(), "day %s %s: window rules; differ: %s" % [key, Clock.format_minute(m), ", ".join(bad)])
		print("  window rules day %s: 144 minutes x 31 buildings, largest difference %s" % [key, String.num_scientific(worst)])

# ---------------------------------------------------------------- sky


func test_sky() -> void:
	var fx := _load("sky.json")
	var c: Array = fx["columns"]
	_ok(float(fx["radius"]) == Clock.SKY_RADIUS and float(fx["secondsPerSimMinute"]) == UP, "sky constants")
	var worst := 0.0
	for row: Array in fx["rows"]:
		var seconds: float = row[0]
		var s := Clock.sky_state_upstream(seconds, row[1])
		var sun: PackedFloat64Array = s["sun_position_units64"]
		var moon: PackedFloat64Array = s["moon_position_units64"]
		var sun_dir: PackedFloat64Array = s["sun_direction64"]
		var moon_dir: PackedFloat64Array = s["moon_direction64"]
		var mine := [seconds, row[1], s["minute"], s["daylight"], s["golden_hour"], s["sunset_blend"], s["cloud_sea"],
			s["sun_visibility"], s["low_sun_haze"], s["sun_radius"], s["moon_visibility"], s["dusk"], sun[0], sun[1], sun[2],
			moon[0], moon[1], moon[2], sun_dir[0], sun_dir[1], sun_dir[2], moon_dir[0], moon_dir[1], moon_dir[2],
			s["space_angle"], s["cloud_shift"]]
		var bad := PackedStringArray()
		for k in c.size():
			var d := absf(float(mine[k]) - float(row[k]))
			worst = maxf(worst, d)
			if d > TOL:
				bad.append("%s %.9f vs %.9f" % [c[k], float(mine[k]), float(row[k])])
		_ok(bad.is_empty(), "sky at %.3f s: %s" % [seconds, "; ".join(bad)])
		# The game's functions of the minute agree wherever the minute is whole.
		var minute := seconds / UP
		if minute == floorf(minute):
			var g := Clock.sky_state(minute)
			var m := fposmod(minute, 1440.0)
			_ok((g["sun_direction"] as Vector3).distance_to(s["sun_direction"]) < 1e-5 and absf(g["golden_hour"] - s["golden_hour"]) <= TOL
				and absf(g["daylight"] - s["daylight"]) <= TOL and absf(g["dusk"] - s["dusk"]) <= TOL
				and Clock.sun_direction(m).distance_to(s["sun_direction"]) < 1e-5 and Clock.moon_direction(m).distance_to(s["moon_direction"]) < 1e-5
				and absf(Clock.golden_hour(m) - s["golden_hour"]) <= TOL and absf(g["space_angle"] - s["space_angle"]) <= TOL,
				"sky_state(%d) for the game" % int(minute))
	print("  sky: %d frames, largest difference %s" % [(fx["rows"] as Array).size(), String.num_scientific(worst)])
	_ok(Clock.sun_direction(735.0).y > 0.69 and Clock.sun_direction(735.0).z > 0.0 and Clock.sun_direction(330.0).x > 0.99
		and Clock.sun_direction(1140.0).x < -0.99, "the sun rises in the east (+x), stands south (+z) at noon and sets in the west")
	_ok(Clock.sun_direction(0.0).y < 0.0 and Clock.moon_direction(0.0).y > 0.0 and Clock.moon_direction(720.0).y < 0.0, "the moon is up at midnight, the sun is not")

# ---------------------------------------------------------------- transit


func test_transit() -> void:
	var fx := _load("transit.json")
	var site: Dictionary = fx["site"]
	var plan := Clock.transit_plan_units(site["x"], site["z"], 0 if site["gateSide"] == null else int(site["gateSide"]))
	_ok(plan["side"] == int(fx["side"]) and float(fx["speed"]) == Clock.TRANSIT_SPEED_UNITS and float(fx["period"]) == Clock.TRANSIT_PERIOD
		and Clock.TRANSIT_SPEED == 5.0, "station loop constants: 10 units/s = 5 m/s, a lap period of 360 s")
	var defaults := Clock.transit_plan_units()
	_ok(defaults["site_x"] == site["x"] and defaults["site_z"] == site["z"] and defaults["side"] == plan["side"], "the default plan is the default town's station")
	var vehicles: Array = plan["vehicles"]
	var rows: Array = fx["vehicles"]
	_ok(vehicles.size() == rows.size() and vehicles.size() == 7, "3 buses and 4 taxis")
	for i in mini(vehicles.size(), rows.size()):
		var v: Dictionary = vehicles[i]
		var r: Array = rows[i]
		_ok(v["id"] == r[0] and v["x"] == r[1] and v["z"] == r[2] and v["bus"] == r[3] and v["index"] == int(r[4])
			and v["departure"] == r[5] and v["path"]["count"] == int(r[7]), "vehicle %s" % str(r[0]))
		_near(v["path"]["length"], r[6], "loop length of %s" % str(r[0]))
	for p: Dictionary in fx["paths"]:
		var path: Dictionary = vehicles[int(p["index"])]["path"]
		var seg: PackedFloat64Array = path["seg"]
		var points: Array = p["points"]
		var starts: Array = p["starts"]
		var worst := 0.0
		var count: int = path["count"]
		if count + 1 == points.size():
			for k in count:
				worst = maxf(worst, maxf(absf(seg[k * 6] - points[k][0]), absf(seg[k * 6 + 1] - points[k][1])))
				worst = maxf(worst, absf(seg[k * 6 + 4] - starts[k]))
			worst = maxf(worst, maxf(absf(seg[(count - 1) * 6 + 2] - points[count][0]), absf(seg[(count - 1) * 6 + 3] - points[count][1])))
		else:
			worst = INF
		_ok(worst <= TOL, "rounded path of vehicle %d (largest difference %s)" % [int(p["index"]), String.num_scientific(worst)])
	var worst_all := 0.0
	var moving := 0
	for sample: Array in fx["samples"]:
		var t: float = sample[0]
		var fleet := Clock.transit_upstream(plan, t)
		var bad := PackedStringArray()
		for i in fleet.size():
			var v: Dictionary = fleet[i]
			var r: Array = sample[1][i]
			var d := maxf(maxf(absf(v["x"] - r[0]), absf(v["z"] - r[1])), maxf(absf(v["y"] - r[2]), maxf(absf(v["local_x"] - r[3]), absf(v["local_z"] - r[4]))))
			var da := maxf(absf(fposmod(v["heading"] - r[5] + PI, TAU) - PI), absf(fposmod(v["local_heading"] - r[6] + PI, TAU) - PI))
			worst_all = maxf(worst_all, maxf(d, da))
			if v["moving"]:
				moving += 1
			if d > TOL or da > TOL or Clock.TRANSIT_STATUS[v["status"]] != r[7] or v["moving"] != r[8]:
				bad.append("%s (%s vs %s)" % [v["id"], Clock.TRANSIT_STATUS[v["status"]], r[7]])
		_ok(bad.is_empty(), "station fleet at %.2f s: %s" % [t, ", ".join(bad)])
	print("  transit: %d times x 7 vehicles (%d moving), largest difference %s" % [(fx["samples"] as Array).size(), moving, String.num_scientific(worst_all)])


# The game's wrappers: metres, Lantern Lane seconds and yaw.
func test_wrappers() -> void:
	var plan := Clock.transit_plan_units()
	# Sim-locked: the same place as upstream at the same sim minute.
	var locked := Clock.transit(plan, Clock.seconds_at(1, 500.0), true)
	var upstream := Clock.transit_upstream(plan, 500.0 * UP)
	var same := true
	for i in locked.size():
		same = same and locked[i]["status"] == upstream[i]["status"] \
			and (locked[i]["pos"] as Vector3).distance_to(Clock.to_metres(upstream[i]["x"], upstream[i]["y"], upstream[i]["z"])) < 1e-4
	_ok(same, "sim-locked transit is upstream's fleet at the same sim minute, in metres")
	# Real-time pace on Lantern Lane's clock: bus 0 leaves 5 s after 06:00 and drives at 5 m/s.
	var before := Clock.transit(plan, 364.9)
	var a := Clock.transit(plan, 400.0)
	var b := Clock.transit(plan, 400.5)
	_ok(not before[0]["moving"] and before[0]["status"] == Clock.TRANSIT_WAITING and a[0]["moving"], "bus 0 leaves at 06:00 plus 5 s of Lantern Lane time")
	_near((a[0]["pos"] as Vector3).distance_to(b[0]["pos"]) / 0.5, Clock.TRANSIT_SPEED, "a bus drives at 5 m/s", 1e-3)
	var forward := Vector3(sin(a[0]["yaw"]), 0.0, cos(a[0]["yaw"]))
	_ok(forward.dot(((b[0]["pos"] as Vector3) - (a[0]["pos"] as Vector3)).normalized()) > 0.999, "yaw points along the motion (forward = (sin, cos))")
	var small_hours := Clock.transit(plan, 200.0)
	_ok(small_hours[0]["status"] == Clock.TRANSIT_CLOSED and small_hours[3]["status"] != Clock.TRANSIT_CLOSED and small_hours[3]["moving"]
		and small_hours[4]["status"] == Clock.TRANSIT_CLOSED and small_hours[6]["status"] == Clock.TRANSIT_CLOSED, "at 03:20 only taxi 0 is in service")
	var departures := 0
	var was := false
	for t in range(0, 1440):
		var now: bool = Clock.transit(plan, float(t))[0]["moving"]
		if now and not was:
			departures += 1
		was = now
	_ok(departures == 3, "bus 0 makes three laps a Lantern Lane day (%d)" % departures)
	_near(Clock.yaw_from_heading(0.0), PI / 2.0, "heading east is yaw PI/2")
	# Fireworks on Lantern Lane's clock: 19:00-22:00, a 96 s loop at real pace.
	var fw := Clock.fireworks_state(1, 1140.0)
	_ok(fw["enabled"] and fw["show_seconds"] == 0.0 and fw["phase"] == "ensemble", "the show starts at 19:00")
	_ok(Clock.fireworks_state(3, 1140.0 + 30.0)["phase"] == "weave" and Clock.fireworks_state(3, 1140.0 + 96.0 + 80.0)["phase"] == "finale"
		and Clock.fireworks_state(3, 1140.0 + 95.0)["phase"] == "rest", "show phases by Lantern Lane seconds")
	_ok(not Clock.fireworks_state(1, 1139.0)["enabled"] and Clock.fireworks_state(1, 1319.0)["enabled"] and not Clock.fireworks_state(1, 1320.0)["enabled"], "the show window is 19:00-22:00")
	var heli_plan := Clock.helipad_plan_units(132.0, -200.0, 21, 28.098, 38.987)
	var h := Clock.helicopter(heli_plan, 10.0)
	_ok(h["parked"] and (h["pos"] as Vector3).is_equal_approx(Vector3(66.0, 63.7, -100.0)), "the parked helicopter in metres")
	var ship := Clock.airship(Clock.airship_plan_units(), 0.0)
	_ok(absf(ship["pos"].y - 107.96) < 0.01, "the airship flies about 108 m up")

# ---------------------------------------------------------------- events


func test_events() -> void:
	var fx := _load("events.json")
	var fw: Dictionary = fx["fireworks"]
	_ok(int(fw["window"]["from"]) == Clock.FIREWORKS_FROM and int(fw["window"]["to"]) == Clock.FIREWORKS_TO
		and float(fw["show"]["duration"]) == Clock.FIREWORKS_SHOW_SECONDS and int(fw["show"]["maxParticles"]) == Clock.FIREWORKS_MAX_PARTICLES, "fireworks constants")
	for row: Array in fw["states"]:
		var s := Clock.fireworks_state_upstream(row[0])
		_ok(s["enabled"] == row[1] and s["minute"] == int(row[2]) and absf(s["show_seconds"] - row[3]) <= TOL and s["day"] == int(row[4])
			and s["phase"] == row[5], "fireworks state at %.3f s: %s" % [float(row[0]), str(s)])
	var sites: Array = fw["sites"]
	var sites_ok := sites.size() == Clock.FIREWORK_SITES.size()
	for i in mini(sites.size(), Clock.FIREWORK_SITES.size()):
		sites_ok = sites_ok and sites[i][0] == Clock.FIREWORK_SITES[i]
	_ok(sites_ok, "the eight launch sites in order")
	var sc: Array = fw["shellColumns"]
	var shells := Clock.fireworks_schedule(Data.SEED)
	var want: Array = fw["shells"]
	_ok(shells.size() == want.size() and shells.size() == 128, "128 shells in a show")
	var worst := 0.0
	for i in mini(shells.size(), want.size()):
		var mine: Dictionary = shells[i]
		var r: Array = want[i]
		var d := maxf(maxf(absf(mine["fire_time"] - r[_column(sc, "fireTime")]), absf(mine["apex_units"] - r[_column(sc, "apexY")])),
			maxf(absf(mine["apex_time"] - r[_column(sc, "apexT")]), absf(mine["ascent_velocity_units"] - r[_column(sc, "ascentVelocity")])))
		d = maxf(d, maxf(absf(mine["drift_x_units"] - r[_column(sc, "driftX")]), absf(mine["drift_z_units"] - r[_column(sc, "driftZ")])))
		d = maxf(d, absf(mine["intensity"] - r[_column(sc, "intensity")]))
		worst = maxf(worst, d)
		_ok(d <= TOL and mine["ordinal"] == int(r[_column(sc, "ordinal")]) and Clock.FIREWORK_SITES[mine["site"]] == r[_column(sc, "siteId")]
			and mine["shape"] == r[_column(sc, "shapeName")] and mine["finale"] == r[_column(sc, "finale")] and mine["color"] == r[_column(sc, "color")],
			"shell %d: %s" % [i, str(mine)])
	var branded := 0
	for shell in shells:
		if Clock.FIREWORK_GAME_SHAPES.has(shell["game_shape"]):
			branded += 1
	_ok(branded == 0, "the game's shells carry none of upstream's branded bursts")
	print("  fireworks: 128 shells, largest difference %s" % String.num_scientific(worst))

	var program: Array = fx["fountain"]["program"]
	var program_ok := program.size() == Clock.FOUNTAIN_PROGRAM.size()
	for i in mini(program.size(), Clock.FOUNTAIN_PROGRAM.size()):
		var p: Array = Clock.FOUNTAIN_PROGRAM[i]
		program_ok = program_ok and p[0] == int(program[i]["from"]) and p[1] == int(program[i]["to"]) and p[2] == float(program[i]["level"]) and p[3] == program[i]["name"]
	_ok(program_ok, "the fountain programme")
	for row: Array in fx["fountain"]["rows"]:
		var m: float = row[0]
		_ok(absf(Clock.fountain_level(m) - row[1]) <= TOL and absf(Clock.fountain_level_smooth(m) - row[2]) <= TOL and Clock.fountain_program(m) == row[3],
			"fountain at %.3f: %.6f, %.6f, %s" % [m, Clock.fountain_level(m), Clock.fountain_level_smooth(m), Clock.fountain_program(m)])

	var heli: Dictionary = fx["helicopter"]
	var cycle: Dictionary = heli["cycle"]
	_ok(float(cycle["period"]) == Clock.HELI_PERIOD and float(cycle["takeOff"]) == Clock.HELI_TAKE_OFF and float(cycle["airborne"]) == Clock.HELI_AIRBORNE
		and float(cycle["homecoming"]) == Clock.HELI_HOMECOMING and float(cycle["touchdown"]) == Clock.HELI_TOUCHDOWN and float(cycle["lift"]) == Clock.HELI_LIFT
		and float(cycle["cruise"]) == Clock.HELI_CRUISE and float(cycle["idleSpin"]) == Clock.HELI_IDLE_SPIN and float(cycle["flightSpin"]) == Clock.HELI_FLIGHT_SPIN, "helicopter cycle")
	var tower: Dictionary = heli["tower"]
	var plan := Clock.helipad_plan_units(tower["x"], tower["z"], int(tower["floors"]), tower["w"], tower["d"])
	var want_plan: Dictionary = heli["plan"]
	var plan_ok := true
	for key: String in ["a", "b", "cruise", "cx", "cz", "radius", "ux", "uz", "vx", "vz", "x", "z"]:
		plan_ok = plan_ok and absf(plan[key] - want_plan[key]) <= TOL
	_ok(plan_ok and absf(plan["roof_y"] - want_plan["roofY"]) <= TOL, "helipad plan on %s" % str(tower["id"]))
	worst = 0.0
	for row: Array in heli["rows"]:
		var s := Clock.helicopter_units(plan, row[0])
		var d := maxf(maxf(absf(s["x"] - row[2]), absf(s["y"] - row[3])), maxf(absf(s["z"] - row[4]), maxf(absf(s["bank"] - row[6]), absf(s["pitch"] - row[7]))))
		d = maxf(d, maxf(absf(fposmod(s["heading"] - row[5] + PI, TAU) - PI), absf(s["rotor_turns"] - row[9])))
		d = maxf(d, absf(fposmod(s["rotor"] - row[8] + PI, TAU) - PI))
		worst = maxf(worst, d)
		_ok(d <= TOL and s["phase"] == row[1] and s["parked"] == row[10] and s["grounded"] == row[11], "helicopter at %.3f s: %s" % [float(row[0]), str(s)])
	print("  helicopter: %d times, largest difference %s" % [(heli["rows"] as Array).size(), String.num_scientific(worst)])

	var air: Dictionary = fx["airship"]
	var route := Clock.airship_plan_units(air["city"]["extentX"], air["city"]["extentZ"], air["city"]["roof"])
	_ok(absf(route["rx"] - air["plan"]["rx"]) <= TOL and absf(route["rz"] - air["plan"]["rz"]) <= TOL and absf(route["altitude"] - air["plan"]["altitude"]) <= TOL
		and float(air["plan"]["period"]) == Clock.AIRSHIP_PERIOD, "airship route")
	var default_route := Clock.airship_plan_units()
	_ok(default_route["rx"] == route["rx"] and default_route["rz"] == route["rz"] and default_route["altitude"] == route["altitude"], "the default airship route is the default town's")
	worst = 0.0
	for row: Array in air["rows"]:
		var s := Clock.airship_units(route, row[0])
		var d := maxf(maxf(absf(s["x"] - row[1]), absf(s["y"] - row[2])), maxf(absf(s["z"] - row[3]), maxf(absf(s["bank"] - row[5]), absf(s["pulse"] - row[6]))))
		d = maxf(d, absf(fposmod(s["heading"] - row[4] + PI, TAU) - PI))
		worst = maxf(worst, d)
		_ok(d <= TOL, "airship at %.1f s" % float(row[0]))
	print("  airship: %d times, largest difference %s" % [(air["rows"] as Array).size(), String.num_scientific(worst)])

# ---------------------------------------------------------------- timing


func test_timing() -> void:
	# A cold build fills the template cache; later days reuse it.
	var cold_sim := Sim.new()
	var t0 := Time.get_ticks_usec()
	cold_sim.build_day(1)
	var cold := (Time.get_ticks_usec() - t0) / 1000.0
	var warm_total := 0.0
	var warm_max := 0.0
	var days := [2, 6, 7, 13, 100, 365]
	for day: int in days:
		t0 = Time.get_ticks_usec()
		cold_sim.build_day(day)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		warm_total += ms
		warm_max = maxf(warm_max, ms)
	var plans := _plans(1)
	t0 = Time.get_ticks_usec()
	for m in range(0, 1440, 60):
		_sim.occupancy(plans, m)
	var occupancy_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 24.0
	t0 = Time.get_ticks_usec()
	for m in range(0, 1440, 60):
		_sim.sample(plans, m)
	var sample_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 24.0
	t0 = Time.get_ticks_usec()
	for i in 1000:
		_sim.state_at(plans, i, 720.0)
	var state_us := float(Time.get_ticks_usec() - t0) / 1000.0
	print("THOUSAND SIM TIMING: roster %.1f ms; build_day (1000 plans) cold %.1f ms, warm mean %.1f ms, warm max %.1f ms; occupancy %.2f ms; sample %.2f ms; state_at %.2f us each"
		% [_roster_ms, cold, warm_total / days.size(), warm_max, occupancy_ms, sample_ms, state_us])
	# The design budget is "well under 1 s on a phone"; this desktop bound leaves a wide margin for one.
	_ok(cold < 500.0 and warm_max < 250.0, "a day of plans builds in well under a second (cold %.1f ms, warm max %.1f ms)" % [cold, warm_max])
	_ok(sample_ms < 50.0, "a per-building sample takes a few milliseconds (%.2f ms)" % sample_ms)
