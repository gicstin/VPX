class_name Dropdown
extends SettingRow

const MENU_WIDTH := 420

@export var options: PackedStringArray
@export var values: PackedInt32Array

var button: OptionButton


func _build() -> void:
	button = OptionButton.new()
	Tooltips.set_text(button, "Choose " + title.to_lower())
	for option in options:
		button.add_item(option)
	button.custom_minimum_size = Vector2(MENU_WIDTH, ROW_HEIGHT)
	button.focus_mode = FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.fit_to_longest_item = false
	button.item_selected.connect(func(index: int) -> void: write(values[index] if not values.is_empty() else index))
	add_child(button)


func _pull() -> void:
	var index := values.find(int(read())) if not values.is_empty() else int(read())
	button.select(clampi(index, 0, button.item_count - 1))
