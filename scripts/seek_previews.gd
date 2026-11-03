extends Node

signal ready_for(path: String)
signal state_changed

const PREVIEW_DIR := "user://cache/previews"
const TILE_DIR := "user://cache/tiles"
const FRAME_SIZE := Vector2i(352, 198)
const MAX_TEXTURES := 48
const SETTLE_MSEC := 50
const REFINE_MSEC := 350
const CANCEL_STALE_MSEC := 750
const JOB_TIMEOUT_MSEC := 30000
const RETRY_MSEC := 1000
const MAX_ATTEMPTS := 3
const QUICK_SCRIPT := "exec nice -n 15 ffmpeg -v error -nostdin -y -threads 1 -skip_loop_filter all -noaccurate_seek -skip_frame nokey -ss \"$3\" -i \"$1\" -map 0:v:0 -an -sn -dn -copyts -fps_mode passthrough -frames:v 1 -filter_threads 1 -vf \"$4\" -pix_fmt yuvj420p -q:v 5 \"$2\" 2> \"$5\""
const EXACT_SCRIPT := "exec nice -n 15 ffmpeg -v error -nostdin -y -threads 2 -skip_loop_filter all -ss \"$3\" -i \"$1\" -map 0:v:0 -an -sn -dn -frames:v 1 -filter_threads 1 -vf \"$4\" -pix_fmt yuvj420p -q:v 5 \"$2\" 2> \"$5\""
const PROBE_SCRIPT := "exec nice -n 15 ffprobe -v error -select_streams v:0 -skip_frame nokey -show_entries frame=pts_time -of csv=p=0 \"$1\" > \"$2\" 2> \"$3\""
const TILE_SCRIPT := "exec nice -n 15 ffmpeg -v error -nostdin -y -threads 1 -skip_frame nokey -i \"$1\" -map 0:v:0 -an -sn -dn -fps_mode passthrough -vf \"$2\" -q:v 7 \"$3\" 2> \"$4\""
const TILE_MAX := 600
const TILE_KEEP := 60
const TILE_PROBE_MSEC := 60000
const TILE_JOB_MSEC := 900000

var path := ""
var duration := 0.0
var format_id := ""
var output_dir := ""
var filter := ""
var interval := 1.0
var desired := -1
var wanted_at := 0
var active := -1
var active_quick := false
var pid := -1
var started := 0
var exact_textures := {}
var quick_textures := {}
var texture_order: Array[int] = []
var exact_absent := {}
var quick_absent := {}
var failed_exact := {}
var failed_quick := {}
var attempts := {}
var request_owner: Object
var unavailable_reason := ""
var tile_dir := ""
var tile_ready := false
var tile_failed := false
var tile_stage := 0
var tile_pid := -1
var tile_started := 0
var tile_times: Array[float] = []
var tile_files := PackedStringArray()
var tile_textures := {}
var tile_order: Array[int] = []
var tile_probe_times: Array[float] = []
var tile_step := 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILE_DIR))
	_prune_tiles()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		clear()


func clear() -> void:
	stop()
	_cancel_tiles()
	tile_dir = ""
	tile_ready = false
	tile_failed = false
	tile_times.clear()
	tile_files = PackedStringArray()
	tile_textures.clear()
	tile_order.clear()
	tile_probe_times.clear()
	path = ""
	duration = 0.0
	format_id = ""
	exact_textures.clear()
	quick_textures.clear()
	texture_order.clear()
	exact_absent.clear()
	quick_absent.clear()
	failed_exact.clear()
	failed_quick.clear()
	attempts.clear()
	unavailable_reason = ""


func stop(requester: Object = null) -> void:
	if requester != null and request_owner != requester:
		return
	_cancel()
	desired = -1
	request_owner = null


func prepare(player: VPXPlayer) -> void:
	var video_path := player.current_path
	if not Settings.seek_previews or video_path.is_empty() or video_path.begins_with("vpxzip://") or player.is_image() or bool(player.stream_metadata.get("audio_only", false)):
		if not path.is_empty():
			clear()
		return
	var length := player.get_stream_length()
	var current_format := _format_id()
	if video_path == path and is_equal_approx(length, duration) and current_format == format_id:
		return
	var picture := Vector2i.ZERO
	var texture := player.get_video_texture()
	if texture != null:
		picture = Vector2i(texture.get_width(), texture.get_height())
	if picture.x <= 0:
		var info := MediaInfo.info(video_path)
		picture = Vector2i(int(info.get("width", 0)), int(info.get("height", 0)))
	if picture.x > 0:
		request(video_path, length, picture)


