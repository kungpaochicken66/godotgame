## The city district's shared rules (design/city-district.md "Playable rules"): pure, deterministic and
## node-free, run by the authority (the solo device, the host or the server). Clients draw pack()'s state.
##
##   - interaction occupancy: seats, exercise machines and desks hold one child each; order and shop are
##     momentary and return a small result ({"line": ..., "prop": ...}); a disconnect frees at once;
##   - the Ferris wheel: gondola angle is a pure function of time; boarding only on the platform within
##     REACH and only while a gondola is within the boarding window of the bottom, two seats per gondola;
##     a rider rides at least one full turn and leaves only at the bottom (after the turn, or on request
##     at the next bottom pass); a disconnect frees the seat at once;
##   - traffic: positions along ROAD_LOOP, advanced in tick(dt, kids) so a vehicle can stop while a child
##     is within STOP_AHEAD in its lane (or while another vehicle is close ahead);
##   - walkers: PEDESTRIANS people along an inward offset of PED_LOOP, a pure function of time.
##
## Directions: forward of a yaw ry is (sin ry, cos ry) in (x, z), as everywhere in the game.
extends RefCounted

const CityMap := preload("res://scripts/core/city_map.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")

const VERSION := 3.0
## A vehicle stops while a child's centre is this far ahead of its front, within LANE_HALF of the lane line.
const STOP_AHEAD := 3.5
const LANE_HALF := 3.0
const ACCEL := 3.0
const DECEL := 9.0
## Following: stop closer than FOLLOW_STOP to the vehicle in front, match its speed within FOLLOW_SLOW.
## r2: one lane, nobody passes. A vehicle keeps CityMap.VEHICLE_GAP (bumper to bumper) behind the one ahead:
## it never goes faster than it could still stop in the free gap at BRAKE (the hard limit is DECEL > BRAKE).
const BRAKE := 6.0
## Buses: dwell BUS_DWELL at each stop, + up to DWELL_EXTRA_MAX when closer to the bus ahead than the even headway
## (none at even, the full extra at BUNCH_FRACTION of it or closer): the buses spread out again.
const DWELL_EXTRA_MAX := 3.0
const BUNCH_FRACTION := 0.6
const STOP_CREEP := 0.3
const TICK_MAX := 0.1
## The offsets from a PED_LOOP leg (positive: toward the middle of the block) tried in turn.
const WALKER_R := 0.25
## Walking speeds of the three loops (m/s), the metres per walk cycle, and the least lane separation.
const WALK_SPEEDS := [1.2, 1.0, 1.4]
const WALK_STRIDE := 1.5
const WALK_SEPARATION := 0.8

## The shop and order results: key -> {"line", "prop"} (line is a text key for the HUD, prop the thing shown).
const RESULTS := {
	"cafe_counter": {"line": "hot_chocolate", "prop": "cup"},
	"restaurant_order": {"line": "dinner", "prop": "plate"},
	"shop_bakery": {"line": "bun", "prop": "bun"},
	"shop_flowers": {"line": "flower", "prop": "flower"},
	"shop_cafe": {"line": "cupcake", "prop": "cupcake"},
	"shop_books": {"line": "book", "prop": "book"},
	"shop_icecream": {"line": "ice_cream", "prop": "cone"},
}

## Authority state.
var time := 0.0
var occupancy: Dictionary = {}     # interaction key -> peer
var riders: Dictionary = {}        # peer -> {"g", "seat", "t_board", "exit_at"}
var vehicles: Array = []           # [{"s": centre arc position, "v": speed, "dwell": seconds left at a stop, "stop": next stop index (-1 for cars)}]
## The shared weather (city r3). `weather` is an index into CityMap.WEATHERS (sunny on wake). The blend is
## kept as the MIX BEFORE the last change: `weather_prev` is an Array of three floats (doubles) (sunny, rain, night) summing to 1
## taken at the moment of the change (so a change in the middle of a blend starts from the current mix and
## nothing jumps), `weather_since` the rules time of the change. weights(t) = prev * (1 - e) + onehot(weather) * e
## with e = smoothstep((t - since) / WEATHER_BLEND). A fresh city is fully sunny (since = -WEATHER_BLEND).
var weather := 0
var weather_prev: Array = [1.0, 0.0, 0.0]
var weather_since := -4.0
## Riders who got off during the last tick(): [{"peer", "gondola", "region", "pos"}].
var exits: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	time = 0.0
	occupancy = {}
	riders = {}
	exits = []
	vehicles = []
	weather = 0
	weather_prev = [1.0, 0.0, 0.0]
	weather_since = -float(CityMap.WEATHER_BLEND)
	var length := loop_length()
	for v: Dictionary in CityMap.VEHICLES:
		var s0 := fposmod(float(v["start"]) * length, length)
		vehicles.append({"s": s0, "v": 0.0, "dwell": 0.0, "stop": _next_stop(s0) if String(v["kind"]) == "bus" else -1})


