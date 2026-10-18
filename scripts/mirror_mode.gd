extends SubViewport

var button: Button
var screen_rect := Rect2()
var held := false


func _ready() -> void:
	disable_3d = true
	gui_disable_input = false
	size = Vector2i(200, 56)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	button = Button.new()
	button.text = "Exit VR"
	button.icon = VpxTheme.icon("screen")
	button.theme = VpxTheme.build()
	add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.viewport_set_parent_viewport(get_viewport_rid(), RID())
	_update_layout()


func _process(_delta: float) -> void:
	_update_layout()


func _update_layout() -> void:
	size = Vector2i(Vector2(200, 56).max(button.get_combined_minimum_size()).ceil())
	var window := DisplayServer.window_get_size()
	var rect := Rect2(Vector2(maxi(window.x - size.x - 16, 0), 16), Vector2(size))
	if rect == screen_rect:
		return
	screen_rect = rect
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_attach_to_screen(get_viewport_rid(), screen_rect, get_window().get_window_id())


func handle_input(event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	if mouse == null:
		return false
	var inside := screen_rect.has_point(mouse.position)
	var consumed := inside or held
	if mouse is InputEventMouseButton:
		if mouse.button_index != MOUSE_BUTTON_LEFT or not consumed:
			return false
		held = mouse.pressed
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position -= screen_rect.position
	forwarded.global_position = forwarded.position
	push_input(forwarded, true)
	return consumed
