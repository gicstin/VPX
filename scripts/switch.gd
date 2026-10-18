class_name Switch
extends SettingRow

const SWITCH_HEIGHT := 34
const ICON_ROLES := ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]

var button: Button


func _build() -> void:
	button = make_button("", 110)
	button.theme_type_variation = &"FlatIcon"
	button.toggle_mode = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 64)
	for role in ICON_ROLES:
		button.add_theme_color_override(role, Color.WHITE)
	for state in ["normal", "pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.toggled.connect(func(on: bool) -> void:
		_show(on)
		write(on))
	add_child(button)
	gui_input.connect(_on_row_input)


func _on_row_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		button.button_pressed = not button.button_pressed
		accept_event()


func _show(on: bool) -> void:
	button.icon = VpxTheme.icon("switch_on" if on else "switch_off", SWITCH_HEIGHT)


func _pull() -> void:
	var on := bool(read())
	button.set_pressed_no_signal(on)
	_show(on)
