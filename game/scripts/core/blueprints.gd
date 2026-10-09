## Blueprint cards (design/playability-8-12.md F09, r11): save a favorite group of
## things, preview it somewhere else, turn it, place it, then change any piece as
## usual. A blueprint is a starting point kept on this device, not a collectible.
## Pure rules, unit-tested; the authority places the pieces one by one with the
## normal rules, so nothing a blueprint does can break the town.
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const PATH := "user://blueprints.json"
## Names come from a fixed list (no free text in a children's game).
const NAMES := ["Picnic", "Café", "Little stage", "Garden corner", "Play corner", "Cozy nook", "Music corner", "Snack stand"]
const RADIUS := 2.5
const MAX_PIECES := 12
const MAX_SAVED := 12


## Can this item be part of a blueprint? (Houses, presents and wall or ceiling
## things stay out: they belong to one particular place.)
static func capturable(item: Dictionary) -> bool:
	return item["kind"] != "cottage" and not item.has("gift") and Catalog.anchor(item["kind"]) == "ground" \
		and Catalog.has(item["kind"])


## The group around a picked item: up to MAX_PIECES things within RADIUS of it in
## the same space, nearest first, plus anything sitting on a captured table.
## Pieces are stored relative to the picked item and its turn, so the blueprint
## can be placed anywhere at any turn. {"pieces": [{kind, dx, dz, rot, color, variant, on}]}
static func capture(model, center_id: String, radius := RADIUS) -> Dictionary:
	var c: Dictionary = model.items.get(center_id, {})
	if c.is_empty() or not capturable(c):
		return {"pieces": []}
	var origin := Vector2(c["x"], c["z"])
	var near: Array = model.items_in(c["space"]).filter(func(i): return capturable(i) and not i.has("host") \
		and Vector2(i["x"], i["z"]).distance_to(origin) <= radius)
	near.sort_custom(func(a, b): return Vector2(a["x"], a["z"]).distance_to(origin) < Vector2(b["x"], b["z"]).distance_to(origin))
	near = near.slice(0, MAX_PIECES)
	var ids: Array = near.map(func(i): return i["id"])
	for it in model.items_in(c["space"]):
		if it.has("host") and ids.has(it["host"]) and capturable(it) and ids.size() < MAX_PIECES:
			near.append(it)
			ids.append(it["id"])
	var turn := -TownModel.rot_to_radians(c["rot"])
	var pieces := []
	for it in near:
		var off := (Vector2(it["x"], it["z"]) - origin).rotated(-turn)
		pieces.append({"kind": it["kind"], "dx": snappedf(off.x, 0.05), "dz": snappedf(off.y, 0.05),
			"rot": posmod(int(it["rot"]) - int(c["rot"]), TownModel.ROT_STEPS), "color": int(it["color"]),
			"variant": int(it.get("variant", 0)), "on": ids.find(it["host"]) if it.has("host") else -1})
	return {"pieces": pieces}


## World positions for a blueprint placed with its picked item at `at`, turned by `rot`.
static func plan(bp: Dictionary, at: Vector2, rot: int) -> Array:
	var turn := TownModel.rot_to_radians(rot)
	var out := []
	for p in bp.get("pieces", []):
		var off := Vector2(float(p["dx"]), float(p["dz"])).rotated(-turn)
		var w := at + off
		out.append({"kind": str(p["kind"]), "x": snappedf(w.x, 0.05), "z": snappedf(w.y, 0.05),
			"rot": posmod(int(p["rot"]) + rot, TownModel.ROT_STEPS), "color": int(p["color"]),
			"variant": int(p.get("variant", 0)), "on": int(p.get("on", -1))})
	return out


## Places a planned blueprint into `model` piece by piece with the normal rules.
## Returns {"placed": [items], "errors": [one per piece, "" when it fit]}.
## Used by the authority for real, and on a scratch copy for the preview.
static func apply(model, space: String, planned: Array) -> Dictionary:
	var placed := []
	var errors := []
	var ids := []   # planned index -> new item id ("" when skipped)
	for p in planned.slice(0, MAX_PIECES):
		var kind: String = str(p.get("kind", ""))
		var err := ""
		var host := ""
		var on := int(p.get("on", -1))
		if not Catalog.has(kind):
			err = TownModel.ERR_UNKNOWN
		elif not Catalog.allowed_in(kind, space):
			err = TownModel.ERR_OUTDOORS if space != "town" else TownModel.ERR_INDOORS
		elif on >= 0:
			host = ids[on] if on < ids.size() else ""
			if host == "":
				err = TownModel.ERR_NOT_SUPPORT
		var r: Dictionary = {"ok": false, "error": err}
		if err == "":
			r = model.place(kind, space, float(p["x"]), float(p["z"]), int(p["rot"]), int(p["color"]), host)
		if r.get("ok", false):
			var item: Dictionary = r["item"]
			if TownModel.VARIANTS.has(kind):
				model.items[item["id"]]["variant"] = posmod(int(p.get("variant", 0)), TownModel.VARIANTS[kind])
				item = model.items[item["id"]].duplicate(true)
			placed.append(item)
			ids.append(item["id"])
			errors.append("")
		else:
			ids.append("")
			errors.append(str(r.get("error", TownModel.ERR_OVERLAP)))
	return {"placed": placed, "errors": errors}


## Which pieces would fit here, without touching the real town.
static func preview(model, space: String, planned: Array) -> Array:
	var scratch := TownModel.new()
	scratch.from_dict(model.to_dict())
	return apply(scratch, space, planned)["errors"]


## Blueprints kept on this device: [{"name", "pieces"}], newest last.
static func load_all(path := PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Array:
		return []
	var out := []
	for b in j.data:
		if b is Dictionary and b.get("pieces") is Array and NAMES.has(str(b.get("name", ""))):
			var pieces: Array = b["pieces"].filter(func(p): return p is Dictionary and Catalog.has(str(p.get("kind", ""))))
			if not pieces.is_empty():
				out.append({"name": str(b["name"]), "pieces": pieces.slice(0, MAX_PIECES)})
	return out.slice(-MAX_SAVED)


static func save_all(list: Array, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(list.slice(-MAX_SAVED)))
	f.close()
	return true