# ------------------------------------------------------------------ occupancy

static func _norm(region: String) -> String:
	return "" if region == "ground" else region


static func pose_of(key: String) -> String:
	var kind: String = (CityMap.INTERACTIONS[key] as Dictionary)["kind"]
	match kind:
		"seat":
			return "sit"
		"desk":
			return "type"
		"exercise":
			if key.contains("treadmill"):
				return "run"
			if key.contains("weights"):
				return "lift"
			return "cycle"
	return ""


## Who holds an interaction (-1: nobody).
func occupant(key: String) -> int:
	return int(occupancy.get(key, -1))


## The interaction a peer holds ("" when none).
func held(peer: int) -> String:
	for k: String in occupancy:
		if int(occupancy[k]) == peer:
			return k
	return ""


## The nearest interaction within REACH of pos on the region, preferring a free one for `peer`: "" if none.
static func nearest(region: String, pos: Vector2) -> String:
	region = _norm(region)
	var best := ""
	var best_d := INF
	for k: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[k]
		if _norm(String(it["region"])) != region:
			continue
		var d := pos.distance_to(it["pos"])
		if d <= CityMap.REACH and d < best_d - 1e-9:
			best_d = d
			best = k
	return best


## The interaction the action button should offer: the nearest FREE one within REACH (or one the peer holds).
func offer(peer: int, region: String, pos: Vector2) -> String:
	region = _norm(region)
	var best := ""
	var best_d := INF
	for k: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[k]
		if _norm(String(it["region"])) != region:
			continue
		var d := pos.distance_to(it["pos"])
		if d > CityMap.REACH or d >= best_d - 1e-9:
			continue
		var o := occupant(k)
		if o != -1 and o != peer:
			continue
		best_d = d
		best = k
	return best


## Use an interaction. {"ok": false, "reason": "unknown" | "level" | "far" | "busy" | ...} or {"ok": true, "kind", "key", ...}:
## holding kinds (seat, exercise, desk) add "hold": true, "pose" and "pos" (where the child is put);
## momentary kinds (order, shop) add "line" and "prop"; ride answers like board(); travel adds "travel": true.
func use(peer: int, key: String, region: String, pos: Vector2) -> Dictionary:
	if not CityMap.INTERACTIONS.has(key):
		return {"ok": false, "reason": "unknown"}
	var it: Dictionary = CityMap.INTERACTIONS[key]
	if _norm(String(it["region"])) != _norm(region):
		return {"ok": false, "reason": "level"}
	var ipos: Vector2 = it["pos"]
	if pos.distance_to(ipos) > CityMap.REACH:
		return {"ok": false, "reason": "far"}
	var kind: String = it["kind"]
	match kind:
		"seat", "exercise", "desk":
			var o := occupant(key)
			if o != -1 and o != peer:
				return {"ok": false, "reason": "busy"}
			if riders.has(peer):
				return {"ok": false, "reason": "riding"}
			release(peer)
			occupancy[key] = peer
			return {"ok": true, "kind": kind, "key": key, "hold": true, "pose": pose_of(key), "pos": ipos}
		"order", "shop":
			var res: Dictionary = (RESULTS[key] as Dictionary).duplicate() if RESULTS.has(key) else {"line": "", "prop": ""}
			res["ok"] = true
			res["kind"] = kind
			res["key"] = key
			return res
		"ride":
			var b := board(peer, time, region, pos)
			b["kind"] = kind
			b["key"] = key
			return b
		"travel":
			return {"ok": true, "kind": kind, "key": key, "travel": true}
	return {"ok": false, "reason": "unknown"}


## Free whatever a peer holds (stands up). Returns the freed key ("" if none). Riders are not touched.
func release(peer: int) -> String:
	for k: String in occupancy.keys():
		if int(occupancy[k]) == peer:
			occupancy.erase(k)
			return k
	return ""


## A peer left (disconnect, or travelled away): frees the seat or machine AND the gondola seat at once.
func leave(peer: int) -> void:
	release(peer)
	riders.erase(peer)


# ------------------------------------------------------------------ the wheel

static func ferris_period() -> float:
	return float((CityMap.FERRIS as Dictionary)["period"])


## Angle of gondola i (0 = the lowest point of the wheel; it grows with time: bottom, east, top, west).
static func gondola_angle(i: int, t: float) -> float:
	var n := int((CityMap.FERRIS as Dictionary)["gondolas"])
	return TAU * fposmod(t / ferris_period() + float(i) / float(n), 1.0)


