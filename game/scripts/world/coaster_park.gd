extends Node3D

const Line := preload("res://scripts/world/coaster_line.gd")
const Kit := preload("res://scripts/art/mesh_kit.gd")
const Kid := preload("res://scripts/art/kid.gd")
const UI := preload("res://scripts/ui/ui_kit.gd")
const NAMES := ["Honeybee Hills","Comet Express","Jade Dragon Spiral","Crystal Mine","Neon Wings","Phantom Castle"]
const IDS := ["orchard-breeze","comet-run","copper-coil","crystal-mine","neon-wings","phantom-castle"]
const VIEWS := ["Rider eye","Chase","Trackside"]
var host: Node
var lines: Array[Line] = []
var kid := Kid.new()
var cam := Camera3D.new()
var panel := CanvasLayer.new()
var shortcuts := VBoxContainer.new()
var hint_panel: PanelContainer   # unified r6: UI.hint_panel(), built in setup()
var hint: Label
var using_pad := false
## unified r6: the selected card shows the shared focus ring (UI.focus_box), as a focused button in every world
var focus_border := UI.focus_box(16)
var selected := 0
var cards: Array[Button] = []
var action: Button
## unified r4: "Ride home" beside "Board train" at a platform, so the child need not walk back to the central tram.
var home_action: Button
var label: Label
var active: Line
var view := 0
var spectator_origin := Vector3.ZERO
var spectator_post := -1
var goal := Vector3.ZERO
var axes := Vector2.ZERO
var exit_point := Vector3(0,0.56,0)
var shuttle := Node3D.new()
var ending := false
var journey := 1.2
var tv_mode_before: int
var riding_home := false
## The shuttle's run for the current journey (arrival: into the centre; home: away from the centre or a platform).
var shuttle_from := Vector3(-2,0.55,-12)
var shuttle_to := Vector3(-2,0.55,0)

