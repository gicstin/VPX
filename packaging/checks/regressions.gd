extends SceneTree

var failures := 0
var checks := 0
var ticks := 0
var main: Node
var endpoint := ""
var fixture := ""


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)


func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	endpoint = args[1]
	fixture = args[2]
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.last_directory = fixture
	settings.hide_menu_on_play = false
	settings.auto_crop = false
	settings.immersive_music_visualizer = false
	settings.music_visualizer = false
	settings.spatial_audio = false
	var timer := Timer.new()
	timer.wait_time = 0.01
	root.add_child(timer)
	timer.timeout.connect(func() -> void: ticks += 1)
	timer.start()
	if mode == "core":
		_playlist_cases()
		_decoder_cases()
		await _remote_case()
	elif mode in ["remote_open", "replacement_end", "local_cancel", "local_read", "online_radio", "online_navigation", "radio_clock", "radio_jitter", "radio_opus", "link_history", "radio_metadata"]:
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for i in 15:
			await process_frame
		match mode:
			"radio_metadata":
				await _radio_metadata_case()
			"radio_opus":
				await _radio_clock_case("/radio-opus")
			"radio_jitter":
				await _radio_jitter_case()
			"radio_clock":
				await _radio_clock_case()
			"link_history":
				await _link_history_case()
			"online_radio":
				await _online_radio_case()
			"online_navigation":
				await _online_navigation_case()
			"remote_open":
				await _remote_open_case()
			"replacement_end":
				await _replacement_case()
			"local_cancel":
				await _local_cancel_case()
			"local_read":
				await _local_read_case()
	else:
		await _music_case(mode)
	if main != null:
		main.queue_free()
		await process_frame
	print("RESULT: %s checks=%d failures=%d" % [mode, checks, failures])
	quit(1 if failures else 0)


func _radio_metadata_case() -> void:
	var radio = main.player.radio
	check(await main.player.open(endpoint + "/radio-icy"), "ICY metadata stream opens")
	check(await wait_for(func() -> bool: return radio.metadata.get("title") == "First Song" and radio.artwork != null, 6.0), "stream metadata supplies artist, song and cover art")
	check(radio.metadata.get("station") == "VPX Metadata Radio", "ICY station name is retained")
	main.photo_bar.root.refresh()
	check(main.photo_bar.root.title_label.text.contains("First Song") and main.photo_bar.root.details_label.text.contains("First Artist") and main.photo_bar.root.cover_image.visible, "expanded music player shows artist and station art")
	main.photo_bar.root.set_collapsed(true)
	check(main.photo_bar.root.preview_image.texture == radio.artwork, "collapsed music player shows station art")
	main.photo_bar.root.set_collapsed(false)
	var first_art: Texture2D = radio.artwork
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(endpoint + "/release")
	await request.request_completed
	request.queue_free()
	check(await wait_for(func() -> bool: return radio.metadata.get("title") == "Second Song" and radio.artwork != null and radio.artwork != first_art, 6.0), "live track change updates title and replaces album art")
	check(main.player.is_playing() and main.ui.music_label().contains("Second Artist"), "metadata refresh leaves audio playing")
	check(await main.player.open(fixture.path_join("short.wav")), "local audio replaces metadata stream")
	await process_frame
	check(radio.path.is_empty() and radio.artwork == null and radio.metadata.is_empty(), "leaving station clears live metadata and album art")
	var feed = load("res://scripts/radio_metadata.gd").new()
	root.add_child(feed)
	feed.follow("test-station", "http://example.org/live")
	feed.api_url = endpoint + "/station-metadata"
	check(await wait_for(func() -> bool: return feed.metadata.get("album") == "Station Album" and feed.artwork != null, 3.0), "station JSON feed supplies album and cover art")
	check(feed.provider_url("http://stream.radioparadise.com/flacm").ends_with("chan=0"), "Radio Paradise Main Mix uses station metadata API")
	check(feed.provider_url("https://stream.radioparadise.com/mellow-flac").ends_with("chan=1"), "Radio Paradise Mellow Mix uses its own metadata channel")
	feed.follow("old-station", "http://example.org/old")
	feed.apply_stream({"radio_tags": {"title": "Old Song", "cover": endpoint + "/slow-art.png"}})
	feed.follow("new-station", "http://example.org/new")
	feed.apply_stream({"radio_tags": {"title": "New Song", "cover": endpoint + "/other-art.png"}})
	check(await wait_for(func() -> bool: return feed.artwork != null, 2.0), "new station artwork loads after cancellation")
	var current_art: Texture2D = feed.artwork
	await create_timer(0.8).timeout
	check(feed.metadata.get("title") == "New Song" and feed.artwork == current_art, "late artwork cannot overwrite another station")
	feed.queue_free()


