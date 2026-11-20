## Thousand Town: the 1000 residents, their day plans and where everybody is
## (design/thousand-town.md, sections 2 and 5). Pure GDScript with packed arrays, no nodes.
##
## Ported from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY (github.com/YiHuiShiBY/thousand-town,
## commit 1332ef2, CC BY 4.0): city-life-ext/resident.js (create), resident-name.js (generate),
## resident-plan.js (buildDay, validate), resident-state.js (stateAt, occupancy) and town-view.js (sample).
## Changed for Lantern Lane: GDScript, residents and buildings by index, packed segments, and names for the
## five other locales. tests/thousand_sim_tests.gd proves exact parity with fixtures produced by upstream's
## code (scripts/thousand_town/sim_fixtures.mjs): the roster, the plans of days 1, 6, 7 and 42, the
## states and occupancy at sample minutes.
##
##   var sim := Sim.new()                     the roster for seed 20260818 (the same town on every device)
##   var plans := sim.build_day(day)          every resident's plan for a day: a pure function of
##                                            (seed, resident, day), any day in any order
##   sim.state_at(plans, i, minute)           what resident i is doing and where
##   sim.occupancy(plans, minute)             counts per building, per state and on the street
##   sim.sample(plans, minute)                per building: who is there, counts by state, open, lights
##
## A resident is an index 0..999 in roster order (the census rows in order, each role's ordinals in order).
## A location is a building index 0..30 into Data.BUILDINGS, or Data.STREET. A COMMUTE segment is just
## "on the street": upstream has no routes; routing door to door is Lantern Lane's addition elsewhere.
## A plan covers its day from 0 to 1440; day d's last segment and day d+1's first need not line up.
extends RefCounted

const Data := preload("res://scripts/core/thousand_sim_data.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")

const SEG := Data.SEG
const STREET := Data.STREET
## Each interior walk slides up to this many minutes either way, and never squeezes a neighbour below
## MIN_SESSION minutes (resident-plan.js staggerWaves).
const WALK_STAGGER := 30
const MIN_SESSION := 10
## leisure_venue values besides a building index: not in the leisure ledger, and "stays home".
const LEISURE_NONE := -2
const LEISURE_HOME := -1
const TOKEN_COUNT := 16

## The plans of all residents for one day. `segs` holds five ints per segment (start, end, state,
## location, substate); resident i's segments are first[i] .. first[i + 1] - 1.
class DayPlans:
	var day: int
	var day_type: int
	var segs := PackedInt32Array()
	var first := PackedInt32Array([0])
	## The building a resident minds on a weekend duty day, or -1.
	var duty := PackedInt32Array()
	## Residents built so far; the plans are complete when this reaches the roster's size.
	var built := 0
	var _day_text: String

## The town's seed, 20260818 (unsigned 32 bits).
var town_seed: int
## The number of residents (1000).
var count := 0
var building_count := 0

# The roster, one entry per resident.
var ids := PackedStringArray()
## Index of the resident's row in Data.CENSUS.
var role := PackedInt32Array()
var ordinal := PackedInt32Array()
var age := PackedInt32Array()
## 0 male ("M"), 1 female ("F").
var gender := PackedInt32Array()
var birth_month := PackedInt32Array()
## Traits: pace tilts the whole day by up to 6 minutes; sociability is drawn but not used, as upstream.
var pace := PackedFloat64Array()
var sociability := PackedFloat64Array()
var home := PackedInt32Array()
## Building index of the workplace or school, or -1.
var workplace := PackedInt32Array()
## 0 early, 1 mid, 2 night, or -1 without a shift.
var shift_index := PackedInt32Array()
## The clinic of the resident's own housing block, or -1.
var clinic := PackedInt32Array()
## An officer's duty place (the school the police post is annexed to), or -1.
var duty_post := PackedInt32Array()
## The weekend policy of the resident's workplace (Data.POLICY_*).
var venue_policy := PackedInt32Array()
## The resident's seat in the leisure ledger: a building index, LEISURE_HOME or LEISURE_NONE.
var leisure_venue := PackedInt32Array()
## The stable habit draw 0..99 that picks the branches of the day templates.
var variant := PackedInt32Array()
var name_zh := PackedStringArray()
var pinyin := PackedStringArray()

# The buildings, one entry per Data.BUILDINGS row.
var building_index := {}
## People whose workplace or school the building is.
var workers := PackedInt32Array()
## People who live in the building.
var housed := PackedInt32Array()
## Seats the leisure ledger handed out in the building.
var venue_use := PackedInt32Array()
## kind -> index of the first building of that kind; "school" is the primary school.
var kinds := {}
## Per building: the residents who live there, in roster order.
var homes: Array[PackedInt32Array] = []

var _index := {}
var _prefix := PackedInt64Array()
var _base_template := PackedInt32Array()
var _work_override := PackedInt32Array()
var _role_class := PackedInt32Array()
var _staff_role := PackedByteArray()
var _capacity := PackedInt32Array()
var _policy := PackedInt32Array()
var _kind := PackedStringArray()
var _owl := PackedFloat64Array()
var _closed: Array[PackedByteArray] = []
var _posts: Array[PackedInt32Array] = []
var _templates := {}
var _place := PackedInt32Array()
var _next_mask := PackedInt32Array()


