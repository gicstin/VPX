class_name VPXPlayer
extends VideoStreamPlayer

signal load_changed(state: Dictionary)
signal opened(path: String)
signal ended
signal marks_changed
signal sleep_finished
signal music_changed
signal music_ended

const AUDIO_EXTENSIONS := ["mp3", "flac", "wav", "ogg", "opus", "oga", "m4a", "aac", "mka", "ac3", "eac3", "dts", "wma", "aiff", "aif", "m4b", "aob", "dsf"]
const ALPHA_PROBE_KEY := "alpha_detected"

const FORMAT_NAMES := {0: "rgba", 1: "yuv420p", 2: "yuva420p", 3: "nv12", 4: "p010", 5: "yuv420p10"}
const POSITION_SAVE_INTERVAL := 5.0
const BOOKMARK_MERGE := 2.0
const CHAPTER_BACK_GRACE := 3.0
const LOOP_MIN_LENGTH := 0.5
const SLEEP_FADE := 20.0
const TEXTURE_WAIT_MSEC := 6000
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const MediaTracks := preload("res://scripts/media_tracks.gd")
const AutoCrop := preload("res://scripts/auto_crop.gd")
const FormatDetector := preload("res://scripts/format_detector.gd")

var current_path := ""
var music_path := ""
var replacing_stream := false
var file_bytes := 0
var video_fps := 0.0
var playback: FFmpegVideoStreamPlayback
var frame_info := {}
var hardware_decoding := false
var save_timer := 0.0
var probe_wanted := false
var shown_period_msec := 0.0
var shown_last_msec := 0
var image: VPXPanorama
var image_info := {}
var image_loader: VPXPanorama
var loading_path := ""
var loading_started_msec := 0
var image_source := -1
var discarded_loaders: Array[VPXPanorama] = []
var prefetched := {}
var open_serial := 0
var load_state := {}
var load_options := {}
var load_error := ""
var image_request: HTTPRequest
var software_retry := false
var decode_before_retry := ""
var stall_seconds := 0.0
var observed_position := 0.0
var image_path := ""
var tracks: MediaTracks = MediaTracks.new()
var chapters: Array = []
var loop_a := -1.0
var loop_b := -1.0
var sleep_left := 0.0
var sleep_armed := -1
var content_rotation := Basis.IDENTITY
var cube_padding := 0.0
var stream_metadata := {}
var source_title := ""
var auto_crop: AutoCrop = AutoCrop.new()
var auto_cropped := false
var auto_crop_key := ""


func _ready() -> void:
	add_child(tracks)
	add_child(auto_crop)
	auto_crop.detected.connect(_on_crop_detected)
	finished.connect(_on_finished)
	visible = false
	Settings.changed.connect(apply_audio)
	Settings.changed.connect(apply_priority)
	Settings.changed.connect(apply_speed)
	Settings.changed.connect(_on_settings_changed)
	Settings.changed.connect(apply_audio_processing)
	apply_audio()


func _process(delta: float) -> void:
	if image_loader != null:
		_poll_image()
	elif not prefetched.is_empty():
		_poll_prefetch()
	if not discarded_loaders.is_empty():
		discarded_loaders = discarded_loaders.filter(func(loader: VPXPanorama) -> bool: return not loader.is_decoded())
	if paused and playback != null and not current_path.is_empty():
		playback.pump_paused(delta)
	_monitor_stream(delta)
	_update_sleep(delta)
	if current_path.is_empty() or paused or not is_playing():
		return
	if loop_b > loop_a and loop_a >= 0.0 and stream_position >= loop_b:
		seek_to(loop_a)
	save_timer += delta
	if save_timer >= POSITION_SAVE_INTERVAL:
		save_timer = 0.0
		remember_position()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		remember_position()


func remember_position() -> void:
	if not music_path.is_empty() and playback != null:
		Settings.remember_position(music_path, 0.0, 0.0)
		if image != null or image_loader != null:
			return
	if current_path.is_empty() or is_image():
		return
	if _is_audio_item(current_path) or bool(stream_metadata.get("audio_only", false)):
		Settings.remember_position(current_path, 0.0, 0.0)
		return
	Settings.remember_position(current_path, stream_position, get_stream_length())


func _is_audio_item(path: String) -> bool:
	return path.begins_with("sacd://") or path.get_extension().to_lower() in AUDIO_EXTENSIONS


func _on_finished() -> void:
	if replacing_stream:
		return
	if not music_path.is_empty() and (image != null or image_loader != null):
		var song := music_path
		Settings.remember_position(song, 0.0, 0.0)
		Library.mark_finished(song)
		Log.info("music ended %s" % song.get_file())
		music_ended.emit()
		return
	Settings.remember_position(current_path, 0.0, 0.0)
	Library.mark_finished(current_path)
	ended.emit()


func apply_audio() -> void:
	var fade := 1.0
	if sleep_armed > 0 and Settings.sleep_timer != Settings.SleepTimer.END_OF_VIDEO:
		fade = clampf(sleep_left / SLEEP_FADE, 0.0, 1.0)
	volume_db = linear_to_db(Settings.volume / 100.0 * fade) if Settings.volume > 0 and fade > 0.0 else -80.0
	AudioServer.set_bus_mute(0, Settings.muted)


