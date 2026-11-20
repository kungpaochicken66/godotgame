## Inside a cottage, while a thing is held, the placement tools leave the player's own child and the thing
## visible (first-steps r9, review D2). r8 kept the dollhouse room camera fixed while a thing was held; its
## own measurement in the starter cottage found the tools on the child at 24 (iPhone), 20 (iPad) and 30
## (TV) of 132 spots, always with the thing and the child on opposite places
## (build/dual-host/first-steps/r8-work-evidence-20261114/measurement/ROOMVIEW-pre-fix-report.md).
## r9: the room camera keeps its view and steps straight back only until the tools have a free place.
##
## The same cottage, things and places of the child as that measurement, through the real Decorate
## button, with a wall thing and a ceiling thing (mounted things hang below their origin). At every spot,
## once the camera and the tools have settled:
##   set up: the game is in the room, the thing is held at the spot, the child stands at its place;
##   the child (its meshes and name tag) is whole on screen and the thing is on screen;
##   (r10) the thing (its own meshes, as below) is whole inside the safe area, not only partly on screen;
##   (r10) no part of a menu beside the room or of the top bar's right part (the left menu, the saved status,
##   lanterns and corner buttons, the camera buttons, the bottom right column, poses and emotes) that is
##   shown covers the child or the thing; a menu that steps aside for them takes no press and is no
##   controller target, and every menu is back, shown and pressable, once the thing is placed or cancelled;
##   nothing laid over the world for placing (the tools, and on a controller its hints) touches the child
##   or the thing: its own meshes, not the placement ring on the floor under it and not its soft contact
##   shadow (a flat disc on the floor, at 22 %; mesh_kit.gd blob_shadow, sized by each model). How much of that shadow the tools lie on is printed at every spot (DIAG) and counted.
##   (r9 development run 2: measured with the shadow, the tools lay on its edge at 23 of 270 spots.)
## Pictures: at most 12 (three per held thing, first language), at spots where r8's fixed room camera
## put the tools on the child, and one where nothing needed to change.
##   Touch:      scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/room_tools_tour.gd \
##                   --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de
##   Controller: scripts/godot.sh --path game --resolution 1920x1080 -- --driver=res://tests/room_tools_tour.gd \
##                   --tv --pad-layout=nintendo --shots=/abs/dir --tag=atv --locales=en,zh-CN,ja,es,fr,de
## Logic only, no renderer (EC2): add --headless before --path, and --no-shots --window=WxH after --.
## --spots=few: in every language after the first only the spots where r8's fixed camera covered the child
## at some layout (the child at the back or at the front right); all spots in the first language.
## --only=kind/child place/x,z;...: only those spots (development: one deterministic case instead of the sweep).
## Its town is its own save (user://room_tools_tour_town.json), deleted at the start of every run.
## r10 (Mac review of r9, room47-all-ipad shot 08): on the iPad the left menu's Story and Hello lay over the
## night painting held at the left wall's front end, part of which was also past the screen's left edge, and
## the saved-status pill over a bird mobile at the back. The menus are found from nodes r9 has as well
## (side_menus), so the same tour judges r9's product as a control.
extends "res://tests/puzzle_ride_tour.gd"

