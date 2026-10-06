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
	_apply_buses()


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
