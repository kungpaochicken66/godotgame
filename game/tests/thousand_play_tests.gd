## Thousand Town's interactions through the real game (design/thousand-town.md, "Interactions"): TownWorld, the
## play controller, the camera rig, the HUD and the controller layer (pad_input.gd) ride the tram to Thousand Town
## and use world/thousand_play.gd with the real world, residents (art/thousand_people.gd), transit
## (world/thousand_transit.gd) and simulation. The town's clock is set by the test through the world's `clock`
## Callable (the authority's own clock is tested in thousand_tests.gd); the Night button goes through the authority.
##   I1 meet a resident (Say hello and a tap), the card in English and Chinese, the marker
##   I2 follow a commute: the walk, the route on the ground, the chip, into a building, aboard, from the panel
##   I3 Who's here? at every door, open/closed and counts from the sample, a picked resident's place
##   I4 the bus: waiting with a countdown, boarding, riding seated, the next stop, getting off, the end of the lap,
##      out of hours, a held clock, the station bays
##   I5 the ferris wheel: closed (when it opens), one turn, Get off only at the bottom
##   I6 the night market: closed before 18:00, a snack and a shopkeeper who is there now
##   I7 the shows: when they are next on, Night through the authority, watching, the end of the show; and the
##      time-dependent town (the market's lanterns, the buses after 22:30)
##   the TV controller (TvMode forced, PadInput): targets, A on the action button, B; the TV's figure budget
##   Ride home from every state: the state ends and the town HUD is exactly as before
## Runs headless (logic, layout and camera; no pixels):
##   scripts/godot.sh --headless --path game -s res://tests/thousand_play_tests.gd
## or rendered (xvfb-run ... --resolution 1366x1024); waits stretch by SLOW, as in thousand_tests.gd.
extends "res://tests/puzzle_ride_tests.gd"

