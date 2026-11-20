## Close, gently tilted follow camera (design direction A) with 45-degree turns
## and two zoom levels. Inside cottages it frames the dollhouse cut-away room.
extends Node3D

const PlacementDock := preload("res://scripts/ui/placement_dock.gd")
const PITCH := deg_to_rad(40.0)
const ZOOMS := [9.5, 15.0]
## The zoo only (zoo standard section 5): three zooms, the default in the middle.
const ZOO_ZOOMS := [8.0, 9.5, 15.0]
const ZOO_DEFAULT := 1
const ROOM_DISTANCE := 11.0
const FOV := 42.0

var camera: Camera3D
var target: Node3D
var yaw_step := 0
var zoom := 0
var in_room := false
## True while the child is on the zoo map: three zooms, and the town's turn and zoom are kept aside.
var on_zoo := false
## city r1: the city's free orbit camera (world/city_orbit.gd). While on_city the rig keeps an orbit state
## ({yaw, pitch, distance, out}) instead of the 45 degree turns and fixed zooms; it opens on the overview.
const CityOrbit := preload("res://scripts/world/city_orbit.gd")
var on_city := false
var city_state: Dictionary = {}
var _city_cur: Dictionary = {}
## city r2, Look: the place being looked at ("" while playing) and its own orbit around that place's focus
## ({yaw, pitch, distance, out: false, focus}). Every change of view glides (_glide_*), never snaps.
const CityMapR := preload("res://scripts/core/city_map.gd")
var city_look := ""
var city_look_view: Dictionary = {}
var _glide_from: Dictionary = {}
var _glide_t := 0.0
var _glide_dur := 0.0
## thousand-town (design/thousand-town.md section 6): a follow camera at the child's height. Behind the child
## about T_DIST m away and T_HEIGHT m up, looking slightly down so the child sits in the lower third; it eases
## behind the child after the child's turns (only while the child walks, and not for T_MANUAL_HOLD s after a
## drag or stick orbit). A drag or the right stick orbits around the child, a pinch, the wheel or the triggers
## zoom (T_MIN..T_MAX m). The camera is pulled in by a sphere cast (radius T_SPHERE) against the world's
## occluders(), never closer than T_PULL_MIN; the occluders still between the camera and the child go to the
## world's set_occluded(ids) for dithering. Look flies to an overview of the whole town and back (T_GLIDE s).
const T_DIST := 7.0
const T_HEIGHT := 2.6
const T_CHEST := 0.9
const T_MIN := 4.0
const T_MAX := 18.0
const T_ZOOM_LEVELS := [7.0, 12.0, 18.0, 4.0]
const T_FOLLOW_RATE := 2.0
const T_MANUAL_HOLD := 1.5
const T_ORBIT_PER_PX := 0.006
const T_STICK_RATE := 2.4   # radians per second at full tilt
const T_SPHERE := 0.25   # under the child's walking body (0.28), so a child at a wall never has its chest inside a grown box
## Never nearer than the closest zoom: at 2.5 m the child's head filled the picture against a wall (EC2 frame
## 07_occluded_day). A wall the camera then stands inside is in the occluded set, so the world dithers it away.
const T_PULL_MIN := 4.0
const T_GLIDE := 1.2
const T_NEAR := 0.1
const T_FAR := 600.0
## TODO(lead): upstream's "home" view of the whole town (study-scene.md / thousand_map.gd) once known; this
## placeholder looks at the board's middle from the south-east, high enough to show all of it.
const T_OVERVIEW_EYE := Vector3(120.0, 210.0, 230.0)
const T_OVERVIEW_AT := Vector3(0.0, 0.0, 10.0)
var on_thousand := false
var thousand_world: Node3D = null
var t_yaw := 0.0                # the camera's yaw around the child (pose_xform's convention: offset (sin, cos))
var t_dist := T_DIST
var t_overview := false
var _t_ov := 0.0                # 0 following .. 1 overview (glides)
var _t_manual := 0.0
var _t_last := Vector3.INF
var _t_pull := INF              # the pulled-in distance along the chest-camera line now
var _t_occluded: Array = []
var t_last_xform := Transform3D()   # the follow pose before the overview blend (tests read it)
## A held view (Thousand Town's interactions: the ferris wheel's view over the town, watching the fireworks or the
## fountain): a Transform3D the camera glides to (T_GLIDE s) and holds while set; null glides back to following.
## The caller may move it every frame (the wheel turns).
var t_watch: Variant = null
var _t_w := 0.0
var _t_watch_last := Transform3D()
## unified r4 (Apple TV feedback, "Ferris wheel camera adjustment"): while t_watch_free is on (the ferris wheel), a
## drag, the right stick, L / R and the zoom adjust the held view itself (look around from the cabin: yaw and pitch
## offsets, a narrower or wider view), within limits. Before, they turned and zoomed the hidden follow camera behind
## the held view: nothing moved on screen, and the follow camera came back elsewhere when the ride ended. The
## offsets reset when the held view ends.
var t_watch_free := false
var t_watch_yaw := 0.0
var t_watch_pitch := 0.0
var t_watch_fov := 0.0          # degrees added to FOV (negative: closer)
const T_WATCH_YAW_MAX := 1.4    # radians each way
const T_WATCH_PITCH_MIN := -0.7
const T_WATCH_PITCH_MAX := 0.35
const T_WATCH_FOV_MIN := -16.0
const T_WATCH_FOV_MAX := 10.0
## With on_zoo: turns and zooms snap instead of gliding.
var reduce_motion := false
var _town_yaw_step := 0
var _town_zoom := 0
var _yaw := 0.0
var _focus := Vector3.ZERO
var _distance: float = ZOOMS[0]
var _focus_override: Variant = null
## Look (design/zoo-and-world-journeys.md 11.1): an animal this child is looking at, and its head
## height. The focus moves at most LOOK_SHIFT toward the head along the ground; the camera steps
## back (never beyond 15 m) if head and child do not both fit. Angle, pitch and field of view stay.
var look_node: Node3D = null
var look_height := 1.5
const LOOK_SHIFT := 2.5
const LOOK_TOP := 104.0
## Node to look at instead of the child, e.g. an item being placed.
var follow: Node3D
## While true the camera does not move at all (a finger is dragging an item).
var hold := false
## While an item is followed: the part of the screen it should rest in, and the item's size
## (x: radius, y: height). The HUD gives the room between the two places its placement tools can
## take (first-steps r8); the item's top edge rests at the top of that room, and the camera steps
## back when the item is taller or wider than the room. With no frame the item rests where it did
## until r7 (a little above the middle of the screen).
var frame := Rect2()
var frame_box := Vector2.ZERO
## How far apart the tools' two places are on screen while a thing is held (0: not known), and the
## lowest place on screen a child's feet can be (the bottom of the low place). The camera steps back
## until a child standing there fits between the two places (frame_fit).
var frame_gap := 0.0
var frame_feet := 0.0
## The child as frame_fit measures it: a ring of this radius at the feet and at 1.85 m, 10 px around.
## At 9.5 m with the feet at the bottom of the safe area this is 318 to 320 px where the child's own meshes
## and name tag measure 297 to 300 px (EC2, the TV and iPad Air layouts): a little larger, never smaller.
## (The HUD's own box for the child, radius 0.45 m, measures about 385 px there: the ring at head height,
## seen from above, adds height.)
const KID_RADIUS := 0.25
## How far the camera may step back to fit a tall item into the frame.
const FRAME_MAX_DISTANCE := 30.0
## Inside a cottage (first-steps r9, review D2) the room camera keeps its dollhouse view while a thing is
## held: the same turn and the same focus. The HUD gives the tools' two places as they are judged
## (PlacementDock.choose_place: the low place with the strip of the screen at its height, the top place)
## and how a held thing's box starts (its anchor: a wall or ceiling thing hangs below its origin). When the
## thing and the player's own child leave neither place free, the camera steps straight back until one is
## free (room_fit). Stepping back only draws the room smaller around the middle of the screen, so whatever
## was on screen stays on screen. Without such a conflict the room view is the one it was before r9.
## (r8 measured the fixed room view: the tools lay on the child at 20 to 30 of 132 spots per layout,
## always with the thing and the child on opposite places.)
var frame_low := Rect2()
var frame_top := Rect2()
var frame_strip := Rect2()
var frame_anchor := "ground"
## Indoors the held thing keeps this far from the tools, as it keeps FRAME_GAP (hud.gd, 24 px) from both
## places outdoors: its box is a ring of its catalog radius, and its meshes can reach a few pixels past
## that (r9 development: the tools 2 to 4 px into a table and a bird mobile measured from their meshes).
## The HUD grows the thing's box by the same before it chooses the place.
const ROOM_THING_GAP := 24.0
## Indoors the held thing also rests whole inside the safe area (first-steps r10): the HUD gives that area
## here, and room_fit steps back until the thing's box, SAFE_GAP around it, lies inside it. r9 left part of
## a painting held at the left wall's front end past the iPad's left edge (Mac review, room47-all-ipad shot
## 08). The box is a ring of the catalog radius; its meshes reach a few pixels past it (see ROOM_THING_GAP).
var frame_safe := Rect2()
const SAFE_GAP := 8.0
## The HUD's own box for the child (hud.gd, avatar_screen_rect and placement_rects).
const KID_BOX_RADIUS := 0.45
const KID_BOX_HEIGHT := 1.85


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.2
	camera.far = 220.0
	add_child(camera)
	camera.current = true


