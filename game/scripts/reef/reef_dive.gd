## Local destination. Town membership, inventory and the player's town-space transform stay in Session.
extends Node3D
signal return_requested
const Garden = preload("res://scripts/reef/reef_garden.gd")
const Kid = preload("res://scripts/art/kid.gd")
const Kit = preload("res://scripts/art/mesh_kit.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Palette = preload("res://scripts/core/palette.gd")
const VIEWS = ["Follow camera", "Diver view", "Portrait camera", "Free camera"]
var avatar: Dictionary
var swimmer:=CharacterBody3D.new()
var child:=Kid.new()
var garden:=Garden.new()
var camera:=Camera3D.new()
var controls:=CanvasLayer.new()
var safe:=Control.new()
var view_button: Button
var view_mode:=0
var yaw:=0.0
var pitch:=-.06
var elapsed:=0.0
var phase:=0.0
var touch_move:=Vector2.ZERO
var move_origin:=Vector2.ZERO
var move_touch:=-1
var look_touch:=-1
var touch_lift:=0.
var pad_id:=-1
## unified r4: the town's PadInput (main.pad), used only for its layout: roles and printed labels. It is disabled while
## the dive is open, so the dive takes every joypad event itself. Found from the parent (main) when not set.
var pad: Node
## unified r4: the controller hint panel (top right), shown while a controller is in use, hidden for touch.
var pad_hint: PanelContainer
var top_row: HBoxContainer   # Back and the view button (top left); the hint keeps clear of them
var pad_hint_label: Label
var touch_hint: Label
var using_pad:=false
var free_point:=Vector3.ZERO
var air:=Vector3(0,1.1,8)
var look:=Vector3.FORWARD
var prior_mouse:=Input.MOUSE_MODE_VISIBLE
var _camera_query:=PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	prior_mouse=Input.mouse_mode
	add_child(garden)
	add_child(swimmer)
	swimmer.collision_layer=0
	swimmer.collision_mask=1<<29
	_camera_query.collision_mask=1<<29
	swimmer.motion_mode=CharacterBody3D.MOTION_MODE_FLOATING
	var hit:=CollisionShape3D.new()
	var shape:=SphereShape3D.new()
	shape.radius=.48
	hit.shape=shape
	swimmer.add_child(hit)
	swimmer.position=air
	swimmer.add_child(child)
	var outfit:=avatar.duplicate(true)
	outfit["hat"]=""
	outfit["prop"]=""
	outfit["wear"]={}
	child.setup(outfit,false)
	child.set_process(false)
	child._shadow.hide()
	child._head.rotation.x=-.88
	_suit()
	add_child(camera)
	camera.environment=Environment.new()
	var env:=camera.environment
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("#09374f")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("#a0cdd2")
	env.ambient_light_energy=.49
	env.fog_enabled=true
	env.fog_light_color=Color("#17667d")
	env.fog_density=.049
	env.fog_sun_scatter=.12
	camera.fov=67
	camera.near=.055
	camera.far=90
	camera.make_current()
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-61,-34,0)
	light.light_color=Color("#fff2ca")
	light.light_energy=1.35
	add_child(light)
	_camera_query.exclude=[swimmer.get_rid()]
	if pad==null and get_parent()!=null:pad=get_parent().get("pad")
	using_pad=OS.has_feature("tvos") or (pad!=null and bool(pad.get("shown")))
	_overlay()
	if pad!=null and int(pad.get("device"))>=0:pad_id=int(pad.get("device"))   # the controller the town was played with
	else:
		for id in Input.get_connected_joypads():
			pad_id=id
			break
	Input.joy_connection_changed.connect(_pad_changed)
	_camera()

func _suit() -> void:
	var navy:=Color("#173e50")
	var gold:Color=Palette.paint(child.avatar["outfit_color"])
	Kit.box(child._body,Vector3(.41,.37,.31),navy,Vector3(0,.53,0),.09)
	Kit.cyl(child._body,.108,.108,.35,gold,Vector3(0,.53,-.205))
	for y in [.44,.63]:
		Kit.cyl(child._body,.112,.112,.035,navy,Vector3(0,y,-.205))
	Kit.ball(child._body,.065,Color("#dfba6b"),Vector3(0,.74,-.2))
	for side in [-1,1]:
		Kit.box(child._head,Vector3(.20,.136,.09),navy,Vector3(side*.099,.30,.253),.045)
		Kit.box(child._head,Vector3(.157,.098,.05),Color("#72c7cf"),Vector3(side*.099,.30,.302),.031)
		Kit.ball(child._head,.024,Color("#26444e"),Vector3(side*.101,.30,.33),Vector3(1,1.2,.4))
		Kit.box(child._head,Vector3(.047,.046,.24),navy,Vector3(side*.264,.29,.104),.018)
	Kit.ball(child._head,.061,navy,Vector3(0,.151,.285),Vector3(1.15,.75,.8))
	for leg in child._legs:
		Kit.part(leg,Kit.capsule(.084,.33),navy,Vector3(0,-.16,0))
		Kit.box(leg,Vector3(.165,.052,.36),gold,Vector3(0,-.33,.12),.025)
	for arm in child._arms:
		Kit.part(arm,Kit.capsule(.068,.25),navy,Vector3(0,-.13,0))
		Kit.ball(arm,.069,gold,Vector3(0,-.29,0))

