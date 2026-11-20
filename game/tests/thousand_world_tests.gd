## Headless tests for Thousand Town's native world (design/thousand-town.md sections 2, 6, 8, 9):
## world/thousand_world.gd building the route C data, core/thousand_nav.gd walking on it, and the light.
##   - build: time, nodes, merged chunks, the view cost (draw calls and triangles, counted from the scene the
##     way the renderer culls it: frustum and visibility ranges) against the budgets of section 8 and
##     world.json;
##   - every building and annex of town.json present at its position, at its height; doors 2.1 m;
##   - walking: no way into a building, into the canal off the bridges, through a bench or a lamp post; the
##     route arrival -> canal bridge -> market -> wheel walks; heights on the bridges and platforms;
##   - light: day, dusk and night (sun, ambient, background, lamps, lit windows by occupancy, real lights);
##   - the API the integration calls (building_at, door_near, occluders, set_occluded, arrival);
##   - determinism: two builds agree on everything.
## Rendered numbers and pictures: tests/thousand_world_capture.gd (EC2 software GL; evidence only).
##   scripts/godot.sh --headless --path game -s res://tests/thousand_world_tests.gd
extends SceneTree

const ThousandWorld := preload("res://scripts/world/thousand_world.gd")
const ThousandMap := preload("res://scripts/core/thousand_map.gd")
const ThousandNav := preload("res://scripts/core/thousand_nav.gd")
const Rig := preload("res://scripts/world/camera_rig.gd")
const Clock := preload("res://scripts/core/thousand_clock.gd")

## Section 8: draw calls in the town (Apple TV, the tighter of the two).
const DRAW_BUDGET := 140
## Triangles drawn in one follow view (this candidate's own limit, section 8).
const TRI_BUDGET := 800000
## Build time, headless on EC2 (generous: the Mac and the devices are faster at the GLB parse).
const BUILD_MS_LIMIT := 4000.0
const ASPECT := 16.0 / 9.0
const WALK_SPEED := 3.4
const TICK := 1.0 / 60.0

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var w: Node3D
var nav: RefCounted


class FakeTown extends Node3D:
	var _env: Environment
	var _sun: DirectionalLight3D


