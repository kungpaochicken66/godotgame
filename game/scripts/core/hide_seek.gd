## Hide-and-seek rules (activity B) that do not depend on the network: how warm a
## seeker is. Used by the Activities autoload on the authority.
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")


## 0 (far away) .. 4 (right here). Other rooms of the same house count as a little
## warm, and so does being outdoors while the acorn is inside a house.
static func warmth_level(st: Dictionary, secret: Dictionary) -> int:
	var space: String = st.get("space", "town")
	if space != secret.get("space", ""):
		var same_house: bool = TownModel.house_of(space) != "" and TownModel.house_of(space) == TownModel.house_of(secret.get("space", ""))
		var outside_its_house := space == "town" and TownModel.house_of(secret.get("space", "")) != ""
		return 1 if same_house or outside_its_house else 0
	var d := Vector2(st.get("x", 0.0), st.get("z", 0.0)).distance_to(Vector2(secret.get("x", 0.0), secret.get("z", 0.0)))
	return 4 if d < 2.0 else (3 if d < 5.0 else (2 if d < 10.0 else (1 if d < 18.0 else 0)))
