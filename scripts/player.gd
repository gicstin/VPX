class_name VPXPlayer
extends VideoStreamPlayer

signal load_changed(state: Dictionary)
signal opened(path: String)
signal ended
signal marks_changed
signal sleep_finished
signal music_changed
signal music_ended
signal music_metadata_changed

const AUDIO_EXTENSIONS := ["mp3", "flac", "wav", "ogg", "opus", "oga", "m4a", "aac", "mka", "ac3", "eac3", "dts", "wma", "aiff", "aif", "m4b", "aob", "dsf"]
const ALPHA_PROBE_KEY := "alpha_detected"

const FORMAT_NAMES := {0: "rgba", 1: "yuv420p", 2: "yuva420p", 3: "nv12", 4: "p010", 5: "yuv420p10"}
const POSITION_SAVE_INTERVAL := 5.0
const BOOKMARK_MERGE := 2.0
const BOOKMARK_NAME_MAX := 64
const BOOKMARK_HISTORY_MAX := 32
const CHAPTER_BACK_GRACE := 3.0
const LOOP_MIN_LENGTH := 0.5
const SLEEP_FADE := 20.0
const OUTPUT_BUS := "VPX media output"
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
var image_file_info := {}
var loading_file_info := {}
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
var decode_setting_before_retry := ""
var playback_state := {}
var stall_seconds := 0.0
var observed_position := 0.0
var observed_progress := -1
var opening_stream: FFmpegVideoStream
var discarded_streams: Array[FFmpegVideoStream] = []
var retired_streams: Array[FFmpegVideoStream] = []
var source_tasks: Array[int] = []
var prefetch_serial := 0
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
var radio := preload("res://scripts/radio_metadata.gd").new()
var radio_metadata_timer := 0.0
var watch_history := preload("res://scripts/watch_history.gd").new()


func _ready() -> void:
	var output_index := AudioServer.get_bus_index(OUTPUT_BUS)
	if output_index < 0:
		AudioServer.add_bus(1)
		output_index = 1
		AudioServer.set_bus_name(output_index, OUTPUT_BUS)
		AudioServer.set_bus_send(output_index, "Master")
	bus = OUTPUT_BUS
	add_child(tracks)
	add_child(auto_crop)
	add_child(radio)
	radio.changed.connect(music_metadata_changed.emit)
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
	for i in range(source_tasks.size() - 1, -1, -1):
		var task := source_tasks[i]
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			source_tasks.remove_at(i)
	for i in range(discarded_streams.size() - 1, -1, -1):
		if discarded_streams[i].get_open_status() != 1:
			discarded_streams.remove_at(i)
	for i in range(retired_streams.size() - 1, -1, -1):
		if retired_streams[i].get_playback().is_io_stopped():
			retired_streams.remove_at(i)
	if image_loader != null:
		_poll_image()
	elif not prefetched.is_empty():
		_poll_prefetch()
	for i in range(discarded_loaders.size() - 1, -1, -1):
		if discarded_loaders[i].is_decoded():
			discarded_loaders.remove_at(i)
	if paused and playback != null and not current_path.is_empty():
		playback.pump_paused(delta)
	_monitor_stream(delta)
	_update_radio_metadata(delta)
	_update_sleep(delta)
	if playback != null and not watch_history.path.is_empty() and not watch_history.counted:
		watch_history.sample(stream_position, get_stream_length(), not paused and is_playing() and (not is_image() or not music_path.is_empty()) and (image_loader == null or not music_path.is_empty()), _audio_only_playing())
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
		if opening_stream != null:
			opening_stream.cancel_open()
		for video in discarded_streams:
			video.cancel_open()
		if playback != null:
			playback.cancel_io()


func _update_radio_metadata(delta: float) -> void:
	if playback == null or not _audio_only_playing() or not stream is FFmpegVideoStream or not _network_path((stream as FFmpegVideoStream).file):
		radio.follow("", "")
		return
	radio.follow(bookmark_path(), (stream as FFmpegVideoStream).file)
	radio_metadata_timer -= delta
	if radio_metadata_timer <= 0.0:
		radio_metadata_timer = 0.5
		radio.apply_stream(playback.get_stream_metadata())


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
	return path.begins_with("sacd://") or path.get_slice("?", 0).get_slice("#", 0).get_extension().to_lower() in AUDIO_EXTENSIONS


