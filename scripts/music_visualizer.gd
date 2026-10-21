extends FloatPanel

const BUS := "VPX media analysis"
const BANDS := 48
const ANALYSIS_INTERVAL := 1.0 / 90.0
const NATIVE_GAP_TIMEOUT := 0.05
const WAVE_SAMPLES := 256
const WAVE_RATE := 4000.0
const WAVE_HISTORY := 4096
const SCOPE_HISTORY := 65536
const SCOPE_WINDOW := 0.024
const SCOPE_SEARCH := 0.025
const SCOPE_POINTS := 320
const OSCILLOSCOPE := 2

var player: VPXPlayer
var camera: Camera3D
var menu: Node3D
var field: ResonanceField
var analyzer: AudioEffectSpectrumAnalyzerInstance
var bus_index := -1
var output_bus: StringName = &"Master"
var effect: AudioEffectSpectrumAnalyzer
var spectrum: SpectrumCanvas
var desktop_rect: TextureRect
var elapsed := 0.0
var enabled := false
var analysing := false
var levels := PackedFloat32Array()
var targets := PackedFloat32Array()
var frequencies := PackedFloat32Array()
var fallback_axes := PackedVector3Array()
var bound_playback: FFmpegVideoStreamPlayback
var native_analysis := false
var last_position := -1.0
var last_feature_time := -1.0
var sample_age := 0.0
var capture_effect: AudioEffectCapture
var capturing := false
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
var scope_gain := 1.0
var native_features := {}
var audio_power := Vector3.ZERO
var audio_envelope := 0.0
var audio_onset := 0.0
var source_channels := 2
var analysis_history: Array[Dictionary] = []
var last_analysis_time := -1.0


func _ready() -> void:
	panel_size = Vector2(0.6, 0.15)
	distance = 1.4
	drop = 0.55
	tilt = 0.0
	levels.resize(BANDS)
	targets.resize(BANDS)
	for i in BANDS + 1:
		frequencies.append(30.0 * pow(600.0, float(i) / BANDS))
	for cell in 48:
		var az := float(cell % 16) * TAU / 16.0
		var el := float(cell / 16 - 1) * PI / 4.0
		var direction := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		fallback_axes.append(direction)
	super._ready()
	bus_index = AudioServer.get_bus_index(BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, BUS)
	output_bus = player.bus
	AudioServer.set_bus_send(bus_index, output_bus)
	effect = AudioEffectSpectrumAnalyzer.new()
	effect.buffer_length = 0.1
	effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(bus_index, effect)
	AudioServer.set_bus_effect_enabled(bus_index, _effect_index(), false)
	capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 0.15
	AudioServer.add_bus_effect(bus_index, capture_effect)
	analyzer = AudioServer.get_bus_effect_instance(bus_index, _effect_index())
	AudioServer.set_bus_effect_enabled(bus_index, _effect_index(capture_effect), false)
	wave_left.resize(WAVE_HISTORY)
	wave_right.resize(WAVE_HISTORY)
	scope_left.resize(WAVE_HISTORY)
	scope_right.resize(WAVE_HISTORY)
	var scope_history := maxi(SCOPE_HISTORY, ceili(AudioServer.get_mix_rate() * (0.5 + SCOPE_WINDOW + SCOPE_SEARCH)) + 1)
	mono.resize(scope_history)
	mono_trigger.resize(scope_history)
	player.bus = BUS
	if desktop_rect != null:
		desktop_rect.texture = viewport.get_texture()
		spectrum.embedded = true


func _effect_index(target_effect: AudioEffect = null) -> int:
	if target_effect == null:
		target_effect = effect
	for i in AudioServer.get_bus_effect_count(bus_index):
		if AudioServer.get_bus_effect(bus_index, i) == target_effect:
			return i
	return -1


func _build() -> Control:
	spectrum = SpectrumCanvas.new()
	return spectrum


