## The city's people (design/city-district.md "City r2"): about fifty townsfolk drawn with a handful of
## MultiMeshes and animated as a pure function of the city's view clock.
##
## Who and where: core/city_people_data.gd (PEOPLE, WALKER_LOOKS, FERRIS_SLOTS, CAROUSEL_RIDERS). The walkers
## walk CityRules.walkers(t); the Ferris passengers ride the gondolas no child is in (Data.ferris_rides, boarding
## and leaving at the bottom); two riders sit on carousel horses.
##
## Drawing: one MultiMesh per part shape (a bevelled box, a limb, a plain block, the head, the skirt and six hair
## styles), each instance coloured through MultiMesh colours on PropsCity's matte vertex-colour material, so the
## people are 11 draw calls in all. A person is a rig of parts (torso, head, hair, two-bone arms and legs, or a
## seated lap); arms and legs use simple forward kinematics or two-bone IK toward hands' and feet's targets.
##
## Time: every pose is a pure function of the time handed to pose_at(t) (the city world's view_time(), so
## Pause freezes them and late joiners see the same), of each person's own clock (Data.timing) and of the shared
## riders. No randomness at run time. Per frame only the moving people are posed every frame; the slow ones
## (seated, staff) alternate halves, and the parts that never move (a seated person's legs) are written only
## when a person appears. The owner adds this node under the city world after build() and calls setup().
extends Node3D

const Data := preload("res://scripts/core/city_people_data.gd")
const CityMap := preload("res://scripts/core/city_map.gd")
const CityRules := preload("res://scripts/core/city_rules.gd")
const PropsCity := preload("res://scripts/art/props_city.gd")
const CityNav := preload("res://scripts/core/city_nav.gd")

## Part shapes, one MultiMesh (one draw call) each.
enum { M_BOX, M_LIMB, M_BLOCK, M_HEAD, M_SKIRT, M_HAIR_SHORT, M_HAIR_LONG, M_HAIR_BUN, M_HAIR_PONY, M_HAIR_CURLY, M_HAIR_CAP, M_UMBRELLA, M_COUNT }
const MESH_NAMES := ["Box", "Limb", "Block", "Head", "Skirt", "HairShort", "HairLong", "HairBun", "HairPonytail", "HairCurly", "HairCap", "Umbrella"]
const HAIR_MESH := {"short": M_HAIR_SHORT, "long": M_HAIR_LONG, "bun": M_HAIR_BUN, "ponytail": M_HAIR_PONY, "curly": M_HAIR_CURLY, "cap": M_HAIR_CAP}

## The parts of a rig (a person's slots).
enum { P_TORSO, P_HEAD, P_UARM0, P_UARM1, P_FARM0, P_FARM1, P_HAND0, P_HAND1, P_PELVIS, P_THIGH0, P_THIGH1, P_SHIN0, P_SHIN1,
	P_SHOE0, P_SHOE1, P_LAP, P_SHINS, P_SHOES, P_SKIRT, P_APRON, P_FRONT, P_GLASSES, P_BEARD, P_BAG, P_SCARF, P_PROP_A, P_PROP_B,
	P_UMBRELLA, P_HAIR0, P_HAIR1, P_HAIR2, P_COUNT }
enum { K_STATIC, K_WALKER, K_FERRIS, K_CAROUSEL }

## Body measurements at scale 1 (1.0 is about 1.8 m to the top of the head).
const HIP_STAND := 0.86
const TORSO_H := 0.46
const TORSO_D := 0.24
const SHOULDER_Y := 0.51
const NECK_Y := 0.58
const HEAD_C := 0.18           # the head's centre above the neck pivot
const UARM := 0.28
const FARM := 0.25
const THIGH := 0.40
const SHIN := 0.38
const SHOE_H := 0.08
const HIP_X := 0.09
## Seated: the hip joint above the seat surface.
const SIT_HIP := 0.07
## The Ferris gondola's bench above its floor (CityWorld.rider_transform puts riders on the floor).
const BENCH_Y := 0.3
## The carousel's seat transform is 3 cm under the saddle's top.
const SADDLE_UP := 0.03
const SLOW_GROUPS := 2
## Umbrella canopies: bright, one per person by id.
const UMBRELLA_COLORS := [Color("#ff6f7d"), Color("#ffd75e"), Color("#4fb0ff"), Color("#5fcfa4"), Color("#a98cf0"), Color("#ff8552"), Color("#ff9ec7")]
## Metres of path over which a person gets up from a seat, or settles at the cover spot.
const BLEND_M := 0.6
## A walker's stride (CityRules.WALK_STRIDE): one walk cycle per this many metres.
const STRIDE := 1.5
const BODY_R := 0.3

## Per-frame accounting (tests and the report): instance transforms written by the last frame() or pose_at().
var writes_last := 0
var people: Array = []                 # Array of Person
var city_world: Node3D = null
var hidden_regions := {}
## Child riders, {gondola: [peers]}; null reads city_world.riders.
var riders_override: Variant = null
var time_override := -1.0              # >= 0: a fixed time (tests)

var _mm: Array[MultiMesh] = []
var _mmi: Array[MultiMeshInstance3D] = []
var _xf: Array = []                    # per shape: Array[Transform3D], the transforms as written (the headless
                                       # renderer keeps no MultiMesh data, so tests and tours read these)
var _alloc: PackedInt32Array = PackedInt32Array()
var _frame := 0
var _local_clock := 0.0
var _child_lap := {}                   # gondola -> the lap in which a child was last aboard
var _last_t := -INF
var _last_riders := ""
var _built := false
var _zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -50.0, 0.0))
## The weather (tests): {"weather": int (CityMap.WEATHERS), "since": float, "prev": Vector3 mix}; null reads City.
var weather_override: Variant = null
var spots: Array = []                  # every cover stand spot: {"region", "pos": Vector2, "y", "cover", "shop"}
var _wkey := ""
var _held := {}                        # spot -> static person id (assigned at build)
var _tmp_a := Pose.new()
var _tmp_b := Pose.new()
static var _rects: Array[Rect2] = []   # ground obstacles grown by the body radius (walker legs to cover)
static var _circs := PackedVector3Array()
static var _exits := {}                # Vector2i(loop, spot) -> {"arc": float, "leg": PackedVector2Array}


class Pose:
	var hip := 0.86
	var off := Vector3.ZERO      # pelvis offset (local)
	var yaw := 0.0               # pelvis yaw
	var sway := 0.0              # pelvis roll
	var lean := 0.0              # torso pitch forward
	var twist := 0.0             # torso yaw
	var side := 0.0              # torso roll
	var head := Vector3.ZERO     # pitch (down +), yaw, roll
	var arm_ik: Array[bool] = [false, false]
	var arm := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])     # fk (pitch fwd, roll out, elbow) | ik target
	var pole := PackedVector3Array([Vector3(0, -1, -0.3), Vector3(0, -1, -0.3)])
	var leg_ik: Array[bool] = [false, false]
	var leg := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])     # fk (pitch fwd, roll out, knee) | ik ankle target
	var plant := false           # lift or lower the body so the lower foot stands on the floor
	var plant_k := 1.0           # how much of that lift applies (standing up from a seat blends it in)
	var ground := 0.0            # that floor's height (local)
	var cross := 0.0             # a seated person's crossed legs (-1..1, the side)
	var umb := 0.0               # the umbrella's opening (0 folded and put away .. 1 open)
	var umb_hand := 1
	var prop_on: Array[int] = [-1, -1]                          # -1 hidden, 0/1 in that hand, 2 placed (local)
	var prop_xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
	var prop_home: Array[bool] = [false, false]                 # placed at the person's home (a cup left on the table)

	func reset() -> void:
		hip = HIP_STAND
		off = Vector3.ZERO
		yaw = 0.0
		sway = 0.0
		lean = 0.0
		twist = 0.0
		side = 0.0
		head = Vector3.ZERO
		arm_ik[0] = false
		arm_ik[1] = false
		arm[0] = Vector3(0.0, 0.08, 0.15)
		arm[1] = Vector3(0.0, 0.08, 0.15)
		pole[0] = Vector3(-0.4, -1.0, -0.5)
		pole[1] = Vector3(0.4, -1.0, -0.5)
		leg_ik[0] = false
		leg_ik[1] = false
		leg[0] = Vector3.ZERO
		leg[1] = Vector3.ZERO
		plant = false
		plant_k = 1.0
		ground = 0.0
		cross = 0.0
		umb = 0.0
		prop_on[0] = -1
		prop_on[1] = -1
		prop_home[0] = false
		prop_home[1] = false

	func copy_from(o: Pose) -> void:
		hip = o.hip
		off = o.off
		yaw = o.yaw
		sway = o.sway
		lean = o.lean
		twist = o.twist
		side = o.side
		head = o.head
		for k in 2:
			arm_ik[k] = o.arm_ik[k]
			arm[k] = o.arm[k]
			pole[k] = o.pole[k]
			leg_ik[k] = o.leg_ik[k]
			leg[k] = o.leg[k]
			prop_on[k] = o.prop_on[k]
			prop_xf[k] = o.prop_xf[k]
			prop_home[k] = o.prop_home[k]
		plant = o.plant
		plant_k = o.plant_k
		ground = o.ground
		cross = o.cross
		umb = o.umb
		umb_hand = o.umb_hand


class Person:
	var id := ""
	var kind := 0
	var index := 0
	var action := ""
	var region := "ground"
	var looks: Array = []
	var look: Dictionary = {}
	var look_i := -1
	var seated := false          # the lap rig (legs at rest under a table)
	var legs_still := false      # lower parts written only when the person appears (static people only)
	var fast := false            # posed every frame
	var group := 0
	var root := Transform3D.IDENTITY
	var seat := 0.0              # seat height above the root (m)
	var table := Vector2.ZERO    # (distance ahead to the edge, top height) in m
	var offset := 0.0
	var rate := 1.0
	var slot := 6.0
	var partner_yaw := 0.0       # the partner's direction (local yaw), 0 when none
	var partner_rank := 0        # 0 or 1 in a pair (who speaks first)
	var pair_seed := 0
	var has_partner := false
	var s := 1.0                 # body scale
	var sd := 0
	var wphase := 0.0            # a walker's stride phase (0..1) this frame
	var slots := PackedInt32Array()
	var hair_part := {}          # hair style -> part index
	var shown := false
	var pose := Pose.new()
	var world := Transform3D.IDENTITY   # the last root * scale drawn
	var home_world := Transform3D.IDENTITY   # where its activity is, scaled (a cup left there stays there)
	# rain (r3)
	var react := false           # outdoors and not under cover: reacts to rain
	var umbrella := false        # opens an umbrella and carries on (else takes cover)
	var legs_seat := false       # seated on the legs rig (gets up in the rain)
	var spot := -1               # its cover stand spot (index into the node's spots)
	var base := PackedVector3Array()      # its path, home end first, cover spot last (world)
	var base_len := PackedFloat32Array()  # cumulative lengths
	var base_reg := PackedStringArray()   # the region of each point
	var lane_e := 0.0            # walkers: the path length along their lane (then the leg off it)
	var lam_d := 0.0             # walkers: lane time at the path's start; carousel riders: the departure time
	var lane_dir := 1.0          # walkers: +1 along their lane's direction, -1 against it
	var lane_speed := 1.0
	var ph_d := 0.0              # the stride phase at the path's start
	var rec := {}                # the current weather phase (see _begin)
	var umb_hand := 1            # the hand that holds the umbrella

	func tau(t: float) -> float:
		return t * rate + offset


# ===================================================================== setup

## Builds every person and the MultiMeshes. `cw` is the city world (view_time, riders, rider_transform...).
func setup(cw: Node3D) -> void:
	city_world = cw
	if _built:
		return
	_built = true
	_make_people()
	_make_meshes()
	pose_at(_now())


func _make_people() -> void:
	for e: Dictionary in Data.PEOPLE:
		var p := Person.new()
		p.id = String(e["id"])
		p.kind = K_STATIC
		p.action = String(e["action"])
		p.region = String(e["region"])
		p.looks = [e["look"]]
		var pose := String(e["pose"])
		var pos: Vector2 = e["pos"]
		var y := Data.floor_y(p.region)
		var yo := float(e["y_offset"])
		if pose in ["stand", "run", "stretch"]:
			y += yo
		else:
			p.seat = yo
		p.root = Transform3D(Basis(Vector3.UP, float(e["ry"])), Vector3(pos.x, y, pos.y))
		p.table = e["table"]
		p.seated = p.action in Data.SEATED_ACTIONS
		p.legs_still = p.seated or p.action in ["serve_counter", "wipe_counter", "browse", "carry_bag", "cook"]
		p.fast = p.action in ["run", "cycle", "row", "stretch", "lift", "wait_tables"]
		_add_timing(p)
		people.append(p)
	# partners: the nearest other seated person at the same table (within 2.2 m on the same region)
	for p: Person in people:
		if not p.seated:
			continue
		var best: Person = null
		var bd := 2.2
		for q: Person in people:
			if q == p or not q.seated or q.region != p.region:
				continue
			var d := p.root.origin.distance_to(q.root.origin)
			if d < bd:
				bd = d
				best = q
		if best != null:
			var rel := p.root.affine_inverse() * best.root.origin
			p.partner_yaw = atan2(rel.x, rel.z)
			p.has_partner = true
			p.partner_rank = 0 if p.id < best.id else 1
			p.pair_seed = Data.seed_of(p.id + best.id if p.id < best.id else best.id + p.id)
	for i in Data.WALKER_LOOKS.size():
		var p := Person.new()
		p.id = "walker_%d" % i
		p.kind = K_WALKER
		p.index = i
		p.action = "walk"
		p.looks = [(Data.WALKER_LOOKS[i] as Dictionary)["look"]]
		p.fast = true
		_add_timing(p)
		people.append(p)
	for sl: Dictionary in Data.FERRIS_SLOTS:
		var p := Person.new()
		p.id = "ferris_%d" % int(sl["slot"])
		p.kind = K_FERRIS
		p.index = int(sl["slot"])
		p.action = "sit_ride"
		for l: Dictionary in sl["looks"]:
			p.looks.append(l["look"])
		p.seated = true
		p.fast = true
		p.seat = BENCH_Y
		_add_timing(p)
		people.append(p)
	for c: Dictionary in Data.CAROUSEL_RIDERS:
		var p := Person.new()
		p.id = String(c["id"])
		p.kind = K_CAROUSEL
		p.index = int(c["horse"])
		p.action = "sit_ride"
		p.looks = [c["look"]]
		p.fast = true
		p.seat = SADDLE_UP
		_add_timing(p)
		people.append(p)
	_setup_weather()
	var k := 0
	for p: Person in people:
		if not p.fast:
			p.group = k % SLOW_GROUPS
			k += 1


func _add_timing(p: Person) -> void:
	var tm := Data.timing(p.id)
	p.offset = float(tm["offset"])
	p.rate = float(tm["rate"])
	p.slot = float(tm["slot"])
	p.sd = Data.seed_of(p.id)


