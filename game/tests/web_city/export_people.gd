## The people's static tables for the Three.js city (design/city-threejs.md §6): what art/city_people.gd and
## the rules work out once at load from the map (the navigation's cover spots and routes, the walkers' lanes
## and their ways off them), exported so the page's port (web_city/js/people_*.js) does not have to carry the
## navigation. Nothing here depends on time: everything that moves is ported, not exported.
##
## tests/web_city/export.gd calls extra() and writes the result as consts.extra.people:
##   walk_loops   CityRules.walk_loops(): [{pts, speed, count, first, length}]
##   gap_dir      the side the carousel's fence opens on (CityWorld.carousel_gap_dir)
##   spots        every cover stand spot, in the people's order: [{region, pos, y, cover, shop}]
##   held         the spots taken at load: {spot index: person id} (static people, carousel riders)
##   react        the people who react to rain, with their fixed spot and path:
##                {id: {umbrella, legs_seat, spot, base (points), base_len, base_reg}}
##   exits        the ways off the walkers' lanes: [{loop, spot, arc, len, leg (points)}] (none when a spot
##                cannot be reached from a lane)
extends RefCounted

const People := preload("res://scripts/art/city_people.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")


static func extra() -> Dictionary:
	var cw := CityWorld.new()
	var pp := People.new()
	pp.time_override = 0.0
	pp.riders_override = {}
	pp.weather_override = {"weather": 0, "since": -1.0e9, "prev": Vector3(1, 0, 0)}
	pp.setup(cw)
	var out := {}
	var loops: Array = []
	for l: Dictionary in CityRules.walk_loops():
		loops.append({"pts": l["pts"], "speed": float(l["speed"]), "count": int(l["count"]), "first": int(l["first"]),
			"length": float(l["length"])})
	out["walk_loops"] = loops
	out["gap_dir"] = CityWorld.carousel_gap_dir()
	out["spots"] = pp.spots
	var held := {}
	for k: Variant in pp._held:
		held[int(k)] = String(pp._held[k])
	out["held"] = held
	var react := {}
	for p: People.Person in pp.people:
		if not p.react:
			continue
		react[p.id] = {"umbrella": p.umbrella, "legs_seat": p.legs_seat, "spot": p.spot, "base": p.base,
			"base_len": p.base_len, "base_reg": p.base_reg}
	out["react"] = react
	var exits: Array = []
	for li in CityRules.walk_loops().size():
		for si in pp.spots.size():
			var key := Vector2i(li, si)
			if not pp._exits.has(key):
				continue
			var ex: Dictionary = pp._exits[key]
			if ex.is_empty():
				continue
			exits.append({"loop": li, "spot": si, "arc": float(ex["arc"]), "len": float(ex["len"]), "leg": ex["leg"]})
	out["exits"] = exits
	pp.free()
	cw.free()
	return out
