## The miniature city district (design/city-district.md): the one source of layout data.
##
## Pure data, like zoo_map.gd. The art (world/city_world.gd, art/props_city.gd) and the navigation
## (core/city_nav.gd) both read it, so a wall, a railing, a stair and a walkable floor always agree.
## 1 unit = 1 m, +x east, +z south (toward the default camera), y up. Child H = 1.30.
##
## Levels:
##   ground (y = 0): one walkable plane over the whole map. GROUND_WALLS and GROUND_SOLIDS (and every
##     FURNITURE item whose region is "ground") are obstacles on it. Building ground floors are part of
##     the ground plane: their walls are GROUND_WALLS and their open fronts are simply where no wall is.
##   REGIONS (y > 0): rectangles at a height, minus their "holes" (stair wells). Two regions, a region and
##     a stair, or a stair and the ground connect where their rectangles share an edge segment at least
##     0.8 m long at the same height. Every other edge of an upper region or stair is a railing or wall:
##     nothing walks off it. DOOR regions are short thin rectangles bridging a wall.
##   STAIRS: straight runs. "up" names the side that is high: "-z" means y0 at the +z edge and y1 at the
##     -z edge. A stair's two ends connect; its long sides are railings.
##   OCCLUDERS: surfaces nobody walks on (roofs) that still stop a tap (picking is floor-aware).
extends RefCounted

const SPACE := "city"
const HALF := Vector2(36.0, 28.0)
const LEVEL_H := 3.2          # one storey, floor to floor
const SLAB := 0.2             # floor thickness (below the walking surface)

## The bus stop: where a traveller arrives, the way out, and four arrival places beside the shelter.
const BUS_STOP := Vector2(-22.6, 4.0)
const ARRIVALS := [Vector2(-22.4, 2.4), Vector2(-22.4, 5.6), Vector2(-21.4, 2.4), Vector2(-21.4, 5.6)]
const ARRIVAL_RY := PI * 0.5      # facing east, into the district
const BUS_REACH := 2.0

## Palette (the brief: bright blue, warm yellow, coral; the wheel berry-red and cream; a white world).
const COLORS := {
	# city r2 (user, 2026-11-17): brighter and cleaner, never grey. A fresh blue office; coral-orange roofs;
	# the central tower in warm white with light peach accents; a soft cream-yellow cafe; mint for the shop
	# row; a berry-red wheel with pastel cabins; a light cool-grey ground; natural greens.
	# city r3 (user, 2026-11-17, superseding r2 where they differ): a blue main building, a coral-orange
	# central building, a warm-yellow restaurant building (the cafe), mint shops, dark-green roofs.
	"blue": Color("#4fb0ff"), "blue_trim": Color("#e8f5ff"),
	"yellow": Color("#ffd46a"), "yellow_trim": Color("#fff6dc"),
	"coral": Color("#ff8a5b"), "peach": Color("#ffd2b8"),            # the central tower: body, light accents
	"roof": Color("#2e8a5f"),                                          # every roof edge and cap: dark green
	"mint": Color("#9fe5c8"), "mint_deep": Color("#5fcfa4"),
	"cream": Color("#fff6e6"), "berry": Color("#c8325a"), "white": Color("#ffffff"),
	"road": Color("#b3bac4"), "pavement": Color("#eef1f4"), "kerb": Color("#dde2e8"), "ground": Color("#e6eaee"),
	"glass": Color("#d6efff"), "wood": Color("#d2a273"), "green": Color("#6db35a"), "green_deep": Color("#4f9a48"),
	"dark": Color("#3a3f47"),
}
## The Ferris wheel's cabins, each its own pastel (r2).
const CABIN_COLORS := [Color("#ffc8d6"), Color("#bfe4ff"), Color("#c6f0d6"), Color("#fff0ad"), Color("#e2d3ff"),
	Color("#ffd8b5"), Color("#c3efee"), Color("#ffdcef")]
## Each shop's colour in the mint row (r2): mint fronts, each with its own accent.
const SHOP_ACCENTS := {"bakery": Color("#ffd7a8"), "corner_cafe": Color("#ffb9a3"), "bookstore": Color("#bfe4ff"),
	"flowers": Color("#ffc8d6"), "icecream": Color("#fff0ad")}

## Roads and pavements (all walkable at y = 0; traffic yields to children, see VEHICLES).
const ROAD_OUTER := Rect2(-31.0, -23.0, 62.0, 46.0)
const ROAD_INNER := Rect2(-25.0, -17.0, 50.0, 34.0)     # the road is the band between the two
const LOT := Rect2(-23.0, -15.0, 46.0, 30.0)            # the block pavement is ROAD_INNER minus LOT
const OUTER_PAVEMENT := Rect2(-33.0, -25.0, 66.0, 50.0)  # the outer pavement is this minus ROAD_OUTER
const CROSSINGS := [Rect2(-3.0, 17.0, 6.0, 6.0), Rect2(-3.0, -23.0, 6.0, 6.0), Rect2(25.0, -3.0, 6.0, 6.0), Rect2(-31.0, -3.0, 6.0, 6.0)]

