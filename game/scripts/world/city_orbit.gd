## The city's camera maths (design/city-district.md "Camera"): pure static functions, no nodes. The owner
## wires it into camera_rig.gd; nothing here reads the scene.
##
## A view state is a Dictionary {"yaw", "pitch", "distance", "out"}: the camera sits `distance` from its
## focus, at `yaw` (0 = south of the focus looking north, growing toward the east) and `pitch` above the
## ground. "out" means the distance follows the zoom-out limit (so the whole block stays in view while the
## child orbits). pose() turns a state into {"yaw", "pitch", "distance", "focus", "xform"} for a child
## position: the focus slides from the middle of the block (zoomed out) to the child (zoomed in).
##
## Gestures are plain functions of a small Dictionary (see gesture_new): a one-finger or mouse drag that
## starts on empty ground orbits; a tap is a short, small touch; two fingers pinch; the TV pointer never
## orbits; a drag never walks the child (only a "tap" result does).
extends RefCounted

const CityMap := preload("res://scripts/core/city_map.gd")

## The same field of view as CameraRig.FOV.
const FOV := 42.0
const PITCH_OVERVIEW := deg_to_rad(45.0)
const PITCH_MIN := deg_to_rad(25.0)
const PITCH_MAX := deg_to_rad(70.0)
## The closest zoom: beside the child.
const DIST_MIN := 8.0
## The map shown with this much room round it (metres).
const MARGIN := 2.0
## dest-fix r1 (the user's acceptance on the installed r3: the city is for strolling with one's own character):
## the default view, on arrival, Reset view and leaving Look, is this zoom level (0 = the closest), which follows
## the child fully. On an iPad (4:3) it is about 15 m away: the child stands about 80 px tall, centred, where the
## overview (96 m) showed a 13 px figure among fifty townsfolk. The overview is one zoom-out step farther each.
const STROLL_LEVEL := 1
## Fraction of the frame the fitted points may fill.
const FIT_FILL := 0.97
const YAW_STEP := TAU / 16.0
const ZOOM_LEVELS := 5
## Zoomed in to this fraction of the overview distance the camera follows the child fully.
const FOLLOW_FULL := 0.45
const FOCUS_LIFT := 0.6
const ORBIT_YAW_PER_PX := deg_to_rad(0.3)
const ORBIT_PITCH_PER_PX := deg_to_rad(0.2)
const SMOOTH_RATE := 9.0
## Pan: how far past the lot the focus may go (metres).
const PAN_MARGIN := 4.0

## Gestures: a touch or mouse press that moves farther than this many px (at scale 1) is a drag.
const DRAG_PX := 10.0
## A press that stays under DRAG_PX and ends within this many seconds is a tap.
const TAP_SEC := 0.5
const PINCH_MIN := 0.5
const PINCH_MAX := 2.0
const WHEEL_BASE := 1.1


# ------------------------------------------------------------------ the camera pose

## The camera's transform for a focus, yaw, pitch and distance (CameraRig.pose_xform with a free pitch).
static func pose_xform(focus: Vector3, yaw: float, pitch: float, distance: float) -> Transform3D:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	return Transform3D(Basis.looking_at(-offset.normalized(), Vector3.UP), focus + offset)


## Where a world point lands on screen (pixels) for a pose; null behind the camera.
static func project(xf: Transform3D, view: Vector2, p: Vector3) -> Variant:
	var v := xf.affine_inverse() * p
	if v.z > -0.05:
		return null
	var half := tan(deg_to_rad(FOV) * 0.5)
	return Vector2(view.x * 0.5 + v.x / (-v.z * half) * view.y * 0.5, view.y * 0.5 - v.y / (-v.z * half) * view.y * 0.5)


## The world ray through a screen point: {"origin": Vector3, "dir": Vector3 (unit)}.
static func ray(xf: Transform3D, view: Vector2, screen: Vector2) -> Dictionary:
	var half := tan(deg_to_rad(FOV) * 0.5)
	var x := (screen.x - view.x * 0.5) / (view.y * 0.5) * half
	var y := -(screen.y - view.y * 0.5) / (view.y * 0.5) * half
	var dir := (xf.basis * Vector3(x, y, -1.0)).normalized()
	return {"origin": xf.origin, "dir": dir}


