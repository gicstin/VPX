class_name DiscImage
extends Node

const BackgroundTask := preload("res://scripts/background_task.gd")
const MOUNT_TIMEOUT := 30.0

var task: Node
var cancelled := false
var deadline := 0


func inspect(path: String) -> Dictionary:
	task = BackgroundTask.start(_inspect.bind(path))
	var result: Dictionary = await task.completed
	task = null
	return result


static func _inspect(token: RefCounted, path: String) -> Dictionary:
	var sacd := is_sacd(path, token)
	if token.is_cancelled():
		return {"ok": false, "cancelled": true}
	return {"ok": true, "is_sacd": sacd, "info": sacd_info(path)}


func cancel() -> void:
	cancelled = true
	if is_instance_valid(task):
		task.cancel()


func _exit_tree() -> void:
	cancel()


static func is_sacd(path: String, token: RefCounted = null) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return false
	var data := file.get_buffer(mini(file.get_length(), 4 * 1024 * 1024))
	for offset in range(data.size() - 7):
		if offset % 4096 == 0 and token != null and token.is_cancelled():
			return false
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


func mount(path: String) -> Dictionary:
	deadline = Time.get_ticks_msec() + int(MOUNT_TIMEOUT * 1000.0)
	match OS.get_name():
		"Windows":
			return await _mount_windows(path)
		"Linux":
			return await _mount_linux(path)
		"macOS":
			return await _mount_macos(path)
	return {"ok": false, "error": "ISO mounting is not supported on this system"}


func _command(program: String, arguments: PackedStringArray) -> Dictionary:
	if cancelled:
		return {"ok": false, "error": "Operation cancelled", "cancelled": true}
	var remaining := (deadline - Time.get_ticks_msec()) / 1000.0
	if remaining <= 0.0:
		return {"ok": false, "error": "Operation timed out"}
	task = BackgroundTask.command(program, arguments, remaining)
	var result: Dictionary = await task.completed
	task = null
	return result


func _mount_windows(path: String) -> Dictionary:
	var script_path := ProjectSettings.globalize_path("user://cache/mount_iso_%d.ps1" % get_instance_id())
	DirAccess.make_dir_recursive_absolute(script_path.get_base_dir())
	var script := FileAccess.open(script_path, FileAccess.WRITE)
	if script == null:
		return {"ok": false, "error": "Could not create the ISO mount helper"}
	script.store_string("$ErrorActionPreference = 'Stop'\n$image = $args[0]\nMount-DiskImage -ImagePath $image | Out-Null\n$volume = Get-DiskImage -ImagePath $image | Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -First 1 -ExpandProperty DriveLetter\nif ($volume) { Write-Output ($volume + ':/') }\n")
	script.close()
	var result := await _command("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script_path, path])
	DirAccess.remove_absolute(script_path)
	if not result["ok"]:
		return _mount_error(result, "Windows could not mount this ISO image")
	var root := str(result.get("output", "")).strip_edges()
	if root.is_empty():
		return {"ok": false, "error": "Mounted ISO has no accessible drive letter"}
	return {"ok": true, "path": root}


func _mount_linux(path: String) -> Dictionary:
	var result := await _command("udisksctl", ["loop-setup", "--read-only", "-f", path])
	if not result["ok"]:
		return _mount_error(result, "Could not create a read-only loop device for this ISO")
	var match_result := RegEx.create_from_string("(/dev/loop[0-9]+)").search(str(result.get("output", "")))
	if match_result == null:
		return {"ok": false, "error": "Could not find the mounted ISO device"}
	var device := match_result.get_string(1)
	result = await _command("udisksctl", ["mount", "-b", device])
	if not result["ok"]:
		_release_linux(device)
		return _mount_error(result, "Could not mount this ISO image")
	match_result = RegEx.create_from_string(" at (/.+)\\.$").search(str(result.get("output", "")).strip_edges())
	if match_result == null:
		_release_linux(device)
		return {"ok": false, "error": "Could not find the mounted ISO folder"}
	return {"ok": true, "path": match_result.get_string(1)}


static func _release_linux(device: String) -> void:
	var cleanup := BackgroundTask.command("udisksctl", ["unmount", "-b", device], 5.0)
	await cleanup.completed
	BackgroundTask.command("udisksctl", ["loop-delete", "-b", device], 5.0)


static func _mount_error(result: Dictionary, message: String) -> Dictionary:
	if result.get("cancelled", false) or result.get("error", "") == "Operation timed out":
		return result
	return {"ok": false, "error": message, "details": result.get("error", "")}


func _mount_macos(path: String) -> Dictionary:
	var mount_path := ProjectSettings.globalize_path("user://mounts/iso_%s" % path.md5_text())
	DirAccess.make_dir_recursive_absolute(mount_path)
	var result := await _command("hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount_path, path])
	if not result["ok"]:
		return _mount_error(result, "Could not mount this ISO image")
	return {"ok": true, "path": mount_path}
