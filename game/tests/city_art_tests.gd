## Headless tests for the city's art (design/city-district.md, "Art tests"): the static scene's draw
## calls and triangles, the moving things' draw calls, matte palette colours with no textures, a
## visible slab under every upper region, a railing or wall on every open edge and none on a shared
## edge, 16 steps on every stair's height line, level gondolas on the rim, the interaction poses and
## the cutaways. The edge checks classify edges here, independently of the art's own edge code, and
## then look for real triangles. Nothing renders.
##   scripts/godot.sh --headless --path game -s res://tests/city_art_tests.gd
extends SceneTree

const CityMap := preload("res://scripts/core/city_map.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")
const CityWorld := preload("res://scripts/world/city_world.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")

const MAX_STATIC_CALLS := 160
const MAX_STATIC_TRIS := 160000
const CELL := 1.0

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var cw: CityWorld
var _tri := PackedVector3Array()     # static triangles above the ground, 3 points each
var _grid := {}                      # Vector2i -> Array of triangle indices
var _up := {}                        # Vector2i -> Array of indices of flat, up-facing triangles


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	cw = CityWorld.new()
	root.add_child(cw)
	cw.build()
	_report.append("build: %d ms" % (Time.get_ticks_msec() - t0))
	_index()
	for t in ["test_budgets", "test_materials_and_palette", "test_structure", "test_kinds", "test_slabs", "test_edges",
			"test_stairs", "test_landings_and_supports", "test_shop_fronts", "test_pavilion", "test_gondolas", "test_seats",
			"test_cutaway", "test_states", "test_palette_keys", "test_npc_places", "test_carousel", "test_view_time",
			"test_vehicle_colours", "test_bus_stops", "test_weather_cycle", "test_lights", "test_lamp_coverage", "test_rain",
			"test_covers", "test_visibility_ranges", "test_night_budget"]:
		_current = t
		call(t)
	for line in _report:
		print(line)
	print("\nCITY ART TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


# ------------------------------------------------------------------ helpers

func _meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out


func _is_moving(mi: Node) -> bool:
	var p := String(cw.get_path_to(mi))
	return p.begins_with("Moving") or p.begins_with("Ferris/Wheel") or p.begins_with("Ferris/Gondola") or p.begins_with("Carousel/Turn")


func _static_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi in _meshes(cw):
		if not _is_moving(mi):
			out.append(mi)
	return out


func _xf_of(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != cw:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _calls(list: Array[MeshInstance3D]) -> int:
	var n := 0
	for mi in list:
		if mi.mesh:
			n += mi.mesh.get_surface_count()
	return n


func _tris(list: Array[MeshInstance3D]) -> int:
	var n := 0
	for mi in list:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			n += int(idx.size() / 3.0)
	return n


## Indexes the static triangles in 1 m cells (all above 0.3 m for the edge probes; flat up-facing
## ones above 0.025 m for the floor probes).
func _index() -> void:
	for mi in _static_meshes():
		var xf := _xf_of(mi)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in range(0, idx.size(), 3):
				var a := xf * v[idx[i]]
				var b := xf * v[idx[i + 1]]
				var c := xf * v[idx[i + 2]]
				var hi := maxf(a.y, maxf(b.y, c.y))
				var lo := minf(a.y, minf(b.y, c.y))
				var up_n := (xf.basis * nv[idx[i]]).normalized()
				var flat_up := up_n.y > 0.99 and hi - lo < 0.005 and lo > 0.025
				if hi < 0.3 and not flat_up:
					continue
				var ti := int(_tri.size() / 3.0)
				_tri.append(a)
				_tri.append(b)
				_tri.append(c)
				var x0 := int(floor(minf(a.x, minf(b.x, c.x)) / CELL))
				var x1 := int(floor(maxf(a.x, maxf(b.x, c.x)) / CELL))
				var z0 := int(floor(minf(a.z, minf(b.z, c.z)) / CELL))
				var z1 := int(floor(maxf(a.z, maxf(b.z, c.z)) / CELL))
				for gx in range(x0, x1 + 1):
					for gz in range(z0, z1 + 1):
						var key := Vector2i(gx, gz)
						if hi >= 0.3:
							if not _grid.has(key):
								_grid[key] = []
							(_grid[key] as Array).append(ti)
						if flat_up:
							if not _up.has(key):
								_up[key] = []
							(_up[key] as Array).append(ti)


## Heights of the flat up-facing triangles over a ground point.
func _tops_at(at: Vector2) -> Array[float]:
	var out: Array[float] = []
	# nudged off the exact centre: a box top's two triangles meet on its diagonal through the centre
	var p := at + Vector2(0.0131, 0.0071)
	var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	for ti: int in _up.get(key, []):
		var a := _tri[ti * 3]
		var b := _tri[ti * 3 + 1]
		var c := _tri[ti * 3 + 2]
		if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
			out.append(a.y)
	return out


## Whether any static triangle crosses the horizontal segment p0-p1.
func _hits(p0: Vector3, p1: Vector3) -> bool:
	var seen := {}
	for q: Vector3 in [p0, p1]:
		var key := Vector2i(int(floor(q.x / CELL)), int(floor(q.z / CELL)))
		if seen.has(key):
			continue
		seen[key] = true
		for ti: int in _grid.get(key, []):
			if Geometry3D.segment_intersects_triangle(p0, p1, _tri[ti * 3], _tri[ti * 3 + 1], _tri[ti * 3 + 2]) != null:
				return true
	return false


# ------------------------------------------------------------------ budgets and style

func test_budgets() -> void:
	var st := _static_meshes()
	var calls := _calls(st)
	var tris := _tris(st)
	_report.append("static scene: %d draw calls, %d triangles (budgets %d, %d)" % [calls, tris, MAX_STATIC_CALLS, MAX_STATIC_TRIS])
	ok(calls <= MAX_STATIC_CALLS, "static draw calls %d > %d" % [calls, MAX_STATIC_CALLS])
	ok(tris <= MAX_STATIC_TRIS, "static triangles %d > %d" % [tris, MAX_STATIC_TRIS])
	var moving := 0
	for v: Node3D in cw.vehicles:
		var c := _calls(_meshes(v))
		ok(c >= 1 and c <= 3, "%s: %d draw calls (1..3)" % [v.name, c])
		moving += _tris(_meshes(v))
		_report.append("%s (%s): %d draw calls, %d triangles" % [v.name, v.get_meta("kind"), c, _tris(_meshes(v))])
	var wheel_calls := _calls(_meshes(cw.wheel))
	var gondola_calls := 0
	for g: Node3D in cw.gondolas:
		gondola_calls += _calls(_meshes(g))
		moving += _tris(_meshes(g))
	moving += _tris(_meshes(cw.wheel))
	ok(cw.gondolas.size() == int(CityMap.FERRIS["gondolas"]), "8 gondolas")
	ok(wheel_calls <= 2 and gondola_calls <= 8, "Ferris wheel %d (the wheel and its night rim bulbs) + gondolas %d draw calls (2 + 8)" % [wheel_calls, gondola_calls])
	ok(cw.vehicles.size() == CityMap.VEHICLES.size() and cw.get_node_or_null("Moving/Walkers") == null, "a node per vehicle, and no walkers here (the people node draws them)")
	# the carousel: its fixed base is static; the turning part and the horses' MultiMesh at most 3 more
	var turn_calls := _calls(_meshes(cw.carousel_turn)) + cw._horses.multimesh.mesh.get_surface_count()
	ok(turn_calls <= 4, "the carousel: %d draw calls (at most 4)" % turn_calls)
	_report.append("carousel: turn, its night bulbs and horses %d draw calls (base in Street); horse %d triangles x %d" % [turn_calls,
		int(cw._horses.multimesh.mesh.get_faces().size() / 3.0), cw._horses.multimesh.instance_count])
	_report.append("Ferris: wheel %d + gondolas %d draw calls, %d triangles; base (static) %d triangles" % [wheel_calls, gondola_calls,
		_tris(_meshes(cw.wheel)) + _tris(_meshes(cw.gondolas[0])) * 8, _tris(_meshes(cw.get_node("Ferris/Base")))])
	_report.append("moving things in all: %d triangles" % moving)


func test_materials_and_palette() -> void:
	var pal := PropsCity.palette()
	var bad_colours := {}
	var all := _meshes(cw)
	for mi in all:
		var m := mi.material_override as StandardMaterial3D
		ok(m != null, "%s has a StandardMaterial3D" % cw.get_path_to(mi))
		if m == null:
			continue
		var path := String(cw.get_path_to(mi))
		var lit := mi.name.ends_with("Glow") or path.begins_with("Ferris/Gondola")
		var weather := path.begins_with("Weather/")
		ok(m.metallic == 0.0 and (m.roughness >= 0.8 or path == "Weather/Puddles"), "%s is matte (metallic 0)" % path)
		ok(m.albedo_texture == null and m.normal_texture == null and m.roughness_texture == null and m.emission_texture == null,
			"%s has no texture" % path)
		ok(m.emission_enabled == lit, "%s glows only if it is a night-lit mesh" % path)
		ok((m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED) != weather, "%s is opaque unless it is a weather layer" % path)
		for s in mi.mesh.get_surface_count():
			ok(mi.mesh.surface_get_material(s) == null, "%s: no surface material" % cw.get_path_to(mi))
			var arr := mi.mesh.surface_get_arrays(s)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			ok(cols.size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "%s: vertex colours" % cw.get_path_to(mi))
			var seen := {}
			for c in cols:
				var key := c.to_html(false)
				if seen.has(key):
					continue
				seen[key] = true
				var found := false
				for p in pal:
					# a palette tone, or the same tone faded toward the ground (scaled by 0.88..1)
					var k := (c.r + c.g + c.b) / maxf(p.r + p.g + p.b, 0.001)
					if k > 0.88 and k < 1.004 and absf(p.r * k - c.r) < 0.004 and absf(p.g * k - c.g) < 0.004 and absf(p.b * k - c.b) < 0.004:
						found = true
						break
				if not found:
					bad_colours[key] = String(cw.get_path_to(mi))
	ok(bad_colours.is_empty(), "colours outside the palette: %s" % str(bad_colours))
	_report.append("materials: %d meshes, one matte vertex-colour material, palette of %d tones" % [all.size(), pal.size()])


func test_structure() -> void:
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		var lv: Array = cw.levels.get(bid, [])
		ok(lv.size() == (b["floors"] as Array).size() + 1, "%s: a node per storey and a roof" % bid)
		for n: Node3D in lv:
			ok(n.has_meta("base_y"), "%s/%s has base_y" % [bid, n.name])
			ok(n.get_node_or_null("Shell") != null, "%s/%s has a Shell mesh" % [bid, n.name])
	for sid: String in CityMap.STAIRS:
		var r: Rect2 = CityMap.STAIRS[sid]["rect"]
		if PropsCity.building_at(r.get_center()) == "":
			ok(cw.get_node_or_null("Stairs/" + sid + "/Shell") != null, "exterior stair node %s" % sid)
	for rid: String in CityMap.REGIONS:
		if String(CityMap.REGIONS[rid]["kind"]) == "skywalk":
			ok(cw.get_node_or_null("Skywalks/" + rid + "/Shell") != null, "skywalk node %s" % rid)
	ok(cw.get_node_or_null("Ground") != null and cw.get_node_or_null("Street/Shell") != null and cw.get_node_or_null("Ferris/Base") != null, "ground, street and the wheel's base")


# ------------------------------------------------------------------ walkable geometry

func test_slabs() -> void:
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		var r: Rect2 = reg["rect"]
		var y: float = reg["y"]
		var holes: Array = reg["holes"]
		var samples := 0
		var missing := 0
		var first := ""
		var nx := maxi(1, int(ceil(r.size.x / 0.5)))
		var nz := maxi(1, int(ceil(r.size.y / 0.5)))
		for i in nx:
			for j in nz:
				var p := Vector2(r.position.x + (float(i) + 0.5) * r.size.x / float(nx), r.position.y + (float(j) + 0.5) * r.size.y / float(nz))
				var in_hole := false
				for h: Rect2 in holes:
					if h.grow(0.05).has_point(p):
						in_hole = true
				if in_hole:
					continue
				samples += 1
				var found := false
				for t in _tops_at(p):
					if absf(t - y) <= 0.03:
						found = true
				if not found:
					missing += 1
					if first == "":
						first = str(p)
		ok(samples > 0 and missing == 0, "%s: slab at %.1f missing at %d of %d points (first %s)" % [rid, y, missing, samples, first])


## Every boundary edge of every upper region and stair, sampled every 0.5 m: open edges need a railing
## or wall within 0.1 m at 0.94 m (just under the 1.0 m rail top); shared edges must be clear at 0.5 m
## and 0.94 m. Shared/open is decided here from CityMap alone.
func test_edges() -> void:
	var guards := 0
	var shared := 0
	var skipped := 0
	var by_owner := {}
	for e in _all_edges():
		var a: float = e["a"]
		var b: float = e["b"]
		var u := a + 0.25
		while u <= b - 0.25 + 0.001:
			var cls := _classify(e, u)
			if _classify(e, u - 0.15) != cls or _classify(e, u + 0.15) != cls:
				skipped += 1
				u += 0.5
				continue
			var p := _edge_point(e, u)
			var n := _edge_out(e)
			var h := _edge_height(e, p)
			var p0 := Vector3(p.x - n.x * 0.1, 0, p.y - n.y * 0.1)
			var p1 := Vector3(p.x + n.x * 0.1, 0, p.y + n.y * 0.1)
			var tally: Vector2i = by_owner.get(e["owner"], Vector2i.ZERO)
			by_owner[e["owner"]] = tally + (Vector2i(1, 0) if cls == "guard" else Vector2i(0, 1))
			if cls == "guard":
				guards += 1
				var y := h + 0.94
				ok(_hits(p0 + Vector3(0, y, 0), p1 + Vector3(0, y, 0)), "%s %s edge at %s (y %.2f): no railing or wall" % [e["owner"], e["side"], str(p), h])
			else:
				shared += 1
				for dy: float in [0.5, 0.94]:
					ok(not _hits(p0 + Vector3(0, h + dy, 0), p1 + Vector3(0, h + dy, 0)), "%s %s shared edge at %s (y %.2f): blocked at +%.2f" % [e["owner"], e["side"], str(p), h, dy])
			u += 0.5
	_report.append("edges: %d guarded samples, %d shared samples, %d near a change skipped" % [guards, shared, skipped])
	ok(guards > 200 and shared > 20, "enough edge samples")
	var gt: Vector2i = by_owner.get("gym_terrace", Vector2i.ZERO)
	ok(gt.x >= 20 and gt.y >= 15, "gym_terrace: railed on its free edges (%d samples), open to the studio (%d)" % [gt.x, gt.y])


func _all_edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid: String in CityMap.REGIONS:
		var reg: Dictionary = CityMap.REGIONS[rid]
		for e in _sides(reg["rect"], false):
			e["owner"] = rid
			e["stair"] = false
			out.append(e)
		for h: Rect2 in reg["holes"]:
			for e in _sides(h, true):
				e["owner"] = rid
				e["stair"] = false
				out.append(e)
	for sid: String in CityMap.STAIRS:
		for e in _sides(CityMap.STAIRS[sid]["rect"], false):
			e["owner"] = sid
			e["stair"] = true
			out.append(e)
	return out


func _sides(r: Rect2, hole: bool) -> Array[Dictionary]:
	var f := -1.0 if hole else 1.0
	var out: Array[Dictionary] = [
		{"side": "xmin", "x": true, "c": r.position.x, "a": r.position.y, "b": r.end.y, "out": -f},
		{"side": "xmax", "x": true, "c": r.end.x, "a": r.position.y, "b": r.end.y, "out": f},
		{"side": "zmin", "x": false, "c": r.position.y, "a": r.position.x, "b": r.end.x, "out": -f},
		{"side": "zmax", "x": false, "c": r.end.y, "a": r.position.x, "b": r.end.x, "out": f}]
	return out


func _edge_point(e: Dictionary, u: float) -> Vector2:
	return Vector2(e["c"], u) if e["x"] else Vector2(u, e["c"])


func _edge_out(e: Dictionary) -> Vector2:
	return Vector2(e["out"], 0.0) if e["x"] else Vector2(0.0, e["out"])


## A stair's height line, written out here (not the art's helper).
func _line(st: Dictionary, p: Vector2) -> float:
	var r: Rect2 = st["rect"]
	var t := 0.0
	match String(st["up"]):
		"-z": t = (r.end.y - p.y) / r.size.y
		"+z": t = (p.y - r.position.y) / r.size.y
		"-x": t = (r.end.x - p.x) / r.size.x
		_: t = (p.x - r.position.x) / r.size.x
	return lerpf(float(st["y0"]), float(st["y1"]), clampf(t, 0.0, 1.0))


func _edge_height(e: Dictionary, p: Vector2) -> float:
	if e["stair"]:
		return _line(CityMap.STAIRS[e["owner"]], p)
	return float(CityMap.REGIONS[e["owner"]]["y"])


func _is_stair_end(st: Dictionary, e: Dictionary) -> bool:
	var up := String(st["up"])
	return (up.ends_with("z") and not e["x"]) or (up.ends_with("x") and e["x"])


## "shared" where a step 0.1 m outward lands on another walkable surface at the same height
## (a stair only through its ends; a stair's low end at 0 on the ground), else "guard".
func _classify(e: Dictionary, u: float) -> String:
	var p := _edge_point(e, u)
	var h := _edge_height(e, p)
	if e["stair"]:
		var st: Dictionary = CityMap.STAIRS[e["owner"]]
		if not _is_stair_end(st, e):
			return "guard"
		if h < 0.01:
			return "shared"
	var q := p + _edge_out(e) * 0.1
	for rid: String in CityMap.REGIONS:
		if rid == e["owner"]:
			continue
		var reg: Dictionary = CityMap.REGIONS[rid]
		if absf(float(reg["y"]) - h) > 0.01 or not (reg["rect"] as Rect2).has_point(q):
			continue
		var in_hole := false
		for hr: Rect2 in reg["holes"]:
			if hr.has_point(q):
				in_hole = true
		if not in_hole:
			return "shared"
	for sid: String in CityMap.STAIRS:
		if sid == e["owner"]:
			continue
		var st: Dictionary = CityMap.STAIRS[sid]
		var r: Rect2 = st["rect"]
		if not r.has_point(q):
			continue
		var on_end := false
		if String(st["up"]).ends_with("z"):
			on_end = absf(p.y - r.position.y) < 0.01 or absf(p.y - r.end.y) < 0.01
		else:
			on_end = absf(p.x - r.position.x) < 0.01 or absf(p.x - r.end.x) < 0.01
		if on_end and absf(_line(st, p) - h) < 0.01:
			return "shared"
	return "guard"


func test_stairs() -> void:
	for sid: String in CityMap.STAIRS:
		var st: Dictionary = CityMap.STAIRS[sid]
		var r: Rect2 = st["rect"]
		var up := String(st["up"])
		var on_line := 0
		for i in CityMap.STEPS:
			var t := (float(i) + 0.5) / float(CityMap.STEPS)
			var p := r.get_center()
			match up:
				"-z": p.y = r.end.y - t * r.size.y
				"+z": p.y = r.position.y + t * r.size.y
				"-x": p.x = r.end.x - t * r.size.x
				_: p.x = r.position.x + t * r.size.x
			var line := _line(st, p)
			var best := -INF
			for top in _tops_at(p):
				if top <= line + 0.15 and top >= line - 0.15:
					best = maxf(best, top)
			if absf(best - line) <= 0.01:
				on_line += 1
			else:
				ok(false, "%s step %d: top %.3f, height line %.3f" % [sid, i + 1, best, line])
		ok(on_line == CityMap.STEPS, "%s: %d of %d step tops on the height line" % [sid, on_line, CityMap.STEPS])
		# 16 distinct step heights along the run's centre line
		var heights := {}
		for k in 120:
			var t := (float(k) + 0.5) / 120.0
			var p := r.get_center()
			match up:
				"-z": p.y = r.end.y - t * r.size.y
				"+z": p.y = r.position.y + t * r.size.y
				"-x": p.x = r.end.x - t * r.size.x
				_: p.x = r.position.x + t * r.size.x
			var line := _line(st, p)
			var best := -INF
			for top in _tops_at(p):
				if absf(top - line) <= 0.09:
					best = maxf(best, top)
			if best > -INF:
				heights[snappedf(best, 0.01)] = true
		ok(heights.size() == CityMap.STEPS, "%s: %d distinct treads (16)" % [sid, heights.size()])


# ------------------------------------------------------------------ the wheel, poses, cutaways, states

func test_gondolas() -> void:
	var hub: Vector3 = CityMap.FERRIS["hub"]
	var rad: float = CityMap.FERRIS["radius"]
	for angle: float in [0.0, 0.37, 1.9, PI, 5.1]:
		for i in int(CityMap.FERRIS["gondolas"]):
			var xf := CityWorld.gondola_transform(i, angle)
			ok(xf.basis.is_equal_approx(Basis.IDENTITY), "gondola %d level at %.2f" % [i, angle])
			ok(absf(xf.origin.distance_to(hub) - rad) < 0.001 and absf(xf.origin.z - hub.z) < 0.001, "gondola %d on the rim at %.2f" % [i, angle])
	var low := CityWorld.gondola_transform(0, 0.0)
	ok(absf(low.origin.y - float(CityMap.FERRIS["hang"]) - float(CityMap.FERRIS["board_y"])) < 0.001 and absf(low.origin.x - hub.x) < 0.001,
		"gondola 0 at angle 0 is at the bottom with its floor at board_y")
	# the rules' clock: the wheel angle is gondola 0's rim angle; every gondola's floor agrees
	for t: float in [0.0, 7.5, 33.0, 61.2]:
		var angle := CityRules.gondola_angle(0, t)
		for i in int(CityMap.FERRIS["gondolas"]):
			var floor_pos := CityWorld.gondola_transform(i, angle).origin - Vector3(0, float(CityMap.FERRIS["hang"]), 0)
			ok(floor_pos.distance_to(CityRules.gondola_pos(i, t)) < 0.001, "gondola %d at t %.1f agrees with CityRules.gondola_pos" % [i, t])
	for slot in 2:
		var rx := CityWorld.rider_transform(3, 1.0, slot)
		ok(absf(rx.origin.y - (CityWorld.gondola_transform(3, 1.0).origin.y - float(CityMap.FERRIS["hang"]))) < 0.001, "rider %d on the gondola floor" % slot)


func test_seats() -> void:
	for iid: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[iid]
		var rid := String(it["region"])
		var y := 0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
		var xf: Transform3D = CityWorld.seat_transform(iid)
		var pos: Vector2 = it["pos"]
		ok(absf(xf.origin.y - y) < 0.001 and Vector2(xf.origin.x, xf.origin.z).distance_to(pos) < 0.001, "%s at its pos on %s (y %.1f)" % [iid, rid, y])
		ok(xf.basis.y.is_equal_approx(Vector3.UP) and absf(xf.basis.determinant() - 1.0) < 0.001, "%s stands upright" % iid)
	# facing: seats toward their tables, machines toward their consoles, shops toward the counter
	var fwd := func(iid: String) -> Vector3: return (CityWorld.seat_transform(iid) as Transform3D).basis.z
	ok((fwd.call("cafe_seat_a") as Vector3).x > 0.9, "cafe seat a faces its table (east)")
	ok((fwd.call("cafe_seat_b") as Vector3).x < -0.9, "cafe seat b faces its table (west)")
	for iid: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[iid]
		if String(it["kind"]) != "shop":
			continue
		var pos: Vector2 = it["pos"]
		var best := INF
		var to := Vector2.ZERO
		for f: Dictionary in CityMap.FURNITURE:
			if String(f["kind"]) == "shop_counter":
				var r: Rect2 = f["rect"]
				var q := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
				if q.distance_to(pos) < best:
					best = q.distance_to(pos)
					to = (q - pos).normalized()
		var fv := fwd.call(iid) as Vector3
		ok(Vector2(fv.x, fv.z).dot(to) > 0.99 and best < CityMap.REACH, "%s faces its sales counter" % iid)
	ok((fwd.call("gym_treadmill_a") as Vector3).z < -0.9, "the treadmill faces its console")
	ok((fwd.call("bus_stop") as Vector3).x < -0.9, "the bus stop faces the road")
	ok((fwd.call("ferris_board") as Vector3).z < -0.9, "the wheel's boarding faces the wheel")


func test_cutaway() -> void:
	cw.set_cutaway(3.2, "office")
	var vis := {}
	for n: Node3D in cw.levels["office"]:
		vis[n.name] = n.visible
	ok(vis.get("L0", false) and vis.get("L1", false) and not vis.get("L2", true) and not vis.get("Roof", true), "office cut at L1: %s" % str(vis))
	var others := true
	for bid: String in cw.levels:
		if bid != "office":
			for n: Node3D in cw.levels[bid]:
				others = others and n.visible
	ok(others, "other buildings untouched")
	cw.set_cutaway(0.0, "gym")
	var gl: Array = cw.levels["gym"]
	ok((gl[0] as Node3D).visible and not (gl[1] as Node3D).visible and not (gl[2] as Node3D).visible, "gym cut at the ground floor")
	ok((cw.levels["office"][2] as Node3D).visible, "the office is restored when another building is cut")
	cw.apply_hidden({"office": 3.2, "gym": 0.0})
	var ol: Array = cw.levels["office"]
	ok((ol[1] as Node3D).visible and not (ol[2] as Node3D).visible and not (gl[1] as Node3D).visible and (gl[0] as Node3D).visible, "apply_hidden takes CityNav.storeys_hidden's form")
	cw.set_cutaway(0.0, "")
	var all := true
	for bid: String in cw.levels:
		for n: Node3D in cw.levels[bid]:
			all = all and n.visible
	ok(all, "building \"\" restores everything")


func test_states() -> void:
	var fake := [12.0]
	cw.clock = func() -> float: return float(fake[0])
	cw._view_ok = false
	var st := {"time": 12.0, "ferris_angle": 0.8,
		"vehicles": [{"kind": "bus", "pos": Vector3(-28, 0, 4), "ry": PI}, {"kind": "car", "pos": Vector2(0, -20), "ry": PI * 0.5},
			{"kind": "bus", "pos": Vector3(28, 0, 0), "ry": 0.0}],
		"riders": {2: [1, 5]}}
	cw.set_states(st)
	cw._shown.clear()
	cw._process(0.016)
	var angle := CityWorld.ferris_angle_at(12.0)
	ok(is_equal_approx(cw.wheel.rotation.z, angle), "the wheel turns with the clock (not the 4 Hz state)")
	ok(absf(CityWorld.ferris_angle_at(12.0) - CityRules.gondola_angle(0, 12.0)) < 1e-6, "ferris_angle_at matches CityRules")
	ok(cw.gondolas[2].transform.is_equal_approx(CityWorld.gondola_transform(2, angle)) and cw.gondolas[2].transform.basis.is_equal_approx(Basis.IDENTITY), "gondolas follow the wheel, upright")
	ok((cw.vehicles[0] as Node3D).position.is_equal_approx(Vector3(-28, 0, 4)) and is_equal_approx((cw.vehicles[0] as Node3D).rotation.y, PI), "the bus is drawn at its state")
	ok((cw.vehicles[1] as Node3D).position.is_equal_approx(Vector3(0, 0, -20)), "a ground-point position is drawn on the ground")
	ok(String((cw.vehicles[0] as Node3D).get_meta("kind")) == "bus" and String((cw.vehicles[1] as Node3D).get_meta("kind")) == "car", "vehicle kinds")
	ok(not (cw.vehicles[3] as Node3D).visible and not (cw.vehicles[4] as Node3D).visible, "vehicles without a state are hidden")
	ok(cw.riders.has(2), "riders kept")
	cw.set_states({"vehicles": [{"kind": "car", "pos": Vector3.ZERO, "ry": 0.0}], "ferris_angle": 0.0})
	cw._process(0.016)
	ok(String((cw.vehicles[0] as Node3D).get_meta("kind")) == "car" and _calls(_meshes(cw.vehicles[0])) <= 3, "a vehicle of another kind is rebuilt")
	cw.clock = Callable()


# ------------------------------------------------------------------ refinement: kinds, fronts, pavilion, stairs

## Every kind CityMap names is one the art builds, and every furniture item and solid has a top
## (something drawn) over its footprint's centre, between its floor and 3 m above it.
func test_kinds() -> void:
	var seen := {}
	for f: Dictionary in CityMap.FURNITURE:
		seen[String(f["kind"])] = true
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		seen[String(s["kind"])] = true
	for k: String in seen:
		ok(PropsCity.KINDS.has(k), "the art builds kind %s" % k)
	for k in ["bread_display", "bookshelf", "flower_stand", "freezer", "bistro_table", "coffee_bar", "pavilion_post", "flower_bed", "dining_table", "desk"]:
		ok(seen.has(k), "CityMap uses the refinement kind %s" % k)
	var items: Array[Dictionary] = []
	for f: Dictionary in CityMap.FURNITURE:
		var rid := String(f["region"])
		var rect: Rect2 = f["rect"]
		var fy := 0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
		items.append({"what": "%s at %s" % [f["kind"], rect], "at": rect.get_center(), "y": fy})
	for s: Dictionary in CityMap.GROUND_SOLIDS:
		var at: Vector2 = s["at"] if s.has("at") else (s["rect"] as Rect2).get_center()
		items.append({"what": "%s at %s" % [s["kind"], at], "at": at, "y": 0.0})
	for it in items:
		var fy: float = it["y"]
		var found := false
		for t in _tops_at(it["at"]):
			if t > fy + 0.05 and t < fy + 3.0:
				found = true
		ok(found, "%s is drawn" % it["what"])


## The shop fronts follow GROUND_WALLS and SHOP_DOORS: two display windows (wall below the glass, glass
## in it, a frame) either side of a clear door gap with a lintel above it.
func test_shop_fronts() -> void:
	for bid: String in CityMap.BUILDINGS:
		var b: Dictionary = CityMap.BUILDINGS[bid]
		if String(b.get("front", "")) != "windows":
			continue
		var door: Vector2 = CityMap.SHOP_DOORS[bid]
		var wins := PropsCity.shop_windows(bid)
		ok(wins.size() == 2, "%s: two display windows" % bid)
		var meets_left := false
		var meets_right := false
		for wn in wins:
			var wr: Rect2 = wn["rect"]
			meets_left = meets_left or absf(wr.end.x - door.x) < 0.01
			meets_right = meets_right or absf(wr.position.x - door.y) < 0.01
			var u0: float = wn["u0"]
			var u1: float = wn["u1"]
			ok(u1 - u0 > 1.2, "%s: a window %.2f m wide" % [bid, u1 - u0])
			var zc := wr.get_center().y
			var xm := (u0 + u1) * 0.5
			ok(_hits(Vector3(xm, 0.35, zc - 0.25), Vector3(xm, 0.35, zc + 0.25)), "%s: wall under the window at x %.2f" % [bid, xm])
			ok(_hits(Vector3(xm - 0.3, 1.1, zc - 0.25), Vector3(xm - 0.3, 1.1, zc + 0.25)), "%s: glass in the window at x %.2f" % [bid, xm - 0.3])
			ok(_hits(Vector3(u0 + 0.04, 1.6, zc - 0.25), Vector3(u0 + 0.04, 1.6, zc + 0.25)), "%s: a window frame at x %.2f" % [bid, u0 + 0.04])
		ok(meets_left and meets_right, "%s: the window walls meet the door gap %s" % [bid, door])
		var zd := 14.85
		for x: float in [door.x + 0.25, (door.x + door.y) * 0.5, door.y - 0.25]:
			for y: float in [0.5, 1.2, 1.9]:
				ok(not _hits(Vector3(x, y, zd - 0.3), Vector3(x, y, zd + 0.3)), "%s: the door is clear at x %.2f y %.1f" % [bid, x, y])
		ok(_hits(Vector3((door.x + door.y) * 0.5, 2.8, zd - 0.3), Vector3((door.x + door.y) * 0.5, 2.8, zd + 0.3)), "%s: a lintel over the door" % bid)
		ok(_hits(Vector3(door.x - 0.06, 1.2, zd + 0.1), Vector3(door.x - 0.06, 1.2, zd + 0.3)), "%s: a door frame on the street face" % bid)
		ok(String(b.get("sign", "")) != "" and PropsCity.text_cols(String(b["sign"])) * 0.075 < (b["rect"] as Rect2).size.x, "%s: its sign fits" % bid)
		for ch in String(b["sign"]):
			ok(ch == " " or PropsCity.FONT.has(ch), "%s: the font has %s" % [bid, ch])


## The rooftop pavilion: a post at every pavilion_post, a slatted roof above them.
func test_pavilion() -> void:
	var n := 0
	var union := Rect2()
	for f: Dictionary in CityMap.FURNITURE:
		if String(f["kind"]) != "pavilion_post":
			continue
		var r: Rect2 = f["rect"]
		var y := float(CityMap.REGIONS[String(f["region"])]["y"])
		union = r if n == 0 else union.merge(r)
		n += 1
		var c := r.get_center()
		ok(_hits(Vector3(r.position.x - 0.05, y + 1.5, c.y), Vector3(r.end.x + 0.05, y + 1.5, c.y)), "pavilion post at %s" % r)
	ok(n == 4, "four pavilion posts")
	var tops := _tops_at(union.get_center() + Vector2(0.2, 0.0))
	var roof_y := float(CityMap.REGIONS["gym_roof"]["y"]) + PropsCity.PAVILION_H
	var covered := false
	for t in tops:
		if t > roof_y and t < roof_y + 0.6:
			covered = true
	ok(covered, "the pavilion has a roof over its centre")


## Every stair stands on something: a landing pad at its foot, columns under its top landing (and at
## mid-span outdoors).
func test_landings_and_supports() -> void:
	for sid: String in CityMap.STAIRS:
		var st: Dictionary = CityMap.STAIRS[sid]
		var fr := PropsCity.stair_frame(st)
		var xf: Transform3D = fr[0]
		var length: float = fr[1]
		var hw: float = float(fr[2]) * 0.5
		var y0: float = st["y0"]
		var y1: float = st["y1"]
		var pad := xf * Vector3(0, 0, -0.45)
		var pad_ok := false
		for t in _tops_at(Vector2(pad.x, pad.z)):
			if absf(t - (y0 + 0.03)) < 0.006:
				pad_ok = true
		ok(pad_ok, "%s: a landing pad at its foot" % sid)
		for sx: float in [-1.0, 1.0]:
			var mid := (y0 + y1 - 0.66) * 0.5
			var p0 := xf * Vector3(sx * (hw - 0.12) - 0.15, 0, length - 0.15)
			var p1 := xf * Vector3(sx * (hw - 0.12) + 0.15, 0, length - 0.15)
			ok(_hits(Vector3(p0.x, mid, p0.z), Vector3(p1.x, mid, p1.z)), "%s: a column under its top (%s)" % [sid, "left" if sx < 0.0 else "right"])
		var head0 := xf * Vector3(0, 0, length - 0.35)
		var head1 := xf * Vector3(0, 0, length + 0.05)
		ok(_hits(Vector3(head0.x, y1 - 0.5, head0.z), Vector3(head1.x, y1 - 0.5, head1.z)), "%s: a header beam under its top landing" % sid)


# ------------------------------------------------------------------ city r2: palette, people's places, rides, view time

func _colours_of(root_node: Node) -> Dictionary:
	var seen := {}
	for mi in _meshes(root_node):
		for s in mi.mesh.get_surface_count():
			var cols: PackedColorArray = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			for c in cols:
				seen[c.to_html(false)] = true
	return seen


func _has_colour(seen: Dictionary, c: Color) -> bool:
	if seen.has(c.to_html(false)):
		return true
	for k: String in seen:
		var o := Color(k)
		if absf(o.r - c.r) < 0.004 and absf(o.g - c.g) < 0.004 and absf(o.b - c.b) < 0.004:
			return true
	return false


## The r2 palette is in use: every building and ground key, the cabins' pastels and the shops' accents.
func test_palette_keys() -> void:
	var seen := _colours_of(cw)
	for k in ["blue", "blue_trim", "yellow", "yellow_trim", "coral", "peach", "roof", "mint", "mint_deep", "cream", "berry",
			"white", "road", "pavement", "kerb", "ground", "glass", "wood", "green", "green_deep", "dark"]:
		ok(_has_colour(seen, PropsCity.col(k)), "the art uses palette key %s" % k)
	for i in CityMap.CABIN_COLORS.size():
		ok(_has_colour(_colours_of(cw.gondolas[i]), CityMap.CABIN_COLORS[i]), "gondola %d in its pastel" % i)
	for shop: String in CityMap.SHOP_ACCENTS:
		ok(_has_colour(seen, CityMap.SHOP_ACCENTS[shop]), "%s's accent is used" % shop)
	ok(_has_colour(_colours_of(cw.get_node("Buildings/bakery/L0")), PropsCity.col("mint")), "the shop fronts are mint")
	ok(_has_colour(_colours_of(cw.get_node("Buildings/office/Roof")), PropsCity.col("roof")), "the office roof edge is roof orange")


## Every place for the city's people: inside its region, on no child's place (>= 0.9 m from every
## INTERACTIONS spot on the same region), not inside furniture or walls unless it is its machine, facing
## what it uses, with a seat drawn under every sitter; enough places for PEOPLE_BUDGET.
func test_npc_places() -> void:
	var furn: Array = []
	furn.append_array(CityMap.FURNITURE)
	furn.append_array(PropsCity.EXTRA_FURNITURE)
	var counts := {}
	var ids := {}
	var poses := ["sit", "stand", "desk", "run", "cycle", "row", "lift", "stretch"]
	var machines := {"run": "treadmill", "cycle": "bike", "row": "rower", "lift": "weight_rack", "stretch": "mat"}
	for np: Dictionary in PropsCity.NPC_PLACES:
		var id := String(np["id"])
		var rid := String(np["region"])
		var pos: Vector2 = np["pos"]
		var pose := String(np["pose"])
		var ry := float(np["ry"])
		ok(not ids.has(id), "%s: unique id" % id)
		ids[id] = true
		counts[np["place"]] = int(counts.get(np["place"], 0)) + 1
		ok(poses.has(pose), "%s: a known pose" % id)
		var y := 0.0
		if rid == "ground":
			ok(absf(pos.x) < CityMap.HALF.x and absf(pos.y) < CityMap.HALF.y, "%s: on the map" % id)
		else:
			ok(CityMap.REGIONS.has(rid), "%s: a region" % id)
			var reg: Dictionary = CityMap.REGIONS[rid]
			y = float(reg["y"])
			var inside := (reg["rect"] as Rect2).grow(-0.2).has_point(pos)
			for h: Rect2 in reg["holes"]:
				if h.grow(0.2).has_point(pos):
					inside = false
			ok(inside, "%s: inside %s" % [id, rid])
		for iid: String in CityMap.INTERACTIONS:
			var it: Dictionary = CityMap.INTERACTIONS[iid]
			if String(it["region"]) == rid:
				ok((it["pos"] as Vector2).distance_to(pos) >= 0.9, "%s: %.2f m from the child's %s" % [id, (it["pos"] as Vector2).distance_to(pos), iid])
		for w: Rect2 in CityMap.GROUND_WALLS:
			if rid == "ground":
				ok(not w.grow(0.15).has_point(pos), "%s: clear of the wall %s" % [id, w])
		var own := ""
		var near_d := INF
		var near_dir := Vector2.ZERO
		for f: Dictionary in furn:
			if String(f["region"]) != rid:
				continue
			var r: Rect2 = f["rect"]
			if r.has_point(pos):
				own = String(f["kind"])
				continue
			var q := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
			if q.distance_to(pos) < near_d:
				near_d = q.distance_to(pos)
				near_dir = (q - pos).normalized()
		if machines.has(pose):
			ok(own == String(machines[pose]), "%s: on its %s (on %s)" % [id, machines[pose], own])
		else:
			ok(own == "", "%s: not inside furniture (%s)" % [id, own])
			var fwd := Vector2(sin(ry), cos(ry))
			ok(near_d < 1.3 and fwd.dot(near_dir) > 0.5, "%s: faces what it uses (%.2f m, dot %.2f)" % [id, near_d, fwd.dot(near_dir)])
		if pose == "sit" or pose == "desk":
			var seat := false
			for t in _tops_at(pos):
				if t > y + 0.35 and t < y + 0.8:
					seat = true
			ok(seat, "%s: a seat is drawn under it" % id)
		for other: Dictionary in PropsCity.NPC_PLACES:
			if other != np and String(other["region"]) == rid:
				ok((other["pos"] as Vector2).distance_to(pos) >= 0.45, "%s: room beside %s" % [id, other["id"]])
	for k: String in CityMap.PEOPLE_BUDGET:
		if k in ["walkers", "ferris", "carousel"]:
			continue
		ok(int(counts.get(k, 0)) >= int(CityMap.PEOPLE_BUDGET[k]), "%s: %d places for %d people" % [k, int(counts.get(k, 0)), int(CityMap.PEOPLE_BUDGET[k])])
	_report.append("NPC places: %d in all, %s" % [PropsCity.NPC_PLACES.size(), str(counts)])


## The carousel turns counter-clockwise from above, the way its horses face; they bob, staggered.
func test_carousel() -> void:
	var period := float(CityMap.CAROUSEL["period"])
	var bob := float(CityMap.CAROUSEL["bob"])
	ok(absf(CityWorld.carousel_angle_at(period * 0.25) - PI * 0.5) < 1e-5, "a quarter turn in a quarter period")
	for t: float in [0.0, 3.7, 15.2]:
		for i in int(CityMap.CAROUSEL["horses"]):
			var a := CityWorld.carousel_horse_transform(i, t)
			var b := CityWorld.carousel_horse_transform(i, t + 0.01)
			var motion := Vector3(b.origin.x - a.origin.x, 0, b.origin.z - a.origin.z).normalized()
			ok(a.basis.z.normalized().dot(motion) > 0.995, "horse %d at %.1f s faces where it goes" % [i, t])
			var b2 := CityWorld.carousel_bob(i, t)
			ok(b2 >= -1e-6 and b2 <= bob + 1e-6, "horse %d bobs within 0..%.2f" % [i, bob])
			var seat := CityWorld.carousel_seat_transform(i, t)
			ok(seat.basis.z.dot(a.basis.z) > 0.999 and absf(seat.origin.y - (PropsCity.CAROUSEL_DECK + b2 + PropsCity.SADDLE_Y + 0.05)) < 1e-4, "horse %d's seat on its saddle" % i)
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var h0 := CityWorld.carousel_horse_transform(0, 0.0).origin
	var h1 := CityWorld.carousel_horse_transform(0, 0.5).origin
	var cross_y := Vector2(h0.x - c.x, h0.z - c.y).cross(Vector2(h1.x - c.x, h1.z - c.y))
	ok(cross_y < 0.0, "counter-clockwise seen from above (east, then north)")
	ok(absf(CityWorld.carousel_bob(0, 1.0) - CityWorld.carousel_bob(0, 1.0 + float(CityMap.CAROUSEL["bob_period"]))) < 1e-5, "the bob repeats every bob_period")
	ok(absf(CityWorld.carousel_bob(0, 0.3) - CityWorld.carousel_bob(1, 0.3)) > 0.01, "neighbouring horses bob out of step")
	cw._pose_carousel(4.2)
	ok(cw.horse_xf[3].is_equal_approx(CityWorld.carousel_horse_local(3, 4.2)) and is_equal_approx(cw.carousel_turn.rotation.y, CityWorld.carousel_angle_at(4.2)), "the drawn horses follow the clock")
	ok(PropsCity.CAROUSEL_RING + 0.8 < float(CityMap.CAROUSEL["radius"]) + 0.6, "the horses stay inside the platform's edge")


## Pause freezes the view time and the vehicles; resume catches up at most 3x, eased, without a jump,
## and the vehicles glide back to their live pose.
func test_view_time() -> void:
	var fake := [100.0]
	cw.clock = func() -> float: return float(fake[0])
	cw._view_ok = false
	cw._paused = false
	cw.set_states({"time": 100.0, "vehicles": [{"kind": "bus", "pos": Vector3(-28, 0, 4), "ry": PI}]})
	cw._shown.clear()
	cw._process(0.1)
	ok(is_equal_approx(cw.view_time(), 100.0), "the view starts on the clock")
	for i in 10:
		fake[0] += 0.1
		cw._process(0.1)
	ok(absf(cw.view_time() - fake[0]) < 1e-6 and not cw.is_paused(), "the view keeps to the clock")
	cw.set_paused(true)
	var frozen := cw.view_time()
	var bus_at := (cw.vehicles[0] as Node3D).position
	cw.set_states({"time": 101.0, "vehicles": [{"kind": "bus", "pos": Vector3(-28, 0, -16), "ry": PI}]})
	for i in 50:
		fake[0] += 0.1
		cw._process(0.1)
	ok(cw.is_paused() and is_equal_approx(cw.view_time(), frozen), "paused: the view stands still (%.2f)" % cw.view_time())
	ok((cw.vehicles[0] as Node3D).position.is_equal_approx(bus_at), "paused: the vehicles stand still")
	ok(is_equal_approx(cw.wheel.rotation.z, CityWorld.ferris_angle_at(frozen)), "paused: the wheel stands still")
	cw.set_paused(false)
	var prev := cw.view_time()
	var met := -1
	var max_step := 0.0
	var mid_ok := false
	for i in 80:
		fake[0] += 0.1
		cw._process(0.1)
		var v := cw.view_time()
		max_step = maxf(max_step, v - prev)
		ok(v >= prev - 1e-9 and v <= fake[0] + 1e-9, "the view never runs backwards or ahead of the clock")
		prev = v
		if i == 2:
			var p := (cw.vehicles[0] as Node3D).position
			mid_ok = p.z < bus_at.z - 0.5 and p.z > -16.0 + 0.5
		if met < 0 and absf(v - fake[0]) < 1e-6:
			met = i
	ok(max_step <= 0.3 + 1e-6, "catching up at most 3x (largest step %.3f s per 0.1 s)" % max_step)
	ok(met > 10 and met < 60, "resume catches up smoothly, meeting the clock after %d frames" % met)
	ok(mid_ok, "on resume the bus glides from its frozen place toward the live one")
	ok((cw.vehicles[0] as Node3D).position.distance_to(Vector3(-28, 0, -16)) < 0.05, "and arrives at the live pose")
	cw.clock = Callable()


func test_vehicle_colours() -> void:
	for i in CityMap.VEHICLES.size():
		var spec: Dictionary = CityMap.VEHICLES[i]
		var v := cw._make_vehicle(String(spec["kind"]), i)
		ok(_has_colour(_colours_of(v), spec["color"]), "vehicle %d (%s) in its colour" % [i, spec["kind"]])
		ok(_calls(_meshes(v)) <= 3, "vehicle %d within 3 draw calls" % i)
		v.free()
	var buses := 0
	for spec: Dictionary in CityMap.VEHICLES:
		buses += 1 if String(spec["kind"]) == "bus" else 0
	ok(buses == 3, "three buses")


func test_bus_stops() -> void:
	var frames := CityWorld.bus_stop_frames()
	ok(frames.size() == CityMap.BUS_STOPS.size(), "a sign at every bus stop")
	for xf in frames:
		var p := Vector2(xf.origin.x, xf.origin.z)
		ok(CityMap.OUTER_PAVEMENT.has_point(p) and not CityMap.ROAD_OUTER.grow(0.3).has_point(p), "the stop at %s stands on the outer pavement" % p)
		for cr: Rect2 in CityMap.CROSSINGS:
			ok(not cr.grow(1.0).has_point(p), "the stop at %s is clear of the crossing %s" % [p, cr])
		var road := xf.basis.z
		var to_road := Vector2(-p.x, -p.y).normalized()
		ok(Vector2(road.x, road.z).dot(to_road) > 0.3, "the stop at %s faces the road" % p)
		var roofed := false
		for t in _tops_at(p):
			if t > 2.0 and t < 2.6:
				roofed = true
		ok(roofed, "the stop at %s has a shelter" % p)



# ------------------------------------------------------------------ city r3: weather, night, covers

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _materials(n: Node, out: Dictionary) -> Dictionary:
	if n is GeometryInstance3D and (n as GeometryInstance3D).material_override:
		out[(n as GeometryInstance3D).material_override.get_instance_id()] = true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			if m.surface_get_material(s):
				out[m.surface_get_material(s).get_instance_id()] = true
	if n is GPUParticles3D:
		var gp := n as GPUParticles3D
		if gp.process_material:
			out[gp.process_material.get_instance_id()] = true
		if gp.draw_pass_1 and gp.draw_pass_1.surface_get_material(0):
			out[gp.draw_pass_1.surface_get_material(0).get_instance_id()] = true
	for ch in n.get_children():
		_materials(ch, out)
	return out


## A full weather cycle only changes parameters: the same nodes and materials before and after, and
## every weather shows its look.
func test_weather_cycle() -> void:
	cw._view_ok = false
	cw._paused = false
	var nodes0 := _count_nodes(cw)
	var mats0 := _materials(cw, {})
	var looks := [{"sunny": 1.0}, {"sunny": 0.5, "rain": 0.5}, {"rain": 1.0}, {"rain": 0.3, "night": 0.7}, {"night": 1.0}, {"sunny": 1.0}]
	for w: Dictionary in looks:
		cw.set_weather_override(w)
		for i in 3:
			cw._process(0.05)
		var ww := cw.weather_weights()
		var sum := float(ww["sunny"]) + float(ww["rain"]) + float(ww["night"])
		ok(absf(sum - 1.0) < 1e-5, "weights sum to 1 for %s" % str(w))
		var rain := float(ww["rain"])
		var night := float(ww["night"])
		var glow := rain * 0.25 + night
		ok(absf(cw._ground_mat.roughness - lerpf(0.92, 0.32, rain)) < 1e-4, "wet ground roughness follows the rain (%s)" % str(w))
		ok(cw._puddles.visible == (rain > 0.003) and absf(cw._puddle_mat.albedo_color.a - 0.6 * rain) < 1e-4, "puddles fade with the rain (%s)" % str(w))
		ok(absf(cw._glow_mat.emission_energy_multiplier - 1.6 * glow) < 1e-4, "windows and lamps glow by WEATHER_LOOK glow (%s)" % str(w))
		ok(cw._pools.visible == (glow > 0.003), "light pools show with the glow (%s)" % str(w))
		ok(cw._rain.visible == (rain > 0.003), "the rain shows with the rain weight (%s)" % str(w))
		if cw._rain is GPUParticles3D:
			ok(absf((cw._rain as GPUParticles3D).amount_ratio - rain) < 1e-4, "rain amount follows the rain weight (%s)" % str(w))
		for l in cw._lights:
			ok(absf(l.light_energy - float(l.get_meta("energy")) * glow) < 1e-4, "%s steady at glow %.2f" % [l.name, glow])
	cw.set_weather_override({})
	cw._process(0.05)
	ok(absf(float(cw.weather_weights()["sunny"]) - 1.0) < 1e-6, "without a shared weather it is sunny")
	cw.set_states({"time": 10.0, "weather": 1, "since": 8.0, "prev": Vector3(1, 0, 0)})
	var fake := [10.0]
	cw.clock = func() -> float: return float(fake[0])
	cw._view_ok = false
	cw._process(0.05)
	var mid := float(cw.weather_weights()["rain"])
	ok(mid > 0.2 and mid < 0.8, "the shared weather blends over WEATHER_BLEND (rain %.2f half way)" % mid)
	fake[0] = 20.0
	cw._view_ok = false
	cw._process(0.05)
	ok(absf(float(cw.weather_weights()["rain"]) - 1.0) < 1e-3, "and arrives at rain")
	cw.clock = Callable()
	cw.set_states({})
	cw.set_weather_override({"sunny": 1.0})
	cw._process(0.05)
	cw.set_weather_override({})
	ok(_count_nodes(cw) == nodes0, "no node made or freed by the weather (%d, %d)" % [nodes0, _count_nodes(cw)])
	var mats1 := _materials(cw, {})
	ok(mats1.size() == mats0.size() and mats1.keys() == mats0.keys(), "no material made or swapped by the weather (%d, %d)" % [mats0.size(), mats1.size()])


func test_lights() -> void:
	var lights := cw.find_children("*", "Light3D", true, false)
	ok(lights.size() >= 1 and lights.size() <= 4, "%d real lights (at most 4)" % lights.size())
	for n in lights:
		var l := n as Light3D
		ok(not l.shadow_enabled and not l.distance_fade_enabled, "%s: no shadow, no distance fade" % l.name)


## Every point of both pavement loops is within 6 m of a lamp; the lamps stand on the pavement, off the
## road and crossings and clear of solids.
func test_lamp_coverage() -> void:
	var lamps: Array[Vector2] = []
	lamps.append_array(PropsCity.STREET_LAMPS)
	for s2: Dictionary in CityMap.GROUND_SOLIDS:
		if String(s2["kind"]) == "lamp":
			lamps.append(s2["at"])
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for pair: Array in [[CityMap.ROAD_INNER, CityMap.LOT], [CityMap.OUTER_PAVEMENT, CityMap.ROAD_OUTER]]:
		var outer: Rect2 = pair[0]
		var inner: Rect2 = pair[1]
		var x := outer.position.x + 0.25
		while x < outer.end.x:
			var z := outer.position.y + 0.25
			while z < outer.end.y:
				var p := Vector2(x, z)
				if not inner.has_point(p):
					var best := INF
					for l in lamps:
						best = minf(best, l.distance_to(p))
					if best > worst:
						worst = best
						worst_at = p
				z += 0.5
			x += 0.5
	ok(worst <= 6.0, "every pavement point within 6 m of a lamp (worst %.2f m at %s)" % [worst, worst_at])
	for l in PropsCity.STREET_LAMPS:
		ok(PropsCity._lamp_clear(l, PropsCity.bus_stop_frames()), "the lamp at %s stands clear" % l)
		for m in PropsCity.STREET_LAMPS:
			ok(m == l or m.distance_to(l) >= 2.4, "lamps at %s and %s are apart" % [l, m])
	_report.append("street lamps: %d added (plus %d solid ones); worst pavement point %.2f m from a lamp" % [PropsCity.STREET_LAMPS.size(), lamps.size() - PropsCity.STREET_LAMPS.size(), worst])


## The rain is bounded (drops, box, culling box) and follows the camera's focus on the map.
func test_rain() -> void:
	var r := cw._rain
	ok(r != null, "a rain node")
	if r is GPUParticles3D:
		var gp := r as GPUParticles3D
		var pm := gp.process_material as ParticleProcessMaterial
		ok(gp.amount <= 2500 and pm.emission_box_extents.x <= 20.0 and pm.emission_box_extents.z <= 20.0, "rain bounded: %d drops in a %.0f m box" % [gp.amount, pm.emission_box_extents.x * 2.0])
		ok(gp.visibility_aabb.size.length() < 80.0 and gp.visibility_aabb.size.y > CityWorld.RAIN_TOP, "a fixed culling box around the falling drops")
		ok(not gp.local_coords and pm.particle_flag_align_y, "drops fall in the world as streaks along their motion")
		ok((pm.direction.x != 0.0) and pm.direction.y < -0.9, "falling at a slight angle")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(10, 20, 25), Vector3(10, 0, 5), Vector3.UP)
	cw.focus_camera = cam
	cw.set_weather_override({"rain": 1.0})
	cw._process(0.05)
	var f := cw.rain_focus(cam)
	ok(f.distance_to(Vector3(10, 0, 5)) < 0.1, "the rain falls around the camera's focus (%s)" % f)
	ok(r.position.distance_to(f + Vector3(0, CityWorld.RAIN_TOP, 0)) < 0.1, "the rain node follows it")
	cam.look_at_from_position(Vector3(300, 20, 0), Vector3(400, 0, 0), Vector3.UP)
	f = cw.rain_focus(cam)
	ok(CityMap.OUTER_PAVEMENT.grow(0.01).has_point(Vector2(f.x, f.z)), "and stays on the map")
	cw.set_weather_override({})
	cw._process(0.05)
	cw.focus_camera = null
	cam.free()


## The covers: every stand spot dry (a roof, awning, slab or canopy above it), clear of solids, lamps and
## flowerpots, 0.9 m from every child's place and 0.5 m from every person's place on its region.
func test_covers() -> void:
	var furn: Array = []
	furn.append_array(CityMap.FURNITURE)
	furn.append_array(PropsCity.EXTRA_FURNITURE)
	var pots: Array[Vector2] = []
	for shop: String in CityMap.SHOP_DOORS:
		var door: Vector2 = CityMap.SHOP_DOORS[shop]
		var fz := (CityMap.BUILDINGS[shop]["rect"] as Rect2).end.y
		pots.append(Vector2(door.x - 0.32, fz + 0.17))
		pots.append(Vector2(door.y + 0.32, fz + 0.17))
	var n := 0
	var kinds := {}
	for cv: Dictionary in PropsCity.COVERS:
		var id := String(cv["id"])
		var rid := String(cv["region"])
		kinds[cv["kind"]] = true
		ok(["awning", "shelter", "canopy", "interior"].has(String(cv["kind"])), "%s: a known kind" % id)
		var y := 0.0 if rid == "ground" else float(CityMap.REGIONS[rid]["y"])
		for p: Vector2 in cv["stand"]:
			n += 1
			ok((cv["rect"] as Rect2).grow(0.05).has_point(p), "%s: %s inside its rect" % [id, p])
			if rid == "ground":
				for s2: Dictionary in CityMap.GROUND_SOLIDS:
					if s2.has("rect"):
						ok(not (s2["rect"] as Rect2).grow(0.3).has_point(p), "%s: %s clear of %s" % [id, p, s2["kind"]])
					else:
						ok((s2["at"] as Vector2).distance_to(p) >= float(s2["r"]) + 0.3, "%s: %s clear of %s" % [id, p, s2["kind"]])
				for w: Rect2 in CityMap.GROUND_WALLS:
					ok(not w.grow(0.3).has_point(p), "%s: %s clear of a wall" % [id, p])
				for l in PropsCity.STREET_LAMPS:
					ok(l.distance_to(p) >= 0.45, "%s: %s clear of a lamp" % [id, p])
				for pt in pots:
					ok(pt.distance_to(p) >= 0.45, "%s: %s clear of a flowerpot" % [id, p])
			for f: Dictionary in furn:
				if String(f["region"]) == rid:
					ok(not (f["rect"] as Rect2).grow(0.3).has_point(p), "%s: %s clear of the %s" % [id, p, f["kind"]])
			for iid: String in CityMap.INTERACTIONS:
				var it: Dictionary = CityMap.INTERACTIONS[iid]
				if String(it["region"]) == rid:
					ok((it["pos"] as Vector2).distance_to(p) >= 0.9, "%s: %s is %.2f m from the child's %s" % [id, p, (it["pos"] as Vector2).distance_to(p), iid])
			for np: Dictionary in PropsCity.NPC_PLACES:
				if String(np["region"]) == rid:
					ok((np["pos"] as Vector2).distance_to(p) >= 0.5, "%s: %s clear of the person's place %s" % [id, p, np["id"]])
			if id == "carousel":
				var c: Vector2 = CityMap.CAROUSEL["center"]
				ok(c.distance_to(p) <= PropsCity.CAROUSEL_CANOPY - 0.1, "%s: %s under the canopy's rim" % [id, p])
			else:
				ok(_hits(Vector3(p.x, y + 1.9, p.y), Vector3(p.x, y + 9.0, p.y)), "%s: %s has cover above it" % [id, p])
	ok(kinds.size() == 4, "awnings, shelters, canopies and interiors")
	_report.append("covers: %d places, %d stand spots" % [PropsCity.COVERS.size(), n])


## No distance-based visibility switch without a fade margin (nothing pops while zooming).
func test_visibility_ranges() -> void:
	cw.set_detail_range(CityWorld.DETAIL_RANGE)
	for n in cw.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
			ok(g.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and g.visibility_range_end_margin > 0.0, "%s fades at its range" % cw.get_path_to(g))
	cw.set_detail_range(0.0)
	for n in cw.find_children("*", "GeometryInstance3D", true, false):
		ok((n as GeometryInstance3D).visibility_range_end == 0.0, "%s: no range by default" % cw.get_path_to(n))
	# weather layers sit clear of the surfaces under them (no coplanar faces): puddles above 0.035, pools above 0.065
	ok(cw._puddles.mesh.get_aabb().position.y >= 0.035, "puddles 1 cm above the paving")
	ok(cw._pools.mesh.get_aabb().position.y >= 0.065, "light pools above the kerbs")


func test_night_budget() -> void:
	var glow := 0
	for n in cw.find_children("*Glow", "MeshInstance3D", true, false):
		glow += 1
	_report.append("night and rain: %d glow meshes, 1 light-pool mesh, 1 puddle mesh, 1 rain emitter, %d real lights" % [glow, cw._lights.size()])
	ok(_calls(_static_meshes()) <= MAX_STATIC_CALLS, "static calls with the night meshes within budget")
