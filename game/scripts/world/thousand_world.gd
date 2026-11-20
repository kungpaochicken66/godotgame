## Thousand Town's world (design/thousand-town.md sections 2, 6, 8 and 9): the native Godot town built from the
## route C data in res://thousand_town/data/ (adapted from "Qianren Xiaozhen (Thousand Town)" by Yihuishi /
## YiHuiShiBY, CC BY 4.0; see that folder's README.md, "What the Godot world builder must do").
##
## What build() makes, once:
##   - the seven world layer GLBs (world_*.glb), read at run time with GLTFDocument. Every glTF material is
##     replaced by name (tt_matte, tt_paint, tt_metal, tt_glass, tt_lamp, tt_window, tt_sign) with one small
##     shader that takes the linear vertex colour as albedo. Static chunk nodes (suffix _c<ix>_<iz>, in any
##     file) are merged per cell, layer and material; the visibility ranges of world.json apply per node.
##   - from W-DATA's town.json and GLBs: the four office towers (district.glb floor and roof modules as
##     MultiMeshes, tinted per tower, with their office parts), the frontage (compound walls, railings,
##     hedges, gates and shop rings, as box MultiMeshes per cell), the civic entry modules, the plaza
##     monument, benches and planters, the carousel and the teacups, and the helipad.
##   - water: the canal (y -0.275) and the plaza fountain's ring basin; the canal fountain's 116 droplets.
##   - light: lamps, signs and market lanterns glow by the town clock's lamp factor; window panes are lit
##     building by building from thousand_sim's occupancy sample (a pane is lit when its rank, UV.x, is
##     below the building's light level; the rest are discarded); the towers light whole floors; 4 real
##     OmniLight3Ds sit on the omni candidate lamps nearest the camera; light pools on the ground.
##   - motion: the ferris wheel (180 s a turn), the carousel and teacups, the doors (by the building's
##     door-open value), the market awnings (a flutter in the shader), the balloons, the fountain.
##   - the sky (world/thousand_sky.gd): dome, sun, moon, ambient, background, fog by night.
## The town's occupancy is sampled at most every LIGHT_STEP sim minutes, not every frame; a new day's plans
## are built a few residents per frame.
##
## API (metres; positions on the ground are Vector2(x, z); y is up; north is -z, east +x). The integration
## (town_world.gd, play_controller.gd, camera_rig.gd, hud.gd) calls nothing else:
##   setup(town_world: Node3D)          the TownWorld that owns this node (its WorldEnvironment and sun light the
##                                      town; set_time changes them while the town is on screen)
##   build(root: Node3D = null)          builds the town's nodes under `root` (default: this node). Idempotent.
##   view_time() -> Dictionary          {"day", "minute", "mode", "speed"}: the clock to draw. Thousand.est_clock()
##                                      unless `clock` (a Callable returning that Dictionary) is set (tests, tours).
##   set_time(day: int, minute: float)  the light for that time: sun, moon, ambient, background, lamps, windows
##                                      (design section 9). TownWorld calls it every frame with view_time().
##   resolve_walk(pos, from = null) -> Vector2
##                                      the walkable point for a step to `pos` (core/thousand_nav.gd): inside the
##                                      board, out of the water except on the bridges, out of every footprint.
##                                      With `from` (the point the step started at) a blocked step slides along
##                                      the edge or stays; without it the point is pushed out.
##   height_at(pos: Vector2) -> float  the ground height under a walkable point (bridges, platforms, yards, steps)
##   arrival(slot := 0) -> Transform3D where the tram leaves a child (the station forecourt), facing east (+x)
##   building_at(pos: Vector2) -> Dictionary
##                                      the building (or place) whose ground holds `pos`: {"id" (thousand_sim's
##                                      ledger id, e.g. "h-terrace"), "map_id" (town.json's), "sim" (ledger
##                                      index), "name" (English, translated by the catalogs), "kind" ("building"
##                                      | "place"), "rect" (Rect2), "door" (Vector2, or null for a place without
##                                      one), "floors"}; {} for none
##   door_near(pos: Vector2, r: float) -> Dictionary
##                                      the same for the building whose door is nearest `pos` within r m; {} for none
##   occluders() -> Array               AABBs (world space) the follow camera keeps out of; the index is the id
##   set_occluded(ids: Array)           the occluders still between the camera and the child: drawn dithered
##                                      (a screen-door pattern inside those boxes). The camera calls it whenever
##                                      the set changes.
## Extras for the lead's integration (residents, transit, the inspect panel): `sim` and plans() (the shared
## ThousandSim and today's plans), town_sample() (the last occupancy sample), vehicle_template(kind),
## stats() (what was built and how long it took); for the interactions (world/thousand_play.gd) ensure_plans(day)
## (today's plans at once, behind the journey card), cabin_global(k), wheel_frame(), cabin_count(), and anim_offset
## (seconds added to the animation clock; tests turn the wheel with it).
extends Node3D

const Places := preload("res://scripts/core/places.gd")
const ThousandMap := preload("res://scripts/core/thousand_map.gd")
const ThousandNav := preload("res://scripts/core/thousand_nav.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")
const Sim := preload("res://scripts/core/thousand_sim.gd")
const SkyScript := preload("res://scripts/world/thousand_sky.gd")

const DATA := ThousandMap.DATA_DIR
const BOARD := ThousandMap.HALF            # half extents (Places.THOUSAND_HALF)
const CANAL_HALF := ThousandMap.CANAL_HALF
const STOREY := ThousandMap.STOREY
const PLINTH := ThousandMap.PLINTH
const DOOR_H := ThousandMap.DOOR_HEIGHT
const BODY := ThousandNav.BODY
## Where a child walks back into the station to ride home (the station's west half, by the waiting platform).
const STATION_TRAVEL := Vector2(-74.0, 20.0)
const WORLD_FILES := ["world_ground", "world_facilities", "world_housing", "world_station", "world_landmarks",
	"world_market", "world_signs"]
## Chunk cells (world.json godot.chunks): x cuts -48, 0, 48 m; z cuts -64.5, 0, 64.5 m.
const CUTS_X := [-48.0, 0.0, 48.0]
const CUTS_Z := [-64.5, 0.0, 64.5]
## town.json building ids -> thousand_sim's ledger ids (upstream's resident.js bindings; the annexes, the
## street office and the places use their ledger ids already).
const SIM_IDS := {
	"b-0-0": "c-primary", "b-1-0": "i-workshop", "b-2-0": "i-depot", "b-3-0": "t-one", "b-5-0": "t-two",
	"b-6-0": "t-three", "b-7-0": "c-hospital", "b-8-0": "h-courtyard", "b-9-0": "t-four", "b-10-0": "h-slab",
	"b-13-0": "h-terrace", "b-14-0": "c-mall", "b-15-0": "h-point", "b-17-0": "c-secondary",
	"b-20-0": "c-university", "b-21-0": "i-market", "b-22-0": "c-library", "b-23-0": "c-annex-mall",
}
## The English names the six catalogs translate, by ledger id (town.json name_en otherwise).
const NAMES := {
	"c-primary": "Primary School", "i-workshop": "Workshop", "i-depot": "Depot", "t-one": "Tower One",
	"t-two": "Tower Two", "t-three": "Tower Three", "t-four": "Tower Four", "c-hospital": "Hospital",
	"h-courtyard": "Courtyard Housing", "h-slab": "Slab Housing", "h-terrace": "Terrace Housing", "c-mall": "Mall",
	"h-point": "Point Housing", "c-secondary": "Secondary School", "c-university": "University",
	"i-market": "Wholesale Market", "c-library": "Library", "c-annex-mall": "Annex Mall", "i-clinic-a": "Clinic",
	"i-clinic-b": "Clinic", "i-clinic-c": "Clinic", "c-precinct": "Police Post", "c-bank": "Bank",
	"c-civic": "Street Office", "c-station": "Station", "c-amusement": "Amusement Park", "c-plaza": "Plaza",
	"c-park-a": "Park", "c-park-b": "Park", "sports": "Sports Ground", "c-night-market": "Night Market",
	"i-waste": "Waste Station",
}
## The placeholder's building names, kept as aliases (older tests and tours use them).
const BUILDINGS := {
	"primary_school": "c-primary", "workshop": "i-workshop", "depot": "i-depot", "tower_one": "t-one",
	"tower_two": "t-two", "tower_three": "t-three", "hospital": "c-hospital", "courtyard_housing": "h-courtyard",
	"tower_four": "t-four", "slab_housing": "h-slab", "terrace_housing": "h-terrace", "mall": "c-mall",
	"point_housing": "h-point", "secondary_school": "c-secondary", "university": "c-university",
	"wholesale_market": "i-market", "library": "c-library", "annex_mall": "c-annex-mall",
}
## Sim minutes between two occupancy samples (windows, doors, the market's lanterns).
const LIGHT_STEP := 0.5
## Residents planned per frame while a new day's plans are built.
const PLAN_BATCH := 120
const OMNI_COUNT := 4
const OMNI_EVERY := 0.25
const OMNI_ENERGY := 1.4
## Emission of the glowing groups at full lamp factor (fitted to the Compatibility renderer's exposure).
const LAMP_GLOW := 1.6
const SIGN_GLOW := 0.35 * 1.6
const WINDOW_GLOW := 1.25
const MARKET_BUSY := 2.6 * 0.75
const MARKET_IDLE := 0.12
const TOWER_GLOW := Color("#ffd69a")
## Frontage roles that glow at night (the shops' lit panels); every other role is drawn as paint.
const LIT_ROLES := ["shoplit"]
const SHEET_ROLES := ["sign", "plaque", "board"]
## The x-ray works for a follow camera up to this far from the child (not for the overview).
const XRAY_MAX := 22.0
## How far the dithered box reaches past an occluder (facade parts stand proud of the footprint).
const DITHER_GROW := 0.4

