## In-game interface: friends and save status, emotes, context actions, the
## toy box catalog, placement tools, scrapbook, language and connection dialogs.
##
## All text is English source passed through Godot translation, so switching
## language updates the screen without touching the town or a placement draft.
extends Control

const UI := preload("res://scripts/ui/ui_kit.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const CozySpots := preload("res://scripts/core/cozy_spots.gd")
const Palette := preload("res://scripts/core/palette.gd")
const Avatar := preload("res://scripts/core/avatar.gd")

## Width of the Decorate/Undo column; the catalog leaves room for it.
const SIDE_W := 236

signal leave_requested()
signal photo_requested()
signal reconnect_requested()

var controller: Node
var thumbs: Node

var _friends: HBoxContainer
var _status: Label
var _status_icon: TextureRect
var _lantern_btn: Button
var _context_btn: Button
var _decorate_btn: Button
var _emotes: HBoxContainer
var _cam_tools: VBoxContainer
var _catalog: PanelContainer
var _tabs: HBoxContainer
var _cards: HBoxContainer
var _tools: PanelContainer
var _tools_row: HBoxContainer
var _swatches: HBoxContainer
var _place_btn: Button
var _remove_btn: Button
var _paint_btn: Button
var _undo_btn: Button
var _hint: Label
var _hint_panel: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _celebration: PanelContainer
var _overlay: Control
var _category := ""
var _ctx := {}
var _photos: Array = []
var _toast_tw: Tween


func _ready() -> void:
	UI.fit_safe_area(self)
	get_viewport().size_changed.connect(func(): UI.fit_safe_area(self))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	_build_top()
	_build_bottom()
	_build_catalog()
	_build_tools()
	_build_messages()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	Session.players_changed.connect(_refresh_friends)
	Session.saved.connect(func(_ok): _refresh_status())
	Session.connection_changed.connect(_on_connection)
	Session.lantern_lit.connect(_on_lantern)
	Session.request_failed.connect(func(e): show_hint(e))
	Session.rejected.connect(_on_rejected)
	Session.evening_changed.connect(func(_on): _refresh_lanterns())
	I18n.locale_changed.connect(func(_c): _refresh_texts())


func bind(c: Node, t: Node) -> void:
	controller = c
	thumbs = t
	controller.context_changed.connect(_on_context)
	controller.mode_changed.connect(_on_mode)
	controller.ghost_changed.connect(_on_ghost)
	controller.hint.connect(show_hint)
	controller.toast.connect(show_toast)
	controller.confirm_remove.connect(_confirm_remove)
	controller.space_changed.connect(func(s):
		_rebuild_catalog_tabs()
		for i in 2:
			_cam_tools.get_child(i).visible = s == "town")
	controller.undo_changed.connect(func(a): _undo_btn.disabled = not a)
	if not thumbs.is_done:
		thumbs.finished.connect(_rebuild_cards)
	_on_mode("play")
	_refresh_texts()


func _corner(preset: int, margin := 16) -> MarginContainer:
	var m := MarginContainer.new()
	UI.pin(m, preset)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	return m


# ------------------------------------------------------------- top bar

func _build_top() -> void:
	var left := _corner(Control.PRESET_TOP_LEFT)
	var p := UI.panel(24)
	left.add_child(p)
	var row := HBoxContainer.new()
	p.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UI.icon("friends", 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	_friends = HBoxContainer.new()
	row.add_child(_friends)

	var right := _corner(Control.PRESET_TOP_RIGHT)
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(rrow)
	var sp := UI.panel(24)
	rrow.add_child(sp)
	var srow := HBoxContainer.new()
	sp.add_child(srow)
	_status_icon = TextureRect.new()
	_status_icon.texture = UI.icon("saved", 36)
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	srow.add_child(_status_icon)
	_status = UI.label("", 20, UI.MUTED)
	srow.add_child(_status)
	_lantern_btn = UI.button("", "lantern")
	_lantern_btn.tooltip_text = "Scrapbook"
	_lantern_btn.pressed.connect(open_scrapbook)
	rrow.add_child(_lantern_btn)
	var photo := UI.icon_button("camera", "Take a photo")
	photo.pressed.connect(func(): photo_requested.emit())
	rrow.add_child(photo)
	var lang := UI.icon_button("globe", "Language")
	lang.pressed.connect(open_language)
	rrow.add_child(lang)
	var leave := UI.icon_button("leave", "Leave town")
	leave.pressed.connect(func(): leave_requested.emit())
	rrow.add_child(leave)

	# Camera controls on the right edge, where a thumb rests while holding an iPad.
	var mid := MarginContainer.new()
	UI.pin(mid, Control.PRESET_CENTER_RIGHT)
	mid.add_theme_constant_override("margin_right", 16)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)
	_cam_tools = VBoxContainer.new()
	mid.add_child(_cam_tools)
	for spec in [["rotate_left", "Rotate view left", -1], ["rotate_right", "Rotate view right", 1], ["zoom", "Zoom", 0]]:
		var b := UI.icon_button(spec[0], spec[1], 68)
		var dir: int = spec[2]
		b.pressed.connect(func():
			if dir == 0:
				controller.rig.toggle_zoom()
			else:
				controller.rig.rotate_step(dir))
		_cam_tools.add_child(b)


func _refresh_friends() -> void:
	for c in _friends.get_children():
		c.queue_free()
	var peers := Session.players.keys()
	peers.sort()
	for peer in peers:
		var av: Dictionary = Session.players[peer]["avatar"]
		var chip := PanelContainer.new()
		var s := UI.box(Palette.paint(av["outfit_color"]).lerp(UI.PANEL, 0.55), 18)
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.content_margin_left = 12
		s.content_margin_right = 12
		if peer == Session.my_id:
			s.set_border_width_all(3)
			s.border_color = UI.ACCENT
		chip.add_theme_stylebox_override("panel", s)
		chip.add_child(UI.label(av["nick"], 22))
		_friends.add_child(chip)
	_refresh_status()


func _refresh_status() -> void:
	var text := ""
	var icon := "saved"
	if Session.state == "connecting":
		text = tr("Connecting…")
		icon = "warn"
	elif Session.state != "online":
		text = tr("Disconnected from the town")
		icon = "warn"
	elif not Session.last_save_ok:
		text = tr("Not saved yet. Trying again…")
		icon = "warn"
	else:
		text = tr("Town saved")
	if Session.mode == "solo":
		text += " · " + tr("Playing alone")
	elif Session.mode in ["client", "host"]:
		text += " · " + tr("%d of %d friends") % [Session.players.size(), Session.MAX_PLAYERS]
	_status.text = text
	_status_icon.texture = UI.icon(icon, 36)


func _refresh_lanterns() -> void:
	_lantern_btn.text = "%d / %d" % [Session.model.lanterns.size(), CozySpots.SPOTS.size()]


func _on_connection(state: String) -> void:
	_refresh_status()
	if state == "disconnected":
		_dialog("Disconnected from the town", "Decorating is paused until we reconnect.",
			[["Reconnect", func(): reconnect_requested.emit(), true], ["Back to start", func(): leave_requested.emit(), false]])


func _on_rejected(reason: String) -> void:
	var body := "Four friends are playing. Try again a little later." if reason == "The town is full right now" else ""
	_dialog(reason, body, [["Back to start", func(): leave_requested.emit(), true]])


# ------------------------------------------------------------- bottom bar

func _build_bottom() -> void:
	var bl := _corner(Control.PRESET_BOTTOM_LEFT)
	_emotes = HBoxContainer.new()
	bl.add_child(_emotes)
	for e in [["wave", "Wave"], ["cheer", "Cheer"], ["dance", "Dance"], ["heart", "Love"]]:
		var b := UI.icon_button(e[0], e[1])
		var kind: String = e[0]
		b.pressed.connect(func(): Session.send_emote(kind))
		_emotes.add_child(b)

	var bc := _corner(Control.PRESET_CENTER_BOTTOM, 24)
	_context_btn = UI.button("", "door", true, 260)
	_context_btn.custom_minimum_size.y = 88
	_context_btn.add_theme_font_size_override("font_size", 28)
	_context_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.do_context())
	bc.add_child(_context_btn)
	_context_btn.visible = false

	var br := _corner(Control.PRESET_BOTTOM_RIGHT)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	br.add_child(col)
	_undo_btn = UI.button("Undo", "undo", false, SIDE_W)
	_undo_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(func(): controller.undo())
	col.add_child(_undo_btn)
	_decorate_btn = UI.button("Decorate", "decorate", true, SIDE_W)
	_decorate_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_decorate_btn.custom_minimum_size.y = 88
	_decorate_btn.add_theme_font_size_override("font_size", 28)
	_decorate_btn.pressed.connect(func():
		Sfx.play("tap")
		controller.set_mode("play" if controller.mode == "decorate" else "decorate"))
	col.add_child(_decorate_btn)


