extends Node

signal completed(result: Dictionary)

const JOURNAL := "user://rename-transaction.cfg"
const UNDO := "user://rename-undo.cfg"
const Detector := preload("res://scripts/format_detector.gd")
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const MediaTracks := preload("res://scripts/media_tracks.gd")
const SIDECARS := ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup", "smi", "sami"]
const MAX_MOVES := 1024

var player: VPXPlayer
var ui: Control
var busy := false
var recovery_error := ""
var panorama_sets := {}


func _ready() -> void:
	recover()


static func suggested_name(path: String) -> String:
	var base := path.get_file().get_basename()
	var suffix := RegEx.create_from_string("(?i)(?:[_ .-](?:FLAT|180|360|EAC|CUBEMAP|FISHEYE[0-9]{0,3}))?[_ .-](?:MONO|2D|SBS|LR|RL|OU|TB|BT)(?:[_ .-]ALPHA)?$")
	base = suffix.sub(base, "").trim_suffix("_").strip_edges()
	var projection: String = ["FLAT", "360", "180", "FISHEYE%d" % int(round(Settings.fisheye_fov)), "EAC", "CUBEMAP"][Settings.projection]
	var stereo := "MONO"
	if Settings.stereo == Settings.Stereo.SIDE_BY_SIDE:
		stereo = "RL" if Settings.swap_eyes else "SBS"
	elif Settings.stereo == Settings.Stereo.OVER_UNDER:
		stereo = "BT" if Settings.swap_eyes else "OU"
	return "%s_%s_%s%s.%s" % [base, projection, stereo, "_ALPHA" if Settings.alpha_mask == Settings.AlphaMask.PACKED_CORNERS else "", path.get_extension()]


func _is_panorama_set(path: String) -> bool:
	var signature := "%s:%d" % [path, FileAccess.get_modified_time(path.get_base_dir())]
	if not panorama_sets.has(signature):
		if panorama_sets.size() > 32:
			panorama_sets.clear()
		panorama_sets[signature] = not PanoramaFiles.cube_faces(path).is_empty()
	return panorama_sets[signature]


func proposal() -> Dictionary:
	var path := player.current_path
	var reason := unsupported_reason(path)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var name := suggested_name(path)
	var result := validate(path, name)
	result["name"] = name
	if not player.is_image():
		var metadata := Detector.format_from_metadata(player.stream_metadata)
		if (metadata["projection"] >= 0 and metadata["projection"] != Settings.projection) or (metadata["stereo"] >= 0 and (metadata["stereo"] != Settings.stereo or metadata["swap"] != Settings.swap_eyes)):
			result["warning"] = "Embedded format conflicts with this choice. VPX keeps your override; other players may ignore the filename tags."
	return result


func unsupported_reason(path: String) -> String:
	if busy:
		return "A rename is already running"
	if not recovery_error.is_empty():
		return recovery_error
	if not ClassDB.class_exists("VPXFileOps"):
		return "Update the VPX native extension to enable safe renaming"
	if path.is_empty() or not path.is_absolute_path() or path.contains("://") or not FileAccess.file_exists(path):
		return "Choose a local media file"
	if path.begins_with("//") or path.begins_with("/run/user/") or path.begins_with("/run/media/"):
		return "Rename is available for local files only"
	if OS.get_name() == "Linux":
		for line: String in FileAccess.get_file_as_string("/proc/mounts").split("\n"):
			var parts := line.split(" ")
			if parts.size() > 2 and parts[2] in ["cifs", "smb3", "nfs", "nfs4", "fuse.sshfs", "davfs", "fuse.gvfsd-fuse"]:
				var mount: String = parts[1].replace("\\040", " ")
				if path.begins_with(mount.trim_suffix("/") + "/"):
					return "Rename is available for local files only"
	if path.get_extension().to_lower() in ["iso", "zip", "rar", "7z"]:
		return "Disc and archive names cannot be tagged here"
	if player.is_loading():
		return "Wait for this file to finish loading"
	if PanoramaFiles.is_image(path) and _is_panorama_set(path):
		return "Multi-file panorama sets must keep their matching names"
	return ""


