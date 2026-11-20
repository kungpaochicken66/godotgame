## Headless tests for the first-steps guide's state (core/first_steps.gd).
##   godot --headless --path game -s res://tests/first_steps_tests.gd
## The line on screen, its place and its texts in six languages are in first_steps_tour.gd.
extends "res://tests/puzzle_ride_tests.gd"

const FirstSteps := preload("res://scripts/core/first_steps.gd")


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	await process_frame   # the tree is running before anything is asked of the autoloads
	_current = "test_first_steps"
	test_first_steps()
	_current = "test_guide_make"
	test_guide_make()
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	print("\nFIRST STEPS TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func test_first_steps() -> void:
	var st: Dictionary = FirstSteps.fresh()
	eq(FirstSteps.current(st), "walk", "a new child is first told how to walk")
	ok(not FirstSteps.all_done(st), "nothing is done yet")
	ok(FirstSteps.mark(st, "walk") and not FirstSteps.mark(st, "walk"), "walking counts once")
	eq(FirstSteps.current(st), "build", "then how to build")
	ok(not FirstSteps.mark(st, "fly"), "a step that does not exist changes nothing")
	ok(FirstSteps.mark(st, "guide"), "steps can be done in any order")
	eq(FirstSteps.current(st), "build", "the one still open is shown")
	ok(FirstSteps.mark(st, "build") and FirstSteps.all_done(st) and FirstSteps.current(st) == "", "after the last step nothing is shown")
	var hidden: Dictionary = FirstSteps.fresh()
	hidden["hidden"] = true
	eq(FirstSteps.current(hidden), "", "a child who hid the guide sees nothing")
	ok(FirstSteps.mark(hidden, "walk") and not FirstSteps.all_done(hidden), "what they do is still remembered")
	eq(FirstSteps.sanitize("nonsense"), FirstSteps.fresh(), "a damaged setting is a fresh start")
	eq(FirstSteps.initial(false), FirstSteps.fresh(), "a device with nothing stored and nothing built is a beginner's")
	ok(FirstSteps.all_done(FirstSteps.initial(true)) and FirstSteps.current(FirstSteps.initial(true)) == "", "a child who built here before the guide existed is shown nothing")
	eq(FirstSteps.sanitize({"walk": true, "build": "yes", "extra": 1}), {"walk": true, "build": false, "guide": false, "hidden": false}, "only real yes-or-no entries are kept")
	eq(FirstSteps.line("walk"), "Tap the ground to walk there.", "by touch")
	eq(FirstSteps.line("walk", true), "Move with the left stick.", "with a controller")
	eq([FirstSteps.line("build"), FirstSteps.line("build", false, true)], ["Open Decorate to build something.", "Pick a thing, then choose Place here."], "before and after the toy box is open")
	eq(FirstSteps.line("guide", true), "Open Activities for ideas to play.", "the same by touch and controller")
	var UIK = load("res://scripts/ui/ui_kit.gd")
	for s in FirstSteps.STEPS:
		ok(UIK.ICONS.has(FirstSteps.icon(s)), "the %s step's icon exists" % s)
	for code in ["zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing := []
		for text in [FirstSteps.line("walk"), FirstSteps.line("walk", true), FirstSteps.line("build"), FirstSteps.line("build", false, true), FirstSteps.line("guide"), FirstSteps.PRAISE, "Hide"]:
			if not cat.has(text) or str(cat[text]) == "" or str(cat[text]) == text:
				missing.append(text)
		eq(missing, [], "[%s] every first-steps line is translated" % code)
		# Each line names the button as that language shows it.
		ok(str(cat[FirstSteps.line("build")]).contains(str(cat["Decorate"])) and str(cat[FirstSteps.line("guide")]).contains(str(cat["Activities"])) and str(cat[FirstSteps.line("build", false, true)]).contains(str(cat["Place here"])),
			"[%s] the lines use the buttons' own names (%s, %s, %s)" % [code, cat["Decorate"], cat["Activities"], cat["Place here"]])


## The guide's second section (things to build and try): the same care as for the eight activities.
func test_guide_make() -> void:
	var G = load("res://scripts/ui/activity_guide.gd")
	var Art = load("res://scripts/ui/guide_art.gd")
	# The eight activities A-H, then the zoo's card (zoo design, W5), which ends the first section.
	eq(G.ENTRIES.size(), 9, "the eight activities and the zoo")
	eq(G.ENTRIES[8]["id"], "zoo", "the zoo's card comes last")
	eq(G.MAKE.map(func(e): return e["id"]), ["contraptions", "puzzles", "rides", "evening", "board", "hello"], "six things to build and try, in order")
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/en.json"))
	var arts := {}
	for e in G.MAKE:
		for f in ["title", "tagline", "where", "steps", "success", "alone", "friends", "go", "go_label", "art"]:
			ok(e.has(f), "%s has %s" % [e["id"], f])
		ok(e["steps"].size() >= 2 and e["steps"].size() <= 3, "%s has two or three steps" % e["id"])
		ok(Art.MAKE_SCENES.has(e["art"]) and not Art.SCENES.has(e["art"]), "%s has its own picture" % e["id"])
		arts[Art.MAKE_SCENES.get(e["art"], "")] = true
		var tex: Texture2D = Art.texture(e["art"])
		ok(tex != null and tex.get_width() == 320 and tex.get_height() == 220, "%s picture renders (320x220)" % e["id"])
		var go: String = e["go"]
		ok(go == "hello" or go == "landmark:bell" or (go.begins_with("tab:") and RoomThemes.TOOLKITS.has(go.trim_prefix("tab:"))), "%s has a safe next step (%s)" % [e["id"], go])
		eq(G.find(e["id"]), e, "%s is found by its id" % e["id"])
		for l in [e["where"], e["friends"], e.get("extra", "")] + e["steps"]:
			if l is Array:
				eq(l[0].count("%s"), l[1].size(), "placeholders match labels: %s" % l[0].left(30))
				for lab in l[1]:
					ok(en.has(lab), "guide label \"%s\" is a real UI string" % lab)
	eq(arts.size(), 6, "six different pictures")
	# The things a guide entry names are in the toy box tab it opens.
	for pair in [["contraptions", ["push_button", "lamp_post"]], ["puzzles", ["puzzle_chest", "puzzle_key", "puzzle_dial"]], ["rides", ["ride_station", "ride_signal"]], ["board", ["picture_board"]]]:
		var tab: String = G.find(pair[0])["go"].trim_prefix("tab:")
		for kind in pair[1]:
			ok(RoomThemes.extra_for(tab).has(kind), "the %s tab has the %s the guide names" % [tab, kind])
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		eq(G.keys().filter(func(k): return not cat.has(k)), [], "%s has every guide string" % code)
		if code != "en":
			eq(["Things to do", "Things to build", "Things to build and try. Nothing is locked."].filter(func(k): return str(cat.get(k, k)) == k), [], "[%s] the two sections are named in this language" % code)