func request(video_path: String, length: float, picture: Vector2i) -> void:
	var current_format := _format_id()
	if video_path == path and is_equal_approx(length, duration) and current_format == format_id:
		return
	clear()
	if length <= 1.0 or not MediaInfo.available or video_path.contains("://") or picture.x <= 0 or picture.y <= 0:
		unavailable_reason = "Install ffmpeg / ffprobe for previews" if not MediaInfo.available else "Preview unavailable for this source"
		return
	path = video_path
	duration = length
	format_id = current_format
	interval = maxf(1.0, length / 720.0)
	filter = _preview_filter(video_path, picture)
	var key := "%s-%s-v7-%s" % [video_path.md5_text(), MediaInfo._stat_signature(video_path).md5_text().substr(0, 8), format_id]
	output_dir = ProjectSettings.globalize_path(PREVIEW_DIR.path_join(key))
	DirAccess.make_dir_recursive_absolute(output_dir)
	tile_dir = ProjectSettings.globalize_path(TILE_DIR.path_join(key))


func _format_id() -> String:
	return "%d-%d-%d" % [Settings.projection, Settings.stereo, int(Settings.swap_eyes)]


func _preview_filter(video_path: String, picture: Vector2i) -> String:
	if Settings.projection != Settings.ProjectionMode.FLAT:
		var crop: String = MediaInfo._thumb_filter(video_path, picture, false, {}, {"projection": Settings.projection, "stereo": Settings.stereo, "swap_eyes": Settings.swap_eyes})
		return crop.replace("scale=%d:%d:flags=bicubic" % [MediaInfo.THUMB_WIDTH, MediaInfo.THUMB_HEIGHT], "scale=%d:%d:flags=fast_bilinear" % [FRAME_SIZE.x, FRAME_SIZE.y])
	var size := picture
	var offset := Vector2i.ZERO
	if Settings.stereo == Settings.Stereo.SIDE_BY_SIDE:
		size.x = maxi((picture.x / 2) & ~1, 2)
		if Settings.swap_eyes:
			offset.x = picture.x - size.x
	elif Settings.stereo == Settings.Stereo.OVER_UNDER:
		size.y = maxi((picture.y / 2) & ~1, 2)
		if Settings.swap_eyes:
			offset.y = picture.y - size.y
	return "crop=%d:%d:%d:%d,scale=%d:%d:flags=fast_bilinear:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=%d:%d:(ow-iw)/2:(oh-ih)/2" % [size.x, size.y, offset.x, offset.y, FRAME_SIZE.x, FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y]


func frame(time: float, requester: Object = null) -> Texture2D:
	if requester != null and request_owner != requester:
		stop()
		request_owner = requester
	if path.is_empty():
		return null
	if tile_ready:
		var tile := _tile_frame(time)
		if tile != null:
			return tile
		tile_ready = false
		tile_failed = true
		_dir_clear(tile_dir)
	else:
		_ensure_tiles()
	var index := clampi(int(roundf(time / interval)), 0, int(ceilf(duration / interval)))
	if desired != index:
		desired = index
		wanted_at = Time.get_ticks_msec()
	if exact_textures.has(index):
		_touch(index)
		return exact_textures[index]
	if not exact_absent.has(index):
		exact_absent[index] = true
		if not (pid > 0 and active == index and not active_quick) and FileAccess.file_exists(_file(index, false)):
			return _load_frame(index, false)
	if quick_textures.has(index):
		_touch(index)
		return quick_textures[index]
	if not quick_absent.has(index):
		quick_absent[index] = true
		if not (pid > 0 and active == index and active_quick) and FileAccess.file_exists(_file(index, true)):
			return _load_frame(index, true)
	return null


func _process(_delta: float) -> void:
	_poll_tiles()
	if tile_ready:
		if pid > 0:
			_cancel()
		desired = -1
		return
	if pid > 0:
		if not OS.is_process_running(pid):
			var finished := active
			var was_quick := active_quick
			pid = -1
			active = -1
			var file := _file(finished, was_quick)
			if FileAccess.file_exists(file) and FileAccess.get_size(file) > 0:
				if _load_frame(finished, was_quick) == null:
					_mark_failed(finished, was_quick)
				elif finished == desired:
					ready_for.emit(path)
			else:
				DirAccess.remove_absolute(file)
				_mark_failed(finished, was_quick)
			_report_error(finished, was_quick)
		elif Time.get_ticks_msec() - started > JOB_TIMEOUT_MSEC:
			_mark_failed(active, active_quick)
			Log.warn("seek preview timed out at %.2f s: %s" % [active * interval, path])
			_cancel()
		elif desired != active and Time.get_ticks_msec() - started >= CANCEL_STALE_MSEC and Time.get_ticks_msec() - wanted_at >= SETTLE_MSEC:
			_cancel()
	if pid > 0 or desired < 0 or exact_textures.has(desired) or _waiting_on_failure(desired, false):
		return
	var elapsed := Time.get_ticks_msec() - wanted_at
	if elapsed < SETTLE_MSEC:
		return
	var quick_ready := quick_textures.has(desired)
	if not quick_ready and not _waiting_on_failure(desired, true):
		_start(desired, true)
	elif elapsed >= REFINE_MSEC or failed_quick.has(desired):
		_start(desired, false)


