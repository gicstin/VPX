extends SceneTree

var failures := 0
var checks := 0
var main: Node
var settings: Node
var fixture := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func write_subtitle(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("1\n00:00:00,000 --> 00:00:05,000\nTransition check\n")
	file.close()

func subtitle_sizes() -> void:
	settings.apply("projection", settings.ProjectionMode.FLAT)
	settings.apply("stereo", settings.Stereo.MONO)
	settings.apply("subtitle_size", 1.2)
	main.ui._save_subtitle_size_for_format()
	settings.apply("subtitle_size", 1.8)
	check(is_equal_approx(settings.subtitle_size, 1.8) and is_equal_approx(main.subtitle_view._active_size(), 1.8), "saved subtitle size permits live editing and rendering")
	main.ui.quick._sync()
	main.ui._sync()
	check(is_equal_approx(settings.subtitle_size, 1.8), "both settings panels preserve live subtitle size")
	main.ui._save_subtitle_size_for_format()
	check(is_equal_approx(settings.subtitle_size_by_format["0:0"], 1.8), "edited subtitle size can replace saved size")
	settings.apply("projection", settings.ProjectionMode.EQUIRECT_360)
	settings.apply("subtitle_size", 0.9)
	main.ui._save_subtitle_size_for_format()
	settings.apply("projection", settings.ProjectionMode.FLAT)
	check(is_equal_approx(settings.subtitle_size, 1.8), "returning to flat format restores its saved size")
	settings.apply("projection", settings.ProjectionMode.EQUIRECT_360)
	check(is_equal_approx(settings.subtitle_size, 0.9), "returning to immersive format restores its saved size")
	settings.apply("subtitle_size", 1.4)
	settings.apply("volume", 75)
	check(is_equal_approx(settings.subtitle_size, 1.4), "unrelated settings do not overwrite subtitle edits")

func photo_rename(photo: String, audio: String) -> void:
	check(await main.player.open(photo), "photo rename fixture opens")
	var rename: Node = main.ui.media_rename
	var image: RefCounted = main.player.image
	var proposal: Dictionary = rename.proposal()
	var result: Dictionary = await rename.rename_current(proposal["name"])
	check(result.get("ok", false), "photo rename succeeds")
	var target: String = proposal["target"]
	check(main.player.current_path == target and main.player.image_path == target and main.player.load_state.get("path") == target, "photo rename updates live and cancellation paths")
	check(main.player.image == image and FileAccess.file_exists(target) and not FileAccess.file_exists(photo), "photo rename keeps the loaded image")
	main.player.open(audio)
	main.player.cancel_open()
	await process_frame
	check(main.player.current_path == target and FileAccess.file_exists(main.player.current_path), "cancel after photo rename keeps the existing renamed path")
	result = await rename.undo()
	check(result.get("ok", false) and main.player.image_path == photo and main.player.current_path == photo, "photo undo restores all live paths")
	main.player.open(audio)
	main.player.cancel_open()
	await process_frame
	check(main.player.current_path == photo and FileAccess.file_exists(photo), "cancel after photo undo keeps the restored path")

func video_rename(video: String) -> void:
	var subs := fixture.path_join("Subs")
	var nested := subs.path_join("movie")
	DirAccess.make_dir_recursive_absolute(nested)
	for suffix in [".srt", ".en.forced.srt", ".fr.sami", ".idx", ".sub"]:
		write_subtitle(video.get_basename() + suffix)
	write_subtitle(subs.path_join("movie.fr.srt"))
	write_subtitle(nested.path_join("spanish.srt"))
	write_subtitle(fixture.path_join("movie2.en.srt"))
	for i in 12:
		write_subtitle(video.get_basename() + ".lang%d.srt" % i)
	check(await main.player.open(video), "video rename fixture opens")
	main.player.tracks.select_subtitle(main.player.tracks._track_index(video.get_basename() + ".en.forced.srt"))
	settings.apply("subtitle_size", 1.1)
	await create_timer(0.1).timeout
	var small_font: int = main.subtitle_view.bottom_label.get_theme_font_size("normal_font_size")
	settings.apply("subtitle_size", 1.8)
	await create_timer(0.1).timeout
	var large_font: int = main.subtitle_view.bottom_label.get_theme_font_size("normal_font_size")
	check(main.subtitle_view.visible and large_font > small_font * 1.5, "live subtitle size changes the displayed text layout")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = main.subtitle_view.viewport.get_texture().get_image()
		var drawn := 0
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				if image.get_pixel(x, y).a > 0.1:
					drawn += 1
		check(drawn > 0, "resized subtitle text renders")
	var nested_path := nested.path_join("spanish.srt")
	var nested_index: int = main.player.tracks._track_index(nested_path)
	check(nested_index >= 0, "nested subtitle discovered before rename")
	check(main.player.tracks._track_index(fixture.path_join("movie2.en.srt")) == -1, "subtitle discovery excludes another movie with a shared name prefix")
	main.player.tracks.select_subtitle(nested_index)
	var rename: Node = main.ui.media_rename
	var proposal: Dictionary = rename.proposal()
	var target: String = proposal["target"]
	var blocked := subs.path_join(target.get_file().get_basename() + ".fr.srt")
	write_subtitle(blocked)
	var result: Dictionary = await rename.rename_current(proposal["name"])
	check(not result.get("ok", false) and FileAccess.file_exists(video) and not FileAccess.file_exists(target), "subtitle collision stops rename without moving media")
	DirAccess.remove_absolute(blocked)
	result = await rename.rename_current(proposal["name"])
	check(result.get("ok", false), "rename supports many language-tagged subtitles")
	for suffix in [".srt", ".en.forced.srt", ".fr.sami", ".idx", ".sub", ".lang11.srt"]:
		check(FileAccess.file_exists(target.get_basename() + suffix) and not FileAccess.file_exists(video.get_basename() + suffix), "rename preserves subtitle suffix " + suffix)
	check(FileAccess.file_exists(blocked) and FileAccess.file_exists(fixture.path_join("movie2.en.srt")), "Subs-folder subtitles follow rename while another movie stays untouched")
	check(main.player.tracks._track_index(nested_path) >= 0 and main.player.tracks.subtitle_tracks[main.player.tracks.subtitle_choice].get("path") == nested_path, "nested subtitle stays discoverable and selected after rename")
	var count: int = main.player.tracks.subtitle_tracks.size()
	rename.recover()
	check(rename.recovery_error.is_empty(), "completed rename needs no recovery")
	result = await rename.undo()
	check(result.get("ok", false) and FileAccess.file_exists(video) and not FileAccess.file_exists(target), "media rename undo succeeds")
	check(FileAccess.file_exists(video.get_basename() + ".en.forced.srt") and FileAccess.file_exists(subs.path_join("movie.fr.srt")), "undo restores original subtitle names")
	check(main.player.tracks.subtitle_tracks.size() == count and main.player.tracks._track_index(nested_path) >= 0, "undo preserves subtitle discovery")
	for name in ["movie_en.srt", "movie-fr.srt", "movie forced.srt"]:
		check(load("res://scripts/media_tracks.gd").matches_stem(name, "movie"), "subtitle matching accepts separator in " + name)

func recovery(video: String) -> void:
	var source := fixture.path_join("recovery.mp4")
	var target := fixture.path_join("recovery_FLAT_MONO.mp4")
	var tagged := fixture.path_join("recovery.en.srt")
	var renamed_tagged := fixture.path_join("recovery_FLAT_MONO.en.srt")
	var nested := fixture.path_join("Subs/recovery/italian.srt")
	DirAccess.make_dir_recursive_absolute(nested.get_base_dir())
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(video))
	file.close()
	write_subtitle(tagged)
	write_subtitle(nested)
	root.get_node("Library").set_pref(source, "subtitle", {"kind": "external", "index": -1, "path": nested})
	var moves: Array = []
	for pair in [[source, target], [tagged, renamed_tagged]]:
		moves.append({"from": pair[0], "to": pair[1], "size": FileAccess.get_size(pair[0]), "mtime": FileAccess.get_modified_time(pair[0])})
	var rename: Node = main.ui.media_rename
	check(rename._write(rename.JOURNAL, {"phase": "moved", "moves": moves, "subtitles": [tagged, nested]}), "interrupted tagged rename journal written")
	for move: Dictionary in moves:
		check(rename._move(move["from"], move["to"]) == OK, "interrupted rename fixture moves " + str(move["from"]).get_file())
	rename.recover()
	var saved: Array = root.get_node("Library").get_pref(target, "subtitle_files", [])
	check(rename.recovery_error.is_empty() and renamed_tagged in saved and nested in saved and not FileAccess.file_exists(rename.JOURNAL), "recovery retains renamed and nested subtitle paths")
	var result: Dictionary = await rename.undo()
	check(result.get("ok", false) and FileAccess.file_exists(source) and FileAccess.file_exists(tagged), "recovered rename can be undone")