const ROOM_TOWN := "user://room_tools_tour_town.json"
const MeshKitForShadow := preload("res://scripts/art/mesh_kit.gd")
const KID_SPOTS := [["front", Vector2(0.0, 2.5)], ["middle", Vector2(0.0, 0.0)], ["back", Vector2(-1.0, -2.3)], ["front-right", Vector2(3.3, 2.5)]]
const FLOOR_SPOTS := [Vector2(-3, -2), Vector2(-1, -2), Vector2(1, -2), Vector2(3, -2),
	Vector2(-3, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(3, 0),
	Vector2(-3, 2), Vector2(-1, 2), Vector2(1, 2), Vector2(3, 2)]
## Floor points handed to the controller for a wall thing: it is mounted on the back wall (z = -3) or the left wall (x = -4).
const WALL_SPOTS := [Vector2(-3, -3), Vector2(-1.5, -3), Vector2(0, -3), Vector2(1.5, -3), Vector2(3, -3),
	Vector2(-4, -1.5), Vector2(-4, 0), Vector2(-4, 1.5), Vector2(-4, 2.5)]
const KINDS := [["table", "floor"], ["bookshelf", "floor"], ["framed_painting_night", "wall"], ["bird_mobile", "ceiling"]]
## Pictures (first language): [thing, child place, spot]. The first two of each thing were covered spots
## under r8's fixed camera at some layout; the last is a spot where the room view stays as it was.
const PICTURES := [["table", "back", Vector2(1, 2)], ["table", "front-right", Vector2(-3, -2)], ["table", "front", Vector2(1, -2)],
	["bookshelf", "back", Vector2(1, 2)], ["bookshelf", "front-right", Vector2(-3, -2)], ["bookshelf", "front", Vector2(1, -2)],
	["framed_painting_night", "front-right", Vector2(-4, -1.5)], ["framed_painting_night", "back", Vector2(-4, 2.5)], ["framed_painting_night", "front", Vector2(0, -3)],
	["bird_mobile", "back", Vector2(1, 2)], ["bird_mobile", "front-right", Vector2(-3, -2)], ["bird_mobile", "front", Vector2(1, -2)],
	# r10: the painting at an accepted spot beside the left menu, and the bird mobile under the saved status.
	["framed_painting_night", "back", Vector2(-4, 1.5)], ["bird_mobile", "front", Vector2(-3, -2)]]
const MAX_PICTURES := 14

var _spots := 0
var _stepped := 0
var _on_shadow := 0
var _menus_stepped := 0


## The menus beside the room and the top bar's right part, as hud.gd side_menus gives them in r10, found
## from nodes r9's HUD has too: the left menu, the top bar's row (the saved status's label, its row, its
## panel, then the bar's row), the camera buttons, the bottom right column, and the poses' column.
func side_menus() -> Array:
	var hud: Control = main.hud
	return [hud._left_stack, hud._status.get_parent().get_parent().get_parent(), hud._cam_tools, hud._side_col, hud._poses.get_parent()]


## How much of a canvas item shows: its own and its parents' alpha.
func shown_alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


## The parts of the side menus on screen now (visible and not stepped aside): [[name, rect], ...].
func menu_parts() -> Array:
	var out := []
	for m in side_menus():
		if not (m as Control).is_visible_in_tree() or shown_alpha(m) < 0.05:
			continue
		for ch in (m as Control).get_children():
			if ch is Control and (ch as Control).is_visible_in_tree() and (ch as Control).get_global_rect().has_area():
				out.append([_part_name(ch), (ch as Control).get_global_rect()])
	return out


func _part_name(ch: Control) -> String:
	if ch is Button and (ch as Button).text != "":
		return (ch as Button).text
	if ch is Button and (ch as Button).tooltip_text != "":
		return (ch as Button).tooltip_text
	return str(ch.name)


## Whether a visible part of the menu `m` lies within the HUD's own boxes for the thing and the child (hud.gd
## placement_rects, which r9 has too), the thing's grown by 16 px and the child's by 8 px, times `k` (as hud.gd
## _keep_menus_clear judges it, r10: MENU_THING_GAP, MENU_KID_GAP; 2 once a menu is aside). r11: the thing's
## box takes in its meshes' boxes as this tour measures them (thing_rect), as the product now judges it too.
func menu_near(m: Control, k: float) -> bool:
	var boxes: Array = main.hud.placement_rects()
	var meshes := thing_rect()
	var tb: Rect2 = boxes[0]
	if meshes.has_area():
		tb = tb.merge(meshes) if tb.has_area() else meshes
	var t: Rect2 = tb.grow(16.0 * k) if tb.has_area() else Rect2()
	var c: Rect2 = boxes[1].grow(8.0 * k) if boxes[1].has_area() else Rect2()
	for ch in m.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree():
			var r: Rect2 = (ch as Control).get_global_rect()
			if r.has_area() and (r.intersects(t) or r.intersects(c)):
				return true
	return false


## Every side menu is back: shown, taking presses, and its buttons are controller targets again.
func menus_back(w: String) -> void:
	await frames(3)
	var targets: Array = pad.targets()
	for m in side_menus():
		var mc := m as Control
		if not mc.is_visible_in_tree():
			continue
		var buttons: Array = mc.find_children("*", "BaseButton", true, false).filter(func(b): return b.is_visible_in_tree() and not b.disabled)
		var reached: Array = buttons.filter(func(b): return targets.has(b))
		check(shown_alpha(mc) > 0.99 and mc.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED and reached.size() == buttons.size(),
			"%s: the menu %s is back, shown and pressable (alpha %.2f, mouse %d, %d of %d buttons reachable)" % [w, mc.name, shown_alpha(mc), mc.mouse_behavior_recursive, reached.size(), buttons.size()])


func shot(name: String) -> void:
	if _n >= MAX_PICTURES or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/room_tools_%s_%02d_%s.png" % [shots, tag, _n, name])


## r11: pictures at named cases in any language (--extra-shots=de/table/back/-3,2;...), besides and apart from
## the first language's PICTURES (which stay as they are, and keep their cap). Taken after the case's checks,
## whether they passed or not, so a failing case has its own frame. The side-menu parts and the thing's box are
## logged with it, for reading the picture. With --no-shots only the log line is written.
var _extra_n := 0

func extra_shot(loc: String, kind: String, kid_name: String, at: Vector2) -> void:
	var key := "%s/%s/%s/%d,%d" % [loc, kind, kid_name, int(at.x), int(at.y)]
	if not Array(str(main.args.get("extra-shots", "")).split(";", false)).has(key):
		return
	var pic := "%s_%s_child_%s_%d_%d" % [loc, kind, kid_name, int(at.x), int(at.y)]
	var thing := thing_rect()
	var parts := []
	for pr in menu_parts():
		parts.append("%s %s%s" % [pr[0], pr[1], " ON THE THING" if (pr[1] as Rect2).intersects(thing) else ""])
	var aside: Array = side_menus().filter(func(m): return (m as Control).is_visible_in_tree() and shown_alpha(m) < 0.05)
	var saved: bool = not main.args.has("no-shots")
	if saved:
		await RenderingServer.frame_post_draw
		_extra_n += 1
		get_viewport().get_texture().get_image().save_png("%s/room_tools_%s_extra%02d_%s.png" % [shots, tag, _extra_n, pic])
	print("DIAG extra picture %s (%s): thing %s; stepped aside: %s; menu parts shown: %s" % [key,
		("room_tools_%s_extra%02d_%s.png" % [tag, _extra_n, pic]) if saved else "not saved: --no-shots", thing,
		", ".join(aside.map(func(m): return str(m.name))), "; ".join(parts)])


## The thing's soft contact shadow (mesh_kit.gd blob_shadow): a flat quad facing up that casts no shadow, drawn
## with the kit's own shadow texture.
func is_contact_shadow(m: MeshInstance3D) -> bool:
	return m.mesh is QuadMesh and (m.mesh as QuadMesh).orientation == PlaneMesh.FACE_Y and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and m.material_override is StandardMaterial3D and (m.material_override as StandardMaterial3D).albedo_texture == MeshKitForShadow._shadow_texture()


## The held thing on screen from its own meshes, without the placement ring that lies on the floor under it and
## (unless `shadow`) without its contact shadow; with `shadow`, the contact shadow alone.
func thing_rect(shadow := false) -> Rect2:
	var c: Node = main.controller
	var cam: Camera3D = main.rig.camera
	var r := Rect2()
	var first := true
	if c.ghost == null or not c.ghost.is_visible_in_tree():
		return r
	for m in c.ghost.find_children("*", "MeshInstance3D", true, false):
		if m == c._ghost_ring or not m.is_visible_in_tree() or (m as MeshInstance3D).mesh == null:
			continue
		if is_contact_shadow(m) != shadow:
			continue
		var box: AABB = (m as MeshInstance3D).get_aabb()
		for i in 8:
			var pt: Vector3 = (m as MeshInstance3D).global_transform * box.get_endpoint(i)
			if cam.is_position_behind(pt):
				continue
			var at: Vector2 = cam.unproject_position(pt)
			r = Rect2(at, Vector2.ZERO) if first else r.expand(at)
			first = false
	return r


func spot(loc: String, kind: String, kid_name: String, at: Vector2) -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	var rig: Node3D = main.rig
	var area: Rect2 = _area() if tv else hud.get_global_rect()
	var w := "[%s] %s at (%.1f,%.1f), the child at the %s" % [loc, kind, at.x, at.y, kid_name]
	c._move_ghost_to(at)
	await settle_camera()
	await tools_settled()
	await settle_camera()
	_spots += 1
	var g: Vector3 = c.ghost.global_position if c.ghost != null else Vector3.INF
	var mount: String = Catalog.anchor(kind)
	# A wall thing is mounted over its floor point on the back or left wall, a ceiling thing hangs over it: the
	# same x and z for every anchor (r8 ROOMVIEW logs; independent review of r9, R2).
	var placed_ok: bool = c.ghost != null and c.g_kind == kind and Vector2(g.x, g.z).distance_to(at) < 0.3
	check(rig.in_room and c.space != "town" and placed_ok, "%s: set up: in the room, the thing held at its spot (held %s, at (%.2f,%.2f,%.2f), anchor %s)" % [w, c.g_kind, g.x, g.y, g.z, mount])
	var panels := []
	for pnl in [hud._tools, hud._hint_panel]:
		if pnl.is_visible_in_tree():
			panels.append(pnl.get_global_rect())
	var over := panels.duplicate()
	if tv and pad._hint_panel.is_visible_in_tree():
		over.append(pad._hint_panel.get_global_rect())
	var kid := kid_screen_rect()
	var thing := thing_rect()
	var shade := thing_rect(true)
	var shade_px := 0
	for r in over:
		if r.intersects(shade):
			shade_px += int(round(r.intersection(shade).get_area()))
	if shade_px > 0:
		_on_shadow += 1
	var dist: float = rig._distance
	if dist > rig.ROOM_DISTANCE + 0.01:
		_stepped += 1
	print("DIAG %s: place \"%s\"; camera distance %.2f m (room view %.2f m); tools %s; child %s; thing %s; contact shadow %s, tools on it %d px2; g_error \"%s\"" % [w, hud.dock, dist, rig.ROOM_DISTANCE, str(over), kid, thing, shade, shade_px, c.g_error])
	check(panels.size() >= 1 and absf(hud._tools_box.modulate.a - 1.0) < 0.01, "%s: set up: the tools are shown" % w)
	check(kid.has_area() and area.grow(1.0).encloses(kid), "%s: the child is whole on screen (child %s, screen %s)" % [w, kid, area])
	check(thing.has_area() and area.intersects(thing), "%s: the thing is on screen (thing %s)" % [w, thing])
	check(over.all(func(r): return not r.intersects(kid)), "%s: the tools do not cover the child or the name tag (place \"%s\"; tools%s %s, child %s)" % [w, hud.dock, " and controller hints" if over.size() > panels.size() else "", str(over), kid])
	check(over.all(func(r): return not r.intersects(thing)), "%s: the tools do not cover the thing being placed (place \"%s\"; tools %s, thing %s)" % [w, hud.dock, str(over), thing])
	# r10: the thing whole inside the safe area, and no side menu or top bar part on it or on the child.
	var parts := menu_parts()
	var on_thing := 0
	var on_kid := 0
	var names := []
	for pr in parts:
		var r: Rect2 = pr[1]
		if r.intersects(thing):
			on_thing += int(round(r.intersection(thing).get_area()))
			names.append(pr[0])
		if r.intersects(kid):
			on_kid += int(round(r.intersection(kid).get_area()))
			names.append(pr[0])
	var aside: Array = side_menus().filter(func(m): return (m as Control).is_visible_in_tree() and shown_alpha(m) < 0.05)
	if not aside.is_empty():
		_menus_stepped += 1
	var past := int(round(thing.get_area() - thing.intersection(area).get_area())) if thing.has_area() else -1
	print("DIAG %s: side menus on the thing %d px2, on the child %d px2 (%s); stepped aside: %s; thing past the safe area %d px2" % [w, on_thing, on_kid, ", ".join(names),
		", ".join(aside.map(func(m): return str(m.name))), past])
	check(thing.has_area() and area.grow(1.0).encloses(thing), "%s: the thing is whole inside the safe area (thing %s, safe area %s)" % [w, thing, area])
	check(on_kid == 0, "%s: no side menu or top bar part covers the child or the name tag (%d px2: %s; child %s)" % [w, on_kid, ", ".join(names), kid])
	check(on_thing == 0, "%s: no side menu or top bar part covers the thing being placed (%d px2: %s; thing %s)" % [w, on_thing, ", ".join(names), thing])
	if not aside.is_empty():
		var targets: Array = pad.targets()
		for m in aside:
			check((m as Control).mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED and targets.all(func(t): return not (m as Control).is_ancestor_of(t)),
				"%s: the menu %s, stepped aside, takes no press and is no controller target" % [w, m.name])
			# Independent review of r10, risk 2: a menu steps aside only for the thing or the child.
			check(menu_near(m, 2.0), "%s: the menu %s steps aside only when it is near the thing or the child (a part within 32 px of the thing's box or 16 px of the child's)" % [w, m.name])


func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "1500"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "1500"))
		print("ROOM_TOOLS %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	print("ROOM_TOOLS start tag=%s input=%s engine=%s renderer=%s" % [tag, "controller" if tv else "touch",
		Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method()])
	Session.request_done.connect(func(req, result): _replies.append([req, result]))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	for f in [ROOM_TOWN, ROOM_TOWN + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	Session.start_solo(ROOM_TOWN, main.menus.avatar)
	await wait(1.5)
	if hud._overlay.get_child_count() > 0:
		await close_dialogs()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	main.world.set_reduce_motion(false)
	Activities._wish_wait = -1.0e6   # no animal wish rebuilding the toy box during the tour (as puzzle_ride_tour)
	park_animals()
	var house := ""
	for it in Session.model.items_in("town"):
		if it["kind"] == "cottage":
			house = it["id"]
			break
	check(house != "", "set up: the starter town has a cottage")
	c.enter_house(house)
	check(await until(func(): return c.space != "town" and main.rig.in_room, 5.0), "set up: the child is inside the cottage and the room camera is on (space %s)" % c.space)
	await frames(6)
	park_animals()
	await settle_camera()
	if c.mode != "decorate":
		await act(hud._decorate_btn, "Decorate")
	check(await until(func(): return c.mode == "decorate", 3.0), "set up: the Decorate button opens Decorate in the room")
	await wait(1.0)
	var only: Array = Array(str(main.args.get("only", "")).split(";", false))
	for li in locales.size():
		var loc: String = locales[li]
		I18n.set_locale(loc)
		await frames(4)
		for kd in KINDS:
			var kind: String = kd[0]
			var spots: Array = FLOOR_SPOTS if kd[1] != "wall" else WALL_SPOTS
			for ks in KID_SPOTS:
				if li > 0 and main.args.get("spots", "all") == "few" and not (ks[0] in ["back", "front-right"]):
					continue
				await stand_at(ks[1])
				check(c.pos.distance_to(ks[1]) < 0.05, "[%s] set up: the child stands at the %s of the room (at (%.2f,%.2f))" % [loc, ks[0], c.pos.x, c.pos.y])
				c.begin_new(kind)
				if not await until(func(): return c.ghost != null and c.g_kind == kind, 3.0):
					check(false, "[%s] set up: a %s is held" % [loc, kind])
					continue
				for at in spots:
					if not only.is_empty() and not only.has("%s/%s/%d,%d" % [kind, ks[0], int(at.x), int(at.y)]):
						continue
					await spot(loc, kind, ks[0], at)
					await extra_shot(loc, kind, ks[0], at)
					if li == 0:
						for p in PICTURES:
							if p[0] == kind and p[1] == ks[0] and p[2] == at:
								await shot("%s_child_%s" % [kind, ks[0]])
				c.cancel_ghost()
				await until(func(): return c.ghost == null, 3.0)
				await frames(6)
				await menus_back("[%s] %s, the child at the %s, cancelled" % [loc, kind, ks[0]])
		case_done_room(loc)
	# r10: the menus come back after a real Cancel and a real Place here, and a menu button then acts: the
	# painting at the left wall's front end beside the left menu (an accepted spot), the child at the back
	# (on the iPad the left menu steps aside there).
	I18n.set_locale(locales[0])
	await frames(4)
	await stand_at(KID_SPOTS[2][1])
	for how in ["Cancel", "Place here"]:
		var w := "[%s] after %s" % [locales[0], how]
		c.begin_new("framed_painting_night")
		if not await until(func(): return c.ghost != null, 3.0):
			check(false, "%s: set up: a painting is held" % w)
			continue
		c._move_ghost_to(Vector2(-4, 1.5))
		await settle_camera()
		await tools_settled()
		await settle_camera()
		check(c.ghost != null and c.g_error == "", "%s: set up: the painting is held at an accepted spot (g_error \"%s\")" % [w, c.g_error])
		var aside_before: Array = side_menus().filter(func(m): return (m as Control).is_visible_in_tree() and shown_alpha(m) < 0.05)
		var near: Array = side_menus().filter(func(m): return (m as Control).is_visible_in_tree() and menu_near(m, 1.0))
		print("DIAG %s: before, stepped aside: %s; near the thing or the child: %s" % [w, ", ".join(aside_before.map(func(m): return str(m.name))), ", ".join(near.map(func(m): return str(m.name)))])
		# Independent review of r10, risk 3: where a menu stands near the thing or the child at this layout, it is aside.
		for m in near:
			check(aside_before.has(m), "%s: set up: the menu %s, near the thing or the child, has stepped aside" % [w, m.name])
		if how == "Cancel" and not aside_before.is_empty():
			# Risk 4: a real press where a stepped-aside menu's button is does not press it (by finger, or the
			# controller's pointer and A). The press reaches the room instead and may move the held thing there.
			var hidden: Array = (aside_before[0] as Control).find_children("*", "BaseButton", true, false).filter(func(x): return x.is_visible_in_tree())
			if not hidden.is_empty():
				var hb: BaseButton = hidden[hidden.size() - 1]
				var fired := [0]
				var count := func(): fired[0] += 1
				hb.pressed.connect(count)
				var opened: int = hud._overlay.get_child_count()
				if tv:
					pad.tap_at(hb.get_global_rect().get_center())
				else:
					await tap(hb.get_global_rect().get_center())
				await frames(12)
				hb.pressed.disconnect(count)
				check(fired[0] == 0 and hud._overlay.get_child_count() == opened, "%s: a press on the stepped-aside %s's button %s does nothing to it (pressed %d time(s), dialogs %d to %d)" % [w, aside_before[0].name, _part_name(hb), fired[0], opened, hud._overlay.get_child_count()])
				await settle_camera()
		await act(pad._tool(how), how)
		check(await until(func(): return c.ghost == null, 3.0), "%s: set up: %s ends the hold" % [w, how])
		await menus_back(w)
	var opened0: int = hud._overlay.get_child_count()
	await act(hud._guide_btn, "Activities")
	check(await until(func(): return hud._overlay.get_child_count() > opened0, 3.0), "[%s] after placing: the left menu's Activities opens again" % locales[0])
	await close_dialogs()
	I18n.set_locale(locales[0])
	print("DIAG room tools: %d spots, the camera stepped back at %d, the tools on the contact shadow at %d, a side menu stepped aside at %d" % [_spots, _stepped, _on_shadow, _menus_stepped])
	check(_spots > 0, "set up: spots were judged (%d)" % _spots)
	check(_real_mouse == 0, "no mouse, trackpad or touch event from outside reached the game during the %s tour (%d; first: %s)" % ["controller" if tv else "touch", _real_mouse, _real_mouse_first])
	print("ROOM_TOOLS %s %s: %d failures, %d screenshots" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n])
	Music.quit_game(1 if failures else 0)


func case_done_room(loc: String) -> void:
	print("DIAG room tools: [%s] done, %d spots so far" % [loc, _spots])
