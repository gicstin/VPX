extends SceneTree

const BackgroundTask := preload("res://scripts/background_task.gd")

var failures := 0
var main: Node
var directory := ProjectSettings.globalize_path("user://critical-ui-test")


class TestDisc extends DiscImage:
	var commands: Array[PackedStringArray] = []
	var slow := false

	func _command(_program: String, arguments: PackedStringArray) -> Dictionary:
		commands.append(arguments)
		var reply := "Mapped file as /dev/loop999999." if arguments[0] == "loop-setup" else "Mounted /dev/loop999999 at /tmp/vpx-disc-test."
		var code := "import time; time.sleep(0.08); print(%s)" % JSON.stringify(reply)
		if slow:
			code = "import time; time.sleep(3)"
		return await super._command("python3", ["-c", code])


func _test_scan_errors() -> void:
	var ui = main.ui
	var missing: String = ui._scan_error_text({"reason": "missing"})
	var denied: String = ui._scan_error_text({"reason": "denied"})
	check(missing.contains("no longer exists") and denied.contains("not allowed") and missing != denied, "folder errors name the cause")
	check(ui._scan_error_text({"message": "Operation timed out"}).contains("stopped responding"), "timeout keeps its own message")
	check(ui._scan_error_text({}) == "This folder cannot be opened", "unknown folder error stays generic")


func _test_library_scale() -> void:
	var ui = main.ui
	var settings := root.get_node("Settings")
	ui.show_library()
	for combo in [[1.0, 1.0, 300.0], [1.25, 1.0, 180.0], [1.0, 1.5, 280.0], [1.25, 1.5, 100.0]]:
		settings.apply("ui_size", combo[0])
		settings.apply("text_size", combo[1])
		for i in 20:
			await process_frame
		var viewport := Vector2(ui.get_viewport().size_2d_override)
		var sheet: Vector2 = ui.get_node("Sheet").size
		var label := "ui %.2f text %.1f" % [combo[0], combo[1]]
		check(sheet.x <= viewport.x + 0.5, "library fits width at " + label)
		check(ui.file_scroll.size.y >= combo[2], "library keeps %d px of list at %s (%d)" % [combo[2], label, ui.file_scroll.size.y])
		check(ui.search_button.text.is_empty() == (viewport.x < 1400.0 or combo[1] > 1.2), "filter labels follow width at " + label)
		var last: Button
		for crumb in ui.crumbs.get_children():
			if crumb is Button:
				last = crumb
		var needed: float = ui.get_theme_font("font", &"Crumb").get_string_size(last.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ui.get_theme_font_size("font_size", &"Crumb")).x + 24.0
		check(last.custom_minimum_size.x >= minf(needed, 320.0) - 0.5, "current folder crumb fits its name at " + label)
		var named := 0
		for source in ui.source_buttons:
			named += int(not source.text.is_empty())
		check(named == (1 if (viewport.x < 1400.0 or combo[1] > 1.2) else ui.source_buttons.size()), "source tabs keep only the active name when compact at " + label)
	settings.apply("ui_size", 1.0)
	settings.apply("text_size", 1.0)
	await process_frame


func _test_window_title() -> void:
	var player = main.player
	var previous: String = player.current_path
	player.current_path = ""
	check(not main._window_title().contains(" — VPX") or main._window_title().begins_with("VPX"), "idle window title is the app name")
	player.current_path = "/media/Some Show/Episode 04.mkv"
	check(main._window_title().begins_with("Episode 04 — VPX"), "window title leads with the playing media")
	player.current_path = previous


