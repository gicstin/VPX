extends Node

signal changed

const SUBTITLE_EXTENSIONS := ["srt", "ass", "ssa", "vtt", "sub", "smi", "sami", "sup"]
const SUBTITLE_ARCHIVE_EXTENSIONS := ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
const SUBTITLE_FOLDERS := ["subs", "subtitles", "sub", "subtitle"]
const FORCED_TAGS := ["forced", "foreign"]
const SDH_TAGS := ["sdh", "hi", "cc"]
const CODEC_NAMES := {"subrip": "SRT", "srt": "SRT", "ass": "ASS", "ssa": "SSA", "webvtt": "VTT", "vtt": "VTT", "mov_text": "Text", "hdmv_pgs_subtitle": "PGS", "sup": "PGS", "dvd_subtitle": "VobSub", "dvb_subtitle": "DVB", "microdvd": "MicroDVD", "sub": "SUB", "sami": "SAMI", "smi": "SAMI", "eac3": "E-AC3", "truehd": "TrueHD", "dts": "DTS", "ac3": "AC3", "aac": "AAC", "opus": "Opus", "vorbis": "Vorbis", "flac": "FLAC", "mp3": "MP3"}
const CHANNEL_NAMES := {1: "Mono", 2: "Stereo", 6: "5.1", 7: "6.1", 8: "7.1"}
const Languages := preload("res://scripts/languages.gd")

var playback: FFmpegVideoStreamPlayback
var path := ""
var audio_tracks: Array = []
var subtitle_tracks: Array = []
var audio_choice := -1
var subtitle_choice := -1
var source: VPXSubtitles
var restoring := false
var subtitle_serial := 0
var subtitle_tasks: Array[int] = []
var applied_audio_delay := 0.0
var applied_subtitle_delay := 0.0


func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)


func _process(_delta: float) -> void:
	for task in subtitle_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			subtitle_tasks.erase(task)


func reset() -> void:
	subtitle_serial += 1
	playback = null
	path = ""
	audio_tracks = []
	subtitle_tracks = []
	audio_choice = -1
	subtitle_choice = -1
	source = null
	changed.emit()


func load_for(file_path: String, video_playback: FFmpegVideoStreamPlayback, external: Variant = null) -> void:
	restoring = true
	playback = video_playback
	path = file_path
	audio_tracks = playback.get_audio_tracks() if playback != null else []
	subtitle_tracks = []
	if playback != null:
		for track in playback.get_subtitle_tracks():
			track["kind"] = "embedded"
			subtitle_tracks.append(track)
	if external is Array:
		subtitle_tracks.append_array(external)
	else:
		subtitle_tracks.append_array(find_external(file_path))
		var imported: Variant = Library.get_pref(path, "subtitle_files", [])
		if imported is Array:
			for external_path in imported:
				if FileAccess.file_exists(str(external_path)) and not _has_external_path(str(external_path)):
					subtitle_tracks.append(_external_track(str(external_path), str(external_path).get_file()))
	audio_choice = playback.get_audio_track() if playback != null else -1
	subtitle_choice = -1
	source = null
	Settings.apply("audio_delay", float(Library.get_pref(path, "audio_delay", 0.0)))
	Settings.apply("subtitle_delay", float(Library.get_pref(path, "subtitle_delay", 0.0)))
	_apply_delays()
	_restore_audio()
	_restore_subtitle()
	restoring = false
	Log.info("tracks: %d audio (using %s), %d subtitles (using %s)" % [audio_tracks.size(), audio_label(audio_choice), subtitle_tracks.size(), subtitle_label(subtitle_choice)])
	changed.emit()


func add_external_file(file_path: String, select_after := true) -> bool:
	if file_path.get_extension().to_lower() not in SUBTITLE_EXTENSIONS:
		return false
	var track := _external_track(file_path, file_path.get_file())
	if not _has_external_path(file_path):
		subtitle_tracks.append(track)
		_remember_external_path(file_path)
		changed.emit()
	var index := _track_index(file_path)
	if index >= 0 and select_after:
		select_subtitle(index)
	return index >= 0


func add_archive(archive_path: String) -> Dictionary:
	var extension := archive_path.get_extension().to_lower()
	if extension == "zip":
		return _add_zip(archive_path)
	return _add_tool_archive(archive_path)


