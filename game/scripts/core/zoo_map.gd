## The zoo map as pure data (design/zoo-and-world-journeys.md sections 8 and 22).
##
## No nodes, no scene: positions, sizes and heights in metres (1 unit = 1 m, the town's axes:
## +x east, +z toward the default camera). The world builds from this; the brain moves animals
## on it; the tests measure it against the real camera. This slice holds the plaza and station,
## the Hill Road, Lion Hill and Monkey Hill; the other habitats come later (section 22).
extends RefCounted

const SPACE := "zoo"
## The whole map: 84 x 64 m (section 8.1).
const HALF := Vector2(42.0, 32.0)
## Children arrive on the station platform, facing north (-z), the plaza ahead.
const ARRIVAL := Vector2(0.0, 26.0)
const ARRIVAL_RY := PI
## Four arrival places side by side, so friends never stand in each other.
const ARRIVALS := [Vector2(-1.5, 26.0), Vector2(-0.5, 26.0), Vector2(0.5, 26.0), Vector2(1.5, 26.0)]
## The Zoo Station: the tram stands here; "Ride home" is offered within TRAM_REACH of STATION.
const STATION := Vector2(0.0, 28.6)
const TRAM_REACH := 2.4
## Where friends arrive on the platform is free; the tram itself and its platform edge block.
const PLAZA := Vector2(0.0, 20.0)
const PLAZA_RADIUS := 6.0

## Habitat rectangles: x, z, width, depth.
const HABITATS := {
	"tiger_hill": Rect2(-40.0, -28.0, 22.0, 18.0),
	"lion_hill": Rect2(-12.0, -28.0, 24.0, 18.0),
	"monkey_hill": Rect2(18.0, -28.0, 22.0, 18.0),
	"splash_bay": Rect2(-40.0, -5.5, 22.0, 16.0),
	"savanna": Rect2(-12.0, -5.5, 24.0, 18.0),
	# zoo r2: Bao the panda, on the lawn kept for a later habitat (Picnic Green).
	"bamboo_grove": Rect2(18.0, -5.5, 22.0, 16.0),
}
## English names for the place label at the top ("Zoo · Lion Hill").
const HABITAT_NAMES := {"tiger_hill": "Tiger Hill", "lion_hill": "Lion Hill", "monkey_hill": "Monkey Hill",
	"splash_bay": "Splash Bay", "savanna": "Savanna Meadow", "bamboo_grove": "Bamboo Grove"}
## Lawns kept for later habitats (Picnic Green, the south lawns): open ground in this release.
const LAWNS := {"south_west_lawn": Rect2(-40.0, 15.0, 22.0, 14.0), "south_east_lawn": Rect2(18.0, 15.0, 22.0, 14.0)}

