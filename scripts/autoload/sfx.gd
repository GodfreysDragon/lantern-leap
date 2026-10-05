extends Node
## A tiny chiptune-style synth. Every sound effect is generated at startup
## into an AudioStreamWAV, so the game ships with zero audio assets and each
## effect is a few readable parameters rather than a binary file.

enum Wave { SQUARE, TRIANGLE, SINE, NOISE }

const RATE := 22050
const VOICES := 12

var _streams: Dictionary[String, AudioStreamWAV] = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

	_streams = {
		"jump": _wav(_sweep(0.11, 260, 540, Wave.SQUARE, 0.16, 0.5)),
		"wall_jump": _wav(_mix(_sweep(0.12, 330, 720, Wave.SQUARE, 0.15, 0.25), _sweep(0.05, 900, 500, Wave.NOISE, 0.12))),
		"land": _wav(_sweep(0.07, 520, 140, Wave.NOISE, 0.22)),
		"dash": _wav(_mix(_sweep(0.2, 2400, 300, Wave.NOISE, 0.24), _sweep(0.14, 880, 330, Wave.SQUARE, 0.08, 0.125))),
		"gem": _wav(_arp([988.0, 1319.0, 1976.0], 0.055, Wave.SQUARE, 0.12, 0.25)),
		"crystal": _wav(_arp([784.0, 1175.0, 1568.0], 0.05, Wave.TRIANGLE, 0.3)),
		"spring": _wav(_sweep(0.28, 170, 960, Wave.SQUARE, 0.14, 0.5, 18.0)),
		"death": _wav(_mix(_sweep(0.42, 520, 55, Wave.SQUARE, 0.16, 0.5, 9.0), _sweep(0.3, 1400, 120, Wave.NOISE, 0.22))),
		"respawn": _wav(_sweep(0.22, 220, 660, Wave.TRIANGLE, 0.3)),
		"crumble": _wav(_sweep(0.18, 380, 90, Wave.NOISE, 0.2)),
		"checkpoint": _wav(_arp([523.0, 659.0, 784.0, 1047.0], 0.07, Wave.SQUARE, 0.12, 0.25)),
		"exit": _wav(_arp([523.0, 659.0, 784.0, 1047.0, 1319.0, 1568.0, 2093.0], 0.075, Wave.TRIANGLE, 0.32, 0.5, 0.45)),
		"ui": _wav(_sweep(0.06, 660, 990, Wave.SQUARE, 0.1, 0.25)),
		"ui_back": _wav(_sweep(0.06, 660, 440, Wave.SQUARE, 0.1, 0.25)),
	}
	AudioServer.set_bus_mute(0, Save.muted)


func play(sound: String, pitch_jitter := 0.04, volume_db := 0.0) -> void:
	var stream: AudioStreamWAV = _streams.get(sound)
	if stream == null:
		push_warning("Unknown sound: %s" % sound)
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()


func toggle_mute() -> bool:
	Save.muted = not Save.muted
	Save.write()
	AudioServer.set_bus_mute(0, Save.muted)
	return Save.muted


# --- synthesis ---------------------------------------------------------------

## One oscillator with an exponential pitch sweep, optional vibrato, a 4ms
## attack and a curved decay.
func _sweep(duration: float, f_start: float, f_end: float, wave: Wave,
		volume := 0.3, duty := 0.5, vibrato_hz := 0.0) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var held := 0.0
	var attack := 0.004 * RATE
	for i in n:
		var t := float(i) / n
		var freq := f_start * pow(f_end / f_start, t)
		if vibrato_hz > 0.0:
			freq *= 1.0 + 0.05 * sin(TAU * vibrato_hz * i / RATE)
		var prev := phase
		phase = fmod(phase + freq / RATE, 1.0)
		var s := 0.0
		match wave:
			Wave.SQUARE:
				s = 1.0 if phase < duty else -1.0
			Wave.TRIANGLE:
				s = 4.0 * absf(phase - 0.5) - 1.0
			Wave.SINE:
				s = sin(phase * TAU)
			Wave.NOISE:
				# Sample-and-hold noise: the "frequency" sets how crunchy it is.
				if phase < prev:
					held = _rng.randf_range(-1.0, 1.0)
				s = held
		var envelope := minf(1.0, i / attack) * pow(1.0 - t, 1.6)
		out[i] = s * envelope * volume
	return out


func _arp(notes: Array[float], note_len: float, wave: Wave, volume := 0.3,
		duty := 0.5, tail := 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in notes.size():
		var length := note_len + (tail if i == notes.size() - 1 else 0.0)
		out.append_array(_sweep(length, notes[i], notes[i] * 1.01, wave, volume, duty))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
