## Animal wishes (activity A): an animal asks for a small arrangement outdoors.
##
## A wish is a list of item kinds that must all stand within `radius` meters of
## one another (around one of them) in the town. Wishes never unlock or consume
## anything; fulfilled wishes become scrapbook stickers.
extends RefCounted


## animal -> list of {id, kinds, radius, text}. Text is the English source shown
## under the picture icons on the wish card.
const TEMPLATES := {
	"pig": [
		{"id": "pig_picnic", "kinds": ["blanket", "pond"], "radius": 4.0, "text": "A picnic blanket by a pond"},
		{"id": "pig_bench", "kinds": ["bench", "pond"], "radius": 4.5, "text": "A bench to rest by the pond"},
		{"id": "pig_flowers", "kinds": ["flowers", "flowers", "bush"], "radius": 3.0, "text": "Flowers and a bush to sniff"},
		{"id": "pig_garden", "kinds": ["garden_bed", "fence"], "radius": 3.0, "text": "A garden bed with a fence"},
	],
	"rabbit": [
		{"id": "rabbit_garden", "kinds": ["garden_bed", "garden_bed"], "radius": 3.0, "text": "Two garden beds side by side"},
		{"id": "rabbit_ring", "kinds": ["tree", "flowers", "flowers"], "radius": 3.0, "text": "Flowers around a tree"},
		{"id": "rabbit_path", "kinds": ["path_stone", "path_stone", "path_stone", "flowers"], "radius": 3.0, "text": "A stone path to some flowers"},
		{"id": "rabbit_pot", "kinds": ["plant", "bench"], "radius": 3.0, "text": "A flower pot by a bench"},
	],
	"sheep": [
		{"id": "sheep_stage", "kinds": ["lamp_post", "bench"], "radius": 3.5, "text": "A lamp post by a bench"},
		{"id": "sheep_swing", "kinds": ["swing", "flowers"], "radius": 4.0, "text": "Flowers next to the swing"},
		{"id": "sheep_concert", "kinds": ["bench", "bench", "lamp_post"], "radius": 4.0, "text": "Two benches and a lamp for a concert"},
		{"id": "sheep_seesaw", "kinds": ["seesaw", "lamp_post"], "radius": 4.5, "text": "A seesaw under a lamp post"},
	],
	"dog": [
		{"id": "dog_field", "kinds": ["fence", "fence", "seesaw"], "radius": 4.5, "text": "A seesaw with a fence"},
		{"id": "dog_picnic", "kinds": ["blanket", "table"], "radius": 3.5, "text": "A blanket and a table outside"},
		{"id": "dog_tea", "kinds": ["table", "chair", "chair"], "radius": 2.5, "text": "A table with two chairs outside"},
		{"id": "dog_shade", "kinds": ["tree", "bench"], "radius": 3.0, "text": "A bench in a tree's shade"},
	],
	"elephant": [
		{"id": "elephant_trail", "kinds": ["path_stone", "path_stone", "lamp_post"], "radius": 3.5, "text": "A lit stone trail"},
		{"id": "elephant_grove", "kinds": ["pine", "pine", "tree"], "radius": 4.5, "text": "A little grove of trees"},
		{"id": "elephant_pond", "kinds": ["pond", "tree"], "radius": 5.0, "text": "A tree beside a pond"},
		{"id": "elephant_fence", "kinds": ["fence", "fence", "fence"], "radius": 3.0, "text": "A fence of three pieces"},
	],
}
const ANIMALS := ["pig", "rabbit", "sheep", "dog", "elephant"]
## Seconds of play between wishes. Not a timer for the child: nothing expires.
const FIRST_WISH_AFTER := 20.0
const NEXT_WISH_AFTER := 25.0


static func find(id: String) -> Dictionary:
	for animal in TEMPLATES:
		for t in TEMPLATES[animal]:
			if t["id"] == id:
				var out: Dictionary = t.duplicate()
				out["animal"] = animal
				return out
	return {}


## Where a wish is met, or null. Wrapped presents do not count.
static func met_at(model, wish_id: String) -> Variant:
	var t := find(wish_id)
	if t.is_empty():
		return null
	var town: Array = model.items_in("town").filter(func(i): return not i.has("gift"))
	for anchor in town:
		if anchor["kind"] != t["kinds"][0]:
			continue
		var center := Vector2(anchor["x"], anchor["z"])
		var used := {anchor["id"]: true}
		var ok := true
		for kind in t["kinds"].slice(1):
			var found := ""
			for it in town:
				if it["kind"] == kind and not used.has(it["id"]) and Vector2(it["x"], it["z"]).distance_to(center) <= t["radius"]:
					found = it["id"]
					break
			if found == "":
				ok = false
				break
			used[found] = true
		if ok:
			return center
	return null


## Picks a wish that is not already met, preferring animals who have waited longest.
static func pick(model, rng: RandomNumberGenerator) -> Dictionary:
	var counts := {}
	for s in model.wishes.get("stickers", []):
		counts[s.get("animal", "")] = counts.get(s.get("animal", ""), 0) + 1
	var order := ANIMALS.duplicate()
	order.sort_custom(func(a, b): return counts.get(a, 0) < counts.get(b, 0))
	for animal in order:
		var options: Array = TEMPLATES[animal].filter(func(t): return met_at(model, t["id"]) == null)
		if not options.is_empty():
			var t: Dictionary = options[rng.randi() % options.size()]
			return {"animal": animal, "id": t["id"]}
	return {}
