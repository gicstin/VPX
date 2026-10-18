extends Node

signal changed
signal zoom_changed(snap: bool)
signal screen_size_changed

enum ProjectionMode { FLAT, EQUIRECT_360, EQUIRECT_180, FISHEYE, EAC, CUBEMAP }
enum Stereo { MONO, SIDE_BY_SIDE, OVER_UNDER }
enum AlphaMask { NONE, PACKED_CORNERS, STACKED_BELOW }
enum Background { CHROMA_KEY, PASSTHROUGH, BLACK, CINEMA }
enum DecodeMode { AUTO, HARDWARE, SOFTWARE }
enum EndAction { STOP, REPEAT, NEXT_FILE }
enum PlaybackPriority { SMOOTH, SHARP }
enum PanoramaSource { SINGLE, CUBE }
enum StickAction { SCREEN_SIZE, BRIGHTNESS, GAMMA, SATURATION, SHARPNESS, VOLUME, FORMAT_2D, FORMAT_3D, FORMAT_ALL, SUBTITLE_TRACK, AUDIO_TRACK, SCREEN_CURVE, STEREO_DEPTH, PICTURE_ZOOM, PLAYBACK_SPEED, CHAPTER }
enum LibraryView { GRID, LIST }
enum SubtitleAuto { OFF, FOREIGN, ALWAYS }
enum LibrarySort { NAME, DATE, SIZE }
enum LibrarySource { FOLDER, RECENT, FAVORITES, PLACES, NETWORK }
enum SleepTimer { OFF, MIN_15, MIN_30, MIN_45, MIN_60, MIN_90, END_OF_VIDEO }
enum LibraryFilter { ALL, FLAT_2D, FLAT_3D, VR_180, VR_360, PHOTOS }
enum AudioFilter { OFF, LEVEL, NIGHT }
enum Deband { OFF, LOW, MEDIUM, HIGH }

