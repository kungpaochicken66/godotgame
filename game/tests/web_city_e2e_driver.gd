## The Godot side of the web city's end-to-end check (scripts/web_city/e2e.mjs drives the page in Chromium):
## a solo game, the child rides to city_web, and its state is printed five times a second as
##   E2E STATE {"space", "pos" [x, z], "level", "weather", "journey", "walking"}
## for the Node script to compare with what the page asked for. When the child is home again (the page's Town
## button) it prints "E2E DRIVER home" and quits two seconds later.
##   scripts/godot.sh --headless --path game -- --driver=res://tests/web_city_e2e_driver.gd --web-city \
##       [--web-city-http=N --web-city-ws=N] [--timeout=240]
extends Node

const Places := preload("res://scripts/core/places.gd")

var main: Node


func _ready() -> void:
	_run.call_deferred()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func until(cond: Callable, timeout := 10.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await wait(0.1)
		t += 0.1
	return cond.call()


func _run() -> void:
	get_tree().create_timer(float(main.args.get("timeout", "240"))).timeout.connect(func():
		print("E2E DRIVER FAIL: timeout")
		Music.quit_game(1))
	var save := "user://web_city_e2e_town.json"
	for f in [save, save + ".bak", save + ".maps", save + ".v2"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var c: Node = main.controller
	print("E2E DRIVER web city offered: %s" % Places.available(Places.CITY_WEB))
	c.ride(Places.CITY_WEB)
	if not await until(func(): return c.space == Places.CITY_WEB and c.journey_to == "", 15.0):
		print("E2E DRIVER FAIL: the child did not arrive in city_web (space %s)" % c.space)
		Music.quit_game(1)
		return
	print("E2E DRIVER in city_web")
	var cw := get_node_or_null("/root/CityWeb")
	while true:
		print("E2E STATE " + JSON.stringify({"space": c.space, "pos": [c.pos.x, c.pos.y], "level": c.level,
			"weather": int(cw.states.get("weather", -1)) if cw else -1, "journey": c.journey_to, "walking": c._walk_target != null}))
		if c.space == Places.TOWN and c.journey_to == "":
			print("E2E DRIVER home")
			await wait(2.0)
			Music.quit_game(0)
			return
		await wait(0.2)
