## Play ideas for ages 8-12 (design/playability-8-12.md): snack stand (F01) and
## "On display" protection (F10). Pure rules, unit-tested; the authority applies
## them and clients only ask. No prices, scores, timers or penalties.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")
const TownModel := preload("res://scripts/core/town_model.gd")

## Standing this close to a tray or a snack counts as "at it".
const REACH := 2.0
## A shared snack makes everyone this close cheer.
const SHARE_REACH := 5.0
## Snack bases (the item made) and toppings (the item's paint color index).
const BASES := ["snack_cookie", "snack_sandwich", "snack_juice"]
const TOPPINGS := {"berry": 2, "honey": 1, "mint": 5}
const TOPPING_ORDER := ["berry", "honey", "mint"]
## Topping names per base, as the picture card shows them.
const TOPPING_NAMES := {"berry": "Berry", "honey": "Honey", "mint": "Mint"}


static func is_snack(kind: String) -> bool:
	return BASES.has(kind)


## Can this child make this snack at this tray now?
static func check_snack(model, tray_id: String, base: String, topping: String, actor_space: String, actor_pos: Vector2) -> String:
	var tray: Dictionary = model.items.get(tray_id, {})
	if tray.is_empty() or tray["kind"] != "snack_tray" or tray.has("gift"):
		return "That snack tray is not here."
	if not BASES.has(base) or not TOPPINGS.has(topping):
		return "That snack is not on the card."
	if tray["space"] != actor_space or Vector2(tray["x"], tray["z"]).distance_to(actor_pos) > REACH:
		return "Stand next to the snack tray to make a snack."
	return ""


## Puts the snack next to the tray (on the floor; the child may move it onto a table).
static func make_snack(model, tray_id: String, base: String, topping: String) -> Dictionary:
	var tray: Dictionary = model.items.get(tray_id, {})
	if tray.is_empty():
		return {}
	var front: Vector2 = Vector2(tray["x"], tray["z"]) + model.facing(tray["rot"]) * 0.6
	var spot = model.find_free_spot(base, tray["space"], front)
	if spot == null:
		return {}
	var r: Dictionary = model.place(base, tray["space"], spot.x, spot.y, tray["rot"], TOPPINGS[topping])
	return r.get("item", {}) if r.get("ok", false) else {}


## Sharing a snack: it must be a snack in the child's space, within reach.
static func check_share(model, snack_id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(snack_id, {})
	if it.is_empty() or not is_snack(it["kind"]) or it.has("gift"):
		return "That snack is not here."
	if it["space"] != actor_space or Vector2(it["x"], it["z"]).distance_to(actor_pos) > REACH + 0.4:
		return "Walk to the snack to share it."
	return ""


## "On display": changing a space someone else put on display is refused until
## it is taken off display (the client asks first). "" when the change is fine.
static func display_error(model, space: String, pid: String) -> String:
	var d: Dictionary = model.display_by(space)
	if d.is_empty() or d.get("pid", "") == pid or d.get("helpers", []).has(pid):
		return ""   # friends who joined a "Please help me edit" invitation may change it too
	return "This place is on display."


## Which space an edit of this item touches.
static func item_space(model, id: String) -> String:
	return model.items.get(id, {}).get("space", "")


# ------------------------------------------------------------- trails (F06)

## Each trail sign shows one clue: do this emote next to it.
const CLUES := ["wave", "cheer", "dance", "heart"]
## A trail needs at least this many signs to follow.
const MIN_TRAIL := 2
## Standing this close to a sign counts as "at the sign".
const TRAIL_REACH := 2.2
## Children who finish within this many seconds share one keepsake sticker.
const KEEPSAKE_WINDOW := 120


static func clue_of(sign: Dictionary) -> String:
	return CLUES[posmod(int(sign.get("variant", 0)), CLUES.size())]


## Can this child start following the trail?
static func check_follow(model, actor_space: String) -> String:
	if actor_space != "town":
		return "Trails are outdoors."
	if model.trail_signs().size() < MIN_TRAIL:
		return "A trail needs at least two signs."
	return ""


## Does this emote here complete the next sign (index `progress` in walking order)?
static func trail_step(model, progress: int, actor_space: String, actor_pos: Vector2, emote: String) -> bool:
	var signs: Array = model.trail_signs()
	if actor_space != "town" or progress < 0 or progress >= signs.size():
		return false
	var s: Dictionary = signs[progress]
	return Vector2(s["x"], s["z"]).distance_to(actor_pos) <= TRAIL_REACH and clue_of(s) == emote


## A child finished the trail: add them to a recent keepsake, or start a new one.
static func add_keepsake(model, nick: String, now: int) -> Dictionary:
	if not model.keepsakes.is_empty():
		var last: Dictionary = model.keepsakes[-1]
		if last["kind"] == "trail" and now - int(last["t"]) <= KEEPSAKE_WINDOW:
			if not last["by"].has(nick):
				last["by"].append(nick)
			return last
	var k := {"kind": "trail", "by": [nick], "t": now}
	model.keepsakes.append(k)
	if model.keepsakes.size() > 24:
		model.keepsakes.pop_front()
	return k


# ------------------------------------------------------------- music box (F08)

## Rows of a music box tune, top to bottom.
const SOUNDS := ["bell", "drum", "chime", "bass"]
const SOUND_NAMES := {"bell": "Bell", "drum": "Drum", "chime": "Chime", "bass": "Bass"}
## One step every 300 ms (100 steps a minute); every device counts steps from
## its own clock, so friends hear the same loop without any network traffic.
const STEP_MS := 300
## Editing the tune needs the child next to the box; it is heard this far away.
const MUSIC_REACH := 2.6
const HEAR := 9.0


static func music_step(msec: int) -> int:
	return int(msec / STEP_MS) % 8


## The sounds a tune plays on this step.
static func notes_at(song: Array, step: int) -> Array:
	var out := []
	for r in SOUNDS.size():
		if r < song.size() and int(song[r]) & (1 << step):
			out.append(SOUNDS[r])
	return out


static func check_music(model, id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(id, {})
	if it.is_empty() or it["kind"] != "music_box" or it.has("gift"):
		return "That music box is not here."
	if it["space"] != actor_space or Vector2(it["x"], it["z"]).distance_to(actor_pos) > MUSIC_REACH:
		return "Walk to the music box to play it."
	return ""
