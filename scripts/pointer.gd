extends XRController3D

const VRSeekBar := preload("res://scripts/vr_seek_bar.gd")

signal menu_toggled
signal play_pause
signal seek(seconds: float)
signal file_step(direction: int)
signal volume_step(direction: int)
signal grip_adjust(direction: int)
signal trigger_adjust(direction: int)
signal chord_adjust(direction: int)
signal trigger_held_changed(held: bool)
signal stick_tapped
signal recenter_requested
signal recenter_progress(fraction: float)
signal pick_triggered
signal pick_cancelled
signal grab_started
signal grab_ended
signal activated
signal level_requested
signal favorite_requested

const SEEK_STEP := 10.0
const TRIGGER_SEEK_SCALE := 6.0
const GRIP_SEEK_SCALE := 30.0
const HOLD_STAGES := [[0.0, 1.0], [1.5, 3.0], [4.0, 6.0]]
const REPEAT_DELAY := 0.45
const REPEAT_INTERVAL := 0.35
const STICK_THRESHOLD := 0.7
const SCROLL_DEADZONE := 0.15
const SCROLL_RATE := 16.0
const SCROLL_CURVE := 1.6
const PULSE_LIGHT := 0.25
const STICK_TAP_MAX := 0.35
const RECENTER_HOLD := 1.0
const RECENTER_SHOW_AFTER := 0.2
const PULSE_STRONG := 0.6
const PULSE_HOVER := 0.08
const AIM_MIN_CUTOFF := 0.5
const AIM_SPEED_GAIN := 0.2
const AIM_SPEED_CUTOFF := 3.0
const CLICK_UNLOCK_DEGREES := 2.5
const LASER_FREE_LENGTH := 3.0

@export var panel: Node3D
@export var viewport: SubViewport
@export var screen: MeshInstance3D

@onready var ray: RayCast3D = $Ray
@onready var laser: MeshInstance3D = $Laser

var zooming := false
var visualizer_zooming := false
var visualizer: ResonanceField
var sizing := false
var stick_armed := true
var stick_axis := Vector2.ZERO
var hold_time := 0.0
var repeat_time := 0.0
var last_uv := Vector2(-1, -1)
var trigger_held := false
var grip_held := false
var picking := false
var ax_clicking := false
var stick_clicked := false
var stick_click_time := 0.0
var stick_tap_allowed := false
var active := true:
	set(value):
		if active and not value:
			_cancel_click()
		active = value
var hovered: Control
var aim := Quaternion.IDENTITY
var aim_raw := Quaternion.IDENTITY
var aim_velocity := Vector3.ZERO
var aim_primed := false
var aim_frame := -1
var click_lock := Quaternion.IDENTITY
var click_locked := false
var laser_rest := Quaternion.IDENTITY
var seek_bar: VRSeekBar
var extra_panels: Array[FloatPanel] = []
var hit_panel: Node3D
var target_viewport: SubViewport
var pressed_viewport: SubViewport
var pressed_panel: Node3D


func _ready() -> void:
	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)
	laser_rest = laser.quaternion
	target_viewport = viewport
	_apply_laser_color()
	Settings.changed.connect(_apply_laser_color)


func _apply_laser_color() -> void:
	var laser_material := laser.get_active_material(0) as StandardMaterial3D
	laser_material.albedo_color = Color(VpxTheme.ACCENT, 0.85)


func aim_basis() -> Basis:
	_update_aim()
	return Basis(click_lock if click_locked else aim)


func aim_direction() -> Vector3:
	return -aim_basis().z


func aim_transform() -> Transform3D:
	return Transform3D(aim_basis(), global_position)


