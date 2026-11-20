## The city's people (design/city-district.md "City r2"): where they are, what they do and how they look.
##
## Pure, static data and functions (no nodes). art/city_people.gd draws and animates them; CityNav makes the
## standing ones solid for children through solids().
##
##   PEOPLE           the 36 static people, `place` a CityMap.PEOPLE_BUDGET key. Seated and machine people sit
##                    exactly on a PropsCity.NPC_PLACES entry ("npc"); standing people stand on one too, except
##                    the restaurant's waiter. None is within MIN_CLEAR of a child's place (CityMap.INTERACTIONS).
##                    y_offset: the seat, deck or saddle height above the region floor (with the 3 cm building
##                    floor for ground places indoors); table: Vector2(distance ahead to the table or counter
##                    edge, its top height) for the hands.
##   WALKER_LOOKS     one look per CityRules walker index (the walkers' poses come from CityRules.walkers(t)).
##   FERRIS_SLOTS     four passengers in two pairs, scheduled per lap of the wheel (ferris_rides(t)); a slot
##                    has three looks and a new passenger boards at the bottom for each ride.
##   CAROUSEL_RIDERS  two riders on horses of the carousel.
##
## Looks are deterministic from each person's seed (look_from_seed); the literal looks below were generated
## by it (the tests check that) with seeds chosen so that neighbours never look alike.
## Directions: forward of a yaw ry is (sin ry, cos ry) in (x, z), as everywhere in the game.
extends RefCounted

const CityMap := preload("res://scripts/core/city_map.gd")

## A person never stands or sits nearer than this to a child's place on the same region.
const MIN_CLEAR := 0.9
## A standing person's radius for the navigation (solids()).
const SOLID_R := 0.3

const ACTIONS := ["type", "read_screen", "phone", "eat", "chat", "drink", "cook", "wait_tables", "serve_counter",
	"wipe_counter", "browse", "carry_bag", "run", "cycle", "row", "lift", "stretch", "sit_ride", "walk"]
## Actions done on a chair or stool (the body sits; the legs rest).
const SEATED_ACTIONS := ["type", "read_screen", "phone", "eat", "chat", "drink", "sit_ride"]
## Actions done on a machine (the legs work).
const MACHINE_ACTIONS := ["run", "cycle", "row"]
## Standing people are solid for children (solids()): staff, customers and athletes on standing machines.
const STANDING_ACTIONS := ["cook", "wait_tables", "serve_counter", "wipe_counter", "browse", "carry_bag", "run", "lift", "stretch"]

const HAIR_STYLES := ["short", "long", "bun", "ponytail", "curly", "cap", "bald"]
const TOPS := ["tee", "shirt", "jacket", "dress", "apron", "uniform", "sports"]

## Palettes: bright and clean like the city, with natural skin and hair.
const SKINS := [Color("#ffe3cc"), Color("#f7cfae"), Color("#ecb98f"), Color("#dba06f"), Color("#c58553"),
	Color("#a86a3d"), Color("#87502b"), Color("#61391f")]
const HAIR_COLORS := [Color("#2a2220"), Color("#4b3123"), Color("#7b4a2b"), Color("#a8642f"), Color("#d9a55a"),
	Color("#f0d48e"), Color("#c95f35"), Color("#bdb7b0")]
const TOP_COLORS := [Color("#4fb0ff"), Color("#2f7fd8"), Color("#ff8552"), Color("#ff6f7d"), Color("#ffd75e"),
	Color("#5fcfa4"), Color("#2fae8f"), Color("#a98cf0"), Color("#ff9ec7"), Color("#c8325a"), Color("#f8f8f4"),
	Color("#ffb98a"), Color("#8fd16a"), Color("#33507a")]
const BOTTOM_COLORS := [Color("#3d6491"), Color("#2c3340"), Color("#cdb68c"), Color("#5d6e4b"), Color("#f0e6d2"),
	Color("#6e4b3a"), Color("#22305a"), Color("#8e94a3")]
const SPORT_BOTTOMS := [Color("#2c3340"), Color("#22305a"), Color("#3d6491"), Color("#5a4a8a")]
const SHOE_COLORS := [Color("#ffffff"), Color("#2f2c2a"), Color("#8a5a3a"), Color("#e2504c"), Color("#4f86d6"), Color("#f2c94c")]
const CAP_COLORS := [Color("#ff8552"), Color("#4fb0ff"), Color("#c8325a"), Color("#5fcfa4"), Color("#ffd75e"), Color("#33507a")]
## Aprons by workplace (the shirt underneath is the look's top_color).
const APRONS := {"bakery": Color("#d99a5b"), "corner_cafe": Color("#ff8f73"), "bookstore": Color("#4f9be0"),
	"flowers": Color("#e86a9a"), "icecream": Color("#f2c84b"), "cafe": Color("#8a5a3a"), "restaurant": Color("#ffffff")}
const WHITE := Color("#f8f8f4")


# ===================================================================== hashing (deterministic: the same on every device)

static func _mix(x: int) -> int:
	x &= 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return (x ^ (x >> 16)) & 0xFFFFFFFF


## A number in [0, 1) from two integers; the same everywhere, every run.
static func hash01(a: int, b: int = 0) -> float:
	var x := (((a & 0x0FFFFFFF) * 0x9E3779B1) & 0xFFFFFFFF) ^ (((b & 0x0FFFFFFF) * 0x85EBCA77) & 0xFFFFFFFF)
	return float(_mix(x ^ 0x165667B1)) / 4294967296.0


## A 32-bit seed from a string (FNV-1a).
static func seed_of(id: String) -> int:
	var h := 2166136261
	for b: int in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func _pick(list: Array, u: float) -> Variant:
	return list[mini(int(u * float(list.size())), list.size() - 1)]


## Picks from `options` by `weights` with u in [0, 1).
static func _weighted(options: Array, weights: Array, u: float) -> Variant:
	var total := 0.0
	for w: float in weights:
		total += w
	var acc := 0.0
	for i in options.size():
		acc += float(weights[i]) / total
		if u < acc:
			return options[i]
	return options[options.size() - 1]


# ===================================================================== looks

