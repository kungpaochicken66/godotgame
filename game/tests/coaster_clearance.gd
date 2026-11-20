## Roller Coaster Workshop clearance audit (unified r6; tools/coaster/README.md "Clearance audit").
## Builds the real park the way the game does (main.tscn, a solo session, Hud's Workshop path:
## controller.stop_for_workshop() and coaster_park.gd setup(main)), then reads back the geometry that
## was actually constructed: every visible MeshInstance3D (merged meshes are split back into their
## convex primitives by index range and shared vertices), every rail/tie/column MultiMesh instance,
## the platform signs, and the parked trains. Each becomes a static body in a private physics space.
## For every frame index of every lap the ride's own train is placed with CoasterLine.place() and
## three envelopes are tested against all of it:
##   track  - each rail segment, tie, support column and hanger arm (static; indexed by its frame)
##   car    - each convex part of each of the three cars (part-aligned boxes) and its four wheels
##   rider  - the child seated in the lead car: boxes around the kid rig's own meshes in its "ride"
##            pose (upper body, legs; +0.05 m) and the rider-eye camera (eye +-0.15 m)
## Exclusions (by design): a car's/rider's contact with its own rails and ties within its own span,
## a track element against its own track within +-8 frames (the same assembly), the train against
## itself, and support columns/arms standing on terrain (ground, hills, mounds), paths, the plaza
## and pools (footings). Everything else that penetrates more than 0.01 m is a conflict.
## Intentional tunnels (the portal arches of Crystal Mine, Neon Wings and Phantom Castle, and the
## castle) never pass by name: their parts must stay at least 0.25 m from the car and rider
## envelopes over the whole lap, and each portal's cross-section (all envelopes + 0.25 m, 0.6 m deep,
## at the portal frame) must be free of any geometry.
##   scripts/godot.sh --headless --path game -s res://tests/coaster_clearance.gd -- \
##       --out=/abs/coaster-clearance.json [--label=r6] [--rides=comet-run,neon-wings]
## Writes the JSON and a .txt summary beside it; prints "COASTER CLEARANCE PASS|FAIL"; exits 1 on
## any conflict (or an incomplete run), 0 when clean.
extends SceneTree

const TOL := 0.01
const MARGIN := 0.25
const PROBE := 2.0
const CELL := 8.0
const DEEP := 0.5
const LOCAL_TRACK := 8
const FOOTING := ["terrain", "path", "plaza", "pool"]

var main: Node
var park: Node
var space: RID
var state: PhysicsDirectSpaceState3D
var obs: Array[Dictionary] = []
var obs_rid: Array[RID] = []
var obs_aabb: Array[AABB] = []
var rid_index := {}
var grid := {}
var huge := PackedInt32Array()
var stamp := PackedInt32Array()
var qid := 0
var shapes: Array = []
var bodies: Array[RID] = []
var args := {}
var records := {}
var tunnel_min := {}
var kid_boxes: Array[AABB] = []
var queries := 0

