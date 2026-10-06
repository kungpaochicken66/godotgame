## Sfx (autoload): tiny synthesized sounds, so there are no audio asset files.
## Soft sine tones with quick decay suit a calm children's game.
extends Node

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var muted := false


func _ready() -> void:
	_streams["place"] = _tones([[660.0, 0.0, 0.12], [880.0, 0.05, 0.16]])
	_streams["pop"] = _tones([[520.0, 0.0, 0.1], [390.0, 0.06, 0.12]])
	_streams["tap"] = _tones([[740.0, 0.0, 0.06]])
	_streams["bell"] = _tones([[784.0, 0.0, 1.2], [1175.0, 0.0, 0.9], [1568.0, 0.02, 0.6]])
	_streams["lantern"] = _tones([[523.0, 0.0, 0.3], [659.0, 0.12, 0.3], [784.0, 0.24, 0.3], [1047.0, 0.36, 0.6]])
	_streams["photo"] = _tones([[1200.0, 0.0, 0.05], [900.0, 0.05, 0.08]])
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)


func play(name: String) -> void:
	if muted or not _streams.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.play()
			return


## Each tone: [frequency Hz, start s, length s]; summed with a soft attack and decay.
func _tones(tones: Array) -> AudioStreamWAV:
	var length := 0.0
	for t in tones:
		length = maxf(length, t[1] + t[2])
	var n := int(length * RATE) + 1
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var time := float(i) / RATE
		var v := 0.0
		for t in tones:
			var local: float = time - t[1]
			if local < 0.0 or local > t[2]:
				continue
			var env := minf(1.0, local / 0.008) * pow(1.0 - local / t[2], 2.0)
			v += sin(TAU * t[0] * local) * env * 0.3
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s
