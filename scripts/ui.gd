extends Control

signal status_requested(message: String, busy: bool)
signal recovery_requested
signal recovery_finished
signal quit_requested
signal close_requested
signal pick_requested
signal recenter_requested
signal reset_position_requested
signal level_requested

const BackgroundTask := preload("res://scripts/background_task.gd")
const VIDEO_EXTENSIONS := ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ts", "m2ts", "vob", "wmv", "flv", "mpg", "mpeg"]
const DISC_EXTENSIONS := ["iso"]
const FormatDetector := preload("res://scripts/format_detector.gd")
const ArchiveFiles := preload("res://scripts/archive_files.gd")
const SEEK_STEP := 10.0
const NAV_HEIGHT := 50
const PRESET_HEIGHT := 58
const STATS_INTERVAL := 0.5
const PICTURE_SETTINGS := ["screen_size", "screen_curve", "flat_image_repeat", "edge_fade", "brightness", "gamma", "saturation", "sharpness_level"]
const ANGLE_SETTINGS := ["angle_yaw", "angle_pitch", "angle_roll"]
const PAN_SETTINGS := ["photo_pan_x", "photo_pan_y"]
const MEDIA_PAGE := "Audio & subs"
const NAV_SECTIONS := [["Library"], ["Format", "Picture", "Angles", "Passthrough"], [MEDIA_PAGE], ["System", "Controls"]]
const NAV_TITLES := ["Library", "Video", MEDIA_PAGE, "Settings"]
const NAV_ICONS := ["library", "picture", "subtitles", "system"]
const PAGE_TITLES := {"Angles": "Position", "System": "General"}
const PAGE_ICONS := {"Format": "format", "Picture": "picture", "Angles": "angles", "Passthrough": "passthrough", "Controls": "controls", "System": "system"}
const QUICK_AUDIO_TAB := 3
const QUICK_SUBTITLE_TAB := 4
const SOURCES := [["Folder", "folder"], ["Recent", "recent"], ["Favourites", "star_outline"], ["Places", "drive"], ["Network", "network"], ["Discover", "audio"]]
const SORTS := ["Name", "Newest", "Largest"]
const END_ACTIONS := [["stop_end", "Stop at end"], ["repeat", "Repeat"], ["playlist", "Play next"]]
const SOURCE_TITLES := ["", "Recently played", "Favourites", "Places", "Network", "Discover radio & streams"]
const FILTERS := ["All", "2D", "3D", "180°", "360°", "Photos"]
const SEARCH_DELAY := 0.35
const SEARCH_MAX_FOLDERS := 600
const SEARCH_MAX_DEPTH := 8
const SEARCH_MAX_RESULTS := 400
const ACTION_HEIGHT := 56
const GRID_COLUMNS := 5
const GRID_SEPARATION := 14
const SCAN_HINT_DELAY_MSEC := 250
const PLAYLIST_SYNC_LIMIT := 2000
const RECENT_LIMIT := 60
const DRAG_THRESHOLD := 14.0
const FLING_DECAY := 5.0
const FLING_MIN := 30.0
const PRIORITIZE_DELAY := 0.25
const MAX_CRUMBS := 4
const CHEAT_SHEET := [
	["Trigger", "Click the menu"],
	["A / X", "Play / pause, or click when pointing at the menu"],
	["B / Y", "Menu"],
	["Hold stick click 1 s", "Recenter"],
	["Tap stick click (music)", "Next music scene"],
	["Grip + A / X", "Favourite what is playing"],
	["Stick ◀ ▶", "Seek 10 s, hold to speed up"],
	["Trigger + stick ◀ ▶", "Seek 1 min"],
	["Grip + stick ◀ ▶", "Seek 5 min"],
	["Grip + trigger + ◀ ▶", "Previous / next video"],
	["Stick ▲ ▼", "Volume, zoom on a photo, or scroll the menu"],
	["Grip + ▲ ▼", "Screen size on flat video, zoom on 3D"],
	["Grip + ▲ in Library", "Go up one folder"],
	["Grip + move", "Pan a flat photo, or drag the picture"],
	["Grip + trigger + move", "Free rotate video, twist to roll"],
	["Grip + trigger + A / X", "Level the picture"],
	["Release near level", "Snaps flat"],
	["Grip on the menu", "Move the menu"],
	["Trigger drag on the library", "Scroll"],
	["Esc", "Library, or close the menu"],
	["Tab", "Move through the menu (Shift reverses)"],
	["Ctrl + Tab", "Next menu page"],
	["Arrows / Enter", "Pick in the menu, Backspace goes up"],
	["Ctrl + F", "Search the library"],
	["Space", "Play / pause"],
	["◀ ▶", "Seek 10 s, or previous / next photo; hold to repeat"],
	["Shift + ◀ ▶", "Seek 1 min, holding runs twice as fast"],
	["Ctrl + ◀ ▶", "Pan a flat photo, or turn video 90°"],
	["Ctrl + ▲", "Favourite"],
	["Ctrl + ▼", "Reset photo pan, or level the picture"],
	["▲ ▼", "Volume"],
	["N / P", "Next / previous file"],
	["0 – 9", "Jump to 0 – 90 %"],
	["Home / End", "Start / end"],
	["[ ]", "Speed"],
	["- =", "Zoom"],
	[", .", "3D depth"],
	["; '", "Brightness"],
	["Backspace", "Reset speed and zoom"],
	["F / V / A", "Format / subtitles / audio track, Shift reverses"],
	["B / C", "Bookmark / next chapter"],
	["L", "A–B loop, Shift clears"],
	["M / S / R", "Mute / shuffle / recenter"],
	["F11", "Fullscreen, also Alt + Enter"],
	["Mouse: click", "Play / pause"],
	["Mouse: double click", "Fullscreen"],
	["Mouse: right click", "Show / hide the menu"],
	["Mouse: click outside the menu", "Close the menu"],
	["Mouse: wheel", "Volume"],
	["Mouse: move", "Show progress, click or drag the bar to seek"],
	["Mouse: drag", "Pan a flat photo, or look around in 180° / 360°"],
	["Ctrl + wheel", "Zoom in 180° / 360°"],
	["F1", "This page"],
]
const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const LibraryScanner := preload("res://scripts/library_scanner.gd")
const DiscImage := preload("res://scripts/disc_image.gd")
const VirtualGrid := preload("res://scripts/virtual_grid.gd")
const Shuffle := preload("res://scripts/shuffle.gd")
const MediaCard := preload("res://scripts/media_card.gd")
const QuickPanel := preload("res://scripts/quick_panel.gd")
const Rows := preload("res://scripts/rows.gd")
const Languages := preload("res://scripts/languages.gd")
const Keyboard := preload("res://scripts/keyboard.gd")
const Network := preload("res://scripts/network.gd")
const SeekPreviews := preload("res://scripts/seek_previews.gd")
const SeekMarks := preload("res://scripts/seek_marks.gd")
const WebVideo := preload("res://scripts/web_video.gd")
const RemoteControl := preload("res://scripts/remote_control.gd")
const RAIL_COLLAPSED := 64.0
const RAIL_EXPANDED := 280.0
const RAIL_OPEN_DELAY := 0.06
const RAIL_CLOSE_DELAY := 0.25
const RAIL_EASE := 30.0
const SCROLL_RESERVE := 32.0
const SCROLL_THIN := 8.0
const SCROLL_WIDE := 26.0
const SCROLL_INSET := 3.0
const SCROLL_NEAR := 160.0
const SCROLL_EASE := 20.0
const SCROLL_STYLES := ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]
const NAV_KEYS := [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]

@export var player: VPXPlayer

var directory := Settings.last_directory
var directory_fallbacks := true
var paths_job: Node
var paths_serial := 0
var saved_path_info := {}
var places_cache: Array = []
var playlist: PackedStringArray = []
var music_playlist: PackedStringArray = []
var radio_queue := PackedStringArray()
var radio_queue_stations := {}
var radio_queue_active := false
var listing: PackedStringArray = []
var cards := {}
var item_meta := {}
var pending_folders := PackedStringArray()
var pending_media := PackedStringArray()
var folder_covers := {}
var cover_owner := {}
var nav_group := ButtonGroup.new()
var speed_button: OptionButton
const SPEEDS := [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
var preset_group := ButtonGroup.new()
var source_group := ButtonGroup.new()
var view_group := ButtonGroup.new()
var nav_buttons: Array[Button] = []
var nav_targets: Array[String] = []
var page_buttons := {}
var page_tabs: PanelContainer
var settings_heading: Label
var preset_buttons: Array[Button] = []
var source_buttons: Array[Button] = []
var folder_grid: VirtualGrid
var media_grid: VirtualGrid
var scanner: LibraryScanner
var scan_started_msec := -1
var scan_hint: Label
var updating_slider := false
var seeking := false
var seek_edit_serial := 0
var seek_media_serial := -1
var stats_timer := STATS_INTERVAL
var clock_timer := 0.0
var shuffle := Shuffle.new()
var music_shuffle := Shuffle.new()
var playlist_index := {}
var music_playlist_index := {}
var pending_entry := ""
var pending_direction := 1
var skipped_entries := {}
var prefetch_sets := {}
var shuffle_on := Settings.shuffle
var was_active := false
var drag_armed := false
var drag_active := false
var drag_origin := Vector2.ZERO
var drag_scroll_start := 0.0
var drag_last_y := 0.0
var drag_last_msec := 0
var drag_velocity := 0.0
var fling := 0.0
var fling_position := 0.0
var prioritize_timer := -1.0
var now_path := ""
var quick: QuickPanel
var spirit_level: SpiritLevel
var spirit_level_section: VBoxContainer
var flat_view_button: Button
var keyboard: Keyboard
var settings_search: Control
var network: Network
var discovery: Control
var filter_group := ButtonGroup.new()
var filter_buttons: Array[Button] = []
var search_button: Button
var query_chip: Button
var search_timer := -1.0
var query_before_edit := ""
var keyboard_purpose := ""
var dlna_stack: Array[Dictionary] = []
var network_status := ""
var disc_status := ""
var archive_path := ""
var archive_members := PackedStringArray()
var sacd_path := ""
var sacd_info_cache := {}
var sacd_serial := 0
var disc_job: DiscImage
var sacd_popup: PopupMenu
var archive_popup: PopupMenu
var removing_servers := false
var network_titles := {}
var previews: SeekPreviews
var marks: SeekMarks
var preview_rect: TextureRect
var preview_time := -1.0
var photo_note_for := ""
var photo_note := ""
var marks_length := -1.0
var rail_slot: Control
var rail_scroll: ScrollContainer
var rail_overlay: Panel
var rail_width := RAIL_COLLAPSED
var rail_expanded_width := RAIL_EXPANDED
var rail_open := false
var rail_hover_time := 0.0
var rail_away_time := 0.0
var rail_suppressed := false
var pointer_position := Vector2(-1, -1)
var pointer_held := false
var scroll_widths := {}
var web: WebVideo
var remote: RemoteControl
var calibration_rows := {}
var photo_repeat_row: Choice
var photo_pan_section: VBoxContainer
var audio_info_label: Label
var remote_label: Label
var web_label: Label
var web_button: Button
var resolving_path := ""
var recovery: Control
var accessibility_size := Vector2.ZERO
var accessibility_text_size := 0.0
var media_rename: Node
var rename_name: LineEdit
var rename_status: Label
var rename_button: Button
var backup_picker: Control
var forwarded_keys := {}
var refocus := false
var refocus_key := ""

@onready var tabs: VBoxContainer = %Nav
@onready var pages: Container = %PageStack
@onready var page_scroll: ScrollContainer = %PageScroll
@onready var file_scroll: ScrollContainer = %FileScroll
@onready var file_list: VBoxContainer = %FileList
@onready var crumbs: HBoxContainer = %Crumbs
@onready var count_label: Label = %CountLabel
@onready var clock_label: Label = %ClockLabel
@onready var sort_button: OptionButton = %SortButton
@onready var up_button: Button = %UpButton
@onready var preset_grid: GridContainer = %PresetGrid
@onready var fov_row: Stepper = %Fov
@onready var color_swatch: Panel = %ColorSwatch
@onready var key_hue: Stepper = %KeyHue
@onready var key_shade: Stepper = %KeyShade
@onready var favorite_button: Button = %FavoriteButton
@onready var play_button: Button = %PlayButton
@onready var seek_slider: HSlider = %SeekSlider
@onready var elapsed_label: Label = %ElapsedLabel
@onready var total_label: Label = %TotalLabel
@onready var end_time_label: Label = %EndTimeLabel
@onready var mute_button: Button = %MuteButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_label: Label = %VolumeLabel
@onready var shuffle_button: Button = %ShuffleButton
@onready var end_button: Button = %EndButton
@onready var end_label: Label = %EndLabel
@onready var stats_label: Label = %StatsLabel
@onready var info_label: Label = %InfoLabel
@onready var now_title: Label = %NowTitle
@onready var now_thumb: TextureRect = %NowThumb
@onready var format_badge: PanelContainer = %FormatBadge
@onready var format_label: Label = %FormatLabel
@onready var seek_bubble: PanelContainer = %SeekBubble
@onready var bubble_label: Label = %BubbleLabel


func _init() -> void:
	theme = VpxTheme.build()


func _ready() -> void:
	_build_media_page()
	_build_nav()
	_build_quick_panel()
	_build_presets()
	Rows.view_adjust(pages.get_node("Format"))
	_build_calibration()
	_build_picture_extras()
	_build_photo_pan()
	_build_position_reset()
	_build_spirit_level()
	_build_auto_swap_row()
	_build_integrations()
	_build_appearance()
	_build_speed_control()
	_build_settings_backup()
	_build_view_profiles()
	_build_format_help()
	_build_media_rename()
	_build_library_bar()
	_build_filter_row()
	_build_network()
	_build_discovery()
	recovery = preload("res://scripts/playback_recovery.gd").new()
	recovery.ui = self
	recovery.player = player
	add_child(recovery)
	_build_settings_search()
	_build_seek_extras()
	_build_cheat_sheet()
	_decorate()
	_build_rail()
	_build_scroll_bars()
	_connect_controls()
	_sync()
	_update_clock()
	Settings.changed.connect(_sync)
	Settings.changed.connect(func() -> void:
		if not Settings.seek_previews:
			previews.clear()
			preview_rect.texture = null
			preview_rect.visible = false)
	player.opened.connect(_on_opened)
	player.music_metadata_changed.connect(_refresh_now_playing)
	player.music_changed.connect(func() -> void:
		_refresh_now_playing()
		_highlight_current()
		_refresh_marks()
		_refresh_audio_info()
		if not player.music_path.is_empty():
			_request_playlist(player.music_path))
	player.music_ended.connect(_on_music_ended)
	MediaInfo.updated.connect(_on_media_updated)
	file_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: prioritize_timer = PRIORITIZE_DELAY)
	sacd_popup = PopupMenu.new()
	sacd_popup.id_pressed.connect(_on_sacd_area_selected)
	add_child(sacd_popup)
	archive_popup = PopupMenu.new()
	archive_popup.id_pressed.connect(_on_archive_member_selected)
	add_child(archive_popup)
	scanner = LibraryScanner.new(VIDEO_EXTENSIONS + VPXPlayer.AUDIO_EXTENSIONS + DISC_EXTENSIONS + ArchiveFiles.ARCHIVE_EXTENSIONS)
	scanner.finished.connect(_on_scan_finished)
	scanner.cover_found.connect(_on_cover_found)
	add_child(scanner)
	refresh_directory()
	_refresh_now_playing()
	page_scroll.follow_focus = true
	file_scroll.follow_focus = true
	_make_focusable(self)
	get_tree().node_added.connect(func(node: Node) -> void: _make_focusable.call_deferred(node, false))


func _build_nav() -> void:
	var body := page_scroll.get_parent()
	var content := VBoxContainer.new()
	content.name = "PageContent"
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	body.add_child(content)
	body.move_child(content, page_scroll.get_index())
	page_tabs = PanelContainer.new()
	page_tabs.theme_type_variation = &"Segment"
	content.add_child(page_tabs)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	page_tabs.add_child(tab_row)
	page_scroll.reparent(content, false)
	page_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	for i in NAV_SECTIONS.size():
		var section: Array = NAV_SECTIONS[i]
		nav_targets.append(section[0])
		if NAV_TITLES[i] == "Settings":
			settings_heading = Label.new()
			settings_heading.text = "SETTINGS"
			settings_heading.theme_type_variation = &"NavSection"
			settings_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			settings_heading.clip_text = true
			tabs.add_child(settings_heading)
		var button := Button.new()
		button.text = NAV_TITLES[i]
		button.icon = VpxTheme.icon(NAV_ICONS[i])
		button.tooltip_text = NAV_TITLES[i]
		button.theme_type_variation = &"NavItem"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = nav_group
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size.y = NAV_HEIGHT
		button.toggled.connect(func(on: bool) -> void:
			if on:
				show_page(pages.get_node(NodePath(nav_targets[i]))))
		tabs.add_child(button)
		nav_buttons.append(button)
		var group := ButtonGroup.new()
		for page_name: String in section:
			var page := pages.get_node(NodePath(page_name))
			var title: String = PAGE_TITLES.get(page_name, page_name)
			page.set_meta("settings_path", "%s › %s" % [NAV_TITLES[i], title] if section.size() > 1 else title)
			if section.size() == 1:
				continue
			var tab := Button.new()
			tab.text = title
			tab.icon = VpxTheme.icon(PAGE_ICONS[page_name], 24)
			tab.theme_type_variation = &"PageTab"
			tab.toggle_mode = true
			tab.button_group = group
			tab.custom_minimum_size.y = NAV_HEIGHT
			tab.size_flags_horizontal = SIZE_EXPAND_FILL
			tab.toggled.connect(func(on: bool) -> void:
				if on:
					show_page(page))
			tab_row.add_child(tab)
			page_buttons[page_name] = tab
	show_page(pages.get_child(0))


