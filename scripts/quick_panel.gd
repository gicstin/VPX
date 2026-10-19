extends PanelContainer

signal bookmark_name_requested(text: String)
signal menu_requested
signal close_requested
signal recenter_requested
signal reset_position_requested
signal level_requested

const PANEL_SIZE := Vector2(1120, 640)
const BOTTOM_MARGIN := 18.0
const TAB_HEIGHT := 52
const TRACK_HEIGHT := 56
const BACKGROUND_ALPHA := VpxTheme.OVERLAY_ALPHA
const TABS := [["Screen", "screen"], ["Picture", "picture"], ["Format", "format"], ["Audio", "audio"], ["Subtitles", "subtitles"], ["Marks", "bookmark"]]
const PICTURE_SETTINGS := ["brightness", "gamma", "saturation", "sharpness_level"]
const SCREEN_SETTINGS := ["screen_size", "screen_curve", "edge_fade"]
const Rows := preload("res://scripts/rows.gd")
const Languages := preload("res://scripts/languages.gd")
const MediaTracks := preload("res://scripts/media_tracks.gd")

var player: VPXPlayer
var tab_group := ButtonGroup.new()
var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var scroll: ScrollContainer
var audio_list: VBoxContainer
var subtitle_list: VBoxContainer
var subtitle_import_status: Label
var subtitle_query := ""
var subtitle_settings: Control
var preset_buttons: Array[Button] = []
var flat_rows: Array[Control] = []
var immersive_rows: Array[Control] = []
var screen_hint: Label
var current_tab := 0
var sleep_hint: Label
var loop_button: Button
var loop_clear: Button
var bookmark_editor: VBoxContainer
var bookmark_name_field: LineEdit
var bookmark_presets: OptionButton
var bookmark_edit_time := -1.0
var bookmark_edit_path := ""
var bookmark_list: VBoxContainer
var chapter_list: VBoxContainer
var shown_chapter := -2
var picker: SubtitleFilePicker
var spirit_level: SpiritLevel
var level_button: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", VpxTheme.flat(Color(VpxTheme.SURFACE, BACKGROUND_ALPHA), 26, 22, 16))
	custom_minimum_size = PANEL_SIZE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -PANEL_SIZE.x * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y - BOTTOM_MARGIN
	offset_bottom = -BOTTOM_MARGIN
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	layout.add_child(_build_header())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_right", 14)
	scroll.add_child(stack)
	for builder in [_build_screen, _build_picture, _build_format, _build_audio, _build_subtitles, _build_marks]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		stack.add_child(page)
		builder.call(page)
		pages.append(page)
	player.tracks.changed.connect(_rebuild_tracks)
	player.marks_changed.connect(_rebuild_marks)
	Settings.changed.connect(_sync)
	player.opened.connect(func(_path: String) -> void: _sync())
	player.music_changed.connect(_sync)
	_rebuild_tracks()
	_rebuild_marks()
	_sync()
	show_tab(0)


func _build_header() -> Control:
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 8)
	header.add_theme_constant_override("v_separation", 8)
	var tabs := PanelContainer.new()
	tabs.theme_type_variation = &"Segment"
	header.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	tabs.add_child(row)
	for i in TABS.size():
		var button := Button.new()
		button.text = TABS[i][0]
		button.icon = VpxTheme.icon(TABS[i][1], 24)
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_group = tab_group
		button.focus_mode = FOCUS_NONE
		button.custom_minimum_size.y = TAB_HEIGHT
		button.toggled.connect(func(on: bool) -> void:
			if on:
				show_tab(i))
		row.add_child(button)
		tab_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)
	var menu := _header_button("Menu", "library")
	menu.pressed.connect(menu_requested.emit)
	header.add_child(menu)
	var close := _header_button("", "close")
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	return header


func _header_button(text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = VpxTheme.icon(icon_name, 26)
	button.theme_type_variation = &"Chip"
	button.focus_mode = FOCUS_NONE
	button.custom_minimum_size = Vector2(TAB_HEIGHT, TAB_HEIGHT)
	return button


func show_tab(index: int) -> void:
	current_tab = index
	scroll.scroll_vertical = 0
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].set_pressed_no_signal(i == index)