const Places := preload("res://scripts/core/places.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")
const PadInput := preload("res://scripts/ui/pad_input.gd")
const Data := preload("res://scripts/core/thousand_sim_data.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const Inspect := preload("res://scripts/core/thousand_inspect.gd")
const EVENTS_PATH := "res://scripts/world/thousand_events.gd"
const SLOW := 8.0

var TownWorld: GDScript
var Thousand: Node
var holder: Node
var world: Node3D
var rig: Node3D
var c: Node
var hud: Control
var pad: Node
var fm: Node
var tp: Node
var tw: Node3D
var pp: Node3D
var tr_node: Node3D
var _tv_before := -1
var _hints: Array = []
var _toasts: Array = []
## The test's town clock: {day, minute, mode, speed}; while `_run` the minute advances in real time at `speed`.
var _clock := {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}
var _run := false
var _run_from := 0.0
var _town_buttons: Array = []


class FakeMain extends Node:
	var menus: Control = null
	var hud: Control
	var controller: Node
	var rig: Node3D


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	Thousand = root.get_node("Thousand")
	_tv_before = TvMode.forced
	TvMode.forced = 0
	TownWorld = load("res://scripts/world/town_world.gd")
	await process_frame
	for t in ["test_arrival", "test_meet", "test_follow", "test_inspect", "test_bus", "test_wheel", "test_market",
			"test_shows", "test_tv", "test_return_home"]:
		_current = t
		await call(t)
	TvMode.forced = _tv_before
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nTHOUSAND PLAY TESTS: %d checks, %d failures" % [_checks, _failures])
	if holder:
		holder.queue_free()
	await process_frame
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _until(cond: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await physics_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout * SLOW:
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## The clock the world draws (and the residents, the transit and the interactions use).
func _view_clock() -> Dictionary:
	var out := _clock.duplicate()
	if _run:
		var m: float = float(_clock["minute"]) + (Time.get_ticks_msec() / 1000.0 - _run_from) * float(_clock["speed"])
		out["minute"] = m
	return out


## Sets the town's time (held) and lets the world, the residents and the transit catch up.
func _at(day: int, minute: float, mode := "auto") -> void:
	_run = false
	_clock = {"day": day, "minute": minute, "mode": mode, "speed": 1}
	await _frames(3)
	await _until(func(): return tw.plans() != null and tw.plans().day == day and absf(float(pp._minute) - fposmod(minute, 1440.0)) < 0.01, 3.0)
	await _frames(2)
	hud._refresh_thousand_play()   # the HUD refreshes the chip four times a second; headless frames are faster


## Lets the clock run in real time at 1x from where it is.
func _run_clock() -> void:
	_clock["minute"] = float(_view_clock()["minute"])
	_run_from = Time.get_ticks_msec() / 1000.0
	_run = true


func _stop() -> void:
	_clock["minute"] = float(_view_clock()["minute"])
	_run = false


func _stand(p: Vector2, ry := PI / 2.0) -> void:
	c._walk_target = null
	c._city_route = []
	c._pending_ctx = {}
	c.pos = tw.resolve_walk(p)
	c.ry = ry
	c._place_kid()
	rig.t_yaw = ry + PI
	rig.snap()
	await _frames(3)


func _build_game() -> void:
	holder = Node.new()
	holder.name = "Main"
	root.add_child(holder)
	var thumbs: Node = load("res://scripts/ui/thumbnails.gd").new()
	holder.add_child(thumbs)
	world = TownWorld.new()
	world.name = "World"
	holder.add_child(world)
	rig = load("res://scripts/world/camera_rig.gd").new()
	holder.add_child(rig)
	c = load("res://scripts/world/play_controller.gd").new()
	holder.add_child(c)
	c.setup(world, rig)
	var ui := CanvasLayer.new()
	holder.add_child(ui)
	hud = load("res://scripts/ui/hud.gd").new()
	ui.add_child(hud)
	hud.bind(c, thumbs)
	c.hint.connect(func(t): _hints.append(t))
	c.toast.connect(func(t): _toasts.append(t))
	pad = PadInput.new()
	fm = FakeMain.new()
	fm.hud = hud
	fm.controller = c
	fm.rig = rig
	holder.add_child(fm)
	holder.add_child(pad)
	pad.bind(fm)
	tp = c.thousand_play


## The HUD's visible buttons (paths), outside dialogs and the floating name tags: "the town HUD" to compare.
func _visible_buttons() -> Array:
	var out: Array = []
	for b in hud.find_children("*", "BaseButton", true, false):
		if not (b as Control).is_visible_in_tree() or hud._overlay.is_ancestor_of(b) or hud._tag_layer.is_ancestor_of(b):
			continue
		out.append(str(hud.get_path_to(b)))
	out.sort()
	return out


func _chip_has(action: String) -> bool:
	for b in hud._tt_chip_btns.get_children():
		if not b.is_queued_for_deletion() and str(b.get_meta("action", "")) == action:
			return true
	return false


func _hint_has(text: String) -> bool:
	for h in _hints:
		if str(h).contains(text):
			return true
	return false


func _toast_has(text: String) -> bool:
	for t in _toasts:
		if str(t).contains(text):
			return true
	return false


# ------------------------------------------------------------- arrival: built behind the journey card

func test_arrival() -> void:
	await process_frame
	_build_game()
	await _fresh_town("user://test_thousand_play.json")
	await process_frame
	ok(c.space == "town" and world.local_kid() != null, "a solo game in town")
	c.pos = TownModel.tram_stop_boarding(Session.model)
	c._place_kid()
	ok(await _until(func(): return c._ctx.get("type", "") == "tram" and c._ctx.has("alt3"), 3.0), "the tram stop offers Thousand Town")
	await _frames(4)
	_town_buttons = _visible_buttons()
	ok(world.thousand_world == null, "nothing of Thousand Town is built before the journey")
	var seen := {}
	world.child_entered_tree.connect(func(n: Node):
		if n.name == "Thousand" and seen.is_empty():
			seen["view"] = world.view_space
			seen["card"] = hud._journey_card != null and hud._journey_card.visible and hud._journey_card.modulate.a > 0.99)
	hud._context_alt3_btn.pressed.emit()
	ok(c.journey_to == "thousand", "the journey starts")
	ok(await _until(func(): return world.thousand_world != null, 6.0), "the town is built during the journey")
	ok(seen.get("view", "") == "town" and bool(seen.get("card", false)), "behind the fully shown journey card, the town still in view underneath (%s)" % str(seen))
	ok(world.thousand_people != null and world.thousand_transit != null, "with its residents and its transit")
	ok(world.thousand_people.get_parent() == world.thousand_world and world.thousand_transit.get_parent() == world.thousand_world, "both under the Thousand world")
	ok(world.thousand_people._plans != null and world.thousand_people._plans == world.thousand_world.plans(), "the residents share the world's plans")
	ok(world.thousand_people.counts()["drawn"] > 0, "and are placed already (warmed) (%s)" % str(world.thousand_people.counts()))
	ok(await _until(func(): return c.space == "thousand" and c.journey_to == "", 8.0), "the child arrives")
	tw = world.thousand_world
	pp = world.thousand_people
	tr_node = world.thousand_transit
	tw.clock = _view_clock
	for kind in ["bus", "taxi"]:
		var tpl: Node3D = tw.vehicle_template(kind)
		ok(tpl == null or not tpl.visible, "the world's %s template is hidden (the transit draws them)" % kind)
	eq(pp.max_figures, 160, "the iPad's budget of figures")
	await _at(1, 480.0)
	ok(absf(float(pp._minute) - 480.0) < 0.01 and absf(float(tr_node.minute) - 480.0) < 0.01 and absf(float(tw.light.get("minute", 0.0)) - 480.0) < 0.01,
		"the light, the residents and the transit draw the same time")
	var bus0: Vector3 = tr_node.vehicle("station-bus-0").pos
	await _at(1, 482.0)
	ok(tr_node.vehicle("station-bus-0").pos.distance_to(bus0) > 1.0, "the buses move with the clock")
	ok(pp.counts()["drawn"] > 0, "residents are drawn at 08:02 (%d)" % pp.counts()["drawn"])
	ok(hud._tt_shows["fireworks"].visible and hud._tt_shows["fountain"].visible, "the show buttons are there in Thousand Town")
	ok(not hud._tt_chip.visible and not hud._tt_card.visible, "no chip and no card yet")


# ------------------------------------------------------------- I1 meeting a resident

## A drawn resident walking a long trip to a building with a door, near the child's reach: [id, info].
func _walker(min_remaining := 40.0) -> Array:
	var best := []
	var bd := INF
	for id: int in pp.drawn_ids():
		var info: Dictionary = pp.info(id, "en")
		if str(info.get("mode", "")) != "walk" or str(info.get("trip", "")) == "outing" or info.has("stops"):
			continue
		if float(info.get("remaining_m", 0.0)) < min_remaining:
			continue
		var to := str(info.get("to", ""))
		if to == "" or to == "street" or tw.door_point(to) == Vector2.INF:
			continue
		var p: Vector3 = pp.position_of(id)
		var d := Vector2(p.x, p.z).distance_to(c.pos)
		if d < bd:
			bd = d
			best = [id, info]
	return best


func test_meet() -> void:
	await _at(1, 470.0)
	var w := _walker()
	ok(not w.is_empty(), "a commuter walks to work at 07:50")
	if w.is_empty():
		return
	var id: int = w[0]
	var p: Vector3 = pp.position_of(id)
	# stand beside them: Say hello is offered (first, or beside the door's Who's here?)
	await _stand(Vector2(p.x, p.z) + Vector2(1.2, 0.0), -PI / 2.0)
	await _frames(2)
	var near: int = pp.nearest(world.local_kid().global_position, 3.0)
	ok(near >= 0, "a resident within 3 m of the child")
	var hello: Dictionary = {}
	for k in ["", "alt"]:
		var cc: Dictionary = c._ctx if k == "" else c._ctx.get("alt", {})
		if str(cc.get("type", "")) == "tt_hello":
			hello = cc
	ok(not hello.is_empty(), "the action button offers Say hello (%s)" % str(c._ctx))
	if hello.is_empty():
		return
	ok(hud._context_btn.text == "Say hello" or hud._context_alt_btn.text == "Say hello", "the HUD shows it")
	var who: int = int(hello["id"])
	c.do_context(hello)
	await _frames(2)
	ok(tp.card_open and tp.selected == who, "the card opens for that resident")
	ok(hud._tt_card.visible, "the HUD shows the card")
	var info: Dictionary = pp.info(who, "en")
	eq(hud._tt_card_name.text, tw.sim.name_of(who, "en"), "the card names them")
	var role: String = str(Inspect.ROLE_IDS.get(str(info.role), str(info.role)))
	ok(hud._tt_card_who.text.contains(tr(load("res://scripts/ui/thousand_panel.gd").role_name(role))) and hud._tt_card_who.text.contains(str(int(info.age))),
		"with role and age (%s)" % hud._tt_card_who.text)
	ok(hud._tt_card_now.text != "", "what they are doing now (%s)" % hud._tt_card_now.text)
	ok(world.local_kid().emote_kind == "wave", "the child waves")
	var rp: Vector3 = pp.position_of(who)
	var face := Vector2(sin(c.ry), cos(c.ry))
	ok(face.dot((Vector2(rp.x, rp.z) - c.pos).normalized()) > 0.95, "the child turned toward them")
	var mk: Node3D = tp._marker
	ok(mk != null and mk.visible and Vector2(mk.global_position.x, mk.global_position.z).distance_to(Vector2(rp.x, rp.z)) < 0.6 and mk.global_position.y > rp.y + 1.5,
		"a marker floats over them (%s, resident %s)" % [mk.global_position if mk else Vector3.ZERO, rp])
	# the card in the reader's language
	root.get_node("I18n").set_locale("zh-CN")
	await _frames(1)
	hud._refresh_thousand_play()
	eq(hud._tt_card_name.text, tw.sim.name_of(who, TranslationServer.get_locale()), "in Chinese, the name the sim gives in Chinese")
	ok(hud._tt_card_name.text != tw.sim.name_of(who, "en"), "(not the English one: %s)" % hud._tt_card_name.text)
	root.get_node("I18n").set_locale("en")
	await _frames(1)
	# Close
	(hud._tt_card.find_child("CloseCard", true, false) as Button).pressed.emit()
	await _frames(1)
	ok(not tp.card_open and not hud._tt_card.visible and not tp._marker.visible, "Close: card and marker go")
	# a tap on a figure: the camera looks at a walker, the tap lands on their chest
	await _at(1, 470.0)
	var w2 := _walker()
	if w2.is_empty():
		ok(false, "a walker to tap")
		return
	var id2: int = w2[0]
	var p2: Vector3 = pp.position_of(id2)
	await _stand(Vector2(p2.x, p2.z) - Vector2(0.0, 5.0), 0.0)
	rig.t_yaw = PI   # the camera south of the child, looking north at the walker
	rig._t_manual = 99.0
	rig.snap()
	await _frames(1)
	p2 = pp.position_of(id2)
	var screen: Vector2 = rig.camera.unproject_position(p2 + Vector3(0, 1.1, 0))
	var picked: int = pp.pick_screen(rig.camera, screen)
	c._thousand_tap(screen)
	await _frames(1)
	ok(picked >= 0 and tp.selected == picked and tp.card_open, "a tap on a figure meets that resident (%d, picked %d, tapped %s)" % [tp.selected, picked, screen])
	rig._t_manual = 0.0
	tp.close_card()


# ------------------------------------------------------------- I2 following a commute

func test_follow() -> void:
	await _at(1, 472.0)
	var w := _walker(70.0)
	ok(not w.is_empty(), "a commuter with a long walk ahead")
	if w.is_empty():
		return
	var id: int = w[0]
	var info: Dictionary = w[1]
	var p: Vector3 = pp.position_of(id)
	await _stand(Vector2(p.x, p.z) + Vector2(0.0, 2.0))
	tp.meet(id)
	await _frames(2)
	ok(hud._tt_card_follow.visible, "the card offers Follow while they walk")
	hud._tt_card_follow.pressed.emit()
	await _frames(2)
	eq(tp.state, "follow", "following")
	eq(tp.follow_id, id, "that resident")
	ok(not hud._tt_card.visible and hud._tt_chip.visible, "the card gives way to the chip")
	var to_name: String = tr(tw.NAMES.get(str(info.to), str(info.to)))
	ok(hud._tt_chip_label.text.contains(tw.sim.name_of(id, "en")) and hud._tt_chip_label.text.contains(to_name) and hud._tt_chip_label.text.contains("min"),
		"the chip: Following NAME · to PLACE · about N min (%s)" % hud._tt_chip_label.text)
	ok(hud._tt_chip_btns.get_child_count() == 1 and str(hud._tt_chip_btns.get_child(0).get_meta("action", "")) == "end", "with Stop")
	_run_clock()
	var start: Vector2 = c.pos
	await create_timer(4.0).timeout
	var rp: Vector3 = pp.position_of(id)
	var gap: float = c.pos.distance_to(Vector2(rp.x, rp.z))
	ok(c.pos.distance_to(start) > 2.0, "the child walks after them (%.1f m)" % c.pos.distance_to(start))
	ok(gap < 9.0, "and keeps up (%.1f m behind)" % gap)
	ok(int(tp._route.get_meta("dashes", 0)) > 3, "the rest of their trip is drawn on the ground (%d dashes)" % int(tp._route.get_meta("dashes", 0)))
	ok(tp._marker.visible, "the marker stays over them")
	_stop()
	# they arrive: into the building
	var eta := float(pp.info(id, "en").get("eta_minute", 0.0))
	await _at(1, eta + 0.4)
	ok(await _until(func(): return tp.state == "follow_inside", 2.0), "they went inside: the chip says so (%s, mode %s)" % [tp.state, pp.info(id, "en").get("mode", "")])
	ok(hud._tt_chip_label.text.contains(to_name), "naming the building (%s)" % hud._tt_chip_label.text)
	var insp: Button = hud._tt_chip_btns.find_child("Chip_inspect", true, false)
	ok(insp != null, "and offers its Who's here?")
	if insp:
		insp.pressed.emit()
		await _frames(2)
		var panel: Node = hud.thousand_inspect_panel()
		ok(panel != null and str(panel.get_meta("building", "")) == str(info.to), "Who's here? for that building")
		if panel:
			var ids: Array = (panel.data.get("here", []) as Array).map(func(r): return int(r.get("index", -1)))
			ok(ids.has(id) or int(panel.data.get("count", 0)) > Inspect.LIST_MAX, "the followed resident is in its list")
			hud._close_overlay()
			await _frames(1)
	(hud._tt_chip_btns.find_child("Chip_end", true, false) as Button).pressed.emit()
	await _frames(2)
	ok(tp.state == "" and not hud._tt_chip.visible and not tp._marker.visible, "Stop ends following")
	# aboard: a resident on a bus ends the follow
	await _at(1, 500.0)
	var aboard := -1
	for i in pp.sim.count:
		if str(pp.info(i, "en").get("mode", "")) == "aboard":
			aboard = i
			break
	if aboard >= 0:
		tp.state = "follow"
		tp.follow_id = aboard
		tp.selected = aboard
		_toasts.clear()
		await _frames(2)
		ok(tp.state == "" and _toast_has("got on the bus"), "they got on a bus: the chip says so and the follow ends (%s)" % str(_toasts))
	else:
		ok(true, "(no resident aboard at 08:20 to check)")
	# from "Who's here?": a resident who lives in a building and walks the street now (among the first LIST_MAX
	# of its residents, the ones the panel lists)
	await _at(1, 472.0)
	var id2 := -1
	for i: int in pp.drawn_ids():
		var inf: Dictionary = pp.info(i, "en")
		if str(inf.get("mode", "")) in ["walk", "jog"] and not inf.has("stops"):
			var homes: PackedInt32Array = tw.sim.homes[tw.sim.home[i]]
			if Array(homes).slice(0, Inspect.LIST_MAX).has(i):
				id2 = i
				break
	if id2 < 0:
		ok(false, "a walker for the panel")
		return
	var home := str(Data.BUILDINGS[tw.sim.home[id2]]["id"])
	hud.open_thousand_inspect(home)
	await _frames(1)
	var panel2: Node = hud.thousand_inspect_panel()
	ok(panel2 != null, "the inspect panel of their home (%s)" % home)
	if panel2 == null:
		return
	panel2.show_tab("lives")
	var btn: Button = panel2.find_child("Resident_" + str(tw.sim.ids[id2]), true, false)
	ok(btn != null, "they are listed under Lives here")
	if btn == null:
		hud._close_overlay()
		return
	btn.pressed.emit()
	await _frames(1)
	eq(tp.selected, id2, "picking them puts the marker on them")
	var fb: Button = panel2.find_child("FollowResident", true, false)
	ok(fb != null, "Follow is offered for a resident out on the street")
	if fb:
		fb.pressed.emit()
		await _frames(2)
		ok(tp.state == "follow" and tp.follow_id == id2 and hud.thousand_inspect_panel() == null, "the panel closes and the child follows them")
	tp.end_all()
	await _frames(1)


# ------------------------------------------------------------- I3 Who's here?

func test_inspect() -> void:
	await _at(1, 600.0)
	var bad: Array = []
	for s: Dictionary in tw.sites():
		if not s.door is Vector2:
			continue
		var at: Vector2 = s.door
		if tw.resolve_walk(at).distance_to(at) > 0.05 or str(tw.door_near(at, c.THOUSAND_DOOR_REACH).get("id", "")) != str(s.id):
			bad.append(s.id)
	eq(bad, [], "every door is walkable and offers its own building")
	# a door through the action button, against the sample
	for spec in [["c-primary", 600.0], ["c-primary", 1380.0], ["c-mall", 720.0], ["h-slab", 1200.0]]:
		await _at(1, float(spec[1]))
		var id: String = spec[0]
		await _stand(tw.door_point(id))
		await _frames(2)
		ok(c._ctx.get("type", "") == "thousand_inspect" and c._ctx.get("id", "") == id, "%s: Who's here? at its door" % id)
		c.do_context()
		await _frames(2)
		var panel: Node = hud.thousand_inspect_panel()
		var row: Dictionary = tp.site_row(id)
		ok(panel != null and not row.is_empty(), "%s: the panel opens" % id)
		if panel and not row.is_empty():
			var status: String = panel.get_node("Status").text
			ok(status.begins_with(tr("Open") if bool(row.open) else tr("Closed")), "%s at %s: %s as the sample says (%s)" % [id, Clock.format_minute(spec[1]), "open" if row.open else "closed", status])
			ok(status.contains(str(int(row.count))), "%s: %d here now (%s)" % [id, int(row.count), status])
			eq((panel.data.get("here", []) as Array).size(), mini(int(row.count), Inspect.LIST_MAX), "%s: the list" % id)
			if int(row.count) > 0:
				var first: Button = panel.find_child("List", true, false).get_child(0)
				first.pressed.emit()
				await _frames(1)
				var now: Label = panel.find_child("Now", true, false)
				ok(now != null and now.text.contains(tr(tw.NAMES.get(id, id))), "%s: a picked resident inside says where they are (%s)" % [id, now.text if now else ""])
				var door: Vector2 = tw.door_point(id)
				ok(tp.selected >= 0 and tp._marker.visible and Vector2(tp._marker.global_position.x, tp._marker.global_position.z).distance_to(door) < 8.0,
					"%s: and the marker shows the building" % id)
		hud._close_overlay()
		await _frames(1)
		tp.back()


# ------------------------------------------------------------- I4 the bus

func _bus_at_stop(stop: String) -> String:
	for v: Dictionary in tr_node.vehicles():
		if str(v.kind) == "bus" and str(v.stop) == stop and str(v.status) == "dwelling":
			return str(v.id)
	return ""


func test_bus() -> void:
	await _at(1, 480.0)
	var st: Dictionary = tp.stands()
	ok(st.has("bus-stop-1") and st.has("bus-stop-3") and st.has("bus-stop-4") and st.has("station"), "the served stops and the station's bays have a waiting point (%s)" % str(st.keys()))
	for k in st:
		ok(not tw._blocked(st[k]), "%s's waiting point is walkable" % k)
	# the lap's first stop (s1) and the next (s2) for the next bus out of the bays
	var lap: Array = []
	var bus_out: String = str(tr_node.next_departures("station", 1)[0].vehicle)
	for sid in ["bus-stop-1", "bus-stop-3", "bus-stop-4"]:
		for e: Dictionary in tr_node.timetable(sid, 1):
			if str(e.vehicle) == bus_out and float(e.arrive_minute) > 480.0:
				lap.append([float(e.arrive_minute), sid])
				break
	lap.sort()
	var s1: String = lap[0][1]
	ok(lap.size() == 3, "the bus calls at three stops a lap (%s)" % str(lap))
	# waiting at the first stop with the countdown
	await _stand(st[s1] + Vector2(1.5, 0.0))
	ok(c._ctx.get("type", "") == "tt_wait", "Wait for the bus at the stop (%s)" % str(c._ctx))
	c.do_context()
	await _frames(2)
	eq(tp.state, "wait_bus", "waiting")
	ok(await _until(func(): return c.pos.distance_to(st[s1]) < 0.3, 4.0), "the child walks to the stop")
	var dep: Dictionary = tr_node.next_departures(s1, 1)[0]
	var secs := int(ceil(float(dep.arrive_minute) - 480.0))
	ok(hud._tt_chip.visible and hud._tt_chip_label.text.contains("%d:%02d" % [floori(secs / 60.0), secs % 60]), "the chip counts down to the next bus (%s, %d s)" % [hud._tt_chip_label.text, secs])
	# the bus comes
	var vid: String = str(dep.vehicle)
	await _at(1, float(dep.arrive_minute) + 0.1)
	ok(_bus_at_stop(s1) == vid, "%s stands at the stop" % vid)
	ok(hud._tt_chip_label.text == "The bus is here!" and hud._tt_chip_btns.find_child("Chip_bus_board", true, false) != null, "the chip says the bus is here, with Get on the bus")
	ok(c._ctx.get("type", "") == "tt_board", "and so does the action button (%s)" % str(c._ctx))
	(hud._tt_chip_btns.find_child("Chip_bus_board", true, false) as Button).pressed.emit()
	await _frames(2)
	eq(tp.state, "bus", "on the bus")
	eq(tr_node.riding(tp.rider_key()), vid, "seated on it (local, no protocol)")
	var kid: Node3D = world.local_kid()
	ok(kid.anim == "sit" and kid.global_position.distance_to(tr_node.vehicle(vid).pos) < 3.5, "the child sits in the bus (%s vs %s)" % [kid.global_position, tr_node.vehicle(vid).pos])
	eq(rig.t_dist, tp.BUS_VIEW, "the camera stands back to keep the bus in view")
	ok(c._ctx.get("type", "") == "tt_bus_off", "Get off while it stands at the stop")
	# it leaves: the child goes with it, the chip names the next stop
	await _at(1, float(dep.depart_minute) + 0.3)
	var nxt: String = tr_node.next_stop(vid)
	eq(nxt, lap[1][1], "the next stop")
	ok(hud._tt_chip_label.text.contains(tp.stop_name(nxt)), "the chip names it (%s)" % hud._tt_chip_label.text)
	ok(c.pos.distance_to(Vector2(tr_node.vehicle(vid).pos.x, tr_node.vehicle(vid).pos.z)) < 3.5, "the child moves with the bus")
	ok(c._ctx.is_empty(), "no Get off between stops")
	# the next stop: Get off
	var arrive := -1.0
	for e: Dictionary in tr_node.timetable(nxt, 1):
		if str(e.vehicle) == vid and float(e.arrive_minute) > float(dep.depart_minute):
			arrive = float(e.arrive_minute)
			break
	ok(arrive > 0.0, "it calls at %s" % nxt)
	await _at(1, arrive + 0.1)
	ok(hud._tt_chip_label.text.contains(tp.stop_name(nxt)) and c._ctx.get("type", "") == "tt_bus_off", "at %s: Get off (%s)" % [nxt, hud._tt_chip_label.text])
	c.do_context()
	await _frames(2)
	ok(tp.state == "" and tr_node.riding(tp.rider_key()) == "", "off the bus")
	var door: Vector3 = tr_node.door_point(vid)
	ok(c.pos.distance_to(Vector2(door.x, door.z)) < 1.5 and world.local_kid().anim != "sit", "standing by its door")
	eq(rig.t_dist, rig.T_DIST, "the camera back at its distance")
	# the end of the lap: at the station everybody gets off
	await _at(1, arrive + 0.1)
	c.pos = tw.resolve_walk(Vector2(door.x, door.z))
	ok(tp.board(vid), "on again")
	var b: Dictionary = {}
	for bb: Dictionary in tr_node._buses:
		if str(bb.id) == vid:
			b = bb
	var lap_end: float = float(tr_node.vehicle(vid).departure) + float(b.lap)
	_toasts.clear()
	await _at(1, lap_end - 2.0)
	eq(tp.state, "bus", "still riding just before the bays")
	await _at(1, lap_end + 2.0)
	ok(tp.state == "" and _toast_has("Everybody off"), "at the bays the lap ends and everybody gets off (%s)" % str(_toasts))
	ok(c.pos.distance_to(st["station"]) < 8.0, "by the station (%s)" % c.pos)
	# out of service hours
	await _at(1, 1410.0)
	await _stand(st["bus-stop-3"])
	c.do_context({"type": "tt_wait", "id": "bus-stop-3"})
	await _frames(2)
	ok(hud._tt_chip_label.text.begins_with("No buses now") and hud._tt_chip_label.text.contains("06:"), "after 22:30: when the first bus comes (%s)" % hud._tt_chip_label.text)
	# a held clock
	await _at(1, 720.0, "day")
	ok(hud._tt_chip_label.text.contains("Auto"), "the clock held: the chip says to press Auto (%s)" % hud._tt_chip_label.text)
	pad._back()
	await _frames(1)
	eq(tp.state, "", "B stops waiting")
	# the station's bays
	await _at(1, 480.0)
	var first: Dictionary = tr_node.next_departures("station", 1)[0]
	await _at(1, float(first.depart_minute) - 0.5)
	await _stand(st["station"])
	ok(c._ctx.get("type", "") == "tt_board" and str(c._ctx.get("id", "")) == str(first.vehicle), "at the bays, the bus about to leave takes riders (%s)" % str(c._ctx))
	# buses after 22:30: back at their bays, closed
	await _at(2, 120.0)
	var closed: int = tr_node.vehicles().filter(func(v): return str(v.kind) == "bus" and str(v.status) == "closed").size()
	eq(closed, 3, "at 02:00 the three buses are closed at their bays")


# ------------------------------------------------------------- I5 the ferris wheel

func _wheel_to_bottom() -> void:
	# the cabin k = 9 is at the bottom when the wheel's clock is a whole turn (thousand_world.animate)
	var now := Time.get_ticks_msec() / 1000.0
	tw.anim_offset = ceilf((now + 1.0) / 180.0) * 180.0 - now - 0.4


## The wheel half-way between two cabins at the bottom (none takes riders for about 7 s).
func _wheel_between() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	tw.anim_offset = ceilf((now + 1.0) / 180.0) * 180.0 - now + 7.5


func test_wheel() -> void:
	await _at(1, 720.0)
	var bp: Vector2 = tp.wheel_board_point()
	ok(bp != Vector2.INF and not tw._blocked(bp), "the wheel's boarding point is walkable (%s)" % bp)
	await _stand(bp)
	ok(c._ctx.get("type", "") == "tt_wheel", "Ride the wheel at the wheel (%s)" % str(c._ctx))
	ok(not bool(tp.site_row("c-amusement").get("open", true)), "the amusement park is closed at 12:00 on a weekday (the sim)")
	_hints.clear()
	c.do_context()
	await _frames(1)
	var opens: float = tp.next_open("c-amusement")
	ok(tp.state == "" and opens > 720.0 and _hint_has("opens at %s" % Clock.format_minute(opens)), "closed: it says when it opens (%s; %s)" % [Clock.format_minute(opens), str(_hints)])
	await _at(1, 1110.0)
	ok(bool(tp.site_row("c-amusement").get("open", false)), "open at 18:30")
	await _stand(bp)
	_wheel_between()
	await _frames(2)
	c.do_context()
	await _frames(1)
	eq(tp.state, "wheel_wait", "waiting for a cabin")
	_wheel_to_bottom()
	ok(await _until(func(): return tp.state == "wheel", 3.0), "a cabin comes down and takes the child")
	await _frames(2)
	var kid: Node3D = world.local_kid()
	var hang: Vector3 = tw.cabin_global(tp.cabin)
	ok(kid.global_position.distance_to(hang - Vector3(0, tp.CABIN_DROP, 0)) < 0.3, "the child stands in the cabin")
	ok(rig.t_watch is Transform3D, "the camera looks out over the town")
	ok(c._ctx.get("type", "") == "tt_wheel_off", "Get off at the bottom")
	tw.anim_offset += 45.0
	await _frames(3)
	ok(kid.global_position.y > 8.0, "a quarter turn later the child is high up (%.1f m)" % kid.global_position.y)
	hud._refresh_thousand_play()
	ok(c._ctx.is_empty() and not _chip_has("wheel_off"), "no getting off up there")
	ok(hud._tt_chip_label.text.contains("%"), "the chip shows the turn (%s)" % hud._tt_chip_label.text)
	ok((-rig.camera.global_basis.z).y < 0.0, "the camera looks out and down")
	_toasts.clear()
	for step in [45.0, 45.0, 44.0, 1.5]:
		tw.anim_offset += step
		await _frames(4)
	ok(await _until(func(): return tp.state == "", 2.0), "after one turn the child gets off at the bottom (%s, turned %.2f)" % [tp.state, tp.turned])
	ok(_toast_has("One whole turn"), "with a word about the view")
	ok(c.pos.distance_to(bp) < 0.5 and rig.t_watch == null, "on the ground at the wheel, the camera behind the child again")
	# Get off at once at the bottom
	_wheel_between()
	await _frames(2)
	c.do_context({"type": "tt_wheel"})
	_wheel_to_bottom()
	ok(await _until(func(): return tp.state == "wheel", 3.0), "in again")
	ok(tp.can_get_off_wheel(), "at the bottom")
	c.do_context()
	await _frames(1)
	eq(tp.state, "", "and off again at the bottom")


# ------------------------------------------------------------- I6 the night market

func test_market() -> void:
	await _at(1, 720.0)
	var stalls: Array = TMap.data().waterfront.stalls
	var st: Dictionary = stalls[5]
	var counter := Vector2(float(st.x) - float(st.side) * (float(st.d) * 0.5 + 0.8), float(st.z))
	await _stand(counter, PI / 2.0 * -float(st.side))
	ok(c._ctx.get("type", "") == "tt_snack" or c._ctx.get("alt", {}).get("type", "") == "tt_snack", "Buy a snack at a stall (%s)" % str(c._ctx))
	ok(not tp.market_open() and not bool(tw.light.get("market_busy", true)), "at 12:00 the market is shut and its lanterns low")
	_hints.clear()
	c.do_context({"type": "tt_snack", "stall": tp.stall_here()})
	await _frames(1)
	ok(_hint_has("opens at 18:00") and not tp.has_snack(), "closed: it opens at 18:00")
	await _at(1, 1290.0)
	ok(tp.market_open() and bool(tw.light.get("market_busy", false)), "at 21:30 it is open and its lanterns bright (the time-dependent town)")
	var keepers: Array = tp.market_keepers()
	ok(not keepers.is_empty(), "shopkeepers are there now (%d)" % keepers.size())
	_toasts.clear()
	c.do_context({"type": "tt_snack", "stall": tp.stall_here()})
	await _frames(2)
	ok(tp.has_snack(), "the child has a snack")
	var named := false
	for i: int in keepers:
		if _toast_has(tw.sim.name_of(i, "en")):
			named = true
	ok(named, "the toast names a shopkeeper who is there now (%s)" % str(_toasts))
	var snack: Node = world.local_kid().find_child("TTSnack", true, false)
	ok(snack != null and snack.get_parent().name == "Hand", "held in the right hand")
	tp.snack_until = 0.0
	await _frames(2)
	ok(world.local_kid().find_child("TTSnack", true, false) == null, "and eaten after a while")


# ------------------------------------------------------------- I7 the shows

func test_shows() -> void:
	var ev: Node = world.thousand_events
	ok(ev != null and ev.get_parent() == tw and bool(ev.drive) and int(ev.spark_cap) == 600, "the fireworks and fountain node is under the town, driving itself, 600 sparks")
	ok(tp.events() == ev, "the interactions use it")
	await _at(1, 720.0)
	var fw: Button = hud._tt_shows["fireworks"]
	var fn: Button = hud._tt_shows["fountain"]
	hud._refresh_thousand_play()
	ok(fw.text == "Fireworks at 19:00" and fn.text == "Fountain show at 19:00", "at 12:00 the buttons say when (%s / %s)" % [fw.text, fn.text])
	_hints.clear()
	fw.pressed.emit()
	await _frames(1)
	ok(tp.state == "" and _hint_has("19:00") and _hint_has("moon"), "pressed: when, and the moon jumps to the night (%s)" % str(_hints))
	# Night through the authority
	tw.clock = Callable()
	(hud._thousand_time_btns["night"] as Button).pressed.emit()
	ok(await _until(func(): return float(tw.view_time().minute) == 1290.0, 3.0), "Night: 21:30")
	await _frames(3)
	hud._refresh_thousand_play()
	ok(fw.text == "Watch the fireworks", "the fireworks are on (%s)" % fw.text)
	ok(fn.text == "Fountain show at 19:00", "the fountain show is not (wind-down) (%s)" % fn.text)
	tw.clock = _view_clock
	await _at(1, 1290.0)
	await _stand(Vector2(-52.0, 3.6))
	fw.pressed.emit()
	await _frames(2)
	eq(tp.state, "watch", "watching")
	var wp: Dictionary = tp._watch_point
	if ev:
		eq(wp.stand, ev.watch_point("fireworks").stand, "at the events node's watch point")
		ok((wp.camera as Transform3D).is_equal_approx(ev.watch_point("fireworks").camera), "with its camera")
	ok(hud._tt_chip_label.text.begins_with("Going to watch"), "the chip: on the way (%s)" % hud._tt_chip_label.text)
	ok(c._walk_target != null, "the child walks there")
	# arrive (the walk is long; put the child at the end of it)
	c._walk_target = null
	c._city_route = []
	c.pos = wp.stand
	await _frames(3)
	ok(tp._watch_arrived and rig.t_watch is Transform3D and absf(angle_difference(c.ry, float(wp.ry))) < 0.01, "there: facing the show, the camera holds on it")
	if ev:
		ok(bool(ev.status().get("fireworks", false)) and int(ev.status().get("sparks", 0)) > 0, "and the sky is full of sparks (%s)" % str(ev.status().get("sparks", 0)))
	ok(hud._tt_chip_label.text == "Watching the fireworks", "the chip (%s)" % hud._tt_chip_label.text)
	_toasts.clear()
	await _at(1, 1321.0)
	ok(tp.state == "" and rig.t_watch == null and _toast_has("The show is over"), "at 22:00 the show is over")
	# the fountain show
	await _at(1, 1180.0)
	hud._refresh_thousand_play()
	ok(fn.text == "Watch the fountain show", "19:40: the fountain show is on")
	fn.pressed.emit()
	await _frames(2)
	eq(tp.state, "watch", "watching the fountain")
	c._walk_target = null
	c._city_route = []
	c.pos = tp._watch_point.stand
	await _frames(3)
	ok(tp._watch_arrived and rig.t_watch is Transform3D, "there, the camera on the fountain")
	var look: Vector3 = tp._watch_point.look_at
	var cam_fwd: Vector3 = -(rig.t_watch as Transform3D).basis.z
	ok(cam_fwd.dot(((look - (rig.t_watch as Transform3D).origin)).normalized()) > 0.9, "looking at it")
	tp.end_all()
	await _frames(1)


# ------------------------------------------------------------- the TV controller

func test_tv() -> void:
	TvMode.forced = 1
	await _at(1, 470.0)
	ok(await _until(func(): return pp.max_figures == 96, 1.0), "on the TV the residents keep its budget (%d)" % pp.max_figures)
	ok(world.thousand_events == null or int(world.thousand_events.spark_cap) == 400, "and the fireworks theirs")
	var w := _walker()
	if w.is_empty():
		ok(false, "a walker")
		return
	var p: Vector3 = pp.position_of(w[0])
	await _stand(Vector2(p.x, p.z) + Vector2(1.2, 0.0), -PI / 2.0)
	await _frames(2)
	var hello: bool = c._ctx.get("type", "") == "tt_hello"
	if not hello and c._ctx.get("alt", {}).get("type", "") == "tt_hello":
		pad._run("turn")   # X: the second action
	else:
		pad._run("context")   # Y: the action button, as a tap on it
	ok(await _until(func(): return tp.card_open, 1.0), "the controller's action button says hello (%s)" % str(c._ctx))
	await _frames(2)
	var targets: Array = pad.targets()
	ok(targets.has(hud._tt_card.find_child("CloseCard", true, false)), "Close on the card is a D-pad target")
	ok(not hud._tt_card_follow.visible or targets.has(hud._tt_card_follow), "Follow too")
	ok(targets.has(hud._tt_shows["fireworks"]) and targets.has(hud._tt_shows["fountain"]), "and the show buttons")
	# A on the card's Follow through the pointer
	if hud._tt_card_follow.visible:
		pad._move_cursor(hud._tt_card_follow.get_global_rect().get_center())
		pad._run("confirm")
		await _frames(3)
		eq(tp.state, "follow", "A on Follow follows")
		ok(pad.targets().has(hud._tt_chip_btns.find_child("Chip_end", true, false)), "the chip's Stop is a target")
		ok(pad.hint_parts().any(func(x): return x[1] == "Back"), "the hint names B")
		pad._back()
		await _frames(1)
		eq(tp.state, "", "B ends following")
	tp.meet(w[0])
	await _frames(1)
	pad._back()
	await _frames(1)
	ok(not tp.card_open and not hud._tt_card.visible, "B closes the card")
	# waiting, then B
	await _at(1, 480.0)
	await _stand(tp.stands()["bus-stop-4"])
	pad._run("context")
	ok(await _until(func(): return tp.state == "wait_bus", 1.0), "the controller's action button: Wait for the bus")
	pad._back()
	await _frames(1)
	eq(tp.state, "", "B stops waiting")
	TvMode.forced = 0
	ok(await _until(func(): return pp.max_figures == 160, 1.0), "back to the iPad's budget")


# ------------------------------------------------------------- Ride home from every state

func _home_and_back(what: String) -> void:
	_hints.clear()
	ok(hud._ride_home.visible, "%s: Ride home is there" % what)
	Session._last_journey.clear()
	hud._ride_home.pressed.emit()
	ok(await _until(func(): return c.space == "town" and c.journey_to == "", 8.0), "%s: home" % what)
	await _frames(4)
	eq(tp.state, "", "%s: the state ended" % what)
	ok(not tp.card_open and tp.selected == -1, "%s: no card, nobody selected" % what)
	ok(tr_node.riding(tp.rider_key()) == "", "%s: no bus seat kept" % what)
	ok(rig.t_watch == null and not rig.on_thousand, "%s: the town's camera" % what)
	ok(world.local_kid().find_child("TTSnack", true, false) == null and world.local_kid().anim != "sit", "%s: the child as it was" % what)
	ok(not hud._tt_box.visible and not hud._tt_shows["fireworks"].visible and not hud._tt_shows["fountain"].visible, "%s: no Thousand chip, card or show buttons" % what)
	eq(_visible_buttons(), _town_buttons, "%s: the town HUD exactly as before" % what)
	Session._last_journey.clear()
	c.ride(Places.THOUSAND)
	ok(await _until(func(): return c.space == "thousand" and c.journey_to == "", 8.0), "%s: and back to Thousand Town" % what)
	tw.clock = _view_clock
	await _frames(2)


func test_return_home() -> void:
	# following
	await _at(1, 472.0)
	var w := _walker(40.0)
	if not w.is_empty():
		var p: Vector3 = pp.position_of(w[0])
		await _stand(Vector2(p.x, p.z) + Vector2(0.0, 2.0))
		tp.meet(w[0])
		tp.start_follow(w[0])
		eq(tp.state, "follow", "following")
		await _home_and_back("following")
	# waiting for the bus
	await _at(1, 480.0)
	await _stand(tp.stands()["bus-stop-3"])
	tp.start_wait("bus-stop-3")
	eq(tp.state, "wait_bus", "waiting")
	await _home_and_back("waiting")
	# riding the bus (between stops)
	var dep: Dictionary = tr_node.next_departures("bus-stop-1", 1)[0]
	await _at(1, float(dep.arrive_minute) + 0.1)
	c.pos = tp.stands()["bus-stop-1"]
	ok(tp.board(str(dep.vehicle)), "on the bus")
	await _at(1, float(dep.depart_minute) + 0.5)
	eq(tp.state, "bus", "riding")
	await _home_and_back("riding the bus")
	# on the wheel, at the top, with a snack
	await _at(1, 1110.0)
	await _stand(tp.wheel_board_point())
	_wheel_between()
	await _frames(2)
	tp.start_wheel()
	_wheel_to_bottom()
	ok(await _until(func(): return tp.state == "wheel", 3.0), "on the wheel")
	tw.anim_offset += 90.0
	await _frames(2)
	tp._attach_snack(tp.STALL_SNACKS["grill"])
	tp.snack_kind = "grill"
	tp.snack_until = Time.get_ticks_msec() / 1000.0 + 60.0
	await _home_and_back("riding the wheel")
	# watching
	await _at(1, 1290.0)
	tp.press_show("fireworks")
	c._walk_target = null
	c._city_route = []
	c.pos = tp._watch_point.stand
	await _frames(3)
	ok(tp.state == "watch" and rig.t_watch is Transform3D, "watching the fireworks")
	await _home_and_back("watching")
	# and finally home for good
	Session._last_journey.clear()
	hud._ride_home.pressed.emit()
	ok(await _until(func(): return c.space == "town" and c.journey_to == "", 8.0), "home")
	await _frames(3)
	eq(_visible_buttons(), _town_buttons, "the town HUD as before the first journey")
