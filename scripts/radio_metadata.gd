extends Node

signal changed

const POLL_SECONDS := 5.0
const MAX_IMAGE_BYTES := 8 * 1024 * 1024

var path := ""
var source := ""
var metadata := {}
var artwork: Texture2D
var api_url := ""
var stream_data := {}
var api_data := {}
var embedded := PackedByteArray()
var artwork_key := ""
var generation := 0
var artwork_serial := 0
var poll_left := 0.0
var api_request: HTTPRequest
var art_request: HTTPRequest


func follow(media_path: String, stream_url: String) -> void:
	if path == media_path and source == stream_url:
		return
	generation += 1
	_cancel(api_request)
	_cancel(art_request)
	api_request = null
	art_request = null
	path = media_path
	source = stream_url
	metadata.clear()
	stream_data.clear()
	api_data.clear()
	embedded = PackedByteArray()
	artwork = null
	artwork_key = ""
	api_url = provider_url(stream_url)
	poll_left = 0.0
	changed.emit()


static func provider_url(url: String) -> String:
	var host := url.get_slice("://", 1).get_slice("/", 0).get_slice(":", 0).to_lower()
	if host != "stream.radioparadise.com":
		return ""
	var name := url.get_slice("?", 0).get_slice("#", 0).get_file().to_lower()
	var channel := -1
	if name in ["flacm", "flac", "mp3-192", "mp3-128", "aac-320", "aac-128", "aac-64", "aac-32"]:
		channel = 0
	elif name.begins_with("mellow-"):
		channel = 1
	elif name.begins_with("rock-"):
		channel = 2
	elif name.begins_with("world-etc-"):
		channel = 3
	return "https://api.radioparadise.com/api/now_playing?chan=%d" % channel if channel >= 0 else ""


func apply_stream(raw: Dictionary) -> void:
	var tags: Dictionary = raw.get("radio_tags", {})
	var data := normalize(tags)
	var bytes: PackedByteArray = raw.get("artwork_data", PackedByteArray())
	if data == stream_data and bytes == embedded:
		return
	stream_data = data
	embedded = bytes
	if api_url.is_empty():
		api_url = image_url(str(tags.get("icy-metadata-url", tags.get("metadata_url", ""))))
	_refresh()


static func normalize(tags: Dictionary) -> Dictionary:
	var result := {}
	var aliases := {
		"title": ["title", "streamtitle"], "artist": ["artist", "album_artist"],
		"album": ["album"], "year": ["year", "date"], "station": ["station", "icy-name"],
		"cover": ["cover_med", "cover", "artwork_url", "artwork", "coverurl", "streamartwork", "icy-logo"]}
	for key: String in aliases:
		for name: String in aliases[key]:
			var value: Variant = tags.get(name, "")
			if value is String and not value.strip_edges().is_empty():
				result[key] = value.strip_edges().left(4096)
				break
	var title := str(result.get("title", ""))
	if not result.has("artist") and title.contains(" - "):
		result["artist"] = title.get_slice(" - ", 0)
		result["title"] = title.substr(title.find(" - ") + 3)
	if not result.has("cover"):
		var link := str(tags.get("streamurl", ""))
		if link.get_slice("?", 0).get_extension().to_lower() in ["jpg", "jpeg", "png", "webp"]:
			result["cover"] = link
	return result


static func image_url(value: String) -> String:
	return value if value.begins_with("https://") or value.begins_with("http://") else ""


func _process(delta: float) -> void:
	if path.is_empty() or api_url.is_empty():
		return
	poll_left -= delta
	if poll_left > 0.0 or api_request != null:
		return
	poll_left = POLL_SECONDS
	var serial := generation
	var request := _request(256 * 1024)
	api_request = request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if serial != generation:
			return
		api_request = null
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and (data.get("title") is String or data.get("artist") is String):
			api_data = normalize(data)
			_refresh())
	if request.request(api_url) != OK:
		api_request = null
		request.queue_free()


func _refresh() -> void:
	var combined := stream_data.duplicate()
	combined.merge(api_data, true)
	var url := image_url(str(combined.get("cover", "")))
	var key := url if not url.is_empty() else (str(hash(embedded)) if not embedded.is_empty() else "")
	var dirty := combined != metadata
	metadata = combined
	if key != artwork_key:
		artwork_key = key
		artwork_serial += 1
		_cancel(art_request)
		art_request = null
		artwork = null
		dirty = true
		if not url.is_empty():
			_download_art(url, generation, artwork_serial)
		elif not embedded.is_empty():
			artwork = decode_art(embedded)
	elif artwork == null and art_request == null and not url.is_empty():
		_download_art(url, generation, artwork_serial)
	if dirty:
		changed.emit()


func _download_art(url: String, serial: int, art_serial: int) -> void:
	var request := _request(MAX_IMAGE_BYTES)
	art_request = request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if serial != generation or art_serial != artwork_serial:
			return
		art_request = null
		request.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			artwork = decode_art(body)
			changed.emit())
	if request.request(url) != OK:
		art_request = null
		request.queue_free()


static func decode_art(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 12 or bytes.size() > MAX_IMAGE_BYTES:
		return null
	var image := Image.new()
	var result := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 137 and bytes.slice(1, 4).get_string_from_ascii() == "PNG":
		result = image.load_png_from_buffer(bytes)
	elif bytes[0] == 255 and bytes[1] == 216:
		result = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		result = image.load_webp_from_buffer(bytes)
	if result != OK or image.is_empty():
		return null
	if maxi(image.get_width(), image.get_height()) > 1024:
		var scale := 1024.0 / maxi(image.get_width(), image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)))
	return ImageTexture.create_from_image(image)


func _request(limit: int) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.max_redirects = 5
	request.body_size_limit = limit
	add_child(request)
	return request


func _cancel(request: HTTPRequest) -> void:
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()


func _exit_tree() -> void:
	generation += 1
	_cancel(api_request)
	_cancel(art_request)