func _build_screen(page: VBoxContainer) -> void:
	page.add_child(load("res://scripts/profile_controls.gd").new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	page.add_child(actions)
	var center := _action("Center screen here", "recenter")
	center.pressed.connect(recenter_requested.emit)
	actions.add_child(center)
	var reset := _action("Reset picture position", "reset")
	reset.pressed.connect(reset_position_requested.emit)
	actions.add_child(reset)
	spirit_level = SpiritLevel.new()
	page.add_child(spirit_level)
	var level := _action("Reset to Level", "angles")
	level_button = level
	level.pressed.connect(level_requested.emit)
	page.add_child(level)
	page.add_child(_reset_button("Reset screen settings", SCREEN_SETTINGS))
	var rows := Rows.section(page, "Flat screen")
	flat_rows.append(Rows.stepper(rows, "Size", &"screen_size", 20.0, 140.0, 5.0, {"suffix": "°"}))
	flat_rows.append(Rows.stepper(rows, "Curve", &"screen_curve", 0.0, 1.0, 0.05, {"fast_step": 0.25, "scale": 100.0, "suffix": "%"}))
	screen_hint = Rows.hint(rows, "Size and curve apply to flat videos. This video is immersive.")
	var view := Rows.section(page, "View")
	Rows.stepper(view, "Edge fade", &"edge_fade", 0.0, 0.4, 0.01, {"fast_step": 0.05, "scale": 100.0, "suffix": "%"})
	flat_rows.append(Rows.toggle(view, "Pan flat videos with grip / mouse", &"flat_video_pan"))
	Rows.toggle(view, "Lock horizon", &"lock_horizon")
	Rows.toggle(view, "Show spirit level while dragging", &"show_level")
	immersive_rows.append(Rows.stepper(view, "Look-around boost", &"look_gain", 1.0, 2.5, 0.25, {"decimals": 2, "suffix": "×", "resettable": true}))
	Rows.toggle(view, "Recenter when opening media", &"face_on_open")


func _build_picture(page: VBoxContainer) -> void:
	var rows := Rows.section(page, "Colour")
	Rows.stepper(rows, "Brightness", &"brightness", 0.2, 2.0, 0.05, {"scale": 100.0, "suffix": "%"})
	Rows.stepper(rows, "Gamma", &"gamma", 0.4, 2.2, 0.1, {"decimals": 1})
	Rows.stepper(rows, "Saturation", &"saturation", 0.0, 2.0, 0.05, {"scale": 100.0, "suffix": "%"})
	Rows.choice(rows, "Sharpness", &"sharpness_level", PackedStringArray(["Off", "Low", "Med", "High", "Extra", "Max"]))
	page.add_child(_reset_button("Reset picture", PICTURE_SETTINGS))


func _build_format(page: VBoxContainer) -> void:
	var rows := Rows.section(page, "Format")
	var grid := GridContainer.new()
	grid.columns = 5
	Settings.changed.connect(func() -> void: grid.columns = 3 if Settings.text_size > 1.1 else 5)
	grid.columns = 3 if Settings.text_size > 1.1 else 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	rows.add_child(grid)
	for i in Settings.FORMAT_PRESETS.size():
		var button := Button.new()
		button.text = Settings.FORMAT_PRESETS[i][0]
		button.toggle_mode = true
		button.focus_mode = FOCUS_NONE
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = TRACK_HEIGHT
		button.pressed.connect(func() -> void:
			Settings.select_format(Settings.FORMAT_PRESETS[i][1], Settings.FORMAT_PRESETS[i][2]))
		grid.add_child(button)
		preset_buttons.append(button)
	Rows.toggle(rows, "Swap eyes", &"swap_eyes")
	Rows.toggle(rows, "Detect format from file name", &"auto_detect")
	Rows.view_adjust(page)


func _build_audio(page: VBoxContainer) -> void:
	sleep_hint = Rows.hint(Rows.playback(page), "")
	var tracks := Rows.section(page, "Audio track")
	audio_list = VBoxContainer.new()
	audio_list.add_theme_constant_override("separation", 4)
	tracks.add_child(audio_list)
	var sync := Rows.section(page, "Sync")
	Rows.stepper(sync, "Audio delay", &"audio_delay", -2.0, 2.0, 0.05, {"fast_step": 0.25, "scale": 1000.0, "suffix": " ms", "resettable": true})
	Rows.hint(sync, "Positive delays the sound, negative plays it earlier. Saved for this video.")


func _build_subtitles(page: VBoxContainer) -> void:
	var tracks := Rows.section(page, "Subtitle track")
	var import_buttons := HFlowContainer.new()
	import_buttons.add_theme_constant_override("h_separation", 8)
	import_buttons.add_theme_constant_override("v_separation", 8)
	tracks.add_child(import_buttons)
	var add_file := _action("Choose subtitle file", "subtitles")
	add_file.pressed.connect(_choose_subtitle_file)
	import_buttons.add_child(add_file)
	var add_archive := _action("Choose ZIP / RAR / 7z archive", "folder")
	add_archive.pressed.connect(_choose_subtitle_archive)
	import_buttons.add_child(add_archive)
	subtitle_import_status = Rows.hint(tracks, "Choose a file or archive from any location. Imported subtitles and your selection are remembered for this video.")
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	tracks.add_child(filter_row)
	var filter := LineEdit.new()
	filter.placeholder_text = "Search languages"
	filter.size_flags_horizontal = SIZE_EXPAND_FILL
	filter.custom_minimum_size.y = TAB_HEIGHT
	filter.text_changed.connect(func(text: String) -> void:
		subtitle_query = text
		_rebuild_tracks())
	filter_row.add_child(filter)
	var jump_top := _action("Top", "up")
	jump_top.size_flags_horizontal = SIZE_SHRINK_END
	jump_top.pressed.connect(func() -> void: scroll.scroll_vertical = 0)
	filter_row.add_child(jump_top)
	var jump_style := _action("Style", "subtitles")
	jump_style.size_flags_horizontal = SIZE_SHRINK_END
	jump_style.pressed.connect(func() -> void: _scroll_to(subtitle_settings))
	filter_row.add_child(jump_style)
	subtitle_list = VBoxContainer.new()
	subtitle_list.add_theme_constant_override("separation", 4)
	tracks.add_child(subtitle_list)
	var timing := Rows.section(page, "Timing")
	subtitle_settings = timing.get_parent()
	Rows.stepper(timing, "Subtitle delay", &"subtitle_delay", -30.0, 30.0, 0.1, {"fast_step": 1.0, "decimals": 1, "suffix": " s", "resettable": true})
	var style := Rows.section(page, "Style")
	Rows.stepper(style, "Size", &"subtitle_size", 0.5, 2.5, 0.1, {"scale": 100.0, "suffix": "%"})
	var save_size := _action("Save size for this format", "check")
	save_size.pressed.connect(func() -> void:
		var sizes: Dictionary = Settings.subtitle_size_by_format.duplicate()
		sizes["%d:%d" % [Settings.projection, Settings.stereo]] = Settings.subtitle_size
		Settings.apply("subtitle_size_by_format", sizes))
	style.add_child(save_size)
	Rows.stepper(style, "Position", &"subtitle_offset", -0.4, 0.5, 0.02, {"scale": 100.0, "suffix": "%"})
	Rows.choice(style, "Colour", &"subtitle_color", PackedStringArray(["White", "Yellow", "Grey"]))
	Rows.toggle(style, "Background box", &"subtitle_box")
	immersive_rows.append(Rows.stepper(style, "Distance (180 / 360)", &"subtitle_distance", 1.0, 8.0, 0.25, {"decimals": 2, "suffix": " m"}))


func _build_marks(page: VBoxContainer) -> void:
	var marks := Rows.section(page, "Bookmarks & loop")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	marks.add_child(actions)
	var add := _action("Add bookmark", "bookmark")
	add.pressed.connect(func() -> void:
		var time := player.add_bookmark()
		if time >= 0.0:
			_edit_bookmark(time))
	actions.add_child(add)
	loop_button = _action("Loop: set A", "loop")
	loop_button.pressed.connect(player.set_loop_point)
	actions.add_child(loop_button)
	loop_clear = _action("Clear loop", "close")
	loop_clear.pressed.connect(player.clear_loop)
	actions.add_child(loop_clear)
	bookmark_editor = VBoxContainer.new()
	bookmark_editor.visible = false
	marks.add_child(bookmark_editor)
	bookmark_name_field = LineEdit.new()
	bookmark_name_field.placeholder_text = "Bookmark name (optional)"
	bookmark_name_field.max_length = VPXPlayer.BOOKMARK_NAME_MAX
	bookmark_name_field.custom_minimum_size.y = TRACK_HEIGHT
	bookmark_name_field.text_submitted.connect(func(_text: String) -> void: _save_bookmark_name())
	bookmark_editor.add_child(bookmark_name_field)
	bookmark_presets = OptionButton.new()
	bookmark_presets.fit_to_longest_item = false
	bookmark_presets.clip_text = true
	bookmark_presets.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	bookmark_presets.custom_minimum_size.y = TRACK_HEIGHT
	bookmark_presets.item_selected.connect(func(index: int) -> void:
		if index > 0:
			bookmark_name_field.text = bookmark_presets.get_item_text(index))
	bookmark_editor.add_child(bookmark_presets)
	var edit_actions := HBoxContainer.new()
	bookmark_editor.add_child(edit_actions)
	var keyboard := _action("Keyboard", "keyboard")
	keyboard.pressed.connect(func() -> void: bookmark_name_requested.emit(bookmark_name_field.text))
	edit_actions.add_child(keyboard)
	var save := _action("Save name", "check")
	save.pressed.connect(_save_bookmark_name)
	edit_actions.add_child(save)
	var cancel := _action("Cancel", "close")
	cancel.pressed.connect(func() -> void: bookmark_editor.hide())
	edit_actions.add_child(cancel)
	bookmark_list = VBoxContainer.new()
	bookmark_list.add_theme_constant_override("separation", 4)
	marks.add_child(bookmark_list)
	var chapters := Rows.section(page, "Chapters")
	chapter_list = VBoxContainer.new()
	chapter_list.add_theme_constant_override("separation", 4)
	chapters.add_child(chapter_list)


func _edit_bookmark(time: float) -> void:
	bookmark_edit_time = time
	bookmark_edit_path = player.bookmark_path()
	bookmark_name_field.text = player.bookmark_name(time)
	bookmark_presets.clear()
	bookmark_presets.add_item("Previous names")
	for title: String in player.bookmark_name_history():
		bookmark_presets.add_item(title)
	bookmark_presets.disabled = bookmark_presets.item_count == 1
	bookmark_editor.show()
	bookmark_name_field.grab_focus()


func set_bookmark_name_text(text: String) -> void:
	if bookmark_editor.visible and bookmark_edit_path == player.bookmark_path():
		bookmark_name_field.text = text.left(VPXPlayer.BOOKMARK_NAME_MAX)


func _save_bookmark_name() -> void:
	if bookmark_editor.visible and bookmark_edit_path == player.bookmark_path():
		if player.rename_bookmark(bookmark_edit_time, bookmark_name_field.text):
			bookmark_editor.hide()


func _action(text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = VpxTheme.icon(icon_name, 24)
	button.focus_mode = FOCUS_NONE
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.custom_minimum_size.y = TRACK_HEIGHT
	return button


func _rebuild_marks() -> void:
	if bookmark_list == null:
		return
	bookmark_editor.hide()
	if player.loop_a < 0.0:
		loop_button.text = "Loop: set A"
	elif player.loop_b < 0.0:
		loop_button.text = "Loop: set B (A %s)" % MediaInfo.duration_text(player.loop_a)
	else:
		loop_button.text = "Looping %s – %s" % [MediaInfo.duration_text(player.loop_a), MediaInfo.duration_text(player.loop_b)]
	loop_clear.disabled = player.loop_a < 0.0
	for child in bookmark_list.get_children():
		child.queue_free()
	var times := player.bookmarks()
	if times.is_empty():
		Rows.hint(bookmark_list, "No bookmarks in this video yet.")
	for time: float in times:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		bookmark_list.add_child(row)
		var jump := Button.new()
		var title := player.bookmark_name(time)
		jump.text = "%s   %s" % [MediaInfo.duration_text(time), title if not title.is_empty() else player.chapter_title(player.chapter_at(time))]
		jump.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		jump.tooltip_text = jump.text
		jump.icon = VpxTheme.icon("bookmark", 22)
		jump.theme_type_variation = &"Chip"
		jump.alignment = HORIZONTAL_ALIGNMENT_LEFT
		jump.focus_mode = FOCUS_NONE
		jump.size_flags_horizontal = SIZE_EXPAND_FILL
		jump.custom_minimum_size.y = TRACK_HEIGHT
		jump.pressed.connect(func() -> void: player.seek_to(time))
		row.add_child(jump)
		var rename := _header_button("Rename", "keyboard")
		rename.pressed.connect(func() -> void: _edit_bookmark(time))
		row.add_child(rename)
		var remove := _header_button("", "trash")
		remove.pressed.connect(func() -> void: player.remove_bookmark(time))
		row.add_child(remove)
	shown_chapter = -2
	_rebuild_chapters()


func _rebuild_chapters() -> void:
	var current := player.chapter_at(player.stream_position)
	if current == shown_chapter and chapter_list.get_child_count() > 0:
		return
	shown_chapter = current
	var entries := []
	for i in player.chapters.size():
		entries.append(["%s   %s" % [MediaInfo.duration_text(float(player.chapters[i]["start"])), player.chapter_title(i)], i])
	_fill_list(chapter_list, entries, current, func(index: int) -> void: player.seek_to(float(player.chapters[index]["start"])), "This video has no chapters.")


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	spirit_level.visible = SpiritLevel.applicable(player, Settings.projection == Settings.ProjectionMode.FLAT)
	level_button.visible = spirit_level.visible
	if current_tab == 5:
		_rebuild_chapters()
	if current_tab == 3 and sleep_hint != null:
		var left := player.sleep_remaining()
		sleep_hint.visible = true
		if Settings.sleep_timer == Settings.SleepTimer.END_OF_VIDEO:
			sleep_hint.text = "Pauses at the end of this video"
		elif left > 0.0:
			sleep_hint.text = "Pauses in %s" % MediaInfo.duration_text(left)
		else:
			sleep_hint.text = "Off. Shortest time is 15 minutes, and it pauses the sound too. A black picture while the sound keeps playing is not this timer."


func _reset_button(text: String, properties: Array) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = VpxTheme.icon("reset", 24)
	button.theme_type_variation = &"Chip"
	button.focus_mode = FOCUS_NONE
	button.size_flags_horizontal = SIZE_SHRINK_END
	button.custom_minimum_size.y = TAB_HEIGHT
	button.pressed.connect(func() -> void: Settings.reset(PackedStringArray(properties)))
	return button


func _rebuild_tracks() -> void:
	var tracks := player.tracks
	var audio := []
	for track in tracks.audio_tracks:
		audio.append([tracks.audio_label(track["index"]), track["index"]])
	if not audio.is_empty():
		audio.append(["Off", -1])
	_fill_list(audio_list, audio, tracks.audio_choice, func(value: int) -> void: tracks.select_audio(value), "No audio in this video")
	var query := subtitle_query.strip_edges().to_lower()
	var subtitles := [["Off", -1]]
	for i in tracks.subtitle_tracks.size():
		var label := tracks.subtitle_label(i)
		if not query.is_empty() and not query in label.to_lower():
			continue
		subtitles.append([label, i])
	_fill_list(subtitle_list, subtitles, tracks.subtitle_choice, func(value: int) -> void: tracks.select_subtitle(value), "")
	if tracks.subtitle_tracks.is_empty():
		Rows.hint(subtitle_list, "No subtitles loaded. Subtitles beside the video are also found automatically.")
	elif subtitles.size() == 1 and not query.is_empty():
		Rows.hint(subtitle_list, "No subtitle matches.")


func _choose_subtitle_file() -> void:
	_open_subtitle_picker(["*.srt,*.ass,*.ssa,*.vtt,*.sub,*.smi,*.sami,*.sup; Subtitle files"])


func _choose_subtitle_archive() -> void:
	_open_subtitle_picker(["*.zip,*.rar,*.7z,*.tar,*.gz,*.bz2,*.xz; Archives"])


func _open_subtitle_picker(filters: PackedStringArray) -> void:
	if is_instance_valid(picker) and not picker.is_queued_for_deletion():
		return
	var video_path := player.current_path
	var initial_directory := video_path.get_base_dir() if not video_path.is_empty() and not video_path.contains("://") else OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if initial_directory.is_empty():
		initial_directory = PlatformPaths.home()
	picker = SubtitleFilePicker.new()
	get_parent().add_child(picker)
	picker.configure(initial_directory, filters)
	Log.info("subtitle picker opened %s" % initial_directory)
	picker.file_selected.connect(func(file_path: String) -> void:
		Log.info("subtitle picker selected %s" % file_path)
		var extension := file_path.get_extension().to_lower()
		if extension in MediaTracks.SUBTITLE_EXTENSIONS:
			subtitle_import_status.text = "Subtitle selected and remembered for this video." if player.tracks.add_external_file(file_path) else "Could not load that subtitle file"
		else:
			var result: Dictionary = player.tracks.add_archive(file_path)
			subtitle_import_status.text = result["message"] + ". First subtitle selected and remembered for this video." if result["ok"] else result["message"]
		picker.queue_free())
	picker.canceled.connect(func() -> void:
		Log.info("subtitle picker canceled")
		picker.queue_free())


func has_picker() -> bool:
	return is_instance_valid(picker) and not picker.is_queued_for_deletion()


func close_picker() -> void:
	if has_picker():
		picker.cancel()


class SubtitleFilePicker extends Control:
	signal file_selected(file_path: String)
	signal canceled

	const BackgroundTask := preload("res://scripts/background_task.gd")
	const PICKER_SIZE := Vector2(1040, 680)
	var current_directory := ""
	var filters := PackedStringArray()
	var path_field: LineEdit
	var filename_field: LineEdit
	var filter_field: LineEdit
	var file_list: ItemList
	var folder_tree: Tree
	var status_label: Label
	var listed_folders := PackedStringArray()
	var listed_files := PackedStringArray()
	var pending_directory := ""
	var pending_selection := ""
	var focused_directory := ""
	var scan_generation := 0
	var scan_job: Node
	var path_job: Node
	var path_generation := 0
	var checking_directory := false
	var queued_accept := false
	var folder_parent: TreeItem
	var previous_focus: WeakRef
	var drives: Array[Dictionary] = []
	var folders: Array[Dictionary] = []
	var save_mode := false
	var overwrite_path := ""
	var picker_title := "Add subtitle"
	var accept_text := "Add subtitle"

	func configure(initial_directory: String, file_filters: PackedStringArray, dialog_title := "Add subtitle", dialog_accept := "Add subtitle", saving := false) -> void:
		current_directory = initial_directory
		filters = file_filters
		picker_title = dialog_title
		accept_text = dialog_accept
		save_mode = saving
		theme = VpxTheme.build()
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		z_index = 100
		var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		previous_focus = weakref(focus) if focus != null else null
		_register_drives()
		_build_picker()
		path_field.grab_focus.call_deferred()

	func _build_picker() -> void:
		var backdrop := ColorRect.new()
		backdrop.color = VpxTheme.SCRIM
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				cancel())
		add_child(backdrop)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var frame := PanelContainer.new()
		frame.custom_minimum_size = PICKER_SIZE
		frame.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.SURFACE, 22, 20, 14))
		center.add_child(frame)
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		frame.add_child(margin)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		margin.add_child(body)
		var header := HBoxContainer.new()
		body.add_child(header)
		var title_label := Label.new()
		title_label.text = picker_title
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title_label)
		var close := _button("Close", "close")
		close.pressed.connect(cancel)
		header.add_child(close)

		var toolbar := HBoxContainer.new()
		toolbar.add_theme_constant_override("separation", 8)
		body.add_child(toolbar)
		var back := _button("Back", "back")
		back.custom_minimum_size.x = 110
		back.pressed.connect(_go_parent)
		toolbar.add_child(back)
		var up := _button("Up", "up")
		up.pressed.connect(_go_parent)
		toolbar.add_child(up)
		path_field = LineEdit.new()
		path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		path_field.placeholder_text = "Folder path"
		path_field.text_changed.connect(func(_text: String) -> void: _cancel_path())
		path_field.text_submitted.connect(_open_path)
		toolbar.add_child(path_field)
		var go := _button("Go", "forward")
		go.tooltip_text = "Open the folder path above"
		go.custom_minimum_size.x = 76
		go.pressed.connect(func() -> void: _open_path(path_field.text))
		toolbar.add_child(go)
		filter_field = LineEdit.new()
		filter_field.placeholder_text = "Search"
		filter_field.custom_minimum_size.y = 54
		filter_field.text_changed.connect(func(text: String) -> void:
			_fill_file_list(text))
		body.add_child(filter_field)

		var content := HSplitContainer.new()
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.split_offset = 260
		body.add_child(content)
		folder_tree = Tree.new()
		folder_tree.custom_minimum_size.x = 240
		folder_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		folder_tree.hide_root = true
		folder_tree.item_selected.connect(_on_folder_selected)
		content.add_child(folder_tree)
		file_list = ItemList.new()
		file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		file_list.allow_reselect = true
		file_list.item_selected.connect(_on_file_selected)
		file_list.item_activated.connect(_on_file_activated)
		content.add_child(file_list)

		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 8)
		body.add_child(footer)
		filename_field = LineEdit.new()
		filename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filename_field.placeholder_text = "Selected file"
		filename_field.text_changed.connect(func(_text: String) -> void:
			overwrite_path = ""
			if not checking_directory:
				_cancel_path())
		filename_field.text_submitted.connect(func(_text: String) -> void: _accept_selection())
		footer.add_child(filename_field)
		status_label = Label.new()
		status_label.theme_type_variation = &"Hint"
		status_label.custom_minimum_size.x = 180
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		footer.add_child(status_label)
		var add_button := _button(accept_text, "check")
		add_button.theme_type_variation = &"PrimaryButton"
		add_button.custom_minimum_size.x = 150
		add_button.pressed.connect(_accept_selection)
		footer.add_child(add_button)
		_refresh()

	func _button(label: String, icon: String) -> Button:
		var button := Button.new()
		button.text = label
		button.icon = VpxTheme.icon(icon, 26)
		button.theme_type_variation = &"Button"
		button.custom_minimum_size.y = 54
		return button

	func _register_drives() -> void:
		for i in DirAccess.get_drive_count():
			var drive := DirAccess.get_drive_name(i)
			drives.append({"name": drive, "path": drive})

	func _refresh() -> void:
		overwrite_path = ""
		_cancel_path()
		var absolute := _absolute_path(current_directory)
		current_directory = absolute.trim_suffix("/") if absolute != "/" and not absolute.ends_with(":/") else absolute
		path_field.text = current_directory
		filter_field.text = ""
		status_label.text = "Loading…"
		listed_folders.clear()
		listed_files.clear()
		file_list.clear()
		folder_tree.clear()
		var root := folder_tree.create_item()
		var place := folder_tree.create_item(root)
		place.set_text(0, "Places")
		place.set_selectable(0, false)
		for drive in drives:
			var item := folder_tree.create_item(place)
			item.set_text(0, str(drive["name"]))
			item.set_metadata(0, drive["path"])
		var home := PlatformPaths.home()
		if not home.is_empty():
			var item := folder_tree.create_item(place)
			item.set_text(0, "Home")
			item.set_metadata(0, home)
		focused_directory = current_directory
		_build_folder_tree(current_directory)
		pending_directory = current_directory
		pending_selection = ""
		_scan_directory(current_directory)

	func _build_folder_tree(start_path: String) -> void:
		folders.clear()
		var components := start_path.split("/", false)
		var root_path := "//" if start_path.begins_with("//") else "/" if start_path.begins_with("/") else ""
		folder_parent = folder_tree.get_root().get_child(0)
		for component in components:
			root_path = root_path.path_join(component) if not root_path.is_empty() else component
			if root_path.ends_with(":"):
				root_path += "/"
			var item := folder_tree.create_item(folder_parent)
			item.set_text(0, component)
			item.set_metadata(0, root_path)
			folders.append({"path": root_path, "item": item})
			folder_parent = item
			if root_path == start_path:
				item.select(0)

	func _scan_directory(scan_path: String) -> void:
		scan_generation += 1
		if is_instance_valid(scan_job):
			scan_job.cancel()
		var generation := scan_generation
		scan_job = BackgroundTask.start(_scan_worker.bind(scan_path, filters))
		scan_job.completed.connect(func(result: Dictionary) -> void:
			if generation != scan_generation or not is_inside_tree() or not visible:
				return
			scan_job = null
			_apply_scan(result))

	static func _scan_worker(token: RefCounted, scan_path: String, file_filters: PackedStringArray) -> Dictionary:
		var folders_found := PackedStringArray()
		var files_found := PackedStringArray()
		if token.is_cancelled():
			return {"ok": false}
		var directory := DirAccess.open(scan_path)
		if directory == null or directory.list_dir_begin() != OK:
			return {"ok": false, "error": "Folder unavailable"}
		var entry := directory.get_next()
		while not entry.is_empty() and not token.is_cancelled():
			if not entry.begins_with("."):
				if directory.current_is_dir():
					folders_found.append(entry)
				elif _matches_filters(entry, file_filters):
					files_found.append(entry)
			entry = directory.get_next()
		directory.list_dir_end()
		folders_found.sort()
		files_found.sort()
		return {"ok": true, "folders": folders_found, "files": files_found}

	static func _matches_filters(file_name: String, file_filters: PackedStringArray) -> bool:
		if file_filters.is_empty():
			return true
		var extension := file_name.get_extension().to_lower()
		for filter in file_filters:
			var pattern := filter.get_slice(";", 0).strip_edges()
			for wildcard in pattern.split(","):
				var wanted := wildcard.strip_edges().trim_prefix("*.").to_lower()
				if extension == wanted:
					return true
		return false

	func _apply_scan(result: Dictionary) -> void:
		if not result.get("ok", false):
			status_label.text = result.get("error", "Could not read folder")
			return
		listed_folders = result["folders"]
		listed_files = result["files"]
		for child_name in listed_folders:
			var child := folder_tree.create_item(folder_parent)
			child.set_text(0, child_name)
			child.set_metadata(0, current_directory.path_join(child_name))
		_fill_file_list(filter_field.text)
		if not pending_selection.is_empty():
			for i in file_list.item_count:
				if file_list.get_item_text(i) == pending_selection.get_file():
					file_list.select(i)
					filename_field.text = pending_selection.get_file()
					break
		pending_selection = ""

	func _fill_file_list(query: String) -> void:
		file_list.clear()
		var needle := query.strip_edges().to_lower()
		var folders_shown := 0
		var files_shown := 0
		for folder in listed_folders:
			if not needle.is_empty() and not needle in folder.to_lower():
				continue
			var index := file_list.add_item(folder, VpxTheme.icon("folder", 30))
			file_list.set_item_metadata(index, "dir")
			folders_shown += 1
		for file_name in listed_files:
			if not needle.is_empty() and not needle in file_name.to_lower():
				continue
			var file_icon := "subtitles" if file_name.get_extension().to_lower() in MediaTracks.SUBTITLE_EXTENSIONS else "folder"
			var index := file_list.add_item(file_name, VpxTheme.icon(file_icon, 30))
			file_list.set_item_metadata(index, "file")
			files_shown += 1
		if status_label != null:
			status_label.text = "%d folders · %d files" % [folders_shown, files_shown]

	func _on_folder_selected() -> void:
		var item := folder_tree.get_selected()
		if item == null:
			return
		var selected_path := str(item.get_metadata(0))
		if selected_path.is_empty() or selected_path == focused_directory:
			return
		current_directory = selected_path
		_refresh()

	func _on_file_selected(index: int) -> void:
		overwrite_path = ""
		_cancel_path()
		if file_list.get_item_metadata(index) == "dir":
			var selected_directory := current_directory.path_join(file_list.get_item_text(index))
			current_directory = selected_directory
			_refresh()
			return
		filename_field.text = file_list.get_item_text(index)

	func _on_file_activated(index: int) -> void:
		if file_list.get_item_metadata(index) == "dir":
			current_directory = current_directory.path_join(file_list.get_item_text(index))
			_refresh()
		else:
			_accept_selection()

	func cancel() -> void:
		_close()
		canceled.emit()

	func _go_parent() -> void:
		var parent_path := current_directory.get_base_dir()
		if parent_path.is_empty():
			return
		current_directory = parent_path
		_refresh()

	func _open_path(value: String) -> void:
		_resolve_path(_absolute_path(value), false)

	func _accept_selection() -> void:
		if checking_directory and is_instance_valid(path_job):
			queued_accept = true
			return
		var name := filename_field.text.strip_edges()
		if name.is_empty():
			status_label.text = "Choose a filename"
			return
		_resolve_path(_absolute_path(name), true)

	func _resolve_path(selected_path: String, accepting: bool) -> void:
		_cancel_path()
		var generation := path_generation
		checking_directory = not accepting
		status_label.text = "Checking path…"
		path_job = BackgroundTask.start(_check_path.bind(selected_path, accepting, save_mode, filters))
		path_job.completed.connect(func(result: Dictionary) -> void:
			if generation != path_generation or not is_inside_tree() or not visible:
				return
			path_job = null
			checking_directory = false
			if not result.get("ok", false):
				status_label.text = result.get("error", "Path not found")
				return
			if result["directory"]:
				var accepting_after_navigation := queued_accept
				current_directory = selected_path
				_refresh()
				if accepting_after_navigation:
					_accept_selection()
				return
			if save_mode and result["exists"] and overwrite_path != selected_path:
				overwrite_path = selected_path
				filename_field.text = selected_path
				status_label.text = "Exists · press Save again to replace"
				return
			_emit_selected(selected_path))

	static func _check_path(token: RefCounted, selected_path: String, accepting: bool, saving: bool, file_filters: PackedStringArray) -> Dictionary:
		if token.is_cancelled():
			return {"ok": false}
		if DirAccess.dir_exists_absolute(selected_path):
			return {"ok": true, "directory": true}
		if token.is_cancelled():
			return {"ok": false}
		var exists := FileAccess.file_exists(selected_path)
		if token.is_cancelled():
			return {"ok": false}
		if saving and accepting:
			if not DirAccess.dir_exists_absolute(selected_path.get_base_dir()):
				return {"ok": false, "error": "Choose a writable folder"}
		elif not exists:
			return {"ok": false, "error": "Path not found"}
		if not _matches_filters(selected_path, file_filters):
			return {"ok": false, "error": "Select a matching file"}
		return {"ok": true, "directory": false, "exists": exists}

	func _emit_selected(selected_path: String) -> void:
		_close()
		file_selected.emit(selected_path)

	func _cancel_path() -> void:
		path_generation += 1
		checking_directory = false
		queued_accept = false
		if is_instance_valid(path_job):
			path_job.cancel()
		path_job = null

	func _cancel_jobs() -> void:
		scan_generation += 1
		if is_instance_valid(scan_job):
			scan_job.cancel()
		scan_job = null
		_cancel_path()

	func _close() -> void:
		_cancel_jobs()
		hide()
		var focus := previous_focus.get_ref() as Control if previous_focus != null else null
		if is_instance_valid(focus) and focus.is_visible_in_tree():
			focus.grab_focus()

	func contain_focus() -> void:
		var controls: Array[Control] = []
		_collect_focus(self, controls)
		if controls.is_empty():
			return
		for i in controls.size():
			controls[i].focus_previous = controls[i].get_path_to(controls[wrapi(i - 1, 0, controls.size())])
			controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not is_ancestor_of(focus):
			path_field.grab_focus()

	func _collect_focus(node: Node, controls: Array[Control]) -> void:
		for child in node.get_children():
			if child is Control and child.is_visible_in_tree():
				if child.focus_mode == Control.FOCUS_ALL and not (child is BaseButton and child.disabled):
					controls.append(child)
				_collect_focus(child, controls)

	func _absolute_path(value: String) -> String:
		var absolute := value
		if not absolute.is_absolute_path():
			absolute = current_directory.path_join(value)
		return absolute.simplify_path()

	func _exit_tree() -> void:
		_cancel_jobs()