const CONFIG_PATH := "user://settings.cfg"
const VISUALIZER_PRESET_MAX := 63
const VISUALIZER_PRESETS := [
	"Resonance Field", "Resonant Architecture", "Particle Cosmos",
	"Bass Strings", "Wave Architecture", "Aurora Cosmos", "Stereo Speakers",
	"Stereo Waterfall", "Spectral River", "Delay Curtains", "Spectral Tunnel",
	"Spectral Canyon", "Ribbon Canopy", "Braided Ribbons", "Harmonic Arches",
	"Stereo Wings", "Spectral Chamber", "Warp Tunnel", "Laser Show",
	"Sub Pulse", "Nebula Storm", "Kaleidosphere", "Source Stage", "Vectorscope",
	"Lissajous Tunnel", "Source Constellation", "Stereo Terrain", "Source Fireworks",
	"Source Planets", "Pan Aurora", "Ripple Pool", "Light Harp", "Sound Radar",
	"Pan Analyzer Ring", "Source Comets", "Stereo Bloom", "Width Tunnel", "Surround Choir",
	"Stereo Point Cloud", "Binary Stars", "Tesla Arcs", "Pendulum Wave", "Phosphor Dome",
	"Polar Scope", "Scope Halo", "Scope Kaleidoscope", "Stereo Helix", "Terrain Canyon",
	"Pan Ridges", "Terrain Tunnel", "Neon Mirror", "Crystal City",
	"Spectrum Observatory", "Phase Cathedral", "Stereo Ribbonfall",
	"Pan Meridian", "Transient Loom", "Stereo Difference",
	"Mid Side Atrium", "Correlation Causeway", "Stereo Spectrogram", "Pan Trails",
	"Dual Waveform", "Spectral Balance"
]
const VISUALIZER_STUDIO_START := 52
const VISUALIZER_STUDIO_GUIDES := [
	"30 Hz → 18 kHz · Cyan L / Pink R · Height −60 → 0 dB · 10 dB rings",
	"Side ↔ / Mid ↕ · Vertical = mono · Horizontal = phase opposition · Auto gain",
	"Centre → edges: 30 Hz → 18 kHz · Cyan L / Pink R · 3.8 s history · Height −60 → 0 dB",
	"Left ↔ Right · Bottom → top: 30 Hz → 18 kHz · Depth = 2.5 s pan history",
	"Left → right: 30 Hz → 18 kHz · Depth = 3.8 s history · Gold = rising spectral energy",
	"30 Hz → 18 kHz · Cyan below = L louder / Pink above = R louder · Centre = equal magnitude",
	"Cyan lower rings = Mid (L+R) / Gold upper rings = Side (R−L) · Waveform displaces rings · Depth = 0.8 s history · Shared auto gain",
	"Left red = −1 phase opposition / Centre amber = 0 / Right green = +1 mono compatibility · Depth = 3.8 s correlation history",
	"Left → right: 30 Hz → 18 kHz · Upper panel L / Lower panel R · Top of each panel = now, bottom = 3.8 s ago · Dark → bright: −60 → 0 dB",
	"Left ↔ Right = frequency pan · Low → high elevation: 30 Hz → 18 kHz · Near → far = 3.8 s history · Colour = frequency",
	"Left → right: 256 captured samples · Cyan upper = L / Pink lower = R · Shared auto gain · Centre lines = zero · Outer rails = ±1 after gain · Depth = 0.8 s persistence",
	"Left → right: 30 Hz → 18 kHz · Height = R minus L, −24 → +24 dB · Cyan below = L louder / Pink above = R louder · Centre = equal magnitude · 6 dB grid · Depth = 3.8 s history"
]
const SCREEN_PLACEMENT_VERSION := 1
const SCREEN_DISTANCE := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 8.0
const ZOOM_RATE := 0.8
const SCREEN_SIZE_RATE := 30.0
const FORMAT_PRESETS := [
	["2D flat", ProjectionMode.FLAT, Stereo.MONO],
	["3D SBS", ProjectionMode.FLAT, Stereo.SIDE_BY_SIDE],
	["3D OU", ProjectionMode.FLAT, Stereo.OVER_UNDER],
	["180 SBS", ProjectionMode.EQUIRECT_180, Stereo.SIDE_BY_SIDE],
	["180 OU", ProjectionMode.EQUIRECT_180, Stereo.OVER_UNDER],
	["180 mono", ProjectionMode.EQUIRECT_180, Stereo.MONO],
	["360 mono", ProjectionMode.EQUIRECT_360, Stereo.MONO],
	["360 SBS", ProjectionMode.EQUIRECT_360, Stereo.SIDE_BY_SIDE],
	["360 OU", ProjectionMode.EQUIRECT_360, Stereo.OVER_UNDER],
	["Fisheye SBS", ProjectionMode.FISHEYE, Stereo.SIDE_BY_SIDE],
]
const FORMAT_PROPERTIES := ["projection", "stereo", "swap_eyes", "fisheye_fov", "alpha_mask", "stereo_depth", "stereo_vertical", "picture_zoom", "single_eye", "photo_pan_x", "photo_pan_y", "equirect_fov", "eye_roll", "lens_k1", "lens_k2", "crop_left", "crop_top", "crop_right", "crop_bottom"]
const VIEW_ADJUST := {"stereo_depth": 0.0, "stereo_vertical": 0.0, "picture_zoom": 1.0, "single_eye": false, "photo_pan_x": 0.0, "photo_pan_y": 0.0, "equirect_fov": 180.0, "eye_roll": 0.0, "lens_k1": 0.0, "lens_k2": 0.0, "crop_left": 0.0, "crop_top": 0.0, "crop_right": 0.0, "crop_bottom": 0.0}
const CALIBRATION := ["equirect_fov", "eye_roll", "lens_k1", "lens_k2", "crop_left", "crop_top", "crop_right", "crop_bottom"]
const DEBAND_PARAMS := [Vector2(0.0, 0.0), Vector2(1.6 / 255.0, 10.0), Vector2(2.6 / 255.0, 16.0), Vector2(4.0 / 255.0, 24.0)]
const REMOTE_PORT := 23554
const SLEEP_MINUTES := [0, 15, 30, 45, 60, 90, 0]
const SHARPNESS_LEVELS := ["Off", "Low", "Medium", "High", "Extra", "Max"]
const SHARPNESS_GAINS := [0.0, 0.5, 1.0, 1.6, 2.4, 3.2]
const RESUME_MIN_SECONDS := 5.0
const RESUME_END_MARGIN := 10.0
const SAVE_DELAY := 0.5
const SUBTITLE_COLORS := [Color(1.0, 1.0, 1.0), Color(1.0, 0.9, 0.3), Color(0.8, 0.8, 0.8)]
const Languages := preload("res://scripts/languages.gd")

