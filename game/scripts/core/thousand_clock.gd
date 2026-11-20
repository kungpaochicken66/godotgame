## Thousand Town: the town clock, daylight and lighting factors, the sun and moon, the event schedules and
## the station loop (design/thousand-town.md, sections 2, 4 and 9). Pure static functions, no nodes.
##
## Ported from "Qianren Xiaozhen (Thousand Town)" by Yihuishi / YiHuiShiBY (github.com/YiHuiShiBY/thousand-town,
## commit 1332ef2, CC BY 4.0): city-life-ext/daily-clock.js and lighting.js, city-materials.js (skyState),
## city-transit-motion.js, and the pure schedule functions of city-fireworks.js, city-fountain.js,
## city-helipad.js and city-airship.js. Changed for Lantern Lane: GDScript, metres and Lantern Lane seconds
## in the wrappers, and English status names. tests/thousand_sim_tests.gd proves parity with fixtures
## produced by upstream's code (scripts/thousand_town/sim_fixtures.mjs).
##
## Units and conversions
##   Length   upstream 1 unit = 0.5 m (UNIT_M). Functions ending in _units return upstream units; the
##            others return metres. Sun and moon positions only matter as directions (upstream puts both on
##            a circle of radius 500 units); axes are upstream's and the game's: east +x, up +y, south +z.
##   Heading  upstream headings are atan2(dz, dx). Lantern Lane's yaw has forward = (sin ry, cos ry) in
##            (x, z), so yaw = PI/2 - heading (yaw_from_heading).
##   Time     the town clock is (day, minute); day 1 is a Monday and a day has 1440 minutes. Lantern Lane
##            runs 1 sim minute per real second at 1x (SECONDS_PER_SIM_MINUTE); upstream ran 0.625 s per
##            sim minute (UPSTREAM_SECONDS_PER_SIM_MINUTE). Everything driven by the minute alone (daylight,
##            lighting factors, window rules, sun, moon, golden hour, fountain level, opening hours) is the
##            same function of the minute in both.
##   Real-time motion   the station loop, the fireworks show, the helicopter and the airship move in real
##            seconds upstream. The game wrappers keep their real-time pace (a bus at 10 units/s = 5 m/s, a
##            360 s lap period, departures 26 s apart, a 96 s show, a 96 s helicopter cycle, a 240 s airship
##            lap) and anchor the timetables to the town clock at Lantern Lane's rate: the buses' first
##            service at 06:00 is 360 Lantern Lane seconds into the day, not upstream's 225. The functions
##            that take `spm` (seconds per sim minute) give upstream's exact numbers with 0.625.
extends RefCounted

const Data := preload("res://scripts/core/thousand_sim_data.gd")

const MINUTES_PER_DAY := 1440
const DAYS_PER_WEEK := 7
## Lantern Lane: real seconds per sim minute at 1x. A day is 24 real minutes.
const SECONDS_PER_SIM_MINUTE := 1.0
## Upstream: real seconds per sim minute at 1x. A day is 900 s. Kept for parity of anything time-scaled.
const UPSTREAM_SECONDS_PER_SIM_MINUTE := 0.625
## Metres per upstream unit.
const UNIT_M := 0.5

## The speeds the Auto mode offers, and where the clock starts and the manual modes hold
## (design/thousand-town.md section 4).
const SPEEDS := [1.0, 2.0, 4.0]
const START_DAY := 1
const START_MINUTE := 480
const DAY_HOLD_MINUTE := 720
const DUSK_HOLD_MINUTE := 1120
const NIGHT_HOLD_MINUTE := 1290

## Day anchors in minutes since midnight (daily-clock.js ANCHORS).
const ANCHORS := {"dawn": 300, "wake": 360, "commute": 420, "workStart": 480, "lunch": 720, "afternoon": 840,
	"offWork": 1020, "dinner": 1140, "sleep": 1320}
## Lamps run 18:30-06:00; daylight rises 05:30-07:00 and falls 18:30-19:30.
const LAMP_ON := 1110
const LAMP_OFF := 360
const SUNRISE := 330
const DUSK_START := 1110
const NIGHT_START := 1170

# ---------------------------------------------------------------- clock


## JavaScript's ((v % n) + n) % n, with the same rounding.
static func js_mod(v: float, n: float) -> float:
	return fmod(fmod(v, n) + n, n)


static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Smoothstep from a to b.
static func smooth(a: float, b: float, x: float) -> float:
	return smooth01((x - a) / (b - a))


## Elapsed real seconds of town time -> whole sim minutes since day 1, 00:00.
static func total_minutes(elapsed_seconds: float, spm: float = SECONDS_PER_SIM_MINUTE) -> int:
	return floori(maxf(0.0, elapsed_seconds) / spm)


static func minute_of_day(elapsed_seconds: float, spm: float = SECONDS_PER_SIM_MINUTE) -> int:
	return posmod(total_minutes(elapsed_seconds, spm), MINUTES_PER_DAY)


## The day number, from 1.
static func day_index(elapsed_seconds: float, spm: float = SECONDS_PER_SIM_MINUTE) -> int:
	@warning_ignore("integer_division")
	return total_minutes(elapsed_seconds, spm) / MINUTES_PER_DAY + 1


## Elapsed real seconds of town time at the start of a (day, minute).
static func seconds_at(day: int, minute: float, spm: float = SECONDS_PER_SIM_MINUTE) -> float:
	return (float(day - 1) * MINUTES_PER_DAY + minute) * spm


## "07:05" for a minute of the day.
static func format_minute(minute: float) -> String:
	var m := posmod(floori(minute), MINUTES_PER_DAY)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [m / 60, m % 60]


## Daylight 0..1: dark before 05:30, full by 07:00, fading from 18:30 to dark at 19:30.
static func daylight(minute: float) -> float:
	var m := js_mod(minute, MINUTES_PER_DAY)
	if m < SUNRISE or m >= NIGHT_START:
		return 0.0
	if m < 420.0:
		return (m - SUNRISE) / (420.0 - SUNRISE)
	if m < DUSK_START:
		return 1.0
	return 1.0 - (m - DUSK_START) / float(NIGHT_START - DUSK_START)


