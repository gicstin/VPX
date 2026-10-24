extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func settled(ui: Control) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (ui.scan_started_msec >= 0 or is_instance_valid(ui.paths_job)) and Time.get_ticks_msec() < deadline:
		await process_frame
	for frame in 5:
		await process_frame
	check(ui.scan_started_msec < 0, "scan completes")


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(40).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	var library := root.get_node("Library")
	var base := ProjectSettings.globalize_path("user://play-count")
	DirAccess.make_dir_recursive_absolute(base.path_join("child"))
	var video := base.path_join("a.mp4")
	var audio := base.path_join("b.wav")
	var unseen := base.path_join("c.mp4")
	var unheard := base.path_join("d.wav")
	var photo := base.path_join("e.png")
	var nested := base.path_join("child/nested.mp4")
	var nested_played := base.path_join("child/played.mp4")
	for path in [video, audio, unseen, unheard, photo, nested, nested_played]:
		FileAccess.open(path, FileAccess.WRITE).close()
		library.mark_played(path)
	library.set_pref(video, "view_count", 2)
	library.set_pref(audio, "listen_count", 3)
	library.set_pref(unseen, "position", 20.0)
	library.set_pref(nested_played, "view_count", 5)
	for path in [unseen, unheard, nested, audio]:
		library.set_favorite(path, true)
	settings.last_directory = base
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.remote_control = false
	root.get_node("MediaInfo").available = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.ui
	await settled(ui)
	ui.sort_button.item_selected.emit(settings.LibrarySort.PLAY_COUNT)
	await settled(ui)
	check(settings.library_sort == settings.LibrarySort.PLAY_COUNT and ui.sort_button.get_item_text(settings.library_sort) == "Play count", "play-count option applies through sort control")
	check(ui.listing == PackedStringArray([audio, video, unseen, unheard, photo]), "folder sorts views and listens together, descending with name ties")
	var filter: Dictionary = ui._scan_filter()
	library.set_pref(video, "view_count", 4)
	check(filter["play_counts"][video] == 2, "scanner uses an isolated play-count snapshot")
	library.set_pref(video, "view_count", 2)
	ui.unplayed_filter_button.button_pressed = true
	await settled(ui)
	check(settings.library_unplayed_only and ui.listing == PackedStringArray([unseen, unheard]), "Unplayed keeps unfinished video and audio and excludes photos")
	check(not ui.folder_grid.is_empty(), "Unplayed keeps folders available for navigation")
	ui.favorites_filter_button.button_pressed = true
	ui.flat_view_button.button_pressed = true
	await settled(ui)
	check(ui.listing.size() == 3 and unseen in ui.listing and unheard in ui.listing and nested in ui.listing, "Unplayed combines with favourites and Flat view")
	ui._set_query("nested")
	await settled(ui)
	check(ui.listing == PackedStringArray([nested]), "Unplayed combines with recursive search")
	ui._set_query("")
	await settled(ui)
	settings.library_filter = settings.LibraryFilter.PHOTOS
	ui.refresh_directory()
	await settled(ui)
	check(ui.listing.is_empty(), "photo-only and Unplayed yields no playable media")
	settings.library_filter = settings.LibraryFilter.ALL
	ui.refresh_directory()
	await settled(ui)
	library.set_pref(unseen, "view_count", 1)
	library.watch_changed.emit(unseen)
	await settled(ui)
	check(ui.listing.size() == 2 and unheard in ui.listing and nested in ui.listing, "newly watched media disappears immediately")
	check(ui.scanner._ordered_playlist(PackedStringArray([audio, unheard]), {"audio_only": true, "sort": settings.LibrarySort.PLAY_COUNT, "filter": ui._scan_filter()}) == PackedStringArray([unheard]), "audio playlists retain Unplayed and favourites")
	var audio_request := {"audio_only": true, "sort": settings.LibrarySort.PLAY_COUNT, "filter": {"play_counts": {audio: 3, unheard: 1}}}
	check(ui.scanner._ordered_playlist(PackedStringArray([unheard, audio]), audio_request) == PackedStringArray([audio, unheard]), "audio playlists follow descending listen counts")
	ui.unplayed_filter_button.button_pressed = false
	ui.favorites_filter_button.button_pressed = false
	ui.flat_view_button.button_pressed = false
	await settled(ui)
	library.set_pref(video, "view_count", 6)
	library.watch_changed.emit(video)
	await settled(ui)
	check(ui.listing[0] == video, "play-count order updates immediately when count changes")
	ui._select_source(settings.LibrarySource.RECENT)
	await settled(ui)
	check(ui.listing[0] == video and ui.listing[1] == nested_played, "Recent supports play-count order")
	ui._select_source(settings.LibrarySource.FAVORITES)
	await settled(ui)
	check(ui.listing[0] == audio and ui.listing[1] == unseen, "Favourites supports play-count order")
	ui.unplayed_filter_button.button_pressed = true
	await settled(ui)
	check(ui.listing.size() == 2 and unheard in ui.listing and nested in ui.listing, "Favourites supports Unplayed")
	ui.unplayed_filter_button.button_pressed = false
	var first_link := "https://example.test/a.mp4"
	var second_link := "https://example.test/b.mp3"
	var unplayed_link := "https://example.test/c.mp4"
	for url in [first_link, second_link, unplayed_link]:
		library.remember_link(url)
	library.set_pref(first_link, "view_count", 2)
	library.set_pref(second_link, "listen_count", 4)
	ui.network.set_meta("scanned", true)
	ui._select_source(settings.LibrarySource.NETWORK)
	await settled(ui)
	check(ui.listing == PackedStringArray([second_link, first_link, unplayed_link]), "opened network links sort by play count")
	ui.unplayed_filter_button.button_pressed = true
	await settled(ui)
	check(ui.listing == PackedStringArray([unplayed_link]), "opened network links honour Unplayed")
	ui.dlna_stack.assign([{"name": "Fixture", "result": {"containers": [], "items": [{"url": first_link, "title": "Video"}, {"url": second_link, "title": "Audio"}, {"url": unplayed_link, "title": "Unplayed"}]}}])
	ui.unplayed_filter_button.button_pressed = false
	await settled(ui)
	check(ui.listing == PackedStringArray([second_link, first_link, unplayed_link]), "media-server items sort by play count")
	ui.unplayed_filter_button.button_pressed = true
	await settled(ui)
	check(ui.listing == PackedStringArray([unplayed_link]), "media-server items honour Unplayed")
	ui._select_source(settings.LibrarySource.FOLDER)
	await settled(ui)
	var tabs = ui.library_tabs
	tabs.new_tab()
	ui.unplayed_filter_button.button_pressed = false
	await settled(ui)
	tabs.select(0)
	await settled(ui)
	check(settings.library_unplayed_only and ui.unplayed_filter_button.button_pressed, "Unplayed persists independently per tab")
	settings.save_config()
	check(settings.flush() == OK, "sort and filter settings save")
	settings.library_unplayed_only = false
	settings.library_sort = settings.LibrarySort.NAME
	settings.load_config()
	check(settings.library_unplayed_only and settings.library_sort == settings.LibrarySort.PLAY_COUNT, "sort and filter survive settings reload")
	var legacy: Dictionary = settings.library_tab_session.duplicate(true)
	for view: Dictionary in legacy["views"]:
		view.erase("library_unplayed_only")
	settings.library_tab_session = legacy
	tabs.restore()
	await settled(ui)
	check(tabs.views.size() == 2 and not settings.library_unplayed_only, "existing saved tabs migrate without losing tabs")
	main.queue_free()
	await process_frame
	print("Play count: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
