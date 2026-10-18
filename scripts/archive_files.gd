class_name ArchiveFiles

const ARCHIVE_EXTENSIONS := ["zip", "cbz"]


static func media_members(path: String) -> PackedStringArray:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return PackedStringArray()
	var extensions := VPXPlayer.AUDIO_EXTENSIONS + ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ts", "m2ts", "vob", "wmv", "flv", "mpg", "mpeg"]
	var members := PackedStringArray()
	for member in reader.get_files():
		if member.ends_with("/"):
			continue
		if member.get_extension().to_lower() in extensions:
			members.append(member)
	reader.close()
	members.sort()
	return members


static func stream_uri(archive_path: String, member: String) -> String:
	var absolute_path := ProjectSettings.globalize_path(archive_path)
	return "vpxzip://%s/%s/%s" % [absolute_path.to_utf8_buffer().hex_encode(), member.to_utf8_buffer().hex_encode(), member.get_file().uri_encode()]
