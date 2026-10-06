## Entry point. Wires menus, the 3D town, the local player and the HUD, or runs
## a headless dedicated town server.
##
## User arguments (after "--" on the Godot command line):
##   --server [--port=9080] [--bind=*] [--save=user://town_server.json]
##   --driver=res://tests/<script>.gd   attach an automated test driver
##   --safe-insets=l,t,r,b              simulate device safe-area insets (layout tests)
extends Node

const Thumbnails := preload("res://scripts/ui/thumbnails.gd")
const TownWorld := preload("res://scripts/world/town_world.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const PlayController := preload("res://scripts/world/play_controller.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Menus := preload("res://scripts/ui/menus.gd")

const SOLO_SAVE := "user://town_solo.json"
const HOST_SAVE := "user://town_hosted.json"

var args := {}
var world: Node3D
var rig: Node3D
var controller: Node
var hud: Control
var menus: Control
var thumbs: Node
var _last_join := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.has("server"):
		_run_server()
		return
	if args.has("safe-insets"):
		var v: PackedFloat64Array = args["safe-insets"].split_floats(",")
		if v.size() == 4:
			preload("res://scripts/ui/ui_kit.gd").test_insets = Vector4(v[0], v[1], v[2], v[3])
	thumbs = Thumbnails.new()
	add_child(thumbs)
	world = TownWorld.new()
	world.name = "World"
	add_child(world)
	rig = CameraRig.new()
	add_child(rig)
	controller = PlayController.new()
	add_child(controller)
	controller.setup(world, rig)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hud.bind(controller, thumbs)
	menus = Menus.new()
	ui.add_child(menus)
	menus.play_solo.connect(_on_play_solo)
	menus.join_server.connect(_on_join)
	menus.host_town.connect(_on_host)
	controller.space_changed.connect(func(space): Music.set_context("town" if space == "town" else "home"))
	hud.leave_requested.connect(_leave)
	hud.photo_requested.connect(_take_photo)
	hud.reconnect_requested.connect(func(): _on_join(_last_join.get("url", ""), _last_join.get("avatar", {})))
	Session.joined.connect(_on_joined)
	Session.rejected.connect(func(reason): menus.set_status(reason))
	Session.connection_changed.connect(_on_connection)
	_show_menus(true)
	if args.has("driver"):
		var driver = load(args["driver"]).new()
		driver.set("main", self)
		add_child(driver)


func _run_server() -> void:
	var port := int(args.get("port", Session.DEFAULT_PORT))
	var save: String = args.get("save", "user://town_server.json")
	var err := Session.start_server(save, port, args.get("bind", "*"))
	if err != OK:
		printerr("[server] could not listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		# iPadOS may suspend the app at any time: save the solo/hosted town now.
		if Session.is_authority() and Session.dirty:
			Session.save_now()


func _show_menus(on: bool) -> void:
	Music.set_context("menu" if on else ("town" if controller.space == "town" else "home"))
	menus.set_active(on)
	hud.visible = not on
	world.visible = not on
	controller.enabled = not on
	if not on:
		rig.camera.current = true


func _on_play_solo(avatar: Dictionary) -> void:
	Session.start_solo(SOLO_SAVE, avatar)


func _on_host(avatar: Dictionary) -> void:
	var err := Session.start_host(HOST_SAVE, avatar)
	if err != OK:
		menus.set_status("Could not reach the town.")


func _on_join(url: String, avatar: Dictionary) -> void:
	if url == "":
		return
	_last_join = {"url": url, "avatar": avatar}
	if Session.join(url, avatar) != OK:
		menus.set_status("Could not reach the town.")


func _on_joined(_id: int) -> void:
	_show_menus(false)


func _on_connection(state: String) -> void:
	if state == "failed" and menus.visible:
		menus.set_status("Could not reach the town.")


func _leave() -> void:
	Session.leave()
	_show_menus(true)


## Hides the interface for one frame and keeps the picture in the scrapbook.
func _take_photo() -> void:
	hud.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = true
	Sfx.play("photo")
	if img == null or img.is_empty():
		return
	DirAccess.make_dir_recursive_absolute("user://photos")
	img.save_png("user://photos/photo_%d.png" % Time.get_unix_time_from_system())
	img.resize(img.get_width() / 3, img.get_height() / 3)
	hud.add_photo(ImageTexture.create_from_image(img))