func rotate_step(dir: int) -> void:
	if _watch_adjusting():
		_watch_turn(dir * TAU / 16.0, 0.0)
		return
	if on_thousand:
		t_yaw += dir * TAU / 8.0
		_t_manual = T_MANUAL_HOLD
		return
	if on_city:
		city_state = CityOrbit.step_yaw(city_state, dir)
		_snap_if_reduced()
		return
	if not in_room:
		yaw_step = posmod(yaw_step + dir, 8)
		_snap_if_reduced()


func toggle_zoom() -> void:
	if on_thousand:
		var i := 0
		for k in T_ZOOM_LEVELS.size():
			if is_equal_approx(t_dist, float(T_ZOOM_LEVELS[k])):
				i = k + 1
		t_dist = float(T_ZOOM_LEVELS[i % T_ZOOM_LEVELS.size()])
		return
	if on_city:
		# The zoom button steps closer, and from the closest level back out to the overview.
		# tv-diag r2 (audit finding 7): +1 is closer (CityOrbit.step_zoom); it used -1, so from the strolling view
		# it only zoomed out and then stayed on the overview.
		var before: float = float(city_state["distance"])
		city_state = CityOrbit.step_zoom(city_state, 1, _aspect())
		if is_equal_approx(float(city_state["distance"]), before):
			city_state = CityOrbit.reset(_aspect())
		_snap_if_reduced()
		return
	if on_zoo:
		# 9.5 -> 15 -> 8 -> 9.5
		zoom = int([1, 2, 0][clampi(zoom, 0, 2)])
	else:
		zoom = 1 - zoom
	_snap_if_reduced()


