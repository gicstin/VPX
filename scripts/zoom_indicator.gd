extends FloatPanel

const SHOW_SECONDS := 1.4
const OPEN_QUIET_MSEC := 900
const WIDTH := 380.0
const HEIGHT := 96.0

var player: VPXPlayer
var camera: Camera3D
var screen: Node3D
var menu: Node3D
var value_label: Label
var bar: ProgressBar
var unity_mark: ColorRect
var remaining := 0.0
var opened_at := -OPEN_QUIET_MSEC


func _init() -> void:
	panel_size = Vector2(WIDTH, HEIGHT) / TEXTURE_DENSITY
	distance = 1.2
	drop = 0.2
	tilt = -10.0


func _ready() -> void:
	super._ready()
	Settings.zoom_changed.connect(_on_zoom_changed)
	player.opened.connect(func(_path: String) -> void: opened_at = Time.get_ticks_msec())


func _build() -> Control:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 22, 24, 12))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	root.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "Zoom"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", VpxTheme.MUTED)
	header.add_child(title)
	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
	bar.min_value = log(Settings.ZOOM_MIN)
	bar.max_value = log(Settings.ZOOM_MAX)
	bar.step = 0.0
	rows.add_child(bar)
	unity_mark = ColorRect.new()
	unity_mark.color = VpxTheme.TEXT
	unity_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(unity_mark)
	return root


func _on_zoom_changed(_snap: bool) -> void:
	if Time.get_ticks_msec() - opened_at < OPEN_QUIET_MSEC or not player.has_picture() or (menu != null and menu.visible):
		return
	remaining = SHOW_SECONDS
	_refresh()
	present(camera)


func _process(delta: float) -> void:
	super._process(delta)
	if not visible:
		return
	remaining -= delta
	if remaining <= 0.0 and target_opacity > 0.0:
		dismiss()
	_refresh()


func _refresh() -> void:
	var zoom: float = screen.displayed_zoom if screen != null else Settings.picture_zoom
	value_label.text = "%.0f%%" % (Settings.picture_zoom * 100.0)
	bar.value = log(maxf(zoom, Settings.ZOOM_MIN))
	var unity := (0.0 - bar.min_value) / (bar.max_value - bar.min_value)
	unity_mark.position = Vector2(bar.size.x * unity - 1.5, -4.0)
	unity_mark.size = Vector2(3.0, bar.size.y + 8.0)
