## Focused controller-hint regression: actual toy-box tabs and clipping, six locales.
## Independent visible-control oracle; includes disabled buttons such as Undo.
extends "res://tests/contraption_tour.gd"

func _run() -> void:
	pad = main.pad
	tv = TvMode.active()
	get_tree().create_timer(120.0).timeout.connect(func():
		print("HINTTOUR FAIL: timed out")
		Music.quit_game(1))
	if not main.args.has("no-shots"):
		check(await until(func(): return main.thumbs.is_done, 60.0), "item thumbnails are ready")
	Session.start_solo("user://hint_tour_town.json", main.menus.avatar)
	await wait(1.5)
	await close_dialogs()
	var hud: Control = main.hud
	await act(hud._decorate_btn, "Decorate")
	for loc in main.args.get("locales", "en,zh-CN,ja,es,fr,de").split(","):
		I18n.set_locale(loc)
		await frames(3)
		var tab: Button = await scroll_into_view(find_button(hud._tabs, "tab", "Contraptions"))
		await act(tab, "Contraptions")
		await frames(3)
		toybox_hints_clear(loc + " immediate")
		await wait(0.6)
		toybox_hints_clear(loc + " settled")
		await shot("hints_" + loc)
		var scroll: ScrollContainer = hud._card_scroll
		scroll.scroll_horizontal = int(scroll.get_h_scroll_bar().max_value)
		await frames(3)
		toybox_hints_clear(loc + " scrolled immediate")
		await wait(0.6)
		toybox_hints_clear(loc + " scrolled settled")
		# Reset the category through its real button before the next language.
		await act(await scroll_into_view(find_button(hud._tabs, "tab", "All")), "All")
		await wait(0.3)
		toybox_hints_clear(loc + " All tab")
		var started := Time.get_ticks_usec()
		for sample in 20:
			pad._place_hints()
		print("HINTPERF %s All tab: %.3f ms/placement" % [loc, float(Time.get_ticks_usec() - started) / 20000.0])
	var blocker := Button.new()
	blocker.text = "Undo"
	blocker.disabled = true
	var original: Rect2 = pad.hint_rect()
	blocker.position = main.hud.get_global_transform().affine_inverse() * original.position
	blocker.size = original.size
	main.hud.add_child(blocker)
	await frames(3)
	check(not blocker.get_global_rect().intersects(pad.hint_rect()), "hints move off a newly visible disabled button without waiting for a timer")
	blocker.queue_free()
	await frames(3)
	check(_real_mouse == 0, "no outside pointer input (%d; %s)" % [_real_mouse, _real_mouse_first])
	print("HINTTOUR %s: %d failures, %d checks, %d screenshots" % ["PASS" if failures == 0 else "FAIL", failures, _checks, _n])
	Music.quit_game(1 if failures else 0)
