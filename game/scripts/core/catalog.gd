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
##   model     optional GLB scene (modeled assets); otherwise built in props.gd
##   size_class, anchor, bounds, tabletop_eligible, support_surface:
##             the object scale and surface contract, see
##             design/object-scale-and-surfaces.md (1 unit = 1 m, H = 1.30)
##
## To add an object designed by the creator: add an entry here, a builder in
## scripts/art/props.gd and its English name to every file in game/locale/.
extends RefCounted

const ITEMS := {
	"cottage": {"name": "Cottage", "category": "Homes", "space": "town", "radius": 2.3, "layer": "solid", "color": 2, "seats": 0, "size_class": "landmark", "anchor": "ground", "bounds": Vector3(3.8, 7.51, 3.6), "tabletop_eligible": false},
	"tree": {"name": "Round tree", "category": "Nature", "space": "town", "radius": 0.55, "layer": "solid", "color": 5, "seats": 0, "size_class": "tree", "anchor": "ground", "bounds": Vector3(1.85, 2.42, 1.85), "tabletop_eligible": false},
	"pine": {"name": "Pine tree", "category": "Nature", "space": "town", "radius": 0.5, "layer": "solid", "color": -1, "seats": 0, "size_class": "tree", "anchor": "ground", "bounds": Vector3(1.5, 2.18, 1.5), "tabletop_eligible": false},
	"bush": {"name": "Berry bush", "category": "Nature", "space": "town", "radius": 0.6, "layer": "solid", "color": 3, "seats": 0, "size_class": "medium", "anchor": "ground", "bounds": Vector3(1.31, 0.96, 0.99), "tabletop_eligible": false},
	"flowers": {"name": "Flower patch", "category": "Nature", "space": "town", "radius": 0.45, "layer": "solid", "color": 3, "seats": 0, "size_class": "small", "anchor": "ground", "bounds": Vector3(0.83, 0.51, 0.83), "tabletop_eligible": false},
	"path_stone": {"name": "Stepping stone", "category": "Paths & water", "space": "town", "radius": 0.45, "layer": "flat", "color": -1, "seats": 0, "size_class": "flat", "anchor": "ground", "bounds": Vector3(1.04, 0.1, 0.97), "tabletop_eligible": false},
	"pond": {"name": "Pond", "category": "Paths & water", "space": "town", "radius": 2.0, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(4.19, 1.06, 3.61), "tabletop_eligible": false},
	"lamp_post": {"name": "Lamp post", "category": "Paths & water", "space": "town", "radius": 0.3, "layer": "solid", "color": 1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(0.56, 3.03, 0.56), "tabletop_eligible": false},
	"fence": {"name": "Fence", "category": "Paths & water", "space": "town", "radius": 0.6, "layer": "solid", "color": 0, "seats": 0, "size_class": "medium", "anchor": "ground", "bounds": Vector3(1.3, 0.85, 0.16), "tabletop_eligible": false},
	"swing": {"name": "Swing", "category": "Play", "space": "town", "radius": 1.3, "layer": "solid", "color": 4, "seats": 1, "action": "Swing", "size_class": "large", "anchor": "ground", "bounds": Vector3(2.4, 2.35, 1.52), "tabletop_eligible": false},
	"seesaw": {"name": "Seesaw", "category": "Play", "space": "town", "radius": 1.5, "layer": "solid", "color": 1, "seats": 2, "action": "Ride", "size_class": "large", "anchor": "ground", "bounds": Vector3(0.5, 0.98, 3.0), "tabletop_eligible": false},
	"bench": {"name": "Bench", "category": "Play", "space": "town", "radius": 0.85, "layer": "solid", "color": 5, "seats": 2, "action": "Sit", "size_class": "large", "anchor": "ground", "bounds": Vector3(1.6, 0.94, 0.54), "tabletop_eligible": false},
	"blanket": {"name": "Picnic blanket", "category": "Play", "space": "town", "radius": 1.0, "layer": "flat", "color": 3, "seats": 0, "size_class": "flat", "anchor": "ground", "bounds": Vector3(1.8, 0.47, 1.4), "tabletop_eligible": false},
	"bed": {"name": "Bed", "category": "Furniture", "space": "home", "radius": 0.95, "layer": "solid", "color": 5, "seats": 1, "action": "Rest", "size_class": "large", "anchor": "ground", "bounds": Vector3(1.28, 0.96, 1.98), "tabletop_eligible": false},
	"chair": {"name": "Chair", "category": "Furniture", "space": "both", "radius": 0.4, "layer": "solid", "color": 0, "seats": 1, "action": "Sit", "size_class": "medium", "anchor": "ground", "bounds": Vector3(0.52, 1.0, 0.52), "tabletop_eligible": false},
	"table": {"name": "Round table", "category": "Furniture", "space": "both", "radius": 0.65, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(1.2, 0.7, 1.2), "tabletop_eligible": false,
		"support_surface": {"local_position": Vector3(0, 0.70, 0), "usable_size_xz": Vector2(0.84, 0.84), "max_items": 1}},
	"sofa": {"name": "Sofa", "category": "Furniture", "space": "home", "radius": 0.9, "layer": "solid", "color": 4, "seats": 2, "action": "Sit", "size_class": "large", "anchor": "ground", "bounds": Vector3(1.8, 0.86, 0.82), "tabletop_eligible": false},
	"bookshelf": {"name": "Bookshelf", "category": "Furniture", "space": "home", "radius": 0.6, "layer": "solid", "color": 6, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(1.1, 1.6, 0.44), "tabletop_eligible": false},
	"rug": {"name": "Rug", "category": "Cozy things", "space": "home", "radius": 1.15, "layer": "flat", "color": 2, "seats": 0, "size_class": "flat", "anchor": "ground", "bounds": Vector3(2.2, 0.04, 1.58), "tabletop_eligible": false},
	"plant": {"name": "Flower pot", "category": "Cozy things", "space": "both", "radius": 0.25, "layer": "solid", "color": 0, "seats": 0, "size_class": "small", "anchor": "ground", "bounds": Vector3(0.38, 0.52, 0.36), "tabletop_eligible": true},
	"floor_lamp": {"name": "Floor lamp", "category": "Cozy things", "space": "home", "radius": 0.3, "layer": "solid", "color": 1, "seats": 0, "size_class": "medium", "anchor": "ground", "bounds": Vector3(0.6, 1.62, 0.6), "tabletop_eligible": false},
	"teddy": {"name": "Teddy bear", "category": "Cozy things", "space": "home", "radius": 0.22, "layer": "solid", "color": 7, "seats": 0, "size_class": "small", "anchor": "ground", "bounds": Vector3(0.35, 0.45, 0.27), "tabletop_eligible": true},
	# Modeled furniture from the reviewed pilot-10 handoff (art/pilot-10-v1). Scale is
	# baked into the GLB; bounds and footprints come from its manifests.
	"scallop_chair": {"name": "Scallop chair", "category": "Furniture", "space": "both", "radius": 0.38, "layer": "solid", "color": -1, "seats": 1, "action": "Sit", "size_class": "medium", "anchor": "ground", "bounds": Vector3(0.533, 1.068, 0.501), "tabletop_eligible": false, "model": "res://assets/models/scallop_chair.glb"},
	"cozy_round_table": {"name": "Cozy round table", "category": "Furniture", "space": "both", "radius": 0.52, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(1.0, 0.66, 1.0), "tabletop_eligible": false, "model": "res://assets/models/cozy_round_table.glb",
		"support_surface": {"local_position": Vector3(0, 0.66, 0), "usable_size_xz": Vector2(0.56, 0.56), "max_items": 1}},
	"scallop_bed": {"name": "Scallop bed", "category": "Furniture", "space": "home", "radius": 0.85, "layer": "solid", "color": -1, "seats": 1, "action": "Rest", "size_class": "large", "anchor": "ground", "bounds": Vector3(1.072, 1.018, 1.792), "tabletop_eligible": false, "model": "res://assets/models/scallop_bed.glb"},
	"writing_bureau": {"name": "Writing desk", "category": "Furniture", "space": "home", "radius": 0.38, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(0.78, 0.95, 0.516), "tabletop_eligible": false, "model": "res://assets/models/writing_bureau.glb"},
	"open_shelf": {"name": "Open shelf", "category": "Furniture", "space": "home", "radius": 0.45, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(1.001, 1.362, 0.401), "tabletop_eligible": false, "model": "res://assets/models/open_shelf.glb"},
	"curved_counter": {"name": "Curved counter", "category": "Furniture", "space": "home", "radius": 0.62, "layer": "solid", "color": -1, "seats": 0, "size_class": "large", "anchor": "ground", "bounds": Vector3(1.51, 0.8, 0.578), "tabletop_eligible": false, "model": "res://assets/models/curved_counter.glb"},
	"desk_lamp": {"name": "Desk lamp", "category": "Cozy things", "space": "home", "radius": 0.18, "layer": "solid", "color": -1, "seats": 0, "size_class": "small", "anchor": "ground", "bounds": Vector3(0.317, 0.538, 0.482), "tabletop_eligible": true, "model": "res://assets/models/desk_lamp.glb"},
	"flower_pot_bloom": {"name": "Blooming flower pot", "category": "Cozy things", "space": "both", "radius": 0.18, "layer": "solid", "color": -1, "seats": 0, "size_class": "small", "anchor": "ground", "bounds": Vector3(0.351, 0.573, 0.351), "tabletop_eligible": true, "model": "res://assets/models/flower_pot_bloom.glb"},
}