func _test_art_retry() -> void:
	var info := root.get_node("MediaInfo")
	var path := directory.path_join("no-art.mp3")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not really audio")
	file.close()
	var signature: String = info._stat_signature(path)
	info.entries[path] = {"sig": signature, "audio": true, "thumb_failed": true, "thumb_failed_at": Time.get_unix_time_from_system()}
	info.request(path, true)
	check(info.entries.has(path) and info.entries[path].has("thumb_failed"), "audio without art keeps its failed thumbnail while the file is unchanged")
	info.entries[path] = {"sig": "stale", "audio": true, "thumb_failed": true, "thumb_failed_at": Time.get_unix_time_from_system()}
	info.request(path, true)
	check(not info.entries.get(path, {}).has("thumb_failed"), "changed audio file retries its thumbnail")
	info.invalidate(path)
	DirAccess.remove_absolute(path)


func _test_stepper_hold() -> void:
	var stepper = main.ui.key_shade
	var settings := root.get_node("Settings")
	var original: Color = settings.chroma_key_color
	var plus: Button
	for child in stepper.get_children():
		if child is Button and child.text == "+":
			plus = child
	check(plus != null and not stepper.is_processing(), "idle stepper does not process")
	var before: float = stepper.value
	plus.button_down.emit()
	check(stepper.is_processing(), "pressed stepper processes")
	var waited := 0.0
	while waited < 1.0:
		await process_frame
		waited += 1.0 / 60.0
	check(stepper.value >= before + 3.0 or stepper.value == stepper.max_value, "held stepper repeats (%.0f -> %.0f)" % [before, stepper.value])
	plus.button_up.emit()
	await process_frame
	await process_frame
	check(not stepper.is_processing(), "released stepper stops processing")
	settings.apply("chroma_key_color", original)


func _test_time_entry() -> void:
	var parser := load("res://scripts/time_entry.gd")
	var cases := [
		["1:23:45", 0.0, 7200.0, 5025.0], ["83:20", 0.0, 7200.0, 5000.0], ["90", 0.0, 7200.0, 90.0], ["90s", 0.0, 7200.0, 90.0],
		["1h30m", 0.0, 7200.0, 5400.0], ["1h30", 0.0, 7200.0, 5400.0], ["2m30", 0.0, 7200.0, 150.0], ["1h 5m 3", 0.0, 7200.0, 3903.0], ["1h 5m 3s", 0.0, 7200.0, 3903.0], ["2m", 0.0, 7200.0, 120.0], ["+30", 100.0, 7200.0, 130.0],
		["-1:00", 100.0, 7200.0, 40.0], ["-500", 100.0, 7200.0, 0.0], ["50%", 0.0, 200.0, 100.0], ["99999", 0.0, 200.0, 200.0],
		["1,5", 0.0, 200.0, 1.5], ["12:3:4:5", 0.0, 200.0, -1.0], ["abc", 0.0, 200.0, -1.0], ["", 0.0, 200.0, -1.0],
		["1:xx", 0.0, 200.0, -1.0], ["+", 0.0, 200.0, -1.0], ["-1:-2", 0.0, 200.0, -1.0], ["50%", 0.0, 0.0, -1.0], ["+50%", 0.0, 200.0, -1.0],
	]
	var bad := PackedStringArray()
	for entry in cases:
		var got: float = parser.parse(entry[0], entry[1], entry[2])
		if not is_equal_approx(got, entry[3]):
			bad.append("%s -> %s" % [entry[0], got])
	check(bad.is_empty(), "time entry parses clock, unit, relative and percent forms %s" % [bad])
	var messages := []
	var capture := func(message: String, _busy: bool) -> void: messages.append(message)
	main.ui.status_requested.connect(capture)
	main.ui._jump_to_time("not a time")
	main.ui.status_requested.disconnect(capture)
	check(messages.size() == 1 and messages[0].begins_with("Time not understood"), "unreadable jump time is reported")


