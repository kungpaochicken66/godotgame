## Close, gently tilted follow camera (design direction A) with 45-degree turns
## and two zoom levels. Inside cottages it frames the dollhouse cut-away room.
extends Node3D

const PITCH := deg_to_rad(40.0)
const ZOOMS := [9.5, 15.0]
const ROOM_DISTANCE := 11.0

var camera: Camera3D
var target: Node3D
var yaw_step := 0
var zoom := 0
var in_room := false
var _yaw := 0.0
var _focus := Vector3.ZERO
var _distance: float = ZOOMS[0]
var _focus_override: Variant = null
## Node to look at instead of the child, e.g. an item being placed.
var follow: Node3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.2
	camera.far = 220.0
	add_child(camera)
	camera.current = true


func rotate_step(dir: int) -> void:
	if not in_room:
		yaw_step = posmod(yaw_step + dir, 8)


func toggle_zoom() -> void:
	zoom = 1 - zoom


func set_room(on: bool) -> void:
	in_room = on
	snap()


## Temporarily look at a point (celebrations), then return to the child.
func peek(point: Vector3, seconds := 2.5) -> void:
	_focus_override = point
	get_tree().create_timer(seconds).timeout.connect(func(): _focus_override = null)


func snap() -> void:
	_update(1.0)


func _process(delta: float) -> void:
	_update(minf(1.0, delta * 4.0))


func _update(k: float) -> void:
	var goal_yaw: float
	var goal_dist: float
	var goal_focus: Vector3
	if in_room:
		goal_yaw = deg_to_rad(28.0)
		goal_dist = ROOM_DISTANCE
		goal_focus = Vector3(0, 0.4, 0.3)
		if target:
			goal_focus = goal_focus.lerp(Vector3(target.global_position.x, 0.4, target.global_position.z), 0.25)
	else:
		goal_yaw = yaw_step * TAU / 8.0
		goal_dist = ZOOMS[zoom]
		var t := follow if is_instance_valid(follow) else target
		goal_focus = (t.global_position if t else Vector3.ZERO) + Vector3(0, 0.6, 0)
		if is_instance_valid(follow):
			# Aim a little in front of the item so it shows above the toy box panels.
			goal_focus += Vector3(sin(goal_yaw), 0, cos(goal_yaw)) * goal_dist * 0.32
	if _focus_override != null:
		goal_focus = _focus_override
	_yaw = lerp_angle(_yaw, goal_yaw, k)
	_distance = lerpf(_distance, goal_dist, k)
	_focus = _focus.lerp(goal_focus, k)
	var offset := Vector3(sin(_yaw) * cos(PITCH), sin(PITCH), cos(_yaw) * cos(PITCH)) * _distance
	camera.global_position = _focus + offset
	camera.global_basis = Basis.looking_at(-offset.normalized(), Vector3.UP)


## Ground-plane directions relative to the camera, for keyboard walking.
func flat_forward() -> Vector2:
	return Vector2(-sin(_yaw), -cos(_yaw))


func flat_right() -> Vector2:
	return Vector2(cos(_yaw), -sin(_yaw))
