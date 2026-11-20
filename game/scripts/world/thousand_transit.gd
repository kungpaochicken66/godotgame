## Thousand Town's transit (design/thousand-town.md, sections 2, 5 and 8): upstream's station loop with its three
## buses and four taxis on the timetable of core/thousand_clock.gd, and the four street-traffic loops of town.json.
##
## The station loop (city-transit-motion.js through Clock.transit_plan_units): every vehicle leaves its bay every
## 360 s, the bays 26 s apart, buses from 06:00 to 22:30 and taxis to 23:00 (taxi 0 all night), at 5 m/s round the
## loop and back to the bay, where it is serviced for 24 s. Taxis run exactly as upstream (Clock.transit).
## Lantern Lane addition: a bus stops at each of upstream's bus stops that lies beside the loop (within SERVE_M of
## it): it slows over DECEL_M, dwells DWELL seconds and pulls away, which still fits the 360 s period. Upstream's
## stops do not move with its layout, so three of the six stand beside the loop (bus-stop-1, 3 and 4; see
## served_stops()); the others are listed with no departures. The timetable is in Lantern Lane seconds of the town
## clock (Clock.seconds_at(day, minute): one sim minute per second at 1x), so it speeds up with the clock.
##
## Street traffic: town.json transit.vehicles, ten per loop, each at its own speed and offset, thinned at night by
## Clock.dispatch; heights follow the road bridges, the tunnels under the canal and the viaducts.
##
## Drawing: MultiMeshes; the bus and the taxi are world_station.glb's Station_BusTemplate and Station_TaxiTemplate
## (two surfaces each), the cars a vertex-coloured car in three shapes (car, shuttle, police): 7 draw calls in all.
##
## The lead's API (positions in metres, town space; a vehicle id is "station-bus-0".."station-taxi-3" or "car-L-K"):
##   setup(map_or_null = null)                   build the plan, the stop timetable and the meshes
##   set_time(day, minute)                        place every vehicle (call once a frame); emits arrived/departed
##   vehicles() -> Array[Dictionary]             {id, kind, pos, yaw, status, moving, stop, seats, riders, length, width}
##   vehicle(id) -> Dictionary                   one of those
##   next_departures(stop_id, count) -> Array    {vehicle, arrive_minute, depart_minute, day, in_seconds} from now
##   timetable(stop_id, day) -> Array            every bus call at a stop on a day
##   served_stops() -> PackedStringArray         the stops the buses call at ("station" is the bays)
##   can_board(vehicle_id) -> bool               a bus standing at a stop or its bay with a free seat
##   board(vehicle_id, rider) -> bool            take a seat (rider: any key, e.g. the peer id)
##   alight(rider, force = false) -> bool        leave the bus while it stands at a stop or its bay (force: anywhere)
##   next_stop(vehicle_id) -> String             the stop a bus calls at next ("station": back to its bay)
##   bay_point(vehicle_id) -> Vector3            where a station vehicle waits at its bay
##   riding(rider) -> String                     the vehicle a rider is on ("" when none)
##   seat_transform(vehicle_id, seat) -> Transform3D, door_point(vehicle_id) -> Vector3
extends Node3D

signal arrived(vehicle_id: String, stop_id: String)
signal departed(vehicle_id: String, stop_id: String)

const Clock := preload("res://scripts/core/thousand_clock.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")

## Seconds a bus stands at a stop, metres it takes to slow down (and to pull away), and how far a stop may stand
## from the loop to be served (metres).
const DWELL := 20.0
const DECEL_M := 8.0
const SERVE_M := 9.0
const BUS_SEATS := 20
## Lantern Lane change (design/thousand-town.md section 5, "Riding the bus"): upstream's three buses leave their
## bays 26 s apart once a period, so a stop waits up to about 5 real minutes at 1x. Here bus k leaves BUS_SPREAD * k
## seconds after the first (120 s: the period split three ways), so the wait is at most about 2 minutes. The
## lap, route, stops, hours and the taxis are upstream's; Clock.transit (the parity reference) is not changed.
const BUS_SPREAD := 120.0
const TAXI_SEATS := 3
## Seconds before its departure a bus at its bay takes riders.
const BAY_BOARDING := 60.0
const BUS_LENGTH := 6.3
const BUS_WIDTH := 2.05
const TAXI_LENGTH := 3.45
const TAXI_WIDTH := 1.65