static func tags_from_name(path: String) -> Dictionary:
	return FormatDetector.tags_from_name(path)


static func format_from_metadata(metadata: Dictionary) -> Dictionary:
	return FormatDetector.format_from_metadata(metadata)


static func guess_format(path: String, aspect: float, metadata := {}) -> Dictionary:
	return FormatDetector.guess_format(path, aspect, metadata)


static func format_label(projection: int, stereo: int) -> String:
	var stereo_name := "" if stereo == Settings.Stereo.MONO else (" 3D" if projection != Settings.ProjectionMode.FLAT else (" SBS" if stereo == Settings.Stereo.SIDE_BY_SIDE else " OU"))
	match projection:
		Settings.ProjectionMode.EQUIRECT_360:
			return "360°" + stereo_name
		Settings.ProjectionMode.EAC:
			return "360° EAC" + stereo_name
		Settings.ProjectionMode.CUBEMAP:
			return "360° cube" + stereo_name
		Settings.ProjectionMode.EQUIRECT_180:
			return "180°" + stereo_name
		Settings.ProjectionMode.FISHEYE:
			return "Fisheye" + stereo_name
	return "3D" + stereo_name if stereo != Settings.Stereo.MONO else "2D"


static func resolution_label(width: int, height: int) -> String:
	if width >= 3200:
		return "%dK" % roundi(width / 1000.0)
	if height <= 0:
		return ""
	return "%dp" % height


func detect_format(path: String) -> void:
	var format := FormatDetector.guess_format(path, aspect_ratio(), stream_metadata if not is_image() else {}, source_title)
	var alpha := Settings.AlphaMask.PACKED_CORNERS if format["alpha"] else int(Library.get_pref(path, ALPHA_PROBE_KEY, Settings.AlphaMask.NONE))
	if alpha not in [Settings.AlphaMask.NONE, Settings.AlphaMask.PACKED_CORNERS, Settings.AlphaMask.STACKED_BELOW]:
		alpha = Settings.AlphaMask.NONE
	if not format["tagged"] and alpha == Settings.AlphaMask.NONE and Settings.restore_session_format():
		var detecting: bool = Settings.detecting
		Settings.detecting = true
		Settings.apply("alpha_mask", Settings.AlphaMask.NONE)
		Settings.detecting = detecting
		probe_wanted = true
		return
	if alpha == Settings.AlphaMask.STACKED_BELOW:
		format = FormatDetector.guess_format(path, aspect_ratio() * 2.0, stream_metadata if not is_image() else {}, source_title)
	elif alpha == Settings.AlphaMask.PACKED_CORNERS and not format["tagged"]:
		format["projection"] = Settings.ProjectionMode.FISHEYE
		format["stereo"] = Settings.Stereo.SIDE_BY_SIDE
	var was_detecting := Settings.detecting
	Settings.detecting = true
	Settings.apply("projection", format["projection"])
	Settings.apply("stereo", format["stereo"])
	Settings.apply("swap_eyes", format["swap"])
	Settings.apply("fisheye_fov", format["fov"] if format["fov"] > 0.0 else 180.0)
	Settings.apply("equirect_fov", format["equirect_fov"] if format["equirect_fov"] > 0.0 else 180.0)
	Settings.apply("alpha_mask", alpha)
	Settings.detecting = was_detecting
	probe_wanted = alpha == Settings.AlphaMask.NONE
	Log.info("detected format: projection %d stereo %d fov %.0f alpha %d aspect %.2f" % [Settings.projection, Settings.stereo, Settings.fisheye_fov, alpha, aspect_ratio()])
	if format["unsupported_stereo"]:
		Log.warn("unsupported stereo packing in %s" % path.get_file())


func apply_probe(mode: int) -> void:
	probe_wanted = false
	if not Settings.auto_detect or Settings.alpha_mask != Settings.AlphaMask.NONE or current_path.is_empty():
		return
	if Library.get_pref(current_path, "format") is Dictionary:
		return
	Library.set_pref(current_path, ALPHA_PROBE_KEY, mode)
	Settings.detecting = true
	Settings.apply("alpha_mask", mode)
	if mode == Settings.AlphaMask.PACKED_CORNERS and Settings.projection == Settings.ProjectionMode.FLAT:
		Settings.apply("projection", Settings.ProjectionMode.FISHEYE)
		Settings.apply("stereo", guess_stereo(Settings.ProjectionMode.FISHEYE, content_aspect()))
	Settings.detecting = false
	Log.info("alpha mask %d detected from picture content" % mode)


func _apply_content_metadata() -> void:
	var from_metadata := format_from_metadata(stream_metadata)
	var angles: Vector3 = from_metadata["rotation"]
	content_rotation = Basis.from_euler(Vector3(deg_to_rad(angles.y), deg_to_rad(-angles.x), deg_to_rad(-angles.z)), EULER_ORDER_YXZ).inverse()
	var width := float(frame_info.get("width", 0))
	var format := FormatDetector.guess_format(current_path, aspect_ratio(), stream_metadata, source_title)
	if format["stereo"] == Settings.Stereo.SIDE_BY_SIDE:
		width *= 0.5
	cube_padding = clampf(from_metadata["padding"] / (width / 3.0), 0.0, 0.2) if width > 0.0 else 0.0