func _build_rail() -> void:
	var rail: VBoxContainer = $Sheet/Margin/Layout/Body/Rail
	var body := rail.get_parent()
	rail_slot = Control.new()
	rail_slot.custom_minimum_size.x = RAIL_COLLAPSED
	rail_slot.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(rail_slot)
	body.move_child(rail_slot, rail.get_index())
	rail_overlay = Panel.new()
	rail_overlay.theme_type_variation = &"RailOverlay"
	rail_overlay.clip_contents = true
	add_child(rail_overlay)
	move_child(rail_overlay, $Sheet.get_index() + 1)
	rail_scroll = ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_scroll.follow_focus = true
	rail_overlay.add_child(rail_scroll)
	rail.reparent(rail_scroll, false)
	rail.size_flags_horizontal = SIZE_EXPAND_FILL
	rail.size_flags_vertical = SIZE_EXPAND_FILL
	rail.custom_minimum_size.x = 0
	rail.position = Vector2.ZERO
	var brand: HBoxContainer = rail.get_node("Brand")
	brand.alignment = BoxContainer.ALIGNMENT_BEGIN
	brand.add_theme_constant_override("separation", 0)
	%Logo.custom_minimum_size.x = RAIL_COLLAPSED
	brand.get_node("BrandName").clip_text = true
	brand.get_node("BrandName").size_flags_horizontal = SIZE_EXPAND_FILL
	for button in nav_buttons + [%ModeButton, %CloseButton, %QuitButton]:
		button.clip_text = true
		button.pressed.connect(_collapse_rail)
	var search: Button = tabs.get_node("SettingsSearch")
	search.clip_text = true
	search.pressed.connect(_collapse_rail)
	search.theme_changed.connect(_fit_rail_width.call_deferred)
	rail_slot.custom_minimum_size.y = 0
	_fit_rail_width()
	_layout_rail()


func _fit_rail_width() -> void:
	rail_expanded_width = RAIL_EXPANDED
	for button: Button in nav_buttons + [tabs.get_node("SettingsSearch"), %ModeButton, %CloseButton, %QuitButton]:
		var width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		width += button.get_theme_stylebox("normal").get_minimum_size().x
		if button.icon != null:
			var icon_width := float(button.icon.get_width())
			var max_width := button.get_theme_constant("icon_max_width")
			if max_width > 0:
				icon_width = minf(icon_width, max_width)
			width += icon_width + button.get_theme_constant("h_separation")
		rail_expanded_width = maxf(rail_expanded_width, ceilf(width) + rail_scroll.get_v_scroll_bar().get_combined_minimum_size().x)


func set_display_mode(desktop: bool, switching := false) -> void:
	%ModeButton.text = "Switching…" if switching else "Enter VR" if desktop else "Exit VR"
	%ModeButton.icon = VpxTheme.icon("format" if desktop else "screen")
	%ModeButton.tooltip_text = "Restart in VR and restore playback" if desktop else "Restart in desktop mode and restore playback"
	%ModeButton.disabled = switching


func _collapse_rail() -> void:
	rail_open = false
	rail_suppressed = true
	rail_hover_time = 0.0


func _update_rail(delta: float) -> void:
	rail_overlay.visible = $Sheet.visible
	var hovering := rail_overlay.visible and Rect2(rail_overlay.global_position, Vector2(rail_width, rail_overlay.size.y)).has_point(pointer_position)
	if not hovering:
		rail_suppressed = false
	if hovering and not rail_suppressed:
		rail_away_time = 0.0
		rail_hover_time += delta
		if rail_hover_time >= RAIL_OPEN_DELAY:
			rail_open = true
	else:
		rail_hover_time = 0.0
		rail_away_time += delta
		if rail_away_time >= RAIL_CLOSE_DELAY:
			rail_open = false
	var target := rail_expanded_width if rail_open else RAIL_COLLAPSED
	rail_width = lerpf(rail_width, target, 1.0 - exp(-RAIL_EASE * delta))
	if absf(rail_width - target) < 0.5:
		rail_width = target
	_layout_rail()


func _layout_rail() -> void:
	rail_overlay.global_position = rail_slot.global_position
	rail_overlay.size = Vector2(rail_width, rail_slot.size.y)
	rail_scroll.size = rail_overlay.size
	var rail: Control = rail_scroll.get_child(0)
	rail.custom_minimum_size.x = maxf(rail_width - rail_scroll.get_v_scroll_bar().size.x, 0.0)
	settings_heading.modulate.a = clampf((rail_width - 140.0) / 80.0, 0.0, 1.0)


func _build_scroll_bars() -> void:
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", int(SCROLL_RESERVE))
	file_scroll.add_child(gutter)
	file_list.get_parent().reparent(gutter, false)
	for scroll: ScrollContainer in [page_scroll, file_scroll]:
		var bar := scroll.get_v_scroll_bar()
		bar.custom_minimum_size.x = SCROLL_RESERVE
		for style in SCROLL_STYLES:
			var box: StyleBoxFlat = bar.get_theme_stylebox(style).duplicate()
			box.content_margin_left = 0
			box.content_margin_right = 0
			bar.add_theme_stylebox_override(style, box)
		scroll_widths[bar] = -1.0
		_style_scroll_bar(bar, SCROLL_THIN)


func _update_scroll_bars(delta: float) -> void:
	for bar: VScrollBar in scroll_widths:
		if not bar.is_visible_in_tree():
			continue
		var rect := bar.get_global_rect()
		var closeness := 0.0
		if pointer_position.y >= rect.position.y and pointer_position.y <= rect.end.y:
			closeness = 1.0 - clampf((rect.position.x - pointer_position.x) / SCROLL_NEAR, 0.0, 1.0)
		if pointer_held and scroll_widths[bar] > (SCROLL_THIN + SCROLL_WIDE) * 0.5:
			closeness = 1.0
		var target := lerpf(SCROLL_THIN, SCROLL_WIDE, closeness)
		var width := lerpf(scroll_widths[bar], target, 1.0 - exp(-SCROLL_EASE * delta))
		if absf(width - target) < 0.1:
			width = target
		_style_scroll_bar(bar, width)


func _style_scroll_bar(bar: VScrollBar, width: float) -> void:
	if is_equal_approx(scroll_widths[bar], width):
		return
	scroll_widths[bar] = width
	for style in SCROLL_STYLES:
		var box := bar.get_theme_stylebox(style) as StyleBoxFlat
		box.expand_margin_left = -(SCROLL_RESERVE - SCROLL_INSET - width)
		box.expand_margin_right = -SCROLL_INSET
		box.set_corner_radius_all(int(width * 0.5))


func _build_media_page() -> void:
	var page := VBoxContainer.new()
	page.name = MEDIA_PAGE
	page.add_theme_constant_override("separation", 12)
	pages.add_child(page)
	pages.move_child(page, pages.get_node("Picture").get_index() + 1)
	var current := Rows.section(page, "This video")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	current.add_child(buttons)
	for entry in [["Audio track", "audio", QUICK_AUDIO_TAB], ["Subtitle track", "subtitles", QUICK_SUBTITLE_TAB]]:
		var button := Button.new()
		button.text = entry[0]
		button.icon = VpxTheme.icon(entry[1], 26)
		button.focus_mode = FOCUS_NONE
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = PRESET_HEIGHT
		var tab: int = entry[2]
		button.pressed.connect(func() -> void: open_quick(tab))
		buttons.add_child(button)
	Rows.playback(page)
	Rows.hint(page, "Sleep timer shortest time is 15 minutes, and it pauses the sound too. A black picture while the sound keeps playing is not this timer.")
	var audio := Rows.section(page, "Audio")
	Rows.dropdown(audio, "Preferred audio language", &"audio_language", PackedStringArray(["File default"]) + Languages.names())
	Rows.toggle(audio, "Spatial audio (surround and 360 sound follow your head)", &"spatial_audio")
	Rows.toggle(audio, "Dialogue boost", &"dialogue_boost")
	Rows.choice(audio, "Loudness", &"audio_filter", PackedStringArray(["Off", "Even out", "Night mode"]))
	audio_info_label = Rows.hint(audio, "")
	var visuals := Rows.section(page, "Immersive sound visuals")
	var scene_picker := preload("res://scripts/visualizer_picker.gd").new()
	scene_picker.name = "SoundVisualizer"
	scene_picker.setting = &"visualizer_preset"
	scene_picker.options = PackedStringArray(Settings.VISUALIZER_PRESETS)
	scene_picker.scene_selected.connect(func() -> void: player.enter_immersive_music())
	visuals.add_child(scene_picker)
	var subtitles := Rows.section(page, "Subtitles")
	Rows.choice(subtitles, "Show subtitles", &"subtitle_auto", PackedStringArray(["Forced only", "Foreign audio", "Always"]))
	Rows.dropdown(subtitles, "Subtitle language", &"subtitle_language", Languages.names())
	Rows.stepper(subtitles, "Size", &"subtitle_size", 0.5, 2.5, 0.1, {"scale": 100.0, "suffix": "%"})
	var save_size_row := HBoxContainer.new()
	save_size_row.add_theme_constant_override("separation", 10)
	subtitles.add_child(save_size_row)
	var save_size_label := Label.new()
	save_size_label.text = "Save size for this format"
	save_size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_size_row.add_child(save_size_label)
	var save_size_button := _action_button("Save", "check")
	save_size_button.pressed.connect(_save_subtitle_size_for_format)
	save_size_row.add_child(save_size_button)
	Rows.stepper(subtitles, "Position", &"subtitle_offset", -0.4, 0.5, 0.02, {"scale": 100.0, "suffix": "%"})
	Rows.choice(subtitles, "Colour", &"subtitle_color", PackedStringArray(["White", "Yellow", "Grey"]))
	Rows.toggle(subtitles, "Background box", &"subtitle_box")
	Rows.stepper(subtitles, "Distance in 180 / 360", &"subtitle_distance", 1.0, 8.0, 0.25, {"decimals": 2, "suffix": " m"})
	Rows.hint(subtitles, "Set Size, then choose Save size for this format. Size restores separately for each projection and 2D / 3D layout.")
	Rows.hint(page, "Subtitle files (.srt .ass .vtt .sup ...) next to the video or in a Subs folder are found automatically. Track choices and delays are remembered per video.")


func _save_subtitle_size_for_format() -> void:
	var sizes: Dictionary = Settings.subtitle_size_by_format.duplicate()
	sizes["%d:%d" % [Settings.projection, Settings.stereo]] = Settings.subtitle_size
	Settings.apply("subtitle_size_by_format", sizes)


func _section_after(page: Control, anchor: Control, title: String) -> VBoxContainer:
	var rows := Rows.section(page, title)
	var group := rows.get_parent() as Control
	var label := page.get_child(group.get_index() - 1)
	page.move_child(label, anchor.get_index() + 1)
	page.move_child(group, label.get_index() + 1)
	return rows


func _build_calibration() -> void:
	var page := pages.get_node("Format") as Control
	var rows := _section_after(page, page.get_node("LayoutGroup"), "Lens & crop")
	calibration_rows["equirect_fov"] = Rows.stepper(rows, "180° video field of view", &"equirect_fov", 120.0, 270.0, 5.0, {"suffix": "°", "resettable": true})
	calibration_rows["lens_k1"] = Rows.stepper(rows, "Fisheye lens curve", &"lens_k1", -0.5, 0.5, 0.01, {"decimals": 2, "resettable": true})
	calibration_rows["lens_k2"] = Rows.stepper(rows, "Fisheye lens edge", &"lens_k2", -0.5, 0.5, 0.01, {"decimals": 2, "resettable": true})
	calibration_rows["eye_roll"] = Rows.stepper(rows, "Eye tilt (fix rotated 3D)", &"eye_roll", -3.0, 3.0, 0.05, {"fast_step": 0.25, "decimals": 2, "suffix": "°", "resettable": true})
	calibration_rows["crop_top"] = Rows.stepper(rows, "Crop top", &"crop_top", 0.0, 0.45, 0.005, {"fast_step": 0.02, "scale": 100.0, "decimals": 1, "suffix": "%", "resettable": true})
	calibration_rows["crop_bottom"] = Rows.stepper(rows, "Crop bottom", &"crop_bottom", 0.0, 0.45, 0.005, {"fast_step": 0.02, "scale": 100.0, "decimals": 1, "suffix": "%", "resettable": true})
	calibration_rows["crop_left"] = Rows.stepper(rows, "Crop left", &"crop_left", 0.0, 0.45, 0.005, {"fast_step": 0.02, "scale": 100.0, "decimals": 1, "suffix": "%", "resettable": true})
	calibration_rows["crop_right"] = Rows.stepper(rows, "Crop right", &"crop_right", 0.0, 0.45, 0.005, {"fast_step": 0.02, "scale": 100.0, "decimals": 1, "suffix": "%", "resettable": true})
	Rows.toggle(rows, "Crop black bars automatically (flat videos)", &"auto_crop")
	var reset := Button.new()
	reset.text = "Reset lens & crop"
	reset.icon = VpxTheme.icon("reset", 22)
	reset.focus_mode = FOCUS_NONE
	reset.pressed.connect(func() -> void:
		player.clear_auto_crop()
		Settings.reset(PackedStringArray(Settings.CALIBRATION)))
	rows.add_child(reset)
	Rows.hint(rows, "Saved for this video. Field of view is for 180° videos filmed wider or narrower than 180°. Lens curve / edge straighten fisheye lenses. Eye tilt fixes 3D where one eye is rotated.")


func _build_picture_extras() -> void:
	var flat_rows := pages.get_node("Picture/ScreenSection/ScreenGroup/Rows") as Control
	photo_repeat_row = Rows.choice(flat_rows, "Image view", &"flat_image_repeat", PackedStringArray(["Single", "Repeat 3 × 3", "Repeat 5 × 5"]))
	var rows := pages.get_node("Picture/QualityGroup/Rows") as Control
	Rows.choice(rows, "Smooth banding", &"deband", PackedStringArray(["Off", "Low", "Medium", "High"]))
	Rows.toggle(rows, "Dither (hides colour steps)", &"dither")
	Rows.toggle(rows, "Sharper video: compositor layer (headset)", &"compositor_layer")


func _build_photo_pan() -> void:
	var page := pages.get_node("Angles") as Control
	photo_pan_section = VBoxContainer.new()
	page.add_child(photo_pan_section)
	page.move_child(photo_pan_section, page.get_node("AnglesFooter").get_index())
	var rows := Rows.section(photo_pan_section, "Flat picture pan")
	Rows.toggle(rows, "Pan flat videos with grip / mouse", &"flat_video_pan")
	Rows.stepper(rows, "Horizontal", &"photo_pan_x", -0.5, 0.5, 0.01, {"fast_step": 0.05, "scale": 100.0, "suffix": "%", "resettable": true})
	Rows.stepper(rows, "Vertical", &"photo_pan_y", -0.5, 0.5, 0.01, {"fast_step": 0.05, "scale": 100.0, "suffix": "%", "resettable": true})
	Rows.hint(rows, "Grip and drag to pan flat photos. Enable video pan above for flat videos. Mouse drag works on desktop.")


func _build_auto_swap_row() -> void:
	var layout := pages.get_node("Format/LayoutGroup/Rows") as Control
	var auto_swap := Rows.toggle(layout, "Swap eyes automatically when 180° 3D is upside down", &"auto_swap_eyes")
	layout.move_child(auto_swap, layout.get_node("SwapEyes").get_index() + 1)


func _build_appearance() -> void:
	var page := pages.get_node("System") as Control
	var rows := _section_after(page, page.get_node("MenuGroup"), "Appearance")
	var row: SettingRow = preload("res://scripts/accent_choice.gd").new()
	row.title = "Highlight colour"
	row.setting = &"accent_color"
	rows.add_child(row)
	var custom: SettingRow = preload("res://scripts/accent_custom.gd").new()
	custom.title = "Custom colour"
	custom.setting = &"accent_color"
	rows.add_child(custom)
	row.custom_row = custom
	custom.visible = row.custom_button.button_pressed
	Rows.hint(rows, "Colour of buttons, sliders, progress bars and the controller laser. Saved with your viewing profile.")
	Rows.stepper(rows, "UI size", &"ui_size", 0.8, 1.25, 0.05, {"scale": 100.0, "suffix": "%", "resettable": true})
	Rows.stepper(rows, "Text size", &"text_size", 1.0, 1.5, 0.1, {"scale": 100.0, "suffix": "%", "resettable": true})
	Rows.hint(rows, "UI size enlarges controls on desktop and the menu in VR. Text size adjusts interface labels independently. Both are saved globally; subtitles keep their own size.")


func _build_integrations() -> void:
	var page := pages.get_node("System") as Control
	var rows := _section_after(page, page.get_node("PlaybackGroup"), "Apps & web")
	Rows.toggle(rows, "Remote control API (DeoVR compatible, port %d)" % Settings.REMOTE_PORT, &"remote_control")
	remote_label = Rows.hint(rows, "")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	rows.add_child(line)
	web_label = Label.new()
	web_label.size_flags_horizontal = SIZE_EXPAND_FILL
	web_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(web_label)
	web_button = _action_button("Install / update web tools", "download")
	web_button.pressed.connect(_install_web_tool)
	line.add_child(web_button)
	remote = RemoteControl.new()
	remote.player = player
	remote.open_path = open_media
	remote.opening_path = func() -> String:
		if not resolving_path.is_empty():
			return resolving_path
		return str(player.load_state.get("path", "")) if player.load_state.get("status") == "opening" else ""
	add_child(remote)
	remote.clients_changed.connect(func(_count: int) -> void: _refresh_integrations())


