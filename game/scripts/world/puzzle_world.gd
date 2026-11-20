## Draws puzzle rooms (design/puzzle-rooms-and-rides.md) in the space on screen:
## which keys are still to be found, what every picture dial shows, the chest's
## lid and its row of lights (one per key and per dial, so the chest itself says
## what it still needs), a key flying to the chest when it is found, and, while
## decorating, the dotted lines that join a puzzle's parts.
##
## Everything here follows Session.puzzle_state (the authority's shared progress)
## and the town as it is now; nothing is decided on this device.
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const Puzzles := preload("res://scripts/core/puzzles.gd")
const Palette := preload("res://scripts/core/palette.gd")

const LINK := Color("#8e6bd6")
const UNLIT := Color("#6f6a62")
const GOLD := Color("#f2c75c")
const LID_OPEN := -1.75

var world: Node3D
var links_on := false
var link_pairs := []          # [[from id, to id, why]] drawn now (for tests)
var keys_flown := 0           # keys seen going to the chest on this device (for tests)
var opens_drawn := 0          # chests seen opening on this device (for tests)
var lights := {}              # chest id -> [lit?, ...] as drawn now (for tests)
var _links_root: Node3D
var _fx_root: Node3D
var _dirty := true


func setup(w: Node3D) -> void:
	world = w
	_links_root = Node3D.new()
	_links_root.name = "PuzzleLinks"
	add_child(_links_root)
	_fx_root = Node3D.new()
	_fx_root.name = "PuzzleFx"
	add_child(_fx_root)
	Session.puzzle_changed.connect(_on_puzzle)
	Session.item_changed.connect(func(_i): _dirty = true)
	Session.items_removed.connect(func(_i): _dirty = true)
	Session.town_reset.connect(func(): _dirty = true)
	world.view_changed.connect(func(_s): _dirty = true)


## Shows or hides the dotted lines between a puzzle's parts (the controller calls this with the mode).
func show_links(on: bool) -> void:
	links_on = on
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		apply()


func _point(id: String, lift := 0.14) -> Vector3:
	var it: Dictionary = Session.model.items.get(id, {})
	return Vector3(it.get("x", 0.0), lift, it.get("z", 0.0))


## Makes every puzzle part on screen show the shared state (called after any change; also by tests).
func apply() -> void:
	var space: String = world.view_space
	var st: Dictionary = Session.puzzle_state(space)
	var parts: Dictionary = Puzzles.parts(Session.model, space)
	var prog: Dictionary = Puzzles.progress(Session.model, space, st)
	lights.clear()
	for id in world.item_nodes:
		var node: Node3D = world.item_nodes[id]
		var item: Dictionary = node.get_meta("item")
		if item.has("gift"):
			continue
		match item["kind"]:
			Puzzles.KEY:
				var key := node.get_node_or_null("Key") as Node3D
				if key:
					key.visible = not st["found"].has(id)
			Puzzles.DIAL:
				var pics := node.get_node_or_null("Pictures") as Node3D
				if pics:
					var shown := int(st["dials"].get(id, 0))
					for i in pics.get_child_count():
						(pics.get_child(i) as Node3D).visible = i == shown
			Puzzles.CHEST:
				var lid := node.get_node_or_null("Lid") as Node3D
				var treasure := node.get_node_or_null("Treasure") as Node3D
				if lid and not lid.has_meta("opening"):
					lid.rotation.x = LID_OPEN if prog["open"] else 0.0
				if treasure:
					treasure.visible = prog["open"]
				_chest_lights(node, id, parts, st)
	_rebuild_links()


## One small light per key (gold) and per dial (the dial's color), lit when that part is done.
func _chest_lights(node: Node3D, id: String, parts: Dictionary, st: Dictionary) -> void:
	var holder := node.get_node_or_null("Lights") as Node3D
	if holder == null:
		return
	for c in holder.get_children():
		c.free()
	var specs := []
	for key in parts["keys"]:
		specs.append([GOLD, st["found"].has(key)])
	for d in parts["dials"]:
		specs.append([Palette.paint(d["color"]), int(st["dials"].get(d["id"], -1)) == int(d["target"])])
	var shown := []
	var width: float = holder.get_meta("width", 0.5)
	var step := minf(0.085, width / maxf(1.0, float(specs.size())))
	for i in specs.size():
		var lit: bool = specs[i][1]
		var c: Color = specs[i][0] if lit else UNLIT
		var bulb := Kit.ball(holder, 0.03, Kit.mat(c, 0.5, c * (0.9 if lit else 0.0)), Vector3((i - (specs.size() - 1) * 0.5) * step, 0, 0),
			Vector3(1, 1, 0.6))
		bulb.add_to_group("glow")
		shown.append(lit)
	lights[id] = shown


