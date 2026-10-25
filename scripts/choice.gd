class_name Choice
extends SettingRow

@export var options: PackedStringArray

var row: GridContainer
var group := ButtonGroup.new()
var buttons: Array[Button] = []


func _build() -> void:
	var segment := PanelContainer.new()
	segment.theme_type_variation = &"Segment"
	segment.size_flags_horizontal = SIZE_EXPAND_FILL
	row = GridContainer.new()
	row.columns = maxi(options.size(), 1)
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.resized.connect(_layout_options)
	segment.add_child(row)
	for i in options.size():
		var button := make_button(options[i], 0)
		button.theme_type_variation = &"Chip"
		Tooltips.set_text(button, title + ": " + options[i])
		button.custom_minimum_size.y = ROW_HEIGHT - 8
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.toggled.connect(func(on: bool) -> void:
			if on:
				write(i))
		row.add_child(button)
		buttons.append(button)
	add_child(segment)


func _label_expands() -> bool:
	return false


func _pull() -> void:
	_layout_options()
	var index := clampi(int(read()), 0, buttons.size() - 1)
	for i in buttons.size():
		buttons[i].set_pressed_no_signal(i == index)


func _layout_options() -> void:
	if row == null or buttons.is_empty():
		return
	var columns := buttons.size()
	if Settings.text_size > 1.0:
		var width := 1.0
		for button in buttons:
			var font := button.get_theme_font("font")
			width = maxf(width, font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + 40.0)
		columns = clampi(floori(row.size.x / width), 1, columns)
	row.columns = columns
