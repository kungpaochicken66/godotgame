## Thousand Town's time-dependent events (design/thousand-town.md sections 8 and 9): the nightly fireworks
## show (19:00-22:00, a 96 s loop) and the plaza fountain's jets (the pump programme, the "show" 19:00-21:10).
## Adapted from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY (github.com/YiHuiShiBY/thousand-town,
## commit 1332ef2, CC BY 4.0): city-fireworks.js (launchSites, townSchedule, townFlight, the shell and burst
## shapes) and city-fountain.js (RINGS, buildRings, wave, the droplets). Changed for Lantern Lane: metres,
## bolder and fewer sparks (a 600 cap, 400 on the TV), every contour shape drawn face-on to the watcher, a
## burst flash instead of real lights, and a fountain show pattern with lit colours at night.
##
## The schedules are core/thousand_clock.gd's (fireworks_schedule, fountain_level_smooth, fountain_program).
## Positions come from the town data: the eight launch sites are upstream's SITE_LAYOUT (a host building,
## park, the sports ground or the amusement park in town.json, plus upstream's offset times 0.5), and the
## fountain is town.json landmarks.fountain.
##
## API (the lead adds this node under the Thousand world and calls it every frame):
##   setup(world: Node3D)        the ThousandWorld (resolve_walk, height_at, occluders, view_time); null works
##                               (the town data only). Builds the tables and three MultiMesh nodes, once.
##   update(day, minute, dt, eye)
##                               the town clock (thousand_world.view_time()), the real frame time and the
##                               camera's position. Outside both windows nothing is drawn and nothing is computed.
##   status() -> Dictionary      {"fireworks": bool, "phase": "off" | "ensemble" | "weave" | "finale" | "rest",
##                               "show_seconds", "next_fireworks_minute" (1140), "minutes_to_fireworks",
##                               "sparks", "shells", "fountain" (the programme name), "fountain_level",
##                               "fountain_show": bool}
##   watch_point(kind) -> Dictionary
##                               "fireworks" or "fountain": {"kind", "stand" (Vector2, walkable), "y" (ground),
##                               "ry" (the child's yaw facing the show), "look_at" (Vector3), "camera"
##                               (Transform3D: watch_camera() for that spot), "sites" (fireworks: the launch
##                               sites in view)}. {} for an unknown kind.
##   watch_camera(child, look_at, dist, height) -> Transform3D (static)
##                               a camera behind the child that keeps the child low in the frame and the
##                               target high (the follow camera of section 6 looks down; the sky needs this).
##   sparks_at(day, minute, show_seconds, eye) -> PackedFloat32Array
##                               the pure fireworks frame (16 floats a spark: the MultiMesh buffer layout).
##   drive: bool                 true: the node calls update() itself every frame from world.view_time() and
##                               the viewport's camera (no change to thousand_world.gd's _process needed).
##   spark_cap: int              MAX_SPARKS (600); MAX_SPARKS_TV (400) on the Apple TV (section 8).
##   pin_show_seconds: float     >= 0 holds the show at that second (tests and captures); -1 runs it.
##
## Time. Lantern Lane's clock runs 1 sim minute per real second at 1x, so in Auto at 1x the show is exactly
## thousand_clock.fireworks_state(day, minute). When the clock is held (Day, Dusk, Night) or runs at 2x or
## 4x, the show and the fountain keep their real pace: an offset collects the real seconds by which the
## clock and real time differ, and is cleared by a jump (a preset), and every night once both the show and
## the pump are off. Two devices that see the same clock therefore start the same show second and run it in
## real time. The look at (day, minute, show_seconds, eye) is a pure function (sparks_at): the schedule, the
## launch sites and every spark's velocity, life and colour come from the seeded tables; nothing uses
## unseeded randomness. Only the facing of the contour shapes (ring, heart, star, saturn, spiral, fan)
## depends on the eye, as upstream's glyphBasis does, so each watcher sees them face-on.
##
## Budget. One MultiMesh for every spark, comet, ember and burst flash (one draw call), one for the 28 jets'
## columns and one for their spray and foam: three draw calls at most, the fireworks' only at night.
## CPU-driven MultiMeshes with use_colors (Compatibility renderer, no compute; a MultiMesh without colours
## draws black there). No real lights: in the Compatibility renderer every omni light adds passes to the
## meshes it touches, so a burst gets a short additive flash quad instead.
extends Node3D

const Clock := preload("res://scripts/core/thousand_clock.gd")
const ThousandMap := preload("res://scripts/core/thousand_map.gd")
const ThousandNav := preload("res://scripts/core/thousand_nav.gd")
const Data := preload("res://scripts/core/thousand_sim_data.gd")

## Section 8: the fireworks' sparks on the iPad and on the Apple TV.
const MAX_SPARKS := 600
const MAX_SPARKS_TV := 400
const UNIT := Clock.UNIT_M
const SPM := Clock.SECONDS_PER_SIM_MINUTE
const TAU_F := TAU
const GOLDEN := PI * (3.0 - 2.236067977499790)
## upstream's TOWN_PHYSICS, in upstream units (positions are scaled by UNIT afterwards)
const GRAVITY := 9.81
const WIND_X := 0.65
const WIND_Z := 0.22
const EMBER_INTERVAL := 0.03
const EMBER_LIFE := 0.18
const EMBERS := 5
## A spark's drawn size in metres (upstream's 0.3-unit stars would be 2 px across a street at 100 m), and a
## floor on its angular size so a far bloom still reads.
const SPARK_M := 2.8
const MIN_SPARK_ANGLE := 0.015
const HALO_M := 12.0
const HALO_LIFE := 0.45
const TRAIL_LAG := 0.085
## A jump of the clock larger than this (seconds of difference from real time in one frame) is a preset.
const JUMP_SECONDS := 30.0
const FLOATS := 16

## upstream's TOWN_COLORS (linear RGB) in FIREWORK_COLORS order, and TOWN_COLOR_LAYERS: [core, outer] by colour.
const COLOURS := [Color(1.0, 0.025, 0.055), Color(1.0, 0.17, 0.018), Color(0.025, 0.22, 1.0),
	Color(0.045, 1.0, 0.14), Color(0.52, 0.035, 1.0), Color(1.0, 0.68, 0.22), Color(1.0, 0.035, 0.38)]
const COLOUR_LAYERS := [[5, 0], [5, 1], [5, 4], [5, 1], [5, 2], [5, 3], [5, 6]]
const COMET_COLOUR := Color(1.0, 0.79, 0.47)
const SALUTE_COLOUR := Color(1.0, 0.95, 0.86)

## upstream's SITE_LAYOUT: id, host kind, host key, offset in upstream units (x, y, z).
const SITE_LAYOUT := [
	["primary-court", "building", "b-0-0", Vector3(-8, 1.5, 18)],
	["depot-court", "building", "b-2-0", Vector3(-8, 1.5, 17)],
	["west-park", "park", 0, Vector3(-18.5, 0.22, 10)],
	["east-park", "park", 1, Vector3(18.5, 0.22, 10)],
	["sports-field", "place", "sports", Vector3(6, 0.405, 4)],
	["amusement-side", "place", "amusement", Vector3(22, 0.37, -10)],
	["university-court", "building", "b-20-0", Vector3(12, 1.5, -18)],
	["library-court", "building", "b-22-0", Vector3(12, 1.5, -18)],
]