var projection := ProjectionMode.FLAT
var stereo := Stereo.MONO
var swap_eyes := false
var fisheye_fov := 180.0
var alpha_mask := AlphaMask.NONE
var stereo_depth := 0.0
var stereo_vertical := 0.0
var picture_zoom := 1.0
var single_eye := false
var flat_image_repeat := 0
var flat_video_pan := false
var photo_pan_x := 0.0
var photo_pan_y := 0.0
var equirect_fov := 180.0
var eye_roll := 0.0
var lens_k1 := 0.0
var lens_k2 := 0.0
var crop_left := 0.0
var crop_top := 0.0
var crop_right := 0.0
var crop_bottom := 0.0
var auto_crop := true
var deband := Deband.OFF
var dither := true
var compositor_layer := false
var music_visualizer := true
var music_visualizer_mode := 0
var immersive_music_visualizer := true
var visualizer_preset := 0
var visualizer_quality := 0
var visualizer_intensity := 0.75
var visualizer_sensitivity := 1.75
var visualizer_motion := 0.6
var visualizer_sync := 0.0
var visualizer_auto_change := false
var ui_size := 1.0
var text_size := 1.0
var accent_color := VpxTheme.DEFAULT_ACCENT
var spatial_audio := true
var dialogue_boost := false
var audio_filter := AudioFilter.OFF
var audio_stretch_quality := 0
var remote_control := false
var sleep_timer := SleepTimer.OFF
var playback_speed := 1.0
var background := Background.PASSTHROUGH
var chroma_key_color := Color8(0, 30, 60)
var cut_enabled := false
var cut_invert := false
var cut_similarity := 0.08
var cut_feather := 0.08
var mask_threshold := 0.5
var mask_trim := 0.0
var mask_darken := 2.0
var edge_fade := 0.1
var screen_size := 67.0
var screen_curve := 0.0
var brightness := 1.0
var sharpness_level := 0
var gamma := 1.0
var saturation := 1.0
var angle_yaw := 0.0
var angle_pitch := 0.0
var angle_roll := 0.0
var match_refresh_rate := true
var prefer_desktop := false
var muted := false
var volume := 100
var decode_mode := DecodeMode.AUTO
var playback_priority := PlaybackPriority.SMOOTH
var panorama_source := PanoramaSource.CUBE
var photo_supersampling := true
var shuffle := false
var auto_detect := true
var hide_menu_on_play := true
var end_action := EndAction.STOP
var resume_playback := true
var seek_previews := true
var drag_speed := 1.0
var menu_translucent := false
var lock_horizon := false
var show_level := true
var laser_menu_only := false
var follow_posture := false
var look_gain := 1.0
var grip_action := StickAction.SCREEN_SIZE
var trigger_action := StickAction.VOLUME
var chord_action := StickAction.BRIGHTNESS
var legacy_positions := {}
var legacy_formats := {}
var dim_behind_menu := true
var menu_follow := true
var video_follow := false
var pause_when_removed := true
var hover_haptics := true
var show_clock := true
var auto_swap_eyes := true
var face_on_open := false
var audio_language := 0
var subtitle_auto := SubtitleAuto.FOREIGN
var subtitle_language := 0
var subtitle_size := 1.0
var subtitle_size_by_format := {}
var subtitle_offset := 0.0
var subtitle_color := 0
var subtitle_box := false
var subtitle_distance := 2.5
var audio_delay := 0.0
var subtitle_delay := 0.0
var format_path := ""
var detecting := false
var session_format := {}
const SESSION_FORMAT_PROPERTIES := ["projection", "stereo", "swap_eyes", "fisheye_fov", "equirect_fov"]
var last_directory := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
var last_file := ""
var library_view := LibraryView.GRID
var library_flat_view := false
var library_sort := LibrarySort.NAME
var library_source := LibrarySource.FOLDER
var library_filter := LibraryFilter.ALL
var library_query := ""
var network_servers: Array = []
var defaults := {}
var profiles = preload("res://scripts/view_profiles.gd").new()
var save_pending := false
var save_timer := 0.0
var subtitle_size_format := ""


