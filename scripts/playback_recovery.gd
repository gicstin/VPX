extends Control

const REVEAL_DELAY := 0.25
const Network := preload("res://scripts/network.gd")
const WebVideo := preload("res://scripts/web_video.gd")
const QuickPanel := preload("res://scripts/quick_panel.gd")

var ui: Control
var player: VPXPlayer
var source := ""
var options := {}
var status := ""
var kind := ""
var elapsed := 0.0
var generation := 0
var title: Label
var filename: Label
var message: Label
var progress: ProgressBar
var actions: HFlowContainer
var retry_button: Button
var fix_button: Button
var cancel_button: Button
var details_button: Button
var details: Label
var picker: Control
var request_mode := "media"
var mount_source := ""
var previous_focus: WeakRef


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	z_index = 100
	hide()
	var shade := ColorRect.new()
	shade.color = VpxTheme.SCRIM
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.SURFACE, 22, 28, 24))
	margin.add_child(frame)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	frame.add_child(rows)
	title = _label(rows, &"Title")
	filename = _label(rows, &"Caption")
	filename.max_lines_visible = 2
	filename.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message = _label(rows)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.indeterminate = true
	progress.custom_minimum_size.y = 8
	rows.add_child(progress)
	actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 10)
	rows.add_child(actions)
	retry_button = _button("Retry", retry)
	fix_button = _button("", _fix)
	cancel_button = _button("Cancel", cancel)
	details_button = _button("Show details", func() -> void:
		details.visible = not details.visible
		details_button.text = "Hide details" if details.visible else "Show details")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	rows.add_child(scroll)
	details = _label(scroll, &"Hint")
	details.size_flags_horizontal = SIZE_EXPAND_FILL
	details.visibility_changed.connect(func() -> void: scroll.visible = details.visible)
	details.hide()
	player.load_changed.connect(_on_load_changed)


func _label(parent: Node, variation := &"") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 60
	button.pressed.connect(callback)
	actions.add_child(button)
	return button


func begin(path: String, extra := {}, mode := "media") -> void:
	generation += 1
	source = path
	options = extra.duplicate(true)
	if WebVideo.needs_resolve(path):
		for key in ["stream", "audio", "headers"]:
			options.erase(key)
	request_mode = mode
	status = "opening"
	kind = ""
	elapsed = 0.0
	title.text = "Opening media"
	filename.text = safe_source(path)
	message.text = "Opening media…"
	progress.show()
	retry_button.hide()
	fix_button.hide()
	cancel_button.text = "Cancel"
	details_button.hide()
	details_button.text = "Show details"
	details.hide()
	_focus_actions()
	if visible:
		cancel_button.grab_focus()


func stage(text: String) -> void:
	message.text = text


func fail(text: String, technical := "", failure_kind := "decode") -> void:
	status = "failed"
	kind = failure_kind
	title.text = "Could not open media"
	message.text = text
	details.text = safe_text(technical)
	progress.hide()
	retry_button.show()
	cancel_button.text = "Back to Library"
	details_button.visible = not details.text.is_empty()
	fix_button.hide()
	match kind:
		"missing":
			fix_button.text = "Locate file"
			fix_button.show()
		"decode":
			var extension := source.get_extension().to_lower()
			if extension in ui.VIDEO_EXTENSIONS and not bool(options.get("software", false)):
				fix_button.text = "Try software decoding"
				fix_button.show()
		"tools":
			fix_button.text = "Open Apps & web"
			fix_button.show()
		"connection":
			fix_button.text = "Edit link" if source.begins_with("http") else "Network sources"
			fix_button.show()
	_focus_actions()
	_reveal()
	retry_button.grab_focus()


func complete(playing := true) -> void:
	status = "ready"
	_restore_focus()
	hide()
	if playing:
		ui.recovery_finished.emit()