enum { ST_CLOSED, ST_WAITING, ST_DEPARTING, ST_RUNNING, ST_ARRIVING, ST_DWELLING, ST_LEAVING, ST_RETURNING, ST_SERVICING }
const STATUS := ["closed", "waiting", "departing", "running", "arriving", "dwelling", "leaving", "returning", "servicing"]
## Car shapes per town.json kind: [mesh, length, width, height] (sedan, compact and van share the car mesh, scaled).
const CAR_SIZES := {"sedan": [0, 4.2, 1.75, 1.42], "compact": [0, 3.6, 1.65, 1.45], "van": [0, 4.6, 1.85, 1.95],
	"shuttle": [1, 5.6, 2.0, 2.45], "police": [2, 4.3, 1.78, 1.5]}

var plan: Dictionary = {}
var day := -1
var minute := -1.0
var update_ms := 0.0

var _stops: Array = []                 # {id, pos (Vector2), served, s (units along the bus paths), side}
var _buses: Array = []                 # per station vehicle: {id, bus, index, ordinal, path, departure, stops: [[s, stop index]], lap}
var _cars: Array = []                  # {id, kind, loop, ordinal, offset, speed, color}
var _loops: Array = []                 # {pts, cum, length}
var _state: Array = []                 # the last vehicles() list
var _by_id := {}
var _riders := {}                      # vehicle id -> Array of riders
var _rider_on := {}                    # rider -> vehicle id
var _last_status := {}
var _mm: Array[MultiMesh] = []         # bus, taxi, car, shuttle, police
var _lamp_mats: Array[StandardMaterial3D] = []
var _xfs: Array = []                   # per MultiMesh: the node-local mesh transform (templates)
var _built := false
var _lamps := -1.0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -50.0, 0.0))


# ================================================================== setup

func setup(_map: Variant = null) -> void:
	if _built:
		return
	_built = true
	var st := TMap.station()
	plan = Clock.transit_plan_units(st.pos.x / Clock.UNIT_M, st.pos.y / Clock.UNIT_M, 1)
	for s: Dictionary in TMap.stops():
		_stops.append({"id": s.id, "pos": s.pos, "served": false, "s": -1.0})
	var bus_rank := 0
	for v: Dictionary in plan.vehicles:
		var calls: Array = []
		var departure := float(v.departure)
		if v.bus:
			calls = _stop_calls(v.path)
			departure = float(plan.vehicles[0].departure) + BUS_SPREAD * bus_rank
			bus_rank += 1
		var starts := PackedFloat64Array()
		var seg: PackedFloat64Array = v.path.seg
		for i in int(v.path.count):
			starts.append(seg[i * 6 + 4])
		_buses.append({"id": v.id, "bus": v.bus, "index": v.index, "ordinal": v.ordinal, "path": v.path,
			"departure": departure, "x": v.x, "z": v.z, "calls": calls, "lap": _lap_seconds(v.path, calls),
			"starts": starts})
	for c in (_buses[0].calls as Array):
		_stops[int(c[1])]["served"] = true
	var town := TMap.data()
	for l: Dictionary in town.transit.street_loops:
		var pts := PackedVector2Array()
		for p in l.points:
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts[0].distance_to(pts[pts.size() - 1]) > 1e-3:
			pts.append(pts[0])
		var cum := PackedFloat64Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		_loops.append({"id": l.id, "pts": pts, "cum": cum, "length": cum[cum.size() - 1]})
	for c: Dictionary in town.transit.vehicles:
		var id := String(c.id)
		var size: Array = CAR_SIZES.get(String(c.kind), CAR_SIZES["sedan"])
		var car := {"id": id, "kind": String(c.kind), "loop": int(c.loop), "ordinal": int(id.get_slice("-", 2)),
			"offset": float(c.offset), "speed": float(c.speed), "color": Color(String(c.color)), "on": false, "on_minute": -1}
		car["state"] = {"id": id, "kind": car.kind, "pos": Vector3.ZERO, "yaw": 0.0, "status": "closed", "moving": false,
			"stop": "", "length": size[1], "width": size[2], "color": car.color, "seats": 0, "riders": 0}
		_cars.append(car)
	_build_meshes()


