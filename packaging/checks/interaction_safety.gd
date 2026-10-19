extends SceneTree

var failures := 0
var checks := 0
var main: Node
var directory := ProjectSettings.globalize_path("user://interaction-safety")


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func frames(count := 5) -> void:
	for i in count:
		await process_frame


func until(predicate: Callable, seconds := 2.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()


func _run() -> void:
	create_timer(25).timeout.connect(func() -> void: printerr("FAIL: timeout"); quit(2))
	DirAccess.make_dir_recursive_absolute(directory.path_join("healthy"))
	DirAccess.make_dir_recursive_absolute(directory.path_join("slow"))
	var output: Array = []
	check(OS.execute("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "color=s=64x64:r=10", "-t", "1", "-c:v", "mpeg4", "-y", directory.path_join("healthy/movie.mp4")], output, true) == 0, "media fixture is generated")
	await _network()
	await _scans()
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.last_directory = directory
	settings.hide_menu_on_play = false
	settings.auto_crop = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	main.get_node("Origin/Left").set_process(false)
	main.get_node("Origin/Right").set_process(false)
	await _pointer()
	await _seek_replacement()
	await _library()
	main.queue_free()
	await create_timer(0.65).timeout
	print("RESULT: interaction_safety checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _network() -> void:
	var network = load("res://packaging/checks/interaction_network.gd").new()
	root.add_child(network)
	var mounted: Array[String] = []
	var failed: Array[String] = []
	network.mounted.connect(func(url: String, path: String) -> void: mounted.append(url + " " + path))
	network.mount_failed.connect(func(_url: String, message: String) -> void: failed.append(message))
	network.mount("smb://slow/first")
	await frames()
	var pid: int = network.pids.back()
	network.cancel_mount()
	check(not network.is_mounting(), "Cancel immediately releases the network attempt")
	if OS.get_name() == "Linux":
		check(not DirAccess.dir_exists_absolute("/proc/%d" % pid), "Cancel kills and reaps the share helper")
	var started := Time.get_ticks_msec()
	network.mount("smb://healthy/second")
	check(await until(func() -> bool: return mounted.size() == 1), "replacement share connects")
	check(Time.get_ticks_msec() - started < 500 and mounted == ["smb://healthy/second /tmp"], "replacement bypasses cancelled work and publishes only its own result")
	check(network.mounted_is_directory, "share result carries directory metadata without another UI-thread stat")
	network.mount("smb://slow/third")
	await frames()
	pid = network.pids.back()
	network.mount("smb://healthy/fourth")
	check(await until(func() -> bool: return mounted.size() == 2), "starting a new share automatically cancels its predecessor")
	if OS.get_name() == "Linux":
		check(not DirAccess.dir_exists_absolute("/proc/%d" % pid), "replacement kills the old helper")
	network.kio = false
	network.mount("webdav://healthy/folder")
	check(await until(func() -> bool: return mounted.size() == 3), "GIO fallback mounts and resolves its local path")
	check(network.helpers.has("gio mount") and network.helpers.has("gio info"), "GIO stages both use asynchronous helpers")
	network.timeout = true
	started = Time.get_ticks_msec()
	network.mount("webdav://slow/folder")
	check(await until(func() -> bool: return failed.size() == 1), "hung GIO helper reports failure")
	check(failed == ["Operation timed out"] and Time.get_ticks_msec() - started < 500 and not network.is_mounting(), "GIO timeout releases the connection without stale success")
	network.timeout = false
	network.mount("smb://slow/shutdown")
	await frames()
	pid = network.pids.back()
	network.queue_free()
	await frames()
	if OS.get_name() == "Linux":
		check(not DirAccess.dir_exists_absolute("/proc/%d" % pid), "closing network owner terminates its helper")


func _scans() -> void:
	var scanner = load("res://packaging/checks/interaction_scanner.gd").new(["mp4"])
	root.add_child(scanner)
	var results: Array[Dictionary] = []
	scanner.finished.connect(func(result: Dictionary) -> void: results.append(result))
	scanner.folder(directory.path_join("slow"), 0, PackedStringArray())
	await frames()
	var started := Time.get_ticks_msec()
	scanner.folder(directory.path_join("healthy"), 0, PackedStringArray())
	check(await until(func() -> bool: return results.any(func(r: Dictionary) -> bool: return r.get("done", false))), "healthy folder replaces a stalled scan")
	check(Time.get_ticks_msec() - started < 400, "new folder scan does not wait for abandoned filesystem work")
	await create_timer(0.55).timeout
	check(results.all(func(r: Dictionary) -> bool: return r["path"].ends_with("/healthy")), "late folder results cannot replace the current listing")
	scanner.folder(directory.path_join("slow"), 0, PackedStringArray())
	await frames()
	started = Time.get_ticks_msec()
	scanner.queue_free()
	await frames()
	check(Time.get_ticks_msec() - started < 100, "scanner shutdown never joins stalled filesystem work")


func _pointer() -> void:
	var controller = main.get_node("Origin/Right")
	var first := SubViewport.new()
	first.size = Vector2i(600, 200)
	root.add_child(first)
	var second := SubViewport.new()
	second.size = Vector2i(600, 200)
	root.add_child(second)
	var slider := HSlider.new()
	slider.position = Vector2(50, 50)
	slider.size = Vector2(400, 40)
	first.add_child(slider)
	var ended: Array[bool] = []
	slider.drag_ended.connect(func(changed: bool) -> void: ended.append(changed))
	await frames()
	controller.target_viewport = first
	controller.hit_panel = null
	var uv := slider.get_global_rect().get_center() / Vector2(first.size)
	controller.trigger_held = true
	controller._push_motion(uv)
	controller._push_button(uv, true)
	check(controller.pressed_viewport == first, "VR press captures its originating viewport")
	controller._retarget({"viewport": second, "panel": null})
	check(controller.target_viewport == first, "crossing panels preserves pointer capture")
	controller._push_motion(Vector2(-1, -1))
	controller.trigger_held = false
	controller._push_button(Vector2(-1, -1), false)
	check(ended.size() == 1 and controller.pressed_viewport == null, "release outside every panel ends the slider drag exactly once")
	controller.target_viewport = first
	controller.trigger_held = true
	controller._push_motion(uv)
	controller._push_button(uv, true)
	controller.active = false
	check(ended.size() == 2 and not controller.trigger_held, "tracking or panel loss cancels the captured drag")
	controller.active = true
	controller.target_viewport = main.ui.get_viewport()
	first.queue_free()
	second.queue_free()
	await frames()


func _seek_replacement() -> void:
	var player = main.player
	var ui = main.ui
	var controller = main.get_node("Origin/Right")
	var path := directory.path_join("healthy/movie.mp4")
	check(await player.open(path, {"paused": true}), "seek fixture opens")
	main.panel.open()
	await frames()
	controller.target_viewport = ui.get_viewport()
	controller.hit_panel = main.panel
	var uv: Vector2 = ui.seek_slider.get_global_rect().get_center() / Vector2(ui.get_viewport().size_2d_override)
	controller.trigger_held = true
	controller._push_motion(uv)
	controller._push_button(uv, true)
	check(ui.seeking, "real timeline begins a captured VR drag")
	check(await player.open(path, {"paused": true}), "media can be replaced during a timeline drag")
	var log_node := root.get_node("Log")
	var serial: int = log_node.seek_serial
	controller.trigger_held = false
	controller._push_button(Vector2(-1, -1), false)
	await frames()
	check(not ui.seeking and log_node.seek_serial == serial, "release from old media cannot seek its replacement")


func _library() -> void:
	var ui = main.ui
	var library := root.get_node("Library")
	var missing := directory.path_join("unavailable.mp4")
	library.set_favorite(missing, true)
	library.set_favorite(directory.path_join("healthy"), true)
	library.set_pref(directory.path_join("healthy"), "is_directory", true)
	library.mark_played(missing)
	library.mark_folder_visited(directory.path_join("healthy"))
	ui._select_source(root.get_node("Settings").LibrarySource.FAVORITES)
	check(missing in ui.media_grid.items and directory.path_join("healthy") in ui.folder_grid.items, "favourites appear immediately from saved metadata")
	check(await until(func() -> bool: return not is_instance_valid(ui.paths_job)), "favourite availability checks complete asynchronously")
	check(missing in ui.media_grid.items and ui.item_meta[missing]["context"].begins_with("Unavailable"), "missing favourites remain visible and are labelled unavailable")
	ui._select_source(root.get_node("Settings").LibrarySource.RECENT)
	check(missing in ui.media_grid.items, "unavailable recent media remains reachable for playback recovery")
	ui._select_source(root.get_node("Settings").LibrarySource.PLACES)
	check(await until(func() -> bool: return not is_instance_valid(ui.paths_job)), "Places discovery finishes in background")
	ui._start_paths_job(_delayed_paths)
	ui.open_directory(directory.path_join("healthy"))
	check(await until(func() -> bool: return not ui.scanner.scanning), "folder navigation finishes asynchronously")
	await create_timer(0.35).timeout
	check(ui.saved_path_info.get("stale") == null, "cancelled availability checks cannot overwrite newer navigation")
	check(ui.directory == directory.path_join("healthy") and ui.listing == PackedStringArray([directory.path_join("healthy/movie.mp4")]), "folder navigation preserves the requested listing")
	ui.open_directory(directory.path_join("missing-folder"))
	check(await until(func() -> bool: return not ui.scanner.scanning), "missing-folder navigation completes")
	check(ui.directory.ends_with("/missing-folder") and ui.listing.is_empty(), "missing navigation reports failure without silently opening an unrelated fallback")


static func _delayed_paths(_token: RefCounted) -> Dictionary:
	OS.delay_msec(300)
	return {"ok": true, "paths": {"stale": {"available": true}}}
