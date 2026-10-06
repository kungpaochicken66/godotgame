## Cozy Spots: arrangements the town recognizes and celebrates with a lantern.
##
## Spots never unlock items or cost anything. They reward arranging things
## thoughtfully and give friends something to make together.
extends RefCounted

const SPOTS := {
	"tea_party": {"name": "Tea party", "hint": "A round table wants two chairs.", "lantern": Color("#f4ad8a")},
	"reading_nook": {"name": "Reading nook", "hint": "Books, a seat and a lamp, all close together.", "lantern": Color("#b7a2e0")},
	"flower_ring": {"name": "Flower ring", "hint": "Three flower patches around a round tree.", "lantern": Color("#ec8fa3")},
	"pond_picnic": {"name": "Pond picnic", "hint": "Spread a picnic blanket beside the pond.", "lantern": Color("#86c3e6")},
	"sleepover": {"name": "Sleepover", "hint": "Two beds and a rug in the same room.", "lantern": Color("#95c97f")},
	"lantern_path": {"name": "Lantern path", "hint": "A lamp post with four stepping stones nearby.", "lantern": Color("#f2cf6b")},
	"playground": {"name": "Playground", "hint": "Put a swing and a seesaw close together.", "lantern": Color("#e9806e")},
	"front_porch": {"name": "Front porch", "hint": "A bench and a flower pot by a cottage door.", "lantern": Color("#a8d8c0")},
}

const ORDER := ["tea_party", "reading_nook", "flower_ring", "pond_picnic", "sleepover", "lantern_path", "playground", "front_porch"]


static func _pos(item: Dictionary) -> Vector2:
	return Vector2(item["x"], item["z"])


static func _near(items: Array, center: Vector2, kinds: Array, radius: float) -> Array:
	return items.filter(func(it): return it["kind"] in kinds and _pos(it).distance_to(center) <= radius)


## Returns every spot currently formed in the model: [{spot, space, at: Vector2, members: [ids]}].
static func detect(model) -> Array:
	var found := []
	var by_space := {}
	for item in model.items.values():
		by_space.get_or_add(item["space"], []).append(item)
	for space in by_space:
		var list: Array = by_space[space]
		for it in list:
			var p := _pos(it)
			match it["kind"]:
				"table":
					var chairs := _near(list, p, ["chair"], 1.7)
					if chairs.size() >= 2:
						found.append(_spot("tea_party", space, p, [it] + chairs))
				"bookshelf":
					var seats := _near(list, p, ["chair", "sofa"], 2.6)
					var lamps := _near(list, p, ["floor_lamp"], 2.6)
					if seats.size() >= 1 and lamps.size() >= 1:
						found.append(_spot("reading_nook", space, p, [it, seats[0], lamps[0]]))
				"tree":
					var flowers := _near(list, p, ["flowers"], 2.6)
					if flowers.size() >= 3:
						found.append(_spot("flower_ring", space, p, [it] + flowers))
				"pond":
					var blankets := _near(list, p, ["blanket"], 3.6)
					if blankets.size() >= 1:
						found.append(_spot("pond_picnic", space, p, [it, blankets[0]]))
				"lamp_post":
					var stones := _near(list, p, ["path_stone"], 3.2)
					if stones.size() >= 4:
						found.append(_spot("lantern_path", space, p, [it] + stones))
				"swing":
					var seesaws := _near(list, p, ["seesaw"], 7.0)
					if seesaws.size() >= 1:
						found.append(_spot("playground", space, p.lerp(_pos(seesaws[0]), 0.5), [it, seesaws[0]]))
				"cottage":
					var door: Vector2 = model.door_point(it)
					var benches := _near(list, door, ["bench"], 3.5)
					var pots := _near(list, door, ["plant", "flowers"], 3.5)
					if benches.size() >= 1 and pots.size() >= 1:
						found.append(_spot("front_porch", space, door, [it, benches[0], pots[0]]))
		if space != "town":
			var beds := list.filter(func(i): return i["kind"] == "bed")
			var rugs := list.filter(func(i): return i["kind"] == "rug")
			if beds.size() >= 2 and rugs.size() >= 1:
				found.append(_spot("sleepover", space, _pos(rugs[0]), [beds[0], beds[1], rugs[0]]))
	return found


static func _spot(kind: String, space: String, at: Vector2, members: Array) -> Dictionary:
	return {"spot": kind, "space": space, "at": at, "members": members.map(func(m): return m["id"])}


## Spot kinds formed now that have no lantern yet.
static func newly_formed(model) -> Array:
	var out := []
	for s in detect(model):
		if not model.lanterns.has(s["spot"]) and not out.has(s["spot"]):
			out.append(s["spot"])
	return out
