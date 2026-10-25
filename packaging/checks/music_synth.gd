extends RefCounted

const RATE := 22050

var samples := PackedFloat32Array()
var bpm := 120.0
var rng := RandomNumberGenerator.new()
var _kick := PackedFloat32Array()
var _snare := PackedFloat32Array()
var _hat := PackedFloat32Array()


func _init(tempo: float, bars: int, seed := 7) -> void:
	bpm = tempo
	rng.seed = seed
	samples.resize(int(ceil(bars * 4 * beat_length() * RATE)) + RATE)
	_kick = _make_kick()
	_snare = _make_snare()
	_hat = _make_hat()


func beat_length() -> float:
	return 60.0 / bpm


func beat_time(beat: float) -> float:
	return beat * beat_length()


func bar_time(bar: float) -> float:
	return bar * 4.0 * beat_length()


func duration() -> float:
	return float(samples.size()) / RATE


func add(buffer: PackedFloat32Array, time: float, gain := 1.0) -> void:
	var start := int(round(time * RATE))
	var count := mini(buffer.size(), samples.size() - start)
	for i in count:
		samples[start + i] += buffer[i] * gain


func kick(beat: float, gain := 1.0) -> void:
	add(_kick, beat_time(beat), gain)


func snare(beat: float, gain := 1.0) -> void:
	add(_snare, beat_time(beat), gain)


func hat(beat: float, gain := 1.0) -> void:
	add(_hat, beat_time(beat), gain)


func click(beat: float, gain := 1.0) -> void:
	var buffer := PackedFloat32Array()
	buffer.resize(int(RATE * 0.03))
	for i in buffer.size():
		buffer[i] = sin(TAU * 1000.0 * i / RATE) * exp(-float(i) / RATE * 150.0)
	add(buffer, beat_time(beat), gain)


func pad(from_bar: int, to_bar: int, notes: Array, gain := 0.12) -> void:
	var length := int(round(bar_time(1) * RATE))
	var buffer := PackedFloat32Array()
	buffer.resize(length)
	for note in notes:
		var frequency := 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)
		var step := TAU * frequency / RATE
		for i in length:
			buffer[i] += sin(step * i) * gain
	var fade := int(RATE * 0.01)
	for i in fade:
		buffer[i] *= float(i) / fade
		buffer[length - 1 - i] *= float(i) / fade
	for bar in range(from_bar, to_bar):
		add(buffer, bar_time(bar))


func bass(from_bar: int, to_bar: int, note: int, gain := 0.5) -> void:
	var length := int(round(beat_length() * RATE))
	var buffer := PackedFloat32Array()
	buffer.resize(length)
	var frequency := 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)
	for i in length:
		var t := float(i) / RATE
		buffer[i] = sin(TAU * frequency * t) * gain * minf(1.0, t * 200.0) * minf(1.0, (length - i) / (RATE * 0.01))
	for beat in range(from_bar * 4, to_bar * 4):
		add(buffer, beat_time(beat))


func riser(from_bar: int, to_bar: int, gain := 0.25) -> void:
	var start := int(round(bar_time(from_bar) * RATE))
	var end := mini(samples.size(), int(round(bar_time(to_bar) * RATE)))
	var low := 0.0
	for i in range(start, end):
		var progress := float(i - start) / (end - start)
		var noise := rng.randf_range(-1.0, 1.0)
		var cutoff := lerpf(0.02, 0.9, progress * progress)
		low = lerpf(low, noise, cutoff)
		samples[i] += low * gain * (0.15 + progress)


func four_on_floor(from_bar: int, to_bar: int, gain := 1.0) -> void:
	for beat in range(from_bar * 4, to_bar * 4):
		kick(beat, gain)


func offbeat_hats(from_bar: int, to_bar: int, gain := 1.0) -> void:
	for beat in range(from_bar * 4, to_bar * 4):
		hat(beat + 0.5, gain)


func backbeat(from_bar: int, to_bar: int, gain := 1.0) -> void:
	for bar in range(from_bar, to_bar):
		snare(bar * 4 + 1, gain)
		snare(bar * 4 + 3, gain)


func normalise(peak := 0.8) -> void:
	var top := 0.0
	for value in samples:
		top = maxf(top, absf(value))
	if top > 0.0:
		for i in samples.size():
			samples[i] *= peak / top


func save_wav(path: String, left := 1.0, right := -1.0) -> void:
	var stereo := right >= 0.0
	var channels := 2 if stereo else 1
	var data := PackedByteArray()
	data.resize(samples.size() * 2 * channels)
	for i in samples.size():
		if stereo:
			data.encode_s16(i * 4, int(clampf(samples[i] * left, -1.0, 1.0) * 32767.0))
			data.encode_s16(i * 4 + 2, int(clampf(samples[i] * right, -1.0, 1.0) * 32767.0))
		else:
			data.encode_s16(i * 2, int(clampf(samples[i] * left, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = stereo
	wav.data = data
	wav.save_to_wav(path)


func _make_kick() -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(RATE * 0.25))
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		phase += TAU * (50.0 + 90.0 * exp(-t * 30.0)) / RATE
		buffer[i] = sin(phase) * exp(-t * 14.0) * 0.9
	return buffer


func _make_snare() -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(RATE * 0.18))
	for i in buffer.size():
		var t := float(i) / RATE
		buffer[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 22.0) * 0.45 + sin(TAU * 185.0 * t) * exp(-t * 30.0) * 0.35
	return buffer


func _make_hat() -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(RATE * 0.05))
	var previous := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		buffer[i] = (noise - previous) * exp(-t * 70.0) * 0.18
		previous = noise
	return buffer