static func validate(path: String, name: String) -> Dictionary:
	if name.is_empty() or name != name.get_file() or name.ends_with(".") or name.ends_with(" ") or name.to_utf8_buffer().size() > 240:
		return {"ok": false, "error": "Choose a valid filename up to 240 bytes"}
	for i in name.length():
		if name.unicode_at(i) < 32 or '<>:"/\\|?*'.contains(name[i]):
			return {"ok": false, "error": "Filename contains an unsupported character"}
	var reserved := RegEx.create_from_string("(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\\.|$)")
	if reserved.search(name) != null or name.get_extension().to_lower() != path.get_extension().to_lower():
		return {"ok": false, "error": "Keep the media extension and use a portable filename"}
	var tags := Detector.tags_from_name(name)
	if tags["projection"] != Settings.projection or tags["stereo"] != Settings.stereo or tags["swap"] != (Settings.swap_eyes and Settings.stereo != Settings.Stereo.MONO) or (Settings.projection == Settings.ProjectionMode.FISHEYE and not is_equal_approx(tags["fov"], Settings.fisheye_fov)):
		return {"ok": false, "error": "Conflicting title tags. Edit the proposed name to match the chosen format"}
	var target := path.get_base_dir().path_join(name)
	if target != path and (_exists_exact(target) or DirAccess.dir_exists_absolute(target) or Library.entries.has(target)):
		return {"ok": false, "error": "That filename or saved library entry already exists"}
	return {"ok": true, "target": target, "unchanged": target == path}


func rename_current(name: String) -> Dictionary:
	var from := player.current_path
	var reason := unsupported_reason(from)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var checked := validate(from, name)
	if not checked["ok"] or checked["unchanged"]:
		return checked
	var moves: Array = [{"from": from, "to": checked["target"]}]
	var stem := from.get_file().get_basename()
	var directories := PackedStringArray([from.get_base_dir()])
	for directory: String in DirAccess.get_directories_at(from.get_base_dir()):
		if directory.to_lower() in MediaTracks.SUBTITLE_FOLDERS:
			directories.append(from.get_base_dir().path_join(directory))
	for directory in directories:
		for filename: String in DirAccess.get_files_at(directory):
			var belongs := MediaTracks.matches_stem(filename, stem)
			if belongs and filename.get_extension().to_lower() in SIDECARS:
				moves.append({"from": directory.path_join(filename), "to": directory.path_join(str(checked["target"]).get_file().get_basename() + filename.substr(stem.length()))})
	for move: Dictionary in moves:
		if _exists_exact(move["to"]) or DirAccess.dir_exists_absolute(move["to"]):
			return {"ok": false, "error": "A target or subtitle filename already exists"}
		move["size"] = FileAccess.get_size(move["from"])
		move["mtime"] = FileAccess.get_modified_time(move["from"])
	var subtitles := PackedStringArray()
	for track: Dictionary in MediaTracks.find_external(from):
		subtitles.append(track["path"])
	return await _execute(moves, true, subtitles)


func undo() -> Dictionary:
	if busy:
		return {"ok": false, "error": "A rename is already running"}
	var data := _read(UNDO)
	if not _valid_journal(data):
		return {"ok": false, "error": "No valid rename to undo"}
	var moves: Array = []
	for move: Dictionary in data.get("moves", []):
		if not FileAccess.file_exists(move["to"]) or FileAccess.get_size(move["to"]) != move["size"] or FileAccess.get_modified_time(move["to"]) != move["mtime"]:
			return {"ok": false, "error": "Renamed file changed or disappeared; undo stopped"}
		moves.append({"from": move["to"], "to": move["from"], "size": move["size"], "mtime": move["mtime"]})
	var result := await _execute(moves, false)
	if result["ok"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UNDO))
	return result


