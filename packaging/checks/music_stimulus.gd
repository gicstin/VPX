extends RefCounted

const BANDS := 48
const ROWS := 50

var bpm := 120.0
var voices: Array[Dictionary] = []
var envelope := 0.0
var onset := 0.0
var kicks: Array[float] = []
var axes: Array[Vector3] = []


func _init() -> void:
	for cell in 48:
		var az := float(cell % 16) * TAU / 16.0
		var el := float(cell / 16 - 1) * PI / 4.0
		axes.append(Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)))


static func band_of(frequency: float) -> float:
	return log(frequency / 30.0) / log(600.0) * BANDS


func clear() -> void:
	voices.clear()
	kicks.clear()


func add(centre: float, spread: float, amplitude: float, pan := 0.0) -> void:
	voices.append({"centre": centre, "spread": maxf(0.5, spread), "amplitude": amplitude, "pan": clampf(pan, -1.0, 1.0)})


func beat_length() -> float:
	return 60.0 / bpm


func kick(t: float, start := 0.0, amplitude := 0.9, every := 1.0) -> void:
	if t < start:
		return
	var period := beat_length() * every
	var since := fmod(t - start, period)
	var index := floorf((t - start) / period)
	var hit := start + index * period
	if kicks.is_empty() or absf(kicks[-1] - hit) > 0.001:
		kicks.append(hit)
	var decay := exp(-since / 0.11)
	add(band_of(55.0), 2.0, amplitude * decay)
	add(band_of(2500.0), 3.0, amplitude * 0.12 * exp(-since / 0.012))


func hats(t: float, amplitude := 0.22, division := 2.0, pan := 0.35) -> void:
	var period := beat_length() / division
	var since := fmod(t, period)
	var index := int(floor(t / period))
	add(band_of(9000.0), 3.0, amplitude * exp(-since / 0.035), pan if index % 2 == 0 else -pan)


func snare(t: float, amplitude := 0.4) -> void:
	var since := fmod(t + beat_length(), beat_length() * 2.0)
	add(band_of(1800.0), 4.0, amplitude * exp(-since / 0.13))
	add(band_of(200.0), 1.5, amplitude * 0.5 * exp(-since / 0.06))


func bass(t: float, amplitude := 0.4) -> void:
	var notes := [55.0, 55.0, 65.4, 49.0]
	var bar := int(floor(t / (beat_length() * 4.0))) % notes.size()
	var since := fmod(t, beat_length() * 0.5)
	add(band_of(notes[bar] * 2.0), 1.5, amplitude * (0.6 + 0.4 * exp(-since / 0.15)))


func pad(t: float, amplitude := 0.12) -> void:
	var swell := 0.85 + 0.15 * sin(t * 0.9)
	for partial in [220.0, 277.2, 329.6, 440.0, 659.3]:
		add(band_of(partial), 1.2, amplitude * swell * (220.0 / partial), -0.4 if partial < 300.0 else 0.4)


func groove(t: float, level := 1.0) -> void:
	kick(t, 0.0, 0.9 * level)
	bass(t, 0.38 * level)
	hats(t, 0.2 * level)
	snare(t, 0.35 * level)
	pad(t, 0.12 * level)


func frame(dt: float, mono := false) -> Dictionary:
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(BANDS)
	right.resize(BANDS)
	var cross := 0.0
	for voice in voices:
		var amplitude: float = voice["amplitude"]
		if amplitude <= 0.00001:
			continue
		var pan: float = voice["pan"]
		var gain_left := cos((pan + 1.0) * PI * 0.25) * sqrt(2.0)
		var gain_right := sin((pan + 1.0) * PI * 0.25) * sqrt(2.0)
		if mono:
			gain_left = 1.0
			gain_right = 1.0
		var low := maxi(0, int(floor(float(voice["centre"]) - float(voice["spread"]) * 2.5)))
		var high := mini(BANDS - 1, int(ceil(float(voice["centre"]) + float(voice["spread"]) * 2.5)))
		for band in range(low, high + 1):
			var distance := (band - float(voice["centre"])) / float(voice["spread"])
			var power := amplitude * amplitude * exp(-distance * distance)
			left[band] += power * gain_left * gain_left
			right[band] += power * gain_right * gain_right
			cross += power * gain_left * gain_right
	var data := PackedFloat32Array()
	data.resize(BANDS * ROWS)
	var total := Vector2.ZERO
	for band in BANDS:
		data[band] = _level(sqrt(left[band]))
		data[BANDS + band] = _level(sqrt(right[band]))
		total += Vector2(left[band], right[band])
	for band in BANDS:
		var magnitude := Vector2(sqrt(left[band]), sqrt(right[band]))
		var pan := (magnitude.y * magnitude.y - magnitude.x * magnitude.x) / maxf(0.000000000001, magnitude.length_squared())
		var direction := Vector3(pan, 0, -sqrt(maxf(0.0, 1.0 - pan * pan)))
		for cell in 48:
			var dot := maxf(0.0, axes[cell].dot(direction))
			data[(cell + 2) * BANDS + band] = _level(maxf(magnitude.x, magnitude.y) * pow(dot, 10.0))
	var rms := sqrt((total.x + total.y) * 0.5 / BANDS) * 0.9
	onset = maxf(maxf(0.0, rms - envelope * 1.15), onset * exp(-dt * 22.0))
	envelope = lerpf(envelope, rms, 1.0 - exp(-dt * (40.0 if rms > envelope else 4.0)))
	var correlation := clampf(cross / sqrt(total.x * total.y), -1.0, 1.0) if total.x * total.y > 0.000000000001 else 1.0
	var width := sqrt(clampf((total.x + total.y - 2.0 * cross) / maxf(0.000000000001, 2.0 * (total.x + total.y)), 0.0, 1.0))
	voices.clear()
	return {"spectrum": data, "features": {"rms": rms, "onset": onset, "width": width, "correlation": correlation, "channels": 1 if mono else 2}}


func waveform(t: float, data: PackedFloat32Array) -> PackedFloat32Array:
	var wave := PackedFloat32Array()
	wave.resize(512)
	var low := (data[4] + data[52]) * 0.5
	var mid := (data[24] + data[72]) * 0.5
	var high := (data[42] + data[90]) * 0.5
	for sample in 256:
		var s := float(sample) / 48000.0
		var shared := sin(TAU * 110.0 * (t + s)) * low * 0.5 + sin(TAU * 880.0 * (t + s)) * mid * 0.3 + sin(TAU * 5200.0 * (t + s)) * high * 0.15
		wave[sample] = shared * (1.0 + (data[24] - data[72]))
		wave[256 + sample] = shared * (1.0 - (data[24] - data[72]))
	return wave


static func _level(magnitude: float) -> float:
	return clampf((linear_to_db(maxf(magnitude, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
