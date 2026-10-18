class_name PlatformPaths

static func home() -> String:
	if OS.get_name() == "Windows":
		var profile := OS.get_environment("USERPROFILE").replace("\\", "/")
		if not profile.is_empty():
			return profile
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).get_base_dir()
	return OS.get_environment("HOME")
