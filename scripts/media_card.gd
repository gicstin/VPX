extends Button

signal activated(path: String, is_dir: bool)

enum Layout { CARD, ROW, CHIP }

const CARD_WIDTH := 226.0
const CHIP_HEIGHT := 60
const ROW_HEIGHT := 78
const ROW_THUMB := Vector2(112, 63)
const THUMB_ASPECT := 16.0 / 9.0
const INSET := 3
const INFO_HEIGHT := 100
const THUMB_RADIUS := 12.0
const STAR_SIZE := 44
const PLACEHOLDER_SIZE := 30
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const RoundedShader := preload("res://shaders/rounded.gdshader")

var path := ""
var is_dir := false
var layout := Layout.CARD
var title := ""
var context := ""
var icon_name := "folder"
var cover := ""
var cover_count := 0
var single := false
var guard := Callable()
var plain := false
var frame: Control
var thumb: TextureRect
var placeholder: TextureRect
var format_badge: PanelContainer
var format_label: Label
var res_badge: PanelContainer
var res_label: Label
var duration_badge: PanelContainer
var duration_label: Label
var progress: ProgressBar
var title_label: Label
var meta_label: Label
var side_label: Label
var star: Button


func setup(p_path: String, p_is_dir: bool, p_layout: Layout, p_guard: Callable, p_title := "", p_context := "", p_icon := "", p_cover := {}) -> void:
	path = p_path
	is_dir = p_is_dir
	cover = p_cover.get("cover", "")
	cover_count = p_cover.get("count", 0)
	single = p_cover.get("single", false)
	layout = p_layout
	guard = p_guard
	title = p_title if not p_title.is_empty() else (path.get_file() if is_dir else pretty_name(path))
	if title.is_empty():
		title = path
	context = p_context
	if not p_icon.is_empty():
		icon_name = p_icon
	focus_mode = FOCUS_NONE
	toggle_mode = not is_dir or single
	_build()
	pressed.connect(_on_pressed)
	refresh()


func set_cover(p_cover: Dictionary) -> void:
	cover = p_cover.get("cover", "")
	cover_count = p_cover.get("count", 0)
	single = p_cover.get("single", false)
	toggle_mode = not is_dir or single
	for child in get_children():
		remove_child(child)
		child.queue_free()
	frame = null
	thumb = null
	placeholder = null
	progress = null
	meta_label = null
	side_label = null
	_build()
	refresh()
	if layout == Layout.CARD:
		_fit_thumb()


func _build() -> void:
	match layout:
		Layout.CARD:
			_build_card()
		Layout.ROW:
			_build_row()
		Layout.CHIP:
			_build_chip()


static func pretty_name(file_path: String) -> String:
	var saved: Variant = Library.get_pref(file_path, "title")
	if saved is String and not saved.is_empty():
		return saved
	var name := file_path.get_slice("?", 0).get_file().get_basename().uri_decode()
	for separator in ["_", "."]:
		name = name.replace(separator, " ")
	while name.contains("  "):
		name = name.replace("  ", " ")
	return name.strip_edges()


func media_path() -> String:
	return cover if is_dir else path


func _on_pressed() -> void:
	if guard.is_valid() and not guard.call():
		return
	if single:
		activated.emit(cover, false)
	else:
		activated.emit(path, is_dir)


