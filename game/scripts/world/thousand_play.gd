## Thousand Town's interactions (design/thousand-town.md, "Interactions"): what a child does in the town, each
## grounded in the simulation (core/thousand_sim.gd through the world's sample and plans, the residents of
## art/thousand_people.gd, the buses of world/thousand_transit.gd and the shows of world/thousand_events.gd).
## The play controller owns this node and asks it, the HUD shows what it reports. Everything is local to this
## device: friends see the child where it is (its state), nothing else goes over the network (no protocol change).
##
##   I1 Meet a resident    a tap on a drawn figure, or "Say hello" within HELLO_REACH: the child turns and waves,
##                         the resident card opens (name in the reader's language, role, age, now, heading, ETA),
##                         a marker floats over the resident while selected.
##   I2 Follow             the card's (or the inspect panel's) Follow: the child walks after the resident along
##                         the pavements, the rest of the resident's trip is drawn on the ground, the chip says
##                         where to and how long; into a building it offers that building's "Who's here?"; aboard
##                         a bus or out of sight it ends.
##   I3 Visit a building   "Who's here?" (play_controller / hud: the inspect panel from the sim).
##   I4 Bus                at a served stop or the station's bays: Wait for the bus (a countdown to the next
##                         departure), Get on the bus, ride seated with the camera behind the bus and the next stop
##                         named, Get off at a stop; at the end of the lap everybody gets off at the bays.
##   I5 Ferris wheel       while the amusement park is open in the sim: one turn in a cabin with the camera looking
##                         out over the town; Get off at the bottom only. Closed: when it opens.
##   I6 Night market       at a stall while the market is open: a snack in the child's hand for a while and a toast
##                         naming a shopkeeper who is there now. Closed: when it opens (18:00).
##   I7 Shows              Watch the fireworks (19:00-22:00) or the fountain show (its "show" programme): walk to
##                         the events node's watch point and hold the camera on the show (its watch camera); outside
##                         the window the button says when it is next on.
## The state is one of STATES; end_all() ends any of them cleanly (the tram home, leaving the town, a new session).
extends Node

