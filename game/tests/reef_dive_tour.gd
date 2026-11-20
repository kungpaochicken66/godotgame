## Run via main's --driver=res://tests/reef_dive_tour.gd --reef-output=<directory>.
## unified r1: enters from the town's tram stop ("Explore the lantern reef"); the rest is the Mac's delivered tour.
extends Node
const Avatar=preload("res://scripts/core/avatar.gd")
var main: Node
var output: String
var dive: Node
var result := {"checks": [], "gpu_ms": [], "frame_ms": []}

func check(ok: bool, message: String) -> void:
	result.checks.append({"pass":ok,"check":message})
	print("REEF ",ok," ",message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	output=main.args.get("reef-output","user://reef-validation")
	DirAccess.make_dir_recursive_absolute(output)
	Session.start_solo(output.path_join("test-town.json"),Avatar.PRESETS[1])
	await get_tree().process_frame
	# unified r1: the reef's entry is at the town's tram stop (beside Thousand Town and the Workshop), not in the guide.
	var board=preload("res://scripts/core/town_model.gd").tram_stop_boarding(Session.model)
	main.controller._walk_to(board,{})
	for i in 600:
		if main.hud._reef_btn.is_visible_in_tree():break
		await get_tree().process_frame
	var entry:Button=main.hud._reef_btn if main.hud._reef_btn.is_visible_in_tree() else null
	check(entry!=null,"Station entry")
	if entry==null:
		get_tree().quit(1)
		return
	entry.pressed.emit()
	await get_tree().process_frame
	dive=main.reef
	check(dive.child.avatar.nick=="Sky","Selected town child")
	check(not main.hud.visible and not main.controller.enabled,"Town controls hidden")
	var start:Vector3=dive.swimmer.position
	var key:=InputEventKey.new()
	key.keycode=KEY_W
	key.pressed=true
	Input.parse_input_event(key)
	await get_tree().create_timer(.45).timeout
	key=key.duplicate()
	key.pressed=false
	Input.parse_input_event(key)
	check(start.distance_to(dive.swimmer.position)>.25,"Forward swimming")
	for i in 4:dive.switch_view()
	check(dive.view_mode==0 and dive.child.visible,"All four camera modes cycle")
	var pad:=InputEventJoypadButton.new()
	pad.button_index=JOY_BUTTON_Y
	pad.pressed=true
	dive._input(pad)
	check(dive.view_mode==1,"Controller camera action")
	for i in 3:dive.switch_view()
	dive.controls.hide()
	var points:=[Vector3(1,1.9,8),Vector3(-8.0,4.5,-28.5),Vector3(-5,2.5,1),Vector3(0,3.3,-3),Vector3(1,4.,-8),Vector3(-1,1.2,1)]
	var targets:=[Vector3(-3,4.,-13),Vector3(3,3.2,-28),Vector3(-6,4.,-9),Vector3(-4,4.,-10),Vector3(1,12.,-18),Vector3(-6,.6,-5)]
	for i in 6:
		dive.swimmer.position=points[i]
		dive.swimmer.velocity=Vector3.ZERO
		var v:Vector3=(targets[i]-points[i]).normalized()
		dive.yaw=atan2(-v.x,-v.z)
		dive.pitch=asin(v.y)
		dive.view_mode=2 if i==3 else (1 if i==1 or i==5 else 0)
		dive.child.visible=dive.view_mode!=1
		await get_tree().create_timer(.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(output.path_join("pose-%d.jpg"%(i+1)),.94)
	var vp:=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp,true)
	_route(0.)
	await get_tree().create_timer(1.).timeout
	var rd:=RenderingServer.get_rendering_device()
	var stamps:Dictionary={}
	if rd:
		RenderingServer.frame_pre_draw.connect(_stamp_begin)
		RenderingServer.frame_post_draw.connect(_stamp_end)
	var start_us:=Time.get_ticks_usec()
	var last:=start_us
	var frames:PackedFloat64Array=[]
	var gpu:PackedFloat64Array=[]
	dive.view_mode=0
	while Time.get_ticks_usec()-start_us<60000000:
		await get_tree().process_frame
		var now:=Time.get_ticks_usec()
		var t:float=(now-start_us)/1000000.
		frames.append((now-last)/1000.)
		if rd:
			var stamp_frame:=rd.get_captured_timestamps_frame()
			if not stamps.has(stamp_frame):
				var start_gpu:=-1
				for i in rd.get_captured_timestamps_count():
					var tag:=rd.get_captured_timestamp_name(i)
					if tag=="reef.begin":start_gpu=rd.get_captured_timestamp_gpu_time(i)
					elif tag=="reef.end" and start_gpu>0:
						var duration:=rd.get_captured_timestamp_gpu_time(i)-start_gpu
						if duration>0:gpu.append(duration*.001)
				stamps[stamp_frame]=true
		if not rd:
			var ms:=RenderingServer.viewport_get_measured_render_time_gpu(vp)
			if ms>0:gpu.append(ms)
		last=now
		_route(t)
	result["frame_ms"]=frames
	result["gpu_ms"]=gpu
	if rd:
		RenderingServer.frame_pre_draw.disconnect(_stamp_begin)
		RenderingServer.frame_post_draw.disconnect(_stamp_end)
	result["size"]=[get_viewport().size.x,get_viewport().size.y]
	result["renderer"]=RenderingServer.get_current_rendering_method()
	result["adapter"]=RenderingServer.get_video_adapter_name()
	result["scale_3d"]=get_viewport().scaling_3d_scale
	RenderingServer.viewport_set_measure_render_time(vp,false)
	if main.args.has("reef-clip"):
		var marker:=FileAccess.open(output.path_join("recording.started"),FileAccess.WRITE)
		marker.close()
		var clip_start:=Time.get_ticks_usec()
		var next:=clip_start
		var times:=PackedFloat64Array()
		while Time.get_ticks_usec()-clip_start<7000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			_route(1.+(now-clip_start)*.000001)
			if now>=next:
				await RenderingServer.frame_post_draw
				var image:=get_viewport().get_texture().get_image()
				image.resize(960,540,Image.INTERPOLATE_BILINEAR)
				image.save_jpg(output.path_join("motion-%03d.jpg"%times.size()),.90)
				times.append((now-clip_start)*.000001)
				next=now+40000
		result["clip_seconds"]=times
	var back:=InputEventKey.new()
	back.keycode=KEY_ESCAPE
	back.pressed=true
	dive._input(back)
	check(main.reef==null and main.hud.visible and main.controller.enabled and main.rig.camera.current,"Return to town")
	var file:=FileAccess.open(output.path_join("run.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	await get_tree().process_frame
	get_tree().quit()

func _route(t:float) -> void:
	var a:=t*TAU/60.
	dive.swimmer.position=Vector3(1.+3.8*sin(a),2.8+1.6*sin(a*2.),-7.+13.*cos(a))
	var head:=Vector3(3.8*cos(a),1.4*cos(a*2.),-13.*sin(a)).normalized()
	dive.yaw=atan2(-head.x,-head.z)
	dive.pitch=asin(head.y)

func _stamp_begin() -> void:
	RenderingServer.get_rendering_device().capture_timestamp("reef.begin")

func _stamp_end() -> void:
	RenderingServer.get_rendering_device().capture_timestamp("reef.end")
