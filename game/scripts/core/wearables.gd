## Wearable clothing (r12): the accepted catalog, slots and conflicts, which baked parts of the
## child each slot replaces, and the per-pose state (seated variants, held items). Pure rules,
## unit-tested. The contract is the Modeling lane's EQUIP_HANDOFF.md (sections 1-9) and its rig
## replica kid_rig.gd (HIDES, BAND_HATS, equip_state); the data comes from frozen batches only
## (scripts/build_wear_catalog.py -> res://data/wearables.json). docs/wearables.md.
extends RefCounted

const PATH := "res://data/wearables.json"
## Slots in the order the wardrobe shows them; "dress" occupies top and bottom.
const SLOTS := ["top", "bottom", "dress", "head", "face", "socks", "shoes", "bag", "hand"]
const CATEGORIES := ["Tops", "Bottoms", "Dress-up", "Headwear", "Accessories", "Socks", "Shoes", "Bags", "Umbrellas"]
## Baked child parts a worn slot replaces (kid_rig.gd HIDES): outfit_body = every baked torso
## outfit part, outfit_body_low = those below y 0.5 (shorts, overall bottom, skirt), outfit_arm =
## sleeves, outfit_leg = trouser cuffs on the legs, shoe = baked shoes, hair = all hair incl. the cap.
const HIDES := {"top": ["outfit_body", "outfit_arm"], "dress": ["outfit_body", "outfit_arm", "outfit_leg"],
	"bottom": ["outfit_body_low", "outfit_leg"], "shoes": ["shoe"], "head": ["hair"]}
## Anims that show seated variants (EQUIP_HANDOFF 9).
const SEATED_ANIMS := ["sit", "rest", "ride", "swing"]
## Hold envelope for the right arm while a held item shows (radians, kid.gd pivots).
const HOLD_X := Vector2(-0.6, 0.6)
const HOLD_Z := Vector2(0.0, 0.05)
## Seated-arm contract while a seated variant shows in sit/rest: arms forward over the knees.
const SIT_HANDS_X := -1.1

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var j := JSON.new()
		if FileAccess.file_exists(PATH) and j.parse(FileAccess.get_file_as_string(PATH)) == OK and j.data is Dictionary:
			_data = j.data
		else:
			_data = {"items": {}, "gated": {}}
	return _data


static func items() -> Dictionary:
	return data().get("items", {})


static func gated() -> Dictionary:
	return data().get("gated", {})


static func has(id: String) -> bool:
	return items().has(id)


static func get_def(id: String) -> Dictionary:
	return items().get(id, {})


static func glb(id: String) -> String:
	return "res://assets/wearables/%s.glb" % id


## Accepted ids of one wardrobe category, by English name.
static func ids_in(category: String) -> Array:
	var out := items().keys().filter(func(k): return items()[k]["category"] == category)
	out.sort_custom(func(a, b): return items()[a]["name"].naturalnocasecmp_to(items()[b]["name"]) < 0)
	return out


## A worn set from saved or received data: only accepted ids in their own slot; a dress-up wins
## over a top and a bottom (it occupies both). Unknown or gated ids are dropped.
static func sanitize(v) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for slot in SLOTS:
		var id := str(v.get(slot, ""))
		if id != "" and has(id) and get_def(id)["slot"] == slot:
			out[slot] = id
	if out.has("dress"):
		out.erase("top")
		out.erase("bottom")
	return out


## Puts on (or, with id "", takes off a slot's) item. Returns {"ok", "wear", "error"}.
static func equip(wear: Dictionary, slot: String, id: String) -> Dictionary:
	var w := sanitize(wear)
	if not SLOTS.has(slot):
		return {"ok": false, "wear": w, "error": "That is not a place to wear things."}
	if id == "":
		w.erase(slot)
		return {"ok": true, "wear": w, "error": ""}
	if gated().has(id):
		return {"ok": false, "wear": w, "error": "That one is not ready to wear yet."}
	if not has(id) or get_def(id)["slot"] != slot:
		return {"ok": false, "wear": w, "error": "That is not in the wardrobe."}
	w[slot] = id
	if slot == "dress":
		w.erase("top")
		w.erase("bottom")
	elif slot == "top" or slot == "bottom":
		w.erase("dress")
	return {"ok": true, "wear": w, "error": ""}


## The baked parts to leave out of the child for this worn set.
static func hides(wear: Dictionary) -> Array:
	var out := []
	for slot in wear:
		if slot == "head" and get_def(wear[slot]).get("band", false):
			continue   # crowns, flower bands, clips, ears, boppers sit on the hair
		for h in HIDES.get(slot, []):
			if not out.has(h):
				out.append(h)
	return out


static func has_sit_variant(wear: Dictionary) -> bool:
	return wear.values().any(func(id): return get_def(id).get("sit", false))


## Per-frame state (EQUIP_HANDOFF 9 precedence) for the body anim (emotes are applied on top by kid.gd).
## {"seated": show *_sit meshes, "sit_hands": arms forward (-1.1), "held_visible", "hold": keep the
## right arm in the hold envelope and play emotes on the left arm}.
static func pose_state(anim: String, wear: Dictionary) -> Dictionary:
	var variant := has_sit_variant(wear) and SEATED_ANIMS.has(anim)
	var st := {"seated": variant, "sit_hands": variant and (anim == "sit" or anim == "rest"), "held_visible": false, "hold": false}
	if not wear.has("hand"):
		return st
	var bag: bool = get_def(wear["hand"]).get("category", "") == "Bags"
	if st["sit_hands"]:
		return st                                  # 1. seated-arm contract wins: held item hidden
	if anim == "ride" or anim == "swing":
		return st                                  # ArmR is on the handle or the ropes: hidden
	if (anim == "sit" or anim == "rest") and bag:
		return st                                  # bags hide while seated
	st["held_visible"] = true
	st["hold"] = true                              # 2. hold envelope; emotes play on the left arm
	return st