func _ready() -> void:
	subtitle_language = Languages.system_language()
	for property in _persisted() + PackedStringArray(["audio_delay", "subtitle_delay", "playback_speed", "sleep_timer"]) + PackedStringArray(VIEW_ADJUST.keys()):
		defaults[property] = get(property)
	load_config()
	picture_zoom = clampf(picture_zoom, ZOOM_MIN, ZOOM_MAX) if is_finite(picture_zoom) else 1.0
	_validate_visualizer()
	ui_size = clampf(ui_size, 0.8, 1.25) if is_finite(ui_size) else 1.0
	text_size = clampf(text_size, 1.0, 1.5) if is_finite(text_size) else 1.0
	profiles.load_store()
	_sync_accent()
	changed.connect(_sync_accent)
	changed.connect(_sync_subtitle_size)
	_sync_subtitle_size()
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Control:
			VpxTheme.scale_control.call_deferred(node))


func _sync_subtitle_size() -> void:
	var key := "%d:%d" % [projection, stereo]
	if key == subtitle_size_format:
		return
	subtitle_size_format = key
	if subtitle_size_by_format.has(key):
		apply("subtitle_size", float(subtitle_size_by_format[key]))


func _sync_accent() -> void:
	VpxTheme.set_accent(accent_color)
	VpxTheme.set_text_size(text_size, get_tree().root)


func _process(delta: float) -> void:
	if not save_pending:
		return
	save_timer += delta
	if save_timer >= SAVE_DELAY:
		flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush()


func visualizer_advance_limit() -> float:
	return minf(0.25, floorf(maxf(0.0, AudioServer.get_output_latency()) / 0.005) * 0.005)


func _validate_visualizer() -> void:
	music_visualizer_mode = clampi(music_visualizer_mode, 0, 2)
	if music_visualizer_mode == 1:
		music_visualizer_mode = 0
	visualizer_preset = clampi(visualizer_preset, 0, VISUALIZER_PRESET_MAX)
	visualizer_quality = clampi(visualizer_quality, 0, 3)
	visualizer_intensity = clampf(visualizer_intensity, 0.0, 1.5) if is_finite(visualizer_intensity) else 0.75
	visualizer_sensitivity = clampf(visualizer_sensitivity, 0.5, 4.0) if is_finite(visualizer_sensitivity) else 1.75
	visualizer_motion = clampf(visualizer_motion, 0.0, 1.0) if is_finite(visualizer_motion) else 0.6
	visualizer_sync = clampf(visualizer_sync, -0.25, visualizer_advance_limit()) if is_finite(visualizer_sync) else 0.0