func _radio_clock_case(route := "/radio-clock") -> void:
	var audio := AudioEffectCapture.new()
	audio.buffer_length = 2.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(main.player.OUTPUT_BUS), audio)
	check(await main.player.open(endpoint + route), "live audio fixture opens: " + route)
	check(main.player.is_live(), "timestamp test remains a live stream")
	await create_timer(0.5).timeout
	audio.clear_buffer()
	var total := 0
	var silent := 0
	var silent_run := 0
	var longest_run := 0
	var start_serial := int(main.player.playback.get_progress_state()["serial"])
	var deadline := Time.get_ticks_msec() + 6500
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for sample: Vector2 in audio.get_buffer(audio.get_frames_available()):
			total += 1
			if sample.length_squared() < 0.0000000001:
				silent += 1
				silent_run += 1
				longest_run = maxi(longest_run, silent_run)
			else:
				silent_run = 0
	check(total > AudioServer.get_mix_rate() * 5, "audio continuity check measures mixed output")
	check(silent < total * 0.01, "timestamp jump cannot mute decoded radio audio")
	check(longest_run < AudioServer.get_mix_rate() * 0.05, "radio output has no audible gaps across timestamp jump")
	check(int(main.player.playback.get_progress_state()["serial"]) > start_serial + 30, "radio decoder keeps feeding audio after timestamp jump")


func _radio_jitter_case() -> void:
	check(await main.player.open(endpoint + "/radio-jitter"), "radio with stalled connection opens")
	check(await wait_for(func() -> bool: return int(main.player.playback.get_progress_state()["serial"]) > 5, 4.0), "radio fills its startup buffer before playing")
	check(await wait_for(func() -> bool: return main.player.stream_position > 1.0 and main.player.playback.get_progress_state().get("audio_buffering", false), 8.0), "radio enters buffering when the network reserve is exhausted")
	var position: float = main.player.stream_position
	var serial := int(main.player.playback.get_progress_state()["serial"])
	await create_timer(0.4).timeout
	check(absf(main.player.stream_position - position) < 0.01, "radio clock stops during starvation instead of skipping samples")
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(endpoint + "/release")
	await request.request_completed
	request.queue_free()
	check(await wait_for(func() -> bool: return int(main.player.playback.get_progress_state()["serial"]) > serial + 10, 4.0), "radio refills and resumes feeding audio after a network stall")
	check(main.player.stream_position > position and main.player.stream_position < position + 2.0, "recovery continues from buffered audio without a clock jump")


func _link_history_case() -> void:
	var library := root.get_node("Library")
	library.remember_link(endpoint + "/first")
	library.set_pref(endpoint + "/first", "link_opened", 1.0)
	library.remember_link(endpoint + "/second")
	library.remember_link(endpoint + "/first")
	check(library.recent_links().size() == 2 and library.recent_links()[0] == endpoint + "/first", "opened-link history deduplicates and moves reopened link first")
	check(library.save() == OK, "opened-link history saves")
	var restored = load("res://scripts/library.gd").new()
	root.add_child(restored)
	check(restored.recent_links() == library.recent_links(), "opened links survive library reload")
	restored.queue_free()
	root.get_node("Settings").library_source = 4
	main.ui.refresh_directory(false)
	check(endpoint + "/first" in main.ui.listing and endpoint + "/second" in main.ui.listing, "Network page lists opened links for reopening")
	for controller: XRController3D in [main.get_node("Origin/Left"), main.get_node("Origin/Right")]:
		check(not controller.is_processing(), "desktop disables XR pointer injection")
	main.ui._ask_link()
	main.ui.keyboard._insert("http://stream.radioparadise.com/flacm")
	var received: Array[String] = []
	main.ui.keyboard.submitted.connect(func(text: String) -> void: received.append(text))
	for i in 8:
		await process_frame
	var done: Button = main.ui.keyboard.rows.get_child(4).get_children().back()
	var canvas := Vector2(main.ui_viewport.size_2d_override)
	var point: Vector2 = main.desktop_view.menu_rect.position + done.get_global_rect().get_center() / canvas * main.desktop_view.menu_rect.size
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for i in 5:
		await process_frame
		check(main.ui_viewport.gui_get_hovered_control() == done, "Done button keeps pointer hover after pasted URL")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		for i in 3:
			await process_frame
	check(received == ["http://stream.radioparadise.com/flacm"], "mouse click on Done submits pasted link once")
	main.ui.recovery.cancel()
	check(library.recent_links().has("http://stream.radioparadise.com/flacm"), "submitted link is remembered even if opening is cancelled")


