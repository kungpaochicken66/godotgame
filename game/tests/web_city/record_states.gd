## Records the City states for the Three.js city's desktop harness (js/harness.js, ?harness=1): the real
## authority rules (core/city_rules.gd, ticked as net/city.gd does with no child in the city) run for
## DURATION seconds at 60 Hz, and every SEND_EVERY seconds the state in its client form
## (city.decode(rules.pack()), exactly what a device draws) is written in the web_json convention.
##   scripts/godot.sh --headless --path game --script res://tests/web_city/record_states.gd -- [--out=/abs/states.json]
## Without --out it writes res://web_city/dev/states.json. Numbers are rounded to 1e-5 to keep the file small
## (the harness only plays it back; parity tests do not read it).
extends SceneTree

const CityRules := preload("res://scripts/core/city_rules.gd")
const WebJson := preload("res://scripts/web/web_json.gd")

const DURATION := 120.0
const HZ := 60.0
const SEND_EVERY := 0.25
const ROUND := 1e-5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://web_city/dev/states.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# The City autoload (net/city.gd) is looked up at run time: in script mode its script cannot be preloaded
	# (it names the Session autoload). Only its static decode() is used.
	var city: Node = root.get_node_or_null("City")
	if city == null or not city.has_method("decode"):
		push_error("the City autoload is missing")
		quit(1)
		return
	var rules = CityRules.new()
	var states: Array = []
	var send := 0.0
	var steps := int(round(DURATION * HZ))
	for k in steps + 1:
		send -= 1.0 / HZ if k > 0 else 0.0
		if send <= 1e-9:
			send += SEND_EVERY
			var s: Dictionary = city.decode(rules.pack())
			if s.is_empty():
				push_error("decode failed at %.3f" % rules.time)
				quit(1)
				return
			states.append(_rounded(WebJson.value(s)))
		if k < steps:
			rules.tick(1.0 / HZ, [])
	var text := JSON.stringify({"version": 1, "source": "tests/web_city/record_states.gd", "hz": HZ,
		"send_every": SEND_EVERY, "states": states}, "", false)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("WEB CITY STATES OK: %d states over %.1f s, %d bytes -> %s" % [states.size(), DURATION, text.length(), path])
	quit(0)


static func _rounded(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return snappedf(float(v), ROUND)
		TYPE_DICTIONARY:
			var d := {}
			for key in v:
				d[key] = _rounded(v[key])
			return d
		TYPE_ARRAY:
			var arr: Array = []
			for e in v:
				arr.append(_rounded(e))
			return arr
	return v
