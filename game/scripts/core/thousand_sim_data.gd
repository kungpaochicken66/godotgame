## Thousand Town: the tables and deterministic primitives of the resident simulation
## (design/thousand-town.md, sections 2 and 5). Pure data and static functions, no nodes.
##
## Ported from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY (github.com/YiHuiShiBY/thousand-town,
## commit 1332ef2, CC BY 4.0): city-random.js, city-life-ext/resident.js (census, buildings),
## resident-name.js (the Chinese name pools) and resident-schedule.js (the 23 day templates). Changed for
## Lantern Lane: GDScript, integer ids instead of strings, packed arrays, and name pools of our own for the
## five other locales. tests/thousand_sim_tests.gd proves parity with fixtures produced by upstream's code
## (scripts/thousand_town/sim_fixtures.mjs).
##
##   Rng, hash32      mulberry32 and FNV-1a exactly as upstream's JavaScript computes them (32-bit wrap).
##   CENSUS           20 roles, exactly 1000 residents. Only the 1000-resident town is ported (upstream can
##                    scale the census; Lantern Lane never does).
##   BUILDINGS        the 31 ledger buildings; a building's index in this list is its location id, and
##                    STREET (= 31) is "on the street".
##   template()       one day of symbolic segments for a template, a habit draw and a small context.
##   NAME_POOLS       our own given and family names for en, ja, es, fr and de; zh-CN uses upstream's pools.
##
## A segment is five ints: start minute, end minute, state (ST_*), place and substate. In a template the
## place is a symbolic token (TK_*); thousand_sim.gd resolves it to a location id.
## extract_strings: per-locale data, not UI text
extends RefCounted

const SEED := 20260818
const MINUTES_PER_DAY := 1440
## Ints per segment in every packed segment list.
const SEG := 5

# ---------------------------------------------------------------- states, tokens, substates

enum { ST_HOME, ST_COMMUTE, ST_AT_WORK, ST_LEISURE, ST_MEDICAL, ST_SHOPPING, ST_DINING, ST_SLEEPING }
const STATES := ["HOME", "COMMUTE", "AT_WORK", "LEISURE", "MEDICAL", "SHOPPING", "DINING", "SLEEPING"]

enum { TK_HOME, TK_WORK, TK_STREET, TK_PLAZA, TK_PARK, TK_MALL, TK_SCHOOL, TK_ANNEX, TK_MARKET, TK_NIGHT, TK_CLINIC,
	TK_BANK, TK_CIVIC, TK_POST, TK_DUTY, TK_AMUSEMENT }
const TOKENS := ["HOME", "WORK", "STREET", "PLAZA", "PARK", "MALL", "SCHOOL", "ANNEX", "MARKET", "NIGHT", "CLINIC",
	"BANK", "CIVIC", "POST", "DUTY", "AMUSEMENT"]

## What a resident is doing inside a state. 0 is "nothing in particular" (upstream's null). A substate that
## was folded into home time (an outing that could not happen) is the same id plus INDOOR: "stroll" becomes
## "indoor-stroll", and 0 becomes "indoor".
const SUBSTATES := ["", "after-school", "afternoon", "afternoon-off", "arcade", "balanceday", "board-games",
	"boxed-meal", "brunch", "canteen", "check-up", "class", "collection", "corridor", "counter", "desk", "driving",
	"duty", "duty-meal", "errand", "evening-play", "evening-study", "family-breakfast", "food-court", "grocery",
	"homework", "labour", "leisure", "lesson-prep", "lunch", "maintenance", "morning-exercise", "nap", "night-snack",
	"office", "patrol", "pension", "pick-up", "playground", "prep", "reception", "records", "rest", "retail", "ride",
	"rides", "riverfront", "rounds", "school-gate", "set-up", "shopping", "square-dance", "staff-meal", "stall",
	"stall-breakfast", "stall-leftovers", "street-food", "stroll", "stroller", "supper", "takings", "transfer",
	"treatment", "tv", "visiting", "wake", "walk", "ward-meal", "ward-rest", "welfare-queue", "wholesale",
	"with-the-kids", "yard", "yard-breakfast"]
const INDOOR := 74

static var _sub_ids := {}


static func substate_id(name: String) -> int:
	if _sub_ids.is_empty():
		for i in SUBSTATES.size():
			_sub_ids[SUBSTATES[i]] = i
	return _sub_ids[name]


static func substate_name(id: int) -> String:
	if id < INDOOR:
		return SUBSTATES[id]
	return "indoor" if id == INDOOR else "indoor-" + SUBSTATES[id - INDOOR]

# ---------------------------------------------------------------- the week and opening policies

## Day types (daily-clock.js dayType): day 1 is a Monday, day 6 a Saturday, day 7 a Sunday.
enum { DAY_WEEKDAY, DAY_SATURDAY, DAY_SUNDAY }
const DAY_TYPES := ["weekday", "saturday", "sunday"]

## A building's weekend policy: open every day, shut on both weekend days, or open on Saturday morning only.
enum { POLICY_DAILY, POLICY_WEEKDAY, POLICY_SAT_AM }
const POLICIES := ["daily", "weekday", "sat-am"]

## The three 8-hour shifts of rotating staff (start, end): early 08-16, mid 16-24, night 00-08.
const SHIFTS := [Vector2i(480, 960), Vector2i(960, 1440), Vector2i(0, 480)]


## Is a building with this policy shut for the whole of this day? (resident-schedule.js closesOn)
static func closes_on(policy: int, day_type: int) -> bool:
	if day_type == DAY_WEEKDAY:
		return false
	if policy == POLICY_WEEKDAY:
		return true
	return policy == POLICY_SAT_AM and day_type == DAY_SUNDAY


static func half_day_on(policy: int, day_type: int) -> bool:
	return policy == POLICY_SAT_AM and day_type == DAY_SATURDAY

# ---------------------------------------------------------------- random numbers

## JavaScript's Math.imul for two values in 0..2^32-1: the low 32 bits of the product, unsigned.
## The product is split into 16-bit halves so it never leaves 64 bits.
static func imul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


## JavaScript's Math.round for the values used here: halves round up (toward +infinity), not away from zero.
static func js_round(x: float) -> int:
	return floori(x + 0.5)


## FNV-1a over the string's UTF-16 code units (resident-plan.js hash32). All keys are in the basic
## multilingual plane, where a code unit is a code point. `h` continues a hash, so a key's fixed prefix
## can be hashed once.
static func hash32(text: String, h: int = 0x811C9DC5) -> int:
	for i in text.length():
		h = ((h ^ text.unicode_at(i)) * 0x01000193) & 0xFFFFFFFF
	return h


