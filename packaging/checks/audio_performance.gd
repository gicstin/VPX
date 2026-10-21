extends SceneTree

const FIELDS := ["wave_position", "wave_phase", "wave_dc", "wave_low", "wave_filtered", "wave_smooth", "wave_bass", "scope_low", "scope_tone", "mono_position", "mono_low", "mono_smooth", "audio_power", "wave_left", "wave_right", "scope_left", "scope_right", "mono", "mono_trigger"]

var checks := 0
var failures := 0
var measurements := {}


class Reference extends RefCounted:
	const WAVE_RATE := 4000.0
	const WAVE_HISTORY := 4096
	const SCOPE_WINDOW := 0.024
	const SCOPE_SEARCH := 0.025
	const SCOPE_POINTS := 320
	var scope_gain := 1.0
	var delay := 0.0
	var spectrum: Control

	var wave_left := PackedFloat32Array()
	var wave_right := PackedFloat32Array()
	var wave_position := 0
	var wave_phase := 0.0
	var wave_dc := Vector2.ZERO
	var wave_low := Vector2.ZERO
	var wave_filtered := Vector2.ZERO
	var wave_smooth := Vector2.ZERO
	var wave_bass := Vector2.ZERO
	var scope_left := PackedFloat32Array()
	var scope_right := PackedFloat32Array()
	var scope_low := Vector2.ZERO
	var scope_tone := Vector2.ZERO
	var mono := PackedFloat32Array()
	var mono_trigger := PackedFloat32Array()
	var mono_position := 0
	var mono_low := 0.0
	var mono_smooth := 0.0
	var audio_power := Vector3.ZERO

	func _analysis_delay() -> float:
		return delay

	func _capture_frames(frames: PackedVector2Array, rate: float) -> void:
		var low_blend := 1.0 - exp(-TAU * 180.0 / rate)
		var dc_blend := 1.0 - exp(-TAU * 25.0 / rate)
		var scope_blend := 1.0 - exp(-TAU * 1600.0 / rate)
		var trigger_blend := 1.0 - exp(-TAU * 300.0 / rate)
		var display_blend := 1.0 - exp(-TAU * 3000.0 / rate)
		var power_blend := 1.0 - exp(-1.0 / 256.0)
		for frame in frames:
			audio_power = audio_power.lerp(Vector3(frame.x * frame.x, frame.y * frame.y, frame.x * frame.y), power_blend)
			wave_phase += WAVE_RATE / rate
			wave_dc = wave_dc.lerp(frame, dc_blend)
			wave_low = wave_low.lerp(frame - wave_dc, low_blend)
			wave_filtered = wave_filtered.lerp(wave_low, low_blend)
			wave_smooth = wave_smooth.lerp(wave_filtered, low_blend)
			wave_bass = wave_bass.lerp(wave_smooth, low_blend)
			scope_low = scope_low.lerp(frame - wave_dc, scope_blend)
			scope_tone = scope_tone.lerp(scope_low, scope_blend)
			var mixed := (frame.x + frame.y - wave_dc.x - wave_dc.y) * 0.5
			mono_low = lerpf(mono_low, mixed, trigger_blend)
			mono_smooth = lerpf(mono_smooth, mixed, display_blend)
			mono[mono_position] = mono_smooth
			mono_trigger[mono_position] = mono_low
			mono_position = (mono_position + 1) % mono.size()
			if wave_phase >= 1.0:
				wave_phase -= 1.0
				wave_left[wave_position] = wave_bass.x
				wave_right[wave_position] = wave_bass.y
				scope_left[wave_position] = scope_tone.x
				scope_right[wave_position] = scope_tone.y
				wave_position = (wave_position + 1) % WAVE_HISTORY

	func _update_scope(rate: float, delta: float) -> void:
		var window := int(SCOPE_WINDOW * rate)
		var delay := int(_analysis_delay() * rate)
		var start := mono_position - delay - window
		var trigger := start
		for offset in int(SCOPE_SEARCH * rate):
			var index := start - offset
			if mono_trigger[posmod(index - 1, mono.size())] < 0.0 and mono_trigger[posmod(index, mono.size())] >= 0.0:
				trigger = index
				break
		var peak := 0.0
		var wave := PackedFloat32Array()
		wave.resize(SCOPE_POINTS)
		for point in SCOPE_POINTS:
			var from := trigger + point * window / SCOPE_POINTS
			var to := maxi(trigger + (point + 1) * window / SCOPE_POINTS, from + 1)
			var total := 0.0
			for index in range(from, to):
				total += mono[posmod(index, mono.size())]
			wave[point] = total / (to - from)
			peak = maxf(peak, absf(wave[point]))
		var wanted_gain := clampf(0.8 / maxf(peak, 0.0001), 1.0, 10.0)
		scope_gain = lerpf(scope_gain, wanted_gain, 1.0 - exp(-delta * (12.0 if wanted_gain < scope_gain else 2.0)))
		for point in SCOPE_POINTS:
			wave[point] = tanh(wave[point] * scope_gain * 1.2)
		spectrum.wave = wave


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func capture(reference: bool) -> Object:
	var script = load("res://scripts/music_visualizer.gd")
	var node = Reference.new() if reference else script.new()
	node.spectrum = script.SpectrumCanvas.new()
	for property in ["wave_left", "wave_right", "scope_left", "scope_right"]:
		var values := PackedFloat32Array()
		values.resize(4096)
		node.set(property, values)
	for property in ["mono", "mono_trigger"]:
		var values := PackedFloat32Array()
		values.resize(65536)
		node.set(property, values)
	return node