func _update_aim() -> void:
	var frame := Engine.get_process_frames()
	if frame == aim_frame:
		return
	var delta := get_process_delta_time()
	aim_frame = frame
	var raw := Quaternion(global_basis.orthonormalized())
	if not aim_primed or delta <= 0.0:
		aim = raw
		aim_raw = raw
		aim_velocity = Vector3.ZERO
		aim_primed = true
	else:
		var step := aim_raw.inverse() * raw
		var velocity := Vector3.ZERO
		if step.get_angle() > 0.0:
			velocity = aim_raw * step.get_axis() * rad_to_deg(wrapf(step.get_angle(), -PI, PI)) / delta
		aim_velocity = aim_velocity.lerp(velocity, _smoothing(AIM_SPEED_CUTOFF, delta))
		aim_raw = raw
		var cutoff := AIM_MIN_CUTOFF + AIM_SPEED_GAIN * aim_velocity.length()
		aim = aim.slerp(raw, _smoothing(cutoff, delta)).normalized()
	if click_locked and rad_to_deg(click_lock.angle_to(raw)) > CLICK_UNLOCK_DEGREES:
		click_locked = false
		aim = click_lock
	var local := Quaternion(global_basis.orthonormalized().inverse() * aim_basis())
	ray.quaternion = local
	laser.quaternion = local * laser_rest


static func _smoothing(cutoff: float, delta: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / delta)


func _lock_click() -> void:
	_update_aim()
	click_lock = aim
	click_locked = true


func _process(delta: float) -> void:
	if is_instance_valid(pressed_viewport) and (not active or not get_is_active() or (is_instance_valid(pressed_panel) and not pressed_panel.visible)):
		_cancel_click()
	if not get_is_active():
		if last_uv != Vector2(-1, -1) and active:
			_push_motion(Vector2(-1, -1))
		last_uv = Vector2(-1, -1)
		hit_panel = null
		hovered = null
		laser.visible = false
		return
	_update_aim()
	_update_stick(delta)
	_update_recenter_hold(delta)
	var hit := _panel_hit()
	_retarget(hit)
	if picking or grip_held:
		laser.visible = get_is_active() and _laser_allowed()
		if screen and get_is_active():
			var screen_hit: Dictionary = screen.hit_from_ray(global_position, aim_direction())
			if screen_hit.get("ok", false):
				_scale_laser(global_position.distance_to(screen_hit.point))
				return
		_scale_laser(LASER_FREE_LENGTH)
		return
	if trigger_held and seek_bar != null and seek_bar.active and get_is_active():
		var seek_hit: Dictionary = seek_bar.hit_from_ray(global_position, aim_direction())
		laser.visible = _laser_allowed()
		_scale_laser(global_position.distance_to(seek_hit.point) if seek_hit.get("ok", false) else LASER_FREE_LENGTH)
		return
	laser.visible = (panel.visible or hit_panel != null) and get_is_active() and active
	if hit.uv == Vector2(-1, -1):
		if last_uv != hit.uv and active:
			_push_motion(hit.uv)
		last_uv = hit.uv
		_scale_laser(LASER_FREE_LENGTH)
		return
	_scale_laser(global_position.distance_to(hit.point))
	last_uv = hit.uv
	if active:
		_push_motion(last_uv)
		_hover_feedback()


func _laser_allowed() -> bool:
	return not Settings.laser_menu_only or panel.visible or hit_panel != null


func _hover_feedback() -> void:
	var control := target_viewport.gui_get_hovered_control()
	if control == hovered:
		return
	hovered = control
	if Settings.hover_haptics and control is BaseButton and not (control as BaseButton).disabled:
		pulse(PULSE_HOVER)


func haptics_available() -> bool:
	var source := XRServer.get_tracker(tracker) as XRPositionalTracker
	return source != null


func pointing_at_panel() -> bool:
	return last_uv != Vector2(-1, -1)


func _panel_hit() -> Dictionary:
	if is_instance_valid(pressed_viewport) and is_instance_valid(pressed_panel):
		return _surface_hit(pressed_panel, pressed_viewport, true)
	var best := _surface_hit(panel, viewport) if panel.visible and ray.is_colliding() else _miss()
	for extra in extra_panels:
		if not extra.interactive():
			continue
		var hit := _surface_hit(extra, extra.viewport)
		if hit.uv != Vector2(-1, -1) and (best.uv == Vector2(-1, -1) or hit.distance < best.distance):
			best = hit
	return best


