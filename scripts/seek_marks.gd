extends Control

signal bookmark_hovered(time: float)
signal bookmark_selected(time: float)

const BOOKMARK_COLOR := VpxTheme.FAVORITE
const TICK_WIDTH := 3.0
const TICK_HEIGHT := 14.0

var length := 0.0
var inset := 0.0
var chapters: Array = []
var bookmarks: Array = []
var loop := Vector2(-1.0, -1.0)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	set_anchors_preset(PRESET_FULL_RECT)


func bookmark_at(point: Vector2) -> float:
	if length <= 0.0 or point.y < size.y * 0.5 - TICK_HEIGHT - 2.0 or point.y > size.y * 0.5 - 1.0:
		return -1.0
	var nearest := -1.0
	var distance := 9.0
	for time: float in bookmarks:
		var delta := absf(point.x - _x(time))
		if delta < distance:
			nearest = time
			distance = delta
	return nearest


func _has_point(point: Vector2) -> bool:
	return bookmark_at(point) >= 0.0


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var time := bookmark_at(mouse.position)
	if time < 0.0:
		return
	if event is InputEventMouseMotion:
		bookmark_hovered.emit(time)
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if button.pressed:
			bookmark_selected.emit(time)


func show_marks(p_length: float, p_inset: float, p_chapters: Array, p_bookmarks: Array, p_loop: Vector2) -> void:
	length = p_length
	inset = p_inset
	chapters = p_chapters
	bookmarks = p_bookmarks
	loop = p_loop
	queue_redraw()


func _x(time: float) -> float:
	return inset + clampf(time / maxf(length, 0.001), 0.0, 1.0) * (size.x - inset * 2.0)


func _draw() -> void:
	if length <= 0.0:
		return
	var middle := size.y * 0.5
	if loop.x >= 0.0:
		var end := loop.y if loop.y >= 0.0 else loop.x
		draw_rect(Rect2(_x(loop.x), middle - TICK_HEIGHT * 0.5, maxf(_x(end) - _x(loop.x), TICK_WIDTH), TICK_HEIGHT), Color(VpxTheme.ACCENT, 0.35))
		for time: float in [loop.x, end]:
			_tick(time, VpxTheme.ACCENT_HOVER)
	for chapter: Dictionary in chapters:
		var start := float(chapter["start"])
		if start > 0.5:
			_tick(start, VpxTheme.TEXT)
	for time: float in bookmarks:
		var x := _x(time)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 7.0, middle - TICK_HEIGHT), Vector2(x + 7.0, middle - TICK_HEIGHT), Vector2(x, middle - 3.0)]), BOOKMARK_COLOR)


func _tick(time: float, outline: Color) -> void:
	var rect := Rect2(_x(time) - TICK_WIDTH * 0.5, (size.y - TICK_HEIGHT) * 0.5, TICK_WIDTH, TICK_HEIGHT)
	draw_rect(rect.grow(1.0), outline)
	draw_rect(rect, VpxTheme.ON_ACCENT)
