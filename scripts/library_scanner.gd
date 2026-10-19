extends Node

signal finished(result: Dictionary)
signal cover_found(path: String, cover: Dictionary)

enum Sort { NAME, DATE, SIZE }

const BackgroundTask := preload("res://scripts/background_task.gd")
const SCAN_TIMEOUT := 15.0
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const Shuffle := preload("res://scripts/shuffle.gd")
const RESOLVE_SETS_LIMIT := 400
const CHECK_EVERY := 32
const FIRST_EMIT_COUNT := 60
const FIRST_EMIT_MSEC := 30
const EMIT_INTERVAL_MSEC := 250
const EMIT_SORT_FACTOR := 3
const COVER_BACKLOG := 256

var extensions: Array = []
var mutex := Mutex.new()
var cover_requests: Array[String] = []
var results: Array[Dictionary] = []
var latest := {"listing": 0, "playlist": 0, "cover": 0}
var jobs := {}
var token: RefCounted
var scanning := false


func _init(p_extensions: Array = []) -> void:
	extensions = p_extensions


func _exit_tree() -> void:
	for lane: String in jobs.keys():
		_cancel_lane(lane)


func folder(path: String, sort: int, fallbacks: PackedStringArray, filter := {}, recursive := false, words := PackedStringArray()) -> int:
	return _submit_listing({"kind": "folder", "path": path, "sort": sort, "fallbacks": fallbacks, "filter": filter, "recursive": recursive, "words": words})


func search(root: String, words: PackedStringArray, sort: int, max_folders: int, max_depth: int, max_results: int, filter := {}) -> int:
	return _submit_listing({"kind": "search", "path": root, "words": words, "sort": sort, "max_folders": max_folders, "max_depth": max_depth, "max_results": max_results, "filter": filter})


func playlist(path: String, images: bool, sort: int = Sort.NAME, filter := {}) -> int:
	var audio := path.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS
	return _submit_playlist({"kind": "playlist", "path": path, "images": images, "audio_only": audio, "sort": sort, "filter": filter})


func prepare(files: PackedStringArray, current: String) -> int:
	return _submit_playlist({"kind": "prepare", "path": current, "files": files, "audio_only": current.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS})


func _submit_playlist(request: Dictionary) -> int:
	return _submit(request, "playlist")


static func index_of(files: PackedStringArray) -> Dictionary:
	var index := {}
	for i in files.size():
		index[files[i]] = i
	return index


func cover(path: String) -> void:
	cover_requests.erase(path)
	cover_requests.append(path)
	if cover_requests.size() > COVER_BACKLOG:
		cover_requests.remove_at(0)


func clear_covers() -> void:
	cover_requests.clear()
	_cancel_lane("cover")


func cancel() -> void:
	_cancel_lane("listing")
	scanning = false


func _cancel_lane(lane: String) -> void:
	latest[lane] += 1
	var job: Node = jobs.get(lane)
	if is_instance_valid(job):
		job.cancel()
	jobs.erase(lane)


func _submit_listing(request: Dictionary) -> int:
	scanning = true
	return _submit(request, "listing")


func _submit(request: Dictionary, lane: String) -> int:
	_cancel_lane(lane)
	request["serial"] = latest[lane]
	request["lane"] = lane
	var serial: int = latest[lane]
	var job := _start_job(request)
	jobs[lane] = job
	job.completed.connect(func(result: Dictionary) -> void:
		if serial != latest[lane]:
			return
		jobs.erase(lane)
		if lane == "listing":
			scanning = false
			if not result.get("ok", false) and not result.get("cancelled", false):
				finished.emit({"kind": request["kind"], "path": request["path"], "done": true, "error": true, "message": result.get("error", "This folder cannot be opened")})
		elif lane == "cover" and not result.get("ok", false):
			cover_found.emit(request["path"], {}))
	return serial


func _start_job(request: Dictionary) -> Node:
	return BackgroundTask.start(_run_job.bind(request, extensions.duplicate(), mutex, results), SCAN_TIMEOUT)