func _overlay() -> void:
	add_child(controls)
	controls.add_child(safe)
	safe.theme=UI.theme()
	safe.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_fit_controls()
	get_viewport().size_changed.connect(_fit_controls)
	var row:=HBoxContainer.new()
	top_row=row
	safe.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	row.position=Vector2(24,22)
	var back:=UI.button("Back","close")
	row.add_child(back)
	back.pressed.connect(func(): return_requested.emit())
	view_button=UI.button(VIEWS[0],"")
	row.add_child(view_button)
	view_button.pressed.connect(switch_view)
	var lift:=HBoxContainer.new()
	safe.add_child(lift)
	lift.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lift.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	lift.grow_vertical=Control.GROW_DIRECTION_BEGIN
	lift.offset_right=-24
	lift.offset_bottom=-22
	for i in 2:
		var btn:=UI.button("Descend" if i==0 else "Ascend","")
		lift.add_child(btn)
		var amount:=float(i*2-1)
		btn.button_down.connect(func():touch_lift=amount)
		btn.button_up.connect(func():touch_lift=0.)
	touch_hint=UI.label("Drag left to swim, right to look",18,Color.WHITE)
	safe.add_child(touch_hint)
	touch_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	touch_hint.offset_left=24
	touch_hint.offset_top=-55
	# unified r4: the controller's buttons, as printed on the controller in use (top right, clear of the touch buttons)
	# unified r5 (Mac's rendered r4 frame: the panel began near x 1780 and ran off the right edge): the panel is laid
	# out by containers anchored to the safe area (a margin box filling it, a row aligned to its end), never by its own
	# offsets, so it always grows leftward from the safe area's top-right corner; _fit_pad_hint() wraps the text when a
	# long locale would not fit beside the Back / view buttons.
	var hint_area:=MarginContainer.new()
	hint_area.name="PadHintArea"
	safe.add_child(hint_area)
	hint_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_area.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint_area.add_theme_constant_override("margin_right",24)
	hint_area.add_theme_constant_override("margin_top",22)
	hint_area.add_theme_constant_override("margin_left",24)
	hint_area.add_theme_constant_override("margin_bottom",22)
	var hint_col:=VBoxContainer.new()
	hint_col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint_area.add_child(hint_col)
	var hint_row:=HBoxContainer.new()
	hint_row.alignment=BoxContainer.ALIGNMENT_END
	hint_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint_col.add_child(hint_row)
	# unified r6 (action UI audit): the shared hint form of every world (UI.hint_panel, UI.hint_label: the town's
	# panel, text colour and size; "glyph  action" parts four spaces apart, alternatives "B / +")
	pad_hint=UI.hint_panel()
	pad_hint.name="PadHint"
	hint_row.add_child(pad_hint)
	pad_hint.size_flags_horizontal=Control.SIZE_SHRINK_END
	pad_hint_label=UI.hint_label()
	pad_hint.add_child(pad_hint_label)
	_show_pad(using_pad)

func _pad_changed(id: int, connected: bool) -> void:
	if connected:
		if pad_id<0:pad_id=id
	elif id==pad_id:pad_id=-1

## The role of a controller button (confirm, back, context, place, ...) as PadInput names it for this layout.
func button_role(button: int) -> String:
	if pad:return str(pad.role_of(button))
	match button:
		JOY_BUTTON_A:return "confirm"
		JOY_BUTTON_B:return "back"
		JOY_BUTTON_Y:return "context"
		JOY_BUTTON_START:return "place"
	return ""

## The letter printed on that button of the controller in use.
func button_label(button: int) -> String:
	if pad:return str(pad.label_of(button))
	match button:
		JOY_BUTTON_A:return "A"
		JOY_BUTTON_B:return "B"
		JOY_BUTTON_Y:return "Y"
		JOY_BUTTON_START:return "Start"
		JOY_BUTTON_BACK:return "Select"
	return "?"

