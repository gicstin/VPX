extends "res://packaging/checks/visualizer_response.gd"

const CANDIDATES := [Vector3.ONE, Vector3(1.2, 1.35, 1.2), Vector3(1.4, 1.7, 1.4)]


func sample_segment(seconds: float, build: Callable, capture_from := 0.0) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for frame in int(round(seconds * FPS)):
		var dt := 1.0 / FPS
		build.call(time)
		var sound := music.frame(dt)
		field.feed(sound["spectrum"], sound["features"])
		var wave: PackedFloat32Array = music.waveform(time, sound["spectrum"])
		field.feed_waveform(wave)
		field.feed_scope(wave)
		field._process(dt)
		if frame % 3 == 0 and frame / FPS >= capture_from:
			await process_frame
			RenderingServer.force_draw()
			var sample := measure(root.get_texture().get_image())
			sample["time"] = time
			frames.append(sample)
		time += dt
	return frames


func evaluate(profile: Vector3) -> Dictionary:
	field.reset()
	field.response_profile = profile
	field.scene_opacity = 1.0
	field.preset = Vector3.ZERO
	field.preset[field.preset_index % 3 if field.preset_index < 6 else 0] = 1.0
	music.clear()
	music.envelope = 0.0
	music.onset = 0.0
	time = 0.0
	var rest := await sample_segment(0.5, func(_t: float) -> void: pass)
	var rest_luma := mean_luma(rest)
	var origin := time
	music.bpm = 120.0
	var groove := await sample_segment(6.0, func(t: float) -> void: music.groove(t - origin))
	var hits: Array[float] = []
	for hit in music.kicks:
		if hit > 4.0:
			hits.append(hit + origin)
	var beat := beat_metrics(groove, hits)
	var levels: Array[float] = []
	var clips := 0.0
	var all_frames: Array[Dictionary] = groove.duplicate()
	for level in [0.04, 0.16, 0.6]:
		field.reset()
		field.scene_opacity = 1.0
		var bed := await sample_segment(4.5, func(t: float) -> void:
			for band in range(2, 46, 4):
				music.add(band, 3.0, level * (1.0 + 0.1 * sin(t * 3.0 + band)), sin(band * 0.7) * 0.5), 3.8)
		levels.append(mean_luma(bed, 0.55))
		all_frames.append_array(bed)
	music.bpm = 180.0
	origin = time
	var fast := await sample_segment(2.0, func(t: float) -> void: music.groove(t - origin))
	all_frames.append_array(fast)
	for frame in all_frames:
		clips = maxf(clips, frame["clip"])
	var flashes := flash_rate(all_frames, "tiles")
	var red_flashes := flash_rate(all_frames, "reds")
	var movement := coherence(groove)
	var contrast := maxf(0.0, float(beat["beat_contrast"]))
	var gain := maxf(0.0, mean_luma(groove, 0.7) - rest_luma)
	var dynamic := maxf(0.0, levels[2] - levels[0])
	var score := sqrt(gain) + sqrt(dynamic) + contrast * 0.15 + maxf(0.0, float(beat["entrainment"])) * 0.1
	var eligible := clips <= 0.03 and flashes <= 3.0 and red_flashes <= 3.0 and movement <= 0.05 and rest_luma <= 0.08
	return {"score": score, "eligible": eligible, "clip": clips, "flash_rate": flashes, "red_flash_rate": red_flashes, "coherence": movement, "rest_luma": rest_luma, "gain": gain, "dynamic": dynamic, "beat": beat, "profile": [profile.x, profile.y, profile.z]}


func run() -> void:
	check(DisplayServer.get_name() != "headless", "calibration requires rendered frames")
	if failures:
		quit(2)
		return
	for i in 256:
		var c := i / 255.0
		linear.append(c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4))
	settings = root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_starred_only = false
	settings.visualizer_quality = 3
	settings.visualizer_motion = 0.6
	settings.visualizer_intensity = 0.75
	settings.visualizer_sensitivity = 1.75
	mute_everything()
	root.size = SIZE
	camera = Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 8000
	var silence := PackedByteArray()
	silence.resize(8000 * 2 * 1800)
	audio.data = silence
	var path := OS.get_user_data_dir().path_join("calibration.wav")
	check(audio.save_to_wav(path) == OK, "silent playback fixture created")
	var playback: Node = load("res://scripts/player.gd").new()
	root.add_child(playback)
	playback.set_process(false)
	await playback.open(path)
	playback.paused = false
	field.player = playback
	check(playback.is_playing(), "calibration advances the real playback motion path")
	if failures:
		quit(1)
		return
	var start := int(argument("--from", "0"))
	var finish := int(argument("--to", str(settings.VISUALIZER_PRESET_MAX)))
	create_timer(3600.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	var report := {}
	var report_path := argument("--report", "/tmp/vpx-visualizer-calibration.json")
	if "--resume" in OS.get_cmdline_user_args() and FileAccess.file_exists(report_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if saved is Dictionary:
			report = saved
	var profiles := {}
	for index in range(start, finish + 1):
		var name: String = settings.VISUALIZER_PRESETS[index]
		if report.has(name):
			var saved: Dictionary = report[name]
			profiles[name] = CANDIDATES[int(saved.selected)]
			print("REUSED %d %s" % [index, name])
			continue
		settings.apply("visualizer_preset", index)
		var results: Array[Dictionary] = []
		var best := 0
		for profile in CANDIDATES:
			var result := await evaluate(profile)
			results.append(result)
			var improved: bool = result.score > results[best].score * 1.03
			var preserves_range: bool = result.gain >= results[0].gain * 0.95 and result.dynamic >= results[0].dynamic * 0.95
			var preserves_beat: bool = result.beat.beat_contrast >= results[0].beat.beat_contrast - absf(results[0].beat.beat_contrast) * 0.15
			preserves_beat = preserves_beat and result.beat.latency_ms <= results[0].beat.latency_ms + 50.0
			if results.size() > 1 and result.eligible and improved and preserves_range and preserves_beat:
				best = results.size() - 1
		profiles[name] = CANDIDATES[best]
		report[name] = {"selected": best, "candidates": results}
		check(best == 0 or results[best].eligible, name + " stronger response meets rendering limits")
		print("CALIBRATED %d %s candidate=%d score=%.4f baseline=%.4f" % [index, name, best, results[best].score, results[0].score])
		var output := FileAccess.open(report_path, FileAccess.WRITE)
		output.store_string(JSON.stringify(report, "\t", true) + "\n")
		output.close()
	if "--write-profiles" in OS.get_cmdline_user_args():
		check(start == 0 and finish == settings.VISUALIZER_PRESET_MAX, "profile generation covers every preset")
		if failures == 0:
			var source := "extends RefCounted\n\nconst VALUES := {\n"
			for name in profiles:
				var value: Vector3 = profiles[name]
				source += "\t%s: Vector3(%.2f, %.2f, %.2f),\n" % [JSON.stringify(name), value.x, value.y, value.z]
			source += "}\n"
			var output := FileAccess.open("res://scripts/visualizer_response_profiles.gd", FileAccess.WRITE)
			output.store_string(source)
	check(AudioServer.is_bus_mute(0), "calibration output stayed muted")
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
