extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func _rows_with(node: Node, setting: StringName) -> Array:
	var found := []
	for child in node.get_children():
		if "setting" in child and child.setting == setting:
			found.append(child)
		found.append_array(_rows_with(child, setting))
	return found


func _visible(row: Node) -> bool:
	var node: Node = row
	while node != null and node is Control:
		if not node.visible:
			return false
		node = node.get_parent()
	return true


func _run() -> void:
	create_timer(30, true, false, true).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.stereo_mode = 0
	var controls: Control = load("res://scripts/stereo_controls.gd").new()
	root.add_child(controls)
	await process_frame
	var expectations := {
		0: {&"stereo_angle": false, &"stereo_amount": false, &"upmix_centre": false, &"upmix_ambience": false, &"crossfeed_db": false, &"air_db": false, &"room_amount": false, &"stereo_distance": false, &"head_width_cm": true, &"bass_translate": true},
		1: {&"stereo_angle": true, &"stereo_amount": true, &"upmix_centre": false, &"upmix_ambience": false, &"crossfeed_db": false, &"air_db": true, &"room_amount": true, &"stereo_distance": true, &"head_width_cm": true, &"bass_translate": true},
		2: {&"stereo_angle": false, &"stereo_amount": false, &"upmix_centre": false, &"upmix_ambience": false, &"crossfeed_db": true, &"air_db": true, &"room_amount": true, &"stereo_distance": true, &"head_width_cm": true, &"bass_translate": true},
		3: {&"stereo_angle": true, &"stereo_amount": false, &"upmix_centre": true, &"upmix_ambience": true, &"crossfeed_db": false, &"air_db": true, &"room_amount": true, &"stereo_distance": true, &"head_width_cm": true, &"bass_translate": true},
	}
	var choice_rows := _rows_with(controls, &"stereo_mode")
	check(choice_rows.size() == 1 and choice_rows[0].options.size() == 4, "the stereo sound choice offers four modes")
	for mode: int in expectations:
		settings.apply("stereo_mode", mode)
		await process_frame
		for key: StringName in expectations[mode]:
			var rows := _rows_with(controls, key)
			check(rows.size() == 1 and _visible(rows[0]) == expectations[mode][key], "mode %d: %s is %s" % [mode, key, "shown" if expectations[mode][key] else "hidden"])
	settings.apply("stereo_mode", 0)
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
