extends CanvasLayer

const SeekPreviews := preload("res://scripts/seek_previews.gd")
const MENU_FILL := 0.94
const MENU_REVEAL_SCALE := 0.97
const BACKDROP_ALPHA := 0.4
const OSD_BOTTOM_MARGIN := 0.04
const LOOK_SPEED := 0.003
const CLICK_SLOP := 6.0
const CURSOR_IDLE_SECONDS := 2.0
const OSD_REFRESH_SECONDS := 0.25
const SEEK_INTERVAL_SECONDS := 0.08
const SEEK_BAR_REACH := 28.0
const SPHERE_FOV := 75.0
const FOV_RANGE := Vector2(30.0, 110.0)
const FOV_STEP := 5.0

var main: Node3D
var camera: Camera3D
var screen: MeshInstance3D
var panel: Node3D
var ui_viewport: SubViewport
var osd: FloatPanel
var player: VPXPlayer

var backdrop: ColorRect
var menu_rect: TextureRect
var osd_rect: TextureRect
var preview_panel: PanelContainer
var preview_image: TextureRect
var preview_label: Label
var previews: SeekPreviews
var preview_time := -1.0
var menu_pressed := false
var press_position := Vector2.ZERO
var video_pressed := false
var menu_click_pressed := false
var dragged := false
var click_toggled := false
var skip_release := false
var seeking := false
var last_seek := -1.0
var last_seek_target := -1.0
var idle := 0.0
var osd_cooldown := 0.0
var sphere_fov := SPHERE_FOV


func _ready() -> void:
	layer = 10
	backdrop = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.0)
	osd_rect = _texture_rect(osd.viewport.get_texture())
	menu_rect = _texture_rect(ui_viewport.get_texture())
	for control: Control in [backdrop, osd_rect, menu_rect]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.visible = false
		add_child(control)
	previews = ui_viewport.get_node("UI").get("previews") as SeekPreviews
	previews.ready_for.connect(func(path: String) -> void:
		if previews.request_owner == self and preview_panel.visible and path == player.current_path:
			_show_preview_frame())
	_build_seek_preview()
	Settings.changed.connect(func() -> void:
		if not Settings.seek_previews:
			_hide_seek_preview())
	panel.quad.visible = false
	osd.quad.visible = false
	var reticle := ui_viewport.get_node_or_null("UI/Reticle") as Control
	if reticle != null:
		reticle.set_process(false)
		reticle.set_process_input(false)
		reticle.visible = false
	screen.flat_desktop = true
	screen.refresh()


func _build_seek_preview() -> void:
	preview_panel = PanelContainer.new()
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 12, 8, 8))
	preview_panel.visible = false
	add_child(preview_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	preview_panel.add_child(column)
	preview_image = TextureRect.new()
	preview_image.custom_minimum_size = Vector2(SeekPreviews.FRAME_SIZE)
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview_image)
	preview_label = Label.new()
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_color_override("font_color", VpxTheme.TEXT)
	preview_label.add_theme_font_size_override("font_size", 20)
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview_label)


func _texture_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return rect


func _process(delta: float) -> void:
	var window := get_viewport().get_visible_rect().size
	if window.x < 1.0 or window.y < 1.0:
		return
	_layout_menu(window)
	_layout_osd(window)
	_fit_camera(window)
	_update_cursor(delta)
	osd_cooldown -= delta
	if osd.visible and not panel.visible and not preview_panel.visible and Settings.seek_previews:
		_update_seek_preview(get_viewport().get_mouse_position())
	if preview_panel.visible:
		if not Settings.seek_previews or not osd.visible or panel.visible or previews.path != player.current_path:
			_hide_seek_preview()
		else:
			osd.remaining = maxf(osd.remaining, 0.5)
			_position_seek_preview()


func ui_scale(window: Vector2) -> float:
	var canvas := Vector2(ui_viewport.size_2d_override)
	return minf(window.x / canvas.x, window.y / canvas.y) * MENU_FILL


func _layout_menu(window: Vector2) -> void:
	var shown: bool = panel.visible
	menu_rect.visible = shown
	backdrop.visible = shown
	if not shown:
		return
	var reveal: float = panel.reveal
	var canvas := Vector2(ui_viewport.size_2d_override)
	menu_rect.size = canvas * ui_scale(window) * lerpf(MENU_REVEAL_SCALE, 1.0, reveal)
	menu_rect.position = ((window - menu_rect.size) * 0.5).round()
	menu_rect.modulate.a = panel.base_opacity * reveal
	backdrop.size = window
	backdrop.color.a = BACKDROP_ALPHA * reveal