func _bind() -> void:
	if bound_playback != null and native_analysis:
		bound_playback.set_visualizer_enabled(false)
	bound_playback = player.playback
	source_channels = int(bound_playback.get_audio_info().get("channels", 2)) if bound_playback != null else 2
	native_analysis = bound_playback != null and bound_playback.has_method("get_visualizer_state") and bound_playback.has_method("set_visualizer_enabled")
	if native_analysis:
		bound_playback.set_visualizer_enabled(analysing)
	AudioServer.set_bus_effect_enabled(bus_index, _effect_index(), analysing)
	_reset()


func _reset() -> void:
	levels.fill(0.0)
	targets.fill(0.0)
	last_feature_time = -1.0
	last_position = -1.0
	sample_age = 0.0
	native_features.clear()
	analysis_history.clear()
	_reset_waveform()
	if field != null:
		field.reset()


func _process(delta: float) -> void:
	var musical := player.playback != null and (player.is_music_mode() or (player.is_image() and not player.music_path.is_empty()))
	var immersive := player.is_immersive_visualizer_active()
	var wanted: bool = (Settings.music_visualizer and musical) or immersive
	if wanted != analysing:
		analysing = wanted
		if bound_playback != null and native_analysis:
			bound_playback.set_visualizer_enabled(analysing)
		AudioServer.set_bus_effect_enabled(bus_index, _effect_index(), analysing)
		_reset()
	if bound_playback != player.playback:
		_bind()
	var show_panel := Settings.music_visualizer and musical and not menu.visible
	if show_panel != enabled:
		enabled = show_panel
		if enabled:
			present(camera)
		else:
			dismiss()
	if field != null:
		field.set_active(immersive)
	var want_capture := analysing and (immersive or (Settings.music_visualizer and Settings.music_visualizer_mode == OSCILLOSCOPE))
	if capturing != want_capture:
		capturing = want_capture
		AudioServer.set_bus_effect_enabled(bus_index, _effect_index(capture_effect), capturing)
		_reset_waveform()
	super._process(delta)
	if desktop_rect != null:
		desktop_rect.modulate.a = opacity
		quad.visible = false
	if not analysing:
		return
	var position_now := player.stream_position
	if last_position >= 0.0 and absf(position_now - last_position) > maxf(0.3, delta * Settings.playback_speed * 4.0):
		_reset()
	last_position = position_now
	var silent := player.paused or not player.is_playing()
	if silent:
		_reset_waveform()
		analysis_history.clear()
		targets.fill(0.0)
		if field != null:
			field.silence()
	else:
		if capturing:
			_sample_waveform()
		elapsed += delta
		sample_age += delta
		if elapsed >= ANALYSIS_INTERVAL:
			elapsed = fmod(elapsed, ANALYSIS_INTERVAL)
			if native_analysis:
				_sample_native()
			_sample_fallback(not native_analysis)
	for i in BANDS:
		var blend := 1.0 - exp(-delta * (60.0 if targets[i] > levels[i] else 10.0))
		levels[i] = lerpf(levels[i], targets[i], blend)
	spectrum.levels = levels
	spectrum.oscilloscope = Settings.music_visualizer_mode == OSCILLOSCOPE
	spectrum.title = (player.music_path if not player.music_path.is_empty() else player.current_path).get_file().get_basename()
	if enabled:
		spectrum.queue_redraw()


func _reset_waveform() -> void:
	wave_left.fill(0.0)
	wave_right.fill(0.0)
	wave_position = 0
	wave_phase = 0.0
	wave_dc = Vector2.ZERO
	wave_low = Vector2.ZERO
	wave_filtered = Vector2.ZERO
	wave_smooth = Vector2.ZERO
	wave_bass = Vector2.ZERO
	scope_left.fill(0.0)
	scope_right.fill(0.0)
	scope_low = Vector2.ZERO
	scope_tone = Vector2.ZERO
	mono.fill(0.0)
	mono_trigger.fill(0.0)
	mono_position = 0
	mono_low = 0.0
	mono_smooth = 0.0
	scope_gain = 1.0
	audio_power = Vector3.ZERO
	audio_envelope = 0.0
	audio_onset = 0.0
	last_analysis_time = -1.0
	spectrum.wave = PackedFloat32Array()
	if capture_effect != null:
		capture_effect.clear_buffer()
	if field != null:
		field.clear_waveform()


