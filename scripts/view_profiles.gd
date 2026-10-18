extends RefCounted

const PATH := "user://view-profiles.cfg"
const VERSION := 1
const MAX_PROFILES := 32
const MAX_NAME := 64
const KEYS := ["subtitle_size", "subtitle_size_by_format", "subtitle_offset", "subtitle_distance", "subtitle_color", "subtitle_box", "subtitle_auto", "subtitle_language", "follow_posture", "lock_horizon", "video_follow", "menu_follow", "screen_size", "screen_curve", "background", "menu_translucent", "dim_behind_menu", "auto_swap_eyes", "face_on_open", "look_gain", "flat_video_pan", "edge_fade", "accent_color"]
const ADDED_KEYS := ["accent_color"]

var entries: Array = []
var active := ""
var error := ""


func load_store() -> void:
	if not FileAccess.file_exists(PATH):
		return
	if FileAccess.get_size(PATH) > 1048576:
		error = "Viewing profiles file is too large"
		return
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		error = "Could not read viewing profiles"
		return
	var data: Variant = config.get_value("profiles", "data", {})
	if not valid(data):
		error = "Invalid viewing profiles; current settings kept"
		return
	entries = data["entries"].duplicate(true)
	active = data["active"]
	_complete()


func snapshot() -> Dictionary:
	return {"version": VERSION, "entries": entries.duplicate(true), "active": active}


static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or not data.get("entries") is Array or not data.get("active") is String or data["entries"].size() > MAX_PROFILES:
		return false
	var ids := {}
	var names := {}
	var validator = load("res://scripts/settings_backup.gd")
	for entry: Variant in data["entries"]:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("name") is String or not entry.get("values") is Dictionary:
			return false
		var id: String = entry["id"]
		var title: String = entry["name"]
		if id.is_empty() or id.length() > 80 or ids.has(id) or not valid_name(title) or names.has(title.to_lower()):
			return false
		ids[id] = true
		names[title.to_lower()] = true
		for key: String in KEYS:
			if not entry["values"].has(key) and key not in ADDED_KEYS:
				return false
		for key: Variant in entry["values"]:
			if key not in KEYS or not validator._valid_setting(key, entry["values"][key]):
				return false
	return data["active"].is_empty() or ids.has(data["active"])


static func valid_name(title: String) -> bool:
	if title.strip_edges().is_empty() or title.length() > MAX_NAME:
		return false
	for i in title.length():
		if title.unicode_at(i) < 32:
			return false
	return true


func find_entry(id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["id"] == id:
			return entry
	return {}


func capture() -> Dictionary:
	var values := {}
	for key: String in KEYS:
		var value: Variant = Settings.get(key)
		values[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return values


func modified() -> bool:
	var entry := find_entry(active)
	return not entry.is_empty() and entry["values"] != capture()


func title() -> String:
	var entry := find_entry(active)
	return "Custom" if entry.is_empty() else entry["name"] + (" · Modified" if modified() else "")


func restore(data: Dictionary) -> bool:
	if not valid(data):
		error = "Invalid viewing profiles"
		return false
	var previous := snapshot()
	entries = data["entries"].duplicate(true)
	active = data["active"]
	_complete()
	if not _save():
		entries = previous["entries"]
		active = previous["active"]
		return false
	return true


func save_current(title_text: String) -> bool:
	var title_value := title_text.strip_edges()
	if not _check_name(title_value) or entries.size() >= MAX_PROFILES:
		if entries.size() >= MAX_PROFILES:
			error = "Maximum 32 profiles"
		return false
	var data := snapshot()
	var id := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	data["entries"].append({"id": id, "name": title_value, "values": capture()})
	data["active"] = id
	return _finish(data)


func update_current() -> bool:
	var data := snapshot()
	for entry: Dictionary in data["entries"]:
		if entry["id"] == active:
			entry["values"] = capture()
			return _finish(data)
	error = "Select a saved profile first"
	return false


func rename_current(title_text: String) -> bool:
	var title_value := title_text.strip_edges()
	if not _check_name(title_value, active):
		return false
	var data := snapshot()
	for entry: Dictionary in data["entries"]:
		if entry["id"] == active:
			entry["name"] = title_value
			return _finish(data)
	return false


func delete_current() -> bool:
	var data := snapshot()
	data["entries"] = data["entries"].filter(func(entry: Dictionary) -> bool: return entry["id"] != active)
	data["active"] = ""
	return _finish(data)


func select(id: String) -> bool:
	if id.is_empty():
		var custom := snapshot()
		custom["active"] = ""
		return _finish(custom)
	var entry := find_entry(id)
	if entry.is_empty():
		return false
	var previous := snapshot()
	var data := snapshot()
	data["active"] = id
	if not restore(data):
		return false
	if not Settings.apply_viewing_values(entry["values"]):
		restore(previous)
		error = "Could not save profile settings; previous view kept"
		return false
	return true


func _complete() -> void:
	for entry: Dictionary in entries:
		for key: String in ADDED_KEYS:
			if not entry["values"].has(key):
				entry["values"][key] = Settings.get(key)


func _check_name(value: String, except := "") -> bool:
	if not valid_name(value):
		error = "Use a name from 1 to 64 characters"
		return false
	for entry: Dictionary in entries:
		if entry["id"] != except and entry["name"].to_lower() == value.to_lower():
			error = "A profile already uses that name"
			return false
	return true


func _finish(data: Dictionary) -> bool:
	if not restore(data):
		return false
	Settings.changed.emit()
	return true


func _save() -> bool:
	var config := ConfigFile.new()
	config.set_value("profiles", "data", snapshot())
	var result := config.save(PATH + ".tmp")
	if result == OK:
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))
	if result != OK:
		error = "Could not save viewing profiles: " + error_string(result)
		return false
	error = ""
	return true
