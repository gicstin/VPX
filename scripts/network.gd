extends Node

signal mounted(url: String, path: String)
signal mount_failed(url: String, message: String)
signal servers_changed

const BackgroundTask := preload("res://scripts/background_task.gd")
const MOUNT_TIMEOUT := 30.0
const SSDP_ADDRESS := "239.255.255.250"
const SSDP_PORT := 1900
const SEARCH_TARGET := "urn:schemas-upnp-org:service:ContentDirectory:1"
const SEARCH_SECONDS := 3.0
const BROWSE_LIMIT := 500
const DIRECT_SCHEMES := ["http", "https", "ftp", "rtsp", "rtmp", "rtmps", "srt", "udp", "rtp"]
const SOAP_BROWSE := """<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>%s</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>%d</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>"""

var media_servers: Array[Dictionary] = []
var socket: PacketPeerUDP
var search_left := 0.0
var locations := {}
var mount_job: Node
var mount_url := ""
var mounted_is_directory := false
var mount_serial := 0


func _process(delta: float) -> void:
	if socket == null:
		return
	while socket.get_available_packet_count() > 0:
		_read_ssdp(socket.get_packet().get_string_from_utf8())
	search_left -= delta
	if search_left <= 0.0:
		socket.close()
		socket = null


static func normalize_url(text: String, share := false) -> Dictionary:
	var url := text.strip_edges()
	if url.is_empty():
		return {"ok": false, "error": "Enter a link or network share"}
	for i in url.length():
		if url.unicode_at(i) < 32 or url.unicode_at(i) == 127:
			return {"ok": false, "error": "Link contains invalid characters"}
	if url.begins_with("\\\\"):
		url = "smb://" + url.substr(2).replace("\\", "/")
	var duplicate := RegEx.create_from_string("(?i)^https?://(https?):?//")
	var repeated := duplicate.search(url)
	if repeated != null:
		url = repeated.get_string(1).to_lower() + "://" + url.substr(repeated.get_end())
	if not url.contains("://"):
		url = ("smb://" if share else "https://") + url
	var split := url.find("://")
	url = url.substr(0, split).to_lower() + url.substr(split)
	var kind := scheme(url)
	if kind not in DIRECT_SCHEMES + ["smb", "sftp", "webdav", "webdavs", "dav", "davs", "nfs"]:
		return {"ok": false, "error": "Unsupported link protocol"}
	var authority := url.substr(split + 3).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	if authority.is_empty() or authority.contains(" ") or authority.ends_with("@"):
		return {"ok": false, "error": "Link needs a valid host"}
	return {"ok": true, "url": url}


static func scheme(url: String) -> String:
	var index := url.find("://")
	return url.substr(0, index).to_lower() if index > 0 else ""


static func plays_directly(url: String, media_extensions: Array) -> bool:
	var kind := scheme(url)
	if kind not in DIRECT_SCHEMES:
		return false
	if kind in ["http", "https"]:
		return true
	var name := url.get_slice("?", 0).get_file()
	return kind in ["rtsp", "rtmp", "rtmps", "srt", "udp", "rtp"] or name.get_extension().to_lower() in media_extensions


static func display_name(url: String) -> String:
	var rest := url.substr(url.find("://") + 3) if url.contains("://") else url
	if rest.contains("@"):
		rest = rest.substr(rest.rfind("@") + 1)
	return rest.trim_suffix("/").uri_decode()


static func strip_password(url: String) -> String:
	var start := url.find("://") + 3
	var at := url.find("@", start)
	if start < 3 or at < 0:
		return url
	var credentials := url.substr(start, at - start)
	if not credentials.contains(":"):
		return url
	return url.substr(0, start) + credentials.get_slice(":", 0) + url.substr(at)


func is_mounting() -> bool:
	return not mount_url.is_empty()