## The distance of the current zoom (the zoo has three zooms, everywhere else two).
func distance() -> float:
	var levels: Array = ZOO_ZOOMS if on_zoo else ZOOMS
	return float(levels[clampi(zoom, 0, levels.size() - 1)])


## One zoom level closer / farther, clamped. In town the two zooms are 0 (close) and 1 (wide).
func zoom_in() -> void:
	if on_thousand:
		thousand_zoom(1.25)
		return
	if on_city:
		city_step_zoom(1)   # CityOrbit.step_zoom: +1 is one level closer
		return
	zoom = maxi(zoom - 1, 0)
	_snap_if_reduced()


func zoom_out() -> void:
	if on_thousand:
		thousand_zoom(0.8)
		return
	if on_city:
		city_step_zoom(-1)
		return
	zoom = mini(zoom + 1, (ZOO_ZOOMS.size() if on_zoo else ZOOMS.size()) - 1)
	_snap_if_reduced()


## Arriving on the zoo map: the designed view (north, 9.5 m); the town's turn and zoom are kept.
func enter_zoo() -> void:
	if not on_zoo:
		_town_yaw_step = yaw_step
		_town_zoom = zoom
	on_zoo = true
	yaw_step = 0
	zoom = ZOO_DEFAULT
	snap()


## Back in town: its own turn and zoom come back.
func leave_zoo() -> void:
	if on_zoo:
		yaw_step = _town_yaw_step
		zoom = _town_zoom
	on_zoo = false
	snap()


func _snap_if_reduced() -> void:
	if (on_zoo or on_city) and reduce_motion and camera != null and camera.is_inside_tree():
		snap()


# ------------------------------------------------------------- the city's orbit camera (city r1)

func _aspect() -> float:
	var v := view_size()
	return v.x / maxf(v.y, 1.0)


## Arriving in the city: the strolling view that follows the child (dest-fix r1; before, the overview of the
## whole block, where the child was a 13 px figure). The town's turn and zoom are kept for later.
func enter_city() -> void:
	if not on_city:
		_town_yaw_step = yaw_step
		_town_zoom = zoom
	on_city = true
	city_state = CityOrbit.stroll(_aspect())
	city_look = ""
	city_look_view = {}
	_glide_from = {}
	_city_cur = {}
	snap()


func leave_city() -> void:
	if on_city:
		yaw_step = _town_yaw_step
		zoom = _town_zoom
	on_city = false
	city_state = {}
	city_look = ""
	city_look_view = {}
	_glide_from = {}
	_city_cur = {}
	snap()


## A drag on empty ground (px since the last move) orbits; a pinch or the wheel zooms; Reset view returns.
func city_orbit(delta_px: Vector2) -> void:
	if on_city and city_look != "":
		_look_keep_focus(CityOrbit.orbit(city_look_view, delta_px, view_size().y, _aspect()))
	elif on_city:
		city_state = CityOrbit.orbit(city_state, delta_px, view_size().y, _aspect())
		_snap_if_reduced()


## city r3: a right drag pans the view over the block (bounded; Reset view and Look clear it).
func city_pan(delta_px: Vector2) -> void:
	if on_city and city_look != "":
		city_look_view = CityOrbit.pan(city_look_view, delta_px, view_size().y, _aspect())
	elif on_city:
		city_state = CityOrbit.pan(city_state, delta_px, view_size().y, _aspect())
		_snap_if_reduced()


func city_zoom(factor: float) -> void:
	if on_city and city_look != "":
		_look_keep_focus(CityOrbit.zoom(city_look_view, factor, _aspect()))
	elif on_city:
		city_state = CityOrbit.zoom(city_state, factor, _aspect())
		_snap_if_reduced()


func city_step_zoom(dir: int) -> void:
	if on_city and city_look != "":
		_look_keep_focus(CityOrbit.step_zoom(city_look_view, dir, _aspect()))
	elif on_city:
		city_state = CityOrbit.step_zoom(city_state, dir, _aspect())
		_snap_if_reduced()


