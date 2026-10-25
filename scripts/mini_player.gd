extends Control

const MusicVisualizer := preload("res://scripts/music_visualizer.gd")
const MediaCard := preload("res://scripts/media_card.gd")
const HEADER := 0.0
const FOOTER := 158.0
const UI_SCALE := 1.6
const IDLE_OPACITY := 0.4
const GOLDEN_RATIO := 1.61803398875
const WIDTH := 560.0
const ART_SIZE := 216.0
const COVER_SIZE := 240.0
const TOOLBAR_DELAY := 1.2
const VISUALIZER_NAMES := ["Disabled", "Spectrum", "Oscilloscope"]
const MUSIC_HEIGHT := WIDTH / GOLDEN_RATIO
const VIDEO_HEIGHT := MUSIC_HEIGHT

var desktop: CanvasLayer
var ui_factor := UI_SCALE
var active := false
var busy := false
var picture := false
var seeking := false
var adjusting_volume := false
var path := ""
var gradient: GradientTexture2D
var artwork: TextureRect
var fallback: TextureRect
var metadata: VBoxContainer
var title_row: HBoxContainer
var favorite_button: Button
var cover_button: Button
var cover_mode := false
var toolbar_idle := 0.0
var toolbar_alpha := 1.0
var content_expansion := 0.0
var hover_alpha := 0.0
var reveal_alpha := 1.0
var visualizer_menu_alpha := 0.0
var window_menu_alpha := 0.0
var title: Label
var title_clip: Control
var quality: Label
var title_scroll_time := 0.0
var title_scroll_distance := 0.0
var title_scroll_horizontal := false
var last_title := ""
var quality_timer := 0.0
var fade_button: Button
var idle_fade := false
var current_opacity := 1.0
var appearance_layer: CanvasLayer
var appearance_rect: ColorRect
var appearance_material: ShaderMaterial
var details: Label
var clock: Label
var duration: Label
var progress: HSlider
var volume: HSlider
var play_button: Button
var mute_button: Button
var pin_button: Button
var restore_button: Button
var minimize_button: Button
var close_button: Button
var previous_button: Button
var next_button: Button
var spectrum: MusicVisualizer.SpectrumCanvas
var transport_overlay: Panel
var pointer_inside := false
var pointer_position := Vector2(-1, -1)
var artwork_hovered := false
var visualizer_mode := 1
var spectrum_button: Button
var more_button: Button
var visualizer_menu: PanelContainer
var window_menu: PanelContainer
var visualizer_options: Array[Button] = []
var keyboard_mode := false
var hint: Label
var hint_remaining := 0.0
var saved_disable_3d := false
var suspended := false
var field_processing := true
var visualizer_processing := true
var menu_was_open := false
var field_was_active := false
var field_transform := Transform3D.IDENTITY


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = VpxTheme.build()
	gradient = GradientTexture2D.new()
	gradient.width = 512
	gradient.height = 256
	gradient.fill_from = Vector2(0, 0)
	gradient.fill_to = Vector2(1, 1)
	gradient.gradient = Gradient.new()
	gradient.gradient.colors = PackedColorArray([Color("242424"), Color("1b1b1b"), Color("171717")])
	gradient.gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	title = _label(22, VpxTheme.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = -1
	title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	details = _label(14, VpxTheme.TEXT)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.max_lines_visible = 2
	metadata = VBoxContainer.new()
	metadata.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metadata.add_theme_constant_override("separation", 6)
	add_child(metadata)
	title_clip = Control.new()
	title_clip.clip_contents = true
	title_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	title_row = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	metadata.add_child(title_row)
	title_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_clip)
	title.reparent(title_clip)
	details.reparent(metadata)
	quality = _label(12, VpxTheme.MUTED)
	quality.reparent(metadata)
	favorite_button = _button("star_outline", "Add to favourites", _toggle_favorite)
	favorite_button.toggle_mode = true
	favorite_button.custom_minimum_size = Vector2(32, 32)
	favorite_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	favorite_button.reparent(title_row)
	favorite_button.add_theme_color_override("icon_hover_color", VpxTheme.FAVORITE)
	favorite_button.add_theme_color_override("icon_pressed_color", VpxTheme.FAVORITE)
	favorite_button.add_theme_color_override("icon_hover_pressed_color", VpxTheme.FAVORITE)
	clock = _label(12, VpxTheme.MUTED)
	duration = _label(12, VpxTheme.MUTED)
	duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	artwork = TextureRect.new()
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/rounded_artwork.gdshader")
	material.set_shader_parameter("corner_radius", 14.0)
	artwork.material = material
	artwork.resized.connect(func() -> void: material.set_shader_parameter("bounds", artwork.size))
	add_child(artwork)
	fallback = TextureRect.new()
	fallback.texture = VpxTheme.icon("audio", 36)
	fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fallback.modulate = VpxTheme.ACCENT
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	transport_overlay = Panel.new()
	transport_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transport_overlay.add_theme_stylebox_override("panel", VpxTheme.flat(Color("050505a6"), 18, 0, 0))
	transport_overlay.z_index = 1
	transport_overlay.visible = false
	add_child(transport_overlay)
	pin_button = _button("pin", "Keep on top", _pin)
	pin_button.toggle_mode = true
	pin_button.add_theme_color_override("icon_pressed_color", VpxTheme.ACCENT)
	pin_button.add_theme_color_override("icon_hover_pressed_color", VpxTheme.ACCENT)
	restore_button = _button("expand", "Restore VPX · Esc / Ctrl+Shift+M", leave)
	minimize_button = _button("minus", "Minimize", func() -> void: get_window().mode = Window.MODE_MINIMIZED)
	close_button = _button("close", "Quit VPX", func() -> void: get_tree().quit())
	previous_button = _button("prev", "Previous track", _track.bind(-1))
	next_button = _button("next", "Next track", _track.bind(1))
	play_button = _button("play", "Play / pause · Space", func() -> void: desktop.player.toggle_pause())
	for button in [previous_button, play_button, next_button]:
		button.z_index = 2
		button.visible = false
	for state_name in ["normal", "hover", "pressed"]:
		play_button.add_theme_stylebox_override(state_name, VpxTheme.accent_flat(26, 0, 0, &"hover" if state_name == "hover" else &"accent"))
	play_button.add_theme_stylebox_override("focus", VpxTheme.outlined(Color.TRANSPARENT, VpxTheme.TEXT, 2, 26, 0, 0))
	play_button.add_theme_color_override("icon_focus_color", VpxTheme.ON_ACCENT)
	play_button.add_theme_stylebox_override("disabled", VpxTheme.flat(Color(VpxTheme.ACCENT, 0.35), 26, 0, 0))
	play_button.add_theme_color_override("icon_normal_color", VpxTheme.ON_ACCENT)
	play_button.add_theme_color_override("icon_hover_color", VpxTheme.ON_ACCENT)
	play_button.add_theme_color_override("icon_pressed_color", VpxTheme.ON_ACCENT)
	progress = _slider("Seek")
	progress.drag_started.connect(func() -> void: seeking = true)
	progress.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			desktop.player.seek_to(progress.value)
		seeking = false)
	volume = _slider("Volume · mouse wheel adjusts 5%")
	volume.max_value = 100
	volume.step = 1
	volume.drag_started.connect(func() -> void: adjusting_volume = true)
	volume.drag_ended.connect(func(_changed: bool) -> void: adjusting_volume = false)
	volume.value_changed.connect(func(value: float) -> void:
		Settings.apply("volume", int(value))
		if value > 0 and Settings.muted:
			Settings.apply("muted", false))
	mute_button = _button("volume", "Mute / unmute", _mute)
	spectrum = MusicVisualizer.SpectrumCanvas.new()
	spectrum.embedded = true
	spectrum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spectrum)
	spectrum_button = _button("audio", "Choose visualizer", _toggle_visualizer_menu)
	cover_button = _button("cover_mode", "Cover mode · Ctrl+Shift+C", _toggle_cover)
	fade_button = _button("opacity", "Fade float when idle", _toggle_idle_fade)
	fade_button.toggle_mode = true
	fade_button.add_theme_color_override("icon_pressed_color", VpxTheme.ACCENT)
	fade_button.add_theme_color_override("icon_hover_pressed_color", VpxTheme.ACCENT)
	more_button = _button("more", "Window actions", _toggle_window_menu)
	visualizer_menu = _menu_panel()
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 4)
	visualizer_menu.add_child(choices)
	for index in VISUALIZER_NAMES.size():
		var option := _button("check", VISUALIZER_NAMES[index], _select_visualizer.bind(index))
		option.text = VISUALIZER_NAMES[index]
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.add_theme_font_size_override("font_size", 14)
		option.add_theme_constant_override("h_separation", 10)
		option.custom_minimum_size = Vector2(164, 36)
		option.reparent(choices)
		visualizer_options.append(option)
	window_menu = _menu_panel()
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	window_menu.add_child(actions)
	for button in [minimize_button, close_button]:
		button.text = "Minimize" if button == minimize_button else "Quit VPX"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_constant_override("h_separation", 10)
		button.custom_minimum_size = Vector2(152, 36)
		button.reparent(actions)
		button.pressed.connect(_close_menus)
	hint = _label(10, VpxTheme.TEXT)
	hint.text = "Hover or press Tab\nfor controls"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_stylebox_override("normal", VpxTheme.flat(Color("101010dd"), 8, 8, 5))
	hint.z_index = 3
	appearance_layer = CanvasLayer.new()
	appearance_layer.layer = 200
	appearance_layer.visible = false
	add_child(appearance_layer)
	appearance_rect = ColorRect.new()
	appearance_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	appearance_material = ShaderMaterial.new()
	appearance_material.shader = preload("res://shaders/mini_window.gdshader")
	appearance_rect.material = appearance_material
	appearance_layer.add_child(appearance_rect)
	get_window().focus_exited.connect(func() -> void:
		keyboard_mode = false
		_release_focus()
		_close_menus()
		_update_transport())
	get_window().mouse_entered.connect(func() -> void:
		pointer_inside = true
		pointer_position = get_local_mouse_position())
	get_window().mouse_exited.connect(func() -> void:
		pointer_inside = false
		_update_transport())
	gui_input.connect(_drag)
	resized.connect(queue_redraw)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(icon_name: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = VpxTheme.icon(icon_name, 18)
	button.set_meta("mini_icon", icon_name)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("h_separation", 0)
	button.add_theme_constant_override("icon_max_width", 18)
	button.focus_mode = Control.FOCUS_ALL
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, VpxTheme.flat(Color(1, 1, 1, 0.09) if state_name != "normal" else Color.TRANSPARENT, 9, 0, 0))
	button.add_theme_stylebox_override("focus", VpxTheme.outlined(Color.TRANSPARENT, VpxTheme.ACCENT, 2, 9, 0, 0))
	for state_name in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_color_override("icon_" + state_name + "_color", VpxTheme.MUTED if state_name == "normal" else VpxTheme.TEXT)
	Tooltips.set_text(button, hint)
	button.pressed.connect(action)
	add_child(button)
	return button