## Buildings, for the art. "floors" are the walking heights inside; "open" names the cutaway face
## (no wall, so the furnished interior shows; upper floors get a railing there); "roof" is the top.
const BUILDINGS := {
	"office": {"rect": Rect2(-23.0, -14.0, 12.0, 12.0), "color": "blue", "floors": [0.0, 3.2, 6.4], "roof": 9.6, "open": "+z",
		"name": "Office"},
	"cafe": {"rect": Rect2(-7.0, -11.0, 10.0, 10.0), "color": "yellow", "floors": [0.0], "roof": 3.2, "open": "+z",
		"name": "Cafe", "roof_terrace": "cafe_terrace"},
	"gym": {"rect": Rect2(7.0, -14.0, 12.0, 11.0), "color": "coral", "floors": [0.0, 3.2], "roof": 6.4, "open": "+z",
		"name": "Gym", "roof_terrace": "gym_roof"},
	# The shop row (refinement): each front is two display windows either side of a framed door ("front":
	# "windows"); "sign" is its English shop sign.
	"bakery": {"rect": Rect2(-23.0, 8.0, 6.0, 7.0), "color": "cream", "floors": [0.0], "roof": 3.4, "open": "", "front": "windows", "name": "Bakery", "sign": "BAKERY", "shop": true},
	"corner_cafe": {"rect": Rect2(-17.0, 8.0, 6.0, 7.0), "color": "coral", "floors": [0.0], "roof": 3.4, "open": "", "front": "windows", "name": "Cafe", "sign": "CAFE", "shop": true},
	"bookstore": {"rect": Rect2(-11.0, 8.0, 6.0, 7.0), "color": "yellow", "floors": [0.0], "roof": 3.4, "open": "", "front": "windows", "name": "Bookstore", "sign": "BOOKS", "shop": true},
	"flowers": {"rect": Rect2(-5.0, 8.0, 6.0, 7.0), "color": "blue", "floors": [0.0], "roof": 3.4, "open": "", "front": "windows", "name": "Flower shop", "sign": "FLOWERS", "shop": true},
	"icecream": {"rect": Rect2(1.0, 8.0, 6.0, 7.0), "color": "cream", "floors": [0.0], "roof": 3.4, "open": "", "front": "windows", "name": "Ice cream", "sign": "ICE CREAM", "shop": true},
}

## Walls at ground level (thin obstacles; the art raises them to the building's height, leaving the open
## faces and the doors listed in REGIONS).
const GROUND_WALLS := [
	Rect2(-23.0, -14.0, 0.3, 12.0), Rect2(-23.0, -14.0, 12.0, 0.3), Rect2(-11.3, -14.0, 0.3, 12.0),     # office
	Rect2(-7.0, -11.0, 0.3, 10.0), Rect2(-7.0, -11.0, 10.0, 0.3), Rect2(2.7, -11.0, 0.3, 10.0),          # cafe
	Rect2(7.0, -14.0, 0.3, 11.0), Rect2(7.0, -14.0, 12.0, 0.3), Rect2(18.7, -14.0, 0.3, 11.0),           # gym
	Rect2(-23.0, 8.0, 30.0, 0.3),                                                                       # shops: back wall
	Rect2(-23.0, 8.0, 0.3, 7.0), Rect2(-17.15, 8.0, 0.3, 7.0), Rect2(-11.15, 8.0, 0.3, 7.0),             # shop dividers
	Rect2(-5.15, 8.0, 0.3, 7.0), Rect2(0.85, 8.0, 0.3, 7.0), Rect2(6.7, 8.0, 0.3, 7.0),
	# shop fronts (refinement): display windows either side of a 1.6 m door in each unit
	Rect2(-22.85, 14.7, 2.05, 0.3), Rect2(-19.2, 14.7, 2.05, 0.3),
	Rect2(-16.85, 14.7, 2.05, 0.3), Rect2(-13.2, 14.7, 2.05, 0.3),
	Rect2(-10.85, 14.7, 2.05, 0.3), Rect2(-7.2, 14.7, 2.05, 0.3),
	Rect2(-4.85, 14.7, 2.05, 0.3), Rect2(-1.2, 14.7, 2.05, 0.3),
	Rect2(1.15, 14.7, 2.05, 0.3), Rect2(4.8, 14.7, 2.05, 0.3),
]
## The door in each shop front (for the art's door frames): x from, x to, at z 14.7..15.0.
const SHOP_DOORS := {"bakery": Vector2(-20.8, -19.2), "corner_cafe": Vector2(-14.8, -13.2), "bookstore": Vector2(-8.8, -7.2),
	"flowers": Vector2(-2.8, -1.2), "icecream": Vector2(3.2, 4.8)}

