extends RefCounted

const COMPLETION := 0.9

var path := ""
var counted := false


func begin(next_path: String) -> void:
	path = next_path
	counted = false


func sample(position: float, length: float, active: bool, audio := false) -> void:
	if counted or path.is_empty() or not active or length <= 0.0 or position < length * COMPLETION:
		return
	counted = true
	var key := "listen_count" if audio else "view_count"
	Library.set_pref(path, key, int(Library.get_pref(path, key, 0)) + 1)
	Library.watch_changed.emit(path)
