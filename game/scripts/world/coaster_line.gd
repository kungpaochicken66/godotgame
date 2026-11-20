extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
var frames: Array[Transform3D] = []
var timetable: Array
var ds: float
var gauge: float
var pitch: float
var stop: float
var cars: Array[Node3D] = []
var wheels: Array[Node3D] = []
var board: Vector3
var scene_tags: PackedByteArray
var seat_type := "sit"
var eye := Vector3(0,1.38,-0.17)
var seat_origin := Vector3(0,0.36,0.15)
var rail_paint: Color
var support_paint := Color("#628578")
var design: String
var accent: Color
var title: String
var elapsed := 0.0
var distance := 0.0
var moving := false
var _frame_cells := {}
var _chunks := []
var _keep_outs := []

func sample(s: float) -> Transform3D:
	var k := fposmod(s / ds, frames.size())
	var i := floori(k)
	return frames[i].interpolate_with(frames[(i + 1) % frames.size()], k - i)

func setup(id: String, caption: String, color: Color, angle: float) -> void:
	design = id
	title = caption
	accent = color
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://coasters/" + id + ".json"))
	scene_tags = PackedByteArray(data.get("scenes",[]))
	seat_type = data.get("seat","sit")
	rail_paint = Color(data.get("railColor",{"orchard-breeze":"#9d4938","comet-run":"#456caa"}.get(id,"#258680")))
	support_paint = Color(data.get("supportColor","#628578"))
	if data.has("eye"):
		eye = Vector3(data.eye[0],data.eye[1],data.eye[2])
		seat_origin = Vector3(eye.x,eye.y-1.02,eye.z+0.20)
	ds = data.ds
	gauge = data.halfWidth
	pitch = data.pitch
	stop = data.stop
	timetable = data.timeline
	var center := Vector3.ZERO
	for row in data.frames:
		var pos := Vector3(row[0], row[1], row[2])
		var forward := Vector3(row[3], row[4], row[5])
		var up := Vector3(row[6], row[7], row[8])
		frames.append(Transform3D(Basis.looking_at(forward, up), pos))
		center += pos
	center /= frames.size()
	var station := sample(stop)
	var outward := center - station.origin
	rotation.y = angle - atan2(outward.x, outward.z)
	var forward := Vector3(outward.x,0,outward.z).normalized()
	var transverse := forward.cross(Vector3.UP)
	var radius := 24.0
	for f in frames:
		var offset := f.origin-station.origin
		radius=maxf(radius,absf(offset.dot(transverse))/tan(PI/6)-offset.dot(forward)+9.0)
	var plaza_edge := Vector3(sin(angle), 0, cos(angle)) * radius
	position = plaza_edge - basis * station.origin
	var hanger_height := 2.75 if seat_type=="invert" else 0.0
	position.y = 0.25+hanger_height-station.origin.y
	# unified r6 (clearance audit): the scenery first, so the track's supports can stand clear of it.
	if data.has("scenes"):
		_build_theme_scenery(data.scenes)
	else:
		_build_landmarks(center)
	_build_track()
	var sign_side := -1.0 if station.basis.x.dot(outward) > 0 else 1.0
	var platform := Node3D.new()
	add_child(platform)
	platform.transform = station
	platform.position.y -= hanger_height
	var x := sign_side * (gauge + 2.5)
	Kit.box(platform, Vector3(4.5, 0.55, 14), Color("#c28c5f"), Vector3(x, 0.02, 4))
	Kit.box(platform, Vector3(0.22, 2.5, 0.22), accent, Vector3(x, 1.5, 8))
	for post_z in [-1.8,9.8]:
		for edge in [-1.7,1.7]:
			Kit.cyl(platform,0.095,0.13,2.8,Color("#80654c"),Vector3(x+edge,1.61,post_z))
	# unified r6 (clearance audit): under the suspended ride the canopy's track-side edge stops short of the passing hangers.
	var trim := 0.45 if seat_type=="invert" else 0.0
	Kit.box(platform, Vector3(4.4-trim,0.22,13),accent,Vector3(x+sign_side*trim*0.5,3.12,4))
	Kit.box(platform, Vector3(4.55-trim,0.13,13.2),Color("#f5d88c"),Vector3(x+sign_side*trim*0.5,3.01,4))
	var signboard := Label3D.new()
	platform.add_child(signboard)
	signboard.position = Vector3(x, 4.4, 5)
	signboard.text = tr(title)
	signboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	signboard.font_size = 78
	signboard.outline_size = 13
	signboard.pixel_size = 0.01
	board = to_global(platform.transform * Vector3(x, 0.31, 0))
	for i in 3:
		var car := Node3D.new()
		add_child(car)
		cars.append(car)
		if seat_type in ["wing","invert"]:
			_build_special_car(car)
		else:
			Kit.box(car, Vector3(2*gauge+0.16, 0.24, 2.4), accent, Vector3(0,0.39,0))
			_build_seat(car,seat_origin)
			for side in [-1,1]:
				Kit.box(car,Vector3(0.16,0.4,2.2),accent,Vector3(side*gauge,0.61,0))
			_theme_car(car,i)
		for side in [-1,1]:
			for z in [-0.76,0.76]:
				wheels.append(Kit.cyl(self,0.17,0.17,0.14,Color("#38424c"),Vector3.ZERO))
		Kit.merge_parts(car)
	place(stop)

