extends FloatPanel

const WIDTH := 1.0
const MIN_HEIGHT := 0.1
const CARD_ALPHA := VpxTheme.OVERLAY_ALPHA
const FONT_SIZE := 22
const KEY_FONT_SIZE := 20
const TITLE_FONT_SIZE := 22
const FPS_INTERVAL := 0.5

@export var player: VPXPlayer

var items: HFlowContainer
var title_label: Label
var status_label: Label
var time_label: Label
var fps_label: Label
var build_label: Label
var fps_timer := 0.0
var progress: ProgressBar
var fit_serial := 0


func _init() -> void:
	panel_size = Vector2(WIDTH, MIN_HEIGHT)
	distance = 1.3
	drop = 0.6
	tilt = -25.0


func _build() -> Control:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", VpxTheme.flat(Color(VpxTheme.BACKGROUND, CARD_ALPHA), 20, 24, 12))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)
	items = HFlowContainer.new()
	items.add_theme_constant_override("h_separation", 26)
	items.add_theme_constant_override("v_separation", 6)
	column.add_child(items)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	title_label = _label(TITLE_FONT_SIZE, VpxTheme.ACCENT_HOVER)
	footer.add_child(title_label)
	status_label = _label(FONT_SIZE, VpxTheme.MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)
	fps_label = _label(FONT_SIZE, VpxTheme.MUTED)
	footer.add_child(fps_label)
	time_label = _label(FONT_SIZE, VpxTheme.MUTED)
	footer.add_child(time_label)
	build_label = _label(FONT_SIZE, VpxTheme.MUTED)
	footer.add_child(build_label)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 5
	progress.add_theme_stylebox_override("background", VpxTheme.flat(VpxTheme.TRACK, 3, 0, 0))
	progress.add_theme_stylebox_override("fill", VpxTheme.accent_flat(3, 0, 0))
	column.add_child(progress)
	Settings.changed.connect(_fit)
	return root


func show_help(title: String, entries: Array, camera: Camera3D, status := "") -> void:
	title_label.text = title
	title_label.add_theme_color_override("font_color", VpxTheme.ACCENT_HOVER)
	status_label.text = status
	build_label.text = player.build_label() if player != null else Log.version_label()
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()
	for entry in entries:
		items.add_child(_item(entry[0], entry[1], entry[2]))
	present(camera)
	_refresh_progress()
	_refresh_fps()
	_fit()


func _process(delta: float) -> void:
	super(delta)
	if not visible:
		return
	_refresh_progress()
	fps_timer += delta
	if fps_timer >= FPS_INTERVAL:
		_refresh_fps()


func _refresh_fps() -> void:
	fps_timer = 0.0
	var has_video := player != null and not player.current_path.is_empty() and not player.is_image()
	fps_label.visible = has_video
	if not has_video:
		return
	var shown := player.shown_fps()
	fps_label.text = "%.0f / %.0f fps" % [shown, player.playback_fps()] if shown > 0.0 else "— / %.0f fps" % player.playback_fps()


func _refresh_progress() -> void:
	var has_video := player != null and not player.current_path.is_empty() and not player.is_image()
	progress.visible = has_video
	time_label.visible = has_video
	if not has_video:
		return
	var length := player.get_stream_length()
	progress.max_value = maxf(length, 1.0)
	progress.value = player.stream_position
	time_label.text = "%s / %s" % [_format_time(player.stream_position), _format_time(length)]


func _fit() -> void:
	fit_serial += 1
	var serial := fit_serial
	await get_tree().process_frame
	if serial != fit_serial:
		return
	var size := Vector2(WIDTH, maxf(content.get_combined_minimum_size().y / texture_density, MIN_HEIGHT))
	if not size.is_equal_approx(panel_size):
		resize(size)


func _item(key: String, text: String, value: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.RAISED, 10, 10, 2))
	var key_label := _label(KEY_FONT_SIZE, VpxTheme.TEXT)
	key_label.text = key
	chip.add_child(key_label)
	line.add_child(chip)
	var label := _label(FONT_SIZE, VpxTheme.TEXT)
	label.text = text
	line.add_child(label)
	if not value.is_empty():
		var value_label := _label(FONT_SIZE, VpxTheme.ACCENT_HOVER)
		value_label.text = value
		line.add_child(value_label)
	return line


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
