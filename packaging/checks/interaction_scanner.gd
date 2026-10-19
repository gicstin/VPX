extends "res://scripts/library_scanner.gd"


func _start_job(request: Dictionary) -> Node:
	return BackgroundTask.start(_delayed_job.bind(request, extensions.duplicate(), mutex, results), SCAN_TIMEOUT)


static func _delayed_job(p_token: RefCounted, request: Dictionary, p_extensions: Array, p_mutex: Mutex, p_results: Array[Dictionary]) -> Dictionary:
	if request["path"].ends_with("/slow"):
		OS.delay_msec(500)
	return load("res://scripts/library_scanner.gd")._run_job(p_token, request, p_extensions, p_mutex, p_results)
