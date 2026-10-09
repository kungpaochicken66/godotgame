## Themed rooms: which toy box tab each room opens on, which existing items also
## belong to a theme, and the starter set a child can put into an empty themed
## room with one tap (design/pets-kitchen-photos.md). Pure data and rules.
extends RefCounted

const Catalog := preload("res://scripts/core/catalog.gd")

## Theme tabs list their own new items (by category) plus these existing ones.
const EXTRA := {
	"Kitchen": ["curved_counter", "kitchen_scale", "garlic_fish_skillet", "tiered_tea_stand", "fried_fish_plate",
		"apple_jam_jars", "apple_jelly_plate", "apple_pie_plate", "apple_smoothie", "apple_tart_slice",
		"baked_potatoes_plate", "bamboo_shoot_soup", "berliner_plate", "fish_carpaccio_plate",
		"table", "chair", "cozy_round_table", "scallop_chair"],
	"Games": ["arcade_cabinet_blue", "arcade_cabinet_keys", "arcade_cabinet_red", "arched_table_radio",
		"plush_bear", "plush_panda", "basketball", "beach_ball", "baseball_set", "child_tube_chair",
		"egg_lounge_chair", "sofa", "rug", "table", "writing_bureau", "oval_arch_table", "open_shelf", "lattice_cabinet",
		"bamboo_ring_shelf"],
	"Pets": ["beach_ball", "basketball", "woven_bamboo_sphere", "plush_bear", "bird_mobile", "butterfly_model", "butterfly_plaque", "anchovy_model", "angelfish_model", "arowana_model",
		"deep_sea_fish_model", "striped_fish_model", "arapaima_model", "plant", "flower_pot_bloom", "rug"],
}

## Scene toolkits (design/playability-8-12.md F09): extra toy box tabs that
## gather existing things for one kind of play, indoors and out, each with a
## one-line idea. Nothing is locked; the same things stay in their own tabs too.
const TOOLKITS := ["Snack Stand", "Little Theater", "Rainy Day", "Music Corner"]
const TOOLKIT_ITEMS := {
	"Snack Stand": ["snack_tray", "garden_umbrella", "snack_cookie", "snack_sandwich", "snack_juice", "table", "chair", "blanket", "bench",
		"tiered_tea_stand", "apple_smoothie", "apple_pie_plate", "berliner_plate", "cozy_round_table"],
	"Little Theater": ["stage_curtain", "stage_moon", "stage_mountain", "bench", "lamp_post", "blanket", "fence", "flowers", "folding_screen", "celebratory_arch_gold",
		"celebratory_arch_teal", "antique_vanity", "accessory_rack", "chair", "rug", "paper_floor_lamp", "egg_light_garland"],
	"Rainy Day": ["paper_boat", "leaf_pile", "garden_umbrella", "snowman", "pond", "path_stone", "bench", "tree", "lamp_post", "rug", "sofa", "teddy", "floor_lamp",
		"bookshelf", "plush_bear"],
	"Music Corner": ["music_box", "bench", "lamp_post", "flowers", "acoustic_guitar_stand", "saxophone_stand", "practice_amp",
		"arched_table_radio", "bamboo_slit_drum", "cushion_stool", "rug"],
}
const TOOLKIT_IDEAS := {
	"Snack Stand": "Idea: set up a snack tray, make snacks for friends, then tap Share.",
	"Little Theater": "Idea: put seats in a row, make a stage, then put on a show with emotes.",
	"Rainy Day": "Idea: change the weather to rain and splash in the puddles, or build a snowman.",
	"Music Corner": "Idea: make a cozy corner for music, then dance together.",
}


## Room (floor, room) -> the tab the toy box opens on there.
const ROOM_TAB := {"Kitchen": "Kitchen", "Game room": "Games", "Pet room": "Pets"}