func apply(property: StringName, value: Variant) -> void:
	if property in [&"ui_size", &"text_size"]:
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		value = clampf(float(value), 0.8, 1.25) if property == &"ui_size" else clampf(float(value), 1.0, 1.5)
	if property in [&"music_visualizer_mode", &"visualizer_preset", &"visualizer_quality", &"visualizer_intensity", &"visualizer_sensitivity", &"visualizer_motion", &"visualizer_sync"]:
		if not (value is int or value is float) or not is_finite(float(value)):
			return
		var limits := {&"music_visualizer_mode": Vector2(0, 2), &"visualizer_preset": Vector2(0, VISUALIZER_PRESET_MAX), &"visualizer_quality": Vector2(0, 3), &"visualizer_intensity": Vector2(0, 1.5), &"visualizer_sensitivity": Vector2(0.5, 4), &"visualizer_motion": Vector2(0, 1), &"visualizer_sync": Vector2(-0.25, 0.25)}
		if property == &"visualizer_sync":
			limits[property].y = visualizer_advance_limit()
		value = clampf(float(value), limits[property].x, limits[property].y)
		if property in [&"music_visualizer_mode", &"visualizer_preset", &"visualizer_quality"]:
			value = int(value)
		if property == &"music_visualizer_mode" and value == 1:
			value = 0
	if property == &"picture_zoom":
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		value = clampf(float(value), ZOOM_MIN, ZOOM_MAX)
	if get(property) == value:
		return
	set(property, value)
	if property == &"picture_zoom":
		zoom_changed.emit(is_equal_approx(float(value), 1.0))
	Log.note_setting(property, value)
	if property in SESSION_FORMAT_PROPERTIES and not detecting:
		for key: String in SESSION_FORMAT_PROPERTIES:
			session_format[key] = get(key)
	if property in FORMAT_PROPERTIES and not detecting and not format_path.is_empty():
		remember_format()
	save_config()
	changed.emit()


func preview_zoom(value: float) -> void:
	if not is_finite(value):
		return
	picture_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	save_config()
	zoom_changed.emit(false)


func commit_zoom() -> void:
	if not detecting and not format_path.is_empty():
		remember_format()
	commit()


func preview_screen_size(value: float) -> void:
	if not is_finite(value):
		return
	screen_size = clampf(value, 20.0, 140.0)
	save_config()
	screen_size_changed.emit()


func apply_viewing_values(values: Dictionary) -> bool:
	var validator = load("res://scripts/settings_backup.gd")
	for key: String in values:
		if key not in profiles.KEYS or not validator._valid_setting(key, values[key]):
			return false
	var previous := profiles.capture()
	for key: String in values:
		var value: Variant = values[key]
		set(key, value.duplicate(true) if value is Dictionary or value is Array else value)
	save_config()
	if flush() != OK:
		for key: String in previous:
			set(key, previous[key])
		return false
	changed.emit()
	return true


func commit() -> void:
	save_config()
	changed.emit()


func reset(properties: PackedStringArray) -> void:
	var format_changed := false
	for property in properties:
		set(property, defaults[property])
		format_changed = format_changed or property in FORMAT_PROPERTIES
	if not detecting:
		for property: String in properties:
			if property in SESSION_FORMAT_PROPERTIES:
				for key: String in SESSION_FORMAT_PROPERTIES:
					session_format[key] = get(key)
				break
	if "picture_zoom" in properties:
		zoom_changed.emit(true)
	if format_changed and not format_path.is_empty():
		remember_format()
	Log.info("reset %s" % ", ".join(properties))
	save_config()
	changed.emit()


func flat_screen_width() -> float:
	return 2.0 * SCREEN_DISTANCE * tan(deg_to_rad(screen_size) * 0.5)


func flat_image_tiles() -> int:
	return 1 + clampi(flat_image_repeat, 0, 2) * 2 if projection == ProjectionMode.FLAT else 1


func pan_photo(delta: Vector2) -> void:
	var next_x := clampf(photo_pan_x + delta.x, -0.5, 0.5)
	var next_y := clampf(photo_pan_y + delta.y, -0.5, 0.5)
	if is_equal_approx(next_x, photo_pan_x) and is_equal_approx(next_y, photo_pan_y):
		return
	photo_pan_x = next_x
	photo_pan_y = next_y
	changed.emit()