func _on_finished() -> void:
	if replacing_stream:
		return
	watch_history.sample(get_stream_length(), get_stream_length(), true, _audio_only_playing())
	if not music_path.is_empty() and (image != null or image_loader != null):
		var song := music_path
		Settings.remember_position(song, 0.0, 0.0)
		Library.mark_finished(song)
		Log.info("music ended %s" % song.get_file())
		music_ended.emit()
		return
	Settings.remember_position(current_path, 0.0, 0.0)
	ended.emit()


func apply_audio() -> void:
	var fade := 1.0
	if sleep_armed > 0 and Settings.sleep_timer != Settings.SleepTimer.END_OF_VIDEO:
		fade = clampf(sleep_left / SLEEP_FADE, 0.0, 1.0)
	volume_db = 0.0
	var output_index := AudioServer.get_bus_index(OUTPUT_BUS)
	AudioServer.set_bus_volume_db(output_index, linear_to_db(Settings.volume / 100.0 * fade) if Settings.volume > 0 and fade > 0.0 else -80.0)
	AudioServer.set_bus_mute(output_index, Settings.muted or Settings.volume == 0 or fade <= 0.0)


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
	observed_progress = -1
	var request_options := options.duplicate(true)
	load_options = request_options
	load_state = {"path": path, "status": "opening", "stage": "Opening media…", "options": load_options}
	load_changed.emit(load_state.duplicate(true))
	var ok := await _open_source(path, request_options, serial)
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


func _retire_stream() -> void:
	if playback == null or not stream is FFmpegVideoStream:
		return
	playback.cancel_io()
	retired_streams.append(stream as FFmpegVideoStream)


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
	var preparing := opening_stream != null
	if opening_stream != null:
		opening_stream.cancel_open()
		discarded_streams.append(opening_stream)
		opening_stream = null
	if is_instance_valid(image_request):
		image_request.cancel_request()
		image_request.queue_free()
		image_request = null
	_discard_loader()
	if not preparing and playback != null and (music_path == load_state.get("path", "") or (current_path == load_state.get("path", "") and not PanoramaFiles.is_image(current_path))):
		_retire_stream()
		stop()
		stream = null
		playback = null
		playback_state.clear()
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
	var source_info := await _inspect_source(path, serial)
	if serial != open_serial:
		return false
	if load_state.get("status") == "failed":
		return false
	if not source_info.get("exists", true):
		_fail_load("missing", "This file is missing or its drive is disconnected.", "File not found: " + path)
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
		_open_image(path, keep_music, source_info)
		while serial == open_serial and image_loader != null:
			await get_tree().process_frame
		return serial == open_serial and load_error.is_empty() and image != null
	if picture and (_is_audio_item(path) or bool(options.get("audio_only", false))):
		return await _play_with_picture(path, options, serial, source_info)
	_apply_decode_mode(bool(options.get("software", false)))
	var video := _create_stream(path, options)
	if not await _prepare_stream(video, serial):
		return false
	Settings.format_path = ""
	stream_metadata = {}
	content_rotation = Basis.IDENTITY
	cube_padding = 0.0
	auto_crop.cancel()
	auto_cropped = false
	music_path = ""
	_close_image()
	tracks.reset()
	_load_stage("Starting decoder…")
	Log.info("open %s (decode mode %d)" % [path, Settings.decode_mode])
	replacing_stream = true
	_retire_stream()
	playback = null
	playback_state.clear()
	frame_info = {}
	video_fps = 0.0
	probe_wanted = false
	stream = video
	replacing_stream = false
	current_path = path
	watch_history.begin(path)
	file_bytes = int(source_info.get("bytes", 0))
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
	tracks.load_for(path, playback, source_info.get("subtitles", []))
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
	playback_state = {"path": path, "status": "ready", "options": options.duplicate(true)}
	opened.emit(path)
	return playback != null


static func _network_path(path: String) -> bool:
	return path.contains("://") and not path.begins_with("sacd://") and not path.begins_with("vpxzip://") and not path.begins_with("file://") and not path.begins_with("res://") and not path.begins_with("user://")


func _create_stream(path: String, options: Dictionary) -> FFmpegVideoStream:
	var video := FFmpegVideoStream.new()
	video.file = str(options.get("stream", path))
	video.audio_file = str(options.get("audio", ""))
	video.http_headers = str(options.get("headers", ""))
	var input_format := str(options.get("input_format", "dsf" if path.begins_with("sacd://") else ""))
	if not input_format.is_empty() and ClassDB.class_has_method("FFmpegVideoStream", "set_input_format"):
		video.call("set_input_format", input_format)
	return video


