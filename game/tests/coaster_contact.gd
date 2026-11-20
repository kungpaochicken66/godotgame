extends SceneTree

const Line := preload("res://scripts/world/coaster_line.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var count := 0
	var worst := 0.0
	var expected := 0
	for file in DirAccess.get_files_at("res://coasters"):
		if file.get_extension()!="json": continue
		var id := file.get_basename()
		var ride := Line.new()
		root.add_child(ride)
		ride.setup(id,id,Color.WHITE,0)
		assert(ride.frames.size()>0 and ride.wheels.size()==12)
		expected += ride.frames.size()*12
		for i in ride.frames.size():
			var front := i * ride.ds
			ride.place(front)
			for w in ride.wheels.size():
				var wheel := ride.wheels[w]
				var side := -1.0 if w%4<2 else 1.0
				var car := floori(w/4.0)
				var bogie_s := front - car * ride.pitch + (0.76 if w%2==0 else -0.76)
				var frame := ride.sample(bogie_s)
				# Compare the bottom of the wheel tread with the top of the actual straight rail beam
				# between adjacent mesh samples, independently of the wheel placement routine.
				var t := fposmod(bogie_s/ride.ds,ride.frames.size())
				var k := floori(t)
				var a := ride.frames[k]
				var b := ride.frames[(k+1)%ride.frames.size()]
				var rail_point := (a * Vector3(side*ride.gauge,0.065,0)).lerp(b * Vector3(side*ride.gauge,0.065,0),t-k)
				var tread := wheel.position-frame.basis.y*0.17
				worst=maxf(worst,tread.distance_to(rail_point))
				count+=1
		ride.free()
	print("WHEEL CONTACT samples=",count," max_error_m=",worst)
	quit(0 if worst<0.005 and count==expected else 1)
