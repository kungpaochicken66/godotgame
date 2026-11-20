## Puzzle rooms (design/puzzle-rooms-and-rides.md): a child hides keys and clue
## cards, sets up picture dials and a treasure chest; friends find the keys, turn
## each dial to the picture on the clue card of its color, and open the chest.
##
## One puzzle per space (a room, or the town outdoors): every puzzle part in the
## space belongs to it. The puzzle itself is ordinary saved items; progress (keys
## found, what each dial shows, the chest open) is shared by everyone in the town,
## kept by the authority and not saved, so a loaded town starts with its puzzles
## ready to play.
##
## Pure rules, unit-tested. Nothing here can lock a door, trap a child or be lost:
## a key that is found goes to the chest (nobody carries it), anyone may start the
## puzzle again, and a part that is moved, painted, wrapped or put away simply
## starts the puzzle again as the town is now. No scores, timers or penalties.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")

const CHEST := "puzzle_chest"
const KEY := "puzzle_key"
const DIAL := "puzzle_dial"
## Clue cards, one kind per picture, in the order a dial shows them.
const CLUES := ["puzzle_clue_circle", "puzzle_clue_square", "puzzle_clue_triangle", "puzzle_clue_flower"]
const PICTURES := ["circle", "square", "triangle", "flower"]
const KINDS := [CHEST, KEY, DIAL] + CLUES
## Picking up a key, turning a dial or using the chest needs the child this close.
const REACH := 2.2
## The most keys and dials one puzzle counts (more are decoration).
const MAX_KEYS := 6
const MAX_DIALS := 6
## Names kept with an opened chest.
const MAX_HELPERS := 4

const ERR_NOT_HERE := "That is not here."
const ERR_WALK := "Walk closer first."
const ERR_NO_CHEST := "Put a treasure chest in this place first."
const ERR_KEY_FOUND := "That key is already at the chest."
const ERR_LOCKED := "The chest is still locked. Look for keys and clue cards."
const ERR_OPEN := "The chest is open. Start again to play once more."


static func is_part(kind: String) -> bool:
	return KINDS.has(kind)


static func picture_of_clue(kind: String) -> int:
	return CLUES.find(kind)


static func _usable(it: Dictionary) -> bool:
	return not it.is_empty() and not it.has("gift")


static func _num(id: String) -> int:
	return int(id.substr(1))


static func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return _num(a["id"]) < _num(b["id"])


## The puzzle of a space as the town is now:
## {"chests": [ids], "keys": [ids], "dials": [{"id", "color", "target"}], "clues": [{"id", "color", "picture"}]}.
## Lists are in id order, so every device and every run agree. A dial counts only
## when a clue card of its color is in the space (its target is that card's
## picture; with several cards of one color, the oldest decides).
static func parts(model, space: String) -> Dictionary:
	var out := {"chests": [], "keys": [], "dials": [], "clues": []}
	var items: Array = model.items_in(space).filter(func(i): return _usable(i) and is_part(i["kind"]))
	items.sort_custom(_by_id)
	var clue_of := {}   # color -> picture
	for it in items:
		var pic := picture_of_clue(it["kind"])
		if pic >= 0:
			out["clues"].append({"id": it["id"], "color": int(it["color"]), "picture": pic})
			if not clue_of.has(int(it["color"])):
				clue_of[int(it["color"])] = pic
	for it in items:
		match it["kind"]:
			CHEST:
				out["chests"].append(it["id"])
			KEY:
				if out["keys"].size() < MAX_KEYS:
					out["keys"].append(it["id"])
			DIAL:
				if clue_of.has(int(it["color"])) and out["dials"].size() < MAX_DIALS:
					out["dials"].append({"id": it["id"], "color": int(it["color"]), "target": int(clue_of[int(it["color"])])})
	return out


## What a dial shows when a puzzle starts: never its answer, and the same on
## every device and every run (from its id).
static func start_picture(id: String, target: int) -> int:
	if target < 0:
		return 0
	return (target + 1 + _num(id) % (PICTURES.size() - 1)) % PICTURES.size()


## A puzzle ready to play: no key found, every dial off its answer, the chest shut.
static func fresh(model, space: String) -> Dictionary:
	var st := {"found": {}, "dials": {}, "open": false, "by": []}
	var targets := {}
	for d in parts(model, space)["dials"]:
		targets[d["id"]] = d["target"]
	for it in model.items_in(space):
		if it["kind"] == DIAL and _usable(it):
			st["dials"][it["id"]] = start_picture(it["id"], int(targets.get(it["id"], -1)))
	return st


## Everything about a space's puzzle parts that matters to the puzzle. When this
## changes (a part placed, moved, painted, wrapped or put away), the authority
## starts the puzzle again, so progress never points at things that are gone.
static func signature(model, space: String) -> String:
	var rows := []
	for it in model.items_in(space):
		if is_part(it["kind"]):
			rows.append([_num(it["id"]), it["kind"], snappedf(it["x"], 0.01), snappedf(it["z"], 0.01), int(it["color"]),
				str(it.get("host", "")), it.has("gift")])
	rows.sort()
	return var_to_str(rows) if not rows.is_empty() else ""