## Where the buses call: each bus stop within SERVE_M of the loop, at its nearest point (the first pass), in path
## order: [[distance along the path in units, stop index], ...].
func _stop_calls(path: Dictionary) -> Array:
	var seg: PackedFloat64Array = path.seg
	var count: int = path.count
	var length: float = path.length
	var out: Array = []
	for si in _stops.size():
		var p: Vector2 = _stops[si].pos / Clock.UNIT_M
		var best := INF
		var best_s := -1.0
		for i in count:
			var a := Vector2(seg[i * 6], seg[i * 6 + 1]) + Vector2(plan.site_x, plan.site_z)
			var b := Vector2(seg[i * 6 + 2], seg[i * 6 + 3]) + Vector2(plan.site_x, plan.site_z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best - 1e-6:
				best = d
				best_s = seg[i * 6 + 4] + seg[i * 6 + 5] * t
		var e := DECEL_M / Clock.UNIT_M
		if best * Clock.UNIT_M <= SERVE_M and best_s > e and best_s < length - e:
			out.append([best_s, si])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out


func _lap_seconds(path: Dictionary, calls: Array) -> float:
	var v := Clock.TRANSIT_SPEED_UNITS
	var e := DECEL_M / Clock.UNIT_M
	return float(path.length) / v + calls.size() * (2.0 * e / v + DWELL)


# ================================================================== motion

## Distance along the path (units) `phase` seconds after leaving the bay, with the stops: [distance, status, stop
## index or -1]. Past the end of the lap it returns the length.
func _profile(phase: float, calls: Array, length: float) -> Array:
	var v := Clock.TRANSIT_SPEED_UNITS
	var e := DECEL_M / Clock.UNIT_M
	var brake := 2.0 * e / v
	var k := v * v / (4.0 * e)
	var t := phase
	var cursor := 0.0
	for c: Array in calls:
		var sj: float = c[0]
		var cruise := (sj - e - cursor) / v
		if t < cruise:
			return [cursor + v * t, ST_RUNNING, -1]
		t -= cruise
		if t < brake:
			return [sj - e + v * t - k * t * t, ST_ARRIVING, int(c[1])]
		t -= brake
		if t < DWELL:
			return [sj, ST_DWELLING, int(c[1])]
		t -= DWELL
		if t < brake:
			return [sj + k * t * t, ST_LEAVING, int(c[1])]
		t -= brake
		cursor = sj + e
	return [minf(length, cursor + v * t), ST_RUNNING, -1]


## The bay departure (Lantern Lane seconds since day 1) of the run a station vehicle is on at time `time`, or
## -INF (Clock.transit_at_units' admission, with the lap lengthened by the stops).
func _departure(b: Dictionary, time: float) -> float:
	var spm := Clock.SECONDS_PER_SIM_MINUTE
	var day_length := Clock.MINUTES_PER_DAY * spm
	if b.bus:
		var d0 := floori(time / day_length)
		var departure := -INF
		for d in [d0 - 1, d0]:
			var start: float = d * day_length + Clock.TRANSIT_BUS_FROM * spm + b.departure
			while start < d * day_length + Clock.TRANSIT_BUS_TO * spm:
				if start <= time:
					departure = maxf(departure, start)
				start += Clock.TRANSIT_PERIOD
		if departure == -INF or not Clock.dispatch("bus", b.ordinal, departure / spm):
			return -INF
		return departure
	var phase := Clock.js_mod(time - b.departure, Clock.TRANSIT_PERIOD)
	if not Clock.dispatch("taxi", b.ordinal, (time - phase) / spm):
		return -INF
	return time - phase


## One station vehicle at `time` (Lantern Lane seconds since day 1): {id, kind, pos, yaw, status, moving, stop}.
func _station_vehicle(b: Dictionary, time: float) -> Dictionary:
	var spm := Clock.SECONDS_PER_SIM_MINUTE
	var path: Dictionary = b.path
	var length: float = path.length
	var kind := "bus" if b.bus else "taxi"
	var operating := Clock.dispatch(kind, b.ordinal, time / spm)
	var dep := _departure(b, time)
	var phase := time - dep
	var lap: float = b.lap
	var x: float = b.x
	var z: float = b.z
	var heading := -PI / 2.0
	var status := ST_WAITING if operating else ST_CLOSED
	var moving := false
	var stop := ""
	if dep != -INF and phase < lap:
		var pr := _profile(phase, b.calls, length)
		var distance: float = pr[0]
		status = pr[1]
		if int(pr[2]) >= 0:
			stop = _stops[int(pr[2])].id
		moving = status != ST_DWELLING
		var seg: PackedFloat64Array = path.seg
		var count: int = path.count
		# the first segment whose end lies beyond the distance (Clock.transit_at_units' scan, by bisection)
		var starts: PackedFloat64Array = b.starts
		var i0 := clampi(starts.bsearch(distance, false) - 1, 0, count - 1)
		while i0 > 0 and distance < seg[(i0 - 1) * 6 + 4] + seg[(i0 - 1) * 6 + 5]:
			i0 -= 1
		while i0 < count - 1 and not (distance < seg[i0 * 6 + 4] + seg[i0 * 6 + 5]):
			i0 += 1
		var at := i0 * 6
		var t := minf(1.0, (distance - seg[at + 4]) / seg[at + 5])
		x = seg[at] + (seg[at + 2] - seg[at]) * t
		z = seg[at + 1] + (seg[at + 3] - seg[at + 1]) * t
		heading = atan2(seg[at + 3] - seg[at + 1], seg[at + 2] - seg[at])
		if b.bus and distance < 11.0:
			heading -= PI
		if not b.bus and distance > length - 14.0:
			heading -= PI
		if x < 29.0 and status == ST_RUNNING:
			status = ST_DEPARTING if distance < length / 2.0 else ST_RETURNING
	elif operating and dep != -INF and phase < lap + Clock.TRANSIT_SERVICE_SECONDS:
		status = ST_SERVICING
	var wx: float = plan.site_x + plan.side * x
	var wz: float = plan.site_z + plan.side * z
	var rise := 0.0
	for bz: float in [-80.0, 80.0]:
		rise = maxf(rise, Clock.smooth01((33.0 - absf(wx)) / 10.0) * Clock.smooth01((11.5 - absf(wz - bz)) / 4.0))
	if stop == "" and (status == ST_WAITING or status == ST_SERVICING) and b.bus:
		stop = "station"
	if not b.has("state"):
		b["state"] = {"id": b.id, "kind": kind, "length": BUS_LENGTH if b.bus else TAXI_LENGTH,
			"width": BUS_WIDTH if b.bus else TAXI_WIDTH}
	var v: Dictionary = b.state
	v["pos"] = Clock.to_metres(wx, 1.7 * rise, wz)
	v["yaw"] = Clock.yaw_from_heading(heading)
	v["status"] = STATUS[status]
	v["moving"] = moving
	v["stop"] = stop
	v["departure"] = dep
	return v


## The road's height (metres) at a point: the road bridges, the tunnels under the canal and the viaducts
## (solids.json's profiles: upstream units inside the formulas, town.json's numbers in metres).
static func road_y(p: Vector2) -> float:
	if _profiles.is_empty():
		_build_profiles()
	var X := p.x * 2.0
	var Z := p.y * 2.0
	for b: PackedFloat64Array in _profiles[0]:
		var wx := (b[2] + 10.0 - absf(X - b[0])) / 10.0
		var wz := (b[3] + 4.0 - absf(Z - b[1])) / 4.0
		if wx > 0.0 and wz > 0.0:
			return 0.5 * (0.25 + 1.7 * Clock.smooth01(wx) * Clock.smooth01(wz))
	for t: PackedFloat64Array in _profiles[1]:
		if absf(p.y - t[0]) <= t[1] + 0.5:
			var k := clampf((t[2] - absf(X)) / (t[2] - t[3]), 0.0, 1.0)
			if k > 0.0:
				return 0.5 * (0.25 - t[4] * Clock.smooth01(k))
	for v: PackedFloat64Array in _profiles[2]:
		var wz := (v[1] + 2.7 - absf(Z - v[0])) / 1.2
		var wx := (v[2] + v[3] - absf(X)) / v[3]
		if wx > 0.0 and wz > 0.0:
			return 0.5 * (0.25 + (v[4] - 0.25) * Clock.smooth01(wx) * Clock.smooth01(wz))
	return 0.125


static var _profiles: Array = []


## The profiles in upstream units: road bridges [x, z, w, d], tunnels [z (m), half_d (m), portal, cover, drop],
## viaducts [z, d, flat, ramp, height].
static func _build_profiles() -> void:
	var town := TMap.data()
	var bridges: Array[PackedFloat64Array] = []
	for b: Dictionary in town.bridges:
		if String(b.kind) == "road_bridge":
			bridges.append(PackedFloat64Array([float(b.x) * 2.0, float(b.z) * 2.0, float(b.w), float(b.d)]))
	var tunnels: Array[PackedFloat64Array] = []
	for t: Dictionary in town.tunnels:
		tunnels.append(PackedFloat64Array([float(t.z), float(t.half_d), float(t.portal_x) * 2.0, float(t.cover_x) * 2.0, float(t.drop) * 2.0]))
	var viaducts: Array[PackedFloat64Array] = []
	for v: Dictionary in town.viaducts:
		viaducts.append(PackedFloat64Array([float(v.z) * 2.0, float(v.d), float(v.flat_x) * 2.0, float(v.ramp_x) * 2.0, float(v.height) * 2.0]))
	_profiles = [bridges, tunnels, viaducts]


func _car(c: Dictionary, time: float, on: bool) -> Dictionary:
	var lp: Dictionary = _loops[c.loop]
	var length: float = lp.length
	var s := fposmod(float(c.offset) + float(c.speed) * time, length)
	var pts: PackedVector2Array = lp.pts
	var cum: PackedFloat64Array = lp.cum
	var j := clampi(cum.bsearch(s, true) - 1, 0, pts.size() - 2)
	var a := pts[j]
	var b := pts[j + 1]
	var p := a.lerp(b, (s - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-9))
	var d := b - a
	var v: Dictionary = c.state
	v["pos"] = Vector3(p.x, road_y(p), p.y)
	v["yaw"] = atan2(d.x, d.y)
	v["status"] = "running" if on else "closed"
	v["moving"] = on
	return v


## Places every vehicle at a moment of the town clock (call once a frame).
func set_time(p_day: int, p_minute: float) -> void:
	if not _built:
		return
	var t0 := Time.get_ticks_usec()
	if p_day == day and p_minute == minute:
		# the same moment again (a held Day / Dusk / Night): every vehicle, status and lamp is already where this
		# moment puts it; boarding and alighting update their vehicle's entry themselves
		update_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	day = p_day
	minute = p_minute
	var time := Clock.seconds_at(p_day, p_minute)
	var m := Clock.js_mod(p_minute, Clock.MINUTES_PER_DAY)
	_state.clear()
	_by_id.clear()
	for b: Dictionary in _buses:
		_add(_station_vehicle(b, time))
	var minute_key := floori(m)
	for c: Dictionary in _cars:
		if int(c.on_minute) != minute_key:
			c["on"] = Clock.dispatch(String(c.kind), int(c.ordinal), m)
			c["on_minute"] = minute_key
		_add(_car(c, time, bool(c.on)))
	for n in _buses.size():
		var v: Dictionary = _state[n]
		var key := String(v.status) + "|" + String(v.stop)
		var was := String(_last_status.get(v.id, ""))
		if was != key:
			var was_stopped := was.begins_with("dwelling|") or was.begins_with("waiting|station")
			var now_stopped := String(v.status) == "dwelling" or (String(v.status) == "waiting" and String(v.stop) == "station")
			if now_stopped and not was_stopped and was != "":
				arrived.emit(v.id, v.stop)
			if was_stopped and not now_stopped:
				departed.emit(v.id, was.get_slice("|", 1))
			_last_status[v.id] = key
	_draw()
	var lamps := 0.2 + 2.2 * Clock.lamp_level(m)
	if absf(lamps - _lamps) > 0.01:
		_lamps = lamps
		for mat in _lamp_mats:
			mat.emission_energy_multiplier = lamps
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _add(v: Dictionary) -> void:
	if v.kind == "bus" or v.kind == "taxi":
		v["seats"] = BUS_SEATS if v.kind == "bus" else TAXI_SEATS
		v["riders"] = (_riders.get(v.id, []) as Array).size()
	_state.append(v)
	_by_id[v.id] = v


# ================================================================== queries and boarding

func vehicles() -> Array:
	return _state


func vehicle(id: String) -> Dictionary:
	return _by_id.get(id, {})


func served_stops() -> PackedStringArray:
	var out := PackedStringArray(["station"])
	for s: Dictionary in _stops:
		if s.served:
			out.append(s.id)
	return out


## Every bus call at a stop on a day: {vehicle, arrive_minute, depart_minute, day} in time order. At "station" the
## arrival is the departure from the bay.
func timetable(stop_id: String, p_day: int) -> Array:
	var out: Array = []
	var spm := Clock.SECONDS_PER_SIM_MINUTE
	var day0 := Clock.seconds_at(p_day, 0.0)
	for b: Dictionary in _buses:
		if not b.bus:
			continue
		var offset := -1.0
		if stop_id == "station":
			offset = 0.0
		else:
			offset = _arrival_offset(b, stop_id)
			if offset < 0.0:
				continue
		var start: float = day0 + Clock.TRANSIT_BUS_FROM * spm + b.departure
		while start < day0 + Clock.TRANSIT_BUS_TO * spm:
			if Clock.dispatch("bus", b.ordinal, (start - Clock.seconds_at(1, 0.0)) / spm):
				var arrive := start + offset
				var depart := arrive + (0.0 if stop_id == "station" else DWELL)
				out.append({"vehicle": b.id, "day": p_day, "arrive_minute": (arrive - day0) / spm,
					"depart_minute": (depart - day0) / spm, "departure_seconds": depart})
			start += Clock.TRANSIT_PERIOD
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.departure_seconds < y.departure_seconds)
	return out


