extends Node3D

const FONT_OF_WIDTH := 0.027
const FONT_OF_HEIGHT := 0.075
const BASE_MARGIN := 0.05
const SIDE_MARGIN := 0.06
const EXTRA_BELOW := 0.45
const CANVAS_WIDTH := 1920
const CANVAS_MAX_HEIGHT := 2400
const SUPERSAMPLE := 1.5
const CURVE_SEGMENTS := 48
const IMMERSIVE_FOV := 60.0
const IMMERSIVE_ASPECT := 16.0 / 9.0
const FOLLOW_ANGLE := 30.0
const FOLLOW_SETTLE := 3.0
const FOLLOW_RATE := 3.0
const SURFACE_LIFT := 0.004
const BOX_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const ITALIC_SKEW := 0.2
const BOLD_EMBOLDEN := 0.7
const OUTLINE_RATIO := 0.14
const RENDER_PASSES := 2

var player: VPXPlayer
var screen: MeshInstance3D
var camera: Node3D
var viewport: SubViewport
var bottom_label: RichTextLabel
var top_label: RichTextLabel
var bitmap_layer: Control
var quad: MeshInstance3D
var mesh: QuadMesh
var material: ShaderMaterial
var shown_key := ""
var picture := Vector2.ONE
var canvas_size := Vector2i.ZERO
var follow := Vector3.ZERO
var gliding := false
var textures := {}
var render_passes := 0
var size_format_key := ""


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.set_meta("vpx_text_size_exempt", true)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(canvas)
	bitmap_layer = Control.new()
	bitmap_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bitmap_layer)
	bottom_label = _make_label(Control.GROW_DIRECTION_BEGIN)
	top_label = _make_label(Control.GROW_DIRECTION_END)
	canvas.add_child(bottom_label)
	canvas.add_child(top_label)
	mesh = QuadMesh.new()
	mesh.subdivide_width = CURVE_SEGMENTS
	quad = MeshInstance3D.new()
	quad.mesh = mesh
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/subtitle.gdshader")
	material.set_shader_parameter("subtitle_texture", viewport.get_texture())
	material.render_priority = 8
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	visible = false
	Settings.changed.connect(func() -> void: shown_key = "")
	player.tracks.changed.connect(func() -> void: shown_key = "")


func _make_label(grow: Control.GrowDirection) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.grow_vertical = grow
	var base: Font = ThemeDB.fallback_font
	var italic := FontVariation.new()
	italic.base_font = base
	italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(ITALIC_SKEW, 1.0), Vector2.ZERO)
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = BOLD_EMBOLDEN
	var bold_italic := FontVariation.new()
	bold_italic.base_font = base
	bold_italic.variation_embolden = BOLD_EMBOLDEN
	bold_italic.variation_transform = italic.variation_transform
	label.add_theme_font_override("italics_font", italic)
	label.add_theme_font_override("bold_font", bold)
	label.add_theme_font_override("bold_italics_font", bold_italic)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	return label


func _process(delta: float) -> void:
	var cues: Array = player.tracks.active_cues() if screen.visible and not player.current_path.is_empty() else []
	if cues.is_empty():
		if visible:
			visible = false
			shown_key = ""
			textures.clear()
		return
	_update_geometry()
	var format_key := _format_key()
	if size_format_key != format_key:
		size_format_key = format_key
		shown_key = ""
	var key := _cue_key(cues)
	if key != shown_key:
		shown_key = key
		_render(cues)
	if render_passes > 0:
		render_passes -= 1
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	visible = true
	_place(delta)


func _cue_key(cues: Array) -> String:
	var ids := PackedStringArray()
	for cue in cues:
		ids.append(str(cue["id"]))
	return "%s|%v|%v|%.3f|%s" % [",".join(ids), picture.snappedf(0.001), canvas_size, _active_size(), _format_key()]


func _format_key() -> String:
	return "%d:%d" % [Settings.projection, Settings.stereo]


func _active_size() -> float:
	return float(Settings.subtitle_size_by_format.get(_format_key(), Settings.subtitle_size))


func _flat() -> bool:
	return Settings.projection == Settings.ProjectionMode.FLAT and screen.mesh is QuadMesh


