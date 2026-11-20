## How-to-play guide for the nine activities (pure data, unit-tested).
##
## Text is English source, translated by the UI. A line is either a string or
## [template, [labels]]: each %s is filled with the translated on-screen label,
## so every language names the buttons exactly as the game shows them.
## The guide never reveals game state such as where the acorn is hidden.
extends RefCounted

const ZooLife := preload("res://scripts/core/zoo_life.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")

## go: "landmark:<id>" walks next to it without using it; "wish" opens the
## current wish card; "decorate" opens Decorate; "garden" opens the toy box at
## the garden bed; "door" walks to the nearest cottage door; "zoo" rides the tram to the zoo; "" none.
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
	{"id": "zoo", "art": "zoo", "title": "The zoo", "tagline": "Ride the tram and meet the animals.",
		"where": ["At the tram stop near where you arrive in town. Its tag says %s.", ["Zoo tram"]],
		"steps": ["Walk to the tram stop and tap the tram to ride to the zoo.",
			"Stand near an animal, cheer or dance, and see how it answers.",
			["When you want to go back, tap %s.", ["Ride home"]]],
		"success": "The animals answer you, and new answers go into the scrapbook.",
		"alone": "Works alone.",
		"friends": "Friends ride along and meet the animals with you.",
		"go": "zoo", "go_label": "Go there"},
]


## Things to build and try (design/experience-plan.md, issue 10): the newer play, which a child
## would otherwise find only by opening the right toy box tab. Same shape as ENTRIES; shown under
## the eight activities. go: "tab:<toy box tab>" opens Decorate on that tab; "hello" opens Leave a
## hello; "landmark:bell" walks to the evening bell.
const MAKE := [
	{"id": "contraptions", "art": "contraptions", "title": "Contraptions", "tagline": "Things that set other things off.",
		"where": ["In Decorate, on the %s tab.", ["Contraptions"]],
		"steps": [["Put a %s next to a %s.", ["Big button", "Lamp post"]],
			["Tap %s, stand by the button and tap %s.", ["Done", "Press"]],
			"Put more things within two steps: each one passes the spark on."],
		"success": "Lamps switch on, a music box plays, a pinwheel spins, one after another.",
		"alone": "Works alone.",
		"friends": "Friends see the same chain and can press too.",
		"go": "tab:Contraptions", "go_label": "Open the toy box"},
	{"id": "puzzles", "art": "puzzles", "title": "Puzzle rooms", "tagline": "Hide a key and a clue for a friend.",
		"where": ["In Decorate, on the %s tab.", ["Puzzles"]],
		"steps": [["Place a %s, a %s, a %s and a clue card.", ["Treasure chest", "Puzzle key", "Picture dial"]],
			"Paint the dial and the clue card the same color. Hide the key and the card.",
			["A friend picks up the key, turns the dial to the card's picture and taps %s.", ["Open the chest"]]],
		"success": "The chest opens, and lamps next to it light up.",
		"alone": "Alone, try your own puzzle to see that it works.",
		"friends": ["Everyone in the room solves it together. Anyone can tap %s.", ["Start again"]],
		"go": "tab:Puzzles", "go_label": "Open the toy box"},
	{"id": "rides", "art": "rides", "title": "Cart rides", "tagline": "Lay rails in a ring and ride round.",
		"where": ["Outdoors. In Decorate, on the %s tab.", ["Rides"]],
		"steps": [["Place a %s, then rails from its front round to its back.", ["Cart station"]],
			["Tap %s, stand by the cart and tap %s, then %s.", ["Done", "Get in the cart", "Go!"]],
			["%s stops the cart. %s is always beside it.", ["Stop", "Get off"]]],
		"success": "Three times round, then the cart waits at its station.",
		"alone": "Works alone.",
		"friends": "One child rides at a time. An animal friend can ride in the trailer.",
		"extra": ["A %s sets off the things beside it as the cart goes by.", ["Signal rail"]],
		"go": "tab:Rides", "go_label": "Open the toy box"},
	{"id": "evening", "art": "evening", "title": "Evening lamps", "tagline": "Light the lamps when evening comes.",
		"where": ["Outdoors, at any %s.", ["Lamp post"]],
		"steps": [["Stand by a lamp post and tap %s.", ["Light the lamp"]],
			["Ring the bell on the town square for %s.", ["Evening"]],
			"Light every lamp post in town."],
		"success": "Fireflies come out around every lamp.",
		"alone": "Works alone.",
		"friends": "Friends can each light some of the lamps.",
		"go": "landmark:bell", "go_label": "Go there"},
	{"id": "board", "art": "board", "title": "Picture board", "tagline": "Paint a picture together, square by square.",
		"where": ["In Decorate, on the %s tab.", ["Puzzles"]],
		"steps": [["Place a %s.", ["Picture board"]],
			["Tap %s, stand by it and tap %s.", ["Done", "Paint a picture"]],
			"Pick a color and tap squares."],
		"success": "The board in town shows your picture.",
		"alone": "Works alone.",
		"friends": "Friends add to the same picture.",
		"go": "tab:Puzzles", "go_label": "Open the toy box"},
	{"id": "hello", "art": "hello", "title": "A hello for friends", "tagline": "Leave three emotes for a friend who is away.",
		"where": ["Tap %s on the left.", ["Hello"]],
		"steps": ["Pick three emotes.",
			["Tap %s. A see-through copy of you stays there.", ["Leave it here"]],
			"A friend who comes by can answer with one emote."],
		"success": "Next time, your hello's card shows who answered.",
		"alone": "Alone, your hello waits for friends to visit.",
		"friends": "It stays seven days. You can take it away any time.",
		"go": "hello", "go_label": "Leave a hello"},
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
	for e in ENTRIES + MAKE:
		for f in ["title", "tagline", "where", "success", "alone", "friends", "go_label"]:
			add.call(e[f])
		if e.has("extra"):
			add.call(e["extra"])
		for s in e["steps"]:
			add.call(s)
	return out


static func find(id: String) -> Dictionary:
	for e in ENTRIES + MAKE:
		if e["id"] == id:
			return e
	return {}


## The rows of the scrapbook page "Zoo friends" (pure; the HUD draws them). `found` is
## model.maps["zoo"]["found"]: {species: {answer: {"by": [nicknames], "t": int}}}, read with guards.
## One row per species in ZooLife.ANSWERS order: {"species", "names" (its animals' names),
## "found": [{"answer", "text" (its hint line), "by"}] in ANSWERS order, "hint" (the first answer not seen yet, or "")}.
## No counts and no scores: the page only names what was found and hints at one more.
static func zoo_friend_rows(found) -> Array:
	var rows := []
	var seen: Dictionary = found if found is Dictionary else {}
	for species in ZooLife.ANSWERS:
		var names := []
		for id in ZooMap.ORDER:
			var r: Dictionary = ZooMap.RESIDENTS.get(id, {})
			if r.get("species", "") == species:
				names.append(str(r.get("name", "")))
		var mine = seen.get(species, {})
		var got := []
		var hint := ""
		for answer in ZooLife.ANSWERS[species]:
			var e = mine.get(answer, null) if mine is Dictionary else null
			if e is Dictionary:
				var by := []
				var raw = e.get("by", [])
				if raw is Array:
					for n in raw:
						by.append(str(n))
				got.append({"answer": answer, "text": str(ZooLife.ANSWERS[species][answer]), "by": by})
			elif hint == "":
				hint = str(ZooLife.ANSWERS[species][answer])
		rows.append({"species": species, "names": names, "found": got, "hint": hint})
	return rows
