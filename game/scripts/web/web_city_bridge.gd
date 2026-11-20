## The web city's bridge (design/city-threejs.md 6.3, protocol v1): while the local child is on the map
## city_web, a Three.js page draws the city and takes the input, and this node talks to it. Godot stays the
## game: the session, the CityWeb authority, the child's walks and actions.
##
## Transports, chosen once:
##   ios      the WebView plugin (singleton "WebView": open(root_dir, query), close(), post(json), poll(),
##            is_open(), stats()). The page's files are copied once per content hash from res://web_city to
##            user://web_city/<hash>/ (WKWebView serves real files), and the web view covers Godot's view:
##            Godot's HUD canvas layers are hidden and its render loop is off while it shows.
##   desktop  an HTTP server for the page's files (read through FileAccess, so an exported pck works too) and
##            a WebSocket server for the messages, both on 127.0.0.1 only, started the first time the child
##            enters the web city (or at launch with --web-city). Ports: --web-city-http=N (8780) and
##            --web-city-ws=N (8781). The page's address is printed: http://127.0.0.1:8780/index.html?ws=8781
##
## Lifecycle: entering city_web opens the page (iOS) or greets the connected page (desktop); 'ready' (and a
## page reconnecting) gets hello, the newest states, the cutaway and every child's model again; then a frame
## every Godot frame (at most FRAME_HZ a second). Leaving sends 'bye' and closes the web view (iOS) or the
## socket a moment later (desktop: the page reconnects and waits quietly until the city is entered again).
##
## The children (kid_model, frame.kids[].pose): each child's rig (art/kid.gd) is packed once per look
## (scripts/web/mesh_pack.gd with track and textures; the name label left out) and sent with the indices of
## the posed nodes: "pose_nodes" (every plain pivot of the rig, in pack order) and "vis_count" (every packed
## node). A frame's pose is {"x": 12 floats per pose node (its local transform: basis x, y, z columns, then
## origin), "v": visibility bits of every packed node, VIS_BITS per number, node i in v[i / VIS_BITS] bit
## i % VIS_BITS}. The root's transform is the kid's "xf"; its own packed transform is identity.
extends Node

const MeshPack := preload("res://scripts/web/mesh_pack.gd")
const WebJson := preload("res://scripts/web/web_json.gd")
const Places := preload("res://scripts/core/places.gd")

const PROTOCOL := 1
const WEB_MAP := "city_web"
const ROOT := "res://web_city"
const COPY_ROOT := "user://web_city"
const PERF_LOG := "user://web_city_perf.jsonl"
const DEFAULT_HTTP_PORT := 8780
const DEFAULT_WS_PORT := 8781
## At most this many frame messages a second (a headless or uncapped Godot would otherwise flood the page),
## and no more than the page draws: once its perf samples come, about PAGE_RATE times its own frame rate
## (at least MIN_FRAME_HZ), so a slow page (software WebGL, a hot device) is never fed a backlog it reads late.
const FRAME_HZ := 120.0
const MIN_FRAME_HZ := 4.0
const PAGE_RATE := 1.25
const VIS_BITS := 30
const POSE_STEP := 0.0001
const HTTP_MAX_REQUEST := 16384
const HTTP_CHUNK := 262144
const HTTP_TIMEOUT := 20.0
const WS_CLOSE_DELAY := 0.4
const WS_CLOSE_WAIT := 15.0
## Frames are dropped (not queued) while this many bytes wait to go to a page that is behind (a slow page reads
## its socket only between its own frames); every other message is always queued.
const WS_BACKLOG := 262144
## The page's own words (js/strings.js PAGE_STRINGS, mirrored here; tests compare the two). Godot sends
## their translations in hello.strings.
const PAGE_STRINGS: Array[String] = ["City", "Office", "Cafe", "Gym", "Bakery", "Bookstore", "Flower shop", "Ice cream",
	"Ride home", "Reset view", "Look around", "Stop looking", "Pause the city", "Resume", "Sunny", "Rain", "Night",
	"Rotate view left", "Rotate view right", "Zoom"]
