## Friend echoes (design/town-evenings-and-more.md): a child leaves a "hello" for friends
## who are not online: three emotes at a spot, shown as a pale, see-through figure in the child's
## own look. A friend who comes by can answer with one emote; the child sees the answers
## on a later visit.
##
## Bounded on purpose. These bounds are implementation defaults chosen by the coordinator within its
## delegated routine decisions and relayed on 2026-11-13; the user has not reviewed them personally.
##   - one echo per player per town; a new one replaces the old
##   - three emotes from the fixed list; one answer per friend, one emote
##   - the creator can take it away; it disappears by itself after seven days
##   - names and looks come from the game's fixed lists (Avatar.sanitize); nothing typed,
##     no sound, no real-world place or time of day, only "how many days are left"
##   - at most MAX_ECHOES in a town and MAX_ANSWERS on one echo (the oldest make room)
## Saved with the town under the optional key "echoes" (absent when there are none).
## Pure rules, unit-tested; the authority applies them.
extends RefCounted

const Avatar := preload("res://scripts/core/avatar.gd")

const EMOTES := ["wave", "cheer", "dance", "heart"]
const LENGTH := 3
const LIFETIME := 7 * 24 * 3600
const MAX_ECHOES := 12
const MAX_ANSWERS := 8
## Answering needs the child this close to the figure.
const REACH := 2.8

const ERR_EMOTES := "Pick three emotes for a hello."
const ERR_PLACE := "A hello cannot be left here."
const ERR_GONE := "That hello is gone."
const ERR_OWN := "This is your own hello."
const ERR_WALK := "Walk to the hello to answer it."
const ERR_EMOTE := "Pick one emote to answer."


static func _valid_emotes(v) -> bool:
	if typeof(v) != TYPE_ARRAY or v.size() != LENGTH:
		return false
	for e in v:
		if typeof(e) != TYPE_STRING or not EMOTES.has(e):
			return false
	return true


## Leaves (or replaces) this player's echo. Returns {"ok", "error", "echo"}.
static func leave(model, pid: String, avatar: Dictionary, space: String, pos: Vector2, ry: float, emotes, now: int) -> Dictionary:
	if not _valid_emotes(emotes):
		return {"ok": false, "error": ERR_EMOTES}
	if pid == "" or not model.is_space(space):
		return {"ok": false, "error": ERR_PLACE}
	var clean: Dictionary = Avatar.sanitize(avatar)
	model.echoes[pid] = {"nick": str(clean["nick"]).left(16), "avatar": clean, "space": space, "x": snappedf(pos.x, 0.05), "z": snappedf(pos.y, 0.05),
		"ry": snappedf(ry, 0.01), "emotes": Array(emotes).duplicate(), "t": now, "answers": {}}
	while model.echoes.size() > MAX_ECHOES:
		var oldest := ""
		for p in model.echoes:
			if p != pid and (oldest == "" or int(model.echoes[p]["t"]) < int(model.echoes[oldest]["t"])):
				oldest = p
		model.echoes.erase(oldest)
	return {"ok": true, "echo": model.echoes[pid].duplicate(true)}


## The creator takes their echo away. Returns whether there was one.
static func remove(model, pid: String) -> bool:
	return model.echoes.erase(pid)


## Can this child answer that echo from where they stand? "" or the reason.
static func check_answer(model, owner_pid: String, pid: String, actor_space: String, actor_pos: Vector2, now: int) -> String:
	var e: Dictionary = model.echoes.get(owner_pid, {})
	if e.is_empty() or expired(e, now):
		return ERR_GONE
	if owner_pid == pid:
		return ERR_OWN
	if e["space"] != actor_space or Vector2(e["x"], e["z"]).distance_to(actor_pos) > REACH:
		return ERR_WALK
	return ""


