## Photo ideas (activity G): playful things to capture with the camera.
##
## Checked deterministically from scene facts gathered when the photo is taken
## (what the camera sees, from the game's own state), never from image analysis.
## Facts dictionary:
##   space: String, evening: bool, weather: String,
##   kids: int (children on screen), animals: Array[String] (species on screen),
##   kinds: Array[String] (item kinds on screen), shared_seat: bool (two children
##   on one item), swinging: bool, tabletop: bool, lanterns: int, room_items: int
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


static func text_of(id: String) -> String:
	for i in IDEAS:
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
	if str(f.get("space", "town")) != "town" and int(f.get("room_items", 0)) >= 5:
		out.append("cozy_room")
	if str(f.get("weather", "sunny")) != "sunny" and int(f.get("kids", 0)) >= 1 and str(f.get("space", "town")) == "town":
		out.append("weather_friend")
	return out
