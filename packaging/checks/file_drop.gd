extends SceneTree

const Synth := preload("res://packaging/checks/music_synth.gd")

var failures := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func wait(frames := 20) -> void:
	for frame in frames:
		await process_frame


func drop(main: Node, files: Array) -> void:
	main.get_window().files_dropped.emit(PackedStringArray(files))
	await wait()


func opened(main: Node, path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while main.player.current_path != path and Time.get_ticks_msec() < deadline:
		await process_frame
	return main.player.current_path == path


func run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	var base := OS.get_user_data_dir().path_join("drop")
	var nested := base.path_join("nested")
	DirAccess.make_dir_recursive_absolute(nested)
	var song := base.path_join("song.wav")
	var synth := Synth.new(120.0, 4)
	synth.four_on_floor(0, 4)
	synth.normalise(0.5)
	synth.save_wav(song, 1.0, 1.0)
	var junk := base.path_join("notes.txt")
	var subtitle := base.path_join("clip.srt")
	FileAccess.open(junk, FileAccess.WRITE).store_string("x")
	FileAccess.open(subtitle, FileAccess.WRITE).store_string("1\n00:00:00,000 --> 00:00:02,000\nHello\n")
	var clip := base.path_join("clip.mp4")
	OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=30:duration=3", "-pix_fmt", "yuv420p", clip])
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.last_directory = OS.get_user_data_dir()
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait(30)
	var ui = main.ui
	check(main.desktop_mode, "desktop mode")
	check(ui.open_dropped(PackedStringArray([junk])) == "", "unsupported file ignored")
	check(ui.open_dropped(PackedStringArray([subtitle])) == "", "subtitle ignored without video")
	main.panel.close()
	settings.apply("library_source", settings.LibrarySource.RECENT)
	await drop(main, [nested])
	check(ui.directory == nested, "folder drop sets directory")
	check(settings.library_source == settings.LibrarySource.FOLDER, "folder drop switches to folder source")
	check(main.panel.is_open(), "folder drop opens menu")
	check(ui.library_tabs.views[ui.library_tabs.active]["directory"] == nested, "current tab keeps dropped folder")
	await drop(main, [junk, song, nested])
	check(ui.directory == base, "media drop sets parent folder")
	check(settings.last_directory == base, "media drop remembers folder")
	check(await opened(main, song), "media drop opens file")
	check(ui.library_tabs.views[ui.library_tabs.active]["directory"] == base, "current tab follows media folder")
	if FileAccess.file_exists(clip):
		await drop(main, [clip])
		check(await opened(main, clip), "video drop opens file")
		check(ui.open_dropped(PackedStringArray([subtitle])) == "subtitle", "subtitle drop loads on video")
		var external: Array = main.player.tracks.subtitle_tracks.filter(func(track: Dictionary) -> bool: return track.get("path", "") == subtitle)
		check(not external.is_empty(), "subtitle track added")
	else:
		print("SKIP: ffmpeg missing, video subtitle drop")
	main.player.stop()
	await wait(10)
	main.queue_free()
	await wait(5)
	quit(1 if failures else 0)