## Starter sets: [kind, preferred x, preferred z, rot]. Placed with the normal
## rules (find_free_spot), so doors, stairs and walls stay clear.
const STARTER := {
	"Kitchen": [["kitchen_counter", -2.6, -2.3, 0], ["kitchen_stove", -1.5, -2.3, 0], ["kitchen_sink", -0.3, -2.3, 0],
		["kitchen_fridge", 0.9, -2.3, 0], ["kitchen_rice_sack", -3.5, -0.4, 1], ["kitchen_egg_basket", -3.5, 0.4, 0],
		["kitchen_veg_basket", -3.5, 1.1, 0], ["kitchen_utensil_crock", -3.5, 1.8, 0], ["table", 1.6, 0.6, 0],
		["chair", 1.6, 1.6, 4], ["chair", 0.4, 0.6, 2], ["kitchen_plate_rack", 2.8, 0.6, 0]],
	"Game room": [["game_tv_stand", -1.0, -2.4, 0], ["game_bean_bag", -1.0, -0.6, 4], ["table", 1.8, -0.6, 0],
		["game_storage_cubby", 2.4, -2.4, 0], ["game_handheld_dock", 0.6, -0.4, 0], ["game_controller", -0.2, -0.9, 0],
		["arcade_cabinet_red", -3.2, -2.2, 0]],
	"Pet room": [["petroom_bed_round", -2.4, -1.4, 0], ["petroom_dog_house", 2.7, -2.1, 0], ["petroom_food_bowl", -0.7, -0.3, 0],
		["petroom_water_bowl", -0.2, -0.3, 0], ["petroom_cat_tree", -3.3, -2.3, 0], ["petroom_scratch_post", -1.6, -2.4, 0],
		["petroom_toy_yarn", 0.8, 0.7, 0], ["petroom_toy_bone", 1.5, 0.9, 0], ["petroom_perch_stand", 0.9, -2.4, 0],
		["petroom_bird_cage", 3.4, 0.5, 0], ["petroom_butterfly_house", 2.4, 1.6, 0]],
}
## A themed room offers its set-up while none of these is in it.
const KEY := {"Kitchen": ["kitchen_stove"], "Game room": ["game_tv_stand", "game_console_set", "game_handheld_dock"],
	"Pet room": ["petroom_bed_round", "petroom_dog_house"]}
## Small items set on a host: the console on the game room table; the pot on the
## kitchen counter and the pan on the stove, so the way to the stove stays clear.
const STARTER_ON := {"Game room": [["game_console_set", "table"]],
	"Kitchen": [["kitchen_pot", "kitchen_counter"], ["kitchen_pan_set", "kitchen_stove"]]}


static func tab_for_room(room_name: String) -> String:
	return ROOM_TAB.get(room_name, "")


## Kinds that a theme tab adds beyond its own category (existing items only).
static func extra_for(tab: String) -> Array:
	return EXTRA.get(tab, TOOLKIT_ITEMS.get(tab, [])).filter(func(k): return Catalog.has(k))


## Toolkit tabs that have something for this space (town or a room).
static func toolkits_for(space: String) -> Array:
	return TOOLKITS.filter(func(t): return extra_for(t).any(func(k): return Catalog.allowed_in(k, space)))


## The set-up label for a room the child stands in, or "" (not themed, it
## already has its key item, or it was set up once).
static func setup_label(model, space: String) -> String:
	var r: Dictionary = model.parse_room(space)
	if r.is_empty():
		return ""
	var name: String = model.ROOM_NAMES[r["floor"]][r["room"]]
	if not STARTER.has(name) or model.starter.has(space):
		return ""
	if model.items_in(space).any(func(i): return KEY[name].has(i["kind"])):
		return ""
	return {"Kitchen": "Set up the kitchen", "Game room": "Set up the game room", "Pet room": "Set up the pet room"}[name]


## Adds the starter set's missing pieces to a themed room (once per room). What
## is already there stays where it is; every new item is placed with the normal
## rules in a free spot. Returns the placed items.
static func furnish_room(model, space: String) -> Array:
	if setup_label(model, space) == "":
		return []
	var r: Dictionary = model.parse_room(space)
	var name: String = model.ROOM_NAMES[r["floor"]][r["room"]]
	model.starter[space] = true
	var placed := []
	var have := {}
	for it in model.items_in(space):
		have[it["kind"]] = int(have.get(it["kind"], 0)) + 1
	for spec in STARTER[name]:
		if int(have.get(spec[0], 0)) > 0:
			have[spec[0]] -= 1
			continue
		var spot = model.find_free_spot(spec[0], space, Vector2(spec[1], spec[2]), spec[3])
		if spot != null:
			var res: Dictionary = model.place(spec[0], space, spot.x, spot.y, spec[3])
			if res.get("ok", false):
				placed.append(res["item"])
	for on in STARTER_ON.get(name, []):
		if int(have.get(on[0], 0)) > 0:
			continue
		for host in model.items_in(space).filter(func(i): return i["kind"] == on[1]):
			# Turn it until it fits the host's top, like a child would.
			for turn in model.ROT_STEPS:
				var res: Dictionary = model.place(on[0], space, host["x"], host["z"], posmod(host["rot"] + turn, model.ROT_STEPS), -2, host["id"])
				if res.get("ok", false):
					placed.append(res["item"])
					break
			break
	return placed


## Every themed room of every cottage that can still be set up (tests and tools).
static func furnish(model) -> int:
	var n := 0
	for house in model.items.values().filter(func(i): return i["kind"] == "cottage"):
		for f in model.ROOM_NAMES.size():
			for r in 2:
				n += furnish_room(model, model.room_space(house["id"], f, r)).size()
	return n