func _execute(moves: Array, save_undo := true, subtitles := PackedStringArray()) -> Dictionary:
	if not _valid_journal({"phase": "moving", "moves": moves}):
		return {"ok": false, "error": "Invalid rename operation"}
	for move: Dictionary in moves:
		if _exists_exact(move["to"]) or DirAccess.dir_exists_absolute(move["to"]) or Library.entries.has(move["to"]):
			return {"ok": false, "error": "A target filename or saved library entry already exists"}
	busy = true
	var steps: Array = []
	for move: Dictionary in moves:
		if OS.get_name() == "Windows" and str(move["from"]).to_lower() == str(move["to"]).to_lower():
			var temporary: String = str(move["from"]).get_base_dir().path_join(".vpx-rename-%d-%d.tmp" % [Time.get_ticks_usec(), steps.size()])
			steps.append({"from": move["from"], "to": temporary, "size": move["size"], "mtime": move["mtime"]})
			steps.append({"from": temporary, "to": move["to"], "size": move["size"], "mtime": move["mtime"]})
		else:
			steps.append(move.duplicate())
	player.remember_position()
	var before_files := {}
	for move: Dictionary in moves:
		before_files[move["from"]] = Library.entries[move["from"]].duplicate(true) if Library.entries.has(move["from"]) else null
	var journal := {"phase": "moving", "moves": moves, "steps": steps, "before": {"files": before_files, "last": Settings.last_file, "format_path": Settings.format_path}}
	journal["subtitles"] = Array(subtitles)
	if not _valid_journal(journal):
		busy = false
		return {"ok": false, "error": "Rename metadata exceeds supported limits"}
	if not _write(JOURNAL, journal):
		busy = false
		return {"ok": false, "error": "Could not save rename recovery data"}
	var old_path: String = moves[0]["from"]
	var active: bool = player.current_path == old_path
	var position := player.stream_position
	var was_paused := player.paused
	var was_image := player.is_image()
	var visual_format := {}
	for key: String in Settings.FORMAT_PROPERTIES:
		visual_format[key] = Settings.get(key)
	ui.previews.clear()
	MediaInfo.invalidate(old_path)
	if active and not was_image:
		player.remember_position()
		player.open_serial += 1
		player.replacing_stream = true
		player.stop()
		player.playback = null
		player.stream = null
		player.replacing_stream = false
		await get_tree().process_frame
	active = active and player.current_path == old_path
	var resume_serial := player.open_serial
	var moved: Array = []
	var failure := ""
	for move: Dictionary in steps:
		if not FileAccess.file_exists(move["from"]) or FileAccess.get_size(move["from"]) != move["size"] or FileAccess.get_modified_time(move["from"]) != move["mtime"]:
			failure = "Source changed while renaming; operation stopped"
			break
		var result := _move(move["from"], move["to"])
		if result != OK:
			failure = "Could not rename %s: %s" % [str(move["from"]).get_file(), error_string(result)]
			break
		moved.append(move)
	if failure.is_empty():
		journal["phase"] = "moved"
		if not _write(JOURNAL, journal):
			failure = "Could not record renamed files"
	if failure.is_empty():
		_apply_paths(moves, subtitles)
		if active:
			Library.set_pref(moves[0]["to"], "format", visual_format)
		if Library.save() != OK or Settings.flush() != OK:
			failure = "Could not save renamed library data"
	if not failure.is_empty():
		var rolled_back := _rollback(moved) and _originals_present(moves)
		var restored := _restore_before(journal) if rolled_back else false
		if rolled_back and restored:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(JOURNAL))
		else:
			journal["phase"] = "rollback"
			_write(JOURNAL, journal)
			recovery_error = "Rename recovery is pending. Restore write access and restart VPX before renaming again"
			failure += ". " + recovery_error
		if active and not was_image and rolled_back and player.open_serial == resume_serial and player.current_path == old_path:
			await player.open(old_path, {"paused": was_paused})
			player.seek_to(position)
		busy = false
		return {"ok": false, "error": failure}
	var target: String = moves[0]["to"]
	active = active and player.current_path == old_path and player.open_serial == resume_serial
	_rekey_live(moves)
	if active:
		Settings.format_path = target
		if not was_image:
			await player.open(target, {"paused": was_paused})
			player.seek_to(position)
			player.paused = was_paused
		else:
			player.opened.emit(target)
	journal["phase"] = "committed"
	if _write(JOURNAL, journal):
		if not save_undo or _write(UNDO, journal):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(JOURNAL))
	ui.refresh_directory()
	busy = false
	var result := {"ok": true, "target": target, "name": target.get_file()}
	completed.emit(result)
	return result


