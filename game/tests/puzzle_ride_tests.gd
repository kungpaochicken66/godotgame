## Headless tests for puzzle rooms and rideable carts (design/puzzle-rooms-and-rides.md):
## the pure rules, the saved town, and the authority running both for real (solo).
##   godot --headless --path game -s res://tests/puzzle_ride_tests.gd
## The scale contract, catalog, locale and toy box name checks for the new things
## run with everything else in run_tests.gd; two real clients are in scripts/net_test.py --puzzles.
extends SceneTree

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Puzzles := preload("res://scripts/core/puzzles.gd")
const RideRules := preload("res://scripts/core/ride_rules.gd")
const Contraptions := preload("res://scripts/core/contraptions.gd")
const RoomThemes := preload("res://scripts/core/room_themes.gd")
const TrackRules := preload("res://scripts/core/track_rules.gd")

var Session: Node
var _failures := 0
var _checks := 0
var _current := "":
	set(v):
		_current = v
		if _catcher:
			_catcher.owner_test = v
var _catcher: ErrorCatcher


class ErrorCatcher extends Logger:
	var owner_test := ""
	var errors: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append({"test": owner_test, "text": "%s %s (%s:%d)" % [code, rationale, file, line]})
		_lock.unlock()


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	for t in ["test_puzzle_rules", "test_puzzle_saves", "test_ride_rules", "test_ride_geometry", "test_toolkits"]:
		_current = t
		call(t)
	for t in ["test_puzzle_session", "test_ride_session"]:
		_current = t
		await call(t)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nPUZZLE RIDE TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func eq(a: Variant, b: Variant, what: String) -> void:
	ok(a == b, "%s: expected %s, got %s" % [what, b, a])


func _result(req: int) -> Dictionary:
	var out := {}
	var cb := func(r_id: int, r: Dictionary):
		if r_id == req:
			out.merge(r)
	Session.request_done.connect(cb)
	for i in 5:
		await process_frame
	Session.request_done.disconnect(cb)
	return out


func _put(m, kind: String, space: String, x: float, z: float, rot := 0, color := -2) -> String:
	var r: Dictionary = m.place(kind, space, x, z, rot, color)
	ok(r["ok"], "placing %s at (%.1f, %.1f): %s" % [kind, x, z, r.get("error", "")])
	return r.get("item", {}).get("id", "")


# ------------------------------------------------------------- puzzle rules

## A little puzzle outdoors: a chest, a key, a Rose dial with a Rose square clue, and a Leaf dial with no clue.
func _puzzle_town() -> Dictionary:
	var m = TownModel.new()
	var ids := {}
	ids["chest"] = _put(m, "puzzle_chest", "town", 6.0, 6.0)
	ids["key"] = _put(m, "puzzle_key", "town", 9.0, 6.0)
	ids["dial"] = _put(m, "puzzle_dial", "town", 6.0, 8.0, 0, 3)
	ids["clue"] = _put(m, "puzzle_clue_square", "town", 9.0, 9.0, 0, 3)
	ids["loose"] = _put(m, "puzzle_dial", "town", 3.0, 8.0, 0, 5)
	return {"m": m, "ids": ids}


