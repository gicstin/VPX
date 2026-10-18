extends SceneTree

var failures := 0
var checks := 0
var opened: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func subtitles() -> void:
	var tracks = load("res://scripts/media_tracks.gd").new()
	root.add_child(tracks)
	tracks.path = "user://audit.mkv"
	tracks.subtitle_tracks = [{"kind": "embedded", "index": 3}, {"kind": "embedded", "index": 7}]
	for index in [7, 3]:
		root.get_node("Library").set_pref(tracks.path, "subtitle", {"kind": "embedded", "index": index, "path": ""})
		tracks._restore_subtitle()
		check(tracks.subtitle_tracks[tracks.subtitle_choice].index == index, "embedded subtitle restores stream %d" % index)
	root.get_node("Library").set_pref(tracks.path, "subtitle", "off")
	tracks._restore_subtitle()
	check(tracks.subtitle_choice == -1, "saved subtitle off stays off")
	var paths := ["user://audit_first.srt", "user://audit_second.srt"]
	tracks.subtitle_tracks.clear()
	for path in paths:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("1\n00:00:00,000 --> 00:00:05,000\nAudit subtitle\n")
		file.close()
		tracks.subtitle_tracks.append({"kind": "external", "index": -1, "path": path})
	root.get_node("Library").set_pref(tracks.path, "subtitle", {"kind": "external", "index": -1, "path": paths[1]})
	tracks._restore_subtitle()
	check(tracks.subtitle_choice == 1, "external subtitle restores by path despite matching negative stream IDs")
	await create_timer(0.1).timeout
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	tracks.free()

func history() -> void:
	var data := PackedFloat32Array()
	data.resize(2400)
	data.fill(0.7)
	var scope := PackedFloat32Array()
	scope.resize(512)
	scope.fill(0.1)
	var gains: Array[float] = []
	for fps in [90, 30, 15]:
		var stereo = load("res://scripts/stereo_image.gd").new()
		stereo.feed(data, false)
		for i in fps * 4:
			stereo.update(1.0 / fps)
			stereo.feed_scope(scope)
		check(stereo.band_ring.head == 179 and stereo.correlation_ring.head == 179 and stereo.field_ring.head == 179 and stereo.source_ring.head == 51, "all stereo histories cover four seconds at %d FPS" % fps)
		check(stereo.scope_head == 24, "scope history covers four seconds at %d FPS" % fps)
		gains.append(stereo.scope_gain)
		stereo.clear_scope()
		check(stereo.scope_head == 0 and stereo.scope_elapsed == 0.0, "scope reset clears timing at %d FPS" % fps)
	check(absf(gains[0] - gains[1]) < 0.001 and absf(gains[0] - gains[2]) < 0.001, "scope gain has the same response across frame rates")

func run() -> void:
	create_timer(35).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.remote_control = false
	settings.resume_playback = false
	settings.auto_crop = false
	settings.music_visualizer = false
	settings.immersive_music_visualizer = false
	await subtitles()
	history()
	settings.apply("visualizer_sync", 0.25)
	check(settings.visualizer_sync <= settings.visualizer_advance_limit() + 0.000001, "visual advance cannot exceed available audio")
	settings.apply("visualizer_sync", -0.25)
	check(settings.visualizer_sync == -0.25, "full visual delay remains available")
	settings.apply("visualizer_sync", 0.0)
	var photo_path := "user://audit_photo.png"
	var audio_path := "user://audit_audio.wav"
	var photo := Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	photo.fill(Color.BLUE)
	photo.save_png(photo_path)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(44100 * 2 * 10)
	audio.data = samples
	audio.save_to_wav(audio_path)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await main.player.open(ProjectSettings.globalize_path(photo_path)), "remote fixture photo opens")
	check(await main.player.open(ProjectSettings.globalize_path(audio_path)), "remote fixture music opens over photo")
	var remote = load("res://scripts/remote_control.gd").new()
	remote.player = main.player
	remote.open_path = func(path: String, options: Dictionary) -> void: opened.append([path, options])
	var music := main.player.music_path as String
	var image: RefCounted = main.player.image
	var status: Dictionary = remote._status()
	check(status.get("path") == music and float(status.get("duration", 0)) > 9.0, "remote reports music path and duration over photo")
	remote._handle(JSON.stringify({"path": music, "playerState": 1}))
	check(main.player.paused and opened.is_empty(), "remote pauses current music without reopening it")
	remote._handle(JSON.stringify({"currentTime": 2.0}))
	check(absf(main.player.stream_position - 2.0) < 0.1, "remote seeks background music")
	remote._handle(JSON.stringify({"playerState": 0}))
	await create_timer(0.25).timeout
	check(not main.player.paused and main.player.stream_position > 2.05, "remote resumes background music")
	check(main.player.image == image and main.player.current_path == ProjectSettings.globalize_path(photo_path), "remote music transport preserves displayed photo")
	var saved_path: String = main.player.current_path
	main.player.current_path = ""
	check(remote._status().get("path") == music, "remote still reports music when picture path is empty")
	main.player.current_path = saved_path
	remote._handle(JSON.stringify({"path": "next.wav", "currentTime": 1.0, "playerState": 1}))
	check(opened.size() == 1 and opened[0][0] == "next.wav" and opened[0][1].get("start_time") == 1.0 and opened[0][1].get("paused"), "new remote paths retain opening transport options")
	main.player.stop_music()
	check(remote._status().is_empty(), "photo without music reports no remote playback")
	main.player.paused = false
	remote._handle(JSON.stringify({"playerState": 1}))
	check(not main.player.paused, "photo without music ignores transport commands")
	remote.free()
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(photo_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_path))
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