func _rekey_live(moves: Array) -> void:
	var mapping := _mapping(moves)
	player.current_path = mapping.get(player.current_path, player.current_path)
	player.music_path = mapping.get(player.music_path, player.music_path)
	player.loading_path = mapping.get(player.loading_path, player.loading_path)
	player.image_path = mapping.get(player.image_path, player.image_path)
	player.image_file_info = Library._replace_paths(player.image_file_info, mapping)
	player.loading_file_info = Library._replace_paths(player.loading_file_info, mapping)
	for state: Dictionary in [player.load_state, player.playback_state]:
		if state.has("path"):
			state["path"] = mapping.get(state["path"], state["path"])
	player.prefetch_images(PackedStringArray())
	ui.playlist = _rekey_list(ui.playlist, mapping)
	ui.music_playlist = _rekey_list(ui.music_playlist, mapping)
	ui.listing = _rekey_list(ui.listing, mapping)
	ui.playlist_index = ui.scanner.index_of(ui.playlist)
	ui.music_playlist_index = ui.scanner.index_of(ui.music_playlist)
	ui.shuffle.rekey(mapping)
	ui.music_shuffle.rekey(mapping)
	player.tracks.path = mapping.get(player.tracks.path, player.tracks.path)
	for track: Dictionary in player.tracks.subtitle_tracks:
		if track.has("path"):
			track["path"] = mapping.get(track["path"], track["path"])
	MediaInfo.request(player.current_path, true)


static func _rekey_list(paths: PackedStringArray, mapping: Dictionary) -> PackedStringArray:
	var result := paths.duplicate()
	for i in result.size():
		result[i] = mapping.get(result[i], result[i])
	return result


func _apply_paths(moves: Array, subtitles := PackedStringArray()) -> void:
	var mapping := _mapping(moves)
	Library.rekey_paths(mapping)
	if not subtitles.is_empty():
		var path: String = moves[0]["to"]
		var saved: Variant = Library.get_pref(path, "subtitle_files", [])
		var files: Array = saved.duplicate() if saved is Array else []
		for source: String in subtitles:
			var target: String = mapping.get(source, source)
			if target not in files:
				files.append(target)
		Library.set_pref(path, "subtitle_files", files)
	Settings.last_file = mapping.get(Settings.last_file, Settings.last_file)
	Settings.format_path = mapping.get(Settings.format_path, Settings.format_path)
	Settings.save_config()


static func _mapping(moves: Array) -> Dictionary:
	var mapping := {}
	for move: Dictionary in moves:
		mapping[move["from"]] = move["to"]
	return mapping


static func _valid_journal(data: Dictionary) -> bool:
	if data.get("phase") not in ["moving", "moved", "committed", "rollback"] or not data.get("moves") is Array or data["moves"].is_empty() or data["moves"].size() > MAX_MOVES:
		return false
	if data.has("subtitles"):
		if not data["subtitles"] is Array or data["subtitles"].size() > MAX_MOVES:
			return false
		for path: Variant in data["subtitles"]:
			if not path is String or not path.is_absolute_path() or path.contains("://"):
				return false
	var used := {}
	for move: Variant in data["moves"]:
		if not move is Dictionary or not move.get("from") is String or not move.get("to") is String or not move.get("size") is int or not move.get("mtime") is int:
			return false
		var from: String = move["from"]
		var to: String = move["to"]
		if not from.is_absolute_path() or from.contains("://") or from.get_base_dir() != to.get_base_dir() or from == to or used.has(from) or used.has(to):
			return false
		used[from] = true
		used[to] = true
	if data.has("before"):
		var before: Variant = data["before"]
		if not before is Dictionary or not before.get("files") is Dictionary or not before.get("last") is String or not before.get("format_path") is String or before["files"].size() != data["moves"].size():
			return false
		for move: Dictionary in data["moves"]:
			if not before["files"].has(move["from"]) or not (before["files"][move["from"]] == null or before["files"][move["from"]] is Dictionary):
				return false
		if not load("res://scripts/settings_backup.gd")._valid_value(before):
			return false
	if data.has("steps"):
		if not data["steps"] is Array or data["steps"].is_empty() or data["steps"].size() > data["moves"].size() * 2:
			return false
		var cursor := 0
		for move: Dictionary in data["moves"]:
			if cursor >= data["steps"].size():
				return false
			var step: Variant = data["steps"][cursor]
			if not step is Dictionary or step.get("from") != move["from"] or step.get("size") != move["size"] or step.get("mtime") != move["mtime"] or not step.get("to") is String:
				return false
			cursor += 1
			if step["to"] == move["to"]:
				continue
			var temporary: String = step["to"]
			if str(move["from"]).to_lower() != str(move["to"]).to_lower() or temporary.get_base_dir() != str(move["from"]).get_base_dir() or not temporary.get_file().begins_with(".vpx-rename-") or not temporary.ends_with(".tmp") or cursor >= data["steps"].size():
				return false
			var final: Variant = data["steps"][cursor]
			if not final is Dictionary or final.get("from") != temporary or final.get("to") != move["to"] or final.get("size") != move["size"] or final.get("mtime") != move["mtime"]:
				return false
			cursor += 1
		if cursor != data["steps"].size():
			return false
	return true