func _on_context(ctx: Dictionary) -> void:
	_ctx = ctx
	_context_btn.visible = not ctx.is_empty() and controller.mode == "play"
	if not ctx.is_empty():
		_context_btn.text = ctx["label"]
		_context_btn.icon = UI.icon(ctx.get("icon", "door"))


func _on_mode(mode: String) -> void:
	var deco := mode == "decorate"
	_decorate_btn.text = "Done" if deco else "Decorate"
	_decorate_btn.icon = UI.icon("check" if deco else "decorate")
	_catalog.visible = deco
	_emotes.visible = not deco
	_undo_btn.visible = deco
	_context_btn.visible = not deco and not _ctx.is_empty()
	if deco:
		_rebuild_catalog_tabs()
		show_hint("Tap something to move, turn, paint or put it away.")
	else:
		_hint_panel.visible = false


# ------------------------------------------------------------- catalog

func _build_catalog() -> void:
	var m := MarginContainer.new()
	UI.pin(m, Control.PRESET_BOTTOM_WIDE)
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", SIDE_W + 32)
	m.add_theme_constant_override("margin_bottom", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(m)
	_catalog = UI.panel(24)
	m.add_child(_catalog)
	var col := VBoxContainer.new()
	_catalog.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var title := UI.label("Toy box", 24, UI.ACCENT)
	top.add_child(title)
	var free := UI.label("Everything is free. Take as many as you like.", 18, UI.MUTED)
	free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(free)
	_tabs = HBoxContainer.new()
	col.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 164)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_cards = HBoxContainer.new()
	scroll.add_child(_cards)
	_catalog.visible = false