## Where gondola i's floor centre is (it hangs level below its rim point).
static func gondola_pos(i: int, t: float) -> Vector3:
	var f: Dictionary = CityMap.FERRIS
	var hub: Vector3 = f["hub"]
	var a := gondola_angle(i, t)
	var r: float = f["radius"]
	return Vector3(hub.x + r * sin(a), hub.y - r * cos(a) - float(f["hang"]), hub.z)


## Signed seconds since gondola i was at the bottom (negative: still coming). Within (-period/2, period/2].
static func bottom_offset(i: int, t: float) -> float:
	var a := gondola_angle(i, t)
	if a > PI:
		a -= TAU
	return a / TAU * ferris_period()


## The boarding window is board_window seconds wide in all, centred on the bottom pass.
static func window_half() -> float:
	return float((CityMap.FERRIS as Dictionary)["board_window"]) * 0.5


static func at_bottom(i: int, t: float) -> bool:
	return absf(bottom_offset(i, t)) <= window_half() + 1e-9


## The gondola inside the boarding window, or -1.
static func bottom_gondola(t: float) -> int:
	var n := int((CityMap.FERRIS as Dictionary)["gondolas"])
	var best := -1
	var best_o := INF
	for i in n:
		var o := absf(bottom_offset(i, t))
		if o <= window_half() + 1e-9 and o < best_o:
			best_o = o
			best = i
	return best


## The first time at or after t that gondola g is exactly at the bottom.
static func next_bottom(g: int, t: float) -> float:
	var n := int((CityMap.FERRIS as Dictionary)["gondolas"])
	var period := ferris_period()
	# bottom passes of g: (k - g / n) * period
	var k := ceilf(t / period + float(g) / float(n) - 1e-9)
	return (k - float(g) / float(n)) * period


func gondola_riders(g: int) -> Array:
	var out: Array = []
	for peer: int in riders:
		if int((riders[peer] as Dictionary)["g"]) == g:
			out.append(peer)
	out.sort()
	return out


func is_riding(peer: int) -> bool:
	return riders.has(peer)


## Board at time t from the platform (ground, within REACH of FERRIS.board_at). `laps` full turns at least one.
## {"ok": true, "gondola", "seat", "exit_at"} or {"ok": false, "reason": "riding" | "level" | "far" | "wait" | "full"}.
func board(peer: int, t: float, region: String, pos: Vector2, laps := 1) -> Dictionary:
	if riders.has(peer):
		return {"ok": false, "reason": "riding"}
	if _norm(region) != "":
		return {"ok": false, "reason": "level"}
	var f: Dictionary = CityMap.FERRIS
	if pos.distance_to(f["board_at"]) > CityMap.REACH:
		return {"ok": false, "reason": "far"}
	var g := bottom_gondola(t)
	if g < 0:
		return {"ok": false, "reason": "wait"}
	var taken: Array = []
	for p: int in gondola_riders(g):
		taken.append(int((riders[p] as Dictionary)["seat"]))
	var seat := -1
	for s in int(f["seats"]):
		if not taken.has(s):
			seat = s
			break
	if seat < 0:
		return {"ok": false, "reason": "full"}
	release(peer)
	var exit_at := t + ferris_period() * float(maxi(laps, 1))
	riders[peer] = {"g": g, "seat": seat, "t_board": t, "exit_at": exit_at}
	return {"ok": true, "gondola": g, "seat": seat, "exit_at": exit_at}


## Ask to get off: at the next bottom pass, but never before one full turn. Returns {"ok", "exit_at"}.
func request_off(peer: int, t: float) -> Dictionary:
	if not riders.has(peer):
		return {"ok": false, "reason": "not_riding"}
	var r: Dictionary = riders[peer]
	var earliest := float(r["t_board"]) + ferris_period()
	var at := maxf(earliest, next_bottom(int(r["g"]), t))
	# the rider's own exit never gets later than a request makes it
	r["exit_at"] = minf(float(r["exit_at"]), at)
	return {"ok": true, "exit_at": float(r["exit_at"])}


func _ferris_tick() -> void:
	var f: Dictionary = CityMap.FERRIS
	for peer: int in riders.keys():
		var r: Dictionary = riders[peer]
		if time >= float(r["exit_at"]) - 1e-9:
			riders.erase(peer)
			exits.append({"peer": peer, "gondola": int(r["g"]), "region": "", "pos": f["board_at"]})


# ------------------------------------------------------------------ weather

