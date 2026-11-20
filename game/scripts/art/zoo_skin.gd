## A skinned Everything Library animal driven by the zoo's named pivots
## (docs/zoo-engineering-standard.md 11.1).
##
## build() makes, under the animal's body node, the same named pivot Node3D tree the procedural
## rigs have (zoo_skin_rigs.gd gives the joints), a Skeleton3D whose bones mirror those pivots, a
## Skin with the matching bind poses, and one MeshInstance3D whose ArrayMesh is the GLB's own
## surface (positions, normals and linear vertex colours unchanged) plus bone indices and weights.
## ZooAnimal eases the pivots as it always did, then calls sync() to copy them into the bones.
##
## Weights are a pure function of a vertex's position and the rig table (see zoo_skin_rigs.gd for
## the rule). Siblings never mix: a left and a right leg, front and hind legs, the neck chain and
## the legs have disjoint regions, and the jaw owns no vertices.
extends RefCounted

const Rigs := preload("res://scripts/art/zoo_skin_rigs.gd")

const MODEL_DIR := "res://assets/models/zoo_everything/"
const ROOT_BONE := "root"
const MAX_INFLUENCES := 4
const MIN_WEIGHT := 0.0001

static var _source_cache := {}    # species -> {"arrays": Array}
static var _weight_cache := {}    # species -> {"bones": PackedInt32Array, "weights": PackedFloat32Array}


static func has_model(species: String) -> bool:
	return Rigs.SPECIES.has(species)


