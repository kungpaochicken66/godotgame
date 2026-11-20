extends "res://tests/zoo_tour.gd"

const Park := preload("res://scripts/world/coaster_park.gd")
var park: Park

func _pad_press(button := JOY_BUTTON_Y) -> void:
	for down in [true,false]:
		var input := InputEventJoypadButton.new()
		input.set_meta("synthetic", true)   # injected by this test driver, not hardware
		input.button_index=button
		input.pressed=down
		Input.parse_input_event(input)
		await frames(1)

func _walk_park(target: Vector3, stick: bool) -> bool:
	for i in 240:
		var diff := target-park.kid.global_position
		if diff.length()<1.2:
			_axis(JOY_AXIS_LEFT_X,0)
			_axis(JOY_AXIS_LEFT_Y,0)
			return true
		if stick:
			var direction := diff.normalized()
			_axis(JOY_AXIS_LEFT_X,direction.x)
			_axis(JOY_AXIS_LEFT_Y,direction.z)
		else:
			var step := park.kid.global_position + diff.limit_length(3)
			await tap(park.cam.unproject_position(step))
		await wait(0.17)
	return false

func _touch_button(button: Button) -> void:
	var pos := get_viewport().get_final_transform() * button.get_global_rect().get_center()
	for down in [true,false]:
		var finger := InputEventScreenTouch.new()
		finger.index = 0
		finger.position = pos
		finger.pressed = down
		Input.parse_input_event(finger)
		await frames(1)

func _capture(name: String) -> void:
	if main.args.has("no-shots"): return
	await RenderingServer.frame_post_draw
	var target := "%s/%s.png" % [shots,name]
	check(get_viewport().get_texture().get_image().save_png(target)==OK,"saved "+name)

func _run() -> void:
	tv=main.args.has("tv")
	if main.args.has("park-locale"): I18n.set_locale(main.args["park-locale"],false)
	Session.start_solo("user://coaster-tour.json",main.menus.avatar)
	await wait(1)
	await settle_camera()
	await walk_to(TownModel.tram_stop_boarding(Session.model))
	await until(func(): return main.hud._workshop_btn.is_visible_in_tree(),8)
	check(main.hud._workshop_btn.is_visible_in_tree(),"workshop offered at the town tram")
	if tv:
		await _pad_press(JOY_BUTTON_START)
		await frames(6)
	else: await _touch_button(main.hud._workshop_btn)
	for node in main.get_children():
		if node is Park: park=node
	if not park:
		check(false,"arrived at the workshop")
		_finish()
		return
	await wait(1.4)
	check(park.cam.current and park.kid.avatar==main.world.kids[Session.my_id].avatar,"walking camera and own child at arrival")
	await _capture("arrival")
	for i in park.lines.size():
		var line := park.lines[i]
		if i==2 and not tv:
			check(await _walk_park(park.exit_point,true),"walk to junction")
			check(await _walk_park(line.board,true),"walk to dragon platform")
			await _pad_press()
		else:
			check(park.shortcuts.visible,"quick boarding available")
			if tv:
				if i==3: await _pad_press(JOY_BUTTON_DPAD_DOWN)
				if i>0: await _pad_press(JOY_BUTTON_DPAD_RIGHT)
				await _pad_press(main.pad.confirm_button())
			elif i==1: await tap(park.cards[i].get_global_rect().get_center())
			else: await _touch_button(park.cards[i])

		if not line.moving:
			check(false,"board stopped train "+line.title)
			_finish()
			return
		check(park.kid.get_parent()==line.cars[0],"child attached to lead car")
		if tv and i==0:
			check(park.hint_panel.visible and park.hint.text.contains(main.pad.label_of(JOY_BUTTON_LEFT_SHOULDER)),"layout-specific ride hints")
			await _pad_press(JOY_BUTTON_LEFT_SHOULDER)
			check(park.view==2,"previous camera wraps to trackside")
			await _pad_press(main.pad.back_button())
			check(line.moving and park.view==2,"back cannot exit a moving train")
			await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
		var seat := park.kid.transform
		var saw_roll := false
		var saw_scenery := false
		if i==0 or i==2:
			await wait(3)
			await _pad_press()
			await _capture("chase_"+str(i))
		var targets: PackedStringArray = main.args.get("marks","0,0,0").split(",") if i==1 else PackedStringArray()
		var names := ["climb","drop","turn"]
		var next := 0
		while line.moving:
			await frames(1)
			if i>=3 and not saw_scenery:
				var k := floori(line.distance/line.ds)%line.frames.size()
				if line.scene_tags[k]!=0:
					saw_scenery = true
					check(line.moving,"train entered authored scenery "+line.title)
					await wait(0.5)
					await _pad_press()
					await _capture("chase_"+str(i))
					await _pad_press()
					await _pad_press()
					var eye := line.cars[0].to_local(park.cam.global_position)
					check(eye.distance_to(line.eye)<0.02 and park.kid.position.is_equal_approx(line.seat_origin),"native rider eye and seat "+line.title)
					await _capture("eye_"+str(i))
			if i>=4 and not saw_roll and line.cars[0].global_basis.y.y < -0.7:
				saw_roll = true
				check(park.kid.transform.is_equal_approx(seat),"seat stable through inversion "+line.title)
				await _capture("inversion_"+str(i))
			if next<targets.size() and line.elapsed>=float(targets[next]):
				var before := line.elapsed
				var before_s := line.distance
				var old_view := park.view
				if next==1 and not tv: await _touch_button(park.action)
				else: await _pad_press(JOY_BUTTON_RIGHT_SHOULDER)
				check(park.view==(old_view+1)%3 and line.elapsed>=before and line.elapsed-before<1.0,"camera switch preserves progress: "+names[next])
				check(absf(line.distance-before_s)<20 and park.kid.transform.is_equal_approx(seat),"seat transform stable: "+names[next])
				await _capture(names[next]+"_"+str(park.view))
				next+=1
		if i>=3: check(saw_scenery,"authored scene visited "+line.title)
		if i>=4: check(saw_roll,"rode through inversion "+line.title)
		check(next==targets.size() and is_equal_approx(line.distance,line.stop),"completed lap at departure platform: "+line.title)
		if i==1: await _capture("station_"+str(i))
		if tv: await _pad_press(main.pad.confirm_button())
		else: await _touch_button(park.action)
		check(not park.active and park.kid.get_parent()==park and park.kid.position.distance_to(line.board)<1.0,"disembarked onto platform")
	check(await _walk_park(park.exit_point,true),"walk to return tram")
	await _pad_press(main.pad.back_button())
	await until(func(): return not is_instance_valid(park),4.0)
	print("RETURN space=",main.controller.space," journey=",main.controller.journey_to," cam=",main.rig.camera.current," hud=",main.hud.visible)
	check(not is_instance_valid(park) and main.rig.camera.current and main.hud.visible and main.controller.space=="town","walking controls, HUD and camera restored at town stop")
	await _capture("home")
	print("COASTER TOUR ",_checks," checks, ",failures," failures")
	_finish()
