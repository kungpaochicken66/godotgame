## Thousand Town's walkable ground (design/thousand-town.md section 2, "Navigation"): where a child may stand,
## how high the ground is there, and sliding collision for a walking step. Pure data, no nodes; deterministic.
##
## Sources (all in metres, built offline from upstream "Qianren Xiaozhen (Thousand Town)" by Yihuishi /
## YiHuiShiBY, CC BY 4.0):
##   solids.json   the world layer's footprints of everything that blocks walking between 0.25 m and 1.8 m
##                 above its own ground (rects and turned quads, with bottom and top), and the walkable
##                 surfaces with their heights or height profiles (bridges, viaducts, tunnels, the station
##                 platforms, yards, plaza and market paving, the housing entry steps)
##   town.json     what the world layer leaves to W-DATA's meshes: the four office towers, the frontage
##                 (compound walls, railings, hedges and the towers' shop rings), the plaza monument,
##                 benches and planters, the carousel and the teacups, the plaza fountain's ring basin; and
##                 the canal, the park lawns and the board
##
## Rules
##   - The board: |x| <= 95, |z| <= 129, less the body radius.
##   - Water: the canal |x| < 7.5 m (plus the body) is open only on a bridge deck (between its rails); the
##     plaza fountain's ring basin is water too (its monument is an island).
##   - A solid blocks a point when it reaches into the band 0.25..1.8 m above the ground height there (so a
##     viaduct pier under a deck, or a kerb, does not).
##   - Tunnels: the sunk roadway (more than STEP_DOWN below the pavement) is closed; viaduct ramps are solid
##     where the deck is 0.25..HEADROOM m above the ground, and a child walks under the high deck.
##   - A step may not climb or drop more than STEP_MAX (a raised yard's 0.575 m edge is one step; a viaduct
##     side or a tunnel wall is not).
## Queries use a 4 m spatial hash; everything is a pure function of the data, so every device agrees.
extends RefCounted

const ThousandMap := preload("res://scripts/core/thousand_map.gd")

const SOLIDS_PATH := ThousandMap.DATA_DIR + "solids.json"
const HALF := ThousandMap.HALF
## The child's walking body radius (town_world.resolve_walk's default).
const BODY := 0.28
const CELL := 4.0
## Solids are hashed grown by this much, so queries with a body up to it are exact.
const GROW := 0.5
const BAND_LO := 0.25
const BAND_HI := 1.8
const STEP_MAX := 0.6
## How far below the pavement a tunnel roadway may sink before it is closed to walking.
const STEP_DOWN := 0.4
## A viaduct deck at least this far above the ground is walked under; lower, its ramp is solid.
const HEADROOM := 2.0
const PAVEMENT := 0.125
const LAWN := 0.06
## A walking step is checked in pieces no longer than this (m).
const SUBSTEP := 0.2

static var _shared: RefCounted = null

# Solids: one entry per index.
var sx0 := PackedFloat32Array()
var sz0 := PackedFloat32Array()
var sx1 := PackedFloat32Array()
var sz1 := PackedFloat32Array()
var sbot := PackedFloat32Array()
var stop := PackedFloat32Array()
var spoly: Array = []           # null, or a convex PackedVector2Array (x, z)
var skind := PackedStringArray()
var sid := PackedStringArray()
# The hash: cell index -> PackedInt32Array of solid indices.
var _nx := 0
var _nz := 0
var _cells: Array = []
# Walkable surfaces: {kind, rect: Rect2, ...} (flat "y"; "steps" y_from/y_to/toward; "bridge" / "tunnel" /
# "viaduct" profiles in metres).
var surfaces: Array = []
var bridges: Array = []         # bridge deck rects (Rect2): the only dry way over the canal
var tunnels: Array = []
var viaducts: Array = []
var lawns: Array = []           # Rect2: the parks' lawns (LAWN high, a little below the pavement)
var rings: Array = []           # water rings: {c: Vector2, r0, r1}
var canal := Rect2(-7.5, -129.0, 15.0, 258.0)
var datums: Dictionary = {}
var loaded := false


## The one navigation everyone shares (built from the data on first use).
static func shared() -> RefCounted:
	if _shared == null:
		var n = load("res://scripts/core/thousand_nav.gd").new()
		n.load_data()
		_shared = n
	return _shared