func measure(name: String, action: Callable) -> void:
	for warmup in 20:
		action.call()
	var samples: Array[float] = []
	for sample in 7:
		var started := Time.get_ticks_usec()
		for i in 100:
			action.call()
		samples.append((Time.get_ticks_usec() - started) / 100000.0)
	samples.sort()
	measurements[name] = {"median_ms": samples[3], "samples_ms": samples}
	print("BENCH %s median=%.5f ms" % [name, samples[3]])


func run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: audio performance timeout"); quit(2))
	var reference := capture(true)
	var actual := capture(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2021021
	var total := 0
	for rate in [8000.0, 44100.0, 48000.0, 96000.0, 192000.0]:
		for batch in 48:
			var frames := PackedVector2Array()
			frames.resize(0 if batch == 0 else rng.randi_range(1, 2048))
			for i in frames.size():
				var left := sin((total + i) * TAU * 110.0 / rate) * 0.5
				match batch % 5:
					0: frames[i] = Vector2.ZERO
					1: frames[i] = Vector2(left, left)
					2: frames[i] = Vector2(left, -left)
					3: frames[i] = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
					4: frames[i] = Vector2(left + 0.25, 0.0)
			total += frames.size()
			reference._capture_frames(frames, rate)
			actual._capture_frames(frames, rate)
			for property in FIELDS:
				check(actual.get(property) == reference.get(property), "capture matches reference %s at %s Hz batch %s" % [property, rate, batch])
	check(total > actual.SCOPE_HISTORY * 2, "capture covers repeated ring wraps")
	var frames := PackedVector2Array()
	frames.resize(480)
	for i in frames.size():
		frames[i] = Vector2(sin(i * 0.1), cos(i * 0.13)) * 0.5
	measure("capture_reference_480", func() -> void: reference._capture_frames(frames, 48000.0))
	measure("capture_optimized_480", func() -> void: actual._capture_frames(frames, 48000.0))
	var settings := root.get_node("Settings")
	for rate in [8000.0, 44100.0, 48000.0, 96000.0, 192000.0]:
		for sync in [-0.5, -0.1, 0.0, 0.05, 0.5]:
			settings.visualizer_sync = sync
			reference.delay = actual._analysis_delay()
			for position in [0, 1, 65535, 32000]:
				actual.mono_position = position
				reference.mono_position = position
				reference._update_scope(rate, 1.0 / 90.0)
				actual._update_scope(rate, 1.0 / 90.0)
				check(reference.spectrum.wave == actual.spectrum.wave and reference.scope_gain == actual.scope_gain, "scope matches reference across rates, delays and ring boundaries")
	settings.visualizer_sync = 0.0
	reference.delay = actual._analysis_delay()
	for node in [reference, actual]:
		node.mono_trigger.fill(1.0)
		node._update_scope(48000.0, 1.0 / 90.0)
	check(reference.spectrum.wave == actual.spectrum.wave and reference.scope_gain == actual.scope_gain, "scope without zero crossings preserves window and gain")
	measure("scope_reference_48000", func() -> void: reference._update_scope(48000.0, 1.0 / 90.0))
	measure("scope_optimized_48000", func() -> void: actual._update_scope(48000.0, 1.0 / 90.0))
	actual._reset_waveform()
	for property in FIELDS:
		var value = reference.get(property)
		if value is PackedFloat32Array:
			value.fill(0.0)
		else:
			value *= 0
		reference.set(property, value)
	for property in FIELDS:
		check(actual.get(property) == reference.get(property), "reset preserves capture state " + property)
	reference.spectrum.free()
	actual.spectrum.free()
	actual.free()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	check(file != null, "capture report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	print("RESULT: audio_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