func _init(p_seed: int = Data.SEED) -> void:
	town_seed = p_seed & 0xFFFFFFFF
	_index_buildings()
	_create_roster()

# ---------------------------------------------------------------- roster (resident.js create)


func _index_buildings() -> void:
	building_count = Data.BUILDINGS.size()
	for b in building_count:
		var row: Dictionary = Data.BUILDINGS[b]
		building_index[row["id"]] = b
		_capacity.append(row["cap"])
		_policy.append(row["open"])
		_kind.append(row["kind"])
		_owl.append(Clock.owl_coin(row["id"]))
		if row["kind"] != "housing" and not kinds.has(row["kind"]):
			kinds[row["kind"]] = b
	kinds["school"] = kinds["primary"]
	workers.resize(building_count)
	housed.resize(building_count)
	venue_use.resize(building_count)
	for day_type in Data.DAY_TYPES.size():
		var closed := PackedByteArray()
		var posts := PackedInt32Array()
		for b in building_count:
			var shut := Data.closes_on(_policy[b], day_type)
			closed.append(1 if shut else 0)
			if shut:
				posts.append(b)
		if day_type != Data.DAY_WEEKDAY:
			for id: String in Data.SECURITY_POSTS:
				if not posts.has(building_index[id]):
					posts.append(building_index[id])
		_closed.append(closed)
		_posts.append(posts)
	# The legal next states of each state as a bit mask (resident-plan.js NEXT).
	var next := [
		[Data.ST_HOME, Data.ST_DINING, Data.ST_COMMUTE, Data.ST_SLEEPING],
		[Data.ST_AT_WORK, Data.ST_SHOPPING, Data.ST_LEISURE, Data.ST_MEDICAL, Data.ST_DINING, Data.ST_HOME, Data.ST_COMMUTE, Data.ST_SLEEPING],
		[Data.ST_AT_WORK, Data.ST_DINING, Data.ST_COMMUTE, Data.ST_HOME, Data.ST_SLEEPING],
		[Data.ST_LEISURE, Data.ST_DINING, Data.ST_SHOPPING, Data.ST_COMMUTE, Data.ST_HOME, Data.ST_SLEEPING],
		[Data.ST_MEDICAL, Data.ST_DINING, Data.ST_COMMUTE, Data.ST_HOME, Data.ST_SLEEPING],
		[Data.ST_SHOPPING, Data.ST_DINING, Data.ST_COMMUTE, Data.ST_HOME, Data.ST_LEISURE, Data.ST_SLEEPING],
		[Data.ST_DINING, Data.ST_AT_WORK, Data.ST_HOME, Data.ST_COMMUTE, Data.ST_SHOPPING, Data.ST_LEISURE, Data.ST_MEDICAL, Data.ST_SLEEPING],
		[Data.ST_HOME, Data.ST_SLEEPING, Data.ST_DINING, Data.ST_COMMUTE],
	]
	for states: Array in next:
		var mask := 0
		for s: int in states:
			mask |= 1 << s
		_next_mask.append(mask)


static func _shuffled(rng: Data.Rng, list: PackedInt32Array) -> PackedInt32Array:
	var a := list.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := floori(rng.next() * (i + 1))
		var t := a[i]
		a[i] = a[j]
		a[j] = t
	return a