## The weather as a plain state (what pack() carries and clients blend from):
## {"weather": int, "since": float, "prev": Array[3] (weights sunny, rain, night)}.
func weather_state() -> Dictionary:
	return {"weather": weather, "since": weather_since, "prev": weather_prev}


## The mix at time t: {"sunny", "rain", "night"} weights summing to 1. `state` is a weather_state() dictionary or
## this class's instance. Eased (smoothstep) over CityMap.WEATHER_BLEND from the previous mix to the weather.
static func weather_weights(state: Variant, t: float) -> Dictionary:
	var w: int
	var since: float
	var raw: Variant
	if state is Dictionary:
		w = int(state["weather"])
		since = float(state["since"])
		raw = state["prev"]
	else:
		w = int(state.weather)
		since = float(state.weather_since)
		raw = state.weather_prev
	# The previous mix comes as an Array of three (the rules, unpack) or a Vector3 (City's client decode).
	var prev: Array = [raw.x, raw.y, raw.z] if raw is Vector3 else (raw as Array)
	var u := clampf((t - since) / float(CityMap.WEATHER_BLEND), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	# in doubles (a Vector3 holds float32): the weights sum to 1 to 1e-15
	var tw := clampi(w, 0, 2)
	var mx := float(prev[0]) * (1.0 - e) + (e if tw == 0 else 0.0)
	var my := float(prev[1]) * (1.0 - e) + (e if tw == 1 else 0.0)
	var mz := float(prev[2]) * (1.0 - e) + (e if tw == 2 else 0.0)
	var sum := mx + my + mz
	if sum > 1e-12:
		mx /= sum
		my /= sum
		mz /= sum
	return {"sunny": mx, "rain": my, "night": mz}


## The rain weight at time t, 0..1 (rain's own smoothstep mix, so it eases in and out with the weather).
static func rain_amount(state: Variant, t: float) -> float:
	return float(weather_weights(state, t)["rain"])


## The mix now (at the rules' own time).
func weights() -> Dictionary:
	return weather_weights(self, time)


## Change the weather at the rules' time. {"ok": true}, or {"ok": false, "reason": "unknown"}. The current weather
## is a no-op success. The blend restarts from the mix as it is now, so the weights are continuous.
func set_weather(w: int) -> Dictionary:
	if w < 0 or w >= CityMap.WEATHERS.size():
		return {"ok": false, "reason": "unknown"}
	if w == weather:
		return {"ok": true, "changed": false}
	var m := weather_weights(self, time)
	weather_prev = [float(m["sunny"]), float(m["rain"]), float(m["night"])]
	weather = w
	weather_since = time
	return {"ok": true, "changed": true}


# ------------------------------------------------------------------ traffic

static func poly_length(poly: Array) -> float:
	var total := 0.0
	for i in poly.size():
		total += (poly[i] as Vector2).distance_to(poly[(i + 1) % poly.size()])
	return total


static func loop_length() -> float:
	return poly_length(CityMap.ROAD_LOOP)


## A point at arc position s along a closed polygon: {"pos": Vector2, "dir": Vector2 (unit)}.
static func poly_point(poly: Array, s: float) -> Dictionary:
	var total := poly_length(poly)
	var rest := fposmod(s, total)
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var seg := a.distance_to(b)
		if rest <= seg or i == poly.size() - 1:
			var dir := (b - a) / seg
			return {"pos": a + dir * minf(rest, seg), "dir": dir}
		rest -= seg
	return {"pos": poly[0], "dir": Vector2.RIGHT}


## Where a point lies relative to a polygon: Vector2(arc position of the nearest point, distance to it).
static func poly_project(poly: Array, p: Vector2) -> Vector2:
	var acc := 0.0
	var best := Vector2(0.0, INF)
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(p)
		if d < best.y:
			best = Vector2(acc + t * sqrt(l2), d)
		acc += sqrt(l2)
	return best


static func _wrap_signed(x: float, total: float) -> float:
	return fposmod(x + total * 0.5, total) - total * 0.5


static var _stop_arcs: Array = []


## The bus stops as arc positions along the loop, ascending: the "stop" index of a bus points into this list.
static func stop_arcs() -> Array:
	if _stop_arcs.is_empty():
		for p: Vector2 in CityMap.BUS_STOPS:
			_stop_arcs.append(poly_project(CityMap.ROAD_LOOP, p).x)
		_stop_arcs.sort()
	return _stop_arcs


## The first stop at or ahead of arc position s.
static func _next_stop(s: float) -> int:
	var arcs := stop_arcs()
	var total := loop_length()
	var best := 0
	var best_d := INF
	for i in arcs.size():
		var d := fposmod(float(arcs[i]) - s, total)
		if d < best_d:
			best_d = d
			best = i
	return best


## A vehicle's pose at arc position s: {"pos", "ry", "dir", "kind", "color"}.
static func vehicle_pose(i: int, s: float) -> Dictionary:
	var pt := poly_point(CityMap.ROAD_LOOP, s)
	var dir: Vector2 = pt["dir"]
	var cfg: Dictionary = CityMap.VEHICLES[i]
	return {"pos": pt["pos"], "dir": dir, "ry": atan2(dir.x, dir.y), "kind": String(cfg["kind"]), "color": cfg["color"]}


## The poses of all vehicles now: [{"kind", "color", "pos", "ry", "s", "v", "dwell", "stopped"}].
func vehicle_poses() -> Array:
	var out: Array = []
	for i in vehicles.size():
		var st: Dictionary = vehicles[i]
		var p := vehicle_pose(i, float(st["s"]))
		p["s"] = float(st["s"])
		p["v"] = float(st["v"])
		p["dwell"] = float(st["dwell"])
		p["stopped"] = float(st["v"]) < 0.01
		out.append(p)
	return out


func _kid_blocks(i: int, kids: Array) -> bool:
	var length: float = (CityMap.VEHICLES[i] as Dictionary)["length"]
	var total := loop_length()
	var front := float((vehicles[i] as Dictionary)["s"]) + length * 0.5
	for k: Dictionary in kids:
		if _norm(String(k.get("region", ""))) != "":
			continue
		var pr := poly_project(CityMap.ROAD_LOOP, k["pos"])
		if pr.y > LANE_HALF:
			continue
		var ahead := _wrap_signed(pr.x - front, total)
		if ahead >= -length and ahead <= STOP_AHEAD:
			return true
	return false


## Bumper-to-bumper gap to the vehicle ahead, and its speed: Vector2(gap, v).
func _leader(i: int) -> Vector2:
	var total := loop_length()
	var length: float = (CityMap.VEHICLES[i] as Dictionary)["length"]
	var front := float((vehicles[i] as Dictionary)["s"]) + length * 0.5
	var best := Vector2(INF, 0.0)
	for j in vehicles.size():
		if j == i:
			continue
		var lj: float = (CityMap.VEHICLES[j] as Dictionary)["length"]
		var rear := float((vehicles[j] as Dictionary)["s"]) - lj * 0.5
		var gap := fposmod(rear - front, total)
		if gap < best.x:
			best = Vector2(gap, float((vehicles[j] as Dictionary)["v"]))
	return best


## Centre-to-centre distance from bus i to the next bus ahead (INF with one bus).
func _bus_headway(i: int) -> float:
	var total := loop_length()
	var best := INF
	var si := float((vehicles[i] as Dictionary)["s"])
	for j in vehicles.size():
		if j != i and String((CityMap.VEHICLES[j] as Dictionary)["kind"]) == "bus":
			best = minf(best, fposmod(float((vehicles[j] as Dictionary)["s"]) - si, total))
	return best


func _bus_count() -> int:
	var n := 0
	for v: Dictionary in CityMap.VEHICLES:
		if String(v["kind"]) == "bus":
			n += 1
	return n


func _traffic_step(h: float, kids: Array) -> void:
	var total := loop_length()
	var arcs := stop_arcs()
	var next: Array = []
	for i in vehicles.size():
		var st: Dictionary = vehicles[i]
		var cfg: Dictionary = CityMap.VEHICLES[i]
		var s: float = st["s"]
		var v: float = st["v"]
		var dwell: float = st["dwell"]
		var stop: int = st["stop"]
		var is_bus := String(cfg["kind"]) == "bus" and stop >= 0 and not arcs.is_empty()
		if dwell > 0.0:
			dwell = maxf(0.0, dwell - h)
			if dwell <= 0.0:
				stop = (stop + 1) % arcs.size()
			next.append({"s": s, "v": 0.0, "dwell": dwell, "stop": stop})
			continue
		var target: float = cfg["speed"]
		if _kid_blocks(i, kids):
			target = 0.0
		var ld := _leader(i)
		if ld.x < INF:
			var free0 := ld.x - float(CityMap.VEHICLE_GAP)
			target = minf(target, sqrt(2.0 * BRAKE * maxf(free0 - v * h, 0.0)))
			# never farther in one step than the free gap (the hard guarantee)
			target = minf(target, maxf(free0, 0.0) / h)
		var d_stop := INF
		if is_bus:
			d_stop = fposmod(float(arcs[stop]) - s, total)
			if d_stop > total - 0.5:
				d_stop = 0.0
			target = minf(target, maxf(sqrt(2.0 * BRAKE * d_stop), STOP_CREEP))
		if v < target:
			v = minf(target, v + ACCEL * h)
		else:
			v = maxf(target, v - DECEL * h)
		if is_bus and v * h >= d_stop - 1e-9:
			# arrives: stands at the stop, longer when it has bunched up behind the bus ahead
			var extra := 0.0
			var even := total / float(maxi(_bus_count(), 1))
			var hw := _bus_headway(i)
			# nothing at an even headway, the full DWELL_EXTRA_MAX at BUNCH_FRACTION of it or less, between linearly
			extra = DWELL_EXTRA_MAX * clampf((even - hw) / (even * (1.0 - BUNCH_FRACTION)), 0.0, 1.0)
			next.append({"s": float(arcs[stop]), "v": 0.0, "dwell": float(CityMap.BUS_DWELL) + minf(extra, DWELL_EXTRA_MAX), "stop": stop})
		else:
			next.append({"s": fposmod(s + v * h, total), "v": v, "dwell": 0.0, "stop": stop})
	vehicles = next


## Advance the authority by dt seconds. kids: [{"id", "pos": Vector2, "region": String}] (children anywhere).
## Returns the riders who got off during this call (also kept in `exits`).
func tick(dt: float, kids: Array = []) -> Array:
	exits = []
	var remaining := dt
	while remaining > 1e-9:
		var h := minf(remaining, TICK_MAX)
		remaining -= h
		time += h
		_traffic_step(h, kids)
		_ferris_tick()
	return exits


# ------------------------------------------------------------------ walkers

## The walkers' lanes are found from the map: the block pavement clockwise, the outer pavement beyond the road
## counter-clockwise (each leg on the first offset that keeps a walker clear), and a loop out and back along the
## longest straight run of PATHS (two lanes). Every point of every lane keeps WALKER_R clear of every ground solid,
## every ground furniture item and the standing people (CityNav.people_solids()). Data-driven.
static var _walk_cache: Array = []


static func _walker_clear(p: Vector2) -> bool:
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		if sd.has("rect"):
			if (sd["rect"] as Rect2).grow(WALKER_R).has_point(p):
				return false
		elif p.distance_to(sd["at"]) < float(sd["r"]) + WALKER_R:
			return false
	for f: Dictionary in CityMap.FURNITURE:
		if String(f["region"]) in ["ground", ""] and (f["rect"] as Rect2).grow(WALKER_R).has_point(p):
			return false
	for ps: Dictionary in CityNav.people_solids():
		if String(ps.get("region", "")) in ["ground", ""] and p.distance_to(ps["at"]) < float(ps["r"]) + WALKER_R:
			return false
	return true


static func _lane_clear(a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 0.1))
	for i in n + 1:
		if not _walker_clear(a.lerp(b, float(i) / float(n))):
			return false
	return true