## Points the overview must show: the ground of the map plus MARGIN, the buildings' roofs, the wheel.
static func overview_points() -> Array:
	var h := CityMap.HALF + Vector2(MARGIN, MARGIN)
	var pts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * h.x, 0.0, sz * h.y))
	for id: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[id]
		var r: Rect2 = b["rect"]
		var y: float = b["roof"]
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			pts.append(Vector3(c.x, y, c.y))
	var f: Dictionary = CityMap.FERRIS
	var hub: Vector3 = f["hub"]
	var rad: float = f["radius"]
	pts.append(Vector3(hub.x - rad, hub.y, hub.z))
	pts.append(Vector3(hub.x + rad, hub.y, hub.z))
	pts.append(Vector3(hub.x, hub.y + rad + 0.5, hub.z))
	return pts


## The middle of the block (what the overview looks at).
static func overview_focus() -> Vector3:
	return Vector3(0.0, 1.5, 0.0)


static func _fits(pts: Array, focus: Vector3, yaw: float, pitch: float, d: float, aspect: float) -> bool:
	var xf := pose_xform(focus, yaw, pitch, d)
	var inv := xf.affine_inverse()
	var tv := tan(deg_to_rad(FOV) * 0.5)
	var th := tv * aspect
	for p: Vector3 in pts:
		var v := inv * p
		if v.z > -0.5:
			return false
		if absf(v.x) > -v.z * th * FIT_FILL or absf(v.y) > -v.z * tv * FIT_FILL:
			return false
	return true


## The smallest distance at which `pts` fit the frame (aspect = width / height) for a focus, yaw and pitch.
static func fit_distance(pts: Array, focus: Vector3, yaw: float, pitch: float, aspect: float) -> float:
	var lo := 5.0
	var hi := 600.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _fits(pts, focus, yaw, pitch, mid, aspect):
			hi = mid
		else:
			lo = mid
	return hi


## The zoom-out limit for a yaw: the whole block (HALF + MARGIN) in view.
static func max_distance(aspect: float, yaw: float = 0.0, pitch: float = PITCH_OVERVIEW) -> float:
	return fit_distance(overview_points(), overview_focus(), yaw, pitch, aspect)


## The overview state: looking north from the south at 45 degrees, the whole block in the frame.
static func overview(aspect: float) -> Dictionary:
	return {"yaw": 0.0, "pitch": PITCH_OVERVIEW, "distance": max_distance(aspect, 0.0, PITCH_OVERVIEW), "out": true}


## Reset view.
static func reset(aspect: float) -> Dictionary:
	return overview(aspect)


## Keep a state inside its limits (distance within [DIST_MIN, the zoom-out limit], pitch within its range).
static func clamp_state(s: Dictionary, aspect: float) -> Dictionary:
	var out := s.duplicate()
	out["pitch"] = clampf(float(s["pitch"]), PITCH_MIN, PITCH_MAX)
	out["yaw"] = _wrap_yaw(float(s["yaw"]))
	var top := max_distance(aspect, float(out["yaw"]), float(out["pitch"]))
	var d := clampf(float(s["distance"]), DIST_MIN, top)
	out["distance"] = d
	out["out"] = d >= top - 1e-3
	return out


static func _wrap_yaw(y: float) -> float:
	return fposmod(y + PI, TAU) - PI


