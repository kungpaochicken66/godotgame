## A stand-in for the native LanternRemote (tv/native/lantern_defaults) for tests: Siri Remote Menu presses are
## queued with press(), and the view controller setting is only recorded. Not native evidence.
extends RefCounted

var presses := 0
var system_back := false
var calls := []


func press(n := 1) -> void:
	presses += n


func take_menu_presses() -> int:
	var n := presses
	presses = 0
	return n


func set_system_back(on: bool) -> bool:
	system_back = on
	calls.append(on)
	return true


func arm_system_back(_seconds: float) -> bool:
	return set_system_back(true)


## What the native side does on a timeout or on another UIKit press while armed.
func drop_system_back() -> void:
	system_back = false


func is_system_back() -> bool:
	return system_back


func remote_connected() -> bool:
	return true
