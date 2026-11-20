extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames(count := 8) -> void:
	for i in count:
		await process_frame


func run() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.resume_playback = false
	settings.auto_crop = false
	var photo := ProjectSettings.globalize_path("user://loading-photo.exr")
	var image := Image.create_empty(1024, 512, false, Image.FORMAT_RGBH)
	image.fill(Color(0.4, 0.5, 0.6))
	image.save_exr(photo)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	check(await main.player.open(photo), "photo opens")
	main.panel.close()
	await frames(30)
	check(not main.panel.is_open(), "menu closed while viewing")

	var watch := await _slow_load(main, "/photos/next.exr")
	check(not watch["menu_opened"], "menu stays closed while the next photo loads")
	check(not watch["card_shown"], "loading card stays hidden")
	check(watch["osd_loading"], "loading status shows on the OSD")
	_emit(main, "/photos/next.exr", "ready")
	await frames()
	check(not _osd_loading(main), "loading status clears when the photo is shown")
	check(not main.panel.is_open(), "menu still closed after the photo is shown")

	await _slow_load(main, "/photos/broken.exr")
	main.player.load_changed.emit({"path": "/photos/broken.exr", "status": "failed", "message": "Could not open this image.", "kind": "image"})
	await frames()
	check(main.panel.is_open() and main.ui.recovery.visible, "a failed photo still opens the menu with the error")
	check(not _osd_loading(main), "loading status clears on failure")
	main.ui.recovery.hide()

	main.panel.close()
	await frames(30)
	watch = await _slow_load(main, "/videos/clip.mp4")
	check(watch["menu_opened"] and watch["card_shown"], "videos keep the loading card")
	_emit(main, "/videos/clip.mp4", "cancelled")
	await frames()

	main.panel.open()
	await frames(30)
	watch = await _slow_load(main, "/photos/from-menu.exr")
	check(watch["card_shown"] and not watch["osd_loading"], "with the menu open the loading card shows")
	_emit(main, "/photos/from-menu.exr", "cancelled")
	await frames()
	main.queue_free()
	await frames()
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func _emit(main: Node, path: String, status: String) -> void:
	main.player.load_changed.emit({"path": path, "status": status, "stage": "Decoding image…", "options": {}})


func _osd_loading(main: Node) -> bool:
	return main.osd.visible and main.osd.sticky and main.osd.title_label.text == main.IMAGE_LOADING_STATUS


func _slow_load(main: Node, path: String) -> Dictionary:
	var was_open: bool = main.panel.is_open()
	var result := {"menu_opened": false, "card_shown": false, "osd_loading": false}
	_emit(main, path, "opening")
	var deadline := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < deadline:
		await process_frame
		result["menu_opened"] = result["menu_opened"] or (main.panel.is_open() and not was_open)
		result["card_shown"] = result["card_shown"] or main.ui.recovery.visible
		result["osd_loading"] = result["osd_loading"] or _osd_loading(main)
	return result
