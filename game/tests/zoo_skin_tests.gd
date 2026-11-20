## Tests for the skinned imported zoo animals: zoo_skin.gd, zoo_skin_rigs.gd, zoo_pose_extra.gd
## (docs/zoo-engineering-standard.md 11.1).
##   scripts/godot.sh --headless --path game -s res://tests/zoo_skin_tests.gd
## Prints "ZOO SKIN TESTS: N checks, M failures" and exits 1 on any failure.
extends SceneTree

const Skin3 := preload("res://scripts/art/zoo_skin.gd")
const Rigs := preload("res://scripts/art/zoo_skin_rigs.gd")
const Extra := preload("res://scripts/art/zoo_pose_extra.gd")

const SPECIES := ["panda", "lion", "elephant", "giraffe", "zebra", "penguin"]
const HEIGHTS := {"panda": 1.10, "lion": 1.55, "elephant": 2.40, "giraffe": 2.80, "zebra": 1.65, "penguin": 1.00}
const COUNTS := {"panda": [659, 1198], "lion": [713, 1264], "elephant": [574, 1076], "giraffe": [701, 1182], "zebra": [1246, 1576], "penguin": [507, 776]}
const FOUR := ["leg_fl", "leg_fr", "leg_bl", "leg_br"]
const LEGS_ALL := ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low"]

# The pivots the standard (11.1) lists per species.
const REQUIRED := {
	"panda": ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low", "neck", "head", "jaw", "ear_l", "ear_r", "tail0", "prop"],
	"lion": ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low", "neck", "head", "jaw", "tail0", "tail1", "tail2", "tail3", "prop"],
	"giraffe": ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low", "neck", "neck1", "head", "ear_l", "ear_r", "jaw", "tail0", "tail1", "tail2", "prop"],
	"zebra": ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low", "neck", "head", "jaw", "tail0", "tail1", "tail2", "prop"],
	"elephant": ["leg_fl", "leg_fl_low", "leg_fr", "leg_fr_low", "leg_bl", "leg_bl_low", "leg_br", "leg_br_low", "neck", "head", "ear_l", "ear_r", "trunk0", "trunk1", "trunk2", "tail0", "tail1", "prop"],
	"penguin": ["leg_l", "leg_r", "flipper_l", "flipper_r", "head", "tail0", "prop"],
}

const ACTIONS := {
	"panda": ["idle", "walk", "look", "nod", "blink", "eat", "nap", "munch", "sit_up", "roll", "play_ball", "graze"],
	"elephant": ["idle", "walk", "look", "nod", "blink", "eat", "nap", "drink", "spray", "dust", "ear_flap", "trumpet", "graze"],
	"penguin": ["idle", "walk", "look", "nod", "blink", "eat", "nap", "waddle", "swim", "dive", "surface", "slide", "flap", "preen", "hop"],
}

var checks := 0
var fails := 0


