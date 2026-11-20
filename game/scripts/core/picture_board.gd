## The picture board (design/town-evenings-and-more.md): an 8 x 8 picture in the eight
## paint colors that everyone in town can add to. The picture lives in the board's item
## as a 64-character string, one digit per square: "0" is empty, "1" to "8" are the paint
## colors (palette index + 1). It is saved with the town like a music box's tune.
##
## Pure rules, unit-tested; the authority sets one square at a time, so two children
## painting at once never lose each other's squares.
extends RefCounted

const Palette := preload("res://scripts/core/palette.gd")

const KIND := "picture_board"
const SIDE := 8
const CELLS := 64
## Painting needs the child this close (as for a music box's tune).
const REACH := 2.6

const ERR_NOT_HERE := "That picture board is not here."
const ERR_WALK := "Walk to the picture board to paint."
const ERR_SQUARE := "That square is not on the board."


static func blank() -> String:
	return "0".repeat(CELLS)


## Any value made into a valid picture: 64 digits, each 0 to the number of paint colors.
static func sanitize(v) -> String:
	if typeof(v) != TYPE_STRING or (v as String).length() != CELLS:
		return blank()
	var out := ""
	for i in CELLS:
		var d: int = (v as String).unicode_at(i) - 48
		out += str(d) if d >= 0 and d <= Palette.PAINT.size() else "0"
	return out


## The color of a square: 0 (empty) or 1 to 8.
static func cell(pix: String, index: int) -> int:
	return pix.unicode_at(index) - 48 if index >= 0 and index < pix.length() else 0


static func with_cell(pix: String, index: int, color: int) -> String:
	return pix.substr(0, index) + str(color) + pix.substr(index + 1)


static func valid(index: int, color: int) -> bool:
	return index >= 0 and index < CELLS and color >= 0 and color <= Palette.PAINT.size()


## Can this child paint on this board now? "" or the reason.
static func check(model, id: String, actor_space: String, actor_pos: Vector2) -> String:
	var it: Dictionary = model.items.get(id, {})
	if it.is_empty() or it["kind"] != KIND or it.has("gift"):
		return ERR_NOT_HERE
	if it["space"] != actor_space or Vector2(it["x"], it["z"]).distance_to(actor_pos) > REACH:
		return ERR_WALK
	return ""
