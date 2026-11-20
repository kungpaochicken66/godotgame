## First steps (design/experience-plan.md, issue 1): what a child who is new on this
## device is told in the first minute, one short line at a time: how to walk, that
## Decorate is how to build, and where ideas to play are. Each line goes away once the
## child has done it; after the last, the guide never shows again. It can be hidden.
##
## Pure state, unit-tested. Kept in the device's settings (not in the town, not on the
## server): it is about this child on this device, not about the town.
extends RefCounted

const STEPS := ["walk", "build", "guide"]
## Walking this far from where the child arrived counts as having walked.
const WALK_METERS := 2.5
const PRAISE := "You know the basics. Have fun building!"


static func fresh() -> Dictionary:
	return {"walk": false, "build": false, "guide": false, "hidden": false}


## The state for a device with nothing stored yet. A child who has already built here before this
## guide existed (the toy box remembers recent things) is not treated as a beginner.
static func initial(has_built_before: bool) -> Dictionary:
	var st := fresh()
	if has_built_before:
		for s in STEPS:
			st[s] = true
	return st


## Any stored value made into a valid state (missing or wrong entries count as not done).
static func sanitize(v) -> Dictionary:
	var st := fresh()
	if typeof(v) == TYPE_DICTIONARY:
		for k in st:
			if typeof(v.get(k)) == TYPE_BOOL:
				st[k] = v[k]
	return st


## The step to show now, or "" (all done, or hidden by the child).
static func current(st: Dictionary) -> String:
	if st.get("hidden", false):
		return ""
	for s in STEPS:
		if not st.get(s, false):
			return s
	return ""


static func all_done(st: Dictionary) -> bool:
	return STEPS.all(func(s): return st.get(s, false))


## Marks a step done. Returns whether that changed anything. Steps can be done in any
## order (a child who opens Decorate first is not made to walk first).
static func mark(st: Dictionary, step: String) -> bool:
	if not STEPS.has(step) or st.get(step, false):
		return false
	st[step] = true
	return true


## The line for a step. `stick`: a controller is in use. `toybox`: the toy box is open.
static func line(step: String, stick := false, toybox := false) -> String:
	match step:
		"walk":
			return "Move with the left stick." if stick else "Tap the ground to walk there."
		"build":
			return "Pick a thing, then choose Place here." if toybox else "Open Decorate to build something."
		"guide":
			return "Open Activities for ideas to play."
	return ""


static func icon(step: String) -> String:
	return {"walk": "stand", "build": "decorate", "guide": "guide"}.get(step, "guide")
