## Focused check of the r12 wardrobe (docs/wearables.md) through the real UI: Dress up ->
## Wardrobe, representative categories worn by tapping, a dress-up replacing top and bottom,
## the gated note, the seated variant and held umbrella on a bench, the swing, the seesaw and
## a bed, an emote with the umbrella, taking things off, and leaving and joining again with the
## kept look (the umbrella is one of the rev5 hold-contract items). Every pressed control must be touch-safe (big enough, inside the safe area).
## At most 10 shots.
##   scripts/godot.sh --path game --resolution 2208x1024 -- --driver=res://tests/wear_tour.gd \
##       --shots=/abs/dir --tag=iphone --safe-insets=154,0,154,55 --locales=de,ja
## Logic only, no renderer (EC2 smoke): add --headless before --path, --no-shots and
## --window=2208x1024 after --.
extends "res://tests/play3_tour.gd"

const W := preload("res://scripts/core/wearables.gd")
## Smallest touch target accepted for a wardrobe control, in canvas pixels (UI.TOUCH is 76;
## tabs and item tiles are 56-60 high, above the 44 pt platform minimum at this scale).
const MIN_TOUCH := 52.0

## Picture readiness budgets (seconds), end to end from the request (the tap that opens the tab) to every
## visible tile showing its own picture at the card's remembered position: a tab whose pictures are not in
## memory (cold), and the same tab reopened after its pictures were made (warm).
const COLD_BUDGET := 3.0
const WARM_BUDGET := 0.25

const DRESS := "paradise_planning_maxi"   # c016 seated variant
const HELD := "ladybug_umbrella"           # c014 bytes, W9 hold record c018 (rev5)


func shot(name: String) -> void:
	if _n >= 10 or main.args.has("no-shots"):
		return
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png("%s/wear_%s_%02d_%s.png" % [shots, tag, _n, name])


func items_of(kind: String) -> Array:
	return Session.model.items.values().filter(func(i): return i["kind"] == kind and i["space"] == "town")


func worn() -> Dictionary:
	return Session.players[Session.my_id]["avatar"].get("wear", {})


func kid_meshes(id: String) -> Array:
	var kid: Node3D = main.world.local_kid()
	return kid.find_children(id + "_*", "MeshInstance3D", true, false) if kid else []


func shown(name: String) -> bool:
	var kid: Node3D = main.world.local_kid()
	var m: Array = kid.find_children(name, "MeshInstance3D", true, false) if kid else []
	return m.size() == 1 and m[0].is_visible_in_tree()


## A real tap on a wardrobe control, only if a finger can reach it: big enough, fully inside
## the safe area and (in the item list) scrolled into the visible part of the list.
func touch(b: Control, what: String) -> void:
	if b == null:
		check(false, "%s is in the wardrobe" % what)
		return
	b = await scrolled_to(b)
	var r := b.get_global_rect()
	var safe: Rect2 = main.hud.get_global_rect().grow(0.5)
	var clip: Rect2 = safe
	var p := b.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	if p:
		clip = (p as Control).get_global_rect().grow(0.5)
	var okay: bool = r.size.y >= MIN_TOUCH and r.size.x >= MIN_TOUCH and safe.encloses(r) and clip.encloses(r)
	check(okay, "%s is touch-safe (%s, %d x %d)" % [what, r.position.round(), r.size.x, r.size.y])
	if okay:
		_taps.append(Time.get_ticks_msec())
		await press(b)


func open_wardrobe(category: String) -> void:
	var hud: Control = main.hud
	if wardrobe_card() == null:
		await close_dialogs()
		await press(hud._dress_btn)
		check(await until(func(): return hud._overlay.get_node_or_null("DressUp") != null, 3.0), "Dress up opens")
		await frames(4)
		await touch(named(hud._overlay, "WardrobeButton"), "the Wardrobe button")
		check(await until(func(): return wardrobe_card() != null, 3.0), "the Wardrobe opens from Dress up")
		await frames(4)
	var tab := find_button(wardrobe_card(), "wear_cat", category)
	if tab and hud._wardrobe_cat != category:
		await touch(tab, "the %s tab" % category)
		await until(func(): return hud._wardrobe_cat == category and wardrobe_card() != null, 3.0)
		await frames(4)
	check(hud._wardrobe_cat == category, "the %s tab is open" % category)
	await wardrobe_settled()


