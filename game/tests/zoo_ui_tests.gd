## Headless tests for the zoo's guide card, its illustration, the zoo photo ideas and the rows of the
## scrapbook page "Zoo friends" (pure helpers; the HUD only draws them).
##   scripts/godot.sh --headless --path game -s res://tests/zoo_ui_tests.gd
extends SceneTree

const Guide := preload("res://scripts/ui/activity_guide.gd")
const Art := preload("res://scripts/ui/guide_art.gd")
const PhotoIdeas := preload("res://scripts/core/photo_ideas.gd")
const ZooLife := preload("res://scripts/core/zoo_life.gd")

var _checks := 0
var _failures := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", what)


func eq(a, b, what: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		print("FAIL: %s (got %s, want %s)" % [what, str(a), str(b)])


func _initialize() -> void:
	test_guide_entry()
	test_art()
	test_photo_ideas()
	test_scrapbook_rows()
	test_strings()
	print("\nZOO UI TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func test_guide_entry() -> void:
	var e: Dictionary = Guide.find("zoo")
	ok(not e.is_empty(), "the guide has a zoo entry")
	eq(Guide.ENTRIES.back()["id"], "zoo", "the zoo card is the last of the nine")
	for f in ["title", "tagline", "where", "steps", "success", "alone", "friends", "go", "go_label", "art"]:
		ok(e.has(f), "zoo has %s" % f)
	eq(e["title"], "The zoo", "title")
	eq(e["art"], "zoo", "art")
	eq(e["go"], "zoo", "go")
	eq(e["go_label"], "Go there", "go label")
	ok(e["steps"].size() >= 2, "at least two steps")
	var text: String = JSON.stringify(e)
	ok(text.contains("Ride home"), "the card names Ride home")
	ok(text.contains("tram stop") and text.contains("answer"), "the card describes the tram stop and the answers")
	for l in [e["where"]] + e["steps"]:
		if l is Array:
			eq(l[0].count("%s"), l[1].size(), "placeholders match labels: %s" % l[0].left(30))


func test_art() -> void:
	var tex: Texture2D = Art.texture("zoo")
	ok(tex != null and tex.get_width() == 320 and tex.get_height() == 220, "the zoo illustration renders 320x220")
	ok(Art.SCENES.has("zoo"), "the zoo scene is in SCENES")
	var seen := {}
	for k in Art.SCENES:
		seen[Art.SCENES[k]] = true
	eq(seen.size(), Art.SCENES.size(), "every scene is different")


func test_photo_ideas() -> void:
	var zoo_ids := PhotoIdeas.ZOO_IDEAS.map(func(i): return i["id"])
	eq(zoo_ids.size(), 4, "four zoo photo ideas")
	for id in zoo_ids:
		ok(PhotoIdeas.text_of(id) != "", "%s has text" % id)
	var base := {"space": "zoo", "kids": 0, "zoo_animals": []}
	eq(PhotoIdeas.evaluate(base), [], "an empty zoo photo matches nothing")
	var f := base.duplicate()
	f["zoo_animals"] = ["lioness"]
	eq(PhotoIdeas.evaluate(f), ["zoo_big_cat"], "a lioness is a big cat")
	f["zoo_animals"] = ["monkey", "monkey"]
	eq(PhotoIdeas.evaluate(f), ["zoo_monkeys"], "two monkeys")
	f["zoo_animals"] = ["monkey"]
	eq(PhotoIdeas.evaluate(f), [], "one monkey is not two")
	f["zoo_animals"] = ["giraffe"]
	f["kids"] = 1
	eq(PhotoIdeas.evaluate(f), ["zoo_friend"], "a child and a giraffe")
	f["zoo_animals"] = ["otter"]
	f["kids"] = 0
	eq(PhotoIdeas.evaluate(f), ["zoo_splash"], "an otter")
	f["zoo_animals"] = ["hippo", "tiger", "monkey", "monkey"]
	f["kids"] = 2
	var all: Array = PhotoIdeas.evaluate(f)
	for id in zoo_ids:
		ok(all.has(id), "%s on matching facts" % id)
	# The same facts in town, or in a room, never match a zoo idea.
	for space in ["town", "town:f0:r0"]:
		var t := f.duplicate()
		t["space"] = space
		for id in PhotoIdeas.evaluate(t):
			ok(not zoo_ids.has(id), "%s does not match in %s" % [id, space])
	var town := {"space": "town", "evening": false, "weather": "sunny", "kids": 2, "animals": ["pig", "dog", "sheep"], "kinds": ["pond"]}
	for id in PhotoIdeas.evaluate(town):
		ok(not zoo_ids.has(id), "town facts give no zoo idea (%s)" % id)
	eq(PhotoIdeas.IDEAS.size(), 8, "the town board still has eight ideas")
	# "A cozy room" is for a cottage room: the zoo with many toys is not one.
	var zt := {"space": "zoo", "evening": false, "weather": "sunny", "kids": 0, "animals": [], "kinds": [], "room_items": 9, "zoo_animals": []}
	ok(not PhotoIdeas.evaluate(zt).has("cozy_room"), "the zoo full of toys is not a cozy room")
	var rt := zt.duplicate()
	rt["space"] = "i3:0:0"
	ok(PhotoIdeas.evaluate(rt).has("cozy_room"), "a cottage room with nine things is")


func test_scrapbook_rows() -> void:
	var rows: Array = Guide.zoo_friend_rows({})
	eq(rows.size(), ZooLife.ANSWERS.size(), "one row per species")
	for r in rows:
		ok(r["found"].is_empty(), "%s: nothing found" % r["species"])
		var first_answer: String = ZooLife.ANSWERS[r["species"]].keys()[0]
		eq(r["hint"], ZooLife.ANSWERS[r["species"]][first_answer], "%s: the first hint shows" % r["species"])
		ok(not r["names"].is_empty(), "%s has animal names" % r["species"])
	eq(rows[0]["names"], ["Rory"], "the lion is Rory")
	var found := {"lion": {"roar": {"by": ["Ann", "Bo"], "t": 5}, "treat": {"by": ["Cy"], "t": 6}}}
	rows = Guide.zoo_friend_rows(found)
	var lion: Dictionary = rows[0]
	eq(lion["found"].map(func(x): return x["answer"]), ["roar", "treat"], "found answers in ANSWERS order")
	eq(lion["found"][0]["by"], ["Ann", "Bo"], "the names of those who found it")
	eq(lion["hint"], ZooLife.ANSWERS["lion"]["pace"], "the hint is the first answer not found yet")
	# Damaged or partial data is ignored, never an error.
	for bad in [null, 5, "x", [], {"lion": 3}, {"lion": {"roar": "x"}}, {"lion": {"roar": {"by": 7}}}]:
		var r2: Array = Guide.zoo_friend_rows(bad)
		eq(r2.size(), ZooLife.ANSWERS.size(), "damaged data still gives every species (%s)" % str(bad))
	var all := {}
	for sp in ZooLife.ANSWERS:
		all[sp] = {}
		for a in ZooLife.ANSWERS[sp]:
			all[sp][a] = {"by": ["Ann"], "t": 1}
	for r in Guide.zoo_friend_rows(all):
		eq(r["hint"], "", "%s: nothing left to hint" % r["species"])
		eq(r["found"].size(), ZooLife.ANSWERS[r["species"]].size(), "%s: every answer listed" % r["species"])


func test_strings() -> void:
	var keys: Array = Guide.keys()
	keys.append_array(["Zoo friends", "Found by %s", "You are already at the zoo.", "A tram to the zoo is waiting."])
	for i in PhotoIdeas.ZOO_IDEAS:
		keys.append(i["text"])
	for code in ["en", "zh-CN", "ja", "es", "fr", "de"]:
		var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/%s.json" % code))
		var missing: Array = keys.filter(func(k): return not cat.has(k))
		eq(missing, [], "%s has every zoo UI string" % code)
		for sp in ZooLife.ANSWERS:
			for a in ZooLife.ANSWERS[sp]:
				var hint: String = ZooLife.ANSWERS[sp][a]
				ok(cat.has(hint), "%s has the hint \"%s\"" % [code, hint])