func test_puzzle_rules() -> void:
	var t := _puzzle_town()
	var m = t["m"]
	var ids: Dictionary = t["ids"]
	var p: Dictionary = Puzzles.parts(m, "town")
	eq(p["chests"], [ids["chest"]], "one chest")
	eq(p["keys"], [ids["key"]], "one key")
	eq(p["dials"], [{"id": ids["dial"], "color": 3, "target": 1}], "the dial counts with its clue's picture (a square is picture 1); the dial without a clue card does not")
	eq(p["clues"], [{"id": ids["clue"], "color": 3, "picture": 1}], "one clue card")
	eq(Puzzles.parts(m, "nowhere"), {"chests": [], "keys": [], "dials": [], "clues": []}, "a space without parts has no puzzle")
	# A fresh puzzle: nothing found, no dial on its answer, the same every time.
	var st: Dictionary = Puzzles.fresh(m, "town")
	eq(st["found"], {}, "no key found at the start")
	ok(st["dials"].has(ids["dial"]) and st["dials"].has(ids["loose"]), "every dial shows a picture, puzzle part or not")
	ok(int(st["dials"][ids["dial"]]) != 1, "a dial never starts on its answer")
	eq(Puzzles.fresh(m, "town"), st, "a fresh puzzle is the same every time (every device agrees without a message)")
	var never := true
	for n in range(1, 40):
		for target in 4:
			var sp: int = Puzzles.start_picture("i%d" % n, target)
			never = never and sp != target and sp >= 0 and sp < 4
	ok(never, "start_picture is a real picture and never the answer, for any id and any answer")
	eq(Puzzles.start_picture("i7", -1), 0, "a dial without a clue starts on the first picture")
	var prog: Dictionary = Puzzles.progress(m, "town", st)
	eq([prog["chest"], prog["keys"], prog["keys_found"], prog["dials"], prog["dials_right"], prog["ready"], prog["open"]],
		[true, 1, 0, 1, 0, false, false], "progress of a fresh puzzle")
	# Reach and kinds.
	eq(Puzzles.check_use(m, ids["key"], "town", Vector2(9.0, 7.0)), "", "next to the key")
	eq(Puzzles.check_use(m, ids["key"], "town", Vector2(20.0, 7.0)), Puzzles.ERR_WALK, "too far from the key")
	eq(Puzzles.check_use(m, ids["key"], "i99:0:0", Vector2(9.0, 7.0)), Puzzles.ERR_WALK, "not from another place")
	eq(Puzzles.check_use(m, ids["clue"], "town", Vector2(9.0, 9.0)), Puzzles.ERR_NOT_HERE, "a clue card is only looked at")
	eq(Puzzles.check_use(m, "i999", "town", Vector2.ZERO), Puzzles.ERR_NOT_HERE, "a part that is gone")
	# Solving.
	eq(Puzzles.use(m, st, ids["chest"], "Sky").get("error"), Puzzles.ERR_LOCKED, "the chest is locked at first")
	eq(Puzzles.use(m, st, ids["key"], "Sky"), {"ok": true, "what": "key"}, "the key is picked up")
	eq(Puzzles.use(m, st, ids["key"], "Mo").get("error"), Puzzles.ERR_KEY_FOUND, "a key is found once")
	eq(Puzzles.progress(m, "town", st)["keys_found"], 1, "one key found")
	ok(not Puzzles.progress(m, "town", st)["ready"], "a key alone does not open this chest")
	var turns := 0
	while int(st["dials"][ids["dial"]]) != 1 and turns < 8:
		var r: Dictionary = Puzzles.use(m, st, ids["dial"], "Mo")
		ok(r["ok"] and r["what"] == "dial" and r["picture"] == st["dials"][ids["dial"]], "a turn shows the next picture")
		turns += 1
	ok(turns >= 1 and turns <= 3, "the answer is at most three turns away (%d)" % turns)
	ok(Puzzles.progress(m, "town", st)["ready"], "every key found and every dial right: the chest can be opened")
	Puzzles.use(m, st, ids["loose"], "Mo")
	ok(Puzzles.progress(m, "town", st)["ready"], "a dial without a clue card changes nothing")
	eq(Puzzles.use(m, st, ids["chest"], "Sky"), {"ok": true, "what": "open"}, "the chest opens")
	eq(st["by"], ["Sky", "Mo"], "everyone who helped is remembered, once each")
	ok(Puzzles.progress(m, "town", st)["open"] and not Puzzles.progress(m, "town", st)["ready"], "an open chest is open, not waiting")
	eq(Puzzles.use(m, st, ids["chest"], "Sky").get("error"), Puzzles.ERR_OPEN, "an open chest stays open until the puzzle starts again")
	eq(Puzzles.use(m, st, ids["dial"], "Sky").get("error"), Puzzles.ERR_OPEN, "dials rest while the chest is open")
	# Things that start a puzzle again are seen through its signature.
	var sig: String = Puzzles.signature(m, "town")
	_put(m, "bench", "town", -8.0, 8.0)
	eq(Puzzles.signature(m, "town"), sig, "other things do not touch the puzzle")
	m.move(ids["key"], 9.0, 6.0, 2)
	eq(Puzzles.signature(m, "town"), sig, "turning a part on its spot does not start the puzzle again")
	m.move(ids["key"], 9.5, 6.0, 0)
	ok(Puzzles.signature(m, "town") != sig, "moving a part does")
	sig = Puzzles.signature(m, "town")
	m.paint(ids["dial"], 5)
	ok(Puzzles.signature(m, "town") != sig, "painting a part does (its color is its link)")
	eq(Puzzles.parts(m, "town")["dials"], [], "a dial painted away from its clue card no longer counts")
	m.paint(ids["dial"], 3)
	sig = Puzzles.signature(m, "town")
	m.wrap(ids["key"], "a", "Sky", "", 2)
	ok(Puzzles.signature(m, "town") != sig, "wrapping a part does")
	eq(Puzzles.parts(m, "town")["keys"], [], "a wrapped key is a present, not a key")
	eq(Puzzles.check_use(m, ids["key"], "town", Vector2(9.5, 6.0)), Puzzles.ERR_NOT_HERE, "and cannot be picked up")
	m.unwrap(ids["key"], "a")
	# A state from elsewhere is made safe.
	var safe: Dictionary = Puzzles.sanitize(m, "town", {"found": {ids["key"]: true, "i999": true, ids["chest"]: true}, "dials": {ids["dial"]: 9, "i998": 2}, "open": true,
		"by": ["A", "A", "B", "C", "D", "E", 7]})
	eq(safe["found"], {ids["key"]: true}, "only this puzzle's keys can be found")
	eq(int(safe["dials"][ids["dial"]]), 1, "a picture number wraps into range")
	ok(not safe["dials"].has("i998") and safe["dials"].has(ids["loose"]), "exactly this town's dials")
	eq(safe["by"], ["A", "B", "C", "D"], "at most four names")
	eq(Puzzles.sanitize(m, "town", "nonsense"), Puzzles.fresh(m, "town"), "nonsense becomes a fresh puzzle")
	eq(Puzzles.sanitize(m, "town", {"found": 3, "dials": [], "open": "x", "by": 5})["found"], {}, "wrong types are ignored")
	# Lines that show the puzzle while decorating.
	var links: Array = Puzzles.links(m, "town")
	ok(links.has([ids["key"], ids["chest"], "key"]) and links.has([ids["dial"], ids["chest"], "dial"]) and links.has([ids["clue"], ids["dial"], "clue"]),
		"a key and a dial are joined to the chest, a clue card to its dial (%s)" % str(links))
	eq(links.size(), 3, "and nothing else")
	# Two clue cards of one color: the older decides. More keys than a puzzle counts.
	var newer := _put(m, "puzzle_clue_flower", "town", 12.0, 9.0, 0, 3)
	eq(Puzzles.parts(m, "town")["dials"][0]["target"], 1, "the older clue card of a color decides")
	m.remove(ids["clue"])
	eq(Puzzles.parts(m, "town")["dials"][0]["target"], 3, "when it is put away the other one does (%s)" % newer)
	for i in 8:
		_put(m, "puzzle_key", "town", -12.0 + i * 1.0, -12.0)
	eq(Puzzles.parts(m, "town")["keys"].size(), Puzzles.MAX_KEYS, "a puzzle counts six keys at most")
	# No chest: a key stays where it is. A chest alone: a plain treasure chest.
	var bare = TownModel.new()
	var lone_key := _put(bare, "puzzle_key", "town", 4.0, 4.0)
	var bst: Dictionary = Puzzles.fresh(bare, "town")
	eq(Puzzles.use(bare, bst, lone_key, "Sky").get("error"), Puzzles.ERR_NO_CHEST, "a key needs a chest to go to")
	var only = TownModel.new()
	var chest := _put(only, "puzzle_chest", "town", 4.0, 4.0)
	var ost: Dictionary = Puzzles.fresh(only, "town")
	ok(Puzzles.progress(only, "town", ost)["ready"], "a chest with no keys and no dials opens at once")
	ok(Puzzles.use(only, ost, chest, "Sky")["ok"], "and does")
	# The chest is a contraption trigger: what stands near it answers when it opens.
	ok(Contraptions.is_trigger("puzzle_chest") and not Contraptions.is_reactor("puzzle_chest"), "an opened chest sets things off")
	var lamp := _put(only, "lamp_post", "town", 5.5, 4.0)
	eq(Contraptions.linked(only, chest), [lamp], "a lamp within two steps of the chest is linked to it")
	for k in Puzzles.KINDS:
		ok(Catalog.has(k) and Catalog.allowed_in(k, "town") and Catalog.allowed_in(k, "i1:0:0"), "%s is a thing for rooms and outdoors" % k)
	eq(Puzzles.CLUES.size(), Puzzles.PICTURES.size(), "one clue card kind per picture")