func _scroll_to(target: Control) -> void:
	if target == null or scroll.get_child_count() == 0:
		return
	var content := scroll.get_child(0) as Control
	scroll.scroll_vertical = int(maxf(target.global_position.y - content.global_position.y, 0.0))


func _fill_list(list: VBoxContainer, entries: Array, selected: int, pick: Callable, empty_text: String) -> void:
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		Rows.hint(list, empty_text)
		return
	var group := ButtonGroup.new()
	for entry in entries:
		var button := Button.new()
		button.text = entry[0]
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size.y = TRACK_HEIGHT
		button.icon = VpxTheme.icon("check", 24) if entry[1] == selected else null
		button.set_pressed_no_signal(entry[1] == selected)
		var value: int = entry[1]
		button.pressed.connect(func() -> void: pick.call(value))
		list.add_child(button)


func _sync() -> void:
	spirit_level.visible = SpiritLevel.applicable(player, Settings.projection == Settings.ProjectionMode.FLAT)
	level_button.visible = spirit_level.visible
	var flat := Settings.projection == Settings.ProjectionMode.FLAT
	for row in flat_rows:
		row.visible = flat
	for row in immersive_rows:
		row.visible = not flat
	screen_hint.visible = not flat
	var matching := Settings.matching_preset()
	for i in preset_buttons.size():
		preset_buttons[i].set_pressed_no_signal(i == matching)