func _build_seat(car: Node3D, anchor: Vector3, width := 1.0) -> void:
	Kit.box(car,Vector3(width,0.18,0.72),Color("#675044"),anchor+Vector3.UP*0.24)
	Kit.box(car,Vector3(width,0.52,0.16),Color("#654c42"),anchor+Vector3(0,0.48,0.4))
	Kit.box(car,Vector3(width,0.08,0.08),Color("#efcb82"),anchor+Vector3(0,0.56,-0.45))

func _build_special_car(car: Node3D) -> void:
	if seat_type=="wing":
		Kit.ball(car,1,Color("#192a32"),Vector3(0,0.62,0),Vector3(0.52,0.38,1.24))
		Kit.box(car,Vector3(5.5,0.16,0.50),accent,Vector3(0,0.45,0.2))
		for x: float in [-2.25,-1.58,1.58,2.25]:
			_build_seat(car,Vector3(x,seat_origin.y,seat_origin.z),0.63)
			Kit.box(car,Vector3(0.10,0.12,1.65),Color("#77ffc3"),Vector3(x,0.58,0.09))
	else:
		Kit.box(car,Vector3(2*gauge+0.55,0.16,1.75),Color("#393342"),Vector3(0,-0.24,0))
		for side in [-1,1]:
			for z in [-0.76,0.76]:
				Kit.box(car,Vector3(0.14,0.54,0.18),Color("#514958"),Vector3(side*(gauge+0.18),0,z))
				Kit.box(car,Vector3(0.23,0.12,0.13),Color("#514958"),Vector3(side*(gauge+0.09),0.235,z))
		Kit.box(car,Vector3(0.20,1.85,0.20),accent,Vector3(0,-1.15,0.48))
		Kit.box(car,Vector3(2.72,0.24,0.55),accent,Vector3(0,-1.98,0.30))
		for x: float in [-0.96,-0.32,0.32,0.96]:
			_build_seat(car,Vector3(x,seat_origin.y,seat_origin.z),0.59)
		Kit.ball(car,0.48,Color("#ebe5c8"),Vector3(0,-0.57,-0.60),Vector3(1.3,1,0.7))
		for side in [-1,1]:
			Kit.ball(car,0.13,Color("#38473d"),Vector3(side*0.20,-0.55,-0.875),Vector3(1,0.83,0.48))
			Kit.ball(car,0.056,Color("#8cef82"),Vector3(side*0.20,-0.55,-0.93))
			Kit.box(car,Vector3(0.14,1.38,0.18),Color("#605268"),Vector3(side*0.94,-1.24,0.35))
		for x: float in [-0.18,0.0,0.18]:
			Kit.box(car,Vector3(0.14,0.20,0.19),Color("#e5daa7"),Vector3(x,-0.94,-0.68))