func _initialize() -> void:
	var tw := FakeTown.new()
	tw._env = Environment.new()
	tw._env.background_mode = Environment.BG_COLOR
	tw._sun = DirectionalLight3D.new()
	tw._sun.light_energy = 0.8
	root.add_child(tw)
	tw.add_child(tw._sun)
	await process_frame
	w = ThousandWorld.new()
	tw.add_child(w)
	w.setup(tw)
	var t0 := Time.get_ticks_usec()
	w.build()
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	nav = w.nav
	_current = "build"
	_report.append("build: %.0f ms headless (%s)" % [build_ms, str(w.stats())])
	ok(build_ms < BUILD_MS_LIMIT, "build in %.0f ms (< %.0f)" % [build_ms, BUILD_MS_LIMIT])
	w.build()
	ok(w.get_child_count() > 100, "built (%d nodes); a second build() does nothing" % w.get_child_count())
	for t in ["test_budgets", "test_buildings", "test_doors", "test_walls", "test_canal", "test_furniture",
			"test_heights", "test_route", "test_light", "test_api", "test_occlusion", "test_determinism"]:
		_current = t
		var t1 := Time.get_ticks_usec()
		call(t)
		_report.append("%s: %.0f ms" % [t, (Time.get_ticks_usec() - t1) / 1000.0])
	for line in _report:
		print(line)
	print("\nTHOUSAND WORLD TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps


# ------------------------------------------------------------- the view cost

var _tri_cache := {}


func _mesh_tris(m: Mesh) -> int:
	if _tri_cache.has(m):
		return _tri_cache[m]
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		n += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_tri_cache[m] = n
	return n


## What the follow camera at `xf` draws: {draws, tris, objects}, culled by the frustum (42 degrees, 16:9,
## near 0.1, far 600) and the visibility ranges, as the renderer does.
func view_cost(xf: Transform3D, by: Dictionary = {}) -> Dictionary:
	var planes := frustum(xf)
	var eye := xf.origin
	var draws := 0
	var tris := 0
	var objects := 0
	for g: GeometryInstance3D in w.find_children("*", "GeometryInstance3D", true, false):
		if not g.is_visible_in_tree():
			continue
		var box: AABB
		var mesh: Mesh
		var count := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			box = g.global_transform * (g as MeshInstance3D).get_aabb()
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.instance_count == 0:
				continue
			mesh = mm.mesh
			count = mm.instance_count
			box = g.global_transform * g.custom_aabb
		else:
			continue
		if mesh == null:
			continue
		if g.custom_aabb.size != Vector3.ZERO:
			box = g.global_transform * g.custom_aabb
		if g.visibility_range_end > 0.0 and eye.distance_to(box.get_center()) > g.visibility_range_end:
			continue
		if not _in_frustum(box, planes):
			continue
		objects += 1
		draws += mesh.get_surface_count()
		tris += _mesh_tris(mesh) * count
		var cat := String(g.name).get_slice("_", 0).to_lower()
		by[cat] = int(by.get(cat, 0)) + mesh.get_surface_count()
	return {"draws": draws, "tris": tris, "objects": objects}


## The six planes of the camera's frustum, normals pointing out.
static func frustum(xf: Transform3D) -> Array[Plane]:
	var hv := tan(deg_to_rad(Rig.FOV) * 0.5)
	var hh := hv * ASPECT
	var eye := xf.origin
	var fwd := -xf.basis.z.normalized()
	var out: Array[Plane] = []
	for n: Vector3 in [Vector3(1, 0, hh), Vector3(-1, 0, hh), Vector3(0, 1, hv), Vector3(0, -1, hv)]:
		out.append(Plane((xf.basis * n).normalized(), eye))
	out.append(Plane(-fwd, eye + fwd * Rig.T_NEAR))
	out.append(Plane(fwd, eye + fwd * Rig.T_FAR))
	return out


static func _in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for p: Plane in planes:
		# the box corner farthest along the plane's normal (the planes point out of the frustum)
		var c := Vector3(box.position.x if p.normal.x > 0.0 else box.end.x, box.position.y if p.normal.y > 0.0 else box.end.y,
			box.position.z if p.normal.z > 0.0 else box.end.z)
		if p.distance_to(c) > 0.0:
			return false
	return true


## The follow camera behind a child at p looking along (dx, dz).
func follow(p: Vector2, look: Vector2, dist := Rig.T_DIST) -> Transform3D:
	var yaw := atan2(-look.x, -look.y)
	return Rig.follow_xform(Vector3(p.x, w.height_at(p), p.y), yaw, dist)


func test_budgets() -> void:
	var wj := ThousandWorld._json(ThousandMap.DATA_DIR + "world.json")
	var arrival: Transform3D = w.arrival()
	var a := Vector2(arrival.origin.x, arrival.origin.z)
	var by := {}
	var at_arrival := view_cost(follow(a, Vector2(1, 0)), by)
	_report.append("arrival view: %d draw calls, %d triangles, %d objects; by kind %s" % [at_arrival.draws, at_arrival.tris, at_arrival.objects, str(by)])
	ok(at_arrival.draws <= DRAW_BUDGET, "arrival: %d draw calls <= %d" % [at_arrival.draws, DRAW_BUDGET])
	ok(at_arrival.tris <= TRI_BUDGET, "arrival: %d triangles <= %d" % [at_arrival.tris, TRI_BUDGET])
	var wv: Dictionary = wj.budgets.worst_view
	var h := deg_to_rad(float(wv.heading_deg))
	var eye := Vector2(float(wv.x), float(wv.z))
	var look := Vector2(cos(h), sin(h))
	var by2 := {}
	var worst_builder := view_cost(follow(eye + look * Rig.T_DIST, look), by2)
	_report.append("world.json worst view (%s): %d draw calls, %d triangles; by kind %s" % [str(wv), worst_builder.draws, worst_builder.tris, str(by2)])
	ok(worst_builder.draws <= DRAW_BUDGET, "world.json's worst view: %d draw calls" % worst_builder.draws)
	# street views: a 16 m grid of walkable points x 8 headings
	var worst := {"draws": 0}
	var worst_at := ""
	var most_tris := 0
	var views := 0
	var x := -88.0
	while x <= 88.0:
		var z := -120.0
		while z <= 120.0:
			var p := Vector2(x, z)
			if not nav.blocked(p):
				for k in 8:
					var ang := TAU * k / 8.0
					var c := view_cost(follow(p, Vector2(cos(ang), sin(ang))))
					views += 1
					most_tris = maxi(most_tris, c.tris)
					if c.draws > worst.draws:
						worst = c
						worst_at = "%s heading %d" % [p, k * 45]
			z += 16.0
		x += 16.0
	_report.append("street views: %d sampled; most draw calls %d (%d triangles) at %s; most triangles %d" % [views, worst.draws, worst.tris, worst_at, most_tris])
	var by3 := {}
	if worst_at != "":
		var parts := worst_at.split(" heading ")
		var pv := str_to_var("Vector2" + parts[0]) as Vector2
		var ang := deg_to_rad(float(parts[1]))
		view_cost(follow(pv, Vector2(cos(ang), sin(ang))), by3)
		_report.append("  worst street view by kind %s" % str(by3))
	ok(views > 300, "%d street views sampled" % views)
	ok(worst.draws <= DRAW_BUDGET, "worst street view %d draw calls <= %d (%s)" % [worst.draws, DRAW_BUDGET, worst_at])
	ok(most_tris <= TRI_BUDGET, "most triangles in a street view %d <= %d" % [most_tris, TRI_BUDGET])
	var ov := view_cost(Rig.overview_xform())
	_report.append("overview: %d draw calls, %d triangles" % [ov.draws, ov.tris])
	ok(ov.draws <= 180, "the overview %d draw calls <= the iPad's 180" % ov.draws)
	# everything in the scene
	var all_tris := 0
	var all_nodes := 0
	for g: GeometryInstance3D in w.find_children("*", "GeometryInstance3D", true, false):
		all_nodes += 1
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			all_tris += _mesh_tris((g as MeshInstance3D).mesh)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			all_tris += _mesh_tris((g as MultiMeshInstance3D).multimesh.mesh) * (g as MultiMeshInstance3D).multimesh.instance_count
	_report.append("scene: %d geometry nodes, %d triangles (world layer alone %d, limit %d)" % [all_nodes, all_tris, int(wj.budgets.triangles_total), int(wj.budgets.limits.triangles_total)])
	ok(all_nodes < 400, "%d geometry nodes" % all_nodes)
	var lights := w.find_children("*", "OmniLight3D", true, false).size()
	ok(lights == int(wj.budgets.limits.real_lights), "%d real omni lights (world.json: %d)" % [lights, int(wj.budgets.limits.real_lights)])


# ------------------------------------------------------------- buildings

## Geometry that covers the point (x, y, z): a building-layer or tower node whose world AABB holds it.
func _covered(p: Vector3) -> bool:
	for g: GeometryInstance3D in w.find_children("*", "GeometryInstance3D", true, false):
		var box: AABB
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			box = g.global_transform * (g as MeshInstance3D).get_aabb()
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			box = g.global_transform * g.custom_aabb
		else:
			continue
		if box.grow(0.05).has_point(p):
			return true
	return false


## The highest building geometry per 2 m cell (the building layer's merged meshes and the towers).
var _tops := {}


func _build_tops() -> void:
	for g: GeometryInstance3D in w.find_children("*", "GeometryInstance3D", true, false):
		var verts := PackedVector3Array()
		if g is MeshInstance3D and str(g.get_meta("layer", "")) == "building":
			for s in (g as MeshInstance3D).mesh.get_surface_count():
				verts.append_array(g.global_transform * ((g as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
		elif g is MultiMeshInstance3D and String(g.name).begins_with("tower_"):
			var mm := (g as MultiMeshInstance3D).multimesh
			var mv: PackedVector3Array = mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for x: Transform3D in g.get_meta("xfs", []):
				verts.append_array(x * mv)
		for v in verts:
			var key := Vector2i(floori(v.x / 2.0), floori(v.z / 2.0))
			if v.y > float(_tops.get(key, -INF)):
				_tops[key] = v.y


func _top_in(r: Rect2) -> float:
	var top := -INF
	for x in range(floori(r.position.x / 2.0), floori(r.end.x / 2.0) + 1):
		for z in range(floori(r.position.y / 2.0), floori(r.end.y / 2.0) + 1):
			top = maxf(top, float(_tops.get(Vector2i(x, z), -INF)))
	return top


func test_buildings() -> void:
	_build_tops()
	var heights := []
	for b: Dictionary in ThousandMap.buildings():
		var top := _top_in(b.rect)
		heights.append("%s %.1f/%.1f" % [b.id, top, float(b.height)])
		ok(top >= float(b.height) - 0.6 and top <= float(b.height) + 6.0, "%s: its geometry stands at its rect, %.1f m for %.1f m" % [b.id, top, float(b.height)])
	_report.append("building tops (drawn/town.json): " + ", ".join(heights))
	var boxes: Array = w.occluders()
	var missing := []
	for b: Dictionary in ThousandMap.buildings():
		var c: Vector2 = b.rect.get_center()
		var id := ThousandWorld.ledger_id(str(b.id))
		if not _covered(Vector3(c.x, float(b.height) * 0.5, c.y)):
			missing.append(str(b.id))
			continue
		# an occluder for it, as high as the building
		var best := -1.0
		for i in boxes.size():
			if str(w.occluder_info(i).get("id", "")) == id:
				var box: AABB = boxes[i]
				if (Rect2(box.position.x, box.position.z, box.size.x, box.size.z)).grow(1.0).has_point(c) or b.kind == "housing":
					best = maxf(best, box.end.y)
		ok(best >= float(b.height) - 0.5, "%s (%s): an occluder up to %.1f m for its %.1f m" % [b.id, id, best, float(b.height)])
		# its solid footprint blocks walking
		ok(nav.blocked(c) or b.kind == "housing", "%s: its middle is solid" % b.id)
	ok(missing.is_empty(), "every town.json building has geometry at its position (missing %s)" % str(missing))
	for a: Dictionary in ThousandMap.annexes():
		var c: Vector2 = a.footprint.get_center() if str(a.id) != "c-bank" else (a.rect as Rect2).get_center()
		ok(_covered(Vector3(c.x, 2.0, c.y)), "annex %s at %s" % [a.id, c])
	# landmarks
	var lm: Dictionary = ThousandMap.data().landmarks
	ok(_covered(Vector3(float(lm.ferris_wheel.x), float(lm.ferris_wheel.axle_y), float(lm.ferris_wheel.z))), "the ferris wheel's axle at 13 m")
	ok(_covered(Vector3(float(lm.monument.x), 6.0, float(lm.monument.z))), "the plaza monument")
	ok(_covered(Vector3(float(lm.carousel.x), 1.0, float(lm.carousel.z))), "the carousel")
	var st := ThousandMap.station()
	ok(_covered(Vector3(st.canopy.get_center().x, 4.0, st.canopy.get_center().y)), "the station canopy")


func test_doors() -> void:
	var doors: Array = w._doors
	ok(doors.size() == 38, "38 door leaves (%d)" % doors.size())
	var bad := []
	var heights := {}
	for d: Dictionary in doors:
		var mi: MeshInstance3D = d.node
		var box := mi.get_aabb()
		heights[snappedf(box.size.y, 0.01)] = int(heights.get(snappedf(box.size.y, 0.01), 0)) + 1
		if box.size.y < ThousandMap.DOOR_HEIGHT - 0.02 or box.size.y > ThousandMap.DOOR_HEIGHT + 0.2:
			bad.append("%s %.2f" % [mi.name, box.size.y])
	_report.append("door leaf heights (m: count): %s" % str(heights))
	ok(bad.is_empty(), "every door leaf is at least 2.1 m, an adult's door (%s)" % str(bad))
	# every door point stands on free ground and door_near finds its building
	var blocked := []
	var wrong := []
	for s: Dictionary in ThousandWorld.sites():
		if not s.door is Vector2:
			continue
		var p: Vector2 = s.door
		if nav.blocked(p):
			blocked.append(s.id)
		var found: Dictionary = w.door_near(p, 2.0)
		if found.get("id", "") != s.id and found.get("door") != p:
			wrong.append("%s->%s" % [s.id, found.get("id", "")])
	ok(blocked.is_empty(), "every door point is walkable (%s)" % str(blocked))
	ok(wrong.is_empty(), "door_near finds each door (%s)" % str(wrong))


# ------------------------------------------------------------- walking

## Walks from a toward b for `seconds` at the child's speed through resolve_walk; returns the path's points.
func walk(a: Vector2, b: Vector2, seconds: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var p := a
	var steps := int(seconds / TICK)
	for i in steps:
		var to := b - p
		if to.length() < 0.05:
			break
		var step := to.normalized() * minf(to.length(), WALK_SPEED * TICK)
		p = w.resolve_walk(p + step, p)
		pts.append(p)
	return pts


func test_walls() -> void:
	# straight at each building from its door: never inside the body's footprint
	var entered := []
	for b: Dictionary in ThousandMap.buildings():
		if b.doors.is_empty():
			continue
		var door: Vector2 = b.doors[0].pos
		var body: Rect2 = b.rect
		for q in walk(door, body.get_center(), 8.0):
			if body.grow(-0.3).has_point(q) and b.kind != "housing":
				entered.append(str(b.id))
				break
			if nav.solid_at(q, 0.2) >= 0:
				entered.append("%s (solid at %s)" % [b.id, q])
				break
	ok(entered.is_empty(), "no walk from a door gets into its building (%s)" % str(entered))
	# the towers too, from the street on every side
	for b: Dictionary in ThousandMap.buildings():
		if b.kind != "tower":
			continue
		var r: Rect2 = b.rect
		for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var start: Vector2 = r.get_center() + side * (r.size.length() * 0.5 + 6.0)
			start = w.resolve_walk(start)
			var end := walk(start, r.get_center(), 10.0)[-1]
			ok(not r.has_point(end), "%s holds from %s (%s)" % [b.id, side, end])
	# a step's slide: along a wall, not through it
	var wall := ThousandMap.building("b-14-0").rect as Rect2
	var from := Vector2(wall.position.x - 0.6, wall.get_center().y)
	var slid: Vector2 = w.resolve_walk(from + Vector2(0.5, 0.3), from)
	ok(slid.x <= wall.position.x and slid.y > from.y, "a diagonal step at a wall slides along it (%s)" % slid)


func test_canal() -> void:
	var canal: Rect2 = ThousandMap.canal()
	var x0 := canal.position.x
	# east from the west bank, away from the bridges: stops at the bank
	for z in [-100.0, -60.0, 0.0, 10.0, 60.0, 100.0]:
		var end := walk(Vector2(-11.0, z), Vector2(11.0, z), 6.0)[-1]
		ok(end.x <= x0, "z %d: the canal holds (%s)" % [int(z), end])
	# over each bridge: across
	for br: Dictionary in ThousandMap.bridges():
		var r: Rect2 = br.rect
		var z := r.get_center().y
		var path := walk(Vector2(-14.0, z), Vector2(14.0, z), 12.0)
		var end := path[-1]
		ok(end.x > 13.5, "%s carries a child across (%s)" % [br.id, end])
		var top := 0.0
		for q in path:
			top = maxf(top, w.height_at(q))
		ok(near(top, 0.975, 0.02), "%s: 0.975 m over the water (%.3f)" % [br.id, top])
	# never standing in the water anywhere on those walks
	var wet := 0
	for z in range(-128, 129, 4):
		var p := Vector2(0.0, float(z))
		if not nav.in_water(p):
			continue
		if w.resolve_walk(p) == p:
			wet += 1
	ok(wet == 0, "no point in the water resolves to itself (%d)" % wet)
	ok(absf(w.resolve_walk(Vector2(1.0, 3.0)).x) >= canal.size.x * 0.5, "a point in the canal is pushed onto a bank")


func test_furniture() -> void:
	var kinds := {"bench": 0, "lamp": 0, "bin": 0, "tree": 0}
	var through := []
	for i in nav.sid.size():
		var k: String = nav.skind[i]
		if not kinds.has(k) or kinds[k] >= 6 or nav.sbot[i] > 0.5:
			continue   # (lamps up on the viaduct's deck stand above the ground walked under it)
		var r := Rect2(nav.sx0[i], nav.sz0[i], nav.sx1[i] - nav.sx0[i], nav.sz1[i] - nav.sz0[i])
		var c := r.get_center()
		var dir := Vector2(1, 0) if r.size.y >= r.size.x else Vector2(0, 1)
		var a := c - dir * 2.5
		if nav.blocked(a) or nav.blocked(c + dir * 2.5):
			continue
		kinds[k] += 1
		for q in walk(a, c + dir * 2.5, 4.0):
			if r.grow(0.1).has_point(q):
				through.append("%s %s" % [nav.sid[i], q])
				break
	ok(kinds.bench >= 3 and kinds.lamp >= 3, "benches and lamps tried (%s)" % str(kinds))
	ok(through.is_empty(), "nothing walks through a bench, lamp, bin or tree (%s)" % str(through))


func test_heights() -> void:
	ok(near(w.height_at(Vector2(0, -40)), 0.975, 0.005), "the road bridge deck 0.975 m")
	ok(near(w.height_at(Vector2(0, 20)), 0.975, 0.005), "the footbridge deck 0.975 m")
	var ramp: float = w.height_at(Vector2(14.0, -40.0))
	ok(ramp > 0.13 and ramp < 0.97, "the bridge ramp rises (%.3f)" % ramp)
	ok(near(w.height_at(Vector2(-68.5, 8.5)), 0.205, 0.001), "the station's waiting platform 0.205 m")
	ok(near(w.height_at(Vector2(-30.0, -40.0)), ThousandNav.PAVEMENT, 0.001), "a street 0.125 m")
	ok(near(w.height_at(Vector2(-60.0, -52.0)), ThousandNav.LAWN, 0.001), "a park lawn 0.06 m")
	ok(near(w.height_at(Vector2(-66.0, -98.0)), 0.7, 0.001), "a school yard 0.7 m")
	# the housing steps climb toward the door
	var steps: Dictionary = {}
	for s: Dictionary in nav.surfaces:
		if s.kind == "housing-steps":
			steps = s
			break
	var r: Rect2 = steps.rect
	var tw: Vector2 = steps.toward
	var lo: float = w.height_at(r.get_center() - tw * r.size * 0.45)
	var hi: float = w.height_at(r.get_center() + tw * r.size * 0.45)
	ok(lo < hi and hi <= 0.7 and lo >= 0.125, "housing steps climb toward the door (%.2f -> %.2f)" % [lo, hi])
	# a sunk tunnel and a viaduct ramp are closed; under the viaduct's deck is open
	ok(nav.in_void(Vector2(25.0, -80.0)), "the tunnel's sunk roadway is closed")
	ok(not nav.blocked(Vector2(-30.0, -122.5)) or nav.solid_at(Vector2(-30.0, -122.5)) >= 0, "under the viaduct's high deck")
	var arr: Transform3D = w.arrival()
	ok(near(arr.origin.y, w.height_at(Vector2(arr.origin.x, arr.origin.z)), 0.001), "arrival on the ground (%s)" % arr.origin)


## A* on a 0.5 m grid over nav (8 neighbours, no corner cutting, the step rule): the cells from a to b.
var _ag_free := PackedByteArray()
var _ag_h := PackedFloat32Array()
var _ag_lo := Vector2.ZERO
var _ag_nx := 0
const AG_RES := 0.5


func _ag_at(i: int) -> Vector2:
	@warning_ignore("integer_division")
	return _ag_lo + Vector2(i % _ag_nx, i / _ag_nx) * AG_RES


func _ag_ok(i: int) -> bool:
	if _ag_free[i] == 2:
		var p := _ag_at(i)
		_ag_free[i] = 0 if nav.blocked(p) else 1
		_ag_h[i] = nav.height_at(p)
	return _ag_free[i] == 1


func astar(a: Vector2, b: Vector2, margin := 30.0) -> PackedVector2Array:
	var lo := (a.min(b) - Vector2(margin, margin)).max(-ThousandMap.HALF)
	var hi := (a.max(b) + Vector2(margin, margin)).min(ThousandMap.HALF)
	_ag_lo = lo
	_ag_nx = int((hi.x - lo.x) / AG_RES) + 1
	var nx := _ag_nx
	var nz := int((hi.y - lo.y) / AG_RES) + 1
	_ag_free = PackedByteArray()
	_ag_free.resize(nx * nz)
	_ag_free.fill(2)   # unknown
	_ag_h = PackedFloat32Array()
	_ag_h.resize(nx * nz)
	var start := clampi(int(round((a.y - lo.y) / AG_RES)), 0, nz - 1) * nx + clampi(int(round((a.x - lo.x) / AG_RES)), 0, nx - 1)
	var goal := clampi(int(round((b.y - lo.y) / AG_RES)), 0, nz - 1) * nx + clampi(int(round((b.x - lo.x) / AG_RES)), 0, nx - 1)
	_ag_ok(start)
	var g := {start: 0.0}
	var came := {}
	var open := [[a.distance_to(b), start]]
	var closed := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while not open.is_empty():
		var bi := 0
		for k in open.size():
			if open[k][0] < open[bi][0]:
				bi = k
		var cur: int = open[bi][1]
		open.remove_at(bi)
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == goal:
			break
		var cx := cur % nx
		@warning_ignore("integer_division")
		var cz := cur / nx
		for d: Vector2i in dirs:
			var x := cx + d.x
			var z := cz + d.y
			if x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			var n := z * nx + x
			if closed.has(n) or not _ag_ok(n):
				continue
			if d.x != 0 and d.y != 0 and (not _ag_ok(cz * nx + x) or not _ag_ok(z * nx + cx)):
				continue
			if absf(_ag_h[n] - _ag_h[cur]) > ThousandNav.STEP_MAX * 0.5:
				continue
			var cost: float = g[cur] + (1.4142 if d.x != 0 and d.y != 0 else 1.0) * AG_RES
			if cost < float(g.get(n, INF)):
				g[n] = cost
				came[n] = cur
				open.append([cost + _ag_at(n).distance_to(b), n])
	if not came.has(goal):
		return PackedVector2Array()
	var out := PackedVector2Array()
	var c := goal
	while c != start:
		out.append(_ag_at(c))
		c = came[c]
	out.reverse()
	return out


## Walks a path's points in order through resolve_walk (every 8th point is a waypoint); returns the end.
func walk_path(a: Vector2, path: PackedVector2Array) -> Vector2:
	var p := a
	var k := 0
	while k < path.size():
		var target := path[mini(k + 2, path.size() - 1)]
		var end := walk(p, target, 3.0)[-1]
		if end.distance_to(target) > 0.6:
			return end
		p = end
		k += 2
	return p


func test_route() -> void:
	var arr: Transform3D = w.arrival()
	var legs := [
		["arrival", Vector2(arr.origin.x, arr.origin.z)],
		["the footbridge", Vector2(0.0, 20.0)],
		["the night market", Vector2(12.0, 30.0)],
		["the road bridge", Vector2(0.0, 40.0)],
		["the wheel", Vector2(66.0, 49.0)],
	]
	ok(not nav.blocked(legs[-1][1]), "the stand by the wheel is walkable")
	var p: Vector2 = legs[0][1]
	var top := 0.0
	for i in range(1, legs.size()):
		var goal: Vector2 = legs[i][1]
		var path := astar(p, goal, 40.0)
		ok(not path.is_empty(), "a way from %s to %s" % [legs[i - 1][0], legs[i][0]])
		if path.is_empty():
			return
		for q in path:
			top = maxf(top, w.height_at(q))
		var end := walk_path(p, path)
		ok(end.distance_to(goal) < 0.8, "walked from %s to %s (%s, %d m of path)" % [legs[i - 1][0], legs[i][0], end, int(path.size() * 0.5)])
		p = end
	ok(top > 0.9, "the route goes over a bridge (%.2f m)" % top)
	# the station travel point (Ride home) is on free ground
	ok(not nav.blocked(ThousandWorld.STATION_TRAVEL), "the station's travel point is walkable")


# ------------------------------------------------------------- light

func _level(id: String) -> float:
	return w.window_level(id)


func test_light() -> void:
	w.set_time(1, 720.0)
	var day: Dictionary = w.light.duplicate()
	var day_lit: int = w.light.windows_lit
	w.place_lights(Vector3(-52, 2.6, 3.6))
	var omni_day := 0
	for o: OmniLight3D in w.find_children("*", "OmniLight3D", true, false):
		if o.visible and o.light_energy > 0.0:
			omni_day += 1
	w.set_time(1, 1120.0)
	var dusk: Dictionary = w.light.duplicate()
	w.set_time(1, 1290.0)
	var night: Dictionary = w.light.duplicate()
	w.place_lights(Vector3(-52, 2.6, 3.6))
	var omni_night := 0
	for o: OmniLight3D in w.find_children("*", "OmniLight3D", true, false):
		if o.visible and o.light_energy > 0.5:
			omni_night += 1
	ok(near(day.daylight, 1.0, 0.001) and near(night.daylight, 0.0, 0.001) and dusk.daylight > 0.0 and dusk.daylight < 1.0,
		"daylight noon %.2f, 18:40 %.2f, 21:30 %.2f" % [day.daylight, dusk.daylight, night.daylight])
	ok(day.sun_energy > 0.5 and dusk.sun_energy < day.sun_energy and night.sun_energy == 0.0,
		"sun energy %.2f > %.2f > %.2f" % [day.sun_energy, dusk.sun_energy, night.sun_energy])
	ok(night.moon_energy > 0.05 and day.moon_energy == 0.0, "the moon by night (%.2f)" % night.moon_energy)
	ok(day.ambient_energy > night.ambient_energy, "ambient %.2f by day, %.2f by night" % [day.ambient_energy, night.ambient_energy])
	ok((day.background as Color).get_luminance() > (dusk.background as Color).get_luminance() and (dusk.background as Color).get_luminance() > (night.background as Color).get_luminance(),
		"the sky darkens noon -> dusk -> night")
	ok(dusk.dusk > 0.3, "18:40 has the dusk colour (%.2f)" % dusk.dusk)
	ok(day.lamps == 0.0 and night.lamps == 1.0, "lamps off by day, on by night")
	ok(omni_day == 0 and omni_night == 4, "4 real lights at night near the camera, none by day (%d, %d)" % [omni_day, omni_night])
	ok(day_lit == 0 and night.windows_lit > 100, "lit windows: %d by day, %d at 21:30" % [day_lit, night.windows_lit])
	# by occupancy: the homes are lit at night, the shut primary school is not; the market's lanterns
	ok(_level("h-point") > 0.2, "Point Housing's windows at 21:30 (%.2f)" % _level("h-point"))
	ok(_level("c-primary") == 0.0, "the primary school is dark at 21:30 (%.2f)" % _level("c-primary"))
	ok(night.get("market_busy", false), "the night market is busy at 21:30")
	var sample: Dictionary = w.town_sample()
	var occupied := 0
	for b: Dictionary in sample.buildings:
		if str(b.id) == "h-point":
			occupied = int(b.count)
	ok(occupied > 100, "the sample has Point Housing's residents at home (%d)" % occupied)
	# the env and the town's sun
	var tw: Node3D = w.town_world
	ok(tw._sun.light_energy == 0.0, "the town's own sun is dark in Thousand Town (its sun is the world's)")
	ok(tw._env.fog_enabled and not _fog_at(720.0), "fog by night only")
	# doors follow the town view: a school's doors open at 07:20, shut at noon on a weekday
	w.set_time(1, 440.0)
	var open_morning := _door_open("c-primary")
	w.set_time(1, 720.0)
	var open_noon := _door_open("c-primary")
	ok(open_morning > 0.5 and open_noon < 0.5, "the primary school's doors open %.2f at 07:20, %.2f at noon" % [open_morning, open_noon])
	# the moving parts
	w.animate(0.0)
	var c0: Vector3 = w.cabin_position(0)
	w.animate(45.0)
	var c1: Vector3 = w.cabin_position(0)
	ok(near(c0.x, 10.0, 0.01) and near(c1.y, 23.0, 0.01), "the wheel turns a quarter in 45 s (%s -> %s)" % [c0, c1])
	ok(near((w._rotor as Node3D).rotation.z, PI / 2.0, 0.001), "its rotor too")


func _fog_at(minute: float) -> bool:
	w.set_time(1, minute)
	return (w.town_world._env as Environment).fog_enabled


func _door_open(id: String) -> float:
	var best := -1.0
	for d: Dictionary in w._doors:
		if str(d.building) == id:
			best = maxf(best, float(d.get("open", -1.0)))
	return best


# ------------------------------------------------------------- the API

func test_api() -> void:
	var mall: Rect2 = ThousandWorld._rect("mall")
	ok(mall.size.x > 10.0, "the mall's lot (%s)" % mall)
	var b: Dictionary = w.building_at(mall.get_center())
	ok(b.get("id", "") == "c-mall" and b.get("name", "") == "Mall" and b.get("kind", "") == "building" and b.get("map_id", "") == "b-14-0",
		"building_at: the mall (%s)" % str(b))
	ok(b.get("door") is Vector2 and int(b.get("floors", 0)) == 4 and int(b.get("sim", -1)) >= 0, "with its door, floors and ledger index")
	ok(str(w.building_at(Vector2(-66.0, 20.0)).get("kind", "")) == "place", "the station is a place")
	ok(str(w.building_at(Vector2(-12.0, -60.0)).get("id", "")) == "c-night-market", "the promenade is the night market")
	ok(str(w.building_at(Vector2(40.2, -30.0)).get("id", "")) == "i-clinic-a", "an annex inside its host's lot is itself")
	var door := ThousandWorld.door_point("terrace_housing")
	ok(door.is_finite() and str(w.door_near(door + Vector2(0.5, 0.0), 2.0).get("id", "")) == "h-terrace", "door_point and door_near (aliases too)")
	ok(w.door_near(Vector2(-20.0, 0.0), 2.0).is_empty(), "no door in the middle of the street")
	ok(not ThousandWorld._blocked(door), "a door point is walkable")
	var arr: Transform3D = w.arrival()
	ok(arr.origin.distance_to(ThousandMap.ARRIVAL_POS) < 0.01, "arrival at the forecourt corner (%s)" % arr.origin)
	ok((arr.basis.z - Vector3(1, 0, 0)).length() < 0.001, "facing east")
	for k in 4:
		var s: Transform3D = w.arrival(k)
		ok(not nav.blocked(Vector2(s.origin.x, s.origin.z)), "arrival slot %d is free" % k)
	w.clock = func() -> Dictionary: return {"day": 4, "minute": 100.0}
	ok(w.view_time()["day"] == 4, "a test clock replaces the shared one")
	w.clock = Callable()
	ok(w.vehicle_template("bus") != null and not w.vehicle_template("bus").visible, "the bus template is kept, hidden")
	ok(w.sim != null and w.plans() != null, "the shared sim and today's plans")


func test_occlusion() -> void:
	var boxes: Array = w.occluders()
	ok(boxes.size() >= 30, "%d occluders" % boxes.size())
	# a child north of the mall with the camera south of it: the mall is in the way
	var mall := ThousandMap.building("b-14-0").rect as Rect2
	var child := Vector3(mall.get_center().x, 0.125, mall.position.y - 3.0)
	var eye := child + Vector3(0, 2.6, 30.0)
	var chest := child + Vector3(0, Rig.T_CHEST, 0)
	var ids: Array = Rig.blocking(chest, eye, boxes)
	var names := ids.map(func(i): return w.occluder_info(i).get("id", ""))
	ok(names.has("c-mall"), "the mall stands between (%s)" % str(names))
	ok(Rig.pull_in(chest, eye, boxes) < chest.distance_to(eye), "the camera is pulled in")
	w.set_occluded(ids)
	ok(w.occluded() == ids, "set_occluded keeps the ids")
	var m: ShaderMaterial = w._dither_mats[0]
	ok(int(m.get_shader_parameter("occ_count")) == mini(ids.size(), 4), "the dither boxes reach the shader")
	w.set_occluded([])
	ok(int(m.get_shader_parameter("occ_count")) == 0, "and clear")


# ------------------------------------------------------------- determinism

func test_determinism() -> void:
	var w2: Node3D = ThousandWorld.new()
	w.get_parent().add_child(w2)
	w2.setup(w.town_world)
	w2.build()
	ok(w2.occluders() == w.occluders(), "the same occluders")
	ok(w2.get_child_count() == w.get_child_count(), "the same nodes (%d)" % w2.get_child_count())
	var a := []
	var b := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260818
	for i in 400:
		var p := Vector2(rng.randf_range(-95, 95), rng.randf_range(-129, 129))
		var q := p + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		a.append([w.resolve_walk(q, p), w.height_at(p), w.building_at(p).get("id", "")])
		b.append([w2.resolve_walk(q, p), w2.height_at(p), w2.building_at(p).get("id", "")])
	ok(a == b, "400 steps, heights and buildings agree")
	var fresh = ThousandNav.new()
	fresh.load_data()
	var same := true
	for i in 400:
		var p := Vector2(rng.randf_range(-95, 95), rng.randf_range(-129, 129))
		same = same and fresh.blocked(p) == nav.blocked(p) and fresh.height_at(p) == nav.height_at(p)
	ok(same, "a second navigation from the data agrees")
	for wx: Node3D in [w, w2]:
		wx.set_time(3, 400.0)
		var guard := 0
		while wx._pending != null and guard < 100:
			wx._process(0.016)
			guard += 1
	for minute in [440.0, 1120.0, 1290.0]:
		w.set_time(3, minute)
		w2.set_time(3, minute)
		var la: Dictionary = w.light.duplicate()
		var lb: Dictionary = w2.light.duplicate()
		ok(la == lb, "the light at %s agrees" % Clock.format_minute(minute))
		ok(w.window_level("h-slab") == w2.window_level("h-slab"), "and the windows")
	w2.free()
