extends SceneTree

var references: GDScript

var checks := 0
var failures := 0
var measurements := {}


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


func measure(name: String, action: Callable, iterations := 300) -> void:
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
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: pipeline performance timeout"); quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.last_directory = ""
	settings.remote_control = false
	references = load("res://packaging/checks/pipeline_references.gd")
	_history()
	_stereo()
	await _remote()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	check(file != null, "pipeline report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	print("RESULT: pipeline_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _history() -> void:
	var actual: Node = load("res://scripts/resonance_field.gd").new()
	var expected: Node = references.ReferenceField.new()
	for field in [actual, expected]:
		root.add_child(field)
		field.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	for frame in 420:
		var levels := PackedFloat32Array()
		levels.resize(actual.BANDS * actual.ROWS)
		for band in actual.BANDS * 2:
			levels[band] = rng.randf_range(-0.1, 2.0) if frame % 11 else 0.0
		actual.spectrum_levels = levels
		expected.spectrum_levels = levels.duplicate()
		for channel in 2:
			var target := Vector3(rng.randf(), rng.randf(), rng.randf())
			actual.channel_targets[channel] = target
			expected.channel_targets[channel] = target
		actual.has_audio = frame % 13 != 0
		expected.has_audio = actual.has_audio
		var delta: float = [0.0, 0.00001, 1.0 / 144.0, 1.0 / 90.0, 1.0 / 45.0, 1.0 / 30.0, 0.1, 0.5][frame % 8]
		if frame in [96, 240]:
			delta = 5.0
		actual._update_history(delta)
		expected._update_history(delta)
		actual._update_spectral_history(delta)
		expected._update_spectral_history(delta)
		check(actual.channel_levels == expected.channel_levels, "channel smoothing exactly matches reference")
		check(actual.history_image.get_data() == expected.history_image.get_data(), "channel history bytes match across frame rates, silence and wraps")
		check(actual.spectral_history_image.get_data() == expected.spectral_history_image.get_data(), "spectral history bytes match across frame rates, silence and wraps")
		check(actual.history_position == expected.history_position and actual.history_elapsed == expected.history_elapsed, "channel history timing matches reference")
		check(actual.spectral_history_position == expected.spectral_history_position and actual.spectral_history_elapsed == expected.spectral_history_elapsed and actual.spectral_history_duration == expected.spectral_history_duration, "spectral history timing matches reference")
	for field in [actual, expected]:
		field.has_audio = true
	measure("spectral_reference", func() -> void: expected._update_spectral_history(1.0 / 45.0))
	measure("spectral_optimized", func() -> void: actual._update_spectral_history(1.0 / 45.0))
	measure("history_reference", func() -> void: expected._update_history(1.0 / 90.0))
	measure("history_optimized", func() -> void: actual._update_history(1.0 / 90.0))
	actual.free()
	expected.free()


func _stereo() -> void:
	var actual := StereoImage.new()
	var expected: RefCounted = references.ReferenceStereo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 485192
	for frame in 240:
		var data := PackedFloat32Array()
		data.resize(96)
		for band in data.size():
			data[band] = rng.randf_range(0.0, 1.5) if frame % 9 else 0.0
		var phase := rng.randf_range(-1.0, 1.0)
		actual.feed(data, frame % 3 == 0, phase)
		expected.feed(data, frame % 3 == 0, phase)
		var delta: float = [0.0, 0.00001, 1.0 / 144.0, 1.0 / 90.0, 1.0 / 30.0, 0.1][frame % 6]
		actual.update(delta)
		expected.update(delta)
		check(actual.left_levels == expected.left_levels and actual.right_levels == expected.right_levels and actual.pans == expected.pans, "stereo levels and steering match reference")
		check(actual.width == expected.width and actual.balance == expected.balance and actual.channel_balance == expected.channel_balance, "stereo balance and width exactly match reference")
		check(actual.sources == expected.sources and actual.source_info == expected.source_info and actual.source_bursts == expected.source_bursts, "source positions, lifetimes and flashes match reference")
		for pair in [[actual.correlation_ring, expected.correlation_ring], [actual.band_ring, expected.band_ring], [actual.field_ring, expected.field_ring], [actual.source_ring, expected.source_ring]]:
			check(pair[0].image.get_data() == pair[1].image.get_data(), "stereo history bytes exactly match reference")
			check(pair[0].head == pair[1].head and pair[0].elapsed == pair[1].elapsed, "stereo history cadence matches reference")
		if frame % 37 == 0:
			actual.clear()
			expected.clear()
	measure("stereo_rows_reference", expected._write_rows, 100)
	measure("stereo_rows_optimized", actual._write_rows, 100)
	actual.active = false
	expected.active = false
	measure("stereo_update_reference", func() -> void: expected.update(1.0 / 90.0))
	measure("stereo_update_optimized", func() -> void: actual.update(1.0 / 90.0))


func _remote() -> void:
	var player: Node = load("res://scripts/player.gd").new()
	var actual: Node = references.TrackedRemote.new()
	var expected: Node = references.ReferenceRemote.new()
	for remote in [actual, expected]:
		remote.player = player
		remote.server = TCPServer.new()
		check(remote.server.listen(0, "127.0.0.1") == OK, "remote performance server listens on loopback")
	measure("remote_idle_reference", func() -> void: expected._process(1.0 / 90.0), 2000)
	measure("remote_idle_optimized", func() -> void: actual._process(1.0 / 90.0), 2000)
	check(actual.status_calls == 0, "remote builds no playback status without clients")
	for connection in 2:
		var client := StreamPeerTCP.new()
		check(client.connect_to_host("127.0.0.1", actual.server.get_local_port()) == OK, "remote client connects or reconnects")
		var first := await _packet(actual, client)
		check(first.get("ok", false), "remote sends initial status after connection")
		player.current_path = "user://remote-performance-%d.wav" % connection
		var changed := await _packet(actual, client, player.current_path)
		check(changed.get("message", {}).get("path", "") == player.current_path, "remote immediately sends changed playback state")
		var body := JSON.stringify({"playbackSpeed": 1.25 + connection * 0.25}).to_utf8_buffer()
		var command := PackedByteArray()
		command.resize(4)
		command.encode_u32(0, body.size())
		command.append_array(body)
		check(client.put_data(command) == OK, "remote transport command sends")
		var deadline := Time.get_ticks_msec() + 1000
		while root.get_node("Settings").playback_speed != 1.25 + connection * 0.25 and Time.get_ticks_msec() < deadline:
			actual._process(1.0 / 90.0)
			await process_frame
		check(root.get_node("Settings").playback_speed == 1.25 + connection * 0.25, "remote transport command applies")
		client.disconnect_from_host()
		deadline = Time.get_ticks_msec() + 1000
		while actual.client_count() > 0 and Time.get_ticks_msec() < deadline:
			actual._process(1.0 / 90.0)
			await process_frame
		check(actual.client_count() == 0, "remote releases disconnected client")
		var calls: int = actual.status_calls
		for frame in 10:
			actual._process(1.0 / 90.0)
		check(actual.status_calls == calls, "remote stops status work after last disconnect")
	actual._stop()
	expected._stop()
	actual.free()
	expected.free()
	player.free()


func _packet(remote: Node, client: StreamPeerTCP, path := "") -> Dictionary:
	var buffer := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		remote._process(1.0 / 90.0)
		client.poll()
		var available := client.get_available_bytes()
		if available > 0:
			var chunk := client.get_data(available)
			if chunk[0] == OK:
				buffer.append_array(chunk[1])
		while buffer.size() >= 4:
			var length := buffer.decode_u32(0)
			if buffer.size() < 4 + length:
				break
			var message: Dictionary = JSON.parse_string(buffer.slice(4, 4 + length).get_string_from_utf8()) if length > 0 else {}
			buffer = buffer.slice(4 + length)
			if path.is_empty() or message.get("path", "") == path:
				return {"ok": true, "message": message}
		await process_frame
	return {"ok": false}
