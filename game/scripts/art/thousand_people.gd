## Thousand Town's residents in the street (design/thousand-town.md, sections 1, 5 and 8).
##
## Who is drawn: every resident whose plan (core/thousand_sim.gd) puts them outdoors at the current minute.
##   - On a COMMUTE segment ("on the street"): that resident, routed door to door along walkable ground, from the
##     place of the segment before to the place of the segment after. A "walk" that starts and ends at the same
##     building is an outing (out toward a park, the plaza or the river walk and back). A "ride" walks to the bus
##     stop nearest its start, waits, is aboard (not drawn) and walks home from the stop nearest its end, when both
##     stops are close; otherwise it is walked.
##   - At an outdoor venue (Data.OUTDOOR_KINDS: the parks, the plaza, the amusement park, the station, the night
##     market) or at a street-food spot: standing at a spot of that venue doing what the substate says (tai chi,
##     square dance, board games, eating at the stalls, minding a stall), or strolling or jogging its walking loop.
##   - Inside a building: not drawn. Counted (counts()) for occupancy, as the sim says.
## Timing is a pure function of (day, minute): a trip longer than the pace allows joins its route partway and fades
## in over FADE minutes (design section 5); a short one waits at its start door and lingers at its end door. One sim
## minute is one second at 1x (thousand_clock.gd), so the pace in metres per second is also metres per minute.
##
## Walkable ground (class Ground): a 0.5 m raster of the board from town.json and solids.json. Blocked: the canal
## and its walls (except the footbridges), the roadways (except the zebras, the pedestrian part of the z = 0 street
## and the tunnel covers), the viaduct decks, the facility yards, and every solid footprint grown by 0.25 m. Routes
## are A* on a 1 m grid whose cells are wholly walkable at 0.5 m, string-pulled with 0.5 m line-of-sight checks, and
## cached per pair of route nodes (doors, venue hubs, stops, outing targets) for the whole session.
##
## Drawing: two MultiMeshes (two draw calls) of a part figure in the city_people style (core shapes from
## art/city_people.gd: the head, the six hair styles, the skirt; bevelled boxes and limbs), animated on the GPU: a
## vertex shader poses the bones (walk, jog, tai chi, dance, talk, eat, work, wait, stand) from the instance's custom
## data, and the looks of all 1000 residents (eight texels each: skin, top, bottom, shoes, hair, accent, skirt and
## the flags) live in one small texture built once. "near" is the full figure within near_m (at most max_near),
## "far" a blocky one out to far_m; beyond far_m nobody is drawn; at most max_figures in all, nearest first.
## Heights: the rig is 1.80 m at scale 1; adults are 0.94 (about 1.70 m), women x 0.97, and under 18 the stature
## follows upstream's curve (resident-character-kit.js HEIGHT), with its head curve.
##
## The lead's API (all positions in metres, town space; resident ids are the sim's indices 0..999):
##   setup(sim, map_or_null = null, world_or_null = null)   build the ground, venues, meshes (map defaults to
##                                                           thousand_map.gd; world may offer walk_route(a, b))
##   set_plans(plans)            share the lead's Sim.DayPlans (otherwise built here when the day changes)
##   set_time(day, minute)       place and draw everybody for that moment (call once a frame)
##   warm(day, minute)           the same, searching every route now (behind the arrival's loading)
##   focus(pos)                  the LOD centre, normally the player's child
##   set_budget(max_figures, max_near, near_m, far_m), budget_profile("ipad" | "tv")
##   pick(ray_origin, ray_dir) -> int, pick_screen(camera, screen_pos) -> int, nearest(pos, radius) -> int
##   position_of(id) -> Vector3  (the door when inside; Vector3.INF if unknown)
##   info(id, locale) -> Dictionary  (name, role, age, state, substate, where, from, to, destination, progress,
##                                    remaining_m, eta_minute, mode, drawn)
##   route_of(id) -> PackedVector3Array   the current trip, for "follow this resident's commute"
##   counts() -> Dictionary, stats() -> Dictionary, drawn_ids() -> PackedInt32Array, draw_calls() -> int
extends Node3D

const Sim := preload("res://scripts/core/thousand_sim.gd")
const Data := preload("res://scripts/core/thousand_sim_data.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const TMap := preload("res://scripts/core/thousand_map.gd")
const Places := preload("res://scripts/core/places.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")
const CityPeople := preload("res://scripts/art/city_people.gd")

const SOLIDS_PATH := "res://thousand_town/data/solids.json"

# ------------------------------------------------------------------ scale (design section 1)

## The rig's height at scale 1 (city_people: about 1.8 m to the top of the head).
const RIG_HEIGHT := 1.80
const ADULT_SCALE := 0.94
const FEMALE_STATURE := 0.97
## Upstream's stature and head-size curves by age (resident-character-kit.js HEIGHT, HEAD).
const HEIGHT_CURVE := [[1, 0.40], [2, 0.44], [3, 0.47], [4, 0.51], [5, 0.55], [6, 0.58], [7, 0.61], [8, 0.64], [9, 0.67],
	[10, 0.70], [11, 0.73], [12, 0.76], [13, 0.80], [14, 0.85], [15, 0.89], [16, 0.92], [17, 0.95], [18, 1.0], [30, 1.0],
	[45, 1.0], [55, 1.0], [60, 0.99], [65, 0.98], [70, 0.97], [75, 0.96], [80, 0.95], [85, 0.94], [90, 0.93]]
const HEAD_CURVE := [[1, 1.46], [3, 1.36], [5, 1.26], [7, 1.20], [9, 1.15], [12, 1.10], [15, 1.05], [18, 1.0], [60, 1.0], [90, 0.98]]
## One walk cycle per this many metres for an adult; children take shorter strides.
const STRIDE := 1.4
## Minutes over which a figure fades in when it joins its route partway, and out as it goes in.
const FADE := 0.8
const BODY_R := 0.32
## Nobody stands within this of a child's arrival slot on the station forecourt (Places.THOUSAND_ARRIVALS): a figure
## standing there overlapped the arriving child and took every tap on the street ahead (the loop tour).
const ARRIVAL_CLEAR := 1.6

# ------------------------------------------------------------------ budgets (design section 8)

var max_figures := 160
var max_near := 40
var near_m := 32.0
var far_m := 110.0
## Route searches allowed per frame (milliseconds); a trip waits for its route otherwise. sync_routes: no limit.
var route_budget_ms := 3.0
var sync_routes := false

enum { MODE_STAND, MODE_WALK, MODE_JOG, MODE_TAICHI, MODE_DANCE, MODE_TALK, MODE_EAT, MODE_WORK, MODE_WAIT }
const MODE_NAMES := ["stand", "walk", "jog", "tai-chi", "dance", "talk", "eat", "work", "wait"]
## The period in minutes of each still mode's animation cycle (walking modes run on distance).
const MODE_PERIOD := [6.0, 1.0, 1.0, 8.0, 1.6, 3.0, 5.0, 1.4, 7.0]
enum { ACT_NONE, ACT_TRIP, ACT_VENUE }

## The sim's ledger buildings drawn on the map: building ids (town.json), annexes, the street office, or a venue.
const SIM_TO_MAP := {
	"h-courtyard": "b-8-0", "h-slab": "b-10-0", "h-terrace": "b-13-0", "h-point": "b-15-0", "c-hospital": "b-7-0",
	"c-primary": "b-0-0", "c-secondary": "b-17-0", "c-university": "b-20-0", "c-library": "b-22-0", "i-workshop": "b-1-0",
	"i-depot": "b-2-0", "i-market": "b-21-0", "i-clinic-a": "annex", "i-clinic-b": "annex", "i-clinic-c": "annex",
	"c-precinct": "annex", "i-waste": "annex", "c-mall": "b-14-0", "c-annex-mall": "b-23-0", "c-night-market": "venue",
	"c-civic": "office", "c-station": "venue", "c-amusement": "venue", "c-plaza": "venue", "c-park-a": "venue",
	"c-park-b": "venue", "t-one": "b-3-0", "t-two": "b-5-0", "t-three": "b-6-0", "t-four": "b-9-0", "c-bank": "annex",
}
const VENUE_OF := {"c-night-market": "market", "c-station": "station", "c-amusement": "amusement", "c-plaza": "plaza",
	"c-park-a": "park-0", "c-park-b": "park-1"}
## Strolling loops per venue (town.json walking_routes).
const VENUE_LOOPS := {"park-0": ["walk-1"], "park-1": ["walk-2"], "amusement": ["walk-4"], "plaza": ["walk-7"],
	"market": ["walk-5", "walk-6"]}
## Where an outing from home may turn back: river-walk and footbridge points (the venue hubs are added).
const OUTING_POINTS := [Vector2(-10.7, -60.0), Vector2(-10.7, 60.0), Vector2(10.7, -60.0), Vector2(10.7, 60.0),
	Vector2(-10.0, -20.0), Vector2(10.0, 20.0), Vector2(-30.0, 0.0), Vector2(30.0, 0.0)]
## A ride uses buses only when both ends are this close to a stop (metres, straight line).
const RIDE_STOP_M := 70.0
const RIDE_SPEED := 5.0

# ------------------------------------------------------------------ looks

const SKIN := [Color("#e8c3a4"), Color("#dcae8c"), Color("#c99977"), Color("#bd8a63"), Color("#ab7750")]
enum { HAIR_NONE, HAIR_SHORT, HAIR_LONG, HAIR_BUN, HAIR_PONY, HAIR_CURLY, HAIR_CAP }
## Look flags (the eight bits of the params texel's green channel; mesh features 10 + bit).
enum { F_DRESS, F_APRON, F_BAG, F_COAT, F_VEST, F_GLASSES, F_TIE, F_PACK }
## Second flags (alpha): female, short sleeves, shorts.
enum { G_FEMALE, G_SHORT_SLEEVES, G_SHORTS }
## Per role: tops, bottoms, shoes, accents (apron, bag, vest...), the chance of each flag, caps (colour list and
## chance), short sleeves and shorts. Lantern Lane's own looks after upstream's role descriptions.
const ROLE_LOOKS := {
	"preschooler": {"top": ["#f2a765", "#f0c46a", "#e9a9b4", "#9fd3c7", "#a8c8f0", "#f4e1a1"], "bottom": ["=top"],
		"shoes": ["#f4efe3", "#e9a9b4", "#a8c8f0"], "accent": ["#ffffff"], "short": 1.0, "shorts": 1.0, "dress": 0.3},
	"student-p": {"top": ["#f2f1ea", "#e4e8ee", "#f0d5da", "#d6e3e1", "#e9e7de"], "bottom": ["#2f3d5c", "#3b4a6b"],
		"shoes": ["#f4f2ea", "#3a3f47"], "accent": ["#d8423a", "#3c7bd1", "#f2b632"], "pack": 0.9, "short": 0.7,
		"shorts": 0.6, "dress": 0.35},
	"student-m": {"top": ["#26324a", "#34383d", "#23413a"], "bottom": ["=top"], "shoes": ["#f4f2ea"],
		"accent": ["#7a2f34", "#3a3f47", "#5a6068"], "pack": 0.8, "dress": 0.2},
	"student-u": {"top": ["#5a6068", "#3d4348", "#7a8f6a", "#a35d4f", "#c7a76b", "#4f6d8f"], "bottom": ["#3b4c6b", "#2c2f33", "#5a6068"],
		"shoes": ["#efece2", "#2c2f33", "#b9b3a2"], "accent": ["#2c2f33", "#8a5f2e"], "pack": 0.55, "bag": 0.2, "short": 0.4,
		"glasses": 0.25},
	"office": {"top": ["#f4f1e8", "#dfe6ee", "#e7dde8", "#e2e8dd", "#eee6dc"], "bottom": ["#2b2f38", "#3a3f4a", "#4a4f5c"],
		"shoes": ["#2a2624", "#3a302a"], "accent": ["#7a2f34", "#2c3752", "#3d5a4a"], "tie": 0.5, "bag": 0.35, "dress": 0.3,
		"glasses": 0.3},
	"worker": {"top": ["#3b4f7a", "#435a86", "#38476a"], "bottom": ["#8a8f96", "#7c8188"], "shoes": ["#6b4a2e", "#3a302a"],
		"accent": ["#d26c1c", "#e3b62c"], "cap": ["#d26c1c", "#e3b62c", "#2c3752"], "cap_p": 0.4},
	"shopkeeper": {"top": ["#e7e2d4", "#e6e0cf", "#dcd5c2"], "bottom": ["#33383a", "#4a4440"], "shoes": ["#2a2624"],
		"accent": ["#b4432c", "#2f6f5e", "#d5a65b", "#8393ad", "#33383a"], "apron": 1.0, "short": 0.5},
	"driver": {"top": ["#7d8b9c", "#8a2f2a", "#a97b3c", "#5d6b7c"], "bottom": ["#2b2f38", "#3a3f4a"], "shoes": ["#2a2624"],
		"accent": ["#cfc8b6"], "cap": ["#2c3752", "#1f2740"], "cap_p": 0.6},
	"teacher": {"top": ["#f3efe6", "#c9a27e", "#9bb0c9", "#b98b9e", "#e9edf1"], "bottom": ["#5a5f6b", "#6b5a4a", "#3a3f4a"],
		"shoes": ["#3a302a", "#2a2624"], "accent": ["#b48b74", "#3c7bd1"], "dress": 0.4, "glasses": 0.4, "bag": 0.3},
	"school-admin": {"top": ["#696279", "#687067", "#b89866"], "bottom": ["#3a3f4a", "#4a4440"], "shoes": ["#2a2624"],
		"accent": ["#f2ecdd"], "glasses": 0.5, "dress": 0.3},
	"medical-doc": {"top": ["#f2f4f2"], "bottom": ["#4a5568", "#5b6b5e", "#3a3f4a"], "shoes": ["#2a2624", "#e2ded2"],
		"accent": ["#f2f4f2"], "coat": 1.0, "glasses": 0.3},
	"medical-nurse": {"top": ["#7fb6c9", "#8fc7a8", "#c9a3c7", "#9fb7d9"], "bottom": ["#eef1ef"], "shoes": ["#f5f7f5"],
		"accent": ["#ffffff"], "cap": ["#f5f7f5"], "cap_p": 0.5, "short": 1.0},
	"hosp-admin": {"top": ["#e4e8ef", "#dceee3", "#f3f0e6"], "bottom": ["#3a3f4a", "#4a5568"], "shoes": ["#2a2624"],
		"accent": ["#7d8b9c"], "dress": 0.3, "short": 0.6},
	"officer": {"top": ["#2c3752", "#1f2740"], "bottom": ["#232b30"], "shoes": ["#1a1a1a"], "accent": ["#bcc75e"],
		"vest": 0.5, "cap": ["#1f2740"], "cap_p": 0.9},
	"clerk": {"top": ["#25304d", "#24453a", "#5e2433", "#4a5563"], "bottom": ["=top"], "shoes": ["#2a2624"],
		"accent": ["#f6f3ea", "#c9a27e"], "tie": 0.5, "dress": 0.4},
	"sanitation": {"top": ["#4b4f56"], "bottom": ["#4b4f56", "#5a5e66"], "shoes": ["#3a302a"], "accent": ["#d6e82c", "#f08a24"],
		"skirt": ["#c3cbd0"], "vest": 1.0, "cap": ["#d26c1c", "#4b4f56"], "cap_p": 0.5},
	"unemployed": {"top": ["#cdc7ba", "#b0aca2", "#a8a396", "#bfb6a4", "#c2bcae"], "bottom": ["#6b7280", "#5a6068", "#8a8578"],
		"shoes": ["#b9b4a6", "#5a5e66"], "accent": ["#8a8578"], "short": 0.5},
	"patient": {"top": ["#e6ece3", "#e3eaee", "#eaf0f3"], "bottom": ["=top"], "shoes": ["#d7dee3"], "accent": ["#9fb7d9"]},
	"retiree": {"top": ["#b7ab8c", "#b08f68", "#c9d2cd", "#8f7f6a", "#9c6b5a", "#dcd6c6"], "bottom": ["#6b6458", "#565a5e", "#7a7468"],
		"shoes": ["#3a302a", "#5a4a3a"], "accent": ["#8a6a42", "#4b4f56"], "bag": 0.3, "cap": ["#6b6458", "#4b4f56"], "cap_p": 0.2,
		"glasses": 0.35, "dress": 0.25},
	"senior": {"top": ["#8f9299", "#7a4b4b", "#6d7b6a", "#6b4f36", "#5e2f36"], "bottom": ["#3f3a36", "#4b4f56"],
		"shoes": ["#2a2624"], "accent": ["#8a6a4a"], "bag": 0.2, "glasses": 0.5, "dress": 0.3, "cap": ["#4b4f56"], "cap_p": 0.25},
}

# ------------------------------------------------------------------ the bones of the figure (shader)

enum { B_PELVIS, B_TORSO, B_HEAD, B_UARM_L, B_UARM_R, B_FARM_L, B_FARM_R, B_THIGH_L, B_THIGH_R, B_SHIN_L, B_SHIN_R }
## Colour slots: 0 skin, 1 top, 2 bottom, 3 shoes, 4 hair, 5 accent, 6 skirt; resolved in the shader: 8 forearm
## (skin with short sleeves), 9 shin (skin with shorts or a dress), 10 thigh (skin under a dress). Texel 7: params.
const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D looks : filter_nearest, repeat_disable;

varying vec3 v_albedo;
varying float v_fade;

const float HIP = 0.86;
const float THIGH = 0.40;
const float SHIN = 0.38;
const float SHOE_H = 0.08;
const vec3 WAIST = vec3(0.0, 0.86, 0.0);
const vec3 NECK = vec3(0.0, 1.44, 0.0);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Rotations about an axis through a pivot, applied to a point and its normal.
void rot_x(inout vec3 p, inout vec3 n, vec3 piv, float a) {
	float c = cos(a);
	float s = sin(a);
	vec3 d = p - piv;
	p = piv + vec3(d.x, d.y * c - d.z * s, d.y * s + d.z * c);
	n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
}
void rot_y(inout vec3 p, inout vec3 n, vec3 piv, float a) {
	float c = cos(a);
	float s = sin(a);
	vec3 d = p - piv;
	p = piv + vec3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c);
	n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
}
void rot_z(inout vec3 p, inout vec3 n, vec3 piv, float a) {
	float c = cos(a);
	float s = sin(a);
	vec3 d = p - piv;
	p = piv + vec3(d.x * c - d.y * s, d.x * s + d.y * c, d.z);
	n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
}
// A limb hanging below its pivot swings toward +z (forward) for a > 0.
void fwd(inout vec3 p, inout vec3 n, vec3 piv, float a) {
	rot_x(p, n, piv, -a);
}

