## UI building blocks: the project theme, SVG icons and helper constructors.
##
## Design values follow docs/design-spec.md: paper #f5f1e7, panel #fffdf6,
## text #344d40, accent #557c5e, soft green #e5eddc, warm yellow #edcf81,
## 24 px panel corners, 16 px button corners and large touch targets.
extends RefCounted

const PAPER := Color("#f5f1e7")
const PANEL := Color("#fffdf6")
const TEXT := Color("#344d40")
const MUTED := Color("#69796a")
const ACCENT := Color("#557c5e")
const SOFT := Color("#e5eddc")
const YELLOW := Color("#edcf81")
const CORAL := Color("#e9806e")
const TOUCH := 76

static var _theme: Theme
## Simulated safe-area insets for layout tests (--safe-insets=l,t,r,b); zero on devices.
static var test_insets := Vector4.ZERO
static var _icons := {}

const ICONS := {
	"decorate": "<path d='M14 30 L34 30 L32 52 L16 52 Z' fill='#edcf81'/><rect x='10' y='24' width='28' height='8' rx='4' fill='#557c5e'/><circle cx='42' cy='18' r='9' fill='#ec8fa3'/><circle cx='42' cy='18' r='3.5' fill='#f6d55c'/><path d='M42 27 L42 44' stroke='#557c5e' stroke-width='3.5' stroke-linecap='round'/>",
	"undo": "<path d='M20 22 C34 14 50 22 50 36 C50 48 38 54 28 50' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M10 22 L24 12 L24 32 Z' fill='#344d40'/>",
	"turn": "<path d='M46 30 A16 16 0 1 1 38 16' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M34 6 L48 14 L34 24 Z' fill='#344d40'/>",
	"paint": "<path d='M32 8 C16 8 8 20 8 32 C8 46 20 56 32 56 C36 56 38 52 36 48 C34 44 36 40 42 40 L48 40 C54 40 56 36 56 30 C56 16 46 8 32 8 Z' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><circle cx='22' cy='24' r='5' fill='#ec8fa3'/><circle cx='34' cy='18' r='5' fill='#86c3e6'/><circle cx='45' cy='26' r='5' fill='#95c97f'/><circle cx='20' cy='38' r='5' fill='#f2cf6b'/>",
	"trash": "<rect x='16' y='20' width='32' height='34' rx='6' fill='#e9806e'/><rect x='10' y='12' width='44' height='8' rx='4' fill='#344d40'/><rect x='26' y='6' width='12' height='8' rx='3' fill='#344d40'/>",
	"check": "<path d='M12 34 L26 48 L52 18' fill='none' stroke='#fffdf6' stroke-width='8' stroke-linecap='round' stroke-linejoin='round'/>",
	"close": "<path d='M16 16 L48 48 M48 16 L16 48' stroke='#344d40' stroke-width='7' stroke-linecap='round'/>",
	"camera": "<rect x='8' y='18' width='48' height='34' rx='8' fill='#344d40'/><rect x='22' y='10' width='20' height='10' rx='4' fill='#344d40'/><circle cx='32' cy='35' r='11' fill='#fffdf6'/><circle cx='32' cy='35' r='6' fill='#86c3e6'/>",
	"book": "<path d='M8 14 C18 10 26 12 32 18 C38 12 46 10 56 14 L56 52 C46 48 38 50 32 56 C26 50 18 48 8 52 Z' fill='#edcf81' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 18 L32 56' stroke='#344d40' stroke-width='3'/>",
	"globe": "<circle cx='32' cy='32' r='22' fill='#86c3e6' stroke='#344d40' stroke-width='3'/><path d='M14 26 C22 22 24 30 30 28 C36 26 34 18 42 16 M20 44 C26 40 32 46 38 42 C44 38 48 42 52 40' stroke='#557c5e' stroke-width='4' fill='none' stroke-linecap='round'/>",
	"wave": "<rect x='22' y='16' width='20' height='30' rx='9' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><path d='M14 14 C10 20 10 26 14 30 M50 14 C54 20 54 26 50 30' stroke='#344d40' stroke-width='3' fill='none' stroke-linecap='round'/><rect x='26' y='42' width='12' height='14' rx='4' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/>",
	"cheer": "<path d='M32 6 L38 24 L56 24 L42 35 L47 54 L32 42 L17 54 L22 35 L8 24 L26 24 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/>",
	"dance": "<path d='M26 46 L26 12 L50 8 L50 40' fill='none' stroke='#344d40' stroke-width='5' stroke-linejoin='round'/><circle cx='20' cy='46' r='8' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/><circle cx='44' cy='42' r='8' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/>",
	"heart": "<path d='M32 54 C10 38 8 26 12 18 C16 10 28 10 32 20 C36 10 48 10 52 18 C56 26 54 38 32 54 Z' fill='#ef6f86' stroke='#344d40' stroke-width='3'/>",
	"rotate_left": "<path d='M18 30 A16 16 0 1 1 26 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M8 22 L20 36 L28 20 Z' fill='#344d40'/>",
	"rotate_right": "<path d='M46 30 A16 16 0 1 0 38 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M56 22 L44 36 L36 20 Z' fill='#344d40'/>",
	"zoom": "<circle cx='28' cy='28' r='16' fill='#fffdf6' stroke='#344d40' stroke-width='6'/><path d='M40 40 L54 54' stroke='#344d40' stroke-width='7' stroke-linecap='round'/><path d='M20 28 L36 28 M28 20 L28 36' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"door": "<rect x='16' y='8' width='32' height='48' rx='14' fill='#95c97f' stroke='#344d40' stroke-width='3'/><circle cx='40' cy='34' r='3.5' fill='#f2cf6b'/>",
	"sit": "<rect x='12' y='30' width='40' height='8' rx='4' fill='#d9a466' stroke='#344d40' stroke-width='3'/><path d='M16 38 L16 54 M48 38 L48 54 M14 30 L14 10' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"stand": "<circle cx='32' cy='14' r='8' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><path d='M32 22 L32 42 M20 30 L44 30 M32 42 L22 56 M32 42 L42 56' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"bell": "<path d='M18 44 C18 30 18 14 32 14 C46 14 46 30 46 44 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><rect x='12' y='42' width='40' height='7' rx='3.5' fill='#344d40'/><circle cx='32' cy='54' r='5' fill='#344d40'/><circle cx='32' cy='10' r='4' fill='#344d40'/>",
	"lantern": "<rect x='18' y='16' width='28' height='34' rx='12' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><rect x='22' y='10' width='20' height='7' rx='3' fill='#344d40'/><rect x='22' y='48' width='20' height='7' rx='3' fill='#344d40'/><path d='M32 4 L32 10' stroke='#344d40' stroke-width='3'/>",
	"friends": "<circle cx='22' cy='22' r='9' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><circle cx='42' cy='22' r='9' fill='#d9a27c' stroke='#344d40' stroke-width='3'/><rect x='10' y='34' width='24' height='20' rx='10' fill='#86c3e6' stroke='#344d40' stroke-width='3'/><rect x='30' y='34' width='24' height='20' rx='10' fill='#f4ad8a' stroke='#344d40' stroke-width='3'/>",
	"home": "<path d='M8 30 L32 10 L56 30' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/><rect x='16' y='28' width='32' height='26' rx='4' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><rect x='27' y='38' width='10' height='16' rx='4' fill='#e9806e'/>",
	"play": "<path d='M20 12 L52 32 L20 52 Z' fill='#fffdf6' stroke='#fffdf6' stroke-width='4' stroke-linejoin='round'/>",
	"leave": "<rect x='10' y='10' width='26' height='44' rx='6' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><path d='M28 32 L54 32 M44 22 L54 32 L44 42' stroke='#344d40' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"saved": "<circle cx='32' cy='32' r='22' fill='#95c97f'/><path d='M20 33 L29 42 L45 24' fill='none' stroke='#fffdf6' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"music": "<circle cx='32' cy='32' r='26' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/><path d='M27 44 L27 18 L45 14 L45 38' fill='none' stroke='#344d40' stroke-width='4' stroke-linejoin='round'/><circle cx='23' cy='44' r='5.5' fill='#344d40'/><circle cx='41' cy='39' r='5.5' fill='#344d40'/>",
	"stairs_up": "<path d='M10 52 L10 42 L22 42 L22 32 L34 32 L34 22 L46 22 L46 12 L56 12 L56 52 Z' fill='#d9a466' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M16 28 L16 12 M10 18 L16 11 L22 18' stroke='#fffdf6' stroke-width='4' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"stairs_down": "<path d='M10 52 L10 42 L22 42 L22 32 L34 32 L34 22 L46 22 L46 12 L56 12 L56 52 Z' fill='#d9a466' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M16 11 L16 27 M10 21 L16 28 L22 21' stroke='#fffdf6' stroke-width='4' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"wish": "<path d='M32 6 C48 6 58 16 58 28 C58 40 48 48 34 48 L22 58 L24 46 C12 43 6 36 6 28 C6 16 16 6 32 6 Z' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M32 14 L35.5 23 L45 23 L37.5 29 L40 38 L32 32.5 L24 38 L26.5 29 L19 23 L28.5 23 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='2' stroke-linejoin='round'/>",
	"gift": "<rect x='10' y='26' width='44' height='30' rx='5' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/><rect x='6' y='18' width='52' height='10' rx='4' fill='#f4ad8a' stroke='#344d40' stroke-width='3'/><path d='M32 18 L32 56' stroke='#fffdf6' stroke-width='6'/><path d='M32 18 C24 6 14 10 20 18 Z M32 18 C40 6 50 10 44 18 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='2'/>",
	"acorn": "<ellipse cx='32' cy='38' rx='15' ry='18' fill='#e3b341' stroke='#344d40' stroke-width='3'/><path d='M14 26 C18 14 46 14 50 26 Z' fill='#a8714a' stroke='#344d40' stroke-width='3'/><path d='M32 14 L34 6' stroke='#344d40' stroke-width='4' stroke-linecap='round'/>",
	"drum": "<ellipse cx='32' cy='20' rx='20' ry='8' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M12 20 L12 44 C12 50 52 50 52 44 L52 20' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/><path d='M40 4 L30 18' stroke='#a8714a' stroke-width='4' stroke-linecap='round'/>",
	"weather": "<circle cx='22' cy='22' r='10' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><path d='M20 46 C10 46 10 34 20 34 C22 26 36 24 40 32 C50 30 54 46 44 46 Z' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M24 52 L22 58 M34 52 L32 58 M44 52 L42 58' stroke='#86c3e6' stroke-width='3' stroke-linecap='round'/>",
	"board": "<rect x='8' y='10' width='48' height='36' rx='5' fill='#d9a466' stroke='#344d40' stroke-width='3'/><rect x='14' y='16' width='16' height='11' rx='2' fill='#86c3e6'/><rect x='34' y='16' width='16' height='11' rx='2' fill='#f4ad8a'/><rect x='14' y='30' width='16' height='11' rx='2' fill='#95c97f'/><rect x='34' y='30' width='16' height='11' rx='2' fill='#b7a2e0'/><path d='M20 46 L16 58 M44 46 L48 58' stroke='#344d40' stroke-width='4' stroke-linecap='round'/>",
	"water": "<path d='M32 8 C32 8 16 28 16 38 C16 48 24 54 32 54 C40 54 48 48 48 38 C48 28 32 8 32 8 Z' fill='#86c3e6' stroke='#344d40' stroke-width='3'/>",
	"warn": "<path d='M32 8 L58 54 L6 54 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 24 L32 38' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><circle cx='32' cy='46' r='3.5' fill='#344d40'/>",
}