const TT_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float rough = 0.9;
uniform float metal = 0.0;
uniform float emit = 0.0;
uniform bool use_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool panes = false;
uniform float levels[32];
uniform bool tower = false;
uniform vec3 glow_color : source_color = vec3(1.0, 0.84, 0.6);
uniform float glow = 0.0;
uniform bool flutter = false;
uniform bool dither = false;
uniform int occ_count = 0;
uniform vec3 occ_min[4];
uniform vec3 occ_max[4];
uniform bool xray = false;
uniform vec3 eye = vec3(0.0);
uniform vec3 focus = vec3(0.0);
varying vec3 wpos;
varying vec4 icustom;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (flutter) {
		float ph = TIME * 1.9 + w.x * 0.8 + w.z * 0.55;
		VERTEX.y += sin(ph) * 0.035 * clamp(fract(w.z * 0.37) + 0.3, 0.0, 1.0);
		w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	wpos = w;
	icustom = tower ? INSTANCE_CUSTOM : vec4(1.0);
}

// a see-through screen door: one pixel in four is kept, so a dithered thing stays a faint ghost
bool screen_door(vec2 fc) {
	return mod(floor(fc.x), 2.0) > 0.5 || mod(floor(fc.y), 2.0) > 0.5;
}

void fragment() {
	if (panes && UV.x >= levels[clamp(int(COLOR.a * 32.0), 0, 31)]) {
		discard;
	}
	if (dither && occ_count > 0) {
		for (int i = 0; i < 4; i++) {
			if (i >= occ_count) {
				break;
			}
			if (all(greaterThan(wpos, occ_min[i])) && all(lessThan(wpos, occ_max[i]))) {
				// the camera inside the box (pulled in against a wall): its walls are not drawn at all
				bool inside = xray && all(greaterThan(eye, occ_min[i])) && all(lessThan(eye, occ_max[i]));
				if (inside || screen_door(FRAGCOORD.xy)) {
					discard;
				}
			}
		}
	}
	if (xray) {
		vec3 ab = focus - eye;
		float t = dot((wpos - eye).xz, ab.xz) / max(dot(ab.xz, ab.xz), 0.01);
		// a vertical slab over the line (seen from above), from the child's knees to 4 m over the eye
		if (t > 0.0 && t < 0.9 && wpos.y > focus.y - 0.6 && wpos.y < eye.y + 4.0) {
			vec3 q = eye + ab * t;
			if (distance(wpos.xz, q.xz) < 0.35 + 0.3 * t && screen_door(FRAGCOORD.xy)) {
				discard;
			}
		}
		// right at the eye (the camera backed against a wall, a shelter or a sign that is not an occluder box):
		// not drawn at all within 1.5 m, a ghost to 2.2 m. A one-in-four ghost here veiled the whole picture.
		float de = distance(wpos, eye);
		if (de < 1.5 || (de < 2.2 && screen_door(FRAGCOORD.xy))) {
			discard;
		}
	}
	vec3 c = COLOR.rgb * base_color.rgb;
	if (tower && COLOR.a > 0.5) {
		c *= icustom.rgb;
	}
	if (use_tex) {
		c *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = c * emit;
	if (tower) {
		EMISSION += glow_color * glow * icustom.a * step(0.9, COLOR.a);
	}
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.25, 0.42, 0.45);
uniform vec3 shallow : source_color = vec3(0.41, 0.56, 0.57);
uniform vec3 sky : source_color = vec3(0.9, 0.94, 0.96);
uniform float daylight = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 g = vec2(
		sin(p.x * 1.7 + t * 1.1) * 0.5 + sin(p.y * 0.9 - t * 0.7 + p.x * 0.4) * 0.5,
		cos(p.y * 1.3 + t * 0.9) * 0.5 + sin(p.x * 0.6 + p.y * 1.1 + t * 1.3) * 0.5);
	vec3 n = normalize(vec3(g.x * 0.06, 1.0, g.y * 0.06));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	vec3 c = mix(deep, shallow, 0.5 + 0.25 * g.x);
	ALBEDO = mix(c, sky, fres * 0.55) * mix(0.35, 1.0, daylight);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.0;
varying vec4 col;

void vertex() {
	col = COLOR;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float f = 1.0 - smoothstep(0.0, 1.0, length(q));
	ALBEDO = col.rgb * f * f * strength;
}
"""

## Tests and tours: a Callable returning {"day", "minute", ...} instead of the Thousand autoload's clock.
var clock: Callable
var town_world: Node3D
## What set_time last chose (tests read it): {"day", "minute", "daylight", "dusk", "lamps", "windows",
## "background", "sun_energy", "moon_energy", ...}.
var light := {}
## The shared simulation and its plans (created by build()).
var sim: RefCounted
var nav: RefCounted

var _built := false
var _root: Node3D
var _boxes: Array = []           # occluder AABBs, index = id
var _box_info: Array = []        # per occluder: {"id" (ledger id), "kind"}
var _occluded: Array = []
var _mats := {}                  # key -> ShaderMaterial
var _dither_mats: Array = []
var _all_mats: Array = []        # every tt material (the x-ray uniforms)
var _lamp_mats: Array = []       # glow with the lamps factor
var _sign_mats: Array = []
var _mlight_mats: Array = []     # the market's lanterns
var _window_parts: Array = []    # [mesh, xf, node name] from the GLBs, merged by _windows_and_doors
var _window_index := {}          # ledger id -> index into the window shader's levels
var _window_panes := {}          # ledger id -> panes
var _window_levels := {}         # ledger id -> the light level drawn now
var _window_mat: ShaderMaterial
var _doors: Array = []           # {node, rest: Transform3D, kind, angle, offset: Vector3, building (ledger id)}
var _tower_mms: Array = []       # {mm: MultiMesh, floors: Array of {tower, floor}} for the glowing glass
var _tower_floor_rank := {}      # ledger id -> PackedFloat32Array of per-floor ranks
var _ferris: Node3D
var _rotor: Node3D
var _cabins: Array = []          # {mm: MultiMesh, i: instance, basis: Basis} by cabin number
var _cabin_pos: Array = []       # the last cabin positions (FerrisWheel space)
var _rides: Array = []           # {node, period}
var _balloons: Node3D
var _balloon_rest := Vector3.ZERO
var _fountain_mm: MultiMesh
var _droplets: Array = []
var _fountain_node: Node3D
var _water_mats: Array = []
var _pool_mat: ShaderMaterial
var _pools: MultiMeshInstance3D
var _droplet_node: MultiMeshInstance3D
var _omni_lamps: Array = []      # {pos: Vector3, colour: Color, range: float}
var _omnis: Array = []
var _omni_xz := PackedVector2Array()   # the candidates' ground points (place_lights)
var _omni_t := 0.0
var _xray_on := false
var _xray_eye := Vector3.INF     # the eye and focus last written to the x-ray uniforms
var _xray_focus := Vector3.INF
var _templates := {}             # "bus" | "taxi" -> Node3D
var _sky: Node3D
## Seconds added to the animation clock (the wheel, the rides, the balloons): tests and captures turn the ferris
## wheel to a chosen angle without waiting for it.
var anim_offset := 0.0
var _market_busy := false
var _plans: RefCounted = null
var _plans_day := -1
var _pending: RefCounted = null
var _pending_day := -1
var _sample := {}
var _sample_key := -1
var _light_minute := -INF
var _lit_now := 0                # _lit_count() of the window levels now (they change only in _refresh_town)
var _set_lamps := NAN            # the lamp factor and the water's daylight and sky colour last written (set_time)
var _set_daylight := NAN
var _set_sky := Color(-1, -1, -1, -1)
var _stats := {}
var _visrange := []              # [[RegEx, metres]]
var _cell_nodes := {}            # "layer|ix|iz|material" -> MeshInstance3D (tests count them)


func setup(tw: Node3D) -> void:
	town_world = tw


# ------------------------------------------------------------- building

func build(root: Node3D = null) -> void:
	if _built:
		return
	_built = true
	_root = root if root != null else self
	var t0 := Time.get_ticks_usec()
	nav = ThousandNav.shared()
	var t_nav := Time.get_ticks_usec()
	var wj := _json(DATA + "world.json")
	var lj := _json(DATA + "lights.json")
	for key in wj.get("godot", {}).get("visibility_ranges_m", {}):
		_visrange.append([RegEx.create_from_string(str(key)), float(wj.godot.visibility_ranges_m[key])])
	var buckets := {}
	var loose: Array = []
	var t_glb := 0
	for f in WORLD_FILES:
		var tg := Time.get_ticks_usec()
		var scene := _glb(DATA + f + ".glb")
		t_glb += Time.get_ticks_usec() - tg
		if scene == null:
			push_error("thousand_world: cannot load %s.glb" % f)
			continue
		_take(scene, buckets, loose)
		scene.free()
	var t_load := Time.get_ticks_usec()
	_add_wdata(buckets)
	var made := _commit(buckets)
	var t_merge := Time.get_ticks_usec()
	_windows_and_doors(wj)
	_towers()
	_boxes_from_parts()
	_water(wj)
	_lights(lj)
	_occluder_boxes(wj)
	_sky = SkyScript.new()
	_root.add_child(_sky)
	sim = Sim.new()
	var t_end := Time.get_ticks_usec()
	_stats = {"total_ms": (t_end - t0) / 1000.0, "nav_ms": (t_nav - t0) / 1000.0, "glb_ms": t_glb / 1000.0,
		"take_ms": (t_load - t_nav) / 1000.0 - t_glb / 1000.0, "merge_ms": (t_merge - t_load) / 1000.0,
		"rest_ms": (t_end - t_merge) / 1000.0, "merged_meshes": made, "loose_nodes": loose.size()}


static func _json(path: String) -> Dictionary:
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		push_error("thousand_world: cannot read " + path)
		return {}
	return j.data


static func _glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## The transform of `n` relative to `top` (the scene is not in the tree).
static func _xf_to(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func cell_of(p: Vector3) -> Vector2i:
	var ix := 0
	for c: float in CUTS_X:
		if p.x >= c:
			ix += 1
	var iz := 0
	for c: float in CUTS_Z:
		if p.z >= c:
			iz += 1
	return Vector2i(ix, iz)


func _range_of(node_name: String) -> float:
	for pair: Array in _visrange:
		if (pair[0] as RegEx).search(node_name) != null:
			return float(pair[1])
	return -1.0


## Sorts the meshes of one world GLB: chunk nodes into merge buckets, the rest kept as nodes.
func _take(scene: Node3D, buckets: Dictionary, loose: Array) -> void:
	var chunk := RegEx.create_from_string("^([a-z_]+?)_c(\\d)_(\\d)$")
	var keep: Array = []
	for n in scene.get_children():
		var low := String(n.name).to_lower()
		if low == "ferriswheel":
			keep.append(n)
	for n in keep:
		_keep_ferris(n, scene)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if _under(mi, keep):
			continue
		var node_name := String(mi.name)
		var low := node_name.to_lower()
		var xf := _xf_to(mi, scene)
		var vis := _range_of(node_name)
		var m := chunk.search(low)
		if m != null:
			var prefix := m.get_string(1)
			var layer := "ground"
			if prefix == "facilities" or prefix == "housing":
				layer = "building"
			elif prefix == "market_goods":
				layer = "goods"
			elif prefix == "market_lights":
				layer = "mlights"
			elif prefix == "signs":
				layer = "signs"
			elif prefix == "ballooncarts":
				layer = "carts"
			var cell := Vector2i(int(m.get_string(2)), int(m.get_string(3)))
			_bucket_add(buckets, layer, cell, vis, mi.mesh, xf)
			continue
		if low.ends_with("_awning"):
			var aabb := xf * mi.get_aabb()
			_bucket_add(buckets, "awning", cell_of(aabb.get_center()), vis, mi.mesh, xf)
			continue
		if low.begins_with("windows_") or low == "streetoffice_windows":
			_window_parts.append([mi.mesh, xf, low])
			continue
		# kept as its own node
		var keep_mi := MeshInstance3D.new()
		keep_mi.name = node_name
		keep_mi.mesh = _remat(mi.mesh, "ground")
		keep_mi.transform = xf
		if vis >= 0.0:
			_vis(keep_mi, vis)
		_root.add_child(keep_mi)
		loose.append(keep_mi)
		if low == "station_bustemplate" or low == "station_taxitemplate":
			keep_mi.visible = false
			_templates["bus" if low.contains("bus") else "taxi"] = keep_mi
		elif low == "canalfountain":
			_fountain_node = keep_mi
		elif low == "ballooncarts_balloons":
			_balloons = keep_mi
			_balloon_rest = xf.origin
		keep_mi.set_meta("thousand_kind", low)


static func _under(n: Node, tops: Array) -> bool:
	var cur := n.get_parent()
	while cur != null:
		if tops.has(cur):
			return true
		cur = cur.get_parent()
	return false


static func _vis(gi: GeometryInstance3D, metres: float) -> void:
	if metres <= 0.0:
		gi.visible = false
		return
	gi.visibility_range_end = metres
	gi.visibility_range_end_margin = 4.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _bucket_add(buckets: Dictionary, layer: String, cell: Vector2i, vis: float, mesh: Mesh, xf: Transform3D) -> void:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var mname := _tt_name(mat.resource_name) if mat else "tt_matte"
		var key := "%s|%d|%d|%s|%d" % [layer, cell.x, cell.y, mname, int(vis)]
		if not buckets.has(key):
			buckets[key] = {"layer": layer, "cell": cell, "mat": mname, "vis": vis, "parts": []}
		buckets[key].parts.append([mesh, s, xf])


## The ShaderMaterial for a tt_* material name in a layer.
func _mat(mname: String, layer: String) -> ShaderMaterial:
	var dither := layer == "building"
	var group := layer
	if layer != "building" and layer != "mlights" and layer != "awning":
		group = "ground"
	var key := group + "|" + mname
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _tt_shader()
	var rough := {"tt_matte": 0.92, "tt_paint": 0.66, "tt_metal": 0.46, "tt_glass": 0.22, "tt_lamp": 0.5,
		"tt_window": 0.72, "tt_sign": 0.6, "tt_fixture": 0.48}
	var metal := {"tt_paint": 0.06, "tt_metal": 0.5, "tt_glass": 0.14, "tt_fixture": 0.1}
	m.set_shader_parameter("rough", float(rough.get(mname, 0.85)))
	m.set_shader_parameter("metal", float(metal.get(mname, 0.0)))
	m.set_shader_parameter("dither", dither)
	_all_mats.append(m)
	if dither:
		_dither_mats.append(m)
	if layer == "awning":
		m.set_shader_parameter("flutter", true)
	if mname == "tt_lamp" or mname == "tt_fixture":
		if layer == "mlights":
			_mlight_mats.append(m)
		else:
			_lamp_mats.append(m)
	elif mname == "tt_sign":
		_sign_mats.append(m)
	_mats[key] = m
	return m


var _tt: Shader
func _tt_shader() -> Shader:
	if _tt == null:
		_tt = Shader.new()
		_tt.code = TT_SHADER
	return _tt


## A copy of a mesh with every glTF material swapped for its shader material.
func _remat(mesh: Mesh, layer: String) -> Mesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var mname := mat.resource_name if mat else "tt_matte"
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		out.surface_set_material(s, _mat(_tt_name(mname), layer))
	return out


## W-DATA's vertex-colour materials map onto the world layer's names.
static func _tt_name(mname: String) -> String:
	if mname.begins_with("tt_"):
		return mname
	return "tt_paint"


## Merges every bucket into one mesh (one surface) under a node; returns how many meshes were made.
func _commit(buckets: Dictionary) -> int:
	var keys := buckets.keys()
	keys.sort()
	var made := 0
	for key: String in keys:
		var b: Dictionary = buckets[key]
		var mesh := _merge(b.parts)
		if mesh == null:
			continue
		var mname := _tt_name(str(b.mat))
		mesh.surface_set_material(0, _mat(mname, str(b.layer)))
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d_%d_%s" % [b.layer, b.cell.x, b.cell.y, mname]
		mi.mesh = mesh
		if float(b.vis) >= 0.0:
			_vis(mi, float(b.vis))
		mi.set_meta("layer", b.layer)
		_root.add_child(mi)
		_cell_nodes[key] = mi
		made += 1
	return made


## One surface from many: positions and normals moved by their transforms, colours (white where missing), UVs
## when every part has them, and the indices offset. The biggest part goes first (no index pass).
static func _merge(parts: Array) -> ArrayMesh:
	var items: Array = []
	var all_uv := true
	for p: Array in parts:
		var arrays: Array = (p[0] as Mesh).surface_get_arrays(int(p[1]))
		items.append([arrays, p[2]])
		if arrays[Mesh.ARRAY_TEX_UV] == null:
			all_uv = false
	items.sort_custom(func(a, b): return (a[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > (b[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	for it: Array in items:
		var arrays: Array = it[0]
		var xf: Transform3D = it[1]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			v = xf * v
			if n.size() > 0:
				n = Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * n
		var count := v.size()
		var off := V.size()
		V.append_array(v)
		if n.size() == count:
			N.append_array(n)
		else:
			var fill := PackedVector3Array()
			fill.resize(count)
			fill.fill(Vector3.UP)
			N.append_array(fill)
		var c = arrays[Mesh.ARRAY_COLOR]
		if c != null and (c as PackedColorArray).size() == count:
			C.append_array(c)
		else:
			var white := PackedColorArray()
			white.resize(count)
			white.fill(Color.WHITE)
			C.append_array(white)
		if all_uv:
			U.append_array(arrays[Mesh.ARRAY_TEX_UV])
		var idx = arrays[Mesh.ARRAY_INDEX]
		var ii: PackedInt32Array
		if idx == null:
			ii = PackedInt32Array(range(count))
		else:
			ii = idx
		if off > 0:
			for k in ii.size():
				ii[k] += off
		I.append_array(ii)
	if V.is_empty():
		return null
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = V
	out[Mesh.ARRAY_NORMAL] = N
	out[Mesh.ARRAY_COLOR] = C
	if all_uv:
		out[Mesh.ARRAY_TEX_UV] = U
	out[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## The ferris wheel keeps its hierarchy (it turns).
func _keep_ferris(n: Node, scene: Node3D) -> void:
	var xf := _xf_to(n, scene)
	for c in n.find_children("*", "", true, false):
		c.owner = null
	n.owner = null
	scene.remove_child(n)
	_root.add_child(n)
	(n as Node3D).transform = xf
	_ferris = n
	var cabins: Array = []
	for c in n.find_children("*", "", true, false):
		var low := String(c.name).to_lower()
		if low == "ferrisrotor":
			_rotor = c
		elif low.begins_with("ferriscabin_") and c is MeshInstance3D:
			cabins.append(c)
	cabins.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if not cabins.has(mi):
			mi.mesh = _remat(mi.mesh, "ground")
	# the twelve cabins: one MultiMesh per shared mesh (cabins k and k + 3 share one), so 6 draw calls, not 24
	var groups := {}
	for k in cabins.size():
		var cab: MeshInstance3D = cabins[k]
		if not groups.has(cab.mesh):
			groups[cab.mesh] = []
		groups[cab.mesh].append(k)
	_cabins.resize(cabins.size())
	_cabin_pos.resize(cabins.size())
	var gi := 0
	for mesh: Mesh in groups:
		var ks: Array = groups[mesh]
		var xfs: Array = []
		for k: int in ks:
			xfs.append((cabins[k] as Node3D).transform)
		var mmi := _mm_node("ferris_cabins_%d" % gi, _remat(mesh, "ground"), xfs, [], [], null)
		mmi.custom_aabb = AABB(Vector3(-12.5, 1.0, -2.0), Vector3(25.0, 25.0, 4.0))
		cabins[ks[0]].get_parent().add_child(mmi)
		for j in ks.size():
			_cabins[ks[j]] = {"mm": mmi.multimesh, "i": j, "basis": (cabins[ks[j]] as Node3D).transform.basis}
		gi += 1
	for cab: Node in cabins:
		cab.get_parent().remove_child(cab)
		cab.free()


## A MultiMeshInstance3D of `mesh` at `xfs` (colours and custom data optional), its AABB computed here (the
## renderer culls by it; headless servers keep no instance data, so the transforms are also kept as meta
## "xfs" for the tests).
func _mm_node(node_name: String, mesh: Mesh, xfs: Array, colors: Array, customs: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true   # without colours the Compatibility renderer's COLOR is zero for a MultiMesh
	mm.use_custom_data = not customs.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var box := AABB()
	var maabb := mesh.get_aabb()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
		if not customs.is_empty():
			mm.set_instance_custom_data(i, customs[i])
		var b: AABB = (xfs[i] as Transform3D) * maabb
		box = b if i == 0 else box.merge(b)
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.custom_aabb = box
	node.set_meta("xfs", xfs)
	if mat:
		node.material_override = mat
	return node


## W-DATA's meshes the world layer leaves out (town.json): civic entry modules, the plaza monument with its
## benches and planters, the ride bases (merged into the buckets) and the ride rotors (turning nodes).
func _add_wdata(buckets: Dictionary) -> void:
	var d := ThousandMap.data()
	var civic := _glb(ThousandMap.glb_path("civic"))
	if civic:
		var by_name := {}
		for mi: MeshInstance3D in civic.find_children("*", "MeshInstance3D", true, false):
			by_name[String(mi.name)] = mi.mesh
		for mod: Dictionary in d.meshes.civic.get("modules", []):
			var fac := str(mod.facility)
			var b := _facility(fac)
			if b.is_empty() or not by_name.has(str(mod.name)):
				continue
			var y := float(b.height) if str(mod.floor) == "roof" else PLINTH + STOREY * float(mod.floor)
			var xf := Transform3D(Basis.IDENTITY, Vector3(b.center.x, y, b.center.y))
			_bucket_add(buckets, "building", cell_of(xf.origin), -1.0, by_name[str(mod.name)], xf)
		civic.free()
	var land := _glb(ThousandMap.glb_path("landscape"))
	var lm: Dictionary = d.get("landmarks", {})
	if land and lm.has("monument"):
		var by_name := {}
		for mi: MeshInstance3D in land.find_children("*", "MeshInstance3D", true, false):
			by_name[String(mi.name)] = mi.mesh
		var mon: Dictionary = lm.monument
		var place := func(module: String, x: float, z: float, yaw: float) -> void:
			if by_name.has(module):
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.0, z))
				_bucket_add(buckets, "ground", cell_of(xf.origin), -1.0, by_name[module], xf)
		place.call(str(mon.module), float(mon.x), float(mon.z), 0.0)
		for b: Dictionary in mon.get("benches", []):
			place.call(str(b.module), float(b.x), float(b.z), float(b.get("yaw", 0.0)))
		for p: Dictionary in mon.get("planters", []):
			place.call(str(p.module), float(p.x), float(p.z), 0.0)
	if land:
		land.free()
	var rides := _glb(ThousandMap.glb_path("amusement"))
	if rides:
		var by_name := {}
		for mi: MeshInstance3D in rides.find_children("*", "MeshInstance3D", true, false):
			by_name[String(mi.name)] = mi.mesh
		for key in ["carousel", "teacups"]:
			if not lm.has(key):
				continue
			var r: Dictionary = lm[key]
			var at := Vector3(float(r.x), float(r.y), float(r.z))
			for module: String in r.modules:
				if not by_name.has(module):
					continue
				if module.to_lower().ends_with("rotor"):
					var mi := MeshInstance3D.new()
					mi.name = module
					mi.mesh = _remat(by_name[module], "ground")
					mi.position = at
					_root.add_child(mi)
					_rides.append({"node": mi, "period": float(r.period)})
				else:
					_bucket_add(buckets, "ground", cell_of(at), -1.0, by_name[module], Transform3D(Basis.IDENTITY, at))
		rides.free()


## A facility building's map record by its programme ("mall", "hospital", "secondary").
static func _facility(programme: String) -> Dictionary:
	for b: Dictionary in ThousandMap.buildings():
		if str(b.programme) == programme:
			return b
	return {}


## Window panes (every group in one mesh; a level per building in the shader) and the doors (animated by
## door-open).
func _windows_and_doors(wj: Dictionary) -> void:
	var anim: Dictionary = wj.get("animate", {})
	var win_of := {}
	for w: Dictionary in anim.get("windows", []):
		win_of[str(w.node).to_lower()] = w
	var door_of := {}
	for d: Dictionary in anim.get("doors", []):
		door_of[str(d.node).to_lower()] = d
	# every window group in one mesh: COLOR.a carries the group's index into the shader's levels
	var parts: Array = []
	for wp: Array in _window_parts:
		var w: Dictionary = win_of.get(str(wp[2]), {})
		if w.is_empty():
			continue
		var bid := ledger_id(str(w.building))
		if not _window_index.has(bid):
			_window_index[bid] = _window_index.size()
			_window_panes[bid] = 0
			_window_levels[bid] = 0.0
		_window_panes[bid] += int(w.panes)
		var tag := (float(_window_index[bid]) + 0.5) / 32.0
		var mesh: Mesh = wp[0]
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for k in cols.size():
				cols[k].a = tag
			arrays[Mesh.ARRAY_COLOR] = cols
			var one := ArrayMesh.new()
			one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			parts.append([one, 0, wp[1]])
	if not parts.is_empty():
		var merged := _merge(parts)
		_window_mat = ShaderMaterial.new()
		_window_mat.shader = _tt_shader()
		_window_mat.set_shader_parameter("panes", true)
		_window_mat.set_shader_parameter("levels", PackedFloat32Array(Array(range(32)).map(func(_i): return 0.0)))
		_window_mat.set_shader_parameter("rough", 0.72)
		_window_mat.set_shader_parameter("dither", true)
		_dither_mats.append(_window_mat)
		_all_mats.append(_window_mat)
		merged.surface_set_material(0, _window_mat)
		var mi := MeshInstance3D.new()
		mi.name = "windows"
		mi.mesh = merged
		mi.set_meta("layer", "building")
		_root.add_child(mi)
	_window_parts = []
	for n in _root.get_children():
		if not n is MeshInstance3D or not n.has_meta("thousand_kind"):
			continue
		var low: String = n.get_meta("thousand_kind")
		if door_of.has(low):
			var d: Dictionary = door_of[low]
			var mo: Dictionary = d.motion
			var off := Vector3.ZERO
			if mo.has("offset_m"):
				off = Vector3(float(mo.offset_m[0]), float(mo.offset_m[1]), float(mo.offset_m[2]))
			_doors.append({"node": n, "rest": (n as Node3D).transform, "kind": str(mo.kind),
				"angle": float(mo.get("angle", 0.0)), "offset": off, "building": ledger_id(str(d.building))})


## The four office towers: district.glb floor and roof modules as MultiMeshes over all towers, tinted per tower
## as upstream (city-district.js buildingTints), the setback above floor(floors x 0.74) at 0.8 x 0.86, the
## roof module on top. Each module's parts are merged into two meshes (the textured stone, and the rest with
## its material colours baked into the vertex colours; alpha marks the tinted glass, 1.0 where it glows), so
## a module is two draw calls. Instance custom data: rgb the tint, a the floor's glow (lit by occupancy).
func _towers() -> void:
	var dist := _glb(ThousandMap.glb_path("district"))
	if dist == null:
		return
	var raw: Dictionary = {}
	for b: Dictionary in ThousandMap.data().buildings:
		raw[b.id] = b
	var inst := {}   # module root name -> [{xf, tower, floor, glass, mineral}]
	for b: Dictionary in ThousandMap.buildings():
		if b.kind != "tower" or not b.has("modules"):
			continue
		var mods: Dictionary = b.modules
		var floors := int(b.floors)
		var cut := int(mods.get("setback_floor", floors))
		var sc: Array = mods.scale
		var up: Array = mods.get("upper_scale", [1, 1, 1])
		var bid := ledger_id(str(b.id))
		var pal: Dictionary = raw[b.id].get("palette", {})
		var glass := _ratio(str(pal.get("glass", "#63a8bb")), "#63a8bb")
		var mineral := _ratio(str(pal.get("wall", "#e6eef3")), "#e6eef3")
		var ranks := PackedFloat32Array()
		var floor_name := str(mods.floor)
		for f in floors + 1:
			var is_roof := f == floors
			if is_roof and mods.get("roof") == null:
				break
			var upper := f >= cut
			var s := Vector3(float(sc[0]) * (float(up[0]) if upper else 1.0), 1.0, float(sc[2]) * (float(up[2]) if upper else 1.0))
			var xf := Transform3D(Basis.from_scale(s), Vector3(b.center.x, PLINTH + STOREY * f, b.center.y))
			var rn := str(mods.roof) if is_roof else floor_name
			if not inst.has(rn):
				inst[rn] = []
			inst[rn].append({"xf": xf, "tower": bid, "floor": -1 if is_roof else f, "glass": glass, "mineral": mineral})
			if not is_roof:
				ranks.append(fposmod(float(f) * 0.6180339 + 0.37, 1.0))
		_tower_floor_rank[bid] = ranks
	for root_node in dist.get_children():
		var rname := String(root_node.name)
		if not inst.has(rname):
			continue
		var list: Array = inst[rname]
		var plain: Array = []
		var textured: Array = []   # [mesh, StandardMaterial3D]
		for mi: MeshInstance3D in root_node.find_children("*", "MeshInstance3D", true, false):
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
			var mname := src.resource_name.to_lower() if src else ""
			if src and src.albedo_texture:
				textured.append([mi.mesh, src])
				continue
			var arrays := mi.mesh.surface_get_arrays(0)
			var flag := 0.0
			if mname == "district_glasswarm" or mname == "district_glass":
				flag = 1.0
			elif mname.begins_with("district_glass"):
				flag = 0.75
			var base := (src.albedo_color if src else Color.WHITE).srgb_to_linear()
			var cc := PackedColorArray()
			cc.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			cc.fill(Color(base.r, base.g, base.b, flag))
			arrays[Mesh.ARRAY_COLOR] = cc
			var one := ArrayMesh.new()
			one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			plain.append([one, 0, Transform3D.IDENTITY])
		var groups: Array = []
		if not plain.is_empty():
			groups.append({"mesh": _merge(plain), "src": null, "glows": true})
		for t: Array in textured:
			var one := ArrayMesh.new()
			var ta := (t[0] as Mesh).surface_get_arrays(0)
			var white := PackedColorArray()
			white.resize((ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			white.fill(Color(1, 1, 1, 0.75))   # COLOR is zero without a colour array; tinted, no glow
			ta[Mesh.ARRAY_COLOR] = white
			one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
			groups.append({"mesh": one, "src": t[1], "glows": false})
		for g: Dictionary in groups:
			var xfs: Array = []
			var customs: Array = []
			for it: Dictionary in list:
				xfs.append(it.xf)
				var tint: Color = it.glass if g.glows else it.mineral
				customs.append(Color(tint.r, tint.g, tint.b, 0.0))
			var m := ShaderMaterial.new()
			m.shader = _tt_shader()
			m.set_shader_parameter("tower", true)
			m.set_shader_parameter("dither", true)
			m.set_shader_parameter("glow_color", TOWER_GLOW)
			var src: StandardMaterial3D = g.src
			if src:
				m.set_shader_parameter("base_color", src.albedo_color)
				m.set_shader_parameter("rough", src.roughness)
				m.set_shader_parameter("use_tex", true)
				m.set_shader_parameter("albedo_tex", src.albedo_texture)
			else:
				m.set_shader_parameter("rough", 0.4)
				m.set_shader_parameter("metal", 0.15)
				_tower_mms.append({"mm": null, "list": list, "mat": m})
			_dither_mats.append(m)
			_all_mats.append(m)
			var node := _mm_node("tower_" + rname.to_lower() + ("_stone" if src else "_body"), g.mesh, xfs, [], customs, m)
			if not src:
				_tower_mms[-1]["mm"] = node.multimesh
			_root.add_child(node)
	dist.free()
	# the helipad on the tallest tower (town.json landmarks.helipad)
	var hp: Dictionary = ThousandMap.data().get("landmarks", {}).get("helipad", {})
	if not hp.is_empty():
		var pad := MeshInstance3D.new()
		pad.name = "helipad"
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(hp.radius)
		cyl.bottom_radius = float(hp.radius)
		cyl.height = float(hp.deck)
		cyl.radial_segments = 24
		var arr := cyl.get_mesh_arrays()
		var cc := PackedColorArray()
		cc.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cc.fill(Color("#3d4a50").srgb_to_linear())
		arr[Mesh.ARRAY_COLOR] = cc
		var col := ArrayMesh.new()
		col.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		pad.mesh = col
		pad.material_override = _mat("tt_paint", "building")
		pad.position = Vector3(float(hp.x), float(hp.roof_y) + float(hp.deck) * 0.5, float(hp.z))
		_root.add_child(pad)


## A tower palette tint: target / base, in linear colour (upstream's relative()).
static func _ratio(target: String, base: String) -> Color:
	var t := Color(target).srgb_to_linear()
	var b := Color(base).srgb_to_linear()
	return Color(t.r / maxf(b.r, 0.001), t.g / maxf(b.g, 0.001), t.b / maxf(b.b, 0.001))


## The frontage and the towers' office parts: box MultiMeshes per cell and material (town.json box parts).
func _boxes_from_parts() -> void:
	var d := ThousandMap.data()
	var groups := {}   # "layer|ix|iz|mat" -> Array of [Transform3D, Color]
	var role_colors: Dictionary = d.get("frontage", {}).get("role_colors", {})
	for site: Dictionary in d.get("frontage", {}).get("sites", []):
		for p: Dictionary in site.get("parts", []):
			var role := str(p.role)
			var mat := "tt_lamp" if role in LIT_ROLES else "tt_paint"   # two draw calls a cell
			var yaw := float(p.get("yaw", 0.0)) if role in SHEET_ROLES else 0.0
			var size := Vector3(float(p.w), float(p.h), float(p.d))
			if role in SHEET_ROLES and absf(yaw) > 0.001:
				# a sheet turned to face its side: d wide when |sin yaw| > 0.5, else w (town.json notes)
				var wide := float(p.d) if absf(sin(yaw)) > 0.5 else float(p.w)
				var thin := minf(float(p.w), float(p.d))
				size = Vector3(wide, float(p.h), thin)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), Vector3(float(p.x), float(p.y), float(p.z)))
			var col := Color(str(role_colors.get(role, "#ece5d9"))).srgb_to_linear()
			var c := cell_of(xf.origin)
			var key := "frontage|%d|%d|%s" % [c.x, c.y, mat]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([xf, col])
	for grp: Dictionary in d.get("office_parts", []):
		for p: Dictionary in grp.get("parts", []):
			var size := Vector3(float(p.w), float(p.h), float(p.d))
			var yaw := float(p.get("yaw", 0.0))
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), Vector3(float(p.x), float(p.y), float(p.z)))
			var col := Color(str(p.get("color", "#e6eef3"))).srgb_to_linear()
			var c := cell_of(xf.origin)
			var key := "office|%d|%d|tt_paint" % [c.x, c.y]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([xf, col])
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var unit := ArrayMesh.new()
	unit.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var list: Array = groups[key]
		var parts := key.split("|")
		var node := _mm_node("%s_%s_%s_%s" % [parts[0], parts[1], parts[2], parts[3]], unit, list.map(func(it): return it[0]),
			list.map(func(it): return it[1]), [], _mat(parts[3], "building" if parts[0] == "office" else "ground"))
		_root.add_child(node)


## The canal's water, the plaza fountain's ring basin and the canal fountain's droplets.
func _water(wj: Dictionary) -> void:
	var d := ThousandMap.data()
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	var canal: Rect2 = ThousandMap.canal()
	var wy := float(d.canal.get("water_y", -0.275))
	var water := MeshInstance3D.new()
	water.name = "canal_water"
	var plane := PlaneMesh.new()
	plane.size = canal.size
	plane.subdivide_depth = 0
	water.mesh = plane
	water.position = Vector3(canal.get_center().x, wy, canal.get_center().y)
	var wm := ShaderMaterial.new()
	wm.shader = wsh
	water.material_override = wm
	_water_mats.append(wm)
	_root.add_child(water)
	var f: Dictionary = d.get("landmarks", {}).get("fountain", {})
	if not f.is_empty():
		var ring := MeshInstance3D.new()
		ring.name = "plaza_fountain_water"
		ring.mesh = _annulus(float(f.inner), float(f.outer), 48)
		ring.position = Vector3(float(f.x), float(f.surface_y), float(f.z))
		var rm := ShaderMaterial.new()
		rm.shader = wsh
		ring.material_override = rm
		_water_mats.append(rm)
		_root.add_child(ring)
	# the canal fountain's droplets (world.json animate.canal_fountain)
	var cf: Dictionary = wj.get("animate", {}).get("canal_fountain", {})
	_droplets = cf.get("droplets", [])
	if not _droplets.is_empty():
		var drop := SphereMesh.new()
		drop.radius = 1.0
		drop.height = 2.0
		drop.radial_segments = 6
		drop.rings = 3
		_fountain_mm = MultiMesh.new()
		_fountain_mm.transform_format = MultiMesh.TRANSFORM_3D
		_fountain_mm.mesh = drop
		_fountain_mm.instance_count = _droplets.size()
		var node := MultiMeshInstance3D.new()
		node.name = "canal_fountain_droplets"
		node.multimesh = _fountain_mm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color("#d9eef2")
		dm.roughness = 0.1
		dm.emission_enabled = true
		dm.emission = Color("#8fc7d6")
		dm.emission_energy_multiplier = 0.15
		node.material_override = dm
		var cen: Array = cf.get("centre", [0, 0, 0])
		node.position = Vector3(float(cen[0]), float(cen[1]), float(cen[2]))
		_vis(node, 150.0)
		node.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
		_root.add_child(node)
		_droplet_node = node
		_fountain_droplets(0.0, true)


static func _annulus(r0: float, r1: float, n: int) -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var I := PackedInt32Array()
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var dir := Vector3(cos(a), 0.0, sin(a))
		V.append(dir * r0)
		V.append(dir * r1)
		N.append(Vector3.UP)
		N.append(Vector3.UP)
	for i in n:
		var k := i * 2
		I.append_array(PackedInt32Array([k, k + 2, k + 1, k + 1, k + 2, k + 3]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Real lights on the omni candidates nearest the camera, and the light pools (lights.json).
func _lights(lj: Dictionary) -> void:
	for l: Dictionary in lj.get("lamps", []):
		if bool(l.get("omni_candidate", false)):
			var p: Array = l.position
			_omni_lamps.append({"pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
				"colour": Color(str(l.get("colour", "#ffe5bc"))), "range": float(l.get("range_m", 8.0))})
	for i in OMNI_COUNT:
		var o := OmniLight3D.new()
		o.name = "lamp_light_%d" % i
		o.shadow_enabled = false
		o.light_energy = 0.0
		o.visible = false
		o.omni_attenuation = 1.2
		_root.add_child(o)
		_omnis.append(o)
	var pools: Array = lj.get("pools", [])
	if pools.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var xfs: Array = []
	var cols: Array = []
	for p: Dictionary in pools:
		var c: Array = p.centre
		var s: Array = p.size_m
		xfs.append(Transform3D(Basis.from_scale(Vector3(float(s[0]), 1.0, float(s[1]))), Vector3(float(c[0]), float(c[1]) + 0.03, float(c[2]))))
		cols.append(Color(str(p.get("colour", "#ffcf91"))).srgb_to_linear() * float(p.get("level", 1.0)))
	var node := _mm_node("light_pools", quad, xfs, cols, [], null)
	_pools = node
	_pool_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = POOL_SHADER
	_pool_mat.shader = sh
	node.material_override = _pool_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(node)


## The occluders: the facility and annex bodies (their footprint solid and top), the housing wings, the
## towers and the station canopy.
func _occluder_boxes(wj: Dictionary) -> void:
	_boxes = []
	_box_info = []
	var tops: Dictionary = wj.get("buildings", {})
	var largest := {}   # building id -> the index of its largest "building" solid
	for i in nav.sid.size():
		if nav.skind[i] != "building":
			continue
		var bid: String = nav.sid[i].get_slice("#", 0)
		var area: float = (nav.sx1[i] - nav.sx0[i]) * (nav.sz1[i] - nav.sz0[i])
		var j := int(largest.get(bid, -1))
		if j < 0 or area > (nav.sx1[j] - nav.sx0[j]) * (nav.sz1[j] - nav.sz0[j]):
			largest[bid] = i
	for bid: String in tops:
		var best := int(largest.get(bid, -1))
		if best < 0:
			continue
		var top := float(tops[bid].get("top_m", 10.0))
		_boxes.append(AABB(Vector3(nav.sx0[best], 0.0, nav.sz0[best]), Vector3(nav.sx1[best] - nav.sx0[best], top, nav.sz1[best] - nav.sz0[best])))
		_box_info.append({"id": ledger_id(bid), "kind": "facility"})
	for b: Dictionary in ThousandMap.buildings():
		if b.kind == "tower":
			var r: Rect2 = b.rect
			_boxes.append(AABB(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, float(b.height), r.size.y)))
			_box_info.append({"id": ledger_id(str(b.id)), "kind": "tower"})
		elif b.kind == "housing":
			for v: Dictionary in b.get("volumes", []):
				var r: Rect2 = v.rect
				var h := PLINTH + STOREY * float(v.floors) + 1.5
				_boxes.append(AABB(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, h, r.size.y)))
				_box_info.append({"id": ledger_id(str(b.id)), "kind": "housing"})
	var st: Dictionary = ThousandMap.data().get("places", {}).get("station", {})
	if st.has("canopy"):
		var cr := ThousandMap.rect_of(st.canopy)
		var cy := float(st.canopy.get("y", 4.08))
		_boxes.append(AABB(Vector3(cr.position.x, cy - 0.35, cr.position.y), Vector3(cr.size.x, 0.7, cr.size.y)))
		_box_info.append({"id": "c-station", "kind": "canopy"})


## The ledger id for a town.json building id (annexes, the street office and the places are their own).
static func ledger_id(map_id: String) -> String:
	return SIM_IDS.get(map_id, map_id)


## The town.json id for a ledger id (or a placeholder alias).
static func map_id(id: String) -> String:
	id = BUILDINGS.get(id, id)
	for k in SIM_IDS:
		if SIM_IDS[k] == id:
			return k
	return id


# ------------------------------------------------------------- time and light

func view_time() -> Dictionary:
	if clock.is_valid():
		return clock.call()
	var t := get_node_or_null("/root/Thousand")
	if t and t.has_method("est_clock"):
		return t.est_clock()
	return {"day": 1, "minute": 480.0, "mode": "auto", "speed": 1}


## 0 at night .. 1 by day (thousand_clock's daylight: dark before 05:30, full by 07:00, gone by 19:30).
static func daylight(minute: float) -> float:
	return Clock.daylight(minute)


func set_time(day: int, minute: float) -> void:
	var m := fposmod(minute, 1440.0)
	var env: Environment = town_world.get("_env") if town_world else null
	var town_sun: DirectionalLight3D = town_world.get("_sun") if town_world else null
	if _sky == null:
		_sky = SkyScript.new()
		(_root if _root else self).add_child(_sky)
	var f: Dictionary = _sky.apply(m + 1440.0 * float(maxi(day - 1, 0)), env, town_sun)
	light = f.duplicate()
	light["day"] = day
	light["minute"] = m
	light["sun_energy"] = f.sun_energy
	light["market_busy"] = _market_busy   # kept between samples
	# the glowing groups follow the lamp factor (a uniform each, written when the factor changes)
	var lamps := float(f.lamps)
	if lamps != _set_lamps:
		_set_lamps = lamps
		for mat: ShaderMaterial in _lamp_mats:
			mat.set_shader_parameter("emit", lamps * LAMP_GLOW)
		for mat: ShaderMaterial in _sign_mats:
			mat.set_shader_parameter("emit", lamps * SIGN_GLOW)
		if _pool_mat:
			_pool_mat.set_shader_parameter("strength", lamps * 0.55)
			_pools.visible = lamps > 0.01   # no draw call by day
	var dl := float(f.daylight)
	var bgc: Color = f.background
	if dl != _set_daylight or bgc != _set_sky:
		_set_daylight = dl
		_set_sky = bgc
		for wm: ShaderMaterial in _water_mats:
			wm.set_shader_parameter("daylight", dl)
			wm.set_shader_parameter("sky", bgc)
	# occupancy: at most every LIGHT_STEP sim minutes
	var key := day * 10000 + int(floor(m / LIGHT_STEP))
	if key != _sample_key and sim != null:
		_sample_key = key
		_refresh_town(day, m)
	light["windows_lit"] = _lit_now


## The plans of a day: built at once the first time, a few residents a frame on a later day change (the old
## sample stays meanwhile).
func _ensure_plans(day: int) -> bool:
	if _plans != null and _plans_day == day:
		return true
	if _plans == null:
		_plans = sim.build_day(day)
		_plans_day = day
		return true
	if _pending_day != day:
		_pending = sim.begin_day(day)
		_pending_day = day
	return false


func _refresh_town(day: int, m: float) -> void:
	if not _ensure_plans(day):
		return
	_sample = sim.sample(_plans, m)
	var by_id := {}
	for b: Dictionary in _sample.get("buildings", []):
		by_id[str(b.id)] = b
	# windows: one level per building
	var lv := PackedFloat32Array()
	lv.resize(32)
	for bid: String in _window_index:
		var b: Dictionary = by_id.get(bid, {})
		var lvl := float(b.get("light", 0.0))
		if int(b.get("max_panes", -1)) == 1 and int(b.get("count", 0)) > 0:
			lvl = 0.99 / float(maxi(1, int(_window_panes[bid])))
		lv[int(_window_index[bid])] = lvl
		_window_levels[bid] = lvl
	if _window_mat:
		_window_mat.set_shader_parameter("levels", lv)
		_window_mat.set_shader_parameter("emit", WINDOW_GLOW)
	# doors
	for d: Dictionary in _doors:
		var b: Dictionary = by_id.get(str(d.building), {})
		var open := float(b.get("door_open", 0.0))
		if open < 0.0:
			open = 1.0 if bool(b.get("open", false)) else 0.0
		var rest: Transform3D = d.rest
		var node: Node3D = d.node
		if str(d.kind) == "swing":
			node.transform = Transform3D(rest.basis * Basis(Vector3.UP, float(d.angle) * open), rest.origin)
		else:
			node.transform = Transform3D(rest.basis, rest.origin + (d.offset as Vector3) * open)
		d["open"] = open
	# tower floors
	for t: Dictionary in _tower_mms:
		var mm: MultiMesh = t.mm
		var list: Array = t.list
		for i in list.size():
			var it: Dictionary = list[i]
			var lvl := float(by_id.get(str(it.tower), {}).get("light", 0.0))
			var ranks: PackedFloat32Array = _tower_floor_rank.get(str(it.tower), PackedFloat32Array())
			var on := 0.0
			if int(it.floor) >= 0 and int(it.floor) < ranks.size() and ranks[int(it.floor)] < lvl:
				on = 1.0
			var tint: Color = it.glass
			mm.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, on))
		(t.mat as ShaderMaterial).set_shader_parameter("glow", float(light.get("windows", 0.0)) * 0.9)
	# the night market's lanterns: bright while it is busy
	var nm: Dictionary = by_id.get("c-night-market", {})
	var busy := bool(nm.get("open", false)) and int(nm.get("count", 0)) > 0
	var lamps := float(light.get("lamps", 0.0))
	for mat: ShaderMaterial in _mlight_mats:
		mat.set_shader_parameter("emit", lamps * (MARKET_BUSY if busy else MARKET_IDLE))
	light["market_busy"] = busy
	_market_busy = busy
	_lit_now = _lit_count()   # the window levels change only here


func _lit_count() -> int:
	var n := 0
	for bid: String in _window_levels:
		n += int(ceil(float(_window_levels[bid]) * float(_window_panes[bid])))
	return n


## The share of a building's window panes lit now (its ledger id), or -1 for a building without panes.
func window_level(id: String) -> float:
	return float(_window_levels.get(id, -1.0))


## The last occupancy sample (thousand_sim.sample), {} before the first set_time.
func town_sample() -> Dictionary:
	return _sample


## Today's plans (null before the first set_time).
func plans() -> RefCounted:
	return _plans


## The plans of `day`, built at once when the town has none yet (the journey's loading builds them so the residents
## can be placed before the first frame in the town; a later day still comes a few residents a frame).
func ensure_plans(day: int) -> RefCounted:
	if sim != null and _plans == null:
		_ensure_plans(day)
	return _plans


## The bus or taxi template (invisible; front toward -z, wheels on y 0.125 m) for the transit to instance.
func vehicle_template(kind: String) -> Node3D:
	return _templates.get(kind)


func stats() -> Dictionary:
	return _stats


# ------------------------------------------------------------- per frame

func _process(dt: float) -> void:
	if not _built or not is_visible_in_tree():
		return
	if _pending != null:
		if sim.build_more(_pending, PLAN_BATCH):
			_plans = _pending
			_plans_day = _pending_day
			_pending = null
			_pending_day = -1
			_sample_key = -1   # sample the new day at the next set_time
	var t := Time.get_ticks_msec() / 1000.0 + anim_offset
	animate(t)
	var cam := get_viewport().get_camera_3d()
	var kid: Node3D = town_world.call("local_kid") if town_world and town_world.has_method("local_kid") else null
	if cam and kid and is_instance_valid(kid):
		set_view_line(cam.global_position, kid.global_position + Vector3(0, 0.9, 0))
	else:
		set_view_line(Vector3.ZERO, Vector3.ZERO)
	_omni_t -= dt
	if _omni_t <= 0.0:
		_omni_t = OMNI_EVERY
		if cam:
			place_lights(cam.global_position)


## The x-ray: whatever stands on the line from the eye to the child's chest (a lamp post, a tree, a sign)
## is drawn with a screen-door pattern; within 1.5 m of the eye it is not drawn, to 2.2 m a ghost. eye == focus
## turns it off.
func set_view_line(eye: Vector3, focus: Vector3) -> void:
	var on := eye.distance_to(focus) > 0.5 and eye.distance_to(focus) < XRAY_MAX
	if not on and not _xray_on:
		return
	if on == _xray_on and (not on or (eye == _xray_eye and focus == _xray_focus)):
		return   # the uniforms already hold exactly these values (a still camera)
	_xray_on = on
	_xray_eye = eye
	_xray_focus = focus
	for m: ShaderMaterial in _all_mats:
		m.set_shader_parameter("xray", on)
		if on:
			m.set_shader_parameter("eye", eye)
			m.set_shader_parameter("focus", focus)


## Cabin k's position in the wheel's space (after the last animate()).
func cabin_position(k: int) -> Vector3:
	return _cabin_pos[k] if k >= 0 and k < _cabin_pos.size() and _cabin_pos[k] != null else Vector3.INF


## Cabin k's hanging point in town space (the rim, where the cabin hangs from), INF before the wheel is built.
func cabin_global(k: int) -> Vector3:
	var p := cabin_position(k)
	if p == Vector3.INF or _ferris == null or not _ferris.is_inside_tree():
		return Vector3.INF
	return _ferris.global_transform * p


## The ferris wheel's frame in town space: origin at its foot centre, x along the wheel's plane (Identity before
## the wheel is built), and the number of cabins.
func wheel_frame() -> Transform3D:
	return _ferris.global_transform if _ferris != null and _ferris.is_inside_tree() else Transform3D.IDENTITY


func cabin_count() -> int:
	return _cabins.size()


## The moving parts at a time in seconds (tests call it with fixed times).
func animate(t: float) -> void:
	if _rotor and not _cabins.is_empty():
		var angle := fmod(t, 180.0) / 180.0 * TAU
		_rotor.rotation = Vector3(0.0, 0.0, angle)
		for k in _cabins.size():
			var a := angle + float(k) * PI / 6.0
			var pos := Vector3(cos(a) * 10.0, 13.0 + sin(a) * 10.0, 0.0)
			_cabin_pos[k] = pos
			var c: Dictionary = _cabins[k]
			(c.mm as MultiMesh).set_instance_transform(int(c.i), Transform3D(c.basis, pos))
	for r: Dictionary in _rides:
		(r.node as Node3D).rotation.y = fmod(t, float(r.period)) / float(r.period) * TAU
	if _balloons:
		var p := fmod(t, 12.0) / 12.0 * TAU
		_balloons.position = _balloon_rest + Vector3(cos(p) * 0.05, sin(p) * 0.09, sin(p) * 0.05)
	_fountain_droplets(t, false)


func _fountain_droplets(t: float, force: bool) -> void:
	if _fountain_mm == null:
		return
	var m := float(light.get("minute", 720.0))
	var on := not (m >= 1320.0 or m < 330.0)   # the pump is off 22:00-05:30
	if _droplet_node:
		_droplet_node.visible = on
	if not force and not on and _fountain_mm.get_meta("off", false):
		return
	_fountain_mm.set_meta("off", not on)
	for i in _droplets.size():
		var dr: Dictionary = _droplets[i]
		if not on:
			_fountain_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
			continue
		var period := float(dr.period_s)
		var u := fposmod(t / period + float(dr.phase), 1.0) * period
		var p0: Array = dr.p0
		var v: Array = dr.v
		var pos := Vector3(float(p0[0]) + float(v[0]) * u, float(p0[1]) + float(v[1]) * u - 4.75 * u * u * 0.5, float(p0[2]) + float(v[2]) * u)
		var r := float(dr.radius_m) * 0.35
		_fountain_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r * 1.6, r)), pos))


## Puts the real lights on the omni candidates nearest `eye` (lit with the lamp factor): the OMNI_COUNT smallest by
## (squared ground distance, index). By day (lamps off) every light is simply hidden, without the search.
## (unified-r4 bench: the search ran over all 376 candidates through dictionaries and a sort lambda every 0.25 s,
## a periodic frame spike; it now scans packed x/z arrays with an insertion into the short list, same result.)
func place_lights(eye: Vector3) -> void:
	var lamps := float(light.get("lamps", 0.0))
	if _omni_lamps.is_empty():
		return
	if lamps <= 0.01:
		for o: OmniLight3D in _omnis:
			o.visible = false
		return
	if _omni_xz.size() != _omni_lamps.size():
		_omni_xz.resize(_omni_lamps.size())
		for i in _omni_lamps.size():
			var lp: Vector3 = _omni_lamps[i].pos
			_omni_xz[i] = Vector2(lp.x, lp.z)
	var e2 := Vector2(eye.x, eye.z)
	var bd := PackedFloat32Array()   # the short list, ascending by (distance, index)
	var bi := PackedInt32Array()
	var count := 0
	for i in _omni_xz.size():
		var dd := (_omni_xz[i] - e2).length_squared()
		if count == OMNI_COUNT and dd >= bd[OMNI_COUNT - 1]:
			continue   # a tie keeps the lower index, as the (distance, index) order says
		var at := count if count < OMNI_COUNT else OMNI_COUNT - 1
		if count < OMNI_COUNT:
			bd.append(dd)
			bi.append(i)
			count += 1
		while at > 0 and bd[at - 1] > dd:   # i is the largest index so far: equal distances stay before it
			bd[at] = bd[at - 1]
			bi[at] = bi[at - 1]
			at -= 1
		bd[at] = dd
		bi[at] = i
	for k in _omnis.size():
		var o: OmniLight3D = _omnis[k]
		if k >= count:
			o.visible = false
			continue
		var l: Dictionary = _omni_lamps[bi[k]]
		o.visible = true
		o.position = l.pos
		o.light_color = l.colour
		o.omni_range = float(l.range)
		o.light_energy = OMNI_ENERGY * lamps


# ------------------------------------------------------------- walking

func resolve_walk(pos: Vector2, from: Variant = null) -> Vector2:
	if nav == null:
		nav = ThousandNav.shared()
	return nav.resolve(pos, from)


func height_at(pos: Vector2) -> float:
	if nav == null:
		nav = ThousandNav.shared()
	return nav.height_at(pos)


## Older tests' helper: is a body blocked at p?
static func _blocked(p: Vector2, body := BODY) -> bool:
	return ThousandNav.shared().blocked(p, body)


## Arrival slots around the forecourt's corner (town.json places.station.arrival), facing east.
const ARRIVAL_SLOTS := [Vector2(0, 0), Vector2(-1.4, 0), Vector2(0, 1.4), Vector2(-1.4, 1.4)]


func arrival(slot := 0) -> Transform3D:
	var at: Vector2 = Vector2(ThousandMap.ARRIVAL_POS.x, ThousandMap.ARRIVAL_POS.z) + ARRIVAL_SLOTS[posmod(slot, ARRIVAL_SLOTS.size())]
	at = resolve_walk(at)
	return Transform3D(Basis(Vector3.UP, Places.THOUSAND_ARRIVAL_RY), Vector3(at.x, height_at(at), at.y))


# ------------------------------------------------------------- inspection

static var _sites: Array = []


## Everything inspectable, smallest first: annexes, the street office, buildings (their whole lot), then
## the places.
static func sites() -> Array:
	if not _sites.is_empty():
		return _sites
	var d := ThousandMap.data()
	if d.is_empty():
		return _sites
	for a: Dictionary in ThousandMap.annexes():
		var door: Variant = _free_door(a.doors[0].pos, a.doors[0].facing) if not a.doors.is_empty() else null
		_sites.append(_site(str(a.id), str(a.id), str(a.name_en), "building", a.footprint, door, int(a.floors)))
	var so: Dictionary = d.get("waterfront", {}).get("street_office", {})
	if not so.is_empty():
		var sd: Array = so.get("doors", [])
		_sites.append(_site("c-civic", "c-civic", str(so.name_en), "building", ThousandMap.rect_of(so),
			_free_door(Vector2(float(sd[0].x), float(sd[0].z)), ThousandMap.v2(sd[0].facing)) if not sd.is_empty() else null, 1))
	for b: Dictionary in ThousandMap.buildings():
		var door: Variant = _free_door(b.doors[0].pos, b.doors[0].facing) if not b.doors.is_empty() else null
		_sites.append(_site(ledger_id(str(b.id)), str(b.id), str(b.name_en), "building", b.record, door, int(b.floors)))
	var places: Dictionary = d.get("places", {})
	for key in ["station", "amusement", "plaza"]:
		if places.has(key):
			_sites.append(_site("c-" + key, "place-" + key, str(places[key].get("name_en", key)), "place", ThousandMap.rect_of(places[key]), null, 0))
	var park_ids := {"park-0": "c-park-a", "park-1": "c-park-b", "sports": "sports"}
	for p: Dictionary in places.get("parks", []):
		_sites.append(_site(str(park_ids.get(str(p.id), str(p.id))), str(p.id), "Park", "place", ThousandMap.rect_of(p), null, 0))
	for pr: Dictionary in d.get("promenade", []):
		_sites.append(_site("c-night-market", "promenade", "Night Market", "place", ThousandMap.rect_of(pr), null, 0))
	return _sites


## Where a child stands to use a door: town.json's point, or, where the world layer's body or a lamp covers
## it (the annexes' entries, the street office), the first free point straight out from the door.
static func _free_door(pos: Vector2, facing: Vector2) -> Vector2:
	var nav := ThousandNav.shared()
	for k in 31:
		var q := pos + facing * 0.1 * float(k)
		if not nav.blocked(q):
			return q
	return nav.push_out(pos)


static func _site(id: String, mid: String, name_en: String, kind: String, rect: Rect2, door: Variant, floors: int) -> Dictionary:
	var sim_index := -1
	var Data = Sim.Data
	for i in Data.BUILDINGS.size():
		if str(Data.BUILDINGS[i].id) == id:
			sim_index = i
			break
	return {"id": id, "map_id": mid, "sim": sim_index, "name": str(NAMES.get(id, name_en)), "kind": kind,
		"rect": rect, "door": door, "floors": floors}


func building_at(pos: Vector2) -> Dictionary:
	for s: Dictionary in sites():
		if (s.rect as Rect2).has_point(pos):
			return s.duplicate()
	return {}


## unified r6 (the Mac's 1080p touch run): the building a finger's ray meets first, as a box over its footprint as
## tall as its storeys, if that is nearer than `max_t` (where the ray meets the walkable ground); else {}. A tap on a
## facade meets the ground behind it, inside the footprint; re-aimed at the ground's height there (for the bridges)
## that point could fall just outside it, and the tap walked into the wall instead of asking who is there.
func building_on_ray(from: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var best := {}
	var best_t := max_t + 0.01
	for s: Dictionary in sites():
		if str(s.get("kind", "")) != "building" or int(s.get("floors", 0)) <= 0:
			continue
		var r: Rect2 = s.rect
		var box := AABB(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, STOREY * int(s.floors), r.size.y))
		if box.has_point(from):
			continue   # the camera pulled in over a courtyard: not a building in front of it
		var hit: Variant = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var t: float = ((hit as Vector3) - from).dot(dir)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = s.duplicate()
	return best


func door_near(pos: Vector2, r: float) -> Dictionary:
	var best := {}
	var best_d := r
	for s: Dictionary in sites():
		if not s.door is Vector2:
			continue
		var d := pos.distance_to(s.door)
		if d <= best_d:
			best_d = d
			best = s.duplicate()
	return best


## The door point of a building (ledger id, town.json id or a placeholder alias): where a child stands to
## use it (0.5 m outside its gate, lobby or entrance).
static func door_point(id: String) -> Vector2:
	id = BUILDINGS.get(id, id)
	for s: Dictionary in sites():
		if (s.id == id or s.map_id == id) and s.door is Vector2:
			return s.door
	return Vector2.INF


## A building's lot rect (ledger id, town.json id or alias).
static func _rect(id: Variant) -> Rect2:
	var key := str(id)
	key = BUILDINGS.get(key, key)
	for s: Dictionary in sites():
		if s.id == key or s.map_id == key:
			return s.rect
	return Rect2()


# ------------------------------------------------------------- the camera's occluders

func occluders() -> Array:
	return _boxes


## What each occluder is: {"id" (ledger id), "kind"}.
func occluder_info(i: int) -> Dictionary:
	return _box_info[i] if i >= 0 and i < _box_info.size() else {}


func set_occluded(ids: Array) -> void:
	_occluded = ids.duplicate()
	var mins := PackedVector3Array()
	var maxs := PackedVector3Array()
	for id in ids:
		if mins.size() >= 4:
			break
		var i := int(id)
		if i < 0 or i >= _boxes.size():
			continue
		var b: AABB = (_boxes[i] as AABB).grow(DITHER_GROW)
		mins.append(b.position)
		maxs.append(b.end)
	var n := mins.size()
	while mins.size() < 4:
		mins.append(Vector3.ZERO)
		maxs.append(Vector3.ZERO)
	for m: ShaderMaterial in _dither_mats:
		m.set_shader_parameter("occ_count", n)
		m.set_shader_parameter("occ_min", mins)
		m.set_shader_parameter("occ_max", maxs)


func occluded() -> Array:
	return _occluded
