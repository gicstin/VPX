extends Node

const LOG_PATH := "user://vpx.log"
const PREVIOUS_LOG_PATH := "user://vpx.prev.log"
const WIVRN_LOG_SUBDIR := "wivrn/wivrn-dashboard"
const STATS_INTERVAL := 5.0
const SEEK_LOG_DELAY := 0.4
const SETTING_LOG_DELAY := 0.4
const BUILD := 202
const HMD_LOG_PATH := "user://hmd.log"
const HMD_TAIL_BYTES := 65536
const WIVRN_TAIL_BYTES := 1048576
const HMD_FIELDS := ["FPS", "Stale", "Tear", "Early", "CPU&GPU", "GPU%"]

var file: FileAccess
var stats_timer := 0.0
var frames_since_report := 0
var worst_frame_ms := 0.0
var slow_frames := 0
var process_ms_total := 0.0
var player: VPXPlayer
var render_screen: Node3D
var video_layer: Node
var last_position := 0.0
var last_path := ""
var seek_adjustment := 0.0
var playing_seconds := 0.0
var last_video_frame_msec := 0
var pending_seek_from := 0.0
var pending_seek_target := 0.0
var pending_seek_count := 0
var pending_seek_wait := 0.0
var pending_seek_path := ""
var seek_serial := 0
var pending_setting_name := &""
var pending_setting_value: Variant
var pending_setting_count := 0
var pending_setting_wait := 0.0
var video_frames := 0
var video_drops := 0
var cadence := [0, 0, 0, 0]
var xr_interface: XRInterface
var hmd_pid := -1
var hmd_offset := 0
var picture_stalled := false


func _init() -> void:
	if Engine.is_editor_hint() or OS.has_environment("VPX_XR_FALLBACK"):
		return
	if RenderingServer.get_current_rendering_driver_name() == "opengl3":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _ready() -> void:
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(PREVIOUS_LOG_PATH))
	file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	info("VPX start %s | Godot %s | %s | %s" % [version_label(), Engine.get_version_info().string, OS.get_name(), OS.get_processor_name()])
	info("log file: %s" % ProjectSettings.globalize_path(LOG_PATH))
	if OS.get_name() == "Linux":
		_log_wivrn_stream()
		_start_hmd_capture()


func version_label() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return "%s (b%d)" % [version, BUILD] if not version.is_empty() else "b%d" % BUILD


func _log_wivrn_stream() -> void:
	var state_home := OS.get_environment("XDG_STATE_HOME")
	if state_home.is_empty():
		state_home = OS.get_environment("HOME").path_join(".local/state")
	var directory := state_home.path_join(WIVRN_LOG_SUBDIR)
	var newest := ""
	for name in DirAccess.get_files_at(directory):
		if name.begins_with("server_logs_") and name > newest:
			newest = name
	if newest.is_empty():
		return
	var stream := FileAccess.open(directory.path_join(newest), FileAccess.READ)
	if stream == null:
		return
	stream.seek(maxi(0, stream.get_length() - WIVRN_TAIL_BYTES))
	var text := stream.get_buffer(stream.get_length() - stream.get_position()).get_string_from_utf8()
	var start := text.rfind("Encoder configuration:")
	if start < 0:
		return
	var parts := PackedStringArray()
	var lines := text.substr(start).split("\n")
	for i in range(1, mini(lines.size(), 12)):
		var line := lines[i].get_slice("]", 1).strip_edges()
		if not (line.begins_with("*") or line.begins_with("size:") or line.begins_with("bitrate:")):
			break
		parts.append(line.trim_prefix("* "))
	info("wivrn stream: %s (%s)" % [" ".join(parts), newest])


func note_cadence(refreshes: int) -> void:
	cadence[clampi(refreshes, 1, 4) - 1] += 1


func bind_player(p: VideoStreamPlayer, xr: XRInterface) -> void:
	player = p
	xr_interface = xr
	last_video_frame_msec = 0
	info("session settings: decode=%d background=%d compositor_layer=%s projection=%d stereo=%d follow_posture=%s video_follow=%s" % [
		Settings.decode_mode, Settings.background, Settings.compositor_layer, Settings.projection, Settings.stereo,
		Settings.follow_posture, Settings.video_follow,
	])
	if xr_interface != null and xr_interface.has_method("get_supported_environment_blend_modes"):
		info("XR blend modes: %s" % str(xr_interface.get_supported_environment_blend_modes()))


