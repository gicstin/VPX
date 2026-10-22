extends SceneTree

var checks := 0
var failures := 0
var measurements := {}
var main: Node
var references: GDScript


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func measure(name: String, action: Callable, iterations := 1000) -> void:
	action.call()
	var samples: Array[float] = []
	for sample in 9:
		var started := Time.get_ticks_usec()
		for i in iterations:
			action.call()
		samples.append(float(Time.get_ticks_usec() - started) / iterations)
	samples.sort()
	measurements[name] = {"median_usec": samples[4], "samples_usec": samples}
	print("BENCH %s median=%.4f us" % [name, samples[4]])


func _run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: runtime performance timeout"); quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.last_directory = ""
	settings.prefer_desktop = true
	settings.music_visualizer = false
	settings.immersive_music_visualizer = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	references = load("res://packaging/checks/runtime_references.gd")
	_panels()
	_smoothing()
	_search()
	await _cleanup()
	_screen()
	await _video()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	check(file != null, "runtime benchmark report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	main.free()
	print("RESULT: runtime_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _panels() -> void:
	var actual: Node = references.TrackedPanel.new()
	var expected: Node = references.ReferencePanel.new()
	for panel in [actual, expected]:
		root.add_child(panel)
		panel.set_process(false)
	for target in [1.0, 0.3, 1.0, 0.0, 1.0]:
		actual.target_opacity = target
		expected.target_opacity = target
		actual.visible = true
		expected.visible = true
		for frame in 120:
			var delta: float = [0.0, 1.0 / 144.0, 1.0 / 90.0, 1.0 / 30.0][frame % 4]
			actual._process(delta)
			expected._process(delta)
			check(actual.opacity == expected.opacity and actual.visible == expected.visible, "panel fade and dismissal match reference")
			check(actual.quad.transform.is_equal_approx(expected.quad.transform), "panel animation preserves transform")
			check(actual.material.get_shader_parameter("opacity") == expected.material.get_shader_parameter("opacity"), "panel animation preserves shader opacity")
	var writes: int = actual.writes
	for i in 200:
		actual._process(1.0 / 90.0)
	check(actual.writes == writes, "settled panel performs no shader or transform writes")
	measure("panel_reference", func() -> void: expected._process(1.0 / 90.0))
	measure("panel_optimized", func() -> void: actual._process(1.0 / 90.0))
	actual.visible = true
	actual.opacity = 0.0
	actual.target_opacity = 0.0
	actual.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	actual._process(1.0 / 90.0)
	check(not actual.visible and actual.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "already transparent panel disables its viewport")
	actual.free()
	expected.free()


func _smoothing() -> void:
	var actual: Node = main.music_visualizer
	var expected: Node = references.ReferenceVisualizer.new()
	expected.levels.resize(actual.BANDS)
	expected.targets.resize(actual.BANDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	for sample in 240:
		for band in actual.BANDS:
			actual.levels[band] = rng.randf_range(0.0, 2.0)
			actual.targets[band] = rng.randf_range(0.0, 2.0) if sample % 3 else 0.0
		expected.levels = actual.levels.duplicate()
		expected.targets = actual.targets.duplicate()
		var delta: float = [0.0, 0.00001, 1.0 / 144.0, 1.0 / 90.0, 1.0 / 30.0, 1.0][sample % 6]
		actual._smooth_levels(delta)
		expected._smooth_levels(delta)
		for band in actual.BANDS:
			check(actual.levels[band] == expected.levels[band], "spectrum smoothing preserves attack, release and silence exactly")
	measure("smoothing_reference", func() -> void: expected._smooth_levels(1.0 / 90.0))
	measure("smoothing_optimized", func() -> void: actual._smooth_levels(1.0 / 90.0))
	expected.free()


func _reference_match(text: String, words: PackedStringArray) -> bool:
	var haystack := text.to_lower().replace("_", " ").replace(".", " ")
	for word in words:
		if not haystack.contains(word):
			return false
	return true


func _search() -> void:
	var scanner: GDScript = load("res://scripts/library_scanner.gd")
	var names := PackedStringArray()
	for i in 1000:
		var text := "Collection_%04d.Ελληνικά日本語.MP4" % i
		names.append(text)
		for words in [PackedStringArray(), PackedStringArray(["collection"]), PackedStringArray(["ελληνικά", "mp4"]), PackedStringArray(["missing"]), PackedStringArray(["collection", str(i)])]:
			check(scanner.words_match(text, words) == _reference_match(text, words), "search preserves empty queries, separators, Unicode and all-word matching")
	measure("search_reference_1000", func() -> void:
		for text in names:
			_reference_match(text, PackedStringArray()), 10)
	measure("search_optimized_1000", func() -> void:
		for text in names:
			scanner.words_match(text, PackedStringArray()), 10)


func _cleanup() -> void:
	var player: Node = main.player
	var tracks: Node = player.tracks
	var gate := Semaphore.new()
	var blocked := WorkerThreadPool.add_task(func() -> void: gate.wait())
	var blocked_subtitle := WorkerThreadPool.add_task(func() -> void: gate.wait())
	var pending: Array[int] = []
	for i in 24:
		pending.append(WorkerThreadPool.add_task(func() -> void: pass))
	while not pending.all(func(task: int) -> bool: return WorkerThreadPool.is_task_completed(task)):
		await process_frame
	player.source_tasks.assign([pending[0], blocked])
	player.source_tasks.append_array(pending.slice(1, 12))
	tracks.subtitle_tasks.assign([pending[12], blocked_subtitle])
	tracks.subtitle_tasks.append_array(pending.slice(13))
	player._process(0.0)
	tracks._process(0.0)
	check(player.source_tasks == [blocked], "source cleanup retains running work and removes adjacent finished tasks")
	check(tracks.subtitle_tasks == [blocked_subtitle], "subtitle cleanup retains running work and removes adjacent finished tasks")
	gate.post()
	gate.post()
	while not WorkerThreadPool.is_task_completed(blocked) or not WorkerThreadPool.is_task_completed(blocked_subtitle):
		await process_frame
	player._process(0.0)
	tracks._process(0.0)
	check(player.source_tasks.is_empty(), "source cleanup reaps work after completion")
	check(tracks.subtitle_tasks.is_empty(), "subtitle cleanup reaps work after completion")
	var empty_stream := FFmpegVideoStream.new()
	player.discarded_streams.assign([empty_stream, FFmpegVideoStream.new()])
	player._process(0.0)
	check(player.discarded_streams.is_empty(), "unopened discarded streams are released together")
	var loader := VPXPanorama.new()
	player.discarded_loaders.assign([loader])
	player._process(0.0)
	check(player.discarded_loaders == [loader], "pending panorama decode remains alive")
	var picture := Image.create_empty(16, 8, false, Image.FORMAT_RGB8)
	picture.fill(Color.BLUE)
	var path := ProjectSettings.globalize_path("user://cleanup.png")
	check(picture.save_png(path) == OK, "cleanup panorama fixture saves")
	var decoded := VPXPanorama.new()
	check(decoded.start(PackedStringArray([path]), VPXPanorama.LAYOUT_TILED, false) == OK, "cleanup panorama decode starts")
	var decode_deadline := Time.get_ticks_msec() + 2000
	while not decoded.is_decoded() and Time.get_ticks_msec() < decode_deadline:
		await process_frame
	check(decoded.is_decoded(), "cleanup panorama decode completes")
	player.discarded_loaders.assign([decoded, loader, decoded])
	player._process(0.0)
	check(player.discarded_loaders == [loader], "cleanup removes completed panoramas around pending decode")
	player.discarded_loaders.clear()
	var reference: Node = references.ReferencePlayer.new()
	root.add_child(reference)
	reference.process_mode = Node.PROCESS_MODE_DISABLED
	reference._process(0.0)
	var reference_tracks: Node = references.ReferenceTracks.new()
	root.add_child(reference_tracks)
	reference_tracks.set_process(false)
	measure("player_reference_idle", func() -> void: reference._process(0.0))
	measure("player_idle", func() -> void: player._process(0.0))
	measure("tracks_reference_idle", func() -> void: reference_tracks._process(0.0))
	measure("tracks_idle", func() -> void: tracks._process(0.0))
	reference_tracks.free()
	reference.free()


func _screen() -> void:
	var screen: Node = main.screen
	screen._process(0.0)
	check(screen.material.get_shader_parameter("visualizer_media_dim") == 1.0, "screen initializes overlay dimming")
	screen.material.set_shader_parameter("visualizer_media_dim", 0.75)
	for i in 20:
		screen._process(0.0)
	check(screen.material.get_shader_parameter("visualizer_media_dim") == 0.75, "unchanged screen does not rewrite dimming")
	screen.media_dim_value = -1.0
	screen._process(0.0)
	check(screen.material.get_shader_parameter("visualizer_media_dim") == 1.0, "screen updates dimming after cache invalidation")
	var reference: Node = references.ReferenceScreen.new()
	reference.material = ShaderMaterial.new()
	reference.player = main.player
	root.add_child(reference)
	reference.set_process(false)
	measure("screen_reference_idle", func() -> void: reference._process(0.0))
	measure("screen_idle", func() -> void: screen._process(0.0))
	reference.free()


func _video() -> void:
	var settings := root.get_node("Settings")
	settings.auto_crop = false
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	var player: Node = main.player
	var screen: Node = main.screen
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var opened: bool = await player.open(OS.get_cmdline_user_args()[1], {"software": true, "paused": true})
	check(opened, "video fixture opens with audio and a decoded frame")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if not opened:
		return
	screen._process(0.0)
	check(screen.visible and screen.bound_serial >= 0, "video frame binds to screen")
	check(is_equal_approx(float(screen.material.get_shader_parameter("frame_seed")), float(screen.bound_serial % 997) * 0.618), "frame seed follows decoded serial")
	var previous: int = screen.bound_serial
	screen.material.set_shader_parameter("frame_seed", -123.0)
	for i in 20:
		screen._process(0.0)
	check(screen.bound_serial == previous and float(screen.material.get_shader_parameter("frame_seed")) == -123.0, "repeated paused frame does not rewrite shader seed")
	if DisplayServer.get_name() == "headless":
		var previous_playback: RefCounted = player.playback
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		check(await player.open(OS.get_cmdline_user_args()[1], {"software": true, "paused": true}), "replacement video opens")
		player.process_mode = Node.PROCESS_MODE_DISABLED
		screen._process(0.0)
		check(screen.bound_playback != previous_playback, "replacement video rebinds even when headless serial stays zero")
	else:
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.seek_to(1.0)
		var seek_deadline := Time.get_ticks_msec() + 2000
		while screen.bound_serial == previous and Time.get_ticks_msec() < seek_deadline:
			screen._process(0.01)
			await process_frame
		player.process_mode = Node.PROCESS_MODE_DISABLED
		check(screen.bound_serial != previous, "paused seek produces a new frame")
	check(is_equal_approx(float(screen.material.get_shader_parameter("frame_seed")), float(screen.bound_serial % 997) * 0.618), "new video frame refreshes shader seed")
	settings.immersive_music_visualizer = true
	settings.visualizer_overlay = true
	settings.visualizer_background_dim = 0.65
	screen._process(0.0)
	check(is_equal_approx(float(screen.material.get_shader_parameter("visualizer_media_dim")), 0.35), "overlay activation updates media dim")
	settings.visualizer_background_dim = 0.2
	screen._process(0.0)
	check(is_equal_approx(float(screen.material.get_shader_parameter("visualizer_media_dim")), 0.8), "changing backdrop dim invalidates cached shader value")
	settings.visualizer_overlay = false
	screen._process(0.0)
	check(float(screen.material.get_shader_parameter("visualizer_media_dim")) == 1.0, "leaving overlay restores undimmed video")
	player._retire_stream()
	player.stream = null
	player.playback = null
	player.playback_state.clear()
	var deadline := Time.get_ticks_msec() + 2000
	while not player.retired_streams.is_empty() and Time.get_ticks_msec() < deadline:
		player._process(0.0)
		await process_frame
	check(player.retired_streams.is_empty(), "retired decoder is released after IO stops")
	player.current_path = ""
