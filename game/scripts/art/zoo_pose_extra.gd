## Poses for the three new imported zoo residents: panda, elephant and penguin
## (docs/zoo-engineering-standard.md 11.1 and 11.2). The owner calls pose() from _pose_animal.
##
## It fills `target` exactly as _pose_animal does: target[pivot_name] = Vector3 rotation OFFSET in
## radians (the pivot's rest rotation is added by the caller), plus target["_off"] (body offset,
## metres) and target["_rot"] (body rotation about the body origin on the ground). `t` already
## carries the animal's own phase, `u` is the action's progress 0..1, `amp` is 1.0 or 0.6 (reduced
## motion), `param` is the action's own number (the world's walk phase offset, a count) and is
## added to the gait clock so two animals never step in time.
##
## Axis conventions on these rigs (all pivots are axis aligned, so these hold for every one):
##   legs and flippers hang along -Y: +X swings the foot BACK, -X forward and up. Lower legs
##   (the knee) bend with +X. Neck and head: +X pitches the head forward and down, -X lifts it.
##   The trunk hangs along -Y: -X swings the tip forward and up (-1.57 is horizontal, -3.14 straight up).
##   Penguin flippers: Z swings them out (left is -Z, right is +Z). Elephant ears hinge on Y: the
##   left ear opens with +Y, the right with -Y. Panda ears tilt on Z. Tails sway on Y.
## Body: _rot.x > 0 pitches the nose down, _rot.z rolls about the long axis.
## `_prop` is true for actions that show the held item (the owner may use it to show the prop).
extends RefCounted

const FOUR_LEGS := ["leg_fl", "leg_fr", "leg_bl", "leg_br"]


static func pose(species: String, action: String, target: Dictionary, t: float, amp: float, u: float, param: float, reduce_motion: bool) -> void:
	target["_off"] = Vector3.ZERO
	target["_rot"] = Vector3.ZERO
	var sp := 0.7 if reduce_motion else 1.0   # reduced motion also slows the quick wobbles
	var tt := t * sp + param               # the animal's own clock
	match species:
		"panda":
			_panda(action, target, tt, amp, clampf(u, 0.0, 1.0), sp)
		"elephant":
			_elephant(action, target, tt, amp, clampf(u, 0.0, 1.0), sp)
		"penguin":
			_penguin(action, target, tt, amp, clampf(u, 0.0, 1.0), sp)


## Diagonal pairs (fl + br, then fr + bl): the upper leg swings fore and aft and the lower leg
## folds as the foot comes forward, so each foot visibly lifts and lands.
static func _quad_walk(target: Dictionary, t: float, speed: float, swing: float, knee: float) -> void:
	var s := sin(t * speed)
	for k in ["leg_fl", "leg_br"]:
		target[k] = Vector3(s * swing, 0, 0)
		target[k + "_low"] = Vector3(maxf(0.0, -s) * knee, 0, 0)
	for k in ["leg_fr", "leg_bl"]:
		target[k] = Vector3(-s * swing, 0, 0)
		target[k + "_low"] = Vector3(maxf(0.0, s) * knee, 0, 0)


## On the haunches: the body tipped back by `pitch`, the hind legs out in front (horizontal in
## the world). Returns (body pitch, body height offset) for the caller to apply.
static func _sit(target: Dictionary, pitch: float) -> Vector2:
	for k in ["leg_bl", "leg_br"]:
		target[k] = Vector3(-(1.57 - pitch) * 0.92, 0, 0)
		target[k + "_low"] = Vector3(0.1, 0, 0)
	return Vector2(-pitch, 0.33 * pitch / 0.7)


## Lying on the belly with the forelegs folded forward and the hind legs folded back.
static func _lie(target: Dictionary, fore: float, hind: float) -> void:
	for k in ["leg_fl", "leg_fr"]:
		target[k] = Vector3(-fore, 0, 0)
		target[k + "_low"] = Vector3(fore * 0.85, 0, 0)
	for k in ["leg_bl", "leg_br"]:
		target[k] = Vector3(hind, 0, 0)
		target[k + "_low"] = Vector3(-hind * 1.2, 0, 0)


