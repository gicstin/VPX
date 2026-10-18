extends Dropdown

signal scene_selected

const THUMBNAILS := preload("res://assets/visualizer_previews.png")
const TILE_SIZE := Vector2(256, 144)

var external_button: Button
var selected: Button
var menu: VBoxContainer
var disabled_button: Button
var tuning: VBoxContainer
var more_controls: VBoxContainer
var adjustments: Dictionary = {}
var gallery: ScrollContainer
var tiles: Array[Button] = []


func _ready() -> void:
	super._ready()
	if external_button != null:
		custom_minimum_size.y = 0
		hide()


func _build() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.custom_minimum_size.x = MENU_WIDTH
	add_child(column)
	selected = external_button
	if selected == null:
		selected = make_button("", MENU_WIDTH)
		selected.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(selected)
	selected.pressed.connect(_toggle_gallery)
	menu = VBoxContainer.new()
	menu.visible = false
	column.add_child(menu)
	disabled_button = make_button("Disable Visualisation", MENU_WIDTH)
	disabled_button.toggle_mode = true
	disabled_button.pressed.connect(func() -> void:
		Settings.apply("immersive_music_visualizer", false)
		close())
	menu.add_child(disabled_button)
	tuning = VBoxContainer.new()
	tuning.add_theme_constant_override("separation", 6)
	menu.add_child(tuning)
	_adjustment(tuning, "Intensity", &"visualizer_intensity", 0.0, 1.5, 0.05, 100.0, "%")
	_adjustment(tuning, "Sensitivity", &"visualizer_sensitivity", 0.5, 4.0, 0.05, 100.0, "%")
	_adjustment(tuning, "Motion", &"visualizer_motion", 0.0, 1.0, 0.05, 100.0, "%")
	var more := make_button("More controls ▾", MENU_WIDTH)
	more.custom_minimum_size.y = 40
	tuning.add_child(more)
	more_controls = VBoxContainer.new()
	more_controls.visible = false
	more_controls.add_theme_constant_override("separation", 6)
	more.pressed.connect(func() -> void:
		more_controls.visible = not more_controls.visible
		more.text = "Fewer controls ▴" if more_controls.visible else "More controls ▾"
		if more_controls.visible:
			gallery.set_deferred("scroll_vertical", 0))
	_option(more_controls, "Quality", &"visualizer_quality", PackedStringArray(["Automatic", "Performance", "Balanced", "High"]))
	_adjustment(more_controls, "Timing", &"visualizer_sync", -0.25, Settings.visualizer_advance_limit(), 0.005, 1000.0, " ms")
	_toggle(more_controls, "Auto scene change", &"visualizer_auto_change")
	_toggle(more_controls, "Compact visualizer", &"music_visualizer")
	_option(more_controls, "Compact display", &"music_visualizer_mode", PackedStringArray(["Spectrum", "Oscilloscope"]), PackedInt32Array([0, 2]))
	tuning.minimum_size_changed.connect(_resize_gallery)
	gallery = ScrollContainer.new()
	gallery.custom_minimum_size.y = 560
	gallery.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gallery.visible = false
	menu.add_child(gallery)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var scene_list := VBoxContainer.new()
	scene_list.size_flags_horizontal = SIZE_EXPAND_FILL
	gallery.add_child(scene_list)
	scene_list.add_child(more_controls)
	scene_list.add_child(grid)
	for index in options.size():
		var tile := SceneTile.new()
		tile.custom_minimum_size = Vector2(200, 0)
		tile.size_flags_horizontal = SIZE_EXPAND_FILL
		tile.tooltip_text = options[index]
		if index >= Settings.VISUALIZER_STUDIO_START:
			tile.tooltip_text += "\n" + Settings.VISUALIZER_STUDIO_GUIDES[index - Settings.VISUALIZER_STUDIO_START]
		var contents := VBoxContainer.new()
		contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_left = 4
		contents.offset_right = -4
		contents.offset_top = 4
		contents.offset_bottom = -4
		contents.mouse_filter = MOUSE_FILTER_IGNORE
		tile.add_child(contents)
		var preview := TextureRect.new()
		preview.texture = thumbnail(index)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.custom_minimum_size.y = 108
		contents.resized.connect(func() -> void:
			preview.custom_minimum_size.y = contents.size.x * TILE_SIZE.y / TILE_SIZE.x)
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = MOUSE_FILTER_IGNORE
		contents.add_child(preview)
		var caption := PanelContainer.new()
		caption.mouse_filter = MOUSE_FILTER_IGNORE
		caption.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.BACKGROUND, 6, 8, 4))
		contents.add_child(caption)
		var label := Label.new()
		label.text = options[index]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", VpxTheme.TEXT)
		label.add_theme_font_size_override("font_size", VpxTheme.SMALL_FONT_SIZE)
		caption.add_child(label)
		contents.minimum_size_changed.connect(func() -> void:
			tile.custom_minimum_size.y = contents.get_combined_minimum_size().y + 8.0)
		tile.focus_mode = FOCUS_NONE
		tile.toggle_mode = true
		tile.pressed.connect(func() -> void:
			scene_selected.emit()
			write(index)
			Settings.apply("immersive_music_visualizer", true)
			close())
		grid.add_child(tile)
		tiles.append(tile)


