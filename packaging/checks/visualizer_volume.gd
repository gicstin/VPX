extends SceneTree

var failures := 0
var main: Node
var output_capture := AudioEffectCapture.new()

func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func rms(values: PackedFloat32Array) -> float:
	var energy := 0.0
	for value in values:
		energy += value * value
	return sqrt(energy / maxf(values.size(), 1))

func peak(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result

func make_audio(path: String, gain: float) -> void:
	var period := PackedByteArray()
	period.resize(4800 * 4)
	for i in 4800:
		period.encode_s16(i * 4, int(12000.0 * gain * sin(TAU * 70.0 * i / 48000.0)))
		period.encode_s16(i * 4 + 2, int(12000.0 * gain * sin(TAU * 110.0 * i / 48000.0)))
	var samples := PackedByteArray()
	for i in 400:
		samples.append_array(period)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.stereo = true
	audio.mix_rate = 48000
	audio.data = samples
	audio.save_to_wav(path)

func measure() -> Dictionary:
	await create_timer(0.7).timeout
	output_capture.clear_buffer()
	await create_timer(0.1).timeout
	var frames := output_capture.get_buffer(output_capture.get_frames_available())
	var output_energy := 0.0
	for frame in frames:
		output_energy += frame.x * frame.x
	var viz = main.music_visualizer
	var wave := PackedFloat32Array()
	for i in viz.WAVE_SAMPLES:
		wave.append(viz.wave_left[posmod(viz.wave_position - viz.WAVE_SAMPLES + i, viz.WAVE_HISTORY)])
	return {"spectrum": peak(viz.targets), "wave": rms(wave), "scope": peak(viz.spectrum.wave), "field": peak(main.resonance_field.wave_image.get_data().to_float32_array()), "output": sqrt(output_energy / maxf(frames.size(), 1))}

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.hide_menu_on_play = false
	settings.resume_playback = false
	settings.music_visualizer = true
	settings.immersive_music_visualizer = true
	settings.music_visualizer_mode = 2
	settings.volume = 100
	settings.muted = false
	settings.end_action = 0
	var media := "user://visualizer_volume_%d.wav" % Time.get_ticks_usec()
	var quiet_media := media.get_basename() + "_quiet.wav"
	make_audio(media, 1.0)
	make_audio(quiet_media, 0.1)
	output_capture.buffer_length = 0.2
	AudioServer.add_bus_effect(0, output_capture)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await main.player.open(ProjectSettings.globalize_path(media))
	main.panel.hide()
	main.player.paused = false
	var viz = main.music_visualizer
	await create_timer(0.2).timeout
	check(viz.native_analysis and viz.capturing and main.resonance_field.active, "native, mini scope and immersive analysis active")
	var native := await measure()
	print("BASELINE native=", native)
	check(native.spectrum > 0.4 and native.wave > 0.1 and native.scope > 0.4 and native.field > 0.1 and native.output > 0.1, "native spectrum, both waveforms and audible output have signal")
	var output_index := AudioServer.get_bus_index(main.player.OUTPUT_BUS)
	for volume in [10, 1, 0]:
		settings.volume = volume
		main.player.apply_audio()
		var actual := await measure()
		print("VOLUME ", volume, " ", actual)
		for key in ["spectrum", "wave", "scope", "field"]:
			var stable := absf(actual[key] - native[key]) < 0.15 if key == "spectrum" else absf(actual[key] / native[key] - 1.0) < 0.15
			check(stable, "%s independent of volume %d" % [key, volume])
		check(absf(actual.output - native.output * volume / 100.0) < 0.008, "audible output follows volume %d" % volume)
	settings.volume = 100
	settings.muted = true
	main.player.apply_audio()
	var muted := await measure()
	check(muted.output < 0.00001 and muted.wave > native.wave * 0.9 and muted.spectrum > 0.4 and muted.scope > 0.4 and muted.field > 0.1, "mute silences output while all visuals continue")
	settings.muted = false
	main.player.sleep_armed = settings.SleepTimer.MIN_15
	main.player.sleep_left = main.player.SLEEP_FADE * 0.5
	main.player.apply_audio()
	main.player.sleep_armed = settings.SleepTimer.OFF
	var faded := await measure()
	check(absf(faded.output / native.output - 0.5) < 0.08 and faded.wave > native.wave * 0.9, "sleep fade changes audible output without changing waveform")
	main.player.apply_audio()
	settings.music_visualizer_mode = 0
	settings.immersive_music_visualizer = false
	settings.volume = 0
	main.player.apply_audio()
	await create_timer(0.2).timeout
	check(not viz.capturing and not main.resonance_field.active and peak(viz.targets) > 0.4, "regular mini native spectrum remains active at zero volume")
	settings.music_visualizer_mode = 2
	settings.immersive_music_visualizer = true
	settings.volume = 100
	main.player.apply_audio()
	main.player.playback.set_visualizer_enabled(false)
	var outage := await measure()
	print("OUTAGE native=%s age=%.3f measurements=%s" % [viz.native_analysis, viz.sample_age, outage])
	check(viz.native_analysis and viz.sample_age > viz.NATIVE_GAP_TIMEOUT and outage.spectrum > 0.4 and outage.wave > native.wave * 0.9, "native analysis outage switches to live fallback without losing waveforms")
	viz.native_analysis = false
	var fallback := await measure()
	print("BASELINE fallback=", fallback)
	check(absf(fallback.spectrum - native.spectrum) < 0.025, "native and fallback spectrum use the same level scale")
	check(fallback.spectrum > 0.4, "fallback analyzer receives live audio")
	for volume in [10, 0]:
		settings.volume = volume
		main.player.apply_audio()
		var actual := await measure()
		check(absf(actual.spectrum - fallback.spectrum) < 0.03 and actual.wave > native.wave * 0.9, "fallback spectrum and waveform independent of volume %d" % volume)
	settings.music_visualizer_mode = 0
	settings.immersive_music_visualizer = false
	await create_timer(0.2).timeout
	check(not viz.capturing and not main.resonance_field.active and peak(viz.targets) > 0.4, "regular mini spectrum remains active at zero volume")
	settings.volume = 100
	main.player.apply_audio()
	settings.music_visualizer_mode = 2
	settings.immersive_music_visualizer = true
	await create_timer(0.2).timeout
	timing()
	await main.player.open(ProjectSettings.globalize_path(quiet_media))
	main.player.paused = false
	settings.music_visualizer_mode = 2
	settings.immersive_music_visualizer = true
	var quiet := await measure()
	check(absf(quiet.wave / native.wave - 0.1) < 0.015 and quiet.spectrum < native.spectrum - 0.2, "quieter source music still produces weaker analysis")
	main.player.paused = true
	await create_timer(0.15).timeout
	check(rms(viz.wave_left) == 0.0 and viz.spectrum.wave.is_empty() and not main.resonance_field.has_audio, "pause clears all visual audio")
	settings.volume = 10
	main.player.apply_audio()
	viz.free()
	main.music_visualizer = null
	check(main.player.bus == main.player.OUTPUT_BUS and AudioServer.get_bus_effect_count(AudioServer.get_bus_index("VPX media analysis")) == 0, "visualizer teardown restores output routing and removes effects")
	check(is_equal_approx(AudioServer.get_bus_volume_db(output_index), -20.0) and main.player.volume_db == 0.0, "playback volume remains applied after visualizer teardown")
	main.player.paused = false
	var after := await measure_output()
	check(after > 0.001 and after < 0.004, "audio keeps playing at selected volume without visualizer")
	main.player.stop()
	main.free()
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(media))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(quiet_media))
	print("RESULT failures=", failures)
	quit(1 if failures else 0)