## The lamp hours, 18:30-06:00.
static func is_night(minute: float) -> bool:
	var m := js_mod(minute, MINUTES_PER_DAY)
	return m >= LAMP_ON or m < LAMP_OFF


## (start, end) of a shift window; the index is clamped to 0..2.
static func shift_window(index: int) -> Vector2i:
	return Data.SHIFTS[clampi(index, 0, 2)]


## 0 = Monday ... 6 = Sunday. Day 1 is a Monday.
static func dow(day: int) -> int:
	return posmod((day if day != 0 else 1) - 1, DAYS_PER_WEEK)


## Data.DAY_WEEKDAY, DAY_SATURDAY or DAY_SUNDAY.
static func day_type(day: int) -> int:
	var d := dow(day)
	return d - 4 if d >= 5 else Data.DAY_WEEKDAY


static func is_weekend(day: int) -> bool:
	return dow(day) >= 5


## Which week of the run a day falls in, from 0.
static func week_index(day: int) -> int:
	return floori(float((day if day != 0 else 1) - 1) / DAYS_PER_WEEK)

# ---------------------------------------------------------------- lighting factors (lighting.js)


## Street lamps 0..1: fading out 05:45-06:00 and in 18:30-18:45.
static func lamp_level(minute: float) -> float:
	var m := js_mod(minute, MINUTES_PER_DAY)
	return 1.0 - smooth(345.0, 360.0, m) if m < 720.0 else smooth(1110.0, 1125.0, m)


## The dusk colour 0..1: rising 16:30-18:30, gone by 19:30.
static func dusk_level(minute: float) -> float:
	var m := js_mod(minute, MINUTES_PER_DAY)
	return smooth(990.0, 1110.0, m) * (1.0 - smooth(1140.0, 1170.0, m))


## How much lit windows show 0..1: fading out 06:00-07:00 and in 16:00-17:15.
static func window_level(minute: float) -> float:
	var m := js_mod(minute, MINUTES_PER_DAY)
	return 1.0 - smooth(360.0, 420.0, m) if m < 720.0 else smooth(960.0, 1035.0, m)


## {minute, daylight, lamps, dusk, windows} for a minute (lighting.js factors).
static func factors(minute: float) -> Dictionary:
	var m := js_mod(minute, MINUTES_PER_DAY)
	return {"minute": m, "daylight": daylight(m), "lamps": lamp_level(m), "dusk": dusk_level(m), "windows": window_level(m)}


## The calendar-only opening rule (lighting.js isOpen), used where no occupancy sample is at hand.
static func is_open(policy: int, day: int, minute: float) -> bool:
	var type := day_type(day)
	if policy == Data.POLICY_WEEKDAY:
		return type == Data.DAY_WEEKDAY
	if policy == Data.POLICY_SAT_AM:
		return type == Data.DAY_WEEKDAY or (type == Data.DAY_SATURDAY and minute >= 480.0 and minute < 840.0)
	return true


## A building's stable coin in [0, 1) for the night-owl windows: FNV-1a over its id (lighting.js hashId).
static func owl_coin(id: String) -> float:
	return float(Data.hash32(id, 2166136261) % 1000) / 1000.0


## The window and facade lights of one building at a minute of the day (lighting.js sample).
##   room        the share of window panes lit, 0..0.82
##   max_panes   1 when the building is shut with somebody on duty inside (one lit window), else -1 (no limit)
##   entry       the entrance and stair lights
##   facade      the facade wash
##   decoration  crown and sign lights
## Towers keep a few overtime windows until 23:00 on a day they are open; 38% of housing blocks (by
## owl_coin) keep a few windows 23:00-01:00; nothing is lit that has nobody behind it otherwise.
static func window_rule(kind: String, capacity: int, open: bool, occupied: int, awake: int, minute: float, coin: float) -> Dictionary:
	var m := js_mod(minute, MINUTES_PER_DAY)
	var lamps := lamp_level(m)
	var tower := kind == "tower"
	var duty := not open and occupied > 0
	var denominator := 45.0 if tower else float(maxi(1, capacity))
	var occupied_room := window_level(m) * minf(0.82, maxf(0.035, awake / denominator * 0.85)) if awake > 0 else 0.0
	var overtime := 0.14 * smooth(1075.0, 1105.0, m) * (1.0 - smooth(1365.0, 1395.0, m)) if tower and open else 0.0
	var owl := 0.12 * lamps if kind == "housing" and (m >= 1380.0 or m < 60.0) and coin < 0.38 else 0.0
	var decoration: float
	if tower:
		decoration = lamps * (0.62 if m >= 1110.0 and m < 1415.0 else 0.0)
	else:
		decoration = lamps * (0.5 if m >= 1080.0 and m < 1350.0 else 0.0)
	return {
		"room": maxf(occupied_room, maxf(overtime, owl)),
		"max_panes": 1 if duty else -1,
		"entry": lamps * (0.8 if occupied > 0 or (m < 1350.0 and m >= 1080.0) else 0.3),
		"facade": lamps * (1.0 if m >= 1110.0 and m < (1415.0 if tower else 1350.0) else 0.25),
		"decoration": decoration,
	}


## Is a vehicle of this kind in service at a minute of the day? (lighting.js dispatch)
## Buses and shuttles 06:00-22:30; taxis 06:00-23:00, and taxi 0 all night; police always; other street
## traffic all day, every second one until 23:00, every seventh all night.
static func dispatch(kind: String, ordinal: int, minute: float) -> bool:
	var m := js_mod(minute, MINUTES_PER_DAY)
	if kind == "police":
		return true
	if kind == "bus" or kind == "shuttle":
		return m >= 360.0 and m < 1350.0
	if kind == "taxi":
		return ordinal == 0 or (m >= 360.0 and m < 1380.0)
	return (m >= 360.0 and m < 1200.0) or (m >= 1200.0 and m < 1380.0 and ordinal % 2 == 0) or ordinal % 7 == 0