## A look from a seed. role: office | guest | walker | staff_<workplace> | cook | waiter | athlete | rider
## (rider: a child-sized passenger, the Ferris cabins being child-sized). Keys: sex ("f" | "m"), skin,
## hair_style, hair_color (a cap's colour for "cap"), top, top_color, bottom_color, shoes, accessory
## (none | glasses | beard | bag | scarf), accent (apron, scarf or bag colour), scale (1.0 is 1.83 m tall).
static func look_from_seed(sd: int, role: String) -> Dictionary:
	var sex := "f" if hash01(sd, 1) < 0.5 else "m"
	var look := {"sex": sex, "skin": _pick(SKINS, hash01(sd, 2))}
	var u_hair := hash01(sd, 3)
	var style := ""
	if role == "cook":
		style = "cap"
	elif role == "athlete":
		style = String(_weighted(["ponytail", "bun", "short", "curly"], [4, 2, 2, 1], u_hair)) if sex == "f" \
			else String(_weighted(["short", "bald", "curly", "cap"], [4, 2, 2, 1], u_hair))
	elif sex == "f":
		style = String(_weighted(["long", "ponytail", "bun", "curly", "short"], [6, 4, 3, 3, 3], u_hair))
	else:
		style = String(_weighted(["short", "curly", "cap", "bald", "long", "ponytail"], [8, 4, 3, 3, 1, 1], u_hair))
	if role.begins_with("staff") or role == "waiter":
		if style == "cap":
			style = "short"
	look["hair_style"] = style
	var hc: Color = _weighted(HAIR_COLORS, [5, 5, 4, 3, 3, 2, 2, 2], hash01(sd, 4))
	if style == "cap":
		hc = WHITE if role == "cook" else _pick(CAP_COLORS, hash01(sd, 4))
	elif role == "rider" and hc == HAIR_COLORS[7]:
		hc = HAIR_COLORS[2]
	look["hair_color"] = hc
	var top := ""
	match role:
		"cook", "waiter":
			top = "uniform"
		"athlete":
			top = "sports"
		"office":
			top = String(_weighted(["shirt", "jacket", "tee", "dress"], [4, 3, 2, 2 if sex == "f" else 0], hash01(sd, 5)))
		"rider":
			top = String(_weighted(["tee", "shirt", "dress"], [5, 2, 2 if sex == "f" else 0], hash01(sd, 5)))
		_:
			if role.begins_with("staff"):
				top = "apron"
			else:
				top = String(_weighted(["tee", "shirt", "jacket", "dress"], [5, 3, 2, 3 if sex == "f" else 0], hash01(sd, 5)))
	look["top"] = top
	var tc: Color = _pick(TOP_COLORS, hash01(sd, 6))
	if role == "cook":
		tc = WHITE
	elif role == "waiter":
		tc = TOP_COLORS[13]
	look["top_color"] = tc
	look["bottom_color"] = _pick(SPORT_BOTTOMS if top == "sports" else BOTTOM_COLORS, hash01(sd, 7))
	look["shoes"] = _pick(SHOE_COLORS, hash01(sd, 8))
	var acc := "none"
	var u_acc := hash01(sd, 9)
	if role == "office":
		acc = String(_weighted(["none", "glasses", "beard", "scarf"], [4, 3, 2 if sex == "m" else 0, 1], u_acc))
	elif role in ["guest", "walker"]:
		acc = String(_weighted(["none", "glasses", "beard", "bag", "scarf"], [4, 2, 2 if sex == "m" else 0, 2 if role == "walker" else 1, 1], u_acc))
	elif role in ["cook", "waiter"] or role.begins_with("staff"):
		acc = String(_weighted(["none", "glasses", "beard"], [5, 2, 2 if sex == "m" else 0], u_acc))
	elif role == "athlete":
		acc = String(_weighted(["none", "beard"], [5, 1 if sex == "m" else 0], u_acc))
	elif role == "rider":
		acc = String(_weighted(["none", "glasses"], [5, 1], u_acc))
	look["accessory"] = acc
	var accent: Color = _pick(TOP_COLORS, hash01(sd, 10))
	if role.begins_with("staff_"):
		accent = APRONS.get(role.substr(6), accent)
	elif role == "cook" or role == "waiter":
		accent = APRONS["restaurant"]
	if accent == tc:
		accent = TOP_COLORS[(TOP_COLORS.find(tc) + 5) % TOP_COLORS.size()]
	look["accent"] = accent
	var u_h := hash01(sd, 11)
	var scale := (0.965 + 0.045 * u_h) if sex == "m" else (0.915 + 0.04 * u_h)
	if role == "rider":
		scale = 0.54 + 0.03 * u_h
	look["scale"] = snappedf(scale, 0.001)
	return look


# ===================================================================== timing (nobody in sync)

## A person's own clock: local time = t * rate + offset; slot is the spacing of their idle events (4 to 9 s).
static func timing(id: String) -> Dictionary:
	var s := seed_of(id)
	return {"offset": 3.0 + 97.0 * hash01(s, 101), "rate": 0.86 + 0.28 * hash01(s, 102), "slot": 4.0 + 5.0 * hash01(s, 103)}


## The phase (0..1) of a person's action cycle of `period` seconds at time t.
static func action_phase(id: String, t: float, period: float) -> float:
	var tm := timing(id)
	return fposmod((t * float(tm["rate"]) + float(tm["offset"])) / period, 1.0)


# ===================================================================== places

## The floor height of a region ("ground" or "" is 0).
static func floor_y(region: String) -> float:
	if region == "ground" or region == "":
		return 0.0
	return float((CityMap.REGIONS[region] as Dictionary)["y"])


static func is_standing(p: Dictionary) -> bool:
	return String(p["action"]) in STANDING_ACTIONS


## The standing people, solid to children: [{"region", "at": Vector2, "r"}]. Seated people sit in chairs that
## are already furniture; riders and walkers are not here (walkers keep to their own lanes).
static func solids() -> Array:
	var out: Array = []
	for p: Dictionary in PEOPLE:
		if is_standing(p):
			out.append({"region": String(p["region"]), "at": p["pos"], "r": SOLID_R, "id": String(p["id"])})
	return out


## How many static people each PEOPLE_BUDGET place has.
static func counts() -> Dictionary:
	var out := {}
	for p: Dictionary in PEOPLE:
		var k := String(p["place"])
		out[k] = int(out.get(k, 0)) + 1
	out["walkers"] = WALKER_LOOKS.size()
	out["ferris"] = FERRIS_SLOTS.size()
	out["carousel"] = CAROUSEL_RIDERS.size()
	return out


# ===================================================================== the Ferris wheel's passengers

## Two pairs ride, each in its own gondola. A pair's cycle: one full lap in gondola A (boarding and leaving at
## its bottom pass), a wait of half a lap, a full lap in the opposite gondola A + n/2, a short wait; then the
## next cycle starts in gondola A + 1, whose bottom pass comes one gondola spacing (period / n) earlier in the
## lap, so a cycle is 3 laps minus that spacing. Every ride starts and ends exactly at a bottom pass.
const FERRIS_PAIRS := [{"g0": 0, "slots": [0, 1]}, {"g0": 3, "slots": [2, 3]}]


