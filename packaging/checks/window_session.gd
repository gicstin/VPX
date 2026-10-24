extends SceneTree

var Session: GDScript

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	Session = load("res://scripts/window_session.gd")
	var usable := Rect2i(0, 32, 1920, 1048)
	check(Session.fit_bounds(Rect2i(100, 100, 900, 550), usable) == Rect2i(100, 100, 900, 550), "valid normal bounds remain unchanged")
	check(Session.fit_bounds(Rect2i(5000, -5000, 4000, 3000), usable) == usable, "oversized offscreen window fits usable desktop")
	check(Session.fit_bounds(Rect2i(-100, 10, 1, 1), usable) == Rect2i(0, 32, 640, 360), "tiny window respects minimum size and taskbar")
	check(Session.fit_bounds(Rect2i(0, 0, 1000, 1000), Rect2i(-800, -600, 500, 300)) == Rect2i(-800, -600, 500, 300), "small screens and negative monitor coordinates remain usable")
	var screens: Array[Rect2i] = [usable, Rect2i(1920, 0, 2560, 1440)]
	check(Session.select_screen(screens[1], Rect2i(100, 100, 900, 550), screens, 0) == 1, "saved monitor wins over normal bounds on another screen")
	check(Session.select_screen(Rect2i(5000, 0, 1920, 1080), Rect2i(5100, 100, 900, 550), screens, 0) == 0, "removed monitor falls back to current screen")
	check(Session.select_screen(Rect2i(), Rect2i(2000, 100, 900, 550), screens, 0) == 1, "changed display layout finds monitor containing saved bounds")
	for mode in [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		check(Session.restored_mode(mode) == mode, "visible window mode %d survives validation" % mode)
	for mode in [DisplayServer.WINDOW_MODE_MINIMIZED, -1, 99, "fullscreen", null]:
		check(Session.restored_mode(mode) == DisplayServer.WINDOW_MODE_WINDOWED, "minimized or invalid mode reopens windowed: %s" % str(mode))
	var settings := root.get_node("Settings")
	if DisplayServer.get_name() == "headless":
		settings.window_session = {"bounds": Rect2i(100, 100, 900, 550), "screen": usable, "mode": DisplayServer.WINDOW_MODE_FULLSCREEN}
		settings.save_config()
		check(settings.flush() == OK, "window state saves atomically")
		settings.window_session = {}
		settings.load_config()
		check(settings.window_session.get("mode") == DisplayServer.WINDOW_MODE_FULLSCREEN and settings.window_session.get("bounds") == Rect2i(100, 100, 900, 550), "window mode and normal bounds survive settings reload")
		var session = Session.new()
		root.add_child(session)
		check(not session.active, "headless runs leave window state untouched")
		quit(1 if failures else 0)
		return
	var arguments := OS.get_cmdline_user_args()
	var restore_only := "--restore-window" in arguments
	var expected_mode := DisplayServer.WINDOW_MODE_WINDOWED
	if "--maximized" in arguments:
		expected_mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	elif "--fullscreen" in arguments:
		expected_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	var saved: Dictionary = settings.window_session.duplicate(true)
	var session = Session.new()
	root.add_child(session)
	await create_timer(0.8).timeout
	check(session.active, "native window restore activates")
	if restore_only:
		check(DisplayServer.window_get_mode() == expected_mode, "new process restores requested native window mode")
		check(session.state["bounds"] == saved.get("bounds"), "new process preserves normal bounds independently of window mode")
		if expected_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			check(DisplayServer.window_get_size() == saved["bounds"].size and DisplayServer.window_get_position() == saved["bounds"].position, "new process restores native window size and position")
		else:
			if expected_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				session.toggle_fullscreen()
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			await create_timer(0.5).timeout
			check(DisplayServer.window_get_size() == saved["bounds"].size, "leaving restored fullscreen or maximized mode returns to normal size")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await create_timer(0.4).timeout
		var screen := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_size(Vector2i(900, 550).min(screen.size))
		DisplayServer.window_set_position(screen.position + Vector2i(80, 80))
		await create_timer(1.0).timeout
		var normal: Rect2i = session.state["bounds"]
		check(normal.size == DisplayServer.window_get_size(), "resize polling captures normal window bounds")
		if expected_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			session.toggle_fullscreen()
		else:
			DisplayServer.window_set_mode(expected_mode)
		await create_timer(0.8).timeout
		check(settings.window_session.get("mode") == expected_mode, "native mode change persists while running")
		check(settings.window_session.get("bounds") == normal, "fullscreen and maximize preserve normal bounds")
		if "--minimized" in arguments:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
			await create_timer(0.4).timeout
			check(settings.window_session.get("mode") == expected_mode, "minimizing preserves previous visible mode")
		session.capture()
		settings.flush()
	session.free()
	quit(1 if failures else 0)