static func guess_projection(stereo: int, aspect: float) -> int:
	return FormatDetector.guess_projection(stereo, aspect)


static func guess_stereo(projection: int, aspect: float) -> int:
	return FormatDetector.guess_stereo(projection, aspect)


func open(path: String, options := {}) -> bool:
	cancel_open()
	open_serial += 1
	var serial := open_serial
	load_error = ""
	stall_seconds = 0.0
	observed_position = 0.0
	load_options = options.duplicate(true)
	load_state = {"path": path, "status": "opening", "stage": "Opening media…", "options": load_options}
	load_changed.emit(load_state.duplicate(true))
	if not path.contains("://") and not FileAccess.file_exists(path):
		_fail_load("missing", "This file is missing or its drive is disconnected.", "File not found: " + path)
		return false
	var ok := await _open_source(path, options, serial)
	if serial != open_serial:
		return false
	if ok:
		load_state["status"] = "ready"
		load_changed.emit(load_state.duplicate(true))
	elif load_state.get("status") != "failed":
		if image != null:
			current_path = image_path
			Settings.format_path = image_path
		var remote := path.contains("://") and not path.begins_with("sacd://")
		if not remote and PanoramaFiles.is_image(path):
			_fail_load("image", "Could not open this image. It may be damaged or use an unsupported format.", load_error)
			return false
		_fail_load("connection" if remote else "decode", "Could not open this stream. Check that the source is online, then retry." if remote else "Could not play this file. It may be damaged or use an unsupported format.", load_error if not load_error.is_empty() else "The media decoder could not open the source.")
	return ok


func _load_stage(stage: String) -> void:
	if load_state.get("status") != "opening":
		return
	load_state["stage"] = stage
	load_changed.emit(load_state.duplicate(true))


func _fail_load(kind: String, message: String, details: String) -> void:
	load_state.merge({"status": "failed", "kind": kind, "message": message, "details": details}, true)
	load_changed.emit(load_state.duplicate(true))


func cancel_open() -> void:
	if load_state.get("status") not in ["opening", "buffering"]:
		return
	open_serial += 1
	if is_instance_valid(image_request):
		image_request.cancel_request()
		image_request.queue_free()
		image_request = null
	_discard_loader()
	if playback != null and (music_path == load_state.get("path", "") or (current_path == load_state.get("path", "") and not PanoramaFiles.is_image(current_path))):
		stop()
		stream = null
		playback = null
		current_path = ""
		music_path = ""
		music_changed.emit()
	if image != null:
		current_path = image_path
		Settings.format_path = image_path
	load_state["status"] = "cancelled"
	load_changed.emit(load_state.duplicate(true))