func _online_radio_case() -> void:
	var web = main.ui.web
	web.tool_path = ""
	for suffix in ["track.flac?token=kept", "track.mp3#radio", "track.aac", "live.m3u8"]:
		check(not web.needs_resolve("https://example.org/" + suffix), "direct audio and HLS bypass web tools: " + suffix)
	check(web.needs_resolve("https://example.org/radio"), "extensionless link needs response detection")
	check(web.needs_resolve("https://www.youtube.com/watch?v=test"), "video pages keep web resolution")
	for route in ["/radio", "/radio-redirect", "/radio-get"]:
		var result: Dictionary = await web.probe_stream(endpoint + route)
		check(result.get("direct", false) and result.get("audio_only", false), "detect stream without reading its endless body: " + route)
		check(result.get("title") == "VPX Test Radio", "read station name: " + route)
	check((await web.probe_stream(endpoint + "/radio-page")).is_empty(), "HTML page stays on web-video path")
	web.probe_stream(endpoint + "/radio-slow")
	await create_timer(0.1).timeout
	var cancelled_at := Time.get_ticks_msec()
	web.cancel()
	check(Time.get_ticks_msec() - cancelled_at < 300 and web.link_probe == null, "cancel slow stream probe immediately")
	var radio := endpoint.replace("127.0.0.1", "localhost.") + "/radio"
	check(web.needs_resolve(radio), "radio UI case exercises extensionless link routing")
	main.ui._open_link(radio)
	check(await wait_for(func() -> bool: return main.player.load_state.get("status") == "ready", 10.0), "Open link plays extensionless radio without yt-dlp")
	check(main.player._audio_only_playing() and main.player.is_live(), "radio is live audio")
	check(main.ui.music_label().contains("VPX Test Radio"), "music controls show station name")
	check(main.ui.music_playlist == PackedStringArray([radio]), "radio replaces previous music navigation")
	var before: float = main.player.stream_position
	await create_timer(0.4).timeout
	check(main.player.stream_position > before, "live radio advances")
	main.ui._update_transport()
	check(not main.player.can_seek() and not main.ui.seek_slider.editable and main.ui.total_label.text == "LIVE", "live transport disables seeking and shows LIVE")
	main.photo_bar.root.refresh()
	check(main.photo_bar.root.time_label.text.ends_with("LIVE") and not main.photo_bar.root.progress.editable and main.photo_bar.root.back_button.disabled and main.photo_bar.root.forward_button.disabled, "compact music controls show LIVE and disable seek controls")
	main.player.seek_to(100.0)
	check(main.player.stream_position > before, "seek shortcut cannot rewind live radio")
	main.player.toggle_pause()
	check(main.player.paused, "live radio pauses")
	main.player.toggle_pause()
	check(not main.player.paused, "live radio resumes")
	check(await main.player.open(fixture.path_join("photo.png")), "photo opens over live radio")
	check(main.player.is_image() and main.player.music_path == radio, "radio continues under photo")
	await main.ui.open_media(radio)
	check(main.player.is_image() and main.player.music_path == radio, "extensionless radio opens over existing photo")
	check(await main.player.open(fixture.path_join("short.wav")), "local audio replaces live radio")
	check(main.player.can_seek() and not main.player.is_live(), "local audio keeps normal seeking")
	main.ui.open_media(endpoint.replace("127.0.0.1", "localhost.") + "/radio-slow")
	await create_timer(0.1).timeout
	await main.ui.open_media(fixture.path_join("short.wav"))
	check(main.player.music_path == fixture.path_join("short.wav") and main.ui.resolving_path.is_empty(), "replacement cancels pending stream detection")


