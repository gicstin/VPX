extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames() -> void:
	for i in 3:
		await process_frame


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.hide_menu_on_play = false
	if FileAccess.file_exists(SpatialPresets.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SpatialPresets.PATH))
	var defaults := SpatialPresets.defaults()
	check(defaults["lfe_gain"] == 0.25 and defaults["surround_level"] == 1.9 and defaults["bass_db"] == 0.0 and defaults["classic_shadow"] == false, "defaults describe the current renderer")
	var classic := SpatialPresets.preset_values("Classic")
	check(classic["lfe_gain"] == 0.35 and classic["surround_level"] == 1.41 and classic["classic_shadow"] and classic["linear_delay"] and classic["normalize_downmix"], "Classic restores the 0.0.10 constants")
	check(SpatialPresets.preset_values("Current") == defaults and SpatialPresets.preset_values("Missing") == defaults, "Current and unknown names resolve to defaults")
	var dirty := SpatialPresets.sanitize({"lfe_gain": 99, "bass_db": NAN, "bass_hz": "loud", "unknown": 1, "linear_delay": 1, 5: 3.0, "ild": -4})
	check(dirty == {"lfe_gain": 2.0, "linear_delay": true, "ild": 0.0}, "sanitize clamps, coerces and drops bad entries")
	check(SpatialPresets.sanitize("text").is_empty() and SpatialPresets.sanitize(null).is_empty(), "sanitize ignores non-dictionaries")
	check(SpatialPresets.valid_name("  My bass  ") == "My bass" and SpatialPresets.valid_name("a[b]").is_empty() and SpatialPresets.valid_name("").is_empty() and SpatialPresets.valid_name("x".repeat(33)).is_empty() and SpatialPresets.valid_name("Custom").is_empty(), "names are trimmed and restricted")
	check(not SpatialPresets.name_error("classic", false).is_empty() and not SpatialPresets.name_error("Heavy BASS", false).is_empty() and SpatialPresets.name_error("Mine", false).is_empty(), "built-in names are reserved ignoring case")
	check(SpatialPresets.user_names().is_empty() and not SpatialPresets.file_exists(), "no preset file until one is saved")

	check(SpatialPresets.save("Warm", {"lfe_gain": 0.6, "bass_db": 4.5}) == OK and SpatialPresets.file_exists(), "saving writes the preset file")
	OS.delay_msec(1100)
	var config := ConfigFile.new()
	check(config.load(SpatialPresets.PATH) == OK and config.has_section("Warm") and config.get_section_keys("Warm").size() == SpatialPresets.KEYS.size(), "file holds every key under the preset name")
	check(SpatialPresets.user_names() == PackedStringArray(["Warm"]) and SpatialPresets.preset_values("Warm")["lfe_gain"] == 0.6 and SpatialPresets.preset_values("Warm")["surround_level"] == 1.9, "saved preset reloads with defaults for the rest")
	config.set_value("Hand made", "lfe_gain", 0.9)
	config.set_value("Hand made", "bass_hz", 9999.0)
	config.set_value("Hand made", "nonsense", "x")
	config.set_value("Classic", "lfe_gain", 0.1)
	config.set_value("bad[name", "lfe_gain", 0.1)
	check(config.save(SpatialPresets.PATH) == OK, "hand edits can be written")
	check(SpatialPresets.user_names() == PackedStringArray(["Hand made", "Warm"]), "edited file is re-read and rejects built-in or malformed names")
	var hand := SpatialPresets.preset_values("Hand made")
	check(hand["lfe_gain"] == 0.9 and hand["bass_hz"] == 400.0 and not hand.has("nonsense"), "hand-written values are clamped and unknown keys ignored")
	check(SpatialPresets.preset_values("Classic")["lfe_gain"] == 0.35, "a file section cannot override a built-in preset")

	settings.apply("spatial_preset", "Classic")
	check(settings.spatial_preset == "Classic" and settings.spatial_overrides.is_empty(), "selecting a preset applies it")
	settings.set_spatial_value("bass_db", 5.0)
	check(settings.spatial_overrides == {"bass_db": 5.0} and settings.spatial_values()["bass_db"] == 5.0 and settings.spatial_values()["lfe_gain"] == 0.35, "an edit becomes an override on the preset")
	settings.set_spatial_value("lfe_gain", 0.35)
	check(settings.spatial_overrides == {"bass_db": 5.0}, "setting a value equal to the preset leaves no override")
	settings.set_spatial_value("bass_db", 99.0)
	check(settings.spatial_values()["bass_db"] == 18.0, "values are clamped")
	settings.reset_spatial_value("bass_db")
	check(settings.spatial_overrides.is_empty(), "reset restores the preset value")
	settings.apply("spatial_preset", "Nope")
	check(settings.spatial_preset == "Classic", "unknown presets are refused")

	settings.set_spatial_value("bass_db", 3.0)
	settings.apply("spatial_advanced", true)
	settings.save_config()
	check(settings.flush() == OK, "settings save")
	settings.spatial_preset = "Current"
	settings.spatial_overrides = {}
	settings.spatial_advanced = false
	settings.load_config()
	check(settings.spatial_preset == "Classic" and settings.spatial_overrides == {"bass_db": 3.0} and settings.spatial_advanced, "preset, overrides and fine-tune state persist")
	check(settings.store_spatial_preset("Mine") == "" and settings.spatial_preset == "Mine" and settings.spatial_overrides.is_empty(), "Save as stores the merged values and selects the new preset")
	var mine := SpatialPresets.preset_values("Mine")
	check(mine["bass_db"] == 3.0 and mine["lfe_gain"] == 0.35 and mine["classic_shadow"], "stored preset keeps Classic values plus the override")
	check(not settings.store_spatial_preset("Classic").is_empty() and not settings.store_spatial_preset("a;b").is_empty(), "invalid names are rejected with a message")
	check(settings.delete_spatial_preset() == "" and settings.spatial_preset == "Current" and not SpatialPresets.exists("Mine"), "deleting the selected preset falls back to Current")
	check(not settings.delete_spatial_preset().is_empty() or settings.spatial_preset == "Current", "built-ins cannot be deleted")

	settings.apply("spatial_preset", "Hand made")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SpatialPresets.PATH))
	OS.delay_msec(1100)
	settings.spatial_overrides = {"lfe_gain": 0.4}
	settings._validate_spatial()
	check(settings.spatial_preset == "Current" and settings.spatial_overrides == {"lfe_gain": 0.4}, "a preset deleted outside the app falls back to Current on load")
	settings.select_spatial_preset("Current")

	check(ClassDB.class_exists("FFmpegVideoStreamPlayback") and ClassDB.class_has_method("FFmpegVideoStreamPlayback", "set_spatial_params"), "extension exposes set_spatial_params")

	settings.apply("spatial_advanced", false)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.ui.show_main()
	main.ui.show_page(main.ui.pages.get_node(NodePath(main.ui.MEDIA_PAGE)))
	await frames()
	var controls: VBoxContainer = main.ui.spatial_controls
	check(controls != null and controls.is_inside_tree(), "Audio page holds the spatial controls")
	var picker = controls.picker
	check(picker.button.item_count == 4 and picker.button.get_item_text(picker.button.selected) == "Current", "picker lists built-in presets")
	picker.button.item_selected.emit(1)
	await frames()
	check(settings.spatial_preset == "Classic" and picker.button.get_item_text(picker.button.selected) == "Classic", "choosing a preset in the picker applies it")
	check(controls.update_button.disabled and controls.delete_button.disabled, "built-in presets cannot be updated or deleted")
	check(not controls.advanced.visible, "fine-tune rows start hidden")
	settings.apply("spatial_advanced", true)
	await frames()
	check(controls.advanced.visible and controls.advanced.get_child_count() == 8, "fine-tune shows eight parameters")
	var bass_row = null
	for row in controls.advanced.get_children():
		if row.get("key") == "bass_db":
			bass_row = row
	check(bass_row != null and is_equal_approx(bass_row.value, 0.0), "bass row shows the preset value")
	bass_row.nudge(bass_row.step)
	await frames()
	check(is_equal_approx(settings.spatial_values()["bass_db"], 0.5) and picker.button.get_item_text(picker.button.selected).ends_with("Modified"), "stepper edits the override and flags the preset modified")
	bass_row._reset_value()
	await frames()
	check(settings.spatial_overrides.is_empty() and not picker.button.get_item_text(picker.button.selected).ends_with("Modified"), "tapping the value restores the preset")
	var normalize = controls.advanced.get_child(controls.advanced.get_child_count() - 1)
	check(normalize.button.button_pressed, "downmix switch reflects Classic")
	normalize.button.button_pressed = false
	await frames()
	check(settings.spatial_overrides == {"normalize_downmix": false}, "switch writes an override")
	settings.select_spatial_preset("Current")

	controls.name_requested.emit()
	check(main.ui.keyboard.visible and main.ui.keyboard_purpose == "spatial_preset", "Save as opens the on-screen keyboard")
	settings.set_spatial_value("lfe_gain", 0.7)
	main.ui.keyboard.field.text = "Keyboard preset"
	main.ui.keyboard._submit()
	await frames()
	check(settings.spatial_preset == "Keyboard preset" and SpatialPresets.preset_values("Keyboard preset")["lfe_gain"] == 0.7, "keyboard name saves the working values")
	check(controls.status.text == "Saved as “Keyboard preset”" and controls.file_button.disabled == false, "status confirms the save")
	check(controls.delete_button.disabled == false and controls.update_button.disabled, "saved preset can be deleted and is not modified")
	settings.set_spatial_value("lfe_gain", 0.8)
	await frames()
	check(not controls.update_button.disabled, "Update enables once a saved preset is modified")
	controls.update_button.pressed.emit()
	await frames()
	check(SpatialPresets.preset_values("Keyboard preset")["lfe_gain"] == 0.8 and settings.spatial_overrides.is_empty(), "Update overwrites the saved preset")

	var rects: Array[Rect2] = []
	for child in controls.update_button.get_parent().get_children():
		if child.visible:
			rects.append(child.get_global_rect())
	var equal_height := true
	var equal_gap := true
	for i in rects.size():
		equal_height = equal_height and is_equal_approx(rects[i].size.y, rects[0].size.y)
		if i > 0:
			equal_gap = equal_gap and is_equal_approx(rects[i].position.x - rects[i - 1].end.x, rects[1].position.x - rects[0].end.x)
	check(rects.size() >= 3 and equal_height and equal_gap and is_equal_approx(rects[0].size.y, 60.0), "action buttons share one height and one gap")
	var bounds := Rect2(Vector2.ZERO, main.ui.get_viewport().get_visible_rect().size)
	check(bounds.encloses(rects[0]) or rects[0].position.x >= 0.0, "action buttons sit inside the window")

	settings.apply("spatial_advanced", true)
	await frames()
	var reference_stepper: Control = null
	var reference_dropdown: Control = null
	for node in main.ui.pages.get_node(NodePath(main.ui.MEDIA_PAGE)).find_children("*", "HBoxContainer", true, false):
		if controls.is_ancestor_of(node):
			continue
		if node.get("value_label") != null and reference_stepper == null:
			reference_stepper = node
		if node.get("button") is OptionButton and reference_dropdown == null:
			reference_dropdown = node
	var rows: Array[Control] = []
	for child in controls.advanced.get_children():
		if child.get("value_label") != null:
			rows.append(child)
	var page_rect: Rect2 = controls.get_global_rect()
	var aligned := reference_stepper != null and reference_dropdown != null and rows.size() == 7
	var steady := true
	var inside := true
	for i in rows.size():
		var rect := rows[i].get_global_rect()
		aligned = aligned and is_equal_approx(rect.size.y, reference_stepper.get_global_rect().size.y) and is_equal_approx(rect.end.x, page_rect.end.x)
		inside = inside and page_rect.encloses(rect.grow(-0.5))
		if i > 0:
			steady = steady and is_equal_approx(rect.position.y - rows[i - 1].get_global_rect().end.y, rows[1].get_global_rect().position.y - rows[0].get_global_rect().end.y)
	var picker_rect: Rect2 = picker.get_global_rect()
	aligned = aligned and is_equal_approx(picker_rect.size.y, reference_dropdown.get_global_rect().size.y) and is_equal_approx(picker_rect.end.x, page_rect.end.x)
	check(aligned and steady and inside, "preset picker and fine-tune steppers match existing rows in height, edge and gap")
	var field_edges := {}
	for row in controls.advanced.get_children():
		if row.get("key") != null and row.get("value_label") != null:
			field_edges[snappedf(row.value_label.get_global_rect().end.x, 0.5)] = true
	check(field_edges.size() == 1, "all steppers line up on the same right edge")
	settings.select_spatial_preset("Current")
	settings.delete_spatial_preset()
	SpatialPresets.delete("Keyboard preset")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