func _surface_hit(surface: Node3D, surface_viewport: SubViewport, captured := false) -> Dictionary:
	var origin := surface.to_local(ray.global_transform.origin)
	var tip := surface.to_local(ray.to_global(ray.target_position))
	var direction := tip - origin
	if absf(direction.z) < 0.0001:
		return _miss()
	var t := -origin.z / direction.z
	if t < 0.0 or t > 1.0:
		return _miss()
	var local := origin + direction * t
	var size: Vector2 = surface.panel_size
	var uv := Vector2((local.x + size.x * 0.5) / size.x, (size.y * 0.5 - local.y) / size.y)
	if not captured and (uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0):
		return _miss()
	var point := surface.to_global(local)
	return {"uv": uv, "point": point, "panel": surface, "viewport": surface_viewport, "distance": global_position.distance_to(point)}


func _miss() -> Dictionary:
	return {"uv": Vector2(-1, -1), "point": Vector3.ZERO, "panel": null, "viewport": null, "distance": INF}


func _retarget(hit: Dictionary) -> void:
	var next: SubViewport = pressed_viewport if is_instance_valid(pressed_viewport) else (hit.viewport if hit.viewport != null else viewport)
	hit_panel = hit.panel
	if next == target_viewport:
		return
	if last_uv != Vector2(-1, -1) and active:
		_push_motion(Vector2(-1, -1))
	target_viewport = next
	last_uv = Vector2(-1, -1)
	hovered = null


func _scale_laser(length: float) -> void:
	laser.scale.z = length
	laser.position = laser.quaternion * laser_rest.inverse() * Vector3(0, 0, -length * 0.5)


func _mouse_pos(uv: Vector2) -> Vector2:
	var canvas := target_viewport.size_2d_override if target_viewport.size_2d_override != Vector2i.ZERO else target_viewport.size
	return uv * Vector2(canvas)