func mount(url: String) -> void:
	cancel_mount()
	mount_url = url
	var serial := mount_serial
	var result := await _mount(url, serial, Time.get_ticks_msec() + int(MOUNT_TIMEOUT * 1000.0))
	if serial != mount_serial:
		return
	mount_job = null
	mount_url = ""
	if result.get("path", "").is_empty():
		Log.warn("mount %s failed: %s" % [strip_password(url), result.get("error", "")])
		mount_failed.emit(url, result.get("error", "Could not connect"))
	else:
		Log.info("mounted %s at %s" % [strip_password(url), result["path"]])
		mounted_is_directory = result.get("is_directory", false)
		mounted.emit(url, result["path"])


func cancel_mount() -> void:
	mount_serial += 1
	mount_url = ""
	if is_instance_valid(mount_job):
		mount_job.cancel()
	mount_job = null


func _exit_tree() -> void:
	cancel_mount()


func _command(program: String, arguments: PackedStringArray, serial: int, deadline: int) -> Dictionary:
	if serial != mount_serial:
		return {"ok": false, "cancelled": true}
	var remaining := (deadline - Time.get_ticks_msec()) / 1000.0
	if remaining <= 0.0:
		return {"ok": false, "error": "Operation timed out"}
	var job := BackgroundTask.command(program, arguments, remaining)
	mount_job = job
	var result: Dictionary = await job.completed
	if mount_job == job:
		mount_job = null
	return result


func _check_path(path: String, serial: int, deadline: int) -> Dictionary:
	if serial != mount_serial:
		return {"ok": false, "cancelled": true}
	var remaining := (deadline - Time.get_ticks_msec()) / 1000.0
	if remaining <= 0.0:
		return {"ok": false, "error": "Operation timed out"}
	var job := BackgroundTask.start(_path_info.bind(path), remaining)
	mount_job = job
	var result: Dictionary = await job.completed
	if mount_job == job:
		mount_job = null
	return result


static func _path_info(token: RefCounted, path: String) -> Dictionary:
	var directory := DirAccess.dir_exists_absolute(path)
	if token.is_cancelled():
		return {"ok": false, "cancelled": true}
	if directory or FileAccess.file_exists(path):
		return {"ok": true, "path": path, "is_directory": directory}
	return {"ok": false, "error": "Could not open " + path}


func _mount(url: String, serial: int, deadline: int) -> Dictionary:
	var kind := scheme(url)
	if OS.get_name() == "Windows":
		if kind != "smb":
			return {"error": "Only Windows / Samba shares are supported on Windows"}
		var result := await _check_path(_windows_share_path(url), serial, deadline)
		if not result.get("ok", false) and not result.get("cancelled", false) and result.get("error") != "Operation timed out":
			result["error"] = "Could not open the share (sign in to the share in File Explorer first)"
		return result
	if _has_command("busctl"):
		var kio_url := url
		if kind == "dav":
			kio_url = "webdav" + url.substr(3)
		elif kind == "davs":
			kio_url = "webdavs" + url.substr(4)
		var result := await _command("busctl", ["--user", "--timeout=30", "call", "org.kde.KIOFuse", "/org/kde/KIOFuse", "org.kde.KIOFuse.VFS", "mountUrl", "s", kio_url], serial, deadline)
		if serial != mount_serial or result.get("cancelled", false) or result.get("error") == "Operation timed out":
			return result
		var text := str(result.get("output", "")).strip_edges()
		if result.get("ok", false) and text.begins_with("s \""):
			var checked := await _check_path(_unescape_busctl(text.substr(3, text.length() - 4)), serial, deadline)
			if checked.get("ok", false) or serial != mount_serial or checked.get("error") == "Operation timed out":
				return checked
		elif not _has_command("gio"):
			return {"error": str(result.get("error", "")) if not str(result.get("error", "")).is_empty() else "Could not connect"}
	if serial != mount_serial:
		return {"cancelled": true}
	if _has_command("gio"):
		var gio_url := url
		if kind == "webdav":
			gio_url = "dav" + url.substr(6)
		elif kind == "webdavs":
			gio_url = "davs" + url.substr(7)
		var mounted_result := await _command("gio", ["mount", gio_url], serial, deadline)
		if serial != mount_serial or mounted_result.get("cancelled", false) or mounted_result.get("error") == "Operation timed out":
			return mounted_result
		var info := await _command("gio", ["info", gio_url], serial, deadline)
		if serial != mount_serial or info.get("cancelled", false) or info.get("error") == "Operation timed out":
			return info
		for line: String in str(info.get("output", "")).split("\n"):
			if line.strip_edges().begins_with("local path:"):
				return await _check_path(line.split(":", true, 1)[1].strip_edges(), serial, deadline)
		return {"error": str(mounted_result.get("error", "")) if not str(mounted_result.get("error", "")).strip_edges().is_empty() else "Could not connect"}
	return {"error": "Network shares need kio-fuse (KDE) or gvfs (GNOME)"}