const Places := preload("res://scripts/core/places.gd")
const Data := preload("res://scripts/core/thousand_sim_data.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const Inspect := preload("res://scripts/core/thousand_inspect.gd")
const TPanel := preload("res://scripts/ui/thousand_panel.gd")
const People := preload("res://scripts/art/thousand_people.gd")

signal changed()

const STATES := ["", "follow", "follow_inside", "wait_bus", "bus", "wheel_wait", "wheel", "watch"]
## How near (m) a drawn resident offers "Say hello", a stop's waiting point "Wait for the bus", a stall's counter
## "Buy a snack", and the wheel's boarding point "Ride the wheel".
const HELLO_REACH := 3.0
const STOP_REACH := 3.0
const STALL_REACH := 1.8
const WHEEL_REACH := 4.0
## Following: re-route every FOLLOW_EVERY s, keep FOLLOW_GAP m behind; out of sight for LOST_AFTER s ends it.
const FOLLOW_EVERY := 1.0
const FOLLOW_GAP := 2.6
const LOST_AFTER := 4.0
## The bus: the camera stands back this far to keep the bus in the picture.
const BUS_VIEW := 11.0
## The wheel: a cabin within BOARD_ANGLE of the bottom takes the child; Get off within OFF_ANGLE of it.
const BOARD_ANGLE := 0.09
const OFF_ANGLE := 0.22
const CABIN_DROP := 2.82      # from a cabin's hanging point down to its floor (the cabin mesh is 2.94 m tall)
const SNACK_SECONDS := 45.0
## The sim's opening rule for the night market (thousand_sim.gd _public_open: kind "night-market", m >= 1080).
const MARKET_OPENS := 1080.0
const STALL_SNACKS := {
	"dessert": ["%s hands you a bowl of sweet jelly.", "cup", Color("#f29bb2")],
	"grill": ["%s hands you a grilled skewer.", "skewer", Color("#c8552e")],
	"juice": ["%s hands you a cup of fresh juice.", "cup", Color("#f5a623")],
	"deli": ["%s hands you a steamed bun.", "bun", Color("#f6ecd6")],
	"hotpot": ["%s hands you a cup of hotpot skewers.", "cup", Color("#d8423a")],
	"griddle": ["%s hands you a hot pancake.", "bun", Color("#e3a94f")],
}

var c: Node = null               # the play controller
var state := ""
var selected := -1               # the resident with the marker (card open, followed, or picked in the panel)
var card_open := false
var follow_id := -1
var follow_place := ""           # the building (ledger id) the followed resident went into
var stop_id := ""                # the stop being waited at (or "station")
var bus_id := ""
var cabin := -1
var turned := 0.0                # radians the cabin has turned since the child got in
var watch_kind := ""
var snack_until := 0.0           # Time.get_ticks_msec() / 1000 when the snack is eaten
var snack_kind := ""
var _bus_left := false
var _cabin_angle := 0.0
var _saved_dist := -1.0
var _follow_t := 0.0
var _route_t := 0.0
var _lost_t := 0.0
var _stuck_t := 0.0              # following: seconds the child has made no headway toward the followed resident
var _stuck_from := Vector2.INF
const STUCK_AFTER := 4.0         # then the follow ends as when they are lost from sight
var _watch_point := {}
var _watch_arrived := false
var _marks: Node3D
var _marker: Node3D
var _ring: MeshInstance3D
var _route: MeshInstance3D
var _route_mesh: ImmediateMesh
var _route_mat: StandardMaterial3D
var _stand_cache := {}
var _stop_names := {}


func setup(controller: Node) -> void:
	c = controller


func rider_key() -> String:
	return "peer:%d" % Session.my_id


# ------------------------------------------------------------- the world's parts

func tw() -> Node3D:
	return c.world.thousand_world if c and c.world and c.space == Places.THOUSAND else null


func people() -> Node3D:
	return c.world.get("thousand_people") if c and c.world else null


func transit() -> Node3D:
	return c.world.get("thousand_transit") if c and c.world else null


## The fireworks and fountain node (world/thousand_events.gd) when the lead has added it, else null.
func events() -> Node:
	if c == null or c.world == null:
		return null
	var e: Node = c.world.get("thousand_events")
	if e == null and c.world.thousand_world:
		for n in c.world.thousand_world.get_children():
			if n.has_method("watch_point") and n.has_method("status"):
				e = n
	return e if e != null and is_instance_valid(e) else null


func clock() -> Dictionary:
	var w := tw()
	return w.view_time() if w else {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}


func minute() -> float:
	return fposmod(float(clock().get("minute", 480.0)), 1440.0)


func locale() -> String:
	return TranslationServer.get_locale()


func busy() -> bool:
	return state in ["bus", "wheel"]


func _kid() -> Node3D:
	return c.world.local_kid() if c and c.world else null


# ------------------------------------------------------------- names

## A sim location id ("c-mall", "street", ...) as the reader's text.
func place_text(id: String) -> String:
	var w := tw()
	if id == "" or id == "street":
		return tr(Inspect.STREET_NAME)
	var names: Dictionary = w.NAMES if w else {}
	return tr(str(names.get(id, id)))


func resident_name(i: int) -> String:
	var w := tw()
	return w.sim.name_of(i, locale()) if w and w.sim else str(i)


## The stop's name for people: the nearest building's door within 45 m ("Mall stop"), the station's bays.
func stop_name(id: String) -> String:
	if id == "station":
		return tr("Station")
	if _stop_names.has(id):
		return tr("%s stop") % tr(str(_stop_names[id]))
	var tr_node := transit()
	var w := tw()
	if tr_node == null or w == null:
		return tr("Bus stop")
	for s: Dictionary in tr_node.stops():
		if str(s.id) == id:
			var best := ""
			var bd := 45.0
			for site: Dictionary in w.sites():
				if site.door is Vector2 and str(site.kind) == "building":
					var d: float = (site.door as Vector2).distance_to(s.pos)
					if d < bd:
						bd = d
						best = str(site.name)
			if best != "":
				_stop_names[id] = best
				return tr("%s stop") % tr(best)
	return tr("Bus stop")


static func hhmm(m: float) -> String:
	return Clock.format_minute(m)


# ------------------------------------------------------------- I1 meeting a resident

## A tap in the town: a drawn figure under the finger is met. True when it was one.
func tap(screen: Vector2) -> bool:
	var pp := people()
	if pp == null or c.rig == null or c.rig.camera == null:
		return false
	var id: int = pp.pick_screen(c.rig.camera, screen)
	if id < 0:
		return false
	meet(id)
	return true


## Turns the child toward resident `id` with a wave and opens the card.
func meet(id: int) -> void:
	var pp := people()
	if pp == null or id < 0:
		return
	if state in ["follow", "follow_inside"] and follow_id != id:
		_end_state(false)
	var p: Vector3 = pp.position_of(id)
	if p != Vector3.INF:
		var d: Vector2 = Vector2(p.x, p.z) - c.pos
		if d.length() > 0.05:
			c.ry = atan2(d.x, d.y)
	if state == "" or state == "wait_bus" or state == "watch":
		c._walk_target = null
		c._pending_ctx = {}
		c._city_route = []
	Session.send_emote("wave")
	Sfx.play("pop")
	selected = id
	card_open = true
	changed.emit()


func close_card() -> void:
	if not card_open:
		return
	card_open = false
	if state not in ["follow", "follow_inside"]:
		selected = -1
	changed.emit()


## The resident card's contents: {"id", "name", "who" (role and age), "now", "heading", "can_follow"}; {} when none.
func card() -> Dictionary:
	if not card_open or selected < 0:
		return {}
	var pp := people()
	if pp == null:
		return {}
	var info: Dictionary = pp.info(selected, locale())
	if info.is_empty():
		return {}
	var role := str(Inspect.ROLE_IDS.get(str(info.get("role", "")), str(info.get("role", ""))))
	var out := {"id": selected, "name": str(info.get("name", "")),
		"who": "%s · %s" % [tr(TPanel.role_name(role)), tr("%d years old") % int(info.get("age", 0))]}
	var lines := describe(info)
	out["now"] = lines[0]
	out["heading"] = lines[1]
	out["can_follow"] = _followable(info)
	return out


## Two lines for a resident's info: what they are doing now and where (a state and a place), and where they are
## heading with the time they get there ("" when they stay where they are).
func describe(info: Dictionary) -> Array:
	var st := Data.STATES.find(str(info.get("state", "")))
	var st_text := tr(TPanel.state_name(Inspect.STATE_IDS[st])) if st >= 0 else ""
	var mode := str(info.get("mode", "inside"))
	var where := place_text(str(info.get("where", "")))
	var to := str(info.get("to", ""))
	var eta := float(info.get("eta_minute", -1.0))
	match mode:
		"inside":
			return ["%s · %s" % [st_text, where], tr("Until about %s") % hhmm(eta) if eta >= 0.0 else ""]
		"aboard":
			return [tr("On the bus"), tr("Heading to %s") % place_text(to) + " · " + tr("arrives about %s") % hhmm(eta)]
		"waiting":
			var stops: Array = info.get("stops", [])
			return [tr("Waiting for the bus") if not stops.is_empty() else st_text,
				tr("Heading to %s") % place_text(to) + " · " + tr("arrives about %s") % hhmm(eta) if to != "" else ""]
		"walk", "jog":
			if str(info.get("trip", "")) == "outing" or to == "" or to == str(info.get("from", "")):
				return [tr("Out for a walk"), tr("Back home about %s") % hhmm(eta)]
			return [tr("Walking") if mode == "walk" else tr("Jogging"),
				tr("Heading to %s") % place_text(to) + " · " + tr("arrives about %s") % hhmm(eta)]
	# at an outdoor venue (the plaza, a park, the market, the station)
	return ["%s · %s" % [st_text, where], tr("Until about %s") % hhmm(eta) if eta >= 0.0 else ""]


func _followable(info: Dictionary) -> bool:
	return bool(info.get("drawn", false)) and str(info.get("mode", "inside")) not in ["inside", "aboard"]


# ------------------------------------------------------------- I2 following a commute

func can_follow(id: int) -> bool:
	var pp := people()
	return pp != null and id >= 0 and _followable(pp.info(id, locale()))


func start_follow(id: int) -> bool:
	if not can_follow(id) or busy():
		return false
	_end_state(false)
	state = "follow"
	follow_id = id
	selected = id
	card_open = false
	follow_place = ""
	_follow_t = 0.0
	_route_t = 0.0
	_lost_t = 0.0
	_stuck_t = 0.0
	_stuck_from = Vector2.INF
	Sfx.play("tap")
	changed.emit()
	return true


func _follow_frame(delta: float) -> void:
	var pp := people()
	if pp == null:
		_end_state(true)
		return
	var info: Dictionary = pp.info(follow_id, locale())
	var mode := str(info.get("mode", "inside"))
	var who_name := str(info.get("name", ""))
	if mode == "aboard":
		c.toast.emit(tr("%s got on the bus.") % who_name)
		_end_state(true)
		return
	if mode == "inside":
		if state != "follow_inside":
			state = "follow_inside"
			follow_place = str(info.get("where", ""))
			c._walk_target = null
			c._city_route = []
			_clear_route()
			changed.emit()
		return
	if state == "follow_inside":
		state = "follow"   # out again: the follow goes on
		_follow_t = 0.0
		changed.emit()
	if not bool(info.get("drawn", false)):
		_lost_t += delta
		if _lost_t > LOST_AFTER:
			c.toast.emit(tr("You lost sight of %s.") % who_name)
			_end_state(true)
		return
	_lost_t = 0.0
	# Stuck behind something (the residents' pavements pass where the child's own walking does not, e.g. along the
	# market's stall row; the loop tour saw the child pressed against it for good): after STUCK_AFTER s without
	# 0.5 m of headway while behind, the follow ends as when the resident is lost from sight.
	var rpos: Vector3 = pp.position_of(follow_id)
	if c.pos.distance_to(Vector2(rpos.x, rpos.z)) > FOLLOW_GAP + 1.5:
		if _stuck_from == Vector2.INF or c.pos.distance_to(_stuck_from) > 0.5:
			_stuck_from = c.pos
			_stuck_t = 0.0
		_stuck_t += delta
		if _stuck_t > STUCK_AFTER:
			c.toast.emit(tr("You lost sight of %s.") % who_name)
			_end_state(true)
			return
	else:
		_stuck_from = Vector2.INF
		_stuck_t = 0.0
	_follow_t -= delta
	if _follow_t <= 0.0:
		_follow_t = FOLLOW_EVERY
		var p: Vector3 = pp.position_of(follow_id)
		var at := Vector2(p.x, p.z)
		if c.pos.distance_to(at) > FOLLOW_GAP + 0.6:
			walk_route(at + (c.pos - at).normalized() * FOLLOW_GAP)
		else:
			c._walk_target = null
			c._city_route = []
			var d: Vector2 = at - c.pos
			if d.length() > 0.05:
				c.ry = atan2(d.x, d.y)
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.5
		_draw_route(pp.route_of(follow_id), pp.position_of(follow_id))


## Walks the child to `to` along the residents' pavements (art/thousand_people.gd Ground.route) when there is a
## way, else straight (the child's own walking slides along walls).
func walk_route(to: Vector2, then: Dictionary = {}) -> void:
	var g = People.ground()
	var a: Vector2 = g.snap(c.pos, 8.0, g.main_area)
	var b: Vector2 = g.snap(to, 8.0, g.main_area)
	var pts := PackedVector2Array()
	if a != Vector2.INF and b != Vector2.INF:
		pts = g.route(a, b)
	var way: Array = []
	for k in range(1, pts.size()):
		way.append({"region": "", "pos": pts[k]})
	way.append({"region": "", "pos": to})
	c._city_route = way
	c._walk_target = (c._city_route.pop_front() as Dictionary)["pos"]
	c._pending_ctx = then


# ------------------------------------------------------------- I4 the bus

## The stops the buses call at, each with the point where a child waits: {id: Vector2}.
func stands() -> Dictionary:
	if not _stand_cache.is_empty():
		return _stand_cache
	var tr_node := transit()
	var w := tw()
	if tr_node == null or w == null:
		return {}
	var served: PackedStringArray = tr_node.served_stops()
	for s: Dictionary in tr_node.stops():
		if served.has(str(s.id)):
			_stand_cache[str(s.id)] = w.resolve_walk(s.pos)
	# the station: by the bays, on the platform side
	var acc := Vector3.ZERO
	var n := 0
	for v: Dictionary in tr_node.vehicles():
		if str(v.kind) == "bus":
			var bp: Vector3 = tr_node.bay_point(str(v.id))
			if bp != Vector3.INF:
				acc += bp
				n += 1
	if n > 0:
		var mid := acc / n
		_stand_cache["station"] = w.resolve_walk(Vector2(mid.x, mid.z - 3.0))
	return _stand_cache


func stop_here() -> String:
	var best := ""
	var bd := STOP_REACH
	var st := stands()
	for id: String in st:
		var d: float = c.pos.distance_to(st[id])
		if d < bd:
			bd = d
			best = id
	return best


## The bus standing at `stop` that takes riders now, or "".
func bus_at(stop: String) -> String:
	var tr_node := transit()
	if tr_node == null:
		return ""
	for v: Dictionary in tr_node.vehicles():
		if str(v.kind) == "bus" and str(v.stop) == stop and tr_node.can_board(str(v.id)):
			return str(v.id)
	return ""


func start_wait(stop: String) -> void:
	if busy():
		return
	_end_state(false)
	state = "wait_bus"
	stop_id = stop
	var at: Vector2 = stands().get(stop, c.pos)
	if c.pos.distance_to(at) > 0.4:
		walk_route(at)
	Sfx.play("tap")
	changed.emit()


func board(vid: String) -> bool:
	var tr_node := transit()
	if tr_node == null or busy() or not tr_node.board(vid, rider_key()):
		c.hint.emit(tr("The bus has just left. Wait for the next one."))
		return false
	_end_state(false)
	state = "bus"
	bus_id = vid
	_bus_left = false
	c._walk_target = null
	c._city_route = []
	c._pending_ctx = {}
	c.walking = false
	if c.rig:
		_saved_dist = c.rig.t_dist
		c.rig.t_dist = BUS_VIEW
	Sfx.play("pop")
	changed.emit()
	return true


func get_off() -> bool:
	var tr_node := transit()
	if state != "bus" or tr_node == null:
		return false
	var door: Vector3 = tr_node.door_point(bus_id)
	if not tr_node.alight(rider_key()):
		return false
	var stop := str(tr_node.vehicle(bus_id).get("stop", ""))
	_leave_bus(door)
	c.toast.emit(tr("You got off at %s.") % stop_name(stop) if stop != "" else tr("You got off the bus."))
	return true


func _leave_bus(door: Vector3) -> void:
	var w := tw()
	state = ""
	bus_id = ""
	if c.rig and _saved_dist > 0.0:
		c.rig.t_dist = _saved_dist
	_saved_dist = -1.0
	if door != Vector3.INF and w:
		c.pos = w.resolve_walk(Vector2(door.x, door.z))
	var kid := _kid()
	if kid:
		kid.anim = "idle"
	c._place_kid()
	changed.emit()


func _bus_frame(kid: Node3D) -> void:
	var tr_node := transit()
	if tr_node == null or tr_node.riding(rider_key()) != bus_id:
		_leave_bus(Vector3.INF)
		return
	var v: Dictionary = tr_node.vehicle(bus_id)
	var status := str(v.get("status", ""))
	if status in ["departing", "running", "arriving", "leaving", "dwelling", "returning"]:
		_bus_left = true
	elif _bus_left and status in ["servicing", "waiting", "closed"]:
		# the end of the lap: everybody gets off at the bays
		var door: Vector3 = tr_node.door_point(bus_id)
		tr_node.alight(rider_key(), true)
		_leave_bus(door)
		c.toast.emit(tr("Back at the station. Everybody off!"))
		return
	var seat: int = maxi(0, (tr_node.riders(bus_id) as Array).find(rider_key()))
	var xf: Transform3D = tr_node.seat_transform(bus_id, seat)
	xf.origin.y -= 0.45
	if kid:
		kid.global_transform = xf
		kid.anim = "sit"
	c.pos = Vector2(xf.origin.x, xf.origin.z)
	var fwd := -xf.basis.z
	c.ry = atan2(fwd.x, fwd.z)


## The chip while waiting or riding: [text, buttons ([label, action])].
func _bus_chip() -> Array:
	var tr_node := transit()
	if tr_node == null:
		return ["", []]
	var ck := clock()
	if state == "bus":
		var v: Dictionary = tr_node.vehicle(bus_id)
		if str(v.get("status", "")) == "dwelling":
			return [tr("At %s") % stop_name(str(v.stop)), [["Get off", "bus_off"]]]
		var nxt: String = tr_node.next_stop(bus_id)
		if str(ck.get("mode", "auto")) != "auto":
			return [tr("On the bus · the clock is stopped. Tap Auto to ride on."), []]
		return [tr("On the bus · next stop: %s") % stop_name(nxt if nxt != "" else "station"), []]
	# waiting
	if bus_at(stop_id) != "":
		return [tr("The bus is here!"), [["Get on the bus", "bus_board"], ["Stop waiting", "end"]]]
	if str(ck.get("mode", "auto")) != "auto":
		return [tr("The clock is stopped. Tap Auto to let the bus come."), [["Stop waiting", "end"]]]
	var m := minute()
	var deps: Array = tr_node.next_departures(stop_id, 1)
	if m < Clock.TRANSIT_BUS_FROM or m >= Clock.TRANSIT_BUS_TO or deps.is_empty() or int(deps[0].day) != int(ck.get("day", 1)):
		var first := hhmm(float(deps[0].arrive_minute)) if not deps.is_empty() else hhmm(Clock.TRANSIT_BUS_FROM)
		return [tr("No buses now. The first bus comes at %s.") % first, [["Stop waiting", "end"]]]
	var speed := maxf(1.0, float(ck.get("speed", 1)))
	var secs := maxi(0, int(ceil((float(deps[0].arrive_minute) - m) * Clock.SECONDS_PER_SIM_MINUTE / speed)))
	@warning_ignore("integer_division")
	return [tr("%s · next bus in %s") % [stop_name(stop_id), "%d:%02d" % [secs / 60, secs % 60]], [["Stop waiting", "end"]]]


# ------------------------------------------------------------- I5 the ferris wheel

var _board_point := Vector2.INF


## Where a child stands to get into a cabin: in front of the wheel's foot (the bottom cabin rests there).
func wheel_board_point() -> Vector2:
	var w := tw()
	if w == null:
		return Vector2.INF
	if _board_point == Vector2.INF and w.cabin_count() > 0:
		var f: Transform3D = w.wheel_frame()
		var p := f * Vector3(0.0, 0.0, 2.4)
		_board_point = w.resolve_walk(Vector2(p.x, p.z))
	return _board_point


func at_wheel() -> bool:
	var p := wheel_board_point()
	return p != Vector2.INF and c.pos.distance_to(p) < WHEEL_REACH


## The amusement park's row of the last sample (open, count, present), {} before the first.
func site_row(id: String) -> Dictionary:
	var w := tw()
	if w == null:
		return {}
	for b: Dictionary in w.town_sample().get("buildings", []):
		if str(b.id) == id:
			return b
	return {}


## The first minute after now (today) at which someone's plan puts them at building `id` awake, or -1: when a
## place that opens for its visitors (the amusement park) opens next (thousand_sim.gd _public_open: open while
## somebody there is awake or on the way).
func next_open(id: String) -> float:
	var w := tw()
	if w == null or w.plans() == null:
		return -1.0
	var b := -1
	for i in Data.BUILDINGS.size():
		if str(Data.BUILDINGS[i].id) == id:
			b = i
	if b < 0:
		return -1.0
	var plans = w.plans()
	var segs: PackedInt32Array = plans.segs
	var first: PackedInt32Array = plans.first
	var m := minute()
	var best := INF
	for i in plans.built:
		for s in range(first[i], first[i + 1]):
			if segs[s * Data.SEG + 3] != b or segs[s * Data.SEG + 2] == Data.ST_SLEEPING:
				continue
			var start := float(segs[s * Data.SEG])
			# on the way there counts: the street segment before it
			if s > first[i] and segs[(s - 1) * Data.SEG + 3] == Data.STREET:
				start = float(segs[(s - 1) * Data.SEG])
			if start > m and start < best:
				best = start
	return best if best < INF else -1.0


func start_wheel() -> void:
	if busy():
		return
	var row := site_row("c-amusement")
	if not bool(row.get("open", false)):
		var at := next_open("c-amusement")
		c.hint.emit(tr("The amusement park is closed. It opens at %s.") % hhmm(at) if at >= 0.0 else tr("The amusement park is closed until tomorrow."))
		return
	_end_state(false)
	state = "wheel_wait"
	cabin = -1
	var p := wheel_board_point()
	if c.pos.distance_to(p) > 0.4:
		c._walk_to(p, {})
	Sfx.play("tap")
	changed.emit()


func _cabin_angle_of(k: int) -> float:
	var w := tw()
	var p: Vector3 = w.cabin_position(k) if w else Vector3.INF
	if p == Vector3.INF:
		return 0.0
	return atan2(p.y - 13.0, p.x)


func _off_bottom(k: int) -> float:
	return absf(angle_difference(_cabin_angle_of(k), -PI / 2.0))


func _wheel_frame(kid: Node3D, delta: float) -> void:
	var w := tw()
	if w == null:
		_end_state(true)
		return
	if state == "wheel_wait":
		if c._walk_target != null:
			return
		for k in w.cabin_count():
			if _off_bottom(k) < BOARD_ANGLE:
				state = "wheel"
				cabin = k
				turned = 0.0
				_cabin_angle = _cabin_angle_of(k)
				c.walking = false
				Sfx.play("pop")
				changed.emit()
				break
		return
	var a := _cabin_angle_of(cabin)
	turned += absf(angle_difference(_cabin_angle, a))
	_cabin_angle = a
	var hang: Vector3 = w.cabin_global(cabin)
	if hang == Vector3.INF:
		return
	var floor_at := hang - Vector3(0.0, CABIN_DROP, 0.0)
	var out := _wheel_outward(w)
	c.ry = atan2(out.x, out.y)
	if kid:
		kid.global_transform = Transform3D(Basis(Vector3.UP, c.ry), floor_at)
		kid.anim = "idle"
	c.pos = Vector2(floor_at.x, floor_at.z)
	if c.rig:
		c.rig.t_watch = _wheel_camera(floor_at, out)
		c.rig.t_watch_free = true   # unified r4: a drag, the right stick, L / R and zoom look around from the cabin
	if turned >= TAU - 0.05 and _off_bottom(cabin) < OFF_ANGLE * 0.5:
		get_off_wheel()
		c.toast.emit(tr("One whole turn! What a view."))


## The way a cabin looks out: along the wheel's axle (the cabins' open side; along the wheel's own plane the rim,
## the spokes and the next cabins fill the view), toward the side with more of the town.
static func _wheel_outward(w: Node3D) -> Vector2:
	var f: Transform3D = w.wheel_frame()
	var axle := Vector2(f.basis.z.x, f.basis.z.z).normalized()
	var foot := Vector2(f.origin.x, f.origin.z)
	return axle if (foot + axle * 60.0).length() < (foot - axle * 60.0).length() else -axle


## The camera at the cabin's open front, just outside it, at the child's eye height, looking out over the town and
## a little down (the child is in the cabin behind the camera; the chip says so).
static func _wheel_camera(child: Vector3, out: Vector2) -> Transform3D:
	var dir := Vector3(out.x, 0.0, out.y)
	var eye := child + dir * 1.45 + Vector3(0.0, 1.5, 0.0)
	var look := eye + dir * 60.0 - Vector3(0.0, minf(eye.y * 0.8, 20.0), 0.0)
	return Transform3D(Basis.looking_at((look - eye).normalized(), Vector3.UP), eye)


func can_get_off_wheel() -> bool:
	return state == "wheel" and cabin >= 0 and _off_bottom(cabin) < OFF_ANGLE


func get_off_wheel() -> bool:
	if state != "wheel":
		return false
	state = ""
	cabin = -1
	if c.rig:
		c.rig.t_watch = null
	c.pos = wheel_board_point()
	var kid := _kid()
	if kid:
		kid.anim = "idle"
	c._place_kid()
	changed.emit()
	return true


# ------------------------------------------------------------- I6 the night market

## The stall whose counter the child stands at: {id, type, pos (the counter), index}; {} for none.
func stall_here() -> Dictionary:
	var d := TMap.data()
	var stalls: Array = d.get("waterfront", {}).get("stalls", [])
	var best := {}
	var bd := STALL_REACH
	for k in stalls.size():
		var st: Dictionary = stalls[k]
		var cp := Vector2(float(st.x) - float(st.side) * (float(st.d) * 0.5 + 0.8), float(st.z))
		var dd: float = c.pos.distance_to(cp)
		if dd < bd:
			bd = dd
			best = {"id": str(st.id), "type": str(st.type), "pos": cp, "index": k}
	return best


## The shopkeepers at the night market now (the sample's present list, role shopkeeper), in roster order.
func market_keepers() -> Array:
	var w := tw()
	var row := site_row("c-night-market")
	var out: Array = []
	if w == null or row.is_empty() or w.sim == null:
		return out
	for i: int in row.get("present", PackedInt32Array()):
		if w.sim.role_name(i) == "shopkeeper":
			out.append(i)
	return out


func market_open() -> bool:
	return bool(site_row("c-night-market").get("open", false))


func buy_snack(stall: Dictionary) -> bool:
	if not market_open():
		c.hint.emit(tr("The night market opens at %s.") % hhmm(MARKET_OPENS))
		return false
	var keepers := market_keepers()
	if keepers.is_empty():
		c.hint.emit(tr("Nobody is at the stalls right now."))
		return false
	var who: int = keepers[int(stall.get("index", 0)) % keepers.size()]
	var spec: Array = STALL_SNACKS.get(str(stall.get("type", "")), STALL_SNACKS["deli"])
	snack_kind = str(stall.get("type", "deli"))
	snack_until = Time.get_ticks_msec() / 1000.0 + SNACK_SECONDS
	_attach_snack(spec)
	Session.send_emote("cheer")
	Sfx.play("pop")
	c.toast.emit(tr(str(spec[0])) % resident_name(who))
	changed.emit()
	return true


func has_snack() -> bool:
	return snack_kind != "" and Time.get_ticks_msec() / 1000.0 < snack_until


## The snack in the child's right hand: under the arm's Hand pivot (art/kid.gd keeps it upright), bold enough to
## read at the follow camera's distance.
func _attach_snack(spec: Array) -> void:
	_remove_snack()
	var kid := _kid()
	if kid == null:
		return
	var arm := kid.find_child("ArmR", true, false) as Node3D
	if arm == null:
		return
	var hand := arm.get_node_or_null("Hand") as Node3D
	if hand == null:
		hand = Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0.04, -0.29, 0.0)
		hand.set_meta("tt_made", true)
		arm.add_child(hand)
	var snack := Node3D.new()
	snack.name = "TTSnack"
	snack.scale = Vector3.ONE * 1.4   # bold enough to read at the follow camera's 7 m
	hand.add_child(snack)
	var col: Color = spec[2]
	match str(spec[1]):
		"skewer":
			_part(snack, _cyl(0.012, 0.012, 0.42), Color("#c9a26b"), Vector3(0, 0.16, 0.06))
			for k in 3:
				_part(snack, _ball(0.06), col.lightened(0.08 * k), Vector3(0, 0.2 + 0.11 * k, 0.06))
		"cup":
			_part(snack, _cyl(0.085, 0.065, 0.18), Color("#fdf8ef"), Vector3(0, 0.08, 0.07))
			_part(snack, _cyl(0.078, 0.078, 0.02), col, Vector3(0, 0.17, 0.07))
			_part(snack, _cyl(0.008, 0.008, 0.2), Color("#e04f5f"), Vector3(0.03, 0.24, 0.07))
		_:
			var bun := _part(snack, _ball(0.1), col, Vector3(0, 0.1, 0.07))
			bun.scale = Vector3(1.0, 0.72, 1.0)
	snack.set_meta("kind", str(spec[1]))


