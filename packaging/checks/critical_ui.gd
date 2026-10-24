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