func _build_theme_scenery(scenes: Array) -> void:
	var decor := Node3D.new()
	add_child(decor)
	var ground := -4.0-position.y
	for i in range(0,frames.size(),14):
		if scenes[i]==0: continue
		var f := frames[i]
		var arch := Node3D.new()
		decor.add_child(arch)
		arch.transform = f
		var stone := Color("#756f83")
		var timber := Color("#805b40")
		var width := 6.2
		for side in [-1,1]:
			var foot := Vector3(side*width,0,0)
			var foundation := f*(foot+Vector3.DOWN*(3.0 if design=="phantom-castle" else 2.2))
			var height := foundation.y-ground
			if height>0.2:
				var pier_size := 1.45 if design=="phantom-castle" else 0.56
				Kit.box(decor,Vector3(pier_size,height,pier_size),stone if design=="phantom-castle" else timber,foundation-Vector3.UP*height*0.5)
			match design:
				"crystal-mine":
					if i%42!=0:
						Kit.ball(arch,1.0,Color("#746e68"),foot+Vector3(side*1.8,0.3,0),Vector3(1.75,3.6,4.4))
					Kit.box(arch,Vector3(0.48,7,0.55),timber,foot+Vector3.UP)
					Kit.ball(arch,0.29,Color("#ffd678"),foot+Vector3(-side*0.48,2.9,0))
					var rock := f*Vector3(side*8.1,-2,0)
					rock.y = ground
					Kit.ball(decor,2.8,stone,rock,Vector3(1,1.12,1.3))
					for j in 3:
						Kit.cyl(decor,0.02,0.48,2.4+j*0.48,Color("#65d7dc") if j%2 else Color("#b487e2"),rock+Vector3(0.65*j,2.7,0),Vector3(10*j,0,18-j*14))
				"neon-wings":
					if i%42==0:
						var pond := f*Vector3(side*13,0,0)
						pond.y = ground+0.09
						Kit.cyl(decor,3.5,3.8,0.18,Color("#5fa7aa"),pond)
						for j in 3:
							var post := pond+Vector3(j-1,1.5+j*0.65,0)
							Kit.cyl(decor,0.13,0.25,3+j*1.3,Color("#374957"),post)
							Kit.ball(decor,0.34,accent,post+Vector3.UP*(1.5+j*0.65))
					Kit.box(arch,Vector3(0.42,7,1),Color("#253446"),foot+Vector3.UP)
					var strip := Kit.box(arch,Vector3(0.18,6.7,0.32),accent,foot+Vector3(-side*0.27,1,0))
					strip.material_override = Kit.glow_mat(accent)
					if side>0:
						Kit.box(arch,Vector3(0.5,7,7.3),Color("#273644"),foot+Vector3(side*0.5,1,0))
				"phantom-castle":
					Kit.box(arch,Vector3(1,8,2.6),stone,foot)
					Kit.box(arch,Vector3(0.75,2.1,7.4),Color("#878595"),foot+Vector3(side*0.2,-2.8,0))
					Kit.box(arch,Vector3(1.28,0.45,2.8),Color("#a6a0ad"),foot+Vector3.UP*3.5)
					Kit.box(arch,Vector3(6.4,0.56,1.1),stone,Vector3(side*3.1,4.8,0),0.05,Vector3(0,0,-side*17))
					if i%28==0:
						for j in 3:
							Kit.box(arch,Vector3(0.22,2.2,0.60),[Color("#68b3bc"),Color("#d993a7"),Color("#c1a75f")][j],foot+Vector3(-side*0.53,1.8,j*0.62-0.60))
					Kit.ball(arch,0.33,Color("#ffa858"),foot+Vector3(-side*0.68,0.65,0),Vector3(0.8,1.7,0.8))
		if design=="neon-wings":
			Kit.box(arch,Vector3(12.9,0.35,7.35),Color("#20303f"),Vector3.UP*4.9)
		if design!="phantom-castle":
			Kit.box(arch,Vector3(width*2+0.7,0.4,0.60),timber if design=="crystal-mine" else accent,Vector3.UP*4.4)
		_keep_clear(arch, arch.transform, true)
		Kit.merge_parts(arch)
	if design=="phantom-castle":
		var avg := Vector3.ZERO
		for f in frames: avg+=f.origin
		avg/=frames.size()
		avg.y=ground
		for side in [-1,1]:
			var at := avg+Vector3(side*5,0,0)
			Kit.cyl(decor,2.4,3,11,Color("#928798"),at+Vector3.UP*5.5)
			Kit.cyl(decor,0.05,3.3,5,Color("#655478"),at+Vector3.UP*13.5)
		Kit.box(decor,Vector3(10,7,4),Color("#a297a4"),avg+Vector3.UP*3.5)
	_keep_clear(decor, decor.transform, false)
	Kit.merge_parts(decor)

