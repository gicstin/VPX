extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	root.size = Vector2i(960, 540)
	var settings: Node = root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.resume_playback = false
	settings.visualizer_quality = 1
	settings.visualizer_auto_change = false
	settings.prefer_desktop = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.music_visualizer.set_process(false)
	main.desktop_view.set_process(false)
	main.panel.visible = false
	main.get_node("Origin/Left").set_process(false)
	main.get_node("Origin/Right").set_process(false)
	var field: Node = main.resonance_field
	field.set_process(false)
	field.set_active(true)
	var picture_zoom: float = settings.picture_zoom
	main._step_action(settings.StickAction.PICTURE_ZOOM, 1)
	check(settings.visualizer_zoom > 1.0 and settings.picture_zoom == picture_zoom, "zoom shortcut changes visualizer independently")
	check(main._presented_action(settings.StickAction.SCREEN_SIZE) == settings.StickAction.PICTURE_ZOOM, "VR size shortcut maps to visualizer zoom in flat mode")
	check(main.action_name(settings.StickAction.SCREEN_SIZE) == "Visualizer zoom" and "%" in main.action_value(settings.StickAction.SCREEN_SIZE), "controller feedback shows visualizer zoom")
	settings.apply("visualizer_zoom", 1.0)
	main.desktop_view._fit_camera(Vector2(960, 540))
	var base_fov: float = main.camera.fov
	settings.apply("visualizer_zoom", 2.0)
	main.desktop_view._fit_camera(Vector2(960, 540))
	check(is_equal_approx(tan(deg_to_rad(base_fov) * 0.5) / tan(deg_to_rad(main.camera.fov) * 0.5), 2.0), "desktop projection magnifies exactly two times")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	main.desktop_view._video_button(wheel)
	check(settings.visualizer_zoom > 2.0 and settings.picture_zoom == picture_zoom, "Ctrl wheel targets visualizer zoom")
	settings.apply("visualizer_zoom", 1.0)
	var left: Node = main.get_node("Origin/Left")
	settings.grip_action = settings.StickAction.SCREEN_SIZE
	settings.projection = settings.ProjectionMode.FLAT
	left.grip_held = true
	left._handle_stick(Vector2(0, 1), 0.5)
	check(settings.visualizer_zoom > 1.0 and settings.picture_zoom == picture_zoom and left.visualizer_zooming, "continuous grip stick zoom works without changing picture zoom")
	left._handle_stick(Vector2.ZERO, 0.01)
	check(not left.zooming and not left.visualizer_zooming, "stick release commits visualizer zoom")
	left.grip_held = false
	var host := Control.new()
	root.add_child(host)
	var picker: Node = load("res://scripts/visualizer_picker.gd").new()
	picker.setting = &"visualizer_preset"
	picker.options = PackedStringArray(settings.VISUALIZER_PRESETS)
	host.add_child(picker)
	check(picker.adjustments.has(&"visualizer_zoom"), "desktop and VR picker includes zoom control")
	picker.adjustments[&"visualizer_zoom"].value = 2.25
	check(is_equal_approx(settings.visualizer_zoom, 2.25), "picker slider applies zoom")
	var row: Node = picker.adjustments[&"visualizer_zoom"].get_parent()
	row.get_child(row.get_child_count() - 1).pressed.emit()
	check(is_equal_approx(settings.visualizer_zoom, 1.0), "picker reset restores normal zoom")
	field.vr_zoom = true
	field.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.4, 0.1)), Vector3(-2, 1, 4))
	main.camera.global_transform = Transform3D(Basis.from_euler(Vector3(-0.3, 0.6, 0.15)), Vector3(0.2, 1.7, -0.4))
	var pose: Transform3D = field.global_transform
	var lens: float = main.camera.fov
	var children: int = field.get_child_count()
	var mesh_ids: Array[int] = []
	var counts: Array[int] = []
	for layer in field.layers:
		mesh_ids.append(layer.multimesh.get_instance_id())
		counts.append(layer.multimesh.instance_count)
	settings.apply("visualizer_zoom", 2.0)
	field._update_zoom()
	var target: Vector3 = main.camera.to_global(Vector3(1, 0.5, -8))
	var magnified: Vector3 = main.camera.to_local(field.to_global(field.layers[0].transform * field.to_local(target)))
	check(magnified.is_equal_approx(Vector3(1, 0.5, -4)), "VR zoom doubles angular size around translated and rotated head pose")
	check(is_equal_approx(main.camera.fov, lens), "VR zoom preserves headset camera projection")
	check(field.global_transform.is_equal_approx(pose), "VR zoom preserves scene placement and audio anchor")
	for index in field.layers.size():
		check(field.layers[index].multimesh.get_instance_id() == mesh_ids[index] and field.layers[index].multimesh.instance_count == counts[index], "VR zoom reuses geometry layer " + str(index))
		check(field.layers[index].transform.is_equal_approx(field.sky.transform), "sky and geometry share zoom layer " + str(index))
	check(field.get_child_count() == children and children == 5, "zoom adds no geometry nodes or render viewports")
	main.camera.position += Vector3(0.1, -0.05, 0.2)
	main.camera.rotate_y(0.3)
	field._update_zoom()
	var fixed: Vector3 = field.to_global(field.layers[0].transform * field.to_local(main.camera.global_position))
	check(fixed.is_equal_approx(main.camera.global_position), "head movement updates zoom pivot without moving the viewer")
	settings.apply("visualizer_zoom", 1.0)
	field._update_zoom()
	check(field.layers[0].transform.is_equal_approx(Transform3D.IDENTITY) and field.sky.transform.is_equal_approx(Transform3D.IDENTITY), "normal zoom restores exact scene transforms")
	field.vr_zoom = false
	settings.apply("visualizer_zoom", 2.0)
	field._update_zoom()
	check(field.layers[0].transform.is_equal_approx(Transform3D.IDENTITY), "desktop mode avoids applying VR zoom twice")
	settings.apply("visualizer_zoom", INF)
	check(is_equal_approx(settings.visualizer_zoom, 2.0), "nonfinite zoom rejected")
	settings.apply("visualizer_zoom", 100.0)
	check(settings.visualizer_zoom == settings.VISUALIZER_ZOOM_MAX, "zoom upper limit enforced")
	settings.apply("visualizer_zoom", -1.0)
	check(settings.visualizer_zoom == settings.VISUALIZER_ZOOM_MIN, "zoom lower limit enforced")
	settings.apply("visualizer_zoom", 1.8)
	var backup: RefCounted = load("res://scripts/settings_backup.gd").new()
	var exported: Dictionary = backup.export_settings("user://zoom-backup.cfg")
	settings.apply("visualizer_zoom", 1.0)
	var imported: Dictionary = backup.import_settings("user://zoom-backup.cfg", false)
	check(exported.get("ok", false) and imported.get("ok", false) and is_equal_approx(settings.visualizer_zoom, 1.8), "settings backup restores visualizer zoom")
	settings.apply("visualizer_preset", 17)
	settings.apply("visualizer_zoom", 1.0)
	var render_view := SubViewport.new()
	render_view.size = Vector2i(640, 360)
	render_view.own_world_3d = true
	render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(render_view)
	var render_camera := Camera3D.new()
	render_camera.fov = 85.0
	render_view.add_child(render_camera)
	render_camera.current = true
	field.reparent(render_view)
	field.camera = render_camera
	field.global_transform = Transform3D.IDENTITY
	field.vr_zoom = true
	var music: RefCounted = load("res://packaging/checks/music_stimulus.gd").new()
	for frame in 180:
		var t := frame / 60.0
		music.groove(t)
		var sound: Dictionary = music.frame(1.0 / 60.0)
		field.feed(sound.spectrum, sound.features)
		field.feed_waveform(music.waveform(t, sound.spectrum))
		field.clock = t
		field.beat_age += 1.0 / 60.0
		field._process(1.0 / 60.0)
	await process_frame
	RenderingServer.force_draw()
	var before: Image = render_view.get_texture().get_image()
	before.save_png("/tmp/vpx-zoom-normal.png")
	settings.apply("visualizer_zoom", 2.0)
	field._update_zoom()
	await process_frame
	RenderingServer.force_draw()
	var after: Image = render_view.get_texture().get_image()
	after.save_png("/tmp/vpx-zoom-magnified.png")
	var difference := 0.0
	for y in range(0, before.get_height(), 4):
		for x in range(0, before.get_width(), 4):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	check(difference > 1.0, "VR scene zoom changes the rendered view")
	settings.apply("visualizer_zoom", 1.8)
	field.set_active(false)
	main.desktop_view._fit_camera(Vector2(960, 540))
	main._step_action(settings.StickAction.PICTURE_ZOOM, 1)
	check(settings.picture_zoom > picture_zoom and is_equal_approx(settings.visualizer_zoom, 1.8), "normal picture zoom resumes when visualizer is inactive")
	print("VISUALIZER_ZOOM checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