func _push_motion(uv: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(-1, -1) if uv == Vector2(-1, -1) else _mouse_pos(uv)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if trigger_held or ax_clicking else 0
	target_viewport.push_input(event, true)


func _push_button(uv: Vector2, is_pressed: bool) -> void:
	if is_pressed and (uv == Vector2(-1, -1) or is_instance_valid(pressed_viewport)):
		return
	if not is_pressed and not is_instance_valid(pressed_viewport):
		return
	if not is_pressed and (trigger_held or ax_clicking):
		return
	var destination := target_viewport if is_pressed else pressed_viewport
	var event := InputEventMouseButton.new()
	var canvas := destination.size_2d_override if destination.size_2d_override != Vector2i.ZERO else destination.size
	event.position = Vector2(-1, -1) if uv == Vector2(-1, -1) else uv * Vector2(canvas)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = is_pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
	if PopupDismiss.outside_press(destination, event):
		return
	if is_pressed:
		pressed_viewport = destination
		pressed_panel = hit_panel
	else:
		pressed_viewport = null
		pressed_panel = null
	destination.push_input(event, true)


func _cancel_click() -> void:
	var was_trigger_held := trigger_held
	trigger_held = false
	ax_clicking = false
	_push_button(Vector2(-1, -1), false)
	_release_click()
	if was_trigger_held:
		trigger_held_changed.emit(false)


func _exit_tree() -> void:
	_cancel_click()


func _push_scroll(up: bool, factor: float = 3.0) -> void:
	if last_uv == Vector2(-1, -1):
		return
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = _mouse_pos(last_uv)
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = is_pressed
		event.factor = factor
		target_viewport.push_input(event, true)


func _ui() -> Control:
	return viewport.get_node_or_null("UI") as Control


func _volume_control() -> Control:
	if not pointing_at_panel() or target_viewport == null:
		return null
	var control := target_viewport.gui_get_hovered_control()
	var node: Node = control
	while node != null:
		if node is Control and node.has_method("volume_hovering") and node.volume_hovering(control):
			return node as Control
		node = node.get_parent()
	return null


func _hovering_volume() -> bool:
	return _volume_control() != null


func _stick_scrolls(stick: Vector2) -> bool:
	return not grip_held and not trigger_held and absf(stick.y) > SCROLL_DEADZONE and absf(stick.y) >= absf(stick.x) \
		and pointing_at_panel() and not _hovering_volume()


func _scroll_continuous(stick_y: float, delta: float) -> void:
	var amount := (absf(stick_y) - SCROLL_DEADZONE) / (1.0 - SCROLL_DEADZONE)
	_push_scroll(stick_y > 0.0, SCROLL_RATE * pow(amount, SCROLL_CURVE) * delta)


func _update_recenter_hold(delta: float) -> void:
	if not stick_clicked:
		return
	stick_click_time += delta
	if stick_click_time < RECENTER_SHOW_AFTER:
		return
	if stick_click_time >= RECENTER_HOLD:
		stick_clicked = false
		recenter_requested.emit()
		pulse(PULSE_STRONG)
		return
	recenter_progress.emit((stick_click_time - RECENTER_SHOW_AFTER) / (RECENTER_HOLD - RECENTER_SHOW_AFTER))


func pulse(strength: float) -> void:
	trigger_haptic_pulse("haptic", 0.0, strength, 0.04, 0.0)


func _on_button_pressed(name: String) -> void:
	match name:
		"trigger_click":
			trigger_held = true
			_claim()
			if picking or pointing_at_panel():
				_lock_click()
			if picking:
				pick_triggered.emit()
				return
			_push_button(last_uv, true)
			trigger_held_changed.emit(true)
		"grip_click":
			grip_held = true
			grab_started.emit()
		"by_button", "menu_button":
			if picking:
				pick_cancelled.emit()
				return
			menu_toggled.emit()
		"primary_click":
			stick_clicked = true
			stick_click_time = 0.0
			stick_tap_allowed = not grip_held and not trigger_held and not picking
		"ax_button":
			if grip_held and trigger_held and not picking:
				level_requested.emit()
				return
			if pointing_at_panel() and not picking:
				_claim()
				_lock_click()
				ax_clicking = true
				_push_button(last_uv, true)
				return
			if grip_held and not picking:
				favorite_requested.emit()
				pulse(PULSE_STRONG)
				return
			play_pause.emit()
			pulse(PULSE_LIGHT)


func _release_click() -> void:
	if click_locked and not trigger_held and not ax_clicking:
		click_locked = false
		aim = click_lock


func _claim() -> void:
	if active:
		return
	activated.emit()
	_push_motion(last_uv)


func _on_button_released(name: String) -> void:
	match name:
		"trigger_click":
			trigger_held = false
			_push_button(last_uv, false)
			_release_click()
			trigger_held_changed.emit(false)
		"grip_click":
			grip_held = false
			grab_ended.emit()
		"ax_button":
			if ax_clicking:
				ax_clicking = false
				_push_button(last_uv, false)
				_release_click()
		"primary_click":
			if stick_clicked and stick_click_time >= RECENTER_SHOW_AFTER:
				recenter_progress.emit(-1.0)
			if stick_clicked and stick_click_time <= STICK_TAP_MAX and stick_tap_allowed and not grip_held and not trigger_held and not picking:
				stick_tapped.emit()
			stick_clicked = false
			stick_tap_allowed = false


func _update_stick(delta: float) -> void:
	_handle_stick(get_vector2("primary"), delta)


func _handle_stick(stick: Vector2, delta: float) -> void:
	var action := _continuous_stick_action()
	var visualizing := visualizer != null and visualizer.active
	if zooming and (action != Settings.StickAction.PICTURE_ZOOM or visualizing != visualizer_zooming):
		_commit_stick_zoom()
	if sizing and action != Settings.StickAction.SCREEN_SIZE:
		sizing = false
		Settings.commit()
	if absf(stick.y) > SCROLL_DEADZONE and absf(stick.y) >= absf(stick.x) and action >= 0:
		var amount := signf(stick.y) * (absf(stick.y) - SCROLL_DEADZONE) / (1.0 - SCROLL_DEADZONE)
		if action == Settings.StickAction.PICTURE_ZOOM:
			zooming = true
			visualizer_zooming = visualizing
			if visualizing:
				Settings.preview_visualizer_zoom(Settings.visualizer_zoom * exp(amount * Settings.ZOOM_RATE * delta))
			else:
				Settings.preview_zoom(Settings.picture_zoom * exp(amount * Settings.ZOOM_RATE * delta))
		else:
			sizing = true
			Settings.preview_screen_size(Settings.screen_size + amount * Settings.SCREEN_SIZE_RATE * delta)
		return
	if zooming:
		_commit_stick_zoom()
	if sizing:
		sizing = false
		Settings.commit()
	if _stick_scrolls(stick):
		_scroll_continuous(stick.y, delta)
		stick_armed = true
		return
	if stick.length() < STICK_THRESHOLD:
		stick_armed = true
		hold_time = 0.0
		return
	var axis := Vector2(signf(stick.x), 0.0) if absf(stick.x) > absf(stick.y) else Vector2(0.0, signf(stick.y))
	if stick_armed or axis != stick_axis:
		stick_armed = false
		stick_axis = axis
		hold_time = 0.0
		repeat_time = 0.0
		_flick(axis, 1.0, false)
		return
	hold_time += delta
	if hold_time < REPEAT_DELAY:
		return
	repeat_time += delta
	if repeat_time < REPEAT_INTERVAL:
		return
	repeat_time = 0.0
	_flick(axis, _hold_scale(), true)


func _commit_stick_zoom() -> void:
	zooming = false
	if visualizer_zooming:
		Settings.commit()
	else:
		Settings.commit_zoom()
	visualizer_zooming = false


func _zoom_stick_active() -> bool:
	return _continuous_stick_action() == Settings.StickAction.PICTURE_ZOOM


func _library_shortcut_active() -> bool:
	var ui := _ui()
	return panel.visible and ui != null and ui.library_navigation_active()


func _continuous_stick_action() -> int:
	var ui := _ui()
	if ui == null or picking or (not grip_held and not trigger_held and pointing_at_panel()) or (grip_held and not trigger_held and _library_shortcut_active()):
		return -1
	var action := Settings.chord_action if grip_held and trigger_held else (Settings.grip_action if grip_held else Settings.trigger_action)
	if not grip_held and not trigger_held:
		return Settings.StickAction.PICTURE_ZOOM if ui.player.is_image() else -1
	if action == Settings.StickAction.SCREEN_SIZE and ((visualizer != null and visualizer.active) or Settings.projection != Settings.ProjectionMode.FLAT):
		return Settings.StickAction.PICTURE_ZOOM
	return action if action in [Settings.StickAction.PICTURE_ZOOM, Settings.StickAction.SCREEN_SIZE] else -1


func _hold_scale() -> float:
	var scale := 1.0
	for stage in HOLD_STAGES:
		if hold_time >= stage[0]:
			scale = stage[1]
	return scale


func _flick(axis: Vector2, hold_scale: float, repeated: bool) -> void:
	if axis.x != 0.0:
		_flick_horizontal(int(axis.x), hold_scale, repeated)
	else:
		_flick_vertical(int(axis.y), repeated)


func _flick_horizontal(direction: int, hold_scale: float, repeated: bool) -> void:
	if grip_held and trigger_held:
		if not repeated:
			file_step.emit(direction)
			pulse(PULSE_STRONG)
		return
	var scale := 1.0
	if grip_held:
		scale = GRIP_SEEK_SCALE
	elif trigger_held:
		scale = TRIGGER_SEEK_SCALE
	seek.emit(SEEK_STEP * scale * hold_scale * direction)
	pulse(PULSE_LIGHT)


func _flick_vertical(direction: int, repeated: bool) -> void:
	if grip_held and not trigger_held and _library_shortcut_active():
		if direction > 0 and not repeated and _ui().navigate_library_up():
			pulse(PULSE_LIGHT)
		return
	if grip_held and trigger_held:
		chord_adjust.emit(direction)
	elif grip_held:
		grip_adjust.emit(direction)
	elif _hovering_volume():
		_volume_control().nudge_volume(direction)
	elif pointing_at_panel():
		return
	elif trigger_held:
		trigger_adjust.emit(direction)
	else:
		volume_step.emit(direction)
	if not repeated:
		pulse(PULSE_LIGHT)