func _open_source(path: String, options: Dictionary, serial: int) -> bool:
	if (path.begins_with("http://") or path.begins_with("https://")) and not options.has("stream"):
		var image_extension := path.get_slice("?", 0).get_slice("#", 0).get_extension().to_lower()
		if image_extension in PanoramaFiles.IMAGE_EXTENSIONS:
			path = await _cache_remote_image(path, serial)
	if serial != open_serial:
		return false
	if not load_error.is_empty():
		return false
	remember_position()
	if _is_audio_item(path):
		Settings.remember_position(path, 0.0, 0.0)
	var keep_music := _audio_only_playing()
	var picture := image != null or image_loader != null
	source_title = str(options.get("title", ""))
	Library.mark_played(path)
	if not path.contains("://") and path.get_extension().to_lower() != "iso":
		MediaInfo.request(path, true)
	if PanoramaFiles.is_image(path):
		Settings.format_path = ""
		if not keep_music:
			stream_metadata = {}
		content_rotation = Basis.IDENTITY
		cube_padding = 0.0
		auto_crop.cancel()
		auto_cropped = false
		_load_stage("Decoding image…")
		_open_image(path, keep_music)
		while serial == open_serial and image_loader != null:
			await get_tree().process_frame
		return serial == open_serial and load_error.is_empty() and image != null
	if picture and path.get_extension().to_lower() in AUDIO_EXTENSIONS:
		await _play_with_picture(path, options, serial)
		return playback != null
	Settings.format_path = ""
	stream_metadata = {}
	content_rotation = Basis.IDENTITY
	cube_padding = 0.0
	auto_crop.cancel()
	auto_cropped = false
	music_path = ""
	_close_image()
	tracks.reset()
	_apply_decode_mode(bool(options.get("software", false)))
	_load_stage("Starting decoder…")
	Log.info("open %s (decode mode %d)" % [path, Settings.decode_mode])
	var video := FFmpegVideoStream.new()
	video.file = str(options.get("stream", path))
	video.audio_file = str(options.get("audio", ""))
	video.http_headers = str(options.get("headers", ""))
	var input_format := str(options.get("input_format", "dsf" if path.begins_with("sacd://") else ""))
	if not input_format.is_empty() and ClassDB.class_has_method("FFmpegVideoStream", "set_input_format"):
		video.call("set_input_format", input_format)
	replacing_stream = true
	playback = null
	frame_info = {}
	video_fps = 0.0
	probe_wanted = false
	stream = video
	replacing_stream = false
	current_path = path
	file_bytes = FileAccess.get_size(path) if FileAccess.file_exists(path) else 0
	chapters = []
	clear_loop()
	play()
	if not is_playing():
		Log.warn("cannot play %s" % path)
		push_warning("Cannot play %s" % path)
		return false
	playback = video.get_playback()
	apply_priority()
	apply_speed()
	apply_audio_processing()
	_load_stage("Waiting for the first frame…")
	await _texture_ready(serial)
	if serial != open_serial:
		return false
	if playback != null:
		frame_info = playback.get_frame_info()
		video_fps = float(frame_info.get("frame_rate", 0.0))
		hardware_decoding = bool(frame_info.get("hardware", false))
	var texture := get_video_texture()
	if texture != null:
		Log.info("video %dx%d %s %s, length %.1f s, %.3f fps, colorspace %d range %d trc %d primaries %d chroma %d" % [
			texture.get_width(), texture.get_height(), pixel_format_name(), "hw" if hardware_decoding else "sw",
			get_stream_length(), playback_fps(), frame_info.get("color_space", -1), frame_info.get("color_range", -1),
			frame_info.get("color_transfer", -1), frame_info.get("color_primaries", -1), frame_info.get("chroma_location", -1)])
	elif playback == null or not bool(playback.get_stream_metadata().get("audio_only", false)):
		Log.warn("no video texture after waiting")
		_fail_load("decode", "The video did not produce a picture. Try software decoding or another file.", "No decoded video frame arrived within %d seconds." % (TEXTURE_WAIT_MSEC / 1000))
		stop()
		return false
	tracks.load_for(path, playback)
	chapters = playback.get_chapters() if playback != null else []
	stream_metadata = playback.get_stream_metadata() if playback != null else {}
	_apply_content_metadata()
	if playback != null:
		Log.info("audio %s" % str(playback.get_audio_info()))
	marks_changed.emit()
	Settings.format_path = path
	Settings.clear_view_adjust()
	if bool(stream_metadata.get("audio_only", false)):
		Settings.detecting = true
		Settings.apply("projection", Settings.ProjectionMode.FLAT)
		Settings.apply("stereo", Settings.Stereo.MONO)
		Settings.apply("swap_eyes", false)
		Settings.apply("alpha_mask", Settings.AlphaMask.NONE)
		Settings.apply("fisheye_fov", 180.0)
		Settings.detecting = false
		Log.info("audio-only %s" % path.get_file())
	elif Settings.restore_format(path):
		Log.info("restored saved format for %s" % path.get_file())
	elif Settings.auto_detect:
		Settings.detecting = true
		detect_format(path)
		Settings.detecting = false
	_request_auto_crop()
	var resume := Settings.resume_position(path) if not _is_audio_item(path) and not bool(stream_metadata.get("audio_only", false)) else 0.0
	if options.has("start_time"):
		resume = clampf(float(options["start_time"]), 0.0, maxf(0.0, get_stream_length() - 0.1))
	if resume > 0.0:
		seek_to(resume)
		Log.info("resumed at %.1f s" % resume)
	if options.has("paused"):
		paused = bool(options["paused"])
	opened.emit(path)
	return playback != null


func _cache_remote_image(url: String, serial: int) -> String:
	var cache_dir := ProjectSettings.globalize_path("user://cache/photos")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var extension := url.get_slice("?", 0).get_slice("#", 0).get_extension().to_lower()
	var path := cache_dir.path_join(url.md5_text() + "." + extension)
	if FileAccess.file_exists(path):
		return path
	_load_stage("Downloading image…")
	var request := HTTPRequest.new()
	image_request = request
	request.timeout = 20.0
	add_child(request)
	var result := request.request(url)
	if result != OK:
		request.queue_free()
		image_request = null
		load_error = "Could not start image download: " + error_string(result)
		return url
	var response: Array = []
	request.request_completed.connect(func(code: int, status: int, headers: PackedStringArray, body: PackedByteArray) -> void: response.assign([code, status, headers, body]), CONNECT_ONE_SHOT)
	while response.is_empty() and serial == open_serial:
		await get_tree().process_frame
	if serial != open_serial:
		return url
	request.queue_free()
	image_request = null
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) < 200 or int(response[1]) >= 300:
		Log.warn("photo download failed: %s" % url)
		load_error = "Image download failed (network result %s, HTTP %s)." % [response[0], response[1]]
		return url
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		load_error = "Could not save downloaded image: " + error_string(FileAccess.get_open_error())
		_fail_load("storage", "Could not save this image. Check free disk space and folder permissions, then retry.", load_error)
		return url
	file.store_buffer(response[3])
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		load_error = "Could not finish image download: " + error_string(error)
		_fail_load("storage", "Could not save this image. Check free disk space and folder permissions, then retry.", load_error)
		return url
	return path


