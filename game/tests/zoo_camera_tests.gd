## Headless tests for the zoo-only camera (docs/zoo-engineering-standard.md section 5): the three
## zoo zooms with eight turns (24 views) at the four layouts, camera-relative movement, picking,
## enter / leave, the zoom steps, and Reduce Motion. The town and room camera stay as they were.
##   scripts/godot.sh --headless --path game -s res://tests/zoo_camera_tests.gd
extends SceneTree

const CameraRig := preload("res://scripts/world/camera_rig.gd")
const ZooMap := preload("res://scripts/core/zoo_map.gd")
const ZooTests := preload("res://tests/zoo_tests.gd")

var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	await process_frame   # the root is in the tree from here
	for t in ["test_constants", "test_views", "test_movement_axes", "test_picking", "test_enter_leave",
			"test_zoom_steps", "test_town_unchanged", "test_reduce_motion"]:
		_current = t
		call(t)
	print("\nZOO CAMERA TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


## A rig with a child-like target at `at`, snapped. The caller frees it.
func _rig(at := Vector3.ZERO) -> Node3D:
	var rig: Node3D = CameraRig.new()
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = at
	rig.target = target
	root.add_child(rig)
	rig.snap()
	return rig


func _free(rig: Node3D) -> void:
	rig.target.queue_free()
	rig.queue_free()


func test_constants() -> void:
	ok(CameraRig.ZOO_ZOOMS == [8.0, 9.5, 15.0], "the zoo zooms are 8, 9.5 and 15 m")
	ok(CameraRig.ZOO_DEFAULT == 1 and CameraRig.ZOO_ZOOMS[CameraRig.ZOO_DEFAULT] == 9.5, "the default zoo zoom is 9.5 m")
	ok(CameraRig.ZOOMS == [9.5, 15.0], "the town still has its two zooms")


func test_views() -> void:
	for sk in ZooMap.SPOTS:
		var bay: Rect2 = ZooMap.AREAS[ZooMap.SPOTS[sk]["bay"]]["rect"]
		var pos: Vector2 = ZooMap.SPOTS[sk]["pos"]
		var child := Vector2(clampf(pos.x, bay.position.x + 0.3, bay.end.x - 0.3), clampf(pos.y, bay.position.y + 0.3, bay.end.y - 0.3))
		for step in 8:
			for z in 3:
				var xf: Transform3D = CameraRig.pose_xform(Vector3(child.x, ZooTests.FOCUS_UP, child.y), step * TAU / 8.0, CameraRig.ZOO_ZOOMS[z])
				for lay in ZooTests.LAYOUTS:
					var view: Vector2 = ZooTests.LAYOUTS[lay]
					var feet = CameraRig.project(xf, view, Vector3(child.x, 0.0, child.y))
					var head = CameraRig.project(xf, view, Vector3(child.x, 1.3, child.y))
					var good: bool = feet != null and head != null and head.y >= ZooTests.TOP_BAR and feet.y <= view.y and head.x >= 0.0 and head.x <= view.x and feet.x >= 0.0 and feet.x <= view.x
					ok(good, "child at %s (%s) is on screen below the top bar: step %d zoom %d %s" % [sk, ZooMap.SPOTS[sk]["bay"], step, z, lay])


func test_movement_axes() -> void:
	var rig := _rig()
	rig.enter_zoo()
	for step in 8:
		rig.yaw_step = step
		rig.snap()
		var yaw: float = step * TAU / 8.0
		# Forward is where the camera looks along the ground; right is its right-hand side.
		var fwd: Vector2 = rig.flat_forward()
		var right: Vector2 = rig.flat_right()
		var look: Vector3 = -rig.camera.global_basis.z
		var cam_right: Vector3 = rig.camera.global_basis.x
		ok(fwd.is_equal_approx(Vector2(-sin(yaw), -cos(yaw))), "forward matches the yaw at step %d" % step)
		ok(right.is_equal_approx(Vector2(cos(yaw), -sin(yaw))), "right matches the yaw at step %d" % step)
		ok(fwd.is_equal_approx(Vector2(look.x, look.z).normalized()), "forward is the camera's ground direction at step %d" % step)
		ok(right.is_equal_approx(Vector2(cam_right.x, cam_right.z).normalized()), "right is the camera's right at step %d" % step)
		ok(absf(fwd.dot(right)) < 0.0001 and absf(fwd.length() - 1.0) < 0.0001, "forward and right are a unit pair at step %d" % step)
	_free(rig)


func test_picking() -> void:
	for lay in ZooTests.LAYOUTS:
		var view: Vector2 = ZooTests.LAYOUTS[lay]
		for step in 8:
			for z in 3:
				var xf: Transform3D = CameraRig.pose_xform(Vector3(3.0, ZooTests.FOCUS_UP, -14.0), step * TAU / 8.0, CameraRig.ZOO_ZOOMS[z])
				for off in [Vector3(0.7, 0, 0.4), Vector3(-1.5, 0, 1.0), Vector3(0.0, 0, -2.0)]:
					var p: Vector3 = Vector3(3.0, 0.0, -14.0) + off
					var s: Variant = CameraRig.project(xf, view, p)
					var back: Variant = ZooTests.ground_hit(xf, view, s) if s != null else null
					ok(back != null and (back as Vector3).distance_to(p) < 0.01, "picking maps %s back at %s step %d zoom %d" % [p, lay, step, z])
	# The live camera agrees with the projection the tests use.
	var rig := _rig(Vector3(3, 0, -14))
	rig.enter_zoo()
	rig.zoom_in()
	rig.rotate_step(3)
	rig.snap()
	var p2 := Vector3(4.0, 0.0, -13.0)
	var a: Variant = CameraRig.project(rig.rest_xform(), rig.view_size(), p2)
	var b: Vector2 = rig.camera.unproject_position(p2)
	ok(a != null and (a as Vector2).distance_to(b) < 0.5, "the live camera and CameraRig.project agree in the zoo")
	_free(rig)


func test_enter_leave() -> void:
	var rig := _rig()
	rig.yaw_step = 5
	rig.zoom = 1
	rig.snap()
	rig.enter_zoo()
	ok(rig.on_zoo and rig.yaw_step == 0 and rig.zoom == CameraRig.ZOO_DEFAULT, "enter_zoo resets to yaw 0 and the default zoom")
	ok(is_equal_approx(rig.distance(), 9.5), "the zoo default distance is 9.5 m")
	ok(is_equal_approx(rig.camera.global_position.distance_to(Vector3(0, 0.6, 0)), 9.5), "enter_zoo snapped the camera to 9.5 m")
	rig.rotate_step(2)
	rig.zoom_in()
	rig.enter_zoo()   # a second call must not overwrite the remembered town view
	rig.leave_zoo()
	ok(not rig.on_zoo and rig.yaw_step == 5 and rig.zoom == 1, "leave_zoo restores the town's turn and zoom")
	ok(is_equal_approx(rig.distance(), 15.0), "the town's distance is back")
	ok(is_equal_approx(rig.camera.global_position.distance_to(Vector3(0, 0.6, 0)), 15.0), "leave_zoo snapped the camera to the town view")
	rig.leave_zoo()
	ok(rig.yaw_step == 5 and rig.zoom == 1, "leave_zoo outside the zoo changes nothing")
	_free(rig)


func test_zoom_steps() -> void:
	var rig := _rig()
	rig.enter_zoo()
	var seen: Array = []
	for i in 4:
		seen.append(rig.distance())
		rig.toggle_zoom()
	ok(seen == [9.5, 15.0, 8.0, 9.5], "the zoo toggle steps 9.5 -> 15 -> 8 -> 9.5 (%s)" % [seen])
	rig.zoom = 1
	rig.zoom_in()
	ok(rig.zoom == 0 and rig.distance() == 8.0, "zoom_in goes to 8 m")
	rig.zoom_in()
	ok(rig.zoom == 0, "zoom_in clamps at the closest")
	rig.zoom_out()
	rig.zoom_out()
	ok(rig.zoom == 2 and rig.distance() == 15.0, "zoom_out goes to 15 m")
	rig.zoom_out()
	ok(rig.zoom == 2, "zoom_out clamps at the widest")
	rig.rotate_step(-1)
	ok(rig.yaw_step == 7, "turning works in the zoo (45 degree steps)")
	var goal: Dictionary = rig.goal_pose()
	ok(is_equal_approx(goal["distance"], 15.0), "the goal pose uses distance()")
	_free(rig)


func test_town_unchanged() -> void:
	var rig := _rig()
	ok(not rig.on_zoo and rig.zoom == 0 and is_equal_approx(rig.distance(), 9.5), "town starts at 9.5 m")
	rig.toggle_zoom()
	ok(rig.zoom == 1 and is_equal_approx(rig.distance(), 15.0), "town toggle goes to 15 m")
	rig.toggle_zoom()
	ok(rig.zoom == 0 and is_equal_approx(rig.distance(), 9.5), "town toggle goes back to 9.5 m")
	rig.zoom_out()
	rig.zoom_out()
	ok(rig.zoom == 1, "town zoom_out clamps at 15 m")
	rig.zoom_in()
	rig.zoom_in()
	ok(rig.zoom == 0, "town zoom_in clamps at 9.5 m")
	rig.rotate_step(-1)
	ok(rig.yaw_step == 7, "town turns in eight steps")
	rig.set_room(true)
	rig.rotate_step(1)
	ok(rig.yaw_step == 7, "rooms do not turn")
	ok(is_equal_approx(rig.goal_pose()["distance"], CameraRig.ROOM_DISTANCE), "the room camera keeps its distance")
	rig.set_room(false)
	_free(rig)


func test_reduce_motion() -> void:
	# In the zoo with Reduce Motion one step reaches the goal; in town the glide is unchanged.
	var rig := _rig()
	rig.enter_zoo()
	rig.reduce_motion = true
	rig.rotate_step(2)
	rig.zoom_out()
	var goal: Dictionary = rig.goal_pose()
	rig._update(0.1)
	ok(rig.camera.global_position.is_equal_approx(CameraRig.pose_xform(goal["focus"], goal["yaw"], goal["distance"]).origin), "zoo + reduce_motion: a turn and a zoom are already at the goal after one step")
	rig.target.global_position = Vector3(5, 0, 5)
	rig._update(0.1)
	var g2: Dictionary = rig.goal_pose()
	ok(rig.camera.global_position.is_equal_approx(CameraRig.pose_xform(g2["focus"], g2["yaw"], g2["distance"]).origin), "zoo + reduce_motion: following snaps as well")
	rig.leave_zoo()
	_free(rig)
	var town := _rig()
	town.reduce_motion = true   # on its own it does nothing in town
	town.rotate_step(2)
	var tg: Dictionary = town.goal_pose()
	town._update(0.1)
	var goal_pos: Vector3 = CameraRig.pose_xform(tg["focus"], tg["yaw"], tg["distance"]).origin
	ok(not town.camera.global_position.is_equal_approx(goal_pos), "town with reduce_motion still glides")
	_free(town)
	var glide := _rig()
	glide.enter_zoo()
	glide.rotate_step(2)
	var gg: Dictionary = glide.goal_pose()
	glide._update(0.1)
	ok(not glide.camera.global_position.is_equal_approx(CameraRig.pose_xform(gg["focus"], gg["yaw"], gg["distance"]).origin), "zoo without reduce_motion still glides")
	_free(glide)
