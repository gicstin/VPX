extends HBoxContainer

const MIXES := [["Subtle", 0.3, 0.0, 0.0], ["Balanced", 0.65, 0.15, 0.15], ["Vivid", 1.0, 0.45, 0.35]]

var activate_overlay := false
var buttons: Array[Button] = []
var off_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if activate_overlay:
		var label := Label.new()
		label.text = "Visuals"
		add_child(label)
		off_button = _button("Off")
		Tooltips.set_text(off_button, "Disable immersive visuals and keep the photo and music playing")
		off_button.pressed.connect(func() -> void:
			Settings.apply("immersive_music_visualizer", false)
			_pull())
	for index in MIXES.size():
		var entry: Array = MIXES[index]
		var button := _button(entry[0])
		Tooltips.set_text(button, "Opacity %d%% · Backdrop dim %d%% · Atmosphere %d%%" % [entry[1] * 100, entry[2] * 100, entry[3] * 100])
		button.pressed.connect(func() -> void: _choose(index))
		buttons.append(button)
	Settings.changed.connect(_pull)
	_pull()


func _button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 44 if activate_overlay else 60
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	add_child(button)
	return button


func _choose(index: int) -> void:
	var entry: Array = MIXES[index]
	Settings.apply("visualizer_overlay_opacity", entry[1])
	Settings.apply("visualizer_background_dim", entry[2])
	Settings.apply("visualizer_atmosphere", entry[3])
	if activate_overlay:
		Settings.apply("visualizer_overlay", true)
		Settings.apply("immersive_music_visualizer", true)
	_pull()


func _pull() -> void:
	var enabled := not activate_overlay or (Settings.visualizer_overlay and Settings.immersive_music_visualizer)
	if off_button != null:
		off_button.set_pressed_no_signal(not enabled)
	for index in buttons.size():
		var entry: Array = MIXES[index]
		buttons[index].set_pressed_no_signal(enabled and is_equal_approx(Settings.visualizer_overlay_opacity, entry[1]) and is_equal_approx(Settings.visualizer_background_dim, entry[2]) and is_equal_approx(Settings.visualizer_atmosphere, entry[3]))