func _refresh_integrations() -> void:
	if remote_label != null:
		if not Settings.remote_control:
			remote_label.text = "Lets MultiFunPlayer, XTPlayer, ScriptPlayer or a phone remote follow and control playback."
		elif not remote.error.is_empty():
			remote_label.text = remote.error
		else:
			remote_label.text = "Listening on port %d · %d app(s) connected" % [Settings.REMOTE_PORT, remote.client_count()]
	if web_label != null and web != null:
		var state := "found" if web.available() else ("downloading…" if web.is_busy() else "not installed")
		web_label.text = "Web video links (YouTube, Vimeo …): yt-dlp %s%s" % [state, "\n" + web.install_message if not web.install_message.is_empty() else ""]
		web_button.visible = not web.is_busy()
		if web.available() and not web.youtube_ready():
			web_label.text += "\nYouTube also needs a JavaScript runtime. Install / update web tools to add it."


func _install_web_tool() -> void:
	web.install()
	_refresh_integrations()


func opening_media() -> bool:
	return player.load_state.get("status") == "opening" or not resolving_path.is_empty() or recovery.status == "opening"


func open_media(path: String, extra := {}) -> void:
	if radio_queue_active and path not in radio_queue and not PanoramaFiles.is_image(path):
		_clear_radio_queue()
	cancel_disc_open()
	recovery.mount_source = ""
	network.cancel_mount()
	player.cancel_open()
	resolving_path = ""
	if web != null:
		web.cancel()
	if Network.scheme(path) in Network.DIRECT_SCHEMES:
		Library.remember_link(path)
	if path.get_extension().to_lower() in ArchiveFiles.ARCHIVE_EXTENSIONS:
		_open_archive(path)
		return
	if path.get_extension().to_lower() == "iso":
		await _open_disc(path, extra)
		return
	var station: Variant = radio_queue_stations.get(path, Library.get_pref(path, "radio_station", {}))
	if station is Dictionary and not station.is_empty():
		discovery.Directory.remember(station)
		extra = extra.duplicate()
		extra.merge({"stream": path, "audio_only": true, "title": station.get("name", "")}, false)
	if extra.has("stream") or not WebVideo.needs_resolve(path):
		await player.open(path, extra)
		return
	recovery.begin(path, extra)
	resolving_path = path
	var request_generation: int = recovery.generation
	if web != null:
		recovery.stage("Checking stream…")
		var source: Dictionary = await web.probe_stream(path)
		if resolving_path != path or recovery.generation != request_generation:
			return
		if source.get("direct", false):
			resolving_path = ""
			var options := extra.duplicate()
			options["audio_only"] = source.get("audio_only", false)
			if not str(source.get("title", "")).is_empty():
				options["title"] = source["title"]
				Library.set_pref(path, "title", source["title"])
			await player.open(path, options)
			return
	if web == null or not web.available():
		resolving_path = ""
		recovery.fail("Web video tools are missing. Install them in Apps & web, then retry.", "The web-video helper is not installed.", "tools")
		return
	recovery.stage("Getting the video link…")
	if Settings.library_source == Settings.LibrarySource.NETWORK:
		refresh_directory()
	web.resolve(path, func(result: Dictionary) -> void:
		if resolving_path != path or recovery.generation != request_generation:
			return
		resolving_path = ""
		network_status = ""
		if not result["ok"]:
			network_status = "Could not get video: %s" % result.get("error", "")
			if Settings.library_source == Settings.LibrarySource.NETWORK:
				refresh_directory()
			recovery.fail("Could not get this video. Check the link and connection, then retry.", str(result.get("error", "")), "connection")
			return
		if not str(result["title"]).is_empty():
			Library.set_pref(path, "title", result["title"])
		var options := extra.duplicate()
		options["stream"] = result["stream"]
		options["audio"] = result["audio"]
		options["headers"] = result["headers"]
		options["title"] = result["title"]
		options["start_time"] = extra.get("start_time", result.get("start_time", 0.0))
		await player.open(path, options))


func _build_quick_panel() -> void:
	quick = QuickPanel.new()
	quick.player = player
	quick.visible = false
	add_child(quick)
	move_child(quick, $Sheet.get_index() + 1)
	quick.bookmark_name_requested.connect(func(text: String) -> void:
		keyboard_purpose = "bookmark_name"
		keyboard.open("Bookmark name", text, "Optional name · up to 64 characters"))
	quick.menu_requested.connect(show_main)
	quick.recenter_requested.connect(recenter_requested.emit)
	quick.reset_position_requested.connect(reset_position_requested.emit)
	quick.level_requested.connect(level_requested.emit)
	quick.close_requested.connect(func() -> void:
		show_main()
		close_requested.emit())


func open_quick(tab := -1) -> void:
	$Sheet.visible = false
	seek_bubble.visible = false
	quick.visible = true
	if tab >= 0:
		quick.show_tab(tab)


func show_main() -> void:
	quick.close_picker()
	quick.visible = false
	$Sheet.visible = true


func show_page(page: Node) -> void:
	page_scroll.scroll_vertical = 0
	pages.add_theme_constant_override("margin_right", 0 if page == %Library else int(SCROLL_RESERVE))
	for child in pages.get_children():
		child.visible = child == page
	for i in NAV_SECTIONS.size():
		var selected: bool = String(page.name) in NAV_SECTIONS[i]
		nav_buttons[i].set_pressed_no_signal(selected)
		if selected:
			nav_targets[i] = String(page.name)
			page_tabs.visible = NAV_SECTIONS[i].size() > 1
		for page_name: String in NAV_SECTIONS[i]:
			if page_buttons.has(page_name):
				var button: Button = page_buttons[page_name]
				button.visible = selected
				button.set_pressed_no_signal(page_name == String(page.name))
	if page == %System:
		_update_stats()


func _build_presets() -> void:
	for i in Settings.FORMAT_PRESETS.size():
		var button := Button.new()
		button.text = Settings.FORMAT_PRESETS[i][0]
		button.toggle_mode = true
		button.button_group = preset_group
		button.focus_mode = FOCUS_NONE
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = PRESET_HEIGHT
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_on_preset_selected(i))
		preset_grid.add_child(button)
		preset_buttons.append(button)


func _build_library_bar() -> void:
	for i in SOURCES.size():
		var button := Button.new()
		button.text = SOURCES[i][0]
		button.icon = VpxTheme.icon(SOURCES[i][1], 24)
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_group = source_group
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size.y = 48
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_select_source(i))
		%SourceRow.add_child(button)
		source_buttons.append(button)
	sort_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for i in SORTS.size():
		sort_button.add_icon_item(VpxTheme.icon("sort", 22), SORTS[i])
	sort_button.item_selected.connect(func(index: int) -> void:
		Settings.apply("library_sort", index)
		refresh_directory()
		if not player.current_path.is_empty():
			_request_playlist(player.current_path))
	for pair in [[%GridButton, "grid", Settings.LibraryView.GRID], [%ListButton, "list", Settings.LibraryView.LIST]]:
		var button: Button = pair[0]
		button.icon = VpxTheme.icon(pair[1], 26)
		button.button_group = view_group
		var view: int = pair[2]
		button.toggled.connect(func(on: bool) -> void:
			if on and Settings.library_view != view:
				Settings.apply("library_view", view)
				refresh_directory())
	up_button.icon = VpxTheme.icon("up", 26)


func _build_filter_row() -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	var library: Control = pages.get_node("Library")
	library.add_child(row)
	library.move_child(row, library.get_node("LibraryBar").get_index() + 1)
	search_button = _action_button("Search", "search")
	search_button.pressed.connect(_open_search)
	row.add_child(search_button)
	flat_view_button = _action_button("Flat view", "folder")
	flat_view_button.toggle_mode = true
	flat_view_button.tooltip_text = "Show media from this folder and all subfolders"
	flat_view_button.toggled.connect(func(on: bool) -> void:
		Settings.apply("library_flat_view", on)
		refresh_directory())
	row.add_child(flat_view_button)
	query_chip = _action_button("", "close")
	query_chip.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	query_chip.pressed.connect(func() -> void: _set_query(""))
	row.add_child(query_chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	var chips := PanelContainer.new()
	chips.theme_type_variation = &"Segment"
	row.add_child(chips)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 4)
	chips.add_child(chip_row)
	for i in FILTERS.size():
		var button := Button.new()
		button.text = FILTERS[i]
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_group = filter_group
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size = Vector2(76, 48)
		button.toggled.connect(func(on: bool) -> void:
			if on and Settings.library_filter != i:
				Settings.apply("library_filter", i)
				refresh_directory())
		chip_row.add_child(button)
		filter_buttons.append(button)


func _action_button(text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = VpxTheme.icon(icon_name, 24)
	button.theme_type_variation = &"Chip"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 48
	return button


func _build_network() -> void:
	network = Network.new()
	add_child(network)
	web = WebVideo.new()
	add_child(web)
	web.install_finished.connect(func(ok: bool, message: String) -> void:
		network_status = message if not ok else ""
		_refresh_integrations()
		if Settings.library_source == Settings.LibrarySource.NETWORK:
			refresh_directory())
	network.servers_changed.connect(func() -> void:
		if Settings.library_source == Settings.LibrarySource.NETWORK and dlna_stack.is_empty():
			refresh_directory())
	network.mounted.connect(func(url: String, path: String) -> void:
		if recovery.mount_source != url:
			return
		recovery.mount_source = ""
		network_status = ""
		recovery.complete(false)
		if network.mounted_is_directory:
			open_directory(path)
			return
		open_directory(path.get_base_dir())
		_request_playlist(path)
		open_media(path))
	network.mount_failed.connect(func(url: String, message: String) -> void:
		if recovery.mount_source != url:
			return
		recovery.mount_source = ""
		recovery.fail("Could not connect to this share. Check that its server and drive are available, then retry.", message, "connection")
		network_status = "Could not open %s: %s" % [Network.display_name(Network.strip_password(url)), message]
		if Settings.library_source == Settings.LibrarySource.NETWORK:
			refresh_directory())
	keyboard = Keyboard.new()
	keyboard.z_index = 110
	add_child(keyboard)
	keyboard.edited.connect(func(text: String) -> void:
		if keyboard_purpose == "search":
			Settings.library_query = text
			_refresh_query_chip()
			search_timer = SEARCH_DELAY
		elif keyboard_purpose == "settings_search":
			settings_search.set_query(text))
	keyboard.submitted.connect(_on_keyboard_submitted)
	keyboard.cancelled.connect(func() -> void:
		if keyboard_purpose == "search" and Settings.library_query != query_before_edit:
			_set_query(query_before_edit)
		elif keyboard_purpose == "settings_search":
			settings_search.set_query(query_before_edit)
			settings_search.field.grab_focus())


func _build_discovery() -> void:
	discovery = preload("res://scripts/radio_discovery.gd").new()
	discovery.visible = false
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	file_scroll.remove_child(file_list)
	file_scroll.add_child(content)
	content.add_child(discovery)
	content.add_child(file_list)
	discovery.keyboard_requested.connect(func(text: String) -> void:
		keyboard_purpose = "radio_search"
		keyboard.open("Find a radio station", text, "Station name"))
	discovery.link_requested.connect(_ask_link)
	discovery.results_changed.connect(func() -> void:
		if Settings.library_source == Settings.LibrarySource.DISCOVER:
			var scroll := file_scroll.scroll_vertical if not discovery.directory.stations.is_empty() else 0
			refresh_directory()
			file_scroll.set_deferred("scroll_vertical", scroll))


func _build_settings_search() -> void:
	settings_search = preload("res://scripts/settings_search.gd").new()
	add_child(settings_search)
	settings_search.keyboard_requested.connect(func() -> void:
		keyboard_purpose = "settings_search"
		query_before_edit = settings_search.field.text
		keyboard.open("Search settings", query_before_edit, "Part of a setting or action", true))
	settings_search.selected.connect(func(page: Control, target: Control, heading: Control) -> void:
		show_main()
		show_page(page)
		await get_tree().process_frame
		if target.focus_mode == FOCUS_ALL:
			target.grab_focus()
		else:
			_first_focusable(target)
		page_scroll.scroll_vertical = int(maxf(heading.global_position.y - pages.global_position.y, 0.0)))
	var button := Button.new()
	button.name = "SettingsSearch"
	button.text = "Search settings"
	button.icon = VpxTheme.icon("search")
	button.theme_type_variation = &"NavItem"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = NAV_HEIGHT
	button.tooltip_text = "Search settings (Ctrl + Shift + F)"
	button.pressed.connect(func() -> void: settings_search.open(pages))
	tabs.add_child(button)


func _build_seek_extras() -> void:
	previews = SeekPreviews.new()
	add_child(previews)
	previews.ready_for.connect(func(_path: String) -> void:
		if get_viewport().render_target_update_mode != SubViewport.UPDATE_DISABLED and previews.request_owner == self and seek_bubble.visible and preview_time >= 0.0:
			_show_bubble(preview_time, _slider_x(preview_time)))
	marks = SeekMarks.new()
	seek_slider.add_child(marks)
	player.marks_changed.connect(_refresh_marks)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	seek_bubble.remove_child(bubble_label)
	seek_bubble.add_child(column)
	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(SeekPreviews.FRAME_SIZE)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.mouse_filter = MOUSE_FILTER_IGNORE
	preview_rect.visible = false
	column.add_child(preview_rect)
	column.add_child(bubble_label)


func _refresh_marks() -> void:
	var has_media := player.playback != null
	marks_length = player.get_stream_length() if has_media else 0.0
	marks.show_marks(marks_length, _grabber_half(), player.chapters if has_media else [], player.bookmarks() if has_media else [], Vector2(player.loop_a, player.loop_b))


func _open_search() -> void:
	if Settings.library_source == Settings.LibrarySource.DISCOVER:
		discovery.keyboard_requested.emit(discovery.field.text)
		return
	keyboard_purpose = "search"
	query_before_edit = Settings.library_query
	keyboard.open("Search %s" % _search_scope(), Settings.library_query, "Part of a name", true)


func _search_scope() -> String:
	match Settings.library_source:
		Settings.LibrarySource.FOLDER:
			return "in %s and its subfolders" % (directory.get_file() if directory != "/" else "Computer")
		Settings.LibrarySource.NETWORK:
			return "this network folder"
	return SOURCE_TITLES[Settings.library_source].to_lower()


func _set_query(text: String) -> void:
	Settings.library_query = text
	search_timer = -1.0
	_refresh_query_chip()
	refresh_directory()


func _refresh_query_chip() -> void:
	if query_chip == null:
		return
	query_chip.visible = not Settings.library_query.is_empty()
	query_chip.text = "“%s”" % Settings.library_query


func _on_keyboard_submitted(text: String) -> void:
	match keyboard_purpose:
		"settings_search":
			settings_search.set_query(text)
			settings_search.field.grab_focus()
		"search":
			_set_query(text)
		"bookmark_name":
			quick.set_bookmark_name_text(text)
		"rename_media":
			rename_name.text = text
			_validate_rename_name(text)
		"profile_save":
			Settings.profiles.save_current(text)
			Settings.changed.emit()
		"profile_rename":
			Settings.profiles.rename_current(text)
			Settings.changed.emit()
		"radio_search":
			discovery.set_search(text)
		"link":
			_open_link(text)
		"server":
			_add_server(text)


func _open_link(text: String) -> void:
	var url := _normalized_url(text)
	if url.is_empty():
		return
	_clear_radio_queue()
	if Network.plays_directly(url, VIDEO_EXTENSIONS):
		_set_playlist(PackedStringArray([url]), url)
		open_media(url)
		return
	_connect_share(url)


func _add_server(text: String) -> void:
	var url := _normalized_url(text, true)
	if url.is_empty():
		return
	var servers: Array = Settings.network_servers.duplicate()
	var clean := url.trim_suffix("/")
	for server: Dictionary in servers:
		if server.get("url", "") == clean:
			_connect_share(clean)
			return
	servers.append({"name": Network.display_name(clean), "url": clean})
	Settings.apply("network_servers", servers)
	_connect_share(clean)


func _normalized_url(text: String, share := false) -> String:
	var result := Network.normalize_url(text, share)
	if not result["ok"]:
		_network_feedback(result["error"], false)
		return ""
	return result["url"]


func _connect_share(url: String) -> void:
	cancel_disc_open()
	var waiting := network.is_mounting()
	player.cancel_open()
	resolving_path = ""
	web.cancel()
	recovery.begin(url, {}, "share")
	recovery.mount_source = url
	recovery.stage("Waiting for the previous connection attempt…" if waiting else "Connecting to network share…")
	network_status = "Connecting to %s…" % Network.display_name(Network.strip_password(url))
	network.mount(url)
	if Settings.library_source == Settings.LibrarySource.NETWORK:
		refresh_directory()


func _go_up() -> void:
	if Settings.library_source == Settings.LibrarySource.NETWORK:
		if not dlna_stack.is_empty():
			dlna_stack.pop_back()
			refresh_directory()
		return
	if Settings.library_source == Settings.LibrarySource.FOLDER and not _is_root(directory):
		open_directory(directory.get_base_dir())


func library_navigation_active() -> bool:
	return %Library.is_visible_in_tree() and not quick.visible and not keyboard.visible and not settings_search.visible


func navigate_library_up() -> bool:
	if not library_navigation_active() or up_button.disabled:
		return false
	_go_up()
	return true


func _build_cheat_sheet() -> void:
	for entry in CHEAT_SHEET:
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 6)
		for part in entry[0].split(" + "):
			if keys.get_child_count() > 0:
				var plus := Label.new()
				plus.text = "+"
				plus.theme_type_variation = &"Hint"
				keys.add_child(plus)
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.RAISED, 8, 10, 2))
			var label := Label.new()
			label.text = part
			label.add_theme_font_size_override("font_size", 20)
			chip.add_child(label)
			keys.add_child(chip)
		%CheatSheet.add_child(keys)
		var text := Label.new()
		text.text = entry[1]
		text.theme_type_variation = &"Hint"
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		%CheatSheet.add_child(text)