func _online_navigation_case() -> void:
	var library := root.get_node("Library")
	var settings := root.get_node("Settings")
	var address := endpoint.replace("127.0.0.1", "localhost.")
	var sources := PackedStringArray([address + "/radio", address + "/radio-get", address + "/radio-clock"])
	for i in sources.size():
		library.set_pref(sources[i], "link_opened", 3.0 - i)
	settings.shuffle = false
	await main.ui.open_media(sources[0])
	check(main.player.is_live() and main.ui.music_playlist == sources and main.ui.playlist == sources, "live radio uses memorised links for both transport playlists")
	for index in [1, 2, 0, 1]:
		main.ui.get_node("%NextButton").pressed.emit()
		check(await wait_for(func() -> bool: return main.player.current_path == sources[index] and main.player.load_state.get("status") == "ready", 5.0), "next reaches memorised source %d" % index)
		check(main.ui.music_playlist == sources, "recent-link updates preserve cycling order")
	for index in [0, 2, 1]:
		main.ui.get_node("%PrevButton").pressed.emit()
		check(await wait_for(func() -> bool: return main.player.current_path == sources[index] and main.player.load_state.get("status") == "ready", 5.0), "previous reaches memorised source %d" % index)
	settings.shuffle = true
	var before: String = main.player.current_path
	check(main.ui.play_music_neighbor(1), "shuffle selects another saved source")
	check(await wait_for(func() -> bool: return main.player.current_path != before and main.player.load_state.get("status") == "ready", 5.0), "shuffle opens another source")
	check(main.ui.play_music_neighbor(-1), "shuffle previous source is available")
	check(await wait_for(func() -> bool: return main.player.current_path == before and main.player.load_state.get("status") == "ready", 5.0), "shuffle previous returns to prior station")
	settings.shuffle = false
	check(await main.player.open(fixture.path_join("photo.png")), "photo opens over station navigation")
	main.photo_bar.root.track(1)
	check(await wait_for(func() -> bool: return main.player.music_path == sources[2] and main.player.load_state.get("status") == "ready", 5.0), "mini-player next switches saved radio under photo")
	check(main.player.is_image() and main.player.current_path == fixture.path_join("photo.png"), "station navigation retains photo")
	main.photo_bar.root.track(-1)
	check(await wait_for(func() -> bool: return main.player.music_path == sources[1] and main.player.load_state.get("status") == "ready", 5.0), "mini-player previous switches saved radio under photo")
	check(await main.player.open(fixture.path_join("short.wav")), "local track replaces station")
	check(await wait_for(func() -> bool: return fixture.path_join("short.wav") in main.ui.music_playlist, 3.0), "local track navigation restores local playlist")
	check(sources[0] not in main.ui.music_playlist, "local playlist excludes online sources")


func _playlist_cases() -> void:
	var ui = load("res://packaging/checks/playlist_ui.gd").new()
	var scanner = load("res://packaging/checks/cover_scanner.gd").new()
	ui.scanner = scanner
	for i in 3000:
		var path := "/unavailable/%04d/" % i
		ui.playlist.append(path)
		ui.folder_covers[path.trim_suffix("/")] = {}
	ui.playlist_index = scanner.index_of(ui.playlist)
	for shuffled in [false, true]:
		root.get_node("Settings").shuffle = shuffled
		for direction in [-1, 1]:
			ui.pending_direction = direction
			ui.shuffle.sync(ui.playlist, ui.playlist[0])
			ui._open_entry(ui.playlist[1])
			check(ui.pending_entry.is_empty() and ui.selected_paths.is_empty(), "exhausted playlist stops: shuffle=%s direction=%d" % [shuffled, direction])
	root.get_node("Settings").shuffle = false
	ui.pending_direction = 1
	ui.folder_covers["/unavailable/2999"] = {"cover": "/available/photo.png"}
	ui._open_entry(ui.playlist[0])
	check(ui.selected_paths == ["/available/photo.png"], "long run of empty folders reaches playable entry without recursion")
	ui.selected_paths.clear()
	ui.playlist = PackedStringArray(["/unknown/a/", "/unknown/b/"])
	ui.playlist_index = scanner.index_of(ui.playlist)
	ui._open_entry(ui.playlist[0])
	check(ui.pending_entry == "/unknown/a/", "unresolved folder waits for its cover")
	ui._on_cover_found("/unknown/a", {})
	check(ui.pending_entry == "/unknown/b/", "empty asynchronous cover advances")
	ui._on_cover_found("/unknown/b", {})
	check(ui.pending_entry.is_empty() and ui.selected_paths.is_empty(), "asynchronous exhaustion stops across callbacks")
	ui.folder_covers.erase("/unknown/a")
	ui._open_entry("/unknown/a/")
	ui._open_entry("/new/photo.png")
	ui._on_cover_found("/unknown/a", {"cover": "/stale/photo.png"})
	check(ui.selected_paths == ["/new/photo.png"], "stale cover cannot replace a newer navigation request")
	ui.playlist = PackedStringArray()
	ui.playlist_index.clear()
	ui._open_entry("/unknown/b/")
	check(ui.pending_entry.is_empty(), "empty playlist stops safely")
	ui.free()
	scanner.free()