## Solid things on the ground (rects or circles). Stair footprints are solid: nobody walks under a stair.
const GROUND_SOLIDS := [
	{"rect": Rect2(-10.8, -9.0, 1.6, 6.0), "kind": "stair_base"},
	{"rect": Rect2(5.2, -9.4, 1.6, 6.0), "kind": "stair_base"},
	{"rect": Rect2(-24.8, 2.0, 1.2, 4.0), "kind": "bus_shelter"},
	# Two A-frames, a leg either side of the wheel's plane (city A1: room for 1.2 m deep gondolas).
	{"at": Vector2(11.6, 3.0), "r": 0.4, "kind": "wheel_leg"}, {"at": Vector2(11.6, 5.0), "r": 0.4, "kind": "wheel_leg"},
	{"at": Vector2(20.4, 3.0), "r": 0.4, "kind": "wheel_leg"}, {"at": Vector2(20.4, 5.0), "r": 0.4, "kind": "wheel_leg"},
	{"rect": Rect2(14.2, 3.2, 3.6, 1.6), "kind": "wheel_platform"},
	{"at": Vector2(15.5, 12.2), "r": 2.9, "kind": "carousel"},   # r2: the carousel and its low fence
	{"at": Vector2(-20.0, 0.5), "r": 0.5, "kind": "tree"}, {"at": Vector2(-13.0, 0.5), "r": 0.5, "kind": "tree"},
	{"at": Vector2(-5.0, 2.5), "r": 0.5, "kind": "tree"}, {"at": Vector2(5.0, 2.5), "r": 0.5, "kind": "tree"},
	{"at": Vector2(22.0, -6.0), "r": 0.5, "kind": "tree"}, {"at": Vector2(22.0, 11.0), "r": 0.5, "kind": "tree"},
	{"rect": Rect2(-17.5, 4.6, 3.0, 0.8), "kind": "planter"}, {"rect": Rect2(-1.5, 4.6, 3.0, 0.8), "kind": "planter"},
	# flower beds (refinement), clear of every door, stair foot and front
	{"rect": Rect2(-22.5, -1.6, 4.0, 0.8), "kind": "flower_bed"}, {"rect": Rect2(-15.5, -1.6, 3.0, 0.8), "kind": "flower_bed"},
	{"rect": Rect2(-6.5, -0.6, 2.4, 0.8), "kind": "flower_bed"}, {"rect": Rect2(0.4, -0.6, 2.4, 0.8), "kind": "flower_bed"},
	{"rect": Rect2(19.4, -2.6, 3.0, 0.8), "kind": "flower_bed"}, {"rect": Rect2(10.0, 8.5, 3.0, 0.8), "kind": "flower_bed"},
	{"rect": Rect2(19.5, 8.5, 3.0, 0.8), "kind": "flower_bed"}, {"rect": Rect2(-24.6, -12.0, 1.2, 4.0), "kind": "flower_bed"},
	{"at": Vector2(-24.0, -10.0), "r": 0.2, "kind": "lamp"}, {"at": Vector2(-24.0, 10.0), "r": 0.2, "kind": "lamp"},
	{"at": Vector2(24.0, -10.0), "r": 0.2, "kind": "lamp"}, {"at": Vector2(24.0, 10.0), "r": 0.2, "kind": "lamp"},
	{"at": Vector2(0.0, 16.0), "r": 0.2, "kind": "lamp"}, {"at": Vector2(0.0, -16.0), "r": 0.2, "kind": "lamp"},
]

## Paved pedestrian paths on the ground (refinement): drawn by the art, walkable like the rest of the ground.
const PATHS := [Rect2(-23.0, 5.6, 32.0, 1.4), Rect2(-1.0, -1.0, 2.0, 6.6), Rect2(9.0, 5.6, 14.0, 1.4), Rect2(-10.6, -2.6, 3.2, 8.2)]

## Upper walkable regions. kind: floor | door | skywalk | terrace | balcony.
const REGIONS := {
	"office_l1": {"rect": Rect2(-22.7, -13.7, 11.4, 11.7), "y": 3.2, "kind": "floor", "building": "office", "holes": [Rect2(-13.1, -9.5, 1.6, 6.0)]},
	"office_l2": {"rect": Rect2(-22.7, -13.7, 11.4, 11.7), "y": 6.4, "kind": "floor", "building": "office", "holes": [Rect2(-13.1, -9.5, 1.6, 6.0)]},
	"office_balcony": {"rect": Rect2(-22.0, -2.0, 10.0, 1.5), "y": 6.4, "kind": "balcony", "building": "office", "holes": []},
	"office_door_l1": {"rect": Rect2(-11.3, -10.8, 0.3, 1.6), "y": 3.2, "kind": "door", "building": "office", "holes": []},
	"skywalk_a": {"rect": Rect2(-11.0, -11.0, 4.0, 2.0), "y": 3.2, "kind": "skywalk", "building": "", "holes": []},
	"cafe_terrace": {"rect": Rect2(-7.0, -11.0, 10.0, 10.0), "y": 3.2, "kind": "terrace", "building": "cafe", "holes": []},
	"skywalk_b": {"rect": Rect2(3.0, -11.0, 4.0, 1.6), "y": 3.2, "kind": "skywalk", "building": "", "holes": []},
	"gym_door_l1": {"rect": Rect2(7.0, -11.0, 0.3, 1.6), "y": 3.2, "kind": "door", "building": "gym", "holes": []},
	"gym_l1": {"rect": Rect2(7.3, -13.7, 11.4, 10.7), "y": 3.2, "kind": "floor", "building": "gym", "holes": [Rect2(17.1, -10.0, 1.6, 6.0)]},
	"gym_roof": {"rect": Rect2(7.0, -14.0, 12.0, 11.0), "y": 6.4, "kind": "terrace", "building": "gym", "holes": [Rect2(17.1, -10.0, 1.6, 6.0)]},
	# refinement: a furnished terrace along the coral tower's first floor (tables, planters, a canopy)
	"gym_terrace": {"rect": Rect2(7.3, -3.0, 11.4, 1.6), "y": 3.2, "kind": "terrace", "building": "gym", "holes": []},
}