## The shapes (upstream's SHAPES, with lifetime = life x (1 + tail x 0.6)), in upstream units:
##   n sparks, speed, life (s), drag, trails (ghost samples behind each spark), size (x SPARK_M),
##   form: sphere | ring | crown | palm | contour (heart, star, saturn, spiral, fan: contourDirection).
const SHAPES := {
	"peony": {"n": 84, "speed": 26.0, "life": 2.6, "drag": 0.9, "trails": 0, "size": 1.0, "form": "sphere"},
	"chrysanthemum": {"n": 72, "speed": 25.0, "life": 4.12, "drag": 0.85, "trails": 1, "size": 0.95, "form": "sphere"},
	"willow": {"n": 52, "speed": 19.0, "life": 7.04, "drag": 0.7, "trails": 2, "size": 0.9, "form": "sphere"},
	"ring": {"n": 60, "speed": 27.0, "life": 3.1, "drag": 0.9, "trails": 0, "size": 1.05, "form": "ring"},
	"crown": {"n": 56, "speed": 24.0, "life": 5.13, "drag": 0.8, "trails": 1, "size": 1.0, "form": "crown"},
	"palm": {"n": 45, "speed": 31.0, "life": 3.63, "drag": 0.95, "trails": 1, "size": 1.2, "form": "palm"},
	"heart": {"n": 72, "speed": 29.0, "life": 3.58, "drag": 0.72, "trails": 0, "size": 1.05, "form": "contour"},
	"star": {"n": 70, "speed": 31.0, "life": 3.45, "drag": 0.75, "trails": 0, "size": 1.05, "form": "contour"},
	"saturn": {"n": 81, "speed": 29.0, "life": 3.81, "drag": 0.74, "trails": 0, "size": 1.0, "form": "contour"},
	"spiral": {"n": 64, "speed": 30.0, "life": 3.88, "drag": 0.7, "trails": 1, "size": 1.0, "form": "contour"},
	"fan": {"n": 63, "speed": 28.0, "life": 3.99, "drag": 0.8, "trails": 1, "size": 1.0, "form": "contour"},
	"salute": {"n": 40, "speed": 22.0, "life": 0.9, "drag": 1.6, "trails": 0, "size": 0.45, "form": "sphere"},
}
const PALM_ARMS := 9

## The plaza fountain: upstream's RINGS spread (the radii and heights are town.json's, already in metres),
## 12 droplets a jet, the show's colours at night.
const RING_SPREAD := {"main": 0.28, "low": 0.34}
const DROPS := 12
const SHOW_COLOURS := [Color(0.2, 0.55, 1.0), Color(0.2, 1.0, 0.55), Color(0.72, 0.3, 1.0), Color(1.0, 0.32, 0.6),
	Color(1.0, 0.78, 0.35)]
const LAMP_COLOUR := Color(1.0, 0.898, 0.737)   # #ffe5bc
const DROP_M := 0.3
const FOAM_M := 0.9

## Draw the events on its own (see the header).
var drive := false
var spark_cap := MAX_SPARKS
var pin_show_seconds := -1.0

var world: Node3D = null
var sites: Array[Dictionary] = []          # {id, pos: Vector3 (m)}
var fountain_centre := Vector3(30.0, 0.0, 60.0)
var fountain_surface := 0.23

var _shells: Array[Shell] = []
var _jets: Array[Dictionary] = []          # {local: Vector2, angle, tier, base, hvar, phase, drops: Array}
var _drop_rows: Array[PackedFloat64Array] = []   # per jet, its drops' numbers (_build_drop_rows)
var _built := false
var _fw_node: MultiMeshInstance3D
var _fw_mm: MultiMesh
var _jet_node: MultiMeshInstance3D
var _jet_mm: MultiMesh
var _drop_node: MultiMeshInstance3D
var _drop_mm: MultiMesh
var _buf := PackedFloat32Array()
var _offset := 0.0
var _last_abs := -1.0
var _event_seconds := 0.0
var _status := {}
var _watch := {}
var _last_t := -1.0



## One shell of the show, precomputed (see _build_shells). Typed fields: the per-spark loop reads them often.
class Shell:
	var ordinal := 0
	var t0 := 0.0             # fire time, s into the show
	var at := 0.0             # apex time after launch
	var v0 := 0.0             # launch speed, units/s
	var dx := 0.0             # the comet's sideways drift, units/s
	var dz := 0.0
	var end := 0.0            # burnt out, s into the show
	var site := 0
	var origin := Vector3.ZERO    # the launch point (m)
	var apex_u := Vector3.ZERO    # the burst point relative to the origin (units)
	var apex := Vector3.ZERO      # the burst point (m)
	var carry := Vector3.ZERO     # the velocity at the burst (units/s)
	var core := Color.WHITE
	var outer := Color.WHITE
	var shape := ""
	var form := ""
	var kind := 0             # 0 plain, 1 willow (cools to amber), 2 salute (white crackle)
	var rel := false          # velocities in the watcher's (right, up, normal)
	var trails := 0
	var intensity := 1.0
	var n := 0
	var sp := PackedFloat32Array()   # stride 8: a, b, c, k, life, size, layer, phase; longest life first
	var size := 1.0
	var halo := 0.0
	var tilt := 1.0
	# per frame (_compose)
	var since := 0.0
	var basis := Basis.IDENTITY
	var alive := 0

# ---------------------------------------------------------------- setup


func setup(w: Node3D) -> void:
	world = w
	if _built:
		return
	_built = true
	var d: Dictionary = ThousandMap.data()
	sites = launch_sites(d)
	var f: Dictionary = d.get("landmarks", {}).get("fountain", {})
	if not f.is_empty():
		fountain_centre = Vector3(float(f.x), 0.0, float(f.z))
		fountain_surface = float(f.get("surface_y", 0.23))
	_shells = _build_shells()
	_jets = _build_jets(f)
	_build_nodes()
	_status = _make_status(1, 480.0, 0.0, 0, 0, 0.0)


