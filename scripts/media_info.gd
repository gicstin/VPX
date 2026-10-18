extends Node

signal updated(path: String)

const THUMB_DIR := "user://cache/thumbs"
const INDEX_PATH := "user://cache/media.json"
const THUMB_WIDTH := 480
const THUMB_HEIGHT := 270
const THUMB_ASPECT := 16.0 / 9.0
const MAX_JOBS := 2
const MAX_LOADS := 6
const RESULT_BUDGET_USEC := 2000
const POLL_MSEC := 5
const JOB_TIMEOUT_MSEC := 30000
const FAILURE_RETRY_SECONDS := 600.0
const SAVE_DELAY := 2.0
const MAX_ENTRIES := 5000
const MAX_TEXTURES := 160
const THUMB_POSITION := 0.3
const NICE := "15"
const PROBE_SCRIPT := "exec nice -n %s ffprobe -v error -select_streams V:0 -read_intervals \"%%+#1\" -show_entries stream=width,height,avg_frame_rate,codec_name:stream_tags=stereo_mode:stream_side_data:frame=width,height:frame_tags=stereo_mode:frame_side_data:format=duration -of json \"$1\" > \"$2\""
const AUDIO_THUMB_SCRIPT := "nice -n %s ffmpeg -v error -y -i \"$1\" -map 0:v -frames:v 1 -vf \"$4\" -q:v 3 \"$2\""
const VIDEO_THUMB_SCRIPT := "nice -n %s ffmpeg -v error -y -noaccurate_seek -skip_frame nokey -ss \"$3\" -i \"$1\" -frames:v 1 -an -sn -dn -vf \"$4\" -q:v 3 \"$2\" 2>/dev/null; [ -s \"$2\" ] || exec nice -n 15 ffmpeg -v error -y -i \"$1\" -frames:v 1 -an -sn -dn -vf \"$4\" -q:v 3 \"$2\""
const IMAGE_THUMB_SCRIPT := "exec nice -n %s ffmpeg -v error -y -i \"$1\" -frames:v 1 -vf \"$4\" -q:v 3 \"$2\""
const CROP_SHARE := {
	Settings.ProjectionMode.FLAT: 1.0,
	Settings.ProjectionMode.EQUIRECT_180: 0.62,
	Settings.ProjectionMode.FISHEYE: 0.55,
	Settings.ProjectionMode.EQUIRECT_360: 0.3,
}
const WebVideo := preload("res://scripts/web_video.gd")
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const FormatDetector := preload("res://scripts/format_detector.gd")

var entries := {}
var signatures := {}
var queue: Array[String] = []
var queued := {}
var in_flight := {}
var textures := {}
var texture_order: Array[String] = []
var pending_loads: Array[String] = []
var loading := {}
var verifying := {}
var requested := {}
var invalidated := {}
var dirty := false
var save_timer := 0.0
var available := false
var threads: Array[Thread] = []
var mutex := Mutex.new()
var work_semaphore := Semaphore.new()
var load_semaphore := Semaphore.new()
var work_queue: Array[Dictionary] = []
var load_queue: Array[Dictionary] = []
var results: Array[Dictionary] = []
var quitting := false
var stopped := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMB_DIR))
	_load()
	available = _has_tool("ffmpeg") and _has_tool("ffprobe")
	if not available:
		Log.warn("media info: ffmpeg / ffprobe not found, library shows no thumbnails")
	for i in MAX_JOBS:
		var thread := Thread.new()
		thread.start(_work_loop)
		threads.append(thread)
	var loader := Thread.new()
	loader.start(_load_loop)
	threads.append(loader)


func info(path: String) -> Dictionary:
	var entry: Dictionary = entries.get(path, {})
	if entry.is_empty():
		return {}
	if not signatures.has(path):
		_verify(path)
		return entry
	return entry if entry.get("sig", "") == signatures[path] else {}


func cached(path: String) -> Dictionary:
	return entries.get(path, {})