func _build_card() -> void:
	theme_type_variation = &"Card"
	custom_minimum_size = Vector2(CARD_WIDTH, _card_height(CARD_WIDTH))
	size_flags_horizontal = SIZE_EXPAND_FILL
	var inset := _margin(INSET, INSET, INSET, INSET)
	add_child(inset)
	var column := _vbox(0)
	inset.add_child(column)
	frame = _thumb_frame(Vector2(CARD_WIDTH - INSET * 2, (CARD_WIDTH - INSET * 2) / THUMB_ASPECT), 56)
	column.add_child(frame)
	format_badge = _badge(&"AccentBadge")
	format_label = format_badge.get_child(0)
	_pin(format_badge, Vector2(10, 10), false, false)
	res_badge = _badge(&"Badge")
	res_label = res_badge.get_child(0)
	_pin(res_badge, Vector2(-10, 10), true, false)
	duration_badge = _badge(&"Badge")
	duration_label = duration_badge.get_child(0)
	_pin(duration_badge, Vector2(-10, -14), true, true)
	var info := _margin(12, 8, 6, 10)
	column.add_child(info)
	var rows := _vbox(2)
	info.add_child(rows)
	var top := HBoxContainer.new()
	top.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	rows.add_child(top)
	title_label = _label(&"CardTitle")
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	title_label.custom_minimum_size.y = 54 * VpxTheme.text_size
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	top.add_child(title_label)
	star = _star()
	top.add_child(star)
	meta_label = _label(&"CardMeta")
	meta_label.clip_text = true
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(meta_label)
	if not resized.is_connected(_fit_thumb):
		resized.connect(_fit_thumb)


func _build_row() -> void:
	theme_type_variation = &"ListItem"
	custom_minimum_size = Vector2(0, height_for(0, Layout.ROW))
	size_flags_horizontal = SIZE_EXPAND_FILL
	var inset := _margin(10, 6, 8, 6)
	add_child(inset)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	inset.add_child(row)
	if is_dir and cover.is_empty():
		var holder := CenterContainer.new()
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.custom_minimum_size = Vector2(ROW_THUMB.x, 0)
		var folder := _icon_rect(icon_name, 36, VpxTheme.ACCENT_HOVER)
		holder.add_child(folder)
		row.add_child(holder)
	else:
		frame = _thumb_frame(ROW_THUMB, 30)
		frame.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(frame)
	var text := _vbox(2)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text)
	title_label = _label(&"Label")
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title_label)
	meta_label = _label(&"CardMeta")
	meta_label.clip_text = true
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(meta_label)
	side_label = _label(&"Caption")
	side_label.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(side_label)
	star = _star()
	star.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(star)


func _build_chip() -> void:
	theme_type_variation = &"ListItem"
	custom_minimum_size = Vector2(CARD_WIDTH, height_for(CARD_WIDTH, Layout.CHIP))
	size_flags_horizontal = SIZE_EXPAND_FILL
	var inset := _margin(14, 4, 4, 4)
	add_child(inset)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	inset.add_child(row)
	var folder := _icon_rect(icon_name, 26, VpxTheme.ACCENT_HOVER)
	folder.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(folder)
	var text := _vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text)
	title_label = _label(&"Label")
	title_label.add_theme_font_size_override("font_size", 21)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title_label)
	if not context.is_empty():
		meta_label = _label(&"CardMeta")
		meta_label.add_theme_font_size_override("font_size", 16)
		meta_label.clip_text = true
		meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(meta_label)
	star = _star()
	star.custom_minimum_size = Vector2(40, 40)
	star.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(star)


