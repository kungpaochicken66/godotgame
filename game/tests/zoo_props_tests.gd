## Headless tests for the zoo's props and scenery (`art/props_zoo.gd`, docs/zoo-engineering-standard.md
## section 6): the catalog kinds' bounds, every scenery builder, the rock top, the style rules and the
## triangle budgets (design/zoo-and-world-journeys.md 14.1). Nothing here renders.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_props_tests.gd
extends SceneTree

const PropsZoo := preload("res://scripts/art/props_zoo.gd")

const BOUNDS := {
	"tram_stop": Vector3(3.2, 2.4, 2.0), "zoo_ball": Vector3(0.5, 0.5, 0.5), "zoo_box": Vector3(0.9, 0.8, 0.9),
	"scratching_log": Vector3(1.8, 0.8, 0.8), "leaf_feeder": Vector3(0.9, 2.4, 0.9),
	"hay_bale": Vector3(1.1, 0.8, 0.8), "play_mirror": Vector3(1.0, 1.3, 0.4),
}
const TOL := 0.12
const TOY_BUDGET := 1500
const STATION_BUDGET := 3000
const TRAM_STOP_BUDGET := 4000

var _checks := 0
var _failures := 0
var _current := ""
var _report: Array[String] = []


func _initialize() -> void:
	for t in ["test_kinds_bounds", "test_scenery_builds", "test_rock_top", "test_style", "test_budgets", "test_sign_and_tyre"]:
		_current = t
		call(t)
	for line in _report:
		print(line)
	print("\nZOO PROPS TESTS: %d checks, %d failures" % [_checks, _failures])
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