const TYPES := {"html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
	"mjs": "text/javascript; charset=utf-8", "json": "application/json", "bin": "application/octet-stream",
	"txt": "text/plain; charset=utf-8", "css": "text/css; charset=utf-8", "png": "image/png", "jpg": "image/jpeg",
	"svg": "image/svg+xml", "wasm": "application/wasm", "ico": "image/x-icon"}

## Every message from the page, parsed (tests and tours listen).
signal page_message(msg: Dictionary)
## Every message to the page (tests record them when record_outbox is on).
var record_outbox := false
var outbox: Array = []

var main: Node
var controller: Node
var world: Node
var platform := "desktop"
var active := false              # the local child is on the web city map
var page_ready := false
var last_ready := {}
var look_on := false
var pause_on := false
var cam := {}
var http_port := DEFAULT_HTTP_PORT
var ws_port := DEFAULT_WS_PORT
var url := ""

var _plugin: Object
var _http: TCPServer
var _ws_server: TCPServer
var _http_conns: Array = []      # {"peer": StreamPeerTCP, "buf": PackedByteArray, "out": PackedByteArray, "off": int, "t": float}
var _ws: Array = []              # {"peer": WebSocketPeer, "greeted": bool, "close_at": float}
var _hidden_layers: Array = []   # [CanvasLayer, was visible]
var _render_was := true
var _models := {}                # peer -> {"key", "rev", "tracked", "pose_nodes", "msg"}
var _sent_rev := {}              # peer -> the rev the current page has
var _cut_key := ""
var _frame_t := 0.0
var _now := 0.0
var _copied_dir := ""
var dropped := 0                 # frames not sent to a page that was behind
var page_fps := 0.0              # the page's own frame rate (its newest perf sample; 0 before one)
var bench_phase := ""           # set by scripts/web/city_bench.gd while a benchmark runs (tags the perf lines)
var bench_run := ""


func _ready() -> void:
	if OS.get_name() == "iOS":
		platform = "ios"
		if Engine.has_singleton("WebView"):
			_plugin = Engine.get_singleton("WebView")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--web-city-http="):
			http_port = int(a.get_slice("=", 1))
		elif a.begins_with("--web-city-ws="):
			ws_port = int(a.get_slice("=", 1))
	if platform == "desktop" and OS.get_cmdline_user_args().has("--web-city"):
		start_servers()


## Connects to the game (main.gd calls it once the controller and the world exist).
func bind(m: Node) -> void:
	main = m
	controller = m.get("controller")
	world = m.get("world")
	if controller:
		controller.space_changed.connect(_on_space_changed)
		controller.toast.connect(func(text: String): _forward_text("toast", text))
		controller.hint.connect(func(text: String): _forward_text("hint", text))
	var cw := city()
	if cw:
		cw.updated.connect(_on_states)
		cw.effect.connect(_on_effect)


func city() -> Node:
	return get_node_or_null("/root/CityWeb")


# ------------------------------------------------------------------ lifecycle

func _on_space_changed(space: String) -> void:
	var on := space == WEB_MAP
	if on == active:
		return
	active = on
	if on:
		_enter()
	else:
		_leave()