func _update_geometry() -> void:
	if _flat():
		picture = (screen.mesh as QuadMesh).size
	else:
		var width := 2.0 * Settings.subtitle_distance * tan(deg_to_rad(IMMERSIVE_FOV) * 0.5)
		picture = Vector2(width, width / IMMERSIVE_ASPECT)
	var ratio := picture.y / maxf(picture.x, 0.001)
	var width_px := mini(CANVAS_WIDTH, int(CANVAS_MAX_HEIGHT / maxf(ratio * (1.0 + EXTRA_BELOW), 0.001)))
	var size := Vector2i(width_px, int(round(width_px * ratio * (1.0 + EXTRA_BELOW))))
	var world := Vector2(picture.x, picture.y * (1.0 + EXTRA_BELOW))
	if mesh.size != world:
		mesh.size = world
		quad.position.y = -picture.y * EXTRA_BELOW * 0.5
	if size != canvas_size:
		canvas_size = size
		viewport.size_2d_override = size
		viewport.size = Vector2i(Vector2(size) * SUPERSAMPLE)


func _render(cues: Array) -> void:
	var width := float(canvas_size.x)
	var picture_px := width * picture.y / maxf(picture.x, 0.001)
	var scale := _active_size()
	var font_size := int(round(minf(width * FONT_OF_WIDTH, picture_px * FONT_OF_HEIGHT) * scale))
	var bottom := PackedStringArray()
	var top := PackedStringArray()
	var live := {}
	for child in bitmap_layer.get_children():
		child.queue_free()
	for cue in cues:
		if cue.has("image"):
			live[cue["id"]] = true
			_add_bitmap(cue, width, picture_px)
			continue
		var converted := ass_to_bbcode(cue["text"], cue["ass"])
		if converted["text"].strip_edges().is_empty():
			continue
		(top if converted["top"] else bottom).append(converted["text"])
	for id in textures.keys():
		if not live.has(id):
			textures.erase(id)
	var color: Color = Settings.SUBTITLE_COLORS[clampi(Settings.subtitle_color, 0, Settings.SUBTITLE_COLORS.size() - 1)]
	for label in [bottom_label, top_label]:
		label.add_theme_font_size_override("normal_font_size", font_size)
		label.add_theme_font_size_override("italics_font_size", font_size)
		label.add_theme_font_size_override("bold_font_size", font_size)
		label.add_theme_font_size_override("bold_italics_font_size", font_size)
		label.add_theme_color_override("default_color", color)
		label.add_theme_constant_override("outline_size", 0 if Settings.subtitle_box else maxi(2, int(font_size * OUTLINE_RATIO)))
		label.add_theme_constant_override("shadow_offset_x", 0 if Settings.subtitle_box else maxi(1, font_size / 20))
		label.add_theme_constant_override("shadow_offset_y", 0 if Settings.subtitle_box else maxi(1, font_size / 16))
		label.add_theme_constant_override("text_highlight_h_padding", font_size / 3)
		label.add_theme_constant_override("text_highlight_v_padding", font_size / 10)
		label.add_theme_constant_override("line_separation", font_size / 5 if Settings.subtitle_box else 0)
		label.offset_left = width * SIDE_MARGIN
		label.offset_right = -width * SIDE_MARGIN
	bottom_label.offset_bottom = picture_px * (1.0 - BASE_MARGIN - Settings.subtitle_offset)
	bottom_label.offset_top = bottom_label.offset_bottom
	top_label.offset_top = picture_px * BASE_MARGIN
	top_label.offset_bottom = top_label.offset_top
	bottom_label.text = _boxed("\n".join(bottom))
	top_label.text = _boxed("\n".join(top))
	bottom_label.visible = not bottom.is_empty()
	top_label.visible = not top.is_empty()
	render_passes = RENDER_PASSES


func _boxed(text: String) -> String:
	if text.is_empty() or not Settings.subtitle_box:
		return text
	return "[bgcolor=#%s]%s[/bgcolor]" % [BOX_COLOR.to_html(true), text]


func _add_bitmap(cue: Dictionary, width: float, picture_px: float) -> void:
	var id: int = cue["id"]
	if not textures.has(id):
		textures[id] = ImageTexture.create_from_image(cue["image"])
	var rect: Rect2 = cue["rect"]
	var scale := _active_size()
	var size := rect.size * Vector2(width, picture_px) * scale
	var bottom_center := Vector2((rect.position.x + rect.size.x * 0.5) * width, (rect.position.y + rect.size.y) * picture_px - Settings.subtitle_offset * picture_px)
	var view := TextureRect.new()
	view.texture = textures[id]
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = bottom_center - Vector2(size.x * 0.5, size.y)
	view.size = size
	bitmap_layer.add_child(view)


