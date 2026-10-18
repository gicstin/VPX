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


static func music_visualizer(parent: Control) -> VBoxContainer:
	var rows := section(parent, "Resonance Field")
	toggle(rows, "Compact music visualizer", &"music_visualizer")
	dropdown(rows, "Compact display", &"music_visualizer_mode", PackedStringArray(["Compact spectrum", "Compact oscilloscope"]), PackedInt32Array([0, 2]))
	toggle(rows, "Immersive music visualizer", &"immersive_music_visualizer")
	dropdown(rows, "Scene", &"visualizer_preset", PackedStringArray(Settings.VISUALIZER_PRESETS))
	dropdown(rows, "Visual quality", &"visualizer_quality", PackedStringArray(["Automatic", "Performance", "Balanced", "High"]))
	stepper(rows, "Intensity", &"visualizer_intensity", 0.0, 1.5, 0.05, {"scale": 100.0, "suffix": "%", "resettable": true})
	stepper(rows, "Depth sensitivity", &"visualizer_sensitivity", 0.5, 4.0, 0.05, {"scale": 100.0, "suffix": "%", "resettable": true})
	stepper(rows, "Motion", &"visualizer_motion", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%", "resettable": true})
	stepper(rows, "Visual timing", &"visualizer_sync", -0.25, 0.25, 0.005, {"scale": 1000.0, "suffix": " ms", "resettable": true})
	toggle(rows, "Change scenes automatically", &"visualizer_auto_change")
	toggle(rows, "Immersive visuals over photos", &"visualizer_over_images")
	hint(rows, "Short thumbstick press cycles scenes; hold to recenter. Depth scenes show recent left/right audio history flowing from far away towards you. Photos keep the compact spectrum unless enabled above. Positive timing advances the visuals.")
	return rows