func _create_roster() -> void:
	var rng := Data.Rng.new(town_seed)
	var by_kind := {}
	for b in building_count:
		var of_kind: Array = by_kind.get(_kind[b], [])
		of_kind.append(b)
		by_kind[_kind[b]] = of_kind

	# Stage 1: the census rows in order. Five draws per resident, in upstream's order: age, gender, birth
	# month, pace, sociability. Birth month and sociability are not used but must still be drawn.
	for row_index in Data.CENSUS.size():
		var row: Dictionary = Data.CENSUS[row_index]
		var trade: String = row["role"]
		var band: Array = row["age"]
		var work: Array = row["work"]
		var quota: Dictionary = row["quota"]
		# The kind each of the row's people works in (by quota), or the pool of buildings taking turns.
		var slots := PackedStringArray()
		var pool := PackedInt32Array()
		if not quota.is_empty():
			for kind: String in work:
				for n in int(quota[kind]):
					slots.append(kind)
			assert(slots.size() == int(row["count"]), "the quota of %s must add up to its headcount" % trade)
		else:
			for kind: String in work:
				pool.append_array(PackedInt32Array(by_kind[kind]))
		var cursors := {}
		var pool_cursor := 0
		var shift_cursor := 0
		for i in int(row["count"]):
			ids.append("%s-%03d" % [trade, i + 1])
			role.append(row_index)
			ordinal.append(i + 1)
			age.append(int(band[0]) + floori(rng.next() * (int(band[1]) - int(band[0]) + 1)))
			gender.append(0 if rng.next() < 0.5 else 1)
			birth_month.append(1 + floori(rng.next() * 12.0))
			pace.append(Data.js_round((rng.next() * 0.4 - 0.2) * 100.0) / 100.0)
			sociability.append(Data.js_round(rng.next() * 100.0) / 100.0)
			var shift := -1
			if row["shift"]:
				shift = shift_cursor % 3
				shift_cursor += 1
			shift_index.append(shift)
			var building := -1
			if not slots.is_empty():
				var candidates: Array = by_kind[slots[i]]
				var pick: int = int(cursors.get(slots[i], 0)) % candidates.size()
				cursors[slots[i]] = pick + 1
				building = candidates[pick]
			elif not pool.is_empty():
				var pick := pool_cursor % pool.size()
				pool_cursor = pick + 1
				building = pool[pick]
			workplace.append(building)
			if building >= 0:
				workers[building] += 1
	count = ids.size()
	assert(count == Data.POPULATION)
	for i in count:
		_index[ids[i]] = i

	# Stage 2: names over the whole roster, from the same generator (resident-name.js generate).
	_generate_zh_names(rng)

	# Stage 3: housing. Patients take the ward; everybody else fills the housing blocks in a shuffled
	# order, the blocks themselves in a shuffled order.
	var housing := _shuffled(rng, PackedInt32Array(by_kind["housing"]))
	var everyone := PackedInt32Array()
	everyone.resize(count)
	for i in count:
		everyone[i] = i
	var hospital: int = kinds["hospital"]
	var slot_cursor := 0
	home.resize(count)
	for r in _shuffled(rng, everyone):
		if Data.CENSUS[role[r]]["role"] == "patient":
			home[r] = hospital
			housed[hospital] += 1
			continue
		while slot_cursor < housing.size() and housed[housing[slot_cursor]] >= _capacity[housing[slot_cursor]]:
			slot_cursor += 1
		assert(slot_cursor < housing.size(), "housing capacity short")
		home[r] = housing[slot_cursor]
		housed[housing[slot_cursor]] += 1
	for b in building_count:
		var living := PackedInt32Array()
		for i in count:
			if home[i] == b:
				living.append(i)
		homes.append(living)

	# Stage 4: what follows from where somebody lives and works.
	var ledger_venues := PackedInt32Array()
	for kind: String in Data.VENUE_ORDER:
		ledger_venues.append_array(PackedInt32Array(by_kind[kind]))
	var venue_cursor := 0
	for i in count:
		var trade: String = Data.CENSUS[role[i]]["role"]
		var own_clinic: String = Data.BUILDINGS[home[i]]["clinic"]
		clinic.append(building_index[own_clinic] if own_clinic != "" else -1)
		var post := -1
		var policy: int = Data.POLICY_DAILY
		if workplace[i] >= 0:
			var host: String = Data.BUILDINGS[workplace[i]]["annex_of"]
			if trade == "officer" and host != "":
				post = building_index[host]
			policy = _policy[workplace[i]]
		duty_post.append(post)
		venue_policy.append(policy)
		# The leisure ledger: one hangout each for these roles, filling each venue to 85% of its
		# capacity less its own staff; whoever is left over stays home.
		var venue := LEISURE_NONE
		if Data.LEDGER_ROLES.has(trade):
			venue = LEISURE_HOME
			while venue_cursor < ledger_venues.size():
				var v := ledger_venues[venue_cursor]
				if floori(_capacity[v] * Data.VENUE_FILL) - workers[v] - venue_use[v] > 0:
					venue = v
					venue_use[v] += 1
					break
				venue_cursor += 1
		leisure_venue.append(venue)
		# The hash of the fixed part of the day key "seed:id:day", and the habit draw from "seed:id:habit".
		var prefix := Data.hash32("%d:%s:" % [town_seed, ids[i]])
		_prefix.append(prefix)
		variant.append(Data.hash32("habit", prefix) % 100)
		# The role's template before the day decides, and the two workplaces that override it.
		var template_id: int = Data.ROLE_TEMPLATE[trade]
		if template_id == Data.T_SHIFT and shift_index[i] == 2:
			template_id = Data.T_SHIFT_NIGHT
		_base_template.append(template_id)
		var work_kind := _kind[workplace[i]] if workplace[i] >= 0 else ""
		_work_override.append(Data.T_MARKET_EARLY if work_kind == "market" else (Data.T_NIGHT_MARKET if work_kind == "night-market" else -1))
		_role_class.append(Data.role_class(trade))
		# Where each symbolic place of a template is for this resident (resident-plan.js resolveLocation);
		# -1 means the town has nowhere for it and the time is spent at home. DUTY changes by the day.
		var hm := home[i]
		var wp := workplace[i]
		var places := PackedInt32Array()
		places.resize(TOKEN_COUNT)
		places[Data.TK_HOME] = hm
		places[Data.TK_WORK] = wp if wp >= 0 else hm
		places[Data.TK_STREET] = STREET
		places[Data.TK_PLAZA] = venue if venue >= 0 else -1
		places[Data.TK_PARK] = places[Data.TK_PLAZA]
		places[Data.TK_MALL] = kinds["mall"]
		places[Data.TK_SCHOOL] = kinds["school"]
		places[Data.TK_ANNEX] = kinds["annex-mall"]
		places[Data.TK_MARKET] = kinds["market"]
		places[Data.TK_NIGHT] = kinds["night-market"]
		places[Data.TK_CLINIC] = clinic[i] if clinic[i] >= 0 else int(kinds["clinic"])
		places[Data.TK_BANK] = kinds["bank"]
		places[Data.TK_CIVIC] = kinds["civic"]
		places[Data.TK_POST] = post if post >= 0 else wp
		places[Data.TK_DUTY] = wp
		places[Data.TK_AMUSEMENT] = kinds["amusement"]
		_place.append_array(places)
		# Students, preschoolers and patients are not staff of the building they "work" in (town-view.js).
		_staff_role.append(0 if trade.begins_with("student-") or trade == "preschooler" or trade == "patient" else 1)