func _layout_osd(window: Vector2) -> void:
	osd_rect.visible = osd.visible
	if not osd.visible:
		return
	osd_rect.size = Vector2(osd.viewport.size_2d_override) * ui_scale(window)
	osd_rect.position = Vector2((window.x - osd_rect.size.x) * 0.5, window.y * (1.0 - OSD_BOTTOM_MARGIN) - osd_rect.size.y).round()
	osd_rect.modulate.a = osd.opacity


func _is_flat() -> bool:
	if main.resonance_field != null and main.resonance_field.active:
		return false
	return Settings.projection == Settings.ProjectionMode.FLAT


func _fit_camera(window: Vector2) -> void:
	if not _is_flat():
		camera.fov = sphere_fov
		return
	var quad := screen.mesh as QuadMesh
	if quad == null or quad.size.x <= 0.0 or quad.size.y <= 0.0:
		return
	camera.global_transform = Transform3D(screen.global_basis.orthonormalized(), screen.get_parent().global_position)
	var tiles := float(Settings.flat_image_tiles()) if player.is_image() else 1.0
	var height := maxf(quad.size.y, quad.size.x * window.y / window.x) / tiles
	camera.fov = rad_to_deg(2.0 * atan(height * 0.5 / Settings.SCREEN_DISTANCE))


func _update_cursor(delta: float) -> void:
	idle += delta
	var hide := not panel.visible and not player.is_image() and not player.is_music_mode() and not player.paused and player.is_playing() and idle > CURSOR_IDLE_SECONDS
	var mode := Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
		toggle_fullscreen()
		return true
	return false