static func _unescape_busctl(text: String) -> String:
	var bytes := PackedByteArray()
	var i := 0
	var raw := text.to_utf8_buffer()
	while i < raw.size():
		if raw[i] == 92 and i + 1 < raw.size():
			var next := raw[i + 1]
			if next >= 48 and next <= 55 and i + 3 < raw.size():
				bytes.append((next - 48) * 64 + (raw[i + 2] - 48) * 8 + (raw[i + 3] - 48))
				i += 4
				continue
			bytes.append(next)
			i += 2
			continue
		bytes.append(raw[i])
		i += 1
	return bytes.get_string_from_utf8()


static func _windows_share_path(url: String) -> String:
	var rest := url.substr(url.find("://") + 3)
	var host_end := rest.find("/")
	var host := rest.substr(0, host_end if host_end >= 0 else rest.length())
	host = host.substr(host.rfind("@") + 1)
	var share_path := rest.substr(host_end) if host_end >= 0 else ""
	var path := ("\\\\" + host + share_path.uri_decode()).replace("/", "\\").trim_suffix("\\")
	return path


func _has_command(command: String) -> bool:
	for folder in OS.get_environment("PATH").split(":"):
		if FileAccess.file_exists(folder.path_join(command)):
			return true
	return false


func discover() -> void:
	if socket != null:
		socket.close()
	socket = PacketPeerUDP.new()
	if socket.bind(0) != OK:
		socket = null
		return
	socket.set_broadcast_enabled(true)
	socket.set_dest_address(SSDP_ADDRESS, SSDP_PORT)
	var request := "M-SEARCH * HTTP/1.1\r\nHOST: %s:%d\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: %s\r\n\r\n" % [SSDP_ADDRESS, SSDP_PORT, SEARCH_TARGET]
	for attempt in 2:
		socket.put_packet(request.to_utf8_buffer())
	search_left = SEARCH_SECONDS


func is_searching() -> bool:
	return socket != null


func _read_ssdp(text: String) -> void:
	for line in text.split("\r\n"):
		if line.to_lower().begins_with("location:"):
			var location := line.substr(9).strip_edges()
			if not locations.has(location):
				locations[location] = true
				_fetch_description(location)


func _fetch_description(location: String) -> void:
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			locations.erase(location)
			return
		var server := parse_description(body, location)
		if server.is_empty():
			return
		for existing in media_servers:
			if existing["control"] == server["control"]:
				return
		media_servers.append(server)
		Log.info("media server %s at %s" % [server["name"], server["control"]])
		servers_changed.emit())
	if request.request(location) != OK:
		request.queue_free()
		locations.erase(location)


