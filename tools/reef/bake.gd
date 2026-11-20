extends SceneTree
func _initialize() -> void:
	for id in ["wreck","fluke","manta","fish","rock","coral","sponge"]:
		var file := FileAccess.open("res://../build/reef/"+id+".bin",FileAccess.READ)
		var count := file.get_32()
		var triangles := file.get_32()
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var weights := PackedColorArray()
		for i in count:
			positions.append(Vector3(file.get_float(),file.get_float(),file.get_float()))
			var n := file.get_buffer(4)
			normals.append(Vector3(n.decode_s8(0),n.decode_s8(1),n.decode_s8(2)).normalized())
			weights.append(Color(n.decode_s8(3)/254.0+.5,0,0,1))
		var idx := file.get_buffer(triangles*4).to_int32_array()
		for i in range(0,idx.size(),3):
			var tmp:=idx[i+1]
			idx[i+1]=idx[i+2]
			idx[i+2]=tmp
		var a: Array=[];a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX]=positions;a[Mesh.ARRAY_NORMAL]=normals;a[Mesh.ARRAY_INDEX]=idx;a[Mesh.ARRAY_COLOR]=weights
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
		assert(ResourceSaver.save(mesh,"res://assets/reef/"+id+".res",ResourceSaver.FLAG_COMPRESS)==OK)
	quit()