## Build the pivots, skeleton and skinned mesh for `species` under `body` (a child of `animal`).
## Returns {} when the species has no imported model or its model cannot be loaded.
static func build(animal: Node3D, body: Node3D, species: String) -> Dictionary:
	if not has_model(species):
		return {}
	var tbl: Dictionary = Rigs.table(species)
	var arrays: Array = _source_arrays(species)
	if arrays.is_empty():
		return {}
	var bones: Array = tbl["bones"]

	# Rest transforms: each pivot frame is the joint position with a pure X pitch.
	var names: Array = [ROOT_BONE]
	var globals: Dictionary = {ROOT_BONE: Transform3D.IDENTITY}
	var pitches: Dictionary = {ROOT_BONE: 0.0}
	var pivots: Dictionary = {}
	var rest: Dictionary = {}
	var local_rest: Dictionary = {ROOT_BONE: Transform3D.IDENTITY}
	for b in bones:
		var bd: Dictionary = b
		var n: String = bd["n"]
		var par: String = bd["p"]
		var pitch: float = bd.get("pitch", 0.0)
		var g := Transform3D(Basis.from_euler(Vector3(pitch, 0.0, 0.0)), bd["j"])
		var lt: Transform3D = (globals[par] as Transform3D).affine_inverse() * g
		globals[n] = g
		pitches[n] = pitch
		local_rest[n] = lt
		names.append(n)
		var node := Node3D.new()
		node.name = n
		node.position = lt.origin
		var rot := Vector3(pitch - float(pitches[par]), 0.0, 0.0)
		node.rotation = rot
		var holder: Node3D = body if par == ROOT_BONE else pivots[par]
		holder.add_child(node)
		pivots[n] = node
		rest[n] = rot

	# The skeleton: the root bone (the body itself) and one bone per pivot.
	var skeleton := Skeleton3D.new()
	skeleton.name = "skeleton"
	var skin := Skin.new()
	for i in names.size():
		var n: String = names[i]
		skeleton.add_bone(n)
	for i in names.size():
		var n: String = names[i]
		if n != ROOT_BONE:
			var par_name: String = _parent_of(bones, n)
			skeleton.set_bone_parent(i, names.find(par_name))
		skeleton.set_bone_rest(i, local_rest[n])
	skeleton.reset_bone_poses()
	for i in names.size():
		var n: String = names[i]
		skin.add_bind(i, (globals[n] as Transform3D).affine_inverse())
		skin.set_bind_name(i, n)
	body.add_child(skeleton)

	# The mesh: the GLB surface plus bones and weights.
	var wt: Dictionary = _weights(species, arrays[Mesh.ARRAY_VERTEX], names, bones)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
	arr[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	arr[Mesh.ARRAY_COLOR] = arrays[Mesh.ARRAY_COLOR]
	arr[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	arr[Mesh.ARRAY_BONES] = wt["bones"]
	arr[Mesh.ARRAY_WEIGHTS] = wt["weights"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _material())
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	mi.mesh = mesh
	mi.skin = skin
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	var box: AABB = mesh.get_aabb()
	mi.custom_aabb = box.grow(0.7)   # poses move limbs well outside the rest bounds

	# The prop: at the mouth, under the animal, not a bone.
	var prop := Node3D.new()
	prop.name = "prop"
	prop.position = tbl["prop"]
	animal.add_child(prop)
	pivots["body"] = body
	pivots["prop"] = prop
	rest["body"] = Vector3.ZERO
	rest["prop"] = Vector3.ZERO
	return {"pivots": pivots, "rest": rest, "size": box.size, "skeleton": skeleton, "mesh": mi}


## Copy every pivot's local transform into its bone pose (call after the pivots are posed).
static func sync(skeleton: Skeleton3D, pivots: Dictionary) -> void:
	if skeleton == null:
		return
	for k in pivots:
		var bn: String = k
		if bn == "body" or bn == "prop":
			continue
		var idx := skeleton.find_bone(bn)
		if idx < 0:
			continue
		var n: Node3D = pivots[k]
		skeleton.set_bone_pose_position(idx, n.position)
		skeleton.set_bone_pose_rotation(idx, n.quaternion)


## The bone names in skeleton order for a species (root first), for tools and tests.
static func bone_names(species: String) -> Array:
	var out: Array = [ROOT_BONE]
	for b in (Rigs.table(species)["bones"] as Array):
		out.append((b as Dictionary)["n"])
	return out


## The cached vertex influences for a species: {"bones": PackedInt32Array, "weights": PackedFloat32Array}.
static func weights_for(species: String) -> Dictionary:
	var arrays: Array = _source_arrays(species)
	if arrays.is_empty():
		return {}
	var tbl: Dictionary = Rigs.table(species)
	return _weights(species, arrays[Mesh.ARRAY_VERTEX], bone_names(species), tbl["bones"])


# ---------------------------------------------------------------------------------- internals

static func _parent_of(bones: Array, n: String) -> String:
	for b in bones:
		if (b as Dictionary)["n"] == n:
			return (b as Dictionary)["p"]
	return ROOT_BONE


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.roughness = 1.0
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## The GLB's surface arrays (vertex, normal, colour, index), loaded once per species.
static func _source_arrays(species: String) -> Array:
	if _source_cache.has(species):
		return _source_cache[species]
	var path := MODEL_DIR + "everything_%s.glb" % species
	var root: Node = null
	var scene := load(path) as PackedScene
	if scene != null:
		root = scene.instantiate()
	elif FileAccess.file_exists(path):
		# Not imported (a bare checkout in a test run): read the GLB directly.
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), state) == OK:
			root = doc.generate_scene(state)
	var out: Array = []
	if root != null:
		var mi := _find_mesh(root)
		if mi != null and mi.mesh != null:
			var src: Array = mi.mesh.surface_get_arrays(0)
			out.resize(Mesh.ARRAY_MAX)
			for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
				out[slot] = src[slot]
		root.free()
	_source_cache[species] = out
	return out


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f := _find_mesh(c)
		if f != null:
			return f
	return null


## Soft box and half space masks (zoo_skin_rigs.gd header).
static func _ramp(v: float, lo: float, hi: float, e: float) -> float:
	var s := maxf(e, 0.0001)
	return smoothstep(lo - s, lo + s, v) * (1.0 - smoothstep(hi - s, hi + s, v))


static func _local_mask(b: Dictionary, v: Vector3) -> float:
	if b.get("none", false):
		return 0.0
	var m := 1.0
	if b.has("box"):
		var bx: Array = b["box"]
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		var e: Vector3 = bx[2]
		m *= _ramp(v.x, lo.x, hi.x, e.x)
		if m > 0.0:
			m *= _ramp(v.y, lo.y, hi.y, e.y)
		if m > 0.0:
			m *= _ramp(v.z, lo.z, hi.z, e.z)
	if m > 0.0 and b.has("plane"):
		var pl: Array = b["plane"]
		var pt: Vector3 = pl[0]
		var dir: Vector3 = pl[1]
		var band: float = pl[2]
		m *= smoothstep(-band, band, (v - pt).dot(dir.normalized()))
	return m