func _rebuild_catalog_tabs() -> void:
	if controller == null:
		return
	for c in _tabs.get_children():
		c.queue_free()
	var cats := Catalog.TOWN_CATEGORIES if controller.space == "town" else Catalog.HOME_CATEGORIES
	if not cats.has(_category):
		_category = cats[0]
	for cat in cats:
		var b := UI.button(cat, "", cat == _category, 0)
		b.custom_minimum_size.y = 56
		var c2: String = cat
		b.pressed.connect(func():
			_category = c2
			_rebuild_catalog_tabs())
		_tabs.add_child(b)
	_rebuild_cards()


func _rebuild_cards() -> void:
	if controller == null:
		return
	for c in _cards.get_children():
		c.queue_free()
	for kind in Catalog.kinds_for(_category, controller.space):
		var b := Button.new()
		b.custom_minimum_size = Vector2(136, 160)
		b.focus_mode = Control.FOCUS_NONE
		b.icon = thumbs.textures.get(kind)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.text = Catalog.ITEMS[kind]["name"]
		b.add_theme_font_size_override("font_size", 17)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_constant_override("icon_max_width", 100)
		var k: String = kind
		b.pressed.connect(func():
			Sfx.play("tap")
			controller.begin_new(k))
		_cards.add_child(b)


# ------------------------------------------------------------- placement tools

