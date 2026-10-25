class_name VpxTheme

const Icons := preload("res://scripts/icons.gd")

const BACKGROUND := Color("121416")
const SURFACE := Color("1b1e21")
const FIELD := Color("15181b")
const RAISED := Color("2b3035")
const HOVER := Color("363d43")
const LIST := Color("22262a")
const BORDER := Color("7c8792")
const TRACK := Color("67717b")
const DEFAULT_ACCENT := Color("70c9dc")
const DEFAULT_TONES := [Color("a0deeb"), Color("203b43"), Color("102126"), Color("8ed1be")]
const ACCENT_PRESETS := [
	["Cyan", Color("70c9dc")],
	["Blue", Color("82a8ff")],
	["Violet", Color("b59cf2")],
	["Pink", Color("f09cc6")],
	["Red", Color("f08b80")],
	["Orange", Color("f5a66e")],
	["Green", Color("8fd694")],
	["Silver", Color("cfd6dd")],
]
const TEXT := Color("e4e8ec")
const MUTED := Color("adb6bf")
const FAINT := Color("858f99")
const FOCUS := Color("f3ce85")
const FAVORITE := Color("e8bd72")
const SCRIM := Color("080a0cf0")
const SHADOW := Color("00000073")
const OVERLAY_ALPHA := 0.96
const OVERLAY := Color(BACKGROUND, OVERLAY_ALPHA)
const TRANSPARENT := Color(0, 0, 0, 0)
const FONT_SIZE := 26
const SMALL_FONT_SIZE := 21
const TITLE_FONT_SIZE := 34
const RADIUS := 14
const ICON_SIZE := 30
const ICON_SUPERSAMPLE := 2
const UI_FONT_KEYS := ["font_size", "normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]

static var text_size := 1.0
static var ACCENT := DEFAULT_ACCENT
static var ACCENT_HOVER: Color = DEFAULT_TONES[0]
static var ACCENT_SOFT: Color = DEFAULT_TONES[1]
static var ON_ACCENT: Color = DEFAULT_TONES[2]
static var SPECTRUM_END: Color = DEFAULT_TONES[3]
static var themes: Array[WeakRef] = []
static var accent_boxes: Array[Array] = []


static func set_accent(color: Color) -> void:
	color.a = 1.0
	if color.is_equal_approx(ACCENT):
		return
	ACCENT = color
	if color.is_equal_approx(DEFAULT_ACCENT):
		ACCENT_HOVER = DEFAULT_TONES[0]
		ACCENT_SOFT = DEFAULT_TONES[1]
		ON_ACCENT = DEFAULT_TONES[2]
		SPECTRUM_END = DEFAULT_TONES[3]
	else:
		ACCENT_HOVER = color.lerp(Color.WHITE, 0.35)
		ACCENT_SOFT = BACKGROUND.lerp(color, 0.2)
		ON_ACCENT = color.darkened(0.84)
		SPECTRUM_END = Color.from_hsv(wrapf(color.h - 0.083, 0.0, 1.0), color.s * 0.8, minf(color.v * 0.98, 1.0))
	var live: Array[WeakRef] = []
	for reference in themes:
		var theme := reference.get_ref() as Theme
		if theme == null:
			continue
		var fresh := Theme.new()
		_populate(fresh)
		_scale_theme(fresh)
		theme.merge_with(fresh)
		live.append(reference)
	themes = live
	var boxes: Array[Array] = []
	for entry in accent_boxes:
		var box := (entry[0] as WeakRef).get_ref() as StyleBoxFlat
		if box == null:
			continue
		box.bg_color = accent_tone(entry[1])
		boxes.append(entry)
	accent_boxes = boxes


static func accent_tone(tone: StringName) -> Color:
	match tone:
		&"hover":
			return ACCENT_HOVER
		&"soft":
			return ACCENT_SOFT
	return ACCENT


static func accent_flat(radius := RADIUS, margin_h := 20, margin_v := 10, tone := &"accent") -> StyleBoxFlat:
	var box := flat(accent_tone(tone), radius, margin_h, margin_v)
	accent_boxes.append([weakref(box), tone])
	return box


static func build() -> Theme:
	var theme := Theme.new()
	_populate(theme)
	_scale_theme(theme)
	themes.append(weakref(theme))
	return theme


static func _populate(theme: Theme) -> void:
	theme.default_font_size = FONT_SIZE
	_buttons(theme)
	_nav(theme)
	_icon_buttons(theme)
	_chips(theme)
	_toggles(theme)
	_cards(theme)
	_list_items(theme)
	_line_edit(theme)
	_scroll_bar(theme)
	_slider(theme)
	_progress(theme)
	_file_dialog(theme)
	_popup_menu(theme)
	_labels(theme)
	_panels(theme)
	_dialogs(theme)


static func icon(name: String, size := ICON_SIZE) -> Texture2D:
	var colors := {}
	if name == "switch_on":
		colors = {"track": ACCENT.to_html(false), "thumb": ON_ACCENT.to_html(false), "border": ACCENT.to_html(false)}
	elif name == "switch_off":
		colors = {"track": FIELD.to_html(false), "thumb": MUTED.to_html(false), "border": BORDER.to_html(false)}
	return Icons.texture(name, size * ICON_SUPERSAMPLE, colors)


static func flat(color: Color, radius := RADIUS, margin_h := 20, margin_v := 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing_size = 1.2
	return box


static func hover(color: Color, radius := RADIUS, margin_h := 20, margin_v := 10) -> StyleBoxFlat:
	var box := flat(color, radius, margin_h, margin_v)
	box.border_color = ON_ACCENT if color.is_equal_approx(ACCENT_HOVER) else ACCENT_HOVER
	box.set_border_width_all(3)
	return box


static func outlined(color: Color, border: Color, width := 2, radius := RADIUS, margin_h := 20, margin_v := 10) -> StyleBoxFlat:
	var box := flat(color, radius, margin_h, margin_v)
	box.border_color = border
	box.set_border_width_all(width)
	return box


static func focus_ring(radius := RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = FOCUS
	box.set_border_width_all(4)
	box.set_corner_radius_all(radius + 4)
	box.set_expand_margin_all(4)
	box.anti_aliasing_size = 1.2
	return box


static func circle(color: Color, size: int) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.67, 0.72, 0.9, 1.0])
	gradient.colors = PackedColorArray([color, color, ON_ACCENT, ON_ACCENT, Color(ON_ACCENT, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


static func _button_colors(theme: Theme, type: String, normal: Color, pressed: Color) -> void:
	for role in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(role, type, normal)
	for role in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(role, type, pressed)
	theme.set_color("font_disabled_color", type, FAINT)
	for role in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		theme.set_color(role, type, normal)
	for role in ["icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(role, type, pressed)
	theme.set_color("icon_disabled_color", type, FAINT)
	theme.set_stylebox("focus", type, focus_ring())


static func _buttons(theme: Theme) -> void:
	theme.set_stylebox("tab_selected", "TabBar", accent_flat(10, 16, 8, &"soft"))
	theme.set_stylebox("tab_unselected", "TabBar", flat(SURFACE, 10, 16, 8))
	theme.set_stylebox("tab_hovered", "TabBar", flat(RAISED, 10, 16, 8))
	theme.set_stylebox("tab_focus", "TabBar", focus_ring(10))
	theme.set_color("font_selected_color", "TabBar", TEXT)
	theme.set_color("font_unselected_color", "TabBar", MUTED)
	theme.set_color("font_hovered_color", "TabBar", TEXT)
	for direction in ["decrement", "increment"]:
		var arrow := icon("chevron_left" if direction == "decrement" else "chevron_right", 24)
		theme.set_icon(direction, "TabBar", arrow)
		theme.set_icon(direction + "_highlight", "TabBar", arrow)
	theme.set_stylebox("normal", "Button", flat(RAISED))
	theme.set_stylebox("hover", "Button", hover(HOVER))
	theme.set_stylebox("pressed", "Button", flat(ACCENT))
	theme.set_stylebox("hover_pressed", "Button", hover(ACCENT_HOVER))
	theme.set_stylebox("disabled", "Button", flat(SURFACE))
	_button_colors(theme, "Button", TEXT, ON_ACCENT)
	theme.set_constant("icon_max_width", "Button", ICON_SIZE)
	theme.set_constant("h_separation", "Button", 12)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", flat(ACCENT))
	theme.set_stylebox("hover", "PrimaryButton", hover(ACCENT_HOVER))
	theme.set_stylebox("pressed", "PrimaryButton", flat(ACCENT_HOVER))
	theme.set_stylebox("hover_pressed", "PrimaryButton", hover(ACCENT_HOVER))
	_button_colors(theme, "PrimaryButton", ON_ACCENT, ON_ACCENT)
	theme.set_stylebox("normal", "OptionButton", flat(RAISED, RADIUS, 20, 10))
	theme.set_stylebox("hover", "OptionButton", hover(HOVER, RADIUS, 20, 10))
	theme.set_stylebox("pressed", "OptionButton", hover(HOVER, RADIUS, 20, 10))
	theme.set_stylebox("hover_pressed", "OptionButton", hover(HOVER, RADIUS, 20, 10))
	theme.set_icon("arrow", "OptionButton", icon("chevron_down", 22))
	theme.set_constant("arrow_margin", "OptionButton", 16)
	_button_colors(theme, "OptionButton", TEXT, TEXT)
	theme.set_type_variation("CompactOption", "OptionButton")
	theme.set_font_size("font_size", "CompactOption", 23)


static func _nav_style(color: Color) -> StyleBoxFlat:
	var box := flat(color, 12, 17, 8)
	box.content_margin_right = 7
	box.expand_margin_left = -6
	box.expand_margin_right = -6
	return box


static func _nav(theme: Theme) -> void:
	theme.set_type_variation("NavItem", "Button")
	theme.set_stylebox("normal", "NavItem", _nav_style(TRANSPARENT))
	theme.set_stylebox("hover", "NavItem", _nav_style(RAISED))
	theme.set_stylebox("pressed", "NavItem", _nav_style(ACCENT_SOFT))
	var selected_hover := _nav_style(ACCENT_SOFT)
	selected_hover.border_color = ACCENT_HOVER
	selected_hover.set_border_width_all(1)
	theme.set_stylebox("hover_pressed", "NavItem", selected_hover)
	theme.set_stylebox("disabled", "NavItem", _nav_style(TRANSPARENT))
	_button_colors(theme, "NavItem", MUTED, ACCENT_HOVER)
	theme.set_color("font_hover_color", "NavItem", TEXT)
	theme.set_color("icon_hover_color", "NavItem", TEXT)
	theme.set_constant("h_separation", "NavItem", 10)
	theme.set_type_variation("Crumb", "Button")
	theme.set_stylebox("normal", "Crumb", flat(TRANSPARENT, 10, 10, 6))
	theme.set_stylebox("hover", "Crumb", hover(RAISED, 10, 10, 6))
	theme.set_stylebox("pressed", "Crumb", flat(RAISED, 10, 10, 6))
	theme.set_stylebox("hover_pressed", "Crumb", hover(HOVER, 10, 10, 6))
	_button_colors(theme, "Crumb", MUTED, TEXT)
	theme.set_color("font_hover_color", "Crumb", TEXT)
	theme.set_font_size("font_size", "Crumb", 23)


static func _icon_buttons(theme: Theme) -> void:
	theme.set_type_variation("IconButton", "Button")
	theme.set_stylebox("normal", "IconButton", flat(RAISED, RADIUS, 14, 10))
	theme.set_stylebox("hover", "IconButton", hover(HOVER, RADIUS, 14, 10))
	theme.set_stylebox("pressed", "IconButton", flat(ACCENT, RADIUS, 14, 10))
	theme.set_stylebox("hover_pressed", "IconButton", hover(ACCENT_HOVER, RADIUS, 14, 10))
	theme.set_stylebox("disabled", "IconButton", flat(SURFACE, RADIUS, 14, 10))
	_button_colors(theme, "IconButton", TEXT, ON_ACCENT)
	theme.set_type_variation("FlatIcon", "Button")
	theme.set_stylebox("normal", "FlatIcon", flat(TRANSPARENT, RADIUS, 12, 8))
	theme.set_stylebox("hover", "FlatIcon", hover(RAISED, RADIUS, 12, 8))
	theme.set_stylebox("pressed", "FlatIcon", flat(ACCENT_SOFT, RADIUS, 12, 8))
	theme.set_stylebox("hover_pressed", "FlatIcon", hover(ACCENT_SOFT, RADIUS, 12, 8))
	_button_colors(theme, "FlatIcon", MUTED, ACCENT_HOVER)
	theme.set_color("font_hover_color", "FlatIcon", TEXT)
	theme.set_color("icon_hover_color", "FlatIcon", TEXT)
	theme.set_type_variation("ValueButton", "Button")
	for state in ["hover", "hover_pressed", "pressed"]:
		theme.set_stylebox(state, "ValueButton", hover(TRANSPARENT, RADIUS, 0, 0))
	theme.set_type_variation("PlayButton", "Button")
	theme.set_stylebox("normal", "PlayButton", flat(ACCENT, 40, 0, 0))
	theme.set_stylebox("hover", "PlayButton", outlined(ACCENT_HOVER, ON_ACCENT, 3, 40, 0, 0))
	theme.set_stylebox("pressed", "PlayButton", flat(ACCENT_HOVER, 40, 0, 0))
	theme.set_stylebox("hover_pressed", "PlayButton", outlined(ACCENT_HOVER, ON_ACCENT, 3, 40, 0, 0))
	_button_colors(theme, "PlayButton", ON_ACCENT, ON_ACCENT)
	theme.set_stylebox("focus", "PlayButton", focus_ring(40))
	theme.set_constant("icon_max_width", "PlayButton", 36)


static func _chips(theme: Theme) -> void:
	theme.set_type_variation("Chip", "Button")
	theme.set_stylebox("normal", "Chip", flat(TRANSPARENT, 12, 16, 6))
	theme.set_stylebox("hover", "Chip", hover(RAISED, 12, 16, 6))
	theme.set_stylebox("pressed", "Chip", flat(ACCENT, 12, 16, 6))
	theme.set_stylebox("hover_pressed", "Chip", hover(ACCENT_HOVER, 12, 16, 6))
	_button_colors(theme, "Chip", MUTED, ON_ACCENT)
	theme.set_color("font_hover_color", "Chip", TEXT)
	theme.set_color("icon_hover_color", "Chip", TEXT)
	theme.set_font_size("font_size", "Chip", 23)
	theme.set_constant("icon_max_width", "Chip", 24)
	theme.set_constant("h_separation", "Chip", 8)
	theme.set_type_variation("PageTab", "Chip")
	theme.set_stylebox("normal", "PageTab", flat(TRANSPARENT, 12, 18, 10))
	theme.set_stylebox("hover", "PageTab", hover(RAISED, 12, 18, 10))
	theme.set_stylebox("pressed", "PageTab", flat(ACCENT_SOFT, 12, 18, 10))
	theme.set_stylebox("hover_pressed", "PageTab", hover(ACCENT_SOFT, 12, 18, 10))
	_button_colors(theme, "PageTab", MUTED, ACCENT_HOVER)
	theme.set_color("font_hover_color", "PageTab", TEXT)
	theme.set_color("icon_hover_color", "PageTab", TEXT)
	theme.set_type_variation("Segment", "PanelContainer")
	theme.set_stylebox("panel", "Segment", flat(FIELD, 16, 4, 4))


static func _cards(theme: Theme) -> void:
	theme.set_type_variation("Card", "Button")
	theme.set_stylebox("normal", "Card", flat(LIST, 16, 0, 0))
	theme.set_stylebox("hover", "Card", outlined(RAISED, ACCENT_HOVER, 3, 16, 0, 0))
	theme.set_stylebox("pressed", "Card", outlined(ACCENT_SOFT, ACCENT, 3, 16, 0, 0))
	theme.set_stylebox("hover_pressed", "Card", outlined(ACCENT_SOFT, ACCENT_HOVER, 3, 16, 0, 0))
	_button_colors(theme, "Card", TEXT, TEXT)
	theme.set_stylebox("focus", "Card", focus_ring(16))
	theme.set_type_variation("Badge", "PanelContainer")
	theme.set_stylebox("panel", "Badge", flat(SCRIM, 8, 8, 1))
	theme.set_type_variation("AccentBadge", "PanelContainer")
	theme.set_stylebox("panel", "AccentBadge", outlined(ACCENT_SOFT, ACCENT, 1, 8, 8, 1))
	theme.set_type_variation("BadgeLabel", "Label")
	theme.set_font_size("font_size", "BadgeLabel", 17)
	theme.set_color("font_color", "BadgeLabel", TEXT)
	theme.set_type_variation("AccentBadgeLabel", "BadgeLabel")
	theme.set_color("font_color", "AccentBadgeLabel", ACCENT_HOVER)
	theme.set_type_variation("CardTitle", "Label")
	theme.set_font_size("font_size", "CardTitle", 20)
	theme.set_color("font_color", "CardTitle", TEXT)
	theme.set_type_variation("CardMeta", "Label")
	theme.set_font_size("font_size", "CardMeta", 18)
	theme.set_color("font_color", "CardMeta", MUTED)


static func _list_items(theme: Theme) -> void:
	theme.set_type_variation("ListItem", "Button")
	theme.set_stylebox("normal", "ListItem", flat(LIST, 12, 16, 6))
	theme.set_stylebox("hover", "ListItem", outlined(RAISED, ACCENT_HOVER, 3, 12, 16, 6))
	theme.set_stylebox("pressed", "ListItem", outlined(ACCENT_SOFT, ACCENT, 3, 12, 16, 6))
	theme.set_stylebox("hover_pressed", "ListItem", outlined(ACCENT_SOFT, ACCENT_HOVER, 3, 12, 16, 6))
	_button_colors(theme, "ListItem", TEXT, TEXT)
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())


static func _line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", outlined(FIELD, BORDER, 2, 10, 16, 10))
	theme.set_stylebox("read_only", "LineEdit", outlined(FIELD, BORDER, 2, 10, 16, 10))
	theme.set_stylebox("focus", "LineEdit", outlined(FIELD, FOCUS, 3, 10, 16, 10))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT_HOVER)
	theme.set_color("font_uneditable_color", "LineEdit", MUTED)
	theme.set_color("selection_color", "LineEdit", ACCENT)
	theme.set_color("font_selected_color", "LineEdit", ON_ACCENT)
	theme.set_color("clear_button_color", "LineEdit", MUTED)
	theme.set_color("clear_button_color_pressed", "LineEdit", ACCENT_HOVER)


static func _popup_menu(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", outlined(SURFACE, BORDER, 2, RADIUS, 8, 8))
	theme.set_stylebox("hover", "PopupMenu", outlined(ACCENT_SOFT, ACCENT_HOVER, 2, 10, 16, 8))
	theme.set_stylebox("separator", "PopupMenu", flat(RAISED, 0, 0, 1))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", FAINT)
	theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
	theme.set_color("font_separator_color", "PopupMenu", MUTED)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_constant("v_separation", "PopupMenu", 16)
	theme.set_constant("item_start_padding", "PopupMenu", 16)
	theme.set_constant("item_end_padding", "PopupMenu", 16)
	theme.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	var check := icon("check", 22)
	theme.set_icon("radio_checked", "PopupMenu", check)
	theme.set_icon("checked", "PopupMenu", check)
	theme.set_icon("radio_unchecked", "PopupMenu", icon("radio_unchecked", 22))
	theme.set_icon("unchecked", "PopupMenu", icon("unchecked", 22))


static func _scroll_bar(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, flat(FIELD, 8, 7 if type == "VScrollBar" else 0, 7 if type == "HScrollBar" else 0))
		theme.set_stylebox("grabber", type, flat(BORDER, 8, 0, 0))
		theme.set_stylebox("grabber_highlight", type, flat(ACCENT_HOVER, 8, 0, 0))
		theme.set_stylebox("grabber_pressed", type, flat(ACCENT, 8, 0, 0))


static func _slider(theme: Theme) -> void:
	for type in ["HSlider", "VSlider"]:
		var horizontal: bool = type == "HSlider"
		theme.set_stylebox("slider", type, flat(TRACK, 6, 0 if horizontal else 5, 5 if horizontal else 0))
		theme.set_stylebox("grabber_area", type, flat(ACCENT, 6, 0 if horizontal else 5, 5 if horizontal else 0))
		theme.set_stylebox("grabber_area_highlight", type, flat(ACCENT_HOVER, 6, 0 if horizontal else 5, 5 if horizontal else 0))
		theme.set_icon("grabber", type, circle(TEXT, 30))
		theme.set_icon("grabber_highlight", type, circle(ACCENT_HOVER, 38))
		theme.set_icon("grabber_disabled", type, circle(MUTED, 30))
		theme.set_stylebox("focus", type, focus_ring(8))


static func _progress(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", flat(TRACK, 3, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", flat(ACCENT, 3, 0, 0))
	theme.set_type_variation("ResumeBar", "ProgressBar")
	theme.set_stylebox("background", "ResumeBar", flat(SCRIM, 0, 0, 0))
	theme.set_stylebox("fill", "ResumeBar", flat(ACCENT, 0, 0, 0))


static func _file_dialog(theme: Theme) -> void:
	theme.set_stylebox("panel", "FileDialog", flat(SURFACE, 18, 18, 14))
	theme.set_stylebox("normal", "FileDialog", flat(SURFACE, 8, 8, 4))
	theme.set_stylebox("hover", "FileDialog", hover(ACCENT_SOFT, 8, 8, 4))
	theme.set_stylebox("pressed", "FileDialog", flat(ACCENT, 8, 8, 4))
	theme.set_stylebox("selected", "FileDialog", flat(ACCENT, 8, 8, 4))
	theme.set_color("font_color", "FileDialog", TEXT)
	theme.set_color("font_hover_color", "FileDialog", TEXT)
	theme.set_color("font_pressed_color", "FileDialog", ON_ACCENT)
	theme.set_color("font_selected_color", "FileDialog", ON_ACCENT)
	theme.set_color("selection_color", "FileDialog", ACCENT)
	theme.set_color("icon_normal_color", "FileDialog", MUTED)
	theme.set_color("icon_hover_color", "FileDialog", ACCENT_HOVER)
	theme.set_color("icon_pressed_color", "FileDialog", ON_ACCENT)
	theme.set_color("icon_selected_color", "FileDialog", ON_ACCENT)


static func _labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_type_variation("Title", "Label")
	theme.set_font_size("font_size", "Title", TITLE_FONT_SIZE)
	theme.set_type_variation("SectionTitle", "Label")
	theme.set_font_size("font_size", "SectionTitle", 19)
	theme.set_color("font_color", "SectionTitle", ACCENT_HOVER)
	var heading := flat(TRANSPARENT, 0, 4, 2)
	heading.content_margin_top = 14
	theme.set_stylebox("normal", "SectionTitle", heading)
	theme.set_type_variation("NavSection", "SectionTitle")
	var nav_heading := flat(TRANSPARENT, 0, 18, 4)
	nav_heading.content_margin_left = 64
	nav_heading.content_margin_right = 0
	nav_heading.content_margin_top = 28
	theme.set_stylebox("normal", "NavSection", nav_heading)
	theme.set_color("font_color", "NavSection", MUTED)
	theme.set_font_size("font_size", "NavSection", 18)
	theme.set_type_variation("Caption", "Label")
	theme.set_font_size("font_size", "Caption", SMALL_FONT_SIZE)
	theme.set_color("font_color", "Caption", MUTED)
	theme.set_type_variation("Hint", "Label")
	theme.set_font_size("font_size", "Hint", 21)
	theme.set_color("font_color", "Hint", MUTED)


static func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", flat(SURFACE, 16, 16, 16))
	theme.set_type_variation("Sheet", "PanelContainer")
	theme.set_stylebox("panel", "Sheet", flat(BACKGROUND, 28, 0, 0))
	theme.set_type_variation("Rail", "PanelContainer")
	theme.set_stylebox("panel", "Rail", flat(TRANSPARENT, 0, 0, 0))
	theme.set_type_variation("RailOverlay", "Panel")
	var rail_overlay := flat(BACKGROUND, RADIUS, 0, 0)
	rail_overlay.shadow_color = SHADOW
	rail_overlay.shadow_size = 18
	theme.set_stylebox("panel", "RailOverlay", rail_overlay)
	theme.set_type_variation("Group", "PanelContainer")
	theme.set_stylebox("panel", "Group", flat(SURFACE, 18, 20, 16))
	theme.set_type_variation("PlayerBar", "PanelContainer")
	theme.set_stylebox("panel", "PlayerBar", flat(SURFACE, 22, 22, 14))
	theme.set_type_variation("Bubble", "PanelContainer")
	theme.set_stylebox("panel", "Bubble", outlined(RAISED, ACCENT, 2, 10, 12, 4))


static func _dialogs(theme: Theme) -> void:
	for type in ["AcceptDialog", "ConfirmationDialog", "PopupPanel"]:
		theme.set_stylebox("panel", type, outlined(SURFACE, BORDER, 2, 18, 18, 14))
	for type in ["Window", "AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		theme.set_color("title_color", type, TEXT)
		theme.set_color("title_outline_modulate", type, TRANSPARENT)
	theme.set_type_variation("TooltipSurface", "PanelContainer")
	var tooltip := outlined(SURFACE, BORDER, 1, RADIUS, 16, 12)
	tooltip.shadow_color = SHADOW
	tooltip.shadow_size = 8
	theme.set_stylebox("panel", "TooltipSurface", tooltip)
	theme.set_type_variation("TooltipLabel", "Label")
	theme.set_font_size("font_size", "TooltipLabel", SMALL_FONT_SIZE)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_color("font_shadow_color", "TooltipLabel", TRANSPARENT)
	theme.set_stylebox("panel", "ItemList", outlined(FIELD, BORDER, 1, 10, 8, 8))
	for state in ["selected", "selected_focus"]:
		theme.set_stylebox(state, "ItemList", outlined(ACCENT_SOFT, ACCENT, 2, 8, 8, 4))
	theme.set_stylebox("cursor", "ItemList", focus_ring(8))
	theme.set_stylebox("cursor_unfocused", "ItemList", outlined(TRANSPARENT, BORDER, 1, 8, 0, 0))
	theme.set_stylebox("focus", "ItemList", focus_ring(10))
	theme.set_stylebox("hovered", "ItemList", flat(RAISED, 8, 8, 4))
	for state in ["hovered_selected", "hovered_selected_focus"]:
		theme.set_stylebox(state, "ItemList", outlined(ACCENT_SOFT, ACCENT_HOVER, 2, 8, 8, 4))
	theme.set_color("font_hovered_selected_color", "ItemList", TEXT)
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", TEXT)
	theme.set_color("font_hovered_color", "ItemList", TEXT)

	for state in ["embedded_border", "embedded_unfocused_border"]:
		var border := ThemeDB.get_default_theme().get_stylebox(state, "Window").duplicate() as StyleBoxFlat
		border.bg_color = SURFACE
		border.border_color = BORDER
		theme.set_stylebox(state, "Window", border)
	theme.set_stylebox("panel", "Tree", outlined(FIELD, BORDER, 1, 10, 8, 8))
	theme.set_stylebox("focus", "Tree", focus_ring(10))
	for state in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
		theme.set_stylebox(state, "Tree", outlined(ACCENT_SOFT, ACCENT, 2, 8, 8, 4))
	for state in ["hovered", "hovered_dimmed", "button_hover", "custom_button_hover", "title_button_hover"]:
		theme.set_stylebox(state, "Tree", flat(RAISED, 8, 8, 4))
	for role in ["font_color", "font_hovered_color", "font_hovered_selected_color", "font_selected_color", "title_button_color"]:
		theme.set_color(role, "Tree", TEXT)
	for role in ["font_hovered_dimmed_color", "font_disabled_color"]:
		theme.set_color(role, "Tree", MUTED)
	for role in ["guide_color", "relationship_line_color"]:
		theme.set_color(role, "Tree", RAISED)
	theme.set_color("guide_color", "ItemList", RAISED)
	for role in ["drop_on_item_color", "drop_position_color", "parent_hl_line_color", "children_hl_line_color"]:
		theme.set_color(role, "Tree", ACCENT)


static func _toggles(theme: Theme) -> void:
	_button_colors(theme, "CheckButton", TEXT, TEXT)
	theme.set_constant("icon_max_width", "CheckButton", 64)
	for state in ["normal", "pressed", "disabled"]:
		theme.set_stylebox(state, "CheckButton", flat(TRANSPARENT))
	for state in ["hover", "hover_pressed"]:
		theme.set_stylebox(state, "CheckButton", hover(RAISED))
	for role in ["button_checked_color", "button_unchecked_color"]:
		theme.set_color(role, "CheckButton", Color.WHITE)
	var disabled_colors := {"track": FAINT.to_html(false), "thumb": ON_ACCENT.to_html(false), "border": FAINT.to_html(false)}
	var disabled_on := Icons.texture("switch_on", 48, disabled_colors)
	disabled_colors = {"track": FIELD.to_html(false), "thumb": FAINT.to_html(false), "border": FAINT.to_html(false)}
	var disabled_off := Icons.texture("switch_off", 48, disabled_colors)
	for suffix in ["", "_mirrored"]:
		theme.set_icon("checked" + suffix, "CheckButton", icon("switch_on", 24))
		theme.set_icon("unchecked" + suffix, "CheckButton", icon("switch_off", 24))
		theme.set_icon("checked_disabled" + suffix, "CheckButton", disabled_on)
		theme.set_icon("unchecked_disabled" + suffix, "CheckButton", disabled_off)


static func set_text_size(value: float, root: Node) -> void:
	if is_equal_approx(text_size, value):
		return
	text_size = value
	var live: Array[WeakRef] = []
	for reference in themes:
		var theme := reference.get_ref() as Theme
		if theme == null:
			continue
		var fresh := Theme.new()
		_populate(fresh)
		_scale_theme(fresh)
		theme.merge_with(fresh)
		live.append(reference)
	themes = live
	_scale_tree(root)


static func _scale_theme(theme: Theme) -> void:
	theme.default_font_size = roundi(FONT_SIZE * text_size)
	for type: StringName in theme.get_type_list():
		for key: StringName in theme.get_font_size_list(type):
			theme.set_font_size(key, type, roundi(theme.get_font_size(key, type) * text_size))


static func _scale_tree(node: Node) -> void:
	scale_control(node)
	for child in node.get_children():
		_scale_tree(child)


static func scale_control(node: Variant) -> void:
	if not is_instance_valid(node) or not node is Control or not node.is_inside_tree() or node.get_viewport().has_meta("vpx_text_size_exempt"):
		return
	for font_key: String in UI_FONT_KEYS:
		var metadata := "vpx_font_" + font_key
		if not node.has_meta(metadata) and not node.has_theme_font_size_override(font_key):
			continue
		if not node.has_meta(metadata):
			node.set_meta(metadata, node.get_theme_font_size(font_key))
		node.add_theme_font_size_override(font_key, roundi(float(node.get_meta(metadata)) * text_size))