func bind_render_state(screen: Node3D, layer: Node) -> void:
	render_screen = screen
	video_layer = layer


func _process(delta: float) -> void:
	if player != null:
		if player.current_path != last_path:
			last_path = player.current_path
			last_position = player.stream_position
			seek_adjustment = 0.0
			playing_seconds = 0.0
		if not player.current_path.is_empty() and player.is_playing() and not player.paused:
			playing_seconds += delta
	if pending_seek_count > 0:
		pending_seek_wait += delta
		if pending_seek_wait >= SEEK_LOG_DELAY:
			_flush_seek()
	if pending_setting_count > 0:
		pending_setting_wait += delta
		if pending_setting_wait >= SETTING_LOG_DELAY:
			_flush_setting()
	frames_since_report += 1
	worst_frame_ms = maxf(worst_frame_ms, delta * 1000.0)
	if delta > 0.025:
		slow_frames += 1
	process_ms_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	stats_timer += delta
	if stats_timer < STATS_INTERVAL:
		return
	var viewport := get_viewport()
	var viewport_rid := viewport.get_viewport_rid()
	var display_fps := frames_since_report / stats_timer
	var line := "display %.1f fps | worst %.1f ms | over 25 ms %d | avg process %.1f ms | render cpu %.1f ms gpu %.1f ms | mem %.0f MB | vram %.0f MB | src %.2f fps" % [
		display_fps, worst_frame_ms, slow_frames, process_ms_total / frames_since_report,
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
		RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
		OS.get_static_memory_usage() / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		player.playback_fps() if player != null and not player.current_path.is_empty() else 0.0,
	]
	if xr_interface:
		line += " | xr refresh %.0f Hz" % xr_interface.get_display_refresh_rate()
	if player != null and not player.current_path.is_empty():
		var texture := player.get_video_texture()
		var advanced := player.stream_position - last_position - seek_adjustment
		last_position = player.stream_position
		seek_adjustment = 0.0
		var video_fps := video_frames / stats_timer
		var drift := advanced - playing_seconds
		var frame_info: Dictionary = player.playback.get_frame_info() if player.playback != null else {}
		var tier := int(frame_info.get("adaptive_tier", 0))
		var hardware := bool(frame_info.get("hardware", false))
		line += " | video %s pos %.1f s fps %.2f bitrate %.1f Mbps advanced %.2f s wall %.2f s drift %+.2f s drops %d tier %d hw %s paused %s" % [
			"%dx%d" % [texture.get_width(), texture.get_height()] if texture else "no texture",
			player.stream_position, video_fps, player.bitrate_mbps(), advanced, stats_timer, drift, video_drops, tier, str(hardware),
			"yes" if player.paused or not player.is_playing() else "no",
		]
		line += " | cadence 1:%d 2:%d 3:%d 4+:%d" % cadence
		var frame_age := -1.0 if last_video_frame_msec <= 0 else float(Time.get_ticks_msec() - last_video_frame_msec) / 1000.0
		var layer_active := bool(video_layer.call("is_active")) if video_layer != null and video_layer.has_method("is_active") else false
		var screen_visible := bool(render_screen.visible) if render_screen != null else true
		line += " | render screen=%s hidden_by_layer=%s comp_layer=%s frame_age=%.1f" % [
			str(screen_visible) if render_screen != null else "?",
			str(render_screen.get("hidden_by_layer")) if render_screen != null else "?",
			str(layer_active), frame_age,
		]
		var playing := not player.paused and player.is_playing()
		var layer_covers_screen := layer_active and render_screen != null and bool(render_screen.get("hidden_by_layer"))
		var picture_visible := screen_visible or layer_covers_screen
		if playing and not player.is_music_mode() and not player.is_image() and (not picture_visible or frame_age > 1.0):
			if not picture_stalled:
				picture_stalled = true
				warn("picture stalled while sound continues (frame age %.1f s, screen visible %s, compositor %s). Sleep timer is not this: shortest is 15 min and it pauses sound." % [frame_age, str(screen_visible), str(layer_active)])
		elif picture_stalled and frame_age >= 0.0 and frame_age < 0.5 and picture_visible:
			picture_stalled = false
			info("picture moving again")
	cadence = [0, 0, 0, 0]
	var hmd := _hmd_summary()
	if not hmd.is_empty():
		line += " | hmd " + hmd
	info(line)
	stats_timer = 0.0
	frames_since_report = 0
	worst_frame_ms = 0.0
	slow_frames = 0
	process_ms_total = 0.0
	video_frames = 0
	video_drops = 0
	playing_seconds = 0.0