func _sample_waveform() -> void:
	var available := capture_effect.get_frames_available()
	if available == 0:
		return
	var frames := capture_effect.get_buffer(available)
	var rate := AudioServer.get_mix_rate()
	_capture_frames(frames, rate)
	if Settings.music_visualizer and Settings.music_visualizer_mode == OSCILLOSCOPE:
		_update_scope(rate, frames.size() / rate)
	_update_waveform()


func _capture_frames(frames: PackedVector2Array, rate: float) -> void:
	if frames.is_empty():
		return
	var power := audio_power
	var phase := wave_phase
	var dc := wave_dc
	var low := wave_low
	var filtered := wave_filtered
	var smooth := wave_smooth
	var bass := wave_bass
	var scope_filter := scope_low
	var tone := scope_tone
	var trigger := mono_low
	var display := mono_smooth
	var mono_index := mono_position
	var wave_index := wave_position
	var wave_step := WAVE_RATE / rate
	var mono_size := mono.size()
	var low_blend := 1.0 - exp(-TAU * 180.0 / rate)
	var dc_blend := 1.0 - exp(-TAU * 25.0 / rate)
	var scope_blend := 1.0 - exp(-TAU * 1600.0 / rate)
	var trigger_blend := 1.0 - exp(-TAU * 300.0 / rate)
	var display_blend := 1.0 - exp(-TAU * 3000.0 / rate)
	var power_blend := 1.0 - exp(-1.0 / 256.0)
	for frame: Vector2 in frames:
		power = power.lerp(Vector3(frame.x * frame.x, frame.y * frame.y, frame.x * frame.y), power_blend)
		phase += wave_step
		dc = dc.lerp(frame, dc_blend)
		low = low.lerp(frame - dc, low_blend)
		filtered = filtered.lerp(low, low_blend)
		smooth = smooth.lerp(filtered, low_blend)
		bass = bass.lerp(smooth, low_blend)
		scope_filter = scope_filter.lerp(frame - dc, scope_blend)
		tone = tone.lerp(scope_filter, scope_blend)
		var mixed := (frame.x + frame.y - dc.x - dc.y) * 0.5
		trigger = lerpf(trigger, mixed, trigger_blend)
		display = lerpf(display, mixed, display_blend)
		mono[mono_index] = display
		mono_trigger[mono_index] = trigger
		mono_index += 1
		if mono_index == mono_size:
			mono_index = 0
		if phase >= 1.0:
			phase -= 1.0
			wave_left[wave_index] = bass.x
			wave_right[wave_index] = bass.y
			scope_left[wave_index] = tone.x
			scope_right[wave_index] = tone.y
			wave_index += 1
			if wave_index == WAVE_HISTORY:
				wave_index = 0
	audio_power = power
	wave_phase = phase
	wave_dc = dc
	wave_low = low
	wave_filtered = filtered
	wave_smooth = smooth
	wave_bass = bass
	scope_low = scope_filter
	scope_tone = tone
	mono_low = trigger
	mono_smooth = display
	mono_position = mono_index
	wave_position = wave_index


func _update_waveform() -> void:
	if field == null or not field.active:
		return
	var data := PackedFloat32Array()
	data.resize(WAVE_SAMPLES * 2)
	var scope := PackedFloat32Array()
	scope.resize(WAVE_SAMPLES * 2)
	var delay_samples := int(_analysis_delay() * WAVE_RATE)
	for i in WAVE_SAMPLES:
		var index := posmod(wave_position - WAVE_SAMPLES - delay_samples + i, WAVE_HISTORY)
		data[i] = wave_left[index]
		data[WAVE_SAMPLES + i] = wave_right[index]
		scope[i] = scope_left[index]
		scope[WAVE_SAMPLES + i] = scope_right[index]
	field.feed_waveform(data)
	field.feed_scope(scope)


