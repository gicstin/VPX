extends FloatPanel

const SeekPreviews := preload("res://scripts/seek_previews.gd")
const BAR_RECT := Rect2(48, 322, 1004, 30)
const HIT_RECT := Rect2(36, 300, 1028, 78)
const PREVIEW_WIDTH := 382.0
const SEEK_DWELL_MSEC := 120
const HOVER_EXIT_MSEC := 120
const PREVIEW_MOVE_PIXELS := 3.0
const PREVIEW_REQUEST_MSEC := 120
const CURSOR_DEADZONE_PIXELS := 1.5
const CURSOR_FOLLOW_RATE := 20.0
const PREVIEW_FADE_SECONDS := 0.14

var player: VPXPlayer
var previews: SeekPreviews
var progress: ProgressBar
var cursor: ColorRect
var current_label: Label
var hint_label: Label
var preview_panel: Panel
var preview_image: TextureRect
var preview_next_image: TextureRect
var preview_label: Label
var hover_time := -1.0
var hover_started := 0
var last_hover_hit := 0
var cursor_target_x := -1.0
var preview_request_x := -1.0
var preview_request_time := -1.0
var preview_requested_at := 0
var preview_fade := -1.0
var active := false
var progress_tick := 0.0


func _init() -> void:
	panel_size = Vector2(1.1, 0.42)
	distance = 1.3
	drop = 0.54
	tilt = -18.0


func _ready() -> void:
	super()
	previews.ready_for.connect(_on_preview_ready)
	previews.state_changed.connect(func() -> void:
		if active and hover_time >= 0.0:
			_show_preview_frame())
	Settings.changed.connect(_on_settings_changed)


func _build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(1100, 420)
	var card := Panel.new()
	card.position = Vector2(0, 262)
	card.size = Vector2(1100, 140)
	card.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 22, 0, 0))
	root.add_child(card)
	current_label = Label.new()
	current_label.position = Vector2(48, 277)
	current_label.size = Vector2(360, 32)
	current_label.add_theme_font_size_override("font_size", 23)
	root.add_child(current_label)
	hint_label = Label.new()
	hint_label.position = Vector2(420, 277)
	hint_label.size = Vector2(632, 32)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", VpxTheme.MUTED)
	hint_label.text = "Point at bar · release trigger to seek"
	root.add_child(hint_label)
	progress = ProgressBar.new()
	progress.position = BAR_RECT.position
	progress.size = BAR_RECT.size
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", VpxTheme.flat(VpxTheme.TRACK, 12, 0, 0))
	progress.add_theme_stylebox_override("fill", VpxTheme.accent_flat(12, 0, 0))
	root.add_child(progress)
	cursor = ColorRect.new()
	cursor.position = Vector2(BAR_RECT.position.x, BAR_RECT.position.y - 9)
	cursor.size = Vector2(5, BAR_RECT.size.y + 18)
	cursor.color = VpxTheme.ACCENT_HOVER
	cursor.visible = false
	root.add_child(cursor)
	preview_panel = Panel.new()
	preview_panel.size = Vector2(PREVIEW_WIDTH, 252)
	preview_panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 16, 0, 0))
	preview_panel.visible = false
	root.add_child(preview_panel)
	var image_back := ColorRect.new()
	image_back.position = Vector2(15, 15)
	image_back.size = Vector2(SeekPreviews.FRAME_SIZE)
	image_back.color = VpxTheme.RAISED
	preview_panel.add_child(image_back)
	preview_image = TextureRect.new()
	preview_image.position = image_back.position
	preview_image.size = image_back.size
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_panel.add_child(preview_image)
	preview_next_image = TextureRect.new()
	preview_next_image.position = image_back.position
	preview_next_image.size = image_back.size
	preview_next_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_next_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_next_image.visible = false
	preview_panel.add_child(preview_next_image)
	preview_label = Label.new()
	preview_label.position = Vector2(15, 219)
	preview_label.size = Vector2(352, 25)
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 22)
	preview_panel.add_child(preview_label)
	return root


func show_bar(camera: Camera3D) -> void:
	if active:
		return
	active = true
	previews.prepare(player)
	place(camera)
	present(camera)
	_refresh_progress()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func close_bar() -> void:
	if not active:
		return
	active = false
	clear_hover()
	previews.stop(self)
	dismiss()


func _process(delta: float) -> void:
	super(delta)
	if active:
		_update_cursor(delta)
		_update_preview_fade(delta)
		progress_tick += delta
		if progress_tick >= 0.1:
			progress_tick = 0.0
			_refresh_progress()


func _refresh_progress() -> void:
	previews.prepare(player)
	if hover_time >= 0.0:
		_show_preview_frame()
	var length := player.get_stream_length()
	progress.max_value = maxf(length, 1.0)
	progress.value = player.stream_position
	current_label.text = "%s / %s" % [format_time(player.stream_position), format_time(length)]
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func hit_from_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	if not active or opacity < 0.2:
		return {"ok": false}
	var local_origin := quad.to_local(origin)
	if local_origin.z <= 0.0:
		return {"ok": false}
	var local_direction := quad.global_basis.inverse() * direction
	if absf(local_direction.z) < 0.0001:
		return {"ok": false}
	var distance_to_plane := -local_origin.z / local_direction.z
	if distance_to_plane <= 0.0 or distance_to_plane > 10.0:
		return {"ok": false}
	var local := local_origin + local_direction * distance_to_plane
	var pixels := Vector2((local.x / panel_size.x + 0.5) * 1100.0, (0.5 - local.y / panel_size.y) * 420.0)
	if not HIT_RECT.has_point(pixels):
		return {"ok": false}
	return {"ok": true, "point": quad.to_global(local), "fraction": clampf((pixels.x - BAR_RECT.position.x) / BAR_RECT.size.x, 0.0, 1.0)}


