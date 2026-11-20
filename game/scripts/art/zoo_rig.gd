## The zoo animals' rig helpers (design/zoo-and-world-journeys.md section 7.1).
##
## Same technique as the town animals and the child: a tree of named pivots whose angles are
## written in code. These are the pure parts, testable headless without a scene:
##   two_bone()    place a hand or foot on a world point with a two-segment limb (law of cosines)
##   ease_to()     ease one angle toward a target, so actions blend instead of snapping
##   pendulum()    the angle of a swing or a hanging body over time
##   arc()         a leap, pounce or dive: the straight move with a lift and a squash
## Reduce Motion scales the amplitudes (section 22.4), never removes the motion.
extends RefCounted


## Bend of a two-segment limb so its end reaches `target` from `root`.
## Returns {"reach": bool, "upper": float, "lower": float, "end": Vector2} in the limb's own 2D
## plane: x along the line root->target, y toward the bend side. "upper" is the angle of the
## first segment from that line, "lower" the angle between the two segments (PI = straight).
## Out of reach the limb points straight at the target and "reach" is false.
static func two_bone(root: Vector2, target: Vector2, l1: float, l2: float) -> Dictionary:
	var d := root.distance_to(target)
	var dir := (target - root).normalized() if d > 0.0001 else Vector2.RIGHT
	var max_d := l1 + l2
	var min_d := absf(l1 - l2)
	var reach := d <= max_d + 0.0001 and d >= min_d - 0.0001
	var dd := clampf(d, min_d + 0.0001, max_d - 0.0001)
	# law of cosines: angle at the root between segment 1 and the root->target line
	var cos_a := clampf((l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0)
	var cos_b := clampf((l1 * l1 + l2 * l2 - dd * dd) / (2.0 * l1 * l2), -1.0, 1.0)
	var upper := acos(cos_a)
	var lower := acos(cos_b)
	var base_ang := dir.angle()
	var joint := root + Vector2.from_angle(base_ang + upper) * l1
	var end := joint + Vector2.from_angle(base_ang + upper - (PI - lower)) * l2
	return {"reach": reach, "upper": upper, "lower": lower, "joint": joint, "end": end}


## Ease an angle toward a target at `rate` per second (exponential), the shorter way round.
static func ease_to(current: float, target: float, rate: float, delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	return current + diff * (1.0 - exp(-rate * delta))


## A swing's angle at time t: amplitude a (radians), period p (seconds), phase in turns.
## With reduce_motion the arc is halved (50 degrees -> 25 degrees, section 22.4).
static func pendulum(t: float, a: float, p: float, phase := 0.0, reduce_motion := false) -> float:
	var amp := a * (0.5 if reduce_motion else 1.0)
	return amp * sin(TAU * (t / maxf(p, 0.01) + phase))


## A point along a leap from `from` to `to` (world, y = height) at progress u in 0..1, with peak
## height `lift` above the higher end. Returns the position; squash is reported by arc_squash().
static func arc(from: Vector3, to: Vector3, lift: float, u: float) -> Vector3:
	var k := clampf(u, 0.0, 1.0)
	var p := from.lerp(to, k)
	p.y += 4.0 * lift * k * (1.0 - k) + (maxf(from.y, to.y) - lerpf(from.y, to.y, k)) * 4.0 * k * (1.0 - k)
	return p


## Vertical scale of the body along a leap: a crouch before (u < 0.1), a stretch in flight, a
## squash on landing (u > 0.9). Never beyond 8 % (section 7.1, "life").
static func arc_squash(u: float) -> float:
	if u < 0.1:
		return 1.0 - 0.08 * sin(u / 0.1 * PI)
	if u > 0.9:
		return 1.0 - 0.08 * sin((u - 0.9) / 0.1 * PI)
	return 1.0 + 0.05 * sin((u - 0.1) / 0.8 * PI)
