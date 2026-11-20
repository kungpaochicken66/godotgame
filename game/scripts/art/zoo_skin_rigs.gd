## Rig tables for the six Everything Library zoo animals (docs/zoo-engineering-standard.md 11.1).
##
## One const table per species: the pivots (= bones) the imported mesh is driven by, the joint
## position of each (model space, metres: +Y up, +Z front, origin at the footprint centre on the
## ground, LEFT is -X as in zoo_animal.gd), and the region rule that decides which vertices follow
## which bone. zoo_skin.gd turns a table into pivots, a Skeleton3D, a Skin and vertex weights.
##
## Bone entry keys
##   "n"      pivot / bone name (the names zoo_animal.gd's poses write)
##   "p"      skeleton parent ("root" = the body)
##   "j"      joint position, model space (the pivot's rest position is j - parent's j, in the
##            parent's frame)
##   "pitch"  absolute rest pitch of the pivot frame about X (radians, default 0). Only the tail
##            chains use it: their local -Z runs along the tail, so the owner's Y-axis sway of
##            tail1..n swings the tail sideways, as on the procedural rigs.
##   "box"    [lo, hi, soft]: a soft box. Per axis the mask is smoothstep(lo-e, lo+e, v) *
##            (1 - smoothstep(hi-e, hi+e, v)), e = soft on that axis. +-9 means open.
##   "plane"  [point, dir, band]: smoothstep(-band, band, dot(v - point, dir)), a soft half space
##            whose edge is the joint's blend band.
##   "none"   true: the bone owns no vertices (the jaw: the meshes have no mouth geometry).
##   "mp"     membership parent when it differs from "p" (elephant ears belong to the neck
##            region, not the head region, but follow the head bone; the trunk is a region of
##            its own, not nested in the neck's, because the trunk hangs far below it).
##   "order"  claim order among siblings with the same membership parent (default 0, then table
##            position): lower claims a contested vertex first.
##
## Weights: see zoo_skin.gd. A bone's membership is parent membership * box * plane. Siblings are
## served in table order (earlier ones win a contested vertex); a bone's weight is its membership
## minus its children's. Everything left is the root bone, so the weights sum to 1 and the result
## is a pure function of vertex position and this table. Last, where a leg's soft region overlaps
## the neck chain's (chest, shoulder) the family with the larger share takes the vertex outright, so
## head and neck vertices never follow a leg (zoo_skin.gd _separate_legs_from_head).
##
## How the numbers were measured (all from the GLB vertex positions, 5 components per mesh: the
## body plus four eye discs): connected-component dumps; horizontal slices (y bands, grid
## clustering in x/z) gave each leg column's x and z extent and the belly height (lowest y of the
## mid-line vertices); a central side profile (|x| < 0.1, z bands, y intervals) gave belly, back,
## neck, head, chin and tail; the eye discs (z, y of the eye centres) located the head; dumps of
## the vertices of small parts (ears, tails, flippers) gave their roots and tips. Hip joints sit
## at the belly/shoulder line inside the body, knees at the mid-height of the leg column.
## Blend half-widths are about a quarter of the segment they separate.
extends RefCounted

const SPECIES := ["panda", "lion", "elephant", "giraffe", "zebra", "penguin"]

const O := 9.0   # "open" end of a soft box