func _start(index: int, quick: bool) -> void:
	var file := _file(index, quick)
	if FileAccess.file_exists(file):
		if _load_frame(index, quick) != null:
			ready_for.emit(path)
			return
	active = index
	active_quick = quick
	var key := "%d:%s" % [index, quick]
	attempts[key] = int(attempts.get(key, 0)) + 1
	var seconds := minf(float(index) * interval, maxf(duration - 0.05, 0.0))
	pid = Shell.spawn(QUICK_SCRIPT if quick else EXACT_SCRIPT, [path, file, "%.3f" % seconds, filter, file + ".log"])
	started = Time.get_ticks_msec()
	if pid <= 0:
		_mark_failed(active, quick)
		Log.warn("seek preview could not start ffmpeg: %s" % path)
		active = -1


func _report_error(index: int, quick: bool) -> void:
	var log_path := _file(index, quick) + ".log"
	if FileAccess.file_exists(log_path):
		var detail := FileAccess.get_file_as_string(log_path).strip_edges()
		if not detail.is_empty():
			Log.warn("seek preview ffmpeg at %.2f s: %s" % [index * interval, detail.substr(0, 500)])
		DirAccess.remove_absolute(log_path)


func _load_frame(index: int, quick: bool) -> Texture2D:
	var file := _file(index, quick)
	var image := Image.load_from_file(file)
	if image == null or image.is_empty():
		DirAccess.remove_absolute(file)
		return null
	var texture := ImageTexture.create_from_image(image)
	attempts.erase("%d:%s" % [index, quick])
	if quick:
		failed_quick.erase(index)
		quick_textures[index] = texture
	else:
		failed_exact.erase(index)
		exact_textures[index] = texture
		quick_textures.erase(index)
	_touch(index)
	while texture_order.size() > MAX_TEXTURES:
		var oldest: int = texture_order.pop_front()
		exact_textures.erase(oldest)
		quick_textures.erase(oldest)
		exact_absent.erase(oldest)
		quick_absent.erase(oldest)
	return texture


func _file(index: int, quick: bool) -> String:
	return output_dir.path_join("%d%s.jpg" % [index, "-fast" if quick else ""])


func _mark_failed(index: int, quick: bool) -> void:
	if quick:
		failed_quick[index] = Time.get_ticks_msec()
	else:
		failed_exact[index] = Time.get_ticks_msec()
	state_changed.emit()


func _touch(index: int) -> void:
	texture_order.erase(index)
	texture_order.append(index)


func _cancel() -> void:
	if pid > 0:
		if OS.is_process_running(pid):
			OS.kill(pid)
		if active >= 0:
			DirAccess.remove_absolute(_file(active, active_quick))
			DirAccess.remove_absolute(_file(active, active_quick) + ".log")
	pid = -1
	active = -1


func _waiting_on_failure(index: int, quick: bool) -> bool:
	var failures: Dictionary = failed_quick if quick else failed_exact
	if not failures.has(index):
		return false
	var key := "%d:%s" % [index, quick]
	if int(attempts.get(key, 0)) >= MAX_ATTEMPTS:
		return true
	return Time.get_ticks_msec() - int(failures[index]) < RETRY_MSEC


func status(time: float) -> String:
	if not Settings.seek_previews:
		return "Previews off"
	if not unavailable_reason.is_empty():
		return unavailable_reason
	if path.is_empty():
		return "Preview unavailable"
	var index := clampi(int(roundf(time / interval)), 0, int(ceilf(duration / interval)))
	if exact_textures.has(index) or quick_textures.has(index):
		return ""
	if int(attempts.get("%d:false" % index, 0)) >= MAX_ATTEMPTS and failed_exact.has(index):
		return "Preview unavailable · reopen to retry"
	return "Loading preview…"


func _ensure_tiles() -> void:
	if tile_ready or tile_failed or tile_stage > 0 or path.is_empty() or tile_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(tile_dir)
	var manifest := tile_dir.path_join("tiles.json")
	if FileAccess.file_exists(manifest):
		if _read_tiles(manifest):
			return
	_dir_clear(tile_dir)
	tile_stage = 1
	tile_started = Time.get_ticks_msec()
	tile_pid = Shell.spawn(PROBE_SCRIPT, [path, tile_dir.path_join("keyframes.txt"), tile_dir.path_join("probe.log")])
	if tile_pid <= 0:
		_tiles_failed("probe could not start")


