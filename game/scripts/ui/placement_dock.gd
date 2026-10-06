## Decides where the placement tools sit so they never cover the item being
## placed. Pure screen-space logic, unit-tested in tests/run_tests.gd.
##
## "bottom" is the normal place (tools above the toy box). When the item's
## screen footprint overlaps that zone, the tools move to the "top" zone under
## the top bar and the toy box tucks away. Switching needs a clear improvement,
## and returning needs a margin of clearance, so a finger dragging along the
## boundary does not make the menu jump back and forth.
extends RefCounted

const HYSTERESIS := 48.0
## Switch only when the other zone covers clearly less of the item.
const IMPROVEMENT := 0.6


static func overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.get_area() if a.intersects(b) else 0.0


## current: "bottom" or "top". Zones are the nominal rectangles the menus
## occupy in each placement, in the same screen space as the ghost rectangle.
static func choose(current: String, ghost: Rect2, bottom_zone: Rect2, top_zone: Rect2) -> String:
	var here := bottom_zone if current == "bottom" else top_zone
	var there := top_zone if current == "bottom" else bottom_zone
	var cost_here := overlap(ghost, here)
	var cost_there := overlap(ghost, there)
	if cost_here > 0.0 and cost_there < cost_here * IMPROVEMENT:
		return "top" if current == "bottom" else "bottom"
	# Back to the usual place once the item is clearly away from it.
	if current == "top" and not ghost.grow(HYSTERESIS).intersects(bottom_zone) and cost_here == 0.0:
		return "bottom"
	return current


## Screen rectangle covering an item's footprint and height as seen by the camera.
static func ghost_rect(camera: Camera3D, center: Vector3, radius: float, height: float) -> Rect2:
	var r := Rect2()
	var first := true
	for i in 8:
		var a := TAU * i / 8.0
		for h in [0.0, height]:
			var p := center + Vector3(cos(a) * radius, h, sin(a) * radius)
			if camera.is_position_behind(p):
				continue
			var s := camera.unproject_position(p)
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
	return r.grow(10.0)