func _test_clear_recent() -> void:
	var library := root.get_node("Library")
	var ui = main.ui
	library.mark_played("/tmp/vpx-recent-probe.mp4")
	library.set_pref("/tmp/vpx-recent-probe.mp4", "view_count", 3)
	library.set_favorite("/tmp/vpx-recent-probe.mp4", true)
	library.mark_folder_visited("/tmp/vpx-recent-probe-dir")
	check("/tmp/vpx-recent-probe.mp4" in library.recent_paths(100), "played media is listed as recent")
	ui._clear_recent_pressed()
	check(ui.clear_recent_armed and "/tmp/vpx-recent-probe.mp4" in library.recent_paths(100), "first press only arms Clear recent")
	ui._clear_recent_pressed()
	check(not ui.clear_recent_armed and library.recent_paths(100).is_empty() and library.recent_folders(100).is_empty(), "second press clears recent media and folders")
	check(library.is_favorite("/tmp/vpx-recent-probe.mp4") and int(library.get_pref("/tmp/vpx-recent-probe.mp4", "view_count", 0)) == 3, "clearing recent keeps favourites and view counts")
	check(library.get_pref("/tmp/vpx-recent-probe-dir", "is_directory", false), "cleared folders stay known as folders")
	library.forget("/tmp/vpx-recent-probe.mp4")
	library.forget("/tmp/vpx-recent-probe-dir")
	library.favorites.erase("/tmp/vpx-recent-probe.mp4")


func _test_subtitle_delay_keys() -> void:
	var settings := root.get_node("Settings")
	var player = main.player
	var previous: String = player.current_path
	var delay: float = settings.subtitle_delay
	player.current_path = "/media/probe.mp4"
	settings.apply("subtitle_delay", 0.0)
	var press := func(code: Key, shift := false) -> void:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = true
		event.shift_pressed = shift
		main._handle_key(event)
	press.call(KEY_X)
	press.call(KEY_X)
	check(is_equal_approx(settings.subtitle_delay, 0.2), "X delays subtitles by 0.1 s per press (%.2f)" % settings.subtitle_delay)
	press.call(KEY_Z, true)
	check(is_equal_approx(settings.subtitle_delay, -0.3), "Shift+Z brings subtitles 0.5 s earlier (%.2f)" % settings.subtitle_delay)
	settings.apply("subtitle_delay", 29.9)
	press.call(KEY_X, true)
	check(is_equal_approx(settings.subtitle_delay, 30.0), "subtitle delay stops at 30 s")
	settings.apply("subtitle_delay", delay)
	player.current_path = previous
	root.get_node("Library").forget("/media/probe.mp4")


func _test_mouse_back_button() -> void:
	var ui = main.ui
	var child := directory.path_join("side-button")
	DirAccess.make_dir_recursive_absolute(child)
	main.panel.open()
	ui.show_library()
	ui.open_directory(child)
	for i in 30:
		await process_frame
	check(ui.directory.simplify_path() == child.simplify_path(), "test folder is open before the back button")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_XBUTTON1
	press.pressed = true
	check(main.desktop_view.handle_input(press), "mouse back button is consumed")
	for i in 30:
		await process_frame
	check(ui.directory.simplify_path() == directory.simplify_path(), "mouse back button goes up one Library folder (%s)" % ui.directory)
	DirAccess.remove_absolute(child)


func _test_reveal_current() -> void:
	var ui = main.ui
	var player = main.player
	var folder := directory.path_join("reveal")
	DirAccess.make_dir_recursive_absolute(folder)
	for index in 40:
		var file := FileAccess.open(folder.path_join("clip_%02d.mp4" % index), FileAccess.WRITE)
		file.close()
	var wanted := folder.path_join("clip_33.mp4")
	var previous: String = player.current_path
	player.current_path = wanted
	ui.open_directory(directory)
	for i in 30:
		await process_frame
	check(ui.reveal_current(), "now playing can be shown in the Library")
	for i in 90:
		await process_frame
	var focused: Control = ui.get_viewport().gui_get_focus_owner()
	check(ui.directory.simplify_path() == folder.simplify_path(), "show in Library opens the file's folder")
	check(focused != null and focused.has_method("media_path") and focused.media_path() == wanted, "show in Library focuses the playing file")
	check(not player.current_path.contains("://") and not ui.reveal_pending, "reveal finishes")
	player.current_path = "https://example.com/stream.mp4"
	check(not ui.reveal_current(), "streams cannot be shown in the Library")
	player.current_path = previous
	for index in 40:
		DirAccess.remove_absolute(folder.path_join("clip_%02d.mp4" % index))
	DirAccess.remove_absolute(folder)