func update_hover(origin: Vector3, direction: Vector3) -> void:
	var hit := hit_from_ray(origin, direction)
	if not hit.get("ok", false):
		if hover_time >= 0.0 and Time.get_ticks_msec() - last_hover_hit >= HOVER_EXIT_MSEC:
			clear_hover()
		return
	var now := Time.get_ticks_msec()
	last_hover_hit = now
	var fraction: float = hit.fraction
	var raw_x := BAR_RECT.position.x + fraction * BAR_RECT.size.x - cursor.size.x * 0.5
	if hover_time < 0.0:
		hover_started = now
		cursor.position.x = raw_x
		cursor_target_x = raw_x
		cursor.visible = true
		preview_panel.position = Vector2(clampf(raw_x - PREVIEW_WIDTH * 0.5, 0.0, 1100.0 - PREVIEW_WIDTH), 0.0)
		preview_panel.visible = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	hover_time = fraction * player.get_stream_length()
	if absf(raw_x - cursor_target_x) >= CURSOR_DEADZONE_PIXELS:
		cursor_target_x = raw_x
		var shown_fraction := clampf((raw_x + cursor.size.x * 0.5 - BAR_RECT.position.x) / BAR_RECT.size.x, 0.0, 1.0)
		preview_label.text = format_time(shown_fraction * player.get_stream_length())
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif preview_label.text.is_empty():
		preview_label.text = format_time(hover_time)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if preview_request_x < 0.0 or (absf(raw_x - preview_request_x) >= PREVIEW_MOVE_PIXELS and now - preview_requested_at >= PREVIEW_REQUEST_MSEC):
		preview_request_x = raw_x
		preview_request_time = hover_time
		preview_requested_at = now
		_show_preview_frame()


func _update_cursor(delta: float) -> void:
	if hover_time < 0.0 or cursor_target_x < 0.0:
		return
	var x := lerpf(cursor.position.x, cursor_target_x, 1.0 - exp(-delta * CURSOR_FOLLOW_RATE))
	if absf(x - cursor_target_x) < 0.2:
		x = cursor_target_x
	if is_equal_approx(x, cursor.position.x):
		return
	cursor.position.x = x
	preview_panel.position.x = clampf(x - PREVIEW_WIDTH * 0.5, 0.0, 1100.0 - PREVIEW_WIDTH)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_preview_fade(delta: float) -> void:
	if preview_fade < 0.0:
		return
	preview_fade = minf(preview_fade + delta / PREVIEW_FADE_SECONDS, 1.0)
	preview_next_image.modulate = Color(1.0, 1.0, 1.0, preview_fade)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if preview_fade >= 1.0:
		preview_image.texture = preview_next_image.texture
		preview_next_image.texture = null
		preview_next_image.visible = false
		preview_fade = -1.0


func clear_hover() -> void:
	if hover_time < 0.0:
		return
	hover_time = -1.0
	hover_started = 0
	last_hover_hit = 0
	cursor_target_x = -1.0
	preview_request_x = -1.0
	preview_request_time = -1.0
	preview_requested_at = 0
	cursor.visible = false
	preview_panel.visible = false
	_clear_preview_image()
	preview_label.text = ""
	previews.stop(self)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func ready_to_seek() -> bool:
	return hover_time >= 0.0 and Time.get_ticks_msec() - hover_started >= SEEK_DWELL_MSEC


func _show_preview_frame() -> void:
	if preview_request_time < 0.0:
		return
	if not Settings.seek_previews or previews.path != player.current_path:
		preview_label.text = "%s · %s" % [format_time(preview_request_time), previews.status(preview_request_time)]
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	var frame: Texture2D = previews.frame(preview_request_time, self)
	if frame == null:
		preview_label.text = "%s · %s" % [format_time(preview_request_time), previews.status(preview_request_time)]
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	preview_label.text = format_time(preview_request_time)
	if frame == preview_next_image.texture:
		return
	if frame == preview_image.texture:
		preview_next_image.texture = null
		preview_next_image.visible = false
		preview_fade = -1.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if preview_image.texture == null:
		preview_image.texture = frame
	else:
		preview_next_image.texture = frame
		preview_next_image.modulate = Color(1.0, 1.0, 1.0, 0.0)
		preview_next_image.visible = true
		preview_fade = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _clear_preview_image() -> void:
	preview_image.texture = null
	preview_next_image.texture = null
	preview_next_image.visible = false
	preview_fade = -1.0


func _on_preview_ready(path: String) -> void:
	if active and previews.request_owner == self and hover_time >= 0.0 and path == player.current_path:
		_show_preview_frame()


func _on_settings_changed() -> void:
	cursor.color = VpxTheme.ACCENT_HOVER
	if not active:
		return
	var previous_path := previews.path
	var previous_format := previews.format_id
	previews.prepare(player)
	if not Settings.seek_previews or previous_path != previews.path or previous_format != previews.format_id:
		_clear_preview_image()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_show_preview_frame()


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