func _prepare_stream(video: FFmpegVideoStream, serial: int) -> bool:
	_load_stage("Connecting to stream…" if _network_path(video.file) or _network_path(video.audio_file) else "Opening media file…")
	opening_stream = video
	if video.begin_open() != OK:
		opening_stream = null
		load_error = "Could not start the stream connection"
		return false
	var deadline := Time.get_ticks_msec() + 15000
	while serial == open_serial and video.get_open_status() == 1:
		if Time.get_ticks_msec() >= deadline:
			video.cancel_open()
			discarded_streams.append(video)
			opening_stream = null
			_fail_load("connection", "This source stopped responding. Check the connection, then retry.", "The media decoder could not open the source within 15 seconds.")
			return false
		await get_tree().process_frame
	if serial != open_serial:
		return false
	opening_stream = null
	if video.get_open_status() != 2:
		load_error = video.get_open_error()
		var remote := _network_path(video.file) or _network_path(video.audio_file)
		_fail_load("connection" if remote else "decode", "Could not open this stream. Check that the source is online, then retry." if remote else "Could not play this file. It may be damaged or use an unsupported format.", load_error)
		return false
	return true


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
		playback.set_visualizer_enabled((Settings.music_visualizer and _audio_only_playing()) or is_immersive_visualizer_active())


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
	var path := bookmark_path()
	if path.is_empty() or (is_image() and music_path.is_empty()):
		return []
	var saved: Variant = Library.get_pref(path, "bookmarks", [])
	var times: Array = (saved as Array).duplicate() if saved is Array else []
	times.sort()
	return times


func bookmark_path() -> String:
	return music_path if not music_path.is_empty() else current_path


func bookmark_name(time: float) -> String:
	var names: Variant = Library.get_pref(bookmark_path(), "bookmark_names", {})
	if not names is Dictionary:
		return ""
	var title: Variant = names.get("%.1f" % time, "")
	return title if title is String else ""


func bookmark_name_history() -> PackedStringArray:
	var paths := Library.entries.keys()
	paths.sort_custom(func(a: String, b: String) -> bool: return float(Library.entries[a].get("seen", 0)) > float(Library.entries[b].get("seen", 0)))
	var result := PackedStringArray()
	var used := {}
	for path: String in paths:
		var history: Variant = Library.get_pref(path, "bookmark_name_history", [])
		if not history is Array:
			continue
		for title: Variant in history:
			if not title is String or title.is_empty() or used.has(title.to_lower()):
				continue
			result.append(title)
			used[title.to_lower()] = true
			if result.size() >= BOOKMARK_HISTORY_MAX:
				return result
	return result


func rename_bookmark(time: float, text: String) -> bool:
	if time not in bookmarks():
		return false
	var title := text.strip_edges()
	if title.length() > BOOKMARK_NAME_MAX:
		return false
	for i in title.length():
		if title.unicode_at(i) < 32:
			return false
	var path := bookmark_path()
	var saved: Variant = Library.get_pref(path, "bookmark_names", {})
	var names: Dictionary = saved.duplicate() if saved is Dictionary else {}
	var key := "%.1f" % time
	if title.is_empty():
		names.erase(key)
	else:
		names[key] = title
		var history: Variant = Library.get_pref(path, "bookmark_name_history", [])
		var recent: Array = history.filter(func(value: Variant) -> bool: return value is String and value.to_lower() != title.to_lower()) if history is Array else []
		recent.push_front(title)
		recent.resize(mini(recent.size(), BOOKMARK_HISTORY_MAX))
		Library.set_pref(path, "bookmark_name_history", recent)
	if names.is_empty():
		Library.erase_pref(path, "bookmark_names")
	else:
		Library.set_pref(path, "bookmark_names", names)
	marks_changed.emit()
	return true


func add_bookmark() -> float:
	var path := bookmark_path()
	if path.is_empty() or (is_image() and music_path.is_empty()):
		return -1.0
	var time := snappedf(stream_position, 0.1)
	var times := bookmarks()
	for existing: float in times:
		if absf(existing - time) < BOOKMARK_MERGE:
			return existing
	times.append(time)
	times.sort()
	Library.set_pref(path, "bookmarks", times)
	Log.info("bookmark at %.1f s" % time)
	marks_changed.emit()
	return time


