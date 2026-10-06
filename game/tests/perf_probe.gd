## Reports rendering cost of the default town (draw calls, objects, primitives,
## frame rate). Frame rate under the software renderer says nothing about iPad
## performance; draw calls and primitives are the portable numbers.
extends Node

var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	while not main.thumbs.is_done:
		await get_tree().process_frame
	var save := "user://perf_town.json"
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(save)
	Session.start_solo(save, main.menus.avatar)
	for zoom in [0, 1]:
		main.rig.zoom = zoom
		await get_tree().create_timer(3.0).timeout
		var frames := Engine.get_frames_drawn()
		await get_tree().create_timer(4.0).timeout
		print("PERF zoom=%d draw_calls=%d objects=%d primitives=%d fps=%.1f" % [zoom,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			(Engine.get_frames_drawn() - frames) / 4.0])
	get_tree().quit()
