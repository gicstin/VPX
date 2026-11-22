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


func _measure(capture: AudioEffectCapture, seconds: float) -> Vector2:
	capture.clear_buffer()
	await create_timer(seconds).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var left := 0.0
	var right := 0.0
	for frame in frames:
		left += frame.x * frame.x
		right += frame.y * frame.y
	var count := maxf(float(frames.size()), 1.0)
	return Vector2(10.0 * log(left / count + 1e-12) / log(10.0), 10.0 * log(right / count + 1e-12) / log(10.0))


func _settle(capture: AudioEffectCapture) -> Vector2:
	await create_timer(2.4).timeout
	return await _measure(capture, 0.6)


func _run() -> void:
	create_timer(200, true, false, true).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	settings.volume = 100
	settings.muted = false
	settings.audio_filter = 0
	settings.audio_mono = false
	settings.dialogue_boost = false

	check(settings.stereo_mode == 0 and settings.stereo_angle == 30.0 and settings.stereo_amount == 1.0 and settings.crossfeed_db == -4.5 and settings.crossfeed_hz == 700.0 and settings.air_db == 0.0 and not settings.stereo_tracked, "stereo sound defaults to off with neutral settings")
	settings.apply("stereo_mode", 9)
	settings.apply("stereo_angle", 500.0)
	settings.apply("stereo_amount", -3.0)
	settings.apply("crossfeed_db", 4.0)
	settings.apply("crossfeed_hz", 5.0)
	settings.apply("air_db", NAN)
	check(settings.stereo_mode == 3 and settings.stereo_angle == 60.0 and settings.stereo_amount == 0.0 and settings.crossfeed_db == -1.0 and settings.crossfeed_hz == 300.0 and settings.air_db == 0.0, "stereo values are clamped and non-finite values refused")
	settings.apply("head_width_cm", 99.0)
	settings.apply("room_amount", 5.0)
	settings.apply("stereo_distance", -2.0)
	settings.apply("bass_translate", NAN)
	settings.apply("upmix_centre", 7.0)
	check(settings.head_width_cm == 22.0 and settings.room_amount == 1.0 and settings.stereo_distance == 0.0 and settings.bass_translate == 0.0 and settings.upmix_centre == 1.0, "room, distance, head width, bass and upmix values are clamped")
	check(is_equal_approx(settings.stereo_values()["head_radius"], 0.11), "head width reaches the extension as a radius in metres")
	settings.apply("head_width_cm", 17.5)
	check(is_equal_approx(settings.stereo_values()["head_radius"], 0.0875), "the default head width is the original head size")
	settings.apply("stereo_mode", 1.4)
	check(settings.stereo_mode == 1 and typeof(settings.stereo_mode) == TYPE_INT, "mode stays a whole number")
	var values: Dictionary = settings.stereo_values()
	check(values.size() == 13 and values.has("stereo_tracked") and values.has("head_radius") and values["stereo_mode"] == 1, "stereo values reach the extension as one dictionary")
	settings.stereo_angle = 20.0
	settings.stereo_tracked = true
	settings.save_config()
	check(settings.flush() == OK, "settings save")
	settings.stereo_mode = 0
	settings.stereo_angle = 30.0
	settings.stereo_tracked = false
	settings.load_config()
	check(settings.stereo_mode == 1 and settings.stereo_angle == 20.0 and settings.stereo_tracked, "stereo choices persist")
	settings.stereo_angle = 999.0
	settings.stereo_mode = -4
	settings._validate_stereo()
	check(settings.stereo_angle == 60.0 and settings.stereo_mode == 0, "hand-edited config values are clamped on load")
	for key in settings.STEREO_LIMITS:
		settings.apply(key, settings.defaults[key])
	settings.apply("stereo_tracked", false)

	var directory := ProjectSettings.globalize_path("user://stereo_sound_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var sources := {
		"hard_left": "0.4*sin(2*PI*440*t)|0",
		"centre": "0.4*sin(2*PI*440*t)|0.4*sin(2*PI*440*t)",
		"high": "0.3*sin(2*PI*9000*t)|0.3*sin(2*PI*9000*t)",
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
		var expression: String = "aevalsrc=" + sources[name] + ":s=48000:d=60:c=stereo"
		check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", expression, "-c:a", "pcm_s16le", path]) == 0, name + " fixture generated")
		check(await main.player.open(path), name + " fixture opens")
		main.panel.hide()
		main.player.paused = false
		await create_timer(0.5).timeout
		settings.apply("stereo_mode", 0)
		levels[name + "/off"] = await _settle(capture)
		check(int(main.player.playback.get_audio_info().get("stereo_mode", -1)) == 0, name + ": info reports stereo sound off")
		settings.apply("stereo_mode", 1)
		levels[name + "/speakers"] = await _settle(capture)
		check(int(main.player.playback.get_audio_info().get("stereo_mode", -1)) == 1, name + ": info reports virtual speakers")
		check(str(main.player.playback.get_audio_info().get("description", "")).contains("virtual speakers"), name + ": description names virtual speakers")
		if name == "hard_left":
			settings.apply("stereo_amount", 0.0)
			levels[name + "/speakers-0"] = await _settle(capture)
			settings.apply("stereo_amount", 1.0)
			settings.apply("stereo_angle", 20.0)
			levels[name + "/speakers-20"] = await _settle(capture)
			settings.apply("stereo_angle", 60.0)
			levels[name + "/speakers-60"] = await _settle(capture)
			settings.apply("stereo_angle", 30.0)
		settings.apply("air_db", 6.0)
		levels[name + "/speakers-air"] = await _settle(capture)
		settings.apply("air_db", 0.0)
		if name == "centre":
			settings.apply("stereo_mode", 3)
			levels[name + "/upmix"] = await _settle(capture)
			check(int(main.player.playback.get_audio_info().get("stereo_mode", -1)) == 3, name + ": info reports upmix")
			settings.apply("stereo_mode", 1)
		if name != "high":
			settings.apply("stereo_mode", 2)
			levels[name + "/crossfeed"] = await _settle(capture)
			check(int(main.player.playback.get_audio_info().get("stereo_mode", -1)) == 2, name + ": info reports crossfeed")
		if name == "hard_left":
			settings.apply("crossfeed_db", -9.0)
			levels[name + "/crossfeed-9"] = await _settle(capture)
			settings.apply("crossfeed_db", -4.5)
		settings.apply("stereo_mode", 0)
		levels[name + "/back-off"] = await _settle(capture)
		main.player.stop()
	for key in levels:
		print("LEVEL %-26s L %7.2f dB  R %7.2f dB" % [key, levels[key].x, levels[key].y])

	var off: Vector2 = levels["hard_left/off"]
	var spk: Vector2 = levels["hard_left/speakers"]
	var cross: Vector2 = levels["hard_left/crossfeed"]
	check(off.y < -80.0 and off.x > -20.0, "off keeps a hard-left tone entirely in the left ear")
	check(spk.y > -35.0 and spk.y < spk.x - 2.0 and spk.y > spk.x - 18.0, "speakers let the far ear hear a softer copy of a hard-left tone")
	check(absf(spk.x - off.x) < 4.0, "speakers keep the near ear at a similar loudness")
	check(levels["hard_left/speakers-0"].y < -80.0, "speaker effect at 0% leaves stereo untouched")
	check(levels["hard_left/speakers-20"].y > spk.y + 0.5 and levels["hard_left/speakers-60"].y < spk.y - 0.5, "a narrower angle leaks more to the far ear and a wider one leaks less")
	check(cross.y > -40.0 and cross.y < cross.x - 3.0, "crossfeed bleeds a softer copy into the far ear")
	check(levels["hard_left/crossfeed-9"].y < cross.y - 2.0, "a lower crossfeed level bleeds less")
	var centre: Vector2 = levels["centre/speakers"]
	var centre_off: Vector2 = levels["centre/off"]
	check(absf(centre.x - centre.y) < 0.8 and absf(centre.x - centre_off.x) < 2.0, "a centred tone stays centred and about as loud")
	check(absf(levels["centre/upmix"].x - centre.x) < 2.0 and absf(levels["centre/upmix"].x - levels["centre/upmix"].y) < 0.8, "upmix keeps a centred tone centred and about as loud")
	check(absf(levels["centre/crossfeed"].x - centre_off.x) < 0.4 and absf(levels["centre/crossfeed"].x - levels["centre/crossfeed"].y) < 0.8, "crossfeed keeps a centred tone centred and near its loudness")
	check(levels["high/speakers-air"].x < levels["high/speakers"].x - 3.0, "soften highs lowers a 9 kHz tone")
	check(absf(levels["centre/speakers-air"].x - centre.x) < 1.5, "soften highs leaves a 440 Hz tone alone")
	check(absf(levels["hard_left/back-off"].x - off.x) < 1.0 and levels["hard_left/back-off"].y < -80.0, "turning stereo sound off restores the original")
	main.player.stop()
	main.free()
	for name in sources:
		DirAccess.remove_absolute(directory.path_join(name + ".wav"))
	DirAccess.remove_absolute(directory)
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