func _build_tools() -> void:
	var m := MarginContainer.new()
	UI.pin(m, Control.PRESET_CENTER_BOTTOM)
	m.add_theme_constant_override("margin_bottom", 300)
	m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(col)
	_hint_panel = UI.panel(20, UI.PANEL)
	_hint = UI.label("", 22, UI.TEXT, true)
	_hint.custom_minimum_size.x = 420
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_panel.add_child(_hint)
	_hint_panel.visible = false
	col.add_child(_hint_panel)
	_tools = UI.panel(24)
	col.add_child(_tools)
	var tcol := VBoxContainer.new()
	_tools.add_child(tcol)
	_swatches = HBoxContainer.new()
	_swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_child(_swatches)
	for i in Palette.PAINT.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(60, 60)
		sw.tooltip_text = Palette.PAINT[i]["name"]
		sw.focus_mode = Control.FOCUS_NONE
		sw.add_theme_stylebox_override("normal", UI.box(Palette.paint(i), 30, 3, UI.PANEL))
		sw.add_theme_stylebox_override("hover", UI.box(Palette.paint(i), 30, 4, UI.ACCENT))
		sw.add_theme_stylebox_override("pressed", UI.box(Palette.paint(i), 30, 5, UI.TEXT))
		var idx := i
		sw.pressed.connect(func():
			Sfx.play("tap")
			controller.paint_ghost(idx))
		_swatches.add_child(sw)
	_swatches.visible = false
	_tools_row = HBoxContainer.new()
	_tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_child(_tools_row)
	var turn := UI.button("Turn", "turn")
	turn.pressed.connect(func(): controller.turn_ghost())
	_tools_row.add_child(turn)
	_paint_btn = UI.button("Paint", "paint")
	_paint_btn.pressed.connect(func(): _swatches.visible = not _swatches.visible)
	_tools_row.add_child(_paint_btn)
	_remove_btn = UI.button("Put away", "trash")
	_remove_btn.pressed.connect(func(): controller.put_away())
	_tools_row.add_child(_remove_btn)
	var cancel := UI.button("Cancel", "close")
	cancel.pressed.connect(func(): controller.cancel_ghost())
	_tools_row.add_child(cancel)
	_place_btn = UI.button("Place here", "check", true, 200)
	_place_btn.pressed.connect(func(): controller.confirm_ghost())
	_tools_row.add_child(_place_btn)
	_tools.visible = false


func _on_ghost(info: Dictionary) -> void:
	_tools.visible = not info.is_empty()
	if info.is_empty():
		_swatches.visible = false
		if controller.mode == "decorate":
			show_hint("Tap something to move, turn, paint or put it away.")
		return
	_place_btn.text = "Done" if info["editing"] else "Place here"
	_place_btn.disabled = info["error"] != ""
	_remove_btn.visible = info["editing"]
	_paint_btn.visible = info["paintable"]
	if not info["paintable"]:
		_swatches.visible = false
	show_hint(info["error"] if info["error"] != "" else "Drag it, turn it, then tap Place here.")


func show_hint(text: String) -> void:
	_hint.text = text
	_hint_panel.visible = text != "" and controller != null and controller.mode == "decorate"
	if controller and controller.mode != "decorate" and text != "":
		show_toast(text)


# ------------------------------------------------------------- messages

func _build_messages() -> void:
	var m := _corner(Control.PRESET_CENTER_TOP, 110)
	m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast = UI.panel(24, UI.ACCENT)
	_toast_label = UI.label("", 24, UI.PANEL)
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_toast)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	_celebration = UI.panel(32, UI.PANEL)
	_celebration.visible = false
	_celebration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_celebration)