## Straight stairs (16 steps of 0.2 m over 6 m: 0.375 m treads). See "up" above.
const STAIRS := {
	# "building": the interior stairs belong to the storey they start from (hidden with it by the cutaway).
	"st_office": {"rect": Rect2(-10.8, -9.0, 1.6, 6.0), "up": "-z", "y0": 0.0, "y1": 3.2, "building": ""},
	"st_office2": {"rect": Rect2(-13.1, -9.5, 1.6, 6.0), "up": "-z", "y0": 3.2, "y1": 6.4, "building": "office"},
	"st_gym": {"rect": Rect2(5.2, -9.4, 1.6, 6.0), "up": "-z", "y0": 0.0, "y1": 3.2, "building": ""},
	"st_gym2": {"rect": Rect2(17.1, -10.0, 1.6, 6.0), "up": "-z", "y0": 3.2, "y1": 6.4, "building": "gym"},
}
const STEPS := 16

## Surfaces nobody walks on that still stop a tap and hide what is under them.
const OCCLUDERS := [
	{"rect": Rect2(-23.0, -14.0, 12.0, 12.0), "y": 9.6, "name": "office_roof"},
	{"rect": Rect2(-23.0, 8.0, 30.0, 7.0), "y": 3.4, "name": "shops_roof"},
]

