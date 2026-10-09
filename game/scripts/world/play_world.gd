## Drawn effects for the play ideas batch 2 (design/playability-8-12.md): the toy
## track ball (F02), the music box loop with its beat lights (F08) and the arrow
## over the next trail sign (F06); r11: light pieces, sailing paper boats, leaf
## pile bursts and Tumble's shaped fountains. Everything here is local drawing
## from shared state and events; nothing is sent or saved.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const TownModel := preload("res://scripts/core/town_model.gd")
const PlayRules := preload("res://scripts/core/play_rules.gd")
const TrackRules := preload("res://scripts/core/track_rules.gd")

signal track_hint(text: String)

var world: Node3D
## The trail sign the local child walks to next ("" when not following).
var trail_target := ""
var balls := []               # [{"node", "cells", "t", "bells", "end", "at", "rung"}]
var last_step := -1           # music step last played (for tests)
var notes_played := 0         # notes this device played (for tests)
var _arrow: Node3D
var _gap_arrow: Node3D
var _gap_t := 0.0
var _t := 0.0
var sails := {}               # boat item id -> {"center", "radius", "t", "from"}
var bursts := 0               # leaf bursts drawn (for tests)
var fountains := 0            # fountains drawn (for tests)


func setup(w: Node3D) -> void:
	world = w
	_arrow = _make_arrow(Color("#f2a541"))
	_gap_arrow = _make_arrow(Color("#ef6f86"))
	Session.track_rolled.connect(_on_track)
	Session.boat_sailed.connect(_on_boat)
	Session.leaves_jumped.connect(_on_leaves)
	Animals.fountain.connect(_on_fountain)


func _make_arrow(c: Color) -> Node3D:
	var a := Node3D.new()
	a.top_level = true
	a.visible = false
	add_child(a)
	Kit.part(a, Kit.cylinder(0.0, 0.16, 0.26, 4), Kit.mat(c, 0.6, c * 0.6), Vector3(0, 0, 0), Vector3(180, 45, 0))
	Kit.cyl(a, 0.05, 0.05, 0.22, Kit.mat(c, 0.6, c * 0.6), Vector3(0, 0.22, 0))
	return a


# ------------------------------------------------------------- toy track ball (F02)

func _on_track(_start: String, cells: Array, end: String, at: Vector2, bells: Array) -> void:
	if world.view_space != "town" or cells.is_empty():
		return
	var ball := Node3D.new()
	ball.top_level = true
	add_child(ball)
	Kit.ball(ball, 0.09, Color("#e9806e"), Vector3.ZERO)
	ball.global_position = Vector3(cells[0].x, 0.2, cells[0].y)
	balls.append({"node": ball, "cells": cells, "t": 0.0, "bells": bells.duplicate(), "end": end, "at": at, "rung": 0, "done": false})


func _tick_balls(delta: float) -> void:
	for b in balls.duplicate():
		var cells: Array = b["cells"]
		b["t"] += delta / TrackRules.CELL_SECONDS
		var k: float = minf(b["t"], float(cells.size() - 1))
		var i := int(k)
		var p: Vector2 = cells[i] if i + 1 >= cells.size() else cells[i].lerp(cells[i + 1], k - i)
		b["node"].global_position = Vector3(p.x, 0.2 + absf(sin(b["t"] * PI)) * 0.03, p.y)
		b["node"].rotation.x += delta * 9.0
		# A bell rings as the ball passes its cell.
		var here := Vector2i(roundi(p.x), roundi(p.y))
		for id in b["bells"]:
			var it: Dictionary = Session.model.items.get(id, {})
			if not it.is_empty() and TrackRules.cell_of(it) == here:
				b["bells"].erase(id)
				var node: Node3D = world.item_nodes.get(id)
				if it["kind"] == "track_light":
					_near_sound("mb_chime", p)
					var lamp: Node3D = node.find_child("Lamp", true, false) if node else null
					if lamp:
						var tl := create_tween()
						tl.tween_property(lamp, "scale", Vector3.ONE * 2.2, 0.08)
						tl.tween_property(lamp, "scale", Vector3.ONE, 0.6)
				else:
					_near_sound("mb_bell", p)
					if node:
						var tw := create_tween()
						tw.tween_property(node, "scale", Vector3.ONE * 1.12, 0.1)
						tw.tween_property(node, "scale", Vector3.ONE, 0.2)
				break
		if b["t"] >= cells.size() - 1 and not b["done"]:
			b["done"] = true
			match b["end"]:
				"finish":
					_near_sound("lantern", p)
				"gap", "wrong_way":
					_gap_arrow.visible = true
					_gap_arrow.global_position = Vector3(b["at"].x, 0.9, b["at"].y)
					_gap_t = 5.0
					track_hint.emit("The ball is waiting: a piece is missing here." if b["end"] == "gap" else "The ball is waiting: turn this piece so the track joins up.")
		if b["t"] >= cells.size() + 2:
			b["node"].queue_free()
			balls.erase(b)


