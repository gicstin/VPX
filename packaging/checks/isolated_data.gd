extends RefCounted


static func verify() -> bool:
	var directory := OS.get_environment("VPX_CHECK_DATA_ROOT").simplify_path()
	if directory.is_absolute_path() and directory != "/" and OS.get_user_data_dir().simplify_path().begins_with((directory.trim_suffix("/") + "/")):
		return true
	printerr("Run through python3 packaging/run_check.py <Godot arguments> to protect player settings.")
	return false