func _slider(hint: String) -> HSlider:
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_ALL
	slider.add_theme_stylebox_override("focus", VpxTheme.outlined(Color.TRANSPARENT, VpxTheme.ACCENT, 2, 4, 0, 0))
	slider.scrollable = false
	slider.add_theme_stylebox_override("slider", VpxTheme.flat(Color("454545"), 2, 0, 2))
	var fill := VpxTheme.accent_flat(2, 0, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", VpxTheme.circle(VpxTheme.TEXT, 8))
	slider.add_theme_icon_override("grabber_highlight", VpxTheme.circle(VpxTheme.ACCENT, 12))
	slider.add_theme_icon_override("grabber_disabled", VpxTheme.circle(VpxTheme.FAINT, 6))
	Tooltips.set_text(slider, hint)
	add_child(slider)
	return slider


func enter() -> void:
	if busy or active or not desktop.main.desktop_mode or not desktop.main.window_session.active:
		return
	busy = true
	menu_was_open = desktop.panel.is_open()
	desktop.panel.close()
	desktop.osd.dismiss()
	desktop._hide_seek_preview()
	desktop.menu_pressed = false
	desktop.video_pressed = false
	desktop.seeking = false
	desktop.main.held_step_key = KEY_NONE
	seeking = false
	adjusting_volume = false
	picture = _has_picture()
	cover_mode = bool(desktop.main.window_session.state.get("mini_cover", false))
	toolbar_idle = 0.0
	toolbar_alpha = 1.0
	content_expansion = 0.0
	visualizer_mode = clampi(int(desktop.main.window_session.state.get("mini_visualizer", 2 if Settings.music_visualizer_mode == 2 else 1)), 0, 2)
	if visualizer_mode != 0:
		Settings.apply("music_visualizer_mode", 2 if visualizer_mode == 2 else 0)
	idle_fade = bool(desktop.main.window_session.state.get("mini_idle_fade", false))
	current_opacity = 1.0
	title_scroll_time = 0.0
	quality_timer = 0.0
	pointer_inside = false
	keyboard_mode = false
	_close_menus()
	_begin_hint()
	var usable := DisplayServer.screen_get_usable_rect()
	ui_factor = UI_SCALE * Settings.ui_size * Settings.text_size
	ui_factor = minf(ui_factor, minf(usable.size.x / WIDTH, usable.size.y / VIDEO_HEIGHT))
	scale = Vector2.ONE * ui_factor
	var font := ThemeDB.fallback_font.duplicate() as FontFile
	if font != null:
		font.oversampling = ui_factor
		theme.default_font = font
	for child in get_children():
		if child is Button and child.has_meta("mini_icon"):
			child.icon = VpxTheme.icon(str(child.get_meta("mini_icon")), ceili(18 * ui_factor))
	fallback.texture = VpxTheme.icon("audio", ceili(36 * ui_factor))
	if not await desktop.main.window_session.enter_mini(ui_factor, _desired_size()):
		busy = false
		return
	active = true
	visible = true
	appearance_layer.visible = true
	get_window().transparent = true
	get_window().transparent_bg = true
	saved_disable_3d = get_viewport().disable_3d
	_fit_window()
	size = get_viewport().get_visible_rect().size / ui_factor
	_refresh()
	busy = false


func leave() -> void:
	if busy or not active:
		return
	busy = true
	_close_menus()
	_release_focus()
	keyboard_mode = false
	appearance_layer.visible = false
	seeking = false
	adjusting_volume = false
	_suspend_visuals(false)
	get_viewport().disable_3d = saved_disable_3d
	desktop.camera.v_offset = 0.0
	await desktop.main.window_session.leave_mini()
	active = false
	visible = false
	if menu_was_open:
		desktop.main.toggle_menu()
	desktop.idle = 0.0
	busy = false


func _has_picture() -> bool:
	return desktop.player.has_picture() and not desktop.player.is_music_mode()


func _desired_size() -> Vector2:
	return Vector2.ONE * COVER_SIZE if cover_mode else Vector2(WIDTH, VIDEO_HEIGHT if picture else MUSIC_HEIGHT)


func _fit_window(centered := false) -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var target := Vector2i((_desired_size() * ui_factor).round()).min(usable.size)
	var position := get_window().position
	if centered:
		position += (get_window().size - target) / 2
	position = position.clamp(usable.position, usable.end - target)
	get_window().min_size = Vector2i.ZERO
	get_window().max_size = Vector2i.ZERO
	get_window().size = target
	get_window().min_size = target
	get_window().max_size = target
	get_window().position = position


func _process(delta: float) -> void:
	if not active or busy:
		return
	size = get_viewport().get_visible_rect().size / ui_factor
	var wanted := _has_picture()
	if wanted != picture:
		picture = wanted
		_fit_window()
		size = get_viewport().get_visible_rect().size / ui_factor
	_refresh()
	if hint_remaining > 0:
		hint_remaining = maxf(0, hint_remaining - delta)
		if hint_remaining == 0:
			_dismiss_hint()
	title_scroll_time += delta
	_scroll_title()
	_update_toolbar(delta)
	_animate_controls(delta)
	_update_appearance(delta)
	quality_timer -= delta


func _suspend_visuals(value: bool) -> void:
	if suspended == value:
		return
	suspended = value
	var field: Node = desktop.main.resonance_field
	var visualizer: Node = desktop.main.music_visualizer
	if value:
		field_was_active = field.active
		field_transform = field.transform
		field.set_active(false)
		field_processing = field.is_processing()
		visualizer_processing = visualizer.is_processing()
		field.set_process(false)
		visualizer.mini_active = true
		visualizer.mini_enabled = visualizer_mode != 0 and not cover_mode
		visualizer.set_process(true)
	else:
		field.set_active(desktop.player.is_immersive_visualizer_active())
		if field_was_active and field.active:
			field.transform = field_transform
		field.set_process(field_processing)
		visualizer.set_process(visualizer_processing)
		visualizer.mini_active = false


func _refresh() -> void:
	var player: VPXPlayer = desktop.player
	var next_path := player.music_path if player._audio_only_playing() and not player.music_path.is_empty() else player.current_path
	if path != next_path:
		path = next_path
		MediaInfo.request(path)
	var radio_active := not path.is_empty() and player.radio.path == path
	var metadata := _track_metadata()
	var name := str(metadata.get("title", "")).strip_edges()
	if name.is_empty():
		name = str(metadata.get("station", "")).strip_edges()
	if name.is_empty():
		name = MediaCard.pretty_name(path)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF if picture and not cover_mode else TextServer.AUTOWRAP_WORD_SMART
	var text := name if not path.is_empty() else "Your music. Your space."
	if text != last_title:
		last_title = text
		title.text = text
		title_scroll_time = 0.0
		quality_timer = 0.0
	var parts := PackedStringArray()
	for key in (["artist"] if cover_mode else ["artist", "album", "station"]):
		var value := str(metadata.get(key, ""))
		if not value.is_empty() and value not in parts:
			parts.append(value)
	details.text = "\n".join(parts) if not parts.is_empty() else "Open media in the full player" if path.is_empty() else "Music over photos" if player.is_image() and player._audio_only_playing() else ""
	if quality_timer <= 0:
		quality.text = _quality_text()
		quality_timer = 0.5
	quality.visible = not quality.text.is_empty()
	Tooltips.set_text(quality, quality.text)
	Tooltips.set_text(self, "Drag to move · double-click to restore")
	var full_metadata := title.text + ("\n" + " · ".join(parts) if not parts.is_empty() else "") + ("\n" + quality.text if not quality.text.is_empty() else "")
	Tooltips.set_text(title, full_metadata)
	Tooltips.set_text(title_clip, full_metadata)
	details.visible = (not picture or cover_mode) and not details.text.is_empty()
	Tooltips.set_text(details, details.text)
	artwork.texture = player.radio.artwork if radio_active else MediaInfo.thumbnail(path)
	artwork.visible = (not picture or cover_mode) and artwork.texture != null
	fallback.visible = (not picture or cover_mode) and artwork.texture == null
	play_button.icon = VpxTheme.icon("play" if player.paused or not player.is_playing() else "pause", ceili(22 * ui_factor))
	play_button.disabled = player.playback == null
	Tooltips.set_text(play_button, "Play · Space" if player.paused else "Pause · Space")
	mute_button.icon = VpxTheme.icon("volume_off" if Settings.muted or Settings.volume == 0 else "volume", ceili(18 * ui_factor))
	pin_button.set_pressed_no_signal(get_window().always_on_top)
	Tooltips.set_text(pin_button, "Unpin from top" if get_window().always_on_top else "Keep on top")
	if not adjusting_volume:
		volume.set_value_no_signal(Settings.volume)
	volume.modulate.a = 0.45 if Settings.muted else 1.0
	Tooltips.set_text(volume, "Volume %d%% · wheel ±5%% · right-click to mute" % Settings.volume)
	progress.editable = player.can_seek()
	if not seeking:
		progress.max_value = maxf(player.get_stream_length(), 1.0)
		progress.set_value_no_signal(player.stream_position)
	clock.text = _time(progress.value if seeking else player.stream_position)
	duration.text = "LIVE" if player.is_live() else _time(player.get_stream_length())
	previous_button.disabled = path.is_empty()
	next_button.disabled = path.is_empty()
	_refresh_favorite()
	_suspend_visuals(true)
	var visualizer: Node = desktop.main.music_visualizer
	visualizer.mini_enabled = visualizer_mode != 0 and not cover_mode
	spectrum.visible = not picture and not cover_mode and visualizer_mode != 0
	spectrum_button.visible = not picture
	spectrum.oscilloscope = Settings.music_visualizer_mode == 2
	spectrum.levels = visualizer.spectrum.levels
	spectrum.wave = visualizer.spectrum.wave
	spectrum_button.icon = VpxTheme.icon("audio_off" if visualizer_mode == 0 else "audio", ceili(18 * ui_factor))
	spectrum_button.modulate = VpxTheme.MUTED if visualizer_mode == 0 else VpxTheme.ACCENT
	Tooltips.set_text(spectrum_button, "Visualizer: %s · choose mode" % VISUALIZER_NAMES[visualizer_mode])
	for index in visualizer_options.size():
		visualizer_options[index].icon = VpxTheme.icon("check" if index == visualizer_mode else "radio_unchecked", ceili(16 * ui_factor))
		visualizer_options[index].modulate = VpxTheme.ACCENT if index == visualizer_mode else VpxTheme.TEXT
	if spectrum.visible:
		spectrum.queue_redraw()
	get_viewport().disable_3d = saved_disable_3d or not picture or cover_mode
	get_window().transparent_bg = true
	_layout()
	_update_transport()
	queue_redraw()


func _place(control: Control, x: float, y: float, width: float, height: float) -> void:
	control.position = Vector2(x, y)
	control.size = Vector2(width, height)


func _layout() -> void:
	var width := size.x
	var height := size.y
	var center := height - 76.0
	var expanded_art := maxf(ART_SIZE, height - 76)
	var art_size := lerpf(ART_SIZE, expanded_art, content_expansion)
	var metadata_left := 260.0 + art_size - ART_SIZE
	_place(artwork, 20, 20, art_size, art_size)
	_place(fallback, 20 + (art_size - 72) * 0.5, 20 + (art_size - 72) * 0.5, 72, 72)
	var title_size := 14 if cover_mode else 22
	if title.get_theme_font_size("font_size") != title_size:
		title.add_theme_font_size_override("font_size", title_size)
	var metadata_width := width - 24 if cover_mode else width - 40 if picture else width - metadata_left - 20
	var text_width := metadata_width - 40
	title_clip.custom_minimum_size.x = 0
	title.size = Vector2(text_width, 0)
	var line_height := title.get_line_height()
	var available_lines := 2 if cover_mode else 1 if picture else 3 if visualizer_mode == 0 else 2
	var line_count := maxi(1, title.get_line_count())
	var visible_lines := mini(available_lines, line_count)
	var title_lines := lerpf(float(visible_lines), float(mini(available_lines + 1, line_count)), content_expansion)
	title_clip.custom_minimum_size.y = minf(title.size.y, line_height * title_lines + title.get_theme_constant("line_spacing") * maxf(0, title_lines - 1))
	title_scroll_horizontal = picture and not cover_mode
	title_scroll_distance = maxf(0, title.size.x - text_width) if title_scroll_horizontal else maxf(0, title.size.y - title_clip.custom_minimum_size.y)
	_place(metadata, 12 if cover_mode else 20 if picture else metadata_left, 12 if cover_mode else height - 128 if picture else 20, metadata_width, 0)
	if picture and not cover_mode:
		metadata.position.y = height - 108 - metadata.size.y
	elif visualizer_mode == 0 and not cover_mode:
		metadata.position.y = 20 + maxf(0, (art_size - metadata.size.y) * 0.5)
	var visualizer_top := metadata.position.y + metadata.size.y + 12.0
	_place(spectrum, metadata_left, visualizer_top, width - metadata_left - 20, maxf(20, lerpf(236.0, height - 56, content_expansion) - visualizer_top))
	_place(progress, 86, height - 38, width - 172, 18)
	_place(clock, 20, height - 38, 62, 18)
	_place(duration, width - 82, height - 38, 62, 18)
	var area := Rect2(Vector2.ZERO, size) if cover_mode else artwork.get_rect() if not picture else Rect2(0, 0, width, height - FOOTER)
	transport_overlay.position = area.position
	transport_overlay.size = area.size
	var transport_center := area.get_center()
	_place(previous_button, transport_center.x - 88, transport_center.y - 18, 36, 36)
	_place(play_button, transport_center.x - 26, transport_center.y - 26, 52, 52)
	_place(next_button, transport_center.x + 52, transport_center.y - 18, 36, 36)
	_place(mute_button, 20, center - 16, 32, 32)
	_place(volume, 60, center - 9, 128, 18)
	_place(spectrum_button, 220, center - 16, 32, 32)
	_place(cover_button, 260, center - 16, 32, 32)
	_place(fade_button, width - 212, center - 16, 32, 32)
	_place(pin_button, width - 172, center - 16, 32, 32)
	_place(restore_button, width - 112, center - 16, 32, 32)
	_place(more_button, width - 52, center - 16, 32, 32)
	visualizer_menu.size = visualizer_menu.get_combined_minimum_size()
	visualizer_menu.position = Vector2(212, center - 24 - visualizer_menu.size.y)
	window_menu.size = window_menu.get_combined_minimum_size()
	window_menu.position = Vector2(width - 20 - window_menu.size.x, center - 24 - window_menu.size.y)
	_place(hint, 30, art_size - 42, art_size - 20, 40)
	if cover_mode:
		_place(artwork, 0, 0, width, height)
		_place(fallback, (width - 80) * 0.5, (height - 80) * 0.5, 80, 80)
		_place(mute_button, 12, height - 44, 32, 32)
		_place(volume, 52, height - 37, width - 108, 18)
		_place(cover_button, width - 44, height - 44, 32, 32)
		_place(hint, 28, height - 56, width - 56, 40)
	details.max_lines_visible = 1 if cover_mode else 2
	if details.get_theme_font_size("font_size") != (11 if cover_mode else 14):
		details.add_theme_font_size_override("font_size", 11 if cover_mode else 14)
	metadata.z_index = 2 if cover_mode else 0
	cover_button.z_index = 2 if cover_mode else 0
	mute_button.z_index = 2 if cover_mode else 0
	volume.z_index = 2 if cover_mode else 0
	cover_button.icon = VpxTheme.icon("expand" if cover_mode else "cover_mode", ceili(18 * ui_factor))
	Tooltips.set_text(cover_button, "Expand to float · Esc / Ctrl+Shift+C" if cover_mode else "Cover mode · Ctrl+Shift+C")


func _update_transport() -> void:
	var area := transport_overlay.get_rect()
	artwork_hovered = active and not busy and ((pointer_inside and area.has_point(pointer_position)) or keyboard_mode)
	if artwork_hovered and hint_remaining > 0:
		_dismiss_hint()
	hint.visible = active and hint_remaining > 0 and not artwork_hovered
	transport_overlay.visible = artwork_hovered
	for button in [previous_button, play_button, next_button]:
		button.visible = artwork_hovered
	if cover_mode:
		metadata.visible = artwork_hovered
		mute_button.visible = artwork_hovered
		volume.visible = artwork_hovered
		cover_button.visible = artwork_hovered


func _select_visualizer(mode: int) -> void:
	visualizer_mode = mode
	_close_menus(spectrum_button)
	if visualizer_mode != 0:
		Settings.apply("music_visualizer_mode", 2 if visualizer_mode == 2 else 0)
	desktop.main.music_visualizer.mini_enabled = visualizer_mode != 0 and not cover_mode
	desktop.main.window_session.state["mini_visualizer"] = visualizer_mode
	desktop.main.window_session._save_state()


func _toggle_cover() -> void:
	if busy or not active:
		return
	var pointer_screen := Vector2(get_window().position) + pointer_position * ui_factor
	_close_menus()
	_release_focus()
	cover_mode = not cover_mode
	desktop.main.window_session.state["mini_cover"] = cover_mode
	desktop.main.window_session._save_state()
	seeking = false
	adjusting_volume = false
	title_scroll_time = 0.0
	toolbar_idle = 0.0
	content_expansion = 0.0
	_fit_window(true)
	size = get_viewport().get_visible_rect().size / ui_factor
	pointer_position = (pointer_screen - Vector2(get_window().position)) / ui_factor
	pointer_inside = Rect2(Vector2.ZERO, size).has_point(pointer_position)
	_begin_hint()
	desktop.main.window_session.capture()
	_refresh()
	_update_toolbar(0.0)
	if keyboard_mode:
		(mute_button if play_button.disabled else play_button).grab_focus()


func _animate_controls(delta: float) -> void:
	hover_alpha = move_toward(hover_alpha, 1.0 if artwork_hovered else 0.0, delta / 0.12)
	reveal_alpha = move_toward(reveal_alpha, 1.0 if toolbar_alpha > 0.01 else 0.0, delta / 0.1)
	var show_transport := artwork_hovered or hover_alpha > 0.01
	transport_overlay.visible = show_transport
	transport_overlay.modulate.a = hover_alpha
	for button in [previous_button, play_button, next_button]:
		button.visible = show_transport
		button.modulate.a = hover_alpha
		button.mouse_filter = Control.MOUSE_FILTER_STOP if artwork_hovered else Control.MOUSE_FILTER_IGNORE
	metadata.modulate.a = hover_alpha if cover_mode else 1.0
	if cover_mode:
		metadata.visible = show_transport
		for control in [mute_button, volume, cover_button]:
			control.visible = show_transport
			control.modulate.a *= hover_alpha
	for control in [spectrum, progress, clock, duration, hint]:
		control.modulate.a = 1.0
	for control in [mute_button, volume, spectrum_button, cover_button, fade_button, pin_button, restore_button, more_button]:
		control.modulate.a *= 1.0 if cover_mode else reveal_alpha
	visualizer_menu_alpha = move_toward(visualizer_menu_alpha, 1.0 if visualizer_menu.visible else 0.0, delta / 0.1)
	window_menu_alpha = move_toward(window_menu_alpha, 1.0 if window_menu.visible else 0.0, delta / 0.1)
	visualizer_menu.modulate.a = visualizer_menu_alpha
	window_menu.modulate.a = window_menu_alpha


func _favorite_path() -> String:
	var player: VPXPlayer = desktop.player
	return player.music_path if player._audio_only_playing() and not player.music_path.is_empty() else player.current_path


func _toggle_favorite() -> void:
	var source := _favorite_path()
	if source.is_empty():
		favorite_button.set_pressed_no_signal(false)
		return
	desktop.main.ui.set_favorite(source, favorite_button.button_pressed)
	_refresh_favorite()


func _refresh_favorite() -> void:
	var source := _favorite_path()
	var on := not source.is_empty() and Library.is_favorite(source)
	favorite_button.disabled = source.is_empty()
	favorite_button.set_pressed_no_signal(on)
	favorite_button.icon = VpxTheme.icon("star" if on else "star_outline", ceili(18 * ui_factor))
	favorite_button.add_theme_color_override("icon_normal_color", VpxTheme.FAVORITE if on else VpxTheme.MUTED)
	Tooltips.set_text(favorite_button, "Remove from favourites" if on else "Add to favourites")


func _update_toolbar(delta: float) -> void:
	var hovered := pointer_inside and Rect2(Vector2.ZERO, size).has_point(pointer_position)
	if hovered or seeking or adjusting_volume or keyboard_mode or visualizer_menu.visible or window_menu.visible:
		toolbar_idle = 0.0
		toolbar_alpha = 1.0
	else:
		toolbar_idle += delta
		if toolbar_idle >= TOOLBAR_DELAY:
			toolbar_alpha = lerpf(toolbar_alpha, 0.0, 1.0 - exp(-delta * 14.0))
	var show := toolbar_alpha > 0.01
	var target_expansion := 0.0 if show or cover_mode or picture else 1.0
	var expansion_before := content_expansion
	content_expansion = target_expansion if delta == 0.0 else lerpf(content_expansion, target_expansion, 1.0 - exp(-delta * 12.0))
	if absf(content_expansion - target_expansion) < 0.001:
		content_expansion = target_expansion
	if not is_equal_approx(expansion_before, content_expansion):
		title_scroll_time = 0.0
		_layout()
		_update_transport()
		queue_redraw()
	metadata.visible = not cover_mode or artwork_hovered
	quality.visible = not cover_mode and not quality.text.is_empty()
	progress.visible = not cover_mode
	clock.visible = not cover_mode
	duration.visible = not cover_mode
	for control in [mute_button, volume, spectrum_button, cover_button, fade_button, pin_button, restore_button, more_button]:
		if cover_mode:
			control.visible = artwork_hovered and control in [mute_button, volume, cover_button]
			control.modulate.a = (0.45 if control == volume and Settings.muted else 1.0)
		else:
			control.visible = show and (control != spectrum_button or not picture)
			control.modulate.a = toolbar_alpha * (0.45 if control == volume and Settings.muted else 1.0)


func _toggle_idle_fade() -> void:
	idle_fade = fade_button.button_pressed
	desktop.main.window_session.state["mini_idle_fade"] = idle_fade
	desktop.main.window_session._save_state()


func _update_appearance(delta: float) -> void:
	var hovered := pointer_inside and Rect2(Vector2.ZERO, size).has_point(pointer_position)
	var target := IDLE_OPACITY if idle_fade and not hovered and not seeking and not adjusting_volume and not keyboard_mode and not visualizer_menu.visible and not window_menu.visible else 1.0
	current_opacity = lerpf(current_opacity, target, 1.0 - exp(-delta * (16.0 if target == 1.0 else 8.0)))
	if absf(current_opacity - target) < 0.001:
		current_opacity = target
	appearance_rect.size = get_viewport().get_visible_rect().size
	appearance_material.set_shader_parameter("bounds", appearance_rect.size)
	appearance_material.set_shader_parameter("corner_radius", 12 * ui_factor)
	appearance_material.set_shader_parameter("opacity", current_opacity)
	fade_button.set_pressed_no_signal(idle_fade)
	Tooltips.set_text(fade_button, "Idle fade on · 40% opacity away, full opacity on hover" if idle_fade else "Enable 40% idle opacity")


func _scroll_title() -> void:
	if title_scroll_distance < 1:
		title.position = Vector2.ZERO
		return
	var travel := title_scroll_distance / 18.0
	var time := fmod(title_scroll_time, travel * 2 + 4.0)
	var offset := 0.0
	if time > 2.0 and time < 2.0 + travel:
		offset = (time - 2.0) * 18.0
	elif time >= 2.0 + travel and time <= 4.0 + travel:
		offset = title_scroll_distance
	elif time > 4.0 + travel:
		offset = title_scroll_distance - (time - 4.0 - travel) * 18.0
	title.position = Vector2(-offset, 0) if title_scroll_horizontal else Vector2(0, -offset)


func _quality_text() -> String:
	if path.is_empty():
		return ""
	var player: VPXPlayer = desktop.player
	var tracks: Array = player.tracks.audio_tracks
	var choice: int = player.tracks.audio_choice
	var track: Dictionary = tracks[choice] if choice >= 0 and choice < tracks.size() else {}
	var codec := str(track.get("codec", "")).to_upper()
	var format := path.get_extension().to_upper() if not path.contains("://") else codec
	if format.is_empty():
		format = codec
	var parts := PackedStringArray()
	if not format.is_empty():
		parts.append(format)
	var bytes := player.file_bytes if path == player.current_path else MediaInfo.file_size(path)
	var length := player.get_stream_length()
	if bytes > 0 and length > 0.1 and not player.is_live():
		var kbps := bytes * 8.0 / length / 1000.0
		parts.append("%.2f Mbps" % (kbps / 1000.0) if kbps >= 1000 else "%d kbps" % roundi(kbps))
	var rate := int(track.get("sample_rate", 0))
	if rate > 0:
		parts.append("%s kHz" % String.num(rate / 1000.0, 1).trim_suffix(".0"))
	return " · ".join(parts)


func _draw() -> void:
	if not active:
		return
	if cover_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1b1b1b"))
	elif not picture:
		draw_texture_rect(gradient, Rect2(Vector2.ZERO, size), false)
		draw_style_box(VpxTheme.flat(Color("ffffff08"), 18, 0, 0), artwork.get_rect())

	else:
		draw_rect(Rect2(0, size.y - FOOTER, size.x, FOOTER), Color("1b1b1b"))
	if not cover_mode and toolbar_alpha > 0.01:
		for area in [Rect2(212, size.y - 96, 88, 40), Rect2(size.x - 220, size.y - 96, 88, 40)]:
			draw_style_box(VpxTheme.flat(Color(1, 1, 1, 0.035 * toolbar_alpha), 10, 0, 0), area)
		draw_line(Vector2(size.x - 124, size.y - 90), Vector2(size.x - 124, size.y - 62), Color(VpxTheme.TEXT, 0.12 * toolbar_alpha), 1)
	draw_style_box(VpxTheme.outlined(Color.TRANSPARENT, Color("ffffff12"), 1, 12, 0, 0), Rect2(Vector2.ZERO, size))


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			if cover_mode:
				_toggle_cover()
			else:
				await leave()
		elif DisplayServer.get_name() != "headless":
			DisplayServer.window_start_drag()
		accept_event()


func _pin() -> void:
	desktop.main.window_session.pin_mini(pin_button.button_pressed)


func _mute() -> void:
	var muted := Settings.muted or Settings.volume == 0
	Settings.apply("muted", not muted)
	if muted and Settings.volume == 0:
		Settings.apply("volume", 50)


func _track(direction: int) -> void:
	if desktop.player._audio_only_playing():
		desktop.main.ui.play_music_neighbor(direction)
	else:
		desktop.main.step_file(direction)


func _time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func _input(event: InputEvent) -> void:
	if not active and not busy:
		return
	if (event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed)) and keyboard_mode:
		keyboard_mode = false
		_release_focus()
	if event is InputEventMouse:
		pointer_inside = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(event.position)
		pointer_position = get_global_transform_with_canvas().affine_inverse() * event.position
		_update_transport()
		_update_toolbar(0.0)
	if busy:
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position
		if visualizer_menu.visible and not visualizer_menu.get_global_rect().has_point(point) and not spectrum_button.get_global_rect().has_point(point):
			_close_menus()
		if window_menu.visible and not window_menu.get_global_rect().has_point(point) and not more_button.get_global_rect().has_point(point):
			_close_menus()
		if volume.get_global_rect().grow(12).has_point(point) or mute_button.get_global_rect().has_point(point):
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				Settings.apply("volume", clampi(Settings.volume + (5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -5), 0, 100))
				if Settings.volume > 0 and Settings.muted:
					Settings.apply("muted", false)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_mute()
				get_viewport().set_input_as_handled()
	if event is not InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if _keyboard_input(event):
		return
	match event.keycode:
		KEY_ESCAPE:
			if cover_mode:
				_toggle_cover()
			else:
				await leave()
		KEY_C:
			if event.ctrl_pressed and event.shift_pressed:
				_toggle_cover()
		KEY_M:
			if event.ctrl_pressed and event.shift_pressed:
				leave()
			else:
				_mute()
		KEY_SPACE, KEY_K:
			desktop.player.toggle_pause()
		KEY_LEFT, KEY_RIGHT:
			desktop.player.seek_relative((-1 if event.keycode == KEY_LEFT else 1) * (60.0 if event.shift_pressed else 10.0))
		KEY_UP, KEY_DOWN:
			Settings.apply("volume", clampi(Settings.volume + (5 if event.keycode == KEY_UP else -5), 0, 100))
			if Settings.volume > 0 and event.keycode == KEY_UP:
				Settings.apply("muted", false)
		KEY_N, KEY_PAGEDOWN:
			_track(1)
		KEY_P, KEY_PAGEUP:
			_track(-1)
		KEY_F11:
			await leave()
			desktop.toggle_fullscreen()
		KEY_ENTER:
			if event.alt_pressed:
				await leave()
				desktop.toggle_fullscreen()