## The part shapes a person needs over all its looks, then one instance per part.
func _make_meshes() -> void:
	_alloc.resize(M_COUNT)
	_alloc.fill(0)
	for p: Person in people:
		p.slots.resize(P_COUNT)
		p.slots.fill(-1)
		var need := {P_TORSO: M_BOX, P_HEAD: M_HEAD, P_UARM0: M_LIMB, P_UARM1: M_LIMB, P_FARM0: M_LIMB, P_FARM1: M_LIMB,
			P_HAND0: M_BLOCK, P_HAND1: M_BLOCK}
		if p.seated:
			need[P_LAP] = M_BOX
			need[P_SHINS] = M_BLOCK
			need[P_SHOES] = M_BLOCK
		else:
			for part: int in [P_PELVIS]:
				need[part] = M_BOX
			for part: int in [P_THIGH0, P_THIGH1, P_SHIN0, P_SHIN1]:
				need[part] = M_LIMB
			need[P_SHOE0] = M_BLOCK
			need[P_SHOE1] = M_BLOCK
		var hk := 0
		for l: Dictionary in p.looks:
			var top := String(l["top"])
			var acc := String(l["accessory"])
			if top == "dress" and not p.seated:
				need[P_SKIRT] = M_SKIRT
			if top == "apron" or (top == "uniform" and l["top_color"] != Data.WHITE):
				need[P_APRON] = M_BLOCK
			if top == "jacket":
				need[P_FRONT] = M_BLOCK
			if acc == "glasses":
				need[P_GLASSES] = M_BLOCK
			if acc == "beard":
				need[P_BEARD] = M_BLOCK
			if acc == "bag" and not p.seated:
				need[P_BAG] = M_BLOCK
			if acc == "scarf":
				need[P_SCARF] = M_BLOCK
			var hs := String(l["hair_style"])
			if HAIR_MESH.has(hs) and not p.hair_part.has(hs) and hk < 3:
				p.hair_part[hs] = P_HAIR0 + hk
				need[P_HAIR0 + hk] = HAIR_MESH[hs]
				hk += 1
		for n: int in _props_of(p.action):
			need[P_PROP_A + n] = M_BLOCK
		if p.umbrella:
			need[P_UMBRELLA] = M_UMBRELLA
		for part: int in need:
			var m: int = need[part]
			p.slots[part] = (m << 16) | _alloc[m]
			_alloc[m] += 1
	var mat := PropsCity.material()
	for m in M_COUNT:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _shape(m)
		mm.instance_count = _alloc[m]
		if "custom_aabb" in mm:
			mm.custom_aabb = AABB(Vector3(-40.0, -60.0, -32.0), Vector3(80.0, 85.0, 64.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = MESH_NAMES[m]
		mi.multimesh = mm
		mi.material_override = mat
		add_child(mi)
		_mm.append(mm)
		_mmi.append(mi)
		var list: Array[Transform3D] = []
		list.resize(mm.instance_count)
		list.fill(_zero)
		_xf.append(list)
		for i in mm.instance_count:
			mm.set_instance_transform(i, _zero)
	for p: Person in people:
		_set_look(p, 0)


## How many held or placed things an action uses (prop slots A, B).
static func _props_of(action: String) -> Array[int]:
	match action:
		"type", "read_screen", "chat", "eat", "phone", "cook", "wait_tables", "lift":
			return [0, 1]
		"drink", "serve_counter", "wipe_counter", "browse", "carry_bag", "row":
			return [0]
	return []


# ===================================================================== looks and colours

func _set_look(p: Person, i: int) -> void:
	if p.look_i == i:
		return
	p.look_i = i
	p.look = p.looks[clampi(i, 0, p.looks.size() - 1)]
	var l := p.look
	p.s = float(l["scale"])
	var skin: Color = l["skin"]
	var top: Color = l["top_color"]
	var bottom: Color = l["bottom_color"]
	var kind := String(l["top"])
	var long_sleeves := kind in ["shirt", "jacket", "uniform"]
	var bare_legs := kind == "dress" or kind == "sports"
	_col(p, P_TORSO, top)
	_col(p, P_HEAD, skin)
	_col(p, P_UARM0, top)
	_col(p, P_UARM1, top)
	_col(p, P_FARM0, top if long_sleeves else skin)
	_col(p, P_FARM1, top if long_sleeves else skin)
	_col(p, P_HAND0, skin)
	_col(p, P_HAND1, skin)
	_col(p, P_PELVIS, top if kind == "dress" else bottom)
	_col(p, P_THIGH0, skin if kind == "dress" else bottom)
	_col(p, P_THIGH1, skin if kind == "dress" else bottom)
	_col(p, P_SHIN0, skin if bare_legs else bottom)
	_col(p, P_SHIN1, skin if bare_legs else bottom)
	_col(p, P_SHOE0, l["shoes"])
	_col(p, P_SHOE1, l["shoes"])
	_col(p, P_LAP, top if kind == "dress" else bottom)
	_col(p, P_SHINS, skin if bare_legs else bottom)
	_col(p, P_SHOES, l["shoes"])
	_col(p, P_SKIRT, top)
	_col(p, P_APRON, l["accent"])
	_col(p, P_FRONT, Data.WHITE if top != Data.WHITE else Color("#bfe4ff"))
	_col(p, P_GLASSES, Color("#2f2c2a"))
	_col(p, P_BEARD, l["hair_color"])
	_col(p, P_BAG, l["accent"])
	_col(p, P_SCARF, l["accent"])
	for hs: String in p.hair_part:
		_col(p, int(p.hair_part[hs]), l["hair_color"])
	var pa := Color("#ffffff")
	var pb := Color("#ffffff")
	match p.action:
		"phone": pa = Color("#2f2c2a")
		"eat": pa = Color("#e8b06a")
		"cook":
			pa = Color("#3a3f47")
			pb = Color("#f2c94c")
		"wait_tables":
			pa = Color("#dde2e8")
			pb = Color("#ffffff")
		"serve_counter", "browse", "carry_bag":
			pa = Data.TOP_COLORS[(Data.seed_of(p.id) % Data.TOP_COLORS.size())]
		"wipe_counter": pa = Color("#bfe4ff")
		"row", "lift":
			pa = Color("#3a3f47")
			pb = Color("#3a3f47")
	if p.action in ["type", "read_screen", "chat", "eat"]:
		pb = Color("#ffffff") if Data.hash01(Data.seed_of(p.id), 7) < 0.5 else Color("#ffc7a6")
	if p.action == "drink":
		pa = Color("#ffffff") if Data.hash01(Data.seed_of(p.id), 7) < 0.5 else Color("#bfe4ff")
	_col(p, P_PROP_A, pa)
	_col(p, P_PROP_B, pb)
	_col(p, P_UMBRELLA, UMBRELLA_COLORS[p.sd % UMBRELLA_COLORS.size()])
	p.shown = false     # rewrite every part (the visible set may change with the look)


func _col(p: Person, part: int, c: Color) -> void:
	var sl := p.slots[part]
	if sl >= 0:
		_mm[sl >> 16].set_instance_color(sl & 0xFFFF, c)


## Whether a part shows for the current look.
func _part_on(p: Person, part: int) -> bool:
	var l := p.look
	var kind := String(l["top"])
	var acc := String(l["accessory"])
	match part:
		P_SKIRT: return kind == "dress"
		P_APRON: return kind == "apron" or (kind == "uniform" and l["top_color"] != Data.WHITE)
		P_FRONT: return kind == "jacket"
		P_GLASSES: return acc == "glasses"
		P_BEARD: return acc == "beard"
		P_BAG: return acc == "bag"
		P_SCARF: return acc == "scarf"
		P_HAIR0, P_HAIR1, P_HAIR2:
			var hs := String(l["hair_style"])
			return p.hair_part.has(hs) and int(p.hair_part[hs]) == part
	return true


# ===================================================================== the meshes

static func _shape(m: int) -> ArrayMesh:
	var a := PropsCity.acc()
	var w := Color.WHITE
	match m:
		M_BOX:
			a.box(Vector3.ZERO, Vector3.ONE, w, 0.16)
		M_LIMB:
			a.prism(Vector3.ZERO, 0.5 / cos(PI / 8.0), 1.0, w, 8)
		M_BLOCK:
			a.box(Vector3.ZERO, Vector3.ONE, w, 0.0)
		M_HEAD:
			_head_shape(a)
		M_SKIRT:
			_skirt_shape(a)
		M_UMBRELLA:
			_umbrella_shape(a)
		_:
			_hair_shape(a, m)
	return _mesh_of(a)


static func _mesh_of(a: PropsCity.Acc) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a.v
	arrays[Mesh.ARRAY_NORMAL] = a.n
	arrays[Mesh.ARRAY_COLOR] = a.c
	arrays[Mesh.ARRAY_INDEX] = a.idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## The head about its centre (0.33 x 0.35 x 0.31), the face toward +z. White parts take the skin colour;
## the others are shades multiplied into it (dark eyes, rosy cheeks, a little mouth).
static func _head_shape(a: PropsCity.Acc) -> void:
	var w := Color.WHITE
	a.box(Vector3.ZERO, Vector3(0.33, 0.35, 0.31), w, 0.05)
	a.box(Vector3(0, -0.2, -0.01), Vector3(0.13, 0.08, 0.13), Color(0.94, 0.9, 0.88))
	for sx: float in [-1.0, 1.0]:
		a.box(Vector3(sx * 0.075, 0.015, 0.157), Vector3(0.045, 0.06, 0.014), Color(0.12, 0.1, 0.1))
		a.box(Vector3(sx * 0.075, 0.072, 0.157), Vector3(0.07, 0.018, 0.012), Color(0.42, 0.33, 0.3))
		a.box(Vector3(sx * 0.105, -0.045, 0.156), Vector3(0.06, 0.035, 0.01), Color(1.0, 0.7, 0.68))
		a.box(Vector3(sx * 0.172, 0.0, 0.0), Vector3(0.03, 0.08, 0.06), Color(0.95, 0.9, 0.88))
	a.box(Vector3(0, -0.015, 0.165), Vector3(0.045, 0.055, 0.03), Color(0.93, 0.86, 0.83))
	a.box(Vector3(0, -0.088, 0.157), Vector3(0.07, 0.016, 0.01), Color(0.6, 0.28, 0.28))


## A flared skirt from the waist (y 0) to above the knee (y -0.44).
static func _skirt_shape(a: PropsCity.Acc) -> void:
	var w := Color.WHITE
	var t := Vector2(0.19, 0.135)
	var b := Vector2(0.27, 0.2)
	var y0 := 0.0
	var y1 := -0.44
	var top: Array[Vector3] = [Vector3(-t.x, y0, -t.y), Vector3(t.x, y0, -t.y), Vector3(t.x, y0, t.y), Vector3(-t.x, y0, t.y)]
	var bot: Array[Vector3] = [Vector3(-b.x, y1, -b.y), Vector3(b.x, y1, -b.y), Vector3(b.x, y1, b.y), Vector3(-b.x, y1, b.y)]
	for i in 4:
		var j := (i + 1) % 4
		var quad: Array[Vector3] = [top[i], top[j], bot[j], bot[i]]
		var mid := (top[i] + top[j] + bot[i] + bot[j]) * 0.25
		var nn := Vector3(mid.x, 0.0, mid.z).normalized()
		nn = (nn + Vector3(0, 0.25, 0)).normalized()
		a.poly(quad, nn, w)
	var cap: Array[Vector3] = [top[0], top[1], top[2], top[3]]
	a.poly(cap, Vector3.UP, w)
	var floor_q: Array[Vector3] = [bot[3], bot[2], bot[1], bot[0]]
	a.poly(floor_q, Vector3.DOWN, w)
	a.box(Vector3(0, y1 + 0.03, 0), Vector3(b.x * 2.0 + 0.01, 0.05, b.y * 2.0 + 0.01), Color(0.88, 0.88, 0.88))


## An umbrella from the hand (y 0) up: a shaft, an eight-panel canopy 0.55 m round (white panels take the
## instance colour, the ribs and shaft are darker) and a tip.
static func _umbrella_shape(a: PropsCity.Acc) -> void:
	var w := Color.WHITE
	var dark := Color(0.3, 0.3, 0.32)
	a.box(Vector3(0, 0.45, 0), Vector3(0.025, 0.95, 0.025), dark)
	a.box(Vector3(0, -0.03, 0.03), Vector3(0.025, 0.04, 0.08), dark)
	var r := 0.55
	var rim := 0.82
	var apex := Vector3(0, 1.0, 0)
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var a1 := TAU * float(i + 1) / 8.0
		var p0 := Vector3(cos(a0) * r, rim, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, rim, sin(a1) * r)
		var c := w if i % 2 == 0 else Color(0.93, 0.93, 0.93)
		var nn := (p1 - apex).cross(p0 - apex).normalized()
		var tri: Array[Vector3] = [apex, p1, p0]
		a.poly(tri, nn, c)
		var under: Array[Vector3] = [apex, p0, p1]
		a.poly(under, -nn, Color(0.8, 0.8, 0.8))
	a.box(Vector3(0, 1.03, 0), Vector3(0.04, 0.07, 0.04), dark)


## Hair about the head's centre (the head's half sizes are 0.165, 0.175, 0.155).
static func _hair_shape(a: PropsCity.Acc, m: int) -> void:
	var w := Color.WHITE
	var top_cap := func(h: float) -> void:
		a.box(Vector3(0, 0.185, -0.01), Vector3(0.355, h, 0.335), w, 0.03)
	match m:
		M_HAIR_SHORT:
			top_cap.call(0.075)
			a.box(Vector3(0, 0.07, -0.168), Vector3(0.355, 0.24, 0.05), w, 0.02)
			for sx: float in [-1.0, 1.0]:
				a.box(Vector3(sx * 0.174, 0.085, -0.05), Vector3(0.03, 0.15, 0.2), w)
			a.box(Vector3(0.04, 0.15, 0.158), Vector3(0.24, 0.05, 0.03), w)
		M_HAIR_LONG:
			top_cap.call(0.08)
			a.box(Vector3(0, -0.07, -0.172), Vector3(0.38, 0.52, 0.06), w, 0.02)
			for sx: float in [-1.0, 1.0]:
				a.box(Vector3(sx * 0.18, -0.03, -0.03), Vector3(0.04, 0.44, 0.24), w, 0.015)
			a.box(Vector3(0.05, 0.15, 0.158), Vector3(0.26, 0.06, 0.03), w)
			a.box(Vector3(-0.12, 0.12, 0.158), Vector3(0.08, 0.1, 0.03), w)
		M_HAIR_BUN:
			top_cap.call(0.07)
			a.box(Vector3(0, 0.06, -0.168), Vector3(0.355, 0.27, 0.05), w, 0.02)
			for sx: float in [-1.0, 1.0]:
				a.box(Vector3(sx * 0.174, 0.09, -0.04), Vector3(0.03, 0.14, 0.2), w)
			a.box(Vector3(0, 0.275, -0.07), Vector3(0.16, 0.14, 0.16), w, 0.03)
			a.box(Vector3(0, 0.15, 0.158), Vector3(0.3, 0.04, 0.03), w)
		M_HAIR_PONY:
			top_cap.call(0.075)
			a.box(Vector3(0, 0.06, -0.168), Vector3(0.355, 0.27, 0.05), w, 0.02)
			for sx: float in [-1.0, 1.0]:
				a.box(Vector3(sx * 0.174, 0.08, -0.04), Vector3(0.03, 0.17, 0.2), w)
			a.box(Vector3(0, 0.12, -0.205), Vector3(0.08, 0.07, 0.06), Color(0.85, 0.85, 0.85))
			a.box(Vector3(0, -0.06, -0.225), Vector3(0.1, 0.32, 0.08), w, 0.02, Basis(Vector3.RIGHT, 0.18))
			a.box(Vector3(-0.03, 0.15, 0.158), Vector3(0.26, 0.05, 0.03), w)
		M_HAIR_CURLY:
			a.box(Vector3(0, 0.17, -0.02), Vector3(0.34, 0.06, 0.32), w)
			for ix in 3:
				for iz in 3:
					var x := (float(ix) - 1.0) * 0.12
					var z := (float(iz) - 1.0) * 0.115 - 0.01
					a.box(Vector3(x, 0.215 + 0.015 * float((ix + iz) % 2), z), Vector3(0.13, 0.12, 0.13), w)
			for sx: float in [-1.0, 1.0]:
				for iy in 2:
					a.box(Vector3(sx * 0.18, 0.12 - float(iy) * 0.11, -0.06), Vector3(0.08, 0.12, 0.17), w)
			for ix in 3:
				a.box(Vector3((float(ix) - 1.0) * 0.12, 0.08, -0.18), Vector3(0.13, 0.2, 0.08), w)
		M_HAIR_CAP:
			a.box(Vector3(0, 0.2, -0.01), Vector3(0.36, 0.13, 0.34), w, 0.04)
			a.box(Vector3(0, 0.145, 0.22), Vector3(0.3, 0.03, 0.15), Color(0.86, 0.86, 0.86))
			a.box(Vector3(0, 0.275, -0.01), Vector3(0.05, 0.03, 0.05), Color(0.8, 0.8, 0.8))
			a.box(Vector3(0, 0.06, -0.165), Vector3(0.3, 0.12, 0.04), Color(0.55, 0.45, 0.4))


# ===================================================================== the clock and the riders

func _now() -> float:
	if time_override >= 0.0:
		return time_override
	if city_world != null and city_world.has_method("view_time"):
		return float(city_world.call("view_time"))
	var city := get_node_or_null("/root/City") if is_inside_tree() else null
	if city != null and city.has_method("est_time"):
		return float(city.call("est_time"))
	return _local_clock


func _riders() -> Dictionary:
	if riders_override != null:
		return riders_override as Dictionary
	if city_world != null and "riders" in city_world:
		var r: Variant = city_world.get("riders")
		if r is Dictionary:
			return r as Dictionary
	return {}


## The wheel's angle at a time (the world's when it has it; else CityRules' gondola 0, the same thing).
func _ferris_angle(t: float) -> float:
	if city_world != null and city_world.has_method("ferris_angle_at"):
		return float(city_world.call("ferris_angle_at", t))
	return CityRules.gondola_angle(0, t)


func _rider_xf(g: int, angle: float, seat: int) -> Transform3D:
	if city_world != null and city_world.has_method("rider_transform"):
		var xf: Transform3D = city_world.call("rider_transform", g, angle, seat)
		return xf
	# fallback: CityWorld's convention (gondola 0 at the bottom at angle 0, riders facing across)
	var f: Dictionary = CityMap.FERRIS
	var hub: Vector3 = f["hub"]
	var a := -PI * 0.5 + angle + TAU * float(g) / float(f["gondolas"])
	var gp := hub + Vector3(cos(a), sin(a), 0.0) * float(f["radius"])
	var sx := -0.5 if seat % 2 == 0 else 0.5
	return Transform3D(Basis(Vector3.UP, PI * 0.5 if seat % 2 == 0 else -PI * 0.5), gp + Vector3(sx, -float(f["hang"]), 0.0))


func _carousel_xf(horse: int, t: float) -> Transform3D:
	if city_world != null and city_world.has_method("carousel_seat_transform"):
		var xf: Transform3D = city_world.call("carousel_seat_transform", horse, t)
		return xf
	var c: Dictionary = CityMap.CAROUSEL
	var centre: Vector2 = c["center"]
	var phi := TAU * float(horse) / float(c["horses"]) + TAU * fposmod(t / float(c["period"]), 1.0)
	var bob := float(c["bob"]) * 0.5 * (1.0 - cos(TAU * t / float(c["bob_period"]) + float(horse) * PI * 0.5))
	var p := Vector3(centre.x + cos(phi) * 1.75, 0.3 + bob + 1.0, centre.y - sin(phi) * 1.75)
	return Transform3D(Basis(Vector3.UP, atan2(-sin(phi), -cos(phi))), p)


# ===================================================================== visibility

## The regions whose storeys the cutaway hides: the people there hide with them (the owner calls this
## alongside the cutaway; an empty list shows everyone).
func set_hidden_regions(regions: Array) -> void:
	hidden_regions = {}
	for r: Variant in regions:
		hidden_regions[str(r)] = true
	_last_t = -INF


## Which Ferris slots ride now and in which gondola and seat: {slot: [gondola, seat, variant]}. A gondola
## with a child aboard, or that had one since its last bottom pass, carries none.
func ferris_now(t: float) -> Dictionary:
	var rs := _riders()
	var busy := {}
	for g: Variant in rs:
		var list: Variant = rs[g]
		if list is Array and not (list as Array).is_empty():
			busy[int(g)] = true
			_child_lap[int(g)] = Data.gondola_lap(int(g), t)
	var out := {}
	for r: Dictionary in Data.ferris_rides(t):
		var g := int(r["gondola"])
		if busy.has(g) or int(_child_lap.get(g, -999999)) == Data.gondola_lap(g, t):
			continue
		out[int(r["slot"])] = [g, int(r["seat"]), int(r["variant"])]
	return out


# ===================================================================== per frame

func _process(delta: float) -> void:
	if not _built:
		return
	_local_clock += delta
	frame(_now())


## One frame's update: the moving people every frame, the slow ones in alternating halves. Returns the
## number of instance transforms written.
func frame(t: float) -> int:
	_weather_tick(t)
	var key := str(_riders()) + _wkey
	if t == _last_t and key == _last_riders:
		writes_last = 0
		return 0       # paused: nothing moves
	_last_t = t
	_last_riders = key
	_frame += 1
	writes_last = 0
	var fer := ferris_now(t)
	for p: Person in people:
		var stale := p.kind == K_STATIC and hidden_regions.has(p.region) == p.shown
		if p.fast or p.group == _frame % SLOW_GROUPS or not p.shown or stale:
			_update(p, t, fer, false)
	return writes_last


## Poses everybody at time t (deterministic; the tests use it). Returns the transforms written.
func pose_at(t: float) -> int:
	writes_last = 0
	_weather_tick(t)
	var fer := ferris_now(t)
	for p: Person in people:
		_update(p, t, fer, true)
	_last_t = t
	_last_riders = str(_riders()) + _wkey
	return writes_last


## Poses and writes one person; `force` rewrites every part (else the still ones only when they appear).
func _update(p: Person, t: float, fer: Dictionary, force: bool) -> void:
	if p.react:
		_update_react(p, t, force)
		return
	var visible_now := true
	var root := p.root
	match p.kind:
		K_STATIC:
			visible_now = not hidden_regions.has(p.region)
		K_WALKER:
			var w: Dictionary = CityRules.walker_pose(p.index, t)
			var wp: Vector2 = w["pos"]
			p.wphase = float(w.get("phase", fposmod(t * 0.8 + float(p.index) * 0.37, 1.0)))
			root = Transform3D(Basis(Vector3.UP, float(w["ry"])), Vector3(wp.x, 0.0, wp.y))
		K_FERRIS:
			if not fer.has(p.index):
				visible_now = false
			else:
				var f: Array = fer[p.index]
				_set_look(p, int(f[2]))
				root = _rider_xf(int(f[0]), _ferris_angle(t), int(f[1]))
		K_CAROUSEL:
			root = _carousel_xf(p.index, t)
	if not visible_now:
		_hide(p, force)
		return
	var full := force or not p.shown
	var s := p.s
	p.world = Transform3D(root.basis * Basis.from_scale(Vector3(s, s, s)), root.origin)
	p.home_world = p.world
	var po := p.pose
	po.reset()
	_pose(p, t, po)
	_draw(p, po, full)
	p.shown = true


func _hide(p: Person, force: bool) -> void:
	if p.shown or force:
		for part in P_COUNT:
			var sl := p.slots[part]
			if sl >= 0:
				_put(sl, _zero)
		p.shown = false


## A part's instance transform as last written (tests and tours).
func part_transform(p: Person, part: int) -> Transform3D:
	var sl := p.slots[part]
	if sl < 0:
		return _zero
	return (_xf[sl >> 16] as Array[Transform3D])[sl & 0xFFFF]


## Every instance transform as last written, shape by shape (tests: determinism).
func snapshot() -> Array:
	var out: Array = []
	for list: Array[Transform3D] in _xf:
		out.append(list.duplicate())
	return out


## The person with an id (null when none).
func person(id: String) -> Person:
	for p: Person in people:
		if p.id == id:
			return p
	return null


func _put(sl: int, xf: Transform3D) -> void:
	_mm[sl >> 16].set_instance_transform(sl & 0xFFFF, xf)
	(_xf[sl >> 16] as Array[Transform3D])[sl & 0xFFFF] = xf
	writes_last += 1


func _place(p: Person, part: int, local: Transform3D) -> void:
	var sl := p.slots[part]
	if sl < 0:
		return
	if not _part_on(p, part):
		_put(sl, _zero)
		return
	_put(sl, p.world * local)


# ===================================================================== kinematics

## A basis whose y axis runs along `axis` (any length), x and z across it, scaled to size.
static func _along(axis: Vector3, hint: Vector3, size: Vector3) -> Basis:
	var y := axis.normalized()
	var x := hint.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3(1, 0, 0).cross(y) if absf(y.x) < 0.9 else Vector3(0, 0, 1).cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x * size.x, y * size.y, z * size.z)


## Two-bone IK: from joint a toward target, bone lengths l1, l2, the middle joint bending toward `pole`.
## Returns [middle joint, end point].
static func _ik(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> PackedVector3Array:
	var d := target - a
	var dist := clampf(d.length(), 0.02, l1 + l2 - 0.0005)
	var dir := d.normalized() if d.length() > 1e-5 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var p := pole - dir * pole.dot(dir)
	if p.length_squared() < 1e-8:
		p = Vector3(0, 0, 1) - dir * dir.z
	p = p.normalized()
	var mid := a + (dir * cos_a + p * sin_a) * l1
	return PackedVector3Array([mid, a + dir * dist])


## Forward kinematics of a limb hanging down: (pitch forward, roll out, bend) on side sign sg.
## Returns [middle joint, end point]; `bend_back` bends the lower bone backward (a knee) not forward (an elbow).
static func _fk(a: Vector3, base: Basis, ang: Vector3, sg: float, l1: float, l2: float, bend_back: bool) -> PackedVector3Array:
	var r1 := base * Basis(Vector3.BACK, sg * ang.y) * Basis(Vector3.RIGHT, -ang.x)
	var mid := a + r1 * Vector3(0, -l1, 0)
	var r2 := r1 * Basis(Vector3.RIGHT, ang.z if bend_back else -ang.z)
	return PackedVector3Array([mid, mid + r2 * Vector3(0, -l2, 0)])


## The pelvis, torso and head frames (person-local) for a pose.
static func frames(po: Pose) -> Array[Transform3D]:
	var pel := Transform3D(Basis(Vector3.UP, po.yaw) * Basis(Vector3.BACK, po.sway), Vector3(0, po.hip, 0) + po.off)
	var tor := pel * Transform3D(Basis(Vector3.UP, po.twist) * Basis(Vector3.BACK, po.side) * Basis(Vector3.RIGHT, po.lean), Vector3.ZERO)
	var head := tor * Transform3D(Basis(Vector3.UP, po.head.y) * Basis(Vector3.RIGHT, po.head.x) * Basis(Vector3.BACK, po.head.z), Vector3(0, NECK_Y, 0))
	return [pel, tor, head]


## The mouth (person-local) for a pose whose head is already set.
static func mouth(po: Pose) -> Vector3:
	return frames(po)[2] * Vector3(0, HEAD_C - 0.085, 0.2)


func _draw(p: Person, po: Pose, full: bool) -> void:
	var fr := frames(po)
	var female := String(p.look["sex"]) == "f"
	# the legs first: planting the lower foot on the floor lifts or lowers the whole body
	var legs: Array[PackedVector3Array] = []
	if not p.seated:
		for k in 2:
			var sg := -1.0 if k == 0 else 1.0
			var hj := fr[0] * Vector3(sg * HIP_X, 0.0, 0.0)
			var jt: PackedVector3Array
			if po.leg_ik[k]:
				jt = _ik(hj, po.leg[k], THIGH, SHIN, fr[0].basis * Vector3(0.0, 0.25, 1.0))
			else:
				jt = _fk(hj, fr[0].basis, po.leg[k], sg, THIGH, SHIN, true)
			legs.append(PackedVector3Array([hj, jt[0], jt[1]]))
		if po.plant:
			var lift := (po.ground - (minf(legs[0][2].y, legs[1][2].y) - SHOE_H)) * po.plant_k
			var up := Vector3(0, lift, 0)
			for k in 3:
				fr[k] = Transform3D(fr[k].basis, fr[k].origin + up)
			for k in 2:
				for j in 3:
					legs[k][j] += up
	var pel := fr[0]
	var tor := fr[1]
	var head := fr[2]
	var tw := 0.39 if female else 0.44
	# torso and head
	_place(p, P_TORSO, Transform3D(tor.basis * Basis.from_scale(Vector3(tw, TORSO_H, TORSO_D)), tor * Vector3(0, 0.1 + TORSO_H * 0.5, 0)))
	var hc := head * Transform3D(Basis.IDENTITY, Vector3(0, HEAD_C, 0))
	_place(p, P_HEAD, hc)
	for part: int in [P_HAIR0, P_HAIR1, P_HAIR2]:
		_place(p, part, hc)
	_place(p, P_GLASSES, hc * Transform3D(Basis.from_scale(Vector3(0.3, 0.07, 0.02)), Vector3(0, 0.02, 0.168)))
	_place(p, P_BEARD, hc * Transform3D(Basis.from_scale(Vector3(0.3, 0.14, 0.06)), Vector3(0, -0.12, 0.13)))
	_place(p, P_SCARF, tor * Transform3D(Basis.from_scale(Vector3(tw * 0.75, 0.09, TORSO_D + 0.04)), Vector3(0, 0.55, 0.0)))
	_place(p, P_FRONT, tor * Transform3D(Basis.from_scale(Vector3(0.12, TORSO_H * 0.82, 0.02)), Vector3(0, 0.1 + TORSO_H * 0.55, TORSO_D * 0.5 + 0.004)))
	var apron_low := 0.12 if p.seated else 0.38
	_place(p, P_APRON, tor * Transform3D(Basis.from_scale(Vector3(tw * 0.82, TORSO_H * 0.7 + apron_low, 0.025)),
		Vector3(0, 0.1 + TORSO_H * 0.35 - apron_low * 0.5, TORSO_D * 0.5 + 0.012)))
	_place(p, P_BAG, tor * Transform3D(Basis.from_scale(Vector3(0.08, 0.26, 0.24)), Vector3(tw * 0.5 + 0.06, 0.06, 0.02)))
	# arms
	var hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var fwd := tor.basis.z
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var sh := tor * Vector3(sg * (tw * 0.5 + 0.045), SHOULDER_Y, 0.0)
		var jt: PackedVector3Array
		if po.arm_ik[k]:
			jt = _ik(sh, po.arm[k], UARM, FARM + 0.04, po.pole[k])
		else:
			jt = _fk(sh, tor.basis, po.arm[k], sg, UARM, FARM + 0.04, false)
		var lo_axis := jt[0] - jt[1]
		var lo_dir := lo_axis.normalized()
		_place(p, P_UARM0 + k, Transform3D(_along(sh - jt[0], fwd, Vector3(0.115, UARM + 0.04, 0.12)), (sh + jt[0]) * 0.5))
		var wrist := jt[0] - lo_dir * FARM
		_place(p, P_FARM0 + k, Transform3D(_along(lo_axis, fwd, Vector3(0.098, FARM + 0.03, 0.1)), (jt[0] + wrist) * 0.5))
		hands[k] = wrist - lo_dir * 0.05
		_place(p, P_HAND0 + k, Transform3D(_along(lo_axis, fwd, Vector3(0.085, 0.1, 0.075)), hands[k]))
	# legs (a static person's resting legs only when they appear; riders' move with their gondola)
	var still := p.legs_still and p.kind == K_STATIC
	if p.seated:
		# the lap rig is written every update (crossing the legs moves the shins)
		var hip := pel.origin
		var shin_len := clampf(hip.y - 0.06 - SHOE_H - po.ground, 0.18, SHIN)
		var ky := hip.y - 0.05
		var c := po.cross
		var sb := Basis(Vector3.BACK, 0.22 * c) * Basis(Vector3.RIGHT, -0.12 * absf(c))
		var shin_c := Vector3(0.05 * c, ky - shin_len * 0.5 + 0.03 * absf(c), 0.38 + 0.03 * absf(c))
		_place(p, P_LAP, Transform3D(Basis.from_scale(Vector3(0.35, 0.2, 0.5)), Vector3(0, hip.y + 0.02 * absf(c), 0.15)))
		_place(p, P_SHINS, Transform3D(sb * Basis.from_scale(Vector3(0.3, shin_len, 0.12)), shin_c))
		_place(p, P_SHOES, Transform3D(sb * Basis.from_scale(Vector3(0.34, SHOE_H, 0.24)), shin_c + sb * Vector3(0, -shin_len * 0.5 - SHOE_H * 0.5, 0.05)))
	elif full or not still:
		_place(p, P_PELVIS, Transform3D(pel.basis * Basis.from_scale(Vector3(0.35 if female else 0.34, 0.18, 0.23)), pel * Vector3(0, 0.05, 0)))
		_place(p, P_SKIRT, Transform3D(pel.basis, pel * Vector3(0, 0.12, 0)))
		var foot_b := Basis(Vector3.UP, po.yaw)
		for k in 2:
			var hj := legs[k][0]
			var kn := legs[k][1]
			var an := legs[k][2]
			_place(p, P_THIGH0 + k, Transform3D(_along(hj - kn, fwd, Vector3(0.155, THIGH + 0.03, 0.16)), (hj + kn) * 0.5))
			_place(p, P_SHIN0 + k, Transform3D(_along(kn - an, fwd, Vector3(0.13, SHIN, 0.135)), (kn + an) * 0.5))
			_place(p, P_SHOE0 + k, Transform3D(foot_b * Basis.from_scale(Vector3(0.13, SHOE_H, 0.25)), an + foot_b * Vector3(0, -SHOE_H * 0.5, 0.05)))
	# held and placed things (held ones stay upright, facing the way the body faces)
	var upright := Basis(Vector3.UP, po.yaw + po.twist)
	for k in 2:
		var on := po.prop_on[k]
		var part := P_PROP_A + k
		if p.slots[part] < 0:
			continue
		if on < 0:
			_put(p.slots[part], _zero)
		elif on == 2 and po.prop_home[k]:
			_put(p.slots[part], p.home_world * po.prop_xf[k])
		elif on == 2:
			_place(p, part, po.prop_xf[k])
		else:
			_place(p, part, Transform3D(upright, hands[on]) * po.prop_xf[k])
	# the umbrella in its hand, opening (wider) and folding (narrower), gone when put away
	if p.slots[P_UMBRELLA] >= 0:
		if po.umb <= 0.0:
			_put(p.slots[P_UMBRELLA], _zero)
		else:
			var f := _smooth(po.umb / 0.15)
			var rs := (0.18 + 0.82 * _smooth(po.umb)) * f
			_place(p, P_UMBRELLA, Transform3D(upright * Basis.from_scale(Vector3(rs, f, rs)), hands[po.umb_hand] + Vector3(0, -0.02, 0)))


# ===================================================================== animation

static func _smooth(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## An eased bump over u in [0, 1]: rises over `a`, holds, falls over `b` (0 outside).
static func _bump(u: float, a: float, b: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	return minf(_smooth(u / a), _smooth((1.0 - u) / b))


## The idle event at personal time tau: [envelope 0..1, u 0..1 inside it, kind 0..1]. One event of `dur`
## seconds in every slot of the person's own length (4 to 9 s), at a varied place in it.
static func _event(p: Person, tau: float, dur: float, salt: int) -> Vector3:
	var k := floori(tau / p.slot)
	var sd := p.sd + salt
	var start := float(k) * p.slot + Data.hash01(sd, k) * maxf(0.0, p.slot - dur)
	var u := (tau - start) / dur
	if u < 0.0 or u > 1.0:
		return Vector3(0.0, -1.0, Data.hash01(sd + 1, k))
	return Vector3(_bump(u, 0.25, 0.25), u, Data.hash01(sd + 1, k))


## The phase (0..1) of a person's main action cycle at time t (the tests check nobody is in sync).
func phase_of(p: Person, t: float) -> float:
	if p.kind == K_WALKER:
		return float(CityRules.walker_pose(p.index, t).get("phase", 0.0))
	return fposmod(p.tau(t) / _period(p.action), 1.0)


static func _period(action: String) -> float:
	match action:
		"run": return 0.72
		"cycle": return 0.8
		"row": return 3.0
		"stretch": return 18.0
		"lift": return 2.6
		"wipe_counter": return 1.3
		"cook": return 1.7
		"type": return 0.28
		"wait_tables": return 14.0
	return 4.0


func _pose(p: Person, t: float, po: Pose) -> void:
	var tau := p.tau(t)
	var inv := 1.0 / p.s
	if p.seated or p.legs_seat or p.action in ["cycle", "row"] or p.kind == K_CAROUSEL:
		po.hip = p.seat * inv + SIT_HIP
	# breathing for everybody
	po.off.y += 0.006 * sin(tau * TAU / 3.7)
	match p.action:
		"walk": _walk(p, t, po)
		"type", "read_screen", "phone", "eat", "chat", "drink":
			_seated(p, t, tau, po, inv)
			_posture(p, tau, po)
		"sit_ride": _ride(p, tau, po)
		"cook": _cook(p, tau, po, inv)
		"wait_tables": _waiter(p, tau, po)
		"serve_counter", "wipe_counter": _staff(p, tau, po, inv)
		"browse", "carry_bag": _customer(p, tau, po, inv)
		"run": _run(p, tau, po)
		"cycle": _cycle(p, tau, po, inv)
		"row": _row(p, tau, po, inv)
		"stretch": _stretch(p, tau, po)
		"lift": _lift(p, tau, po)


## Arms hanging relaxed, legs straight, feet on the floor.
static func _stand(po: Pose) -> void:
	po.plant = true
	po.leg[0] = Vector3(0.0, 0.03, 0.04)
	po.leg[1] = Vector3(0.0, 0.03, 0.04)


static func _ik_arm(po: Pose, k: int, target: Vector3, pole: Vector3) -> void:
	po.arm_ik[k] = true
	po.arm[k] = target
	po.pole[k] = pole


func _walk(p: Person, t: float, po: Pose) -> void:
	_walk_cycle(po, p.wphase, false)
	var ev := _event(p, p.tau(t), 2.4, 11)
	po.head.y += ev.x * (0.55 if ev.z < 0.5 else -0.55)
	po.head.x = 0.04 - ev.x * 0.05


## A walk cycle at a stride phase (0..1): legs swing and bend, each arm swings against the leg on its side,
## the body bobs (the lower foot stays on the floor) and counter-turns. `hurry`: longer strides, more swing.
static func _walk_cycle(po: Pose, phase01: float, hurry: bool) -> void:
	var ph := TAU * phase01
	var sw := sin(ph)
	var amp := 0.53 if hurry else 0.47
	po.plant = true
	po.leg[0] = Vector3(amp * sw, 0.02, 0.08 + 0.8 * pow(maxf(0.0, cos(ph)), 1.5))
	po.leg[1] = Vector3(-amp * sw, 0.02, 0.08 + 0.8 * pow(maxf(0.0, -cos(ph)), 1.5))
	var a0 := -(0.5 if hurry else 0.42) * sw
	po.arm[0] = Vector3(a0, 0.07, 0.25 + (0.6 if hurry else 0.3) * maxf(0.0, a0) + (0.35 if hurry else 0.0))
	po.arm[1] = Vector3(-a0, 0.07, 0.25 + (0.6 if hurry else 0.3) * maxf(0.0, -a0) + (0.35 if hurry else 0.0))
	po.twist = 0.07 * sw
	po.yaw = -0.05 * sw
	po.side = 0.02 * sin(ph * 2.0)
	po.lean = 0.11 if hurry else 0.05
	po.head.y = -0.07 * sw
	po.head.x = 0.04


## The hands' resting places at a table (person-local): [side 0, side 1].
static func _table_hands(p: Person, po: Pose, inv: float) -> Array[Vector3]:
	var d := (p.table.x + 0.12) * inv if p.table.y > 0.0 else 0.3
	var y := (p.table.y + 0.03) * inv if p.table.y > 0.0 else po.hip + 0.05
	return [Vector3(-0.15, y, maxf(d, 0.26)), Vector3(0.15, y, maxf(d, 0.26))]


func _seated(p: Person, t: float, tau: float, po: Pose, inv: float) -> void:
	var rest := _table_hands(p, po, inv)
	var pole0 := Vector3(-0.8, -1.0, -0.4)
	var pole1 := Vector3(0.8, -1.0, -0.4)
	_ik_arm(po, 0, rest[0], pole0)
	_ik_arm(po, 1, rest[1], pole1)
	po.lean = 0.08
	var cup_rest := rest[1] + Vector3(0.06, 0.02, 0.04)
	var has_cup := p.action != "drink"
	match p.action:
		"type":
			po.lean = 0.16
			po.head.x = 0.12
			for k in 2:
				var sg := -1.0 if k == 0 else 1.0
				var tap := maxf(0.0, sin(tau * TAU / _period("type") + float(k) * 2.1)) * 0.014
				po.arm[k] = Vector3(sg * (0.12 + 0.012 * sin(tau * 1.3 + float(k))), rest[k].y + 0.01 + tap, rest[k].z + 0.16 * inv)
			cup_rest = Vector3(0.38, rest[1].y + 0.02, rest[1].z + 0.04)
			var look := _event(p, tau, 2.6, 21)
			if look.z < 0.5:
				po.lean += 0.12 * look.x
				po.head.x -= 0.1 * look.x
			else:
				po.head.y += (0.45 if look.z < 0.75 else -0.45) * look.x
		"read_screen":
			po.lean = -0.04
			po.head.x = 0.06
			po.arm[1] = Vector3(0.24, rest[1].y + 0.005 + 0.006 * sin(tau * 3.1), rest[1].z + 0.04 + 0.02 * sin(tau * 0.9))
			# the other hand under the chin, elbow on the desk
			po.arm[0] = frames(po)[2] * Vector3(-0.04, HEAD_C - 0.17, 0.17)
			po.pole[0] = Vector3(-0.3, -1.0, 0.5)
			po.head.z = 0.08
			po.head.y = 0.1 * sin(tau * 0.31)
			cup_rest = Vector3(0.4, rest[1].y + 0.02, rest[1].z)
		"phone":
			po.head.z = 0.14
			po.head.x = 0.04
			po.arm[0] = frames(po)[2] * Vector3(-0.2, HEAD_C - 0.02, 0.04)
			po.pole[0] = Vector3(-0.6, -1.0, 0.2)
			po.prop_on[0] = 0
			po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.025, 0.14, 0.07)), Vector3(0.03, -0.02, 0.0))
			var nod := 0.07 * sin(tau * TAU / 2.3) * (0.5 + 0.5 * sin(tau * 0.4))
			po.head.x += nod
			var gest := _event(p, tau, 2.0, 31)
			po.arm[1] = rest[1].lerp(Vector3(0.22, po.hip + 0.32, 0.32), gest.x)
		"eat":
			po.lean = 0.14
			po.head.x = 0.16
			var bite := _event(p, tau, 2.2, 41)
			var plate := Vector3(-0.08, rest[0].y + 0.02, rest[0].z + 0.08)
			po.head.x -= 0.18 * bite.x
			var m := mouth(po) + Vector3(0, -0.02, 0.05)
			po.arm[0] = plate.lerp(m, _bump(bite.y, 0.4, 0.4) if bite.y >= 0.0 else 0.0)
			po.prop_on[0] = 0
			po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.06, 0.04, 0.06)), Vector3(0.0, -0.02, 0.06))
		"chat":
			_chat(p, t, tau, po, rest)
		"drink":
			po.prop_on[0] = 1
			po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.08, 0.1, 0.08)), Vector3(0.0, 0.01, 0.05))
			var sip := _event(p, tau, 2.4, 51)
			var u := _bump(sip.y, 0.3, 0.35) if sip.y >= 0.0 else 0.0
			po.head.x -= 0.2 * u
			po.arm[1] = rest[1].lerp(mouth(po) + Vector3(0.03, -0.06, 0.07), u)
			if p.has_partner:
				po.head.y = p.partner_yaw * 0.25 * (0.5 + 0.5 * sin(tau * 0.5))
			var turn := _event(p, tau + 2.1, 1.8, 52)
			po.head.y += (0.5 if turn.z < 0.5 else -0.5) * turn.x * (1.0 - u)
	if has_cup and p.slots[P_PROP_B] >= 0:
		# the cup on the table, lifted to the mouth now and then (every 4 to 9 s, varied)
		var sip := _event(p, tau + 1.3, 3.0, 61) if p.action != "chat" else Vector3(0.0, -1.0, 0.0)
		var cup_xf := Transform3D(Basis.from_scale(Vector3(0.08, 0.1, 0.08)), cup_rest + Vector3(0, 0.05, 0))
		po.prop_on[1] = 2
		po.prop_xf[1] = cup_xf
		po.prop_home[1] = true
		if sip.y >= 0.0 and sip.z < 0.6 and p.action in ["type", "read_screen", "eat"]:
			var reach := _smooth(sip.y / 0.2) * _smooth((1.0 - sip.y) / 0.2)
			var lift := _bump((sip.y - 0.2) / 0.6, 0.35, 0.35)
			po.head.x -= 0.18 * lift
			var m := mouth(po) + Vector3(0.03, -0.06, 0.07)
			var hand := po.arm[1].lerp(cup_rest - Vector3(0.0, 0.0, 0.05), reach).lerp(m, lift)
			po.arm[1] = hand
			if reach > 0.95:
				po.prop_on[1] = 1
				po.prop_home[1] = false
				po.prop_xf[1] = Transform3D(Basis.from_scale(Vector3(0.08, 0.1, 0.08)), Vector3(0.0, 0.01, 0.05))


