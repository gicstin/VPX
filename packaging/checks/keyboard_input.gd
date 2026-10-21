extends SceneTree

var failures := 0
var checks := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)


func frames(count := 4) -> void:
	for i in count:
		await process_frame


func position_for(control: Control) -> Vector2:
	return position_for_point(control.get_global_rect().get_center())


func position_for_point(point: Vector2) -> Vector2:
	var rect: Rect2 = main.desktop_view.menu_rect.get_rect()
	return rect.position + point / Vector2(main.ui_viewport.size_2d_override) * rect.size


func motion(position: Vector2, held := false) -> void:
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(position)
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func button(position: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func click(position: Vector2, index := MOUSE_BUTTON_LEFT) -> void:
	motion(position)
	button(position, true, index)
	await frames(2)
	button(position, false, index)
	await frames(2)


func keypress(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)


func context_menu_cases(rate: int) -> void:
	var keyboard: Control = main.ui.keyboard
	var field: LineEdit = keyboard.field
	var menu := field.get_menu()
	var key: Button = keyboard.letter_buttons[10]
	var done: Button = keyboard.rows.get_child(4).get_children().back()
	var received: Array[String] = []
	var capture := func(text: String) -> void: received.append(text)
	keyboard.submitted.connect(capture)
	main.ui.keyboard_purpose = ""
	var original := ""
	var pasted := ""
	var actions := ["keyboard_clear", "outside"]
	if DisplayServer.get_name() != "headless":
		original = DisplayServer.clipboard_get()
		pasted = "http://example.org/stream"
		DisplayServer.clipboard_set(pasted)
		actions = ["mouse_paste", "keyboard_paste", "keyboard_clear", "outside"]
	for action in actions:
		keyboard.open("Clipboard input", "clear me" if action == "keyboard_clear" else "")
		await frames()
		await click(position_for(field), MOUSE_BUTTON_RIGHT)
		check(menu.visible, "right click opens text menu for %s at %d fps" % [action, rate])
		match action:
			"mouse_paste":
				var height := menu.get_theme_font("font").get_height(menu.get_theme_font_size("font_size")) + menu.get_theme_constant("v_separation")
				var point := Vector2(menu.position) + Vector2(menu.size.x * 0.5, menu.get_theme_stylebox("panel").get_margin(SIDE_TOP) + height * 2.5)
				await click(position_for_point(point))
			"keyboard_paste":
				menu.set_focused_item(menu.get_item_index(LineEdit.MENU_PASTE))
				await keypress(KEY_ENTER)
			"keyboard_clear":
				menu.set_focused_item(menu.get_item_index(LineEdit.MENU_CLEAR))
				await keypress(KEY_ENTER)
			"outside":
				await click(position_for(key))
		await frames()
		check(not menu.visible, "text menu closes after %s at %d fps" % [action, rate])
		var expected := pasted if action.ends_with("paste") else ""
		check(field.text == expected, "text menu action %s keeps expected text at %d fps" % [action, rate])
		motion(position_for(key))
		await frames()
		check(main.ui_viewport.gui_get_hovered_control() == key, "key hover recovers after %s at %d fps" % [action, rate])
		if DisplayServer.get_name() != "headless":
			check(Input.get_current_cursor_shape() == Input.CURSOR_ARROW, "text cursor clears after %s at %d fps" % [action, rate])
		await click(position_for(key))
		check(field.text == expected + "q", "key click works after %s at %d fps" % [action, rate])
		check(main.ui_viewport.gui_get_focus_owner() == field, "text focus survives %s at %d fps" % [action, rate])
		received.clear()
		await click(position_for(done))
		check(received == [expected + "q"] and not keyboard.visible, "Done submits once after %s at %d fps" % [action, rate])
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(original)
	keyboard.submitted.disconnect(capture)


func _run() -> void:
	create_timer(30).timeout.connect(func() -> void: quit(2))
	root.get_node("Settings").last_file = ""
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	var keyboard: Control = main.ui.keyboard
	var key: Button = keyboard.letter_buttons[10]
	var field_motion: Array[InputEvent] = []
	var key_motion: Array[InputEvent] = []
	keyboard.field.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			field_motion.append(event))
	key.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			key_motion.append(event))
	for rate in [30, 90]:
		Engine.max_fps = rate
		main.ui._ask_link()
		await frames()
		field_motion.clear()
		key_motion.clear()
		var field_position := position_for(keyboard.field)
		var key_position := position_for(key)
		motion(field_position)
		check(not field_motion.is_empty(), "text field receives desktop mouse motion at %d fps" % rate)
		await click(field_position)
		if DisplayServer.get_name() != "headless":
			check(Input.get_current_cursor_shape() == Input.CURSOR_IBEAM, "text cursor stays inside text field")
		motion(key_position)
		check(not key_motion.is_empty(), "keyboard key receives desktop mouse motion at %d fps" % rate)
		var stable := true
		var stable_cursor := true
		for i in 8:
			await process_frame
			stable = stable and main.ui_viewport.gui_get_hovered_control() == key
			if DisplayServer.get_name() != "headless":
				stable_cursor = stable_cursor and Input.get_current_cursor_shape() == Input.CURSOR_ARROW
		check(stable, "stationary key hover stays stable at %d fps" % rate)
		if DisplayServer.get_name() != "headless":
			check(stable_cursor, "keyboard key cursor stays stable at %d fps" % rate)
		await click(key_position)
		check(keyboard.field.text == "q", "field-to-key click types once at %d fps" % rate)
		check(main.ui_viewport.gui_get_focus_owner() == keyboard.field, "typing retains text focus at %d fps" % rate)
		button(key_position, true)
		motion(Vector2.ZERO, true)
		button(Vector2.ZERO, false)
		await frames(2)
		check(keyboard.field.text == "q", "releasing a key outside menu cancels typing")
		check(main.ui_viewport.gui_get_hovered_control() == null, "leaving desktop menu clears keyboard hover")
		key_motion.clear()
		motion(key_position)
		check(not key_motion.is_empty(), "reentering desktop menu restores keyboard mouse motion")
		await click(key_position)
		check(keyboard.field.text == "qq", "next key click works after release outside menu")
		keyboard.close()
		await context_menu_cases(rate)
	main.ui._ask_link()
	await frames()
	motion(position_for(key))
	root.mouse_exited.emit()
	check(main.ui_viewport.gui_get_hovered_control() == null, "leaving desktop window clears keyboard hover")
	motion(position_for(key))
	main.panel.close()
	await frames(30)
	check(main.ui_viewport.gui_get_hovered_control() == null, "closing desktop menu clears keyboard hover")
	main.queue_free()
	await frames()
	print("RESULT: keyboard_input checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
