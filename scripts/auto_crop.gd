extends Node

signal detected(path: String, stereo: int, rect: Vector4)

const PREF_KEY := "auto_crop"
const SAMPLE_POINTS := [0.12, 0.3, 0.5, 0.7, 0.88]
const FRAMES_PER_POINT := 8
const JOB_TIMEOUT_MSEC := 60000
const MIN_CROP := 0.004
const NICE := "15"
const SCRIPT := "for t in $3; do nice -n %s ffmpeg -hide_banner -nostats -noaccurate_seek -ss \"$t\" -i \"$1\" -an -sn -dn -frames:v %d -vf \"$4cropdetect=limit=24:round=2:reset=0\" -f null - 2>&1 | grep -o 'crop=[0-9:]*' | tail -n 1; done > \"$2\"; ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 \"$1\" >> \"$2\""

var pid := -1
var job := {}


func request(path: String, stereo: int, length: float) -> void:
	cancel()
	var cached: Variant = Library.get_pref(path, PREF_KEY)
	if cached is Dictionary and int(cached.get("stereo", -1)) == stereo:
		var values: Array = cached.get("rect", [])
		if values.size() == 4:
			detected.emit(path, stereo, Vector4(values[0], values[1], values[2], values[3]))
			return
	if length <= 1.0:
		return
	var times := PackedStringArray()
	for point: float in SAMPLE_POINTS:
		times.append("%.2f" % (length * point))
	var pre := ""
	match stereo:
		Settings.Stereo.SIDE_BY_SIDE:
			pre = "crop=iw/2:ih:0:0,"
		Settings.Stereo.OVER_UNDER:
			pre = "crop=iw:ih/2:0:0,"
	var output := ProjectSettings.globalize_path("user://cache/crop_%s.txt" % path.md5_text())
	pid = Shell.spawn(SCRIPT % [NICE, FRAMES_PER_POINT], [path, output, " ".join(times), pre])
	if pid <= 0:
		pid = -1
		return
	job = {"path": path, "stereo": stereo, "output": output, "started": Time.get_ticks_msec()}
	Log.info("auto crop: scanning %s" % path.get_file())


func cancel() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	job = {}


func _process(_delta: float) -> void:
	if pid <= 0:
		return
	if OS.is_process_running(pid):
		if Time.get_ticks_msec() - int(job["started"]) > JOB_TIMEOUT_MSEC:
			cancel()
		return
	pid = -1
	var finished := job
	job = {}
	var text := FileAccess.get_file_as_string(finished["output"])
	DirAccess.remove_absolute(finished["output"])
	var rect := parse(text, int(finished["stereo"]))
	if rect.x < 0.0:
		return
	Library.set_pref(finished["path"], PREF_KEY, {"stereo": finished["stereo"], "rect": [rect.x, rect.y, rect.z, rect.w]})
	detected.emit(finished["path"], finished["stereo"], rect)


static func parse(text: String, stereo: int) -> Vector4:
	var lines := text.strip_edges().split("\n", false)
	if lines.is_empty():
		return Vector4(-1, -1, -1, -1)
	var size_parts := lines[lines.size() - 1].split(",")
	if size_parts.size() < 2:
		return Vector4(-1, -1, -1, -1)
	var frame := Vector2(float(size_parts[0]), float(size_parts[1]))
	if stereo == Settings.Stereo.SIDE_BY_SIDE:
		frame.x = floorf(frame.x / 2.0)
	elif stereo == Settings.Stereo.OVER_UNDER:
		frame.y = floorf(frame.y / 2.0)
	if frame.x <= 0.0 or frame.y <= 0.0:
		return Vector4(-1, -1, -1, -1)
	var union := Rect2()
	var found := false
	for line in lines:
		if not line.begins_with("crop="):
			continue
		var values := line.trim_prefix("crop=").split(":")
		if values.size() != 4:
			continue
		var rect := Rect2(float(values[2]), float(values[3]), float(values[0]), float(values[1]))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		union = rect if not found else union.merge(rect)
		found = true
	if not found:
		return Vector4(-1, -1, -1, -1)
	var result := Vector4(union.position.x / frame.x, union.position.y / frame.y, 1.0 - union.end.x / frame.x, 1.0 - union.end.y / frame.y)
	for axis in 4:
		result[axis] = clampf(result[axis], 0.0, 0.45)
		if result[axis] < MIN_CROP:
			result[axis] = 0.0
	return result
