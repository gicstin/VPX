extends Node

signal install_finished(ok: bool, message: String)

const TOOL_DIR := "user://tools"
const TOOL_NAME := "yt-dlp"
const DOWNLOAD_URL := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
const WINDOWS_TOOL_NAME := "yt-dlp.exe"
const WINDOWS_DOWNLOAD_URL := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
const DENO_DOWNLOAD_URL := "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip"
const WINDOWS_DENO_DOWNLOAD_URL := "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
const FORMAT := "bv*+ba/b"
const JOB_TIMEOUT_MSEC := 45000
const DIRECT_EXTENSIONS := ["mp4", "mkv", "webm", "mov", "m4v", "ts", "m3u8", "mpd", "avi", "wmv", "flv", "mpg", "mpeg", "jpg", "jpeg", "png", "webp"]
const RESOLVE_SCRIPT := "if [ -n \"$6\" ]; then exec nice -n 5 \"$1\" -J --ignore-config --no-playlist --socket-timeout 15 --retries 1 --js-runtimes \"$6\" -f \"$2\" \"$3\" > \"$4\" 2> \"$5\"; else exec nice -n 5 \"$1\" -J --ignore-config --no-playlist --socket-timeout 15 --retries 1 -f \"$2\" \"$3\" > \"$4\" 2> \"$5\"; fi"

var tool_path := ""
var runtime_path := ""
var download_stage := "tool"
var jobs := {}
var download: HTTPRequest
var install_message := ""


func _ready() -> void:
	tool_path = find_tool()
	runtime_path = find_runtime()
	if not tool_path.is_empty():
		Log.info("web video: %s" % tool_path)


func available() -> bool:
	return not tool_path.is_empty()