func _build_landmarks(center: Vector3) -> void:
	var garden := Node3D.new()
	add_child(garden)
	var ground := -4.0-position.y
	var gold := Color("#efb548")
	var brick := Color("#af4c39")
	if design=="copper-coil":
		var base := Vector3(0,ground,0)
		for tier in 5:
			var w := 12.0-tier*1.7
			var y := 2.6+tier*4.2
			Kit.cyl(garden,w*0.48,w*0.52,4.4,brick,base+Vector3.UP*y)
			Kit.cyl(garden,w*0.40,w*0.77,2,Color("#306f64"),base+Vector3.UP*(y+2.45))
			Kit.cyl(garden,w*0.77,w*0.75,0.24,gold,base+Vector3.UP*(y+1.49))
			for side in 8:
				var ray := Vector3(cos(side*PI/4),0,sin(side*PI/4))
				Kit.ball(garden,0.46,gold,base+ray*w*0.53+Vector3.UP*y,Vector3(1,1.5,1))
		Kit.cyl(garden,0.06,0.38,3,gold,base+Vector3.UP*24)
	else:
		var stride := 27 if design=="orchard-breeze" else 140
		for i in range(stride,frames.size(),stride):
			var f := frames[i]
			var toward := Vector3(center.x-f.origin.x,0,center.z-f.origin.z).normalized()
			var at := Vector3(f.origin.x,ground,f.origin.z)+toward*(8.0+float(i%3))
			if design=="orchard-breeze":
				Kit.cyl(garden,0.28,0.48,4.3,Color("#916447"),at+Vector3.UP*2.1)
				Kit.ball(garden,2.7,Color("#64a268"),at+Vector3.UP*4.9,Vector3(1,0.84,1))
				for fruit in 7:
					var ray := Vector3(cos(fruit*0.9),0,sin(fruit*0.9))
					Kit.ball(garden,0.34,brick,at+ray*2.5+Vector3.UP*(4.7+0.5*(fruit%2)))
			else:
				var mast := 10.0+6*(i%3)
				Kit.cyl(garden,0.24,0.8,mast,Color("#57849a"),at+Vector3.UP*mast*0.5)
				var star := at+Vector3.UP*mast
				Kit.ball(garden,0.92,gold,star)
				for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
					for sign_value in [-1,1]:
						var ray: Vector3 = axis*sign_value
						var tip := Kit.cyl(garden,0.04,0.51,2.6,gold,star+ray*1.45)
						tip.quaternion = Quaternion(Vector3.UP,ray) if ray!=Vector3.DOWN else Quaternion(Vector3.RIGHT,PI)
	_keep_clear(garden, garden.transform, false)
	Kit.merge_parts(garden)

