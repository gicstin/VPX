extends Control

signal submitted(text: String)
signal edited(text: String)
signal cancelled

const PANEL_WIDTH := 1180
const KEY_SIZE := Vector2(88, 72)
const KEY_GAP := 8
const LETTER_ROWS := ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
const SYMBOL_ROWS := ["1234567890", "-_/:.@?&=%", "~+#!$()[]'", ",;*|\\\"<>^"]

var title_label: Label
var field: LineEdit
var rows: VBoxContainer
var shift := false
var symbols := false
var live := false
var letter_buttons: Array[Button] = []
var shift_button: Button
var symbol_button: Button


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = VpxTheme.SCRIM
	shade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.SURFACE, 26, 24, 20))
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 26)
	layout.add_child(title_label)
	field = LineEdit.new()
	field.custom_minimum_size.y = 64
	field.add_theme_font_size_override("font_size", 28)
	field.clear_button_enabled = true
	field.text_changed.connect(func(text: String) -> void:
		if live:
			edited.emit(text))
	field.text_submitted.connect(func(_text: String) -> void: _submit())
	layout.add_child(field)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", KEY_GAP)
	layout.add_child(rows)
	_build_keys()


func open(title: String, text := "", placeholder := "", p_live := false) -> void:
	size = get_viewport().get_visible_rect().size
	title_label.text = title
	field.text = text
	field.placeholder_text = placeholder
	field.caret_column = text.length()
	live = p_live
	shift = false
	symbols = false
	_relabel()
	move_to_front()
	visible = true
	field.grab_focus()


func close() -> void:
	visible = false
	field.release_focus()


func _build_keys() -> void:
	for row_index in LETTER_ROWS.size():
		var row := _row()
		if row_index == 3:
			shift_button = _key("⇧", _toggle_shift, 1.3)
			shift_button.toggle_mode = true
			row.add_child(shift_button)
		for column in LETTER_ROWS[row_index].length():
			var key := _key("", Callable())
			key.set_meta("row", row_index)
			key.set_meta("column", column)
			key.pressed.connect(_type_key.bind(key))
			row.add_child(key)
			letter_buttons.append(key)
		if row_index == 3:
			row.add_child(_key("⌫", _backspace, 1.6))
	var bottom := _row()
	symbol_button = _key("#+=", _toggle_symbols, 1.4)
	bottom.add_child(symbol_button)
	bottom.add_child(_key("Clear", func() -> void: _set_text(""), 1.4))
	bottom.add_child(_key("Paste", paste_clipboard, 1.4))
	bottom.add_child(_key("Space", func() -> void: _insert(" "), 2.6))
	bottom.add_child(_key("Cancel", cancel, 1.6))
	var done := _key("Done", _submit, 1.8)
	done.theme_type_variation = &"PrimaryButton"
	bottom.add_child(done)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", KEY_GAP)
	rows.add_child(row)
	return row


func _key(text: String, action: Callable, width := 1.0) -> Button:
	var key := Button.new()
	key.text = text
	key.focus_mode = FOCUS_NONE
	key.custom_minimum_size = Vector2(KEY_SIZE.x * width + KEY_GAP * (width - 1.0), KEY_SIZE.y)
	key.add_theme_font_size_override("font_size", 28)
	if action.is_valid():
		key.pressed.connect(action)
	return key


func _relabel() -> void:
	var source: Array = SYMBOL_ROWS if symbols else LETTER_ROWS
	for key in letter_buttons:
		var row: String = source[key.get_meta("row")]
		var column: int = key.get_meta("column")
		key.visible = column < row.length()
		if key.visible:
			var character := row[column]
			key.text = character.to_upper() if shift and not symbols else character
	shift_button.visible = not symbols
	shift_button.set_pressed_no_signal(shift)
	symbol_button.text = "abc" if symbols else "#+="


func _type_key(key: Button) -> void:
	_insert(key.text)
	if shift:
		shift = false
		_relabel()


func _insert(text: String) -> void:
	var start := field.get_selection_from_column() if field.has_selection() else field.caret_column
	var end := field.get_selection_to_column() if field.has_selection() else field.caret_column
	_set_text(field.text.substr(0, start) + text + field.text.substr(end), start + text.length())


func _backspace() -> void:
	var column := field.caret_column
	if column <= 0:
		return
	_set_text(field.text.substr(0, column - 1) + field.text.substr(column), column - 1)


func _set_text(text: String, caret := -1) -> void:
	field.text = text
	field.caret_column = text.length() if caret < 0 else caret
	if live:
		edited.emit(text)


func _toggle_shift() -> void:
	shift = not shift
	_relabel()


func _toggle_symbols() -> void:
	symbols = not symbols
	shift = false
	_relabel()


func _submit() -> void:
	close()
	submitted.emit(field.text.strip_edges())


func cancel() -> void:
	close()
	cancelled.emit()


func paste_clipboard() -> void:
	_insert(DisplayServer.clipboard_get().replace("\r", "").replace("\n", " "))
	field.grab_focus()
