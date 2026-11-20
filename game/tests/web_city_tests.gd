## Headless tests for the web city's bridge (design/city-threejs.md 6.3; scripts/web/web_city_bridge.gd):
## the desktop HTTP server (types, traversal refused, a missing file, a wrong method), the WebSocket link with
## a scripted page (hello on ready, the frame's shape, each child's model before its first frame and the pose
## that fits it, a tap, the action, a weather press and Town reaching the controller, toasts forwarded, bye),
## a child's pack (no name label, the blob shadow's texture described, every pose node a pivot), the perf
## record, the page's copy for iOS, PAGE_STRINGS against js/strings.js (when it exists), and the city's
## export still byte-identical to the checked-in files (mesh_pack.gd's optional fields are off there).
## Nothing renders. End to end with Chromium: node scripts/web_city/e2e.mjs.
##   scripts/godot.sh --headless --path game -s res://tests/web_city_tests.gd
extends SceneTree

const MeshPack := preload("res://scripts/web/mesh_pack.gd")
const Bridge := preload("res://scripts/web/web_city_bridge.gd")

var _checks := 0
var _failures := 0
var _current := ""
var _catcher: ErrorCatcher
var Session: Node
var bridge: Bridge
var ctl: FakeController
var fake_world: FakeWorld
var kid: Node3D


## Collects engine errors (including SCRIPT ERROR) with the test that was running.
class ErrorCatcher extends Logger:
	var owner_test := ""
	var errors: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append({"test": owner_test, "type": error_type, "text": "%s %s (%s:%d)" % [code, rationale, file, line]})
		_lock.unlock()


## The controller's side the bridge uses (play_controller.gd: space_changed, toast, hint, web_*).
class FakeController extends Node:
	signal space_changed(space: String)
	signal toast(text: String)
	signal hint(text: String)
	var calls: Array = []
	var level := ""
	var pos := Vector2(-26.0, 6.0)
	var city_hold := {}

	func web_tap(origin: Vector3, dir: Vector3) -> void:
		calls.append(["tap", origin, dir])

	func web_act() -> void:
		calls.append(["act"])

	func web_weather(w: int) -> void:
		calls.append(["weather", w])

	func web_home() -> void:
		calls.append(["home"])

	func web_ctx() -> Dictionary:
		return {"type": "city_use", "label": "Sit", "icon": "sit"}


## The world's side: the children and the cutaway (town_world.gd kids, web_cutaway()).
class FakeWorld extends Node3D:
	var kids := {}
	var cut := {"hidden": {}, "regions": [], "rev": 0}

	func web_cutaway() -> Dictionary:
		return cut.duplicate(true)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s] %s" % [_current, what])


func _initialize() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Session = root.get_node("Session")
	_run.call_deferred()


func _run() -> void:
	_setup()
	for t in ["test_paths", "test_http", "test_kid_pack", "test_ws", "test_perf_log", "test_copy", "test_page_strings", "test_export_unchanged"]:
		_current = t
		_catcher.owner_test = t
		await call(t)
	_current = "engine errors"
	for e in _catcher.errors:
		ok(false, "unexpected engine error in %s: %s" % [e["test"], e["text"]])
	bridge.stop_servers()
	print("\nWEB CITY TESTS: %d checks, %d failures" % [_checks, _failures])
	await root.get_node("Music").stop_for_exit()
	quit(1 if _failures > 0 else 0)