static func _run_job(p_token: RefCounted, request: Dictionary, p_extensions: Array, p_mutex: Mutex, p_results: Array[Dictionary]) -> Dictionary:
	var worker = load("res://scripts/library_scanner.gd").new(p_extensions)
	worker.token = p_token
	worker.mutex = p_mutex
	worker.results = p_results
	worker.latest[request["lane"]] = request["serial"]
	match request["lane"]:
		"listing":
			if request["kind"] == "folder":
				worker._scan_folder(request)
			else:
				worker._scan_search(request)
		"playlist":
			var files: PackedStringArray = request["files"] if request["kind"] == "prepare" else worker._ordered_playlist(worker._scan_playlist(request), request)
			if not p_token.is_cancelled():
				var shuffle := Shuffle.new()
				shuffle.sync(files, "")
				worker._post({"serial": request["serial"], "lane": "playlist", "kind": "playlist", "path": request["path"], "files": files, "index": index_of(files), "shuffle": shuffle, "audio_only": request.get("audio_only", false)})
		"cover":
			worker._post({"serial": request["serial"], "lane": "cover", "path": request["path"], "cover": worker.folder_cover(request["path"])})
	worker.free()
	return {"ok": true}


func _process(_delta: float) -> void:
	mutex.lock()
	var ready := results.duplicate()
	results.clear()
	mutex.unlock()
	for result in ready:
		if int(result["serial"]) != int(latest[result["lane"]]):
			continue
		if result["lane"] == "cover":
			cover_found.emit(result["path"], result["cover"])
		else:
			var job: Node = jobs.get(result["lane"])
			if is_instance_valid(job) and result["lane"] == "listing":
				job.deadline = Time.get_ticks_msec() + int(SCAN_TIMEOUT * 1000.0)
			finished.emit(result)
	if not jobs.has("cover") and not cover_requests.is_empty():
		_submit({"kind": "cover", "path": cover_requests.pop_back()}, "cover")


func _post(result: Dictionary) -> void:
	if token != null and token.is_cancelled():
		return
	mutex.lock()
	results.append(result)
	mutex.unlock()


func _playlist_stale(serial: int) -> bool:
	return (token != null and token.is_cancelled()) or serial != int(latest["playlist"])


func _cancelled(serial: int) -> bool:
	return (token != null and token.is_cancelled()) or serial != int(latest["listing"])


func is_media(name: String) -> bool:
	return name.get_extension().to_lower() in extensions or PanoramaFiles.is_image(name)


func _new_state(request: Dictionary, path: String) -> Dictionary:
	return {
		"request": request, "path": path, "folders": [] as Array[String], "files": [] as Array[String], "keys": {},
		"plain_images": {}, "deferred": {}, "entries": 0, "emitted": false,
		"started": Time.get_ticks_msec(), "last_emit": 0, "sort_cost": 0, "truncated": false, "flat": request["kind"] == "folder" and not request.get("recursive", false),
	}


func _scan_folder(request: Dictionary) -> void:
	var serial: int = request["serial"]
	var path: String = request["path"]
	var dir := DirAccess.open(path)
	if dir == null:
		for fallback in request["fallbacks"]:
			dir = DirAccess.open(fallback)
			if dir != null:
				path = fallback
				break
	if dir == null:
		_post({"serial": serial, "lane": "listing", "kind": "folder", "path": path, "folders": PackedStringArray(), "files": PackedStringArray(), "done": true, "error": true})
		return
	if request.get("recursive", false):
		_scan_tree(request, path)
		return
	var state := _new_state(request, path)
	if _read_dir(dir, path, state, serial, PackedStringArray(), false):
		return
	_resolve_faces(state, path)
	_emit(state, true)


