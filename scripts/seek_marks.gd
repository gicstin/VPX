extends Control

const BOOKMARK_COLOR := VpxTheme.FAVORITE
const TICK_WIDTH := 3.0
const TICK_HEIGHT := 14.0

var length := 0.0
var inset := 0.0
var chapters: Array = []
var bookmarks: Array = []
var loop := Vector2(-1.0, -1.0)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)


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
