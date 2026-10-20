extends Node3D

const MENU_DISTANCE := 1.5
const DESKTOP_VIEW := preload("res://scripts/desktop_view.gd")
const DisplayMode := preload("res://scripts/display_mode.gd")
const VRSeekBar := preload("res://scripts/vr_seek_bar.gd")
const MusicPanel := preload("res://scripts/music_panel.gd")
const ZoomIndicator := preload("res://scripts/zoom_indicator.gd")
const LevelGauge := preload("res://scripts/level_gauge.gd")
const DESKTOP_REFRESH_RATE := 90.0
const REFRESH_MATCH_TOLERANCE := 0.02
const ROLL_DEADZONE := 4.0
const DRAG_DEADZONE := 1.0
const SPHERE_GRAB_RADIUS := 50.0
const LEVEL_RATE := 6.0
const LEVEL_SNAP := 5.0
const RELEASE_ROLL_SNAP := 3.0
const RELEASE_PITCH_SNAP := 2.0
const LEVEL_PITCH_MAX := 70.0
const LEVEL_PAN_PITCH_LIMIT := 89.0
const TURN_MIN_HORIZONTAL := 0.08
const RECLINE_LOOK_UP := 30.0
const RECLINE_LOOK_DOWN := 60.0
const RECLINE_HEAD_TILT := 35.0
const RECLINE_HYSTERESIS := 10.0
const GAIN_FADE_START := 120.0
const GAIN_POLE_FADE := Vector2(0.2, 0.5)
const MENU_FOLLOW_ANGLE := 55.0
const MENU_FOLLOW_DELAY := 0.6
const MENU_FOLLOW_RATE := 7.0
const MENU_DIM := 0.25
const DIM_RATE := 14.0
const VOLUME_STEP := 10
const HMD_POLL_SECONDS := 3.0
const XR_FALLBACK_ENV := "VPX_XR_FALLBACK"
const WANT_XR_ENV := "VPX_WANT_XR"
const NUMERIC_ACTIONS := {
	Settings.StickAction.SCREEN_SIZE: ["screen_size", 5.0, 20.0, 140.0, "Screen size", "%.0f°", 1.0],
	Settings.StickAction.BRIGHTNESS: ["brightness", 0.05, 0.2, 2.0, "Brightness", "%.0f%%", 100.0],
	Settings.StickAction.GAMMA: ["gamma", 0.1, 0.4, 2.2, "Gamma", "%.1f", 1.0],
	Settings.StickAction.SATURATION: ["saturation", 0.05, 0.0, 2.0, "Saturation", "%.0f%%", 100.0],
	Settings.StickAction.SHARPNESS: ["sharpness_level", 1.0, 0.0, 5.0, "Sharpness", "", 1.0],
	Settings.StickAction.VOLUME: ["volume", 10.0, 0.0, 100.0, "Volume", "%.0f%%", 1.0],
	Settings.StickAction.SCREEN_CURVE: ["screen_curve", 0.1, 0.0, 1.0, "Screen curve", "%.0f%%", 100.0],
	Settings.StickAction.STEREO_DEPTH: ["stereo_depth", 0.1, -3.0, 3.0, "3D depth", "%+.1f°", 1.0],
	Settings.StickAction.PICTURE_ZOOM: ["picture_zoom", 0.05, Settings.ZOOM_MIN, Settings.ZOOM_MAX, "Zoom", "%.0f%%", 100.0],
	Settings.StickAction.PLAYBACK_SPEED: ["playback_speed", 0.25, 0.5, 2.0, "Speed", "%.2f×", 1.0],
}
const MARK_ACTION_NAME := "Chapter / bookmark"
const TRACK_ACTION_NAMES := {
	Settings.StickAction.SUBTITLE_TRACK: "Subtitles",
	Settings.StickAction.AUDIO_TRACK: "Audio track",
}
const FORMAT_ACTION_NAMES := {
	Settings.StickAction.FORMAT_2D: "2D format",
	Settings.StickAction.FORMAT_3D: "3D format",
	Settings.StickAction.FORMAT_ALL: "Format",
}
const OneEuroFilter := preload("res://scripts/one_euro.gd")
const SubtitleView := preload("res://scripts/subtitle_view.gd")
const CinemaRoom := preload("res://scripts/cinema_room.gd")
const VideoLayer := preload("res://scripts/video_layer.gd")
const DESKTOP_SEEK_STEP := 10.0
const DESKTOP_SEEK_STEP_LARGE := 60.0
const KEY_TURN_DEGREES := 90.0
const KEY_REPEAT_DELAY := 0.45
const IMAGE_STEP_INTERVAL := 0.5
const SEEK_REPEAT_INTERVAL := 0.2
const KEY_FAST_FACTOR := 2.0
const KEY_NUMERIC_ACTIONS := {
	KEY_BRACKETLEFT: [Settings.StickAction.PLAYBACK_SPEED, -1],
	KEY_BRACKETRIGHT: [Settings.StickAction.PLAYBACK_SPEED, 1],
	KEY_MINUS: [Settings.StickAction.PICTURE_ZOOM, -1],
	KEY_KP_SUBTRACT: [Settings.StickAction.PICTURE_ZOOM, -1],
	KEY_EQUAL: [Settings.StickAction.PICTURE_ZOOM, 1],
	KEY_PLUS: [Settings.StickAction.PICTURE_ZOOM, 1],
	KEY_KP_ADD: [Settings.StickAction.PICTURE_ZOOM, 1],
	KEY_COMMA: [Settings.StickAction.STEREO_DEPTH, -1],
	KEY_PERIOD: [Settings.StickAction.STEREO_DEPTH, 1],
	KEY_SEMICOLON: [Settings.StickAction.BRIGHTNESS, -1],
	KEY_APOSTROPHE: [Settings.StickAction.BRIGHTNESS, 1],
}

@onready var camera: XRCamera3D = $Origin/Camera
@onready var screen_anchor: Node3D = $ScreenAnchor
@onready var screen: MeshInstance3D = $ScreenAnchor/Screen
@onready var panel: Node3D = $Panel
@onready var ui_viewport: SubViewport = $UIViewport
@onready var ui: Control = $UIViewport/UI
@onready var player: VPXPlayer = $Player
@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var osd: FloatPanel = $Osd
@onready var photo_bar = $PhotoBar
@onready var help_card: FloatPanel = $HelpCard

var music_visualizer: FloatPanel
var resonance_field: ResonanceField
var music_panel: MusicPanel
var zoom_indicator: ZoomIndicator
var level_gauge: LevelGauge
var xr_interface: XRInterface
var desktop_mode := false
var hmd_state := -1
var user_present_state := -1
var hmd_probe_busy := false
var hmd_probe_task := -1
var mode_switching := false
var mirror_mode_button: Button
var mirror_mode: SubViewport
var screenshot_path := ""
var frames := 0
var picking := false
var pick_busy := false
var grab_controller: XRController3D
var grab_point := Vector3.FORWARD
var grab_basis := Basis.IDENTITY
var grab_angles := Vector3.ZERO
var grab_pan := Vector2.ZERO
var roll_active := false
var drag_active := false
var grab_picture := Basis.IDENTITY
var grab_free := false
var grab_view := Basis.IDENTITY
var grab_content := Vector3.FORWARD
var level_yaw := 0.0
var level_roll := 0.0
var level_heading := 0.0
var reclined := false
var roll_filter := OneEuroFilter.new(1.5, 0.05)
var panel_grab_offset := Transform3D.IDENTITY
var panel_grabbed := false
var trigger_help_controller: XRController3D
var menu_dim := 1.0
var menu_away_time := 0.0
var menu_gliding := false
var video_glide_away_time := 0.0
var video_gliding := false
var video_glide_basis := Basis.IDENTITY
var video_glide_position := Vector3.ZERO
var video_glide_initializing := false
var haptic_note := ""
var last_blend_request := -1
var blend_fallback := false
var posture_blending := false
var auto_paused := false
var active_hand: XRController3D
var subtitle_view: SubtitleView
var video_layer: VideoLayer
var desktop_view: CanvasLayer
var seek_bar: VRSeekBar
var seek_bar_suppressed := false
var held_step_key := KEY_NONE
var held_step_direction := 0
var held_step_timer := 0.0


