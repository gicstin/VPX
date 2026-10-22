extends Node

signal clients_changed(count: int)

const STATUS_INTERVAL := 0.5
const MAX_MESSAGE := 1 << 20
const WRITE_BUDGET := 65536
const SEND_TIMEOUT_MSEC := 5000
const STATE_PLAYING := 0
const STATE_PAUSED := 1

var player: VPXPlayer
var open_path: Callable
var opening_path: Callable
var pending_path := ""
var pending_options := {}
var server: TCPServer
var clients: Array[StreamPeerTCP] = []
var buffers: Array[PackedByteArray] = []
var outgoing := {}
var status_timer := 0.0
var last_status := ""
var sent_time := 0.0
var sent_msec := 0
var port := Settings.REMOTE_PORT
var error := ""


func _ready() -> void:
	Settings.changed.connect(_sync_enabled)
	_sync_enabled()


func _exit_tree() -> void:
	_stop()


func is_listening() -> bool:
	return server != null and server.is_listening()


func client_count() -> int:
	return clients.size()


func _sync_enabled() -> void:
	if Settings.remote_control and server == null:
		_start()
	elif not Settings.remote_control and server != null:
		_stop()


func _start() -> void:
	server = TCPServer.new()
	var result := server.listen(port)
	if result != OK:
		error = "Port %d is busy (%s)" % [port, error_string(result)]
		Log.warn("remote control: cannot listen on %d: %s" % [port, error_string(result)])
		server = null
		return
	error = ""
	Log.info("remote control: DeoVR-compatible API on TCP port %d" % port)


func _stop() -> void:
	for client in clients:
		client.disconnect_from_host()
	clients.clear()
	buffers.clear()
	outgoing.clear()
	if server != null:
		server.stop()
		server = null
		Log.info("remote control: stopped")
	clients_changed.emit(0)


func _process(delta: float) -> void:
	if server == null:
		return
	while server.is_connection_available():
		var client := server.take_connection()
		client.set_no_delay(true)
		clients.append(client)
		buffers.append(PackedByteArray())
		Log.info("remote control: client %s connected" % client.get_connected_host())
		clients_changed.emit(clients.size())
		_send(client, _status())
	for i in range(clients.size() - 1, -1, -1):
		var client := clients[i]
		client.poll()
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(i)
			buffers.remove_at(i)
			outgoing.erase(client)
			Log.info("remote control: client disconnected")
			clients_changed.emit(clients.size())
			continue
		var available := client.get_available_bytes()
		if available > 0:
			var chunk := client.get_data(available)
			if chunk[0] == OK:
				buffers[i].append_array(chunk[1])
				_drain(i)
	if clients.is_empty():
		return
	status_timer += delta
	var status := _status()
	var text := "%s|%s|%s" % [status.get("path", ""), status.get("playerState", -1), status.get("playbackSpeed", 1.0)]
	var now := Time.get_ticks_msec()
	var expected := sent_time + (float(now - sent_msec) / 1000.0 * Settings.playback_speed if int(status.get("playerState", STATE_PAUSED)) == STATE_PLAYING else 0.0)
	var jumped := absf(float(status.get("currentTime", 0.0)) - expected) > 0.75
	if status_timer >= STATUS_INTERVAL or text != last_status or jumped:
		status_timer = 0.0
		last_status = text
		sent_time = float(status.get("currentTime", 0.0))
		sent_msec = now
		for client in clients:
			_send(client, status)
	for client in clients:
		_flush(client)


func _drain(index: int) -> void:
	var buffer := buffers[index]
	while buffer.size() >= 4:
		var length := buffer.decode_u32(0)
		if length > MAX_MESSAGE:
			buffer = PackedByteArray()
			break
		if buffer.size() < 4 + length:
			break
		var body := buffer.slice(4, 4 + length)
		buffer = buffer.slice(4 + length)
		if length > 0:
			_handle(body.get_string_from_utf8())
	buffers[index] = buffer


func _handle(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return
	var command := data as Dictionary
	var path := str(command.get("path", ""))
	if command.has("playbackSpeed"):
		Settings.apply("playback_speed", clampf(float(command["playbackSpeed"]), 0.5, 2.0))
	var options := {}
	if command.has("currentTime"):
		options["start_time"] = maxf(0.0, float(command["currentTime"]))
	if command.has("playerState"):
		options["paused"] = int(command["playerState"]) == STATE_PAUSED
	var opening := str(opening_path.call()) if opening_path.is_valid() else (str(player.load_state.get("path", "")) if player.load_state.get("status") == "opening" else "")
	if not opening.is_empty() and (path.is_empty() or path == opening):
		if pending_path == opening:
			pending_options.merge(options, true)
		if player.load_state.get("status") == "opening" and player.load_state.get("path") == opening:
			player.load_options.merge(options, true)
		return
	var active_path := _playback_path()
	if not path.is_empty() and (path != active_path or not opening.is_empty()) and open_path.is_valid():
		Log.info("remote control: open %s" % path)
		pending_path = path
		pending_options = options
		open_path.call(path, pending_options)
		return
	if command.has("currentTime") and not active_path.is_empty():
		player.seek_to(float(command["currentTime"]))
	if command.has("playerState") and not active_path.is_empty():
		player.paused = int(command["playerState"]) == STATE_PAUSED


func _playback_path() -> String:
	return player.music_path if not player.music_path.is_empty() else ("" if player.is_image() else player.current_path)


func _status() -> Dictionary:
	var path := _playback_path()
	if path.is_empty():
		return {}
	return {
		"path": path,
		"duration": player.get_stream_length(),
		"currentTime": player.stream_position,
		"playbackSpeed": Settings.playback_speed,
		"playerState": STATE_PAUSED if player.paused or not player.is_playing() else STATE_PLAYING,
	}


func _send(client: StreamPeerTCP, message: Dictionary) -> void:
	var body := JSON.stringify(message).to_utf8_buffer() if not message.is_empty() else PackedByteArray()
	if body.size() > MAX_MESSAGE:
		client.disconnect_from_host()
		return
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, body.size())
	var packet := header + body
	if not outgoing.has(client):
		outgoing[client] = {"packet": packet, "offset": 0, "next": PackedByteArray(), "progress": Time.get_ticks_msec()}
	else:
		outgoing[client]["next"] = packet


func _flush(client: StreamPeerTCP) -> void:
	if not outgoing.has(client):
		return
	var pending: Dictionary = outgoing[client]
	if Time.get_ticks_msec() - int(pending["progress"]) >= SEND_TIMEOUT_MSEC:
		client.disconnect_from_host()
		outgoing.erase(client)
		return
	var packet: PackedByteArray = pending["packet"]
	var offset: int = pending["offset"]
	var result := client.put_partial_data(packet.slice(offset, mini(offset + WRITE_BUDGET, packet.size())))
	if result[0] != OK:
		client.disconnect_from_host()
		outgoing.erase(client)
		return
	if result[1] > 0:
		pending["progress"] = Time.get_ticks_msec()
		pending["offset"] += int(result[1])
	if int(pending["offset"]) == packet.size():
		if pending["next"].is_empty():
			outgoing.erase(client)
		else:
			pending["packet"] = pending["next"]
			pending["next"] = PackedByteArray()
			pending["offset"] = 0
