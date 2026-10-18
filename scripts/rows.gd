extends RefCounted


static func section(parent: Control, title: String) -> VBoxContainer:
	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = &"SectionTitle"
	parent.add_child(label)
	var group := PanelContainer.new()
	group.theme_type_variation = &"Group"
	parent.add_child(group)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	group.add_child(rows)
	return rows


static func stepper(parent: Control, title: String, setting: StringName, min_value: float, max_value: float, step: float, options := {}) -> Stepper:
	var row: Stepper = load("res://scripts/zoom_control.gd").new() if setting in [&"picture_zoom", &"screen_size"] else Stepper.new()
	row.title = title
	row.setting = setting
	row.min_value = min_value
	row.max_value = max_value
	row.step = step
	row.fast_step = options.get("fast_step", 0.0)
	row.display_scale = options.get("scale", 1.0)
	row.decimals = options.get("decimals", 0)
	row.suffix = options.get("suffix", "")
	row.resettable = options.get("resettable", false)
	parent.add_child(row)
	return row


static func choice(parent: Control, title: String, setting: StringName, options: PackedStringArray) -> Choice:
	var row := Choice.new()
	row.title = title
	row.setting = setting
	row.options = options
	parent.add_child(row)
	return row


static func toggle(parent: Control, title: String, setting: StringName) -> Switch:
	var row := Switch.new()
	row.title = title
	row.setting = setting
	parent.add_child(row)
	return row


static func dropdown(parent: Control, title: String, setting: StringName, options: PackedStringArray, values := PackedInt32Array()) -> Dropdown:
	var row := Dropdown.new()
	row.title = title
	row.setting = setting
	row.options = options
	row.values = values
	parent.add_child(row)
	return row


static func hint(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Hint"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


static func view_adjust(parent: Control) -> VBoxContainer:
	var rows := section(parent, "3D & zoom")
	stepper(rows, "3D depth", &"stereo_depth", -3.0, 3.0, 0.1, {"fast_step": 0.5, "decimals": 1, "suffix": "°", "resettable": true})
	stepper(rows, "Eye height", &"stereo_vertical", -2.0, 2.0, 0.05, {"fast_step": 0.25, "decimals": 2, "suffix": "°", "resettable": true})
	toggle(rows, "Watch 3D in 2D (one eye)", &"single_eye")
	stepper(rows, "Zoom", &"picture_zoom", Settings.ZOOM_MIN, Settings.ZOOM_MAX, 0.05, {"fast_step": 0.25, "scale": 100.0, "suffix": "%", "resettable": true})
	hint(rows, "Saved for this video. Depth + pushes the 3D picture back, − brings it closer. Eye height fixes a picture that looks doubled up and down.")
	return rows


static func playback(parent: Control) -> VBoxContainer:
	var rows := section(parent, "Playback")
	dropdown(rows, "Audio speed quality", &"audio_stretch_quality", PackedStringArray(["High quality", "Fast"]))
	stepper(rows, "Speed", &"playback_speed", 0.5, 2.0, 0.25, {"decimals": 2, "suffix": "×", "resettable": true})
	choice(rows, "Sleep timer", &"sleep_timer", PackedStringArray(["Off", "15 m", "30 m", "45 m", "60 m", "90 m", "End"]))
	return rows
