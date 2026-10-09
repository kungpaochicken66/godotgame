## Focused check of the play ideas batch 2 (design/playability-8-12.md) through
## the real UI: Dress up (hats, colors), a three-panel Story with poses, a
## Trail followed with clue emotes, a Music box tune with Play and Mute, and a
## toy Track ball (finish, a gap, a switch). At most 10 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/play2_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path and --no-shots after --.
## Without a renderer the camera has no picture, so --no-shots hands the story
## three blank panels instead of pressing the shutter; track pieces are laid out
## through the session (exact cells), then rolled, flipped and fixed by taps.
extends "res://tests/play_tour.gd"

const Story := preload("res://scripts/core/story.gd")
const Avatar := preload("res://scripts/core/avatar.gd")


func shot(name: String) -> void:
	if _n >= 10 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/play2_%s_%02d_%s.png" % [shots, tag, _n, name])


func tooltip_button(root: Node, tip: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.tooltip_text == tip and b.is_visible_in_tree():
			return b
	return null


func go(p: Vector2) -> void:
	main.controller._walk_target = null   # stop any walk in progress (Join, a tapped item)
	main.controller._pending_ctx = {}
	main.controller.pos = p
	main.controller._place_kid()
	await wait(0.6)


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "300"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "300"))
		print("PLAY2 %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://play2_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	await _dress(hud, c)
	await _story(hud, c)
	await _trail(hud, c)
	await _music(hud, c)
	await _tracks(hud, c)
	for loc in locales:
		await _fit_in(loc, hud, area)
	print("PLAY2 %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## F07: Dress up opens a card; a hat and a color change the child in town.
func _dress(hud: Control, c: Node) -> void:
	await press(hud._dress_btn)
	check(await until(func(): return hud._overlay.get_node_or_null("DressUp") != null, 3.0), "Dress up opens its card")
	await frames(4)
	await press(find_button(hud._overlay, "hat", "chef"))
	check(await until(func(): return Session.players[Session.my_id]["avatar"]["hat"] == "chef", 5.0), "the chef hat is on")
	await frames(4)
	await press(find_button(hud._overlay, "outfit_color", 3))
	check(await until(func(): return Session.players[Session.my_id]["avatar"]["outfit_color"] == 3, 5.0), "the clothes color changed")
	var kid: Node3D = main.world.local_kid()
	check(kid != null and kid.get_node_or_null("Body/Head/Hat") != null and kid.get_node("Body/Head/Hat").get_child_count() > 0, "the hat is drawn on the child (Body/Head/Hat)")
	await shot("dress_up")
	await close_dialogs()
	check(main.menus.avatar.get("hat") == "chef", "the new look is kept for next time")


## F05: a story card, poses, three pictures, rearranged and kept.
func _story(hud: Control, c: Node) -> void:
	var before: int = Story.list().size()
	await press(hud._story_btn)
	check(await until(func(): return hud._overlay.get_node_or_null("StoryCards") != null, 3.0), "Story opens the inspiration cards")
	await frames(4)
	await press(find_button(hud._overlay, "story_card", "rain"))
	check(not hud.story.is_empty() and hud._play_chip.visible and hud._poses.visible, "a story is in progress with poses to pick")
	await press(find_button(hud._poses, "pose", "surprised"))
	check(main.world.local_kid().emote_kind == "surprised", "the child strikes the Surprised pose")
	for i in Story.PANELS:
		if main.args.has("no-shots"):
			var img := Image.create(320, 240, false, Image.FORMAT_RGBA8)
			img.fill([Color.RED, Color.GREEN, Color.BLUE][i])
			hud.story_add_panel(img)
		else:
			await press(tooltip_button(hud, "Take a photo"))
			await wait(0.6)
		if i == 0:
			await shot("story_chip")
	check(await until(func(): return hud._overlay.get_node_or_null("StoryArrange") != null, 5.0), "after three pictures the story can be arranged")
	await frames(4)
	await press(find_button(hud._overlay, "story_move", [0, 1]))
	await frames(4)
	await shot("story_arrange")
	await press(find_button(hud._overlay, "dialog_button", "Keep story"))
	check(await until(func(): return Story.list().size() == before + 1, 5.0), "the story is kept on the device")
	if main.args.has("no-shots") and Story.list().size() == before + 1:
		var strip := Image.load_from_file(ProjectSettings.globalize_path(Story.list()[0]["png"]))
		check(strip.get_pixel(Story.GAP + 10, Story.GAP + 10).is_equal_approx(Color.GREEN), "the kept strip uses the new order (second picture first)")
		check(Story.list()[0]["card"] == "rain", "with its card")
	check(hud.story.is_empty() and not hud._poses.visible, "the story mode ends")
	await close_dialogs()


## F06: two signs, Follow the trail, the right clue at each sign.
func _trail(hud: Control, c: Node) -> void:
	await go(Vector2(-8, -14))
	var s1 := await place_from_toybox("Play", "trail_sign")
	await go(Vector2(-2, -14))
	var s2 := await place_from_toybox("Play", "trail_sign")
	check(s1 != "" and s2 != "" and Session.model.trail_signs().size() == 2, "two trail signs placed from the toy box")
	if Session.model.trail_signs().size() < 2:
		return
	await tap_item(s1)
	check(await until(func(): return hud._overlay.get_node_or_null("TrailSign") != null, 10.0), "tapping a sign opens its card")
	await frames(4)
	await shot("trail_sign")
	await press(find_button(hud._overlay, "dialog_button", "Follow the trail"))
	check(await until(func(): return not hud.trail.is_empty() and hud._play_chip.visible, 5.0), "following the trail shows the next sign")
	for i in 2:
		var sign: Dictionary = Session.model.trail_signs()[i]
		check(main.world.play_fx.trail_target == sign["id"], "the arrow points at sign %d" % (i + 1))
		await go(Vector2(sign["x"], sign["z"] + 1.0))
		await press(tooltip_button(hud, "Wave"))
		if i == 0:
			check(await until(func(): return hud.trail.get("found", 0) == 1, 5.0), "a wave at sign 1 finds it")
	check(await until(func(): return hud.trail.is_empty() and Session.model.keepsakes.size() == 1, 5.0), "the trail is finished with a keepsake")


## F08: a tune on the grid, Play, hear it nearby, mute on this device.
func _music(hud: Control, c: Node) -> void:
	await go(Vector2(8, -12))
	var mb := await place_from_toybox("Music Corner", "music_box")
	if mb == "":
		return
	await tap_item(mb)
	check(await until(func(): return hud._overlay.get_node_or_null("Music") != null, 10.0), "tapping the music box opens its card")
	await frames(4)
	var cell := find_button(hud._overlay, "note", [2, 5])
	await press(cell)
	check(await until(func(): return int(Session.model.items[mb]["song"][2]) & (1 << 5) != 0, 5.0), "tapping a square adds a chime")
	check(await until(func(): return cell.get_meta("on", false), 3.0), "the square lights up")
	await press(hud._overlay.find_child("PlayButton", true, false))
	check(await until(func(): return Session.model.items[mb]["on"], 5.0), "Play starts the loop")
	await shot("music_box")
	var fx: Node = main.world.play_fx
	var before: int = fx.notes_played
	check(await until(func(): return fx.notes_played > before, 6.0), "the tune plays nearby")
	await press(hud._overlay.find_child("MuteButton", true, false))
	check(Sfx.music_boxes_muted, "Mute music boxes silences them on this device")
	await wait(0.6)
	var muted_at: int = fx.notes_played
	await wait(2.0)
	check(fx.notes_played == muted_at, "no notes while muted")
	await press(hud._overlay.find_child("MuteButton", true, false))
	check(not Sfx.music_boxes_muted, "and they can be heard again")
	await close_dialogs()


## F02: roll the ball to the finish, see a gap, flip a switch.
func _tracks(hud: Control, c: Node) -> void:
	var base := Vector2(99, 99)
	for x in range(6, 20):
		for z in range(-18, 14):
			if base.x != 99:
				break
			var fits := true
			for i in 3:
				for dx in [0, 1]:
					if Session.model.check("track_straight", "town", x + dx, z + i, 0) != "":
						fits = false
			if fits:
				base = Vector2(x, z)
	check(base.x != 99, "found room for a track")
	var put := func(kind: String, at: Vector2, rot := 0) -> String:
		return (await _result_of(Session.place(kind, "town", at, rot, -2))).get("item", {}).get("id", "")
	var start: String = await put.call("track_start", base)
	var sw: String = await put.call("track_switch", base + Vector2(0, 1))
	var fin: String = await put.call("track_finish", base + Vector2(0, 2))
	await put.call("track_finish", base + Vector2(1, 1))
	await go(base + Vector2(-1.5, 0))
	await tap_item(start)
	check(await until(func(): return not main.world.play_fx.balls.is_empty(), 6.0), "tapping the start rolls a ball")
	await shot("track_ball")
	check(await until(func(): return main.world.play_fx.balls.is_empty(), 8.0), "the ball reaches the finish and is caught")
	Session.remove(fin)
	await wait(0.6)
	await tap_item(start)
	check(await until(func(): return main.world.play_fx._gap_arrow.visible, 6.0), "a gap: the ball waits and an arrow shows where")
	check(hud._hint.text == "The ball is waiting: a piece is missing here.", "and says what is missing (%s)" % hud._hint.text)
	await shot("track_gap")
	await tap_item(sw)
	check(await until(func(): return int(Session.model.items[sw].get("variant", 0)) == 1, 6.0), "tapping the switch flips it")
	await wait(3.0)
	var ends := []
	var cb := func(_id, _cells, end, _at, _bells): ends.append(end)
	Session.track_rolled.connect(cb)
	await tap_item(start)
	await until(func(): return not ends.is_empty(), 6.0)
	Session.track_rolled.disconnect(cb)
	check(ends == ["finish"], "now the ball goes to the side finish (%s)" % [ends])


func _result_of(req: int) -> Dictionary:
	var out := {}
	var cb := func(r_id: int, r: Dictionary):
		if r_id == req:
			out.merge(r)
	Session.request_done.connect(cb)
	await frames(5)
	Session.request_done.disconnect(cb)
	return out


## The new cards fit the safe area in this language.
func _fit_in(loc: String, hud: Control, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	for spec in [["dress", func(): hud.open_dress_up()], ["story cards", func(): hud.open_story_cards()],
			["music", func(): hud._open_music(Session.model.items.values().filter(func(i): return i["kind"] == "music_box")[0]["id"])]]:
		spec[1].call()
		await frames(4)
		var r := dialog_rect(hud)
		check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the %s card fits the safe area (%s)" % [loc, spec[0], r])
		if spec[0] == "music":
			await shot("%s_music_card" % loc)
		await close_dialogs()