## Reset view: a glide back to the strolling view that follows the child (from Look too; dest-fix r1).
func city_reset() -> void:
	if on_city:
		city_look = ""
		city_look_view = {}
		city_state = CityOrbit.stroll(_aspect())
		_start_glide()


## The overview of the whole block (the zoom-out end; tests use it to pick places on the whole block).
func city_overview() -> void:
	if on_city:
		city_look = ""
		city_look_view = {}
		city_state = CityOrbit.reset(_aspect())
		_start_glide()


## Look off (dest-fix r1): a glide back to the strolling view, the child again (a tap on empty space while
## looking still glides out to the overview with city_look_out).
func city_stroll() -> void:
	if on_city:
		city_look = ""
		city_look_view = {}
		city_state = CityOrbit.stroll(_aspect())
		_start_glide()


## Look (city r2): glide in to a place of CityMap.LOOK_PLACES, framed so the people inside show.
func city_look_at(key: String) -> void:
	if not on_city or not CityMapR.LOOK_PLACES.has(key):
		return
	city_look = key
	city_look_view = CityOrbit.look_state(key, _aspect())   # framed for this screen's shape
	_start_glide()


## Leaving a place (a tap on empty space, Esc, B, Look off): a glide back to the overview.
func city_look_out() -> void:
	if on_city:
		city_look = ""
		city_look_view = {}
		city_state = CityOrbit.reset(_aspect())
		_start_glide()


## True while a glide is under way (tests and the HUD wait for it).
func city_gliding() -> bool:
	return not _glide_from.is_empty()


func _look_keep_focus(st: Dictionary) -> void:
	var focus: Vector3 = city_look_view["focus"]
	var pan: Vector3 = city_look_view.get("pan", Vector3.ZERO)
	city_look_view = st
	city_look_view["focus"] = focus
	city_look_view["pan"] = pan
	city_look_view["out"] = false


func _start_glide() -> void:
	if _city_cur.is_empty():
		return
	_glide_from = _city_cur.duplicate()
	_glide_t = 0.0
	_glide_dur = 0.25 if reduce_motion else float(CityMapR.LOOK_GLIDE)



func _update_city(k: float, dt: float) -> void:
	var child := target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var goal := CityOrbit.pose(city_state, _aspect(), child)
	if city_look != "" and not city_look_view.is_empty():
		goal = CityOrbit.pose(city_look_view, _aspect(), child)   # a state with its own focus keeps it
	if not _glide_from.is_empty():
		_glide_t += dt
		var u := clampf(_glide_t / maxf(_glide_dur, 0.01), 0.0, 1.0)
		_city_cur = CityOrbit.glide(_glide_from, goal, u)
		if u >= 1.0:
			_glide_from = {}
	elif _city_cur.is_empty() or k >= 1.0:
		_city_cur = goal
	else:
		_city_cur = CityOrbit.smooth(_city_cur, goal, dt, reduce_motion)
	var xf: Transform3D = _city_cur["xform"]
	_yaw = float(_city_cur["yaw"])   # the stick and keys walk relative to the view, as everywhere
	_distance = float(_city_cur["distance"])
	_focus = _city_cur["focus"]
	camera.global_position = xf.origin
	camera.global_basis = xf.basis


# ------------------------------------------------------------- Thousand Town's follow camera

## Arriving in Thousand Town: behind the child (facing `child_ry`), at the usual distance, the far plane at
## 600 m. The town's turn and zoom are kept for later.
func enter_thousand(world_node: Node3D, child_ry: float) -> void:
	if not on_thousand:
		_town_yaw_step = yaw_step
		_town_zoom = zoom
	on_thousand = true
	thousand_world = world_node
	t_yaw = child_ry + PI
	t_dist = T_DIST
	t_overview = false
	_t_ov = 0.0
	t_watch = null
	_t_w = 0.0
	_t_manual = 0.0
	_t_last = Vector3.INF
	_t_pull = INF
	_t_occluded = []
	if camera:
		camera.near = T_NEAR
		camera.far = T_FAR
	snap()


func leave_thousand() -> void:
	if on_thousand:
		yaw_step = _town_yaw_step
		zoom = _town_zoom
		if thousand_world and is_instance_valid(thousand_world) and not _t_occluded.is_empty():
			thousand_world.set_occluded([])
	on_thousand = false
	thousand_world = null
	t_overview = false
	t_watch = null
	_t_w = 0.0
	_t_occluded = []
	if camera:
		camera.near = 0.2
		camera.far = 220.0
	snap()


## A drag (px since the last move) orbits around the child.
func thousand_orbit(delta_px: Vector2) -> void:
	if _watch_adjusting():
		_watch_turn(-delta_px.x * T_ORBIT_PER_PX, -delta_px.y * T_ORBIT_PER_PX)
		return
	if on_thousand:
		t_yaw -= delta_px.x * T_ORBIT_PER_PX
		_t_manual = T_MANUAL_HOLD