func load_data() -> void:
	if loaded:
		return
	loaded = true
	_nx = int(ceil(HALF.x * 2.0 / CELL))
	_nz = int(ceil(HALF.y * 2.0 / CELL))
	_cells.resize(_nx * _nz)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()
	var j := JSON.new()
	if not FileAccess.file_exists(SOLIDS_PATH) or j.parse(FileAccess.get_file_as_string(SOLIDS_PATH)) != OK:
		push_error("thousand_nav: cannot read " + SOLIDS_PATH)
		return
	var sd: Dictionary = j.data
	datums = sd.get("datums", {})
	for s: Dictionary in sd.get("solids", []):
		if s.has("poly"):
			var poly := PackedVector2Array()
			for q in s["poly"]:
				poly.append(Vector2(float(q[0]), float(q[1])))
			_add_poly(poly, float(s["bottom"]), float(s["top"]), str(s["kind"]), str(s["id"]))
		else:
			_add_rect(ThousandMap.rect_of(s["rect"]), float(s["bottom"]), float(s["top"]), str(s["kind"]), str(s["id"]))
	for w: Dictionary in sd.get("walkable", []):
		var surf := {"kind": str(w["kind"]), "rect": ThousandMap.rect_of(w["rect"])}
		if w.has("y"):
			surf["y"] = float(w["y"])
		elif w.has("y_from"):
			surf["y_from"] = float(w["y_from"])
			surf["y_to"] = float(w["y_to"])
			surf["toward"] = ThousandMap.v2(w["toward"])
		elif w.has("profile"):
			var pr: Dictionary = w["profile"]
			surf["profile"] = str(pr["kind"])
			surf["p"] = pr.get(str(pr["kind"]), {})
		match surf.get("profile", ""):
			"bridge":
				var b: Dictionary = surf["p"]
				bridges.append(ThousandMap.rect_of(b))
				surfaces.append(surf)
			"tunnel":
				tunnels.append(surf)
			"viaduct":
				viaducts.append(surf)
			_:
				surfaces.append(surf)
	_add_town()


## What the world layer leaves to town.json: towers, frontage, plaza and ride meshes, water and lawns.
func _add_town() -> void:
	var d := ThousandMap.data()
	if d.is_empty():
		return
	canal = ThousandMap.canal()
	for b: Dictionary in ThousandMap.buildings():
		if b.kind == "tower":
			_add_rect(b.rect, 0.0, float(b.height), "tower", str(b.id))
	# Frontage: compound walls, railings, hedges, gates and the towers' shop rings (box parts, metres).
	for site: Dictionary in d.get("frontage", {}).get("sites", []):
		var k := 0
		for p: Dictionary in site.get("parts", []):
			k += 1
			var y := float(p.y)
			var h := float(p.h)
			var bot := y - h * 0.5
			var top := y + h * 0.5
			if top <= PAVEMENT + BAND_LO or bot >= PAVEMENT + BAND_HI:
				continue
			var w := float(p.w)
			var dd := float(p.d)
			_add_rect(Rect2(float(p.x) - w * 0.5, float(p.z) - dd * 0.5, w, dd), bot, top, "frontage", "%s#%d" % [site.id, k])
	var lm: Dictionary = d.get("landmarks", {})
	if lm.has("monument"):
		var m: Dictionary = lm.monument
		_add_poly(_ngon(Vector2(float(m.x), float(m.z)), 2.9, 12), 0.0, float(m.height), "monument", "monument")
		for bench: Dictionary in m.get("benches", []):
			_add_poly(_turned(Vector2(float(bench.x), float(bench.z)), Vector2(2.3, 0.575), float(bench.get("yaw", 0.0))), 0.14, 0.97, "plaza-bench", "plaza-bench")
		for pl: Dictionary in m.get("planters", []):
			_add_rect(Rect2(float(pl.x) - 1.125, float(pl.z) - 1.125, 2.25, 2.25), 0.14, 0.88, "plaza-planter", "plaza-planter")
	for ride in ["carousel", "teacups"]:
		if lm.has(ride):
			var r: Dictionary = lm[ride]
			_add_poly(_ngon(Vector2(float(r.x), float(r.z)), float(r.radius), 12), float(r.y), float(r.y) + float(r.height), ride, ride)
	if lm.has("fountain"):
		var f: Dictionary = lm.fountain
		rings.append({"c": Vector2(float(f.x), float(f.z)), "r0": float(f.inner), "r1": float(f.outer)})
	for park: Dictionary in d.get("places", {}).get("parks", []):
		if str(park.get("use", "")) == "park":
			lawns.append(ThousandMap.rect_of(park))


static func _ngon(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## A w x d box (along its own x and z) turned by yaw about +y, as a quad (x, z).
static func _turned(c: Vector2, size: Vector2, yaw: float) -> PackedVector2Array:
	var ax := Vector2(cos(yaw), -sin(yaw)) * size.x * 0.5   # Godot's +y rotation turns +x toward -z
	var az := Vector2(sin(yaw), cos(yaw)) * size.y * 0.5
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])


func _add_rect(r: Rect2, bot: float, top: float, kind: String, id: String) -> void:
	sx0.append(r.position.x)
	sz0.append(r.position.y)
	sx1.append(r.end.x)
	sz1.append(r.end.y)
	sbot.append(bot)
	stop.append(top)
	spoly.append(null)
	skind.append(kind)
	sid.append(id)
	_hash(sx0.size() - 1)