## Posture now and then (besides the head turns and cup lifts, on its own slot so they interleave): a shift
## of weight, leaning back, crossing the legs.
static func _posture(p: Person, tau: float, po: Pose) -> void:
	if p.legs_seat:
		po.leg[0] = Vector3(1.45, 0.06, 1.5)
		po.leg[1] = Vector3(1.45, 0.06, 1.5)
	var pz := _event(p, tau + 3.7, 3.6, 151)
	if pz.y < 0.0:
		return
	var sg := 1.0 if Data.hash01(p.sd, floori((tau + 3.7) / p.slot) + 9000) < 0.5 else -1.0
	match int(pz.z * 3.0):
		0:
			po.sway += 0.05 * pz.x * sg
			po.off.x += 0.035 * pz.x * sg
		1:
			po.lean -= 0.16 * pz.x
			po.head.x -= 0.05 * pz.x
		_:
			po.cross = pz.x * sg
			if p.legs_seat:
				var k := 0 if sg < 0.0 else 1
				po.leg[k] = Vector3(1.45 + 0.15 * pz.x, 0.06 - 0.32 * pz.x, 1.5 - 0.15 * pz.x)


## Talking at a table: turns toward the partner; the speaker gestures, the listener nods. Who speaks is
## decided on the pair's shared clock, so the two take turns.
func _chat(p: Person, t: float, tau: float, po: Pose, rest: Array[Vector3]) -> void:
	var toward := p.partner_yaw if p.has_partner else 0.0
	po.head.y = clampf(toward, -1.1, 1.1) * 0.7
	po.twist = clampf(toward, -1.1, 1.1) * 0.25
	var turn := floori((t + float(p.pair_seed % 1000) * 0.01) / 3.4)    # the pair's turn on the shared clock
	var speaker := int(Data.hash01(p.pair_seed, turn) * 2.0)
	var speaking := (speaker == p.partner_rank) or not p.has_partner
	if speaking:
		var g := 0.5 + 0.5 * sin(tau * TAU / 1.6)
		po.arm[1] = rest[1].lerp(Vector3(0.24, po.hip + 0.28 + 0.06 * g, 0.34), 0.4 + 0.6 * g)
		po.arm[0] = rest[0].lerp(Vector3(-0.2, po.hip + 0.24, 0.3), 0.5 * (0.5 + 0.5 * sin(tau * TAU / 2.3 + 1.0)))
		po.head.z = 0.05 * sin(tau * 1.7)
		po.head.x = -0.05
	else:
		po.head.x = 0.08 * sin(tau * TAU / 1.1) * maxf(0.0, sin(tau * 0.9))
		po.lean = 0.12
		po.arm[0] = rest[0] + Vector3(0.05, 0.0, -0.02)