static func _ferris_n() -> int:
	return int((CityMap.FERRIS as Dictionary)["gondolas"])


static func _ferris_p() -> float:
	return float((CityMap.FERRIS as Dictionary)["period"])


## The ride a pair is on at time t: {"gondola", "ride" (a running index), "start", "end"}; {} between rides.
static func pair_ride(pair: int, t: float) -> Dictionary:
	var n := _ferris_n()
	var period := _ferris_p()
	var g0 := int((FERRIS_PAIRS[pair] as Dictionary)["g0"])
	# gondola g is at the bottom at (k - g / n) * period (CityRules.gondola_angle)
	var s0 := -float(g0) / float(n) * period
	var cycle := 3.0 * period - period / float(n)
	var c := floori((t - s0) / cycle)
	var u := t - s0 - float(c) * cycle
	var start := s0 + float(c) * cycle
	var a := posmod(g0 + c, n)
	if u < period:
		return {"gondola": a, "ride": c * 2, "start": start, "end": start + period}
	if u >= 1.5 * period and u < 2.5 * period:
		return {"gondola": posmod(a + (n >> 1), n), "ride": c * 2 + 1, "start": start + 1.5 * period, "end": start + 2.5 * period}
	return {}


## The scheduled passengers at time t (before children are taken into account):
## [{"slot", "gondola", "seat", "ride", "variant"}]. The variant picks which of the slot's looks boards.
static func ferris_rides(t: float) -> Array:
	var out: Array = []
	for pi in FERRIS_PAIRS.size():
		var r := pair_ride(pi, t)
		if r.is_empty():
			continue
		var slots: Array = (FERRIS_PAIRS[pi] as Dictionary)["slots"]
		for k in slots.size():
			var slot := int(slots[k])
			var looks: Array = (FERRIS_SLOTS[slot] as Dictionary)["looks"]
			var v := int(hash01(slot + 7, int(r["ride"]) + 1000) * float(looks.size())) % looks.size()
			out.append({"slot": slot, "gondola": int(r["gondola"]), "seat": k, "ride": int(r["ride"]), "variant": v})
	return out


## The lap index of gondola g at time t (it changes exactly at g's bottom pass).
static func gondola_lap(g: int, t: float) -> int:
	return floori(t / _ferris_p() + float(g) / float(_ferris_n()))


# ===================================================================== weather (city r3)

## In the rain (CityMap.WEATHERS index 1) people outdoors and not under cover react: about UMBRELLA_SHARE of
## those who may (walkers and seated people) open an umbrella and carry on; the others hurry to a free stand
## spot of the nearest cover, in small groups over RAIN_COVER_SPREAD seconds, wait there, and when the rain
## stops walk back over RAIN_RETURN_SPREAD seconds and resume. art/city_people.gd runs it from the shared
## weather state; this part is the data and the pure rules.
const RAIN := 1
const HURRY_SPEED := 1.75      # m/s, a quick walk (walkers stroll at 1.0 to 1.4)
const RETURN_SPEED := 1.25
const LANE_RETURN_SPEED := 1.6  # a walker on its lane going to meet its own place in the stroll
const UMBRELLA_TIME := 1.2     # seconds to open or fold an umbrella
const GROUP_CELL := 8.0        # people within one such square of ground start together (a small group)

## Overhead covers the art draws that PropsCity.COVERS does not list (yet): the rooftop restaurant's pavilion,
## the parasols over its tables and the cafe terrace's parasol table, and the skywalk decks under their glass
## canopies. Same fields as PropsCity.COVERS.
const EXTRA_COVERS := [
	{"id": "restaurant_pavilion", "kind": "canopy", "region": "gym_roof", "rect": Rect2(7.6, -14.0, 8.4, 3.7), "stand": [Vector2(13.5, -10.9), Vector2(14.7, -11.4)]},
	{"id": "parasol_t1", "kind": "parasol", "region": "gym_roof", "rect": Rect2(9.8, -8.95, 2.0, 2.1), "stand": []},
	{"id": "parasol_t2", "kind": "parasol", "region": "gym_roof", "rect": Rect2(12.8, -6.95, 2.0, 2.1), "stand": []},
	{"id": "parasol_t3", "kind": "parasol", "region": "gym_roof", "rect": Rect2(7.7, -6.75, 2.0, 2.1), "stand": []},
	{"id": "parasol_t4", "kind": "parasol", "region": "gym_roof", "rect": Rect2(14.9, -9.55, 2.0, 2.1), "stand": []},
	{"id": "parasol_t5", "kind": "parasol", "region": "gym_roof", "rect": Rect2(9.5, -5.45, 2.0, 2.1), "stand": []},
	{"id": "terrace_parasol", "kind": "parasol", "region": "cafe_terrace", "rect": Rect2(-3.3, -3.7, 2.2, 2.2), "stand": []},
	{"id": "skywalk_a_deck", "kind": "canopy", "region": "skywalk_a", "rect": Rect2(-11.0, -11.0, 4.0, 2.0), "stand": [Vector2(-10.0, -10.65), Vector2(-8.6, -10.65)]},
	{"id": "skywalk_b_deck", "kind": "canopy", "region": "skywalk_b", "rect": Rect2(3.0, -11.0, 4.0, 1.6), "stand": []},
]
## Storeys with a floor above them: everyone on them is indoors.
const INDOOR_REGIONS := ["office_l1", "office_l2", "gym_l1", "office_door_l1", "gym_door_l1"]

static var _covers_cache: Array = []


static func norm_region(region: String) -> String:
	return "ground" if region == "" else region


## Every cover: PropsCity.COVERS (A1), then EXTRA_COVERS, then CityNav.cover_spots() (S1) for spots the
## others lack (a small square round each, kept only when no listed spot is within 0.6 m). Each:
## {id, kind, region, rect, stand: Array of Vector2}.
static func covers() -> Array:
	if not _covers_cache.is_empty():
		return _covers_cache
	var out: Array = []
	var art: GDScript = load("res://scripts/art/props_city.gd") as GDScript
	if art != null and art.get_script_constant_map().has("COVERS"):
		for c: Dictionary in art.get_script_constant_map()["COVERS"]:
			var d := c.duplicate()
			d["region"] = norm_region(String(c["region"]))
			out.append(d)
	for c: Dictionary in EXTRA_COVERS:
		out.append(c.duplicate())
	var nav: GDScript = load("res://scripts/core/city_nav.gd") as GDScript
	if nav != null and nav.has_method("cover_spots"):
		var spots: Variant = nav.call("cover_spots")
		if spots is Array:
			for c: Dictionary in spots:
				var pos: Vector2 = c["pos"]
				var reg := norm_region(String(c.get("region", "")))
				var near := false
				for o: Dictionary in out:
					for q: Vector2 in o["stand"]:
						if String(o["region"]) == reg and q.distance_to(pos) < 0.6:
							near = true
				if not near:
					out.append({"id": "nav_" + String(c.get("id", str(pos))), "kind": String(c.get("kind", "awning")), "region": reg,
						"rect": Rect2(pos - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), "stand": [pos]})
	_covers_cache = out
	return out