func _test_cheat_sheet_and_stats() -> void:
	var ui = main.ui
	var sheet: Node = ui.get_node("%CheatSheet")
	var shortcuts := ""
	for child in sheet.get_children():
		if child is Label:
			shortcuts += child.text + "\n"
	check(shortcuts.contains("Jump to a time") and shortcuts.contains("Subtitles earlier") and shortcuts.contains("Show video details"), "cheat sheet lists the new shortcuts")
	check(not ui.stats_text().is_empty(), "video details text is available")


func _test_card_menu() -> void:
	var ui = main.ui
	var library := root.get_node("Library")
	var folder := directory.path_join("card-menu")
	DirAccess.make_dir_recursive_absolute(folder)
	var media := folder.path_join("clip.mp4")
	var file := FileAccess.open(media, FileAccess.WRITE)
	file.close()
	ui.open_directory(folder)
	for i in 40:
		await process_frame
	var card: Button = ui.cards.get(media)
	check(card != null, "test card is built")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.global_position = Vector2(120, 140)
	card.gui_input.emit(click)
	await process_frame
	var labels := []
	for index in ui.card_popup.item_count:
		labels.append(ui.card_popup.get_item_text(index))
	check(ui.card_popup_path == media and "Play" in labels and "Add to favourites" in labels and "Copy path" in labels, "right click opens the card menu %s" % [labels])
	ui._on_card_menu_selected(ui.CARD_MENU_FAVORITE)
	check(library.is_favorite(media), "card menu adds a favourite")
	ui._on_card_menu_selected(ui.CARD_MENU_FAVORITE)
	check(not library.is_favorite(media), "card menu removes a favourite")
	ui._on_card_menu_selected(ui.CARD_MENU_COPY)
	check(DisplayServer.clipboard_get() == media or DisplayServer.get_name() == "headless", "card menu copies the path")
	library.mark_played(media)
	check(library.forget_recent(media) and not (media in library.recent_paths(100)), "card menu can drop an item from Recent")
	ui.card_popup.hide()
	ui.card_popup_path = ""
	ui._focus_control(card)
	var menu_key := InputEventKey.new()
	menu_key.keycode = KEY_F10
	menu_key.shift_pressed = true
	menu_key.pressed = true
	check(ui.handle_key(menu_key) and ui.card_popup_path == media, "Shift+F10 opens the menu for the focused card")
	ui.card_popup.hide()
	library.forget(media)
	DirAccess.remove_absolute(media)
	DirAccess.remove_absolute(folder)


func _test_library_async_save() -> void:
	var library := root.get_node("Library")
	library.save()
	var probes := []
	for index in 4000:
		var key := "/probe/library/Episode %04d.mkv" % index
		library.entries[key] = {"position": 12.5, "duration": 3600.0, "view_count": 2, "played": 1700000000.0 + index, "seen": 1700000000.0, "format": {"projection": 0, "stereo": 0}}
		probes.append(key)
	library._mark_dirty()
	var started := Time.get_ticks_usec()
	var text: String = JSON.stringify({"version": 1, "files": library.entries})
	var serialize_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	library._save_async()
	var handoff_usec := Time.get_ticks_usec() - started
	check(not library.dirty and library.writer != null, "library save hands the write to a worker")
	check(handoff_usec * 2 < serialize_usec, "worker hand-off is much cheaper than serialising on the frame (%d us vs %d us)" % [handoff_usec, serialize_usec])
	library.set_pref("/probe/library/late.mkv", "position", 7.0)
	check(library.dirty, "changes during a write stay dirty")
	check(library.save() == OK and library.writer == null and not library.dirty, "synchronous save joins the worker and flushes late changes")
	var saved: String = FileAccess.get_file_as_string("user://library.json")
	check(saved.contains("Episode 3999.mkv") and saved.contains("late.mkv") and JSON.parse_string(saved) is Dictionary, "saved library file holds every entry and parses")
	for key in probes:
		library.entries.erase(key)
	library.entries.erase("/probe/library/late.mkv")
	library._mark_dirty()
	library.save()
	check(text.length() > 0, "serialised sample is not empty")