func _add_zip(archive_path: String) -> Dictionary:
	var zip := ZIPReader.new()
	var error := zip.open(archive_path)
	if error != OK:
		return {"ok": false, "message": "Cannot open ZIP archive (%s)" % error_string(error)}
	var added := 0
	var first_added := ""
	for member in zip.get_files():
		if member.ends_with("/") or member.get_extension().to_lower() not in SUBTITLE_EXTENSIONS:
			continue
		var bytes := zip.read_file(member)
		if bytes.is_empty():
			continue
		var cached := _cache_archive_member(archive_path, member, bytes)
		if add_external_file(cached, false):
			added += 1
			if first_added.is_empty():
				first_added = cached
	zip.close()
	if not first_added.is_empty():
		select_subtitle(_track_index(first_added))
	return {"ok": added > 0, "message": "%d subtitle file(s) added" % added if added > 0 else "No supported subtitle files found in ZIP"}


func _add_tool_archive(archive_path: String) -> Dictionary:
	var tool := "7z" if Shell.has_command("7z") else ("7zz" if Shell.has_command("7zz") else ("unrar" if Shell.has_command("unrar") else ""))
	if tool.is_empty():
		return {"ok": false, "message": "This archive needs 7-Zip or unrar installed. ZIP works without them."}
	var listing: Array = []
	var is_unrar := tool == "unrar"
	if OS.execute(tool, ["lb", archive_path] if is_unrar else ["l", "-slt", archive_path], listing, true) != 0 or listing.is_empty():
		return {"ok": false, "message": "Cannot list archive contents"}
	var members := PackedStringArray()
	var text := str(listing[0])
	for line in text.split("\n"):
		var member := line.strip_edges()
		if not is_unrar:
			if not member.begins_with("Path = "):
				continue
			member = member.trim_prefix("Path = ").strip_edges()
		if member == archive_path or member.ends_with("/") or member.get_extension().to_lower() not in SUBTITLE_EXTENSIONS:
			continue
		members.append(member)
	if members.is_empty():
		return {"ok": false, "message": "No supported subtitle files found in archive"}
	var destination := ProjectSettings.globalize_path("user://cache/subtitles/%s" % archive_path.md5_text())
	DirAccess.make_dir_recursive_absolute(destination)
	var args := PackedStringArray(["e", "-o+", archive_path]) if is_unrar else PackedStringArray(["e", "-y", "-o" + destination, archive_path])
	args.append_array(members)
	if is_unrar:
		args.append(destination.path_join(""))
	var output: Array = []
	if OS.execute(tool, args, output, true) != 0:
		return {"ok": false, "message": "Could not extract subtitle files from archive"}
	var added := 0
	var first_added := ""
	for member in members:
		var extracted := destination.path_join(member.get_file())
		if FileAccess.file_exists(extracted) and add_external_file(extracted, false):
			added += 1
			if first_added.is_empty():
				first_added = extracted
	if not first_added.is_empty():
		select_subtitle(_track_index(first_added))
	return {"ok": added > 0, "message": "%d subtitle file(s) added" % added if added > 0 else "Archive contained no readable subtitle files"}


func _cache_archive_member(archive_path: String, member: String, bytes: PackedByteArray) -> String:
	var folder := "user://cache/subtitles/%s" % archive_path.md5_text()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder.path_join("%s_%s" % [member.md5_text(), member.get_file()])
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return target


func _has_external_path(file_path: String) -> bool:
	return _track_index(file_path) >= 0


func _track_index(file_path: String) -> int:
	for i in subtitle_tracks.size():
		if subtitle_tracks[i].get("kind", "") == "external" and subtitle_tracks[i].get("path", "") == file_path:
			return i
	return -1


func _remember_external_path(file_path: String) -> void:
	if path.is_empty():
		return
	var imported: Variant = Library.get_pref(path, "subtitle_files", [])
	var files: Array = imported.duplicate() if imported is Array else []
	if file_path not in files:
		files.append(file_path)
		Library.set_pref(path, "subtitle_files", files)


func _restore_audio() -> void:
	var saved: Variant = Library.get_pref(path, "audio_track")
	if saved != null and (int(saved) == -1 or _audio_position(int(saved)) >= 0):
		select_audio(int(saved), false)
		return
	if Settings.audio_language <= 0:
		return
	var language: int = Settings.audio_language - 1
	var best := -1
	for track in audio_tracks:
		if Languages.matches(track["language"], language) and (best < 0 or not track["commentary"]):
			best = track["index"]
			if not track["commentary"]:
				break
	if best >= 0:
		select_audio(best, false)