func commit_photo_pan() -> void:
	if not format_path.is_empty():
		remember_format()
	commit()


func matching_preset() -> int:
	for i in FORMAT_PRESETS.size():
		if FORMAT_PRESETS[i][1] == projection and FORMAT_PRESETS[i][2] == stereo:
			return i
	return -1


func presets_for(action: StickAction) -> Array:
	var indexes := []
	for i in FORMAT_PRESETS.size():
		var mono: bool = FORMAT_PRESETS[i][2] == Stereo.MONO
		if action == StickAction.FORMAT_ALL or (action == StickAction.FORMAT_2D) == mono:
			indexes.append(i)
	return indexes


func cycle_preset(action: StickAction, direction: int) -> void:
	var indexes := presets_for(action)
	var position := indexes.find(matching_preset())
	position = wrapi(position + direction, 0, indexes.size()) if position >= 0 else 0
	select_format(FORMAT_PRESETS[indexes[position]][1], FORMAT_PRESETS[indexes[position]][2])


func remember_format() -> void:
	var saved := {}
	for property in FORMAT_PROPERTIES:
		saved[property] = get(property)
	Library.set_pref(format_path, "format", saved)


func restore_format(path: String) -> bool:
	var saved: Variant = Library.get_pref(path, "format")
	if not saved is Dictionary:
		return false
	detecting = true
	apply("projection", int(saved.get("projection", projection)))
	apply("stereo", int(saved.get("stereo", stereo)))
	apply("swap_eyes", bool(saved.get("swap_eyes", swap_eyes)))
	apply("fisheye_fov", float(saved.get("fisheye_fov", fisheye_fov)))
	apply("alpha_mask", int(saved.get("alpha_mask", AlphaMask.NONE)))
	for property: String in VIEW_ADJUST:
		apply(property, type_convert(saved.get(property, VIEW_ADJUST[property]), typeof(VIEW_ADJUST[property])))
	detecting = false
	return true


func has_crop() -> bool:
	return crop_left + crop_top + crop_right + crop_bottom > 0.0001


func crop_rect() -> Vector4:
	return Vector4(crop_left, crop_top, crop_right, crop_bottom)


func apply_crop(rect: Vector4) -> void:
	apply("crop_left", rect.x)
	apply("crop_top", rect.y)
	apply("crop_right", rect.z)
	apply("crop_bottom", rect.w)


func clear_view_adjust() -> void:
	var was_detecting := detecting
	detecting = true
	for property: String in VIEW_ADJUST:
		apply(property, VIEW_ADJUST[property])
	detecting = was_detecting


func remember_position(path: String, seconds: float, length: float) -> void:
	if path.is_empty():
		return
	if length > 0.0 and seconds > length - RESUME_END_MARGIN:
		Library.erase_pref(path, "position")
		Library.mark_finished(path)
	elif seconds < RESUME_MIN_SECONDS:
		Library.erase_pref(path, "position")
	else:
		Library.set_pref(path, "position", seconds)


func resume_position(path: String) -> float:
	return float(Library.get_pref(path, "position", 0.0)) if resume_playback else 0.0


