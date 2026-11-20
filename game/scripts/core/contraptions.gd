## Contraptions (design/contraptions-and-town-life.md): things that set off other
## things. A trigger (a big button, a step pad, a toy-track bell, light or finish
## piece) sets off every reactor close to it; each reactor passes the spark on to
## the reactors close to it, one hop at a time, so a row of things becomes a chain.
##
## Pure rules, unit-tested. The authority runs a chain (Session) and every device
## draws it. Nothing can break: a chain touches each thing once, stops after
## MAX_STEPS, and a trigger rests for COOLDOWN_MS before it works again. There are
## no scores, goals or timers to beat.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")
const TrackRules := preload("res://scripts/core/track_rules.gd")

## Things closer than this (centre to centre, on the floor plan) are linked.
const LINK_REACH := 2.0
## A spark takes this long from one thing to the next.
const HOP_MS := 450
## A chain touches at most this many reactors.
const MAX_STEPS := 24
## A trigger works again after this long.
const COOLDOWN_MS := 1200
## Pressing the big button needs the child this close.
const PRESS_REACH := 2.0
## Standing this close to a step pad's centre presses it.
const PAD_REACH := 0.5

## Trigger kinds and how they are set off: "press" (the context action), "step"
## (a child, or an animal outdoors, walks onto it), "ball" (a rolling toy-track
## ball passes or arrives), "open" (a puzzle's treasure chest is opened, core/puzzles.gd), "cart"
## (a ridden cart passes over a signal rail, core/ride_rules.gd), "weather" (the weather changes).
const TRIGGERS := {"push_button": "press", "step_pad": "step",
	"track_bell": "ball", "track_light": "ball", "track_finish": "ball", "puzzle_chest": "open",
	"ride_signal": "cart", "weather_bell": "weather"}

## Every placeable thing with a lamp of its own (Catalog.LAMPS).
const LAMPS := Catalog.LAMPS

## What a reactor does when a spark reaches it:
##   "light"   a lamp switches on, or off if it was on (saved with the town)
##   "music"   a music box starts, or stops if it was playing (saved)
##   "roll"    a toy-track start rolls its ball (its bells, lights and finish are triggers again)
##   "spin"    a pinwheel spins for a few seconds
##   "bubbles" a bubble machine blows bubbles for a few seconds
const EFFECT_SECONDS := {"spin": 5.0, "bubbles": 5.0}


static func is_trigger(kind: String) -> bool:
	return TRIGGERS.has(kind)


static func effect_of(kind: String) -> String:
	if LAMPS.has(kind):
		return "light"
	match kind:
		"music_box": return "music"
		"track_start": return "roll"
		"pinwheel": return "spin"
		"bubble_machine": return "bubbles"
	return ""


static func is_reactor(kind: String) -> bool:
	return effect_of(kind) != ""


## Is this thing part of contraptions at all (for drawing links)?
static func takes_part(kind: String) -> bool:
	return is_trigger(kind) or is_reactor(kind)


static func _usable(it: Dictionary) -> bool:
	return not it.is_empty() and not it.has("gift")


static func _at(it: Dictionary) -> Vector2:
	return Vector2(it["x"], it["z"])


## The reactors a spark jumps to from this thing: same space, within LINK_REACH,
## nearest first (ties by id, so every device and every run agree).
static func linked(model, id: String) -> Array:
	var src: Dictionary = model.items.get(id, {})
	if not _usable(src):
		return []
	var found := []
	for it in model.items_in(src["space"]):
		if it["id"] == id or not _usable(it) or not is_reactor(it["kind"]):
			continue
		var d := _at(src).distance_to(_at(it))
		if d <= LINK_REACH + 0.001:
			found.append([snappedf(d, 0.001), int(it["id"].substr(1)), it["id"]])
	found.sort()
	return found.map(func(f): return f[2])


## Every link in a space, for the dotted lines shown while decorating:
## [[from id, to id]], a trigger to each reactor near it and each pair of
## neighbouring reactors once.
static func links(model, space: String) -> Array:
	var out := []
	for it in model.items_in(space):
		if not _usable(it) or not takes_part(it["kind"]):
			continue
		for to in linked(model, it["id"]):
			var other: Dictionary = model.items[to]
			if is_reactor(it["kind"]) and int(other["id"].substr(1)) < int(it["id"].substr(1)):
				continue   # a reactor pair is listed from its lower id only
			out.append([it["id"], to])
	return out


## The whole chain a trigger would set off right now, in order:
## [{"id", "from", "hop" (1 = straight from the trigger), "effect"}].
## The authority walks the same way one hop at a time (so a chain follows what
## the town looks like when each spark lands); this preview is for hints and tests.
static func plan(model, trigger_id: String) -> Array:
	var out := []
	var seen := {trigger_id: true}
	var frontier := [trigger_id]
	var hop := 1
	while not frontier.is_empty() and out.size() < MAX_STEPS:
		var next := []
		for from in frontier:
			for to in linked(model, from):
				if seen.has(to) or out.size() >= MAX_STEPS:
					continue
				seen[to] = true
				out.append({"id": to, "from": from, "hop": hop, "effect": effect_of(model.items[to]["kind"])})
				next.append(to)
		frontier = next
		hop += 1
	return out


## Can this child press this button now? "" or the reason.
static func check_press(model, id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(id, {})
	if not _usable(it) or TRIGGERS.get(it["kind"], "") != "press":
		return "That button is not here."
	if it["space"] != actor_space or _at(it).distance_to(actor_pos) > PRESS_REACH:
		return "Walk to the button to press it."
	return ""


## The step pads someone standing at `pos` is on.
static func pads_under(model, space: String, pos: Vector2) -> Array:
	var out := []
	for it in model.items_in(space):
		if it["kind"] == "step_pad" and _usable(it) and _at(it).distance_to(pos) <= PAD_REACH:
			out.append(it["id"])
	return out


## When a rolling ball sets off the bell, light and finish pieces of its route:
## [[milliseconds after the roll starts, piece id]].
static func ball_triggers(model, route: Dictionary) -> Array:
	var out := []
	var ids: Array = route.get("bells", []).duplicate()
	if route.get("finish", "") != "":
		ids.append(route["finish"])
	var cells: Array = route.get("cells", [])
	for id in ids:
		var it: Dictionary = model.items.get(id, {})
		if it.is_empty():
			continue
		var at := cells.find(Vector2(TrackRules.cell_of(it)))
		if at >= 0:
			out.append([roundi(at * TrackRules.CELL_SECONDS * 1000.0), id])
	return out
