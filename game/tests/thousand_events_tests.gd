## Headless tests for Thousand Town's events (world/thousand_events.gd; design/thousand-town.md sections 8, 9):
##   - the eight launch sites from the town data, against upstream's own (tests/thousand/fixtures/events.json);
##   - schedule adherence: nothing before 19:00 or from 22:00, the phases, the show second at 1x equal to
##     thousand_clock.fireworks_state, real pace while the clock holds, a preset jump re-anchors;
##   - determinism: two instances agree spark for spark; a second call gives the same frame;
##   - the spark cap (600, and 400 for the TV) over a whole show; the comets and flashes are counted;
##   - the shapes: every game shape blooms, big enough to read, the contour shapes face the watcher;
##   - the fountain: the pump level at every programme boundary, off 22:00-05:30, the show's pattern and
##     lit colours, daylight jets;
##   - status() and watch_point(): keys, walkable spots (the world's resolve_walk), clear views, the framing;
##   - nothing of the fireworks is visible or computed by day; nothing at all at 03:00.
## Rendered frames: tests/thousand_events_capture.gd.
##   scripts/godot.sh --headless --path game -s res://tests/thousand_events_tests.gd
extends SceneTree

const ThousandWorld := preload("res://scripts/world/thousand_world.gd")
const Events := preload("res://scripts/world/thousand_events.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const FIXTURE := "res://tests/thousand/fixtures/events.json"

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var w: Node3D
var ev: Node3D


class FakeTown extends Node3D:
	var _env: Environment
	var _sun: DirectionalLight3D


func _initialize() -> void:
	var tw := FakeTown.new()
	tw._env = Environment.new()
	tw._sun = DirectionalLight3D.new()
	root.add_child(tw)
	tw.add_child(tw._sun)
	await process_frame
	w = ThousandWorld.new()
	tw.add_child(w)
	w.setup(tw)
	w.build()
	var t0 := Time.get_ticks_usec()
	ev = Events.new()
	w.add_child(ev)
	ev.setup(w)
	_report.append("setup: %.0f ms (%d shells, %d jets)" % [(Time.get_ticks_usec() - t0) / 1000.0, ev.shell_count(), ev.jet_count()])
	for t in ["test_sites", "test_schedule", "test_clock", "test_determinism", "test_cap", "test_shapes",
			"test_fountain", "test_status", "test_watch", "test_daytime"]:
		_current = t
		var t1 := Time.get_ticks_usec()
		call(t)
		_report.append("%s: %.0f ms" % [t, (Time.get_ticks_usec() - t1) / 1000.0])
	for line in _report:
		print(line)
	print("\nTHOUSAND EVENTS TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func _fresh() -> Node3D:
	var e: Node3D = Events.new()
	w.add_child(e)
	e.setup(w)
	return e


func _eye() -> Vector3:
	var wp: Dictionary = ev.watch_point("fireworks")
	return (wp.camera as Transform3D).origin if wp.has("camera") else Vector3(0, 2, 0)


func test_sites() -> void:
	var j := JSON.new()
	ok(j.parse(FileAccess.get_file_as_string(FIXTURE)) == OK, "the events fixture parses")
	var ref: Array = j.data.fireworks.sites
	ok(ev.sites.size() == 8 and ref.size() == 8, "eight launch sites")
	for i in mini(ev.sites.size(), ref.size()):
		var s: Dictionary = ev.sites[i]
		var r: Array = ref[i]
		var want := Vector3(float(r[1]), float(r[2]), float(r[3])) * Clock.UNIT_M
		ok(s.id == r[0] and (s.pos as Vector3).distance_to(want) < 1e-4,
			"site %s at %s (upstream %s x 0.5)" % [s.id, s.pos, want])
		ok(s.id == Clock.FIREWORK_SITES[i], "site %d is %s" % [i, Clock.FIREWORK_SITES[i]])


func test_schedule() -> void:
	var e := _fresh()
	var eye := _eye()
	var leaks := 0
	var m := 0.0
	while m < 1440.0:
		if m < Clock.FIREWORKS_FROM or m >= Clock.FIREWORKS_TO:
			e.update(3, m, 0.0, eye)
			if e.drawn().fireworks > 0 or e.status().fireworks or e.sparks_at(3, m, 40.0, eye).size() > 0:
				leaks += 1
		m += 3.5
	ok(leaks == 0, "no sparks before 19:00 or from 22:00 (%d leaks over a day in 3.5 min steps)" % leaks)
	for edge: Array in [[1139.99, false], [1140.0, true], [1319.99, true], [1320.0, false]]:
		e.update(3, edge[0], 0.0, eye)
		ok(bool(e.status().fireworks) == edge[1], "fireworks at %.2f: %s" % [edge[0], edge[1]])
	# the phases and that something is in the sky through the show
	e.update(3, 1200.0, 0.0, eye)
	var empty := 0
	var phases := {}
	for k in 960:
		e.pin_show_seconds = k * 0.1
		e.update(3, 1200.0, 0.0, eye)
		var st: Dictionary = e.status()
		phases[st.phase] = int(phases.get(st.phase, 0)) + 1
		if k * 0.1 > 0.2 and k * 0.1 < 90.0 and int(st.sparks) == 0:
			empty += 1
			if empty <= 5:
				_report.append("empty sky at %.1f s" % (k * 0.1))
		if absf(float(st.show_seconds) - k * 0.1) > 1e-4 or st.phase != Clock.fireworks_phase(k * 0.1):
			ok(false, "show second and phase at %.1f: %s" % [k * 0.1, st])
	ok(empty == 0, "the sky is never empty between 0.2 s and 90 s of the show (%d empty frames; the last lift is at 84 s)" % empty)
	ok(phases.has("ensemble") and phases.has("weave") and phases.has("finale") and phases.has("rest"),
		"the four phases: %s" % str(phases))
	e.pin_show_seconds = 95.0
	e.update(3, 1200.0, 0.0, eye)
	ok(e.status().phase == "rest", "95 s is the rest (%s, %d sparks)" % [e.status().phase, e.status().sparks])
	e.queue_free()


func test_clock() -> void:
	var e := _fresh()
	var eye := _eye()
	# Auto at 1x: the show second is thousand_clock's
	var bad := 0
	e.update(2, 1150.0, 0.0, eye)
	var m := 1150.0
	for k in 120:
		m += 0.5
		e.update(2, m, 0.5, eye)
		var want: float = Clock.fireworks_state(2, m).show_seconds
		if absf(float(e.status().show_seconds) - want) > 1e-3:
			bad += 1
	ok(bad == 0, "Auto 1x: the show second equals fireworks_state(day, minute) (%d mismatches)" % bad)
	# held (the Night preset): the show runs on in real time
	e.update(2, 1290.0, 0.5, eye)   # the jump to 21:30 re-anchors
	var start: float = Clock.fireworks_state(2, 1290.0).show_seconds
	ok(absf(float(e.status().show_seconds) - start) < 1e-3, "a preset jump starts at the clock's show second (%.2f)" % start)
	for k in 20:
		e.update(2, 1290.0, 0.5, eye)
	ok(absf(float(e.status().show_seconds) - fposmod(start + 10.0, 96.0)) < 1e-3,
		"held: 10 real seconds move the show 10 s (%.2f -> %.2f)" % [start, e.status().show_seconds])
	# 4x: still the real pace
	var s0: float = e.status().show_seconds
	m = 1290.0
	for k in 10:
		m += 2.0
		e.update(2, m, 0.5, eye)
	ok(absf(float(e.status().show_seconds) - fposmod(s0 + 5.0, 96.0)) < 1e-3, "4x: 5 real seconds move the show 5 s")
	# another device that saw the same clock agrees
	var e2 := _fresh()
	e2.update(2, 1290.0, 0.0, eye)
	for k in 20:
		e2.update(2, 1290.0, 0.5, eye)
	ok(absf(float(e2.status().show_seconds) - fposmod(start + 10.0, 96.0)) < 1e-3, "a second device holding the same time agrees")
	# the pump off and the show over: the offset is cleared
	e.update(3, 200.0, 0.5, eye)
	e.update(3, 200.5, 0.5, eye)
	e.update(3, 1141.0, 0.5, eye)
	ok(absf(float(e.status().show_seconds) - float(Clock.fireworks_state(3, 1141.0).show_seconds)) < 1e-3,
		"next night starts on the clock again")
	e.queue_free()
	e2.queue_free()


func test_determinism() -> void:
	var a := _fresh()
	var b := _fresh()
	var eye := _eye()
	var same := true
	var frames := 0
	var t := 0.0
	while t < 96.0:
		var fa: PackedFloat32Array = a.sparks_at(5, 1200.0, t, eye)
		var fb: PackedFloat32Array = b.sparks_at(5, 1200.0, t, eye)
		var fa2: PackedFloat32Array = a.sparks_at(5, 1200.0, t, eye)
		if fa != fb or fa != fa2:
			same = false
		frames += 1
		t += 0.37
	ok(same, "two instances (and a repeated call) give the same %d frames" % frames)
	# the content does not depend on the watcher: the same count of shells and the same colours
	var other := Vector3(-60, 2, 40)
	var fa: PackedFloat32Array = a.sparks_at(5, 1200.0, 50.0, eye)
	var fo: PackedFloat32Array = a.sparks_at(5, 1200.0, 50.0, other)
	var ca := []
	var co := []
	for i in fa.size() / 16:
		ca.append(Color(fa[i * 16 + 12], fa[i * 16 + 13], fa[i * 16 + 14]).to_html())
	for i in fo.size() / 16:
		co.append(Color(fo[i * 16 + 12], fo[i * 16 + 13], fo[i * 16 + 14]).to_html())
	ca.sort()
	co.sort()
	ok(ca == co, "another watcher sees the same sparks and colours (%d vs %d)" % [ca.size(), co.size()])
	a.queue_free()
	b.queue_free()


func test_cap() -> void:
	var e := _fresh()
	var eye := _eye()
	var worst := 0
	var at := 0.0
	var capped := 0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var t := 0.0
	while t < 96.0:
		e.pin_show_seconds = t
		e.update(4, 1200.0, 0.0, eye)
		var n: int = e.status().sparks
		if n > worst:
			worst = n
			at = t
		if n >= Events.MAX_SPARKS - 2:
			capped += 1
		frames += 1
		t += 0.1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	# the parts: the fireworks alone (sparks_at) and the fountain alone (a day frame)
	var t1 := Time.get_ticks_usec()
	var nf := 0
	t = 0.0
	while t < 96.0:
		e.sparks_at(4, 1200.0, t, eye)
		nf += 1
		t += 0.5
	var fw_ms := (Time.get_ticks_usec() - t1) / 1000.0 / nf
	t1 = Time.get_ticks_usec()
	for k in 100:
		e.update(4, 720.0 + k * 0.01, 0.01, eye)
	var fo_ms := (Time.get_ticks_usec() - t1) / 1000.0 / 100.0
	ok(worst <= Events.MAX_SPARKS, "at most %d sparks (worst %d at %.1f s)" % [Events.MAX_SPARKS, worst, at])
	ok(e.drawn().fireworks <= Events.MAX_SPARKS, "the MultiMesh draws within the cap")
	_report.append("sparks: worst %d at %.1f s of the show; %d of %d frames at the cap; a night frame (fireworks + fountain) %.2f ms, the fireworks alone %.2f ms, the fountain alone %.2f ms (EC2 headless GDScript, not a device number)" % [worst, at, capped, frames, ms, fw_ms, fo_ms])
	e.spark_cap = Events.MAX_SPARKS_TV
	var worst_tv := 0
	t = 0.0
	while t < 96.0:
		e.pin_show_seconds = t
		e.update(4, 1200.0, 0.0, eye)
		worst_tv = maxi(worst_tv, int(e.status().sparks))
		t += 0.25
	ok(worst_tv <= Events.MAX_SPARKS_TV, "the TV cap: at most %d (worst %d)" % [Events.MAX_SPARKS_TV, worst_tv])
	# the cap thins evenly: under the cap every live shell still draws
	e.spark_cap = Events.MAX_SPARKS
	e.pin_show_seconds = at
	e.update(4, 1200.0, 0.0, eye)
	ok(int(e.status().shells) >= 3, "at the worst moment %d shells are in the air" % e.status().shells)
	e.queue_free()


func test_shapes() -> void:
	var eye := _eye()
	var seen := {}
	for i in ev.shell_count():
		var s = ev.shell(i)
		if seen.has(s.shape):
			continue
		seen[s.shape] = i
		var since := 0.4 if s.shape == "salute" else 1.5
		var f: Dictionary = ev.shell_frame(i, since, eye)
		var buf: PackedFloat32Array = f.buffer
		var n := buf.size() / 16
		var apex: Vector3 = f.apex
		var b: Basis = f.basis
		var extent := 0.0
		var span_r := 0.0
		var span_n := 0.0
		for k in n:
			var p := Vector3(buf[k * 16 + 3], buf[k * 16 + 7], buf[k * 16 + 11]) - apex
			extent = maxf(extent, p.length())
			span_r = maxf(span_r, absf(p.dot(b.x)))
			span_n = maxf(span_n, absf(p.dot(b.z)))
		ok(n >= int(s.n) * 0.6, "%s: %d of %d sparks alive at %.2f s" % [s.shape, n, s.n, since])
		var small := 2.0 if s.shape == "salute" else 8.0
		ok(extent > small and extent < 45.0, "%s: %.1f m across its radius (readable, inside the sky)" % [s.shape, extent])
		if s.rel and s.shape != "saturn":
			ok(span_n < span_r * 0.95, "%s faces the watcher (depth %.1f m < width %.1f m)" % [s.shape, span_n, span_r])
	var want := ["peony", "chrysanthemum", "willow", "palm", "salute", "ring", "fan", "crown", "heart", "star", "spiral", "saturn"]
	for sh in want:
		ok(seen.has(sh), "the show has a %s" % sh)
	_report.append("shapes, first shell of each: %s" % str(seen))


func test_fountain() -> void:
	var e := _fresh()
	ok(e.jet_count() == 28, "28 jets (16 main, 12 low)")
	for m: float in [0.0, 329.9, 330.0, 335.9, 336.0, 419.0, 420.0, 425.0, 1079.0, 1080.0, 1110.0, 1139.0, 1140.0,
			1145.0, 1269.0, 1270.0, 1319.9, 1320.0, 1439.9]:
		e.update(1, m, 0.0, Vector3(30, 2, 75))
		var st: Dictionary = e.status()
		var want := Clock.fountain_level_smooth(m)
		ok(absf(float(st.fountain_level) - want) < 1e-6 and st.fountain == Clock.fountain_program(m),
			"%s: level %.3f programme %s" % [Clock.format_minute(m), want, Clock.fountain_program(m)])
		var drawn: Dictionary = e.drawn()
		if want > 0.001:
			ok(drawn.jets == 28 and drawn.spray > 0, "%s: 28 jets and their spray drawn" % Clock.format_minute(m))
		else:
			ok(drawn.jets == 0 and drawn.spray == 0, "%s: the pump is off, nothing drawn" % Clock.format_minute(m))
	# daytime: modest jets, all moving
	var h0: PackedFloat32Array = e.jet_heights(720.0, 1000.0)
	var h1: PackedFloat32Array = e.jet_heights(720.0, 1003.0)
	var lo := 99.0
	var hi := 0.0
	var moved := 0
	for i in h0.size():
		lo = minf(lo, h0[i])
		hi = maxf(hi, h0[i])
		if absf(h1[i] - h0[i]) > 0.01:
			moved += 1
	ok(lo > 0.3 and hi < 3.0, "by day the jets stand %.2f-%.2f m" % [lo, hi])
	ok(moved > 20, "by day %d of 28 jets breathe within 3 s" % moved)
	# the show: taller, a pattern round the ring that changes
	var smax := 0.0
	var smin := 99.0
	for k in 72:
		for v in e.jet_heights(1200.0, 5000.0 + k):
			smax = maxf(smax, v)
			smin = minf(smin, v)
	ok(smax > hi * 1.8, "the show's tallest jet %.2f m (by day %.2f m)" % [smax, hi])
	var figures := {}
	for s: float in [5000.0, 5024.0 + 5.0, 5048.0 + 5.0]:
		var hh: PackedFloat32Array = e.jet_heights(1200.0, s)
		var key := []
		for v in hh:
			key.append(snappedf(v, 0.05))
		figures[str(key)] = true
	ok(figures.size() == 3, "the show's three figures differ")
	# lit colours at night in the show, plain water by day
	e.update(1, 1200.0, 0.0, Vector3(30, 2, 75))
	var night := _colours(e._jet_mm.buffer)
	e.update(1, 720.0, 0.0, Vector3(30, 2, 75))
	var day := _colours(e._jet_mm.buffer)
	ok(night.size() >= 4, "the show lights the jets in %d colours" % night.size())
	ok(day.size() == 1, "by day the jets are one water colour (%d)" % day.size())
	_report.append("fountain: day jets %.2f-%.2f m; show %.2f-%.2f m; show colours %d" % [lo, hi, smin, smax, night.size()])
	e.queue_free()


func _colours(buf: PackedFloat32Array) -> Dictionary:
	var out := {}
	for i in buf.size() / 16:
		out[Color(buf[i * 16 + 12], buf[i * 16 + 13], buf[i * 16 + 14]).to_html(false).substr(0, 4)] = true
	return out


func test_status() -> void:
	var e := _fresh()
	e.update(1, 1200.0, 0.0, _eye())
	var st: Dictionary = e.status()
	for k in ["fireworks", "phase", "show_seconds", "next_fireworks_minute", "next_fireworks_day", "minutes_to_fireworks",
			"sparks", "shells", "fountain", "fountain_level", "fountain_show"]:
		ok(st.has(k), "status() has %s" % k)
	ok(st.fireworks == true and st.fountain == "show" and st.fountain_show == true, "20:00: fireworks and the fountain show")
	e.update(1, 600.0, 0.0, _eye())
	st = e.status()
	ok(st.fireworks == false and st.phase == "off" and is_equal_approx(float(st.minutes_to_fireworks), 540.0)
		and int(st.next_fireworks_day) == 1, "10:00: off, 540 minutes to the show today")
	e.update(1, 1330.0, 0.0, _eye())
	st = e.status()
	ok(int(st.next_fireworks_day) == 2 and is_equal_approx(float(st.minutes_to_fireworks), 1250.0), "22:10: tomorrow's show")
	e.queue_free()


func test_watch() -> void:
	ok(ev.watch_point("nothing").is_empty(), "an unknown kind gives {}")
	for kind in ["fireworks", "fountain"]:
		var wp: Dictionary = ev.watch_point(kind)
		ok(not wp.is_empty(), "a %s watch point" % kind)
		if wp.is_empty():
			continue
		var p: Vector2 = wp.stand
		ok(w.resolve_walk(p).distance_to(p) < 0.05, "%s: %s is walkable" % [kind, p])
		ok(absf(float(wp.y) - w.height_at(p)) < 1e-4, "%s: its ground height" % kind)
		var look: Vector3 = wp.look_at
		var fwd := Vector2(sin(float(wp.ry)), cos(float(wp.ry)))
		ok(fwd.dot(Vector2(look.x - p.x, look.z - p.y).normalized()) > 0.99, "%s: the child faces the target" % kind)
		var cam: Transform3D = wp.camera
		var to := (look - cam.origin).normalized()
		var ang := rad_to_deg((-cam.basis.z).angle_to(to))
		ok(ang < 21.0, "%s: the target is inside the 42-degree frame (%.1f degrees off the centre)" % [kind, ang])
		var chest := Vector3(p.x, float(wp.y) + 0.9, p.y)
		var ca := rad_to_deg((-cam.basis.z).angle_to((chest - cam.origin).normalized()))
		ok(ca < 21.0, "%s: the child is in the frame (%.1f degrees)" % [kind, ca])
		ok(ev.watch_point(kind) == wp, "%s: the same answer again" % kind)
		_report.append("watch %s: stand %s y %.2f ry %.2f look %s sites %s camera %s" % [kind, p, wp.y, wp.ry, look, str(wp.sites), cam.origin])
	var fw: Dictionary = ev.watch_point("fireworks")
	ok(fw.get("sites", []).size() >= 2, "the fireworks spot sees %d launch sites" % fw.get("sites", []).size())
	var fo: Dictionary = ev.watch_point("fountain")
	if not fo.is_empty():
		var d := Vector2(ev.fountain_centre.x, ev.fountain_centre.z).distance_to(fo.stand)
		ok(d > 9.0 and d < 15.0, "the fountain spot is %.1f m from the centre, outside the 7.3 m basin" % d)


func test_daytime() -> void:
	var e := _fresh()
	e.update(1, 720.0, 0.0, _eye())
	var dr: Dictionary = e.drawn()
	ok(dr.fireworks == 0 and not e._fw_node.visible, "12:00: the fireworks node is hidden, no sparks")
	ok(dr.nodes_visible == 2, "12:00: only the fountain's two nodes are visible (%d)" % dr.nodes_visible)
	e.update(1, 180.0, 0.0, _eye())
	dr = e.drawn()
	ok(dr.nodes_visible == 0 and dr.fireworks == 0 and dr.jets == 0, "03:00: nothing visible")
	# no per-frame work by day: the buffer is not touched
	var before: PackedFloat32Array = e._fw_mm.buffer
	e.update(1, 600.0, 0.5, _eye())
	ok(e._fw_mm.buffer == before and e._fw_mm.visible_instance_count == 0, "by day the fireworks' buffer is untouched")
	e.queue_free()