func _remove_snack() -> void:
	var kid := _kid()
	if kid == null:
		return
	var s := kid.find_child("TTSnack", true, false)
	if s:
		var hand := s.get_parent()
		hand.remove_child(s)
		s.queue_free()
		if hand.has_meta("tt_made") and hand.get_child_count() == 0:
			hand.get_parent().remove_child(hand)
			hand.queue_free()


static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 14
	m.rings = 1
	return m


static func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


static func _part(parent: Node3D, mesh: Mesh, col: Color, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------- I7 the shows

## {"fireworks": bool, "fountain": bool}: is each show on now (the events node's status when there is one, the
## same schedules from thousand_clock.gd otherwise).
func shows_now() -> Dictionary:
	var e := events()
	var m := minute()
	if e != null:
		var st: Dictionary = e.status()
		if st.has("fireworks"):
			return {"fireworks": bool(st.get("fireworks", false)), "fountain": bool(st.get("fountain_show", false))}
	return {"fireworks": m >= Clock.FIREWORKS_FROM and m < Clock.FIREWORKS_TO, "fountain": Clock.fountain_program(m) == "show"}


## The HUD's show buttons: [{"kind", "label", "on"}].
func show_buttons() -> Array:
	var on := shows_now()
	var fw_from := hhmm(Clock.FIREWORKS_FROM)
	var fn_from := hhmm(_fountain_show_from())
	return [
		{"kind": "fireworks", "on": bool(on.fireworks), "label": tr("Watch the fireworks") if on.fireworks else tr("Fireworks at %s") % fw_from},
		{"kind": "fountain", "on": bool(on.fountain), "label": tr("Watch the fountain show") if on.fountain else tr("Fountain show at %s") % fn_from},
	]


static func _fountain_show_from() -> float:
	for p: Array in Clock.FOUNTAIN_PROGRAM:
		if str(p[3]) == "show":
			return float(p[0])
	return 1140.0


func press_show(kind: String) -> void:
	if busy():
		c.hint.emit(tr("Get off first."))
		return
	var on := shows_now()
	if not bool(on.get(kind, false)):
		if kind == "fireworks":
			c.hint.emit(tr("The fireworks start at %s. Tap the moon to jump to the night.") % hhmm(Clock.FIREWORKS_FROM))
		else:
			c.hint.emit(tr("The fountain show starts at %s. Tap the sunset, then Auto, and wait a moment.") % hhmm(_fountain_show_from()))
		return
	var wp := watch_point(kind)
	if wp.is_empty():
		return
	_end_state(false)
	state = "watch"
	watch_kind = kind
	_watch_point = wp
	_watch_arrived = false
	walk_route(wp.stand)
	Sfx.play("tap")
	changed.emit()


## The events node's watch point (world/thousand_events.gd: a walkable spot, the child's heading and a camera that
## frames the show; the fireworks burst 50-61 m up some 150 m away, so the follow camera would not show them).
func watch_point(kind: String) -> Dictionary:
	var e := events()
	return e.watch_point(kind) if e != null else {}


func _watch_frame() -> void:
	if not bool(shows_now().get(watch_kind, false)):
		c.toast.emit(tr("The show is over."))
		_end_state(true)
		return
	if not _watch_arrived and c._walk_target == null:
		var stand: Vector2 = _watch_point.stand
		if c.pos.distance_to(stand) > 2.0:
			return   # stopped short (blocked): the chip still says where; a tap walks on
		_watch_arrived = true
		c.ry = float(_watch_point.ry)
		if c.rig:
			c.rig.t_watch = _watch_point.camera
		changed.emit()


# ------------------------------------------------------------- the controller's questions

## The actions the action button offers here, best first (the controller shows the first, the second as its alt).
func contexts() -> Array:
	var out: Array = []
	var tr_node := transit()
	if state == "bus":
		if tr_node and str(tr_node.vehicle(bus_id).get("status", "")) == "dwelling":
			out.append({"type": "tt_bus_off", "label": "Get off", "icon": "stand"})
		return out
	if state == "wheel":
		if can_get_off_wheel():
			out.append({"type": "tt_wheel_off", "label": "Get off", "icon": "stand"})
		return out
	if state == "wheel_wait":
		return out
	var stop := stop_here()
	if stop != "":
		var vid := bus_at(stop)
		if vid != "":
			out.append({"type": "tt_board", "id": vid, "label": "Get on the bus", "icon": "bus"})
		elif not (state == "wait_bus" and stop_id == stop):
			out.append({"type": "tt_wait", "id": stop, "label": "Wait for the bus", "icon": "bus"})
	if at_wheel():
		out.append({"type": "tt_wheel", "label": "Ride the wheel", "icon": "wheel"})
	return out


## A stall's counter here, as an action ({} for none; after a door's "Who's here?" in the controller's order).
func stall_context() -> Dictionary:
	if busy() or state == "wheel_wait":
		return {}
	var stall := stall_here()
	if stall.is_empty():
		return {}
	return {"type": "tt_snack", "id": stall.id, "label": "Buy a snack", "icon": "snack", "stall": stall}


## A resident within HELLO_REACH, as an action ({} for none).
func hello_context() -> Dictionary:
	var pp := people()
	var kid := _kid()
	if pp == null or kid == null or busy():
		return {}
	var id: int = pp.nearest(kid.global_position, HELLO_REACH)
	if id < 0:
		return {}
	return {"type": "tt_hello", "id": str(id), "label": "Say hello", "icon": "wave"}


## Runs one of this node's actions; false when `ctx` is not one of them.
func do(ctx: Dictionary) -> bool:
	match str(ctx.get("type", "")):
		"tt_hello":
			meet(int(str(ctx.get("id", "-1"))))
		"tt_wait":
			start_wait(str(ctx.get("id", "")))
		"tt_board":
			board(str(ctx.get("id", "")))
		"tt_bus_off":
			get_off()
		"tt_wheel":
			start_wheel()
		"tt_wheel_off":
			get_off_wheel()
		"tt_snack":
			buy_snack(ctx.get("stall", stall_here()))
		_:
			return false
	return true


## The chip under the top bar: {"text", "buttons": [[label, action]]}; {} when nothing runs.
func chip() -> Dictionary:
	var who_name := resident_name(follow_id) if follow_id >= 0 else ""
	match state:
		"follow":
			var info: Dictionary = people().info(follow_id, locale()) if people() else {}
			var to := str(info.get("to", ""))
			var eta := float(info.get("eta_minute", minute()))
			var mins := maxi(1, int(ceil(eta - minute())))
			var text := tr("Following %s") % who_name
			if to != "" and to != str(info.get("from", "")) and str(info.get("trip", "")) != "outing":
				text += " · " + tr("to %s") % place_text(to) + " · " + tr("about %d min") % mins
			else:
				text += " · " + tr("out for a walk")
			return {"text": text, "buttons": [["Stop", "end"]]}
		"follow_inside":
			return {"text": tr("%s went into %s.") % [who_name, place_text(follow_place)],
				"buttons": [["Who's here?", "inspect"], ["Stop", "end"]]}
		"wait_bus", "bus":
			var b := _bus_chip()
			return {"text": b[0], "buttons": b[1]}
		"wheel_wait":
			return {"text": tr("The next cabin is coming…"), "buttons": [["Stop", "end"]]}
		"wheel":
			var pct := clampi(int(turned / TAU * 100.0), 0, 100)
			return {"text": tr("On the ferris wheel · %d%% of a turn") % pct,
				"buttons": [["Get off", "wheel_off"]] if can_get_off_wheel() else []}
		"watch":
			var t := tr("Watching the fireworks") if watch_kind == "fireworks" else tr("Watching the fountain show")
			if not _watch_arrived:
				t = tr("Going to watch the fireworks") if watch_kind == "fireworks" else tr("Going to watch the fountain show")
			return {"text": t, "buttons": [["Stop", "end"]]}
	return {}


func chip_action(action: String) -> void:
	match action:
		"end":
			Sfx.play("tap")
			_end_state(true)
		"inspect":
			var place := follow_place
			Sfx.play("tap")
			if place != "":
				c.open_panel.emit("thousand_inspect", {"id": place})
		"bus_board":
			var vid := bus_at(stop_id)
			if vid != "":
				board(vid)
		"bus_off":
			get_off()
		"wheel_off":
			get_off_wheel()


## B on a controller: closes the card, or ends following, waiting or watching. True when it did something.
func back() -> bool:
	if card_open:
		close_card()
		return true
	if state in ["follow", "follow_inside", "wait_bus", "watch", "wheel_wait"]:
		_end_state(true)
		return true
	if selected >= 0 and state == "":
		selected = -1   # a resident picked in "Who's here?": the marker goes
		changed.emit()
		return true
	return false


## The child walked by itself (the stick, the keys, a tap on the ground): following, waiting and watching end.
func manual_walk() -> void:
	if state in ["follow", "follow_inside", "wait_bus", "watch", "wheel_wait"]:
		_end_state(true)


## Ends whatever runs, cleanly: off the bus or the wheel, the camera back behind the child, no marker, no card.
func end_all() -> void:
	_end_state(true)
	card_open = false
	selected = -1
	snack_kind = ""
	snack_until = 0.0
	_remove_snack()
	_update_marks(0.0)
	changed.emit()


func _end_state(notify: bool) -> void:
	var was := state
	if was == "bus":
		var tr_node := transit()
		if tr_node:
			tr_node.alight(rider_key(), true)
		bus_id = ""
		if c.rig and _saved_dist > 0.0:
			c.rig.t_dist = _saved_dist
		_saved_dist = -1.0
		var kid := _kid()
		if kid:
			kid.anim = "idle"
	if was in ["wheel", "wheel_wait"]:
		if was == "wheel":
			c.pos = wheel_board_point() if tw() else c.pos
		cabin = -1
		var kid2 := _kid()
		if kid2:
			kid2.anim = "idle"
	if c and c.rig:
		c.rig.t_watch = null
	if was in ["follow", "follow_inside", "wait_bus", "watch", "wheel_wait"]:
		c._walk_target = null
		c._city_route = []
		c._pending_ctx = {}
	if was in ["follow", "follow_inside"] and not card_open:
		selected = -1
	state = ""
	follow_id = -1
	follow_place = ""
	stop_id = ""
	watch_kind = ""
	_watch_point = {}
	_watch_arrived = false
	_clear_route()
	if notify and was != "":
		changed.emit()


# ------------------------------------------------------------- per frame

## Every physics frame in Thousand Town (before the controller walks or places the child).
func frame(delta: float, kid: Node3D) -> void:
	match state:
		"follow", "follow_inside":
			_follow_frame(delta)
		"bus":
			_bus_frame(kid)
		"wheel", "wheel_wait":
			_wheel_frame(kid, delta)
		"watch":
			_watch_frame()
	if snack_kind != "" and not has_snack():
		snack_kind = ""
		_remove_snack()
		changed.emit()
	if card_open and selected >= 0 and people() and people().info(selected, "en").is_empty():
		close_card()
	_update_marks(delta)


# ------------------------------------------------------------- the marker and the route on the ground

const MARK_COLOR := Color("#ffc928")
const ROUTE_COLOR := Color("#ffd84a")


func _ensure_marks() -> bool:
	var w := tw()
	if w == null:
		return false
	if _marks != null and is_instance_valid(_marks) and _marks.get_parent() == w:
		return true
	_marks = Node3D.new()
	_marks.name = "PlayMarks"
	w.add_child(_marks)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = MARK_COLOR
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color("#3b2a14")
	_marker = Node3D.new()
	_marker.name = "ResidentMarker"
	_marks.add_child(_marker)
	var cone := MeshInstance3D.new()
	cone.mesh = _cyl(0.3, 0.0, 0.5)
	cone.material_override = glow
	cone.position = Vector3(0, 0.25, 0)
	_marker.add_child(cone)
	var rim := MeshInstance3D.new()
	rim.mesh = _cyl(0.36, 0.36, 0.06)
	rim.material_override = edge
	rim.position = Vector3(0, 0.52, 0)
	_marker.add_child(rim)
	_ring = MeshInstance3D.new()
	_ring.name = "ResidentRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.66
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = glow
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_marks.add_child(_ring)
	_route_mesh = ImmediateMesh.new()
	_route = MeshInstance3D.new()
	_route.name = "FollowRoute"
	_route.mesh = _route_mesh
	_route_mat = StandardMaterial3D.new()
	_route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_route_mat.albedo_color = ROUTE_COLOR
	_route_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # seen from above whatever the winding
	_route.material_override = _route_mat
	_route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marks.add_child(_route)
	return true


var _bob := 0.0


func _update_marks(delta: float) -> void:
	if not _ensure_marks():
		return
	var pp := people()
	var show := selected >= 0 and pp != null
	var p := Vector3.INF
	var h := 1.7
	if show:
		p = pp.position_of(selected)
		var info: Dictionary = pp.info(selected, "en")
		h = float(info.get("height_m", 1.7))
		if str(info.get("mode", "")) == "inside":
			h = 2.4   # over the door
		show = p != Vector3.INF
	_marker.visible = show
	_ring.visible = show
	if show:
		_bob += delta
		_marker.position = p + Vector3(0.0, h + 0.35 + sin(_bob * 3.0) * 0.08, 0.0)
		_marker.rotation.y = _bob * 1.5
		_ring.position = p + Vector3(0.0, 0.06, 0.0)


## The rest of the resident's trip from where they are now: dashes 0.4 m wide just above the ground.
func _draw_route(route: PackedVector3Array, at: Vector3) -> void:
	if not _ensure_marks():
		return
	_route_mesh.clear_surfaces()
	if route.size() < 2 or at == Vector3.INF:
		return
	# the segment the resident is on
	var start := 0
	var bd := INF
	for k in route.size() - 1:
		var q := Geometry3D.get_closest_point_to_segment(at, route[k], route[k + 1])
		var d := q.distance_to(at)
		if d < bd:
			bd = d
			start = k
	var pts := PackedVector3Array([at])
	for k in range(start + 1, route.size()):
		pts.append(route[k])
	_route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var dash := 1.0
	var gap := 0.55
	var carry := 0.0
	var drawn := 0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := b - a
		var length := Vector2(seg.x, seg.z).length()
		if length < 0.01:
			continue
		var dir := Vector3(seg.x, 0.0, seg.z) / length
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.2
		var s := carry
		while s < length:
			var e := minf(s + dash, length)
			var p0 := a + seg * (s / length) + Vector3(0, 0.07, 0)
			var p1 := a + seg * (e / length) + Vector3(0, 0.07, 0)
			for v: Vector3 in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
				_route_mesh.surface_add_vertex(v)
			drawn += 1
			s += dash + gap
		carry = s - length
	if drawn == 0:
		_route_mesh.surface_add_vertex(at)
		_route_mesh.surface_add_vertex(at)
		_route_mesh.surface_add_vertex(at)
	_route_mesh.surface_end()
	_route.set_meta("dashes", drawn)
	_route.set_meta("points", pts.size())


func _clear_route() -> void:
	if _route_mesh:
		_route_mesh.clear_surfaces()
		_route.set_meta("dashes", 0)