func _near_sound(name: String, at: Vector2) -> void:
	var me: Node3D = world.local_kid()
	if me and Vector2(me.global_position.x, me.global_position.z).distance_to(at) < 14.0:
		Sfx.play(name)


# ------------------------------------------------------------- music boxes (F08)

func _tick_music() -> void:
	var step := PlayRules.music_step(int(Time.get_unix_time_from_system() * 1000.0))
	if step == last_step:
		return
	last_step = step
	var me: Node3D = world.local_kid()
	for id in world.item_nodes:
		var it: Dictionary = Session.model.items.get(id, {})
		if it.get("kind", "") != "music_box" or not it.get("on", false):
			continue
		var node: Node3D = world.item_nodes[id]
		var notes := PlayRules.notes_at(it.get("song", []), step)
		var beat := node.get_node_or_null("Beat")
		if beat and step < beat.get_child_count() * 2:
			for i in beat.get_child_count():
				(beat.get_child(i) as Node3D).scale = Vector3.ONE * (1.6 if i == step % 4 and not notes.is_empty() else 1.0)
		if notes.is_empty():
			continue
		# Lamps close by glow a little on the beat (gentle, never flashing).
		for lid in world.item_nodes:
			var lamp: Dictionary = Session.model.items.get(lid, {})
			if lamp.get("kind", "") == "lamp_post" and Vector2(lamp["x"], lamp["z"]).distance_to(Vector2(it["x"], it["z"])) < 6.0:
				for g in world.item_nodes[lid].find_children("*", "MeshInstance3D", true, false):
					if g.is_in_group("glow"):
						var tw := create_tween()
						tw.tween_property(g, "scale", Vector3.ONE * 1.08, 0.08)
						tw.tween_property(g, "scale", Vector3.ONE, 0.2)
		var near := me != null and me.global_position.distance_to(node.global_position) < PlayRules.HEAR
		if near and not Sfx.music_boxes_muted:
			for n in notes:
				Sfx.play("mb_" + n)
				notes_played += 1


# ------------------------------------------------------------- trail arrow (F06)

func _tick_trail() -> void:
	var it: Dictionary = Session.model.items.get(trail_target, {})
	_arrow.visible = world.view_space == "town" and not it.is_empty()
	if _arrow.visible:
		_arrow.global_position = Vector3(it["x"], 1.55 + sin(_t * 3.0) * 0.08, it["z"])
		_arrow.rotation.y = _t * 1.5


# ------------------------------------------------------------- r11 weather toys and fountains

const SAIL_SECONDS := 9.0

func _on_boat(id: String, center: Vector2, radius: float) -> void:
	var node: Node3D = world.item_nodes.get(id)
	if node == null:
		return
	sails[id] = {"center": center, "radius": radius, "t": 0.0, "from": node.global_position,
		"axes": Vector2(radius, radius), "turn": 0.0}
	# A pond is an ellipse (props.gd: water 1.65 x 1.35 m, turned with the pond):
	# sail a lap well inside the water so the boat never crosses the rim stones.
	for it in Session.model.items_in("town"):
		if it["kind"] == "pond" and Vector2(it["x"], it["z"]).distance_to(center) < 0.05:
			sails[id]["axes"] = POND_SAIL
			sails[id]["turn"] = TownModel.rot_to_radians(it["rot"])
			return
	sails[id]["axes"] = TownModel.PUDDLE_HALF * 0.55   # a rain puddle: a small lap


## The sailing lap on a pond, in the pond's own frame (x, z semi-axes, metres).
const POND_SAIL := Vector2(1.15, 0.85)
## Water surface heights for the boat: pond water top 0.075 m; puddles lie on the grass.
const POND_WATER_Y := 0.075


## A point on a sail's lap (angle a), in world x/z.
static func sail_point(center: Vector2, axes: Vector2, turn: float, a: float) -> Vector2:
	var local := Vector2(cos(a) * axes.x, sin(a) * axes.y)
	# Same convention as an item turned by rot_to_radians: local +z maps to facing().
	return center + Vector2(local.x * cos(turn) + local.y * sin(turn), -local.x * sin(turn) + local.y * cos(turn))