func remove_bookmark(time: float) -> void:
	var path := bookmark_path()
	var saved: Variant = Library.get_pref(path, "bookmark_names", {})
	if saved is Dictionary:
		var names: Dictionary = saved.duplicate()
		names.erase("%.1f" % time)
		if names.is_empty():
			Library.erase_pref(path, "bookmark_names")
		else:
			Library.set_pref(path, "bookmark_names", names)
	var times := bookmarks().filter(func(existing: float) -> bool: return not is_equal_approx(existing, time))
	if times.is_empty():
		Library.erase_pref(path, "bookmarks")
	else:
		Library.set_pref(path, "bookmarks", times)
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
	return Settings.immersive_music_visualizer and (is_music_mode() or is_visualizer_overlay_active())


func is_visualizer_overlay_active() -> bool:
	if not Settings.immersive_music_visualizer or not Settings.visualizer_overlay or playback == null or is_music_mode():
		return false
	return _audio_only_playing() if is_image() else playback.get_audio_track() >= 0


func enter_immersive_music() -> void:
	if Settings.visualizer_overlay or not _audio_only_playing() or not is_image():
		return
	cancel_open()
	current_path = music_path
	music_path = ""
	_close_image()
	Settings.format_path = current_path
	Settings.clear_view_adjust()
	Settings.detecting = true
	Settings.apply("projection", Settings.ProjectionMode.FLAT)
	Settings.apply("stereo", Settings.Stereo.MONO)
	Settings.apply("swap_eyes", false)
	Settings.apply("alpha_mask", Settings.AlphaMask.NONE)
	Settings.detecting = false
	music_changed.emit()
	opened.emit(current_path)


func stop_music() -> void:
	if music_path.is_empty() and not _audio_only_playing():
		return
	music_path = ""
	replacing_stream = true
	_retire_stream()
	stream = null
	playback = null
	playback_state.clear()
	replacing_stream = false
	tracks.reset()
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


func _play_with_picture(path: String, options: Dictionary, serial: int, source_info := {}) -> bool:
	if serial != open_serial:
		return false
	_apply_decode_mode(bool(options.get("software", false)))
	var video := _create_stream(path, options)
	if not await _prepare_stream(video, serial):
		return false
	Log.info("music over picture %s" % path)
	tracks.reset()
	music_path = path
	watch_history.begin(path)
	replacing_stream = true
	_retire_stream()
	playback = null
	playback_state.clear()
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
		return false
	playback = video.get_playback()
	apply_priority()
	apply_speed()
	apply_audio_processing()
	await _texture_ready(serial)
	if serial != open_serial:
		return false
	if playback != null:
		tracks.load_for(path, playback, source_info.get("subtitles", []))
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
	playback_state = {"path": path, "status": "ready", "options": options.duplicate(true)}
	marks_changed.emit()
	music_changed.emit()
	return playback != null


func is_loading() -> bool:
	return image_loader != null


func has_picture() -> bool:
	return is_image() or get_video_texture() != null


func _open_image(path: String, keep_music := false, source_info := {}) -> void:
	loading_file_info = source_info
	if keep_music:
		if music_path.is_empty():
			music_path = current_path
		Log.info("picture over music %s" % music_path.get_file())
	else:
		tracks.reset()
		_retire_stream()
		stop()
		stream = null
		playback = null
		playback_state.clear()
		music_path = ""
		frame_info = {}
		video_fps = 0.0
	probe_wanted = false
	current_path = path
	file_bytes = int(source_info.get("bytes", 0))
	_discard_loader()
	image_source = Settings.panorama_source
	loading_path = path
	loading_started_msec = Time.get_ticks_msec()
	if prefetched.has(path):
		image_loader = prefetched[path]
		prefetched.erase(path)
		Log.info("open image %s from prefetch" % path)
	else:
		image_loader = _start_loader(path, source_info)
	if image_loader != null:
		_poll_image()
	else:
		load_error = "The image loader could not start for this source."


func prefetch_images(paths: PackedStringArray) -> void:
	prefetch_serial += 1
	for path: String in prefetched.keys():
		if path not in paths:
			_discard(prefetched[path])
			prefetched.erase(path)
	for path in paths:
		if path != current_path and not prefetched.has(path) and PanoramaFiles.is_image(path):
			_prefetch_image(path, prefetch_serial)


