extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func frames() -> void:
	for frame in 6:
		await process_frame

func mouse(viewport: Viewport, control: Control, button: int) -> void:
	var position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event, true)

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 700)
	root.add_child(viewport)
	var controls = load("res://scripts/music_controls.gd").new()
	viewport.add_child(controls)
	controls.size = controls.wanted_size()
	await frames()
	settings.apply("volume", 50)
	settings.apply("muted", false)
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_WHEEL_UP)
	check(settings.volume == 55 and not controls.volume_row.visible, "mini player wheel raises volume without opening slider")
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_WHEEL_DOWN)
	check(settings.volume == 50, "mini player wheel lowers volume")
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_RIGHT)
	check(settings.muted and not controls.volume_row.visible, "mini player right click mutes without opening slider")
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_RIGHT)
	check(not settings.muted, "second right click unmutes")
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_LEFT)
	await frames()
	check(controls.volume_row.visible, "left click still opens volume slider")
	for control: Control in [controls.mute_button, controls.volume_slider, controls.volume_label]:
		settings.apply("volume", 50)
		mouse(viewport, control, MOUSE_BUTTON_WHEEL_UP)
		check(settings.volume == 55, "mini volume row wheel changes volume once: " + control.get_class())
		mouse(viewport, control, MOUSE_BUTTON_RIGHT)
		check(settings.muted, "mini volume row right click mutes: " + control.get_class())
		settings.apply("muted", false)
	var pointer = load("res://scripts/pointer.gd").new()
	pointer.viewport = main.ui.get_viewport()
	pointer.target_viewport = viewport
	pointer.panel = main.panel
	pointer.last_uv = Vector2(0.5, 0.5)
	mouse(viewport, controls.volume_button, MOUSE_BUTTON_WHEEL_DOWN)
	settings.apply("volume", 50)
	check(pointer._hovering_volume(), "VR finds volume on floating music viewport")
	check(not pointer._stick_scrolls(Vector2.UP), "VR volume hover prevents menu scrolling")
	pointer._flick_vertical(1, true)
	check(settings.volume == 55 and not settings.muted, "VR thumbstick up raises mini volume")
	pointer._flick_vertical(-1, true)
	check(settings.volume == 50, "VR thumbstick down lowers mini volume")
	pointer.last_uv = Vector2(-1, -1)
	check(not pointer._hovering_volume(), "VR ignores stale hover outside panel")
	main.ui.set_process(false)
	main.ui.reparent(viewport)
	controls.hide()
	main.ui.show()
	main.ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()
	for control: Control in [main.ui.mute_button, main.ui.volume_slider, main.ui.volume_label]:
		settings.apply("volume", 50)
		mouse(viewport, control, MOUSE_BUTTON_WHEEL_UP)
		check(settings.volume == 55, "main volume wheel changes volume once: " + control.get_class())
		mouse(viewport, control, MOUSE_BUTTON_RIGHT)
		check(settings.muted, "main volume right click mutes: " + control.get_class())
		settings.apply("muted", false)
	pointer.last_uv = Vector2(0.5, 0.5)
	check(pointer._hovering_volume(), "VR still finds main volume controls")
	pointer._flick_vertical(-1, true)
	check(settings.volume == 50, "VR thumbstick still adjusts main volume")
	pointer.free()
	main.free()
	viewport.free()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
