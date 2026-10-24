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


func opened(ui: Control, path: String) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while (ui.player.current_path != path or ui.opening_media()) and Time.get_ticks_msec() < deadline:
		await process_frame
	for frame in 3:
		await process_frame


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(60).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	var fixture := ProjectSettings.globalize_path("user://card-play")
	DirAccess.make_dir_recursive_absolute(fixture)
	var first := fixture.path_join("first.mp4")
	var second := fixture.path_join("second.mp4")
	for video in [first, second]:
		check(OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=160x90:r=10:d=12", "-c:v", "mpeg4", video]) == 0, "fixture generated")
	settings.last_directory = fixture
	settings.last_file = ""
	settings.hide_menu_on_play = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.ui
	await settled(ui)
	var card: Control = ui.cards.get(first)
	check(card != null, "card built")
	if card == null:
		quit(1)
		return
	ui.open_media(second, {"paused": true})
	await opened(ui, second)
	check(ui.player.paused, "player starts paused")
	main.panel.open()
	card.play_requested.emit(first, false)
	await opened(ui, first)
	check(ui.player.current_path == first and not ui.player.paused, "play request opens and resumes")
	ui.player.toggle_pause()
	main.panel.open()
	await process_frame
	check(card.playing_badge != null and card.playing_badge.visible and card.playing_badge.mouse_filter == Control.MOUSE_FILTER_STOP, "play badge clickable")
	var badge_pressed := [false]
	card.play_requested.connect(func(_path: String, _dir: bool) -> void: badge_pressed[0] = true, CONNECT_ONE_SHOT)
	card._on_badge_input(_press())
	check(badge_pressed[0] and not ui.player.paused, "badge click resumes current item")
	ui.player.toggle_pause()
	var activations := [0]
	card.activated.connect(func(_path: String, _dir: bool) -> void: activations[0] += 1)
	var double := _press()
	double.double_click = true
	card._on_gui_input(double)
	check(not ui.player.paused, "double click resumes")
	check(activations[0] == 0, "double click does not reopen")
	main.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _press() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event