func test_puzzle_saves() -> void:
	var t := _puzzle_town()
	var m = t["m"]
	ok(Puzzles.use(m, Puzzles.fresh(m, "town"), t["ids"]["key"], "Sky")["ok"], "progress is made")
	var saved: Dictionary = m.to_dict()
	eq(saved["schema"], TownModel.SCHEMA, "the save format is the current schema (3 since the zoo; this feature added none)")
	ok(not JSON.stringify(saved).contains("found") and not saved.has("puzzles"), "progress is not in the save")
	var back = TownModel.new()
	ok(back.from_dict(JSON.parse_string(JSON.stringify(saved))), "the town loads again")
	eq(Puzzles.parts(back, "town"), Puzzles.parts(m, "town"), "the puzzle is the same after loading")
	eq(Puzzles.fresh(back, "town"), Puzzles.fresh(m, "town"), "and starts the same way")
	eq(Puzzles.signature(back, "town"), Puzzles.signature(m, "town"), "with the same signature")
	# An old save (schema 1 and 2 without any of the new kinds) loads exactly as before.
	var old = TownModel.make_default()
	var before: String = JSON.stringify(old.to_dict())
	var again = TownModel.new()
	again.from_dict(JSON.parse_string(before))
	eq(JSON.stringify(again.to_dict()), before, "a town without the new things saves byte for byte as it did")
	eq(Puzzles.spaces(again), [], "and has no puzzle")
	var v1 = TownModel.new()
	ok(v1.from_dict({"schema": 1, "next_id": 3, "items": [{"id": "i1", "kind": "cottage", "space": "town", "x": 6.0, "z": 6.0, "rot": 0, "color": 2},
		{"id": "i2", "kind": "chair", "space": "i1", "x": 0.0, "z": 0.0, "rot": 0, "color": 0}]}), "a version 1 save still migrates")
	eq(v1.items["i2"]["space"], "i1:0:0", "its furniture moves into the living room as before")
	# A save from this version read by this version keeps rails on their cells.
	var rails = TownModel.new()
	var st := _put(rails, "ride_station", "town", 8.3, 5.2, 1)
	eq([rails.items[st]["x"], rails.items[st]["z"], rails.items[st]["rot"]], [8.0, 6.0, 2], "rails sit on whole 2 m cells in quarter turns")
	var rb = TownModel.new()
	rb.from_dict(JSON.parse_string(JSON.stringify(rails.to_dict())))
	eq([rb.items[st]["x"], rb.items[st]["z"], rb.items[st]["rot"]], [8.0, 6.0, 2], "and load there again")


# ------------------------------------------------------------- ride rules

static func _curve_rot(d_in: Vector2i, d_out: Vector2i) -> int:
	for rot in [0, 2, 4, 6]:
		var ports := [RideRules.dir_of(rot, 2), RideRules.dir_of(rot, 1)]
		if ports.has(-d_in) and ports.has(d_out):
			return rot
	return -1


static func _straight_rot(d: Vector2i) -> int:
	for rot in [0, 2, 4, 6]:
		if RideRules.dir_of(rot, 0) == d:
			return rot
	return -1


## The pieces of a ring of w x h cells (w >= 3), ridden +x along the row z = cz where the
## station stands in the second cell: [[kind, cell, rot]], station first, in riding order.
static func _ring(cx: int, cz: int, w: int, h: int) -> Array:
	var path := []
	for x in range(1, w):
		path.append(Vector2i(cx + x, cz))
	for z in range(1, h):
		path.append(Vector2i(cx + w - 1, cz + z))
	for x in range(w - 2, -1, -1):
		path.append(Vector2i(cx + x, cz + h - 1))
	for z in range(h - 2, -1, -1):
		path.append(Vector2i(cx, cz + z))
	var out := []
	for i in path.size():
		var cell: Vector2i = path[i]
		var d_in: Vector2i = cell - path[(i - 1 + path.size()) % path.size()]
		var d_out: Vector2i = path[(i + 1) % path.size()] - cell
		if i == 0:
			out.append([RideRules.STATION, cell, _straight_rot(d_out)])
		elif d_in == d_out:
			out.append(["ride_straight", cell, _straight_rot(d_out)])
		else:
			out.append(["ride_curve", cell, _curve_rot(d_in, d_out)])
	return out


func _lay(m, pieces: Array) -> Array:
	var ids := []
	for p in pieces:
		ids.append(_put(m, p[0], "town", p[1].x * RideRules.CELL, p[1].y * RideRules.CELL, p[2]))
	return ids