float ankle(float th, float kn) {
	return HIP - THIGH * cos(th) - SHIN * cos(th - kn);
}

void vertex() {
	int rid = int(INSTANCE_CUSTOM.x + 0.5);
	float t = 6.2831853 * INSTANCE_CUSTOM.y;
	int mode = int(INSTANCE_CUSTOM.z + 0.5);
	v_fade = INSTANCE_CUSTOM.w;
	vec4 par = texelFetch(looks, ivec2(7, rid), 0);
	int hair = int(par.r * 255.0 + 0.5);
	int flags = int(par.g * 255.0 + 0.5);
	float head_s = 0.9 + par.b * 0.6;
	int flags2 = int(par.a * 255.0 + 0.5);
	int slot = int(UV.x + 0.5);
	int bone = int(UV.y + 0.5);
	int feat = int(UV2.x + 0.5);
	bool show = true;
	if (feat >= 1 && feat <= 6) {
		show = feat == hair;
	} else if (feat >= 10) {
		show = ((flags >> (feat - 10)) & 1) == 1;
	}
	bool dress = (flags & 1) == 1;
	int s = slot;
	if (slot == 8) {
		s = (flags2 & 2) == 2 ? 0 : 1;
	} else if (slot == 9) {
		s = ((flags2 & 4) == 4 || dress) ? 0 : 2;
	} else if (slot == 10) {
		s = dress ? 0 : 2;
	}
	// the vertex's shade (face details, glasses) is packed in UV2.y as 4-bit r, g, b: the Compatibility renderer
	// does not hand a MultiMesh without instance colours its vertex colours
	int pk = int(UV2.y + 0.5);
	vec3 shade = vec3(float((pk >> 8) & 15), float((pk >> 4) & 15), float(pk & 15)) / 15.0;
	v_albedo = to_linear(texelFetch(looks, ivec2(s, rid), 0).rgb * shade);

	// the pose of this instance's mode at its phase
	float sw = sin(t);
	vec2 th = vec2(0.0);
	vec2 kn = vec2(0.03);
	vec2 ar = vec2(0.05);
	vec2 el = vec2(0.18);
	vec2 ro = vec2(0.07);
	float lean = 0.0;
	float twist = 0.0;
	float yaw = 0.0;
	float hy = 0.0;
	float hp = 0.04;
	if (mode == 1 || mode == 2) {
		bool jog = mode == 2;
		float amp = jog ? 0.62 : 0.47;
		float cw = cos(t);
		float lift = jog ? 1.25 : 0.8;
		th = vec2(amp * sw, -amp * sw);
		kn = vec2(0.08 + lift * pow(max(0.0, cw), 1.5), 0.08 + lift * pow(max(0.0, -cw), 1.5));
		float a0 = -(jog ? 0.55 : 0.42) * sw;
		ar = vec2(a0, -a0);
		el = vec2(0.25 + 0.3 * max(0.0, a0), 0.25 + 0.3 * max(0.0, -a0)) + (jog ? 1.05 : 0.0);
		twist = 0.07 * sw;
		yaw = -0.05 * sw;
		lean = jog ? 0.16 : 0.05;
		hy = -0.07 * sw;
	} else if (mode == 3) {
		float u = 0.5 - 0.5 * cos(t);
		ar = vec2(0.35 + 1.0 * u);
		el = vec2(0.55 - 0.3 * u);
		ro = vec2(0.12 + 0.25 * (0.5 + 0.5 * sin(t * 0.5)));
		th = vec2(0.14);
		kn = vec2(0.3);
		yaw = 0.35 * sin(t * 0.5);
		hp = 0.0;
	} else if (mode == 4) {
		ar = vec2(2.3 + 0.35 * sw, 2.3 - 0.35 * sw);
		el = vec2(0.5);
		ro = vec2(0.3);
		float b = abs(sw);
		th = vec2(0.06 + 0.06 * b);
		kn = vec2(0.12 + 0.16 * b);
		yaw = 0.45 * sin(t * 0.5);
		twist = 0.12 * sw;
	} else if (mode == 5) {
		ar = vec2(0.06, 0.35 + 0.28 * max(0.0, sin(t)));
		el = vec2(0.2, 1.1 + 0.35 * sin(t * 2.0));
		hy = 0.28 * sin(t * 0.333);
		hp = 0.04 + 0.06 * sin(t * 2.0);
	} else if (mode == 6) {
		float u = smoothstep(0.55, 0.75, fract(t / 6.2831853)) * (1.0 - smoothstep(0.85, 1.0, fract(t / 6.2831853)));
		ar = vec2(0.3, 0.45 + 0.35 * u);
		el = vec2(1.35, 1.25 + 1.0 * u);
		hp = 0.12 - 0.08 * u;
	} else if (mode == 7) {
		ar = vec2(0.72 + 0.12 * sw, 0.72 - 0.12 * sw);
		el = vec2(0.75);
		lean = 0.12;
		hp = 0.2;
	} else if (mode == 8) {
		float look = smoothstep(0.0, 0.1, fract(t / 6.2831853)) * (1.0 - smoothstep(0.6, 0.7, fract(t / 6.2831853)));
		ar = vec2(0.05, 0.05 + 0.32 * look);
		el = vec2(0.18, 0.18 + 1.7 * look);
		hp = 0.04 + 0.3 * look;
		hy = 0.35 * sin(t * 0.5) * (1.0 - look);
	} else {
		hy = 0.3 * sin(t * 0.37);
		ar = vec2(0.05 + 0.02 * sin(t * 0.5));
	}
	// breathing, and the lower foot planted on the floor
	float bob = SHOE_H - min(ankle(th.x, kn.x), ankle(th.y, kn.y)) + 0.006 * sin(t * 0.25);

	vec3 p = VERTEX;
	vec3 n = NORMAL;
	if (!show) {
		p = vec3(0.0, 1.0, 0.0);
	}
	bool female = (flags2 & 1) == 1;
	if (female && (bone == 0 || bone == 1)) {
		p.x *= 0.92;
	}
	if (female && bone >= 3 && bone <= 6) {
		p.x -= sign(p.x) * 0.018;
	}
	if (bone == 2) {
		p = NECK + (p - NECK) * head_s;
		rot_x(p, n, NECK, hp);
		rot_y(p, n, NECK, hy);
	}
	if (bone >= 3 && bone <= 6) {
		int side = (bone == 3 || bone == 5) ? 0 : 1;
		float sg = side == 0 ? -1.0 : 1.0;
		vec3 sh = vec3(sg * (female ? 0.237 : 0.255), 1.37, 0.0);
		if (bone >= 5) {
			fwd(p, n, vec3(sh.x, 1.07, 0.0), side == 0 ? el.x : el.y);
		}
		fwd(p, n, sh, side == 0 ? ar.x : ar.y);
		rot_z(p, n, sh, sg * (side == 0 ? ro.x : ro.y));
	}
	if (bone >= 7) {
		int side = (bone == 7 || bone == 9) ? 0 : 1;
		float sg = side == 0 ? -1.0 : 1.0;
		if (bone >= 9) {
			fwd(p, n, vec3(sg * 0.09, 0.46, 0.0), -(side == 0 ? kn.x : kn.y));
		}
		fwd(p, n, vec3(sg * 0.09, HIP, 0.0), side == 0 ? th.x : th.y);
	}
	if (bone >= 1 && bone <= 6) {
		rot_x(p, n, WAIST, lean);
		rot_y(p, n, WAIST, twist);
	}
	rot_y(p, n, vec3(0.0), yaw);
	p.y += bob;
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	if (v_fade < 0.999) {
		int bx = int(FRAGCOORD.x) % 4;
		int by = int(FRAGCOORD.y) % 4;
		if (v_fade * 16.0 <= BAYER[by * 4 + bx] + 0.5) {
			discard;
		}
	}
	ALBEDO = v_albedo;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
"""


# ================================================================== walkable ground

## The walkable raster, its heights, and routes between points (A* on a coarser grid, string-pulled).
class Ground:
	const CELL := 0.5
	const X0 := -95.0
	const Z0 := -129.0
	const INFLATE := 0.2            # metres of clearance beyond the cells a solid touches
	const COARSE := 2               # fine cells per A* cell
	var w := 380
	var h := 516
	var cw := 190
	var ch := 258
	var free := PackedByteArray()
	var yv := PackedFloat32Array()
	var astar := AStarGrid2D.new()      # 1 m cells with any walkable 0.5 m cell (optimistic)
	var astar_f := AStarGrid2D.new()    # the 0.5 m cells, for the stretches the coarse path cannot see along
	var footbridges: Array = []     # [Rect2 (walkable), Dictionary bridge (metres)]
	var build_ms := 0.0
	var routes := {}                # Vector2i(a, b) node pair -> PackedVector2Array (a < b)
	var route_ms := 0.0
	var route_count := 0

	func idx(p: Vector2) -> int:
		var cx := floori((p.x - X0) / CELL)
		var cz := floori((p.y - Z0) / CELL)
		if cx < 0 or cz < 0 or cx >= w or cz >= h:
			return -1
		return cz * w + cx

	func centre(cx: int, cz: int) -> Vector2:
		return Vector2(X0 + (cx + 0.5) * CELL, Z0 + (cz + 0.5) * CELL)

	func walkable(p: Vector2) -> bool:
		var i := idx(p)
		return i >= 0 and free[i] == 1

	## Every point of the segment, sampled every 0.2 m, on walkable cells.
	## Every cell the segment passes through is walkable (a grid traversal, Amanatides and Woo).
	func clear(a: Vector2, b: Vector2) -> bool:
		var fx := (a.x - X0) / CELL
		var fz := (a.y - Z0) / CELL
		var gx := (b.x - X0) / CELL
		var gz := (b.y - Z0) / CELL
		var cx := floori(fx)
		var cz := floori(fz)
		var ex := floori(gx)
		var ez := floori(gz)
		if cx < 0 or cz < 0 or cx >= w or cz >= h or ex < 0 or ez < 0 or ex >= w or ez >= h:
			return false
		var dx := gx - fx
		var dz := gz - fz
		var sx := 1 if dx > 0.0 else -1
		var sz := 1 if dz > 0.0 else -1
		var tdx := absf(1.0 / dx) if dx != 0.0 else INF
		var tdz := absf(1.0 / dz) if dz != 0.0 else INF
		var tmx := ((cx + 1 - fx) if dx > 0.0 else (fx - cx)) * tdx if dx != 0.0 else INF
		var tmz := ((cz + 1 - fz) if dz > 0.0 else (fz - cz)) * tdz if dz != 0.0 else INF
		var n := absi(ex - cx) + absi(ez - cz)
		if free[cz * w + cx] == 0:
			return false
		for k in n:
			if tmx < tmz:
				cx += sx
				tmx += tdx
			else:
				cz += sz
				tmz += tdz
			if free[cz * w + cx] == 0:
				return false
		return true

	## The centre of the nearest walkable cell within r metres (the point's own cell first), or Vector2.INF.
	func snap(p: Vector2, r: float = 6.0, area: int = -1) -> Vector2:
		var c0 := Vector2i(floori((p.x - X0) / CELL), floori((p.y - Z0) / CELL))
		var rings := ceili(r / CELL)
		for ring in rings + 1:
			var best := Vector2.INF
			var bd := INF
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var cx := c0.x + dx
					var cz := c0.y + dz
					if cx < 0 or cz < 0 or cx >= w or cz >= h or free[cz * w + cx] == 0:
						continue
					if area >= 0 and _area_cell(cx, cz) != area:
						continue
					var q := centre(cx, cz)
					var d := q.distance_squared_to(p)
					if d < bd:
						bd = d
						best = q
			if best != Vector2.INF:
				return best
		return Vector2.INF

	## The ground height (the pavement, paving, platforms, park lawns; the footbridges' rise exactly).
	func y_at(p: Vector2) -> float:
		for fb: Array in footbridges:
			if (fb[0] as Rect2).has_point(p):
				return bridge_y(p, fb[1])
		var i := idx(p)
		return 0.125 if i < 0 else yv[i]

	## solids.json's bridge profile (upstream units inside the formula; the numbers are metres).
	static func bridge_y(p: Vector2, b: Dictionary) -> float:
		var wx := (float(b.w) * 0.5 + 5.0 - absf(p.x - float(b.x))) / 5.0
		var wz := (float(b.d) * 0.5 + 2.0 - absf(p.y - float(b.z))) / 2.0
		return 0.5 * (0.25 + 1.7 * _sm(wx) * _sm(wz))

	static func _sm(e: float) -> float:
		var u := clampf(e, 0.0, 1.0)
		return u * u * (3.0 - 2.0 * u)

	## Blocking (v = 0) takes every cell the rect touches; opening (v = 1) only the cells wholly inside it, so a
	## walkable cell is walkable all over.
	func _fill(rect: Rect2, v: int) -> void:
		var r := rect.grow(0.249 if v == 0 else -0.249)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
		var x0 := maxi(0, ceili((r.position.x - X0) / CELL - 0.5))
		var x1 := mini(w - 1, floori((r.end.x - X0) / CELL - 0.5))
		var z0 := maxi(0, ceili((r.position.y - Z0) / CELL - 0.5))
		var z1 := mini(h - 1, floori((r.end.y - Z0) / CELL - 0.5))
		for cz in range(z0, z1 + 1):
			var row := cz * w
			for cx in range(x0, x1 + 1):
				free[row + cx] = v

	func _fill_y(r: Rect2, y: float) -> void:
		var x0 := maxi(0, ceili((r.position.x - X0) / CELL - 0.5))
		var x1 := mini(w - 1, floori((r.end.x - X0) / CELL - 0.5))
		var z0 := maxi(0, ceili((r.position.y - Z0) / CELL - 0.5))
		var z1 := mini(h - 1, floori((r.end.y - Z0) / CELL - 0.5))
		for cz in range(z0, z1 + 1):
			var row := cz * w
			for cx in range(x0, x1 + 1):
				yv[row + cx] = y

	static func _rect(d: Dictionary) -> Rect2:
		return Rect2(float(d.x) - float(d.w) * 0.5, float(d.z) - float(d.d) * 0.5, float(d.w), float(d.d))

	func build() -> void:
		var t0 := Time.get_ticks_usec()
		free.resize(w * h)
		free.fill(1)
		yv.resize(w * h)
		yv.fill(0.125)
		var town := TMap.data()
		var solids_doc := {}
		var j := JSON.new()
		if FileAccess.file_exists(SOLIDS_PATH) and j.parse(FileAccess.get_file_as_string(SOLIDS_PATH)) == OK:
			solids_doc = j.data
		# heights: park lawns, then the listed walkable surfaces
		for pl: Dictionary in TMap.places():
			if pl.kind in ["park", "sports"]:
				_fill_y(pl.rect, 0.06)
		for wk: Dictionary in solids_doc.get("walkable", []):
			if wk.has("y"):
				_fill_y(_rect(wk.rect), float(wk.y))
		# the canal and its walls
		_fill(Rect2(-8.0, Z0, 16.0, 258.0), 0)
		# the roadways (the pedestrian part of a walk-only street stays open)
		for r: Dictionary in TMap.roads():
			var rect: Rect2 = r.rect
			var only := float(r.walk_only_to)
			if only > 0.0:
				if rect.position.x < -only:
					_fill(Rect2(rect.position.x, rect.position.y, minf(rect.end.x, -only) - rect.position.x, rect.size.y), 0)
				if rect.end.x > only:
					var x0 := maxf(rect.position.x, only)
					_fill(Rect2(x0, rect.position.y, rect.end.x - x0, rect.size.y), 0)
			else:
				_fill(rect, 0)
		for v: Dictionary in town.get("viaducts", []):
			_fill(Rect2(-85.0, float(v.z) - float(v.d) * 0.5, 170.0, float(v.d)), 0)
		# tunnel covers: the river walks run over the road where it is underground
		for t: Dictionary in town.get("tunnels", []):
			var cx := float(t.cover_x)
			var hd := float(t.half_d)
			_fill(Rect2(-cx, float(t.z) - hd, cx - 8.0, hd * 2.0), 1)
			_fill(Rect2(8.0, float(t.z) - hd, cx - 8.0, hd * 2.0), 1)
		# zebras, stretched kerb to kerb along their walking axis
		for c: Dictionary in town.get("crossings", []):
			for z: Dictionary in c.zebras:
				var zr := _rect(z)
				if String(z.walk_axis) == "z":
					zr = zr.grow_individual(0.0, 1.0, 0.0, 1.0)
				else:
					zr = zr.grow_individual(1.0, 0.0, 1.0, 0.0)
				_fill(zr, 1)
		# footbridges (the road bridges' rails leave no pavement)
		for b: Dictionary in town.get("bridges", []):
			if String(b.kind) == "footbridge":
				_fill(_rect(b), 1)
		for wk: Dictionary in solids_doc.get("walkable", []):
			if String(wk.kind) == "footbridge":
				footbridges.append([_rect(wk.rect), wk.profile.bridge])
				var bz := float(wk.profile.bridge.z)
				bridge_ends.append(PackedVector2Array([Vector2(-10.25, bz), Vector2(10.25, bz)]))
			if String(wk.kind) == "facility-yard":
				_fill(_rect(wk.rect), 0)
		# every solid, grown by the body's clearance
		for s: Dictionary in solids_doc.get("solids", []):
			var r := Rect2()
			if s.has("rect"):
				r = _rect(s.rect)
			elif s.has("poly"):
				var pts: Array = s.poly
				r = Rect2(Vector2(float(pts[0][0]), float(pts[0][1])), Vector2.ZERO)
				for q in pts:
					r = r.expand(Vector2(float(q[0]), float(q[1])))
			_fill(r.grow(INFLATE), 0)
		# the board's edge
		_fill(Rect2(X0, Z0, 190.0, 0.6), 0)
		_fill(Rect2(X0, -Z0 - 0.6, 190.0, 0.6), 0)
		_fill(Rect2(X0, Z0, 0.6, 258.0), 0)
		_fill(Rect2(-X0 - 0.6, Z0, 0.6, 258.0), 0)
		# A* on 1 m cells holding any walkable 0.5 m cell, and on the 0.5 m cells themselves
		for g: AStarGrid2D in [astar, astar_f]:
			g.region = Rect2i(0, 0, cw, ch) if g == astar else Rect2i(0, 0, w, h)
			g.cell_size = Vector2(1, 1)
			g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
			g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
			g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
			g.update()
		_label_components()
		# the 0.5 m grid's blocked cells are the gaps between the runs; a 1 m cell is open if any of its runs reach it
		var cfree := PackedByteArray()
		cfree.resize(cw * ch)
		for row in h:
			var prev := 0
			for k in range(run_first[row], run_first[row + 1]):
				if run_x0[k] > prev:
					astar_f.fill_solid_region(Rect2i(prev, row, run_x0[k] - prev, 1), true)
				prev = run_x1[k]
				var crow := (row >> 1) * cw
				for c in range(run_x0[k] >> 1, ((run_x1[k] - 1) >> 1) + 1):
					cfree[crow + c] = 1
			if prev < w:
				astar_f.fill_solid_region(Rect2i(prev, row, w - prev, 1), true)
		for cz in ch:
			var base := cz * cw
			var x := base
			var end := base + cw
			while x < end:
				var st := cfree.find(0, x)
				if st < 0 or st >= end:
					break
				var en := cfree.find(1, st)
				if en < 0 or en > end:
					en = end
				astar.fill_solid_region(Rect2i(st - base, cz, en - st, 1), true)
				x = en
		build_ms = (Time.get_ticks_usec() - t0) / 1000.0

	var main_area := -1
	var run_first := PackedInt32Array()    # per row: its first run (h + 1 entries)
	var run_x0 := PackedInt32Array()       # walkable runs of cells in a row: [x0, x1)
	var run_x1 := PackedInt32Array()
	var run_area := PackedInt32Array()

	## Connected areas of walkable cells (4-neighbours, as the diagonal rule allows), labelled by row runs: a route
	## is only searched for inside one area, so a search never floods the board for an unreachable point.
	func _label_components() -> void:
		for row in h:
			run_first.append(run_x0.size())
			var base := row * w
			var x := base
			var end := base + w
			while x < end:
				var st := free.find(1, x)
				if st < 0 or st >= end:
					break
				var en := free.find(0, st)
				if en < 0 or en > end:
					en = end
				run_x0.append(st - base)
				run_x1.append(en - base)
				x = en
		run_first.append(run_x0.size())
		var parent := PackedInt32Array()
		parent.resize(run_x0.size())
		for k in parent.size():
			parent[k] = k
		for row in range(1, h):
			var i := run_first[row - 1]
			var j := run_first[row]
			while i < run_first[row] and j < run_first[row + 1]:
				if run_x0[i] < run_x1[j] and run_x0[j] < run_x1[i]:
					var ra := _find(parent, i)
					var rb := _find(parent, j)
					if ra != rb:
						parent[maxi(ra, rb)] = mini(ra, rb)
				if run_x1[i] < run_x1[j]:
					i += 1
				else:
					j += 1
		run_area.resize(run_x0.size())
		var sizes := {}
		for k in run_x0.size():
			var r := _find(parent, k)
			run_area[k] = r
			sizes[r] = int(sizes.get(r, 0)) + run_x1[k] - run_x0[k]
		var best := 0
		for r: int in sizes:
			if int(sizes[r]) > best:
				best = int(sizes[r])
				main_area = r

	static func _find(parent: PackedInt32Array, k: int) -> int:
		var r := k
		while parent[r] != r:
			r = parent[r]
		var c := k
		while parent[c] != r:
			var nxt := parent[c]
			parent[c] = r
			c = nxt
		return r

	func _area_cell(cx: int, cz: int) -> int:
		if cx < 0 or cz < 0 or cx >= w or cz >= h:
			return -1
		# the last run of the row starting at or before cx (the runs of a row are in order)
		var lo := run_first[cz]
		var hi := run_first[cz + 1] - 1
		if hi < lo or run_x0[lo] > cx:
			return -1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if run_x0[mid] <= cx:
				lo = mid
			else:
				hi = mid - 1
		return run_area[lo] if cx < run_x1[lo] else -1

	## The size of the connected area a point stands in (0 when blocked).
	func area_of(p: Vector2) -> int:
		return _area_cell(floori((p.x - X0) / CELL), floori((p.y - Z0) / CELL))

	func _coarse_centre(c: Vector2i) -> Vector2:
		return Vector2(X0 + (c.x + 0.5) * CELL * COARSE, Z0 + (c.y + 0.5) * CELL * COARSE)

	## The walkable 0.5 m cell nearest the 1 m cell's centre, in the given area (Vector2.INF when none).
	func _rep(c: Vector2i, area: int) -> Vector2:
		var best := Vector2.INF
		var bd := INF
		var mid := _coarse_centre(c)
		for k in 4:
			var fx := c.x * COARSE + (k & 1)
			var fz := c.y * COARSE + (k >> 1)
			if free[fz * w + fx] == 1 and _area_cell(fx, fz) == area:
				var q := centre(fx, fz)
				var d := q.distance_squared_to(mid)
				if d < bd:
					bd = d
					best = q
		return best

	## A walkable polyline from a to b (both walkable points), or empty when there is none. A* on the 1 m grid
	## gives the corridor; consecutive cells that cannot see each other at 0.5 m are joined by a short 0.5 m search;
	## then the string is pulled.
	func route(a: Vector2, b: Vector2) -> PackedVector2Array:
		var t0 := Time.get_ticks_usec()
		var out := PackedVector2Array()
		var area := area_of(a)
		var bridge := _bridge_for(a, b)
		if area >= 0 and area == area_of(b) and not bridge.is_empty():
			# across the canal: over the better footbridge, one bank at a time (a search never floods both banks)
			var r1 := _route_bank(a, bridge[0], area)
			var r2 := _route_bank(bridge[1], b, area)
			if not r1.is_empty() and not r2.is_empty():
				out = r1
				out.append_array(r2)
		elif area >= 0 and area == area_of(b):
			out = _route_bank(a, b, area)
		route_ms += (Time.get_ticks_usec() - t0) / 1000.0
		route_count += 1
		return out

	## The two ends of the footbridge that serves a trip from one bank to the other, or [] (same bank, or a point
	## on the canal's line).
	func _bridge_for(a: Vector2, b: Vector2) -> PackedVector2Array:
		if a.x * b.x >= 0.0 or absf(a.x) < 8.5 or absf(b.x) < 8.5 or clear(a, b):
			return PackedVector2Array()
		var best := PackedVector2Array()
		var bd := INF
		for e: PackedVector2Array in bridge_ends:
			var ea := e[0] if signf(e[0].x) == signf(a.x) else e[1]
			var eb := e[1] if ea == e[0] else e[0]
			var d := a.distance_to(ea) + ea.distance_to(eb) + eb.distance_to(b)
			if d < bd:
				bd = d
				best = PackedVector2Array([ea, eb])
		return best

	var bridge_ends: Array[PackedVector2Array] = []

	func _route_bank(a: Vector2, b: Vector2, area: int) -> PackedVector2Array:
		var out := PackedVector2Array()
		if clear(a, b):
			out = PackedVector2Array([a, b])
		else:
			var ca := Vector2i(floori((a.x - X0) / (CELL * COARSE)), floori((a.y - Z0) / (CELL * COARSE)))
			var cb := Vector2i(floori((b.x - X0) / (CELL * COARSE)), floori((b.y - Z0) / (CELL * COARSE)))
			var ids := astar.get_id_path(ca, cb)
			var chain := PackedVector2Array([a])
			for k in range(1, ids.size() - 1):
				var q := _rep(ids[k], area)
				if q != Vector2.INF:
					chain.append(q)
			chain.append(b)
			var pts := PackedVector2Array([a])
			for k in range(1, chain.size()):
				var p := pts[pts.size() - 1]
				var q := chain[k]
				if clear(p, q):
					pts.append(q)
					continue
				var fp := astar_f.get_point_path(Vector2i(floori((p.x - X0) / CELL), floori((p.y - Z0) / CELL)),
					Vector2i(floori((q.x - X0) / CELL), floori((q.y - Z0) / CELL)))
				if fp.is_empty():
					pts.clear()
					break
				for f in range(1, fp.size()):
					pts.append(Vector2(X0 + (fp[f].x + 0.5) * CELL, Z0 + (fp[f].y + 0.5) * CELL))
				pts[pts.size() - 1] = q
			if not pts.is_empty():
				out = _pull(_corners(pts))
		return out

	## Drops the points where the way runs straight on.
	static func _corners(p: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array([p[0]])
		for k in range(1, p.size() - 1):
			var d0 := (p[k] - out[out.size() - 1]).normalized()
			var d1 := (p[k + 1] - p[k]).normalized()
			if d0.dot(d1) < 0.9999:
				out.append(p[k])
		out.append(p[p.size() - 1])
		return out

	func _pull(pts: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array([pts[0]])
		var anchor := pts[0]
		var i := 1
		while i < pts.size():
			var j := i
			while j + 1 < pts.size() and j + 1 - i < 10 and clear(anchor, pts[j + 1]):
				j += 1
			if out[out.size() - 1].distance_squared_to(pts[j]) > 1e-6:
				out.append(pts[j])
			anchor = pts[j]
			i = j + 1
		return out


static var _ground: Ground = null


## The shared walkable ground (built once per session).
static func ground() -> Ground:
	if _ground == null:
		_ground = Ground.new()
		_ground.build()
	return _ground


# ================================================================== trips

## Where one resident is over one outdoor segment: a polyline and a timeline of (minute, distance along it).
class Trip:
	var k := -1                      # the plan segment
	var t0 := 0.0
	var t1 := 0.0
	var kind := "walk"               # walk, outing, ride, venue, loop
	var pts := PackedVector2Array()
	var cum := PackedFloat32Array()
	var clr := PackedFloat32Array()  # per polyline segment: room for the lane offset (0 on the legs)
	var length := 0.0
	var kt := PackedFloat32Array()   # timeline: minutes ...
	var ks := PackedFloat32Array()   # ... and the distance along the polyline at each
	var speed := 1.3                 # loop walkers: metres per minute
	var s0 := 0.0                    # loop walkers: the distance at t0
	var hide0 := INF                 # aboard a bus: not drawn
	var hide1 := -INF
	var fade_in := -INF
	var fade_out := INF
	var mode_move := MODE_WALK
	var mode_still := MODE_STAND
	var still_yaw := 0.0
	var lane := 0.0
	var from_loc := -1
	var to_loc := -1
	var venue := ""
	var stop_a := -1
	var stop_b := -1
	var ready := true

	func set_pts(p: PackedVector2Array, c: PackedFloat32Array) -> void:
		pts = p
		cum.resize(p.size())
		var acc := 0.0
		for i in p.size():
			if i > 0:
				acc += p[i].distance_to(p[i - 1])
			cum[i] = acc
		length = acc
		if c.size() == maxi(0, p.size() - 1):
			clr = c
		else:
			clr.resize(maxi(0, p.size() - 1))
			clr.fill(0.0)

	## The distance along the polyline at minute m.
	func s_at(m: float) -> float:
		if kind == "loop":
			return s0 + speed * (m - t0)
		if kt.size() < 2:
			return 0.0 if ks.is_empty() else ks[0]
		if m <= kt[0]:
			return ks[0]
		var n := kt.size()
		if m >= kt[n - 1]:
			return ks[n - 1]
		var j := kt.bsearch(m, true) - 1
		j = clampi(j, 0, n - 2)
		var span := kt[j + 1] - kt[j]
		if span <= 1e-6:
			return ks[j + 1]
		return lerpf(ks[j], ks[j + 1], (m - kt[j]) / span)

	func moving_at(m: float) -> bool:
		if kind == "loop":
			return true
		if kt.size() < 2 or m < kt[0] or m >= kt[kt.size() - 1]:
			return false
		var j := clampi(kt.bsearch(m, true) - 1, 0, kt.size() - 2)
		return ks[j + 1] > ks[j] + 1e-4

	## The point at distance s (clamped; wrapped for loops) and the segment it is on.
	func point(s: float) -> Vector2:
		if pts.size() == 1 or length <= 0.0:
			return pts[0]
		var d := fposmod(s, length) if kind == "loop" else clampf(s, 0.0, length)
		var j := clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)
		var span := cum[j + 1] - cum[j]
		return pts[j] if span <= 1e-6 else pts[j].lerp(pts[j + 1], (d - cum[j]) / span)

	func seg_of(s: float) -> int:
		if pts.size() < 2 or length <= 0.0:
			return 0
		var d := fposmod(s, length) if kind == "loop" else clampf(s, 0.0, length)
		return clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)


# ================================================================== state

var sim: Sim = null
var map_script: Variant = TMap
var world: Object = null
var _g: Ground = null
var _plans: Sim.DayPlans = null
var _shared_plans := false
var _next_plans: Sim.DayPlans = null
var _day := -1
var _minute := -1.0
var _focus := Vector3(TMap.ARRIVAL_POS)
var _last_focus := Vector3(TMap.ARRIVAL_POS)
var _frame := 0
var _held_frames := 0
var _idle_clock := 0.0

# per resident
var _hs := PackedFloat32Array()        # height scale
var _pace := PackedFloat32Array()      # metres per minute
var _hash := PackedInt64Array()
var _seg_lo := PackedFloat32Array()
var _seg_hi := PackedFloat32Array()
var _seg_k := PackedInt32Array()
var _act := PackedByteArray()
var _trips: Array = []                 # Trip or null
var _pos := PackedVector3Array()
var _pos_frame := PackedInt32Array()   # the frame _pos was last computed
var _xf_cache: Array[Transform3D] = []
var _cu_cache := PackedColorArray()
var _xf_frame := PackedInt32Array()
## The held pose (unified-r4 bench): while the clock holds (_held_frames >= 2) a figure's place, yaw, mode, alpha and
## so its transform are a pure function of its trip and the minute; only the idle animation's phase moves. Kept per
## resident with the trip and minute they were made for, so a held frame recomputes only the phase.
var _hc_m := PackedFloat64Array()      # the minute of the held pose (NAN: none)
var _hc_tr: Array = []                 # the Trip it was made for
var _hc_xf: Array[Transform3D] = []
var _hc_pos := PackedVector3Array()
var _hc_mode := PackedInt32Array()
var _hc_alpha := PackedFloat64Array()
var _hc_vis := PackedByteArray()
var _hc_h16 := PackedFloat64Array()    # _h01(i, 21) * 16
var _active := PackedInt32Array()
var _next_change := -INF
var _scan_floor := INF

# the map
var _loc_door := PackedInt32Array()    # building index -> route node (doors), -1 for venues
var _loc_venue := PackedStringArray()  # building index -> venue key or ""
var _nodes := PackedVector2Array()
var _venues := {}                      # key -> Dictionary
var _stops: Array = []                 # {id, pos (walkable), node, bus}
var _outing_nodes := PackedInt32Array()
var _unroutable := {}                  # resident -> the segment that could not be placed (today)
var _pending := 0
var _route_spent_ms := 0.0
static var _rooms := {}               # [first, last, size] of a route -> its lane room

# drawing
var _mm_near: MultiMesh
var _mm_far: MultiMesh
var _mi_near: MultiMeshInstance3D
var _mi_far: MultiMeshInstance3D
var _mat: ShaderMaterial
var _looks: ImageTexture
var _drawn := PackedInt32Array()
var _drawn_xf: Array[Transform3D] = []
var _drawn_custom := PackedColorArray()
var _drawn_near := PackedByteArray()
var _culled_range := 0
var _culled_budget := 0
var _aboard := 0
var _fading := 0                       # outdoors but faded right out this frame (joining, going in)
var update_ms := 0.0
var _built := false

# scratch of the last evaluation
var _e_pos := Vector3.ZERO
var _e_yaw := 0.0
var _e_mode := 0
var _e_phase := 0.0
var _e_alpha := 1.0
var _e_vis := false


# ================================================================== setup

## Builds the walkable ground (shared, once per session), the venues, the looks texture and the two MultiMeshes.
## `p_sim` is the lead's Sim (the same 1000 residents); `p_map` defaults to thousand_map.gd; `p_world` may offer
## walk_route(a: Vector2, b: Vector2) -> PackedVector2Array to replace the routes here.
func setup(p_sim: Sim, p_map: Variant = null, p_world: Object = null) -> void:
	if _built:
		return
	_built = true
	sim = p_sim
	if p_map != null:
		map_script = p_map
	world = p_world
	_g = ground()
	var n := sim.count
	_hs.resize(n)
	_pace.resize(n)
	_hash.resize(n)
	_seg_lo.resize(n)
	_seg_hi.resize(n)
	_seg_k.resize(n)
	_act.resize(n)
	_pos.resize(n)
	_pos_frame.resize(n)
	_pos_frame.fill(-100)
	_xf_cache.resize(n)
	_cu_cache.resize(n)
	_xf_frame.resize(n)
	_xf_frame.fill(-100)
	_trips.resize(n)
	_hc_m.resize(n)
	_hc_m.fill(NAN)
	_hc_tr.resize(n)
	_hc_xf.resize(n)
	_hc_pos.resize(n)
	_hc_mode.resize(n)
	_hc_alpha.resize(n)
	_hc_vis.resize(n)
	_hc_h16.resize(n)
	for i in n:
		var hv := Data.hash32("tt-person:%d" % i)
		_hash[i] = hv
		_hs[i] = height_scale(sim.age[i], sim.gender[i] == 1)
		_pace[i] = _pace_of(i)
	_reset_segments()
	_build_places()
	_build_looks()
	_build_draw()


## A resident's scale on the 1.80 m rig: 0.94 for an adult man (1.69 m), x 0.97 for a woman, the curve under 18.
static func height_scale(age: int, female: bool) -> float:
	return _curve(HEIGHT_CURVE, age) * (FEMALE_STATURE if female else 1.0) * ADULT_SCALE


static func head_scale(age: int) -> float:
	return _curve(HEAD_CURVE, age)


static func _curve(table: Array, v: float) -> float:
	var x := clampf(v, float(table[0][0]), float(table[table.size() - 1][0]))
	for k in table.size() - 1:
		var a: Array = table[k]
		var b: Array = table[k + 1]
		if x <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			return float(a[1]) + (float(b[1]) - float(a[1])) * ((x - float(a[0])) / span if span > 0.0 else 0.0)
	return float(table[table.size() - 1][1])


func _h01(i: int, salt: int) -> float:
	var x := (_hash[i] ^ (salt * 0x9E3779B1)) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x) / 4294967296.0


func _pace_of(i: int) -> float:
	var a := sim.age[i]
	var u := _h01(i, 3)
	if sim.role_name(i) == "patient":
		return 0.8 + 0.2 * u
	if a <= 5:
		return 0.95 + 0.2 * u
	if a <= 12:
		return 1.1 + 0.25 * u
	if a < 60:
		return 1.2 + 0.3 * u
	if a < 75:
		return 1.0 + 0.25 * u
	return 0.8 + 0.2 * u


func set_budget(p_max_figures: int, p_max_near: int = -1, p_near_m: float = -1.0, p_far_m: float = -1.0) -> void:
	max_figures = maxi(0, p_max_figures)
	if p_max_near >= 0:
		max_near = p_max_near
	if p_near_m > 0.0:
		near_m = p_near_m
	if p_far_m > 0.0:
		far_m = p_far_m
	if _mm_far != null:
		_mm_far.instance_count = maxi(1, max_figures)
		_mm_far.visible_instance_count = 0
		_mm_near.instance_count = maxi(1, max_near)
		_mm_near.visible_instance_count = 0


## Design section 8: iPad 160 figures, Apple TV 96.
func budget_profile(device: String) -> void:
	if device == "tv":
		set_budget(96, 28, 28.0, 90.0)
	else:
		set_budget(160, 40, 32.0, 110.0)


func focus(pos: Vector3) -> void:
	_focus = pos


func focus_moved() -> bool:
	return _last_focus.distance_squared_to(_focus) > 25.0


## Use the lead's plans for their day (Sim.DayPlans); they are not rebuilt here while their day is current.
func set_plans(plans: Sim.DayPlans) -> void:
	if plans == null:
		return
	_plans = plans
	_shared_plans = true
	_day = plans.day
	_reset_segments()


func _process(delta: float) -> void:
	_idle_clock += delta


# ================================================================== the map: doors, venues, stops

func _node(p: Vector2) -> int:
	var q := _g.snap(p, 8.0, _g.main_area)
	if q == Vector2.INF:
		return -1
	for k in _nodes.size():
		if _nodes[k].distance_squared_to(q) < 0.04:
			return k
	_nodes.append(q)
	return _nodes.size() - 1


func _build_places() -> void:
	var nb := Data.BUILDINGS.size()
	_loc_door.resize(nb)
	_loc_door.fill(-1)
	_loc_venue.resize(nb)
	var annex := {}
	for a: Dictionary in TMap.annexes():
		annex[a.id] = a
	for b in nb:
		var id := String(Data.BUILDINGS[b]["id"])
		var where := String(SIM_TO_MAP.get(id, ""))
		_loc_venue[b] = ""
		var door := Vector2.INF
		if where == "venue":
			_loc_venue[b] = VENUE_OF[id]
			continue
		elif where == "annex" and annex.has(id) and not (annex[id].doors as Array).is_empty():
			door = annex[id].doors[0].pos
		elif where == "office":
			var o: Dictionary = TMap.data().waterfront.street_office
			door = Vector2(float(o.doors[0].x), float(o.doors[0].z))
		elif where.begins_with("b-"):
			var d := TMap.door(where)
			if not d.is_empty():
				door = d.pos
		if door != Vector2.INF:
			_loc_door[b] = _node(door)
	# venues
	var places := {}
	for pl: Dictionary in TMap.places():
		places[pl.id] = pl
	var walk := {}
	for wr: Dictionary in TMap.data().get("walking_routes", []):
		walk[wr.id] = wr
	var solids_walk: Array = []
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(SOLIDS_PATH)) == OK:
		solids_walk = j.data.get("walkable", [])
	var market_rects: Array = []
	var station_rects: Array = []
	for wk: Dictionary in solids_walk:
		if String(wk.kind) == "market-promenade":
			market_rects.append(Ground._rect(wk.rect))
		if String(wk.kind) in ["station-waiting-platform", "station-taxi-platform"]:
			station_rects.append(Ground._rect(wk.rect))
	var st := TMap.station()
	station_rects.append(st.forecourt)
	_add_venue("park-0", [places["park-0"].rect], walk)
	_add_venue("park-1", [places["park-1"].rect], walk)
	_add_venue("plaza", [places["plaza"].rect], walk)
	_add_venue("amusement", [places["amusement"].rect], walk, [Vector2(66.0, 70.4)])
	_add_venue("station", station_rects, walk)
	_add_venue("market", market_rects, walk)
	_add_venue("street", [Rect2(-45.0, -2.4, 31.0, 4.8), Rect2(14.0, -2.4, 31.0, 4.8)], walk)
	# the stall fronts (shopkeepers and diners face the promenade)
	var fronts := PackedVector2Array()
	var front_yaw := PackedFloat32Array()
	for s: Dictionary in TMap.data().waterfront.stalls:
		var side := float(s.side)
		var p := Vector2(float(s.x) - side * (float(s.w) * 0.5 + 0.7), float(s.z))
		var q := _g.snap(p, 2.0)
		if q != Vector2.INF:
			fronts.append(q)
			front_yaw.append(atan2(side, 0.0))
	_venues["market"]["fronts"] = fronts
	_venues["market"]["front_yaw"] = front_yaw
	# bus stops and the taxi rank
	for s: Dictionary in TMap.stops():
		var nd := _node(s.pos)
		if nd >= 0:
			_stops.append({"id": s.id, "pos": _nodes[nd], "node": nd, "bus": true})
	var tr := TMap.taxi_rank()
	var tn := _node(tr.pos)
	if tn >= 0:
		_stops.append({"id": tr.id, "pos": _nodes[tn], "node": tn, "bus": false})
	# outing targets: river-walk and footbridge points, the street, and the parks' and plaza's hubs
	for p: Vector2 in OUTING_POINTS:
		var nd := _node(p)
		if nd >= 0:
			_outing_nodes.append(nd)
	for key: String in ["park-0", "park-1", "plaza"]:
		var hubs: PackedInt32Array = _venues[key]["hubs"]
		if not hubs.is_empty():
			_outing_nodes.append(hubs[0])


func _add_venue(key: String, rects: Array, walk: Dictionary, extra_hubs: Array = []) -> void:
	var v := {"key": key, "rects": rects, "hubs": PackedInt32Array(), "spots": PackedVector2Array(),
		"spot_hub": PackedInt32Array(), "loops": [], "centre": Vector2.ZERO}
	var bounds: Rect2 = rects[0]
	for r: Rect2 in rects:
		bounds = bounds.merge(r)
	v["centre"] = bounds.get_center()
	var cand: Array[Vector2] = []
	for r: Rect2 in rects:
		var c := r.get_center()
		cand.append(c)
		if r.size.x > 14.0 and r.size.y > 14.0:
			cand.append_array([Vector2(c.x, r.position.y + 1.5), Vector2(c.x, r.end.y - 1.5),
				Vector2(r.position.x + 1.5, c.y), Vector2(r.end.x - 1.5, c.y)])
	for p: Vector2 in extra_hubs:
		cand.append(p)
	var hubs := PackedInt32Array()
	for p: Vector2 in cand:
		var nd := _node(p)
		if nd >= 0 and not hubs.has(nd):
			hubs.append(nd)
	v["hubs"] = hubs
	# spots on a grid, each in clear sight of its nearest hub
	var spots := PackedVector2Array()
	var spot_hub := PackedInt32Array()
	for r: Rect2 in rects:
		var x := r.position.x + 0.8
		while x < r.end.x - 0.6:
			var z := r.position.y + 0.8
			while z < r.end.y - 0.6:
				var p := Vector2(x, z)
				if _g.walkable(p) and not _near_arrival(p):
					# the nearest hub in clear sight (nearest first, within 30 m)
					var order: Array = []
					for nd in hubs:
						var d := _nodes[nd].distance_squared_to(p)
						if d < 900.0:
							order.append([d, nd])
					order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
					for e: Array in order:
						if _g.clear(_nodes[int(e[1])], p):
							spots.append(p)
							spot_hub.append(int(e[1]))
							break
				z += 1.7
			x += 1.7
	v["spots"] = spots
	v["spot_hub"] = spot_hub
	# strolling loops, repaired where a straight leg is not clear
	for wid: String in VENUE_LOOPS.get(key, []):
		if not walk.has(wid):
			continue
		var raw: Array = walk[wid].points
		var pts := PackedVector2Array()
		var vtx_s := PackedFloat32Array()
		var vtx_node := PackedInt32Array()
		var prev := Vector2.INF
		for q in raw:
			var nd := _node(Vector2(float(q[0]), float(q[1])))
			if nd < 0:
				continue
			var p := _nodes[nd]
			if prev != Vector2.INF:
				var leg := PackedVector2Array([prev, p]) if _g.clear(prev, p) else _g.route(prev, p)
				if leg.is_empty():
					pts.clear()
					break
				for k in range(1, leg.size()):
					pts.append(leg[k])
			else:
				pts.append(p)
			prev = p
			vtx_node.append(nd)
		if pts.size() < 3:
			continue
		var cum := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		# the arc position of each original vertex (its node), in order along the loop
		for nd in vtx_node:
			var best := 0
			for k in pts.size():
				if pts[k].distance_squared_to(_nodes[nd]) < 1e-4:
					best = k
					break
			vtx_s.append(cum[best])
		(v["loops"] as Array).append({"id": wid, "pts": pts, "cum": cum, "length": cum[cum.size() - 1],
			"vtx_s": vtx_s, "vtx_node": vtx_node})
	_venues[key] = v


# ================================================================== the day and the minute

func _reset_segments() -> void:
	if _seg_lo.is_empty():
		return
	_seg_lo.fill(INF)
	_seg_hi.fill(-INF)
	_seg_k.fill(-1)
	_act.fill(ACT_NONE)
	for i in _trips.size():
		_trips[i] = null
	_pos_frame.fill(-100)
	_xf_frame.fill(-100)
	_next_change = -INF
	_scan_floor = INF
	_unroutable.clear()


func _load_day(day: int) -> void:
	if _plans != null and _plans.day == day:
		_day = day
		return
	if _next_plans != null and _next_plans.day == day and _next_plans.built >= sim.count:
		_plans = _next_plans
	else:
		_plans = sim.build_day(day)
	_next_plans = null
	_shared_plans = false
	_day = day
	_reset_segments()


## Places and draws everybody for a moment of the town clock (call once a frame).
func set_time(day: int, minute: float) -> void:
	if not _built:
		return
	var t0 := Time.get_ticks_usec()
	_frame += 1
	_route_spent_ms = 0.0
	var m := clampf(minute, 0.0, 1439.999)
	if day != _day or _plans == null or _plans.day != day:
		_load_day(day)
	_held_frames = _held_frames + 1 if m == _minute else 0
	if absf(m - _minute) > 0.25 or focus_moved():
		# a jump in time or place: every cached pose is stale
		_pos_frame.fill(-100)
		_xf_frame.fill(-100)
	_last_focus = _focus
	_minute = m
	if m >= _next_change or m < _scan_floor:
		_rescan(m)
	# tomorrow's plans, a slice per frame late in the evening
	if not _shared_plans and m > 1380.0:
		if _next_plans == null or _next_plans.day != day + 1:
			_next_plans = sim.begin_day(day + 1)
		if _next_plans.built < sim.count:
			sim.build_more(_next_plans, 60)
	_place_and_draw(m)
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Places everybody once with every route searched now (no per-frame budget): call it behind the arrival's
## loading so the first frames in the town have nobody waiting for a route.
func warm(day: int, minute: float) -> void:
	var was := sync_routes
	sync_routes = true
	set_time(day, minute)
	sync_routes = was


## Who is where at minute m: refresh every resident whose segment no longer covers m.
func _rescan(m: float) -> void:
	var segs := _plans.segs
	var first := _plans.first
	var SEGN := Sim.SEG
	var next_change := INF
	var floor_lo := -INF
	var active := PackedInt32Array()
	for i in sim.count:
		if m < _seg_lo[i] or m >= _seg_hi[i]:
			var k := -1
			for s in range(first[i], first[i + 1]):
				if m >= segs[s * SEGN] and m < segs[s * SEGN + 1]:
					k = s - first[i]
					break
			if k < 0:
				_seg_lo[i] = m
				_seg_hi[i] = m + 1.0
				_seg_k[i] = -1
				_act[i] = ACT_NONE
				_trips[i] = null
			else:
				var at := (first[i] + k) * SEGN
				_seg_lo[i] = segs[at]
				_seg_hi[i] = segs[at + 1]
				if _seg_k[i] != k:
					_seg_k[i] = k
					_act[i] = _classify(segs[at + 2], segs[at + 3])
					_trips[i] = null
					_pos_frame[i] = -100
					_xf_frame[i] = -100
		next_change = minf(next_change, _seg_hi[i])
		floor_lo = maxf(floor_lo, _seg_lo[i])
		if _act[i] != ACT_NONE:
			active.append(i)
	_next_change = next_change
	_scan_floor = floor_lo
	_active = active


func _classify(state: int, loc: int) -> int:
	if loc == Data.STREET:
		return ACT_TRIP if state == Data.ST_COMMUTE else ACT_VENUE
	if _loc_venue[loc] != "":
		return ACT_VENUE
	return ACT_NONE


func _seg(i: int, k: int) -> Dictionary:
	var n := _plans.first[i + 1] - _plans.first[i]
	if k < 0 or k >= n:
		return {}
	return sim.segment(_plans, i, k)


# ================================================================== building trips

## The trip of resident i over its current segment (built once per segment; null while its route is pending).
func _trip(i: int) -> Trip:
	var tr: Trip = _trips[i]
	if tr != null and tr.ready:
		return tr
	var k := _seg_k[i]
	if int(_unroutable.get(i, -2)) == k:
		return null
	var seg := _seg(i, k)
	if seg.is_empty():
		return null
	if _act[i] == ACT_VENUE:
		tr = _venue_trip(i, k, seg)
	else:
		tr = _street_trip(i, k, seg)
	if tr == null:
		return null
	_trips[i] = tr if tr.ready else null
	return tr if tr.ready else null


func _venue_key(loc: int) -> String:
	return "street" if loc == Data.STREET else _loc_venue[loc]


## The venue plan of resident i over segment seg: {venue, mode, loop (index or -1), spot, hub, yaw, speed, s0}.
func _venue_plan(i: int, seg: Dictionary) -> Dictionary:
	var key := _venue_key(int(seg.location))
	var v: Dictionary = _venues.get(key, {})
	var sub := Data.substate_name(int(seg.substate))
	var out := {"venue": key, "mode": MODE_STAND, "loop": -1, "spot": Vector2.INF, "hub": -1, "yaw": 0.0, "speed": 1.0, "s0": 0.0}
	if v.is_empty():
		return out
	var loops: Array = v["loops"]
	var age := sim.age[i]
	var mode := MODE_STAND
	var walker := false
	match sub:
		"stroll", "walk":
			walker = true
			mode = MODE_WALK
		"morning-exercise":
			if age < 45 and not loops.is_empty():
				walker = true
				mode = MODE_JOG
			else:
				mode = MODE_TAICHI
		"square-dance":
			mode = MODE_DANCE
		"board-games", "afternoon", "after-school", "with-the-kids", "driving":
			mode = MODE_TALK if _h01(i, 41) < 0.6 else MODE_STAND
		"stall", "set-up":
			mode = MODE_WORK
		"night-snack", "staff-meal", "street-food", "supper":
			mode = MODE_EAT
		"rides":
			mode = MODE_WAIT if _h01(i, 42) < 0.4 else MODE_STAND
		_:
			mode = MODE_STAND if _h01(i, 43) < 0.5 else MODE_TALK
	out["mode"] = mode
	if walker and not loops.is_empty():
		var li := int(_h01(i, 44) * loops.size()) % loops.size()
		var lp: Dictionary = loops[li]
		out["loop"] = li
		out["speed"] = (2.2 + 0.6 * _h01(i, 45)) if mode == MODE_JOG else _pace[i] * 0.8
		out["s0"] = _h01(i, 46) * float(lp.length)
		return out
	if mode == MODE_WALK:
		out["mode"] = MODE_STAND
	var fronts: PackedVector2Array = v.get("fronts", PackedVector2Array())
	if key == "market" and (sub in ["stall", "set-up"]) and not fronts.is_empty():
		var f := int(_h01(i, 47) * fronts.size()) % fronts.size()
		out["spot"] = fronts[f]
		out["yaw"] = float((v["front_yaw"] as PackedFloat32Array)[f])
	else:
		var spots: PackedVector2Array = v["spots"]
		if spots.is_empty():
			return out
		var si := (i * 7919 + int(_h01(i, 48) * 97.0)) % spots.size()
		out["spot"] = spots[si]
		var hubp := _nodes[(v["spot_hub"] as PackedInt32Array)[si]]
		var c: Vector2 = v["centre"]
		var look := (c - spots[si]) if spots[si].distance_to(c) > 1.0 else (hubp - spots[si])
		out["yaw"] = atan2(look.x, look.y) + (_h01(i, 49) - 0.5) * (2.4 if mode == MODE_STAND else 0.8)
	out["hub"] = _nearest_hub(v, out["spot"])
	return out


static func _near_arrival(p: Vector2) -> bool:
	for a: Vector2 in Places.THOUSAND_ARRIVALS:
		if a.distance_to(p) < ARRIVAL_CLEAR:
			return true
	return false


func _nearest_hub(v: Dictionary, p: Vector2) -> int:
	var best := -1
	var bd := INF
	for nd in (v["hubs"] as PackedInt32Array):
		var d := _nodes[nd].distance_squared_to(p)
		if d < bd and _g.clear(_nodes[nd], p):
			bd = d
			best = nd
	return best


func _loop_of(vp: Dictionary) -> Dictionary:
	var v: Dictionary = _venues[vp.venue]
	return (v["loops"] as Array)[int(vp.loop)]


static func _loop_point(lp: Dictionary, s: float) -> Vector2:
	var pts: PackedVector2Array = lp.pts
	var cum: PackedFloat32Array = lp.cum
	var d := fposmod(s, float(lp.length))
	var j := clampi(cum.bsearch(d, true) - 1, 0, pts.size() - 2)
	var span := cum[j + 1] - cum[j]
	return pts[j] if span <= 1e-6 else pts[j].lerp(pts[j + 1], (d - cum[j]) / span)


## The loop's polyline from arc sa forward to arc sb (sb >= sa; wraps over the loop's start).
static func _loop_sub(lp: Dictionary, sa: float, sb: float) -> PackedVector2Array:
	var out := PackedVector2Array([_loop_point(lp, sa)])
	var pts: PackedVector2Array = lp.pts
	var cum: PackedFloat32Array = lp.cum
	var length := float(lp.length)
	var base := floorf(sa / length) * length
	for lap in 3:
		for k in pts.size():
			var s := base + lap * length + cum[k]
			if s > sa + 1e-4 and s < sb - 1e-4 and out[out.size() - 1].distance_squared_to(pts[k]) > 1e-6:
				out.append(pts[k])
	var e := _loop_point(lp, sb)
	if out[out.size() - 1].distance_squared_to(e) > 1e-6 or out.size() == 1:
		out.append(e)
	return out


## A place's end of a trip: {pos, node, leg (node -> pos), loc}. `arriving`: the trip ends there at the start of
## segment `seg`; otherwise it leaves there at the end of `seg`.
func _endpoint(i: int, seg: Dictionary, arriving: bool) -> Dictionary:
	if seg.is_empty():
		var home := sim.home[i]
		var nd := _loc_door[home] if home >= 0 else -1
		return {} if nd < 0 else {"pos": _nodes[nd], "node": nd, "leg": PackedVector2Array([_nodes[nd]]), "loc": home}
	var loc := int(seg.location)
	var venue := (loc == Data.STREET and int(seg.state) != Data.ST_COMMUTE) or (loc != Data.STREET and _loc_venue[loc] != "")
	if not venue:
		if loc == Data.STREET:
			return {}
		var nd := _loc_door[loc]
		return {} if nd < 0 else {"pos": _nodes[nd], "node": nd, "leg": PackedVector2Array([_nodes[nd]]), "loc": loc}
	var vp := _venue_plan(i, seg)
	if int(vp.loop) >= 0:
		var lp := _loop_of(vp)
		var s := float(vp.s0) if arriving else float(vp.s0) + float(vp.speed) * (float(seg.end) - float(seg.start))
		var vs: PackedFloat32Array = lp.vtx_s
		var vn: PackedInt32Array = lp.vtx_node
		var length := float(lp.length)
		var d := fposmod(s, length)
		if arriving:
			# come in at the last loop vertex before s, then walk the loop up to s
			var j := 0
			for k in vs.size():
				if vs[k] <= d:
					j = k
			var sa := s - (d - vs[j])
			return {"pos": _loop_point(lp, s), "node": vn[j], "leg": _loop_sub(lp, sa, s), "loc": loc}
		# leave at the next loop vertex after s
		var jn := -1
		for k in vs.size():
			if vs[k] > d + 0.01:
				jn = k
				break
		var sb := s + ((vs[jn] - d) if jn >= 0 else (length - d + vs[0]))
		var nd2: int = vn[jn] if jn >= 0 else vn[0]
		var leg := _loop_sub(lp, s, sb)
		leg.reverse()
		return {"pos": _loop_point(lp, s), "node": nd2, "leg": leg, "loc": loc}
	var spot: Vector2 = vp.spot
	var hub := int(vp.hub)
	if spot == Vector2.INF or hub < 0:
		return {}
	return {"pos": spot, "node": hub, "leg": PackedVector2Array([_nodes[hub], spot]), "loc": loc}


## The cached route between two nodes (forward), computing it if the frame's budget allows; null when pending,
## an empty array when there is none.
func _route(a: int, b: int) -> Variant:
	if a == b:
		return PackedVector2Array([_nodes[a]])
	var key := Vector2i(mini(a, b), maxi(a, b))
	var r: PackedVector2Array
	if _g.routes.has(key):
		r = _g.routes[key]
	else:
		if not sync_routes and _route_spent_ms >= route_budget_ms:
			return null
		var t0 := Time.get_ticks_usec()
		if world != null and world.has_method("walk_route"):
			r = world.call("walk_route", _nodes[key.x], _nodes[key.y])
		else:
			r = _g.route(_nodes[key.x], _nodes[key.y])
		_route_spent_ms += (Time.get_ticks_usec() - t0) / 1000.0
		_g.routes[key] = r
	if r.is_empty():
		return r
	if a == key.x:
		return r
	var rev := r.duplicate()
	rev.reverse()
	return rev


## Lane room per segment of a route: how far a walker may keep to the right of the centre line (cached with the
## route; the check is the same both ways, so a reversed route has the reversed room).
func _lane_room(p: PackedVector2Array) -> PackedFloat32Array:
	if p.size() >= 2:
		var key := [p[0], p[p.size() - 1], p.size()]
		if _rooms.has(key):
			return _rooms[key]
		var rkey := [p[p.size() - 1], p[0], p.size()]
		if _rooms.has(rkey):
			var rev: PackedFloat32Array = (_rooms[rkey] as PackedFloat32Array).duplicate()
			rev.reverse()
			return rev
	var out := PackedFloat32Array()
	for k in p.size() - 1:
		var a := p[k]
		var b := p[k + 1]
		var d := b - a
		if d.length() < 2.5:
			out.append(0.0)
			continue
		var nrm := Vector2(-d.y, d.x).normalized() * 0.45
		out.append(0.45 if _g.clear(a + nrm, b + nrm) and _g.clear(a - nrm, b - nrm) else 0.0)
	if p.size() >= 2:
		_rooms[[p[0], p[p.size() - 1], p.size()]] = out
	return out


## Concatenates legs into one polyline with its lane room (the legs keep to the centre line).
func _join(parts: Array, rooms: Array) -> Array:
	var pts := PackedVector2Array()
	var clr := PackedFloat32Array()
	for n in parts.size():
		var part: PackedVector2Array = parts[n]
		var room: PackedFloat32Array = rooms[n]
		for k in part.size():
			var p := part[k]
			if not pts.is_empty() and pts[pts.size() - 1].distance_squared_to(p) < 1e-4:
				continue
			if not pts.is_empty():
				clr.append(room[k - 1] if k >= 1 and k - 1 < room.size() else 0.0)
			pts.append(p)
	return [pts, clr]


func _street_trip(i: int, k: int, seg: Dictionary) -> Trip:
	var tr := Trip.new()
	tr.k = k
	tr.t0 = float(seg.start)
	tr.t1 = float(seg.end)
	var prev := _seg(i, k - 1)
	var nxt := _seg(i, k + 1)
	var a := _endpoint(i, prev, false)
	var b := _endpoint(i, nxt, true)
	if a.is_empty() or b.is_empty():
		_unroutable[i] = k
		return null
	tr.from_loc = int(a.loc)
	tr.to_loc = int(b.loc)
	tr.lane = 1.0 if _h01(i, 5) < 0.5 else 0.6
	var v := _pace[i]
	var D := tr.t1 - tr.t0
	var sub := Data.substate_name(int(seg.substate))
	if int(a.node) == int(b.node) and int(a.loc) == int(b.loc) and (a.leg as PackedVector2Array).size() == 1:
		return _outing_trip(i, tr, a, v, D)
	if sub == "ride":
		var rt := _ride_trip(i, tr, a, b, v, D)
		if rt != null:
			return rt
		if not tr.ready:
			return tr
	var r: Variant = _route(int(a.node), int(b.node))
	if r == null:
		tr.ready = false
		_pending += 1
		return tr
	if (r as PackedVector2Array).is_empty():
		_unroutable[i] = k
		return null
	var la: PackedVector2Array = (a.leg as PackedVector2Array).duplicate()
	la.reverse()
	var j := _join([la, r, b.leg], [PackedFloat32Array(), _lane_room(r), PackedFloat32Array()])
	tr.set_pts(j[0], j[1])
	tr.kind = "walk"
	_walk_timeline(i, tr, 0.0, tr.length, tr.t0, tr.t1, v, true, _loc_venue_of(int(b.loc)) == "")
	return tr


func _loc_venue_of(loc: int) -> String:
	return "street" if loc == Data.STREET else _loc_venue[loc]


## Walks [s_from, s_to] of the polyline between minutes ta and tb at pace v (briskly up to 1.35 v, slowly down to
## 0.8 v): joins partway when it is too far, waits at the start and lingers at the end when there is time over.
func _walk_timeline(i: int, tr: Trip, s_from: float, s_to: float, ta: float, tb: float, v: float, fresh: bool, into_door: bool) -> void:
	var L := s_to - s_from
	var D := tb - ta
	if fresh:
		tr.kt = PackedFloat32Array()
		tr.ks = PackedFloat32Array()
	if L <= 0.05 or D <= 0.0:
		tr.kt.append_array([ta, tb])
		tr.ks.append_array([s_to, s_to])
	else:
		var ve := clampf(L / D, 0.8 * v, 1.35 * v)
		var tw := L / ve
		if tw >= D:
			var start := s_to - ve * D
			tr.kt.append_array([ta, tb])
			tr.ks.append_array([start, s_to])
			if start > s_from + 0.05 and fresh:
				tr.fade_in = ta
		else:
			var wait0 := (D - tw) * (0.3 + 0.55 * _h01(i, 7))
			tr.kt.append_array([ta, ta + wait0, ta + wait0 + tw, tb])
			tr.ks.append_array([s_from, s_from, s_to, s_to])
	if into_door:
		tr.fade_out = tb


## A walk out from a building and back: toward an outing target, turning back halfway through the time.
func _outing_trip(i: int, tr: Trip, a: Dictionary, v: float, D: float) -> Trip:
	tr.kind = "outing"
	var home_node := int(a.node)
	# the three nearest targets, one picked by the resident's coin
	var order: Array = []
	for nd in _outing_nodes:
		if nd != home_node:
			order.append([_nodes[nd].distance_squared_to(_nodes[home_node]), nd])
	order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	if order.is_empty():
		_unroutable[i] = tr.k
		return null
	var pick := int(_h01(i, 11) * mini(3, order.size()))
	var target := int(order[pick][1])
	var r: Variant = _route(home_node, target)
	if r == null:
		tr.ready = false
		_pending += 1
		return tr
	var path: PackedVector2Array = r
	if path.is_empty():
		path = PackedVector2Array([_nodes[home_node]])
	# out as far as half the time allows, a pause, and back
	var room := _lane_room(path)
	var out := PackedVector2Array([path[0]])
	var out_room := PackedFloat32Array()
	var budget := v * D * 0.42
	var acc := 0.0
	for k in range(1, path.size()):
		var d := path[k].distance_to(path[k - 1])
		if acc + d >= budget:
			out.append(path[k - 1].lerp(path[k], (budget - acc) / maxf(d, 1e-6)))
			out_room.append(room[k - 1])
			acc = budget
			break
		out.append(path[k])
		out_room.append(room[k - 1])
		acc += d
	var back := out.duplicate()
	back.reverse()
	var back_room := out_room.duplicate()
	back_room.reverse()
	var j := _join([out, back], [out_room, back_room])
	tr.set_pts(j[0], j[1])
	var half := tr.length * 0.5
	var tw := half / v
	var slack := maxf(0.0, D - 2.0 * tw)
	var wait0 := slack * 0.35 * _h01(i, 12)
	var pause := slack - wait0 - slack * 0.25
	var a0 := tr.t0 + wait0
	tr.kt = PackedFloat32Array([tr.t0, a0, a0 + tw, a0 + tw + pause, minf(tr.t1, a0 + 2.0 * tw + pause), tr.t1])
	tr.ks = PackedFloat32Array([0.0, 0.0, half, half, tr.length, tr.length])
	tr.fade_out = tr.t1
	tr.to_loc = tr.from_loc
	return tr


## A ride: to the stop nearest the start, a wait, aboard, and from the stop nearest the end. Null when the stops
## are too far or the same one (the trip is walked instead); a trip with ready = false while a route is pending.
func _ride_trip(i: int, tr: Trip, a: Dictionary, b: Dictionary, v: float, D: float) -> Trip:
	var sa := _nearest_stop(a.pos)
	var sb := _nearest_stop(b.pos)
	if sa < 0 or sb < 0 or sa == sb:
		return null
	var pa: Vector2 = _stops[sa].pos
	var pb: Vector2 = _stops[sb].pos
	if pa.distance_to(a.pos) > RIDE_STOP_M or pb.distance_to(b.pos) > RIDE_STOP_M:
		return null
	var r1: Variant = _route(int(a.node), int(_stops[sa].node))
	var r2: Variant = _route(int(_stops[sb].node), int(b.node))
	if r1 == null or r2 == null:
		tr.ready = false
		_pending += 1
		return tr
	if (r1 as PackedVector2Array).is_empty() or (r2 as PackedVector2Array).is_empty():
		return null
	var la: PackedVector2Array = (a.leg as PackedVector2Array).duplicate()
	la.reverse()
	var leg1 := _join([la, r1], [PackedFloat32Array(), _lane_room(r1)])
	var leg2 := _join([r2, b.leg], [_lane_room(r2), PackedFloat32Array()])
	var p1: PackedVector2Array = leg1[0]
	var p2: PackedVector2Array = leg2[0]
	var c1: PackedFloat32Array = leg1[1]
	var c2: PackedFloat32Array = leg2[1]
	var all := p1.duplicate()
	all.append_array(p2)
	var clr := c1.duplicate()
	clr.append(0.0)          # the ride itself (not drawn)
	clr.append_array(c2)
	tr.set_pts(all, clr)
	tr.kind = "ride"
	tr.stop_a = sa
	tr.stop_b = sb
	var l1 := 0.0
	for k in range(1, p1.size()):
		l1 += p1[k].distance_to(p1[k - 1])
	var lr := pa.distance_to(pb)
	var l2 := tr.length - l1 - lr
	var ride_t := minf(lr / RIDE_SPEED, D * 0.4)
	var rest := D - ride_t
	var w1 := l1 / v
	var w2 := l2 / v
	tr.kt = PackedFloat32Array()
	tr.ks = PackedFloat32Array()
	if w1 + w2 <= rest:
		var wait := rest - w1 - w2
		var wait_stop := wait * 0.7
		var wait0 := wait - wait_stop - wait * 0.15
		var tb := tr.t0 + wait0 + w1 + wait_stop
		tr.kt = PackedFloat32Array([tr.t0, tr.t0 + wait0, tr.t0 + wait0 + w1, tb, tb + ride_t, tb + ride_t + w2, tr.t1])
		tr.ks = PackedFloat32Array([0.0, 0.0, l1, l1, l1 + lr, tr.length, tr.length])
		tr.hide0 = tb
		tr.hide1 = tb + ride_t
	else:
		# too little time: join the first leg partway, ride, and walk the second at a brisk pace
		var k1 := rest * w1 / (w1 + w2)
		var k2 := rest - k1
		var s_start := maxf(0.0, l1 - v * k1)
		var tb := tr.t0 + k1
		var v2 := clampf(l2 / maxf(k2, 1e-3), v, 1.35 * v)
		var s_end := minf(tr.length, l1 + lr + v2 * k2)
		tr.kt = PackedFloat32Array([tr.t0, tb, tb + ride_t, tr.t1])
		tr.ks = PackedFloat32Array([s_start, l1, l1 + lr, s_end])
		if s_start > 0.05:
			tr.fade_in = tr.t0
		tr.hide0 = tb
		tr.hide1 = tb + ride_t
	if _loc_venue_of(int(b.loc)) == "":
		tr.fade_out = tr.t1
	return tr


func _nearest_stop(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for k in _stops.size():
		if not bool(_stops[k].bus):
			continue
		var d := (_stops[k].pos as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = k
	return best


func _venue_trip(i: int, k: int, seg: Dictionary) -> Trip:
	var vp := _venue_plan(i, seg)
	var tr := Trip.new()
	tr.k = k
	tr.t0 = float(seg.start)
	tr.t1 = float(seg.end)
	tr.venue = String(vp.venue)
	tr.from_loc = int(seg.location)
	tr.to_loc = tr.from_loc
	tr.mode_still = int(vp.mode)
	tr.still_yaw = float(vp.yaw)
	if int(vp.loop) >= 0:
		var lp := _loop_of(vp)
		tr.kind = "loop"
		tr.set_pts(lp.pts, PackedFloat32Array())
		tr.speed = float(vp.speed)
		tr.s0 = float(vp.s0)
		tr.mode_move = int(vp.mode)
		tr.lane = 0.0
		return tr
	if vp.spot == Vector2.INF:
		_unroutable[i] = k
		return null
	tr.kind = "venue"
	tr.set_pts(PackedVector2Array([vp.spot]), PackedFloat32Array())
	tr.kt = PackedFloat32Array([tr.t0, tr.t1])
	tr.ks = PackedFloat32Array([0.0, 0.0])
	return tr


# ================================================================== evaluation

## Evaluates resident i's trip at minute m into the _e_* scratch. `full`: also yaw, mode, phase and fade.
func _eval(i: int, tr: Trip, m: float, full: bool) -> void:
	_e_vis = not (m >= tr.hide0 and m < tr.hide1)
	var s := tr.s_at(m)
	var p := tr.point(s)
	var moving := tr.moving_at(m)
	var seg := 0
	if moving and tr.lane != 0.0 and tr.pts.size() > 1:
		seg = tr.seg_of(s)
		var room := tr.clr[seg] if seg < tr.clr.size() else 0.0
		if room > 0.0:
			var d := fposmod(s, tr.length) if tr.kind == "loop" else clampf(s, 0.0, tr.length)
			var edge := minf(d - tr.cum[seg], tr.cum[seg + 1] - d)
			var dir := (tr.pts[seg + 1] - tr.pts[seg]).normalized()
			var off := Vector2(-dir.y, dir.x) * room * tr.lane * Ground._sm(edge / 1.2)
			p -= off
	_e_pos = Vector3(p.x, _g.y_at(p), p.y)
	if not full:
		return
	var hs := _hs[i]
	if moving and _held_frames < 2:
		var a := tr.point(s - 0.5)
		var b := tr.point(s + 0.5)
		var dv := b - a
		_e_yaw = atan2(dv.x, dv.y) if dv.length_squared() > 1e-6 else tr.still_yaw
		_e_mode = tr.mode_move
		_e_phase = fposmod(s / (STRIDE * hs / ADULT_SCALE), 16.0)
	else:
		_e_mode = tr.mode_still if tr.kind == "venue" or tr.kind == "loop" else MODE_WAIT
		if tr.kind == "walk" or tr.kind == "outing" or tr.kind == "ride":
			# waiting at a door or stop: face along the way on (or back the way they came at the end)
			var a2 := tr.point(s)
			var b2 := tr.point(s + 1.0) if s < tr.length - 0.5 else tr.point(s - 1.0)
			var dv2 := (b2 - a2) if s < tr.length - 0.5 else (a2 - b2)
			_e_yaw = atan2(dv2.x, dv2.y) if dv2.length_squared() > 1e-6 else 0.0
			if s >= tr.length - 0.5:
				_e_mode = MODE_STAND
		else:
			_e_yaw = tr.still_yaw
		var clock := m if _held_frames < 2 else m + _idle_clock
		_e_phase = fposmod((clock - tr.t0) / float(MODE_PERIOD[_e_mode]) + _h01(i, 21) * 16.0, 16.0)
	var alpha := 1.0
	if m < tr.fade_in + FADE:
		alpha = Ground._sm((m - tr.fade_in) / FADE)
	if m > tr.fade_out - FADE:
		alpha = minf(alpha, Ground._sm((tr.fade_out - m) / FADE))
	if tr.hide0 < INF:
		if m < tr.hide0 and m > tr.hide0 - FADE * 0.5:
			alpha = minf(alpha, Ground._sm((tr.hide0 - m) / (FADE * 0.5)))
		if m >= tr.hide1 and m < tr.hide1 + FADE * 0.5:
			alpha = minf(alpha, Ground._sm((m - tr.hide1) / (FADE * 0.5)))
	_e_alpha = alpha
	if alpha <= 0.0:
		_e_vis = false


# ================================================================== drawing

func _place_and_draw(m: float) -> void:
	_pending = 0
	_aboard = 0
	_fading = 0
	_culled_range = 0
	_culled_budget = 0
	var far2 := far_m * far_m
	var held := _held_frames >= 2
	var cand := PackedInt32Array()
	var dist := PackedFloat32Array()
	var fresh_since := _frame - 3
	for i in _active:
		var tr: Trip = _trips[i]
		if tr == null or not tr.ready:
			tr = _trip(i)   # (the ready trip, the common case, without the call)
			if tr == null:
				continue
		if m >= tr.hide0 and m < tr.hide1:
			_aboard += 1
			continue
		# distances for the choice: each resident re-placed every 4th frame (the drawn ones every frame below)
		if _pos_frame[i] < fresh_since or ((i + _frame) & 3) == 0:
			if held and _hc_m[i] == m and _hc_tr[i] == tr:
				_pos[i] = _hc_pos[i]   # the held pose's place (the same _eval would give)
			else:
				_eval(i, tr, m, false)
				_pos[i] = _e_pos
			_pos_frame[i] = _frame
		var d := _pos[i].distance_squared_to(_focus)
		if d > far2:
			_culled_range += 1
			continue
		cand.append(i)
		dist.append(d)
	# nearest first within the budget
	var limit := INF
	if cand.size() > max_figures:
		var sorted := dist.duplicate()
		sorted.sort()
		limit = sorted[max_figures - 1] if max_figures > 0 else -1.0
	var near_limit := near_m * near_m
	var near_count := 0
	for k in cand.size():
		if dist[k] <= near_limit:
			near_count += 1
	if near_count > max_near:
		var nd := PackedFloat32Array()
		for k in cand.size():
			if dist[k] <= near_limit:
				nd.append(dist[k])
		nd.sort()
		near_limit = nd[max_near - 1] if max_near > 0 else -1.0
	_drawn.clear()
	_drawn_xf.clear()
	_drawn_custom.clear()
	_drawn_near.clear()
	var n_near := 0
	var n_far := 0
	var taken := 0
	for k in cand.size():
		if dist[k] > limit or taken >= max_figures:
			_culled_budget += 1
			continue
		var i := cand[k]
		var near := dist[k] <= near_limit and n_near < max_near
		var xf: Transform3D
		var custom: Color
		# far figures are re-posed every other frame (the frame between reuses the last pose)
		if near or _xf_frame[i] < _frame - 1 or ((i + _frame) & 1) == 0:
			var tr: Trip = _trips[i]
			if held and _hc_m[i] == m and _hc_tr[i] == tr:
				# a held frame: the pose is the one made for this trip and minute; only the phase moves (as _eval's
				# held branch computes it, clock = m + _idle_clock)
				if _hc_vis[i] == 0:
					_fading += 1
					continue
				var mode := _hc_mode[i]
				xf = _hc_xf[i]
				custom = Color(float(i), fposmod((m + _idle_clock - tr.t0) / float(MODE_PERIOD[mode]) + _hc_h16[i], 16.0),
					float(mode), _hc_alpha[i])
				_pos[i] = _hc_pos[i]
				_pos_frame[i] = _frame
				_xf_cache[i] = xf
				_cu_cache[i] = custom
				_xf_frame[i] = _frame
				taken += 1
				if near:
					_mm_near.set_instance_transform(n_near, xf)
					_mm_near.set_instance_custom_data(n_near, custom)
					n_near += 1
				else:
					_mm_far.set_instance_transform(n_far, xf)
					_mm_far.set_instance_custom_data(n_far, custom)
					n_far += 1
				_drawn.append(i)
				_drawn_xf.append(xf)
				_drawn_custom.append(custom)
				_drawn_near.append(1 if near else 0)
				continue
			_eval(i, tr, m, true)
			var s := _hs[i]
			if held:
				_hc_m[i] = m
				_hc_tr[i] = tr
				_hc_pos[i] = _e_pos
				_hc_mode[i] = _e_mode
				_hc_alpha[i] = _e_alpha
				_hc_vis[i] = 1 if _e_vis else 0
				_hc_h16[i] = _h01(i, 21) * 16.0
				if _e_vis:
					_hc_xf[i] = Transform3D(Basis(Vector3.UP, _e_yaw).scaled(Vector3(s, s, s)), _e_pos)
			if not _e_vis:
				_fading += 1
				continue
			xf = Transform3D(Basis(Vector3.UP, _e_yaw).scaled(Vector3(s, s, s)), _e_pos)
			custom = Color(float(i), _e_phase, float(_e_mode), _e_alpha)
			_pos[i] = _e_pos
			_pos_frame[i] = _frame
			_xf_cache[i] = xf
			_cu_cache[i] = custom
			_xf_frame[i] = _frame
		else:
			xf = _xf_cache[i]
			custom = _cu_cache[i]
			_xf_frame[i] = _frame
		taken += 1
		if near:
			_mm_near.set_instance_transform(n_near, xf)
			_mm_near.set_instance_custom_data(n_near, custom)
			n_near += 1
		else:
			_mm_far.set_instance_transform(n_far, xf)
			_mm_far.set_instance_custom_data(n_far, custom)
			n_far += 1
		_drawn.append(i)
		_drawn_xf.append(xf)
		_drawn_custom.append(custom)
		_drawn_near.append(1 if near else 0)
	_mm_near.visible_instance_count = n_near
	_mm_far.visible_instance_count = n_far


func _build_draw() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	_mat.set_shader_parameter("looks", _looks)
	var aabb := AABB(Vector3(-100.0, -4.0, -135.0), Vector3(200.0, 12.0, 270.0))
	_mm_near = MultiMesh.new()
	_mm_near.transform_format = MultiMesh.TRANSFORM_3D
	_mm_near.use_custom_data = true
	_mm_near.mesh = figure_mesh(false)
	_mm_near.instance_count = maxi(1, max_near)
	_mm_near.visible_instance_count = 0
	_mm_near.custom_aabb = aabb
	_mm_far = MultiMesh.new()
	_mm_far.transform_format = MultiMesh.TRANSFORM_3D
	_mm_far.use_custom_data = true
	_mm_far.mesh = figure_mesh(true)
	_mm_far.instance_count = maxi(1, max_figures)
	_mm_far.visible_instance_count = 0
	_mm_far.custom_aabb = aabb
	_mi_near = MultiMeshInstance3D.new()
	_mi_near.name = "residents_near"
	_mi_near.multimesh = _mm_near
	_mi_near.material_override = _mat
	add_child(_mi_near)
	_mi_far = MultiMeshInstance3D.new()
	_mi_far.name = "residents_far"
	_mi_far.multimesh = _mm_far
	_mi_far.material_override = _mat
	_mi_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi_far)


## Two draw calls (the near and the far MultiMesh), whatever the number of figures.
func draw_calls() -> int:
	return int(_mm_near.visible_instance_count > 0) + int(_mm_far.visible_instance_count > 0)


## Accumulates a mesh with per-vertex colour slots and bones in UV, features and the packed shade in UV2.
class MeshBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(a: PropsCity.Acc, slot: int, bone: int, feat: int = 0) -> void:
		var base := v.size()
		v.append_array(a.v)
		n.append_array(a.n)
		c.append_array(a.c)
		for k in a.v.size():
			uv.append(Vector2(slot, bone))
			var col := a.c[k]
			var packed := (roundi(clampf(col.r, 0.0, 1.0) * 15.0) << 8) | (roundi(clampf(col.g, 0.0, 1.0) * 15.0) << 4) | roundi(clampf(col.b, 0.0, 1.0) * 15.0)
			uv2.append(Vector2(feat, packed))
		for x in a.idx:
			idx.append(base + x)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am


## The figure at scale 1 (1.80 m), facing +z, feet on y = 0. `far`: the blocky distant version.
static func figure_mesh(far: bool) -> ArrayMesh:
	var mb := MeshBuf.new()
	var wc := Color.WHITE
	var hip := 0.86
	var a := PropsCity.acc()
	a.box(Vector3(0, hip + 0.05, 0), Vector3(0.34, 0.18, 0.23), wc, 0.0 if far else 0.04)
	mb.add(a, 2, B_PELVIS)
	a = PropsCity.acc()
	a.box(Vector3(0, hip + 0.33, 0), Vector3(0.42, 0.46, 0.24), wc, 0.0 if far else 0.05)
	mb.add(a, 1, B_TORSO)
	a = PropsCity.acc()
	if far:
		a.box(Vector3(0, 1.62, 0), Vector3(0.33, 0.35, 0.31), wc)
		mb.add(a, 0, B_HEAD)
		a = PropsCity.acc()
		a.box(Vector3(0, 1.62 + 0.15, -0.02), Vector3(0.355, 0.13, 0.34), wc)
		a.box(Vector3(0, 1.62 + 0.03, -0.16), Vector3(0.355, 0.22, 0.05), wc)
		mb.add(a, 4, B_HEAD)
	else:
		a.box(Vector3(0, 1.45, 0), Vector3(0.11, 0.1, 0.11), wc)
		a.xf = Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))
		CityPeople._head_shape(a)
		mb.add(a, 0, B_HEAD)
		var styles := [CityPeople.M_HAIR_SHORT, CityPeople.M_HAIR_LONG, CityPeople.M_HAIR_BUN, CityPeople.M_HAIR_PONY,
			CityPeople.M_HAIR_CURLY, CityPeople.M_HAIR_CAP]
		for k in styles.size():
			a = PropsCity.acc()
			a.xf = Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))
			CityPeople._hair_shape(a, styles[k])
			mb.add(a, 4, B_HEAD, k + 1)
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var x := sg * 0.255
		a = PropsCity.acc()
		if far:
			a.box(Vector3(x, 1.22, 0), Vector3(0.11, 0.32, 0.11), wc)
		else:
			a.prism(Vector3(x, 1.22, 0), 0.062, 0.32, wc, 8)
		mb.add(a, 1, B_UARM_L + side)
		a = PropsCity.acc()
		if far:
			a.box(Vector3(x, 0.9, 0), Vector3(0.095, 0.34, 0.095), wc)
		else:
			a.prism(Vector3(x, 0.93, 0), 0.052, 0.3, wc, 8)
		mb.add(a, 8, B_FARM_L + side)
		if not far:
			a = PropsCity.acc()
			a.box(Vector3(x, 0.735, 0.0), Vector3(0.085, 0.1, 0.075), wc)
			mb.add(a, 0, B_FARM_L + side)
		a = PropsCity.acc()
		if far:
			a.box(Vector3(sg * 0.09, 0.66, 0), Vector3(0.15, 0.42, 0.15), wc)
		else:
			a.prism(Vector3(sg * 0.09, 0.66, 0), 0.08, 0.42, wc, 8)
		mb.add(a, 10, B_THIGH_L + side)
		a = PropsCity.acc()
		if far:
			a.box(Vector3(sg * 0.09, 0.27, 0), Vector3(0.125, 0.4, 0.125), wc)
		else:
			a.prism(Vector3(sg * 0.09, 0.27, 0), 0.068, 0.4, wc, 8)
		mb.add(a, 9, B_SHIN_L + side)
		a = PropsCity.acc()
		a.box(Vector3(sg * 0.09, 0.04, 0.05), Vector3(0.13, 0.08, 0.25), wc)
		mb.add(a, 3, B_SHIN_L + side)
	# the look features
	a = PropsCity.acc()
	if far:
		a.box(Vector3(0, hip - 0.1, 0), Vector3(0.48, 0.42, 0.36), wc)
	else:
		a.xf = Transform3D(Basis.IDENTITY, Vector3(0, hip + 0.12, 0))
		CityPeople._skirt_shape(a)
	mb.add(a, 6, B_PELVIS, 10 + F_DRESS)
	a = PropsCity.acc()
	a.box(Vector3(0, 0.93, 0.13), Vector3(0.36, 0.62, 0.025), wc)
	mb.add(a, 5, B_TORSO, 10 + F_APRON)
	a = PropsCity.acc()
	a.box(Vector3(0, 0.78, -0.13), Vector3(0.44, 0.5, 0.03), wc)
	a.box(Vector3(-0.215, 0.78, -0.01), Vector3(0.03, 0.5, 0.24), wc)
	a.box(Vector3(0.215, 0.78, -0.01), Vector3(0.03, 0.5, 0.24), wc)
	mb.add(a, 5, B_PELVIS, 10 + F_COAT)
	a = PropsCity.acc()
	a.box(Vector3(0, hip + 0.33, 0), Vector3(0.445, 0.4, 0.265), wc)
	mb.add(a, 5, B_TORSO, 10 + F_VEST)
	if not far:
		a = PropsCity.acc()
		a.box(Vector3(0, hip + 0.25, 0), Vector3(0.452, 0.04, 0.272), wc)
		a.box(Vector3(0, hip + 0.4, 0), Vector3(0.452, 0.04, 0.272), wc)
		mb.add(a, 6, B_TORSO, 10 + F_VEST)
		a = PropsCity.acc()
		a.box(Vector3(0.275, 0.98, 0.0), Vector3(0.07, 0.24, 0.22), wc)
		a.box(Vector3(0.2, 1.24, 0.0), Vector3(0.04, 0.4, 0.03), wc, 0.0, Basis(Vector3.BACK, 0.5))
		mb.add(a, 5, B_TORSO, 10 + F_BAG)
		a = PropsCity.acc()
		a.box(Vector3(0, 1.645, 0.168), Vector3(0.3, 0.07, 0.02), Color(0.15, 0.14, 0.14))
		mb.add(a, 0, B_HEAD, 10 + F_GLASSES)
		a = PropsCity.acc()
		a.box(Vector3(0, 1.25, 0.125), Vector3(0.07, 0.3, 0.02), wc)
		mb.add(a, 5, B_TORSO, 10 + F_TIE)
	a = PropsCity.acc()
	a.box(Vector3(0, 1.2, -0.19), Vector3(0.3, 0.36, 0.14), wc, 0.0 if far else 0.03)
	mb.add(a, 5, B_TORSO, 10 + F_PACK)
	return mb.mesh()


## The looks of every resident, eight texels each (skin, top, bottom, shoes, hair, accent, skirt, params).
func _build_looks() -> void:
	var img := Image.create(8, sim.count, false, Image.FORMAT_RGBA8)
	for i in sim.count:
		var lk := look_of(i)
		for k in 7:
			img.set_pixel(k, i, lk.colors[k])
		img.set_pixel(7, i, Color8(int(lk.hair), int(lk.flags), int(lk.head_code), int(lk.flags2)))
	_looks = ImageTexture.create_from_image(img)


## A resident's look, deterministic from the roster: {colors (7), hair, flags, flags2, head_code, head}.
func look_of(i: int) -> Dictionary:
	var role := sim.role_name(i)
	var spec: Dictionary = ROLE_LOOKS.get(role, ROLE_LOOKS["retiree"])
	var age := sim.age[i]
	var female := sim.gender[i] == 1
	var pickc := func(key: String, salt: int, fallback: Color) -> Color:
		var list: Array = spec.get(key, [])
		if list.is_empty():
			return fallback
		return Color(String(list[int(_h01(i, salt) * list.size()) % list.size()]))
	var chance := func(key: String, salt: int) -> bool:
		return _h01(i, salt) < float(spec.get(key, 0.0))
	var skin: Color = SKIN[(sim.ordinal[i] + int(_h01(i, 60) * 2.0)) % SKIN.size()]
	var top: Color = pickc.call("top", 61, Color("#b7ab8c"))
	var bottom_list: Array = spec.get("bottom", [])
	var bottom: Color = top if (not bottom_list.is_empty() and String(bottom_list[0]) == "=top") else pickc.call("bottom", 62, Color("#4b4f56"))
	var shoes: Color = pickc.call("shoes", 63, Color("#2a2624"))
	var accent: Color = pickc.call("accent", 64, Color("#8a6a42"))
	var skirt_c: Color = pickc.call("skirt", 65, bottom) if spec.has("skirt") else (bottom if bottom != top else top.darkened(0.15))
	var hair_c := Color("#38312e").lerp(Color("#8d8a80"), clampf((age - 38.0) / 62.0, 0.0, 1.0))
	if age < 18:
		hair_c = Color("#2e2724") if _h01(i, 66) < 0.8 else Color("#5a4232")
	var flags := 0
	var flags2 := 0
	if female:
		flags2 |= 1 << G_FEMALE
	if chance.call("short", 67):
		flags2 |= 1 << G_SHORT_SLEEVES
	if chance.call("shorts", 68) and not (female and chance.call("dress", 69)):
		flags2 |= 1 << G_SHORTS
	if female and chance.call("dress", 69):
		flags |= 1 << F_DRESS
	if chance.call("apron", 70):
		flags |= 1 << F_APRON
	if chance.call("coat", 71):
		flags |= 1 << F_COAT
	if chance.call("vest", 72):
		flags |= 1 << F_VEST
	if chance.call("glasses", 73):
		flags |= 1 << F_GLASSES
	if not female and chance.call("tie", 74):
		flags |= 1 << F_TIE
	if chance.call("pack", 75):
		flags |= 1 << F_PACK
	elif chance.call("bag", 76):
		flags |= 1 << F_BAG
	var hair := HAIR_SHORT
	var hu := _h01(i, 77)
	if spec.has("cap") and hu < float(spec.get("cap_p", 0.0)):
		hair = HAIR_CAP
		hair_c = pickc.call("cap", 78, hair_c)
	elif female:
		hair = [HAIR_LONG, HAIR_BUN, HAIR_PONY, HAIR_SHORT, HAIR_CURLY][int(_h01(i, 79) * 5.0) % 5]
		if age >= 60 and _h01(i, 80) < 0.6:
			hair = [HAIR_BUN, HAIR_SHORT, HAIR_CURLY][int(_h01(i, 81) * 3.0) % 3]
	else:
		hair = HAIR_SHORT if _h01(i, 79) < 0.72 else HAIR_CURLY
		if age >= 60 and _h01(i, 82) < 0.18:
			hair = HAIR_NONE
	var head := head_scale(age)
	var head_code := clampi(int(round((head - 0.9) / 0.6 * 255.0)), 0, 255)
	return {"colors": [skin, top, bottom, shoes, hair_c, accent, skirt_c], "hair": hair, "flags": flags, "flags2": flags2,
		"head_code": head_code, "head": head, "role": role}


# ================================================================== queries

## The resident under a ray (the nearest drawn figure's body capsule it passes through), or -1.
func pick(ray_origin: Vector3, ray_dir: Vector3) -> int:
	var d := ray_dir.normalized()
	var best := -1
	var bt := INF
	for k in _drawn.size():
		var i := _drawn[k]
		var base: Vector3 = _drawn_xf[k].origin
		var height := RIG_HEIGHT * _hs[i]
		var r := BODY_R * maxf(0.7, _hs[i] / ADULT_SCALE)
		# the closest approach of the ray to the vertical segment [base, base + height]
		var w0 := ray_origin - base
		var b := d.y
		var dd := d.dot(w0)
		var e := w0.y
		var den := 1.0 - b * b
		var t := 0.0
		var u := 0.0
		if den > 1e-6:
			t = (b * e - dd) / den
			u = clampf(e + t * b, 0.0, height)
			t = maxf(0.0, (base + Vector3(0, u, 0) - ray_origin).dot(d))
		else:
			t = maxf(0.0, -dd)
			u = clampf(ray_origin.y + d.y * t - base.y, 0.0, height)
		var on_ray := ray_origin + d * t
		var on_body := base + Vector3(0, clampf(on_ray.y - base.y, 0.0, height), 0)
		if on_ray.distance_to(on_body) <= r and t < bt:
			bt = t
			best = i
	return best


func pick_screen(camera: Camera3D, screen_pos: Vector2) -> int:
	return pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


## The drawn resident nearest to pos within radius metres (on the ground plane), or -1 (the TV's "who is near").
func nearest(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius * radius
	for k in _drawn.size():
		var o: Vector3 = _drawn_xf[k].origin
		var d := Vector2(o.x - pos.x, o.z - pos.z).length_squared()
		if d <= bd:
			bd = d
			best = _drawn[k]
	return best


func drawn_ids() -> PackedInt32Array:
	return _drawn


## The drawn figures as written last frame: {id: {xf, custom, near}} (tests and tours; the headless renderer
## keeps no MultiMesh data).
func drawn_snapshot() -> Dictionary:
	var out := {}
	for k in _drawn.size():
		out[_drawn[k]] = {"xf": _drawn_xf[k], "custom": _drawn_custom[k], "near": _drawn_near[k] == 1}
	return out


## Where resident i is now: on the street or at a venue its figure's feet; inside, the building's door; INF if
## the plan does not cover the minute.
func position_of(i: int) -> Vector3:
	if i < 0 or i >= sim.count or _plans == null:
		return Vector3.INF
	if _act[i] != ACT_NONE:
		var tr := _trip(i)
		if tr != null:
			_eval(i, tr, _minute, false)
			return _e_pos
	var k := _seg_k[i]
	var seg := _seg(i, k)
	if seg.is_empty():
		return Vector3.INF
	var loc := int(seg.location)
	if loc == Data.STREET or _loc_door[loc] < 0:
		var v: Dictionary = _venues.get(_venue_key(loc), {})
		if v.is_empty():
			return Vector3.INF
		var c: Vector2 = v["centre"]
		return Vector3(c.x, _g.y_at(c), c.y)
	var p := _nodes[_loc_door[loc]]
	return Vector3(p.x, _g.y_at(p), p.y)


func _loc_id(loc: int) -> String:
	return "" if loc < 0 else Data.location_name(loc)


## What resident i is doing, for the inspect panel and "follow this resident's commute".
func info(i: int, locale: String = "en") -> Dictionary:
	if i < 0 or i >= sim.count or _plans == null:
		return {}
	var k := _seg_k[i]
	var seg := _seg(i, k)
	var out := {"id": i, "resident_id": sim.ids[i], "name": sim.name_of(i, locale), "role": sim.role_name(i), "age": sim.age[i],
		"height_m": RIG_HEIGHT * _hs[i], "drawn": _drawn.has(i), "minute": _minute, "day": _day}
	if seg.is_empty():
		return out
	out["state"] = Data.STATES[int(seg.state)]
	out["substate"] = Data.substate_name(int(seg.substate))
	out["where"] = _loc_id(int(seg.location))
	out["eta_minute"] = float(seg.end)
	out["mode"] = "inside"
	out["position"] = position_of(i)
	var tr: Trip = _trips[i] if _act[i] != ACT_NONE else null
	if tr != null:
		var s := tr.s_at(_minute)
		out["from"] = _loc_id(tr.from_loc)
		out["to"] = _loc_id(tr.to_loc)
		var dest := tr.point(tr.length) if tr.kind != "loop" else tr.point(s)
		out["destination"] = Vector3(dest.x, _g.y_at(dest), dest.y)
		out["progress"] = 1.0 if tr.length <= 0.0 or tr.kind == "loop" else clampf(s / tr.length, 0.0, 1.0)
		out["remaining_m"] = 0.0 if tr.kind == "loop" else maxf(0.0, tr.length - s)
		out["trip"] = tr.kind
		if _minute >= tr.hide0 and _minute < tr.hide1:
			out["mode"] = "aboard"
		elif tr.moving_at(_minute):
			out["mode"] = MODE_NAMES[tr.mode_move]
		elif tr.kind == "venue" or tr.kind == "loop":
			out["mode"] = MODE_NAMES[tr.mode_still]
		else:
			out["mode"] = "waiting"
		if tr.stop_a >= 0:
			out["stops"] = [_stops[tr.stop_a].id, _stops[tr.stop_b].id]
	return out


## The current trip's polyline (feet height), for following a commute; empty when inside.
func route_of(i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if i < 0 or i >= sim.count or _act[i] == ACT_NONE:
		return out
	var tr := _trip(i)
	if tr == null:
		return out
	for p in tr.pts:
		out.append(Vector3(p.x, _g.y_at(p), p.y))
	return out


## Who is where at the current minute: on the street (sim COMMUTE + street spots), at the outdoor venues, drawn,
## aboard a ride, culled by range or by the budget, waiting for a route, unroutable; and indoors per building.
func counts() -> Dictionary:
	var street := 0
	var venue := 0
	for i in _active:
		if _act[i] == ACT_TRIP:
			street += 1
		else:
			venue += 1
	var per := {}
	if _plans != null:
		var occ := sim.occupancy(_plans, _minute)
		var pb: PackedInt32Array = occ["per_building"]
		for b in pb.size():
			if _loc_venue[b] == "" and pb[b] > 0:
				per[Data.location_name(b)] = pb[b]
	return {"street": street, "venue": venue, "outdoor": street + venue, "drawn": _drawn.size(), "aboard": _aboard, "fading": _fading,
		"culled_range": _culled_range, "culled_budget": _culled_budget, "pending": _pending,
		"unroutable": _unroutable.size(), "indoors": per}


func stats() -> Dictionary:
	var near := 0
	for b in _drawn_near:
		near += b
	return {"update_ms": update_ms, "drawn": _drawn.size(), "near": near, "far": _drawn.size() - near,
		"draw_calls": draw_calls(), "active": _active.size(), "routes_cached": _g.routes.size(),
		"route_ms_total": _g.route_ms, "ground_build_ms": _g.build_ms, "nodes": _nodes.size()}


## The route nodes and venues (tests): {nodes, venues: {key: {spots, hubs, loops}}, stops}.
func layout() -> Dictionary:
	return {"nodes": _nodes, "venues": _venues, "stops": _stops, "doors": _loc_door}
