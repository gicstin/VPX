extends Control

signal selected(page: Control, target: Control, heading: Control)
signal keyboard_requested

var field: LineEdit
var results: VBoxContainer
var status: Label
var entries: Array[Dictionary] = []
var pages: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	z_index = 90
	hide()
	var shade := ColorRect.new()
	shade.color = VpxTheme.SCRIM
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(1040, 680)
	frame.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.SURFACE, 22, 24, 20))
	center.add_child(frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	frame.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "Search settings"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size.y = 54
	close.pressed.connect(self.close)
	header.add_child(close)
	var input := HBoxContainer.new()
	body.add_child(input)
	field = LineEdit.new()
	field.placeholder_text = "Search settings, controls and actions"
	field.clear_button_enabled = true
	field.custom_minimum_size.y = 60
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.text_changed.connect(func(_text: String) -> void: _refresh())
	field.text_submitted.connect(func(_text: String) -> void: _focus_result())
	input.add_child(field)
	var keyboard := Button.new()
	keyboard.text = "Keyboard"
	keyboard.pressed.connect(func() -> void: keyboard_requested.emit())
	input.add_child(keyboard)
	status = Label.new()
	status.theme_type_variation = &"Hint"
	body.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	results = VBoxContainer.new()
	results.size_flags_horizontal = SIZE_EXPAND_FILL
	results.add_theme_constant_override("separation", 8)
	scroll.add_child(results)


func open(source: Control) -> void:
	pages = source
	entries.clear()
	for page: Control in pages.get_children():
		if page.name != "Library":
			_index(page, page)
	_refresh()
	show()
	field.grab_focus()


func close() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	hide()


func set_query(text: String) -> void:
	field.text = text
	field.caret_column = text.length()
	_refresh()


func _index(node: Node, page: Control) -> void:
	var children := node.get_children()
	for i in children.size():
		var child: Node = children[i]
		if child is Label and child.theme_type_variation == &"SectionTitle" and i + 1 < children.size():
			var target := children[i + 1] as Control
			if target != null:
				var terms := _terms(target, true)
				var title: String = child.text.capitalize()
				entries.append({"page": page, "target": target, "heading": child, "title": title, "summary": _terms(target), "text": _normalize(str(page.get_meta("settings_path", page.name)) + " " + str(page.name) + " " + title + " " + terms)})
		_index(child, page)


func _terms(node: Node, include_keys := false) -> String:
	var parts := PackedStringArray()
	if node is SettingRow:
		parts.append(node.title)
		if include_keys:
			parts.append(String(node.setting).replace("_", " "))
			if node is Choice or node is Dropdown:
				parts.append(" ".join(node.options))
		return " ".join(parts)
	elif node is Label or node is BaseButton:
		parts.append(node.text)
	for child in node.get_children():
		var text := _terms(child, include_keys)
		if not text.is_empty():
			parts.append(text)
	return (" " if include_keys else " · ").join(parts)


func _normalize(text: String) -> String:
	return text.to_lower().replace("colour", "color").replace("favourite", "favorite").replace("visualiser", "visualizer").replace("\n", " ")


func _available(target: Control, page: Control) -> bool:
	var node := target
	while node != page:
		if not node.visible:
			return false
		node = node.get_parent() as Control
	return true


func _matching_target(node: Control, words: PackedStringArray) -> Control:
	if node is SettingRow or node is BaseButton:
		var text := _normalize(_terms(node, true))
		var matches := true
		for word in words:
			if not word in text:
				matches = false
				break
		if matches:
			return node
	for child in node.get_children():
		if child is Control:
			var target := _matching_target(child, words)
			if target != null:
				return target
	return null


func _refresh() -> void:
	for child in results.get_children():
		results.remove_child(child)
		child.queue_free()
	var words := _normalize(field.text).split(" ", false)
	var count := 0
	for entry in entries:
		var matches := true
		for word in words:
			if not word in entry["text"]:
				matches = false
				break
		if not matches:
			continue
		var page: Control = entry["page"]
		var target: Control = entry["target"]
		var heading: Control = entry["heading"]
		var context := _normalize(str(page.get_meta("settings_path", page.name)) + " " + str(page.name) + " " + entry["title"])
		var target_words := PackedStringArray()
		for word in words:
			if not word in context:
				target_words.append(word)
		if not target_words.is_empty():
			var match_target := _matching_target(target, target_words)
			if match_target != null:
				target = match_target
				heading = match_target
		var available := _available(target, page)
		var button := Button.new()
		button.text = "%s › %s\n%s" % [page.get_meta("settings_path", page.name), entry["title"], entry["summary"] if available else "Available with matching media or settings"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size.y = 88
		button.disabled = not available
		button.pressed.connect(func() -> void:
			close()
			selected.emit(page, target, heading))
		results.add_child(button)
		count += 1
	status.text = "%d %s · select a result to open its settings" % [count, "section" if count == 1 else "sections"] if count else "No matching settings. Try another word."


func _focus_result() -> void:
	for button: Button in results.get_children():
		if not button.disabled:
			button.grab_focus()
			return