func apply_audio_processing() -> void:
	if playback == null:
		return
	playback.set_spatial_audio(Settings.spatial_audio)
	playback.set_dialogue_boost(1.0 if Settings.dialogue_boost else 0.0)
	playback.set_audio_filter(Settings.audio_filter)
	if playback.has_method("set_visualizer_enabled"):
		playback.set_visualizer_enabled((Settings.music_visualizer or is_immersive_visualizer_active()) and (is_music_mode() or not music_path.is_empty()))


func _request_auto_crop() -> void:
	auto_cropped = false
	if not Settings.auto_crop or Settings.projection != Settings.ProjectionMode.FLAT or Settings.has_crop() or Settings.alpha_mask != Settings.AlphaMask.NONE:
		return
	if current_path.contains("://") or is_image() or bool(stream_metadata.get("audio_only", false)):
		return
	auto_crop.request(current_path, Settings.stereo, get_stream_length())


func _on_crop_detected(path: String, stereo: int, rect: Vector4) -> void:
	if path != current_path or stereo != Settings.stereo or not Settings.auto_crop or Settings.projection != Settings.ProjectionMode.FLAT:
		return
	if Settings.has_crop() and not auto_cropped:
		return
	Settings.detecting = true
	Settings.apply_crop(rect)
	Settings.detecting = false
	auto_cropped = rect != Vector4.ZERO
	if auto_cropped:
		Log.info("auto crop %s" % str(rect))


func _update_auto_crop_state() -> void:
	var key := "%s %d %d %s" % [Settings.auto_crop, Settings.stereo, Settings.projection, current_path]
	if key == auto_crop_key:
		return
	var path_changed := not auto_crop_key.ends_with(current_path)
	auto_crop_key = key
	if path_changed or Settings.detecting or current_path.is_empty() or is_image() or playback == null:
		return
	if not Settings.auto_crop or Settings.projection != Settings.ProjectionMode.FLAT:
		clear_auto_crop()
	elif auto_cropped or not Settings.has_crop():
		clear_auto_crop()
		_request_auto_crop()


func clear_auto_crop() -> void:
	auto_crop.cancel()
	if not auto_cropped:
		return
	auto_cropped = false
	Settings.detecting = true
	Settings.apply_crop(Vector4.ZERO)
	Settings.detecting = false


func bookmarks() -> Array:
	var path := music_path if not music_path.is_empty() else current_path
	if path.is_empty() or (is_image() and music_path.is_empty()):
		return []
	var saved: Variant = Library.get_pref(path, "bookmarks", [])
	var times: Array = (saved as Array).duplicate() if saved is Array else []
	times.sort()
	return times


func add_bookmark() -> float:
	if current_path.is_empty() or is_image():
		return -1.0
	var time := snappedf(stream_position, 0.1)
	var times := bookmarks()
	for existing: float in times:
		if absf(existing - time) < BOOKMARK_MERGE:
			return existing
	times.append(time)
	times.sort()
	Library.set_pref(current_path, "bookmarks", times)
	Log.info("bookmark at %.1f s" % time)
	marks_changed.emit()
	return time


func remove_bookmark(time: float) -> void:
	var times := bookmarks().filter(func(existing: float) -> bool: return not is_equal_approx(existing, time))
	if times.is_empty():
		Library.erase_pref(current_path, "bookmarks")
	else:
		Library.set_pref(current_path, "bookmarks", times)
	marks_changed.emit()


func mark_times() -> Array:
	var times: Array = bookmarks()
	for chapter: Dictionary in chapters:
		times.append(float(chapter["start"]))
	times.sort()
	return times


func step_mark(direction: int) -> bool:
	var times := mark_times()
	if times.is_empty():
		return false
	var position := stream_position
	var target := -1.0
	if direction > 0:
		for time: float in times:
			if time > position + 0.5:
				target = time
				break
	else:
		for i in range(times.size() - 1, -1, -1):
			if times[i] < position - CHAPTER_BACK_GRACE:
				target = times[i]
				break
		if target < 0.0:
			target = 0.0
	if target < 0.0:
		return false
	seek_to(target)
	return true


func chapter_at(time: float) -> int:
	for i in range(chapters.size() - 1, -1, -1):
		if time >= float(chapters[i]["start"]) - 0.01:
			return i
	return -1


func chapter_title(index: int) -> String:
	if index < 0 or index >= chapters.size():
		return ""
	var title: String = chapters[index]["title"]
	return title if not title.is_empty() else "Chapter %d" % (index + 1)


func set_loop_point() -> void:
	if current_path.is_empty() or is_image():
		return
	if loop_a < 0.0 or loop_b >= 0.0:
		loop_a = stream_position
		loop_b = -1.0
	elif stream_position > loop_a + LOOP_MIN_LENGTH:
		loop_b = stream_position
	else:
		loop_a = stream_position
	Log.info("loop %.1f - %.1f" % [loop_a, loop_b])
	marks_changed.emit()


func clear_loop() -> void:
	if loop_a < 0.0 and loop_b < 0.0:
		return
	loop_a = -1.0
	loop_b = -1.0
	marks_changed.emit()


