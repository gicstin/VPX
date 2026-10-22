extends SceneTree

var Directory: GDScript

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames(count := 4) -> void:
	for i in count:
		await process_frame


func settle(service: Node) -> void:
	for i in 100:
		if not service.busy:
			break
		await process_frame
	await frames()


func _run() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(50).timeout.connect(func() -> void: printerr("FAIL: discovery timeout"); quit(2))
	Directory = load("res://scripts/radio_directory.gd")
	var path: String = Directory.search_path({"name": "Jazz & Ελληνικά", "tag": "chill out", "countrycode": "GR", "language": "greek", "order": "clicktrend"}, 40)
	check("name=Jazz%20%26%20" in path and "tag=chill%20out" in path and "offset=40" in path and "countrycode=GR" in path and "language=greek" in path and "hidebroken=true" in path, "search escapes Unicode and separators and combines filters with pagination")
	check("order=clickcount" in Directory.search_path({"order": "injected&limit=99999"}, -1), "sort values and offsets stay bounded")
	check(Directory.mirror_urls([null, {"name": "de1.api.radio-browser.info"}, {"name": "de1.api.radio-browser.info"}, {"name": "attacker.example"}, {"name": "bad@de1.api.radio-browser.info"}]) == ["https://de1.api.radio-browser.info"], "mirror discovery deduplicates and rejects unrelated hosts")
	check(Directory.normalize_station(null).is_empty() and Directory.normalize_station({"url": "file:///tmp/a"}).is_empty() and Directory.normalize_station({"url": "https://valid.example", "lastcheckok": 0}).is_empty(), "malformed, non-web and known broken stations are discarded")
	var normalized: Dictionary = Directory.normalize_station({"name": "  Ελληνικά  ", "url_resolved": "javascript:bad", "url": "http://stream.example/live", "bitrate": 128})
	check(normalized["name"] == "Ελληνικά" and normalized["url"] == "http://stream.example/live", "normalization preserves names and falls back to a playable source")
	check(Directory.normalize_station({"url": "https://stream.example/flacm", "codec": "OGG"})["codec"] == "FLAC" and Directory.normalize_station({"name": "Opus Station", "url": "https://stream.example/live", "codec": "OGG"})["codec"] == "OPUS", "Ogg containers retain advertised FLAC and Opus quality")
	check(Directory.normalize_station({"name": "FLAC Radio", "url": "https://stream.example/live.mp3", "codec": "MP3"})["codec"] == "MP3", "station branding cannot relabel an explicit lossy codec")
	var service: Node = load("res://packaging/checks/radio_directory_fixture.gd").new()
	root.add_child(service)
	service.servers.assign(["https://bad.example", "https://good.example"])
	service.search({})
	await settle(service)
	check(service.stations.size() == 40 and service.has_more and service.offset == 42, "results deduplicate stream URLs, skip invalid rows and retain raw paging offset")
	check(service.calls[0].begins_with("https://bad.example") and service.servers[0] == "https://good.example", "failed directory mirror retries and remembers the working mirror")
	check(not service.countries.is_empty() and not service.languages.is_empty(), "filter catalogs load after results")
	service.search({}, true)
	await settle(service)
	check(service.stations.size() == 80, "load more appends distinct stations")
	service.fail = true
	service.search({}, true)
	await settle(service)
	check(not service.error.is_empty() and not service.busy and service.stations.size() == 80, "directory errors retain loaded stations and allow retry")
	service.fail = false
	service.slow = true
	service.search({"name": "old"})
	service.slow = false
	service.search({"name": "new"})
	await frames(20)
	check(service.filters["name"] == "new" and service.stations[0]["name"] != "Old" and service.stations.size() == 40, "superseded search cannot overwrite newer results")
	service.search({"order": "random"})
	await settle(service)
	check(not service.has_more, "random discovery avoids unstable pagination")
	service.quality_mode = true
	service.search({"codec": "FLAC"})
	await settle(service)
	check(service.stations.size() == 1 and service.has_more and service.offset == 40, "FLAC search retains paging through Ogg candidates")
	service.search({"codec": "FLAC"}, true)
	await settle(service)
	check(service.stations.size() == 2 and not service.has_more and service.offset == 80 and service.stations[1]["codec"] == "FLAC", "FLAC pagination includes Ogg FLAC, deduplicates URLs and excludes MP3 variants")
	service.search({"codec": "OPUS"})
	await settle(service)
	check(service.stations.size() == 1 and service.stations[0]["codec"] == "OPUS" and service.offset == 80, "Opus search skips empty candidate pages and finds Ogg Opus")
	service.queue_free()
	await _ui_checks()
	print("Radio discovery: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _ui_checks() -> void:
	var settings := root.get_node("Settings")
	var library := root.get_node("Library")
	settings.last_file = ""
	settings.library_source = settings.LibrarySource.FOLDER
	settings.library_query = "local query"
	settings.library_filter = settings.LibraryFilter.PHOTOS
	settings.hide_menu_on_play = false
	library.entries = {}
	library.favorites = {}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(15)
	var ui = main.ui
	var discovery = ui.discovery
	check(not discovery.directory.started and discovery.directory.requests.is_empty(), "ordinary library browsing makes no radio-directory requests")
	var original = discovery.directory
	discovery.remove_child(original)
	original.queue_free()
	discovery.directory = load("res://packaging/checks/radio_directory_fixture.gd").new()
	discovery.add_child(discovery.directory)
	discovery.directory.changed.connect(discovery.results_changed.emit)
	discovery.directory.catalogs_changed.connect(discovery._catalogs_changed)
	ui._select_source(settings.LibrarySource.DISCOVER)
	ui._select_source(settings.LibrarySource.FOLDER)
	await frames()
	check(not discovery.directory.started and discovery.directory.calls.is_empty(), "leaving Discover immediately cancels deferred directory startup")
	ui._select_source(settings.LibrarySource.DISCOVER)
	await frames(20)
	check(discovery.visible and not ui.search_button.get_parent().visible and ui.listing.size() == 40, "Discover opens popular stations despite local query and photo filters")
	check(discovery.country.item_count == 2 and discovery.language.item_count == 2, "country and language choices populate")
	discovery.genre.select(8)
	discovery.country.select(1)
	discovery.language.select(1)
	discovery.set_search("Station")
	await settle(discovery.directory)
	check(discovery.directory.filters["tag"] == "jazz" and discovery.directory.filters["countrycode"] == "GR" and discovery.directory.filters["language"] == "greek", "genre, country, language and name combine in one search")
	ui._open_search()
	check(ui.keyboard.visible and ui.keyboard_purpose == "radio_search", "search shortcut opens VR-capable radio keyboard")
	ui.keyboard.field.text = "New name"
	ui.keyboard._submit()
	await settle(discovery.directory)
	check(discovery.field.text == "New name" and settings.library_query == "local query", "radio keyboard searches without changing local library query")
	var url: String = ui.listing[0]
	var card = ui.media_grid.control_at(0)
	card.star.button_pressed = true
	check(library.is_favorite(url) and library.get_pref(url, "radio_station", {}).get("name") == "Station 0", "starring an unplayed station saves its stream and name")
	check(not root.get_node("MediaInfo").requested.has(url), "discovery cards do not probe or download radio streams")
	discovery._mode("saved")
	await frames()
	check(ui.listing == PackedStringArray([url]) and not discovery.directory.busy, "saved stations remain available without a directory request")
	ui.media_grid.control_at(0).star.button_pressed = false
	await frames()
	check(ui.listing.is_empty() and not library.is_favorite(url), "unstarring removes a saved station immediately")
	library.set_favorite(url, true)
	ui.refresh_directory()
	check(library.save() == OK, "saved station persists")
	library.entries = {}
	library.favorites = {}
	library._load()
	library._index_favorites()
	check(library.is_favorite(url) and library.get_pref(url, "title") == "Station 0", "station title and favourite survive reload")
	var Backup = load("res://scripts/settings_backup.gd")
	var backup_path := ProjectSettings.globalize_path("user://discovery-backup.cfg")
	check(Backup.export_settings(backup_path)["ok"], "backup supports Discover source")
	settings.library_source = 0
	check(Backup.import_settings(backup_path)["ok"] and settings.library_source == settings.LibrarySource.DISCOVER, "backup restores Discover source")
	discovery.directory.fail = true
	discovery.submit()
	await settle(discovery.directory)
	var retry := false
	for child in ui.file_list.get_children():
		if child is Button and child.text == "Retry":
			retry = true
	check(retry and ui.listing.is_empty(), "offline discovery shows a working retry action")
	discovery._mode("saved")
	await frames()
	check(ui.listing == PackedStringArray([url]), "directory failure does not hide saved stations")
	discovery.directory.fail = false
	discovery.submit()
	await settle(discovery.directory)
	settings.apply("ui_size", 1.25)
	settings.apply("text_size", 1.5)
	await frames(15)
	var bounds: Rect2 = ui.get_viewport_rect()
	var tabs_fit := true
	for button in ui.source_buttons:
		tabs_fit = tabs_fit and bounds.encloses(button.get_global_rect())
	check(tabs_fit and ui.file_scroll.size.y > 100, "largest UI and text sizes keep source tabs and results accessible")
	check(discovery.get_global_rect().end.y <= ui.file_list.global_position.y, "discovery toolbar and station results share scrolling without overlap")
	ui._select_source(settings.LibrarySource.FOLDER)
	check(not discovery.visible and ui.search_button.get_parent().visible and settings.library_filter == settings.LibraryFilter.PHOTOS and settings.library_query == "local query", "leaving discovery restores local search and filters")
	main.queue_free()
	await frames()