func _analysis_delay() -> float:
	return clampf(AudioServer.get_output_latency() - minf(Settings.visualizer_sync, Settings.visualizer_advance_limit()), 0.0, 0.5)


func _update_scope(rate: float, delta: float) -> void:
	var history := mono.size()
	var window := int(SCOPE_WINDOW * rate)
	var delay := int(_analysis_delay() * rate)
	var start := mono_position - delay - window
	var trigger := start
	for offset in int(SCOPE_SEARCH * rate):
		var index := start - offset
		if mono_trigger[posmod(index - 1, history)] < 0.0 and mono_trigger[posmod(index, history)] >= 0.0:
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
			total += mono[posmod(index, history)]
		wave[point] = total / (to - from)
		peak = maxf(peak, absf(wave[point]))
	var wanted_gain := clampf(0.8 / maxf(peak, 0.0001), 1.0, 10.0)
	scope_gain = lerpf(scope_gain, wanted_gain, 1.0 - exp(-delta * (12.0 if wanted_gain < scope_gain else 2.0)))
	for point in SCOPE_POINTS:
		wave[point] = tanh(wave[point] * scope_gain * 1.2)
	spectrum.wave = wave


static func _mix(left: float, right: float) -> float:
	var amplitude := (db_to_linear(left * 60.0 - 60.0) + db_to_linear(right * 60.0 - 60.0)) * 0.5
	return clampf((linear_to_db(maxf(amplitude, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)


func _sample_native() -> void:
	var offset := -_analysis_delay() * 1000.0
	var features: Dictionary = bound_playback.get_visualizer_state(offset)
	if features.is_empty():
		return
	var time := float(features.get("time", -1.0))
	if time == last_feature_time:
		return
	var data: PackedFloat32Array = features.get("spectrum", PackedFloat32Array())
	if data.size() != BANDS * 50:
		return
	last_feature_time = time
	sample_age = 0.0
	native_features = features
	source_channels = int(features.get("channels", source_channels))


func _sample_fallback(reset_age := true) -> void:
	var data := PackedFloat32Array()
	data.resize(BANDS * 50)
	var magnitudes := PackedVector2Array()
	for i in BANDS:
		magnitudes.append(analyzer.get_magnitude_for_frequency_range(frequencies[i], frequencies[i + 1], AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE))
	var now := Time.get_ticks_usec() * 0.000001
	var delta := maxf(0.0, now - last_analysis_time) if last_analysis_time >= 0.0 else ANALYSIS_INTERVAL
	last_analysis_time = now
	analysis_history.append({"time": now, "magnitudes": magnitudes, "power": audio_power})
	while analysis_history.size() > 128 or (analysis_history.size() > 1 and now - float(analysis_history[0]["time"]) > 0.65):
		analysis_history.pop_front()
	var selected := {}
	var selected_time := now - _analysis_delay()
	for i in range(analysis_history.size() - 1, -1, -1):
		if float(analysis_history[i]["time"]) <= selected_time:
			selected = analysis_history[i]
			break
	var power: Vector3 = selected.get("power", Vector3.ZERO)
	magnitudes = selected.get("magnitudes", PackedVector2Array())
	if magnitudes.is_empty():
		magnitudes.resize(BANDS)
	var rms := sqrt(maxf(0.0, (power.x + power.y) * 0.5))
	var correlation := clampf(power.z / sqrt(power.x * power.y), -1.0, 1.0) if power.x * power.y > 0.000000000001 else 1.0
	var width := sqrt(clampf((power.x + power.y - 2.0 * power.z) / maxf(0.000000000001, 2.0 * (power.x + power.y)), 0.0, 1.0))
	audio_onset = maxf(maxf(0.0, rms - audio_envelope * 1.15), audio_onset * exp(-delta * 22.0))
	audio_envelope = lerpf(audio_envelope, rms, 1.0 - exp(-delta * (40.0 if rms > audio_envelope else 4.0)))
	var features := {"rms": rms, "onset": audio_onset, "width": width, "correlation": correlation, "channels": 1 if source_channels == 1 else 2}
	var native_data: PackedFloat32Array = native_features.get("spectrum", PackedFloat32Array())
	var spatial := native_analysis and sample_age <= NATIVE_GAP_TIMEOUT and int(native_features.get("channels", 2)) > 2 and native_data.size() == BANDS * 50
	if spatial:
		features["channels"] = native_features["channels"]
		features["ambisonic"] = native_features.get("ambisonic", false)
		features["spatial"] = bound_playback.get_audio_info().get("spatial", false)
	for i in BANDS:
		var magnitude := magnitudes[i]
		data[i] = clampf((linear_to_db(maxf(magnitude.x, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
		data[BANDS + i] = clampf((linear_to_db(maxf(magnitude.y, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
		targets[i] = clampf((linear_to_db(maxf((magnitude.x + magnitude.y) * 0.5, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
	if reset_age:
		sample_age = 0.0
	if field != null and field.active:
		_fill_directions(data, magnitudes, correlation, native_data if spatial else PackedFloat32Array())
		field.feed(data, features)


func _fill_directions(data: PackedFloat32Array, magnitudes: PackedVector2Array, correlation: float, spatial_data := PackedFloat32Array()) -> void:
	if not spatial_data.is_empty():
		for band in BANDS:
			var native_peak := maxf(spatial_data[band], spatial_data[BANDS + band])
			var peak := maxf(data[band], data[BANDS + band])
			for cell in 48:
				var index := (cell + 2) * BANDS + band
				data[index] = clampf(spatial_data[index] + peak - native_peak, 0.0, 1.0) if spatial_data[index] > 0.0 else 0.0
		return
	var diffuse := (1.0 - correlation) * 0.35
	for band in BANDS:
		var magnitude := magnitudes[band]
		var peak := maxf(magnitude.x, magnitude.y)
		if peak <= 0.000001:
			continue
		var pan := (magnitude.y * magnitude.y - magnitude.x * magnitude.x) / maxf(0.000000000001, magnitude.length_squared())
		var direction := Vector3(pan, 0, -sqrt(maxf(0.0, 1.0 - pan * pan)))
		for cell in 32:
			var dot := fallback_axes[cell].dot(direction)
			if dot <= 0.0:
				continue
			var weight := pow(dot, 10.0) * (1.0 - diffuse) + dot * dot * diffuse
			var value := clampf((linear_to_db(maxf(peak * weight, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
			data[(cell + 2) * BANDS + band] = value
			if cell < 16:
				data[(cell + 34) * BANDS + band] = value


func _exit_tree() -> void:
	if bound_playback != null and native_analysis:
		bound_playback.set_visualizer_enabled(false)
	if is_instance_valid(player) and player.bus == BUS:
		player.bus = output_bus
	var index := AudioServer.get_bus_index(BUS)
	if index >= 0:
		var capture_index := _effect_index(capture_effect)
		if capture_index >= 0:
			AudioServer.remove_bus_effect(index, capture_index)
		var owned := _effect_index()
		if owned >= 0:
			AudioServer.remove_bus_effect(index, owned)


class SpectrumCanvas extends Control:
	const SMOOTH_STEPS := 4

	var levels := PackedFloat32Array()
	var wave := PackedFloat32Array()
	var oscilloscope := false
	var title := ""
	var embedded := false
	var scope_indices := PackedInt32Array()
	var gradient_state: Array = []
	var gradients := {}
	var background := VpxTheme.flat(VpxTheme.OVERLAY, 18, 12, 10)
	var font := ThemeDB.fallback_font

	func _draw() -> void:
		if not embedded:
			draw_style_box(background, Rect2(Vector2.ZERO, size))
			draw_string(font, Vector2(16, 27), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 20, VpxTheme.TEXT)
		var top := 10.0 if embedded else 44.0
		var area := Rect2(16.0, top, size.x - 32.0, size.y - top - (6.0 if embedded else 12.0))
		if oscilloscope:
			_draw_scope(area)
		elif not levels.is_empty():
			_draw_spectrum(area)

	func _draw_spectrum(area: Rect2) -> void:
		var base := area.end.y
		var points := PackedVector2Array()
		for i in levels.size():
			points.append(Vector2(area.position.x + float(i) * area.size.x / (levels.size() - 1), base - clampf(levels[i], 0.0, 1.0) * area.size.y))
		points = _smooth(points)
		for i in points.size():
			points[i].y = clampf(points[i].y, area.position.y, base)
		var colors := _gradient(points, area, 1.0)
		var fill := points.duplicate()
		var fill_colors := _gradient(points, area, 0.45)
		for i in range(points.size() - 1, -1, -1):
			fill.append(Vector2(points[i].x, base + 1.0))
			fill_colors.append(Color(fill_colors[i], 0.0))
		draw_polygon(fill, fill_colors)
		draw_polyline_colors(points, _gradient(points, area, 0.18), 6.0, true)
		draw_polyline_colors(points, colors, 2.2, true)
		draw_line(Vector2(area.position.x, base + 1.0), Vector2(area.end.x, base + 1.0), Color(VpxTheme.ACCENT, 0.25), 1.0, true)

	func _draw_scope(area: Rect2) -> void:
		var middle := area.get_center().y
		var half := area.size.y * 0.5
		draw_line(Vector2(area.position.x, middle), Vector2(area.end.x, middle), Color(VpxTheme.ACCENT, 0.3), 1.0, true)
		if wave.size() < 2:
			return
		var points := PackedVector2Array()
		for i in wave.size():
			points.append(Vector2(area.position.x + float(i) * area.size.x / (wave.size() - 1), middle - wave[i] * half))
		var colors := _gradient(points, area, 1.0)
		var fill := PackedVector2Array()
		var shades := PackedColorArray()
		fill.resize(points.size() * 2)
		shades.resize(fill.size())
		for i in points.size():
			fill[i * 2] = points[i]
			fill[i * 2 + 1] = Vector2(points[i].x, middle)
			shades[i * 2] = Color(colors[i], 0.4)
			shades[i * 2 + 1] = Color(colors[i], 0.0)
		if scope_indices.size() != (points.size() - 1) * 6:
			scope_indices.resize((points.size() - 1) * 6)
			for i in points.size() - 1:
				var vertex := i * 2
				scope_indices[i * 6] = vertex
				scope_indices[i * 6 + 1] = vertex + 2
				scope_indices[i * 6 + 2] = vertex + 3
				scope_indices[i * 6 + 3] = vertex
				scope_indices[i * 6 + 4] = vertex + 3
				scope_indices[i * 6 + 5] = vertex + 1
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), scope_indices, fill, shades)
		draw_polyline_colors(points, _gradient(points, area, 0.14), 8.0, true)
		draw_polyline_colors(points, _gradient(points, area, 0.3), 4.0, true)
		draw_polyline_colors(points, colors, 2.0, true)

	func _gradient(points: PackedVector2Array, area: Rect2, alpha: float) -> PackedColorArray:
		var state := [area, points.size(), oscilloscope, VpxTheme.ACCENT, VpxTheme.SPECTRUM_END]
		if gradient_state != state:
			gradient_state = state
			gradients.clear()
		if not gradients.has(alpha):
			var colors := PackedColorArray()
			for point in points:
				colors.append(Color(VpxTheme.ACCENT.lerp(VpxTheme.SPECTRUM_END, clampf((point.x - area.position.x) / area.size.x, 0.0, 1.0)), alpha))
			gradients[alpha] = colors
		return gradients[alpha].duplicate()

	static func _smooth(points: PackedVector2Array) -> PackedVector2Array:
		var result := PackedVector2Array()
		var last := points.size() - 1
		for i in last:
			var p0 := points[maxi(i - 1, 0)]
			var p1 := points[i]
			var p2 := points[i + 1]
			var p3 := points[mini(i + 2, last)]
			for step in SMOOTH_STEPS:
				var t := float(step) / SMOOTH_STEPS
				var t2 := t * t
				var t3 := t2 * t
				result.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
		result.append(points[last])
		return result