func refresh() -> void:
	title_label.text = title
	star.set_pressed_no_signal(Library.is_favorite(path))
	star.visible = not plain
	_show_star()
	if is_dir and cover.is_empty():
		if meta_label != null:
			meta_label.text = context
		return
	var media := media_path()
	var info: Dictionary = MediaInfo.info(media)
	var texture: Texture2D = MediaInfo.thumbnail(media)
	if thumb != null:
		thumb.texture = texture
		thumb.visible = texture != null
		placeholder.visible = texture == null
	var image := PanoramaFiles.is_image(media)
	var width := int(info.get("width", 0))
	var height := int(info.get("height", 0))
	var duration := float(info.get("duration", 0.0))
	var resume_at := float(Library.get_pref(media, "position", 0.0))
	var format := _format_text(media, info, image)
	var resolution := VPXPlayer.resolution_label(width, height) if width > 0 else ""
	var length := MediaInfo.duration_text(duration) if duration > 0.0 else ""
	var status := _status_text(media, duration, resume_at)
	if is_dir and not single:
		format = "%d items" % cover_count
		resolution = ""
		length = ""
		status = ""
	if layout == Layout.CARD:
		_set_badge(format_badge, format_label, format)
		_set_badge(res_badge, res_label, resolution)
		_set_badge(duration_badge, duration_label, length)
		var parts := PackedStringArray()
		if not context.is_empty():
			parts.append(context)
		if not status.is_empty():
			parts.append(status)
		elif context.is_empty():
			parts.append("Folder" if is_dir and not single else _size_text(media))
		meta_label.text = "  ·  ".join(parts)
	else:
		var parts := PackedStringArray()
		for part in [context, format, resolution, status if not status.is_empty() else ("" if is_dir and not single else _size_text(media))]:
			if not part.is_empty():
				parts.append(part)
		meta_label.text = "  ·  ".join(parts)
		side_label.text = length
	if progress != null:
		progress.visible = resume_at > 0.0 and duration > 0.0
		progress.value = clampf(resume_at / maxf(duration, 1.0), 0.0, 1.0)
	if info.has("failed") and thumb != null:
		placeholder.modulate = Color(VpxTheme.FAINT, 0.6)


func _format_text(media: String, info: Dictionary, image: bool) -> String:
	if image and info.get("cube", false):
		return "360°"
	var saved: Variant = Library.get_pref(media, "format")
	var label := ""
	if saved is Dictionary:
		label = VPXPlayer.format_label(int(saved.get("projection", 0)), int(saved.get("stereo", 0)))
	else:
		var height := float(info.get("height", 0))
		var aspect := float(info.get("width", 0)) / height if height > 0.0 else 0.0
		var guess := VPXPlayer.guess_format(media, aspect, info.get("meta", {}))
		if guess["tagged"] or (image and guess["projection"] != Settings.ProjectionMode.FLAT):
			label = VPXPlayer.format_label(guess["projection"], guess["stereo"])
	var alpha: bool = VPXPlayer.tags_from_name(media)["alpha"] or int(Library.get_pref(media, VPXPlayer.ALPHA_PROBE_KEY, 0)) != 0
	if saved is Dictionary and int(saved.get("alpha_mask", 0)) != 0:
		alpha = true
	if alpha:
		label = "Passthrough" if label.is_empty() else label + "  α"
	return label


func _status_text(media: String, duration: float, resume_at: float) -> String:
	if resume_at > 0.0 and duration > 0.0:
		return "%s left" % MediaInfo.duration_text(maxf(duration - resume_at, 0.0))
	if Library.get_pref(media, "finished", false):
		return "Watched"
	return ""


func _size_text(media: String) -> String:
	var bytes := MediaInfo.file_size(media)
	if bytes <= 0:
		return ""
	if bytes >= 1 << 30:
		return "%.1f GB" % (bytes / 1073741824.0)
	return "%.0f KB" % maxf(bytes / 1024.0, 1.0) if bytes < 1 << 20 else "%.1f MB" % (bytes / 1048576.0)


static func height_for(width: float, card_layout: Layout) -> float:
	match card_layout:
		Layout.ROW:
			return ROW_HEIGHT * VpxTheme.text_size
		Layout.CHIP:
			return CHIP_HEIGHT * VpxTheme.text_size
	return _card_height(width)


static func _card_height(width: float) -> float:
	return roundf((width - INSET * 2) / THUMB_ASPECT) + INSET * 2 + INFO_HEIGHT * VpxTheme.text_size


func _fit_thumb() -> void:
	if frame == null:
		return
	var height := roundf((size.x - INSET * 2) / THUMB_ASPECT)
	if not is_equal_approx(frame.custom_minimum_size.y, height):
		frame.custom_minimum_size = Vector2(0, height)
		custom_minimum_size.y = _card_height(size.x)
	(thumb.material as ShaderMaterial).set_shader_parameter("size", Vector2(size.x - INSET * 2, height))


