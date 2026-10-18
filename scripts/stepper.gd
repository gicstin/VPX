class_name Stepper
extends SettingRow

signal value_changed(value: float)

const REPEAT_DELAY := 0.4
const REPEAT_INTERVAL := 0.06
const FAST_AFTER := 1.5
const SYMBOL_FONT_SIZE := 34

@export var min_value := 0.0
@export var max_value := 1.0
@export var step := 1.0
@export var fast_step := 0.0
@export var display_scale := 1.0
@export var decimals := 0
@export var suffix := ""
@export var resettable := false

var value := 0.0
var direction := 0
var hold_time := 0.0
var repeat_time := 0.0
var value_label: Label


func _build() -> void:
	var button_width := COMPACT_BUTTON_WIDTH if compact else BUTTON_WIDTH
	var minus := make_button("−", button_width)
	var plus := make_button("+", button_width)
	for button in [minus, plus]:
		button.add_theme_font_size_override("font_size", SYMBOL_FONT_SIZE)
	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = MOUSE_FILTER_IGNORE
	value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	var field := PanelContainer.new()
	field.theme_type_variation = &"Segment"
	field.custom_minimum_size = Vector2(90 if compact else 170, ROW_HEIGHT)
	var stack := Control.new()
	stack.custom_minimum_size = field.custom_minimum_size
	stack.mouse_filter = MOUSE_FILTER_IGNORE
	field.add_child(stack)
	stack.add_child(value_label)
	var value_hit := Button.new()
	value_hit.flat = true
	value_hit.theme_type_variation = &"ValueButton"
	value_hit.focus_mode = FOCUS_NONE
	value_hit.tooltip_text = "Reset"
	value_hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	value_hit.pressed.connect(_reset_value)
	stack.add_child(value_hit)
	add_child(minus)
	add_child(field)
	add_child(plus)
	if resettable:
		var reset := make_button("", COMPACT_BUTTON_WIDTH)
		reset.theme_type_variation = &"FlatIcon"
		reset.icon = VpxTheme.icon("reset", 26)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.pressed.connect(func() -> void: Settings.reset(PackedStringArray([setting])))
		add_child(reset)
	_bind_hold(minus, -1)
	_bind_hold(plus, 1)
	show_value(min_value)


func _bind_hold(button: Button, dir: int) -> void:
	button.button_down.connect(func() -> void:
		direction = dir
		hold_time = 0.0
		repeat_time = 0.0
		nudge(dir * step))
	button.button_up.connect(_release)
	button.mouse_exited.connect(_release)


func _release() -> void:
	direction = 0


func _process(delta: float) -> void:
	if direction == 0:
		return
	hold_time += delta
	if hold_time < REPEAT_DELAY:
		return
	repeat_time += delta
	if repeat_time < REPEAT_INTERVAL:
		return
	repeat_time = 0.0
	var amount := fast_step if fast_step > 0.0 and hold_time > FAST_AFTER else step
	nudge(direction * amount)


func nudge(amount: float) -> void:
	var next := clampf(snappedf(value + amount, step), min_value, max_value)
	if is_equal_approx(next, value):
		return
	show_value(next)
	value_changed.emit(value)
	write(value)


func _reset_value() -> void:
	if setting == &"" or not Settings.defaults.has(setting):
		return
	Settings.reset(PackedStringArray([setting]))


func show_value(new_value: float) -> void:
	value = clampf(new_value, min_value, max_value)
	value_label.text = ("%." + str(decimals) + "f") % (value * display_scale) + suffix


func _pull() -> void:
	show_value(float(read()))
