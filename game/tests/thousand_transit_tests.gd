## Headless tests for Thousand Town's transit (world/thousand_transit.gd; design/thousand-town.md sections 2, 5
## and 8). Nothing renders.
##   scripts/godot.sh --headless --path game -s res://tests/thousand_transit_tests.gd
## The station loop: the taxis exactly where Clock.transit (upstream's motion, parity-tested in
## thousand_sim_tests.gd) has them; the buses too until they first slow for a stop; every moving vehicle on its
## path; the stops beside the loop served, each with a dwell of DWELL seconds at rest beside the stop; the lap still
## inside the 360 s period; the timetable's departures from the bays and the stops, and next_departures(); boarding
## and getting off only while standing, with the seat count; the arrived/departed signals; the street traffic on
## its loops, thinned at night, and through the canal tunnels; determinism; draw calls and the per-frame cost.
extends SceneTree

const Clock := preload("res://scripts/core/thousand_clock.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const Transit := preload("res://scripts/world/thousand_transit.gd")

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var tt: Transit
var _events: Array = []


func _initialize() -> void:
	tt = Transit.new()
	root.add_child(tt)
	tt.setup()
	tt.arrived.connect(func(v: String, s: String) -> void: _events.append(["arrived", v, s]))
	tt.departed.connect(func(v: String, s: String) -> void: _events.append(["departed", v, s]))
	for t: String in ["test_stops", "test_taxi_parity", "test_bus_parity", "test_on_path", "test_dwell", "test_lap",
			"test_timetable", "test_next_departures", "test_boarding", "test_signals", "test_traffic", "test_determinism",
			"test_budgets"]:
		_current = t
		call(t)
	for line: String in _report:
		print(line)
	print("\nTHOUSAND TRANSIT TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		if _failures < 60:
			print("FAIL [%s] %s" % [_current, what])


func _bus(id: String) -> Dictionary:
	for b: Dictionary in tt._buses:
		if b.id == id:
			return b
	return {}


func test_stops() -> void:
	var served := tt.served_stops()
	ok(served.has("station"), "the bays are a stop")
	for id: String in ["bus-stop-1", "bus-stop-3", "bus-stop-4"]:
		ok(served.has(id), "%s stands beside the loop and is served" % id)
	for id: String in ["bus-stop-0", "bus-stop-2", "bus-stop-5"]:
		ok(not served.has(id), "%s is away from the loop (upstream's stops do not follow its layout)" % id)
	ok(tt.next_departures("bus-stop-0", 3).is_empty(), "an unserved stop has no departures")
	var calls: Array = _bus("station-bus-0").calls
	ok(calls.size() == 3, "a bus calls at three stops (%d)" % calls.size())
	ok(_bus("station-taxi-0").calls.is_empty(), "taxis do not call at bus stops")
	_report.append("stops served: %s" % ", ".join(served))


## Station vehicles against Clock.transit at Lantern Lane seconds `time` (position in metres).
func _clock_fleet(time: float) -> Dictionary:
	var out := {}
	for v: Dictionary in Clock.transit(tt.plan, time):
		out[v.id] = v
	return out


func test_taxi_parity() -> void:
	var worst := 0.0
	var n := 0
	for day in [1, 2, 6, 7]:
		for k in 300:
			var minute := 300.0 + k * 3.7
			tt.set_time(day, minute)
			var ref := _clock_fleet(Clock.seconds_at(day, minute))
			for v: Dictionary in tt.vehicles():
				if v.kind != "taxi":
					continue
				var r: Dictionary = ref[v.id]
				worst = maxf(worst, (v.pos as Vector3).distance_to(r.pos))
				ok(absf(angle_difference(float(v.yaw), float(r.yaw))) < 1e-6, "%s heading matches the clock at day %d %.1f" % [v.id, day, minute])
				ok(bool(v.moving) == bool(r.moving), "%s moving matches the clock at day %d %.1f" % [v.id, day, minute])
				n += 1
	ok(worst < 1e-6, "the taxis are exactly where Clock.transit has them (worst %.9f m over %d samples)" % [worst, n])


func test_bus_parity() -> void:
	# before a bus first slows for a stop it is where upstream has it
	var worst := 0.0
	var n := 0
	for b: Dictionary in tt._buses:
		if not b.bus:
			continue
		var first_brake: float = (float(b.calls[0][0]) - Transit.DECEL_M / Clock.UNIT_M) / Clock.TRANSIT_SPEED_UNITS
		for run in 4:
			var dep: float = Clock.seconds_at(1, Clock.TRANSIT_BUS_FROM) + b.departure + run * Clock.TRANSIT_PERIOD
			for k in 20:
				var time := dep + first_brake * k / 20.0
				var day := 1
				var minute := (time - Clock.seconds_at(1, 0.0)) / Clock.SECONDS_PER_SIM_MINUTE
				tt.set_time(day, minute)
				# upstream's bus at the same point of its run (BUS_SPREAD moves the departures, not the motion)
				var shift: float = b.departure - _upstream_departure(b.id)
				var ref: Dictionary = _clock_fleet(time - shift)[b.id]
				worst = maxf(worst, (tt.vehicle(b.id).pos as Vector3).distance_to(ref.pos))
				n += 1
	ok(worst < 1e-6, "the buses follow upstream's motion up to their first stop (worst %.9f m over %d samples)" % [worst, n])


func _upstream_departure(id: String) -> float:
	for v: Dictionary in tt.plan.vehicles:
		if v.id == id:
			return float(v.departure)
	return 0.0


## Distance (metres) from a point to a station vehicle's path.
func _off_path(b: Dictionary, p: Vector3) -> float:
	var seg: PackedFloat64Array = b.path.seg
	var q := Vector2(p.x, p.z) / Clock.UNIT_M - Vector2(tt.plan.site_x, tt.plan.site_z)
	var best := INF
	for i in int(b.path.count):
		var a := Vector2(seg[i * 6], seg[i * 6 + 1])
		var c := Vector2(seg[i * 6 + 2], seg[i * 6 + 3])
		var ac := c - a
		var t := clampf((q - a).dot(ac) / maxf(ac.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ac * t))
	return best * Clock.UNIT_M


func test_on_path() -> void:
	var worst := 0.0
	var moving := 0
	for k in 600:
		var minute := 360.0 + k * 1.33
		tt.set_time(3, minute)
		for b: Dictionary in tt._buses:
			var v := tt.vehicle(b.id)
			if v.moving or v.status == "dwelling":
				moving += 1
				worst = maxf(worst, _off_path(b, v.pos))
	ok(moving > 500, "plenty of samples of moving vehicles (%d)" % moving)
	ok(worst < 1e-4, "every station vehicle on the road is on its loop (worst %.9f m)" % worst)
	# the loop crosses the canal on the road bridges, rising with them
	var top := 0.0
	for k in 3000:
		tt.set_time(1, 725.0 + k * 0.1)
		for v: Dictionary in tt.vehicles():
			if v.kind == "bus" and absf((v.pos as Vector3).x) < 2.0:
				top = maxf(top, (v.pos as Vector3).y)
	ok(top > 0.8, "a bus on a road bridge rides over the canal (%.2f m up)" % top)


func test_dwell() -> void:
	var b := _bus("station-bus-0")
	var dep: float = Clock.seconds_at(1, Clock.TRANSIT_BUS_FROM) + b.departure
	for c: Array in b.calls:
		var stop: Dictionary = tt.stops()[int(c[1])]
		var arrive := dep + tt._arrival_offset(b, stop.id)
		var rest: Vector3 = Vector3.INF
		for k in 21:
			var time := arrive + 0.05 + (Transit.DWELL - 0.1) * k / 20.0
			tt.set_time(1, time / Clock.SECONDS_PER_SIM_MINUTE)
			var v := tt.vehicle(b.id)
			ok(v.status == "dwelling" and v.stop == stop.id, "bus 0 dwells at %s (%s %s)" % [stop.id, v.status, v.stop])
			ok(not v.moving, "bus 0 stands still at %s" % stop.id)
			if rest == Vector3.INF:
				rest = v.pos
			ok((v.pos as Vector3).distance_to(rest) < 1e-6, "bus 0 does not creep at %s" % stop.id)
		var sp: Vector2 = stop.pos
		var d := Vector2(rest.x, rest.z).distance_to(sp)
		ok(d <= Transit.SERVE_M + 0.01, "the bus stands beside %s (%.2f m)" % [stop.id, d])
		tt.set_time(1, (arrive - 1.0) / Clock.SECONDS_PER_SIM_MINUTE)
		ok(tt.vehicle(b.id).status == "arriving", "bus 0 slows into %s" % stop.id)
		tt.set_time(1, (arrive + Transit.DWELL + 1.0) / Clock.SECONDS_PER_SIM_MINUTE)
		ok(tt.vehicle(b.id).status == "leaving", "bus 0 pulls away from %s" % stop.id)
		_report.append("bus 0 at %s: arrives %s, %.1f m from the stop" % [stop.id, Clock.format_minute(arrive / Clock.SECONDS_PER_SIM_MINUTE), d])


func test_lap() -> void:
	for b: Dictionary in tt._buses:
		ok(float(b.lap) + Clock.TRANSIT_SERVICE_SECONDS < Clock.TRANSIT_PERIOD, "%s: the lap (%.0f s) and servicing fit the 360 s period" % [b.id, b.lap])
	# after the lap the bus is serviced at its bay, then waits
	var b := _bus("station-bus-1")
	var dep: float = Clock.seconds_at(1, Clock.TRANSIT_BUS_FROM) + b.departure
	tt.set_time(1, (dep + float(b.lap) + 5.0) / Clock.SECONDS_PER_SIM_MINUTE)
	ok(tt.vehicle(b.id).status == "servicing", "bus 1 is serviced after its lap")
	tt.set_time(1, (dep + float(b.lap) + Clock.TRANSIT_SERVICE_SECONDS + 5.0) / Clock.SECONDS_PER_SIM_MINUTE)
	var v := tt.vehicle(b.id)
	ok(v.status == "waiting" and v.stop == "station", "then waits at its bay")
	tt.set_time(1, 23.5 * 60.0)
	ok(tt.vehicle("station-bus-0").status == "closed", "no buses after 22:30")
	ok(tt.vehicle("station-taxi-0").status != "closed", "taxi 0 runs all night")
	tt.set_time(1, 3.0 * 60.0)
	ok(tt.vehicle("station-taxi-2").status == "closed", "the other taxis rest at night")
	_report.append("laps: bus %.0f s (upstream %.0f s without stops), taxi %.0f s; period %.0f s" % [_bus("station-bus-0").lap,
		float(_bus("station-bus-0").path.length) / Clock.TRANSIT_SPEED_UNITS, _bus("station-taxi-0").lap, Clock.TRANSIT_PERIOD])


func test_timetable() -> void:
	var tab := tt.timetable("station", 1)
	# the service window is 06:00-22:30 of the town clock, which runs one sim minute a second: 990 s, so each bus
	# leaves its bay every 360 s about three times a day
	var want := 0
	for b: Dictionary in tt._buses:
		if b.bus:
			var t: float = Clock.TRANSIT_BUS_FROM * Clock.SECONDS_PER_SIM_MINUTE + b.departure
			while t < Clock.TRANSIT_BUS_TO * Clock.SECONDS_PER_SIM_MINUTE:
				want += 1
				t += Clock.TRANSIT_PERIOD
	ok(tab.size() == want and want == 9, "%d bay departures a day (06:00 to 22:30, 3 buses every 360 s): %d" % [want, tab.size()])
	var day0 := Clock.seconds_at(1, 0.0)
	var bad := 0
	for e: Dictionary in tab:
		var b := _bus(e.vehicle)
		var rel: float = float(e.departure_seconds) - day0 - Clock.TRANSIT_BUS_FROM * Clock.SECONDS_PER_SIM_MINUTE - b.departure
		if absf(fposmod(rel, Clock.TRANSIT_PERIOD)) > 1e-6:
			bad += 1
	ok(bad == 0, "every bay departure is 06:00 + 5 + 120 i + 360 k seconds (%d are not)" % bad)
	var widest := 0.0
	for k in range(1, tab.size()):
		widest = maxf(widest, float(tab[k].departure_seconds) - float(tab[k - 1].departure_seconds))
	ok(absf(widest - tt.BUS_SPREAD) < 1e-6, "the buses are spread evenly: a bus every %.0f s (BUS_SPREAD, Lantern Lane change)" % widest)
	ok(absf(float(tab[0].depart_minute) - (360.0 + 5.0 / Clock.SECONDS_PER_SIM_MINUTE)) < 1e-6, "the first bus leaves 5 s (five sim minutes) after 06:00")
	for id: String in ["bus-stop-1", "bus-stop-3", "bus-stop-4"]:
		var st := tt.timetable(id, 1)
		ok(st.size() == want, "%s: %d calls a day (%d)" % [id, want, st.size()])
		var sorted := true
		for k in range(1, st.size()):
			if float(st[k].departure_seconds) < float(st[k - 1].departure_seconds):
				sorted = false
		ok(sorted, "%s: in time order" % id)
		# the bus is really there, standing, at the timetable's minute
		for k in st.size():
			var e: Dictionary = st[k]
			tt.set_time(1, (float(e.arrive_minute) + float(e.depart_minute)) * 0.5)
			var v := tt.vehicle(e.vehicle)
			ok(v.status == "dwelling" and v.stop == id, "%s call %d: %s stands there (%s %s)" % [id, k, e.vehicle, v.status, v.stop])
	var ts := tt.timetable("bus-stop-3", 1)
	_report.append("bus-stop-3: first calls %s, %s, %s; dwell %d s" % [Clock.format_minute(ts[0].arrive_minute),
		Clock.format_minute(ts[1].arrive_minute), Clock.format_minute(ts[2].arrive_minute), int(Transit.DWELL)])


func test_next_departures() -> void:
	tt.set_time(1, 600.0)
	var nd := tt.next_departures("bus-stop-4", 3)
	ok(nd.size() == 3, "three next departures")
	var now := Clock.seconds_at(1, 600.0)
	var prev := -INF
	for e: Dictionary in nd:
		ok(float(e.departure_seconds) >= now and float(e.departure_seconds) >= prev, "upcoming and in order")
		ok(absf(float(e.in_seconds) - (float(e.departure_seconds) - now)) < 1e-6, "in_seconds counts down from now")
		prev = float(e.departure_seconds)
	ok(float(nd[0].in_seconds) <= Clock.TRANSIT_PERIOD, "a bus within the period (%.0f s)" % nd[0].in_seconds)
	tt.set_time(1, 1430.0)
	var late := tt.next_departures("station", 1)
	ok(late.size() == 1 and int(late[0].day) == 2, "after the last bus, the next is tomorrow's first")


func _standing_minute(id: String, stop_id: String, from_minute: float) -> float:
	for e: Dictionary in tt.timetable(stop_id, 1):
		if e.vehicle == id and float(e.arrive_minute) > from_minute:
			return (float(e.arrive_minute) + float(e.depart_minute)) * 0.5
	return -1.0


func test_boarding() -> void:
	var m := _standing_minute("station-bus-0", "bus-stop-3", 600.0)
	tt.set_time(1, m - 2.0)
	ok(not tt.can_board("station-bus-0") or tt.vehicle("station-bus-0").status == "dwelling", "no boarding a moving bus")
	ok(not tt.board("station-taxi-0", "kid"), "taxis take no riders")
	tt.set_time(1, m)
	ok(tt.can_board("station-bus-0"), "a bus standing at a stop takes riders")
	ok(tt.board("station-bus-0", "kid"), "board the bus")
	ok(not tt.board("station-bus-0", "kid"), "not twice")
	ok(tt.riding("kid") == "station-bus-0", "riding() names the bus")
	ok(int(tt.vehicle("station-bus-0").riders) == 1, "the bus counts its rider")
	var seat := tt.seat_transform("station-bus-0", 0)
	var bus_pos: Vector3 = tt.vehicle("station-bus-0").pos
	ok(seat.origin.distance_to(bus_pos) < 3.5, "the seat is in the bus")
	ok(tt.door_point("station-bus-0").distance_to(bus_pos) < 4.0, "the door is at the bus")
	# riding on: the seat moves with the bus, and no getting off while it moves
	tt.set_time(1, m + (Transit.DWELL * 0.5 + 3.0) / Clock.SECONDS_PER_SIM_MINUTE)
	ok(tt.vehicle("station-bus-0").moving, "the bus moves on")
	ok(not tt.alight("kid"), "no getting off a moving bus")
	ok(tt.seat_transform("station-bus-0", 0).origin.distance_to(seat.origin) > 0.5, "the seat goes with the bus")
	var m2 := _standing_minute("station-bus-0", "bus-stop-4", m)
	tt.set_time(1, m2)
	ok(tt.alight("kid"), "get off at the next stop")
	ok(tt.riding("kid") == "", "off the bus")
	# the seats run out
	for k in Transit.BUS_SEATS:
		tt.board("station-bus-0", "rider-%d" % k)
	ok(int(tt.vehicle("station-bus-0").riders) == Transit.BUS_SEATS, "the bus fills its %d seats" % Transit.BUS_SEATS)
	ok(not tt.can_board("station-bus-0") and not tt.board("station-bus-0", "one-more"), "a full bus takes nobody")
	for k in Transit.BUS_SEATS:
		tt.alight("rider-%d" % k)
	# at the bay shortly before leaving
	var dep_minute: float = float(tt.timetable("station", 1)[4].depart_minute)
	var who: String = tt.timetable("station", 1)[4].vehicle
	tt.set_time(1, dep_minute - 0.5)
	ok(tt.can_board(who), "a bus at its bay takes riders in the last minute before it leaves")
	tt.set_time(1, dep_minute - (Transit.BAY_BOARDING + 30.0) / Clock.SECONDS_PER_SIM_MINUTE)
	ok(not tt.can_board(who), "but not long before")


func test_signals() -> void:
	_events.clear()
	for k in 5000:   # 06:00 to 26:50, past the last bus's last lap (BUS_SPREAD puts it at 22:05 + 4 min)
		tt.set_time(4, 360.0 + k * 0.25)
	var arrived := 0
	var departed := 0
	var at_stop := 0
	for e: Array in _events:
		if e[0] == "arrived":
			arrived += 1
			if String(e[2]).begins_with("bus-stop"):
				at_stop += 1
		else:
			departed += 1
	ok(at_stop == 27, "every bus arrives at its three stops on each of its runs (%d of 27)" % at_stop)
	ok(absi(arrived - departed) <= 6, "arrivals and departures pair up (%d / %d)" % [arrived, departed])


func test_traffic() -> void:
	tt.set_time(1, 720.0)
	var noon := 0
	var on_loop := true
	for v: Dictionary in tt.vehicles():
		if v.kind in ["bus", "taxi"]:
			continue
		if v.status != "closed":
			noon += 1
		var c: Dictionary = {}
		for x: Dictionary in tt._cars:
			if x.id == v.id:
				c = x
		var lp: Dictionary = tt._loops[c.loop]
		var best := INF
		var pts: PackedVector2Array = lp.pts
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(Vector2(v.pos.x, v.pos.z), pts[k], pts[k + 1])
			best = minf(best, q.distance_to(Vector2(v.pos.x, v.pos.z)))
		if best > 1e-3:
			on_loop = false
	ok(noon == 40, "all 40 cars out at noon (%d)" % noon)
	ok(on_loop, "every car on its traffic loop")
	tt.set_time(1, 180.0)
	var night := 0
	for v: Dictionary in tt.vehicles():
		if not v.kind in ["bus", "taxi"] and v.status != "closed":
			night += 1
	ok(night < 15 and night > 0, "the night thins the traffic (%d at 03:00)" % night)
	ok(Transit.road_y(Vector2(0.0, 78.8)) < -1.5, "the ring traffic runs under the canal in the tunnel (%.2f m)" % Transit.road_y(Vector2(0.0, 78.8)))
	ok(Transit.road_y(Vector2(0.0, 40.0)) > 0.9, "and over it on the road bridges (%.2f m)" % Transit.road_y(Vector2(0.0, 40.0)))
	ok(Transit.road_y(Vector2(0.0, 123.7)) > 2.0, "and up on the viaducts (%.2f m)" % Transit.road_y(Vector2(0.0, 123.7)))
	ok(absf(Transit.road_y(Vector2(-48.0, -60.0)) - 0.125) < 1e-6, "on the avenues at road level")
	# cars keep moving along at their speed
	tt.set_time(1, 700.0)
	var a := tt.vehicle("car-2-3").pos as Vector3
	tt.set_time(1, 700.0 + 1.0 / 60.0)
	var b := tt.vehicle("car-2-3").pos as Vector3
	var speed := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) * 60.0
	ok(absf(speed - float(tt._cars[23].speed)) < 0.2, "a car drives at its own speed (%.2f m/s)" % speed)
	_report.append("traffic: %d cars at noon, %d at 03:00" % [noon, night])


func test_determinism() -> void:
	var other := Transit.new()
	root.add_child(other)
	other.setup()
	for row: Array in [[1, 450.3], [1, 1020.7], [7, 600.1], [3, 1371.2]]:
		other.set_time(5, 200.0)
		other.set_time(int(row[0]), float(row[1]))
		tt.set_time(int(row[0]), float(row[1]))
		var same := true
		for v: Dictionary in tt.vehicles():
			var w := other.vehicle(v.id)
			if not (v.pos as Vector3).is_equal_approx(w.pos) or v.status != w.status or absf(float(v.yaw) - float(w.yaw)) > 1e-9:
				same = false
		ok(same, "day %d %.1f: the same fleet whatever came before" % [row[0], row[1]])
	other.queue_free()


func test_budgets() -> void:
	tt.set_time(1, 720.0)
	ok(tt.draw_calls() <= 7, "transit draws in at most 7 calls (%d)" % tt.draw_calls())
	var total := 0.0
	var n := 600
	for k in n:
		var t := Time.get_ticks_usec()
		tt.set_time(1, 720.0 + k / 60.0)
		total += (Time.get_ticks_usec() - t) / 1000.0
	ok(total / n < 1.5, "transit update %.3f ms a frame" % (total / n))
	_report.append("transit: update avg %.3f ms a frame (EC2 headless), %d draw calls, %d vehicles" % [total / n, tt.draw_calls(), tt.vehicles().size()])