func test_ride_rules() -> void:
	var m = TownModel.new()
	var pieces := _ring(2, 2, 3, 2)   # station, curve, curve, straight, curve, curve
	eq(pieces.map(func(p): return p[0]), ["ride_station", "ride_curve", "ride_curve", "ride_straight", "ride_curve", "ride_curve"], "a 3 x 2 ring is a station, a straight and four curves")
	var ids := _lay(m, pieces)
	var station: String = ids[0]
	var r: Dictionary = RideRules.route(m, station)
	eq([r["end"], r["loop"], r["legs"].size()], ["loop", true, 6], "the rails come back into the station: a circuit of six pieces")
	var lap := 2.0 * 2 + 4 * PI * 0.5
	ok(absf(RideRules.total_length(r) - lap) < 0.001, "once round is two straights and four quarter circles (%.2f m)" % RideRules.total_length(r))
	ok(absf(RideRules.end_distance(r) - RideRules.LAPS * lap) < 0.001, "a ride is %d laps" % RideRules.LAPS)
	eq(RideRules.go_error(r, 0.0), "", "the cart can go")
	var p0: Dictionary = RideRules.pose(r, 0.0)
	ok(p0["pos"].distance_to(Vector2(6.0, 4.0)) < 0.001 and p0["dir"] == Vector2(1, 0), "the cart starts in the middle of its station, facing the way it rides")
	# The cart moves smoothly all the way round and is back where it began.
	var worst := 0.0
	var prev: Vector2 = p0["pos"]
	var unit := true
	var s := 0.0
	while s < lap:
		s += 0.05
		var p: Dictionary = RideRules.pose(r, s)
		worst = maxf(worst, p["pos"].distance_to(prev))
		unit = unit and absf(p["dir"].length() - 1.0) < 0.001
		prev = p["pos"]
	ok(worst < 0.06, "no jump anywhere on the way round (largest step %.3f m for 0.05 m of riding)" % worst)
	ok(unit, "the cart always points somewhere")
	ok(RideRules.pose(r, lap)["pos"].distance_to(p0["pos"]) < 0.001, "after one lap the cart is at its station again")
	ok(RideRules.pose(r, lap + 3.0)["pos"].distance_to(RideRules.pose(r, 3.0)["pos"]) < 0.001, "the second lap follows the first")
	eq(RideRules.locate(r, 0.0), {"leg": 0, "offset": 1.0}, "at the start the cart is half way through its station")
	# Open, misjoined and blocked tracks.
	var gone: Dictionary = m.items[ids[3]].duplicate()
	m.remove(ids[3])
	var open: Dictionary = RideRules.route(m, station)
	eq([open["end"], open["loop"], open["legs"].size(), open["at"]], ["end", false, 3, Vector2(6.0, 6.0)], "a missing piece: the track ends before it, and the place is known")
	ok(absf(RideRules.end_distance(open) - (2.0 + PI - 1.0 - RideRules.STOP_MARGIN)) < 0.001, "the cart stops a little before the last piece's end")
	eq(RideRules.go_error(open, 0.0), "", "an open track can be ridden to its end")
	eq(RideRules.go_error(open, RideRules.end_distance(open)), RideRules.ERR_END, "and not past it")
	var turned: String = _put(m, "ride_straight", "town", gone["x"], gone["z"], int(gone["rot"]) + 2)
	eq(RideRules.route(m, station)["end"], "wrong_way", "a piece turned across the way does not join")
	m.remove(turned)
	var straight: String = _put(m, "ride_straight", "town", gone["x"], gone["z"], gone["rot"])
	eq(RideRules.route(m, station)["end"], "loop", "the piece back in place closes the circuit again")
	var tree: String = _put(m, "tree", "town", gone["x"], gone["z"])
	var blocked: Dictionary = RideRules.route(m, station)
	eq([blocked["end"], blocked["legs"].size()], ["blocked", 3], "a tree standing on a rail: the cart stops before it")
	m.remove(tree)
	var close: String = _put(m, "tree", "town", 6.0, 4.0 - 1.4)
	eq(RideRules.route(m, station)["end"], "loop", "a tree 1.4 m beside the rails is clear of the cart (0.4 m half width)")
	m.remove(close)
	var bush: String = _put(m, "bush", "town", 6.0, 4.0)
	var stuck: Dictionary = RideRules.route(m, station)
	eq([stuck["end"], stuck["legs"].size()], ["blocked", 1], "something on the station itself")
	eq(RideRules.go_error(stuck, 0.0), RideRules.ERR_BLOCKED, "the cart does not start into it")
	m.remove(bush)
	# The town changing under a moving cart.
	var full: Dictionary = RideRules.route(m, station)
	var here := 1.0 + PI * 0.5 + 0.4   # 0.4 m into the second curve
	eq(RideRules.locate(full, here)["leg"], 2, "the cart is on the third piece")
	m.remove(ids[5])
	var shorter: Dictionary = RideRules.route(m, station)
	ok(absf(RideRules.rebase(full, here, shorter) - here) < 0.001, "a piece taken away ahead: the cart is where it was")
	ok(RideRules.rebased_end(shorter, here, 20.0) < RideRules.total_length(full), "and its ride now ends at the new end of the rails")
	m.remove(ids[2])
	eq(RideRules.rebase(full, here, RideRules.route(m, station)), -1.0, "the piece under the cart taken away: the cart is on no route")
	_put(m, "ride_curve", "town", pieces[2][1].x * 2.0, pieces[2][1].y * 2.0, pieces[2][2])
	_put(m, "ride_curve", "town", pieces[5][1].x * 2.0, pieces[5][1].y * 2.0, pieces[5][2])
	var whole: Dictionary = RideRules.route(m, station)
	eq(whole["end"], "loop", "both back: a circuit again")
	var half_lap_left := RideRules.rebased_end(whole, here, 1.0)
	ok(absf(half_lap_left - lap) < 0.001, "a ride with less than a lap to go ends at the station next time round")
	ok(absf(RideRules.rebased_end(whole, here, lap * 2.0 - 1.0) - lap * 2.0) < 0.001, "one with two laps to go ends one lap later")
	# A second station on the same rails, and boarding.
	m.remove(straight)
	var other: String = _put(m, "ride_station", "town", gone["x"], gone["z"], gone["rot"])
	eq(RideRules.route(m, station)["end"], "end", "a cart stops before another cart's station")
	eq(RideRules.route(m, other)["end"], "end", "and so does the other one")
	eq(RideRules.check_board(m, station, "town", Vector2(6.0, 5.5)), "", "next to the cart")
	eq(RideRules.check_board(m, station, "town", Vector2(16.0, 5.5)), RideRules.ERR_WALK, "too far to get in")
	eq(RideRules.check_board(m, ids[1], "town", Vector2(8.0, 4.0)), RideRules.ERR_NOT_HERE, "a rail is not a cart")
	eq(RideRules.check_board(m, station, "i1:0:0", Vector2(6.0, 5.5)), RideRules.ERR_WALK, "not from indoors")
	m.wrap(station, "a", "Sky", "", 1)
	eq(RideRules.check_board(m, station, "town", Vector2(6.0, 5.5)), RideRules.ERR_NOT_HERE, "a wrapped station is a present")
	eq(RideRules.route(m, station)["legs"], [], "and has no route")
	# A station with nothing in front of it, and turned round on a ring.
	var lone = TownModel.new()
	var alone := _put(lone, "ride_station", "town", 4.0, 4.0, 0)
	eq(RideRules.go_error(RideRules.route(lone, alone), 0.0), RideRules.ERR_NO_TRACK, "a station alone has nowhere to go")
	var rev = TownModel.new()
	var rp := _ring(2, 2, 4, 3)
	rp[0][2] = posmod(rp[0][2] + 4, 8)
	var rids := _lay(rev, rp)
	var back: Dictionary = RideRules.route(rev, rids[0])
	eq([back["end"], back["legs"].size()], ["loop", 10], "a station turned round rides the same ring the other way")
	eq(Vector2i(back["legs"][1][0], back["legs"][1][1]), rp[9][1], "starting with the piece behind it")
	eq(RideRules.step_off_points(Vector2(4, 4), Vector2(1, 0)), [Vector2(4, 4 + RideRules.STEP_OFF), Vector2(4, 4 - RideRules.STEP_OFF), Vector2(4 - RideRules.STEP_OFF, 4)],
		"stepping off: right of the cart, else left, else behind")


