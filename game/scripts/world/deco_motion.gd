## Decorative motion (r20, design/decorative-motion.md): a few placed decorations move gently while their
## room or the town is on screen. Purely cosmetic and local: nothing is sent, saved or changed in the
## town, and it never touches an item's root transform, anchors, markers, collision or selection.
##
## Every pose is computed from the time alone ("absolute"), on top of the part's own transform recorded
## once when the item is built, so nothing drifts or accumulates. With Reduce motion on (a local setting
## in user://settings.cfg) every part goes back to that recorded pose and lights to their steady
## brightness at once.
##
## spin: the three blades of ceiling_fan_light turn about the fan's axis. The frozen model has one merged
##   mesh; its blades are separate, unconnected pieces of the white surface, so this module copies them
##   into a turning part (and the rest into a static copy) per instance. The GLB file and its shared
##   mesh are never modified (Modeling owns them).
## sway: a hanging decoration swings a few degrees about its hook (the item's origin).
## glow: the item's own lamp (Light0) breathes slowly between 85 % and 100 % of its normal brightness;
##   off by day as before. No flashing.
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"

## The first batch (exact catalog ids). circulator_fan is not here: its model has no blades (a closed
## drum behind a fixed guard), so it needs a Modeling change first.
const MOTION := {
	"ceiling_fan_light": "spin",
	"bird_mobile": "sway",
	"red_paper_lantern": "sway",
	"candle_ring_chandelier": "glow",
	"bamboo_floor_lantern": "glow",
}
const SPIN_RATE := 0.25 * TAU          # a quarter turn per second: a slow fan
const SWAY_X := deg_to_rad(3.5)
const SWAY_Z := deg_to_rad(2.5)
const SWAY_PERIODS := Vector2(3.4, 4.7)
const GLOW_PERIOD := 6.0
const GLOW_LOW := 0.85                 # brightness factor range 0.85 .. 1.0
const LAMP_ENERGY := 1.6               # TownWorld._apply_evening: lamp energy = 1.6 * evening

static var _fan_split := {}            # kind -> {static: ArrayMesh, blades: ArrayMesh, surface: int, axis: Vector3, islands: int}


## Drops the cached fan pieces (the world calls this when it leaves the tree, so nothing outlives it).
static func clear_cache() -> void:
	_fan_split.clear()


static func has_motion(kind: String) -> bool:
	return MOTION.has(kind)


static func load_reduce() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value("display", "reduce_motion", false))


static func save_reduce(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "reduce_motion", on)
	cfg.save(SETTINGS_PATH)


## Prepares a built item node for motion and returns its state (empty if the kind has none).
static func attach(node: Node3D, kind: String, id: String) -> Dictionary:
	var mode: String = MOTION.get(kind, "")
	var model := node.get_node_or_null("Model") as Node3D
	if mode == "" or model == null:
		return {}
	var st := {"kind": kind, "mode": mode, "node": node, "phase": float(hash(id) % 1000) / 1000.0 * TAU}
	match mode:
		"spin":
			var mi := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var split := fan_split(kind, mi.mesh)
			if split.is_empty():
				return {}
			var overrides := []
			for si in mi.mesh.get_surface_count():
				overrides.append(mi.get_surface_override_material(si))
			mi.mesh = split["static"]
			for si in overrides.size():
				mi.set_surface_override_material(si, overrides[si])
			var pivot := Node3D.new()
			pivot.name = "BladePivot"
			pivot.position = split["axis"]
			mi.add_child(pivot)
			var blades := MeshInstance3D.new()
			blades.name = "Blades"
			blades.mesh = split["blades"]
			blades.set_surface_override_material(0, overrides[split["surface"]])
			blades.cast_shadow = mi.cast_shadow
			pivot.add_child(blades)
			st["part"] = pivot
			st["base"] = pivot.transform
		"sway":
			st["part"] = model
			st["base"] = model.transform
		"glow":
			var light: OmniLight3D = null
			for c in node.get_children():
				if c is OmniLight3D:
					light = c
			if light == null:
				return {}
			st["light"] = light
	return st


