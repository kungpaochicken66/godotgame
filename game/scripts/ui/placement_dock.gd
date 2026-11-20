## Decides where the placement tools sit so they cover neither the item being
## placed nor the player's own child. Pure screen-space logic, unit-tested in
## tests/run_tests.gd.
##
## Two places: the bottom edge ("low", with the toy box tucked away for as long
## as a thing is held) and under the top bar ("top"). The camera rests the held
## item between the two (camera_rig.gd, hud.gd), so at rest neither place covers
## it; the place is then chosen by where the child stands (choose_place).
##
## History. Until first-steps r5 the lower place was above the toy box, chosen
## by the item alone; that is where the child stands, and the tools lay on the
## child (the Mac's r5 pictures). r6 tried three places and weighed the child
## against the item: the tools hopped twice during one drag and, with the child
## low on the screen, went up onto the item, because the camera rested the item
## under the top place. r7 put the tools at the bottom edge by the item alone:
## a child standing in that strip was hidden (the Mac's r7 pictures). r8: the
## item is rested clear of both places first, and then the child decides.
extends RefCounted

const HYSTERESIS := 48.0
## Switch only when the other zone covers clearly less of the item.
const IMPROVEMENT := 0.6


static func overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.get_area() if a.intersects(b) else 0.0


## current: "bottom" (the lower place, whichever it is) or "top". Zones are the nominal rectangles
## the menus occupy in each placement, in the same screen space as the ghost rectangle.
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


## How near the tools may come to the child before they step away.
const CHILD_GAP := 8.0


## Where the tools go while a thing is held: "low" or "top".
## current: "low" or "top". ghost, child: what the item and the player's own child (name tag
## included) cover on screen; an empty child rectangle means the child is not on screen.
## low_tools, top_tools: what the tools cover at each place. low_strip: the whole strip of the
## screen at the height of the low place; an item dragged anywhere into it sends the tools up (as
## since r5), not only one dragged under the tools themselves.
##
## The item comes first: the tools never stay on it. Where the item allows both places, the tools
## leave the child. With nothing near the bottom edge they return to it.
##
## dragging: a finger is dragging the item (the camera stands still). Then only the item decides,
## with r7's margin for the way back: the child is not weighed until the finger lifts. (Review of the
## r8 draft, D1: with the child under one place and the item wobbling at the other place's edge, "leave
## the item" and "leave the child" undid each other and the tools flipped every 0.3 s.) A margin on the
## child rule at rest would not do: the camera rests the item only FRAME_GAP (24 px) from a place.
static func choose_place(current: String, ghost: Rect2, child: Rect2, low_tools: Rect2, top_tools: Rect2, low_strip: Rect2, dragging := false) -> String:
	var other := "top" if current == "low" else "low"
	# 1. The item, as r5 chose: move when the tools' place covers it and the other clearly less.
	var item_here := overlap(ghost, low_strip if current == "low" else top_tools)
	var item_there := overlap(ghost, top_tools if current == "low" else low_strip)
	if item_here > 0.0 and item_there < item_here * IMPROVEMENT:
		return other
	# 2. The child, where the item is clear of the other place.
	var kid := child.grow(CHILD_GAP) if child.has_area() else Rect2()
	var kid_here := overlap(kid, low_tools if current == "low" else top_tools)
	var kid_there := overlap(kid, top_tools if current == "low" else low_tools)
	if not dragging and item_here == 0.0 and item_there == 0.0 and kid_here > 0.0 and kid_there == 0.0:
		return other
	# 3. Back to the bottom edge once the item and the child are clearly away from it.
	if current == "top" and item_here == 0.0 and kid_here == 0.0 and not ghost.grow(HYSTERESIS).intersects(low_strip) \
			and not (child.has_area() and child.grow(CHILD_GAP + HYSTERESIS).intersects(low_tools)):
		return "low"
	return current


## Where the box of a thing at `origin` starts: the height its footprint is measured from, given its
## anchor (design/object-scale-and-surfaces.md). A thing on the ground stands up from its origin; a wall
## thing's origin is the middle of its back, so it reaches half its height below; a ceiling thing's origin
## is its hook, so it hangs its whole height below. (Until first-steps r8 every box was measured upward
## from the origin, so a wall thing's box was half its height too high and a ceiling thing's lay wholly
## above it: the measured cottage view, r8 work evidence `ROOMVIEW-pre-fix-*`.)
static func box_base(origin: Vector3, height: float, anchor: String) -> Vector3:
	if anchor == "wall":
		return origin - Vector3(0, height * 0.5, 0)
	if anchor == "ceiling":
		return origin - Vector3(0, height, 0)
	return origin


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
