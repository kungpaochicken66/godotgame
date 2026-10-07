## Places landmark name tags on screen without overlaps (pure, unit-tested).
##
## Each candidate wants its tag centered just above its anchor point. Tags never
## overlap each other or the blocked bands (top bar, bottom controls), stay inside
## the safe area, and at most `limit` are shown, nearest first. A tag that does not
## fit above its landmark tries just below the landmark's foot (for landmarks right
## under the top bar), then one row further, each also nudged a little sideways;
## otherwise it is skipped.
extends RefCounted

const GAP := 6.0


## candidates: [{id, screen: Vector2, size: Vector2, foot: Vector2 (optional)}]
## sorted nearest first. `screen` is the top of the landmark, `foot` its base.
## Returns [{id, rect: Rect2}].
static func place(candidates: Array, area: Rect2, blocked: Array, limit := 3) -> Array:
	var placed := []
	for c in candidates:
		if placed.size() >= limit:
			break
		var size: Vector2 = c["size"]
		var top: Vector2 = c["screen"]
		var foot: Vector2 = c.get("foot", top)
		var row := size.y + GAP
		var spots := [
			Vector2(top.x, top.y - size.y - 10.0), Vector2(foot.x, foot.y + 8.0),
			Vector2(top.x, top.y - size.y - 10.0 - row), Vector2(foot.x, foot.y + 8.0 + row),
			Vector2(foot.x, foot.y + 8.0 + row * 2.0),
		]
		var found := false
		for spot in spots:
			for dx in [0.0, -size.x * 0.6, size.x * 0.6]:
				var r := Rect2(spot + Vector2(dx - size.x * 0.5, 0), size)
				r.position.x = clampf(r.position.x, area.position.x + 8.0, area.end.x - size.x - 8.0)
				if area.encloses(r) and not _clashes(r, blocked, placed):
					placed.append({"id": c["id"], "rect": r})
					found = true
					break
			if found:
				break
	return placed


static func _clashes(r: Rect2, blocked: Array, placed: Array) -> bool:
	for b in blocked:
		if r.intersects(b):
			return true
	for p in placed:
		if r.grow(GAP).intersects(p["rect"]):
			return true
	return false