func audio_tracks(photo: String, audio: String) -> void:
	check(await main.player.open(photo), "audio-track fixture photo opens")
	root.get_node("Library").set_pref(audio, "audio_delay", 0.2)
	root.get_node("Library").set_pref(audio, "subtitle_delay", -0.1)
	root.get_node("Library").set_pref(audio, "audio_track", 1)
	var image: RefCounted = main.player.image
	check(await main.player.open(audio), "multi-track audio opens over photo")
	var tracks: Node = main.player.tracks
	check(tracks.playback == main.player.playback and tracks.path == audio and tracks.audio_tracks.size() == 2, "background music binds its track controls")
	check(tracks.audio_choice == 1 and main.player.playback.get_audio_track() == 1, "background music restores the saved audio track")
	check(is_equal_approx(settings.audio_delay, 0.2) and is_equal_approx(settings.subtitle_delay, -0.1) and is_equal_approx(tracks.applied_audio_delay, 0.2), "background music restores saved audio and subtitle delays")
	tracks.select_audio(0)
	settings.apply("audio_delay", 0.35)
	check(root.get_node("Library").get_pref(audio, "audio_track") == 0 and is_equal_approx(root.get_node("Library").get_pref(audio, "audio_delay"), 0.35), "background audio controls save track and delay edits")
	check(main.player.image == image and main.player.current_path == photo, "track and delay edits preserve photo")
	check(await main.player.open(audio), "background music reopens")
	check(main.player.tracks.audio_choice == 0 and is_equal_approx(settings.audio_delay, 0.35), "background music restores edited track and delay")
	main.player.stop_music()
	check(main.player.tracks.playback == null and main.player.tracks.audio_tracks.is_empty(), "stopping music clears stale track controls")