## Scale and clearance: the numbers the rails were sized by, checked instead of assumed.
func test_ride_geometry() -> void:
	for k in RideRules.KINDS:
		var d: Dictionary = Catalog.ITEMS[k]
		eq([Catalog.grid(k), d["layer"], d["space"]], [RideRules.CELL, "flat", "town"], "%s lies flat outdoors on 2 m cells" % k)
		ok(d["radius"] * 2.0 < RideRules.CELL, "%s: two neighbours do not count as overlapping (%.2f m footprints, 2 m apart)" % [k, d["radius"]])
	ok(Catalog.seats(RideRules.STATION) == 0, "the cart's seat is the ride's own (the plain Sit request cannot take it)")
	# A quarter circle stays inside its own cell and one meter from the cell corner it turns about.
	var leg := [3, 3, 0, 1, 1, 0]
	var inside := true
	var radius_ok := true
	for i in 21:
		var p: Vector2 = RideRules.leg_pose(leg, i / 20.0)["pos"]
		inside = inside and absf(p.x - 6.0) <= 1.0001 and absf(p.y - 6.0) <= 1.0001
		radius_ok = radius_ok and absf(p.distance_to(Vector2(7.0, 5.0)) - 1.0) < 0.001
	ok(inside and radius_ok, "a curve is a 1 m quarter circle inside its cell")
	eq(RideRules.leg_pose(leg, 0.0), {"pos": Vector2(6.0, 5.0), "dir": Vector2(0, 1)}, "in at the middle of one edge")
	ok(RideRules.leg_pose(leg, 1.0)["pos"].distance_to(Vector2(7.0, 6.0)) < 0.001 and RideRules.leg_pose(leg, 1.0)["dir"].distance_to(Vector2(1, 0)) < 0.001, "out at the middle of the next")
	ok(RideRules.CELL - 2.0 * RideRules.CART_HALF >= 1.0, "carts on side-by-side tracks keep more than a meter between them")
	ok(RideRules.SPEED < 3.4, "the cart is slower than walking, so the camera follows it as gently as on foot")
	# The built cart: narrower than the rails' cell, its seat a child's hip height above the floor.
	var Props = load("res://scripts/art/props.gd")
	var node: Node3D = Props.build(RideRules.STATION, 2, 1)
	var cart := node.get_node_or_null("Cart") as Node3D
	ok(cart != null and Props.seat_marker(node, 0) != null and Props.seat_marker(node, 0).get_parent() == cart, "the station has a cart, and the seat is in the cart")
	var box := AABB()
	var first := true
	for mi in cart.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var p: Node = mi
		while p != cart:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	ok(box.size.x <= 2.0 * RideRules.CART_HALF + 0.03 and box.size.x >= 0.7, "the cart is as wide as the rules say (%.2f m)" % box.size.x)
	ok(box.size.z <= 1.25, "and short enough to turn on a 1 m curve (%.2f m)" % box.size.z)
	var seat_y: float = Props.seat_marker(node, 0).position.y
	ok(seat_y > 0.3 and seat_y < 0.6, "the seat is at sitting height (%.2f m)" % seat_y)
	ok(box.end.y < 0.75, "the sides stay under a seated child's shoulders (%.2f m), so the child is seen" % box.end.y)
	node.free()
	# Why the toy-track pieces are not reused: their arches are lower than a seated rider.
	for k in ["track_bell", "track_light", "track_switch", "track_start"]:
		ok(Catalog.height(k) < 0.6 and Catalog.ITEMS[k]["bounds"].x < 1.0, "%s is a %.2f m high piece on a board under 1 m: no room for a rider" % [k, Catalog.height(k)])
	eq(TrackRules.PORTS["track_start"].size(), 1, "and a toy-track start has one opening, so it cannot be part of a ring")
	# Rails and toy tracks cannot share a cell.
	var m = TownModel.new()
	_put(m, "ride_straight", "town", 4.0, 4.0)
	eq(m.place("track_straight", "town", 4.0, 4.0, 0)["error"], TownModel.ERR_OVERLAP, "a toy-track piece cannot lie on a rail")
	ok(m.place("ride_straight", "town", 6.0, 4.0, 0)["ok"], "the next cell is free for the next rail")
	# A new rail's preview starts on a cell that is really free: the search for a free spot tries
	# the cell a piece would snap to, not the unsnapped point (found by the tour: a preview that began red).
	for near in [Vector2(4.6, 4.4), Vector2(5.1, 3.9), Vector2(6.9, 4.9), Vector2(3.2, 5.0)]:
		var spot = m.find_free_spot("ride_curve", "town", near)
		ok(spot != null and is_equal_approx(fposmod(spot.x, 2.0), 0.0) and is_equal_approx(fposmod(spot.y, 2.0), 0.0) and m.check("ride_curve", "town", spot.x, spot.y, 0) == "",
			"a free spot for a rail near %s is a whole free cell (%s)" % [near, spot])
		ok(spot != null and m.place("ride_curve", "town", spot.x, spot.y, 0).get("item", {}).get("x") == spot.x, "and the rail lands exactly there")
	var tm = TownModel.new()
	_put(tm, "track_straight", "town", 5.0, 5.0)
	var tspot = tm.find_free_spot("track_straight", "town", Vector2(5.3, 5.4))
	ok(tspot != null and tspot == tspot.round() and tspot != Vector2(5.0, 5.0), "the same holds for 1 m toy-track pieces (%s)" % [tspot])
	eq(TownModel.new().find_free_spot("chair", "town", Vector2(5.33, 5.41)), Vector2(5.35, 5.4), "things without a grid are searched as before")


