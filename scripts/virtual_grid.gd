extends Control

const OVERSCAN_ROWS := 1
const BUILD_BUDGET_USEC := 3000

var columns := 1
var layout := 0
var h_separation := 0
var v_separation := 0
var items := PackedStringArray()
var scroll: ScrollContainer
var build: Callable
var release: Callable
var cell_height: Callable
var built := {}


func setup(p_scroll: ScrollContainer, p_columns: int, p_h_separation: int, p_v_separation: int, p_cell_height: Callable, p_build: Callable, p_release: Callable) -> void:
	scroll = p_scroll
	columns = maxi(p_columns, 1)
	h_separation = p_h_separation
	v_separation = p_v_separation
	cell_height = p_cell_height
	build = p_build
	release = p_release
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_horizontal = SIZE_EXPAND_FILL
	resized.connect(_relayout)


func set_items(p_items: PackedStringArray) -> void:
	for index: int in built.keys():
		if index >= p_items.size() or p_items[index] != items[index]:
			_drop(index)
	items = p_items
	_update_height()


func clear() -> void:
	for index: int in built.keys():
		_drop(index)
	items = PackedStringArray()
	_update_height()


func rebuild(key: String) -> void:
	for index: int in built.keys():
		if items[index] == key:
			_drop(index)


func is_empty() -> bool:
	return items.is_empty()


func pending() -> bool:
	var window := _window()
	for index in range(window.x, window.y):
		if not built.has(index):
			return true
	return false


func _process(_delta: float) -> void:
	sync()


func sync() -> void:
	if items.is_empty() or not is_visible_in_tree():
		return
	var window := _window()
	for index: int in built.keys():
		if (index < window.x or index >= window.y) and not built[index].has_focus():
			_drop(index)
	var complete := true
	for index in range(window.x, window.y):
		if not built.has(index):
			complete = false
			break
	if complete:
		return
	var started := Time.get_ticks_usec()
	for index in _build_order(window):
		if built.has(index):
			continue
		var control: Control = build.call(items[index], self)
		built[index] = control
		_place(index, control)
		if Time.get_ticks_usec() - started > BUILD_BUDGET_USEC:
			break


func index_of(control: Control) -> int:
	for index: int in built:
		if built[index] == control:
			return index
	return -1


func control_at(index: int) -> Control:
	if index < 0 or index >= items.size():
		return null
	if not built.has(index):
		var control: Control = build.call(items[index], self)
		built[index] = control
		_place(index, control)
	return built[index]


func first_built() -> Control:
	var indexes := built.keys()
	if indexes.is_empty():
		return null
	indexes.sort()
	return built[indexes[0]]


func page_rows() -> int:
	if scroll == null:
		return 1
	return maxi(floori(scroll.size.y / (_row_height() + v_separation)), 1)


func _build_order(window: Vector2i) -> Array[int]:
	var view := _view_rows()
	var order: Array[int] = []
	for index in range(maxi(view.x * columns, window.x), mini(view.y * columns, window.y)):
		order.append(index)
	for index in range(window.x, window.y):
		if index < view.x * columns or index >= view.y * columns:
			order.append(index)
	return order


func _cell_width() -> float:
	return maxf((size.x - h_separation * (columns - 1)) / columns, 1.0)


func _row_height() -> float:
	return float(cell_height.call(_cell_width()))


func _row_count() -> int:
	return ceili(items.size() / float(columns))


func _update_height() -> void:
	var rows := _row_count()
	custom_minimum_size.y = maxf(rows * _row_height() + maxi(rows - 1, 0) * v_separation, 0.0)


func _view_rows() -> Vector2i:
	if scroll == null:
		return Vector2i(0, _row_count())
	var pitch := _row_height() + v_separation
	var top := scroll.get_global_rect().position.y - get_global_rect().position.y
	var first := floori(top / pitch)
	var last := floori((top + scroll.size.y) / pitch) + 1
	return Vector2i(clampi(first, 0, _row_count()), clampi(last, 0, _row_count()))


func _window() -> Vector2i:
	var rows := _view_rows()
	var first := maxi(rows.x - OVERSCAN_ROWS, 0)
	var last := mini(rows.y + OVERSCAN_ROWS, _row_count())
	return Vector2i(first * columns, mini(last * columns, items.size()))


func _place(index: int, control: Control) -> void:
	var width := _cell_width()
	var height := _row_height()
	control.position = Vector2((index % columns) * (width + h_separation), (index / columns) * (height + v_separation))
	control.size = Vector2(width, height)


func _relayout() -> void:
	_update_height()
	for index: int in built:
		_place(index, built[index])


func _drop(index: int) -> void:
	var control: Control = built[index]
	built.erase(index)
	release.call(items[index], control)
	remove_child(control)
	control.queue_free()
