## Every placeable object. All entries are free and unlimited; nothing is unlocked.
##
## Fields:
##   name      English source string (translated through the locale catalogs)
##   category  catalog tab
##   space     "town", "home" (inside a house) or "both"
##   radius    footprint circle in meters used for overlap and walking collision
##   layer     "solid" blocks walking and other solids; "flat" lies on the ground
##             and only collides with other flat items
##   color     default paint index (see palette.gd); -1 means not paintable
##   seats     how many children can sit/ride at once (0 = not interactive)
##   action    context action label key for seated items
##
## To add an object designed by the creator: add an entry here, a builder in
## scripts/art/props.gd and its English name to every file in game/locale/.
extends RefCounted

const ITEMS := {
	"cottage": {"name": "Cottage", "category": "Homes", "space": "town", "radius": 2.3, "layer": "solid", "color": 2, "seats": 0},
	"tree": {"name": "Round tree", "category": "Nature", "space": "town", "radius": 0.8, "layer": "solid", "color": 5, "seats": 0},
	"pine": {"name": "Pine tree", "category": "Nature", "space": "town", "radius": 0.7, "layer": "solid", "color": -1, "seats": 0},
	"bush": {"name": "Berry bush", "category": "Nature", "space": "town", "radius": 0.6, "layer": "solid", "color": 3, "seats": 0},
	"flowers": {"name": "Flower patch", "category": "Nature", "space": "town", "radius": 0.45, "layer": "solid", "color": 3, "seats": 0},
	"path_stone": {"name": "Stepping stone", "category": "Paths & water", "space": "town", "radius": 0.45, "layer": "flat", "color": -1, "seats": 0},
	"pond": {"name": "Pond", "category": "Paths & water", "space": "town", "radius": 2.0, "layer": "solid", "color": -1, "seats": 0},
	"lamp_post": {"name": "Lamp post", "category": "Paths & water", "space": "town", "radius": 0.3, "layer": "solid", "color": 1, "seats": 0},
	"fence": {"name": "Fence", "category": "Paths & water", "space": "town", "radius": 0.6, "layer": "solid", "color": 0, "seats": 0},
	"swing": {"name": "Swing", "category": "Play", "space": "town", "radius": 1.3, "layer": "solid", "color": 4, "seats": 1, "action": "Swing"},
	"seesaw": {"name": "Seesaw", "category": "Play", "space": "town", "radius": 1.5, "layer": "solid", "color": 1, "seats": 2, "action": "Ride"},
	"bench": {"name": "Bench", "category": "Play", "space": "town", "radius": 0.85, "layer": "solid", "color": 5, "seats": 2, "action": "Sit"},
	"blanket": {"name": "Picnic blanket", "category": "Play", "space": "town", "radius": 1.0, "layer": "flat", "color": 3, "seats": 0},
	"bed": {"name": "Bed", "category": "Furniture", "space": "home", "radius": 0.95, "layer": "solid", "color": 5, "seats": 1, "action": "Rest"},
	"chair": {"name": "Chair", "category": "Furniture", "space": "both", "radius": 0.4, "layer": "solid", "color": 0, "seats": 1, "action": "Sit"},
	"table": {"name": "Round table", "category": "Furniture", "space": "both", "radius": 0.65, "layer": "solid", "color": -1, "seats": 0},
	"sofa": {"name": "Sofa", "category": "Furniture", "space": "home", "radius": 0.9, "layer": "solid", "color": 4, "seats": 2, "action": "Sit"},
	"bookshelf": {"name": "Bookshelf", "category": "Furniture", "space": "home", "radius": 0.6, "layer": "solid", "color": 6, "seats": 0},
	"rug": {"name": "Rug", "category": "Cozy things", "space": "home", "radius": 1.15, "layer": "flat", "color": 2, "seats": 0},
	"plant": {"name": "Flower pot", "category": "Cozy things", "space": "both", "radius": 0.35, "layer": "solid", "color": 0, "seats": 0},
	"floor_lamp": {"name": "Floor lamp", "category": "Cozy things", "space": "home", "radius": 0.3, "layer": "solid", "color": 1, "seats": 0},
	"teddy": {"name": "Teddy bear", "category": "Cozy things", "space": "home", "radius": 0.3, "layer": "solid", "color": 7, "seats": 0},
}

const TOWN_CATEGORIES := ["Nature", "Paths & water", "Play", "Homes", "Furniture"]
const HOME_CATEGORIES := ["Furniture", "Cozy things"]


static func has(kind: String) -> bool:
	return ITEMS.has(kind)


static func get_def(kind: String) -> Dictionary:
	return ITEMS.get(kind, {})


static func allowed_in(kind: String, space: String) -> bool:
	var where: String = ITEMS.get(kind, {}).get("space", "")
	if where == "both":
		return true
	return where == ("town" if space == "town" else "home")


## Kinds shown in one catalog tab for the given space, in a stable order.
static func kinds_for(category: String, space: String) -> Array:
	var out := []
	for kind in ITEMS:
		if ITEMS[kind]["category"] == category and allowed_in(kind, space):
			out.append(kind)
	return out