## One lane per leg of PED_LOOP: the chosen offsets (positive toward the middle of the block).
static func _block_offsets(pts: Array, candidates: Array, avoid: Array) -> Array:
	var n := pts.size()
	var c := Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	c /= float(n)
	var out: Array = []
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var dir := (b - a).normalized()
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(c - a) < 0.0:
			inward = -inward
		var chosen: float = candidates[0]
		for off: float in candidates:
			if not avoid.is_empty() and absf(off - float(avoid[i])) < WALK_SEPARATION:
				continue
			if _lane_clear(a + inward * off, b + inward * off):
				chosen = off
				break
		out.append(chosen)
	return out


## The loop's points for per-leg offsets (axis-aligned legs meet at one point).
static func _block_points(pts: Array, offsets: Array) -> Array:
	var n := pts.size()
	var c := Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	c /= float(n)
	var legs: Array = []
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var dir := (b - a).normalized()
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(c - a) < 0.0:
			inward = -inward
		legs.append({"a": a + inward * float(offsets[i]), "axis_x": absf(dir.x) > absf(dir.y)})
	var out: Array = []
	for i in n:
		var prev: Dictionary = legs[(i + n - 1) % n]
		var cur: Dictionary = legs[i]
		var corner: Vector2 = cur["a"]
		if bool(prev["axis_x"]) != bool(cur["axis_x"]):
			var horizontal: Dictionary = prev if bool(prev["axis_x"]) else cur
			var vertical: Dictionary = cur if bool(prev["axis_x"]) else prev
			corner = Vector2((vertical["a"] as Vector2).x, (horizontal["a"] as Vector2).y)
		out.append(corner)
	return out


