## Shared color palettes. Pure data so the server and tests can use it.
extends RefCounted

## Paint swatches players can apply to paintable items. Index is stored in saves.
const PAINT := [
	{"name": "Cream", "color": Color("#f3ead8")},
	{"name": "Sunny", "color": Color("#f2cf6b")},
	{"name": "Peach", "color": Color("#f4ad8a")},
	{"name": "Rose", "color": Color("#ec8fa3")},
	{"name": "Sky", "color": Color("#86c3e6")},
	{"name": "Leaf", "color": Color("#95c97f")},
	{"name": "Lilac", "color": Color("#b7a2e0")},
	{"name": "Cocoa", "color": Color("#a87a5c")},
]

const SKIN := [Color("#fbe0cc"), Color("#f2c7a5"), Color("#d9a27c"), Color("#a8734f"), Color("#6f4a33")]
const HAIR := [Color("#3a2a22"), Color("#6b4128"), Color("#c98a4b"), Color("#e8c57a"), Color("#2c2c3a"), Color("#c45a3c")]

# Fixed scene colors (UI design values come from docs/design-spec.md).
const GRASS := Color("#a9d27f")
const GRASS_DARK := Color("#86b866")
const PATH := Color("#eadbb8")
const WOOD := Color("#d9a466")
const WOOD_DARK := Color("#a8714a")
const WATER := Color("#6cc9d2")
const STONE := Color("#cfc8bb")
const PLASTER := Color("#fbf3e3")


static func paint(index: int) -> Color:
	return PAINT[clampi(index, 0, PAINT.size() - 1)]["color"]