## The card stays inside the safe area on every frame for a while after it opened or changed
## (layout settles over frames on a real renderer: r12 Mac). Returns the worst rect seen.
func card_fits_while_settling(what: String, n := 20) -> void:
	var safe: Rect2 = main.hud.get_global_rect().grow(0.5)
	var worst := Rect2()
	var ok_all := true
	for i in n:
		await get_tree().process_frame
		var r := dialog_rect(main.hud)
		if r.size == Vector2.ZERO or not safe.encloses(r):
			ok_all = false
			worst = r
		elif worst.size == Vector2.ZERO or r.size.y > worst.size.y:
			worst = r
	check(ok_all, "%s fits the safe area on each of %d frames (%s)" % [what, n, worst])


## Every tile in the open tab shows its picture area above its whole name (broken only between words,
## every line shown, untrimmed, inside the tile) and stays touch-safe; no two tiles read the same.
func names_readable(what: String) -> void:
	var tiles: Array = wardrobe_card().find_children("*", "Button", true, false).filter(func(b): return b.has_meta("wear_item"))
	var bad := []
	var shown := []
	for b in tiles:
		var l: Label = b.find_child("Name", true, false)
		var pic: TextureRect = b.find_child("Pic", true, false)
		if l == null or pic == null:
			bad.append("%s: no name or picture" % b.get_meta("wear_item"))
			continue
		shown.append(tr(l.text))
		if l.autowrap_mode != TextServer.AUTOWRAP_WORD or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING \
				or l.get_visible_line_count() < l.get_line_count() or l.get_line_count() > 3 \
				or not b.get_global_rect().grow(0.5).encloses(l.get_global_rect()) or l.get_global_rect().position.y < pic.get_global_rect().end.y - 0.5 \
				or b.size.y < MIN_TOUCH or b.size.x < MIN_TOUCH:
			bad.append(tr(l.text))
	check(not tiles.is_empty() and bad.is_empty(), "%s: all %d tiles show a picture area above the whole name and stay touch-safe (%s)" % [what, tiles.size(), bad])
	print("DIAG %s: tiles %d, tallest %d px, names on 3 lines %d" % [what, tiles.size(), tiles.map(func(b): return b.size.y).max() if tiles.size() else 0, tiles.filter(func(b): return b.find_child("Name", true, false) and b.find_child("Name", true, false).get_line_count() == 3).size()])
	var uniq := {}
	for t in shown:
		uniq[t] = true
	check(uniq.size() == shown.size(), "%s: every tile reads differently" % what)


## Tiles of the open tab inside the visible part of the list.
func visible_tiles() -> Array:
	if wardrobe_card() == null:
		return []
	var scroll: ScrollContainer = wardrobe_card().find_child("WardrobeScroll", true, false)
	if scroll == null:
		return []
	var view := scroll.get_global_rect()
	return wardrobe_card().find_children("*", "Button", true, false).filter(func(b): return b.has_meta("wear_item") and b.get_global_rect().intersects(view))