## unified r6 (clearance audit): each scenery part's box (line space, recorded before the parts are merged), which the
## track's supports keep clear of.
func _keep_clear(node: Node3D, xf: Transform3D, deep: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			var t: Transform3D = xf*child.transform
			var box: AABB = child.mesh.get_aabb()
			_keep_outs.append([t.affine_inverse(), box.grow(0.25/maxf(0.01,t.basis.get_scale()[t.basis.get_scale().min_axis_index()])), t*box])
		elif deep and child is Node3D:
			_keep_clear(child, xf*child.transform, true)

func _clear_of_scenery(a: Vector3, b: Vector3) -> bool:
	var span := AABB(a,Vector3.ZERO).expand(b).grow(0.5)
	for k in _keep_outs:
		if span.intersects(k[2]) and k[1].intersects_segment(k[0]*a,k[0]*b): return false
	return true

func _theme_car(car: Node3D, index: int) -> void:
	var gold := Color("#e5ab53")
	var cream := Color("#fff0bb")
	var silver := Color("#cadde1")
	match design:
		"crystal-mine":
			for side in [-1,1]:
				for j in 3:
					Kit.box(car,Vector3(0.12,0.16,2.36),Color("#8d694a"),Vector3(side*gauge,0.56+j*0.16,0))
				Kit.box(car,Vector3(0.15,0.55,0.13),Color("#59534e"),Vector3(side*gauge,0.77,-0.85))
			Kit.box(car,Vector3(1.8,0.40,0.15),accent,Vector3(0,0.66,-1.06))
			if index==0: Kit.ball(car,0.19,Color("#ffd884"),Vector3(0,0.73,-1.2))
		"orchard-breeze":
			Kit.ball(car,0.62,accent,Vector3(0,0.66,-0.8),Vector3(1.5,0.75,0.72))
			for side in [-1,1]:
				Kit.ball(car,0.46,cream,Vector3(side*gauge,0.82,0.34),Vector3(0.22,0.70,1.55))
				if index==0:
					Kit.cyl(car,0.03,0.045,0.34,gold,Vector3(side*0.54,1,-0.87),Vector3(-16,0,-side*20))
					Kit.ball(car,0.085,Color("#513829"),Vector3(side*0.6,1.17,-0.92))
					Kit.ball(car,0.13,Color("#452f21"),Vector3(side*0.58,0.79,-1.09))
		"comet-run":
			if index==0:
				Kit.cyl(car,0.04,0.54,0.86,silver,Vector3(0,0.65,-1.04),Vector3(-90,0,0))
			for side in [-1,1]:
				Kit.box(car,Vector3(0.13,0.55,0.83),silver,Vector3(side*gauge,0.85,0.69),0.11,Vector3(-27,0,-side*18))
				Kit.cyl(car,0.23,0.18,0.58,Color("#86423d"),Vector3(side*0.70,0.58,0.86),Vector3(90,0,0))
		"copper-coil":
			if index==0:
				Kit.ball(car,0.55,accent,Vector3(0,0.83,-0.74),Vector3(1.48,0.75,0.9))
				Kit.ball(car,0.40,gold,Vector3(0,0.69,-1.12),Vector3(1.48,0.62,0.76))
			for side in [-1,1]:
				if index==0:
					Kit.cyl(car,0.025,0.13,0.55,gold,Vector3(side*0.62,1.12,-0.52),Vector3(24,0,-side*25))
					Kit.ball(car,0.12,cream,Vector3(side*0.56,0.92,-1.0))
				for z in [-0.70,-0.2,0.30,0.80]:
					Kit.ball(car,0.26,gold,Vector3(side*gauge,0.67,z),Vector3(0.45,0.83,1.12))

func _instances(mesh: Mesh, poses: Array[Transform3D], color: Color) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = poses.size()
	for i in poses.size():
		batch.set_instance_transform(i, poses[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = batch
	node.material_override = Kit.mat(color)
	add_child(node)

func _build_track() -> void:
	var rails: Array[Transform3D] = []
	var ties: Array[Transform3D] = []
	var columns: Array[Transform3D] = []
	for i in frames.size():
		var f := frames[i]
		var next := frames[(i + 1) % frames.size()]
		for side in [-1,1]:
			var a: Vector3 = f.origin + f.basis.x * gauge * side
			var b: Vector3 = next.origin + next.basis.x * gauge * side
			var beam := Basis.looking_at((b-a).normalized(),f.basis.y)
			rails.append(Transform3D(beam.scaled_local(Vector3(0.13,0.13,a.distance_to(b)+0.015)),(a+b)*0.5))
		if i % 3 == 0:
			ties.append(Transform3D(f.basis.scaled_local(Vector3(2*gauge+0.16,0.13,0.16)),f.origin-f.basis.y*0.13))
		if i % 18 == 0:
			# unified r6 (clearance audit): a column top stays under its tie, not between the rails. A support is left
			# out where it would pass through the train or its rider anywhere on the lap, or through the scenery; a
			# suspended ride's hanger arm first tries the other side and then a shorter reach before that.
			var reaches: Array = [[5.0,1.0],[5.0,-1.0],[3.6,1.0],[3.6,-1.0]] if seat_type=="invert" else [[0.0,1.0]]
			for option in reaches:
				var top := 0.0 if seat_type=="invert" else 0.13
				var h := maxf(0.1, f.origin.y-top+position.y+4)
				var base := f.origin-Vector3.UP*top
				var arm := Vector3.ZERO
				var mount := Vector3.ZERO
				if seat_type=="invert":
					arm = f.basis.z.cross(Vector3.UP).normalized()*option[0]
					if arm.dot(f.basis.y)<0: arm = -arm
					arm *= option[1]
					mount = f.basis.y*0.6   # unified r6: the hanger arm passes above the wheels (0.45 m clipped them)
					base+=arm+mount
					h+=mount.y
				if not _clear_of_train(base, base-Vector3.UP*h, i, 4) or not _clear_of_scenery(base, base-Vector3.UP*h): continue
				if seat_type=="invert":
					if not _clear_of_train(f.origin+mount, base, i, 4) or not _clear_of_scenery(f.origin+mount, base): continue
					columns.append(Transform3D(Basis.looking_at(arm.normalized()).scaled_local(Vector3(0.25,0.25,arm.length())),f.origin+arm*0.5+mount))
				columns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.31,h,0.31)),base-Vector3.UP*h*0.5))
				break
	var box := BoxMesh.new()
	_instances(box,rails,rail_paint)
	_instances(box,ties,accent)
	_instances(box,columns,support_paint)