func _menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.z_index = 5
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", VpxTheme.outlined(Color("282828"), Color("484848"), 1, 12, 8, 8))
	add_child(panel)
	return panel


func _toggle_visualizer_menu() -> void:
	var opening := not visualizer_menu.visible
	_close_menus()
	visualizer_menu.visible = opening
	if opening and keyboard_mode:
		visualizer_options[visualizer_mode].grab_focus()


func _toggle_window_menu() -> void:
	var opening := not window_menu.visible
	_close_menus()
	window_menu.visible = opening
	if opening and keyboard_mode:
		minimize_button.grab_focus()


func _close_menus(return_focus: Control = null) -> void:
	if visualizer_menu != null:
		visualizer_menu.hide()
	if window_menu != null:
		window_menu.hide()
	if keyboard_mode and return_focus != null:
		return_focus.grab_focus()


func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


func _keyboard_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if visualizer_menu.visible:
		for option in visualizer_options:
			controls.append(option)
	elif window_menu.visible:
		controls.assign([minimize_button, close_button])
	else:
		controls.assign([play_button, previous_button, next_button, favorite_button])
		if not cover_mode:
			controls.append(progress)
		controls.append(mute_button)
		controls.append(volume)
		if not cover_mode and not picture:
			controls.append(spectrum_button)
		controls.append(cover_button)
		if not cover_mode:
			controls.append_array([fade_button, pin_button, restore_button, more_button])
	return controls.filter(func(control: Control) -> bool: return control.is_visible_in_tree() and (control is not BaseButton or not control.disabled) and (control != progress or progress.editable))