func _read_dir(dir: DirAccess, path: String, state: Dictionary, serial: int, words: PackedStringArray, collect_folders_only_matching: bool, children: Array = []) -> bool:
	dir.include_hidden = false
	dir.include_navigational = false
	if dir.list_dir_begin() != OK:
		return false
	var name := dir.get_next()
	var count := 0
	while not name.is_empty():
		if dir.current_is_dir():
			if not name.begins_with("."):
				if collect_folders_only_matching and not dir.is_link(name):
					children.append(path.path_join(name))
				if not state["request"].get("recursive", false) and (not collect_folders_only_matching or words_match(name, words)):
					_add_folder(state, path, name)
		elif is_media(name) and (words.is_empty() or words_match(name.uri_decode(), words)):
			_add_file(state, path, name)
		state["entries"] += 1
		count += 1
		if count % CHECK_EVERY == 0:
			if _cancelled(serial):
				dir.list_dir_end()
				return true
			_maybe_emit(state)
		name = dir.get_next()
	dir.list_dir_end()
	return false


func _add_folder(state: Dictionary, directory: String, name: String) -> void:
	var entry := name if state["flat"] else directory.path_join(name)
	state["folders"].append(entry)
	if int(state["request"]["sort"]) == Sort.DATE:
		state["keys"][entry] = FileAccess.get_modified_time(directory.path_join(name))


func _add_file(state: Dictionary, directory: String, name: String) -> void:
	if PanoramaFiles.is_image(name):
		if not PanoramaFiles.face_of(name).is_empty():
			_group(state["deferred"], directory).append(name)
			return
		_group(state["plain_images"], directory).append(name)
	_accept_file(state, directory, name)


func _group(groups: Dictionary, key: String) -> Array:
	if not groups.has(key):
		groups[key] = []
	return groups[key]


func _accept_file(state: Dictionary, directory: String, name: String) -> void:
	var path := directory.path_join(name)
	if not _passes(state["request"].get("filter", {}), path):
		return
	var entry := name if state["flat"] else path
	state["files"].append(entry)
	match int(state["request"]["sort"]):
		Sort.DATE:
			state["keys"][entry] = FileAccess.get_modified_time(path)
		Sort.SIZE:
			state["keys"][entry] = FileAccess.get_size(path)


func _resolve_faces(state: Dictionary, only_directory := "") -> void:
	var deferred: Dictionary = state["deferred"]
	for directory: String in deferred.keys():
		if not only_directory.is_empty() and directory != only_directory:
			continue
		var faces := {}
		var names: Array[String] = []
		for name: String in deferred[directory]:
			faces[name] = true
			names.append(name)
		for name: String in state["plain_images"].get(directory, []):
			names.append(name)
		for name in PanoramaFiles.visible_images(directory, names):
			if faces.has(name):
				_accept_file(state, directory, name)
		deferred.erase(directory)
		state["plain_images"].erase(directory)


func _passes(filter: Dictionary, path: String) -> bool:
	if filter.is_empty():
		return true
	var kind: int = filter["kind"]
	if kind == Settings.LibraryFilter.PHOTOS:
		return PanoramaFiles.is_image(path)
	return format_kind(path, filter["info"].get(path, {}), filter["formats"].get(path)) == kind


func _maybe_emit(state: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if not state["emitted"]:
		if state["folders"].size() + state["files"].size() >= FIRST_EMIT_COUNT or now - int(state["started"]) >= FIRST_EMIT_MSEC:
			_emit(state, false)
		return
	if now - int(state["last_emit"]) >= maxi(EMIT_INTERVAL_MSEC, int(state["sort_cost"]) * EMIT_SORT_FACTOR):
		_emit(state, false)


func _emit(state: Dictionary, done: bool) -> void:
	var started := Time.get_ticks_msec()
	var request: Dictionary = state["request"]
	var by_file: bool = not state["flat"]
	_sort(state["folders"], state["keys"], int(request["sort"]) == Sort.DATE, by_file)
	_sort(state["files"], state["keys"], int(request["sort"]) != Sort.NAME, by_file)
	var result := {
		"serial": request["serial"], "lane": "listing", "kind": request["kind"], "path": state["path"],
		"folders": _paths(state, state["folders"]), "files": _paths(state, state["files"]),
		"done": done, "entries": state["entries"], "truncated": state["truncated"],
	}
	state["emitted"] = true
	state["last_emit"] = Time.get_ticks_msec()
	state["sort_cost"] = state["last_emit"] - started
	_post(result)


func _paths(state: Dictionary, entries: Array[String]) -> PackedStringArray:
	if not state["flat"]:
		return PackedStringArray(entries)
	var directory: String = state["path"]
	var paths := PackedStringArray()
	paths.resize(entries.size())
	for i in entries.size():
		paths[i] = directory.path_join(entries[i])
	return paths


func _sort(paths: Array[String], keys: Dictionary, by_key: bool, by_file: bool) -> void:
	if by_key:
		paths.sort_custom(func(a: String, b: String) -> bool:
			var key_a: Variant = keys[a]
			var key_b: Variant = keys[b]
			return a.naturalnocasecmp_to(b) < 0 if key_a == key_b else key_a > key_b)
	elif by_file:
		var names := PackedStringArray()
		var order: Array[int] = []
		names.resize(paths.size())
		order.resize(paths.size())
		for i in paths.size():
			names[i] = paths[i].get_file()
			order[i] = i
		order.sort_custom(func(a: int, b: int) -> bool: return names[a].naturalnocasecmp_to(names[b]) < 0)
		var original := paths.duplicate()
		for i in paths.size():
			paths[i] = original[order[i]]
	else:
		paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)