func _generate_zh_names(rng: Data.Rng) -> void:
	var surnames := Data.ZH_SURNAMES
	var initial := {}
	for pair: String in Data.ZH_PINYIN_INITIAL.split(" "):
		initial[pair[0]] = pair[1]
	# Per tier and gender: the single-character names and the longer ones, each [name, pinyin].
	var pools := []
	for tier: Array in Data.ZH_GIVEN:
		var by_gender := []
		for text: String in tier:
			var singles := []
			var doubles := []
			for entry: String in text.split(" "):
				var cut := entry.length()
				while cut > 0 and entry.unicode_at(cut - 1) >= 97 and entry.unicode_at(cut - 1) <= 122:
					cut -= 1
				var parts := [entry.substr(0, cut), entry.substr(cut)]
				if cut == 1:
					singles.append(parts)
				else:
					doubles.append(parts)
			by_gender.append([singles, doubles])
		pools.append(by_gender)
	var used := {}
	for i in count:
		var tier := Data.zh_tier(age[i])
		var singles: Array = pools[tier][gender[i]][0]
		var doubles: Array = pools[tier][gender[i]][1]
		var chosen := ""
		var chosen_pinyin := ""
		# Unique by retry: a surname, then a single or a longer given name; the 64th attempt is kept anyway.
		for attempt in 64:
			var surname := surnames[floori(rng.next() * surnames.length())]
			var choice: Array
			if rng.next() < Data.ZH_SINGLE_RATE[tier]:
				choice = singles[floori(rng.next() * singles.size())]
			else:
				choice = doubles[floori(rng.next() * doubles.size())]
			var candidate: String = surname + choice[0]
			if not used.has(candidate) or attempt == 63:
				chosen = candidate
				chosen_pinyin = str(initial.get(surname, "")) + str(choice[1])
				break
		used[chosen] = true
		name_zh.append(chosen)
		pinyin.append(chosen_pinyin)

# ---------------------------------------------------------------- roster queries


## The resident index of an id such as "office-037", or -1.
func index_of(id: String) -> int:
	return _index.get(id, -1)


func role_name(i: int) -> String:
	return Data.CENSUS[role[i]]["role"]


## The resident's name in a locale ("zh-CN", "en", "ja", "es", "fr", "de"; a region suffix is ignored and
## an unknown locale gets the English name). zh-CN is upstream's generated name. The other five come from
## Lantern Lane's own pools, fixed by the resident's place in the roster, and all 1000 are different:
## the roster index is spread over the 32 x 32 given-and-family pairs by an odd multiplier.
func name_of(i: int, locale: String = "en") -> String:
	var code := locale.substr(0, 2).to_lower()
	if code == "zh":
		return name_zh[i]
	var pools: Dictionary = Data.NAME_POOLS.get(code, Data.NAME_POOLS["en"])
	var pair := (i * 389 + 147) & 1023
	var given: String = pools["male" if gender[i] == 0 else "female"][pair & 31]
	var family: String = pools["family"][pair >> 5]
	return family + " " + given if Data.FAMILY_FIRST.has(code) else given + " " + family


## Everything about one resident, for the inspect panel and the tests.
func resident(i: int) -> Dictionary:
	return {
		"id": ids[i], "role": role_name(i), "ordinal": ordinal[i], "age": age[i], "gender": "M" if gender[i] == 0 else "F",
		"birth_month": birth_month[i], "pace": pace[i], "sociability": sociability[i], "home": home[i],
		"workplace": workplace[i], "shift_index": shift_index[i], "clinic": clinic[i], "duty_post": duty_post[i],
		"venue_policy": venue_policy[i], "leisure_venue": leisure_venue[i], "variant": variant[i],
		"name_zh": name_zh[i], "pinyin": pinyin[i],
	}

# ---------------------------------------------------------------- plans (resident-plan.js buildDay)


## The buildings that need somebody on duty on a day of this type: the shut ones, then the two malls.
func duty_posts(day_type: int) -> PackedInt32Array:
	return _posts[day_type]


## The building resident i minds on this day, or -1 (resident-plan.js weekendPostOf). Only workers whose
## own workplace is shut are on the roster; Saturday and Sunday call different halves, and the week
## number slides both along.
func weekend_post_of(i: int, day: int) -> int:
	var day_type := Clock.day_type(day)
	if day_type == Data.DAY_WEEKDAY or Data.CENSUS[role[i]]["role"] != "worker":
		return -1
	if not Data.closes_on(venue_policy[i], day_type):
		return -1
	var posts := _posts[day_type]
	if posts.is_empty():
		return -1
	var week := Clock.week_index(day)
	if (ordinal[i] + week + (1 if day_type == Data.DAY_SUNDAY else 0)) % 2 != 0:
		return -1
	@warning_ignore("integer_division")
	var rank := (ordinal[i] - 1) / 2
	return posts[(rank + week) % posts.size()]


