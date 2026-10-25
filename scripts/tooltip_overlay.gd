extends CanvasLayer

const DELAY := 0.55
const MOVE_THRESHOLD := 6.0
const EDGE := 12.0
const OFFSET := Vector2(18, 26)

var panel: PanelContainer
var source: Control
var text := ""
var anchor := Vector2.ZERO
var elapsed := 0.0
var blocked := false
var content: Control
var text_scale := 0.0
var bounds := Vector2.ZERO
var pointer_position := Vector2(-1, -1)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.theme = VpxTheme.build()
	panel.theme_type_variation = &"TooltipSurface"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = true
	panel.hide()
	add_child(panel)
	if get_viewport() is Window:
		get_viewport().mouse_exited.connect(func() -> void:
			pointer_position = Vector2(-1, -1)
			_clear())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
		if event.position.distance_to(anchor) > MOVE_THRESHOLD:
			anchor = event.position
			_reset()
			blocked = false
	elif event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_reset()
		blocked = true


func _process(delta: float) -> void:
	var viewport := get_viewport()
	if viewport is Window and (not viewport.visible or not viewport.has_focus()):
		_clear()
		return
	for window in viewport.get_embedded_subwindows():
		if window.visible:
			_clear()
			return
	var hovered := viewport.gui_get_hovered_control()
	var next_source: Control
	var next_text := ""
	var cursor := pointer_position
	var area := viewport.get_visible_rect().size
	if not Rect2(Vector2.ZERO, area).has_point(cursor):
		_clear()
		return
	while is_instance_valid(hovered) and hovered.is_visible_in_tree():
		next_text = get_node("/root/Tooltips").get_text(hovered, hovered.get_global_transform_with_canvas().affine_inverse() * cursor).strip_edges()
		if not next_text.is_empty():
			next_source = hovered
			break
		if hovered.mouse_filter == Control.MOUSE_FILTER_STOP or hovered.top_level:
			break
		hovered = hovered.get_parent_control()
	var next_scale := next_source.get_global_transform_with_canvas().get_scale().abs() if is_instance_valid(next_source) else Vector2.ONE
	next_scale = next_scale.max(Vector2.ONE * 0.001)
	if next_source != source or next_text != text or not area.is_equal_approx(bounds) or not is_equal_approx(text_scale, VpxTheme.text_size) or not panel.scale.is_equal_approx(next_scale):
		_reset()
		blocked = false
		source = next_source
		text = next_text
		anchor = cursor
		bounds = area
		text_scale = VpxTheme.text_size
		panel.scale = next_scale
	if not is_instance_valid(source) or text.is_empty() or blocked:
		return
	elapsed += delta
	if elapsed >= DELAY and not panel.visible:
		_show_tooltip()
	if panel.visible:
		_place()


func _reset() -> void:
	elapsed = 0.0
	panel.hide()


func _clear() -> void:
	_reset()
	source = null
	text = ""


func _show_tooltip() -> void:
	if is_instance_valid(content):
		panel.remove_child(content)
		content.queue_free()
	content = null
	var style := panel.get_theme_stylebox("panel")
	var available := (bounds / panel.scale - Vector2.ONE * EDGE * 2.0 - style.get_minimum_size()).max(Vector2.ONE)
	var width := minf(520.0 * VpxTheme.text_size, available.x)
	if source.has_method("_make_custom_tooltip"):
		content = source.call("_make_custom_tooltip", text) as Control
		if is_instance_valid(content):
			var wrapper := ScrollContainer.new()
			wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			wrapper.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
			wrapper.custom_minimum_size = Vector2(width, 0)
			panel.add_child(wrapper)
			wrapper.add_child(content)
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.size.x = width
			wrapper.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, available.y)
			panel.remove_child(wrapper)
			content = wrapper
	if not is_instance_valid(content):
		var label := Label.new()
		label.theme_type_variation = &"TooltipLabel"
		label.text = source.tr(text)
		var font := panel.theme.get_font("font", "TooltipLabel")
		var font_size := panel.theme.get_font_size("font_size", "TooltipLabel")
		width = minf(width, font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		label.custom_minimum_size.x = width
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = maxi(1, floori(available.y / font.get_height(font_size)))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content = label
	_ignore_mouse(content)
	panel.add_child(content)
	panel.reset_size()
	panel.show()
	_place()


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)


func _place() -> void:
	var cursor := pointer_position
	var rendered_size := panel.size * panel.scale
	var edge := Vector2.ONE * EDGE * panel.scale
	var offset := OFFSET * panel.scale
	var position := cursor + offset
	if position.y + rendered_size.y > bounds.y - edge.y:
		position.y = cursor.y - rendered_size.y - offset.y
	panel.position = position.clamp(edge, (bounds - rendered_size - edge).max(edge))
