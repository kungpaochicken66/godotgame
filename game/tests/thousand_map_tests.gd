## Headless tests for Thousand Town's map data (design/thousand-town.md, sections 1-3): the metre scale,
## doors on walkable ground facing a street or a plaza, nothing on the canal but its bridges, every GLB
## loading at run time through GLTFDocument (not as an editor-imported resource), and the arrival on the
## station forecourt looking east. The data's byte identity across two extractor runs is checked in Node
## (node scripts/thousand_town/extract.mjs --check). Nothing renders.
##   scripts/godot.sh --headless --path game -s res://tests/thousand_map_tests.gd
extends SceneTree

const ThousandMap := preload("res://scripts/core/thousand_map.gd")
const EPS := 0.001

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []
var D: Dictionary


func _initialize() -> void:
	D = ThousandMap.data()
	_current = "load"
	ok(not D.is_empty(), "town.json loads")
	if D.is_empty():
		print("\nTHOUSAND MAP TESTS: %d checks, %d failures" % [_checks, _failures])
		quit(1)
		return
	for t in ["test_source", "test_scale", "test_doors", "test_canal", "test_glbs", "test_arrival", "test_api"]:
		_current = t
		call(t)
	for line in _report:
		print(line)
	print("\nTHOUSAND MAP TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


func rect(d: Dictionary) -> Rect2:
	return ThousandMap.rect_of(d)


## Positive-area overlap (touching edges do not count).
func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - EPS and b.position.x < a.end.x - EPS \
		and a.position.y < b.end.y - EPS and b.position.y < a.end.y - EPS


func inside(r: Rect2, p: Vector2) -> bool:
	return p.x > r.position.x + EPS and p.x < r.end.x - EPS and p.y > r.position.y + EPS and p.y < r.end.y - EPS


# ------------------------------------------------------------------ source

func test_source() -> void:
	var s: Dictionary = D.source
	ok(s.commit == "1332ef29d6208a4192bf7400e0085033fd773a3c", "pinned upstream commit")
	ok(s.licence == "CC BY 4.0", "licence CC BY 4.0")
	ok(s.author == "\u4eea\u7ed8\u58eb / YiHuiShiBY", "author credited (the original name, as town.json carries it)")
	ok(String(s.repository).ends_with("YiHuiShiBY/thousand-town"), "repository link")
	ok(s.units == "metres (upstream ×0.5)" and D.units == s.units, "units recorded")
	ok(int(D.params.seed) == 20260818, "seed 20260818")


# ------------------------------------------------------------------ scale (design section 1)

func test_scale() -> void:
	var c: Dictionary = D.constants
	ok(ThousandMap.HALF == Vector2(95, 129), "HALF is +-95 x +-129 m")
	ok(near(D.board.half_x, 95) and near(D.board.half_z, 129), "board +-95 / +-129 m in town.json")
	ok(ThousandMap.BOARD == Rect2(-95, -129, 190, 258), "BOARD rect")
	ok(near(c.storey, 3.0) and near(ThousandMap.STOREY, 3.0), "storey 3.0 m")
	ok(near(c.plinth, 0.7), "plinth 0.7 m")
	ok(near(c.upstream_door_height, 1.8) and near(c.door_height, ThousandMap.DOOR_HEIGHT) and near(c.door_height, 2.1),
		"doors 2.1 m (upstream 1.8 m)")
	ok(near(c.canal_half_width, 7.5) and near(ThousandMap.CANAL_HALF, 7.5), "canal half-width 7.5 m")
	var canal := ThousandMap.canal()
	ok(near(canal.position.x, -7.5) and near(canal.end.x, 7.5), "canal is |x| < 7.5 m")
	ok(near(canal.position.y, -129) and near(canal.end.y, 129), "canal runs the whole board")

	var streets := 0
	var avenues := 0
	var rings := 0
	for r in D.roads:
		var rr := rect(r)
		if r.role == "cross_street":
			streets += 1
			ok(near(rr.size.y, 6.0), "%s: cross street 6 m wide (%.3f)" % [r.id, rr.size.y])
		elif r.role == "avenue":
			avenues += 1
			ok(near(rr.size.x, 5.0) and near(absf(float(r.x)), 48.0), "%s: avenue 5 m wide at x = +-48" % r.id)
		elif r.role == "ring_road":
			rings += 1
			ok(near(rr.size.x, 5.0) and near(absf(float(r.x)), 87.5), "%s: ring road 5 m wide at x = +-87.5" % r.id)
	ok(streets == 10 and avenues == 2 and rings == 2, "10 cross-street halves, 2 avenues, 2 ring roads")
	ok(near(ThousandMap.CROSS_STREET_WIDTH, 6.0) and near(ThousandMap.AVENUE_WIDTH, 5.0), "width constants")
	var walk := 0
	for r in ThousandMap.roads():
		if r.walk_only_to > 0.0:
			walk += 1
			ok(near(r.walk_only_to, 45.5) and near(r.rect.get_center().y, 0.0), "%s: z = 0 street walk-only to |x| 45.5" % r.id)
	ok(walk == 2, "both halves of the z = 0 street are pedestrian")

	var bs := ThousandMap.buildings()
	ok(bs.size() == 18, "18 buildings (%d)" % bs.size())
	var towers := []
	for b in bs:
		ok(near(b.storey, 3.0), "%s: storey 3.0" % b.id)
		ok(near(b.height, 0.7 + 3.0 * b.floors), "%s: height = plinth + floors x storey" % b.id)
		if b.kind == "tower":
			towers.append(b)
	ok(towers.size() == 4, "4 office towers")
	var tallest = null
	for t in towers:
		ok(t.floors >= 18 and t.floors <= 22, "%s: tower 18-22 floors (%d)" % [t.id, t.floors])
		if tallest == null or t.floors > tallest.floors:
			tallest = t
	ok(D.landmarks.helipad.building == tallest.id, "the helipad stands on the tallest tower")
	var floors := towers.map(func(t): return t.floors)
	floors.sort()
	ok(floors == [19, 19, 20, 21], "default seed tower floors 21/19/19/20 (%s)" % str(floors))
	var housing := 0
	var facility := 0
	for b in bs:
		housing += 1 if b.kind == "housing" else 0
		facility += 1 if b.kind == "facility" else 0
	ok(housing == 4 and facility == 10, "4 housing blocks, 10 facilities")

	var st := ThousandMap.station()
	ok(st.pos == Vector2(-66, 20) and ThousandMap.STATION == st.pos, "station centre (-66, 20)")
	ok(near(st.rect.size.x, 26) and near(st.rect.size.y, 29), "station 26 x 29 m")
	ok(D.lots[12].kind == "station" and D.lots[12].cell == "A4", "the station is lot 12, cell A4")
	for b in ThousandMap.bridges():
		if b.kind == "road_bridge":
			ok(near(b.rect.size.x, 23) and near(b.rect.size.y, 7.5) and near(absf(b.rect.get_center().y), 40), "%s: road bridge 23 x 7.5 m at z = +-40" % b.id)
		else:
			ok(near(b.rect.size.x, 22) and near(b.rect.size.y, 2.5) and near(absf(b.rect.get_center().y), 20), "%s: footbridge 22 x 2.5 m at z = +-20" % b.id)
	var fw: Dictionary = D.landmarks.ferris_wheel
	ok(near(fw.radius, 10) and near(fw.axle_y, 13), "ferris wheel radius 10 m, axle 13 m")
	ok(D.trees.size() > 90, "trees present (%d)" % D.trees.size())
	ok(ThousandMap.stops().size() == 6, "6 bus stops")
	ok(D.waterfront.stalls.size() == 32, "32 night-market stalls")
	_report.append("scale: %d buildings, %d towers %s, %d trees, %d frontage parts" % [bs.size(), towers.size(), str(floors),
		D.trees.size(), int(D.counts.frontage_parts)])


# ------------------------------------------------------------------ doors

func _solids() -> Array:
	var out := []
	for b in ThousandMap.buildings():
		out.append({"id": b.id, "rect": b.rect})
		if b.has("volumes"):
			for v in b.volumes:
				out.append({"id": b.id, "rect": v.rect})
	for a in ThousandMap.annexes():
		out.append({"id": a.id, "rect": a.rect})
	for s in D.waterfront.stalls:
		out.append({"id": s.id, "rect": rect(s)})
	out.append({"id": "street-office", "rect": rect(D.waterfront.street_office)})
	for site in D.frontage.sites:
		for r in site.reservations:
			out.append({"id": site.id, "rect": rect(r)})
	return out


## Walkable ground: on the board, not water, not inside a solid, not on a carriageway (a zebra or the
## walk-only stretch of the z = 0 street is fine).
func _walkable(p: Vector2, solids: Array, ignore: String = "") -> String:
	if not inside(ThousandMap.BOARD, p):
		return "off the board"
	if inside(ThousandMap.canal(), p):
		return "in the canal"
	for s in solids:
		if s.id != ignore and inside(s.rect, p):
			return "inside " + s.id
	for r in ThousandMap.roads():
		if inside(r.rect, p) and not (r.walk_only_to > 0.0 and absf(p.x) <= r.walk_only_to):
			var on_zebra := false
			for z in ThousandMap.zebras():
				on_zebra = on_zebra or inside(z, p)
			if not on_zebra:
				return "on the carriageway of " + r.id
	return ""


## March from the door along its facing: it must reach a street or a public place within 15 m, and pass
## no solid on the way.
func _faces_street(p: Vector2, f: Vector2, solids: Array, ignore: String) -> String:
	var places := ThousandMap.places()
	var t := 0.0
	while t <= 15.0:
		var q := p + f * t
		for r in ThousandMap.roads():
			if inside(r.rect, q):
				return ""
		for pl in places:
			if inside(pl.rect, q):
				return ""
		for s in solids:
			if s.id != ignore and inside(s.rect, q):
				return "blocked by %s at %.1f m" % [s.id, t]
		t += 0.25
	return "no street or plaza within 15 m"


func test_doors() -> void:
	var solids := _solids()
	var count := 0
	for b in ThousandMap.buildings():
		ok(b.doors.size() >= 1, "%s has a door" % b.id)
		for d in b.doors:
			count += 1
			var p: Vector2 = d.pos
			ok(near(d.facing.length(), 1.0) and (is_zero_approx(d.facing.x) or is_zero_approx(d.facing.y)),
				"%s: door faces along an axis" % b.id)
			ok(not inside(b.rect, p) and not inside(b.record, p), "%s: door outside its footprint" % b.id)
			var why := _walkable(p, solids)
			ok(why == "", "%s: door %s on walkable ground (%s)" % [b.id, str(p), why])
			ok((p - b.center).dot(d.facing) > 0.0, "%s: door faces away from the building" % b.id)
			var face := _faces_street(p, d.facing, solids, b.id)
			ok(face == "", "%s: door faces a street or plaza (%s)" % [b.id, face])
			ok(String(d.source) != "", "%s: door records its source" % b.id)
		for d in b.facade_doors:
			ok(not inside(b.rect, d.pos) or b.kind == "housing", "%s: facade door outside the solid mass" % b.id)
	for a in ThousandMap.annexes():
		ok(a.doors.size() >= 1, "%s has a door" % a.id)
		for d in a.doors:
			ok(not inside(a.rect, d.pos), "%s: annex door outside its body" % a.id)
	var main := ThousandMap.door("b-14-0")
	ok(not main.is_empty() and main.facing == Vector2(0, -1), "door(): the mall's entrance faces north to the z = 0 street")
	ok(ThousandMap.door("nope").is_empty(), "door() of an unknown id is empty")
	_report.append("doors: %d street doors on 18 buildings, all walkable and facing a street or plaza" % count)


# ------------------------------------------------------------------ canal

func test_canal() -> void:
	var canal := ThousandMap.canal()
	var bad := []
	var check := func(what: String, r: Rect2) -> void:
		if overlaps(r, canal):
			bad.append(what)
	for b in ThousandMap.buildings():
		check.call(b.id, b.record)
		check.call(b.id, b.rect)
	for a in ThousandMap.annexes():
		check.call(a.id, a.footprint)
	for s in D.waterfront.stalls:
		check.call(s.id, rect(s))
	check.call("street office", rect(D.waterfront.street_office))
	for s in ThousandMap.stops():
		check.call(s.id, s.rect)
	check.call("taxi rank", ThousandMap.taxi_rank().rect)
	for p in ThousandMap.places():
		check.call(p.id, p.rect)
	for r in ThousandMap.roads():
		check.call(r.id, r.rect)
	for z in ThousandMap.zebras():
		check.call("zebra", z)
	for s in D.landmarks.balloon_stands:
		check.call(s.id, rect(s))
	for t in D.trees:
		if absf(float(t.x)) - float(t.r) < 7.5:
			bad.append("tree at %s" % str(Vector2(t.x, t.z)))
	var parts := 0
	for site in D.frontage.sites:
		for p in site.parts:
			parts += 1
			check.call(site.id + " " + String(p.role), rect(p))
	for group in D.facility_parts + D.office_parts:
		for p in group.parts:
			parts += 1
			check.call(String(group.building) + " " + String(p.feature), rect(p))
	ok(bad.is_empty(), "nothing but bridges over the canal (%s)" % str(bad.slice(0, 6)))
	ok(parts == int(D.counts.frontage_parts) + int(D.counts.facility_parts) + int(D.counts.office_parts), "all parts checked")
	for b in ThousandMap.bridges():
		ok(b.rect.position.x < canal.position.x and b.rect.end.x > canal.end.x, "%s spans the canal" % b.id)
	for v in D.viaducts:
		ok(float(v.flat_x) > 7.5, "%s spans the canal at full height" % v.id)
	for t in D.tunnels:
		ok(float(t.cover_x) > 7.5, "%s passes under the canal" % t.id)
	_report.append("canal: %d parts and every footprint clear of |x| < 7.5 except 4 bridges, 2 viaducts, 2 tunnels" % parts)


# ------------------------------------------------------------------ GLBs

func _triangles(state: GLTFState) -> Dictionary:
	var tris := 0
	var max_abs := Vector3.ZERO
	for gm in state.get_meshes():
		var im: ImporterMesh = gm.mesh
		for i in im.get_surface_count():
			var arrays := im.get_surface_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else verts.size()) / 3
			for v in verts:
				max_abs = Vector3(maxf(max_abs.x, absf(v.x)), maxf(max_abs.y, absf(v.y)), maxf(max_abs.z, absf(v.z)))
	return {"triangles": tris, "max_abs": max_abs}