func _ready() -> void:
	if not _init_xr():
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	ui.previews.reparent(self)
	Log.bind_player(player, null if desktop_mode else xr_interface)
	subtitle_view = SubtitleView.new()
	subtitle_view.player = player
	subtitle_view.screen = screen
	subtitle_view.camera = camera
	add_child(subtitle_view)
	var room := CinemaRoom.new()
	room.screen = screen
	room.player = player
	room.anchor = screen_anchor
	add_child(room)
	video_layer = VideoLayer.new()
	video_layer.player = player
	video_layer.screen = screen
	video_layer.menu_panel = panel
	video_layer.origin = $Origin
	video_layer.xr_active = not desktop_mode
	video_layer.force_offscreen = OS.has_environment("VPX_LAYER_DEBUG")
	add_child(video_layer)
	photo_bar.main = self
	photo_bar.player = player
	photo_bar.ui = ui
	photo_bar.camera = camera
	for indicator: SpiritLevel in [ui.spirit_level, ui.quick.spirit_level]:
		indicator.screen = screen
		indicator.camera = camera
	if not desktop_mode:
		level_gauge = LevelGauge.new()
		add_child(level_gauge)
		level_gauge.strip.screen = screen
		level_gauge.strip.camera = camera
		music_panel = MusicPanel.new()
		music_panel.player = player
		music_panel.ui = ui
		music_panel.menu = panel
		music_panel.camera = camera
		music_panel.anchor = screen_anchor
		add_child(music_panel)
		zoom_indicator = ZoomIndicator.new()
		zoom_indicator.player = player
		zoom_indicator.camera = camera
		zoom_indicator.screen = screen
		zoom_indicator.menu = panel
		add_child(zoom_indicator)
	resonance_field = ResonanceField.new()
	resonance_field.vr_zoom = not desktop_mode
	resonance_field.camera = camera
	resonance_field.anchor = screen_anchor
	resonance_field.audio_anchor = screen
	resonance_field.menu = panel
	resonance_field.player = player
	add_child(resonance_field)
	resonance_field.activity_changed.connect(_apply_settings)
	room.resonance = resonance_field
	var visualizer := preload("res://scripts/music_visualizer.gd").new()
	visualizer.field = resonance_field
	visualizer.player = player
	visualizer.camera = camera
	visualizer.menu = panel
	visualizer.desktop_rect = photo_bar.root.spectrum_view if desktop_mode else music_panel.view.spectrum_view
	music_visualizer = visualizer
	add_child(visualizer)
	Log.bind_render_state(screen, video_layer)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	ui.quit_requested.connect(get_tree().quit)
	ui.close_requested.connect(panel.close)
	ui.recovery_requested.connect(func() -> void:
		panel.open()
		panel.place_in_front(camera, MENU_DISTANCE, desktop_mode or reclined))
	ui.recovery_finished.connect(func() -> void:
		if Settings.hide_menu_on_play and not player.paused:
			panel.close())
	ui.status_requested.connect(func(message: String, busy: bool) -> void:
		osd.show_status(message, camera, busy)
		if not busy:
			osd.remaining = 8.0)
	if not desktop_mode:
		seek_bar = VRSeekBar.new()
		seek_bar.player = player
		seek_bar.previews = ui.previews
		add_child(seek_bar)
	panel.visibility_changed.connect(func() -> void:
		if not panel.visible:
			ui.close_pickers())
	ui.pick_requested.connect(_start_pick)
	ui.recenter_requested.connect(center_screen)
	ui.reset_position_requested.connect(reset_picture_position)
	ui.level_requested.connect(reset_to_level)
	screen.view_origin = camera
	player.opened.connect(_on_opened)
	for controller in [$Origin/Left, $Origin/Right]:
		controller.visualizer = resonance_field
		controller.seek_bar = seek_bar
		if music_panel != null:
			controller.extra_panels.append(music_panel)
		controller.menu_toggled.connect(toggle_menu)
		controller.play_pause.connect(toggle_pause)
		controller.seek.connect(seek_relative)
		controller.file_step.connect(step_file)
		controller.volume_step.connect(step_volume)
		controller.grip_adjust.connect(_adjust.bind("grip_action"))
		controller.trigger_adjust.connect(_adjust.bind("trigger_action"))
		controller.chord_adjust.connect(_adjust.bind("chord_action"))
		controller.trigger_held_changed.connect(_on_trigger_held.bind(controller))
		controller.stick_tapped.connect(_cycle_visualizer_preset)
		controller.recenter_requested.connect(recenter)
		controller.recenter_progress.connect(_on_recenter_progress)
		controller.level_requested.connect(_level_view.bind(controller))
		controller.favorite_requested.connect(_toggle_favorite)
		controller.pick_triggered.connect(_on_pick.bind(controller))
		controller.pick_cancelled.connect(_stop_pick)
		controller.grab_started.connect(_on_grab_started.bind(controller))
		controller.grab_ended.connect(_on_grab_ended.bind(controller))
		controller.activated.connect(_set_active_hand.bind(controller))
	_set_active_hand($Origin/Right)
	if desktop_mode:
		_create_desktop_view()
	_create_mode_controls()
	player.ended.connect(_on_ended)
	player.sleep_finished.connect(func() -> void: _show_status("Sleep timer — paused"))
	if not OS.has_environment(DisplayMode.SESSION_ENV):
		_parse_arguments()
	await get_tree().process_frame
	recenter()
	var restored := await _restore_mode_session()
	if not restored and player.current_path.is_empty() and not Settings.last_file.is_empty():
		ui.open_media(Settings.last_file, {"paused": true})


func _create_desktop_view() -> void:
	for controller: XRController3D in [$Origin/Left, $Origin/Right]:
		controller.set_process(false)
	desktop_view = DESKTOP_VIEW.new()
	desktop_view.main = self
	desktop_view.camera = camera
	desktop_view.screen = screen
	desktop_view.panel = panel
	desktop_view.ui_viewport = ui_viewport
	desktop_view.osd = osd
	desktop_view.player = player
	add_child(desktop_view)


func _exit_tree() -> void:
	if hmd_probe_task >= 0:
		WorkerThreadPool.wait_for_task_completion(hmd_probe_task)


func _create_mode_controls() -> void:
	ui.set_display_mode(desktop_mode)
	ui.get_node("%ModeButton").pressed.connect(func() -> void: _switch_mode.call_deferred())
	if desktop_mode:
		return
	mirror_mode = preload("res://scripts/mirror_mode.gd").new()
	add_child(mirror_mode)
	mirror_mode_button = mirror_mode.button
	mirror_mode_button.pressed.connect(func() -> void: _switch_mode.call_deferred())


func _mode_session() -> Dictionary:
	return {
		"path": player.current_path,
		"music": player.music_path,
		"position": player.stream_position,
		"paused": player.paused and not auto_paused,
		"menu_open": panel.is_open(),
		"vr": desktop_mode,
	}


func _switch_mode() -> void:
	if mode_switching:
		return
	mode_switching = true
	ui.set_display_mode(desktop_mode, true)
	if mirror_mode_button != null:
		mirror_mode_button.disabled = true
	var previous_preference := Settings.prefer_desktop
	var previous_environment := {}
	for key in [XR_FALLBACK_ENV, WANT_XR_ENV, DisplayMode.SESSION_ENV]:
		previous_environment[key] = OS.get_environment(key) if OS.has_environment(key) else null
	OS.set_environment(DisplayMode.SESSION_ENV, JSON.stringify(_mode_session()))
	Settings.prefer_desktop = not desktop_mode
	Settings.save_config()
	Settings.flush()
	player.remember_position()
	if desktop_mode:
		OS.unset_environment(XR_FALLBACK_ENV)
		OS.set_environment(WANT_XR_ENV, "1")
	else:
		OS.unset_environment(WANT_XR_ENV)
	var mode := "on" if desktop_mode else "off"
	if _relaunch(PackedStringArray(["--xr-mode", mode]), "switching to %s" % ("VR" if desktop_mode else "desktop")):
		return
	for key: String in previous_environment:
		if previous_environment[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, previous_environment[key])
	Settings.prefer_desktop = previous_preference
	Settings.save_config()
	mode_switching = false
	ui.set_display_mode(desktop_mode)
	if mirror_mode_button != null:
		mirror_mode_button.disabled = false
	_mode_error("Could not restart VPX. Try switching again.")


func _restore_mode_session() -> bool:
	if not OS.has_environment(DisplayMode.SESSION_ENV):
		return false
	var session: Variant = JSON.parse_string(OS.get_environment(DisplayMode.SESSION_ENV))
	OS.unset_environment(DisplayMode.SESSION_ENV)
	if not session is Dictionary:
		return false
	var path := str(session.get("path", ""))
	var music := str(session.get("music", ""))
	var options := {"paused": bool(session.get("paused", true)), "start_time": float(session.get("position", 0.0))}
	if not path.is_empty():
		await ui.open_media(path, {} if not music.is_empty() and music != path else options)
	if not music.is_empty() and music != path:
		await ui.open_media(music, options)
	if bool(session.get("menu_open", true)) or ui.recovery.visible:
		panel.open()
	else:
		panel.close()
	if bool(session.get("vr", false)) and desktop_mode:
		_mode_error("VR unavailable. Connect the headset and start\nits OpenXR runtime, then try Enter VR again.")
	return true


func _mode_error(message: String) -> void:
	if not desktop_mode:
		panel.close()
		osd.show_status(message, camera)
		osd.remaining = 8.0
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Display mode"
	dialog.dialog_text = message
	dialog.theme = VpxTheme.build()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 140))