func _ride(p: Person, tau: float, po: Pose) -> void:
	var outward := 0.0
	var wave_k := 1
	# toward the default camera (+z in the world): the side to wave on and to look at
	var cam := p.world.basis.inverse() * Vector3(0, 0, 1)
	outward = atan2(cam.x, cam.z)
	wave_k = 1 if cam.x > 0.0 else 0
	if p.kind == K_CAROUSEL:
		po.leg[0] = Vector3(1.3, 0.38, 1.35)
		po.leg[1] = Vector3(1.3, 0.38, 1.35)
		var grip := po.hip + 0.3
		_ik_arm(po, 0, Vector3(-0.07, grip, 0.3), Vector3(-1, -1, -0.3))
		_ik_arm(po, 1, Vector3(0.07, grip, 0.3), Vector3(1, -1, -0.3))
		po.lean = 0.1 + 0.04 * sin(tau * 2.2)
	else:
		_ik_arm(po, 0, Vector3(-0.13, po.hip + 0.04, 0.3), Vector3(-0.8, -1, -0.2))
		_ik_arm(po, 1, Vector3(0.13, po.hip + 0.04, 0.3), Vector3(0.8, -1, -0.2))
		po.lean = -0.05
	var look := _event(p, tau, 3.0, 71)
	po.head.y = clampf(outward, -1.2, 1.2) * 0.6 * look.x + 0.3 * sin(tau * 0.37)
	po.head.x = -0.05 * look.x
	var wave := _event(p, tau + 3.3, 2.6, 72)
	if wave.y >= 0.0 and wave.z < 0.55:
		var sg := -1.0 if wave_k == 0 else 1.0
		var up := Vector3(sg * 0.3, po.hip + 0.85, 0.12 + 0.05 * sin(tau * TAU * 1.6))
		po.arm[wave_k] = po.arm[wave_k].lerp(up + Vector3(sg * 0.06 * sin(tau * TAU * 1.6), 0, 0), wave.x)
		po.pole[wave_k] = Vector3(sg, -0.3, 0.0)
		po.head.y = clampf(outward, -1.2, 1.2) * 0.8 * wave.x + po.head.y * (1.0 - wave.x)


