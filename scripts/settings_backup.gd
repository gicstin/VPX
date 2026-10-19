extends RefCounted

const VERSION := 2
const MAX_BYTES := 16777216
const LIMITS := {
	"ui_size": [0.8, 1.25], "text_size": [1, 1.5],
	"music_visualizer_mode": [0, 2], "visualizer_preset": [0, Settings.VISUALIZER_PRESET_MAX], "visualizer_quality": [0, 3], "visualizer_grab_mode": [0, 2],
	"visualizer_intensity": [0, 1.5], "visualizer_sensitivity": [0.5, 4], "visualizer_motion": [0, 1], "visualizer_sync": [-0.25, 0.25],
	"projection": [0, 5], "stereo": [0, 2], "alpha_mask": [0, 2], "background": [0, 3],
	"decode_mode": [0, 2], "end_action": [0, 2], "playback_priority": [0, 1], "panorama_source": [0, 1],
	"grip_action": [0, 15], "trigger_action": [0, 15], "chord_action": [0, 15], "library_view": [0, 1],
	"library_sort": [0, 2], "library_source": [0, 4], "library_filter": [0, 5],
	"audio_stretch_quality": [0, 1], "subtitle_auto": [0, 2], "subtitle_color": [0, 2], "sharpness_level": [0, 5], "audio_filter": [0, 2], "deband": [0, 3],
	"screen_size": [20, 140], "screen_curve": [0, 1], "picture_zoom": [Settings.ZOOM_MIN, Settings.ZOOM_MAX], "flat_image_repeat": [0, 2],
	"photo_pan_x": [-0.5, 0.5], "photo_pan_y": [-0.5, 0.5], "fisheye_fov": [90, 270], "equirect_fov": [90, 360],
	"stereo_depth": [-3, 3], "stereo_vertical": [-2, 2], "eye_roll": [-3, 3], "lens_k1": [-0.5, 0.5], "lens_k2": [-0.5, 0.5],
	"crop_left": [0, 0.45], "crop_right": [0, 0.45], "crop_top": [0, 0.45], "crop_bottom": [0, 0.45],
	"brightness": [0.2, 2], "gamma": [0.4, 2.2], "saturation": [0, 2], "volume": [0, 100],
	"look_gain": [1, 2.5], "drag_speed": [0.1, 5], "subtitle_size": [0.5, 2.5], "subtitle_offset": [-0.4, 0.5],
	"subtitle_distance": [1, 8], "cut_similarity": [0, 1], "cut_feather": [0, 1], "edge_fade": [0, 0.4],
	"mask_threshold": [0, 1], "mask_trim": [0, 1], "mask_darken": [0, 10], "playback_speed": [0.5, 2]
}


static func export_settings(path: String, include_library := false, redact_credentials := true) -> Dictionary:
	var config := ConfigFile.new()
	config.set_value("backup", "version", VERSION)
	config.set_value("profiles", "data", Settings.profiles.snapshot())
	config.set_value("backup", "created", Time.get_datetime_string_from_system())
	config.set_value("backup", "screen_placement_version", Settings.SCREEN_PLACEMENT_VERSION)
	for property: String in Settings._persisted():
		config.set_value("settings", property, _redact(Settings.get(property)) if redact_credentials else Settings.get(property))
	if include_library:
		var files := {}
		for key: String in Library.entries:
			files[_strip_password(key) if redact_credentials else key] = _redact(Library.entries[key]) if redact_credentials else Library.entries[key]
		config.set_value("library", "files", files)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return {"ok": false, "error": "Could not save backup: " + error_string(error)}
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "Could not finish backup: " + error_string(error)}
	return {"ok": true, "path": path}


