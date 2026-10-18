class_name SettingRow
extends HBoxContainer

const LABEL_WIDTH := 300
const COMPACT_LABEL_WIDTH := 40
const ROW_HEIGHT := 60
const BUTTON_WIDTH := 80
const COMPACT_BUTTON_WIDTH := 60

@export var title := ""
@export var setting: StringName
@export var compact := false


func _ready() -> void:
	custom_minimum_size.y = ROW_HEIGHT
	add_theme_constant_override("separation", 12)
	if compact:
		alignment = ALIGNMENT_CENTER
	if not title.is_empty():
		var label := Label.new()
		label.text = title
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = COMPACT_LABEL_WIDTH if compact else LABEL_WIDTH
		if not compact:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.tooltip_text = title
		if _label_expands() and not compact:
			label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(label)
	_build()
	if setting != &"":
		Settings.changed.connect(_pull)
		_pull()


func _build() -> void:
	pass


func _pull() -> void:
	pass


func _label_expands() -> bool:
	return true


func make_button(text: String, width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	button.focus_mode = FOCUS_NONE
	return button


func read() -> Variant:
	return Settings.get(setting)


func write(value: Variant) -> void:
	if setting == &"":
		return
	if typeof(Settings.get(setting)) == TYPE_INT and typeof(value) == TYPE_FLOAT:
		value = int(round(value))
	Settings.apply(setting, value)