func sleep_remaining() -> float:
	return sleep_left if sleep_armed > 0 and Settings.sleep_timer != Settings.SleepTimer.END_OF_VIDEO else -1.0


func _update_sleep(delta: float) -> void:
	if sleep_armed != Settings.sleep_timer:
		sleep_armed = Settings.sleep_timer
		sleep_left = Settings.SLEEP_MINUTES[sleep_armed] * 60.0
		apply_audio()
	if Settings.sleep_timer == Settings.SleepTimer.OFF or Settings.sleep_timer == Settings.SleepTimer.END_OF_VIDEO:
		return
	if current_path.is_empty() or paused or (not is_playing() and not is_image()):
		return
	sleep_left -= delta
	if sleep_left <= SLEEP_FADE:
		apply_audio()
	if sleep_left <= 0.0:
		fall_asleep()


func fall_asleep() -> void:
	Log.info("sleep timer: paused")
	paused = true
	Settings.sleep_timer = Settings.SleepTimer.OFF
	sleep_armed = Settings.SleepTimer.OFF
	apply_audio()
	sleep_finished.emit()


func is_image() -> bool:
	return image != null


func is_music_mode() -> bool:
	return _audio_only_playing() and not is_image()


func is_immersive_visualizer_active() -> bool:
	return Settings.immersive_music_visualizer and _audio_only_playing() and (not is_image() or Settings.visualizer_over_images)


func stop_music() -> void:
	if music_path.is_empty() and not _audio_only_playing():
		return
	music_path = ""
	replacing_stream = true
	stream = null
	playback = null
	replacing_stream = false
	chapters = []
	clear_loop()
	music_changed.emit()


func _audio_only_playing() -> bool:
	if playback == null:
		return false
	if not music_path.is_empty():
		return true
	if bool(stream_metadata.get("audio_only", false)):
		return true
	return current_path.get_extension().to_lower() in AUDIO_EXTENSIONS


func _play_with_picture(path: String, options: Dictionary, serial: int) -> void:
	if serial != open_serial:
		return
	Log.info("music over picture %s" % path)
	tracks.reset()
	var video := FFmpegVideoStream.new()
	video.file = str(options.get("stream", path))
	video.audio_file = str(options.get("audio", ""))
	video.http_headers = str(options.get("headers", ""))
	music_path = path
	replacing_stream = true
	playback = null
	stream = video
	replacing_stream = false
	chapters = []
	clear_loop()
	play()
	if not is_playing():
		Log.warn("cannot play %s" % path)
		push_warning("Cannot play %s" % path)
		music_path = ""
		music_changed.emit()
		return
	playback = video.get_playback()
	apply_priority()
	apply_speed()
	apply_audio_processing()
	await _texture_ready(serial)
	if serial != open_serial:
		return
	if playback != null:
		frame_info = playback.get_frame_info()
		stream_metadata = playback.get_stream_metadata()
		chapters = playback.get_chapters()
		Log.info("audio %s" % str(playback.get_audio_info()))
	var resume := Settings.resume_position(path) if not _is_audio_item(path) and not bool(stream_metadata.get("audio_only", false)) else 0.0
	if options.has("start_time"):
		resume = clampf(float(options["start_time"]), 0.0, maxf(0.0, get_stream_length() - 0.1))
	if resume > 0.0:
		seek_to(resume)
		Log.info("resumed at %.1f s" % resume)
	if options.has("paused"):
		paused = bool(options["paused"])
	marks_changed.emit()
	music_changed.emit()


func is_loading() -> bool:
	return image_loader != null


func has_picture() -> bool:
	return is_image() or get_video_texture() != null


func _open_image(path: String, keep_music := false) -> void:
	if keep_music:
		if music_path.is_empty():
			music_path = current_path
		Log.info("picture over music %s" % music_path.get_file())
	else:
		tracks.reset()
		stop()
		stream = null
		playback = null
		music_path = ""
		frame_info = {}
		video_fps = 0.0
	probe_wanted = false
	current_path = path
	file_bytes = FileAccess.get_size(path) if FileAccess.file_exists(path) else 0
	_discard_loader()
	image_source = Settings.panorama_source
	loading_path = path
	loading_started_msec = Time.get_ticks_msec()
	if prefetched.has(path):
		image_loader = prefetched[path]
		prefetched.erase(path)
		Log.info("open image %s from prefetch" % path)
	else:
		image_loader = _start_loader(path)
	if image_loader != null:
		_poll_image()
	else:
		load_error = "The image loader could not start for this source."


func prefetch_images(paths: PackedStringArray) -> void:
	for path: String in prefetched.keys():
		if path not in paths:
			_discard(prefetched[path])
			prefetched.erase(path)
	for path in paths:
		if path != current_path and not prefetched.has(path) and PanoramaFiles.is_image(path):
			var loader := _start_loader(path)
			if loader != null:
				prefetched[path] = loader