func find_tool() -> String:
	var local := ProjectSettings.globalize_path(TOOL_DIR.path_join(_tool_name()))
	var candidates := [local, OS.get_environment("HOME").path_join(".local/bin/yt-dlp"), "/usr/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	var output := []
	if Shell.run("command -v yt-dlp", [], output) == 0 and not output.is_empty() and not str(output[0]).strip_edges().is_empty():
		return str(output[0]).strip_edges()
	return ""


static func needs_resolve(url: String) -> bool:
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return false
	var authority := url.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	var host := authority.get_slice("@", authority.count("@")).get_slice(":", 0).to_lower()
	if host == "localhost" or host.ends_with(".local") or host.begins_with("10.") or host.begins_with("192.168.") or host.begins_with("127."):
		return false
	if host.begins_with("172.") and int(host.get_slice(".", 1)) >= 16 and int(host.get_slice(".", 1)) <= 31:
		return false
	var name := url.get_slice("?", 0).get_slice("#", 0).get_file()
	return name.get_extension().to_lower() not in DIRECT_EXTENSIONS


static func canonical_url(url: String) -> String:
	if not is_youtube(url):
		return url
	var parts := url.split("#", true, 1)
	var query := parts[0].split("?", true, 1)
	if query.size() < 2:
		return url
	var path := query[0].substr(query[0].find("://") + 3)
	path = path.substr(path.find("/")) if path.contains("/") else "/"
	if path != "/watch" and not path.begins_with("/shorts/") and not path.begins_with("/live/") and not query[0].contains("youtu.be/"):
		return url
	var kept := PackedStringArray()
	for param: String in query[1].split("&"):
		if param.get_slice("=", 0) not in ["list", "index", "start_radio", "pp"]:
			kept.append(param)
	return query[0] + ("?" + "&".join(kept) if not kept.is_empty() else "") + ("#" + parts[1] if parts.size() > 1 else "")


static func playlist_only(url: String) -> bool:
	return is_youtube(url) and url.get_slice("?", 0).trim_suffix("/").ends_with("/playlist")


func resolve(url: String, done: Callable) -> void:
	if playlist_only(url):
		done.call({"ok": false, "error": "Open a video from the playlist, then paste its video link"})
		return
	url = canonical_url(url)
	if tool_path.is_empty():
		done.call({"ok": false, "error": "yt-dlp is not installed"})
		return
	if is_youtube(url) and runtime_path.is_empty():
		done.call({"ok": false, "error": "YouTube needs a JavaScript runtime. Install / update web tools in System → Apps & web."})
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
	var base := ProjectSettings.globalize_path("user://cache/web_%s" % url.md5_text())
	var pid := Shell.spawn(RESOLVE_SCRIPT, [tool_path, FORMAT, url, base + ".json", base + ".err", runtime_path])
	if pid <= 0:
		done.call({"ok": false, "error": "cannot start yt-dlp"})
		return
	jobs[pid] = {"url": url, "base": base, "done": done, "started": Time.get_ticks_msec()}
	Log.info("web video: resolving %s" % url)


func is_busy() -> bool:
	return not jobs.is_empty() or download != null


func _process(_delta: float) -> void:
	for pid: int in jobs.keys():
		var job: Dictionary = jobs[pid]
		if OS.is_process_running(pid):
			if Time.get_ticks_msec() - int(job["started"]) > JOB_TIMEOUT_MSEC:
				OS.kill(pid)
				jobs.erase(pid)
				job["done"].call({"ok": false, "error": "yt-dlp timed out"})
			continue
		jobs.erase(pid)
		var text := FileAccess.get_file_as_string(job["base"] + ".json")
		var error_text := FileAccess.get_file_as_string(job["base"] + ".err").strip_edges()
		DirAccess.remove_absolute(job["base"] + ".json")
		DirAccess.remove_absolute(job["base"] + ".err")
		var result := parse(text)
		if not result["ok"]:
			var lines := error_text.split("\n", false)
			result["error"] = lines[lines.size() - 1].trim_prefix("ERROR: ") if not lines.is_empty() else "no playable video found"
			Log.warn("web video: %s" % result["error"])
		else:
			Log.info("web video: %s (%s)" % [result["title"], "separate audio" if not str(result["audio"]).is_empty() else "single stream"])
		job["done"].call(result)


static func parse(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return {"ok": false}
	var info := data as Dictionary
	var stream := ""
	var audio := ""
	var headers: Dictionary = info.get("http_headers", {})
	var requested: Array = info.get("requested_formats", [])
	if requested.size() >= 2:
		for format: Dictionary in requested:
			if str(format.get("vcodec", "none")) != "none" and stream.is_empty():
				stream = str(format.get("url", ""))
				headers = format.get("http_headers", headers)
			elif str(format.get("acodec", "none")) != "none" and audio.is_empty():
				audio = str(format.get("url", ""))
	if stream.is_empty():
		stream = str(info.get("url", ""))
		audio = ""
	if stream.is_empty():
		return {"ok": false}
	var header_text := ""
	for key: String in headers:
		header_text += "%s: %s\r\n" % [key, headers[key]]
	return {
		"ok": true,
		"stream": stream,
		"audio": audio,
		"headers": header_text,
		"title": str(info.get("title", "")),
		"duration": float(info.get("duration", 0.0)) if info.get("duration") != null else 0.0,
		"thumbnail": str(info.get("thumbnail", "")),
		"start_time": maxf(0.0, float(info.get("start_time", 0.0))) if info.get("start_time") != null else 0.0,
		"width": int(info.get("width", 0)) if info.get("width") != null else 0,
		"height": int(info.get("height", 0)) if info.get("height") != null else 0,
	}


func install() -> void:
	if download != null:
		return
	install_message = ""
	download_stage = "tool"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TOOL_DIR))
	download = HTTPRequest.new()
	download.download_file = ProjectSettings.globalize_path(TOOL_DIR.path_join(_tool_name() + ".part"))
	download.max_redirects = 10
	download.timeout = 60.0
	add_child(download)
	download.request_completed.connect(_on_download_completed)
	var result := download.request(_download_url())
	Log.info("web video: downloading yt-dlp from %s" % _download_url())
	if result != OK:
		_finish_install(false, "download failed to start (%s)" % error_string(result))


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if download_stage == "runtime":
		_finish_runtime_download(result, code)
		return
	var part := ProjectSettings.globalize_path(TOOL_DIR.path_join(_tool_name() + ".part"))
	var target := ProjectSettings.globalize_path(TOOL_DIR.path_join(_tool_name()))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		var reason := "no internet connection" if code == 0 else "HTTP %d" % code
		_finish_install(false, "Could not download yt-dlp: %s" % reason)
		return
	if DirAccess.rename_absolute(part, target) != OK:
		_finish_install(false, "Could not install yt-dlp")
		return
	if not Shell.is_windows():
		OS.execute("chmod", ["+x", target])
	var output := []
	if OS.execute(target, ["--version"], output) != 0:
		_finish_install(false, "downloaded yt-dlp does not run")
		return
	tool_path = target
	if runtime_path.is_empty():
		_download_runtime()
	else:
		_finish_install(true, "Web video tools ready")