func test_toolkits() -> void:
	ok(RoomThemes.toolkits_for("town").has("Puzzles") and RoomThemes.toolkits_for("i1:0:0").has("Puzzles"), "the Puzzles tab is in the toy box indoors and out")
	ok(RoomThemes.toolkits_for("town").has("Rides") and not RoomThemes.toolkits_for("i1:0:0").has("Rides"), "the Rides tab is outdoors only")
	for k in Puzzles.KINDS:
		ok(RoomThemes.extra_for("Puzzles").has(k), "%s is in the Puzzles tab" % k)
	for k in RideRules.KINDS:
		ok(RoomThemes.extra_for("Rides").has(k), "%s is in the Rides tab" % k)
	# Every icon an action button can ask for exists. (An unknown name silently shows the warning
	# icon; "Pick up the key" first asked for one that did not exist. No headless check saw it.)
	var UIK = load("res://scripts/ui/ui_kit.gd")
	var src: String = FileAccess.get_file_as_string("res://scripts/world/play_controller.gd")
	var rx := RegEx.new()
	rx.compile("\"icon\": \"([a-z_]+)\"")
	var names := {}
	for m in rx.search_all(src):
		names[m.get_string(1)] = true
	ok(names.size() >= 12 and names.has("key"), "the action button's icon names are found in the source (%d)" % names.size())
	eq(names.keys().filter(func(n): return not UIK.ICONS.has(n)), [], "every icon an action button names exists")
	ok(UIK.icon("key", 64) != null and UIK.icon("key", 64).get_width() == 64, "the key icon draws")
	for tab in ["Puzzles", "Rides"]:
		ok(RoomThemes.TOOLKIT_IDEAS.has(tab) and RoomThemes.TOOLKIT_ITEMS[tab].all(func(k): return Catalog.has(k)), "%s has an idea line and only real things" % tab)
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing := []
		for text in [RoomThemes.TOOLKIT_IDEAS["Puzzles"], RoomThemes.TOOLKIT_IDEAS["Rides"], "Puzzles", "Rides", Puzzles.ERR_LOCKED, Puzzles.ERR_NO_CHEST, Puzzles.ERR_KEY_FOUND,
				Puzzles.ERR_OPEN, Puzzles.ERR_WALK, Puzzles.ERR_NOT_HERE, RideRules.ERR_TAKEN, RideRules.ERR_NO_TRACK, RideRules.ERR_END, RideRules.ERR_BLOCKED,
				RideRules.ERR_BROKEN, RideRules.ERR_WALK, RideRules.ERR_NOT_HERE, RideRules.ERR_NOT_RIDING] + (Puzzles.KINDS + RideRules.KINDS).map(func(k): return Catalog.ITEMS[k]["name"]):
			if code != "en" and (not cat.has(text) or str(cat[text]) == "" or str(cat[text]) == text):
				missing.append(text)
		eq(missing, [], "[%s] every puzzle and ride text is translated" % code)


# ------------------------------------------------------------- the authority (solo)

func _fresh_town(path: String) -> void:
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	# The animals stay out of the way (they have their own tests).
	var anim = root.get_node("Animals")
	for a in anim.brain.animals:
		a["pos"] = Vector2(-24.0, -20.0)
		a["goal"] = null
		a["plan"] = "rest"
		a["timer"] = 999.0


func _go(space: String, p: Vector2, peer := 0) -> void:
	Session._srv_state(peer if peer != 0 else Session.my_id, {"space": space, "x": p.x, "z": p.y, "ry": 0.0, "anim": "idle"})


func _place(kind: String, at: Vector2, rot := 0, color := -2) -> String:
	var r := await _result(Session.place(kind, "town", at, rot, color))
	ok(r.get("ok", false), "placing %s at %s: %s" % [kind, at, r.get("error", "")])
	return r.get("item", {}).get("id", "")


