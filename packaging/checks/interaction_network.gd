extends "res://scripts/network.gd"

var helpers: Array[String] = []
var pids: Array[int] = []
var kio := true
var timeout := false


func _has_command(program: String) -> bool:
	return program == "busctl" if kio else program == "gio"


func _command(program: String, arguments: PackedStringArray, serial: int, deadline: int) -> Dictionary:
	helpers.append(program + " " + arguments[0])
	var slow := "slow" in " ".join(arguments) or timeout
	var reply := 's "/tmp"' if program == "busctl" else ("local path: /tmp" if arguments[0] == "info" else "")
	var source := "import time; time.sleep(%s); print(%s)" % ["2" if slow else "0", JSON.stringify(reply)]
	var shortened := mini(deadline, Time.get_ticks_msec() + 80) if timeout else deadline
	_capture_pid.call_deferred()
	return await super._command("python3", ["-c", source], serial, shortened)


func _capture_pid() -> void:
	if is_instance_valid(mount_job) and not mount_job.process.is_empty():
		pids.append(mount_job.process["pid"])