func _cook(p: Person, tau: float, po: Pose, inv: float) -> void:
	_stand(po)
	var top := (p.table.y if p.table.y > 0.0 else 1.06) * inv
	var d := (p.table.x if p.table.y > 0.0 else 0.35) * inv
	var ph := fposmod(tau / _period("cook"), 1.0)
	var toss := pow(maxf(0.0, sin(ph * TAU)), 3.0)
	var pan := Vector3(-0.12, top + 0.14 + 0.05 * toss, d + 0.12 + 0.03 * toss)
	_ik_arm(po, 0, pan, Vector3(-1, -0.6, -0.4))
	po.prop_on[0] = 0
	po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.26, 0.04, 0.26)), Vector3(0.05, 0.0, 0.14))
	# the food flips: up and down over the pan
	var fly := 0.22 * maxf(0.0, sin(fposmod(ph - 0.25, 1.0) * TAU))
	po.prop_on[1] = 2
	po.prop_xf[1] = Transform3D(Basis(Vector3.RIGHT, fly * 9.0) * Basis.from_scale(Vector3(0.12, 0.05, 0.12)), pan + Vector3(0.05, 0.06 + fly, 0.12))
	var shake := 0.03 * sin(tau * TAU * 3.0)
	_ik_arm(po, 1, Vector3(0.2, top + 0.3 + shake, d + 0.18), Vector3(1, -0.6, -0.4))
	po.lean = 0.12
	po.head.x = 0.3
	var ev := _event(p, tau, 2.4, 81)
	if ev.z < 0.5:
		po.twist = 0.5 * ev.x
		po.head.y = 0.4 * ev.x
		po.head.x -= 0.25 * ev.x
	else:
		po.arm[1] = po.arm[1].lerp(Vector3(0.12, top + 0.12, d + 0.4), ev.x)
		po.head.x -= 0.1 * ev.x


func _waiter(p: Person, tau: float, po: Pose) -> void:
	_stand(po)
	# turns slowly between the tables, stepping as it turns
	var turn_ph := tau * TAU / _period("wait_tables")
	po.yaw = 0.75 * sin(turn_ph)
	var turning := absf(cos(turn_ph))
	var step := sin(tau * TAU * 1.5)
	po.leg[0] = Vector3(0.12 * step * turning, 0.03, 0.04 + 0.5 * maxf(0.0, step) * turning)
	po.leg[1] = Vector3(-0.12 * step * turning, 0.03, 0.04 + 0.5 * maxf(0.0, -step) * turning)
	po.twist = 0.1 * sin(turn_ph + 0.6)
	# the tray on the flat hand, a cup on the tray
	var tray := Vector3(-0.28, 1.1, 0.25)
	_ik_arm(po, 0, tray, Vector3(-1, -0.6, -0.5))
	po.prop_on[0] = 0
	po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.38, 0.025, 0.38)), Vector3(0.02, 0.05, 0.04))
	po.prop_on[1] = 0
	po.prop_xf[1] = Transform3D(Basis.from_scale(Vector3(0.08, 0.1, 0.08)), Vector3(0.0, 0.12, 0.06))
	var ev := _event(p, tau, 1.8, 91)
	po.head.x = 0.25 * ev.x * (1.0 if ev.z < 0.6 else 0.0)
	po.arm[1] = Vector3(0.05 + 0.6 * ev.x * (1.0 if ev.z >= 0.6 else 0.3), 0.12, 0.2 + 0.4 * ev.x)
	po.head.y = 0.2 * sin(turn_ph + 0.3)


func _staff(p: Person, tau: float, po: Pose, inv: float) -> void:
	_stand(po)
	var top := (p.table.y if p.table.y > 0.0 else 0.96) * inv
	var d := (p.table.x if p.table.y > 0.0 else 0.4) * inv
	var rest: Array[Vector3] = [Vector3(-0.18, top + 0.02, d + 0.03), Vector3(0.18, top + 0.02, d + 0.03)]
	_ik_arm(po, 0, rest[0], Vector3(-1, -0.8, -0.6))
	_ik_arm(po, 1, rest[1], Vector3(1, -0.8, -0.6))
	po.lean = 0.08
	po.sway = 0.025 * sin(tau * TAU / 7.0)
	po.off.x = 0.02 * sin(tau * TAU / 7.0)
	if p.action == "wipe_counter":
		var w := tau * TAU / _period("wipe_counter")
		po.arm[1] = Vector3(0.05 + 0.13 * cos(w), top + 0.035, d + 0.12 + 0.07 * sin(w))
		po.prop_on[0] = 1
		po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.15, 0.025, 0.11)), Vector3(0.0, -0.05, 0.03))
		po.lean = 0.24
		po.head.x = 0.35
		var ev := _event(p, tau, 2.2, 101)
		po.head.x -= 0.4 * ev.x
		po.head.y = 0.35 * ev.x * (1.0 if ev.z < 0.5 else -1.0)
		po.arm[1] = po.arm[1].lerp(rest[1], 0.7 * ev.x)
		if ev.x > 0.5:
			po.head.x += 0.12 * sin(tau * TAU * 1.4)
	else:
		# hand something over the counter, with a nod; between times look about
		po.head.x = 0.08
		var hand_ev := _event(p, tau, 3.2, 111)
		po.prop_on[0] = -1
		if hand_ev.y >= 0.0:
			var u := hand_ev.y
			var below := Vector3(0.24, top - 0.25, 0.12)
			var over := Vector3(0.1, top + 0.14, d + 0.45)
			var hand := rest[1]
			if u < 0.25:
				hand = rest[1].lerp(below, _smooth(u / 0.25))
			elif u < 0.55:
				hand = below.lerp(over, _smooth((u - 0.25) / 0.3))
			elif u < 0.8:
				hand = over
			else:
				hand = over.lerp(rest[1], _smooth((u - 0.8) / 0.2))
			po.arm[1] = hand
			po.pole[1] = Vector3(1, -0.6, -0.8)
			if u > 0.22 and u < 0.8:
				po.prop_on[0] = 1
				po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.13, 0.11, 0.13)), Vector3(0.0, 0.0, 0.07))
			var nod := _bump((u - 0.55) / 0.3, 0.4, 0.4)
			po.head.x += 0.28 * nod - 0.1 * _bump(u / 0.3, 0.3, 0.3)
			po.lean += 0.12 * _bump((u - 0.4) / 0.45, 0.3, 0.3)
		else:
			po.head.y = 0.3 * sin(tau * 0.45)


func _customer(p: Person, tau: float, po: Pose, inv: float) -> void:
	_stand(po)
	po.sway = 0.03 * sin(tau * TAU / 6.0)
	po.off.x = 0.025 * sin(tau * TAU / 6.0)
	if p.action == "carry_bag":
		po.arm[1] = Vector3(0.08, 0.05, 0.2)
		po.prop_on[0] = 1
		po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.26, 0.3, 0.12)), Vector3(0.0, -0.18, 0.0))
		po.arm[0] = Vector3(0.05, 0.1, 0.25)
		po.head.y = 0.45 * sin(tau * 0.33)
		po.head.x = 0.12
		var bag_ev := _event(p, tau, 2.5, 121)
		if bag_ev.z < 0.5:
			# points at something in the window
			po.lean = 0.2 * bag_ev.x
			po.head.x += 0.25 * bag_ev.x
			_ik_arm(po, 0, Vector3(-0.3, 0.62, 0.05).lerp(Vector3(-0.12, 1.15 * inv, 0.45), bag_ev.x), Vector3(-1, -0.6, -0.4))
		else:
			po.yaw = 0.35 * bag_ev.x
			po.head.y = 0.6 * bag_ev.x
		return
	# browse: scan the shelf, now and then take a thing down, look at it and put it back
	var shelf := (p.table.y if p.table.y > 0.0 else 1.2) * inv
	var d := (p.table.x if p.table.y > 0.0 else 0.4) * inv
	po.head.y = 0.35 * sin(tau * TAU / 7.5)
	po.head.x = 0.1 * sin(tau * TAU / 5.3) - (0.15 if shelf < 1.0 else -0.05)
	po.arm[0] = Vector3(0.08, 0.1, 0.25)
	po.arm[1] = Vector3(0.05, 0.08, 0.2)
	var ev := _event(p, tau, 4.0, 131)
	if ev.y >= 0.0:
		var u := ev.y
		var spot := Vector3(0.18 + 0.15 * (ev.z - 0.5), clampf(shelf + 0.1, 0.9, 1.5), d + 0.08)
		var chest := Vector3(0.06, po.hip + 0.28, 0.32)
		var hang := frames(po)[1] * Vector3(0.27, 0.0, 0.08)
		var hand := hang
		if u < 0.2:
			hand = hang.lerp(spot, _smooth(u / 0.2))
		elif u < 0.35:
			hand = spot.lerp(chest, _smooth((u - 0.2) / 0.15))
		elif u < 0.7:
			hand = chest
		elif u < 0.85:
			hand = chest.lerp(spot, _smooth((u - 0.7) / 0.15))
		else:
			hand = spot.lerp(hang, _smooth((u - 0.85) / 0.15))
		_ik_arm(po, 1, hand, Vector3(1, -0.7, -0.5))
		if u > 0.18 and u < 0.86:
			po.prop_on[0] = 1
			po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.16, 0.2, 0.05)), Vector3(0.0, 0.0, 0.05))
		var look := _bump((u - 0.3) / 0.45, 0.2, 0.2)
		po.head.x = po.head.x * (1.0 - look) + 0.35 * look
		po.head.y *= 1.0 - look
		po.lean = 0.1 * look


