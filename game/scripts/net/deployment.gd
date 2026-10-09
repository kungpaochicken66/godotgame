## Private deployment config and invite rules (pure, unit-tested).
## Contract: docs/deployment.md. Never log URLs or invites from here.
extends RefCounted

const CONFIG_PATH := "res://private/deployment.json"
const SCHEMA := 1
const LOOPBACK := ["localhost", "127.0.0.1", "[::1]"]


## {ok, url, invite, reason}. reason is a short category, never a value.
static func parse(text: String) -> Dictionary:
	var data = quiet_json(text)
	if not data is Dictionary:
		return {"ok": false, "reason": "not a JSON object"}
	if typeof(data.get("schema")) not in [TYPE_INT, TYPE_FLOAT] or int(data["schema"]) != SCHEMA or float(data["schema"]) != float(SCHEMA):
		return {"ok": false, "reason": "unsupported schema"}
	var url = data.get("multiplayer_url")
	if not url is String or not valid_url(url, true):
		return {"ok": false, "reason": "invalid multiplayer_url"}
	var invite = data.get("invite_code", "")
	if not invite is String or (invite != "" and not valid_invite(invite)):
		return {"ok": false, "reason": "invalid invite_code"}
	return {"ok": true, "url": url, "invite": invite, "reason": ""}


## Parses JSON without printing engine errors (null when malformed).
static func quiet_json(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


## Loads the packaged config; {} when absent or invalid (with one warning).
static func load_config(path := CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Private deployment config ignored: unreadable")
		return {}
	var r := parse(f.get_as_text())
	if not r["ok"]:
		push_warning("Private deployment config ignored: %s" % r["reason"])
		return {}
	return r


## wss:// with a host; ws:// only to loopback (local testing). `strict` is the
## packaged-config rule; the join screen also accepts ws:// on a LAN by hand.
static func valid_url(url: String, strict := false) -> bool:
	if url.length() > 512 or url.strip_edges() != url or url.contains(" "):
		return false
	var scheme := ""
	if url.begins_with("wss://"):
		scheme = "wss"
	elif url.begins_with("ws://"):
		scheme = "ws"
	else:
		return false
	var host := host_of(url)
	if host == "":
		return false
	if scheme == "ws" and strict:
		return host in LOOPBACK
	return true


static func host_of(url: String) -> String:
	var rest := url.substr(url.find("://") + 3)
	var end := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < end:
			end = i
	var hostport := rest.substr(0, end)
	if hostport.contains("@"):
		return ""   # no credentials in URLs
	if hostport.begins_with("["):
		var close := hostport.find("]")
		return hostport.substr(0, close + 1) if close > 1 else ""
	var colon := hostport.rfind(":")
	if colon >= 0:
		var port := hostport.substr(colon + 1)
		if not port.is_valid_int() or int(port) < 1 or int(port) > 65535:
			return ""
		hostport = hostport.substr(0, colon)
	return hostport


## 1-256 printable ASCII characters, no spaces.
static func valid_invite(code: String) -> bool:
	if code.length() < 1 or code.length() > 256:
		return false
	for i in code.length():
		var c := code.unicode_at(i)
		if c < 0x21 or c > 0x7E:
			return false
	return true


## Constant-time comparison: both sides are hashed to 32 bytes first, so the
## time depends on neither the length nor the content of the secret.
static func same_invite(a: String, b: String) -> bool:
	var da := _digest(a)
	var db := _digest(b)
	var diff := 0
	for i in da.size():
		diff |= da[i] ^ db[i]
	return diff == 0


static func _digest(s: String) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("invite:" + s).to_utf8_buffer())   # never empty (an empty update is an engine error)
	return h.finish()


## The address the join screen shows (docs/deployment.md, section 2).
## settings: {server, override, override_base} from user://settings.cfg.
static func shown_address(config: Dictionary, settings: Dictionary, fallback := "ws://127.0.0.1:9080") -> String:
	var d: String = config.get("url", "")
	if d != "":
		var o: String = settings.get("override", "")
		return o if o != "" and settings.get("override_base", "") == d else d
	var s: String = settings.get("server", "")
	return s if s != "" else fallback


## The settings to store after the player joins `url` by hand.
static func remember_address(config: Dictionary, settings: Dictionary, url: String) -> Dictionary:
	var out := settings.duplicate()
	var d: String = config.get("url", "")
	if d == "":
		out["server"] = url
	elif url == d:
		out["override"] = ""
		out["override_base"] = ""
	else:
		out["override"] = url
		out["override_base"] = d
	return out


## The invite to send when joining `url`.
static func invite_for(config: Dictionary, url: String, typed: String) -> String:
	if config.get("url", "") != "" and url == config["url"] and config.get("invite", "") != "":
		return config["invite"]
	return typed.strip_edges()


## Reads the server invite file: {ok, invite, reason, loose}. `loose` = readable by group or others.
static func read_invite_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "reason": "invite file not found"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "invite file unreadable"}
	var code := f.get_line().strip_edges()
	if not valid_invite(code):
		return {"ok": false, "reason": "invite file empty or invalid"}
	var perms := FileAccess.get_unix_permissions(path)
	return {"ok": true, "invite": code, "reason": "", "loose": (perms & 0x3F) != 0}
