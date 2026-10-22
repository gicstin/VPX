extends Node

signal changed
signal catalogs_changed

const PAGE_SIZE := 40
const MAX_RESULTS := 240
const HEADERS := ["User-Agent: VPX/0.0.5 (radio discovery)", "Accept: application/json"]
const BOOTSTRAP := "https://all.api.radio-browser.info"
const FALLBACK := "https://de1.api.radio-browser.info"
static var ogg_codec_pattern := RegEx.create_from_string("(^|[^a-z0-9])(flacm?|opus)([^a-z0-9]|$)")

var servers: Array[String] = []
var stations: Array[Dictionary] = []
var countries: Array[Dictionary] = []
var languages: Array[Dictionary] = []
var filters := {}
var busy := false
var started := false
var has_more := false
var error := ""
var offset := 0
var codec_ends := {}
var generation := 0
var requests: Array[HTTPRequest] = []


func search(query: Dictionary, append := false) -> void:
	cancel()
	started = true
	if not append or query != filters:
		stations.clear()
		offset = 0
		codec_ends.clear()
	filters = query.duplicate()
	error = ""
	busy = true
	has_more = false
	changed.emit()
	_search(generation)


func cancel() -> void:
	generation += 1
	for request in requests:
		request.cancel_request()
		request.queue_free()
	requests.clear()
	busy = false


func _search(serial: int) -> void:
	if servers.is_empty():
		var mirrors := await _fetch(BOOTSTRAP + "/json/servers", serial)
		if serial != generation:
			return
		servers = mirror_urls(mirrors.get("data"))
		servers.shuffle()
		if FALLBACK not in servers:
			servers.append(FALLBACK)
	var result := await _search_page(filters, offset, serial)
	if serial != generation:
		return
	busy = false
	if not result.get("data") is Array:
		error = "Radio directory unavailable. Check your connection, then Retry. Saved stations still work."
	else:
		var raw: Array = result["data"]
		var seen := {}
		for station in stations:
			seen[station["url"]] = true
		for value: Variant in raw:
			var station := normalize_station(value)
			if station.is_empty() or seen.has(station["url"]):
				continue
			seen[station["url"]] = true
			stations.append(station)
			if stations.size() >= MAX_RESULTS:
				break
		offset = int(result.get("next_offset", offset + raw.size()))
		has_more = bool(result.get("has_more", raw.size() >= PAGE_SIZE)) and stations.size() < MAX_RESULTS and filters.get("order") != "random"
	changed.emit()
	if countries.is_empty() or languages.is_empty():
		_load_catalogs(serial)


func _search_page(query: Dictionary, start: int, serial: int) -> Dictionary:
	var wanted := str(query.get("codec", "")).to_upper()
	if wanted not in ["FLAC", "OPUS"]:
		return await _api(search_path(query, start), serial)
	var rows := []
	var more := true
	while rows.is_empty() and more and serial == generation:
		more = false
		for codec in [wanted, "OGG"]:
			if codec_ends.has(codec) and start >= int(codec_ends[codec]):
				continue
			var candidate_query := query.duplicate()
			candidate_query["codec"] = codec
			var response := await _api(search_path(candidate_query, start), serial)
			if serial != generation or not response.get("data") is Array:
				return {}
			var candidates: Array = response["data"]
			if candidates.size() < PAGE_SIZE:
				codec_ends[codec] = start + candidates.size()
			more = more or candidates.size() >= PAGE_SIZE
			for value: Variant in candidates:
				if normalize_station(value).get("codec", "").to_upper() == wanted:
					rows.append(value)
		start += PAGE_SIZE
	return {"data": rows, "next_offset": start, "has_more": more}


func _load_catalogs(serial: int) -> void:
	for kind in ["countries", "languages"]:
		if not get(kind).is_empty():
			continue
		var response := await _api("/json/%s?hidebroken=true" % kind, serial)
		if serial != generation:
			return
		var data: Variant = response.get("data")
		if not data is Array:
			continue
		var rows: Array[Dictionary] = []
		for value: Variant in data:
			if value is Dictionary and value.get("name") is String and not value["name"].strip_edges().is_empty():
				rows.append(value)
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"].naturalnocasecmp_to(b["name"]) < 0)
		set(kind, rows)
		catalogs_changed.emit()


