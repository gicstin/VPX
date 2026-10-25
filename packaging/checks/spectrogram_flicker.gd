extends "res://packaging/checks/studio_visualizers.gd"


func run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(640, 360)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.visualizer_intensity = 0.75
	var camera := Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var data := PackedFloat32Array()
	data.resize(field.BANDS * field.ROWS)
	for band in field.BANDS:
		data[band] = 0.4 + 0.25 * sin(band * 0.3)
		data[field.BANDS + band] = 0.5 + 0.2 * cos(band * 0.25)
	DirAccess.make_dir_recursive_absolute("/tmp/vpx-spectrogram-flicker")
	for index in range(field.SPECTROGRAM_START, field.WORLD_START):
		settings.apply("visualizer_preset", index)
		field.reset()
		var title: String = settings.VISUALIZER_PRESETS[index]
		field.feed(data, {"channels": 2, "rms": 0.15})
		field._process(0.5 / field.SPECTRAL_HISTORY_RATE)
		check(int(field.materials[0].get_shader_parameter("spectral_history_head")) == -1, title + " stays empty until the first history sample")
		field.reset()
		var previous: Image
		for frame in range(1, field.HISTORY_SAMPLES * 3 + 2):
			field.feed(data, {"channels": 2, "rms": 0.15})
			field._process(1.0 / field.SPECTRAL_HISTORY_RATE)
			if frame < field.HISTORY_SAMPLES * 2 - 1:
				continue
			var position: int = field.spectral_history_position
			if position not in [field.HISTORY_SAMPLES - 1, 0, 1]:
				continue
			var current := await capture()
			if index == field.SPECTROGRAM_START:
				current.save_png("/tmp/vpx-spectrogram-flicker/frame-%03d.png" % frame)
			if position == field.HISTORY_SAMPLES - 1:
				previous = current
			else:
				var delta := difference(previous, current)
				check(delta < 0.0001, "%s stays stable at frame %d, ring position %d (difference %.6f)" % [title, frame, position, delta])
				if position == 0:
					check(int(field.materials[0].get_shader_parameter("spectral_history_head")) >= 0, title + " keeps a valid history head across rollover")
		field.silence()
		field._process(0.0)
		check(int(field.materials[0].get_shader_parameter("spectral_history_head")) == -1, title + " marks cleared history as empty")
	print("SPECTROGRAM_FLICKER checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
