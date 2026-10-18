extends SettingRow

const SWATCH_SIZE := 48

var group := ButtonGroup.new()
var buttons: Array[Button] = []
var custom_button: Button
var custom_row: Control


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END
	for preset: Array in VpxTheme.ACCENT_PRESETS:
		var color: Color = preset[1]
		var button := _swatch(preset[0])
		_paint(button, color)
		button.toggled.connect(func(on: bool) -> void:
			if on:
				write(color))
		row.add_child(button)
		buttons.append(button)
	custom_button = _swatch("Custom")
	custom_button.text = "+"
	custom_button.toggled.connect(func(on: bool) -> void:
		if custom_row != null:
			custom_row.visible = on)
	row.add_child(custom_button)
	add_child(row)


func _swatch(tip: String) -> Button:
	var button := Button.new()
	button.focus_mode = FOCUS_NONE
	button.toggle_mode = true
	button.button_group = group
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
	return button


func _paint(button: Button, color: Color) -> void:
	for state in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state, VpxTheme.outlined(color, VpxTheme.BORDER, 2, SWATCH_SIZE / 2, 0, 0))
	button.add_theme_stylebox_override("hover", VpxTheme.outlined(color, VpxTheme.TEXT, 3, SWATCH_SIZE / 2, 0, 0))
	button.add_theme_stylebox_override("pressed", VpxTheme.outlined(color, VpxTheme.TEXT, 5, SWATCH_SIZE / 2, 0, 0))
	button.add_theme_stylebox_override("hover_pressed", VpxTheme.outlined(color, VpxTheme.FOCUS, 5, SWATCH_SIZE / 2, 0, 0))
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(role, color.darkened(0.84))


func _pull() -> void:
	var current: Color = read()
	var matched := false
	for i in buttons.size():
		var preset: Color = VpxTheme.ACCENT_PRESETS[i][1]
		var hit := preset.is_equal_approx(current)
		buttons[i].set_pressed_no_signal(hit)
		matched = matched or hit
	_paint(custom_button, current)
	if not matched:
		custom_button.set_pressed_no_signal(true)
	if custom_row != null:
		custom_row.visible = custom_button.button_pressed