## The template resident i follows on a day of this type (Data.T_*).
func template_of(i: int, day_type: int, on_duty: bool) -> int:
	if on_duty:
		return Data.T_DUTY
	if _work_override[i] >= 0:
		return _work_override[i]
	if Data.closes_on(venue_policy[i], day_type):
		return Data.T_WEEKEND
	return _base_template[i]


## Start an empty set of plans for a day; build_more() fills it a few residents at a time, so a new day
## can be spread over several frames.
func begin_day(day: int) -> DayPlans:
	var plans := DayPlans.new()
	plans.day = day
	plans.day_type = Clock.day_type(day)
	plans._day_text = str(day)
	return plans


## Build the plans of up to `max_residents` more residents; true when the day is complete.
func build_more(plans: DayPlans, max_residents: int) -> bool:
	var to := mini(count, plans.built + max_residents)
	for i in range(plans.built, to):
		_build_one(i, plans)
	plans.built = to
	return to >= count


## Every resident's plan for a day.
func build_day(day: int) -> DayPlans:
	var plans := begin_day(day)
	build_more(plans, count)
	return plans


func _build_one(i: int, plans: DayPlans) -> void:
	var day_type := plans.day_type
	var weekend := day_type != Data.DAY_WEEKDAY
	var duty := weekend_post_of(i, plans.day) if weekend else -1
	plans.duty.append(duty)
	var template_id := template_of(i, day_type, duty >= 0)
	var v := variant[i]
	var half_day := Data.half_day_on(venue_policy[i], day_type)
	# The template's day depends only on these few things, so each distinct day is built once.
	var key := template_id | (v << 5) | ((shift_index[i] + 1) << 12) | ((1 if ordinal[i] == 1 else 0) << 14) \
		| (_role_class[i] << 15) | (day_type << 17) | ((1 if half_day else 0) << 19)
	var base: PackedInt32Array
	if _templates.has(key):
		base = _templates[key]
	else:
		var shift_start: int = Data.SHIFTS[shift_index[i]].x if shift_index[i] >= 0 else -1
		base = Data.template(template_id, v, shift_start, ordinal[i], role_name(i), day_type, half_day)
		_templates[key] = base

	# The day's own generator, keyed "seed:id:day". Pace tilts the whole day by up to 6 minutes and the
	# first draw adds up to 15 minutes of jitter either way.
	var rng := Data.Rng.new(Data.hash32(plans._day_text, _prefix[i]))
	var offset := Data.js_round(pace[i] * 30.0 + (rng.next() * 30.0 - 15.0))

	# Rotate the day by the offset, splitting whatever crosses midnight (resident-plan.js rotate).
	@warning_ignore("integer_division")
	var n := base.size() / SEG
	var w := PackedInt32Array()
	w.resize((n + n) * SEG)
	var m := 0
	for k in n:
		var at := k * SEG
		var start := base[at] + offset
		var end := base[at + 1] + offset
		var c := m * SEG
		if start < 0 or end > 1440:
			var d := c + SEG
			if start < 0:
				w[c] = 0
				w[c + 1] = end
				w[d] = 1440 + start
				w[d + 1] = 1440
			else:
				w[c] = start
				w[c + 1] = 1440
				w[d] = 0
				w[d + 1] = end - 1440
			w[d + 2] = base[at + 2]
			w[d + 3] = base[at + 3]
			w[d + 4] = base[at + 4]
			m += 2
		else:
			w[c] = start
			w[c + 1] = end
			m += 1
		w[c + 2] = base[at + 2]
		w[c + 3] = base[at + 3]
		w[c + 4] = base[at + 4]
	var order := Data.sorted_order(w, m)

	# Waves, not platoons: slide each interior walk as a rigid unit; its two neighbours absorb the shift.
	for k in range(1, m - 1):
		var c := order[k] * SEG
		if w[c + 2] != Data.ST_COMMUTE:
			continue
		var p := order[k - 1] * SEG
		var x := order[k + 1] * SEG
		if w[p + 2] == Data.ST_COMMUTE or w[x + 2] == Data.ST_COMMUTE:
			continue
		var room := mini(w[p + 1] - w[p], w[x + 1] - w[x]) - MIN_SESSION
		if room <= 0:
			continue
		var d := clampi(Data.js_round((rng.next() * 2.0 - 1.0) * WALK_STAGGER), -room, room)
		if d == 0:
			continue
		w[p + 1] += d
		w[c] += d
		w[c + 1] += d
		w[x] += d

	# Resolve the symbolic places against this resident's own buildings.
	var hm := home[i]
	var places := i * TOKEN_COUNT
	var duty_place := duty if duty >= 0 else workplace[i]
	var homebound := leisure_venue[i] == LEISURE_HOME
	var closed := _closed[day_type]
	var segs := plans.segs
	for k in m:
		var c := order[k] * SEG
		var state := w[c + 2]
		var token := w[c + 3]
		var place := duty_place if token == Data.TK_DUTY else _place[places + token]
		var stays := place < 0
		if not stays:
			if weekend and place != STREET and token != Data.TK_DUTY and place != duty and closed[place] == 1:
				# A queue cannot stand inside a shut bank; anything aimed at a closed venue folds into home time.
				stays = true
			elif homebound and (state == Data.ST_LEISURE or state == Data.ST_SHOPPING or token == Data.TK_PLAZA
					or token == Data.TK_PARK or token == Data.TK_MALL or token == Data.TK_SCHOOL) \
					and not (state == Data.ST_SHOPPING and (token == Data.TK_BANK or token == Data.TK_CIVIC)):
				# No seat in the leisure ledger: outings become time indoors, but an errand is still run.
				stays = true
		segs.append(w[c])
		segs.append(w[c + 1])
		if stays:
			segs.append(Data.ST_HOME)
			segs.append(hm)
			segs.append(w[c + 4] + Data.INDOOR)
		else:
			segs.append(state)
			segs.append(place)
			segs.append(w[c + 4])
	@warning_ignore("integer_division")
	plans.first.append(segs.size() / SEG)

