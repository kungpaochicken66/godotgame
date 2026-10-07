## Music (autoload): the looping background music and the player's audio settings.
##
## Plays the original loop "Meadow Lanterns" (see docs/assets.md) quietly on its
## own bus, a little softer on menus and inside houses. Settings persist in
## user://settings.cfg: music on/off, music volume and sounds on/off. Music
## pauses while iPadOS/iOS has the app in the background.
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const TRACK := "res://assets/audio/meadow_lanterns.wav"
## Loudest the music ever plays (dB) at full volume; kept well under effects.
const BASE_DB := -9.0
const CONTEXT_GAIN := {"menu": 0.6, "town": 1.0, "home": 0.55, "silent": 0.0}

signal settings_changed()

var music_on := true
var music_volume := 0.6      # 0..1, slider value
var sounds_on := true
var context := "silent"

var _player: AudioStreamPlayer
var _tween: Tween
var _beat: AudioStreamPlayer      # soft party beat for the dance parade (activity E)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_on = bool(cfg.get_value("audio", "music_on", music_on))
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sounds_on = bool(cfg.get_value("audio", "sounds_on", sounds_on))
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = -80.0
	var stream = load(TRACK) if ResourceLoader.exists(TRACK) else null
	if stream is AudioStreamWAV:
		# Sample-exact loop over the whole file; the composition is rendered seamless.
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	_player.stream = stream
	add_child(_player)
	_beat = AudioStreamPlayer.new()
	_beat.bus = "Music"
	_beat.stream = _make_beat()
	add_child(_beat)
	_apply_buses()
	Activities.party_changed.connect(set_party)


## "menu", "town", "home" or "silent". Fades smoothly between levels.
func set_context(c: String) -> void:
	if not CONTEXT_GAIN.has(c):
		c = "town"
	context = c
	_fade_to_target(1.2)


func target_db() -> float:
	var gain: float = CONTEXT_GAIN[context] * music_volume
	if not music_on or gain <= 0.001:
		return -80.0
	return BASE_DB + linear_to_db(gain)


func set_music_on(on: bool) -> void:
	music_on = on
	_changed()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_changed()


func set_sounds_on(on: bool) -> void:
	sounds_on = on
	_changed()


func _changed() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sounds_on", sounds_on)
	cfg.save(SETTINGS_PATH)
	_apply_buses()
	_fade_to_target(0.4)
	settings_changed.emit()


func _apply_buses() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not sounds_on)


func _fade_to_target(seconds: float) -> void:
	if _player.stream == null:
		return
	var goal := target_db()
	if goal > -79.0 and not _player.playing:
		_player.volume_db = -60.0
		_player.play()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", goal, seconds)
	if goal <= -79.0:
		_tween.tween_callback(_player.stop)


## Party: the loop plays a little faster with a gentle beat on top.
func set_party(on: bool) -> void:
	_player.pitch_scale = 1.12 if on else 1.0
	if on and music_on and music_volume > 0.0:
		_beat.volume_db = target_db() - 4.0
		_beat.play()
	else:
		_beat.stop()


func is_party() -> bool:
	return _beat.playing


## Two bars of soft kick and woodblock at 94 BPM, synthesized (no samples).
static func _make_beat() -> AudioStreamWAV:
	var rate := 22050
	var beat := 60.0 / 94.0
	var n := int(beat * 8 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var in_beat := fmod(t, beat)
		var v := sin(TAU * (60.0 + 80.0 * exp(-in_beat * 30.0)) * in_beat) * exp(-in_beat * 9.0) * 0.5
		var off := fmod(t + beat * 0.5, beat)
		v += sin(TAU * 1200.0 * off) * exp(-off * 60.0) * 0.18
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


## Clean shutdown: stop every player, drop the streams and let the audio server
## mix once (about 0.1 s) so it releases its playbacks before the engine exits.
## Without this a looping playback is still owned at exit ("resources still in
## use"). Stopping in _exit_tree alone was shown not to be enough.
func stop_for_exit() -> void:
	if _tween:
		_tween.kill()
	for p in [_player, _beat]:
		if p:
			p.stop()
			p.stream = null
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.stop_for_exit()
	# Mix cycles run on the audio thread; a fresh playback can need a few to be released.
	for i in 3:
		await get_tree().create_timer(0.12, true, false, true).timeout


## The one way the game and its test drivers quit.
func quit_game(code := 0) -> void:
	await stop_for_exit()
	get_tree().quit(code)


func is_playing() -> bool:
	return _player.playing and not _player.stream_paused


func _notification(what: int) -> void:
	# The OS may suspend the app at any time; never keep playing in the background.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _player:
			_player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _player:
			_player.stream_paused = false