# ---------------------------------------------------------------- sun, moon and sky (city-materials.js skyState)

## Upstream's sun and moon circle, in upstream units. Positions only matter as directions.
const SKY_RADIUS := 500.0
const SUN_RISE := 330.0
const SUN_UP_MINUTES := 810.0
const SUN_ALTITUDE := 0.78
const MOON_RISE := 1140.0
const MOON_UP_MINUTES := 630.0
const MOON_ALTITUDE := 0.66


## A point of a body's daily circle, in upstream units: up for `visible` minutes from `rise`, reaching
## `altitude` radians above the southern horizon; the hidden half of the circle is continuous too.
static func orbit_units(visual_minute: float, rise: float, visible: float, altitude: float) -> Vector3:
	var elapsed := fmod(visual_minute - rise + 1440.0, 1440.0)
	var angle := PI * elapsed / visible if elapsed <= visible else PI + PI * (elapsed - visible) / (1440.0 - visible)
	return Vector3(SKY_RADIUS * cos(angle), SKY_RADIUS * sin(angle) * sin(altitude), SKY_RADIUS * sin(angle) * cos(altitude))


static func _orbit64(visual_minute: float, rise: float, visible: float, altitude: float) -> PackedFloat64Array:
	var elapsed := fmod(visual_minute - rise + 1440.0, 1440.0)
	var angle := PI * elapsed / visible if elapsed <= visible else PI + PI * (elapsed - visible) / (1440.0 - visible)
	return PackedFloat64Array([SKY_RADIUS * cos(angle), SKY_RADIUS * sin(angle) * sin(altitude), SKY_RADIUS * sin(angle) * cos(altitude)])


static func _unit64(p: PackedFloat64Array) -> PackedFloat64Array:
	var length := sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
	return PackedFloat64Array([p[0] / length, p[1] / length, p[2] / length])


static func _v3(p: PackedFloat64Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])


## The direction to the sun at a (fractional) minute of the day; y is negative below the horizon.
static func sun_direction(minute: float) -> Vector3:
	return _v3(_unit64(_orbit64(js_mod(minute, 1440.0), SUN_RISE, SUN_UP_MINUTES, SUN_ALTITUDE)))


## The direction to the moon: up from 19:00 for 630 minutes.
static func moon_direction(minute: float) -> Vector3:
	return _v3(_unit64(_orbit64(js_mod(minute, 1440.0), MOON_RISE, MOON_UP_MINUTES, MOON_ALTITUDE)))


## Golden hour 0..1: a dawn ramp (05:00-05:35, out by 06:30-08:00) and a sunset ramp (17:00-18:10, out
## by 19:00-19:30).
static func golden_hour(minute: float) -> float:
	var m := js_mod(minute, 1440.0)
	var dawn := smooth(300.0, 335.0, m) * (1.0 - smooth(390.0, 480.0, m))
	var sunset := smooth(1020.0, 1090.0, m) * (1.0 - smooth(1140.0, 1170.0, m))
	return maxf(dawn, sunset)


static func _sky(visual_minute: float, light: float, dusk: float, upstream_seconds: float) -> Dictionary:
	dusk = clampf(dusk, 0.0, 1.0)
	var dawn := smooth(300.0, 335.0, visual_minute) * (1.0 - smooth(390.0, 480.0, visual_minute))
	var sunset := smooth(1020.0, 1090.0, visual_minute) * (1.0 - smooth(1140.0, 1170.0, visual_minute))
	var golden := maxf(dawn, sunset)
	var sun := _orbit64(visual_minute, SUN_RISE, SUN_UP_MINUTES, SUN_ALTITUDE)
	var moon := _orbit64(visual_minute, MOON_RISE, MOON_UP_MINUTES, MOON_ALTITUDE)
	var sun_dir := _unit64(sun)
	var twilight := maxf(0.0, 1.0 - absf(light - 0.28) / 0.28)
	return {
		"daylight": light,
		"night": 1.0 - light,
		"golden_hour": golden,
		"sunset_blend": sunset,
		"cloud_sea": smooth(300.0, 340.0, visual_minute) * (1.0 - smooth(1140.0, 1170.0, visual_minute)),
		"sun_visibility": smooth(305.0, 330.0, visual_minute) * (1.0 - smooth(1140.0, 1170.0, visual_minute)),
		"low_sun_haze": clampf((0.34 - sun_dir[1]) / 0.34, 0.0, 1.0) * golden,
		"sun_radius": lerpf(0.0105, 0.031, golden),
		"moon_radius": 0.052,
		"moon_visibility": smooth(0.0, 0.06, moon[1] / SKY_RADIUS),
		"dusk": maxf(dusk, twilight * 0.5),
		"sun_position_units": _v3(sun),
		"moon_position_units": _v3(moon),
		"sun_direction": _v3(sun_dir),
		"moon_direction": _v3(_unit64(moon)),
		# 64-bit copies of the four vectors above (Vector3 is 32-bit in standard builds).
		"sun_position_units64": sun,
		"moon_position_units64": moon,
		"sun_direction64": sun_dir,
		"moon_direction64": _unit64(moon),
		# The starfield turns once per three town days; the clouds drift with upstream's seconds.
		"space_angle": fmod((upstream_seconds - 1240.0 * 0.625) * PI / 1350.0, TAU),
		"cloud_shift": fmod(upstream_seconds * 0.00012, 1.0),
	}


## Upstream's sky frame for its own clock: `day_seconds` are upstream seconds (0.625 s per sim minute) and
## `dusk` is the lighting factor (dusk_level of the whole minute). Daylight steps by whole minutes while
## the sun and moon move smoothly, exactly as upstream.
static func sky_state_upstream(day_seconds: float, dusk: float) -> Dictionary:
	var seconds := maxf(0.0, day_seconds)
	var minute := minute_of_day(seconds, UPSTREAM_SECONDS_PER_SIM_MINUTE)
	var frame := _sky(fmod(seconds / UPSTREAM_SECONDS_PER_SIM_MINUTE, 1440.0), daylight(minute), dusk, seconds)
	frame["minute"] = minute
	return frame


