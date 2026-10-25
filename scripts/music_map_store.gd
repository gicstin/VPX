class_name MusicMapStore
extends RefCounted

const DIRECTORY := "user://music_maps"
const LIMIT := 400
const MAX_BYTES := 2000000000

static var _analysis_version := -1

var directory := DIRECTORY
var analysis: Object
var pending_path := ""
var pending_key := ""
var map: MusicMap
var map_path := ""
var failed := {}
var retiring: Array[Object] = []


static func available() -> bool:
	return ClassDB.class_exists(&"VPXMusicAnalysis")


static func analysable(path: String) -> bool:
	return not path.is_empty() and not path.contains("://") and FileAccess.file_exists(path) and FileAccess.get_size(path) <= MAX_BYTES


func cache_key(path: String) -> String:
	var stamp := "%s|%d|%d|%d" % [path, FileAccess.get_size(path) if FileAccess.file_exists(path) else 0, FileAccess.get_modified_time(path), _version()]
	return stamp.md5_text()


func cache_file(key: String) -> String:
	return directory.path_join(key + ".map")


func request(path: String) -> MusicMap:
	if path == map_path and map != null:
		return map
	if path == pending_path:
		return null
	cancel()
	map = null
	map_path = ""
	if not available() or not analysable(path) or failed.has(path):
		return null
	var key := cache_key(path)
	var cached := _load(key)
	if cached != null:
		map = cached
		map_path = path
		return map
	analysis = ClassDB.instantiate(&"VPXMusicAnalysis")
	if not analysis.start(path):
		analysis = null
		return null
	pending_path = path
	pending_key = key
	return null


func poll() -> MusicMap:
	retiring = retiring.filter(func(old: Object) -> bool: return old.is_running())
	if analysis == null or not analysis.is_done():
		return null
	var result: Dictionary = analysis.get_result()
	var path := pending_path
	var key := pending_key
	analysis = null
	pending_path = ""
	pending_key = ""
	var loaded := MusicMap.from_dictionary(result)
	if loaded == null:
		failed[path] = true
		return null
	_save(key, result)
	map = loaded
	map_path = path
	return map


func progress() -> float:
	return analysis.get_progress() if analysis != null else (1.0 if map != null else 0.0)


func is_pending() -> bool:
	return analysis != null


func cancel() -> void:
	if analysis != null:
		analysis.stop()
		retiring.append(analysis)
	analysis = null
	pending_path = ""
	pending_key = ""


func clear() -> void:
	cancel()
	map = null
	map_path = ""


func _version() -> int:
	if _analysis_version < 0:
		_analysis_version = int(ClassDB.instantiate(&"VPXMusicAnalysis").get_version()) if available() else 0
	return _analysis_version


func _load(key: String) -> MusicMap:
	var file_path := cache_file(key)
	if not FileAccess.file_exists(file_path):
		return null
	var file := FileAccess.open_compressed(file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return null
	var value: Variant = file.get_var()
	file.close()
	if not value is Dictionary or int(value.get("version", -1)) != _version():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
		return null
	return MusicMap.from_dictionary(value)


func _save(key: String, result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open_compressed(cache_file(key), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return
	file.store_var(result)
	file.close()
	_prune()


func _prune() -> void:
	var files := DirAccess.get_files_at(directory)
	if files.size() <= LIMIT:
		return
	var dated := []
	for name in files:
		var full := directory.path_join(name)
		dated.append([FileAccess.get_modified_time(full), full])
	dated.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in dated.size() - LIMIT:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dated[i][1]))
