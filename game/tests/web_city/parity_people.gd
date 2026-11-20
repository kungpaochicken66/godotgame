## Parity fixture for the Three.js city's people (design/city-threejs.md §6): builds the Godot city and its
## people as tests/web_city/export.gd does (CityWorld.build() plus art/city_people.gd's setup), drives the
## people through scenes (view times; child riders in gondolas; sunny, rain beginning, settled and ending,
## changes mid-way, night; cut-away regions; frame() scheduling) and writes city_people.gd's own results:
## every instance transform (snapshot()), every instance colour, who is shown, the transforms written, and the
## rain state of the people who react. scripts/web_city/people.test.mjs replays the same scenes on the page's
## port (web_city/js/people_core.js) and compares.
##
##   scripts/godot.sh --headless --path game --script res://tests/web_city/parity_people.gd -- [--out=/abs/people.json]
## Without --out it writes <repo>/scripts/web_city/fixtures/people.json. Nothing renders.
##
## The file: {"version", "shapes", "alloc", "persons" (every Person's fixed fields), "rules" (the pure rules at
## chosen times), "color_sets" (base64 float32 r, g, b per instance, shape by shape; steps refer to them by
## index), "scenes": [{"name", "init": {"t", "riders", "weather"}, "steps": [...]}]}. A step is one call:
##   {"op": "riders" | "weather" | "hidden" | "reset_weather", ...}                       an input changes
##   {"op": "pose" | "frame", "t", "writes", "shown", "react", "wkey", ["xf", "col"]}     pose_at(t) or frame(t)
## "xf" is base64 of gzipped float32, 12 numbers per instance (the basis's x, y, z columns, then the origin),
## shape by shape; "shown" is one character per person; "react" is the _eval() state of each person who reacts;
## "wkey" is the people's weather key (a new one begins a new weather phase).
## Every time in the scenes is a short decimal or a dyadic fraction, so JSON carries it exactly.
extends SceneTree