## The pose for a state: the focus slides from the middle of the block to the child as the camera comes in.
static func pose(s: Dictionary, aspect: float, child: Vector3) -> Dictionary:
	var yaw: float = s["yaw"]
	var pitch: float = s["pitch"]
	var d: float = s["distance"]
	var top := max_distance(aspect, yaw, pitch)
	if bool(s.get("out", false)):
		d = top
	var w := clampf((top - d) / (top * (1.0 - FOLLOW_FULL)), 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var focus := overview_focus().lerp(child + Vector3(0.0, FOCUS_LIFT, 0.0), w)
	if s.has("focus"):
		# a Look view (look_state) looks at its own place, whoever the child is
		focus = s["focus"]
	focus = apply_pan(focus, s.get("pan", Vector3.ZERO))
	return {"yaw": yaw, "pitch": pitch, "distance": d, "focus": focus, "xform": pose_xform(focus, yaw, pitch, d)}


## The ground rectangle the focus may be panned within: the lot plus 4 m.
static func pan_bounds() -> Rect2:
	return (CityMap.LOT as Rect2).grow(PAN_MARGIN)


## base + pan, kept within pan_bounds() along each axis. A base that is already outside (a child on the outer
## pavement) is not pulled back: the pan can only move the focus within the bounds or less far out than base.
static func apply_pan(base: Vector3, pan: Vector3) -> Vector3:
	var b := pan_bounds()
	var out := base + Vector3(pan.x, 0.0, pan.z)
	out.x = clampf(out.x, minf(b.position.x, base.x), maxf(b.end.x, base.x))
	out.z = clampf(out.z, minf(b.position.y, base.z), maxf(b.end.y, base.z))
	return out


## The close follow pose: centred on the child at the state's distance.
static func follow_pose(s: Dictionary, child: Vector3) -> Dictionary:
	var focus := apply_pan(child + Vector3(0.0, FOCUS_LIFT, 0.0), s.get("pan", Vector3.ZERO))
	var yaw: float = s["yaw"]
	var pitch: float = s["pitch"]
	var d: float = s["distance"]
	return {"yaw": yaw, "pitch": pitch, "distance": d, "focus": focus, "xform": pose_xform(focus, yaw, pitch, d)}


# ------------------------------------------------------------------ orbit and zoom

## A drag of delta_px (finger or mouse) orbits: yaw is free (continuous), pitch stays in 25..70 degrees.
## view_h scales the sensitivity so a drag across the screen turns the same on every device.
static func orbit(s: Dictionary, delta_px: Vector2, view_h: float = 1080.0, aspect: float = 16.0 / 9.0) -> Dictionary:
	var k := 1080.0 / maxf(view_h, 1.0)
	var out := s.duplicate()
	out["yaw"] = _wrap_yaw(float(s["yaw"]) - delta_px.x * k * ORBIT_YAW_PER_PX)
	out["pitch"] = clampf(float(s["pitch"]) + delta_px.y * k * ORBIT_PITCH_PER_PX, PITCH_MIN, PITCH_MAX)
	if bool(s.get("out", false)):
		out["distance"] = max_distance(aspect, float(out["yaw"]), float(out["pitch"]))
	else:
		out["distance"] = minf(float(s["distance"]), max_distance(aspect, float(out["yaw"]), float(out["pitch"])))
	return out


## Right-drag pan: moves the state's ground "pan" offset (Vector3, y 0) along the view's right and forward
## directions so that the ground follows the cursor: a drag of delta_px moves the ground under the cursor by
## about delta_px on screen (across: 2 d tan(fov/2) per view height; along the ground: that over sin(pitch)).
## The pan is kept within pan_bounds() (the focus is clamped again in pose()).
static func pan(s: Dictionary, delta_px: Vector2, view_h: float, aspect: float) -> Dictionary:
	var out := s.duplicate()
	var yaw: float = s["yaw"]
	var pitch: float = s["pitch"]
	var d := max_distance(aspect, yaw, pitch) if bool(s.get("out", false)) else float(s["distance"])
	var per_px := 2.0 * d * tan(deg_to_rad(FOV) * 0.5) / maxf(view_h, 1.0)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var cur: Vector3 = s.get("pan", Vector3.ZERO)
	var np := cur - right * delta_px.x * per_px + fwd * delta_px.y * per_px / maxf(sin(pitch), 0.2)
	var b := pan_bounds()
	np.x = clampf(np.x, b.position.x, b.end.x)
	np.z = clampf(np.z, b.position.y, b.end.y)
	np.y = 0.0
	out["pan"] = np
	return out


## Zoom by a factor (> 1: closer, a pinch spreading or the wheel forward): distance / factor within its limits.
static func zoom(s: Dictionary, factor: float, aspect: float) -> Dictionary:
	var out := s.duplicate()
	var top := max_distance(aspect, float(s["yaw"]), float(s["pitch"]))
	var d := float(s["distance"])
	if bool(s.get("out", false)):
		d = top
	d = clampf(d / maxf(factor, 0.01), DIST_MIN, top)
	out["distance"] = d
	out["out"] = d >= top - 1e-3
	return out


## The zoom factor of a pinch whose finger distance went from `prev` to `cur`.
static func pinch_factor(prev: float, cur: float) -> float:
	if prev < 1e-3:
		return 1.0
	return clampf(cur / prev, PINCH_MIN, PINCH_MAX)


## The zoom factor of mouse-wheel notches (positive: forward, closer).
static func wheel_factor(notches: float) -> float:
	return pow(WHEEL_BASE, notches)


## Controller L / R: turn by one 22.5 degree step (dir = +1 or -1); a free yaw goes to the next grid line.
static func step_yaw(s: Dictionary, dir: int) -> Dictionary:
	var out := s.duplicate()
	var k := float(s["yaw"]) / YAW_STEP
	var target := floorf(k + 1e-6) + 1.0 if dir > 0 else ceilf(k - 1e-6) - 1.0
	out["yaw"] = _wrap_yaw(target * YAW_STEP)
	if bool(s.get("out", false)):
		out["distance"] = max_distance(16.0 / 9.0, float(out["yaw"]), float(s["pitch"]))
	return out


## The discrete zoom distances (closest first): ZOOM_LEVELS steps, geometric between DIST_MIN and the limit.
static func zoom_levels(aspect: float, yaw: float, pitch: float) -> Array:
	var top := max_distance(aspect, yaw, pitch)
	var out: Array = []
	for i in ZOOM_LEVELS:
		out.append(DIST_MIN * pow(top / DIST_MIN, float(i) / float(ZOOM_LEVELS - 1)))
	return out


## One zoom level (dir = +1 closer, -1 farther), clamped: the rig's zoom_in / zoom_out. (The controller's ZL / ZR
## reach the city as the mouse wheel, design/tv-controller.md: ZL zooms in, ZR out.)
static func step_zoom(s: Dictionary, dir: int, aspect: float) -> Dictionary:
	var out := s.duplicate()
	var levels := zoom_levels(aspect, float(s["yaw"]), float(s["pitch"]))
	var d := float(levels[levels.size() - 1]) if bool(s.get("out", false)) else float(s["distance"])
	var idx := 0
	var best := INF
	for i in levels.size():
		var e := absf(log(d) - log(float(levels[i])))
		if e < best:
			best = e
			idx = i
	idx = clampi(idx - dir, 0, levels.size() - 1)
	out["distance"] = float(levels[idx])
	out["out"] = idx == levels.size() - 1
	return out


## The strolling view (STROLL_LEVEL): the camera follows the child at the overview's yaw and pitch.
static func stroll(aspect: float) -> Dictionary:
	var levels := zoom_levels(aspect, 0.0, PITCH_OVERVIEW)
	return {"yaw": 0.0, "pitch": PITCH_OVERVIEW, "distance": float(levels[STROLL_LEVEL]), "out": false}


## Glide a pose toward its goal ({"yaw", "pitch", "distance", "focus"}); reduce motion snaps.
static func smooth(cur: Dictionary, goal: Dictionary, dt: float, reduce_motion: bool) -> Dictionary:
	if reduce_motion:
		return goal.duplicate()
	var k := 1.0 - exp(-SMOOTH_RATE * maxf(dt, 0.0))
	var yaw: float = cur["yaw"]
	var out := {
		"yaw": _wrap_yaw(yaw + angle_difference(yaw, float(goal["yaw"])) * k),
		"pitch": lerpf(float(cur["pitch"]), float(goal["pitch"]), k),
		"distance": lerpf(float(cur["distance"]), float(goal["distance"]), k),
		"focus": (cur["focus"] as Vector3).lerp(goal["focus"], k)}
	out["xform"] = pose_xform(out["focus"], out["yaw"], out["pitch"], out["distance"])
	return out


# ------------------------------------------------------------------ gesture arbitration

## Start a gesture. source: "touch" | "mouse" | "pointer" (the TV pointer); started_on: "ground" (empty
## ground: a drag may orbit) | "thing" | "ui" (a drag there never orbits, never walks). button "left" (default) |
## "right" (a drag pans, a press never taps). scale: px per
## 1080-tall reference px (device density), so the thresholds follow the screen.
static func gesture_new(source: String, started_on: String, pos: Vector2, t: float, scale: float = 1.0, button: String = "left") -> Dictionary:
	return {"button": button, "source": source, "on": started_on, "start": pos, "last": pos, "t0": t, "scale": scale,
		"moved": 0.0, "mode": "pending", "delta": Vector2.ZERO, "pinched": false}


## Feed a move (fingers = fingers down now). Returns the updated gesture; g["mode"] is "pending" (could still
## be a tap), "orbit" (use g["delta"]), "pan" (a right drag: use g["delta"] with pan()), "pinch" (use pinch_factor) or "none" (ignore: a drag on a thing or
## the UI, or what is left after a pinch).
static func gesture_move(g: Dictionary, pos: Vector2, _t: float, fingers: int = 1) -> Dictionary:
	var out := g.duplicate()
	out["delta"] = pos - (g["last"] as Vector2)
	out["last"] = pos
	var src: String = g["source"]
	if src == "pointer":
		return out
	if g.get("button", "left") == "right":
		# a right drag pans, wherever it starts; it is never a tap
		out["moved"] = maxf(float(g["moved"]), pos.distance_to(g["start"]))
		if float(out["moved"]) > DRAG_PX * float(g["scale"]) or g["mode"] == "pan":
			out["mode"] = "pan"
		return out
	if fingers >= 2:
		out["pinched"] = true
		out["mode"] = "pinch"
		return out
	if bool(g["pinched"]):
		out["mode"] = "none"
		return out
	out["moved"] = maxf(float(g["moved"]), pos.distance_to(g["start"]))
	if g["mode"] == "pending" and float(out["moved"]) > DRAG_PX * float(g["scale"]):
		out["mode"] = "orbit" if g["on"] == "ground" else "none"
	elif g["mode"] == "pinch":
		out["mode"] = "none"
	return out


## The gesture ended at time t: "tap" (walk or use the thing there), "hold" (a still press that lasted:
## nothing), or "none" (a drag, a pinch). The pointer's press is always a tap.
static func gesture_end(g: Dictionary, t: float) -> String:
	if g.get("button", "left") == "right":
		return "none"
	if g["source"] == "pointer":
		return "tap" if t - float(g["t0"]) <= TAP_SEC * 2.0 else "hold"
	if g["mode"] != "pending" or bool(g["pinched"]):
		return "none"
	if float(g["moved"]) > DRAG_PX * float(g["scale"]):
		return "none"
	return "tap" if t - float(g["t0"]) <= TAP_SEC else "hold"


# ------------------------------------------------------------------ Look (city r2)

## The pose of a Look view: {"yaw", "pitch" (radians), "distance", "out": false, "focus"} for a LOOK_PLACES key.
## A narrow screen backs the camera off so the place still fits across (never beyond the zoom-out limit).
## The pitch is the place's own (it may lie under the orbit's 25 degree floor, which only limits dragging).
static func look_state(key: String, aspect: float) -> Dictionary:
	var lp: Dictionary = CityMap.LOOK_PLACES[key]
	var d: float = lp["distance"]
	if aspect < 16.0 / 9.0:
		d *= minf((16.0 / 9.0) / maxf(aspect, 0.1), 1.8)
	var yaw: float = lp["yaw"]
	var pitch := deg_to_rad(float(lp["pitch"]))
	d = minf(d, max_distance(aspect, yaw, pitch))
	return {"yaw": yaw, "pitch": pitch, "distance": d, "out": false, "focus": lp["focus"]}


static func _slab(o: float, d: float, lo: float, hi: float) -> Vector2:
	if absf(d) < 1e-12:
		return Vector2(-INF, INF) if o >= lo and o <= hi else Vector2(1.0, 0.0)
	var a := (lo - o) / d
	var b := (hi - o) / d
	return Vector2(minf(a, b), maxf(a, b))


## Interval [t_in, t_out] of a ray inside a vertical cylinder (x, z) of radius r about c; empty: (1, 0).
static func _cyl(o: Vector3, d: Vector3, c: Vector2, r: float, ax: int) -> Vector2:
	# ax 1: the axis is y (disc in x-z); ax 2: the axis is z (disc in x-y)
	var ox := o.x - c.x
	var oa := o.z - c.y if ax == 1 else o.y - c.y
	var dx := d.x
	var da := d.z if ax == 1 else d.y
	var qa := dx * dx + da * da
	if qa < 1e-12:
		return Vector2(-INF, INF) if ox * ox + oa * oa <= r * r else Vector2(1.0, 0.0)
	var qb := 2.0 * (ox * dx + oa * da)
	var qc := ox * ox + oa * oa - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return Vector2(1.0, 0.0)
	var sq := sqrt(disc)
	return Vector2((-qb - sq) / (2.0 * qa), (-qb + sq) / (2.0 * qa))


## The LOOK_PLACES key a ray meets first, else "". A place is a box (rect x y), the wheel's disc (a vertical
## disc in the wheel's plane at FERRIS.hub, radius + 0.8, 0.8 m either side) or the carousel's cylinder.
## "restaurant" is the tower's box above 6.2 m: the tower below it.
static func pick_place(origin: Vector3, dir: Vector3) -> String:
	var best := ""
	var best_t := INF
	for key: String in CityMap.LOOK_PLACES:
		var lp: Dictionary = CityMap.LOOK_PLACES[key]
		var iv := Vector2(-INF, INF)
		if lp.has("rect"):
			var r: Rect2 = lp["rect"]
			var y: Vector2 = lp["y"]
			iv = _isect(iv, _slab(origin.x, dir.x, r.position.x, r.end.x))
			iv = _isect(iv, _slab(origin.y, dir.y, y.x, y.y))
			iv = _isect(iv, _slab(origin.z, dir.z, r.position.y, r.end.y))
		elif lp.get("disc", false):
			var f: Dictionary = CityMap.FERRIS
			var hub: Vector3 = f["hub"]
			iv = _isect(iv, _slab(origin.z, dir.z, hub.z - 0.8, hub.z + 0.8))
			iv = _isect(iv, _cyl(origin, dir, Vector2(hub.x, hub.y), float(f["radius"]) + 0.8, 2))
		elif lp.has("circle"):
			var c: Vector3 = lp["focus"]
			var y2: Vector2 = lp["y"]
			iv = _isect(iv, _slab(origin.y, dir.y, y2.x, y2.y))
			iv = _isect(iv, _cyl(origin, dir, Vector2(c.x, c.z), float(lp["circle"]), 1))
		var t_in := maxf(iv.x, 0.0)
		if iv.x <= iv.y and iv.y >= 0.0 and t_in < best_t:
			best_t = t_in
			best = key
	return best


static func _isect(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x, b.x), minf(a.y, b.y))


