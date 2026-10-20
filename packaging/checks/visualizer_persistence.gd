extends SceneTree


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func run() -> void:
	var settings := root.get_node("Settings")
	settings.set_process(false)
	var args := OS.get_cmdline_user_args()
	var expected := int(args[1])
	if args[0] == "select":
		settings.apply("visualizer_zoom", 1.8)
		settings.apply("visualizer_preset", expected)
		settings.apply("immersive_music_visualizer", true)
	elif args[0] == "cycle":
		settings.cycle_visualizer_preset(1)
	elif args[0] == "disable":
		settings.apply("immersive_music_visualizer", false)
	else:
		if not is_equal_approx(settings.visualizer_zoom, 1.8):
			printerr("FAIL: visualizer zoom lost across restart")
			quit(1)
			return
		if settings.visualizer_preset != expected or settings.immersive_music_visualizer != (args[0] == "restore"):
			printerr("FAIL: last preset or enabled state lost across restart")
			quit(1)
			return
		var field = load("res://scripts/resonance_field.gd").new()
		field.set_process(false)
		root.add_child(field)
		if field.preset_index != expected:
			printerr("FAIL: renderer did not restore last preset")
			quit(1)
			return
		print("PASS: last preset and enabled state restored across restart")
	quit()
