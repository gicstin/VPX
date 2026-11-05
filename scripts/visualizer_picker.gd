extends Dropdown

signal scene_selected

const THUMBNAILS := preload("res://assets/visualizer_previews.png")
const TILE_SIZE := Vector2(160, 90)

var external_button: Button
var selected: Button
var menu: VBoxContainer
var disabled_button: Button
var controls_button: Button
var starred_filter: Button
var random_button: Button
var overlay_toggle: CheckButton
var gallery_built := false
var pulled_state: Array = []
var pulled_favorites := PackedStringArray()
var tuning: VBoxContainer:
	get:
		_ensure_gallery()
		return _tuning
var adjustments: Dictionary:
	get:
		_ensure_gallery()
		return _adjustments
var gallery: ScrollContainer:
	get:
		_ensure_gallery()
		return _gallery
var tiles: Array[Button]:
	get:
		_ensure_gallery()
		return _tiles
var favorite_buttons: Array[Button]:
	get:
		_ensure_gallery()
		return _favorite_buttons
var empty_favorites: Label:
	get:
		_ensure_gallery()
		return _empty_favorites
var mix_controls: VBoxContainer:
	get:
		_ensure_gallery()
		return _mix_controls
var _tuning: VBoxContainer
var _adjustments: Dictionary = {}
var _gallery: ScrollContainer
var _tiles: Array[Button] = []
var _favorite_buttons: Array[Button] = []
var _empty_favorites: Label
var _mix_controls: VBoxContainer


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
	selected.toggle_mode = true
	selected.pressed.connect(_toggle_gallery)
	menu = VBoxContainer.new()
	menu.visible = false
	column.add_child(menu)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	menu.add_child(actions)
	disabled_button = make_button("Disable visuals", 0)
	Tooltips.set_text(disabled_button, "Turn off immersive visualization")
	disabled_button.size_flags_horizontal = SIZE_EXPAND_FILL
	disabled_button.toggle_mode = true
	disabled_button.pressed.connect(func() -> void:
		Settings.apply("immersive_music_visualizer", false)
		close())
	actions.add_child(disabled_button)
	starred_filter = make_button("", 60)
	starred_filter.toggle_mode = true
	starred_filter.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	starred_filter.add_theme_constant_override("icon_max_width", VpxTheme.ICON_SIZE)
	starred_filter.toggled.connect(func(on: bool) -> void:
		Settings.apply("visualizer_starred_only", on)
		_scroll_gallery_top())
	actions.add_child(starred_filter)
	random_button = make_button("", 60)
	random_button.icon = VpxTheme.icon("dice")
	random_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_button.add_theme_constant_override("icon_max_width", VpxTheme.ICON_SIZE)
	random_button.toggle_mode = true
	random_button.toggled.connect(func(on: bool) -> void:
		Settings.apply("visualizer_shuffle", on))
	actions.add_child(random_button)
	controls_button = make_button("Controls ▾", 0)
	controls_button.toggle_mode = true
	Tooltips.set_text(controls_button, "Adjust visualizer response and display")
	controls_button.toggled.connect(func(on: bool) -> void:
		tuning.visible = on
		controls_button.text = "Controls ▴" if on else "Controls ▾"
		_scroll_gallery_top())
	actions.add_child(controls_button)
	overlay_toggle = CheckButton.new()
	overlay_toggle.text = "Overlay on media"
	overlay_toggle.custom_minimum_size.y = 44
	overlay_toggle.focus_mode = FOCUS_NONE
	Tooltips.set_text(overlay_toggle, "Keep media visible. Visuals follow video sound or music playing over a photo or panorama.")
	overlay_toggle.toggled.connect(func(on: bool) -> void:
		Settings.apply("visualizer_overlay", on)
		if on:
			Settings.apply("immersive_music_visualizer", true)
		_scroll_gallery_top())
	menu.add_child(overlay_toggle)


func _on_shown_page() -> bool:
	return true


func _scroll_gallery_top() -> void:
	if gallery_built:
		_gallery.set_deferred("scroll_vertical", 0)


func _ensure_gallery() -> void:
	if gallery_built:
		return
	gallery_built = true
	_build_gallery()
	pulled_state = []
	_pull()