func _enter() -> void:
	_sent_rev.clear()
	_cut_key = ""
	if platform == "ios":
		_open_web_view()
		return
	start_servers()
	print("WEB CITY URL %s" % url)
	var open := false
	for c in _ws:
		c["close_at"] = -1.0
		open = open or (c["peer"] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN
	if open:
		_greet()


func _leave() -> void:
	send({"t": "bye"})
	page_ready = false
	page_fps = 0.0
	look_on = false
	pause_on = false
	if platform == "ios":
		_close_web_view()
		return
	for c in _ws:
		c["close_at"] = _now + WS_CLOSE_DELAY


## hello, the newest states and cutaway, and every child's model again (a page that is ready or came back).
func _greet() -> void:
	if not active:
		return
	var strings := {}
	for s in PAGE_STRINGS:
		strings[s] = tr(s)
	send({"t": "hello", "v": PROTOCOL, "me": _my_id(), "map": WEB_MAP, "platform": platform,
		"locale": TranslationServer.get_locale(), "strings": strings})
	_sent_rev.clear()
	_cut_key = ""
	var cw := city()
	if cw:
		send({"t": "states", "s": WebJson.value(cw.states)})


func _my_id() -> int:
	var s := get_node_or_null("/root/Session")
	return int(s.my_id) if s else 0


# ------------------------------------------------------------------ iOS: the web view

func _open_web_view() -> void:
	if _plugin == null:
		push_warning("web city: no WebView plugin")
		return
	var dir := ensure_copy()
	if dir == "":
		push_warning("web city: the page's files could not be copied")
		return
	if not bool(_plugin.call("open", ProjectSettings.globalize_path(dir), "platform=ios")):
		push_warning("web city: the web view did not open")
		return
	_hidden_layers.clear()
	if main:
		for c in main.get_children():
			if c is CanvasLayer:
				_hidden_layers.append([c, (c as CanvasLayer).visible])
				(c as CanvasLayer).visible = false
	_render_was = RenderingServer.render_loop_enabled
	RenderingServer.render_loop_enabled = false


func _close_web_view() -> void:
	if _plugin and bool(_plugin.call("is_open")):
		_plugin.call("close")
	for pair in _hidden_layers:
		if is_instance_valid(pair[0]):
			(pair[0] as CanvasLayer).visible = pair[1]
	_hidden_layers.clear()
	RenderingServer.render_loop_enabled = _render_was


## The page's files as real files: user://web_city/<content hash>/, copied once (older copies removed).
## Returns the folder, or "" when a file could not be written.
func ensure_copy() -> String:
	if _copied_dir != "":
		return _copied_dir
	var files := list_files(ROOT)
	files = files.filter(func(p: String): return not p.begins_with("dev/"))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for rel in files:
		ctx.update(("%s\n%s\n" % [rel, FileAccess.get_md5(ROOT.path_join(rel))]).to_utf8_buffer())
	var hash := ctx.finish().hex_encode().substr(0, 16)
	var dir := COPY_ROOT.path_join(hash)
	if not (FileAccess.file_exists(dir.path_join(".complete")) and FileAccess.file_exists(dir.path_join("index.html"))):
		for rel in files:
			var dst := dir.path_join(rel)
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var f := FileAccess.open(dst, FileAccess.WRITE)
			if f == null:
				return ""
			f.store_buffer(FileAccess.get_file_as_bytes(ROOT.path_join(rel)))
			f.close()
		var done := FileAccess.open(dir.path_join(".complete"), FileAccess.WRITE)
		if done == null:
			return ""
		done.store_string(hash)
		done.close()
	var top := DirAccess.open(COPY_ROOT)
	if top:
		for d in top.get_directories():
			if d != hash:
				_remove_tree(COPY_ROOT.path_join(d))
	_copied_dir = dir
	return dir


## Every file below `root` (relative paths, sorted).
static func list_files(root: String, rel := "") -> Array:
	var out: Array = []
	var d := DirAccess.open(root.path_join(rel))
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid") or f.begins_with("."):
			continue
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(list_files(root, rel.path_join(sub) if rel != "" else sub))
	out.sort()
	return out


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true   # the ".complete" marker too
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ------------------------------------------------------------------ desktop: HTTP and WebSocket servers

## Starts both servers (once); true when they listen.
func start_servers() -> bool:
	if _http and _ws_server:
		return true
	_http = TCPServer.new()
	var e1 := _http.listen(http_port, "127.0.0.1")
	_ws_server = TCPServer.new()
	var e2 := _ws_server.listen(ws_port, "127.0.0.1")
	url = "http://127.0.0.1:%d/index.html?ws=%d" % [http_port, ws_port]
	if e1 != OK or e2 != OK:
		printerr("web city: cannot listen on 127.0.0.1:%d (HTTP, error %d) / %d (WebSocket, error %d)" % [http_port, e1, ws_port, e2])
		return false
	return true


func stop_servers() -> void:
	for c in _http_conns:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_http_conns.clear()
	for c in _ws:
		(c["peer"] as WebSocketPeer).close()
	_ws.clear()
	if _http:
		_http.stop()
	if _ws_server:
		_ws_server.stop()
	_http = null
	_ws_server = null


## The Content-Type for a file name.
static func content_type(path: String) -> String:
	return TYPES.get(path.get_extension().to_lower(), "application/octet-stream")


## The res:// file for a request target ("/js/main.js?x=1"), or "" when it is refused (not absolute, a ".."
## segment, a backslash, a NUL, a scheme).
static func resolve_path(target: String) -> String:
	var p := target.get_slice("?", 0).get_slice("#", 0)
	if not p.begins_with("/"):
		return ""
	p = percent_decode(p)
	if p == "" or p.contains("\\") or p.contains(":"):
		return ""
	if p.ends_with("/"):
		p += "index.html"
	var parts: Array = []
	for seg in p.split("/"):
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			return ""
		parts.append(seg)
	if parts.is_empty():
		return ""
	return ROOT.path_join("/".join(parts))


func _poll_http() -> void:
	if _http == null:
		return
	while _http.is_connection_available():
		var peer := _http.take_connection()
		if peer:
			_http_conns.append({"peer": peer, "buf": PackedByteArray(), "out": PackedByteArray(), "off": 0, "t": _now, "sent": false})
	for c in _http_conns.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED or _now - float(c["t"]) > HTTP_TIMEOUT:
			peer.disconnect_from_host()
			_http_conns.erase(c)
			continue
		if not c["sent"]:
			var n := peer.get_available_bytes()
			if n > 0:
				var got: Array = peer.get_partial_data(n)
				if got[0] == OK:
					var buf: PackedByteArray = c["buf"]   # packed arrays are values: append, then store back
					buf.append_array(got[1])
					c["buf"] = buf
			var head := (c["buf"] as PackedByteArray).get_string_from_ascii()
			if head.contains("\r\n\r\n"):
				c["out"] = _respond(head)
				c["sent"] = true
			elif (c["buf"] as PackedByteArray).size() > HTTP_MAX_REQUEST:
				c["out"] = _status(431, "Request Header Fields Too Large")
				c["sent"] = true
		if c["sent"]:
			var out: PackedByteArray = c["out"]
			var off: int = c["off"]
			var budget := HTTP_CHUNK * 8
			while off < out.size() and budget > 0:
				var r: Array = peer.put_partial_data(out.slice(off, mini(out.size(), off + HTTP_CHUNK)))
				if r[0] != OK or int(r[1]) == 0:
					break
				off += int(r[1])
				budget -= int(r[1])
			c["off"] = off
			if off >= out.size():
				peer.disconnect_from_host()
				_http_conns.erase(c)


## The whole response (headers and body) to one request.
func _respond(head: String) -> PackedByteArray:
	var line := head.get_slice("\r\n", 0).split(" ")
	if line.size() < 3:
		return _status(400, "Bad Request")
	var method := line[0]
	if method != "GET" and method != "HEAD":
		return _status(405, "Method Not Allowed")
	var path := resolve_path(line[1])
	if path == "":
		return _status(403, "Forbidden")
	if not FileAccess.file_exists(path):
		return _status(404, "Not Found")
	var body := FileAccess.get_file_as_bytes(path)
	var out := ("HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [
		content_type(path), body.size()]).to_ascii_buffer()
	if method == "GET":
		out.append_array(body)
	return out


