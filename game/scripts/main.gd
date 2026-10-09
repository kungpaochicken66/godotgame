## Entry point. Wires menus, the 3D town, the local player and the HUD, or runs
## a headless dedicated town server.
##
## User arguments (after "--" on the Godot command line):
##   --server [--port=9080] [--bind=*] [--save=user://town_server.json]
##   --driver=res://tests/<script>.gd   attach an automated test driver
##   --safe-insets=l,t,r,b              simulate device safe-area insets (layout tests)
extends Node

const Deployment := preload("res://scripts/net/deployment.gd")
const Thumbnails := preload("res://scripts/ui/thumbnails.gd")
const TownWorld := preload("res://scripts/world/town_world.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const PlayController := preload("res://scripts/world/play_controller.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Menus := preload("res://scripts/ui/menus.gd")
const PhotoIdeas := preload("res://scripts/core/photo_ideas.gd")
const PhotoStore := preload("res://scripts/core/photo_store.gd")
const Story := preload("res://scripts/core/story.gd")

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
var photo_library: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	get_tree().auto_accept_quit = false   # closing the window goes through Music.quit_game
	if args.has("server"):
		_run_server()
		return
	if args.has("safe-insets"):
		var v: PackedFloat64Array = args["safe-insets"].split_floats(",")
		if v.size() == 4:
			preload("res://scripts/ui/ui_kit.gd").test_insets = Vector4(v[0], v[1], v[2], v[3])
	thumbs = Thumbnails.new()
	add_child(thumbs)
	photo_library = preload("res://scripts/ui/photo_library.gd").new()
	add_child(photo_library)
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
	hud.story_kept.connect(_keep_story)
	# Dress-up changes made in town are kept for next time (F07).
	Session.avatar_changed.connect(func(peer):
		if peer == Session.my_id and Session.players.has(peer):
			menus.avatar = Session.players[peer]["avatar"].duplicate()
			menus._save())
	# Reconnect with the outfit as it is now (dress-up and wardrobe changes since joining), not as it was.
	hud.reconnect_requested.connect(func(): _on_join(_last_join.get("url", ""), menus.avatar if not menus.avatar.is_empty() else _last_join.get("avatar", {}), _last_join.get("invite", "")))
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
	# Optional town invite from a restricted file (docs/deployment.md); never printed.
	var invite_path: String = args.get("invite-file", OS.get_environment("LANTERN_LANE_INVITE_FILE"))
	var town_invite := ""
	if invite_path != "":
		var r: Dictionary = Deployment.read_invite_file(invite_path)
		if not r["ok"]:
			printerr("[server] invite configuration error: %s" % r["reason"])
			Music.quit_game(2)
			return
		if r["loose"]:
			print("[server] warning: the invite file is readable by other users; restrict it (chmod 600)")
		town_invite = r["invite"]
	var err := Session.start_server(save, port, args.get("bind", "*"), town_invite)
	if err != OK:
		printerr("[server] could not listen on port %d (error %d)" % [port, err])
		Music.quit_game(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		# iPadOS may suspend the app at any time: save the solo/hosted town now.
		if Session.is_authority() and Session.dirty:
			Session.save_now()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Music.quit_game(0)   # desktop close: release audio before exit


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


func _on_join(url: String, avatar: Dictionary, invite := "") -> void:
	if url == "":
		return
	_last_join = {"url": url, "avatar": avatar, "invite": invite}
	if Session.join(url, avatar, invite) != OK:
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
## Asks the system to add the picture to Photos and reports only its real answer.
func _save_to_photos(abs_path: String) -> void:
	photo_library.save(abs_path)
	var result: String = await photo_library.finished
	hud.photo_result(result, func(): _save_to_photos(abs_path), func(): photo_library.open_settings())


## A finished three-panel story: compose the strip, keep it on the device (and in
## Photos where available, with the system's real answer).
func _keep_story(panels: Array, order: Array, card_id: String) -> void:
	var title: String = Story.card(card_id)["title"]
	var caption: Image = await _caption_image(tr(title)) if title != "" else null
	var strip := Story.compose(panels, order, caption)
	var path := Story.save(strip, card_id, int(Time.get_unix_time_from_system()))
	if path == "":
		hud.show_toast("The story could not be kept.")
		return
	if photo_library.available():
		_save_to_photos(ProjectSettings.globalize_path(path))
	else:
		hud.show_toast("Story kept in the scrapbook.")


## The story title as a picture (r11 caption), drawn once in an off-screen
## viewport with the game's font. Without a renderer it is empty and the strip
## simply has no title band.
func _caption_image(text: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 64)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", I18n.ui_font())
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_color", Color("#7a5a3a"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(1200, 64)
	vp.add_child(l)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img if img != null and not img.is_empty() else null


func _take_photo() -> void:
	hud.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = true
	Sfx.play("photo")
	if img == null or img.is_empty():
		return
	# Making a story (F05): the picture is a panel; the strip is kept at the end.
	if not hud.story.is_empty():
		hud.story_add_panel(img)
		return
	# Kept in the game's own folder for the scrapbook, also after a restart (r16, PhotoStore).
	var name := PhotoStore.save(img)
	img.resize(img.get_width() / 3, img.get_height() / 3)
	# On iPhone and iPad the picture also goes to Photos; the message waits for the system's answer.
	var to_photos: bool = photo_library.available() and name != ""
	hud.add_photo(ImageTexture.create_from_image(img), not to_photos, name)
	if to_photos:
		_save_to_photos(ProjectSettings.globalize_path(PhotoStore.DIR.path_join(name)))
	# Photo ideas (activity G): checked from what the camera saw, not from the pixels.
	var ideas := PhotoIdeas.evaluate(world.photo_facts(rig.camera))
	if not ideas.is_empty():
		var req: int = Session.report_photo(ideas)
		controller._ask(req, func(r):
			for idea in r.get("new", []):
				hud.show_toast(tr("Photo idea done: %s") % tr(PhotoIdeas.text_of(idea))))
