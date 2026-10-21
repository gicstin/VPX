extends "res://packaging/checks/studio_visualizers.gd"


func silhouette_difference(a: Image, b: Image) -> float:
	var changed := 0
	var samples := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			var first_lit := maxf(first.r, maxf(first.g, first.b)) > 0.12
			var second_lit := maxf(second.r, maxf(second.g, second.b)) > 0.12
			changed += int(first_lit != second_lit)
			samples += 1
	return float(changed) / samples


func run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
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
	var silhouettes: Array[Image] = []
	for index in range(field.PROJECTM_START, settings.VISUALIZER_PRESETS.size()):
		settings.apply("visualizer_preset", index)
		field.reset()
		for frame in 120:
			field.feed(bands, {"channels": 2, "rms": 0.12, "onset": 0.0})
			field.beat_age += 1.0 / 60.0
			field._process(1.0 / 60.0)
		var title: String = settings.VISUALIZER_PRESETS[index]
		var steady := await capture()
		field.feed(bands, {"channels": 2, "rms": 0.12, "onset": 0.12})
		field._process(0.0)
		var struck := await capture()
		check(difference(steady, struck) > 0.0005, title + " responds to percussion independently of spectrum")
		field.impulse = 0.0
		field._process(0.0)
		var still := await capture()
		field.feed_waveform(wave)
		field._process(0.0)
		var captured := await capture()
		check(difference(still, captured) > 0.0005, title + " responds to captured stereo waveform")
		field._process(0.0)
		check(difference(captured, await capture()) < 0.00001, title + " uses only controlled animation clocks")
		silhouettes.append(captured)
		field.sky.hide()
		for turn in 4:
			camera.rotation.y = turn * PI * 0.5
			var side := await capture()
			var black := Image.create_empty(side.get_width(), side.get_height(), false, side.get_format())
			black.fill(Color.BLACK)
			check(difference(side, black) > 0.0005, title + " has geometry at yaw " + str(turn * 90))
		camera.rotation.y = 0.0
		field.sky.show()
		field.silence()
		field._process(1.0)
		var quiet := await capture()
		check(difference(captured, quiet) > 0.003, title + " settles when playback stops")
	for first in silhouettes.size():
		for second in range(first + 1, silhouettes.size()):
			var delta := silhouette_difference(silhouettes[first], silhouettes[second])
			check(delta > 0.025, "distinct silhouettes %d / %d (%.3f)" % [first, second, delta])
	print("PROJECTM_VISUALIZERS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
