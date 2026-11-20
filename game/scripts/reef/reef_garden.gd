## The same native meshes are shared by every instance in a batch.
extends Node3D
const WATERLIGHT = preload("res://scripts/reef/waterlight.gdshader")
const SURFACE = preload("res://scripts/reef/surface.gdshader")
const SHAFTS = preload("res://scripts/reef/shafts.gdshader")
const ROCK = preload("res://assets/reef/rock.res")
const CORAL = preload("res://assets/reef/coral.res")
const SPONGE = preload("res://assets/reef/sponge.res")
const MANTA = preload("res://assets/reef/manta.res")
const FISH = preload("res://assets/reef/fish.res")
const Kit = preload("res://scripts/art/mesh_kit.gd")
var rng := RandomNumberGenerator.new()
var schools: Array[Node3D] = []
var rays: Array[Node3D] = []

static func floor_y(x: float, z: float) -> float:
	return -3.0 + 1.1*sin(x*.18+cos(z*.13))+.7*sin(z*.24+x*.09)

func material(color: String, motion := 0, glow := 0.1, finish := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATERLIGHT
	m.set_shader_parameter("pigment", Color(color))
	m.set_shader_parameter("motion", motion)
	m.set_shader_parameter("glimmer", glow)
	m.set_shader_parameter("finish", finish)
	return m

func place(mesh: Mesh, mat: Material, at: Vector3, size: Vector3, yaw := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat
	node.transform=Transform3D(Basis(Vector3.UP,yaw).scaled_local(size),at)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func batch(mesh: Mesh, mat: Material, poses: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm:=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.mesh=mesh
	mm.instance_count=poses.size()
	for i in poses.size():
		mm.set_instance_transform(i,poses[i])
	var node:=MultiMeshInstance3D.new()
	node.multimesh=mm
	node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func tf(p: Vector3, size: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,yaw).scaled_local(size),p)

func kelp_mesh() -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A twisted central ribbon and two alternating rows of tapered blades.
	for leaf in range(-1,46):
		var theta:=float(leaf)*2.39996
		var radial:=Vector3(cos(theta),0,sin(theta))
		var across:=Vector3(-radial.z,0,radial.x)
		var level:=(leaf+1)*.203
		var length:=rng.randf_range(.60,1.25)*(1.-level*.04)
		for row in 5:
			for k in [0,1,2,2,1,3]:
				var t:float=(row+(k>>1))/5.0
				var side:float=float(k%2)*2.-1.
				var center:=Vector3(.16*sin(level),level,.12*cos(level))
				var pos:=center+radial*(length*t)+Vector3.UP*(.20*t+.48*sin(t*PI)+.12*sin(t*TAU+theta))+across*(side*(.008+.15*sin(t*PI)))
				if leaf==-1:
					pos=Vector3(.16*sin(t*9.5)+side*.047,t*9.5,.12*cos(t*9.5))
				st.set_normal((Vector3.UP+radial*.45).normalized())
				st.set_uv(Vector2((side+1.)*.5,t))
				st.add_vertex(pos)
	return st.commit()

func _ready() -> void:
	rng.seed=71006
	var bed:=PlaneMesh.new()
	bed.size=Vector2(120,120)
	bed.subdivide_width=100
	bed.subdivide_depth=100
	var arrays:=bed.get_mesh_arrays()
	var v:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in v.size():
		var x:=v[i].x
		var z:=v[i].z
		v[i].y=floor_y(x,z)
		normals[i]=Vector3(floor_y(x-.1,z)-floor_y(x+.1,z),.2,floor_y(x,z-.1)-floor_y(x,z+.1)).normalized()
	arrays[Mesh.ARRAY_VERTEX]=v
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	place(mesh,material("91a898",0,.08,2),Vector3.ZERO,Vector3.ONE)
	var stone:=material("526a70",0,.06,1)
	var cliffs:Array[Transform3D]=[]
	for i in 120:
		var z:=rng.randf_range(-48,48)
		var x:float=(-1. if i%2 else 1.)*rng.randf_range(15.,29.)+sin(z*.14)*3.
		cliffs.append(tf(Vector3(x,floor_y(x,z),z),Vector3(rng.randf_range(3.,7.),rng.randf_range(4.,13.),rng.randf_range(4.,8.)),rng.randf()*TAU))
	# Distant headlands close both ends of the valley beyond the swimming area.
	for j in 62:
		var angle:=TAU*j/62.
		var distance:=rng.randf_range(43.,51.)
		var x:=sin(angle)*distance
		var z:=cos(angle)*distance
		cliffs.append(tf(Vector3(x,-4,z),Vector3(rng.randf_range(4,8),rng.randf_range(6,16),rng.randf_range(4,8)),angle))
	# An arch silhouettes the central channel.
	for j in 13:
		var a:float=j*PI/12
		cliffs.append(tf(Vector3(8.5*cos(a)-1.,floor_y(-1,-17)+9.*sin(a),-17),Vector3(2.6,2.2,2.7),a))
	for i in 7:
		cliffs.append(tf(Vector3(rng.randf_range(-15,15),rng.randf_range(8.,13.),rng.randf_range(-36,-21)),Vector3(1.7,1.0,2.0),rng.randf()*TAU))
	batch(ROCK,stone,cliffs)
	var barrier:=StaticBody3D.new()
	barrier.collision_layer=1<<29
	barrier.collision_mask=0
	add_child(barrier)
	var hull:=ROCK.create_convex_shape()
	for t in cliffs:
		var collision:=CollisionShape3D.new()
		collision.shape=hull
		collision.transform=t
		barrier.add_child(collision)
	place(preload("res://assets/reef/fluke.res"),material("a5b9b2"),Vector3(-6,floor_y(-6,-9),-9),Vector3.ONE*.58,.33)
	place(preload("res://assets/reef/wreck.res"),material("b77f45",0,.18,3),Vector3(3,.35,-28),Vector3.ONE*.52,-.25).rotation.z=.15
	var blade:=kelp_mesh()
	for region in 3:
		var transforms:Array[Transform3D]=[]
		for i in 185:
			var z:=rng.randf_range(-38,31)
			var x:=rng.randf_range(-23,23)
			if absf(x)<5.8 or Vector2(x+6,z+9).length()<4.0 or Vector2(x-8,z+19).length()<6.5:
				continue
			var h:=rng.randf_range(.4,1.65)
			if region==2:h*=.28
			transforms.append(tf(Vector3(x,floor_y(x,z),z),Vector3(1.,h,1.),rng.randf()*TAU))
		batch(blade,material(["558c39","899b40","c76bba"][region],1,.17),transforms)
	for group in 5:
		var transforms:Array[Transform3D]=[]
		for cluster in 26:
			var cx:=rng.randf_range(-16,16)
			var cz:=rng.randf_range(-33,27)
			var growth:=rng.randf_range(.48,1.12)
			for i in 9:
				var x:=cx+rng.randfn(0,1.05)
				var z:=cz+rng.randfn(0,.83)
				var size:=growth*rng.randf_range(.4,1.24)
				transforms.append(tf(Vector3(x,floor_y(x,z)-.06,z),Vector3.ONE*size,rng.randf()*TAU))
		batch(SPONGE if group<2 else CORAL,material(["d78c48","b55c87","ed6899","9d5cbb","e78876"][group]),transforms)
	var sheet:=PlaneMesh.new()
	sheet.size=Vector2(140,140)
	var sm:=ShaderMaterial.new()
	sm.shader=SURFACE
	place(sheet,sm,Vector3.UP*16.,Vector3.ONE)
	var shaft:=QuadMesh.new()
	shaft.size=Vector2(2.4,21)
	var beam:=ShaderMaterial.new()
	beam.shader=SHAFTS
	for i in 31:
		var shaft_node:=place(shaft,beam,Vector3(rng.randf_range(-23,23),7,rng.randf_range(-38,24)),Vector3.ONE,rng.randf_range(-.65,.65))
		shaft_node.rotation.z=-.21
	for i in 3:
		rays.append(place(MANTA,material("526a91",2),Vector3.ZERO,Vector3.ONE*(1.25+i*.2)))
	for i in 5:
		var fish:Array[Transform3D]=[]
		for j in 38:
			fish.append(tf(Vector3(rng.randfn(0,1.8),rng.randfn(0,.53),rng.randfn(0,.8)),Vector3.ONE*rng.randf_range(.25,.43)))
		schools.append(batch(FISH,material(["a3d7bf","d6b86a"][i%2],3),fish))
	for mark in [Vector3(-3.5,1.65,4),Vector3(3.,2.1,-5),Vector3(-3.,1.8,-14),Vector3(4.5,2.2,-24)]:
		_lantern(Vector3(mark.x,floor_y(mark.x,mark.z),mark.z),mark.y)
	_motes(false)
	_motes(true)

# Brass diving lanterns mark the route between the sculpture and the wreck.
func _lantern(at: Vector3, height: float) -> void:
	var post:=Node3D.new()
	add_child(post)
	post.position=at
	var bronze:=Color("#7d694b")
	var casing:=Color("#385a5b")
	Kit.cyl(post,.065,.095,height,casing,Vector3.UP*height*.5)
	Kit.cyl(post,.38,.20,.15,bronze,Vector3.UP*height)
	Kit.cyl(post,.31,.26,.61,Kit.glow_mat(Color("#ffc677")),Vector3.UP*(height+.37))
	for i in 6:
		var a:=i*TAU/6.
		Kit.cyl(post,.026,.026,.65,casing,Vector3(cos(a)*.29,height+.37,sin(a)*.29))
	Kit.cyl(post,.13,.39,.22,bronze,Vector3.UP*(height+.78))
	Kit.ball(post,.08,bronze,Vector3.UP*(height+.94))
	Kit.merge_parts(post)

func _motes(bubbles: bool) -> void:
	var p:=GPUParticles3D.new()
	p.amount=95 if bubbles else 640
	p.lifetime=9.
	p.preprocess=9.
	p.visibility_aabb=AABB(Vector3(-30,-8,-45),Vector3(60,35,80))
	var process:=ParticleProcessMaterial.new()
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=Vector3(13,1 if bubbles else 7,19)
	process.direction=Vector3.UP
	process.spread=17
	process.gravity=Vector3.ZERO
	process.initial_velocity_min=.8 if bubbles else .10
	process.initial_velocity_max=1.8 if bubbles else .29
	process.scale_min=.42
	process.scale_max=1.2
	p.process_material=process
	var sphere:=SphereMesh.new()
	sphere.radius=.062 if bubbles else .027
	sphere.height=sphere.radius*2.
	sphere.radial_segments=8
	sphere.rings=3
	var m:=StandardMaterial3D.new()
	m.albedo_color=Color("#89dee4") if bubbles else Color("#d0e698")
	m.emission_enabled=true
	m.emission=m.albedo_color
	m.emission_energy_multiplier=.7
	sphere.material=m
	p.draw_pass_1=sphere
	p.position=Vector3(0,-2 if bubbles else 4,-6)
	add_child(p)

func animate(t: float) -> void:
	for i in schools.size():
		var a:=t*.12+i*1.257
		schools[i].position=Vector3(cos(a)*10,3.+i*.7+sin(a*3.)*.7,-10+sin(a)*9.)
		schools[i].rotation.y=-a-PI*.5
	for i in rays.size():
		var a:=t*.095+2.1*i
		rays[i].position=Vector3(9*cos(a),7.+sin(a*2.)*1.5,-9+9*sin(a))
		rays[i].rotation.y=-a