func _restore_subtitle() -> void:
	var saved: Variant = Library.get_pref(path, "subtitle")
	if saved is String and saved == "off":
		select_subtitle(-1, false)
		return
	if saved is Dictionary:
		for i in subtitle_tracks.size():
			var track: Dictionary = subtitle_tracks[i]
			var matches: bool
			if track["kind"] == "embedded":
				matches = int(saved.get("index", -1)) >= 0 and track.get("index", -1) == int(saved["index"])
			else:
				matches = not str(saved.get("path", "")).is_empty() and track.get("path", "") == saved["path"]
			if track["kind"] == saved.get("kind") and matches:
				select_subtitle(i, false)
				return
	select_subtitle(auto_subtitle(), false)


func auto_subtitle() -> int:
	var preferred: int = Settings.subtitle_language
	var audio_language := ""
	var position := _audio_position(audio_choice)
	if position >= 0:
		audio_language = audio_tracks[position]["language"]
	var foreign := not audio_language in ["", "und"] and not Languages.matches(audio_language, preferred)
	var regular := -1
	var hearing := -1
	var forced := -1
	for i in subtitle_tracks.size():
		var track: Dictionary = subtitle_tracks[i]
		if not Languages.matches(track["language"], preferred):
			continue
		if track["forced"]:
			forced = i if forced < 0 else forced
		elif track["hearing_impaired"]:
			hearing = i if hearing < 0 else hearing
		elif regular < 0:
			regular = i
	var full := regular if regular >= 0 else hearing
	match Settings.subtitle_auto:
		Settings.SubtitleAuto.ALWAYS:
			return full if full >= 0 else forced
		Settings.SubtitleAuto.FOREIGN:
			return full if foreign and full >= 0 else forced
	return forced


func select_audio(stream_index: int, remember := true) -> void:
	audio_choice = stream_index
	if playback != null:
		playback.set_audio_track(stream_index)
	if remember and not path.is_empty():
		Library.set_pref(path, "audio_track", stream_index)
		Log.info("audio track %s" % audio_label(stream_index))
	changed.emit()


func select_subtitle(choice: int, remember := true) -> void:
	subtitle_serial += 1
	subtitle_choice = choice if choice >= 0 and choice < subtitle_tracks.size() else -1
	source = null
	var track: Dictionary = subtitle_tracks[subtitle_choice] if subtitle_choice >= 0 else {}
	if playback != null:
		playback.set_subtitle_track(track["index"] if track.get("kind", "") == "embedded" else -1)
	if track.get("kind", "") == "embedded" and playback != null:
		source = playback.get_subtitles()
		if remember:
			var player := get_parent() as VideoStreamPlayer
			player.stream_position = player.stream_position
	elif track.get("kind", "") == "external":
		_load_external(track["path"], subtitle_serial)
	if remember and not path.is_empty():
		if track.is_empty():
			Library.set_pref(path, "subtitle", "off")
		else:
			Library.set_pref(path, "subtitle", {"kind": track["kind"], "index": track.get("index", -1), "path": track.get("path", "")})
		Log.info("subtitles %s" % subtitle_label(subtitle_choice))
	changed.emit()


func cycle_subtitle(direction: int) -> void:
	select_subtitle(wrapi(subtitle_choice + 1 + direction, 0, subtitle_tracks.size() + 1) - 1)


func cycle_audio(direction: int) -> void:
	if audio_tracks.is_empty():
		return
	var position := wrapi(_audio_position(audio_choice) + direction, 0, audio_tracks.size())
	select_audio(audio_tracks[position]["index"])


func active_cues() -> Array:
	if source == null or playback == null:
		return []
	var player := get_parent() as VideoStreamPlayer
	return source.get_active((player.stream_position - Settings.subtitle_delay) * 1000.0)


func _audio_position(stream_index: int) -> int:
	for i in audio_tracks.size():
		if audio_tracks[i]["index"] == stream_index:
			return i
	return -1


func audio_label(stream_index: int) -> String:
	var position := _audio_position(stream_index)
	if position < 0:
		return "Off" if stream_index == -1 and not audio_tracks.is_empty() else "None"
	var track: Dictionary = audio_tracks[position]
	var parts := PackedStringArray()
	var language := Languages.display_name(track["language"])
	parts.append(language if not language.is_empty() else "Track %d" % (position + 1))
	parts.append(codec_name(track["codec"]))
	parts.append(CHANNEL_NAMES.get(int(track["channels"]), "%d ch" % int(track["channels"])))
	if track["commentary"]:
		parts.append("Commentary")
	if not str(track["title"]).is_empty() and str(track["title"]).to_lower() != language.to_lower():
		parts.append(track["title"])
	return " · ".join(parts)


