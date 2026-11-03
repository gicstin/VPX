extends Control

signal mark_hovered(time: float)
signal mark_selected(time: float)

const BOOKMARK_COLOR := VpxTheme.FAVORITE
const SESSION_COLOR := VpxTheme.MUTED
const TICK_WIDTH := 4.0
const TICK_HEIGHT := 14.0
const BOOKMARK_GRAB := 13.0
const CHAPTER_GRAB := 11.0
const AUTO_GRAB := 10.0
const SCENE_GRAB := 5.0
const STICKY_PAD := 8.0
const PIN_HALF := 8.0
const PIN_HOVER_HALF := 10.0

var length := 0.0
var inset := 0.0
var chapters: Array = []
var bookmarks: Array = []
var loop := Vector2(-1.0, -1.0)
var session_start := -1.0
var last_jump := -1.0
var scenes: Array = []
var hovered := -1.0
var hovered_bookmark := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_exited.connect(func() -> void:
		if hovered >= 0.0:
			hovered = -1.0
			queue_redraw())


func _row_height() -> float:
	var parent := get_parent() as Control
	var height := maxf(size.y, parent.size.y) if parent != null else size.y
	return maxf(height, TICK_HEIGHT + 4.0)


func _in_band(point: Vector2) -> bool:
	return length > 0.0 and point.y >= 0.0 and point.y <= _row_height()


func _on_handle(point: Vector2) -> bool:
	var slider := get_parent() as Range
	if slider == null or not slider.editable:
		return false
	var grabber: Texture2D = slider.get_theme_icon("grabber")
	var half := (grabber.get_width() * 0.5 if grabber != null else 8.0) + 1.0
	return absf(point.x - _x(float(slider.value))) <= half


func bookmark_at(point: Vector2) -> float:
	if not _in_band(point) or _on_handle(point):
		return -1.0
	var nearest := -1.0
	var distance := BOOKMARK_GRAB
	for time: float in bookmarks:
		var delta := absf(point.x - _x(time))
		if delta < distance:
			nearest = time
			distance = delta
	return nearest


func chapter_at(point: Vector2) -> float:
	if not _in_band(point) or _on_handle(point):
		return -1.0
	var nearest := -1.0
	var distance := CHAPTER_GRAB
	for chapter: Dictionary in chapters:
		var start := float(chapter["start"])
		if start <= 0.5:
			continue
		var delta := absf(point.x - _x(start))
		if delta < distance:
			nearest = start
			distance = delta
	return nearest


func auto_at(point: Vector2) -> float:
	if not _in_band(point) or _on_handle(point):
		return -1.0
	var nearest := -1.0
	var distance := AUTO_GRAB
	for time: float in [session_start, last_jump]:
		if time < 0.0:
			continue
		var delta := absf(point.x - _x(time))
		if delta < distance:
			nearest = time
			distance = delta
	return nearest


func scene_at(point: Vector2) -> float:
	if not _in_band(point) or _on_handle(point):
		return -1.0
	var nearest := -1.0
	var distance := SCENE_GRAB
	for time: float in scenes:
		var delta := absf(point.x - _x(time))
		if delta < distance:
			nearest = time
			distance = delta
	return nearest


func mark_at(point: Vector2) -> float:
	var bookmark := bookmark_at(point)
	if bookmark >= 0.0:
		return bookmark
	var chapter := chapter_at(point)
	if chapter >= 0.0:
		return chapter
	var auto := auto_at(point)
	return auto if auto >= 0.0 else scene_at(point)


func _grab(bookmark: bool) -> float:
	return BOOKMARK_GRAB if bookmark else CHAPTER_GRAB


func _has_point(point: Vector2) -> bool:
	if length <= 0.0 or _on_handle(point):
		return false
	if hovered >= 0.0 and absf(point.x - _x(hovered)) <= _grab(hovered_bookmark) + STICKY_PAD:
		return true
	return mark_at(point) >= 0.0


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var bookmark := bookmark_at(mouse.position)
	var time := bookmark
	if time < 0.0:
		time = chapter_at(mouse.position)
	if time < 0.0:
		time = auto_at(mouse.position)
	if time < 0.0:
		time = scene_at(mouse.position)
	if time < 0.0:
		if hovered >= 0.0:
			hovered = -1.0
			queue_redraw()
		return
	if event is InputEventMouseMotion:
		hovered = time
		hovered_bookmark = bookmark >= 0.0
		queue_redraw()
		mark_hovered.emit(time)
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if button.pressed:
			mark_selected.emit(time)


func show_marks(p_length: float, p_inset: float, p_chapters: Array, p_bookmarks: Array, p_loop: Vector2, p_session_start := -1.0, p_last_jump := -1.0, p_scenes: Array = []) -> void:
	length = p_length
	inset = p_inset
	chapters = p_chapters
	bookmarks = p_bookmarks
	loop = p_loop
	session_start = p_session_start
	last_jump = p_last_jump
	scenes = p_scenes
	hovered = -1.0
	queue_redraw()


func _x(time: float) -> float:
	return inset + clampf(time / maxf(length, 0.001), 0.0, 1.0) * (size.x - inset * 2.0)


func _hovering(time: float, bookmark: bool) -> bool:
	return hovered_bookmark == bookmark and is_equal_approx(hovered, time)


func _draw() -> void:
	if length <= 0.0:
		return
	var middle := _row_height() * 0.5
	if loop.x >= 0.0:
		var end := loop.y if loop.y >= 0.0 else loop.x
		draw_rect(Rect2(_x(loop.x), middle - TICK_HEIGHT * 0.5, maxf(_x(end) - _x(loop.x), TICK_WIDTH), TICK_HEIGHT), Color(VpxTheme.ACCENT, 0.35))
		for time: float in [loop.x, end]:
			_tick(time, VpxTheme.ACCENT_HOVER, TICK_WIDTH)
	for chapter: Dictionary in chapters:
		var start := float(chapter["start"])
		if start <= 0.5:
			continue
		var active := _hovering(start, false)
		_tick(start, VpxTheme.ACCENT_HOVER if active else VpxTheme.TEXT, 7.0 if active else TICK_WIDTH)
	for time: float in bookmarks:
		var x := _x(time)
		var half := PIN_HOVER_HALF if _hovering(time, true) else PIN_HALF
		draw_colored_polygon(PackedVector2Array([Vector2(x - half, middle - TICK_HEIGHT), Vector2(x + half, middle - TICK_HEIGHT), Vector2(x, middle - 2.0)]), BOOKMARK_COLOR)
	var lane := middle + TICK_HEIGHT * 0.5 + 2.0
	if session_start >= 0.0:
		var sx := _x(session_start)
		draw_rect(Rect2(sx - 1.0, lane, 2.0, 5.0), SESSION_COLOR)
	if last_jump >= 0.0:
		var jx := _x(last_jump)
		draw_colored_polygon(PackedVector2Array([Vector2(jx - 5.0, lane), Vector2(jx + 5.0, lane), Vector2(jx, lane + 5.0)]), VpxTheme.ACCENT)
	var dot_y := minf(lane + 9.0, _row_height() - 2.0)
	for time: float in scenes:
		draw_circle(Vector2(_x(time), dot_y), 1.5, VpxTheme.FAINT)


func _tick(time: float, outline: Color, width: float) -> void:
	var rect := Rect2(_x(time) - width * 0.5, (_row_height() - TICK_HEIGHT) * 0.5, width, TICK_HEIGHT)
	draw_rect(rect.grow(1.0), outline)
	draw_rect(rect, VpxTheme.ON_ACCENT)
