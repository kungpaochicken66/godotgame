## Town evenings and more through the real UI (design/town-evenings-and-more.md): the lamplighter
## walk and the evening moment, a signal rail setting a pinwheel off as the cart passes, a weather
## bell rung by the weather vane and pinwheels turning in autumn, the picture board's card, a hello
## left for friends, answered and taken away, and an animal riding in the cart's trailer.
## Touch (default) and controller (--tv), as in puzzle_ride_tour.gd, whose helpers this reuses;
## the outside-pointer guard stays on in controller mode.
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/town_play_tour.gd \
##                   --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/town_play_tour.gd \
##                   --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv --locales=en,zh-CN,ja,es,fr,de
## Logic only, no renderer (EC2): add --headless before --path, and --no-shots --window=WxH after --.
## Its town is its own save (user://town_play_tour_town.json), deleted at the start of every run.
## At most 30 screenshots (ten cases and three per language).
extends "res://tests/puzzle_ride_tour.gd"

const Lamplight := preload("res://scripts/core/lamplight.gd")
const PictureBoard := preload("res://scripts/core/picture_board.gd")
const Echoes := preload("res://scripts/core/echoes.gd")
const Avatar := preload("res://scripts/core/avatar.gd")

const PLAY_TOWN := "user://town_play_tour_town.json"

var lamp := ""
var lamp_at := Vector2.ZERO
var board := ""
var board_at := Vector2.ZERO
var bell_at := Vector2.ZERO


func shot(name: String) -> void:
	if _n >= 30 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/town_play_%s_%02d_%s.png" % [shots, tag, _n, name])


