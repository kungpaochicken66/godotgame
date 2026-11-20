## Draws friend echoes (core/echoes.gd) in the space on screen: each "hello" is a figure in its
## child's shape, standing where it was left. It must never be mistaken for a child who is here
## (Mac review of town-play r1: the first version relied on GeometryInstance3D.transparency, which
## the OpenGL renderer does not draw, and showed an exact, opaque double with the same name tag).
## So it differs in three ways that do not depend on the renderer or on color alone: every part is
## one pale, see-through material (ordinary alpha blending); its tag reads "A hello from <name>" in
## another color; and a ring lies on the ground under it. When this device's child comes
## near, the figure plays its three emotes, one after another, and then waits a while.
## Nothing is decided here; the echoes are Session.model.echoes.
extends Node3D

const KidScript := preload("res://scripts/art/kid.gd")
const Kit := preload("res://scripts/art/mesh_kit.gd")
const Echoes := preload("res://scripts/core/echoes.gd")

## The figure plays when the child is this close, and again only after this many seconds.
const NOTICE := 4.5
const REST := 9.0
const STEP := 1.4
## The one material of every figure: pale, half see-through, drawn with ordinary alpha blending.
const TINT := Color("#d6ecf8")
const ALPHA := 0.5
const TAG_COLOR := Color("#7a5cc4")
const RING_COLOR := Color("#8e6bd6")

var world: Node3D
var figures := {}             # owner player id -> {"node", "rest", "queue", "next"}
var played := 0               # emotes figures played on this device (for tests)
var _dirty := true
var _ghost: StandardMaterial3D


func ghost_material() -> StandardMaterial3D:
	if _ghost == null:
		_ghost = StandardMaterial3D.new()
		_ghost.albedo_color = Color(TINT.r, TINT.g, TINT.b, ALPHA)
		_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Depth is written, so the figure is one even veil over what is behind it instead of
		# showing its own inner parts through each other.
		_ghost.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		_ghost.roughness = 0.8
		_ghost.emission_enabled = true
		_ghost.emission = TINT
		_ghost.emission_energy_multiplier = 0.25
	return _ghost


func setup(w: Node3D) -> void:
	world = w
	Session.town_data_changed.connect(func(key):
		if key == "echoes":
			_dirty = true)
	Session.town_reset.connect(func(): _dirty = true)
	world.view_changed.connect(func(_s): _dirty = true)
	I18n.locale_changed.connect(func(_c): _dirty = true)   # the tags follow the language


## Rebuilds the figures of the space on screen (after any change; also called by tests).
func apply() -> void:
	for f in figures.values():
		f["node"].queue_free()
	figures.clear()
	for pid in Session.model.echoes:
		var e: Dictionary = Session.model.echoes[pid]
		if e["space"] != world.view_space:
			continue
		var kid := KidScript.new()
		kid.name = "Echo_%s" % pid.left(8)
		add_child(kid)
		kid.setup(e["avatar"], true)
		kid.interpolate = false
		kid.position = Vector3(e["x"], 0, e["z"])
		kid.rotation.y = e["ry"]
		for mi in kid.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = ghost_material()
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kid._label:
			kid._label.text = tr("A hello from %s") % tr(str(e["nick"]))
			kid._label.modulate = TAG_COLOR
		var ring := MeshInstance3D.new()
		ring.name = "HelloRing"
		ring.mesh = Kit.torus(0.42, 0.5)
		ring.material_override = Kit.mat(RING_COLOR, 0.6, RING_COLOR * 0.4)
		ring.position = Vector3(0, 0.05, 0)
		kid.add_child(ring)
		figures[pid] = {"node": kid, "rest": 0.0, "queue": [], "next": 0.0}


func _process(delta: float) -> void:
	if world == null:
		return
	if _dirty:
		_dirty = false
		apply()
	var me: Node3D = world.local_kid()
	for pid in figures:
		var f: Dictionary = figures[pid]
		f["rest"] = maxf(0.0, f["rest"] - delta)
		if not f["queue"].is_empty():
			f["next"] -= delta
			if f["next"] <= 0.0:
				f["node"].play_emote(f["queue"].pop_front())
				played += 1
				f["next"] = STEP
		elif me and f["rest"] <= 0.0 and me.global_position.distance_to(f["node"].global_position) < NOTICE:
			f["queue"] = Array(Session.model.echoes.get(pid, {}).get("emotes", [])).duplicate()
			f["next"] = 0.3
			f["rest"] = REST
