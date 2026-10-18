class_name Shell

static func is_windows() -> bool:
	return OS.get_name() == "Windows"


static func program() -> String:
	if is_windows():
		return OS.get_executable_path().get_base_dir().path_join("busybox.exe")
	return "sh"


static func arguments(script: String, positional: Array = []) -> PackedStringArray:
	var args := PackedStringArray()
	if is_windows():
		args.append("sh")
		var folder := OS.get_executable_path().get_base_dir()
		script = RegEx.create_from_string("nice -n [0-9]+ ").sub(script, "", true)
		var setup := "export PATH=\"%s:$PATH\"; " % folder
		if not positional.is_empty():
			var values := PackedStringArray()
			for value: Variant in positional:
				values.append("'" + str(value).replace("'", "'\\''") + "'")
			setup += "set -- %s; " % " ".join(values)
		script = (setup + script).replace("\"", "\\\"")
	args.append_array(["-c", script, "sh"])
	if not is_windows():
		for value: Variant in positional:
			args.append(str(value))
	return args


static func spawn(script: String, positional: Array = []) -> int:
	return OS.create_process(program(), arguments(script, positional))


static func run(script: String, positional: Array = [], output: Array = [], read_stderr := false) -> int:
	return OS.execute(program(), arguments(script, positional), output, read_stderr)


static func has_command(command: String) -> bool:
	return run("command -v %s" % command) == 0