func _run(_p: Person, tau: float, po: Pose) -> void:
	po.plant = true
	var ph := tau * TAU / _period("run")
	var sw := sin(ph)
	po.leg[0] = Vector3(0.55 * sw, 0.02, 0.3 + 1.1 * pow(maxf(0.0, cos(ph)), 1.2))
	po.leg[1] = Vector3(-0.55 * sw, 0.02, 0.3 + 1.1 * pow(maxf(0.0, -cos(ph)), 1.2))
	po.arm[0] = Vector3(-0.55 * sw, 0.12, 1.45)
	po.arm[1] = Vector3(0.55 * sw, 0.12, 1.45)
	po.lean = 0.14
	po.twist = 0.1 * sw
	po.off.y += 0.03 * absf(cos(ph))
	po.head.x = -0.08


func _cycle(_p: Person, tau: float, po: Pose, inv: float) -> void:
	# the saddle 0.22 m behind the bike's centre, the bars 0.28 m ahead at 1.0, the cranks at 0.34
	po.off.z = -0.22 * inv
	var th := tau * TAU / _period("cycle")
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var a := th + float(k) * PI
		var pedal := Vector3(sg * 0.11, 0.34 + 0.13 * sin(a), 0.02 + 0.13 * cos(a)) * inv
		po.leg_ik[k] = true
		po.leg[k] = pedal + Vector3(0, SHOE_H * 0.7, -0.04)
		_ik_arm(po, k, Vector3(sg * 0.2, 1.0, 0.28) * inv, Vector3(sg, -1.0, -0.5))
	po.lean = 0.5
	po.head.x = -0.32
	po.sway = 0.03 * sin(th)
	po.twist = 0.04 * sin(th)


func _row(_p: Person, tau: float, po: Pose, inv: float) -> void:
	var u := fposmod(tau / _period("row"), 1.0)
	# the drive (legs push, then the arms pull) and the slower recovery
	var slide := 0.0
	if u < 0.4:
		slide = 1.0 - _smooth(u / 0.4)
	else:
		slide = _smooth((u - 0.4) / 0.6)
	var arms := 1.0 - _smooth((u - 0.2) / 0.2) if u < 0.4 else _smooth((u - 0.5) / 0.25)
	po.off.z = 0.3 * slide * inv
	po.lean = -0.28 + 0.7 * slide
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		po.leg_ik[k] = true
		po.leg[k] = Vector3(sg * 0.11, (0.24 + SHOE_H * 0.7) * inv, 0.72 * inv)
	var chest := Vector3(0.0, po.hip + 0.3, po.off.z + 0.2)
	var reach := Vector3(0.0, 0.48 * inv, 0.7 * inv)
	var handle := chest.lerp(reach, arms)
	_ik_arm(po, 0, handle + Vector3(-0.12, 0, 0), Vector3(-1, -0.5, -0.8))
	_ik_arm(po, 1, handle + Vector3(0.12, 0, 0), Vector3(1, -0.5, -0.8))
	po.prop_on[0] = 2
	po.prop_xf[0] = Transform3D(Basis.from_scale(Vector3(0.42, 0.035, 0.035)), handle + Vector3(0, -0.01, 0.04))
	po.head.x = -0.2 * slide


## A stretching routine on the mat: reach up, bend to each side, fold forward, cross an arm; a key pose
## every few seconds with eased moves between them.
func _stretch(_p: Person, tau: float, po: Pose) -> void:
	_stand(po)
	po.leg[0] = Vector3(0.0, 0.12, 0.03)
	po.leg[1] = Vector3(0.0, 0.12, 0.03)
	var keys := [
		[0.0, 0.0, Vector3(-0.15, 2.05, 0.08), Vector3(0.15, 2.05, 0.08)],
		[0.0, 0.3, Vector3(-0.05, 2.0, 0.05), Vector3(0.3, 1.85, 0.05)],
		[0.0, 0.0, Vector3(-0.15, 2.05, 0.08), Vector3(0.15, 2.05, 0.08)],
		[0.0, -0.3, Vector3(-0.3, 1.85, 0.05), Vector3(0.05, 2.0, 0.05)],
		[1.05, 0.0, Vector3(-0.12, 0.3, 0.3), Vector3(0.12, 0.3, 0.3)],
		[0.05, 0.0, Vector3(0.3, 1.22, 0.12), Vector3(0.1, 1.3, 0.25)],
	]
	var n := keys.size()
	var period := _period("stretch")
	var x := fposmod(tau / period, 1.0) * float(n)
	var i := floori(x)
	var f := x - float(i)
	var b := _smooth((f - 0.55) / 0.45)
	var k0: Array = keys[i % n]
	var k1: Array = keys[(i + 1) % n]
	po.lean = lerpf(float(k0[0]), float(k1[0]), b)
	po.side = lerpf(float(k0[1]), float(k1[1]), b)
	var hold := 0.02 * sin(tau * TAU / 2.2)
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var target := (k0[2 + k] as Vector3).lerp(k1[2 + k] as Vector3, b)
		_ik_arm(po, k, target + Vector3(0, hold, 0), Vector3(sg, -0.2, -0.6))
	po.head.x = 0.4 * po.lean - 0.1
	po.head.z = -0.4 * po.side


func _lift(_p: Person, tau: float, po: Pose) -> void:
	_stand(po)
	po.leg[0] = Vector3(0.0, 0.1, 0.06)
	po.leg[1] = Vector3(0.0, 0.1, 0.06)
	var ph := fposmod(tau / _period("lift"), 1.0)
	for k in 2:
		var u := fposmod(ph + 0.5 * float(k), 1.0)
		var curl := _bump(u / 0.6, 0.45, 0.45)
		po.arm[k] = Vector3(0.12, 0.1, 0.2 + 2.0 * curl)
		po.prop_on[k] = k
		po.prop_xf[k] = Transform3D(Basis.from_scale(Vector3(0.24, 0.08, 0.08)), Vector3(0.0, -0.02, 0.0))
	po.head.x = -0.05


# ===================================================================== rain (city r3)
#
# Each person who reacts has a phase record `rec`, made when the shared weather changes (_begin) from where the
# person is at that moment under the previous record (so a change mid-way never makes anybody jump), and read
# by _eval(t). A person moves along its `base` path: home end first, cover spot last; s is the distance along
# it. In the rain s grows (after the person's group delay, unless it was already on the way); when the rain
# stops it shrinks back. Walkers' paths start where they leave their lane: on the way back they rejoin the lane
# where the path leaves it and walk a little faster (or slower) until they are in step with their lane clock.
# Carousel riders get back on when their horse comes round. Umbrella holders only open and fold an umbrella.

## Who reacts, their umbrellas, the cover spots, and the fixed spots and paths (static people, carousel riders).
func _setup_weather() -> void:
	spots = []
	for c: Dictionary in Data.covers():
		var reg := String(c["region"])
		for q: Vector2 in c["stand"]:
			if _near_child_place(reg, q):
				continue
			var bid := PropsCity.building_at(q) if reg == "ground" else ""
			var shop := bid if bid != "" and bool((CityMap.BUILDINGS[bid] as Dictionary).get("shop", false)) else ""
			spots.append({"region": reg, "pos": q, "y": Data.floor_y(reg), "cover": String(c["id"]), "shop": shop})
	for p: Person in people:
		match p.kind:
			K_STATIC:
				var pos := Vector2(p.root.origin.x, p.root.origin.z)
				p.react = not Data.is_indoor(p.region, pos) and not Data.under_cover(p.region, pos)
				if p.react:
					p.umbrella = p.seated and Data.umbrella_for(p.id)
					if p.seated and not p.umbrella:
						p.seated = false
						p.legs_seat = true
			K_WALKER:
				p.react = true
				p.umbrella = Data.umbrella_for(p.id)
			K_CAROUSEL:
				p.react = true
		if p.react:
			p.fast = true
			p.legs_still = false
			p.umb_hand = 1 if p.kind == K_WALKER or p.action in ["eat", "read_screen", "phone"] else 0
	for p: Person in people:
		if p.react and not p.umbrella and p.kind == K_CAROUSEL:
			_assign_carousel(p)
	for p: Person in people:
		if p.react and not p.umbrella and p.kind == K_STATIC:
			_assign_static(p)
	# the walkers' ways off their lanes, once (so the first shower has nothing to work out)
	var any_walker := false
	for p: Person in people:
		if p.kind == K_WALKER and p.react and not p.umbrella:
			any_walker = true
	if any_walker:
		for li in CityRules.walk_loops().size():
			for j in spots.size():
				if String((spots[j] as Dictionary)["region"]) == "ground" and not _held.has(j):
					_exit(li, j)


## A spot within Data.MIN_CLEAR of a child's place on its region is never used.
static func _near_child_place(region: String, q: Vector2) -> bool:
	for k: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[k]
		if Data.norm_region(String(it["region"])) == region and q.distance_to(it["pos"]) < Data.MIN_CLEAR:
			return true
	return false


## The shared weather: {"rain": bool, "since": float, "prev_rain": bool}. Reads the decoded City states
## ({"weather": int, "since", "prev": Vector3 mix}) or the rules' shape ({"weather": {weather, since, prev}}).
func _weather() -> Dictionary:
	var st: Variant = weather_override
	if st == null and is_inside_tree():
		var city := get_node_or_null("/root/City")
		if city != null and "states" in city:
			st = city.get("states")
	var out := {"rain": false, "since": -1.0e9, "prev_rain": false}
	if not (st is Dictionary) or not (st as Dictionary).has("weather"):
		return out
	var d: Dictionary = st
	var w: Variant = d["weather"]
	if w is Dictionary:
		d = w
		w = d["weather"]
	out["rain"] = int(w) == Data.RAIN
	out["since"] = float(d.get("since", d.get("weather_since", -1.0e9)))
	var prev: Variant = d.get("prev", d.get("weather_prev", Vector3(1, 0, 0)))
	var pr := 0.0
	if prev is Vector3:
		pr = (prev as Vector3).y
	elif prev is Array and (prev as Array).size() > 1:
		pr = float((prev as Array)[1])
	out["prev_rain"] = pr >= 0.5
	return out


## Forget every weather phase (tests; a new city).
func reset_weather() -> void:
	_wkey = ""
	for p: Person in people:
		p.rec = {}


func _weather_tick(_t: float) -> void:
	var w := _weather()
	var since := float(w["since"])
	var key := "%d|%.4f|%d" % [1 if bool(w["rain"]) else 0, since, 1 if bool(w["prev_rain"]) else 0]
	if key == _wkey:
		return
	_wkey = key
	var cur := {}
	for p: Person in people:
		if p.react and not p.rec.is_empty():
			cur[p.id] = _eval(p, since)
	for p: Person in people:
		if p.react:
			_begin(p, w, cur.get(p.id, {}))
	_assign_walkers()


## A walker's lane: [points, total length, its slot's speed].
static func _lane(index: int) -> Array:
	var l: Dictionary = CityRules.walk_loops()[_loop_index(index)]
	return [l["pts"], float(l["length"]), float(l["speed"])]


## The arc along its lane of walker `index`'s slot at lane time lam.
static func _slot_arc(index: int, lam: float) -> float:
	var ln := _lane(index)
	return CityRules.poly_project(ln[0], CityRules.walker_pose(index, lam)["pos"]).x


static func _lane_phase(index: int, lam: float) -> float:
	return float(CityRules.walker_pose(index, lam).get("phase", 0.0))


func _plen(p: Person) -> float:
	return float(p.base_len[p.base_len.size() - 1]) if p.base_len.size() > 0 else 0.0


## A new weather phase for one person, from its state `cur` at the change (empty: no memory).
func _begin(p: Person, w: Dictionary, cur: Dictionary) -> void:
	var rain := bool(w["rain"])
	var since := float(w["since"])
	var has := not cur.is_empty()
	var spread := float(CityMap.RAIN_COVER_SPREAD) if rain else float(CityMap.RAIN_RETURN_SPREAD)
	var rec := {"rain": rain, "since": since}
	if p.umbrella:
		var a0 := float(cur["umb"]) if has else (1.0 if not rain and bool(w["prev_rain"]) else 0.0)
		var rest := a0 <= 0.0 if rain else a0 >= 1.0
		rec["a0"] = a0
		rec["start"] = since + (Data.group_delay(p.id, _pos2(p, since, cur), spread) if rest else 0.0)
		p.rec = rec
		return
	var assumed := not has and not rain and bool(w["prev_rain"])
	var s0 := float(cur["s"]) if has else 0.0
	rec["w0"] = float(cur["walked"]) if has else 0.0
	match p.kind:
		K_WALKER:
			var on_lane := not has or bool(cur["on_lane"])
			var g0 := (float(cur["lam"]) - since) if has and on_lane else 0.0
			rec["g0"] = g0
			rec["pd0"] = float(cur["pd"]) if has else 0.0
			rec["ph0"] = float(cur["ph"]) if has else -1.0
			if (rain and on_lane) or assumed:
				# leaves its lane after its group's delay (at once when it was on its way back; assumed: it left
				# when the rain began, long ago)
				var moving := has and bool(cur.get("moving", false))
				var td := since if assumed or moving else since + Data.group_delay(p.id, _pos2(p, since, cur), spread)
				rec["depart"] = true
				rec["td"] = td
				rec["lam_d"] = td + g0
				rec["assumed"] = assumed
				rec["s0"] = 0.0
				rec["start"] = td
				p.rec = rec
				return
			rec["s0"] = s0 if not on_lane else 0.0
		K_CAROUSEL:
			if (rain and s0 <= 0.0) or assumed:
				var td2 := since if assumed else since + Data.group_delay(p.id, _pos2(p, since, cur), spread)
				p.lam_d = td2
				_carousel_path(p, td2)
				s0 = _plen(p) if assumed else 0.0
				rec["start"] = td2
			rec["s0"] = s0
		_:
			if assumed:
				s0 = _plen(p)
			rec["s0"] = s0
	p.rec = rec
	_timing(p)