## Seconds after leaving the bay that a bus comes to rest at a stop, or -1 when it does not call there.
func _arrival_offset(b: Dictionary, stop_id: String) -> float:
	var v := Clock.TRANSIT_SPEED_UNITS
	var e := DECEL_M / Clock.UNIT_M
	var t := 0.0
	var cursor := 0.0
	for c: Array in b.calls:
		var sj: float = c[0]
		t += (sj - e - cursor) / v + 2.0 * e / v
		if _stops[int(c[1])].id == stop_id:
			return t
		t += DWELL + 2.0 * e / v
		cursor = sj + e
	return -1.0


## The next `count` bus departures from a stop after the current time (today's, then tomorrow's).
func next_departures(stop_id: String, count: int = 3) -> Array:
	var now := Clock.seconds_at(day, minute)
	var out: Array = []
	for d in [day, day + 1]:
		for e: Dictionary in timetable(stop_id, d):
			if float(e.departure_seconds) >= now:
				var row := e.duplicate()
				row["in_seconds"] = float(e.departure_seconds) - now
				out.append(row)
				if out.size() >= count:
					return out
	return out


func _standing(v: Dictionary) -> bool:
	return String(v.status) == "dwelling" or (String(v.status) == "waiting" and String(v.stop) == "station")


## A bus that stands at a stop (or at its bay, within BAY_BOARDING seconds of leaving) and has a free seat.
func can_board(vehicle_id: String) -> bool:
	var v: Dictionary = _by_id.get(vehicle_id, {})
	if v.is_empty() or String(v.kind) != "bus" or not _standing(v):
		return false
	if String(v.status) == "waiting":
		var nxt := next_departures("station", 3)
		var soon := false
		for e: Dictionary in nxt:
			if e.vehicle == vehicle_id and float(e.in_seconds) <= BAY_BOARDING:
				soon = true
		if not soon:
			return false
	return (_riders.get(vehicle_id, []) as Array).size() < BUS_SEATS