## unified r6 (clearance audit): the space a car and its rider can take, in track-frame coordinates (the car's own
## space; tests/coaster_clearance.gd measures the real parts): sit cars with the child up to head height, the wing car's
## outboard seats, the suspended car and rider below the rails. With `track`, the rails and ties are included.
func clearance_box(track := true) -> AABB:
	var low := -0.25 if track else -0.05
	match seat_type:
		"wing":
			return AABB(Vector3(-2.9,low,-1.6),Vector3(5.8,2.1-low,3.2))
		"invert":
			return AABB(Vector3(-gauge-0.45,-2.6,-1.6),Vector3(2*gauge+0.9,(0.6 if track else 0.45)+2.6,3.2))
	return AABB(Vector3(-gauge-0.35,low,-1.6),Vector3(2*gauge+0.7,2.1-low,3.2))

## Whether the support segment a..b (line space) stays out of the train and rider at every frame. Within `near`
## frames of its own frame `own` only the part of the car away from the rails counts (the support's own mounting).
func _clear_of_train(a: Vector3, b: Vector3, own: int, near: int) -> bool:
	if _frame_cells.is_empty():
		for j in frames.size():
			var cell := Vector2i(floori(frames[j].origin.x/6),floori(frames[j].origin.z/6))
			if not _frame_cells.has(cell): _frame_cells[cell] = PackedInt32Array()
			_frame_cells[cell].append(j)
	var room := clearance_box(false).grow(0.25)
	var body := room
	if seat_type=="invert":
		body.size.y = room.size.y-0.45-0.25
	else:
		body.position.y = 0.25
		body.size.y = room.end.y-0.25
	# beside the support's own top: the rails and the wheels on them (a support out of a steeply banked frame)
	var inner := gauge-0.32
	var sides := [AABB(Vector3(room.position.x,-0.25,room.position.z),Vector3(-inner-room.position.x,0.8,room.size.z)),
		AABB(Vector3(inner,-0.25,room.position.z),Vector3(room.end.x-inner,0.8,room.size.z))]
	for x in range(floori((minf(a.x,b.x)-5)/6),floori((maxf(a.x,b.x)+5)/6)+1):
		for z in range(floori((minf(a.z,b.z)-5)/6),floori((maxf(a.z,b.z)+5)/6)+1):
			for j in _frame_cells.get(Vector2i(x,z),PackedInt32Array()):
				var d := absi(j-own)
				var la: Vector3 = frames[j].affine_inverse()*a
				var lb: Vector3 = frames[j].affine_inverse()*b
				if mini(d,frames.size()-d) > near:
					if room.intersects_segment(la,lb): return false
				elif body.intersects_segment(la,lb) or sides[0].intersects_segment(la,lb) or sides[1].intersects_segment(la,lb): return false
	return true