## Anchors a control to a screen corner/edge and makes it grow inward from there.
static func pin(c: Control, preset: int) -> void:
	c.set_anchors_and_offsets_preset(preset)
	var right := [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_RIGHT_WIDE]
	var hcenter := [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER, Control.PRESET_VCENTER_WIDE]
	var bottom := [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_WIDE]
	var vcenter := [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER, Control.PRESET_HCENTER_WIDE]
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in right else (Control.GROW_DIRECTION_BOTH if preset in hcenter else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in bottom else (Control.GROW_DIRECTION_BOTH if preset in vcenter else Control.GROW_DIRECTION_END)


## Shrinks a full-screen root control to the device safe area (iPadOS home
## indicator, rounded corners). Desktop windows are left unchanged.
static func fit_safe_area(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if test_insets != Vector4.ZERO:
		# Automated layout tests simulate device insets (left, top, right, bottom) in UI pixels.
		c.offset_left = test_insets.x
		c.offset_top = test_insets.y
		c.offset_right = -test_insets.z
		c.offset_bottom = -test_insets.w
		return
	if not OS.has_feature("mobile"):
		return
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0 or safe.size.x <= 0:
		return
	var k := c.get_viewport().get_visible_rect().size / win
	c.offset_left = safe.position.x * k.x
	c.offset_top = safe.position.y * k.y
	c.offset_right = -(win.x - safe.end.x) * k.x
	c.offset_bottom = -(win.y - safe.end.y) * k.y


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.lightened(0.3))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 44)
	t.set_stylebox("normal", "Button", box(PANEL, 16, 2, SOFT.darkened(0.08)))
	t.set_stylebox("hover", "Button", box(PANEL.lerp(SOFT, 0.5), 16, 2, ACCENT.lightened(0.4)))
	t.set_stylebox("pressed", "Button", box(SOFT, 16, 3, ACCENT))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 16, 3, YELLOW))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.03), 16, 2, SOFT))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 24, 0, Color.TRANSPARENT, 0.12))
	t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 12, 2, SOFT.darkened(0.1)))
	t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 12, 3, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 12)
	_theme = t
	return t