## The sky frame for the game: `minute` is the fractional minute of the day (add 1440 per day to keep the
## starfield turning across days). Same formulas as upstream; daylight and dusk follow the fractional
## minute, so nothing steps once a second.
static func sky_state(minute: float) -> Dictionary:
	var frame := _sky(js_mod(minute, 1440.0), daylight(minute), dusk_level(minute), maxf(0.0, minute) * UPSTREAM_SECONDS_PER_SIM_MINUTE)
	frame["minute"] = js_mod(minute, 1440.0)
	return frame

# ---------------------------------------------------------------- headings and units


## Lantern Lane's yaw (forward = (sin ry, cos ry) in (x, z)) for an upstream heading (atan2(dz, dx)).
static func yaw_from_heading(heading: float) -> float:
	return PI / 2.0 - heading


## An upstream position (x, y up, z) in metres.
static func to_metres(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * UNIT_M, y * UNIT_M, z * UNIT_M)

# ---------------------------------------------------------------- fireworks (city-fireworks.js)

## The nightly show runs 19:00-22:00 on a 96 s loop: ensemble 0-24 s, weave 24-72, finale 72-94, then a
## 2 s rest. The rooftop searchlights share the window.
const FIREWORKS_FROM := 1140
const FIREWORKS_TO := 1320
const FIREWORKS_SHOW_SECONDS := 96.0
const FIREWORKS_MAX_PARTICLES := 1400
## The eight launch sites in upstream's order (city-fireworks.js SITE_LAYOUT).
const FIREWORK_SITES := ["primary-court", "depot-court", "west-park", "east-park", "sports-field", "amusement-side",
	"university-court", "library-court"]
const FIREWORK_COLORS := ["crimson", "tangerine", "azure", "emerald", "violet", "champagne", "rose"]
const _FW_SITE_ORDER := [0, 5, 2, 7, 1, 4, 3, 6]
const _FW_CLASSICS := ["peony", "chrysanthemum", "willow", "palm", "salute"]
const _FW_ACCENTS := {7: "ring", 11: "fan", 15: "crown", 19: "heart", 20: "thousand", 31: "ring", 35: "fan",
	39: "crown", 43: "star", 44: "like", 55: "ring", 59: "fan", 63: "crown", 67: "spiral", 68: "favorite", 79: "ring",
	83: "fan", 87: "crown", 91: "saturn", 92: "coin", 107: "heart", 111: "crown", 115: "star", 120: "thousand"}
## Upstream's five text and icon bursts are its branding and call-to-action (design/thousand-town.md
## section 0, "Not used"); the game fires a plain shape in their place.
const FIREWORK_GAME_SHAPES := {"thousand": "ring", "like": "heart", "favorite": "star", "coin": "saturn"}
const _FW_GRAVITY := 9.81


## The show's state for elapsed seconds of town time at `spm` seconds per sim minute
## (city-fireworks.js nightlyState): {enabled, minute, day, show_seconds, phase}.
static func fireworks_state_at(seconds: float, spm: float) -> Dictionary:
	if is_nan(seconds) or is_inf(seconds) or seconds < 0.0:
		return {"enabled": false, "minute": 0, "day": 1, "show_seconds": 0.0, "phase": fireworks_phase(0.0)}
	var total := floori(seconds / spm)
	var minute := total % 1440
	@warning_ignore("integer_division")
	var day := total / 1440 + 1
	var elapsed := seconds - (day - 1) * 1440 * spm - FIREWORKS_FROM * spm
	var show := float(Data.js_round(js_mod(elapsed, FIREWORKS_SHOW_SECONDS) * 1e9)) / 1e9
	if show == FIREWORKS_SHOW_SECONDS:
		show = 0.0
	return {"enabled": minute >= FIREWORKS_FROM and minute < FIREWORKS_TO, "minute": minute, "day": day,
		"show_seconds": show, "phase": fireworks_phase(show)}


## Upstream's exact state for its own seconds (0.625 s per sim minute).
static func fireworks_state_upstream(day_seconds: float) -> Dictionary:
	return fireworks_state_at(day_seconds, UPSTREAM_SECONDS_PER_SIM_MINUTE)


## The show for the game's clock: the show plays at its real pace, 96 Lantern Lane seconds per loop,
## starting at 19:00, so at 1x a night holds 1.875 shows (upstream's shorter day held 1.17).
static func fireworks_state(day: int, minute: float) -> Dictionary:
	return fireworks_state_at(seconds_at(day, minute), SECONDS_PER_SIM_MINUTE)


static func fireworks_phase(show_seconds: float) -> String:
	if show_seconds < 24.0:
		return "ensemble"
	if show_seconds < 72.0:
		return "weave"
	return "finale" if show_seconds < 94.0 else "rest"