## Where the soft regions of the neck chain and of a leg overlap (the chest, the shoulder), the
## family holding the larger share keeps the vertex outright: a head or neck vertex never follows a
## leg, and a leg vertex never follows the head. `rem` is indexed like `names`.
static func _separate_legs_from_head(names: Array, rem: PackedFloat32Array) -> void:
	var legs := 0.0
	var head := 0.0
	for k in range(1, names.size()):
		var n: String = names[k]
		if n.begins_with("leg_"):
			legs += rem[k]
		elif n.begins_with("neck") or n == "head" or n == "jaw" or n.begins_with("ear_") or n.begins_with("trunk"):
			head += rem[k]
	if legs <= 0.0 or head <= 0.0:
		return
	var keep_head := head >= legs
	var scale := (legs + head) / (head if keep_head else legs)
	for k in range(1, names.size()):
		var n: String = names[k]
		var is_leg := n.begins_with("leg_")
		var is_head := n.begins_with("neck") or n == "head" or n == "jaw" or n.begins_with("ear_") or n.begins_with("trunk")
		if is_leg:
			rem[k] = 0.0 if keep_head else rem[k] * scale
		elif is_head:
			rem[k] = rem[k] * scale if keep_head else 0.0


static func _weights(species: String, verts: PackedVector3Array, names: Array, bones: Array) -> Dictionary:
	if _weight_cache.has(species):
		return _weight_cache[species]
	var nb := bones.size()
	# Membership parent of bone i (0 = root; bone i is index i + 1 in `names`) and the order the
	# bones claim their share: parents first, siblings by "order" then table position.
	var mp: Array = []
	for b in bones:
		var bd: Dictionary = b
		mp.append(names.find(bd.get("mp", bd["p"])))
	var order: Array = []
	var queue: Array = [0]
	while not queue.is_empty():
		var par: int = queue.pop_front()
		var kids: Array = []
		for i in nb:
			if mp[i] == par:
				kids.append(i)
		kids.sort_custom(func(a: int, c: int) -> bool:
			var oa: float = (bones[a] as Dictionary).get("order", 0.0)
			var oc: float = (bones[c] as Dictionary).get("order", 0.0)
			if oa != oc:
				return oa < oc
			return a < c)
		for k in kids:
			order.append(k)
			queue.append(k + 1)
	var out_bones := PackedInt32Array()
	var out_weights := PackedFloat32Array()
	out_bones.resize(verts.size() * MAX_INFLUENCES)
	out_weights.resize(verts.size() * MAX_INFLUENCES)
	var mem := PackedFloat32Array()
	var rem := PackedFloat32Array()
	mem.resize(nb + 1)
	rem.resize(nb + 1)
	for vi in verts.size():
		var v: Vector3 = verts[vi]
		mem[0] = 1.0
		rem[0] = 1.0
		for i in order:
			var par: int = mp[i]
			var local := _local_mask(bones[i], v)
			var m := minf(mem[par] * local, rem[par])
			rem[par] -= m
			mem[i + 1] = m
			rem[i + 1] = m
		# rem[k] is now bone k's own weight (its membership minus what its children took).
		_separate_legs_from_head(names, rem)
		var picks: Array = []
		for k in nb + 1:
			if rem[k] > MIN_WEIGHT:
				picks.append([rem[k], k])
		picks.sort_custom(func(a: Array, c: Array) -> bool:
			if absf(float(a[0]) - float(c[0])) > 0.000001:
				return float(a[0]) > float(c[0])
			return int(a[1]) < int(c[1]))
		var total := 0.0
		var cnt := mini(picks.size(), MAX_INFLUENCES)
		for j in cnt:
			total += float((picks[j] as Array)[0])
		for j in MAX_INFLUENCES:
			if j < cnt:
				out_bones[vi * MAX_INFLUENCES + j] = int((picks[j] as Array)[1])
				out_weights[vi * MAX_INFLUENCES + j] = float((picks[j] as Array)[0]) / total
			else:
				out_bones[vi * MAX_INFLUENCES + j] = 0
				out_weights[vi * MAX_INFLUENCES + j] = 0.0
	var res := {"bones": out_bones, "weights": out_weights}
	_weight_cache[species] = res
	return res
