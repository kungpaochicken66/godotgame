## Compiles every game and test script inside the project (autoloads known),
## so a typing or parse error fails here instead of inside a long test run.
## Pass: "PARSE PASS" and no "SCRIPT ERROR" / "Parse Error" line in the output.
##   scripts/godot.sh --headless --path game -s res://tests/parse_all.gd
extends SceneTree


func _initialize() -> void:
	var bad := 0
	var n := 0
	for dir in ["res://scripts", "res://tests"]:
		for path in _scripts(dir):
			if path == get_script().resource_path:
				continue
			n += 1
			# Normal cached loading: recompiling a script that is already running (an
			# autoload) can crash the engine. Autoloads compiled at startup, where any
			# error prints SCRIPT ERROR to the log (scan it as well).
			var s := load(path) as GDScript
			if s == null or not s.can_instantiate():
				print("PARSE FAIL %s" % path)
				bad += 1
	print("PARSE %s: %d scripts, %d failures" % ["PASS" if bad == 0 else "FAIL", n, bad])
	quit(1 if bad else 0)


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