## Furniture: drawn by the art, solid for the navigation (rect footprints), in a region ("ground" or a
## REGIONS id). "kind" names the builder in props_city.gd.
const FURNITURE := [
	# the cafe (ground)
	{"region": "ground", "kind": "counter", "rect": Rect2(-4.0, -10.6, 4.0, 0.8)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(-4.7, -6.6, 0.8, 0.8)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(0.3, -5.1, 0.8, 0.8)},
	{"region": "ground", "kind": "shelf", "rect": Rect2(-6.6, -10.6, 0.5, 3.0)},
	# the cafe terrace (L1)
	{"region": "cafe_terrace", "kind": "cafe_table", "rect": Rect2(-4.6, -6.0, 0.8, 0.8)},
	{"region": "cafe_terrace", "kind": "cafe_table", "rect": Rect2(-0.6, -6.0, 0.8, 0.8)},
	{"region": "cafe_terrace", "kind": "umbrella_table", "rect": Rect2(-2.6, -3.0, 0.8, 0.8)},
	{"region": "cafe_terrace", "kind": "planter", "rect": Rect2(0.8, -10.6, 1.2, 0.6)},   # 1 m clear of skywalk_b's mouth (city S1)
	# the rooftop restaurant (gym roof, L2)
	{"region": "gym_roof", "kind": "dining_table", "rect": Rect2(10.3, -8.4, 1.0, 1.0)},
	{"region": "gym_roof", "kind": "dining_table", "rect": Rect2(13.3, -6.4, 1.0, 1.0)},
	{"region": "gym_roof", "kind": "kitchen_bar", "rect": Rect2(8.0, -13.4, 4.0, 0.8)},
	{"region": "gym_roof", "kind": "planter", "rect": Rect2(13.4, -13.4, 2.0, 0.6)},
	# the gym (ground) and its studio (L1)
	{"region": "ground", "kind": "treadmill", "rect": Rect2(9.1, -13.2, 0.8, 1.8)},
	{"region": "ground", "kind": "treadmill", "rect": Rect2(11.1, -13.2, 0.8, 1.8)},
	{"region": "ground", "kind": "weight_rack", "rect": Rect2(14.4, -13.3, 1.6, 0.7)},
	{"region": "ground", "kind": "mat", "rect": Rect2(9.0, -8.0, 2.0, 1.2)},
	{"region": "gym_l1", "kind": "bike", "rect": Rect2(9.6, -12.9, 0.8, 1.2)},
	{"region": "gym_l1", "kind": "bike", "rect": Rect2(11.6, -12.9, 0.8, 1.2)},
	{"region": "gym_l1", "kind": "mirror_wall", "rect": Rect2(7.4, -13.6, 6.0, 0.2)},
	# the office (L0 lobby, L1 and L2 desks)
	{"region": "ground", "kind": "reception", "rect": Rect2(-19.0, -6.0, 3.0, 0.8)},
	{"region": "ground", "kind": "sofa", "rect": Rect2(-22.4, -9.0, 0.9, 2.2)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-20.6, -11.0, 1.4, 0.8)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-17.6, -11.0, 1.4, 0.8)},
	{"region": "office_l1", "kind": "plant", "rect": Rect2(-22.4, -13.4, 0.6, 0.6)},
	{"region": "office_l2", "kind": "meeting_table", "rect": Rect2(-20.0, -10.0, 3.0, 1.4)},
	{"region": "office_l2", "kind": "plant", "rect": Rect2(-15.0, -13.4, 0.6, 0.6)},
	# the shops (ground): a sales counter just inside each door; display tables and shelves behind
	{"region": "ground", "kind": "shop_counter", "rect": Rect2(-19.0, 12.6, 1.8, 0.7)},
	{"region": "ground", "kind": "shop_counter", "rect": Rect2(-13.0, 12.6, 1.8, 0.7)},
	{"region": "ground", "kind": "shop_counter", "rect": Rect2(-7.0, 12.6, 1.8, 0.7)},
	{"region": "ground", "kind": "shop_counter", "rect": Rect2(-1.0, 12.6, 1.8, 0.7)},
	{"region": "ground", "kind": "shop_counter", "rect": Rect2(5.0, 12.6, 1.8, 0.7)},
	{"region": "ground", "kind": "bread_display", "rect": Rect2(-22.4, 9.0, 3.0, 0.8)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(-16.0, 10.0, 0.8, 0.8)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(-13.0, 9.6, 0.8, 0.8)},
	{"region": "ground", "kind": "bookshelf", "rect": Rect2(-10.4, 8.4, 4.8, 0.6)},
	{"region": "ground", "kind": "flower_stand", "rect": Rect2(-4.4, 9.0, 3.0, 0.8)},
	{"region": "ground", "kind": "freezer", "rect": Rect2(1.6, 8.6, 2.6, 0.9)},
	# outdoor seating on the pavement in front of the bakery, the cafe and the bookstore (1.1 m left to walk)
	{"region": "ground", "kind": "bistro_table", "rect": Rect2(-22.4, 15.2, 0.7, 0.7)},
	{"region": "ground", "kind": "bistro_table", "rect": Rect2(-16.4, 15.2, 0.7, 0.7)},
	{"region": "ground", "kind": "bistro_table", "rect": Rect2(-12.2, 15.2, 0.7, 0.7)},
	{"region": "ground", "kind": "bistro_table", "rect": Rect2(-10.4, 15.2, 0.7, 0.7)},
	# the yellow cafe: a coffee bar (espresso machine, stools) and a dining area
	{"region": "ground", "kind": "coffee_bar", "rect": Rect2(-6.6, -7.6, 0.8, 3.2)},
	{"region": "ground", "kind": "dining_table", "rect": Rect2(0.6, -9.0, 1.2, 0.9)},
	# the coral tower: its first-floor terrace, and the rooftop restaurant's pavilion and canopies
	{"region": "gym_terrace", "kind": "bistro_table", "rect": Rect2(9.0, -2.4, 0.7, 0.7)},
	{"region": "gym_terrace", "kind": "bistro_table", "rect": Rect2(12.6, -2.4, 0.7, 0.7)},
	{"region": "gym_terrace", "kind": "planter", "rect": Rect2(16.6, -2.6, 1.6, 0.5)},
	{"region": "gym_roof", "kind": "pavilion_post", "rect": Rect2(7.6, -13.6, 0.3, 0.3)},
	{"region": "gym_roof", "kind": "pavilion_post", "rect": Rect2(15.7, -13.6, 0.3, 0.3)},
	{"region": "gym_roof", "kind": "pavilion_post", "rect": Rect2(7.6, -10.6, 0.3, 0.3)},
	{"region": "gym_roof", "kind": "pavilion_post", "rect": Rect2(15.7, -10.6, 0.3, 0.3)},
	{"region": "gym_roof", "kind": "planter", "rect": Rect2(8.0, -4.0, 1.6, 0.5)},
	# the cafe terrace: canopies over the tables
	{"region": "cafe_terrace", "kind": "planter", "rect": Rect2(-6.4, -1.8, 1.6, 0.5)},
	# the office (blue): desks with computers and bookshelves on both floors
	{"region": "office_l1", "kind": "bookshelf", "rect": Rect2(-22.6, -12.0, 0.5, 3.0)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-20.6, -6.6, 1.4, 0.8)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-17.6, -6.6, 1.4, 0.8)},
	{"region": "office_l2", "kind": "bookshelf", "rect": Rect2(-22.6, -12.0, 0.5, 3.0)},
	{"region": "office_l2", "kind": "desk", "rect": Rect2(-20.6, -6.0, 1.4, 0.8)},
	{"region": "ground", "kind": "bookshelf", "rect": Rect2(-15.0, -13.6, 3.0, 0.5)},
	# city r2: the furniture the city's people use (never a child's place), solid like the rest
	{"region": "ground", "kind": "treadmill", "rect": Rect2(13.1, -13.2, 0.8, 1.8)},
	{"region": "ground", "kind": "rower", "rect": Rect2(13.0, -9.8, 2.0, 0.6)},
	{"region": "gym_l1", "kind": "bike", "rect": Rect2(13.6, -12.9, 0.8, 1.2)},
	{"region": "gym_l1", "kind": "bike", "rect": Rect2(15.6, -12.9, 0.8, 1.2)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-14.8, -6.6, 1.4, 0.8)},
	{"region": "office_l1", "kind": "desk", "rect": Rect2(-14.8, -11.0, 1.4, 0.8)},
	{"region": "office_l2", "kind": "desk", "rect": Rect2(-17.6, -6.0, 1.4, 0.8)},
	{"region": "office_l2", "kind": "desk", "rect": Rect2(-14.8, -6.0, 1.4, 0.8)},
	{"region": "gym_roof", "kind": "dining_table", "rect": Rect2(8.2, -6.2, 1.0, 1.0)},
	{"region": "gym_roof", "kind": "dining_table", "rect": Rect2(15.4, -9.0, 1.0, 1.0)},
	{"region": "gym_roof", "kind": "dining_table", "rect": Rect2(10.4, -5.2, 1.0, 1.0)},
	{"region": "cafe_terrace", "kind": "dining_table", "rect": Rect2(-4.5, -9.2, 1.0, 1.0)},
	{"region": "cafe_terrace", "kind": "dining_table", "rect": Rect2(-1.0, -9.2, 1.0, 1.0)},
	{"region": "gym_terrace", "kind": "bistro_table", "rect": Rect2(15.0, -2.4, 0.7, 0.7)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(-2.3, -4.4, 0.8, 0.8)},
	{"region": "ground", "kind": "cafe_table", "rect": Rect2(-5.6, -3.2, 0.8, 0.8)},
]