func _setup() -> void:
	fake_world = FakeWorld.new()
	root.add_child(fake_world)
	kid = load("res://scripts/art/kid.gd").new()
	fake_world.add_child(kid)
	var wear := {}
	var W = load("res://scripts/core/wearables.gd")
	for id in W.items():
		var slot: String = W.get_def(id)["slot"]
		if slot in ["top", "shoes", "hand"] and not wear.has(slot) and not W.get_def(id).get("sit", false):
			wear[slot] = id
	kid.setup({"nick": "Ana", "skin": 1, "hair": 2, "hair_color": 1, "outfit": 0, "outfit_color": 2, "wear": wear})
	kid.position = Vector3(-26.0, 0.0, 6.0)
	fake_world.kids[int(Session.my_id)] = kid
	ctl = FakeController.new()
	root.add_child(ctl)
	bridge = Bridge.new()
	var base := 21000 + randi() % 20000
	bridge.http_port = base
	bridge.ws_port = base + 1
	root.add_child(bridge)
	bridge.controller = ctl
	bridge.world = fake_world
	ctl.space_changed.connect(bridge._on_space_changed)
	ctl.toast.connect(func(text: String): bridge._forward_text("toast", text))
	ctl.hint.connect(func(text: String): bridge._forward_text("hint", text))


func _frames(n := 1) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ paths and HTTP

func test_paths() -> void:
	ok(Bridge.resolve_path("/index.html") == "res://web_city/index.html", "/index.html maps into res://web_city")
	ok(Bridge.resolve_path("/") == "res://web_city/index.html", "/ is the index")
	ok(Bridge.resolve_path("/js/main.js?ws=8781#x") == "res://web_city/js/main.js", "a query and a fragment are ignored")
	ok(Bridge.resolve_path("/js/%6Dain.js") == "res://web_city/js/main.js" and Bridge.resolve_path("/js/%6dain.js") == "res://web_city/js/main.js",
		"percent-encoding is decoded (either case)")
	ok(Bridge.percent_decode("/a%2") == "" and Bridge.percent_decode("/a%-1") == "" and Bridge.percent_decode("/%C3%A9") == ""
		and Bridge.percent_decode("/%FF") == "" and Bridge.percent_decode("/%2e%2E") == "/..", "malformed escapes and non-ASCII are refused")
	for bad in ["/../project.godot", "/js/../../project.godot", "/%2e%2e/project.godot", "/js/%2E%2E/%2E%2E/project.godot",
			"/..%2fproject.godot", "/js\\..\\..\\project.godot", "/res://project.godot", "/user://x", "index.html", "/a%00.js", ""]:
		ok(Bridge.resolve_path(bad) == "", "refused: %s" % bad)
	ok(Bridge.content_type("a/b/main.js") == "text/javascript; charset=utf-8", "a module is text/javascript")
	ok(Bridge.content_type("index.html").begins_with("text/html"), "html is text/html")
	ok(Bridge.content_type("data/city.json") == "application/json", "json is application/json")
	ok(Bridge.content_type("data/city.bin") == "application/octet-stream", "bin is octet-stream")


## One raw HTTP exchange with the bridge's server: {"status", "headers" (lower-case names), "body"}.
func _http(request: String) -> Dictionary:
	var c := StreamPeerTCP.new()
	c.connect_to_host("127.0.0.1", bridge.http_port)
	var buf := PackedByteArray()
	var sent := false
	for i in 600:
		await process_frame
		c.poll()
		var st := c.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				c.put_data(request.to_ascii_buffer())
				sent = true
			var n := c.get_available_bytes()
			if n > 0:
				buf.append_array(c.get_partial_data(n)[1])
		elif sent and (st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR):
			break
		var r := _parse_http(buf)
		if not r.is_empty() and (r["body"] as PackedByteArray).size() >= int(r["headers"].get("content-length", "0")):
			c.disconnect_from_host()
			return r
	c.disconnect_from_host()
	return _parse_http(buf)


static func _parse_http(buf: PackedByteArray) -> Dictionary:
	var sep := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			sep = i
			break
	if sep < 0:
		return {}
	var head := buf.slice(0, sep).get_string_from_ascii().split("\r\n")
	var headers := {}
	for h in head.slice(1):
		var k := h.get_slice(":", 0).strip_edges().to_lower()
		headers[k] = h.substr(h.find(":") + 1).strip_edges()
	return {"status": int(head[0].get_slice(" ", 1)), "headers": headers, "body": buf.slice(sep + 4)}


