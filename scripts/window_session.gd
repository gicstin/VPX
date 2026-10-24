extends Node

const MIN_SIZE := Vector2i(640, 360)
const POLL_INTERVAL := 0.2

var state := {}
var elapsed := 0.0
var active := false
var last_mode := DisplayServer.WINDOW_MODE_WINDOWED


static func restored_mode(value: Variant) -> int:
	if value is int and value in [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		return value
	return DisplayServer.WINDOW_MODE_WINDOWED


static func fit_bounds(bounds: Rect2i, usable: Rect2i) -> Rect2i:
	var minimum := MIN_SIZE.min(usable.size)
	var size := bounds.size.clamp(minimum, usable.size)
	return Rect2i(bounds.position.clamp(usable.position, usable.end - size), size)


static func select_screen(saved_screen: Rect2i, bounds: Rect2i, screens: Array[Rect2i], fallback: int) -> int:
	for index in screens.size():
		if screens[index] == saved_screen:
			return index
	var selected := clampi(fallback, 0, screens.size() - 1)
	var overlap := 0
	for index in screens.size():
		var area := screens[index].intersection(bounds).get_area()
		if area > overlap:
			overlap = area
			selected = index
	return selected


func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	state = Settings.window_session.duplicate(true)
	var screens: Array[Rect2i] = []
	for index in DisplayServer.get_screen_count():
		screens.append(DisplayServer.screen_get_usable_rect(index))
	if screens.is_empty():
		return
	var bounds := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var saved_bounds: Variant = state.get("bounds")
	if saved_bounds is Rect2i and saved_bounds.size.x > 0 and saved_bounds.size.y > 0:
		bounds = saved_bounds
	var saved_screen: Variant = state.get("screen")
	var screen := select_screen(saved_screen if saved_screen is Rect2i else Rect2i(), bounds, screens, DisplayServer.window_get_current_screen())
	var mode := restored_mode(state.get("mode"))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen)
	var decorations := (DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()).max(Vector2i.ZERO)
	var inset := (DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()).max(Vector2i.ZERO)
	var usable := Rect2i(screens[screen].position + inset, (screens[screen].size - decorations).max(Vector2i.ONE))
	bounds = fit_bounds(bounds, usable)
	get_window().min_size = MIN_SIZE.min(usable.size)
	DisplayServer.window_set_size(bounds.size)
	DisplayServer.window_set_position(bounds.position)
	state = {"bounds": bounds, "screen": screens[screen], "mode": mode}
	if mode != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(mode)
	last_mode = mode
	active = true
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	capture(false)
	set_process(true)


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < POLL_INTERVAL:
		return
	elapsed = 0.0
	capture()


func capture(include_bounds := true) -> void:
	if not active:
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	var mode_changed := mode != last_mode
	last_mode = mode
	state["mode"] = restored_mode(mode)
	state["screen"] = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if include_bounds and not mode_changed and mode == DisplayServer.WINDOW_MODE_WINDOWED:
		state["bounds"] = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	if Settings.window_session != state:
		Settings.window_session = state.duplicate(true)
		Settings.save_config()
		if mode_changed:
			Settings.flush()


func toggle_fullscreen() -> void:
	capture()
	var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if fullscreen and active:
		DisplayServer.window_set_size(state["bounds"].size)
		DisplayServer.window_set_position(state["bounds"].position)
	capture(false)


func _notification(what: int) -> void:
	if active and what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE]:
		capture()
		Settings.flush()