## The average color of a small patch of the picture around a world point (rendered runs only).
func patch_color(img: Image, world_point: Vector3) -> Color:
	var cam: Camera3D = main.rig.camera
	var px: Vector2 = get_viewport().get_final_transform() * cam.unproject_position(world_point)
	var sum := Vector3.ZERO
	var n := 0
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var x := int(px.x) + dx
			var y := int(px.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var c := img.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	return Color(sum.x / maxf(n, 1), sum.y / maxf(n, 1), sum.z / maxf(n, 1))


static func color_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## From the picture on screen: the hello's figure must not look like the child standing next to it,
## and the ground must show through it. Runs only when a renderer draws (never headless), so a
## headless pass says nothing about this; the numbers are printed for whoever reads the log.
func figure_looks_different(fig: Node3D, live: Node3D) -> void:
	if main.args.has("no-shots"):
		print("DIAG [%s] no renderer: the figure's look was NOT checked in this run" % tag)
		return
	# The child steps aside so both are on screen side by side, facing the same way.
	await stand_at(Vector2(fig.position.x + 1.3, fig.position.z + 0.2))
	live.rotation.y = fig.rotation.y
	await settle_camera()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var torso := Vector3(0, 0.62, 0)
	var hair := Vector3(0, 1.22, 0)
	var f_torso := patch_color(img, fig.global_position + torso)
	var k_torso := patch_color(img, live.global_position + torso)
	var f_hair := patch_color(img, fig.global_position + hair)
	var k_hair := patch_color(img, live.global_position + hair)
	var ground := patch_color(img, Vector3((fig.global_position.x + live.global_position.x) * 0.5, 0.0, fig.global_position.z + 1.6))
	print("DIAG [%s] picture colors: figure torso %s hair %s; child torso %s hair %s; ground %s" % [tag, f_torso.to_html(false), f_hair.to_html(false), k_torso.to_html(false), k_hair.to_html(false), ground.to_html(false)])
	check(color_gap(f_torso, k_torso) > 0.12 or color_gap(f_hair, k_hair) > 0.12, "in the picture the figure is not colored like the child beside it (torso apart by %.2f, hair by %.2f)" % [color_gap(f_torso, k_torso), color_gap(f_hair, k_hair)])
	check(color_gap(f_hair, k_hair) > 0.12, "its hair is not the child's dark hair: the whole figure is one pale color (%.2f apart)" % color_gap(f_hair, k_hair))
	# Whether the ground shows through. The first form of this check compared how far the figure's torso
	# and the child's torso are from the ground's color. That does not isolate transparency: the child
	# wears other colors, and in five of the Mac's six rendered runs of first-steps r1 the child's own
	# torso patch happened to be nearer the ground's color (0.16 to 0.31) than the pale figure was (0.30
	# to 0.35), so it failed while the pictures showed a see-through figure. The comparison is still
	# printed; the judgement is now a controlled one, on the figure alone, at one place in the picture:
	# the ground alone (figure hidden), the figure as the game draws it, and the figure made opaque by
	# this test. If the renderer blends the material, the middle color lies between the other two,
	# clearly away from both.
	print("DIAG [%s] old comparison, not judged: figure torso %.2f from the ground's color, child torso %.2f" % [tag, color_gap(f_torso, ground), color_gap(k_torso, ground)])
	var at: Vector3 = fig.global_position + torso
	var mats := []
	for m in fig.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
		if mat and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and not mats.has(mat) and not m.name.begins_with("HelloRing"):
			mats.append(mat)
	var alphas: Array = mats.map(func(m): return m.albedo_color.a)
	# The figure must stand still for the three pictures (it plays its emotes when a child comes near,
	# and a dancing figure would be measured at three different poses), and only its own see-through
	# parts are hidden for the first picture: the ring under it stays, so the ground behind the torso
	# is the same in all three. (Both points are from an independent audit of this check, 2026-11-14.)
	var entry := {}
	for f in main.world.echo_fx.figures.values():
		if f["node"] == fig:
			entry = f
	var still: bool = await until(func(): return fig._emote_t <= 0.0 and entry.get("queue", []).is_empty(), 15.0)
	if not entry.is_empty():
		entry["rest"] = 120.0   # it does not start again during the measurement
	check(still, "set up: the figure has finished its emotes and stands still for the measurement")
	var veil: Array = fig.find_children("*", "MeshInstance3D", true, false).filter(func(m): return mats.has((m as MeshInstance3D).material_override))
	for m in veil:
		m.visible = false
	var bare := await _drawn_color(at)
	for m in veil:
		m.visible = true
	for m in mats:
		m.albedo_color.a = 1.0
	var solid := await _drawn_color(at)
	for k in mats.size():
		mats[k].albedo_color.a = alphas[k]
	var seen := await _drawn_color(at)
	var span := Vector3(solid.r - bare.r, solid.g - bare.g, solid.b - bare.b)
	var part := Vector3(seen.r - bare.r, seen.g - bare.g, seen.b - bare.b)
	var share: float = part.dot(span) / maxf(span.length_squared(), 0.000001)
	print("DIAG [%s] controlled colors at the figure's torso: ground alone %s, figure as drawn %s, figure made opaque %s; share of the opaque color %.2f; %d material(s), alpha %s" % [tag, bare.to_html(false), seen.to_html(false), solid.to_html(false), share, mats.size(), str(alphas)])
	check(not mats.is_empty() and color_gap(solid, bare) > 0.15, "set up: made opaque, the figure's torso is clearly not the ground's color (%.2f apart)" % color_gap(solid, bare))
	check(color_gap(seen, bare) > 0.05, "the figure is drawn: its torso is not the bare ground (%.2f apart)" % color_gap(seen, bare))
	check(color_gap(seen, solid) > 0.05, "the figure is not opaque: its torso differs from the same torso made opaque (%.2f apart)" % color_gap(seen, solid))
	check(share > 0.15 and share < 0.92, "the ground shows through the figure: its color is a mix of the ground and the opaque figure (%.2f of the way)" % share)


## The picture's color at a place in the world, after the next frame has been drawn.
func _drawn_color(world_point: Vector3) -> Color:
	await frames(2)
	await RenderingServer.frame_post_draw
	return patch_color(get_viewport().get_texture().get_image(), world_point)


func free_ground(kinds: Array, far_from: Array, reach := 6.0) -> Vector2:
	for z in range(9, 18):
		for x in range(-16, 10):
			var b := Vector2(x, z)
			if kinds.all(func(e): return Session.model.check(e[0], "town", b.x + e[1].x, b.y + e[1].y, 0) == "") and far_from.all(func(p): return p.distance_to(b) > reach) \
					and Session.model.items_in("town").all(func(i): return Vector2(i["x"], i["z"]).distance_to(b) > 4.0 or not Contraptions.takes_part(i["kind"])):
				return b
	return Vector2(99, 99)


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "600"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "600"))
		print("TOWN_PLAY %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("TOWN_PLAY start tag=%s input=%s engine=%s renderer=%s protocol=%d" % [tag, "controller" if tv else "touch",
		Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method(), Session.PROTOCOL])
	hud._context_btn.pressed.connect(func(): _ctx_presses += 1)
	hud._context_alt_btn.pressed.connect(func(): _alt_presses += 1)
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	for f in [PLAY_TOWN, PLAY_TOWN + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var reduce_before: bool = DecoMotion.load_reduce()
	Session.start_solo(PLAY_TOWN, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	main.world.set_reduce_motion(false)
	Activities._wish_wait = -1.0e6   # test isolation, as in puzzle_ride_tour.gd (its own case covers a wish arriving)
	park_animals()
	if tv:
		# The controller layer applies its button layout when a controller is first used. The other tours
		# begin with the pointer; this one begins with the action button, so the pointer is nudged first.
		await stick(false, Vector2(0.5, 0.0), 0.3)
		await frames(6)
		check(pad.shown, "the controller layer is awake before the first action")
	await _lamps(hud, c)
	case_ended("lamplighter walk")
	await _signal(hud, c)
	case_ended("signal rail")
	await _weather(hud, c)
	case_ended("weather toys")
	await _board(hud, c)
	case_ended("picture board")
	await _echo(hud, c)
	case_ended("friend echoes")
	await _passenger(hud, c)
	case_ended("animal passenger")
	for loc in locales:
		await _texts_of(loc, hud, c)
		case_ended("[%s] town play texts" % loc)
	main.world.set_reduce_motion(reduce_before)
	I18n.set_locale(locales[0])
	if tv:
		check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the controller tour (%d; first: %s)" % [_real_mouse, _real_mouse_first])
	print("TOWN_PLAY %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


## Light a lamp by hand; then every lamp lit and the evening bell: the fireflies gather.
func _lamps(hud: Control, c: Node) -> void:
	var spot = Session.model.find_free_spot("lamp_post", "town", Vector2(-10, 13))
	lamp = await put_as("lamp_post", spot)
	lamp_at = item_at(lamp)
	await stand_at(lamp_at + Vector2(0.0, 1.0))
	check(await do_context("lamp"), "next to a lamp post the action is Light the lamp")
	check(await until(func(): return Session.model.items[lamp].get("on", false), 3.0), "the lamp is lit by hand")
	check(await until(func(): return hud._context_btn.text == "Put out the lamp", 2.0), "the action becomes Put out the lamp (%s)" % hud._context_btn.text)
	await frames(4)
	check(main.world.item_nodes[lamp].get_node_or_null("LampHalo") != null and lamp_energy(lamp) > 1.5, "it shines by day, with its halo")
	await settle_camera()
	await shot("lamp_lit_by_hand")
	check(await do_context("lamp"), "Put out the lamp")
	check(await until(func(): return not Session.model.items[lamp].get("on", false), 3.0), "the lamp is out again")
	# Set up: every lamp post lit (the same request from next to each); then the bell.
	for id in Lamplight.posts(Session.model):
		await stand_at(item_at(id) + Vector2(0.0, 1.0))
		var r: Dictionary = await ask_result(Session.toggle_lamp(id))
		check(r.get("ok", false) and r.get("on", false), "set up: lamp %s lit" % id)
	check(Lamplight.all_lit(Session.model) and main.world.lamplight_drawn == 0, "every lamp post is lit; by day nothing gathers")
	await stand_at(lamp_at + Vector2(0.0, 2.2))
	check((await ask_result(Session.ring_bell())).get("ok", false) and Session.model.evening, "the evening bell rings")
	check(await until(func(): return main.world.lamplight_drawn == 1, 3.0), "the fireflies gather, once")
	check(hud._toast_label.text == "Every lamp is lit. The fireflies have come!", "everyone reads it (%s)" % hud._toast_label.text)
	await frames(6)
	check(main.world.item_nodes[lamp].get_node_or_null("LamplightFireflies") != null, "fireflies rise around the lamp")
	await wait(1.0)
	await shot("lamplight_evening")
	check((await ask_result(Session.ring_bell())).get("ok", false) and not Session.model.evening, "set up: morning again")
	await wait(0.5)
	_case_ok = true


## A ring with a signal rail and a pinwheel beside it: riding past sets the pinwheel off.
func _signal(hud: Control, c: Node) -> void:
	var found := false
	for cz in range(1, 9):
		for cx in range(-11, 8):
			var pieces := ring_pieces(cx, cz, 4, 2)
			var mid := Vector2(cx * 2.0 + 3.0, cz * 2.0 + 1.0)
			if not found and mid.distance_to(lamp_at) > 9.0 and pieces.all(func(p): return Session.model.check(p[0], "town", p[1].x * 2.0, p[1].y * 2.0, p[2]) == "") \
					and RideRules._solids(Session.model).all(func(s): return s[0].distance_to(mid) > 5.8 + s[1]) \
					and Session.model.items_in("town").all(func(i): return not Contraptions.takes_part(i["kind"]) or Vector2(i["x"], i["z"]).distance_to(mid) > 7.5):
				ring = pieces
				found = true
	check(found, "free ground for a ring of rails")
	ring[1][0] = RideRules.SIGNAL   # the straight rail right after the station
	rails.clear()
	for p in ring:
		rails.append(await put_as(p[0], Vector2(p[1]) * 2.0, p[2]))
	station = rails[0]
	station_at = Vector2(ring[0][1]) * 2.0
	var sig_at := Vector2(ring[1][1]) * 2.0
	var wheel := await put_as("pinwheel", sig_at + Vector2(0.0, -1.6))   # outside the ring, clear of the rails
	park_animals()
	check(RideRules.route(Session.model, station)["end"] == "loop" and Contraptions.linked(Session.model, rails[1]) == [wheel],
		"a circuit with a signal rail, and a pinwheel linked to it (%s, %s)" % [RideRules.route(Session.model, station)["end"], str(Contraptions.linked(Session.model, rails[1]))])
	await stand_at(station_at + Vector2(0.0, 1.7))
	await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 2.0), "Decorate")
	await frames(4)
	check(main.world.contraptions.link_pairs.has([rails[1], wheel]), "Decorate shows the link from the signal rail to the pinwheel")
	await settle_camera()
	await shot("signal_rail_link")
	await leave_decorate()
	check(await until(func(): return c.mode == "play", 2.0), "Done")
	var spins: int = int(main.world.contraptions.effects.get("spin", 0))
	check(await do_context("ride_board"), "Get in the cart")
	check(await until(func(): return Session.ride_of(Session.my_id) == station, 3.0), "in the cart")
	check(await do_context("ride_go"), "Go!")
	check(await until(func(): return int(main.world.contraptions.effects.get("spin", 0)) == spins + 1, 6.0), "riding over the signal rail spins the pinwheel beside it")
	check(Session.ride_distance(station) > 1.9, "after the cart passed the rail's middle (%.1f m along)" % Session.ride_distance(station))
	await shot("signal_rail_passed")
	await get_off()
	check(Session.ride_of(Session.my_id) == "", "out of the cart")
	_case_ok = true


## A weather bell rung by the weather vane; pinwheels turn in autumn.
func _weather(hud: Control, c: Node) -> void:
	bell_at = free_ground([["weather_bell", Vector2.ZERO], ["pinwheel", Vector2(1.5, 0)]], [lamp_at, station_at], 8.0)
	check(bell_at.x != 99, "free ground for a weather bell")
	var bell := await put_as("weather_bell", bell_at)
	var wheel := await put_as("pinwheel", bell_at + Vector2(1.5, 0))
	park_animals()
	await stand_at(bell_at + Vector2(0.7, 2.0))
	await calm()
	var presses: int = main.world.contraptions.presses
	var spins: int = int(main.world.contraptions.effects.get("spin", 0))
	var before: String = Session.model.weather
	c._use_landmark("vane")   # what the weather vane's own action button does
	check(await until(func(): return Session.model.weather != before, 3.0), "the weather changes (%s)" % Session.model.weather)
	check(await until(func(): return main.world.contraptions.presses == presses + 1, 2.0), "the weather bell rings on screen")
	check(await until(func(): return int(main.world.contraptions.effects.get("spin", 0)) == spins + 1, 3.0), "and the pinwheel beside it answers")
	check(hud._toast_label.text == "The weather bells are ringing!", "the child who changed the weather reads why (%s)" % hud._toast_label.text)
	await shot("weather_bell_rung")
	# Round to autumn: every pinwheel outdoors turns by itself.
	for i in 4:
		if Session.model.weather != "autumn":
			await wait(1.3)
			await ask_result(Session.change_weather())
	check(Session.model.weather == "autumn", "set up: autumn")
	var w: Node3D = main.world.item_nodes[wheel].get_node("Wheel")
	await wait(1.5)   # the spin from the last ring is over or slowing
	var a0: float = w.rotation.z
	await wait(0.6)
	check(main.world.contraptions.windy and absf(w.rotation.z - a0) > 0.5, "in autumn the pinwheel turns by itself (%.1f rad in 0.6 s)" % absf(w.rotation.z - a0))
	main.world.set_reduce_motion(true)
	await frames(3)
	check(not main.world.contraptions.windy, "not with Reduce motion on")
	main.world.set_reduce_motion(false)
	_case_ok = true


## The picture board's card: pick a color, paint three squares, rub one out.
func _board(hud: Control, c: Node) -> void:
	board_at = free_ground([["picture_board", Vector2.ZERO]], [lamp_at, station_at, bell_at], 5.0)
	check(board_at.x != 99, "free ground for a picture board")
	board = await put_as("picture_board", board_at)
	park_animals()
	await stand_at(board_at + Vector2(0.0, 1.3))
	await calm()
	check(await do_context("board"), "next to a picture board the action is Paint a picture")
	check(await until(func(): return dialog("Board") != null, 2.0), "its card opens")
	var card := dialog("Board")
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	if card:
		await frames(3)
		var panel: Control = card.find_children("*", "PanelContainer", true, false)[0]
		check(area.grow(1.0).encloses(panel.get_global_rect()), "the card fits the screen (%s in %s)" % [panel.get_global_rect(), area])
		var colors: Array = card.find_child("Colors", true, false).get_children()
		var cells: Array = card.find_child("Grid", true, false).get_children()
		check(colors.size() == 9 and cells.size() == 64, "eight colors and a rubber, and 64 squares (%d, %d)" % [colors.size(), cells.size()])
		check(cells.all(func(b): return b.size.x >= 44.0 and b.size.y >= 44.0), "every square is a 44 px target or larger")
		await act(colors[3], "the fourth color")
		for i in [9, 10, 18]:
			await act(cells[i], "square %d" % i)
		check(await until(func(): return [9, 10, 18].all(func(i): return PictureBoard.cell(Session.model.items[board]["pix"], i) == 4), 3.0), "three squares are painted in that color")
		await frames(3)
		check([9, 10, 18].all(func(i): return cells[i].get_meta("color") == 4) and cells[0].get_meta("color") == 0, "the card shows them")
		await act(colors[8], "the rubber")
		await act(cells[10], "square 10")
		check(await until(func(): return PictureBoard.cell(Session.model.items[board]["pix"], 10) == 0, 3.0), "the rubber clears a square")
		# A friend's square arrives while the card is open.
		Session.model.set_pixel(board, 63, 2)
		Session.ev_item.rpc(Session.model.items[board].duplicate(true))
		await frames(4)
		check(cells[63].get_meta("color") == 2, "a friend's square appears while the card is open")
		if tv:
			await hints_ok("the picture board's card")
		await shot("board_card")
		await act(button_text(card, "Close"), "Close")
	check(await until(func(): return dialog("Board") == null, 2.0), "Close closes the card")
	await frames(6)
	check(main.world.item_nodes[board].get_node("Face/Cells").get_child_count() > 0, "the board in the world shows the picture")
	await settle_camera()
	await shot("board_in_town")
	_case_ok = true


## Leave a hello, see it play, read an answer, take it away.
func _echo(hud: Control, c: Node) -> void:
	var pid: String = Session.my_pid
	var at := board_at + Vector2(3.0, 2.0)
	await stand_at(at)
	await calm()
	check(hud._echo_btn.is_visible_in_tree() and hud._echo_btn.text == "Hello", "the menu column has Hello")
	await act(hud._echo_btn, "Hello")
	check(await until(func(): return dialog("EchoRecorder") != null, 2.0), "Leave a hello opens")
	for e in ["wave", "dance", "heart"]:
		var rec := dialog("EchoRecorder")
		var b: Button = find_button(rec, "emote", e) if rec else null
		check(b != null, "the %s emote is offered" % e)
		if b:
			await act(b, "the %s emote" % e)
		await frames(4)
	var rec := dialog("EchoRecorder")
	check(rec != null and rec.find_child("Picked", true, false) != null and rec.find_child("Picked", true, false).get_child_count() == 3, "three emotes are picked and shown")
	if tv and rec:
		await hints_ok("Leave a hello")
	await shot("hello_recorder")
	await act(button_text(rec, "Leave it here"), "Leave it here")
	check(await until(func(): return Session.model.echoes.has(pid), 3.0), "the hello is left")
	check(Session.model.echoes[pid]["emotes"] == ["wave", "dance", "heart"] and Vector2(Session.model.echoes[pid]["x"], Session.model.echoes[pid]["z"]).distance_to(at) < 0.1, "three emotes, where the child stood")
	await frames(4)
	var fx: Node3D = main.world.echo_fx
	check(fx.figures.has(pid), "a figure stands there")
	var fig: Node3D = fx.figures[pid]["node"]
	# Mac review of town-play r1: the figure was an exact, opaque double of the child with the same name
	# tag. The earlier check here asserted a property the OpenGL renderer does not draw, and passed.
	# These three do not depend on the renderer: one see-through material on every part, another tag,
	# a ring on the ground. Whether it LOOKS different is checked below from the picture itself, and
	# only when a renderer is drawing.
	var parts: Array = fig.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.name != "HelloRing")
	check(parts.size() >= 3 and parts.all(func(m): return m.material_override is StandardMaterial3D and m.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.material_override.albedo_color.a <= 0.6),
		"every part of the figure is drawn with one see-through material (%d parts)" % parts.size())
	var live: Node3D = main.world.local_kid()
	check(fig._label.text == tr("A hello from %s") % tr(Session.nick_of(Session.my_id)) and fig._label.text != live._label.text and fig._label.modulate != live._label.modulate,
		"its tag says it is a hello, in another color than a child's name (%s / %s)" % [fig._label.text, live._label.text])
	check(fig.get_node_or_null("HelloRing") != null and live.get_node_or_null("HelloRing") == null, "a ring lies under the figure and under no child")
	check(main.world.kids.size() == 1, "and it is not counted as a child")
	await figure_looks_different(fig, live)
	# Walk away and come back: it plays its three emotes.
	await stand_at(at + Vector2(9.0, 0.0))
	await wait(0.5)
	fx.figures[pid]["rest"] = 0.0
	var played: int = fx.played
	await stand_at(at + Vector2(0.9, 0.9))
	check(await until(func(): return fx.played == played + 3, 8.0), "when the child comes near, the figure plays its three emotes (%d)" % (fx.played - played))
	await settle_camera()
	await shot("hello_figure")
	# A friend's answer, read on the hello's own card.
	Session.players[77] = {"avatar": Avatar.sanitize(Avatar.PRESETS[1]), "state": {"space": "town", "x": at.x + 0.5, "z": at.y + 0.5, "ry": 0.0, "anim": "idle"}, "pid": "b".repeat(32)}
	Session._srv_echo_answer(77, 0, pid, "cheer")
	Session.players.erase(77)
	check(Session.model.echoes[pid]["answers"].size() == 1, "set up: a friend answered")
	check(await do_context("echo"), "next to their own hello the action is Your hello")
	check(await until(func(): return dialog("Echo") != null, 2.0), "its card opens")
	var card := dialog("Echo")
	if card:
		var text := dialog_text(card)
		check((tr("%s answered: %s") % [tr(Avatar.PRESETS[1]["nick"]), tr("Cheer")]) in text and (tr("It stays for %d more days.") % 7) in text, "it says who answered and how long it stays (%s)" % text.replace("\n", " | "))
		await shot("hello_card")
		await act(button_text(card, "Take it away"), "Take it away")
	check(await until(func(): return not Session.model.echoes.has(pid), 3.0), "the creator takes the hello away")
	await frames(4)
	check(not fx.figures.has(pid), "the figure is gone")
	check(await until(func(): return Echoes.new_answers(Session.model, pid).is_empty(), 1.0), "nothing is left behind")
	_case_ok = true