## The controller's right stick (deadzoned, length <= 1) orbits for `dt` seconds.
func thousand_orbit_stick(v: Vector2, dt: float) -> void:
	if _watch_adjusting() and v != Vector2.ZERO:
		_watch_turn(-v.x * T_STICK_RATE * dt, -v.y * T_STICK_RATE * 0.6 * dt)
		return
	if on_thousand and v != Vector2.ZERO:
		t_yaw -= v.x * T_STICK_RATE * dt
		_t_manual = T_MANUAL_HOLD


## A pinch: a factor above 1 comes closer.
func thousand_zoom(factor: float) -> void:
	if _watch_adjusting() and factor > 0.0:
		t_watch_fov = clampf(t_watch_fov - 12.0 * log(factor) / log(1.25), T_WATCH_FOV_MIN, T_WATCH_FOV_MAX)
		return
	if on_thousand and factor > 0.0:
		t_dist = clampf(t_dist / factor, T_MIN, T_MAX)


## The held view is on screen and may be adjusted (the ferris wheel).
func _watch_adjusting() -> bool:
	return on_thousand and t_watch_free and t_watch is Transform3D


func _watch_turn(dyaw: float, dpitch: float) -> void:
	t_watch_yaw = clampf(t_watch_yaw + dyaw, -T_WATCH_YAW_MAX, T_WATCH_YAW_MAX)
	t_watch_pitch = clampf(t_watch_pitch + dpitch, T_WATCH_PITCH_MIN, T_WATCH_PITCH_MAX)


## The held view with the look-around offsets applied (yaw about the world's up, then pitch about the view's right).
func watch_adjusted(w: Transform3D) -> Transform3D:
	if not t_watch_free or (is_zero_approx(t_watch_yaw) and is_zero_approx(t_watch_pitch)):
		return w
	var b := Basis(Vector3.UP, t_watch_yaw) * w.basis.orthonormalized()
	b = Basis(b.x.normalized(), t_watch_pitch) * b
	return Transform3D(b.orthonormalized(), w.origin)


## Look: fly to the overview of the whole town (on) or back behind the child (off).
func thousand_set_overview(on: bool) -> void:
	if on_thousand:
		t_overview = on
		if reduce_motion:
			_t_ov = 1.0 if on else 0.0


## True while the Look glide (or the glide to or from a held view) is under way.
func thousand_gliding() -> bool:
	return on_thousand and (not is_equal_approx(_t_ov, 1.0 if t_overview else 0.0) \
		or not is_equal_approx(_t_w, 1.0 if t_watch is Transform3D else 0.0))


## The follow pose for a child at `child` with the camera at yaw `yaw` and distance `dist` (not pulled in):
## T_HEIGHT m up at T_DIST (the height scales with the distance, so the look-down stays), looking above the
## chest by the angle that puts the chest on the lower third of the picture.
static func follow_xform(child: Vector3, yaw: float, dist: float) -> Transform3D:
	var h := T_CHEST + (T_HEIGHT - T_CHEST) * dist / T_DIST
	var eye := child + Vector3(sin(yaw) * dist, h, cos(yaw) * dist)
	var down := atan2(h - T_CHEST, dist)   # from the eye down to the chest
	var pitch := down - atan(tan(deg_to_rad(FOV) * 0.5) / 3.0)
	var fwd := Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), eye)


static func overview_xform() -> Transform3D:
	return Transform3D(Basis.looking_at((T_OVERVIEW_AT - T_OVERVIEW_EYE).normalized(), Vector3.UP), T_OVERVIEW_EYE)


## Where a sphere of `radius` moving from `from` to `to` first touches one of `boxes` (AABBs), as a distance
## from `from` (the whole length when it touches none). A box the start point is inside is ignored.
static func sphere_cast(from: Vector3, to: Vector3, boxes: Array, radius := T_SPHERE) -> float:
	var seg := to - from
	var length := seg.length()
	if length < 0.0001:
		return length
	var best := length
	for b: AABB in boxes:
		var g := b.grow(radius)
		if g.has_point(from):
			continue
		var t = _segment_enter(from, seg, g)
		if t != null:
			best = minf(best, float(t) * length)
	return best


## The fraction (0..1) of `seg` from `from` where it enters `box`, or null when it misses (the slab method).
static func _segment_enter(from: Vector3, seg: Vector3, box: AABB) -> Variant:
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		var o := from[i]
		var d := seg[i]
		var lo := box.position[i]
		var hi := box.end[i]
		if absf(d) < 1e-9:
			if o < lo or o > hi:
				return null
			continue
		var a := (lo - o) / d
		var c := (hi - o) / d
		if a > c:
			var tmp := a
			a = c
			c = tmp
		t0 = maxf(t0, a)
		t1 = minf(t1, c)
		if t0 > t1:
			return null
	return t0


## The distance the camera keeps along the chest-to-eye line: the sphere cast's, never under T_PULL_MIN
## (nor over the whole line).
static func pull_in(chest: Vector3, eye: Vector3, boxes: Array) -> float:
	var length := chest.distance_to(eye)
	var hit := sphere_cast(chest, eye, boxes)
	if hit >= length:
		return length   # nothing in the way
	return minf(length, maxf(T_PULL_MIN, hit - 0.05))