## The 128 lifts of one show (city-fireworks.js townSchedule), in firing order. Per shell:
##   ordinal, fire_time (s into the show), site (index into FIREWORK_SITES), phase, shape (upstream's name),
##   game_shape (FIREWORK_GAME_SHAPES applied), color (a FIREWORK_COLORS name), apex_units and apex_m (the
##   height of the burst above the launch site), apex_time (s from launch to burst), ascent_velocity_units,
##   drift_units (Vector2: the comet's sideways launch velocity in x and z), intensity, finale.
static func fireworks_schedule(town_seed: int = Data.SEED) -> Array[Dictionary]:
	var rand := Data.Rng.new((town_seed ^ 0x6f13ab79) & 0xFFFFFFFF)
	var times := PackedFloat64Array([0.0])
	var total := 0.0
	for slot in range(1, 128):
		total += (0.69 if slot < 32 else (0.66 if slot < 96 else 0.55)) * (0.64 + rand.next() * 0.72)
		times.append(total)
	var colour_offset := floori(rand.next() * FIREWORK_COLORS.size())
	var shells: Array[Dictionary] = []
	for index in 128:
		var time := float(Data.js_round(times[index] / total * 84.0 * 1e6)) / 1e6
		@warning_ignore("integer_division")
		var block := index / 8
		var phase := "ensemble" if time < 24.0 else ("weave" if time < 72.0 else "finale")
		var height := 100.0 + rand.next() * 23.0
		var shape: String = _FW_ACCENTS.get(index, _FW_CLASSICS[(index * 3 + block) % _FW_CLASSICS.size()])
		# The shell's own draws (city-fireworks.js shell): shape, colour, two for the lateral offset, the
		# side, two for the depth offset, the height (all unused by the town score), then the drift.
		var ordinal := 1200000 + index
		var own := Data.Rng.new((town_seed ^ ((ordinal * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF)
		own.next()
		own.next()
		own.next()
		own.next()
		var sideways := -1.0 if own.next() < 0.5 else 1.0
		own.next()
		own.next()
		own.next()
		var drift_x := sideways * (2.5 + own.next() * 5.0) * 0.25
		var drift_z := (own.next() - 0.5) * 4.0 * 0.25
		# The time and launch speed that reach the apex under drag 1 and gravity 9.81 (townApex).
		var lo := 0.0
		var hi := 6.0
		for i in 42:
			var t := (lo + hi) / 2.0
			if _FW_GRAVITY * (exp(t) - 1.0 - t) < height:
				lo = t
			else:
				hi = t
		var apex_time := (lo + hi) / 2.0
		@warning_ignore("integer_division")
		shells.append({
			"ordinal": ordinal, "fire_time": time, "site": _FW_SITE_ORDER[(index + block * 3) % 8], "phase": phase,
			"shape": shape, "game_shape": FIREWORK_GAME_SHAPES.get(shape, shape),
			"color": FIREWORK_COLORS[(index * 3 + index / 8 + colour_offset) % FIREWORK_COLORS.size()],
			"apex_units": height, "apex_m": height * UNIT_M, "apex_time": apex_time,
			"ascent_velocity_units": _FW_GRAVITY * (exp(apex_time) - 1.0),
			"drift_units": Vector2(drift_x, drift_z),
			"drift_x_units": drift_x, "drift_z_units": drift_z,
			"intensity": 0.86 if phase == "ensemble" else (0.94 if phase == "weave" else 1.0),
			"finale": phase == "finale",
		})
	return shells

# ---------------------------------------------------------------- fountain (city-fountain.js)

## The plaza and canal fountains' day programme: from, to (minutes), pump level 0..1, name.
const FOUNTAIN_PROGRAM := [
	[330, 420, 0.35, "dawn"],
	[420, 1080, 0.45, "daytime"],
	[1080, 1110, 0.6, "dusk-ramp"],
	[1110, 1140, 0.9, "ramp-up"],
	[1140, 1270, 1.0, "show"],
	[1270, 1320, 0.55, "wind-down"],
	[1320, 1440, 0.0, "off"],
	[0, 330, 0.0, "off"],
]
const FOUNTAIN_SMOOTH_WINDOW := 6.0


## The pump level of the whole minute: off 22:00-05:30, full 19:00-21:10.
static func fountain_level(minute: float) -> float:
	var m := posmod(floori(minute), 1440)
	for p: Array in FOUNTAIN_PROGRAM:
		if m >= p[0] and m < p[1]:
			return p[2]
	return 0.0


static func fountain_program(minute: float) -> String:
	var m := posmod(floori(minute), 1440)
	for p: Array in FOUNTAIN_PROGRAM:
		if m >= p[0] and m < p[1]:
			return p[3]
	return "off"


## The pump level with six minutes of easing on each side of a programme change; the pump still stops
## exactly at 22:00 (city-fountain.js dayLevelSmooth).
static func fountain_level_smooth(minute: float) -> float:
	var base := fountain_level(minute)
	if base <= 0.0:
		return 0.0
	var m := js_mod(minute, 1440.0)
	for p: Array in FOUNTAIN_PROGRAM:
		var boundary: float = p[0]
		var before := fountain_level(boundary - 1.0)
		var after: float = p[2]
		if before <= 0.0 or after <= 0.0 or before == after:
			continue
		var distance := js_mod(m - boundary + 720.0, 1440.0) - 720.0
		if absf(distance) >= FOUNTAIN_SMOOTH_WINDOW:
			continue
		return before + (after - before) * ((distance + FOUNTAIN_SMOOTH_WINDOW) / (2.0 * FOUNTAIN_SMOOTH_WINDOW))
	return base

# ---------------------------------------------------------------- helicopter (city-helipad.js)

## One 96 s cycle in real seconds: parked until 22, lift-off 22-30, the circuit 30-72, approach 72-80,
## landed 80-96. Heights and speeds in upstream units.
const HELI_PERIOD := 96.0
const HELI_TAKE_OFF := 22.0
const HELI_AIRBORNE := 30.0
const HELI_HOMECOMING := 72.0
const HELI_TOUCHDOWN := 80.0
const HELI_LIFT := 10.0
const HELI_CRUISE := 150.0
const HELI_IDLE_SPIN := 12.0
const HELI_FLIGHT_SPIN := 1.5
const HELI_ROTOR_UNITS := 5.2
const _HELI_BANK := 2.6
const _HELI_MAX_BANK := 0.42
const _HELI_PITCH := -0.012
const _HELI_MAX_PITCH := 0.16
const _HELI_CYCLE_TURNS := HELI_TAKE_OFF / HELI_IDLE_SPIN + (HELI_TOUCHDOWN - HELI_TAKE_OFF) / HELI_FLIGHT_SPIN \
	+ (HELI_PERIOD - HELI_TOUCHDOWN) / HELI_IDLE_SPIN


## The helipad and circuit for the tower it stands on (city-helipad.js plan), in upstream units: the
## tower's centre, storeys and footprint. Upstream picks the tallest ordinary tower (b-3-0, "t-one").
static func helipad_plan_units(tower_x: float, tower_z: float, floors: int, w: float, d: float) -> Dictionary:
	var roof_y := floors * 6.0 + 1.4
	var span := sqrt(tower_x * tower_x + tower_z * tower_z)
	if span == 0.0:
		span = 1.0
	var ux := -tower_x / span
	var uz := -tower_z / span
	return {"x": tower_x, "z": tower_z, "roof_y": roof_y, "radius": minf(8.0, minf(w, d) / 2.0 - 1.0),
		"cruise": maxf(HELI_CRUISE, roof_y + 20.0), "cx": tower_x * 0.5, "cz": tower_z * 0.5, "a": span * 0.5,
		"b": span * 0.5 * 0.62, "ux": ux, "uz": uz, "vx": -uz, "vz": ux}


## The helicopter at a real time in seconds (city-helipad.js sample), in upstream units:
## {phase, x, y, z, heading, bank, pitch, rotor (radians), rotor_turns, parked, grounded}.
## Phases: "parked", "take-off", "circuit", "approach", "shutdown".
static func helicopter_units(plan: Dictionary, time: float) -> Dictionary:
	var moment := maxf(0.0, time)
	var at := fmod(moment, HELI_PERIOD)
	var parked_heading := atan2(-plan["vz"], -plan["vx"])
	var roof: float = plan["roof_y"]
	var s := {"phase": "", "x": plan["x"], "y": roof, "z": plan["z"], "heading": parked_heading, "bank": 0.0, "pitch": 0.0,
		"rotor": 0.0, "rotor_turns": 0.0, "parked": false, "grounded": false}
	if at < HELI_TAKE_OFF or at >= HELI_TOUCHDOWN:
		s["phase"] = "parked" if at < HELI_TAKE_OFF else "shutdown"
		s["parked"] = true
		s["grounded"] = true
	elif at < HELI_AIRBORNE:
		s["phase"] = "take-off"
		s["y"] = roof + HELI_LIFT * smooth01((at - HELI_TAKE_OFF) / (HELI_AIRBORNE - HELI_TAKE_OFF))
	elif at < HELI_HOMECOMING:
		var p := (at - HELI_AIRBORNE) / (HELI_HOMECOMING - HELI_AIRBORNE)
		var phi := PI + TAU * p
		var cosine := cos(phi)
		var sine := sin(phi)
		var a: float = plan["a"]
		var b: float = plan["b"]
		var ux: float = plan["ux"]
		var uz: float = plan["uz"]
		var vx: float = plan["vx"]
		var vz: float = plan["vz"]
		s["phase"] = "circuit"
		s["x"] = plan["cx"] + a * cosine * ux + b * sine * vx
		s["z"] = plan["cz"] + a * cosine * uz + b * sine * vz
		s["y"] = roof + HELI_LIFT + (plan["cruise"] - roof - HELI_LIFT) * sin(PI * p) * sin(PI * p)
		var fx := -a * sine * ux + b * cosine * vx
		var fz := -a * sine * uz + b * cosine * vz
		var gx := -a * cosine * ux - b * sine * vx
		var gz := -a * cosine * uz - b * sine * vz
		var rate := TAU / (HELI_HOMECOMING - HELI_AIRBORNE)
		var ramp := smooth01(p / 0.14) * smooth01((1.0 - p) / 0.14)
		s["heading"] = atan2(fz, fx)
		s["bank"] = clampf(_HELI_BANK * (fx * gz - fz * gx) / (fx * fx + fz * fz) * rate, -_HELI_MAX_BANK, _HELI_MAX_BANK) * ramp
		s["pitch"] = clampf(_HELI_PITCH * sqrt(fx * fx + fz * fz) * rate, -_HELI_MAX_PITCH, _HELI_MAX_PITCH)
	else:
		s["phase"] = "approach"
		s["y"] = roof + HELI_LIFT * (1.0 - smooth01((at - HELI_HOMECOMING) / (HELI_TOUCHDOWN - HELI_HOMECOMING)))
		s["grounded"] = s["y"] <= roof + 1e-9
	var turns := floorf(moment / HELI_PERIOD) * _HELI_CYCLE_TURNS
	if at <= HELI_TAKE_OFF:
		turns += at / HELI_IDLE_SPIN
	else:
		turns += HELI_TAKE_OFF / HELI_IDLE_SPIN
		if at <= HELI_TOUCHDOWN:
			turns += (at - HELI_TAKE_OFF) / HELI_FLIGHT_SPIN
		else:
			turns += (HELI_TOUCHDOWN - HELI_TAKE_OFF) / HELI_FLIGHT_SPIN + (at - HELI_TOUCHDOWN) / HELI_IDLE_SPIN
	s["rotor_turns"] = turns
	s["rotor"] = fmod(turns, 1.0) * TAU
	return s


## The helicopter for the game: {phase, pos (metres), yaw, bank, pitch, rotor, parked, grounded}.
static func helicopter(plan: Dictionary, time: float) -> Dictionary:
	var s := helicopter_units(plan, time)
	return {"phase": s["phase"], "pos": to_metres(s["x"], s["y"], s["z"]), "yaw": yaw_from_heading(s["heading"]),
		"bank": s["bank"], "pitch": s["pitch"], "rotor": s["rotor"], "parked": s["parked"], "grounded": s["grounded"]}

# ---------------------------------------------------------------- airship (city-airship.js)

const AIRSHIP_PERIOD := 240.0


## The airship's ellipse (city-airship.js plan), in upstream units: the board's half extents (190 and 258
## in the default town) and the tallest roof (storeys * 6 + 22, or a landmark's height).
static func airship_plan_units(extent_x: float = 190.0, extent_z: float = 258.0, roof: float = 148.0) -> Dictionary:
	return {"rx": maxf(70.0, extent_x * 0.71), "rz": maxf(90.0, extent_z * 0.64), "altitude": maxf(150.0, roof) + 64.0,
		"period": AIRSHIP_PERIOD}


## The airship at a real time in seconds (city-airship.js sample), in upstream units:
## {x, y, z, heading, bank, pulse}. One lap of the ellipse takes 240 s.
static func airship_units(plan: Dictionary, time: float) -> Dictionary:
	var t := maxf(0.0, time)
	var period: float = plan["period"]
	var a := fmod(t, period) / period * TAU + 0.65
	return {"x": cos(a) * plan["rx"], "z": sin(a) * plan["rz"], "y": plan["altitude"] + sin(a * 2.0) * 2.0,
		"heading": atan2(plan["rz"] * cos(a), -plan["rx"] * sin(a)), "bank": sin(a) * 0.025, "pulse": 0.88 + 0.12 * sin(a * 8.0)}


## The airship for the game: {pos (metres), yaw, bank, pulse}.
static func airship(plan: Dictionary, time: float) -> Dictionary:
	var s := airship_units(plan, time)
	return {"pos": to_metres(s["x"], s["y"], s["z"]), "yaw": yaw_from_heading(s["heading"]), "bank": s["bank"], "pulse": s["pulse"]}

# ---------------------------------------------------------------- station loop (city-transit-motion.js)

## Three buses and four taxis share one loop from the station: out by the south exit, around the east
## bank's ring and back by the north entrance.
const TRANSIT_SPEED_UNITS := 10.0
const TRANSIT_SPEED := TRANSIT_SPEED_UNITS * UNIT_M
## A vehicle leaves every `TRANSIT_PERIOD` seconds; the bays leave `TRANSIT_HEADWAY` apart, the first 5 s
## after the timetable opens; after a lap a vehicle is serviced for 24 s.
const TRANSIT_PERIOD := 360.0
const TRANSIT_HEADWAY := 26.0
const TRANSIT_SERVICE_SECONDS := 24.0
const TRANSIT_BUS_FROM := 360
const TRANSIT_BUS_TO := 1350
## Bay positions relative to the station (x, z in upstream units) and whether the bay is a bus bay.
const TRANSIT_SLOTS := [[-17.0, -7.0, true], [-5.0, -7.0, true], [7.0, -7.0, true], [-18.0, 18.0, false],
	[-8.0, 18.0, false], [2.0, 18.0, false], [12.0, 18.0, false]]
## Statuses. Upstream's Chinese texts, in order: waiting at the bay, out of service, leaving the station,
## returning to it, in service on the loop, being serviced after a lap.
enum { TRANSIT_WAITING, TRANSIT_CLOSED, TRANSIT_DEPARTING, TRANSIT_RETURNING, TRANSIT_RUNNING, TRANSIT_SERVICING }
const TRANSIT_STATUS := ["waiting", "closed", "departing", "returning", "running", "servicing"]
## The canal bridges the loop crosses rise 1.7 units at z = -80 and z = 80.
const _TRANSIT_BRIDGES := [-80.0, 80.0]


## A polyline with its corners rounded (radius up to 2.2 units, ten steps each), as packed segments:
## {seg: PackedFloat64Array of [ax, az, bx, bz, start, length] per segment, count, length}.
static func transit_route_units(points: Array) -> Dictionary:
	var xs := PackedFloat64Array([points[0][0]])
	var zs := PackedFloat64Array([points[0][1]])
	for i in range(1, points.size() - 1):
		var ax: float = points[i - 1][0]
		var az: float = points[i - 1][1]
		var bx: float = points[i][0]
		var bz: float = points[i][1]
		var cx: float = points[i + 1][0]
		var cz: float = points[i + 1][1]
		var ab := sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az))
		var bc := sqrt((cx - bx) * (cx - bx) + (cz - bz) * (cz - bz))
		var radius := minf(2.2, minf(ab * 0.3, bc * 0.3))
		var px := bx + (ax - bx) * radius / ab
		var pz := bz + (az - bz) * radius / ab
		var qx := bx + (cx - bx) * radius / bc
		var qz := bz + (cz - bz) * radius / bc
		xs.append(px)
		zs.append(pz)
		for j in range(1, 11):
			var t := j / 10.0
			var u := 1.0 - t
			xs.append(u * u * px + 2.0 * u * t * bx + t * t * qx)
			zs.append(u * u * pz + 2.0 * u * t * bz + t * t * qz)
	xs.append(points[points.size() - 1][0])
	zs.append(points[points.size() - 1][1])
	var seg := PackedFloat64Array()
	var length := 0.0
	for i in range(1, xs.size()):
		var d := sqrt((xs[i] - xs[i - 1]) * (xs[i] - xs[i - 1]) + (zs[i] - zs[i - 1]) * (zs[i] - zs[i - 1]))
		if d > 1e-8:
			seg.append_array(PackedFloat64Array([xs[i - 1], zs[i - 1], xs[i], zs[i], length, d]))
			length += d
	@warning_ignore("integer_division")
	return {"seg": seg, "count": seg.size() / 6, "length": length}


## The station loop for a station at (site_x, site_z) in upstream units (city-transit-motion.js create).
## `gate_side` is the station's gateSide (1 or -1), or 0 to derive it from the bank the station is on.
## The default town's station is at (-132, 40) with gate side 1.
static func transit_plan_units(site_x: float = -132.0, site_z: float = 40.0, gate_side: int = 1) -> Dictionary:
	var side := gate_side if gate_side != 0 else (1 if site_x < 0.0 else -1)
	var wz := side * site_z
	var vehicles: Array[Dictionary] = []
	for index in TRANSIT_SLOTS.size():
		var x: float = TRANSIT_SLOTS[index][0]
		var z: float = TRANSIT_SLOTS[index][1]
		var bus: bool = TRANSIT_SLOTS[index][2]
		var path := transit_route_units([[x, z], [x, 4.0], [21.0, 4.0], [21.0, 13.0], [33.6, 13.0],
			[33.6, 150.0 - wz], [38.4, 150.0 - wz], [38.4, -77.6 - wz], [225.6, -77.6 - wz], [225.6, 77.6 - wz],
			[38.4, 77.6 - wz], [38.4, -150.0 - wz], [33.6, -150.0 - wz], [33.6, -13.0], [21.0, -13.0], [21.0, 4.0],
			[x, 4.0], [x, z]])
		vehicles.append({"id": ("station-bus-%d" % index) if bus else ("station-taxi-%d" % (index - 3)), "x": x, "z": z,
			"bus": bus, "index": index, "ordinal": index if bus else index - 3, "path": path,
			"departure": 5.0 + index * TRANSIT_HEADWAY})
	return {"site_x": site_x, "site_z": site_z, "side": side, "vehicles": vehicles}


## Every station vehicle at `day_seconds` of town time running at `spm` seconds per sim minute
## (city-transit-motion.js sample, daily mode), in upstream units. With spm = 0.625 this is upstream
## exactly. Per vehicle: {id, bus, x, y, z (world), local_x, local_z (relative to the station), heading,
## local_heading, status (TRANSIT_*), moving}.
static func transit_at_units(plan: Dictionary, day_seconds: float, spm: float) -> Array[Dictionary]:
	var time := maxf(0.0, day_seconds)
	var day_length := MINUTES_PER_DAY * spm
	var side: int = plan["side"]
	var out: Array[Dictionary] = []
	for v: Dictionary in plan["vehicles"]:
		var path: Dictionary = v["path"]
		var length: float = path["length"]
		var bus: bool = v["bus"]
		var kind := "bus" if bus else "taxi"
		var ordinal: int = v["ordinal"]
		var driving := length / TRANSIT_SPEED_UNITS
		var phase := js_mod(time - v["departure"], TRANSIT_PERIOD)
		var admitted: bool
		if bus:
			# Each day's first service is anchored at 06:00; a departure of the day before may still be out.
			var day := floori(time / day_length)
			var departure := -INF
			for d in [day - 1, day]:
				var start: float = d * day_length + TRANSIT_BUS_FROM * spm + v["departure"]
				while start < d * day_length + TRANSIT_BUS_TO * spm:
					if start <= time:
						departure = maxf(departure, start)
					start += TRANSIT_PERIOD
			phase = time - departure
			admitted = departure != -INF and dispatch(kind, ordinal, (time - phase) / spm)
		else:
			admitted = dispatch(kind, ordinal, (time - phase) / spm)
		var operating := dispatch(kind, ordinal, time / spm)
		var x: float = v["x"]
		var z: float = v["z"]
		var heading := -PI / 2.0
		var status := TRANSIT_WAITING if operating else TRANSIT_CLOSED
		var moving := false
		if admitted and phase < driving:
			moving = true
			var distance := phase * TRANSIT_SPEED_UNITS
			var seg: PackedFloat64Array = path["seg"]
			var count: int = path["count"]
			var at := (count - 1) * 6
			for i in count:
				if distance < seg[i * 6 + 4] + seg[i * 6 + 5]:
					at = i * 6
					break
			var t := minf(1.0, (distance - seg[at + 4]) / seg[at + 5])
			x = seg[at] + (seg[at + 2] - seg[at]) * t
			z = seg[at + 1] + (seg[at + 3] - seg[at + 1]) * t
			heading = atan2(seg[at + 3] - seg[at + 1], seg[at + 2] - seg[at])
			if bus and distance < 11.0:
				heading -= PI
			if not bus and distance > length - 14.0:
				heading -= PI
			if x < 29.0:
				status = TRANSIT_DEPARTING if distance < length / 2.0 else TRANSIT_RETURNING
			else:
				status = TRANSIT_RUNNING
		elif operating and admitted and phase < driving + TRANSIT_SERVICE_SECONDS:
			status = TRANSIT_SERVICING
		var wx: float = plan["site_x"] + side * x
		var wz: float = plan["site_z"] + side * z
		var rise := 0.0
		for bz: float in _TRANSIT_BRIDGES:
			rise = maxf(rise, smooth01((33.0 - absf(wx)) / 10.0) * smooth01((11.5 - absf(wz - bz)) / 4.0))
		out.append({"id": v["id"], "bus": bus, "x": wx, "y": 1.7 * rise, "z": wz, "local_x": x, "local_z": z,
			"heading": heading + (PI if side < 0 else 0.0), "local_heading": heading, "status": status, "moving": moving})
	return out


## Upstream's exact fleet for its own seconds (0.625 s per sim minute).
static func transit_upstream(plan: Dictionary, day_seconds: float) -> Array[Dictionary]:
	return transit_at_units(plan, day_seconds, UPSTREAM_SECONDS_PER_SIM_MINUTE)


## The fleet for the game at `day_seconds` Lantern Lane seconds of town time (seconds_at(day, minute)).
## Per vehicle: {id, bus, pos (metres), yaw, status (TRANSIT_*), moving}.
## By default the vehicles keep upstream's real-time pace (5 m/s, a departure per vehicle every 360 s) on a
## timetable anchored to the town clock. With `sim_locked` every vehicle is where upstream has it at the
## same sim minute instead, which is 0.625 times slower in Lantern Lane's seconds (3.125 m/s).
static func transit(plan: Dictionary, day_seconds: float, sim_locked: bool = false) -> Array[Dictionary]:
	var fleet: Array[Dictionary]
	if sim_locked:
		fleet = transit_at_units(plan, day_seconds * UPSTREAM_SECONDS_PER_SIM_MINUTE / SECONDS_PER_SIM_MINUTE, UPSTREAM_SECONDS_PER_SIM_MINUTE)
	else:
		fleet = transit_at_units(plan, day_seconds, SECONDS_PER_SIM_MINUTE)
	var out: Array[Dictionary] = []
	for v in fleet:
		out.append({"id": v["id"], "bus": v["bus"], "pos": to_metres(v["x"], v["y"], v["z"]),
			"yaw": yaw_from_heading(v["heading"]), "status": v["status"], "moving": v["moving"]})
	return out