func board(vehicle_id: String, rider: Variant) -> bool:
	if _rider_on.has(rider) or not can_board(vehicle_id):
		return false
	if not _riders.has(vehicle_id):
		_riders[vehicle_id] = []
	(_riders[vehicle_id] as Array).append(rider)
	_rider_on[rider] = vehicle_id
	_by_id[vehicle_id]["riders"] = (_riders[vehicle_id] as Array).size()
	return true


## Leaves the bus while it stands at a stop or its bay. `force` (the lead's integration: the tram home, leaving the
## town) frees the seat wherever the bus is.
func alight(rider: Variant, force := false) -> bool:
	if not _rider_on.has(rider):
		return false
	var vid := String(_rider_on[rider])
	var v: Dictionary = _by_id.get(vid, {})
	if not force and (v.is_empty() or not (_standing(v) or String(v.status) == "servicing" or String(v.status) == "closed")):
		return false
	if not _riders.has(vid):
		_rider_on.erase(rider)
		return true
	(_riders[vid] as Array).erase(rider)
	_rider_on.erase(rider)
	if not v.is_empty():
		v["riders"] = (_riders[vid] as Array).size()
	return true


## The stop a bus calls at next ("station" when only the way back to its bay is left; "" for an unknown vehicle,
## a taxi, or a bus that is not on a run). While it stands at a stop, that stop.
func next_stop(vehicle_id: String) -> String:
	for b: Dictionary in _buses:
		if String(b.id) != vehicle_id or not b.bus:
			continue
		var v: Dictionary = _by_id.get(vehicle_id, {})
		var dep := float(v.get("departure", -INF))
		if v.is_empty() or dep == -INF:
			return ""
		var phase := Clock.seconds_at(day, minute) - dep
		if phase < 0.0 or phase >= float(b.lap):
			return ""
		var pr := _profile(phase, b.calls, float(b.path.length))
		if int(pr[2]) >= 0 and int(pr[1]) in [ST_ARRIVING, ST_DWELLING]:
			return String(_stops[int(pr[2])].id)
		for c: Array in b.calls:
			if float(c[0]) > float(pr[0]) + 1e-6:
				return String(_stops[int(c[1])].id)
		return "station"
	return ""


