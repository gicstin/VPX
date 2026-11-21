extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func _measure(capture: AudioEffectCapture, seconds: float) -> float:
	capture.clear_buffer()
	OS.delay_msec(int(seconds * 1000.0))
	var frames := capture.get_buffer(capture.get_frames_available())
	var sum := 0.0
	for frame in frames:
		sum += frame.x * frame.x + frame.y * frame.y
	return 10.0 * log(sum / maxf(float(frames.size()) * 2.0, 1.0) + 1e-12) / log(10.0)


func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	settings.volume = 100
	settings.muted = false
	settings.spatial_audio = true
	settings.audio_filter = 0
	var directory := ProjectSettings.globalize_path("user://spatial_levels_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var sources := {
		"sub": "0|0|0|0.5*sin(2*PI*60*t)|0|0",
		"front": "0.5*sin(2*PI*60*t)|0.5*sin(2*PI*60*t)|0|0|0|0",
	}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var bus_index := AudioServer.get_bus_index(main.player.bus)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus_index, capture)
	var levels := {}
	for name in sources:
		var path := directory.path_join(name + ".wav")
		var expression: String = "aevalsrc=" + sources[name] + ":s=48000:d=40:c=5.1"
		check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", expression, "-c:a", "pcm_s16le", path]) == 0, name + " fixture generated")
		check(await main.player.open(path), name + " fixture opens")
		main.panel.hide()
		main.player.paused = false
		await create_timer(0.5).timeout
		for preset in ["Current", "Classic", "Bass boost", "Heavy bass"]:
			settings.select_spatial_preset(preset)
			await create_timer(1.6).timeout
			levels["%s/%s" % [name, preset]] = _measure(capture, 0.6)
		for preset in ["Current", "Classic"]:
			settings.select_spatial_preset(preset)
			settings.apply("spatial_audio", false)
			await create_timer(1.6).timeout
			levels["%s/%s/stereo" % [name, preset]] = _measure(capture, 0.6)
			settings.apply("spatial_audio", true)
		settings.select_spatial_preset("Current")
		settings.set_spatial_value("lfe_gain", 0.0)
		await create_timer(1.6).timeout
		levels[name + "/no-lfe"] = _measure(capture, 0.6)
		settings.select_spatial_preset("Current")
		main.player.stop()
	for key in levels:
		print("LEVEL %-24s %7.2f dB" % [key, levels[key]])
	check(levels["sub/Heavy bass"] > levels["sub/Bass boost"] + 1.0 and levels["sub/Bass boost"] > levels["sub/Current"] + 1.0, "bass presets raise a sub-only 60 Hz tone step by step")
	check(levels["sub/Classic"] > levels["sub/Current"] - 1.0 and absf(levels["sub/Classic"] - levels["sub/Current"]) < 2.0, "sub-only level barely differs between Current and Classic")
	check(levels["front/Classic"] < levels["front/Current"] - 1.5, "Classic keeps the front channels quieter than Current, as 0.0.10 did")
	check(levels["front/Bass boost"] > levels["front/Current"] + 1.0, "the bass shelf lifts front-channel bass too")
	check(levels["sub/no-lfe"] < levels["sub/Current"] - 30.0, "a zero LFE level silences the sub channel")
	check(levels["front/Current/stereo"] > levels["front/Current"] - 6.0 and levels["front/Classic/stereo"] < levels["front/Current/stereo"] - 2.0, "stereo downmix follows the preset normalisation")
	main.player.stop()
	main.free()
	for name in sources:
		DirAccess.remove_absolute(directory.path_join(name + ".wav"))
	DirAccess.remove_absolute(directory)
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