static func import_settings(path: String, include_library := false) -> Dictionary:
	if not FileAccess.file_exists(path) or FileAccess.get_size(path) > MAX_BYTES:
		return {"ok": false, "error": "Backup is missing or larger than 16 MB"}
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return {"ok": false, "error": "Invalid settings file: " + error_string(error)}
	var legacy := not config.has_section("backup") and config.has_section("player")
	if not legacy and int(config.get_value("backup", "version", -1)) not in [1, VERSION]:
		return {"ok": false, "error": "Unsupported backup version"}
	var section := "player" if legacy else "settings"
	if not config.has_section(section):
		return {"ok": false, "error": "Backup has no settings"}
	var values := {}
	for property: String in config.get_section_keys(section):
		if property not in Settings._persisted():
			continue
		var value: Variant = config.get_value(section, property)
		if not _valid_setting(property, value):
			return {"ok": false, "error": "Invalid value for " + property}
		values[property] = type_convert(value, typeof(Settings.defaults[property]))
	if values.is_empty():
		return {"ok": false, "error": "Backup contains no recognized settings"}
	if not values.has("immersive_music_visualizer") and (values.has("music_visualizer") or values.has("music_visualizer_mode")):
		values["immersive_music_visualizer"] = bool(values.get("music_visualizer", true)) and int(values.get("music_visualizer_mode", 1)) == 1
	if values.get("music_visualizer_mode", 0) == 1:
		values["music_visualizer_mode"] = 0
	var placement: int = config.get_value(section if legacy else "backup", "screen_placement_version", 0)
	if placement < Settings.SCREEN_PLACEMENT_VERSION:
		values["face_on_open"] = false
	if legacy and not values.has("screen_size") and config.has_section_key(section, "screen_width"):
		var width: Variant = config.get_value(section, "screen_width")
		var distance: Variant = config.get_value(section, "screen_distance", Settings.SCREEN_DISTANCE)
		if not _finite_number(width) or not _finite_number(distance) or float(distance) <= 0.0:
			return {"ok": false, "error": "Invalid legacy screen size"}
		values["screen_size"] = clampf(snappedf(rad_to_deg(2.0 * atan(float(width) * 0.5 / float(distance))), 5.0), 20.0, 140.0)
	if legacy and config.has_section_key(section, "screen_distance"):
		for property in ["grip_action", "trigger_action", "chord_action"]:
			if values.has(property):
				values[property] = maxi(int(values[property]) - 1, 0)
	var has_library := config.has_section_key("library", "files") or (legacy and (config.has_section_key("player", "resume_positions") or config.has_section_key("player", "file_formats")))
	var files: Variant = _legacy_library(config) if legacy and include_library else config.get_value("library", "files", {})
	if include_library and not _valid_library(files):
		return {"ok": false, "error": "Invalid library data"}
	var profile_data: Variant = config.get_value("profiles", "data") if config.has_section_key("profiles", "data") else null
	if profile_data != null and not Settings.profiles.valid(profile_data):
		return {"ok": false, "error": "Invalid viewing profiles"}
	var previous_profiles: Dictionary = Settings.profiles.snapshot()
	var directory := ProjectSettings.globalize_path("user://backups")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Could not create rollback backup folder"}
	var rollback := directory.path_join("before-import-%d-%d.cfg" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	var backup := export_settings(rollback, true, false)
	if not backup["ok"]:
		return backup
	var previous := {}
	for property: String in Settings._persisted():
		previous[property] = Settings.get(property)
	var previous_files: Dictionary = Library.entries.duplicate(true)
	for property: String in values:
		Settings.set(property, values[property])
	Settings.save_config()
	error = Settings.flush()
	if error == OK and include_library and has_library:
		Library.entries = files.duplicate(true)
		Library.favorites.clear()
		Library._index_favorites()
		Library._mark_dirty()
		error = Library.save()
	if error == OK and profile_data != null and not Settings.profiles.restore(profile_data):
		error = ERR_CANT_CREATE
	if error != OK:
		Settings.profiles.restore(previous_profiles)
		for property: String in previous:
			Settings.set(property, previous[property])
		Library.entries = previous_files
		Library.favorites.clear()
		Library._index_favorites()
		Settings.save_config()
		Settings.flush()
		Library._mark_dirty()
		Library.save()
		return {"ok": false, "error": "Import could not be saved; previous settings restored. Backup: " + rollback}
	Settings.session_format.clear()

	Settings.changed.emit()
	return {"ok": true, "backup": rollback, "count": values.size()}


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _valid_setting(property: String, value: Variant) -> bool:
	var expected: Variant = Settings.defaults.get(property)
	if expected is float or expected is int:
		if not _finite_number(value) or (expected is int and float(value) != floorf(float(value))):
			return false
		if LIMITS.has(property):
			var bounds: Array = LIMITS[property]
			return float(value) >= bounds[0] and float(value) <= bounds[1]
		return absf(float(value)) <= 1000000.0
	if typeof(expected) != typeof(value) or not _valid_value(value):
		return false
	if property == "network_servers":
		for server: Variant in value:
			if not server is Dictionary or not server.get("name") is String or not server.get("url") is String:
				return false
	if property == "subtitle_size_by_format":
		for key: Variant in value:
			if not key is String or not _finite_number(value[key]) or float(value[key]) < 0.5 or float(value[key]) > 2.5:
				return false
	return true


static func _valid_library(files: Variant) -> bool:
	if not files is Dictionary or files.size() > Library.MAX_ENTRIES or not _valid_value(files):
		return false
	for path: Variant in files:
		if not path is String or not files[path] is Dictionary:
			return false
		var format: Variant = files[path].get("format")
		if format != null:
			if not format is Dictionary:
				return false
			for property: Variant in format:
				if not property is String or property not in Settings.FORMAT_PROPERTIES + ["flat_image_repeat"] or not _valid_setting(property, format[property]):
					return false
	return true


static func _valid_value(value: Variant, depth := 0) -> bool:
	if depth > 12:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= 32768
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.size() > 10000:
				return false
			for item: Variant in value:
				if not _valid_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 10000:
				return false
			for key: Variant in value:
				if not key is String or not _valid_value(key, depth + 1) or not _valid_value(value[key], depth + 1):
					return false
			return true
	return false


static func _strip_password(text: String) -> String:
	var start := text.find("://")
	if start < 0:
		return text
	start += 3
	var end := text.find("/", start)
	if end < 0:
		end = text.length()
	var at := text.find("@", start)
	if at < 0 or at > end:
		return text
	var colon := text.find(":", start)
	if colon < 0 or colon > at:
		return text
	return text.substr(0, colon) + text.substr(at)


static func _redact(value: Variant) -> Variant:
	if value is String:
		return _strip_password(value)
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(_redact(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _redact(value[key])
		return result
	return value


static func _legacy_library(config: ConfigFile) -> Variant:
	var positions: Variant = config.get_value("player", "resume_positions", {})
	var formats: Variant = config.get_value("player", "file_formats", {})
	if not positions is Dictionary or not formats is Dictionary:
		return null
	var files: Dictionary = Library.entries.duplicate(true)
	for path: Variant in positions:
		if not path is String or not _finite_number(positions[path]) or float(positions[path]) < 0.0:
			return null
		var entry: Dictionary = files.get(path, {})
		entry["position"] = float(positions[path])
		files[path] = entry
	for path: Variant in formats:
		var value: Variant = formats[path]
		if not path is String or not value is Array or value.size() < 4:
			return null
		var saved := {"projection": value[0], "stereo": value[1], "swap_eyes": value[2], "fisheye_fov": value[3]}
		for key: String in saved:
			if not _valid_setting(key, saved[key]):
				return null
		var entry: Dictionary = files.get(path, {})
		entry["format"] = saved
		files[path] = entry
	return files