## Where a station vehicle waits at its bay (on the road, metres).
func bay_point(vehicle_id: String) -> Vector3:
	for b: Dictionary in _buses:
		if String(b.id) == vehicle_id:
			return Clock.to_metres(plan.site_x + plan.side * float(b.x), 0.0, plan.site_z + plan.side * float(b.z))
	return Vector3.INF


func riding(rider: Variant) -> String:
	return String(_rider_on.get(rider, ""))


func riders(vehicle_id: String) -> Array:
	return _riders.get(vehicle_id, [])


## The vehicle's frame: origin on the road under its centre, -z its front (the templates' convention).
func vehicle_transform(vehicle_id: String) -> Transform3D:
	var v: Dictionary = _by_id.get(vehicle_id, {})
	if v.is_empty():
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3.UP, float(v.yaw) + PI), v.pos)


## Seat k of a bus: two by ten facing forward, the hips 0.62 m above the road.
func seat_transform(vehicle_id: String, seat: int) -> Transform3D:
	@warning_ignore("integer_division")
	var row := clampi(seat, 0, BUS_SEATS - 1) / 2
	var col := clampi(seat, 0, BUS_SEATS - 1) % 2
	var local := Transform3D(Basis(Vector3.UP, PI), Vector3(-0.45 if col == 0 else 0.45, 0.62, -1.9 + row * 0.42))
	return vehicle_transform(vehicle_id) * local