func load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for property in _persisted():
		set(property, config.get_value("player", property, get(property)))
	if not config.has_section_key("player", "immersive_music_visualizer"):
		immersive_music_visualizer = music_visualizer and int(config.get_value("player", "music_visualizer_mode", 1)) == 1
	_validate_visualizer()
	if int(config.get_value("player", "screen_placement_version", 0)) < SCREEN_PLACEMENT_VERSION:
		face_on_open = false
		save_config()
	if not config.has_section_key("player", "screen_size") and config.has_section_key("player", "screen_width"):
		var legacy_width := float(config.get_value("player", "screen_width"))
		var legacy_distance := float(config.get_value("player", "screen_distance", SCREEN_DISTANCE))
		screen_size = clampf(snappedf(rad_to_deg(2.0 * atan(legacy_width * 0.5 / maxf(legacy_distance, 0.1))), 5.0), 20.0, 140.0)
	if config.has_section_key("player", "screen_distance"):
		for property in ["grip_action", "trigger_action", "chord_action"]:
			set(property, maxi(int(get(property)) - 1, 0))
	if not config.has_section_key("player", "library_source") and bool(config.get_value("player", "show_favorites", false)):
		library_source = LibrarySource.FAVORITES
	legacy_positions = config.get_value("player", "resume_positions", {})
	legacy_formats = config.get_value("player", "file_formats", {})


func save_config() -> void:
	save_pending = true
	save_timer = 0.0


func flush() -> Error:
	if not save_pending:
		return OK
	var config := ConfigFile.new()
	for property in _persisted():
		config.set_value("player", property, get(property))
	config.set_value("player", "screen_placement_version", SCREEN_PLACEMENT_VERSION)
	var error := config.save(CONFIG_PATH + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(CONFIG_PATH + ".tmp"), ProjectSettings.globalize_path(CONFIG_PATH))
	if error != OK:
		save_timer = 0.0
		Log.warn("settings: cannot save: " + error_string(error))
		return error
	save_pending = false
	return OK


func _persisted() -> PackedStringArray:
	return PackedStringArray([
		"projection", "stereo", "swap_eyes", "fisheye_fov", "alpha_mask", "background",
		"chroma_key_color", "cut_enabled", "cut_invert", "cut_similarity",
		"cut_feather", "mask_threshold", "mask_trim", "mask_darken", "edge_fade", "screen_size", "screen_curve", "brightness",
		"sharpness_level", "gamma", "saturation", "angle_yaw", "angle_pitch", "angle_roll",
		"match_refresh_rate", "prefer_desktop",
		"muted", "volume", "decode_mode", "playback_priority", "panorama_source", "photo_supersampling", "shuffle", "auto_detect", "hide_menu_on_play",
		"end_action", "resume_playback", "seek_previews", "drag_speed", "menu_translucent", "lock_horizon", "follow_posture", "look_gain", "grip_action", "trigger_action", "chord_action",
		"show_level", "laser_menu_only", "dim_behind_menu", "menu_follow", "video_follow", "pause_when_removed", "hover_haptics", "show_clock", "face_on_open", "auto_swap_eyes",
		"audio_language", "subtitle_auto", "subtitle_language", "subtitle_size", "subtitle_size_by_format", "subtitle_offset", "subtitle_color", "subtitle_box", "subtitle_distance",
		"last_directory", "last_file", "library_view", "library_flat_view", "library_sort", "library_source", "library_filter", "network_servers",
		"stereo_depth", "stereo_vertical", "picture_zoom", "single_eye", "flat_image_repeat", "photo_pan_x", "photo_pan_y",
		"auto_crop", "deband", "dither", "compositor_layer", "spatial_audio", "dialogue_boost", "audio_filter",
		"remote_control", "flat_video_pan", "music_visualizer", "audio_stretch_quality", "accent_color", "ui_size", "text_size",
		"music_visualizer_mode", "immersive_music_visualizer", "visualizer_preset", "visualizer_quality", "visualizer_intensity", "visualizer_sensitivity", "visualizer_motion", "visualizer_sync", "visualizer_auto_change",
	])


func restore_session_format() -> bool:
	if session_format.is_empty():
		return false
	var was_detecting := detecting
	detecting = true
	for key: String in session_format:
		apply(key, session_format[key])
	detecting = was_detecting
	return true


func select_format(mode: int, layout: int) -> void:
	apply("projection", mode)
	apply("stereo", layout)
	if not format_path.is_empty():
		remember_format()
	for key: String in SESSION_FORMAT_PROPERTIES:
		session_format[key] = get(key)
