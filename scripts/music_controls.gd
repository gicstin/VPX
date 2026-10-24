extends Control

signal collapsed_changed

const WIDTH := 640.0
const PREVIEW_SIZE := 128.0
const IDLE_OPACITY := 0.3
const OPACITY_RATE := 14.0

var player: VPXPlayer
var ui: Control
var fade_group: CanvasGroup
var panel: PanelContainer
var rows: VBoxContainer
var header: HBoxContainer
var cover_button: Button
var preview_button: Button
var preview_image: TextureRect
var preview_path := ""
var volume_button: Button
var volume_row: HBoxContainer
var volume_slider: HSlider
var volume_label: Label
var mute_button: Button
var collapsed := false
var title_label: Label
var time_label: Label
var details_label: Label
var cover_image: TextureRect
var progress: HSlider
var spectrum_view: TextureRect
var immersive_button: Button
var previous_style_button: Button
var next_style_button: Button
var scene_picker: Dropdown
var quick_mix: HBoxContainer
var play_button: Button
var favorite_button: Button
var back_button: Button
var forward_button: Button
var seeking := false
var refreshing := false
var grabbed := false
var adjusting_volume := false
var favorite_state := -1


func _init() -> void:
	theme = VpxTheme.build()
	fade_group = CanvasGroup.new()
	fade_group.self_modulate.a = IDLE_OPACITY
	add_child(fade_group)
	panel = PanelContainer.new()
	panel.theme = theme
	panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 18, 24, 16))
	fade_group.add_child(panel)
	theme_changed.connect(func() -> void: panel.theme = theme)
	panel.minimum_size_changed.connect(update_minimum_size)
	resized.connect(func() -> void: panel.size = size)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	rows.add_child(header)
	cover_button = _icon_button(header, "audio", func() -> void: set_collapsed(true), 48)
	cover_button.custom_minimum_size = Vector2(88, 88)
	cover_button.tooltip_text = "Collapse music player"
	cover_image = _artwork_image(cover_button, 14)
	var metadata := VBoxContainer.new()
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	metadata.add_theme_constant_override("separation", 2)
	header.add_child(metadata)
	title_label = Label.new()
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metadata.add_child(title_label)
	details_label = Label.new()
	details_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details_label.add_theme_font_size_override("font_size", VpxTheme.SMALL_FONT_SIZE)
	details_label.add_theme_color_override("font_color", VpxTheme.MUTED)
	rows.add_child(details_label)
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", VpxTheme.SMALL_FONT_SIZE)
	time_label.add_theme_color_override("font_color", VpxTheme.MUTED)
	metadata.add_child(time_label)
	immersive_button = _icon_button(header, "format", Callable())
	immersive_button.toggle_mode = true
	favorite_button = _favorite_button(header)
	volume_button = _icon_button(header, "volume", func() -> void: volume_row.visible = not volume_row.visible)
	volume_button.toggle_mode = true
	volume_row = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 10)
	volume_row.visible = false
	rows.add_child(volume_row)
	mute_button = _icon_button(volume_row, "volume", _toggle_mute)
	mute_button.toggle_mode = true
	volume_slider = HSlider.new()
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.custom_minimum_size.y = 40
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.tooltip_text = "Music volume"
	volume_slider.drag_started.connect(func() -> void: adjusting_volume = true)
	volume_slider.drag_ended.connect(func(_changed: bool) -> void: adjusting_volume = false)
	volume_slider.value_changed.connect(func(value: float) -> void:
		Settings.apply("volume", int(value))
		if value > 0 and Settings.muted:
			Settings.apply("muted", false))
	volume_row.add_child(volume_slider)
	volume_label = Label.new()
	volume_label.custom_minimum_size.x = 64
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(volume_label)
	spectrum_view = TextureRect.new()
	spectrum_view.custom_minimum_size.y = 72
	spectrum_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spectrum_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(spectrum_view)
	progress = HSlider.new()
	progress.custom_minimum_size.y = 40
	progress.step = 0.1
	progress.focus_mode = Control.FOCUS_NONE
	progress.tooltip_text = "Seek music"
	progress.drag_started.connect(func() -> void: seeking = true)
	progress.drag_ended.connect(func(_changed: bool) -> void: seeking = false)
	progress.value_changed.connect(func(value: float) -> void:
		if not refreshing and player != null:
			player.seek_to(value))
	rows.add_child(progress)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	rows.add_child(controls)
	previous_style_button = _icon_button(controls, "chevron_left", func() -> void: _cycle_style(-1))
	previous_style_button.tooltip_text = "Previous immersive visualizer style"
	previous_style_button.visible = false
	_icon_button(controls, "prev", func() -> void: track(-1)).tooltip_text = "Previous music track"
	back_button = _icon_button(controls, "back", func() -> void: player.seek_relative(-10.0), 34)
	back_button.tooltip_text = "Music back 10 seconds"
	play_button = _icon_button(controls, "play", func() -> void: player.toggle_pause(), 36)
	play_button.custom_minimum_size = Vector2(76, 76)
	play_button.theme_type_variation = &"PlayButton"
	forward_button = _icon_button(controls, "forward", func() -> void: player.seek_relative(10.0), 34)
	forward_button.tooltip_text = "Music forward 10 seconds"
	_icon_button(controls, "next", func() -> void: track(1)).tooltip_text = "Next music track"
	next_style_button = _icon_button(controls, "chevron_right", func() -> void: _cycle_style(1))
	next_style_button.tooltip_text = "Next immersive visualizer style"
	next_style_button.visible = false
	quick_mix = preload("res://scripts/visualizer_mix.gd").new()
	quick_mix.activate_overlay = true
	quick_mix.visible = false
	rows.add_child(quick_mix)
	scene_picker = preload("res://scripts/visualizer_picker.gd").new()
	scene_picker.scene_selected.connect(func() -> void: player.enter_immersive_music())
	scene_picker.external_button = immersive_button
	scene_picker.setting = &"visualizer_preset"
	scene_picker.options = PackedStringArray(Settings.VISUALIZER_PRESETS)
	rows.add_child(scene_picker)
	preview_button = _icon_button(panel, "audio", func() -> void: set_collapsed(false), 48)
	preview_button.custom_minimum_size = Vector2.ONE * PREVIEW_SIZE
	preview_button.visible = false
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		preview_button.add_theme_stylebox_override(state, VpxTheme.flat(VpxTheme.TRANSPARENT, 18, 0, 0))
	preview_image = _artwork_image(preview_button, 18)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		adjusting_volume = false
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var active: bool = grabbed or seeking or adjusting_volume or scene_picker.menu.visible or (hovered != null and (hovered == self or is_ancestor_of(hovered)))
	var target := 1.0 if active else IDLE_OPACITY
	fade_group.self_modulate.a = lerpf(fade_group.self_modulate.a, target, 1.0 - exp(-delta * OPACITY_RATE))
	if absf(fade_group.self_modulate.a - target) < 0.004:
		fade_group.self_modulate.a = target