## The eight launch sites in upstream's order (city-fireworks.js launchSites): the host's centre plus the
## offset, in metres. A missing host is an error, as upstream (the site is then left at the board's centre).
static func launch_sites(d: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_id := {}
	for b: Dictionary in d.get("buildings", []):
		by_id[str(b.get("id", ""))] = b
	var places: Dictionary = d.get("places", {})
	for s: Array in SITE_LAYOUT:
		var host: Dictionary = {}
		match str(s[1]):
			"building":
				host = by_id.get(s[2], {})
			"park":
				var parks: Array = places.get("parks", [])
				var k := 0
				for p: Dictionary in parks:
					if str(p.get("use", "")) == "park":
						if k == int(s[2]):
							host = p
							break
						k += 1
			"place":
				host = places.get(s[2], {})
		var off: Vector3 = s[3]
		if host.is_empty():
			push_error("thousand_events: launch site %s has no host %s" % [s[0], str(s[2])])
		var hx := float(host.get("x", 0.0))
		var hz := float(host.get("z", 0.0))
		out.append({"id": s[0], "pos": Vector3(hx + off.x * UNIT, off.y * UNIT, hz + off.z * UNIT)})
	return out


## Upstream's townFlight: dv/dt = -k (v - wind) + gravity, closed form. Returns [x, y, z, vx, vy, vz] in units.
static func flight(t: float, vx: float, vy: float, vz: float, k: float) -> PackedFloat32Array:
	var e := exp(-k * t)
	var f := (1.0 - e) / k
	var gk := GRAVITY / k
	return PackedFloat32Array([WIND_X * t + (vx - WIND_X) * f, (vy + gk) * f - gk * t, WIND_Z * t + (vz - WIND_Z) * f,
		WIND_X + (vx - WIND_X) * e, (vy + gk) * e - gk, WIND_Z + (vz - WIND_Z) * e])


## upstream's contourDirection for heart, star, saturn, spiral and fan: (right, up, normal) components.
static func contour(kind: String, index: int, count: int) -> Vector3:
	var u := float(index) / float(count)
	var angle := u * TAU
	var z := 0.025 * sin(float(index) * GOLDEN)
	match kind:
		"heart":
			return Vector3(16.0 * pow(sin(angle), 3) / 17.0,
				(13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle)) / 17.0, z)
		"star":
			var edge := floori(u * 10.0)
			var along := u * 10.0 - edge
			var a := PI / 2.0 - edge * TAU / 10.0
			var b := a - TAU / 10.0
			var ra := 0.43 if edge % 2 == 1 else 1.0
			var rb := 1.0 if edge % 2 == 1 else 0.43
			return Vector3(cos(a) * ra * (1.0 - along) + cos(b) * rb * along,
				sin(a) * ra * (1.0 - along) + sin(b) * rb * along, z)
		"saturn":
			var ring_count := floori(count * 2.0 / 3.0)
			if index < ring_count:
				angle = float(index) / ring_count * TAU
				return Vector3(cos(angle), sin(angle) * 0.38, sin(angle) * sqrt(1.0 - 0.38 * 0.38))
			var body := index - ring_count
			var body_count := count - ring_count
			var phi := acos(1.0 - 2.0 * ((body + 0.5) / body_count))
			angle = body * GOLDEN
			return Vector3(0.42 * sin(phi) * cos(angle), 0.42 * cos(phi), 0.42 * sin(phi) * sin(angle))
		"spiral":
			u = float(index) / float(count - 1)
			angle = u * TAU * 2.4
			var radius := 0.15 + 0.85 * u
			return Vector3(cos(angle) * radius, sin(angle) * radius, z)
	# fan: nine ribs
	var per_rib := float(count) / 9.0
	var rib := floori(index / per_rib)
	var reach := 0.2 + 0.8 * fmod(float(index), per_rib) / (per_rib - 1.0)
	angle = -0.9 + 1.8 * rib / 8.0
	return Vector3(sin(angle) * reach, cos(angle) * reach, z)


## The 128 shells of a show with their sparks, precomputed once. Per shell: fire time, apex time, end, the
## launch origin (m), the apex relative to it and the velocity there (units), colours, form and the spark
## table `sp` (stride 8: a, b, c (the velocity: world x, y, z, or right, up, normal for a relative form),
## k (drag), life, size, layer (0 core, 1 outer), phase), sorted by life, longest first.
func _build_shells() -> Array[Shell]:
	var out: Array[Shell] = []
	for s: Dictionary in Clock.fireworks_schedule():
		var shape: String = s.game_shape
		var def: Dictionary = SHAPES.get(shape, SHAPES.peony)
		var ci := Clock.FIREWORK_COLORS.find(s.color)
		var layers: Array = COLOUR_LAYERS[ci % COLOUR_LAYERS.size()]
		var sh := Shell.new()
		sh.core = COLOURS[layers[0]]
		sh.outer = COLOURS[layers[1]]
		if shape == "willow":
			sh.outer = COLOURS[5]
			sh.kind = 1
		elif shape == "salute":
			sh.core = SALUTE_COLOUR
			sh.outer = SALUTE_COLOUR
			sh.kind = 2
		sh.ordinal = int(s.ordinal)
		sh.t0 = float(s.fire_time)
		sh.at = float(s.apex_time)
		sh.v0 = float(s.ascent_velocity_units)
		var drift: Vector2 = s.drift_units
		sh.dx = drift.x
		sh.dz = drift.y
		var a := flight(sh.at, sh.dx, sh.v0, sh.dz, 1.0)
		sh.site = int(s.site)
		sh.origin = sites[sh.site].pos if sh.site < sites.size() else Vector3.ZERO
		sh.apex_u = Vector3(a[0], a[1], a[2])
		sh.apex = sh.origin + sh.apex_u * UNIT
		sh.carry = Vector3(a[3], a[4], a[5])
		sh.intensity = float(s.intensity)
		sh.shape = shape
		sh.form = def.form
		sh.rel = sh.form == "contour" or sh.form == "ring"
		sh.trails = int(def.trails)
		sh.sp = _spark_table(sh.ordinal, shape, def, sh.intensity)
		@warning_ignore("integer_division")
		sh.n = sh.sp.size() / 8
		sh.size = float(def.size)
		sh.halo = HALO_M * (1.4 if shape == "salute" else 1.0)
		sh.tilt = -1.0 if sh.ordinal % 2 == 1 else 1.0
		sh.end = sh.t0 + sh.at + float(def.life) + TRAIL_LAG * sh.trails
		out.append(sh)
	return out


func _spark_table(ordinal: int, shape: String, def: Dictionary, intensity: float) -> PackedFloat32Array:
	var n := int(def.n)
	var speed := float(def.speed)
	var life := float(def.life)
	var drag := float(def.drag)
	var form: String = def.form
	var rand := Data.Rng.new((ordinal * 40503 + 7919) & 0xFFFFFFFF)
	var rows: Array = []
	for i in n:
		var fuel := rand.next()
		var grain := rand.next()
		var turb := rand.next()
		var size := 0.68 + rand.next() * 0.65
		var jitter := 0.82 + rand.next() * 0.36
		var phase := rand.next()
		var v := Vector3.ZERO
		var k := drag
		var spark_life := life * (0.67 + 0.33 * fuel)
		var layer := 0
		match form:
			"sphere":
				var theta := i * GOLDEN + (turb - 0.5) * 0.68
				var phi := clampf(acos(1.0 - 2.0 * ((i + 0.5) / n)) + (grain - 0.5) * 0.24, 0.015, PI - 0.015)
				var volume := 0.37 + grain * 1.1 if grain < 0.26 else 0.86 + turb * 0.28
				var sp := speed * jitter * volume * (0.55 + 0.45 * intensity)
				v = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * sp
				k = drag * (0.76 + turb * 0.54)
				layer = 1 if volume * jitter >= 0.94 else 0
			"ring":
				var theta := float(i) / n * TAU + (turb - 0.5) * 0.045
				layer = 1 if jitter >= 1.0 else 0
				var sp := speed * (0.98 + (jitter - 0.82) / 0.36 * 0.04) * (1.08 if layer == 1 else 0.94) * (0.55 + 0.45 * intensity)
				# a ring tilted 60 degrees from face-on: an ellipse half as tall as wide
				v = Vector3(cos(theta), sin(theta) * 0.5, sin(theta) * 0.866) * sp
				spark_life = life * (0.85 + 0.15 * fuel)
			"crown":
				var theta := float(i) / n * TAU + (turb - 0.5) * 0.06
				var polar := 0.72 + (grain - 0.5) * 0.16
				layer = 1 if jitter >= 1.0 else 0
				var sp := speed * (0.92 + 0.16 * (jitter - 0.82) / 0.36) * (0.55 + 0.45 * intensity)
				v = Vector3(sin(polar) * cos(theta), cos(polar), sin(polar) * sin(theta)) * sp
			"palm":
				var arm := i % PALM_ARMS
				@warning_ignore("integer_division")
				var step := i / PALM_ARMS
				var phi := acos(1.0 - (arm + 0.5) / PALM_ARMS * 1.45)
				var theta := arm * GOLDEN + 0.4
				var sp := speed * (1.0 - step * 0.075) * (0.55 + 0.45 * intensity)
				v = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * sp
				layer = 1 if step == 0 else 0
				spark_life = life * (0.9 - step * 0.05 + 0.1 * fuel)
				k = drag
			"contour":
				var c := contour(shape, i, n)
				layer = 1 if jitter >= 1.0 else 0
				var sp := speed * (0.98 + (jitter - 0.82) / 0.36 * 0.04) * (1.06 if layer == 1 else 0.94) * (0.55 + 0.45 * intensity)
				v = c * sp
				spark_life = life * (0.85 + 0.15 * fuel)
		if shape == "salute":
			k = drag
		rows.append([v.x, v.y, v.z, k, spark_life, size, layer, phase])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[4] > b[4])
	var out := PackedFloat32Array()
	for r: Array in rows:
		for x in r:
			out.append(float(x))
	return out