## Reviewed models that are complete but not placeable yet: they need wall or
## ceiling anchors, which are not implemented (see design/object-scale-and-surfaces.md).
## They are kept in art/pilot-10-v1 and deliberately absent from ITEMS.
const PENDING_MODELS := {"wall_clock": "wall", "bird_mobile": "ceiling"}

const TOWN_CATEGORIES := ["Nature", "Paths & water", "Play", "Homes", "Furniture"]
const HOME_CATEGORIES := ["Furniture", "Cozy things"]


static func has(kind: String) -> bool:
	return ITEMS.has(kind)


static func get_def(kind: String) -> Dictionary:
	return ITEMS.get(kind, {})


## Visual height of the built model (from the scale contract bounds).
static func height(kind: String) -> float:
	return ITEMS.get(kind, {}).get("bounds", Vector3.ONE).y


static func support_surface(kind: String) -> Dictionary:
	return ITEMS.get(kind, {}).get("support_surface", {})


## True when an item of this kind may sit on a host of that kind, turned by
## rel_steps 45-degree steps relative to the host (eligibility and fit).
static func fits_on(kind: String, host_kind: String, rel_steps := 0) -> bool:
	var surface := support_surface(host_kind)
	var def := get_def(kind)
	if surface.is_empty() or not def.get("tabletop_eligible", false):
		return false
	return fits_surface(def["bounds"], surface, rel_steps)


## The item's footprint box, turned by rel_steps x 45 degrees in the host's frame,
## must lie inside the usable rectangle: no overhang at any rotation.
static func fits_surface(bounds: Vector3, surface: Dictionary, rel_steps := 0) -> bool:
	var a := posmod(rel_steps, 8) * TAU / 8.0
	var w := absf(bounds.x * cos(a)) + absf(bounds.z * sin(a))
	var d := absf(bounds.x * sin(a)) + absf(bounds.z * cos(a))
	var area: Vector2 = surface["usable_size_xz"]
	return w <= area.x + 0.001 and d <= area.y + 0.001


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