## The boat glides onto the water, sails once around, bobbing, and comes back.
func _tick_sails(delta: float) -> void:
	for id in sails.keys():
		var sl: Dictionary = sails[id]
		var node: Node3D = world.item_nodes.get(id)
		var boat: Node3D = node.get_node_or_null("Boat") if node else null
		if boat == null:
			sails.erase(id)
			continue
		sl["t"] += delta / SAIL_SECONDS
		var k: float = sl["t"]
		var home := Vector2(sl["from"].x, sl["from"].z)
		# Start the lap at the point nearest the boat's stand (in the pond's frame).
		var rel: Vector2 = (home - sl["center"]).rotated(sl["turn"])
		var start_a := atan2(rel.y / maxf(sl["axes"].y, 0.01), rel.x / maxf(sl["axes"].x, 0.01))
		var ring: Vector2 = sail_point(sl["center"], sl["axes"], sl["turn"], start_a + clampf((k - 0.15) / 0.7, 0.0, 1.0) * TAU)
		var p: Vector2
		var hop := 0.0
		if k < 0.15:
			p = home.lerp(ring, k / 0.15)
			hop = sin(k / 0.15 * PI) * 0.35   # lifted over the rim stones
		elif k > 0.85:
			p = ring.lerp(home, (k - 0.85) / 0.15)
			hop = sin((k - 0.85) / 0.15 * PI) * 0.35
		else:
			p = ring
		var water_y := POND_WATER_Y if sl["axes"] == POND_SAIL else 0.02
		boat.global_position = Vector3(p.x, water_y - 0.03 + hop + sin(_t * 5.0) * 0.012, p.y)
		boat.rotation.z = sin(_t * 3.0) * 0.12
		if k >= 1.0:
			boat.position = Vector3.ZERO
			boat.rotation = Vector3.ZERO
			sails.erase(id)


func _on_leaves(id: String, _peer: int, together: bool) -> void:
	var node: Node3D = world.item_nodes.get(id)
	if node == null:
		return
	bursts += 1
	var p := CPUParticles3D.new()
	p.amount = 60 if together else 26
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = node.global_position + Vector3(0, 0.3, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 70
	p.gravity = Vector3(0, -2.2, 0)
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.6 if together else 2.6
	p.angular_velocity_min = -180
	p.angular_velocity_max = 180
	var m := BoxMesh.new()
	m.size = Vector3(0.1, 0.015, 0.07)
	var g := Gradient.new()
	g.set_color(0, Color("#e9934b"))
	g.set_color(1, Color("#f2c75c"))
	p.color_initial_ramp = g
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	_near_sound("splash", Vector2(node.global_position.x, node.global_position.z))
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.15, 0.7, 1.15), 0.12)
	tw.tween_property(node, "scale", Vector3.ONE, 0.5)


## Tumble's fountain (F03): droplets rise from points on a heart, star or circle.
static func fountain_points(shape: String) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 48:
		var t := TAU * i / 48.0
		var v := Vector2.ZERO
		match shape:
			"heart":
				v = Vector2(16.0 * pow(sin(t), 3), 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)) / 17.0
			"star":
				# Along the outline between 5 outer (r 1) and 5 inner (r 0.45) corners.
				var seg := TAU / 10.0
				var j := int(t / seg)
				var c0 := Vector2(sin(j * seg), cos(j * seg)) * (1.0 if j % 2 == 0 else 0.45)
				var c1 := Vector2(sin((j + 1) * seg), cos((j + 1) * seg)) * (1.0 if (j + 1) % 2 == 0 else 0.45)
				v = c0.lerp(c1, (t - j * seg) / seg)
			_:
				v = Vector2(sin(t), cos(t))
		pts.append(Vector3(v.x * 0.6, v.y * 0.6, 0.0))
	return pts


func _on_fountain(shape: String, at: Vector2, ry: float) -> void:
	if world.view_space != "town":
		return
	fountains += 1
	var p := CPUParticles3D.new()
	p.amount = 140
	p.lifetime = 1.6
	p.preprocess = 0.6   # the shape is already drawn when the fountain appears
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = fountain_points(shape)
	p.position = Vector3(at.x, 2.0, at.y) + Vector3(sin(ry), 0, cos(ry)) * 0.9
	# The shape faces this device's camera, so it is never seen edge-on.
	var cam := get_viewport().get_camera_3d()
	p.rotation.y = cam.global_rotation.y if cam else ry
	p.direction = Vector3(0, 1, 0)
	p.spread = 3
	p.gravity = Vector3(0, -0.3, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.12
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#9fd0ea")
	m.material = mat
	p.mesh = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false
			get_tree().create_timer(1.2).timeout.connect(p.queue_free))
	_near_sound("splash", at)


func _process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	_tick_sails(delta)
	_tick_balls(delta)
	_tick_music()
	_tick_trail()
	if _gap_t > 0.0:
		_gap_t -= delta
		_gap_arrow.global_position.y = 0.9 + sin(_t * 4.0) * 0.08
		if _gap_t <= 0.0:
			_gap_arrow.visible = false