static func _tail_sway(target: Dictionary, names: Array, t: float, a: float, speed: float) -> void:
	for i in names.size():
		target[names[i]] = Vector3(0, sin(t * speed - i * 0.6) * a, 0)


# ---------------------------------------------------------------------------------- panda

static func _panda(action: String, target: Dictionary, t: float, amp: float, u: float, sp: float) -> void:
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	off.y = sin(t * 1.6) * 0.012   # breathing
	var ears := sin(t * 1.3) * 0.08
	target["ear_l"] = Vector3(0, 0, ears)
	target["ear_r"] = Vector3(0, 0, -ears)
	target["tail0"] = Vector3(0, sin(t * 2.0) * 0.3, 0)
	match action:
		"walk":
			var spd := 5.0 * sp
			_quad_walk(target, t, spd, 0.45 * amp, 0.9 * amp)
			off.y += absf(sin(t * spd)) * 0.03 * amp
			rot.z = sin(t * spd) * 0.04 * amp   # a rolling bear's gait
			target["neck"] = Vector3(0.1 + sin(t * spd * 2.0) * 0.04 * amp, 0, 0)
			target["head"] = Vector3(0, sin(t * spd) * 0.1 * amp, 0)
		"look":
			target["neck"] = Vector3(-0.1, sin(t * 0.8) * 0.6, 0)
			target["head"] = Vector3(0, sin(t * 0.8 + 0.5) * 0.25, 0)
		"nod":
			target["head"] = Vector3(absf(sin(t * 3.0)) * 0.4 * amp, 0, 0)
			target["neck"] = Vector3(absf(sin(t * 3.0)) * 0.1 * amp, 0, 0)
		"blink":
			# No eyelids on the mesh: a quick dip of the head and a flick of the ears.
			var b := maxf(0.0, sin(t * 2.4)) * 0.12 * amp
			target["head"] = Vector3(b, 0, 0)
			target["ear_l"] = Vector3(0, 0, ears + b)
			target["ear_r"] = Vector3(0, 0, -ears - b)
		"eat":
			target["neck"] = Vector3(0.55, 0, 0)
			target["head"] = Vector3(0.2 + absf(sin(t * 5.0 * sp)) * 0.12 * amp, 0, 0)
			target["_prop"] = true
		"nap":
			off.y += -0.17 + sin(t * 1.0) * 0.012
			_lie(target, 1.0, 0.9)
			target["neck"] = Vector3(0.5, 0.3, 0)
			target["head"] = Vector3(0.25, 0.5, 0.1)
			target["ear_l"] = Vector3(0, 0, 0.1)
			target["ear_r"] = Vector3(0, 0, -0.1)
			target["tail0"] = Vector3.ZERO
		"munch":
			# Sitting, both paws held to the mouth, the head tipped into them and chewing.
			var st := _sit(target, 0.7)
			rot.x = st.x
			off.y += st.y
			var chew := absf(sin(t * 6.0 * sp))
			for k in ["leg_fl", "leg_fr"]:
				target[k] = Vector3(-1.45 + chew * 0.08 * amp, 0, 0)
				target[k + "_low"] = Vector3(-1.0 - chew * 0.1 * amp, 0, 0)
			target["neck"] = Vector3(0.25, 0, 0)
			target["head"] = Vector3(0.15 + chew * 0.14 * amp, sin(t * 3.0 * sp) * 0.05 * amp, 0)
			target["_prop"] = true
		"sit_up":
			# Upright, front paws resting on the belly, looking about.
			var k := smoothstep(0.0, 0.25, u)
			var st := _sit(target, 0.7 * k)
			rot.x = st.x
			off.y += st.y
			for k2 in ["leg_fl", "leg_fr"]:
				target[k2] = Vector3(-0.35 * k, 0, 0)
				target[k2 + "_low"] = Vector3(-0.5 * k, 0, 0)
			target["neck"] = Vector3(-0.1 * k, sin(t * 0.9) * 0.5 * k, 0)
			target["head"] = Vector3(-0.1 * k, 0, 0)
		"roll":
			# Rocking over on its back, all four paws waving.
			var a := sin(u * TAU) * 1.9 * amp
			rot.z = a
			off.x = 0.55 * sin(a)
			off.y += 0.55 * (1.0 - cos(a)) + 0.05
			for k in FOUR_LEGS:
				target[k] = Vector3(-0.9 + sin(t * 9.0 * sp) * 0.4 * amp, 0, 0)
				target[k + "_low"] = Vector3(0.4, 0, 0)
			target["head"] = Vector3(0, 0, sin(t * 3.0) * 0.1)
		"play_ball":
			# Sitting, batting a ball with alternating forepaws.
			var st := _sit(target, 0.5)
			rot.x = st.x
			off.y += st.y
			var s := sin(t * 4.0 * sp)
			target["leg_fl"] = Vector3(-0.9 + s * 0.6 * amp, 0, 0)
			target["leg_fr"] = Vector3(-0.9 - s * 0.6 * amp, 0, 0)
			target["leg_fl_low"] = Vector3(maxf(0.0, -s) * 0.7, 0, 0)
			target["leg_fr_low"] = Vector3(maxf(0.0, s) * 0.7, 0, 0)
			target["neck"] = Vector3(0.35, 0, 0)
			target["head"] = Vector3(0.15 + absf(s) * 0.1 * amp, 0, 0)
			target["_prop"] = true
		"graze":
			target["neck"] = Vector3(0.8, 0, 0)
			target["head"] = Vector3(0.35 + absf(sin(t * 4.0 * sp)) * 0.1 * amp, 0, 0)
			var s := sin(t * 0.9)
			target["leg_fl"] = Vector3(s * 0.15, 0, 0)
			target["leg_br"] = Vector3(s * 0.15, 0, 0)
			target["leg_fr"] = Vector3(-s * 0.15, 0, 0)
			target["leg_bl"] = Vector3(-s * 0.15, 0, 0)
			off.y -= 0.03
			target["_prop"] = true
		_:
			pass   # "idle" and anything unknown: breathing, ear twitch and a tail wag only
	target["_off"] = off
	target["_rot"] = rot