## An animal friend rides in the trailer.
func _passenger(hud: Control, c: Node) -> void:
	await calm()
	await stand_at(station_at + Vector2(0.0, 1.7))
	check(await do_context("ride_board"), "Get in the cart")
	check(await until(func(): return Session.ride_of(Session.my_id) == station, 3.0), "in the cart")
	var sheep := animal("sheep")
	var trailer: Vector2 = Animals.trailer_pose(station)["pos"]
	sheep["pos"] = Animals.brain._free_near(Session.model, trailer + Vector2(0.3, 2.0), 0.5)
	sheep["plan"] = ""
	sheep["timer"] = 30.0
	sheep["goal"] = null
	await wait(0.5)
	c.open_panel.emit("animal", {"kind": "sheep"})   # what a tap on Wooly does
	check(await until(func(): return hud._overlay.get_child_count() > 0, 2.0), "Wooly's card opens")
	await frames(4)   # the card is laid out before anything on it is pressed
	var invite: Button = hud._overlay.find_child("RideInvite", true, false) as Button
	check(invite != null and invite.text == "Come for a ride", "in a cart at the station the card offers Come for a ride")
	if invite:
		await act(invite, "Come for a ride")
	check(await until(func(): return Animals.riders.get("sheep", "") == station, 3.0), "Wooly is asked for a ride")
	check(await until(func(): return sheep["aboard"], 8.0), "and hops into the trailer")
	await frames(6)
	var node: Node3D = main.world.animals.get("sheep")
	var tnode: Node3D = main.world.item_nodes[station].get_node("Trailer")
	check(node != null and Vector2(node.global_position.x, node.global_position.z).distance_to(Vector2(tnode.global_position.x, tnode.global_position.z)) < 0.5, "it is drawn in the trailer")
	await settle_camera()
	await shot("passenger_aboard")
	check(await do_context("ride_go"), "Go!")
	await wait(1.6)
	check(Vector2(node.global_position.x, node.global_position.z).distance_to(Vector2(tnode.global_position.x, tnode.global_position.z)) < 0.5 and Vector2(tnode.global_position.x, tnode.global_position.z).distance_to(trailer) > 1.5,
		"Wooly rides along in the trailer behind the cart")
	check(main.world.ride_fx.passengers_drawn.get("sheep", "") == station, "drawn as this cart's passenger")
	await shot("passenger_riding")
	await get_off()
	check(await until(func(): return Animals.riders.is_empty() and not sheep["aboard"], 3.0), "the child gets off: Wooly hops out at the station")
	check(sheep["pos"].distance_to(station_at) < 3.2, "next to the station (%.1f m)" % sheep["pos"].distance_to(station_at))
	park_animals()
	_case_ok = true