const NAMES := {
	"park": {"8eb789": ["ground", "terrain"], "d9b28a": ["plaza", "plaza"], "dfc099": ["path", "path"],
		"795640": ["path tree trunk", "garden"], "679d76": ["path tree crown", "garden"], "8abb81": ["path tree crown", "garden"],
		"73584a": ["lamp post", "garden"], "f4ab67": ["lamp", "garden"], "925648": ["lamp cap", "garden"],
		"91ab75": ["garden mound", "terrain"], "e0bd91": ["fountain basin", "garden"], "61b4bf": ["fountain water", "garden"],
		"ddc48e": ["fountain column", "garden"], "eed5a4": ["fountain bowl", "garden"], "96dfec": ["fountain jet", "garden"],
		"bf6352": ["tent roof", "garden"], "ffe4ac": ["tent trim", "garden"], "a5764d": ["tent pole", "garden"],
		"a4774b": ["balloon basket", "garden"], "886b51": ["balloon rope", "garden"], "e68a5e": ["balloon", "garden"],
		"ffe9ae": ["balloon band", "garden"], "80a994": ["distant hill", "terrain"], "749d90": ["distant hill", "terrain"]},
	"decor": {"805b40": ["timber pier", "scenery"], "756f83": ["stone pier/rock", "scenery"], "65d7dc": ["crystal", "scenery"],
		"b487e2": ["crystal", "scenery"], "5fa7aa": ["light pool", "pool"], "374957": ["pool light post", "scenery"],
		"43dfbf": ["pool lamp", "scenery"], "928798": ["castle tower", "tunnel"], "655478": ["castle tower roof", "tunnel"],
		"a297a4": ["castle keep", "tunnel"]},
	"arch": {"746e68": ["portal boulder", "tunnel"], "805b40": ["portal timber", "tunnel"], "ffd678": ["portal lantern", "tunnel"],
		"253446": ["corridor pillar", "tunnel"], "273644": ["corridor wall", "tunnel"], "20303f": ["corridor roof", "tunnel"],
		"43dfbf": ["corridor beam/strip", "tunnel"], "756f83": ["arch pier/lintel", "tunnel"], "878595": ["arch plinth", "tunnel"],
		"a6a0ad": ["arch cap", "tunnel"], "68b3bc": ["stained glass", "tunnel"], "d993a7": ["stained glass", "tunnel"],
		"c1a75f": ["stained glass", "tunnel"], "ffa858": ["torch", "tunnel"], "99663b": ["portal beam", "tunnel"]},
	"landmark": {"af4c39": ["pagoda tier/fruit", "landmark"], "306f64": ["pagoda roof", "landmark"], "efb548": ["pagoda trim/comet star", "landmark"],
		"916447": ["orchard tree trunk", "landmark"], "64a268": ["orchard tree crown", "landmark"], "57849a": ["comet mast", "landmark"]},
	"platform": {"c28c5f": ["platform deck", "platform"], "80654c": ["canopy post", "platform"], "f5d88c": ["canopy trim", "platform"]},
}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	var save := "user://coaster-clearance-town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	root.get_node("Session").start_solo(save, main.menus.avatar)   # autoloads are not identifiers in a -s script
	await _wait(10)
	# The Hud's Workshop button path (hud.gd): a clean stop, then the park built on the main scene.
	main.controller.stop_for_workshop()
	park = load("res://scripts/world/coaster_park.gd").new()   # load at run time: autoloads exist only then
	var t_setup := Time.get_ticks_usec()
	park.setup(main)
	print("CLEARANCE park setup %.0f ms" % ((Time.get_ticks_usec() - t_setup) / 1000.0))
	park.kid.anim = "ride"
	await _wait(4)
	for p in 4:
		await physics_frame
	_measure_kid()
	space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	_collect()
	for p in 3:
		await physics_frame
	state = PhysicsServer3D.space_get_direct_state(space)
	print("CLEARANCE obstacles=%d (%.1f s)" % [obs.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	if args.has("dump"):
		var kinds := {}
		for o in obs:
			var k: String = o.kind + " " + o.name.get_slice(" (", 0)
			if not kinds.has(k):
				kinds[k] = [0, o.center, o.size]
			kinds[k][0] += 1
		for k in kinds:
			print("  ", k, " x", kinds[k][0], " e.g. c=", kinds[k][1], " s=", kinds[k][2])
		for o in obs:
			if o.kind == "terrain":
				print("  terrain ", o.name, " c=", o.center, " s=", o.size)
	var wanted: PackedStringArray = str(args.get("rides", "")).split(",", false)
	var report := {"tree": args.get("label", ""), "tolerance_m": TOL, "tunnel_margin_m": MARGIN,
		"engine": Engine.get_version_info().string, "rides": {}, "intervals": [], "tunnels": []}
	var audited := 0
	for line in park.lines:
		if not wanted.is_empty() and not wanted.has(line.design):
			continue
		var t1 := Time.get_ticks_msec()
		var summary := _audit_line(line, report)
		summary["seconds"] = (Time.get_ticks_msec() - t1) / 1000.0
		report.rides[line.design] = summary
		audited += 1
		print("CLEARANCE %s done in %.1f s (%d queries so far)" % [line.design, summary.seconds, queries])
		line.place(line.stop)
	var bad := 0
	for it in report.intervals:
		if not it.allowed:
			bad += 1
	for tn in report.tunnels:
		if not tn.pass:
			bad += 1
	report["complete"] = audited == park.lines.size()
	report["conflicts"] = bad
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	_write(report)
	print("COASTER CLEARANCE %s: %d rides, %d conflict intervals, %d tunnel failures" % ["PASS" if bad == 0 and report.complete else "FAIL", audited, bad, report.tunnels.filter(func(t): return not t.pass).size()])
	for b in bodies:
		PhysicsServer3D.free_rid(b)
	for s in shapes:
		if s is RID:
			PhysicsServer3D.free_rid(s)
	PhysicsServer3D.free_rid(space)
	quit(0 if bad == 0 and report.complete else 1)


# ------------------------------------------------------------------ the rider

## The kid rig's visible meshes in its "ride" pose, in kid space, split into upper body and legs.
func _measure_kid() -> void:
	var kid: Node3D = park.kid
	var inv := kid.global_transform.affine_inverse()
	var parts: Array[AABB] = []
	var lo := INF
	var hi := -INF
	for mi in _meshes(kid):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		parts.append(box)
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	var split := lo + (hi - lo) * 0.42
	var upper := AABB()
	var lower := AABB()
	var nu := 0
	var nl := 0
	for b in parts:
		if b.get_center().y > split:
			upper = b if nu == 0 else upper.merge(b)
			nu += 1
		else:
			lower = b if nl == 0 else lower.merge(b)
			nl += 1
	kid_boxes = [upper.grow(0.05), lower.grow(0.05)]
	print("CLEARANCE kid parts=%d upper=%s lower=%s" % [parts.size(), kid_boxes[0], kid_boxes[1]])


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


# ------------------------------------------------------------------ geometry

func _collect() -> void:
	var skip := {park.kid: true, park.shuttle: true}
	for line in park.lines:
		for c in line.cars:
			skip[c] = true
		for w in line.wheels:
			skip[w] = true
	var line_nodes := {}
	for line in park.lines:
		line_nodes[line] = true
		_collect_line(line, skip)
		for c in line.cars.size():
			for comp in _components(line.cars[c], line.cars[c].global_transform):
				_add_convex(comp.points, {"kind": "train", "name": "parked car %d" % c, "ride": line.design, "color": comp.color})
	for child in park.get_children():
		if line_nodes.has(child) or skip.has(child):
			continue
		if child is MeshInstance3D or child is Node3D:
			for comp in _components(child, child.global_transform if child is Node3D else Transform3D()):
				var nm := _name("park", comp.color)
				_add_convex(comp.points, {"kind": nm[1], "name": nm[0], "ride": "", "color": comp.color})


func _collect_line(line: Node3D, skip: Dictionary) -> void:
	var decor_done := false
	_add_track(line)
	for child in line.get_children():
		if skip.has(child) or child is MultiMeshInstance3D:
			continue
		if child is Node3D and _has_label(child):
			for comp in _components(child, child.global_transform):
				var nm := _name("platform", comp.color)
				if comp.color.is_equal_approx(line.accent):
					nm = ["platform sign post/roof", "platform"]
				_add_convex(comp.points, {"kind": nm[1], "name": nm[0], "ride": line.design, "color": comp.color})
			for l in child.get_children():
				if l is Label3D:
					_add_label(line, l)
		elif child is Node3D and not (child is MeshInstance3D) and not decor_done:
			decor_done = true
			var themed: bool = not line.scene_tags.is_empty()
			for sub in child.get_children():
				if sub is MeshInstance3D:
					for comp in _components(sub, sub.global_transform):
						var nm := _name("decor" if themed else "landmark", comp.color)
						if themed and line.design == "phantom-castle" and nm[0] == "stone pier/rock":
							nm = ["stone pier", "scenery"]
						elif themed and line.design == "crystal-mine" and nm[0] == "stone pier/rock":
							nm = ["rock outcrop", "scenery"]
						_add_convex(comp.points, {"kind": nm[1], "name": nm[0], "ride": line.design, "color": comp.color})
				elif sub is Node3D:
					var at := _nearest_frame(line, line.to_local(sub.global_position))
					for mi in _meshes(sub):
						for comp in _components(mi, mi.global_transform):
							var nm := _name("arch", comp.color)
							if comp.color.is_equal_approx(line.accent):
								nm = ["portal beam/strip", "tunnel"]
							_add_convex(comp.points, {"kind": nm[1], "name": "%s (portal @f%d)" % [nm[0], at], "ride": line.design, "color": comp.color, "arch": at})
		elif child is MeshInstance3D:
			for comp in _components(child, child.global_transform):
				_add_convex(comp.points, {"kind": "scenery", "name": "line mesh", "ride": line.design, "color": comp.color})


func _has_label(n: Node) -> bool:
	for c in n.get_children():
		if c is Label3D:
			return true
	return false


func _nearest_frame(line: Node3D, p: Vector3) -> int:
	var best := 0
	var d := INF
	for i in line.frames.size():
		var e: float = line.frames[i].origin.distance_squared_to(p)
		if e < d:
			d = e
			best = i
	return best


func _name(table: String, c: Color) -> Array:
	var key := c.to_html(false)
	if NAMES[table].has(key):
		return NAMES[table][key]
	return ["#" + key, "tunnel" if table == "arch" else ("scenery" if table != "park" else "garden")]


## Convex pieces of a mesh node: merged meshes are split by their per-part index ranges (Kit.merge_parts
## appends each part's vertices and indices in turn), and range chunks that share vertex positions within a
## few chunks of each other are the faces of one primitive. Points are returned in world space.
func _components(node: Node, xf: Transform3D) -> Array:
	var out := []
	if not (node is MeshInstance3D):
		for c in node.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree():
				out.append_array(_components(c, c.global_transform))
			elif c is Node3D and not (c is MeshInstance3D) and not (c is MultiMeshInstance3D) and not (c is Label3D):
				out.append_array(_components(c, c.global_transform))
		return out
	var mi := node as MeshInstance3D
	if mi.mesh == null or not mi.is_visible_in_tree():
		return out
	var fallback := Color.WHITE
	if mi.material_override is StandardMaterial3D:
		fallback = (mi.material_override as StandardMaterial3D).albedo_color
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols = arr[Mesh.ARRAY_COLOR]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null or idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var chunks: Array[Vector2i] = []
		var cur_lo := -1
		var cur_hi := -1
		for t in range(0, idx.size(), 3):
			var mn: int = mini(idx[t], mini(idx[t + 1], idx[t + 2]))
			var mx: int = maxi(idx[t], maxi(idx[t + 1], idx[t + 2]))
			if cur_hi < 0 or mn > cur_hi:
				if cur_hi >= 0:
					chunks.append(Vector2i(cur_lo, cur_hi))
				cur_lo = mn
				cur_hi = mx
			else:
				cur_lo = mini(cur_lo, mn)
				cur_hi = maxi(cur_hi, mx)
		if cur_hi >= 0:
			chunks.append(Vector2i(cur_lo, cur_hi))
		var parent := PackedInt32Array()
		parent.resize(chunks.size())
		for k in chunks.size():
			parent[k] = k
		var owner := {}
		for k in chunks.size():
			for i in range(chunks[k].x, chunks[k].y + 1):
				var p := v[i]
				var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
				var o: int = owner.get(key, -1)
				if o >= 0 and o != k and k - o <= 8:
					var ra := _find(parent, o)
					var rb := _find(parent, k)
					if ra != rb:
						parent[maxi(ra, rb)] = mini(ra, rb)
				owner[key] = k
		var groups := {}
		for k in chunks.size():
			var r := _find(parent, k)
			if not groups.has(r):
				groups[r] = []
			groups[r].append(k)
		for r in groups:
			var pts := PackedVector3Array()
			var seen := {}
			var color := fallback
			for k in groups[r]:
				for i in range(chunks[k].x, chunks[k].y + 1):
					var p := v[i]
					var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
					if seen.has(key):
						continue
					seen[key] = true
					pts.append(xf * p)
			if cols != null and not cols.is_empty():
				color = cols[chunks[groups[r][0]].x]
			if pts.size() >= 4:
				out.append({"points": pts, "color": color})
	return out


func _find(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k


func _register(rid: RID, box: AABB, info: Dictionary) -> void:
	var i := obs.size()
	info["id"] = i
	info["center"] = box.get_center()
	info["size"] = box.size
	obs.append(info)
	obs_rid.append(rid)
	obs_aabb.append(box)
	rid_index[rid] = i
	stamp.append(0)
	if box.size.x > 400.0 or box.size.z > 400.0:
		huge.append(i)
		return
	for gx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for gz in range(floori(box.position.z / CELL), floori(box.end.z / CELL) + 1):
			var key := Vector2i(gx, gz)
			if not grid.has(key):
				grid[key] = PackedInt32Array()
			grid[key].append(i)


func _body(shape: RID, xf: Transform3D) -> RID:
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(b, shape, xf)
	PhysicsServer3D.body_set_space(b, space)
	bodies.append(b)
	shapes.append(shape)
	return b


func _add_convex(points: PackedVector3Array, info: Dictionary) -> void:
	var sh := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(sh, points)
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	info["color"] = "#" + (info.color as Color).to_html(false)
	_register(_body(sh, Transform3D()), box, info)


func _add_box(size: Vector3, xf: Transform3D, info: Dictionary) -> void:
	var sh := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(sh, size * 0.5)
	_register(_body(sh, xf), xf * AABB(-size * 0.5, size), info)


## The rails, ties and columns are MultiMesh instances; a headless (dummy) rendering server does not keep
## instance transforms, so the line's own _build_track() is run once more on a capturing copy of the line
## (same frames, gauge, seat type and position) whose _instances() records the poses instead of drawing them.
## The poses are exactly the ones the game hands to its MultiMeshes, in the same order.
func _track_poses(line: Node3D) -> Array:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/world/coaster_line.gd\"\nvar captured := []\nfunc _instances(mesh: Mesh, poses: Array[Transform3D], color: Color) -> void:\n\tcaptured.append(poses.duplicate())\n"
	src.reload()
	var copy: Node3D = src.new()
	copy.frames = line.frames
	copy.gauge = line.gauge
	copy.seat_type = line.seat_type
	copy.rail_paint = line.rail_paint
	copy.accent = line.accent
	copy.support_paint = line.support_paint
	copy.transform = line.transform
	if "_keep_outs" in line:
		copy._keep_outs = line._keep_outs   # r6: supports stand clear of the scenery recorded while it was built
	copy._build_track()
	var out: Array = copy.captured
	copy.free()
	return out


func _add_track(line: Node3D) -> void:
	var g := line.global_transform
	var invert: bool = line.seat_type == "invert"
	var sets := _track_poses(line)
	for m in mini(sets.size(), 3):
		var kind: String = ["rail", "tie", "column"][m]
		var poses: Array = sets[m]
		for k in poses.size():
			var t: Transform3D = g * poses[k]
			var size := t.basis.get_scale()
			var xf := Transform3D(t.basis.orthonormalized(), t.origin)
			var frame := k / 2
			var type := kind
			if kind == "tie":
				frame = 3 * k
			elif kind == "column":
				# Supports stand at every 18th frame, though some may be left out: the frame is the nearest one to the
				# column's top (a suspended ride's hanger arm and its column come in pairs; the arm names the frame).
				var probe: Transform3D = poses[k]
				if invert:
					type = "arm" if k % 2 == 0 else "column"
					probe = poses[k - k % 2]
					frame = _nearest_support(line, probe.origin)
				else:
					type = "column"
					frame = _nearest_support(line, probe.origin + Vector3.UP * probe.basis.get_scale().y * 0.5)
			_add_box(size, xf, {"kind": "track", "type": type, "name": "%s %s" % [line.design, type], "ride": line.design, "frame": frame})


func _nearest_support(line: Node3D, p: Vector3) -> int:
	var best := 0
	var d := INF
	for i in range(0, line.frames.size(), 18):
		var e: float = line.frames[i].origin.distance_squared_to(p)
		if e < d:
			d = e
			best = i
	return best


func _add_label(line: Node3D, l: Label3D) -> void:
	# A billboard: the text's width in every horizontal direction, its line height upright.
	var font := l.font if l.font else ThemeDB.fallback_font
	var text := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size) * l.pixel_size
	var w := text.x + 2.0 * l.outline_size * l.pixel_size
	var size := Vector3(w, text.y + 2.0 * l.outline_size * l.pixel_size, w)
	_add_box(size, Transform3D(Basis.IDENTITY, l.global_position), {"kind": "platform", "name": "platform sign text", "ride": line.design, "color": "#ffffff"})


# ------------------------------------------------------------------ queries

func _cands(box: AABB) -> PackedInt32Array:
	qid += 1
	var out := PackedInt32Array()
	for i in huge:
		if obs_aabb[i].intersects(box):
			out.append(i)
	for gx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for gz in range(floori(box.position.z / CELL), floori(box.end.z / CELL) + 1):
			var list: PackedInt32Array = grid.get(Vector2i(gx, gz), PackedInt32Array())
			for i in list:
				if stamp[i] != qid:
					stamp[i] = qid
					if obs_aabb[i].intersects(box):
						out.append(i)
	return out


## Penetration depth of a box (half extents grown by `grow`) at xf into each of `targets` (obstacle indices),
## excluding `exclude`. Returns {index: depth} for the targets it touches.
func _depths(size: Vector3, xf: Transform3D, grow: float, targets: PackedInt32Array, exclude: Array[RID], exact: Shape3D = null) -> Dictionary:
	var out := {}
	var shape := BoxShape3D.new()
	shape.size = size + Vector3.ONE * 2.0 * grow
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape if exact == null else exact
	q.transform = xf
	q.exclude = exclude
	var box := xf * AABB(-shape.size * 0.5, shape.size)
	var near: Array[RID] = []
	for i in targets:
		if exact != null or obs_aabb[i].intersects(box):
			near.append(obs_rid[i])
	if near.is_empty():
		return out
	queries += 1
	var hits := state.intersect_shape(q, 32)
	var hit: Array[RID] = []
	for h in hits:
		if near.has(h.rid) and not hit.has(h.rid):
			hit.append(h.rid)
	for r in hit:
		var ex: Array[RID] = exclude.duplicate()
		for o in hits:
			if o.rid != r and not ex.has(o.rid):
				ex.append(o.rid)
		q.exclude = ex
		queries += 1
		var c := state.collide_shape(q, 32)
		var d := 0.0
		for j in range(0, c.size() - 1, 2):
			d = maxf(d, (c[j] as Vector3).distance_to(c[j + 1]))
		out[rid_index[r]] = d
	return out


func _tunnel_seen(ride: String, o: int, clear: float, i: int, piece: String) -> void:
	var tk := "%s|%d" % [ride, obs[o].get("arch", -1)]
	if not tunnel_min.has(tk) or clear < tunnel_min[tk].clearance:
		tunnel_min[tk] = {"clearance": clear, "sample": i, "piece": piece, "object": o}


func _note(key: String, ride: String, part: String, detail: String, o: int, index: int, depth: float, clearance := INF) -> void:
	if not records.has(key):
		records[key] = {"ride": ride, "part": part, "object": o, "hits": {}}
	var r: Dictionary = records[key]
	if obs[o].kind == "track":
		var f: int = obs[o].frame
		r["ofr"] = [mini(f, r.get("ofr", [f, f])[0]), maxi(f, r.get("ofr", [f, f])[1])]
	var prev: Array = r.hits.get(index, [-INF, "", INF])
	if depth > prev[0]:
		r.hits[index] = [depth, detail, minf(clearance, prev[2])]
	elif clearance < prev[2]:
		prev[2] = clearance


func _obj_key(o: int) -> String:
	var info: Dictionary = obs[o]
	if info.kind == "track" and info.type in ["column", "arm"]:
		return "%s:track:%s@%d" % [info.ride, info.type, info.frame]
	if info.kind == "track":
		return "%s:track:%s" % [info.ride, info.type]
	if info.kind == "train":
		return "%s:train" % info.ride
	return "obj%d" % o


func _audit_line(line: Node3D, report: Dictionary) -> Dictionary:
	records = {}
	var n: int = line.frames.size()
	var ds: float = line.ds
	var ride: String = line.design
	var own_train: Array[RID] = []
	var local := {}   # frame -> own rails and ties
	var local_all := {}   # frame -> all own track elements
	for i in obs.size():
		var info: Dictionary = obs[i]
		if info.ride != ride:
			continue
		if info.kind == "train":
			own_train.append(obs_rid[i])
		elif info.kind == "track":
			if not local_all.has(info.frame):
				local_all[info.frame] = []
			local_all[info.frame].append(i)
			if info.type in ["rail", "tie"]:
				if not local.has(info.frame):
					local[info.frame] = []
				local[info.frame].append(i)
	# Car parts in car space: one part-aligned box per convex part of the car mesh.
	var car_parts: Array = []
	for c in line.cars.size():
		var inv: Transform3D = line.cars[c].global_transform.affine_inverse()
		var list := []
		for comp in _components(line.cars[c], line.cars[c].global_transform):
			var b := AABB((inv * comp.points[0]), Vector3.ZERO)
			for p in comp.points:
				b = b.expand(inv * p)
			var local_pts := PackedVector3Array()
			for p in comp.points:
				local_pts.append(inv * p)
			var hull := ConvexPolygonShape3D.new()
			hull.points = local_pts
			list.append({"box": b, "hull": hull, "name": "car %d %s" % [c, "#" + (comp.color as Color).to_html(false)]})
		car_parts.append(list)
	var seat := Transform3D(Basis(Vector3.UP, PI), line.seat_origin)
	var rider_parts := [
		{"box": seat * kid_boxes[0], "name": "rider upper body"},
		{"box": seat * kid_boxes[1], "name": "rider legs"},
		{"box": AABB(line.eye - Vector3(0.15, 0.12, 0.15), Vector3(0.3, 0.24, 0.3)), "name": "rider eye camera"}]
	var reach := AABB()
	for list in car_parts:
		for p in list:
			reach = p.box if reach.size == Vector3.ZERO else reach.merge(p.box)
	for p in rider_parts:
		reach = reach.merge(p.box)
	# 1) track elements (static)
	var track_count := 0
	for i in obs.size():
		var info: Dictionary = obs[i]
		if info.ride != ride or info.kind != "track":
			continue
		track_count += 1
		var box := obs_aabb[i]
		var targets := PackedInt32Array()
		for o in _cands(box):
			if o == i:
				continue
			var oi: Dictionary = obs[o]
			if oi.ride == ride and oi.kind == "train":
				continue
			if oi.ride == ride and oi.kind == "track" and _cdist(oi.frame, info.frame, n) <= LOCAL_TRACK:
				continue
			if info.type in ["column", "arm"] and oi.kind in FOOTING:
				continue
			targets.append(o)
		if targets.is_empty():
			continue
		var shape_size: Vector3 = _box_size(i)
		var xf := _box_xf(i)
		var ex: Array[RID] = own_train.duplicate()
		ex.append(obs_rid[i])
		var d := _depths(shape_size, xf, 0.0, targets, ex)
		for o in d:
			if d[o] > TOL:
				_note("track|" + _obj_key(o), ride, "track", info.type, o, info.frame, d[o])
	# 2) the train at every sample
	var unions: Array[AABB] = []
	for c in line.cars.size():
		var u := AABB(Vector3(-line.gauge - 0.15, 0.0, -1.0), Vector3(2.0 * line.gauge + 0.3, 0.5, 2.0))   # wheels
		for p in car_parts[c]:
			u = u.merge(p.box)
		if c == 0:
			for p in rider_parts:
				u = u.merge(p.box)
		unions.append(u)
	var wheel_shape := CylinderShape3D.new()
	wheel_shape.radius = 0.17
	wheel_shape.height = 0.14
	for i in n:
		var s := i * ds
		line.place(s)
		for c in line.cars.size():
			var car: Transform3D = line.cars[c].global_transform
			var cf := posmod(roundi((s - line.pitch * c) / ds), n)
			var ex: Array[RID] = own_train.duplicate()
			for f in range(cf - 5, cf + 6):
				for o in local.get(posmod(f, n), []):
					ex.append(obs_rid[o])
			var exset := {}
			for r in ex:
				exset[r] = true
			var u := unions[c]
			var uxf := car * Transform3D(Basis.IDENTITY, u.get_center())
			var whole := uxf * AABB(-u.size * 0.5, u.size)
			var normal := PackedInt32Array()
			var tunnel := PackedInt32Array()
			for o in _cands(whole.grow(PROBE)):
				if exset.has(obs_rid[o]):
					continue
				if obs[o].kind == "tunnel":
					tunnel.append(o)
				elif obs_aabb[o].intersects(whole):
					normal.append(o)
			# The whole car (and rider) as one box first: most samples end here. A car deep in terrain is recorded
			# with that box (part boxes would only repeat it); the rider's own boxes are still tested.
			var buried := PackedInt32Array()
			if not normal.is_empty():
				var ud := _depths(u.size, uxf, 0.0, normal, ex)
				normal = PackedInt32Array()
				for o in ud:
					if obs[o].kind == "terrain" and ud[o] > DEEP:
						buried.append(o)
						_note("car|" + _obj_key(o), ride, "car", "car %d (whole-car box)" % c, o, i, ud[o])
					else:
						normal.append(o)
			if not tunnel.is_empty():
				var td := _depths(u.size, uxf, PROBE, tunnel, ex)
				tunnel = PackedInt32Array()
				for o in td:
					var clear: float = PROBE - td[o]
					if clear >= MARGIN:
						_tunnel_seen(ride, o, clear, i, "car %d whole-car box" % c)
					else:
						tunnel.append(o)
			if normal.is_empty() and tunnel.is_empty() and (buried.is_empty() or c != 0):
				continue
			var pieces: Array = []
			for p in car_parts[c]:
				pieces.append({"xf": car * Transform3D(Basis.IDENTITY, p.box.get_center()), "size": p.box.size, "name": p.name, "part": "car",
					"exact": p.hull, "exact_xf": car})
			for j in 4:
				var w: Node3D = line.wheels[4 * c + j]
				pieces.append({"xf": w.global_transform, "size": Vector3(0.34, 0.14, 0.34), "name": "car %d wheel" % c, "part": "car",
					"exact": wheel_shape, "exact_xf": w.global_transform})
			if c == 0:
				for p in rider_parts:
					pieces.append({"xf": car * Transform3D(Basis.IDENTITY, p.box.get_center()), "size": p.box.size, "name": p.name, "part": "rider"})
			for p in pieces:
				var hit_list := normal
				if p.part == "rider" and not buried.is_empty():
					hit_list = normal.duplicate()
					hit_list.append_array(buried)
				if not hit_list.is_empty():
					var d := _depths(p.size, p.xf, 0.0, hit_list, ex)
					for o in d:
						var depth: float = d[o]
						# Part boxes are a conservative envelope; against anything but terrain the car part's own
						# convex hull (a wheel's cylinder) decides.
						if depth > TOL and p.has("exact") and obs[o].kind != "terrain":
							var e := _depths(p.size, p.exact_xf, 0.0, PackedInt32Array([o]), ex, p.exact)
							depth = e.get(o, 0.0)
						if depth > TOL:
							_note(p.part + "|" + _obj_key(o), ride, p.part, p.name, o, i, depth)
				if not tunnel.is_empty():
					var d := _depths(p.size, p.xf, PROBE, tunnel, ex)
					for o in d:
						var clear: float = PROBE - d[o]
						_tunnel_seen(ride, o, clear, i, p.name)
						if clear < MARGIN:
							_note(p.part + "|" + _obj_key(o), ride, p.part, p.name, o, i, MARGIN - clear, clear)
	# 3) portals: each arch's cross-section must be open
	var arches := {}
	for i in obs.size():
		if obs[i].ride == ride and obs[i].has("arch"):
			arches[obs[i].arch] = true
	var gate_size := Vector3(reach.size.x + 2 * MARGIN, reach.size.y + 2 * MARGIN, 0.6)
	var gate_center := Vector3(reach.get_center().x, reach.get_center().y, 0)
	var blocked := []
	var worst := INF
	for a in arches:
		var xf: Transform3D = line.global_transform * line.frames[a] * Transform3D(Basis.IDENTITY, gate_center)
		var ex: Array[RID] = own_train.duplicate()
		for f in range(a - LOCAL_TRACK, a + LOCAL_TRACK + 1):
			for o in local_all.get(posmod(f, n), []):
				ex.append(obs_rid[o])
		var exset := {}
		for r in ex:
			exset[r] = true
		var targets := PackedInt32Array()
		for o in _cands(xf * AABB(-gate_size * 0.5, gate_size)):
			if not exset.has(obs_rid[o]):
				targets.append(o)
		var d := _depths(gate_size, xf, 0.0, targets, ex)
		var names := []
		for o in d:
			if d[o] > TOL:
				names.append(obs[o].name)
		if not names.is_empty():
			blocked.append({"frame": a, "s": a * ds, "objects": names})
		var tk := "%s|%d" % [ride, a]
		if tunnel_min.has(tk):
			worst = minf(worst, tunnel_min[tk].clearance)
	if not arches.is_empty():
		var low := []
		for a in arches:
			var tk := "%s|%d" % [ride, a]
			if tunnel_min.has(tk) and tunnel_min[tk].clearance < PROBE:
				low.append({"portal_frame": a, "clearance_m": snappedf(tunnel_min[tk].clearance, 0.001), "sample": tunnel_min[tk].sample, "piece": tunnel_min[tk].piece, "object": obs[tunnel_min[tk].object].name})
		low.sort_custom(func(x, y): return x.clearance_m < y.clearance_m)
		report.tunnels.append({"ride": ride, "portals": arches.size(), "gate_size_m": [snappedf(gate_size.x, 0.01), snappedf(gate_size.y, 0.01), 0.6],
			"blocked_portals": blocked, "min_clearance_m": snappedf(worst, 0.001) if worst < INF else ">= %.2f" % PROBE,
			"margin_m": MARGIN, "pass": blocked.is_empty() and worst >= MARGIN, "closest": low.slice(0, 12)})
	# intervals
	var count := 0
	for key in records:
		var r: Dictionary = records[key]
		var idx: Array = r.hits.keys()
		idx.sort()
		var gap := 20 if r.part == "track" else 6
		var start := 0
		for k in range(1, idx.size() + 1):
			if k == idx.size() or idx[k] - idx[k - 1] > gap:
				_interval(report, r, idx.slice(start, k), ds, line)
				count += 1
				start = k
	return {"frames": n, "ds": ds, "length_m": n * ds, "track_elements": track_count, "intervals": count}


func _interval(report: Dictionary, r: Dictionary, idx: Array, ds: float, line: Node3D) -> void:
	var worst := -INF
	var at: int = idx[0]
	var detail := ""
	var details := {}
	var clearance := INF
	for i in idx:
		var h: Array = r.hits[i]
		details[h[1]] = true
		clearance = minf(clearance, h[2])
		if h[0] > worst:
			worst = h[0]
			at = i
			detail = h[1]
	var o: Dictionary = obs[r.object]
	var obj := {"name": o.name, "kind": o.kind, "ride": o.ride, "center": _v(o.center), "size": _v(o.size)}
	if o.kind == "track":
		obj["name"] = ("%s %s f%d" % [o.ride, o.type, r.ofr[0]]) if r.ofr[0] == r.ofr[1] else ("%s %s f%d..f%d" % [o.ride, o.type, r.ofr[0], r.ofr[1]])
		obj["frames"] = r.ofr
	var it := {"ride": r.ride, "part": r.part, "first": idx[0], "last": idx[idx.size() - 1], "samples": idx.size(),
		"s0": snappedf(idx[0] * ds, 0.01), "s1": snappedf(idx[idx.size() - 1] * ds, 0.01),
		"worst_penetration_m": snappedf(worst, 0.001), "worst_frame": at, "worst_s": snappedf(at * ds, 0.01),
		"worst_piece": detail, "pieces": details.keys(), "object": obj, "allowed": false}
	if clearance < INF:
		it["tunnel_clearance_m"] = snappedf(clearance, 0.001)
		it["rule"] = "tunnel part closer than %.2f m to the envelope" % MARGIN
	report.intervals.append(it)


func _cdist(a: int, b: int, n: int) -> int:
	var d := absi(a - b) % n
	return mini(d, n - d)


func _box_size(i: int) -> Vector3:
	var sh: RID = PhysicsServer3D.body_get_shape(obs_rid[i], 0)
	return PhysicsServer3D.shape_get_data(sh) * 2.0


func _box_xf(i: int) -> Transform3D:
	return PhysicsServer3D.body_get_shape_transform(obs_rid[i], 0)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


# ------------------------------------------------------------------ output

func _write(report: Dictionary) -> void:
	report.intervals.sort_custom(func(a, b): return a.ride < b.ride or (a.ride == b.ride and (a.first < b.first or (a.first == b.first and a.part < b.part))))
	var path: String = args.get("out", "user://coaster-clearance.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  ", false))
	f.close()
	var lines := PackedStringArray()
	lines.append("Roller Coaster Workshop clearance audit %s (%s)" % [report.tree, report.engine])
	lines.append("tolerance %.2f m, tunnel margin %.2f m; conflicts %d; complete %s" % [TOL, MARGIN, report.conflicts, report.complete])
	for ride in report.rides:
		var s: Dictionary = report.rides[ride]
		lines.append("%s: %d frames x %.3f m = %.1f m, %d track elements, %d intervals" % [ride, s.frames, s.ds, s.length_m, s.track_elements, s.intervals])
	lines.append("")
	lines.append("ride | frames | s (m) | part | piece | object (kind, owner, centre) | worst pen. (m) @frame")
	for it in report.intervals:
		lines.append("%s | %d..%d | %.1f..%.1f | %s | %s | %s (%s, %s, %s) | %.3f @%d%s" % [it.ride, it.first, it.last, it.s0, it.s1, it.part, it.worst_piece,
			it.object.name, it.object.kind, it.object.ride if it.object.ride != "" else "park", it.object.center, it.worst_penetration_m, it.worst_frame,
			(" (tunnel clearance %.3f)" % it.tunnel_clearance_m) if it.has("tunnel_clearance_m") else ""])
	lines.append("")
	for t in report.tunnels:
		lines.append("tunnel %s: %d portals, blocked %d, min clearance %s (margin %.2f) -> %s" % [t.ride, t.portals, t.blocked_portals.size(), str(t.min_clearance_m), t.margin_m, "PASS" if t.pass else "FAIL"])
	var tf := FileAccess.open(path.get_basename() + ".txt", FileAccess.WRITE)
	tf.store_string("\n".join(lines) + "\n")
	tf.close()
	print("\n".join(lines))
	print("CLEARANCE wrote ", ProjectSettings.globalize_path(path))
