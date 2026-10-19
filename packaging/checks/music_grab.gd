extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	var saved := {}
	for key in settings._persisted():
		saved[key] = settings.get(key)
	saved = saved.duplicate(true)
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	settings.follow_posture = false
	settings.flat_video_pan = false
	settings.lock_horizon = false
	settings.angle_yaw = 0.0
	settings.angle_pitch = 0.0
	settings.angle_roll = 0.0
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(44100 * 2 * 8)
	audio.data = samples
	var path := "user://music_grab_%d.wav" % Time.get_ticks_usec()
	audio.save_to_wav(path)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await main.player.open(ProjectSettings.globalize_path(path)), "music fixture opens")
	for frame in 8:
		await process_frame
	check(main.player.has_picture(), "audio fixture provides its placeholder picture for VR grabs")
	main.set_process(false)
	main.music_visualizer.set_process(false)
	main.resonance_field.set_active(true)
	main.resonance_field.set_process(false)
	main.panel.visible = false
	var view = main.desktop_view
	var field = main.resonance_field
	for mode in [settings.VisualizerGrab.DEFAULT, settings.VisualizerGrab.SCENE_AND_AUDIO, settings.VisualizerGrab.AUDIO_ONLY]:
		settings.visualizer_grab_mode = mode
		main.camera.basis = Basis.IDENTITY
		field.place()
		var before: Basis = main.camera.global_basis.inverse() * field.global_basis
		view.dragged = true
		view.press_position = Vector2.ZERO
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = Vector2(120, 120)
		motion.relative = Vector2(80, 50)
		view._video_input(motion)
		var after: Basis = main.camera.global_basis.inverse() * field.global_basis
		check(after.is_equal_approx(before) == (mode == settings.VisualizerGrab.AUDIO_ONLY), "desktop grab scene behavior for mode %d" % mode)
		var listener: Basis = main.screen.global_basis.inverse() * main.camera.global_basis
		check(not is_zero_approx(listener.z.y), "desktop vertical drag reaches listener pitch for mode %d" % mode)
		check((main.screen.global_basis.inverse() * field.global_basis).is_equal_approx(field.audio_basis), "scene frequency mapping matches audio frame for mode %d" % mode)
	var pointer = main.get_node("Origin/Right")
	pointer.tracker = &"none"
	main.desktop_mode = false
	main.camera.basis = Basis.IDENTITY
	settings.projection = settings.ProjectionMode.FLAT
	for mode in [settings.VisualizerGrab.DEFAULT, settings.VisualizerGrab.SCENE_AND_AUDIO, settings.VisualizerGrab.AUDIO_ONLY]:
		settings.visualizer_grab_mode = mode
		settings.angle_yaw = 0.0
		settings.angle_pitch = 0.0
		settings.angle_roll = 0.0
		main.screen.apply_angles()
		field.place()
		var before: Basis = field.global_basis
		var audio_before: Basis = main.screen.global_basis
		pointer.rotation = Vector3.ZERO
		pointer.aim_primed = false
		pointer.aim_frame = -1
		main.grab_controller = pointer
		main.panel_grabbed = false
		main._begin_drag(pointer)
		main.drag_active = true
		pointer.rotation = Vector3(0.25, 0.2, 0.0)
		pointer.aim_primed = false
		pointer.aim_frame = -1
		main._update_grab(1.0 / 90.0)
		check(not main.screen.global_basis.is_equal_approx(audio_before), "VR grab rotates audio frame for mode %d" % mode)
		if mode == settings.VisualizerGrab.SCENE_AND_AUDIO:
			check(field.global_basis.is_equal_approx(main.screen.global_basis * audio_before.inverse() * before), "VR scene follows audio rotation")
		else:
			check(field.global_basis.is_equal_approx(before), "VR audio-only grab keeps scene fixed for mode %d" % mode)
	settings.visualizer_grab_mode = settings.VisualizerGrab.SCENE_AND_AUDIO
	settings.angle_pitch = 1.0
	settings.angle_roll = 2.0
	main._apply_grab_angles()
	var before_release: Basis = field.global_basis
	var audio_before_release: Basis = main.screen.global_basis
	main._on_grab_ended(pointer)
	check(field.global_basis.is_equal_approx(main.screen.global_basis * audio_before_release.inverse() * before_release), "scene follows audio when release snaps small pitch and roll")
	var library := root.get_node("Library")
	var music_path: String = main.player.current_path
	pointer.last_uv = Vector2(-1, -1)
	pointer.grip_held = true
	pointer.trigger_held = false
	pointer._on_button_pressed("ax_button")
	check(library.is_favorite(music_path), "Grip + A / X favourites music during visualization")
	pointer._on_button_released("ax_button")
	pointer._on_button_pressed("ax_button")
	check(not library.is_favorite(music_path), "Grip + A / X removes the music favourite")
	pointer._on_button_released("ax_button")
	pointer.grip_held = false
	var previous_preset: int = settings.visualizer_preset
	pointer._on_button_pressed("primary_click")
	pointer._on_button_released("primary_click")
	check(settings.visualizer_preset == (previous_preset + 1) % settings.VISUALIZER_PRESETS.size(), "unmodified stick tap advances music scene")
	previous_preset = settings.visualizer_preset
	pointer._on_button_pressed("primary_click")
	pointer._update_recenter_hold(1.1)
	pointer._on_button_released("primary_click")
	check(settings.visualizer_preset == previous_preset, "holding stick to recenter does not advance music scene")
	library.entries.erase(music_path)
	library.favorites.erase(music_path)
	check("visualizer_grab_mode" in settings._persisted(), "grab mode persists")
	settings.apply("visualizer_grab_mode", 99)
	check(settings.visualizer_grab_mode == settings.VisualizerGrab.AUDIO_ONLY, "invalid grab mode clamps safely")
	settings.visualizer_grab_mode = settings.VisualizerGrab.DEFAULT
	settings.save_pending = false
	main.player.stop()
	main.free()
	for key in saved:
		settings.set(key, saved[key])
	settings.save_pending = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