func _initialize() -> void:
	for sp in SPECIES:
		_species_tests(sp)
	_procedural_names_test()
	_pose_tests()
	_misc_tests()
	print("ZOO SKIN TESTS: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


# ---------------------------------------------------------------------------------- helpers

class Rig:
	var animal: Node3D
	var body: Node3D
	var r: Dictionary
	var sk: Skeleton3D
	var mi: MeshInstance3D
	var pivots: Dictionary
	var verts: PackedVector3Array
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var names: Array = []


func _make(sp: String) -> Rig:
	var rg := Rig.new()
	rg.animal = Node3D.new()
	rg.body = Node3D.new()
	rg.body.name = "body"
	rg.animal.add_child(rg.body)
	rg.r = Skin3.build(rg.animal, rg.body, sp)
	if rg.r.is_empty():
		return rg
	rg.sk = rg.r["skeleton"]
	rg.mi = rg.r["mesh"]
	rg.pivots = rg.r["pivots"]
	var arrays: Array = rg.mi.mesh.surface_get_arrays(0)
	rg.verts = arrays[Mesh.ARRAY_VERTEX]
	rg.bones = arrays[Mesh.ARRAY_BONES]
	rg.weights = arrays[Mesh.ARRAY_WEIGHTS]
	for i in rg.sk.get_bone_count():
		rg.names.append(rg.sk.get_bone_name(i))
	return rg


## CPU linear blend skinning with the skeleton's current pose.
func _skinned(rg: Rig) -> PackedVector3Array:
	# Global poses from the local poses ourselves: the engine refreshes its own cache on a deferred
	# call that never runs inside a test script. Parents come before children in the skeleton.
	var skin: Skin = rg.mi.skin
	var globals: Array = []
	var mats: Array = []
	for i in rg.sk.get_bone_count():
		var par := rg.sk.get_bone_parent(i)
		var g: Transform3D = rg.sk.get_bone_pose(i) if par < 0 else (globals[par] as Transform3D) * rg.sk.get_bone_pose(i)
		globals.append(g)
		mats.append(g * skin.get_bind_pose(i))
	var out := PackedVector3Array()
	out.resize(rg.verts.size())
	for vi in rg.verts.size():
		var p := Vector3.ZERO
		for j in 4:
			var w := rg.weights[vi * 4 + j]
			if w > 0.0:
				p += w * ((mats[rg.bones[vi * 4 + j]] as Transform3D) * rg.verts[vi])
		out[vi] = p
	return out


## Weight of vertex vi on the named bones.
func _wsum(rg: Rig, vi: int, bone_names: Array) -> float:
	var s := 0.0
	for j in 4:
		if bone_names.has(rg.names[rg.bones[vi * 4 + j]]):
			s += rg.weights[vi * 4 + j]
	return s


func _free(rg: Rig) -> void:
	rg.animal.free()


func _load_glb(sp: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../art/everything-zoo-r1/godot-pack/models/everything_%s.glb" % sp).simplify_path()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return {}
	var root := doc.generate_scene(state)
	var mi: MeshInstance3D = _find_mesh(root)
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	root.free()
	return {"arrays": arrays}


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f := _find_mesh(c)
		if f != null:
			return f
	return null


func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c


func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		var da := float(a[i]) - ma
		var db := float(b[i]) - mb
		sab += da * db
		saa += da * da
		sbb += db * db
	if saa < 1e-12 or sbb < 1e-12:
		return 0.0
	return sab / sqrt(saa * sbb)


# ---------------------------------------------------------------------------------- per species

func _species_tests(sp: String) -> void:
	_ok(Skin3.has_model(sp), "%s: has_model" % sp)
	var rg := _make(sp)
	_ok(not rg.r.is_empty(), "%s: build succeeds" % sp)
	if rg.r.is_empty():
		_free(rg)
		return
	# Return shape and pivots.
	for k in ["pivots", "rest", "size", "skeleton", "mesh"]:
		_ok(rg.r.has(k), "%s: result has %s" % [sp, k])
	for n in REQUIRED[sp]:
		_ok(rg.pivots.has(n), "%s: pivot %s exists" % [sp, n])
		_ok(rg.r["rest"].has(n), "%s: rest of %s" % [sp, n])
	_ok(rg.pivots["prop"] is Node3D and (rg.pivots["prop"] as Node3D).get_parent() == rg.animal, "%s: prop is a Node3D under the animal" % sp)
	_ok(rg.sk.find_bone("prop") < 0, "%s: prop is not a bone" % sp)
	for n in REQUIRED[sp]:
		if n != "prop":
			_ok(rg.sk.find_bone(n) >= 0, "%s: bone %s" % [sp, n])
			var node: Node3D = rg.pivots[n]
			var idx := rg.sk.find_bone(n)
			_ok(node.position.is_equal_approx(rg.sk.get_bone_rest(idx).origin), "%s: %s bone rest origin = pivot position" % [sp, n])
			_ok(Quaternion(node.quaternion).is_equal_approx(rg.sk.get_bone_rest(idx).basis.get_rotation_quaternion()), "%s: %s bone rest rotation = pivot rotation" % [sp, n])
			_ok((rg.r["rest"][n] as Vector3).is_equal_approx(node.rotation), "%s: rest value of %s = pivot rotation" % [sp, n])
	# Hierarchy conventions: lower leg is a child of its leg, head of neck, etc.
	for k in FOUR:
		if rg.pivots.has(k):
			_ok((rg.pivots[k + "_low"] as Node3D).get_parent() == rg.pivots[k], "%s: %s_low is a child of %s" % [sp, k, k])
			_ok((rg.pivots[k + "_low"] as Node3D).position.x == 0.0 and (rg.pivots[k + "_low"] as Node3D).position.y < -0.2, "%s: %s_low hangs below the hip along -Y" % [sp, k])
	if rg.pivots.has("neck"):
		_ok((rg.pivots["head"] as Node3D).get_parent() == (rg.pivots["neck1"] if rg.pivots.has("neck1") else rg.pivots["neck"]), "%s: head hangs under the neck chain" % sp)
	# One mesh, material.
	_ok(_count_meshes(rg.animal) == 1, "%s: exactly one MeshInstance3D" % sp)
	_ok(rg.mi.get_parent() == rg.sk and rg.sk.get_parent() == rg.body, "%s: mesh under skeleton under body" % sp)
	var mat := rg.mi.mesh.surface_get_material(0) as StandardMaterial3D
	_ok(mat != null, "%s: standard material" % sp)
	if mat != null:
		_ok(mat.vertex_color_use_as_albedo, "%s: vertex colour as albedo" % sp)
		_ok(not mat.vertex_color_is_srgb, "%s: vertex colours linear" % sp)
		_ok(mat.diffuse_mode == BaseMaterial3D.DIFFUSE_LAMBERT_WRAP, "%s: lambert wrap" % sp)
		_ok(is_equal_approx(mat.roughness, 1.0) and is_equal_approx(mat.metallic, 0.0), "%s: roughness 1, metallic 0" % sp)
		_ok(mat.cull_mode == BaseMaterial3D.CULL_BACK, "%s: cull back" % sp)
		_ok(mat.albedo_texture == null, "%s: no texture" % sp)
	# Mesh equals the GLB.
	var glb := _load_glb(sp)
	_ok(not glb.is_empty(), "%s: GLB readable" % sp)
	var n_v := rg.verts.size()
	var n_i := (rg.mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	_ok(n_v == COUNTS[sp][0], "%s: %d vertices (%d)" % [sp, n_v, COUNTS[sp][0]])
	_ok(n_i == COUNTS[sp][1] * 3, "%s: %d triangles" % [sp, n_i / 3])
	if not glb.is_empty():
		var ga: Array = glb["arrays"]
		var gv: PackedVector3Array = ga[Mesh.ARRAY_VERTEX]
		var gc: PackedColorArray = ga[Mesh.ARRAY_COLOR]
		var gn: PackedVector3Array = ga[Mesh.ARRAY_NORMAL]
		var arrays: Array = rg.mi.mesh.surface_get_arrays(0)
		var cc: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_ok(gv.size() == n_v, "%s: vertex count equals the GLB's" % sp)
		_ok(gc.size() == cc.size(), "%s: colour count equals the GLB's" % sp)
		_ok((ga[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == n_i, "%s: index count equals the GLB's" % sp)
		# The importer reorders vertices (vertex cache optimisation) and the mesh stores normals
		# and colours compressed, so match each built vertex to an unused GLB vertex at the same
		# position within those tolerances.
		var pool := {}
		for i in gv.size():
			var key := Vector3i((gv[i] * 5000.0).round())
			if not pool.has(key):
				pool[key] = []
			(pool[key] as Array).append([gn[i], gc[i], false])
		var unmatched := 0
		for i in n_v:
			var key := Vector3i((rg.verts[i] * 5000.0).round())
			var found := false
			for e in pool.get(key, []):
				var ea: Array = e
				var en: Vector3 = ea[0]
				var ec: Color = ea[1]
				if not ea[2] and en.distance_to(nn[i]) < 0.03 and absf(ec.r - cc[i].r) + absf(ec.g - cc[i].g) + absf(ec.b - cc[i].b) < 0.02:
					ea[2] = true
					found = true
					break
			if not found:
				unmatched += 1
		_ok(unmatched == 0, "%s: positions, normals and colours are the GLB's (%d unmatched)" % [sp, unmatched])
	_ok(absf((rg.r["size"] as Vector3).y - HEIGHTS[sp]) < 0.01, "%s: size.y is the height %.2f" % [sp, (rg.r["size"] as Vector3).y])
	var aabb: AABB = rg.mi.mesh.get_aabb()
	_ok(aabb.size.is_equal_approx(rg.r["size"]), "%s: size is the mesh AABB size" % sp)
	_ok(absf(aabb.position.y) < 0.01, "%s: stands on the ground (min y %.4f)" % [sp, aabb.position.y])

	# Weights.
	_ok(rg.bones.size() == n_v * 4 and rg.weights.size() == n_v * 4, "%s: 4 influence slots per vertex" % sp)
	var bad_sum := 0
	var bad_none := 0
	var bad_idx := 0
	var bad_neg := 0
	for vi in n_v:
		var s := 0.0
		var nz := 0
		for j in 4:
			var w := rg.weights[vi * 4 + j]
			s += w
			if w > 0.0:
				nz += 1
			if w < 0.0 or w > 1.0001:
				bad_neg += 1
			if rg.bones[vi * 4 + j] < 0 or rg.bones[vi * 4 + j] >= rg.names.size():
				bad_idx += 1
		if absf(s - 1.0) > 1e-4:
			bad_sum += 1
		if nz == 0:
			bad_none += 1
	_ok(bad_sum == 0, "%s: weights normalised (%d bad)" % [sp, bad_sum])
	_ok(bad_none == 0, "%s: every vertex weighted" % sp)
	_ok(bad_idx == 0 and bad_neg == 0, "%s: indices and weights in range" % sp)
	_ok(rg.names[0] == "root" or rg.names.has("root"), "%s: root bone" % sp)
	_weight_rules(sp, rg)
	_rest_pose_test(sp, rg)
	if sp != "penguin":
		for leg in FOUR:
			_leg_deformation(sp, rg, leg)
	else:
		for leg in ["leg_l", "leg_r"]:
			_leg_deformation(sp, rg, leg)
	_head_deformation(sp, rg)
	_free(rg)


func _weight_rules(sp: String, rg: Rig) -> void:
	var margin := 0.03
	var left_bad := 0
	var right_bad := 0
	var fb_bad := 0
	var mix_bad := 0
	var head_leg_bad := 0
	var split_z := 0.0
	if rg.pivots.has("leg_fl"):
		split_z = ((rg.pivots["leg_fl"] as Node3D).position.z + (rg.pivots["leg_bl"] as Node3D).position.z) * 0.5
	var head_set: Array = ["neck", "neck1", "head", "jaw", "ear_l", "ear_r", "trunk0", "trunk1", "trunk2"]
	for vi in rg.verts.size():
		var v := rg.verts[vi]
		var has_left := false
		var has_right := false
		var has_front := false
		var has_hind := false
		for j in 4:
			if rg.weights[vi * 4 + j] < 0.001:
				continue
			var bn: String = rg.names[rg.bones[vi * 4 + j]]
			var left := bn.ends_with("_l") or bn.ends_with("_l_low") or bn.begins_with("leg_fl") or bn.begins_with("leg_bl") or bn == "flipper_l"
			var right := bn.ends_with("_r") or bn.ends_with("_r_low") or bn.begins_with("leg_fr") or bn.begins_with("leg_br") or bn == "flipper_r"
			if left:
				has_left = true
				if v.x > margin:
					left_bad += 1
			if right:
				has_right = true
				if v.x < -margin:
					right_bad += 1
			if bn.begins_with("leg_f"):
				has_front = true
				if v.z < split_z:
					fb_bad += 1
			if bn.begins_with("leg_b"):
				has_hind = true
				if v.z > split_z:
					fb_bad += 1
		if has_left and has_right:
			mix_bad += 1
		if has_front and has_hind:
			mix_bad += 1
		if sp != "penguin" and _wsum(rg, vi, head_set) > 0.5 and _wsum(rg, vi, LEGS_ALL) > 0.0:
			head_leg_bad += 1
	_ok(left_bad == 0, "%s: no vertex right of the midline (x > %.2f) follows a left bone (%d)" % [sp, margin, left_bad])
	_ok(right_bad == 0, "%s: no vertex left of the midline follows a right bone (%d)" % [sp, right_bad])
	_ok(fb_bad == 0, "%s: no front-leg weight behind the split, no hind-leg weight ahead (%d)" % [sp, fb_bad])
	_ok(mix_bad == 0, "%s: left and right (front and hind) legs never mix on a vertex (%d)" % [sp, mix_bad])
	_ok(head_leg_bad == 0, "%s: head and neck vertices never follow legs (%d)" % [sp, head_leg_bad])
	# Coverage: the moving bones each own vertices (the jaw excepted).
	var owned := {}
	for vi in rg.verts.size():
		for j in 4:
			if rg.weights[vi * 4 + j] > 0.5:
				owned[rg.names[rg.bones[vi * 4 + j]]] = true
	for n in REQUIRED[sp]:
		if n != "prop" and n != "jaw":
			_ok(owned.has(n), "%s: bone %s owns vertices" % [sp, n])
	# Determinism: the weights are a pure function of position.
	var again: Dictionary = Skin3.weights_for(sp)
	var again_w: PackedFloat32Array = again["weights"]
	var again_b: PackedInt32Array = again["bones"]
	var same := again_w.size() == rg.weights.size()
	for i in mini(again_w.size(), rg.weights.size()):
		if absf(again_w[i] - rg.weights[i]) > 0.0002 or (again_w[i] > 0.001 and again_b[i] != rg.bones[i]):
			same = false
	_ok(same, "%s: weights deterministic" % sp)
	# Split vertices at one position share weights (no cracks).
	var seen := {}
	var crack := 0
	for vi in rg.verts.size():
		var key := Vector3i((rg.verts[vi] * 10000.0).round())
		var sig: Array = []
		for j in 4:
			sig.append([rg.bones[vi * 4 + j], snappedf(rg.weights[vi * 4 + j], 0.00001)])
		if seen.has(key):
			if seen[key] != sig:
				crack += 1
		else:
			seen[key] = sig
	_ok(crack == 0, "%s: co-located vertices share weights (%d)" % [sp, crack])


func _rest_pose_test(sp: String, rg: Rig) -> void:
	rg.sk.reset_bone_poses()
	var sk_pos := _skinned(rg)
	var worst := 0.0
	var miny := 1e9
	for i in sk_pos.size():
		worst = maxf(worst, sk_pos[i].distance_to(rg.verts[i]))
		miny = minf(miny, sk_pos[i].y)
	_ok(worst < 1e-4, "%s: rest pose skins to the original positions (%.6f)" % [sp, worst])
	_ok(absf(miny) < 0.005, "%s: floor contact unchanged (min y %.4f)" % [sp, miny])
	# sync of untouched pivots leaves the rest pose.
	Skin3.sync(rg.sk, rg.pivots)
	var sk2 := _skinned(rg)
	var worst2 := 0.0
	for i in sk2.size():
		worst2 = maxf(worst2, sk2[i].distance_to(rg.verts[i]))
	_ok(worst2 < 1e-4, "%s: sync at rest keeps the rest pose (%.6f)" % [sp, worst2])


func _reset(rg: Rig) -> void:
	for k in rg.pivots:
		if k == "body" or k == "prop":
			continue
		(rg.pivots[k] as Node3D).rotation = rg.r["rest"][k]
	Skin3.sync(rg.sk, rg.pivots)


func _leg_deformation(sp: String, rg: Rig, leg: String) -> void:
	_reset(rg)
	var base := _skinned(rg)
	var own: Array = [leg, leg + "_low"]
	var others: Array = []
	for k in (LEGS_ALL if sp != "penguin" else ["leg_l", "leg_r"]):
		if not own.has(k):
			others.append(k)
	(rg.pivots[leg] as Node3D).rotation = rg.r["rest"][leg] + Vector3(0.5, 0, 0)
	Skin3.sync(rg.sk, rg.pivots)
	var moved := _skinned(rg)
	var foot_max := 0.0
	var foot_n := 0
	var other_max := 0.0
	var head_max := 0.0
	var head_set: Array = ["neck", "neck1", "head", "ear_l", "ear_r", "trunk0", "trunk1", "trunk2"]
	for vi in rg.verts.size():
		var d := moved[vi].distance_to(base[vi])
		if rg.verts[vi].y < 0.15 and _wsum(rg, vi, own) > 0.99:
			foot_max = maxf(foot_max, d)
			foot_n += 1
		if rg.verts[vi].y < 0.15 and _wsum(rg, vi, others) > 0.99:
			other_max = maxf(other_max, d)
		if _wsum(rg, vi, head_set) > 0.99:
			head_max = maxf(head_max, d)
	_ok(foot_n > 0, "%s: %s has foot vertices" % [sp, leg])
	_ok(foot_max > (0.1 if sp == "penguin" else 0.2), "%s: rotating %s 0.5 rad moves its foot (%.3f m)" % [sp, leg, foot_max])
	_ok(other_max < 1e-5, "%s: %s leaves the other legs' feet unmoved (%.6f)" % [sp, leg, other_max])
	_ok(head_max < 1e-5, "%s: %s leaves the head unmoved (%.6f)" % [sp, leg, head_max])
	_reset(rg)


func _head_deformation(sp: String, rg: Rig) -> void:
	_reset(rg)
	var base := _skinned(rg)
	(rg.pivots["head"] as Node3D).rotation = rg.r["rest"]["head"] + Vector3(0.6, 0, 0)
	Skin3.sync(rg.sk, rg.pivots)
	var moved := _skinned(rg)
	var head_move := 0.0
	var body_move := 0.0
	var legs_move := 0.0
	for vi in rg.verts.size():
		var d := moved[vi].distance_to(base[vi])
		if _wsum(rg, vi, ["head"]) > 0.99:
			head_move = maxf(head_move, d)
		if _wsum(rg, vi, ["root"]) > 0.99:
			body_move = maxf(body_move, d)
		if _wsum(rg, vi, LEGS_ALL + ["leg_l", "leg_r"]) > 0.99:
			legs_move = maxf(legs_move, d)
	_ok(head_move > 0.05, "%s: nodding the head moves head vertices (%.3f)" % [sp, head_move])
	_ok(body_move < 1e-5 and legs_move < 1e-5, "%s: nodding leaves the body and legs still" % sp)
	_reset(rg)


# ---------------------------------------------------------------------------------- procedural poses

func _procedural_names_test() -> void:
	var script := load("res://scripts/art/zoo_animal.gd") as GDScript
	_ok(script != null and script.can_instantiate(), "zoo_animal.gd compiles")
	if script == null or not script.can_instantiate():
		return
	for sp in ["lion", "giraffe", "zebra"]:
		var z: Node3D = script.new()
		z.call("setup", sp, "skintest", 0, false)
		var procedural: Dictionary = z.get("_pivots")
		var rg := _make(sp)
		for k in procedural:
			if k == "body" or k == "prop":
				continue
			if sp == "lion" and (k == "ear_l" or k == "ear_r"):
				continue   # the standard gives the lion no ear pivots (its ears are in the mane)
			_ok(rg.pivots.has(k), "%s: procedural pivot %s exists on the skin" % [sp, k])
		# Every name _pose_animal writes for this species resolves on the skin or is ignored by
		# the caller as it is on the procedural rig (the pose loop only visits existing pivots).
		var target := {}
		z.set("species", sp)
		for act in ["walk", "prowl", "trot", "gallop", "nap", "survey", "look", "nod", "yawn", "roar", "roll", "stretch", "eat", "graze", "drink", "bow", "shake", "swim", "stalk", "buck", "lick", "chuff", "puzzled", "pool_leap"]:
			z.set("action", act)
			target = {}
			z.call("_pose_animal", target, 1.3, 1.0)
			for k in target:
				if k == "_off" or k == "_rot":
					continue
				if not procedural.has(k):
					continue   # written but absent on the procedural rig too (ignored by _pose)
				_ok(rg.pivots.has(k), "%s %s: written pivot %s exists on the skin" % [sp, act, k])
		# The procedural walk, played on the skin, lifts every foot and moves diagonal pairs together.
		_walk_check_from_procedural(sp, z, rg)
		z.free()
		_free(rg)


func _walk_check_from_procedural(sp: String, z: Node3D, rg: Rig) -> void:
	var series := {"leg_fl": [], "leg_fr": [], "leg_bl": [], "leg_br": []}
	z.set("action", "walk")
	var speed := 6.0
	var steps := 24
	for i in steps:
		var t := float(i) / steps * TAU / speed
		var target := {}
		z.call("_pose_animal", target, t, 1.0)
		_apply_target(rg, target)
		var pos := _skinned(rg)
		for leg in FOUR:
			series[leg].append(_foot(rg, pos, leg))
	_check_series(sp + " (procedural walk on the skin)", series)
	_reset(rg)


## Mean position of a leg's foot vertices (those within 6 cm of the floor at rest).
func _foot(rg: Rig, pos: PackedVector3Array, leg: String) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for vi in rg.verts.size():
		if rg.verts[vi].y < 0.06 and _wsum(rg, vi, [leg, leg + "_low"]) > 0.99:
			s += pos[vi]
			n += 1
	return s / maxf(1.0, float(n))


func _check_series(label: String, series: Dictionary) -> void:
	var ys := {}
	var zs := {}
	for leg in series:
		ys[leg] = []
		zs[leg] = []
		for p in series[leg]:
			(ys[leg] as Array).append((p as Vector3).y)
			(zs[leg] as Array).append((p as Vector3).z)
		var arr: Array = ys[leg]
		_ok(arr.max() - arr.min() > 0.03, "%s: %s lifts by %.3f m" % [label, leg, arr.max() - arr.min()])
		var za: Array = zs[leg]
		_ok(za.max() - za.min() > 0.08, "%s: %s swings fore and aft by %.3f m" % [label, leg, za.max() - za.min()])
	_ok(_corr(zs["leg_fl"], zs["leg_br"]) > 0.7, "%s: front-left and back-right step together (%.2f)" % [label, _corr(zs["leg_fl"], zs["leg_br"])])
	_ok(_corr(zs["leg_fr"], zs["leg_bl"]) > 0.7, "%s: front-right and back-left step together (%.2f)" % [label, _corr(zs["leg_fr"], zs["leg_bl"])])
	_ok(_corr(zs["leg_fl"], zs["leg_fr"]) < -0.7, "%s: left and right alternate (%.2f)" % [label, _corr(zs["leg_fl"], zs["leg_fr"])])


## Apply a pose target to the pivots (rest + offset, no easing) and sync the bones.
func _apply_target(rg: Rig, target: Dictionary) -> void:
	for k in rg.pivots:
		if k == "body" or k == "prop":
			continue
		var off: Vector3 = target.get(k, Vector3.ZERO)
		(rg.pivots[k] as Node3D).rotation = (rg.r["rest"][k] as Vector3) + off
	Skin3.sync(rg.sk, rg.pivots)


# ---------------------------------------------------------------------------------- pose_extra

func _pose_tests() -> void:
	for sp in ["panda", "elephant", "penguin"]:
		var rg := _make(sp)
		# Every action fills sane numbers and the body keys.
		for act in (ACTIONS[sp] as Array) + ["no_such_action"]:
			var target := {}
			Extra.pose(sp, act, target, 2.7, 1.0, 0.4, 0.3, false)
			_ok(target.has("_off") and target.has("_rot"), "%s %s: _off and _rot set" % [sp, act])
			var finite := true
			for k in target:
				var v = target[k]
				if v is Vector3:
					finite = finite and is_finite((v as Vector3).x) and is_finite((v as Vector3).y) and is_finite((v as Vector3).z)
					if k != "_off" and k != "_rot":
						finite = finite and rg.pivots.has(k)
			_ok(finite, "%s %s: finite offsets on existing pivots" % [sp, act])
			var idle := {}
			Extra.pose(sp, "idle", idle, 2.7, 1.0, 0.4, 0.3, false)
			if act == "no_such_action":
				_ok(target == idle, "%s: unknown action falls back to idle" % sp)
		# Idle breathes: the body offset changes over time.
		var lo := 1e9
		var hi := -1e9
		for i in 40:
			var tg := {}
			Extra.pose(sp, "idle", tg, float(i) * 0.1, 1.0, 0.0, 0.0, false)
			lo = minf(lo, (tg["_off"] as Vector3).y)
			hi = maxf(hi, (tg["_off"] as Vector3).y)
		_ok(hi - lo > 0.005, "%s: idle breathes (%.4f m)" % [sp, hi - lo])
		# Reduced motion shrinks the walk's swing.
		var full := {}
		var calm := {}
		var key := "leg_fl" if sp != "penguin" else "leg_l"
		var swing_full := 0.0
		var swing_calm := 0.0
		for i in 40:
			Extra.pose(sp, "walk", full, float(i) * 0.1, 1.0, 0.0, 0.0, false)
			Extra.pose(sp, "walk", calm, float(i) * 0.1, 0.6, 0.0, 0.0, true)
			swing_full = maxf(swing_full, absf((full[key] as Vector3).x))
			swing_calm = maxf(swing_calm, absf((calm[key] as Vector3).x))
		_ok(swing_calm < swing_full, "%s: reduced motion walks with smaller swing (%.2f < %.2f)" % [sp, swing_calm, swing_full])
		# A different animal phase steps out of time.
		var ta := {}
		var tb := {}
		Extra.pose(sp, "walk", ta, 1.0, 1.0, 0.0, 0.0, false)
		Extra.pose(sp, "walk", tb, 1.0, 1.0, 0.0, 1.7, false)
		_ok(ta != tb, "%s: param shifts the gait phase" % sp)
		# Walk on the skin: feet lift, sides alternate.
		if sp != "penguin":
			var series := {"leg_fl": [], "leg_fr": [], "leg_bl": [], "leg_br": []}
			var steps := 24
			var spd := {"panda": 5.0, "elephant": 3.4}[sp] as float
			for i in steps:
				var target := {}
				Extra.pose(sp, "walk", target, float(i) / steps * TAU / spd, 1.0, 0.0, 0.0, false)
				_apply_target(rg, target)
				var pos := _skinned(rg)
				for leg in FOUR:
					series[leg].append(_foot(rg, pos, leg))
			_check_series(sp + " walk", series)
		else:
			for act in ["walk", "waddle"]:
				var yl: Array = []
				var yr: Array = []
				var zl: Array = []
				var zr: Array = []
				var roll: Array = []
				for i in 24:
					var target := {}
					Extra.pose(sp, act, target, float(i) / 24.0 * TAU / 6.0, 1.0, 0.0, 0.0, false)
					_apply_target(rg, target)
					var pos := _skinned(rg)
					var fl_pos := _foot_pen(rg, pos, "leg_l")
					var fr_pos := _foot_pen(rg, pos, "leg_r")
					yl.append(fl_pos.y)
					yr.append(fr_pos.y)
					zl.append(fl_pos.z)
					zr.append(fr_pos.z)
					roll.append((target["_rot"] as Vector3).z)
				_ok((yl.max() - yl.min()) > 0.015 and (yr.max() - yr.min()) > 0.015, "penguin %s: both feet lift (%.3f, %.3f)" % [act, yl.max() - yl.min(), yr.max() - yr.min()])
				_ok(_corr(zl, zr) < -0.5, "penguin %s: feet alternate (%.2f)" % [act, _corr(zl, zr)])
				_ok(roll.max() - roll.min() > 0.2, "penguin %s: the body rolls (%.2f rad)" % [act, roll.max() - roll.min()])
				# The flippers counter-swing against the feet.
				var fl: Array = []
				for i in 24:
					var target := {}
					Extra.pose(sp, act, target, float(i) / 24.0 * TAU / 6.0, 1.0, 0.0, 0.0, false)
					fl.append((target["flipper_l"] as Vector3).x)
				_ok(fl.max() - fl.min() > 0.3, "penguin %s: flippers swing (%.2f)" % [act, fl.max() - fl.min()])
		_free(rg)


func _foot_pen(rg: Rig, pos: PackedVector3Array, leg: String) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for vi in rg.verts.size():
		if rg.verts[vi].y < 0.04 and _wsum(rg, vi, [leg]) > 0.99:
			s += pos[vi]
			n += 1
	return s / maxf(1.0, float(n))


func _misc_tests() -> void:
	_ok(not Skin3.has_model("hippo") and not Skin3.has_model("lioness") and not Skin3.has_model(""), "has_model false for other species")
	var a := Node3D.new()
	var b := Node3D.new()
	a.add_child(b)
	_ok(Skin3.build(a, b, "hippo").is_empty(), "build returns {} for a procedural species")
	a.free()
	# Elephant trunk chain follows a trunk pose (trunk2 tip rises).
	var rg := _make("elephant")
	_reset(rg)
	var base := _skinned(rg)
	var tip := -1
	var lowest := 1e9
	for vi in rg.verts.size():
		if _wsum(rg, vi, ["trunk2"]) > 0.99 and rg.verts[vi].y < lowest:
			lowest = rg.verts[vi].y
			tip = vi
	var target := {}
	Extra.pose("elephant", "trumpet", target, 1.0, 1.0, 0.5, 0.0, false)
	_apply_target(rg, target)
	var moved := _skinned(rg)
	_ok(tip >= 0 and moved[tip].y > base[tip].y + 0.8, "elephant: trumpet raises the trunk tip (%.2f m)" % (moved[tip].y - base[tip].y if tip >= 0 else -1.0))
	_free(rg)