## Indoors: an upper storey under a floor, or the ground inside a building.
static func is_indoor(region: String, pos: Vector2) -> bool:
	region = norm_region(region)
	if region in INDOOR_REGIONS:
		return true
	if region != "ground":
		return false
	for bid: String in CityMap.BUILDINGS:
		if (CityMap.BUILDINGS[bid]["rect"] as Rect2).has_point(pos):
			return true
	return false


## Under a cover (a body's width of slack, `grow`).
static func under_cover(region: String, pos: Vector2, grow: float = 0.15) -> bool:
	region = norm_region(region)
	for c: Dictionary in covers():
		if String(c["region"]) == region and (c["rect"] as Rect2).grow(grow).has_point(pos):
			return true
	return false


## Whether a person who reacts to rain opens an umbrella (by its id; staff and carousel riders never do).
static func umbrella_for(id: String) -> bool:
	return hash01(seed_of(id), 501) < float(CityMap.UMBRELLA_SHARE)


## A person's start delay after a weather change: its group's (the square of ground it is in) plus a little
## of its own, within `spread` seconds.
static func group_delay(id: String, at: Vector2, spread: float) -> float:
	var cell := Vector2i(floori(at.x / GROUP_CELL), floori(at.y / GROUP_CELL))
	var g := hash01((cell.x + 64) * 131 + (cell.y + 64), 777)
	return spread * (0.72 * g + 0.26 * hash01(seed_of(id), 778))


# ===================================================================== generated data (checked by tests/city_people_tests.gd)