func _start_loader(path: String) -> VPXPanorama:
	var faces := PanoramaFiles.cube_faces(path)
	var equirect := PanoramaFiles.equirect_for(path)
	var use_cube := faces.size() == PanoramaFiles.CUBE_ORDER.size() and (Settings.panorama_source == Settings.PanoramaSource.CUBE or equirect.is_empty())
	var sources := faces if use_cube else PackedStringArray([equirect if not equirect.is_empty() else path])
	var loader := VPXPanorama.new()
	Log.info("load image %s as %s from %s" % [path, "cube" if use_cube else "single image", ", ".join(PackedStringArray(Array(sources).map(func(p: String) -> String: return p.get_file())))])
	if loader.start(sources, VPXPanorama.LAYOUT_CUBE if use_cube else VPXPanorama.LAYOUT_TILED, use_cube or _wraps(path, sources[0])) != OK:
		Log.warn("cannot load %s" % path)
		return null
	return loader


func _poll_prefetch() -> void:
	for path: String in prefetched.keys():
		if prefetched[path].poll() == VPXPanorama.STATUS_FAILED:
			Log.warn("prefetch %s failed: %s" % [path, prefetched[path].get_error()])
			prefetched.erase(path)


func _wraps(path: String, source: String) -> bool:
	var saved: Variant = Library.get_pref(path, "format")
	if saved is Dictionary:
		return int(saved.get("projection", -1)) == Settings.ProjectionMode.EQUIRECT_360 and int(saved.get("stereo", 0)) == Settings.Stereo.MONO
	var size := PanoramaFiles.probe_size(source)
	var format := guess_format(path, float(size.x) / float(size.y) if size.y > 0 else 0.0)
	return format["projection"] == Settings.ProjectionMode.EQUIRECT_360 and format["stereo"] == Settings.Stereo.MONO


func _poll_image() -> void:
	var status := image_loader.poll()
	if status == VPXPanorama.STATUS_LOADING:
		return
	var loader := image_loader
	var path := loading_path
	image_loader = null
	if status == VPXPanorama.STATUS_FAILED:
		load_error = loader.get_error()
		if str(load_state.get("path", "")).begins_with("http") and path.begins_with(ProjectSettings.globalize_path("user://cache/photos")):
			DirAccess.remove_absolute(path)
		Log.warn("image %s failed: %s" % [path, load_error])
		push_warning("Cannot open %s" % path)
		return
	if path != current_path:
		return
	image = loader
	image_path = path
	image_info = loader.get_info()
	image_info["total_msec"] = Time.get_ticks_msec() - loading_started_msec
	Log.info("image %dx%d %s, %d layer(s), read %.0f ms, pinned alloc %.0f ms, decode %.0f ms, decoded after %.0f ms, %s %.0f ms, mips %.0f ms in %d frames, shown after %d ms, %.0f MB VRAM" % [
		image_info["width"], image_info["height"], "cube" if image_info["layout"] == VPXPanorama.LAYOUT_CUBE else "tiled",
		image_info["layers"], image_info["read_msec"], image_info["alloc_msec"], image_info["decode_msec"], image_info["decoded_msec"],
		"dma" if image_info["dma"] else "staged upload", image_info["transfer_msec"] if image_info["dma"] else image_info["upload_msec"],
		image_info["mip_msec"], image_info["mip_frames"], image_info["total_msec"], image_info["vram_bytes"] / 1048576.0])
	_apply_image_format(path)
	opened.emit(path)


func _apply_image_format(path: String) -> void:
	probe_wanted = false
	Settings.format_path = path
	Settings.clear_view_adjust()
	if image_info["layout"] == VPXPanorama.LAYOUT_CUBE:
		Settings.detecting = true
		Settings.apply("projection", Settings.ProjectionMode.EQUIRECT_360)
		Settings.apply("stereo", Settings.Stereo.MONO)
		Settings.apply("swap_eyes", false)
		Settings.apply("alpha_mask", Settings.AlphaMask.NONE)
		Settings.detecting = false
		return
	if Settings.restore_format(path):
		Log.info("restored saved format for %s" % path.get_file())
		return
	if Settings.auto_detect:
		detect_format(path)


func _discard_loader() -> void:
	if image_loader != null:
		_discard(image_loader)
	image_loader = null


func _discard(loader: VPXPanorama) -> void:
	loader.abort()
	if not loader.is_decoded():
		discarded_loaders.append(loader)


func _close_image() -> void:
	_discard_loader()
	prefetch_images(PackedStringArray())
	image = null
	image_path = ""
	image_info = {}


func _on_settings_changed() -> void:
	_update_auto_crop_state()
	if image_source >= 0 and image_source != Settings.panorama_source and not current_path.is_empty() and (is_image() or is_loading()):
		image_source = Settings.panorama_source
		prefetch_images(PackedStringArray())
		if PanoramaFiles.cube_faces(current_path).size() == PanoramaFiles.CUBE_ORDER.size() and not PanoramaFiles.equirect_for(current_path).is_empty():
			open(current_path)


func apply_priority() -> void:
	if playback != null:
		playback.set_smooth_decode(Settings.playback_priority == Settings.PlaybackPriority.SMOOTH)


func apply_speed() -> void:
	if playback != null and playback.has_method("set_tempo_quality"):
		playback.set_tempo_quality(Settings.audio_stretch_quality)
	if playback != null and not is_equal_approx(playback.get_speed(), Settings.playback_speed):
		playback.set_speed(Settings.playback_speed)
		Log.info("playback speed %.2f" % Settings.playback_speed)