const CityWorld := preload("res://scripts/world/city_world.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const Data := preload("res://scripts/core/city_people_data.gd")
const People := preload("res://scripts/art/city_people.gd")
const WebJson := preload("res://scripts/web/web_json.gd")

const VERSION := 1
const SUNNY := {"weather": 0, "since": -4.0, "prev": Vector3(1, 0, 0)}


## The people, recording the instance colours as they are set (the headless renderer keeps no MultiMesh data).
class RecPeople extends "res://scripts/art/city_people.gd":
	var cols: Array = []

	func _col(p: Person, part: int, c: Color) -> void:
		super(p, part, c)
		var sl := p.slots[part]
		if sl < 0:
			return
		if cols.is_empty():
			for m in M_COUNT:
				var a := PackedFloat32Array()
				a.resize(_alloc[m] * 3)
				a.fill(1.0)
				cols.append(a)
		var list: PackedFloat32Array = cols[sl >> 16]
		var i := (sl & 0xFFFF) * 3
		list[i] = c.r
		list[i + 1] = c.g
		list[i + 2] = c.b
		cols[sl >> 16] = list


var cw: CityWorld
var color_sets: Array = []
var _color_index := {}
var _snaps := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../scripts/web_city/fixtures/people.json").simplify_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var holder := Node3D.new()
	root.add_child(holder)
	cw = CityWorld.new()
	cw.name = "City"
	holder.add_child(cw)
	cw.setup(holder)
	cw.build()

	var scenes: Array = []
	var first := _new_people(20.0, {}, SUNNY)
	var doc := {"version": VERSION, "source": "tests/web_city/parity_people.gd", "shapes": People.MESH_NAMES,
		"alloc": Array(first._alloc), "persons": _persons(first), "rules": _rules(first)}
	first.free()

	# ---- sunny, nobody on the wheel: plain view times (the wheel's rides begin and end among them)
	scenes.append(_scene("sunny", 20.0, {}, SUNNY, [
		["pose", 0.0], ["pose", 0.5], ["pose", 37.25], ["pose", 79.5], ["pose", 123.456], ["pose", 599.9],
		["pose", 1800.25], ["pose", 43210.125]]))

	# ---- frame(): the moving people every frame, the slow ones in alternating halves; a paused frame writes
	# nothing; a cutaway change makes the next frame run
	scenes.append(_scene("frames", 100.0, {}, SUNNY, [
		["frame", 100.015625], ["frame", 100.03125], ["frame", 100.03125, false], ["frame", 100.046875],
		["hidden", ["gym_roof", "office_l2"]], ["frame", 100.046875], ["frame", 100.0625, false], ["frame", 100.078125],
		["hidden", []], ["frame", 100.078125], ["frame", 100.09375, false], ["frame", 100.109375]]))

	# ---- children on the wheel: their gondola carries no passenger, nor until its next bottom pass
	scenes.append(_scene("riders", 150.0, {}, SUNNY, [
		["riders", {4: [7, 9], 2: [5]}], ["pose", 152.0], ["frame", 152.0, false], ["frame", 152.015625, false],
		["riders", {}], ["frame", 152.015625], ["pose", 180.0], ["pose", 205.0],
		["riders", {4: [3]}], ["pose", 210.0], ["riders", {}], ["pose", 250.0], ["pose", 300.0], ["pose", 330.0]]))

	# ---- rain: mid-blend (the first seconds), people leaving in their groups, settled; then the way back
	scenes.append(_scene("rain", 1000.0, {}, SUNNY, [
		["weather", {"weather": 1, "since": 1000.5, "prev": Vector3(1, 0, 0)}],
		["pose", 1001.0], ["pose", 1003.0], ["pose", 1005.5], ["pose", 1008.0], ["pose", 1011.0], ["pose", 1015.0],
		["pose", 1022.0], ["pose", 1040.0], ["pose", 1100.0],
		["weather", {"weather": 0, "since": 1100.25, "prev": Vector3(0, 1, 0)}],
		["pose", 1101.0], ["pose", 1104.0], ["pose", 1108.0], ["pose", 1113.0], ["pose", 1120.0], ["pose", 1130.0],
		["pose", 1150.0], ["pose", 1200.0], ["pose", 1300.0]]))

	# ---- the weather changes mid-way (nobody jumps), then night ends the rain
	scenes.append(_scene("rain_changes", 2000.0, {4: [11]}, SUNNY, [
		["weather", {"weather": 1, "since": 2000.0, "prev": Vector3(1, 0, 0)}],
		["pose", 2004.0], ["pose", 2006.0],
		["weather", {"weather": 0, "since": 2006.0, "prev": Vector3(0.2, 0.8, 0)}],
		["pose", 2006.0], ["pose", 2007.5], ["pose", 2010.0],
		["weather", {"weather": 1, "since": 2011.0, "prev": Vector3(0.7, 0.3, 0)}],
		["pose", 2011.0], ["pose", 2012.0], ["pose", 2016.0], ["pose", 2030.0],
		["weather", {"weather": 2, "since": 2035.0, "prev": Vector3(0, 1, 0)}],
		["pose", 2036.0], ["pose", 2045.0], ["pose", 2070.0], ["pose", 2150.0]]))

	# ---- arriving with no memory: just after the rain ended (everybody is assumed under cover and returns),
	# then a new city in old rain (everybody under cover at once)
	scenes.append(_scene("assumed", 3000.0, {}, {"weather": 0, "since": 2999.0, "prev": Vector3(0, 1, 0)}, [
		["pose", 3003.0], ["pose", 3010.0], ["pose", 3025.0], ["pose", 3060.0],
		["reset_weather"], ["weather", {"weather": 1, "since": 2000.0, "prev": Vector3(1, 0, 0)}],
		["pose", 3070.0], ["pose", 3075.5]]))

	# ---- cut-away regions with rain: a person hides with the region it is on, on its way too
	scenes.append(_scene("hidden_rain", 4000.0, {}, {"weather": 1, "since": 3900.0, "prev": Vector3(1, 0, 0)}, [
		["hidden", ["skywalk_a"]], ["pose", 4000.0],
		["hidden", ["cafe_terrace", "gym_roof", "office_l1"]], ["pose", 4001.0],
		["weather", {"weather": 0, "since": 4002.0, "prev": Vector3(0, 1, 0)}],
		["hidden", ["skywalk_a", "gym_l1"]], ["pose", 4004.0], ["pose", 4008.0],
		["frame", 4008.125], ["frame", 4008.25, false], ["hidden", []], ["frame", 4008.25], ["pose", 4030.0]]))

	# ---- night, and no weather at all
	scenes.append(_scene("night", 5000.0, {}, {"weather": 2, "since": 4998.0, "prev": Vector3(1, 0, 0)}, [
		["pose", 5001.5], ["weather", {}], ["pose", 5002.0], ["frame", 5002.25, false]]))

	# ---- a walker back in step with its lane (the second after it meets its slot, when its stride eases into the
	# lane's), and rain beginning again in that very second (the stride offset carries over). The times come from
	# the walkers' own records, snapped to 1/64 s, so they keep finding those moments if the map changes.
	scenes.append(_scene("meet", 7000.0, {}, SUNNY, [
		["weather", {"weather": 1, "since": 7000.0, "prev": Vector3(1, 0, 0)}], ["pose", 7030.0, false],
		["weather", {"weather": 0, "since": 7031.0, "prev": Vector3(0, 1, 0)}], ["pose", 7031.5, false],
		["pose_meet", 0, 0.296875], ["pose_meet", 0, 0.5], ["pose_meet", 2, 0.25],
		["weather_now", 1, Vector3(1, 0, 0)], ["pose_rel", 0.25], ["pose_rel", 0.5], ["pose_rel", 8.0]]))

	# ---- two showers close together: a walker still sheltering keeps its spot, so a walker leaving its lane
	# for the second shower goes to another one (found by search: without that rule walker 7 would take 8's spot)
	scenes.append(_scene("held", 8000.0, {}, SUNNY, [
		["weather", {"weather": 1, "since": 8000.0, "prev": Vector3(1, 0, 0)}], ["pose", 8008.0, false],
		["weather", {"weather": 0, "since": 8008.0, "prev": Vector3(0, 1, 0)}], ["pose", 8011.0, false],
		["weather", {"weather": 1, "since": 8011.0, "prev": Vector3(1, 0, 0)}], ["pose", 8011.5], ["pose", 8030.0]]))

	# ---- frame() through a shower's beginning: the weather tick and the scheduling together
	var steps: Array = [["weather", {"weather": 1, "since": 6000.25, "prev": Vector3(1, 0, 0)}]]
	for k in 24:
		steps.append(["frame", 6000.25 + 0.5 * float(k + 1), k % 8 == 7])
	scenes.append(_scene("frames_rain", 6000.0, {0: [2]}, SUNNY, steps))

	doc["color_sets"] = color_sets
	doc["scenes"] = scenes
	var text := JSON.stringify(WebJson.value(doc), "", false)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("WEB CITY PEOPLE PARITY OK: %d scenes, %d snapshots, %d colour sets, %d bytes -> %s" % [
		scenes.size(), _snaps, color_sets.size(), text.length(), out])
	quit(0)


func _new_people(t: float, riders: Dictionary, weather: Variant) -> RecPeople:
	var pp := RecPeople.new()
	pp.set_process(false)
	pp.time_override = t
	pp.riders_override = riders
	pp.weather_override = weather
	cw.add_child(pp)
	pp.setup(cw)
	return pp


## One scene on fresh people. `steps`: ["pose" | "frame", t, (false: no transforms in the file)],
## ["riders", {gondola: [peers]}], ["weather", state], ["hidden", [regions]], ["reset_weather"], and three whose
## time comes from the run itself: ["pose_meet", k, after] (see _meet_time), ["pose_rel", seconds after the last
## pose], ["weather_now", weather, prev] (a weather change at the last pose's time).
func _scene(scene_name: String, t0: float, riders: Dictionary, weather: Variant, steps: Array) -> Dictionary:
	var pp := _new_people(t0, riders, weather)
	var out_steps: Array = []
	var init := {"t": t0, "riders": riders, "weather": WebJson.value(weather)}
	# the first pose's transforms go in the file where it is not one more plain sunny pose
	init.merge(_snap(pp, t0, pp.writes_last, scene_name == "sunny" or weather != SUNNY))
	var now := t0
	for s: Array in steps:
		# the steps whose time comes from the people's own state become plain steps
		match String(s[0]):
			"pose_meet":
				s = ["pose", _meet_time(pp, now, int(s[1]), float(s[2]))]
			"pose_rel":
				s = ["pose", now + float(s[1])]
			"weather_now":
				s = ["weather", {"weather": int(s[1]), "since": now, "prev": s[2]}]
		match String(s[0]):
			"riders":
				pp.riders_override = s[1]
				out_steps.append({"op": "riders", "riders": s[1]})
			"weather":
				pp.weather_override = s[1]
				out_steps.append({"op": "weather", "weather": WebJson.value(s[1])})
			"hidden":
				pp.set_hidden_regions(s[1])
				out_steps.append({"op": "hidden", "regions": s[1]})
			"reset_weather":
				pp.reset_weather()
				out_steps.append({"op": "reset_weather"})
			"pose", "frame":
				var t := float(s[1])
				now = t
				pp.time_override = t
				var writes := pp.pose_at(t) if String(s[0]) == "pose" else pp.frame(t)
				var d := {"op": String(s[0]), "t": t}
				d.merge(_snap(pp, t, writes, s.size() < 3 or bool(s[2])))
				out_steps.append(d)
	pp.free()
	return {"name": scene_name, "init": init, "steps": out_steps}


## The k-th next moment a walker meets its lane slot again after `now`, plus `after` seconds, on a 1/64 s grid.
func _meet_time(pp: RecPeople, now: float, k: int, after: float) -> float:
	var meets: Array = []
	for p: People.Person in pp.people:
		if p.kind == People.K_WALKER and not p.umbrella and p.rec.has("t_meet") and float(p.rec["t_meet"]) > now:
			meets.append(float(p.rec["t_meet"]))
	meets.sort()
	if meets.is_empty():
		push_error("parity_people: no walker is on its way back to its lane after %.3f" % now)
		return now + 1.0
	return snappedf(float(meets[mini(k, meets.size() - 1)]) + after, 0.015625)


func _snap(pp: RecPeople, t: float, writes: int, with_xf: bool) -> Dictionary:
	var d := {"writes": writes}
	var shown := ""
	var react := {}
	for p: People.Person in pp.people:
		shown += "1" if p.shown else "0"
		if p.react:
			var e := pp._eval(p, t)
			react[p.id] = {"s": e["s"], "lam": e["lam"], "ph": e["ph"], "umb": e["umb"], "walked": e["walked"],
				"on_lane": e["on_lane"], "moving": e["moving"], "back": e["back"], "spot": p.spot, "n": p.base.size()}
	d["shown"] = shown
	d["react"] = react
	d["wkey"] = pp._wkey
	if with_xf:
		_snaps += 1
		var floats := PackedFloat32Array()
		for list: Array[Transform3D] in pp._xf:
			for xf: Transform3D in list:
				floats.append_array(PackedFloat32Array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y,
					xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z]))
		d["xf"] = Marshalls.raw_to_base64(floats.to_byte_array().compress(FileAccess.COMPRESSION_GZIP))
		var all := PackedFloat32Array()
		for list: PackedFloat32Array in pp.cols:
			all.append_array(list)
		var b64 := Marshalls.raw_to_base64(all.to_byte_array())
		if not _color_index.has(b64):
			_color_index[b64] = color_sets.size()
			color_sets.append(b64)
		d["col"] = int(_color_index[b64])
	return d


