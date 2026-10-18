extends Node

signal ready_for(path: String)
signal state_changed

const PREVIEW_DIR := "user://cache/previews"
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


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		clear()


func clear() -> void:
	stop()
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
