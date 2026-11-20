## The first-steps guide through the real UI (design/experience-plan.md, issue 1): a child new on
## this device is told how to walk, then how to build, then where ideas are; each line goes when
## it is done; nothing shows a second time; the line can be hidden; it never covers a control.
## Touch (default) and controller (--tv). It needs --first-steps (other tours run without the
## guide) and a fresh user-data folder (the guide is remembered in the device's settings).
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/first_steps_tour.gd --first-steps \
##                   --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/first_steps_tour.gd --first-steps \
##                   --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv --locales=en,zh-CN,ja,es,fr,de
## Logic only, no renderer (EC2): add --headless before --path, and --no-shots --window=WxH after --.
## Its town is its own save (user://first_steps_tour_town.json). At most 20 screenshots (a six-language run takes 18).
extends "res://tests/town_play_tour.gd"

const FirstSteps := preload("res://scripts/core/first_steps.gd")
const ActivityGuide := preload("res://scripts/ui/activity_guide.gd")
const FIRST_TOWN := "user://first_steps_tour_town.json"


func shot(name: String) -> void:
	if _n >= 20 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/first_steps_%s_%02d_%s.png" % [shots, tag, _n, name])


## The line is on screen, inside the safe area, and over no button or other message.
func chip_ok(what: String, expect: String) -> void:
	var hud: Control = main.hud
	var chip: Control = hud._first_chip
	await frames(4)
	check(chip.is_visible_in_tree() and hud._first_label.text == expect, "%s: the line reads \"%s\" (%s)" % [what, expect, hud._first_label.text])
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	var r: Rect2 = chip.get_global_rect()
	check(area.grow(1.0).encloses(r), "%s: the line is inside the safe area (%s in %s)" % [what, r, area])
	var over := []
	for b in hud.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and not chip.is_ancestor_of(b) and b.get_global_rect().intersects(r) and b.get_global_rect().has_area():
			over.append(str(b.name))
	check(over.is_empty(), "%s: the line covers no button (%s)" % [what, str(over)])
	check(not hud._toast.get_global_rect().intersects(r) or hud._toast.modulate.a < 0.05, "%s: the line and a message do not share a place" % what)
	var need: float = hud._first_label.get_theme_font("font").get_string_size(tr(expect), HORIZONTAL_ALIGNMENT_LEFT, -1, hud._first_label.get_theme_font_size("font_size")).x
	check(need <= hud._first_label.size.x + 1.0, "%s: the whole line fits (%d px of %d)" % [what, int(need), int(hud._first_label.size.x)])
	if tv:
		await hints_ok(what)


func guide_cards() -> Array:
	var grid: Control = main.hud._overlay.find_child("GuideCards", true, false)
	return grid.get_children().filter(func(x): return not x.is_queued_for_deletion()) if grid else []


