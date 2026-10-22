extends "res://scripts/radio_directory.gd"

var calls: Array[String] = []
var fail := false
var slow := false
var quality_mode := false


func _fetch(url: String, _serial: int) -> Dictionary:
	calls.append(url)
	var delayed := slow
	for i in (12 if delayed else 1):
		await get_tree().process_frame
	if fail or url.begins_with("https://bad.example"):
		return {}
	if url.ends_with("/json/servers"):
		return {"data": [{"name": "test.api.radio-browser.info"}]}
	if "/json/countries" in url:
		return {"data": [{"name": "Greece", "iso_3166_1": "GR"}]}
	if "/json/languages" in url:
		return {"data": [{"name": "greek"}]}
	var rows := []
	var start := url.get_slice("offset=", 1).get_slice("&", 0).to_int()
	if quality_mode:
		if "codec=FLAC" in url:
			return {"data": [{"name": "Direct FLAC", "url": "https://stream.example/direct.flac", "codec": "FLAC"}] if start == 0 else []}
		if "codec=OGG" not in url:
			return {"data": []}
		if start == 0:
			for i in PAGE_SIZE:
				rows.append({"name": "Vorbis %d" % i, "url": "https://stream.example/ogg/%d" % i, "codec": "OGG"})
			return {"data": rows}
		return {"data": [
			{"name": "Ogg FLAC", "url": "https://stream.example/main-flacm", "codec": "OGG"},
			{"name": "Ogg Opus", "url": "https://stream.example/stream.opus", "codec": "OGG"},
			{"name": "FLAC Radio MP3", "url": "https://stream.example/stream.mp3", "codec": "MP3"},
			{"name": "Direct FLAC", "url": "https://stream.example/direct.flac", "codec": "OGG"},
		]}
	for i in PAGE_SIZE:
		rows.append({"name": "Old" if delayed else "Station %d" % (start + i), "url_resolved": "https://stream.example/%d" % (start + i), "stationuuid": "uuid-%d" % i, "country": "Greece", "language": "greek", "codec": "MP3", "bitrate": 128, "lastcheckok": 1})
	rows.append(rows[0])
	rows.append({"url": "file:///tmp/private.mp3"})
	return {"data": rows}