# ---------------------------------------------------------------------------------- panda
## Panda 1.10 m, 1.9 long (head +Z, eyes at z 0.85, y 0.80). Legs are short columns below a belly at
## y 0.28: front z 0.16..0.52, hind z -0.84..-0.48, |x| 0.08..0.40. Back (shoulder hump) y 1.1 at
## z 0.4; head box x +-0.22, y 0.54..1.0, z 0.6..0.96; ears are the dark vertices at |x| 0.13..0.22,
## y 0.94..1.0, z 0.7; the "tail" is only the rump cap at z < -0.86 (y 0.5..0.93).
const PANDA := {
	"prop": Vector3(0, 0.62, 0.96),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 0.78, -0.88), "pitch": 0.0, "box": [Vector3(-0.13, 0.55, -O), Vector3(0.13, 1.0, -0.86), Vector3(0.03, 0.04, 0.03)]},
		{"n": "neck", "p": "root", "j": Vector3(0, 0.88, 0.44), "box": [Vector3(-O, 0.55, -O), Vector3(O, O, O), Vector3(0.1, 0.08, 0.1)], "plane": [Vector3(0, 0.88, 0.42), Vector3(0, 0, 1), 0.1]},
		{"n": "head", "p": "neck", "j": Vector3(0, 0.78, 0.62), "plane": [Vector3(0, 0.78, 0.62), Vector3(0, 0, 1), 0.08]},
		{"n": "jaw", "p": "head", "j": Vector3(0, 0.62, 0.82), "none": true},
		{"n": "ear_l", "p": "head", "j": Vector3(-0.16, 0.93, 0.68), "box": [Vector3(-O, 0.9, 0.6), Vector3(-0.1, O, 0.82), Vector3(0.02, 0.02, 0.03)]},
		{"n": "ear_r", "p": "head", "j": Vector3(0.16, 0.93, 0.68), "box": [Vector3(0.1, 0.9, 0.6), Vector3(O, O, 0.82), Vector3(0.02, 0.02, 0.03)]},
		{"n": "leg_fl", "p": "root", "j": Vector3(-0.24, 0.5, 0.34), "box": [Vector3(-0.46, -O, 0.12), Vector3(-0.06, 0.5, 0.56), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_fl_low", "p": "leg_fl", "j": Vector3(-0.24, 0.22, 0.34), "plane": [Vector3(-0.24, 0.22, 0.34), Vector3(0, -1, 0), 0.07]},
		{"n": "leg_fr", "p": "root", "j": Vector3(0.24, 0.5, 0.34), "box": [Vector3(0.06, -O, 0.12), Vector3(0.46, 0.5, 0.56), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_fr_low", "p": "leg_fr", "j": Vector3(0.24, 0.22, 0.34), "plane": [Vector3(0.24, 0.22, 0.34), Vector3(0, -1, 0), 0.07]},
		{"n": "leg_bl", "p": "root", "j": Vector3(-0.24, 0.5, -0.64), "box": [Vector3(-0.46, -O, -0.88), Vector3(-0.06, 0.5, -0.4), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_bl_low", "p": "leg_bl", "j": Vector3(-0.24, 0.22, -0.64), "plane": [Vector3(-0.24, 0.22, -0.64), Vector3(0, -1, 0), 0.07]},
		{"n": "leg_br", "p": "root", "j": Vector3(0.24, 0.5, -0.64), "box": [Vector3(0.06, -O, -0.88), Vector3(0.46, 0.5, -0.4), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_br_low", "p": "leg_br", "j": Vector3(0.24, 0.22, -0.64), "plane": [Vector3(0.24, 0.22, -0.64), Vector3(0, -1, 0), 0.07]},
	],
}

# ---------------------------------------------------------------------------------- lion
## Lion 1.55 m (mane top), 2.4 long. Belly y 0.70, back y 1.27; legs: front z 0.28..0.62, hind
## z -0.84..-0.5 (haunch to z -0.4 at y 0.7), |x| 0.08..0.36; mane/head z 0.85..1.2, y 1.0..1.55,
## eyes z 1.02, y 1.25. Tail is a thin tube hanging from the rump (0, 1.0, -0.83) to the tuft at
## (0, 0.29, -1.15), x +-0.04: joints read off the tube's ring centres at y 0.85, 0.6, 0.42.
const LION := {
	"prop": Vector3(0, 1.05, 1.15),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 1.0, -0.83), "pitch": -1.25, "box": [Vector3(-0.07, 0.2, -O), Vector3(0.07, 1.05, -0.78), Vector3(0.02, 0.03, 0.03)]},
		{"n": "tail1", "p": "tail0", "j": Vector3(0, 0.8, -0.88), "pitch": -1.25, "plane": [Vector3(0, 0.8, -0.88), Vector3(0, -0.97, -0.25), 0.07]},
		{"n": "tail2", "p": "tail1", "j": Vector3(0, 0.6, -0.92), "pitch": -1.25, "plane": [Vector3(0, 0.6, -0.92), Vector3(0, -0.97, -0.25), 0.07]},
		{"n": "tail3", "p": "tail2", "j": Vector3(0, 0.42, -1.0), "pitch": -1.25, "plane": [Vector3(0, 0.42, -1.0), Vector3(0, -0.9, -0.43), 0.06]},
		{"n": "neck", "p": "root", "j": Vector3(0, 1.2, 0.4), "box": [Vector3(-O, 0.95, -O), Vector3(O, O, O), Vector3(0.1, 0.1, 0.1)], "plane": [Vector3(0, 1.2, 0.4), Vector3(0, 0, 1), 0.12]},
		{"n": "head", "p": "neck", "j": Vector3(0, 1.28, 0.85), "plane": [Vector3(0, 1.28, 0.85), Vector3(0, 0, 1), 0.1]},
		{"n": "jaw", "p": "head", "j": Vector3(0, 1.1, 1.05), "none": true},
		{"n": "leg_fl", "p": "root", "j": Vector3(-0.22, 0.8, 0.45), "box": [Vector3(-0.42, -O, 0.26), Vector3(-0.07, 0.8, 0.64), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_fl_low", "p": "leg_fl", "j": Vector3(-0.22, 0.4, 0.45), "plane": [Vector3(-0.22, 0.4, 0.45), Vector3(0, -1, 0), 0.1]},
		{"n": "leg_fr", "p": "root", "j": Vector3(0.22, 0.8, 0.45), "box": [Vector3(0.07, -O, 0.26), Vector3(0.42, 0.8, 0.64), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_fr_low", "p": "leg_fr", "j": Vector3(0.22, 0.4, 0.45), "plane": [Vector3(0.22, 0.4, 0.45), Vector3(0, -1, 0), 0.1]},
		{"n": "leg_bl", "p": "root", "j": Vector3(-0.2, 0.8, -0.65), "box": [Vector3(-0.42, -O, -0.9), Vector3(-0.07, 0.8, -0.38), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_bl_low", "p": "leg_bl", "j": Vector3(-0.2, 0.4, -0.65), "plane": [Vector3(-0.2, 0.4, -0.65), Vector3(0, -1, 0), 0.1]},
		{"n": "leg_br", "p": "root", "j": Vector3(0.2, 0.8, -0.65), "box": [Vector3(0.07, -O, -0.9), Vector3(0.42, 0.8, -0.38), Vector3(0.05, 0.1, 0.05)]},
		{"n": "leg_br_low", "p": "leg_br", "j": Vector3(0.2, 0.4, -0.65), "plane": [Vector3(0.2, 0.4, -0.65), Vector3(0, -1, 0), 0.1]},
	],
}

# ---------------------------------------------------------------------------------- elephant
## Elephant 2.40 m, 3.45 long. Belly y 0.9 (rising to 1.2 at the chest), back y 2.35; legs are
## pillars: front z 0.0..0.45, hind z -1.4..-0.95, |x| 0.1..0.55. The head is z 0.65..1.4, y 1.4..2.3
## with eyes at z 1.05, y 1.8, |x| 0.25; the trunk hangs from (0, 1.72, 1.18) to (0, 0.12, 1.2),
## |x| < 0.15 (centres read per 0.15 m of height: z 1.2..1.3); tusks at |x| 0.3..0.45, z 1.4..1.75.
## Ears are the plates at |x| > 0.5, z 0.1..0.45, y 1.5..2.2 (x to 0.8). Tail: a tube behind the
## rump, (0, 1.9, -1.6) to (0, 0.65, -1.7).
const ELEPHANT := {
	"prop": Vector3(0, 0.9, 1.3),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 1.78, -1.62), "pitch": -1.2, "box": [Vector3(-0.08, 0.5, -O), Vector3(0.08, 1.82, -1.56), Vector3(0.02, 0.04, 0.03)]},
		{"n": "tail1", "p": "tail0", "j": Vector3(0, 1.2, -1.64), "pitch": -1.2, "plane": [Vector3(0, 1.2, -1.64), Vector3(0, -1, 0), 0.15]},
		{"n": "neck", "p": "root", "j": Vector3(0, 1.9, 0.3), "box": [Vector3(-O, 1.4, -O), Vector3(O, O, O), Vector3(0.1, 0.1, 0.1)], "plane": [Vector3(0, 1.9, 0.25), Vector3(0, 0, 1), 0.15]},
		{"n": "head", "p": "neck", "j": Vector3(0, 1.95, 0.8), "plane": [Vector3(0, 1.95, 0.75), Vector3(0, 0, 1), 0.12]},
		{"n": "ear_l", "p": "head", "mp": "neck", "j": Vector3(-0.42, 1.9, 0.5), "box": [Vector3(-O, 1.45, 0.05), Vector3(-0.45, O, 0.7), Vector3(0.04, 0.05, 0.05)]},
		{"n": "ear_r", "p": "head", "mp": "neck", "j": Vector3(0.42, 1.9, 0.5), "box": [Vector3(0.45, 1.45, 0.05), Vector3(O, O, 0.7), Vector3(0.04, 0.05, 0.05)]},
		{"n": "trunk0", "p": "head", "mp": "root", "order": -1, "j": Vector3(0, 1.72, 1.18), "box": [Vector3(-0.17, -O, 1.0), Vector3(0.17, 1.8, O), Vector3(0.04, 0.18, 0.06)]},
		{"n": "trunk1", "p": "trunk0", "j": Vector3(0, 1.15, 1.2), "plane": [Vector3(0, 1.15, 1.2), Vector3(0, -1, 0), 0.12]},
		{"n": "trunk2", "p": "trunk1", "j": Vector3(0, 0.62, 1.22), "plane": [Vector3(0, 0.62, 1.22), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_fl", "p": "root", "j": Vector3(-0.3, 1.25, 0.22), "box": [Vector3(-0.62, -O, -0.05), Vector3(-0.1, 1.3, 0.5), Vector3(0.05, 0.15, 0.05)]},
		{"n": "leg_fl_low", "p": "leg_fl", "j": Vector3(-0.3, 0.62, 0.22), "plane": [Vector3(-0.3, 0.62, 0.22), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_fr", "p": "root", "j": Vector3(0.3, 1.25, 0.22), "box": [Vector3(0.1, -O, -0.05), Vector3(0.62, 1.3, 0.5), Vector3(0.05, 0.15, 0.05)]},
		{"n": "leg_fr_low", "p": "leg_fr", "j": Vector3(0.3, 0.62, 0.22), "plane": [Vector3(0.3, 0.62, 0.22), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_bl", "p": "root", "j": Vector3(-0.33, 1.25, -1.17), "box": [Vector3(-0.62, -O, -1.45), Vector3(-0.1, 1.3, -0.88), Vector3(0.05, 0.15, 0.05)]},
		{"n": "leg_bl_low", "p": "leg_bl", "j": Vector3(-0.33, 0.62, -1.17), "plane": [Vector3(-0.33, 0.62, -1.17), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_br", "p": "root", "j": Vector3(0.33, 1.25, -1.17), "box": [Vector3(0.1, -O, -1.45), Vector3(0.62, 1.3, -0.88), Vector3(0.05, 0.15, 0.05)]},
		{"n": "leg_br_low", "p": "leg_br", "j": Vector3(0.33, 0.62, -1.17), "plane": [Vector3(0.33, 0.62, -1.17), Vector3(0, -1, 0), 0.12]},
	],
}

# ---------------------------------------------------------------------------------- giraffe
## Giraffe 2.80 m, 1.75 long, body only +-0.24 wide. Belly y 1.2, back y 1.8; legs: front z 0.12..0.4,
## hind z -0.88..-0.64 (thigh to z -0.4 at y 1.0), |x| 0.12..0.32. Neck: centre line from (0, 1.75,
## 0.22) to (0, 2.45, 0.5) (top/bottom profile intervals per z band); head z 0.5..0.88, y 2.4..2.8
## (eyes z 0.68, y 2.6). Ears: small plates at |x| 0.1..0.16, y 2.62..2.7, z 0.53..0.58. Tail: a
## thin tube at z -0.74..-0.78 from y 1.4 to 1.0.
const GIRAFFE := {
	"prop": Vector3(0, 2.52, 0.86),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 1.38, -0.75), "pitch": -1.2, "box": [Vector3(-0.07, 0.9, -O), Vector3(0.07, 1.42, -0.72), Vector3(0.02, 0.02, 0.02)]},
		{"n": "tail1", "p": "tail0", "j": Vector3(0, 1.22, -0.76), "pitch": -1.2, "plane": [Vector3(0, 1.22, -0.76), Vector3(0, -1, 0), 0.04]},
		{"n": "tail2", "p": "tail1", "j": Vector3(0, 1.08, -0.77), "pitch": -1.2, "plane": [Vector3(0, 1.08, -0.77), Vector3(0, -1, 0), 0.04]},
		{"n": "neck", "p": "root", "j": Vector3(0, 1.72, 0.24), "box": [Vector3(-O, 1.45, -O), Vector3(O, O, O), Vector3(0.1, 0.1, 0.1)], "plane": [Vector3(0, 1.72, 0.24), Vector3(0, 0.93, 0.37), 0.12]},
		{"n": "neck1", "p": "neck", "j": Vector3(0, 2.12, 0.38), "plane": [Vector3(0, 2.12, 0.38), Vector3(0, 0.93, 0.37), 0.1]},
		{"n": "head", "p": "neck1", "j": Vector3(0, 2.46, 0.5), "plane": [Vector3(0, 2.46, 0.5), Vector3(0, 0.9, 0.4), 0.1]},
		{"n": "ear_l", "p": "head", "j": Vector3(-0.09, 2.63, 0.55), "box": [Vector3(-O, 2.58, 0.47), Vector3(-0.095, 2.76, 0.62), Vector3(0.015, 0.02, 0.02)]},
		{"n": "ear_r", "p": "head", "j": Vector3(0.09, 2.63, 0.55), "box": [Vector3(0.095, 2.58, 0.47), Vector3(O, 2.76, 0.62), Vector3(0.015, 0.02, 0.02)]},
		{"n": "jaw", "p": "head", "j": Vector3(0, 2.5, 0.78), "none": true},
		{"n": "leg_fl", "p": "root", "j": Vector3(-0.18, 1.25, 0.27), "box": [Vector3(-0.38, -O, 0.08), Vector3(-0.08, 1.28, 0.46), Vector3(0.03, 0.12, 0.04)]},
		{"n": "leg_fl_low", "p": "leg_fl", "j": Vector3(-0.18, 0.65, 0.27), "plane": [Vector3(-0.18, 0.65, 0.27), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_fr", "p": "root", "j": Vector3(0.18, 1.25, 0.27), "box": [Vector3(0.08, -O, 0.08), Vector3(0.38, 1.28, 0.46), Vector3(0.03, 0.12, 0.04)]},
		{"n": "leg_fr_low", "p": "leg_fr", "j": Vector3(0.18, 0.65, 0.27), "plane": [Vector3(0.18, 0.65, 0.27), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_bl", "p": "root", "j": Vector3(-0.22, 1.25, -0.74), "box": [Vector3(-0.4, -O, -0.92), Vector3(-0.08, 1.28, -0.4), Vector3(0.03, 0.12, 0.04)]},
		{"n": "leg_bl_low", "p": "leg_bl", "j": Vector3(-0.22, 0.62, -0.74), "plane": [Vector3(-0.22, 0.62, -0.74), Vector3(0, -1, 0), 0.12]},
		{"n": "leg_br", "p": "root", "j": Vector3(0.22, 1.25, -0.74), "box": [Vector3(0.08, -O, -0.92), Vector3(0.4, 1.28, -0.4), Vector3(0.03, 0.12, 0.04)]},
		{"n": "leg_br_low", "p": "leg_br", "j": Vector3(0.22, 0.62, -0.74), "plane": [Vector3(0.22, 0.62, -0.74), Vector3(0, -1, 0), 0.12]},
	],
}

# ---------------------------------------------------------------------------------- zebra
## Zebra 1.65 m, 2.04 long. Belly y 0.68, back y 1.27; legs: front z 0.09..0.30, hind z -1.02..-0.78
## (thigh to z -0.69 at y 0.65), |x| 0.03..0.24. Neck rises from (0, 1.2, 0.2) to the head at
## (0, 1.4, 0.58); head z 0.58..1.02, y 1.07..1.64 (eyes z 0.78, y 1.35); the ears are part of the
## head (no ear pivots). Tail: a tube at z -0.9..-1.02 from the rump (0, 1.18, -0.96) to the
## tuft (0, 0.6, -0.92).
const ZEBRA := {
	"prop": Vector3(0, 1.15, 1.0),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 1.18, -0.96), "pitch": -1.2, "box": [Vector3(-0.05, 0.55, -O), Vector3(0.05, 1.17, -0.88), Vector3(0.015, 0.02, 0.02)]},
		{"n": "tail1", "p": "tail0", "j": Vector3(0, 0.95, -0.99), "pitch": -1.2, "plane": [Vector3(0, 0.95, -0.99), Vector3(0, -1, 0), 0.06]},
		{"n": "tail2", "p": "tail1", "j": Vector3(0, 0.78, -0.97), "pitch": -1.2, "plane": [Vector3(0, 0.78, -0.97), Vector3(0, -1, 0), 0.05]},
		{"n": "neck", "p": "root", "j": Vector3(0, 1.2, 0.2), "box": [Vector3(-O, 0.95, -O), Vector3(O, O, O), Vector3(0.1, 0.1, 0.1)], "plane": [Vector3(0, 1.2, 0.2), Vector3(0, 0.55, 0.83), 0.1]},
		{"n": "head", "p": "neck", "j": Vector3(0, 1.4, 0.58), "plane": [Vector3(0, 1.4, 0.58), Vector3(0, 0.25, 0.97), 0.08]},
		{"n": "jaw", "p": "head", "j": Vector3(0, 1.2, 0.9), "none": true},
		{"n": "leg_fl", "p": "root", "j": Vector3(-0.15, 0.78, 0.21), "box": [Vector3(-0.3, -O, 0.03), Vector3(-0.04, 0.78, 0.4), Vector3(0.015, 0.1, 0.04)]},
		{"n": "leg_fl_low", "p": "leg_fl", "j": Vector3(-0.15, 0.42, 0.21), "plane": [Vector3(-0.15, 0.42, 0.21), Vector3(0, -1, 0), 0.08]},
		{"n": "leg_fr", "p": "root", "j": Vector3(0.15, 0.78, 0.21), "box": [Vector3(0.04, -O, 0.03), Vector3(0.3, 0.78, 0.4), Vector3(0.015, 0.1, 0.04)]},
		{"n": "leg_fr_low", "p": "leg_fr", "j": Vector3(0.15, 0.42, 0.21), "plane": [Vector3(0.15, 0.42, 0.21), Vector3(0, -1, 0), 0.08]},
		{"n": "leg_bl", "p": "root", "j": Vector3(-0.12, 0.78, -0.9), "box": [Vector3(-0.28, -O, -1.08), Vector3(-0.04, 0.78, -0.68), Vector3(0.015, 0.1, 0.04)]},
		{"n": "leg_bl_low", "p": "leg_bl", "j": Vector3(-0.12, 0.42, -0.9), "plane": [Vector3(-0.12, 0.42, -0.9), Vector3(0, -1, 0), 0.08]},
		{"n": "leg_br", "p": "root", "j": Vector3(0.12, 0.78, -0.9), "box": [Vector3(0.04, -O, -1.08), Vector3(0.28, 0.78, -0.68), Vector3(0.015, 0.1, 0.04)]},
		{"n": "leg_br_low", "p": "leg_br", "j": Vector3(0.12, 0.42, -0.9), "plane": [Vector3(0.12, 0.42, -0.9), Vector3(0, -1, 0), 0.08]},
	],
}

# ---------------------------------------------------------------------------------- penguin
## Penguin 1.00 m, 0.43 long, +-0.36 across the flippers. Feet: the pads under the body at y < 0.16,
## |x| 0..0.15, z -0.1..0.07 (hip joint inside the body at y 0.3 so a swing lifts them). Flippers:
## roots at (+-0.2, 0.55) tips at (+-0.35, 0.29, 0.12), the vertices with |x| > 0.2. Head and beak:
## y > 0.8 (eyes y 0.94, z 0.04; beak to z 0.22). Tail: the stub at z < -0.14, y < 0.2.
const PENGUIN := {
	"prop": Vector3(0, 0.88, 0.24),
	"bones": [
		{"n": "tail0", "p": "root", "j": Vector3(0, 0.15, -0.15), "pitch": -0.9, "box": [Vector3(-0.07, -O, -O), Vector3(0.07, 0.22, -0.13), Vector3(0.03, 0.04, 0.03)]},
		{"n": "head", "p": "root", "j": Vector3(0, 0.78, 0.0), "plane": [Vector3(0, 0.78, 0), Vector3(0, 1, 0), 0.06]},
		{"n": "flipper_l", "p": "root", "j": Vector3(-0.2, 0.55, 0.0), "box": [Vector3(-O, 0.2, -O), Vector3(-0.2, 0.64, O), Vector3(0.04, 0.03, 0.05)]},
		{"n": "flipper_r", "p": "root", "j": Vector3(0.2, 0.55, 0.0), "box": [Vector3(0.2, 0.2, -O), Vector3(O, 0.64, O), Vector3(0.04, 0.03, 0.05)]},
		{"n": "leg_l", "p": "root", "j": Vector3(-0.07, 0.3, -0.02), "box": [Vector3(-0.2, -O, -0.16), Vector3(-0.02, 0.22, 0.13), Vector3(0.02, 0.1, 0.03)]},
		{"n": "leg_r", "p": "root", "j": Vector3(0.07, 0.3, -0.02), "box": [Vector3(0.02, -O, -0.16), Vector3(0.2, 0.22, 0.13), Vector3(0.02, 0.1, 0.03)]},
	],
}


static func table(species: String) -> Dictionary:
	match species:
		"panda": return PANDA
		"lion": return LION
		"elephant": return ELEPHANT
		"giraffe": return GIRAFFE
		"zebra": return ZEBRA
		"penguin": return PENGUIN
	return {}