## Between two pose() dictionaries, u in 0..1 eased in and out (smoothstep): yaw the short way round,
## pitch, distance and focus interpolated; the endpoints are the poses themselves. Returns a pose with "xform".
static func glide(from_pose: Dictionary, to_pose: Dictionary, u: float) -> Dictionary:
	var k := clampf(u, 0.0, 1.0)
	var src: Dictionary = from_pose if k <= 0.0 else (to_pose if k >= 1.0 else {})
	if not src.is_empty():
		var out := {"yaw": src["yaw"], "pitch": src["pitch"], "distance": src["distance"], "focus": src["focus"]}
		out["xform"] = pose_xform(out["focus"], out["yaw"], out["pitch"], out["distance"])
		return out
	var e := k * k * (3.0 - 2.0 * k)
	var yaw: float = from_pose["yaw"]
	var out2 := {
		"yaw": _wrap_yaw(yaw + angle_difference(yaw, float(to_pose["yaw"])) * e),
		"pitch": lerpf(float(from_pose["pitch"]), float(to_pose["pitch"]), e),
		"distance": lerpf(float(from_pose["distance"]), float(to_pose["distance"]), e),
		"focus": (from_pose["focus"] as Vector3).lerp(to_pose["focus"], e)}
	out2["xform"] = pose_xform(out2["focus"], out2["yaw"], out2["pitch"], out2["distance"])
	return out2