func _thumb_frame(frame_size: Vector2, icon_size: int) -> Control:
	var box := Control.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.custom_minimum_size = frame_size
	var background := Panel.new()
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.FIELD, int(THUMB_RADIUS), 0, 0))
	background.set_anchors_preset(PRESET_FULL_RECT)
	box.add_child(background)
	var placeholder_icon := "folder" if is_dir and not single else ("photo" if PanoramaFiles.is_image(media_path()) else "film")
	placeholder = _icon_rect(placeholder_icon, icon_size, VpxTheme.FAINT)
	placeholder.set_anchors_preset(PRESET_CENTER)
	placeholder.offset_left = -icon_size * 0.5
	placeholder.offset_top = -icon_size * 0.5
	placeholder.offset_right = icon_size * 0.5
	placeholder.offset_bottom = icon_size * 0.5
	box.add_child(placeholder)
	thumb = TextureRect.new()
	thumb.mouse_filter = MOUSE_FILTER_IGNORE
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_SCALE
	thumb.set_anchors_preset(PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = RoundedShader
	material.set_shader_parameter("size", frame_size)
	material.set_shader_parameter("radius", THUMB_RADIUS)
	thumb.material = material
	box.add_child(thumb)
	progress = ProgressBar.new()
	progress.theme_type_variation = &"ResumeBar"
	progress.mouse_filter = MOUSE_FILTER_IGNORE
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.step = 0.0
	progress.set_anchors_preset(PRESET_BOTTOM_WIDE)
	progress.offset_top = -5
	progress.offset_left = THUMB_RADIUS * 0.5
	progress.offset_right = -THUMB_RADIUS * 0.5
	progress.offset_bottom = -2
	progress.visible = false
	box.add_child(progress)
	return box


func _badge(variation: StringName) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.theme_type_variation = variation
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	var label := _label(&"AccentBadgeLabel" if variation == &"AccentBadge" else &"BadgeLabel")
	badge.add_child(label)
	badge.visible = false
	frame.add_child(badge)
	return badge


func _pin(control: Control, offset: Vector2, right: bool, bottom: bool) -> void:
	control.anchor_left = 1.0 if right else 0.0
	control.anchor_right = control.anchor_left
	control.anchor_top = 1.0 if bottom else 0.0
	control.anchor_bottom = control.anchor_top
	control.grow_horizontal = GROW_DIRECTION_BEGIN if right else GROW_DIRECTION_END
	control.grow_vertical = GROW_DIRECTION_BEGIN if bottom else GROW_DIRECTION_END
	control.offset_left = offset.x
	control.offset_right = offset.x
	control.offset_top = offset.y
	control.offset_bottom = offset.y


func _set_badge(badge: PanelContainer, label: Label, text: String) -> void:
	label.text = text
	badge.visible = not text.is_empty()


func _star() -> Button:
	var button := Button.new()
	button.theme_type_variation = &"FlatIcon"
	button.toggle_mode = true
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 26)
	button.toggled.connect(func(on: bool) -> void:
		if guard.is_valid() and not guard.call():
			button.set_pressed_no_signal(not on)
			return
		Library.set_favorite(path, on)
		_show_star())
	return button


func _show_star() -> void:
	star.icon = VpxTheme.icon("star" if star.button_pressed else "star_outline", 26)
	var color := VpxTheme.FAVORITE if star.button_pressed else VpxTheme.FAINT
	for role in ["icon_normal_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		star.add_theme_color_override(role, color)
	star.add_theme_color_override("icon_hover_color", VpxTheme.FAVORITE)


func _icon_rect(name: String, icon_size: int, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	rect.texture = VpxTheme.icon(name, icon_size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.modulate = color
	return rect


func _label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label


func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", separation)
	return box


func _margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func apply_text_size() -> void:
	custom_minimum_size.y = height_for(size.x, layout)
	if layout == Layout.CARD:
		title_label.custom_minimum_size.y = 54 * VpxTheme.text_size