func _axis_label(axis: int) -> String:
	if pad and pad.has_method("label_of_axis"):return str(pad.label_of_axis(axis))
	return "LT" if axis==JOY_AXIS_TRIGGER_LEFT else "RT"

## The controller hint: left stick swims, right stick looks, the triggers rise and sink, the view button, the ways home.
func hint_text() -> String:
	var back:int=pad.back_button() if pad else JOY_BUTTON_B
	var lines:=PackedStringArray()
	lines.append(UI.HINT_SEP.join([UI.hint_part(tr("Left stick"),tr("Swim")),UI.hint_part(tr("Right stick"),tr("Look around"))]))
	lines.append(UI.HINT_SEP.join([UI.hint_part(_axis_label(JOY_AXIS_TRIGGER_RIGHT),tr("Ascend")),UI.hint_part(_axis_label(JOY_AXIS_TRIGGER_LEFT),tr("Descend"))]))
	lines.append(UI.HINT_SEP.join([UI.hint_part(button_label(JOY_BUTTON_Y),tr("Switch view")),
		UI.hint_part(UI.glyphs([button_label(back),button_label(JOY_BUTTON_START),button_label(JOY_BUTTON_BACK)]),tr("Back to town"))]))
	return "\n".join(lines)

func _show_pad(on: bool) -> void:
	using_pad=on
	pad_hint.visible=on
	touch_hint.visible=not on
	if on:
		var text:=hint_text()
		if pad_hint_label.text!=text:
			pad_hint_label.text=text
		_fit_pad_hint.call_deferred()