## %XX (either case) decoded; "" for a malformed escape, a NUL or anything not ASCII (the page's files all
## have ASCII names). "+" stays.
static func percent_decode(s: String) -> String:
	var src := s.to_utf8_buffer()
	var out := PackedByteArray()
	var i := 0
	while i < src.size():
		var b := src[i]
		if b == 37:   # %
			if i + 2 >= src.size():
				return ""
			var hex := src.slice(i + 1, i + 3).get_string_from_ascii()
			if not ("0123456789abcdefABCDEF".contains(hex[0]) and "0123456789abcdefABCDEF".contains(hex[1])):
				return ""
			b = hex.hex_to_int()
			i += 2
		if b == 0 or b >= 128:
			return ""
		out.append(b)
		i += 1
	return out.get_string_from_ascii()


static func _status(code: int, text: String) -> PackedByteArray:
	return ("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % [code, text]).to_ascii_buffer()


func _poll_ws() -> void:
	if _ws_server == null:
		return
	while _ws_server.is_connection_available():
		var tcp := _ws_server.take_connection()
		if tcp == null:
			continue
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = 1 << 20
		peer.outbound_buffer_size = 32 << 20
		peer.max_queued_packets = 4096
		if peer.accept_stream(tcp) == OK:
			_ws.append({"peer": peer, "greeted": false, "close_at": -1.0})
	for c in _ws.duplicate():
		var peer: WebSocketPeer = c["peer"]
		peer.poll()
		var st := peer.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_ws.erase(c)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			continue
		if not c["greeted"]:
			c["greeted"] = true
			if active:
				_greet()   # a page that came back (the page sends 'ready' only once, at load)
		while peer.get_available_packet_count() > 0:
			_on_text(peer.get_packet().get_string_from_utf8())
		# Closed only once 'bye' has left (wslay sends a close frame ahead of queued messages), or after
		# WS_CLOSE_WAIT whatever is still queued.
		var at := float(c["close_at"])
		if at >= 0.0 and _now >= at and (peer.get_current_outbound_buffered_amount() == 0 or _now >= at + WS_CLOSE_WAIT):
			c["close_at"] = -1.0
			peer.close(1000, "bye")


# ------------------------------------------------------------------ messages

## One message to the page (as JSON text). Returns whether a page took it. A droppable message (a frame) is
## not queued behind a backlog (WS_BACKLOG): the next one replaces it.
func send(msg: Dictionary, droppable := false) -> bool:
	if record_outbox:
		outbox.append(msg)
	var text := JSON.stringify(msg)
	var ok := false
	if platform == "ios":
		if _plugin and bool(_plugin.call("is_open")):
			_plugin.call("post", text)
			ok = true
	else:
		for c in _ws:
			var peer: WebSocketPeer = c["peer"]
			if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				continue
			if droppable and peer.get_current_outbound_buffered_amount() > WS_BACKLOG:
				dropped += 1
				continue
			if peer.send_text(text) == OK:
				ok = true
	return ok


func linked() -> bool:
	if platform == "ios":
		return _plugin != null and bool(_plugin.call("is_open"))
	for c in _ws:
		if (c["peer"] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
	return false


func _on_text(text: String) -> void:
	var v = JSON.parse_string(text)
	if v is Dictionary:
		handle_page(v)


static func _vec3(a) -> Variant:
	if not (a is Array) or (a as Array).size() != 3:
		return null
	for x in a:
		if not (x is float or x is int):
			return null
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A message from the page (protocol 6.3 "Page to Godot").
func handle_page(msg: Dictionary) -> void:
	page_message.emit(msg)
	var t := str(msg.get("t", ""))
	match t:
		"ready":
			page_ready = true
			last_ready = msg
			print("WEB CITY page ready: %s" % JSON.stringify({"v": msg.get("v"), "w": msg.get("w"), "h": msg.get("h"),
				"dpr": msg.get("dpr"), "load_ms": msg.get("load_ms"), "failed": msg.get("failed")}))
			_greet()
		"first_frame":
			print("WEB CITY first frame after %s ms" % str(msg.get("ms")))
		"log":
			print("WEB CITY page %s: %s" % [str(msg.get("level", "log")), str(msg.get("text", ""))])
		"tap":
			var o = _vec3(msg.get("o"))
			var d = _vec3(msg.get("d"))
			if active and o != null and d != null and controller and controller.has_method("web_tap"):
				controller.web_tap(o, d)
		"act":
			if active and controller and controller.has_method("web_act"):
				controller.web_act()
		"weather":
			var w = msg.get("w")
			if active and (w is float or w is int) and controller and controller.has_method("web_weather"):
				controller.web_weather(int(w))
		"home":
			if active and controller and controller.has_method("web_home"):
				controller.web_home()
		"look":
			look_on = typeof(msg.get("on")) == TYPE_BOOL and msg["on"]
		"pause":
			pause_on = typeof(msg.get("on")) == TYPE_BOOL and msg["on"]
		"cam":
			cam = msg
		"perf":
			var fps = msg.get("fps")
			if fps is float or fps is int:
				page_fps = float(fps)
			_log_perf(msg)


func _log_perf(msg: Dictionary) -> void:
	var rec := msg.duplicate()
	rec.erase("t")
	rec["platform"] = platform
	rec["os"] = OS.get_name()
	rec["model"] = OS.get_model_name()
	rec["unix"] = Time.get_unix_time_from_system()
	if bench_phase != "":
		rec["phase"] = bench_phase
		rec["bench"] = bench_run
	if platform == "ios" and _plugin:
		rec["stats"] = _plugin.call("stats")
	var f := FileAccess.open(PERF_LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(PERF_LOG) else FileAccess.open(PERF_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(rec))
	f.close()


func _forward_text(kind: String, text: String) -> void:
	if active and text != "":
		send({"t": kind, "text": tr(text)})


func _on_states(states: Dictionary) -> void:
	if active:
		send({"t": "states", "s": WebJson.value(states)})


func _on_effect(kind: String, data: Dictionary) -> void:
	if active:
		send({"t": "effect", "kind": kind, "data": WebJson.value(data)})


# ------------------------------------------------------------------ every frame

func _process(delta: float) -> void:
	_now += delta
	if platform == "ios":
		if _plugin and bool(_plugin.call("is_open")):
			for text in _plugin.call("poll"):
				_on_text(str(text))
	else:
		_poll_http()
		_poll_ws()
	if not active or not linked():
		return
	_frame_t -= delta
	if _frame_t > 0.0:
		return
	_frame_t = 1.0 / frame_hz()
	_send_cutaway()
	send(frame_message(), true)


## Frame messages a second now (see FRAME_HZ).
func frame_hz() -> float:
	if page_fps <= 0.0:
		return FRAME_HZ
	return clampf(page_fps * PAGE_RATE, MIN_FRAME_HZ, FRAME_HZ)


func _send_cutaway() -> void:
	if world == null or not world.has_method("web_cutaway"):
		return
	var cut: Dictionary = world.web_cutaway()
	var key := str(cut.get("rev", "")) if cut.has("rev") else str([cut.get("hidden", {}), cut.get("regions", [])])
	if key == _cut_key:
		return
	_cut_key = key
	send({"t": "cutaway", "hidden": WebJson.value(cut.get("hidden", {})), "regions": WebJson.value(cut.get("regions", [])),
		"rev": cut.get("rev", null)})


## The frame message (and, first, each child's model when it is new to the page; kid_gone for one that left).
func frame_message() -> Dictionary:
	var cw := city()
	var me_id := _my_id()
	var kids_out: Array = []
	var seen := {}
	var kids: Dictionary = world.get("kids") if world and world.get("kids") is Dictionary else {}
	for peer in kids:
		var kid: Node3D = kids[peer]
		if not is_instance_valid(kid) or not _in_web_city(int(peer)):
			continue
		var m := _model_for(int(peer), kid)
		if m.is_empty():
			continue
		seen[int(peer)] = true
		if _sent_rev.get(int(peer), -1) != m["rev"]:
			if send(m["msg"]):
				_sent_rev[int(peer)] = m["rev"]
		kids_out.append({"id": int(peer), "me": int(peer) == me_id, "rev": m["rev"], "xf": MeshPack.Pack.xf12(kid.global_transform),
			"anim": str(kid.get("anim")), "ride": _ride_of(cw, int(peer)), "level": _level_of(int(peer)), "pose": pose_of(m)})
	for peer in _sent_rev.keys():
		if not seen.has(peer):
			send({"t": "kid_gone", "id": peer})
			_sent_rev.erase(peer)
	for peer in _models.keys():
		if not kids.has(peer) or not is_instance_valid(kids[peer]):
			_models.erase(peer)
	var me := {}
	if controller and controller.has_method("web_me"):
		me = controller.web_me()
	elif controller:
		var ctx: Dictionary = controller.web_ctx() if controller.has_method("web_ctx") else {}
		var p: Vector2 = controller.get("pos")
		me = {"id": me_id, "level": str(controller.get("level")), "pos": [p.x, p.y],
			"riding": int(cw.riding(me_id)) if cw and cw.has_method("riding") else -1,
			"hold": str((controller.get("city_hold") as Dictionary).get("key", "")), "ctx": ctx if not ctx.is_empty() else null}
	return {"t": "frame", "clock": float(cw.est_time()) if cw and cw.has_method("est_time") else 0.0, "me": me, "kids": kids_out}


func _in_web_city(peer: int) -> bool:
	if peer == _my_id():
		return active
	var s := get_node_or_null("/root/Session")
	if s == null:
		return false
	return str((s.players.get(peer, {}) as Dictionary).get("state", {}).get("space", "")) == WEB_MAP


func _level_of(peer: int) -> String:
	if peer == _my_id():
		return str(controller.get("level")) if controller else ""
	var s := get_node_or_null("/root/Session")
	return str((s.players.get(peer, {}) as Dictionary).get("state", {}).get("level", "")) if s else ""


static func _ride_of(cw: Node, peer: int) -> Variant:
	if cw == null:
		return null
	var riders: Dictionary = cw.states.get("riders", {})
	for g in riders:
		var slot := (riders[g] as Array).find(peer)
		if slot >= 0:
			return {"g": int(g), "slot": slot}
	return null


## The child's packed model, rebuilt when its rig was rebuilt (a new look).
func _model_for(peer: int, kid: Node3D) -> Dictionary:
	var key := rig_key(kid)
	var m: Dictionary = _models.get(peer, {})
	if not m.is_empty() and m["key"] == key:
		for n in m["tracked"]:
			if not is_instance_valid(n):
				m = {}
				break
		if not m.is_empty():
			return m
	if key == "":
		return {}
	var rev := int((_models.get(peer, {}) as Dictionary).get("rev", 0)) + 1
	m = build_kid_model(peer, kid, rev)
	m["key"] = key
	_models[peer] = m
	return m


## What identifies one build of a rig: kid.gd setup() replaces every child.
static func rig_key(kid: Node3D) -> String:
	if kid.get_child_count() == 0:
		return ""
	return "%d:%d" % [kid.get_child(0).get_instance_id(), kid.get_child_count()]


## Packs a child's rig: {"rev", "tracked" (nodes in pack order), "pose_nodes", "msg" (the kid_model message)}.
static func build_kid_model(peer: int, kid: Node3D, rev: int) -> Dictionary:
	var pack := MeshPack.Pack.new()
	pack.track = true
	pack.textures = true
	_exclude_undrawable(kid, pack.exclude)
	pack.add_tree(kid)
	var header := pack.header()
	(header["nodes"] as Array)[0]["xf"] = MeshPack.Pack.xf12(Transform3D.IDENTITY)   # the frame's xf places the root
	var pose_nodes: Array = []
	for i in range(1, pack.tracked.size()):
		if not (pack.tracked[i] is GeometryInstance3D):
			pose_nodes.append(i)
	var avatar = kid.get("avatar")
	var nick := str((avatar as Dictionary).get("nick", "")) if avatar is Dictionary else ""
	# dest-fix r1: "label" is the name as the Godot city's label shows it (translated), for the page's name tags
	var msg := {"t": "kid_model", "id": peer, "rev": rev, "nick": nick, "label": TranslationServer.translate(nick), "pack": header,
		"bin": Marshalls.raw_to_base64(pack.bytes()), "pose_nodes": pose_nodes, "vis_count": pack.tracked.size(), "vis_bits": VIS_BITS}
	return {"rev": rev, "tracked": pack.tracked, "pose_nodes": pose_nodes, "msg": msg}


## The name label and whatever the page cannot draw (labels, sprites, particles, lights, decals).
static func _exclude_undrawable(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and not (c is MeshInstance3D or c is MultiMeshInstance3D):
			out[c] = true
		else:
			_exclude_undrawable(c, out)


## This frame's pose of a packed model (see the header).
static func pose_of(m: Dictionary) -> Dictionary:
	var tracked: Array = m["tracked"]
	var x: Array = []
	for i in m["pose_nodes"]:
		var n = tracked[i]
		if not is_instance_valid(n):
			return {"x": [], "v": []}
		for f in MeshPack.Pack.xf12((n as Node3D).transform):
			x.append(snappedf(f, POSE_STEP))
	var v: Array = []
	var word := 0
	for i in tracked.size():
		var n = tracked[i]
		if is_instance_valid(n) and (n as Node3D).visible:
			word |= 1 << (i % VIS_BITS)
		if i % VIS_BITS == VIS_BITS - 1 or i == tracked.size() - 1:
			v.append(word)
			word = 0
	return {"x": x, "v": v}
