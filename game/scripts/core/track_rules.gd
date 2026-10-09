## Toy tracks (design/playability-8-12.md F02): flat pieces on 1 m cells that a
## ball rolls along. Pure rules, unit-tested; the authority runs a ball and
## every device draws it. Nothing breaks: at a gap the ball waits and an arrow
## shows where a piece is missing.
##
## Ports are quarter turns q of the piece's own facing: the world direction of
## port q is TownModel.facing(rot + 2 * q); q 0 = front, 1 = local +x side,
## 2 = back, 3 = local -x side (the same as the built models in props_play.gd).
extends RefCounted

const TownModel := preload("res://scripts/core/town_model.gd")

const KINDS := ["track_start", "track_straight", "track_curve", "track_switch", "track_bell", "track_finish", "track_light"]
## Ports each piece connects. A switch's back leads to its front (variant 0) or
## its side (variant 1); the finish catches the ball from any side.
const PORTS := {"track_start": [0], "track_straight": [0, 2], "track_bell": [0, 2], "track_light": [0, 2], "track_curve": [2, 1],
	"track_switch": [2, 0, 1], "track_finish": [0, 1, 2, 3]}
## The longest route followed (a loop ends here).
const MAX_STEPS := 48
## Seconds the drawn ball takes per cell.
const CELL_SECONDS := 0.35


static func is_track(kind: String) -> bool:
	return KINDS.has(kind)


static func cell_of(item: Dictionary) -> Vector2i:
	return Vector2i(roundi(item["x"]), roundi(item["z"]))


static func dir_of(rot: int, q: int) -> Vector2i:
	var f := TownModel.facing(rot + 2 * q)
	return Vector2i(roundi(f.x), roundi(f.y))


## Which port of this piece faces world direction d (or -1).
static func port_facing(item: Dictionary, d: Vector2i) -> int:
	for q in 4:
		if dir_of(item["rot"], q) == d:
			return q
	return -1


## Where the ball leaves a piece it entered through port q_in (or -1: it stops here).
static func exit_port(item: Dictionary, q_in: int) -> int:
	match item["kind"]:
		"track_straight", "track_bell", "track_light":
			return 2 if q_in == 0 else 0
		"track_curve":
			return 1 if q_in == 2 else 2
		"track_switch":
			if q_in == 2:
				return 0 if int(item.get("variant", 0)) % 2 == 0 else 1
			return 2
	return -1


## The ball's route from a start piece:
## {"cells": [Vector2 centers in order], "end": "finish" | "gap" | "wrong_way" | "loop" (back at the start or too long),
##  "at": Vector2 (the missing or blocking cell), "bells": [bell and light piece ids passed, in order], "finish": id}
static func route(model, start_id: String) -> Dictionary:
	var start: Dictionary = model.items.get(start_id, {})
	var out := {"cells": [], "end": "gap", "at": Vector2.ZERO, "bells": [], "finish": ""}
	if start.is_empty() or start["kind"] != "track_start" or start["space"] != "town":
		return out
	var grid := {}
	for it in model.items_in("town"):
		if is_track(it["kind"]) and not it.has("gift"):
			grid[cell_of(it)] = it
	var cell := cell_of(start)
	var d := dir_of(start["rot"], 0)
	out["cells"].append(Vector2(cell))
	for i in MAX_STEPS:
		cell += d
		var piece: Dictionary = grid.get(cell, {})
		if not piece.is_empty() and piece["id"] == start_id:
			out["cells"].append(Vector2(cell))
			out["end"] = "loop"   # back home: a loop
			return out
		if piece.is_empty() or piece["kind"] == "track_start":
			out["end"] = "gap"
			out["at"] = Vector2(cell)
			return out
		var q_in := port_facing(piece, -d)
		if not PORTS[piece["kind"]].has(q_in):
			out["end"] = "wrong_way"
			out["at"] = Vector2(cell)
			return out
		out["cells"].append(Vector2(cell))
		if piece["kind"] in ["track_bell", "track_light"]:
			out["bells"].append(piece["id"])   # bells ring and lights light up as the ball passes
		if piece["kind"] == "track_finish":
			out["end"] = "finish"
			out["finish"] = piece["id"]
			return out
		var q_out := exit_port(piece, q_in)
		if q_out < 0:
			out["end"] = "gap"
			out["at"] = Vector2(cell)
			return out
		d = dir_of(piece["rot"], q_out)
	out["end"] = "loop"
	return out
