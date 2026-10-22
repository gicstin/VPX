extends "res://packaging/checks/projectm_visualizers.gd"


func silhouette_distance(a: Image, b: Image) -> float:
	var changed := 0
	var occupied := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			var first_lit := maxf(first.r, maxf(first.g, first.b)) > 0.12
			var second_lit := maxf(second.r, maxf(second.g, second.b)) > 0.12
			changed += int(first_lit != second_lit)
			occupied += int(first_lit or second_lit)
	return float(changed) / maxi(1, occupied)


func run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(640, 360)
	DirAccess.make_dir_recursive_absolute("/tmp/vpx-immersive-catalog")
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.visualizer_motion = 0.6
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
	var bands := PackedFloat32Array()
	bands.resize(2400)
	for band in 96:
		bands[band] = 0.45 + 0.25 * sin(band * 0.37)
	var wave := PackedFloat32Array()
	wave.resize(512)
	for sample in 256:
		wave[sample] = sin(sample * 0.12) * 0.35
		wave[256 + sample] = cos(sample * 0.12) * 0.35
	var catalog: Array[Image] = []
	for index in settings.VISUALIZER_PRESETS.size():
		settings.apply("visualizer_preset", index)
		field.reset()
		field.clock = 8.0
		for frame in 90:
			field.feed(bands, {"channels": 2, "rms": 0.15, "width": 0.65, "onset": 0.08 if frame % 30 == 0 else 0.0})
			field.feed_waveform(wave)
			field.feed_scope(wave)
			field._process(1.0 / 60.0)
		catalog.append(await capture())
		catalog[index].save_png("/tmp/vpx-immersive-catalog/%03d.png" % index)
	for index in range(field.IMMERSIVE_START, field.SPECTROGRAM_START):
		var closest := -1
		var minimum := INF
		for other in index:
			var delta := silhouette_distance(catalog[index], catalog[other])
			if delta < minimum:
				minimum = delta
				closest = other
		check(minimum > 0.35, "%s differs in silhouette from every earlier preset; closest %s (%.3f)" % [settings.VISUALIZER_PRESETS[index], settings.VISUALIZER_PRESETS[closest], minimum])
	print("IMMERSIVE_VISUALIZERS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