## Spaces that have any puzzle part.
static func spaces(model) -> Array:
	var seen := {}
	for it in model.items.values():
		if is_part(it["kind"]):
			seen[it["space"]] = true
	var out := seen.keys()
	out.sort()
	return out


## How far along a puzzle is: {"chest": bool, "keys", "keys_found", "dials", "dials_right", "ready", "open"}.
## "ready" means the chest can be opened now. A chest with no keys and no dials
## is ready at once (a plain treasure chest).
static func progress(model, space: String, st: Dictionary) -> Dictionary:
	var p := parts(model, space)
	var found := 0
	for id in p["keys"]:
		if st.get("found", {}).has(id):
			found += 1
	var right := 0
	for d in p["dials"]:
		if int(st.get("dials", {}).get(d["id"], -1)) == int(d["target"]):
			right += 1
	var has_chest: bool = not p["chests"].is_empty()
	var open: bool = has_chest and bool(st.get("open", false))
	return {"chest": has_chest, "keys": p["keys"].size(), "keys_found": found, "dials": p["dials"].size(), "dials_right": right,
		"ready": has_chest and not open and found == p["keys"].size() and right == p["dials"].size(), "open": open}


## Can this child use this puzzle part now? "" or the reason.
static func check_use(model, id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(id, {})
	if not _usable(it) or not it["kind"] in [CHEST, KEY, DIAL]:
		return ERR_NOT_HERE
	if it["space"] != actor_space or Vector2(it["x"], it["z"]).distance_to(actor_pos) > REACH:
		return ERR_WALK
	return ""


## A child uses a part (the caller checked check_use). Changes `st` and returns
## {"ok", "error", "what": "key" | "dial" | "open", "picture" (a dial's new picture)}.
##   key    it goes to the chest (needs a chest in the space; once per key)
##   dial   shows its next picture (not while the chest is open)
##   chest  opens when every key is found and every dial shows its clue's picture
static func use(model, st: Dictionary, id: String, nick := "") -> Dictionary:
	var it: Dictionary = model.items.get(id, {})
	if not _usable(it):
		return {"ok": false, "error": ERR_NOT_HERE}
	var space: String = it["space"]
	var p := progress(model, space, st)
	match it["kind"]:
		KEY:
			if not p["chest"]:
				return {"ok": false, "error": ERR_NO_CHEST}
			if st["found"].has(id) or p["open"]:
				return {"ok": false, "error": ERR_KEY_FOUND}
			if not parts(model, space)["keys"].has(id):
				return {"ok": false, "error": ERR_NOT_HERE}   # more keys than a puzzle counts
			st["found"][id] = true
			_add_helper(st, nick)
			return {"ok": true, "what": "key"}
		DIAL:
			if p["open"]:
				return {"ok": false, "error": ERR_OPEN}
			var next := (int(st["dials"].get(id, 0)) + 1) % PICTURES.size()
			st["dials"][id] = next
			_add_helper(st, nick)
			return {"ok": true, "what": "dial", "picture": next}
		CHEST:
			if p["open"]:
				return {"ok": false, "error": ERR_OPEN}
			if not p["ready"]:
				return {"ok": false, "error": ERR_LOCKED}
			st["open"] = true
			_add_helper(st, nick)
			return {"ok": true, "what": "open"}
	return {"ok": false, "error": ERR_NOT_HERE}


static func _add_helper(st: Dictionary, nick: String) -> void:
	if nick != "" and not st["by"].has(nick) and st["by"].size() < MAX_HELPERS:
		st["by"].append(nick)


## A state received from the authority or kept across an edit, made safe for
## this town: unknown ids dropped, every dial present, pictures in range.
static func sanitize(model, space: String, v) -> Dictionary:
	var st := fresh(model, space)
	if typeof(v) != TYPE_DICTIONARY:
		return st
	var p := parts(model, space)
	if typeof(v.get("found")) == TYPE_DICTIONARY:
		for id in v["found"]:
			if p["keys"].has(str(id)):
				st["found"][str(id)] = true
	if typeof(v.get("dials")) == TYPE_DICTIONARY:
		for id in v["dials"]:
			if st["dials"].has(str(id)):
				st["dials"][str(id)] = posmod(int(v["dials"][id]), PICTURES.size())
	st["open"] = typeof(v.get("open")) == TYPE_BOOL and v["open"] and not p["chests"].is_empty()
	if typeof(v.get("by")) == TYPE_ARRAY:
		for n in v["by"]:
			_add_helper(st, str(n).left(16))
	return st


## Pairs to join with a dotted line while decorating, so the puzzle reads as one
## thing: [[from id, to id, why]] with why "key" (a key to the chest), "clue" (a
## clue card to the dial of its color) or "dial" (a dial to the chest).
static func links(model, space: String) -> Array:
	var p := parts(model, space)
	var out := []
	if not p["chests"].is_empty():
		var chest: String = p["chests"][0]
		for id in p["keys"]:
			out.append([id, chest, "key"])
		for d in p["dials"]:
			out.append([d["id"], chest, "dial"])
	var first_clue := {}
	for c in p["clues"]:
		if not first_clue.has(c["color"]):
			first_clue[c["color"]] = c["id"]
	for d in p["dials"]:
		out.append([first_clue[d["color"]], d["id"], "clue"])
	return out
