## The places registry (design/zoo-and-world-journeys.md sections 12.1 and 22).
##
## The one place that knows which spaces are separate maps. A space is:
##   a map        "town" or "zoo": outdoors, its own ground, reached by a journey (the town is home)
##   a room       "<cottage id>:<floor>:<room>", inside a cottage, which belongs to the town
## Code that means "outdoors" asks is_map(); code that means "this map's ground and limits" asks
## half() and friends. The literal "town" stays only where the town itself is meant.
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const TvMode := preload("res://scripts/core/tv_mode.gd")

const TOWN := "town"
const ZOO := "zoo"
const CITY := "city"   # city r1: the miniature city district (design/city-district.md)
## city-web: the same city (CityMap, rules, navigation, interactions), drawn by a Three.js page
## (design/city-threejs.md section 6). A separate map with its own shared state (the CityWeb autoload).
const CITY_WEB := "city_web"
## thousand-town: Thousand Town, a separate destination adapted from upstream's "Thousand Town"
## (design/thousand-town.md section 3). Its shared clock is the Thousand autoload (net/thousand.gd).
const THOUSAND := "thousand"
## Every map, in the order a stop's board would list them.
const MAPS := [TOWN, ZOO, CITY, CITY_WEB, THOUSAND]
## Where a journey can go from each map. The authority accepts every listed journey from any device;
## whether a device offers a map is available() (a client-side offer, not a rule).
const DESTINATIONS := {TOWN: [ZOO, CITY, CITY_WEB, THOUSAND], ZOO: [TOWN], CITY: [TOWN], CITY_WEB: [TOWN], THOUSAND: [TOWN]}
## English names (translated by the locale catalogs).
const NAMES := {TOWN: "Town", ZOO: "Zoo", CITY: "City", CITY_WEB: "City (web)", THOUSAND: "Thousand Town"}
## Thousand Town's board in metres (design section 1: x +-95, z +-129) and where the tram leaves a child: the
## station forecourt, facing +x (east, along the pedestrian street toward the canal; ry = atan2(1, 0)), with
## three more places beside the first for friends arriving together.
## TODO(lead): take HALF, the arrival point and its facing from core/thousand_map.gd (W-DATA) once it exists;
## these are placeholders from the design numbers (station lot 12 at x -66, z 20).
const THOUSAND_HALF := Vector2(95.0, 129.0)
## The station forecourt's corner; must match ThousandWorld.arrival(slot) (ThousandMap.ARRIVAL_POS + ARRIVAL_SLOTS).
const THOUSAND_ARRIVALS := [Vector2(-52.0, 3.6), Vector2(-53.4, 3.6), Vector2(-52.0, 5.0), Vector2(-53.4, 5.0)]
const THOUSAND_ARRIVAL_RY := PI / 2.0
## Environment switch that offers the web city on a desktop (as the user argument --web-city does).
const WEB_CITY_ENV := "LANTERN_WEB_CITY"   # read with OS.get_environment


static func is_map(space: String) -> bool:
	return space in MAPS


## A city map: the Godot-drawn city or the web-drawn one (the same CityMap, rules and navigation).
static func is_city(space: String) -> bool:
	return space == CITY or space == CITY_WEB


## Whether this device offers a journey to `map`. Every map (Thousand Town too, the TV included) is offered
## everywhere except the web city: on
## iOS only where the WebView plugin is present; on a desktop (macOS, Linux, Windows) only with the user
## argument --web-city or the environment LANTERN_WEB_CITY=1; never on a TV (tvOS has no web view).
static func available(map: String) -> bool:
	if map != CITY_WEB:
		return is_map(map)
	if TvMode.active() or OS.has_feature("tvos"):
		return false
	if OS.has_feature("ios"):
		return Engine.has_singleton("WebView")
	var desktop := OS.has_feature("macos") or OS.has_feature("linuxbsd") or OS.has_feature("windows")
	if desktop and not OS.has_feature("mobile"):
		return OS.get_cmdline_user_args().has("--web-city") or OS.get_environment(WEB_CITY_ENV) == "1"
	return false


## The journeys this device offers from `map`, in board order.
static func offered(map: String) -> Array:
	return (DESTINATIONS.get(map, []) as Array).filter(func(m): return available(m))


## Whether things can be placed, moved and painted in a space: the town, the zoo and cottage rooms. The cities
## are visited, not decorated (dest-fix r1, from the user's feedback on the installed r3: "Ride to the city is
## for strolling with my own character"): there the HUD shows no Decorate, the controller never enters decorate
## mode and the catalog offers nothing. The authority already refuses placing there (TownModel.is_space).
static func decoratable(space: String) -> bool:
	return space == TOWN or space == ZOO or is_room(space)


## unified r6 (Apple TV feedback): the main world's own actions are offered only on the maps where they work. Pets
## (adopting, the Pet room), Story (story cards, the town's story board), Hello (friend echoes: the model keeps them
## only in the town, the zoo and rooms, TownModel.is_space) and the lantern scrapbook (the town's lantern spots and
## the zoo's stickers) belong to the main world; Thousand Town is visited and its HUD shows its own actions there
## (time, Look, the shows, Ride home, the action button) besides the ones every map has (Activities, Dress up, the
## emotes, photo, sound, language, leave, the camera). Decorate is decoratable(). Hidden actions take no focus or input.
const MAIN_WORLD_ACTIONS := ["pets", "story", "hello", "scrapbook"]


static func offers(space: String, action: String) -> bool:
	if action == "decorate":
		return decoratable(space)
	if action in MAIN_WORLD_ACTIONS:
		return space != THOUSAND
	return true


static func is_room(space: String) -> bool:
	return not TownModel.parse_room(space).is_empty()


## The map a space belongs to: a cottage room belongs to the town; "" for nothing known.
static func map_of(space: String) -> String:
	if is_map(space):
		return space
	if is_room(space):
		return TOWN
	return ""


## The walkable half extents of a space.
static func half(space: String) -> Vector2:
	if space == ZOO:
		return ZooMap.HALF
	if is_city(space):
		return CityMap.HALF
	if space == THOUSAND:
		return THOUSAND_HALF
	if space == TOWN:
		return TownModel.TOWN_HALF
	return TownModel.ROOM_HALF


## Where a traveller arrives on a map (the zoo: one of four places on the station platform).
static func arrival(map: String, slot := 0) -> Vector2:
	if map == ZOO:
		return ZooMap.ARRIVALS[posmod(slot, ZooMap.ARRIVALS.size())]
	if is_city(map):
		return CityMap.ARRIVALS[posmod(slot, CityMap.ARRIVALS.size())]
	if map == THOUSAND:
		return THOUSAND_ARRIVALS[posmod(slot, THOUSAND_ARRIVALS.size())]
	return TownModel.TOWN_SPAWN


## Whether things can be placed here from the toy box: everywhere but the city (the zoo has its own toy
## box with the Zoo and Picnic tabs, design 10.4; the city district is a place to visit, city r1; so is the
## web city, and so is Thousand Town).
static func can_decorate(space: String) -> bool:
	return not is_city(space) and space != THOUSAND


## The music context of a space: "town" outdoors on any map, "home" inside a cottage.
static func music(space: String) -> String:
	return "town" if is_map(space) else "home"