## Waits until every visible tile shows its own picture (the cached picture of that very item) and
## checks the time from the moment the card was built (hud meta built_ms: before any picture of it was
## asked for) against budget. min_new: pictures that must have been made since the card was built
## (cold: proves they were not already waiting in memory). Also checks the pictures differ.
## Returns the seconds taken.
func pictures_ready(what: String, budget: float, min_new := 0, since_ms := -1, renders_since := -1, timed := true) -> float:
	var thumbs: Node = main.hud.wardrobe_thumbs()
	var card: Node = wardrobe_card()
	var t0: int = card.get_meta("built_ms", Time.get_ticks_msec()) if card else Time.get_ticks_msec()
	var r0: int = card.get_meta("renders_at_build", thumbs.renders) if card else thumbs.renders
	if since_ms >= 0:   # measured from a later event (a scroll), not from the card build
		t0 = since_ms
		r0 = renders_since
	var all_ok := func() -> bool:
		var tiles := visible_tiles()
		return not tiles.is_empty() and tiles.all(func(b):
			var pic: TextureRect = b.find_child("Pic", true, false)
			var id: String = b.get_meta("wear_item")
			return pic != null and pic.texture != null and thumbs.cache.get(id) == pic.texture)
	var deadline := Time.get_ticks_msec() + int((budget + 2.0) * 1000.0)
	while not all_ok.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame   # every frame, so the time is not rounded up to a polling step
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var tiles := visible_tiles()
	if timed:
		check(all_ok.call() and secs <= budget, "%s: all %d visible tiles show their own picture %.2f s after %s (budget %.2f s)" % [what, tiles.size(), secs, "the scroll" if since_ms >= 0 else "the card was built", budget])
	else:   # timing is checked end to end by check_watch; here only that the right pictures are shown
		check(all_ok.call(), "%s: all %d visible tiles show their own picture" % [what, tiles.size()])
	if min_new < 0:
		min_new = tiles.size()
	if min_new > 0:
		check(thumbs.renders - r0 >= min_new, "%s: %d pictures were made for it (at least %d), none were waiting in memory" % [what, thumbs.renders - r0, min_new])
	var seen := {}
	var dup := 0
	for b in tiles:
		var tex: Texture2D = (b.find_child("Pic", true, false) as TextureRect).texture
		if tex:
			var key := hash(tex.get_image().get_data()) if not thumbs.stub else tex.get_instance_id()
			if seen.has(key):
				dup += 1
			seen[key] = true
	check(dup == 0, "%s: the visible pictures all differ (%d duplicates)" % [what, dup])
	var sc: ScrollContainer = wardrobe_card().find_child("WardrobeScroll", true, false)
	print("DIAG view %s: scroll %d, visible %s" % [what, sc.scroll_vertical if sc else -1, tiles.map(func(b): return b.get_meta("wear_item"))])
	print("DIAG pictures %s: %.2f s, %d tiles, renders so far %d, cache %d, viewports %d, %s" % [what, secs, tiles.size(), thumbs.renders, thumbs.cache.size(), thumbs.viewports_alive(), "stub (no renderer)" if thumbs.stub else "rendered"])
	return secs


var _taps: Array = []   # when each wardrobe tap was sent (ms), to time requests end to end
var _watch := {}


## Watches, every frame, for the next Wardrobe card built after now: records the request (the last tap
## before it was built), the build, the settle at its remembered position, and the first frame on which
## every visible tile shows its own picture. Started before the opening tap; runs in the background so
## later checks do not add to the time.
func watch_pictures() -> void:
	var thumbs: Node = main.hud.wardrobe_thumbs()
	var start := Time.get_ticks_msec()
	_watch = {"start": start, "done": false}
	var w := _watch
	var deadline := start + 8000
	var card: Node = null
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var c := wardrobe_card()
		if c and c.get_meta("built_ms", 0) >= start and c != card:
			card = c   # follow the newest card (quick taps build several); its phases are measured afresh
			w.erase("built")
		if card == null or not is_instance_valid(card) or not card.get_meta("settled", false):
			continue
		if not w.has("built"):
			w["built"] = card.get_meta("built_ms")
			w["settled"] = card.get_meta("settled_ms")
			w["r0"] = card.get_meta("renders_at_build")
			var before: Array = _taps.filter(func(t): return t <= w["built"])
			w["request"] = before.max() if not before.is_empty() else start
		var tiles := visible_tiles()
		if not tiles.is_empty() and tiles.all(func(b):
				var pic: TextureRect = b.find_child("Pic", true, false)
				return pic != null and pic.texture != null and thumbs.cache.get(b.get_meta("wear_item")) == pic.texture):
			w["ready"] = Time.get_ticks_msec()
			w["renders"] = thumbs.renders - int(w["r0"])
			break
	w["done"] = true


## Checks the watched opening against budget (end to end, request to ready) and reports the phases.
func check_watch(what: String, budget: float, min_new := 0) -> void:
	await until(func(): return _watch.get("done", false), 9.0)
	var w := _watch
	if not w.has("ready"):
		check(false, "%s: every visible tile showed its own picture within %.1f s of the request" % [what, 8.0])
		return
	var total: float = (w["ready"] - w["request"]) / 1000.0
	print("DIAG timing %s: request->built %.3f s, built->settled %.3f s, settled->pictures %.3f s, total %.3f s, renders %d" % [what,
		(w["built"] - w["request"]) / 1000.0, (w["settled"] - w["built"]) / 1000.0, (w["ready"] - w["settled"]) / 1000.0, total, w["renders"]])
	check(total <= budget, "%s: end to end, request to every visible tile showing its own picture, %.3f s (budget %.2f s)" % [what, total, budget])
	if min_new > 0:
		check(w["renders"] >= min_new, "%s: %d pictures were made for it (at least %d); none were waiting in memory" % [what, w["renders"], min_new])