## Kinds of area:
##   "terrace"  raised rock or a structure base an animal uses; children cannot walk onto it
##   "backdrop" a tall crag at the far side; no animal, children cannot walk into it
##   "planting" low planting under a climbing route: children cannot walk there (section 22.5)
##   "path"     ground where children walk
##   "bay"      a viewing bay on a path (ground)
##   "ground"   habitat ground: animals walk here; children may too (no fences, section 8.1)
##   "grass"    tall grass: animals stalk here; children may stand in it
## Each: kind, rect (Rect2 on the ground: x, z, width, depth), height (top of the surface).
const AREAS := {
	# --- Lion Hill (section 8.2), 24 x 18 m: x -12..12, z -28..-10 ---
	"lion_overlook": {"kind": "bay", "rect": Rect2(-3.0, -12.5, 6.0, 2.5), "height": 0.0, "hill": "lion_hill"},
	"lion_sun_rock": {"kind": "terrace", "rect": Rect2(-3.5, -17.5, 7.0, 4.5), "height": 0.7, "hill": "lion_hill"},
	"lion_pass": {"kind": "path", "rect": Rect2(-12.0, -24.0, 3.0, 14.0), "height": 0.0, "hill": "lion_hill"},
	"lion_ridge": {"kind": "terrace", "rect": Rect2(-8.5, -20.0, 3.0, 6.5), "height": 0.9, "hill": "lion_hill"},
	"lion_ridge_view": {"kind": "bay", "rect": Rect2(-12.0, -18.0, 3.0, 3.0), "height": 0.0, "hill": "lion_hill"},
	"lion_back_trail": {"kind": "path", "rect": Rect2(-12.0, -24.0, 24.0, 2.0), "height": 0.0, "hill": "lion_hill"},
	"lion_crag": {"kind": "backdrop", "rect": Rect2(-8.0, -28.0, 16.0, 2.0), "height": 3.0, "hill": "lion_hill"},
	"lion_den": {"kind": "terrace", "rect": Rect2(4.0, -26.0, 4.5, 1.8), "height": 0.0, "hill": "lion_hill"},
	"lion_shady_ledge": {"kind": "terrace", "rect": Rect2(4.0, -21.0, 4.5, 4.0), "height": 0.4, "hill": "lion_hill"},
	"lion_cub_walk": {"kind": "path", "rect": Rect2(9.0, -24.0, 3.0, 14.0), "height": 0.0, "hill": "lion_hill"},
	"lion_den_corner": {"kind": "bay", "rect": Rect2(9.0, -24.0, 3.0, 2.5), "height": 0.0, "hill": "lion_hill"},
	"lion_tall_grass": {"kind": "grass", "rect": Rect2(4.0, -15.5, 4.5, 4.0), "height": 0.0, "hill": "lion_hill"},
	"lion_ground": {"kind": "ground", "rect": Rect2(-9.0, -22.0, 18.0, 12.0), "height": 0.0, "hill": "lion_hill"},
	# --- Monkey Hill (sections 8.4, 22.4, 22.5), 22 x 18 m: x 18..40, z -28..-10 ---
	"monkey_lane": {"kind": "path", "rect": Rect2(27.5, -15.0, 3.0, 5.0), "height": 0.0, "hill": "monkey_hill"},
	"monkey_court": {"kind": "bay", "rect": Rect2(25.5, -23.0, 7.0, 8.0), "height": 0.0, "hill": "monkey_hill"},
	"monkey_ground": {"kind": "ground", "rect": Rect2(18.0, -28.0, 22.0, 18.0), "height": 0.0, "hill": "monkey_hill"},
	# the Ring Run's strip: under the rings, children never walk (22.5 item 3)
	"monkey_ring_strip": {"kind": "planting", "rect": Rect2(22.7, -22.6, 1.6, 8.0), "height": 0.15, "hill": "monkey_hill"},
	"monkey_west_tower": {"kind": "terrace", "rect": Rect2(20.0, -14.0, 2.0, 2.0), "height": 1.6, "hill": "monkey_hill"},
	"monkey_east_tower": {"kind": "terrace", "rect": Rect2(35.5, -15.0, 2.0, 2.0), "height": 1.6, "hill": "monkey_hill"},
	"monkey_west_perch": {"kind": "terrace", "rect": Rect2(20.3, -20.7, 1.4, 1.4), "height": 1.2, "hill": "monkey_hill"},
	# the Net Bridge between the towers' west pair: a beam; the strip under it is planting
	"monkey_bridge_strip": {"kind": "planting", "rect": Rect2(20.4, -19.3, 1.2, 5.3), "height": 0.15, "hill": "monkey_hill"},
	# the vine hangs over planting too
	"monkey_vine_strip": {"kind": "planting", "rect": Rect2(35.2, -20.0, 2.0, 5.0), "height": 0.15, "hill": "monkey_hill"},
	"monkey_rock_a": {"kind": "terrace", "rect": Rect2(35.5, -21.4, 1.4, 1.4), "height": 1.0, "hill": "monkey_hill"},
	"monkey_rock_b": {"kind": "terrace", "rect": Rect2(34.0, -23.8, 1.2, 1.2), "height": 0.7, "hill": "monkey_hill"},
	"monkey_rock_c": {"kind": "terrace", "rect": Rect2(32.3, -25.5, 1.1, 1.1), "height": 0.5, "hill": "monkey_hill"},
	"monkey_spire": {"kind": "terrace", "rect": Rect2(27.6, -28.0, 3.0, 3.0), "height": 2.0, "hill": "monkey_hill"},
	"monkey_hammock": {"kind": "terrace", "rect": Rect2(19.0, -25.2, 2.0, 1.4), "height": 0.8, "hill": "monkey_hill"},
	# the tyre swing hangs over a ring of bark; the bongo logs stand by the court
	"monkey_tyre_ring": {"kind": "planting", "rect": Rect2(32.6, -21.6, 1.6, 2.0), "height": 0.05, "hill": "monkey_hill"},
	# --- Tiger Hill (section 8.3), 22 x 18 m: x -40..-18, z -28..-10 ---
	"tiger_falls": {"kind": "backdrop", "rect": Rect2(-36.0, -28.0, 10.0, 1.6), "height": 2.6, "hill": "tiger_hill"},
	"tiger_falls_ledge": {"kind": "terrace", "rect": Rect2(-26.6, -27.6, 2.6, 2.4), "height": 1.0, "hill": "tiger_hill"},
	"tiger_pool": {"kind": "water", "rect": Rect2(-34.0, -23.5, 8.0, 5.0), "height": 0.0, "hill": "tiger_hill"},
	"tiger_log": {"kind": "terrace", "rect": Rect2(-30.4, -24.0, 0.8, 6.0), "height": 0.6, "hill": "tiger_hill"},
	"tiger_thicket": {"kind": "thicket", "rect": Rect2(-40.0, -24.0, 4.5, 6.0), "height": 0.0, "hill": "tiger_hill"},
	"tiger_slab": {"kind": "terrace", "rect": Rect2(-25.8, -24.6, 2.4, 2.0), "height": 0.4, "hill": "tiger_hill"},
	"tiger_trail_east": {"kind": "path", "rect": Rect2(-22.0, -27.5, 3.0, 17.5), "height": 0.0, "hill": "tiger_hill"},
	"tiger_trail_south": {"kind": "path", "rect": Rect2(-40.0, -16.5, 21.0, 2.5), "height": 0.0, "hill": "tiger_hill"},
	"tiger_falls_bay": {"kind": "bay", "rect": Rect2(-22.0, -27.5, 3.0, 2.5), "height": 0.0, "hill": "tiger_hill"},
	"tiger_pool_bay": {"kind": "bay", "rect": Rect2(-32.0, -16.5, 4.0, 2.5), "height": 0.0, "hill": "tiger_hill"},
	"tiger_thicket_bay": {"kind": "bay", "rect": Rect2(-39.5, -16.5, 4.0, 2.5), "height": 0.0, "hill": "tiger_hill"},
	"tiger_ground": {"kind": "ground", "rect": Rect2(-40.0, -28.0, 22.0, 18.0), "height": 0.0, "hill": "tiger_hill"},
	# --- Savanna Meadow (section 8.5), 24 x 18 m: x -12..12, z -5.5..12.5 ---
	"savanna_ground": {"kind": "ground", "rect": Rect2(-12.0, -5.5, 24.0, 18.0), "height": 0.0, "hill": "savanna"},
	"savanna_waterhole": {"kind": "water", "rect": Rect2(3.0, 0.5, 5.0, 4.0), "height": 0.0, "hill": "savanna"},
	"savanna_gate": {"kind": "bay", "rect": Rect2(-3.0, 10.0, 6.0, 2.5), "height": 0.0, "hill": "savanna"},
	# --- Splash Bay (section 8.5), 22 x 16 m: x -40..-18, z -5.5..10.5 ---
	"splash_ground": {"kind": "ground", "rect": Rect2(-40.0, -5.5, 22.0, 16.0), "height": 0.0, "hill": "splash_bay"},
	"splash_pool": {"kind": "water", "rect": Rect2(-36.0, -3.0, 13.0, 7.2), "height": 0.0, "hill": "splash_bay"},
	"splash_beach": {"kind": "bay", "rect": Rect2(-36.0, 6.0, 13.0, 3.0), "height": 0.0, "hill": "splash_bay"},
	"splash_jetty": {"kind": "bay", "rect": Rect2(-30.6, 4.2, 1.6, 1.8), "height": 0.0, "hill": "splash_bay"},
	"splash_slide": {"kind": "terrace", "rect": Rect2(-22.6, -2.6, 2.2, 3.6), "height": 0.8, "hill": "splash_bay"},
	"splash_bank": {"kind": "path", "rect": Rect2(-40.0, -5.5, 3.6, 16.0), "height": 0.0, "hill": "splash_bay"},
	# Bamboo Grove (zoo r2): open ground like the savanna, a bamboo screen at the back and a clump to
	# munch, a low rock to sit on, and a viewing bay at the front with the treat table.
	"grove_ground": {"kind": "ground", "rect": Rect2(18.0, -5.5, 22.0, 16.0), "height": 0.0, "hill": "bamboo_grove"},
	"grove_bamboo_back": {"kind": "thicket", "rect": Rect2(19.0, -5.2, 20.0, 2.0), "height": 0.0, "hill": "bamboo_grove"},
	"grove_bamboo_clump": {"kind": "thicket", "rect": Rect2(20.0, 3.6, 2.6, 3.0), "height": 0.0, "hill": "bamboo_grove"},
	"grove_rock": {"kind": "terrace", "rect": Rect2(30.0, 3.8, 3.4, 2.4), "height": 0.5, "hill": "bamboo_grove"},
	"grove_gate": {"kind": "bay", "rect": Rect2(22.0, 8.0, 10.0, 2.5), "height": 0.0, "hill": "bamboo_grove"},
	# --- shared ground ---
	"hill_road": {"kind": "path", "rect": Rect2(-42.0, -10.0, 84.0, 4.5), "height": 0.0, "hill": ""},
}
## Round solid things on the ground: trees, posts, the tram. A child slides around them.
const SOLIDS := [
	{"at": Vector2(-27.4, -17.6), "r": 0.35, "kind": "scratch_tree"},
	{"at": Vector2(-8.0, 0.5), "r": 0.45, "kind": "acacia"},
	{"at": Vector2(7.5, 7.5), "r": 0.45, "kind": "acacia"},
	{"at": Vector2(-5.0, 7.0), "r": 0.45, "kind": "acacia"},
	{"at": Vector2(5.8, -10.9), "r": 0.6, "kind": "shade_tree"},
	{"at": Vector2(-22.4, 6.4), "r": 0.35, "kind": "shower"},
	{"at": Vector2(-5.6, 18.4), "r": 0.75, "kind": "bench", "ry": PI * 0.5},
	{"at": Vector2(5.6, 18.4), "r": 0.75, "kind": "bench", "ry": -PI * 0.5},
]

