## Title, character creator and "play with friends" screens over a small 3D stage.
extends Control

const UI := preload("res://scripts/ui/ui_kit.gd")
const Avatar := preload("res://scripts/core/avatar.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Props := preload("res://scripts/art/props.gd")
const Kit := preload("res://scripts/art/mesh_kit.gd")
const KidScript := preload("res://scripts/art/kid.gd")

signal play_solo(avatar: Dictionary)
signal join_server(url: String, avatar: Dictionary)
signal host_town(avatar: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"

var avatar := {}
var server_url := "ws://127.0.0.1:9080"
var stage: Node3D
var _kid: Node3D
var _cam: Camera3D
var _screen := "title"
var _friends_mode := false
var _status: Label
var _url_edit: LineEdit
var _content: Control


func _ready() -> void:
	UI.fit_safe_area(self)
	get_viewport().size_changed.connect(func(): UI.fit_safe_area(self))
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	avatar = Avatar.sanitize(cfg.get_value("player", "avatar", Avatar.PRESETS[0]))
	server_url = str(cfg.get_value("player", "server", server_url))
	_build_stage()
	I18n.locale_changed.connect(func(_c):
		theme.default_font = I18n.ui_font()
		show_screen(_screen))
	theme.default_font = I18n.ui_font()
	show_screen("title")


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "avatar", avatar)
	cfg.set_value("player", "server", server_url)
	cfg.save(SETTINGS_PATH)


func set_active(on: bool) -> void:
	visible = on
	stage.visible = on
	if on:
		_cam.current = true
		show_screen("title")


# ------------------------------------------------------------- stage

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "MenuStage"
	stage.position = Vector3(0, 0, 400)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#cfe9ef")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#eef3ef")
	env.environment.ambient_light_energy = 0.5
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.8
	stage.add_child(sun)
	Kit.part(stage, Kit.cylinder(9, 9, 0.6, 48), Palette.GRASS, Vector3(0, -0.3, 0))
	var meadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	meadow.mesh = pm
	meadow.material_override = Kit.mat(Palette.GRASS_DARK)
	meadow.position.y = -0.5
	stage.add_child(meadow)
	var place := func(kind: String, color: int, p: Vector3, rot := 0.0):
		var n := Props.build(kind, color, int(p.x * 10))
		n.position = p
		n.rotation.y = rot
		stage.add_child(n)
	place.call("cottage", 2, Vector3(-3.6, 0, -4.2), 0.35)
	place.call("tree", 5, Vector3(3.8, 0, -4.8))
	place.call("tree", 3, Vector3(6.5, 0, -2.0))
	place.call("flowers", 3, Vector3(-1.2, 0, -1.6))
	place.call("flowers", 1, Vector3(1.8, 0, -1.9))
	place.call("lamp_post", 1, Vector3(-2.0, 0, 0.2))
	place.call("swing", 4, Vector3(4.6, 0, 0.6), -0.6)
	for x in [-0.6, 0.2, 1.0]:
		place.call("path_stone", -1, Vector3(x, 0, 1.6 - absf(x)))
	_kid = KidScript.new()
	stage.add_child(_kid)
	_kid.setup(avatar, false)
	_kid.rotation.y = 0.25
	_cam = Camera3D.new()
	_cam.fov = 38
	stage.add_child(_cam)
	_frame_camera(false)
	add_child(stage)


func _frame_camera(close: bool) -> void:
	# Close-up for the creator puts the child on the left, beside the options panel.
	var focus := Vector3(1.05, 0.75, 0) if close else Vector3(0.6, 1.0, -1.0)
	var pos := Vector3(1.05, 1.5, 3.6) if close else Vector3(1.0, 3.6, 8.5)
	_cam.position = pos
	_cam.basis = Basis.looking_at(focus - pos, Vector3.UP)


func _process(_d: float) -> void:
	if visible and _kid:
		_kid.rotation.y = 0.25 + sin(Time.get_ticks_msec() / 1400.0) * 0.25


# ------------------------------------------------------------- screens

func show_screen(name: String) -> void:
	_screen = name
	if _content:
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var lang := UI.icon_button("globe", "Language")
	lang.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	lang.pressed.connect(func(): show_screen("language"))
	_content.add_child(lang)
	match name:
		"title": _title()
		"creator": _creator()
		"friends": _friends()
		"language": _language()
	_frame_camera(name == "creator")


func _box_at(preset: int, margin := 40) -> VBoxContainer:
	var m := MarginContainer.new()
	UI.pin(m, preset)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(m)
	var p := UI.panel(32)
	m.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	p.add_child(col)
	return col


func _title() -> void:
	_kid.play_emote("wave")
	var top := MarginContainer.new()
	UI.pin(top, Control.PRESET_CENTER_TOP)
	top.add_theme_constant_override("margin_top", 70)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_content.add_child(top)
	var p := UI.panel(36)
	top.add_child(p)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)
	var logo := UI.label("Lantern Lane", 72, UI.ACCENT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var tag := UI.label("Build cozy spots together and light up the town.", 26, UI.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var bottom := MarginContainer.new()
	UI.pin(bottom, Control.PRESET_CENTER_BOTTOM)
	bottom.add_theme_constant_override("margin_bottom", 60)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_content.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	bottom.add_child(row)
	var solo := UI.button("Play", "play", true, 280)
	solo.custom_minimum_size.y = 96
	solo.add_theme_font_size_override("font_size", 32)
	solo.pressed.connect(func():
		_friends_mode = false
		show_screen("creator"))
	row.add_child(solo)
	var friends := UI.button("Play with friends", "friends", false, 320)
	friends.custom_minimum_size.y = 96
	friends.add_theme_font_size_override("font_size", 30)
	friends.pressed.connect(func():
		_friends_mode = true
		show_screen("creator"))
	row.add_child(friends)


func _option_row(col: VBoxContainer, title: String, count: int, current: int, make: Callable, pick: Callable) -> void:
	col.add_child(UI.label(title, 22, UI.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	col.add_child(flow)
	for i in count:
		var b: Button = make.call(i)
		b.focus_mode = Control.FOCUS_NONE
		if i == current:
			var bg: Color = b.get_meta("swatch", UI.SOFT)
			b.add_theme_stylebox_override("normal", UI.box(bg, 28 if b.has_meta("swatch") else 16, 5, UI.ACCENT))
		var idx := i
		b.pressed.connect(func():
			pick.call(idx)
			Sfx.play("tap")
			_kid.setup(avatar, false)
			_kid.play_emote("cheer")
			show_screen("creator"))
		flow.add_child(b)


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.set_meta("swatch", c)
	b.custom_minimum_size = Vector2(56, 56)
	b.add_theme_stylebox_override("normal", UI.box(c, 28, 2, UI.PANEL))
	b.add_theme_stylebox_override("hover", UI.box(c, 28, 3, UI.ACCENT.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", UI.box(c, 28, 4, UI.ACCENT))
	return b


func _text_choice(text: String) -> Button:
	var b := UI.button(text, "", false, 0)
	b.custom_minimum_size.y = 56
	return b


func _creator() -> void:
	var m := MarginContainer.new()
	UI.pin(m, Control.PRESET_RIGHT_WIDE)
	m.custom_minimum_size.x = 640
	m.offset_left = -660
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_top", 100)
	_content.add_child(m)
	var p := UI.panel(32)
	m.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)
	col.add_child(UI.label("Make your character", 34, UI.ACCENT))
	_option_row(col, "Name", Avatar.NICKNAMES.size(), Avatar.NICKNAMES.find(avatar["nick"]),
		func(i): return _text_choice(Avatar.NICKNAMES[i]), func(i): avatar["nick"] = Avatar.NICKNAMES[i])
	_option_row(col, "Skin", Palette.SKIN.size(), avatar["skin"], func(i): return _swatch(Palette.SKIN[i]), func(i): avatar["skin"] = i)
	_option_row(col, "Hair", Avatar.HAIR_STYLES.size(), avatar["hair"], func(i): return _text_choice(Avatar.HAIR_STYLES[i]), func(i): avatar["hair"] = i)
	_option_row(col, "Hair color", Palette.HAIR.size(), avatar["hair_color"], func(i): return _swatch(Palette.HAIR[i]), func(i): avatar["hair_color"] = i)
	_option_row(col, "Clothes", Avatar.OUTFITS.size(), avatar["outfit"], func(i): return _text_choice(Avatar.OUTFITS[i]), func(i): avatar["outfit"] = i)
	_option_row(col, "Color", Palette.PAINT.size(), avatar["outfit_color"], func(i): return _swatch(Palette.paint(i)), func(i): avatar["outfit_color"] = i)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var back := UI.button("Back", "", false, 140)
	back.pressed.connect(func(): show_screen("title"))
	row.add_child(back)
	var go := UI.button("Let's go!", "play", true, 240)
	go.pressed.connect(func():
		_save()
		if _friends_mode:
			show_screen("friends")
		else:
			play_solo.emit(avatar))
	row.add_child(go)


func _friends() -> void:
	var col := _box_at(Control.PRESET_CENTER, 0)
	col.custom_minimum_size.x = 640
	col.add_child(UI.label("Play with friends", 34, UI.ACCENT))
	col.add_child(UI.label("Ask a grown-up to set up the town server address.", 22, UI.MUTED, true))
	col.add_child(UI.label("Town server", 22, UI.TEXT))
	_url_edit = LineEdit.new()
	_url_edit.text = server_url
	_url_edit.custom_minimum_size.y = 64
	_url_edit.add_theme_font_size_override("font_size", 24)
	col.add_child(_url_edit)
	_status = UI.label("", 22, UI.CORAL, true)
	col.add_child(_status)
	var row := HBoxContainer.new()
	col.add_child(row)
	var back := UI.button("Back", "", false, 140)
	back.pressed.connect(func(): show_screen("creator"))
	row.add_child(back)
	var host := UI.button("Host on this device", "home", false, 0)
	host.pressed.connect(func(): host_town.emit(avatar))
	row.add_child(host)
	var join := UI.button("Join", "friends", true, 180)
	join.pressed.connect(func():
		server_url = _url_edit.text.strip_edges()
		_save()
		set_status("Connecting…")
		join_server.emit(server_url, avatar))
	row.add_child(join)


func set_status(text: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = text


func _language() -> void:
	var col := _box_at(Control.PRESET_CENTER, 0)
	col.add_child(UI.label("Language", 34, UI.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	for code in I18n.LOCALES:
		var b := UI.button(I18n.native_names.get(code, code), "", code == I18n.current, 260)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var c2: String = code
		b.pressed.connect(func(): I18n.set_locale(c2))
		grid.add_child(b)
	var back := UI.button("Back", "", false, 140)
	back.pressed.connect(func(): show_screen("title"))
	col.add_child(back)