func subtitle_label(choice: int) -> String:
	if choice < 0 or choice >= subtitle_tracks.size():
		return "Off"
	var track: Dictionary = subtitle_tracks[choice]
	var parts := PackedStringArray()
	var language := Languages.display_name(track["language"])
	parts.append(language if not language.is_empty() else "Track %d" % (choice + 1))
	if track["forced"]:
		parts.append("Forced")
	if track["hearing_impaired"]:
		parts.append("SDH")
	var title := str(track["title"])
	if not title.is_empty() and title.to_lower() != language.to_lower() and track["kind"] == "embedded":
		parts.append(title)
	parts.append(codec_name(track["codec"]) + (" file" if track["kind"] == "external" else ""))
	return " · ".join(parts)


static func codec_name(codec: String) -> String:
	return CODEC_NAMES.get(codec.to_lower(), codec.to_upper())


func _on_settings_changed() -> void:
	if not is_equal_approx(applied_audio_delay, Settings.audio_delay) or not is_equal_approx(applied_subtitle_delay, Settings.subtitle_delay):
		_apply_delays()
		if not restoring and not path.is_empty():
			Library.set_pref(path, "audio_delay", Settings.audio_delay)
			Library.set_pref(path, "subtitle_delay", Settings.subtitle_delay)


func _load_external(file_path: String, serial: int) -> void:
	var loaded := VPXSubtitles.new()
	var task := WorkerThreadPool.add_task(func() -> void: loaded.load_file(file_path))
	var deadline := Time.get_ticks_msec() + 15000
	while not WorkerThreadPool.is_task_completed(task):
		if serial != subtitle_serial or Time.get_ticks_msec() >= deadline:
			subtitle_tasks.append(task)
			return
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if serial != subtitle_serial:
		return
	if loaded.get_error().is_empty():
		source = loaded
	else:
		Log.warn("subtitle file %s: %s" % [file_path.get_file(), loaded.get_error()])
	changed.emit()


func _apply_delays() -> void:
	applied_audio_delay = Settings.audio_delay
	applied_subtitle_delay = Settings.subtitle_delay
	if playback != null:
		playback.set_audio_delay(Settings.audio_delay * 1000.0)


static func matches_stem(filename: String, stem: String) -> bool:
	var base := filename.get_basename().to_lower()
	var prefix := stem.to_lower()
	if base == prefix:
		return true
	for separator in [".", "_", "-", " "]:
		if base.begins_with(prefix + separator):
			return true
	return false


static func find_external(video_path: String) -> Array:
	var folder := video_path.get_base_dir()
	var stem := video_path.get_file().get_basename()
	var found: Array = []
	if video_path.contains("://"):
		return found
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in SUBTITLE_EXTENSIONS and matches_stem(file, stem):
			found.append(_external_track(folder.path_join(file), file.substr(stem.length())))
	for sub in DirAccess.get_directories_at(folder):
		if sub.to_lower() not in SUBTITLE_FOLDERS:
			continue
		var sub_path := folder.path_join(sub)
		var nested := sub_path.path_join(stem)
		for dir in [sub_path, nested]:
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for file in DirAccess.get_files_at(dir):
				if file.get_extension().to_lower() not in SUBTITLE_EXTENSIONS:
					continue
				var in_nested: bool = dir == nested
				var matches := matches_stem(file, stem)
				if in_nested or matches:
					found.append(_external_track(dir.path_join(file), file.substr(stem.length()) if matches else file))
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Languages.display_name(a["language"]) + a["path"] < Languages.display_name(b["language"]) + b["path"])
	return found


static func _external_track(file_path: String, tail: String) -> Dictionary:
	var tokens := tail.get_basename().to_lower().replace("_", ".").replace("-", ".").replace(" ", ".").split(".", false)
	var language := ""
	var forced := false
	var hearing := false
	for token in tokens:
		if token in FORCED_TAGS:
			forced = true
		elif token in SDH_TAGS:
			hearing = true
		elif language.is_empty() and Languages.index_of(token) >= 0:
			language = token
	return {
		"kind": "external", "path": file_path, "language": language, "title": file_path.get_file(),
		"codec": file_path.get_extension().to_lower(), "forced": forced, "hearing_impaired": hearing, "default": false, "bitmap": file_path.get_extension().to_lower() == "sup",
	}