## The ids (indices into `boxes`) of the boxes the line from `a` to `b` passes through.
static func blocking(a: Vector3, b: Vector3, boxes: Array) -> Array:
	var out := []
	for i in boxes.size():
		var box: AABB = boxes[i]
		if box.has_point(a):
			continue
		if _segment_enter(a, b - a, box) != null:
			out.append(i)
	return out


func _update_thousand(k: float, dt: float) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var child := target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var moving := _t_last != Vector3.INF and Vector2(child.x - _t_last.x, child.z - _t_last.z).length() > 0.002
	_t_last = child
	_t_manual = maxf(0.0, _t_manual - dt)
	# unified r5 (Mac, thousand_pad_tour on r4): while a held view is on screen (the ferris wheel, a show) the child is
	# carried, not walking; the hidden follow camera behind the held view must not steer after it, or it drifts and
	# the view comes back elsewhere when the hold ends. It resumes following when the hold ends.
	var held := t_watch is Transform3D
	if moving and not held and _t_manual <= 0.0 and target != null and is_instance_valid(target):
		var behind: float = target.global_rotation.y + PI
		t_yaw = lerp_angle(t_yaw, behind, 1.0 if reduce_motion else 1.0 - exp(-T_FOLLOW_RATE * dt))
	var xf := follow_xform(child, t_yaw, t_dist)
	var chest := child + Vector3(0, T_CHEST, 0)
	var boxes: Array = thousand_world.occluders() if thousand_world and is_instance_valid(thousand_world) else []
	var full := chest.distance_to(xf.origin)
	var allowed := pull_in(chest, xf.origin, boxes)
	if k >= 1.0 or allowed < _t_pull or _t_pull == INF:
		_t_pull = allowed   # pulled in at once (never through a wall), let out again smoothly
	else:
		_t_pull = lerpf(_t_pull, allowed, 1.0 - exp(-4.0 * dt))
	if _t_pull < full:
		xf.origin = chest + (xf.origin - chest) / full * _t_pull
	t_last_xform = xf
	var occ := blocking(chest, xf.origin, boxes)
	if occ != _t_occluded:
		_t_occluded = occ
		if thousand_world and is_instance_valid(thousand_world) and thousand_world.has_method("set_occluded"):
			thousand_world.set_occluded(occ)
	var goal := 1.0 if t_overview else 0.0
	if k >= 1.0:
		_t_ov = goal
	else:
		_t_ov = move_toward(_t_ov, goal, dt / T_GLIDE)
	var out := xf
	if _t_ov > 0.0:
		var u := smoothstep(0.0, 1.0, _t_ov)
		var ov := overview_xform()
		out = Transform3D(xf.basis.slerp(ov.basis, u), xf.origin.lerp(ov.origin, u))
	if t_watch is Transform3D:
		_t_watch_last = watch_adjusted(t_watch)
	else:
		t_watch_yaw = 0.0   # the held view ended: its adjustments go with it
		t_watch_pitch = 0.0
		t_watch_fov = 0.0
		t_watch_free = false
	if camera:
		camera.fov = FOV + (t_watch_fov * _t_w if t_watch_free or _t_w > 0.0 else 0.0)
	var wgoal := 1.0 if t_watch is Transform3D else 0.0
	_t_w = wgoal if k >= 1.0 or reduce_motion else move_toward(_t_w, wgoal, dt / T_GLIDE)
	if _t_w > 0.0:
		var uw := smoothstep(0.0, 1.0, _t_w)
		out = Transform3D(out.basis.orthonormalized().slerp(_t_watch_last.basis.orthonormalized(), uw), out.origin.lerp(_t_watch_last.origin, uw))
	_yaw = t_yaw   # the stick and keys walk relative to the view, as everywhere
	_distance = t_dist
	_focus = chest
	camera.global_position = out.origin
	camera.global_basis = out.basis


func set_room(on: bool) -> void:
	in_room = on
	snap()


## Temporarily look at a point (celebrations), then return to the child.
func peek(point: Vector3, seconds := 2.5) -> void:
	_focus_override = point
	get_tree().create_timer(seconds).timeout.connect(func(): _focus_override = null)


func snap() -> void:
	if on_thousand:
		if camera != null and camera.is_inside_tree():
			_t_pull = INF
			_t_ov = 1.0 if t_overview else 0.0
			_update_thousand(1.0, 0.0)
		return
	if on_city:
		_glide_from = {}   # a snap is "be there now" (arrivals, tests): it ends any glide
		if camera != null and camera.is_inside_tree():
			_update_city(1.0, 0.0)
		return
	_update(1.0)


func _process(delta: float) -> void:
	if on_thousand:
		_update_thousand(0.0, delta)
		return
	if on_city:
		_update_city(0.0, delta)
		return
	if not hold:
		_update(minf(1.0, delta * 4.0))