func _get_minimum_size() -> Vector2:
	return panel.get_combined_minimum_size() if panel != null else Vector2.ZERO


func wanted_size() -> Vector2:
	if collapsed:
		return Vector2.ONE * PREVIEW_SIZE
	custom_minimum_size = Vector2(WIDTH, 0.0)
	return Vector2(WIDTH, get_combined_minimum_size().y)


func refresh() -> void:
	title_label.text = ui.music_label() if ui != null and ui.has_method("music_label") else music_path().get_file().get_basename()
	title_label.tooltip_text = title_label.text
	var radio_active := player.radio.path == music_path()
	var details := PackedStringArray()
	if radio_active:
		if not str(player.radio.metadata.get("title", "")).is_empty():
			title_label.text = str(player.radio.metadata["title"])
		for key in ["artist", "album", "station"]:
			var value := str(player.radio.metadata.get(key, ""))
			if not value.is_empty():
				details.append(value)
	details_label.text = " · ".join(details)
	details_label.tooltip_text = details_label.text
	details_label.visible = not details.is_empty()
	_refresh_volume()
	_refresh_artwork()
	quick_mix.visible = player.is_image() and player._audio_only_playing()
	spectrum_view.visible = Settings.music_visualizer
	if not player._audio_only_playing():
		scene_picker.close()
	immersive_button.visible = player._audio_only_playing()
	var immersive := player.is_immersive_visualizer_active()
	immersive_button.set_pressed_no_signal(immersive)
	scene_picker._pull()
	previous_style_button.visible = immersive
	next_style_button.visible = immersive
	var random_mode := Settings.visualizer_shuffle
	previous_style_button.icon = VpxTheme.icon("dice" if random_mode else "chevron_left")
	next_style_button.icon = VpxTheme.icon("dice" if random_mode else "chevron_right")
	var random_tooltip := "Random favourite visualizer" if Settings.visualizer_starred_only else "Random visualizer"
	previous_style_button.tooltip_text = random_tooltip if random_mode else "Previous immersive visualizer style"
	next_style_button.tooltip_text = random_tooltip if random_mode else "Next immersive visualizer style"
	var length := player.get_stream_length()
	refreshing = true
	progress.max_value = maxf(length, 1.0)
	progress.editable = player.can_seek()
	back_button.disabled = not player.can_seek()
	forward_button.disabled = not player.can_seek()
	if not seeking:
		progress.value = player.stream_position
	refreshing = false
	time_label.text = "%s / %s" % [_format_time(progress.value if seeking else player.stream_position), "LIVE" if player.is_live() else _format_time(length)]
	var playing := not player.paused and player.is_playing()
	play_button.icon = VpxTheme.icon("pause" if playing else "play", 36)
	play_button.tooltip_text = "Pause music" if playing else "Play music"
	_refresh_favorite()