## Spots where an animal does a signature or rests, each seen from a bay (rule H1) or beside a
## path (rule H2). pos is on the ground plane; height is the surface it stands on.
const SPOTS := {
	"lion_sun_rock": {"pos": Vector2(0.0, -13.9), "height": 0.7, "area": "lion_sun_rock", "bay": "lion_overlook", "use": ["bask", "roar", "survey"]},
	"lion_ridge_south": {"pos": Vector2(-7.0, -14.6), "height": 0.9, "area": "lion_ridge", "bay": "lion_ridge_view", "use": ["patrol", "survey"]},
	"lion_ridge_north": {"pos": Vector2(-7.0, -19.0), "height": 0.9, "area": "lion_ridge", "bay": "lion_ridge_view", "use": ["patrol"]},
	"lion_shade": {"pos": Vector2(6.2, -19.0), "height": 0.4, "area": "lion_shady_ledge", "bay": "lion_den_corner", "use": ["nap", "groom"]},
	"lion_den_mouth": {"pos": Vector2(7.6, -25.0), "height": 0.0, "area": "lion_den", "bay": "lion_den_corner", "use": ["shelter", "peek"]},
	"lion_grass": {"pos": Vector2(6.2, -13.5), "height": 0.0, "area": "lion_tall_grass", "bay": "lion_overlook", "use": ["stalk", "pounce"]},
	"tiger_ledge": {"pos": Vector2(-25.3, -26.4), "height": 1.0, "area": "tiger_falls_ledge", "bay": "tiger_falls_bay", "use": ["rest", "leap"]},
	"tiger_swim": {"pos": Vector2(-32.0, -21.0), "height": -0.35, "area": "tiger_pool", "bay": "tiger_pool_bay", "use": ["soak", "swim"]},
	"tiger_log_south": {"pos": Vector2(-30.0, -18.6), "height": 0.6, "area": "tiger_log", "bay": "tiger_pool_bay", "use": ["balance"]},
	"tiger_log_north": {"pos": Vector2(-30.0, -23.4), "height": 0.6, "area": "tiger_log", "bay": "tiger_pool_bay", "use": ["balance"]},
	"tiger_hide": {"pos": Vector2(-37.6, -18.9), "height": 0.0, "area": "tiger_thicket", "bay": "tiger_thicket_bay", "use": ["hide", "peekaboo"]},
	"tiger_slab": {"pos": Vector2(-24.6, -23.6), "height": 0.4, "area": "tiger_slab", "bay": "tiger_falls_bay", "use": ["nap"]},
	"tiger_scratch": {"pos": Vector2(-27.4, -18.2), "height": 0.0, "area": "tiger_ground", "bay": "tiger_pool_bay", "use": ["stretch"]},
	"tiger_treat": {"pos": Vector2(-29.0, -17.5), "height": 0.0, "area": "tiger_ground", "bay": "tiger_pool_bay", "use": ["lick"]},
	"tiger_prowl_a": {"pos": Vector2(-34.8, -17.6), "height": 0.0, "area": "tiger_ground", "bay": "tiger_thicket_bay", "use": ["prowl"]},
	"tiger_prowl_b": {"pos": Vector2(-24.4, -20.6), "height": 0.0, "area": "tiger_ground", "bay": "tiger_falls_bay", "use": ["prowl"]},
	"giraffe_acacia_a": {"pos": Vector2(-7.0, 1.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["browse"]},
	"giraffe_acacia_b": {"pos": Vector2(6.4, 6.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["browse"]},
	"giraffe_acacia_c": {"pos": Vector2(-4.0, 6.0), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["browse"]},
	"savanna_drink": {"pos": Vector2(5.5, 5.3), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["drink"]},
	"savanna_drink_b": {"pos": Vector2(2.4, 2.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["drink"]},
	"zebra_graze_a": {"pos": Vector2(-6.0, -2.5), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["graze"]},
	"zebra_graze_b": {"pos": Vector2(0.5, -1.5), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["graze"]},
	"zebra_graze_c": {"pos": Vector2(9.0, -1.0), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["graze"]},
	"savanna_treat": {"pos": Vector2(-1.0, 8.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["eat"]},
	"hippo_float": {"pos": Vector2(-31.0, 2.4), "height": -0.55, "area": "splash_pool", "bay": "splash_beach", "use": ["float"]},
	"hippo_jetty": {"pos": Vector2(-29.8, 3.0), "height": -0.55, "area": "splash_pool", "bay": "splash_jetty", "use": ["surface"]},
	"hippo_beach": {"pos": Vector2(-34.0, 7.0), "height": 0.0, "area": "splash_beach", "bay": "splash_beach", "use": ["bask"]},
	"hippo_shower": {"pos": Vector2(-23.2, 5.6), "height": 0.0, "area": "splash_ground", "bay": "splash_beach", "use": ["shower"]},
	"otter_float_a": {"pos": Vector2(-27.0, 1.0), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["float"]},
	"otter_float_b": {"pos": Vector2(-26.0, 2.0), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["float"]},
	"otter_slide_top": {"pos": Vector2(-21.5, -2.2), "height": 0.8, "area": "splash_slide", "bay": "splash_beach", "use": ["slide"]},
	"otter_slide_end": {"pos": Vector2(-24.0, 0.8), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["slide"]},
	"otter_beach": {"pos": Vector2(-28.0, 7.0), "height": 0.0, "area": "splash_beach", "bay": "splash_beach", "use": ["juggle", "beg"]},
	"otter_bank": {"pos": Vector2(-35.4, -2.0), "height": -0.3, "area": "splash_pool", "bay": "splash_bank", "use": ["escort"]},
	# zoo r2: Mabel the elephant (Savanna Meadow), Pebble and Flip the penguins (Splash Bay), Bao the
	# panda (Bamboo Grove). Each spot is at least the two animals' radii from every other spot nearby.
	"elephant_dust": {"pos": Vector2(-9.5, 4.0), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["dust", "ear_flap", "trumpet"]},
	"elephant_waterhole": {"pos": Vector2(9.2, 2.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["drink", "spray"]},
	"elephant_treat": {"pos": Vector2(3.5, 8.6), "height": 0.0, "area": "savanna_ground", "bay": "savanna_gate", "use": ["eat"]},
	"penguin_shore_a": {"pos": Vector2(-33.5, 5.0), "height": 0.0, "area": "splash_ground", "bay": "splash_beach", "use": ["preen", "flap"]},
	"penguin_shore_b": {"pos": Vector2(-25.5, 5.1), "height": 0.0, "area": "splash_ground", "bay": "splash_beach", "use": ["preen", "flap", "eat"]},
	"penguin_swim_a": {"pos": Vector2(-25.6, 3.6), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["swim", "dive"]},
	"penguin_swim_b": {"pos": Vector2(-34.0, 3.6), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["swim", "dive"]},
	# The penguins' own belly-slide, from the shore into the pool in front of the beach (the otters' slide
	# stays theirs, and is too far from a bay for a 1.2 m penguin to read at 115 px).
	"penguin_slide_top": {"pos": Vector2(-28.4, 5.0), "height": 0.0, "area": "splash_ground", "bay": "splash_beach", "use": ["slide"]},
	"penguin_slide_end": {"pos": Vector2(-28.4, 3.4), "height": -0.3, "area": "splash_pool", "bay": "splash_beach", "use": ["slide"]},
	"panda_bamboo": {"pos": Vector2(23.5, 5.6), "height": 0.0, "area": "grove_ground", "bay": "grove_gate", "use": ["munch"]},
	"panda_rock": {"pos": Vector2(31.7, 5.0), "height": 0.5, "area": "grove_rock", "bay": "grove_gate", "use": ["sit_up", "nap"]},
	"panda_lawn": {"pos": Vector2(27.4, 5.2), "height": 0.0, "area": "grove_ground", "bay": "grove_gate", "use": ["roll", "play_ball"]},
	"panda_treat": {"pos": Vector2(27.0, 6.9), "height": 0.0, "area": "grove_ground", "bay": "grove_gate", "use": ["eat"]},
	"panda_shade": {"pos": Vector2(35.5, 6.0), "height": 0.0, "area": "grove_ground", "bay": "grove_gate", "use": ["nap"]},
	"splash_treat": {"pos": Vector2(-31.5, 3.4), "height": -0.55, "area": "splash_pool", "bay": "splash_beach", "use": ["chomp"]},
}

## Things a child uses with the action button (X). Each: pos, the species that answers, label.
const STATIONS := {
	"lion_treats": {"pos": Vector2(1.8, -10.6), "hill": "lion_hill", "label": "Offer a treat", "icon": "paw"},
	"tiger_treats": {"pos": Vector2(-28.0, -15.2), "hill": "tiger_hill", "label": "Offer a treat", "icon": "paw"},
	"tiger_ball": {"pos": Vector2(-31.2, -15.2), "hill": "tiger_hill", "label": "Float a ball", "icon": "play"},
	"savanna_treats": {"pos": Vector2(1.6, 11.2), "hill": "savanna", "label": "Offer a treat", "icon": "paw"},
	"savanna_pump": {"pos": Vector2(5.5, 6.9), "hill": "savanna", "label": "Pump water", "icon": "water"},
	"grove_treats": {"pos": Vector2(27.0, 9.4), "hill": "bamboo_grove", "label": "Offer a treat", "icon": "paw"},
	"splash_treats": {"pos": Vector2(-33.0, 8.6), "hill": "splash_bay", "label": "Offer a treat", "icon": "paw"},
	"splash_shower": {"pos": Vector2(-21.6, 7.4), "hill": "splash_bay", "label": "Turn on the shower", "icon": "water"},
	"monkey_tyre": {"pos": Vector2(33.2, -18.8), "hill": "monkey_hill", "label": "Push the swing", "icon": "play"},
	"monkey_bongos": {"pos": Vector2(26.0, -16.0), "hill": "monkey_hill", "label": "Play the drums", "icon": "music"},
	"monkey_bananas": {"pos": Vector2(31.6, -12.0), "hill": "monkey_hill", "label": "Offer a banana", "icon": "paw"},
	"monkey_bell": {"pos": Vector2(29.0, -22.4), "hill": "monkey_hill", "label": "Ring the bell", "icon": "bell"},
}
const STATION_REACH := 1.8

## Monkey Hill's anchors: every place a monkey can be. kind: ground, perch, ring, vine, rock,
## ledge, hammock. Positions are where the monkey's feet are (its body root). On a ring or the
## vine it hangs: its hands are HANG metres above its feet.
const ANCHORS := {
	"m_court_w": {"pos": Vector3(26.4, 0.0, -19.0), "kind": "ground"},
	"m_court_e": {"pos": Vector3(31.6, 0.0, -19.0), "kind": "ground"},
	"m_court_n": {"pos": Vector3(29.0, 0.0, -22.9), "kind": "ground"},
	"m_court_s": {"pos": Vector3(29.0, 0.0, -16.2), "kind": "ground"},
	"m_wt_foot": {"pos": Vector3(22.6, 0.0, -13.0), "kind": "ground"},
	"m_et_foot": {"pos": Vector3(34.6, 0.0, -14.0), "kind": "ground"},
	"m_west_n": {"pos": Vector3(21.0, 0.0, -22.4), "kind": "ground"},
	"m_rocks": {"pos": Vector3(31.4, 0.0, -24.2), "kind": "ground"},
	"m_hammock_foot": {"pos": Vector3(21.6, 0.0, -24.6), "kind": "ground"},
	"m_nook_a": {"pos": Vector3(24.0, 0.0, -25.4), "kind": "ground"},
	"m_nook_b": {"pos": Vector3(24.7, 0.0, -25.6), "kind": "ground"},
	"m_banana": {"pos": Vector3(32.8, 0.0, -13.4), "kind": "ground"},
	"m_tyre": {"pos": Vector3(33.4, 0.5, -20.6), "kind": "swing"},
	"m_west_tower": {"pos": Vector3(21.0, 1.6, -13.0), "kind": "perch"},
	"m_east_tower": {"pos": Vector3(36.5, 1.6, -14.0), "kind": "perch"},
	"m_west_perch": {"pos": Vector3(21.0, 1.2, -20.0), "kind": "perch"},
	"m_ring_s": {"pos": Vector3(23.5, 1.15, -15.0), "kind": "ring"},
	"m_ring_n": {"pos": Vector3(23.5, 1.15, -22.2), "kind": "ring"},
	"m_vine": {"pos": Vector3(36.2, 0.45, -17.6), "kind": "vine"},   # hanging at rest; the pivot is VINE_LENGTH + HANG above
	"m_rock_a": {"pos": Vector3(36.2, 1.0, -20.7), "kind": "rock"},
	"m_rock_b": {"pos": Vector3(34.6, 0.7, -23.2), "kind": "rock"},
	"m_rock_c": {"pos": Vector3(32.85, 0.5, -24.95), "kind": "rock"},
	"m_spire_1": {"pos": Vector3(29.0, 0.8, -25.2), "kind": "ledge"},
	"m_spire_2": {"pos": Vector3(28.4, 1.4, -26.0), "kind": "ledge"},
	"m_spire_3": {"pos": Vector3(29.2, 2.0, -26.9), "kind": "ledge"},
	"m_hammock": {"pos": Vector3(20.0, 0.8, -24.5), "kind": "hammock"},
}
## A hanging monkey: hands this far above its feet (the rings' grips are at 2.7 m).
const HANG := 1.55
## The vine's rope from its pivot (3.6 m up) down to the monkey's grip, and how far it swings each way.
const VINE_LENGTH := 1.6
const VINE_ARC := deg_to_rad(50.0)

## Directed routes between anchors: [from, to, move]. Every move a monkey makes from one anchor
## to another is one of these, so a sequence always starts and ends at a valid anchor.
##   run      on the ground                  climb    up a pole or ledges
##   descend  down head first, then a flip   rings    hand over hand along the Ring Run
##   leap     a jump between perches          drop     from the rings to the ground
##   vine     swing on the vine and let go    hop      a short jump (rocks, hammock)
##   balance  along the Net Bridge's beam
const LINKS := [
	["m_court_w", "m_court_e", "run"], ["m_court_e", "m_court_w", "run"],
	["m_court_w", "m_court_n", "run"], ["m_court_n", "m_court_w", "run"],
	["m_court_e", "m_court_n", "run"], ["m_court_n", "m_court_e", "run"],
	["m_court_s", "m_court_w", "run"], ["m_court_w", "m_court_s", "run"],
	["m_court_s", "m_court_e", "run"], ["m_court_e", "m_court_s", "run"],
	["m_court_w", "m_wt_foot", "run"], ["m_wt_foot", "m_court_w", "run"],
	["m_court_e", "m_et_foot", "run"], ["m_et_foot", "m_court_e", "run"],
	["m_court_n", "m_rocks", "run"], ["m_rocks", "m_court_n", "run"],
	["m_court_w", "m_west_n", "run"], ["m_west_n", "m_court_w", "run"],
	["m_west_n", "m_hammock_foot", "run"], ["m_hammock_foot", "m_west_n", "run"],
	["m_hammock_foot", "m_nook_a", "run"], ["m_nook_a", "m_hammock_foot", "run"],
	["m_west_n", "m_nook_b", "run"], ["m_nook_b", "m_west_n", "run"],
	["m_nook_a", "m_court_n", "run"], ["m_court_n", "m_nook_b", "run"],
	["m_court_e", "m_banana", "run"], ["m_banana", "m_court_e", "run"],
	["m_et_foot", "m_banana", "run"], ["m_banana", "m_et_foot", "run"],
	["m_court_s", "m_banana", "run"], ["m_banana", "m_court_s", "run"],
	["m_court_e", "m_tyre", "hop"], ["m_tyre", "m_court_e", "hop"],
	["m_wt_foot", "m_west_tower", "climb"], ["m_west_tower", "m_wt_foot", "descend"],
	["m_et_foot", "m_east_tower", "climb"], ["m_east_tower", "m_et_foot", "descend"],
	["m_west_n", "m_west_perch", "climb"], ["m_west_perch", "m_west_n", "descend"],
	["m_west_tower", "m_west_perch", "balance"], ["m_west_perch", "m_west_tower", "balance"],
	["m_west_tower", "m_ring_s", "leap"],
	["m_ring_s", "m_ring_n", "rings"], ["m_ring_n", "m_ring_s", "rings"],
	["m_ring_n", "m_west_n", "drop"],
	["m_ring_s", "m_wt_foot", "drop"],
	["m_east_tower", "m_vine", "leap"],
	["m_vine", "m_rock_a", "vine"],
	["m_rock_a", "m_rock_b", "hop"], ["m_rock_b", "m_rock_c", "hop"], ["m_rock_c", "m_rocks", "hop"],
	["m_rocks", "m_rock_c", "hop"], ["m_rock_c", "m_rock_b", "hop"], ["m_rock_b", "m_rock_a", "hop"],
	["m_rock_a", "m_east_tower", "leap"],
	["m_court_n", "m_spire_1", "climb"], ["m_spire_1", "m_spire_2", "climb"], ["m_spire_2", "m_spire_3", "climb"],
	["m_spire_3", "m_court_n", "descend"], ["m_spire_1", "m_court_n", "hop"],
	["m_hammock_foot", "m_hammock", "hop"], ["m_hammock", "m_hammock_foot", "hop"],
]

## The two lions of Lion Hill and the five monkeys of Monkey Hill, and where they start.
const RESIDENTS := {
	"rory": {"species": "lion", "home": "lion_sun_rock", "name": "Rory"},
	"honey": {"species": "lioness", "home": "lion_shade", "name": "Honey"},
	"mango": {"species": "monkey", "home": "m_west_tower", "name": "Mango", "variant": 0},
	"coco": {"species": "monkey", "home": "m_court_e", "name": "Coco", "variant": 1},
	"peanut": {"species": "monkey", "home": "m_east_tower", "name": "Peanut", "variant": 2},
	"momo": {"species": "monkey", "home": "m_hammock", "name": "Momo", "variant": 3},
	"bibi": {"species": "monkey", "home": "m_court_w", "name": "Bibi", "variant": 4, "young": true},
	"tango": {"species": "tiger", "home": "tiger_slab", "name": "Tango"},
	"topper": {"species": "giraffe", "home": "giraffe_acacia_a", "name": "Topper"},
	"zig": {"species": "zebra", "home": "zebra_graze_a", "name": "Zig", "variant": 0},
	"zag": {"species": "zebra", "home": "zebra_graze_b", "name": "Zag", "variant": 1},
	"bubbles": {"species": "hippo", "home": "hippo_float", "name": "Bubbles"},
	"skip": {"species": "otter", "home": "otter_float_a", "name": "Skip", "variant": 0},
	"ripple": {"species": "otter", "home": "otter_float_b", "name": "Ripple", "variant": 1},
	# zoo r2 (appended: the network order only grows)
	"bao": {"species": "panda", "home": "panda_bamboo", "name": "Bao"},
	"mabel": {"species": "elephant", "home": "elephant_dust", "name": "Mabel"},
	"pebble": {"species": "penguin", "home": "penguin_shore_a", "name": "Pebble", "variant": 0},
	"flip": {"species": "penguin", "home": "penguin_shore_b", "name": "Flip", "variant": 1},
}
## A stable order of residents (network order). r1: seven species, fourteen animals (section 6.3);
## r2 appends Bao, Mabel, Pebble and Flip (protocol 15).
const ORDER := ["rory", "honey", "mango", "coco", "peanut", "momo", "bibi", "tango", "topper", "zig", "zag", "bubbles", "skip", "ripple",
	"bao", "mabel", "pebble", "flip"]


static func area(name: String) -> Dictionary:
	return AREAS.get(name, {})


static func areas_of(hill: String) -> Array:
	var out: Array = []
	for k in AREAS:
		if AREAS[k]["hill"] == hill:
			out.append(k)
	return out


## The height of the surface at a ground point: the highest raised area under it, else 0.
static func surface_height(p: Vector2) -> float:
	var h := 0.0
	for k in AREAS:
		var a: Dictionary = AREAS[k]
		if a["kind"] in ["terrace", "backdrop"] and (a["rect"] as Rect2).has_point(p):
			h = maxf(h, a["height"])
	return h


## Where a child may not walk: rock, structures, backdrops, plantings under routes, the edge,
## and the tram at the station.
static func blocked_for_child(p: Vector2) -> bool:
	if absf(p.x) > HALF.x - 0.3 or absf(p.y) > HALF.y - 0.3:
		return true
	if p.distance_to(STATION) < 1.3:
		return true
	for k in AREAS:
		var a: Dictionary = AREAS[k]
		if a["kind"] in ["terrace", "backdrop", "planting", "water", "thicket"] and (a["rect"] as Rect2).grow(0.25).has_point(p):
			return true
	for s in SOLIDS:
		if p.distance_to(s["at"]) < s["r"] + 0.28:
			return true
	return false


## The walkable areas of a hill a child can stand on (paths and bays), for the view tests.
static func child_stands(hill: String) -> Array:
	var out: Array = []
	for k in areas_of(hill):
		if AREAS[k]["kind"] in ["path", "bay"]:
			out.append(k)
	return out


## The habitat a point lies in, or "".
static func habitat_at(p: Vector2) -> String:
	for h in HABITATS:
		if (HABITATS[h] as Rect2).has_point(p):
			return h
	return ""


## Routes leaving an anchor.
static func links_from(anchor: String) -> Array:
	var out: Array = []
	for l in LINKS:
		if l[0] == anchor:
			out.append(l)
	return out


static func anchor_pos(anchor: String) -> Vector3:
	return ANCHORS[anchor]["pos"]