## unified r5: the hint's width. It keeps its natural width when that fits in the safe area beside the top-left
## buttons, else it wraps at the width that is left (never under 260 px). Called when the text changes, on resize,
## and on a language change; deferred, so the safe area and the buttons have their final sizes.
func _fit_pad_hint() -> void:
	if pad_hint==null or not is_inside_tree():
		return
	var left_used:=(top_row.get_combined_minimum_size().x+24.0) if top_row else 0.0
	var available:=maxf(260.0,safe.size.x-48.0-left_used-24.0-28.0)   # margins, the gap, the panel's own padding
	var font:=pad_hint_label.get_theme_font("font")
	var fs:=pad_hint_label.get_theme_font_size("font_size")
	var natural:=font.get_multiline_string_size(pad_hint_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	if natural>available:
		pad_hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		pad_hint_label.custom_minimum_size.x=available
	else:
		pad_hint_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		pad_hint_label.custom_minimum_size.x=0.0

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and pad_hint_label:
		pad_hint_label.text=""   # rebuilt in the new language and fitted again
		if using_pad:_show_pad(true)

func stick(axis: JoyAxis) -> float:
	if pad_id<0:return 0.
	var n:=Input.get_joy_axis(pad_id,axis)
	return signf(n)*maxf(0.,absf(n)-.16)/.84

func switch_view() -> void:
	view_mode=(view_mode+1)%VIEWS.size()
	if view_mode==3:free_point=camera.position
	child.visible=view_mode!=1
	view_button.text=tr(VIEWS[view_mode])
	_camera()

func _fit_controls() -> void:
	UI.fit_safe_area(safe)
	_fit_pad_hint.call_deferred()

func _input(e: InputEvent) -> void:
	var change_view:=false
	var go_back:=false
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		# unified r4: adopt the device of any controller event (as PadInput does), so a controller works without a
		# connection signal; a pressed button takes over from another controller, a stick only when none is in use.
		if e.device!=pad_id and (pad_id<0 or (e is InputEventJoypadButton and e.pressed)):
			pad_id=e.device
			# unified r5: another controller may have another layout: PadInput learns it (its own layer is paused here)
			# and the hint is rebuilt in that controller's labels and fitted again
			if pad and pad.has_method("_use") and pad.device!=e.device:pad._use(e.device)
			if using_pad:
				pad_hint_label.text=""
				_show_pad(true)
		if e.device==pad_id and (e is InputEventJoypadButton or absf(e.axis_value)>.3) and not using_pad:_show_pad(true)
	if e is InputEventJoypadButton and e.pressed:
		# unified r4: by role, so the button and the hint agree on every layout: the context button (Y; X on a Nintendo
		# pad) changes the view; back (B), + / Start and - / Select return to town. No button does both.
		var role:=button_role(e.button_index)
		change_view=role=="context"
		go_back=role in ["back","place"] or e.button_index==JOY_BUTTON_BACK
		if not change_view and not go_back:
			get_viewport().set_input_as_handled()   # the town's layers are paused; nothing else may act on it
	elif e is InputEventKey and e.pressed and not e.echo:
		change_view=e.keycode==KEY_V
		go_back=e.keycode==KEY_ESCAPE
	elif (e is InputEventScreenTouch or e is InputEventMouseButton) and using_pad and not e.has_meta("pad"):
		_show_pad(false)   # a finger or the mouse took over
	if e is InputEventScreenTouch and not e.pressed:
		if move_touch==e.index:
			move_touch=-1
			touch_move=Vector2.ZERO
		if look_touch==e.index:look_touch=-1
	if change_view or go_back:
		get_viewport().set_input_as_handled()
		if go_back:return_requested.emit()
		else:switch_view()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_RIGHT:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if e.pressed else Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		_turn(e.relative*.003)
	elif e is InputEventScreenTouch:
		if e.pressed:
			if e.position.x<get_viewport().get_visible_rect().size.x*.5 and move_touch<0:
				move_touch=e.index
				move_origin=e.position
			elif look_touch<0:look_touch=e.index
	elif e is InputEventScreenDrag:
		if e.index==look_touch:_turn(e.relative*.004)
		if e.index==move_touch:touch_move=((e.position-move_origin)/80.).limit_length(1.)

func _turn(delta: Vector2) -> void:
	yaw-=delta.x
	pitch=clampf(pitch-delta.y,-1.25,1.25)

func _physics_process(dt: float) -> void:
	elapsed+=dt
	_turn(Vector2(stick(JOY_AXIS_RIGHT_X),stick(JOY_AXIS_RIGHT_Y))*dt*1.9)
	look=Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var x:=float(Input.is_key_pressed(KEY_D))-float(Input.is_key_pressed(KEY_A))+stick(JOY_AXIS_LEFT_X)+touch_move.x
	var f:=float(Input.is_key_pressed(KEY_W))-float(Input.is_key_pressed(KEY_S))-stick(JOY_AXIS_LEFT_Y)-touch_move.y
	var y:=float(Input.is_key_pressed(KEY_E))-float(Input.is_key_pressed(KEY_Q))+touch_lift+stick(JOY_AXIS_TRIGGER_RIGHT)-stick(JOY_AXIS_TRIGGER_LEFT)
	var fast:=Input.is_key_pressed(KEY_SHIFT) or (pad_id>=0 and Input.is_joy_button_pressed(pad_id,JOY_BUTTON_LEFT_STICK))
	var direction:=(look*f+Vector3(cos(yaw),0,-sin(yaw))*x+Vector3.UP*y).limit_length(1.)
	var speed:=7.0 if fast else 3.0
	if view_mode==3:
		free_point=_bounded(free_point+direction*speed*dt)
	else:
		swimmer.velocity=swimmer.velocity.lerp(direction*speed,1.-exp(-6.*dt))
		swimmer.move_and_slide()
		swimmer.position=_bounded(swimmer.position)
		swimmer.rotation.y=yaw+PI
		child.rotation.x=1.03-pitch*.68
		child.position=-child.transform.basis.y*.52
	var pace:=direction.length() if view_mode!=3 else 0.
	phase+=dt*(2.2+pace*4.)
	for i in 2:
		var sign_side:=float(2*i-1)
		child._legs[i].rotation.x=sign_side*sin(phase)*(.12+.34*pace)
		child._arms[i].rotation.x=-.38+sign_side*cos(phase)*(.12+.17*pace)
		child._arms[i].rotation.z=sign_side*.28
	garden.animate(elapsed)
	_camera()

func _bounded(p: Vector3) -> Vector3:
	p.x=clampf(p.x,-26,26)
	p.z=clampf(p.z,-37,29)
	p.y=clampf(p.y,Garden.floor_y(p.x,p.z)+.52,15.3)
	return p

func _camera() -> void:
	var p:=swimmer.position
	var across:=Vector3(cos(yaw),0,-sin(yaw))
	if view_mode==3 or view_mode==1:
		camera.position=free_point if view_mode==3 else p+look*.35+Vector3.UP*.25
		camera.look_at(camera.position+look)
		return
	var destination:=p-look*3.1+across*.84+Vector3.UP*.72
	if view_mode==2:destination=p+look*1.9+across*1.5+Vector3.UP*.63
	_camera_query.from=p
	_camera_query.to=destination
	var hit:=get_world_3d().direct_space_state.intersect_ray(_camera_query)
	if not hit.is_empty():destination=hit.position+hit.normal*.17
	camera.position=_bounded(destination)
	child.visible=camera.position.distance_to(p)>1.15
	camera.look_at(p+look*(1.45 if view_mode==0 else 0.)+Vector3.UP*.41)

func _exit_tree() -> void:
	Input.mouse_mode=prior_mouse
	# unified r4: the town's controller layer comes back with nothing held (no stick or press from before the dive)
	if pad and pad.has_method("_reset"):pad._reset()