func _init_xr() -> bool:
	xr_interface = XRServer.find_interface("OpenXR")
	hmd_state = _wivrn_headset_connected()
	var xr_mode := _xr_mode_arg()
	var want_xr := OS.has_environment(WANT_XR_ENV) or xr_mode == "on"
	var desktop_requested := "--desktop" in OS.get_cmdline_user_args() or xr_mode == "off" or (Settings.prefer_desktop and not want_xr)
	if not desktop_requested and not want_xr and (xr_interface == null or not xr_interface.is_initialized()) and _headset_present():
		OS.set_environment(WANT_XR_ENV, "1")
		if _relaunch(PackedStringArray(["--xr-mode", "on"]), "headset connected, relaunching in VR"):
			return false
	var try_xr := not desktop_requested and xr_mode != "off" and xr_interface != null
	if try_xr and not want_xr and hmd_state == 0 and _active_openxr_runtime().containsn("wivrn"):
		try_xr = false
		Log.info("WiVRn has no headset connected, running in desktop mode")
	if try_xr and xr_interface.initialize():
		get_viewport().use_xr = true
		get_viewport().transparent_bg = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_log_blend_modes()
		_connect_session_signals()
		_watch_headset()
		_update_title.call_deferred()
		return true
	desktop_mode = true
	get_viewport().use_xr = false
	if xr_interface != null and xr_interface.is_initialized():
		xr_interface.uninitialize()
	if not desktop_requested and RenderingServer.get_current_rendering_driver_name() == "opengl3" and not OS.has_environment(XR_FALLBACK_ENV):
		OS.set_environment(XR_FALLBACK_ENV, "1")
		OS.unset_environment(WANT_XR_ENV)
		if _relaunch(PackedStringArray(["--xr-mode", "off"]), "OpenXR failed and rendering fell back to OpenGL, relaunching without XR"):
			return false
	Engine.max_fps = 90
	if not desktop_requested:
		push_warning("OpenXR unavailable, running in desktop mode")
	camera.position = Vector3(0, 1.6, 0)
	camera.current = true
	_watch_headset()
	_update_title.call_deferred()
	return true


func _update_title() -> void:
	var connected := hmd_state == 1 or (hmd_state == -1 and not desktop_mode)
	DisplayServer.window_set_title("VPX %s — %s%s" % [Log.version_label(), "Desktop" if desktop_mode else "VR", " (HMD Connected)" if connected else ""])


func _wivrn_headset_connected() -> int:
	if OS.get_name() != "Linux":
		return -1
	var output := []
	if OS.execute("busctl", ["--user", "--timeout=2", "get-property", "io.github.wivrn.Server", "/io/github/wivrn/Server", "io.github.wivrn.Server", "HeadsetConnected"], output) != 0 or output.is_empty():
		return -1
	match str(output[0]).strip_edges():
		"b true":
			return 1
		"b false":
			return 0
	return -1


func _active_openxr_runtime() -> String:
	var candidates := [OS.get_environment("XR_RUNTIME_JSON")]
	var config_home := OS.get_environment("XDG_CONFIG_HOME")
	if config_home.is_empty():
		config_home = OS.get_environment("HOME").path_join(".config")
	var config_dirs := OS.get_environment("XDG_CONFIG_DIRS")
	candidates.append(config_home.path_join("openxr/1/active_runtime.json"))
	for folder in (config_dirs if not config_dirs.is_empty() else "/etc/xdg").split(":"):
		candidates.append(folder.path_join("openxr/1/active_runtime.json"))
	for path: String in candidates:
		if not path.is_empty() and FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path)
	return ""


func _watch_headset() -> void:
	var timer := Timer.new()
	timer.wait_time = HMD_POLL_SECONDS
	add_child(timer)
	timer.timeout.connect(_probe_presence)
	timer.start()
	if not desktop_mode and xr_interface != null and xr_interface.has_signal("user_presence_changed"):
		xr_interface.user_presence_changed.connect(_on_presence_changed)


func _probe_headset() -> void:
	if hmd_probe_busy:
		return
	hmd_probe_busy = true
	hmd_probe_task = WorkerThreadPool.add_task(func() -> void: _on_headset_probed.call_deferred(_wivrn_headset_connected()))


func _probe_presence() -> void:
	if desktop_mode or xr_interface == null or not Settings.pause_when_removed:
		return
	if xr_interface.has_signal("user_presence_changed"):
		return
	if xr_interface.has_method("is_user_present"):
		_on_presence_changed(bool(xr_interface.call("is_user_present")))
	elif xr_interface.has_method("get_user_presence"):
		var presence: Variant = xr_interface.call("get_user_presence")
		if presence is bool:
			_on_presence_changed(presence)
	else:
		_probe_headset()


func _on_headset_probed(state: int) -> void:
	if hmd_probe_task >= 0:
		WorkerThreadPool.wait_for_task_completion(hmd_probe_task)
		hmd_probe_task = -1
	hmd_probe_busy = false
	if state == hmd_state:
		return
	hmd_state = state
	Log.info("WiVRn headset %s" % ("connected" if state == 1 else "disconnected" if state == 0 else "state unknown"))
	_update_title()


func _xr_mode_arg() -> String:
	var args := OS.get_cmdline_args()
	var index := args.find("--xr-mode")
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	for arg in args:
		if arg.begins_with("--xr-mode="):
			return arg.trim_prefix("--xr-mode=")
	return ""


func _headset_present() -> bool:
	if hmd_state == 1:
		return true
	if hmd_state == 0:
		return false
	return _steamvr_hmd_present()


func _steamvr_hmd_present() -> bool:
	if OS.get_name() != "Linux" or not _active_openxr_runtime().containsn("steamvr"):
		return false
	var output := []
	if OS.execute("ps", ["-C", "vrserver", "-o", "args="], output) != 0 or output.is_empty():
		return false
	return not "\n".join(output).contains("-waitformonitor")


func _relaunch(engine_args: PackedStringArray, reason: String) -> bool:
	var executable := OS.get_environment("VPX_LAUNCHER" if OS.get_name() == "Windows" else "APPIMAGE")
	var args := DisplayMode.engine_arguments(OS.get_cmdline_args())
	if executable.is_empty():
		executable = OS.get_executable_path()
		if not OS.has_feature("template") and not "--path" in args and not "--path=" in " ".join(args):
			args = PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]) + args
	if not FileAccess.file_exists(executable):
		Log.warn("Cannot restart: executable is missing")
		return false
	args.append_array(engine_args)
	var user_args := DisplayMode.user_arguments(OS.get_cmdline_user_args())
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	Log.info("%s: %s %s" % [reason, executable, " ".join(args)])
	var pid: int
	if OS.get_name() == "Windows":
		pid = OS.create_process(executable, args)
	else:
		pid = OS.create_process("sh", PackedStringArray(["-c", "sleep 1; exec \"$0\" \"$@\"", executable]) + args)
	if pid < 0:
		Log.warn("Could not restart VPX")
		return false
	get_tree().quit()
	return true


func _connect_session_signals() -> void:
	for pair in [["session_visible", _on_session_hidden], ["session_stopping", _on_session_hidden], ["session_focussed", _on_session_focussed], ["pose_recentered", recenter]]:
		if xr_interface.has_signal(pair[0]):
			xr_interface.connect(pair[0], pair[1])


func _on_session_hidden() -> void:
	Log.info("XR session not focused")
	if Settings.pause_when_removed and not player.paused and player.is_playing() and not player.is_image():
		player.paused = true
		auto_paused = true
		Log.info("headset not in use, paused")


func _on_presence_changed(present: bool) -> void:
	if user_present_state == int(present):
		return
	user_present_state = int(present)
	Log.info("headset presence %s" % ("detected" if present else "lost"))
	if present:
		_on_session_focussed()
	else:
		_on_session_hidden()


func _on_session_focussed() -> void:
	Log.info("XR session focused")
	last_blend_request = -1
	_apply_settings()
	if auto_paused and player.paused:
		player.paused = false
		Log.info("headset back, resumed")
	auto_paused = false


func _set_active_hand(controller: XRController3D) -> void:
	active_hand = controller
	for hand in [$Origin/Left, $Origin/Right]:
		hand.active = hand == controller


func _refresh_haptic_note() -> void:
	var active := false
	var vibrates := false
	for hand in [$Origin/Left, $Origin/Right]:
		if not hand.get_is_active():
			continue
		active = true
		vibrates = vibrates or hand.haptics_available()
	var key := "%s:%s" % [active, vibrates]
	if key == haptic_note:
		return
	haptic_note = key
	ui.set_haptic_note(active, vibrates)


func _update_menu_follow(delta: float) -> void:
	_update_video_glide(delta)
	if not panel.visible or not Settings.menu_follow or panel_grabbed or desktop_mode:
		menu_away_time = 0.0
		menu_gliding = false
		return
	var to_panel := panel.global_position - camera.global_position
	var angle := rad_to_deg(FloatPanel.level(to_panel).angle_to(FloatPanel.level_forward(camera)))
	var away := angle > MENU_FOLLOW_ANGLE
	if not menu_gliding:
		menu_away_time = menu_away_time + delta if away else 0.0
		menu_gliding = menu_away_time > MENU_FOLLOW_DELAY
		return
	var target := Transform3D(panel.global_transform)
	panel.place_in_front(camera, MENU_DISTANCE)
	var goal := panel.global_transform
	var weight := 1.0 - exp(-delta * MENU_FOLLOW_RATE)
	panel.global_transform = Transform3D(target.basis.slerp(goal.basis.orthonormalized(), weight), target.origin.lerp(goal.origin, weight))
	if angle < 5.0:
		menu_gliding = false
		menu_away_time = 0.0