func _keyboard_input(event: InputEventKey) -> bool:
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
		return false
	if event.keycode == KEY_TAB:
		var was_keyboard := keyboard_mode
		keyboard_mode = true
		_dismiss_hint()
		_update_transport()
		_update_toolbar(0.0)
		var controls := _keyboard_controls()
		if not controls.is_empty():
			var current := controls.find(get_viewport().gui_get_focus_owner()) if was_keyboard else -1
			var next := posmod(current + (-1 if event.shift_pressed else 1), controls.size()) if current >= 0 else controls.size() - 1 if event.shift_pressed else 0
			controls[next].grab_focus()
		return true
	if event.keycode == KEY_ESCAPE and (visualizer_menu.visible or window_menu.visible):
		_close_menus(spectrum_button if visualizer_menu.visible else more_button)
		return true
	if not keyboard_mode:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	if event.keycode in [KEY_UP, KEY_DOWN] and (visualizer_menu.visible or window_menu.visible):
		var choices := _keyboard_controls()
		if not choices.is_empty():
			choices[posmod(choices.find(focused) + (-1 if event.keycode == KEY_UP else 1), choices.size())].grab_focus()
		return true
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and focused is Button:
		if focused.toggle_mode:
			focused.button_pressed = not focused.button_pressed
		focused.pressed.emit()
		return true
	if focused == progress and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END]:
		var target: float = 0.0 if event.keycode == KEY_HOME else progress.max_value if event.keycode == KEY_END else desktop.player.stream_position + (-5 if event.keycode == KEY_LEFT else 5)
		desktop.player.seek_to(clampf(target, 0, progress.max_value))
		return true
	if focused == volume and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END]:
		volume.value = 0 if event.keycode == KEY_HOME else 100 if event.keycode == KEY_END else volume.value + (-5 if event.keycode in [KEY_LEFT, KEY_DOWN] else 5)
		return true
	return false