func _on_load_changed(state: Dictionary) -> void:
	match state.get("status", ""):
		"opening":
			if source != state["path"] or status != "opening":
				begin(state["path"], state.get("options", {}))
			stage(state.get("stage", "Opening media…"))
		"buffering":
			if status != "opening":
				begin(state["path"], state.get("options", {}))
			title.text = "Buffering media"
			stage("Waiting for the stream to continue…")
		"failed":
			if request_mode == "disc" and is_instance_valid(ui.disc_job):
				return
			if source != state["path"]:
				begin(state["path"], state.get("options", {}))
			fail(state["message"], state.get("details", ""), state.get("kind", "decode"))
		"ready":
			complete()
		"cancelled":
			status = "cancelled"
			_restore_focus()
			hide()


func _process(delta: float) -> void:
	if status != "opening":
		return
	elapsed += delta
	if elapsed >= REVEAL_DELAY and not visible:
		_reveal()
		cancel_button.grab_focus()


func _reveal() -> void:
	if not visible:
		var focus := get_viewport().gui_get_focus_owner()
		previous_focus = weakref(focus) if focus != null else null
		ui.close_pickers()
		ui.keyboard.close()
		show()
	ui.recovery_requested.emit()


func _focus_actions() -> void:
	var buttons: Array[Control] = []
	for button: Control in actions.get_children():
		if button.visible:
			buttons.append(button)
	for i in buttons.size():
		var button := buttons[i]
		var previous := button.get_path_to(buttons[wrapi(i - 1, 0, buttons.size())])
		var next := button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_previous = previous
		button.focus_next = next
		button.focus_neighbor_left = previous
		button.focus_neighbor_right = next
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = next


func _restore_focus() -> void:
	if previous_focus == null:
		return
	var focus := previous_focus.get_ref() as Control
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()
	previous_focus = null


func cancel() -> void:
	generation += 1
	ui.cancel_disc_open()
	mount_source = ""
	ui.resolving_path = ""
	ui.web.cancel()
	ui.network.cancel_mount()
	player.cancel_open()
	status = "cancelled"
	if is_instance_valid(picker):
		picker.cancel()
	_restore_focus()
	hide()
	ui.show_library()


func retry() -> void:
	if request_mode == "share":
		ui._connect_share(source)
	else:
		ui.open_media(source, options)


func _fix() -> void:
	match kind:
		"missing":
			_locate()
		"decode":
			options["software"] = true
			retry()
		"tools":
			hide()
			ui.show_page(ui.pages.get_node("System"))
			ui.settings_search.open(ui.pages)
			ui.settings_search.set_query("Apps & web")
		"connection":
			hide()
			if source.begins_with("http"):
				ui.keyboard_purpose = "link"
				ui.keyboard.open("Edit media link", source, "https://…")
			else:
				ui.show_library()
				ui._select_source(Settings.LibrarySource.NETWORK)


func _locate() -> void:
	if is_instance_valid(picker):
		return
	picker = QuickPanel.SubtitleFilePicker.new()
	var directory := source.get_base_dir()
	if directory.is_empty() or directory.contains("://"):
		directory = ui.directory
	picker.configure(directory, PackedStringArray(), "Locate media file", "Open file")
	picker.z_index = 105
	ui.add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		var selected_picker := picker
		picker = null
		selected_picker.queue_free()
		var old_source := source
		if Library.entries.has(old_source) and not Library.entries.has(path):
			Library.rekey_paths({old_source: path})
		ui.open_directory(path.get_base_dir())
		ui.open_media(path, options))
	picker.canceled.connect(func() -> void:
		picker.queue_free()
		picker = null
		fix_button.grab_focus())


static func safe_source(path: String) -> String:
	if not path.contains("://"):
		return path
	return Network.strip_password(path).get_slice("?", 0).get_slice("#", 0)


static func safe_text(text: String) -> String:
	var pattern := RegEx.create_from_string("[A-Za-z][A-Za-z0-9+.-]*://[^\\s]+")
	var matches := pattern.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var found := matches[i]
		text = text.substr(0, found.get_start()) + safe_source(found.get_string()) + text.substr(found.get_end())
	return text