# ---------------------------------------------------------------- plan queries (resident-state.js)


func segment_count(plans: DayPlans, i: int) -> int:
	return plans.first[i + 1] - plans.first[i]


## One segment as a dictionary: {start, end, state, location, substate} with the state, location and
## substate as ints (Data.STATES, Data.location_name, Data.substate_name give their names).
func segment(plans: DayPlans, i: int, k: int) -> Dictionary:
	var at := (plans.first[i] + k) * SEG
	return {"start": plans.segs[at], "end": plans.segs[at + 1], "state": plans.segs[at + 2],
		"location": plans.segs[at + 3], "substate": plans.segs[at + 4]}


## A resident's whole day, for the inspect panel.
func plan(plans: DayPlans, i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in segment_count(plans, i):
		out.append(segment(plans, i, k))
	return out


## The index within resident i's plan of the segment that covers a minute of the day, or -1.
func segment_index_at(plans: DayPlans, i: int, minute: float) -> int:
	var m := Clock.js_mod(minute, 1440.0)
	var segs := plans.segs
	for s in range(plans.first[i], plans.first[i + 1]):
		if m >= segs[s * SEG] and m < segs[s * SEG + 1]:
			return s - plans.first[i]
	return -1


## What resident i is doing at a minute: {state, substate, location, state_since, until_minute}, or an
## empty dictionary if the plan does not cover the minute. A sleep that wraps midnight is reported as one
## span: state_since goes negative before 00:00 and until_minute runs past 1440.
func state_at(plans: DayPlans, i: int, minute: float) -> Dictionary:
	var k := segment_index_at(plans, i, minute)
	if k < 0:
		return {}
	var segs := plans.segs
	var head := plans.first[i] * SEG
	var tail := (plans.first[i + 1] - 1) * SEG
	var at := head + k * SEG
	var wrap_sleep := segs[head + 2] == Data.ST_SLEEPING and segs[tail + 2] == Data.ST_SLEEPING
	var since := segs[at]
	var until := segs[at + 1]
	if wrap_sleep and at == head:
		since = segs[tail] - 1440
	if wrap_sleep and at == tail:
		until = segs[head + 1] + 1440
	return {"state": segs[at + 2], "substate": segs[at + 4], "location": segs[at + 3], "state_since": since, "until_minute": until}


## The number of state changes inside the day.
func state_changes(plans: DayPlans, i: int) -> int:
	var changes := 0
	for s in range(plans.first[i] + 1, plans.first[i + 1]):
		if plans.segs[s * SEG + 2] != plans.segs[(s - 1) * SEG + 2]:
			changes += 1
	return changes


## Structure and transition checks of one plan (resident-plan.js validate): an empty list when the plan is
## a legal, fully covered day.
func validate(plans: DayPlans, i: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var from := plans.first[i]
	var n := plans.first[i + 1] - from
	if n <= 0:
		problems.append("empty plan")
		return problems
	var segs := plans.segs
	var cursor := 0
	for k in n:
		var at := (from + k) * SEG
		if segs[at + 2] < 0 or segs[at + 2] >= Data.STATES.size():
			problems.append("unknown state %d @%d" % [segs[at + 2], k])
		if segs[at] < cursor:
			problems.append("overlap @%d start %d < %d" % [k, segs[at], cursor])
		elif segs[at] > cursor:
			problems.append("uncovered minute %d->%d @%d" % [cursor, segs[at], k])
		if segs[at + 1] <= segs[at]:
			problems.append("empty segment @%d" % k)
		cursor = maxi(cursor, segs[at + 1])
	if cursor > 1440:
		problems.append("plan exceeds 1440 minutes: %d" % cursor)
	var head := from * SEG
	var tail := (from + n - 1) * SEG
	for k in n - 1:
		var a := (from + k) * SEG
		if not _allows(segs, a, a + SEG):
			problems.append("illegal transition %s->%s @%d" % [Data.STATES[segs[a + 2]], Data.STATES[segs[a + SEG + 2]], segs[a + SEG]])
	# A sleep that wraps midnight is one sleep; any other seam must be a legal transition too.
	if not (segs[head + 2] == Data.ST_SLEEPING and segs[tail + 2] == Data.ST_SLEEPING) and not _allows(segs, tail, head):
		problems.append("illegal seam transition %s->%s" % [Data.STATES[segs[tail + 2]], Data.STATES[segs[head + 2]]])
	if segs[head] != 0:
		problems.append("day starts at %d" % segs[head])
	if segs[tail + 1] != 1440:
		problems.append("day ends at %d" % segs[tail + 1])
	return problems


# A change of state is legal when the table allows it, or when both segments are in the same place
# (a ward patient walking to the treatment room needs no street segment).
func _allows(segs: PackedInt32Array, a: int, b: int) -> bool:
	if _next_mask[segs[a + 2]] & (1 << segs[b + 2]):
		return true
	return segs[b + 3] == segs[a + 3]


## Town-wide occupancy at a minute (resident-state.js occupancy):
##   street        people on a COMMUTE segment
##   per_building  people at each building, by building index
##   by_state      people in each state, by Data.ST_*
##   missing       residents whose plan does not cover the minute (always 0 for built plans)
func occupancy(plans: DayPlans, minute: float) -> Dictionary:
	var m := Clock.js_mod(minute, 1440.0)
	var per_building := PackedInt32Array()
	per_building.resize(building_count)
	var by_state := PackedInt32Array()
	by_state.resize(Data.STATES.size())
	var street := 0
	var missing := 0
	var segs := plans.segs
	var first := plans.first
	for i in plans.built:
		var found := false
		for s in range(first[i], first[i + 1]):
			var at := s * SEG
			if m >= segs[at] and m < segs[at + 1]:
				by_state[segs[at + 2]] += 1
				if segs[at + 3] == STREET:
					street += 1
				else:
					per_building[segs[at + 3]] += 1
				found = true
				break
		if not found:
			missing += 1
	return {"minute": minute, "street": street, "per_building": per_building, "by_state": by_state, "missing": missing}


## The most people at once per location over the day, sampled every `step` minutes; index Data.STREET
## carries the walking peak (resident-state.js peakOccupancy).
func peak_occupancy(plans: DayPlans, step: int = 5) -> PackedInt32Array:
	var peaks := PackedInt32Array()
	peaks.resize(building_count + 1)
	for m in range(0, 1440, step):
		var occ := occupancy(plans, m)
		var per_building: PackedInt32Array = occ["per_building"]
		for b in building_count:
			peaks[b] = maxi(peaks[b], per_building[b])
		peaks[STREET] = maxi(peaks[STREET], occ["street"])
	return peaks

# ---------------------------------------------------------------- per-building sample (town-view.js, lighting.js)

## When a building's doors stand open, by kind: [from, to] minutes (town-view.js DOOR_WINDOWS). Other
## kinds follow their open flag.
const DOOR_WINDOWS := {
	"housing": [[390, 1320]],
	"hospital": [[420, 1140]],
	"primary": [[435, 505], [945, 1010]],
	"secondary": [[405, 480], [1215, 1300]],
	"university": [[615, 690], [885, 950]],
}
const DOOR_FADE := 8.0


## Is the building open to the public? (town-view.js publicOpen) Housing, the hospital and the police post
## always; the two counters and the food street by their hours; parks and the plaza whenever the calendar
## allows; every other venue while somebody awake is inside or on the way.
func _public_open(b: int, awake: int, day_type: int, m: float, incoming: int) -> bool:
	var kind := _kind[b]
	if kind == "housing" or kind == "hospital" or kind == "precinct":
		return true
	var policy := _policy[b]
	if policy == Data.POLICY_WEEKDAY and day_type != Data.DAY_WEEKDAY:
		return false
	if policy == Data.POLICY_SAT_AM and day_type == Data.DAY_SUNDAY:
		return false
	if kind == "bank" or kind == "civic":
		var close := 840.0 if policy == Data.POLICY_SAT_AM and day_type == Data.DAY_SATURDAY else 1020.0
		return m >= 480.0 and m < close
	if kind == "night-market":
		return m >= 1080.0
	if kind == "park" or kind == "plaza":
		return true
	return awake > 0 or incoming > 0


## How far a building's doors are open, 0..1, or -1 when its kind has no door timetable.
func _door_travel(b: int, day_type: int, m: float) -> float:
	if not DOOR_WINDOWS.has(_kind[b]):
		return -1.0
	if _policy[b] == Data.POLICY_WEEKDAY and day_type != Data.DAY_WEEKDAY:
		return 0.0
	var travel := 0.0
	for window: Array in DOOR_WINDOWS[_kind[b]]:
		var from: float = window[0]
		var to: float = window[1]
		var edge := 0.0
		if m >= from and m <= to:
			edge = 1.0
		elif m >= from - DOOR_FADE and m < from:
			edge = (m - (from - DOOR_FADE)) / DOOR_FADE
		elif m > to and m <= to + DOOR_FADE:
			edge = ((to + DOOR_FADE) - m) / DOOR_FADE
		travel = maxf(travel, edge)
	return Clock.smooth01(travel)


## Everything the town shows about a minute of a built day (town-view.js sample with lighting.js sample
## on top, as upstream's sketch.js combines them):
##   day, minute, night      night is the lamp hours
##   factors                 Clock.factors(minute)
##   street, by_state, missing, per_building   as occupancy()
##   street_by_destination   people on the street by the building they are heading for (size
##                           building_count + 1; the last entry is "nowhere": a plan that is all street)
##   buildings               one dictionary per building, in Data.BUILDINGS order:
##       id, kind
##       present       resident indices, in roster order
##       count         present.size()
##       by_state      counts by Data.ST_*
##       awake, working, staff, visitors   staff are people whose workplace it is (not pupils or patients)
##       home_count    people who live there
##       open          open to the public now
##       door_open     0..1, how far the doors stand open
##       outdoor       its crowd is outdoors and can be seen (parks, plaza, amusement park, station, night
##                     market); upstream shows that crowd only while the venue is open
##       light         the share of windows lit, 0..0.82 (lighting.js "room"; what upstream draws)
##       max_panes     1 when shut with somebody on duty inside, else -1 (no limit)
##       entry, facade, decoration   Clock.window_rule
##       activity_light    town-view.js's own light level 0..1 (upstream overwrites it with `light`)
func sample(plans: DayPlans, minute: float) -> Dictionary:
	var m := Clock.js_mod(minute, 1440.0)
	var day_type := plans.day_type
	var night := Clock.is_night(m)
	var dark := maxf(1.0 - Clock.daylight(m), 0.15 if night else 0.0)
	var n := building_count
	var state_count := Data.STATES.size()
	# Where each resident is (a building index, or -1 on the street or missing), and counts by building and state.
	var where_of := PackedInt32Array()
	where_of.resize(plans.built)
	where_of.fill(-1)
	var states := PackedInt32Array()
	states.resize(n * state_count)
	var awake := PackedInt32Array()
	awake.resize(n)
	var working := PackedInt32Array()
	working.resize(n)
	var staff := PackedInt32Array()
	staff.resize(n)
	var awake_home := PackedInt32Array()
	awake_home.resize(n)
	var heading := PackedInt32Array()
	heading.resize(n + 1)
	var by_state := PackedInt32Array()
	by_state.resize(Data.STATES.size())
	var per_building := PackedInt32Array()
	per_building.resize(n)
	var street := 0
	var missing := 0
	var segs := plans.segs
	var first := plans.first
	for i in plans.built:
		var from := first[i]
		var to := first[i + 1]
		var found := -1
		for s in range(from, to):
			if m >= segs[s * SEG] and m < segs[s * SEG + 1]:
				found = s
				break
		if found < 0:
			missing += 1
			continue
		var at := found * SEG
		var state := segs[at + 2]
		var where := segs[at + 3]
		by_state[state] += 1
		if where == STREET:
			street += 1
			# Where the walk leads: the next segment that is not the street, around the day's end if need be.
			var target := STREET
			var count_here := to - from
			for step in range(1, count_here + 1):
				var candidate := segs[(from + (found - from + step) % count_here) * SEG + 3]
				if candidate != STREET:
					target = candidate
					break
			heading[target] += 1
			continue
		per_building[where] += 1
		where_of[i] = where
		states[where * state_count + state] += 1
		if state != Data.ST_SLEEPING:
			awake[where] += 1
			if home[i] == where:
				awake_home[where] += 1
		if state == Data.ST_AT_WORK:
			working[where] += 1
		if workplace[i] == where and _staff_role[i] == 1:
			staff[where] += 1
	# The residents present per building, in roster order: a counting sort into one list, then slices.
	var offset := PackedInt32Array()
	offset.resize(n + 1)
	for b in n:
		offset[b + 1] = offset[b] + per_building[b]
	var fill := offset.duplicate()
	var sorted := PackedInt32Array()
	sorted.resize(offset[n])
	for i in plans.built:
		var where := where_of[i]
		if where >= 0:
			sorted[fill[where]] = i
			fill[where] += 1
	var buildings: Array[Dictionary] = []
	for b in n:
		var total := per_building[b]
		var open := _public_open(b, awake[b], day_type, m, heading[b])
		var travel := _door_travel(b, day_type, m)
		var kind := _kind[b]
		var capacity := float(maxi(1, _capacity[b]))
		var activity := 0.0
		if kind == "housing":
			activity = float(awake_home[b]) / maxi(1, homes[b].size())
		elif kind == "hospital":
			# A sleeping ward keeps a small care light; working staff carry the stronger signal.
			if total > 0:
				activity = 0.12 + 0.6 * working[b] / maxi(1, total) + 0.2 * total / capacity
		elif not open:
			if awake[b] > 0:
				activity = minf(0.08, 0.025 + awake[b] / capacity * 0.08)
		elif awake[b] > 0:
			activity = 0.18 + 0.82 * awake[b] / capacity
		var light := Clock.window_rule(kind, _capacity[b], open, total, awake[b], m, _owl[b])
		buildings.append({
			"id": Data.BUILDINGS[b]["id"], "kind": kind, "present": sorted.slice(offset[b], offset[b + 1]), "count": total,
			"by_state": states.slice(b * state_count, (b + 1) * state_count),
			"awake": awake[b], "working": working[b], "staff": staff[b], "visitors": total - staff[b],
			"home_count": homes[b].size(), "open": open, "door_open": travel if travel >= 0.0 else (1.0 if open else 0.0),
			"outdoor": Data.OUTDOOR_KINDS.has(kind), "light": light["room"], "max_panes": light["max_panes"],
			"entry": light["entry"], "facade": light["facade"], "decoration": light["decoration"],
			"activity_light": clampf(activity * dark, 0.0, 1.0),
		})
	return {"day": plans.day, "minute": m, "night": night, "factors": Clock.factors(m), "street": street,
		"by_state": by_state, "missing": missing, "per_building": per_building, "street_by_destination": heading,
		"buildings": buildings}
