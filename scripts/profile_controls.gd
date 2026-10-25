extends VBoxContainer

signal name_requested(renaming: bool)

const Rows := preload("res://scripts/rows.gd")

var manager := false
var selector: OptionButton
var status: Label
var update_button: Button
var rename_button: Button
var delete_button: Button


func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = "Viewing profile"
	label.custom_minimum_size.x = 220
	row.add_child(label)
	selector = OptionButton.new()
	Tooltips.set_text(selector, "Apply a saved viewing setup")
	selector.fit_to_longest_item = false
	selector.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	selector.clip_text = true
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selector.size_flags_horizontal = SIZE_EXPAND_FILL
	selector.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	selector.item_selected.connect(func(index: int) -> void:
		Settings.profiles.select(selector.get_item_metadata(index))
		_sync())
	row.add_child(selector)
	if manager:
		var actions := HBoxContainer.new()
		add_child(actions)
		var save := _button(actions, "Save current")
		save.pressed.connect(func() -> void: name_requested.emit(false))
		update_button = _button(actions, "Update")
		update_button.pressed.connect(func() -> void:
			Settings.profiles.update_current()
			_sync())
		rename_button = _button(actions, "Rename")
		rename_button.pressed.connect(func() -> void: name_requested.emit(true))
		delete_button = _button(actions, "Delete")
		delete_button.pressed.connect(func() -> void:
			Settings.profiles.delete_current()
			_sync())
		status = Rows.hint(self, "")
	Settings.changed.connect(_sync)
	_sync()


func _button(row: HBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	Tooltips.set_text(button, {"Save current": "Save current viewing settings as a new profile", "Update": "Replace the selected profile with current viewing settings", "Rename": "Rename the selected viewing profile", "Delete": "Delete the selected viewing profile"}.get(text, text))
	button.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(button)
	return button


func _sync() -> void:
	selector.clear()
	selector.add_item("Custom")
	selector.set_item_metadata(0, "")
	selector.select(0)
	for entry: Dictionary in Settings.profiles.entries:
		selector.add_item(entry["name"] + (" · Modified" if entry["id"] == Settings.profiles.active and Settings.profiles.modified() else ""))
		var index := selector.item_count - 1
		selector.set_item_metadata(index, entry["id"])
		if entry["id"] == Settings.profiles.active:
			selector.select(index)
	if manager:
		var custom: bool = Settings.profiles.active.is_empty()
		update_button.disabled = custom or not Settings.profiles.modified()
		rename_button.disabled = custom
		delete_button.disabled = custom
		status.text = Settings.profiles.error if not Settings.profiles.error.is_empty() else "Save a viewing setup. File formats, zoom, crop and library data stay separate."
