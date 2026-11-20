## Thousand Town's sky and light (design/thousand-town.md section 9): a procedural sky dome (gradient, twilight
## glow, sun and moon discs, stars) that follows the camera, its own sun and moon lights (the sun's direction
## follows upstream's daily circle), and the TownWorld environment's background, ambient and fog. Values come
## from upstream's light table through core/thousand_clock.gd (sky_state, factors), fitted to Lantern Lane's
## Compatibility renderer and exposure (the town's own sun is 0.8 at noon).
##
## TownWorld owns the WorldEnvironment and the town's sun. While Thousand Town is shown its sun is set dark and
## this node's sun (with the right direction) lights the town; leaving restores both (town_world.gd
## _apply_white_world(false) puts the sun, fog and evening back). The dome, sun and moon are children of the
## Thousand world, so they hide with it.
extends Node3D

const Clock := preload("res://scripts/core/thousand_clock.gd")

const DOME_RADIUS := 480.0
## Section 9 colours (sRGB hex as upstream writes them).
const SUN_DAY := Color("#ffe4c4")
const SUN_LOW := Color("#ffb27a")
const MOON := Color("#8fa7cc")
const SKY_NIGHT := Color("#5f739a")
const SKY_DAY := Color("#c4dbf5")
const GROUND_NIGHT := Color("#1b2431")
const GROUND_DAY := Color("#b6a38a")
const BG_NIGHT := Color("#131c2b")
const BG_DAY := Color("#e9f0f5")
const TWILIGHT := Color("#c98a5e")
const ZENITH_NIGHT := Color("#0a1222")
const ZENITH_DAY := Color("#8fbbe6")
## Upstream's sun energy (4.2 - s) x d x (1 - 0.48 dusk) with s = 0.7, over this, is Lantern Lane's sun energy.
const SUN_FIT := 4.2
const MOON_FIT := 1.25

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 zenith : source_color = vec3(0.5, 0.7, 0.9);
uniform vec3 horizon : source_color = vec3(0.9, 0.94, 0.96);
uniform vec3 below : source_color = vec3(0.6, 0.6, 0.6);
uniform vec3 glow : source_color = vec3(0.8, 0.55, 0.37);
uniform float glow_amount = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.8);
uniform float sun_size = 0.02;
uniform float sun_vis = 1.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_vis = 0.0;
uniform float stars = 0.0;
uniform float space_angle = 0.0;
varying vec3 dir;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	float up = d.y;
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.55, up));
	col = mix(col, below, smoothstep(0.0, -0.08, up));
	float toward_sun = max(dot(d, normalize(sun_dir)), 0.0);
	col += glow * glow_amount * pow(toward_sun, 6.0) * (1.0 - smoothstep(0.0, 0.5, up));
	float sd = acos(clamp(dot(d, normalize(sun_dir)), -1.0, 1.0));
	col = mix(col, sun_col, (1.0 - smoothstep(sun_size * 0.8, sun_size, sd)) * sun_vis * step(-0.02, up));
	float md = acos(clamp(dot(d, normalize(moon_dir)), -1.0, 1.0));
	float disc = 1.0 - smoothstep(0.045, 0.052, md);
	vec3 moon_col = vec3(0.86, 0.9, 0.97) * (0.75 + 0.25 * smoothstep(0.052, 0.0, md));
	col = mix(col, moon_col, disc * moon_vis * step(-0.02, up));
	if (stars > 0.001 && up > 0.0) {
		float c = cos(space_angle);
		float s = sin(space_angle);
		vec3 r = vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
		vec3 cell = floor(r * 380.0);
		float h = hash3(cell);
		float twinkle = step(0.9988, h) * (0.55 + 0.45 * hash3(cell + 3.1));
		col += vec3(twinkle) * stars * smoothstep(0.0, 0.25, up) * (1.0 - disc);
	}
	ALBEDO = col;
}
"""

var dome: MeshInstance3D
var dome_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
## The last frame of light: {daylight, dusk, golden, lamps, windows, background, sun_energy, moon_energy,
## ambient, ambient_energy, sun_direction}.
var frame := {}
var _minute := NAN   # the minute `frame` is for


func _init() -> void:
	name = "Sky"
	dome = MeshInstance3D.new()
	dome.name = "Dome"
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	dome.mesh = sphere
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.ignore_occlusion_culling = true
	dome_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DOME_SHADER
	dome_mat.shader = sh
	dome_mat.render_priority = -100
	dome.material_override = dome_mat
	add_child(dome)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = false
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = MOON
	add_child(moon)


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		dome.global_position = cam.global_position


## A light pointing from `toward` (the direction to the body) down onto the town.
static func _aim(light: DirectionalLight3D, toward: Vector3) -> void:
	var d := toward.normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD
	light.basis = Basis.looking_at(-d, up)


## The light at a fractional minute of the day (add 1440 per day to keep the stars turning). Sets the dome,
## this node's sun and moon, and (when given) the TownWorld's environment and its own sun (set dark).
## The same minute as the last call (a held time) recomputes nothing: the dome, sun and moon keep what they have and
## only the environment and the town's sun are written again (TownWorld's own light code shares them).
func apply(minute: float, env: Environment = null, town_sun: DirectionalLight3D = null) -> Dictionary:
	if minute == _minute and not frame.is_empty():
		_apply_env(env, town_sun)
		return frame
	_minute = minute
	var sky := Clock.sky_state(minute)
	var f := Clock.factors(minute)
	var d := float(sky.daylight)
	var dusk := float(f.dusk)
	var golden := float(sky.golden_hour)
	var low := maxf(dusk, golden)
	var sun_dir: Vector3 = sky.sun_direction
	var moon_dir: Vector3 = sky.moon_direction
	var sun_e := (SUN_FIT - 0.7) * d * (1.0 - 0.48 * dusk) / SUN_FIT * clampf(sun_dir.y * 6.0 + 0.3, 0.0, 1.0)
	var moon_e := 0.20 * (1.0 - d) * float(sky.moon_visibility) * MOON_FIT
	var bg := BG_NIGHT.lerp(BG_DAY, d).lerp(TWILIGHT, float(sky.dusk) * 0.5)
	var sky_amb := SKY_NIGHT.lerp(SKY_DAY, d)
	var ground_amb := GROUND_NIGHT.lerp(GROUND_DAY, d)
	var ambient := sky_amb.lerp(ground_amb, 0.3)
	var ambient_e := lerpf(0.42, 0.62, d)
	# the dome
	dome_mat.set_shader_parameter("zenith", ZENITH_NIGHT.lerp(ZENITH_DAY, d).lerp(Color("#56628f"), float(sky.dusk) * 0.35))
	dome_mat.set_shader_parameter("horizon", bg)
	dome_mat.set_shader_parameter("below", GROUND_NIGHT.lerp(Color("#cfd6d6"), d))
	dome_mat.set_shader_parameter("glow", TWILIGHT.lightened(0.1))
	dome_mat.set_shader_parameter("glow_amount", clampf(float(sky.sunset_blend) + 0.6 * float(sky.low_sun_haze), 0.0, 1.0))
	dome_mat.set_shader_parameter("sun_dir", sun_dir)
	dome_mat.set_shader_parameter("sun_col", SUN_DAY.lerp(SUN_LOW, low).lightened(0.25))
	dome_mat.set_shader_parameter("sun_size", float(sky.sun_radius) * 1.6)
	dome_mat.set_shader_parameter("sun_vis", float(sky.sun_visibility))
	dome_mat.set_shader_parameter("moon_dir", moon_dir)
	dome_mat.set_shader_parameter("moon_vis", float(sky.moon_visibility) * (1.0 - d * 0.7))
	dome_mat.set_shader_parameter("stars", clampf(1.0 - d * 1.6, 0.0, 1.0))
	dome_mat.set_shader_parameter("space_angle", float(sky.space_angle))
	# the lights
	sun.light_color = SUN_DAY.lerp(SUN_LOW, low)
	sun.light_energy = sun_e
	sun.visible = sun_e > 0.001
	if sun_dir.y > -0.2:
		_aim(sun, Vector3(sun_dir.x, maxf(sun_dir.y, 0.05), sun_dir.z))
	moon.light_energy = moon_e
	moon.visible = moon_e > 0.001
	if moon_dir.y > -0.2:
		_aim(moon, Vector3(moon_dir.x, maxf(moon_dir.y, 0.1), moon_dir.z))
	frame = {"daylight": d, "dusk": dusk, "golden": golden, "lamps": float(f.lamps), "windows": float(f.windows),
		"background": bg, "sun_energy": sun_e, "moon_energy": moon_e, "ambient": ambient, "ambient_energy": ambient_e,
		"sun_direction": sun_dir, "moon_direction": moon_dir}
	_apply_env(env, town_sun)
	return frame


func _apply_env(env: Environment, town_sun: DirectionalLight3D) -> void:
	if env:
		var bg: Color = frame.background
		env.background_color = bg
		env.ambient_light_color = frame.ambient
		env.ambient_light_energy = frame.ambient_energy
		env.fog_enabled = float(frame.daylight) < 0.25   # fog in the distance only at night (design section 6)
		env.fog_light_color = bg
		env.adjustment_enabled = false
	if town_sun:
		town_sun.light_energy = 0.0   # this node's sun lights the town with the right direction