## unified r6 (clearance audit): the tallest vertical semi-axis an ellipsoid hill (centre and semi-axes in the park's
## space, where this line is placed) may have and still stay 0.3 m below this ride's track, train and rider.
func hill_room(center: Vector3, semi: Vector3) -> float:
	var room := clearance_box()
	var corners: Array[Vector3] = []
	var r := 0.0
	for k in 8:
		corners.append(room.get_endpoint(k))
		r = maxf(r, corners[k].length())
	r += 0.3
	if _chunks.is_empty():
		for start in range(0,frames.size(),32):
			var box := AABB(transform*frames[start].origin,Vector3.ZERO)
			for i in range(start,mini(start+32,frames.size())): box = box.expand(transform*frames[i].origin)
			_chunks.append([box,start])
	var near := AABB(center-semi,semi*2).grow(r)
	var top := semi.y
	for chunk in _chunks:
		if not near.intersects(chunk[0]): continue
		for i in range(chunk[1],mini(chunk[1]+32,frames.size())):
			var p := transform*frames[i].origin
			var hx := maxf(0,absf(p.x-center.x)-r)/semi.x
			var hz := maxf(0,absf(p.z-center.z)-r)/semi.z
			var h2 := hx*hx+hz*hz
			if h2 >= 1: continue
			var low := INF
			for c in corners: low = minf(low,(transform*(frames[i]*c)).y)
			top = minf(top,maxf(0.0,low-0.3-center.y)/sqrt(1.0-h2))
	return top

func place(s: float) -> void:
	distance = s
	for i in cars.size():
		cars[i].transform = sample(s - pitch * i)
		for j in 4:
			var side := -1.0 if j<2 else 1.0
			var offset := 0.76 if j%2==0 else -0.76
			var bogie := sample(s-pitch*i+offset)
			wheels[4*i+j].transform = bogie*Transform3D(Basis(Vector3.BACK,PI/2),Vector3(side*gauge,0.235,0))

func depart() -> void:
	elapsed = 0
	moving = true

func advance(dt: float) -> void:
	if not moving: return
	elapsed += dt
	var t := elapsed * 20
	if t >= timetable.size()-1:
		moving = false
		place(stop)
		return
	var i := floori(t)
	var a := float(timetable[i][0])
	var length := frames.size()*ds
	var delta := fposmod(float(timetable[i+1][0])-a+length*0.5,length)-length*0.5
	place(fposmod(a+delta*(t-i),length))
