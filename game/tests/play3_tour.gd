## Focused check of r11 (design/playability-8-12.md) through the real UI:
## Dress up with clothes style and a handheld prop; Wooly's and Tumble's games
## from their cards; a paper boat sailing and a leaf pile jump; a blueprint saved
## from a picked group, previewed, turned, placed and undone; Suggest a trail;
## invitation cards (Not now, Join) and a music part. At most 10 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/play3_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path and --no-shots after --.
## In a solo town no friend can send a real invitation, so the cards are given to
## this device the way the authority hands them over (inbox + event).
extends "res://tests/play2_tour.gd"

const Blueprints := preload("res://scripts/core/blueprints.gd")
const AnimalBrain := preload("res://scripts/core/animal_brain.gd")


func shot(name: String) -> void:
	if _n >= 10 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/play3_%s_%02d_%s.png" % [shots, tag, _n, name])


func animal_state(kind: String) -> Dictionary:
	for st in Animals.states:
		if st["kind"] == kind:
			return st
	return {}


## What a missed animal tap hit instead: open dialogs and each animal's screen distance.
func _tap_report(kind: String) -> String:
	var cam: Camera3D = main.rig.camera
	var aim := cam.unproject_position(main.world.animals[kind].global_position + Vector3(0, 0.9 if kind == "elephant" else 0.4, 0))
	var parts := ["dialogs " + str(main.hud._overlay.get_children().map(func(n): return str(n.name)))]
	for k in main.world.animals:
		var a: Node3D = main.world.animals[k]
		parts.append("%s %.0f px" % [k, cam.unproject_position(a.global_position + Vector3(0, 0.9 if k == "elephant" else 0.4, 0)).distance_to(aim)])
	return ", ".join(parts)


## Framing before a real tap (r11c Mac: a toy placed "in front of" the child can sit
## off screen toward the camera): stand beside and a little behind the thing, so it
## is near the middle of the view. The tap itself still checks it is reachable.
func frame_item(id: String) -> void:
	var it: Dictionary = Session.model.items.get(id, {})
	if it.is_empty():
		return
	await go(Vector2(it["x"], it["z"]) + Vector2(1.4, -1.0))