func _rebuild_links() -> void:
	for c in _links_root.get_children():
		c.queue_free()
	link_pairs = Puzzles.links(Session.model, world.view_space) if links_on else []
	var mat := Kit.mat(LINK, 0.6, LINK * 0.5)
	for pair in link_pairs:
		var a := _point(pair[0])
		var b := _point(pair[1])
		if a.distance_to(b) < 0.3:
			continue   # a key lying on the chest: nothing to draw
		var n := maxi(2, int(a.distance_to(b) / 0.26))
		for i in range(1, n):
			var dot := MeshInstance3D.new()
			# Squares, where contraption links are round dots: two kinds of line that differ by shape too.
			dot.mesh = Kit.rounded_box(Vector3(0.06, 0.03, 0.06), 0.01)
			dot.material_override = mat
			dot.position = a.lerp(b, float(i) / n)
			_links_root.add_child(dot)


func _on_puzzle(space: String, st: Dictionary, was: Dictionary) -> void:
	_dirty = true
	if space != world.view_space or st.is_empty():
		return
	var chest_id := ""
	var parts: Dictionary = Puzzles.parts(Session.model, space)
	if not parts["chests"].is_empty():
		chest_id = parts["chests"][0]
	for id in st.get("found", {}):
		if not was.get("found", {}).has(id):   # nothing known before means a fresh puzzle: no key was found yet
			_fly_key(id, chest_id)
	for id in st.get("dials", {}):
		if was.get("dials", {}).has(id) and int(was["dials"][id]) != int(st["dials"][id]) and not was.get("open", false):
			_turn_knob(id)
	if bool(st.get("open", false)) and not bool(was.get("open", false)):
		_open_chests(parts["chests"])


## A found key hops from where it lay to the chest.
func _fly_key(key_id: String, chest_id: String) -> void:
	keys_flown += 1
	_near_sound("pop", key_id)
	if world.reduce_motion or chest_id == "" or not world.item_nodes.has(key_id):
		return
	var from := _point(key_id, 0.25)
	var to := _point(chest_id, 0.45)
	var star := Kit.ball(_fx_root, 0.07, Kit.mat(GOLD, 0.4, GOLD * 0.8), from)
	var tw := create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(star):
			star.position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 0.9, 0), 0.0, 1.0, 0.7)
	tw.tween_callback(star.queue_free)


func _turn_knob(dial_id: String) -> void:
	_near_sound("tap", dial_id)
	var node: Node3D = world.item_nodes.get(dial_id)
	var knob := node.get_node_or_null("Knob") as Node3D if node else null
	if knob and not world.reduce_motion:
		var tw := create_tween()
		tw.tween_property(knob, "rotation:x", knob.rotation.x + PI * 0.5, 0.2)


func _open_chests(ids: Array) -> void:
	opens_drawn += 1
	if not ids.is_empty():
		_near_sound("lantern", ids[0])
	for id in ids:
		var node: Node3D = world.item_nodes.get(id)
		var lid := node.get_node_or_null("Lid") as Node3D if node else null
		if lid == null:
			continue
		if world.reduce_motion:
			lid.rotation.x = LID_OPEN
			continue
		lid.set_meta("opening", true)
		var tw := create_tween()
		tw.tween_property(lid, "rotation:x", LID_OPEN, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			if is_instance_valid(lid):
				lid.remove_meta("opening"))
		# A few gold sparkles rise from the chest.
		for i in 6:
			var a := TAU * i / 6.0
			var from := node.global_position + Vector3(0, 0.5, 0)
			var to := from + Vector3(cos(a) * 0.5, 0.7 + 0.1 * (i % 2), sin(a) * 0.5)
			var s := Kit.ball(_fx_root, 0.04, Kit.mat(GOLD, 0.4, GOLD * 0.9), from)
			var ts := create_tween()
			ts.tween_property(s, "position", to, 0.7).set_ease(Tween.EASE_OUT)
			ts.parallel().tween_property(s, "scale", Vector3.ONE * 0.1, 0.7)
			ts.tween_callback(s.queue_free)


func _near_sound(name: String, id: String) -> void:
	var me: Node3D = world.local_kid()
	var at := _point(id)
	if me and Vector2(me.global_position.x, me.global_position.z).distance_to(Vector2(at.x, at.z)) < 14.0:
		Sfx.play(name)
