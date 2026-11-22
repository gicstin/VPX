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


func _run() -> void:
	create_timer(30, true, false, true).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.playback_speed = 1.0
	settings.audio_stretch_quality = 0
	var host := VBoxContainer.new()
	root.add_child(host)
	var rows: Node = load("res://scripts/rows.gd").playback(host)
	await process_frame
	var warning: Label = rows.get_node_or_null("StretchWarning")
	check(warning != null, "playback rows carry a stretch warning")
	check(warning != null and not warning.visible, "no warning at normal speed")
	settings.apply("playback_speed", 1.25)
	await process_frame
	check(warning.visible and warning.text.contains("lowers sound quality"), "warning appears at 1.25x and says quality drops")
	check(warning.get_theme_color("font_color") != root.get_theme_color("font_color", "Label") or warning.theme_type_variation == &"Warning", "warning uses its own warning style")
	settings.apply("audio_stretch_quality", 1)
	await process_frame
	check(warning.visible and warning.text.contains("Fast mode"), "Fast mode gets its own stronger wording")
	settings.apply("playback_speed", 0.5)
	await process_frame
	check(warning.visible, "warning also shows when slowed down")
	settings.apply("playback_speed", 1.0)
	await process_frame
	check(not warning.visible, "warning hides again at 1x")
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