static func _originals_present(moves: Array) -> bool:
	for move: Dictionary in moves:
		if not _exists_exact(move["from"]) or _exists_exact(move["to"]):
			return false
	return true


func _restore_before(data: Dictionary) -> bool:
	if data.has("before"):
		for move: Dictionary in data["moves"]:
			Library.entries.erase(move["to"])
			var entry: Variant = data["before"]["files"][move["from"]]
			if entry == null:
				Library.entries.erase(move["from"])
			else:
				Library.entries[move["from"]] = entry.duplicate(true)
		Library.favorites.clear()
		Library._index_favorites()
		Library._mark_dirty()
		Settings.last_file = data["before"]["last"]
		Settings.format_path = data["before"]["format_path"]
		Settings.save_config()
	else:
		var reverse: Array = []
		for move: Dictionary in data["moves"]:
			reverse.append({"from": move["to"], "to": move["from"]})
		_apply_paths(reverse)
	var saved := Library.save()
	var settings_saved := Settings.flush()
	return saved == OK and settings_saved == OK


func recover() -> void:
	recovery_error = ""
	if not FileAccess.file_exists(JOURNAL):
		return
	var data := _read(JOURNAL)
	if not _valid_journal(data) or not ClassDB.class_exists("VPXFileOps"):
		recovery_error = "Could not read rename recovery data"
		return
	if _originals_present(data["moves"]):
		if not _restore_before(data):
			recovery_error = "Could not restore renamed library data"
			return
	elif data.get("phase") in ["moved", "committed"]:
		for move: Dictionary in data["moves"]:
			if not _exists_exact(move["to"]) or _exists_exact(move["from"]):
				recovery_error = "Rename recovery found a missing file or collision"
				return
			if data.has("before") and not Library.entries.has(move["from"]) and not Library.entries.has(move["to"]) and data["before"]["files"][move["from"]] is Dictionary:
				Library.entries[move["from"]] = data["before"]["files"][move["from"]].duplicate(true)
		_apply_paths(data["moves"], PackedStringArray(data.get("subtitles", [])))
		if Library.save() != OK or Settings.flush() != OK or not _write(UNDO, data):
			recovery_error = "Could not save recovered rename"
			return
	elif not _rollback(data.get("steps", data["moves"])) or not _originals_present(data["moves"]) or not _restore_before(data):
		recovery_error = "Could not roll back interrupted rename"
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(JOURNAL))

static func _rollback(moves: Array) -> bool:
	var ok := true
	for i in range(moves.size() - 1, -1, -1):
		var move: Dictionary = moves[i]
		if _exists_exact(move["to"]):
			if FileAccess.get_size(move["to"]) != move["size"] or FileAccess.get_modified_time(move["to"]) != move["mtime"]:
				ok = false
				continue
			if _exists_exact(move["from"]) or _move(move["to"], move["from"]) != OK:
				ok = false
	return ok


static func _exists_exact(path: String) -> bool:
	if OS.get_name() != "Windows":
		return FileAccess.file_exists(path)
	return path.get_file() in DirAccess.get_files_at(path.get_base_dir())


static func _move(from: String, to: String) -> Error:
	if not ClassDB.class_exists("VPXFileOps"):
		return ERR_UNAVAILABLE
	var ops = ClassDB.instantiate("VPXFileOps")
	return ops.rename_no_replace(from, to)


static func _write(path: String, data: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.set_value("rename", "data", data)
	if config.save(path + ".tmp") != OK:
		return false
	if FileAccess.get_size(path + ".tmp") > 1048576:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK


static func _read(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or FileAccess.get_size(path) > 1048576 or config.load(path) != OK:
		return {}
	var data: Variant = config.get_value("rename", "data", {})
	return data if data is Dictionary else {}