func sleep_end(photo: String, short_audio: String) -> void:
	for action in [settings.EndAction.REPEAT, settings.EndAction.NEXT_FILE]:
		check(await main.player.open(photo), "sleep fixture photo opens")
		settings.apply("end_action", action)
		settings.apply("sleep_timer", settings.SleepTimer.END_OF_VIDEO)
		check(await main.player.open(short_audio), "sleep fixture music opens")
		var image: RefCounted = main.player.image
		main.ui.music_playlist = PackedStringArray([short_audio, fixture.path_join("tracks.mka")])
		main.ui.music_playlist_index = main.ui.scanner.index_of(main.ui.music_playlist)
		main.ui.resolving_path = "pending replacement"
		main.ui._on_music_ended()
		check(settings.sleep_timer == settings.SleepTimer.END_OF_VIDEO and main.player.playback != null, "pending replacement keeps end sleep armed")
		main.ui.resolving_path = ""
		await create_timer(1.2).timeout
		check(settings.sleep_timer == settings.SleepTimer.OFF and main.player.playback == null and not main.player.is_playing(), "end sleep overrides music end action %d" % action)
		check(main.player.image == image and main.player.current_path == photo and main.player.tracks.audio_tracks.is_empty(), "end sleep leaves photo and clears ended music controls")

func run() -> void:
	create_timer(65).timeout.connect(func() -> void: quit(2))
	settings = root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.last_directory = ProjectSettings.globalize_path("user://")
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.auto_crop = false
	settings.hide_menu_on_play = false
	settings.music_visualizer = false
	settings.immersive_music_visualizer = false
	settings.end_action = settings.EndAction.STOP
	fixture = ProjectSettings.globalize_path("user://transitions_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture)
	var video := fixture.path_join("movie.mp4")
	var audio := fixture.path_join("tracks.mka")
	var short_audio := fixture.path_join("short.wav")
	var photo := fixture.path_join("photo.png")
	check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=160x90:r=10:d=12", "-c:v", "mpeg4", video]) == 0, "video fixture generated")
	check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=220:duration=12", "-f", "lavfi", "-i", "sine=frequency=440:duration=12", "-map", "0:a", "-map", "1:a", "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=fra", "-c:a", "flac", audio]) == 0, "multi-track fixture generated")
	check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=330:duration=0.65", short_audio]) == 0, "short music fixture generated")
	var picture := Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	picture.fill(Color.BLUE)
	picture.save_png(photo)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	subtitle_sizes()
	await photo_rename(photo, audio)
	await video_rename(video)
	await recovery(video)
	await audio_tracks(photo, audio)
	await sleep_end(photo, short_audio)
	main.player.stop()
	main.free()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