func _prefetch_image(path: String, serial: int) -> void:
	var info := await _inspect_source(path)
	if serial != prefetch_serial or path == current_path or prefetched.has(path) or not info.get("exists", false):
		return
	var loader := _start_loader(path, info)
	if loader != null:
		prefetched[path] = loader


func _start_loader(path: String, info: Dictionary) -> VPXPanorama:
	var faces: PackedStringArray = info.get("faces", PackedStringArray())
	var equirect: String = info.get("equirect", "")
	var use_cube := faces.size() == PanoramaFiles.CUBE_ORDER.size() and (Settings.panorama_source == Settings.PanoramaSource.CUBE or equirect.is_empty())
	var sources := faces if use_cube else PackedStringArray([equirect if not equirect.is_empty() else path])
	var wraps := use_cube
	if not use_cube:
		var saved: Variant = Library.get_pref(path, "format")
		if saved is Dictionary:
			wraps = int(saved.get("projection", -1)) == Settings.ProjectionMode.EQUIRECT_360 and int(saved.get("stereo", 0)) == Settings.Stereo.MONO
		else:
			var size: Vector2i = info.get("size", Vector2i.ZERO)
			var format := guess_format(path, float(size.x) / float(size.y) if size.y > 0 else 0.0)
			wraps = format["projection"] == Settings.ProjectionMode.EQUIRECT_360 and format["stereo"] == Settings.Stereo.MONO
	var loader := VPXPanorama.new()
	Log.info("load image %s as %s from %s" % [path, "cube" if use_cube else "single image", ", ".join(PackedStringArray(Array(sources).map(func(p: String) -> String: return p.get_file())))])
	if loader.start(sources, VPXPanorama.LAYOUT_CUBE if use_cube else VPXPanorama.LAYOUT_TILED, wraps) != OK:
		Log.warn("cannot load %s" % path)
		return null
	return loader


func _inspect_source(path: String, serial := -1) -> Dictionary:
	if path.contains("://") and not path.begins_with("res://") and not path.begins_with("user://"):
		return {}
	var result := {}
	var imported: Variant = Library.get_pref(path, "subtitle_files", [])
	var files: Array = imported.duplicate() if imported is Array else []
	var task := WorkerThreadPool.add_task(func() -> void: result.merge(_source_info(path, files)))
	var deadline := Time.get_ticks_msec() + 15000
	while not WorkerThreadPool.is_task_completed(task):
		if (serial >= 0 and serial != open_serial) or Time.get_ticks_msec() >= deadline:
			source_tasks.append(task)
			if serial >= 0 and serial == open_serial:
				_fail_load("connection", "This drive stopped responding. Check the connection, then retry.", "The media file could not be inspected within 15 seconds.")
			return {"exists": false}
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return result


static func _source_info(path: String, imported: Array) -> Dictionary:
	var exists := FileAccess.file_exists(path)
	var result := {"exists": exists, "bytes": FileAccess.get_size(path) if exists else 0}
	if not exists:
		return result
	if PanoramaFiles.is_image(path):
		result["faces"] = PanoramaFiles.cube_faces(path)
		result["equirect"] = PanoramaFiles.equirect_for(path)
		result["size"] = PanoramaFiles.probe_size(result["equirect"] if not str(result["equirect"]).is_empty() else path)
	else:
		var subtitles := MediaTracks.find_external(path)
		for external_path in imported:
			var file := str(external_path)
			if FileAccess.file_exists(file) and not subtitles.any(func(track: Dictionary) -> bool: return track["path"] == file):
				subtitles.append(MediaTracks._external_track(file, file.get_file()))
		result["subtitles"] = subtitles
	return result


func _poll_prefetch() -> void:
	for path: String in prefetched.keys():
		if prefetched[path].poll() == VPXPanorama.STATUS_FAILED:
			Log.warn("prefetch %s failed: %s" % [path, prefetched[path].get_error()])
			prefetched.erase(path)


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
	image_file_info = loading_file_info
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
		var info: Dictionary = loading_file_info if image_loader != null else image_file_info
		if info.get("faces", PackedStringArray()).size() == PanoramaFiles.CUBE_ORDER.size() and not str(info.get("equirect", "")).is_empty():
			open(current_path)


func apply_priority() -> void:
	if playback != null:
		playback.set_smooth_decode(Settings.playback_priority == Settings.PlaybackPriority.SMOOTH)