func _apply_decode_mode(force_software := false) -> void:
	OS.set_environment("VPX_PLAYBACK_PRIORITY", "sharp" if Settings.playback_priority == Settings.PlaybackPriority.SHARP else "smooth")
	if force_software:
		if not software_retry:
			decode_before_retry = OS.get_environment("VPX_DECODE")
		OS.set_environment("VPX_DECODE", "sw")
		software_retry = true
		return
	if software_retry:
		OS.set_environment("VPX_DECODE", decode_before_retry)
		software_retry = false
	if OS.get_environment("VPX_DECODE") in ["hw", "sw", "hardware", "software"]:
		return
	match Settings.decode_mode:
		Settings.DecodeMode.HARDWARE:
			OS.set_environment("VPX_DECODE", "hw")
		Settings.DecodeMode.SOFTWARE:
			OS.set_environment("VPX_DECODE", "sw")
		_:
			OS.set_environment("VPX_DECODE", "auto")


func _texture_ready(serial := -1) -> void:
	var deadline := Time.get_ticks_msec() + TEXTURE_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		if serial >= 0 and serial != open_serial:
			return
		if playback == null or bool(playback.get_stream_metadata().get("audio_only", false)):
			return
		var texture := get_video_texture()
		var info := playback.get_frame_info()
		if texture != null and texture.get_height() > 0 and (int(info.get("format", -1)) == 0 or playback.get_frame_serial() > 0):
			return
		await get_tree().process_frame


func toggle_pause() -> void:
	if playback == null:
		return
	paused = not paused
	Log.info("playback %s at %.1f s" % ["paused" if paused else "resumed", stream_position])


func seek_relative(seconds: float) -> void:
	seek_to(stream_position + seconds)


func restart() -> void:
	if playback == null:
		return
	seek_to(0.0)
	paused = false
	if not is_playing():
		play()


func seek_to(seconds: float) -> void:
	if playback == null:
		return
	var target := clampf(seconds, 0.0, get_stream_length())
	if is_equal_approx(stream_position, target):
		return
	Log.note_seek(stream_position, target)
	if not is_playing():
		play()
	stream_position = target


func aspect_ratio() -> float:
	if is_image():
		return float(image_info["width"]) / maxf(float(image_info["height"]), 1.0)
	var texture := get_video_texture()
	if texture == null or texture.get_height() == 0:
		return 16.0 / 9.0
	return float(texture.get_width()) / float(texture.get_height())


func content_aspect() -> float:
	var aspect := aspect_ratio()
	aspect = aspect * 2.0 if Settings.alpha_mask == Settings.AlphaMask.STACKED_BELOW else aspect
	var width := maxf(1.0 - Settings.crop_left - Settings.crop_right, 0.05)
	var height := maxf(1.0 - Settings.crop_top - Settings.crop_bottom, 0.05)
	return aspect * width / height


func bitrate_mbps() -> float:
	var length := get_stream_length()
	if length <= 0.1 or file_bytes <= 0:
		return 0.0
	return file_bytes * 8.0 / length / 1000000.0


func note_shown_frame() -> void:
	var now := Time.get_ticks_msec()
	var elapsed := float(now - shown_last_msec)
	shown_last_msec = now
	if elapsed <= 0.0 or elapsed > 1000.0:
		return
	shown_period_msec = elapsed if shown_period_msec <= 0.0 else shown_period_msec + (elapsed - shown_period_msec) * 0.08


func shown_fps() -> float:
	return 1000.0 / shown_period_msec if shown_period_msec > 0.0 else 0.0


func build_label() -> String:
	var label := Log.version_label()
	if playback != null:
		var extension_build := int(playback.get_frame_info().get("build", 0))
		if extension_build != Log.BUILD:
			label += " (extension b%d)" % extension_build
	return label


func playback_fps() -> float:
	if video_fps > 1.0:
		return video_fps
	return 30.0


func pixel_format_name() -> String:
	return FORMAT_NAMES.get(int(frame_info.get("format", -1)), "—")


func _monitor_stream(delta: float) -> void:
	if load_state.get("status") not in ["ready", "buffering"]:
		return
	var path: String = load_state.get("path", "")
	if not path.contains("://") or path.begins_with("sacd://") or is_image() or playback == null:
		return
	var position := stream_position
	if paused or not is_playing() or absf(position - observed_position) > 0.03:
		observed_position = position
		stall_seconds = 0.0
		if load_state.get("status") == "buffering":
			load_state["status"] = "ready"
			load_changed.emit(load_state.duplicate(true))
		return
	stall_seconds += delta
	if stall_seconds >= 30.0:
		remember_position()
		_fail_load("connection", "This stream stopped responding. Check the connection, then retry.", "The playback position did not advance for 30 seconds.")
		stop()
	elif stall_seconds >= 3.0 and load_state.get("status") != "buffering":
		load_state["options"]["start_time"] = position
		load_state["status"] = "buffering"
		load_changed.emit(load_state.duplicate(true))