func _build_gallery() -> void:
	_tuning = VBoxContainer.new()
	_tuning.visible = false
	_tuning.add_theme_constant_override("separation", 6)
	_adjustment(_tuning, "Intensity", &"visualizer_intensity", 0.0, 1.5, 0.05, 100.0, "%")
	_adjustment(_tuning, "Sensitivity", &"visualizer_sensitivity", 0.5, 4.0, 0.05, 100.0, "%")
	_adjustment(_tuning, "Motion", &"visualizer_motion", 0.0, 1.0, 0.05, 100.0, "%")
	_adjustment(_tuning, "Zoom", &"visualizer_zoom", Settings.VISUALIZER_ZOOM_MIN, Settings.VISUALIZER_ZOOM_MAX, 0.05, 100.0, "%")
	_gallery = ScrollContainer.new()
	_gallery.custom_minimum_size.y = 560
	_gallery.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_gallery.visible = false
	menu.add_child(_gallery)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var scene_list := VBoxContainer.new()
	scene_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_gallery.add_child(scene_list)
	_mix_controls = VBoxContainer.new()
	_mix_controls.add_theme_constant_override("separation", 6)
	scene_list.add_child(_mix_controls)
	var mix_title := Label.new()
	mix_title.text = "MEDIA MIX"
	_mix_controls.add_child(mix_title)
	var mixes := preload("res://scripts/visualizer_mix.gd").new()
	_mix_controls.add_child(mixes)
	_adjustment(_mix_controls, "Visual opacity", &"visualizer_overlay_opacity", 0.0, 1.0, 0.01, 100.0, "%")
	_adjustment(_mix_controls, "Backdrop dim", &"visualizer_background_dim", 0.0, 1.0, 0.01, 100.0, "%")
	_adjustment(_mix_controls, "Atmosphere", &"visualizer_atmosphere", 0.0, 1.0, 0.01, 100.0, "%")
	Tooltips.set_text(_adjustments[&"visualizer_overlay_opacity"], "0% hides the visual layer; 100% gives full-strength visuals")
	Tooltips.set_text(_adjustments[&"visualizer_background_dim"], "Darken media behind the visuals without changing picture settings")
	Tooltips.set_text(_adjustments[&"visualizer_atmosphere"], "Blend the scene's sky into the backdrop; 0% keeps the media clear")
	scene_list.add_child(_tuning)
	_option(_tuning, "Quality", &"visualizer_quality", PackedStringArray(["Automatic", "Performance", "Balanced", "High"]))
	_adjustment(_tuning, "Timing", &"visualizer_sync", -0.25, Settings.visualizer_advance_limit(), 0.005, 1000.0, " ms")
	_option(_tuning, "Grab moves", &"visualizer_grab_mode", PackedStringArray(["Default", "Scene + audio", "Audio only"]), PackedInt32Array(), true)
	_toggle(_tuning, "Auto scene change", &"visualizer_auto_change")
	_toggle(_tuning, "Compact visualizer", &"music_visualizer")
	_option(_tuning, "Compact display", &"music_visualizer_mode", PackedStringArray(["Spectrum", "Oscilloscope"]), PackedInt32Array([0, 2]), true)
	_empty_favorites = Label.new()
	_empty_favorites.text = "No starred presets.\nTurn off Starred only, then star your favorites."
	_empty_favorites.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scene_list.add_child(_empty_favorites)
	scene_list.add_child(grid)
	for index in options.size():
		var tile := SceneTile.new()
		tile.custom_minimum_size = Vector2(200, 0)
		tile.size_flags_horizontal = SIZE_EXPAND_FILL
		Tooltips.set_text(tile, options[index])
		if index >= Settings.VISUALIZER_STUDIO_START:
			Tooltips.set_text(tile, Tooltips.get_text(tile) + "\n" + Settings.VISUALIZER_STUDIO_GUIDES[index - Settings.VISUALIZER_STUDIO_START])
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
		tile.add_theme_stylebox_override("focus", VpxTheme.focus_ring(VpxTheme.RADIUS, 0))
		tile.toggle_mode = true
		tile.pressed.connect(func() -> void:
			scene_selected.emit()
			write(index)
			Settings.apply("immersive_music_visualizer", true)
			_pull())
		grid.add_child(tile)
		_tiles.append(tile)
		var favorite := Button.new()
		favorite.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		favorite.offset_left = -48
		favorite.offset_right = -4
		favorite.offset_top = 4
		favorite.offset_bottom = 48
		favorite.custom_minimum_size = Vector2(44, 44)
		favorite.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		favorite.focus_mode = FOCUS_NONE
		favorite.mouse_filter = MOUSE_FILTER_STOP
		favorite.toggle_mode = true
		favorite.theme_type_variation = &"TileStar"
		favorite.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		favorite.expand_icon = false
		favorite.pressed.connect(func() -> void: Settings.toggle_visualizer_favorite(index))
		tile.add_child(favorite)
		_favorite_buttons.append(favorite)


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
	Tooltips.set_text(slider, "Positive timing advances visuals up to the available audio output latency" if key == &"visualizer_sync" else title)
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
	Tooltips.set_text(reset, "Reset " + title.to_lower() + " to default")
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
	_adjustments[key] = slider