func _poll_tiles() -> void:
	if tile_stage <= 0 or tile_pid <= 0:
		return
	if OS.is_process_running(tile_pid):
		var limit := TILE_PROBE_MSEC if tile_stage == 1 else TILE_JOB_MSEC
		if Time.get_ticks_msec() - tile_started > limit:
			tile_pid = -1
			_tiles_failed("timed out")
		return
	tile_pid = -1
	if tile_stage == 1:
		_start_extract()
	else:
		_finish_tiles()


func _start_extract() -> void:
	var probe_file := tile_dir.path_join("keyframes.txt")
	tile_probe_times.clear()
	if FileAccess.file_exists(probe_file):
		for line in FileAccess.get_file_as_string(probe_file).split("\n"):
			if line.strip_edges().is_empty():
				continue
			tile_probe_times.append(float(line.strip_edges()))
		DirAccess.remove_absolute(probe_file)
	DirAccess.remove_absolute(tile_dir.path_join("probe.log"))
	if tile_probe_times.size() < 2:
		_tiles_failed("no keyframes found")
		return
	tile_stage = 2
	tile_started = Time.get_ticks_msec()
	tile_step = maxi(int(ceilf(tile_probe_times.size() / float(TILE_MAX))), 1)
	var tile_filter := filter if tile_step == 1 else "select=not(mod(n\\,%d)),%s" % [tile_step, filter]
	tile_pid = Shell.spawn(TILE_SCRIPT, [path, tile_filter, tile_dir.path_join("%05d.jpg"), tile_dir.path_join("extract.log")])
	if tile_pid <= 0:
		_tiles_failed("extract could not start")


func _finish_tiles() -> void:
	DirAccess.remove_absolute(tile_dir.path_join("extract.log"))
	var files := PackedStringArray()
	var dir := DirAccess.open(tile_dir)
	if dir != null:
		for name in dir.get_files():
			if name.ends_with(".jpg"):
				files.append(name)
	files.sort()
	if files.size() != ceili(tile_probe_times.size() / float(tile_step)):
		_tiles_failed("frame count mismatch")
		return
	tile_times.clear()
	tile_files = PackedStringArray()
	for index in files.size():
		tile_times.append(tile_probe_times[index * tile_step])
		tile_files.append(files[index])
	tile_probe_times.clear()
	if tile_times.is_empty():
		_tiles_failed("no tiles kept")
		return
	_write_tiles()
	tile_stage = 0
	tile_ready = true
	ready_for.emit(path)


func _tiles_failed(reason: String) -> void:
	tile_stage = 0
	tile_failed = true
	Log.warn("preview tiles %s: %s" % [reason, path])


func _write_tiles() -> void:
	var file := FileAccess.open(tile_dir.path_join("tiles.json"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"times": tile_times, "files": tile_files}))
	file.close()


func _read_tiles(manifest: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not parsed is Dictionary:
		return false
	var times: Variant = parsed.get("times", [])
	var files: Variant = parsed.get("files", [])
	if not times is Array or not files is Array or times.is_empty() or times.size() != files.size():
		return false
	tile_times.clear()
	tile_files = PackedStringArray()
	for index in times.size():
		tile_times.append(float(times[index]))
		tile_files.append(str(files[index]))
	tile_ready = true
	return true


func _tile_frame(time: float) -> Texture2D:
	var index := _tile_index(time)
	if index < 0:
		return null
	if tile_textures.has(index):
		tile_order.erase(index)
		tile_order.append(index)
		return tile_textures[index]
	var image := Image.load_from_file(tile_dir.path_join(tile_files[index]))
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	tile_textures[index] = texture
	tile_order.append(index)
	while tile_order.size() > MAX_TEXTURES:
		tile_textures.erase(tile_order.pop_front())
	return texture


func _tile_index(time: float) -> int:
	if tile_times.is_empty():
		return -1
	var low := 0
	var high := tile_times.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if tile_times[middle] < time:
			low = middle + 1
		else:
			high = middle
	if low > 0 and absf(tile_times[low - 1] - time) <= absf(tile_times[low] - time):
		return low - 1
	return low


func _cancel_tiles() -> void:
	if tile_pid > 0:
		if OS.is_process_running(tile_pid):
			OS.kill(tile_pid)
		tile_pid = -1
	tile_stage = 0


func _prune_tiles() -> void:
	var root := ProjectSettings.globalize_path(TILE_DIR)
	var dir := DirAccess.open(root)
	if dir == null:
		return
	var stamped := []
	for name in dir.get_directories():
		var folder := root.path_join(name)
		stamped.append([FileAccess.get_modified_time(folder.path_join("tiles.json")), folder])
	if stamped.size() <= TILE_KEEP:
		return
	stamped.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for index in range(TILE_KEEP, stamped.size()):
		var folder: String = stamped[index][1]
		_dir_clear(folder)
		DirAccess.remove_absolute(folder)


func _dir_clear(target: String) -> void:
	var dir := DirAccess.open(target)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(target.path_join(name))