## The longest straight horizontal run of PATHS (touching rectangles merge): a Rect2, or an empty one.
static func _longest_path() -> Rect2:
	var strips: Array = []
	for r: Rect2 in CityMap.PATHS:
		if r.size.x < r.size.y:
			continue
		var merged := false
		for k in strips.size():
			var q: Rect2 = strips[k]
			if absf(q.position.y - r.position.y) < 0.01 and absf(q.size.y - r.size.y) < 0.01 and r.position.x <= q.end.x + 0.01 and r.end.x >= q.position.x - 0.01:
				strips[k] = q.merge(r)
				merged = true
				break
		if not merged:
			strips.append(r)
	var best := Rect2()
	for q: Rect2 in strips:
		if q.size.x > best.size.x:
			best = q
	return best


## The walkers' loops: [{"pts": Array[Vector2], "speed", "count", "first", "length"}], built once.
static func walk_loops() -> Array:
	if not _walk_cache.is_empty():
		return _walk_cache
	var loops: Array = []
	var inward_first: Array = [0.8, 0.9, 1.0, 0.6, 0.4, 0.2, 0.0, -0.2, -0.4, -0.6, -0.8, -1.0]
	var middle_first: Array = [0.0, 0.2, -0.2, 0.4, -0.4, 0.6, -0.6, 0.8, -0.8]
	var block: Array = CityMap.PED_LOOP
	loops.append({"pts": _block_points(block, _block_offsets(block, inward_first, [])), "speed": WALK_SPEEDS[0]})
	# the outer pavement beyond the road, the other way round
	var op: Rect2 = CityMap.OUTER_PAVEMENT
	var ro: Rect2 = CityMap.ROAD_OUTER
	var ring: Array = [Vector2((op.position.x + ro.position.x) * 0.5, (op.position.y + ro.position.y) * 0.5),
		Vector2((op.end.x + ro.end.x) * 0.5, (op.position.y + ro.position.y) * 0.5),
		Vector2((op.end.x + ro.end.x) * 0.5, (op.end.y + ro.end.y) * 0.5),
		Vector2((op.position.x + ro.position.x) * 0.5, (op.end.y + ro.end.y) * 0.5)]
	var b_pts := _block_points(ring, _block_offsets(ring, middle_first, []))
	b_pts.reverse()
	loops.append({"pts": b_pts, "speed": WALK_SPEEDS[1]})
	var path := _longest_path()
	if path.size.x > 4.0:
		var zc := path.position.y + path.size.y * 0.5
		var x0 := path.position.x + 0.6
		var x1 := path.end.x - 0.6
		var found := false
		for shift: float in [0.0, 0.1, -0.1, 0.2, -0.2, 0.3, -0.3]:
			var za := zc - 0.45 + shift
			var zb := zc + 0.45 + shift
			if _lane_clear(Vector2(x0, za), Vector2(x1, za)) and _lane_clear(Vector2(x0, zb), Vector2(x1, zb)) and _lane_clear(Vector2(x1, za), Vector2(x1, zb)) and _lane_clear(Vector2(x0, za), Vector2(x0, zb)):
				loops.append({"pts": [Vector2(x0, za), Vector2(x1, za), Vector2(x1, zb), Vector2(x0, zb)], "speed": WALK_SPEEDS[2]})
				found = true
				break
		if not found:
			push_warning("CityRules: no clear lane along the paths for walkers")
	var total_n := int(CityMap.PEDESTRIANS)
	@warning_ignore("integer_division")
	var base := total_n / loops.size()   # whole walkers per loop; the remainder goes to the first loops
	var extra := total_n % loops.size()
	var first := 0
	for k in loops.size():
		var l: Dictionary = loops[k]
		l["count"] = base + (1 if k < extra else 0)
		l["first"] = first
		l["length"] = poly_length(l["pts"])
		first += int(l["count"])
	_walk_cache = loops
	return loops