## Things a child can do (the action button offers them within REACH of "pos" on the same region).
## kind: seat (sit; shared, one child per seat), order (a drink or a dish appears), exercise (the
## avatar runs, cycles or lifts in place; one child per machine), desk (sit and type), shop (a short
## line and a little thing), ride (the Ferris wheel), travel (the bus).
const REACH := 1.4
const INTERACTIONS := {
	"cafe_counter": {"region": "ground", "pos": Vector2(-2.0, -9.4), "kind": "order", "label": "Order a hot chocolate"},
	"cafe_seat_a": {"region": "ground", "pos": Vector2(-5.2, -6.2), "kind": "seat", "label": "Sit down"},
	"cafe_seat_b": {"region": "ground", "pos": Vector2(-3.4, -6.2), "kind": "seat", "label": "Sit down"},
	"cafe_seat_c": {"region": "ground", "pos": Vector2(-0.2, -4.7), "kind": "seat", "label": "Sit down"},
	"cafe_seat_d": {"region": "ground", "pos": Vector2(1.6, -4.7), "kind": "seat", "label": "Sit down"},
	"terrace_seat_a": {"region": "cafe_terrace", "pos": Vector2(-5.1, -5.6), "kind": "seat", "label": "Sit down"},
	"terrace_seat_b": {"region": "cafe_terrace", "pos": Vector2(-1.1, -5.6), "kind": "seat", "label": "Sit down"},
	"restaurant_order": {"region": "gym_roof", "pos": Vector2(10.0, -12.2), "kind": "order", "label": "Order dinner"},
	"restaurant_seat_a": {"region": "gym_roof", "pos": Vector2(9.8, -7.9), "kind": "seat", "label": "Sit down"},
	"restaurant_seat_b": {"region": "gym_roof", "pos": Vector2(11.8, -7.9), "kind": "seat", "label": "Sit down"},
	"restaurant_seat_c": {"region": "gym_roof", "pos": Vector2(12.8, -5.9), "kind": "seat", "label": "Sit down"},
	"restaurant_seat_d": {"region": "gym_roof", "pos": Vector2(14.8, -5.9), "kind": "seat", "label": "Sit down"},
	"gym_treadmill_a": {"region": "ground", "pos": Vector2(9.5, -12.3), "kind": "exercise", "label": "Run on the treadmill"},
	"gym_treadmill_b": {"region": "ground", "pos": Vector2(11.5, -12.3), "kind": "exercise", "label": "Run on the treadmill"},
	"gym_weights": {"region": "ground", "pos": Vector2(15.2, -12.2), "kind": "exercise", "label": "Lift the weights"},
	"studio_bike_a": {"region": "gym_l1", "pos": Vector2(10.0, -12.3), "kind": "exercise", "label": "Ride the bike"},
	"studio_bike_b": {"region": "gym_l1", "pos": Vector2(12.0, -12.3), "kind": "exercise", "label": "Ride the bike"},
	"office_desk_a": {"region": "office_l1", "pos": Vector2(-19.9, -10.0), "kind": "desk", "label": "Work at the desk"},
	"office_desk_b": {"region": "office_l1", "pos": Vector2(-16.9, -10.0), "kind": "desk", "label": "Work at the desk"},
	# shops (refinement): the child stands just inside the door, beside the sales counter
	"shop_bakery": {"region": "ground", "pos": Vector2(-20.0, 13.9), "kind": "shop", "label": "Buy a bun"},
	"shop_cafe": {"region": "ground", "pos": Vector2(-14.0, 13.9), "kind": "shop", "label": "Buy a cupcake"},
	"shop_books": {"region": "ground", "pos": Vector2(-8.0, 13.9), "kind": "shop", "label": "Read a book"},
	"shop_flowers": {"region": "ground", "pos": Vector2(-2.0, 13.9), "kind": "shop", "label": "Buy a flower"},
	"shop_icecream": {"region": "ground", "pos": Vector2(4.0, 13.9), "kind": "shop", "label": "Buy an ice cream"},
	"ferris_board": {"region": "ground", "pos": Vector2(16.0, 5.4), "kind": "ride", "label": "Ride the wheel"},
	"bus_stop": {"region": "ground", "pos": BUS_STOP, "kind": "travel", "label": "Ride home"},
}

## The Ferris wheel: in the x-y plane at z = plane_z, facing the default camera. A gondola hangs
## level below its rim point; the lowest gondola's floor is at board_y beside the platform.
const FERRIS := {"hub": Vector3(16.0, 7.6, 4.0), "radius": 6.0, "gondolas": 8, "period": 80.0,
	"hang": 1.25, "board_at": Vector2(16.0, 5.4), "board_y": 0.35, "board_window": 6.0, "seats": 2}