## A town point with nothing solid within `clear` metres (a lawn for evidence views).
func _open_spot(clear: float) -> Vector2:
	for r in range(0, 22, 2):
		for k in 16:
			var p := Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * r
			if AnimalBrain.is_clear(Session.model, p, clear):
				return p
	return Vector2(0, 6)


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("PLAY3 %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://play3_tour_town.json"
	for f in [save, save + ".bak", Blueprints.PATH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	await _dress_more(hud, c)
	await _animals(hud, c)
	await _weather_toys(hud, c)
	await _blueprint(hud, c)
	await _starter_trail(hud, c)
	await _invitations(hud, c)
	await _music_part(hud, c)
	for loc in locales:
		await _fit_r11(loc, hud, area)
	print("PLAY3 %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## Clothes style and a handheld prop in Dress up (batch 2 follow-up).
func _dress_more(hud: Control, c: Node) -> void:
	await press(hud._dress_btn)
	await until(func(): return hud._overlay.get_node_or_null("DressUp") != null, 3.0)
	await frames(4)
	await press(find_button(hud._overlay, "outfit", 2))
	check(await until(func(): return Session.players[Session.my_id]["avatar"]["outfit"] == 2, 5.0), "the dress style is on")
	await frames(4)
	await press(await scrolled_to(find_button(hud._overlay, "prop", "umbrella")))
	check(await until(func(): return Session.players[Session.my_id]["avatar"]["prop"] == "umbrella", 5.0), "the umbrella is in hand")
	var kid: Node3D = main.world.local_kid()
	check(kid.get_node_or_null("Body/ArmR/Hand") != null and kid.get_node("Body/ArmR/Hand").get_child_count() > 0, "held at Body/ArmR/Hand")
	await shot("dress_prop")
	await close_dialogs()


## F03: Wooly answers emotes; Tumble sprays a star.
func _animals(hud: Control, c: Node) -> void:
	for kind in ["sheep", "elephant"]:
		check(await until(func(): return main.world.animals.has(kind), 5.0), "%s is in town" % kind)
		if kind == "elephant":
			# Evidence framing (r11 review): call Tumble to an open lawn, away from trees.
			var open_spot := _open_spot(4.0)
			Animals.brain.animals.filter(func(a): return a["kind"] == "elephant")[0]["pos"] = open_spot + Vector2(-2.5, 0)
			await wait(0.6)
		var st := animal_state(kind)
		await go(st["pos"] + Vector2(2.2, 0))
		await settle_camera()   # aim only once the view has stopped sliding after the jump
		var node: Node3D = main.world.animals[kind]
		await tap_at_world(node.global_position + Vector3(0, 0.9 if kind == "elephant" else 0.4, 0), kind)
		var opened := await until(func(): return hud._overlay.get_node_or_null("Animal") != null, 5.0)
		check(opened, "tapping %s opens its game card%s" % [kind, "" if opened else " (" + _tap_report(kind) + ")"])
		await frames(4)
		if kind == "sheep":
			await shot("wooly_card")
			await press(find_button(hud._overlay, "animal_game", ["sheep", 0]))
			var brain = Animals.brain
			var sheep: Dictionary = brain.animals.filter(func(a): return a["kind"] == "sheep")[0]
			check(await until(func(): return sheep["plan"] == "copy", 12.0), "Wooly comes over and waits for an emote")
			await press(tooltip_button(hud, "Dance"))
			check(await until(func(): return sheep["action"] == "dance", 3.0), "Wooly answers the dance")
		else:
			var before: int = main.world.play_fx.fountains
			await press(find_button(hud._overlay, "animal_game", ["elephant", 1]))
			var ele: Dictionary = Animals.brain.animals.filter(func(a): return a["kind"] == "elephant")[0]
			check(await until(func(): return main.world.play_fx.fountains > before, 20.0), "Tumble sprays the star fountain (plan %s, action %s, %.1f m from the child)" % [ele["plan"], ele["action"], ele["pos"].distance_to(c.pos)])
			main.rig.peek(Vector3(ele["pos"].x, 1.6, ele["pos"].y), 3.0)   # look at the fountain, not the child
			await wait(1.2)
			await shot("tumble_fountain")
			main.rig._focus_override = null   # end the framing peek before the next step
		await close_dialogs()


## F04: a paper boat by the pond sails; a leaf pile is jumped into.
func _weather_toys(hud: Control, c: Node) -> void:
	var pond: Dictionary = Session.model.items.values().filter(func(i): return i["kind"] == "pond")[0]
	var dock: Vector2 = Session.model.find_free_spot("paper_boat", "town", Vector2(pond["x"], pond["z"]) + Vector2(0, 2.6))
	await go(dock + Vector2(0, 2.0))
	var boat := await place_from_toybox("Rainy Day", "paper_boat")
	if boat == "":
		return
	if Vector2(Session.model.items[boat]["x"], Session.model.items[boat]["z"]).distance_to(Vector2(pond["x"], pond["z"])) > 3.4:
		await _result_of(Session.move(boat, dock, 0))   # put it at the water's edge (moving by drag is covered elsewhere)
	await frame_item(boat)
	await tap_item(boat)
	check(await until(func(): return main.world.play_fx.sails.has(boat), 8.0), "tapping the boat sails it")
	main.rig.peek(Vector3(pond["x"], 0.0, pond["z"]), 6.0)   # evidence framing: the pond, mid-lap
	await wait(4.0)
	var bnode: Node3D = main.world.item_nodes[boat].get_node("Boat")
	var on_water: bool = Vector2(bnode.global_position.x, bnode.global_position.z).distance_to(Vector2(pond["x"], pond["z"])) < 1.5
	check(on_water, "mid-lap the boat is out on the water")
	await shot("boat_sailing")
	main.rig._focus_override = null   # end the framing peek before the next step
	check(await until(func(): return not main.world.play_fx.sails.has(boat), 12.0), "the boat comes back to its stand")
	await go(Vector2(12, 8))
	var pile := await place_from_toybox("Rainy Day", "leaf_pile")
	if pile == "":
		return
	var before: int = main.world.play_fx.bursts
	await frame_item(pile)
	await tap_item(pile)
	check(await until(func(): return main.world.play_fx.bursts > before, 8.0), "Jump in! makes the leaves fly")


## F09: save the leaf corner as a blueprint, preview it elsewhere, turn, place, undo.
func _blueprint(hud: Control, c: Node) -> void:
	var piles: Array = Session.model.items.values().filter(func(i): return i["kind"] == "leaf_pile")
	if piles.is_empty():
		check(false, "a leaf pile to save")
		return
	await press(hud._decorate_btn)
	c.select_item(piles[0]["id"])
	await frames(4)
	check(hud._bp_save_btn.visible, "a picked thing offers Blueprint")
	await press(hud._bp_save_btn)
	check(await until(func(): return hud._overlay.get_node_or_null("BlueprintSave") != null, 3.0), "the save card opens")
	await frames(4)
	await shot("blueprint_save")
	await press(find_button(hud._overlay, "blueprint_name", "Picnic"))
	check(Blueprints.load_all().size() == 1 and Blueprints.load_all()[0]["name"] == "Picnic", "saved as Picnic on this device")
	await close_dialogs()
	await go(Vector2(-12, 14))
	await press(hud._bp_btn)
	check(await until(func(): return find_button(hud._overlay, "blueprint", 0) != null, 3.0), "Blueprints lists it")
	await press(find_button(hud._overlay, "blueprint", 0))
	check(not c.bp.is_empty() and hud._bp_tools.visible, "a preview with Turn, Place here and Cancel")
	var target: Vector2 = Session.model.find_free_spot("leaf_pile", "town", Vector2(-12, 17))
	await settle_camera()
	await tap_at_world(Vector3(target.x, 0, target.y), "ground for the blueprint")
	await frames(3)
	check(c.bp["at"].distance_to(target) < 0.6, "a ground tap moves the preview")
	var rot0: int = c.bp["rot"]
	await press(hud._bp_tools.find_child("BpTurn", true, false))
	check(c.bp["rot"] == posmod(rot0 + 2, 8), "Turn turns it a quarter")
	await shot("blueprint_preview")
	var count: int = Session.model.items.size()
	var fits: int = c.bp["errors"].count("")
	await press(hud._bp_tools.find_child("BpPlacehere", true, false))
	check(await until(func(): return Session.model.items.size() == count + fits, 5.0) and fits >= 1, "Place here puts in every piece that fits (%d)" % fits)
	check(c.bp.is_empty() and not hud._bp_tools.visible, "the preview ends")
	await press(hud._undo_btn)
	check(await until(func(): return Session.model.items.size() == count, 5.0), "Undo takes the whole blueprint away")
	await press(hud._decorate_btn)   # Done


## F06 follow-up: Suggest a trail in a town without one.
func _starter_trail(hud: Control, c: Node) -> void:
	await go(Vector2(0, 6))
	await press(hud._decorate_btn)
	check(hud._trail_btn.visible == (Session.model.trail_signs().size() < 2), "Suggest a trail shows only while there is no trail")
	if hud._trail_btn.visible:
		await press(hud._trail_btn)
		check(await until(func(): return Session.model.trail_signs().size() >= 2, 5.0), "a starter trail goes up (%d signs)" % Session.model.trail_signs().size())
		check(await until(func(): return not hud._trail_btn.visible, 3.0), "and the button goes away")
	await press(hud._decorate_btn)


## F10: invitation cards. Solo: no Invite buttons; a card can be declined or joined.
func _invitations(hud: Control, c: Node) -> void:
	hud._open_panel("fetch", {})
	await frames(4)
	check(find_button(hud._overlay, "invite", "fetch") == null, "alone in town, cards show no Invite friends")
	await close_dialogs()
	var Inv = load("res://scripts/core/invites.gd")
	var now := int(Time.get_unix_time_from_system())
	var fake := {"Pebble": "k".repeat(32), "Leaf": "l".repeat(32)}   # preset nicknames, as real friends have
	var target: Vector2 = c.pos + Vector2(6, 0)
	for nick in fake:
		var card: Dictionary = Inv.card(fake[nick], nick, "music" if nick == "Pebble" else "trail", "", "town", target, now)
		Inv.add(Session.inbox.get_or_add(Session.my_id, {}), card)
		Session.invited.emit(card)
	# A second card from Pebble replaces the first: one card per friend.
	var again: Dictionary = Inv.card(fake["Pebble"], "Pebble", "story", "", "town", target, now + 1)
	Inv.add(Session.inbox[Session.my_id], again)
	Session.invited.emit(again)
	await frames(4)
	check(hud._invites_box != null and hud._invites_box.get_children().filter(func(n): return not n.is_queued_for_deletion()).size() == 2, "one card per friend")
	await shot("invite_cards")
	var leaf_card: Node = hud._invites_box.get_children().filter(func(n): return n.get_meta("from", "") == fake["Leaf"])[0]
	await press(find_button(leaf_card, "invite_answer", "not_now"))
	var leaf_pid: String = fake["Leaf"]
	check(await until(func(): return hud._invites_box.get_children().all(func(n): return n.get_meta("from", "") != leaf_pid or n.is_queued_for_deletion()), 2.0), "Not now closes the card, nothing else happens")
	var kai_card: Node = hud._invites_box.get_children().filter(func(n): return n.get_meta("from", "") == fake["Pebble"] and not n.is_queued_for_deletion())[0]
	var from_pos: Vector2 = c.pos
	await press(find_button(kai_card, "invite_answer", "join"))
	check(await until(func(): return c.pos.distance_to(target) < from_pos.distance_to(target) - 1.0, 6.0), "Join walks over to the friend")
	check(not Session.inbox.get(Session.my_id, {}).has(fake["Pebble"]), "and the card is used up")


## F08 follow-up: take a part of a music box.
func _music_part(hud: Control, c: Node) -> void:
	var boxes: Array = Session.model.items.values().filter(func(i): return i["kind"] == "music_box")
	var mb := ""
	if boxes.is_empty():
		await go(Vector2(8, -12))
		mb = await place_from_toybox("Music Corner", "music_box")
	else:
		mb = boxes[0]["id"]
		await go(Vector2(boxes[0]["x"], boxes[0]["z"] + 1.2))
	if mb == "":
		return
	await tap_item(mb)
	check(await until(func(): return hud._overlay.get_node_or_null("Music") != null, 10.0), "the music card opens (mode %s, context %s)" % [c.mode, c._ctx.get("type", "")])
	await frames(4)
	var part := find_button(hud._overlay, "part", 1)
	if part == null:
		return
	await press(part)
	check(await until(func(): return Session.music_part_names(mb).get(1, "") == Session.nick_of(Session.my_id), 5.0), "tapping Drum takes the drum part")
	check(await until(func(): return part.get_meta("holder", "") != "", 3.0), "the row shows who plays it")
	await shot("music_part")
	await press(part)
	check(await until(func(): return not Session.music_part_names(mb).has(1), 5.0), "tapping it again lets it go")
	await close_dialogs()


func _fit_r11(loc: String, hud: Control, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	for spec in [["dress", func(): hud.open_dress_up()], ["animal", func(): hud._open_animal("elephant")],
			["blueprints", func(): hud.open_blueprints()]]:
		spec[1].call()
		await frames(4)
		var r := dialog_rect(hud)
		check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the %s card fits the safe area (%s)" % [loc, spec[0], r])
		await close_dialogs()
