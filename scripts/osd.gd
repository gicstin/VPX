extends FloatPanel

const SHOW_SECONDS := 2.0
const CARD_ALPHA := VpxTheme.OVERLAY_ALPHA
const TIMELINE_HEIGHT := 0.11
const STATUS_HEIGHT := 0.068

@export var player: VPXPlayer

var title_label: Label
var time_label: Label
var progress: ProgressBar
var remaining := 0.0
var sticky := false
var holding := false
var root: PanelContainer


func _init() -> void:
	panel_size = Vector2(0.86, TIMELINE_HEIGHT)
	distance = 1.4
	drop = 0.62
	tilt = -22.0


func _build() -> Control:
	root = PanelContainer.new()
	root.add_theme_stylebox_override("panel", VpxTheme.flat(Color(VpxTheme.BACKGROUND, CARD_ALPHA), 22, 28, 12))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	root.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title_label)
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(time_label)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	progress.add_theme_stylebox_override("background", VpxTheme.flat(VpxTheme.TRACK, 6, 0, 0))
	progress.add_theme_stylebox_override("fill", VpxTheme.accent_flat(6, 0, 0))
	rows.add_child(progress)
	return root


func show_status(title: String, camera: Camera3D, hold := false) -> void:
	title_label.text = title
	remaining = SHOW_SECONDS
	sticky = hold
	root.add_theme_stylebox_override("panel", card(VpxTheme.BACKGROUND, 28, 36, 18) if hold else VpxTheme.flat(Color(VpxTheme.BACKGROUND, CARD_ALPHA), 22, 28, 12))
	present(camera)
	_refresh()


func show_hold(title: String, fraction: float, camera: Camera3D) -> void:
	if not holding:
		holding = true
		show_status(title, camera, true)
		time_label.text = ""
	_set_timeline_visible(true)
	progress.max_value = 1.0
	progress.value = clampf(fraction, 0.0, 1.0)


func end_hold() -> void:
	if not holding:
		return
	holding = false
	release()
	dismiss()


func release() -> void:
	sticky = false
	remaining = 0.0


func _process(delta: float) -> void:
	super(delta)
	if not visible:
		return
	if not sticky:
		remaining -= delta
	if remaining <= 0.0:
		dismiss()
		return
	_refresh()


func _refresh() -> void:
	if holding:
		return
	_set_timeline_visible(get_viewport().use_xr or (not player.is_image() and not player.is_music_mode()))
	if not progress.visible:
		time_label.text = ""
		return
	var length := player.get_stream_length() if not player.current_path.is_empty() else 0.0
	progress.max_value = maxf(length, 1.0)
	progress.value = player.stream_position
	time_label.text = "%s / %s" % [format_time(player.stream_position), format_time(length)]


func _set_timeline_visible(shown: bool) -> void:
	progress.visible = shown
	var wanted := Vector2(panel_size.x, (TIMELINE_HEIGHT if shown else STATUS_HEIGHT) * Settings.text_size)
	if not panel_size.is_equal_approx(wanted):
		resize(wanted)


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