## mulberry32 (city-random.js randomGenerator): the same sequence as upstream for the same seed.
class Rng:
	var state: int

	func _init(p_seed: int) -> void:
		state = p_seed & 0xFFFFFFFF

	## The next value as the 32-bit numerator.
	func next_u32() -> int:
		state = (state + 0x6D2B79F5) & 0xFFFFFFFF
		var a := state ^ (state >> 15)
		var b := state | 1
		var v := (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF
		a = v ^ (v >> 7)
		b = v | 61
		v ^= (v + ((a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return (v ^ (v >> 14)) & 0xFFFFFFFF

	## The next value in [0, 1).
	func next() -> float:
		return float(next_u32()) / 4294967296.0

# ---------------------------------------------------------------- census and buildings

## role, headcount, inclusive age band, the kinds of building the role works (or studies) in, the headcount
## per kind where that is a decision ("quota"; otherwise the buildings of the kinds take turns), and
## whether the role rotates through the three shifts. Sums to exactly 1000 (resident.js:45-82).
const CENSUS := [
	{"role": "preschooler", "count": 40, "age": [1, 5], "work": [], "quota": {}, "shift": false},
	{"role": "student-p", "count": 80, "age": [6, 12], "work": ["primary"], "quota": {}, "shift": false},
	{"role": "student-m", "count": 50, "age": [13, 17], "work": ["secondary"], "quota": {}, "shift": false},
	{"role": "student-u", "count": 70, "age": [18, 22], "work": ["university"], "quota": {}, "shift": false},
	{"role": "office", "count": 150, "age": [23, 55], "work": ["tower"], "quota": {}, "shift": false},
	{"role": "worker", "count": 105, "age": [23, 50], "work": ["workshop", "depot", "market"],
		"quota": {"workshop": 45, "depot": 20, "market": 40}, "shift": false},
	{"role": "shopkeeper", "count": 60, "age": [25, 55], "work": ["mall", "annex-mall", "night-market"],
		"quota": {"mall": 35, "annex-mall": 15, "night-market": 10}, "shift": false},
	{"role": "driver", "count": 30, "age": [25, 55], "work": ["station", "depot"],
		"quota": {"station": 18, "depot": 12}, "shift": false},
	{"role": "teacher", "count": 24, "age": [25, 55], "work": ["primary", "secondary", "university"],
		"quota": {"primary": 8, "secondary": 10, "university": 6}, "shift": false},
	{"role": "school-admin", "count": 6, "age": [28, 55], "work": ["primary", "secondary", "university"],
		"quota": {"primary": 2, "secondary": 2, "university": 2}, "shift": false},
	{"role": "medical-doc", "count": 20, "age": [28, 60], "work": ["hospital"], "quota": {}, "shift": true},
	{"role": "medical-nurse", "count": 30, "age": [22, 50], "work": ["hospital"], "quota": {}, "shift": true},
	{"role": "hosp-admin", "count": 5, "age": [25, 55], "work": ["hospital"], "quota": {}, "shift": false},
	{"role": "officer", "count": 8, "age": [23, 45], "work": ["precinct"], "quota": {}, "shift": true},
	{"role": "clerk", "count": 22, "age": [23, 55], "work": ["bank", "civic"],
		"quota": {"bank": 10, "civic": 12}, "shift": false},
	{"role": "sanitation", "count": 10, "age": [25, 55], "work": ["waste"], "quota": {}, "shift": true},
	{"role": "unemployed", "count": 10, "age": [18, 22], "work": [], "quota": {}, "shift": false},
	{"role": "patient", "count": 30, "age": [5, 85], "work": ["hospital"], "quota": {}, "shift": false},
	{"role": "retiree", "count": 190, "age": [56, 70], "work": [], "quota": {}, "shift": false},
	{"role": "senior", "count": 60, "age": [71, 90], "work": [], "quota": {}, "shift": false},
]
const POPULATION := 1000

## The roles whose members get a seat in the leisure ledger (resident.js:399).
const LEDGER_ROLES := ["retiree", "senior", "student-u", "unemployed"]
## The leisure ledger fills venues of these kinds in this order, up to 85% of each one's capacity.
const VENUE_ORDER := ["plaza", "park", "library", "amusement"]
const VENUE_FILL := 0.85

## The 31 ledger buildings of the 1000-resident town (resident.js defaultBuildings). `cap` is the peak
## number of people at once (for housing, the number of residents); `open` the weekend policy;
## `annex_of` the building an annex belongs to; `clinic` a housing block's own ground-floor clinic.
const BUILDINGS := [
	{"id": "h-courtyard", "kind": "housing", "type": "courtyard", "cap": 12, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "h-slab", "kind": "housing", "type": "slab", "cap": 350, "open": POLICY_DAILY, "annex_of": "", "clinic": "i-clinic-a"},
	{"id": "h-terrace", "kind": "housing", "type": "terrace", "cap": 178, "open": POLICY_DAILY, "annex_of": "", "clinic": "i-clinic-b"},
	{"id": "h-point", "kind": "housing", "type": "point", "cap": 430, "open": POLICY_DAILY, "annex_of": "", "clinic": "i-clinic-c"},
	{"id": "c-hospital", "kind": "hospital", "type": "", "cap": 100, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-primary", "kind": "primary", "type": "", "cap": 200, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "c-secondary", "kind": "secondary", "type": "", "cap": 260, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "c-university", "kind": "university", "type": "", "cap": 300, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "c-library", "kind": "library", "type": "", "cap": 90, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "i-workshop", "kind": "workshop", "type": "", "cap": 60, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "i-depot", "kind": "depot", "type": "", "cap": 55, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "i-market", "kind": "market", "type": "", "cap": 90, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "i-clinic-a", "kind": "clinic", "type": "", "cap": 16, "open": POLICY_DAILY, "annex_of": "h-slab", "clinic": ""},
	{"id": "i-clinic-b", "kind": "clinic", "type": "", "cap": 16, "open": POLICY_DAILY, "annex_of": "h-terrace", "clinic": ""},
	{"id": "i-clinic-c", "kind": "clinic", "type": "", "cap": 16, "open": POLICY_DAILY, "annex_of": "h-point", "clinic": ""},
	{"id": "c-precinct", "kind": "precinct", "type": "", "cap": 8, "open": POLICY_DAILY, "annex_of": "c-primary", "clinic": ""},
	{"id": "i-waste", "kind": "waste", "type": "", "cap": 12, "open": POLICY_DAILY, "annex_of": "i-depot", "clinic": ""},
	{"id": "c-mall", "kind": "mall", "type": "", "cap": 150, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-annex-mall", "kind": "annex-mall", "type": "", "cap": 90, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-night-market", "kind": "night-market", "type": "", "cap": 140, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-civic", "kind": "civic", "type": "", "cap": 40, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "c-station", "kind": "station", "type": "", "cap": 80, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-amusement", "kind": "amusement", "type": "", "cap": 60, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-plaza", "kind": "plaza", "type": "", "cap": 100, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-park-a", "kind": "park", "type": "", "cap": 90, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "c-park-b", "kind": "park", "type": "", "cap": 90, "open": POLICY_DAILY, "annex_of": "", "clinic": ""},
	{"id": "t-one", "kind": "tower", "type": "", "cap": 90, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "t-two", "kind": "tower", "type": "", "cap": 90, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "t-three", "kind": "tower", "type": "", "cap": 90, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "t-four", "kind": "tower", "type": "", "cap": 90, "open": POLICY_WEEKDAY, "annex_of": "", "clinic": ""},
	{"id": "c-bank", "kind": "bank", "type": "", "cap": 48, "open": POLICY_SAT_AM, "annex_of": "t-two", "clinic": ""},
]
## The location id of "on the street"; building location ids are 0..30.
const STREET := 31

## The two malls keep a guard at the door on a weekend even though they are open (resident-plan.js:147).
const SECURITY_POSTS := ["c-mall", "c-annex-mall"]

## Kinds whose crowd is outdoors, where the figures can be seen (town-view.js:201).
const OUTDOOR_KINDS := ["park", "plaza", "amusement", "station", "night-market"]


static func location_name(location: int) -> String:
	return "street" if location == STREET else str(BUILDINGS[location]["id"])

# ---------------------------------------------------------------- names

## Upstream's Chinese pools, exactly (resident-name.js:17-51): 100 surnames, the surname initials for the
## pinyin sort key, and whole given names with their pinyin initials in three eras by gender.
## The Chinese pools live in thousand_town/data/names_cjk.json (scripts/check.py keeps CJK text out of source
## files): ZH_SURNAMES, ZH_PINYIN_INITIAL and ZH_GIVEN below are read from it once, unchanged.
const CJK_NAMES_PATH := "res://thousand_town/data/names_cjk.json"
static var _cjk: Dictionary = _load_cjk()
static var ZH_SURNAMES: String = _cjk["zh_surnames"]
static var ZH_PINYIN_INITIAL: String = _cjk["zh_pinyin_initial"]
static var ZH_GIVEN: Array = _cjk["zh_given"]


static func _load_cjk() -> Dictionary:
	var f := FileAccess.open(CJK_NAMES_PATH, FileAccess.READ)
	assert(f != null, "missing " + CJK_NAMES_PATH)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	return d
## Tiers by age: 50 and over "old", 27 and over "mid", younger "young" (resident-name.js tierForAge).
## How often a tier's name is a single character.
const ZH_SINGLE_RATE := [0.3, 0.22, 0.12]


static func zh_tier(age: int) -> int:
	return 0 if age >= 50 else (1 if age >= 27 else 2)


## Every character the zh-CN names can use, for the font subset.
static func zh_name_characters() -> String:
	var seen := {}
	for c in ZH_SURNAMES:
		seen[c] = true
	for tier: Array in ZH_GIVEN:
		for pool: String in tier:
			for c in pool:
				if c.unicode_at(0) > 0x7F:
					seen[c] = true
	return "".join(seen.keys())


## Lantern Lane's own small name pools for the other five locales: 32 given names per gender and 32
## family names each. Japanese names are in hiragana, which the game's font subset always carries.
## A resident's name is a fixed function of their place in the roster (thousand_sim.gd name_of), and
## all 1000 names of a locale are different.
const _NAME_POOLS_SOURCE := {
	"en": {
		"male": ["Liam", "Noah", "Oliver", "Ethan", "Lucas", "Mason", "Logan", "Henry", "Jack", "Leo", "Owen",
			"Wyatt", "Caleb", "Isaac", "Nathan", "Eli", "Adam", "Miles", "Felix", "Theo", "Max", "Sam", "Ben", "Finn",
			"Hugo", "Oscar", "Jude", "Ezra", "Reid", "Cole", "Dean", "Luke"],
		"female": ["Emma", "Olivia", "Ava", "Mia", "Sophia", "Isla", "Ella", "Grace", "Chloe", "Lily", "Zoe", "Ruby",
			"Nora", "Hazel", "Alice", "Clara", "Lucy", "Ivy", "Maya", "Anna", "Rose", "Eva", "Leah", "Sadie", "Tessa",
			"Wren", "June", "Faye", "Hope", "Iris", "Jade", "Kate"],
		"family": ["Baker", "Carter", "Brooks", "Hayes", "Fisher", "Mills", "Parker", "Reed", "Turner", "Wood",
			"Bell", "Hill", "Stone", "Lane", "Gray", "Fox", "Marsh", "Dale", "Ford", "Webb", "Price", "Shaw", "Hart",
			"Rowe", "Page", "West", "Frost", "Nash", "Pike", "Wells", "Finch", "Abbott"],
	},
	"es": {
		"male": ["Mateo", "Hugo", "Martín", "Lucas", "Leo", "Daniel", "Pablo", "Álvaro", "Adrián", "Diego", "Mario",
			"Bruno", "Marcos", "Javier", "Sergio", "Carlos", "Miguel", "Antonio", "Manuel", "Rafael", "Andrés", "Tomás",
			"Gabriel", "Iván", "Rubén", "Jorge", "Luis", "Pedro", "Raúl", "Samuel", "Víctor", "Óscar"],
		"female": ["Lucía", "Sofía", "Martina", "María", "Paula", "Julia", "Emma", "Valeria", "Daniela", "Alba", "Sara",
			"Carmen", "Noa", "Claudia", "Elena", "Irene", "Laura", "Marta", "Ana", "Isabel", "Rosa", "Pilar", "Teresa",
			"Lola", "Inés", "Nuria", "Clara", "Vera", "Olivia", "Carla", "Alicia", "Marina"],
		"family": ["García", "López", "Martínez", "Sánchez", "Pérez", "Gómez", "Fernández", "Ruiz", "Díaz", "Moreno",
			"Muñoz", "Álvarez", "Romero", "Navarro", "Torres", "Ramos", "Gil", "Serrano", "Molina", "Blanco", "Castro",
			"Ortega", "Rubio", "Marín", "Sanz", "Iglesias", "Medina", "Cortés", "Castillo", "Garrido", "Santos", "Lozano"],
	},
	"fr": {
		"male": ["Lucas", "Louis", "Gabriel", "Léo", "Raphaël", "Arthur", "Jules", "Hugo", "Adam", "Maël", "Paul",
			"Nathan", "Tom", "Noé", "Théo", "Sacha", "Victor", "Antoine", "Pierre", "Julien", "Nicolas", "Olivier",
			"Marc", "Luc", "Henri", "Michel", "Alain", "Bernard", "André", "René", "Yves", "Émile"],
		"female": ["Emma", "Jade", "Louise", "Alice", "Chloé", "Lina", "Rose", "Léa", "Anna", "Mila", "Inès", "Manon",
			"Camille", "Sarah", "Zoé", "Juliette", "Lucie", "Clara", "Marie", "Sophie", "Claire", "Hélène", "Anne",
			"Céline", "Élise", "Margot", "Nina", "Agathe", "Jeanne", "Colette", "Odile", "Simone"],
		"family": ["Martin", "Dubois", "Thomas", "Robert", "Richard", "Petit", "Durand", "Leroy", "Moreau", "Simon",
			"Laurent", "Lefebvre", "Garnier", "Fontaine", "Rousseau", "Bertrand", "Roux", "Vincent", "Fournier", "Morel",
			"Girard", "Mercier", "Dupont", "Lambert", "Bonnet", "François", "Blanc", "Guérin", "Faure", "Chevalier",
			"Marchand", "Dumas"],
	},
	"de": {
		"male": ["Ben", "Paul", "Leon", "Finn", "Elias", "Jonas", "Luis", "Noah", "Felix", "Lukas", "Max", "Emil",
			"Anton", "Jakob", "Oskar", "Moritz", "Jan", "Tim", "Niklas", "David", "Stefan", "Thomas", "Michael",
			"Andreas", "Klaus", "Peter", "Hans", "Jürgen", "Wolfgang", "Dieter", "Uwe", "Karl"],
		"female": ["Mia", "Emma", "Hannah", "Sofia", "Anna", "Lea", "Lina", "Marie", "Mila", "Emilia", "Clara", "Ida",
			"Frieda", "Greta", "Lotte", "Paula", "Julia", "Sabine", "Petra", "Monika", "Ursula", "Renate", "Karin",
			"Heike", "Birgit", "Anja", "Katrin", "Helga", "Ingrid", "Gisela", "Erika", "Martha"],
		"family": ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Schulz",
			"Hoffmann", "Koch", "Bauer", "Richter", "Klein", "Wolf", "Schröder", "Neumann", "Schwarz", "Zimmermann",
			"Braun", "Krüger", "Hofmann", "Hartmann", "Lange", "Werner", "Krause", "Lehmann", "Köhler", "Maier", "Vogel",
			"Keller", "Jung"],
	},
}
## Every locale's pools: the source table plus the Japanese pools from names_cjk.json.
static var NAME_POOLS: Dictionary = _all_pools()


static func _all_pools() -> Dictionary:
	var d := _NAME_POOLS_SOURCE.duplicate(true)
	d["ja"] = _load_cjk()["ja"]
	return d
## Locales whose names put the family name first.
const FAMILY_FIRST := ["ja"]
const NAME_POOL_SIZE := 32

# ---------------------------------------------------------------- day templates

enum { T_OFFICE, T_WORKER, T_SHOPKEEPER, T_DRIVER, T_MARKET_EARLY, T_NIGHT_MARKET, T_STUDENT_P, T_STUDENT_M,
	T_TEACHER, T_STUDENT_U, T_SHIFT, T_SHIFT_NIGHT, T_PATIENT, T_VISITOR, T_RETIREE, T_SENIOR, T_CHILD, T_IDLER,
	T_PRECINCT, T_CLERK, T_SANITATION, T_WEEKEND, T_DUTY }
const TEMPLATES := ["office", "worker", "shopkeeper", "driver", "market-early", "night-market", "student-p",
	"student-m", "teacher", "student-u", "shift", "shift-night", "patient", "visitor", "retiree", "senior", "child",
	"idler", "precinct", "clerk", "sanitation", "weekend", "duty"]

## role -> template (resident-schedule.js ROLE_TEMPLATE). "visitor" is a template without a census role.
const ROLE_TEMPLATE := {
	"preschooler": T_CHILD, "student-p": T_STUDENT_P, "student-m": T_STUDENT_M, "student-u": T_STUDENT_U,
	"teacher": T_TEACHER, "school-admin": T_OFFICE, "office": T_OFFICE, "worker": T_WORKER,
	"shopkeeper": T_SHOPKEEPER, "driver": T_DRIVER, "medical-doc": T_SHIFT, "medical-nurse": T_SHIFT,
	"hosp-admin": T_OFFICE, "officer": T_PRECINCT, "clerk": T_CLERK, "sanitation": T_SANITATION,
	"patient": T_PATIENT, "visitor": T_VISITOR, "retiree": T_RETIREE, "senior": T_SENIOR, "unemployed": T_IDLER,
}

## The weekend template branches by these classes of role.
enum { ROLE_ADULT, ROLE_KID, ROLE_STUDENT_U }


static func role_class(role: String) -> int:
	if role == "preschooler" or role == "student-p" or role == "student-m":
		return ROLE_KID
	return ROLE_STUDENT_U if role == "student-u" else ROLE_ADULT


## The day shape for one resident (resident-schedule.js templateFor): the role's template, then the
## overrides that come from where they work and from the week. `shift_index` is -1 without a shift;
## `on_duty` says the resident minds a shut building today.
static func template_for(role: String, shift_index: int, workplace_kind: String, policy: int, day_type: int, on_duty: bool) -> int:
	var id: int = ROLE_TEMPLATE[role]
	if on_duty:
		return T_DUTY
	if id == T_SHIFT and shift_index == 2:
		id = T_SHIFT_NIGHT
	if workplace_kind == "market":
		return T_MARKET_EARLY
	if workplace_kind == "night-market":
		return T_NIGHT_MARKET
	if closes_on(policy, day_type):
		return T_WEEKEND
	return id


static func _g(a: PackedInt32Array, start: int, end: int, state: int, token: int, sub: String = "") -> void:
	a.append(start)
	a.append(end)
	a.append(state)
	a.append(token)
	a.append(substate_id(sub))


static func _walk(a: PackedInt32Array, start: int, end: int) -> void:
	_g(a, start, end, ST_COMMUTE, TK_STREET, "walk")


static func _ride(a: PackedInt32Array, start: int, end: int) -> void:
	_g(a, start, end, ST_COMMUTE, TK_STREET, "ride")


## A stable sort of 5-int records by their first int: the order of the records' indices.
## JavaScript's Array.sort is stable, so equal starts keep their order; this is the same.
static func sorted_order(a: PackedInt32Array, count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	order.resize(count)
	for i in count:
		var key := a[i * SEG]
		var j := i
		while j > 0 and a[order[j - 1] * SEG] > key:
			order[j] = order[j - 1]
			j -= 1
		order[j] = i
	return order


## Assemble a full day (resident-schedule.js day): the sleep that wraps midnight (none when sleep_from is
## -1) plus the awake chain, sorted, with gaps filled as home time and overlaps trimmed.
static func _day(sleep_from: int, sleep_to: int, awake: PackedInt32Array) -> PackedInt32Array:
	var a := awake.duplicate()
	if sleep_from >= 0:
		var to := sleep_to
		if to < sleep_from:
			to += 1440
		if to > 1440:
			_g(a, 0, to - 1440, ST_SLEEPING, TK_HOME)
			_g(a, sleep_from, 1440, ST_SLEEPING, TK_HOME)
		else:
			_g(a, sleep_from, to, ST_SLEEPING, TK_HOME)
	@warning_ignore("integer_division")
	var count := a.size() / SEG
	var order := sorted_order(a, count)
	var filled := PackedInt32Array()
	var cursor := 0
	for k in count:
		var at := order[k] * SEG
		var s_start := a[at]
		var s_end := a[at + 1]
		if s_start > cursor:
			_g(filled, cursor, s_start, ST_HOME, TK_HOME)
		var start := maxi(s_start, cursor)
		if s_end > start:
			filled.append(start)
			filled.append(s_end)
			filled.append(a[at + 2])
			filled.append(a[at + 3])
			filled.append(a[at + 4])
		cursor = maxi(cursor, s_end)
	if cursor < 1440:
		_g(filled, cursor, 1440, ST_HOME, TK_HOME)
	return filled


## One day of symbolic segments (resident-schedule.js TEMPLATES).
##   v            the resident's stable habit draw, 0..99
##   shift_start  the start minute of the resident's shift window (480, 960 or 0), or -1 without a shift
##   ordinal      the resident's number within the role, from 1
##   role, day_type, half_day   as buildDay passes them
static func template(id: int, v: int, shift_start: int, ordinal: int, role: String, day_type: int, half_day: bool) -> PackedInt32Array:
	var a := PackedInt32Array()
	match id:
		T_OFFICE:
			var late := (v % 3) * 30
			_g(a, 420, 510, ST_HOME, TK_HOME, "wake")
			_walk(a, 510, 540)
			_g(a, 540, 720, ST_AT_WORK, TK_WORK, "office")
			_g(a, 720, 780, ST_DINING, TK_WORK, "canteen")
			if v >= 40 and v < 50:
				_g(a, 780, 850, ST_AT_WORK, TK_WORK, "office")
				_walk(a, 850, 870)
				_g(a, 870, 930, ST_SHOPPING, TK_BANK if v % 2 else TK_CIVIC, "errand")
				_walk(a, 930, 950)
				_g(a, 950, 1080, ST_AT_WORK, TK_WORK, "office")
			else:
				_g(a, 780, 1080, ST_AT_WORK, TK_WORK, "office")
			if v < 20:
				_walk(a, 1080, 1125)
				_g(a, 1125, 1245 + late, ST_DINING, TK_NIGHT, "night-snack")
				_walk(a, 1245 + late, 1290 + late)
			else:
				_walk(a, 1080, 1110)
				_g(a, 1110, 1170, ST_HOME, TK_HOME)
				_g(a, 1170, 1230, ST_DINING, TK_HOME)
				_g(a, 1230, 1320, ST_HOME, TK_HOME, "leisure")
			return _day(1320, 420, a)
		T_WORKER:
			var late := (v % 3) * 30
			_g(a, 390, 450, ST_HOME, TK_HOME, "wake")
			_ride(a, 450, 480)
			_g(a, 480, 720, ST_AT_WORK, TK_WORK, "labour")
			_g(a, 720, 780, ST_DINING, TK_WORK, "canteen")
			_g(a, 780, 1050, ST_AT_WORK, TK_WORK, "labour")
			if v < 35:
				_ride(a, 1050, 1095)
				_g(a, 1095, 1230 + late, ST_DINING, TK_NIGHT, "night-snack")
				_walk(a, 1230 + late, 1275 + late)
			else:
				_ride(a, 1050, 1080)
				_g(a, 1080, 1160, ST_HOME, TK_HOME)
				_g(a, 1160, 1220, ST_DINING, TK_HOME)
				_g(a, 1220, 1290, ST_HOME, TK_HOME, "leisure")
			return _day(1290, 390, a)
		T_SHOPKEEPER:
			_g(a, 360, 450, ST_HOME, TK_HOME, "wake")
			_walk(a, 450, 510)
			if v >= 22:
				_g(a, 510, 750, ST_AT_WORK, TK_WORK, "reception")
			else:
				_g(a, 510, 600, ST_AT_WORK, TK_WORK, "reception")
				_walk(a, 600, 620)
				_g(a, 620, 670, ST_SHOPPING, TK_BANK, "takings")
				_walk(a, 670, 690)
				_g(a, 690, 750, ST_AT_WORK, TK_WORK, "reception")
			_g(a, 750, 795, ST_DINING, TK_WORK, "canteen")
			_g(a, 795, 1260, ST_AT_WORK, TK_WORK, "reception")
			_walk(a, 1260, 1305)
			_g(a, 1305, 1350, ST_HOME, TK_HOME)
			return _day(1350, 360, a)
		T_DRIVER:
			_g(a, 360, 390, ST_HOME, TK_HOME, "wake")
			_ride(a, 390, 420)
			_g(a, 420, 720, ST_AT_WORK, TK_WORK, "driving")
			_g(a, 720, 870, ST_HOME, TK_HOME, "rest")
			_ride(a, 870, 900)
			_g(a, 900, 1230, ST_AT_WORK, TK_WORK, "driving")
			_g(a, 1230, 1290, ST_HOME, TK_HOME)
			return _day(1290, 360, a)
		T_MARKET_EARLY:
			if v >= 50:
				_g(a, 390, 420, ST_HOME, TK_HOME, "wake")
				_ride(a, 420, 450)
				_g(a, 450, 690, ST_AT_WORK, TK_WORK, "retail")
				_ride(a, 690, 720)
				_g(a, 720, 840, ST_HOME, TK_HOME, "rest")
				_walk(a, 840, 870)
				_g(a, 870, 1020, ST_LEISURE, TK_PLAZA, "afternoon")
				_walk(a, 1020, 1050)
				_g(a, 1050, 1110, ST_DINING, TK_HOME)
				_g(a, 1110, 1320, ST_HOME, TK_HOME, "leisure")
				return _day(1320, 390, a)
			_g(a, 180, 210, ST_HOME, TK_HOME, "wake")
			_ride(a, 210, 240)
			_g(a, 240, 420, ST_AT_WORK, TK_WORK, "wholesale")
			_g(a, 420, 450, ST_DINING, TK_WORK, "stall-breakfast")
			_g(a, 450, 480, ST_AT_WORK, TK_WORK, "wholesale")
			_ride(a, 480, 510)
			_g(a, 510, 660, ST_SLEEPING, TK_HOME, "nap")
			_g(a, 660, 720, ST_HOME, TK_HOME)
			_walk(a, 720, 750)
			_g(a, 750, 930, ST_LEISURE, TK_PLAZA, "afternoon")
			_walk(a, 930, 960)
			_g(a, 960, 1050, ST_HOME, TK_HOME)
			_g(a, 1050, 1110, ST_DINING, TK_HOME)
			_g(a, 1110, 1290, ST_HOME, TK_HOME, "leisure")
			return _day(1290, 180, a)
		T_NIGHT_MARKET:
			_g(a, 0, 330, ST_SLEEPING, TK_HOME)
			_g(a, 330, 540, ST_HOME, TK_HOME)
			_g(a, 540, 690, ST_SLEEPING, TK_HOME, "nap")
			_g(a, 690, 930, ST_HOME, TK_HOME, "prep")
			_ride(a, 930, 960)
			_g(a, 960, 1080, ST_AT_WORK, TK_WORK, "set-up")
			_g(a, 1080, 1260, ST_AT_WORK, TK_WORK, "stall")
			_g(a, 1260, 1305, ST_DINING, TK_WORK, "staff-meal")
			_g(a, 1305, 1410, ST_AT_WORK, TK_WORK, "stall")
			_ride(a, 1410, 1440)
			return _day(-1, -1, a)
		T_STUDENT_P:
			_g(a, 390, 450, ST_HOME, TK_HOME, "wake")
			_walk(a, 450, 480)
			_g(a, 480, 690, ST_AT_WORK, TK_WORK, "class")
			_g(a, 690, 810, ST_AT_WORK, TK_WORK, "lunch")
			_g(a, 810, 960, ST_AT_WORK, TK_WORK, "class")
			if v < 25:
				_walk(a, 960, 1005)
				_g(a, 1005, 1125, ST_LEISURE, TK_AMUSEMENT, "after-school")
				_walk(a, 1125, 1170)
				_g(a, 1170, 1260, ST_HOME, TK_HOME, "homework")
			else:
				_walk(a, 960, 1020)
				_g(a, 1020, 1140, ST_HOME, TK_HOME, "leisure")
				_g(a, 1140, 1260, ST_HOME, TK_HOME, "homework")
			return _day(1260, 390, a)
		T_STUDENT_M:
			_g(a, 360, 420, ST_HOME, TK_HOME, "wake")
			_walk(a, 420, 450)
			_g(a, 450, 690, ST_AT_WORK, TK_WORK, "class")
			_g(a, 690, 810, ST_AT_WORK, TK_WORK, "lunch")
			_g(a, 810, 1020, ST_AT_WORK, TK_WORK, "class")
			_g(a, 1020, 1230, ST_AT_WORK, TK_WORK, "evening-study")
			_walk(a, 1230, 1290)
			_g(a, 1290, 1350, ST_HOME, TK_HOME)
			return _day(1350, 360, a)
		T_TEACHER:
			_g(a, 390, 450, ST_HOME, TK_HOME, "wake")
			_walk(a, 450, 480)
			_g(a, 480, 720, ST_AT_WORK, TK_WORK, "class")
			_g(a, 720, 780, ST_DINING, TK_WORK, "canteen")
			_g(a, 780, 1020, ST_AT_WORK, TK_WORK, "office")
			_walk(a, 1020, 1050)
			_g(a, 1050, 1140, ST_HOME, TK_HOME)
			_g(a, 1140, 1200, ST_DINING, TK_HOME)
			_g(a, 1200, 1320, ST_HOME, TK_HOME, "lesson-prep")
			return _day(1320, 390, a)
		T_STUDENT_U:
			var late := (v % 3) * 30
			_g(a, 540, 630, ST_HOME, TK_HOME, "wake")
			_walk(a, 630, 660)
			_g(a, 660, 840, ST_AT_WORK, TK_WORK, "class")
			_g(a, 840, 900, ST_DINING, TK_WORK, "canteen")
			_walk(a, 900, 930)
			_g(a, 930, 1080, ST_SHOPPING, TK_ANNEX if v < 35 else TK_MALL)
			if v < 40:
				_walk(a, 1080, 1110)
				_g(a, 1110, 1260 + late, ST_DINING, TK_NIGHT, "night-snack")
				_walk(a, 1260 + late, 1290 + late)
			else:
				_walk(a, 1080, 1110)
				_g(a, 1110, 1140, ST_LEISURE, TK_PLAZA)
				_walk(a, 1140, 1170)
				_g(a, 1170, 1380, ST_HOME, TK_HOME, "leisure")
			return _day(1380, 540, a)
		T_SHIFT:
			if shift_start < 0 or shift_start == 480:
				_walk(a, 435, 480)
				_g(a, 480, 720, ST_AT_WORK, TK_WORK, "duty")
				_g(a, 720, 780, ST_DINING, TK_WORK, "canteen")
				_g(a, 780, 960, ST_AT_WORK, TK_WORK, "duty")
				_walk(a, 960, 1020)
				_g(a, 1020, 1200, ST_HOME, TK_HOME, "leisure")
				return _day(1320, 420, a)
			_g(a, 0, 60, ST_SLEEPING, TK_HOME)
			_g(a, 60, 390, ST_HOME, TK_HOME)
			_g(a, 390, 450, ST_DINING, TK_HOME)
			_g(a, 450, 930, ST_HOME, TK_HOME, "leisure")
			_walk(a, 930, 960)
			_g(a, 960, 1200, ST_AT_WORK, TK_WORK, "duty")
			_g(a, 1200, 1260, ST_DINING, TK_WORK, "canteen")
			_g(a, 1260, 1440, ST_AT_WORK, TK_WORK, "duty")
			return _day(-1, -1, a)
		T_SHIFT_NIGHT:
			_g(a, 0, 420, ST_AT_WORK, TK_WORK, "duty")
			_g(a, 420, 480, ST_DINING, TK_WORK, "canteen")
			_walk(a, 480, 540)
			_g(a, 540, 1140, ST_SLEEPING, TK_HOME)
			_g(a, 1140, 1200, ST_DINING, TK_HOME)
			_g(a, 1200, 1320, ST_HOME, TK_HOME)
			_walk(a, 1320, 1380)
			_g(a, 1380, 1440, ST_AT_WORK, TK_WORK, "duty")
			return _day(-1, -1, a)
		T_PATIENT:
			_g(a, 360, 480, ST_HOME, TK_WORK, "ward-rest")
			_g(a, 480, 660, ST_MEDICAL, TK_WORK, "treatment")
			_g(a, 660, 720, ST_DINING, TK_WORK, "ward-meal")
			_g(a, 720, 840, ST_HOME, TK_WORK, "ward-rest")
			_g(a, 840, 1020, ST_MEDICAL, TK_WORK, "treatment")
			_g(a, 1020, 1080, ST_LEISURE, TK_WORK, "corridor")
			_g(a, 1080, 1140, ST_DINING, TK_WORK, "ward-meal")
			_g(a, 1140, 1290, ST_HOME, TK_WORK, "ward-rest")
			return _day(1290, 360, a)
		T_VISITOR:
			_g(a, 450, 510, ST_HOME, TK_HOME, "wake")
			_walk(a, 510, 570)
			_g(a, 570, 750, ST_MEDICAL, TK_WORK, "visiting")
			_g(a, 750, 810, ST_DINING, TK_STREET, "street-food")
			_g(a, 810, 1020, ST_MEDICAL, TK_WORK, "visiting")
			_walk(a, 1020, 1080)
			_g(a, 1080, 1320, ST_HOME, TK_HOME, "leisure")
			return _day(1320, 450, a)
		T_RETIREE:
			var weekend := day_type != DAY_WEEKDAY
			var games_end := 900 if v < 34 else (960 if v < 67 else 1020)
			_g(a, 330, 390, ST_HOME, TK_HOME, "wake")
			_walk(a, 625, 660)
			_g(a, 660, 720, ST_DINING, TK_HOME)
			# morning
			_walk(a, 390, 420)
			if v >= 8 and v < 20:
				_g(a, 420, 540, ST_SHOPPING, TK_MARKET, "grocery")
				_walk(a, 540, 570)
				_g(a, 570, 625, ST_LEISURE, TK_PLAZA, "morning-exercise")
			else:
				_g(a, 420, 625, ST_LEISURE, TK_PLAZA, "morning-exercise")
			# midday
			if v < 8:
				_walk(a, 720, 750)
				_g(a, 750, 810, ST_MEDICAL, TK_CLINIC, "check-up")
				_walk(a, 810, 840)
			elif v >= 24 and v < 36:
				_walk(a, 720, 745)
				_g(a, 745, 815, ST_SHOPPING, TK_BANK, "pension")
				_walk(a, 815, 840)
			elif v >= 36 and v < 42:
				_walk(a, 720, 745)
				_g(a, 745, 815, ST_SHOPPING, TK_CIVIC, "records")
				_walk(a, 815, 840)
			else:
				_g(a, 720, 805, ST_HOME, TK_HOME)
				_walk(a, 805, 840)
			# afternoon: board games, then the school-gate pick-up (on a weekend, the mall or a stroll)
			_g(a, 840, games_end, ST_LEISURE, TK_PLAZA, "board-games")
			_walk(a, games_end, games_end + 30)
			if weekend:
				if v < 30:
					_g(a, games_end + 30, games_end + 90, ST_SHOPPING, TK_MALL, "errand")
				else:
					_g(a, games_end + 30, games_end + 90, ST_LEISURE, TK_PLAZA, "stroll")
			else:
				_g(a, games_end + 30, games_end + 90, ST_LEISURE, TK_SCHOOL, "pick-up")
			_walk(a, games_end + 90, games_end + 120)
			_g(a, games_end + 120, games_end + 180, ST_DINING, TK_HOME)
			# evening
			if v >= 28 and v < 52:
				_walk(a, 1200, 1230)
				_g(a, 1230, 1300, ST_LEISURE, TK_PLAZA, "square-dance")
				_walk(a, 1300, 1320)
			else:
				_g(a, 1200, 1320, ST_HOME, TK_HOME, "tv")
			return _day(1320, 330, a)
		T_SENIOR:
			_g(a, 360, 450, ST_HOME, TK_HOME, "wake")
			_g(a, 450, 510, ST_DINING, TK_HOME)
			if v < 12:
				_g(a, 510, 600, ST_HOME, TK_HOME)
				_walk(a, 600, 630)
				_g(a, 630, 720, ST_MEDICAL, TK_CLINIC, "check-up")
				_walk(a, 720, 750)
				_g(a, 750, 840, ST_HOME, TK_HOME)
			elif v < 24:
				_g(a, 510, 540, ST_HOME, TK_HOME)
				_walk(a, 540, 570)
				_g(a, 570, 690, ST_SHOPPING, TK_BANK if v >= 16 else TK_MARKET, "pension" if v >= 16 else "grocery")
				_walk(a, 690, 720)
				_g(a, 720, 840, ST_HOME, TK_HOME)
			else:
				_g(a, 510, 840, ST_HOME, TK_HOME)
			_walk(a, 840, 875)
			_g(a, 875, 990, ST_LEISURE, TK_PLAZA, "stroll")
			_walk(a, 990, 1025)
			_g(a, 1080, 1140, ST_DINING, TK_HOME)
			_g(a, 1140, 1230, ST_HOME, TK_HOME, "tv")
			return _day(1230, 360, a)
		T_CHILD:
			_g(a, 405, 540, ST_HOME, TK_HOME, "wake")
			_g(a, 540, 600, ST_DINING, TK_HOME)
			_g(a, 600, 720, ST_HOME, TK_HOME)
			_walk(a, 720, 780)
			_g(a, 780, 990, ST_LEISURE, TK_PLAZA, "stroller")
			_walk(a, 990, 1050)
			_g(a, 1050, 1170, ST_HOME, TK_HOME, "nap")
			_g(a, 1170, 1275, ST_HOME, TK_HOME)
			return _day(1275, 405, a)
		T_IDLER:
			var late := (v % 3) * 30
			var queue := v >= 66 and v < 82
			_g(a, 570, 660, ST_HOME, TK_HOME, "wake")
			_g(a, 660, 720, ST_DINING, TK_HOME)
			_walk(a, 720, 765)
			_g(a, 765, 960, ST_SHOPPING if queue else ST_LEISURE, TK_CIVIC if queue else TK_PLAZA,
				"welfare-queue" if queue else "")
			_walk(a, 960, 1005)
			_g(a, 1005, 1140, ST_SHOPPING, TK_ANNEX if v < 35 else TK_MALL)
			if v < 50:
				_walk(a, 1140, 1170)
				_g(a, 1170, 1290 + late, ST_DINING, TK_NIGHT, "night-snack")
				_walk(a, 1290 + late, 1320 + late)
			else:
				_g(a, 1140, 1200, ST_DINING, TK_STREET, "street-food")
				_g(a, 1200, 1380, ST_HOME, TK_HOME, "leisure")
			return _day(1380, 570, a)
		T_PRECINCT:
			var open := shift_start if shift_start >= 0 else 480
			if open == 960:
				return template(T_SHIFT, v, shift_start, ordinal, role, day_type, half_day)
			if open == 0:
				return template(T_SHIFT_NIGHT, v, shift_start, ordinal, role, day_type, half_day)
			# The school-gate posting exists only on a teaching day, and the first number keeps the desk.
			var gate := ordinal != 1 and day_type == DAY_WEEKDAY
			_walk(a, 435, 480)
			_g(a, 480, 900, ST_AT_WORK, TK_WORK, "patrol" if gate else "desk")
			_walk(a, 900, 915)
			_g(a, 915, 960, ST_AT_WORK, TK_POST if gate else TK_WORK, "school-gate" if gate else "desk")
			_walk(a, 960, 1005)
			_g(a, 1005, 1140, ST_HOME, TK_HOME)
			_g(a, 1140, 1200, ST_DINING, TK_HOME)
			_g(a, 1200, 1320, ST_HOME, TK_HOME, "leisure")
			return _day(1320, 420, a)
		T_CLERK:
			_g(a, 390, 435, ST_HOME, TK_HOME, "wake")
			_walk(a, 435, 480)
			if half_day:
				_g(a, 480, 840, ST_AT_WORK, TK_WORK, "counter")
				_walk(a, 840, 870)
				_g(a, 870, 930, ST_DINING, TK_HOME, "lunch")
				_g(a, 930, 1300, ST_HOME, TK_HOME, "afternoon-off")
				return _day(1300, 390, a)
			_g(a, 480, 720, ST_AT_WORK, TK_WORK, "counter")
			_g(a, 720, 780, ST_DINING, TK_WORK, "canteen")
			_g(a, 780, 1020, ST_AT_WORK, TK_WORK, "counter")
			if v < 16:
				_g(a, 1020, 1050, ST_AT_WORK, TK_WORK, "balanceday")
				_g(a, 1050, 1080, ST_DINING, TK_WORK, "boxed-meal")
				_walk(a, 1080, 1110)
			else:
				_walk(a, 1020, 1050)
			_g(a, 1110, 1170, ST_HOME, TK_HOME)
			_g(a, 1170, 1230, ST_DINING, TK_HOME)
			_g(a, 1230, 1300, ST_HOME, TK_HOME, "tv")
			return _day(1300, 390, a)
		T_SANITATION:
			var open := shift_start if shift_start >= 0 else 480
			if open == 960:
				_g(a, 810, 870, ST_HOME, TK_HOME, "wake")
				_ride(a, 870, 900)
				_g(a, 900, 1140, ST_AT_WORK, TK_WORK, "riverfront")
				_g(a, 1140, 1185, ST_DINING, TK_WORK, "stall-leftovers")
				_g(a, 1185, 1290, ST_AT_WORK, TK_WORK, "yard")
				_ride(a, 1290, 1320)
				return _day(1350, 810, a)
			_ride(a, 255, 285)
			_g(a, 285, 540, ST_AT_WORK, TK_WORK, "collection")
			_g(a, 540, 585, ST_DINING, TK_WORK, "yard-breakfast")
			_g(a, 585, 720, ST_AT_WORK, TK_WORK, "transfer")
			_ride(a, 720, 750)
			_g(a, 750, 900, ST_HOME, TK_HOME)
			_g(a, 900, 960, ST_DINING, TK_HOME)
			_g(a, 960, 1290, ST_HOME, TK_HOME, "nap")
			return _day(1290, 255, a)
		T_WEEKEND:
			var rc := role_class(role)
			if rc == ROLE_KID:
				_g(a, 480, 540, ST_HOME, TK_HOME, "wake")
				_g(a, 540, 600, ST_DINING, TK_HOME, "family-breakfast")
				_g(a, 600, 660, ST_HOME, TK_HOME)
				_walk(a, 660, 705)
				if v < 25:
					_g(a, 705, 900, ST_LEISURE, TK_AMUSEMENT, "rides")
				elif v < 50:
					_g(a, 705, 900, ST_LEISURE, TK_MALL, "arcade")
				else:
					_g(a, 705, 900, ST_LEISURE, TK_PLAZA, "playground")
				_walk(a, 900, 945)
				_g(a, 945, 1005, ST_DINING, TK_HOME, "lunch")
				_g(a, 1005, 1140, ST_HOME, TK_HOME, "nap")
				_walk(a, 1140, 1185)
				_g(a, 1185, 1260, ST_LEISURE, TK_PLAZA, "evening-play")
				_walk(a, 1260, 1290)
				return _day(1290, 480, a)
			if rc == ROLE_STUDENT_U:
				_g(a, 540, 600, ST_HOME, TK_HOME, "wake")
				_g(a, 600, 660, ST_DINING, TK_HOME, "brunch")
				_g(a, 660, 780, ST_HOME, TK_HOME)
				_walk(a, 780, 825)
				_g(a, 825, 1020, ST_LEISURE, TK_PLAZA, "afternoon")
				_walk(a, 1020, 1065)
				_g(a, 1065, 1125, ST_DINING, TK_HOME)
				_walk(a, 1125, 1170)
				_g(a, 1170, 1320, ST_DINING, TK_NIGHT if v < 48 else TK_MALL, "night-snack" if v < 48 else "food-court")
				_walk(a, 1320, 1380)
				return _day(1380, 540, a)
			_g(a, 480, 540, ST_HOME, TK_HOME, "wake")
			_g(a, 540, 600, ST_DINING, TK_HOME, "family-breakfast")
			_walk(a, 600, 645)
			if v < 15:
				_g(a, 645, 780, ST_SHOPPING, TK_MARKET, "grocery")
			elif v < 30:
				_g(a, 645, 780, ST_SHOPPING, TK_MALL, "shopping")
			elif v < 42:
				_g(a, 645, 780, ST_SHOPPING, TK_ANNEX, "shopping")
			else:
				_g(a, 645, 780, ST_LEISURE, TK_PLAZA, "stroll")
			_walk(a, 780, 825)
			_g(a, 825, 900, ST_HOME, TK_HOME)
			_g(a, 900, 960, ST_DINING, TK_HOME, "lunch")
			_walk(a, 960, 1005)
			if v < 30:
				_g(a, 1005, 1170, ST_SHOPPING, TK_MALL, "shopping")
			elif v < 48:
				_g(a, 1005, 1170, ST_SHOPPING, TK_ANNEX, "shopping")
			elif v < 56:
				_g(a, 1005, 1170, ST_SHOPPING, TK_AMUSEMENT, "with-the-kids")
			else:
				_g(a, 1005, 1170, ST_LEISURE, TK_PLAZA, "stroll")
			_walk(a, 1170, 1215)
			_g(a, 1215, 1290, ST_DINING, TK_NIGHT if v < 26 else TK_HOME, "night-snack" if v < 26 else "supper")
			_g(a, 1290, 1350, ST_HOME, TK_HOME, "tv")
			return _day(1350, 480, a)
		T_DUTY:
			_g(a, 420, 480, ST_HOME, TK_HOME, "wake")
			_ride(a, 480, 510)
			_g(a, 510, 720, ST_AT_WORK, TK_DUTY, "maintenance")
			_g(a, 720, 765, ST_DINING, TK_DUTY, "duty-meal")
			_g(a, 765, 960, ST_AT_WORK, TK_DUTY, "rounds")
			_ride(a, 960, 990)
			_g(a, 990, 1140, ST_HOME, TK_HOME)
			_g(a, 1140, 1200, ST_DINING, TK_HOME)
			_g(a, 1200, 1320, ST_HOME, TK_HOME, "tv")
			return _day(1320, 420, a)
	push_error("thousand_sim_data: unknown template %d" % id)
	return a
