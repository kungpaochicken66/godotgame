## A living town (design/contraptions-and-town-life.md): what the animal friends
## do with the things children place outdoors. Pure rules, unit-tested; the
## animal brain (core/animal_brain.gd) asks here what is worth walking to.
##
## Each attraction is a kind of thing, an optional condition, what the animal
## does there and how much each species cares. Nothing is consumed, scored or
## required: an animal uses a thing for a little while and wanders on.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")

## Conditions ("needs"):
##   "on"      the thing is switched on (a playing music box)
##   "lit"     it is evening, or a contraption switched the lamp on
##   "rain"    it is raining
##   "dry"     it is not raining
##   "active"  the thing was just set off (bubbles blowing, a pinwheel spinning)
## "on_top": the animal goes onto the (flat) thing instead of beside it.
## "say": the line shown over the animal and on its card (%s is its name).
const ATTRACTIONS := [
	{"why": "music", "kinds": ["music_box"], "needs": "on", "action": "dance", "seconds": [6.0, 9.0],
		"say": "%s loves this music!", "fans": {"sheep": 3.0, "pig": 1.0, "rabbit": 1.0, "dog": 1.0, "elephant": 1.0}},
	{"why": "snack", "kinds": ["snack_tray", "snack_cookie", "snack_sandwich", "snack_juice"], "needs": "", "action": "sniff", "seconds": [4.0, 6.0],
		"say": "%s smells a snack!", "fans": {"pig": 3.0, "dog": 1.5, "elephant": 1.0}},
	{"why": "picnic", "kinds": ["blanket"], "needs": "dry", "action": "rest", "seconds": [6.0, 9.0], "on_top": true,
		"say": "%s is having a picnic.", "fans": {"dog": 2.0, "sheep": 1.5, "pig": 1.0, "rabbit": 1.0}},
	{"why": "shade", "kinds": ["garden_umbrella"], "needs": "dry", "action": "rest", "seconds": [5.0, 8.0],
		"say": "%s likes the shade.", "fans": {"rabbit": 2.0, "sheep": 1.0, "dog": 1.0}},
	{"why": "rain", "kinds": ["garden_umbrella"], "needs": "rain", "action": "look", "seconds": [7.0, 10.0],
		"say": "%s is keeping dry.", "fans": {"rabbit": 3.0, "sheep": 3.0, "dog": 2.0, "elephant": 1.0}},
	{"why": "lamp", "kinds": ["lamp_post"], "needs": "lit", "action": "rest", "seconds": [6.0, 9.0],
		"say": "%s likes the cozy light.", "fans": {"elephant": 2.0, "sheep": 1.5, "rabbit": 1.0, "pig": 1.0, "dog": 1.0}},
	{"why": "bubbles", "kinds": ["bubble_machine"], "needs": "active", "action": "greet", "seconds": [4.0, 6.0],
		"say": "%s loves the bubbles!", "fans": {"elephant": 3.0, "dog": 2.0, "pig": 1.5, "rabbit": 1.0, "sheep": 1.0}},
	{"why": "pinwheel", "kinds": ["pinwheel"], "needs": "active", "action": "look", "seconds": [4.0, 6.0],
		"say": "%s is watching it spin.", "fans": {"rabbit": 2.5, "elephant": 2.0, "dog": 1.0}},
]
## Reasons that are not attractions: a thing that was just placed, a rolling toy-track ball.
const SAY := {"new": "%s wonders what this is.", "ball": "%s is watching the ball roll."}
## At most this many animals use one thing at a time (the others pick something else).
const CROWD := 2


## The line for a reason (untranslated; %s is the animal's name), or "".
static func say(why: String) -> String:
	if SAY.has(why):
		return SAY[why]
	for a in ATTRACTIONS:
		if a["why"] == why:
			return a["say"]
	return ""


static func _holds(needs: String, item: Dictionary, model, active: Dictionary) -> bool:
	match needs:
		"on": return bool(item.get("on", false))
		"lit": return model.evening or bool(item.get("on", false))
		"rain": return model.weather == "rain"
		"dry": return model.weather != "rain"
		"active": return active.has(item["id"])
	return true


## The attraction this species finds in this thing right now, or {}.
## active: {item id: anything} for things that were just set off.
static func attraction(model, species: String, item: Dictionary, active := {}) -> Dictionary:
	if item.is_empty() or item["space"] != "town" or item.has("gift"):
		return {}
	for a in ATTRACTIONS:
		if a["kinds"].has(item["kind"]) and a["fans"].has(species) and _holds(a["needs"], item, model, active):
			return a
	return {}


## Everything outdoors this species would use now:
## [{"id", "why", "action", "seconds": [min, max], "on_top", "weight"}], in item order.
## busy: {item id: how many animals use it already}.
static func options(model, species: String, active := {}, busy := {}) -> Array:
	var out := []
	for item in model.items_in("town"):
		if int(busy.get(item["id"], 0)) >= CROWD:
			continue
		var a := attraction(model, species, item, active)
		if not a.is_empty():
			out.append({"id": item["id"], "why": a["why"], "action": a["action"], "seconds": a["seconds"],
				"on_top": bool(a.get("on_top", false)), "weight": float(a["fans"][species])})
	return out


## How much a species cares about a reason (0 = not at all).
static func fondness(species: String, why: String) -> float:
	for a in ATTRACTIONS:
		if a["why"] == why:
			return float(a["fans"].get(species, 0.0))
	return 0.0
