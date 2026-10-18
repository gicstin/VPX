extends RefCounted

const SESSION_ENV := "VPX_MODE_SESSION"


static func engine_arguments(args: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var skip := false
	for arg in args:
		if arg == "--":
			break
		if skip:
			skip = false
			continue
		if arg == "--xr-mode":
			skip = true
			continue
		if not arg.begins_with("--xr-mode="):
			result.append(arg)
	return result


static func user_arguments(args: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for arg in args:
		if arg != "--desktop":
			result.append(arg)
	return result