func _decoder_cases() -> void:
	OS.unset_environment("VPX_DECODE")
	OS.unset_environment("VPX_DECODE_SETTING")
	var player = load("res://scripts/player.gd").new()
	var settings := root.get_node("Settings")
	for pair in [[settings.DecodeMode.SOFTWARE, "sw"], [settings.DecodeMode.AUTO, "auto"], [settings.DecodeMode.HARDWARE, "hw"], [settings.DecodeMode.SOFTWARE, "sw"], [settings.DecodeMode.AUTO, "auto"]]:
		settings.decode_mode = pair[0]
		player._apply_decode_mode()
		check(OS.get_environment("VPX_DECODE") == pair[1], "decoder setting changes to " + pair[1])
	player._apply_decode_mode(true)
	player._apply_decode_mode(true)
	settings.decode_mode = settings.DecodeMode.HARDWARE
	player._apply_decode_mode()
	check(OS.get_environment("VPX_DECODE") == "hw", "repeated software retry restores current decoder preference")
	var restarted = load("res://scripts/player.gd").new()
	settings.decode_mode = settings.DecodeMode.AUTO
	restarted._apply_decode_mode()
	check(OS.get_environment("VPX_DECODE") == "auto", "inherited app setting stays changeable after restart")
	restarted.free()
	for override in ["hw", "sw", "hardware", "software"]:
		OS.set_environment("VPX_DECODE", override)
		OS.unset_environment("VPX_DECODE_SETTING")
		player._apply_decode_mode()
		check(OS.get_environment("VPX_DECODE") == override, "explicit environment override preserved: " + override)
		player._apply_decode_mode(true)
		check(OS.get_environment("VPX_DECODE") == "sw", "software retry temporarily overrides " + override)
		player._apply_decode_mode()
		check(OS.get_environment("VPX_DECODE") == override, "software retry restores explicit " + override)
	OS.set_environment("VPX_DECODE", "sw")
	OS.set_environment("VPX_DECODE_SETTING", "sw")
	var cli = load("res://scripts/main.gd").new()
	cli._parse_arguments()
	player._apply_decode_mode()
	check(OS.get_environment("VPX_DECODE") == "sw", "explicit command line wins even when equal to last app setting")
	cli.free()
	player.free()
	OS.unset_environment("VPX_DECODE")
	OS.unset_environment("VPX_DECODE_SETTING")