## The new texts and cards in one language.
func _texts_of(loc: String, hud: Control, c: Node) -> void:
	I18n.set_locale(loc)
	await frames(4)
	await calm()
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	for key in ["Light the lamp", "Put out the lamp", "Every lamp is lit. The fireflies have come!", "Signal rail", "Weather bell", "The weather bells are ringing!", "Picture board", "Paint a picture",
			"Hello", "Leave a hello", "Leave it here", "Your hello", "Answer the hello", "Take it away", "Come for a ride", "Hop out", Echoes.ERR_EMOTES, Lamplight.ERR_WALK]:
		check(loc == "en" or tr(key) != key, "[%s] \"%s\" is translated (%s)" % [loc, key.left(30), tr(key).left(30)])
	check("%d" in tr("It stays for %d more days.") and tr("%s answered: %s").count("%s") == 2, "[%s] the sentences keep their numbers and names" % loc)
	# The lamp's action fits its button.
	await stand_at(lamp_at + Vector2(0.0, 1.0))
	check(await until(func(): return c._ctx.get("type", "") == "lamp" and hud._context_btn.is_visible_in_tree(), 3.0), "[%s] the lamp's action is offered" % loc)
	await frames(3)
	var need: float = hud._context_btn.get_theme_font("font").get_string_size(tr(hud._context_btn.text), HORIZONTAL_ALIGNMENT_LEFT, -1, hud._context_btn.get_theme_font_size("font_size")).x
	check(need <= hud._context_btn.size.x - 24.0 and area.grow(1.0).encloses(hud._context_btn.get_global_rect()), "[%s] \"%s\" fits its button inside the safe area" % [loc, tr(hud._context_btn.text)])
	# The menu column with Hello stays inside the screen and clear of the emote row.
	check(area.grow(1.0).encloses(hud._echo_btn.get_global_rect()) and not hud._echo_btn.get_global_rect().intersects(hud._emotes.get_global_rect()), "[%s] Hello is inside the safe area, above the emotes (%s)" % [loc, hud._echo_btn.get_global_rect()])
	# The picture board's card and the hello recorder fit.
	await stand_at(board_at + Vector2(0.0, 1.3))
	check(await do_context("board"), "[%s] Paint a picture" % loc)
	check(await until(func(): return dialog("Board") != null, 2.0), "[%s] the board's card opens" % loc)
	var card := dialog("Board")
	if card:
		await frames(3)
		var panel: Control = card.find_children("*", "PanelContainer", true, false)[0]
		check(area.grow(1.0).encloses(panel.get_global_rect()), "[%s] the board's card fits the screen (%s in %s)" % [loc, panel.get_global_rect(), area])
		if tv:
			await hints_ok("[%s] the board's card" % loc)
		await shot("board_%s" % loc)
		await act(button_text(card, "Close"), "Close")
	check(await until(func(): return dialog("Board") == null, 2.0), "[%s] the card closes" % loc)
	await act(hud._echo_btn, "Hello")
	check(await until(func(): return dialog("EchoRecorder") != null, 2.0), "[%s] Leave a hello opens" % loc)
	var rec := dialog("EchoRecorder")
	if rec:
		await frames(3)
		var panel: Control = rec.find_children("*", "PanelContainer", true, false)[0]
		check(area.grow(1.0).encloses(panel.get_global_rect()), "[%s] Leave a hello fits the screen (%s in %s)" % [loc, panel.get_global_rect(), area])
		if tv:
			await hints_ok("[%s] Leave a hello" % loc)
		await shot("hello_%s" % loc)
		await act(button_text(rec, "Close"), "Close")
	check(await until(func(): return dialog("EchoRecorder") == null, 2.0), "[%s] it closes, and nothing is left" % loc)
	check(not Session.model.echoes.has(Session.my_pid), "[%s] closing leaves no hello" % loc)
	_case_ok = true