## A friend's answer: one emote. A second answer from the same friend replaces their first.
static func answer(model, owner_pid: String, pid: String, nick: String, emote: String, now: int) -> Dictionary:
	if not EMOTES.has(emote):
		return {"ok": false, "error": ERR_EMOTE}
	var e: Dictionary = model.echoes.get(owner_pid, {})
	if e.is_empty():
		return {"ok": false, "error": ERR_GONE}
	e["answers"][pid] = {"nick": nick.left(16), "emote": emote, "t": now, "new": true}
	while e["answers"].size() > MAX_ANSWERS:
		var oldest := ""
		for p in e["answers"]:
			if p != pid and (oldest == "" or int(e["answers"][p]["t"]) < int(e["answers"][oldest]["t"])):
				oldest = p
		e["answers"].erase(oldest)
	return {"ok": true, "echo": e.duplicate(true)}


## The creator has looked at their answers: none is new any more. Returns whether anything changed.
static func mark_seen(model, pid: String) -> bool:
	var changed := false
	for a in model.echoes.get(pid, {}).get("answers", {}).values():
		if a.get("new", false):
			a["new"] = false
			changed = true
	return changed


static func new_answers(model, pid: String) -> Array:
	var out := []
	for a in model.echoes.get(pid, {}).get("answers", {}).values():
		if a.get("new", false):
			out.append(a["nick"])
	return out


static func expired(e: Dictionary, now: int) -> bool:
	return now - int(e.get("t", 0)) >= LIFETIME


## Whole days an echo still stays (at least 1 while it is there).
static func days_left(e: Dictionary, now: int) -> int:
	return maxi(1, ceili((LIFETIME - (now - int(e.get("t", 0)))) / 86400.0))


## Drops echoes that are older than seven days or whose place is gone (its house was put away).
## Returns whether anything was dropped.
static func prune(model, now: int) -> bool:
	var changed := false
	for pid in model.echoes.keys():
		var e: Dictionary = model.echoes[pid]
		if expired(e, now) or not model.is_space(str(e.get("space", ""))):
			model.echoes.erase(pid)
			changed = true
	return changed


## The echo nearest to a point in a space, within reach: its owner's player id, or "".
static func near(model, space: String, pos: Vector2, reach := REACH) -> String:
	var best := ""
	var best_d := reach
	var pids: Array = model.echoes.keys()
	pids.sort()
	for pid in pids:
		var e: Dictionary = model.echoes[pid]
		var d := Vector2(e["x"], e["z"]).distance_to(pos)
		if e["space"] == space and d <= best_d:
			best_d = d
			best = pid
	return best


## Echoes from a save or from the authority, made safe: wrong shapes dropped, texts cut,
## emotes from the list only, counts bounded. Places are checked by prune() once the town is loaded.
static func sanitize(v) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for pid in v:
		var e = v[pid]
		if out.size() >= MAX_ECHOES or typeof(e) != TYPE_DICTIONARY or not _valid_emotes(e.get("emotes")) or typeof(e.get("avatar")) != TYPE_DICTIONARY:
			continue
		var clean: Dictionary = Avatar.sanitize(e["avatar"])
		var answers := {}
		if typeof(e.get("answers")) == TYPE_DICTIONARY:
			for ap in e["answers"]:
				var a = e["answers"][ap]
				if answers.size() < MAX_ANSWERS and typeof(a) == TYPE_DICTIONARY and EMOTES.has(str(a.get("emote", ""))):
					answers[str(ap).left(64)] = {"nick": str(a.get("nick", "")).left(16), "emote": str(a["emote"]), "t": int(a.get("t", 0)),
						"new": typeof(a.get("new")) == TYPE_BOOL and a["new"]}
		out[str(pid).left(64)] = {"nick": str(clean["nick"]).left(16), "avatar": clean, "space": str(e.get("space", "town")),
			"x": float(e.get("x", 0.0)), "z": float(e.get("z", 0.0)), "ry": float(e.get("ry", 0.0)),
			"emotes": Array(e["emotes"]).map(func(s): return str(s)), "t": int(e.get("t", 0)), "answers": answers}
	return out
