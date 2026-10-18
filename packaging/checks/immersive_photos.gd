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


func frames() -> void:
	for i in 8:
		await process_frame


func run() -> void:
	create_timer(45).timeout.connect(func() -> void: quit(2))
	Engine.max_fps = 60
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.resume_playback = false
	settings.auto_crop = false
	settings.music_visualizer = false
	settings.immersive_music_visualizer = true
	settings.visualizer_quality = 1
	settings.visualizer_preset = 0
	var photo_path := ProjectSettings.globalize_path("user://immersive-photo.png")
	var audio_path := ProjectSettings.globalize_path("user://immersive-audio.wav")
	var picture := Image.create(512, 256, false, Image.FORMAT_RGB8)
	picture.fill(Color.CORAL)
	picture.save_png(photo_path)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(44100 * 2 * 30)
	audio.data = samples
	audio.save_to_wav(audio_path)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await main.player.open(photo_path), "photo opens")
	check(await main.player.open(audio_path), "music opens over photo")
	main.panel.visible = false
	await frames()
	var playback: RefCounted = main.player.playback
	var image: RefCounted = main.player.image
	check(main.screen.visible and not main.resonance_field.active, "photo stays visible without immersive visuals")
	for projection in [settings.ProjectionMode.FLAT, settings.ProjectionMode.EQUIRECT_360]:
		settings.apply("projection", projection)
		await frames()
		check(main.screen.visible and not main.resonance_field.active, "photo stays visible without immersive scene: projection=%d" % projection)
		check(main.photo_bar.root.immersive_button.visible and not main.photo_bar.root.scene_picker.visible, "photo music controls retain compact immersive selector: projection=%d" % projection)
		main.photo_bar.root.immersive_button.pressed.emit()
		await frames()
		check(main.photo_bar.root.scene_picker.menu.visible and not main.resonance_field.active, "selector opens without enabling photo overlay: projection=%d" % projection)
		main.photo_bar.root.scene_picker.close()
		check(main.player.playback == playback and main.player.image == image and main.player.is_playing(), "photo and music remain active: projection=%d" % projection)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			var photo_pixels := 0
			for y in range(0, rendered.get_height(), 8):
				for x in range(0, rendered.get_width(), 8):
					var pixel := rendered.get_pixel(x, y)
					if pixel.r > 0.8 and pixel.g > 0.35 and pixel.g < 0.65 and pixel.b < 0.5:
						photo_pixels += 1
			check(photo_pixels > 100, "photo pixels remain rendered: projection=%d" % projection)
	main.player.stop_music()
	await frames()
	check(main.screen.visible and not main.resonance_field.active, "stopping music keeps photo visible")
	main.player._close_image()
	check(await main.player.open(audio_path), "audio-only playback opens")
	await frames()
	check(main.resonance_field.active and not main.screen.visible, "audio-only playback retains full immersive scene")
	check(main.photo_bar.root.immersive_button.visible and not main.photo_bar.root.scene_picker.visible, "audio-only music controls retain immersive selector without expanded gallery")
	check(await main.player.open(photo_path), "photo opens during immersive music")
	await frames()
	check(main.screen.visible and not main.resonance_field.active and main.player.is_playing(), "opening a photo stops immersive visuals and preserves music")
	var music_playback: RefCounted = main.player.playback
	main.photo_bar.root.immersive_button.pressed.emit()
	main.photo_bar.root.scene_picker.disabled_button.pressed.emit()
	await frames()
	check(main.player.is_image() and not main.resonance_field.active, "Disabled preserves the photo")
	main.photo_bar.root.immersive_button.pressed.emit()
	main.photo_bar.root.scene_picker.tiles[1].pressed.emit()
	await frames()
	check(main.player.is_music_mode() and main.resonance_field.active and not main.screen.visible, "selecting a scene switches from photo to immersive music")
	check(main.player.playback == music_playback and main.player.is_playing(), "switching to immersive preserves music playback")
	check(main.player.current_path == audio_path and main.player.music_path.is_empty(), "immersive switch restores music path")
	main.queue_free()
	await frames()
	DirAccess.remove_absolute(photo_path)
	DirAccess.remove_absolute(audio_path)
	print("RESULT: immersive photos checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