func _update_video_glide(delta: float) -> void:
	if not _tracking_usable():
		return
	if desktop_mode or not Settings.video_follow or not player.has_picture() or panel_grabbed or grab_controller != null:
		video_glide_away_time = 0.0
		video_gliding = false
		video_glide_initializing = false
		return
	if not video_gliding:
		var gaze := -camera.global_basis.z
		var screen_direction := screen.global_position - camera.global_position if Settings.projection == Settings.ProjectionMode.FLAT else -screen.global_basis.z
		var angle := rad_to_deg(FloatPanel.level(screen_direction).angle_to(FloatPanel.level(gaze)))
		video_glide_away_time = video_glide_away_time + delta if angle > MENU_FOLLOW_ANGLE else 0.0
		if video_glide_away_time > MENU_FOLLOW_DELAY:
			video_gliding = true
			video_glide_initializing = true
			Log.info("screen recenter started after looking away %.1f°" % angle)
		return
	if video_glide_initializing:
		_bake_screen_pose()
		video_glide_basis = screen.global_basis
		video_glide_position = screen.global_position
		video_glide_initializing = false
	var head := _screen_follow_frame()
	var goal_position := camera.global_position
	if Settings.projection == Settings.ProjectionMode.FLAT:
		goal_position += head * Vector3(0.0, 0.0, -Settings.SCREEN_DISTANCE)
	var weight := 1.0 - exp(-delta * 1.8)
	video_glide_basis = video_glide_basis.slerp(head, weight).orthonormalized()
	video_glide_position = video_glide_position.lerp(goal_position, weight)
	var screen_goal := Transform3D(video_glide_basis, video_glide_position)
	screen_anchor.global_transform = screen_goal * screen.transform.affine_inverse()
	FloatPanel.frame = screen_anchor.global_basis
	if video_glide_basis.get_rotation_quaternion().angle_to(head.get_rotation_quaternion()) < deg_to_rad(0.5) and video_glide_position.distance_to(goal_position) < 0.01:
		Settings.angle_yaw = 0.0
		Settings.angle_pitch = 0.0
		Settings.angle_roll = 0.0
		screen.apply_angles()
		_align_anchor()
		if subtitle_view != null:
			subtitle_view.recenter()
		Settings.commit()
		video_gliding = false
		video_glide_away_time = 0.0


func _level_head(head: Basis) -> Basis:
	var forward := Vector3(-head.z.x, 0.0, -head.z.z)
	if forward.length_squared() < 0.001:
		forward = Vector3(-screen_anchor.global_basis.z.x, 0.0, -screen_anchor.global_basis.z.z)
		if forward.length_squared() < 0.001:
			forward = Vector3.FORWARD
	return Basis.looking_at(forward.normalized(), Vector3.UP)


func apply_recline_pose(head: Basis) -> bool:
	var gaze_pitch := rad_to_deg(asin(clampf(-head.z.y, -1.0, 1.0)))
	var head_tilt := rad_to_deg(asin(clampf(head.x.y, -1.0, 1.0)))
	var margin := RECLINE_HYSTERESIS if reclined else 0.0
	return Settings.follow_posture and (gaze_pitch > RECLINE_LOOK_UP - margin or gaze_pitch < -RECLINE_LOOK_DOWN + margin or absf(head_tilt) > RECLINE_HEAD_TILT - margin or head.y.y < 0.0)


func _log_blend_modes() -> void:
	if xr_interface == null or not xr_interface.has_method("get_supported_environment_blend_modes"):
		return
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	Log.info("XR blend modes %s (0=opaque 1=additive 2=alpha passthrough)" % str(modes))
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND not in modes:
		Log.warn("runtime has no alpha-blend passthrough; use chroma key if WiVRn server key is enabled")


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var open_path := ""
	for i in args.size():
		match args[i]:
			"--screenshot":
				if i + 1 < args.size():
					screenshot_path = args[i + 1]
			"--projection":
				if i + 1 < args.size():
					Settings.apply("projection", int(args[i + 1]))
			"--stereo":
				if i + 1 < args.size():
					Settings.apply("stereo", int(args[i + 1]))
			"--no-menu":
				panel.visible = false
			"--decode":
				if i + 1 < args.size():
					OS.unset_environment("VPX_DECODE_SETTING")
					match args[i + 1]:
						"hw", "hardware":
							OS.set_environment("VPX_DECODE", "hw")
						"sw", "software":
							OS.set_environment("VPX_DECODE", "sw")
						_:
							OS.set_environment("VPX_DECODE", "auto")
			"--open":
				if i + 1 < args.size():
					open_path = args[i + 1]
	if not open_path.is_empty():
		ui.open_media(open_path)


func _process(delta: float) -> void:
	_update_posture_frame(delta)
	_update_grab(delta)
	_update_held_step(delta)
	_update_vr_seek()
	screen.update_zoom_direction(camera.global_basis, delta, not desktop_mode)
	screen.update_auto_swap(camera.global_basis)
	_update_listener()
	_update_look_gain()
	if panel.visible and osd.visible and not osd.holding:
		osd.dismiss()
	_update_menu_dim(delta)
	_update_menu_follow(delta)
	_refresh_haptic_note()
	_update_spirit_level()
	if screenshot_path.is_empty():
		return
	frames += 1
	if frames == 240:
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		for eye in video_layer.viewports.size():
			video_layer.eye_image(eye).save_png(screenshot_path.get_basename() + "_layer%d.png" % eye)
		get_tree().quit()


func music_grab_moves_scene() -> bool:
	return desktop_mode if Settings.visualizer_grab_mode == Settings.VisualizerGrab.DEFAULT else Settings.visualizer_grab_mode == Settings.VisualizerGrab.SCENE_AND_AUDIO


func _update_listener() -> void:
	if player.playback == null:
		return
	player.playback.set_listener_orientation((screen.global_basis.orthonormalized().inverse() * camera.global_basis.orthonormalized()).orthonormalized())


func _update_menu_dim(delta: float) -> void:
	var target := MENU_DIM if panel.visible and Settings.dim_behind_menu else 1.0
	if is_equal_approx(menu_dim, target):
		return
	menu_dim = lerpf(menu_dim, target, 1.0 - exp(-delta * DIM_RATE))
	if absf(menu_dim - target) < 0.005:
		menu_dim = target
	screen.set_menu_dim(menu_dim)


func _on_opened(_path: String) -> void:
	if seek_bar != null:
		seek_bar.close_bar()
	var has_visual := player.is_image() or (player.has_picture() and not bool(player.stream_metadata.get("audio_only", false)))
	if Settings.face_on_open and grab_controller == null and has_visual:
		center_screen()
	if Settings.hide_menu_on_play and not player.paused:
		panel.close()
	_match_refresh_rate()


func _on_ended() -> void:
	if ui.opening_media():
		return
	if Settings.sleep_timer == Settings.SleepTimer.END_OF_VIDEO:
		Settings.apply("sleep_timer", Settings.SleepTimer.OFF)
		Log.info("sleep timer: stopped at end of video")
		return
	match Settings.end_action:
		Settings.EndAction.REPEAT:
			player.restart()
		Settings.EndAction.NEXT_FILE:
			if not ui.play_neighbor(1):
				panel.open()
		_:
			panel.open()


func _show_status(title: String) -> void:
	if panel.visible or player.current_path.is_empty() or osd.sticky or help_card.target_opacity > 0.0:
		return
	osd.show_status(title, camera)


func toggle_pause() -> void:
	if player._audio_only_playing():
		return
	_suppress_vr_seek()
	player.toggle_pause()


func seek_relative(seconds: float) -> void:
	_suppress_vr_seek()
	if _image_navigation_active():
		step_file(signi(int(seconds)))
		return
	if player._audio_only_playing():
		return
	player.seek_relative(seconds)


func _image_navigation_active() -> bool:
	return player.is_image()


func step_file(direction: int) -> void:
	if player.is_image():
		ui._play_media_neighbor(direction)
	elif not player._audio_only_playing():
		ui.play_neighbor(direction)


func step_volume(direction: int) -> void:
	if player.is_image():
		_key_action(Settings.StickAction.PICTURE_ZOOM, direction)
		return
	if player._audio_only_playing():
		return
	Settings.apply("volume", clampi(Settings.volume + VOLUME_STEP * direction, 0, 100))
	if Settings.muted and direction > 0:
		Settings.apply("muted", false)
	_show_status("Volume %d%%" % Settings.volume)


func _adjust(direction: int, slot: String) -> void:
	if slot == "trigger_action":
		_suppress_vr_seek()
	_step_action(_presented_action(Settings.get(slot)), direction)
	_refresh_help()


func adjust_visualizer_zoom(amount: float) -> void:
	Settings.apply("visualizer_zoom", Settings.visualizer_zoom * exp(amount))