func _update(k: float) -> void:
	if on_zoo and reduce_motion:
		k = 1.0
	var goal := goal_pose()
	_yaw = lerp_angle(_yaw, goal["yaw"], k)
	_distance = lerpf(_distance, goal["distance"], k)
	_focus = _focus.lerp(goal["focus"], k)
	var xf := pose_xform(_focus, _yaw, _distance)
	camera.global_position = xf.origin
	camera.global_basis = xf.basis


## Where the camera is going: {yaw, distance, focus}. It is there once it has come to rest.
func goal_pose() -> Dictionary:
	var goal_yaw: float
	var goal_dist: float
	var goal_focus: Vector3
	if in_room:
		goal_yaw = deg_to_rad(28.0)
		goal_dist = ROOM_DISTANCE
		goal_focus = Vector3(0, 0.4, 0.3)
		if target:
			goal_focus = goal_focus.lerp(Vector3(target.global_position.x, 0.4, target.global_position.z), 0.25)
		if is_instance_valid(follow) and frame_box.y > 0.0 and frame_low.has_area() and frame_top.has_area():
			var kid: Variant = null
			if is_instance_valid(target) and target.is_visible_in_tree():
				kid = target.global_position
			var base := PlacementDock.box_base(follow.global_position, frame_box.y, frame_anchor)
			goal_dist = room_fit(base, frame_box.x, frame_box.y, kid, goal_yaw, goal_dist, goal_focus, frame_low, frame_top, frame_strip, view_size(), frame_safe)
	else:
		goal_yaw = yaw_step * TAU / 8.0
		goal_dist = distance()
		var t := follow if is_instance_valid(follow) else target
		goal_focus = (t.global_position if t else Vector3.ZERO) + Vector3(0, 0.6, 0)
		if is_instance_valid(follow):
			# Aim a little in front of the item so it shows above the middle of the screen.
			goal_focus += Vector3(sin(goal_yaw), 0, cos(goal_yaw)) * goal_dist * 0.32
			if frame.has_area() and frame_box.y > 0.0:
				var fit := frame_fit(follow.global_position, frame_box.x, frame_box.y, goal_yaw, goal_dist, goal_focus, frame, view_size(), frame_gap, frame_feet)
				goal_focus = fit["focus"]
				goal_dist = fit["distance"]
	if not in_room and not is_instance_valid(follow) and is_instance_valid(look_node):
		var head := look_node.global_position + Vector3(0, look_height, 0)
		var shift := Vector3(head.x - goal_focus.x, 0, head.z - goal_focus.z) * 0.5
		if shift.length() > LOOK_SHIFT:
			shift = shift.normalized() * LOOK_SHIFT
		goal_focus += shift
		var view := view_size()
		while goal_dist < 15.0:
			var xf := pose_xform(goal_focus, goal_yaw, goal_dist)
			var hp: Variant = project(xf, view, head)
			if hp != null and (hp as Vector2).y >= LOOK_TOP:
				break
			goal_dist = minf(15.0, goal_dist + 0.5)
	if _focus_override != null:
		goal_focus = _focus_override
	return {"yaw": goal_yaw, "distance": goal_dist, "focus": goal_focus}


## The camera's place and direction for a focus point, a turn and a distance.
static func pose_xform(focus: Vector3, yaw: float, distance: float) -> Transform3D:
	var offset := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH)) * distance
	return Transform3D(Basis.looking_at(-offset.normalized(), Vector3.UP), focus + offset)


## The camera's pose once it has come to rest (what the HUD plans with while the camera glides).
func rest_xform() -> Transform3D:
	var goal := goal_pose()
	return pose_xform(goal["focus"], goal["yaw"], goal["distance"])


func view_size() -> Vector2:
	return camera.get_viewport().get_visible_rect().size if camera != null and camera.is_inside_tree() else Vector2(1920, 1080)


## Where a point in the world shows on screen for a camera pose; null when it is behind the camera.
## The same picture as Camera3D.unproject_position gives for that pose (checked in the tours).
static func project(xf: Transform3D, view: Vector2, p: Vector3) -> Variant:
	var v := xf.affine_inverse() * p
	if v.z > -0.05:
		return null
	var half := tan(deg_to_rad(FOV) * 0.5)
	return Vector2(view.x * 0.5 + v.x / (-v.z * half) * view.y * 0.5, view.y * 0.5 - v.y / (-v.z * half) * view.y * 0.5)


## What an item's footprint and height cover on screen for a camera pose (the same points and margin
## as PlacementDock.ghost_rect); an empty rectangle when all of it is behind the camera.
static func box_rect(xf: Transform3D, view: Vector2, center: Vector3, radius: float, height: float) -> Rect2:
	var r := Rect2()
	var first := true
	for i in 8:
		var a := TAU * i / 8.0
		for h in [0.0, height]:
			var s = project(xf, view, center + Vector3(cos(a) * radius, h, sin(a) * radius))
			if s == null:
				continue
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
	return r.grow(10.0) if not first else Rect2()