func _cycle_style(direction: int) -> void:
	if player.is_immersive_visualizer_active():
		Settings.cycle_visualizer_preset(direction)
		refresh()


func set_collapsed(value: bool) -> void:
	collapsed = value
	seeking = false
	rows.visible = not collapsed
	preview_button.visible = collapsed
	panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 18, 0 if collapsed else 24, 0 if collapsed else 16))
	custom_minimum_size = Vector2.ONE * PREVIEW_SIZE if collapsed else Vector2(WIDTH, 0.0)
	refresh()
	collapsed_changed.emit()


func music_path() -> String:
	return player.music_path if not player.music_path.is_empty() else player.current_path


func track(direction: int) -> void:
	if ui != null and ui.has_method("play_music_neighbor"):
		ui.play_music_neighbor(direction)


func _refresh_artwork() -> void:
	var path := music_path()
	if preview_path != path:
		preview_path = path
		MediaInfo.request(path)
	var texture := player.radio.artwork if player.radio.path == path else null
	if texture == null:
		texture = MediaInfo.thumbnail(path)
	cover_image.texture = texture
	cover_button.icon = VpxTheme.icon("audio", 48) if texture == null else null
	if not collapsed:
		return
	if texture == null and Settings.music_visualizer:
		texture = spectrum_view.texture
	preview_image.texture = texture
	preview_button.icon = VpxTheme.icon("audio", 48) if texture == null else null
	preview_button.tooltip_text = "Expand music player · " + title_label.tooltip_text


func _refresh_volume() -> void:
	var muted := Settings.muted or Settings.volume == 0
	var icon := VpxTheme.icon("volume_off" if muted else "volume")
	volume_button.icon = icon
	volume_button.set_pressed_no_signal(volume_row.visible)
	volume_button.tooltip_text = "%s volume · %d%%" % ["Hide" if volume_row.visible else "Adjust", Settings.volume]
	mute_button.icon = icon
	mute_button.set_pressed_no_signal(muted)
	mute_button.tooltip_text = "Unmute music" if muted else "Mute music"
	volume_slider.set_value_no_signal(Settings.volume)
	volume_label.text = "%d%%" % Settings.volume


func _toggle_mute() -> void:
	var muted := Settings.muted or Settings.volume == 0
	Settings.apply("muted", not muted)
	if muted and Settings.volume == 0:
		Settings.apply("volume", 50)


func _refresh_favorite() -> void:
	if player == null:
		return
	var path := music_path()
	favorite_button.disabled = path.is_empty()
	favorite_button.set_pressed_no_signal(not path.is_empty() and Library.is_favorite(path))
	var on := favorite_button.button_pressed
	if favorite_state == int(on):
		return
	favorite_state = int(on)
	favorite_button.icon = VpxTheme.icon("star" if on else "star_outline")
	var color := VpxTheme.FAVORITE if on else VpxTheme.MUTED
	for role in ["icon_normal_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		favorite_button.add_theme_color_override(role, color)
	favorite_button.add_theme_color_override("icon_hover_color", VpxTheme.FAVORITE)
	favorite_button.tooltip_text = "Remove music from favourites" if on else "Add music to favourites"


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func _favorite_button(parent: Control) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 60)
	button.theme_type_variation = &"FlatIcon"
	button.toggle_mode = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", VpxTheme.ICON_SIZE)
	button.toggled.connect(func(on: bool) -> void:
		if player == null or music_path().is_empty():
			button.set_pressed_no_signal(false)
			return
		if ui != null:
			ui.set_favorite(music_path(), on)
		else:
			Library.set_favorite(music_path(), on)
		_refresh_favorite())
	parent.add_child(button)
	return button


func _artwork_image(button: Button, radius: int) -> TextureRect:
	var image := TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/rounded_artwork.gdshader")
	material.set_shader_parameter("corner_radius", float(radius))
	image.material = material
	image.resized.connect(func() -> void: material.set_shader_parameter("bounds", image.size))
	button.add_child(image)
	return image


func _icon_button(parent: Control, icon_name: String, action: Callable, size := VpxTheme.ICON_SIZE) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 60)
	button.theme_type_variation = &"FlatIcon"
	button.add_theme_constant_override("icon_max_width", size)
	button.icon = VpxTheme.icon(icon_name, size)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button
