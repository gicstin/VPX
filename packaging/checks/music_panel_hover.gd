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

func frames(count := 6) -> void:
	for frame in count:
		await process_frame

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(44100 * 2 * 8)
	audio.data = samples
	var path := "user://hover_music_%d.wav" % Time.get_ticks_usec()
	audio.save_to_wav(path)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await main.player.open(ProjectSettings.globalize_path(path)), "music fixture opens")
	main.panel.visible = false
	main.player.paused = false
	await frames()
	main.osd.release()
	main.osd.dismiss()
	main.osd.opacity = 0.0
	main.osd.visible = false
	await frames()
	var controls = main.photo_bar.root
	check(controls.visible and main.player.is_music_mode(), "desktop music player is active")
	controls.immersive_button.pressed.emit()
	await frames()
	var before: Vector2 = controls.scale
	var bounds: Vector2 = controls.size
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(1200, 360)
	motion.global_position = motion.position
	main.desktop_view.osd_cooldown = 0.0
	main.desktop_view.handle_input(motion)
	await frames()
	check(main.osd.target_opacity == 0.0 and not main.osd.visible, "hover outside music controls does not show track-name overlay")
	check(controls.scale.is_equal_approx(before) and controls.size.is_equal_approx(bounds), "hover leaves player size and scale unchanged")
	main.osd.show_status("Volume 80%", main.camera)
	await frames()
	check(main.desktop_view.osd_rect.visible, "explicit status overlays remain available")
	check(controls.scale.is_equal_approx(before) and controls.size.is_equal_approx(bounds), "status overlays do not shrink music player")
	main.osd.release()
	main.osd.dismiss()
	main.osd.opacity = 0.0
	main.osd.visible = false
	await frames()
	check(controls.scale.is_equal_approx(before), "status dismissal leaves player scale unchanged")
	main.player.current_path = "test-video.mp4"
	main.player.stream_metadata["audio_only"] = false
	main.desktop_view.osd_cooldown = 0.0
	main.desktop_view._reveal_osd()
	check(main.osd.target_opacity > 0.0, "video hover still reveals playback overlay")
	main.player.stop()
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