func _test_open_picker() -> void:
	var ui = main.ui
	var press := InputEventKey.new()
	press.keycode = KEY_O
	press.ctrl_pressed = true
	press.pressed = true
	main._handle_key(press)
	for i in 5:
		await process_frame
	check(is_instance_valid(ui.open_picker) and ui.open_picker.visible and main.panel.is_open(), "Ctrl+O opens the in-app file picker with the menu")
	main._handle_key(press)
	check(ui.open_picker.get_parent() == ui and ui.get_children().filter(func(child: Node) -> bool: return child == ui.open_picker).size() == 1, "second Ctrl+O reuses the picker")
	var messages := []
	var capture := func(message: String, _busy: bool) -> void: messages.append(message)
	ui.status_requested.connect(capture)
	var subtitle := directory.path_join("probe.srt")
	var file := FileAccess.open(subtitle, FileAccess.WRITE)
	file.close()
	var previous: String = main.player.current_path
	main.player.current_path = ""
	ui.open_picker.file_selected.emit(subtitle)
	await process_frame
	ui.status_requested.disconnect(capture)
	check(messages.size() == 1 and messages[0].begins_with("Play a video"), "picked subtitle goes through the drop path (%s)" % [messages])
	await process_frame
	await process_frame
	check(not is_instance_valid(ui.open_picker), "picker closes after a choice")
	main._handle_key(press)
	for i in 3:
		await process_frame
	ui.close_pickers()
	for i in 3:
		await process_frame
	check(not is_instance_valid(ui.open_picker) or ui.open_picker.is_queued_for_deletion() or not ui.open_picker.visible, "closing pickers cancels the open picker")
	main.player.current_path = previous
	DirAccess.remove_absolute(subtitle)


func _test_recent_shortcut() -> void:
	var ui = main.ui
	var settings := root.get_node("Settings")
	ui.show_library()
	settings.apply("library_source", settings.LibrarySource.FOLDER)
	var press := InputEventKey.new()
	press.keycode = KEY_R
	press.ctrl_pressed = true
	press.pressed = true
	check(main._handle_key(press), "Ctrl+R is handled")
	for i in 5:
		await process_frame
	check(settings.library_source == settings.LibrarySource.RECENT and main.panel.is_open(), "Ctrl+R opens the menu on Recent")
	ui._select_source(settings.LibrarySource.FOLDER)
	for i in 5:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func frames(count := 4) -> void:
	for i in count:
		await process_frame


static func _blocked_worker(_token: RefCounted) -> Dictionary:
	OS.delay_msec(350)
	return {"ok": true, "late": true}


func _wait_picker(picker: Control) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while (is_instance_valid(picker.scan_job) or is_instance_valid(picker.path_job)) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(picker.scan_job) and not is_instance_valid(picker.path_job), "picker operation completes")