func _option(parent: VBoxContainer, title: String, key: StringName, labels: PackedStringArray, values := PackedInt32Array(), inline_choices := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 130
	row.add_child(label)
	if inline_choices:
		var group := ButtonGroup.new()
		for index in labels.size():
			var choice := Button.new()
			choice.text = labels[index]
			Tooltips.set_text(choice, title + ": " + labels[index])
			if key == &"visualizer_grab_mode" and index == Settings.VisualizerGrab.DEFAULT:
				Tooltips.set_text(choice, "Scene + audio on desktop; audio only in VR")
			choice.custom_minimum_size.y = 40
			choice.size_flags_horizontal = SIZE_EXPAND_FILL
			choice.focus_mode = FOCUS_NONE
			choice.toggle_mode = true
			choice.button_group = group
			row.add_child(choice)
			var value := values[index] if not values.is_empty() else index
			choice.pressed.connect(func() -> void: Settings.apply(key, value))
			var pull := func() -> void: choice.set_pressed_no_signal(int(Settings.get(key)) == value)
			Settings.changed.connect(pull)
			pull.call()
		return
	var choice := OptionButton.new()
	Tooltips.set_text(choice, "Choose " + title.to_lower())
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
	Tooltips.set_text(toggle, {&"visualizer_auto_change": "Change immersive scene automatically during music playback", &"music_visualizer": "Show the compact spectrum or oscilloscope in the music player"}.get(key, title))
	toggle.custom_minimum_size.y = 40
	toggle.focus_mode = FOCUS_NONE
	parent.add_child(toggle)
	toggle.toggled.connect(func(on: bool) -> void: Settings.apply(key, on))
	var pull := func() -> void: toggle.set_pressed_no_signal(bool(Settings.get(key)))
	Settings.changed.connect(pull)
	pull.call()


func _pull() -> void:
	var index := clampi(int(read()), 0, options.size() - 1)
	var enabled := Settings.immersive_music_visualizer
	var state := [index, enabled, Settings.visualizer_overlay, Settings.visualizer_starred_only, Settings.visualizer_shuffle]
	var label := options[index] if enabled else "Disabled"
	selected.set_pressed_no_signal(menu.visible)
	if external_button == null:
		selected.text = label + (" ▴" if menu.visible else " ▾")
	Tooltips.set_text(selected, ("Hide" if menu.visible else "Show") + " immersive visualizer list · " + label + (" · Overlay on media" if Settings.visualizer_overlay else ""))
	if state == pulled_state and pulled_favorites == Settings.visualizer_favorites:
		if gallery_built:
			_tiles[index].set_pressed_no_signal(enabled)
		return
	pulled_state = state
	pulled_favorites = Settings.visualizer_favorites.duplicate()
	overlay_toggle.set_pressed_no_signal(Settings.visualizer_overlay)
	disabled_button.set_pressed_no_signal(not enabled)
	starred_filter.set_pressed_no_signal(Settings.visualizer_starred_only)
	starred_filter.icon = VpxTheme.icon("star" if Settings.visualizer_starred_only else "star_outline")
	Tooltips.set_text(starred_filter, "Starred only: " + ("On" if Settings.visualizer_starred_only else "Off"))
	random_button.set_pressed_no_signal(Settings.visualizer_shuffle)
	Tooltips.set_text(random_button, "Random " + ("favourites" if Settings.visualizer_starred_only else "visualizers") + ": " + ("On" if Settings.visualizer_shuffle else "Off") + " · Next and previous pick without repeats until the list is exhausted")
	random_button.disabled = Settings.visualizer_starred_only and Settings.visualizer_favorites.size() < 2
	if not gallery_built:
		return
	_mix_controls.visible = Settings.visualizer_overlay
	_empty_favorites.visible = Settings.visualizer_starred_only and Settings.visualizer_favorites.is_empty()
	for i in _tiles.size():
		var starred: bool = options[i] in Settings.visualizer_favorites
		_tiles[i].visible = not Settings.visualizer_starred_only or starred
		_tiles[i].set_pressed_no_signal(enabled and i == index)
		_favorite_buttons[i].icon = VpxTheme.icon("star" if starred else "star_outline", 28)
		_favorite_buttons[i].set_pressed_no_signal(starred)
		Tooltips.set_text(_favorite_buttons[i], ("Unstar " if starred else "Star ") + options[i])


func close() -> void:
	controls_button.set_pressed(false)
	menu.hide()
	if gallery_built:
		_gallery.hide()
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
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(gallery) and gallery.visible:
		var tile := tiles[clampi(int(read()), 0, tiles.size() - 1)]
		if Settings.immersive_music_visualizer and tile.visible and not Settings.visualizer_overlay:
			gallery.ensure_control_visible(tile)
		else:
			gallery.scroll_vertical = 0


static func thumbnail(index: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = THUMBNAILS
	texture.filter_clip = true
	texture.region = Rect2(Vector2(index % 8, index / 8) * TILE_SIZE, TILE_SIZE)
	return texture


class SceneTile extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		var render_scale := maxf(0.001, absf(get_global_transform_with_canvas().get_scale().x))
		var width := minf(520.0 * VpxTheme.text_size, maxf(1.0, get_viewport_rect().size.x / render_scale - 56.0))
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = width
		box.add_theme_constant_override("separation", roundi(12.0 * VpxTheme.text_size))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parts := for_text.split("\n", true, 1)
		var title := Label.new()
		title.text = parts[0]
		title.custom_minimum_size.x = width
		title.add_theme_color_override("font_color", VpxTheme.TEXT)
		title.theme_type_variation = &"Title"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(title)
		if parts.size() > 1:
			var guide := Label.new()
			guide.text = parts[1].replace(" · ", "\n")
			guide.custom_minimum_size.x = width
			guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			guide.add_theme_color_override("font_color", VpxTheme.TEXT)
			guide.theme_type_variation = &"TooltipLabel"
			guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(guide)
		return box