func _adjustment(parent: VBoxContainer, title: String, key: StringName, low: float, high: float, increment: float, display_scale: float, suffix: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = increment
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 100
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.tooltip_text = "Positive timing advances visuals up to the available audio output latency" if key == &"visualizer_sync" else title
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 80
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var reset := Button.new()
	reset.custom_minimum_size = Vector2(40, 40)
	reset.theme_type_variation = &"FlatIcon"
	reset.icon = VpxTheme.icon("reset", 26)
	reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset.focus_mode = FOCUS_NONE
	reset.tooltip_text = "Reset " + title.to_lower() + " to default"
	reset.pressed.connect(func() -> void: Settings.reset(PackedStringArray([key])))
	row.add_child(reset)
	var pull := func() -> void:
		if key == &"visualizer_sync":
			slider.max_value = Settings.visualizer_advance_limit()
		slider.set_value_no_signal(float(Settings.get(key)))
		value.text = "%d%s" % [roundi(slider.value * display_scale), suffix]
	Settings.changed.connect(pull)
	slider.value_changed.connect(func(amount: float) -> void: Settings.apply(key, amount))
	pull.call()
	adjustments[key] = slider


func _option(parent: VBoxContainer, title: String, key: StringName, labels: PackedStringArray, values := PackedInt32Array()) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var choice := OptionButton.new()
	choice.custom_minimum_size.y = 40
	choice.size_flags_horizontal = SIZE_EXPAND_FILL
	choice.focus_mode = FOCUS_NONE
	for text in labels:
		choice.add_item(text)
	row.add_child(choice)
	choice.item_selected.connect(func(index: int) -> void: Settings.apply(key, values[index] if not values.is_empty() else index))
	var pull := func() -> void:
		var index := values.find(int(Settings.get(key))) if not values.is_empty() else int(Settings.get(key))
		choice.select(clampi(index, 0, labels.size() - 1))
	Settings.changed.connect(pull)
	pull.call()


func _toggle(parent: VBoxContainer, title: String, key: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.custom_minimum_size.y = 40
	toggle.focus_mode = FOCUS_NONE
	parent.add_child(toggle)
	toggle.toggled.connect(func(on: bool) -> void: Settings.apply(key, on))
	var pull := func() -> void: toggle.set_pressed_no_signal(bool(Settings.get(key)))
	Settings.changed.connect(pull)
	pull.call()


func _resize_gallery() -> void:
	if gallery != null:
		gallery.custom_minimum_size.y = maxf(180.0, 560.0 - tuning.get_combined_minimum_size().y)


func _pull() -> void:
	var index := clampi(int(read()), 0, options.size() - 1)
	var enabled := Settings.immersive_music_visualizer
	var label := options[index] if enabled else "Disabled"
	if external_button == null:
		selected.text = label + " ▾"
	else:
		selected.set_pressed_no_signal(enabled)
	selected.tooltip_text = "Immersive music visualizer · " + label + " · Choose a scene or Disable Visualisation"
	disabled_button.set_pressed_no_signal(not enabled)
	for i in tiles.size():
		tiles[i].set_pressed_no_signal(enabled and i == index)


func close() -> void:
	menu.hide()
	gallery.hide()
	if external_button != null:
		hide()
	_pull()


func _toggle_gallery() -> void:
	if menu.visible:
		close()
		return
	show()
	menu.show()
	gallery.show()
	_pull()
	_resize_gallery()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(gallery) and gallery.visible:
		gallery.scroll_vertical = int(tiles[clampi(int(read()), 0, tiles.size() - 1)].position.y) if Settings.immersive_music_visualizer else 0


static func thumbnail(index: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = THUMBNAILS
	texture.filter_clip = true
	texture.region = Rect2(Vector2(index % 8, index / 8) * TILE_SIZE, TILE_SIZE)
	return texture


class SceneTile extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		var width := minf(520.0 * VpxTheme.text_size, maxf(200.0, get_viewport_rect().size.x - 48.0))
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = width
		box.add_theme_constant_override("separation", roundi(12.0 * VpxTheme.text_size))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parts := for_text.split("\n", true, 1)
		var title := Label.new()
		title.text = parts[0]
		title.custom_minimum_size.x = width
		title.add_theme_color_override("font_color", VpxTheme.TEXT)
		title.add_theme_font_size_override("font_size", VpxTheme.TITLE_FONT_SIZE)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(title)
		if parts.size() > 1:
			var guide := Label.new()
			guide.text = parts[1].replace(" · ", "\n")
			guide.custom_minimum_size.x = width
			guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			guide.add_theme_color_override("font_color", VpxTheme.TEXT)
			guide.add_theme_font_size_override("font_size", VpxTheme.FONT_SIZE)
			guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(guide)
		return box