func _key(code: Key, pressed := true, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	return event


func _run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: test timeout"); quit(2))
	await _test_background()
	await _test_disc()
	var settings := root.get_node("Settings")
	settings.last_directory = directory
	settings.last_file = ""
	settings.hide_menu_on_play = false
	DirAccess.make_dir_recursive_absolute(directory.path_join("first"))
	DirAccess.make_dir_recursive_absolute(directory.path_join("second"))
	for name in ["first/a.cfg", "first/hidden.txt", "second/b.cfg"]:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		file.store_string("fixture")
		file.close()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	await _test_picker()
	await _test_backup_roundtrip()
	await _test_seek()
	await _test_disc_cancellation()
	_test_scan_errors()
	await _test_library_scale()
	_test_window_title()
	await _test_art_retry()
	await _test_stepper_hold()
	_test_time_entry()
	_test_clear_recent()
	_test_subtitle_delay_keys()
	await _test_mouse_back_button()
	await _test_reveal_current()
	await _test_cheat_sheet_and_stats()
	await _test_card_menu()
	await _test_library_async_save()
	await _test_open_picker()
	await _test_recent_shortcut()
	main.queue_free()
	await create_timer(0.4).timeout
	print("Critical UI regression: %d failures" % failures)
	quit(1 if failures else 0)


func _test_background() -> void:
	var task := BackgroundTask.command("python3", ["-c", "import sys; print('out'); print('err', file=sys.stderr)"], 2.0)
	var result: Dictionary = await task.completed
	check(result["ok"] and result["output"] == "out\n" and result["error"] == "err\n", "process output and exit status survive asynchronous execution")
	task = BackgroundTask.command("python3", ["-c", "raise SystemExit(7)"], 2.0)
	result = await task.completed
	check(not result["ok"] and result["code"] == 7, "failed helper exit status is preserved")
	task = BackgroundTask.command("python3", ["-c", "import time; time.sleep(3)"], 0.1)
	var started := Time.get_ticks_msec()
	result = await task.completed
	check(not result["ok"] and result["error"] == "Operation timed out" and Time.get_ticks_msec() - started < 500, "mount helpers time out without blocking frames")
	task = BackgroundTask.command("python3", ["-c", "import time; time.sleep(3)"], 5.0)
	var pid: int = task.process["pid"]
	task.cancel()
	result = await task.completed
	check(result.get("cancelled", false), "cancelling terminates a running mount helper")
	if OS.get_name() == "Linux":
		check(not DirAccess.dir_exists_absolute("/proc/%d" % pid), "cancelled helper process is reaped")
	task = BackgroundTask.start(_blocked_worker)
	var replies: Array[Dictionary] = []
	task.completed.connect(func(value: Dictionary) -> void: replies.append(value))
	started = Time.get_ticks_msec()
	task.cancel()
	result = await task.completed
	check(result.get("cancelled", false) and Time.get_ticks_msec() - started < 100, "blocked filesystem worker cancels immediately")
	await create_timer(0.4).timeout
	check(replies.size() == 1 and not is_instance_valid(task), "late worker result is discarded and task is reaped")


func _test_disc() -> void:
	if OS.get_name() != "Linux":
		return
	var disc := TestDisc.new()
	root.add_child(disc)
	var result := await disc.mount("test.iso")
	check(result.get("path") == "/tmp/vpx-disc-test" and disc.commands.size() == 2, "ISO mount stages await helpers and preserve mounted path")
	disc.queue_free()
	disc = TestDisc.new()
	disc.slow = true
	root.add_child(disc)
	var replies: Array[Dictionary] = []
	_capture_mount(disc, replies)
	await frames()
	var started := Time.get_ticks_msec()
	disc.cancel()
	await frames()
	check(replies.size() == 1 and replies[0].get("cancelled", false) and Time.get_ticks_msec() - started < 100, "ISO cancellation propagates through the mount operation")
	disc.queue_free()


func _capture_mount(disc: DiscImage, replies: Array[Dictionary]) -> void:
	replies.append(await disc.mount("test.iso"))


func _test_picker() -> void:
	var ui: Control = main.ui
	ui.show_page(ui.pages.get_node("System"))
	var picker = load("res://scripts/quick_panel.gd").SubtitleFilePicker.new()
	ui.add_child(picker)
	picker.configure(directory.path_join("first"), ["*.cfg"], "Import settings", "Import")
	ui.backup_picker = picker
	await _wait_picker(picker)
	check(picker.listed_files == PackedStringArray(["a.cfg"]), "file picker filters asynchronous directory results")
	picker.current_directory = directory.path_join("first")
	picker._refresh()
	picker.current_directory = directory.path_join("second")
	picker._refresh()
	await _wait_picker(picker)
	check(picker.listed_files == PackedStringArray(["b.cfg"]), "new folder wins over cancelled scans")
	picker.filename_field.grab_focus()
	check(main._handle_key(_key(KEY_TAB, true, true)), "modal consumes Ctrl+Tab")
	check(ui.pages.get_node("System").visible, "modal shortcut does not change menu page")
	var trapped := true
	for i in 24:
		main._handle_key(_key(KEY_TAB))
		main._handle_key(_key(KEY_TAB, false))
		trapped = trapped and picker.is_ancestor_of(ui.get_viewport().gui_get_focus_owner())
	check(trapped, "Tab stays inside settings picker through two full focus cycles")
	ui.get_viewport().gui_get_focus_owner().release_focus()
	var shuffle: bool = root.get_node("Settings").shuffle
	main._handle_key(_key(KEY_S))
	check(root.get_node("Settings").shuffle == shuffle, "picker without focus blocks playback shortcuts")
	main._handle_key(_key(KEY_ESCAPE))
	check(not picker.visible and main.panel.is_open(), "one Escape closes settings picker without closing menu")
	picker.queue_free()
	await frames()
	picker = load("res://scripts/quick_panel.gd").SubtitleFilePicker.new()
	ui.add_child(picker)
	picker.configure(directory.path_join("first"), ["*.cfg"], "Export settings", "Save", true)
	ui.backup_picker = picker
	await _wait_picker(picker)
	var selected: Array[String] = []
	picker.file_selected.connect(func(path: String) -> void: selected.append(path))
	picker.filename_field.text = "a.cfg"
	picker._accept_selection()
	await _wait_picker(picker)
	check(selected.is_empty() and picker.status_label.text.contains("Save again"), "existing export requires overwrite confirmation")
	picker._accept_selection()
	await _wait_picker(picker)
	check(selected == [directory.path_join("first/a.cfg")], "confirmed export selects the intended path")
	picker.queue_free()
	await frames()
	picker = load("res://scripts/quick_panel.gd").SubtitleFilePicker.new()
	ui.add_child(picker)
	picker.configure(directory, ["*.cfg"])
	await _wait_picker(picker)
	picker.scan_job = BackgroundTask.start(_blocked_worker)
	var worker: Node = picker.scan_job
	var started := Time.get_ticks_msec()
	picker.cancel()
	picker.queue_free()
	await frames()
	check(Time.get_ticks_msec() - started < 100 and not is_instance_valid(picker), "closing picker never joins blocked scan")
	await create_timer(0.4).timeout
	check(not is_instance_valid(worker), "closed picker leaves no completed worker behind")


func _test_backup_roundtrip() -> void:
	DirAccess.remove_absolute(directory.path_join("roundtrip.cfg"))
	var ui: Control = main.ui
	ui.show_page(ui.pages.get_node("System"))
	var buttons := {}
	for node: Button in ui.find_children("*", "Button", true, false):
		if node.text in ["Export settings", "Import settings"]:
			buttons[node.text] = node
	var settings := root.get_node("Settings")
	settings.apply("volume", 37)
	buttons["Export settings"].pressed.emit()
	var picker: Control = ui.backup_picker
	picker._open_path(directory)
	picker.filename_field.text = "roundtrip.cfg"
	picker._accept_selection()
	await _wait_backup_closed()
	check(FileAccess.file_exists(directory.path_join("roundtrip.cfg")), "export waits for pending navigation and writes to the intended folder")
	settings.apply("volume", 61)
	buttons["Import settings"].pressed.emit()
	picker = ui.backup_picker
	picker._open_path(directory)
	picker.filename_field.text = "roundtrip.cfg"
	picker._accept_selection()
	await _wait_backup_closed()
	check(settings.volume == 37, "settings import restores the exported values through the asynchronous picker")


func _wait_backup_closed() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(main.ui.backup_picker) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(main.ui.backup_picker), "settings operation closes its picker")