func info(message: String) -> void:
	var line := "[%s +%.3f] %s" % [Time.get_time_string_from_system(), Time.get_ticks_msec() / 1000.0, message]
	print(line)
	if file != null:
		file.store_line(line)
		file.flush()


func warn(message: String) -> void:
	info("WARNING: " + message)


func note_video_frame() -> void:
	video_frames += 1
	last_video_frame_msec = Time.get_ticks_msec()


func note_seek(from: float, target: float) -> void:
	if is_equal_approx(from, target):
		return
	seek_serial += 1
	seek_adjustment += target - from
	var path := player.current_path if player != null else ""
	if pending_seek_count > 0 and pending_seek_path != path:
		_flush_seek()
	if pending_seek_count == 0:
		pending_seek_from = from
		pending_seek_path = path
	pending_seek_target = target
	pending_seek_count += 1
	pending_seek_wait = 0.0


func _flush_seek() -> void:
	if pending_seek_count == 0:
		return
	info("seek %.1f -> %.1f s (%d request%s)" % [pending_seek_from, pending_seek_target, pending_seek_count, "" if pending_seek_count == 1 else "s"])
	pending_seek_count = 0
	pending_seek_wait = 0.0
	pending_seek_path = ""


func note_setting(property: StringName, value: Variant) -> void:
	if pending_setting_count > 0 and pending_setting_name != property:
		_flush_setting()
	pending_setting_name = property
	pending_setting_value = value
	pending_setting_count += 1
	pending_setting_wait = 0.0


func _flush_setting() -> void:
	if pending_setting_count == 0:
		return
	info("setting %s = %s (%d update%s)" % [pending_setting_name, pending_setting_value, pending_setting_count, "" if pending_setting_count == 1 else "s"])
	pending_setting_count = 0
	pending_setting_wait = 0.0


func _start_hmd_capture() -> void:
	var output := []
	if OS.execute("adb", ["devices"], output) != 0 or output.is_empty():
		return
	var serial := ""
	for row in String(output[0]).split("\n"):
		var columns := row.split("\t")
		if columns.size() == 2 and columns[1].strip_edges() == "device" and (serial.is_empty() or columns[0].contains(":")):
			serial = columns[0]
	if serial.is_empty():
		return
	var path := ProjectSettings.globalize_path(HMD_LOG_PATH)
	hmd_pid = OS.create_process("sh", ["-c", "exec adb -s '%s' logcat -T 1 -v time VrApi:I WiVRn:V *:S > '%s'" % [serial, path]])
	info("hmd capture: %s -> %s" % [serial, path])


func _hmd_summary() -> String:
	if hmd_pid < 0:
		return ""
	var hmd_file := FileAccess.open(HMD_LOG_PATH, FileAccess.READ)
	if hmd_file == null:
		return ""
	var length := hmd_file.get_length()
	if length < hmd_offset:
		hmd_offset = 0
	if length <= hmd_offset:
		return ""
	var start := maxi(hmd_offset, length - HMD_TAIL_BYTES)
	hmd_file.seek(start)
	var chunk := hmd_file.get_buffer(length - start).get_string_from_ascii()
	var found := chunk.rfind("FPS=")
	hmd_offset = length
	if found < 0:
		return ""
	var latest := chunk.substr(chunk.rfind("\n", found) + 1).get_slice("\n", 0)
	var values := PackedStringArray()
	for pair in latest.get_slice(": ", 1).split(","):
		if pair.get_slice("=", 0) in HMD_FIELDS:
			values.append(pair)
	return " ".join(values)


func _exit_tree() -> void:
	if hmd_pid > 0:
		OS.kill(hmd_pid)
	_flush_seek()
	_flush_setting()
	info("VPX exit")
	if file != null:
		file.close()