func _place(delta: float) -> void:
	if _flat():
		global_transform = screen.global_transform.translated_local(Vector3(0.0, 0.0, SURFACE_LIFT))
		material.set_shader_parameter("flat_curve", screen.curve_inverse_radius())
		return
	material.set_shader_parameter("flat_curve", 0.0)
	var forward := FloatPanel.level_forward(camera)
	if follow == Vector3.ZERO:
		follow = forward
	var angle := rad_to_deg(follow.angle_to(forward))
	if angle > FOLLOW_ANGLE:
		gliding = true
	if gliding:
		follow = follow.slerp(forward, 1.0 - exp(-delta * FOLLOW_RATE)).normalized()
		gliding = angle > FOLLOW_SETTLE
	global_position = camera.global_position + follow * Settings.subtitle_distance
	look_at(camera.global_position, FloatPanel.frame.y, true)


func recenter() -> void:
	follow = Vector3.ZERO
	gliding = false


static func ass_to_bbcode(text: String, is_ass: bool) -> Dictionary:
	var out := ""
	var top := false
	var drawing := false
	var open := {"i": false, "b": false, "u": false, "s": false, "color": false}
	var i := 0
	var length := text.length()
	while i < length:
		var c := text[i]
		if is_ass and c == "{":
			var close := text.find("}", i)
			if close < 0:
				close = length
			for tag in text.substr(i + 1, close - i - 1).split("\\", false):
				var result := _apply_tag(tag.strip_edges(), open)
				out += result["bbcode"]
				if result.has("top"):
					top = result["top"]
				if result.has("drawing"):
					drawing = result["drawing"]
			i = close + 1
			continue
		if is_ass and c == "\\" and i + 1 < length:
			var next := text[i + 1]
			if next == "N" or next == "n":
				out += "\n"
				i += 2
				continue
			if next == "h":
				out += " "
				i += 2
				continue
		if not drawing:
			out += "[lb]" if c == "[" else c
		i += 1
	for tag in ["color", "s", "u", "b", "i"]:
		if open[tag]:
			out += "[/%s]" % tag
	return {"text": out.strip_edges(), "top": top}


static func _apply_tag(tag: String, open: Dictionary) -> Dictionary:
	var result := {"bbcode": ""}
	if tag.is_empty():
		return result
	for style in ["i", "b", "u", "s"]:
		if tag == style + "1" or (style == "b" and tag.length() > 1 and tag[0] == "b" and tag.substr(1).is_valid_int() and int(tag.substr(1)) >= 600):
			if not open[style]:
				open[style] = true
				result["bbcode"] = "[%s]" % style
			return result
		if tag == style + "0" or (style == "b" and tag.length() > 1 and tag[0] == "b" and tag.substr(1).is_valid_int() and int(tag.substr(1)) < 600 and int(tag.substr(1)) > 1):
			if open[style]:
				open[style] = false
				result["bbcode"] = "[/%s]" % style
			return result
	if tag.begins_with("an") and tag.substr(2).is_valid_int():
		result["top"] = int(tag.substr(2)) >= 7
	elif tag.begins_with("a") and tag.substr(1).is_valid_int():
		result["top"] = int(tag.substr(1)) >= 5
	elif tag.begins_with("p") and tag.substr(1).is_valid_int():
		result["drawing"] = int(tag.substr(1)) > 0
	elif tag.begins_with("c&H") or tag.begins_with("1c&H"):
		var hex := tag.substr(tag.find("&H") + 2).replace("&", "").lpad(6, "0")
		hex = hex.substr(hex.length() - 6)
		var bbcode := "[/color]" if open["color"] else ""
		open["color"] = true
		result["bbcode"] = bbcode + "[color=#%s%s%s]" % [hex.substr(4, 2), hex.substr(2, 2), hex.substr(0, 2)]
	elif tag == "r":
		var closing := ""
		for style in ["color", "s", "u", "b", "i"]:
			if open[style]:
				open[style] = false
				closing += "[/%s]" % style
		result["bbcode"] = closing
	return result