func _test_seek() -> void:
	var clip := directory.path_join("seek.mp4")
	var output: Array = []
	var generated := OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=64x64:r=24", "-t", "12", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", clip], output, true)
	check(generated == 0, "seek fixture generated")
	var player = main.player
	check(await player.open(clip, {"paused": true}), "seek fixture opens")
	var ui: Control = main.ui
	ui.show_library()
	main.panel.open()
	await frames()
	ui.seek_slider.grab_focus()
	ui.handle_key(_key(KEY_RIGHT))
	ui.handle_key(_key(KEY_RIGHT, false))
	await frames()
	check(player.stream_position > 0.0 and is_equal_approx(ui.seek_slider.value, player.stream_position), "keyboard seek commits and survives transport refresh")
	var log_node := root.get_node("Log")
	var seek_serial: int = log_node.seek_serial
	root.get_node("Library").set_pref(clip, "bookmarks", [0.0, 4.37, 12.0])
	player.rename_bookmark(4.37, "Opening Ελληνικά")
	await frames()
	var controller = main.get_node("Origin/Right")
	controller.target_viewport = ui.get_viewport()
	controller.hit_panel = main.panel
	ui.get_viewport().notify_mouse_entered()
	var pin := Vector2(ui.marks._x(4.37), ui.marks.size.y * 0.5 - 9.0)
	var uv: Vector2 = (ui.marks.global_position + pin) / Vector2(ui.get_viewport().size_2d_override)
	controller._push_motion(uv)
	await frames()
	check(ui.seek_bubble.visible and "Opening Ελληνικά" in ui.bubble_label.text and is_equal_approx(ui.preview_time, 4.37), "pin hover shows Unicode name at exact bookmark time")
	controller.trigger_held = true
	controller._push_button(uv, true)
	controller.trigger_held = false
	controller._push_button(uv, false)
	await frames()
	check(log_node.seek_serial == seek_serial + 1 and is_equal_approx(player.stream_position, 4.37) and not ui.seeking, "pin click seeks once to exact timestamp without slider drag")
	controller._push_motion(Vector2(0.1, 0.1))
	await frames()
	check(not ui.seek_bubble.visible, "leaving pin hides hover bubble")
	check(not ui.marks._has_point(Vector2(pin.x, ui.marks.size.y * 0.5)), "timeline track remains available for normal scrubbing")
	check(ui.marks.bookmark_at(Vector2(ui.marks._x(0.0), pin.y)) == 0.0 and ui.marks.bookmark_at(Vector2(ui.marks._x(12.0), pin.y)) == 12.0, "first and last pins remain clickable")
	seek_serial = log_node.seek_serial
	ui.seek_slider.value = 3.0
	ui.seek_slider.drag_started.emit()
	await frames()
	check(log_node.seek_serial == seek_serial, "pointer press cannot commit before drag begins")
	ui.seek_slider.value = 5.0
	ui.seek_slider.drag_ended.emit(true)
	await frames()
	check(log_node.seek_serial == seek_serial + 1 and is_equal_approx(player.stream_position, 5.0), "drag release commits exactly one seek")
	seek_serial = log_node.seek_serial
	ui.seek_slider.value = 8.0
	player.open_serial += 1
	await frames()
	check(log_node.seek_serial == seek_serial, "pending keyboard seek cannot affect replacement media")


func _test_disc_cancellation() -> void:
	var path := directory.path_join("cancel.iso")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	file.close()
	var ui: Control = main.ui
	ui.open_media(path)
	check(is_instance_valid(ui.disc_job), "opening ISO creates a cancellable operation")
	ui.recovery.cancel()
	await frames(12)
	check(not is_instance_valid(ui.disc_job) and ui.recovery.status == "cancelled" and not ui.recovery.visible, "cancelled ISO inspection cannot reopen recovery or show stale results")
	check(main.player.current_path != path, "cancelled ISO cannot replace current playback")
