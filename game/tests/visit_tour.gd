## r18 animals visit houses through the real UI (design/animal-visits.md): tap Pip, Come home with me;
## Pip follows in town and through the door; it answers a dance in the living room; it follows up the
## stairs; tap it, Say goodbye, and it is back outdoors by the front door. Tumble's card has no invitation.
## Other children are covered by net_test.py --visits. At most 8 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/visit_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja --timeout=400
## Logic only, no renderer (EC2 smoke): add --headless before --path, --no-shots and --window=2208x1024
## after --.
extends "res://tests/play_tour.gd"

const AnimalBrain := preload("res://scripts/core/animal_brain.gd")

var _case_done := false


func shot(name: String) -> void:
	if _n >= 8 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/visit_%s_%02d_%s.png" % [shots, tag, _n, name])


func case_ended(what: String) -> void:
	check(_case_done, "the %s case ran to its end" % what)
	_case_done = false


func animal_at(kind: String) -> Vector2:
	for st in Animals.states:
		if st["kind"] == kind:
			return st["pos"]
	return Vector2.INF


func guest_node() -> Node3D:
	return main.world.guest_layer.guests.get("pig")


func guest_beside() -> bool:
	var n := guest_node()
	var kid: Node3D = main.world.local_kid()
	return n != null and kid != null and n.is_visible_in_tree() and Vector2(n.position.x, n.position.z).distance_to(Vector2(kid.position.x, kid.position.z)) < 2.5