## The bus door on the side facing the stop it stands at (its right-hand side otherwise), on the road.
func door_point(vehicle_id: String) -> Vector3:
	var v: Dictionary = _by_id.get(vehicle_id, {})
	if v.is_empty():
		return Vector3.INF
	var xf := vehicle_transform(vehicle_id)
	var side := 1.0
	for s: Dictionary in _stops:
		if s.id == v.stop:
			var to: Vector2 = s.pos - Vector2(xf.origin.x, xf.origin.z)
			var right := xf.basis.x
			side = 1.0 if to.dot(Vector2(right.x, right.z)) >= 0.0 else -1.0
	return xf * Vector3(side * (BUS_WIDTH * 0.5 + 0.4), 0.0, -BUS_LENGTH * 0.3)


func stops() -> Array:
	return _stops


# ================================================================== drawing

func draw_calls() -> int:
	var n := 0
	for mm in _mm:
		if mm.visible_instance_count != 0 and mm.mesh != null:
			n += mm.mesh.get_surface_count()
	return n


func _build_meshes() -> void:
	var templates := _templates()
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = false
	paint.roughness = 0.66
	paint.metallic = 0.06
	var lamp := paint.duplicate() as StandardMaterial3D
	lamp.roughness = 0.5
	lamp.metallic = 0.0
	lamp.emission_enabled = true
	lamp.emission = Color("#ffd6a0")
	_lamp_mats.append(lamp)
	var counts := [3, 4, 0, 0, 0]
	for c: Dictionary in _cars:
		var size: Array = CAR_SIZES.get(c.kind, CAR_SIZES["sedan"])
		var mk := 2 + int(size[0])
		c["mesh"] = mk
		c["slot"] = counts[mk]
		c["shape"] = Basis.from_scale(Vector3(float(size[2]) / 1.75, float(size[3]) / 1.42, float(size[1]) / 4.2)) if int(size[0]) == 0 else Basis.IDENTITY
		counts[mk] += 1
	var meshes: Array = [templates[0][0], templates[1][0], _car_mesh(0), _car_mesh(1), _car_mesh(2)]
	_xfs = [templates[0][1], templates[1][1], Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
	var names := ["transit_buses", "transit_taxis", "traffic_cars", "traffic_shuttles", "traffic_police"]
	for k in 5:
		var mesh: Mesh = meshes[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = k >= 2
		mm.mesh = mesh
		mm.instance_count = maxi(1, counts[k])
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-100.0, -5.0, -135.0), Vector3(200.0, 15.0, 270.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = names[k]
		mi.multimesh = mm
		if k >= 2:
			mi.material_override = PropsCity.material()
		elif mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				var mname := ""
				var sm := mesh.surface_get_material(s)
				if sm != null:
					mname = sm.resource_name
				(mesh as ArrayMesh).surface_set_material(s, lamp if mname == "tt_lamp" else paint)
		add_child(mi)
		_mm.append(mm)
		if k >= 2:
			mm.visible_instance_count = -1
	for c: Dictionary in _cars:
		_mm[int(c.mesh)].set_instance_transform(int(c.slot), _hidden)
		_mm[int(c.mesh)].set_instance_color(int(c.slot), c.color)


## [[bus mesh, node transform], [taxi mesh, node transform]] from world_station.glb (simple boxes if missing).
func _templates() -> Array:
	var out: Array = [[null, Transform3D.IDENTITY], [null, Transform3D.IDENTITY]]
	var path := TMap.DATA_DIR + "world_station.glb"
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			var scene := doc.generate_scene(state)
			if scene != null:
				for k in 2:
					var n := scene.find_child(["Station_BusTemplate", "Station_TaxiTemplate"][k], true, false)
					if n != null:
						var mi := n as MeshInstance3D
						if mi == null:
							for ch in n.find_children("*", "MeshInstance3D", true, false):
								mi = ch as MeshInstance3D
								break
						if mi != null and mi.mesh != null:
							var xf := Transform3D.IDENTITY
							var cur: Node = mi
							while cur != null and cur != scene:
								if cur is Node3D:
									xf = (cur as Node3D).transform * xf
								cur = cur.get_parent()
							out[k] = [mi.mesh.duplicate(), xf]
				scene.free()
	for k in 2:
		if out[k][0] == null:
			out[k] = [_fallback_vehicle(k == 0), Transform3D.IDENTITY]
	return out


func _fallback_vehicle(bus: bool) -> ArrayMesh:
	var a := PropsCity.acc()
	var l := BUS_LENGTH if bus else TAXI_LENGTH
	var w := BUS_WIDTH if bus else TAXI_WIDTH
	var h := 2.0 if bus else 1.45
	var body := Color("#3f8f7a") if bus else Color("#f2c230")
	a.box(Vector3(0, 0.35 + (h - 0.35) * 0.5, 0), Vector3(w, h - 0.35, l), body, 0.08)
	a.box(Vector3(0, h * 0.7, 0), Vector3(w + 0.02, h * 0.25, l * 0.8), Color(0.2, 0.26, 0.3))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * w * 0.42, 0.35, sz * l * 0.32), Vector3(0.24, 0.6, 0.6), Color(0.12, 0.12, 0.12))
	return a.build_mesh()