func _remote_case() -> void:
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	var remote = load("res://scripts/remote_control.gd").new()
	remote.player = player
	remote.port = 0
	root.get_node("Settings").remote_control = true
	root.add_child(remote)
	var slow := StreamPeerTCP.new()
	var fast := StreamPeerTCP.new()
	var port: int = remote.server.get_local_port()
	slow.connect_to_host("127.0.0.1", port)
	fast.connect_to_host("127.0.0.1", port)
	check(await wait_for(func() -> bool:
		slow.poll()
		fast.poll()
		return remote.client_count() == 2, 2.0), "two remote clients connect")
	if remote.client_count() != 2:
		remote.queue_free()
		player.queue_free()
		return
	var fast_received := PackedByteArray()
	var messages := 0
	var latest := -1
	var worst_usec := 0
	var before := ticks
	var deadline := Time.get_ticks_msec() + 1800
	var sequence := 0
	var bounded := true
	var ordered := true
	while Time.get_ticks_msec() < deadline:
		var message := {"sequence": sequence, "path": "x".repeat(90000)}
		for client in remote.clients:
			remote._send(client, message)
			var pending: Dictionary = remote.outgoing.get(client, {})
			if not pending.is_empty():
				bounded = bounded and pending["packet"].size() + pending["next"].size() <= 2 * (remote.MAX_MESSAGE + 4)
		var start := Time.get_ticks_usec()
		for client in remote.clients:
			remote._flush(client)
		worst_usec = maxi(worst_usec, Time.get_ticks_usec() - start)
		fast.poll()
		var available := fast.get_available_bytes()
		if available:
			fast_received.append_array(fast.get_data(available)[1])
		while fast_received.size() >= 4:
			var length := fast_received.decode_u32(0)
			if fast_received.size() < length + 4:
				break
			if length:
				var decoded: Variant = JSON.parse_string(fast_received.slice(4, 4 + length).get_string_from_utf8())
				if not decoded is Dictionary:
					check(false, "partial writes preserve JSON framing")
				elif decoded.has("sequence"):
					ordered = ordered and int(decoded["sequence"]) > latest
					latest = int(decoded["sequence"])
					messages += 1
			fast_received = fast_received.slice(4 + length)
		sequence += 1
		await process_frame
	check(worst_usec < 100000 and ticks - before >= 30, "unread remote socket leaves writes and UI heartbeat responsive")
	check(bounded and remote.outgoing.size() <= 2, "pending status memory stays bounded")
	check(ordered and messages > 5 and latest > 20, "healthy remote receives complete ordered statuses beside stalled client")
	var backpressure := false
	for client in remote.clients:
		var pending: Dictionary = remote.outgoing.get(client, {})
		if not pending.is_empty() and client.get_connected_port() == slow.get_local_port():
			backpressure = true
			pending["progress"] = Time.get_ticks_msec() - remote.SEND_TIMEOUT_MSEC
			remote._flush(client)
	check(backpressure, "slow socket reaches backpressure with an unfinished packet")
	check(await wait_for(func() -> bool: return remote.client_count() == 1, 1.0), "stalled remote client times out without dropping healthy client")
	var command := JSON.stringify({"playbackSpeed": 1.25}).to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, command.size())
	fast.put_data(header + command)
	check(await wait_for(func() -> bool: return root.get_node("Settings").playback_speed == 1.25, 1.0), "healthy client still controls playback after stalled peer is removed")
	remote._stop()
	root.get_node("Settings").remote_control = false
	check(remote.outgoing.is_empty() and remote.buffers.is_empty(), "remote shutdown clears pending state")
	slow.disconnect_from_host()
	fast.disconnect_from_host()
	remote.queue_free()
	player.queue_free()
	await process_frame