func test_http() -> void:
	ok(bridge.start_servers(), "the servers listen on 127.0.0.1:%d and :%d" % [bridge.http_port, bridge.ws_port])
	ok(bridge.url == "http://127.0.0.1:%d/index.html?ws=%d" % [bridge.http_port, bridge.ws_port], "the page's address (%s)" % bridge.url)
	var r := await _http("GET /index.html?ws=1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
	ok(r.get("status", 0) == 200, "index.html: 200 (%s)" % r.get("status"))
	ok(str(r.get("headers", {}).get("content-type", "")).begins_with("text/html"), "index.html is text/html")
	ok(r.get("body", PackedByteArray()) == FileAccess.get_file_as_bytes("res://web_city/index.html"), "index.html's bytes are the file's")
	r = await _http("GET /js/main.js HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
	ok(r.get("status", 0) == 200 and str(r.get("headers", {}).get("content-type", "")).begins_with("text/javascript"),
		"a module is served as text/javascript (%s, %s)" % [r.get("status"), r.get("headers", {}).get("content-type")])
	ok(r.get("body", PackedByteArray()) == FileAccess.get_file_as_bytes("res://web_city/js/main.js"), "main.js's bytes are the file's")
	r = await _http("GET /data/city.bin HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
	ok(r.get("status", 0) == 200 and (r.get("body", PackedByteArray()) as PackedByteArray).size() == FileAccess.get_file_as_bytes("res://web_city/data/city.bin").size(),
		"the city's 7 MB binary arrives whole (%d bytes)" % (r.get("body", PackedByteArray()) as PackedByteArray).size())
	for bad in ["/../project.godot", "/js/../../project.godot", "/%2e%2e/project.godot", "/..%2f..%2fproject.godot"]:
		r = await _http("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % bad)
		ok(r.get("status", 0) == 403, "traversal refused: %s (%s)" % [bad, r.get("status")])
	r = await _http("GET /nothing-here.js HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
	ok(r.get("status", 0) == 404, "a missing file: 404 (%s)" % r.get("status"))
	r = await _http("POST /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n")
	ok(r.get("status", 0) == 405, "POST: 405 (%s)" % r.get("status"))
	# Only the loopback address listens: nothing answers on another of this host's addresses.
	var other := ""
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127."):
			other = a
			break
	if other != "":
		var c := StreamPeerTCP.new()
		c.connect_to_host(other, bridge.http_port)
		var reached := false
		for i in 30:
			await process_frame
			c.poll()
			if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				reached = true
				break
			if c.get_status() == StreamPeerTCP.STATUS_ERROR:
				break
		c.disconnect_from_host()
		ok(not reached, "the server is not reachable on %s" % other)


# ------------------------------------------------------------------ the child's pack

func test_kid_pack() -> void:
	await _frames(2)
	var m: Dictionary = Bridge.build_kid_model(7, kid, 1)
	var msg: Dictionary = m["msg"]
	var header: Dictionary = msg["pack"]
	var nodes: Array = header["nodes"]
	ok(msg["t"] == "kid_model" and msg["id"] == 7 and msg["rev"] == 1 and msg["nick"] == str(kid.avatar.get("nick", "")) and msg["nick"] != "", "kid_model's fields")
	ok(nodes.size() == (m["tracked"] as Array).size() and nodes.size() > 10, "every packed node is tracked (%d)" % nodes.size())
	ok(Marshalls.base64_to_raw(msg["bin"]).size() == int(header["bytes"]), "the base64 binary has the header's size")
	var names := nodes.map(func(n): return str(n["name"]))
	for want in ["Body", "LegL", "LegR", "ArmL", "ArmR", "Head"]:
		ok(names.has(want), "the rig's %s is packed" % want)
	var labels := (m["tracked"] as Array).filter(func(n): return n is Label3D)
	ok(labels.is_empty(), "the name label is left out")
	ok(nodes[0]["xf"] == MeshPack.Pack.xf12(Transform3D.IDENTITY), "the root is packed at identity (the frame places it)")
	var pivots := (msg["pose_nodes"] as Array).map(func(i): return m["tracked"][i])
	ok(pivots.all(func(n): return not (n is GeometryInstance3D)), "every pose node is a pivot")
	ok(pivots.any(func(n): return str(n.name) == "LegL") and pivots.any(func(n): return str(n.name) == "Body"), "the legs and body are posed")
	var textured: Array = header["materials"].values().filter(func(d): return d.has("texture"))
	ok(textured.size() == 1 and textured[0]["texture"]["kind"] == "gradient" and textured[0]["texture"]["fill"] == "radial",
		"the blob shadow's gradient is described (%s)" % str(textured.map(func(d): return d["texture"].get("kind"))))
	var uv_surfaces := 0
	for mesh in header["meshes"]:
		for s in mesh["surfaces"]:
			ok(s.has("uv"), "a child's surface says whether it has UVs")
			if int(s.get("uv", -1)) >= 0:
				uv_surfaces += 1
	ok(uv_surfaces >= 1, "the shadow's quad carries UVs (%d surfaces)" % uv_surfaces)
	var pose := Bridge.pose_of(m)
	ok((pose["x"] as Array).size() == 12 * (msg["pose_nodes"] as Array).size(), "the pose has 12 numbers per pose node (%d)" % (pose["x"] as Array).size())
	ok((pose["v"] as Array).size() == ceili(float(msg["vis_count"]) / Bridge.VIS_BITS), "the visibility words cover every node")
	ok(int(pose["v"][0]) & 1 == 1, "the root's bit says the child is visible")
	# A posed leg shows in the pose: walking swings the legs.
	kid.anim = "walk"
	await _frames(5)
	var li: int = (m["tracked"] as Array).find(kid.get_node("Body/LegL"))
	var k := (msg["pose_nodes"] as Array).find(li)
	var leg_xf: Array = Bridge.pose_of(m)["x"].slice(k * 12, k * 12 + 12)
	var real: Transform3D = kid.get_node("Body/LegL").transform
	ok(absf(float(leg_xf[4]) - real.basis.y.y) < 0.001 and absf(float(leg_xf[5]) - real.basis.y.z) < 0.001, "the leg's local transform is the rig's")
	kid.anim = "idle"
	var t0 := Time.get_ticks_usec()
	Bridge.build_kid_model(7, kid, 2)
	print("  a child's pack: %d nodes, %d bytes, %d ms to build" % [nodes.size(), int(header["bytes"]), (Time.get_ticks_usec() - t0) / 1000])
	var a := Bridge.rig_key(kid)
	kid.setup(kid.avatar)
	ok(Bridge.rig_key(kid) != a, "a rebuilt rig has a new key (a new look is sent again)")


# ------------------------------------------------------------------ the WebSocket link

var _got: Array = []


func _pump(c: WebSocketPeer) -> void:
	c.poll()
	while c.get_available_packet_count() > 0:
		var v = JSON.parse_string(c.get_packet().get_string_from_utf8())
		if v is Dictionary:
			_got.append(v)


func _wait_for(c: WebSocketPeer, cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		await process_frame
		_pump(c)
		if cond.call():
			return true
	return false


func _of(t: String) -> Array:
	return _got.filter(func(m): return m.get("t", "") == t)


func test_ws() -> void:
	var c := WebSocketPeer.new()
	c.inbound_buffer_size = 16 << 20
	ok(c.connect_to_url("ws://127.0.0.1:%d" % bridge.ws_port) == OK, "a page connects")
	ok(await _wait_for(c, func(): return c.get_ready_state() == WebSocketPeer.STATE_OPEN), "the socket opens")
	await _frames(10)
	_pump(c)
	ok(_got.is_empty(), "nothing is sent while the child is not in the web city (%d)" % _got.size())
	ctl.space_changed.emit("city_web")
	ok(bridge.active, "the bridge is active in city_web")
	ok(await _wait_for(c, func(): return not _of("hello").is_empty()), "a connected page is greeted on entering")
	_got.clear()
	c.send_text(JSON.stringify({"t": "ready", "v": 1, "w": 1280, "h": 720, "dpr": 1, "load_ms": 10, "failed": [], "ua": "test"}))
	ok(await _wait_for(c, func(): return not _of("hello").is_empty() and not _of("frame").is_empty()), "hello on ready, then frames")
	var hello: Dictionary = _of("hello")[0] if not _of("hello").is_empty() else {}
	ok(hello.get("v") == 1.0 and hello.get("map") == "city_web" and hello.get("platform") == "desktop" and hello.get("strings") is Dictionary
		and int(hello.get("me", -1)) == int(Session.my_id) and str(hello.get("locale", "")) != "", "hello's fields (%s)" % str(hello.keys()))
	ok(bridge.page_ready and bridge.last_ready.get("w") == 1280.0, "ready is recorded")
	ok(await _wait_for(c, func(): return not _of("kid_model").is_empty()), "the child's model arrives")
	var first_model := _got.find(_of("kid_model")[0]) if not _of("kid_model").is_empty() else -1
	var first_frame_with := -1
	for i in _got.size():
		if _got[i].get("t") == "frame" and not (_got[i]["kids"] as Array).is_empty():
			first_frame_with = i
			break
	ok(first_model >= 0 and first_model < first_frame_with, "the model comes before the first frame that has the child (%d < %d)" % [first_model, first_frame_with])
	ok(_of("kid_model").size() == 1, "one model per look (%d)" % _of("kid_model").size())
	var f: Dictionary = _of("frame")[-1]
	ok(f.has("clock") and f["me"] is Dictionary and f["kids"] is Array, "the frame's shape")
	var me: Dictionary = f["me"]
	for key in ["id", "level", "pos", "riding", "hold", "ctx"]:
		ok(me.has(key), "frame.me has %s" % key)
	ok(me.get("ctx") is Dictionary and me["ctx"].get("label") == "Sit", "frame.me.ctx is the action button")
	var k0: Dictionary = (f["kids"] as Array)[0] if not (f["kids"] as Array).is_empty() else {}
	for key in ["id", "me", "rev", "xf", "anim", "ride", "pose", "level"]:
		ok(k0.has(key), "frame.kids[] has %s" % key)
	ok(k0.get("me") == true and (k0.get("xf", []) as Array).size() == 12 and absf(float(k0["xf"][9]) + 26.0) < 0.01, "the child's world transform")
	var model: Dictionary = _of("kid_model")[0]
	ok((k0["pose"]["x"] as Array).size() == 12 * (model["pose_nodes"] as Array).size(), "the frame's pose fits the model")
	ok(k0["rev"] == model["rev"], "the frame names the model's revision")
	# A new look: a new revision, sent once.
	kid.setup(kid.avatar)
	ok(await _wait_for(c, func(): return _of("kid_model").size() == 2), "a new look sends the model again")
	ok(_of("kid_model")[-1]["rev"] == model["rev"] + 1, "with the next revision")
	# The cutaway: sent on a new revision only.
	_got.clear()
	fake_world.cut = {"hidden": {"office": 1}, "regions": ["office_2"], "rev": 5}
	ok(await _wait_for(c, func(): return not _of("cutaway").is_empty()), "a cutaway change is sent")
	await _frames(10)
	_pump(c)
	ok(_of("cutaway").size() == 1 and _of("cutaway")[0]["regions"] == ["office_2"] and float(_of("cutaway")[0]["hidden"].get("office", 0)) == 1.0,
		"once, with what the world hides")
	# Input from the page reaches the controller.
	ctl.calls.clear()
	c.send_text(JSON.stringify({"t": "tap", "o": [1, 20, 3], "d": [0, -1, 0]}))
	c.send_text(JSON.stringify({"t": "tap", "o": [1, 20], "d": [0, -1, 0]}))
	c.send_text(JSON.stringify({"t": "act"}))
	c.send_text(JSON.stringify({"t": "weather", "w": 2}))
	c.send_text(JSON.stringify({"t": "look", "on": true}))
	c.send_text(JSON.stringify({"t": "pause", "on": true}))
	c.send_text(JSON.stringify({"t": "home"}))
	await _wait_for(c, func(): return ctl.calls.size() >= 4)
	ok(ctl.calls.size() >= 1 and ctl.calls[0] == ["tap", Vector3(1, 20, 3), Vector3(0, -1, 0)], "a tap reaches web_tap with its ray (%s)" % str(ctl.calls))
	ok(ctl.calls.size() == 4 and ctl.calls[1] == ["act"] and ctl.calls[2] == ["weather", 2] and ctl.calls[3] == ["home"],
		"a malformed tap is dropped; act, weather and Town arrive (%s)" % str(ctl.calls))
	ok(bridge.look_on and bridge.pause_on, "Look and Pause are recorded")
	# Toasts and hints are forwarded while in the web city.
	_got.clear()
	ctl.toast.emit("Hello")
	ctl.hint.emit("That place can't be reached from here.")
	ok(await _wait_for(c, func(): return not _of("toast").is_empty() and not _of("hint").is_empty()), "toast and hint are forwarded")
	# A reconnecting page is greeted again and gets the model again.
	var c2 := WebSocketPeer.new()
	c2.inbound_buffer_size = 16 << 20
	c2.connect_to_url("ws://127.0.0.1:%d" % bridge.ws_port)
	var got2: Array = []
	var seen_model := false
	for i in 300:
		await process_frame
		_pump(c)
		c2.poll()
		while c2.get_available_packet_count() > 0:
			var v = JSON.parse_string(c2.get_packet().get_string_from_utf8())
			if v is Dictionary:
				got2.append(v.get("t"))
		if got2.has("hello") and got2.has("kid_model"):
			seen_model = true
			break
	ok(seen_model, "a page that comes back gets hello and the models again (%s)" % str(got2.slice(0, 6)))
	c2.close()
	# Leaving: bye, then the socket closes; the controller's toasts no longer go to the page.
	_got.clear()
	ctl.space_changed.emit("town")
	ok(not bridge.active, "the bridge is inactive in town")
	ok(await _wait_for(c, func(): return not _of("bye").is_empty()), "the page gets bye")
	ok(await _wait_for(c, func(): return c.get_ready_state() == WebSocketPeer.STATE_CLOSED, 200), "and the socket closes after it")
	var after := _got.filter(func(m): return m.get("t") == "frame" and _got.find(m) > _got.find(_of("bye")[0]))
	ok(after.is_empty(), "no frame after bye")
	ctl.calls.clear()
	bridge.handle_page({"t": "tap", "o": [0, 10, 0], "d": [0, -1, 0]})
	ok(ctl.calls.is_empty(), "a tap outside the web city does nothing")


# ------------------------------------------------------------------ records

func test_perf_log() -> void:
	var before := FileAccess.get_file_as_string(Bridge.PERF_LOG).length() if FileAccess.file_exists(Bridge.PERF_LOG) else 0
	bridge.handle_page({"t": "perf", "fps": 59.5, "p50": 16.6, "p95": 18.0, "max": 30.0, "calls": 120, "triangles": 1000, "geometries": 10, "textures": 2, "heap": null})
	ok(absf(bridge.frame_hz() - 59.5 * Bridge.PAGE_RATE) < 0.01, "frames follow the page's own rate (%.1f a second)" % bridge.frame_hz())
	bridge.handle_page({"t": "perf", "fps": 0.8})
	ok(bridge.frame_hz() == Bridge.MIN_FRAME_HZ, "a very slow page still gets %.0f frames a second" % Bridge.MIN_FRAME_HZ)
	bridge.page_fps = 0.0
	ok(bridge.frame_hz() == Bridge.FRAME_HZ, "before any perf sample: at most %.0f" % Bridge.FRAME_HZ)
	var text := FileAccess.get_file_as_string(Bridge.PERF_LOG)
	var last = JSON.parse_string(text.substr(before).strip_edges().split("\n")[0])
	ok(last is Dictionary and last.get("fps") == 59.5 and last.get("platform") == "desktop" and last.get("model") == OS.get_model_name()
		and last.has("unix") and not last.has("t"), "a perf sample is appended with the platform and the device model")


func test_copy() -> void:
	var b2 := Bridge.new()
	var dir := b2.ensure_copy()
	ok(dir.begins_with(Bridge.COPY_ROOT + "/") and FileAccess.file_exists(dir.path_join(".complete")), "the page is copied for the web view (%s)" % dir)
	ok(FileAccess.get_file_as_bytes(dir.path_join("js/main.js")) == FileAccess.get_file_as_bytes("res://web_city/js/main.js")
		and FileAccess.get_file_as_bytes(dir.path_join("data/city.bin")).size() == FileAccess.get_file_as_bytes("res://web_city/data/city.bin").size(),
		"the copy's files are the page's")
	ok(not DirAccess.dir_exists_absolute(dir.path_join("dev")), "the harness's recordings are not copied")
	var b3 := Bridge.new()
	ok(b3.ensure_copy() == dir, "the same content gives the same folder")
	b2.free()
	b3.free()
	Bridge._remove_tree(Bridge.COPY_ROOT)


# ------------------------------------------------------------------ the page's words

## The string literals of `const PAGE_STRINGS = [...]` (or `export const PAGE_STRINGS = [...]`) in a JS file.
static func js_page_strings(text: String) -> Variant:
	var at := text.find("PAGE_STRINGS")
	if at < 0:
		return null
	var open := text.find("[", at)
	var close := -1
	var depth := 0
	var i := open
	var quote := ""
	while i >= 0 and i < text.length():
		var ch := text[i]
		if quote != "":
			if ch == "\\":
				i += 1
			elif ch == quote:
				quote = ""
		elif ch == "'" or ch == "\"" or ch == "`":
			quote = ch
		elif ch == "[":
			depth += 1
		elif ch == "]":
			depth -= 1
			if depth == 0:
				close = i
				break
		i += 1
	if open < 0 or close < 0:
		return null
	var body := text.substr(open + 1, close - open - 1)
	var re := RegEx.new()
	re.compile("'((?:[^'\\\\]|\\\\.)*)'|\"((?:[^\"\\\\]|\\\\.)*)\"")
	var out: Array = []
	for m in re.search_all(body):
		var s := m.get_string(1) if m.get_start(1) >= 0 else m.get_string(2)
		out.append(s.c_unescape())
	return out


func test_page_strings() -> void:
	var path := "res://web_city/js/strings.js"
	if not FileAccess.file_exists(path):
		print("  SKIP js/strings.js is not there yet: PAGE_STRINGS (%d) not compared" % Bridge.PAGE_STRINGS.size())
		return
	var js = js_page_strings(FileAccess.get_file_as_string(path))
	ok(js is Array, "js/strings.js has a PAGE_STRINGS array")
	if js is Array:
		ok(Array(Bridge.PAGE_STRINGS) == js, "the bridge's PAGE_STRINGS equal js/strings.js's (%d and %d)" % [Bridge.PAGE_STRINGS.size(), (js as Array).size()])


# ------------------------------------------------------------------ the city's export

func test_export_unchanged() -> void:
	var out := OS.get_user_data_dir().path_join("lantern_web_city_export_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var log: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/web_city/export.gd", "--", "--out=" + out], log, true)
	ok(code == 0, "the export runs (%d)" % code)
	for f in ["city.json", "city.bin", "consts.json"]:
		var fresh := FileAccess.get_file_as_bytes(out.path_join(f))
		var kept := FileAccess.get_file_as_bytes("res://web_city/data/" + f)
		ok(fresh.size() > 0 and fresh == kept, "data/%s equals a fresh export (%d / %d bytes)" % [f, fresh.size(), kept.size()])
		DirAccess.remove_absolute(out.path_join(f))
	DirAccess.remove_absolute(out)
