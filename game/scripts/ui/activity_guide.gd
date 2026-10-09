## How-to-play guide for the eight activities (pure data, unit-tested).
##
## Text is English source, translated by the UI. A line is either a string or
## [template, [labels]]: each %s is filled with the translated on-screen label,
## so every language names the buttons exactly as the game shows them.
## The guide never reveals game state such as where the acorn is hidden.
extends RefCounted

## go: "landmark:<id>" walks next to it without using it; "wish" opens the
## current wish card; "decorate" opens Decorate; "garden" opens the toy box at
## the garden bed; "door" walks to the nearest cottage door; "" none.
const ENTRIES := [
	{"id": "wishes", "art": "wishes", "title": "Animal wishes", "tagline": "Help an animal friend make a cozy spot.",
		"where": "Outdoors. An animal with a wish has a bubble over its head.",
		"steps": ["Tap the animal with the bubble to see its wish.",
			["Tap %s. The toy box opens on the %s tab.", ["I'll help!", "Wish"]],
			"Put the pictured things close together outdoors. Things already there count too."],
		"success": "The animal celebrates and a sticker goes in the scrapbook. Sometimes it leaves a present.",
		"alone": "Works alone: new wishes come while you play outdoors.",
		"friends": "Everyone nearby is thanked on the sticker.",
		"go": "wish", "go_label": "Show the wish"},
	{"id": "acorn", "art": "acorn", "title": "Golden acorn", "tagline": "Hide-and-seek with warm and cold hints.",
		"where": ["At the tree stump on the town square, tap %s.", ["Hide and seek"]],
		"steps": ["Walk around. The dots at the top show how warm you are: more dots, closer.",
			"Up close, the golden acorn appears. After a few minutes it starts to glow as a hint.",
			["Tap %s.", ["Pick up the acorn!"]]],
		"success": "Everyone hears who found it, and the game chip goes away.",
		"alone": "Alone, an animal friend hides the acorn somewhere outdoors for you.",
		"friends": ["With friends, the one who starts hides it: walk anywhere, even into a house, and tap %s. The others seek.", ["Hide the acorn here"]],
		"extra": ["%s on the game chip ends the round any time.", ["Stop"]],
		"go": "landmark:stump", "go_label": "Go there"},
	{"id": "gifts", "art": "gifts", "title": "Presents", "tagline": "Wrap something with a bow for someone.",
		"where": "In Decorate, on anything already placed.",
		"steps": [["Tap %s, then tap something placed.", ["Decorate"]],
			["Tap %s and choose %s or a friend.", ["Gift", "For anyone"]],
			["Tap %s, walk to a present and tap %s.", ["Done", "Open the present"]]],
		"success": "The bow comes off and the thing is back, ready to use.",
		"alone": "Alone, wrap things for anyone. Animal friends sometimes leave presents too.",
		"friends": "A present for a friend waits in this town until they open it. Each friend can have 3 waiting.",
		"go": "decorate", "go_label": "Start decorating"},
	{"id": "garden", "art": "garden", "title": "Little gardens", "tagline": "Water a garden bed until it blooms.",
		"where": ["Outdoors. The %s is in the toy box, on the %s tab.", ["Garden bed", "Nature"]],
		"steps": [["Tap %s and place a %s outdoors.", ["Decorate", "Garden bed"]],
			["Tap %s, stand next to the bed and tap %s.", ["Done", "Water"]],
			"Wait a moment and water again: seeds, sprouts, buds, then flowers."],
		"success": "After three waterings it blooms. It also grows slowly while you play outdoors, and it never wilts.",
		"alone": "Works alone.",
		"friends": "Friends can water the same bed.",
		"go": "garden", "go_label": "Find a garden bed"},
	{"id": "party", "art": "party", "title": "Dance party", "tagline": "Thirty seconds of music, lanterns and dancing.",
		"where": ["At the drum on the town square, tap %s.", ["Party!"]],
		"steps": ["The music speeds up, the animals parade around the tree and the lanterns twinkle.",
			["Tap %s at the bottom left to dance along.", ["Dance"]]],
		"success": "A party chip shows at the top while it lasts. It ends by itself after 30 seconds.",
		"alone": "Works alone.",
		"friends": "Everyone in town joins the same party.",
		"extra": ["%s on the chip ends it early.", ["Stop"]],
		"go": "landmark:drum", "go_label": "Go there"},
	{"id": "visits", "art": "visits", "title": "House visits", "tagline": "Leave hearts in rooms and sign the guest book.",
		"where": ["Inside any house: walk to a door and tap %s.", ["Go inside"]],
		"steps": ["Tap the heart button on the right to leave a heart in a room you like. Tap it again to take it back.",
			["In the living room, stand by the guest book and tap %s.", ["Guest book"]]],
		"success": "The heart button fills in, and the guest book lists who visited.",
		"alone": "Works alone in any house.",
		"friends": "Friends' hearts and visits show too. There are no scores.",
		"go": "door", "go_label": "Go to a door"},
	{"id": "photos", "art": "photos", "title": "Photo ideas", "tagline": "Take photos that match the ideas on the board.",
		"where": ["At the board on the town square, tap %s to see the ideas.", ["Photo ideas"]],
		"steps": ["Pick an idea, like an animal by the pond.",
			"Set up the scene so it is on screen, then tap the camera at the top."],
		"success": "When a photo matches, a message names the idea and the board gets a check mark.",
		"alone": "Works alone.",
		"friends": "Some ideas need friends in the photo.",
		"extra": "Every photo is saved in the scrapbook. Only matching photos check off an idea.",
		"go": "landmark:board", "go_label": "Go there"},
	{"id": "weather", "art": "weather", "title": "Weather", "tagline": "Sunny, rain, autumn or snow.",
		"where": ["At the weather vane on the town square, tap %s.", ["Change the weather"]],
		"steps": ["Each tap moves to the next weather: sunny, rain, autumn, snow.",
			"When it rains, Pip the pig splashes in the puddles."],
		"success": "The sky, the ground and the air change. Everything can still be placed.",
		"alone": "Works alone.",
		"friends": "Everyone in town sees the same weather.",
		"go": "landmark:vane", "go_label": "Go there"},
]


## A guide line in the current language, with its labels filled in.
static func line(entry_line, translate: Callable) -> String:
	if entry_line is String:
		return translate.call(entry_line)
	var labels: Array = entry_line[1].map(func(l): return translate.call(l))
	return translate.call(entry_line[0]) % labels


## Every English key the guide uses (templates and labels).
static func keys() -> Array:
	var out := []
	var add := func(x):
		if x is String:
			out.append(x)
		else:
			out.append(x[0])
			out.append_array(x[1])
	for e in ENTRIES:
		for f in ["title", "tagline", "where", "success", "alone", "friends", "go_label"]:
			add.call(e[f])
		if e.has("extra"):
			add.call(e["extra"])
		for s in e["steps"]:
			add.call(s)
	return out


static func find(id: String) -> Dictionary:
	for e in ENTRIES:
		if e["id"] == id:
			return e
	return {}