static func parse_description(body: PackedByteArray, location: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(body) != OK:
		return {}
	var name := ""
	var base := ""
	var control := ""
	var service_type := ""
	var element := ""
	var in_service := false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				element = parser.get_node_name()
				if element == "service":
					in_service = true
					service_type = ""
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "service":
					in_service = false
				element = ""
			XMLParser.NODE_TEXT:
				var value := parser.get_node_data().strip_edges()
				if value.is_empty():
					continue
				if element == "friendlyName" and name.is_empty():
					name = value
				elif element == "URLBase":
					base = value
				elif in_service and element == "serviceType":
					service_type = value
				elif in_service and element == "controlURL" and service_type.contains("ContentDirectory") and control.is_empty():
					control = value
	if control.is_empty():
		return {}
	return {"name": name if not name.is_empty() else display_name(location), "control": resolve(base if not base.is_empty() else location, control)}


static func resolve(base: String, relative: String) -> String:
	if relative.contains("://"):
		return relative
	var host_end := base.find("/", base.find("://") + 3)
	var origin := base if host_end < 0 else base.substr(0, host_end)
	if relative.begins_with("/"):
		return origin + relative
	var folder := base.substr(0, base.rfind("/") + 1) if host_end >= 0 else origin + "/"
	return folder + relative


func browse(control: String, object_id: String, done: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			Log.warn("browse %s %s failed: result %d http %d" % [control, object_id, result, code])
			done.call({"error": "The media server did not answer"})
			return
		done.call(parse_browse(body)))
	var headers := PackedStringArray(["Content-Type: text/xml; charset=\"utf-8\"", "SOAPACTION: \"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\""])
	if request.request(control, headers, HTTPClient.METHOD_POST, SOAP_BROWSE % [object_id.xml_escape(), BROWSE_LIMIT]) != OK:
		request.queue_free()
		done.call({"error": "Could not reach the media server"})


static func parse_browse(body: PackedByteArray) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(body) != OK:
		return {"error": "Unreadable answer"}
	var didl := ""
	var in_result := false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				in_result = parser.get_node_name() == "Result"
			XMLParser.NODE_ELEMENT_END:
				in_result = false
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if in_result:
					didl += parser.get_node_data()
	return parse_didl(didl)


static func parse_didl(didl: String) -> Dictionary:
	var containers: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var parser := XMLParser.new()
	if didl.is_empty() or parser.open_buffer(didl.to_utf8_buffer()) != OK:
		return {"containers": containers, "items": items}
	var current := {}
	var element := ""
	var res_attributes := {}
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				element = parser.get_node_name()
				if element == "container" or element == "item":
					current = {"kind": element, "id": parser.get_named_attribute_value_safe("id"), "title": "", "url": "", "class": "", "count": parser.get_named_attribute_value_safe("childCount")}
				elif element == "res":
					res_attributes = {"protocol": parser.get_named_attribute_value_safe("protocolInfo"), "duration": parser.get_named_attribute_value_safe("duration"), "resolution": parser.get_named_attribute_value_safe("resolution")}
			XMLParser.NODE_TEXT:
				if current.is_empty():
					continue
				var value := parser.get_node_data().strip_edges()
				if element == "dc:title" and current["title"].is_empty():
					current["title"] = value
				elif element == "upnp:class":
					current["class"] = value
				elif element == "res" and current["url"].is_empty() and not value.is_empty():
					current["url"] = value
					current["protocol"] = res_attributes.get("protocol", "")
					current["duration"] = res_attributes.get("duration", "")
					current["resolution"] = res_attributes.get("resolution", "")
			XMLParser.NODE_ELEMENT_END:
				var name := parser.get_node_name()
				if (name == "container" or name == "item") and not current.is_empty():
					if name == "container":
						containers.append(current)
					elif not current["url"].is_empty() and (current["class"].contains("videoItem") or current["protocol"].contains(":video/")):
						items.append(current)
					current = {}
				element = ""
	return {"containers": containers, "items": items}


static func parse_duration(text: String) -> float:
	var parts := text.split(":")
	if parts.size() != 3:
		return 0.0
	return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
