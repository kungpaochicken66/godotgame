## Focused rendered check of pets, themed rooms and cooking (Mac; at most 12 shots).
## Uses the real UI and action paths: the Pets dialog, taps on the ground to walk,
## the action button (doors, stairs, Set up, Cook, Eat) and the recipe card.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/pets_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path and --no-shots after --.
## --timeout=SECONDS (default 300) ends a hung run with a failure.
extends Node

const TownModel := preload("res://scripts/core/town_model.gd")
const Cooking := preload("res://scripts/core/cooking.gd")
const PetRules := preload("res://scripts/core/pets.gd")

var main: Node
var failures := 0
var shots := ""
var tag := ""
var _n := 0


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + "[%s] %s" % [tag, what])
	if not cond:
		failures += 1


func _ready() -> void:
	shots = main.args.get("shots", ProjectSettings.globalize_path("user://shots"))
	tag = main.args.get("tag", "view")
	# --window=WxH: the device layout without a renderer (headless ignores --resolution),
	# so EC2 checks aim at the same screen geometry as the Mac's rendered run.
	if main.args.has("window"):
		var wh: PackedStringArray = str(main.args["window"]).split("x")
		if wh.size() == 2:
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(shots)
	_run.call_deferred()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func until(cond: Callable, timeout := 10.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await wait(0.1)
		t += 0.1
	return cond.call()


## --no-shots: logic only (headless smoke without a renderer).
func shot(name: String) -> void:
	if _n >= 12 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/pets_%s_%02d_%s.png" % [shots, tag, _n, name])


## A tap at a point in canvas (UI) coordinates, mapped to the window like a finger.
func tap(canvas_pos: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_final_transform() * canvas_pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen
		e.global_position = screen
		Input.parse_input_event(e)
		await get_tree().process_frame


## A real finger drag in the world (press, moves, release), e.g. a placement ghost.
## Both ends must be reachable like a tap; the finger follows the target each step,
## because the camera follows a dragged ghost.
func drag_world(from: Vector3, to: Vector3, what: String) -> void:
	var cam: Camera3D = main.rig.camera
	var area := playable_rect()
	var start := cam.unproject_position(from)
	var ok_from := area.has_point(start) and ui_blocker_at(start) == ""
	check(ok_from, "the drag of %s starts on screen and not under the HUD (aim %s)" % [what, start.round()])
	if not ok_from:
		return
	var xf := get_viewport().get_final_transform()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = xf * start
	down.global_position = down.position
	Input.parse_input_event(down)
	await get_tree().process_frame
	var p := start
	for i in range(1, 13):
		var goal := cam.unproject_position(to)
		if not (area.has_point(goal) and ui_blocker_at(goal) == ""):
			check(false, "the drag of %s ends on screen and not under the HUD (aim %s)" % [what, goal.round()])
			break
		var next := p.lerp(goal, 1.0 / (13 - i))
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = xf * next
		mv.global_position = mv.position
		mv.relative = (next - p) * xf.get_scale()
		Input.parse_input_event(mv)
		p = next
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = xf * p
	up.global_position = up.position
	Input.parse_input_event(up)
	await get_tree().process_frame


func press(b: Control) -> void:
	if b == null:
		check(false, "a button to press is missing")
		return
	await tap(b.get_global_rect().get_center())
	await frames(3)


func find_button(root: Node, key: String, value) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.has_meta(key) and b.get_meta(key) == value and b.is_visible_in_tree():
			return b
	return null


func named(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button


func dialog_rect(hud: Control) -> Rect2:
	for p in hud._overlay.find_children("*", "PanelContainer", true, false):
		return (p as Control).get_global_rect()
	return Rect2()


## Walks with a real tap on the ground at a world point.
func walk_to(p: Vector2) -> void:
	await settle_camera()
	await tap_at_world(Vector3(p.x, 0, p.y), "ground")


## Uses the action button once it offers `type` (it appears when the child is close).
func use_context(type: String, timeout := 8.0) -> bool:
	var c: Node = main.controller
	if not await until(func(): return c._ctx.get("type", "") == type and main.hud._context_btn.visible, timeout):
		return false
	await press(main.hud._context_btn)
	return true


## Arrives in a room through its door or stairs, then walks to a free spot away
## from the stairs (and from resting pets, whose card a tap would open) so the
## room's own action (Set up) is offered.
func enter_room(space: String, spot: Vector2) -> void:
	main.controller.go_to_room(space)
	await wait(1.0)
	check(main.hud._overlay.get_child_count() == 0, "no dialog is open when walking in")
	var from: Vector2 = main.controller.pos
	await walk_to(spot)
	await wait(2.5)
	check(main.controller.pos.distance_to(from) > 1.0 and main.hud._overlay.get_child_count() == 0, "walked into the room")


## Taps an item where it is on screen (play mode: walk over and use it).
func tap_item(id: String) -> void:
	await settle_camera()
	var node: Node3D = main.world.item_nodes.get(id)
	if node == null:
		check(false, "item %s is on screen" % id)
		return
	await tap_at_world(node.global_position + Vector3(0, 0.4, 0), "item %s" % id)


## The camera eases after the child or the view jumps (camera_rig.gd, 4/s). A
## finger taps what is on screen; a driver must not aim while the view is still
## sliding, or the point drifts off the target before the tap is handled (r11b
## Mac play3: 160 px at 60 fps right after a jump). Waits until the camera has
## been still for 5 frames (bounded); returns the seconds waited.
func settle_camera(timeout := 4.0) -> float:
	# A framing peek (rig.peek) pins the camera; a still camera is only "settled" on
	# the child once no peek holds it (r11d: a pinned camera looked still).
	main.rig._focus_override = null
	var cam: Camera3D = main.rig.camera
	var last := cam.global_position
	var still := 0
	var t := 0.0
	while still < 5 and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		still = still + 1 if cam.global_position.distance_to(last) < 0.002 else 0
		last = cam.global_position
	if still < 5:
		print("DIAG camera still moving after %.1f s" % t)
	return t


## Where a finger can tap the world: the visible view inside the HUD's safe area.
func playable_rect() -> Rect2:
	return main.hud.get_global_rect().intersection(get_viewport().get_visible_rect()).grow(-8.0)


## The HUD control (if any) that would take a tap at this point instead of the world.
func ui_blocker_at(p: Vector2) -> String:
	for c in main.hud.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.is_visible_in_tree() \
				and ctl.size.x > 0.0 and ctl.get_global_rect().has_point(p):
			return str(ctl.name)
	return ""


## A real tap on a world point, logging how far it drifted while being handled.
## Only a tap a finger could make is sent: the point must be on screen, inside the
## safe area and not under a HUD control (r11c Mac: a boat tap aimed at 2096, 1437
## on a 2208 x 1024 screen had passed). Otherwise the check fails and nothing is sent.
func tap_at_world(point: Vector3, what: String) -> void:
	var cam: Camera3D = main.rig.camera
	var aim := cam.unproject_position(point)
	var area := playable_rect()
	var blocker := ui_blocker_at(aim)
	var reachable := not cam.is_position_behind(point) and area.has_point(aim) and blocker == ""
	check(reachable, "the tap on %s is on screen, in the safe area and not under the HUD (aim %s, area %s%s)" \
		% [what, aim.round(), area, (", under " + blocker) if blocker != "" else ""])
	if not reachable:
		return
	await tap(aim)
	print("DIAG tap %s: aimed %s, drift while handled %.1f px" % [what, aim.round(), cam.unproject_position(point).distance_to(aim)])


## Closes dialogs the way the game does (queue_free) and waits until they are
## really gone: a full-screen shade still in the tree for that frame would
## swallow the next tap. Bounded; fails if a dialog stays.
func close_dialogs() -> void:
	main.hud._close_overlay()
	check(await until(func(): return main.hud._overlay.get_child_count() == 0, 2.0), "dialogs closed")
	await frames(2)


func my_pet_node() -> Node3D:
	var e: Dictionary = PetRules.entry(Session.model, Session.my_pid)
	return main.world.pet_layer.pets.get(Session.my_pid + "/" + e.get("active", ""))


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	# Watchdog: a hang anywhere ends the run with a failure instead of stalling.
	get_tree().create_timer(float(main.args.get("timeout", "300"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "300"))
		print("PETS %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	# Thumbnails need a renderer; the logic-only mode does not use them.
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://pets_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	await _adopt_all(hud)
	await _follow_and_stairs(hud, c)
	await _rest_at_home(hud, c)
	await _kitchen(hud, c)
	await _game_room(hud, c)
	for loc in locales:
		await _dialogs_in(loc, hud, c, area)
	print("PETS %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## Adopt one pet of every family through the Pets dialog.
func _adopt_all(hud: Control) -> void:
	for fam in PetRules.ORDER:
		await press(hud._pets_btn)
		check(hud._overlay.get_node_or_null("Pets") != null or dialog_rect(hud).size != Vector2.ZERO, "the Pets dialog opens")
		await frames(4)
		await press(find_button(hud._overlay, "family", fam))
		await press(find_button(hud._overlay, "color", 1 if fam in ["cat", "dog"] else 0))
		var before: int = PetRules.entry(Session.model, Session.my_pid)["pets"].size()
		if fam == "cat":
			await shot("adopt_dialog")
		await press(named(hud._overlay, "AdoptButton"))
		check(await until(func(): return PetRules.entry(Session.model, Session.my_pid)["pets"].size() == before + 1), "adopted a %s" % fam)
		var node := my_pet_node()
		check(node != null and node.family == fam and node.model_loaded, "the new %s follows and shows its model (%s)" % [fam, node.model_id if node else "-"])
		await close_dialogs()
		await frames(3)


## The active pet trots behind the child, animating, through the door and up the stairs.
func _follow_and_stairs(hud: Control, c: Node) -> void:
	for fam in PetRules.ORDER:
		var e: Dictionary = PetRules.entry(Session.model, Session.my_pid)
		var pet: Dictionary = e["pets"].filter(func(p): return p["family"] == fam)[0]
		if not (e["active"] == pet["id"] and e["mode"] == "follow"):
			await press(hud._pets_btn)
			await press(find_button(hud._overlay, "pet_id", pet["id"]))   # Follow me
			await close_dialogs()
		await until(func(): return PetRules.entry(Session.model, Session.my_pid)["active"] == pet["id"])
		await wait(0.5)
		var node := my_pet_node()
		var start: Vector3 = node.global_position if node else Vector3.ZERO
		var j0 := {}
		if node:
			for h in node.joints():
				j0[h] = node._joints[h].rotation
		await walk_to(c.pos + Vector2(3.0, 1.0))
		await wait(0.9)
		var moved := false
		if node:
			for h in node.joints():
				if node._joints[h].rotation.distance_to(j0[h]) > 0.02:
					moved = true
		check(node != null and node.global_position.distance_to(start) > 0.4 and moved, "the %s moves after the child and its joints animate" % fam)
		await wait(1.5)
		check(node != null and Vector2(node.global_position.x, node.global_position.z).distance_to(c.pos) < 2.5, "the %s keeps close" % fam)
		if fam == "dog":
			await shot("dog_follows")
	# Through the door and upstairs with the butterfly following.
	c.walk_to_door()
	check(await use_context("enter", 15.0), "the door offers Go inside")
	await wait(1.0)
	check(c.space != "town" and await until(func(): return my_pet_node() != null and my_pet_node().visible, 5.0), "the pet comes into the house")
	var stairs: Array = c.portal_contexts().filter(func(p): return p.get("label", "") == "Go upstairs")
	check(not stairs.is_empty(), "the living room has stairs up")
	if not stairs.is_empty():
		await walk_to(stairs[0]["at"])
		check(await use_context(stairs[0]["type"], 10.0), "the stairs offer Go upstairs")
		await wait(1.0)
		check(TownModel.parse_room(c.space).get("floor", 0) == 1, "upstairs")
		check(await until(func(): var n := my_pet_node(); return n != null and n.visible and Vector2(n.global_position.x, n.global_position.z).distance_to(c.pos) < 3.0, 5.0), "the pet followed up the stairs")
		await shot("followed_upstairs")


## Send the pets home: they rest by the Pet room furniture.
func _rest_at_home(hud: Control, c: Node) -> void:
	var e: Dictionary = PetRules.entry(Session.model, Session.my_pid)
	await press(hud._pets_btn)
	await press(find_button(hud._overlay, "pet_id", e["active"]))   # Rest at home
	await close_dialogs()
	check(await until(func(): return PetRules.entry(Session.model, Session.my_pid)["mode"] == "home"), "Rest at home sends the pets home")
	var pet_room := PetRules.pet_room(Session.model, Session.my_pid)
	await enter_room(pet_room, Vector2(2.8, 0.2))
	check(await use_context("setup", 6.0), "the Pet room offers Set up the pet room")
	check(await until(func(): return Session.model.items_in(pet_room).any(func(i): return i["kind"] == "petroom_cat_tree"), 5.0), "the Pet room is set up")
	await wait(2.0)
	var layer: Node = main.world.pet_layer
	check(layer.pets.size() == 4 and layer.pets.values().all(func(n): return int(n.get_meta("follow_peer", 0)) == 0), "all four pets rest in the Pet room")
	var cat_tree: Node3D = null
	for id in main.world.item_nodes:
		if main.world.item_nodes[id].get_meta("item")["kind"] == "petroom_cat_tree":
			cat_tree = main.world.item_nodes[id]
	var cat: Node3D = layer.pets.values().filter(func(n): return n.family == "cat")[0]
	check(cat_tree != null and cat.global_position.distance_to(cat_tree.global_position) < 1.6, "the cat rests on the cat tree")
	await shot("pets_resting")


## Kitchen: Set up, then cook, serve and eat all four recipes.
func _kitchen(hud: Control, c: Node) -> void:
	var home := TownModel.house_of(c.space)
	var kitchen := TownModel.room_space(home, 0, 1)
	await enter_room(kitchen, Vector2(-1.2, 1.4))
	check(await use_context("setup", 6.0), "the kitchen offers Set up the kitchen")
	check(await until(func(): return Session.model.items_in(kitchen).any(func(i): return i["kind"] == "kitchen_stove"), 5.0), "the kitchen has a stove")
	await wait(0.6)
	var stove: Dictionary = Session.model.items_in(kitchen).filter(func(i): return i["kind"] == "kitchen_stove")[0]
	check(Session.model.items_in(kitchen).any(func(i): return i["kind"] == "kitchen_pot" and i.has("host")), "the pot starts on the counter")
	for recipe in Cooking.ORDER:
		# Tapping the stove walks over and opens the recipe card.
		await tap_item(stove["id"])
		var held := [null]   # lambdas capture by value: the button comes back in an array
		var found := await until(func():
			held[0] = find_button(main.hud._overlay, "recipe", recipe)
			return held[0] != null, 10.0)
		await frames(4)   # let the centered card finish its layout before a finger taps it
		var cook: Button = held[0]
		check(found and not cook.disabled, "tapping the stove opens the recipe card with %s ready" % recipe)
		if not found:
			await close_dialogs()
			continue
		if recipe == "rice":
			await shot("recipe_card")
		var dish_kind: String = Cooking.RECIPES[recipe]["dish"]
		await press(cook)
		check(await until(func(): return Session.model.items_in(kitchen).any(func(i): return i["kind"] == dish_kind), 8.0), "%s is served (last message: %s)" % [dish_kind, main.hud._toast_label.text])
		var dishes: Array = Session.model.items_in(kitchen).filter(func(i): return i["kind"] == dish_kind)
		if dishes.is_empty():
			continue
		if recipe == "rice":
			await shot("dish_served")
		# Tapping the dish walks over and eats it.
		await tap_item(dishes[0]["id"])
		check(await until(func(): return not Session.model.items.has(dishes[0]["id"]), 10.0), "ate the %s" % dish_kind)
	check(int(Session.model.cooked.get(Session.my_pid, 0)) == 4, "four dishes cooked")


## Game room: Set up brings the TV, console, handheld and bean bag.
func _game_room(hud: Control, c: Node) -> void:
	var game := TownModel.room_space(TownModel.house_of(c.space), 1, 1)
	await enter_room(game, Vector2(-1.6, 1.3))
	check(await use_context("setup", 6.0), "the game room offers Set up the game room")
	var kinds := func(): return Session.model.items_in(game).map(func(i): return i["kind"])
	check(await until(func(): return kinds.call().has("game_tv_stand") and kinds.call().has("game_console_set") and kinds.call().has("game_handheld_dock") and kinds.call().has("game_bean_bag"), 5.0), "the game room has TV, console, handheld and bean bag")
	await wait(0.8)
	await shot("game_room")


## The Pets dialog and the recipe card fit the safe area in this language.
func _dialogs_in(loc: String, hud: Control, c: Node, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	await press(hud._pets_btn)
	var r := dialog_rect(hud)
	check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the Pets dialog fits the safe area" % loc)
	await shot("%s_pets_dialog" % loc)
	await close_dialogs()
	var kitchen := TownModel.room_space(TownModel.house_of(c.space), 0, 1)
	if c.space != kitchen:
		c.go_to_room(kitchen)
		await wait(1.0)
	var stove: Dictionary = Session.model.items_in(kitchen).filter(func(i): return i["kind"] == "kitchen_stove")[0]
	await tap_item(stove["id"])
	check(await until(func(): return find_button(hud._overlay, "recipe", "rice") != null, 10.0), "[%s] tapping the stove opens the recipe card" % loc)
	r = dialog_rect(hud)
	check(r.size != Vector2.ZERO and area.grow(0.5).encloses(r), "[%s] the recipe card fits the safe area" % loc)
	await shot("%s_recipe_card" % loc)
	await close_dialogs()
	await frames(3)
