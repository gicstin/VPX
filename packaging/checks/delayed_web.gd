extends "res://scripts/web_video.gd"

var media := ""


func _ready() -> void:
	pass


func available() -> bool:
	return true


func resolve(_url: String, done: Callable) -> void:
	await get_tree().create_timer(1.5).timeout
	done.call({"ok": true, "stream": media, "audio": "", "headers": "", "title": "Delayed web video", "start_time": 0.0})
