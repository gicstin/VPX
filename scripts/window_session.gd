extends Node

const MIN_SIZE := Vector2i(640, 360)
const POLL_INTERVAL := 0.2

var state := {}
var elapsed := 0.0
var active := false
var last_mode := DisplayServer.WINDOW_MODE_WINDOWED
var mini_active := false
var mini_transition := false
var mini_restore := {}


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
	state.merge({"bounds": bounds, "screen": screens[screen], "mode": mode}, true)
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
	if not active or mini_transition:
		return
	if mini_active:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			state["mini_screen"] = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			state["mini_bounds"] = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
			_save_state()
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
	_save_state(mode_changed)


func _save_state(flush := false) -> void:
	if Settings.window_session != state:
		Settings.window_session = state.duplicate(true)
		Settings.save_config()
		if flush:
			Settings.flush()


func toggle_fullscreen() -> void:
	if mini_active or mini_transition:
		return
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


func enter_mini(ui_scale := 1.0, logical_size := Vector2(480, 344)) -> bool:
	if mini_active or mini_transition or not active:
		return false
	capture()
	mini_restore = {"mode": DisplayServer.window_get_mode(), "bounds": state["bounds"], "screen": DisplayServer.window_get_current_screen(), "minimum": get_window().min_size, "borderless": get_window().borderless, "top": get_window().always_on_top, "unresizable": get_window().unresizable, "maximum": get_window().max_size, "transparent": get_window().transparent, "transparent_bg": get_window().transparent_bg}
	mini_transition = true
	mini_active = true
	state["mini_active"] = true
	_save_state(true)
	get_window().mode = Window.MODE_WINDOWED
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().borderless = true
	get_window().always_on_top = bool(state.get("mini_pinned", true))
	var screens: Array[Rect2i] = []
	for index in DisplayServer.get_screen_count():
		screens.append(DisplayServer.screen_get_usable_rect(index))
	var saved_bounds: Variant = state.get("mini_bounds")
	var saved_screen: Variant = state.get("mini_screen")
	var screen := select_screen(saved_screen if saved_screen is Rect2i else Rect2i(), saved_bounds if saved_bounds is Rect2i else Rect2i(), screens, DisplayServer.window_get_current_screen())
	DisplayServer.window_set_current_screen(screen)
	var usable := screens[screen]
	var target := Vector2i((logical_size * ui_scale).round()).min(usable.size)
	var saved: Variant = state.get("mini_bounds")
	var position: Vector2i = saved.position if saved is Rect2i else usable.end - target - Vector2i(24, 24)
	get_window().min_size = Vector2i.ZERO
	get_window().max_size = Vector2i.ZERO
	get_window().size = target
	get_window().min_size = target
	get_window().max_size = target
	get_window().unresizable = true
	get_window().position = position.clamp(usable.position, usable.end - target)
	await get_tree().process_frame
	mini_transition = false
	return true


func leave_mini() -> void:
	if not mini_active or mini_transition:
		return
	capture()
	mini_transition = true
	get_window().mode = Window.MODE_WINDOWED
	get_window().max_size = Vector2i.ZERO
	get_window().min_size = Vector2i.ZERO
	get_window().unresizable = mini_restore["unresizable"]
	get_window().always_on_top = mini_restore["top"]
	get_window().transparent = mini_restore["transparent"]
	get_window().transparent_bg = mini_restore["transparent_bg"]
	get_window().borderless = mini_restore["borderless"]
	var screen := clampi(int(mini_restore["screen"]), 0, DisplayServer.get_screen_count() - 1)
	DisplayServer.window_set_current_screen(screen)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	get_window().min_size = Vector2i(mini_restore["minimum"]).min(usable.size)
	var bounds := fit_bounds(mini_restore["bounds"], usable)
	get_window().size = bounds.size
	get_window().position = bounds.position
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().max_size = mini_restore["maximum"]
	get_window().mode = restored_mode(mini_restore["mode"]) as Window.Mode
	last_mode = restored_mode(mini_restore["mode"])
	mini_active = false
	mini_transition = false
	state["mini_active"] = false
	_save_state(true)


func pin_mini(pinned: bool) -> void:
	if not mini_active:
		return
	get_window().always_on_top = pinned
	state["mini_pinned"] = pinned
	_save_state()