func file_size(path: String) -> int:
	if not signatures.has(path):
		_verify(path)
		return 0
	var signature: String = signatures[path]
	var colon := signature.find(":")
	return signature.substr(colon + 1).to_int() if colon >= 0 else 0


func forget(path: String) -> void:
	requested.erase(path)
	if queued.has(path):
		queued.erase(path)
		queue.erase(path)


func invalidate(path: String) -> void:
	invalidated[path] = true
	forget(path)
	entries.erase(path)
	signatures.erase(path)
	textures.erase(path)
	texture_order.erase(path)
	pending_loads.erase(path)
	_mark_dirty()


func _verify(path: String) -> void:
	if verifying.has(path) or stopped:
		return
	verifying[path] = true
	_push_load({"stage": "stat", "path": path})


func thumbnail(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var entry := info(path)
	if not entry.get("thumb", "").is_empty() and not loading.has(path) and path not in pending_loads:
		pending_loads.append(path)
	return null


func request(path: String, refresh_signature := false) -> void:
	invalidated.erase(path)
	if WebVideo.needs_resolve(path):
		return
	if refresh_signature:
		signatures.erase(path)
	requested[path] = true
	var entry := info(path)
	if refresh_signature and not entry.is_empty() and (entry.has("failed") or entry.has("thumb_failed")):
		entries.erase(path)
		_mark_dirty()
		entry = {}
	if not entry.is_empty() and (entry.has("failed") or entry.has("thumb_failed")):
		var failed_at := float(entry.get("thumb_failed_at", entry.get("created", 0.0)))
		if Time.get_unix_time_from_system() - failed_at >= FAILURE_RETRY_SECONDS:
			entries.erase(path)
			signatures.erase(path)
			_mark_dirty()
			entry = {}
	if not entry.is_empty():
		thumbnail(path)
		return
	if not available or queued.has(path) or in_flight.has(path):
		return
	queued[path] = true
	queue.append(path)


func prioritize(paths: PackedStringArray) -> void:
	var front: Array[String] = []
	var wanted := {}
	for path in paths:
		if queued.has(path):
			front.append(path)
			wanted[path] = true
	if front.is_empty():
		return
	var rest: Array[String] = []
	for path in queue:
		if not wanted.has(path):
			rest.append(path)
	queue = front + rest


func cancel_pending() -> void:
	queue.clear()
	queued.clear()
	requested.clear()
	pending_loads.clear()


func duration_text(seconds: float) -> String:
	var total := int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func _process(delta: float) -> void:
	while in_flight.size() < MAX_JOBS and not queue.is_empty():
		var path: String = queue.pop_front()
		queued.erase(path)
		_start_probe(path)
	while loading.size() < MAX_LOADS and not pending_loads.is_empty():
		_start_load(pending_loads.pop_front())
	_drain_results()
	if dirty:
		save_timer += delta
		if save_timer >= SAVE_DELAY:
			save(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_stop_workers()
		for job in load_queue:
			if job["stage"] == "save":
				dirty = true
		load_queue.clear()
		save()


func _stop_workers() -> void:
	if stopped:
		return
	stopped = true
	mutex.lock()
	quitting = true
	mutex.unlock()
	for i in MAX_JOBS:
		work_semaphore.post()
	load_semaphore.post()
	for thread in threads:
		if thread.is_started():
			thread.wait_to_finish()
	threads.clear()


func _push_work(job: Dictionary) -> void:
	mutex.lock()
	work_queue.append(job)
	mutex.unlock()
	work_semaphore.post()


func _push_load(job: Dictionary) -> void:
	mutex.lock()
	load_queue.append(job)
	mutex.unlock()
	load_semaphore.post()


func _drain_results() -> void:
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < RESULT_BUDGET_USEC:
		mutex.lock()
		var result: Dictionary = results.pop_front() if not results.is_empty() else {}
		mutex.unlock()
		if result.is_empty():
			return
		match result["stage"]:
			"probe":
				_finish_probe(result)
			"thumb":
				_finish_thumb(result)
			"load":
				_finish_load(result)
			"stat":
				_finish_stat(result)


func _work_loop() -> void:
	while true:
		work_semaphore.wait()
		mutex.lock()
		if quitting:
			mutex.unlock()
			return
		var job: Dictionary = work_queue.pop_front() if not work_queue.is_empty() else {}
		mutex.unlock()
		if job.is_empty():
			continue
		var result := _probe_job(job) if job["stage"] == "probe" else _thumb_job(job)
		result["stage"] = job["stage"]
		result["path"] = job["path"]
		mutex.lock()
		results.append(result)
		mutex.unlock()


func _load_loop() -> void:
	while true:
		load_semaphore.wait()
		mutex.lock()
		if quitting:
			mutex.unlock()
			return
		var job: Dictionary = load_queue.pop_front() if not load_queue.is_empty() else {}
		mutex.unlock()
		if job.is_empty():
			continue
		if job["stage"] == "save":
			_write_index(job["files"])
			continue
		if job["stage"] == "stat":
			var signature := _stat_signature(job["path"])
			mutex.lock()
			results.append({"stage": "stat", "path": job["path"], "sig": signature})
			mutex.unlock()
			continue
		var image := Image.load_from_file(job["file"])
		mutex.lock()
		results.append({"stage": "load", "path": job["path"], "image": image})
		mutex.unlock()


func _is_quitting() -> bool:
	mutex.lock()
	var value := quitting
	mutex.unlock()
	return value


func _run(script: String, args: Array) -> bool:
	var pid := Shell.spawn(script, args)
	if pid <= 0:
		return false
	var started := Time.get_ticks_msec()
	var finished := true
	while OS.is_process_running(pid):
		if _is_quitting() or Time.get_ticks_msec() - started > JOB_TIMEOUT_MSEC:
			OS.kill(pid)
			finished = false
			break
		OS.delay_msec(POLL_MSEC)
	return finished


func _signature(path: String) -> String:
	if signatures.has(path):
		return signatures[path]
	var signature := _stat_signature(path)
	signatures[path] = signature
	return signature


static func _stat_signature(path: String) -> String:
	if path.contains("://"):
		return "url"
	return "%d:%d" % [FileAccess.get_modified_time(path), FileAccess.get_size(path)] if FileAccess.file_exists(path) else ""


func _start_probe(path: String) -> void:
	in_flight[path] = true
	_push_work({"stage": "probe", "path": path, "output": _scratch_path(path, "json")})


func _probe_job(job: Dictionary) -> Dictionary:
	var path: String = job["path"]
	var signature := _stat_signature(path)
	if signature.is_empty():
		return {"sig": signature, "missing": true}
	var result := {"sig": signature}
	if PanoramaFiles.is_image(path):
		var cube := PanoramaFiles.cube_faces(path)
		if cube.size() == PanoramaFiles.CUBE_ORDER.size():
			var source := cube[PanoramaFiles.CUBE_ORDER.find("front")]
			result["cube_source"] = source
			result["face_size"] = PanoramaFiles.probe_size(source)
		if path.get_extension().to_lower() in ["jpg", "jpeg"]:
			var size := PanoramaFiles.probe_size(path)
			if size.x > 0 and size.y > 0:
				result["data"] = {"streams": [{"width": size.x, "height": size.y, "codec_name": "jpeg", "avg_frame_rate": "0/1"}]}
				return result
	if not _run(PROBE_SCRIPT % NICE, [path, job["output"]]):
		result["timeout"] = true
		DirAccess.remove_absolute(job["output"])
		return result
	var text := FileAccess.get_file_as_string(job["output"])
	result["data"] = JSON.parse_string(text) if not text.is_empty() else null
	DirAccess.remove_absolute(job["output"])
	return result


func _thumb_job(job: Dictionary) -> Dictionary:
	if not _run(job["script"], job["args"]):
		return {"timeout": true}
	var output: String = job["output"]
	if not FileAccess.file_exists(output) or FileAccess.get_size(output) <= 0:
		return {"failed": true}
	return {"image": Image.load_from_file(output)}


func _finish_probe(result: Dictionary) -> void:
	if invalidated.has(result["path"]):
		in_flight.erase(result["path"])
		return
	var path: String = result["path"]
	signatures[path] = result["sig"]
	if result.get("missing", false):
		in_flight.erase(path)
		return
	if result.get("timeout", false):
		_store_failure(path, "timeout in probe")
		return
	var data: Variant = result.get("data")
	if not data is Dictionary or (data.get("streams", []) as Array).is_empty():
		if path.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS and data is Dictionary:
			_begin_audio(path, result)
			return
		_store_failure(path, "no video stream")
		return
	var stream: Dictionary = data["streams"][0]
	var entry := {
		"sig": result["sig"],
		"width": int(stream.get("width", 0)),
		"height": int(stream.get("height", 0)),
		"codec": str(stream.get("codec_name", "")),
		"fps": _parse_rate(str(stream.get("avg_frame_rate", "0/1"))),
		"duration": float(data.get("format", {}).get("duration", 0.0)) if not PanoramaFiles.is_image(path) else 0.0,
		"created": Time.get_unix_time_from_system(),
	}
	if entry["width"] <= 0 or entry["height"] <= 0:
		_store_failure(path, "no picture size")
		return
	var metadata := FormatDetector.metadata_from_probe(stream, data.get("frames", []))
	if not metadata.is_empty():
		entry["meta"] = metadata
	_begin_thumb(path, entry, result)


static func metadata_from_side_data(side_data: Array, width: int, height := 0) -> Dictionary:
	return FormatDetector.metadata_from_side_data(side_data, width, height)


func _begin_audio(path: String, probe: Dictionary) -> void:
	var data: Dictionary = probe.get("data", {})
	var entry := {
		"sig": probe["sig"],
		"width": 0,
		"height": 0,
		"codec": "audio",
		"fps": 0.0,
		"duration": float(data.get("format", {}).get("duration", 0.0)),
		"audio": true,
		"cover_aspect_preserved": true,
		"created": Time.get_unix_time_from_system(),
	}
	var thumb := "%s-%s.jpg" % [path.md5_text(), str(entry["sig"]).md5_text().substr(0, 8)]
	var output := ProjectSettings.globalize_path(THUMB_DIR.path_join(thumb))
	entries[path] = entry
	_mark_dirty()
	var job := {"stage": "thumb", "path": path, "output": output, "thumb": thumb, "script": AUDIO_THUMB_SCRIPT % NICE, "args": [path, output, "0", "scale=%d:%d:force_original_aspect_ratio=decrease:flags=bicubic,setsar=1" % [THUMB_WIDTH, THUMB_HEIGHT]]}
	in_flight[path] = job
	_push_work(job)


func _begin_thumb(path: String, entry: Dictionary, probe: Dictionary) -> void:
	var source := path
	var size := Vector2i(entry["width"], entry["height"])
	if probe.has("cube_source"):
		source = probe["cube_source"]
		var face_size: Vector2i = probe["face_size"]
		size = face_size if face_size.x > 0 else Vector2i(entry["height"], entry["height"])
		entry["cube"] = true
	var thumb := "%s-%s.jpg" % [path.md5_text(), str(entry["sig"]).md5_text().substr(0, 8)]
	var previous: String = entries.get(path, {}).get("thumb", "")
	if not previous.is_empty() and previous != thumb:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(THUMB_DIR.path_join(previous)))
	var filter := _thumb_filter(path, size, entry.get("cube", false), entry.get("meta", {}))
	var output := ProjectSettings.globalize_path(THUMB_DIR.path_join(thumb))
	entries[path] = entry
	_mark_dirty()
	var job := {"stage": "thumb", "path": path, "output": output, "thumb": thumb}
	if PanoramaFiles.is_image(path):
		job["script"] = IMAGE_THUMB_SCRIPT % NICE
		job["args"] = [source, output, "0", filter]
	else:
		job["script"] = VIDEO_THUMB_SCRIPT % NICE
		job["args"] = [source, output, "%.3f" % (float(entry["duration"]) * THUMB_POSITION), filter]
	in_flight[path] = job
	_push_work(job)


func _finish_thumb(result: Dictionary) -> void:
	if invalidated.has(result["path"]):
		in_flight.erase(result["path"])
		return
	var path: String = result["path"]
	var job: Variant = in_flight.get(path)
	in_flight.erase(path)
	if not entries.has(path) or not job is Dictionary:
		return
	var entry: Dictionary = entries[path].duplicate()
	if result.get("timeout", false):
		_store_failure(path, "timeout in thumb")
		return
	var image: Image = result.get("image")
	if image != null and not image.is_empty():
		entry["thumb"] = job["thumb"]
		entries[path] = entry
		_store_texture(path, image)
	else:
		entry["thumb_failed"] = true
		entry["thumb_failed_at"] = Time.get_unix_time_from_system()
		entries[path] = entry
		Log.warn("media info: thumbnail extraction failed for %s" % path)
	_mark_dirty()
	updated.emit(path)


func _store_failure(path: String, reason: String) -> void:
	in_flight.erase(path)
	entries[path] = {"sig": _signature(path), "failed": reason, "created": Time.get_unix_time_from_system(), "failed_at": Time.get_unix_time_from_system()}
	_mark_dirty()
	updated.emit(path)
	Log.warn("media info: %s for %s" % [reason, path])


func _thumb_filter(path: String, size: Vector2i, cube: bool, metadata := {}, format_override := {}) -> String:
	var eye := Rect2(Vector2.ZERO, Vector2(size))
	var projection := Settings.ProjectionMode.FLAT
	if cube:
		projection = Settings.ProjectionMode.FLAT
	else:
		var format: Dictionary = format_override if not format_override.is_empty() else _format_for(path, float(size.x) / float(size.y), metadata)
		projection = format["projection"]
		if format["stereo"] == Settings.Stereo.SIDE_BY_SIDE:
			eye.size.x *= 0.5
			if format.get("swap_eyes", false):
				eye.position.x = eye.size.x
		elif format["stereo"] == Settings.Stereo.OVER_UNDER:
			eye.size.y *= 0.5
			if format.get("swap_eyes", false):
				eye.position.y = eye.size.y
		if projection == Settings.ProjectionMode.EAC:
			eye = Rect2(eye.position + Vector2(eye.size.x / 3.0, 0.0), Vector2(eye.size.x / 3.0, eye.size.y / 2.0))
			projection = Settings.ProjectionMode.FLAT
		elif projection == Settings.ProjectionMode.CUBEMAP:
			eye = Rect2(eye.position + Vector2(eye.size.x / 3.0, eye.size.y / 2.0), Vector2(eye.size.x / 3.0, eye.size.y / 2.0))
			projection = Settings.ProjectionMode.FLAT
	var share: float = CROP_SHARE.get(projection, 1.0)
	var crop := Vector2(eye.size.x * share, eye.size.x * share / THUMB_ASPECT)
	if crop.y > eye.size.y:
		crop = Vector2(eye.size.y * THUMB_ASPECT, eye.size.y)
	var corner := eye.get_center() - crop * 0.5
	var w := maxi(int(crop.x) & ~1, 2)
	var h := maxi(int(crop.y) & ~1, 2)
	return "crop=%d:%d:%d:%d,scale=%d:%d:flags=bicubic" % [w, h, maxi(int(corner.x), 0), maxi(int(corner.y), 0), THUMB_WIDTH, THUMB_HEIGHT]


func _format_for(path: String, aspect: float, metadata := {}) -> Dictionary:
	var saved: Variant = Library.get_pref(path, "format")
	if saved is Dictionary:
		return {"projection": int(saved.get("projection", 0)), "stereo": int(saved.get("stereo", 0)), "swap_eyes": bool(saved.get("swap_eyes", false))}
	return VPXPlayer.guess_format(path, aspect, metadata)


func _finish_stat(result: Dictionary) -> void:
	if invalidated.has(result["path"]):
		verifying.erase(result["path"])
		return
	var path: String = result["path"]
	verifying.erase(path)
	signatures[path] = result["sig"]
	var entry: Dictionary = entries.get(path, {})
	if not entry.is_empty() and entry.get("sig", "") != result["sig"]:
		textures.erase(path)
		if requested.has(path):
			request(path)
	updated.emit(path)


func _start_load(path: String) -> void:
	var thumb: String = info(path).get("thumb", "")
	if thumb.is_empty() or textures.has(path):
		return
	loading[path] = true
	_push_load({"stage": "load", "path": path, "file": ProjectSettings.globalize_path(THUMB_DIR.path_join(thumb))})


func _finish_load(result: Dictionary) -> void:
	if invalidated.has(result["path"]):
		loading.erase(result["path"])
		return
	var path: String = result["path"]
	loading.erase(path)
	var image: Image = result["image"]
	if image == null or image.is_empty():
		if entries.has(path):
			var entry: Dictionary = entries[path].duplicate()
			entry.erase("thumb")
			entry["thumb_failed"] = true
			entry["thumb_failed_at"] = Time.get_unix_time_from_system()
			entries[path] = entry
			_mark_dirty()
		return
	_store_texture(path, image)
	updated.emit(path)


func _store_texture(path: String, image: Image) -> void:
	textures[path] = ImageTexture.create_from_image(image)
	texture_order.erase(path)
	texture_order.append(path)
	while texture_order.size() > MAX_TEXTURES:
		textures.erase(texture_order.pop_front())


func _scratch_path(path: String, extension: String) -> String:
	return ProjectSettings.globalize_path(THUMB_DIR.path_join("%s.%s.tmp" % [path.md5_text(), extension]))


func _parse_rate(rate: String) -> float:
	var parts := rate.split("/")
	if parts.size() == 2 and float(parts[1]) > 0.0:
		return float(parts[0]) / float(parts[1])
	return float(rate)


func _has_tool(tool: String) -> bool:
	return Shell.has_command(tool)


func _mark_dirty() -> void:
	dirty = true
	save_timer = 0.0


func save(background := false) -> void:
	if not dirty:
		return
	dirty = false
	_prune()
	if background and not stopped:
		_push_load({"stage": "save", "files": entries.duplicate()})
		return
	_write_index(entries)


func _write_index(files: Dictionary) -> void:
	var text := JSON.stringify({"version": 2, "files": files})
	var temp := INDEX_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		Log.warn("media info: cannot write %s" % INDEX_PATH)
		return
	file.store_string(text)
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(INDEX_PATH))


func _load() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if data is Dictionary and data.get("version", 0) == 2 and data.get("files") is Dictionary:
		entries = data["files"]
		for path in entries.keys():
			var entry: Dictionary = entries[path]
			if entry.get("audio", false) and not entry.get("cover_aspect_preserved", false):
				entries.erase(path)
				_mark_dirty()


func _prune() -> void:
	var excess := entries.size() - MAX_ENTRIES
	if excess <= 0:
		return
	var paths: Array = entries.keys()
	paths.sort_custom(func(a: String, b: String) -> bool:
		return float(entries[a].get("created", 0)) < float(entries[b].get("created", 0)))
	for i in excess:
		var thumb: String = entries[paths[i]].get("thumb", "")
		if not thumb.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(THUMB_DIR.path_join(thumb)))
		entries.erase(paths[i])
