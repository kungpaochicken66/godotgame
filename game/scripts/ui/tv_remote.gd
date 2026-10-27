## Apple TV Siri Remote Menu button (atv-r20-controller, design/tv-controller.md, "The Siri Remote's Menu").
## Menu goes back one step, like the controller's B: it closes a dialog, cancels placing, leaves Decorate,
## goes Back in the start menus, and in town with nothing open leaves to the title (the Leave town button).
## At the title the next Menu press returns to the Apple TV Home screen: the first press there "arms" Home for at most
## ARM_SECONDS (the engine hands that press to UIKit; it needs tv/engine/0001-tvos-menu-presses-to-uikit.patch),
## and a note says so. Leaving the title, the timeout, controller input the game sees or another UIKit press disarms it.
## While armed only UIKit gets controller input: a controller's A may only disarm, and its B (Menu to UIKit) may go Home.
## The native LanternRemote (tv/native/lantern_defaults) counts Siri Remote Menu presses and switches the
## view controller; without it (iPhone, iPad, desktop) this does nothing.
extends Node

const BRIDGE := "LanternRemote"   # the get_singleton name of the native module
const UI := preload("res://scripts/ui/ui_kit.gd")
## Home stays armed this long at most. While armed, controller input reaches only UIKit (the game sees none
## of it), so the native side also ends it at once on any other press; the game follows the native state.
const ARM_SECONDS := 5.0

var main: Node
var armed := false
## Tests put a stand-in here (take_menu_presses, set_system_back, is_system_back).
var backend: Object = null
var note: PanelContainer          # "Press Menu again for the Home screen.", shown while Home is armed


func bind(m: Node) -> void:
	main = m
	if main.pad:
		main.pad.controller_used.connect(disarm)


func _backend() -> Object:
	if backend != null:
		return backend
	if Engine.has_singleton(BRIDGE):
		return Engine.get_singleton(BRIDGE)
	return null


func _ready() -> void:
	# Menu reaches the game, not the OS, unless Home is armed at the title.
	get_tree().quit_on_go_back = false
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	note = UI.panel(14, Color(1, 1, 1, 0.95))
	note.name = "HomeNote"
	note.theme = UI.theme()   # the game's per-language font (all six languages)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.visible = false
	var l := UI.label("Press Menu again for the Home screen.", 24, UI.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(l)
	layer.add_child(note)


func _process(_delta: float) -> void:
	var be := _backend()
	if be == null or main == null:
		return
	var n: int = be.call("take_menu_presses")
	for i in n:
		menu()
	if armed and (not at_title() or not be.call("is_system_back")):
		disarm()   # left the title, timed out, or another press ended it natively


func _notification(what: int) -> void:
	# If a Menu press reaches UIKit while Home is not armed, the engine asks the game to go back instead.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not armed:
		menu()


## The start menus' title screen, with nothing open over it: the top of the game.
func at_title() -> bool:
	return main.menus != null and main.menus.visible and str(main.menus._screen) == "title"


## One Menu press of the Siri Remote.
func menu() -> void:
	if at_title():
		arm()
		return
	var pad: Node = main.pad
	var c: Node = main.controller
	var hud: Control = main.hud
	if main.menus.visible or pad.is_modal() or c.ghost != null or c.mode == "decorate":
		pad._back()   # the same step back as the controller's B
		return
	# In town with nothing open: leave to the title, like the Leave town button.
	main._leave()


func arm() -> void:
	var be := _backend()
	if be == null or armed:
		return
	if be.call("arm_system_back", ARM_SECONDS):
		armed = true
		get_tree().quit_on_go_back = true
		note.visible = true
		note.reset_size()
		# Top centre of the TV safe area, clear of the title's buttons.
		var area: Rect2 = main.pad._area() if main.pad else get_viewport().get_visible_rect()
		var s := note.get_combined_minimum_size()
		note.position = Vector2(area.get_center().x - s.x / 2.0, area.position.y + 8.0)


func disarm() -> void:
	if not armed:
		return
	armed = false
	get_tree().quit_on_go_back = false
	var be := _backend()
	if be:
		be.call("set_system_back", false)
	note.visible = false
