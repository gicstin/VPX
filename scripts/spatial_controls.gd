extends VBoxContainer

signal name_requested

const Rows := preload("res://scripts/rows.gd")
const POLL_INTERVAL := 1.0

var picker: Picker
var advanced: VBoxContainer
var status: Label
var update_button: Button
var delete_button: Button
var file_button: Button
var poll_time := 0.0
var file_stamp := 0
var notice := ""


class Picker:
	extends SettingRow

	var button: OptionButton
	var names := PackedStringArray()

	func _build() -> void:
		button = OptionButton.new()
		Tooltips.set_text(button, "Choose a spatial sound preset")
		button.custom_minimum_size = Vector2(Dropdown.MENU_WIDTH, ROW_HEIGHT)
		button.focus_mode = FOCUS_NONE
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		button.fit_to_longest_item = false
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.item_selected.connect(func(index: int) -> void: Settings.select_spatial_preset(names[index]))
		add_child(button)

	func _pull() -> void:
		if not SpatialPresets.exists(Settings.spatial_preset):
			Settings.select_spatial_preset(SpatialPresets.CURRENT)
			return
		names = SpatialPresets.all_names()
		button.clear()
		for name in names:
			var modified: bool = name == Settings.spatial_preset and not Settings.spatial_overrides.is_empty()
			button.add_item(name + (" · Modified" if modified else ""))
		button.select(names.find(Settings.spatial_preset))


class ParamStepper:
	extends Stepper

	var key := ""

	func read() -> Variant:
		return Settings.spatial_values()[key]

	func write(new_value: Variant) -> void:
		Settings.set_spatial_value(key, new_value)

	func _reset_value() -> void:
		Settings.reset_spatial_value(key)


class ParamSwitch:
	extends Switch

	var key := ""

	func read() -> Variant:
		return Settings.spatial_values()[key]

	func write(new_value: Variant) -> void:
		Settings.set_spatial_value(key, new_value)


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	picker = Picker.new()
	picker.title = "Spatial sound preset"
	picker.setting = &"spatial_preset"
	add_child(picker)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	var save := _button(actions, "Save as…", "Save the current sound settings as a new preset")
	save.pressed.connect(func() -> void: name_requested.emit())
	update_button = _button(actions, "Update", "Replace the selected preset with the current sound settings")
	update_button.pressed.connect(func() -> void: _report(Settings.store_spatial_preset(Settings.spatial_preset), "Preset updated"))
	delete_button = _button(actions, "Delete", "Delete the selected saved preset")
	delete_button.pressed.connect(func() -> void: _report(Settings.delete_spatial_preset(), "Preset deleted"))
	file_button = _button(actions, "Preset file", "Show the preset file in the file manager. Saved presets can be edited there")
	file_button.pressed.connect(func() -> void: OS.shell_show_in_file_manager(SpatialPresets.file_path()))
	file_button.visible = not OS.has_feature("android")
	Rows.toggle(self, "Fine-tune sound", &"spatial_advanced")
	advanced = VBoxContainer.new()
	advanced.add_theme_constant_override("separation", 6)
	add_child(advanced)
	_stepper("LFE (sub) level", "lfe_gain", 0.0, 2.0, 0.05, {"decimals": 2, "suffix": "×"})
	_stepper("Bass boost", "bass_db", -6.0, 12.0, 0.5, {"decimals": 1, "suffix": " dB"})
	_stepper("Bass boost up to", "bass_hz", 60.0, 250.0, 10.0, {"suffix": " Hz"})
	_stepper("Surround level", "surround_level", 0.8, 3.0, 0.05, {"decimals": 2, "suffix": "×"})
	_stepper("Head shadow", "shadow_strength", 0.0, 1.5, 0.05, {"scale": 100.0, "suffix": "%"})
	_stepper("Head delay", "itd_scale", 0.0, 1.5, 0.05, {"scale": 100.0, "suffix": "%"})
	_stepper("Rear softening", "rear_depth", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	var normalize := ParamSwitch.new()
	normalize.key = "normalize_downmix"
	normalize.title = "Keep stereo downmix level steady"
	normalize.setting = &"spatial_overrides"
	advanced.add_child(normalize)
	status = Rows.hint(self, "")
	file_stamp = SpatialPresets.file_stamp()
	Settings.changed.connect(_sync)
	_sync()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	poll_time += delta
	if poll_time < POLL_INTERVAL:
		return
	poll_time = 0.0
	var stamp := SpatialPresets.file_stamp()
	if stamp != file_stamp:
		file_stamp = stamp
		Settings.changed.emit()


func save_named(text: String) -> void:
	_report(Settings.store_spatial_preset(text), "Saved as “%s”" % text.strip_edges())


func _stepper(title: String, key: String, min_value: float, max_value: float, step: float, options: Dictionary) -> void:
	var row := ParamStepper.new()
	row.key = key
	row.title = title
	row.setting = &"spatial_overrides"
	row.min_value = min_value
	row.max_value = max_value
	row.step = step
	row.display_scale = options.get("scale", 1.0)
	row.decimals = options.get("decimals", 0)
	row.suffix = options.get("suffix", "")
	advanced.add_child(row)


func _button(row: HBoxContainer, text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	Tooltips.set_text(button, tip)
	button.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.focus_mode = FOCUS_NONE
	row.add_child(button)
	return button


func _report(error: String, done: String) -> void:
	notice = error if not error.is_empty() else done
	_sync()


func _sync() -> void:
	var user := not SpatialPresets.is_builtin(Settings.spatial_preset)
	update_button.disabled = not user or Settings.spatial_overrides.is_empty()
	delete_button.disabled = not user
	file_button.disabled = not SpatialPresets.file_exists()
	advanced.visible = Settings.spatial_advanced
	var text := notice
	if text.is_empty():
		text = "Presets shape 5.1 / 7.1 surround and 360° sound; stereo plays unchanged. Classic restores the 0.0.10 sound."
		if SpatialPresets.file_exists():
			text += "\nSaved presets: " + SpatialPresets.file_path()
	status.text = text
	notice = ""