## Traffic (one-way, clockwise, on the road's centre line) and people on the block pavement. Vehicles
## stop while a child is within 3.5 m ahead in their lane. Bounded: a bus and two cars; four walkers.
const ROAD_LOOP := [Vector2(-28.0, -20.0), Vector2(28.0, -20.0), Vector2(28.0, 20.0), Vector2(-28.0, 20.0)]
const BUS_BAY := Vector2(-28.0, 4.0)
## r2 (user, 2026-11-17): three buses in different colours and the two cars, one lane, clockwise. Nobody
## passes: each keeps at least GAP behind the one ahead (bumper to bumper) and slows smoothly. A bus stops for
## DWELL seconds at each BUS_STOPS point; whoever is behind waits. Everything still stops for a child ahead.
const VEHICLES := [
	{"kind": "bus", "length": 7.0, "speed": 3.0, "start": 0.02, "color": Color("#4fb0ff")},
	{"kind": "car", "length": 3.6, "speed": 4.0, "start": 0.20, "color": Color("#ff8552")},
	{"kind": "bus", "length": 7.0, "speed": 3.0, "start": 0.36, "color": Color("#ffd75e")},
	{"kind": "car", "length": 3.6, "speed": 3.6, "start": 0.55, "color": Color("#9fe5c8")},
	{"kind": "bus", "length": 7.0, "speed": 3.0, "start": 0.70, "color": Color("#c8325a")},
]
const VEHICLE_GAP := 3.0
const BUS_DWELL := 3.0
## Bus stops on the road's centre line (a sign and a shelter or pole on the pavement beside each): the town
## tram's bus bay on the west side, then one on each other side. The west one is where children arrive.
const BUS_STOPS := [Vector2(-28.0, 4.0), Vector2(8.0, -20.0), Vector2(28.0, -4.0), Vector2(-8.0, 20.0)]   # north stop clear of the zebra crossing (A1)
const PED_LOOP := [Vector2(-24.0, -16.0), Vector2(24.0, -16.0), Vector2(24.0, 16.0), Vector2(-24.0, 16.0)]
const PEDESTRIANS := 10   # r2: ten walkers on the block pavement and the paths (arms swing; see CityRules)
## Seated townsfolk (decoration only, never on a child's seat).
const NPC_SEATS := [{"region": "cafe_terrace", "pos": Vector2(-0.1, -6.4)}, {"region": "gym_roof", "pos": Vector2(13.8, -6.9)},
	{"region": "ground", "pos": Vector2(-4.3, -5.4)}]

## What a child is told after ordering or shopping (CityRules.RESULTS line keys -> English, translated).
const LINES := {
	"hot_chocolate": "A warm hot chocolate. Yum!",
	"dinner": "Dinner on the roof! The city looks tiny from up here.",
	"bun": "A warm bun from the bakery.",
	"flower": "A flower to take home.",
	"cupcake": "A cupcake and a cocoa at the little cafe.",
	"book": "You read a picture book.",
	"ice_cream": "A strawberry ice cream!",
}
## How an avatar holds a pose at a seat or machine (CityRules.pose_of -> the avatar's animation and how far
## above the floor its feet sit: a chair's seat, the treadmill's deck, the bike's saddle).
const HOLD_POSES := {"sit": ["sit", 0.44], "type": ["sit", 0.44], "run": ["jog", 0.18], "cycle": ["pedal", 0.55], "lift": ["lift", 0.0]}


# ------------------------------------------------------------------ city r2 (user, 2026-11-17)

## The carousel on the free ground south-east of the wheel. It turns slowly in the direction its horses face
## (counter-clockwise seen from above: the horses' noses point along +angle); each horse bobs on its pole.
## A pure function of the city's shared clock, so every player sees the same turn.
const CAROUSEL := {"center": Vector2(15.5, 12.2), "radius": 2.4, "horses": 8, "period": 22.0, "bob": 0.22,
	"bob_period": 2.6, "roof_y": 3.6}

## How many people live in each part of the city (about 50 in all, user 2026-11-17). Exact places, looks and
## actions are in core/city_people_data.gd; none ever stands or sits on a child's place (INTERACTIONS), and
## the standing ones are solid for children (CityNav).
const PEOPLE_BUDGET := {"office": 6, "restaurant": 7, "cafe": 4, "cafe_terrace": 3, "tower_terrace": 2,
	"shops": 8, "gym": 4, "bistro": 2, "ferris": 4, "carousel": 2, "walkers": 10}