## A car facing +z, wheels on y = 0, its body white (the instance colour), glass and tyres dark. 0 car (scaled per
## kind), 1 shuttle, 2 police (white with a light bar).
static func _car_mesh(shape: int) -> ArrayMesh:
	var a := PropsCity.acc()
	var body := Color.WHITE
	var glass := Color(0.18, 0.22, 0.26)
	var tyre := Color(0.1, 0.1, 0.1)
	var size: Array = [[1.0, 1.0, 1.0], [5.6, 2.0, 2.45], [4.3, 1.78, 1.5]][shape]
	var l := 4.2 if shape == 0 else float(size[0])
	var w := 1.75 if shape == 0 else float(size[1])
	var h := 1.42 if shape == 0 else float(size[2])
	if shape == 1:
		a.box(Vector3(0, 0.3 + (h - 0.3) * 0.5, 0), Vector3(w, h - 0.3, l), body, 0.12)
		a.box(Vector3(0, h * 0.68, 0.05), Vector3(w + 0.02, h * 0.3, l * 0.86), glass)
	else:
		a.box(Vector3(0, 0.3 + 0.32, 0), Vector3(w, 0.64, l), body, 0.12)
		a.box(Vector3(0, 0.94 + (h - 0.94) * 0.5, -0.15), Vector3(w * 0.86, h - 0.94, l * 0.52), body, 0.08)
		a.box(Vector3(0, 0.94 + (h - 0.94) * 0.45, -0.15), Vector3(w * 0.88, (h - 0.94) * 0.62, l * 0.5), glass)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.box(Vector3(sx * w * 0.42, 0.3, sz * l * 0.32), Vector3(0.22, 0.6, 0.6), tyre)
	a.box(Vector3(0, 0.55, l * 0.5), Vector3(w * 0.7, 0.12, 0.04), Color(1.0, 0.95, 0.8))
	a.box(Vector3(0, 0.6, -l * 0.5), Vector3(w * 0.7, 0.1, 0.04), Color(0.8, 0.15, 0.12))
	if shape == 2:
		a.box(Vector3(0, 0.62, 0), Vector3(w + 0.01, 0.16, l * 0.6), Color(0.15, 0.3, 0.75))
		a.box(Vector3(-0.25, h + 0.06, -0.15), Vector3(0.45, 0.12, 0.22), Color(0.2, 0.35, 1.0))
		a.box(Vector3(0.25, h + 0.06, -0.15), Vector3(0.45, 0.12, 0.22), Color(1.0, 0.2, 0.2))
	return a.build_mesh()


func _draw() -> void:
	var n := [0, 0]
	for k in _buses.size():
		var v: Dictionary = _state[k]
		var m := 0 if v.kind == "bus" else 1
		_mm[m].set_instance_transform(n[m], Transform3D(Basis(Vector3.UP, float(v.yaw) + PI), v.pos) * _xfs[m])
		n[m] += 1
	_mm[0].visible_instance_count = n[0]
	_mm[1].visible_instance_count = n[1]
	# cars keep their own instance (and colour); one out of service is folded away
	for c: Dictionary in _cars:
		var v: Dictionary = c.state
		var xf := _hidden
		if bool(v.moving):
			xf = Transform3D(Basis(Vector3.UP, float(v.yaw)) * (c.shape as Basis), v.pos)
		_mm[int(c.mesh)].set_instance_transform(int(c.slot), xf)
