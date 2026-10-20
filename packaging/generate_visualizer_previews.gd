extends SceneTree

const Stimulus := preload("res://packaging/checks/music_stimulus.gd")
const TILE_SIZE := Vector2i(160, 90)

func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()

func run() -> void:
	var settings := root.get_node("Settings")
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.set_process(false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 216)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 85
	viewport.add_child(camera)
	var field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	viewport.add_child(field)
	field.active = true
	field.set_process(false)
	var atlas := Image.create_empty(TILE_SIZE.x * 8, TILE_SIZE.y * ceili(settings.VISUALIZER_PRESETS.size() / 8.0), false, Image.FORMAT_RGB8)
	var start := 0
	var args := OS.get_cmdline_user_args()
	var from := args.find("--from")
	if from >= 0 and from + 1 < args.size():
		start = clampi(int(args[from + 1]), 0, settings.VISUALIZER_PRESETS.size() - 1)
		var previous := Image.load_from_file("res://assets/visualizer_previews.png")
		atlas.blit_rect(previous, Rect2i(Vector2i.ZERO, previous.get_size()), Vector2i.ZERO)
	var music := Stimulus.new()
	for index in range(start, settings.VISUALIZER_PRESETS.size()):
		field.reset()
		music.clear()
		field.preset_index = index
		field._apply_preset()
		field._apply_quality()
		field.preset = Vector3.ZERO
		field.preset[index % 3 if index < 6 else 0] = 1.0
		for frame in 240:
			var t := float(frame) / 60.0
			var spectrum := PackedFloat32Array()
			spectrum.resize(field.BANDS * field.ROWS)
			for channel in 2:
				for band in field.BANDS:
					spectrum[channel * field.BANDS + band] = clampf(0.65 + 0.23 * sin(band * 0.38 + t * 4.0 + channel * 1.4) + 0.1 * cos(t * 9.0 + band), 0.0, 1.0)
			if index >= field.PSYCHE_START:
				music.groove(t)
				var sound := music.frame(1.0 / 60.0)
				field.feed(sound["spectrum"], sound["features"])
			else:
				field.feed(spectrum, {"rms": 0.18, "width": 0.65, "onset": 0.1 if frame % 30 == 0 else 0.0})
			field.beat_age = minf(4.0, field.beat_age + 1.0 / 60.0)
			var wave := PackedFloat32Array()
			wave.resize(512)
			for sample in 256:
				wave[sample] = 0.5 * sin(sample * 0.08 + t * 3.0) + 0.18 * sin(sample * 0.23 + t)
				wave[256 + sample] = 0.5 * sin(sample * 0.08 + t * 3.0 + 0.8) + 0.18 * sin(sample * 0.19)
			field.feed_waveform(wave)
			field.feed_scope(wave)
			field.clock = t + 10.0
			field.travel = t * 1.2
			field.spin = t * 0.6
			field._process(1.0 / 60.0)
		await process_frame
		RenderingServer.force_draw()
		var shot := viewport.get_texture().get_image()
		shot.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		shot.convert(Image.FORMAT_RGB8)
		atlas.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i(index % 8, index / 8) * TILE_SIZE)
		print("Preview ", index, " ", settings.VISUALIZER_PRESETS[index])
	for index in range(settings.VISUALIZER_PRESETS.size(), 8 * ceili(settings.VISUALIZER_PRESETS.size() / 8.0)):
		atlas.fill_rect(Rect2i(Vector2i(index % 8, index / 8) * TILE_SIZE, TILE_SIZE), Color.BLACK)
	atlas.save_png("res://assets/visualizer_previews.png")
	quit()