func timing() -> void:
	var settings := root.get_node("Settings")
	var viz = main.music_visualizer
	viz.set_process(false)
	settings.visualizer_sync = -0.2
	var now := Time.get_ticks_usec() * 0.000001
	var earlier := PackedVector2Array()
	var later := PackedVector2Array()
	earlier.resize(48)
	later.resize(48)
	earlier.fill(Vector2(0.3, 0.3))
	later.fill(Vector2(0.01, 0.01))
	viz.analysis_history.assign([{"time": now - 0.4, "magnitudes": earlier, "power": Vector3(0.04, 0.04, 0.04)}, {"time": now - 0.05, "magnitudes": later, "power": Vector3(0.0001, 0.0001, 0.0001)}])
	viz._sample_fallback(false)
	check(absf(peak(viz.targets) - (linear_to_db(0.3) + 60.0) / 60.0) < 0.001, "fallback spectrum selects the requested historical audio")
	check(is_equal_approx(main.resonance_field.desired_presence, 1.0), "spectrum and RMS use the same historical sample")
	viz.wave_left.fill(0.0)
	viz.wave_right.fill(0.0)
	var delay := int(viz._analysis_delay() * viz.WAVE_RATE)
	for i in viz.WAVE_SAMPLES:
		var index := posmod(viz.wave_position - viz.WAVE_SAMPLES - delay + i, viz.WAVE_HISTORY)
		viz.wave_left[index] = 0.2
		viz.wave_right[index] = 0.3
	viz._update_waveform()
	check(absf(peak(main.resonance_field.wave_image.get_data().to_float32_array()) - 0.3) < 0.001, "immersive waveform selects the same requested delay")
	var rate := AudioServer.get_mix_rate()
	viz.mono.fill(0.0)
	viz.mono_trigger.fill(0.0)
	for i in int(viz.SCOPE_WINDOW * rate):
		viz.mono[posmod(viz.mono_position - int(viz._analysis_delay() * rate) - int(viz.SCOPE_WINDOW * rate) + i, viz.mono.size())] = 0.2
	viz._update_scope(rate, 0.1)
	check(peak(viz.spectrum.wave) > 0.2, "mini oscilloscope selects the requested delay")
	settings.visualizer_sync = 0.0
	viz._update_waveform()
	viz._update_scope(rate, 0.1)
	check(peak(main.resonance_field.wave_image.get_data().to_float32_array()) == 0.0 and peak(viz.spectrum.wave) == 0.0, "removing visual delay moves both waveform views forward")
	check(viz.mono.size() > int(rate * (0.5 + viz.SCOPE_WINDOW + viz.SCOPE_SEARCH)), "oscilloscope history holds the full supported delay at the active mix rate")
	viz._reset()
	viz.set_process(true)

func measure_output() -> float:
	await create_timer(0.3).timeout
	output_capture.clear_buffer()
	await create_timer(0.1).timeout
	var frames := output_capture.get_buffer(output_capture.get_frames_available())
	var energy := 0.0
	for frame in frames:
		energy += frame.x * frame.x
	return sqrt(energy / maxf(frames.size(), 1))