## The start time of a record whose path is known, and for a walker going back to its lane, how it meets its
## slot again: from where it steps back onto the lane (or where it is on it), it walks along the lane toward
## its slot (or waits under cover until the slot comes by, when that is about as quick), so that it is in step
## again exactly; then it simply walks on.
func _timing(p: Person) -> void:
	var rec := p.rec
	var since := float(rec["since"])
	var s0 := float(rec["s0"])
	var big := _plen(p)
	var rain := bool(rec["rain"])
	if rain:
		if not rec.has("start"):
			rec["start"] = since + (Data.group_delay(p.id, _pos2(p, since, {}), float(CityMap.RAIN_COVER_SPREAD)) if s0 <= 0.0 else 0.0)
		return
	var start := since
	var at_spot := s0 > 0.0 and s0 >= big - 1e-4
	if at_spot:
		start += Data.group_delay(p.id, _pos2(p, since, {}), float(CityMap.RAIN_RETURN_SPREAD))
	rec["start"] = start
	if p.kind == K_CAROUSEL and s0 > 0.0:
		# back on when the horse comes round to where the rider got off
		var period := float(CityMap.CAROUSEL["period"])
		var earliest := start + s0 / Data.RETURN_SPEED
		var k := ceilf((earliest - p.lam_d) / period - 1e-9)
		rec["start"] = p.lam_d + k * period - s0 / Data.RETURN_SPEED
		return
	if p.kind != K_WALKER:
		return
	var ln := _lane(p.index)
	var total: float = ln[1]
	var v: float = ln[2]
	var vr := Data.LANE_RETURN_SPEED
	var t_r := since
	var a_r := 0.0
	var ph_r := 0.0
	var w_r := float(rec["w0"])
	if s0 > 0.0:
		var flo := minf(s0, p.lane_e)
		t_r = start + (s0 - flo) / Data.RETURN_SPEED
		a_r = fposmod(_slot_arc(p.index, p.lam_d) + p.lane_dir * flo, total)
		w_r += s0 - flo
		ph_r = p.ph_d + w_r / STRIDE
		rec["floor"] = flo
	else:
		var lam0 := since + float(rec["g0"])
		a_r = _slot_arc(p.index, lam0)
		var ph0 := float(rec["ph0"])
		ph_r = ph0 if ph0 >= 0.0 else _lane_phase(p.index, lam0) + float(rec["pd0"])
		rec["floor"] = 0.0
	# the slot is behind it by `ahead` metres along the lane (or ahead of it by total - ahead)
	var ahead := fposmod(a_r - _slot_arc(p.index, t_r), total)
	var g_r := 0.0
	var rate := 0.0
	if ahead > 0.05 and ahead < total - 0.05:
		var t_back := ahead / (vr + v)                                     # walk back to meet it
		var t_fwd := (total - ahead) / (vr - v) if vr > v else INF         # or catch it up
		var t_wait := ahead / v                                            # or wait for it to come by
		if at_spot and t_wait <= minf(t_back, t_fwd) + 8.0:
			rec["start"] = start + t_wait
			t_r += t_wait
		elif t_back <= t_fwd:
			g_r = ahead / v
			rate = -(vr + v) / v
		else:
			g_r = -(total - ahead) / v
			rate = (vr - v) / v
	var t_meet := t_r + (absf(g_r / rate) if rate != 0.0 else 0.0)
	rec["t_r"] = t_r
	rec["g_r"] = g_r
	rec["rate"] = rate
	rec["t_meet"] = t_meet
	rec["ph_r"] = ph_r
	rec["w_r"] = w_r
	var lane_walk := vr * (t_meet - t_r)
	rec["pdb"] = wrapf(ph_r + lane_walk / STRIDE - _lane_phase(p.index, t_meet), -0.5, 0.5)


## Where a person is for its group (the square of ground it starts from).
func _pos2(p: Person, t: float, cur: Dictionary) -> Vector2:
	match p.kind:
		K_WALKER:
			var lam := float(cur["lam"]) if not cur.is_empty() and bool(cur.get("on_lane", true)) else t
			return CityRules.walker_pose(p.index, lam)["pos"]
		K_CAROUSEL:
			return CityMap.CAROUSEL["center"]
	return Vector2(p.root.origin.x, p.root.origin.z)


## The state at time t under the current record: {"s", "on_lane", "lam", "walked", "pd", "umb", "ph" (a walker's
## stride phase), "moving" (a walker on its lane walking to meet its slot), "back" (that walk is against the lane)}.
func _eval(p: Person, t: float) -> Dictionary:
	var rec := p.rec
	var out := {"s": 0.0, "on_lane": true, "lam": t, "walked": 0.0, "pd": 0.0, "umb": 0.0, "ph": -1.0, "moving": false, "back": false}
	if p.kind == K_WALKER:
		out["ph"] = _lane_phase(p.index, t)
	if rec.is_empty():
		return out
	var rain := bool(rec["rain"])
	var since := float(rec["since"])
	var start := float(rec.get("start", since))
	if p.umbrella:
		var a0 := float(rec["a0"])
		var da := maxf(0.0, t - start) / Data.UMBRELLA_TIME
		out["umb"] = minf(1.0, a0 + da) if rain else maxf(0.0, a0 - da)
		return out
	var s0 := float(rec["s0"])
	var big := _plen(p)
	var w0 := float(rec["w0"])
	if p.kind != K_WALKER:
		var sv := minf(big, s0 + maxf(0.0, t - start) * Data.HURRY_SPEED) if rain else maxf(0.0, s0 - maxf(0.0, t - start) * Data.RETURN_SPEED)
		out["s"] = sv
		out["on_lane"] = sv <= 0.0
		out["walked"] = w0 + absf(sv - s0)
		return out
	# walkers
	if rain:
		if (bool(rec.get("depart", false)) and t < start) or big <= 0.0:
			# still in its stride on the lane (a lane time a little off its slot keeps its place)
			var lam := t + float(rec["g0"])
			out["lam"] = lam
			out["pd"] = float(rec["pd0"]) * (1.0 - _smooth((t - since) / 1.0))
			out["ph"] = fposmod(_lane_phase(p.index, lam) + float(out["pd"]), 1.0)
			return out
		var sv2 := minf(big, s0 + maxf(0.0, t - start) * Data.HURRY_SPEED)
		out["s"] = sv2
		out["on_lane"] = false
		out["lam"] = p.lam_d
		out["walked"] = w0 + absf(sv2 - s0)
		out["ph"] = fposmod(p.ph_d + float(out["walked"]) / STRIDE, 1.0)
		return out
	var t_r := float(rec["t_r"])
	if s0 > 0.0 and t < t_r:
		var sv3 := maxf(float(rec["floor"]), s0 - maxf(0.0, t - start) * Data.RETURN_SPEED)
		out["s"] = sv3
		out["on_lane"] = false
		out["lam"] = p.lam_d
		out["walked"] = w0 + absf(sv3 - s0)
		out["ph"] = fposmod(p.ph_d + float(out["walked"]) / STRIDE, 1.0)
		return out
	var t_meet := float(rec["t_meet"])
	if t < t_meet:
		var rate := float(rec["rate"])
		var dt := maxf(0.0, t - t_r)
		out["lam"] = t + float(rec["g_r"]) + rate * dt
		out["moving"] = true
		out["back"] = rate < -1.0
		out["walked"] = float(rec["w_r"]) + Data.LANE_RETURN_SPEED * dt
		out["ph"] = fposmod(float(rec["ph_r"]) + Data.LANE_RETURN_SPEED * dt / STRIDE, 1.0)
		return out
	out["lam"] = t
	out["pd"] = float(rec["pdb"]) * (1.0 - _smooth((t - t_meet) / 1.0))
	out["ph"] = fposmod(_lane_phase(p.index, t) + float(out["pd"]), 1.0)
	return out


## Free cover spots for the walkers leaving their lanes in this phase, in the order they leave.
func _assign_walkers() -> void:
	var held := _held.duplicate()
	var leaving: Array = []
	for p: Person in people:
		if p.kind != K_WALKER or not p.react or p.umbrella or p.rec.is_empty():
			continue
		if bool(p.rec.get("depart", false)):
			leaving.append(p)
		elif float(p.rec["s0"]) > 0.0 and p.spot >= 0:
			held[p.spot] = p.id
	leaving.sort_custom(func(a: Person, b: Person) -> bool:
		var ta := float(a.rec["td"])
		var tb := float(b.rec["td"])
		return ta < tb or (ta == tb and a.index < b.index))
	var loops := CityRules.walk_loops()
	for p: Person in leaving:
		var lam_d := float(p.rec["lam_d"])
		var li := _loop_index(p.index)
		var loop: Dictionary = loops[li]
		var pts: Array = loop["pts"]
		var total := float(loop["length"])
		var d: Vector2 = CityRules.walker_pose(p.index, lam_d)["pos"]
		var a_d := CityRules.poly_project(pts, d).x
		var best := -1
		var best_cost := INF
		var best_dir := 1.0
		var best_dl := 0.0
		for j in spots.size():
			if held.has(j) or String((spots[j] as Dictionary)["region"]) != "ground":
				continue
			var ex := _exit(li, j)
			if ex.is_empty():
				continue
			var fwd := fposmod(float(ex["arc"]) - a_d, total)
			var dir := 1.0 if fwd <= total - fwd else -1.0
			var dl := fwd if dir > 0.0 else total - fwd
			var cost := dl + float(ex["len"])
			if cost < best_cost - 1e-9:
				best_cost = cost
				best = j
				best_dir = dir
				best_dl = dl
		p.base = PackedVector3Array()
		p.base_reg = PackedStringArray()
		p.base_len = PackedFloat32Array()
		p.spot = best
		if best < 0:
			continue
		held[best] = p.id
		var ex2 := _exit(li, best)
		var pts3: Array[Vector2] = [d]
		# the lane part: along the loop through its corners
		var arcs := _corner_arcs(pts)
		for ca: float in arcs:
			var rel := fposmod((ca - a_d) * best_dir, total)
			if rel > 1e-4 and rel < best_dl - 1e-4:
				pts3.append(pts[arcs.find(ca)])
		pts3.sort_custom(func(x: Vector2, y: Vector2) -> bool:
			return fposmod((CityRules.poly_project(pts, x).x - a_d) * best_dir, total) < fposmod((CityRules.poly_project(pts, y).x - a_d) * best_dir, total))
		var leg: PackedVector2Array = ex2["leg"]
		for q: Vector2 in leg:
			pts3.append(q)
		_set_path(p, pts3, [])
		p.lane_e = best_dl
		p.lam_d = lam_d
		p.lane_dir = best_dir
		p.lane_speed = float(loop["speed"])
		var ph0 := float(p.rec.get("ph0", -1.0))
		p.ph_d = ph0 if ph0 >= 0.0 and float(p.rec["td"]) <= float(p.rec["since"]) + 1e-6 else _lane_phase(p.index, lam_d) + float(p.rec.get("pd0", 0.0))
		p.rec["s0"] = _plen(p) if bool(p.rec.get("assumed", false)) else 0.0
		if bool(p.rec.get("assumed", false)):
			p.rec["depart"] = false
			p.rec["start"] = float(p.rec["since"])
			p.rec["w0"] = _plen(p)
			_timing(p)


static func _loop_index(index: int) -> int:
	var loops := CityRules.walk_loops()
	for li in loops.size():
		var l: Dictionary = loops[li]
		if index >= int(l["first"]) and index < int(l["first"]) + int(l["count"]):
			return li
	return 0


static func _corner_arcs(pts: Array) -> Array[float]:
	var out: Array[float] = []
	var acc := 0.0
	for i in pts.size():
		out.append(acc)
		acc += (pts[i] as Vector2).distance_to(pts[(i + 1) % pts.size()])
	return out


## Sets a person's path from ground points (y 0) or, with `regions`, points on those regions.
func _set_path(p: Person, pts: Array[Vector2], regions: Array) -> void:
	p.base = PackedVector3Array()
	p.base_reg = PackedStringArray()
	p.base_len = PackedFloat32Array()
	var acc := 0.0
	for i in pts.size():
		var reg := "ground" if regions.is_empty() else String(regions[i])
		var y := 0.0 if reg == "ground" else CityNav.height(reg, pts[i])
		var q := Vector3(pts[i].x, y, pts[i].y)
		if i > 0:
			if q.distance_to(p.base[p.base.size() - 1]) < 1e-4:
				continue
			acc += q.distance_to(p.base[p.base.size() - 1])
		p.base.append(q)
		p.base_reg.append(reg)
		p.base_len.append(acc)


## The way off a walker lane to a ground spot: the lane point to leave from (its arc) and the leg from there
## (through the shop door for a spot inside a shop), every piece clear of the ground's solids. {} when none.
func _exit(li: int, si: int) -> Dictionary:
	var key := Vector2i(li, si)
	if _exits.has(key):
		return _exits[key]
	_obstacles()
	var loop: Dictionary = CityRules.walk_loops()[li]
	var pts: Array = loop["pts"]
	var total := float(loop["length"])
	var sp: Dictionary = spots[si]
	var q: Vector2 = sp["pos"]
	var via: Array[Vector2] = []
	var shop := String(sp["shop"])
	if shop != "" and CityMap.SHOP_DOORS.has(shop):
		var door: Vector2 = CityMap.SHOP_DOORS[shop]
		var front := (CityMap.BUILDINGS[shop]["rect"] as Rect2).end.y
		via = [Vector2((door.x + door.y) * 0.5, front + 0.55), Vector2((door.x + door.y) * 0.5, front - 0.6)]
	var first := via[0] if not via.is_empty() else q
	var cands: Array = []
	var a := 0.0
	while a < total:
		var e: Vector2 = CityRules.poly_point(pts, a)["pos"]
		var dd := e.distance_to(first)
		if dd <= 14.0:
			cands.append([dd, a])
		a += 0.5
	cands.sort()
	var out := {}
	var tries := 0
	for c: Array in cands:
		tries += 1
		if tries > 40:
			break
		var e2: Vector2 = CityRules.poly_point(pts, float(c[1]))["pos"]
		var leg := PackedVector2Array([e2])
		for v: Vector2 in via:
			leg.append(v)
		leg.append(q)
		var ok := true
		var length := 0.0
		for i in leg.size() - 1:
			length += leg[i].distance_to(leg[i + 1])
			if not _seg_clear(leg[i], leg[i + 1]):
				ok = false
				break
		# and walkable for the navigation itself, every 0.1 m past the lane point
		if ok:
			for i in leg.size() - 1:
				var n := maxi(1, ceili(leg[i].distance_to(leg[i + 1]) / 0.1))
				for j in n + 1:
					var w := leg[i].lerp(leg[i + 1], float(j) / float(n))
					if w.distance_to(leg[0]) >= 0.3 and not CityNav.allowed("", w):
						ok = false
						break
				if not ok:
					break
		if ok:
			out = {"arc": float(c[1]), "leg": leg, "len": length}
			break
	_exits[key] = out
	return out