func test_glbs() -> void:
	var meshes: Dictionary = D.meshes
	ok(meshes.size() == 6, "six GLBs listed")
	var lines := []
	for key in meshes.keys():
		var path := ThousandMap.glb_path(key)
		ok(FileAccess.file_exists(path), "%s exists" % path)
		var imp := path + ".import"
		var imp_text := FileAccess.get_file_as_string(imp) if FileAccess.file_exists(imp) else ""
		ok(imp_text.contains('importer="keep"'), "%s is kept as a plain file (importer=\"keep\")" % path)
		# A kept file has no imported resource to remap to (no path= line), so nothing needs an editor
		# import and an export ships the .glb itself. (ResourceLoader.exists() is true for any file with a
		# .import beside it, but load() would fail: GLTFDocument is the way in.)
		ok(not imp_text.contains("path=") and not imp_text.contains("dest_files"), "%s has no imported resource" % path)
		var state := ThousandMap.glb_state(key)
		ok(state != null, "%s loads through GLTFDocument at run time" % path)
		if state == null:
			continue
		var t := _triangles(state)
		ok(int(t.triangles) == int(meshes[key].triangles), "%s: %d triangles (town.json %d)" % [key, t.triangles, int(meshes[key].triangles)])
		var scene := ThousandMap.glb_scene(key)
		ok(scene != null and scene.get_child_count() > 0, "%s generates a scene" % key)
		if scene:
			scene.free()
		lines.append("%s %d" % [key, t.triangles])
		if key == "district":
			# Metres: the widest floor module is 36.74 upstream units = 18.37 m across.
			ok(near(t.max_abs.x, 9.2750, 0.01) and near(t.max_abs.y, 3.0, 0.01), "district modules in metres (%s)" % str(t.max_abs))
		if key == "housing":
			var names := []
			for n in state.get_nodes():
				names.append(n.resource_name)
			ok(names.has("Housing_Entry") and names.has("Housing_Window"), "housing modules named")
		if key == "landscape":
			ok(near(t.max_abs.y, 12.425, 0.01), "the monument is 12.4 m tall in metres (%s)" % str(t.max_abs))
	_report.append("glb triangles: " + ", ".join(lines))


