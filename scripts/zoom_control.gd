extends Stepper

var slider: HSlider
var pending := false
var settle := 0.0
var dragging := false


func _build() -> void:
	super._build()
	slider = HSlider.new()
	slider.min_value = _slider_value(min_value)
	slider.max_value = _slider_value(max_value)
	slider.step = 0.0
	slider.custom_minimum_size = Vector2(140, ROW_HEIGHT)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.value = _slider_value(float(read()))
	slider.value_changed.connect(func(next: float) -> void:
		pending = true
		settle = 0.0
		_preview(exp(next) if setting == &"picture_zoom" else next))
	slider.drag_started.connect(func() -> void: dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging = false
		_commit())
	slider.focus_exited.connect(_commit)
	add_child(slider)
	Settings.zoom_changed.connect(func(_snap: bool) -> void: _pull())
	Settings.screen_size_changed.connect(_pull)


func _bind_hold(button: Button, dir: int) -> void:
	button.button_down.connect(func() -> void: direction = dir)
	button.button_up.connect(_release)
	button.mouse_exited.connect(_release)


func _process(delta: float) -> void:
	var viewport := get_viewport() as SubViewport
	if not is_visible_in_tree() or (viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED):
		if direction != 0 or pending:
			dragging = false
			_release()
		return
	if direction == 0:
		if pending:
			settle += delta
			if settle > 0.25 and not dragging:
				pending = false
				_commit()
		return
	if setting == &"picture_zoom":
		_preview(Settings.picture_zoom * exp(direction * Settings.ZOOM_RATE * delta))
	else:
		_preview(Settings.screen_size + direction * Settings.SCREEN_SIZE_RATE * delta)


func nudge(amount: float) -> void:
	_preview(Settings.picture_zoom * exp(amount) if setting == &"picture_zoom" else Settings.screen_size + amount)


func _release() -> void:
	super._release()
	_commit()


func _pull() -> void:
	show_value(float(read()))
	if slider != null:
		slider.set_value_no_signal(_slider_value(float(read())))


func _slider_value(next: float) -> float:
	return log(next) if setting == &"picture_zoom" else next


func _preview(next: float) -> void:
	if setting == &"picture_zoom":
		Settings.preview_zoom(next)
	else:
		Settings.preview_screen_size(next)


func _commit() -> void:
	pending = false
	if setting == &"picture_zoom":
		Settings.commit_zoom()
	else:
		Settings.commit()
