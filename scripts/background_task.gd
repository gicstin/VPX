extends Node

signal completed(result: Dictionary)

const OUTPUT_LIMIT := 1048576

var task_id := -1
var work: Work
var process := {}
var output := PackedByteArray()
var errors := PackedByteArray()
var deadline := 0
var delivered := false
var cancellation := ""


class Work extends RefCounted:
	var action: Callable
	var mutex := Mutex.new()
	var cancelled := false
	var result := {}

	func run() -> void:
		var value: Dictionary = action.call(self)
		mutex.lock()
		result = value
		mutex.unlock()

	func is_cancelled() -> bool:
		mutex.lock()
		var value := cancelled
		mutex.unlock()
		return value

	func cancel() -> void:
		mutex.lock()
		cancelled = true
		mutex.unlock()


static func start(action: Callable, timeout := 30.0) -> Node:
	var job = load("res://scripts/background_task.gd").new()
	job.work = Work.new()
	job.work.action = action
	job.deadline = Time.get_ticks_msec() + int(timeout * 1000.0)
	job.task_id = WorkerThreadPool.add_task(job.work.run)
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(job)
	return job


static func command(program: String, arguments: PackedStringArray, timeout := 30.0) -> Node:
	var job = load("res://scripts/background_task.gd").new()
	job.process = OS.execute_with_pipe(program, arguments, false)
	job.deadline = Time.get_ticks_msec() + int(timeout * 1000.0)
	if job.process.is_empty():
		job.cancellation = "Could not start " + program
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(job)
	return job


func cancel() -> void:
	_stop("Operation cancelled")


func _stop(reason: String) -> void:
	if delivered:
		return
	cancellation = reason
	if work != null:
		work.cancel()
	if not process.is_empty():
		if OS.is_process_running(process["pid"]):
			OS.kill(process["pid"])
		_close_pipes()


func _process(_delta: float) -> void:
	if not delivered and cancellation.is_empty() and Time.get_ticks_msec() >= deadline:
		_stop("Operation timed out")
	if not cancellation.is_empty() and not delivered:
		_finish({"ok": false, "error": cancellation, "cancelled": cancellation == "Operation cancelled"})
	if task_id >= 0:
		if not WorkerThreadPool.is_task_completed(task_id):
			return
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
		if not delivered:
			_finish(work.result)
	elif not process.is_empty():
		_drain()
		if OS.is_process_running(process["pid"]):
			return
		_drain()
		if not delivered:
			var code := OS.get_process_exit_code(process["pid"])
			_finish({"ok": code == 0, "code": code, "output": output.get_string_from_utf8(), "error": errors.get_string_from_utf8()})
		_close_pipes()
	if delivered:
		queue_free()


func _drain() -> void:
	var stream: FileAccess = process["stdio"]
	var chunk := stream.get_buffer(65536)
	if output.size() < OUTPUT_LIMIT:
		output.append_array(chunk.slice(0, OUTPUT_LIMIT - output.size()))
	stream = process["stderr"]
	chunk = stream.get_buffer(65536)
	if errors.size() < OUTPUT_LIMIT:
		errors.append_array(chunk.slice(0, OUTPUT_LIMIT - errors.size()))


func _finish(result: Dictionary) -> void:
	delivered = true
	completed.emit(result)


func _close_pipes() -> void:
	for key in ["stdio", "stderr"]:
		var stream: FileAccess = process.get(key)
		if stream != null:
			stream.close()
	process.clear()


func _exit_tree() -> void:
	if work != null:
		work.cancel()
	if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
		WorkerThreadPool.wait_for_task_completion(task_id)
	if not process.is_empty():
		if OS.is_process_running(process["pid"]):
			OS.kill(process["pid"])
		_close_pipes()
