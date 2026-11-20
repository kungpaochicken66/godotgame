## The evening lamplighter walk (design/town-evenings-and-more.md): a child lights
## lamp posts by hand, and when the evening bell has rung and every lamp post in
## town is lit, the fireflies gather, once that evening, for everyone.
##
## Optional and cozy: nothing counts what is missing, nothing is timed, and a lamp
## can be put out again. A lamp lit by hand is the same as one a contraption
## switched on (TownModel.set_lamp_on): it shines by day too and is saved.
## Pure rules, unit-tested; the authority applies them.
extends RefCounted

const KIND := "lamp_post"
## Lighting a lamp needs the child this close.
const REACH := 2.2

const ERR_NOT_HERE := "That lamp is not here."
const ERR_WALK := "Walk to the lamp to light it."


## Lamp posts outdoors that can be lit (not wrapped), oldest first.
static func posts(model) -> Array:
	var out: Array = model.items_in("town").filter(func(i): return i["kind"] == KIND and not i.has("gift"))
	out.sort_custom(func(a, b): return int(a["id"].substr(1)) < int(b["id"].substr(1)))
	return out.map(func(i): return i["id"])


## Can this child light or put out this lamp now? "" or the reason.
static func check(model, id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(id, {})
	if it.is_empty() or it["kind"] != KIND or it.has("gift"):
		return ERR_NOT_HERE
	if it["space"] != actor_space or Vector2(it["x"], it["z"]).distance_to(actor_pos) > REACH:
		return ERR_WALK
	return ""


## Is every lamp post in town lit (and is there at least one)?
static func all_lit(model) -> bool:
	var ids := posts(model)
	return not ids.is_empty() and ids.all(func(id): return bool(model.items[id].get("on", false)))


## How many lamp posts are lit, and how many there are: [lit, all].
static func count(model) -> Array:
	var ids := posts(model)
	return [ids.filter(func(id): return bool(model.items[id].get("on", false))).size(), ids.size()]