## The pose at time t (seconds). evening: TownWorld.evening (0 day .. 1 evening).
static func tick(st: Dictionary, t: float, evening: float) -> void:
	match st["mode"]:
		"spin":
			var a := fposmod(t * SPIN_RATE + st["phase"], TAU)
			(st["part"] as Node3D).transform = st["base"] * Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
		"sway":
			var ax := SWAY_X * sin(TAU * t / SWAY_PERIODS.x + st["phase"])
			var az := SWAY_Z * sin(TAU * t / SWAY_PERIODS.y + st["phase"] * 1.7)
			(st["part"] as Node3D).transform = Transform3D(Basis.from_euler(Vector3(ax, 0, az)), Vector3.ZERO) * st["base"]
		"glow":
			(st["light"] as OmniLight3D).light_energy = LAMP_ENERGY * evening * glow_factor(t, st["phase"])


static func glow_factor(t: float, phase: float) -> float:
	return GLOW_LOW + (1.0 - GLOW_LOW) * (0.5 + 0.5 * sin(TAU * t / GLOW_PERIOD + phase))


## Back to the still pose: the recorded transform, steady brightness.
static func rest(st: Dictionary, evening: float) -> void:
	if st.has("part") and is_instance_valid(st["part"]):
		(st["part"] as Node3D).transform = st["base"]
	if st.has("light") and is_instance_valid(st["light"]):
		(st["light"] as OmniLight3D).light_energy = LAMP_ENERGY * evening


## ceiling_fan_light's blades: the unconnected pieces of one surface that are thin and wide (a blade is
## a flat plate about 0.47 m long). Returns a static copy without them, a blade mesh centered on the
## fan's axis (the mean of the blades' centers), and that axis. Built once per kind; read-only after.
static func fan_split(kind: String, mesh: Mesh) -> Dictionary:
	if _fan_split.has(kind):
		return _fan_split[kind]
	var out := {}
	var stat := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var blade_tris := PackedInt32Array()
		var keep := PackedInt32Array()
		var centers := []
		if out.is_empty():
			for isle in _islands(verts, idx):
				var lo := Vector3.INF
				var hi := -Vector3.INF
				for tri in isle:
					for j in 3:
						var v: Vector3 = verts[idx[tri + j]]
						lo = lo.min(v)
						hi = hi.max(v)
				var size := hi - lo
				if size.y < 0.04 and maxf(size.x, size.z) > 0.35:
					centers.append((lo + hi) * 0.5)
					for tri in isle:
						blade_tris.append_array([idx[tri], idx[tri + 1], idx[tri + 2]])
		if centers.size() >= 3:
			var axis := Vector3.ZERO
			for c in centers:
				axis += c
			axis /= centers.size()
			axis.y = 0.0
			var blade_set := {}
			for i in range(0, blade_tris.size(), 3):
				blade_set["%d,%d,%d" % [blade_tris[i], blade_tris[i + 1], blade_tris[i + 2]]] = true
			for i in range(0, idx.size(), 3):
				if not blade_set.has("%d,%d,%d" % [idx[i], idx[i + 1], idx[i + 2]]):
					keep.append_array([idx[i], idx[i + 1], idx[i + 2]])
			var b_arrays := arrays.duplicate()
			var moved := PackedVector3Array()
			moved.resize(verts.size())
			for i in verts.size():
				moved[i] = verts[i] - axis
			b_arrays[Mesh.ARRAY_VERTEX] = moved
			b_arrays[Mesh.ARRAY_INDEX] = blade_tris
			var blades := ArrayMesh.new()
			blades.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b_arrays)
			blades.surface_set_material(0, mesh.surface_get_material(si))
			out = {"blades": blades, "surface": si, "axis": axis, "islands": centers.size()}
			var s_arrays := arrays.duplicate()
			s_arrays[Mesh.ARRAY_INDEX] = keep
			arrays = s_arrays
		stat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		stat.surface_set_material(si, mesh.surface_get_material(si))
	if out.is_empty():
		return {}
	out["static"] = stat
	_fan_split[kind] = out
	return out


## Groups triangles (by their first index) into pieces that share a vertex position.
static func _islands(verts: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var parent := []   # an Array (shared by reference with the lambda; packed arrays are copied)
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var seen := {}
	for i in verts.size():
		var key := verts[i].snapped(Vector3.ONE * 0.0001)
		if seen.has(key):
			parent[find.call(i)] = find.call(seen[key])
		else:
			seen[key] = i
	for i in range(0, idx.size(), 3):
		parent[find.call(idx[i + 1])] = find.call(idx[i])
		parent[find.call(idx[i + 2])] = find.call(idx[i])
	var groups := {}
	for i in range(0, idx.size(), 3):
		groups.get_or_add(find.call(idx[i]), []).append(i)
	return groups.values()