## The guide's second section: six things to build and try, each leading into the game.
func _guide_make(hud: Control, c: Node) -> void:
	await set_steps(true, true, true)
	await calm()
	await act(hud._guide_btn, "Activities")
	check(await until(func(): return hud.guide_open(), 2.0), "the guide opens")
	await frames(4)
	check(guide_cards().size() == 8, "on the eight activities, as before")
	var make: Button = find_button(hud._overlay, "guide_section", "make")
	check(make != null and find_button(hud._overlay, "guide_section", "do") != null, "with two sections to choose from")
	await act(make, "Things to build")
	await frames(4)
	var list := guide_cards()
	check(list.map(func(x): return x.get_meta("guide_id")) == ActivityGuide.MAKE.map(func(e): return e["id"]), "the second section lists the six things to build (%s)" % str(list.map(func(x): return x.get_meta("guide_id"))))
	var textures := {}
	for card in list:
		var art := card.find_child("Art", true, false) as TextureRect
		if art and art.texture:
			textures[art.texture.get_rid()] = true
	check(textures.size() == 6, "each with its own picture")
	if tv:
		await hints_ok("the guide's second section")
	await shot("guide_make")
	# Contraptions: its how-to, then straight into the toy box on its tab.
	await act(find_button(hud._overlay, "guide_id", "contraptions"), "Contraptions")
	await frames(4)
	var detail: Control = hud._overlay.find_child("GuideDetail", true, false)
	check(detail != null and detail.get_meta("guide_id") == "contraptions", "a card opens its how-to")
	await shot("guide_contraptions")
	await act(hud._overlay.find_child("GuideGo", true, false), "Open the toy box")
	check(await until(func(): return c.mode == "decorate" and not hud.guide_open(), 3.0), "Open the toy box closes the guide and opens Decorate")
	await frames(4)
	check(hud._category == "Contraptions" and hud._hint.text == RoomThemes.TOOLKIT_IDEAS["Contraptions"], "on the Contraptions tab, with its idea line (%s)" % hud._category)
	check(find_button(hud._cards, "kind", "push_button") != null, "and the Big button is right there")
	await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done")
	# A hello: the guide leads to Leave a hello.
	hud.open_guide("hello")
	await frames(4)
	check(find_button(hud._overlay, "guide_section", "make") == null and hud._overlay.find_child("GuideDetail", true, false) != null, "a how-to can be opened directly")
	await act(hud._overlay.find_child("GuideGo", true, false), "Leave a hello")
	check(await until(func(): return dialog("EchoRecorder") != null, 2.0), "Leave a hello opens from the guide")
	hud._close_overlay()
	await frames(4)
	# Evening lamps: walks to the evening bell.
	hud.open_guide("evening")
	await frames(4)
	var before: Vector2 = c.pos
	await act(hud._overlay.find_child("GuideGo", true, false), "Go there")
	check(await until(func(): return not hud.guide_open() and c.pos.distance_to(before) > 0.5, 4.0), "Go there walks toward the evening bell")
	check(await until(func(): return c.pos.distance_to(main.world.activity.point("bell")) < 2.5, 15.0), "and arrives next to it (%.1f m)" % c.pos.distance_to(main.world.activity.point("bell")))
	# Cart rides from indoors: told to go outside, and nothing else happens.
	var house: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "cottage")[0]
	c.enter_house(house["id"])
	check(await until(func(): return c.space != "town", 4.0), "set up: indoors")
	await frames(6)
	hud.open_guide("rides")
	await frames(4)
	await act(hud._overlay.find_child("GuideGo", true, false), "Open the toy box")
	await frames(4)
	check(hud._toast_label.text == "Those things go outdoors. Go outside first." and c.mode == "play" and hud.guide_open(), "indoors, the cart rides entry says to go outside and stays open (%s)" % hud._toast_label.text)
	hud._close_overlay()
	await frames(3)
	c.exit_house()
	check(await until(func(): return c.space == "town", 4.0), "set up: outdoors again")
	await frames(6)
	# The guide opens on the eight activities again.
	await act(hud._guide_btn, "Activities")
	await frames(4)
	check(guide_cards().size() == 8, "the next time, the guide opens on the eight activities")
	hud._close_overlay()
	await frames(4)
	park_animals()
	_case_ok = true