## Every person's fixed fields, as city_people.gd made them.
func _persons(pp: RecPeople) -> Array:
	var out: Array = []
	for p: People.Person in pp.people:
		var hair := {}
		for hs: String in p.hair_part:
			hair[hs] = int(p.hair_part[hs])
		out.append({"id": p.id, "kind": p.kind, "index": p.index, "action": p.action, "region": p.region,
			"seated": p.seated, "legs_still": p.legs_still, "fast": p.fast, "group": p.group,
			"root": WebJson.value(p.root)["xf"], "seat": p.seat, "table": p.table, "offset": p.offset, "rate": p.rate,
			"slot": p.slot, "partner_yaw": p.partner_yaw, "partner_rank": p.partner_rank, "pair_seed": p.pair_seed,
			"has_partner": p.has_partner, "sd": p.sd, "slots": Array(p.slots), "hair_part": hair, "looks": p.looks.size(),
			"react": p.react, "umbrella": p.umbrella, "legs_seat": p.legs_seat, "spot": p.spot, "umb_hand": p.umb_hand,
			"base_len": Array(p.base_len)})
	return out


## The pure rules the port carries, at chosen times.
func _rules(pp: RecPeople) -> Dictionary:
	var times: Array = [0.0, 0.25, 13.7, 79.99, 80.0, 123.456, 200.0, 229.999, 230.0, 345.6, 1000.5, 4321.0625, 86400.5, 250000.75]
	var walkers: Array = []
	var ferris: Array = []
	var laps: Array = []
	var seats: Array = []
	for t: float in times:
		var ws: Array = []
		for w: Dictionary in CityRules.walkers(t):
			ws.append([(w["pos"] as Vector2).x, (w["pos"] as Vector2).y, float(w["ry"]), float(w["phase"])])
		walkers.append(ws)
		var fr: Array = []
		for r: Dictionary in Data.ferris_rides(t):
			fr.append([int(r["slot"]), int(r["gondola"]), int(r["seat"]), int(r["ride"]), int(r["variant"])])
		ferris.append(fr)
		var ll: Array = []
		for g in int(CityMap.FERRIS["gondolas"]):
			ll.append(Data.gondola_lap(g, t))
		laps.append(ll)
		var st: Array = []
		for g in int(CityMap.FERRIS["gondolas"]):
			st.append(WebJson.value(CityWorld.rider_transform(g, CityWorld.ferris_angle_at(t), g % 2))["xf"])
		for h in int(CityMap.CAROUSEL["horses"]):
			st.append(WebJson.value(CityWorld.carousel_seat_transform(h, t))["xf"])
		seats.append(st)
	var hashes: Array = []
	for a: int in [0, 1, 7, 1000, 123456789, 2993932774, 4294967295, 4294967495]:
		for b: int in [0, 1, 5, 101, 777, 9000, 123456]:
			hashes.append([a, b, Data.hash01(a, b)])
	var seeds := {}
	var delays: Array = []
	var umbrellas := {}
	for p: People.Person in pp.people:
		seeds[p.id] = Data.seed_of(p.id)
		umbrellas[p.id] = Data.umbrella_for(p.id)
		for at: Vector2 in [Vector2(-20.3, 15.6), Vector2(3.9, -7.75), Vector2(31.99, -24.0)]:
			delays.append([p.id, at.x, at.y, Data.group_delay(p.id, at, 9.0)])
	var projections: Array = []
	var loops := CityRules.walk_loops()
	for li in loops.size():
		var pts: Array = (loops[li] as Dictionary)["pts"]
		for q: Vector2 in [Vector2(-20.0, 15.6), Vector2(8.4, -23.8), Vector2(0.0, 0.0), Vector2(22.4, 6.3), Vector2(-32.0, 24.0), Vector2(15.5, 12.2)]:
			var pr := CityRules.poly_project(pts, q)
			projections.append([li, q.x, q.y, pr.x, pr.y])
	return {"times": times, "walkers": walkers, "ferris": ferris, "laps": laps, "seats": seats, "hash01": hashes,
		"seed_of": seeds, "group_delay": delays, "umbrella_for": umbrellas, "poly_project": projections}
