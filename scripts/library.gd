extends Node

const PATH := "user://library.json"
const SAVE_DELAY := 1.0
const MAX_ENTRIES := 5000
const MAX_LINKS := 60

var entries := {}
var favorites := {}
var dirty := false
var save_timer := 0.0


func _ready() -> void:
	_load()
	_import_legacy()
	_index_favorites()


func is_favorite(path: String) -> bool:
	return path in favorites


func set_favorite(path: String, on: bool) -> void:
	if path.is_empty() or on == (path in favorites):
		return
	if on:
		favorites[path] = true
		set_pref(path, "favorite", true)
	else:
		favorites.erase(path)
		erase_pref(path, "favorite")


func favorite_paths() -> PackedStringArray:
	return PackedStringArray(favorites.keys())


func mark_played(path: String) -> void:
	set_pref(path, "played", Time.get_unix_time_from_system())


func remember_link(url: String) -> void:
	set_pref(url, "link_opened", Time.get_unix_time_from_system())
	for path: String in recent_links(MAX_ENTRIES).slice(MAX_LINKS):
		erase_pref(path, "link_opened")


func recent_links(limit := MAX_LINKS) -> PackedStringArray:
	var paths: Array = entries.keys().filter(func(path: String) -> bool:
		return entries[path].has("link_opened") or (path.begins_with("http://") or path.begins_with("https://")) and entries[path].has("played"))
	paths.sort_custom(func(a: String, b: String) -> bool:
		return float(entries[a].get("link_opened", entries[a].get("played", 0.0))) > float(entries[b].get("link_opened", entries[b].get("played", 0.0))))
	return PackedStringArray(paths.slice(0, maxi(limit, 0)))


func mark_folder_visited(path: String) -> void:
	if not path.is_empty():
		set_pref(path, "is_directory", true)
		set_pref(path, "folder_visited", Time.get_unix_time_from_system())


func mark_finished(path: String) -> void:
	set_pref(path, "finished", true)


func recent_paths(limit: int) -> PackedStringArray:
	var played: Array = []
	for path: String in entries:
		var stamp: Variant = entries[path].get("played")
		if stamp != null:
			played.append([float(stamp), path])
	played.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var paths := PackedStringArray()
	for entry in played:
		if paths.size() >= limit:
			break
		paths.append(entry[1])
	return paths


func recent_folders(limit: int) -> PackedStringArray:
	var visited: Array = []
	for path: String in entries:
		var stamp: Variant = entries[path].get("folder_visited")
		if stamp != null:
			visited.append([float(stamp), path])
	visited.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var paths := PackedStringArray()
	for entry in visited:
		if paths.size() >= limit:
			break
		paths.append(entry[1])
	return paths


func forget_played(path: String) -> void:
	erase_pref(path, "played")


func get_pref(path: String, key: String, default: Variant = null) -> Variant:
	var entry: Dictionary = entries.get(path, {})
	return entry.get(key, default)


func set_pref(path: String, key: String, value: Variant) -> void:
	if path.is_empty():
		return
	var entry: Dictionary = entries.get(path, {})
	entry[key] = value
	entry["seen"] = Time.get_unix_time_from_system()
	entries[path] = entry
	_mark_dirty()


func erase_pref(path: String, key: String) -> void:
	if path not in entries:
		return
	entries[path].erase(key)
	_mark_dirty()


func forget(path: String) -> void:
	if entries.erase(path):
		_mark_dirty()


func rekey_paths(mapping: Dictionary) -> void:
	for old: String in mapping:
		if entries.has(old):
			entries[mapping[old]] = _replace_paths(entries[old], mapping)
			entries.erase(old)
	favorites.clear()
	_index_favorites()
	_mark_dirty()


func _replace_paths(value: Variant, mapping: Dictionary) -> Variant:
	if value is String:
		return mapping.get(value, value)
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_replace_paths(item, mapping))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _replace_paths(value[key], mapping)
		return result
	return value


func clear() -> void:
	entries.clear()
	_mark_dirty()


func _mark_dirty() -> void:
	dirty = true
	save_timer = 0.0


func _process(delta: float) -> void:
	if not dirty:
		return
	save_timer += delta
	if save_timer >= SAVE_DELAY:
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save()


func save() -> Error:
	if not dirty:
		return OK
	_prune()
	var file := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		Log.warn("library: cannot write %s" % PATH)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "files": entries}))
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))
	if error != OK:
		save_timer = 0.0
		Log.warn("library: cannot save: " + error_string(error))
		return error
	dirty = false
	return OK


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and data.get("files") is Dictionary:
		entries = data["files"]
	else:
		Log.warn("library: %s unreadable, starting empty" % PATH)


func _prune() -> void:
	var excess := entries.size() - MAX_ENTRIES
	if excess <= 0:
		return
	var paths: Array = entries.keys().filter(func(path: String) -> bool: return path not in favorites)
	paths.sort_custom(func(a: String, b: String) -> bool:
		return float(entries[a].get("seen", 0)) < float(entries[b].get("seen", 0)))
	for i in mini(excess, paths.size()):
		entries.erase(paths[i])


func _index_favorites() -> void:
	for path in entries:
		if entries[path].get("favorite", false):
			favorites[path] = true


func _import_legacy() -> void:
	var imported := 0
	for path in Settings.legacy_positions:
		if path not in entries:
			set_pref(path, "position", float(Settings.legacy_positions[path]))
			imported += 1
	for path in Settings.legacy_formats:
		var saved: Array = Settings.legacy_formats[path]
		if saved.size() >= 4 and get_pref(path, "format") == null:
			set_pref(path, "format", {"projection": int(saved[0]), "stereo": int(saved[1]), "swap_eyes": bool(saved[2]), "fisheye_fov": float(saved[3])})
			imported += 1
	if imported > 0:
		Log.info("library: imported %d legacy entries" % imported)
		save()
	Settings.legacy_positions.clear()
	Settings.legacy_formats.clear()