func _api(path: String, serial: int) -> Dictionary:
	for server in servers.duplicate():
		var result := await _fetch(server + path, serial)
		if serial != generation:
			return {}
		if result.get("data") is Array:
			servers.erase(server)
			servers.push_front(server)
			return result
	return {}


func _fetch(url: String, serial: int) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.body_size_limit = 2 * 1024 * 1024
	request.max_redirects = 3
	add_child(request)
	requests.append(request)
	var reply := {}
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		reply["done"] = true
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			reply["data"] = JSON.parse_string(body.get_string_from_utf8()))
	if request.request(url, HEADERS) == OK:
		while reply.is_empty() and serial == generation:
			await get_tree().process_frame
	if serial != generation:
		return {}
	requests.erase(request)
	request.queue_free()
	return reply


func count_play(station: Dictionary) -> void:
	var uuid := str(station.get("uuid", ""))
	if uuid.is_empty() or servers.is_empty():
		return
	_fetch(servers[0] + "/json/url/" + uuid.uri_encode(), generation)


static func mirror_urls(value: Variant) -> Array[String]:
	var urls: Array[String] = []
	if value is Array:
		for row: Variant in value:
			if not row is Dictionary:
				continue
			var host := str(row.get("name", "")).to_lower()
			if not host.ends_with(".api.radio-browser.info") or host.trim_suffix(".api.radio-browser.info").is_empty():
				continue
			if host.validate_filename() != host or host.contains(":") or host.contains("@") or host.contains(" "):
				continue
			var url := "https://" + host
			if url not in urls:
				urls.append(url)
	return urls


static func search_path(query: Dictionary, start: int) -> String:
	var parts := PackedStringArray(["hidebroken=true", "limit=%d" % PAGE_SIZE, "offset=%d" % maxi(start, 0)])
	var order := str(query.get("order", "clickcount"))
	if order not in ["clickcount", "clicktrend", "random"]:
		order = "clickcount"
	parts.append("order=" + order)
	parts.append("reverse=true")
	for key in ["name", "tag", "countrycode", "language", "codec"]:
		var value := str(query.get(key, "")).strip_edges()
		if not value.is_empty():
			parts.append(key + "=" + value.uri_encode())
	for key in ["bitrateMin", "bitrateMax"]:
		if query.has(key):
			parts.append("%s=%d" % [key, clampi(int(query[key]), 0, 1000000)])
	return "/json/stations/search?" + "&".join(parts)


static func normalize_station(value: Variant) -> Dictionary:
	if not value is Dictionary or int(value.get("lastcheckok", 1)) != 1:
		return {}
	var url := str(value.get("url_resolved", "")).strip_edges()
	if not stream_url(url):
		url = str(value.get("url", "")).strip_edges()
	if not stream_url(url):
		return {}
	var name := str(value.get("name", "")).strip_edges().left(200)
	var codec := str(value.get("codec", "")).strip_edges().to_upper().left(20)
	if codec == "OGG":
		var declared := ogg_codec_pattern.search((name + " " + url.get_slice("?", 0).get_slice("#", 0)).to_lower())
		if declared != null:
			codec = "FLAC" if declared.get_string(2).begins_with("flac") else "OPUS"
	return {"url": url, "name": name if not name.is_empty() else url.get_slice("://", 1).get_slice("/", 0),
		"uuid": str(value.get("stationuuid", "")), "country": str(value.get("country", "")).left(100),
		"language": str(value.get("language", "")).left(100), "tags": str(value.get("tags", "")).left(180),
		"codec": codec, "bitrate": clampi(int(value.get("bitrate", 0)), 0, 10000)}


static func stream_url(url: String) -> bool:
	return (url.begins_with("https://") or url.begins_with("http://")) and not url.get_slice("://", 1).get_slice("/", 0).is_empty() and not url.contains("\n") and not url.contains("\r")


static func remember(station: Dictionary) -> void:
	var url := str(station.get("url", ""))
	if stream_url(url):
		Library.set_pref(url, "title", station["name"])
		Library.set_pref(url, "radio_station", station.duplicate())


static func description(station: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in ["country", "language", "tags", "codec"]:
		var value := str(station.get(key, "")).strip_edges()
		if not value.is_empty():
			parts.append(value)
	if int(station.get("bitrate", 0)) > 0:
		parts.append("%d kbps" % int(station["bitrate"]))
	return " · ".join(parts)


func _exit_tree() -> void:
	cancel()
