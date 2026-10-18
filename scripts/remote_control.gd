extends Node

signal clients_changed(count: int)

const STATUS_INTERVAL := 0.5
const MAX_MESSAGE := 1 << 20
const STATE_PLAYING := 0
const STATE_PAUSED := 1

var player: VPXPlayer
var open_path: Callable
var server: TCPServer
var clients: Array[StreamPeerTCP] = []
var buffers: Array[PackedByteArray] = []
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
			Log.info("remote control: client disconnected")
			clients_changed.emit(clients.size())
			continue
		var available := client.get_available_bytes()
		if available > 0:
			var chunk := client.get_data(available)
			if chunk[0] == OK:
				buffers[i].append_array(chunk[1])
				_drain(i)
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
	if not path.is_empty() and path != player.current_path and open_path.is_valid():
		Log.info("remote control: open %s" % path)
		open_path.call(path)
	if command.has("playbackSpeed"):
		Settings.apply("playback_speed", clampf(float(command["playbackSpeed"]), 0.5, 2.0))
	if command.has("currentTime") and not player.current_path.is_empty():
		player.seek_to(float(command["currentTime"]))
	if command.has("playerState") and not player.current_path.is_empty() and not player.is_image():
		player.paused = int(command["playerState"]) == STATE_PAUSED


func _status() -> Dictionary:
	if player.current_path.is_empty() or player.is_image():
		return {}
	return {
		"path": player.current_path,
		"duration": player.get_stream_length(),
		"currentTime": player.stream_position,
		"playbackSpeed": Settings.playback_speed,
		"playerState": STATE_PAUSED if player.paused or not player.is_playing() else STATE_PLAYING,
	}


func _send(client: StreamPeerTCP, message: Dictionary) -> void:
	var body := JSON.stringify(message).to_utf8_buffer() if not message.is_empty() else PackedByteArray()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, body.size())
	client.put_data(header + body)
