extends Node
## Retro sound effects synthesized at startup as 8-bit samples
## (square-wave engine, noise skids and crashes, countdown beeps).

const RATE := 11025

var _engine: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _oneshots: Array = []
var _streams: Dictionary = {}
var _next := 0
var _skid_level := 0.0
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["engine"] = _make_engine()
	_streams["skid"] = _make_noise(0.5, true, 0.0, 3)
	_streams["crash"] = _make_noise(0.35, false, 7.0, 1)
	_streams["beep"] = _make_tone(440.0, 0.18)
	_streams["go"] = _make_tone(880.0, 0.45)
	_streams["lap"] = _make_arpeggio([523.0, 659.0, 784.0], 0.07)
	_streams["finish"] = _make_arpeggio([523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0], 0.11)
	_streams["click"] = _make_tone(1200.0, 0.04)
	_engine = _player(_streams["engine"], -14.0)
	_skid = _player(_streams["skid"], -80.0)
	for i in range(5):
		_oneshots.append(_player(null, -6.0))


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func play(name: String, volume_db: float = -6.0) -> void:
	if not enabled or not _streams.has(name):
		return
	var p: AudioStreamPlayer = _oneshots[_next]
	_next = (_next + 1) % _oneshots.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.play()


## speed01: 0..1 engine load. Call every frame while racing.
func set_engine(active: bool, speed01: float) -> void:
	if not enabled:
		return
	if active:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 0.55 + clampf(speed01, 0.0, 1.2) * 1.15
	elif _engine.playing:
		_engine.stop()


func set_skid(active: bool) -> void:
	if not enabled:
		return
	_skid_level = move_toward(_skid_level, 1.0 if active else 0.0, 0.2)
	if _skid_level > 0.01:
		if not _skid.playing:
			_skid.play()
		_skid.volume_db = linear_to_db(_skid_level) - 12.0
	elif _skid.playing:
		_skid.stop()


func stop_all() -> void:
	if _engine:
		_engine.stop()
	if _skid:
		_skid.stop()
	_skid_level = 0.0


func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


static func _s8(v: float) -> int:
	# 8-bit WAV data in Godot is signed.
	var i := clampi(int(round(v * 127.0)), -127, 127)
	return i if i >= 0 else i + 256


func _make_engine() -> AudioStreamWAV:
	# Pulse wave with a little grit, exactly a whole number of cycles so it loops cleanly.
	var freq := 90.0
	var cycles := 18
	var samples := int(round(RATE / freq * cycles))
	var data := PackedByteArray()
	data.resize(samples)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(samples):
		var ph := fmod(i * cycles / float(samples), 1.0)
		var v := 0.55 if ph < 0.3 else -0.45
		v += rng.randf_range(-0.08, 0.08)
		data[i] = _s8(v)
	return _wav(data, true)


func _make_noise(seconds: float, loop: bool, decay: float, hold: int) -> AudioStreamWAV:
	var samples := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(samples)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var v := 0.0
	for i in range(samples):
		if i % hold == 0:
			v = rng.randf_range(-1.0, 1.0)
		var env := 1.0 if decay <= 0.0 else exp(-decay * i / float(RATE))
		data[i] = _s8(v * env * 0.8)
	return _wav(data, loop)


func _make_tone(freq: float, seconds: float) -> AudioStreamWAV:
	var samples := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(samples)
	for i in range(samples):
		var ph := fmod(i * freq / RATE, 1.0)
		var env := 1.0 - float(i) / samples
		data[i] = _s8((0.6 if ph < 0.5 else -0.6) * env)
	return _wav(data, false)


func _make_arpeggio(freqs: Array, note_len: float) -> AudioStreamWAV:
	var per := int(RATE * note_len)
	var data := PackedByteArray()
	data.resize(per * freqs.size())
	for n in range(freqs.size()):
		for i in range(per):
			var ph := fmod(i * float(freqs[n]) / RATE, 1.0)
			var env := 1.0 - 0.6 * float(i) / per
			data[n * per + i] = _s8((0.5 if ph < 0.5 else -0.5) * env)
	return _wav(data, false)