## The ground's solids for the walkers' legs to cover, grown by the walker radius (CityRules.WALKER_R, so a lane
## point itself is clear): walls, ground solids, furniture (the extra too), the standing people, and the
## chairs of seated people and of children's seats.
static func _obstacles() -> void:
	if not _rects.is_empty():
		return
	var r := float(CityRules.WALKER_R)
	for w: Rect2 in CityMap.GROUND_WALLS:
		_rects.append(w.grow(r))
	for sd: Dictionary in CityMap.GROUND_SOLIDS:
		if sd.has("rect"):
			_rects.append((sd["rect"] as Rect2).grow(r))
		else:
			var at: Vector2 = sd["at"]
			_circs.append(Vector3(at.x, at.y, float(sd["r"]) + r))
	var furn: Array = []
	furn.append_array(CityMap.FURNITURE)
	if "EXTRA_FURNITURE" in PropsCity:
		furn.append_array(PropsCity.EXTRA_FURNITURE)
	for f: Dictionary in furn:
		if String(f["region"]) in ["ground", ""]:
			_rects.append((f["rect"] as Rect2).grow(r))
	for sol: Dictionary in Data.solids():
		if String(sol["region"]) in ["ground", ""]:
			var at2: Vector2 = sol["at"]
			_circs.append(Vector3(at2.x, at2.y, float(sol["r"]) + r))
	for e: Dictionary in Data.PEOPLE:
		if String(e["region"]) == "ground" and not Data.is_standing(e):
			var at3: Vector2 = e["pos"]
			_circs.append(Vector3(at3.x, at3.y, 0.22 + r))
	for k: String in CityMap.INTERACTIONS:
		var it: Dictionary = CityMap.INTERACTIONS[k]
		if String(it["region"]) == "ground" and String(it["kind"]) == "seat":
			var at4: Vector2 = it["pos"]
			_circs.append(Vector3(at4.x, at4.y, 0.22 + r))


## A straight walk from a to b clear of the ground's solids.
static func _seg_clear(a: Vector2, b: Vector2) -> bool:
	_obstacles()
	var d := b - a
	for rc: Rect2 in _rects:
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for ax in 2:
			var lo := rc.position[ax]
			var hi := rc.end[ax]
			if absf(d[ax]) < 1e-9:
				if a[ax] <= lo or a[ax] >= hi:
					hit = false
					break
			else:
				var u0 := (lo - a[ax]) / d[ax]
				var u1 := (hi - a[ax]) / d[ax]
				if u0 > u1:
					var tmp := u0
					u0 = u1
					u1 = tmp
				t0 = maxf(t0, u0)
				t1 = minf(t1, u1)
				if t0 >= t1:
					hit = false
					break
		if hit:
			return false
	for c: Vector3 in _circs:
		var cc := Vector2(c.x, c.y)
		var l2 := d.length_squared()
		var u := 0.0 if l2 < 1e-12 else clampf((cc - a).dot(d) / l2, 0.0, 1.0)
		if (a + d * u).distance_to(cc) < c.z:
			return false
	return true


## A static person's spot: the nearest free spot on its kind of level (upper floors for the upper ones) that a
## real route (CityNav.route) reaches; the path is home, then the route.
func _assign_static(p: Person) -> void:
	var home := Vector2(p.root.origin.x, p.root.origin.z)
	var here := p.root.origin
	var cands: Array = []
	for i in spots.size():
		if _held.has(i):
			continue
		var sp: Dictionary = spots[i]
		var upper := String(sp["region"]) != "ground"
		if upper != (p.region != "ground"):
			continue
		var q: Vector2 = sp["pos"]
		cands.append([here.distance_to(Vector3(q.x, float(sp["y"]), q.y)), i])
	cands.sort()
	for c: Array in cands.slice(0, 4):
		var i := int(c[1])
		var sp: Dictionary = spots[i]
		var reg := String(sp["region"])
		var r := CityNav.route("" if p.region == "ground" else p.region, home, "" if reg == "ground" else reg, sp["pos"])
		if r.is_empty():
			continue
		var pts: Array[Vector2] = [home]
		var regs: Array = [p.region]
		for wp: Dictionary in r:
			pts.append(wp["pos"])
			regs.append(Data.norm_region(String(wp["region"])))
		_set_path(p, pts, regs)
		p.spot = i
		_held[i] = p.id
		return


## A carousel rider's spot: a free canopy spot round the carousel, nearest its fence gap.
func _assign_carousel(p: Person) -> void:
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var gap := _gap_dir()
	var out_pt := c + gap * 3.35
	var best := -1
	var bd := INF
	for i in spots.size():
		var sp: Dictionary = spots[i]
		var q: Vector2 = sp["pos"]
		if _held.has(i) or String(sp["region"]) != "ground" or q.distance_to(c) > 4.2:
			continue
		if q.distance_to(out_pt) < bd:
			bd = q.distance_to(out_pt)
			best = i
	if best >= 0:
		p.spot = best
		_held[best] = p.id


func _gap_dir() -> Vector2:
	if city_world != null and city_world.has_method("carousel_gap_dir"):
		var g: Vector2 = city_world.call("carousel_gap_dir")
		return g
	return Vector2(0, -1)


## A carousel rider's way off: from the saddle down to the deck, round the deck to the fence gap, out, to its spot.
func _carousel_path(p: Person, td: float) -> void:
	if p.spot < 0:
		return
	var c: Vector2 = CityMap.CAROUSEL["center"]
	var seat := _carousel_xf(p.index, td).origin
	var a_seat := atan2(-(seat.z - c.y), seat.x - c.x)
	var gap := _gap_dir()
	var a_gap := atan2(-gap.y, gap.x)
	var da := wrapf(a_gap - a_seat, -PI, PI)
	var pts := PackedVector3Array([seat])
	var deck := 0.3
	var steps := maxi(1, ceili(absf(da) / 0.5))
	for i in steps + 1:
		var a := a_seat + da * float(i) / float(steps)
		pts.append(Vector3(c.x + cos(a) * 2.15, deck, c.y - sin(a) * 2.15))
	pts.append(Vector3(c.x + gap.x * 2.6, 0.13, c.y + gap.y * 2.6))
	pts.append(Vector3(c.x + gap.x * 3.35, 0.0, c.y + gap.y * 3.35))
	var q: Vector2 = (spots[p.spot] as Dictionary)["pos"]
	pts.append(Vector3(q.x, 0.0, q.y))
	p.base = PackedVector3Array()
	p.base_reg = PackedStringArray()
	p.base_len = PackedFloat32Array()
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		p.base.append(pts[i])
		p.base_reg.append("ground")
		p.base_len.append(acc)


## A point on a person's path: [position, unit direction (x, z) forward along the path, region].
func _path_at(p: Person, s: float) -> Array:
	var n := p.base.size()
	if n == 0:
		return [p.root.origin, Vector2(0, 1), p.region]
	if n == 1:
		return [p.base[0], Vector2(0, 1), p.base_reg[0]]
	var i := 1
	while i < n - 1 and float(p.base_len[i]) < s:
		i += 1
	var a := p.base[i - 1]
	var b := p.base[i]
	var seg := float(p.base_len[i]) - float(p.base_len[i - 1])
	var u := clampf((s - float(p.base_len[i - 1])) / seg, 0.0, 1.0) if seg > 1e-6 else 1.0
	var d := Vector2(b.x - a.x, b.z - a.z)
	if d.length() < 1e-4:
		d = Vector2(0, 1)
	return [a.lerp(b, u), d.normalized(), p.base_reg[i]]


static func _ry_of(b: Basis) -> float:
	return atan2(b.z.x, b.z.z)


## The way a person faces at its cover spot: back out the way it came (watching the rain).
func _spot_ry(p: Person) -> float:
	var n := p.base.size()
	if n < 2:
		return 0.0
	var d := p.base[n - 2] - p.base[n - 1]
	return atan2(d.x, d.z)


## Where a person's activity is (no scale): its place, its lane point, its horse.
func _home_root(p: Person, t: float, e: Dictionary) -> Transform3D:
	match p.kind:
		K_WALKER:
			var w: Dictionary = CityRules.walker_pose(p.index, float(e["lam"]))
			var wp: Vector2 = w["pos"]
			return Transform3D(Basis(Vector3.UP, float(w["ry"])), Vector3(wp.x, 0.0, wp.y))
		K_CAROUSEL:
			return _carousel_xf(p.index, t)
	return p.root


func _update_react(p: Person, t: float, force: bool) -> void:
	var e := _eval(p, t)
	var s := float(e["s"])
	var away := s > 0.0
	var at: Array = _path_at(p, s) if away else []
	var region := String(at[2]) if away else p.region
	if p.kind == K_STATIC and hidden_regions.has(region):
		_hide(p, force)
		return
	var full := force or not p.shown
	var sc := p.s
	var body_scale := Basis.from_scale(Vector3(sc, sc, sc))
	var home := _home_root(p, t, e)
	p.home_world = Transform3D(home.basis * body_scale, home.origin)
	p.world = p.home_world
	var po := p.pose
	po.reset()
	var root := home
	var female := String(p.look["sex"]) == "f"
	if p.kind == K_WALKER:
		p.wphase = float(e["ph"])
		if bool(e["back"]):
			# walking back along its lane to meet its slot: it faces the way it walks
			home = Transform3D(Basis(Vector3.UP, PI) * home.basis, home.origin)
			p.home_world = Transform3D(home.basis * body_scale, home.origin)
	if not away:
		_pose(p, t, po)
	else:
		var big := _plen(p)
		var rain := bool(p.rec["rain"])
		var walk := _tmp_a
		walk.reset()
		var ph := float(e["ph"]) if p.kind == K_WALKER else Data.hash01(p.sd, 5) + float(e["walked"]) / STRIDE
		_walk_cycle(walk, fposmod(ph, 1.0), rain)
		var ks := _smooth((big - s) / BLEND_M)
		if ks < 1.0:
			var idle := _tmp_b
			idle.reset()
			_cover_idle(p, p.tau(t), idle)
			_mix(walk, idle, 1.0 - ks, female)
		var kh := _smooth(s / (BLEND_M * (2.0 if p.kind == K_CAROUSEL else 1.0)))
		if p.kind == K_WALKER:
			p.wphase = fposmod(ph, 1.0)
		_pose(p, t, po)
		_mix(po, walk, kh, female)
		var pos: Vector3 = home.origin.lerp(at[0] as Vector3, kh)
		var d: Vector2 = at[1]
		if not rain:
			d = -d
		var ry := atan2(d.x, d.y)
		if ks < 1.0:
			ry = lerp_angle(_spot_ry(p), ry, ks)
		ry = lerp_angle(_ry_of(home.basis), ry, kh)
		root = Transform3D(Basis(Vector3.UP, ry), pos)
	if p.umbrella:
		po.umb = float(e["umb"])
		po.umb_hand = p.umb_hand
		_umbrella_arm(po, female)
	p.world = Transform3D(root.basis * body_scale, root.origin)
	_draw(p, po, full)
	p.shown = true


## The hand of arm k at the end of its forward kinematics (person-local).
static func _arm_end(po: Pose, k: int, female: bool) -> Vector3:
	var tor := frames(po)[1]
	var tw := 0.39 if female else 0.44
	var sg := -1.0 if k == 0 else 1.0
	var sh := tor * Vector3(sg * (tw * 0.5 + 0.045), SHOULDER_Y, 0.0)
	return _fk(sh, tor.basis, po.arm[k], sg, UARM, FARM + 0.04, false)[1]


## Blends pose a toward pose b by k (into a). Arms in different modes meet as hand targets; a keeps its held
## things (the waiter's tray, a cup) and its things left at home.
static func _mix(a: Pose, b: Pose, k: float, female: bool) -> void:
	var ta: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var tb: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for i in 2:
		if a.arm_ik[i] != b.arm_ik[i] or a.arm_ik[i]:
			ta[i] = a.arm[i] if a.arm_ik[i] else _arm_end(a, i, female)
			tb[i] = b.arm[i] if b.arm_ik[i] else _arm_end(b, i, female)
	for i in 2:
		if not a.arm_ik[i] and not b.arm_ik[i]:
			a.arm[i] = a.arm[i].lerp(b.arm[i], k)
		else:
			a.arm[i] = ta[i].lerp(tb[i], k)
			a.pole[i] = a.pole[i].lerp(b.pole[i], k)
			a.arm_ik[i] = true
		if not a.leg_ik[i] and not b.leg_ik[i]:
			a.leg[i] = a.leg[i].lerp(b.leg[i], k)
		elif k >= 0.5:
			a.leg_ik[i] = b.leg_ik[i]
			a.leg[i] = b.leg[i]
		if a.prop_on[i] < 0:
			a.prop_on[i] = b.prop_on[i]
			a.prop_xf[i] = b.prop_xf[i]
			a.prop_home[i] = b.prop_home[i]
	a.hip = lerpf(a.hip, b.hip, k)
	a.off = a.off.lerp(b.off, k)
	a.yaw = lerp_angle(a.yaw, b.yaw, k)
	a.sway = lerpf(a.sway, b.sway, k)
	a.lean = lerpf(a.lean, b.lean, k)
	a.twist = lerpf(a.twist, b.twist, k)
	a.side = lerpf(a.side, b.side, k)
	a.head = a.head.lerp(b.head, k)
	var pa := a.plant_k if a.plant else 0.0
	var pb := b.plant_k if b.plant else 0.0
	a.plant_k = lerpf(pa, pb, k)
	a.plant = a.plant or b.plant
	a.ground = lerpf(a.ground, b.ground, k)
	a.cross = lerpf(a.cross, b.cross, k)


## Waiting under cover: standing, now and then glancing up at the sky or shaking the rain off.
static func _cover_idle(p: Person, tau: float, po: Pose) -> void:
	_stand(po)
	po.sway = 0.02 * sin(tau * TAU / 5.0)
	po.off.x = 0.015 * sin(tau * TAU / 5.0)
	var hands := Data.hash01(p.sd, 171) < 0.5
	if hands:
		_ik_arm(po, 0, Vector3(-0.07, 1.08, 0.24), Vector3(-1, -1, -0.4))
		_ik_arm(po, 1, Vector3(0.07, 1.08, 0.24), Vector3(1, -1, -0.4))
	var ev := _event(p, tau, 2.4, 161)
	if ev.z < 0.55:
		po.head.x = -0.45 * ev.x
		po.head.y = (0.3 if ev.z < 0.27 else -0.3) * ev.x
	else:
		var sh := sin(tau * TAU * 4.0) * ev.x
		po.side = 0.05 * sh
		po.head.z = 0.08 * sh
		if not hands:
			po.arm[0] = Vector3(0.1 + 0.1 * sh, 0.2 + 0.1 * ev.x, 0.3)
			po.arm[1] = Vector3(0.1 - 0.1 * sh, 0.2 + 0.1 * ev.x, 0.3)


## The umbrella hand rises from wherever it was to hold the umbrella over the head as it opens.
static func _umbrella_arm(po: Pose, female: bool) -> void:
	if po.umb <= 0.0:
		return
	var k := po.umb_hand
	var sg := -1.0 if k == 0 else 1.0
	var cur := po.arm[k] if po.arm_ik[k] else _arm_end(po, k, female)
	var target := Vector3(sg * 0.17, po.hip + 0.6, 0.2)
	po.arm[k] = cur.lerp(target, _smooth(po.umb * 3.0))
	po.pole[k] = Vector3(sg, -1.0, -0.6)
	po.arm_ik[k] = true