func _begin_hint() -> void:
	var key := "nano_controls_hint_seen" if cover_mode else "mini_controls_hint_seen"
	hint_remaining = 0.0 if bool(desktop.main.window_session.state.get(key, false)) else 5.0


func _dismiss_hint() -> void:
	hint_remaining = 0.0
	hint.hide()
	var key := "nano_controls_hint_seen" if cover_mode else "mini_controls_hint_seen"
	if not bool(desktop.main.window_session.state.get(key, false)):
		desktop.main.window_session.state[key] = true
		desktop.main.window_session._save_state()


func _track_metadata() -> Dictionary:
	var player: VPXPlayer = desktop.player
	if not path.is_empty() and player.radio.path == path:
		return player.radio.metadata
	var raw: Variant = player.stream_metadata.get("radio_tags", player.stream_metadata.get("tags", {}))
	var tags := {}
	if raw is Dictionary:
		for key: Variant in raw:
			if raw[key] is String:
				tags[str(key).to_lower()] = str(raw[key]).strip_edges().left(4096)
	var result := {}
	for key: String in ["title", "artist", "album"]:
		var value := str(tags.get(key, ""))
		if value.is_empty() and key == "artist":
			value = str(tags.get("album_artist", tags.get("albumartist", "")))
		if not value.is_empty():
			result[key] = value
	return result