func set_steps(walk: bool, build: bool, guide: bool, hidden := false) -> void:
	main.hud.first_steps = {"walk": walk, "build": build, "guide": guide, "hidden": hidden}
	main.hud._save_first_steps()
	main.hud._first_from = null
	await frames(3)


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "500"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "500"))
		print("FIRST_STEPS %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("FIRST_STEPS start tag=%s input=%s engine=%s renderer=%s" % [tag, "controller" if tv else "touch", Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method()])
	hud._context_btn.pressed.connect(func(): _ctx_presses += 1)
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	check(hud.first_steps_enabled, "this tour runs with the first-steps guide on (--first-steps)")
	check(hud.first_steps == FirstSteps.fresh(), "the device is new: no first step is done (a fresh user-data folder is needed) (%s)" % str(hud.first_steps))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	for f in [FIRST_TOWN, FIRST_TOWN + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	check(not hud._first_chip.is_visible_in_tree(), "nothing is shown over the menus, before the town")
	Session.start_solo(FIRST_TOWN, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	Activities._wish_wait = -1.0e6   # test isolation, as in the other tours
	park_animals()
	if tv:
		await stick(false, Vector2(0.5, 0.0), 0.3)
		await frames(6)
	# 1. Walk.
	await chip_ok("on arrival", FirstSteps.line("walk", tv))
	await shot("walk")
	var from: Vector2 = c.pos
	if tv:
		await stick(true, Vector2(1.0, 0.0), 1.6)
	else:
		# A tap on plain ground a few steps away: not on a control, a name tag, a landmark, a thing or an animal.
		var cam: Camera3D = main.rig.camera
		var spot = null
		for d in [Vector2(4, 0), Vector2(-4, 0), Vector2(3, 3), Vector2(-3, 3), Vector2(0, 4), Vector2(4, -2), Vector2(-4, -2), Vector2(5, 2), Vector2(-5, 2)]:
			var p3 := Vector3(c.pos.x + d.x, 0, c.pos.y + d.y)
			var at = seen_at(p3)
			if spot == null and at != null and main.world.activity.pick(cam, at) == "" and main.world.pick_item(cam, at) == "" and main.world.pick_animal(cam, at) == "" \
					and main.world.resolve_walk(Vector2(p3.x, p3.z)).distance_to(Vector2(p3.x, p3.z)) < 0.05:
				spot = at
		check(spot != null, "there is plain ground to tap near the child")
		if spot != null:
			await tap(spot)
		await until(func(): return c.pos.distance_to(from) > 3.0, 5.0)
		if c.pos.distance_to(from) < 0.1:
			print("DIAG the child did not move: dialogs %s, context %s, mode %s" % [str(hud._overlay.get_children().map(func(n): return str(n.name))), str(c._ctx.get("type", "")), c.mode])
	check(await until(func(): return hud.first_steps["walk"], 4.0), "after a few steps the walking line is done (%.1f m walked)" % c.pos.distance_to(from))
	# 2. Build.
	await chip_ok("after walking", FirstSteps.line("build"))
	await shot("build")
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0), "Decorate opens the toy box")
	await chip_ok("with the toy box open", FirstSteps.line("build", false, true))
	check(not hud._first_chip.get_global_rect().intersects(hud._catalog.get_global_rect()), "the line is clear of the toy box")
	var tab: Button = await toybox_button(hud._tabs, "tab", "Play")
	if tab:
		await act(tab, "the Play tab")
		await frames(4)
	var made := await place_from_tab("Play", "bench")
	check(made != "" and hud.first_steps["build"], "placing a first thing finishes the building line")
	if c.mode == "decorate":
		await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done")
	# 3. Activities.
	await calm()
	await chip_ok("after a first build", FirstSteps.line("guide"))
	await shot("activities")
	await act(hud._guide_btn, "Activities")
	check(await until(func(): return hud._overlay.get_child_count() > 0, 2.0), "the guide opens")
	check(hud.first_steps["guide"] and FirstSteps.all_done(hud.first_steps), "opening it finishes the last line")
	check(not hud._first_chip.is_visible_in_tree(), "nothing is shown over the guide")
	hud._close_overlay()   # set up: the guide is closed
	await frames(4)
	check(not hud._first_chip.is_visible_in_tree() and hud._toast_label.text == FirstSteps.PRAISE, "the child is told they know the basics, once (%s)" % hud._toast_label.text)
	await shot("done")
	# Remembered on the device: a second start shows nothing.
	var cfg := ConfigFile.new()
	check(cfg.load("user://settings.cfg") == OK and cfg.get_value("first_steps", "walk", false) and cfg.get_value("first_steps", "build", false) and cfg.get_value("first_steps", "guide", false), "the three steps are in the device's settings")
	Session.leave()
	await frames(4)
	hud.first_steps = FirstSteps.fresh()
	hud._load_first_steps()
	Session.start_solo(FIRST_TOWN, main.menus.avatar)
	await wait(1.2)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	check(FirstSteps.all_done(hud.first_steps) and not hud._first_chip.is_visible_in_tree(), "the next time the town opens, nothing is shown")
	park_animals()
	# A child who already played on this device before the guide existed is not treated as a beginner.
	var old := ConfigFile.new()
	old.load("user://settings.cfg")
	old.erase_section("first_steps")
	old.set_value("toybox", "recent", ["bench"])
	old.save("user://settings.cfg")
	hud._load_first_steps()
	await frames(3)
	check(FirstSteps.all_done(hud.first_steps) and not hud._first_chip.is_visible_in_tree(), "a device whose toy box already remembers things shows no first steps")
	old.erase_section("toybox")
	old.save("user://settings.cfg")
	hud._load_first_steps()
	check(hud.first_steps == FirstSteps.fresh(), "a device with nothing remembered is a beginner's")
	# The line can be hidden, and stays hidden.
	await set_steps(false, false, false)
	check(await until(func(): return hud._first_chip.is_visible_in_tree(), 2.0), "set up: a new child again")
	await act(hud.find_child("HideFirstSteps", true, false), "Hide")
	await frames(4)
	check(not hud._first_chip.is_visible_in_tree() and hud.first_steps["hidden"], "Hide puts the line away")
	hud._load_first_steps()
	check(hud.first_steps["hidden"], "and that is remembered")
	# A dialog or a running activity comes first.
	await set_steps(false, false, false)
	c.open_panel.emit("photo_ideas", {})
	await frames(4)
	check(hud._overlay.get_child_count() > 0 and not hud._first_chip.is_visible_in_tree(), "a dialog hides the line while it is open")
	hud._close_overlay()
	await frames(4)
	check(hud._first_chip.is_visible_in_tree(), "and it is back afterwards")
	Activities.start_party()
	check(await until(func(): return hud._activity_chip.visible, 3.0), "set up: a dance party")
	await frames(3)
	check(not hud._first_chip.is_visible_in_tree(), "a running activity's chip takes the place")
	Activities.stop_party()
	check(await until(func(): return not hud._activity_chip.visible, 3.0), "set up: the party is over")
	_case_ok = true
	case_ended("first steps")
	await _guide_make(hud, c)
	case_ended("things to build in the guide")
	# Each language: every line fits and covers nothing.
	for loc in locales:
		I18n.set_locale(loc)
		await frames(4)
		await calm()
		await set_steps(false, false, false)
		await chip_ok("[%s] walk" % loc, FirstSteps.line("walk", tv))
		await set_steps(true, false, false)
		await chip_ok("[%s] build" % loc, FirstSteps.line("build"))
		await act(hud._decorate_btn, "Decorate")
		await until(func(): return c.mode == "decorate", 2.0)
		await chip_ok("[%s] build, toy box open" % loc, FirstSteps.line("build", false, true))
		await leave_decorate()
		await until(func(): return c.mode == "play", 2.0)
		await set_steps(true, true, false)
		await chip_ok("[%s] activities" % loc, FirstSteps.line("guide"))
		check(loc == "en" or tr(FirstSteps.line("guide")) != FirstSteps.line("guide"), "[%s] the line is in this language (%s)" % [loc, tr(FirstSteps.line("guide"))])
		await shot("line_%s" % loc)
		# The guide's second section in this language: six cards, and one how-to that fits.
		await set_steps(true, true, true)
		await act(hud._guide_btn, "Activities")
		check(await until(func(): return hud.guide_open(), 2.0), "[%s] the guide opens" % loc)
		await act(find_button(hud._overlay, "guide_section", "make"), "Things to build")
		await frames(4)
		var area: Rect2 = _area() if tv else hud.get_global_rect()
		var list := guide_cards()
		check(list.size() == 6, "[%s] six things to build" % loc)
		for card in list:
			check(card.size.y >= 120.0 and card.size.x >= 200.0, "[%s] card %s is a big touch target" % [loc, card.get_meta("guide_id")])
		# Every line of a card's words lies inside the card with room to spare, in both sections. (The
		# Mac's German and Japanese pictures of first-steps r1: a two-line description ran down to the
		# card's lower edge.)
		for section in ["make", "do"]:
			await act(find_button(hud._overlay, "guide_section", section), "the %s section" % section)
			await frames(4)
			var tight := []
			for card in guide_cards():
				var inner: Rect2 = card.get_global_rect()
				for l in card.find_children("*", "Label", true, false):
					var lab := l as Label
					var words_end: float = lab.get_global_rect().position.y + lab.get_line_height() * mini(lab.get_line_count(), lab.max_lines_visible if lab.max_lines_visible > 0 else lab.get_line_count())
					if words_end > inner.end.y - 8.0 or lab.get_global_rect().end.y > inner.end.y - 6.0 or lab.get_global_rect().position.y < inner.position.y:
						tight.append("%s: words end %d px from the card's edge" % [card.get_meta("guide_id"), int(inner.end.y - words_end)])
			check(tight.is_empty(), "[%s] in the %s section every card's words end at least 8 px inside the card (%s)" % [loc, section, str(tight)])
		await act(find_button(hud._overlay, "guide_section", "make"), "Things to build")
		await frames(4)
		var sec: Button = find_button(hud._overlay, "guide_section", "make")
		check(sec != null and area.grow(1.0).encloses(sec.get_global_rect()) and (loc == "en" or tr(sec.text) != sec.text), "[%s] the section is named in this language, inside the safe area (%s)" % [loc, tr(sec.text) if sec else ""])
		await shot("guide_%s" % loc)
		await act(find_button(hud._overlay, "guide_id", "rides"), "Cart rides")
		await frames(4)
		var detail: Control = hud._overlay.find_child("GuideDetail", true, false)
		check(detail != null and detail.get_meta("guide_id") == "rides", "[%s] Cart rides opens its how-to" % loc)
		if detail:
			var text: Control = detail.find_child("GuideText", true, false)
			var wide := 0.0
			for l in text.find_children("*", "Label", true, false):
				wide = maxf(wide, l.get_global_rect().end.x)
			check(wide <= area.end.x + 1.0, "[%s] its text stays inside the screen (%d of %d)" % [loc, int(wide), int(area.end.x)])
			var all: String = " ".join(text.find_children("*", "Label", true, false).map(func(l): return str(l.text)))
			check(tr("Get in the cart") in all and tr("Go!") in all and not "%s" in all, "[%s] the steps name the buttons as the game shows them" % loc)
			if tv:
				await hints_ok("[%s] the how-to" % loc)
		hud._close_overlay()
		await frames(4)
		_case_ok = true
		case_ended("[%s] first-steps lines" % loc)
	await set_steps(true, true, true)
	I18n.set_locale(locales[0])
	if tv:
		check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the controller tour (%d; first: %s)" % [_real_mouse, _real_mouse_first])
	print("FIRST_STEPS %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)