## The focus point and distance that rest an item's box with its top edge at the top of `room`, the
## camera stepping back (never nearer than `distance`) when the box is taller or wider than the room.
## Worked out afresh from the item's place alone, so it does not depend on where the camera is now.
##
## kid_gap: how far apart the tools' two places are (0: no such rule); kid_feet: the lowest screen
## height of a child's feet. The camera also steps back until a child standing with its feet there (where
## it is drawn largest) is no taller than kid_gap, so wherever the child stands one of the two places is
## clear of it. (first-steps r8: while a placed thing
## was edited, two rows of buttons made each place 279 px tall; at the iPad Air layout and at the TV
## layout in German the child, about 300 px tall, no longer fitted between them.) The child is measured
## as kid_height does. Moving the focus along the ground does not change that height, only the
## distance does, and the distance only grows, so this converges as before.
static func frame_fit(center: Vector3, radius: float, height: float, yaw: float, distance: float, focus: Vector3, room: Rect2, view: Vector2, kid_gap := 0.0, kid_feet := 0.0) -> Dictionary:
	var toward := Vector3(sin(yaw), 0, cos(yaw))   # along the ground, toward the camera
	var half := tan(deg_to_rad(FOV) * 0.5)
	for i in 12:
		var xf := pose_xform(focus, yaw, distance)
		var r := box_rect(xf, view, center, radius, height)
		if not r.has_area():
			break
		var over := maxf(r.size.y / room.size.y, r.size.x / room.size.x)
		if kid_gap > 0.0:
			over = maxf(over, kid_height(xf, view, kid_feet if kid_feet > 0.0 else view.y) / kid_gap)
		if over > 1.0 and distance < FRAME_MAX_DISTANCE:
			distance = minf(distance * over * 1.01, FRAME_MAX_DISTANCE)
			continue
		var down := room.position.y - r.position.y   # how far the box must move down the screen
		if absf(down) < 0.25:
			break
		# A step of the focus along the ground away from the camera moves the picture down the screen.
		var px_per_m := view.y / (2.0 * distance * half)
		focus -= toward * (down / (px_per_m * sin(PITCH)))
	return {"focus": focus, "distance": distance}


## Indoors (see frame_low): the distance, from `distance` outward, at which one of the tools' two places
## is free of the held thing (its box grown by ROOM_THING_GAP, as the HUD gives it to choose_place indoors)
## and of the child, judged as PlacementDock.choose_place judges them: the low
## place is free when the thing is clear of the whole strip at its height and the child (CHILD_GAP
## around it) clear of the tools there; the top place when both are clear of it. `base` is where the
## thing's box starts (PlacementDock.box_base); `kid` the child's feet, or null when there is no child.
## With a `safe` area (r10) the thing's box, SAFE_GAP around it, must also lie inside it.
## Only the distance changes, never the turn or the focus. Gives FRAME_MAX_DISTANCE when no distance
## up to it frees a place.
static func room_fit(base: Vector3, radius: float, height: float, kid: Variant, yaw: float, distance: float, focus: Vector3, low: Rect2, top: Rect2, strip: Rect2, view: Vector2, safe := Rect2()) -> float:
	for i in 64:   # 1.02 a step: from the room's 11 m to FRAME_MAX_DISTANCE takes 51
		var xf := pose_xform(focus, yaw, distance)
		var thing := box_rect(xf, view, base, radius, height)
		var whole := not safe.has_area() or not thing.has_area() or safe.encloses(thing.grow(SAFE_GAP))
		if thing.has_area():
			thing = thing.grow(ROOM_THING_GAP)
		var child := Rect2()
		if kid != null:
			child = box_rect(xf, view, kid, KID_BOX_RADIUS, KID_BOX_HEIGHT)
			if child.has_area():
				child = child.grow(PlacementDock.CHILD_GAP)
		var low_free := PlacementDock.overlap(thing, strip) == 0.0 and PlacementDock.overlap(child, low) == 0.0
		var top_free := PlacementDock.overlap(thing, top) == 0.0 and PlacementDock.overlap(child, top) == 0.0
		if (low_free or top_free) and whole or distance >= FRAME_MAX_DISTANCE:
			return distance
		distance = minf(distance * 1.02, FRAME_MAX_DISTANCE)
	return distance


## How tall a child is on screen (KID_RADIUS ring at the feet and at 1.85 m, 10 px around) when it
## stands on the ground at the middle of the view with its feet at screen height `feet_y`, for this
## pose (0 when that point of the view does not meet the ground).
static func kid_height(xf: Transform3D, view: Vector2, feet_y: float) -> float:
	var half := tan(deg_to_rad(FOV) * 0.5)
	var dir := xf.basis * Vector3(0, (view.y * 0.5 - feet_y) / (view.y * 0.5) * half, -1)
	if dir.y > -0.0001:
		return 0.0
	var at := xf.origin + dir * (-xf.origin.y / dir.y)
	return box_rect(xf, view, Vector3(at.x, 0, at.z), KID_RADIUS, 1.85).size.y


## Ground-plane directions relative to the camera, for keyboard walking.
func flat_forward() -> Vector2:
	return Vector2(-sin(_yaw), -cos(_yaw))


func flat_right() -> Vector2:
	return Vector2(cos(_yaw), -sin(_yaw))