func _decorate() -> void:
	%Logo.texture = VpxTheme.icon("logo", 46)
	%Logo.modulate = VpxTheme.ACCENT
	%CloseButton.icon = VpxTheme.icon("close")
	%QuitButton.icon = VpxTheme.icon("power")
	%PrevButton.icon = VpxTheme.icon("prev")
	%NextButton.icon = VpxTheme.icon("next")
	%BackButton.icon = VpxTheme.icon("back", 34)
	%ForwardButton.icon = VpxTheme.icon("forward", 34)
	%BackButton.add_theme_constant_override("icon_max_width", 34)
	%ForwardButton.add_theme_constant_override("icon_max_width", 34)
	%PickButton.icon = VpxTheme.icon("pick", 26)
	%TuneButton.icon = VpxTheme.icon("tune")
	%SubtitleButton.icon = VpxTheme.icon("subtitles")
	%ResetPicture.icon = VpxTheme.icon("reset", 26)
	%ResetAngles.icon = VpxTheme.icon("reset", 26)
	shuffle_button.icon = VpxTheme.icon("shuffle")
	var thumb_material := ShaderMaterial.new()
	thumb_material.shader = MediaCard.RoundedShader
	thumb_material.set_shader_parameter("size", now_thumb.custom_minimum_size)
	thumb_material.set_shader_parameter("radius", 10.0)
	now_thumb.material = thumb_material


func _sync() -> void:
	_apply_accessibility()
	clock_label.visible = Settings.show_clock
	%Logo.modulate = VpxTheme.ACCENT
	if speed_button != null:
		var index := SPEEDS.find(Settings.playback_speed)
		speed_button.select(maxi(index, 0))
	fov_row.visible = Settings.projection == Settings.ProjectionMode.FISHEYE
	if not calibration_rows.is_empty():
		calibration_rows["equirect_fov"].visible = Settings.projection == Settings.ProjectionMode.EQUIRECT_180
		calibration_rows["lens_k1"].visible = Settings.projection == Settings.ProjectionMode.FISHEYE
		calibration_rows["lens_k2"].visible = Settings.projection == Settings.ProjectionMode.FISHEYE
		calibration_rows["eye_roll"].visible = Settings.stereo != Settings.Stereo.MONO
	_refresh_integrations()
	_refresh_audio_info()
	_refresh_photo_source_note()
	%ScreenSection.visible = Settings.projection == Settings.ProjectionMode.FLAT
	var flat_photo := player.is_image() and Settings.projection == Settings.ProjectionMode.FLAT
	spirit_level_section.visible = SpiritLevel.applicable(player, Settings.projection == Settings.ProjectionMode.FLAT)
	photo_repeat_row.visible = flat_photo
	pages.get_node("Picture/ScreenSection/ScreenGroup/Rows/Curve").visible = not flat_photo or Settings.flat_image_repeat == 0
	photo_pan_section.visible = Settings.projection == Settings.ProjectionMode.FLAT
	pages.get_node("Angles/OrientationGroup").visible = not flat_photo
	pages.get_node("Angles/OrientationTitle").visible = not flat_photo
	page_buttons["Angles"].text = "Pan" if flat_photo else "Position"
	pages.get_node("Angles/AnglesFooter/AnglesHint").text = "Drag to pan the flat photo. Grip and drag in the headset, or drag with the mouse on desktop." if flat_photo else "Grip and move to drag the picture with the horizon locked. Add the trigger, then twist your wrist to tilt the horizon. Set Roll (tilt) here too. Near-level angles snap flat on release. Grip while pointing at this menu moves the menu. In bed, hold B / Y while looking where you want the picture."
	%ResetAngles.text = "Reset pan" if flat_photo else "Reset"
	pages.get_node("Picture/PictureFooter/PictureHint").text = "Repeat fills more of your surroundings with the same flat photo. Curve is off while repeat is on." if flat_photo and Settings.flat_image_repeat > 0 else "Size is the angle the flat screen fills, so it looks the same at any distance. Curve bends it around you like a cinema screen."
	var keyed := Settings.background == Settings.Background.CHROMA_KEY
	%KeyRow.visible = keyed
	%TuneRow.visible = keyed
	%CutTitle.visible = keyed
	%CutGroup.visible = keyed
	for row in [%CutInvert, %CutSimilarity, %CutFeather]:
		row.visible = Settings.cut_enabled
	var masked := Settings.alpha_mask != Settings.AlphaMask.NONE
	%MaskSection.visible = masked
	%MaskDarken.visible = masked and Settings.background != Settings.Background.CHROMA_KEY
	var matching := Settings.matching_preset()
	for i in preset_buttons.size():
		preset_buttons[i].set_pressed_no_signal(i == matching)
	color_swatch.add_theme_stylebox_override("panel", VpxTheme.outlined(Settings.chroma_key_color, VpxTheme.HOVER, 2, 12, 0, 0))
	if Settings.chroma_key_color.v > 0.0 and Settings.chroma_key_color.s > 0.0:
		key_hue.show_value(roundf(Settings.chroma_key_color.h * 360.0))
	key_shade.show_value(roundf(Settings.chroma_key_color.v * 100.0))
	if shuffle_on != Settings.shuffle:
		shuffle_on = Settings.shuffle
		if player.is_image():
			player.prefetch_images(_neighbor_images(player.current_path))
		_refresh_now_playing()
	shuffle_button.set_pressed_no_signal(Settings.shuffle)
	mute_button.set_pressed_no_signal(Settings.muted)
	mute_button.icon = VpxTheme.icon("volume_off" if Settings.muted or Settings.volume == 0 else "volume")
	volume_slider.set_value_no_signal(Settings.volume)
	volume_label.text = "%d%%" % Settings.volume
	var end_index := clampi(Settings.end_action, 0, END_ACTIONS.size() - 1)
	end_button.icon = VpxTheme.icon(END_ACTIONS[end_index][0])
	end_button.set_pressed_no_signal(Settings.end_action != Settings.EndAction.STOP)
	end_label.text = END_ACTIONS[end_index][1]
	for i in source_buttons.size():
		source_buttons[i].set_pressed_no_signal(i == Settings.library_source)
	for i in filter_buttons.size():
		filter_buttons[i].set_pressed_no_signal(i == Settings.library_filter)
	_refresh_query_chip()
	%GridButton.set_pressed_no_signal(Settings.library_view == Settings.LibraryView.GRID)
	%ListButton.set_pressed_no_signal(Settings.library_view == Settings.LibraryView.LIST)
	var discovering := Settings.library_source == Settings.LibrarySource.DISCOVER
	discovery.visible = discovering
	search_button.get_parent().visible = not discovering
	sort_button.visible = not discovering
	up_button.visible = not discovering
	flat_view_button.visible = Settings.library_source == Settings.LibrarySource.FOLDER
	flat_view_button.set_pressed_no_signal(Settings.library_flat_view)
	sort_button.select(clampi(Settings.library_sort, 0, SORTS.size() - 1))
	_refresh_format_badge()
	_refresh_favorite_button()


func _connect_controls() -> void:
	favorite_button.toggled.connect(_on_favorite_button_toggled)
	play_button.pressed.connect(player.toggle_pause)
	%BackButton.pressed.connect(func() -> void:
		if player.is_image() and not _music_menu_priority():
			play_neighbor(-1)
		else:
			player.seek_relative(-SEEK_STEP))
	%ForwardButton.pressed.connect(func() -> void:
		if player.is_image() and not _music_menu_priority():
			play_neighbor(1)
		else:
			player.seek_relative(SEEK_STEP))
	%PrevButton.pressed.connect(func() -> void: play_neighbor(-1))
	%NextButton.pressed.connect(func() -> void: play_neighbor(1))
	up_button.pressed.connect(_go_up)
	%QuitButton.pressed.connect(quit_requested.emit)
	%CloseButton.pressed.connect(close_requested.emit)
	%PickButton.pressed.connect(pick_requested.emit)
	%TuneButton.pressed.connect(func() -> void: open_quick())
	%SubtitleButton.pressed.connect(func() -> void: open_quick(QUICK_SUBTITLE_TAB))
	%ResetPicture.pressed.connect(func() -> void: Settings.reset(PackedStringArray(PICTURE_SETTINGS)))
	%ResetAngles.pressed.connect(func() -> void:
		Settings.reset(PackedStringArray(PAN_SETTINGS if Settings.projection == Settings.ProjectionMode.FLAT and (player.is_image() or Settings.flat_video_pan) else ANGLE_SETTINGS)))
	mute_button.toggled.connect(func(on: bool) -> void:
		Settings.apply("muted", on)
		if not on and Settings.volume == 0:
			Settings.apply("volume", 50))
	volume_slider.value_changed.connect(func(value: float) -> void:
		Settings.apply("volume", int(value))
		if Settings.muted and value > 0.0:
			Settings.apply("muted", false))
	for control: Control in [mute_button, volume_slider, volume_label]:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.gui_input.connect(_on_volume_nudge_input)
	shuffle_button.toggled.connect(func(on: bool) -> void: Settings.apply("shuffle", on))
	end_button.pressed.connect(func() -> void: Settings.apply("end_action", wrapi(Settings.end_action + 1, 0, END_ACTIONS.size())))
	seek_slider.drag_started.connect(func() -> void:
		seek_edit_serial += 1
		seeking = true
		seek_media_serial = player.open_serial)
	seek_slider.drag_ended.connect(_on_seek_ended)
	seek_slider.value_changed.connect(_on_seek_value)
	seek_slider.gui_input.connect(_on_seek_hover)
	seek_slider.mouse_exited.connect(func() -> void:
		if not seeking:
			seek_bubble.visible = false
			previews.stop(self))
	for stepper in [key_hue, key_shade]:
		stepper.value_changed.connect(func(_value: float) -> void:
			Settings.apply("chroma_key_color", Color.from_hsv(key_hue.value / 360.0, Settings.chroma_key_color.s, key_shade.value / 100.0)))


func _process(delta: float) -> void:
	var active: bool = get_viewport().render_target_update_mode != SubViewport.UPDATE_DISABLED
	if active and not was_active:
		_refresh_cards()
		show_main()
	was_active = active
	if not active:
		return
	spirit_level_section.visible = SpiritLevel.applicable(player, Settings.projection == Settings.ProjectionMode.FLAT)
	_update_rail(delta)
	_update_scroll_bars(delta)
	_update_transport()
	clock_timer += delta
	if clock_timer >= 1.0:
		clock_timer = 0.0
		_update_clock()
	stats_timer += delta
	if stats_timer >= STATS_INTERVAL:
		stats_timer = 0.0
		_update_stats()
	_update_fling(delta)
	_update_scan_hint()
	_update_refocus()
	if search_timer >= 0.0:
		search_timer -= delta
		if search_timer < 0.0:
			refresh_directory()
	if prioritize_timer >= 0.0:
		prioritize_timer -= delta
		if prioritize_timer < 0.0:
			MediaInfo.prioritize(_visible_paths())


func _update_clock() -> void:
	var time := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [time.hour, time.minute]


func _update_transport() -> void:
	var has_media := player.playback != null
	var length := player.get_stream_length() if has_media else 0.0
	updating_slider = true
	seek_slider.max_value = maxf(length, 1.0)
	seek_slider.editable = player.can_seek()
	if not seeking:
		seek_slider.set_value_no_signal(player.stream_position if has_media else 0.0)
	updating_slider = false
	elapsed_label.text = _format_time(player.stream_position if has_media else 0.0, length)
	total_label.text = "LIVE" if player.is_live() else _format_time(length, length)
	var playing := has_media and not player.paused and player.is_playing()
	end_time_label.visible = playing and length > 0.0
	if end_time_label.visible:
		var position := seek_slider.value if seeking else player.stream_position
		var remaining := maxf(length - position, 0.0) / maxf(Settings.playback_speed, 0.01)
		var now := Time.get_datetime_dict_from_system()
		var end_minutes := posmod(int((now.hour * 3600 + now.minute * 60 + now.second + remaining) / 60.0), 1440)
		end_time_label.text = "end %02d:%02d" % [end_minutes / 60, end_minutes % 60]
	var icon_name := "pause" if playing else "play"
	if play_button.get_meta("icon_name", "") != icon_name:
		play_button.set_meta("icon_name", icon_name)
		play_button.icon = VpxTheme.icon(icon_name, 36)
	%BackButton.disabled = not player.can_seek()
	%ForwardButton.disabled = not player.can_seek()
	if seeking:
		_show_bubble(seek_slider.value, _slider_x(seek_slider.value))
	if not is_equal_approx(length, marks_length):
		_refresh_marks()


func _format_time(seconds: float, reference: float) -> String:
	var total := int(seconds)
	if reference >= 3600.0:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func volume_hovering(control: Control = null) -> bool:
	var node := control if control != null else get_viewport().gui_get_hovered_control()
	while node != null:
		if node == mute_button or node == volume_slider or node == volume_label:
			return true
		node = node.get_parent() as Control
	return false


func nudge_volume(direction: int) -> void:
	var next := clampi(Settings.volume + int(volume_slider.step) * direction, 0, 100)
	Settings.apply("volume", next)
	if Settings.muted and next > 0:
		Settings.apply("muted", false)