func test_puzzle_session() -> void:
	await process_frame
	eq(Session.PROTOCOL, 20, "protocol 20")
	var path := "user://test_puzzles.json"
	await _fresh_town(path)
	var me: int = Session.my_id
	var nick: String = Session.nick_of(me)
	# Free ground for a 5 x 4 m corner.
	var base := Vector2(99, 99)
	var spec := [["puzzle_chest", Vector2(0, 0)], ["puzzle_key", Vector2(3, 0)], ["puzzle_dial", Vector2(0, 2)], ["puzzle_clue_triangle", Vector2(3, 3)], ["lamp_post", Vector2(1.5, 0)]]
	for x in range(-22, 16):
		for z in range(8, 16):
			var c := Vector2(x, z)
			if base.x == 99 and spec.all(func(e): return Session.model.check(e[0], "town", c.x + e[1].x, c.y + e[1].y, 0) == "") \
					and Session.model.items_in("town").all(func(i): return not Contraptions.takes_part(i["kind"]) or Vector2(i["x"], i["z"]).distance_to(c) > 6.0):
				base = c
	ok(base.x != 99, "found room for a puzzle corner")
	var changes := []
	var on_change := func(space, st, was): changes.append([space, st.duplicate(true), was.duplicate(true)])
	Session.puzzle_changed.connect(on_change)
	var ids := {}
	for e in spec:
		ids[e[0]] = await _place(e[0], base + e[1], 0, 6 if e[0] in ["puzzle_dial", "puzzle_clue_triangle"] else -2)
	eq(changes, [], "building a puzzle sends nothing: a fresh puzzle is the same everywhere")
	eq(Session.puzzle_state("town"), Puzzles.fresh(Session.model, "town"), "it is ready to play")
	eq(Puzzles.parts(Session.model, "town")["dials"], [{"id": ids["puzzle_dial"], "color": 6, "target": 2}], "the Lilac dial wants the Lilac card's triangle")
	# Solving, with the authority checking where the child stands.
	_go("town", base + Vector2(3, 8))
	eq((await _result(Session.use_puzzle(ids["puzzle_key"]))).get("error"), Puzzles.ERR_WALK, "a key is picked up from next to it")
	_go("town", base + Vector2(0.8, 0.8))
	var locked := await _result(Session.use_puzzle(ids["puzzle_chest"]))
	eq(locked.get("error"), Puzzles.ERR_LOCKED, "the chest is locked")
	eq(locked.get("progress", {}).get("keys_found"), 0, "the answer says how far the puzzle is")
	_go("town", base + Vector2(3, 0.8))
	var got := await _result(Session.use_puzzle(ids["puzzle_key"]))
	ok(got.get("ok", false) and got.get("what") == "key" and got["progress"]["keys_found"] == 1, "the key is found (%s)" % str(got))
	eq(changes.size(), 1, "everyone is told once")
	ok(changes[0][0] == "town" and changes[0][1]["found"].has(ids["puzzle_key"]) and changes[0][2].is_empty(), "with the new progress")
	eq(Session.puzzles["town"]["by"], [nick], "and who helped")
	_go("town", base + Vector2(0.8, 2.6))
	var turns := 0
	var last := {}
	while not Puzzles.progress(Session.model, "town", Session.puzzle_state("town"))["ready"] and turns < 6:
		last = await _result(Session.use_puzzle(ids["puzzle_dial"]))
		turns += 1
	ok(turns >= 1 and turns <= 3 and last.get("progress", {}).get("ready", false), "turning the dial to the triangle unlocks the chest (%d turns)" % turns)
	# Opening it sets off the lamp beside it, like any contraption trigger.
	var reacted := []
	var on_react := func(id, from, effect, on): reacted.append([id, from, effect, on])
	Session.contraption_reacted.connect(on_react)
	_go("town", base + Vector2(0.8, 0.8))
	var opened := await _result(Session.use_puzzle(ids["puzzle_chest"]))
	ok(opened.get("ok", false) and opened.get("what") == "open" and opened["progress"]["open"], "the chest opens (%s)" % str(opened))
	await create_timer(0.8).timeout
	eq(reacted, [[ids["lamp_post"], ids["puzzle_chest"], "light", true]], "and the lamp next to it lights up")
	Session.contraption_reacted.disconnect(on_react)
	eq((await _result(Session.use_puzzle(ids["puzzle_chest"]))).get("error"), Puzzles.ERR_OPEN, "an open chest stays open")
	# Starting again: anyone in the place, from anywhere in it; not from somewhere else.
	eq((await _result(Session.reset_puzzle("i999:0:0"))).get("error"), Puzzles.ERR_NOT_HERE, "a puzzle is started again from its own place")
	_go("town", base + Vector2(9, 9))
	ok((await _result(Session.reset_puzzle("town"))).get("ok", false), "Start again works from anywhere in the place")
	eq(Session.puzzle_state("town"), Puzzles.fresh(Session.model, "town"), "the puzzle is fresh: key back, dial turned away, chest shut")
	# Replay, then an edit while half solved starts it again.
	_go("town", base + Vector2(3, 0.8))
	ok((await _result(Session.use_puzzle(ids["puzzle_key"]))).get("ok", false), "the key is found a second time")
	changes.clear()
	var moved := await _result(Session.move(ids["puzzle_key"], base + Vector2(3.5, 0), 0))
	ok(moved.get("ok", false), "the key is moved while it counts as found")
	ok(changes.size() == 1 and changes[0][1]["found"].is_empty(), "moving a part starts the puzzle again for everyone")
	changes.clear()
	await _place("bench", base + Vector2(-3, 3))
	eq(changes, [], "placing something else does not")
	# A second child helps the same puzzle, and leaving does not take progress away.
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": base.x + 3.5, "z": base.y + 0.8, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_puzzle(77, 0, ids["puzzle_key"])
	ok(Session.puzzles["town"]["found"].has(ids["puzzle_key"]), "a friend finds the key")
	Session._on_peer_disconnected(77)
	ok(Session.puzzles["town"]["found"].has(ids["puzzle_key"]), "and it stays found when the friend leaves")
	_go("town", base + Vector2(0.8, 2.6))
	for i in 4:
		if not Puzzles.progress(Session.model, "town", Session.puzzle_state("town"))["ready"]:
			await _result(Session.use_puzzle(ids["puzzle_dial"]))
	_go("town", base + Vector2(0.8, 0.8))
	ok((await _result(Session.use_puzzle(ids["puzzle_chest"]))).get("ok", false), "the chest is opened with a friend's key")
	eq(Session.puzzles["town"]["by"].size(), 2, "both names are kept")
	# Everyone leaves the place: an opened chest shuts by itself for the next visitor.
	var house: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0] if Session.model.items.values().any(func(i): return i["kind"] == "cottage") else {}
	if house.is_empty():
		house = Session.model.items[await _place("cottage", Session.model.find_free_spot("cottage", "town", Vector2(-10, -10)))]
	_go(TownModel.room_space(house["id"], 0, 0), TownModel.ROOM_SPAWN)
	ok(not Session.puzzles["town"]["open"] and Session.puzzles["town"]["found"].is_empty(), "with nobody left outdoors the opened puzzle is ready again")
	_go("town", base + Vector2(3.5, 0.8))
	# Save and load: the puzzle is there, its progress is not.
	ok((await _result(Session.use_puzzle(ids["puzzle_key"]))).get("ok", false), "progress before saving")
	ok(Session.save_now(), "the town is saved")
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	eq(Session.puzzles, {}, "a loaded town has no puzzle under way")
	eq(Puzzles.parts(Session.model, "town")["keys"], [ids["puzzle_key"]], "the puzzle itself is there")
	_go("town", base + Vector2(3.5, 0.8))
	ok((await _result(Session.use_puzzle(ids["puzzle_key"]))).get("ok", false), "and can be played again")
	# Putting every part away ends the puzzle; nothing is left behind.
	changes.clear()
	for k in ["puzzle_chest", "puzzle_key", "puzzle_dial", "puzzle_clue_triangle"]:
		ok((await _result(Session.remove(ids[k]))).get("ok", false), "%s is put away" % k)
	ok(not Session.puzzles.has("town") and not Session._puzzle_sig.has("town"), "no parts, no puzzle")
	ok(not changes.is_empty() and changes[-1][1].is_empty(), "and every device is told")
	Session.puzzle_changed.disconnect(on_change)
	Session.leave()


