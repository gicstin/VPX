extends "res://packaging/checks/studio_visualizers.gd"


func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(640, 360)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.visualizer_motion = 0.6
	var camera := Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var bands := PackedFloat32Array()
	bands.resize(2400)
	for band in 96:
		bands[band] = 0.65
	var wave := PackedFloat32Array()
	wave.resize(512)
	for sample in 256:
		wave[sample] = sin(sample * 0.12) * 0.35
		wave[256 + sample] = cos(sample * 0.12) * 0.35
	for index in range(field.LIVE_START, field.PROJECTM_START):
		settings.apply("visualizer_preset", index)
		field.reset()
		for frame in 90:
			field.feed(bands, {"channels": 2, "rms": 0.12, "onset": 0.0})
			field.beat_age += 1.0 / 60.0
			field._process(1.0 / 60.0)
		var steady := await capture()
		field.feed(bands, {"channels": 2, "rms": 0.12, "onset": 0.12})
		field._process(0.0)
		var struck := await capture()
		var title: String = settings.VISUALIZER_PRESETS[index]
		check(difference(steady, struck) > 0.0005, title + " responds to percussion independently of spectrum and loudness")
		field.impulse = 0.0
		field._process(0.0)
		var still := await capture()
		field.feed_waveform(wave)
		field._process(0.0)
		var captured := await capture()
		check(difference(still, captured) > 0.0005, title + " captured waveform changes the geometry")
		field._process(0.0)
		var repeated := await capture()
		check(difference(captured, repeated) < 0.00001, title + " has no animation independent of its controlled clocks")
	print("LIVE_VISUALIZERS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
