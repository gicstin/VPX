class_name DiscImage

static func is_sacd(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return false
	var data := file.get_buffer(mini(file.get_length(), 4 * 1024 * 1024))
	for offset in range(data.size() - 7):
		if data[offset] == 83 and data[offset + 1] == 65 and data[offset + 2] == 67 and data[offset + 3] == 68 \
				and data[offset + 4] == 84 and data[offset + 5] == 101 and data[offset + 6] == 120 and data[offset + 7] == 116:
			return true
	return false


static func sacd_info(path: String) -> Dictionary:
	if not ClassDB.class_has_method("FFmpegVideoStream", "get_sacd_info"):
		return {"ok": false, "error": "SACD playback support is missing"}
	var result: Variant = ClassDB.class_call_static("FFmpegVideoStream", "get_sacd_info", path)
	return result if result is Dictionary else {"ok": false, "error": "Could not read SACD tracks"}


static func sacd_track_uri(iso_path: String, vfs_path: String, title: String) -> String:
	return "sacd://%s/%s/%s" % [iso_path.to_utf8_buffer().hex_encode(), vfs_path.to_utf8_buffer().hex_encode(), title]


static func mount(path: String) -> Dictionary:
	match OS.get_name():
		"Windows":
			return _mount_windows(path)
		"Linux":
			return _mount_linux(path)
		"macOS":
			return _mount_macos(path)
	return {"ok": false, "error": "ISO mounting is not supported on this system"}


static func _mount_windows(path: String) -> Dictionary:
	var script_path := ProjectSettings.globalize_path("user://cache/mount_iso.ps1")
	DirAccess.make_dir_recursive_absolute(script_path.get_base_dir())
	var script := FileAccess.open(script_path, FileAccess.WRITE)
	if script == null:
		return {"ok": false, "error": "Could not create the ISO mount helper"}
	script.store_string("$ErrorActionPreference = 'Stop'\n$image = $args[0]\nMount-DiskImage -ImagePath $image | Out-Null\n$volume = Get-DiskImage -ImagePath $image | Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -First 1 -ExpandProperty DriveLetter\nif ($volume) { Write-Output ($volume + ':/') }\n")
	script.close()
	var output: Array = []
	var result := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script_path, path], output, true)
	if result != 0 or output.is_empty():
		return {"ok": false, "error": "Windows could not mount this ISO image"}
	var root := str(output[0]).strip_edges()
	if root.is_empty():
		return {"ok": false, "error": "Mounted ISO has no accessible drive letter"}
	return {"ok": true, "path": root}


static func _mount_linux(path: String) -> Dictionary:
	var output: Array = []
	if OS.execute("udisksctl", ["loop-setup", "--read-only", "-f", path], output, true) != 0 or output.is_empty():
		return {"ok": false, "error": "Could not create a read-only loop device for this ISO"}
	var match_result := RegEx.create_from_string("(/dev/loop[0-9]+)").search(str(output[0]))
	if match_result == null:
		return {"ok": false, "error": "Could not find the mounted ISO device"}
	var device := match_result.get_string(1)
	output.clear()
	if OS.execute("udisksctl", ["mount", "-b", device], output, true) != 0 or output.is_empty():
		return {"ok": false, "error": "Could not mount this ISO image"}
	match_result = RegEx.create_from_string(" at (/.+)\\.$").search(str(output[0]).strip_edges())
	if match_result == null:
		return {"ok": false, "error": "Could not find the mounted ISO folder"}
	return {"ok": true, "path": match_result.get_string(1)}


static func _mount_macos(path: String) -> Dictionary:
	var mount_path := ProjectSettings.globalize_path("user://mounts/iso_%s" % path.md5_text())
	DirAccess.make_dir_recursive_absolute(mount_path)
	var output: Array = []
	if OS.execute("hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount_path, path], output, true) != 0:
		return {"ok": false, "error": "Could not mount this ISO image"}
	return {"ok": true, "path": mount_path}
