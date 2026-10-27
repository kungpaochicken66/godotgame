## Writes a synthetic town save for the join tests (r19-connect): the default town plus cottages, with
## real catalog items filling their rooms, until it has --items items. No real save is used.
##   scripts/godot.sh --headless --path game -s res://tests/town_fixture.gd -- --out=/abs/town.json --items=420
## Prints "FIXTURE <items> items, <bytes> welcome bytes, <sha256 of the items>".
extends SceneTree

const TownModel := preload("res://scripts/core/town_model.gd")
const Catalog := preload("res://scripts/core/catalog.gd")


## A stable digest of every item (the join test compares what a client received with this).
static func items_digest(items: Dictionary) -> String:
	var keys := items.keys()
	keys.sort()
	var parts := []
	for k in keys:
		var it: Dictionary = items[k]
		var fields := it.keys()
		fields.sort()
		parts.append(str(k) + ":" + ",".join(fields.map(func(f): return "%s=%s" % [f, var_to_str(it[f])])))
	return "|".join(parts).sha256_text()


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var want := int(args.get("items", "420"))
	var m = TownModel.make_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var kinds := []
	for k in Catalog.ITEMS:
		var d: Dictionary = Catalog.get_def(k)
		if d.get("space", "") in ["home", "both"] and d.get("anchor", "ground") == "ground":
			kinds.append(k)
	var spaces := []
	for tries in 200:
		if m.items.size() + spaces.size() * TownModel.MAX_ROOM_ITEMS >= want:
			break
		var spot = m.find_free_spot("cottage", "town", Vector2(rng.randf_range(-22, 22), rng.randf_range(-18, 18)))
		if spot != null and m.place("cottage", "town", spot.x, spot.y, 0).get("ok", false):
			pass
		spaces.clear()
		for h in m.items.values().filter(func(i): return i["kind"] == "cottage"):
			for f in TownModel.FLOORS:
				for r in TownModel.ROOMS_PER_FLOOR:
					spaces.append(TownModel.room_space(h["id"], f, r))
	var n := 0
	var full := {}
	while m.items.size() < want and full.size() < spaces.size():
		var sp: String = spaces[n % spaces.size()]
		n += 1
		if m.items_in(sp).size() >= TownModel.MAX_ROOM_ITEMS:
			full[sp] = true
			continue
		var id := "f%d" % n
		m.items[id] = {"id": id, "kind": kinds[n % kinds.size()], "space": sp,
			"x": snappedf(rng.randf_range(-3.4, 3.4), 0.05), "z": snappedf(rng.randf_range(-2.4, 2.4), 0.05),
			"rot": n % 8, "color": n % 6}
	# Saved as the game itself would save it after loading (defaults filled in, e.g. a music box's song).
	var norm = TownModel.new()
	norm.from_dict(m.to_dict())
	m = norm
	var d: Dictionary = m.to_dict()
	var f := FileAccess.open(args.get("out", "user://town_fixture.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	var welcome_bytes := var_to_bytes([2, d, {}, {}, {}]).size()
	print("FIXTURE %d items, %d welcome bytes, %s" % [m.items.size(), welcome_bytes, items_digest(m.items)])
	quit()