func apply_speed() -> void:
	if playback != null and playback.has_method("set_tempo_quality"):
		playback.set_tempo_quality(Settings.audio_stretch_quality)
	var speed := 1.0 if is_live() else Settings.playback_speed
	if playback != null and not is_equal_approx(playback.get_speed(), speed):
		playback.set_speed(speed)
		Log.info("playback speed %.2f" % speed)


func _apply_decode_mode(force_software := false) -> void:
	OS.set_environment("VPX_PLAYBACK_PRIORITY", "sharp" if Settings.playback_priority == Settings.PlaybackPriority.SHARP else "smooth")
	if software_retry:
		OS.set_environment("VPX_DECODE", decode_before_retry)
		OS.set_environment("VPX_DECODE_SETTING", decode_setting_before_retry)
		software_retry = false
	if force_software:
		decode_before_retry = OS.get_environment("VPX_DECODE")
		decode_setting_before_retry = OS.get_environment("VPX_DECODE_SETTING")
		OS.set_environment("VPX_DECODE", "sw")
		OS.set_environment("VPX_DECODE_SETTING", "sw")
		software_retry = true
		return
	var mode := OS.get_environment("VPX_DECODE").to_lower()
	if mode in ["hw", "sw", "hardware", "software"] and mode != OS.get_environment("VPX_DECODE_SETTING"):
		return
	match Settings.decode_mode:
		Settings.DecodeMode.HARDWARE:
			mode = "hw"
		Settings.DecodeMode.SOFTWARE:
			mode = "sw"
		_:
			mode = "auto"
	OS.set_environment("VPX_DECODE", mode)
	OS.set_environment("VPX_DECODE_SETTING", mode)


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


func can_seek() -> bool:
	return playback != null and get_stream_length() > 0.0


func is_live() -> bool:
	return playback != null and not can_seek() and (_network_path(current_path) or _network_path(music_path))


func restart() -> void:
	if playback == null:
		return
	if watch_history.counted:
		watch_history.begin(music_path if not music_path.is_empty() else current_path)
	seek_to(0.0)
	paused = false
	if not is_playing():
		play()


func seek_to(seconds: float) -> void:
	if not can_seek():
		return
	var target := clampf(seconds, 0.0, get_stream_length())
	if is_equal_approx(stream_position, target):
		return
	Log.note_seek(stream_position, target)
	stall_seconds = 0.0
	observed_progress = -1
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


func playback_fps() -> float:
	if video_fps > 1.0:
		return video_fps
	return 30.0


func pixel_format_name() -> String:
	return FORMAT_NAMES.get(int(frame_info.get("format", -1)), "—")


func _monitor_stream(delta: float) -> void:
	if load_state.get("status") == "opening" or playback_state.get("status") not in ["ready", "buffering"]:
		return
	if playback == null or not stream is FFmpegVideoStream:
		return
	var video := stream as FFmpegVideoStream
	if not _network_path(video.file) and not _network_path(video.audio_file):
		return
	var progress := playback.get_progress_state()
	var serial := int(progress.get("serial", 0))
	var position := stream_position
	if paused or not is_playing() or serial != observed_progress:
		observed_progress = serial
		observed_position = position
		stall_seconds = 0.0
		if playback_state.get("status") == "buffering":
			playback_state["status"] = "ready"
			if load_state.get("path") == playback_state["path"] and load_state.get("status") == "buffering":
				load_state = playback_state.duplicate(true)
				load_changed.emit(load_state.duplicate(true))
		return
	if int(progress.get("error", 0)) != 0:
		remember_position()
		playback_state["status"] = "failed"
		load_state = playback_state.duplicate(true)
		_fail_load("connection", "This stream stopped responding. Check the connection, then retry.", "The media decoder could not read more data (error %s)." % progress["error"])
		playback.cancel_io()
		stop()
		return
	stall_seconds += delta
	if stall_seconds >= 30.0:
		remember_position()
		playback_state["status"] = "failed"
		load_state = playback_state.duplicate(true)
		_fail_load("connection", "This stream stopped responding. Check the connection, then retry.", "No video frames or audio samples arrived for 30 seconds.")
		playback.cancel_io()
		stop()
	elif stall_seconds >= 3.0 and (playback_state.get("status") != "buffering" or load_state.get("path") != playback_state["path"] or load_state.get("status") != "buffering"):
		playback_state["options"]["start_time"] = position
		playback_state["status"] = "buffering"
		load_state = playback_state.duplicate(true)
		load_changed.emit(load_state.duplicate(true))