## Walker `index` (0..PEDESTRIANS-1) at time t: {"pos", "ry", "phase" (walk cycle 0..1), "index"}.
static func walker_pose(index: int, t: float) -> Dictionary:
	for l: Dictionary in walk_loops():
		var k := index - int(l["first"])
		if k >= 0 and k < int(l["count"]):
			var speed: float = l["speed"]
			var total: float = l["length"]
			var s := t * speed + total * float(k) / float(l["count"]) + 3.1 * float(l["first"])
			var pt := poly_point(l["pts"], s)
			var dir: Vector2 = pt["dir"]
			return {"pos": pt["pos"], "ry": atan2(dir.x, dir.y), "phase": fposmod(s / WALK_STRIDE + 0.137 * float(index), 1.0), "index": index}
	return {"pos": Vector2.ZERO, "ry": 0.0, "phase": 0.0, "index": index}


## All walkers at time t, in index order.
static func walkers(t: float) -> Array:
	var out: Array = []
	for k in int(CityMap.PEDESTRIANS):
		out.append(walker_pose(k, t))
	return out


# ------------------------------------------------------------------ the shared state

## [VERSION (3), time, vehicles n, (s, v, dwell, stop) each, occupied n, (key index, peer) each, riders n,
##  (peer, gondola, seat, t_board, exit_at) each, weather, since, prev sunny, prev rain, prev night]. Float64: peers are up to 2^31. stop indexes stop_arcs()
## (ascending arc positions of BUS_STOPS), -1 for a car; dwell is the seconds left standing at a stop.
func pack() -> PackedFloat64Array:
	var out := PackedFloat64Array([VERSION, time, float(vehicles.size())])
	for st: Dictionary in vehicles:
		out.append(float(st["s"]))
		out.append(float(st["v"]))
		out.append(float(st["dwell"]))
		out.append(float(st["stop"]))
	var keys: Array = CityMap.INTERACTIONS.keys()
	var held_keys: Array = []
	for k: String in keys:
		if occupancy.has(k):
			held_keys.append(k)
	out.append(float(held_keys.size()))
	for k: String in held_keys:
		out.append(float(keys.find(k)))
		out.append(float(int(occupancy[k])))
	var peers: Array = riders.keys()
	peers.sort()
	out.append(float(peers.size()))
	for peer: int in peers:
		var r: Dictionary = riders[peer]
		out.append_array([float(peer), float(r["g"]), float(r["seat"]), float(r["t_board"]), float(r["exit_at"])])
	out.append_array([float(weather), weather_since, float(weather_prev[0]), float(weather_prev[1]), float(weather_prev[2])])
	return out