func setup(main: Node) -> void:
	host = main
	using_pad = main.pad.shown or OS.has_feature("tvos")
	Input.joy_connection_changed.connect(_park_connection)
	main.pad._reset()
	main.add_child(self)
	main.world.hide()
	main.world.process_mode = Node.PROCESS_MODE_DISABLED
	main.controller.process_mode = Node.PROCESS_MODE_DISABLED
	main.rig.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.hide()
	main.pad.process_mode = Node.PROCESS_MODE_DISABLED
	main.pad.hide()
	if main.tv_remote:
		tv_mode_before = main.tv_remote.process_mode
		main.tv_remote.process_mode = Node.PROCESS_MODE_DISABLED
	var colors := [Color("#e9a62f"),Color("#e45c4e"),Color("#228c78"),Color("#99663b"),Color("#43dfbf"),Color("#665080")]
	for i in IDS.size():
		var line := Line.new()
		add_child(line)
		line.setup(IDS[i],NAMES[i],colors[i],TAU*i/IDS.size())
		lines.append(line)
		var delta := line.board-exit_point
		var path := Node3D.new()
		add_child(path)
		path.position = (line.board+exit_point)*0.5
		path.rotation.y = atan2(delta.x,delta.z)
		Kit.box(path,Vector3(5,0.16,delta.length()+1),Color("#dfc099"),Vector3(0,-0.1,0))
	Kit.box(self,Vector3(1600,1,1600),Color("#8eb789"),Vector3(0,-4.5,0))
	Kit.cyl(self,5,5,0.6,Color("#d9b28a"),Vector3(0,0.24,0))
	add_child(kid)
	kid.setup(Session.players[Session.my_id]["avatar"], false)
	add_child(shuttle)
	Kit.box(shuttle,Vector3(2.6,0.38,4.8),Color("#5e8f82"),Vector3(0,0.48,0))
	Kit.box(shuttle,Vector3(2.7,0.20,5.0),Color("#eebc63"),Vector3(0,2.3,0))
	for side in [-1,1]:
		for z in [-1.8,1.8]:
			Kit.cyl(shuttle,0.075,0.075,1.7,Color("#947244"),Vector3(side*1.16,1.45,z))
			Kit.cyl(shuttle,0.28,0.28,0.22,Color("#49505a"),Vector3(side*1.17,0.27,z),Vector3(0,0,90))
	shuttle.position = Vector3(-2,0.55,-12)
	var garden := Node3D.new()
	add_child(garden)
	for line in lines:
		var direction := Vector3(line.board.x,0,line.board.z).normalized()
		var side := direction.cross(Vector3.UP)
		for k in range(8,int(line.board.length())-3,7):
			var at := direction*k
			var sign_side := 1.0 if k%2==0 else -1.0
			var tree_at := at+side*sign_side*5
			Kit.cyl(garden,0.22,0.33,4.3,Color("#795640"),tree_at+Vector3.UP*(-1.6))
			Kit.ball(garden,2.05,Color("#679d76"),tree_at+Vector3.UP*1.4,Vector3(1,1.25,1))
			Kit.ball(garden,1.46,Color("#8abb81"),tree_at+Vector3(0.8,2.7,0.3))
			var lamp_at := at-side*2
			Kit.cyl(garden,0.07,0.11,2.65,Color("#73584a"),lamp_at+Vector3.UP*1.85)
			Kit.ball(garden,0.36,Color("#f4ab67"),lamp_at+Vector3.UP*3.28,Vector3(1,1.2,1))
			Kit.cyl(garden,0.18,0.25,0.11,Color("#925648"),lamp_at+Vector3.UP*3.69)
	# Set the Workshop's fountain, striped tent and balloon between paths.
	for i in 3:
		var angle := (i*2+0.5)*TAU/lines.size()
		var at := Vector3(sin(angle),0,cos(angle))*21.5
		Kit.cyl(garden,5.3,5.6,4.3,Color("#91ab75"),at-Vector3.UP*1.85)
		if i==0:
			Kit.cyl(garden,3.1,3.3,0.55,Color("#e0bd91"),at+Vector3.UP*0.4)
			Kit.cyl(garden,2.85,2.85,0.13,Color("#61b4bf"),at+Vector3.UP*0.72)
			Kit.cyl(garden,0.25,0.5,1.8,Color("#ddc48e"),at+Vector3.UP*1.5)
			Kit.cyl(garden,1.1,0.45,0.44,Color("#eed5a4"),at+Vector3.UP*2.4)
			Kit.ball(garden,0.30,Color("#96dfec"),at+Vector3.UP*2.95,Vector3(0.8,1.7,0.8))
		elif i==1:
			Kit.cyl(garden,0.10,3.55,2.15,Color("#bf6352"),at+Vector3.UP*3.9)
			Kit.cyl(garden,1.28,2.09,0.50,Color("#ffe4ac"),at+Vector3.UP*4.05)
			for x in [-1.9,1.9]:
				for z in [-1.9,1.9]:
					Kit.cyl(garden,0.09,0.13,3.0,Color("#a5764d"),at+Vector3(x,1.7,z))
		else:
			Kit.box(garden,Vector3(1.55,1.1,1.55),Color("#a4774b"),at+Vector3.UP*4)
			for x in [-0.68,0.68]:
				for z in [-0.68,0.68]:
					Kit.cyl(garden,0.045,0.045,2.65,Color("#886b51"),at+Vector3(x,5.7,z))
			Kit.ball(garden,2.35,Color("#e68a5e"),at+Vector3.UP*9,Vector3(1,1.24,1))
			Kit.cyl(garden,2.32,2.32,0.38,Color("#ffe9ae"),at+Vector3.UP*9.1)
	for i in 24:
		var angle := TAU*i/24
		var at := Vector3(sin(angle),0,cos(angle))*(380.0+25*(i%3))
		# unified r6 (clearance audit): a hill a ride runs through is lowered until it clears that ride (or left out).
		var semi := Vector3(92,39+i%4*7,78)
		for line in lines: semi.y = minf(semi.y,line.hill_room(at-Vector3.UP*12,semi))
		if semi.y > 9.5:
			Kit.ball(garden,1.0,Color("#80a994") if i%2 else Color("#749d90"),at-Vector3.UP*12,semi)
	Kit.merge_parts(garden)
	kid.reparent(shuttle,false)
	kid.anim = "sit"
	kid.position = Vector3(0,0.52,0)
	goal = kid.position
	add_child(cam)
	cam.near = 0.07
	cam.far = 650
	cam.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-56,-36,0)
	add_child(light)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#a8d4de")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e4")
	env.ambient_light_energy = 0.75
	cam.environment = env
	add_child(panel)
	panel.layer = 8
	var root := Control.new()
	panel.add_child(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	root.name = "SafeArea"
	# unified r6 (action UI audit): everything inside the TV's title-safe area, as the town's HUD and the reef (the
	# title stood at x 46 and the action row 26 px from the bottom, inside the overscan margin on a TV).
	UI.fit_safe_area(root)
	get_viewport().size_changed.connect(func(): if is_instance_valid(root): UI.fit_safe_area(root))
	label = UI.label("",28)
	root.add_child(label)
	label.position = Vector2(24,22)
	# unified r6: the controller hint in the shared form (UI.hint_panel: the town's panel, text and spacing) at the
	# safe area's top right, laid out by containers as the reef's (it grows leftward from that corner).
	var hint_area := MarginContainer.new()
	hint_area.name = "PadHintArea"
	root.add_child(hint_area)
	hint_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in ["margin_left","margin_right"]: hint_area.add_theme_constant_override(m,24)
	for m in ["margin_top","margin_bottom"]: hint_area.add_theme_constant_override(m,22)
	var hint_col := VBoxContainer.new()
	hint_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_area.add_child(hint_col)
	var hint_row := HBoxContainer.new()
	hint_row.alignment = BoxContainer.ALIGNMENT_END
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_col.add_child(hint_row)
	hint_panel = UI.hint_panel()
	hint_panel.name = "PadHint"
	hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	hint_row.add_child(hint_panel)
	hint = UI.hint_label()
	hint_panel.add_child(hint)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	actions.name = "Actions"
	actions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	actions.grow_horizontal = Control.GROW_DIRECTION_BOTH
	actions.offset_top = -24-UI.DEST_H
	actions.offset_bottom = -24
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation",14)   # as the town's action row
	# unified r6: the action button as the town's (primary, 88 px, 28 px text); Ride home as every destination
	action = UI.button("Ride home","tram",true,240)
	action.custom_minimum_size.y = UI.DEST_H
	action.add_theme_font_size_override("font_size",28)
	actions.add_child(action)
	action.pressed.connect(interact)
	home_action = UI.button("Ride home","tram",false,240)
	UI.style_destination(home_action)
	home_action.name = "RideHome"
	actions.add_child(home_action)
	home_action.pressed.connect(ride_home)
	home_action.visible = false
	root.add_child(shortcuts)
	shortcuts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shortcuts.offset_top = -440
	shortcuts.offset_bottom = -122
	shortcuts.alignment = BoxContainer.ALIGNMENT_END
	shortcuts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcuts.add_theme_constant_override("separation",12)
	var row: HBoxContainer
	for i in lines.size():
		if i%3==0:
			row = HBoxContainer.new()
			shortcuts.add_child(row)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation",12)
		var btn := UI.button("", "", false, 235)
		row.add_child(btn)
		btn.custom_minimum_size.y = 150
		cards.append(btn)
		var poster := TextureRect.new()
		btn.add_child(poster)
		var path: String = "res://coasters/"+IDS[i]+".jpg"
		if ResourceLoader.exists(path): poster.texture = load(path)
		poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		poster.offset_left = 6
		poster.offset_right = -6
		poster.offset_top = 6
		poster.offset_bottom = -54
		poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := UI.label(tr(NAMES[i]),23)
		btn.add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_top = -50
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.pressed.connect(_board.bind(lines[i]))
		btn.gui_input.connect(_card_input.bind(btn,lines[i]))
	_select_card(0)
	_walk_camera()
	_refresh()

func _walk_camera() -> void:
	cam.global_position = kid.global_position + Vector3(0,9,11)
	cam.look_at(kid.global_position+Vector3.UP*0.7)

func nearby() -> Line:
	for line in lines:
		if kid.global_position.distance_to(line.board) < 3.3: return line
	return null

func _refresh() -> void:
	hint_panel.visible = using_pad and journey<=0
	shortcuts.visible = journey <= 0 and not active and (kid.position.distance_to(exit_point)<3.5 or nearby()!=null)
	if hint_panel.visible: _pad_hint()
	home_action.visible = journey <= 0 and not ending and not active and nearby() != null
	if journey > 0:
		action.visible = false
		label.text = tr("Ride home") if riding_home else tr("Roller Coaster Workshop")
		return
	if active:
		label.text = tr(active.title)+"  ·  "+tr(VIEWS[view])
		action.text = tr("Switch view") if active.moving else tr("Get off")
		action.visible = true
	else:
		var near_line := nearby()
		label.text = tr(near_line.title) if near_line else tr("Roller Coaster Workshop")
		action.visible = near_line != null or kid.position.distance_to(exit_point) < 3.5
		if shortcuts.visible:
			label.text = tr(NAMES[selected]) if using_pad else tr("Choose a coaster to board")
		if action.visible:
			action.text = tr("Board train") if near_line else tr("Ride home")
			action.visible = true

func _pad_hint() -> void:
	var ok: String = host.pad.label_of(host.pad.confirm_button())
	var back: String = host.pad.label_of(host.pad.back_button())
	var parts := PackedStringArray()
	# unified r6: the shared form (UI.hint_part, UI.glyphs, UI.HINT_SEP), as the town's and the reef's hints
	if active:
		if active.moving:
			parts.append(UI.hint_part(UI.glyphs([host.pad.label_of(JOY_BUTTON_LEFT_SHOULDER),host.pad.label_of(JOY_BUTTON_RIGHT_SHOULDER)]),tr("Switch view")))
		else: parts.append(UI.hint_part(ok,tr("Get off")))
	else:
		parts.append(UI.hint_part(tr("Left stick"),tr("Move")))
		if shortcuts.visible:
			parts.append(UI.hint_part(tr("D-pad"),tr("Select")))
			parts.append(UI.hint_part(ok,tr("Board train")))
		# unified r4: off the train, back (B) or + / Start rides home from anywhere, a platform included
		parts.append(UI.hint_part(UI.glyphs([back,host.pad.label_of(JOY_BUTTON_START)]),tr("Ride home")))
	var message := UI.HINT_SEP.join(parts)
	if hint.text!=message:
		hint.text=message
		hint_panel.reset_size()

func _change_view(step: int) -> void:
	view = wrapi(view+step,0,VIEWS.size())
	spectator_post = -1
	_refresh()

func interact() -> void:
	if ending or journey > 0: return
	if active:
		if active.moving:
			_change_view(1)
		else:
			var dock := active.board
			kid.reparent(self,false)
			kid.transform = Transform3D(Basis.IDENTITY,dock)
			kid.show()
			kid.anim = "idle"
			goal = dock
			active = null
			_walk_camera()
	elif nearby():
		_board(nearby())
	elif kid.position.distance_to(exit_point)<3.5:
		ride_home()
		return
	_refresh()

## Off the train the child can always ride home: at the central tram the shuttle leaves from the centre as before;
## anywhere else (a platform) it pulls up on the walkway there and runs toward the centre. Never while riding a train,
## while any train runs, during the shuttle's journey or once leaving; one press starts it, later ones do nothing.
func can_ride_home() -> bool:
	if ending or riding_home or journey > 0 or active: return false
	for line in lines:
		if line.moving: return false
	return true

func ride_home() -> void:
	if not can_ride_home(): return
	riding_home = true
	axes = Vector2.ZERO
	goal = kid.position
	if kid.position.distance_to(exit_point) < 3.5:
		shuttle.rotation.y = 0
		shuttle_from = Vector3(-2,0.55,0)
		shuttle_to = Vector3(-2,0.55,-12)
	else:
		var inward := Vector3(exit_point.x-kid.position.x,0,exit_point.z-kid.position.z)
		var dir := inward.normalized() if inward.length() > 0.01 else Vector3.BACK
		var stop := Vector3(kid.position.x,0.55,kid.position.z) + dir*2.4
		var run := minf(12.0,maxf(0.0,inward.length()-6.0))
		shuttle.rotation.y = atan2(dir.x,dir.z)
		shuttle_from = stop
		shuttle_to = stop + dir*run
	shuttle.position = shuttle_from
	kid.reparent(shuttle,false)
	kid.transform = Transform3D(Basis.IDENTITY,Vector3(0,0.52,0))
	kid.show()
	kid.anim = "sit"
	journey = 1.2
	_refresh()

func _card_input(event: InputEvent, button: Button, line: Line) -> void:
	if event is InputEventScreenTouch and event.pressed:
		button.accept_event()
		_board(line)

func _select_card(index: int) -> void:
	selected = wrapi(index,0,cards.size())
	for i in cards.size():
		if i==selected:
			cards[i].add_theme_stylebox_override("normal",focus_border)
		else: cards[i].remove_theme_stylebox_override("normal")

func _board(line: Line) -> void:
	if ending or journey>0 or active or line.moving: return
	active = line
	view = 0
	kid.reparent(active.cars[0],false)
	kid.transform = Transform3D(Basis(Vector3.UP,PI),active.seat_origin)
	kid.anim = "ride"
	active.depart()
	_ride_camera()
	_refresh()

func _ride_camera() -> void:
	var car := active.cars[0].global_transform
	kid.visible = view != 0
	match view:
		0:
			cam.global_transform = car * Transform3D(Basis.IDENTITY,active.eye)
		1:
			cam.global_transform = car * Transform3D(Basis.IDENTITY,active.seat_origin+Vector3(-2.65 if active.seat_type=="wing" else -4.0,1.9,-3.8))
			cam.look_at(car*(active.seat_origin+Vector3.UP*0.55),car.basis.y)
		2:
			var post := floori(active.distance/36)
			var fixed_frame := active.global_transform*active.sample(post*36+18)
			var target := fixed_frame*Vector3(12,5,0)
			var k := floori(active.distance/active.ds)%active.frames.size()
			if not active.scene_tags.is_empty() and active.scene_tags[k]!=0:
				target = fixed_frame*Vector3(4.7,active.eye.y+0.7,0)
			target.y = maxf(-2.8,target.y)
			if spectator_post == -1:
				spectator_origin = target
			spectator_post = post
			spectator_origin = spectator_origin.lerp(target,1.0-exp(-get_process_delta_time()*4.0))
			cam.global_position = spectator_origin
			cam.look_at(car*(active.seat_origin+Vector3.UP*0.55))

func _process(dt: float) -> void:
	if ending: return
	if journey>0:
		journey = maxf(0,journey-dt)
		shuttle.position = shuttle_from.lerp(shuttle_to,1.0-journey/1.2)
		_walk_camera()
		if journey>0: return
		if riding_home:
			_home()
			return
		kid.reparent(self,false)
		kid.position = exit_point
		goal = exit_point
	if active:
		active.advance(dt)
		_ride_camera()
	else:
		var walk := Vector3(axes.x,0,axes.y)
		if walk.length()>0.18: goal=_on_walkway(kid.position+walk.limit_length()*1.6)
		var next := kid.position.move_toward(goal,dt*6.5)
		var d := next-kid.position
		if d.length()>0.001:
			kid.rotation.y = atan2(d.x,d.z)
			kid.anim = "walk"
		else: kid.anim = "idle"
		kid.position = next
		_walk_camera()
	_refresh()

func _input(event: InputEvent) -> void:
	if not host or ending: return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		using_pad = false
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if host.pad.device!=event.device:
			if host.pad.device==-1 or (event is InputEventJoypadButton and event.pressed):
				axes = Vector2.ZERO
				host.pad._use(event.device)
			else: return
	if event is InputEventJoypadMotion:
		if event.axis==JOY_AXIS_LEFT_X: axes.x=event.axis_value
		if event.axis==JOY_AXIS_LEFT_Y: axes.y=event.axis_value
		if axes.length()>0.18: using_pad = true
	elif event is InputEventJoypadButton and event.pressed:
		using_pad = true
		if journey>0: return
		var role: String = host.pad.role_of(event.button_index)
		if shortcuts.visible and role in ["left","right","up","down"]:
			if role in ["up","down"]: _select_card(selected+3)
			else: _select_card(selected-selected%3+wrapi(selected%3+(1 if role=="right" else -1),0,3))
		elif active and active.moving and role in ["cam_left","cam_right","context"]:
			_change_view(-1 if role=="cam_left" else 1)
		elif active and not active.moving and role=="confirm":
			interact()
		elif shortcuts.visible and role=="confirm":
			_board(lines[selected])
		elif not active and role in ["back","place"]:
			ride_home()   # unified r4: from a platform too (can_ride_home refuses while anything runs)
		elif not active and nearby() and role=="context":
			interact()
		else: return
		get_viewport().set_input_as_handled()

func _park_connection(_device: int, _connected: bool) -> void:
	axes = Vector2.ZERO
	if not active and journey<=0: goal = kid.position

func _unhandled_input(event: InputEvent) -> void:
	if active or journey>0: return
	if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		var p: Variant = Plane(Vector3.UP,exit_point.y).intersects_ray(cam.project_ray_origin(event.position),cam.project_ray_normal(event.position))
		if p != null:
			goal=_on_walkway(p)
			get_viewport().set_input_as_handled()

func _on_walkway(p: Vector3) -> Vector3:
	var best := exit_point
	for line in lines:
		var q := Geometry3D.get_closest_point_to_segment(p,exit_point,line.board)
		if q.distance_to(p)<best.distance_to(p): best=q
	return best

func _home() -> void:
	ending = true
	axes = Vector2.ZERO
	host.pad._reset()   # nothing held or queued from before the Workshop reaches the town
	host.world.process_mode = Node.PROCESS_MODE_INHERIT
	host.controller.process_mode = Node.PROCESS_MODE_INHERIT
	host.rig.process_mode = Node.PROCESS_MODE_INHERIT
	host.pad.process_mode = Node.PROCESS_MODE_INHERIT
	if host.tv_remote: host.tv_remote.process_mode = tv_mode_before
	host.pad.show()
	host.world.show()
	host.hud.show()
	host.rig.camera.current = true
	queue_free()