## The Wardrobe card on screen: the newest one built that is not being freed (a tab change frees the old
## card at the end of the frame, while it still holds the name "Wardrobe").
func wardrobe_card() -> Node:
	var best: Node = null
	for c in main.hud._overlay.get_children():
		if c.has_meta("built_ms") and not c.is_queued_for_deletion() and (best == null or c.get_meta("built_ms") >= best.get_meta("built_ms")):
			best = c
	return best


## The card is back at its remembered scroll position and has asked for its pictures (hud sets
## "settled"); nothing is tapped before that (r14 Mac retry1: a late position restore moved the list
## under a tap).
func wardrobe_settled() -> void:
	check(await until(func(): return wardrobe_card() != null and wardrobe_card().get_meta("settled", false), 3.0), "the Wardrobe has settled at its remembered position")
	await frames(1)


## Taps an item in the open wardrobe tab and waits for the authority to put it on.
func wear_by_tap(category: String, id: String) -> void:
	await open_wardrobe(category)
	await touch(find_button(wardrobe_card(), "wear_item", id), "%s (%s)" % [W.get_def(id)["name"], category])
	var slot: String = W.get_def(id)["slot"]
	check(await until(func(): return worn().get(slot) == id, 5.0), "%s is worn in the %s slot" % [id, slot])
	check(await until(func(): return kid_meshes(id).size() == W.get_def(id)["parts"].size(), 3.0), "%s is drawn on the child (%d parts)" % [id, kid_meshes(id).size()])
	await until(func(): return wardrobe_card() != null, 3.0)   # the card reopens on its tab
	await wardrobe_settled()


## Walks over to a seat by a real tap and uses it; returns the child's anim.
func seat_at(id: String, action: String) -> String:
	await frame_item(id)
	await tap_item(id)
	if not await until(func(): return not Session.seat_of(Session.my_id).is_empty(), 6.0):
		check(await use_context("sit", 8.0), "the %s action is offered next to it" % action)
	check(await until(func(): return not Session.seat_of(Session.my_id).is_empty(), 5.0), "%s: seated" % action)
	await frames(6)
	return main.world.local_kid().anim


func stand() -> void:
	main.controller.stand_up()
	check(await until(func(): return Session.seat_of(Session.my_id).is_empty(), 5.0), "stood up")
	await frames(6)