func _step_action(action: Settings.StickAction, direction: int) -> void:
	if player._audio_only_playing() and action in FORMAT_ACTION_NAMES:
		Settings.cycle_visualizer_preset(direction)
		return
	if player._audio_only_playing() and action in [Settings.StickAction.VOLUME, Settings.StickAction.PLAYBACK_SPEED, Settings.StickAction.AUDIO_TRACK, Settings.StickAction.SUBTITLE_TRACK, Settings.StickAction.CHAPTER]:
		return
	if action == Settings.StickAction.PICTURE_ZOOM:
		if resonance_field != null and resonance_field.active:
			adjust_visualizer_zoom(direction * 0.05)
		else:
			Settings.apply("picture_zoom", Settings.picture_zoom * exp(direction * 0.05))
		return
	if action in NUMERIC_ACTIONS:
		var entry: Array = NUMERIC_ACTIONS[action]
		var property: String = entry[0]
		var value := clampf(float(Settings.get(property)) + entry[1] * direction, entry[2], entry[3])
		if typeof(Settings.get(property)) == TYPE_INT:
			Settings.apply(property, int(round(value)))
		else:
			Settings.apply(property, snappedf(value, absf(entry[1])))
	elif action == Settings.StickAction.SUBTITLE_TRACK:
		player.tracks.cycle_subtitle(direction)
	elif action == Settings.StickAction.AUDIO_TRACK:
		player.tracks.cycle_audio(direction)
	elif action == Settings.StickAction.CHAPTER:
		if not player.step_mark(direction):
			_show_status("No chapters or bookmarks")
	else:
		Settings.cycle_preset(action, direction)


func _presented_action(action: Settings.StickAction) -> Settings.StickAction:
	if action == Settings.StickAction.SCREEN_SIZE and ((resonance_field != null and resonance_field.active) or Settings.projection != Settings.ProjectionMode.FLAT):
		return Settings.StickAction.PICTURE_ZOOM
	return action


func action_name(action: Settings.StickAction) -> String:
	action = _presented_action(action)
	if action == Settings.StickAction.PICTURE_ZOOM and resonance_field != null and resonance_field.active:
		return "Visualizer zoom"
	if action in FORMAT_ACTION_NAMES:
		return "Music scene" if player._audio_only_playing() else FORMAT_ACTION_NAMES[action]
	if action in TRACK_ACTION_NAMES:
		return TRACK_ACTION_NAMES[action]
	if action == Settings.StickAction.CHAPTER:
		return MARK_ACTION_NAME
	var entry: Array = NUMERIC_ACTIONS[action]
	if Settings.projection != Settings.ProjectionMode.FLAT and action in [Settings.StickAction.SCREEN_SIZE, Settings.StickAction.SCREEN_CURVE]:
		return "%s (flat screen only)" % entry[4]
	return entry[4]


func action_value(action: Settings.StickAction) -> String:
	action = _presented_action(action)
	if action == Settings.StickAction.PICTURE_ZOOM and resonance_field != null and resonance_field.active:
		return "%.0f%%" % (Settings.visualizer_zoom * 100.0)
	if action in FORMAT_ACTION_NAMES:
		if player._audio_only_playing():
			return "%d / %d · %s" % [Settings.visualizer_preset + 1, Settings.VISUALIZER_PRESETS.size(), Settings.VISUALIZER_PRESETS[Settings.visualizer_preset]]
		var preset := Settings.matching_preset()
		var name: String = Settings.FORMAT_PRESETS[preset][0] if preset >= 0 else "Custom"
		return name + " + alpha" if Settings.alpha_mask != Settings.AlphaMask.NONE else name
	if action == Settings.StickAction.SUBTITLE_TRACK:
		return player.tracks.subtitle_label(player.tracks.subtitle_choice)
	if action == Settings.StickAction.AUDIO_TRACK:
		return player.tracks.audio_label(player.tracks.audio_choice)
	if action == Settings.StickAction.CHAPTER:
		return player.chapter_title(player.chapter_at(player.stream_position))
	if action == Settings.StickAction.SHARPNESS:
		return Settings.SHARPNESS_LEVELS[clampi(Settings.sharpness_level, 0, Settings.SHARPNESS_LEVELS.size() - 1)]
	var entry: Array = NUMERIC_ACTIONS[action]
	return entry[5] % (float(Settings.get(entry[0])) * entry[6])


func _refresh_help() -> void:
	if seek_bar != null:
		if _vr_seek_available():
			seek_bar.show_bar(camera)
			help_card.dismiss()
			osd.release()
			osd.dismiss()
			return
		seek_bar.close_bar()
	var gripping := grab_controller != null and not panel_grabbed
	if not gripping and trigger_help_controller == null:
		help_card.dismiss()
		osd.release()
		return
	var status: String = ui.playlist_label(player.current_path) if not player.current_path.is_empty() else ""
	var action: Settings.StickAction = Settings.chord_action if gripping and grab_controller.trigger_held else Settings.grip_action if gripping else Settings.trigger_action
	var format_entries := [] if player._audio_only_playing() and action in FORMAT_ACTION_NAMES else [[action_name(Settings.StickAction.FORMAT_ALL), "", action_value(Settings.StickAction.FORMAT_ALL)]]
	if gripping:
		if grab_controller.trigger_held:
			help_card.show_help("Grip + Trigger", [
				["Move", "Free drag", ""],
				["Twist", "Roll", ""],
				["A / X", "Level", ""],
				["◀ ▶", "Prev / next video", ""],
				["▲ ▼", action_name(Settings.chord_action), action_value(Settings.chord_action)],
			] + format_entries, camera, status)
		else:
			help_card.show_help("Grip", [
				["Move", "Turn, stays level" if Settings.projection != Settings.ProjectionMode.FLAT else "Move screen, level", ""],
				["A / X", "Favourite", "★ on" if Library.is_favorite(player.current_path) else "off"],
				["◀ ▶", "±5 min", ""],
				["▲ ▼", action_name(Settings.grip_action), action_value(Settings.grip_action)],
			] + format_entries + [
				["+ Trigger", "Free rotate, prev / next", ""],
			], camera, status)
	else:
		help_card.show_help("Trigger", [
			["◀ ▶", "±1 min", ""],
			["▲ ▼", action_name(Settings.trigger_action), action_value(Settings.trigger_action)],
		] + format_entries + [
			["+ Grip", "Free rotate, prev / next", ""],
		], camera, status)
	osd.release()
	osd.dismiss()


func _toggle_favorite() -> void:
	if player.current_path.is_empty():
		return
	var on := not Library.is_favorite(player.current_path)
	ui.set_favorite(player.current_path, on)
	Log.info("favourite %s: %s" % ["on" if on else "off", player.current_path])
	_refresh_help()
	_show_status("Added to favourites" if on else "Removed from favourites")


func _on_trigger_held(held: bool, controller: XRController3D) -> void:
	if held:
		seek_bar_suppressed = false
		if controller.pointing_at_panel() and grab_controller == null:
			return
		trigger_help_controller = controller
	elif trigger_help_controller == controller:
		if seek_bar != null and seek_bar.active and seek_bar.ready_to_seek():
			var hit := seek_bar.hit_from_ray(controller.global_position, controller.aim_direction())
			if hit.get("ok", false):
				player.seek_to(float(hit.fraction) * player.get_stream_length())
		trigger_help_controller = null
	_refresh_help()


func _vr_seek_available() -> bool:
	return trigger_help_controller != null and trigger_help_controller.trigger_held and not seek_bar_suppressed and not panel.visible and not picking and grab_controller == null and player.playback != null and not player.is_image() and not player._audio_only_playing() and player.get_stream_length() > 1.0


func _suppress_vr_seek() -> void:
	if seek_bar != null and seek_bar.active:
		seek_bar_suppressed = true
		seek_bar.close_bar()


func _update_vr_seek() -> void:
	if seek_bar == null:
		return
	if not seek_bar.active:
		if _vr_seek_available():
			_refresh_help()
		return
	if not _vr_seek_available():
		seek_bar.close_bar()
		return
	seek_bar.update_hover(trigger_help_controller.global_position, trigger_help_controller.aim_direction())


func _match_refresh_rate() -> void:
	var rate := DESKTOP_REFRESH_RATE
	if not desktop_mode and xr_interface != null and xr_interface.has_method("get_display_refresh_rate"):
		rate = xr_interface.get_display_refresh_rate()
		var target := _preferred_refresh_rate(player.playback_fps())
		if target > 0.0 and not is_equal_approx(target, rate):
			xr_interface.set_display_refresh_rate(target)
			rate = target
			Log.info("display refresh %.0f Hz for %.2f fps video" % [target, player.playback_fps()])
	if player.playback != null and rate > 0.0:
		player.playback.set_display_rate(rate)


func _preferred_refresh_rate(video_fps: float) -> float:
	if not Settings.match_refresh_rate or video_fps < 1.0 or not xr_interface.has_method("get_available_display_refresh_rates"):
		return 0.0
	var current: float = xr_interface.get_display_refresh_rate()
	var rates: Array = Array(xr_interface.get_available_display_refresh_rates())
	var best := 0.0
	for rate in rates:
		var ratio: float = float(rate) / video_fps
		if absf(ratio - roundf(ratio)) > REFRESH_MATCH_TOLERANCE * ratio or ratio < 0.98:
			continue
		if best <= 0.0 or float(rate) < best:
			best = float(rate)
	if best <= 0.0:
		Log.info("no refresh rate in %s is a multiple of %.2f fps, keeping %.0f Hz" % [str(rates), video_fps, current])
	return best