func _add_poly(poly: PackedVector2Array, bot: float, top: float, kind: String, id: String) -> void:
	# Keep it counter-clockwise in (x, z) so the inside test is one sign.
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	sx0.append(lo.x)
	sz0.append(lo.y)
	sx1.append(hi.x)
	sz1.append(hi.y)
	sbot.append(bot)
	stop.append(top)
	spoly.append(poly)
	skind.append(kind)
	sid.append(id)
	_hash(sx0.size() - 1)


func _hash(i: int) -> void:
	var cx0 := clampi(int(floor((sx0[i] - GROW + HALF.x) / CELL)), 0, _nx - 1)
	var cx1 := clampi(int(floor((sx1[i] + GROW + HALF.x) / CELL)), 0, _nx - 1)
	var cz0 := clampi(int(floor((sz0[i] - GROW + HALF.y) / CELL)), 0, _nz - 1)
	var cz1 := clampi(int(floor((sz1[i] + GROW + HALF.y) / CELL)), 0, _nz - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var arr: PackedInt32Array = _cells[cz * _nx + cx]
			arr.append(i)
			_cells[cz * _nx + cx] = arr


func _cell_of(p: Vector2) -> int:
	var cx := int(floor((p.x + HALF.x) / CELL))
	var cz := int(floor((p.y + HALF.y) / CELL))
	if cx < 0 or cz < 0 or cx >= _nx or cz >= _nz:
		return -1
	return cz * _nx + cx


# ------------------------------------------------------------- heights

static func _smooth(e: float) -> float:
	e = clampf(e, 0.0, 1.0)
	return e * e * (3.0 - 2.0 * e)


## The bridge profile (solids.json, upstream units = metres x 2): 0.125 m at the ends, 0.975 m on the deck.
static func bridge_y(b: Dictionary, p: Vector2) -> float:
	var ax := (float(b.w) + 10.0 - absf(p.x - float(b.x)) * 2.0) / 10.0   # (w/2 + 10 - |X - x|) / 10 in units
	var az := (float(b.d) + 4.0 - absf(p.y - float(b.z)) * 2.0) / 4.0     # (d/2 + 4 - |Z - z|) / 4
	return 0.5 * (0.25 + 1.7 * _smooth(ax) * _smooth(az))


static func viaduct_y(v: Dictionary, p: Vector2) -> float:
	var flat := float(v.flatX) * 2.0
	var ramp := float(v.rampX) * 2.0
	var ex := (flat + ramp - absf(p.x) * 2.0) / ramp
	var ez := (float(v.d) + 2.7 - absf(p.y - float(v.z)) * 2.0) / 1.2   # (d/2 + 2.7 - |Z - z|) / 1.2
	return 0.5 * (0.25 + (float(v.height) * 2.0 - 0.25) * _smooth(ex) * _smooth(ez))


static func tunnel_y(t: Dictionary, p: Vector2) -> float:
	var portal := float(t.portalX) * 2.0
	var cover := float(t.coverX) * 2.0
	var e := clampf((portal - absf(p.x) * 2.0) / (portal - cover), 0.0, 1.0)
	return 0.5 * (0.25 - float(t.drop) * 2.0 * _smooth(e))


## The ground height (m) at a point: the highest walkable surface there, the park lawn, or the pavement; a
## tunnel's roadway sinks below it.
func height_at(p: Vector2) -> float:
	var h := PAVEMENT
	for r: Rect2 in lawns:
		if r.has_point(p):
			h = LAWN
			break
	for s: Dictionary in surfaces:
		var r: Rect2 = s.rect
		if not r.has_point(p):
			continue
		var y := h
		if s.has("y"):
			y = s.y
		elif s.has("y_from"):
			var tw: Vector2 = s.toward
			var depth := absf(tw.x) * r.size.x + absf(tw.y) * r.size.y
			var start := r.position + Vector2(r.size.x if tw.x < 0.0 else 0.0, r.size.y if tw.y < 0.0 else 0.0)
			var t := clampf((p - start).dot(tw) / maxf(depth, 0.001), 0.0, 1.0)
			y = lerpf(s.y_from, s.y_to, t)
		elif s.get("profile", "") == "bridge":
			y = bridge_y(s.p, p)
		h = maxf(h, y)
	for t: Dictionary in tunnels:
		if (t.rect as Rect2).has_point(p):
			h = minf(h, tunnel_y(t.p, p))
	return h


# ------------------------------------------------------------- blocking

## Is the canal (or another water) under a body at p, with no bridge deck to stand on?
func in_water(p: Vector2, body := BODY) -> bool:
	if absf(p.x - canal.get_center().x) < canal.size.x * 0.5 + body:
		var on_deck := false
		for r: Rect2 in bridges:
			if p.y >= r.position.y and p.y <= r.end.y and p.x >= r.position.x and p.x <= r.end.x:
				on_deck = true
				break
		if not on_deck:
			return true
	for ring: Dictionary in rings:
		var dist := p.distance_to(ring.c)
		if dist > float(ring.r0) - body and dist < float(ring.r1) + body:
			return true
	return false


## Closed ground: a tunnel's sunk roadway, a viaduct's ramp.
func in_void(p: Vector2) -> bool:
	for t: Dictionary in tunnels:
		if (t.rect as Rect2).has_point(p) and tunnel_y(t.p, p) < PAVEMENT - STEP_DOWN:
			return true
	for v: Dictionary in viaducts:
		if (v.rect as Rect2).has_point(p):
			var rise := viaduct_y(v.p, p) - PAVEMENT
			if rise > BAND_LO and rise < HEADROOM:
				return true
	return false


## The index of the first solid that blocks a body at p, or -1.
func solid_at(p: Vector2, body := BODY, h := NAN) -> int:
	var c := _cell_of(p)
	if c < 0:
		return -1
	if is_nan(h):
		h = height_at(p)
	var lo := h + BAND_LO
	var hi := h + BAND_HI
	for i: int in _cells[c]:
		if stop[i] <= lo or sbot[i] >= hi:
			continue
		if p.x < sx0[i] - body or p.x > sx1[i] + body or p.y < sz0[i] - body or p.y > sz1[i] + body:
			continue
		if spoly[i] == null:
			# a rect grown by a round body: the corners are rounded
			var qx := clampf(p.x, sx0[i], sx1[i])
			var qz := clampf(p.y, sz0[i], sz1[i])
			if (p.x - qx) * (p.x - qx) + (p.y - qz) * (p.y - qz) < body * body:
				return i
		elif _poly_hit(spoly[i], p, body):
			return i
	return -1


static func _poly_hit(poly: PackedVector2Array, p: Vector2, r: float) -> bool:
	var inside := true
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var e := b - a
		if e.cross(p - a) < 0.0:
			inside = false
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) < r * r:
			return true
	return inside


