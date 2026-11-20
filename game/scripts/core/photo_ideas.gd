## Photo ideas (activity G): playful things to capture with the camera.
##
## Checked deterministically from scene facts gathered when the photo is taken
## (what the camera sees, from the game's own state), never from image analysis.
## Facts dictionary:
##   space: String, evening: bool, weather: String,
##   kids: int (children on screen), animals: Array[String] (species on screen),
##   kinds: Array[String] (item kinds on screen), shared_seat: bool (two children
##   on one item), swinging: bool, tabletop: bool, lanterns: int, room_items: int
## In the zoo (space == "zoo") the facts also carry zoo_animals: Array[String], the species of the
## zoo animals on screen (lion, lioness, tiger, monkey, giraffe, zebra, hippo, otter).
extends RefCounted

const IDEAS := [
	{"id": "friends_bench", "text": "Two friends sharing a seat"},
	{"id": "animal_pond", "text": "An animal friend by a pond"},
	{"id": "pot_on_table", "text": "Something sitting on a table"},
	{"id": "lantern_evening", "text": "Glowing lanterns in the evening"},
	{"id": "swing_ride", "text": "Someone on the swing"},
	{"id": "three_animals", "text": "Three animal friends together"},
	{"id": "cozy_room", "text": "A cozy room with lots of things"},
	{"id": "weather_friend", "text": "A friend in rain, autumn leaves or snow"},
]

## Ideas for the zoo (kept apart from IDEAS: the board in town lists the eight above).
const ZOO_IDEAS := [
	{"id": "zoo_big_cat", "text": "A lion or a tiger in the picture"},
	{"id": "zoo_monkeys", "text": "Two monkeys together"},
	{"id": "zoo_friend", "text": "A friend with a zoo animal"},
	{"id": "zoo_splash", "text": "A hippo or an otter in the water"},
]


static func text_of(id: String) -> String:
	for i in IDEAS + ZOO_IDEAS:
		if i["id"] == id:
			return i["text"]
	return ""


static func evaluate(f: Dictionary) -> Array:
	var out := []
	var animals: Array = f.get("animals", [])
	var kinds: Array = f.get("kinds", [])
	if f.get("shared_seat", false):
		out.append("friends_bench")
	if not animals.is_empty() and kinds.has("pond"):
		out.append("animal_pond")
	if f.get("tabletop", false):
		out.append("pot_on_table")
	if f.get("evening", false) and int(f.get("lanterns", 0)) >= 1:
		out.append("lantern_evening")
	if f.get("swinging", false):
		out.append("swing_ride")
	var distinct := {}
	for a in animals:
		distinct[a] = true
	if distinct.size() >= 3:
		out.append("three_animals")
	if not (str(f.get("space", "town")) in ["town", "zoo"]) and int(f.get("room_items", 0)) >= 5:   # a cottage room, not a map
		out.append("cozy_room")
	if str(f.get("weather", "sunny")) != "sunny" and int(f.get("kids", 0)) >= 1 and str(f.get("space", "town")) == "town":
		out.append("weather_friend")
	if str(f.get("space", "town")) == "zoo":
		out.append_array(_evaluate_zoo(f))
	return out


static func _evaluate_zoo(f: Dictionary) -> Array:
	var out := []
	var species: Array = f.get("zoo_animals", [])
	if species.has("lion") or species.has("lioness") or species.has("tiger"):
		out.append("zoo_big_cat")
	if species.count("monkey") >= 2:
		out.append("zoo_monkeys")
	if not species.is_empty() and int(f.get("kids", 0)) >= 1:
		out.append("zoo_friend")
	if species.has("hippo") or species.has("otter"):
		out.append("zoo_splash")
	return out
