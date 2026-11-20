extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames() -> void:
	for i in 3:
		await process_frame


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	return event


func _run() -> void:
	create_timer(45).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	var library := root.get_node("Library")
	library.entries = {}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	var ui = main.ui
	var player: Node = main.player
	player.current_path = "hover-test.mp4"
	library.set_pref(player.current_path, "bookmarks", [30.0])
	player.rename_bookmark(30.0, "Opening")
	ui.seek_slider.editable = true
	ui.seek_slider.max_value = 100.0
	ui.marks.show_marks(100.0, 0.0, [], [30.0], Vector2(-1.0, -1.0))
	var marks = ui.marks
	var x: float = marks._x(30.0)
	var origin: Vector2 = ui.seek_slider.get_global_rect().position
	var y: float = origin.y + ui.seek_slider.size.y * 0.5
	ui.seek_slider.editable = true
	ui._on_seek_hover(_motion(Vector2(5.0, y - origin.y)))
	await frames()
	check(ui.seek_bubble.visible, "bubble shows on plain slider hover")
	ui.seek_slider.editable = true
	ui._on_seek_hover(_motion(Vector2(x - 20.0, y - origin.y)))
	await frames()
	ui.seek_slider.editable = true
	marks._gui_input(_motion(Vector2(x - 8.0, y - origin.y)))
	await frames()
	print("bubble: ", ui.bubble_label.text, " visible ", ui.seek_bubble.visible)
	check(ui.seek_bubble.visible and "Opening" in ui.bubble_label.text, "bookmark name shows on hover without click")
	ui.seek_slider.editable = true
	marks._gui_input(_motion(Vector2(x, y - origin.y)))
	await frames()
	check(ui.seek_bubble.visible and "Opening" in ui.bubble_label.text, "name stays on marker")
	ui.seek_slider.editable = true
	ui._on_seek_hover(_motion(Vector2(x + 4.0, y - origin.y)))
	check(ui.seek_bubble.visible and "Opening" in ui.bubble_label.text, "slider hover near marker snaps to its name")
	ui._on_seek_hover(_motion(Vector2(x + 60.0, y - origin.y)))
	check(ui.seek_bubble.visible and not "Opening" in ui.bubble_label.text, "away from marker shows plain time")
	main.queue_free()
	await frames()
	print("marker hover: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