## True when a body of radius `body` cannot stand at p.
func blocked(p: Vector2, body := BODY) -> bool:
	if absf(p.x) > HALF.x - body or absf(p.y) > HALF.y - body:
		return true
	if in_water(p, body) or in_void(p):
		return true
	return solid_at(p, body) >= 0


## Can a body step from a (free) to b? Not blocked, and no ledge higher than STEP_MAX between them.
func can_step(a: Vector2, b: Vector2, body := BODY) -> bool:
	if blocked(b, body):
		return false
	return absf(height_at(b) - height_at(a)) <= STEP_MAX


## The walkable point for a step to `pos`. With `from`, the step is walked in SUBSTEP pieces; a blocked piece
## slides along x or z, or stops. Without it (or from a blocked start), pos is pushed out to the nearest free
## point.
func resolve(pos: Vector2, from: Variant = null, body := BODY) -> Vector2:
	if from == null or not (from is Vector2) or blocked(from, body):
		return pos if not blocked(pos, body) else push_out(pos, body)
	var f: Vector2 = from
	var move := pos - f
	var n := maxi(1, int(ceil(move.length() / SUBSTEP)))
	var step := move / float(n)
	var cur := f
	for i in n:
		var cand := cur + step
		if can_step(cur, cand, body):
			cur = cand
			continue
		var sx := cur + Vector2(step.x, 0.0)
		var sz := cur + Vector2(0.0, step.y)
		# slide along the axis that keeps more of the step
		var first := sx if absf(step.x) >= absf(step.y) else sz
		var second := sz if first == sx else sx
		if first != cur and can_step(cur, first, body):
			cur = first
		elif second != cur and can_step(cur, second, body):
			cur = second
		else:
			break
	return cur


## The nearest free point to p, searched on rings 0.1 m apart in 16 directions (deterministic).
func push_out(p: Vector2, body := BODY) -> Vector2:
	p = Vector2(clampf(p.x, -HALF.x + body + 0.01, HALF.x - body - 0.01), clampf(p.y, -HALF.y + body + 0.01, HALF.y - body - 0.01))
	if not blocked(p, body):
		return p
	for ring in range(1, 80):
		var r := 0.1 * float(ring)
		for k in 16:
			var a := TAU * float(k) / 16.0
			var q := p + Vector2(cos(a), sin(a)) * r
			if not blocked(q, body):
				return q
	return Vector2(ThousandMap.ARRIVAL_POS.x, ThousandMap.ARRIVAL_POS.z)


## Solids whose id starts with a prefix (tests, debugging): indices.
func solids_named(prefix: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in sid.size():
		if sid[i].begins_with(prefix):
			out.append(i)
	return out