func _on_volume_nudge_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_WHEEL_UP and button.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	nudge_volume(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	accept_event()


func _on_seek_hover(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or seeking or not seek_slider.editable:
		return
	var ratio := clampf((motion.position.x - _grabber_half()) / maxf(seek_slider.size.x - _grabber_half() * 2.0, 1.0), 0.0, 1.0)
	var value := ratio * seek_slider.max_value
	_show_bubble(value, motion.position.x)


func _grabber_half() -> float:
	var grabber := seek_slider.get_theme_icon("grabber")
	return grabber.get_width() * 0.5 if grabber else 0.0


func _slider_x(value: float) -> float:
	var ratio := value / maxf(seek_slider.max_value, 0.001)
	return _grabber_half() + ratio * (seek_slider.size.x - _grabber_half() * 2.0)


func _ensure_seek_previews() -> void:
	previews.prepare(player)


func _show_bubble(value: float, local_x: float) -> void:
	preview_time = value
	_ensure_seek_previews()
	bubble_label.text = _format_time(value, seek_slider.max_value)
	var chapter := player.chapter_title(player.chapter_at(value)) if not player.chapters.is_empty() else ""
	if not chapter.is_empty():
		bubble_label.text += "  ·  " + chapter
	_show_preview(value)
	seek_bubble.reset_size()
	var origin := seek_slider.get_global_rect().position
	seek_bubble.position = Vector2(origin.x + local_x - seek_bubble.size.x * 0.5, origin.y - seek_bubble.size.y - 10.0)
	seek_bubble.visible = true


func _show_preview(value: float) -> void:
	var frame: Texture2D = previews.frame(value, self) if previews.path == player.current_path else null
	if frame != null:
		preview_rect.texture = frame
	preview_rect.visible = preview_rect.texture != null and previews.path == player.current_path


func set_haptic_note(active: bool, vibrates: bool) -> void:
	if not active:
		%HoverHapticsHint.text = "Vibration only works on controllers that support it."
	elif vibrates:
		%HoverHapticsHint.text = "This controller vibrates."
	else:
		%HoverHapticsHint.text = "This controller has no vibration, so the buzz does nothing."


func _refresh_photo_source_note() -> void:
	var path := player.current_path
	if not player.is_image():
		photo_note_for = ""
		%FormatHint.text = "Auto-detect reads the format from the filename and the alpha mask from the picture. A format you pick by hand is remembered for that video. Load from switches a 360° photo only when the folder has both one image and six cube faces."
		return
	if photo_note_for == path:
		%FormatHint.text = photo_note
		return
	photo_note_for = path
	var both := PanoramaFiles.cube_faces(path).size() == PanoramaFiles.CUBE_ORDER.size() and not PanoramaFiles.equirect_for(path).is_empty()
	photo_note = "Load from switches this photo between the single 360° image and the six cube faces." if both else "This photo has only one source, so Load from does not change the picture."
	%FormatHint.text = photo_note


func _on_seek_value(value: float) -> void:
	if updating_slider:
		return
	seek_edit_serial += 1
	if seeking:
		_show_bubble(value, _slider_x(value))
	else:
		_commit_seek_value.call_deferred(value, seek_edit_serial, player.open_serial)


func _commit_seek_value(value: float, serial: int, media_serial: int) -> void:
	if serial != seek_edit_serial or media_serial != player.open_serial or seeking or not seek_slider.editable:
		return
	player.seek_to(value)
	seek_slider.set_value_no_signal(value)


func _on_seek_ended(changed: bool) -> void:
	seek_edit_serial += 1
	seeking = false
	seek_bubble.visible = false
	previews.stop(self)
	if changed and seek_slider.editable and seek_media_serial == player.open_serial:
		player.seek_to(seek_slider.value)


func _on_preset_selected(index: int) -> void:
	Settings.select_format(Settings.FORMAT_PRESETS[index][1], Settings.FORMAT_PRESETS[index][2])


func apply_video_color(color: Color) -> void:
	Settings.apply("background", Settings.Background.CHROMA_KEY)
	Settings.apply("cut_enabled", true)
	Settings.apply("chroma_key_color", color)
	show_page(%Passthrough)


func _refresh_audio_info() -> void:
	if audio_info_label == null:
		return
	if player.playback == null:
		audio_info_label.text = "Spatial audio renders 5.1 / 7.1 as virtual speakers around the screen and turns 360° ambisonic sound with your head. Start music first, then open a 360° photo — the track keeps playing."
		return
	var info: Dictionary = player.playback.get_audio_info()
	audio_info_label.text = "Now playing: %s%s" % [info.get("description", "no audio"), "  ·  separate web audio" if info.get("external", false) else ""]
	if int(info.get("channels", 0)) in [1, 2] and not bool(info.get("ambisonic", false)):
		audio_info_label.text += "\nMono / stereo plays unchanged. Head-tracked spatial processing needs surround or ambisonic audio."


func _update_stats() -> void:
	var display_fps := Engine.get_frames_per_second()
	if player.is_image() or player.is_loading():
		stats_label.text = _image_stats()
		info_label.text = stats_label.text
		return
	var texture := player.get_video_texture() if not player.current_path.is_empty() else null
	if texture == null:
		stats_label.text = "Display %.0f fps" % display_fps
		info_label.text = "%s\nDisplay %.0f fps\nNo video playing\nLog: %s" % [player.build_label(), display_fps, ProjectSettings.globalize_path(Log.LOG_PATH)]
		return
	var res := "%dx%d" % [texture.get_width(), texture.get_height()]
	var mbps := player.bitrate_mbps()
	var rate := "%.0f Mbps" % mbps if mbps > 0.0 else "— Mbps"
	var decode := "hw" if player.hardware_decoding else "sw"
	var measured := player.shown_fps()
	var shown := "%.0f/%.0f fps video" % [measured, player.playback_fps()] if measured > 0.0 else "%.2f fps video" % player.playback_fps()
	stats_label.text = "%s  ·  %s  ·  %s decode" % [shown, res, decode]
	if %System.visible:
		var tier := int(player.playback.get_frame_info().get("adaptive_tier", 0)) if player.playback != null else 0
		info_label.text = "\n".join(PackedStringArray([
			"Build %s" % player.build_label(),
			"Display %.0f fps  ·  video %s" % [display_fps, shown],
			"%s  ·  %s  ·  %s decode  ·  %s" % [res, rate, decode, player.pixel_format_name()],
			"Adaptive quality tier %d" % tier,
			"Log: %s" % ProjectSettings.globalize_path(Log.LOG_PATH),
		]))


func _image_stats() -> String:
	if player.is_loading() and not player.is_image():
		return "loading…"
	var info := player.image_info
	var source := "cube 6×%d²" % info["face_size"] if info["layout"] == VPXPanorama.LAYOUT_CUBE else "%dx%d" % [info["width"], info["height"]]
	var loading := "  ·  loading…" if player.is_loading() else ""
	return "%s  ·  loaded in %d ms  ·  %.0f MB VRAM%s" % [source, info["total_msec"], info["vram_bytes"] / 1048576.0, loading]


func _on_opened(path: String) -> void:
	var entry := _entry_for(path)
	if entry.is_empty() or VPXPlayer._network_path(path):
		_request_playlist(path)
	elif Settings.shuffle and shuffle.members.has(entry):
		shuffle.visit(entry)
	Settings.apply("last_file", path)
	var previous := now_path
	previews.clear()
	preview_rect.texture = null
	preview_rect.visible = false
	_sync()
	_refresh_now_playing()
	_highlight_current()
	for other in [previous, path]:
		var card := _card_for(other)
		if card != null:
			card.refresh()
	if path.get_extension().to_lower() not in DISC_EXTENSIONS and not path.begins_with("vpxzip://"):
		MediaInfo.request(path)
	_refresh_marks()
	player.prefetch_images(_neighbor_images(path) if player.is_image() else PackedStringArray())
	_refresh_audio_info()


func _refresh_now_playing() -> void:
	now_path = player.current_path
	if now_path.is_empty():
		now_title.text = "Nothing playing"
		now_thumb.texture = null
		now_thumb.visible = false
		format_badge.visible = false
		_refresh_favorite_button()
		return
	now_title.text = playlist_label(now_path)
	if player.is_music_mode():
		now_title.text = music_label()
	if not player.music_path.is_empty():
		now_title.text += "  ·  " + music_label()
	var texture := MediaInfo.thumbnail(now_path)
	if player.is_music_mode() and player.radio.artwork != null:
		texture = player.radio.artwork
	now_thumb.custom_minimum_size = Vector2(54, 54) if player.is_music_mode() else Vector2(96, 54)
	now_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if player.is_music_mode() else TextureRect.STRETCH_SCALE
	(now_thumb.material as ShaderMaterial).set_shader_parameter("size", now_thumb.custom_minimum_size)
	now_thumb.texture = texture
	now_thumb.visible = texture != null
	_refresh_format_badge()
	_refresh_favorite_button()


func _favorite_path() -> String:
	return player.current_path


func _on_favorite_button_toggled(on: bool) -> void:
	var path := _favorite_path()
	if path.is_empty():
		favorite_button.set_pressed_no_signal(false)
		return
	set_favorite(path, on)


func _refresh_favorite_button() -> void:
	if favorite_button == null:
		return
	var path := _favorite_path()
	favorite_button.disabled = path.is_empty()
	favorite_button.set_pressed_no_signal(not path.is_empty() and Library.is_favorite(path))
	var on := favorite_button.button_pressed
	favorite_button.icon = VpxTheme.icon("star" if on else "star_outline", 26)
	var color := VpxTheme.FAVORITE if on else VpxTheme.FAINT
	for role in ["icon_normal_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		favorite_button.add_theme_color_override(role, color)
	favorite_button.add_theme_color_override("icon_hover_color", VpxTheme.FAVORITE)


func _refresh_format_badge() -> void:
	if format_badge == null:
		return
	if player.current_path.is_empty():
		format_badge.visible = false
		return
	var label := VPXPlayer.format_label(Settings.projection, Settings.stereo)
	if Settings.alpha_mask != Settings.AlphaMask.NONE and not player.is_image():
		label += "  α"
	format_label.text = label
	format_badge.visible = true


func playlist_label(path: String) -> String:
	var index: int = playlist_index.get(_entry_for(path), -1)
	var name := MediaCard.pretty_name(path)
	if index < 0:
		return name
	if Settings.shuffle:
		return "Shuffle %d / %d   %s" % [shuffle.seen_count(), playlist.size(), name]
	return "%d / %d   %s" % [index + 1, playlist.size(), name]


func music_label() -> String:
	var path := player.music_path if not player.music_path.is_empty() else player.current_path
	if path.is_empty():
		return ""
	var name := MediaCard.pretty_name(path)
	if player.radio.path == path and not str(player.radio.metadata.get("title", "")).is_empty():
		var artist := str(player.radio.metadata.get("artist", ""))
		return (artist + " — " if not artist.is_empty() else "") + str(player.radio.metadata["title"])
	if music_playlist.is_empty():
		return name
	var index: int = music_playlist_index.get(path, -1)
	if index < 0:
		return name
	if Settings.shuffle:
		return "Shuffle %d / %d   %s" % [music_shuffle.seen_count(), music_playlist.size(), name]
	return "%d / %d   %s" % [index + 1, music_playlist.size(), name]


func play_neighbor(direction: int) -> bool:
	if player.is_image() and not _music_menu_priority():
		return _play_media_neighbor(direction)
	if player._audio_only_playing():
		return play_music_neighbor(direction)
	return _play_media_neighbor(direction)


func _music_menu_priority() -> bool:
	return player._audio_only_playing() and get_viewport().render_target_update_mode != SubViewport.UPDATE_DISABLED


func play_music_neighbor(direction: int) -> bool:
	if music_playlist.is_empty():
		return false
	var current := player.music_path if not player.music_path.is_empty() else player.current_path
	if Settings.shuffle:
		if not radio_queue_active and not music_shuffle.members.has(current) and not current.is_empty():
			music_shuffle.visit(current)
		var target := music_shuffle.next() if direction > 0 else music_shuffle.previous()
		if target.is_empty():
			return false
		open_media(target)
		return true
	var index: int = music_playlist_index.get(current, -1)
	if index < 0:
		index = 0 if direction > 0 else music_playlist.size() - 1
	else:
		index = wrapi(index + direction, 0, music_playlist.size())
	open_media(music_playlist[index])
	return true


func _play_media_neighbor(direction: int) -> bool:
	if playlist.is_empty():
		return false
	pending_direction = direction
	var current := _entry_for(player.current_path)
	if Settings.shuffle:
		if not radio_queue_active and not shuffle.members.has(current) and not current.is_empty():
			shuffle.visit(current)
		var target := shuffle.next() if direction > 0 else shuffle.previous()
		if target.is_empty():
			return false
		_open_entry(target)
		return true
	var index: int = playlist_index.get(current, -1)
	if index < 0:
		index = 0 if direction > 0 else playlist.size() - 1
	else:
		index = wrapi(index + direction, 0, playlist.size())
	_open_entry(playlist[index])
	return true


func _entry_for(path: String) -> String:
	if path.is_empty():
		return ""
	if playlist_index.has(path):
		return path
	var folder := path.get_base_dir() + "/"
	return folder if playlist_index.has(folder) else ""


func _open_entry(entry: String) -> void:
	skipped_entries.clear()
	_resolve_entry(entry)


func _resolve_entry(entry: String) -> void:
	pending_entry = ""
	while not entry.is_empty() and not skipped_entries.has(entry):
		if not entry.ends_with("/"):
			skipped_entries.clear()
			open_media(entry)
			return
		var folder := entry.trim_suffix("/")
		if not folder_covers.has(folder):
			pending_entry = entry
			scanner.cover(folder)
			return
		var cover: Dictionary = folder_covers[folder]
		if not cover.is_empty():
			skipped_entries.clear()
			open_media(cover["cover"])
			return
		skipped_entries[entry] = true
		entry = _next_entry(entry)
	skipped_entries.clear()


func _skip_entry(entry: String) -> void:
	skipped_entries[entry] = true
	_resolve_entry(_next_entry(entry))


func _next_entry(entry: String) -> String:
	if Settings.shuffle:
		shuffle.visit(entry)
	elif playlist_index.has(entry) and not playlist.is_empty():
		var index := wrapi(int(playlist_index[entry]) + pending_direction, 0, playlist.size())
		return playlist[index]
	else:
		return ""
	return shuffle.next() if pending_direction > 0 else shuffle.previous()


func _neighbor_images(path: String) -> PackedStringArray:
	var entry := _entry_for(path)
	var index: int = playlist_index.get(entry, -1)
	var neighbors := PackedStringArray()
	prefetch_sets.clear()
	if index < 0 or playlist.size() < 2:
		return neighbors
	var candidates := [shuffle.peek_next(), shuffle.peek_previous()] if Settings.shuffle else [playlist[wrapi(index + 1, 0, playlist.size())], playlist[wrapi(index - 1, 0, playlist.size())]]
	for candidate: String in candidates:
		var neighbor := candidate
		if candidate.ends_with("/"):
			var folder := candidate.trim_suffix("/")
			if not folder_covers.has(folder):
				prefetch_sets[folder] = true
				scanner.cover(folder)
				continue
			neighbor = folder_covers[folder].get("cover", "")
		if not neighbor.is_empty() and neighbor != path and PanoramaFiles.is_image(neighbor) and neighbor not in neighbors:
			neighbors.append(neighbor)
	return neighbors


func _highlight_current() -> void:
	for path: String in cards:
		_sync_card_playback(cards[path])


func _sync_card_playback(card: Button) -> void:
	var media: String = card.media_path()
	if card.toggle_mode:
		card.set_pressed_no_signal(media == player.current_path)
	card.set_playing(not media.is_empty() and (media == player.current_path or media == player.music_path))


func _refresh_cards() -> void:
	for card in cards.values():
		card.refresh()
	_refresh_now_playing()


func _on_media_updated(path: String) -> void:
	var card := _card_for(path)
	if card != null:
		card.refresh()
	if path == player.current_path:
		_refresh_now_playing()


func _on_music_ended() -> void:
	if opening_media():
		return
	if Settings.sleep_timer == Settings.SleepTimer.END_OF_VIDEO:
		Settings.apply("sleep_timer", Settings.SleepTimer.OFF)
		_stop_music_under_picture()
		Log.info("sleep timer: stopped at end of music")
		return
	match Settings.end_action:
		Settings.EndAction.REPEAT:
			player.restart()
		Settings.EndAction.NEXT_FILE:
			if not play_music_neighbor(1):
				_stop_music_under_picture()
		_:
			_stop_music_under_picture()


func _stop_music_under_picture() -> void:
	if player.music_path.is_empty():
		return
	player.stop_music()


func _request_playlist(path: String) -> void:
	var audio_over_image := player.is_image() and player.music_path == path
	if VPXPlayer._network_path(path):
		var audio := player._audio_only_playing()
		var files := _link_playlist(path, music_playlist if audio else playlist)
		if not audio_over_image:
			_set_playlist(files, path)
		if audio:
			music_playlist = files
			music_playlist_index = LibraryScanner.index_of(files)
			music_shuffle.sync(files, path)
		return
	if not PanoramaFiles.is_image(path):
		_clear_radio_queue()
	if not audio_over_image:
		_set_playlist(PackedStringArray([path]), path)
	if Settings.library_flat_view and Settings.library_source == Settings.LibrarySource.FOLDER and path in listing:
		var audio := path.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS
		var image := PanoramaFiles.is_image(path)
		var files := PackedStringArray(Array(listing).filter(func(item: String) -> bool:
			return (item.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS) == audio and PanoramaFiles.is_image(item) == image))
		scanner.prepare(files, path)
		return
	if not path.contains("://"):
		scanner.playlist(path, PanoramaFiles.is_image(path), Settings.library_sort, _scan_filter())


func _link_playlist(current: String, previous: PackedStringArray) -> PackedStringArray:
	if radio_queue_active and (current in radio_queue or Settings.library_source == Settings.LibrarySource.DISCOVER):
		return radio_queue.duplicate()
	var links := Library.recent_links()
	if current not in links:
		links.append(current)
	var files := PackedStringArray()
	for path: String in previous:
		if path in links and path not in files:
			files.append(path)
	for path: String in links:
		if path not in files:
			files.append(path)
	return files


func _clear_radio_queue() -> void:
	radio_queue_active = false
	radio_queue = PackedStringArray()
	radio_queue_stations.clear()


func _capture_radio_queue() -> void:
	radio_queue = listing.duplicate()
	radio_queue_stations.clear()
	for path in radio_queue:
		radio_queue_stations[path] = item_meta.get(path, {}).get("station", {}).duplicate()
	var current := player.music_path if not player.music_path.is_empty() else player.current_path
	if not player.is_image():
		_set_playlist(radio_queue, current)
	music_playlist = radio_queue.duplicate()
	music_playlist_index = LibraryScanner.index_of(music_playlist)
	music_shuffle.sync(music_playlist, current)


func _set_playlist(files: PackedStringArray, current: String) -> void:
	if files.size() > PLAYLIST_SYNC_LIMIT:
		_set_playlist(PackedStringArray([current]), current)
		scanner.prepare(files, current)
		return
	playlist = files
	playlist_index = LibraryScanner.index_of(files)
	shuffle.sync(playlist, _entry_for(current))


func _on_scan_finished(result: Dictionary) -> void:
	if result["kind"] == "playlist":
		var path: String = result["path"]
		var files: PackedStringArray = result["files"]
		var index: Dictionary = result["index"]
		if result.get("audio_only", false):
			var song := player.music_path if not player.music_path.is_empty() else path
			if not index.has(song):
				files.insert(0, song)
				index = LibraryScanner.index_of(files)
				music_shuffle.sync(files, song)
			else:
				music_shuffle = result["shuffle"]
			music_playlist = files
			music_playlist_index = index
			if music_shuffle.members.has(song):
				music_shuffle.visit(song)
			if not player.is_image():
				playlist = files
				playlist_index = index
				shuffle = music_shuffle
			return
		var current := player.current_path if not player.current_path.is_empty() else path
		if current != path and not playlist_index.has(current) and not result["index"].has(current) and not result["index"].has(current.get_base_dir() + "/"):
			return
		if not index.has(current) and not index.has(current.get_base_dir() + "/"):
			files.insert(0, current)
			index = LibraryScanner.index_of(files)
			shuffle.sync(files, current)
		else:
			shuffle = result["shuffle"]
		playlist = files
		playlist_index = index
		var entry := _entry_for(current)
		if shuffle.members.has(entry):
			shuffle.visit(entry)
		if player.is_image():
			player.prefetch_images(_neighbor_images(player.current_path))
		return
	_show_scan(result)


func _on_cover_found(path: String, cover: Dictionary) -> void:
	folder_covers[path] = cover
	if pending_entry == path + "/":
		if cover.is_empty():
			_skip_entry(pending_entry)
		else:
			pending_entry = ""
			open_media(cover["cover"])
	elif prefetch_sets.has(path) and player.is_image():
		player.prefetch_images(_neighbor_images(player.current_path))
	if cover.is_empty() or not cards.has(path):
		return
	var card: Button = cards[path]
	card.set_cover(cover)
	_track_cover(path, card)
	_sync_card_playback(card)


func open_directory(path: String) -> void:
	cancel_disc_open()
	if path.is_empty():
		return
	directory = _clean_directory(path)
	directory_fallbacks = false
	Settings.apply("last_directory", directory)
	Settings.apply("library_source", Settings.LibrarySource.FOLDER)
	refresh_directory()


func _select_source(source: int) -> void:
	if Settings.library_source == source:
		return
	if source != Settings.LibrarySource.DISCOVER and discovery.directory.busy:
		discovery.directory.cancel()
		discovery.directory.started = false
	Settings.apply("library_source", source)
	refresh_directory()


func refresh_directory(check_paths := true) -> void:
	paths_serial += 1
	if is_instance_valid(paths_job):
		paths_job.cancel()
	paths_job = null
	MediaInfo.cancel_pending()
	scanner.cancel()
	scanner.clear_covers()
	scan_started_msec = -1
	scan_hint = null
	item_meta.clear()
	cover_owner.clear()
	pending_folders = PackedStringArray()
	pending_media = PackedStringArray()
	listing = PackedStringArray()
	for grid in [folder_grid, media_grid]:
		if grid != null:
			grid.clear()
	cards.clear()
	for row in file_list.get_children():
		file_list.remove_child(row)
		row.queue_free()
	file_scroll.scroll_vertical = 0
	fling = 0.0
	if Settings.library_view == Settings.LibraryView.GRID:
		folder_grid = _section(GRID_COLUMNS, GRID_SEPARATION, 10, MediaCard.Layout.CHIP)
		media_grid = _section(GRID_COLUMNS, GRID_SEPARATION, GRID_SEPARATION, MediaCard.Layout.CARD)
	else:
		folder_grid = _section(1, 0, file_list.get_theme_constant("separation"), MediaCard.Layout.ROW)
		media_grid = _section(1, 0, file_list.get_theme_constant("separation"), MediaCard.Layout.ROW)
	match Settings.library_source:
		Settings.LibrarySource.RECENT:
			_list_recent(check_paths)
		Settings.LibrarySource.FAVORITES:
			_list_favorites(check_paths)
		Settings.LibrarySource.PLACES:
			_list_places(check_paths)
		Settings.LibrarySource.NETWORK:
			_list_network()
		Settings.LibrarySource.DISCOVER:
			_list_discovery()
		_:
			_start_scan()
	_build_crumbs()
	match Settings.library_source:
		Settings.LibrarySource.FOLDER:
			up_button.disabled = _is_root(directory)
		Settings.LibrarySource.NETWORK:
			up_button.disabled = dlna_stack.is_empty()
		_:
			up_button.disabled = true
	if scan_started_msec < 0:
		_flush_items()


func _section(columns: int, h_separation: int, v_separation: int, layout: MediaCard.Layout) -> VirtualGrid:
	if layout != MediaCard.Layout.ROW:
		columns = clampi(floori((accessibility_size.x - 130.0) / (260.0 * Settings.text_size)), 3, GRID_COLUMNS)
	var grid := VirtualGrid.new()
	grid.layout = layout
	var height := func(width: float) -> float: return MediaCard.height_for(width, grid.layout)
	grid.setup(file_scroll, columns, h_separation, v_separation, height, _build_card, _release_card)
	file_list.add_child(grid)
	return grid


func _start_scan() -> void:
	scan_started_msec = Time.get_ticks_msec()
	if Settings.library_view == Settings.LibraryView.GRID:
		folder_grid.layout = MediaCard.Layout.CARD
	var query := Settings.library_query.strip_edges()
	var filter := _scan_filter()
	if query.is_empty() or Settings.library_flat_view:
		scanner.folder(directory, Settings.library_sort, _folder_fallbacks() if directory_fallbacks else PackedStringArray(), filter, Settings.library_flat_view, query.to_lower().split(" ", false))
	else:
		scanner.search(directory, query.to_lower().split(" ", false), Settings.library_sort, SEARCH_MAX_FOLDERS, SEARCH_MAX_DEPTH, SEARCH_MAX_RESULTS, filter)


func _scan_filter() -> Dictionary:
	if Settings.library_filter == Settings.LibraryFilter.ALL:
		return {}
	var formats := {}
	for path: String in Library.entries:
		var saved: Variant = Library.entries[path].get("format")
		if saved is Dictionary:
			formats[path] = saved.duplicate()
	return {"kind": Settings.library_filter, "formats": formats, "info": MediaInfo.entries.duplicate()}


func _update_scan_hint() -> void:
	if scan_started_msec < 0 or scan_hint != null or Time.get_ticks_msec() - scan_started_msec < SCAN_HINT_DELAY_MSEC:
		return
	if not folder_grid.is_empty() or not media_grid.is_empty():
		return
	_add_hint("Searching…" if not Settings.library_query.strip_edges().is_empty() else "Reading folder…")
	scan_hint = file_list.get_child(file_list.get_child_count() - 1)


func _end_scan_hint() -> void:
	if scan_hint != null:
		file_list.remove_child(scan_hint)
		scan_hint.queue_free()
		scan_hint = null


func _show_scan(result: Dictionary) -> void:
	var done: bool = result["done"]
	if result.get("error", false):
		scan_started_msec = -1
		_end_scan_hint()
		_add_hint("This folder stopped responding. Choose another location or retry." if result.get("message") == "Operation timed out" else "This folder cannot be opened")
		return
	if result["kind"] == "folder" and result["path"] != directory:
		directory = result["path"]
		_build_crumbs()
		up_button.disabled = _is_root(directory)
	if result["kind"] == "folder":
		directory_fallbacks = false
		Library.mark_folder_visited(directory)
		Settings.apply("last_directory", directory)
	var folders: PackedStringArray = result["folders"]
	var files: PackedStringArray = result["files"]
	folder_grid.set_items(folders)
	media_grid.set_items(files)
	listing = files
	if done and player.current_path in files:
		if Settings.library_flat_view:
			_request_playlist(player.current_path)
		else:
			var ordered := PackedStringArray(Array(files).filter(func(item: String) -> bool: return PanoramaFiles.is_image(item))) if player.is_image() else files
			_set_playlist(ordered, player.current_path)
	_set_count(folders.size(), files.size(), not done)
	if not folders.is_empty() or not files.is_empty() or done:
		_end_scan_hint()
	prioritize_timer = PRIORITIZE_DELAY
	if not done:
		return
	scan_started_msec = -1
	if not Settings.library_query.strip_edges().is_empty():
		if folders.is_empty() and files.is_empty():
			_add_hint("Nothing matches “%s” in this folder or its subfolders" % Settings.library_query)
		elif result.get("truncated", false):
			_add_hint("Showing the first matches — open a subfolder to search deeper")
	elif files.is_empty() and Settings.library_filter != Settings.LibraryFilter.ALL:
		_add_hint("No %s videos in this folder" % FILTERS[Settings.library_filter] if Settings.library_filter != Settings.LibraryFilter.PHOTOS else "No photos in this folder")
	elif folders.is_empty() and files.is_empty():
		_add_hint("No videos, audio, or photos in this folder")
	if not disc_status.is_empty():
		_add_hint(disc_status)
		disc_status = ""


func _list_recent(check_paths := true) -> void:
	var folders := Array(Library.recent_folders(RECENT_LIMIT)).filter(_query_matches)
	var paths := Array(Library.recent_paths(RECENT_LIMIT)).filter(_wanted)
	for path: String in folders:
		_queue_item(path, true, "", _saved_context(path))
	for path: String in paths:
		_queue_item(path, false, "", _saved_context(path))
	if check_paths:
		_check_saved_paths(PackedStringArray(folders + paths))
	_set_count(folders.size(), paths.size())
	if folders.is_empty() and paths.is_empty():
		_add_hint("Nothing matches" if _narrowed() else "No recent folders or media yet")


func _list_favorites(check_paths := true) -> void:
	var folders: Array[String] = []
	var files: Array[String] = []
	for path in Library.favorite_paths():
		var info: Dictionary = saved_path_info.get(path, {})
		if info.get("is_directory", Library.get_pref(path, "is_directory", Library.get_pref(path, "folder_visited") != null)):
			folders.append(path)
		else:
			files.append(path)
	if check_paths:
		_check_saved_paths(Library.favorite_paths())
	folders = _sorted(_keep(folders, _query_matches), true)
	files = _sorted(_keep(files, _wanted), false)
	for path in folders:
		_queue_item(path, true, "", _saved_context(path))
	for path in files:
		_queue_item(path, false, "", _saved_context(path))
	_set_count(folders.size(), files.size())
	if folders.is_empty() and files.is_empty():
		_add_hint("No favourites yet — tap the star on any folder, video or photo")


func _saved_context(path: String) -> String:
	var info: Dictionary = saved_path_info.get(path, {})
	return ("Unavailable · " if info.get("available") == false else "") + _short_dir(path.get_base_dir())


func _check_saved_paths(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	_start_paths_job(_read_saved_paths.bind(paths))


func _start_paths_job(action: Callable, places := false) -> void:
	var serial := paths_serial
	var job := BackgroundTask.start(action, 15.0)
	paths_job = job
	job.completed.connect(func(result: Dictionary) -> void:
		if serial != paths_serial:
			return
		paths_job = null
		if result.get("ok", false):
			if places:
				places_cache = result["places"]
			else:
				saved_path_info.merge(result["paths"], true)
			_refresh_saved_listing())


func _refresh_saved_listing() -> void:
	var scroll := file_scroll.scroll_vertical
	var focus := get_viewport().gui_get_focus_owner()
	var focus_path: String = focus.path if focus is MediaCard else ""
	refresh_directory(false)
	file_scroll.set_deferred("scroll_vertical", scroll)
	if not focus_path.is_empty():
		for grid: VirtualGrid in [folder_grid, media_grid]:
			var index := grid.items.find(focus_path)
			if index >= 0:
				grid.control_at(index).grab_focus()
				break


static func _read_saved_paths(token: RefCounted, paths: PackedStringArray) -> Dictionary:
	var info := {}
	for path in paths:
		if token.is_cancelled():
			return {"cancelled": true}
		if path.contains("://"):
			continue
		var directory := DirAccess.dir_exists_absolute(path)
		var available := directory or FileAccess.file_exists(path)
		info[path] = {"available": available, "mtime": FileAccess.get_modified_time(path) if available else 0, "bytes": FileAccess.get_size(path) if available and not directory else 0}
		if available:
			info[path]["is_directory"] = directory
	return {"ok": true, "paths": info}


func _list_places(check_paths := true) -> void:
	var home := PlatformPaths.home()
	var places: Array = [[home, "Home", "home"]]
	for kind in [OS.SYSTEM_DIR_MOVIES, OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_PICTURES, OS.SYSTEM_DIR_DOCUMENTS]:
		var path := OS.get_system_dir(kind)
		if not path.is_empty() and path != home:
			places.append([path, path.get_file(), "folder"])
	var seeds := places.duplicate(true)
	for place: Array in places_cache:
		if not places.any(func(existing: Array) -> bool: return existing[0] == place[0]):
			places.append(place)
	for place: Array in places:
		_queue_item(place[0], true, place[1], _short_dir(place[0]), place[2])
	_set_count(places.size(), 0)
	if check_paths:
		_start_paths_job(_read_places.bind(seeds, OS.get_name(), OS.get_environment("USER")), true)


static func _read_places(token: RefCounted, places: Array, platform: String, user: String) -> Dictionary:
	if platform == "Windows":
		for code in range(65, 91):
			if token.is_cancelled():
				return {"cancelled": true}
			var path := String.chr(code) + ":/"
			if DirAccess.dir_exists_absolute(path):
				places.append([path, path.trim_suffix("/"), "drive"])
	else:
		var mounts: Array[String] = []
		for root in ["/run/media/%s" % user, "/run/media", "/media/%s" % user, "/media", "/mnt"]:
			if token.is_cancelled():
				return {"cancelled": true}
			var folder := DirAccess.open(root)
			if folder == null:
				continue
			for name in folder.get_directories():
				var path: String = root.path_join(name)
				if name != user and not name.begins_with(".") and path not in mounts:
					mounts.append(path)
		for path in mounts:
			places.append([path, path.get_file(), "drive"])
		places.append(["/", "Computer", "drive"])
	return {"ok": true, "places": places}


func _narrowed() -> bool:
	return Settings.library_filter != Settings.LibraryFilter.ALL or not Settings.library_query.strip_edges().is_empty()


func _keep(paths: Array[String], test: Callable) -> Array[String]:
	var kept: Array[String] = []
	for path in paths:
		if test.call(path):
			kept.append(path)
	return kept


func _relative_dir(path: String) -> String:
	if path == directory:
		return "This folder"
	return path.trim_prefix(directory).trim_prefix("/") if path.begins_with(directory) else _short_dir(path)


func _words_match(text: String, words: PackedStringArray) -> bool:
	var haystack := text.to_lower().replace("_", " ").replace(".", " ")
	for word in words:
		if not haystack.contains(word):
			return false
	return true


func _query_matches(path: String, title := "") -> bool:
	var words := Settings.library_query.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return true
	return _words_match("%s %s" % [title, path.get_slice("?", 0).get_file().uri_decode()], words)


func _wanted(path: String, title := "") -> bool:
	return _query_matches(path, title) and _filter_matches(path)


func _filter_matches(path: String) -> bool:
	var filter: int = Settings.library_filter
	if filter == Settings.LibraryFilter.ALL:
		return true
	if filter == Settings.LibraryFilter.PHOTOS:
		return PanoramaFiles.is_image(path)
	return _format_kind(path) == filter


func _format_kind(path: String) -> int:
	return LibraryScanner.format_kind(path, MediaInfo.cached(path), Library.get_pref(path, "format"))


func _start_radio_discovery() -> void:
	if Settings.library_source == Settings.LibrarySource.DISCOVER:
		discovery.ensure_started()


func _list_discovery() -> void:
	_start_radio_discovery.call_deferred()
	var directory_service: Node = discovery.directory
	var stations: Array = directory_service.stations
	if discovery.saved:
		stations = []
		for path in Library.favorite_paths():
			var station: Variant = Library.get_pref(path, "radio_station", {})
			if station is Dictionary and not station.is_empty():
				stations.append(station)
		stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	var hint := Label.new()
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Tap a station to listen · Star to save · Directory: Radio Browser"
	if directory_service.has_more and not discovery.saved:
		hint.text += " · Load more stations below"
	if directory_service.busy:
		hint.text = "Finding radio stations…"
	elif not directory_service.error.is_empty() and not discovery.saved:
		hint.text = directory_service.error
	file_list.add_child(hint)
	file_list.move_child(hint, 0)
	for station: Dictionary in stations:
		var path: String = station["url"]
		_queue_item(path, false, station["name"], discovery.Directory.description(station), "audio")
		item_meta[path]["station"] = station
	count_label.text = "%d station%s" % [stations.size(), "" if stations.size() == 1 else "s"]
	if stations.is_empty() and not directory_service.busy:
		_add_hint("No saved stations yet. Tap the star on a station to keep it here and in Favourites." if discovery.saved else "No stations found. Try another name or clear the filters with Reset." if directory_service.error.is_empty() else "You can still open a stream URL or listen to saved stations.")
	if not discovery.saved and not directory_service.busy and (directory_service.has_more or not directory_service.error.is_empty()):
		var button := _action_button("Retry" if not directory_service.error.is_empty() else "Load more stations", "recent" if not directory_service.error.is_empty() else "plus")
		button.pressed.connect(func() -> void: directory_service.search(discovery.query(), not directory_service.stations.is_empty()))
		file_list.add_child(button)


func _list_network() -> void:
	if not dlna_stack.is_empty():
		_list_media_server()
		return
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	file_list.add_child(actions)
	file_list.move_child(actions, 0)
	var entries := [["Add server", "plus", _ask_server], ["Open link", "link", _ask_link], ["Scan network", "recent", network.discover]]
	if not web.available() and not web.is_busy():
		entries.append(["Get yt-dlp", "download", _install_web_tool])
	for entry in entries:
		var button := _action_button(entry[0], entry[1])
		button.custom_minimum_size.y = ACTION_HEIGHT
		button.pressed.connect(func() -> void:
			entry[2].call()
			refresh_directory())
		actions.add_child(button)
	if not Settings.network_servers.is_empty():
		var remove := _action_button("Done removing" if removing_servers else "Remove servers", "check" if removing_servers else "trash")
		remove.custom_minimum_size.y = ACTION_HEIGHT
		remove.pressed.connect(func() -> void:
			removing_servers = not removing_servers
			refresh_directory())
		actions.add_child(remove)
	if not network_status.is_empty():
		_add_hint(network_status)
		file_list.move_child(file_list.get_child(file_list.get_child_count() - 1), 1)
	var count := 0
	var link_count := 0
	for url: String in Library.recent_links():
		var title := MediaCard.pretty_name(url)
		if not _query_matches(url, title):
			continue
		_queue_item(url, false, title, "Opened link  ·  " + Network.strip_password(url), "link")
		link_count += 1
	for i in Settings.network_servers.size():
		var server: Dictionary = Settings.network_servers[i]
		if not _query_matches(server.get("url", ""), server.get("name", "")):
			continue
		_queue_item("server:%d" % i, true, server.get("name", ""), ("Tap to remove  ·  " if removing_servers else "") + Network.strip_password(server.get("url", "")), "trash" if removing_servers else "network")
		count += 1
	for i in network.media_servers.size():
		var server: Dictionary = network.media_servers[i]
		if not _query_matches("", server["name"]):
			continue
		_queue_item("dlna:%d" % i, true, server["name"], "Media server", "network")
		count += 1
	_set_count(count, link_count)
	if network.is_searching():
		_add_hint("Looking for media servers on your network…")
	elif count == 0 and link_count == 0:
		_add_hint("Add a Windows / Samba share (smb://computer/share), SFTP, FTP or WebDAV server, or open a video or radio stream link. Media servers (DLNA) on your network show up here after a scan.")
	if network.media_servers.is_empty() and not network.is_searching() and not network.get_meta("scanned", false):
		network.set_meta("scanned", true)
		network.discover()
		get_tree().create_timer(Network.SEARCH_SECONDS + 0.2).timeout.connect(func() -> void:
			if Settings.library_source == Settings.LibrarySource.NETWORK and dlna_stack.is_empty():
				refresh_directory())


func _list_media_server() -> void:
	var top: Dictionary = dlna_stack.back()
	if not top.has("result"):
		_add_hint("Loading %s…" % top["name"])
		var depth := dlna_stack.size()
		network.browse(top["control"], top["id"], func(result: Dictionary) -> void:
			if dlna_stack.size() == depth and dlna_stack.back() == top:
				top["result"] = result
				if Settings.library_source == Settings.LibrarySource.NETWORK:
					refresh_directory())
		return
	var result: Dictionary = top["result"]
	if result.has("error"):
		_add_hint(result["error"])
		return
	var folders := 0
	var files := 0
	for i in result["containers"].size():
		var container: Dictionary = result["containers"][i]
		if not _query_matches("", container["title"]):
			continue
		var items: String = container.get("count", "")
		_queue_item("upnp:%d" % i, true, container["title"], "%s items" % items if not items.is_empty() else "")
		folders += 1
	for item: Dictionary in result["items"]:
		var url: String = item["url"]
		if not _query_matches(url, item["title"]) or not _filter_matches(url):
			continue
		network_titles[url] = item["title"]
		_queue_item(url, false, item["title"], _item_context(item))
		files += 1
	_set_count(folders, files)
	if folders == 0 and files == 0:
		_add_hint("No videos or photos here")


func _item_context(item: Dictionary) -> String:
	var parts := PackedStringArray()
	var seconds := Network.parse_duration(item.get("duration", ""))
	if seconds > 0.0:
		parts.append(MediaInfo.duration_text(seconds))
	if not item.get("resolution", "").is_empty():
		parts.append(item["resolution"])
	return "  ·  ".join(parts)


func _ask_server() -> void:
	keyboard_purpose = "server"
	keyboard.open("Add a network share", "smb://", "smb://computer/share  ·  sftp://user@host/path  ·  webdav://host/path")


func _ask_link() -> void:
	keyboard_purpose = "link"
	keyboard.open("Open a media link or share", "", "Radio stream / audio / video URL  ·  YouTube / Vimeo%s  ·  smb://computer/share" % ("" if web.available() else " (needs yt-dlp)"))


func _on_network_item(path: String) -> void:
	var index := path.get_slice(":", 1).to_int()
	if path.begins_with("server:"):
		if index >= Settings.network_servers.size():
			return
		if removing_servers:
			var servers: Array = Settings.network_servers.duplicate()
			servers.remove_at(index)
			Settings.apply("network_servers", servers)
			removing_servers = not servers.is_empty()
			refresh_directory()
			return
		_connect_share(Settings.network_servers[index]["url"])
	elif path.begins_with("dlna:") and index < network.media_servers.size():
		var server: Dictionary = network.media_servers[index]
		dlna_stack = [{"name": server["name"], "control": server["control"], "id": "0"}]
		refresh_directory()
	elif path.begins_with("upnp:") and not dlna_stack.is_empty():
		var top: Dictionary = dlna_stack.back()
		var containers: Array = top.get("result", {}).get("containers", [])
		if index < containers.size():
			dlna_stack.append({"name": containers[index]["title"], "control": top["control"], "id": containers[index]["id"]})
			refresh_directory()


func _sorted(paths: Array[String], folders: bool) -> Array[String]:
	var keys := {}
	match Settings.library_sort:
		Settings.LibrarySort.DATE:
			for path in paths:
				keys[path] = saved_path_info.get(path, {}).get("mtime", 0)
			paths.sort_custom(func(a: String, b: String) -> bool: return keys[a] > keys[b] or (keys[a] == keys[b] and a.naturalnocasecmp_to(b) < 0))
		Settings.LibrarySort.SIZE when not folders:
			for path in paths:
				keys[path] = saved_path_info.get(path, {}).get("bytes", MediaInfo.entries.get(path, {}).get("bytes", 0))
			paths.sort_custom(func(a: String, b: String) -> bool: return keys[a] > keys[b] or (keys[a] == keys[b] and a.naturalnocasecmp_to(b) < 0))
		_:
			paths.sort_custom(func(a: String, b: String) -> bool: return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	return paths


func _set_count(folders: int, files: int, reading := false) -> void:
	var parts := PackedStringArray()
	if folders > 0:
		parts.append("%d folder%s" % [folders, "" if folders == 1 else "s"])
	if files > 0:
		parts.append("%d file%s" % [files, "" if files == 1 else "s"])
	if reading:
		parts.append("reading…")
	count_label.text = "  ·  ".join(parts)


func _queue_item(path: String, is_dir: bool, title := "", context := "", icon_name := "") -> void:
	item_meta[path] = {"title": title, "context": context, "icon": icon_name}
	if is_dir:
		pending_folders.append(path)
	else:
		pending_media.append(path)


func _flush_items() -> void:
	folder_grid.set_items(pending_folders)
	media_grid.set_items(pending_media)
	listing = pending_media
	if radio_queue_active and Settings.library_source == Settings.LibrarySource.DISCOVER:
		_capture_radio_queue()
	pending_folders = PackedStringArray()
	pending_media = PackedStringArray()
	prioritize_timer = PRIORITIZE_DELAY


func _build_card(key: String, parent: VirtualGrid) -> Control:
	var card: Button = MediaCard.new()
	parent.add_child(card)
	var is_dir := parent == folder_grid
	var meta: Dictionary = item_meta.get(key, {})
	var scanned := meta.is_empty()
	var context: String = meta.get("context", "")
	if scanned and ((Settings.library_flat_view and Settings.library_source == Settings.LibrarySource.FOLDER) or not Settings.library_query.strip_edges().is_empty()):
		context = _relative_dir(key.get_base_dir())
	card.plain = _is_virtual(key)
	card.online_quality = meta.get("station", {})
	card.setup(key, is_dir, parent.layout, _click_allowed, meta.get("title", ""), context, meta.get("icon", ""), folder_covers.get(key, {}) if is_dir else {})
	if meta.has("station"):
		card.tooltip_text = meta["title"] + "\n" + meta["context"]
		card.star.toggled.connect(func(on: bool) -> void:
			if on and Library.is_favorite(key):
				discovery.Directory.remember(meta["station"])
			elif not on and discovery.saved and Settings.library_source == Settings.LibrarySource.DISCOVER:
				_refresh_saved_listing.call_deferred())
	card.activated.connect(_on_item_activated)
	card.toggled.connect(func(_on: bool) -> void: _highlight_current())
	cards[key] = card
	if is_dir and scanned and not folder_covers.has(key):
		scanner.cover(key)
	if not meta.has("station"):
		_track_cover(key, card)
	_sync_card_playback(card)
	return card


func _track_cover(key: String, card: Button) -> void:
	var media: String = card.media_path()
	if media.is_empty():
		return
	if media.get_extension().to_lower() in DISC_EXTENSIONS or media.get_extension().to_lower() in ArchiveFiles.ARCHIVE_EXTENSIONS:
		return
	MediaInfo.request(media)
	if media != key:
		cover_owner[media] = key


func _release_card(key: String, card: Control) -> void:
	if cards.get(key) == card:
		cards.erase(key)
	var media: String = card.media_path()
	if not media.is_empty():
		MediaInfo.forget(media)
		if cover_owner.get(media) == key:
			cover_owner.erase(media)


func set_favorite(path: String, on: bool) -> void:
	var card := _card_for(path)
	if on and card != null:
		Library.set_pref(path, "is_directory", card.is_dir and card.path == path)
	Library.set_favorite(path, on)
	if card != null:
		card.refresh()
	if path == _favorite_path():
		_refresh_favorite_button()
	if Settings.library_source == Settings.LibrarySource.FAVORITES:
		refresh_directory()


func _card_for(media: String) -> Button:
	if cards.has(media):
		return cards[media]
	return cards.get(cover_owner.get(media, ""))


func _is_virtual(path: String) -> bool:
	return path.begins_with("server:") or path.begins_with("dlna:") or path.begins_with("upnp:")


func _on_item_activated(path: String, is_dir: bool) -> void:
	cancel_disc_open()
	if path.get_extension().to_lower() in ArchiveFiles.ARCHIVE_EXTENSIONS:
		_open_archive(path)
		return
	disc_status = ""
	if path.get_extension().to_lower() == "iso" and not is_dir:
		open_media(path)
		return
	if _is_virtual(path):
		_on_network_item(path)
		return
	if path.begins_with("http://") or path.begins_with("https://"):
		var station: Dictionary = item_meta.get(path, {}).get("station", {})
		if not station.is_empty():
			if Settings.library_source == Settings.LibrarySource.DISCOVER:
				radio_queue_active = true
				_capture_radio_queue()
			discovery.Directory.remember(station)
			discovery.directory.count_play(station)
		if not radio_queue_active:
			_set_playlist(PackedStringArray([path]), path)
		open_media(path)
		return
	if network_titles.has(path):
		Library.set_pref(path, "title", network_titles[path])
	if is_dir:
		open_directory(path)
		return
	if (Settings.library_flat_view and Settings.library_source == Settings.LibrarySource.FOLDER) or path.get_extension().to_lower() in VPXPlayer.AUDIO_EXTENSIONS:
		_request_playlist(path)
	elif PanoramaFiles.is_image(path) and Settings.library_source == Settings.LibrarySource.FOLDER:
		var photos := PackedStringArray(Array(listing).filter(func(item: String) -> bool: return PanoramaFiles.is_image(item)))
		if photos.size() > 1 and path in photos:
			_set_playlist(photos, path)
		else:
			_request_playlist(path)
	else:
		_set_playlist(listing, path)
	open_media(path)


func cancel_disc_open() -> void:
	sacd_serial += 1
	sacd_path = ""
	sacd_info_cache = {}
	if sacd_popup != null:
		sacd_popup.hide()
	if is_instance_valid(disc_job):
		disc_job.cancel()
		disc_job = null
		if recovery != null and recovery.request_mode == "disc" and recovery.status == "opening":
			recovery.status = "cancelled"
			recovery.hide()


func _disc_current(job: DiscImage, serial: int) -> bool:
	return disc_job == job and serial == sacd_serial and not job.cancelled


func _finish_disc(job: DiscImage) -> void:
	if disc_job == job:
		disc_job = null
	job.queue_free()


func _open_disc(path: String, extra: Dictionary) -> void:
	var job := DiscImage.new()
	add_child(job)
	disc_job = job
	var serial := sacd_serial
	recovery.begin(path, extra, "disc")
	recovery.stage("Reading disc image…")
	var inspected := await job.inspect(path)
	if not _disc_current(job, serial):
		_finish_disc(job)
		return
	if not inspected.get("ok", false):
		_finish_disc(job)
		recovery.fail(inspected.get("error", "Could not read this ISO image"), "", "disc")
		return
	var info: Dictionary = inspected["info"]
	if info.get("ok", false):
		sacd_info_cache = info
		sacd_path = path
		sacd_popup.clear()
		if not Array(info.get("stereo", [])).is_empty():
			sacd_popup.add_item("Stereo (2-channel)", 0)
		if not Array(info.get("multichannel", [])).is_empty():
			sacd_popup.add_item("Multichannel", 1)
		_finish_disc(job)
		recovery.complete(false)
		sacd_popup.popup_centered()
		return
	if inspected["is_sacd"]:
		_finish_disc(job)
		recovery.fail(str(info.get("error", "Could not read SACD tracks")), "", "disc")
		return
	var options := extra.duplicate()
	options["input_format"] = "dvdvideo"
	var opened := await player.open(path, options)
	if not _disc_current(job, serial):
		_finish_disc(job)
		return
	if opened:
		_finish_disc(job)
		_set_playlist(PackedStringArray([path]), path)
		return
	recovery.stage("Mounting disc image…")
	var mounted := await job.mount(path)
	if not _disc_current(job, serial):
		_finish_disc(job)
		return
	_finish_disc(job)
	if mounted.get("ok", false):
		recovery.complete(false)
		_set_playlist(PackedStringArray(), "")
		open_directory(mounted["path"])
	else:
		recovery.fail(str(mounted.get("error", "Could not open this ISO image")), str(mounted.get("details", "")), "disc")


func _exit_tree() -> void:
	paths_serial += 1
	if is_instance_valid(paths_job):
		paths_job.cancel()
	cancel_disc_open()


func _on_archive_member_selected(id: int) -> void:
	if id < 0 or id >= archive_members.size() or archive_path.is_empty():
		return
	var uri := ArchiveFiles.stream_uri(archive_path, archive_members[id])
	_set_playlist(PackedStringArray([uri]), uri)
	open_media(uri)


func _open_archive(path: String) -> void:
	archive_path = path
	archive_members = ArchiveFiles.media_members(path)
	archive_popup.clear()
	for i in archive_members.size():
		archive_popup.add_item(archive_members[i].get_file(), i)
	if archive_members.is_empty():
		disc_status = "No playable media in this archive"
		refresh_directory()
	else:
		archive_popup.popup_centered(Vector2i(680, 720))


func _on_sacd_area_selected(id: int) -> void:
	if sacd_path.is_empty():
		return
	var path := sacd_path
	sacd_path = ""
	var info: Dictionary = sacd_info_cache
	sacd_info_cache = {}
	if not info.get("ok", false):
		disc_status = str(info.get("error", "Could not read SACD tracks"))
		refresh_directory()
		return
	var album := str(info.get("album", "SACD"))
	var area_name := "Multi-channel" if id == 1 else "Stereo"
	var tracks: PackedStringArray = []
	var entries: Array = info.get("multichannel" if id == 1 else "stereo", [])
	for entry in entries:
		var title := str(entry)
		var virtual_path := "/%s/%s/%s" % [album, area_name, title]
		tracks.append(DiscImage.sacd_track_uri(path, virtual_path, title))
	if tracks.is_empty():
		disc_status = "No tracks found in this SACD area"
		refresh_directory()
		return
	disc_status = ""
	_set_playlist(tracks, tracks[0])
	music_playlist = tracks
	music_playlist_index = LibraryScanner.index_of(tracks)
	music_shuffle = Shuffle.new()
	music_shuffle.sync(tracks, tracks[0])
	open_media(tracks[0], {"input_format": "dsf"})


func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Hint"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 160
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_list.add_child(label)


func _build_crumbs() -> void:
	for child in crumbs.get_children():
		crumbs.remove_child(child)
		child.queue_free()
	if Settings.library_source == Settings.LibrarySource.NETWORK and not dlna_stack.is_empty():
		var names: Array = ["Network"]
		for entry in dlna_stack:
			names.append(entry["name"])
		var first := maxi(names.size() - MAX_CRUMBS, 0)
		for i in range(first, names.size()):
			if i > first:
				var chevron := TextureRect.new()
				chevron.texture = VpxTheme.icon("chevron_right", 20)
				chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				chevron.custom_minimum_size = Vector2(22, 0)
				chevron.modulate = VpxTheme.FAINT
				crumbs.add_child(chevron)
			var crumb := Button.new()
			crumb.text = names[i]
			crumb.tooltip_text = "/".join(names.slice(0, i + 1))
			crumb.theme_type_variation = &"Crumb"
			crumb.focus_mode = FOCUS_NONE
			crumb.custom_minimum_size.y = 50
			_prepare_crumb(crumb, i == names.size() - 1)
			if i == names.size() - 1:
				crumb.add_theme_color_override("font_color", VpxTheme.TEXT)
			var depth := i
			crumb.pressed.connect(func() -> void:
				dlna_stack.resize(depth)
				refresh_directory())
			crumbs.add_child(crumb)
		return
	if Settings.library_source != Settings.LibrarySource.FOLDER:
		var label := Label.new()
		label.text = SOURCE_TITLES[Settings.library_source]
		label.add_theme_font_size_override("font_size", 24)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crumbs.add_child(label)
		return
	var root := _path_root(directory)
	var relative := directory.trim_prefix(root).trim_prefix("/")
	var parts := relative.split("/", false)
	var paths: Array[String] = []
	var names: Array[String] = []
	if OS.get_name() == "Windows":
		paths.append("")
		paths.append(root)
		names.append("Computer")
		names.append(root.trim_suffix("/"))
	else:
		paths.append(root)
		names.append("Computer")
	var home := PlatformPaths.home()
	for i in parts.size():
		var path := root.path_join("/".join(parts.slice(0, i + 1)))
		if OS.get_name() != "Windows" and path == home:
			paths = [path]
			names = ["Home"]
			continue
		paths.append(path)
		names.append(parts[i])
	var first := maxi(paths.size() - MAX_CRUMBS, 0)
	if first > 0:
		var ellipsis := _crumb("…", paths[first - 1])
		crumbs.add_child(ellipsis)
	for i in range(first, paths.size()):
		if i > first or first > 0:
			var chevron := TextureRect.new()
			chevron.texture = VpxTheme.icon("chevron_right", 20)
			chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			chevron.custom_minimum_size = Vector2(22, 0)
			chevron.modulate = VpxTheme.FAINT
			crumbs.add_child(chevron)
		var crumb := _crumb(names[i], paths[i], i == paths.size() - 1)
		if i == paths.size() - 1:
			crumb.add_theme_color_override("font_color", VpxTheme.TEXT)
		if i == first and names[i] == "Home":
			crumb.icon = VpxTheme.icon("home", 22)
		crumbs.add_child(crumb)


func _prepare_crumb(button: Button, is_last: bool) -> void:
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var font := get_theme_font("font", &"Crumb")
	var font_size := get_theme_font_size("font_size", &"Crumb")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon_width := 34.0 if button.icon != null or button.text == "Home" else 0.0
	button.custom_minimum_size.x = clampf(ceilf(text_width) + 24.0 + icon_width, 64.0, 320.0 if is_last else 240.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if is_last:
		button.add_theme_stylebox_override("normal", VpxTheme.accent_flat(10, 10, 6, &"soft"))


func _crumb(text: String, path: String, is_last := false) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = path if not path.is_empty() else "Computer"
	button.theme_type_variation = &"Crumb"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size.y = 50
	button.add_theme_constant_override("icon_max_width", 22)
	_prepare_crumb(button, is_last)
	if path.is_empty():
		button.pressed.connect(func() -> void: _select_source(Settings.LibrarySource.PLACES))
	else:
		button.pressed.connect(func() -> void: open_directory(path))
	return button


func _short_dir(path: String) -> String:
	var home := PlatformPaths.home()
	if not home.is_empty() and path.begins_with(home):
		return "~" + path.substr(home.length())
	return path


func _clean_directory(path: String) -> String:
	var clean := path.replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows" and clean.length() == 2 and clean[1] == ":":
		clean += "/"
	return clean


func _path_root(path: String) -> String:
	if OS.get_name() == "Windows" and path.begins_with("//"):
		var parts := path.split("/", false)
		if parts.size() >= 2:
			return "//%s/%s" % [parts[0], parts[1]]
	if OS.get_name() == "Windows" and path.length() >= 2 and path[1] == ":":
		return path.substr(0, 2).to_upper() + "/"
	return "/"


func _is_root(path: String) -> bool:
	return _clean_directory(path).trim_suffix("/") == _path_root(path).trim_suffix("/")


func _folder_fallbacks() -> PackedStringArray:
	var paths := PackedStringArray([OS.get_system_dir(OS.SYSTEM_DIR_MOVIES), PlatformPaths.home()])
	if OS.get_name() == "Windows":
		paths.append(OS.get_environment("SystemDrive") + "/")
	else:
		paths.append("/")
	return paths


func _visible_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var view := file_scroll.get_global_rect()
	for path: String in cards:
		var card: Button = cards[path]
		if not card.media_path().is_empty() and view.intersects(card.get_global_rect()):
			paths.append(card.media_path())
	return paths


func _make_focusable(node: Variant, recursive := true) -> void:
	if not is_instance_valid(node) or not node is Control or not (node == self or is_ancestor_of(node)):
		return
	var control := node as Control
	if keyboard != null and keyboard.is_ancestor_of(control):
		return
	var parent := control.get_parent()
	while parent != self and parent != null:
		if parent is MediaCard:
			return
		parent = parent.get_parent()
	if (control is BaseButton or (control is Range and not control is ScrollBar)) and control.focus_mode == FOCUS_NONE:
		control.focus_mode = FOCUS_ALL
	if recursive:
		for child in control.get_children():
			_make_focusable(child)


func handle_key(event: InputEventKey) -> bool:
	var modal_picker: Control
	var candidates: Array = [recovery.picker if recovery != null else null, backup_picker, quick.picker]
	for candidate: Variant in candidates:
		if is_instance_valid(candidate) and candidate.visible and not candidate.is_queued_for_deletion():
			modal_picker = candidate
			break
	if is_instance_valid(modal_picker) and modal_picker.visible and not modal_picker.is_queued_for_deletion():
		if not event.pressed:
			if forwarded_keys.erase(event.keycode):
				get_viewport().push_input(event)
		elif event.keycode == KEY_ESCAPE:
			modal_picker.cancel()
		else:
			modal_picker.contain_focus()
			_forward(event)
			if is_instance_valid(modal_picker) and modal_picker.visible and not modal_picker.is_queued_for_deletion():
				modal_picker.contain_focus()
		return true
	if recovery != null and recovery.visible:
		if event.pressed and event.keycode == KEY_ESCAPE:
			recovery.cancel()
		else:
			_forward(event)
		return true
	if not event.pressed:
		if forwarded_keys.erase(event.keycode):
			get_viewport().push_input(event)
			return true
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if keyboard != null and keyboard.visible:
		if event.keycode == KEY_ESCAPE:
			keyboard.cancel()
		elif event.keycode != KEY_TAB:
			_forward(event)
		return true
	if settings_search.visible:
		if event.keycode == KEY_ESCAPE:
			settings_search.close()
		else:
			_forward(event)
		return true
	if focus is LineEdit:
		if event.keycode == KEY_ESCAPE:
			focus.release_focus()
		else:
			_forward(event)
		return true
	var ctrl := event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_ESCAPE:
			if quick.visible:
				show_main()
				return true
			return false
		KEY_TAB when ctrl:
			step_page(-1 if event.shift_pressed else 1)
			return true
		KEY_BACKSPACE:
			if not %Library.visible or quick.visible:
				return false
			refocus_key = directory if Settings.library_source == Settings.LibrarySource.FOLDER else ""
			refocus = true
			_go_up()
			return true
		KEY_F when ctrl:
			if event.shift_pressed:
				settings_search.open(pages)
			else:
				show_library()
				_open_search()
			return true
		KEY_UP when ctrl:
			if focus is MediaCard and not focus.media_path().is_empty():
				set_favorite(focus.media_path(), not Library.is_favorite(focus.media_path()))
				return true
			return false
	if event.keycode not in NAV_KEYS or ctrl or event.alt_pressed:
		return false
	if focus == null or not focus.is_visible_in_tree():
		if not event.echo:
			_focus_start()
		return true
	if focus is MediaCard and _grid_key(focus, event):
		return true
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and focus is MediaCard and focus.is_dir and not focus.single:
		refocus_key = ""
		refocus = true
	_forward(event)
	return true


func _forward(event: InputEventKey) -> void:
	if event.pressed:
		forwarded_keys[event.keycode] = true
	else:
		forwarded_keys.erase(event.keycode)
	get_viewport().push_input(event)


func show_library() -> void:
	show_main()
	show_page(%Library)
	refocus_key = ""
	refocus = true


func step_page(direction: int) -> void:
	show_main()
	var current := 0
	for i in nav_buttons.size():
		if nav_buttons[i].button_pressed:
			current = i
	nav_buttons[wrapi(current + direction, 0, nav_buttons.size())].button_pressed = true
	refocus = %Library.visible
	if not refocus:
		_focus_start()


func _update_refocus() -> void:
	if recovery != null and recovery.visible:
		return
	if not refocus:
		return
	if not %Library.visible or quick.visible:
		refocus = false
		return
	var start := _library_start()
	if start != null:
		start.grab_focus()
		refocus = false


func _focus_start() -> void:
	if quick.visible:
		_first_focusable(quick)
		return
	if %Library.visible:
		var start := _library_start()
		if start != null:
			start.grab_focus()
			return
	for page in pages.get_children():
		if page.visible and _first_focusable(page):
			return
	_first_focusable(self)


func _first_focusable(root: Node) -> bool:
	for child in root.get_children():
		var control := child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.focus_mode == FOCUS_ALL:
			control.grab_focus()
			return true
		if _first_focusable(control):
			return true
	return false


func _library_start() -> Control:
	for grid: VirtualGrid in [folder_grid, media_grid]:
		if grid == null:
			continue
		var index := grid.items.find(refocus_key)
		if index < 0:
			index = grid.items.find(player.current_path)
		if index >= 0:
			return grid.control_at(index)
	for grid: VirtualGrid in [folder_grid, media_grid]:
		if grid != null and not grid.is_empty():
			return grid.first_built()
	return null


func _grid_key(card: Control, event: InputEventKey) -> bool:
	var grid := card.get_parent() as VirtualGrid
	if grid == null:
		return false
	var index := grid.index_of(card)
	var count := grid.items.size()
	var column := index % grid.columns
	var target := index
	match event.keycode:
		KEY_LEFT:
			target = maxi(index - 1, 0)
		KEY_RIGHT:
			target = mini(index + 1, count - 1)
		KEY_UP:
			target = index - grid.columns
		KEY_DOWN:
			target = index + grid.columns
		KEY_PAGEUP:
			target = maxi(index - grid.columns * grid.page_rows(), column)
		KEY_PAGEDOWN:
			target = index + grid.columns * grid.page_rows()
		KEY_HOME:
			target = 0
		KEY_END:
			target = count - 1
		_:
			return false
	var other := media_grid if grid == folder_grid else folder_grid
	if target < 0:
		if grid != media_grid or other == null or other.is_empty():
			return false
		var last_row := (other.items.size() - 1) / other.columns * other.columns
		other.control_at(mini(last_row + mini(column, other.columns - 1), other.items.size() - 1)).grab_focus()
		return true
	if target >= count:
		var last_row_start := (count - 1) / grid.columns * grid.columns
		if index >= last_row_start and grid == folder_grid and other != null and not other.is_empty():
			other.control_at(mini(column, other.items.size() - 1)).grab_focus()
			return true
		target = count - 1
	grid.control_at(target).grab_focus()
	return true


func _click_allowed() -> bool:
	return not drag_active


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_position = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_held = event.pressed
	if not %Library.visible or settings_search.visible or keyboard.visible:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			var bar := file_scroll.get_v_scroll_bar()
			drag_armed = file_scroll.get_global_rect().has_point(button.position) and not (bar.visible and bar.get_global_rect().has_point(button.position))
			drag_active = false
			drag_origin = button.position
			drag_scroll_start = file_scroll.scroll_vertical
			drag_last_y = button.position.y
			drag_last_msec = Time.get_ticks_msec()
			drag_velocity = 0.0
			fling = 0.0
		elif drag_armed:
			drag_armed = false
			if drag_active:
				fling = drag_velocity if absf(drag_velocity) > FLING_MIN else 0.0
				fling_position = file_scroll.scroll_vertical
				_end_drag.call_deferred()
		return
	var motion := event as InputEventMouseMotion
	if motion == null or not drag_armed or (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	var offset := motion.position.y - drag_origin.y
	if not drag_active and absf(offset) > DRAG_THRESHOLD:
		drag_active = true
		drag_origin = motion.position
		drag_scroll_start = file_scroll.scroll_vertical
		offset = 0.0
	if drag_active:
		file_scroll.scroll_vertical = int(drag_scroll_start - offset)
		var now := Time.get_ticks_msec()
		var elapsed := maxf((now - drag_last_msec) / 1000.0, 0.001)
		drag_velocity = lerpf(drag_velocity, -(motion.position.y - drag_last_y) / elapsed, 0.5)
		drag_last_y = motion.position.y
		drag_last_msec = now


func _end_drag() -> void:
	drag_active = false
	_highlight_current()


func _update_fling(delta: float) -> void:
	if absf(fling) < FLING_MIN:
		fling = 0.0
		return
	var bar := file_scroll.get_v_scroll_bar()
	fling_position = clampf(fling_position + fling * delta, 0.0, maxf(bar.max_value - bar.page, 0.0))
	file_scroll.scroll_vertical = int(fling_position)
	fling *= exp(-FLING_DECAY * delta)


func _build_speed_control() -> void:
	speed_button = OptionButton.new()
	speed_button.name = "PlaybackSpeed"
	speed_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	speed_button.theme_type_variation = &"CompactOption"
	speed_button.custom_minimum_size = Vector2(120, 52)
	speed_button.tooltip_text = "Playback speed · 1× resets normal speed"
	speed_button.mouse_exited.connect(_dismiss_speed_tooltip)
	speed_button.get_popup().about_to_popup.connect(_dismiss_speed_tooltip)
	for speed: float in SPEEDS:
		speed_button.add_item("%.2f×" % speed)
	speed_button.item_selected.connect(func(index: int) -> void: Settings.apply("playback_speed", SPEEDS[index]))
	total_label.get_parent().add_child(speed_button)


func _dismiss_speed_tooltip() -> void:
	for child in speed_button.get_children():
		if child is PopupPanel and child.theme_type_variation == &"TooltipPanel":
			child.hide()
			child.queue_free()


func _network_feedback(message: String, busy: bool) -> void:
	network_status = message
	status_requested.emit(message, busy)
	if Settings.library_source == Settings.LibrarySource.NETWORK:
		refresh_directory()


func _build_media_rename() -> void:
	media_rename = load("res://scripts/media_rename.gd").new()
	media_rename.player = player
	media_rename.ui = self
	add_child(media_rename)
	var rows := Rows.section(pages.get_node("Format"), "Rename from current format")
	rename_name = LineEdit.new()
	rename_name.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	rename_name.placeholder_text = "Proposed filename"
	rows.add_child(rename_name)
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	var edit_name := _action_button("Edit name", "keyboard")
	edit_name.pressed.connect(func() -> void:
		keyboard_purpose = "rename_media"
		keyboard.open("Edit proposed filename", rename_name.text, "Keep format tags and extension"))
	actions.add_child(edit_name)
	rename_button = _action_button("Rename file", "format")
	rename_button.pressed.connect(func() -> void:
		rename_button.disabled = true
		var result: Dictionary = await media_rename.rename_current(rename_name.text)
		_refresh_rename()
		rename_status.text = ("Renamed: " + result.get("name", rename_name.text)) if result["ok"] else result["error"])
	actions.add_child(rename_button)
	var undo := _action_button("Undo rename", "reset")
	undo.pressed.connect(func() -> void:
		var result: Dictionary = await media_rename.undo()
		_refresh_rename()
		rename_status.text = "Rename undone" if result["ok"] else result["error"])
	actions.add_child(undo)
	rename_status = Rows.hint(rows, "")
	rename_name.text_changed.connect(_validate_rename_name)
	Rows.hint(rows, "Renames one local file and matching subtitle sidecars. Saved picture choices stay with the file; embedded metadata still takes precedence in other players.")
	player.opened.connect(func(_path: String) -> void: _refresh_rename())
	Settings.changed.connect(_refresh_rename)
	_refresh_rename()


func _validate_rename_name(text: String) -> void:
	if media_rename.busy:
		return
	var reason: String = media_rename.unsupported_reason(player.current_path)
	if not reason.is_empty():
		rename_button.disabled = true
		rename_status.text = reason
		return
	var result: Dictionary = media_rename.validate(player.current_path, text)
	rename_button.disabled = not result["ok"] or result.get("unchanged", false)
	rename_status.text = result.get("error", "Ready to rename" if not result.get("unchanged", false) else "Filename already matches this format")


func _refresh_rename() -> void:
	if media_rename.busy:
		return
	var proposal: Dictionary = media_rename.proposal()
	rename_name.text = proposal.get("name", "")
	rename_button.disabled = not proposal["ok"] or proposal.get("unchanged", false)
	rename_status.text = proposal.get("error", proposal.get("warning", "Tags encode projection and stereo layout; zoom, pan and picture corrections remain in VPX."))


func _build_view_profiles() -> void:
	var rows := Rows.section(pages.get_node("System"), "Viewing profiles")
	var controls = load("res://scripts/profile_controls.gd").new()
	controls.manager = true
	controls.name_requested.connect(func(renaming: bool) -> void:
		keyboard_purpose = "profile_rename" if renaming else "profile_save"
		var entry: Dictionary = Settings.profiles.find_entry(Settings.profiles.active)
		keyboard.open("Rename viewing profile" if renaming else "Save viewing profile", entry.get("name", "") if renaming else "", "Lying down · 3D viewing · Flat viewing"))
	rows.add_child(controls)


func _build_position_reset() -> void:
	var rows := Rows.section(pages.get_node("Angles"), "Picture position")
	var reset := _action_button("Reset picture position", "recenter")
	reset.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	reset.pressed.connect(reset_position_requested.emit)
	rows.add_child(reset)


func _build_spirit_level() -> void:
	var page := pages.get_node("Angles")
	var section := VBoxContainer.new()
	spirit_level_section = section
	section.add_theme_constant_override("separation", 10)
	page.add_child(section)
	page.move_child(section, 0)
	spirit_level = SpiritLevel.new()
	section.add_child(spirit_level)
	var reset := _action_button("Reset to Level", "angles")
	reset.theme_type_variation = &"Button"
	reset.custom_minimum_size.y = SettingRow.ROW_HEIGHT
	reset.pressed.connect(level_requested.emit)
	section.add_child(reset)
	Rows.toggle(Rows.section(pages.get_node("Controls"), "Spirit level"), "Show spirit level while dragging", &"show_level")
	Rows.toggle(pages.get_node("Controls/HandsGroup/Rows"), "Laser only on menus", &"laser_menu_only")


func _build_format_help() -> void:
	var rows := Rows.section(pages.get_node("Controls"), "Filename format guide")
	for example: Array in FormatDetector.FILENAME_EXAMPLES:
		Rows.hint(rows, "%s — %s" % [example[0], example[1]])
	Rows.hint(rows, "Use spaces, underscores, dots or dashes around tags. SBS / LR = side by side; OU / TB = top and bottom. RL / BT reverse the eyes. Saved file choices override detection; explicit media metadata overrides filename tags. Untagged files keep your manual session format. A renamed download cannot restore a projection that was flattened by the source.")



func _build_settings_backup() -> void:
	var rows := Rows.section(pages.get_node("System"), "Settings backup")
	var include := CheckButton.new()
	include.text = "Include library data"
	rows.add_child(include)
	var status := Rows.hint(rows, "Library data includes formats, bookmarks, favourites and resume positions. Passwords and generated caches are excluded. Import creates a rollback backup first.")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	for importing: bool in [false, true]:
		var button := _action_button("Import settings" if importing else "Export settings", "folder" if importing else "download")
		button.theme_type_variation = &"Button"
		button.custom_minimum_size.y = SettingRow.ROW_HEIGHT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
		button.pressed.connect(func() -> void:
			if is_instance_valid(backup_picker):
				return
			backup_picker = QuickPanel.SubtitleFilePicker.new()
			add_child(backup_picker)
			var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
			if directory.is_empty():
				directory = PlatformPaths.home()
			backup_picker.configure(directory, PackedStringArray(["*.cfg; VPX settings"]), "Import settings" if importing else "Export settings", "Import" if importing else "Save", not importing)
			if not importing:
				backup_picker.filename_field.text = "VPX-settings.cfg"
			backup_picker.file_selected.connect(func(path: String) -> void:
				if path.get_extension().to_lower() != "cfg":
					status.text = "Choose a .cfg settings file"
					backup_picker.queue_free()
					return
				var backup = load("res://scripts/settings_backup.gd")
				var result: Dictionary = backup.import_settings(path, include.button_pressed) if importing else backup.export_settings(path, include.button_pressed)
				status.text = ("Settings imported. Previous settings: %s" % result["backup"] if importing else "Settings exported: " + path) if result["ok"] else result["error"]
				if importing and result["ok"]:
					refresh_directory()
				backup_picker.queue_free())
			backup_picker.canceled.connect(backup_picker.queue_free))


func close_pickers() -> void:
	quick.close_picker()
	settings_search.close()
	if keyboard_purpose == "settings_search":
		keyboard.close()
	if is_instance_valid(backup_picker):
		backup_picker.cancel()


func _apply_accessibility() -> void:
	var viewport := get_viewport() as SubViewport
	if viewport == null:
		return
	var wanted := Vector2(1554, 960) if get_tree().root.use_xr else Vector2(1554, 960) / Settings.ui_size
	var changed := not wanted.is_equal_approx(accessibility_size) or not is_equal_approx(accessibility_text_size, Settings.text_size)
	if not changed:
		return
	accessibility_size = wanted
	accessibility_text_size = Settings.text_size
	viewport.size_2d_override = Vector2i(wanted)
	var columns := clampi(floori((wanted.x - 130.0) / (260.0 * Settings.text_size)), 3, GRID_COLUMNS)
	for grid in [folder_grid, media_grid]:
		if is_instance_valid(grid):
			if grid.layout != MediaCard.Layout.ROW:
				grid.columns = columns
			for card: MediaCard in grid.built.values():
				card.apply_text_size()
			grid._relayout()
	%PresetGrid.columns = mini(5, columns)
	volume_slider.custom_minimum_size.x = 90.0 if wanted.x < 1400.0 else 170.0
	end_label.visible = wanted.x >= 1400.0 and Settings.text_size <= 1.2
