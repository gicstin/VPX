extends SceneTree

var failures := 0


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
	while (ui.scan_started_msec >= 0 or is_instance_valid(ui.paths_job)) and Time.get_ticks_msec() < deadline:
		await process_frame
	for frame in 5:
		await process_frame
	check(ui.scan_started_msec < 0, "scan completes")


func rebuild_tabs(ui: Control) -> void:
	ui.library_tabs.free()
	ui.library_tabs = load("res://scripts/library_tabs.gd").new()
	ui.get_node("%Library").add_child(ui.library_tabs)
	ui.get_node("%Library").move_child(ui.library_tabs, 0)
	ui.library_tabs.setup(ui)
	ui.library_tabs.restore()
	await process_frame


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(30).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	var base := ProjectSettings.globalize_path("user://library-tabs")
	var first := base.path_join("first")
	var second := base.path_join("second")
	DirAccess.make_dir_recursive_absolute(first)
	DirAccess.make_dir_recursive_absolute(second)
	for i in 80:
		DirAccess.make_dir_recursive_absolute(first.path_join("folder-%03d" % i))
	DirAccess.make_dir_recursive_absolute(second.path_join("unique"))
	var restore_only := "--restore-session" in OS.get_cmdline_user_args()
	if not restore_only:
		settings.last_directory = first
		settings.last_file = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.ui
	var tabs = ui.library_tabs
	await settled(ui)
	if restore_only:
		check(tabs.views.size() == 2 and tabs.active == 1 and ui.directory == second, "new process restores open tabs and selection")
		check(settings.library_query == "unique" and settings.library_view == settings.LibraryView.LIST and settings.library_sort == settings.LibrarySort.DATE and settings.library_filter == settings.LibraryFilter.PHOTOS and settings.library_flat_view and settings.library_favorites_only, "new process restores search, view and filters")
		tabs.select(0)
		await settled(ui)
		check(ui.directory == first and ui.file_scroll.scroll_vertical > 0 and settings.library_query == "", "new process restores background folder and scroll")
		quit(1 if failures else 0)
		return
	check(tabs.views.size() == 1 and tabs.bar.get_tab_title(0) == "first", "initial tab names current folder")
	tabs.new_tab()
	ui._set_query("folder-000")
	await settled(ui)
	tabs.select(0)
	await settled(ui)
	check(settings.library_query == "" and not ui.query_chip.visible, "same-folder tabs restore search controls")
	tabs.close(1)
	ui.file_scroll.scroll_vertical = 250
	await process_frame
	var scroll: int = ui.file_scroll.scroll_vertical
	check(scroll > 0, "first folder scrolls")
	tabs.new_tab()
	ui.open_directory(second)
	await settled(ui)
	settings.library_view = settings.LibraryView.LIST
	settings.library_sort = settings.LibrarySort.DATE
	settings.library_filter = settings.LibraryFilter.PHOTOS
	settings.library_flat_view = true
	settings.library_favorites_only = true
	ui._set_query("unique")
	await settled(ui)
	check(tabs.views.size() == 2 and tabs.bar.get_tab_title(1) == "second", "new tab navigates independently")
	tabs.select(0)
	await settled(ui)
	check(ui.directory == first and settings.library_query == "" and settings.library_view == settings.LibraryView.GRID, "switch restores folder, query and view mode")
	check(settings.library_sort == settings.LibrarySort.NAME and settings.library_filter == settings.LibraryFilter.ALL and not settings.library_flat_view and not settings.library_favorites_only, "first tab keeps sort and filters")
	check(ui.file_scroll.scroll_vertical == scroll, "switch restores scroll position")
	check(ui.folder_grid.items.size() == 80, "first folder listing restored")
	tabs.select(1)
	await settled(ui)
	check(ui.directory == second and settings.library_query == "unique" and settings.library_view == settings.LibraryView.LIST, "second tab keeps its own query and view")
	check(settings.library_sort == settings.LibrarySort.DATE and settings.library_filter == settings.LibraryFilter.PHOTOS and settings.library_flat_view and settings.library_favorites_only, "second tab keeps sort and filters")
	check(settings.flush() == OK, "tab session saves to disk")
	if "--save-session" in OS.get_cmdline_user_args():
		quit(1 if failures else 0)
		return
	settings.library_tab_session = {}
	settings.load_config()
	await rebuild_tabs(ui)
	tabs = ui.library_tabs
	await settled(ui)
	check(tabs.views.size() == 2 and tabs.active == 1 and tabs.bar.current_tab == 1, "restart restores tab order and active tab")
	check(ui.directory == second and settings.library_query == "unique" and settings.library_view == settings.LibraryView.LIST, "restart restores active folder, search and view")
	check(settings.library_sort == settings.LibrarySort.DATE and settings.library_filter == settings.LibraryFilter.PHOTOS and settings.library_flat_view and settings.library_favorites_only, "restart restores active filters")
	tabs.select(0)
	await settled(ui)
	check(ui.directory == first and settings.library_query == "" and settings.library_view == settings.LibraryView.GRID, "restart preserves background tab state")
	check(ui.file_scroll.scroll_vertical == scroll, "restart restores background tab scroll")
	check(settings.flush() == OK, "active scroll saves to disk")
	settings.library_tab_session = {}
	settings.load_config()
	await rebuild_tabs(ui)
	tabs = ui.library_tabs
	await settled(ui)
	check(tabs.active == 0 and ui.file_scroll.scroll_vertical == scroll, "restart restores active tab scroll after scan")
	tabs.select(1)
	await settled(ui)
	tabs.new_tab()
	ui.open_directory(first)
	tabs.select(1)
	await settled(ui)
	check(ui.directory == second and tabs.bar.current_tab == 1, "switch cancels previous folder scan")
	tabs.close(0)
	check(tabs.active == 0 and ui.directory == second, "closing background tab preserves active folder")
	tabs.close(0)
	await settled(ui)
	check(tabs.views.size() == 1 and ui.directory == first, "closing active tab selects remaining folder")
	tabs.close(0)
	check(tabs.views.size() == 1, "last tab remains available")
	ui.show_library()
	var key := InputEventKey.new()
	key.pressed = true
	key.ctrl_pressed = true
	key.keycode = KEY_T
	check(ui.handle_key(key) and tabs.views.size() == 2, "Ctrl+T opens tab")
	key.keycode = KEY_TAB
	check(ui.handle_key(key) and tabs.active == 0, "Ctrl+Tab cycles tabs")
	key.shift_pressed = true
	check(ui.handle_key(key) and tabs.active == 1, "Ctrl+Shift+Tab cycles backwards")
	key.keycode = KEY_W
	check(ui.handle_key(key) and tabs.views.size() == 1, "Ctrl+W closes tab")
	await settled(ui)
	check(settings.flush() == OK, "closed tab session saves")
	settings.library_tab_session = {}
	settings.load_config()
	check(settings.library_tab_session["views"].size() == 1, "closed tabs stay closed on disk")
	settings.library_tab_session = {"views": [null, {}, {"library_source": 900}], "active": -99}
	await rebuild_tabs(ui)
	await settled(ui)
	check(main.ui.library_tabs.views.size() == 1, "invalid saved tabs fall back to one usable tab")
	main.queue_free()
	await process_frame
	print("RESULT: library tabs failures=%d" % failures)
	quit(1 if failures else 0)