func handle_input(event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	if mouse == null:
		return false
	if mouse is InputEventMouseMotion:
		idle = 0.0
	if panel.is_open() or menu_pressed:
		return _menu_input(mouse)
	return _video_input(mouse)


func _menu_input(mouse: InputEventMouse) -> bool:
	var button := mouse as InputEventMouseButton
	var inside := menu_rect.get_rect().has_point(mouse.position)
	if button != null and button.pressed and not inside and not menu_pressed:
		if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			panel.close()
		return true
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		menu_pressed = button.pressed
	var rect := menu_rect.get_rect()
	var canvas := Vector2(ui_viewport.size_2d_override)
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = (mouse.position - rect.position) / rect.size * canvas
	forwarded.global_position = forwarded.position
	var motion := forwarded as InputEventMouseMotion
	if motion != null:
		motion.relative *= canvas / rect.size
	if PopupDismiss.outside_press(ui_viewport, forwarded):
		return true
	ui_viewport.push_input(forwarded, true)
	return true


func _video_input(mouse: InputEventMouse) -> bool:
	var button := mouse as InputEventMouseButton
	if button != null:
		_video_button(button)
		return true
	if seeking:
		_seek_at(mouse.position)
		return true
	var motion := mouse as InputEventMouseMotion
	if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		if motion.position.distance_to(press_position) > CLICK_SLOP:
			dragged = true
		if dragged and _is_flat() and (player.is_image() or Settings.flat_video_pan) and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var window := get_viewport().get_visible_rect().size
			Settings.pan_photo(Vector2(-motion.relative.x / maxf(window.x, 1.0), -motion.relative.y / maxf(window.y, 1.0)))
		elif dragged and not _is_flat():
			var speed := LOOK_SPEED / maxf(screen.displayed_zoom, 1.0)
			var previous := camera.global_basis.orthonormalized()
			camera.rotate_y(-motion.relative.x * speed)
			camera.rotate_object_local(Vector3.RIGHT, -motion.relative.y * speed)
			if main.resonance_field != null and main.resonance_field.active and not main.music_grab_moves_scene():
				main.resonance_field.rotate_scene(camera.global_basis.orthonormalized() * previous.inverse())
		return true
	_reveal_osd()
	_update_seek_preview(mouse.position)
	return true


func _video_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				if button.double_click:
					toggle_fullscreen()
					if click_toggled:
						main.toggle_pause()
					click_toggled = false
					skip_release = true
					return
				if _over_osd(button.position):
					seeking = _near_seek_bar(button.position)
					if seeking:
						last_seek_target = -1.0
						_seek_at(button.position)
					return
				press_position = button.position
				dragged = false
				video_pressed = true
				click_toggled = false
				return
			if seeking:
				_seek_at(button.position, true)
				seeking = false
				_update_seek_preview(button.position)
				return
			if video_pressed and not dragged and not skip_release:
				main.toggle_pause()
				click_toggled = true
			elif video_pressed and dragged and _is_flat() and (player.is_image() or Settings.flat_video_pan):
				Settings.commit_photo_pan()
			video_pressed = false
			skip_release = false
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				press_position = button.position
				dragged = false
				menu_click_pressed = true
				return
			if menu_click_pressed and not dragged:
				main.toggle_menu()
			menu_click_pressed = false
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not button.pressed:
				return
			var direction := 1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if button.ctrl_pressed and not _is_flat():
				Settings.apply("picture_zoom", Settings.picture_zoom * exp(direction * 0.08))
			else:
				main.step_volume(direction)


func _reveal_osd() -> void:
	if osd_cooldown > 0.0 or player.current_path.is_empty() or panel.visible or player.is_music_mode():
		return
	osd_cooldown = OSD_REFRESH_SECONDS
	if osd.visible and osd.target_opacity > 0.0:
		osd.show_status(osd.title_label.text, camera)
	else:
		main._show_status(player.current_path.get_file())


func _over_osd(position: Vector2) -> bool:
	return osd_rect.visible and osd.opacity >= 0.5 and osd_rect.get_rect().has_point(position)


func _osd_local(position: Vector2) -> Vector2:
	var rect := osd_rect.get_rect()
	return (position - rect.position) / rect.size * Vector2(osd.viewport.size_2d_override)


func _near_seek_bar(position: Vector2) -> bool:
	return player.playback != null and osd.progress.visible and _osd_local(position).y >= osd.progress.get_global_rect().position.y - SEEK_BAR_REACH


func _seek_at(position: Vector2, force := false) -> void:
	var bar: Rect2 = osd.progress.get_global_rect()
	var now := Time.get_ticks_msec() / 1000.0
	var target := clampf((_osd_local(position).x - bar.position.x) / bar.size.x, 0.0, 1.0) * player.get_stream_length()
	if (force or now - last_seek >= SEEK_INTERVAL_SECONDS) and not is_equal_approx(target, last_seek_target):
		last_seek = now
		last_seek_target = target
		player.seek_to(target)
	osd.show_status(osd.title_label.text, camera)
	_update_seek_preview(position)


func _update_seek_preview(position: Vector2) -> void:
	if not Settings.seek_previews or panel.visible or not _over_osd(position) or not _near_seek_bar(position):
		_hide_seek_preview()
		return
	previews.prepare(player)
	if previews.path != player.current_path or previews.path.is_empty():
		_hide_seek_preview()
		return
	var bar: Rect2 = osd.progress.get_global_rect()
	var fraction := clampf((_osd_local(position).x - bar.position.x) / maxf(bar.size.x, 1.0), 0.0, 1.0)
	preview_time = fraction * player.get_stream_length()
	var total := int(preview_time)
	preview_label.text = "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	_show_preview_frame()
	preview_panel.visible = true
	preview_panel.reset_size()
	_position_seek_preview()


func _show_preview_frame() -> void:
	var frame := previews.frame(preview_time, self)
	if frame != null:
		preview_image.texture = frame


func _position_seek_preview() -> void:
	var bar: Rect2 = osd.progress.get_global_rect()
	var canvas := Vector2(osd.viewport.size_2d_override)
	var x := osd_rect.position.x + (bar.position.x + bar.size.x * preview_time / maxf(player.get_stream_length(), 0.001)) / canvas.x * osd_rect.size.x
	var window_size := get_viewport().get_visible_rect().size
	preview_panel.position = Vector2(clampf(x - preview_panel.size.x * 0.5, 0.0, maxf(window_size.x - preview_panel.size.x, 0.0)), maxf(osd_rect.position.y - preview_panel.size.y - 8.0, 0.0))


func _hide_seek_preview() -> void:
	if preview_panel.visible:
		preview_panel.visible = false
		preview_image.texture = null
		previews.stop(self)
	preview_time = -1.0