## r18b: taps move the pointer to the point before the press and again before the lift, as a finger does.
## The inherited pets_tour.tap sends only press and release; on the r18 Mac run the Come home with me
## press never fired (no message, the card stayed open), the same signature as guide_tour's r16 Back
## failure: a desktop-cursor motion between press and release makes a Button treat the press as slid off.
## World taps (tap_at_world) use this too. Assertions are unchanged.
func tap(canvas_pos: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_final_transform() * canvas_pos
	for pressed in [true, false]:
		var m := InputEventMouseMotion.new()
		m.position = screen
		m.global_position = screen
		m.button_mask = 0 if pressed else MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		if pressed:
			await _between_press_and_lift()
		await get_tree().process_frame


## Diagnosis hook (the r18b probe injects a desktop-cursor motion here); nothing happens in the tour.
func _between_press_and_lift() -> void:
	pass


func card_button(hud: Control, name: String) -> Button:
	return hud._overlay.find_child(name, true, false) as Button


## Presses a card button once the card has been laid out (a fresh dialog's rects are not final in its
## first frame), and only where a finger could: on screen and inside the safe area.
func press_card(b: Button, what: String) -> void:
	await frames(4)
	var r := b.get_global_rect()
	check(playable_rect().encloses(r) and r.size.x > 40.0, "%s is on screen and in the safe area (%s)" % [what, r])
	await press(b)


## Shows the message, then waits for it to fade so the next picture is clean (bench r17 shot-03 note).
func message_shown(hud: Control, text: String) -> bool:
	var seen := await until(func(): return hud._toast_label.text == text and hud._toast.modulate.a > 0.5, 4.0)
	await feedback_settled()
	return seen


func feedback_settled() -> void:
	await until(func(): return main.hud._toast.modulate.a <= 0.01, 5.0)
	await frames(3)


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("VISIT %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://visit_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	_case_done = false
	await _invite(hud, c)
	case_ended("invite")
	await _inside(hud, c)
	case_ended("inside")
	await _goodbye(hud, c)
	case_ended("goodbye")
	for loc in locales.slice(1):
		await _card_in(loc, hud, c)
		case_ended("[%s] card" % loc)
	print("VISIT %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## Tap Pip, see the card, Come home with me; Pip follows across town to the door.
func _invite(hud: Control, c: Node) -> void:
	check(await until(func(): return animal_at("pig") != Vector2.INF, 10.0), "Pip is in town")
	# Tumble's card has no invitation (too big for the door).
	hud._open_animal("elephant")
	await frames(3)
	check(card_button(hud, "VisitInvite") == null, "Tumble's card does not offer Come home with me")
	await close_dialogs()
	c.pos = animal_at("pig") + Vector2(2.0, 1.0)
	c._place_kid()
	main.rig.snap()
	await settle_camera()
	var pig: Node3D = main.world.animals.get("pig")
	if pig == null:
		check(false, "Pip is drawn")
		return
	await tap_at_world(pig.global_position + Vector3(0, 0.4, 0), "Pip")
	var b := card_button(hud, "VisitInvite")
	check(await until(func(): b = card_button(hud, "VisitInvite"); return b != null and b.is_visible_in_tree(), 4.0), "Pip's card offers %s" % tr("Come home with me"))
	if b == null:
		return
	await shot("pip_card_invite")
	await press_card(b, tr("Come home with me"))
	await frames(3)
	print("DIAG after invite: message '%s', Pip %.1f m from me, card open %s" % [hud._toast_label.text, animal_at("pig").distance_to(c.pos), card_button(hud, "VisitInvite") != null])
	check(await message_shown(hud, tr("%s is coming home with you!") % tr("Pip")), "the message says Pip is coming home")
	check(Animals.guests.get("pig", 0) == Session.my_id, "Pip visits me")
	# Children walk in straight lines, so the walk to the door starts on the open path in front of it
	# (3 m out); Pip has to come across town to catch up.
	var houses: Array = Session.model.items_in("town").filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(x, y): return TownModel.door_point(x).distance_to(c.pos) < TownModel.door_point(y).distance_to(c.pos))
	var door := TownModel.door_point(houses[0])
	c.pos = door + TownModel.facing(houses[0]["rot"]) * 3.0
	c._place_kid()
	main.rig.snap()
	c._send_state()
	check(await until(func(): return animal_at("pig").distance_to(c.pos) < 3.0, 20.0), "Pip comes across town after me (%.1f m)" % animal_at("pig").distance_to(c.pos))
	c.walk_to_door()
	check(await until(func(): return c.pos.distance_to(door) < 1.2, 15.0), "walked to the front door (%s)" % c.pos)
	await wait(1.5)   # Pip catches up
	check(animal_at("pig").distance_to(c.pos) < 3.5, "Pip followed me to the door (%.1f m)" % animal_at("pig").distance_to(c.pos))
	await settle_camera()
	await shot("pip_follows_to_door")
	_case_done = true


## Inside: Pip comes in, answers a dance, and follows up the stairs.
func _inside(hud: Control, c: Node) -> void:
	print("DIAG at the door: me %s, nearest door ctx %s" % [c.pos, c._ctx])
	check(await use_context("enter", 15.0), "the door offers Go inside")
	await wait(1.0)
	check(c.space != "town", "inside the house")
	check(await until(guest_beside, 5.0), "Pip came into the living room with me")
	await walk_to(Vector2(0.5, 1.0))
	await wait(2.0)
	check(guest_beside(), "Pip keeps beside me in the room")
	await settle_camera()
	await shot("pip_in_living_room")
	var dance: Button = null
	for b in hud._emotes.get_children():
		if (b as Button).tooltip_text == "Dance":
			dance = b
	check(dance != null, "the Dance button is there")
	if dance:
		await press(dance)
		check(await until(func(): return guest_node() != null and guest_node().action == "dance", 3.0), "Pip answers my dance with a dance")
		await shot("pip_answers_dance")
	var stairs: Array = c.portal_contexts().filter(func(p): return p.get("label", "") == "Go upstairs")
	check(not stairs.is_empty(), "the living room has stairs up")
	if stairs.is_empty():
		return
	await walk_to(stairs[0]["at"])
	check(await use_context(stairs[0]["type"], 10.0), "the stairs offer Go upstairs")
	await wait(1.0)
	check(TownModel.parse_room(c.space).get("floor", 0) == 1, "upstairs")
	check(await until(guest_beside, 5.0), "Pip followed me up the stairs")
	await walk_to(Vector2(1.0, 0.8))
	await wait(2.0)
	await settle_camera()
	await shot("pip_upstairs")
	_case_done = true


## Tap Pip, Say goodbye: it is back outdoors by the front door.
func _goodbye(hud: Control, c: Node) -> void:
	var n := guest_node()
	if n == null:
		check(false, "Pip is drawn upstairs")
		return
	await settle_camera()
	await tap_at_world(n.global_position + Vector3(0, 0.4, 0), "Pip indoors")
	var b := card_button(hud, "VisitGoodbye")
	check(await until(func(): b = card_button(hud, "VisitGoodbye"); return b != null and b.is_visible_in_tree(), 4.0), "Pip's card offers %s" % tr("Say goodbye"))
	if b == null:
		return
	await shot("pip_card_goodbye")
	await press_card(b, tr("Say goodbye"))
	check(await message_shown(hud, tr("%s went back outside.") % tr("Pip")), "the message says Pip went back outside")
	check(Animals.guests.is_empty() and guest_node() == null, "the visit ended and Pip is not drawn inside")
	var house := TownModel.house_of(c.space)
	var door := TownModel.door_point(Session.model.items[house])
	check(animal_at("pig").distance_to(door) < 2.0, "Pip is outdoors by the front door (%.1f m)" % animal_at("pig").distance_to(door))
	c.exit_house()
	await wait(1.0)
	check(c.space == "town" and main.world.animals["pig"].visible, "outside again, Pip is in town")
	await settle_camera()
	await shot("pip_back_outside")
	_case_done = true


## The cards in another language (invitation on the game card).
func _card_in(loc: String, hud: Control, c: Node) -> void:
	I18n.set_locale(loc)
	await frames(3)
	hud._open_animal("sheep")
	await frames(3)
	var b := card_button(hud, "VisitInvite")
	check(b != null and b.text == "Come home with me" and (loc == "en" or tr(b.text) != b.text), "[%s] Wooly's card offers the invitation, translated (%s)" % [loc, tr("Come home with me")])
	await shot("%s_wooly_card" % loc)
	await close_dialogs()
	_case_done = true
