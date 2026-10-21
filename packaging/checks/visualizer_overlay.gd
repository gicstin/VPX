extends SceneTree

var failures := 0
var checks := 0
var main: Node
var settings: Node


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames(count := 12) -> void:
	for i in count:
		await process_frame


func capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func difference(a: Image, b: Image) -> float:
	var total := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
			samples += 1
	return total / maxf(1.0, samples * 3.0)


func run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	settings = root.get_node("Settings")
	settings.last_file = ""
	settings.resume_playback = false
	settings.auto_crop = false
	settings.music_visualizer = false
	settings.immersive_music_visualizer = true
	settings.visualizer_overlay = false
	settings.visualizer_quality = 1
	settings.prefer_desktop = true
	var photo := ProjectSettings.globalize_path("user://overlay.png")
	var audio := ProjectSettings.globalize_path("user://overlay.wav")
	var picture := Image.create(512, 256, false, Image.FORMAT_RGB8)
	picture.fill(Color(0.2, 0.35, 0.5))
	picture.save_png(photo)
	var sound := AudioStreamWAV.new()
	sound.mix_rate = 44100
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	samples.resize(44100 * 2 * 30)
	for i in 44100 * 30:
		samples.encode_s16(i * 2, int(sin(float(i) * TAU * 120.0 / 44100.0) * 12000.0))
	sound.data = samples
	sound.save_to_wav(audio)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await main.player.open(photo), "photo opens")
	check(await main.player.open(audio), "soundtrack opens")
	main.panel.visible = false
	settings.apply("projection", settings.ProjectionMode.FLAT)
	await frames()
	var playback: RefCounted = main.player.playback
	var image: RefCounted = main.player.image
	var picker: Node = main.photo_bar.root.scene_picker
	check(not main.resonance_field.active and main.screen.visible, "overlay starts opt-in")
	picker.overlay_toggle.set_pressed(true)
	await frames()
	check(main.resonance_field.active and main.screen.visible and main.player.is_image(), "overlay keeps photo visible")
	check(main.music_visualizer.analysing and main.music_visualizer.capturing and not main.music_visualizer.enabled, "overlay analyses audio with compact visualizer off")
	check(main.player.playback == playback and main.player.image == image and main.player.current_path == photo, "overlay preserves media and soundtrack")
	check(main.desktop_view._is_flat(), "flat backdrop keeps fitted camera")
	check(picker.mix_controls.visible, "mix controls open with overlay")
	var quick_mix: Node = main.photo_bar.root.quick_mix
	check(quick_mix.is_visible_in_tree() and not picker.menu.visible, "mini player exposes mixes without opening scene picker")
	quick_mix.off_button.pressed.emit()
	await frames()
	check(not main.resonance_field.active and quick_mix.off_button.button_pressed, "mini player Off disables immersive overlay")
	quick_mix.buttons[2].pressed.emit()
	await frames()
	check(main.resonance_field.active and quick_mix.buttons[2].button_pressed and is_equal_approx(settings.visualizer_overlay_opacity, 1.0), "mini player Vivid enables and applies overlay mix")
	check(main.player.image == image and main.player.playback == playback and main.player.is_playing(), "mini player quick mixes preserve photo and uninterrupted music")
	check(picker.mix_controls.get_child(1).buttons[2].button_pressed, "mini player and gallery mix selections stay synchronized")
	quick_mix.buttons[1].pressed.emit()
	check(is_equal_approx(settings.visualizer_overlay_opacity, 0.65) and is_equal_approx(settings.visualizer_background_dim, 0.15), "mini player Balanced applies shared defaults")
	picker.mix_controls.get_child(1).get_child(0).pressed.emit()
	check(is_equal_approx(settings.visualizer_overlay_opacity, 0.3) and settings.visualizer_background_dim == 0.0 and settings.visualizer_atmosphere == 0.0, "Subtle preset applies a clear backdrop mix")
	picker.mix_controls.get_child(1).get_child(0).pressed.emit()
	check(picker.mix_controls.get_child(1).get_child(0).button_pressed, "reselecting a mix keeps its selected state")
	var opacity_row: Node = picker.adjustments[&"visualizer_overlay_opacity"].get_parent()
	opacity_row.get_child(opacity_row.get_child_count() - 1).pressed.emit()
	check(is_equal_approx(settings.visualizer_overlay_opacity, 0.65), "individual mix reset restores default")
	picker.tiles[3].pressed.emit()
	await frames()
	check(main.player.image == image and main.player.playback == playback and main.resonance_field.preset_index == 3, "scene selection preserves media")
	picker.adjustments[&"visualizer_overlay_opacity"].value = 0.42
	picker.adjustments[&"visualizer_background_dim"].value = 0.3
	picker.adjustments[&"visualizer_atmosphere"].value = 0.2
	await frames()
	check(is_equal_approx(settings.visualizer_overlay_opacity, 0.42) and is_equal_approx(float(main.screen.material.get_shader_parameter("visualizer_media_dim")), 0.7), "mix sliders control visuals and media separately")
	check(is_equal_approx(float(main.resonance_field.sky_material.get_shader_parameter("overlay_opacity")), 0.084), "atmosphere follows overall visual opacity")
	var media_picker := main.get_node("UIViewport/UI").find_child("SoundVisualizer", true, false)
	check(media_picker != null and is_equal_approx(media_picker.adjustments[&"visualizer_overlay_opacity"].value, 0.42), "Media page exposes synchronized sound controls")
	for projection in [settings.ProjectionMode.FLAT, settings.ProjectionMode.EQUIRECT_360, settings.ProjectionMode.EQUIRECT_180]:
		settings.apply("projection", projection)
		await frames()
		check(main.screen.visible and main.resonance_field.active, "overlay preserves projection %d" % projection)
	var lens: float = main.camera.fov
	settings.apply("visualizer_zoom", 1.8)
	await frames()
	check(is_equal_approx(main.camera.fov, lens), "overlay zoom leaves panorama field of view unchanged")
	for preset in [0, 3, 7, 17, 22, 68, 76, 80, 86]:
		settings.apply("visualizer_preset", preset)
		await frames(3)
		check(main.resonance_field.materials[0].shader.code.contains("depth_test_disabled") and main.resonance_field.sky_material.shader.code.contains("ALPHA = overlay_opacity"), "overlay composites shader family %d" % preset)
	settings.apply("visualizer_overlay_opacity", 0.42)
	settings.flush()
	settings.visualizer_overlay = false
	settings.visualizer_overlay_opacity = 0.0
	settings.visualizer_background_dim = 0.0
	settings.visualizer_atmosphere = 0.0
	settings.load_config()
	check(settings.visualizer_overlay and is_equal_approx(settings.visualizer_overlay_opacity, 0.42) and is_equal_approx(settings.visualizer_background_dim, 0.3) and is_equal_approx(settings.visualizer_atmosphere, 0.2), "all mix settings survive reload")
	settings.apply("visualizer_overlay_opacity", NAN)
	settings.apply("visualizer_background_dim", 2.0)
	settings.apply("visualizer_atmosphere", -1.0)
	check(is_equal_approx(settings.visualizer_overlay_opacity, 0.42) and settings.visualizer_background_dim == 1.0 and settings.visualizer_atmosphere == 0.0, "mix settings reject invalid values and clamp ranges")
	main.player.paused = true
	await frames()
	var position: float = main.player.stream_position
	picker.disabled_button.pressed.emit()
	await frames()
	check(main.screen.visible and not main.resonance_field.active and main.player.paused and is_equal_approx(main.player.stream_position, position), "disable restores undimmed media without changing pause or position")
	check(is_equal_approx(float(main.screen.material.get_shader_parameter("visualizer_media_dim")), 1.0), "disable clears backdrop dim")
	settings.apply("immersive_music_visualizer", true)
	await frames()
	if DisplayServer.get_name() != "headless":
		await render_checks()
	main.player.stop_music()
	await frames()
	check(not main.resonance_field.active and main.screen.visible, "stopping soundtrack leaves photo intact")
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "--desktop":
		check(await main.player.open(args[0]), "video with audio opens")
		main.panel.visible = false
		main.player.paused = false
		await frames(45)
		check(main.resonance_field.active and main.screen.visible and main.music_visualizer.analysing, "video audio drives overlay")
		settings.compositor_layer = true
		main.video_layer.force_offscreen = true
		check(not main.video_layer._wanted(), "overlay uses scene composition in VR")
		settings.compositor_layer = false
		main.video_layer.force_offscreen = false
		var peak := 0.0
		for value in main.music_visualizer.levels:
			peak = maxf(peak, value)
		check(peak > 0.001, "video produces measured sound response")
		settings.apply("visualizer_overlay", false)
		await frames()
		check(not main.resonance_field.active and main.screen.visible and not main.music_visualizer.analysing, "video exits overlay cleanly")
		var silent: String = args[0].get_base_dir().path_join("silent.mp4")
		if FileAccess.file_exists(silent):
			settings.apply("visualizer_overlay", true)
			check(await main.player.open(silent), "silent video opens")
			await frames()
			check(main.screen.visible and not main.resonance_field.active and not main.music_visualizer.analysing, "silent video leaves visuals and analysis off")
	main.player._close_image()
	check(await main.player.open(audio), "standalone music opens")
	await frames()
	check(main.resonance_field.active and not main.player.is_visualizer_overlay_active() and not main.screen.visible, "standalone music keeps full immersive scene")
	check(not main.photo_bar.root.quick_mix.visible, "media mix shortcuts hide when standalone music has no backdrop")
	check(not main.resonance_field.materials[0].shader.code.contains("depth_test_disabled"), "leaving media restores normal scene shaders")
	main.queue_free()
	await frames()
	print("RESULT: visualizer overlay checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func render_checks() -> void:
	settings.apply("projection", settings.ProjectionMode.FLAT)
	settings.apply("visualizer_zoom", 1.0)
	settings.apply("visualizer_background_dim", 0.0)
	settings.apply("visualizer_atmosphere", 0.0)
	settings.apply("visualizer_overlay_opacity", 0.0)
	main.photo_bar.set_process(false)
	main.photo_bar.root.hide()
	if main.music_panel != null:
		main.music_panel.hide()
	main.resonance_field.set_process(false)
	main.music_visualizer.set_process(false)
	main.resonance_field.scene_opacity = 1.0
	main.resonance_field._process(1.0)
	await frames()
	var clear := await capture()
	settings.apply("immersive_music_visualizer", false)
	main.resonance_field.set_active(false)
	await frames()
	var plain := await capture()
	check(difference(clear, plain) < 0.002, "zero opacity exactly preserves rendered backdrop")
	settings.apply("immersive_music_visualizer", true)
	main.resonance_field.set_active(true)
	var bands := PackedFloat32Array()
	bands.resize(48 * 50)
	bands.fill(0.75)
	for preset in [0, 3, 7, 17, 22, 68, 76, 80]:
		settings.apply("visualizer_preset", preset)
		settings.apply("visualizer_overlay_opacity", 0.0)
		main.resonance_field._process(0.1)
		await frames()
		var hidden := await capture()
		check(difference(plain, hidden) < 0.002, "zero opacity clears shader family %d" % preset)
		settings.apply("visualizer_overlay_opacity", 1.0)
		main.resonance_field.scene_opacity = 1.0
		main.resonance_field.feed(bands, {"channels": 2, "rms": 0.2, "onset": 0.1})
		main.resonance_field._process(0.1)
		await frames()
		var mixed := await capture()
		check(difference(plain, mixed) > 0.0001, "visible overlay renders in front of flat photo: family %d" % preset)
		if preset == 3:
			mixed.save_png("/tmp/vpx-overlay-render.png")
	settings.apply("visualizer_overlay_opacity", 0.0)
	settings.apply("visualizer_background_dim", 0.75)
	main.resonance_field._process(0.1)
	await frames()
	var dark := await capture()
	check(difference(plain, dark) > 0.05, "backdrop dim changes rendered media")
	settings.apply("visualizer_overlay_opacity", 1.0)
	settings.apply("visualizer_background_dim", 0.0)
	for projection in [settings.ProjectionMode.EQUIRECT_360, settings.ProjectionMode.EQUIRECT_180]:
		settings.apply("projection", projection)
		settings.apply("visualizer_overlay_opacity", 0.0)
		main.resonance_field._process(0.1)
		await frames()
		var backdrop := await capture()
		settings.apply("visualizer_overlay_opacity", 1.0)
		main.resonance_field._process(0.1)
		await frames()
		var mixed := await capture()
		check(difference(backdrop, mixed) > 0.0001, "panorama overlay renders for projection %d" % projection)
	settings.apply("projection", settings.ProjectionMode.FLAT)
	settings.apply("visualizer_overlay_opacity", 0.65)
	settings.apply("visualizer_background_dim", 0.15)
	settings.apply("visualizer_atmosphere", 0.15)
	main.resonance_field.set_process(true)
	main.music_visualizer.set_process(true)
	main.photo_bar.set_process(true)
	await frames()
	var mini_player := await capture()
	mini_player.save_png("/tmp/vpx-overlay-mini-player.png")
	main.photo_bar.root.scene_picker._toggle_gallery()
	await frames()
	var controls := await capture()
	controls.save_png("/tmp/vpx-overlay-controls.png")
