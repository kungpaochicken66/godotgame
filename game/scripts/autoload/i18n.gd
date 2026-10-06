## I18n (autoload): the six supported UI languages and their fonts.
##
## Catalogs are JSON files in res://locale/ keyed by the English source string,
## shared in format with the browser design preview. They are loaded into
## Godot's TranslationServer, so Control text and tr() translate automatically.
extends Node

const LOCALES := ["en", "zh-CN", "ja", "es", "fr", "de"]
const DEFAULT_LOCALE := "en"
const SETTINGS_PATH := "user://settings.cfg"

signal locale_changed(locale: String)

var current := DEFAULT_LOCALE
var native_names := {}
var _fonts := {}


func _ready() -> void:
	native_names = _read_json("res://locale/languages.json")
	for code in LOCALES:
		var t := Translation.new()
		t.locale = godot_code(code)
		var catalog := _read_json("res://locale/%s.json" % code)
		for key in catalog:
			t.add_message(key, catalog[key])
		TranslationServer.add_translation(t)
	var cfg := ConfigFile.new()
	var saved := DEFAULT_LOCALE
	if cfg.load(SETTINGS_PATH) == OK:
		saved = str(cfg.get_value("ui", "locale", DEFAULT_LOCALE))
	set_locale(saved if LOCALES.has(saved) else DEFAULT_LOCALE, false)


## Godot uses underscores ("zh_CN"); the project and design files use "zh-CN".
static func godot_code(code: String) -> String:
	return code.replace("-", "_")


func set_locale(code: String, persist := true) -> void:
	if not LOCALES.has(code):
		code = DEFAULT_LOCALE
	current = code
	TranslationServer.set_locale(godot_code(code))
	if persist:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("ui", "locale", code)
		cfg.save(SETTINGS_PATH)
	locale_changed.emit(code)


## Rounded UI font for the current language, with fallbacks for the others.
## Chinese and Japanese share Han characters but use different glyph shapes,
## so the locale decides which CJK font comes first.
func ui_font() -> Font:
	if _fonts.has(current):
		return _fonts[current]
	var latin := _load_font("res://assets/fonts/Nunito-Variable.ttf")
	var ja := _load_font("res://assets/fonts/MPLUSRounded1c-Bold-subset.ttf")
	var sc := _load_font("res://assets/fonts/NotoSansSC-subset.ttf")
	var fallbacks: Array[Font] = []
	for f in ([sc, ja] if current == "zh-CN" else [ja, sc]):
		if f:
			fallbacks.append(f)
	var v := FontVariation.new()
	if latin:
		v.base_font = latin
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 760}
	else:
		v.base_font = ThemeDB.fallback_font
	v.fallbacks = fallbacks
	_fonts[current] = v
	return v


func _load_font(path: String) -> Font:
	return load(path) if ResourceLoader.exists(path) else null


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing locale file %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}