## The 28 jets: upstream's buildRings with its seeded draws (phase, height variation, wobble, 12 droplets
## each, then the ring's offset), at town.json's radii and heights.
func _build_jets(f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rings: Array = f.get("rings", [{"base_height": 4.2, "count": 16, "radius": 6.325, "tier": "main"},
		{"base_height": 2.15, "count": 12, "radius": 6.875, "tier": "low"}])
	var rand := Data.Rng.new((Data.SEED ^ 0x504F4E54) & 0xFFFFFFFF)
	for r: Dictionary in rings:
		var tier: String = r.get("tier", "main")
		var count := int(r.get("count", 16))
		var spread: float = RING_SPREAD.get(tier, 0.3)
		var made: Array[Dictionary] = []
		for k in count:
			var phase := float(k) / count * TAU + (rand.next() - 0.5) * 0.22
			var hvar := (rand.next() - 0.5) * 0.14
			var wobble := (rand.next() - 0.5) * spread * 0.42 * UNIT
			var drops: Array = []
			for i in DROPS:
				drops.append({
					"phase": float(i) / DROPS + rand.next() * 0.045,
					"lifetime": (2.5 if tier == "main" else 1.9) + rand.next() * 0.25,
					"drift": (rand.next() - 0.5) * (0.78 if tier == "main" else 0.62) * UNIT * 1.6,
					"tangent": (rand.next() - 0.5) * 0.32 * UNIT * 1.6,
					"size": 0.033 + rand.next() * 0.026,
				})
			made.append({"tier": tier, "phase": phase, "hvar": hvar, "radius": float(r.get("radius", 6.5)) + wobble,
				"base": float(r.get("base_height", 3.0)), "drops": drops, "index": k, "count": count})
		var offset := rand.next() * TAU
		for j: Dictionary in made:
			var angle: float = float(j.index) / float(j.count) * TAU + offset
			j["angle"] = angle
			j["local"] = Vector2(sin(angle), cos(angle)) * float(j.radius)
			out.append(j)
	return out

# ---------------------------------------------------------------- nodes


const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// A camera-facing soft star: the instance colour is the tint, its alpha the brightness.
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float glow = exp(-r2 * 2.2) * (1.0 - smoothstep(0.7, 1.0, r2));
	float core = exp(-r2 * 9.0);
	// a deep colour (crimson, azure) alone is dim against the night: lift it toward its own bright tint
	vec3 tint = clamp(COLOR.rgb * 1.5 + vec3(0.12), 0.0, 1.0);
	ALBEDO = mix(tint, vec3(1.0), core * 0.55);
	ALPHA = clamp(COLOR.a * 2.2 * (glow * 0.8 + core), 0.0, 1.0);
}
"""

const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Spray and foam: a camera-facing soft disc; the instance colour is the water's tint and alpha.
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * h, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	ALBEDO = COLOR.rgb * (1.0 + 0.25 * exp(-r2 * 6.0));
	ALPHA = COLOR.a * exp(-r2 * 2.6) * (1.0 - smoothstep(0.7, 1.0, r2));
}
"""