func _apply_settings() -> void:
	panel.scale = Vector3.ONE * (1.0 if desktop_mode else Settings.ui_size)
	if Settings.lock_horizon and not is_zero_approx(Settings.angle_roll) and grab_controller == null:
		Settings.angle_roll = 0.0
		screen.apply_angles()
	panel.set_opacity(0.8 if Settings.menu_translucent else 1.0)
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var env := environment.environment
	if resonance_field != null and resonance_field.active:
		resonance_field.apply_render_quality()
		_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		return
	match Settings.background:
		Settings.Background.CHROMA_KEY:
			_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
			env.background_mode = Environment.BG_COLOR
			env.background_color = Settings.chroma_key_color
		Settings.Background.PASSTHROUGH:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0, 0, 0, 0)
			_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
		Settings.Background.BLACK, Settings.Background.CINEMA:
			_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color.BLACK


func _set_blend_mode(mode: XRInterface.EnvironmentBlendMode) -> void:
	var requested_passthrough := mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	if xr_interface == null or desktop_mode:
		get_viewport().transparent_bg = requested_passthrough
		return
	if last_blend_request == int(mode):
		if blend_fallback:
			environment.environment.background_color = Color.BLACK
		return
	last_blend_request = int(mode)
	var effective_mode := mode
	if requested_passthrough and xr_interface.has_method("get_supported_environment_blend_modes"):
		var supported: Array = xr_interface.get_supported_environment_blend_modes()
		if mode not in supported:
			effective_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	var accepted := xr_interface.set_environment_blend_mode(effective_mode)
	if not accepted and requested_passthrough and effective_mode != XRInterface.XR_ENV_BLEND_MODE_OPAQUE:
		effective_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		accepted = xr_interface.set_environment_blend_mode(effective_mode)
	var passthrough := accepted and effective_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	blend_fallback = requested_passthrough and not passthrough
	get_viewport().transparent_bg = passthrough
	if blend_fallback:
		environment.environment.background_color = Color.BLACK
		Log.warn("runtime rejected alpha blend; using opaque black background")
	if passthrough:
		if xr_interface.has_method("is_passthrough_supported") and xr_interface.is_passthrough_supported():
			if xr_interface.start_passthrough():
				Log.info("XR_FB passthrough started")
			else:
				passthrough = false
				blend_fallback = true
				get_viewport().transparent_bg = false
				environment.environment.background_color = Color.BLACK
				xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
				Log.warn("XR_FB passthrough failed to start; using opaque black background")
		if passthrough:
			Log.info("OpenXR alpha-blend passthrough on")
	elif xr_interface.has_method("stop_passthrough"):
		xr_interface.stop_passthrough()
	if not accepted:
		Log.warn("blend mode %d rejected by runtime" % effective_mode)


func _cycle_visualizer_preset() -> void:
	if not player._audio_only_playing() or panel.visible:
		return
	_key_action(Settings.StickAction.FORMAT_ALL, 1)


func _on_recenter_progress(fraction: float) -> void:
	if fraction < 0.0:
		osd.end_hold()
		return
	osd.show_hold("Hold to recenter", fraction, camera)


func recenter() -> void:
	if not _tracking_usable():
		_show_status("Tracking unavailable. Recenter when tracking returns")
		return
	_cancel_picture_motion()
	osd.end_hold()
	_align_anchor()
	subtitle_view.recenter()
	panel.place_in_front(camera, MENU_DISTANCE, desktop_mode or reclined)


func center_screen() -> void:
	if not _tracking_usable():
		_show_status("Tracking unavailable. Recenter when tracking returns")
		return
	_cancel_picture_motion()
	Settings.angle_yaw = 0.0
	Settings.angle_pitch = 0.0
	screen.apply_angles()
	_align_anchor()
	subtitle_view.recenter()
	Settings.commit()


func _tracking_usable() -> bool:
	if desktop_mode or xr_interface == null:
		return true
	return xr_interface.get_tracking_status() not in [XRInterface.XR_NOT_TRACKING, XRInterface.XR_INSUFFICIENT_FEATURES, XRInterface.XR_EXCESSIVE_MOTION]


func _cancel_picture_motion() -> void:
	grab_controller = null
	drag_active = false
	roll_active = false
	grab_free = false
	video_gliding = false
	video_glide_initializing = false
	video_glide_away_time = 0.0
	posture_blending = false


func _bake_screen_pose() -> void:
	var pose := screen.global_transform
	Settings.angle_yaw = 0.0
	Settings.angle_pitch = 0.0
	Settings.angle_roll = 0.0
	screen.set_view_yaw(0.0)
	screen.apply_angles()
	screen_anchor.global_transform = pose * screen.transform.affine_inverse()
	FloatPanel.frame = screen_anchor.global_basis.orthonormalized()


func reset_picture_position() -> void:
	if not _tracking_usable():
		_show_status("Tracking unavailable. Reset when tracking returns")
		return
	_cancel_picture_motion()
	Settings.angle_yaw = 0.0
	Settings.angle_pitch = 0.0
	Settings.angle_roll = 0.0
	Settings.photo_pan_x = 0.0
	Settings.photo_pan_y = 0.0
	screen.set_view_yaw(0.0)
	screen.apply_angles()
	_align_anchor()
	Settings.commit_photo_pan()
	subtitle_view.recenter()
	_show_status("Picture position reset")


func _align_anchor() -> void:
	if desktop_mode:
		camera.basis = Basis.IDENTITY
	video_glide_away_time = 0.0
	video_gliding = false
	video_glide_initializing = false
	posture_blending = false
	var head := camera.global_basis.orthonormalized()
	var gaze_pitch := rad_to_deg(asin(clampf(-head.z.y, -1.0, 1.0)))
	var head_tilt := rad_to_deg(asin(clampf(head.x.y, -1.0, 1.0)))
	reclined = apply_recline_pose(head)
	screen_anchor.global_position = camera.global_position
	if reclined:
		screen_anchor.global_basis = head
	else:
		screen_anchor.global_basis = _level_head(head)
	FloatPanel.frame = screen_anchor.global_basis
	screen.set_view_yaw(0.0)
	Log.info("recenter %s (gaze pitch %.0f°, head tilt %.0f°)" % ["reclined, head frame" if reclined else "upright, level frame", gaze_pitch, head_tilt])
	if resonance_field != null and resonance_field.active:
		resonance_field.place()
	if music_visualizer != null and music_visualizer.visible:
		music_visualizer.place(camera)
	if music_panel != null and music_panel.visible:
		music_panel.place(camera)
	screen.zoom_snap = true


func _update_posture_frame(delta: float) -> void:
	if desktop_mode or not _tracking_usable() or video_gliding or not Settings.follow_posture or Settings.projection in [Settings.ProjectionMode.EQUIRECT_360, Settings.ProjectionMode.EAC, Settings.ProjectionMode.CUBEMAP]:
		return
	var head := camera.global_basis.orthonormalized()
	var should_recline := apply_recline_pose(head)
	if should_recline != reclined:
		reclined = should_recline
		posture_blending = true
		Log.info("posture %s (gaze pitch %.0f°, head tilt %.0f°)" % ["reclined" if reclined else "upright", rad_to_deg(asin(clampf(-head.z.y, -1.0, 1.0))), rad_to_deg(asin(clampf(head.x.y, -1.0, 1.0)))])
	if reclined:
		var follow_weight := 1.0 - exp(-delta * 12.0)
		screen_anchor.global_basis = screen_anchor.global_basis.slerp(head, follow_weight).orthonormalized()
		FloatPanel.frame = screen_anchor.global_basis
		return
	if not posture_blending:
		return
	var target := _level_head(head)
	screen_anchor.global_basis = screen_anchor.global_basis.slerp(target, 1.0 - exp(-delta * 5.0)).orthonormalized()
	FloatPanel.frame = screen_anchor.global_basis
	if rad_to_deg(screen_anchor.global_basis.get_rotation_quaternion().angle_to(target.get_rotation_quaternion())) < 1.0:
		screen_anchor.global_basis = target
		FloatPanel.frame = target
		posture_blending = false


func _screen_follow_frame() -> Basis:
	var head := camera.global_basis.orthonormalized()
	return head if reclined else _level_head(head)


func toggle_menu() -> void:
	if picking:
		_stop_pick()
		return
	if panel.is_open():
		panel.close()
		return
	var was_visible: bool = panel.visible
	panel.open()
	if not was_visible:
		panel.place_in_front(camera, MENU_DISTANCE, desktop_mode or reclined)
		ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _start_pick() -> void:
	if player.get_video_texture() == null:
		Log.warn("pick: no video")
		return
	picking = true
	panel.close()
	for controller in [$Origin/Left, $Origin/Right]:
		controller.picking = true
	Log.info("pick from video: point at picture, trigger. B cancels")


