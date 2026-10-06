## Rendered client for a real networked session: joins the server, waits for the
## bot friends to walk over and captures what this child sees.
extends Node

var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var shots: String = main.args.get("shots", ProjectSettings.globalize_path("user://shots"))
	while not main.thumbs.is_done:
		await get_tree().process_frame
	main.menus.avatar = load("res://scripts/core/avatar.gd").PRESETS[3]
	main._on_join(main.args.get("url", "ws://127.0.0.1:9080"), main.menus.avatar)
	print("CAP joining")
	var t := 0.0
	while (Session.players.size() < 3 or not Session.model.lanterns.has("pond_picnic")) and t < 60.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if int(t * 2) % 10 == 0:
			print("CAP t=%.0f state=%s players=%d fps=%d" % [t, Session.state, Session.players.size(), Engine.get_frames_per_second()])
	print("CAP players=%d after %.1fs" % [Session.players.size(), t])
	main.controller.pos = Vector2(0.2, 11.6)
	main.controller.ry = PI
	main.controller._place_kid()
	await get_tree().create_timer(4.0).timeout
	Session.send_emote("cheer")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/net_friends.png")
	print("NETCAPTURE players=%d lanterns=%s" % [Session.players.size(), Session.model.lanterns.keys()])
	Session.leave()
	get_tree().quit()