## Look (r2): the places a tap glides the camera to while looking around. `rect` and `y` bound what a tap
## hits (a box, or for the wheel its disc); the view is the focus, yaw (0 looks north, at the open fronts),
## pitch in degrees and distance. A place may name the floors to cut away while it is looked at.
const LOOK_PLACES := {
	"office": {"rect": Rect2(-23.0, -14.0, 12.0, 12.0), "y": Vector2(0.0, 10.4), "focus": Vector3(-17.0, 3.6, -6.5), "yaw": 0.0, "pitch": 22.0, "distance": 15.0, "name": "Office"},
	"cafe": {"rect": Rect2(-7.0, -11.0, 10.0, 10.0), "y": Vector2(0.0, 4.4), "focus": Vector3(-2.0, 1.6, -6.0), "yaw": 0.0, "pitch": 26.0, "distance": 12.0, "name": "Cafe"},
	"tower": {"rect": Rect2(7.0, -14.0, 12.0, 11.0), "y": Vector2(0.0, 6.2), "focus": Vector3(13.0, 3.0, -6.5), "yaw": 0.12, "pitch": 24.0, "distance": 15.0, "name": "Gym"},
	"restaurant": {"rect": Rect2(7.0, -14.0, 12.0, 11.0), "y": Vector2(6.2, 10.0), "focus": Vector3(11.8, 6.9, -9.5), "yaw": 0.35, "pitch": 46.0, "distance": 12.0, "name": "Rooftop restaurant"},
	"bakery": {"rect": Rect2(-23.0, 8.0, 6.0, 7.0), "y": Vector2(0.0, 4.2), "focus": Vector3(-20.0, 1.2, 12.0), "yaw": 0.0, "pitch": 24.0, "distance": 8.5, "name": "Bakery"},
	"corner_cafe": {"rect": Rect2(-17.0, 8.0, 6.0, 7.0), "y": Vector2(0.0, 4.2), "focus": Vector3(-14.0, 1.2, 12.0), "yaw": 0.0, "pitch": 24.0, "distance": 8.5, "name": "Cafe"},
	"bookstore": {"rect": Rect2(-11.0, 8.0, 6.0, 7.0), "y": Vector2(0.0, 4.2), "focus": Vector3(-8.0, 1.2, 12.0), "yaw": 0.0, "pitch": 24.0, "distance": 8.5, "name": "Bookstore"},
	"flowers": {"rect": Rect2(-5.0, 8.0, 6.0, 7.0), "y": Vector2(0.0, 4.2), "focus": Vector3(-2.0, 1.2, 12.0), "yaw": 0.0, "pitch": 24.0, "distance": 8.5, "name": "Flower shop"},
	"icecream": {"rect": Rect2(1.0, 8.0, 6.0, 7.0), "y": Vector2(0.0, 4.2), "focus": Vector3(4.0, 1.2, 12.0), "yaw": 0.0, "pitch": 24.0, "distance": 8.5, "name": "Ice cream"},
	"ferris": {"disc": true, "y": Vector2(0.0, 14.0), "focus": Vector3(16.0, 6.8, 4.0), "yaw": 0.0, "pitch": 10.0, "distance": 21.0, "name": "Ferris wheel"},
	"carousel": {"circle": 2.9, "y": Vector2(0.0, 4.2), "focus": Vector3(15.5, 1.2, 12.2), "yaw": 0.35, "pitch": 30.0, "distance": 9.5, "name": "Carousel"},
}
## The order the controller's D-pad steps through the places while looking (left / right).
const LOOK_ORDER := ["office", "cafe", "tower", "restaurant", "ferris", "carousel", "icecream", "flowers", "bookstore", "corner_cafe", "bakery"]
## The glide between views (seconds, eased in and out; Reduce motion makes it a quick fade of 0.25 s).
const LOOK_GLIDE := 0.9


# ------------------------------------------------------------------ city r3 (user, 2026-11-17)

## The city's weather: shared by everyone in the city (like the town's), chosen with the glass buttons on the
## right. The authority keeps {weather, since}; everything that changes with it (light, rain, wet ground,
## people taking cover and coming back) is a function of the shared clock and `since`, so all players see
## the same city. Sunny is the default (and what a city wakes up with).
const WEATHERS := ["sunny", "rain", "night"]
## Seconds a change takes (eased): light, sky, wetness, lamps. Never a cut, never a reload.
const WEATHER_BLEND := 4.0
## The look of each weather (the owner's lighting; A1's materials read wet and glow).
const WEATHER_LOOK := {
	"sunny": {"sky": Color("#ffffff"), "ambient": Color("#f5f8ff"), "ambient_energy": 0.85, "sun": Color("#fffaf0"),
		"sun_energy": 0.9, "shadow": 0.35, "saturation": 1.12, "wet": 0.0, "glow": 0.0, "rain": 0.0},
	"rain": {"sky": Color("#e9eef3"), "ambient": Color("#e8eef6"), "ambient_energy": 0.8, "sun": Color("#eef3fa"),
		"sun_energy": 0.45, "shadow": 0.15, "saturation": 1.04, "wet": 1.0, "glow": 0.25, "rain": 1.0},
	"night": {"sky": Color("#1d2f5e"), "ambient": Color("#8fa6e0"), "ambient_energy": 0.55, "sun": Color("#b9c8ff"),
		"sun_energy": 0.18, "shadow": 0.2, "saturation": 1.1, "wet": 0.0, "glow": 1.0, "rain": 0.0},
}
## In the rain, people outdoors without an umbrella take cover in staggered groups over this many seconds
## (never vanishing), and drift back over this many after it stops.
const RAIN_COVER_SPREAD := 9.0
const RAIN_RETURN_SPREAD := 12.0
const UMBRELLA_SHARE := 0.35   # about a third of the people outdoors open an umbrella and carry on
