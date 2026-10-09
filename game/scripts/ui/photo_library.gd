## Saves camera photos to the iOS/iPadOS Photos library through the native
## PhotoLibrary plugin (add-only access; ios/plugins/photo_library). Reports the
## system's own answer: "saved", "denied" or "failed". Elsewhere, or when the
## plugin is not in the build, it answers "local": the photo stays in the game.
extends Node

signal finished(result: String)

var _native: Object


func _ready() -> void:
	if OS.get_name() == "iOS" and Engine.has_singleton("PhotoLibrary"):
		_native = Engine.get_singleton("PhotoLibrary")
		_native.connect("save_finished", func(_ok: bool, code: String): finished.emit(code))
	elif OS.get_name() == "iOS":
		push_warning("PhotoLibrary plugin missing: photos stay in the game only")


func available() -> bool:
	return _native != null


## Saves the image file at an absolute path. One answer arrives on `finished`
## (after the system responds on iOS). Returns "local" right away when there is
## no native saver, "pending" otherwise.
func save(abs_path: String) -> String:
	if _native == null:
		finished.emit.call_deferred("local")
		return "local"
	_native.call("save_image", abs_path)
	return "pending"


func open_settings() -> void:
	if _native:
		_native.call("open_settings")
	else:
		OS.shell_open("app-settings:")