# ------------------------------------------------------------------ arrival

func test_arrival() -> void:
	var st := ThousandMap.station()
	var a: Dictionary = st.arrival
	ok(a.pos.is_equal_approx(ThousandMap.ARRIVAL_POS), "ARRIVAL_POS matches town.json")
	ok(a.facing == ThousandMap.ARRIVAL_FACING and ThousandMap.ARRIVAL_FACING == Vector2(1, 0), "arrival faces +x")
	var p := Vector2(ThousandMap.ARRIVAL_POS.x, ThousandMap.ARRIVAL_POS.z)
	ok(inside(st.forecourt, p), "ARRIVAL is on the station forecourt %s" % str(st.forecourt))
	var forward := -ThousandMap.ARRIVAL.basis.z
	ok(forward.is_equal_approx(Vector3(1, 0, 0)), "ARRIVAL looks toward +x (%s)" % str(forward))
	ok(ThousandMap.ARRIVAL.basis.y.is_equal_approx(Vector3.UP), "ARRIVAL is upright")
	ok(ThousandMap.ARRIVAL.origin == ThousandMap.ARRIVAL_POS and ThousandMap.arrival() == ThousandMap.ARRIVAL, "arrival()")
	ok(near(ThousandMap.ARRIVAL_POS.y, float(D.constants.pavement_y)), "ARRIVAL stands on the pavement datum")
	var solids := _solids()
	ok(_walkable(p, solids) == "", "ARRIVAL is walkable (%s)" % _walkable(p, solids))
	# The view east: the z = 0 street runs open to the canal, with no building or compound in the way.
	var blocked := ""
	var x := p.x
	while x < -7.5 and blocked == "":
		for s in solids:
			if inside(s.rect, Vector2(x, p.y)):
				blocked = "%s at x = %.1f" % [s.id, x]
		x += 0.25
	ok(blocked == "", "an open line east from the arrival to the canal (%s)" % blocked)
	var pedestrian := false
	for r in ThousandMap.roads():
		if r.walk_only_to > 0.0 and r.rect.get_center().x < 0.0:
			pedestrian = r.rect.position.y <= 0.0 and r.rect.end.y >= 0.0 and p.y - r.rect.end.y < 1.0
	ok(pedestrian, "the arrival stands at the north kerb of the z = 0 street, just west of its pedestrian stretch")


# ------------------------------------------------------------------ API

func test_api() -> void:
	var b := ThousandMap.building("b-3-0")
	ok(b.kind == "tower" and b.floors == 21 and b.roof == "plain", "building(): the helipad tower")
	ok(ThousandMap.building("nope").is_empty(), "building() of an unknown id is empty")
	var loops := ThousandMap.loops()
	ok(loops.station.size() == 7, "7 station vehicles (3 buses, 4 taxis)")
	ok(loops.traffic.size() == 4, "4 street-traffic loops")
	for l in loops.station + loops.traffic:
		ok(l.points.size() > 4, "%s: a polyline" % l.id)
		for q in l.points:
			if absf(q.x) < 7.5 and not (absf(absf(q.y) - 40.0) < 4.0 or absf(q.y) > 120.0 or absf(absf(q.y) - 80.0) < 4.0):
				ok(false, "%s crosses the canal off a bridge at %s" % [l.id, str(q)])
				break
	var tr := ThousandMap.taxi_rank()
	ok(tr.pos.is_equal_approx(Vector2(-52.5, 20)), "taxi rank at (-52.5, 20)")
	var data_again := ThousandMap.data()
	ok(is_same(data_again, D), "town.json is loaded once and cached")