func _finish_install(ok: bool, message: String) -> void:
	if download != null:
		download.queue_free()
		download = null
	Log.info("web video: %s" % message)
	install_message = message
	install_finished.emit(ok, message)


func _tool_name() -> String:
	return WINDOWS_TOOL_NAME if Shell.is_windows() else TOOL_NAME


func _download_url() -> String:
	return WINDOWS_DOWNLOAD_URL if Shell.is_windows() else DOWNLOAD_URL


static func is_youtube(url: String) -> bool:
	var host := url.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0).get_slice(":", 0).to_lower()
	return host == "youtu.be" or host == "youtube.com" or host.ends_with(".youtube.com")


func youtube_ready() -> bool:
	return available() and not runtime_path.is_empty()


func find_runtime() -> String:
	var local := ProjectSettings.globalize_path(TOOL_DIR.path_join("deno.exe" if Shell.is_windows() else "deno"))
	if FileAccess.file_exists(local) and _supported_runtime("deno", local):
		return "deno:" + local
	for runtime: String in ["deno", "node"]:
		var output := []
		if Shell.run("command -v " + runtime, [], output) == 0 and not output.is_empty():
			var path := str(output[0]).strip_edges()
			if not path.is_empty() and _supported_runtime(runtime, path):
				return runtime + ":" + path
	return ""


func _download_runtime() -> void:
	if download != null:
		download.queue_free()
	download_stage = "runtime"
	download = HTTPRequest.new()
	download.download_file = ProjectSettings.globalize_path(TOOL_DIR.path_join("deno.zip.part"))
	download.max_redirects = 10
	download.timeout = 60.0
	add_child(download)
	download.request_completed.connect(_on_download_completed)
	var error := download.request(WINDOWS_DENO_DOWNLOAD_URL if Shell.is_windows() else DENO_DOWNLOAD_URL)
	if error != OK:
		_finish_install(false, "Could not start JavaScript runtime download")


func _finish_runtime_download(result: int, code: int) -> void:
	var part := ProjectSettings.globalize_path(TOOL_DIR.path_join("deno.zip.part"))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_finish_install(false, "yt-dlp installed; JavaScript runtime download failed (HTTP %d). Press Install / update to retry." % code)
		return
	var zip := ZIPReader.new()
	var filename := "deno.exe" if Shell.is_windows() else "deno"
	if zip.open(part) != OK or not zip.file_exists(filename):
		zip.close()
		DirAccess.remove_absolute(part)
		_finish_install(false, "JavaScript runtime archive is invalid")
		return
	var bytes := zip.read_file(filename)
	zip.close()
	DirAccess.remove_absolute(part)
	var target := ProjectSettings.globalize_path(TOOL_DIR.path_join(filename))
	var file := FileAccess.open(target + ".part", FileAccess.WRITE)
	if file == null or bytes.is_empty():
		_finish_install(false, "Could not save JavaScript runtime")
		return
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(target + ".part", target) != OK:
		_finish_install(false, "Could not install JavaScript runtime")
		return
	if not Shell.is_windows():
		OS.execute("chmod", ["+x", target])
	if OS.execute(target, ["--version"]) != 0:
		_finish_install(false, "JavaScript runtime does not run")
		return
	runtime_path = "deno:" + target
	_finish_install(true, "Web video tools ready")


func _supported_runtime(runtime: String, path: String) -> bool:
	var output := []
	if OS.execute(path, ["--version"], output) != 0 or output.is_empty():
		return false
	var version := RegEx.create_from_string("(?:^|\\s)v?([0-9]+)\\.([0-9]+)").search(str(output[0]))
	if version == null:
		return false
	var major := version.get_string(1).to_int()
	var minor := version.get_string(2).to_int()
	return major >= 22 if runtime == "node" else (major > 2 or (major == 2 and minor >= 3))


func cancel() -> void:
	for pid: int in jobs:
		if OS.is_process_running(pid):
			OS.kill(pid)
		DirAccess.remove_absolute(jobs[pid]["base"] + ".json")
		DirAccess.remove_absolute(jobs[pid]["base"] + ".err")
	jobs.clear()


func _exit_tree() -> void:
	cancel()
