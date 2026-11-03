extends Node

signal changed

const CACHE_DIR := "user://cache/scenes"
const SCAN_SCRIPT := "exec nice -n 15 ffmpeg -v info -nostdin -nostats -y -threads 1 -skip_frame nokey -i \"$1\" -map 0:v:0 -an -sn -dn -vf \"$2\" -f null - 2> \"$3\""
const FILTER := "select=gt(scene\\,0.02),metadata=print"
const MIN_SCORE := 0.05
const MIN_GAP := 20.0
const MAX_MARKS := 40
const MIN_LENGTH := 120.0
const JOB_TIMEOUT_MSEC := 900000

var path := ""
var times: Array[float] = []
var pid := -1
var started := 0
var log_path := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		stop()


func stop() -> void:
	if pid > 0:
		if OS.is_process_running(pid):
			OS.kill(pid)
		pid = -1
	if not log_path.is_empty():
		DirAccess.remove_absolute(log_path)
		log_path = ""


func clear() -> void:
	stop()
	path = ""
	times.clear()


func prepare(player: VPXPlayer) -> void:
	if not Settings.scene_marks or player == null:
		if not path.is_empty():
			clear()
		return
	var video_path := player.current_path
	if not _scannable(player, video_path):
		if not path.is_empty():
			clear()
		return
	if video_path == path:
		return
	clear()
	path = video_path
	var cache := _cache_path(video_path)
	if FileAccess.file_exists(cache):
		times = _read_cache(FileAccess.get_file_as_string(cache))
		changed.emit()
		return
	log_path = cache + ".log"
	started = Time.get_ticks_msec()
	pid = Shell.spawn(SCAN_SCRIPT, [video_path, FILTER, log_path])
	if pid <= 0:
		pid = -1
		path = ""
		Log.warn("scene scan could not start: %s" % video_path)
		return
	Log.info("scene scan started: %s" % video_path.get_file())


func _process(_delta: float) -> void:
	if pid <= 0:
		return
	if OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > JOB_TIMEOUT_MSEC:
			Log.warn("scene scan timed out: %s" % path.get_file())
			stop()
			path = ""
			changed.emit()
		return
	pid = -1
	var found: Array[float] = []
	if FileAccess.file_exists(log_path):
		found = _thin(_parse_log(FileAccess.get_file_as_string(log_path)))
		DirAccess.remove_absolute(log_path)
	log_path = ""
	times = found
	_write_cache(_cache_path(path), found)
	if found.is_empty():
		Log.info("scene scan found no cuts: %s" % path.get_file())
	else:
		Log.info("scene scan found %d cuts: %s" % [found.size(), path.get_file()])
	changed.emit()


func _scannable(player: VPXPlayer, video_path: String) -> bool:
	if video_path.is_empty() or video_path.contains("://") or player.is_image():
		return false
	if bool(player.stream_metadata.get("audio_only", false)):
		return false
	if player.playback == null or player.get_stream_length() < MIN_LENGTH:
		return false
	return MediaInfo.available


func _cache_path(video_path: String) -> String:
	var key := "%s-%s" % [video_path.md5_text(), MediaInfo._stat_signature(video_path).md5_text().substr(0, 8)]
	return ProjectSettings.globalize_path(CACHE_DIR.path_join(key + ".json"))


func _read_cache(text: String) -> Array[float]:
	var result: Array[float] = []
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		return result
	for value: Variant in parsed:
		if value is float or value is int:
			result.append(float(value))
	return result


func _write_cache(cache: String, values: Array[float]) -> void:
	var file := FileAccess.open(cache, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(values))
	file.close()


func _parse_log(text: String) -> Array:
	var found := []
	var pending := -1.0
	for line in text.split("\n"):
		if line.contains("pts_time:"):
			pending = float(line.substr(line.find("pts_time:") + 9).strip_edges().split(" ")[0])
		elif line.contains("scene_score="):
			if pending >= 0.0:
				var score := float(line.substr(line.find("scene_score=") + 12).strip_edges())
				if score >= MIN_SCORE:
					found.append({"time": pending, "score": score})
			pending = -1.0
	return found


func _thin(candidates: Array) -> Array[float]:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var picked: Array[float] = []
	for entry: Dictionary in candidates:
		if picked.size() >= MAX_MARKS:
			break
		var time := float(entry["time"])
		var clear := true
		for kept: float in picked:
			if absf(kept - time) < MIN_GAP:
				clear = false
				break
		if clear:
			picked.append(time)
	picked.sort()
	return picked
