extends SceneTree

var failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func settled(ui: Control) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while ui.scan_started_msec >= 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(ui.scan_started_msec < 0, "folder scan completes")


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(30).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	var library := root.get_node("Library")
	var base := ProjectSettings.globalize_path("user://folder-favorites")
	var folder := base.path_join("current")
	for path in [folder.path_join("child"), base.path_join("outside")]:
		DirAccess.make_dir_recursive_absolute(path)
	var first := folder.path_join("star.png")
	var nested := folder.path_join("child/nested-star.png")
	var outside := base.path_join("outside/star.png")
	var video := folder.path_join("star.mp4")
	for path in [first, nested, outside, video, folder.path_join("plain.png")]:
		FileAccess.open(path, FileAccess.WRITE).close()
	for path in [first, nested, outside, video]:
		library.set_favorite(path, true)
	settings.last_directory = folder
	settings.last_file = ""
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.ui
	await settled(ui)
	ui.favorites_filter_button.button_pressed = true
	await settled(ui)
	check(settings.library_favorites_only, "favourites toggle applies immediately")
	check(ui.listing.size() == 2 and first in ui.listing and video in ui.listing, "normal view keeps only current folder favourites")
	ui.flat_view_button.button_pressed = true
	await settled(ui)
	check(ui.listing.size() == 3 and nested in ui.listing and outside not in ui.listing, "Flat view includes nested favourites and excludes other folders")
	var playlists: Array[Dictionary] = []
	ui.scanner.finished.connect(func(result: Dictionary) -> void:
		if result["kind"] == "playlist":
			playlists.append(result))
	ui._request_playlist(first)
	var deadline := Time.get_ticks_msec() + 5000
	while playlists.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not playlists.is_empty() and playlists.back()["files"] == PackedStringArray([nested, first]), "photo navigation stays within filtered Flat view")
	settings.library_filter = settings.LibraryFilter.PHOTOS
	ui.refresh_directory()
	await settled(ui)
	check(ui.listing.size() == 2 and video not in ui.listing, "favourites combine with media-type filter")
	ui._set_query("nested")
	await settled(ui)
	check(ui.listing == PackedStringArray([nested]), "favourites combine with search")
	ui.set_favorite(nested, false)
	await settled(ui)
	check(ui.listing.is_empty(), "removing a favourite updates filtered results")
	ui._set_query("")
	await settled(ui)
	ui.favorites_filter_button.button_pressed = false
	await settled(ui)
	check(ui.listing.size() == 3, "turning filter off restores unstarred photos")
	ui.favorites_filter_button.button_pressed = true
	await settled(ui)
	settings.save_config()
	check(settings.flush() == OK, "filter settings save")
	settings.library_favorites_only = false
	settings.load_config()
	check(settings.library_favorites_only, "favourites filter survives settings reload")
	ui._select_source(settings.LibrarySource.FAVORITES)
	await process_frame
	check(not ui._scan_filter().has("favorites"), "folder filter does not constrain other sources")
	check(outside in ui.listing, "global favourites still includes other folders")
	var scanner = ui.scanner
	var audio_filter := {"favorites": {"/star.mp3": true}, "kind": settings.LibraryFilter.PHOTOS}
	check(scanner._ordered_playlist(PackedStringArray(["/plain.mp3", "/star.mp3"]), {"audio_only": true, "filter": audio_filter}) == PackedStringArray(["/star.mp3"]), "audio playlists honour favourites without applying video filters")
	main.queue_free()
	await process_frame
	print("RESULT: folder favourites failures=%d" % failures)
	quit(1 if failures else 0)