## {"ok", "time", "vehicles": [...], "occupancy": {key: peer}, "riders": {peer: {...}}, "weather": {"weather","since","prev"}}; ok false when malformed.
static func unpack(data: PackedFloat64Array) -> Dictionary:
	var out := {"ok": false, "time": 0.0, "vehicles": [], "occupancy": {}, "riders": {}}
	if data.size() < 3 or data[0] != VERSION:
		return out
	var i := 1
	out["time"] = data[i]
	i += 1
	var nv := int(data[i])
	i += 1
	if nv != (CityMap.VEHICLES as Array).size() or data.size() < i + nv * 4 + 1:
		return out
	for k in nv:
		(out["vehicles"] as Array).append({"s": data[i], "v": data[i + 1], "dwell": data[i + 2], "stop": int(data[i + 3])})
		i += 4
	var keys: Array = CityMap.INTERACTIONS.keys()
	var no := int(data[i])
	i += 1
	if no < 0 or data.size() < i + no * 2 + 1:
		return {"ok": false, "time": 0.0, "vehicles": [], "occupancy": {}, "riders": {}}
	for k in no:
		var idx := int(data[i])
		if idx < 0 or idx >= keys.size():
			return {"ok": false, "time": 0.0, "vehicles": [], "occupancy": {}, "riders": {}}
		(out["occupancy"] as Dictionary)[keys[idx]] = int(data[i + 1])
		i += 2
	var nr := int(data[i])
	i += 1
	if nr < 0 or data.size() != i + nr * 5 + 5:
		return {"ok": false, "time": 0.0, "vehicles": [], "occupancy": {}, "riders": {}}
	for k in nr:
		(out["riders"] as Dictionary)[int(data[i])] = {"g": int(data[i + 1]), "seat": int(data[i + 2]), "t_board": data[i + 3], "exit_at": data[i + 4]}
		i += 5
	var wi := int(data[i])
	if wi < 0 or wi >= CityMap.WEATHERS.size():
		return {"ok": false, "time": 0.0, "vehicles": [], "occupancy": {}, "riders": {}}
	out["weather"] = {"weather": wi, "since": data[i + 1], "prev": [data[i + 2], data[i + 3], data[i + 4]]}
	out["ok"] = true
	return out


## Replace this state with a packed one (a late joiner, or a test). False (and unchanged) when malformed.
func restore(data: PackedFloat64Array) -> bool:
	var u := unpack(data)
	if not u["ok"]:
		return false
	time = float(u["time"])
	vehicles = []
	for v: Dictionary in u["vehicles"]:
		vehicles.append({"s": float(v["s"]), "v": float(v["v"]), "dwell": float(v["dwell"]), "stop": int(v["stop"])})
	occupancy = (u["occupancy"] as Dictionary).duplicate()
	riders = {}
	for peer: int in u["riders"]:
		riders[peer] = (u["riders"][peer] as Dictionary).duplicate()
	exits = []
	var wst: Dictionary = u["weather"]
	weather = int(wst["weather"])
	weather_since = float(wst["since"])
	weather_prev = wst["prev"]
	return true