# ---------------------------------------------------------------------------------- elephant

static func _elephant(action: String, target: Dictionary, t: float, amp: float, u: float, sp: float) -> void:
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	off.y = sin(t * 1.1) * 0.015   # slow, deep breathing
	var ear := sin(t * 1.4) * 0.12
	target["ear_l"] = Vector3(0, ear, 0)
	target["ear_r"] = Vector3(0, -ear, 0)
	target["trunk0"] = Vector3(sin(t * 0.9) * 0.08, 0, sin(t * 0.7) * 0.05)
	target["trunk1"] = Vector3(sin(t * 0.9 - 0.5) * 0.1, 0, 0)
	target["trunk2"] = Vector3(sin(t * 0.9 - 1.0) * 0.12, 0, 0)
	_tail_sway(target, ["tail0", "tail1"], t, 0.3, 1.2)
	match action:
		"walk":
			var spd := 3.4 * sp
			_quad_walk(target, t, spd, 0.32 * amp, 0.55 * amp)
			off.y += absf(sin(t * spd)) * 0.025 * amp
			rot.z = sin(t * spd) * 0.025 * amp
			target["neck"] = Vector3(sin(t * spd * 2.0) * 0.03 * amp, 0, 0)
			target["head"] = Vector3(sin(t * spd * 2.0 - 0.5) * 0.04 * amp, sin(t * spd) * 0.05 * amp, 0)
			target["trunk0"] = Vector3(-0.1 + sin(t * spd) * 0.18 * amp, 0, 0)
			target["trunk1"] = Vector3(sin(t * spd - 0.7) * 0.18 * amp, 0, 0)
			target["trunk2"] = Vector3(sin(t * spd - 1.4) * 0.2 * amp, 0, 0)
			target["ear_l"] = Vector3(0, 0.1 + sin(t * spd * 2.0) * 0.12 * amp, 0)
			target["ear_r"] = Vector3(0, -0.1 - sin(t * spd * 2.0) * 0.12 * amp, 0)
		"look":
			target["neck"] = Vector3(-0.05, sin(t * 0.7) * 0.4, 0)
			target["head"] = Vector3(0, sin(t * 0.7 + 0.4) * 0.25, 0)
			target["trunk0"] = Vector3(-0.2, sin(t * 0.7) * 0.2, 0)
		"nod":
			target["head"] = Vector3(absf(sin(t * 2.4)) * 0.3 * amp, 0, 0)
			target["neck"] = Vector3(absf(sin(t * 2.4)) * 0.08 * amp, 0, 0)
		"blink":
			var b := maxf(0.0, sin(t * 2.0)) * 0.08 * amp
			target["head"] = Vector3(b, 0, 0)
			target["ear_l"] = Vector3(0, ear + b * 2.0, 0)
			target["ear_r"] = Vector3(0, -ear - b * 2.0, 0)
		"eat":
			# The trunk curls up and back under the chin, as if putting food in the mouth.
			var c := 0.5 + 0.5 * sin(t * 1.6 * sp)
			target["neck"] = Vector3(0.15, 0, 0)
			target["head"] = Vector3(0.1 + absf(sin(t * 4.0 * sp)) * 0.05 * amp, 0, 0)
			target["trunk0"] = Vector3(-0.6 - c * 0.5, 0, 0)
			target["trunk1"] = Vector3(-0.7 - c * 0.5, 0, 0)
			target["trunk2"] = Vector3(-0.9 - c * 0.4, 0, 0)
			target["_prop"] = true
		"nap":
			off.y += -0.8 + sin(t * 0.8) * 0.015
			_lie(target, 1.3, 1.1)
			target["neck"] = Vector3(0.3, 0, 0)
			target["head"] = Vector3(0.25, 0.3, 0)
			target["trunk0"] = Vector3(-0.1, 0, 0.1)
			target["trunk1"] = Vector3(0.2, 0, 0)
			target["trunk2"] = Vector3(-0.3, 0, 0)
			target["ear_l"] = Vector3(0, -0.15, 0)
			target["ear_r"] = Vector3(0, 0.15, 0)
		"drink":
			var d := smoothstep(0.0, 0.2, u)
			target["neck"] = Vector3(0.5 * d, 0, 0)
			target["head"] = Vector3(0.3 * d, 0, 0)
			target["trunk0"] = Vector3(-0.3 * d, 0, 0)
			target["trunk1"] = Vector3(-0.3 * d, 0, 0)
			target["trunk2"] = Vector3((-0.3 + sin(t * 3.5 * sp) * 0.25 * amp) * d, 0, 0)
			target["leg_fl"] = Vector3(-0.05, 0, 0.12 * d)
			target["leg_fr"] = Vector3(-0.05, 0, -0.12 * d)
			off.y -= 0.05 * d
		"spray":
			var k := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.85, 1.0, u))
			var pulse := sin(t * 8.0 * sp) * 0.1 * amp
			target["neck"] = Vector3(-0.1 * k, 0, 0)
			target["head"] = Vector3(-0.15 * k, 0, 0)
			target["trunk0"] = Vector3((-1.7 + pulse) * k, 0, 0)
			target["trunk1"] = Vector3(-0.5 * k, 0, 0)
			target["trunk2"] = Vector3((-0.4 - pulse) * k, 0, 0)
			target["ear_l"] = Vector3(0, 0.3 * k + ear, 0)
			target["ear_r"] = Vector3(0, -0.3 * k - ear, 0)
		"dust":
			# The trunk swings across the back and throws dust over itself.
			var s := sin(t * 3.0 * sp)
			target["neck"] = Vector3(0.1, 0, 0)
			target["trunk0"] = Vector3(-0.9 + s * 0.5 * amp, 0, s * 0.5 * amp)
			target["trunk1"] = Vector3(-0.6 + sin(t * 3.0 * sp + 0.6) * 0.4 * amp, 0, 0)
			target["trunk2"] = Vector3(-0.4 + sin(t * 3.0 * sp + 1.2) * 0.4 * amp, 0, 0)
			rot.z = s * 0.03 * amp
			target["ear_l"] = Vector3(0, 0.2, 0)
			target["ear_r"] = Vector3(0, -0.2, 0)
		"ear_flap":
			var f := sin(t * 7.0 * sp)
			target["ear_l"] = Vector3(0, (0.55 + 0.45 * f) * 0.9 * amp, 0)
			target["ear_r"] = Vector3(0, -(0.55 + 0.45 * f) * 0.9 * amp, 0)
			target["head"] = Vector3(0, sin(t * 1.2) * 0.06, 0)
		"trumpet":
			var k := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.8, 1.0, u))
			var shake := sin(t * 14.0 * sp) * 0.06 * amp
			target["neck"] = Vector3(-0.2 * k, 0, 0)
			target["head"] = Vector3(-0.3 * k, shake * k, 0)
			target["trunk0"] = Vector3(-2.0 * k, 0, 0)
			target["trunk1"] = Vector3((-0.5 + shake) * k, 0, 0)
			target["trunk2"] = Vector3((-0.35 - shake) * k, 0, 0)
			target["ear_l"] = Vector3(0, 0.6 * k + ear, 0)
			target["ear_r"] = Vector3(0, -0.6 * k - ear, 0)
			rot.x = -0.08 * k
			off.y += 0.04 * k
		"graze":
			var s := sin(t * 2.0 * sp)
			target["neck"] = Vector3(0.7, 0, 0)
			target["head"] = Vector3(0.25, 0, 0)
			target["trunk0"] = Vector3(-0.5 + s * 0.2 * amp, 0, 0)
			target["trunk1"] = Vector3(-0.5 + sin(t * 2.0 * sp - 0.6) * 0.2 * amp, 0, 0)
			target["trunk2"] = Vector3(-0.6 + sin(t * 2.0 * sp - 1.2) * 0.2 * amp, 0, 0)
			var w := sin(t * 0.8)
			target["leg_fl"] = Vector3(w * 0.1, 0, 0)
			target["leg_br"] = Vector3(w * 0.1, 0, 0)
			target["leg_fr"] = Vector3(-w * 0.1, 0, 0)
			target["leg_bl"] = Vector3(-w * 0.1, 0, 0)
			target["_prop"] = true
		_:
			pass
	target["_off"] = off
	target["_rot"] = rot