static func box(bg: Color, radius := 16, border := 0, border_color := Color.TRANSPARENT, shadow := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	if shadow > 0.0:
		s.shadow_color = Color(0.2, 0.25, 0.2, shadow)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	return s


static func icon(name: String, size := 64) -> Texture2D:
	var key := "%s|%d" % [name, size]
	if _icons.has(key):
		return _icons[key]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>%s</svg>" % ICONS.get(name, ICONS["warn"])
	var img := Image.new()
	img.load_svg_from_string(svg, size / 64.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


static func button(text: String, icon_name := "", primary := false, min_w := TOUCH) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if primary:
		b.add_theme_stylebox_override("normal", box(ACCENT, 16))
		b.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.1), 16))
		b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.1), 16))
		b.add_theme_stylebox_override("disabled", box(ACCENT.lerp(PAPER, 0.6), 16))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, PANEL)
	return b


static func icon_button(icon_name: String, tooltip: String, size := TOUCH) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(size, size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", box(PANEL, size / 2, 2, SOFT.darkened(0.08), 0.1))
	b.add_theme_stylebox_override("hover", box(PANEL.lerp(SOFT, 0.5), size / 2, 2, ACCENT.lightened(0.4), 0.1))
	b.add_theme_stylebox_override("pressed", box(SOFT, size / 2, 3, ACCENT))
	return b


static func label(text: String, size := 24, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func panel(radius := 24, color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, radius, 0, Color.TRANSPARENT, 0.14)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", s)
	return p