func _xf_of(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var b: AABB = _xf_of(mi, root) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _tris(root: Node3D) -> int:
	var total := 0
	for mi in _meshes(root):
		if mi.mesh is QuadMesh:
			continue
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			total += idx.size() / 3 if not idx.is_empty() else verts.size() / 3
	return total


## Every scenery builder with a name, a factory and a budget.
func _scenery() -> Array:
	var P := PropsZoo
	return [
		["tram_car", P.tram_car(), STATION_BUDGET], ["station", P.station(Vector2(8, 4)), STATION_BUDGET],
		["rock", P.rock(Vector3(7, 0.7, 4.5), 3), 4000], ["crag", P.crag(Vector3(6, 3, 3), 2), 4000],
		["acacia", P.acacia(), STATION_BUDGET], ["bamboo", P.bamboo(Vector2(8, 5)), STATION_BUDGET],
		["hedge", P.hedge(6.0), STATION_BUDGET], ["shade_tree", P.shade_tree(), STATION_BUDGET],
		["water", P.water(Vector2(7, 5), 0.6), STATION_BUDGET], ["falls", P.falls(5.0, 2.6), STATION_BUDGET],
		["log_bridge", P.log_bridge(5.0), STATION_BUDGET], ["scratch_tree", P.scratch_tree(), STATION_BUDGET],
		["ring_run", P.ring_run(7.0, 2.9, 7), STATION_BUDGET], ["tower", P.tower(1.2), STATION_BUDGET],
		["tower2", P.tower(2.0), STATION_BUDGET], ["beam", P.beam(3.0), STATION_BUDGET],
		["vine_arch", P.vine_arch(3.0), STATION_BUDGET], ["spire", P.spire([0.8, 1.4, 2.0, 3.2]), STATION_BUDGET],
		["hammock", P.hammock(), STATION_BUDGET], ["tyre_frame", P.tyre_frame(), STATION_BUDGET],
		["tyre", P.tyre(), STATION_BUDGET], ["bell_rope", P.bell_rope(), STATION_BUDGET],
		["bongo_logs", P.bongo_logs(), STATION_BUDGET], ["water_pump", P.water_pump(), STATION_BUDGET],
		["shower_arch", P.shower_arch(), STATION_BUDGET], ["treat_table", P.treat_table(), STATION_BUDGET],
		["ball_basket", P.ball_basket(), STATION_BUDGET], ["sign_post", P.sign_post("Lion Hill"), STATION_BUDGET],
		["map_board", P.map_board(), STATION_BUDGET], ["lamp", P.lamp(), STATION_BUDGET],
	]


# ------------------------------------------------------------------- tests

func test_kinds_bounds() -> void:
	ok(PropsZoo.KINDS.size() == 7, "seven catalog kinds")
	ok(PropsZoo.KINDS == BOUNDS.keys(), "KINDS match the standard's table, in order")
	for kind in PropsZoo.KINDS:
		var n: Node3D = PropsZoo.build(kind, 2)
		ok(n != null and n.name == kind, "%s builds" % kind)
		var box := _aabb(n)
		var want: Vector3 = BOUNDS[kind]
		for ax in 3:
			ok(absf(box.size[ax] - want[ax]) <= TOL, "%s size axis %d is %.2f (want %.2f)" % [kind, ax, box.size[ax], want[ax]])
		ok(box.position.y >= -0.15 and box.position.y <= 0.1, "%s bottom at y %.3f" % [kind, box.position.y])
		ok(absf(box.get_center().x) <= 0.15 and absf(box.get_center().z) <= 0.15, "%s is centred on the origin (%s)" % [kind, str(box.get_center())])
		for c in [-1, 0, 7]:
			ok(PropsZoo.build(kind, c) != null, "%s builds with colour %d" % [kind, c])
		n.free()
	ok(PropsZoo.build("nonsense", 0) != null, "an unknown kind still returns a node")


func test_scenery_builds() -> void:
	for e in _scenery():
		var n: Node3D = e[1]
		ok(n != null and not _meshes(n).is_empty() or e[0] == "none", "%s builds with meshes" % e[0])
		var box := _aabb(n)
		ok(box.size.length() > 0.3, "%s has a size (%s)" % [e[0], str(box.size)])
		if e[0] != "tyre":
			ok(box.position.y >= -0.15 and box.position.y <= 0.1, "%s starts at the ground, y %.2f" % [e[0], box.position.y])
		n.free()


func test_rock_top() -> void:
	for sz in [Vector3(7, 0.7, 4.5), Vector3(3, 1.0, 3), Vector3(4.5, 0.4, 4), Vector3(2, 2.6, 2)]:
		for seed in [0, 1, 7, 99]:
			var n: Node3D = PropsZoo.rock(sz, seed)
			var box := _aabb(n)
			ok(absf(box.end.y - sz.y) <= 0.05, "rock %s seed %d top %.3f" % [str(sz), seed, box.end.y])
			ok(box.size.x <= sz.x + 0.05 and box.size.z <= sz.z + 0.05, "rock %s seed %d stays within its footprint %s" % [str(sz), seed, str(box.size)])
			n.free()
	var a: Node3D = PropsZoo.rock(Vector3(5, 1, 4), 1)
	var b: Node3D = PropsZoo.rock(Vector3(5, 1, 4), 2)
	var va: PackedVector3Array = ((a.get_child(0) as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var vb: PackedVector3Array = ((b.get_child(0) as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ok(va != vb, "the seed varies the rock")
	a.free()
	b.free()


func test_style() -> void:
	var all: Array = []
	for kind in PropsZoo.KINDS:
		all.append([kind, PropsZoo.build(kind, 3)])
	for e in _scenery():
		all.append([e[0], e[1]])
	var water_seen := false
	for e in all:
		for mi in _meshes(e[1]):
			var shadow: bool = mi.mesh is QuadMesh
			var m := mi.material_override as StandardMaterial3D
			ok(m != null, "%s/%s has a standard material" % [e[0], mi.name])
			if m == null:
				continue
			if shadow:
				ok(m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s: the blob shadow is the only quad" % e[0])
				continue
			ok(m.albedo_texture == null and m.normal_texture == null and m.roughness_texture == null and m.emission_texture == null, "%s/%s has no texture" % [e[0], mi.name])
			ok(m.metallic == 0.0, "%s/%s is not metallic" % [e[0], mi.name])
			ok(m.roughness >= 0.85, "%s/%s roughness %.2f" % [e[0], mi.name, m.roughness])
			ok(not m.emission_enabled, "%s/%s does not glow" % [e[0], mi.name])
			if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				ok(mi.name == "Water", "%s/%s is transparent but is not water" % [e[0], mi.name])
				water_seen = true
			var sm: Mesh = mi.mesh
			for s in sm.get_surface_count():
				ok(sm.surface_get_material(s) == null or not (sm.surface_get_material(s) as StandardMaterial3D).albedo_texture, "%s mesh surface has no texture" % e[0])
		ok(_count_lights(e[1]) == 0, "%s has no lights" % e[0])
		e[1].free()
	ok(water_seen, "the pond's surface is the one translucent part")


func _count_lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _count_lights(ch)
	return c


func test_budgets() -> void:
	for kind in PropsZoo.KINDS:
		var n: Node3D = PropsZoo.build(kind, 3)
		var t := _tris(n)
		var budget: int = TRAM_STOP_BUDGET if kind == "tram_stop" else TOY_BUDGET
		ok(t <= budget, "%s has %d triangles (budget %d)" % [kind, t, budget])
		var draws := 0
		for mi in _meshes(n):
			if not (mi.mesh is QuadMesh):
				draws += 1
		ok(draws <= (2 if kind == "tram_stop" else 3), "%s has %d draw calls" % [kind, draws])
		_report.append("tris %-16s %5d  (draw calls %d)" % [kind, t, draws])
		n.free()
	for e in _scenery():
		var t := _tris(e[1])
		ok(t <= int(e[2]), "%s has %d triangles (budget %d)" % [e[0], t, e[2]])
		_report.append("tris %-16s %5d" % [e[0], t])
		e[1].free()


func test_sign_and_tyre() -> void:
	var s: Node3D = PropsZoo.sign_post("Tiger Hill")
	var label: Label3D = s.get_node_or_null("Label") as Label3D
	ok(label != null and label.text.length() > 0, "the sign has a Label3D with text")
	ok(label != null and absf(label.pixel_size - 0.004) < 0.0001, "the sign uses the town's pixel size")
	s.free()
	var f: Node3D = PropsZoo.tyre_frame()
	var t: Node3D = PropsZoo.tyre()
	ok(f != t and t.get_parent() == null and f.get_parent() == null, "the tyre and its frame are separate nodes")
	ok(_aabb(t).end.y <= 0.1 and _aabb(t).position.y < -1.5, "the tyre hangs below its pivot")
	ok(absf(_aabb(f).end.y - 2.6) <= 0.1 and PropsZoo.TYRE_PIVOT.y < 2.6, "the frame is 2.6 m and the pivot is under the bar")
	f.free()
	t.free()