func _stop_pick() -> void:
	picking = false
	pick_busy = false
	for controller in [$Origin/Left, $Origin/Right]:
		controller.picking = false
	panel.open()
	panel.place_in_front(camera, MENU_DISTANCE, desktop_mode or reclined)
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _on_pick(controller: XRController3D) -> void:
	if not picking or pick_busy:
		return
	var hit: Dictionary = screen.hit_from_ray(controller.global_position, controller.aim_direction())
	if not hit.get("ok", false):
		Log.warn("pick: no video hit")
		return
	pick_busy = true
	var color: Color = await screen.sample_color(hit.uv)
	pick_busy = false
	if not picking:
		return
	Log.info("picked video color %s" % color)
	ui.apply_video_color(color)
	_stop_pick()


func _on_grab_started(controller: XRController3D) -> void:
	if grab_controller != null:
		return
	if music_panel != null and controller.hit_panel == music_panel and music_panel.interactive():
		music_panel.begin_grab(controller)
		controller.pulse(0.15)
		return
	grab_controller = controller
	panel_grabbed = panel.visible and controller.pointing_at_panel()
	if panel_grabbed:
		panel_grab_offset = controller.aim_transform().affine_inverse() * panel.global_transform
		return
	_begin_drag(controller)
	roll_active = false
	drag_active = false
	roll_filter.reset()
	_refresh_help()


func _begin_drag(controller: XRController3D) -> void:
	grab_point = _grab_point(controller)
	grab_basis = _controller_basis(controller)
	grab_angles = Vector3(Settings.angle_yaw, Settings.angle_pitch, Settings.angle_roll)
	grab_pan = Vector2(Settings.photo_pan_x, Settings.photo_pan_y)
	grab_view = Basis(Vector3.UP, screen.view_yaw)
	grab_picture = grab_view * Basis.from_euler(Vector3(deg_to_rad(grab_angles.y), deg_to_rad(grab_angles.x), deg_to_rad(grab_angles.z)))
	grab_free = controller.trigger_held and not Settings.lock_horizon
	grab_content = grab_picture.inverse() * grab_point
	level_yaw = grab_angles.x
	level_roll = grab_angles.z
	level_heading = _heading(grab_view.inverse() * grab_point, 0.0)
	roll_filter.reset()


func _on_grab_ended(controller: XRController3D) -> void:
	if music_panel != null and music_panel.grab_controller == controller:
		music_panel.end_grab()
		return
	if grab_controller != controller:
		return
	grab_controller = null
	_refresh_help()
	if panel_grabbed:
		panel_grabbed = false
		return
	if _flat_pan_active():
		controller.pulse(0.15)
		Settings.commit_photo_pan()
		return
	if absf(Settings.angle_roll) < RELEASE_ROLL_SNAP:
		Settings.angle_roll = 0.0
	if absf(Settings.angle_pitch) < RELEASE_PITCH_SNAP:
		Settings.angle_pitch = 0.0
	_apply_grab_angles()
	controller.pulse(0.15)
	Settings.commit()


func _aim_direction(controller: XRController3D) -> Vector3:
	return screen_anchor.global_basis.inverse() * controller.aim_direction()


func _grab_point(controller: XRController3D) -> Vector3:
	var origin := screen_anchor.to_local(controller.global_position)
	var direction := _aim_direction(controller).normalized()
	var radius := Settings.SCREEN_DISTANCE if Settings.projection == Settings.ProjectionMode.FLAT else SPHERE_GRAB_RADIUS
	var b := origin.dot(direction)
	var c := origin.length_squared() - radius * radius
	var t := -b + sqrt(maxf(b * b - c, 0.0))
	return (origin + direction * t).normalized()


func _dragged_picture(point: Vector3, speed: float) -> Basis:
	var axis := grab_point.cross(point)
	if axis.length_squared() < 1e-10:
		return grab_picture
	return Basis(axis.normalized(), grab_point.angle_to(point) * speed) * grab_picture


func _turn_angles(point: Vector3, speed: float) -> Vector3:
	var heading := _heading(grab_view.inverse() * point, level_heading)
	level_yaw += rad_to_deg(wrapf(heading - level_heading, -PI, PI)) * speed
	level_heading = heading
	return Vector3(level_yaw, grab_angles.y, level_roll)


func _heading(direction: Vector3, fallback: float) -> float:
	if Vector2(direction.x, direction.z).length() < TURN_MIN_HORIZONTAL:
		return fallback
	return atan2(-direction.x, -direction.z)


func _level_angles(point: Vector3, speed: float) -> Vector3:
	var target := point
	var axis := grab_point.cross(point)
	if axis.length_squared() > 1e-10:
		target = Basis(axis.normalized(), grab_point.angle_to(point) * speed) * grab_point
	var view_target := grab_view.inverse() * target
	var content := Basis(Vector3.BACK, deg_to_rad(level_roll)) * grab_content
	var horizontal := Vector2(view_target.x, view_target.z).length()
	var phi := atan2(view_target.z, view_target.x)
	var spread := acos(clampf(content.x / maxf(horizontal, 1e-6), -1.0, 1.0))
	var previous := deg_to_rad(level_yaw)
	var yaw := previous
	var best := INF
	for candidate in [-phi + spread, -phi - spread]:
		var unwrapped := previous + wrapf(candidate - previous, -PI, PI)
		if absf(unwrapped - previous) < best:
			best = absf(unwrapped - previous)
			yaw = unwrapped
	var aligned := Basis(Vector3.UP, -yaw) * view_target
	var pitch := atan2(content.y * aligned.z - content.z * aligned.y, content.y * aligned.y + content.z * aligned.z)
	pitch = clampf(pitch, -deg_to_rad(LEVEL_PAN_PITCH_LIMIT), deg_to_rad(LEVEL_PAN_PITCH_LIMIT))
	level_yaw = rad_to_deg(yaw)
	return Vector3(level_yaw, rad_to_deg(pitch), level_roll)


func _picture_angles(picture: Basis) -> Vector3:
	var euler := (grab_view.inverse() * picture).orthonormalized().get_euler()
	return Vector3(rad_to_deg(euler.y), rad_to_deg(euler.x), rad_to_deg(euler.z))


func _controller_basis(controller: XRController3D) -> Basis:
	return (screen_anchor.global_basis.inverse() * controller.global_basis).orthonormalized()


func _controller_twist(controller: XRController3D) -> float:
	var current := _controller_basis(controller)
	var aim := -current.z
	var start_up := Quaternion(-grab_basis.z, aim) * grab_basis.y
	return -rad_to_deg(start_up.signed_angle_to(current.y, aim))


func _update_grab(delta: float) -> void:
	if not _tracking_usable():
		return
	if grab_controller == null:
		return
	if panel_grabbed:
		panel.global_transform = grab_controller.aim_transform() * panel_grab_offset
		return
	if not player.has_picture():
		return
	var speed: float = Settings.drag_speed
	var free_rotate: bool = grab_controller.trigger_held and not Settings.lock_horizon
	var point := _grab_point(grab_controller)
	if _flat_pan_active():
		var scale := speed / maxf(deg_to_rad(Settings.screen_size), 0.1)
		var target := grab_pan + Vector2(-(point.x - grab_point.x), point.y - grab_point.y) * scale
		Settings.pan_photo(target - Vector2(Settings.photo_pan_x, Settings.photo_pan_y))
		return
	if not drag_active and rad_to_deg(grab_point.angle_to(point)) > DRAG_DEADZONE:
		drag_active = true
		_begin_drag(grab_controller)
		point = grab_point
	if free_rotate != grab_free:
		_begin_drag(grab_controller)
		point = grab_point
		roll_active = false
	var roll_delta := wrapf(_controller_twist(grab_controller), -180.0, 180.0)
	if free_rotate and not roll_active and absf(roll_delta) > ROLL_DEADZONE:
		roll_active = true
	var filtered := point if drag_active else grab_point
	var angles := grab_angles
	if free_rotate:
		var picture := _dragged_picture(filtered, speed) if drag_active else grab_picture
		if roll_active:
			picture = Basis(-filtered, deg_to_rad(roll_filter.filter(roll_delta, delta) * speed)) * picture
		angles = _picture_angles(picture)
	else:
		if Settings.lock_horizon or (absf(level_roll) < LEVEL_SNAP and absf(Settings.angle_pitch) < LEVEL_PITCH_MAX):
			level_roll *= exp(-delta * LEVEL_RATE)
		if not drag_active:
			angles = Vector3(grab_angles.x, grab_angles.y, level_roll)
		elif Settings.projection == Settings.ProjectionMode.FLAT:
			angles = _level_angles(filtered, speed)
		else:
			angles = _turn_angles(filtered, speed)
	Settings.angle_yaw = wrapf(angles.x, -180.0, 180.0)
	Settings.angle_pitch = angles.y
	Settings.angle_roll = wrapf(angles.z, -180.0, 180.0)
	_apply_grab_angles()


func _apply_grab_angles() -> void:
	var previous := screen.global_basis.orthonormalized()
	screen.apply_angles()
	if resonance_field != null and resonance_field.active and music_grab_moves_scene():
		resonance_field.rotate_scene(screen.global_basis.orthonormalized() * previous.inverse())