func _music_case(mode: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 15:
		await process_frame
	var player: Node = main.player
	var original := fixture.path_join("photo.png")
	var photo := fixture.path_join("other.png")
	var song := fixture.path_join("audio.wav")
	var options := {"stream": endpoint + "/audio.wav?token=kept", "headers": "X-VPX-Test: yes\r\n"}
	check(await player.open(original), "initial photo opens")
	check(await player.open(song, options), "network music opens over photo")
	check(await player.open(photo), "photo browsing preserves music")
	check(player.music_path == song and player.current_path == photo and player.is_playing(), "photo and music retain separate identities")
	if mode == "music_cancel":
		player.open(endpoint + "/never.mp4")
		await create_timer(0.2).timeout
		player.cancel_open()
		check(player.is_playing() and player.music_path == song, "cancelling replacement preserves music")
	elif mode == "music_failed_photo":
		await player.open(fixture.path_join("missing.png"))
		check(main.ui.recovery.status == "failed", "failed photo keeps its own recovery context")
	check(await wait_for(func() -> bool: return player.playback_state.get("status") == "buffering", 16.0), "music starvation still detected after photo or cancelled request")
	check(main.ui.recovery.source == song, "music recovery selects original song rather than photo")
	check(main.ui.recovery.options.get("stream") == options["stream"] and main.ui.recovery.options.get("headers") == options["headers"], "music recovery retains signed stream and request headers")
	if mode == "music_transient":
		var request := HTTPRequest.new()
		root.add_child(request)
		request.request(endpoint + "/release")
		await request.request_completed
		request.queue_free()
		check(await wait_for(func() -> bool: return player.playback_state.get("status") == "ready", 5.0), "transient music starvation clears after new audio arrives")
		check(not main.ui.recovery.visible and player.is_playing() and player.current_path == photo, "transient recovery retains photo and music")
		return
	player.set_process(false)
	player._monitor_stream(30.0)
	check(main.ui.recovery.status == "failed" and main.ui.recovery.source == song, "permanent music failure retains correct retry source")
	main.ui.recovery.retry()
	player.set_process(true)
	check(await wait_for(func() -> bool: return player.load_state.get("status") == "ready" and player.is_playing(), 4.0), "Retry actually restarts music playback")
	check(player.current_path == photo and player.music_path == song, "Retry retains current photo")
	var progress := int(player.playback.get_progress_state()["serial"])
	await create_timer(0.3).timeout
	check(int(player.playback.get_progress_state()["serial"]) > progress, "retried music produces new audio samples")


func _remote_open_case() -> void:
	var url := endpoint + "/delayed.mp4"
	main.ui.remote._handle(JSON.stringify({"path": url, "currentTime": 5.0, "playerState": 1}))
	check(await wait_for(func() -> bool: return main.player.load_state.get("status") == "ready", 4.0), "remote open finishes")
	check(main.player.current_path == url and main.player.paused and absf(main.player.stream_position - 5.0) < 0.3, "combined remote open retains seek and pause")
	await main.player.open(fixture.path_join("movie.mp4"), {"start_time": 2.0, "paused": true})
	url = endpoint + "/delayed-again.mp4"
	main.ui.remote._handle(JSON.stringify({"path": url, "currentTime": 3.0, "playerState": 0}))
	await create_timer(0.15).timeout
	main.ui.remote._handle(JSON.stringify({"path": url, "currentTime": 7.0, "playerState": 1}))
	check(main.player.paused and absf(main.player.stream_position - 2.0) < 0.3, "pending transport updates leave previous media untouched")
	check(await wait_for(func() -> bool: return main.player.load_state.get("status") == "ready", 4.0), "updated remote open finishes")
	check(main.player.current_path == url and main.player.paused and absf(main.player.stream_position - 7.0) < 0.3, "latest pending transport options win")
	main.ui.remote._handle(JSON.stringify({"path": endpoint + "/delayed-slow.mp4", "currentTime": 8.0, "playerState": 0}))
	await create_timer(0.1).timeout
	main.ui.remote._handle(JSON.stringify({"path": fixture.path_join("movie.mp4"), "currentTime": 1.0, "playerState": 1}))
	await create_timer(2.2).timeout
	check(main.player.current_path == fixture.path_join("movie.mp4") and main.player.paused and absf(main.player.stream_position - 1.0) < 0.3, "cancelled remote request cannot change newer playback")

	var original_web: Node = main.ui.web
	var web = load("res://packaging/checks/delayed_web.gd").new()
	web.media = fixture.path_join("movie.mp4")
	main.ui.add_child(web)
	main.ui.web = web
	main.ui.remote._handle(JSON.stringify({"path": "https://example.test/watch/remote", "currentTime": 4.0, "playerState": 0}))
	main.ui.remote._handle(JSON.stringify({"currentTime": 6.0, "playerState": 1}))
	check(await wait_for(func() -> bool: return main.player.current_path == "https://example.test/watch/remote" and main.player.load_state.get("status") == "ready", 4.0), "remote web resolution finishes")
	check(main.player.paused and absf(main.player.stream_position - 6.0) < 0.3, "transport updates survive web resolution")
	main.ui.web = original_web
	web.queue_free()
	root.get_node("Settings").subtitle_auto = root.get_node("Settings").SubtitleAuto.ALWAYS
	await main.player.open(fixture.path_join("movie.mp4"), {"paused": true})
	check(await wait_for(func() -> bool: return main.player.tracks.source != null, 2.0), "filesystem subtitles load asynchronously after discovery")
	main.player.tracks.select_subtitle(0)
	main.player.tracks.select_subtitle(-1)
	await create_timer(0.1).timeout
	check(main.player.tracks.source == null, "late subtitle loading cannot restore a deselected track")


func _replacement_case() -> void:
	var settings := root.get_node("Settings")
	for picture in [false, true]:
		for action in [settings.EndAction.NEXT_FILE, settings.EndAction.REPEAT]:
			settings.end_action = settings.EndAction.STOP
			if picture:
				await main.player.open(fixture.path_join("photo.png"))
			await main.player.open(fixture.path_join("short.wav"), {"paused": false})
			settings.end_action = action
			var url := endpoint + "/delayed-slow-%s-%d.wav" % [picture, action]
			main.ui.open_media(url)
			await create_timer(1.3).timeout
			check(main.player.load_state.get("path") == url and main.player.load_state.get("status") == "opening", "old completion preserves pending replacement: picture=%s action=%d" % [picture, action])
			check(not main.player.is_playing(), "old track does not restart during replacement")
			check(await wait_for(func() -> bool: return main.player.load_state.get("status") == "ready", 4.0), "replacement finishes after old completion")
			check((main.player.music_path if picture else main.player.current_path) == url, "requested source wins after old completion")
			settings.end_action = settings.EndAction.STOP
			await main.player.open(fixture.path_join("movie.mp4"), {"paused": true})

	var original_web: Node = main.ui.web
	var web = load("res://packaging/checks/delayed_web.gd").new()
	web.media = fixture.path_join("movie.mp4")
	main.ui.add_child(web)
	main.ui.web = web
	await main.player.open(fixture.path_join("short.wav"), {"paused": false})
	settings.end_action = settings.EndAction.NEXT_FILE
	main.ui.open_media("https://example.test/watch/replacement")
	check(await wait_for(func() -> bool: return main.player.current_path == "https://example.test/watch/replacement" and main.player.load_state.get("status") == "ready", 4.0), "old completion also preserves a pending web resolution")
	settings.end_action = settings.EndAction.STOP
	main.ui.web = original_web
	web.queue_free()


func _local_cancel_case() -> void:
	var player: Node = main.player
	var before := ticks
	player.open(fixture.path_join("audio.wav"), {"stream": fixture.path_join("blocked.wav")})
	await create_timer(0.3).timeout
	check(player.opening_stream != null and player.opening_stream.get_open_status() == 1 and ticks - before >= 15, "blocked filesystem open keeps UI heartbeat responsive")
	var start := Time.get_ticks_msec()
	player.cancel_open()
	check(Time.get_ticks_msec() - start < 100, "blocked filesystem open cancels without waiting for the OS")
	check(await player.open(fixture.path_join("photo.png")), "new media opens while cancelled file I/O remains blocked")
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(endpoint + "/release-local")
	await request.request_completed
	request.queue_free()
	check(await wait_for(func() -> bool: return player.discarded_streams.is_empty(), 3.0), "cancelled local decoder releases after filesystem I/O returns")
	check(player.current_path == fixture.path_join("photo.png") and player.is_image(), "late file I/O cannot replace newer media")


func _local_read_case() -> void:
	var player: Node = main.player
	check(await player.open(fixture.path_join("audio.wav"), {"stream": fixture.path_join("blocked.wav")}), "filesystem stream starts before read stalls")
	await create_timer(9.0).timeout
	var before := ticks
	var started := Time.get_ticks_msec()
	check(await player.open(fixture.path_join("movie.mp4"), {"paused": true}), "new video replaces a decoder blocked in filesystem I/O")
	check(Time.get_ticks_msec() - started < 1500 and ticks - before < 100, "replacement does not join a blocked decoder on the UI thread")
	check(not player.retired_streams.is_empty(), "blocked decoder remains retained until its worker exits")
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(endpoint + "/release-local")
	await request.request_completed
	request.queue_free()
	check(await wait_for(func() -> bool: return player.retired_streams.is_empty(), 3.0), "retired decoder releases after blocked read returns")
	check(player.current_path == fixture.path_join("movie.mp4") and player.paused, "late decoder completion leaves replacement untouched")
