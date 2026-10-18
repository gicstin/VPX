extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func peak_cell(data: PackedFloat32Array, band: int) -> int:
	var selected := 0
	for cell in 48:
		if data[(cell + 2) * 48 + band] > data[(selected + 2) * 48 + band]:
			selected = cell
	return selected

func run() -> void:
	create_timer(30).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	settings.music_visualizer = true
	settings.immersive_music_visualizer = true
	settings.music_visualizer_mode = 0
	settings.volume = 100
	settings.muted = false
	settings.spatial_audio = true
	settings.visualizer_sync = 0.0
	var directory := ProjectSettings.globalize_path("user://channel_check_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var expressions := {"left": "0.4*sin(2*PI*110*t)|0", "right": "0|0.4*sin(2*PI*110*t)", "centre": "0.4*sin(2*PI*110*t)|0.4*sin(2*PI*110*t)", "antiphase": "0.4*sin(2*PI*110*t)|-0.4*sin(2*PI*110*t)", "mono": "0.4*sin(2*PI*110*t)", "surround": "0.2*sin(2*PI*110*t)|0.2*sin(2*PI*220*t)|0.2*sin(2*PI*330*t)|0.2*sin(2*PI*70*t)|0.2*sin(2*PI*660*t)|0.2*sin(2*PI*880*t)"}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for name in expressions:
		var path := directory.path_join(name + ".wav")
		var source: String = "aevalsrc=" + expressions[name] + ":s=48000:d=8" + (":c=5.1" if name == "surround" else "")
		check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", source, "-c:a", "pcm_s16le", path]) == 0, name + " fixture generated")
		check(await main.player.open(path), name + " fixture opens")
		main.panel.hide()
		main.player.paused = false
		await create_timer(0.75).timeout
		var field: Node = main.resonance_field
		var viz: Node = main.music_visualizer
		print("CHANNELS %s left=%s right=%s width=%.4f" % [name, field.channel_levels[0], field.channel_levels[1], field.stereo_width])
		if name == "left":
			check(field.channel_levels[0].length() > 0.1 and field.channel_levels[1].length() < 0.001, "left audio drives only left visual channel")
		elif name == "right":
			check(field.channel_levels[1].length() > 0.1 and field.channel_levels[0].length() < 0.001, "right audio drives only right visual channel")
		elif name == "mono":
			check(field.source_count == 1, "mono audio keeps one visual source")
		elif name in ["centre", "antiphase"]:
			check(field.channel_levels[0].distance_to(field.channel_levels[1]) < 0.001 and field.channel_levels[0].length() > 0.1, name + " preserves equal channel levels")
			if name == "antiphase":
				check(field.stereo_width > 0.9, "antiphase audio retains stereo width")
				check(field.correlation < -0.95, "antiphase audio reaches studio correlation readout")
			else:
				check(field.correlation > 0.95, "centred audio reaches studio correlation readout")
		else:
			viz._sample_native()
			viz._sample_fallback(false)
			check(int(viz.native_features.get("channels", 0)) == 6 and field.source_count == 0, "surround keeps native spatial sources")
			var band := clampi(int(log(660.0 / 30.0) / log(600.0) * 48.0), 0, 47)
			var native_data: PackedFloat32Array = viz.native_features.get("spectrum", PackedFloat32Array())
			check(native_data.size() == 2400 and peak_cell(native_data, band) == peak_cell(field.spectrum_targets, band), "surround spectral direction survives shared level calibration")
			settings.apply("spatial_audio", false)
			await create_timer(0.3).timeout
			check(field.source_count == 2, "surround downmix switches to stereo visual sources")
	main.player.stop()
	main.free()
	for name in expressions:
		DirAccess.remove_absolute(directory.path_join(name + ".wav"))
	DirAccess.remove_absolute(directory)
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