func _scan_search(request: Dictionary) -> void:
	_scan_tree(request, request["path"])


func _scan_tree(request: Dictionary, path: String) -> void:
	var serial: int = request["serial"]
	var words: PackedStringArray = request["words"]
	var state := _new_state(request, path)
	var queue: Array = [[path, 0]]
	var scanned := 0
	var recursive: bool = request.get("recursive", false)
	while scanned < queue.size() and (recursive or scanned < int(request["max_folders"])):
		if _cancelled(serial):
			return
		var entry: Array = queue[scanned]
		var folder_path: String = entry[0]
		var dir := DirAccess.open(folder_path)
		scanned += 1
		if dir == null:
			continue
		var children: Array = []
		if _read_dir(dir, folder_path, state, serial, words, true, children):
			return
		_resolve_faces(state, folder_path)
		state["plain_images"].erase(folder_path)
		if recursive or entry[1] < int(request["max_depth"]):
			for child: String in children:
				queue.append([child, entry[1] + 1])
		if not recursive and state["folders"].size() + state["files"].size() >= int(request["max_results"]):
			state["truncated"] = true
			break
	state["truncated"] = state["truncated"] or scanned < queue.size()
	if _cancelled(serial):
		return
	_emit(state, true)


func _scan_playlist(request: Dictionary) -> PackedStringArray:
	var path: String = request["path"]
	if request.get("audio_only", false):
		return _folder_audio(path.get_base_dir())
	if not request["images"]:
		return _folder_media(path.get_base_dir())
	var own_images := PackedStringArray()
	for file: String in _folder_media(path.get_base_dir()):
		if PanoramaFiles.is_image(file):
			own_images.append(file)
	if own_images.size() > 1:
		return own_images
	var root := path.get_base_dir().get_base_dir()
	var dir := DirAccess.open(root)
	if dir == null:
		return _folder_media(path.get_base_dir())
	dir.include_hidden = false
	dir.include_navigational = false
	var folders: Array[String] = []
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	var count := 0
	while not name.is_empty():
		if dir.current_is_dir():
			if not name.begins_with("."):
				folders.append(name)
		elif is_media(name):
			names.append(name)
		count += 1
		if count % 1024 == 0 and _playlist_stale(request["serial"]):
			dir.list_dir_end()
			return PackedStringArray()
		name = dir.get_next()
	dir.list_dir_end()
	folders.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var images := PackedStringArray()
	for file in _sorted_media(root, names):
		if PanoramaFiles.is_image(file):
			images.append(file)
	var lazy := folders.size() > RESOLVE_SETS_LIMIT
	var own_folder := path.get_base_dir()
	var found := false
	for folder_name in folders:
		var folder_path := root.path_join(folder_name)
		if lazy:
			images.append(folder_path + "/")
			found = found or folder_path == own_folder
			continue
		if _playlist_stale(request["serial"]):
			return PackedStringArray()
		for file in _folder_media(folder_path):
			if PanoramaFiles.is_image(file):
				images.append(file)
				found = found or file == path
	if not found and path not in images:
		return _folder_media(own_folder)
	return images