func _run() -> void:
	var hud: Control = main.hud
	var c: Node = main.controller
	get_tree().create_timer(float(main.args.get("timeout", "400"))).timeout.connect(func():
		check(false, "the tour finished within %s s" % main.args.get("timeout", "400"))
		print("WEAR %s FAIL: %d failures (timed out)" % [tag, failures])
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	var save := "user://wear_tour_town.json"
	for f in [save, save + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var saved_wear: Array = main.menus.avatar.get("wear", {}).values()   # a look saved on this device loads its worn models
	var start: Dictionary = main.menus.avatar.duplicate(true)
	start["wear"] = {}
	start["hat"] = ""
	start["prop"] = ""
	main.menus.avatar = start
	Session.start_solo(save, start)
	await wait(1.0)
	var area: Rect2 = hud.get_global_rect()
	var locales: Array = main.args.get("locales", "en").split(",")
	I18n.set_locale(locales[0])
	await frames(3)
	# Startup does no wardrobe work: no picture maker, no wearable model loaded (nothing is worn yet).
	check(hud._wear_thumbs == null, "no wardrobe picture maker exists before the Wardrobe opens")
	var loaded: Array = W.items().keys().filter(func(id): return ResourceLoader.has_cached(W.glb(id)) and not saved_wear.has(id))
	check(loaded.is_empty(), "no wearable model is loaded at startup beyond the %d of the saved look (%s)" % [saved_wear.size(), loaded])
	print("DIAG startup: %d ms from engine start to the tour (catalog thumbnails %s)" % [Time.get_ticks_msec(), "ready" if main.thumbs.is_done else "still rendering"])
	await _categories(hud)
	await _poses(hud, c)
	await _take_off(hud)
	await _rejoin(save)
	for loc in locales:
		await _fit(loc, hud, area)
	await _pictures_fast(hud)
	print("WEAR %s %s: %d failures, %d screenshots, %d wearable scenes cached" % [tag, "PASS" if failures == 0 else "FAIL", failures, _n, main.world.local_kid().wear_cache_size()])
	Music.quit_game(1 if failures else 0)


## Representative categories, each worn by a tap in its own tab; conflicts follow the rules.
func _categories(hud: Control) -> void:
	await open_wardrobe("Tops")
	await card_fits_while_settling("the Wardrobe")
	await names_readable("Tops")
	check(W.CATEGORIES.all(func(cat): return find_button(wardrobe_card(), "wear_cat", cat) != null), "all nine category tabs are there")
	check(find_button(wardrobe_card(), "wear_item", "a_tee") != null and wardrobe_card().find_children("*", "Button", true, false).filter(func(b): return b.has_meta("wear_item")).size() == W.ids_in("Tops").size(), "the Tops tab lists every accepted top (%d)" % W.ids_in("Tops").size())
	var hair_before: int = main.world.local_kid().find_children("*", "MeshInstance3D", true, false).size()
	await wear_by_tap("Tops", "a_tee")
	await wear_by_tap("Bottoms", "acid_washed_jeans")
	await close_dialogs()
	await settle_camera()
	await shot("top_and_bottom")   # the child, card closed
	var hat: String = W.ids_in("Headwear").filter(func(k): return not W.get_def(k)["band"])[0]
	await wear_by_tap("Headwear", hat)
	await wear_by_tap("Accessories", "goggles" if W.has("goggles") else W.ids_in("Accessories")[0])
	await wear_by_tap("Socks", W.ids_in("Socks")[0])
	await wear_by_tap("Shoes", "boots")
	await wear_by_tap("Bags", W.ids_in("Bags").filter(func(k): return W.get_def(k)["slot"] == "bag")[0])
	check(worn().size() == 7, "seven slots worn at once (%s)" % [worn().keys()])
	await close_dialogs()
	await settle_camera()
	await shot("seven_slots")   # the child, card closed
	await wear_by_tap("Dress-up", DRESS)
	check(not worn().has("top") and not worn().has("bottom") and kid_meshes("a_tee").is_empty() and kid_meshes("acid_washed_jeans").is_empty(), "the dress-up replaced the top and the bottom (and their meshes)")
	await open_wardrobe("Umbrellas")
	var waiting: int = W.gated().values().filter(func(g): return g["category"] == "Umbrellas").size()
	var want: String = tr("%d more are still being checked and come later.") % waiting
	var note: Array = wardrobe_card().find_children("*", "Label", true, false).filter(func(l): return l.text == want)
	check(note.size() == (1 if waiting > 0 else 0), "the Umbrellas tab lists all %d umbrellas; %d still being checked" % [W.ids_in("Umbrellas").size(), waiting])
	check(wardrobe_card().find_children("*", "Button", true, false).filter(func(b): return b.has_meta("wear_item")).size() == W.ids_in("Umbrellas").size(), "every umbrella has a tile")
	await wear_by_tap("Umbrellas", HELD)
	check(main.menus.avatar.get("wear", {}) == worn(), "the look is kept on this device for next time")
	await pictures_ready("Umbrellas (some pictures made earlier in the tour)", COLD_BUDGET)
	await shot("wardrobe_umbrellas")
	await close_dialogs()


## Seated variant and held item per pose: bench (sit), swing, seesaw (ride), bed (rest); an emote.
func _poses(hud: Control, c: Node) -> void:
	var kid: Node3D = main.world.local_kid()
	check(shown(DRESS + "_Body") and not shown(DRESS + "_Body_sit") and shown(HELD + "_ArmR"), "standing: standing skirt and the umbrella in hand")
	await tap_world_emote(hud, "Wave")
	var bench: Dictionary = items_of("bench")[0]
	var anim := await seat_at(bench["id"], "Sit")
	check(anim == "sit" and not shown(DRESS + "_Body") and shown(DRESS + "_Body_sit") and shown(DRESS + "_LegL_sit") and not shown(HELD + "_ArmR"), "on the bench: seated variant only, umbrella put away (%s)" % anim)
	check(is_equal_approx(kid._arms[0].rotation.x, W.SIT_HANDS_X) and is_equal_approx(kid._arms[1].rotation.x, W.SIT_HANDS_X), "seated hands rest over the knees")
	await settle_camera()
	await shot("bench_seated")
	await stand()
	check(shown(DRESS + "_Body") and not shown(DRESS + "_Body_sit") and shown(HELD + "_ArmR"), "standing again restores the skirt and the umbrella")
	if items_of("seesaw").is_empty():
		# Setup only (the starter town has no seesaw): placed through the session, then used by taps.
		var spot: Vector2 = Session.model.find_free_spot("seesaw", "town", c.pos + Vector2(4, 0))
		await _result_of(Session.place("seesaw", "town", spot, 0, -2))
		await until(func(): return not items_of("seesaw").is_empty(), 3.0)
	for spec in [["swing", "Swing", "swing"], ["seesaw", "Ride", "ride"]]:
		var items := items_of(spec[0])
		if items.is_empty():
			check(false, "a %s is in town" % spec[0])
			continue
		anim = await seat_at(items[0]["id"], spec[1])
		check(anim == spec[2] and shown(DRESS + "_Body_sit") and not shown(DRESS + "_Body") and not shown(HELD + "_ArmR"), "%s: seated variant, umbrella hidden (%s)" % [spec[1], anim])
		if spec[0] == "swing":
			await settle_camera()
			await shot("swing_seated")
		await stand()
	var beds: Array = Session.model.items.values().filter(func(i): return i["kind"] == "bed" and i["space"] != "town")
	if beds.is_empty():
		print("DIAG no bed in this town; rest is covered by the units (pose_state) only")
	else:
		c.go_to_room(beds[0]["space"])
		await wait(1.0)
		anim = await seat_at(beds[0]["id"], "Rest")
		check(anim == "rest" and shown(DRESS + "_Body_sit") and not shown(HELD + "_ArmR"), "Rest on a bed: seated variant, umbrella put away (%s)" % anim)
		await stand()
		c.go_to_room("town")
		await wait(1.0)


## An emote with the umbrella: the right arm stays in the hold envelope, the left arm moves.
func tap_world_emote(hud: Control, tip: String) -> void:
	var kid: Node3D = main.world.local_kid()
	await touch(tooltip_button(hud, tip), "the %s button" % tip)
	var worst := 0.0
	var most_l := 0.0
	for i in 40:
		var rx: float = kid._arms[1].rotation.x
		var rz: float = kid._arms[1].rotation.z
		worst = maxf(worst, maxf(maxf(rx - W.HOLD_X.y, W.HOLD_X.x - rx), maxf(rz - W.HOLD_Z.y, W.HOLD_Z.x - rz)))
		most_l = maxf(most_l, absf(kid._arms[0].rotation.x) + absf(kid._arms[0].rotation.z))
		if i == 12:
			await shot("wave_with_umbrella")   # mid-wave
		await get_tree().process_frame
	check(kid.emote_kind == tip.to_lower() or most_l > 0.5, "the %s emote plays" % tip)
	check(worst <= 0.001 and most_l > 0.5, "%s with the umbrella: right arm in the hold envelope (worst %.3f), left arm waves (%.2f)" % [tip, worst, most_l])


## Take it off: the umbrella and the dress-up come off by taps; their meshes go.
func _take_off(hud: Control) -> void:
	for spec in [["Umbrellas", "hand", HELD], ["Dress-up", "dress", DRESS]]:
		await open_wardrobe(spec[0])
		await touch(find_button(wardrobe_card(), "wear_off", spec[0]), "Take it off (%s)" % spec[0])
		check(await until(func(): return not worn().has(spec[1]), 5.0), "%s is off" % spec[2])
		check(await until(func(): return kid_meshes(spec[2]).is_empty(), 3.0), "and no longer drawn")
		var off := find_button(wardrobe_card(), "wear_off", spec[0])
		check(off != null and off.disabled, "Take it off is greyed out when nothing there is worn")
	await close_dialogs()
	await shot("taken_off")


## Leaving and joining again with the device's kept look wears the same things.
func _rejoin(save: String) -> void:
	var keep: Dictionary = worn().duplicate()
	check(main.menus.avatar.get("wear", {}) == keep, "the device kept the current look (%s)" % [keep.keys()])
	Session.leave()
	await wait(0.5)
	Session.start_solo(save, main.menus.avatar)
	await wait(1.0)
	check(worn() == keep, "joining again wears the same things")
	var kid: Node3D = main.world.local_kid()
	var n := 0
	for slot in keep:
		n += kid_meshes(keep[slot]).size() if kid else 0
	var want := 0
	for slot in keep:
		want += W.get_def(keep[slot])["parts"].size()
	check(n == want, "each worn item is drawn once (%d of %d meshes)" % [n, want])


func _fit(loc: String, hud: Control, area: Rect2) -> void:
	I18n.set_locale(loc)
	await frames(4)
	var tab: String = "Accessories" if loc == "ja" else "Dress-up"   # three representative tabs with Umbrellas
	# Cold: none of this tab's pictures are in memory (dropped first), so the time runs from the card
	# being built through asking for the pictures to all visible ones shown, and they must be made then.
	var thumbs: Node = hud.wardrobe_thumbs()
	await close_dialogs()
	await open_wardrobe("Tops" if tab != "Tops" else "Shoes")   # another tab first, so the measured open is one tap
	await until(func(): return thumbs.queued().is_empty() and not thumbs._busy, COLD_BUDGET)
	thumbs.forget(W.ids_in(tab))   # right before the measured tap: none of this tab's pictures are in memory
	watch_pictures()
	await open_wardrobe(tab)
	await check_watch("[%s] %s, cold" % [loc, tab], COLD_BUDGET, 6)
	await card_fits_while_settling("[%s] the Wardrobe" % loc)
	await names_readable("[%s] %s" % [loc, tab])
	await pictures_ready("[%s] %s, cold (pictures)" % [loc, tab], COLD_BUDGET + 2.0, 0, -1, -1, false)
	var tabs: Array = wardrobe_card().find_children("*", "Button", true, false).filter(func(b): return b.has_meta("wear_cat"))
	check(tabs.all(func(b): return b.get_global_rect().size.y >= MIN_TOUCH and area.grow(0.5).encloses(b.get_global_rect())), "[%s] every tab is touch-safe and inside the safe area" % loc)
	check(loc == "en" or tabs.all(func(b): return tr(b.get_meta("wear_cat")) != b.get_meta("wear_cat")), "[%s] the tab names are translated" % loc)
	await shot("%s_wardrobe" % loc)
	# Warm: once the tab's pictures (including the row ahead) are made, closed and reopened, the card
	# comes back to the same scroll position and the same rows (checked, not assumed), and shows them from
	# memory, rendering nothing new.
	await until(func(): return thumbs.queued().is_empty() and not thumbs._busy, COLD_BUDGET)
	var sc: ScrollContainer = wardrobe_card().find_child("WardrobeScroll", true, false)
	var cold_scroll: int = sc.scroll_vertical
	var cold_rows: Array = visible_tiles().map(func(b): return b.get_meta("wear_item"))
	var before: int = thumbs.renders
	var cached_before: Array = thumbs.cache.keys()
	await open_wardrobe("Tops" if tab != "Tops" else "Shoes")   # leave the tab, then come back with one tap
	await until(func(): return thumbs.queued().is_empty() and not thumbs._busy, COLD_BUDGET)
	before = thumbs.renders
	cached_before = thumbs.cache.keys()
	watch_pictures()
	await open_wardrobe(tab)
	await check_watch("[%s] %s, warm" % [loc, tab], WARM_BUDGET)
	sc = wardrobe_card().find_child("WardrobeScroll", true, false)
	var warm_rows: Array = visible_tiles().map(func(b): return b.get_meta("wear_item"))
	var card: Node = wardrobe_card()
	var at_settle := visible_tiles().filter(func(b): return (b.find_child("Pic", true, false) as TextureRect).texture == null or thumbs.cache.get(b.get_meta("wear_item")) != (b.find_child("Pic", true, false) as TextureRect).texture)
	check(at_settle.is_empty(), "[%s] %s warm: when the card settles (%.2f s after it was built) every visible tile already shows its own picture (%d missing)" % [loc, tab, (card.get_meta("settled_ms", 0) - card.get_meta("built_ms", 0)) / 1000.0, at_settle.size()])
	check(sc.scroll_vertical == cold_scroll and warm_rows == cold_rows, "[%s] %s reopens at the same place with the same rows (scroll %d vs %d; %s vs %s)" % [loc, tab, sc.scroll_vertical, cold_scroll, warm_rows, cold_rows])
	await pictures_ready("[%s] %s, warm (pictures)" % [loc, tab], WARM_BUDGET + 2.0, 0, -1, -1, false)
	check(thumbs.renders == before, "[%s] reopening %s renders nothing new (%d: %s)" % [loc, tab, thumbs.renders - before, thumbs.cache.keys().filter(func(k): return not cached_before.has(k))])
	# The language changes while the card is open: it refits to the new text.
	var other: String = "ja" if loc != "ja" else "de"
	I18n.set_locale(other)
	await card_fits_while_settling("[%s -> %s, card open] the Wardrobe" % [loc, other])
	I18n.set_locale(loc)
	await card_fits_while_settling("[%s, back] the Wardrobe" % loc)
	await close_dialogs()


## Fast tab changes and scrolling never leave a wrong or stale picture; memory stays bounded and the
## render viewport is let go after closing.
func _pictures_fast(hud: Control) -> void:
	var thumbs: Node = hud.wardrobe_thumbs()
	await open_wardrobe("Tops")
	thumbs.forget(W.ids_in("Bottoms"))   # the tab the quick taps end on is cold
	watch_pictures()
	for cat in ["Shoes", "Socks", "Bottoms"]:   # three taps in quick succession
		var t := find_button(wardrobe_card(), "wear_cat", cat)
		if t:
			_taps.append(Time.get_ticks_msec())
			await tap(t.get_global_rect().get_center())
			await frames(1)
	check(await until(func(): return hud._wardrobe_cat == "Bottoms" and wardrobe_card() != null, 3.0), "after quick taps the last tab is open")
	await frames(3)
	await check_watch("Bottoms after quick tab changes, cold", COLD_BUDGET, 6)
	await pictures_ready("Bottoms after quick tab changes (pictures)", COLD_BUDGET + 2.0, 0, -1, -1, false)
	var bottoms: Array = W.ids_in("Bottoms")
	check(thumbs.queued().all(func(id): return bottoms.has(id)), "nothing from the tabs passed over is still queued")
	# Real wheel scrolling to the end of the list: the rows that come into view get their pictures.
	var scroll: ScrollContainer = wardrobe_card().find_child("WardrobeScroll", true, false)
	var at := scroll.get_global_rect().get_center()
	var renders_before: int = thumbs.renders
	var scroll_ms := Time.get_ticks_msec()
	for i in 40:
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = pressed
			e.position = get_viewport().get_final_transform() * at
			e.global_position = e.position
			Input.parse_input_event(e)
		await frames(1)
	await frames(4)
	check(scroll.scroll_vertical > 0, "the list scrolled (%d px)" % scroll.scroll_vertical)
	await pictures_ready("Bottoms after scrolling to the end (timed from the scroll)", COLD_BUDGET, -1, scroll_ms, renders_before)
	check(thumbs.renders - renders_before <= bottoms.size(), "scrolling renders only rows that came into view (%d of %d)" % [thumbs.renders - renders_before, bottoms.size()])
	check(thumbs.cache.size() <= thumbs.CACHE_MAX, "pictures in memory stay within %d (%d)" % [thumbs.CACHE_MAX, thumbs.cache.size()])
	check(thumbs.viewports_alive() <= 1, "at most one render viewport")
	await close_dialogs()
	check(await until(func(): return thumbs.viewports_alive() == 0, thumbs.IDLE_FREE + 2.0), "the render viewport is let go after the Wardrobe closes")
	check(thumbs.queued().is_empty(), "closing the Wardrobe empties the picture queue")

