## TEST FIXTURE ONLY: a deterministic, generated large catalog for toy box
## query and UI responsiveness tests. These entries are not models, are never
## added to the game catalog and must not be presented as accepted assets.
extends RefCounted

const WORDS := ["Lantern", "Chair", "Table", "Clock", "Shelf", "Rug", "Lamp", "Bench", "Vase", "Café sign",
	"Teapot", "Frame", "Mobile", "Stool", "Basket", "Mirror", "Plant", "Bed", "Desk", "Drum"]
const SHAPES := ["round", "tall", "tiny", "striped", "blue", "old", "cozy", "folding"]


## n entries named "Fixture <shape> <word> <i>", spread over anchors, sizes,
## seats and table surfaces; same input, same output.
static func build(n := 2000) -> Dictionary:
	var out := {}
	for i in n:
		var word: String = WORDS[i % WORDS.size()]
		var anchor: String = ["ground", "ground", "ground", "wall", "ceiling"][(i * 7) % 5]
		var size: String = ["small", "medium", "large"][(i * 3) % 3]
		var def := {"name": "Fixture %s %s %04d" % [SHAPES[(i / 20) % SHAPES.size()], word, i],
			"category": ["Furniture", "Cozy things"][i % 2], "space": "home", "anchor": anchor,
			"size_class": size, "seats": 1 if word in ["Chair", "Bench", "Stool"] and anchor == "ground" else 0,
			"tabletop_eligible": size == "small" and anchor == "ground", "radius": 0.3, "color": -1}
		if word in ["Table", "Desk"] and anchor == "ground":
			def["support_surface"] = {"usable_size_xz": Vector2(0.6, 0.6)}
		out["fixture_%04d" % i] = def
	return out