const JET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
// A jet's water column: brighter at the rims, streaks running up it.
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float streak = 0.82 + 0.18 * sin(UV.x * 37.7 + UV.y * 18.0 + TIME * 9.0);
	ALBEDO = COLOR.rgb * (0.85 + 0.4 * rim) * streak;
	ALPHA = COLOR.a * (0.5 + 0.5 * rim);
}
"""


func _material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _mm_node(mesh: Mesh, count: int, code: String, node_name: String, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = _material(code)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.custom_aabb = aabb
	node.visible = false
	add_child(node)
	return node


func _build_nodes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_fw_node = _mm_node(quad, MAX_SPARKS, SPARK_SHADER, "fireworks",
		AABB(Vector3(-220.0, -5.0, -250.0), Vector3(440.0, 160.0, 500.0)))
	_fw_mm = _fw_node.multimesh
	var col := CylinderMesh.new()
	col.top_radius = 0.045
	col.bottom_radius = 0.11
	col.height = 1.0
	col.radial_segments = 8
	col.rings = 1
	col.cap_top = false
	col.cap_bottom = false
	var faabb := AABB(Vector3(-9.0, -0.5, -9.0), Vector3(18.0, 9.0, 18.0))
	_jet_node = _mm_node(col, _jets.size(), JET_SHADER, "fountain_jets", faabb)
	_jet_mm = _jet_node.multimesh
	var drop := QuadMesh.new()
	drop.size = Vector2.ONE
	_drop_node = _mm_node(drop, _jets.size() * (DROPS + 1), DROP_SHADER, "fountain_spray", faabb)
	_drop_mm = _drop_node.multimesh
	_jet_node.position = fountain_centre
	_drop_node.position = fountain_centre

# ---------------------------------------------------------------- per frame


func _process(_dt: float) -> void:
	if not drive or world == null or not is_visible_in_tree():
		return
	var now := Time.get_ticks_usec() / 1000000.0
	var dt := 0.0 if _last_t < 0.0 else now - _last_t
	_last_t = now
	var t: Dictionary = world.view_time() if world.has_method("view_time") else {"day": 1, "minute": 480.0}
	var cam := get_viewport().get_camera_3d()
	update(int(t.get("day", 1)), float(t.get("minute", 480.0)), dt, cam.global_position if cam else Vector3.INF)


func update(day: int, minute: float, dt: float, eye: Vector3) -> void:
	if not _built:
		return
	var m := fposmod(minute, 1440.0)
	var abs_min := float(maxi(day, 1) - 1) * 1440.0 + m
	var level := Clock.fountain_level_smooth(m)
	var fw_on := m >= Clock.FIREWORKS_FROM and m < Clock.FIREWORKS_TO
	# the event clock: real-paced while the town clock holds or runs fast (see the header)
	if _last_abs < 0.0:
		_offset = 0.0
	else:
		var gap := dt - (abs_min - _last_abs) * SPM
		if absf(gap) > JUMP_SECONDS:
			_offset = 0.0
		else:
			_offset += gap
	_last_abs = abs_min
	if not fw_on and level <= 0.0:
		_offset = 0.0
	_event_seconds = abs_min * SPM + _offset
	var show := 0.0
	var n := 0
	var shells := 0
	if fw_on:
		show = pin_show_seconds if pin_show_seconds >= 0.0 else show_seconds_for(day, _event_seconds)
		var cap := clampi(spark_cap, 0, MAX_SPARKS)
		var r := _compose(show, eye, cap)
		_buf = r[0]
		n = r[1]
		shells = r[2]
		if _buf.size() != MAX_SPARKS * FLOATS:
			_buf.resize(MAX_SPARKS * FLOATS)
		_fw_mm.buffer = _buf
		_fw_mm.visible_instance_count = n
	elif _fw_mm.visible_instance_count != 0:
		_fw_mm.visible_instance_count = 0
	_fw_node.visible = n > 0
	if level > 0.001:
		_fountain(m, _event_seconds, level)
		_jet_node.visible = true
		_drop_node.visible = true
	elif _jet_node.visible or _drop_node.visible:
		_jet_node.visible = false
		_drop_node.visible = false
		_jet_mm.visible_instance_count = 0
		_drop_mm.visible_instance_count = 0
	_status = _make_status(day, m, show, n, shells, level)


## The second of the show for an event time: the clock's show at 1x (thousand_clock.fireworks_state).
static func show_seconds_for(day: int, event_seconds: float) -> float:
	var elapsed := event_seconds - (float(maxi(day, 1) - 1) * 1440.0 + Clock.FIREWORKS_FROM) * SPM
	var show := float(Data.js_round(Clock.js_mod(elapsed, Clock.FIREWORKS_SHOW_SECONDS) * 1e9)) / 1e9
	return 0.0 if show >= Clock.FIREWORKS_SHOW_SECONDS else show


func _make_status(day: int, m: float, show: float, n: int, shells: int, level: float) -> Dictionary:
	var on := m >= Clock.FIREWORKS_FROM and m < Clock.FIREWORKS_TO
	var to_next := 0.0 if on else Clock.js_mod(Clock.FIREWORKS_FROM - m, 1440.0)
	var prog := Clock.fountain_program(m)
	return {
		"fireworks": on, "phase": Clock.fireworks_phase(show) if on else "off", "show_seconds": show if on else 0.0,
		"next_fireworks_minute": Clock.FIREWORKS_FROM, "next_fireworks_day": day if (on or m < Clock.FIREWORKS_FROM) else day + 1,
		"minutes_to_fireworks": to_next, "sparks": n, "shells": shells,
		"fountain": prog, "fountain_level": level, "fountain_show": prog == "show" and level > 0.0,
	}


func status() -> Dictionary:
	return _status.duplicate()


## The pure fireworks frame at a time: the MultiMesh buffer (16 floats a spark), only the drawn sparks.
func sparks_at(day: int, minute: float, show_seconds: float, eye: Vector3, cap := -1) -> PackedFloat32Array:
	var m := fposmod(minute, 1440.0)
	if not _built or m < Clock.FIREWORKS_FROM or m >= Clock.FIREWORKS_TO:
		return PackedFloat32Array()
	var r := _compose(show_seconds, eye, clampi(spark_cap if cap < 0 else cap, 0, MAX_SPARKS))
	var out: PackedFloat32Array = r[0]
	out.resize(int(r[1]) * FLOATS)
	return out


## One shell's whole bloom `since` seconds after its burst, uncapped (tests and the shape review):
## {"shell" (its Shell), "apex" (Vector3), "basis" (the contour basis), "buffer" (16 floats a spark)}.
func shell_frame(index: int, since: float, eye: Vector3) -> Dictionary:
	var s: Shell = _shells[index]
	s.since = since
	s.basis = _basis_for(s.apex, eye, s.tilt) if s.rel else Basis.IDENTITY
	var out := PackedFloat32Array()
	out.resize(s.n * FLOATS)
	var n := 0
	for i in s.n:
		if _spark(out, n, s, i, eye, 0):
			n += 1
	out.resize(n * FLOATS)
	return {"shell": s, "apex": s.apex, "basis": s.basis, "buffer": out}


func shell_count() -> int:
	return _shells.size()


func shell(index: int) -> Shell:
	return _shells[index]


## The shells in the air at a show second (launched, not yet burnt out), in firing order.
func live_shells(show: float) -> Array[Shell]:
	var out: Array[Shell] = []
	for s: Shell in _shells:
		if show >= s.t0 and show < s.end:
			out.append(s)
	return out

# ---------------------------------------------------------------- fireworks


static func _put(out: PackedFloat32Array, i: int, p: Vector3, size: float, c: Color, a: float) -> void:
	var o := i * FLOATS
	out[o] = size
	out[o + 1] = 0.0
	out[o + 2] = 0.0
	out[o + 3] = p.x
	out[o + 4] = 0.0
	out[o + 5] = size
	out[o + 6] = 0.0
	out[o + 7] = p.y
	out[o + 8] = 0.0
	out[o + 9] = 0.0
	out[o + 10] = size
	out[o + 11] = p.z
	out[o + 12] = c.r
	out[o + 13] = c.g
	out[o + 14] = c.b
	out[o + 15] = clampf(a, 0.0, 1.0)


## A cheap seeded hash to [0, 1) (the embers' scatter; upstream seeds a generator per ember).
static func _h01(a: int, b: int) -> float:
	var h := (a * 374761393 + b * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## The basis a contour shape faces the watcher with: right, up, normal (toward the eye, level).
static func _basis_for(apex: Vector3, eye: Vector3, tilt: float) -> Basis:
	var n := Vector3(0.0, 0.0, 1.0)
	if eye.is_finite():
		var to := Vector3(eye.x - apex.x, 0.0, eye.z - apex.z)
		if to.length() > 0.01:
			n = to.normalized()
	var right := (-n).cross(Vector3.UP).normalized() * tilt
	return Basis(right, Vector3.UP, n)


## Composes the frame: [buffer (MAX_SPARKS x 16 floats), drawn count, shells in the air]. The comets,
## embers and burst flashes come first; then the sparks, evenly thinned when they would pass the cap; then
## the trails with whatever is left.
func _compose(show: float, eye: Vector3, cap: int) -> Array:
	var out := PackedFloat32Array()
	out.resize(MAX_SPARKS * FLOATS)
	var live := live_shells(show)
	var n := 0
	var total := 0
	for s: Shell in live:
		var age := show - s.t0
		s.since = age - s.at
		s.basis = _basis_for(s.apex, eye, s.tilt) if s.rel else Basis.IDENTITY
		if age < s.at + EMBER_LIFE:
			n = _comet(out, n, cap, s, age, eye)
		s.alive = 0
		if s.since >= 0.0:
			if s.since < HALO_LIFE and n < cap:
				var u := s.since / HALO_LIFE
				_put(out, n, s.apex, s.halo * (0.55 + 0.9 * u), Color(1, 1, 1).lerp(s.outer, 0.7),
					(0.4 if s.kind == 2 else 0.22) * (1.0 - u) * (1.0 - u))
				n += 1
			var sp := s.sp
			while s.alive < s.n and sp[s.alive * 8 + 4] > s.since:
				s.alive += 1
		total += s.alive
	# the sparks, thinned evenly to the room left
	var take := mini(total, maxi(cap - n, 0))
	if take > 0:
		var li := 0
		var start := 0
		for j in take:
			var g := floori(float(j) * total / take)
			while li < live.size() and g >= start + live[li].alive:
				start += live[li].alive
				li += 1
			if li >= live.size():
				break
			if _spark(out, n, live[li], g - start, eye, 0):
				n += 1
	# the trails with what is left
	if n < cap and take == total:
		for s: Shell in live:
			for tr in range(1, s.trails + 1):
				for i in s.alive:
					if n >= cap:
						break
					if _spark(out, n, s, i, eye, tr):
						n += 1
	return [out, n, live.size()]


## The rising comet and its embers (upstream's townComet).
func _comet(out: PackedFloat32Array, n: int, cap: int, s: Shell, age: float, eye: Vector3) -> int:
	if age < s.at and n < cap:
		var f := flight(age, s.dx, s.v0, s.dz, 1.0)
		var ign := clampf(age / 0.04, 0.0, 1.0)
		var p := s.origin + Vector3(f[0], f[1], f[2]) * UNIT
		_put(out, n, p, _size(1.1 * ign, p, eye), COMET_COLOUR, 0.95 * ign * s.intensity)
		n += 1
	var last := floori(minf(age, s.at - 1e-9) / EMBER_INTERVAL)
	var serial := last
	while serial > 0 and serial > last - EMBERS and n < cap:
		var born := serial * EMBER_INTERVAL
		var e_age := age - born
		if e_age >= 0.0 and e_age < EMBER_LIFE:
			var src := flight(born, s.dx, s.v0, s.dz, 1.0)
			var r0 := _h01(s.ordinal, serial * 3)
			var r1 := _h01(s.ordinal, serial * 3 + 1)
			var r2 := _h01(s.ordinal, serial * 3 + 2)
			var st := flight(e_age, src[3] * 0.24 + (r0 - 0.5) * 2.2, src[4] * 0.24 - 2.0 - r1 * 2.0,
				src[5] * 0.24 + (r2 - 0.5) * 2.2, 2.6)
			var heat := pow(1.0 - e_age / EMBER_LIFE, 1.45)
			var p := s.origin + Vector3(src[0] + st[0], src[1] + st[1], src[2] + st[2]) * UNIT
			_put(out, n, p, _size(0.75 * sqrt(heat), p, eye), COMET_COLOUR, 0.55 * heat * s.intensity)
			n += 1
		serial -= 1
	return n


static func _size(base_m: float, p: Vector3, eye: Vector3) -> float:
	if not eye.is_finite():
		return base_m
	return maxf(base_m, base_m * eye.distance_to(p) * MIN_SPARK_ANGLE / SPARK_M)


## Spark i of a shell (trail 0) or one of its ghost samples (trail 1, 2), at the shell's `since` seconds
## after its burst (upstream's townFlight inlined). Returns false when it is out (burnt, or at the ground).
func _spark(out: PackedFloat32Array, n: int, s: Shell, i: int, eye: Vector3, trail: int) -> bool:
	var t := s.since - TRAIL_LAG * trail
	if t < 0.0:
		return false
	var sp := s.sp
	var o := i * 8
	var life := sp[o + 4]
	if t >= life:
		return false
	var vx := sp[o]
	var vy := sp[o + 1]
	var vz := sp[o + 2]
	if s.rel:
		var b := s.basis
		var w := b.x * vx + b.y * vy + b.z * vz
		vx = w.x
		vy = w.y
		vz = w.z
	vx += s.carry.x
	vy += s.carry.y
	vz += s.carry.z
	var k := sp[o + 3]
	var e := exp(-k * t)
	var f := (1.0 - e) / k
	var gk := GRAVITY / k
	var py := s.apex.y + ((vy + gk) * f - gk * t) * UNIT
	var above := (py - s.origin.y) / UNIT - 1.5
	if above <= 0.0:
		return false
	var p := Vector3(s.apex.x + (WIND_X * t + (vx - WIND_X) * f) * UNIT, py, s.apex.z + (WIND_Z * t + (vz - WIND_Z) * f) * UNIT)
	var ground := minf(above / 8.0, 1.0)
	var burn := clampf((t / life - 0.15) / 0.85, 0.0, 1.0)
	var fade := 1.0 - burn * burn * (3.0 - 2.0 * burn)
	var ph := sp[o + 7]
	var tw := sin(ph * TAU + t * (12.0 + ph * 20.0))
	var bright := fade * (0.2 + 0.4 * tw * tw if s.kind == 2 else 0.72 + 0.28 * tw * tw) * s.intensity * ground
	if bright <= 0.002:
		return false
	var col := s.outer if sp[o + 6] > 0.5 else s.core
	if s.kind == 1:
		col = s.core.lerp(Color(1.0, 0.55, 0.16), minf(t / life, 1.0))
	var size := SPARK_M * s.size * sp[o + 5] * (0.55 + 0.45 * sqrt(fade * ground))
	if t < 0.3:
		# just after the burst every spark is still at the apex: grow in, so they do not add up to a white
		# blob (the burst's flash quad marks the moment)
		var grow := t / 0.3
		size *= 0.35 + 0.65 * grow
		bright *= 0.3 + 0.7 * grow
	if trail > 0:
		bright *= 0.5 if trail == 1 else 0.28
		size *= 0.78 if trail == 1 else 0.62
	# _size and _put written out (unified-r4 bench: two script calls a spark, up to 600 sparks a frame)
	if eye.is_finite():
		size = maxf(size, size * eye.distance_to(p) * MIN_SPARK_ANGLE / SPARK_M)
	var w := n * FLOATS
	out[w] = size
	out[w + 1] = 0.0
	out[w + 2] = 0.0
	out[w + 3] = p.x
	out[w + 4] = 0.0
	out[w + 5] = size
	out[w + 6] = 0.0
	out[w + 7] = p.y
	out[w + 8] = 0.0
	out[w + 9] = 0.0
	out[w + 10] = size
	out[w + 11] = p.z
	out[w + 12] = col.r
	out[w + 13] = col.g
	out[w + 14] = col.b
	out[w + 15] = clampf(bright, 0.0, 1.0)
	return true

# ---------------------------------------------------------------- fountain


## upstream's wave(): three slow breaths, so the ring always has rising and falling jets.
static func wave(seconds: float, phase: float) -> float:
	return 0.68 + 0.17 * sin(seconds * TAU / 9.8 - phase * 2.0) + 0.09 * sin(seconds * TAU / 15.2 + phase) \
		+ 0.06 * sin(seconds * TAU / 4.8 - phase * 3.0)


## The show's pattern 0..1 for a jet: three figures of 24 s each, cross-faded over 2 s: a double wave chasing
## round the ring, the whole ring pulsing together, and the two rings answering each other.
static func show_pattern(seconds: float, angle: float, tier: String) -> float:
	var cycle := fposmod(seconds, 72.0)
	var section := floori(cycle / 24.0)
	var into := cycle - section * 24.0
	var a := _figure(section, seconds, angle, tier)
	if into < 2.0:
		var prev := _figure((section + 2) % 3, seconds, angle, tier)
		var u := Clock.smooth01(into / 2.0)
		return prev * (1.0 - u) + a * u
	return a


static func _figure(section: int, seconds: float, angle: float, tier: String) -> float:
	match section:
		0:
			return pow(0.5 + 0.5 * cos(angle * 2.0 - seconds * TAU / 6.0), 2.0)
		1:
			return 0.15 + 0.85 * pow(0.5 + 0.5 * sin(seconds * TAU / 3.2), 1.5)
	var s := sin(seconds * TAU / 4.0)
	return 0.5 + 0.5 * (s if tier == "main" else -s)


## A jet's height in metres at an event second, level and programme.
func jet_height(j: Dictionary, seconds: float, level: float, show: bool) -> float:
	var base := float(j.base) * (1.0 + float(j.hvar)) * level
	if show:
		return base * (0.3 + 1.0 * show_pattern(seconds, float(j.angle), j.tier))
	return base * wave(seconds, float(j.phase))


## The light a jet is lit with at night: the show's colours chasing round the ring, else the lamps' white.
static func jet_light(seconds: float, angle: float, show: bool) -> Color:
	if not show:
		return LAMP_COLOUR
	var x := fposmod(angle / TAU * SHOW_COLOURS.size() + seconds / 5.0, float(SHOW_COLOURS.size()))
	var i := floori(x)
	var u := Clock.smooth01((x - i - 0.7) / 0.3)
	return (SHOW_COLOURS[i] as Color).lerp(SHOW_COLOURS[(i + 1) % SHOW_COLOURS.size()], u)


func _fountain(m: float, seconds: float, level: float) -> void:
	var show := Clock.fountain_program(m) == "show"
	var day := Clock.daylight(m)
	var lamps := Clock.lamp_level(m)
	var water := Color(0.78, 0.87, 0.95) * (0.32 + 0.68 * day)
	var jb := PackedFloat32Array()
	jb.resize(_jets.size() * FLOATS)
	var db := PackedFloat32Array()
	db.resize(_jets.size() * (DROPS + 1) * FLOATS)
	var dn := 0
	var sy := fountain_surface
	var grow := minf(1.0, level * 2.0)
	if _drop_rows.size() != _jets.size():
		_build_drop_rows()
	for ji in _jets.size():
		var j: Dictionary = _jets[ji]
		var h := jet_height(j, seconds, level, show)
		var lit := jet_light(seconds, float(j.angle), show) * lamps * (1.0 if show else 0.6)
		var c := Color(water.r + lit.r * 0.85, water.g + lit.g * 0.85, water.b + lit.b * 0.85)
		var local: Vector2 = j.local
		var w := (1.0 if j.tier == "main" else 0.8) * (0.85 + 0.15 * level)
		var o := ji * FLOATS
		jb[o] = w
		jb[o + 3] = local.x
		jb[o + 5] = maxf(h, 0.01)
		jb[o + 7] = sy + h * 0.5
		jb[o + 10] = w
		jb[o + 11] = local.y
		jb[o + 12] = c.r
		jb[o + 13] = c.g
		jb[o + 14] = c.b
		jb[o + 15] = 0.62 + 0.2 * lamps
		# the droplets (upstream's appendDroplets): up from the surface to the jet's height, falling outward
		# into the ring of water
		var angle := float(j.angle)
		var rx := sin(angle)
		var rz := cos(angle)
		# (unified-r4 bench: the droplets were most of the fountain's cost, which runs every frame while it plays;
		# the same arithmetic in the same order, with each drop's numbers read from a packed row instead of its
		# dictionary and smooth01 / _put_stretched written out)
		var rows: PackedFloat64Array = _drop_rows[ji]
		var apex := h * 1.05   # upstream keeps the height at the drop's birth; the jet's own is close
		var lx := local.x
		var lz := local.y
		var cr := c.r
		var cg := c.g
		var cb := c.b
		for r in range(0, rows.size(), 5):
			var clock := seconds / rows[r + 1] + rows[r]
			var cycle := floorf(clock)
			var p := clock - cycle
			var rise := 4.0 * p * (1.0 - p)
			var spread := p * p * (3.0 - 2.0 * p)
			var side := sin(p * PI * 0.5)
			var v0 := clampf(p / 0.1, 0.0, 1.0)
			var v1 := clampf((1.0 - p) / 0.16, 0.0, 1.0)
			var vis := v0 * v0 * (3.0 - 2.0 * v0) * (v1 * v1 * (3.0 - 2.0 * v1))
			var size := rows[r + 4] * vis * grow
			var drift := rows[r + 2]
			var tangent := rows[r + 3]
			var q := dn * FLOATS
			db[q] = size
			db[q + 3] = lx + rx * drift * spread + rz * tangent * side
			db[q + 5] = size * (1.3 + 0.6 * absf(1.0 - 2.0 * p))
			db[q + 7] = sy + apex * rise
			db[q + 10] = size
			db[q + 11] = lz + rz * drift * spread - rx * tangent * side
			db[q + 12] = cr
			db[q + 13] = cg
			db[q + 14] = cb
			db[q + 15] = clampf(0.78 * vis, 0.0, 1.0)
			dn += 1
		# foam where the jet meets the water
		var fs := FOAM_M * (0.6 + 0.4 * level) * (1.0 if j.tier == "main" else 0.8)
		_put_stretched(db, dn, Vector3(local.x, sy + 0.12, local.y), fs, fs * 0.55, c, 0.55)
		dn += 1
	_jet_mm.buffer = jb
	_jet_mm.visible_instance_count = _jets.size()
	_drop_mm.buffer = db
	_drop_mm.visible_instance_count = dn


## Each jet's droplets as packed rows of five: phase, lifetime, drift, tangent and DROP_M x (0.75 + 8 x size).
func _build_drop_rows() -> void:
	_drop_rows.clear()
	for j: Dictionary in _jets:
		var rows := PackedFloat64Array()
		for dr: Dictionary in j.drops:
			rows.append_array(PackedFloat64Array([float(dr.phase), float(dr.lifetime), float(dr.drift), float(dr.tangent),
				DROP_M * (0.75 + 8.0 * float(dr.size))]))
		_drop_rows.append(rows)


static func _put_stretched(out: PackedFloat32Array, i: int, p: Vector3, w: float, h: float, c: Color, a: float) -> void:
	var o := i * FLOATS
	out[o] = w
	out[o + 3] = p.x
	out[o + 5] = h
	out[o + 7] = p.y
	out[o + 10] = w
	out[o + 11] = p.z
	out[o + 12] = c.r
	out[o + 13] = c.g
	out[o + 14] = c.b
	out[o + 15] = clampf(a, 0.0, 1.0)


## The jets' heights now (tests): one per jet, in metres.
func jet_heights(minute: float, seconds: float) -> PackedFloat32Array:
	var m := fposmod(minute, 1440.0)
	var level := Clock.fountain_level_smooth(m)
	var show := Clock.fountain_program(m) == "show"
	var out := PackedFloat32Array()
	for j: Dictionary in _jets:
		out.append(jet_height(j, seconds, level, show) if level > 0.001 else 0.0)
	return out


func jet_count() -> int:
	return _jets.size()


## What is drawn now: {"fireworks": instances, "jets": instances, "spray": instances, "nodes_visible": count}.
func drawn() -> Dictionary:
	var vis := 0
	for nd: Node3D in [_fw_node, _jet_node, _drop_node]:
		if nd and nd.visible:
			vis += 1
	return {"fireworks": _fw_mm.visible_instance_count if _fw_node.visible else 0,
		"jets": _jet_mm.visible_instance_count if _jet_node.visible else 0,
		"spray": _drop_mm.visible_instance_count if _drop_node.visible else 0, "nodes_visible": vis}

# ---------------------------------------------------------------- watching


func _walkable(p: Vector2) -> bool:
	var q: Vector2
	if world and world.has_method("resolve_walk"):
		q = world.resolve_walk(p)
	else:
		q = ThousandNav.shared().resolve(p, null)
	return q.distance_to(p) < 0.05


func _ground(p: Vector2) -> float:
	if world and world.has_method("height_at"):
		return float(world.height_at(p))
	return float(ThousandNav.shared().height_at(p))


func _clear(a: Vector3, b: Vector3) -> bool:
	if world == null or not world.has_method("occluders"):
		return true
	for box: AABB in world.occluders():
		if box.intersects_segment(a, b) != null:
			return false
	return true


## A good spot and look target for "fireworks" or "fountain" (see the header). Deterministic; computed once.
func watch_point(kind: String) -> Dictionary:
	if _watch.has(kind):
		return (_watch[kind] as Dictionary).duplicate()
	var r := {}
	match kind:
		"fireworks":
			r = _watch_fireworks()
		"fountain":
			r = _watch_fountain()
		_:
			return {}
	_watch[kind] = r
	return r.duplicate()


## The fireworks: along the canal promenades and the bridges (the open sky of the town), the spot and
## heading that see the most launch sites 75-170 m away, 12-22 degrees up (so watch_camera() keeps the child
## in the frame), within 24 degrees of the heading, not behind a building (nearer sites score a little more).
## The look target is the mean burst point of those sites (45 m up).
func _watch_fireworks() -> Dictionary:
	var cands: Array[Vector2] = []
	var d: Dictionary = ThousandMap.data()
	for pr: Dictionary in d.get("promenade", []):
		var x := float(pr.get("x", 0.0))
		var half := float(pr.get("d", 200.0)) * 0.5 - 6.0
		var z := -half
		while z <= half:
			cands.append(Vector2(x, z + float(pr.get("z", 0.0))))
			z += 6.0
	for b: Dictionary in d.get("bridges", []):
		cands.append(Vector2(float(b.x) + 3.0, float(b.z)))
	var best := {}
	var best_score := -1.0
	for p in cands:
		if not _walkable(p):
			continue
		var y := _ground(p)
		var eye := Vector3(p.x, y + 1.6, p.y)
		var seen := []
		for s: Dictionary in sites:
			var target: Vector3 = s.pos + Vector3(0.0, 45.0, 0.0)
			var hd := Vector2(target.x - p.x, target.z - p.y)
			var dist := hd.length()
			var elev := atan2(target.y - eye.y, dist)
			if dist < 75.0 or dist > 170.0 or elev < deg_to_rad(12.0) or elev > deg_to_rad(22.0):
				continue
			if not _clear(eye, target):
				continue
			seen.append([s, hd.angle(), dist])
		for hi in 72:
			var heading := hi * TAU / 72.0   # Lantern Lane yaw: forward (sin ry, cos ry)
			var fwd_angle := Vector2(sin(heading), cos(heading)).angle()
			var score := 0.0
			var ids: Array = []
			var acc := Vector3.ZERO
			for e: Array in seen:
				var off := absf(angle_difference(fwd_angle, float(e[1])))
				if off <= deg_to_rad(24.0):
					score += 1.0 + 0.2 * (1.0 - off / deg_to_rad(24.0)) + 0.15 * (170.0 - float(e[2])) / 95.0
					ids.append(e[0].id)
					acc += Vector3(e[0].pos) + Vector3(0.0, 45.0, 0.0)
			if score > best_score + 1e-6:
				best_score = score
				var look := acc / maxf(ids.size(), 1)
				best = {"kind": "fireworks", "stand": p, "y": y, "sites": ids, "look_at": look,
					"ry": atan2(look.x - p.x, look.z - p.y)}
	if best.is_empty():
		return {}
	best["camera"] = watch_camera(Vector3(best.stand.x, best.y, best.stand.y), best.look_at)
	return best


## The fountain: a walkable spot 11-14 m from its centre with a clear view of the ring, west of it first
## (the side the station's visitors come from), facing it.
func _watch_fountain() -> Dictionary:
	var c := Vector2(fountain_centre.x, fountain_centre.z)
	var look := fountain_centre + Vector3(0.0, 2.0, 0.0)
	for radius: float in [11.5, 13.0, 10.0, 14.5]:
		for k in 16:
			# west of the centre first, then alternately either side of it
			var a := PI * 1.5 + floorf((k + 1) * 0.5) * TAU / 16.0 * (1.0 if k % 2 == 0 else -1.0)
			var p := c + Vector2(sin(a), cos(a)) * radius
			if not _walkable(p):
				continue
			var y := _ground(p)
			if not _clear(Vector3(p.x, y + 1.6, p.y), look):
				continue
			if not _camera_room(p + (p - c).normalized() * 7.0):
				continue
			var ry := atan2(c.x - p.x, c.y - p.y)
			return {"kind": "fountain", "stand": p, "y": y, "ry": ry, "look_at": look, "sites": [],
				"camera": watch_camera(Vector3(p.x, y, p.y), look, 7.0, 2.6)}
	return {}


## Room for the watch camera at `eye` (ground x, z): open ground within 1.2 m (no lamp post or stall at the lens),
## and away from the market promenades and their stalls, whose lanterns and lamp heads hang over the walk with no
## footprint (lead integration: from the first west spot the camera stood 1.9 m from a promenade lamp head and a
## market lantern, which filled the frame as a flat blue box and a red blob).
func _camera_room(eye: Vector2) -> bool:
	for o: Vector2 in [Vector2.ZERO, Vector2(1.2, 0.0), Vector2(-1.2, 0.0), Vector2(0.0, 1.2), Vector2(0.0, -1.2)]:
		if not _walkable(eye + o):
			return false
	var d: Dictionary = ThousandMap.data()
	for pr: Dictionary in d.get("promenade", []):
		var r := Rect2(float(pr.x) - float(pr.w) * 0.5, float(pr.get("z", 0.0)) - float(pr.d) * 0.5, float(pr.w), float(pr.d))
		if r.grow(8.0).has_point(eye):
			return false
	return true


## A camera behind the child (at `child`, its feet) looking toward `look_at`: `dist` m back and `height` m
## up, pitched up toward the target (a third of the way from the centre to the top of the 42-degree frame)
## but no further than keeps the child's chest inside the bottom of the frame.
static func watch_camera(child: Vector3, look_at: Vector3, dist := 6.0, height := 1.7, fov_deg := 42.0) -> Transform3D:
	var dir := Vector2(look_at.x - child.x, look_at.z - child.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
	var eye := child + Vector3(-dir.x * dist, height, -dir.y * dist)
	var chest := child + Vector3(0.0, 0.9, 0.0)
	var half := deg_to_rad(fov_deg) * 0.5
	var e_t := atan2(look_at.y - eye.y, Vector2(look_at.x - eye.x, look_at.z - eye.z).length())
	var e_c := atan2(chest.y - eye.y, dist)
	var pitch := minf(e_t - 0.35 * half, e_c + 0.88 * half)
	var fwd := Vector3(dir.x * cos(pitch), sin(pitch), dir.y * cos(pitch))
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), eye)