func show_toast(text: String) -> void:
	_toast_label.text = text
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(2.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_lantern(spot: String, by: Array) -> void:
	_refresh_lanterns()
	Sfx.play("lantern")
	for c in _celebration.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_celebration.add_child(col)
	var icon := TextureRect.new()
	icon.texture = UI.icon("lantern", 96)
	icon.modulate = CozySpots.SPOTS[spot]["lantern"].lightened(0.2)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	col.add_child(icon)
	var head := UI.label("A new lantern is glowing!", 34, UI.ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name := UI.label(CozySpots.SPOTS[spot]["name"], 30)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name)
	var who := UI.label(tr("Made together by %s") % ", ".join(by.map(func(n): return tr(n))), 22, UI.MUTED)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(who)
	_celebration.visible = true
	_celebration.scale = Vector2.ONE * 0.8
	_celebration.pivot_offset = _celebration.size * 0.5
	var tw := create_tween()
	tw.tween_property(_celebration, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_callback(func(): _celebration.visible = false)


func _dialog(title: String, body: String, buttons: Array) -> Control:
	_close_overlay()
	var shade := ColorRect.new()
	shade.color = Color(0.2, 0.25, 0.2, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(c)
	var p := UI.panel(28)
	p.custom_minimum_size.x = 560
	c.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	col.add_child(UI.label(title, 32, UI.ACCENT, true))
	if body != "":
		col.add_child(UI.label(body, 24, UI.TEXT, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	for spec in buttons:
		var b := UI.button(spec[0], "", spec[2], 160)
		var cb: Callable = spec[1]
		b.pressed.connect(func():
			_close_overlay()
			cb.call())
		row.add_child(b)
	return col


## Adds content to a dialog above its button row.
func _insert(col: VBoxContainer, node: Control) -> void:
	col.add_child(node)
	col.move_child(node, col.get_child_count() - 2)


func _close_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()


func _confirm_remove(item: Dictionary, contents: int) -> void:
	_dialog("Put this house away?", tr("Its %d things inside will be packed away with it. You can undo this.") % contents,
		[["Keep it", func(): controller.cancel_ghost(), false], ["Put it away", func(): controller.put_away(true), true]])


func open_language() -> void:
	var col := _dialog("Language", "", [["Close", func(): pass, false]])
	var grid := GridContainer.new()
	grid.columns = 2
	_insert(col, grid)
	for code in I18n.LOCALES:
		var b := UI.button(I18n.native_names.get(code, code), "", code == I18n.current, 250)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var c2: String = code
		b.pressed.connect(func():
			I18n.set_locale(c2)
			open_language())
		grid.add_child(b)


## Lanterns and photos the friends have made together.
func open_scrapbook() -> void:
	var col := _dialog("Scrapbook", tr("Lanterns lit: %d of %d") % [Session.model.lanterns.size(), CozySpots.SPOTS.size()], [["Close", func(): pass, true]])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_insert(col, grid)
	for spot in CozySpots.ORDER:
		var lit: bool = Session.model.lanterns.has(spot)
		var card := PanelContainer.new()
		var bg: Color = CozySpots.SPOTS[spot]["lantern"].lerp(UI.PANEL, 0.6) if lit else UI.PAPER
		card.add_theme_stylebox_override("panel", UI.box(bg, 18))
		card.custom_minimum_size = Vector2(230, 170)
		grid.add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		var icon := TextureRect.new()
		icon.texture = UI.icon("lantern", 52)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.modulate = CozySpots.SPOTS[spot]["lantern"] if lit else Color(0.6, 0.6, 0.6, 0.5)
		v.add_child(icon)
		v.add_child(UI.label(CozySpots.SPOTS[spot]["name"] if lit else "Not found yet", 22, UI.TEXT, true))
		var sub := tr("Made together by %s") % ", ".join(Session.model.lanterns[spot]["by"].map(func(n): return tr(n))) if lit else tr(CozySpots.SPOTS[spot]["hint"])
		var l := UI.label(sub, 17, UI.MUTED, true)
		v.add_child(l)
	_insert(col, UI.label("Photos", 24, UI.ACCENT))
	var photos := HBoxContainer.new()
	_insert(col, photos)
	if _photos.is_empty():
		photos.add_child(UI.label("No photos yet. Tap the camera to take one.", 20, UI.MUTED))
	for tex in _photos.slice(-4):
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(220, 165)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photos.add_child(r)


func add_photo(tex: Texture2D) -> void:
	_photos.append(tex)
	show_toast("Photo saved to the scrapbook")


func _refresh_texts() -> void:
	theme.default_font = I18n.ui_font()
	_refresh_friends()
	_refresh_lanterns()
	_refresh_status()