# ---------------------------------------------------------------------------------- penguin

static func _penguin(action: String, target: Dictionary, t: float, amp: float, u: float, sp: float) -> void:
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	off.y = sin(t * 1.8) * 0.01   # breathing
	target["flipper_l"] = Vector3(0, 0, -0.1 - sin(t * 1.3) * 0.05)
	target["flipper_r"] = Vector3(0, 0, 0.1 + sin(t * 1.3) * 0.05)
	target["tail0"] = Vector3(0, sin(t * 2.0) * 0.25, 0)
	match action:
		"walk", "waddle":
			# Body rolls toward the planted foot, the other foot lifts, the flippers counter-swing.
			var spd := 6.0 * sp
			var s := sin(t * spd)
			rot.z = s * 0.2 * amp
			rot.y = s * 0.08 * amp
			off.y += absf(sin(t * spd)) * 0.02 * amp
			target["leg_l"] = Vector3(-maxf(0.0, s) * 0.6 * amp, 0, 0)
			target["leg_r"] = Vector3(-maxf(0.0, -s) * 0.6 * amp, 0, 0)
			target["flipper_l"] = Vector3(-s * 0.5 * amp, 0, -0.35 - maxf(0.0, -s) * 0.2)
			target["flipper_r"] = Vector3(s * 0.5 * amp, 0, 0.35 + maxf(0.0, s) * 0.2)
			target["head"] = Vector3(0, 0, -s * 0.1 * amp)   # the head stays level against the roll
			target["tail0"] = Vector3(0, -s * 0.35 * amp, 0)
		"look":
			target["head"] = Vector3(-0.05, sin(t * 0.9) * 0.7, sin(t * 0.9 + 1.0) * 0.1)
		"nod":
			target["head"] = Vector3(absf(sin(t * 3.0)) * 0.4 * amp, 0, 0)
		"blink":
			var b := maxf(0.0, sin(t * 2.4)) * 0.1 * amp
			target["head"] = Vector3(b, 0, 0)
		"eat":
			# Pecking: the head dips down and up quickly.
			target["head"] = Vector3(0.15 + absf(sin(t * 5.0 * sp)) * 0.5 * amp, 0, 0)
			rot.x = 0.12 + absf(sin(t * 5.0 * sp)) * 0.1 * amp
			target["_prop"] = true
		"nap":
			# Asleep: the head turned back and tucked into the shoulder, the body settled.
			target["head"] = Vector3(0.45, 2.4, 0.2)
			target["flipper_l"] = Vector3(0, 0, -0.05)
			target["flipper_r"] = Vector3(0, 0, 0.05)
			rot.x = 0.1
			off.y += -0.02 + sin(t * 1.0) * 0.012
			target["tail0"] = Vector3.ZERO
		"swim":
			# Flat on the water, face down; the flippers beat in turn, the feet trail.
			rot.x = 1.45
			off.y += 0.32 + sin(t * 2.0 * sp) * 0.02
			var s := sin(t * 5.0 * sp)
			target["flipper_l"] = Vector3(0, 0, -0.9 - s * 0.6 * amp)
			target["flipper_r"] = Vector3(0, 0, 0.9 - s * 0.6 * amp)
			target["leg_l"] = Vector3(0.5 + sin(t * 5.0 * sp) * 0.15, 0, 0)
			target["leg_r"] = Vector3(0.5 - sin(t * 5.0 * sp) * 0.15, 0, 0)
			target["head"] = Vector3(-1.0, 0, 0)   # the head lifted to look ahead
		"dive":
			var k := sin(u * PI)
			rot.x = 1.2 + k * 1.3
			off.y += 0.25 - k * 0.8 * amp
			var s := sin(t * 6.0 * sp)
			target["flipper_l"] = Vector3(0, 0, -1.0 - s * 0.4 * amp)
			target["flipper_r"] = Vector3(0, 0, 1.0 + s * 0.4 * amp)
			target["leg_l"] = Vector3(0.7, 0, 0)
			target["leg_r"] = Vector3(0.7, 0, 0)
		"surface":
			var k := smoothstep(0.0, 0.6, u)
			rot.x = lerpf(2.2, 0.15, k)
			off.y += k * 0.3
			target["flipper_l"] = Vector3(0, 0, -0.6 - (1.0 - k) * 0.6)
			target["flipper_r"] = Vector3(0, 0, 0.6 + (1.0 - k) * 0.6)
			target["head"] = Vector3(-0.3 * k, 0, 0)
		"slide":
			# On the belly, tobogganing: flippers back, feet up, a little wobble.
			rot.x = 1.45
			off.y += 0.13
			rot.z = sin(t * 4.0 * sp) * 0.06 * amp
			target["flipper_l"] = Vector3(0.9, 0, -0.35)
			target["flipper_r"] = Vector3(0.9, 0, 0.35)
			target["leg_l"] = Vector3(1.2, 0, 0)
			target["leg_r"] = Vector3(1.2, 0, 0)
			target["head"] = Vector3(-1.1, 0, 0)
		"flap":
			var f := sin(t * 13.0 * sp)
			var open := 0.9 + f * 0.7 * amp
			target["flipper_l"] = Vector3(0, 0, -open)
			target["flipper_r"] = Vector3(0, 0, open)
			off.y += maxf(0.0, f) * 0.02 * amp
			target["head"] = Vector3(-0.2, 0, 0)
			rot.x = -0.1
		"preen":
			# The head swings round to the flipper and nibbles it, the flipper held forward.
			var n := sin(t * 7.0 * sp)
			target["head"] = Vector3(0.45 + n * 0.1 * amp, 1.0, 0.0)
			target["flipper_l"] = Vector3(-1.0 + n * 0.1 * amp, 0, -0.55)
			rot.z = 0.05
		"hop":
			var h := sin(t * 6.0 * sp)
			off.y += absf(h) * 0.16 * amp
			var tuck := absf(h)
			target["leg_l"] = Vector3(-tuck * 0.5 * amp, 0, 0)
			target["leg_r"] = Vector3(-tuck * 0.5 * amp, 0, 0)
			target["flipper_l"] = Vector3(0, 0, -0.5 - tuck * 0.6 * amp)
			target["flipper_r"] = Vector3(0, 0, 0.5 + tuck * 0.6 * amp)
			rot.x = -0.08 * tuck
		_:
			pass
	target["_off"] = off
	target["_rot"] = rot
