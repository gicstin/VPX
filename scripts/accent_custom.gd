extends SettingRow

const MIN_BRIGHTNESS := 0.35
const HUE_STOPS := 12

var hue_slider: HSlider
var saturation_slider: HSlider
var brightness_slider: HSlider
var shown := Color(0, 0, 0, 0)
var dragging := false


func _build() -> void:
	hue_slider = _slider("Hue", 0.0, 1.0, _hue_track())
	saturation_slider = _slider("Saturation", 0.0, 1.0)
	brightness_slider = _slider("Brightness", MIN_BRIGHTNESS, 1.0)


func _slider(tip: String, min_value: float, max_value: float, track: StyleBox = null) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.0
	slider.tooltip_text = tip
	slider.focus_mode = FOCUS_NONE
	slider.custom_minimum_size = Vector2(120, ROW_HEIGHT)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	if track != null:
		slider.add_theme_stylebox_override("slider", track)
		for area in ["grabber_area", "grabber_area_highlight"]:
			slider.add_theme_stylebox_override(area, StyleBoxEmpty.new())
	slider.value_changed.connect(func(_value: float) -> void:
		if dragging:
			VpxTheme.set_accent(_picked())
		else:
			_commit())
	slider.drag_started.connect(func() -> void: dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging = false
		_commit())
	add_child(slider)
	return slider


func _hue_track() -> StyleBoxTexture:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in HUE_STOPS + 1:
		var t := float(i) / HUE_STOPS
		offsets.append(t)
		colors.append(Color.from_hsv(t, 0.6, 0.9))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box


func _picked() -> Color:
	return Color.from_hsv(hue_slider.value, saturation_slider.value, brightness_slider.value)


func _commit() -> void:
	shown = _picked()
	write(shown)


func _label_expands() -> bool:
	return false


func _pull() -> void:
	var current: Color = read()
	if current.is_equal_approx(shown):
		return
	shown = current
	if current.s > 0.01:
		hue_slider.set_value_no_signal(current.h)
	saturation_slider.set_value_no_signal(current.s)
	brightness_slider.set_value_no_signal(maxf(current.v, MIN_BRIGHTNESS))