func test_ride_session() -> void:
	await process_frame
	var path := "user://test_rides.json"
	await _fresh_town(path)
	var me: int = Session.my_id
	# Free ground for a 3 x 2 ring (6 x 4 m).
	var origin := Vector2i(99, 99)
	for cx in range(-10, 8):
		for cz in range(2, 8):
			var pieces := _ring(cx, cz, 3, 2)
			if origin.x == 99 and pieces.all(func(p): return Session.model.check(p[0], "town", p[1].x * 2.0, p[1].y * 2.0, p[2]) == "") \
					and RideRules._solids(Session.model).all(func(s): return s[0].distance_to(Vector2(cx * 2.0 + 2.0, cz * 2.0 + 1.0)) > 4.5 + s[1]):
				origin = Vector2i(cx, cz)
	ok(origin.x != 99, "found room for a ring of rails")
	var pieces := _ring(origin.x, origin.y, 3, 2)
	var ids := []
	for p in pieces:
		ids.append(await _place(p[0], Vector2(p[1]) * 2.0, p[2]))
	var station: String = ids[0]
	var at := Vector2(pieces[0][1]) * 2.0
	var lap := 2.0 * 2 + 4 * PI * 0.5
	var log := []
	var on_ride := func(id, ride): log.append([id, ride.get("phase", "home"), ride.get("why", "")])
	Session.ride_changed.connect(on_ride)
	# Getting in.
	_go("town", at + Vector2(0, 9))
	eq((await _result(Session.ride(station, "board"))).get("error"), RideRules.ERR_WALK, "the cart is boarded from next to it")
	eq((await _result(Session.ride(station, "go"))).get("error"), RideRules.ERR_NOT_RIDING, "nobody starts a cart from outside")
	_go("town", at + Vector2(0, 1.6))
	var boarded := await _result(Session.ride(station, "board"))
	ok(boarded.get("ok", false) and boarded.get("end") == "loop" and boarded.get("pieces") == 6, "in the cart (%s)" % str(boarded))
	eq(Session.seats.get(station), {0: me}, "the cart's seat is an ordinary seat, taken")
	eq(Session.seat_of(me), [station, 0], "the child is seated")
	eq([Session.rides[station]["phase"], Session.ride_of(me)], ["ready", station], "the cart waits at its station")
	eq((await _result(Session.move(station, at + Vector2(0, 2), 0))).get("error"), "Someone is playing on it.", "the station cannot be moved under a rider")
	eq((await _result(Session.remove(station))).get("error"), "Someone is playing on it.", "or put away")
	# A second child cannot take the seat.
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": at.x, "z": at.y + 1.6, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_ride(77, 0, station, "board")
	eq(Session.seats.get(station), {0: me}, "a friend asking for the same cart does not get it")
	Session._srv_ride(77, 0, station, "go")
	eq(Session.rides[station]["phase"], "ready", "and cannot start it")
	Session._srv_sit(77, 0, station)
	eq(Session.seats.get(station), {0: me}, "the plain Sit request cannot take the seat either")
	# Go, stop, go.
	var went := await _result(Session.ride(station, "go"))
	ok(went.get("ok", false) and went.get("loop", false), "the cart sets off round the circuit")
	await create_timer(0.5).timeout
	var d := float(Session.ride_distance(station))
	ok(d > 0.8 and d < 2.0, "after half a second it is about 1.2 m along (%.2f m at %.1f m/s)" % [d, RideRules.SPEED])
	ok((await _result(Session.ride(station, "stop"))).get("ok", false), "Stop")
	var held := float(Session.ride_distance(station))
	await create_timer(0.3).timeout
	eq([Session.rides[station]["phase"], float(Session.ride_distance(station))], ["stopped", held], "the cart stands still where it stopped")
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "Go again")
	ok(absf(float(Session.rides[station]["end"]) - RideRules.LAPS * lap) < 0.001, "the ride is still %d laps" % RideRules.LAPS)
	# The rails change ahead of a moving cart: it rides to the new end and stops there.
	ok((await _result(Session.remove(ids[4]))).get("ok", false), "a rail far ahead is put away during the ride")
	eq([Session.rides[station]["phase"], Session.rides[station]["route"]["end"], Session.rides[station]["route"]["legs"].size()], ["moving", "end", 4], "the cart keeps going on what is left")
	Session.rides[station]["t"] -= 60000   # a minute later
	await process_frame
	await process_frame
	eq([Session.rides[station]["phase"], Session.rides[station]["why"]], ["stopped", "end"], "and stops by itself at the end of the rails")
	ok(absf(float(Session.ride_distance(station)) - RideRules.end_distance(Session.rides[station]["route"])) < 0.001, "a little before the last piece's end")
	eq((await _result(Session.ride(station, "go"))).get("error"), RideRules.ERR_END, "Go there says the rails end")
	ids[4] = await _place(pieces[4][0], Vector2(pieces[4][1]) * 2.0, pieces[4][2])
	eq(Session.rides[station]["route"]["end"], "loop", "the rail put back: the cart knows the circuit is whole")
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "and goes on")
	# The piece under the cart is taken away: it stops where it stands; putting the piece back mends it.
	var under: int = RideRules.locate(Session.rides[station]["route"], Session.ride_distance(station))["leg"]
	ok(under >= 1, "the cart is out on the rails (piece %d)" % under)
	ok((await _result(Session.remove(ids[under]))).get("ok", false), "the rail under the cart is put away")
	eq([Session.rides[station]["phase"], Session.rides[station]["why"]], ["stopped", "broken"], "the cart stops where it is")
	eq((await _result(Session.ride(station, "go"))).get("error"), RideRules.ERR_BROKEN, "and does not drive over bare ground")
	ids[under] = await _place(pieces[under][0], Vector2(pieces[under][1]) * 2.0, pieces[under][2])
	eq(Session.rides[station]["why"], "", "the rail put back under it")
	ok((await _result(Session.ride(station, "go"))).get("ok", false), "the cart goes on")
	# The end of the ride: at the station after the last lap, still seated, ready to go again.
	Session.rides[station]["t"] -= 120000
	await process_frame
	await process_frame
	eq([Session.rides[station]["phase"], Session.rides[station]["why"], float(Session.ride_distance(station))], ["ready", "lap", 0.0], "after its laps the cart is back at the station")
	eq(Session.seat_of(me), [station, 0], "the child is still in it")
	# Getting off frees the cart for the friend; the friend leaving the town frees it again.
	log.clear()
	ok((await _result(Session.stand())).get("ok", false), "Get off")
	ok(not Session.rides.has(station) and not Session.seats.has(station) and Session.seat_of(me).is_empty(), "the cart is home and empty")
	eq(log, [[station, "home", ""]], "every device is told the cart is home")
	Session._srv_ride(77, 0, station, "board")
	Session._srv_ride(77, 0, station, "go")
	eq([Session.seats.get(station), Session.rides[station]["phase"]], [{0: 77}, "moving"], "now the friend rides")
	eq((await _result(Session.ride(station, "board"))).get("error"), RideRules.ERR_TAKEN, "and this child waits for the cart")
	Session._on_peer_disconnected(77)
	ok(not Session.rides.has(station) and not Session.seats.has(station) and not Session.players.has(77), "the friend's connection drops mid-ride: no rider, no ghost, the cart is home")
	ok((await _result(Session.ride(station, "board"))).get("ok", false), "the cart can be boarded again at once")
	# Sitting somewhere else leaves the cart.
	var bench := await _place("bench", Session.model.find_free_spot("bench", "town", at + Vector2(0, 5)))
	ok((await _result(Session.sit(bench))).get("ok", false), "sitting on a bench from the cart")
	ok(not Session.rides.has(station) and Session.seat_of(me) == [bench, 0], "one seat per child: the cart went home")
	await _result(Session.stand())
	# Save and load: rails stay, no ride is under way.
	_go("town", at + Vector2(0, 1.6))
	await _result(Session.ride(station, "board"))
	await _result(Session.ride(station, "go"))
	ok(Session.save_now(), "saved during a ride")
	ok(not FileAccess.get_file_as_string(path).contains("\"rides\"") and not FileAccess.get_file_as_string(path).contains("\"phase\""), "a ride is not in the save")
	Session.ride_changed.disconnect(on_ride)
	Session.leave()
	Session.start_solo(path, Avatar.PRESETS[0])
	await process_frame
	eq([Session.rides, Session.seats], [{}, {}], "a loaded town has every cart at home")
	eq(RideRules.route(Session.model, station)["end"], "loop", "and the circuit as it was built")
	Session.leave()