# BEGIN GENERATED
## The static people (generated; see the header).
const PEOPLE := [
	{"id": "office_l1_desk_c", "place": "office", "region": "office_l1", "pos": Vector2(-19.9, -5.6), "y_offset": 0.49, "ry": PI, "action": "type", "pose": "desk", "npc": "office_l1_desk_c", "table": Vector2(0.21, 0.765),
		"role": "office", "seed": 2993932774, "look": {"sex": "f", "skin": Color("#a86a3d"), "hair_style": "long", "hair_color": Color("#4b3123"), "top": "tee", "top_color": Color("#8fd16a"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#5fcfa4"), "scale": 0.938}},
	{"id": "office_l1_desk_e", "place": "office", "region": "office_l1", "pos": Vector2(-14.1, -5.6), "y_offset": 0.49, "ry": PI, "action": "read_screen", "pose": "desk", "npc": "office_l1_desk_e", "table": Vector2(0.21, 0.765),
		"role": "office", "seed": 3998643769, "look": {"sex": "m", "skin": Color("#ecb98f"), "hair_style": "curly", "hair_color": Color("#d9a55a"), "top": "jacket", "top_color": Color("#ff9ec7"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#ff6f7d"), "scale": 0.97}},
	{"id": "office_l1_desk_f", "place": "office", "region": "office_l1", "pos": Vector2(-14.1, -10.0), "y_offset": 0.49, "ry": PI, "action": "phone", "pose": "desk", "npc": "office_l1_desk_f", "table": Vector2(0.21, 0.765),
		"role": "office", "seed": 1992225025, "look": {"sex": "f", "skin": Color("#ecb98f"), "hair_style": "bun", "hair_color": Color("#4b3123"), "top": "tee", "top_color": Color("#4fb0ff"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#ffffff"), "accessory": "scarf", "accent": Color("#2fae8f"), "scale": 0.951}},
	{"id": "office_l2_desk_b", "place": "office", "region": "office_l2", "pos": Vector2(-16.9, -5.0), "y_offset": 0.49, "ry": PI, "action": "type", "pose": "desk", "npc": "office_l2_desk_b", "table": Vector2(0.21, 0.765),
		"role": "office", "seed": 543586711, "look": {"sex": "m", "skin": Color("#61391f"), "hair_style": "curly", "hair_color": Color("#2a2220"), "top": "shirt", "top_color": Color("#ff6f7d"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#f2c94c"), "accessory": "glasses", "accent": Color("#4fb0ff"), "scale": 1.001}},
	{"id": "office_l2_meeting_a", "place": "office", "region": "office_l2", "pos": Vector2(-19.4375, -10.25), "y_offset": 0.49, "ry": 0.0, "action": "chat", "pose": "sit", "npc": "office_l2_meeting_a", "table": Vector2(0.25, 0.77),
		"role": "office", "seed": 2028725819, "look": {"sex": "m", "skin": Color("#c58553"), "hair_style": "curly", "hair_color": Color("#d9a55a"), "top": "tee", "top_color": Color("#4fb0ff"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#2fae8f"), "scale": 0.968}},
	{"id": "office_l2_meeting_b", "place": "office", "region": "office_l2", "pos": Vector2(-17.5625, -8.35), "y_offset": 0.49, "ry": PI, "action": "chat", "pose": "sit", "npc": "office_l2_meeting_b", "table": Vector2(0.26, 0.77),
		"role": "office", "seed": 805061744, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "short", "hair_color": Color("#a8642f"), "top": "shirt", "top_color": Color("#8fd16a"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#8a5a3a"), "accessory": "scarf", "accent": Color("#c8325a"), "scale": 0.929}},
	{"id": "restaurant_cook", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.6, -13.75), "y_offset": 0.0, "ry": 0.0, "action": "cook", "pose": "stand", "npc": "restaurant_cook", "table": Vector2(0.35, 1.06),
		"role": "cook", "seed": 3240795829, "look": {"sex": "m", "skin": Color("#f7cfae"), "hair_style": "cap", "hair_color": Color("#f8f8f4"), "top": "uniform", "top_color": Color("#f8f8f4"), "bottom_color": Color("#8e94a3"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#ffffff"), "scale": 0.974}},
	{"id": "restaurant_waiter", "place": "restaurant", "region": "gym_roof", "pos": Vector2(13.2, -9.6), "y_offset": 0.0, "ry": -PI * 0.5, "action": "wait_tables", "pose": "stand", "npc": "", "table": Vector2(0.0, 0.0),
		"role": "waiter", "seed": 1647192343, "look": {"sex": "f", "skin": Color("#c58553"), "hair_style": "ponytail", "hair_color": Color("#c95f35"), "top": "uniform", "top_color": Color("#33507a"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#ffffff"), "scale": 0.932}},
	{"id": "restaurant_t1_n", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.8, -8.85), "y_offset": 0.465, "ry": 0.0, "action": "chat", "pose": "sit", "npc": "restaurant_t1_n", "table": Vector2(0.46, 0.76),
		"role": "guest", "seed": 641673561, "look": {"sex": "f", "skin": Color("#a86a3d"), "hair_style": "long", "hair_color": Color("#4b3123"), "top": "tee", "top_color": Color("#4fb0ff"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#ffffff"), "accessory": "scarf", "accent": Color("#f8f8f4"), "scale": 0.948}},
	{"id": "restaurant_t1_s", "place": "restaurant", "region": "gym_roof", "pos": Vector2(10.8, -6.95), "y_offset": 0.465, "ry": PI, "action": "chat", "pose": "sit", "npc": "restaurant_t1_s", "table": Vector2(0.46, 0.76),
		"role": "guest", "seed": 3152646556, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "short", "hair_color": Color("#2a2220"), "top": "shirt", "top_color": Color("#c8325a"), "bottom_color": Color("#2c3340"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#ffd75e"), "scale": 0.979}},
	{"id": "restaurant_t4_n", "place": "restaurant", "region": "gym_roof", "pos": Vector2(15.9, -9.45), "y_offset": 0.465, "ry": 0.0, "action": "eat", "pose": "sit", "npc": "restaurant_t4_n", "table": Vector2(0.45, 0.76),
		"role": "guest", "seed": 4071544786, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "curly", "hair_color": Color("#f0d48e"), "top": "tee", "top_color": Color("#5fcfa4"), "bottom_color": Color("#2c3340"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#ff6f7d"), "scale": 0.981}},
	{"id": "restaurant_t4_s", "place": "restaurant", "region": "gym_roof", "pos": Vector2(15.9, -7.55), "y_offset": 0.465, "ry": PI, "action": "eat", "pose": "sit", "npc": "restaurant_t4_s", "table": Vector2(0.46, 0.76),
		"role": "guest", "seed": 2741111819, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "short", "hair_color": Color("#4b3123"), "top": "jacket", "top_color": Color("#4fb0ff"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#e2504c"), "accessory": "glasses", "accent": Color("#2fae8f"), "scale": 0.92}},
	{"id": "restaurant_bar_e", "place": "restaurant", "region": "gym_roof", "pos": Vector2(11.32, -12.25), "y_offset": 0.74, "ry": PI, "action": "drink", "pose": "sit", "npc": "restaurant_bar_e", "table": Vector2(0.35, 1.06),
		"role": "guest", "seed": 1021942956, "look": {"sex": "m", "skin": Color("#ecb98f"), "hair_style": "curly", "hair_color": Color("#bdb7b0"), "top": "shirt", "top_color": Color("#33507a"), "bottom_color": Color("#22305a"), "shoes": Color("#e2504c"), "accessory": "beard", "accent": Color("#a98cf0"), "scale": 0.98}},
	{"id": "cafe_barista", "place": "cafe", "region": "ground", "pos": Vector2(0.5, -10.2), "y_offset": 0.03, "ry": -PI * 0.5, "action": "serve_counter", "pose": "stand", "npc": "cafe_barista", "table": Vector2(0.51, 0.98),
		"role": "staff_cafe", "seed": 727200063, "look": {"sex": "f", "skin": Color("#ffe3cc"), "hair_style": "long", "hair_color": Color("#d9a55a"), "top": "apron", "top_color": Color("#8fd16a"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#8a5a3a"), "accessory": "glasses", "accent": Color("#8a5a3a"), "scale": 0.948}},
	{"id": "cafe_dining_a", "place": "cafe", "region": "ground", "pos": Vector2(0.912, -9.28), "y_offset": 0.495, "ry": 0.0, "action": "chat", "pose": "sit", "npc": "cafe_dining_a", "table": Vector2(0.28, 0.76),
		"role": "guest", "seed": 2192928482, "look": {"sex": "m", "skin": Color("#a86a3d"), "hair_style": "short", "hair_color": Color("#bdb7b0"), "top": "jacket", "top_color": Color("#ff6f7d"), "bottom_color": Color("#8e94a3"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 1.003}},
	{"id": "cafe_dining_c", "place": "cafe", "region": "ground", "pos": Vector2(0.912, -7.82), "y_offset": 0.495, "ry": PI, "action": "chat", "pose": "sit", "npc": "cafe_dining_c", "table": Vector2(0.29, 0.76),
		"role": "guest", "seed": 3624297759, "look": {"sex": "f", "skin": Color("#87502b"), "hair_style": "curly", "hair_color": Color("#a8642f"), "top": "tee", "top_color": Color("#c8325a"), "bottom_color": Color("#3d6491"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#2fae8f"), "scale": 0.949}},
	{"id": "cafe_t3_w", "place": "cafe", "region": "ground", "pos": Vector2(-2.62, -4.0), "y_offset": 0.495, "ry": PI * 0.5, "action": "drink", "pose": "sit", "npc": "cafe_t3_w", "table": Vector2(0.32, 0.735),
		"role": "guest", "seed": 2246751140, "look": {"sex": "f", "skin": Color("#ecb98f"), "hair_style": "curly", "hair_color": Color("#f0d48e"), "top": "tee", "top_color": Color("#ff6f7d"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#ff9ec7"), "scale": 0.95}},
	{"id": "terrace_t3_n", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-4.0, -9.65), "y_offset": 0.465, "ry": 0.0, "action": "chat", "pose": "sit", "npc": "terrace_t3_n", "table": Vector2(0.45, 0.76),
		"role": "guest", "seed": 2276223264, "look": {"sex": "m", "skin": Color("#c58553"), "hair_style": "short", "hair_color": Color("#c95f35"), "top": "tee", "top_color": Color("#ff9ec7"), "bottom_color": Color("#2c3340"), "shoes": Color("#2f2c2a"), "accessory": "none", "accent": Color("#4fb0ff"), "scale": 1.008}},
	{"id": "terrace_t3_s", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-4.0, -7.75), "y_offset": 0.465, "ry": PI, "action": "chat", "pose": "sit", "npc": "terrace_t3_s", "table": Vector2(0.46, 0.76),
		"role": "guest", "seed": 966677872, "look": {"sex": "f", "skin": Color("#87502b"), "hair_style": "curly", "hair_color": Color("#4b3123"), "top": "dress", "top_color": Color("#33507a"), "bottom_color": Color("#3d6491"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#ffd75e"), "scale": 0.928}},
	{"id": "terrace_umbrella_e", "place": "cafe_terrace", "region": "cafe_terrace", "pos": Vector2(-1.3, -2.6), "y_offset": 0.465, "ry": -PI * 0.5, "action": "drink", "pose": "sit", "npc": "terrace_umbrella_e", "table": Vector2(0.51, 0.735),
		"role": "guest", "seed": 3700453321, "look": {"sex": "m", "skin": Color("#c58553"), "hair_style": "curly", "hair_color": Color("#7b4a2b"), "top": "jacket", "top_color": Color("#f8f8f4"), "bottom_color": Color("#2c3340"), "shoes": Color("#8a5a3a"), "accessory": "glasses", "accent": Color("#2fae8f"), "scale": 0.977}},
	{"id": "tower_t2_w", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(12.28, -2.05), "y_offset": 0.465, "ry": PI * 0.5, "action": "chat", "pose": "sit", "npc": "tower_t2_w", "table": Vector2(0.33, 0.745),
		"role": "guest", "seed": 1805732827, "look": {"sex": "f", "skin": Color("#87502b"), "hair_style": "long", "hair_color": Color("#bdb7b0"), "top": "tee", "top_color": Color("#ffd75e"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#33507a"), "scale": 0.943}},
	{"id": "tower_t2_e", "place": "tower_terrace", "region": "gym_terrace", "pos": Vector2(13.62, -2.05), "y_offset": 0.465, "ry": -PI * 0.5, "action": "drink", "pose": "sit", "npc": "tower_t2_e", "table": Vector2(0.33, 0.745),
		"role": "guest", "seed": 3851320387, "look": {"sex": "m", "skin": Color("#ffe3cc"), "hair_style": "short", "hair_color": Color("#bdb7b0"), "top": "jacket", "top_color": Color("#ff8552"), "bottom_color": Color("#cdb68c"), "shoes": Color("#e2504c"), "accessory": "glasses", "accent": Color("#8fd16a"), "scale": 0.976}},
	{"id": "bakery_staff", "place": "shops", "region": "ground", "pos": Vector2(-18.1, 12.2), "y_offset": 0.03, "ry": 0.0, "action": "serve_counter", "pose": "stand", "npc": "bakery_staff", "table": Vector2(0.41, 0.96),
		"role": "staff_bakery", "seed": 53616737, "look": {"sex": "f", "skin": Color("#ffe3cc"), "hair_style": "long", "hair_color": Color("#a8642f"), "top": "apron", "top_color": Color("#ffb98a"), "bottom_color": Color("#5d6e4b"), "shoes": Color("#f2c94c"), "accessory": "glasses", "accent": Color("#d99a5b"), "scale": 0.932}},
	{"id": "corner_cafe_staff", "place": "shops", "region": "ground", "pos": Vector2(-12.1, 12.2), "y_offset": 0.03, "ry": 0.0, "action": "wipe_counter", "pose": "stand", "npc": "corner_cafe_staff", "table": Vector2(0.41, 0.96),
		"role": "staff_corner_cafe", "seed": 764562919, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "curly", "hair_color": Color("#7b4a2b"), "top": "apron", "top_color": Color("#2f7fd8"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#ff8f73"), "scale": 0.985}},
	{"id": "bookstore_staff", "place": "shops", "region": "ground", "pos": Vector2(-6.1, 12.2), "y_offset": 0.03, "ry": 0.0, "action": "serve_counter", "pose": "stand", "npc": "bookstore_staff", "table": Vector2(0.41, 0.96),
		"role": "staff_bookstore", "seed": 126197861, "look": {"sex": "m", "skin": Color("#a86a3d"), "hair_style": "curly", "hair_color": Color("#4b3123"), "top": "apron", "top_color": Color("#4fb0ff"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#f2c94c"), "accessory": "beard", "accent": Color("#4f9be0"), "scale": 0.995}},
	{"id": "flowers_staff", "place": "shops", "region": "ground", "pos": Vector2(-0.1, 12.2), "y_offset": 0.03, "ry": 0.0, "action": "wipe_counter", "pose": "stand", "npc": "flowers_staff", "table": Vector2(0.41, 0.96),
		"role": "staff_flowers", "seed": 1807992214, "look": {"sex": "f", "skin": Color("#dba06f"), "hair_style": "short", "hair_color": Color("#f0d48e"), "top": "apron", "top_color": Color("#f8f8f4"), "bottom_color": Color("#cdb68c"), "shoes": Color("#4f86d6"), "accessory": "glasses", "accent": Color("#e86a9a"), "scale": 0.951}},
	{"id": "icecream_staff", "place": "shops", "region": "ground", "pos": Vector2(5.9, 12.2), "y_offset": 0.03, "ry": 0.0, "action": "serve_counter", "pose": "stand", "npc": "icecream_staff", "table": Vector2(0.41, 0.96),
		"role": "staff_icecream", "seed": 1752771200, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "short", "hair_color": Color("#7b4a2b"), "top": "apron", "top_color": Color("#ff8552"), "bottom_color": Color("#8e94a3"), "shoes": Color("#8a5a3a"), "accessory": "glasses", "accent": Color("#f2c84b"), "scale": 0.979}},
	{"id": "bakery_browse", "place": "shops", "region": "ground", "pos": Vector2(-20.9, 10.3), "y_offset": 0.03, "ry": PI, "action": "carry_bag", "pose": "stand", "npc": "bakery_browse", "table": Vector2(0.51, 1.0),
		"role": "guest", "seed": 368307856, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "curly", "hair_color": Color("#a8642f"), "top": "shirt", "top_color": Color("#ff8552"), "bottom_color": Color("#3d6491"), "shoes": Color("#f2c94c"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 0.948}},
	{"id": "bookstore_browse", "place": "shops", "region": "ground", "pos": Vector2(-8.0, 9.75), "y_offset": 0.03, "ry": PI, "action": "browse", "pose": "stand", "npc": "bookstore_browse", "table": Vector2(0.76, 1.35),
		"role": "guest", "seed": 442028069, "look": {"sex": "m", "skin": Color("#a86a3d"), "hair_style": "cap", "hair_color": Color("#c8325a"), "top": "tee", "top_color": Color("#a98cf0"), "bottom_color": Color("#22305a"), "shoes": Color("#e2504c"), "accessory": "scarf", "accent": Color("#ffd75e"), "scale": 0.991}},
	{"id": "icecream_browse", "place": "shops", "region": "ground", "pos": Vector2(2.9, 10.1), "y_offset": 0.03, "ry": PI, "action": "browse", "pose": "stand", "npc": "icecream_browse", "table": Vector2(0.61, 0.88),
		"role": "guest", "seed": 3805354458, "look": {"sex": "f", "skin": Color("#ffe3cc"), "hair_style": "bun", "hair_color": Color("#2a2220"), "top": "jacket", "top_color": Color("#ffd75e"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#4f86d6"), "accessory": "none", "accent": Color("#4fb0ff"), "scale": 0.936}},
	{"id": "bistro_cafe_w", "place": "bistro", "region": "ground", "pos": Vector2(-16.72, 15.55), "y_offset": 0.465, "ry": PI * 0.5, "action": "chat", "pose": "sit", "npc": "bistro_cafe_w", "table": Vector2(0.32, 0.745),
		"role": "guest", "seed": 1650051813, "look": {"sex": "m", "skin": Color("#dba06f"), "hair_style": "short", "hair_color": Color("#4b3123"), "top": "shirt", "top_color": Color("#a98cf0"), "bottom_color": Color("#2c3340"), "shoes": Color("#8a5a3a"), "accessory": "bag", "accent": Color("#33507a"), "scale": 0.993}},
	{"id": "bistro_cafe_e", "place": "bistro", "region": "ground", "pos": Vector2(-15.38, 15.55), "y_offset": 0.465, "ry": -PI * 0.5, "action": "drink", "pose": "sit", "npc": "bistro_cafe_e", "table": Vector2(0.33, 0.745),
		"role": "guest", "seed": 2834945275, "look": {"sex": "f", "skin": Color("#f7cfae"), "hair_style": "long", "hair_color": Color("#7b4a2b"), "top": "shirt", "top_color": Color("#2fae8f"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#2f2c2a"), "accessory": "none", "accent": Color("#2f7fd8"), "scale": 0.919}},
	{"id": "gym_treadmill_c", "place": "gym", "region": "ground", "pos": Vector2(13.5, -12.3), "y_offset": 0.185, "ry": PI, "action": "run", "pose": "run", "npc": "gym_treadmill_c", "table": Vector2(0.0, 1.0),
		"role": "athlete", "seed": 1829681292, "look": {"sex": "f", "skin": Color("#a86a3d"), "hair_style": "ponytail", "hair_color": Color("#7b4a2b"), "top": "sports", "top_color": Color("#4fb0ff"), "bottom_color": Color("#3d6491"), "shoes": Color("#2f2c2a"), "accessory": "none", "accent": Color("#2fae8f"), "scale": 0.942}},
	{"id": "studio_bike_c", "place": "gym", "region": "gym_l1", "pos": Vector2(14.0, -12.3), "y_offset": 0.79, "ry": PI, "action": "cycle", "pose": "cycle", "npc": "studio_bike_c", "table": Vector2(0.0, 1.0),
		"role": "athlete", "seed": 2433666780, "look": {"sex": "m", "skin": Color("#ecb98f"), "hair_style": "curly", "hair_color": Color("#d9a55a"), "top": "sports", "top_color": Color("#2fae8f"), "bottom_color": Color("#3d6491"), "shoes": Color("#ffffff"), "accessory": "beard", "accent": Color("#a98cf0"), "scale": 1.01}},
	{"id": "gym_rower", "place": "gym", "region": "ground", "pos": Vector2(13.7, -9.5), "y_offset": 0.28, "ry": PI * 0.5, "action": "row", "pose": "row", "npc": "gym_rower", "table": Vector2(0.0, 0.5),
		"role": "athlete", "seed": 119296506, "look": {"sex": "m", "skin": Color("#ecb98f"), "hair_style": "bald", "hair_color": Color("#4b3123"), "top": "sports", "top_color": Color("#ff6f7d"), "bottom_color": Color("#3d6491"), "shoes": Color("#2f2c2a"), "accessory": "none", "accent": Color("#a98cf0"), "scale": 0.995}},
	{"id": "gym_mat", "place": "gym", "region": "ground", "pos": Vector2(16.6, -7.1), "y_offset": 0.072, "ry": 0.0, "action": "stretch", "pose": "stretch", "npc": "gym_mat", "table": Vector2(0.0, 0.04),
		"role": "athlete", "seed": 2183366774, "look": {"sex": "f", "skin": Color("#ecb98f"), "hair_style": "ponytail", "hair_color": Color("#4b3123"), "top": "sports", "top_color": Color("#2f7fd8"), "bottom_color": Color("#2c3340"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 0.953}},
]
## One look per walker index (CityRules.walkers).
const WALKER_LOOKS := [
	{"seed": 301907621, "look": {"sex": "f", "skin": Color("#f7cfae"), "hair_style": "ponytail", "hair_color": Color("#7b4a2b"), "top": "dress", "top_color": Color("#2f7fd8"), "bottom_color": Color("#8e94a3"), "shoes": Color("#4f86d6"), "accessory": "scarf", "accent": Color("#8fd16a"), "scale": 0.955}},
	{"seed": 3443611536, "look": {"sex": "m", "skin": Color("#c58553"), "hair_style": "short", "hair_color": Color("#2a2220"), "top": "tee", "top_color": Color("#a98cf0"), "bottom_color": Color("#3d6491"), "shoes": Color("#8a5a3a"), "accessory": "bag", "accent": Color("#ffd75e"), "scale": 0.992}},
	{"seed": 1838505875, "look": {"sex": "f", "skin": Color("#c58553"), "hair_style": "bun", "hair_color": Color("#f0d48e"), "top": "shirt", "top_color": Color("#8fd16a"), "bottom_color": Color("#2c3340"), "shoes": Color("#8a5a3a"), "accessory": "glasses", "accent": Color("#5fcfa4"), "scale": 0.946}},
	{"seed": 2670756573, "look": {"sex": "m", "skin": Color("#f7cfae"), "hair_style": "curly", "hair_color": Color("#c95f35"), "top": "jacket", "top_color": Color("#ff6f7d"), "bottom_color": Color("#3d6491"), "shoes": Color("#ffffff"), "accessory": "bag", "accent": Color("#8fd16a"), "scale": 0.978}},
	{"seed": 4143340642, "look": {"sex": "f", "skin": Color("#c58553"), "hair_style": "bun", "hair_color": Color("#a8642f"), "top": "shirt", "top_color": Color("#f8f8f4"), "bottom_color": Color("#8e94a3"), "shoes": Color("#2f2c2a"), "accessory": "glasses", "accent": Color("#a98cf0"), "scale": 0.95}},
	{"seed": 4032944883, "look": {"sex": "m", "skin": Color("#61391f"), "hair_style": "bald", "hair_color": Color("#a8642f"), "top": "jacket", "top_color": Color("#ff9ec7"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#ffffff"), "accessory": "beard", "accent": Color("#33507a"), "scale": 0.99}},
	{"seed": 3368753843, "look": {"sex": "f", "skin": Color("#c58553"), "hair_style": "ponytail", "hair_color": Color("#4b3123"), "top": "dress", "top_color": Color("#ff6f7d"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#ffffff"), "accessory": "bag", "accent": Color("#5fcfa4"), "scale": 0.948}},
	{"seed": 2646508223, "look": {"sex": "m", "skin": Color("#dba06f"), "hair_style": "ponytail", "hair_color": Color("#2a2220"), "top": "tee", "top_color": Color("#5fcfa4"), "bottom_color": Color("#cdb68c"), "shoes": Color("#e2504c"), "accessory": "glasses", "accent": Color("#4fb0ff"), "scale": 1.0}},
	{"seed": 2986093547, "look": {"sex": "f", "skin": Color("#f7cfae"), "hair_style": "long", "hair_color": Color("#4b3123"), "top": "tee", "top_color": Color("#c8325a"), "bottom_color": Color("#2c3340"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#8fd16a"), "scale": 0.946}},
	{"seed": 3221774882, "look": {"sex": "m", "skin": Color("#ffe3cc"), "hair_style": "short", "hair_color": Color("#2a2220"), "top": "jacket", "top_color": Color("#2fae8f"), "bottom_color": Color("#22305a"), "shoes": Color("#f2c94c"), "accessory": "scarf", "accent": Color("#ff8552"), "scale": 1.009}},
]
## The Ferris wheel's four passenger slots (pairs: FERRIS_PAIRS), three looks each (child-sized: the cabins are).
const FERRIS_SLOTS := [
	{"slot": 0, "looks": [
		{"seed": 1830244924, "look": {"sex": "f", "skin": Color("#f7cfae"), "hair_style": "ponytail", "hair_color": Color("#a8642f"), "top": "tee", "top_color": Color("#c8325a"), "bottom_color": Color("#f0e6d2"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#4fb0ff"), "scale": 0.554}},
		{"seed": 3580670740, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "cap", "hair_color": Color("#5fcfa4"), "top": "tee", "top_color": Color("#2f7fd8"), "bottom_color": Color("#3d6491"), "shoes": Color("#f2c94c"), "accessory": "none", "accent": Color("#4fb0ff"), "scale": 0.559}},
		{"seed": 3739976311, "look": {"sex": "f", "skin": Color("#f7cfae"), "hair_style": "ponytail", "hair_color": Color("#7b4a2b"), "top": "tee", "top_color": Color("#ff8552"), "bottom_color": Color("#2c3340"), "shoes": Color("#4f86d6"), "accessory": "glasses", "accent": Color("#8fd16a"), "scale": 0.544}},
	]},
	{"slot": 1, "looks": [
		{"seed": 4125630504, "look": {"sex": "m", "skin": Color("#a86a3d"), "hair_style": "ponytail", "hair_color": Color("#7b4a2b"), "top": "shirt", "top_color": Color("#2fae8f"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#a98cf0"), "scale": 0.567}},
		{"seed": 3586967783, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "long", "hair_color": Color("#d9a55a"), "top": "dress", "top_color": Color("#33507a"), "bottom_color": Color("#22305a"), "shoes": Color("#f2c94c"), "accessory": "none", "accent": Color("#2f7fd8"), "scale": 0.555}},
		{"seed": 1794344376, "look": {"sex": "m", "skin": Color("#a86a3d"), "hair_style": "curly", "hair_color": Color("#7b4a2b"), "top": "tee", "top_color": Color("#8fd16a"), "bottom_color": Color("#cdb68c"), "shoes": Color("#8a5a3a"), "accessory": "glasses", "accent": Color("#ff6f7d"), "scale": 0.563}},
	]},
	{"slot": 2, "looks": [
		{"seed": 100498097, "look": {"sex": "m", "skin": Color("#87502b"), "hair_style": "short", "hair_color": Color("#d9a55a"), "top": "tee", "top_color": Color("#2fae8f"), "bottom_color": Color("#22305a"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#a98cf0"), "scale": 0.55}},
		{"seed": 900872719, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "curly", "hair_color": Color("#d9a55a"), "top": "tee", "top_color": Color("#5fcfa4"), "bottom_color": Color("#22305a"), "shoes": Color("#e2504c"), "accessory": "none", "accent": Color("#33507a"), "scale": 0.545}},
		{"seed": 2378429032, "look": {"sex": "m", "skin": Color("#61391f"), "hair_style": "bald", "hair_color": Color("#d9a55a"), "top": "tee", "top_color": Color("#33507a"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#a98cf0"), "scale": 0.548}},
	]},
	{"slot": 3, "looks": [
		{"seed": 391539529, "look": {"sex": "f", "skin": Color("#ffe3cc"), "hair_style": "ponytail", "hair_color": Color("#2a2220"), "top": "dress", "top_color": Color("#f8f8f4"), "bottom_color": Color("#2c3340"), "shoes": Color("#4f86d6"), "accessory": "none", "accent": Color("#33507a"), "scale": 0.566}},
		{"seed": 1857735678, "look": {"sex": "m", "skin": Color("#61391f"), "hair_style": "short", "hair_color": Color("#4b3123"), "top": "tee", "top_color": Color("#2fae8f"), "bottom_color": Color("#22305a"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 0.56}},
		{"seed": 1407095120, "look": {"sex": "f", "skin": Color("#61391f"), "hair_style": "bun", "hair_color": Color("#7b4a2b"), "top": "dress", "top_color": Color("#c8325a"), "bottom_color": Color("#cdb68c"), "shoes": Color("#ffffff"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 0.557}},
	]},
]
## Two riders on the carousel's horses (CityWorld.carousel_seat_transform(horse, t)).
const CAROUSEL_RIDERS := [
	{"id": "carousel_0", "horse": 1, "role": "guest", "seed": 2969851925, "look": {"sex": "f", "skin": Color("#87502b"), "hair_style": "ponytail", "hair_color": Color("#d9a55a"), "top": "shirt", "top_color": Color("#2fae8f"), "bottom_color": Color("#2c3340"), "shoes": Color("#f2c94c"), "accessory": "none", "accent": Color("#ffb98a"), "scale": 0.922}},
	{"id": "carousel_1", "horse": 5, "role": "rider", "seed": 2622910142, "look": {"sex": "m", "skin": Color("#ecb98f"), "hair_style": "curly", "hair_color": Color("#a8642f"), "top": "tee", "top_color": Color("#f8f8f4"), "bottom_color": Color("#6e4b3a"), "shoes": Color("#8a5a3a"), "accessory": "none", "accent": Color("#2f7fd8"), "scale": 0.563}},
]
# END GENERATED
