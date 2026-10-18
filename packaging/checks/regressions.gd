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
	elif mode in ["remote_open", "replacement_end", "local_cancel", "local_read"]:
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for i in 15:
			await process_frame
		match mode:
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
