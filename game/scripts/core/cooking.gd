## Cooking in the kitchen (pure rules, unit-tested): a stove, ingredients in the
## same room, three seconds on the hob, then a real dish to serve and eat.
## The authority applies these; clients only ask.
extends RefCounted

const COOK_SECONDS := 3.0
## Standing this close to the stove counts as "at the stove".
const REACH := 1.8

## Recipe id -> name, the dish it makes, what must be in the same room.
## Kinds are the modeled p002 items (design/pets-rooms-assets.md).
const RECIPES := {
	"rice": {"name": "Rice bowl", "dish": "dish_rice_bowl", "needs": ["kitchen_rice_sack"]},
	"soup": {"name": "Vegetable soup", "dish": "dish_veg_soup", "needs": ["kitchen_veg_basket", "kitchen_pot"]},
	"egg": {"name": "Fried egg", "dish": "dish_fried_egg", "needs": ["kitchen_egg_basket", "kitchen_pan_set"]},
	"stew": {"name": "Rice and stew", "dish": "dish_rice_meal", "needs": ["kitchen_rice_sack", "kitchen_veg_basket", "kitchen_pot"]},
}
const ORDER := ["rice", "soup", "egg", "stew"]
const DISHES := ["dish_rice_bowl", "dish_veg_soup", "dish_fried_egg", "dish_rice_meal"]


## Ingredient kinds a recipe still lacks in a room (empty = ready to cook).
static func missing(model, space: String, recipe: String) -> Array:
	var have := {}
	for it in model.items_in(space):
		if not it.has("gift"):
			have[it["kind"]] = true
	return RECIPES.get(recipe, {"needs": []})["needs"].filter(func(k): return not have.has(k))


## Can this child start this recipe at this stove now? busy: stove id -> recipe.
static func check(model, stove_id: String, recipe: String, actor_space: String, actor_pos: Vector2, busy: Dictionary) -> String:
	var stove: Dictionary = model.items.get(stove_id, {})
	if stove.is_empty() or stove["kind"] != "kitchen_stove" or stove.has("gift"):
		return "That stove is not here."
	if not RECIPES.has(recipe):
		return "That recipe is not in the book."
	if stove["space"] != actor_space or Vector2(stove["x"], stove["z"]).distance_to(actor_pos) > REACH:
		return "Stand next to the stove to cook."
	if busy.has(stove_id):
		return "Someone is cooking on this stove. Try again in a moment."
	if not missing(model, actor_space, recipe).is_empty():
		return "Some ingredients are missing in this room."
	return ""


## Serves the dish next to the stove (on the floor, like everything else; the
## child may move it onto a table). Returns the placed item or {}.
static func serve(model, stove_id: String, recipe: String) -> Dictionary:
	var stove: Dictionary = model.items.get(stove_id, {})
	if stove.is_empty():
		return {}
	var dish: String = RECIPES[recipe]["dish"]
	var front: Vector2 = Vector2(stove["x"], stove["z"]) + model.facing(stove["rot"]) * 0.75
	var spot = model.find_free_spot(dish, stove["space"], front)
	if spot == null:
		return {}
	var r: Dictionary = model.place(dish, stove["space"], spot.x, spot.y, stove["rot"])
	return r.get("item", {}) if r.get("ok", false) else {}


## Eating a dish: it must be a dish in the child's room, within reach.
static func check_eat(model, dish_id: String, actor_space: String, actor_pos: Vector2) -> String:
	var dish: Dictionary = model.items.get(dish_id, {})
	if dish.is_empty() or not DISHES.has(dish["kind"]) or dish.has("gift"):
		return "That dish is not here."
	if dish["space"] != actor_space or Vector2(dish["x"], dish["z"]).distance_to(actor_pos) > REACH + 0.4:
		return "Walk to the dish to eat it."
	return ""