func _folder_audio(path: String) -> PackedStringArray:
	var names: Array[String] = []
	for name in DirAccess.get_files_at(path):
		if name.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS:
			names.append(path.path_join(name))
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(names)


func _sorted_media(path: String, names: Array[String]) -> PackedStringArray:
	var media := PanoramaFiles.visible_images(path, names)
	media.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var files := PackedStringArray()
	for name in media:
		files.append(path.path_join(name))
	return files


func _media_names(path: String, names: PackedStringArray) -> Array[String]:
	var media: Array[String] = []
	for name in names:
		if is_media(name):
			media.append(name)
	return PanoramaFiles.visible_images(path, media)


func _folder_media(path: String) -> PackedStringArray:
	var names: Array[String] = []
	for name in DirAccess.get_files_at(path):
		if is_media(name):
			names.append(name)
	return _sorted_media(path, names)


func folder_cover(path: String) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir == null:
		return {}
	var shown := _media_names(path, dir.get_files())
	if shown.is_empty():
		return {}
	var first := shown[0]
	var tied := false
	for i in range(1, shown.size()):
		var comparison := shown[i].naturalnocasecmp_to(first)
		if comparison < 0:
			first = shown[i]
			tied = false
		elif comparison == 0:
			tied = true
	if tied:
		shown.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		first = shown[0]
	var single := shown.size() == 1
	if single:
		for name in dir.get_directories():
			if not name.begins_with("."):
				single = false
				break
	return {"cover": path.path_join(first), "count": shown.size(), "single": single}


static func format_kind(path: String, info: Dictionary, saved: Variant) -> int:
	var width := float(info.get("width", 0))
	var height := float(info.get("height", 0))
	if path.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS:
		return Settings.LibraryFilter.FLAT_2D
	if PanoramaFiles.is_image(path) and info.get("cube", false):
		return Settings.LibraryFilter.VR_360
	var projection := Settings.ProjectionMode.FLAT
	var stereo := Settings.Stereo.MONO
	if saved is Dictionary:
		projection = int(saved.get("projection", 0))
		stereo = int(saved.get("stereo", 0))
	else:
		var guess := VPXPlayer.guess_format(path, width / height if height > 0.0 else 16.0 / 9.0, info.get("meta", {}))
		projection = guess["projection"]
		stereo = guess["stereo"]
	match projection:
		Settings.ProjectionMode.EQUIRECT_360, Settings.ProjectionMode.EAC, Settings.ProjectionMode.CUBEMAP:
			return Settings.LibraryFilter.VR_360
		Settings.ProjectionMode.EQUIRECT_180, Settings.ProjectionMode.FISHEYE:
			return Settings.LibraryFilter.VR_180
	if PanoramaFiles.is_image(path):
		return Settings.LibraryFilter.PHOTOS
	return Settings.LibraryFilter.FLAT_2D if stereo == Settings.Stereo.MONO else Settings.LibraryFilter.FLAT_3D


static func words_match(text: String, words: PackedStringArray) -> bool:
	var haystack := text.to_lower().replace("_", " ").replace(".", " ")
	for word in words:
		if not haystack.contains(word):
			return false
	return true


func _ordered_playlist(files: PackedStringArray, request: Dictionary) -> PackedStringArray:
	var paths: Array[String] = []
	var keys := {}
	var sort: int = request.get("sort", Sort.NAME)
	var filter: Dictionary = {} if request.get("audio_only", false) else request.get("filter", {})
	for path: String in files:
		if not path.ends_with("/") and not _passes(filter, path):
			continue
		paths.append(path)
		if sort != Sort.NAME:
			var source := path.trim_suffix("/")
			keys[path] = FileAccess.get_modified_time(source) if sort == Sort.DATE else FileAccess.get_size(source)
	_sort(paths, keys, sort != Sort.NAME, false)
	return PackedStringArray(paths)
