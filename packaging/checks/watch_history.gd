extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func _run() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	var History = load("res://scripts/watch_history.gd")
	var Card = load("res://scripts/media_card.gd")
	create_timer(45).timeout.connect(func() -> void: quit(2))
	var library := root.get_node("Library")
	library.entries = {}
	var history = History.new()
	history.begin("test.mp4")
	history.sample(89.9, 100.0, true)
	check(not history.counted, "before 90 percent stays unwatched")
	history.sample(95.0, 100.0, false)
	check(not history.counted, "paused seek does not count until playback resumes")
	history.sample(90.0, 100.0, true)
	check(history.counted and library.get_pref("test.mp4", "view_count", 0) == 1, "reaching 90 percent counts a view without coverage tracking")
	history.sample(100.0, 100.0, true)
	check(library.get_pref("test.mp4", "view_count", 0) == 1, "same session cannot count twice")
	history.begin("test.mp4")
	history.sample(99.0, 100.0, true)
	check(library.get_pref("test.mp4", "view_count", 0) == 2, "seeking past 90 percent on replay adds one view")
	history.begin("live.mp3")
	history.sample(1000.0, 0.0, true, true)
	check(not history.counted, "unknown duration earns no listen")
	history.begin("song.mp3")
	history.sample(89.0, 100.0, true, true)
	check(not history.counted, "audio before 90 percent stays unlistened")
	history.sample(95.0, 100.0, true, true)
	history.sample(99.0, 100.0, true, true)
	check(library.get_pref("song.mp3", "listen_count", 0) == 1 and library.get_pref("song.mp3", "view_count", 0) == 0, "audio counts one listen and no views")
	history.begin("https://example.test/audio")
	history.sample(95.0, 100.0, true, true)
	var settings := root.get_node("Settings")
	settings.remember_position("seek.mp4", 99.0, 100.0)
	check(not library.get_pref("seek.mp4", "finished", false), "resume near end cannot set finished")
	library.set_pref("legacy.mp4", "finished", true)
	var card = Card.new()
	root.add_child(card)
	card.setup("legacy.mp4", false, Card.Layout.ROW, Callable())
	check(not card.watched_badge.visible and not card.meta_label.text.contains("Watched"), "legacy seek-based flag cannot claim watched")
	card.queue_free()
	for layout in [Card.Layout.CARD, Card.Layout.ROW, Card.Layout.CHIP]:
		card = Card.new()
		root.add_child(card)
		card.setup("test.mp4", false, layout, Callable())
		check(card.watched_badge.visible and card.watched_label.text == "2 views", "watched badge and count in layout %d" % layout)
		card.set_playing(true)
		card.refresh()
		if layout == Card.Layout.CARD:
			check(card.playing_badge.offset_top < card.watched_badge.offset_top, "playing and watched badges stay separate")
		card.queue_free()
	for media in ["song.mp3", "https://example.test/audio"]:
		for layout in [Card.Layout.CARD, Card.Layout.ROW, Card.Layout.CHIP]:
			card = Card.new()
			root.add_child(card)
			card.setup(media, false, layout, Callable())
			check(card.watched_badge.visible and card.watched_label.text == "1 listen" and card.watched_badge.tooltip_text.begins_with("Listened"), "listened badge for %s in layout %d" % [media, layout])
			card.queue_free()
	check(library.save() == OK, "view count saves")
	library.entries = {}
	library._load()
	check(library.get_pref("test.mp4", "view_count", 0) == 2, "view count survives reload")
	check(library.get_pref("song.mp3", "listen_count", 0) == 1, "listen count survives reload")
	await playback_check()
	print("Watch history: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func playback_check() -> void:
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.remote_control = false
	settings.auto_crop = false
	settings.playback_speed = 1.0
	settings.end_action = 0
	var path := ProjectSettings.globalize_path("user://watch-playback.mp4")
	var result := OS.execute("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=30", "-t", "4", "-c:v", "libx264", "-y", path])
	check(result == 0, "create playback fixture")
	if result != 0:
		return
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var player = main.player
	check(await player.open(path), "open real video")
	player.seek_to(3.8)
	await create_timer(0.8).timeout
	var library := root.get_node("Library")
	check(library.get_pref(path, "view_count", 0) == 1, "real seek past 90 percent counts watched view")
	player.restart()
	await wait_for_view(path, 2)
	check(library.get_pref(path, "view_count", 0) == 2, "real playback after restart counts another view")
	player.restart()
	await wait_for_view(path, 3)
	check(library.get_pref(path, "view_count", 0) == 3, "real restart counts third view")
	var audio_path := ProjectSettings.globalize_path("user://listen-playback.wav")
	result = OS.execute("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-y", audio_path])
	check(result == 0, "create audio fixture")
	if result == 0:
		check(await player.open(audio_path), "open real audio")
		player.seek_to(3.65)
		await create_timer(0.2).timeout
		check(library.get_pref(audio_path, "listen_count", 0) == 1 and library.get_pref(audio_path, "view_count", 0) == 0, "real audio earns listen instead of view")
		var picture := Image.create(16, 16, false, Image.FORMAT_RGB8)
		picture.fill(Color.RED)
		var picture_path := ProjectSettings.globalize_path("user://listen-picture.png")
		check(picture.save_png(picture_path) == OK, "create picture fixture")
		check(await player.open(picture_path), "open picture while audio remains")
		check(await player.open(audio_path), "open audio over picture")
		check(player.music_path == audio_path and player.is_image(), "audio plays over picture")
		player.seek_to(3.65)
		await create_timer(0.2).timeout
		check(library.get_pref(audio_path, "listen_count", 0) == 2, "audio over picture earns another listen")
		player.restart()
		player.seek_to(3.65)
		await create_timer(0.2).timeout
		check(library.get_pref(audio_path, "listen_count", 0) == 3 and player.watch_history.path == audio_path, "audio restart over picture counts correct path")
	main.queue_free()
	await process_frame


func wait_for_view(path: String, count: int) -> void:
	var library := root.get_node("Library")
	var deadline := Time.get_ticks_msec() + 6000
	while int(library.get_pref(path, "view_count", 0)) < count and Time.get_ticks_msec() < deadline:
		await process_frame