func _level_view(controller: XRController3D) -> void:
	reset_to_level()
	controller.pulse(0.3)


func reset_to_level() -> void:
	if not _tracking_usable():
		_show_status("Tracking unavailable. Level when tracking returns")
		return
	_level_picture(0.0)
	_show_status("Picture leveled")


func _update_spirit_level() -> void:
	if level_gauge == null:
		return
	if not Settings.show_level or grab_controller == null or panel_grabbed or _flat_pan_active() or picking or not SpiritLevel.applicable(player, Settings.projection == Settings.ProjectionMode.FLAT):
		level_gauge.dismiss()
		return
	level_gauge.present(camera)
	if help_card.visible and help_card.target_opacity > 0.0:
		level_gauge.place_above(help_card)


func _level_picture(turn_degrees: float) -> void:
	var anchor := screen_anchor.global_basis.orthonormalized()
	var view := Basis(Vector3.UP, screen.view_yaw)
	var world := anchor * view * Basis.from_euler(Vector3(deg_to_rad(Settings.angle_pitch), deg_to_rad(Settings.angle_yaw), deg_to_rad(Settings.angle_roll)))
	var level := Basis(Vector3.UP, deg_to_rad(turn_degrees)) * Basis.looking_at(SpiritLevel.heading(world), Vector3.UP)
	var euler := (view.inverse() * anchor.inverse() * level).orthonormalized().get_euler()
	Settings.angle_yaw = wrapf(rad_to_deg(euler.y), -180.0, 180.0)
	Settings.angle_pitch = rad_to_deg(euler.x)
	Settings.angle_roll = rad_to_deg(euler.z)
	screen.apply_angles()
	if Settings.lock_horizon and not is_zero_approx(Settings.angle_roll):
		_bake_screen_pose()
	if grab_controller != null and not panel_grabbed:
		_begin_drag(grab_controller)
		roll_active = false
	Settings.commit()


func _update_look_gain() -> void:
	if grab_controller != null and not panel_grabbed:
		return
	if Settings.projection == Settings.ProjectionMode.FLAT or is_equal_approx(Settings.look_gain, 1.0):
		screen.set_view_yaw(0.0)
		return
	var gaze := screen_anchor.global_basis.inverse() * (-camera.global_basis.z)
	var head_yaw := atan2(-gaze.x, -gaze.z)
	var fade := (1.0 - smoothstep(deg_to_rad(GAIN_FADE_START), PI, absf(head_yaw))) * smoothstep(GAIN_POLE_FADE.x, GAIN_POLE_FADE.y, Vector2(gaze.x, gaze.z).length())
	screen.set_view_yaw((1.0 - Settings.look_gain) * head_yaw * fade)


func _unhandled_input(event: InputEvent) -> void:
	if mirror_mode != null and mirror_mode.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if desktop_view != null and desktop_view.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if (desktop_view != null and desktop_view.handle_key(event)) or _handle_key(event):
			get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> bool:
	if not event.pressed:
		if event.keycode == held_step_key:
			held_step_key = KEY_NONE
		return ui.handle_key(event)
	if panel.is_open() and ui.handle_key(event):
		return true
	var ctrl := event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_ESCAPE:
			if picking:
				_stop_pick()
			elif panel.is_open():
				panel.close()
			else:
				_open_menu()
				ui.show_library()
		KEY_TAB:
			if not panel.is_open():
				_open_menu()
			if ctrl:
				ui.step_page(-1 if event.shift_pressed else 1)
			else:
				ui.handle_key(event)
		KEY_F1, KEY_SLASH:
			_open_menu()
			ui.show_page(ui.pages.get_node("Controls"))
		KEY_F when ctrl:
			_open_menu()
			ui.handle_key(event)
		KEY_SPACE, KEY_K:
			if not event.echo:
				toggle_pause()
		KEY_LEFT, KEY_RIGHT:
			var direction := 1 if event.keycode == KEY_RIGHT else -1
			if ctrl:
				if not event.echo:
					if _flat_pan_active():
						Settings.pan_photo(Vector2(-0.1 * direction, 0.0))
						Settings.commit_photo_pan()
					else:
						_level_picture(KEY_TURN_DEGREES * direction)
			elif not event.echo:
				_start_held_step(event.keycode, direction, event.shift_pressed)
		KEY_UP when ctrl:
			if not event.echo:
				_toggle_favorite()
		KEY_DOWN when ctrl:
			if not event.echo:
				if _flat_pan_active():
					Settings.reset(PackedStringArray(["photo_pan_x", "photo_pan_y"]))
					_show_status("Pan reset")
				else:
					_level_picture(0.0)
					_show_status("Level")
		KEY_UP:
			if player.is_image():
				_key_action(Settings.StickAction.PICTURE_ZOOM, 1)
			else:
				step_volume(1)
		KEY_DOWN:
			if player.is_image():
				_key_action(Settings.StickAction.PICTURE_ZOOM, -1)
			else:
				step_volume(-1)
		KEY_HOME:
			if not player.is_image() and not player._audio_only_playing():
				player.seek_to(0.0)
		KEY_END:
			if not player.is_image() and not player._audio_only_playing():
				player.seek_to(maxf(player.get_stream_length() - DESKTOP_SEEK_STEP, 0.0))
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			if not player.is_image() and not player._audio_only_playing() and not player.current_path.is_empty():
				player.seek_to(player.get_stream_length() * (event.keycode - KEY_0) / 10.0)
		KEY_N, KEY_PAGEDOWN:
			if not event.echo:
				step_file(1)
		KEY_P, KEY_PAGEUP:
			if not event.echo:
				step_file(-1)
		KEY_S:
			if not player.is_music_mode():
				Settings.apply("shuffle", not Settings.shuffle)
				_show_status("Shuffle on" if Settings.shuffle else "Shuffle off")
		KEY_M:
			if not player._audio_only_playing():
				Settings.apply("muted", not Settings.muted)
				_show_status("Muted" if Settings.muted else "Unmuted")
		KEY_R:
			if not event.echo:
				recenter()
		KEY_F:
			if event.echo:
				return true
			_key_action(Settings.StickAction.FORMAT_ALL, -1 if event.shift_pressed else 1)
		KEY_V:
			_key_action(Settings.StickAction.SUBTITLE_TRACK, -1 if event.shift_pressed else 1)
		KEY_A:
			_key_action(Settings.StickAction.AUDIO_TRACK, -1 if event.shift_pressed else 1)
		KEY_C:
			if not player._audio_only_playing() and not player.step_mark(-1 if event.shift_pressed else 1):
				_show_status("No chapters or bookmarks")
		KEY_B:
			if not event.echo and not player.is_image() and not player._audio_only_playing() and not player.current_path.is_empty():
				player.add_bookmark()
				_show_status("Bookmark added")
		KEY_L:
			if event.echo or player.is_image() or player._audio_only_playing():
				return true
			if event.shift_pressed:
				player.clear_loop()
				_show_status("Loop cleared")
			else:
				player.set_loop_point()
				_show_status("Loop A–B set" if player.loop_b >= 0.0 else "Loop start set")
		KEY_BACKSPACE:
			if not event.echo:
				if not player._audio_only_playing():
					Settings.apply("playback_speed", 1.0)
				if resonance_field != null and resonance_field.active:
					Settings.apply("visualizer_zoom", 1.0)
				else:
					Settings.apply("picture_zoom", 1.0)
				_show_status("Speed and zoom reset")
		_:
			if event.keycode not in KEY_NUMERIC_ACTIONS:
				return false
			var entry: Array = KEY_NUMERIC_ACTIONS[event.keycode]
			_key_action(entry[0], entry[1])
	return true


func _open_menu() -> void:
	if not panel.is_open():
		toggle_menu()


func _key_action(action: Settings.StickAction, direction: int) -> void:
	_step_action(action, direction)
	_show_status("%s  %s" % [action_name(action), action_value(action)])


func _start_held_step(keycode: Key, direction: int, fast: bool) -> void:
	held_step_key = keycode
	held_step_direction = direction
	held_step_timer = KEY_REPEAT_DELAY
	_held_step(fast)


func _held_step(fast: bool) -> void:
	if _image_navigation_active():
		step_file(held_step_direction)
	else:
		seek_relative((DESKTOP_SEEK_STEP_LARGE if fast else DESKTOP_SEEK_STEP) * held_step_direction)


func _update_held_step(delta: float) -> void:
	if held_step_key == KEY_NONE:
		return
	if not Input.is_key_pressed(held_step_key) or Input.is_key_pressed(KEY_CTRL):
		held_step_key = KEY_NONE
		return
	var fast := Input.is_key_pressed(KEY_SHIFT)
	held_step_timer -= delta * (KEY_FAST_FACTOR if fast else 1.0)
	if held_step_timer > 0.0:
		return
	held_step_timer += IMAGE_STEP_INTERVAL if _image_navigation_active() else SEEK_REPEAT_INTERVAL
	_held_step(fast)


func _flat_pan_active() -> bool:
	return Settings.projection == Settings.ProjectionMode.FLAT and (player.is_image() or Settings.flat_video_pan)
